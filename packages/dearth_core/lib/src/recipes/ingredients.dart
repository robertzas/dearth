import 'package:meta/meta.dart';

import 'units.dart';

/// Grocery aisles, in a default store-walk order (FR-SHOP-04).
enum Aisle {
  produce('Produce', '🥬'),
  bakery('Bakery', '🥖'),
  meatSeafood('Meat & seafood', '🥩'),
  dairyEggs('Dairy & eggs', '🥚'),
  deli('Deli', '🧀'),
  frozen('Frozen', '🧊'),
  pantry('Pantry', '🥫'),
  grains('Pasta, rice & grains', '🍝'),
  spices('Spices & baking', '🧂'),
  snacks('Snacks', '🍿'),
  beverages('Beverages', '🧃'),
  household('Household', '🧻'),
  other('Other', '🛒');

  const Aisle(this.label, this.emoji);
  final String label;
  final String emoji;

  static Aisle parse(String? s) => values.firstWhere((a) => a.name == s, orElse: () => other);
}

/// A structured ingredient line (SPEC FR-RCP-02).
@immutable
class Ingredient {
  const Ingredient({
    required this.raw,
    required this.name,
    required this.key,
    this.qty,
    this.qtyMax,
    this.unit = '',
    this.prep,
    this.optional = false,
    this.group,
    this.aisle = Aisle.other,
    this.confidence = 0.7,
  });

  factory Ingredient.fromJson(Map<String, Object?> j) => Ingredient(
        raw: j['raw'] as String? ?? '',
        name: j['name'] as String? ?? '',
        key: j['key'] as String? ?? '',
        qty: (j['qty'] as num?)?.toDouble(),
        qtyMax: (j['qtyMax'] as num?)?.toDouble(),
        unit: j['unit'] as String? ?? '',
        prep: j['prep'] as String?,
        optional: j['optional'] as bool? ?? false,
        group: j['group'] as String?,
        aisle: Aisle.parse(j['aisle'] as String?),
        confidence: (j['conf'] as num?)?.toDouble() ?? 0.7,
      );

  /// Original line as written by the source.
  final String raw;

  /// Display name ("green onions").
  final String name;

  /// Normalized key used for matching and consolidation ("green onion").
  final String key;
  final double? qty;
  final double? qtyMax;
  final String unit;
  final String? prep;
  final bool optional;
  final String? group;
  final Aisle aisle;

  /// 0..1; ≥ 0.85 is safe to merge with other lines (FR-SHOP-01).
  final double confidence;

  bool get isStaple => kPantryStaples.contains(key);
  int get perishDays => perishabilityDays(key);

  Ingredient scaled(double factor) => Ingredient(
        raw: raw,
        name: name,
        key: key,
        qty: qty == null ? null : qty! * factor,
        qtyMax: qtyMax == null ? null : qtyMax! * factor,
        unit: unit,
        prep: prep,
        optional: optional,
        group: group,
        aisle: aisle,
        confidence: confidence,
      );

  /// "1⅓ cups flour, sifted" for display.
  String describe({bool metric = false}) {
    if (qty == null) return '$name$_prepSuffix';
    var amount = qty!;
    var maxAmount = qtyMax;
    var u = unit;
    if (unitFamily(unit) == UnitFamily.volume || unitFamily(unit) == UnitFamily.weight) {
      final (a, unit2) = toSystem(amount, unit, metric: metric);
      if (maxAmount != null) maxAmount = maxAmount * (a / amount);
      amount = a;
      u = unit2;
    }
    final measure = formatMeasure(amount, u, max: maxAmount);
    return '$measure $name$_prepSuffix';
  }

  /// ", minced", unless the name already says it ("grated ginger").
  String get _prepSuffix {
    final p = prep;
    if (p == null || p.isEmpty || name.toLowerCase().contains(p.toLowerCase())) return '';
    return ', $p';
  }

