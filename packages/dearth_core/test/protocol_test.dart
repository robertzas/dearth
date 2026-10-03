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
}
