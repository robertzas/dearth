import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';

// Bead Slider (SPEC FR-TOY-03, Appendix B: fives and tens). Tallies'
// grouping in fives, now with beads she moves: a rekenrek, a counting
// rack of rows with five red and five white beads. She slides beads
// across ("Show seven!") and the bell checks; the voice names the
// structure — "Five and two make seven!", "Ten and four make
// fourteen!" — the way the rack is read. At the top the beads are
// already across and she reads them.

@immutable
class BeadRound {
  const BeadRound(this.want, {this.rows = 1, this.read = false, this.choices = const []});

  /// How many beads should be across — or, in read mode, are.
  final int want;

  /// Rack rows: 1, or 2 when the count goes past ten.
  final int rows;

  /// Level 4: the beads start across; she picks the number.
  final bool read;

  /// Read mode: three distinct numbers, [want] among them, all in 1–20.
  final List<int> choices;
}

/// A round at [level] (the ladder above); the want never repeats [last]'s.
BeadRound beadRound(int level, Random rng, {BeadRound? last}) {
  for (var i = 0;; i++) {
    final r = _round(level, rng);
    if (last == null || r.want != last.want || i >= 20) return r;
  }
}

BeadRound _round(int level, Random rng) {
  switch (level) {
    case <= 1:
      return BeadRound(1 + rng.nextInt(5));
    case 2:
      return BeadRound(3 + rng.nextInt(8));
    case 3:
      return BeadRound(11 + rng.nextInt(10), rows: 2);
    default:
      final want = 1 + rng.nextInt(20);
      return BeadRound(want, rows: want > 10 ? 2 : 1, read: true, choices: _choices(want, rng));
  }
}

/// Three distinct numbers in 1–20 with [want] among them: its neighbors
/// ±1, then ±5 and ±10 where in range (the rekenrek's own structure), the
/// rest of the range as a fallback.
List<int> _choices(int want, Random rng) {
  final near = [for (final d in [-1, 1, -5, 5, -10, 10]) if (want + d >= 1 && want + d <= 20) want + d]..shuffle(rng);
  final far = [for (var n = 1; n <= 20; n++) if (n != want) n]..shuffle(rng);
  final out = <int>[];
  for (var guard = 0; out.length < 2 && guard < 100; guard++) {
    final n = near.isNotEmpty ? near.removeLast() : far.removeLast();
    if (n != want && !out.contains(n)) out.add(n);
  }
  return ([want, ...out]..shuffle(rng));
}

/// A wrong ring is a slip: the first is "helped", more a miss.
String beadResult(int slips) => countingResult(slips);
