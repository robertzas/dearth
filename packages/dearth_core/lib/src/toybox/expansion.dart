import 'dart:math';

import 'package:meta/meta.dart';

import 'games.dart';
import 'rounds.dart';

// Rounds of the Toybox expansion set (SPEC FR-TOY-03, Appendix B, M4), made
// from a Random so a test can replay them. Drawing and touch live in the
// app; the rules live here. Every picture is an Emoji 12 glyph: the kitchen
// frame (Android 10) draws nothing newer.

T _pick<T>(List<T> xs, Random rng) => xs[rng.nextInt(xs.length)];

// ─────────────────────────────────── Patterns ───────────────────────────────

/// Pictures a pattern is made of: each round draws one set.
const List<List<String>> kPatternSets = [
  ['🍎', '🍌', '🍇'],
  ['🐶', '🐱', '🐰'],
  ['⭐', '❤️', '🔵'],
  ['🌸', '🍀', '🌞'],
  ['🚗', '🚂', '✈️'],
  ['🐟', '🐙', '🐢'],
];

@immutable
class PatternRound {
  const PatternRound(this.shown, this.answer, this.choices, {this.towers = false});

  /// The pattern so far; the next one is asked for. For [towers], each
  /// entry is a stack: its picture repeated.
  final List<String> shown;
  final String answer;
  final List<String> choices;

  /// Growing patterns: stacks of one picture, one taller each step.
  final bool towers;
}

/// AB, then AAB, then ABC, then a growing tower (1, 2, 3, … what's next?).
PatternRound patternRound(int level, Random rng) {
  final set = [..._pick(kPatternSets, rng)]..shuffle(rng);
  if (level >= 4) {
    final p = set.first;
    final start = 1 + rng.nextInt(2);
    final shown = [for (var n = start; n < start + 3; n++) p * n];
    final answer = p * (start + 3);
    final choices = [p * (start + 2), answer, p * (start + 4)]..shuffle(rng);
    return PatternRound(shown, answer, choices, towers: true);
  }
  final unit = switch (level) { 1 => [set[0], set[1]], 2 => rng.nextBool() ? [set[0], set[0], set[1]] : [set[0], set[1], set[1]], _ => [set[0], set[1], set[2]] };
  // Two whole repeats and a bit, so the rule shows.
  final length = unit.length * 2 + rng.nextInt(unit.length);
  final shown = [for (var i = 0; i < length; i++) unit[i % unit.length]];
  final choices = {...unit}.toList()..shuffle(rng);
  return PatternRound(shown, unit[length % unit.length], choices);
}

// ──────────────────────────────── Odd One Out ───────────────────────────────

/// Groups for the category and "what it's for" levels. No picture is in two
/// groups of the same level.
const Map<String, List<String>> kKinds = {
  'animals': ['🐶', '🐱', '🐰', '🐮', '🐷', '🐸', '🦁', '🐵'],
  'fruit': ['🍎', '🍌', '🍇', '🍓', '🍊', '🍐'],
  'vehicles': ['🚗', '🚌', '🚂', '🚲', '🚜', '🚒'],
  'clothes': ['👕', '👖', '👗', '🧦', '👟', '🧥'],
};

const Map<String, List<String>> kUses = {
  'flies': ['🐦', '✈️', '🦋', '🚁', '🎈'],
  'hats': ['🧢', '👒', '🎩', '👑', '⛑️'],
  'music': ['🥁', '🎺', '🎸', '🎻', '🎹'],
  'water': ['🐟', '🐳', '⛵', '🐙', '🦀'],
  'warm': ['🧤', '🧣', '🔥', '🧥', '☕'],
};

/// One picture in an odd-one-out row: an emoji, or a painted [shape].
@immutable
class OddItem {
  const OddItem({this.emoji, this.shape, this.color = 0});
  final String? emoji;
  final ToyShape? shape;

  /// For shapes: an index into the app's shape colors.
  final int color;
}

@immutable
class OddRound {
  const OddRound(this.items, this.odd, this.rule);
  final List<OddItem> items;

  /// The index of the one that doesn't belong.
  final int odd;

  /// color, shape, kind or use.
  final String rule;
}

