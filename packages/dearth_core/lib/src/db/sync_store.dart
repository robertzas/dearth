import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../sync/merge.dart';
import '../sync/op.dart';
import '../sync/sync_specs.dart';
import 'database.dart';

class _TableMeta {
  _TableMeta(this.info) : types = {for (final c in info.$columns) c.name: c.type};
  final TableInfo<Table, Object?> info;
  final Map<String, Object> types;
}

/// Thrown for ops that reference unknown tables (programming or version error).
class UnknownTableException implements Exception {
  UnknownTableException(this.table);
  final String table;
  @override
  String toString() => 'UnknownTableException: $table';
}

/// Applies replicated ops to any synced table with field-level LWW merge
/// (SPEC §8.4). Used identically by devices and the Hub.
///
/// All SQL is dialect-neutral (`INSERT … ON CONFLICT … DO UPDATE`), so the
/// same code runs on SQLite and Postgres.
class SyncStore {
  SyncStore(this.db) {
    for (final t in db.allTables) {
      if (kSyncTables.containsKey(t.actualTableName)) {
        _tables[t.actualTableName] = _TableMeta(t);
      }
    }
  }

  final DearthDb db;
  final Map<String, _TableMeta> _tables = {};

  Iterable<String> get syncedTables => _tables.keys;
  bool isSynced(String table) => _tables.containsKey(table);
  Set<String> columnsOf(String table) => (_tables[table] ?? (throw UnknownTableException(table))).types.keys.toSet();
  TableInfo<Table, Object?> tableInfo(String table) =>
      (_tables[table] ?? (throw UnknownTableException(table))).info;

  /// Writable (non-system) columns of [table].
  bool isDataColumn(String table, String column) {
    final meta = _tables[table];
    return meta != null && meta.types.containsKey(column) && !kSyncSystemColumns.contains(column);
  }

  /// Applies [ops] in one transaction. Returns how many changed a row.
  Future<int> applyOps(Iterable<Op> ops, {int Function(Op op)? seqOf}) => db.transaction(() async {
        var changed = 0;
        for (final op in ops) {
          if (await applyOp(op, seq: seqOf?.call(op) ?? 0)) changed++;
        }
        return changed;
      });

  /// Applies one op. Returns true when at least one field changed.
  /// Unknown columns are ignored (forward compatibility with newer clients).
  Future<bool> applyOp(Op op, {int seq = 0}) async {
    final meta = _tables[op.table];
    if (meta == null) throw UnknownTableException(op.table);
    final existing = await db.customSelect(
      'SELECT "sync_clock", "sync_hlc", "sync_seq" FROM "${op.table}" WHERE "id" = ?',
      variables: [Variable<String>(op.rowId)],
      readsFrom: {meta.info},
    ).getSingleOrNull();

    bool known(String f) => meta.types.containsKey(f) && !kSyncSystemColumns.contains(f);
    final existingSeq = existing?.read<int>('sync_seq') ?? 0;
    final MergeResult result;
    final String rowHlc;

    if (op.kind == OpKind.insertOnly) {
      // Append-only rows: FIRST writer wins (lowest HLC). Unlike "ignore if
      // present", this converges regardless of arrival order (SPEC §8.4.4).
      final existingHlc = existing?.read<String>('sync_hlc') ?? '';
      if (existing != null && existingHlc.isNotEmpty && op.hlc.compareTo(existingHlc) >= 0) {
        await _bumpSeq(meta, op.rowId, seq, existingSeq);
        return false;
      }
      final changes = {for (final e in op.fields.entries) if (known(e.key)) e.key: e.value};
      result = MergeResult(changes, {for (final k in changes.keys) k: op.hlc});
      rowHlc = op.hlc;
    } else {
      final fields = op.kind == OpKind.delete ? {...op.fields, 'deleted': true} : op.fields;
      final clock = existing == null ? <String, String>{} : decodeClock(existing.read<String>('sync_clock'));
      result = mergeFields(clock: clock, fields: fields, hlc: op.hlc, isKnown: known);
      if (!result.changed && existing != null) {
        await _bumpSeq(meta, op.rowId, seq, existingSeq);
        return false;
      }
      rowHlc = existing == null ? op.hlc : _maxString(existing.read<String>('sync_hlc'), op.hlc);
    }
    final rowSeq = seq > existingSeq ? seq : existingSeq;

    final columns = <String>['id', ...result.changes.keys, 'sync_clock', 'sync_hlc', 'sync_seq'];
    final values = <Variable<Object>>[
      Variable<String>(op.rowId),
      for (final e in result.changes.entries) _toVariable(meta.types[e.key], e.value),
      Variable<String>(encodeClock(result.clock)),
      Variable<String>(rowHlc),
      Variable<int>(rowSeq),
    ];
    final quoted = columns.map((c) => '"$c"').join(', ');
    final placeholders = List.filled(columns.length, '?').join(', ');
    final updates = columns.skip(1).map((c) => '"$c" = excluded."$c"').join(', ');
    await db.customInsert(
      'INSERT INTO "${op.table}" ($quoted) VALUES ($placeholders) ON CONFLICT ("id") DO UPDATE SET $updates',
      variables: values,
      updates: {meta.info},
    );
    return true;
  }

