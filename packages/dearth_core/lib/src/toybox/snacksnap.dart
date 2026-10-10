import 'dart:math';

import 'package:meta/meta.dart';

import 'games.dart';
import 'rounds.dart';

// Snack Snap (SPEC FR-TOY-03, Appendix B: seeing amounts at a glance).
// Feed the Monster's orange cousin asks for a number of treats — "Four
// treats, please!" — and plates show amounts as a pattern she must take
// in at a glance: dots in rows, dice pips, later a ten-frame. Wrong
// plates say their own amount ("That's three!"), so every slip is still
// subitizing practice. No game trains this yet; it's the base of number
// sense. The top level flashes the plates and covers them: look, then
// choose from memory.

enum SnackPattern { row, dice, frame }

@immutable
class SnackPlate {
  const SnackPlate(this.n, this.pattern);
  final int n;
  final SnackPattern pattern;
}

@immutable
class SnackRound {
  const SnackRound(this.want, this.plates, {this.flash = false});

  /// How many treats the monster wants.
  final int want;

  /// [SnackPlate]s with distinct amounts; one equals [want].
  final List<SnackPlate> plates;

  /// The plates show for two seconds, then cover over.
  final bool flash;

  int get answer => plates.indexWhere((p) => p.n == want);
}

/// A round at [level] (the ladder above); the want never repeats [last]'s.
SnackRound snackRound(int level, Random rng, {SnackRound? last}) {
  for (var i = 0;; i++) {
    final r = _round(level, rng);
    if (last == null || r.want != last.want || i >= 20) return r;
  }
}

SnackRound _round(int level, Random rng) {
  switch (level) {
    case <= 1:
      // Exactly one, two and three: she learns what each looks like.
      final plates = [for (var n = 1; n <= 3; n++) SnackPlate(n, SnackPattern.row)]..shuffle(rng);
      return SnackRound(1 + rng.nextInt(3), plates);
    case 2:
      final want = 1 + rng.nextInt(6);
      final amounts = [want, ..._distractors(want, 2, 1, 6, rng)]..shuffle(rng);
      return SnackRound(want, [for (final n in amounts) SnackPlate(n, SnackPattern.dice)]);
    case 3:
      final want = 5 + rng.nextInt(6);
      final amounts = [want, ..._distractors(want, 3, 5, 10, rng, neighbor: true)]..shuffle(rng);
      return SnackRound(want, [for (final n in amounts) SnackPlate(n, SnackPattern.frame)]);
    default:
      final want = 1 + rng.nextInt(6);
      final amounts = [want, ..._distractors(want, 3, 1, 6, rng)]..shuffle(rng);
      return SnackRound(want, [for (final n in amounts) SnackPlate(n, rng.nextBool() ? SnackPattern.row : SnackPattern.dice)], flash: true);
  }
}

/// [count] amounts beside [want], all within [lo]–[hi], distinct: the
/// want's neighbors ±1–2 first (so a wrong plate is one she must look at
/// closely), the whole range as a fallback when the want is at an edge.
/// With [neighbor] one distractor is always want ± 1.
List<int> _distractors(int want, int count, int lo, int hi, Random rng, {bool neighbor = false}) {
  final out = <int>[];
  if (neighbor) {
    final sides = [for (final d in (rng.nextBool() ? [-1, 1] : [1, -1])) if (want + d >= lo && want + d <= hi) want + d];
    if (sides.isNotEmpty) out.add(sides.first);
  }
  final near = [for (final d in [1, -1, 2, -2]) want + d]..shuffle(rng);
  final far = [for (var n = lo; n <= hi; n++) if (n != want) n]..shuffle(rng);
  for (var guard = 0; out.length < count && guard < 200; guard++) {
    final n = near.isNotEmpty ? near.removeLast() : far.removeLast();
    if (n >= lo && n <= hi && n != want && !out.contains(n)) out.add(n);
  }
  return out;
}

/// Where a plate's treats sit, as (x, y) in a unit square (0–1), so the
/// app draws them and the tests check them: row (rows of up to three,
/// centered), dice (the standard pips for 1–6), frame (two rows of five,
/// the top row filling left to right first).
List<(double, double)> snackDots(SnackPlate p) => switch (p.pattern) {
      SnackPattern.row => _rowDots(p.n),
      SnackPattern.dice => p.n >= 1 && p.n <= 6 ? _diceDots[p.n]! : _rowDots(p.n),
      SnackPattern.frame => [for (var i = 0; i < p.n; i++) (0.1 + (i % 5) * 0.2, i < 5 ? 0.3 : 0.7)],
    };

List<(double, double)> _rowDots(int n) {
  final rows = (n + 2) ~/ 3;
  return [
    for (var r = 0; r < rows; r++)
      for (var i = 0; i < min(3, n - 3 * r); i++) (0.5 + (i - (min(3, n - 3 * r) - 1) / 2) * 0.3, 0.5 + (r - (rows - 1) / 2) * 0.3),
  ];
}

const Map<int, List<(double, double)>> _diceDots = {
  1: [(0.5, 0.5)],
  2: [(0.25, 0.25), (0.75, 0.75)],
  3: [(0.25, 0.25), (0.5, 0.5), (0.75, 0.75)],
  4: [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)],
  5: [(0.25, 0.25), (0.75, 0.25), (0.5, 0.5), (0.25, 0.75), (0.75, 0.75)],
  6: [(0.25, 0.25), (0.75, 0.25), (0.25, 0.5), (0.75, 0.5), (0.25, 0.75), (0.75, 0.75)],
};

/// A wrong plate is a slip: the first is "helped", more a miss. A look at
/// the covered plates (the say-again button at the top level) can't be a
/// clean win either.
String snackResult(int slips, {bool peeked = false}) => peeked && slips == 0 ? GameResult.helped : countingResult(slips);
