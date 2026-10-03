import 'dart:async';
import 'dart:convert';

import 'package:dearth_core/dearth_core.dart';
import 'package:drift/drift.dart';
import 'package:logging/logging.dart';

final _log = Logger('kernel');

/// A connected device's identity as seen by the kernel.
class DeviceIdentity {
  const DeviceIdentity({required this.deviceId, required this.role, required this.admin, this.name = ''});
  final String deviceId;
  final String role;
  final bool admin;
  final String name;

  static const hub = DeviceIdentity(deviceId: 'hub', role: 'hub', admin: true, name: 'Hub');
}

/// Receives ops after they are committed (connections, jobs).
typedef OpListener = void Function(List<SeqOp> ops, DeviceIdentity origin);

/// The sync authority (SPEC §8.4): validates, sequences, applies and fans out
/// every op — from devices and from the Hub's own integration workers.
class HubKernel {
  HubKernel(this.db, {String node = 'hub'})
      : store = SyncStore(db),
        clock = HlcClock(node) {
    mutator = Mutator(store: store, clock: clock, sink: (_) async {});
  }

  final DearthDb db;
  final SyncStore store;
  final HlcClock clock;

  /// Used for HLC stamping and field normalization of Hub-originated ops.
  late final Mutator mutator;
  final List<OpListener> _listeners = [];

  void addListener(OpListener l) => _listeners.add(l);
  void removeListener(OpListener l) => _listeners.remove(l);

  // ────────────────────────────── Hub writes ───────────────────────────────

  /// Commits Hub-originated ops (integrations, bootstrap) and broadcasts.
  Future<List<SeqOp>> write(List<Op> ops) async {
    if (ops.isEmpty) return const [];
    final out = <SeqOp>[];
    await db.transaction(() async {
      for (final op in ops) {
        final seq = await _appendLog(op, DeviceIdentity.hub.deviceId);
        await store.applyOp(op, seq: seq);
        out.add(SeqOp(seq, op));
      }
    });
    _emit(out, DeviceIdentity.hub);
    return out;
  }

  Future<void> upsert(String table, String id, Map<String, Object?> fields) =>
      write([mutator.makeOp(table, id, fields)]);

  Future<String> create(String table, Map<String, Object?> fields) async {
    final id = newId();
    await upsert(table, id, fields);
    return id;
  }

  Future<void> delete(String table, String id) => write([mutator.makeOp(table, id, const {}, kind: OpKind.delete)]);

  // ───────────────────────────── Device writes ─────────────────────────────

  /// Validates and applies a device batch. Returns accepted op ids and
  /// rejections with reasons (SPEC §8.4.3–8.4.4).
  Future<(List<String>, List<Rejection>)> accept(DeviceIdentity device, List<Op> ops) async {
    final accepted = <String>[];
    final rejected = <Rejection>[];
    final applied = <SeqOp>[];
    await db.transaction(() async {
      for (final original in ops) {
        final (op, reason) = await _validate(device, original);
        if (op == null) {
          rejected.add(Rejection(original.id, reason ?? 'rejected'));
          continue;
        }
        final dup = await (db.select(db.opLog)..where((t) => t.opId.equals(op.id))).getSingleOrNull();
        if (dup != null) {
          accepted.add(op.id);
          continue;
        }
        try {
          clock.observe(Hlc.parse(op.hlc));
        } on ClockDriftException catch (e) {
          rejected.add(Rejection(op.id, 'clock_drift:${e.driftMs}'));
          continue;
        } on FormatException {
          rejected.add(Rejection(op.id, 'bad_hlc'));
          continue;
        }
        final seq = await _appendLog(op, device.deviceId);
        await store.applyOp(op, seq: seq);
        applied.add(SeqOp(seq, op));
        accepted.add(op.id);
      }
    });
    if (applied.isNotEmpty) _emit(applied, device);
    if (rejected.isNotEmpty) _log.info('Rejected ${rejected.length} op(s) from ${device.deviceId}: ${rejected.map((r) => r.reason).toSet()}');
    return (accepted, rejected);
  }

