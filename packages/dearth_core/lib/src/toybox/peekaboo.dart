import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';

// Peekaboo Pals (SPEC FR-TOY-03, Appendix B: parts of a number, the
// missing part). Friends play in the meadow, counted out loud as they
// come; then some run to hide behind the bush, giggling. She sees how
// many are left: how many are hiding? Then "Peekaboo!" and the hiders
// pop out, counted. Five is two and three: the part-whole idea that
// adding and taking away grow from, in the oldest game there is. At the
// top the friends are only a number on a sign, and some were already
// hiding when she looked.

@immutable
class PeekabooRound {
  const PeekabooRound(this.friend, this.total, this.hiding, this.choices, {this.sign = false});

  /// The friends' picture (one kind a round).
  final String friend;
  final int total;
  final int hiding;

  /// Numbers to pick from, small to big.
  final List<int> choices;

  /// The total is only told (a number on a sign); she never sees them all.
  final bool sign;

  int get showing => total - hiding;
}

/// Who plays: friends that read clearly as one of many.
const List<String> kPeekabooFriends = ['🐰', '🐥', '🐶', '🐱', '🐼', '🐸', '🐭', '🐻'];

/// A round at [level]: 2–3 friends → 4–5 → 6–10 → a total on a sign.
/// At least one always hides; all of them now and then (none left!).
/// Never the same total and hiding twice in a row.
PeekabooRound peekabooRound(int level, Random rng, {PeekabooRound? last}) {
  for (var i = 0;; i++) {
    final r = _round(level, rng);
    if (last == null || (r.total, r.hiding) != (last.total, last.hiding) || i >= 20) return r;
  }
}

PeekabooRound _round(int level, Random rng) {
  final (lo, hi, sign) = switch (level) { <= 1 => (2, 3, false), 2 => (4, 5, false), 3 => (6, 10, false), _ => (3, 8, true) };
  final total = lo + rng.nextInt(hi - lo + 1);
  // Mostly some of them, sometimes all: "they're all hiding!" is funny.
  final hiding = rng.nextInt(6) == 0 && !sign ? total : 1 + rng.nextInt(total - 1);
  // At least one always hides, so 0 is never offered.
  final n = min(3, total);
  final key = {for (var k = 1; k <= total; k++) if (k != hiding) k: (k - hiding).abs() * 10 + rng.nextInt(10)};
  final others = key.keys.toList()..sort((a, b) => key[a]!.compareTo(key[b]!));
  final choices = [hiding, ...others.take(n - 1)]..sort();
  return PeekabooRound(kPeekabooFriends[rng.nextInt(kPeekabooFriends.length)], total, hiding, choices, sign: sign);
}

/// Right the first time is a win.
String peekabooResult(int slips) => countingResult(slips);
