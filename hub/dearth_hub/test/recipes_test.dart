import 'dart:convert';
import 'dart:io';

import 'package:dearth_hub/dearth_hub.dart';
import 'package:dearth_integrations/dearth_integrations.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const _admin = {'x-dearth-admin': 'test-admin', 'content-type': 'application/json'};

/// Recipe sources on the Hub (SPEC FR-RCP-01, FR-RCP-13): every search asks
/// every enabled source and answers with one blended list; Settings →
/// Recipes switches sources and holds their keys. The network is fake.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late DearthHub hub;
  late Directory dir;
  final asked = <http.Request>[];

  http.Response json(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

  Future<http.Response> network(http.Request req) async {
    asked.add(req);
    final u = req.url;
    return switch ((u.host, u.path)) {
      ('www.themealdb.com', '/api/json/v1/1/search.php') => json({
          'meals': [
            {
              'idMeal': '52806', 'strMeal': 'Chicken Curry', 'strArea': 'Indian', 'strCategory': 'Chicken', //
              'strMealThumb': 'https://www.themealdb.com/images/media/meals/curry.jpg',
              'strInstructions': 'Fry the onions.\r\nAdd the chicken.\r\nSimmer for 20 minutes.',
              'strIngredient1': 'Chicken', 'strMeasure1': '1 lb', 'strIngredient2': 'Onion', 'strMeasure2': '1', 'strIngredient3': 'Curry Powder', 'strMeasure3': '2 tbsp',
            },
          ],
        }),
      ('en.wikibooks.org', '/w/api.php') => json({
          'query': {
            'pages': [
              for (final (i, title) in const ['Chicken Curry', 'Butter Chicken'].indexed)
                {
                  'title': 'Cookbook:$title',
                  'index': i + 1,
                  'fullurl': 'https://en.wikibooks.org/wiki/Cookbook:${title.replaceAll(' ', '_')}',
                  'revisions': [
                    {
                      'slots': {
                        'main': {'content': '==Ingredients==\n* 1 [[Cookbook:Pound|lb]] chicken\n* 1 onion\n* 2 tbsp curry powder\n==Procedure==\n# Fry the onion.\n# Simmer the chicken.'},
                      },
                    },
                  ],
                },
            ],
          },
        }),
      ('racion.app', '/api/recipes') => json({
          'items': [
            {'ID': 'chicken_rice_curry', 'Title': 'Chicken Rice Bowl', 'TimeMin': 30, 'Kid': true},
          ],
        }),
      ('racion.app', '/api/recipes/chicken_rice_curry') => json({
          'id': 'chicken_rice_curry', 'title': 'Chicken Rice Bowl', 'timeMin': 30, 'slot': 'lunch', //
          'ingredients': [
            {'name': 'Chicken breast', 'amount': 140, 'unit': 'g'},
            {'name': 'Rice', 'amount': 70, 'unit': 'g'},
          ],
          'steps': ['Cook the rice.', 'Fry the chicken.'],
        }),
      ('recipeapi.io', '/api/v1/recipes') => json({
          'data': [
            {
              'id': 7, 'name': 'Thai Green Curry', 'cuisine': 'thai', 'meal_type': 'main', 'servings': 4, 'prep_time': 15, 'cook_time': 20, //
              'instructions': ['Fry the paste.', 'Add the chicken and coconut milk.'],
              'ingredients': [
                {'name': 'Chicken', 'quantity': 500, 'unit': 'g'},
                {'name': 'Coconut milk', 'quantity': 400, 'unit': 'ml'},
              ],
            },
          ],
        }),
      _ => http.Response('no route for $u', 404),
    };
  }

  setUp(() async {
    asked.clear();
    dir = await Directory.systemTemp.createTemp('dearth-recipes-test');
    hub = await DearthHub.start(
      HubConfig(dataDir: dir.path, secretKey: 'k' * 32, port: 0, host: '127.0.0.1', adminPassword: 'test-admin', jobsEnabled: false),
      inMemory: true,
      fetcher: Fetcher(client: MockClient(network), maxRetries: 1, sleep: (_) async {}),
    );
  });

  tearDown(() async {
    await hub.stop();
    await dir.delete(recursive: true);
  });

  Uri u(String path) => Uri.parse('http://127.0.0.1:${hub.port}$path');

  Future<String> pairKitchen() async {
    Future<Map<String, Object?>> post(String path, Object body, [Map<String, String>? headers]) async =>
        jsonDecode((await http.post(u(path), headers: {'content-type': 'application/json', ...?headers}, body: jsonEncode(body))).body) as Map<String, Object?>;
    final start = await post('/api/pair/start', {'name': 'Kitchen', 'platform': 'test', 'role': 'kitchen'});
    await post('/api/admin/pair/approve', {'code': start['code'], 'role': 'kitchen', 'admin': true}, _admin);
    final status = await post('/api/pair/status', {'pairingId': start['pairingId'], 'secret': start['secret']});
    return status['token']! as String;
  }

  Future<List<Map<String, Object?>>> sources() async {
    final r = await http.get(u('/api/admin/integrations'), headers: _admin);
    expect(r.body, isNot(contains('sk_live_secret')), reason: 'keys never leave the Hub');
    return [for (final s in (jsonDecode(r.body) as Map<String, Object?>)['recipes']! as List) s as Map<String, Object?>];
  }

  Future<void> configure(Map<String, Object?> body) async {
    final r = await http.put(u('/api/admin/integrations/recipes'), headers: _admin, body: jsonEncode(body));
    expect(r.statusCode, 200, reason: r.body);
  }

  test('FR-RCP-13: a search asks every source and answers with one list; Settings → Recipes switches them and keeps their keys', () async {
    final token = await pairKitchen();
    Future<(List<Map<String, Object?>>, http.Response)> search(String q) async {
      final r = await http.get(u('/api/recipes/search?q=${Uri.encodeQueryComponent(q)}'), headers: {'authorization': 'Bearer $token'});
      expect(r.statusCode, 200, reason: r.body);
      return ([for (final x in jsonDecode(r.body) as List) x as Map<String, Object?>], r);
    }

    // Every free source, the keyed ones waiting for a key.
    final listed = await sources();
    expect([for (final s in listed) s['id']], ['themealdb', 'wikibooks', 'racion', 'recipeapi', 'tasty', 'spoonacular']);
    expect({for (final s in listed) s['id']: (s['on'], s['hasKey'])}['recipeapi'], (true, false));
    expect(listed.firstWhere((s) => s['id'] == 'tasty')['quota'], {'used': 0, 'allowed': isPositive, 'limit': 500});

    var (found, res) = await search('chicken curry');
    expect(res.headers['x-dearth-recipe-sources'], 'themealdb,wikibooks,racion,catalog');
    // TheMealDB's and Wikibooks' "Chicken Curry" are one card, with the photo.
    final curries = [for (final r in found) if (r['title'] == 'Chicken Curry') r];
    expect(curries, hasLength(1));
    expect(curries.single['source'], 'themealdb');
    expect(curries.single['alsoFrom'], contains('wikibooks'));
    expect(found.map((r) => r['title']), containsAll(['Butter Chicken', 'Chicken Rice Bowl']));
    expect(found.firstWhere((r) => r['title'] == 'Chicken Rice Bowl')['tags'], contains('kid-friendly'));

    // A key for RecipeAPI.io, and Wikibooks off.
    await configure({'source': 'recipeapi', 'apiKey': 'sk_live_secret'});
    await configure({'source': 'wikibooks', 'on': false});
    final after = await sources();
    expect({for (final s in after) s['id']: (s['on'], s['hasKey'])}, containsPair('recipeapi', (true, true)));
    expect({for (final s in after) s['id']: s['on']}, containsPair('wikibooks', false));

    asked.clear();
    (found, res) = await search('chicken curry');
    expect(res.headers['x-dearth-recipe-sources'], 'themealdb,racion,recipeapi,catalog', reason: 'the change applies at once, not after the cache expires');
    expect(asked.any((r) => r.url.host == 'en.wikibooks.org'), isFalse);
    expect(asked.firstWhere((r) => r.url.host == 'recipeapi.io').headers['authorization'], 'Bearer sk_live_secret');
    expect(found.map((r) => r['title']), contains('Thai Green Curry'));
    expect((await sources()).firstWhere((s) => s['id'] == 'recipeapi')['quota'], containsPair('used', 1), reason: 'the request counts against the month');

    final bad = await http.put(u('/api/admin/integrations/recipes'), headers: _admin, body: jsonEncode({'source': 'nope', 'on': true}));
    expect(bad.statusCode, 400);
  });
}
