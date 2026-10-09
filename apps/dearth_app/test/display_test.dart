import 'dart:async';

import 'package:dearth_app/app/display_state.dart';
import 'package:dearth_app/app/frame.dart';
import 'package:dearth_app/core/data/household.dart';
import 'package:dearth_app/core/env.dart';
import 'package:dearth_app/core/platform/freekiosk.dart';
import 'package:dearth_app/core/providers.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

  testWidgets('FR-DSP-03: "screen off" at night: FreeKiosk turns the panel off, a timer and the morning turn it back on', (tester) async {
    var now = 1000000;
    var night = false;
    final calls = <String>[];
    final keys = <String?>{};
    var woken = 0;
    final kiosk = FreeKiosk(
      port: 8080,
      key: 'k',
      // No expect() in here: it would run inside a pump (a guarded-call conflict).
      client: MockClient((req) async {
        keys.add(req.headers['X-Api-Key']);
        calls.add(req.url.path);
        return http.Response('{"success":true,"data":{}}', 200);
      }),
    );
    final c = ProviderContainer(overrides: [
      envProvider.overrideWithValue(const AppEnv()),
      idleClockProvider.overrideWithValue(() => now),
      deviceSettingsProvider.overrideWithValue(const DeviceSettings(idleMinutes: 2, nightScreen: 'off')),
      isNightTimeProvider.overrideWith((ref) => night),
      householdIdleMinutesProvider.overrideWithValue(5),
      lightReadingsProvider.overrideWithValue(const Stream.empty()),
      freeKioskProvider.overrideWith((ref) async => kiosk),
      screenWakerProvider.overrideWithValue(() async => woken++),
      brightnessSinkProvider.overrideWithValue((_) async {}),
    ]);
    c.listen(screenPowerProvider, (_, _) {});
    final display = c.read(displayProvider.notifier);
    DisplayMode mode() => c.read(displayProvider).mode;
    Future<void> wait(Duration d) async {
      now += d.inMilliseconds;
      await tester.pump(d);
    }

    await tester.pump();
    display.activity();
    night = true;
    c.invalidate(isNightTimeProvider);
    await wait(const Duration(minutes: 3));
    expect(mode(), DisplayMode.off);
    await tester.pump();
    expect(calls, ['/api/screen/off']);
    expect(c.read(screenPowerProvider), isTrue);

    // A kitchen timer rings in the dark.
    display.wake();
    await tester.pump();
    await tester.pump();
    expect(calls.last, '/api/screen/on');
    expect(woken, 1, reason: 'the app’s own wake lock too, so the morning never hangs on FreeKiosk');
    await wait(const Duration(seconds: 61));
    expect(mode(), DisplayMode.off, reason: 'back off a minute after the timer is seen to');

    night = false;
    c.invalidate(isNightTimeProvider);
    await wait(const Duration(seconds: 1));
    expect(mode(), DisplayMode.screensaver, reason: 'morning: the photo frame');
    await tester.pump();
    expect(calls.where((p) => p == '/api/screen/on'), hasLength(2));
    expect(woken, 2);
    expect(keys, {'k'}, reason: 'every call carries the key');
    // Stops the idle timer before the test ends.
    c.dispose();
  });

  testWidgets('§10.12: night when the room goes dark shows the clock (never the screen off) and the light wakes it', (tester) async {
    var now = 1000000;
    final light = StreamController<double>();
    addTearDown(light.close);
    final c = ProviderContainer(overrides: [
      envProvider.overrideWithValue(const AppEnv()),
      idleClockProvider.overrideWithValue(() => now),
      deviceSettingsProvider.overrideWithValue(const DeviceSettings(idleMinutes: 2, darkRoomNight: true, nightScreen: 'off')),
      isNightTimeProvider.overrideWithValue(false),
      householdIdleMinutesProvider.overrideWithValue(5),
      lightReadingsProvider.overrideWithValue(light.stream),
      brightnessSinkProvider.overrideWithValue((_) async {}),
    ]);
    DisplayMode mode() => c.read(displayProvider).mode;
    Future<void> wait(Duration d) async {
      for (var i = 0; i < d.inSeconds; i++) {
        now += 1000;
        await tester.pump(const Duration(seconds: 1));
      }
    }

    await tester.pump();
    c.read(displayProvider.notifier).activity();
    light.add(150);
    await wait(const Duration(minutes: 3));
    expect(mode(), DisplayMode.screensaver);
    light.add(0.5);
    await wait(const Duration(minutes: 1));
    expect(mode(), DisplayMode.screensaver, reason: 'a minute of dark isn’t night yet');
    await wait(const Duration(minutes: 2));
    expect(mode(), DisplayMode.night, reason: 'off is for the schedule, which ends it; a dark room shows the clock');
    light.add(200);
    await wait(const Duration(seconds: 30));
    expect(mode(), DisplayMode.screensaver);
    // Stops the room's one-second tick before the test ends.
    c.dispose();
  });

  testWidgets('FR-DSP-02: the brightness follows the room, calmer for the photos, barely lit at night; phones keep their own', (tester) async {
    var now = 1000000;
    var night = false;
    var settings = const DeviceSettings(idleMinutes: 2);
    final applied = <double?>[];
    final light = StreamController<double>();
    addTearDown(light.close);
    final c = ProviderContainer(overrides: [
      envProvider.overrideWithValue(const AppEnv()),
      idleClockProvider.overrideWithValue(() => now),
      deviceSettingsProvider.overrideWith((ref) => settings),
      isNightTimeProvider.overrideWith((ref) => night),
      householdIdleMinutesProvider.overrideWithValue(5),
      lightReadingsProvider.overrideWithValue(light.stream),
      brightnessSinkProvider.overrideWithValue((v) async => applied.add(v)),
    ]);
    addTearDown(c.dispose);
    c.listen(brightnessProvider, (_, _) {});
    Future<void> wait(Duration d) async {
      for (var i = 0; i < d.inMilliseconds ~/ 250; i++) {
        now += 250;
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    await tester.pump();
    c.read(displayProvider.notifier).activity();
    await wait(const Duration(seconds: 1));
    expect(applied, isEmpty, reason: 'no reading yet: the system’s brightness stands');
    light.add(110);
    await wait(const Duration(seconds: 1));
    final day = c.read(brightnessProvider)!;
    expect(day, closeTo(targetBrightness(BrightnessScene.active, 110)!, 0.01));
    expect(applied.last, day);

    // The lights go down: it follows, gently, without flickering on the way.
    light.add(5);
    await wait(const Duration(seconds: 30));
    final dim = c.read(brightnessProvider)!;
    expect(dim, lessThan(day - 0.2));
    for (var i = 1; i < applied.length; i++) {
      expect((applied[i]! - applied[i - 1]!).abs(), lessThanOrEqualTo(0.13), reason: 'no jumps within a scene');
    }

    await wait(const Duration(minutes: 2));
    expect(c.read(displayProvider).mode, DisplayMode.screensaver);
    expect(c.read(brightnessProvider)!, lessThanOrEqualTo(dim));

    night = true;
    c.invalidate(isNightTimeProvider);
    await wait(const Duration(seconds: 1));
    expect(c.read(displayProvider).mode, DisplayMode.night);
    expect(c.read(brightnessProvider)!, lessThanOrEqualTo(0.12), reason: 'the night clock, at once');

    settings = const DeviceSettings(role: DeviceRole.personal);
    c.invalidate(deviceSettingsProvider);
    await wait(const Duration(seconds: 1));
    expect(c.read(brightnessProvider), isNull);
    expect(applied.last, isNull, reason: 'handed back to the system');
  });
}
