import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';

// Cookie Count (SPEC FR-TOY-03, Appendix B: making a set of a given size).
// Feed the Monster's monster holds up a number and asks for that many
// cookies. She taps the jar, and a cookie lands on the plate while the voice
// says the new count; a cookie on the plate goes back to the jar. When she
// thinks it's right she rings the bell, and the monster eats them all, or
// asks for more or fewer. Counting Garden and Tallies ask "how many are
// there?"; this asks the harder question: "make this many", and know when
// to stop. The ladder: 1–5 with a spot on the plate for each cookie → 2–5
// with no spots → 5–10 → the plate starts with some cookies (too few or too
// many), so she counts what's there, then adds or takes away. Drawing lives
// in the app.

@immutable
class CookieRound {
  const CookieRound(this.want, {this.start = 0, this.spots = false});

  /// The cookies the monster asks for.
  final int want;

  /// Cookies already on the plate when the round starts.
  final int start;

  /// Whether the plate shows a spot for each cookie it wants (the youngest
  /// level, and the hint after two slips).
  final bool spots;
}

/// The plate holds two rows of five, like a ten frame.
const int kCookiePlate = 10;

/// A round at [level] (Appendix B ladder): 1–5 with spots → 2–5 → 5–10 → a
/// plate that starts one to three off. Never the same number as [last].
CookieRound cookieRound(int level, Random rng, {CookieRound? last}) {
  for (var i = 0;; i++) {
    final r = _round(level, rng);
    if (last == null || r.want != last.want || i >= 20) return r;
  }
}

CookieRound _round(int level, Random rng) {
  switch (level) {
    case <= 1:
      return CookieRound(1 + rng.nextInt(5), spots: true);
    case 2:
      return CookieRound(2 + rng.nextInt(4));
    case 3:
      return CookieRound(5 + rng.nextInt(6));
    default:
      final want = 3 + rng.nextInt(8);
      while (true) {
        final start = want + (rng.nextBool() ? 1 : -1) * (1 + rng.nextInt(3));
        if (start >= 1 && start <= kCookiePlate) return CookieRound(want, start: start);
      }
  }
}

/// A slip is ringing the bell with the wrong number: the first is
/// "helped", more a miss (counting out has one right answer, and she gets
/// to fix the plate each time).
String cookieResult(int slips) => countingResult(slips);
