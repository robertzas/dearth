import 'dart:convert';

import '../sync/hlc.dart';
import '../sync/op.dart';
import '../sync/sync_specs.dart';
import '../time/local_date.dart';
import '../util/ids.dart';
import 'sync_store.dart';

/// Receives locally created ops inside the same transaction that applied
/// them: devices append to the outbox; the Hub appends to the op log.
typedef OpSink = Future<void> Function(List<Op> ops);

/// The only way application code writes synced data (SPEC §8.4).
///
/// Each write becomes an [Op] stamped by this node's [HlcClock], applied
/// locally through [SyncStore] (so the UI updates instantly) and handed to
/// [sink] for replication, atomically.
class Mutator {
  Mutator({required this.store, required this.clock, required this.sink, this.defaultActor});

  final SyncStore store;
  final HlcClock clock;
  final OpSink sink;

  /// Actor stamped on ops when none is given (e.g. the profile in grown-up
  /// mode).
  String? defaultActor;

  Op makeOp(String table, String rowId, Map<String, Object?> fields, {OpKind kind = OpKind.upsert, String? actor}) {
    final spec = kSyncTables[table];
    if (spec == null || !store.isSynced(table)) throw UnknownTableException(table);
    final normalized = <String, Object?>{};
    fields.forEach((k, v) {
      if (!store.isDataColumn(table, k)) {
        throw ArgumentError.value(k, 'fields', 'Unknown column for table "$table"');
      }
      normalized[k] = _normalize(v);
    });
    return Op(
      id: newId(),
      table: table,
      rowId: rowId,
      kind: kind,
      fields: normalized,
      hlc: clock.tick().pack(),
      actor: actor ?? defaultActor,
    );
  }

  Future<void> upsert(String table, String rowId, Map<String, Object?> fields, {String? actor}) =>
      commit([makeOp(table, rowId, fields, actor: actor)]);

  /// Creates a new row with a fresh id and returns the id.
  Future<String> create(String table, Map<String, Object?> fields, {String? actor}) async {
    final id = newId();
    await upsert(table, id, fields, actor: actor);
    return id;
  }

  /// Create-once insert for append-only tables (ledger, game events…).
  Future<void> insertOnly(String table, String rowId, Map<String, Object?> fields, {String? actor}) =>
      commit([makeOp(table, rowId, fields, kind: OpKind.insertOnly, actor: actor)]);

  Future<void> delete(String table, String rowId, {String? actor}) =>
      commit([makeOp(table, rowId, const {}, kind: OpKind.delete, actor: actor)]);

  /// Applies [ops] locally and hands them to the sink, atomically.
  Future<void> commit(List<Op> ops) async {
    if (ops.isEmpty) return;
    await store.db.transaction(() async {
      await store.applyOpsBulk(ops);
      await sink(ops);
    });
  }

  static Object? _normalize(Object? v) => switch (v) {
        null || String() || bool() || int() || double() => v,
        DateTime() => v.millisecondsSinceEpoch,
        LocalDate() => v.iso,
        Enum() => v.name,
        Map() || List() => jsonEncode(v),
        _ => '$v',
      };
}
