import 'package:dearth_core/dearth_core.dart';

import '../calendar/event_ops.dart' show MakeOp;

/// The local id of [r] once it's copied into the family box (SPEC FR-RCP-02).
/// Provider recipes get a stable id from their source, so planning the same
/// recipe on two offline devices converges on one row (and matches the demo
/// seed); hand-entered recipes keep theirs.
String localRecipeId(RecipeData r) {
  final sid = r.sourceId;
  return r.source == 'box' || sid == null || sid.isEmpty ? r.id : stableId('recipe', [r.source, sid]);
}

/// Ops that copy [r] into the recipes table, unless [existing] (its local
/// row) is already there: a family's edits and notes win over the provider.
List<Op> copyRecipeOps(MakeOp op, RecipeData r, {Recipe? existing, bool saved = false, int? nowMs}) => existing != null
    ? [if (saved && !existing.saved) op('recipes', existing.id, const {'saved': true})]
    : [op('recipes', localRecipeId(r), {...r.toFields(saved: saved), 'created_ms': nowMs, 'deleted': false})];

/// Plans [r] on [date]/[slot] (SPEC FR-MEAL-01); planning copies the recipe
/// locally so the plan survives the provider disappearing.
List<Op> planRecipeOps(
  MakeOp op, {
  required RecipeData recipe,
  Recipe? existing,
  required LocalDate date,
  required String slot,
  required int servings,
  String? entryId,
  String sortKey = 'm',
  int? nowMs,
}) =>
    [
      ...copyRecipeOps(op, recipe, existing: existing, nowMs: nowMs),
      op('meal_entries', entryId ?? newId(), {
        'date': date.iso,
        'slot': slot,
        'recipe_id': existing?.id ?? localRecipeId(recipe),
        'title': null,
        'servings': servings,
        'sort_key': sortKey,
        'deleted': false,
      }),
    ];

/// A free-text entry ("Leftovers", "Eat out").
List<Op> planTextOps(MakeOp op, {required String title, required LocalDate date, required String slot, String? entryId, String sortKey = 'm'}) => [
      op('meal_entries', entryId ?? newId(), {
        'date': date.iso,
        'slot': slot,
        'recipe_id': null,
        'title': title.trim(),
        'servings': null,
        'sort_key': sortKey,
        'deleted': false,
      }),
    ];

List<Op> moveMealOps(MakeOp op, String entryId, {required LocalDate date, required String slot}) => [
      op('meal_entries', entryId, {'date': date.iso, 'slot': slot}),
    ];

List<Op> mealServingsOps(MakeOp op, String entryId, int servings) => [op('meal_entries', entryId, {'servings': servings})];

List<Op> removeMealOps(MakeOp op, String entryId) => [op('meal_entries', entryId, const {}, kind: OpKind.delete)];

/// Saves [r] to the family box, or takes it out (the row stays: plans may
/// still point at it).
List<Op> saveRecipeOps(MakeOp op, RecipeData r, {Recipe? existing, required bool saved, int? nowMs}) => existing == null
    ? copyRecipeOps(op, r, saved: saved, nowMs: nowMs)
    : [op('recipes', existing.id, {'saved': saved})];

/// The family's rating faces (SPEC FR-RCP-06), best first. Scores are
/// centered on "it's OK" so they add straight into plan scoring.
const List<(int score, String emoji, String label)> kRatingFaces = [
  (2, '😋', 'Love it'),
  (1, '🙂', 'Like it'),
  (0, '😐', 'It’s OK'),
  (-2, '🙅', 'No thanks'),
];

/// One row per person per recipe, so re-rating overwrites on every device.
String ratingId(String recipeId, String profileId) => stableId('rating', [recipeId, profileId]);