  Future<(Op?, String?)> _validate(DeviceIdentity device, Op op) async {
    final spec = kSyncTables[op.table];
    if (spec == null || !store.isSynced(op.table)) return (null, 'unknown_table');
    if (spec.hubOnly) return (null, 'hub_only');
    if (op.schema != kSchemaMajor) return (null, 'schema_mismatch');
    if (device.role == DeviceRole.kidRoom && !spec.kidWritable) return (null, 'acl:role');

    // Strip fields devices may not write (integration-owned, system).
    final fields = <String, Object?>{};
    var stripped = 0;
    op.fields.forEach((k, v) {
      if (deviceMayWriteField(spec, k)) {
        fields[k] = v;
      } else {
        stripped++;
      }
    });
    if (fields.isEmpty && op.fields.isNotEmpty && op.kind != OpKind.delete) return (null, 'acl:fields');

    // Gated actions need an adult actor on a non-kid device (SPEC §8.4.4).
    final needsAdult = switch (op.table) {
      'chore_instances' => fields['status'] == 'approved',
      'redemptions' => const {'approved', 'denied', 'fulfilled'}.contains(fields['status']),
      'ledger_entries' => (fields['delta'] is num && (fields['delta']! as num) < 0) && !const {'undo', 'redeem'}.contains(fields['reason']),
      'profiles' => fields.containsKey('pin_hash') || fields.containsKey('role'),
      _ => false,
    };
    if (needsAdult && !await _isAdultActor(device, op.actorProfileId)) return (null, 'acl:approval_requires_adult');

    final out = stripped == 0
        ? op
        : Op(id: op.id, table: op.table, rowId: op.rowId, kind: op.kind, fields: fields, hlc: op.hlc, actor: op.actor, schema: op.schema);
    return (out, null);
  }

  Future<bool> _isAdultActor(DeviceIdentity device, String? profileId) async {
    if (device.role == DeviceRole.kidRoom) return false;
    if (device.admin && profileId == null) return true; // admin tooling
    if (profileId == null) return false;
    final p = await (db.select(db.profiles)..where((t) => t.id.equals(profileId))).getSingleOrNull();
    if (p == null) {
      // First-run bootstrap: the very first profile can be created by anyone.
      final count = await db.profiles.count().getSingle();
      return count == 0;
    }
    return !p.deleted && (p.role == ProfileRole.adult || p.role == ProfileRole.caregiver);
  }

  Future<int> _appendLog(Op op, String deviceId) => db.into(db.opLog).insert(OpLogCompanion.insert(
        opId: op.id,
        tbl: op.table,
        rowId: op.rowId,
        opJson: jsonEncode(op.toJson()),
        deviceId: deviceId,
        receivedMs: DateTime.now().millisecondsSinceEpoch,
      ));

  void _emit(List<SeqOp> ops, DeviceIdentity origin) {
    for (final l in List.of(_listeners)) {
      try {
        l(ops, origin);
      } on Object catch (e, st) {
        _log.warning('Op listener failed: $e', e, st);
      }
    }
  }

  // ─────────────────────────────── Reading ─────────────────────────────────

  Future<int> maxSeq() async {
    final row = await db.customSelect('SELECT COALESCE(MAX(seq), 0) AS m FROM op_log', readsFrom: {db.opLog}).getSingle();
    return row.read<int>('m');
  }

  Future<int> minSeq() async {
    final row = await db.customSelect('SELECT COALESCE(MIN(seq), 0) AS m FROM op_log', readsFrom: {db.opLog}).getSingle();
    return row.read<int>('m');
  }

  /// Ops after [since] visible to [role], in sequence order.
  Future<List<SeqOp>> opsSince(int since, {required String role, int limit = 1000}) async {
    final rows = await (db.select(db.opLog)
          ..where((t) => t.seq.isBiggerThanValue(since))
          ..orderBy([(t) => OrderingTerm.asc(t.seq)])
          ..limit(limit))
        .get();
    return [
      for (final r in rows)
        if (roleReceivesTable(role, r.tbl)) SeqOp(r.seq, Op.fromJson(jsonDecode(r.opJson) as Map<String, Object?>)),
    ];
  }

  /// Highest seq among the next page (so cursors advance past filtered ops).
  Future<int?> pageEnd(int since, {int limit = 1000}) async {
    final row = await db.customSelect(
      'SELECT MAX(seq) AS m FROM (SELECT seq FROM op_log WHERE seq > ? ORDER BY seq LIMIT ?)',
      variables: [Variable<int>(since), Variable<int>(limit)],
      readsFrom: {db.opLog},
    ).getSingle();
    return row.readNullable<int>('m');
  }

  /// A role-scoped snapshot of every synced table (SPEC §8.4.6).
  Future<Map<String, Object?>> snapshot(String role) => db.transaction(() async {
        final seq = await maxSeq();
        final tables = <String, Object?>{};
        for (final t in store.syncedTables) {
          if (!roleReceivesTable(role, t)) continue;
          tables[t] = await store.readAll(t);
        }
        return {'seq': seq, 'schema': kSchemaMajor, 'tables': tables};
      });

  /// Drops op-log entries older than [keepDays] (devices further behind
  /// re-bootstrap from a snapshot).
  Future<int> compact({int keepDays = 30}) {
    final cutoff = DateTime.now().subtract(Duration(days: keepDays)).millisecondsSinceEpoch;
    return (db.delete(db.opLog)..where((t) => t.receivedMs.isSmallerThanValue(cutoff))).go();
  }
}