/// Four in a row, one different: by color, then shape, then kind (an apple
/// among animals), then what things are for (a drum among things that fly).
OddRound oddOneOut(int level, Random rng) {
  List<OddItem> three;
  OddItem other;
  final String rule;
  switch (level) {
    case 1:
      rule = 'color';
      final byColor = <String, List<Food>>{};
      for (final f in kFoods) {
        (byColor[f.color] ??= []).add(f);
      }
      final colors = [for (final e in byColor.entries) if (e.value.length >= 3) e.key];
      final c = _pick(colors, rng);
      three = [for (final f in ([...byColor[c]!]..shuffle(rng)).take(3)) OddItem(emoji: f.emoji)];
      other = OddItem(emoji: _pick([for (final f in kFoods) if (f.color != c) f], rng).emoji);
    case 2:
      rule = 'shape';
      final shapes = [...ToyShape.values.take(6)]..shuffle(rng);
      final colors = [0, 1, 2, 3, 4, 5]..shuffle(rng);
      three = [for (var i = 0; i < 3; i++) OddItem(shape: shapes[0], color: colors[i])];
      other = OddItem(shape: shapes[1], color: colors[3]);
    default:
      rule = level == 3 ? 'kind' : 'use';
      final groups = level == 3 ? kKinds : kUses;
      final keys = groups.keys.toList()..shuffle(rng);
      three = [for (final e in ([...groups[keys[0]]!]..shuffle(rng)).take(3)) OddItem(emoji: e)];
      other = OddItem(emoji: _pick(groups[keys[1]]!, rng));
  }
  final odd = rng.nextInt(4);
  return OddRound([...three.take(odd), other, ...three.skip(odd)], odd, rule);
}

// ──────────────────────────────── Shadow Match ──────────────────────────────

/// Pictures with outlines worth recognizing, by family: the later levels
/// draw all of a round's pictures from one family, so the shadows look
/// alike.
const Map<String, List<String>> kShadowFamilies = {
  'animals': ['🐘', '🦒', '🐢', '🐇', '🦆', '🐌', '🐎', '🐓', '🦕', '🐿️'],
  'things': ['🚲', '🎸', '☂️', '🔑', '✂️', '🏠', '⏰', '🎈'],
  'food': ['🍌', '🍐', '🍕', '🥕', '🍉', '🥨', '🍦', '🥦'],
};

/// Shadows per level: 2 → 6.
const List<int> kShadowCounts = [2, 3, 4, 6];

@immutable
class ShadowRound {
  const ShadowRound(this.pictures, this.shadows);

  /// To drag, in the tray's order.
  final List<String> pictures;

  /// The same pictures as shadows, in the board's order.
  final List<String> shadows;
}

ShadowRound shadowRound(int level, Random rng) {
  final n = kShadowCounts[(level - 1).clamp(0, kShadowCounts.length - 1)];
  final List<String> pool;
  if (level <= 2) {
    // Mixed families: shadows that differ a lot.
    pool = [for (final f in kShadowFamilies.values) ...f]..shuffle(rng);
  } else {
    pool = [..._pick(kShadowFamilies.values.toList(), rng)]..shuffle(rng);
  }
  final pictures = pool.take(n).toList();
  return ShadowRound(pictures, [...pictures]..shuffle(rng));
}

// ───────────────────────────────── Size Order ───────────────────────────────

/// Sizes in a row per level: 3 → 6.
const List<int> kSizeCounts = [3, 4, 5, 6];

const List<String> kSizePictures = ['🐻', '🐟', '🌳', '🍎', '🚂', '🏠', '⭐', '🐘', '🎁', '🌷'];

@immutable
class SizeRound {
  const SizeRound(this.emoji, this.scales);
  final String emoji;

  /// Each one's size (0…1 of the biggest), in the order they're laid out.
  final List<double> scales;

  /// Indices from smallest to biggest: the order to tap them in.
  List<int> get order => [for (var i = 0; i < scales.length; i++) i]..sort((a, b) => scales[a].compareTo(scales[b]));
}

/// The same picture in [n] sizes, shuffled. Sizes step evenly from 35% to
/// 100%, so neighbours always differ enough to see.
SizeRound sizeRound(int level, Random rng) {
  final n = kSizeCounts[(level - 1).clamp(0, kSizeCounts.length - 1)];
  final scales = [for (var i = 0; i < n; i++) 0.35 + 0.65 * i / (n - 1)]..shuffle(rng);
  return SizeRound(_pick(kSizePictures, rng), scales);
}

// ─────────────────────────────── Picture Sudoku ─────────────────────────────

