import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';

import 'recipe_provider.dart';

/// One search across every recipe source (SPEC FR-RCP-13).
class AggregatedSearch {
  const AggregatedSearch(this.recipes, {this.answered = const [], this.skipped = const []});
  final List<RecipeData> recipes;

  /// Sources that answered (even with nothing).
  final List<String> answered;

  /// Sources left out of this search: too slow, failed, or out of budget.
  final List<String> skipped;
}

/// Asks every source at once and folds the answers into one list (SPEC
/// FR-RCP-13): a slow or failing source is left out after [timeout] rather
/// than holding up the rest.
Future<AggregatedSearch> searchEverywhere(
  Iterable<RecipeProvider> providers,
  RecipeQuery query, {
  Duration timeout = const Duration(seconds: 6),
  void Function(String provider, Object error)? onError,
}) async {
  final answers = await Future.wait([
    for (final p in providers)
      p.search(query).timeout(timeout).then<(String, List<RecipeData>?)>((r) => (p.id, r), onError: (Object e) {
        onError?.call(p.id, e);
        return (p.id, null);
      }),
  ]);
  return AggregatedSearch(
    blendRecipes([for (final (_, r) in answers) ...?r], query),
    answered: [for (final (id, r) in answers) if (r != null) id],
    skipped: [for (final (id, r) in answers) if (r == null) id],
  );
}

/// Every source's recipes as one list: tidied into the same shape, the
/// same dish from several sources merged into one card, ranked by how well
/// each fits [query], and interleaved so no one source fills the top.
List<RecipeData> blendRecipes(Iterable<RecipeData> found, RecipeQuery query) {
  final merged = mergeSameDishes([for (final r in found) tidyRecipe(r)]);
  final scored = [for (final r in merged) (r, recipeScore(r, query))]..sort((a, b) => b.$2.compareTo(a.$2));
  return interleaveSources(scored).take(query.limit).toList();
}

// ── One shape ─────────────────────────────────────────────────────────────

/// A recipe in Dearth's own words: a tidy title, total time filled in,
/// cuisine, course and diets from one vocabulary, tags lowercased.
RecipeData tidyRecipe(RecipeData r) {
  final cuisine = _cuisine(r.cuisine);
  return RecipeData(
    id: r.id,
    source: r.source,
    sourceId: r.sourceId,
    url: r.url,
    title: tidyTitle(r.title),
    imageUrl: (r.imageUrl?.isEmpty ?? true) ? null : r.imageUrl,
    imageBlob: r.imageBlob,
    servings: r.servings > 0 ? r.servings : 4,
    prepMin: r.prepMin,
    cookMin: r.cookMin,
    totalMin: r.totalMin ?? r.minutes,
    cuisine: cuisine,
    category: _course(r.category),
    tags: {for (final t in r.tags) if (t.trim().isNotEmpty) t.trim().toLowerCase()}.toList(),
    diets: {for (final d in r.diets) ?_diet(d)}.toList(),
    ingredients: r.ingredients,
    steps: r.steps,
    attribution: r.attribution,
    popularity: r.popularity,
    summary: (r.summary?.trim().isEmpty ?? true) ? null : r.summary!.trim(),
    alsoFrom: r.alsoFrom,
  );
}

const _small = {'a', 'an', 'and', 'or', 'of', 'with', 'in', 'on', 'the', 'to', 'for', 'de', 'la', 'al'};

/// "EASY CHICKEN CURRY RECIPE 🍛" → "Easy Chicken Curry".
String tidyTitle(String title) {
  var s = title.replaceAll(RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]', unicode: true), ' ');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  s = s.replaceFirst(RegExp(r'\s+recipes?$', caseSensitive: false), '').replaceFirst(RegExp(r'[\s.!:;,–-]+$'), '');
  final letters = s.replaceAll(RegExp('[^A-Za-z]'), '');
  if (letters.length > 3 && letters == letters.toUpperCase()) {
    final words = s.toLowerCase().split(' ');
    s = [
      for (var i = 0; i < words.length; i++)
        if (i > 0 && _small.contains(words[i])) words[i] else if (words[i].isEmpty) words[i] else words[i][0].toUpperCase() + words[i].substring(1),
    ].join(' ');
  }
  return s.isEmpty ? title.trim() : s;
}

