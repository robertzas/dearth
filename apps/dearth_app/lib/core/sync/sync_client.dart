import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'hub_api.dart';

/// Connection phases shown by the sync indicator (SPEC FR-HOME-04).
enum SyncPhase {
  /// Not started (demo mode) or stopped.
  idle,
  connecting,

  /// Downloading a snapshot (first start, or after a long offline gap).
  bootstrapping,

  /// Receiving missed ops.
  catchingUp,

  /// Up to date and receiving changes as they happen.
  live,

  /// Disconnected; retrying with backoff. The app keeps working offline.
  offline,

  /// The Hub no longer knows this device (revoked): re-pair needed.
  unauthorized,

  /// The Hub speaks a newer schema: update the app (SPEC §8.4.5).
  upgradeRequired,
}

@immutable
class SyncState {
  const SyncState(this.phase, {this.lastLiveMs, this.error, this.retryInS});
  final SyncPhase phase;
  final int? lastLiveMs;
  final String? error;
  final int? retryInS;

  bool get isHealthy => phase == SyncPhase.live || phase == SyncPhase.idle;
  bool get isBlocked => phase == SyncPhase.unauthorized || phase == SyncPhase.upgradeRequired;

  SyncState copyWith({SyncPhase? phase, String? error, int? retryInS}) =>
      SyncState(phase ?? this.phase, lastLiveMs: phase == SyncPhase.live ? DateTime.now().millisecondsSinceEpoch : lastLiveMs, error: error, retryInS: retryInS);
}

/// Handles a remote command (wake, sleep, chime, screenshot…) and returns
/// result data, or throws to report failure.
typedef CommandHandler = Future<Map<String, Object?>> Function(String command, Map<String, Object?> args);

/// The device side of the sync protocol (SPEC §8.4, Appendix E).
///
/// * Local writes land in the outbox (via the [Mutator] sink) and are pushed
///   in batches of ≤ 500; acks remove them. Rejected ops trigger a repair:
///   the device re-downloads the snapshot and replays what is still pending,
///   which restores the authoritative value of the rejected rows.
/// * Remote ops apply in one transaction per message together with the
///   cursor, so a crash can never skip or double-count a batch.
/// * A snapshot is used for first sync and when the Hub has compacted past
///   our cursor; live ops arriving meanwhile are buffered and replayed.
class SyncClient {
  SyncClient({
    required this.db,
    required this.store,
    required this.clock,
    required this.api,
    required this.token,
    required this.appVersion,
    required this.platform,
    this.onRejected,
    this.onCommand,
    this.telemetry,
    this.onEphemeral,
  });

  final DearthDb db;
  final SyncStore store;
  final HlcClock clock;
  final HubApi api;
  final String token;
  final String appVersion;
  final String platform;
  final void Function(List<Rejection> rejected)? onRejected;
  final CommandHandler? onCommand;
  final Map<String, Object?> Function()? telemetry;
  final void Function(EphemeralMsg msg)? onEphemeral;

  static const cursorKey = 'sync.seq';
  static const maxBatch = 500;

  final _states = StreamController<SyncState>.broadcast();
  SyncState _state = const SyncState(SyncPhase.idle);
  SyncState get state => _state;
  Stream<SyncState> get states => _states.stream;

  WebSocketChannel? _ws;
  StreamSubscription<Object?>? _sub;
  Future<void> _queue = Future.value();
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  Timer? _pongDeadline;
  Timer? _telemetryTimer;
  Timer? _ackDeadline;
  int _attempt = 0;
  bool _running = false;
  bool _welcomed = false;
  bool _bootstrapping = false;
  bool _repairPending = false;
  final List<OpsMsg> _buffered = [];
  String? _inflightBatch;
  Set<String> _inflightOps = const {};
  String? deviceId;
  String? role;

