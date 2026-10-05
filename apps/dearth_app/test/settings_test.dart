import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:dearth_app/app/router.dart';
import 'package:dearth_app/core/data/household.dart';
import 'package:dearth_app/core/providers.dart';
import 'package:dearth_app/core/sync/hub_api.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

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

  testWidgets('FR-RCP-13: Settings → Recipes lists the Hub’s free sources, switches them, and sends a key the Hub keeps', (tester) async {
    final handle = tester.ensureSemantics();
    final puts = <Map<String, Object?>>[];
    var wikibooksOn = true, recipeApiKey = false;
    http.Response ok(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    final api = HubApi(Uri.parse('http://hub.test'), token: 't', client: MockClient((req) async {
      if (req.method == 'PUT' && req.url.path == '/api/admin/integrations/recipes') {
        final b = jsonDecode(req.body) as Map<String, Object?>;
        puts.add(b);
        if (b['source'] == 'wikibooks') wikibooksOn = b['on'] == true;
        if (b['source'] == 'recipeapi') recipeApiKey = (b['apiKey'] as String? ?? '').isNotEmpty;
        return ok({'ok': true});
      }
      if (req.url.path == '/api/admin/integrations') {
        return ok({
          'recipes': [
            {'id': 'wikibooks', 'name': 'Wikibooks Cookbook', 'note': 'About 3,800 community recipes', 'needsKey': false, 'hasKey': true, 'on': wikibooksOn},
            {'id': 'recipeapi', 'name': 'RecipeAPI.io', 'note': 'About 50,000 recipes', 'needsKey': true, 'hasKey': recipeApiKey, 'on': true, 'quota': {'used': 3, 'allowed': 17, 'limit': 500}},
          ],
        });
      }
      return http.Response('{}', 404);
    }));
    final h = await AppHarness.demo(tester, overrides: [hubApiProvider.overrideWithValue(api)]);
    h.container.read(routerProvider).go('/settings/recipes');
    await h.settle();
    expect(labelOf(tester, 'recipes.source.wikibooks'), startsWith('Wikibooks Cookbook, On'));
    expect(labelOf(tester, 'recipes.source.recipeapi'), contains('Needs a free key'));
    expectNoFallbackText();

    await tester.tap(byId('recipes.source.wikibooks'));
    await h.settle();
    expect(puts.last, {'source': 'wikibooks', 'on': false});
    expect(labelOf(tester, 'recipes.source.wikibooks'), startsWith('Wikibooks Cookbook, Off'));

    await tester.tap(byId('recipes.key.recipeapi'));
    await h.settle();
    await tester.enterText(find.descendant(of: byId('recipes.key.input'), matching: find.byType(EditableText)), 'sk_live_test');
    await tester.tap(byId('recipes.key.save'));
    await h.settle();
    expect(puts.last, {'source': 'recipeapi', 'apiKey': 'sk_live_test'});
    expect(labelOf(tester, 'recipes.source.recipeapi'), contains('3 of 500 used this month'));
    expect(labelOf(tester, 'recipes.key.recipeapi'), 'Change the RecipeAPI.io key');
    await h.shutdown();
    handle.dispose();
  });
}
