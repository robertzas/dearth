import 'dart:math';

import 'package:meta/meta.dart';

import 'games.dart';

// Rounds of the launch-set games (SPEC FR-TOY-02, Appendix B): what each
// level asks for, generated from a Random so a test can replay it. Drawing
// and touch live in the app; the rules live here.

int _step(List<int> ladder, int level) => ladder[(level - 1).clamp(0, ladder.length - 1)];

/// How a round went, from the help it needed: none or a little is a win, more
/// is "helped" (the level stays), a lot is a miss (three in a row: easier).
String resultFor(int slips, {required int allowed}) => slips <= allowed ? GameResult.win : (slips <= allowed * 3 ? GameResult.helped : GameResult.miss);

// ─────────────────────────────── Memory Match ───────────────────────────────

/// Pairs per level: 2 → 12.
const List<int> kMemoryPairs = [2, 3, 4, 6, 8, 12];

const List<String> kMemoryFaces = ['🐶', '🐱', '🐰', '🦊', '🐻', '🐼', '🐸', '🐵', '🦁', '🐯', '🐮', '🐷', '🐔', '🐧', '🦄', '🐙'];

/// A shuffled deck: every face twice.
List<String> memoryDeck(int level, Random rng, {List<String> faces = kMemoryFaces}) {
  final pairs = _step(kMemoryPairs, level);
  final picks = ([...faces]..shuffle(rng)).take(pairs).toList();
  return [...picks, ...picks]..shuffle(rng);
}

/// A finished board: up to one wrong pair per pair is a win.
String memoryResult(int pairs, int mismatches) => resultFor(mismatches, allowed: pairs);

// ─────────────────────────────── Shape Sorter ───────────────────────────────

enum ToyShape { circle, square, triangle, star, heart, hexagon, oval, diamond }

/// Shapes per level: 2 → 8; the last level turns the holes.
const List<int> kShapeCounts = [2, 3, 4, 6, 8];

@immutable
class ShapeRound {
  const ShapeRound(this.shapes, {required this.rotated});

  /// In the order the holes sit on the board.
  final List<ToyShape> shapes;

  /// Holes turned at an angle: the shape has to be recognized, not matched.
  final bool rotated;
}

ShapeRound shapeRound(int level, Random rng) {
  final n = _step(kShapeCounts, level);
  final shapes = ToyShape.values.take(n).toList()..shuffle(rng);
  return ShapeRound(shapes, rotated: level >= kShapeCounts.length);
}

// ────────────────────────────── Counting Garden ─────────────────────────────

@immutable
class CountingRound {
  const CountingRound(this.count, this.choices, {required this.flash});
  final int count;

  /// The answers to pick from, including [count], in order.
  final List<int> choices;

  /// Subitizing: the flowers show for a moment only, so she sees "how many"
  /// without counting one by one.
  final bool flash;
}

/// 1–3 with two answers, 1–5 and 1–10 with three, then quick flashes of 1–6.
CountingRound countingRound(int level, Random rng) {
  final (top, choices, flash) = switch (level) { 1 => (3, 2, false), 2 => (5, 3, false), 3 => (10, 3, false), _ => (6, 3, true) };
  final count = 1 + rng.nextInt(top);
  final others = [for (var n = 1; n <= top; n++) if (n != count) n]
    // Near misses teach more than far ones.
    ..sort((a, b) => (a - count).abs().compareTo((b - count).abs()));
  final picks = [count, ...others.take(choices - 1)]..sort();
  return CountingRound(count, picks, flash: flash);
}

// ───────────────────────────── Feed the Monster ─────────────────────────────

@immutable
class Food {
  const Food(this.emoji, this.name, {required this.color, required this.round, required this.kind});
  final String emoji;
  final String name;
  final String color;
  final bool round;

  /// fruit, vegetable or treat
  final String kind;

  @override
  String toString() => emoji;
}

