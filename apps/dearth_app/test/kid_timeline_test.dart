import 'package:dearth_app/app/router.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// The kid picture timeline (SPEC FR-CAL-10) on the demo household, a
/// Saturday at 8:30: Ava's "Good morning" routine (7:00) is done, swim is
/// next (9:00), and the day ends with dinner and "Bedtime" (19:00).
void main() {
  String label(WidgetTester tester, String id) => tester.getSemantics(byId(id)).label;

  testWidgets('FR-CAL-10: Ava’s day in pictures, in order, with the sun between what’s done and what’s next', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await AppHarness.demo(tester);
    h.container.read(routerProvider).go('/calendar');
    await h.settle();
    await tester.tap(byId('cal.view.timeline'));
    await h.settle();

    const ava = 'timeline.p-ava';
    expect(byId(ava), findsOneWidget);
    const order = ['routine-rt-morning', 'event-ev-swim', 'event-ev-story', 'event-ev-pizza', 'routine-rt-bedtime'];
    final xs = [for (final id in order) tester.getCenter(byId('$ava.stop.$id')).dx];
    for (var i = 1; i < xs.length; i++) {
      expect(xs[i], greaterThan(xs[i - 1]), reason: '${order[i - 1]} comes before ${order[i]}');
    }
    expect(byId('$ava.stop.dinner'), findsOneWidget, reason: 'tonight’s planned dinner');
    expect(byId('$ava.stop.event-ev-market'), findsOneWidget, reason: 'family outings with Ava in them');
    expect(byId('$ava.stop.event-ev-daycare'), findsNothing, reason: 'no daycare on Saturdays');

    expect(label(tester, '$ava.stop.routine-rt-morning'), endsWith(', done'));
    expect(label(tester, '$ava.stop.event-ev-swim'), isNot(contains('done')));
    final now = tester.getCenter(byId('$ava.now')).dx;
    expect(now, inExclusiveRange(xs[0], xs[1]), reason: '8:30 is between the morning routine and swim');

    await tester.tap(byId('$ava.stop.event-ev-swim'));
    await h.settle();
    expect(byId('timeline.sheet'), findsOneWidget);
    expect(label(tester, 'timeline.sheet.when'), 'At 9:00 AM · in 30 min');
    expect(byId('timeline.sheet.start'), findsNothing, reason: 'events have nothing to start');
    expectNoFallbackText(byId('timeline.sheet'));
    await h.shutdown();
    handle.dispose();
  });

  testWidgets('FR-CAL-10: a routine on the timeline starts from its picture; the Kids screen shows “My day”', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await AppHarness.demo(tester);
    h.container.read(routerProvider).go('/kids');
    await h.settle();
    expect(byId('kids.myday'), findsOneWidget);
    await tester.tap(byId('timeline.p-ava.stop.routine-rt-bedtime'));
    await h.settle();
    expect(label(tester, 'timeline.sheet.title'), 'Bedtime');
    await tester.tap(byId('timeline.sheet.start'));
    await h.settle();
    expect(byId('timeline.sheet'), findsNothing);
    expect(byId('routine.step'), findsOneWidget, reason: 'the run mode opens');
    await h.shutdown();
    handle.dispose();
  });
}
