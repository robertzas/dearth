import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

Event ev({
  required String id,
  String title = 'Event',
  int startMs = 0,
  int endMs = 0,
  bool allDay = false,
  String? startDate,
  String? endDate,
  String? rrule,
  String exdates = '[]',
  String? parent,
  int? originalStartMs,
  String status = 'confirmed',
  String? tz,
}) =>
    Event(
      id: id,
      syncClock: '{}',
      syncHlc: '',
      syncSeq: 0,
      deleted: false,
      sourceId: 'local',
      title: title,
      startMs: startMs,
      endMs: endMs,
      allDay: allDay,
      startDate: startDate,
      endDate: endDate,
      tz: tz,
      rrule: rrule,
      exdates: exdates,
      recurringParentId: parent,
      originalStartMs: originalStartMs,
      countdown: false,
      reminders: '[]',
      profileIds: '[]',
      status: status,
    );

void main() {
  final denver = HouseholdTime.named('America/Denver');
  int at(LocalDate d, int h, [int m = 0]) => denver.msAt(d, h, m);

  group('FR-CAL-23: recurrence expansion', () {
    test('weekly 9 am stays 9 am across the DST change', () {
      const first = LocalDate(2026, 10, 20); // Tuesday, MDT
      final master = ev(
        id: 'swim',
        startMs: at(first, 9),
        endMs: at(first, 10),
        rrule: 'RRULE:FREQ=WEEKLY;BYDAY=TU',
        tz: 'America/Denver',
      );
      final occ = RecurrenceExpander(denver).expand(
        [master],
        fromMs: at(const LocalDate(2026, 10, 19), 0),
        toMs: at(const LocalDate(2026, 11, 12), 0),
      );
      expect(occ.map((o) => denver.dateOfMs(o.startMs).iso), ['2026-10-20', '2026-10-27', '2026-11-03', '2026-11-10']);
      for (final o in occ) {
        expect(denver.minuteOfDay(o.startMs), 9 * 60);
        expect(o.durationMs, 3600 * 1000);
        expect(o.recurring, isTrue);
      }
    });

    test('EXDATE, moved and cancelled exceptions', () {
      const d1 = LocalDate(2026, 10, 5); // Monday
      final master = ev(
        id: 'm',
        title: 'Daycare',
        startMs: at(d1, 8),
        endMs: at(d1, 8, 30),
        rrule: 'FREQ=DAILY;COUNT=5',
        exdates: '[${at(d1.addDays(1), 8)}]',
      );
      final moved = ev(
        id: 'x1',
        title: 'Daycare (late)',
        startMs: at(d1.addDays(2), 9),
        endMs: at(d1.addDays(2), 9, 30),
        parent: 'm',
        originalStartMs: at(d1.addDays(2), 8),
      );
      final cancelled = ev(
        id: 'x2',
        parent: 'm',
        originalStartMs: at(d1.addDays(3), 8),
        status: 'cancelled',
      );
      final occ = RecurrenceExpander(denver).expand(
        [master, moved, cancelled],
        fromMs: at(d1, 0),
        toMs: at(d1.addDays(7), 0),
      );
      expect(
        occ.map((o) => '${denver.dateOfMs(o.startMs).day}@${denver.minuteOfDay(o.startMs) ~/ 60} ${o.event.title}'),
        ['5@8 Daycare', '7@9 Daycare (late)', '9@8 Daycare'],
      );
    });

    test('UTC UNTIL includes the last local instance', () {
      const d1 = LocalDate(2026, 6, 1);
      // Last instance June 3 at 18:00 MDT == June 4 00:00Z.
      final master = ev(id: 'u', startMs: at(d1, 18), endMs: at(d1, 19), rrule: 'FREQ=DAILY;UNTIL=20260604T000000Z');
      final occ = RecurrenceExpander(denver).expand([master], fromMs: at(d1, 0), toMs: at(d1.addDays(10), 0));
      expect(occ.length, 3);
    });

    test('yearly all-day birthday and multi-day all-day events', () {
      final bday = ev(id: 'b', title: "Ava's birthday", allDay: true, startDate: '2024-04-12', endDate: '2024-04-13', rrule: 'FREQ=YEARLY');
      final trip = ev(id: 't', title: 'Trip', allDay: true, startDate: '2026-04-10', endDate: '2026-04-14');
      final ex = RecurrenceExpander(denver);
      final occ = ex.expand([bday, trip], fromMs: at(const LocalDate(2026, 4, 1), 0), toMs: at(const LocalDate(2026, 5, 1), 0));
      expect(occ.map((o) => o.startDate!.iso), ['2026-04-10', '2026-04-12']);
      final trip0 = occ.first;
      expect(trip0.isMultiDay, isTrue);
      expect(trip0.daysTouched(denver).map((d) => d.day), [10, 11, 12, 13]);
      expect(ex.forDay([bday, trip], const LocalDate(2026, 4, 13)).map((o) => o.event.id), ['t']);
    });

    test('presets build RRULEs and descriptions read naturally', () {
      const tue = LocalDate(2026, 10, 6);
      expect(buildRrule(RepeatPreset.weekly, tue, weekdays: {2, 4}), 'FREQ=WEEKLY;BYDAY=TU,TH');
      expect(describeRrule('FREQ=WEEKLY;BYDAY=TU,TH'), 'Every week on Tue, Thu');
      expect(describeRrule(buildRrule(RepeatPreset.weekdays, tue)), 'Every weekday');
      expect(buildRrule(RepeatPreset.monthlyByWeekday, tue), 'FREQ=MONTHLY;BYDAY=1TU');
      expect(describeRrule('FREQ=MONTHLY;BYDAY=1TU'), 'Every month on the first Tue');
      expect(describeRrule('FREQ=DAILY;INTERVAL=2;COUNT=4'), 'Every 2 days, 4 times');
      expect(describeRrule(null), 'Does not repeat');
      expect(parseRrule('garbage', locationOrUtc('UTC')), isNull);
    });
  });

  group('FR-CAL-05: day layout', () {
    test('overlaps share columns; free space expands', () {
      final placed = layoutDay([
        const TimedItem('a', 540, 600), // 9-10
        const TimedItem('b', 570, 630), // 9:30-10:30
        const TimedItem('c', 600, 660), // 10-11 (fits under a)
        const TimedItem('d', 720, 780), // 12-1 alone
      ]);
      final byId = {for (final p in placed) p.value: p};
      expect(byId['a']!.columns, 2);
      expect(byId['a']!.column, 0);
      expect(byId['b']!.column, 1);
      expect(byId['c']!.column, 0);
      expect(byId['d']!.columns, 1);
      expect(byId['d']!.widthFraction, 1);
    });

    test('short events get a minimum height', () {
      final p = layoutDay([const TimedItem('x', 600, 605)]).single;
      expect(p.endMin, 620);
    });
  });

  group('FR-CAL-12: quick add', () {
    const today = LocalDate(2026, 10, 2); // Friday
    const people = {'ava': 'p-ava', 'mom': 'p-mom', 'dad': 'p-dad'};
    QuickAddResult? q(String s) => parseQuickAdd(s, today: today, peopleByWord: people);

    test('date, time and person', () {
      final r = q('Swim Saturday 9am Ava')!;
      expect(r.title, 'Swim');
      expect(r.date, const LocalDate(2026, 10, 3));
      expect(r.allDay, isFalse);
      expect(r.startMinute, 9 * 60);
      expect(r.profileIds, ['p-ava']);
    });

    test('duration and several people', () {
      final r = q('Dentist tue 3:30pm mom 1.5h')!;
      expect(r.title, 'Dentist');
      expect(r.date, const LocalDate(2026, 10, 6));
      expect(r.startMinute, 15 * 60 + 30);
      expect(r.durationMinutes, 90);
      expect(q('Soccer 5-6:30pm Ava Dad')!.durationMinutes, 90);
      expect(q('Soccer 5-6:30pm Ava Dad')!.profileIds, ['p-ava', 'p-dad']);
    });

    test('no time means all-day; next weekday; month names', () {
      final r = q('Grandma visits next Friday')!;
      expect(r.allDay, isTrue);
      expect(r.date, const LocalDate(2026, 10, 9));
      expect(r.title, 'Grandma visits');
      expect(q('Pumpkin patch Oct 17th')!.date, const LocalDate(2026, 10, 17));
      expect(q('Ski trip jan 5')!.date, const LocalDate(2027, 1, 5));
      expect(q('Pizza night tonight')!.startMinute, 19 * 60);
      expect(q('Party in 3 days')!.date, const LocalDate(2026, 10, 5));
    });

    test('"at 5" means 5 pm; connectors are dropped; ranges for all-day spans', () {
      final r = q('Dinner at Nana on sunday at 5')!;
      expect(r.title, 'Dinner at Nana');
      expect(r.date, const LocalDate(2026, 10, 4));
      expect(r.startMinute, 17 * 60);
      final span = q('Camp mon-wed')!;
      expect(span.date, const LocalDate(2026, 10, 5));
      expect(span.endDate, const LocalDate(2026, 10, 8));
    });

    test('empty or title-less input', () {
      expect(q('   '), isNull);
      expect(q('tomorrow 9am'), isNull);
    });
  });

  group('FR-CAL-15: auto icons', () {
    test('keywords, phrases and learned overrides', () {
      expect(suggestEventIcon('Ava swim lesson'), '🏊');
      expect(suggestEventIcon("Leo's birthday party"), '🎉');
      expect(suggestEventIcon('Dentist'), '🦷');
      expect(suggestEventIcon('Quarterly taxes'), '💵');
      expect(suggestEventIcon('Something else'), isNull);
      expect(suggestEventIcon('Swim', learned: {'swim': '🐬'}), '🐬');
    });
  });
}
