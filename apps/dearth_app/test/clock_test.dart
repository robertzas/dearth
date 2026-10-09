import 'package:dearth_app/core/clock_check.dart';
import 'package:dearth_app/core/env.dart';
import 'package:dearth_app/core/providers.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// A clock the test moves by hand, as the network would set it.
class _SettableClock extends AppClock {
  _SettableClock(this.t);
  DateTime t;

  @override
  DateTime now() => t;
}

/// "Setting the time…" (SPEC §6, Appendix A: the frame has no clock
/// battery and starts at 1970 after a power cut).
void main() {
  testWidgets('a clock stuck in 1970 covers the app and holds sync back until the network sets it', (tester) async {
    final clock = _SettableClock(DateTime.utc(1970, 1, 1, 0, 0, 12));
    final h = await AppHarness.boot(tester, overrides: [appClockProvider.overrideWithValue(clock)]);
    await h.settle();
    expect(byId('clock.setting'), findsOneWidget);
    expect(h.container.read(clockSetProvider), isFalse);
    expect(h.container.read(syncClientProvider), isNull, reason: 'nothing stamped 1970 goes to the Hub');

    // Wi-Fi comes up and the time arrives.
    clock.t = DateTime.utc(2026, 10, 9, 21);
    await h.settle(30);
    expect(h.container.read(clockSetProvider), isTrue);
    expect(byId('clock.setting'), findsNothing);
    expect(await tester.runAsync(() => h.db.kvGet('clock.lastSeenMs')), '${clock.t.millisecondsSinceEpoch}', reason: 'remembered for the next start');
    await h.shutdown();
  });

  testWidgets('a clock more than a day behind the last one seen waits too, and a grown-up can say it’s right', (tester) async {
    final clock = _SettableClock(DateTime.utc(2026, 10, 1, 9));
    final h = await AppHarness.boot(tester, overrides: [appClockProvider.overrideWithValue(clock)]);
    await tester.runAsync(() => h.db.kvSet('clock.lastSeenMs', '${DateTime.utc(2026, 10, 9, 21).millisecondsSinceEpoch}'));
    h.container.invalidate(clockSetProvider);
    await h.settle();
    expect(byId('clock.setting'), findsOneWidget);
    expect(byId('clock.accept'), findsNothing, reason: 'first, a minute for the network');
    await tester.pump(const Duration(minutes: 1));
    await h.settle(2);
    await tester.tap(byId('clock.accept'));
    await h.settle();
    expect(byId('clock.setting'), findsNothing);
    expect(h.container.read(clockSetProvider), isTrue);
    await h.shutdown();
  });
}