String? _cuisine(String? c) {
  final s = c?.trim().toLowerCase() ?? '';
  if (s.isEmpty || s == 'unknown' || s == 'other' || s == 'international') return null;
  final alias = const {'usa': 'American', 'us': 'American', 'america': 'American', 'uk': 'British', 'english': 'British', 'tex mex': 'Tex-Mex'}[s];
  return alias ?? s.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');
}

/// Courses in one vocabulary; anything else (TheMealDB's "Chicken",
/// Wikibooks' "Curry") is kept, title-cased.
String? _course(String? c) {
  final s = c?.trim().toLowerCase() ?? '';
  if (s.isEmpty || s == 'miscellaneous' || s == 'other') return null;
  for (final MapEntry(key: course, value: names) in _courses.entries) {
    if (names.contains(s)) return course;
  }
  return s[0].toUpperCase() + s.substring(1);
}

const Map<String, Set<String>> _courses = {
  'Main course': {'main course', 'main', 'main dish', 'mains', 'dinner', 'entree', 'entrée'},
  'Breakfast': {'breakfast', 'brunch'},
  'Lunch': {'lunch'},
  'Side': {'side', 'side dish', 'sides'},
  'Starter': {'starter', 'starters', 'appetizer', 'appetizers', 'appetiser'},
  'Soup': {'soup', 'soups'},
  'Salad': {'salad', 'salads'},
  'Dessert': {'dessert', 'desserts', 'sweet', 'sweets'},
  'Snack': {'snack', 'snacks'},
  'Drink': {'drink', 'drinks', 'beverage', 'beverages'},
  'Sauce': {'sauce', 'sauces', 'condiment'},
  'Baking': {'baking', 'bread', 'breads'},
};

String? _diet(String d) {
  final s = d.trim().toLowerCase().replaceAll(RegExp('[-_]'), ' ').replaceAll(RegExp(r'\s+'), ' ');
  if (s.isEmpty) return null;
  return const {
        'lacto ovo vegetarian': 'vegetarian',
        'ovo vegetarian': 'vegetarian',
        'lacto vegetarian': 'vegetarian',
        'pescetarian': 'pescatarian',
        'ketogenic': 'keto',
        'whole 30': 'whole30',
        'gluten free friendly': 'gluten free',
      }[s] ??
      s;
}

// ── The same dish ─────────────────────────────────────────────────────────

const _fillers = {
  'the', 'a', 'an', 'and', 'with', 'easy', 'best', 'simple', 'quick', 'homemade', 'classic', 'perfect', 'my', 'our', 'recipe', //
  'style', 'authentic', 'ultimate', 'delicious', 'favorite', 'favourite', 'tasty', 'i', 'ii', 'iii',
};

/// A dish's title reduced to its words, in order-free form: "The Best
/// Chicken Curry" and "Curry, chicken" are both "chicken curry".
String dishKey(String title) {
  var s = title.toLowerCase().replaceAll('&', ' and ');
  const accents = {'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'í': 'i', 'î': 'i', 'ï': 'i', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ñ': 'n', 'ç': 'c'};
  s = s.split('').map((ch) => accents[ch] ?? ch).join();
  final words = [
    for (final w in s.replaceAll(RegExp('[^a-z0-9 ]'), ' ').split(' '))
      if (w.isNotEmpty && !_fillers.contains(w)) w.length > 3 && w.endsWith('s') && !w.endsWith('ss') ? w.substring(0, w.length - 1) : w,
  ]..sort();
  return words.join(' ');
}

double _jaccard(Set<String> a, Set<String> b) => a.isEmpty && b.isEmpty ? 0 : a.intersection(b).length / a.union(b).length;

/// Folds the same dish from different sources into one recipe: the most
/// complete one, filled in from the others (a photo, times, a cuisine),
/// listing them in [RecipeData.alsoFrom]. Two recipes are the same dish
/// when their titles reduce to the same words, or nearly (three in four
/// words) with most ingredients in common. A source's own recipes are
/// never merged with each other: two curries from one cookbook are two.
List<RecipeData> mergeSameDishes(List<RecipeData> recipes) {
  final groups = <List<RecipeData>>[];
  for (final r in recipes) {
    if (groups.any((g) => g.any((x) => x.id == r.id))) continue;
    final key = dishKey(r.title);
    final words = key.split(' ').toSet();
    final same = groups.where((g) {
      if (g.any((x) => x.source == r.source)) return false;
      final k = dishKey(g.first.title);
      return k == key || (_jaccard(words, k.split(' ').toSet()) >= 0.75 && _jaccard(r.keys, g.first.keys) >= 0.4);
    }).firstOrNull;
    same == null ? groups.add([r]) : same.add(r);
  }
  return [for (final g in groups) _merge(g)];
}