  Map<String, Object?> toJson() => {
        'raw': raw,
        'name': name,
        'key': key,
        if (qty != null) 'qty': qty,
        if (qtyMax != null) 'qtyMax': qtyMax,
        if (unit.isNotEmpty) 'unit': unit,
        if (prep != null) 'prep': prep,
        if (optional) 'optional': true,
        if (group != null) 'group': group,
        'aisle': aisle.name,
        'conf': confidence,
      };
}

// ───────────────────────────── Normalization ───────────────────────────────

const Map<String, String> _synonyms = {
  'scallion': 'green onion', 'spring onion': 'green onion', 'green onions': 'green onion', //
  'boneless skinless chicken breast': 'chicken breast', 'chicken breast half': 'chicken breast', //
  'boneless skinless chicken thigh': 'chicken thigh', //
  'garlic clove': 'garlic', 'clove garlic': 'garlic', 'clove of garlic': 'garlic', //
  'roma tomato': 'tomato', 'plum tomato': 'tomato', 'vine tomato': 'tomato', //
  'confectioners sugar': 'powdered sugar', "confectioners' sugar": 'powdered sugar', 'icing sugar': 'powdered sugar', //
  'coriander leaf': 'cilantro', 'fresh coriander': 'cilantro', //
  'beef mince': 'ground beef', 'minced beef': 'ground beef', 'hamburger': 'ground beef', //
  'double cream': 'heavy cream', 'heavy whipping cream': 'heavy cream', 'whipping cream': 'heavy cream', //
  'courgette': 'zucchini', 'aubergine': 'eggplant', 'garbanzo bean': 'chickpea', 'garbanzo': 'chickpea', //
  'kosher salt': 'salt', 'sea salt': 'salt', 'table salt': 'salt', 'fine salt': 'salt', //
  'extra virgin olive oil': 'olive oil', 'extra-virgin olive oil': 'olive oil', 'evoo': 'olive oil', //
  'canola oil': 'vegetable oil', 'neutral oil': 'vegetable oil', //
  'all-purpose flour': 'flour', 'all purpose flour': 'flour', 'plain flour': 'flour', 'ap flour': 'flour', //
  'ground black pepper': 'black pepper', 'freshly ground black pepper': 'black pepper', 'pepper': 'black pepper', //
  'soya sauce': 'soy sauce', 'tamari': 'soy sauce', 'yoghurt': 'yogurt', 'greek yoghurt': 'greek yogurt', //
  'spaghettini': 'spaghetti', 'caster sugar': 'sugar', 'granulated sugar': 'sugar', 'white sugar': 'sugar', //
  'bicarbonate of soda': 'baking soda', 'cornflour': 'cornstarch', 'corn starch': 'cornstarch', //
  'chilli': 'chili pepper', 'chile': 'chili pepper', 'red chilli': 'chili pepper', //
  'capsicum': 'bell pepper', 'red pepper': 'red bell pepper', 'green pepper': 'green bell pepper', //
  'prawn': 'shrimp', 'rocket': 'arugula', 'mince': 'ground beef', 'single cream': 'light cream', //
  'egg yolk': 'egg', 'egg white': 'egg', 'large egg': 'egg', //
  'unsalted butter': 'butter', 'salted butter': 'butter', //
  'chicken stock': 'chicken broth', 'beef stock': 'beef broth', 'vegetable stock': 'vegetable broth', //
  'parmigiano-reggiano': 'parmesan', 'parmigiano reggiano': 'parmesan', 'parmesan cheese': 'parmesan', //
  'lemon juice': 'lemon', 'lime juice': 'lime', 'lemon zest': 'lemon', 'lime zest': 'lime',
};

