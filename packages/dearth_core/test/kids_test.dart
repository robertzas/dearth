import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

Chore chore(String id, {String rrule = 'FREQ=DAILY', String assignees = '[]', String? anchor, bool active = true}) => Chore(
      id: id,
      syncClock: '{}',
      syncHlc: '',
      syncSeq: 0,
      deleted: false,
      title: id,
      rrule: rrule,
      anchorDate: anchor,
      assignees: assignees,
      stars: 1,
      sticker: true,
      jar: 1,
      needsApproval: false,
      timeWindow: 'any',
      adult: false,
      active: active,
      sortKey: 'm',
    );

LedgerEntry entry(String id, String? profile, String currency, int delta) => LedgerEntry(
      id: id,
      syncClock: '{}',
      syncHlc: '',
      syncSeq: 0,
      deleted: false,
      profileId: profile,
      currency: currency,
      delta: delta,
      reason: 'chore',
      atMs: 0,
    );

void main() {
  const fri = LocalDate(2026, 10, 2);

  group('FR-KID-02: scheduling', () {
    test('daily, weekly and biweekly rules with an anchor', () {
      expect(isDueOn('FREQ=DAILY', fri, fri), isTrue);
      expect(isDueOn('FREQ=WEEKLY;BYDAY=MO,TH', fri, fri), isFalse);
      expect(isDueOn('FREQ=WEEKLY;BYDAY=MO,TH', fri, fri.addDays(3)), isTrue); // Monday
      const anchor = LocalDate(2026, 9, 28); // Monday
      expect(isDueOn('FREQ=WEEKLY;INTERVAL=2;BYDAY=MO', anchor, anchor.addDays(7)), isFalse);
      expect(isDueOn('FREQ=WEEKLY;INTERVAL=2;BYDAY=MO', anchor, anchor.addDays(14)), isTrue);
      expect(isDueOn('FREQ=DAILY', fri, fri.addDays(-1)), isFalse, reason: 'before anchor');
    });

    test('expands assignees and the Anyone pool with deterministic ids', () {
      final due = dueChores([
        chore('toys', assignees: '["ava"]'),
        chore('pet'),
        chore('off', active: false),
      ], fri, defaultAnchor: fri);
      expect(due.map((d) => '${d.chore.id}:${d.profileId}'), ['toys:ava', 'pet:null']);
      expect(due.first.instanceId, choreInstanceId('toys', fri, 'ava'));
      expect(choreInstanceId('toys', fri, 'ava'), isNot(choreInstanceId('toys', fri.addDays(1), 'ava')));
    });
  });

  test('ledger balances per currency and per profile', () {
    final b = balances([
      entry('1', 'ava', Currency.sticker, 1),
      entry('2', 'ava', Currency.sticker, 1),
      entry('3', 'ava', Currency.star, 5),
      entry('4', 'ava', Currency.star, -3),
      entry('5', null, Currency.family, 2),
    ], 'ava');
    expect(b, {Currency.sticker: 2, Currency.star: 2});
    expect(grantLedgerId('chore_instances', 'x', 'star'), grantLedgerId('chore_instances', 'x', 'star'));
  });

  test('routine steps round-trip and templates build', () {
    final steps = kRoutineTemplates.first.buildSteps();
    expect(steps.length, greaterThan(3));
    final json = encodeJson([for (final s in steps) s.toJson()]);
    expect(decodeSteps(json).map((s) => s.title), steps.map((s) => s.title));
    expect(buddyEmoji('dino'), '🦕');
    expect(buddyEmoji('unknown'), '🐰');
    expect(kChoreLibrary.where((c) => c.minAge <= 2.5).length, greaterThanOrEqualTo(7));
  });
}
