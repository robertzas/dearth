import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

RecipeData recipe(String id, String title, List<String> lines, {int servings = 4, String? cuisine}) => RecipeData(
      id: id,
      source: 'test',
      title: title,
      servings: servings,
      cuisine: cuisine,
      ingredients: [for (final l in lines) parseIngredientLine(l)],
    );

void main() {
  group('units & quantities', () {
    test('parses fractions, mixed numbers, unicode and ranges', () {
      expect(parseQuantity('1 1/2')!.value, 1.5);
      expect(parseQuantity('½')!.value, .5);
      expect(parseQuantity('1½')!.value, 1.5);
      expect(parseQuantity('2-3')!.max, 3);
      expect(parseQuantity('abc'), isNull);
    });

    test('friendly formatting', () {
      expect(formatAmount(1 + 1 / 3), '1⅓');
      expect(formatAmount(0.5), '½');
      expect(formatAmount(2.0), '2');
      expect(formatAmount(1.1), '1.1');
      expect(formatMeasure(2, 'cup'), '2 cups');
      expect(formatMeasure(2, 'tbsp'), '2 tbsp');
      expect(formatMeasure(3, 'bunch'), '3 bunches');
    });

    test('conversions and friendly units', () {
      final (a, u) = friendlyUnit(6, 'tsp');
      expect(u, 'tbsp');
      expect(a, closeTo(2, 0.01));
      final (c, cu) = friendlyUnit(16, 'tbsp');
      expect(cu, 'cup');
      expect(c, closeTo(1, 0.01));
      final (g, gu) = toSystem(1, 'lb', metric: true);
      expect(gu, 'g');
      expect(g, closeTo(453.6, 0.1));
      expect(canConvert('cup', 'ml'), isTrue);
      expect(canConvert('cup', 'g'), isFalse);
    });
  });

  group('FR-RCP-02: ingredient parsing & normalization', () {
    test('quantity, unit, name, preparation', () {
      final i = parseIngredientLine('2 1/2 cups all-purpose flour, sifted');
      expect(i.qty, 2.5);
      expect(i.unit, 'cup');
      expect(i.key, 'flour');
      expect(i.prep, contains('sifted'));
      expect(i.isStaple, isTrue);
    });

    test('package sizes, ranges, synonyms, plurals', () {
      final can = parseIngredientLine('1 (14 oz) can diced tomatoes');
      expect(can.unit, 'can');
      expect(can.key, 'tomato');
      expect(can.prep, contains('14 oz'));
      final garlic = parseIngredientLine('3-4 cloves garlic, minced');
      expect(garlic.qty, 3);
      expect(garlic.qtyMax, 4);
      expect(garlic.unit, 'clove');
      expect(garlic.key, 'garlic');
      expect(parseIngredientLine('4 scallions, thinly sliced').key, 'green onion');
      expect(parseIngredientLine('2 limes').key, 'lime');
      expect(parseIngredientLine('Salt to taste').qty, isNull);
      expect(parseIngredientLine('1 bunch cilantro').aisle, Aisle.produce);
      expect(parseIngredientLine('1 lb boneless skinless chicken thighs').aisle, Aisle.meatSeafood);
    });

    test('TheMealDB measure + name pairs', () {
      final i = ingredientFromMeasure('1/2 tsp', 'Cumin');
      expect(i.qty, .5);
      expect(i.unit, 'tsp');
      expect(i.key, 'cumin');
      final pinch = ingredientFromMeasure('pinch', 'Salt');
      expect(pinch.key, 'salt');
    });

    test('FR-RCP-06: scaling and display', () {
      final r = recipe('r', 'Pancakes', ['1 1/2 cups flour', '2 eggs', '1 tbsp sugar']);
      final doubled = r.scaledIngredients(8);
      expect(doubled[0].describe(), '3 cups flour');
      expect(doubled[1].describe(), '4 eggs');
      expect(r.scaledIngredients(2)[0].describe(), '¾ cup flour');
      expect(r.scaledIngredients(4)[0].describe(metric: true), contains('ml'));
    });

    test('FR-RCP-06: preparation is shown once', () {
      expect(parseIngredientLine('2 cloves garlic, minced').describe(), '2 cloves garlic, minced');
      expect(parseIngredientLine('1 tbsp grated ginger').describe(), isNot(contains(', grated')));
    });
  });

  test('FR-RCP-13: a recipe credits its source and the others that have the same dish', () {
    const merged = RecipeData(id: 'themealdb:1', source: 'themealdb', title: 'Chicken Curry', attribution: 'TheMealDB', alsoFrom: ['wikibooks', 'tasty']);
    expect(recipeCredit(merged), 'From TheMealDB · also on the Wikibooks Cookbook and Tasty');
    // Rows saved before said "Recipe from …" or "Via …".
    expect(recipeCredit(const RecipeData(id: 'a', source: 'themealdb', title: 'x', attribution: 'Recipe from TheMealDB')), 'From TheMealDB');
    expect(recipeCredit(const RecipeData(id: 'b', source: 'spoonacular', title: 'x', attribution: 'Via Spoonacular · Foodista')), 'From Spoonacular · Foodista');
    expect(recipeCredit(const RecipeData(id: 'c', source: 'web', title: 'x')), 'From the web');
    expect(RecipeData.fromJson(merged.toJson()).alsoFrom, ['wikibooks', 'tasty']);
    expect(const RecipeData(id: 'd', source: 'box', title: 'x').toJson().containsKey('alsoFrom'), isFalse);
  });

  group('FR-SHOP-01/02: consolidation', () {
    test('merges confident, convertible lines and keeps sources', () {
      final tacos = recipe('t', 'Tacos', ['1 lb ground beef', '1 bunch cilantro', '2 limes', '1/2 cup sour cream']);
      final chili = recipe('c', 'Chili', ['8 oz ground beef', '1 can black beans', '1 lime', '1/4 cup sour cream']);
      final lines = consolidate([PlannedRecipe(tacos, 4, label: 'Tacos (Tue)'), PlannedRecipe(chili, 8, label: 'Chili (Thu)')]);
      final beef = lines.firstWhere((l) => l.key == 'ground beef');
      // 1 lb + (8 oz × 2 servings factor) = 2 lb
      expect(beef.parts.single.unit, 'lb');
      expect(beef.parts.single.qty, closeTo(2, 0.01));
      expect(beef.recipes, {'Tacos (Tue)', 'Chili (Thu)'});
      final limes = lines.firstWhere((l) => l.key == 'lime');
      expect(limes.parts.single.qty, 4);
      final cream = lines.firstWhere((l) => l.key == 'sour cream');
      expect(cream.amounts(), '1 cup');
      expect(lines.first.aisle.index <= lines.last.aisle.index, isTrue);
    });

    test('incompatible units stay as separate parts; unsure names stay separate lines', () {
      final a = recipe('a', 'A', ['1 bag spinach']);
      final b = recipe('b', 'B', ['2 cups spinach']);
      final lines = consolidate([PlannedRecipe(a, 4), PlannedRecipe(b, 4)]);
      final spinach = lines.firstWhere((l) => l.key == 'spinach');
      expect(spinach.parts.length, 2);
      expect(spinach.amounts(), '1 bag · 2 cups');
    });

    test('state ids are stable per period', () {
      final l = consolidate([PlannedRecipe(recipe('a', 'A', ['2 limes']), 4)]).single;
      expect(l.stateId('2026-W40'), l.stateId('2026-W40'));
      expect(l.stateId('2026-W40'), isNot(l.stateId('2026-W41')));
    });
  });

  group('FR-RCP-09/10: plan-aware recommendations', () {
    final tacos = recipe('t', 'Fish tacos', ['1 bunch cilantro', '3 limes', '1 lb cod', '8 tortillas'], cuisine: 'Mexican');
    final plan = PlanContext.fromRecipes([tacos]);

    test('perishable overlap wins; explanation is human', () {
      final rice = recipe('r', 'Cilantro lime rice', ['1 cup rice', '1/2 bunch cilantro', '2 limes'], cuisine: 'Mexican');
      final cake = recipe('k', 'Chocolate cake', ['2 cups flour', '1 cup cocoa', '3 eggs', '1 cup milk']);
      final ranked = rankForPlan([cake, rice], plan);
      expect(ranked.first.recipe.id, 'r');
      expect(ranked.first.matched, containsAll(['cilantro', 'lime']));
      expect(ranked.first.explanation, startsWith('Uses your cilantro and lime'));
      expect(ranked.first.explanation, contains('adds 1 item'));
      expect(ranked.last.explanation, startsWith('Something new'));
    });

    test('allergen/exclusion hard filters and already-planned penalty', () {
      final peanut = recipe('p', 'Peanut noodles', ['1/2 cup peanut butter', '8 oz noodles']);
      expect(scoreForPlan(peanut, plan, excluded: {'peanut'}), isNull);
      expect(scoreForPlan(tacos, plan)!.score, lessThan(0));
    });

    test('variety: third dish of the same protein is penalized', () {
      final chicken1 = recipe('c1', 'A', ['1 lb chicken breast', '1 lime']);
      final chicken2 = recipe('c2', 'B', ['1 lb chicken thigh', '1 lime']);
      final p2 = PlanContext.fromRecipes([chicken1, chicken2]);
      final chicken3 = recipe('c3', 'C', ['1 lb chicken drumstick', '1 lime']);
      final tofu = recipe('tf', 'D', ['1 lb tofu', '1 lime']);
      expect(scoreForPlan(tofu, p2)!.score, greaterThan(scoreForPlan(chicken3, p2)!.score));
    });
  });

  test('FR-RCP-07: cook-mode timers are detected in steps', () {
    final timers = stepTimers('Bake for 25 minutes, then rest 5-10 min. Simmer 1 hour.');
    expect(timers.map((t) => t.$1), [1500, 600, 3600]);
    expect(stepTimers('Add 2 cups of stock'), isEmpty);
  });

  test('RecipeData survives row fields and JSON', () {
    final r = recipe('x', 'Soup', ['1 onion', '2 carrots']);
    final back = RecipeData.fromJson(r.toJson());
    expect(back.ingredients.map((i) => i.key), ['onion', 'carrot']);
    expect(r.toFields()['ingredients'], isA<List<Object?>>());
  });
}