const List<String> kSudokuFruit = ['🍎', '🍌', '🍇', '🍊'];

/// Empty squares per level: 1 → 6.
const List<int> kSudokuBlanks = [1, 2, 3, 4, 5, 6];

@immutable
class SudokuRound {
  const SudokuRound(this.solution, this.blanks);

  /// 4 × 4, row by row: an index into [kSudokuFruit]. Every row, column
  /// and 2 × 2 box holds each fruit once.
  final List<int> solution;

  /// The squares to fill (indices into [solution]).
  final Set<int> blanks;
}

bool sudokuValid(List<int> g) {
  bool distinct(Iterable<int> cells) => cells.map((i) => g[i]).toSet().length == 4;
  for (var k = 0; k < 4; k++) {
    if (!distinct([for (var c = 0; c < 4; c++) k * 4 + c])) return false;
    if (!distinct([for (var r = 0; r < 4; r++) r * 4 + k])) return false;
    final r0 = (k ~/ 2) * 2, c0 = (k % 2) * 2;
    if (!distinct([r0 * 4 + c0, r0 * 4 + c0 + 1, (r0 + 1) * 4 + c0, (r0 + 1) * 4 + c0 + 1])) return false;
  }
  return true;
}

/// How many ways [g] (−1 for empty) can be finished, stopping at [limit].
int sudokuSolutions(List<int> g, {int limit = 2}) {
  final i = g.indexOf(-1);
  if (i < 0) return sudokuValid(g) ? 1 : 0;
  final r = i ~/ 4, c = i % 4;
  var count = 0;
  for (var v = 0; v < 4 && count < limit; v++) {
    final clash = [
      for (var k = 0; k < 4; k++) g[r * 4 + k],
      for (var k = 0; k < 4; k++) g[k * 4 + c],
      for (final (dr, dc) in const [(0, 0), (0, 1), (1, 0), (1, 1)]) g[((r ~/ 2) * 2 + dr) * 4 + (c ~/ 2) * 2 + dc],
    ].contains(v);
    if (clash) continue;
    g[i] = v;
    count += sudokuSolutions(g, limit: limit - count);
    g[i] = -1;
  }
  return count;
}

/// A shuffled valid grid with blanks that leave exactly one answer.
SudokuRound sudokuRound(int level, Random rng) {
  // A valid grid, then shuffles that keep it valid: fruit, rows in a band,
  // bands, columns in a stack, stacks, and a turn across the diagonal.
  var g = [0, 1, 2, 3, 2, 3, 0, 1, 1, 0, 3, 2, 3, 2, 1, 0];
  final fruit = [0, 1, 2, 3]..shuffle(rng);
  g = [for (final v in g) fruit[v]];
  List<int> rows(List<int> order) => [for (final r in order) ...g.sublist(r * 4, r * 4 + 4)];
  List<int> cols(List<int> order) => [for (var r = 0; r < 4; r++) for (final c in order) g[r * 4 + c]];
  List<int> perm() {
    final a = rng.nextBool() ? [0, 1] : [1, 0], b = rng.nextBool() ? [2, 3] : [3, 2];
    return rng.nextBool() ? [...a, ...b] : [...b, ...a];
  }

  g = rows(perm());
  g = cols(perm());
  if (rng.nextBool()) g = [for (var r = 0; r < 4; r++) for (var c = 0; c < 4; c++) g[c * 4 + r]];
  final want = kSudokuBlanks[(level - 1).clamp(0, kSudokuBlanks.length - 1)];
  final cells = [for (var i = 0; i < 16; i++) i]..shuffle(rng);
  final blanks = <int>{};
  final work = [...g];
  for (final i in cells) {
    if (blanks.length == want) break;
    work[i] = -1;
    if (sudokuSolutions([...work]) == 1) {
      blanks.add(i);
    } else {
      work[i] = g[i];
    }
  }
  return SudokuRound(g, blanks);
}

// ───────────────────────────── Spot the Difference ──────────────────────────

/// One picture in a scene, at fractions of the picture (0…1).
@immutable
class ScenePart {
  const ScenePart(this.emoji, this.x, this.y, this.size, {this.flipped = false});
  final String emoji;
  final double x, y;

  /// Fraction of the picture's height.
  final double size;
  final bool flipped;

