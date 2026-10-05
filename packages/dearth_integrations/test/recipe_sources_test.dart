import 'dart:async';
import 'dart:convert';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_integrations/dearth_integrations.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The free recipe sources and the search that blends them (SPEC FR-RCP-01,
/// FR-RCP-13, §13.6). Wikibooks and Racion fixtures are recorded
/// responses; RecipeAPI.io's follows its documented schema and Tasty's its
/// known shape (re-record both once a key is set).
void main() {
  group('Wikibooks Cookbook', () {
    test('FR-RCP-01: one request finds recipes, with their ingredients, steps, time, cuisine and photo', () async {
      final log = <Object>[];
      final f = fakeFetcher({path('/w/api.php'): (req) {
        log.add(req.url.queryParameters);
        return json(jsonDecode(fixture('wikibooks_search.json')) as Object, headers: {'content-type': 'application/json; charset=utf-8'});
      }});
      final found = await WikibooksCookbook(f).search(const RecipeQuery(text: 'chicken curry', limit: 6));
      expect(log, hasLength(1));
      final q = log.single as Map<String, String>;
      expect(q['generator'], 'search');
      expect(q['gsrnamespace'], '102');
      expect(q['prop'], contains('revisions'));
      expect(found.length, greaterThanOrEqualTo(4));
      // In search order.
      expect(found.first.title, 'Chicken Curry');
      final curry = found.first;
      expect(curry.id, 'wikibooks:Chicken Curry');
      expect(curry.servings, 8);
      expect(curry.totalMin, 90);
      expect(curry.cuisine, 'Indian');
      expect(curry.category, 'Curry');
      expect(curry.imageUrl, startsWith('https://'));
      expect(curry.url, 'https://en.wikibooks.org/wiki/Cookbook:Chicken_Curry');
      expect(curry.attribution, contains('CC BY-SA'));
      expect(curry.ingredients.map((i) => i.group).toSet(), containsAll(['Marinade', 'Curry']));
      expect(curry.ingredients.map((i) => i.key), contains('chicken'));
      expect(curry.ingredients.every((i) => !i.raw.contains('[[')), isTrue, reason: 'links are plain text');
      expect(curry.steps.first, startsWith('Clean the chicken'));
      expect(curry.steps.any((s) => s.contains('[[')), isFalse);
      // "Curry Chicken I" loses the roman numeral.
      expect(found.map((r) => r.title), contains('Curry Chicken'));
    });

    test('a page without ingredients and a procedure is an article, not a recipe', () {
      final p = WikibooksCookbook(fakeFetcher({})).parsePage({
        'title': 'Cookbook:Onion',
        'revisions': [
          {
            'slots': {
              'main': {'content': '{{Ingredient summary}}\nThe onion is a bulb.\n==Selection==\n* Firm ones'},
            },
          },
        ],
      });
      expect(p, isNull);
    });

    test('wikitext becomes plain text; times and templates are read', () {
      expect(wikiPlain("2 [[Cookbook:Cup|cups]] '''sifted''' [[Cookbook:Flour]]<ref>King Arthur</ref>"), '2 cups sifted Cookbook:Flour');
      expect(wikiPlain('{{convert|1|lb|kg}} [[Cookbook:Beef|beef]] [[File:x.jpg|thumb]] <!-- note -->'), '1 lb beef');
      expect(minutesIn('1 hour 30 minutes'), 90);
      expect(minutesIn('45 min'), 45);
      expect(minutesIn('1½ hours'), 90);
      expect(minutesIn('overnight'), isNull);
      expect(templateParams('{{Recipe summary\n| Servings = 4\n| Image = [[File:a.jpg|300px]]\n}}', 'recipe summary'), {'servings': '4', 'image': '[[File:a.jpg|300px]]'});
      expect(cuisineOf('[[Cookbook:Cuisine of the United States|American]]'), 'American');
    });
  });

  group('Racion', () {
    Map<String, Object?> details() => jsonDecode(fixture('racion_details.json')) as Map<String, Object?>;

    test('FR-RCP-01: a search looks up its top hits for ingredients and steps (amounts per serving)', () async {
      final asked = <String>[];
      final f = fakeFetcher({
        path('/api/recipes'): (req) {
          expect(req.url.queryParameters, containsPair('country', 'US'));
          expect(req.url.queryParameters, containsPair('lang', 'en'));
          final search = jsonDecode(fixture('racion_search.json')) as Map<String, Object?>;
          // One of them is marked for kids.
          ((search['items']! as List).first as Map<String, Object?>)['Kid'] = true;
          return json(search, headers: {'x-ratelimit-remaining-hour': '45', 'x-ratelimit-remaining-day': '290'});
        },
        (req) => req.url.path.startsWith('/api/recipes/'): (req) {
          final id = req.url.pathSegments.last;
          asked.add(id);
          return json(details()[id]!, headers: {'x-ratelimit-remaining-hour': '44'});
        },
      });
      final found = await Racion(f).search(const RecipeQuery(text: 'chicken', limit: 12));
      expect(asked, hasLength(4), reason: 'four lookups at most per search');
      expect(found, hasLength(4));
      final bowl = found.firstWhere((r) => r.sourceId == 'chicken_bowl_rice');
      expect(bowl.title, 'Chicken Bowl with Rice and Vegetables');
      expect(bowl.servings, 1);
      expect(bowl.totalMin, 30);
      expect(bowl.category, 'Lunch');
      expect(bowl.imageUrl, 'https://racion.app/images/recipes/chicken_bowl_rice.webp');
      expect(bowl.url, 'https://racion.app/en/recipe/chicken_bowl_rice');
      final chicken = bowl.ingredients.firstWhere((i) => i.key.contains('chicken'));
      expect((chicken.qty, chicken.unit), (140, 'g'));
      expect(bowl.ingredients.firstWhere((i) => i.name.toLowerCase().contains('egg')).unit, '', reason: '"pcs" is a count, not a unit');
      expect(bowl.steps, hasLength(6));
      expect(found.first.tags, contains('kid-friendly'));
    });

    test('it stops before Racion runs out, as its headers count down', () async {
      final f = fakeFetcher({
        path('/api/recipes'): (_) => json({'items': <Object>[]}, headers: {'x-ratelimit-remaining-hour': '3', 'x-ratelimit-remaining-day': '200'}),
      });
      final racion = Racion(f);
      expect(await racion.search(const RecipeQuery(text: 'soup', limit: 1)), isEmpty);
      // Three left this hour, and a search needs up to five.
      await expectLater(racion.search(const RecipeQuery(text: 'soup')), throwsA(isA<QuotaExceededException>()));
      expect(racion.canSpend(5, now: DateTime.now().add(const Duration(minutes: 61))), isTrue, reason: 'a new hour');
    });
  });

  group('RecipeAPI.io', () {
    test('FR-RCP-01: sends the key, maps the filters, and normalizes the recipes', () async {
      final f = fakeFetcher({path('/api/v1/recipes'): (req) {
        expect(req.headers['authorization'], 'Bearer sk_live_test');
        expect(req.url.queryParameters, containsPair('search', 'beef'));
        expect(req.url.queryParameters, containsPair('cuisine', 'mexican'));
        expect(req.url.queryParameters, containsPair('dietary_tags', 'gluten_free'));
        expect(req.url.queryParameters['per_page'], '10', reason: 'the free plan pages ten');
        return text(fixture('recipeapi_search.json'));
      }});
      final found = await RecipeApiIo(f, 'sk_live_test').search(const RecipeQuery(text: 'beef', cuisine: 'Mexican', diet: 'gluten-free'));
      expect(found, hasLength(2));
      final tostadas = found.first;
      expect(tostadas.id, 'recipeapi:449');
      expect((tostadas.servings, tostadas.prepMin, tostadas.cookMin, tostadas.totalMin), (6, 15, 15, 30));
      expect(tostadas.cuisine, 'American');
      expect(tostadas.category, 'Main course');
      expect(tostadas.diets, ['nut free']);
      expect(tostadas.imageUrl, isNull, reason: 'it has no photos');
      expect(tostadas.ingredients.firstWhere((i) => i.key.contains('beef')).unit, 'lb');
      expect(tostadas.ingredients.firstWhere((i) => i.name.contains('Sour')).optional, isTrue);
      expect(tostadas.steps, hasLength(4));
      expect(found.last.category, 'Soup');
    });

    test('the month\'s 500 requests are spread over the month', () async {
      var now = DateTime.utc(2026, 11, 1, 9);
      final budget = QuotaBudget(limit: 500, period: QuotaPeriod.month, clock: () => now);
      final f = fakeFetcher({path('/api/v1/recipes'): (_) => text(fixture('recipeapi_search.json'))});
      final api = RecipeApiIo(f, 'k', budget: budget);
      // November 1st may spend a thirtieth: 17 searches.
      for (var i = 0; i < 17; i++) {
        await api.search(const RecipeQuery(text: 'beef'));
      }
      await expectLater(api.search(const RecipeQuery(text: 'beef')), throwsA(isA<QuotaExceededException>()));
      now = DateTime.utc(2026, 11, 2, 9);
      expect(await api.search(const RecipeQuery(text: 'beef')), isNotEmpty, reason: 'a new day brings its share');
    });
  });

  group('Tasty', () {
    test('FR-RCP-01: parses recipes, opens compilations, skips videos, and counts what RapidAPI says is left', () async {
      final budget = QuotaBudget(limit: 500, period: QuotaPeriod.month, spread: false);
      final f = fakeFetcher({path('/recipes/list'): (req) {
        expect(req.headers['x-rapidapi-key'], 'rk');
        expect(req.headers['x-rapidapi-host'], 'tasty.p.rapidapi.com');
        expect(req.url.queryParameters, containsPair('q', 'curry'));
        return json(jsonDecode(fixture('tasty_list.json')) as Object, headers: {'x-ratelimit-requests-remaining': '420'});
      }});
      final found = await TastyApi(f, 'rk', budget: budget).search(const RecipeQuery(text: 'curry'));
      expect(found.map((r) => r.title), ['One-Pot Chicken Curry', 'Fluffy Pancakes']);
      final curry = found.first;
      expect((curry.servings, curry.prepMin, curry.cookMin, curry.totalMin), (4, 10, 25, 35));
      expect(curry.cuisine, 'Indian');
      expect(curry.category, 'Dinner');
      expect(curry.diets, ['gluten-free']);
      expect(curry.tags, ['quick']);
      expect(curry.steps, ['Brown the chicken in a large pot.', 'Simmer everything for 20 minutes.'], reason: 'in their order');
      expect(curry.ingredients.firstWhere((i) => i.key.contains('chicken')).unit, 'lb');
      expect(curry.ingredients.last.group, 'For serving');
      expect(curry.ingredients.last.name, contains('rice'), reason: '"n/a" lines are rebuilt from the measurement');
      expect(curry.popularity, 1830);
      expect(curry.url, 'https://tasty.co/recipe/one-pot-chicken-curry');
      expect(found.last.totalMin, isNull, reason: 'zero means unknown');
      expect(budget.used, 80);
    });
  });

  group('QuotaBudget', () {
    test('a month is spread by day, saved and restored, and starts over next month', () {
      var now = DateTime.utc(2026, 11, 10, 12);
      final b = QuotaBudget(limit: 300, period: QuotaPeriod.month, clock: () => now);
      expect(b.allowed, 100, reason: 'ten days of thirty');
      b.spend(99);
      expect(b.canSpend(1), isTrue);
      expect(b.canSpend(2), isFalse);
      final saved = b.toJson();
      final again = QuotaBudget(limit: 300, period: QuotaPeriod.month, clock: () => now)..restore(saved);
      expect(again.used, 99);
      now = DateTime.utc(2026, 12);
      expect(again.used, 0);
      again.restore(saved);
      expect(again.used, 0, reason: "last month's count doesn't carry over");
    });
  });

  group('FR-RCP-13: aggregated search', () {
    RecipeData r(String source, String id, String title, {String? image, List<String> ingredients = const ['chicken', 'onion', 'garlic'], int steps = 3, double? popularity, int? minutes}) => RecipeData(
          id: '$source:$id',
          source: source,
          sourceId: id,
          title: title,
          imageUrl: image,
          totalMin: minutes,
          ingredients: [for (final i in ingredients) parseIngredientLine('1 $i')],
          steps: [for (var i = 0; i < steps; i++) 'Step $i'],
          popularity: popularity,
        );

    test('titles, courses, cuisines and diets come out in one shape', () {
      expect(tidyTitle('EASY CHICKEN CURRY RECIPE 🍛'), 'Easy Chicken Curry');
      expect(tidyTitle('Pasta with Peas!'), 'Pasta with Peas');
      expect(tidyTitle('BLT'), 'BLT');
      final t = tidyRecipe(const RecipeData(id: 'x:1', source: 'x', title: 'TACOS DE POLLO', cuisine: 'mexican', category: 'main dish', diets: ['Gluten-Free', 'lacto_ovo_vegetarian'], prepMin: 10, cookMin: 15));
      expect(t.title, 'Tacos de Pollo');
      expect((t.cuisine, t.category, t.totalMin), ('Mexican', 'Main course', 25));
      expect(t.diets, ['gluten free', 'vegetarian']);
      expect(tidyRecipe(const RecipeData(id: 'x:2', source: 'x', title: 'Stew', cuisine: 'Unknown', category: 'Miscellaneous')).cuisine, isNull);
    });

    test('the same dish from two sources is one card, with the best details of both', () {
      expect(dishKey('The Best Chicken Curry'), dishKey('Curry, Chicken'));
      expect(dishKey('Crème Brûlée'), dishKey('Creme Brulee'));
      final merged = mergeSameDishes([
        r('wikibooks', '1', 'Chicken Curry', steps: 6),
        r('tasty', '2', 'The Best Chicken Curry', image: 'https://img/curry.jpg', minutes: 35),
        r('wikibooks', '3', 'Curry Chicken'),
        r('racion', '4', 'Chicken Curry with Rice', ingredients: const ['rice', 'chicken', 'curry powder', 'garlic']),
      ]);
      expect(merged, hasLength(3), reason: "one cookbook's two curries stay two; a different dish stays apart");
      final curry = merged.firstWhere((x) => x.alsoFrom.isNotEmpty);
      expect(curry.source, 'tasty', reason: 'the one with a photo and a time is the most complete');
      expect(curry.alsoFrom, ['wikibooks']);
      expect(curry.totalMin, 35);
    });

    test('the best fit for the search comes first, and sources take turns', () {
      final list = blendRecipes([
        r('themealdb', '1', 'Beef Stew', image: 'https://i/1.jpg', ingredients: const ['beef', 'carrot', 'potato']),
        r('themealdb', '2', 'Chicken Pie', image: 'https://i/2.jpg'),
        r('themealdb', '3', 'Chicken Soup', image: 'https://i/3.jpg'),
        r('wikibooks', '4', 'Chicken Tikka'),
        r('racion', '5', 'Rice Bowl', ingredients: const ['rice', 'chicken', 'egg']),
      ], const RecipeQuery(text: 'chicken', limit: 10));
      expect(list.first.title, startsWith('Chicken'), reason: 'the word in the title counts most');
      expect(list.last.title, 'Beef Stew', reason: 'a recipe without chicken comes last');
      // Never the same source twice running while another is nearly as good.
      expect([for (var i = 1; i < 3; i++) list[i].source != list[i - 1].source], everyElement(isTrue));
    });

    test('every source is asked at once; a slow or failing one is left out, not waited for', () async {
      final slow = _Fake('slow', [r('slow', '1', 'Chicken Soup')], delay: const Duration(seconds: 30));
      final broken = _Fake('broken', const [], error: StateError('down'));
      final good = _Fake('good', [r('good', '1', 'Chicken Soup', image: 'https://i/s.jpg')]);
      final errors = <String>[];
      final watch = Stopwatch()..start();
      final found = await searchEverywhere([slow, broken, good], const RecipeQuery(text: 'soup'), timeout: const Duration(milliseconds: 200), onError: (p, _) => errors.add(p));
      expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(found.answered, ['good']);
      expect(found.skipped, unorderedEquals(['slow', 'broken']));
      expect(errors, unorderedEquals(['slow', 'broken']));
      expect(found.recipes.single.source, 'good');
    });
  });
}

/// A source with canned answers.
class _Fake implements RecipeProvider {
  _Fake(this.id, this.answer, {this.delay = Duration.zero, this.error});
  @override
  final String id;
  final List<RecipeData> answer;
  final Duration delay;
  final Object? error;

  @override
  String get displayName => id;

  @override
  Future<List<RecipeData>> search(RecipeQuery query) async {
    await Future<void>.delayed(delay);
    if (error != null) throw error!;
    return answer;
  }

  @override
  Future<List<RecipeData>> random(int count, {String? tag}) => search(const RecipeQuery());
  @override
  Future<RecipeData?> lookup(String sourceId) async => null;
  @override
  Future<List<String>> cuisines() async => const [];
}
