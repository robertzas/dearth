import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';

// Dice Dash (SPEC FR-TOY-03, Appendix B: dice patterns, counting on,
// adding). A board game with no one to lose to: she rolls a big die, sees
// how many dots (the pattern, then the count), and hops her buddy along a
// winding path to the birthday cake, one counted square at a time.
// Ladders lift her up, slides whisk her down: the surprise is the fun.
// Later she says where she'll land before she hops (counting on in her
// head), then two dice add up.

/// How she moves after a roll.
enum DiceMode {
  /// Tap the glowing next square, once per dot, each hop counted aloud.
  hop,

  /// Tap the square she'll land on; the buddy then hops there counting.
  landOn,
}

@immutable
class DiceBoard {
  const DiceBoard(this.squares, this.jumps, {required this.mode, required this.dice, required this.faces});

  /// Squares on the path: 0 is the start, the last one is the cake.
  final int squares;

  /// Ladders (up) and slides (down), by the square they start on.
  final Map<int, int> jumps;
  final DiceMode mode;

  /// One die, or two whose dots add up.
  final int dice;

  /// The highest face of each die: 3 (dots she can see at a glance) or 6.
  final int faces;

  int get cake => squares - 1;

  /// Where [steps] hops from [from] land (the cake stops her: no exact roll
  /// needed to finish).
  int landing(int from, int steps) => min(from + steps, cake);

  /// Where she ends up once a ladder or slide at [square] has moved her.
  int afterJump(int square) => jumps[square] ?? square;
}

/// The board at [level]: 12 squares and a 1–3 die → 18 with a 1–6 die and
/// ladders and slides → the same, saying where she'll land → two 1–3 dice.
DiceBoard diceBoard(int level, Random rng) {
  final (squares, mode, dice, faces, ladders, slides) = switch (level) {
    <= 1 => (12, DiceMode.hop, 1, 3, 0, 0),
    2 => (18, DiceMode.hop, 1, 6, 2, 1),
    3 => (18, DiceMode.landOn, 1, 6, 2, 1),
    _ => (20, DiceMode.hop, 2, 3, 2, 2),
  };
  // Ladders climb straight up a row and slides drop straight down one, as
  // on a real board (the track winds in rows of [kDiceRow]): never from or
  // onto the start, the cake or another ladder or slide.
  final jumps = <int, int>{};
  bool free(int s) => s > 0 && s < squares - 1 && !jumps.containsKey(s) && !jumps.containsValue(s);
  var tries = 0;
  while (jumps.length < ladders + slides && tries++ < 500) {
    final ladder = jumps.length < ladders;
    final from = 1 + rng.nextInt(squares - 2);
    final to = ladder ? diceAbove(from) : diceBelow(from);
    if (to == null || !free(from) || !free(to) || (to - from).abs() < 2) continue;
    jumps[from] = to;
  }
  return DiceBoard(squares, jumps, mode: mode, dice: dice, faces: faces);
}

/// Squares in a row of the winding track.
const int kDiceRow = 6;

int _square(int row, int col) => row * kDiceRow + (row.isEven ? col : kDiceRow - 1 - col);

/// The square straight above [i] (the next row up; past the end of a short
/// track it's beyond the cake, which a board never uses).
int diceAbove(int i) {
  final row = i ~/ kDiceRow, k = i % kDiceRow, col = row.isEven ? k : kDiceRow - 1 - k;
  return _square(row + 1, col);
}

/// The square straight below [i], or null on the bottom row.
int? diceBelow(int i) {
  final row = i ~/ kDiceRow, k = i % kDiceRow, col = row.isEven ? k : kDiceRow - 1 - k;
  return row == 0 ? null : _square(row - 1, col);
}

/// A roll: one or two dice, each 1…[DiceBoard.faces].
List<int> diceRoll(DiceBoard board, Random rng) => [for (var i = 0; i < board.dice; i++) 1 + rng.nextInt(board.faces)];

/// A whole board: a slip (a wrong square) now and then is fine.
String diceResult(int slips) => resultFor(slips, allowed: 2);
