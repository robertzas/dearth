import 'package:dearth_app/app/display_state.dart';
import 'package:dearth_app/core/providers.dart';
import 'package:dearth_app/core/sound.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// Kitchen timers (SPEC FR-TMR-01/02): presets, the floating pill, ringing
/// with an escalating chime that wakes the frame, and one-tap stop.
void main() {
  Future<List<KitchenTimer>> timers(AppHarness h) async => (await h.tester.runAsync(() => h.db.select(h.db.kitchenTimers).get()))!;

  testWidgets('FR-TMR-01: a preset starts a synced timer; the pill shows it on every screen', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await AppHarness.demo(tester);
    await tester.tap(byId('nav.timers'));
    await h.settle();
    expect(byId('timers.sheet'), findsOneWidget);
    await tester.tap(byId('timers.preset.5'));
    await h.settle();
    final rows = await timers(h);
    expect((rows.single.label, rows.single.durationMs, rows.single.status), ('5 min timer', 300000, TimerStatus.running));
    expect(byId('timer.${rows.single.id}'), findsOneWidget);
    expect(byId('timers.pill'), findsOneWidget);
    expectNoFallbackText(byId('timers.pill'));

    await tester.tap(byId('timer.${rows.single.id}.pause'));
    await h.settle();
    expect((await timers(h)).single.status, TimerStatus.paused);
    await tester.tap(byId('timer.${rows.single.id}.cancel'));
    await h.settle();
    expect((await timers(h)).single.status, TimerStatus.done);
    expect(byId('timers.pill'), findsNothing);
    await h.shutdown();
    handle.dispose();
  });

  testWidgets('FR-TMR-01: a finished timer chimes, wakes the photo frame, and one tap on the pill stops it', (tester) async {
    final handle = tester.ensureSemantics();
    final sound = RecordingSound();
    final h = await AppHarness.demo(tester, sound: sound);
    h.container.read(displayProvider.notifier).startScreensaver();
    await h.settle();
    final now = h.container.read(appClockProvider).nowMs();
    await h.write((w) => [w.op('kitchen_timers', 'tm-pasta', startTimerFields('Pasta', const Duration(minutes: 10), now - 10 * 60000 - 500))]);
    await h.settle();
    expect(h.container.read(displayProvider).mode, DisplayMode.active, reason: 'ringing wakes the display');
    expect(sound.played.first.$1, Sfx.timer);
    expect(byId('timers.pill'), findsOneWidget);

    // Chimes repeat every 6 s, a little louder each time.
    await tester.pump(const Duration(seconds: 13));
    expect(sound.played.length, greaterThanOrEqualTo(3));
    expect(sound.played[2].$2, greaterThan(sound.played[0].$2));

    await tester.tap(byId('timers.pill'));
    await h.settle();
    expect((await timers(h)).single.status, TimerStatus.done);
    final count = sound.played.length;
    await tester.pump(const Duration(seconds: 13));
    expect(sound.played.length, count, reason: 'stopped');
    await h.shutdown();
    handle.dispose();
  });
}