const List<Food> kFoods = [
  Food('🍎', 'apple', color: 'red', round: true, kind: 'fruit'),
  Food('🍓', 'strawberry', color: 'red', round: false, kind: 'fruit'),
  Food('🍒', 'cherries', color: 'red', round: true, kind: 'fruit'),
  Food('🍅', 'tomato', color: 'red', round: true, kind: 'vegetable'),
  Food('🌶️', 'pepper', color: 'red', round: false, kind: 'vegetable'),
  Food('🍌', 'banana', color: 'yellow', round: false, kind: 'fruit'),
  Food('🍋', 'lemon', color: 'yellow', round: true, kind: 'fruit'),
  Food('🌽', 'corn', color: 'yellow', round: false, kind: 'vegetable'),
  Food('🍐', 'pear', color: 'green', round: false, kind: 'fruit'),
  Food('🥝', 'kiwi', color: 'green', round: true, kind: 'fruit'),
  Food('🥦', 'broccoli', color: 'green', round: false, kind: 'vegetable'),
  Food('🥒', 'cucumber', color: 'green', round: false, kind: 'vegetable'),
  Food('🍇', 'grapes', color: 'purple', round: false, kind: 'fruit'),
  Food('🍆', 'eggplant', color: 'purple', round: false, kind: 'vegetable'),
  Food('🫐', 'blueberries', color: 'blue', round: true, kind: 'fruit'),
  Food('🍊', 'orange', color: 'orange', round: true, kind: 'fruit'),
  Food('🥕', 'carrot', color: 'orange', round: false, kind: 'vegetable'),
  Food('🍩', 'donut', color: 'pink', round: true, kind: 'treat'),
  Food('🧁', 'cupcake', color: 'pink', round: false, kind: 'treat'),
  Food('🍪', 'cookie', color: 'brown', round: true, kind: 'treat'),
];

/// What the monster eats today: one attribute, or two that must both hold.
@immutable
class MonsterRule {
  const MonsterRule({this.color, this.round, this.kind});
  final String? color;
  final bool? round;
  final String? kind;

  bool accepts(Food f) => (color == null || f.color == color) && (round == null || f.round == round) && (kind == null || f.kind == kind);

  /// "red", "round", "fruit", "red and round".
  String get words => [?color, if (round == true) 'round', ?kind].join(' and ');

  @override
  String toString() => words;
}

@immutable
class MonsterRound {
  const MonsterRound(this.rule, this.tray);
  final MonsterRule rule;

  /// Some it eats, some it doesn't, shuffled.
  final List<Food> tray;
  int get toEat => tray.where(rule.accepts).length;
}

/// One color among two, then among more, then a shape or a kind, then two
/// attributes at once ("red AND round", with decoys that are only one).
MonsterRound monsterRound(int level, Random rng) {
  MonsterRule pick() {
    final f = kFoods[rng.nextInt(kFoods.length)];
    return switch (level) {
      1 || 2 => MonsterRule(color: f.color),
      3 => rng.nextBool() ? MonsterRule(kind: f.kind) : const MonsterRule(round: true),
      _ => rng.nextBool() ? MonsterRule(color: f.color, round: true) : MonsterRule(color: f.color, kind: f.kind),
    };
  }

  var rule = pick();
  // Two-attribute rules need at least two foods that fit.
  while (kFoods.where(rule.accepts).length < (level >= 4 ? 1 : 2)) {
    rule = pick();
  }
  final size = switch (level) { 1 => 4, 2 || 3 => 6, _ => 8 };
  final yes = [...kFoods.where(rule.accepts)]..shuffle(rng);
  // Level 1: just one other color, so the choice is plain.
  final other = level == 1 ? _otherColor(rule.color!, rng.nextInt(1 << 20)) : null;
  final no = [...kFoods.where((f) => !rule.accepts(f) && (other == null || f.color == other))]..shuffle(rng);
  if (level >= 4) {
    // Decoys that match one of the two attributes teach the "and".
    no.sort((a, b) => _partial(rule, b).compareTo(_partial(rule, a)));
  }
  final eat = yes.take(min(yes.length, max(1, size ~/ 2))).toList();
  final tray = [...eat, ...no.take(size - eat.length)]..shuffle(rng);
  return MonsterRound(rule, tray);
}

String _otherColor(String color, int seed) {
  const plain = ['red', 'yellow', 'green', 'orange', 'purple'];
  final others = [for (final c in plain) if (c != color) c];
  return others[seed % others.length];
}

int _partial(MonsterRule r, Food f) =>
    (r.color != null && f.color == r.color ? 1 : 0) + (r.round != null && f.round == r.round ? 1 : 0) + (r.kind != null && f.kind == r.kind ? 1 : 0);

// ─────────────────────────────────── Jigsaw ─────────────────────────────────

/// Pieces per level: 2 → 24.
const List<int> kJigsawPieces = [2, 4, 6, 9, 12, 16, 24];

