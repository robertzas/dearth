import 'package:meta/meta.dart';

import '../util/ids.dart';
import 'ingredients.dart';
import 'recipe_model.dart';
import 'units.dart';

/// One amount within a shopping line (incompatible units stay separate).
@immutable
class ShoppingPart {
  const ShoppingPart({required this.qty, required this.unit, required this.recipes});
  final double? qty;
  final String unit;
  final List<String> recipes;
}

/// A consolidated shopping-list line (SPEC FR-SHOP-01/02).
@immutable
class ShoppingLine {
  const ShoppingLine({
    required this.key,
    required this.name,
    required this.aisle,
    required this.parts,
    required this.staple,
    required this.perishDays,
  });

  /// Normalized ingredient key (or raw text for low-confidence lines).
  final String key;
  final String name;
  final Aisle aisle;
  final List<ShoppingPart> parts;
  final bool staple;
  final int perishDays;

  /// Stable id for check state (`shopping_states`), scoped to a period.
  String stateId(String periodKey) => stableId('shopping', [periodKey, key]);

  Set<String> get recipes => {for (final p in parts) ...p.recipes};

  /// "2 lb · 1 bunch" (or "" when no amounts are known).
  String amounts({bool metric = false}) => parts
      .where((p) => p.qty != null || p.unit.isNotEmpty)
      .map((p) {
        if (p.qty == null) return p.unit;
        final fam = unitFamily(p.unit);
        if (fam == UnitFamily.volume || fam == UnitFamily.weight) {
          final (a, u) = toSystem(p.qty!, p.unit, metric: metric);
          return formatMeasure(a, u);
        }
        return formatMeasure(p.qty, p.unit);
      })
      .join(' · ');

  /// Fingerprint of the quantities; a change un-checks a checked line.
  String get qtySignature => parts.map((p) => '${p.qty?.toStringAsFixed(2)}${p.unit}').join('|');
}

/// One planned recipe contributing to the list.
@immutable
class PlannedRecipe {
  const PlannedRecipe(this.recipe, this.servings, {this.label});
  final RecipeData recipe;
  final int servings;

  /// Short label for "for: Tacos (Tue)".
  final String? label;
}

/// Builds the consolidated list for a planning period. Ingredients merge only
/// when normalized with high confidence AND units are convertible (SPEC
/// FR-SHOP-01); anything uncertain stays on its own line rather than being
/// silently combined.
List<ShoppingLine> consolidate(Iterable<PlannedRecipe> planned, {double minConfidence = 0.85}) {
  final byKey = <String, _Accumulator>{};
  for (final p in planned) {
    final label = p.label ?? p.recipe.title;
    for (final ing in p.recipe.scaledIngredients(p.servings)) {
      if (ing.optional) continue;
      final confident = ing.confidence >= minConfidence;
      final key = confident ? ing.key : 'raw:${ing.raw.toLowerCase()}';
      final acc = byKey.putIfAbsent(
        key,
        () => _Accumulator(key: key, name: confident ? _titleCase(ing.key) : ing.raw, aisle: ing.aisle, staple: ing.isStaple, perish: ing.perishDays),
      );
      acc.add(ing.qty, ing.unit, label);
    }
  }
  final lines = [for (final a in byKey.values) a.build()]
    ..sort((a, b) {
      final c = a.aisle.index.compareTo(b.aisle.index);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
  return lines;
}

class _Accumulator {
  _Accumulator({required this.key, required this.name, required this.aisle, required this.staple, required this.perish});
  final String key;
  final String name;
  final Aisle aisle;
  final bool staple;
  final int perish;
  final List<(double?, String, Set<String>)> parts = [];

  void add(double? qty, String unit, String recipe) {
    for (var i = 0; i < parts.length; i++) {
      final (pq, pu, recipes) = parts[i];
      if (qty == null && pq == null && pu == unit) {
        recipes.add(recipe);
        return;
      }
      if (qty != null && pq != null && canConvert(unit, pu)) {
        parts[i] = (pq + convert(qty, unit, pu), pu, recipes..add(recipe));
        return;
      }
    }
    parts.add((qty, unit, {recipe}));
  }

  ShoppingLine build() => ShoppingLine(
        key: key,
        name: name,
        aisle: aisle,
        staple: staple,
        perishDays: perish,
        parts: [
          for (final (q, u, r) in parts)
            if (q != null && unitFamily(u) != UnitFamily.other && unitFamily(u) != UnitFamily.count)
              () {
                final (fq, fu) = friendlyUnit(q, u);
                return ShoppingPart(qty: _round(fq), unit: fu, recipes: r.toList());
              }()
            else
              ShoppingPart(qty: q == null ? null : _round(q), unit: u, recipes: r.toList()),
        ],
      );
}

double _round(double v) => (v * 100).round() / 100;

String _titleCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
