import 'package:meta/meta.dart';

/// Measurement units, quantity parsing and friendly formatting (SPEC
/// FR-RCP-06, FR-SHOP-01).

enum UnitFamily { volume, weight, count, other }

const Map<String, String> _aliases = {
  'tsp': 'tsp', 't': 'tsp', 'teaspoon': 'tsp', 'teaspoons': 'tsp', //
  'tbsp': 'tbsp', 'tbs': 'tbsp', 'tbl': 'tbsp', 'tablespoon': 'tbsp', 'tablespoons': 'tbsp', //
  'cup': 'cup', 'cups': 'cup', 'c': 'cup', //
  'ml': 'ml', 'milliliter': 'ml', 'milliliters': 'ml', 'millilitre': 'ml', 'millilitres': 'ml', //
  'l': 'l', 'liter': 'l', 'liters': 'l', 'litre': 'l', 'litres': 'l', //
  'fl oz': 'fl oz', 'fluid ounce': 'fl oz', 'fluid ounces': 'fl oz', //
  'oz': 'oz', 'ounce': 'oz', 'ounces': 'oz', //
  'lb': 'lb', 'lbs': 'lb', 'pound': 'lb', 'pounds': 'lb', //
  'g': 'g', 'gram': 'g', 'grams': 'g', 'gr': 'g', //
  'kg': 'kg', 'kilogram': 'kg', 'kilograms': 'kg', //
  'quart': 'quart', 'quarts': 'quart', 'qt': 'quart', //
  'pint': 'pint', 'pints': 'pint', 'pt': 'pint', //
  'gallon': 'gallon', 'gallons': 'gallon', 'gal': 'gallon', //
  'clove': 'clove', 'cloves': 'clove', 'pinch': 'pinch', 'pinches': 'pinch', //
  'dash': 'dash', 'dashes': 'dash', 'can': 'can', 'cans': 'can', 'tin': 'can', 'tins': 'can', //
  'package': 'package', 'packages': 'package', 'pkg': 'package', 'pack': 'package', 'packet': 'package', //
  'bag': 'bag', 'bags': 'bag', 'bunch': 'bunch', 'bunches': 'bunch', //
  'slice': 'slice', 'slices': 'slice', 'piece': 'piece', 'pieces': 'piece', //
  'sprig': 'sprig', 'sprigs': 'sprig', 'stalk': 'stalk', 'stalks': 'stalk', 'rib': 'stalk', 'ribs': 'stalk', //
  'head': 'head', 'heads': 'head', 'stick': 'stick', 'sticks': 'stick', //
  'jar': 'jar', 'jars': 'jar', 'bottle': 'bottle', 'bottles': 'bottle', //
  'box': 'box', 'boxes': 'box', 'sheet': 'sheet', 'sheets': 'sheet', //
  'handful': 'handful', 'handfuls': 'handful', 'drop': 'drop', 'drops': 'drop', //
  'scoop': 'scoop', 'scoops': 'scoop', 'large': 'large', 'medium': 'medium', 'small': 'small',
};

/// Base factor per unit within its family (volume → ml, weight → g).
const Map<String, double> _base = {
  'tsp': 4.92892, 'tbsp': 14.7868, 'cup': 236.588, 'fl oz': 29.5735, 'ml': 1, 'l': 1000, //
  'quart': 946.353, 'pint': 473.176, 'gallon': 3785.41, 'drop': 0.05, //
  'g': 1, 'kg': 1000, 'oz': 28.3495, 'lb': 453.592,
};

const Set<String> _volume = {'tsp', 'tbsp', 'cup', 'fl oz', 'ml', 'l', 'quart', 'pint', 'gallon', 'drop'};
const Set<String> _weight = {'g', 'kg', 'oz', 'lb'};

String normalizeUnit(String raw) {
  final k = raw.trim().toLowerCase().replaceAll(RegExp(r'\.$'), '');
  return _aliases[k] ?? k;
}

bool isKnownUnit(String raw) => _aliases.containsKey(raw.trim().toLowerCase().replaceAll(RegExp(r'\.$'), ''));

UnitFamily unitFamily(String unit) {
  if (unit.isEmpty) return UnitFamily.count;
  if (_volume.contains(unit)) return UnitFamily.volume;
  if (_weight.contains(unit)) return UnitFamily.weight;
  return UnitFamily.other;
}

const Map<String, double> _unicodeFractions = {
  '½': .5, '⅓': 1 / 3, '⅔': 2 / 3, '¼': .25, '¾': .75, '⅕': .2, '⅖': .4, '⅗': .6, '⅘': .8, //
  '⅙': 1 / 6, '⅚': 5 / 6, '⅛': .125, '⅜': .375, '⅝': .625, '⅞': .875,
};

/// Replaces unicode vulgar fractions with ASCII (`1½` → `1 1/2`).
String asciiFractions(String s) {
  var out = s;
  _unicodeFractions.forEach((glyph, value) {
    final ascii = switch (glyph) {
      '½' => '1/2', '⅓' => '1/3', '⅔' => '2/3', '¼' => '1/4', '¾' => '3/4', '⅛' => '1/8', //
      '⅜' => '3/8', '⅝' => '5/8', '⅞' => '7/8', '⅕' => '1/5', '⅖' => '2/5', '⅗' => '3/5', //
      '⅘' => '4/5', '⅙' => '1/6', '⅚' => '5/6', _ => '$value',
    };
    out = out.replaceAllMapped(RegExp('(\\d)$glyph'), (m) => '${m[1]} $ascii').replaceAll(glyph, ascii);
  });
  return out.replaceAll('⁄', '/');
}

