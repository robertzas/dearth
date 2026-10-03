import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_integrations/dearth_integrations.dart' show CatalogRecipes, RecipeQuery, recipeCatalog;
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/calendar.dart';
import '../../core/data/household.dart';
import '../../core/data/household_data.dart';
import '../../core/providers.dart';
import '../../core/sync/hub_api.dart';
import 'meal_ops.dart';

// ───────────────────────────── Local recipes ───────────────────────────────

/// Every local recipe (planned or saved) by id.
final localRecipesProvider = StreamProvider<Map<String, Recipe>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.recipes)..where((r) => r.deleted.equals(false))).watch().map((rows) => {for (final r in rows) r.id: r});
});

/// The local row for [r], if it has been planned or saved before.
Recipe? localRowOf(Map<String, Recipe> local, RecipeData r) => local[r.id] ?? local[localRecipeId(r)];

/// The family recipe box (SPEC FR-RCP-01), A–Z.
final recipeBoxProvider = Provider<List<Recipe>>((ref) {
  final all = ref.watch(localRecipesProvider).value ?? const <String, Recipe>{};
  return all.values.where((r) => r.saved).toList()..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
});

/// recipe id → profile id → score ([kRatingFaces]).
final recipeRatingsProvider = StreamProvider<Map<String, Map<String, int>>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.recipeRatings)..where((r) => r.deleted.equals(false))).watch().map((rows) {
    final out = <String, Map<String, int>>{};
    for (final r in rows) {
      (out[r.recipeId] ??= {})[r.profileId] = r.score;
    }
    return out;
  });
});

/// Mean family rating per recipe id: a plan-scoring input (SPEC FR-RCP-09).
final familyRatingProvider = Provider<Map<String, double>>((ref) {
  final all = ref.watch(recipeRatingsProvider).value ?? const <String, Map<String, int>>{};
  return {
    for (final e in all.entries)
      if (e.value.isNotEmpty) e.key: e.value.values.fold<int>(0, (a, b) => a + b) / e.value.length,
  };
});

/// The list "Add to list" fills: the first shopping list, read once. (A
/// one-shot query, not a provider: Riverpod pauses providers nothing
/// listens to, so reading one from a handler can wait forever.)
Future<DList?> shoppingListOnce(DearthDb db) => (db.select(db.lists)
      ..where((l) => l.deleted.equals(false) & l.kind.equals('shopping') & l.isTemplate.equals(false))
      ..orderBy([(l) => OrderingTerm.asc(l.sortKey)])
      ..limit(1))
    .getSingleOrNull();

/// A list's live items, read once (for "Add to list").
Future<List<ListItem>> listItemsOnce(DearthDb db, String listId) =>
    (db.select(db.listItems)..where((i) => i.listId.equals(listId) & i.deleted.equals(false))).get();

// ──────────────────────────────── Planner ──────────────────────────────────

/// Which week the planner shows, as an offset from the current one.
class MealWeekController extends Notifier<int> {
  @override
  int build() => 0;

  void step(int direction) => state += direction;
  void thisWeek() => state = 0;
}

final mealWeekOffsetProvider = NotifierProvider<MealWeekController, int>(MealWeekController.new);

/// The planner's days: the household's week, [mealWeekOffsetProvider] away.
final mealWeekProvider = Provider<DayRange>((ref) {
  final today = ref.watch(todayProvider);
  final start = today.startOfWeek(ref.watch(weekStartProvider)).addDays(7 * ref.watch(mealWeekOffsetProvider));
  return DayRange(start, 7);
});

/// The recipes planned in [range], for shopping and recommendations.
List<RecipeData> plannedRecipes(List<PlannedMeal> meals) => [
      for (final m in meals)
        if (m.recipe != null) RecipeData.fromRow(m.recipe!),
    ];

/// The planner week at a glance (SPEC FR-MEAL-02).
class PlanSummary {
  const PlanSummary({required this.meals, required this.recipes, required this.lines});
  final int meals;
  final int recipes;

  /// The consolidated shopping lines, staples included.
  final List<ShoppingLine> lines;

  int get toBuy => lines.where((l) => !l.staple).length;

  /// Ingredients more than one planned recipe uses.
  int get shared => lines.where((l) => !l.staple && l.recipes.length > 1).length;
}

