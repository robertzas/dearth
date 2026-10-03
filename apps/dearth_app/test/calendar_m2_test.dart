import 'package:dearth_app/app/router.dart';
import 'package:dearth_app/core/data/calendar.dart';
import 'package:dearth_app/core/data/household.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// Calendar M2 on the demo household (SPEC §10.2): People lanes (FR-CAL-09),
/// drag to move/resize (FR-CAL-14) and weather on events (FR-CAL-19).
/// Saturday Oct 3 has the weekly swim 9:00 at the Rec Center pool, story
/// time 10:30 (Ava, Dad), the farmers market 10:30 and Pizza night 18:00
/// (nobody: the family).
void main() {
  Future<AppHarness> calendar(WidgetTester tester, String view) async {
    final h = await AppHarness.demo(tester);
    h.container.read(routerProvider).go('/calendar');
    await h.settle();
    await tester.tap(byId('cal.view.$view'));
    await h.settle();
    return h;
  }

  Future<Event> event(AppHarness h, String id) async =>
      (await h.tester.runAsync(() => (h.db.select(h.db.events)..where((e) => e.id.equals(id))).getSingle()))!;

  int at(AppHarness h, int hour, int minute, {LocalDate date = const LocalDate(2026, 10, 3)}) =>
      h.container.read(householdTimeProvider).msAt(date, hour, minute);

  /// One hour of grid, measured from story time's 45-minute block.
  double hourOf(WidgetTester tester) => (tester.getSize(byId('event.block.ev-story').first).height + 2) * 60 / 45;

  /// Long-presses [from] for the deliberate 600 ms, then drags by [by].
  Future<void> drag(AppHarness h, Offset from, Offset by) async {
    final g = await h.tester.startGesture(from);
    await h.tester.pump(const Duration(milliseconds: 700));
    await g.moveBy(by / 2);
    await h.tester.pump();
    await g.moveBy(by / 2);
    await h.tester.pump();
    await g.up();
    await h.settle();
  }

  testWidgets('FR-CAL-09: People shows a lane per person, a Family lane, and pets only when busy', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await calendar(tester, 'people');
    for (final lane in ['family', 'p-mom', 'p-dad', 'p-ava']) {
      expect(byId('cal.lane.2026-10-03.$lane'), findsOneWidget, reason: lane);
    }
    expect(byId('cal.lane.2026-10-03.p-biscuit'), findsNothing, reason: 'the dog has nothing on today');
    // Story time is Ava's and Dad's: it shows in both lanes.
    expect(byId('event.block.ev-story'), findsNWidgets(2));
    expect(byId('event.block.ev-pizza'), findsOneWidget);

    await tester.tap(byId('cal.people.3-days'));
    await h.settle();
    expect(byId('cal.lane.2026-10-05.p-ava'), findsOneWidget);
    expect(byId('cal.dayhead.2026-10-04'), findsOneWidget);
    expectNoFallbackText();
    await h.shutdown();
    handle.dispose();
  });

  testWidgets('FR-CAL-14: long-press and drag moves an event in 15-minute steps; Undo puts it back', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await calendar(tester, 'day');
    final hour = hourOf(tester);
    // A little over an hour down snaps to exactly one hour later.
    await drag(h, tester.getCenter(byId('event.block.ev-story')), Offset(0, hour * 1.05));
    var e = await event(h, 'ev-story');
    expect((e.startMs, e.endMs), (at(h, 11, 30), at(h, 12, 15)));
    expect(find.textContaining('Moved “Library story time”'), findsOneWidget);

    await tester.tap(byId('toast.action'));
    await h.settle();
    e = await event(h, 'ev-story');
    expect((e.startMs, e.endMs), (at(h, 10, 30), at(h, 11, 15)));
    await h.shutdown();
    handle.dispose();
  });

  testWidgets('FR-CAL-14: dragging the bottom edge changes the length', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await calendar(tester, 'day');
    final hour = hourOf(tester);
    final block = tester.getRect(byId('event.block.ev-story'));
    await drag(h, Offset(block.center.dx, block.bottom - 4), Offset(0, hour / 2));
    final e = await event(h, 'ev-story');
    expect((e.startMs, e.endMs), (at(h, 10, 30), at(h, 11, 45)));
    await h.shutdown();
    handle.dispose();
  });

  testWidgets('FR-CAL-14: moving one day of a repeating event asks which days, and the rest stay', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await calendar(tester, 'week');
    final hour = hourOf(tester);
    await drag(h, tester.getCenter(byId('event.block.ev-swim')), Offset(0, -hour));
    expect(byId('event.scope'), findsOneWidget);
    await tester.tap(byId('event.scope.single'));
    await h.settle();
    final rows = await tester.runAsync(() => (h.db.select(h.db.events)..where((e) => e.recurringParentId.equals('ev-swim'))).get());
    expect(rows, hasLength(1));
    expect((rows!.single.startMs, rows.single.originalStartMs), (at(h, 8, 0), at(h, 9, 0)));
    expect((await event(h, 'ev-swim')).rrule, 'FREQ=WEEKLY;BYDAY=SA', reason: 'the series is untouched');
    await h.shutdown();
    handle.dispose();
  });

  testWidgets('FR-CAL-14: with PINs set, a long press asks for a grown-up instead of lifting', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await calendar(tester, 'day');
    await h.write((w) => [w.op('profiles', 'p-mom', {'pin_hash': hashPin('2468', iterations: 1000)})]);
    await drag(h, tester.getCenter(byId('event.block.ev-story')), const Offset(0, 120));
    expect(byId('grownup.sheet'), findsOneWidget);
    final e = await event(h, 'ev-story');
    expect(e.startMs, at(h, 10, 30));
    await h.shutdown();
    handle.dispose();
  });

  testWidgets('FR-CAL-19: events with a place or outdoors show their forecast; others don’t', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await calendar(tester, 'agenda');
    expect(byId('event.weather.ev-market'), findsOneWidget, reason: 'outdoor keyword');
    expect(byId('event.weather.ev-swim'), findsWidgets, reason: 'it has a location');
    expect(byId('event.weather.ev-pizza'), findsNothing);
    await tester.tap(byId('event.ev-market').first);
    await h.settle();
    expect(byId('event.sheet.weather'), findsOneWidget);
    await h.shutdown();
    handle.dispose();
  });

  /// Titles of everything on [d], once the data has loaded.
  Future<List<String>> titlesOn(AppHarness h, LocalDate d) async {
    final sub = h.container.listen(occurrencesProvider(DayRange.single(d)), (_, _) {});
    await h.settle(5);
    final titles = [for (final o in sub.read().value ?? const <Occurrence>[]) o.event.title];
    sub.close();
    return titles;
  }

  testWidgets('FR-CAL-18: holidays and birthdays join the calendar, read-only and without duplicates', (tester) async {
    final h = await AppHarness.demo(tester);
    // A Denver household gets US holidays and family days.
    expect(await titlesOn(h, const LocalDate(2026, 10, 31)), contains('Halloween'));
    expect(await titlesOn(h, const LocalDate(2026, 11, 26)), contains('Thanksgiving'));
    expect(h.container.read(calendarSourceMapProvider)[VirtualCalendars.holidays]!.writable, isFalse);
    // Ava already has a birthday event: no second one.
    final ava = LocalDate.parse((await tester.runAsync(() => (h.db.select(h.db.profiles)..where((p) => p.id.equals('p-ava'))).getSingle()))!.birthday!);
    final next = ava.addMonths(12 * (2027 - ava.year));
    expect((await titlesOn(h, next)).where((t) => t.contains('Ava')), ["Ava's birthday"]);
    // A grown-up's birthday, without the age.
    await h.write((w) => [w.op('profiles', 'p-mom', {'birthday': '1990-10-10'})]);
    expect(await titlesOn(h, const LocalDate(2026, 10, 10)), contains('Mom’s birthday'));
    // Halloween counts down for the kids.
    final countdowns = h.container.read(countdownsProvider);
    expect(countdowns.map((c) => c.occurrence.event.id), contains('holiday:US:2026-10-31:halloween'));
    // Switched off in Settings, the holidays go.
    await h.write((w) => [settingOp(w, SettingKeys.calendarVirtual, {'holidays': false})]);
    expect(await titlesOn(h, const LocalDate(2026, 10, 31)), isNot(contains('Halloween')));
    await h.shutdown();
  });
}