/// Rows and columns for a level, the long side along the picture's.
({int rows, int cols}) jigsawGrid(int level, {bool landscape = true}) {
  final (a, b) = switch (_step(kJigsawPieces, level)) { 2 => (1, 2), 4 => (2, 2), 6 => (2, 3), 9 => (3, 3), 12 => (3, 4), 16 => (4, 4), _ => (4, 6) };
  return landscape ? (rows: a, cols: b) : (rows: b, cols: a);
}

/// Which way each inner edge's tab points: +1 out of the left/top piece, −1
/// into it. `right[r][c]` is the edge right of piece (r, c); `down[r][c]` the
/// edge below it.
({List<List<int>> right, List<List<int>> down}) jigsawTabs(int rows, int cols, Random rng) => (
      right: [for (var r = 0; r < rows; r++) [for (var c = 0; c < cols - 1; c++) rng.nextBool() ? 1 : -1]],
      down: [for (var r = 0; r < rows - 1; r++) [for (var c = 0; c < cols; c++) rng.nextBool() ? 1 : -1]],
    );

// ──────────────────────────────── Bubble Pop ────────────────────────────────

@immutable
class BubbleRound {
  const BubbleRound({required this.riseSeconds, required this.colorCall, required this.targets});

  /// Seconds a bubble takes to cross the screen.
  final double riseSeconds;

  /// "Pop the blue ones!": only bubbles of one color count.
  final bool colorCall;

  /// Pops that finish a round.
  final int targets;
}

BubbleRound bubbleRound(int level) => switch (level) {
      1 => const BubbleRound(riseSeconds: 9, colorCall: false, targets: 12),
      2 => const BubbleRound(riseSeconds: 6, colorCall: false, targets: 15),
      3 => const BubbleRound(riseSeconds: 7, colorCall: true, targets: 8),
      _ => const BubbleRound(riseSeconds: 5, colorCall: true, targets: 10),
    };

// ─────────────────────────────── Animal Farm ────────────────────────────────

@immutable
class FarmAnimal {
  const FarmAnimal(this.id, this.name, this.emoji, this.says);
  final String id;
  final String name;
  final String emoji;

  /// Written the way a book spells it: "Moo!"
  final String says;
}

const List<FarmAnimal> kFarmAnimals = [
  FarmAnimal('cow', 'Cow', '🐮', 'Moo!'),
  FarmAnimal('pig', 'Pig', '🐷', 'Oink oink!'),
  FarmAnimal('sheep', 'Sheep', '🐑', 'Baa!'),
  FarmAnimal('duck', 'Duck', '🦆', 'Quack quack!'),
  FarmAnimal('chicken', 'Chicken', '🐔', 'Cluck cluck!'),
  FarmAnimal('horse', 'Horse', '🐴', 'Neigh!'),
  FarmAnimal('dog', 'Dog', '🐶', 'Woof woof!'),
  FarmAnimal('cat', 'Cat', '🐱', 'Meow!'),
  FarmAnimal('frog', 'Frog', '🐸', 'Ribbit!'),
  FarmAnimal('owl', 'Owl', '🦉', 'Hoo hoo!'),
];

@immutable
class FarmRound {
  const FarmRound(this.animals, this.find);
  final List<FarmAnimal> animals;

  /// "Where's the cow?" — null in free play.
  final FarmAnimal? find;
}

/// Free play with six animals, then "where's the …?" among three, then six.
FarmRound farmRound(int level, Random rng) {
  final animals = ([...kFarmAnimals]..shuffle(rng)).take(level == 2 ? 3 : 6).toList();
  return FarmRound(animals, level == 1 ? null : animals[rng.nextInt(animals.length)]);
}

// ──────────────────────────── Xylophone & Drums ─────────────────────────────

/// The xylophone's eight bars: C major pentatonic, so any tune sounds good.
const List<int> kXylophoneMidi = [60, 62, 64, 67, 69, 72, 74, 76];

/// "Echo my rhythm": bars to play back, by index. Free play (level 1) has
/// none; then three notes, then five.
List<int> echoPattern(int level, Random rng) {
  final n = switch (level) { 1 => 0, 2 => 3, _ => 5 };
  final out = <int>[];
  while (out.length < n) {
    final bar = rng.nextInt(kXylophoneMidi.length);
    // Repeats are fine, three in a row isn't a tune.
    if (out.length >= 2 && out[out.length - 1] == bar && out[out.length - 2] == bar) continue;
    out.add(bar);
  }
  return out;
}
