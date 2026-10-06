import 'dart:async';
import 'dart:convert';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_integrations/dearth_integrations.dart';
import 'package:drift/drift.dart';
import 'package:logging/logging.dart';

import 'integrations.dart';

final _log = Logger('recipes');

/// Multi-provider recipe search with caching, discovery feeds and plan-aware
/// recommendations (SPEC §10.5, §13.6). Provider failures degrade to the
/// remaining providers, the recipes remembered from earlier and the bundled
/// catalog.
///
/// Every recipe an API returns is kept in `recipe_cache` indefinitely
/// (owner request, 2026-10-06): when sources fall short (offline, a quota
/// spent, an API gone), remembered recipes that fit fill a search, and
/// "pairs with your plan" ranks everything ever seen.
class RecipeService {
  RecipeService(this.integrations, this.fetcher);

  final Integrations integrations;
  final Fetcher fetcher;

  /// Answers to recent searches and feeds, so paging and going back don't
  /// spend quota. The recipes in them are kept for good in [_remembered].
  final Map<String, (int, List<RecipeData>)> _cache = {};
  static const _ttl = Duration(hours: 12);
  static const _maxCache = 400;

  /// Every recipe ever fetched, by id: `recipe_cache`, read once.
  Map<String, RecipeData>? _kept;

  /// A recipe returned earlier, from any source, however long ago.
  Future<RecipeData?> known(String id) async => (await _remembered())[id];

  Future<Map<String, RecipeData>> _remembered() async {
    if (_kept != null) return _kept!;
    final db = integrations.db;
    final kept = <String, RecipeData>{};
    for (final row in await db.select(db.recipeCache).get()) {
      try {
        kept[row.id] = RecipeData.fromJson(decodeJsonMap(row.data));
      } on Object catch (e) {
        _log.warning('Skipping remembered recipe ${row.id}: $e');
      }
    }
    return _kept ??= kept;
  }

  /// Sources never kept: the bundled catalog and the family's box are here
  /// already, and Spoonacular's terms forbid storing its recipes (only an id,
  /// title and image may be kept; anything cached goes after an hour).
  static const _neverKept = {'catalog', 'box', 'spoonacular'};

  /// Keeps [recipes] for good: a new one is added, a known one refreshed.
  /// One batch, however many.
  Future<void> _remember(Iterable<RecipeData> recipes) async {
    final fresh = {for (final r in recipes) if (r.id.isNotEmpty && !_neverKept.contains(r.source)) r.id: r};
    if (fresh.isEmpty) return;
    final kept = await _remembered();
    final db = integrations.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.batch((b) {
      for (final r in fresh.values) {
        final data = jsonEncode(r.toJson());
        b.insert(
          db.recipeCache,
          RecipeCacheCompanion.insert(id: r.id, source: r.source, title: r.title, data: data, firstSeenMs: now, lastSeenMs: now),
          onConflict: DoUpdate((_) => RecipeCacheCompanion(source: Value(r.source), title: Value(r.title), data: Value(data), lastSeenMs: Value(now))),
        );
      }
    });
    kept.addAll(fresh);
  }

  /// How many recipes are kept.
  Future<int> rememberedCount() async => (await _remembered()).length;

  /// The sources that answered the last search, and those left out of it.
  ({List<String> answered, List<String> skipped}) lastSources = (answered: const [], skipped: const []);

  /// Every enabled source at once, blended into one list: one shape, the
  /// same dish merged, best fit first, sources taking turns (FR-RCP-13).
  Future<List<RecipeData>> search(RecipeQuery q) => _cached('search|${q.cacheKey}', () async {
        final found = await searchEverywhere(await integrations.recipeProviders(), q, onError: (p, e) {
          if (e is! QuotaExceededException) _log.warning('Recipe provider $p left out: $e');
        });
        lastSources = (answered: found.answered, skipped: found.skipped);
        await _remember(found.recipes);
        // Short of a full page (a source offline or out of quota): the
        // recipes remembered from earlier that fit come after.
        if (found.recipes.length >= q.limit) return found.recipes;
        final have = {for (final r in found.recipes) _titleKey(r.title)};
        final extra = [for (final r in matchRecipes((await _remembered()).values, RecipeQuery(text: q.text, cuisine: q.cuisine, category: q.category, maxMinutes: q.maxMinutes, includeIngredients: q.includeIngredients, excludeIngredients: q.excludeIngredients, limit: q.limit * 2))) if ((q.diet == null || r.diets.contains(q.diet)) && have.add(_titleKey(r.title))) r];
        return [...found.recipes, ...extra].take(q.limit).toList();
      });

  static String _titleKey(String title) => title.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  /// Forgets cached answers (a source was switched on or off, or got a key).
  void clearCache() => _cache.clear();

