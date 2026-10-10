import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';

// Creature Count (SPEC FR-TOY-03, Appendix B: counting out a set). A bare
// creature asks for parts: "Give it three eyes!" She adds them one at a
// time (each says the count), takes extras off, and makes it dance to
// check. Build-a-Creature's creatures and Cookie Count's "make this many":
// she must stop at the number. The ladder: one part 1–3 with outlines →
// 1–5 → two parts at once → the numeral alone. Drawing lives in the app.

enum CountPart { eyes, legs, horns, spots }

/// The most of each part a creature can wear (what fits on its body).
const Map<CountPart, int> kCountPartMax = {CountPart.eyes: 6, CountPart.legs: 8, CountPart.horns: 6, CountPart.spots: 9};

/// (one, many): "eye", "eyes".
const Map<CountPart, (String, String)> kCountPartWords = {
  CountPart.eyes: ('eye', 'eyes'),
  CountPart.legs: ('leg', 'legs'),
  CountPart.horns: ('horn', 'horns'),
  CountPart.spots: ('spot', 'spots'),
};

/// "3 eyes", "1 eye" (labels).
String countPartLabel(CountPart p, int n) => '$n ${n == 1 ? kCountPartWords[p]!.$1 : kCountPartWords[p]!.$2}';

/// The bodies whose edges the parts fit: Build-a-Creature's round, egg and
/// square bodies (the spiky and fluffy ones have uneven tops).
const List<int> kCountBodies = [0, 1, 3];

@immutable
class CountAsk {
  const CountAsk(this.part, this.n);
  final CountPart part;
  final int n;
}

@immutable
class CreatureCountRound {
  const CreatureCountRound(this.asks, {required this.body, required this.color, this.numeral = false, this.guides = false});

  /// One part, or two different parts (level 3), in the order asked.
  final List<CountAsk> asks;

  /// One of [kCountBodies].
  final int body;

  /// An index into the app's `kCreatureColors` (0–7).
  final int color;

  /// The voice says "this many": the numeral in the pill is the question.
  final bool numeral;

  /// Outlines show where the parts go from the start (level 1).
  final bool guides;
}

/// A round at [level] (the ladder above), never with the same first ask
/// as [last].
CreatureCountRound creatureCountRound(int level, Random rng, {CreatureCountRound? last}) {
  for (var i = 0;; i++) {
    final r = _round(level, rng);
    final a = r.asks.first, b = last?.asks.first;
    if (b == null || a.part != b.part || a.n != b.n || i >= 20) return r;
  }
}

CreatureCountRound _round(int level, Random rng) {
  final body = kCountBodies[rng.nextInt(kCountBodies.length)];
  final color = rng.nextInt(8);
  CountPart part() => CountPart.values[rng.nextInt(CountPart.values.length)];
  switch (level) {
    case <= 1:
      return CreatureCountRound([CountAsk(part(), 1 + rng.nextInt(3))], body: body, color: color, guides: true);
    case 2:
      final p = part();
      return CreatureCountRound([CountAsk(p, 1 + rng.nextInt(min(5, kCountPartMax[p]!)))], body: body, color: color);
    case 3:
      final p = part();
      var q = part();
      while (q == p) {
        q = part();
      }
      return CreatureCountRound([CountAsk(p, 1 + rng.nextInt(4)), CountAsk(q, 1 + rng.nextInt(4))], body: body, color: color);
    default:
      final p = part();
      return CreatureCountRound([CountAsk(p, 3 + rng.nextInt(kCountPartMax[p]! - 2))], body: body, color: color, numeral: true);
  }
}

/// A slip is a dance with the wrong count: the first is "helped", more a
/// miss (one right answer, and she fixes the creature each time).
String creatureCountResult(int slips) => countingResult(slips);