  ScenePart copyWith({String? emoji, double? x, double? y, double? size, bool? flipped}) =>
      ScenePart(emoji ?? this.emoji, x ?? this.x, y ?? this.y, size ?? this.size, flipped: flipped ?? this.flipped);
}

/// Scenes to play with: a backdrop and what can stand in it.
const Map<String, List<String>> kSceneKits = {
  'park': ['🌳', '🌷', '🐿️', '🦆', '⚽', '🪁', '🐕', '🌻', '🍄', '🐦', '🦋', '🌲'],
  'sea': ['🐟', '🐠', '🐙', '🦀', '🐚', '⭐', '🐳', '⛵', '🦈', '🐬', '🦑', '🌊'],
  'farm': ['🐄', '🐖', '🐑', '🐓', '🚜', '🌾', '🐴', '🥕', '🐐', '🐔', '🌽', '🐶'],
  'space': ['🚀', '🌙', '⭐', '🪐', '👽', '🛸', '☄️', '🌍', '🛰️', '🌟', '🌕', '🔭'],
};

/// Differences per level: 3 → 7; later ones get subtle (a turned picture,
/// a smaller one, one moved a little).
const List<int> kDifferenceCounts = [3, 4, 5, 6, 7];

@immutable
class DifferenceRound {
  const DifferenceRound(this.kit, this.left, this.right, this.spots);
  final String kit;
  final List<ScenePart> left, right;

  /// Where the differences are (fractions), as (x, y, radius).
  final List<(double, double, double)> spots;
}

DifferenceRound differenceRound(int level, Random rng) {
  final kitName = _pick(kSceneKits.keys.toList(), rng);
  final kit = [...kSceneKits[kitName]!]..shuffle(rng);
  final n = kDifferenceCounts[(level - 1).clamp(0, kDifferenceCounts.length - 1)];
  // A loose grid with jitter keeps parts apart: no difference hides another.
  const cols = 4, rows = 3;
  final cells = [for (var i = 0; i < cols * rows; i++) i]..shuffle(rng);
  final count = min(kit.length, 7 + n);
  final left = [
    for (var k = 0; k < count; k++)
      ScenePart(
        kit[k],
        (cells[k] % cols + 0.5 + (rng.nextDouble() - 0.5) * 0.35) / cols,
        (cells[k] ~/ cols + 0.5 + (rng.nextDouble() - 0.5) * 0.3) / rows,
        0.14 + rng.nextDouble() * 0.06,
        flipped: rng.nextBool(),
      ),
  ];
  final right = [...left];
  final spots = <(double, double, double)>[];
  final changed = ([for (var k = 0; k < count; k++) k]..shuffle(rng)).take(n).toList();
  final spare = kit.skip(count).toList();
  final subtle = level >= 4;
  for (final (j, k) in changed.indexed) {
    final p = left[k];
    // Early levels: things missing or swapped. Later: subtler changes too.
    final kinds = subtle ? const ['missing', 'swap', 'flip', 'size', 'move'] : const ['missing', 'swap', 'missing'];
    final kind = kinds[(j + rng.nextInt(kinds.length)) % kinds.length];
    switch (kind) {
      case 'missing':
        right[k] = p.copyWith(size: 0);
      case 'swap':
        right[k] = p.copyWith(emoji: spare.isNotEmpty ? spare.removeAt(0) : kit[(kit.indexOf(p.emoji) + 1) % kit.length]);
      case 'flip':
        right[k] = p.copyWith(flipped: !p.flipped);
      case 'size':
        right[k] = p.copyWith(size: p.size * 0.6);
      default:
        right[k] = p.copyWith(y: (p.y + (p.y < 0.5 ? 0.12 : -0.12)).clamp(0.08, 0.92));
    }
    spots.add((p.x, (p.y + right[k].y) / 2, max(p.size, 0.12) * 0.75 + (p.y - right[k].y).abs() / 2));
  }
  return DifferenceRound(kitName, left, right, spots);
}

// ───────────────────────────── Sequencing Stories ───────────────────────────

