import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'auth.dart';
import 'kernel.dart';

final _log = Logger('connections');

/// This Hub's release version: the image sets `DEARTH_VERSION` (the
/// Dockerfile's `VERSION`, a semantic version from CI); anything else is a
/// development build, which never updates by itself.
final String hubVersion = Platform.environment['DEARTH_VERSION'] ?? '0.1.0-dev';

/// All live device WebSockets (SPEC §8.4.3, §8.6).
class ConnectionHub {
  ConnectionHub(this.kernel, this.auth) {
    kernel.addListener(_onOps);
  }

  final HubKernel kernel;
  final HubAuth auth;
  final Set<DeviceSession> _sessions = {};

  /// Latest telemetry per device id (SPEC FR-ADM-01).
  final Map<String, Map<String, Object?>> telemetry = {};
  final Map<String, Completer<CommandResultMsg>> _pending = {};

  Iterable<DeviceSession> get sessions => _sessions.where((s) => s.identity != null);
  bool isOnline(String deviceId) => sessions.any((s) => s.identity!.deviceId == deviceId);

  Handler get handler => webSocketHandler((WebSocketChannel channel, String? _) {
        final s = DeviceSession(this, channel);
        _sessions.add(s);
        s.start();
      }, pingInterval: const Duration(seconds: 25));

  void _onOps(List<SeqOp> ops, DeviceIdentity origin) {
    for (final s in List.of(_sessions)) {
      s.deliver(ops);
    }
  }

  void _closed(DeviceSession s) => _sessions.remove(s);

  /// Sends a remote command (wake, sleep, reload, screenshot…) and awaits the
  /// device's result. Null when the device is offline or times out.
  Future<CommandResultMsg?> command(String deviceId, String command, {Map<String, Object?> args = const {}, Duration timeout = const Duration(seconds: 20)}) async {
    final targets = sessions.where((s) => s.identity!.deviceId == deviceId).toList();
    if (targets.isEmpty) return null;
    final id = newId();
    final c = Completer<CommandResultMsg>();
    _pending[id] = c;
    targets.last.send(CommandMsg(id: id, command: command, args: args));
    try {
      return await c.future.timeout(timeout);
    } on TimeoutException {
      return null;
    } finally {
      _pending.remove(id);
    }
  }

  /// Broadcasts a non-persisted message to every (matching) device.
  void ephemeral(String channel, Map<String, Object?> data, {bool Function(DeviceIdentity)? where}) {
    final msg = EphemeralMsg(channel, data);
    for (final s in sessions) {
      if (where == null || where(s.identity!)) s.send(msg);
    }
  }

  void _commandResult(CommandResultMsg m) => _pending.remove(m.id)?.complete(m);

  /// Drops every session of [deviceId] (revoked tokens; SPEC §9.2).
  Future<void> disconnect(String deviceId) async {
    for (final s in List.of(_sessions)) {
      if (s.identity?.deviceId != deviceId) continue;
      s.send(const ErrorMsg('unauthorized', 'This device was removed from the Hub'));
      await s.close(4401, 'revoked');
    }
  }

  Future<void> closeAll() async {
    for (final s in List.of(_sessions)) {
      await s.close(1000, 'hub shutting down');
    }
  }
}

/// One device WebSocket.
class DeviceSession {
  DeviceSession(this.hub, this.channel);

  final ConnectionHub hub;
  final WebSocketChannel channel;
  DeviceIdentity? identity;
  StreamSubscription<Object?>? _sub;
  Timer? _helloTimer;
  bool _catchingUp = true;
  final List<SeqOp> _buffer = [];
  int _sentUpTo = 0;
  bool _closed = false;

  HubKernel get kernel => hub.kernel;

  void start() {
    _helloTimer = Timer(const Duration(seconds: 10), () => close(4408, 'hello timeout'));
    _sub = channel.stream.listen(
      (data) => unawaited(_onFrame(data)),
      onDone: _onClosed,
      onError: (Object _) => _onClosed(),
      cancelOnError: true,
    );
  }

  void send(SyncMessage m) {
    if (_closed) return;
    try {
      channel.sink.add(m.encode());
    } on Object catch (e) {
      _log.fine('send failed: $e');
    }
  }

