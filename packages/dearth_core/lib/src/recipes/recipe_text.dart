import 'ingredients.dart';

// A recipe as the family types it (SPEC FR-RCP-01, the family recipe box:
// hand-entered or edited). Ingredients go one per line, a group as a line
// of its own ending in a colon ("For the sauce:"), and steps one per line.
// The editor shows a recipe through these and saves through them, so a
// recipe opened and saved unchanged keeps every structured ingredient a
// source gave it.

/// Courses, in the vocabulary searches use (FR-RCP-13).
const List<String> kRecipeCourses = ['Main course', 'Breakfast', 'Lunch', 'Side', 'Starter', 'Soup', 'Salad', 'Dessert', 'Snack', 'Drink', 'Sauce', 'Baking'];

/// Diets, in the vocabulary searches use (FR-RCP-13).
const List<String> kRecipeDiets = ['vegetarian', 'vegan', 'pescatarian', 'gluten free', 'dairy free', 'nut free', 'keto'];

/// The tag the "Toddler-approved" feed and kid-friendly sources use.
const String kKidFriendlyTag = 'kid-friendly';

/// [ingredients] as editable text: each line as written, a group's name on
/// a line of its own ending in a colon, a blank line before each group.
String ingredientsText(List<Ingredient> ingredients) {
  final out = <String>[];
  String? group;
  for (final i in ingredients) {
    if (i.group != null && i.group != group) {
      if (out.isNotEmpty) out.add('');
      out.add('${i.group}:');
    }
    group = i.group ?? group;
    out.add(_oneLine(i.raw.isNotEmpty ? i.raw : i.describe()));
  }
  return out.join('\n');
}

/// The ingredients in [text], parsed (FR-RCP-12). A line that's the same as
/// one of [before] (same words, same group) keeps that ingredient as it
/// was, so a source's structured amounts survive an edit elsewhere.
List<Ingredient> parseIngredientsText(String text, {List<Ingredient> before = const []}) {
  final kept = {for (final i in before) _keyOf(i.group, _oneLine(i.raw)): i};
  final out = <Ingredient>[];
  String? group;
  for (final raw in text.split('\n')) {
    final line = raw.trim().replaceFirst(_bullet, '').trim();
    if (line.isEmpty) continue;
    if (_isHeading(line)) {
      group = line.substring(0, line.length - 1).trim();
      continue;
    }
    out.add(kept[_keyOf(group, line)] ?? parseIngredientLine(line, group: group));
  }
  return out;
}

/// [steps] as editable text, one a line.
String stepsText(List<String> steps) => steps.map(_oneLine).join('\n');

/// The steps in [text]: one a line, without the numbers or bullets people
/// type ("1.", "Step 2:", "•"); cook mode numbers them itself.
List<String> parseStepsText(String text) => [
      for (final raw in text.split('\n'))
        if (raw.trim().replaceFirst(_stepNumber, '').trim() case final s when s.isNotEmpty) s,
    ];

/// The tags in [text], comma-separated, without repeats.
List<String> parseTagsText(String text) {
  final seen = <String>{};
  return [
    for (final t in text.split(','))
      if (t.trim() case final s when s.isNotEmpty && seen.add(s.toLowerCase())) s,
  ];
}

final _bullet = RegExp(r'^[-•*·▪◦]\s*');
final _stepNumber = RegExp(r'^(step\s*\d+\s*[:.)-]?|\d+\s*[.)]|[-•*·▪◦])\s*', caseSensitive: false);

/// "For the sauce:": short, ends in a colon, and doesn't start with an
/// amount ("2 cups:" is an ingredient someone typed oddly).
bool _isHeading(String line) => line.length > 1 && line.endsWith(':') && !RegExp(r'^\d').hasMatch(line) && line.split(RegExp(r'\s+')).length <= 6;

String _keyOf(String? group, String line) => '${group ?? ''}\n${line.trim()}';

String _oneLine(String s) => s.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
