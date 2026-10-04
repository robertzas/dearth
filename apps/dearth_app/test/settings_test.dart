import 'dart:ui' show Tristate;

import 'package:dearth_app/app/router.dart';
import 'package:dearth_app/core/data/household.dart';
import 'package:dearth_app/core/providers.dart';
import 'package:dearth_app/core/sync/hub_api.dart';
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

  testWidgets('lists sync with Google Tasks once a Hub runs it; each list switches on its own', (tester) async {
    final handle = tester.ensureSemantics();
    var h = await AppHarness.demo(tester);
    h.container.read(routerProvider).go('/settings/lists');
    await h.settle();
    expect(byId('lists.gtasks.list-shopping'), findsOneWidget);
    await tester.tap(byId('lists.gtasks.list-shopping'));
    await h.settle(4);
    expect(h.container.read(settingMapProvider(SettingKeys.listsGoogleTasks)), isEmpty, reason: 'no Hub, no sync');
    expectNoFallbackText();
    await h.shutdown();

    // On a display paired with a Hub (never called here: the Hub does the syncing).
    h = await AppHarness.demo(tester, overrides: [hubApiProvider.overrideWithValue(HubApi(Uri.parse('http://hub.invalid')))]);
    h.container.read(routerProvider).go('/settings/lists');
    await h.settle();
    await tester.tap(byId('lists.gtasks.list-shopping'));
    await h.settle(4);
    expect(h.container.read(settingMapProvider(SettingKeys.listsGoogleTasks)), {
      'lists': ['list-shopping'],
    });
    expect(labelOf(tester, 'lists.gtasks.list-shopping'), contains('Synced with'));
    await h.shutdown();
    handle.dispose();
  });
}