/// Planned recipes for [meals] with their entry servings and a short label
/// ("Tacos (Tue)") for the shopping sources.
List<PlannedRecipe> plannedForShopping(List<PlannedMeal> meals, {required int defaultServings, required String Function(LocalDate) dayLabel}) => [
      for (final m in meals)
        if (m.recipe case final Recipe r when m.entry.leftoversOf == null)
          PlannedRecipe(
            RecipeData.fromRow(r),
            m.entry.servings ?? defaultServings,
            label: '${r.title} (${LocalDate.tryParse(m.entry.date) == null ? m.entry.date : dayLabel(LocalDate.parse(m.entry.date))})',
          ),
    ];

final planSummaryProvider = Provider<PlanSummary>((ref) {
  final meals = ref.watch(mealsInRangeProvider(ref.watch(mealWeekProvider))).value ?? const <PlannedMeal>[];
  final planned = plannedForShopping(meals, defaultServings: ref.watch(defaultServingsProvider), dayLabel: shortWeekday);
  return PlanSummary(meals: meals.length, recipes: planned.length, lines: consolidate(planned));
});

/// "Tue" without pulling intl into the data layer.
String shortWeekday(LocalDate d) => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];

/// Default servings for a new plan entry: the household's people (pets and
/// guests aside), at least 2.
final defaultServingsProvider = Provider<int>((ref) {
  final n = ref.watch(familyProvider).where((p) => p.role != 'pet').length;
  return n < 2 ? 2 : n;
});

// ─────────────────────────────── Discovery ─────────────────────────────────

/// Discover feeds (SPEC FR-RCP-04) that every source supports.
enum RecipeFeed {
  quick('quick', 'Quick weeknights', '⚡'),
  popular('popular', 'Popular this week', '🔥'),
  seasonal('seasonal', 'In season now', '🍂'),
  surprise('surprise', 'Surprise me', '🎲');

  const RecipeFeed(this.id, this.label, this.emoji);
  final String id;
  final String label;
  final String emoji;
}

/// Where recipes come from (SPEC FR-RCP-01): the Hub's providers when paired,
/// the bundled catalog otherwise (demo, offline). Widgets never call
/// providers directly (AGENTS.md rule 7).
abstract interface class RecipeSource {
  Future<List<RecipeData>> search(RecipeQuery query);
  Future<List<RecipeData>> feed(RecipeFeed feed);
  Future<List<String>> cuisines();

  /// "Pairs with your plan" candidates, best first (SPEC FR-RCP-09).
  Future<List<ReuseScore>> pairsWith(List<RecipeData> planned, {Map<String, double> ratings = const {}, List<RecipeData> box = const []});
}

class CatalogRecipeSource implements RecipeSource {
  CatalogRecipeSource({int seed = 7}) : _catalog = CatalogRecipes(seed: seed);
  final CatalogRecipes _catalog;

  @override
  Future<List<RecipeData>> search(RecipeQuery query) => _catalog.search(query);

  @override
  Future<List<RecipeData>> feed(RecipeFeed feed) => switch (feed) {
        RecipeFeed.quick => _catalog.search(const RecipeQuery(maxMinutes: 30, limit: 12)),
        RecipeFeed.popular => _catalog.random(12),
        RecipeFeed.seasonal => _catalog.search(const RecipeQuery(includeIngredients: ['squash', 'apple', 'sweet potato', 'pumpkin'], limit: 12)),
        RecipeFeed.surprise => _catalog.random(8),
      };

  @override
  Future<List<String>> cuisines() => _catalog.cuisines();

  @override
  Future<List<ReuseScore>> pairsWith(List<RecipeData> planned, {Map<String, double> ratings = const {}, List<RecipeData> box = const []}) async {
    if (planned.isEmpty) return const [];
    final plan = PlanContext.fromRecipes(planned);
    final seen = <String>{};
    final pool = [
      for (final r in [...box, ...recipeCatalog])
        if (seen.add(localRecipeId(r))) r,
    ];
    return rankForPlan(pool, plan, ratings: ratings).where((s) => s.score > -50).take(10).toList();
  }
}

class HubRecipeSource implements RecipeSource {
  HubRecipeSource(this.api);
  final HubApi api;

