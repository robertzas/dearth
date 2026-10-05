import 'package:dearth_core/dearth_core.dart';

import '../http/fetcher.dart';
import 'quota.dart';
import 'recipe_provider.dart';
import 'spoonacular.dart' show QuotaExceededException;

/// Tasty (optional free RapidAPI key; SPEC §13.6, FR-RCP-01): photo-led
/// recipes with ratings and tags. The BASIC plan is 500 requests a month;
/// RapidAPI reports what's left in a header, and [budget] spreads it over
/// the month. It's an unofficial API run by a third party (API Dojo), so a
/// failure here just leaves Tasty out of the results.
class TastyApi implements RecipeProvider {
  TastyApi(this.fetcher, this.apiKey, {QuotaBudget? budget, Uri? base})
      : budget = budget ?? QuotaBudget(limit: 500, period: QuotaPeriod.month),
        base = base ?? Uri.parse('https://tasty.p.rapidapi.com');

  final Fetcher fetcher;
  final String apiKey;
  final QuotaBudget budget;
  final Uri base;

  @override
  String get id => 'tasty';
  @override
  String get displayName => 'Tasty';

  Future<Object?> _get(String path, Map<String, String> q) async {
    if (!budget.canSpend(1)) throw QuotaExceededException(id);
    final res = await fetcher.send(id, 'GET', base.replace(path: path, queryParameters: q), headers: {'X-RapidAPI-Key': apiKey, 'X-RapidAPI-Host': base.host});
    final left = int.tryParse(res.headers['x-ratelimit-requests-remaining'] ?? '');
    left == null ? budget.spend(1) : budget.observeRemaining(left);
    return fetcher.decodeResponse(id, res);
  }

  /// The recipes in a list response; a compilation stands for its recipes.
  List<RecipeData> _recipes(Object? j) {
    final results = j is Map<String, Object?> && j['results'] is List ? (j['results']! as List).whereType<Map<String, Object?>>() : const <Map<String, Object?>>[];
    return [
      for (final r in results)
        if (r['recipes'] is List)
          for (final inner in (r['recipes']! as List).whereType<Map<String, Object?>>()) ?parseRecipe(inner)
        else
          ?parseRecipe(r),
    ];
  }

  @override
  Future<List<RecipeData>> search(RecipeQuery query) async {
    final words = [
      if (query.text?.trim().isNotEmpty ?? false) query.text!.trim(),
      ...query.includeIngredients,
      ?query.cuisine,
    ];
    final found = _recipes(await _get('/recipes/list', {'from': '0', 'size': '${query.limit.clamp(1, 20)}', if (words.isNotEmpty) 'q': words.join(' ')}));
    return [
      for (final r in found)
        if ((query.maxMinutes == null || (r.totalMin ?? 0) <= query.maxMinutes!) &&
            !query.excludeIngredients.any((x) => r.ingredients.any((i) => i.key.contains(x.toLowerCase()))))
          r,
    ];
  }

  @override
  Future<List<RecipeData>> random(int count, {String? tag}) async =>
      _recipes(await _get('/recipes/list', {'from': '${DateTime.now().millisecondsSinceEpoch % 500}', 'size': '${count.clamp(1, 20)}', 'tags': tag ?? 'dinner'}));

  @override
  Future<RecipeData?> lookup(String sourceId) async {
    final j = await _get('/recipes/get-more-info', {'id': sourceId});
    return j is Map<String, Object?> ? parseRecipe(j) : null;
  }

  @override
  Future<List<String>> cuisines() async => const [];

  /// Normalizes one recipe; null without ingredients or steps.
  RecipeData? parseRecipe(Map<String, Object?> r) {
    final ingredients = <Ingredient>[];
    for (final s in (r['sections'] as List? ?? const []).whereType<Map<String, Object?>>()) {
      final group = s['name'] as String?;
      for (final c in (s['components'] as List? ?? const []).whereType<Map<String, Object?>>()) {
        final raw = (c['raw_text'] as String? ?? '').trim();
        if (raw.isNotEmpty && raw.toLowerCase() != 'n/a') {
          ingredients.add(parseIngredientLine(raw, group: group));
        } else if (c['ingredient'] case {'name': final String name}) {
          final m = (c['measurements'] as List? ?? const []).whereType<Map<String, Object?>>().firstOrNull;
          final unit = m?['unit'] is Map<String, Object?> ? (m!['unit']! as Map<String, Object?>)['name'] as String? ?? '' : '';
          ingredients.add(parseIngredientLine('${m?['quantity'] ?? ''} $unit $name'.replaceAll(RegExp(r'\s+'), ' ').trim(), group: group));
        }
      }
    }
    final steps = [
      for (final i in ((r['instructions'] as List? ?? const []).whereType<Map<String, Object?>>().toList()..sort((a, b) => ((a['position'] as num?) ?? 0).compareTo((b['position'] as num?) ?? 0))))
        if ((i['display_text'] as String? ?? '').trim().isNotEmpty) (i['display_text']! as String).trim(),
    ];
    if (ingredients.isEmpty || steps.isEmpty) return null;
    final tags = (r['tags'] as List? ?? const []).whereType<Map<String, Object?>>().toList();
    String? tagOf(String type) => tags.where((t) => t['type'] == type).map((t) => t['display_name'] as String?).nonNulls.firstOrNull;
    final ratings = r['user_ratings'];
    final prep = (r['prep_time_minutes'] as num?)?.toInt(), cook = (r['cook_time_minutes'] as num?)?.toInt();
    final total = (r['total_time_minutes'] as num?)?.toInt();
    final sourceId = '${r['id']}';
    final slug = r['slug'] as String?;
    return RecipeData(
      id: providerRecipeId(id, sourceId),
      source: id,
      sourceId: sourceId,
      url: slug == null ? null : 'https://tasty.co/recipe/$slug',
      title: (r['name'] as String? ?? 'Recipe').trim(),
      imageUrl: r['thumbnail_url'] as String?,
      servings: (r['num_servings'] as num?)?.toInt() ?? 4,
      prepMin: prep == 0 ? null : prep,
      cookMin: cook == 0 ? null : cook,
      totalMin: total == null || total == 0 ? null : total,
      cuisine: tagOf('cuisine'),
      category: tagOf('meal'),
      diets: [
        for (final t in tags)
          if (t['type'] == 'dietary' && t['display_name'] is String) (t['display_name']! as String).toLowerCase(),
      ],
      tags: [
        for (final t in tags)
          if (t['type'] == 'difficulty' && t['name'] == 'under_30_minutes') 'quick',
      ],
      ingredients: ingredients,
      steps: steps,
      popularity: ratings is Map<String, Object?> ? (ratings['count_positive'] as num?)?.toDouble() : null,
      summary: (r['description'] as String?)?.trim(),
      attribution: 'Tasty',
    );
  }
}
