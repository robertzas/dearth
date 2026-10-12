import 'dart:convert';

import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

void main() {
  const op = Op(
    id: 'op1',
    table: 'events',
    rowId: 'row1',
    kind: OpKind.upsert,
    fields: {'title': 'Swim', 'all_day': false, 'start_ms': 42},
    hlc: '018bcfe568000003-devA',
    actor: 'profile:mom',
  );

  test('Op JSON round-trip', () {
    final back = Op.fromJson(op.toJson());
    expect(back.toJson(), op.toJson());
    expect(back.actorProfileId, 'mom');
  });

  test('every message type round-trips through encode/decode', () {
    final messages = <SyncMessage>[
      const HelloMsg(token: 't', since: 12, appVersion: '0.1.0', platform: 'android'),
      const WelcomeMsg(deviceId: 'd', role: 'kitchen', admin: true, seq: 99, hubTimeMs: 5, snapshotRequired: false),
      const PushMsg(batch: 'b1', ops: [op]),
      const AckMsg(batch: 'b1', accepted: ['op1'], rejected: [Rejection('op2', 'acl')]),
      const OpsMsg(ops: [SeqOp(7, op)], upTo: 7, live: true),
      const EphemeralMsg('ha.state', {'light.kitchen': 'on'}),
      const CommandMsg(id: 'c1', command: 'wake', args: {'reason': 'doorbell'}),
      const CommandResultMsg(id: 'c1', ok: true, data: {'png': 'blob:abc'}),
      const TelemetryMsg({'p95': 12.5}),
      const ErrorMsg('upgrade_required', 'update the app'),
      const PingMsg(),
      const PongMsg(),
    ];
    for (final m in messages) {
      final back = SyncMessage.decode(m.encode());
      expect(back.runtimeType, m.runtimeType);
      expect(back.toJson(), m.toJson(), reason: m.type);
    }
  });

  test('unknown message type is a FormatException', () {
    expect(() => SyncMessage.decode('{"type":"nope"}'), throwsFormatException);
  });

  group('malformed frames', () {
    test('an op missing a required key is a FormatException, not a TypeError', () {
      for (final key in ['op', 't', 'id', 'k', 'f', 'h']) {
        final j = op.toJson()..remove(key);
        expect(() => Op.fromJson(j), throwsFormatException, reason: key);
      }
      expect(() => Op.fromJson(op.toJson()..['f'] = 'oops'), throwsFormatException);
      expect(() => Op.fromJson(op.toJson()..['a'] = 7), throwsFormatException);
      expect(() => SeqOp.fromJson({'s': 'x', 'o': op.toJson()}), throwsFormatException);
    });

    test('a catch-up page skips a bad op and keeps the rest and the cursor', () {
      final frame = jsonEncode({
        'type': 'ops',
        'ops': [
          const SeqOp(7, op).toJson(),
          {'s': 8, 'o': {'op': 'bad', 't': 'events'}},
          'not an object',
          SeqOp(10, Op.fromJson(op.toJson()..['op'] = 'op3')).toJson(),
        ],
        'upTo': 10,
      });
      final m = SyncMessage.decode(frame) as OpsMsg;
      expect(m.ops.map((o) => o.seq), [7, 10]);
      expect(m.upTo, 10);
      expect(m.skipped, 2);
    });

    test('a frame of the wrong shape is a FormatException', () {
      expect(() => SyncMessage.decode('[1]'), throwsFormatException);
      expect(() => SyncMessage.decode('{"type":"ops","ops":"nope"}'), throwsFormatException);
      expect(() => SyncMessage.decode('{"type":"push","ops":[{"op":1}]}'), throwsFormatException);
      expect(() => SyncMessage.decode('{"type":"ack","rejected":[5]}'), throwsFormatException);
    });
  });
}
