import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_integrations/dearth_integrations.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('TheMealDB', () {
    test('parses a recorded meal into normalized ingredients and steps', () async {
      final f = fakeFetcher({pathEnds('/lookup.php'): (_) => text(fixture('themealdb_lookup.json'))});
      final r = (await TheMealDb(f).lookup('52772'))!;
      expect(r.title, 'Teriyaki Chicken Casserole');
      expect(r.id, 'themealdb:52772');
      expect(r.cuisine, isNotNull);
      expect(r.ingredients.length, greaterThan(5));
      expect(r.ingredients.map((i) => i.key), contains('soy sauce'));
      expect(r.steps, isNotEmpty);
      expect(r.attribution, contains('TheMealDB'));
    });

    test('search by name uses the free v1 endpoint', () async {
      final f = fakeFetcher({
        (req) => req.url.path == '/api/json/v1/1/search.php' && req.url.queryParameters['s'] == 'tacos': (_) => text(fixture('themealdb_search.json')),
      });
      final results = await TheMealDb(f).search(const RecipeQuery(text: 'tacos'));
      expect(results, isNotEmpty);
      expect(results.first.ingredients, isNotEmpty);
    });
  });

  test('Spoonacular complexSearch parses and tracks the point budget', () async {
    final budget = PointBudget(dailyPoints: 10);
    final f = fakeFetcher({
      path('/recipes/complexSearch'): (req) {
        expect(req.url.queryParameters['sort'], 'popularity');
        return json({
          'results': [
            {
              'id': 715538,
              'title': 'Bruschetta Style Pork & Pasta',
              'image': 'https://img.spoonacular.com/recipes/715538-312x231.jpg',
              'servings': 5,
              'readyInMinutes': 35,
              'sourceUrl': 'https://example.com/bruschetta',
              'cuisines': ['Mediterranean', 'Italian'],
              'dishTypes': ['dinner'],
              'diets': ['dairy free'],
              'aggregateLikes': 209,
              'missedIngredients': [
                {'original': '1 lb pork tenderloin'},
                {'original': '2 cups penne'},
              ],
              'usedIngredients': [
                {'original': '1 cup cherry tomatoes, halved'},
              ],
              'analyzedInstructions': [
                {
                  'steps': [
                    {'number': 1, 'step': 'Cook the pasta for 10 minutes.'},
                    {'number': 2, 'step': 'Sear the pork.'},
                  ],
                },
              ],
            },
          ],
        }, headers: {'x-api-quota-used': '1.12'});
      },
    });
    final sp = Spoonacular(f, 'key', budget: budget);
    final rs = await sp.search(const RecipeQuery(text: 'pasta', sortByPopularity: true, limit: 5));
    final r = rs.single;
    expect(r.id, 'spoonacular:715538');
    expect(r.servings, 5);
    expect(r.totalMin, 35);
    expect(r.cuisine, 'Mediterranean');
    expect(r.ingredients.map((i) => i.key), containsAll(['pork tenderloin', 'penne', 'cherry tomato']));
    expect(r.steps.length, 2);
    expect(budget.used, 1.12);
    final tight = Spoonacular(f, 'key', budget: PointBudget(dailyPoints: 0.5));
    expect(() => tight.search(const RecipeQuery(text: 'x')), throwsA(isA<QuotaExceededException>()));
  });

  group('URL import (schema.org)', () {
    const page = '''
<html><head><title>Best Tacos</title>
<script type="application/ld+json">
{"@context":"https://schema.org","@graph":[{"@type":"WebPage","name":"x"},
 {"@type":["Recipe"],"name":"Best Weeknight Tacos","image":[{"url":"https://img.test/a.jpg"},{"url":"https://img.test/b.jpg"}],
  "recipeYield":["4","4 servings"],"prepTime":"PT10M","cookTime":"PT20M","totalTime":"PT30M",
  "recipeCuisine":"Mexican","recipeCategory":["Dinner"],"keywords":"tacos, quick, family",
  "author":{"@type":"Person","name":"Jo Cook"},
  "recipeIngredient":["1 lb ground beef","8 corn tortillas","1 &amp; 1/2 cups salsa","1 bunch cilantro"],
  "recipeInstructions":[{"@type":"HowToSection","name":"Cook","itemListElement":[
     {"@type":"HowToStep","text":"Brown the beef for 8 minutes."},
     {"@type":"HowToStep","text":"Warm the tortillas."}]}]}]}
</script></head><body></body></html>''';

    test('JSON-LD with @graph, sections and image lists', () {
      final r = parseRecipeHtml(page, Uri.parse('https://www.cooking.test/tacos'))!;
      expect(r.title, 'Best Weeknight Tacos');
      expect(r.servings, 4);
      expect(r.totalMin, 30);
      expect(r.cuisine, 'Mexican');
      expect(r.imageUrl, 'https://img.test/b.jpg');
      expect(r.ingredients.length, 4);
      expect(r.ingredients.first.key, 'ground beef');
      expect(r.steps, ['Brown the beef for 8 minutes.', 'Warm the tortillas.']);
      expect(r.attribution, 'cooking.test · Jo Cook');
      expect(r.id, startsWith('web:'));
    });

    test('pages without recipe data return null', () {
      expect(parseRecipeHtml('<html><body>hello</body></html>', Uri.parse('https://x.test')), isNull);
    });

    test('importUrl rejects non-http links', () {
      expect(() => RecipeImporter(fakeFetcher({})).importUrl(Uri.parse('file:///etc/passwd')), throwsA(isA<ProviderException>()));
    });
  });

  group('bundled catalog', () {
    test('every recipe has a photo on TheMealDB, also for rows saved before photos', () {
      final photo = RegExp(r'^https://www\.themealdb\.com/images/media/meals/[a-z0-9]+\.jpg$');
      for (final r in recipeCatalog) {
        expect(r.imageUrl, matches(photo), reason: r.title);
        expect(catalogPhotoUrl(r.sourceId), r.imageUrl);
        expect(r.toFields()['image_url'], r.imageUrl, reason: 'saved with the recipe');
      }
      expect(catalogPhotoUrl('not-a-recipe'), isNull);
    });

    test('every recipe parses cleanly and shares ingredients', () {
      expect(recipeCatalog.length, greaterThanOrEqualTo(20));
      for (final r in recipeCatalog) {
        expect(r.ingredients, isNotEmpty, reason: r.title);
        expect(r.steps, isNotEmpty, reason: r.title);
        expect(r.ingredients.where((i) => i.key.isEmpty), isEmpty, reason: r.title);
      }
      final tacos = recipeCatalog.firstWhere((r) => r.sourceId == 'chicken-tacos');
      final ranked = rankForPlan(recipeCatalog, PlanContext.fromRecipes([tacos]));
      expect(ranked.first.matched, contains('cilantro'));
    });

    test('search, ingredient filter and random are deterministic', () async {
      final c = CatalogRecipes();
      expect((await c.search(const RecipeQuery(text: 'soup'))).map((r) => r.title), contains('Chicken noodle soup'));
      final withBroccoli = await c.search(const RecipeQuery(includeIngredients: ['broccoli']));
      expect(withBroccoli, isNotEmpty);
      expect(withBroccoli.every((r) => r.keys.any((k) => k.contains('broccoli'))), isTrue);
      final quick = await c.search(const RecipeQuery(maxMinutes: 15));
      expect(quick.every((r) => (r.totalMin ?? 0) <= 15), isTrue);
      expect((await CatalogRecipes(seed: 1).random(3)).map((r) => r.id), (await CatalogRecipes(seed: 1).random(3)).map((r) => r.id));
      expect(catalogEmoji('catalog:pesto-pasta'), '🌿');
    });
  });
}