const List<String> _qualifiers = [
  'boneless', 'skinless', 'fresh', 'freshly', 'frozen', 'organic', 'large', 'medium', 'small', 'ripe', //
  'raw', 'cooked', 'uncooked', 'dried', 'dry', 'whole', 'sweetened', 'unsweetened', 'low-fat', 'low fat', //
  'fat-free', 'reduced-fat', 'free-range', 'extra lean', 'lean', 'thinly', 'thickly', 'finely', 'roughly', //
  'coarsely', 'good quality', 'good-quality', 'store-bought', 'homemade', 'plain', 'baby', 'jumbo', 'heaping', 'level',
];

const List<String> _prepWords = [
  'minced', 'diced', 'chopped', 'sliced', 'shredded', 'grated', 'peeled', 'crushed', 'melted', 'softened', //
  'drained', 'rinsed', 'halved', 'quartered', 'julienned', 'cubed', 'beaten', 'whisked', 'sifted', 'toasted', //
  'roasted', 'deveined', 'pitted', 'seeded', 'cored', 'trimmed', 'torn', 'crumbled', 'zested', 'juiced', //
  'cut into chunks', 'cut into pieces', 'cut into wedges', 'at room temperature', 'room temperature', //
  'for serving', 'for garnish', 'to taste', 'divided', 'plus more', 'or more', 'as needed', 'packed', 'thawed',
];

const Set<String> _noSingular = {
  'rice', 'couscous', 'hummus', 'corn', 'asparagus', 'spinach', 'lettuce', 'pasta', 'quinoa', 'oats', //
  'flour', 'sugar', 'salt', 'cheese', 'milk', 'bread', 'butter', 'yogurt', 'tofu', 'miso', 'molasses', //
  'swiss', 'brussels', 'grits', 'greens', 'chives', 'peas', 'lentils',
};

