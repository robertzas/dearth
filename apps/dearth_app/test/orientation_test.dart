import 'package:dearth_app/app/display_state.dart';
import 'package:dearth_app/app/router.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// Orientation per display (SPEC FR-DEV-05).
void main() {
  test('FR-DEV-05: a wall display follows the accelerometer; a personal one keeps its rotation lock', () {
    expect(orientationMode(personal: false, setting: 'auto'), 'sensor', reason: 'frame ROMs switch auto-rotate off at boot');
    expect(orientationMode(personal: true, setting: 'auto'), 'user');
    expect(orientationMode(personal: false, setting: 'landscape'), 'landscape');
    expect(orientationMode(personal: true, setting: 'portrait'), 'portrait');
  });

  testWidgets('FR-DEV-05: the display asks Android for its orientation, and the setting changes it', (tester) async {
    final asked = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('app.dearth/display'), (call) async {
      if (call.method == 'setOrientation') asked.add(call.arguments);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('app.dearth/display'), null));
    final h = await AppHarness.demo(tester);
    expect(asked.last, 'sensor', reason: 'the demo display is a kitchen display');

    h.container.read(routerProvider).go('/settings/device');
    await h.settle();
    await tester.tap(byId('device.orientation.landscape'));
    await h.settle();
    expect(asked.last, 'landscape');
    await tester.tap(byId('device.orientation.rotate'));
    await h.settle();
    expect(asked.last, 'sensor');
    await h.shutdown();
  });

  testWidgets('a wall display hides the empty system bars; a personal device keeps them', (tester) async {
    final chrome = <(String, Object?)>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method.startsWith('SystemChrome.setEnabledSystemUI')) chrome.add((call.method, call.arguments));
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final h = await AppHarness.demo(tester);
    expect(chrome.last, ('SystemChrome.setEnabledSystemUIMode', 'SystemUiMode.immersiveSticky'));

    h.container.read(routerProvider).go('/settings/device');
    await h.settle();
    await tester.tap(byId('device.role.personal'));
    await h.settle();
    expect(chrome.last.$1, 'SystemChrome.setEnabledSystemUIOverlays', reason: 'bars back on a phone');
    await h.shutdown();
  });
}
