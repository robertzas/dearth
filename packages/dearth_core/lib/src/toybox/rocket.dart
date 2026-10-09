import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';

// Rocket Countdown (SPEC FR-TOY-03, Appendix B: number order, counting
// back). A rocket waits on its pad under a night sky of numbered stars.
// "Count down from ten!": she taps the stars in order, ten, nine, eight…
// and each one says its number, lights up the rocket's fuel gauge and
// plays a note a step higher; at one the voice says "Zero! Blast off!" and
// the rocket launches. Dot-to-Dot counts up; this counts down, the order
// she hears every time something is about to happen. The ladder: from five
// → from ten → from a start between eleven and fifteen → from twenty.
// Drawing lives in the app.

@immutable
class RocketRound {
  const RocketRound(this.start);

  /// The number she counts down from, to one.
  final int start;

  /// The stars in the order she taps them: [start] down to one.
  List<int> get countdown => [for (var n = start; n >= 1; n--) n];
}

/// Where a countdown can start: what the voice can say "Count down from…"
/// for.
const List<int> kRocketStarts = [5, 10, 11, 12, 13, 14, 15, 20];

/// A round at [level] (Appendix B ladder): from five → from ten → from 11–15
/// → from twenty. Not the same start as [last] where the level allows.
RocketRound rocketRound(int level, Random rng, {RocketRound? last}) => switch (level) {
      <= 1 => const RocketRound(5),
      2 => const RocketRound(10),
      3 => RocketRound(([for (var n = 11; n <= 15; n++) if (n != last?.start) n]..shuffle(rng)).first),
      _ => const RocketRound(20),
    };

/// One slip in a short countdown is fine, two in a long one; a lot more is
/// a miss.
String rocketResult(RocketRound r, int slips) => resultFor(slips, allowed: r.start <= 10 ? 1 : 2);
