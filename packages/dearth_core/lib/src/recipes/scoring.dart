import 'package:meta/meta.dart';

import 'ingredients.dart';
import 'recipe_model.dart';

/// Tunable weights for plan-aware recommendations (SPEC FR-RCP-09).
@immutable
class ReuseWeights {
  const ReuseWeights({
    this.perishableBonus = 1.5,
    this.semiPerishableBonus = 0.5,
    this.newIngredientPenalty = 0.6,
    this.repeatCuisinePenalty = 0.5,
    this.repeatProteinPenalty = 0.75,
    this.ratingWeight = 0.8,
    this.relevanceWeight = 1.0,
  });
  final double perishableBonus;
  final double semiPerishableBonus;
  final double newIngredientPenalty;
  final double repeatCuisinePenalty;
  final double repeatProteinPenalty;
  final double ratingWeight;
  final double relevanceWeight;
}

const _proteins = ['chicken', 'beef', 'pork', 'turkey', 'lamb', 'salmon', 'fish', 'shrimp', 'tofu', 'egg', 'bean', 'lentil', 'chickpea', 'sausage'];

String? mainProtein(RecipeData r) {
  for (final p in _proteins) {
    if (r.keys.any((k) => k.contains(p))) return p;
  }
  return null;
}

/// What the current plan already needs.
@immutable
class PlanContext {
  const PlanContext({this.keys = const {}, this.cuisines = const {}, this.proteins = const {}, this.recipeIds = const {}});

  factory PlanContext.fromRecipes(Iterable<RecipeData> recipes) {
    final keys = <String>{};
    final cuisines = <String, int>{};
    final proteins = <String, int>{};
    final ids = <String>{};
    for (final r in recipes) {
      ids.add(r.id);
      keys.addAll(r.keys);
      final c = r.cuisine?.toLowerCase();
      if (c != null && c.isNotEmpty) cuisines[c] = (cuisines[c] ?? 0) + 1;
      final p = mainProtein(r);
      if (p != null) proteins[p] = (proteins[p] ?? 0) + 1;
    }
    return PlanContext(keys: keys, cuisines: cuisines, proteins: proteins, recipeIds: ids);
  }

  final Set<String> keys;
  final Map<String, int> cuisines;
  final Map<String, int> proteins;
  final Set<String> recipeIds;

  bool get isEmpty => keys.isEmpty;

  /// Perishable keys first: the ones worth using up.
  List<String> get perishablesFirst => keys.toList()..sort((a, b) => perishabilityDays(a).compareTo(perishabilityDays(b)));
}

/// A scored candidate with its one-line explanation (FR-RCP-10).
@immutable
class ReuseScore {
  const ReuseScore({required this.recipe, required this.score, required this.matched, required this.added, required this.explanation});
  final RecipeData recipe;
  final double score;
  final List<String> matched;
  final List<String> added;
  final String explanation;
}

/// Scores [candidate] against [plan]. Returns null when a hard filter
/// (allergen or excluded ingredient) rejects it (SPEC FR-RCP-03).
ReuseScore? scoreForPlan(
  RecipeData candidate,
  PlanContext plan, {
  ReuseWeights weights = const ReuseWeights(),
  Set<String> excluded = const {},
  double relevance = 0,
  double? familyRating,
}) {
  final lowerKeys = candidate.ingredients.map((i) => '${i.key} ${i.name}'.toLowerCase()).toList();
  for (final ex in excluded) {
    final e = ex.toLowerCase().trim();
    if (e.isNotEmpty && lowerKeys.any((k) => k.contains(e))) return null;
  }
  final relevant = candidate.keys;
  final matched = relevant.where(plan.keys.contains).toList()
    ..sort((a, b) => perishabilityDays(a).compareTo(perishabilityDays(b)));
  final added = relevant.where((k) => !plan.keys.contains(k)).toList()..sort();

  var score = 0.0;
  for (final k in matched) {
    final days = perishabilityDays(k);
    score += 1 + (days <= 7 ? weights.perishableBonus : (days <= 14 ? weights.semiPerishableBonus : 0));
  }
  score -= added.length * weights.newIngredientPenalty;
  final cuisine = candidate.cuisine?.toLowerCase();
  if (cuisine != null && (plan.cuisines[cuisine] ?? 0) >= 2) score -= weights.repeatCuisinePenalty;
  final protein = mainProtein(candidate);
  if (protein != null && (plan.proteins[protein] ?? 0) >= 2) score -= weights.repeatProteinPenalty;
  if (familyRating != null) score += familyRating * weights.ratingWeight;
  score += relevance * weights.relevanceWeight;
  if (plan.recipeIds.contains(candidate.id)) score -= 100; // already planned

  return ReuseScore(
    recipe: candidate,
    score: score,
    matched: matched,
    added: added,
    explanation: _explain(matched, added),
  );
}

String _explain(List<String> matched, List<String> added) {
  final adds = added.isEmpty ? 'nothing new to buy' : 'adds ${added.length} item${added.length == 1 ? '' : 's'}';
  if (matched.isEmpty) return 'Something new · $adds';
  final names = matched.take(3).toList();
  final list = names.length == 1
      ? names.first
      : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  final more = matched.length > 3 ? ' (+${matched.length - 3} more)' : '';
  return 'Uses your $list$more · $adds';
}

/// Ranks candidates for "Pairs with your plan" (best first), dropping
/// filtered ones.
List<ReuseScore> rankForPlan(
  Iterable<RecipeData> candidates,
  PlanContext plan, {
  ReuseWeights weights = const ReuseWeights(),
  Set<String> excluded = const {},
  Map<String, double> ratings = const {},
}) {
  final scored = <ReuseScore>[
    for (final c in candidates)
      ?scoreForPlan(c, plan, weights: weights, excluded: excluded, familyRating: ratings[c.id]),
  ]..sort((a, b) => b.score.compareTo(a.score));
  return scored;
}
