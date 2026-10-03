import 'dart:convert';

import 'package:meta/meta.dart';

import 'op.dart';

/// WebSocket messages between devices and the Hub (SPEC Appendix E).
/// Every frame is one JSON object with a `type` discriminator.
@immutable
sealed class SyncMessage {
  const SyncMessage();

  String get type;
  Map<String, Object?> body();

  Map<String, Object?> toJson() => {'type': type, ...body()};
  String encode() => jsonEncode(toJson());

  static SyncMessage decode(String frame) {
    final j = jsonDecode(frame);
    if (j is! Map<String, Object?>) throw const FormatException('Sync frame is not an object');
    return fromJson(j);
  }

  static SyncMessage fromJson(Map<String, Object?> j) {
    List<Op> ops(Object? v) => [for (final o in (v as List? ?? const [])) Op.fromJson(Map<String, Object?>.from(o as Map))];
    switch (j['type']) {
      case 'hello':
        return HelloMsg(
          token: j['token'] as String? ?? '',
          since: (j['since'] as num?)?.toInt() ?? 0,
          schema: (j['schema'] as num?)?.toInt() ?? kSchemaMajor,
          appVersion: j['app'] as String? ?? '',
          platform: j['platform'] as String? ?? '',
        );
      case 'welcome':
        return WelcomeMsg(
          deviceId: j['deviceId'] as String? ?? '',
          role: j['role'] as String? ?? 'kitchen',
          admin: j['admin'] as bool? ?? false,
          seq: (j['seq'] as num?)?.toInt() ?? 0,
          hubTimeMs: (j['hubTime'] as num?)?.toInt() ?? 0,
          snapshotRequired: j['snapshot'] as bool? ?? false,
          hubVersion: j['hub'] as String? ?? '',
        );
      case 'push':
        return PushMsg(batch: j['batch'] as String? ?? '', ops: ops(j['ops']));
      case 'ack':
        return AckMsg(
          batch: j['batch'] as String? ?? '',
          accepted: [for (final s in (j['accepted'] as List? ?? const [])) s as String],
          rejected: [
            for (final r in (j['rejected'] as List? ?? const []))
              Rejection((r as Map)['op'] as String, r['reason'] as String? ?? 'rejected'),
          ],
        );
      case 'ops':
        return OpsMsg(
          ops: [for (final o in (j['ops'] as List? ?? const [])) SeqOp.fromJson(Map<String, Object?>.from(o as Map))],
          upTo: (j['upTo'] as num?)?.toInt() ?? 0,
          live: j['live'] as bool? ?? false,
        );
      case 'eph':
        return EphemeralMsg(j['channel'] as String? ?? '', Map<String, Object?>.from(j['data'] as Map? ?? const {}));
      case 'cmd':
        return CommandMsg(
          id: j['id'] as String? ?? '',
          command: j['cmd'] as String? ?? '',
          args: Map<String, Object?>.from(j['args'] as Map? ?? const {}),
        );
      case 'cmd_result':
        return CommandResultMsg(
          id: j['id'] as String? ?? '',
          ok: j['ok'] as bool? ?? false,
          data: Map<String, Object?>.from(j['data'] as Map? ?? const {}),
        );
      case 'telemetry':
        return TelemetryMsg(Map<String, Object?>.from(j['data'] as Map? ?? const {}));
      case 'error':
        return ErrorMsg(j['code'] as String? ?? 'error', j['message'] as String? ?? '');
      case 'ping':
        return const PingMsg();
      case 'pong':
        return const PongMsg();
      default:
        throw FormatException('Unknown sync message type', '${j['type']}');
    }
  }
}

/// Device → Hub, first frame after connecting.
class HelloMsg extends SyncMessage {
  const HelloMsg({required this.token, required this.since, this.schema = kSchemaMajor, this.appVersion = '', this.platform = ''});
  final String token;
  final int since;
  final int schema;
  final String appVersion;
  final String platform;
  @override
  String get type => 'hello';
  @override
  Map<String, Object?> body() =>
      {'token': token, 'since': since, 'schema': schema, 'app': appVersion, 'platform': platform};
}

