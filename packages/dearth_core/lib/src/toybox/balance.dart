import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';

// Banana Balance (SPEC FR-TOY-03, Appendix B: comparing quantities). A
// see-saw with a monkey on the middle and a load on each end: "Which side
// has more?" The side she picks is pressed down, and a see-saw can't lie:
// the heavier side goes down. The ladder moves from what she sees to what
// the numbers say: piles far apart (5 and 2) → piles a banana apart → a
// pile against a numeral → two numerals. Drawing lives in the app.

/// What sits on one end of the see-saw.
@immutable
class BalanceSide {
  const BalanceSide(this.count, {required this.numeral});

  final int count;

  /// A number card instead of a pile of bananas.
  final bool numeral;
}

@immutable
class BalanceRound {
  const BalanceRound(this.left, this.right);
  final BalanceSide left, right;

  /// The side with more: true for the left.
  bool get leftMore => left.count > right.count;
  int get more => max(left.count, right.count);
  int get fewer => min(left.count, right.count);
}

/// A round at [level]: two piles of 1–5 at least two apart → two piles of
/// 1–10, sometimes only one apart → a pile against a numeral → two
/// numerals. Never a tie, the bigger side left or right by chance, and not
/// the same pair as [last].
BalanceRound balanceRound(int level, Random rng, {BalanceRound? last}) {
  for (var i = 0;; i++) {
    final r = _round(level, rng);
    final same = last != null && r.more == last.more && r.fewer == last.fewer;
    if (!same || i >= 20) return r;
  }
}

BalanceRound _round(int level, Random rng) {
  final top = level <= 1 ? 5 : 10;
  final gap = level <= 1 ? 2 : 1;
  late int a, b;
  do {
    a = 1 + rng.nextInt(top);
    b = 1 + rng.nextInt(top);
  } while ((a - b).abs() < gap);
  // The pile against a numeral: either side may be the card.
  final numeralLeft = level == 3 ? rng.nextBool() : level >= 4;
  final numeralRight = level == 3 ? !numeralLeft : level >= 4;
  return BalanceRound(BalanceSide(a, numeral: numeralLeft), BalanceSide(b, numeral: numeralRight));
}

/// Every "more than" pair the voice can say: 1 ≤ fewer < more ≤ 10.
Iterable<(int, int)> get kBalancePairs sync* {
  for (var more = 2; more <= 10; more++) {
    for (var fewer = 1; fewer < more; fewer++) {
      yield (more, fewer);
    }
  }
}

/// Two sides: right first time is a win; a slip is "helped".
String balanceResult(int slips) => countingResult(slips);