  /// Discovery feeds (FR-RCP-04).
  Future<List<RecipeData>> discover(String feed, {int limit = 12, String? arg, int? month}) {
    return _cached('feed|$feed|$arg|$limit|$month', () async {
      final providers = await integrations.recipeProviders();
      final catalog = providers.whereType<CatalogRecipes>().firstOrNull ?? CatalogRecipes();
      final online = providers.where((p) => p is! CatalogRecipes).toList();
      Future<List<RecipeData>> first(Future<List<RecipeData>> Function(RecipeProvider p) run) async {
        for (final p in online) {
          final r = await _safe(p.id, () => run(p));
          if (r.isNotEmpty) return r;
        }
        return const [];
      }

      switch (feed) {
        case 'popular':
          final spoon = online.whereType<Spoonacular>().firstOrNull;
          final r = spoon == null ? <RecipeData>[] : await _safe(spoon.id, () => spoon.search(RecipeQuery(sortByPopularity: true, limit: limit)));
          return _dedupe([...r, ...await first((p) => p.random(limit)), ...await catalog.random(limit)]).take(limit).toList();
        case 'surprise':
          return _dedupe([...await first((p) => p.random(6)), ...await catalog.random(limit)]).take(limit).toList();
        case 'quick':
          return _dedupe([
            ...await first((p) => p.search(RecipeQuery(maxMinutes: 30, limit: limit, category: p is TheMealDb ? null : 'main course'))),
            ...await catalog.search(RecipeQuery(maxMinutes: 30, limit: limit)),
          ]).where((r) => (r.minutes ?? 30) <= 30).take(limit).toList();
        case 'seasonal':
          final produce = kSeasonalProduce[month ?? DateTime.now().month] ?? const [];
          final hits = <RecipeData>[];
          for (final item in produce.take(3)) {
            hits.addAll(await first((p) => p.search(RecipeQuery(includeIngredients: [item], limit: 4))));
            hits.addAll(await catalog.search(RecipeQuery(includeIngredients: [item], limit: 3)));
          }
          return _dedupe(hits).take(limit).toList();
        case 'cuisine':
          return _dedupe([
            ...await first((p) => p.search(RecipeQuery(cuisine: arg, limit: limit))),
            ...await catalog.search(RecipeQuery(cuisine: arg, limit: limit)),
          ]).take(limit).toList();
        case 'toddler':
          final kid = await catalog.search(RecipeQuery(limit: limit));
          return kid.where((r) => !r.ingredients.any((i) => i.key.contains('chili') || i.key.contains('cayenne'))).take(limit).toList();
        default:
          return catalog.random(limit);
      }
    });
  }

  Future<List<String>> cuisines() async {
    final providers = await integrations.recipeProviders();
    for (final p in providers) {
      final c = await _safe(p.id, p.cuisines);
      if (c.isNotEmpty) return c;
    }
    return const [];
  }

  Future<RecipeData> importUrl(String url) async {
    final r = await RecipeImporter(fetcher).importUrl(Uri.parse(url));
    await _remember([r]);
    return r;
  }

  /// "Pairs with your plan" (FR-RCP-09): candidates come from the catalog,
  /// everything seen recently, and provider ingredient searches for the
  /// plan's most perishable ingredients.
  Future<List<ReuseScore>> recommend(List<RecipeData> planned, {Set<String> excluded = const {}, Map<String, double> ratings = const {}, int limit = 12}) async {
    final plan = PlanContext.fromRecipes(planned);
    final candidates = <String, RecipeData>{for (final r in recipeCatalog) r.id: r, ...await _remembered()};
    if (!plan.isEmpty) {
      // Unmetered sources only: three ingredient searches would spend a
      // tenth of Racion's hour, or a day of RecipeAPI.io and Tasty.
      final providers = (await integrations.recipeProviders()).where((p) => p is! CatalogRecipes && p is! Racion && p is! RecipeApiIo && p is! TastyApi);
      for (final key in plan.perishablesFirst.take(3)) {
        for (final p in providers) {
          final found = await _safe(p.id, () => p.search(RecipeQuery(includeIngredients: [key], limit: 6)));
          await _remember(found);
          for (final r in found) {
            candidates[r.id] = r;
          }
        }
      }
    }
    final plannedTitles = {for (final r in planned) r.title.toLowerCase()};
    final ranked = rankForPlan(
      candidates.values.where((r) => !plannedTitles.contains(r.title.toLowerCase())),
      plan,
      excluded: excluded,
      ratings: ratings,
    );
    return ranked.take(limit).toList();
  }

  Future<List<RecipeData>> _cached(String key, Future<List<RecipeData>> Function() load) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final hit = _cache[key];
    // Spoonacular allows an hour at most.
    final ttl = hit != null && hit.$2.any((r) => r.source == 'spoonacular') ? const Duration(hours: 1) : _ttl;
    if (hit != null && now - hit.$1 < ttl.inMilliseconds) return hit.$2;
    final value = await load();
    await _remember(value);
    if (_cache.length >= _maxCache) _cache.remove(_cache.keys.first);
    _cache[key] = (now, value);
    return value;
  }

  Future<List<T>> _safe<T>(String provider, Future<List<T>> Function() run) async {
    try {
      return await run();
    } on QuotaExceededException {
      return const [];
    } on Object catch (e) {
      _log.warning('Recipe provider $provider failed: $e');
      return const [];
    }
  }

  static List<RecipeData> _dedupe(Iterable<RecipeData> items) {
    final seen = <String>{};
    return [
      for (final r in items)
        if (seen.add(r.title.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), ''))) r,
    ];
  }
}