/// A parsed quantity; ranges ("2–3") keep both ends.
@immutable
class Quantity {
  const Quantity(this.value, [this.max]);
  final double value;
  final double? max;

  Quantity operator *(double f) => Quantity(value * f, max == null ? null : max! * f);
}

/// Parses "1 1/2", "1/2", "2.5", "2-3", "1½" → [Quantity] (null if absent).
Quantity? parseQuantity(String raw) {
  final s = asciiFractions(raw.trim());
  if (s.isEmpty) return null;
  double? one(String t) {
    final mixed = RegExp(r'^(\d+)\s+(\d+)/(\d+)$').firstMatch(t);
    if (mixed != null) return int.parse(mixed[1]!) + int.parse(mixed[2]!) / int.parse(mixed[3]!);
    final frac = RegExp(r'^(\d+)/(\d+)$').firstMatch(t);
    if (frac != null && int.parse(frac[2]!) != 0) return int.parse(frac[1]!) / int.parse(frac[2]!);
    return double.tryParse(t);
  }

  final range = RegExp(r'^(.+?)\s*(?:-|–|—|to)\s*(.+)$').firstMatch(s);
  if (range != null) {
    final a = one(range[1]!.trim());
    final b = one(range[2]!.trim());
    if (a != null && b != null) return Quantity(a, b > a ? b : null);
  }
  final v = one(s);
  return v == null ? null : Quantity(v);
}

/// Formats a number with friendly fractions: 1.333 → "1⅓", 0.5 → "½",
/// 2.0 → "2", 1.1 → "1.1".
String formatAmount(double v) {
  if (v <= 0) return '0';
  final whole = v.floor();
  final frac = v - whole;
  const glyphs = [(1 / 8, '⅛'), (1 / 4, '¼'), (1 / 3, '⅓'), (3 / 8, '⅜'), (1 / 2, '½'), (5 / 8, '⅝'), (2 / 3, '⅔'), (3 / 4, '¾'), (7 / 8, '⅞')];
  if (frac < 0.04) return '$whole';
  if (frac > 0.96) return '${whole + 1}';
  for (final (value, glyph) in glyphs) {
    // Eighths need a tighter match so 1.1 doesn't read as 1⅛.
    final tolerance = const {'⅛', '⅜', '⅝', '⅞'}.contains(glyph) ? 0.012 : 0.02;
    if ((frac - value).abs() < tolerance) return whole == 0 ? glyph : '$whole$glyph';
  }
  final rounded = v >= 10 ? v.round().toString() : v.toStringAsFixed(1);
  return rounded.endsWith('.0') ? rounded.substring(0, rounded.length - 2) : rounded;
}

bool canConvert(String from, String to) =>
    from == to || (_base.containsKey(from) && _base.containsKey(to) && unitFamily(from) == unitFamily(to));

double convert(double v, String from, String to) => from == to ? v : v * _base[from]! / _base[to]!;

/// Picks a friendly unit for a volume/weight amount in the same measuring
/// system as [unit] (US kitchen: tsp → tbsp → cup; metric: ml → l; g → kg).
(double, String) friendlyUnit(double amount, String unit) {
  if (!_base.containsKey(unit)) return (amount, unit);
  final family = unitFamily(unit);
  final base = amount * _base[unit]!;
  if (family == UnitFamily.volume) {
    if (const {'ml', 'l'}.contains(unit)) return base >= 1000 ? (base / 1000, 'l') : (base, 'ml');
    if (base >= _base['cup']! / 4 - 0.01) return (base / _base['cup']!, 'cup');
    if (base >= _base['tbsp']! - 0.01) return (base / _base['tbsp']!, 'tbsp');
    return (base / _base['tsp']!, 'tsp');
  }
  if (const {'g', 'kg'}.contains(unit)) return base >= 1000 ? (base / 1000, 'kg') : (base, 'g');
  return base >= _base['lb']! ? (base / _base['lb']!, 'lb') : (base / _base['oz']!, 'oz');
}

/// Converts between US customary and metric for display (FR-RCP-06).
(double, String) toSystem(double amount, String unit, {required bool metric}) {
  final family = unitFamily(unit);
  if (!_base.containsKey(unit) || (family != UnitFamily.volume && family != UnitFamily.weight)) {
    return (amount, unit);
  }
  final isMetric = const {'ml', 'l', 'g', 'kg'}.contains(unit);
  if (isMetric == metric) return friendlyUnit(amount, unit);
  if (metric) {
    return friendlyUnit(convert(amount, unit, family == UnitFamily.volume ? 'ml' : 'g'), family == UnitFamily.volume ? 'ml' : 'g');
  }
  return friendlyUnit(convert(amount, unit, family == UnitFamily.volume ? 'tsp' : 'oz'), family == UnitFamily.volume ? 'tsp' : 'oz');
}

/// "1⅓ cups", "2 cloves", "3" — pluralizes common units.
String formatMeasure(double? amount, String unit, {double? max}) {
  if (amount == null) return unit;
  final a = formatAmount(amount);
  final range = max != null ? '$a–${formatAmount(max)}' : a;
  if (unit.isEmpty) return range;
  final plural = (max ?? amount) > 1.0001 && !const {'tsp', 'tbsp', 'ml', 'l', 'g', 'kg', 'oz', 'lb', 'fl oz'}.contains(unit);
  final shown = plural
      ? switch (unit) {
          'bunch' => 'bunches',
          'box' => 'boxes',
          'pinch' => 'pinches',
          'dash' => 'dashes',
          _ => '${unit}s',
        }
      : unit;
  return '$range $shown';
}
