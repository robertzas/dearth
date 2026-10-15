import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';

// Block Tower (SPEC FR-TOY-03, Appendix B: counting to a number, height,
// one more and one less). The giraffe wants to reach the star: "Build a
// tower five blocks tall!" Each tap drops a block that wobbles onto the
// tower and is counted out loud; the top block taps off again. The bell
// checks: right, and the giraffe climbs to the star and the tower topples
// in a heap (the best part); too short or too tall, the voice says which.
// Then a red tower to match, and one taller or shorter than it.

enum TowerAsk {
  /// "Build a tower five blocks tall!"
  build,

  /// "Make yours as tall as the red one!"
  match,

  /// "Make yours one taller than the red one!"
  oneMore,

  /// "Make yours one shorter than the red one!"
  oneLess,
}

@immutable
class TowerRound {
  const TowerRound(this.ask, this.target, {this.other = 0, this.outline = false});
  final TowerAsk ask;

  /// Blocks her tower needs.
  final int target;

  /// The red tower's blocks (0 when there is none).
  final int other;

  /// A faint outline shows how tall to build (the first level).
  final bool outline;
}

/// The tallest tower a wall fits.
const int kTowerMax = 10;

/// A round at [level]: 1–5 with an outline → 3–10 from the number alone →
/// as tall as a red tower → one taller or shorter than it. Never the same
/// target twice in a row.
TowerRound towerRound(int level, Random rng, {TowerRound? last}) {
  for (var i = 0;; i++) {
    final r = _round(level, rng);
    if (last == null || r.target != last.target || i >= 20) return r;
  }
}

TowerRound _round(int level, Random rng) {
  switch (level) {
    case <= 1:
      return TowerRound(TowerAsk.build, 1 + rng.nextInt(5), outline: true);
    case 2:
      return TowerRound(TowerAsk.build, 3 + rng.nextInt(8));
    case 3:
      final other = 2 + rng.nextInt(7);
      return TowerRound(TowerAsk.match, other, other: other);
    default:
      final more = rng.nextBool();
      final other = more ? 2 + rng.nextInt(7) : 3 + rng.nextInt(7);
      return TowerRound(more ? TowerAsk.oneMore : TowerAsk.oneLess, more ? other + 1 : other - 1, other: other);
  }
}

/// Rang right the first time is a win; once wrong, helped; more, a miss.
String towerResult(int slips) => countingResult(slips);