/// Little stories in pictures, first to last.
const List<List<String>> kStories = [
  ['🥚', '🐣', '🐥'],
  ['🌱', '🌿', '🌷'],
  ['☁️', '🌧️', '🌈'],
  ['❄️', '⛄', '💧'],
  ['🌅', '☀️', '🌙'],
  ['🥚', '🐣', '🐥', '🐔'],
  ['🌰', '🌱', '🌳', '🍎'],
  ['👶', '🧒', '🧑', '👴'],
  ['🌑', '🌓', '🌕'],
  ['🍞', '🥪', '😋'],
  ['🎂', '🕯️', '🎉'],
  ['🌱', '🌿', '🌷', '🐝', '🍯'],
  ['👶', '🧒', '🧑', '👨', '👴'],
  ['🌅', '🌞', '🌇', '🌙', '🌟'],
];

/// Cards per level: 3 → 5.
const List<int> kStoryLengths = [3, 4, 5];

@immutable
class StoryRound {
  const StoryRound(this.story, this.cards);

  /// First to last.
  final List<String> story;

  /// The same pictures, shuffled (never already in order).
  final List<String> cards;
}

StoryRound storyRound(int level, Random rng) {
  final n = kStoryLengths[(level - 1).clamp(0, kStoryLengths.length - 1)];
  final fits = [for (final s in kStories) if (s.length == n) s];
  final story = _pick(fits, rng);
  var cards = [...story];
  while (cards.join() == story.join()) {
    cards = [...story]..shuffle(rng);
  }
  return StoryRound(story, cards);
}

// ──────────────────────────────── Finger Mazes ──────────────────────────────

/// Maze sizes per level (columns × rows): wide paths first, then more
/// turns, branches and dead ends.
const List<(int, int)> kMazeSizes = [(3, 2), (4, 3), (5, 4), (7, 5)];

@immutable
class MazeRound {
  const MazeRound(this.cols, this.rows, this.open);
  final int cols, rows;

  /// Open passages, each as the two cell indices (lower first).
  final Set<(int, int)> open;

  /// Start bottom-left, home top-right.
  int get start => (rows - 1) * cols;
  int get home => cols - 1;

  bool connected(int a, int b) => open.contains(a < b ? (a, b) : (b, a));

  /// The way home from [from], cell by cell (breadth-first).
  List<int> path(int from) {
    final prev = <int, int>{from: from};
    final queue = [from];
    while (queue.isNotEmpty) {
      final c = queue.removeAt(0);
      if (c == home) break;
      for (final n in neighbours(c)) {
        if (connected(c, n) && !prev.containsKey(n)) {
          prev[n] = c;
          queue.add(n);
        }
      }
    }
    final out = [home];
    while (out.last != from) {
      out.add(prev[out.last]!);
    }
    return out.reversed.toList();
  }

  List<int> neighbours(int c) => [
        if (c % cols > 0) c - 1,
        if (c % cols < cols - 1) c + 1,
        if (c >= cols) c - cols,
        if (c < (rows - 1) * cols) c + cols,
      ];
}

/// A perfect maze (one way between any two cells) by a randomized
/// depth-first carve.
MazeRound mazeRound(int level, Random rng) {
  final (cols, rows) = kMazeSizes[(level - 1).clamp(0, kMazeSizes.length - 1)];
  final m = MazeRound(cols, rows, const {});
  final open = <(int, int)>{};
  final seen = {m.start};
  final stack = [m.start];
  while (stack.isNotEmpty) {
    final c = stack.last;
    final next = [for (final n in m.neighbours(c)) if (!seen.contains(n)) n];
    if (next.isEmpty) {
      stack.removeLast();
      continue;
    }
    final n = _pick(next, rng);
    open.add(c < n ? (c, n) : (n, c));
    seen.add(n);
    stack.add(n);
  }
  return MazeRound(cols, rows, open);
}

// ──────────────────────────────── Results ───────────────────────────────────

/// Sequencing, size order, sudoku and the like: on a small board, right
/// the first time is a win and one slip "helped"; on a bigger one a slip
/// per four is still a win.
String expansionResult(int slips, {int size = 3}) => size <= 3 ? countingResult(slips) : resultFor(slips, allowed: size ~/ 4);

/// All the pictures the expansion set draws, for the frame's Emoji 12 check.
List<String> get kExpansionPictures => [
      for (final s in kPatternSets) ...s,
      for (final g in kKinds.values) ...g,
      for (final g in kUses.values) ...g,
      for (final g in kShadowFamilies.values) ...g,
      ...kSizePictures,
      ...kSudokuFruit,
      for (final k in kSceneKits.values) ...k,
      for (final s in kStories) ...s,
      for (final g in kExpansionGames) g.emoji,
    ];