  /// Raw row (SQL column → value) or null.
  Future<Map<String, Object?>?> readRow(String table, String id) async {
    final meta = _tables[table];
    if (meta == null) throw UnknownTableException(table);
    final row = await db.customSelect(
      'SELECT * FROM "$table" WHERE "id" = ?',
      variables: [Variable<String>(id)],
      readsFrom: {meta.info},
    ).getSingleOrNull();
    return row?.data;
  }

  /// All rows of [table] as raw maps (snapshots, exports).
  Future<List<Map<String, Object?>>> readAll(String table) async {
    final meta = _tables[table];
    if (meta == null) throw UnknownTableException(table);
    final rows = await db.customSelect('SELECT * FROM "$table"', readsFrom: {meta.info}).get();
    return [for (final r in rows) r.data];
  }

  /// Replaces every synced table with [snapshot] (device bootstrap, §8.4.6).
  /// Tables missing from the snapshot are cleared. Runs as one batch (a
  /// single round trip to the database worker on web and isolates).
  Future<void> replaceAll(Map<String, List<Map<String, Object?>>> snapshot) async {
    await db.batch((b) {
      for (final entry in _tables.entries) {
        b.customStatement('DELETE FROM "${entry.key}"');
        for (final row in snapshot[entry.key] ?? const <Map<String, Object?>>[]) {
          final cols = row.keys.where(entry.value.types.containsKey).toList();
          if (cols.isEmpty) continue;
          b.customStatement(
            'INSERT INTO "${entry.key}" (${cols.map((c) => '"$c"').join(', ')}) '
            'VALUES (${List.filled(cols.length, '?').join(', ')})',
            [for (final c in cols) _toSql(entry.value.types[c], row[c])],
          );
        }
      }
    });
    // One notification for everything (cheaper than per-row updates).
    db.notifyUpdates({for (final m in _tables.values) TableUpdate.onTable(m.info)});
  }