  void _set(SyncState s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  // ─────────────────────────────── Lifecycle ───────────────────────────────

  void start() {
    if (_running) return;
    _running = true;
    unawaited(_connect());
  }

  Future<void> stop() async {
    _running = false;
    _reconnectTimer?.cancel();
    await _teardown();
    _set(const SyncState(SyncPhase.idle));
  }

  Future<void> dispose() async {
    await stop();
    await _states.close();
  }

  /// Reconnect immediately (app resumed, network came back).
  void nudge() {
    if (!_running || _state.isBlocked) return;
    if (_ws == null) {
      _reconnectTimer?.cancel();
      _attempt = 0;
      unawaited(_connect());
    }
  }

  /// The outbox changed: push soon.
  void kick() {
    if (_welcomed && _inflightBatch == null) _enqueue(_pushOutbox);
  }

  /// Sends a telemetry frame now (admin "refresh").
  void sendTelemetry() => _sendTelemetry();

  Future<void> _teardown() async {
    _pingTimer?.cancel();
    _pongDeadline?.cancel();
    _telemetryTimer?.cancel();
    _ackDeadline?.cancel();
    _welcomed = false;
    _inflightBatch = null;
    _inflightOps = const {};
    final ws = _ws;
    _ws = null;
    await _sub?.cancel();
    _sub = null;
    if (ws != null) {
      try {
        await ws.sink.close(1000);
      } on Object {
        // already closed
      }
    }
  }

  Future<void> _connect() async {
    if (!_running) return;
    _set(_state.copyWith(phase: SyncPhase.connecting));
    try {
      final ch = WebSocketChannel.connect(api.wsUri);
      await ch.ready.timeout(const Duration(seconds: 12));
      if (!_running) {
        await ch.sink.close(1000);
        return;
      }
      _ws = ch;
      _sub = ch.stream.listen(
        (data) => _enqueue(() => _onFrame(data)),
        onDone: () => _enqueue(() => _onClosed(ch.closeCode, ch.closeReason)),
        onError: (Object _) => _enqueue(() => _onClosed(null, null)),
        cancelOnError: true,
      );
      final since = int.tryParse(await db.kvGet(cursorKey) ?? '') ?? 0;
      _send(HelloMsg(token: token, since: since, appVersion: appVersion, platform: platform));
    } on Object catch (e) {
      debugPrint('sync: connect failed: $e');
      await _teardown();
      _scheduleReconnect();
    }
  }

  Future<void> _onClosed(int? code, String? reason) async {
    if (_ws == null && !_welcomed) {
      // Already torn down by us.
    }
    await _teardown();
    if (!_running) return;
    if (code == 4401) {
      _set(const SyncState(SyncPhase.unauthorized, error: 'This device was removed from the Hub.'));
      return;
    }
    if (code == 4426) {
      _set(const SyncState(SyncPhase.upgradeRequired, error: 'Update Dearth to keep syncing.'));
      return;
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_running || _state.isBlocked) return;
    _reconnectTimer?.cancel();
    final base = math.min(30, 1 << math.min(_attempt, 5));
    final delayMs = (base * 1000 * (0.75 + math.Random().nextDouble() * 0.5)).round();
    _attempt++;
    _set(_state.copyWith(phase: SyncPhase.offline, retryInS: (delayMs / 1000).ceil()));
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () => unawaited(_connect()));
  }

  void _enqueue(Future<void> Function() task) {
    _queue = _queue.then((_) => task()).catchError((Object e, StackTrace st) {
      debugPrint('sync: task failed: $e\n$st');
    });
  }

  void _send(SyncMessage m) {
    final ws = _ws;
    if (ws == null) return;
    try {
      ws.sink.add(m.encode());
    } on Object catch (e) {
      debugPrint('sync: send failed: $e');
    }
  }

  // ─────────────────────────────── Frames ──────────────────────────────────

  Future<void> _onFrame(Object? data) async {
    if (data is! String) return;
    final SyncMessage msg;
    try {
      msg = SyncMessage.decode(data);
    } on FormatException catch (e) {
      debugPrint('sync: bad frame: $e');
      return;
    }
    switch (msg) {
      case WelcomeMsg():
        await _onWelcome(msg);
      case OpsMsg():
        if (_bootstrapping) {
          _buffered.add(msg);
        } else {
          await _applyOps(msg);
        }
      case AckMsg():
        await _onAck(msg);
      case PongMsg():
        _pongDeadline?.cancel();
      case PingMsg():
        _send(const PongMsg());
      case CommandMsg():
        unawaited(_onCommand(msg));
      case EphemeralMsg():
        onEphemeral?.call(msg);
      case ErrorMsg():
        if (msg.code == 'unauthorized') {
          _set(SyncState(SyncPhase.unauthorized, error: msg.message));
        } else if (msg.code == 'upgrade_required') {
          _set(SyncState(SyncPhase.upgradeRequired, error: msg.message));
        } else {
          debugPrint('sync: hub error ${msg.code}: ${msg.message}');
        }
      default:
        break;
    }
  }