/// Hub → device, accepted hello.
class WelcomeMsg extends SyncMessage {
  const WelcomeMsg({
    required this.deviceId,
    required this.role,
    required this.admin,
    required this.seq,
    required this.hubTimeMs,
    required this.snapshotRequired,
    this.hubVersion = '',
  });
  final String deviceId;
  final String role;
  final bool admin;
  final int seq;
  final int hubTimeMs;
  final bool snapshotRequired;
  final String hubVersion;
  @override
  String get type => 'welcome';
  @override
  Map<String, Object?> body() => {
        'deviceId': deviceId,
        'role': role,
        'admin': admin,
        'seq': seq,
        'hubTime': hubTimeMs,
        'snapshot': snapshotRequired,
        'hub': hubVersion,
      };
}

class PushMsg extends SyncMessage {
  const PushMsg({required this.batch, required this.ops});
  final String batch;
  final List<Op> ops;
  @override
  String get type => 'push';
  @override
  Map<String, Object?> body() => {'batch': batch, 'ops': [for (final o in ops) o.toJson()]};
}

@immutable
class Rejection {
  const Rejection(this.opId, this.reason);
  final String opId;
  final String reason;
}

class AckMsg extends SyncMessage {
  const AckMsg({required this.batch, required this.accepted, this.rejected = const []});
  final String batch;
  final List<String> accepted;
  final List<Rejection> rejected;
  @override
  String get type => 'ack';
  @override
  Map<String, Object?> body() => {
        'batch': batch,
        'accepted': accepted,
        'rejected': [for (final r in rejected) {'op': r.opId, 'reason': r.reason}],
      };
}

/// Hub → device: ops in sequence order. [live] marks the end of catch-up.
class OpsMsg extends SyncMessage {
  const OpsMsg({required this.ops, required this.upTo, this.live = false});
  final List<SeqOp> ops;
  final int upTo;
  final bool live;
  @override
  String get type => 'ops';
  @override
  Map<String, Object?> body() => {'ops': [for (final o in ops) o.toJson()], 'upTo': upTo, 'live': live};
}

/// Non-persisted channels: HA states, presence, ringing timers (SPEC §8.6).
class EphemeralMsg extends SyncMessage {
  const EphemeralMsg(this.channel, this.data);
  final String channel;
  final Map<String, Object?> data;
  @override
  String get type => 'eph';
  @override
  Map<String, Object?> body() => {'channel': channel, 'data': data};
}

/// Hub → device remote command (wake, sleep, reload, screenshot, chime…).
class CommandMsg extends SyncMessage {
  const CommandMsg({required this.id, required this.command, this.args = const {}});
  final String id;
  final String command;
  final Map<String, Object?> args;
  @override
  String get type => 'cmd';
  @override
  Map<String, Object?> body() => {'id': id, 'cmd': command, 'args': args};
}

class CommandResultMsg extends SyncMessage {
  const CommandResultMsg({required this.id, required this.ok, this.data = const {}});
  final String id;
  final bool ok;
  final Map<String, Object?> data;
  @override
  String get type => 'cmd_result';
  @override
  Map<String, Object?> body() => {'id': id, 'ok': ok, 'data': data};
}

/// Device → Hub performance and health counters (SPEC §12.9).
class TelemetryMsg extends SyncMessage {
  const TelemetryMsg(this.data);
  final Map<String, Object?> data;
  @override
  String get type => 'telemetry';
  @override
  Map<String, Object?> body() => {'data': data};
}

class ErrorMsg extends SyncMessage {
  const ErrorMsg(this.code, this.message);
  final String code;
  final String message;
  @override
  String get type => 'error';
  @override
  Map<String, Object?> body() => {'code': code, 'message': message};
}

class PingMsg extends SyncMessage {
  const PingMsg();
  @override
  String get type => 'ping';
  @override
  Map<String, Object?> body() => const {};
}

class PongMsg extends SyncMessage {
  const PongMsg();
  @override
  String get type => 'pong';
  @override
  Map<String, Object?> body() => const {};
}
