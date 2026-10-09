import 'dart:convert';
import 'dart:ui' show Tristate;

import 'package:dearth_app/app/router.dart';
import 'package:dearth_app/core/data/calendar.dart';
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
    h.container.read(routerProvider).go('/settings/weather');
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

  testWidgets('FR-SET-03: Settings is grouped, and the search finds a setting inside a section and names it', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await AppHarness.demo(tester);
    h.container.read(routerProvider).go('/settings');
    await h.settle();
    // (The list is lazy: the last headings may not be built yet.)
    expect(labelOf(tester, 'settings.group.family'), 'FAMILY');
    expect(labelOf(tester, 'settings.group.display'), 'THIS DISPLAY');
    Future<void> search(String q) async {
      await tester.enterText(find.descendant(of: byId('settings.search'), matching: find.byType(EditableText)), q);
      await h.settle(3);
    }

    await search('keep');
    expect(labelOf(tester, 'settings.nav.screensaver'), 'Photo frame & night: Keep the screen on');
    expect(byId('settings.nav.household'), findsNothing);
    expect(byId('settings.nav.device'), findsNothing, reason: 'the idle settings moved to Photo frame & night');
    expect(byId('settings.group.family'), findsNothing, reason: 'no headings over a few results');
    // Every word has to match: "google tasks" is Lists, not Calendars.
    await search('google tasks');
    expect(labelOf(tester, 'settings.nav.lists'), 'Lists');
    expect(byId('settings.nav.calendars'), findsNothing);
    await search('zzzz');
    expect(byId('settings.search.none'), findsOneWidget);
    await tester.tap(byId('settings.search.clear'));
    await h.settle(3);
    expect(byId('settings.nav.household'), findsOneWidget);
    expect(byId('settings.search.none'), findsNothing);
    expectNoFallbackText();
    await h.shutdown();
    handle.dispose();
  });

  testWidgets('FR-SSV-01: this display’s idle settings sit with the photo frame’s, starting after the usual time until it picks its own', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await AppHarness.demo(tester);
    h.container.read(routerProvider).go('/settings/screensaver');
    await h.settle();
    expect(tester.getSemantics(byId('device.idle.usual')).flagsCollection.isSelected, Tristate.isTrue);
    expect(byId('ss.idle.5-min'), findsOneWidget, reason: 'the usual time for every display is on the same page');
    await tester.tap(byId('device.idle.2-min'));
    await h.settle();
    expect(h.container.read(deviceSettingsProvider).idleMinutes, 2);
    // FR-DSP-03: what the night shows, in one choice.
    expect(tester.getSemantics(byId('device.atnight.dim-clock')).flagsCollection.isSelected, Tristate.isTrue);
    await tester.tap(byId('device.atnight.screen-off'));
    await h.settle();
    expect(h.container.read(deviceSettingsProvider).nightScreen, 'off');
    expect(h.container.read(deviceSettingsProvider).nightMode, isTrue);
    await tester.tap(byId('device.atnight.photos'));
    await h.settle();
    expect(h.container.read(deviceSettingsProvider).nightMode, isFalse);
    expect(byId('device.darkroom'), findsNothing, reason: 'no light sensor in tests');
    h.container.read(routerProvider).go('/settings/device');
    await h.settle();
    expect(byId('device.idle.2-min'), findsNothing, reason: 'not on Screen & sound as well');
    expect(byId('device.theme.auto'), findsOneWidget);
    await h.shutdown();
    handle.dispose();
  });

  testWidgets('FR-WX-01, FR-WX-04: Settings → Weather adds a Weather Underground key, then a station from the nearby ones, and its forecast can be left out', (tester) async {
    final handle = tester.ensureSemantics();
    final puts = <Map<String, Object?>>[];
    var station = <String, Object?>{'hasKey': false, 'stationId': '', 'useWuForecast': true};
    http.Response ok(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    final api = HubApi(Uri.parse('http://hub.test'), token: 't', client: MockClient((req) async {
      switch ((req.method, req.url.path)) {
        case ('PUT', '/api/admin/integrations/weather'):
          final b = jsonDecode(req.body) as Map<String, Object?>;
          puts.add(b);
          station = {'hasKey': station['hasKey'] == true || (b['apiKey'] as String? ?? '').isNotEmpty, 'stationId': b['stationId'], 'useWuForecast': b['useWuForecast']};
          return ok({'ok': true});
        case ('GET', '/api/admin/integrations'):
          return ok({'weather': station});
        case ('GET', '/api/admin/weather/stations'):
          return ok([
            {'id': 'KCOBOULD12', 'name': 'Table Mesa', 'distanceKm': 1.24},
            {'id': 'KCOBOULD40', 'name': 'Chautauqua', 'distanceKm': 3.5},
          ]);
      }
      return http.Response('{}', 404);
    }));
    final h = await AppHarness.demo(tester, overrides: [hubApiProvider.overrideWithValue(api)]);
    h.container.read(routerProvider).go('/settings/weather');
    await h.settle();
    expect(labelOf(tester, 'weather.key'), 'Add a Weather Underground key');
    expect(byId('weather.station'), findsNothing, reason: 'a station needs the key first');
    expectNoFallbackText();

    await tester.tap(byId('weather.key'));
    await h.settle();
    await tester.enterText(find.descendant(of: byId('weather.key.input'), matching: find.byType(EditableText)), 'wu-key');
    await tester.tap(byId('weather.key.save'));
    await h.settle();
    expect(puts.last, {'stationId': '', 'useWuForecast': true, 'apiKey': 'wu-key'});
    expect(labelOf(tester, 'weather.key'), 'Change the Weather Underground key');

    await tester.tap(byId('weather.station'));
    await h.settle();
    expect(labelOf(tester, 'weather.station.near.KCOBOULD12'), contains('Table Mesa · 1.2 km away'));
    await tester.tap(byId('weather.station.near.KCOBOULD12'));
    await h.settle();
    expect(puts.last, {'stationId': 'KCOBOULD12', 'useWuForecast': true});
    expect(labelOf(tester, 'weather.station'), contains('KCOBOULD12'));

    await tester.tap(byId('weather.wuforecast'));
    await h.settle();
    expect(puts.last, {'stationId': 'KCOBOULD12', 'useWuForecast': false}, reason: 'turning the forecast off keeps the station');
    await h.shutdown();
    handle.dispose();
  });

  testWidgets('FR-SET-02: a new person’s birthday starts at the years, so a grown-up’s takes three taps', (tester) async {
    final h = await AppHarness.demo(tester);
    h.container.read(routerProvider).go('/settings/people');
    await h.settle();
    await tester.tap(byId('people.add'));
    await h.settle();
    await tester.ensureVisible(byId('profile.birthday'));
    await tester.tap(byId('profile.birthday'));
    await h.settle();
    final year = h.container.read(todayProvider).year;
    expect(byId('picker.year.$year'), findsNothing, reason: 'opens around 30 years back');
    expect(byId('picker.year.${year + 1}'), findsNothing, reason: 'no birthdays in the future');
    await tester.tap(byId('picker.year.1985'));
    await h.settle();
    await tester.tap(byId('picker.month.3'));
    await h.settle();
    expect(find.text('March 1985'), findsOneWidget);
    expect(byId('picker.date.today'), findsNothing, reason: 'no Today button for a birthday');
    await tester.tap(byId('picker.date.1985-03-14'));
    await h.settle();
    expect(find.text('March 14, 1985'), findsOneWidget);
    expectNoFallbackText();
    await h.shutdown();
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

  testWidgets('FR-CAL-04: with Google connected, Settings → Calendars offers a shared Family calendar the Hub makes', (tester) async {
    final handle = tester.ensureSemantics();
    final posts = <Map<String, Object?>>[];
    final api = HubApi(Uri.parse('http://hub.test'), token: 't', client: MockClient((req) async {
      if (req.method == 'POST' && req.url.path == '/api/admin/calendars/google/family') {
        posts.add(jsonDecode(req.body) as Map<String, Object?>);
        return http.Response(jsonEncode({'created': true, 'source': 'gcal-a', 'shared': ['b@example.com', 'grandma@example.com'], 'failed': <String>[], 'moved': 2}), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('{}', 404);
    }));
    final h = await AppHarness.demo(tester, overrides: [hubApiProvider.overrideWithValue(api)]);
    h.container.read(routerProvider).go('/settings/calendars');
    await h.settle();
    expect(byId('calendars.family.create'), findsNothing, reason: 'no Google account yet');

    // Both parents connected their Google accounts on the Hub.
    await h.write((w) => [
          w.op('calendar_sources', 'gcal-a', {'kind': 'google', 'account_id': 'a@example.com', 'remote_id': 'primary', 'name': 'Alex', 'writable': true}),
          w.op('calendar_sources', 'gcal-b', {'kind': 'google', 'account_id': 'b@example.com', 'remote_id': 'primary', 'name': 'Bea', 'writable': true}),
        ]);
    await tester.ensureVisible(byId('calendars.family.create'));
    await tester.tap(byId('calendars.family.create'));
    await h.settle();
    expect(tester.getSemantics(byId('family.share.b@example.com')).flagsCollection.isSelected, Tristate.isTrue, reason: 'the other grown-up is shared by default');
    expect(byId('family.move'), findsOneWidget, reason: 'the demo has events on the Hub’s own Family calendar');
    await tester.enterText(find.descendant(of: byId('family.share.email'), matching: find.byType(EditableText)), 'Grandma@Example.com');
    await tester.ensureVisible(byId('family.create'));
    await tester.tap(byId('family.create'));
    await h.settle();
    expect(posts.single, {'account': 'a@example.com', 'share': ['b@example.com', 'grandma@example.com'], 'move': true});

    // The Hub made it and says so through the synced setting.
    await h.write((w) => [settingOp(w, SettingKeys.calendarGoogleFamily, {'source': 'gcal-a', 'account': 'a@example.com', 'shared': ['b@example.com']})]);
    expect(byId('calendars.family.create'), findsNothing);
    expect(labelOf(tester, 'calendars.family.made'), contains('shared with b@example.com'));
    expectNoFallbackText();
    await h.shutdown();
    handle.dispose();
  });

  testWidgets('FR-CAL-04: “Not now” tucks the offer away under Add calendars; a Google calendar called Family is offered as is', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await AppHarness.demo(tester, overrides: [hubApiProvider.overrideWithValue(HubApi(Uri.parse('http://hub.invalid')))]);
    h.container.read(routerProvider).go('/settings/calendars');
    await h.write((w) => [w.op('calendar_sources', 'gcal-a', {'kind': 'google', 'account_id': 'a@example.com', 'remote_id': 'primary', 'name': 'Alex', 'writable': true})]);
    await tester.ensureVisible(byId('calendars.family.dismiss'));
    await tester.tap(byId('calendars.family.dismiss'));
    await h.settle();
    expect(byId('calendars.family.create'), findsNothing);
    expect(byId('calendars.add.family'), findsOneWidget);

    await h.write((w) => [
          settingOp(w, SettingKeys.calendarGoogleFamily, const <String, Object?>{}),
          w.op('calendar_sources', 'gcal-fam', {'kind': 'google', 'account_id': 'a@example.com', 'remote_id': 'fam', 'name': 'Family', 'writable': true, 'enabled': false}),
        ]);
    await tester.ensureVisible(byId('calendars.family.use'));
    await tester.tap(byId('calendars.family.use'));
    await h.settle();
    final sources = {for (final s in h.container.read(calendarSourcesProvider).value!) s.id: s};
    expect((sources['gcal-fam']!.isDefault, sources['gcal-fam']!.enabled), (true, true));
    expect(sources.values.where((s) => s.isDefault).length, 1);
    expect(h.container.read(settingMapProvider(SettingKeys.calendarGoogleFamily))['source'], 'gcal-fam');
    await h.shutdown();
    handle.dispose();
  });
}