  Future<void> _onWelcome(WelcomeMsg w) async {
    _attempt = 0;
    _welcomed = true;
    deviceId = w.deviceId;
    role = w.role;
    if (w.snapshotRequired) {
      await _bootstrap();
    } else {
      _set(_state.copyWith(phase: SyncPhase.catchingUp));
    }
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _send(const PingMsg());
      kick();
      _pongDeadline?.cancel();
      _pongDeadline = Timer(const Duration(seconds: 15), () {
        debugPrint('sync: pong timeout; reconnecting');
        _enqueue(() => _onClosed(null, null));
      });
    });
    _telemetryTimer = Timer.periodic(const Duration(seconds: 60), (_) => _sendTelemetry());
    _sendTelemetry();
    await _pushOutbox();
  }

  Future<void> _bootstrap() async {
    _bootstrapping = true;
    _set(_state.copyWith(phase: SyncPhase.bootstrapping));
    try {
      final snap = await api.snapshot();
      final seq = (snap['seq'] as num?)?.toInt() ?? 0;
      final tables = <String, List<Map<String, Object?>>>{
        for (final e in (snap['tables'] as Map<String, Object?>? ?? const {}).entries)
          e.key: [for (final r in (e.value as List? ?? const [])) if (r is Map<String, Object?>) r],
      };
      final pending = await _pendingOps();
      await db.transaction(() async {
        await store.replaceAll(tables);
        // Replay local intent that the Hub has not acknowledged yet.
        await store.applyOpsBulk([for (final op in pending) if (store.isSynced(op.table)) op]);
        await db.kvSet(cursorKey, '$seq');
      });
      for (final t in tables.values.expand((rows) => rows)) {
        final h = Hlc.tryParse(t['sync_hlc'] as String?);
        if (h != null) _observe(h);
      }
    } finally {
      _bootstrapping = false;
    }
    final buffered = List.of(_buffered);
    _buffered.clear();
    for (final m in buffered) {
      await _applyOps(m);
    }
    _set(_state.copyWith(phase: SyncPhase.live));
  }

  Future<void> _applyOps(OpsMsg m) async {
    if (m.ops.isNotEmpty || m.upTo > 0) {
      final seqs = <Op, int>{};
      for (final so in m.ops) {
        final h = Hlc.tryParse(so.op.hlc);
        if (h != null) _observe(h);
        // Tables a newer Hub has but this app doesn't know yet are skipped.
        if (store.isSynced(so.op.table)) seqs[so.op] = so.seq;
      }
      await db.transaction(() async {
        // One read per table and one batched write per message (SPEC §12.7).
        await store.applyOpsBulk(seqs.keys.toList(), seqOf: (op) => seqs[op]!);
        final current = int.tryParse(await db.kvGet(cursorKey) ?? '') ?? 0;
        if (m.upTo > current) await db.kvSet(cursorKey, '${m.upTo}');
      });
    }
    if (m.live && _state.phase != SyncPhase.live) _set(_state.copyWith(phase: SyncPhase.live));
  }

  void _observe(Hlc h) {
    try {
      clock.observe(h);
    } on ClockDriftException {
      // The Hub validates drift; a far-future stamp from elsewhere must not
      // stall this device.
    }
  }

  // ─────────────────────────────── Outbox ──────────────────────────────────

  Future<List<Op>> _pendingOps({int? limit}) async {
    final q = db.select(db.outbox)..orderBy([(t) => OrderingTerm.asc(t.seq)]);
    if (limit != null) q.limit(limit);
    final rows = await q.get();
    return [for (final r in rows) Op.fromJson(jsonDecode(r.opJson) as Map<String, Object?>)];
  }

  Future<void> _pushOutbox() async {
    if (!_welcomed || _inflightBatch != null || _ws == null) return;
    final ops = await _pendingOps(limit: maxBatch);
    if (ops.isEmpty) {
      if (_repairPending) {
        _repairPending = false;
        await _bootstrap();
      }
      return;
    }
    final batch = newId();
    _inflightBatch = batch;
    _inflightOps = {for (final o in ops) o.id};
    _send(PushMsg(batch: batch, ops: ops));
    _ackDeadline?.cancel();
    _ackDeadline = Timer(const Duration(seconds: 30), () {
      if (_inflightBatch == batch) {
        debugPrint('sync: ack timeout; reconnecting');
        _enqueue(() => _onClosed(null, null));
      }
    });
  }

  Future<void> _onAck(AckMsg a) async {
    if (a.batch != _inflightBatch) return;
    _ackDeadline?.cancel();
    final done = {...a.accepted, for (final r in a.rejected) r.opId}.intersection(_inflightOps);
    if (done.isNotEmpty) {
      await (db.delete(db.outbox)..where((t) => t.opId.isIn(done))).go();
    }
    _inflightBatch = null;
    _inflightOps = const {};
    if (a.rejected.isNotEmpty) {
      _repairPending = true;
      onRejected?.call(a.rejected);
    }
    await _pushOutbox();
  }

  // ───────────────────────────── Commands etc. ─────────────────────────────

  Future<void> _onCommand(CommandMsg c) async {
    try {
      final data = c.command == 'ping' ? <String, Object?>{'pong': true} : await (onCommand?.call(c.command, c.args) ?? Future.value(<String, Object?>{}));
      _send(CommandResultMsg(id: c.id, ok: true, data: data));
    } on Object catch (e) {
      _send(CommandResultMsg(id: c.id, ok: false, data: {'error': '$e'}));
    }
  }

  void _sendTelemetry() {
    if (!_welcomed) return;
    _send(TelemetryMsg({'app': appVersion, 'platform': platform, ...?telemetry?.call()}));
  }
}
