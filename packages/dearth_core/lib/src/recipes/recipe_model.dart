import 'package:meta/meta.dart';

import '../db/database.dart';
import '../util/json.dart';
import 'ingredients.dart';

/// Provider-neutral recipe (SPEC FR-RCP-02). Providers, the planner, the
/// shopping list and the UI all speak this type.
@immutable
class RecipeData {
  const RecipeData({
    required this.id,
    required this.source,
    required this.title,
    this.sourceId,
    this.url,
    this.imageUrl,
    this.imageBlob,
    this.servings = 4,
    this.prepMin,
    this.cookMin,
    this.totalMin,
    this.cuisine,
    this.category,
    this.tags = const [],
    this.diets = const [],
    this.ingredients = const [],
    this.steps = const [],
    this.attribution,
    this.popularity,
    this.summary,
  });

  factory RecipeData.fromRow(Recipe r) => RecipeData(
        id: r.id,
        source: r.source,
        sourceId: r.sourceId,
        url: r.url,
        title: r.title,
        imageUrl: r.imageUrl,
        imageBlob: r.imageBlob,
        servings: r.servings,
        prepMin: r.prepMin,
        cookMin: r.cookMin,
        totalMin: r.totalMin,
        cuisine: r.cuisine,
        category: r.category,
        tags: decodeStringList(r.tags),
        diets: decodeStringList(r.diets),
        ingredients: [for (final m in decodeMapList(r.ingredients)) Ingredient.fromJson(m)],
        steps: decodeStringList(r.steps),
        attribution: r.attribution,
      );

  factory RecipeData.fromJson(Map<String, Object?> j) => RecipeData(
        id: j['id'] as String? ?? '',
        source: j['source'] as String? ?? 'box',
        sourceId: j['sourceId'] as String?,
        url: j['url'] as String?,
        title: j['title'] as String? ?? '',
        imageUrl: j['imageUrl'] as String?,
        imageBlob: j['imageBlob'] as String?,
        servings: (j['servings'] as num?)?.toInt() ?? 4,
        prepMin: (j['prepMin'] as num?)?.toInt(),
        cookMin: (j['cookMin'] as num?)?.toInt(),
        totalMin: (j['totalMin'] as num?)?.toInt(),
        cuisine: j['cuisine'] as String?,
        category: j['category'] as String?,
        tags: [for (final t in j.arr('tags')) '$t'],
        diets: [for (final t in j.arr('diets')) '$t'],
        ingredients: [for (final i in j.arr('ingredients')) if (i is Map<String, Object?>) Ingredient.fromJson(i)],
        steps: [for (final s in j.arr('steps')) '$s'],
        attribution: j['attribution'] as String?,
        popularity: (j['popularity'] as num?)?.toDouble(),
        summary: j['summary'] as String?,
      );

  /// Local row id (or `provider:sourceId` for unsaved search results).
  final String id;

  /// themealdb | spoonacular | web | box | demo
  final String source;
  final String? sourceId;
  final String? url;
  final String title;
  final String? imageUrl;
  final String? imageBlob;
  final int servings;
  final int? prepMin;
  final int? cookMin;
  final int? totalMin;
  final String? cuisine;
  final String? category;
  final List<String> tags;
  final List<String> diets;
  final List<Ingredient> ingredients;
  final List<String> steps;
  final String? attribution;
  final double? popularity;
  final String? summary;

  int? get minutes => totalMin ?? ((prepMin ?? 0) + (cookMin ?? 0) == 0 ? null : (prepMin ?? 0) + (cookMin ?? 0));

  /// Non-staple ingredient keys (what matters for reuse and shopping).
  Set<String> get keys => {for (final i in ingredients) if (!i.isStaple && i.key.isNotEmpty) i.key};

  List<Ingredient> scaledIngredients(int toServings) {
    if (servings <= 0 || toServings == servings) return ingredients;
    final f = toServings / servings;
    return [for (final i in ingredients) i.scaled(f)];
  }

  /// Column map for `Mutator.upsert('recipes', …)`.
  Map<String, Object?> toFields({bool saved = true}) => {
        'source': source,
        'source_id': sourceId,
        'url': url,
        'title': title,
        'image_url': imageUrl,
        'image_blob': imageBlob,
        'servings': servings,
        'prep_min': prepMin,
        'cook_min': cookMin,
        'total_min': totalMin,
        'cuisine': cuisine,
        'category': category,
        'tags': tags,
        'diets': diets,
        'ingredients': [for (final i in ingredients) i.toJson()],
        'steps': steps,
        'attribution': attribution,
        'saved': saved,
      };

  Map<String, Object?> toJson() => {
        'id': id,
        'source': source,
        'sourceId': sourceId,
        'url': url,
        'title': title,
        'imageUrl': imageUrl,
        'imageBlob': imageBlob,
        'servings': servings,
        'prepMin': prepMin,
        'cookMin': cookMin,
        'totalMin': totalMin,
        'cuisine': cuisine,
        'category': category,
        'tags': tags,
        'diets': diets,
        'ingredients': [for (final i in ingredients) i.toJson()],
        'steps': steps,
        'attribution': attribution,
        'popularity': popularity,
        'summary': summary,
      };

  RecipeData copyWith({String? id, String? imageBlob}) => RecipeData(
        id: id ?? this.id,
        source: source,
        sourceId: sourceId,
        url: url,
        title: title,
        imageUrl: imageUrl,
        imageBlob: imageBlob ?? this.imageBlob,
        servings: servings,
        prepMin: prepMin,
        cookMin: cookMin,
        totalMin: totalMin,
        cuisine: cuisine,
        category: category,
        tags: tags,
        diets: diets,
        ingredients: ingredients,
        steps: steps,
        attribution: attribution,
        popularity: popularity,
        summary: summary,
      );
}

/// Extracts step timers ("bake 25 minutes", "simmer for 1 hour") for cook
/// mode (FR-RCP-07). Returns durations in seconds with the matched phrase.
List<(int seconds, String label)> stepTimers(String step) {
  final out = <(int, String)>[];
  final re = RegExp(
    r'(\d+(?:\.\d+)?)(?:\s*(?:-|–|to)\s*(\d+(?:\.\d+)?))?\s*(hours?|hrs?|minutes?|mins?|seconds?|secs?)\b',
    caseSensitive: false,
  );
  for (final m in re.allMatches(step)) {
    final a = double.parse(m[2] ?? m[1]!); // use the upper bound of ranges
    final unit = m[3]!.toLowerCase();
    final seconds = unit.startsWith('h') ? a * 3600 : (unit.startsWith('m') ? a * 60 : a);
    if (seconds >= 30 && seconds <= 24 * 3600) out.add((seconds.round(), m[0]!));
  }
  return out;
}
