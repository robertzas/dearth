import 'package:dearth_core/dearth_core.dart';

import '../http/fetcher.dart';
import 'recipe_provider.dart';
import 'spoonacular.dart' show QuotaExceededException;

/// Racion (no key; SPEC §13.6, FR-RCP-01): English recipes with
/// per-serving amounts, times, calories and a kid-friendly flag, mostly
/// Eastern European home cooking. A search lists summaries, so the top few
/// are looked up for their ingredients and steps. Third-party apps get 50
/// requests an hour and 300 a day per address; the remaining counts come
/// back in headers, and the provider stops before it runs out rather than
/// collecting 429s.
class Racion implements RecipeProvider {
  Racion(this.fetcher, {Uri? base, this.country = 'US', this.details = 4}) : base = base ?? Uri.parse('https://racion.app');

  final Fetcher fetcher;
  final Uri base;

  /// Prices and stores are per country; the recipes are the same.
  final String country;

  /// How many hits a search looks up in full (each is one request).
  final int details;

  int? _leftThisHour, _leftToday;
  DateTime? _hourOf, _dayOf;

  @override
  String get id => 'racion';
  @override
  String get displayName => 'Racion';

  /// Whether [n] more requests fit in what Racion said is left.
  bool canSpend(int n, {DateTime? now}) {
    final t = (now ?? DateTime.now()).toUtc();
    if (_hourOf != null && t.difference(_hourOf!).inMinutes >= 60) _leftThisHour = null;
    if (_dayOf != null && (t.year, t.month, t.day) != (_dayOf!.year, _dayOf!.month, _dayOf!.day)) _leftToday = null;
    return (_leftThisHour ?? n) >= n && (_leftToday ?? n) >= n;
  }

  Future<Object?> _get(String path, Map<String, String> q) async {
    final res = await fetcher.send(id, 'GET', base.replace(path: path, queryParameters: {'country': country, 'lang': 'en', ...q}));
    final now = DateTime.now().toUtc();
    final hour = int.tryParse(res.headers['x-ratelimit-remaining-hour'] ?? '');
    final day = int.tryParse(res.headers['x-ratelimit-remaining-day'] ?? '');
    if (hour != null) {
      // The count is for the hour that started with the first request in it.
      if (_hourOf == null || now.difference(_hourOf!).inMinutes >= 60) _hourOf = now;
      _leftThisHour = hour;
    }
    if (day != null) {
      _leftToday = day;
      _dayOf = now;
    }
    return fetcher.decodeResponse(id, res);
  }

  @override
  Future<List<RecipeData>> search(RecipeQuery query) async {
    final words = [
      if (query.text?.trim().isNotEmpty ?? false) query.text!.trim(),
      ...query.includeIngredients,
    ];
    final wanted = query.limit.clamp(1, details);
    if (!canSpend(1 + wanted)) throw QuotaExceededException(id);
    final j = await _get('/api/recipes', {if (words.isNotEmpty) 'q': words.join(' '), 'limit': '${wanted * 2}'});
    final items = j is Map<String, Object?> && j['items'] is List ? (j['items']! as List).whereType<Map<String, Object?>>() : const <Map<String, Object?>>[];
    final hits = [
      for (final it in items)
        if (query.maxMinutes == null || ((it['TimeMin'] as num?) ?? 0) <= query.maxMinutes!) it,
    ].take(wanted);
    final full = await Future.wait(hits.map((it) async {
      final r = await lookup('${it['ID']}');
      // Only the search summary says whether it's one for kids.
      return r != null && it['Kid'] == true ? r.copyWith(tags: [...r.tags, 'kid-friendly']) : r;
    }));
    return [
      for (final r in full)
        if (r != null && !query.excludeIngredients.any((x) => r.ingredients.any((i) => i.key.contains(x.toLowerCase())))) r,
    ];
  }

  @override
  Future<List<RecipeData>> random(int count, {String? tag}) => search(RecipeQuery(limit: count));

  @override
  Future<RecipeData?> lookup(String sourceId) async {
    final j = await _get('/api/recipes/${Uri.encodeComponent(sourceId)}', const {});
    return j is Map<String, Object?> && j['title'] is String ? parseRecipe(j) : null;
  }

  @override
  Future<List<String>> cuisines() async => const [];

  /// Normalizes one recipe. Amounts are for one serving.
  RecipeData parseRecipe(Map<String, Object?> j) {
    final sourceId = '${j['id']}';
    final image = j['image'] as String?;
    final tags = [for (final t in (j['tags'] as List? ?? const [])) '$t'];
    return RecipeData(
      id: providerRecipeId(id, sourceId),
      source: id,
      sourceId: sourceId,
      url: base.replace(path: '/en/recipe/$sourceId').toString(),
      title: j['title']! as String,
      imageUrl: image == null || image.isEmpty ? null : (image.startsWith('http') ? image : base.replace(path: image).toString()),
      servings: 1,
      totalMin: (j['timeMin'] as num?)?.toInt(),
      category: switch (j['slot']) { 'breakfast' => 'Breakfast', 'lunch' => 'Lunch', 'dinner' => 'Dinner', 'snack' => 'Snack', _ => null },
      tags: [
        for (final t in tags) ?_tags[t],
      ],
      ingredients: [
        for (final i in (j['ingredients'] as List? ?? const []).whereType<Map<String, Object?>>())
          if (i['name'] is String) ingredientFromMeasure(_measure(i['amount'] as num?, i['unit'] as String?), i['name']! as String),
      ],
      steps: [
        for (final s in (j['steps'] as List? ?? const []))
          if ('$s'.trim().isNotEmpty) '$s'.trim(),
      ],
      summary: j['description'] as String?,
      attribution: 'Racion (racion.app)',
    );
  }

  /// "140 g", "1" (pieces have no unit), "" for "to taste".
  static String _measure(num? amount, String? unit) {
    if (amount == null || amount <= 0) return '';
    final n = amount == amount.roundToDouble() ? '${amount.round()}' : '$amount';
    final u = unit == null || const {'pcs', 'pc', 'piece', 'pieces'}.contains(unit) ? '' : unit;
    return '$n $u'.trim();
  }

  /// Racion's tags worth keeping, in Dearth's words.
  static const Map<String, String> _tags = {
    'quick': 'quick', 'poultry': 'poultry', 'meat': 'meat', 'fish': 'fish', 'vegetarian': 'vegetarian', 'vegan': 'vegan', //
    'soup': 'soup', 'salad': 'salad', 'baking': 'baking', 'dessert': 'dessert', 'breakfast': 'breakfast', 'pp': 'healthy',
  };
}
