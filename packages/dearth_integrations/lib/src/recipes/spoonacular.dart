import 'package:dearth_core/dearth_core.dart';

import '../http/fetcher.dart';
import 'recipe_provider.dart';

/// Tracks Spoonacular's daily point budget (free tier ≈ 50/day; SPEC §13.6).
class PointBudget {
  PointBudget({this.dailyPoints = 45, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final double dailyPoints;
  final DateTime Function() _clock;
  String _day = '';
  double _used = 0;

  double get used {
    _roll();
    return _used;
  }

  bool canSpend(double points) {
    _roll();
    return _used + points <= dailyPoints;
  }

  void spend(double points) {
    _roll();
    _used += points;
  }

  /// Syncs with the provider's own counter (`X-API-Quota-Used` header).
  void observeQuotaUsed(double used) {
    _roll();
    if (used > _used) _used = used;
  }

  void _roll() {
    final now = _clock().toUtc();
    final day = '${now.year}-${now.month}-${now.day}';
    if (day != _day) {
      _day = day;
      _used = 0;
    }
  }
}

class QuotaExceededException extends ProviderException {
  QuotaExceededException(String provider) : super(provider, 'Daily point budget used up');
}

/// Spoonacular (optional key): popularity sort, diets, ingredients, similar.
class Spoonacular implements RecipeProvider {
  Spoonacular(this.fetcher, this.apiKey, {PointBudget? budget, Uri? base})
      : budget = budget ?? PointBudget(),
        base = base ?? Uri.parse('https://api.spoonacular.com');

  final Fetcher fetcher;
  final String apiKey;
  final PointBudget budget;
  final Uri base;

  @override
  String get id => 'spoonacular';
  @override
  String get displayName => 'Spoonacular';

  Future<Object?> _get(String path, Map<String, String> q, double estimatedPoints) async {
    if (!budget.canSpend(estimatedPoints)) throw QuotaExceededException(id);
    final res = await fetcher.send(id, 'GET', base.replace(path: path, queryParameters: {...q, 'apiKey': apiKey}));
    final used = double.tryParse(res.headers['x-api-quota-used'] ?? '');
    if (used != null) {
      budget.observeQuotaUsed(used);
    } else {
      budget.spend(estimatedPoints);
    }
    return fetcher.decodeResponse(id, res);
  }

  @override
  Future<List<RecipeData>> search(RecipeQuery query) async {
    final n = query.limit.clamp(1, 20);
    final j = await _get('/recipes/complexSearch', {
      if (query.text != null && query.text!.isNotEmpty) 'query': query.text!,
      if (query.includeIngredients.isNotEmpty) 'includeIngredients': query.includeIngredients.join(','),
      if (query.excludeIngredients.isNotEmpty) 'excludeIngredients': query.excludeIngredients.join(','),
      if (query.cuisine != null) 'cuisine': query.cuisine!,
      if (query.category != null) 'type': query.category!,
      if (query.diet != null) 'diet': query.diet!,
      if (query.maxMinutes != null) 'maxReadyTime': '${query.maxMinutes}',
      if (query.sortByPopularity) 'sort': 'popularity',
      'number': '$n',
      'addRecipeInformation': 'true',
      'addRecipeInstructions': 'true',
      'fillIngredients': 'true',
    }, 1 + n * 0.06);
    final results = j is Map<String, Object?> ? j.arr('results') : const <Object?>[];
    return [for (final r in results) if (r is Map<String, Object?>) parseRecipe(r)];
  }

  @override
  Future<List<RecipeData>> random(int count, {String? tag}) async {
    final j = await _get('/recipes/random', {'number': '${count.clamp(1, 10)}', 'include-tags': ?tag}, 1 + count * 0.01);
    final recipes = j is Map<String, Object?> ? j.arr('recipes') : const <Object?>[];
    return [for (final r in recipes) if (r is Map<String, Object?>) parseRecipe(r)];
  }

  @override
  Future<RecipeData?> lookup(String sourceId) async {
    final j = await _get('/recipes/$sourceId/information', const {'includeNutrition': 'false'}, 1);
    return j is Map<String, Object?> ? parseRecipe(j) : null;
  }

  /// Similar recipes (ids only; details need lookups).
  Future<List<String>> similarIds(String sourceId, {int count = 6}) async {
    final j = await _get('/recipes/$sourceId/similar', {'number': '$count'}, 1);
    return [for (final r in (j as List? ?? const [])) if (r is Map) '${r['id']}'];
  }

  @override
  Future<List<String>> cuisines() async => const [
        'African', 'American', 'British', 'Cajun', 'Caribbean', 'Chinese', 'French', 'German', 'Greek', 'Indian', //
        'Irish', 'Italian', 'Japanese', 'Korean', 'Latin American', 'Mediterranean', 'Mexican', 'Middle Eastern', //
        'Spanish', 'Thai', 'Vietnamese',
      ];

  RecipeData parseRecipe(Map<String, Object?> r) {
    final ingredients = <Ingredient>[];
    final ext = r.arr('extendedIngredients');
    final source = ext.isNotEmpty ? ext : [...r.arr('usedIngredients'), ...r.arr('missedIngredients')];
    final seen = <String>{};
    for (final i in source) {
      if (i is! Map<String, Object?>) continue;
      final original = i.str('original') ?? '${i.str('amount') ?? ''} ${i.str('unit') ?? ''} ${i.str('name') ?? ''}';
      if (!seen.add(original)) continue;
      ingredients.add(parseIngredientLine(original));
    }
    final steps = <String>[];
    for (final block in r.arr('analyzedInstructions')) {
      if (block is! Map<String, Object?>) continue;
      for (final s in block.arr('steps')) {
        if (s is Map<String, Object?> && s.str('step') != null) steps.add(s.str('step')!.trim());
      }
    }
    if (steps.isEmpty && r.str('instructions') != null) {
      steps.addAll(r.str('instructions')!.replaceAll(RegExp('<[^>]+>'), '\n').split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty));
    }
    final sourceId = '${r['id']}';
    final diets = [for (final d in r.arr('diets')) '$d'];
    return RecipeData(
      id: providerRecipeId(id, sourceId),
      source: id,
      sourceId: sourceId,
      url: r.str('sourceUrl') ?? r.str('spoonacularSourceUrl'),
      title: r.str('title') ?? 'Recipe',
      imageUrl: r.str('image'),
      servings: r.integer('servings') ?? 4,
      prepMin: r.integer('preparationMinutes')?.clamp(0, 1000),
      cookMin: r.integer('cookingMinutes')?.clamp(0, 1000),
      totalMin: r.integer('readyInMinutes'),
      cuisine: r.arr('cuisines').isEmpty ? null : '${r.arr('cuisines').first}',
      category: r.arr('dishTypes').isEmpty ? null : '${r.arr('dishTypes').first}',
      diets: diets,
      tags: [for (final t in r.arr('dishTypes')) '$t'],
      ingredients: ingredients,
      steps: steps,
      popularity: r.number('aggregateLikes'),
      summary: r.str('summary')?.replaceAll(RegExp('<[^>]+>'), ''),
      attribution: 'Via Spoonacular${r.str('sourceName') == null ? '' : ' · ${r.str('sourceName')}'}',
    );
  }
}