RecipeData _merge(List<RecipeData> same) {
  if (same.length == 1) return same.single;
  final byCompleteness = [...same]..sort((a, b) => recipeCompleteness(b).compareTo(recipeCompleteness(a)));
  final best = byCompleteness.first;
  T? first<T extends Object>(T? Function(RecipeData r) f) => byCompleteness.map(f).nonNulls.firstOrNull;
  return best.copyWith(
    imageUrl: first((r) => r.imageUrl),
    prepMin: first((r) => r.prepMin),
    cookMin: first((r) => r.cookMin),
    totalMin: first((r) => r.totalMin),
    cuisine: first((r) => r.cuisine),
    category: first((r) => r.category),
    summary: first((r) => r.summary),
    alsoFrom: {for (final r in byCompleteness.skip(1)) r.source, for (final r in same) ...r.alsoFrom}.difference({best.source}).toList(),
  );
}

// ── Ranking ───────────────────────────────────────────────────────────────

/// How much of a recipe there is to cook from: a photo, steps, a real
/// ingredient list, a time, a description.
double recipeCompleteness(RecipeData r) =>
    (r.imageUrl != null ? 1.0 : 0) + (r.steps.length >= 2 ? 1.0 : 0) + (r.ingredients.length >= 3 ? 0.6 : 0) + (r.minutes != null ? 0.4 : 0) + ((r.summary?.isNotEmpty ?? false) ? 0.2 : 0);

List<String> _words(String s) => [
      for (final w in s.toLowerCase().replaceAll(RegExp('[^a-z0-9 ]'), ' ').split(' '))
        if (w.length > 1 && !_fillers.contains(w)) w,
    ];

/// How well [r] answers [q]: the searched words in its title count most,
/// then in its ingredients, tags, cuisine and course; wanted ingredients;
/// completeness; several sources agreeing; and a little popularity.
double recipeScore(RecipeData r, RecipeQuery q) {
  var s = recipeCompleteness(r);
  final text = q.text?.trim().toLowerCase() ?? '';
  final words = _words(text);
  if (words.isNotEmpty) {
    final title = _words(r.title).toSet();
    final other = [...r.keys, ...r.tags, ?r.cuisine?.toLowerCase(), ?r.category?.toLowerCase()];
    bool near(String w, String t) => t == w || (w.length > 3 && (t.startsWith(w) || w.startsWith(t)));
    final inTitle = words.where((w) => title.any((t) => near(w, t))).length / words.length;
    final anywhere = words.where((w) => title.any((t) => near(w, t)) || other.any((o) => o.contains(w))).length / words.length;
    s += 4 * inTitle + 1.5 * anywhere + (r.title.toLowerCase().contains(text) ? 1 : 0);
  }
  if (q.includeIngredients.isNotEmpty) {
    final have = q.includeIngredients.where((i) => r.keys.any((k) => k.contains(i.toLowerCase()))).length;
    s += 3 * have / q.includeIngredients.length;
  }
  return s + 0.4 * r.alsoFrom.length + math.min(1, math.log(1 + (r.popularity ?? 0)) / 8);
}

/// Best first, but never the same source twice running when another
/// source's recipe is nearly as good (within a fifth).
List<RecipeData> interleaveSources(List<(RecipeData, double)> ranked) {
  final left = [...ranked];
  final out = <RecipeData>[];
  String? last;
  while (left.isNotEmpty) {
    var pick = 0;
    if (left.first.$1.source == last) {
      final other = left.indexWhere((x) => x.$1.source != last);
      if (other > 0 && left[other].$2 >= left.first.$2 * 0.8) pick = other;
    }
    final (r, _) = left.removeAt(pick);
    out.add(r);
    last = r.source;
  }
  return out;
}
