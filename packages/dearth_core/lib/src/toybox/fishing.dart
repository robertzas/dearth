import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';

// Number Fishing (SPEC FR-TOY-03, Appendix B: reading numerals to twenty,
// comparing, number pairs). Fish with numbers on their sides swim back and
// forth across a pond, a lane each. The voice calls one ("Find the number
// seven.") and she taps it: it leaps out of the water into her bucket.
// Later it asks for the biggest number, then for two fish that make five.
// A moving target asks her to read a numeral at a glance, the step after
// Number Tracing's writing it. The ladder: 1–5 among three → 6–20 among
// four, with a decoy that shares a digit (12 against 2) → the biggest of
// three up to twenty → two of four that make five (exactly one pair can).
// Drawing lives in the app.

enum FishAsk { find, biggest, makeFive }

@immutable
class FishRound {
  const FishRound(this.ask, this.fish, {this.target});
  final FishAsk ask;

  /// The numbers on the fish, a lane each, top to bottom; never two the
  /// same.
  final List<int> fish;

  /// The number to find ([FishAsk.find]).
  final int? target;

  /// The fish she catches to finish, by number.
  Set<int> get catches => switch (ask) {
        FishAsk.find => {target!},
        FishAsk.biggest => {fish.reduce(max)},
        FishAsk.makeFive => {for (final a in fish) if (fish.contains(5 - a)) a},
      };
}

/// The pairs that make five, smaller first.
const List<(int, int)> kFivePairs = [(0, 5), (1, 4), (2, 3)];

/// A round at [level] (Appendix B ladder). Not the same catch as [last].
FishRound fishRound(int level, Random rng, {FishRound? last}) {
  for (var i = 0;; i++) {
    final r = _round(level, rng);
    if (last == null || r.catches.join() != last.catches.join() || i >= 20) return r;
  }
}

FishRound _round(int level, Random rng) {
  switch (level) {
    case <= 1:
      final fish = ([1, 2, 3, 4, 5]..shuffle(rng)).take(3).toList();
      return FishRound(FishAsk.find, fish, target: fish[rng.nextInt(3)]);
    case 2:
      final target = 6 + rng.nextInt(15);
      // A decoy that shares a digit: 12 against 2 or 21-ish; 7 against 17.
      final twin = target >= 10 ? target % 10 : target + 10;
      final fish = <int>{target, if (twin >= 1 && twin <= 20) twin};
      while (fish.length < 4) {
        fish.add(1 + rng.nextInt(20));
      }
      return FishRound(FishAsk.find, fish.toList()..shuffle(rng), target: target);
    case 3:
      while (true) {
        final fish = <int>{};
        while (fish.length < 3) {
          fish.add(1 + rng.nextInt(20));
        }
        final sorted = fish.toList()..sort();
        if (sorted[2] - sorted[1] < 2) continue;
        return FishRound(FishAsk.biggest, fish.toList()..shuffle(rng));
      }
    default:
      final pairs = [...kFivePairs]..shuffle(rng);
      final (a, b) = pairs.first;
      // One from each other pair: neither finds its partner in the pond.
      final fish = [a, b, for (final (c, d) in pairs.skip(1)) rng.nextBool() ? c : d]..shuffle(rng);
      return FishRound(FishAsk.makeFive, fish);
  }
}

/// One fish to catch: right first time is a win, one slip helped. Two to
/// catch: one slip is still a win.
String fishResult(FishRound r, int slips) => r.ask == FishAsk.makeFive ? resultFor(slips, allowed: 1) : countingResult(slips);
