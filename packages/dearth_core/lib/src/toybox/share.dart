import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';

// Fair Share (SPEC FR-TOY-03, Appendix B: sharing equally). Two or three
// of Feed the Monster's monsters, empty plates, and a tray of cupcakes:
// "Share the cupcakes so everyone has the same!" A tap on a plate gives
// it one (and says its count), a tap on a cupcake takes it back, and the
// bell checks. Fair: everyone eats, "Three each! Fair and square!".
// Unequal: the one with fewest complains ("Hey! I have fewer!"); equal
// but the tray still holds more than the leftover: "There are more to
// share!" — a slip either way, and the cupcakes stay to fix. The top
// level always leaves one over: "One left over, for later!"

@immutable
class ShareRound {
  const ShareRound(this.monsters, this.treats);

  /// The monsters sharing (and so the plates).
  final int monsters;

  /// Cupcakes on the tray at the start.
  final int treats;

  /// A fair share for each monster.
  int get each => treats ~/ monsters;

  /// What fair sharing leaves on the tray.
  int get left => treats % monsters;
}

/// What the bell finds.
enum ShareCheck { fair, unequal, moreToShare }

/// A round at [level] (the ladder above), never the same (monsters,
/// treats) as [last]'s.
ShareRound shareRound(int level, Random rng, {ShareRound? last}) {
  for (var i = 0;; i++) {
    final r = _round(level, rng);
    if (last == null || (r.monsters, r.treats) != (last.monsters, last.treats) || i >= 20) return r;
  }
}

ShareRound _round(int level, Random rng) {
  switch (level) {
    case <= 1:
      return ShareRound(2, [2, 4, 6][rng.nextInt(3)]);
    case 2:
      return ShareRound(2, [4, 6, 8, 10][rng.nextInt(4)]);
    case 3:
      return ShareRound(3, [3, 6, 9, 12][rng.nextInt(4)]);
    default:
      return rng.nextBool() ? ShareRound(2, [5, 7, 9][rng.nextInt(3)]) : ShareRound(3, [4, 7, 10][rng.nextInt(3)]);
  }
}

/// Pure: what the bell finds with [plates] served and [tray] cupcakes
/// left. Unequal plates come first (the one with fewest complains), then
/// a tray that still holds more than the round's leftover.
ShareCheck shareCheck(ShareRound r, List<int> plates, int tray) {
  if (plates.toSet().length > 1) return ShareCheck.unequal;
  if (tray > r.left) return ShareCheck.moreToShare;
  return ShareCheck.fair;
}

/// The monster who complains: the first plate holding the fewest.
int fewestPlate(List<int> plates) {
  var low = 0;
  for (var i = 1; i < plates.length; i++) {
    if (plates[i] < plates[low]) low = i;
  }
  return low;
}

/// A wrong ring is a slip: the first is "helped", more a miss.
String shareResult(int slips) => countingResult(slips);
