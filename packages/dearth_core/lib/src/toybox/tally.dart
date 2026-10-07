import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';

// Tallies (SPEC FR-TOY-03, Appendix B: keeping count). Bunnies hop up to a
// chalkboard one at a time, and each waits for its mark: she taps, a chalk
// line appears and the voice says the count; the fifth line crosses the
// four before it. One tap, one bunny, one mark is the whole lesson (one-to-
// one counting), and the crossed bundle of five is the first grouping she
// meets. The ladder: one to five bunnies → five already on the board, then
// counting on to six–ten → read a finished tally and pick its numeral.
// Drawing lives in the app.

enum TallyMode { mark, countOn, read }

@immutable
class TallyRound {
  const TallyRound(this.mode, {this.start = 0, this.bunnies = 0, this.choices = const []});
  final TallyMode mode;

  /// Marks already on the board when the round starts (five when counting
  /// on; the whole tally when reading).
  final int start;

  /// Bunnies that hop up, one mark each.
  final int bunnies;

  /// Read: the numerals to choose from, the answer among them.
  final List<int> choices;

  int get total => start + bunnies;
}

/// The most marks a board holds: two bundles.
const int kTallyMax = 10;

/// A round at [level] (Appendix B ladder): 1–5 bunnies → five on the board
/// and 1–5 more (six to ten) → a tally of 2–10 to read among three
/// numerals. Not the same total as [last].
TallyRound tallyRound(int level, Random rng, {TallyRound? last}) {
  for (var i = 0;; i++) {
    final r = _round(level, rng);
    if (last == null || r.total != last.total || i >= 20) return r;
  }
}

TallyRound _round(int level, Random rng) {
  switch (level) {
    case <= 1:
      return TallyRound(TallyMode.mark, bunnies: 1 + rng.nextInt(5));
    case 2:
      return TallyRound(TallyMode.countOn, start: 5, bunnies: 1 + rng.nextInt(5));
    default:
      final n = 2 + rng.nextInt(kTallyMax - 1);
      // Near misses: one or two away, so she has to read the tally, not guess its size.
      final near = <int>{};
      for (final d in [...const [-1, 1, -2, 2]]..shuffle(rng)) {
        final c = n + d;
        if (c >= 1 && c <= kTallyMax && near.length < 2) near.add(c);
      }
      return TallyRound(TallyMode.read, start: n, choices: [n, ...near]..shuffle(rng));
  }
}

/// [n] marks as tally bundles: fives, then what's left ("7" → [5, 2]).
List<int> tallyGroups(int n) => [for (var left = n; left > 0; left -= 5) min(5, left)];

/// The numbers the voice says counting a finished tally back: one by one
/// for the youngest, and by the bundle ("Five", then on) once bundles mean
/// five ("7" → [5, 6, 7]). Each entry lights that many marks.
List<int> tallyCountBack(int n, {required bool byFives}) => byFives ? [for (var k = 5; k <= n; k += 5) k, for (var k = (n ~/ 5) * 5 + 1; k <= n; k++) k] : [for (var k = 1; k <= n; k++) k];

/// Marking: an extra tap (a mark with no bunny) is the slip, and one is
/// fine. Reading: three numerals, so a slip is "helped".
String tallyResult(TallyRound r, int slips) => r.mode == TallyMode.read ? countingResult(slips) : resultFor(slips, allowed: 1);
