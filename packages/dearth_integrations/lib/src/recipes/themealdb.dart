import 'package:dearth_core/dearth_core.dart';

import '../http/fetcher.dart';
import 'recipe_provider.dart';

/// TheMealDB (free baseline; SPEC §13.6). `apiKey` `1` is the public test key;
/// a supporter key unlocks the V2 endpoints (multi-ingredient, random sets).
class TheMealDb implements RecipeProvider {
  TheMealDb(this.fetcher, {this.apiKey = '1', Uri? base}) : base = base ?? Uri.parse('https://www.themealdb.com');

  final Fetcher fetcher;
  final String apiKey;
  final Uri base;

  @override
  String get id => 'themealdb';
  @override
  String get displayName => 'TheMealDB';

  bool get _premium => apiKey != '1';
  String get _prefix => '/api/json/${_premium ? 'v2' : 'v1'}/$apiKey';

  Future<List<Map<String, Object?>>> _meals(String endpoint, Map<String, String> q) async {
    final uri = base.replace(path: '$_prefix/$endpoint', queryParameters: q.isEmpty ? null : q);
    final j = await fetcher.getJson(id, uri);
    if (j is! Map<String, Object?>) return const [];
    final meals = j['meals'];
    return meals is List ? meals.whereType<Map<String, Object?>>().toList() : const [];
  }

  @override
  Future<List<RecipeData>> search(RecipeQuery query) async {
    List<Map<String, Object?>> rows;
    var needsLookup = false;
    if (query.text != null && query.text!.trim().isNotEmpty) {
      rows = await _meals('search.php', {'s': query.text!.trim()});
    } else if (query.includeIngredients.isNotEmpty) {
      // Free tier filters by one ingredient; the planner ranks locally.
      final ing = query.includeIngredients.take(_premium ? 3 : 1).map((s) => s.trim().replaceAll(' ', '_')).join(',');
      rows = await _meals('filter.php', {'i': ing});
      needsLookup = true;
    } else if (query.cuisine != null) {
      rows = await _meals('filter.php', {'a': query.cuisine!});
      needsLookup = true;
    } else if (query.category != null) {
      rows = await _meals('filter.php', {'c': query.category!});
      needsLookup = true;
    } else {
      return random(query.limit);
    }
    rows = rows.take(query.limit).toList();
    if (needsLookup) {
      // Filter endpoints return id/title/thumb only; fetch details (bounded).
      final full = await Future.wait(rows.take(12).map((r) => lookup('${r['idMeal']}')));
      return full.whereType<RecipeData>().where((r) => _passes(r, query)).toList();
    }
    return rows.map(parseMeal).where((r) => _passes(r, query)).toList();
  }

  bool _passes(RecipeData r, RecipeQuery q) {
    for (final ex in q.excludeIngredients) {
      if (r.ingredients.any((i) => i.key.contains(ex.toLowerCase()))) return false;
    }
    if (q.cuisine != null && r.cuisine != null && q.text != null && r.cuisine!.toLowerCase() != q.cuisine!.toLowerCase()) return false;
    return true;
  }

  @override
  Future<List<RecipeData>> random(int count, {String? tag}) async {
    if (_premium) {
      final rows = await _meals('randomselection.php', const {});
      return rows.take(count).map(parseMeal).toList();
    }
    final results = await Future.wait(List.generate(count.clamp(1, 8), (_) => _meals('random.php', const {})));
    final seen = <String>{};
    return [
      for (final rows in results)
        for (final r in rows)
          if (seen.add('${r['idMeal']}')) parseMeal(r),
    ];
  }

  @override
  Future<RecipeData?> lookup(String sourceId) async {
    final rows = await _meals('lookup.php', {'i': sourceId});
    return rows.isEmpty ? null : parseMeal(rows.first);
  }

  @override
  Future<List<String>> cuisines() async {
    final rows = await _meals('list.php', {'a': 'list'});
    return [for (final r in rows) if (r['strArea'] is String) r['strArea']! as String];
  }

  /// Normalizes one TheMealDB meal object.
  RecipeData parseMeal(Map<String, Object?> m) {
    final ingredients = <Ingredient>[];
    for (var i = 1; i <= 20; i++) {
      final name = (m['strIngredient$i'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      ingredients.add(ingredientFromMeasure((m['strMeasure$i'] as String?) ?? '', name));
    }
    final instructions = (m['strInstructions'] as String?) ?? '';
    final steps = instructions
        .split(RegExp(r'\r?\n+'))
        .map((s) => s.replaceFirst(RegExp(r'^(step\s*)?\d+[.):]?\s*', caseSensitive: false), '').trim())
        .where((s) => s.length > 2)
        .toList();
    final sourceId = '${m['idMeal']}';
    return RecipeData(
      id: providerRecipeId(id, sourceId),
      source: id,
      sourceId: sourceId,
      url: (m['strSource'] as String?)?.isNotEmpty ?? false ? m['strSource'] as String? : 'https://www.themealdb.com/meal/$sourceId',
      title: (m['strMeal'] as String?) ?? 'Recipe',
      imageUrl: m['strMealThumb'] as String?,
      cuisine: m['strArea'] as String?,
      category: m['strCategory'] as String?,
      tags: [for (final t in ((m['strTags'] as String?) ?? '').split(',')) if (t.trim().isNotEmpty) t.trim()],
      ingredients: ingredients,
      steps: steps,
      attribution: 'TheMealDB',
    );
  }
}
