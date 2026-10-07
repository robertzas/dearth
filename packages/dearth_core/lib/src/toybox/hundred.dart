import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';

// Hundred Square (SPEC FR-TOY-03, Appendix B: counting past twenty, place
// value). A ladybug sits on a number square; the voice asks for a number
// and she finds it. The right square lights its whole row, so each find
// shows the tens; a wrong one says its own number (45 for 54 is the
// mistake the square teaches past). The ladder grows the square, a row,
// two rows, then all hundred, and at the top some numbers hide: she finds
// where the missing one goes from its row and column. Drawing lives in
// the app.

@immutable
class HundredRound {
  const HundredRound(this.rows, this.target, {this.hidden = const {}});

  /// Rows of ten on the square (1–10 is one row).
  final int rows;

  /// The number she finds.
  final int target;

  /// Numbers whose squares are blank (the target among them at the top level).
  final Set<int> hidden;

  int get cells => rows * 10;

  /// The target's row, from 0 (1–10).
  int get row => (target - 1) ~/ 10;

  bool get hiding => hidden.contains(target);
}

/// A round at [level] (Appendix B ladder): find 1–10 on one row → 1–20 on
/// two → anything up to 100 on the whole square (more often past 20, where
/// the reversed twin is on the board too) → a hidden number's place, with
/// a dozen others blank around the square. Not the same number as [last].
HundredRound hundredRound(int level, Random rng, {HundredRound? last}) {
  for (var i = 0;; i++) {
    final r = _round(level, rng);
    if (last == null || r.target != last.target || i >= 20) return r;
  }
}

HundredRound _round(int level, Random rng) {
  final rows = switch (level) { <= 1 => 1, 2 => 2, _ => 10 };
  if (level <= 2) return HundredRound(rows, 1 + rng.nextInt(rows * 10));
  // Past twenty mostly: the first rows were the levels before.
  final target = rng.nextDouble() < 0.8 ? 21 + rng.nextInt(80) : 1 + rng.nextInt(20);
  if (level == 3) return HundredRound(rows, target);
  // Hide the target and a dozen others, but never its neighbors in the
  // row: they say where it goes.
  final hidden = <int>{target};
  while (hidden.length < 13) {
    final n = 1 + rng.nextInt(100);
    final sameRow = (n - 1) ~/ 10 == (target - 1) ~/ 10;
    if (!sameRow || (n - target).abs() > 1) hidden.add(n);
  }
  return HundredRound(rows, target, hidden: hidden);
}

/// A slip on a square of ten or twenty is "helped"; on the whole square
/// one is fine (there are a hundred to choose from).
String hundredResult(HundredRound r, int slips) => r.rows < 10 ? countingResult(slips) : resultFor(slips, allowed: 1);