  /// Applies [ops] in order with exactly the result of calling [applyOp] for
  /// each, but with one read per table and a single batched write. Every
  /// statement crosses to drift's worker on web (and to the database isolate
  /// on native), so bulk work — catch-up, bootstrap replays, seeding — must
  /// not pay two round trips per op (SPEC §12.7). Returns how many ops
  /// changed a row.
  Future<int> applyOpsBulk(List<Op> ops, {int Function(Op op)? seqOf}) async {
    if (ops.isEmpty) return 0;
    final idsByTable = <String, Set<String>>{};
    for (final op in ops) {
      if (!_tables.containsKey(op.table)) throw UnknownTableException(op.table);
      idsByTable.putIfAbsent(op.table, () => <String>{}).add(op.rowId);
    }
    var changed = 0;
    await db.transaction(() async {
      final rows = <String, _BulkRow>{};
      String key(String table, String id) => '$table\u0000$id';
      for (final e in idsByTable.entries) {
        final meta = _tables[e.key]!;
        final ids = e.value.toList();
        for (var i = 0; i < ids.length; i += 500) {
          final chunk = ids.sublist(i, math.min(i + 500, ids.length));
          final found = await db.customSelect(
            'SELECT "id", "sync_clock", "sync_hlc", "sync_seq" FROM "${e.key}" '
            'WHERE "id" IN (${List.filled(chunk.length, '?').join(', ')})',
            variables: [for (final id in chunk) Variable<String>(id)],
            readsFrom: {meta.info},
          ).get();
          for (final r in found) {
            rows[key(e.key, r.read<String>('id'))] = _BulkRow.existing(
              decodeClock(r.read<String>('sync_clock')),
              r.read<String>('sync_hlc'),
              r.read<int>('sync_seq'),
            );
          }
        }
      }

      for (final op in ops) {
        final meta = _tables[op.table]!;
        final row = rows.putIfAbsent(key(op.table, op.rowId), _BulkRow.absent);
        final seq = seqOf?.call(op) ?? 0;
        bool known(String f) => meta.types.containsKey(f) && !kSyncSystemColumns.contains(f);
        if (op.kind == OpKind.insertOnly) {
          // First writer (lowest HLC) wins, as in [applyOp].
          if (row.present && row.hlc.isNotEmpty && op.hlc.compareTo(row.hlc) >= 0) {
            row.bump(seq);
            continue;
          }
          final values = {for (final f in op.fields.entries) if (known(f.key)) f.key: f.value};
          row.values.addAll(values);
          row.clock = {for (final k in values.keys) k: op.hlc};
          row.hlc = op.hlc;
        } else {
          final fields = op.kind == OpKind.delete ? {...op.fields, 'deleted': true} : op.fields;
          final result = mergeFields(clock: row.clock, fields: fields, hlc: op.hlc, isKnown: known);
          if (!result.changed && row.present) {
            row.bump(seq);
            continue;
          }
          row.values.addAll(result.changes);
          row.clock = result.clock;
          row.hlc = row.present ? _maxString(row.hlc, op.hlc) : op.hlc;
        }
        row
          ..present = true
          ..write = true
          ..seq = math.max(row.seq, seq);
        changed++;
      }

      final touched = <String>{};
      await db.batch((b) {
        rows.forEach((k, row) {
          if (!row.write && !row.seqDirty) return;
          final sep = k.indexOf('\u0000');
          final table = k.substring(0, sep);
          final id = k.substring(sep + 1);
          final meta = _tables[table]!;
          touched.add(table);
          if (!row.write) {
            b.customStatement('UPDATE "$table" SET "sync_seq" = ? WHERE "id" = ?', [row.seq, id]);
            return;
          }
          final columns = ['id', ...row.values.keys, 'sync_clock', 'sync_hlc', 'sync_seq'];
          b.customStatement(
            'INSERT INTO "$table" (${columns.map((c) => '"$c"').join(', ')}) '
            'VALUES (${List.filled(columns.length, '?').join(', ')}) '
            'ON CONFLICT ("id") DO UPDATE SET ${columns.skip(1).map((c) => '"$c" = excluded."$c"').join(', ')}',
            [
              id,
              for (final e in row.values.entries) _toSql(meta.types[e.key], e.value),
              encodeClock(row.clock),
              row.hlc,
              row.seq,
            ],
          );
        });
      });
      if (touched.isNotEmpty) db.notifyUpdates({for (final t in touched) TableUpdate.onTable(_tables[t]!.info)});
    });
    return changed;
  }

  Future<void> _bumpSeq(_TableMeta meta, String rowId, int seq, int existingSeq) async {
    if (seq <= existingSeq) return;
    await db.customUpdate(
      'UPDATE "${meta.info.actualTableName}" SET "sync_seq" = ? WHERE "id" = ?',
      variables: [Variable<int>(seq), Variable<String>(rowId)],
      updates: {meta.info},
    );
  }

  static String _maxString(String a, String b) => a.compareTo(b) >= 0 ? a : b;

  /// A raw SQL argument for batched statements (no drift Variable wrapper).
  static Object? _toSql(Object? type, Object? v) {
    if (v == null) return null;
    switch (type) {
      case DriftSqlType.bool:
        final b = v is bool ? v : (v is num ? v != 0 : '$v' == 'true');
        return b ? 1 : 0;
      case DriftSqlType.int:
      case DriftSqlType.bigInt:
        return v is num ? v.toInt() : int.tryParse('$v') ?? 0;
      case DriftSqlType.double:
        return v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;
      default:
        return v is String ? v : jsonEncode(v);
    }
  }

  static Variable<Object> _toVariable(Object? type, Object? v) {
    if (v == null) return const Variable<Object>(null);
    switch (type) {
      case DriftSqlType.bool:
        return Variable<bool>(v is bool ? v : (v is num ? v != 0 : '$v' == 'true'));
      case DriftSqlType.int:
      case DriftSqlType.bigInt:
        return Variable<int>(v is num ? v.toInt() : int.tryParse('$v') ?? 0);
      case DriftSqlType.double:
        return Variable<double>(v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
      default:
        return Variable<String>(v is String ? v : jsonEncode(v));
    }
  }
}

/// Working state of one row during [SyncStore.applyOpsBulk].
class _BulkRow {
  _BulkRow.existing(this.clock, this.hlc, this.seq) : present = true;
  _BulkRow.absent()
      : clock = {},
        hlc = '',
        seq = 0,
        present = false;

  Map<String, String> clock;
  String hlc;
  int seq;

  /// Exists in the table, or was created by an earlier op of this batch.
  bool present;

  /// Needs a full upsert of [values] plus the system columns.
  bool write = false;

  /// Only `sync_seq` moved.
  bool seqDirty = false;
  final Map<String, Object?> values = {};

  void bump(int newSeq) {
    if (newSeq > seq) {
      seq = newSeq;
      seqDirty = true;
    }
  }
}
