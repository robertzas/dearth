import 'package:dearth_app/app/reminders.dart';
import 'package:dearth_app/app/router.dart';
import 'package:dearth_app/core/data/household.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show EditableText, Text;

import 'support/app_harness.dart';

/// Reminders (SPEC FR-CAL-13 field, FR-CAL-20 on-display banners).
void main() {
  final denver = HouseholdTime.named('America/Denver');
  const today = LocalDate(2026, 10, 3);
  int at(int h, [int m = 0, LocalDate d = today]) => denver.msAt(d, h, m);

  Profile kid(String name, {String? nickname}) => Profile(
        id: 'p-$name',
        syncClock: '{}',
        syncHlc: '',
        syncSeq: 0,
        deleted: false,
        name: name,
        nickname: nickname,
        role: ProfileRole.child,
        color: 0,
        sortKey: 'm',
        archived: false,
      );

  DueReminder due(String title, int startMs, {int lead = 15, bool allDay = false, LocalDate? date, String? location}) {
    final e = Event(
      id: 'e',
      syncClock: '{}',
      syncHlc: '',
      syncSeq: 0,
      deleted: false,
      sourceId: 'local',
      title: title,
      startMs: startMs,
      endMs: startMs + 3600000,
      allDay: allDay,
      exdates: '[]',
      location: location,
      countdown: false,
      reminders: '[$lead]',
      profileIds: '[]',
      status: 'confirmed',
    );
    final o = Occurrence(event: e, startMs: startMs, endMs: startMs + 3600000, allDay: allDay, startDate: date, endDate: date?.addDays(1));
    final anchor = reminderAnchorMs(o, denver);
    return DueReminder(o, lead, anchor - lead * 60000, anchor);
  }

  group('FR-CAL-20: banner wording', () {
    test('grown-ups get the title and when', () {
      final (title, detail) = reminderText(due('Dentist', at(15, 30), location: 'Smile Dental'), kids: const [], nowMs: at(15, 15), time: denver, h24: false);
      expect(title, 'Dentist');
      expect(detail, 'In 15 minutes · 3:30–4:30 PM · Smile Dental');
    });

    test('kids are addressed by name (nickname first), with the title mid-sentence', () {
      final ava = kid('Ava', nickname: 'Avie');
      expect(reminderText(due('Swim lesson', at(9)), kids: [ava], nowMs: at(8, 45), time: denver, h24: false).$1, 'Avie, swim lesson in 15 minutes!');
      expect(reminderText(due('Swim lesson', at(9)), kids: [ava], nowMs: at(9), time: denver, h24: false).$1, 'Avie, it’s time for swim lesson!');
      expect(reminderText(due('PTA night', at(18)), kids: [kid('Ava'), kid('Leo')], nowMs: at(17), time: denver, h24: false).$1, 'Ava and Leo, PTA night at 6:00 PM!');
      expect(reminderText(due("Ava's party", at(9, 0, today.addDays(1)), lead: 1440), kids: [kid('Ava')], nowMs: at(9), time: denver, h24: false).$1,
          "Ava, Ava's party tomorrow at 9:00 AM!");
    });

    test('later days are named, never lower-cased', () {
      const monday = LocalDate(2026, 10, 5);
      expect(reminderText(due('Swim lesson', at(9, 0, monday), lead: 2880), kids: [kid('Ava')], nowMs: at(9), time: denver, h24: false).$1, 'Ava, swim lesson on Monday at 9:00 AM!');
    });

    test('all-day reminders talk about the day', () {
      const sunday = LocalDate(2026, 10, 4);
      expect(reminderText(due('Grandma visits', 0, lead: 0, allDay: true, date: today), kids: [kid('Ava')], nowMs: at(8), time: denver, h24: false).$1,
          'Ava, grandma visits today!');
      final (title, detail) = reminderText(due('Grandma visits', 0, lead: 1440, allDay: true, date: sunday), kids: const [], nowMs: at(8), time: denver, h24: false);
      expect((title, detail), ('Grandma visits', 'Tomorrow'));
    });

    test('names join naturally', () {
      expect(joinNames(['Ava']), 'Ava');
      expect(joinNames(['Ava', 'Leo', 'Max']), 'Ava, Leo and Max');
    });
  });

  testWidgets('FR-CAL-20: a due reminder shows a banner once, addressed to the kid; OK dismisses it for good', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await AppHarness.demo(tester);
    final time = h.container.read(householdTimeProvider);
    final now = time.nowMs() ~/ 60000 * 60000;
    await h.write((w) => [
          w.op('events', 'ev-piano', {
            'title': 'Piano',
            'source_id': Ids.familyCalendar,
            'start_ms': now + 10 * 60000,
            'end_ms': now + 40 * 60000,
            'profile_ids': ['p-ava'],
            'reminders': [10],
          }),
        ]);
    await h.settle();
    expect(byId('reminder.banner'), findsOneWidget);
    final title = find.descendant(of: byId('reminder.title'), matching: find.byType(Text));
    expect(tester.widget<Text>(title).data, 'Ava, piano in 10 minutes!');
    expectNoFallbackText(byId('reminder.banner'));

    await tester.tap(byId('reminder.ok'));
    await h.settle();
    expect(byId('reminder.banner'), findsNothing);
    // Another change re-runs the check; the fired reminder stays quiet.
    await h.write((w) => [w.op('events', 'ev-piano', {'title': 'Piano lesson'})]);
    await h.settle();
    expect(byId('reminder.banner'), findsNothing);
    final fired = await tester.runAsync(() => h.db.kvGet('reminders.fired'));
    expect(fired, contains('ev-piano@${now + 10 * 60000}@10'));
    await h.shutdown();
    handle.dispose();
  });

  testWidgets('FR-CAL-13: new events start with their calendar’s default reminders, and the editor saves them', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await AppHarness.demo(tester);
    await h.write((w) => [settingOp(w, SettingKeys.calendarReminders, {Ids.familyCalendar: [15]})]);
    h.container.read(routerProvider).go('/calendar');
    await h.settle();
    await tester.tap(byId('cal.add'));
    await h.settle();
    await tester.enterText(find.descendant(of: byId('editor.title'), matching: find.byType(EditableText)), 'Haircut');
    await tester.tap(byId('editor.remind.60'));
    await h.settle(5);
    await tester.ensureVisible(byId('editor.save'));
    await tester.tap(byId('editor.save'));
    await h.settle();
    final rows = await tester.runAsync(() => (h.db.select(h.db.events)..where((e) => e.title.equals('Haircut'))).get());
    expect(decodeReminders(rows!.single.reminders), [15, 60]);
    await h.shutdown();
    handle.dispose();
  });
}
