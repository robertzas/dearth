import 'dart:ui' show Tristate;

import 'package:dearth_app/app/router.dart';
import 'package:dearth_app/core/data/household.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// Household settings (SPEC FR-SET-02).
void main() {
  testWidgets('§14.3: the weather updates every 10 minutes until the household picks another pace', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await AppHarness.demo(tester);
    h.container.read(routerProvider).go('/settings/household');
    await h.settle();
    expect(tester.getSemantics(byId('household.weather.10-min')).flagsCollection.isSelected, Tristate.isTrue);
    await tester.tap(byId('household.weather.30-min'));
    await h.settle();
    expect(h.container.read(settingMapProvider(SettingKeys.weatherRefresh)), {'minutes': 30});
    expect(tester.getSemantics(byId('household.weather.30-min')).flagsCollection.isSelected, Tristate.isTrue);
    expectNoFallbackText();
    await h.shutdown();
    handle.dispose();
  });
}
