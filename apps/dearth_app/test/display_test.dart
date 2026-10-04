import 'package:dearth_app/app/display_state.dart';
import 'package:dearth_app/core/data/household.dart';
import 'package:dearth_app/core/env.dart';
import 'package:dearth_app/core/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The idle engine (SPEC §10.12, FR-DSP-01) with its clock in the test's
/// hands. App-level tests run with it off (e2e), so it gets its own.
void main() {
  testWidgets('FR-DSP-01: a tap on the photo frame wakes it for a whole idle timeout', (tester) async {
    var now = 1000000;
    final c = ProviderContainer(overrides: [
      envProvider.overrideWithValue(const AppEnv()),
      idleClockProvider.overrideWithValue(() => now),
      deviceSettingsProvider.overrideWithValue(const DeviceSettings(idleMinutes: 1)),
      isNightTimeProvider.overrideWithValue(false),
      householdIdleMinutesProvider.overrideWithValue(5),
    ]);
    addTearDown(c.dispose);
    final display = c.read(displayProvider.notifier);
    DisplayMode mode() => c.read(displayProvider).mode;
    Future<void> wait(Duration d) async {
      now += d.inMilliseconds;
      await tester.pump(d);
    }

    await tester.pump();
    display.activity();
    await wait(const Duration(seconds: 61));
    expect(mode(), DisplayMode.screensaver);

    display.wake();
    await wait(const Duration(seconds: 1));
    expect(mode(), DisplayMode.active, reason: 'it used to fall straight back to the photos');
    await wait(const Duration(seconds: 58));
    expect(mode(), DisplayMode.active);
    await wait(const Duration(seconds: 2));
    expect(mode(), DisplayMode.screensaver, reason: 'one idle timeout after the tap');
  });

  testWidgets('FR-DSP-01: touches keep the display awake; the night clock wakes the same way', (tester) async {
    var now = 1000000;
    var night = false;
    final c = ProviderContainer(overrides: [
      envProvider.overrideWithValue(const AppEnv()),
      idleClockProvider.overrideWithValue(() => now),
      deviceSettingsProvider.overrideWithValue(const DeviceSettings(idleMinutes: 2)),
      isNightTimeProvider.overrideWith((ref) => night),
      householdIdleMinutesProvider.overrideWithValue(5),
    ]);
    addTearDown(c.dispose);
    final display = c.read(displayProvider.notifier);
    DisplayMode mode() => c.read(displayProvider).mode;
    Future<void> wait(Duration d) async {
      now += d.inMilliseconds;
      await tester.pump(d);
    }

    await tester.pump();
    for (var i = 0; i < 4; i++) {
      display.activity();
      await wait(const Duration(seconds: 90));
    }
    expect(mode(), DisplayMode.active, reason: 'a touch every 90 s never lets a 2 min timeout run out');

    night = true;
    c.invalidate(isNightTimeProvider);
    await wait(const Duration(minutes: 3));
    expect(mode(), DisplayMode.night);
    display.wake();
    await wait(const Duration(seconds: 30));
    expect(mode(), DisplayMode.active, reason: 'a dim UI for 60 s after a touch at night');
    await wait(const Duration(seconds: 31));
    expect(mode(), DisplayMode.night);
  });
}