  static List<RecipeData> _decode(List<Map<String, Object?>> rows) => [for (final j in rows) RecipeData.fromJson(j)];

  @override
  Future<List<RecipeData>> search(RecipeQuery q) async => _decode(await api.getList('/api/recipes/search', {
        if (q.text != null && q.text!.isNotEmpty) 'q': q.text!,
        if (q.cuisine != null) 'cuisine': q.cuisine!,
        if (q.category != null) 'category': q.category!,
        if (q.maxMinutes != null) 'maxMinutes': '${q.maxMinutes}',
        if (q.includeIngredients.isNotEmpty) 'include': q.includeIngredients.join(','),
        if (q.excludeIngredients.isNotEmpty) 'exclude': q.excludeIngredients.join(','),
        'limit': '${q.limit}',
      }));

  @override
  Future<List<RecipeData>> feed(RecipeFeed feed) async => _decode(await api.getList('/api/recipes/discover/${feed.id}'));

  @override
  Future<List<String>> cuisines() => api.getStrings('/api/recipes/cuisines');

  @override
  Future<List<ReuseScore>> pairsWith(List<RecipeData> planned, {Map<String, double> ratings = const {}, List<RecipeData> box = const []}) async {
    if (planned.isEmpty) return const [];
    final rows = await api.postList('/api/recipes/recommend', {
      'recipes': [for (final r in planned) r.toJson()],
      'ratings': ratings,
      'limit': 10,
    });
    return [
      for (final j in rows)
        if (j['recipe'] case final Map<String, Object?> recipe)
          ReuseScore(
            recipe: RecipeData.fromJson(recipe),
            score: (j['score'] as num?)?.toDouble() ?? 0,
            matched: [for (final m in (j['matched'] as List? ?? const [])) '$m'],
            added: [for (final a in (j['added'] as List? ?? const [])) '$a'],
            explanation: j['why'] as String? ?? '',
          ),
    ];
  }
}

final recipeSourceProvider = Provider<RecipeSource>((ref) {
  final api = ref.watch(hubApiProvider);
  return api == null ? CatalogRecipeSource() : HubRecipeSource(api);
});

final recipeFeedProvider = FutureProvider.family<List<RecipeData>, RecipeFeed>((ref, feed) => ref.watch(recipeSourceProvider).feed(feed));

/// Search results: matching family-box recipes first, then the source's,
/// without duplicates (SPEC FR-RCP-03).
final recipeSearchProvider = FutureProvider.autoDispose.family<List<RecipeData>, String>((ref, text) async {
  final q = text.trim().toLowerCase();
  final box = ref.watch(recipeBoxProvider);
  final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  final mine = [
    for (final r in box)
      if (words.every('${r.title} ${r.cuisine ?? ''} ${r.category ?? ''}'.toLowerCase().contains)) RecipeData.fromRow(r),
  ];
  final remote = await ref.watch(recipeSourceProvider).search(RecipeQuery(text: q, limit: 24));
  final seen = {for (final r in mine) r.id};
  return [
    ...mine,
    for (final r in remote)
      if (seen.add(localRecipeId(r))) r,
  ];
});

/// "Pairs with your plan" for the planner's week (SPEC FR-RCP-09/10).
final planPairsProvider = FutureProvider.autoDispose<List<ReuseScore>>((ref) async {
  final week = ref.watch(mealWeekProvider);
  final meals = ref.watch(mealsInRangeProvider(week)).value ?? const <PlannedMeal>[];
  final planned = plannedRecipes(meals);
  final box = [for (final r in ref.watch(recipeBoxProvider)) RecipeData.fromRow(r)];
  return ref.watch(recipeSourceProvider).pairsWith(planned, ratings: ref.watch(familyRatingProvider), box: box);
});

/// Family favorites: rated recipes, best first (SPEC FR-RCP-04).
final familyFavoritesProvider = Provider<List<Recipe>>((ref) {
  final local = ref.watch(localRecipesProvider).value ?? const <String, Recipe>{};
  final ratings = ref.watch(familyRatingProvider);
  final rated = [
    for (final e in ratings.entries)
      if (e.value >= 1 && local[e.key] != null) (local[e.key]!, e.value),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  return [for (final (r, _) in rated) r];
});
