import 'package:dearth_app/features/kids/kids_setup.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Chore/routine/reward setup helpers (SPEC FR-KID-01/04/11/14).
void main() {
  group('FR-KID-01: schedules', () {
    test('every editor schedule round-trips through its RRULE', () {
      for (final (kind, days) in [
        (ScheduleKind.daily, <int>{}),
        (ScheduleKind.weekdays, {1, 2, 3, 4, 5}),
        (ScheduleKind.weekends, {6, 7}),
        (ScheduleKind.days, {1, 4}),
      ]) {
        final rule = scheduleRule(kind, days: days);
        final (back, backDays) = scheduleOf(rule);
        expect(back, kind, reason: rule);
        expect(backDays, days, reason: rule);
      }
    });

    test('rules it can’t express are kept as custom, untouched', () {
      for (final rule in ['FREQ=DAILY;INTERVAL=2', 'FREQ=MONTHLY;BYMONTHDAY=1', 'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO']) {
        expect(scheduleOf(rule).$1, ScheduleKind.custom, reason: rule);
        expect(scheduleRule(ScheduleKind.custom, custom: rule), rule);
      }
    });

    test('all seven days is daily; plain words for the list', () {
      expect(scheduleOf('FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR,SA,SU').$1, ScheduleKind.daily);
      expect(describeSchedule('FREQ=DAILY'), 'Every day');
      expect(describeSchedule('FREQ=WEEKLY;BYDAY=TH,MO'), 'Mon, Thu');
      expect(describeSchedule('FREQ=WEEKLY;BYDAY=SA,SU'), 'Weekends');
      expect(scheduleRule(ScheduleKind.days, days: {4, 1}), 'FREQ=WEEKLY;BYDAY=MO,TH');
      expect(scheduleRule(ScheduleKind.days), 'FREQ=DAILY', reason: 'no days picked yet');
    });
  });

  group('FR-KID-01/05: chore fields', () {
    test('grown-ups’ chores carry no kid rewards', () {
      final f = choreFields(
        title: ' Trash ',
        emoji: '🗑️',
        assignees: const ['p-dad'],
        rrule: 'FREQ=DAILY',
        window: 'any',
        stars: 3,
        jar: true,
        sticker: true,
        needsApproval: false,
        adult: true,
        voiceLine: '  ',
        anchorDate: '2026-10-03',
      );
      expect((f['title'], f['stars'], f['jar'], f['sticker'], f['voice_line']), ('Trash', 0, 0, false, null));
    });

    test('a library chore is assigned, scheduled and voiced from its template', () {
      final tpl = kChoreLibrary.firstWhere((c) => c.title == 'Water a plant');
      final f = choreFromTemplate(tpl, kidId: 'p-ava', anchorDate: '2026-10-03');
      expect(f['assignees'], ['p-ava']);
      expect((f['rrule'], f['voice_line'], f['stars'], f['jar'], f['sticker']), (tpl.rrule, tpl.voiceLine, 1, 1, true));
    });
  });

  group('FR-KID-04: chore ideas by age', () {
    test('only what the kid is old enough for, easiest first, without repeats', () {
      final ideas = choreIdeasFor(2.5, existingTitles: const ['toys in the bin']);
      expect(ideas.every((c) => c.minAge <= 3.0), isTrue);
      expect(ideas.map((c) => c.title), isNot(contains('Toys in the bin')));
      expect(ideas.map((c) => c.minAge).toList(), [...ideas.map((c) => c.minAge)]..sort());
      expect(choreIdeasFor(null).length, kChoreLibrary.length, reason: 'no birthday: everything');
    });

    test('age from a birthday', () {
      expect(ageOn('2024-04-03', const LocalDate(2026, 10, 3))!, closeTo(2.5, 0.01));
      expect(ageOn(null, const LocalDate(2026, 10, 3)), isNull);
    });
  });

  group('FR-KID-13..15: reward fields', () {
    test('each kind spends its own currency; surprises cost the jar, not a price', () {
      expect(rewardFields(title: 'Story', emoji: '📖', kind: RewardKind.store, cost: 5), containsPair('currency', Currency.star));
      final surprise = rewardFields(title: 'Park', emoji: '🛝', kind: RewardKind.surprise, cost: 50);
      expect((surprise['currency'], surprise['cost']), (Currency.jar, 0));
      expect(rewardFields(title: 'Zoo', emoji: '🦁', kind: RewardKind.family, cost: 0)['cost'], 1, reason: 'a goal needs at least one job');
      expect(RewardKind.parse('nope'), RewardKind.store);
    });
  });
}