String _singular(String w) {
  if (_noSingular.contains(w) || w.length <= 3) return w;
  if (w.endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
  if (w.endsWith('oes')) return w.substring(0, w.length - 2);
  if (RegExp(r'(sh|ch|ss|x|z)es$').hasMatch(w)) return w.substring(0, w.length - 2);
  if (w.endsWith('s') && !w.endsWith('ss') && !w.endsWith('us')) return w.substring(0, w.length - 1);
  return w;
}

/// Result of name normalization.
@immutable
class NormalizedName {
  const NormalizedName(this.key, this.prep, this.confidence);
  final String key;
  final String prep;
  final double confidence;
}

/// Normalizes an ingredient name to a canonical matching key. Confidence
/// ≥ 0.85 means "safe to consolidate" (SPEC FR-SHOP-01).
NormalizedName normalizeIngredientName(String name) {
  var s = ' ${name.toLowerCase().trim()} ';
  final preps = <String>[];
  s = s.replaceAllMapped(RegExp(r'\(([^)]*)\)'), (m) {
    preps.add(m[1]!.trim());
    return ' ';
  });
  final comma = s.indexOf(',');
  if (comma >= 0) {
    preps.add(s.substring(comma + 1).trim());
    s = s.substring(0, comma);
  }
  for (final p in _prepWords) {
    final re = RegExp('\\b${RegExp.escape(p)}\\b');
    if (re.hasMatch(s)) {
      preps.add(p);
      s = s.replaceAll(re, ' ');
    }
  }
  for (final q in _qualifiers) {
    s = s.replaceAll(RegExp('\\b${RegExp.escape(q)}\\b'), ' ');
  }
  s = s.replaceAll(RegExp(r'\b(of|the|a|an)\b'), ' ').replaceAll(RegExp(r"[^a-z' -]"), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  final prep = preps.where((p) => p.isNotEmpty).join(', ');
  if (s.isEmpty) return NormalizedName(name.toLowerCase().trim(), prep, 0.3);

  final direct = _synonyms[s];
  if (direct != null) return NormalizedName(direct, prep, 0.99);
  final words = s.split(' ');
  final singular = words.map(_singular).join(' ');
  final syn = _synonyms[singular];
  if (syn != null) return NormalizedName(syn, prep, 0.95);
  var confidence = singular == s ? 0.9 : 0.88;
  if (words.length > 2) confidence = 0.6; // unusual multi-word names stay separate
  return NormalizedName(singular, prep, confidence);
}

/// Parses an ingredient line: "2 1/2 cups all-purpose flour, sifted",
/// "1 (14 oz) can diced tomatoes", "3-4 cloves garlic, minced", "Salt to taste".
Ingredient parseIngredientLine(String line, {String? group}) {
  final raw = line.trim();
  var s = asciiFractions(raw);
  final optional = RegExp(r'\boptional\b', caseSensitive: false).hasMatch(s);
  s = s.replaceAll(RegExp(r'\(?\boptional\b\)?', caseSensitive: false), ' ').trim();

  Quantity? q;
  final qtyMatch = RegExp(r'^((?:\d+\s+\d+/\d+)|(?:\d+/\d+)|(?:\d+(?:\.\d+)?))(?:\s*(?:-|–|to)\s*((?:\d+\s+\d+/\d+)|(?:\d+/\d+)|(?:\d+(?:\.\d+)?)))?\s*')
      .firstMatch(s);
  if (qtyMatch != null) {
    final a = parseQuantity(qtyMatch[1]!);
    final b = qtyMatch[2] == null ? null : parseQuantity(qtyMatch[2]!);
    if (a != null) q = Quantity(a.value, b?.value);
    s = s.substring(qtyMatch.end);
  }
  // "1 (14 oz) can tomatoes" → package count with size note.
  String? sizeNote;
  final paren = RegExp(r'^\(([^)]*)\)\s*').firstMatch(s);
  if (paren != null) {
    sizeNote = paren[1];
    s = s.substring(paren.end);
  }
  var unit = '';
  final unitMatch = RegExp(r'^(fl\.?\s?oz|fluid ounces?|[a-zA-Z]+)\.?\s+').firstMatch(s);
  if (q != null && unitMatch != null && isKnownUnit(unitMatch[1]!.replaceAll(RegExp(r'\s'), ' ')) && !const {'large', 'medium', 'small'}.contains(unitMatch[1]!.toLowerCase())) {
    unit = normalizeUnit(unitMatch[1]!.replaceAll(RegExp(r'\.\s?'), ' ').trim());
    s = s.substring(unitMatch.end);
  }
  s = s.replaceFirst(RegExp(r'^of\s+', caseSensitive: false), '');
  final displayName = s.split(',').first.replaceAll(RegExp(r'\s+'), ' ').trim();
  final norm = normalizeIngredientName(s);
  final prepParts = [?sizeNote, if (norm.prep.isNotEmpty) norm.prep];
  return Ingredient(
    raw: raw,
    name: displayName.isEmpty ? raw : displayName,
    key: norm.key,
    qty: q?.value,
    qtyMax: q?.max,
    unit: unit,
    prep: prepParts.isEmpty ? null : prepParts.join(', '),
    optional: optional,
    group: group,
    aisle: aisleFor(norm.key),
    confidence: q == null && unit.isEmpty ? norm.confidence - 0.05 : norm.confidence,
  );
}

/// Builds an ingredient from a provider's separate measure + name fields
/// (TheMealDB: strMeasure + strIngredient).
Ingredient ingredientFromMeasure(String measure, String name) {
  final line = '${measure.trim()} ${name.trim()}'.trim();
  final parsed = parseIngredientLine(line);
  if (parsed.qty != null || parsed.unit.isNotEmpty) return parsed;
  final norm = normalizeIngredientName(name);
  return Ingredient(
    raw: line,
    name: name.trim(),
    key: norm.key,
    prep: measure.trim().isEmpty ? null : measure.trim(),
    aisle: aisleFor(norm.key),
    confidence: norm.confidence,
  );
}

// ───────────────────────────── Knowledge base ──────────────────────────────

/// Pantry staples assumed on hand: excluded from reuse scoring and shown as
/// "check you have" on the shopping list (FR-SHOP-03).
const Set<String> kPantryStaples = {
  'water', 'salt', 'black pepper', 'sugar', 'flour', 'olive oil', 'vegetable oil', 'ice', //
  'baking soda', 'baking powder', 'cornstarch', 'vanilla extract', 'brown sugar',
};

const List<(Aisle, List<String>)> _aisleKeywords = [
  (Aisle.frozen, ['frozen', 'ice cream']),
  (Aisle.meatSeafood, [
    'chicken', 'beef', 'pork', 'lamb', 'turkey', 'bacon', 'sausage', 'ham', 'steak', 'salmon', 'tuna', //
    'cod', 'shrimp', 'crab', 'lobster', 'fish', 'tilapia', 'trout', 'anchov', 'sardine', 'duck', 'veal', //
    'chorizo', 'prosciutto', 'pancetta', 'mince', 'meatball', 'scallop', 'mussel', 'clam',
  ]),
  (Aisle.deli, ['salami', 'pepperoni', 'hummus', 'deli']),
  (Aisle.dairyEggs, [
    'milk', 'cheese', 'egg', 'yogurt', 'butter', 'cream', 'mozzarella', 'parmesan', 'cheddar', 'feta', //
    'ricotta', 'buttermilk', 'margarine', 'ghee', 'mascarpone', 'halloumi', 'kefir',
  ]),
  (Aisle.spices, [
    'salt', 'black pepper', 'cumin', 'paprika', 'oregano', 'cinnamon', 'nutmeg', 'turmeric', 'curry powder', //
    'chili powder', 'cayenne', 'clove', 'cardamom', 'allspice', 'bay leaf', 'garlic powder', 'onion powder', //
    'red pepper flake', 'seasoning', 'garam masala', 'saffron', 'vanilla', 'baking powder', 'baking soda', //
    'yeast', 'cocoa', 'chocolate chip', 'sprinkle', 'food coloring', 'dried', 'ground ginger', 'sugar',
  ]),
  (Aisle.produce, [
    'onion', 'garlic', 'tomato', 'potato', 'carrot', 'celery', 'bell pepper', 'chili pepper', 'jalapeno', //
    'broccoli', 'spinach', 'lettuce', 'cucumber', 'mushroom', 'zucchini', 'eggplant', 'corn', 'pea', 'cabbage', //
    'kale', 'avocado', 'lemon', 'lime', 'orange', 'apple', 'banana', 'berry', 'strawberr', 'blueberr', //
    'raspberr', 'grape', 'melon', 'pineapple', 'mango', 'peach', 'pear', 'plum', 'ginger', 'basil', //
    'parsley', 'cilantro', 'thyme', 'rosemary', 'dill', 'mint', 'chive', 'leek', 'shallot', 'squash', //
    'sweet potato', 'beet', 'radish', 'cauliflower', 'asparagus', 'arugula', 'fennel', 'bok choy', 'chard', //
    'sprout', 'herb', 'salad', 'green bean', 'okra', 'pumpkin', 'cherry', 'kiwi', 'watermelon',
  ]),
  (Aisle.bakery, ['bread', 'baguette', 'croissant', 'bun', 'roll', 'bagel', 'pita', 'naan', 'tortilla', 'brioche', 'sourdough', 'english muffin']),
  (Aisle.grains, [
    'rice', 'pasta', 'spaghetti', 'noodle', 'penne', 'fusilli', 'macaroni', 'linguine', 'fettuccine', //
    'lasagna', 'quinoa', 'couscous', 'barley', 'oat', 'cereal', 'breadcrumb', 'panko', 'polenta', 'gnocchi', //
    'ramen', 'udon', 'soba', 'orzo', 'farro', 'bulgur', 'flour', 'cornmeal',
  ]),
  (Aisle.beverages, ['juice', 'soda', 'coffee', 'tea', 'wine', 'beer', 'sparkling water']),
  (Aisle.snacks, ['chip', 'cracker', 'pretzel', 'popcorn', 'granola bar', 'cookie']),
  (Aisle.pantry, [
    'oil', 'vinegar', 'soy sauce', 'honey', 'syrup', 'peanut butter', 'jam', 'jelly', 'mayonnaise', 'mayo', //
    'mustard', 'ketchup', 'salsa', 'sauce', 'broth', 'stock', 'tomato paste', 'bean', 'lentil', 'chickpea', //
    'coconut milk', 'nut', 'almond', 'walnut', 'cashew', 'pecan', 'peanut', 'seed', 'raisin', 'olive', //
    'caper', 'pickle', 'tahini', 'miso', 'cornstarch', 'canned', 'tuna can', 'chocolate',
  ]),
  (Aisle.household, ['paper towel', 'foil', 'plastic wrap', 'parchment', 'napkin', 'detergent', 'soap', 'trash bag']),
];

/// Aisle for a normalized ingredient key (first keyword hit wins).
Aisle aisleFor(String key) {
  final k = ' $key ';
  for (final (aisle, words) in _aisleKeywords) {
    for (final w in words) {
      if (k.contains(w)) return aisle;
    }
  }
  return Aisle.other;
}

const Map<String, int> _perish = {
  'cilantro': 5, 'parsley': 6, 'basil': 4, 'mint': 5, 'dill': 5, 'green onion': 6, 'spinach': 5, //
  'lettuce': 6, 'arugula': 4, 'avocado': 4, 'berry': 4, 'strawberr': 4, 'raspberr': 3, 'blueberr': 7, //
  'mushroom': 6, 'zucchini': 7, 'cucumber': 7, 'tomato': 6, 'banana': 5, 'fish': 2, 'salmon': 2, 'shrimp': 2, //
  'ground beef': 2, 'chicken': 2, 'pork': 3, 'beef': 3, 'turkey': 2, 'buttermilk': 10, 'heavy cream': 10, //
  'sour cream': 14, 'ricotta': 7, 'milk': 7, 'yogurt': 14, 'tortilla': 10, 'bread': 5, 'bell pepper': 8, //
  'broccoli': 6, 'cauliflower': 7, 'kale': 6, 'lime': 14, 'lemon': 21, 'celery': 14, 'carrot': 21,
};

/// Rough shelf life in days once bought; drives "use it up" scoring.
int perishabilityDays(String key) {
  for (final e in _perish.entries) {
    if (key.contains(e.key)) return e.value;
  }
  return aisleFor(key) == Aisle.produce ? 10 : 60;
}

/// Produce in season by month (northern-hemisphere US), for "In season now".
const Map<int, List<String>> kSeasonalProduce = {
  1: ['citrus', 'kale', 'cabbage', 'sweet potato', 'leek'],
  2: ['citrus', 'cauliflower', 'broccoli', 'kale', 'carrot'],
  3: ['asparagus', 'pea', 'spinach', 'leek', 'artichoke'],
  4: ['asparagus', 'pea', 'radish', 'strawberry', 'spinach'],
  5: ['strawberry', 'asparagus', 'pea', 'rhubarb', 'green onion'],
  6: ['strawberry', 'zucchini', 'cherry', 'blueberry', 'basil'],
  7: ['corn', 'tomato', 'zucchini', 'peach', 'blueberry', 'basil'],
  8: ['corn', 'tomato', 'peach', 'bell pepper', 'eggplant', 'watermelon'],
  9: ['apple', 'tomato', 'bell pepper', 'squash', 'grape'],
  10: ['apple', 'pumpkin', 'squash', 'pear', 'sweet potato'],
  11: ['squash', 'sweet potato', 'brussels sprout', 'cranberry', 'pear'],
  12: ['citrus', 'brussels sprout', 'sweet potato', 'kale', 'pomegranate'],
};