  Future<void> close(int code, String reason) async {
    if (_closed) return;
    _closed = true;
    _helloTimer?.cancel();
    await channel.sink.close(code, reason);
    await _sub?.cancel();
    hub._closed(this);
  }

  void _onClosed() {
    _closed = true;
    _helloTimer?.cancel();
    hub._closed(this);
    if (identity != null) _log.info('Device ${identity!.name} (${identity!.deviceId}) disconnected');
  }

  Future<void> _onFrame(Object? data) async {
    if (data is! String) return;
    SyncMessage msg;
    try {
      msg = SyncMessage.decode(data);
    } on FormatException catch (e) {
      send(ErrorMsg('bad_frame', e.message));
      return;
    }
    if (identity == null) {
      if (msg is HelloMsg) {
        await _hello(msg);
      } else {
        send(const ErrorMsg('hello_required', 'Send hello first'));
        await close(4400, 'hello required');
      }
      return;
    }
    switch (msg) {
      case PushMsg():
        final (accepted, rejected) = await kernel.accept(identity!, msg.ops);
        send(AckMsg(batch: msg.batch, accepted: accepted, rejected: rejected));
      case TelemetryMsg():
        hub.telemetry[identity!.deviceId] = {...msg.data, 'receivedMs': DateTime.now().millisecondsSinceEpoch};
        unawaited(hub.auth.touch(identity!.deviceId));
      case CommandResultMsg():
        hub._commandResult(msg);
      case PingMsg():
        send(const PongMsg());
      default:
        break;
    }
  }

  Future<void> _hello(HelloMsg h) async {
    final id = await hub.auth.deviceForToken(h.token);
    if (id == null) {
      send(const ErrorMsg('unauthorized', 'Unknown or revoked device token'));
      await close(4401, 'unauthorized');
      return;
    }
    if (h.schema != kSchemaMajor) {
      send(const ErrorMsg('upgrade_required', 'Hub speaks schema $kSchemaMajor; update the app'));
      await close(4426, 'upgrade required');
      return;
    }
    _helloTimer?.cancel();
    identity = id;
    unawaited(hub.auth.touch(id.deviceId));
    final maxSeq = await kernel.maxSeq();
    final minSeq = await kernel.minSeq();
    final needsSnapshot = h.since <= 0 ? maxSeq > 0 : (minSeq > 1 && h.since < minSeq - 1);
    send(WelcomeMsg(
      deviceId: id.deviceId,
      role: id.role,
      admin: id.admin,
      seq: maxSeq,
      hubTimeMs: DateTime.now().millisecondsSinceEpoch,
      snapshotRequired: needsSnapshot,
      hubVersion: hubVersion,
    ));
    _log.info('Device ${id.name} (${id.role}) connected, since=${h.since}${needsSnapshot ? ' → snapshot' : ''}');
    if (needsSnapshot) {
      _sentUpTo = maxSeq;
      _catchingUp = false;
      return;
    }
    var cursor = h.since;
    while (true) {
      final end = await kernel.pageEnd(cursor);
      if (end == null) break;
      final ops = await kernel.opsSince(cursor, role: id.role);
      send(OpsMsg(ops: ops, upTo: end));
      cursor = end;
    }
    final pending = _buffer.where((o) => o.seq > cursor && roleReceivesTable(id.role, o.op.table)).toList();
    final upTo = _buffer.isEmpty ? cursor : math.max(cursor, _buffer.map((o) => o.seq).reduce(math.max));
    _buffer.clear();
    _catchingUp = false;
    _sentUpTo = upTo;
    send(OpsMsg(ops: pending, upTo: upTo, live: true));
  }

  void deliver(List<SeqOp> ops) {
    final id = identity;
    if (id == null || ops.isEmpty) return;
    if (_catchingUp) {
      _buffer.addAll(ops);
      return;
    }
    final upTo = ops.map((o) => o.seq).reduce(math.max);
    if (upTo <= _sentUpTo) return;
    final visible = ops.where((o) => o.seq > _sentUpTo && roleReceivesTable(id.role, o.op.table)).toList();
    _sentUpTo = upTo;
    send(OpsMsg(ops: visible, upTo: upTo, live: true));
  }
}