List<Op> rateRecipeOps(MakeOp op, {required String recipeId, required String profileId, required int? score, required int nowMs}) {
  final id = ratingId(recipeId, profileId);
  return score == null
      ? [op('recipe_ratings', id, const {}, kind: OpKind.delete)]
      : [op('recipe_ratings', id, {'recipe_id': recipeId, 'profile_id': profileId, 'score': score, 'at_ms': nowMs, 'deleted': false})];
}

/// What [addToListOps] did.
class AddToListResult {
  const AddToListResult(this.ops, {required this.added, required this.alreadyListed, required this.staples});
  final List<Op> ops;
  final int added;

  /// Ingredients already open on the list (by normalized name).
  final int alreadyListed;

  /// Pantry staples left off (SPEC FR-SHOP-03: "check you have").
  final int staples;
}

/// Shopping-list items for [ingredients] (SPEC FR-RCP-06 "Add ingredients to
/// list"). Skips staples and anything already open on the list, and sorts
/// new items after [lastSortKey] in ingredient order.
AddToListResult addToListOps(
  MakeOp op, {
  required String listId,
  required List<Ingredient> ingredients,
  required List<ListItem> existing,
  String? lastSortKey,
  bool metric = false,
}) {
  final open = {for (final i in existing) if (!i.checked && !i.deleted) _itemKey(i.itemText)};
  final ops = <Op>[];
  var listed = 0, staples = 0;
  var sortKey = lastSortKey;
  for (final i in ingredients) {
    if (i.optional) continue;
    if (i.isStaple) {
      staples++;
      continue;
    }
    final key = i.key.isEmpty ? i.name.toLowerCase() : i.key;
    if (!open.add(key)) {
      listed++;
      continue;
    }
    sortKey = sortKeyAfter(sortKey);
    final name = i.name.isEmpty ? i.raw : i.name;
    ops.add(op('list_items', newId(), {
      'list_id': listId,
      'text': name.isEmpty ? name : name[0].toUpperCase() + name.substring(1),
      'qty': i.qty,
      'unit': i.unit.isEmpty ? null : i.unit,
      'note': i.qty == null ? null : formatMeasure(i.qty, i.unit, max: i.qtyMax),
      'category': i.aisle.name,
      'sort_key': sortKey,
      'checked': false,
      'deleted': false,
    }));
  }
  return AddToListResult(ops, added: ops.length, alreadyListed: listed, staples: staples);
}

/// List items for a period's consolidated shopping lines (SPEC FR-SHOP-01/02):
/// one item per line with its total and where it's used ("for Tacos (Tue)").
/// Staples and items already open on the list are skipped, like
/// [addToListOps].
AddToListResult addLinesToListOps(
  MakeOp op, {
  required String listId,
  required List<ShoppingLine> lines,
  required List<ListItem> existing,
  String? lastSortKey,
  bool metric = false,
}) {
  final open = {for (final i in existing) if (!i.checked && !i.deleted) _itemKey(i.itemText)};
  final ops = <Op>[];
  var listed = 0, staples = 0;
  var sortKey = lastSortKey;
  for (final l in lines) {
    if (l.staple) {
      staples++;
      continue;
    }
    if (!open.add(l.key.startsWith('raw:') ? _itemKey(l.name) : l.key)) {
      listed++;
      continue;
    }
    sortKey = sortKeyAfter(sortKey);
    final amount = l.amounts(metric: metric);
    final sources = l.recipes.toList()..sort();
    ops.add(op('list_items', newId(), {
      'list_id': listId,
      'text': l.name,
      'note': [if (amount.isNotEmpty) amount, if (sources.isNotEmpty) 'for ${sources.join(', ')}'].join(' · '),
      'category': l.aisle.name,
      'sort_key': sortKey,
      'checked': false,
      'deleted': false,
    }));
  }
  return AddToListResult(ops, added: ops.length, alreadyListed: listed, staples: staples);
}

String _itemKey(String text) {
  final parsed = parseIngredientLine(text);
  return parsed.key.isEmpty ? text.trim().toLowerCase() : parsed.key;
}
