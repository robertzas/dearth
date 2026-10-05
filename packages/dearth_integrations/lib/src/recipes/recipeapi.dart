import 'package:dearth_core/dearth_core.dart';

import '../http/fetcher.dart';
import 'quota.dart';
import 'recipe_provider.dart';
import 'spoonacular.dart' show QuotaExceededException;

/// RecipeAPI.io (optional free key; SPEC §13.6, FR-RCP-01): about 50,000
/// recipes with structured ingredients, steps, cuisine, meal type and diet
/// tags, but no photos. The free plan is 500 requests a month (personal,
/// non-commercial use) and ten results a page; [budget] spreads them over
/// the month.
class RecipeApiIo implements RecipeProvider {
  RecipeApiIo(this.fetcher, this.apiKey, {QuotaBudget? budget, Uri? base})
      : budget = budget ?? QuotaBudget(limit: 500, period: QuotaPeriod.month),
        base = base ?? Uri.parse('https://recipeapi.io');

  final Fetcher fetcher;
  final String apiKey;
  final QuotaBudget budget;
  final Uri base;

  @override
  String get id => 'recipeapi';
  @override
  String get displayName => 'RecipeAPI.io';

  /// Its cuisine and diet filters only know these values.
  static const _cuisines = {'american', 'chinese', 'french', 'greek', 'italian', 'japanese', 'mexican', 'portuguese', 'spanish', 'thai', 'turkish'};
  static const _diets = {'vegetarian': 'vegetarian', 'vegan': 'vegan', 'gluten free': 'gluten_free', 'dairy free': 'dairy_free', 'nut free': 'nut_free'};

  Future<Object?> _get(String path, [Map<String, String> q = const {}]) async {
    if (!budget.canSpend(1)) throw QuotaExceededException(id);
    budget.spend(1);
    return fetcher.getJson(id, base.replace(path: path, queryParameters: q.isEmpty ? null : q), headers: {'Authorization': 'Bearer $apiKey', 'Accept': 'application/json'});
  }

  static List<Map<String, Object?>> _data(Object? j) => j is Map<String, Object?> && j['data'] is List ? (j['data']! as List).whereType<Map<String, Object?>>().toList() : const [];

  @override
  Future<List<RecipeData>> search(RecipeQuery query) async {
    final cuisine = query.cuisine?.toLowerCase();
    final diet = query.diet?.toLowerCase().replaceAll('-', ' ');
    final dietTag = _diets[diet];
    final rows = _data(await _get('/api/v1/recipes', {
      if (query.text?.trim().isNotEmpty ?? false) ...{'search': query.text!.trim(), 'search_in': 'both'},
      if (query.includeIngredients.isNotEmpty) 'ingredients': query.includeIngredients.join(','),
      if (cuisine != null && _cuisines.contains(cuisine)) 'cuisine': cuisine,
      'dietary_tags': ?dietTag,
      'per_page': '${query.limit.clamp(1, 10)}',
    }));
    return [
      for (final r in rows.map(parseRecipe))
        if ((query.maxMinutes == null || (r.totalMin ?? 0) <= query.maxMinutes!) &&
            !query.excludeIngredients.any((x) => r.ingredients.any((i) => i.key.contains(x.toLowerCase()))))
          r,
    ];
  }

  @override
  Future<List<RecipeData>> random(int count, {String? tag}) async => _data(await _get('/api/v1/recipes/random', {'count': '${count.clamp(1, 10)}'})).map(parseRecipe).toList();

  @override
  Future<RecipeData?> lookup(String sourceId) async {
    final j = await _get('/api/v1/recipes/${Uri.encodeComponent(sourceId)}');
    final row = j is Map<String, Object?> ? j['data'] : null;
    return row is Map<String, Object?> ? parseRecipe(row) : null;
  }

  @override
  Future<List<String>> cuisines() async => [for (final c in _cuisines) c[0].toUpperCase() + c.substring(1)];

  /// Normalizes one recipe.
  RecipeData parseRecipe(Map<String, Object?> r) {
    final sourceId = '${r['id']}';
    final prep = (r['prep_time'] as num?)?.toInt(), cook = (r['cook_time'] as num?)?.toInt();
    final cuisine = r['cuisine'] as String?;
    return RecipeData(
      id: providerRecipeId(id, sourceId),
      source: id,
      sourceId: sourceId,
      url: 'https://recipeapi.io/recipes/$sourceId',
      title: r['name'] as String? ?? 'Recipe',
      servings: (r['servings'] as num?)?.toInt() ?? 4,
      prepMin: prep,
      cookMin: cook,
      totalMin: prep == null && cook == null ? null : (prep ?? 0) + (cook ?? 0),
      cuisine: cuisine == null || cuisine.isEmpty ? null : cuisine[0].toUpperCase() + cuisine.substring(1),
      category: _mealTypes[r['meal_type']],
      diets: [
        for (final d in (r['dietary_tags'] as List? ?? const []))
          '$d'.replaceAll('_', ' '),
      ],
      ingredients: [
        for (final i in (r['ingredients'] as List? ?? const []).whereType<Map<String, Object?>>())
          if (i['name'] is String) _ingredient(i),
      ],
      steps: [
        for (final s in (r['instructions'] as List? ?? const []))
          if ('$s'.trim().isNotEmpty && '$s'.trim() != '...') '$s'.trim(),
      ],
      summary: r['description'] as String?,
      attribution: 'RecipeAPI.io',
    );
  }

  static Ingredient _ingredient(Map<String, Object?> i) {
    final qty = i['quantity'] as num?;
    final unit = i['unit'] as String? ?? '';
    final amount = qty == null ? '' : (qty == qty.roundToDouble() ? '${qty.round()}' : '$qty');
    final base = ingredientFromMeasure('$amount ${const {'piece', 'pieces', 'whole'}.contains(unit) ? '' : unit}'.trim(), i['name']! as String);
    return i['optional'] == true
        ? Ingredient(raw: base.raw, name: base.name, key: base.key, qty: base.qty, unit: base.unit, prep: base.prep, optional: true, aisle: base.aisle, confidence: base.confidence)
        : base;
  }

  static const Map<Object?, String> _mealTypes = {
    'main': 'Main course', 'starter': 'Starter', 'appetizer': 'Starter', 'dessert': 'Dessert', 'breakfast': 'Breakfast', 'brunch': 'Breakfast', //
    'snack': 'Snack', 'side_dish': 'Side', 'soup': 'Soup', 'drink': 'Drink', 'sauce': 'Sauce',
  };
}
