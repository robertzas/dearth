import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';

// Frog Hop (SPEC FR-TOY-03, Appendix B: the number line, one more and one
// less, first adding). Lily pads in a row are a number line; a frog sits on
// one. The voice asks for a pad ("Hop to six!"), then for one more or one
// less than where the frog sits, then for a sum ("Three and two more!"):
// she taps where it lands, and it hops there a pad at a time, so the hops
// show the distance. Drawing lives in the app.

enum HopMode { find, oneMore, oneLess, add }

@immutable
class HopRound {
  const HopRound(this.mode, this.pads, this.from, this.target);
  final HopMode mode;

  /// Pads 0 to [pads] - 1 (0–5, then 0–10).
  final int pads;

  /// Where the frog sits, and the pad the voice asks for.
  final int from, target;

  /// How many pads it hops (the "two more" of an add round).
  int get hops => (target - from).abs();
}

/// A round at [level]: find a pad on 0–5 → on 0–10 → one more or one less
/// → a sum of a number and 1–3 more (up to 10). Never the same target as
/// [last], and the frog never starts on the answer.
HopRound hopRound(int level, Random rng, {int? last}) {
  for (var i = 0;; i++) {
    final r = _round(level, rng);
    if (r.target != last || i >= 20) return r;
  }
}

HopRound _round(int level, Random rng) {
  switch (level) {
    case <= 2:
      final pads = level <= 1 ? 6 : 11;
      final from = rng.nextInt(pads);
      final target = (from + 1 + rng.nextInt(pads - 1)) % pads;
      return HopRound(HopMode.find, pads, from, target);
    case 3:
      if (rng.nextBool()) {
        final from = rng.nextInt(10);
        return HopRound(HopMode.oneMore, 11, from, from + 1);
      }
      final from = 1 + rng.nextInt(10);
      return HopRound(HopMode.oneLess, 11, from, from - 1);
    default:
      final more = 1 + rng.nextInt(3);
      final from = 1 + rng.nextInt(10 - more);
      return HopRound(HopMode.add, 11, from, from + more);
  }
}

/// Every add round there can be: a start of 1–9 and 1–3 more, up to 10.
Iterable<(int, int)> get kHopSums sync* {
  for (var more = 1; more <= 3; more++) {
    for (var from = 1; from + more <= 10; from++) {
      yield (from, more);
    }
  }
}

/// Like the other pick-one games: right first time is a win, one slip is
/// helped, more is a miss.
String hopResult(int slips) => countingResult(slips);
