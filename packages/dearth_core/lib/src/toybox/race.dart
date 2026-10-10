import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';

// Animal Race (SPEC FR-TOY-03, Appendix B: ordinal words). Who Has More?'s
// comparing and lining up, as a race: three animals (then five) cross
// their lanes' finish line in order and coast to a stop, and she answers
// "Who came second?" — or ribbons them all, first to fifth, at the top.
// A slip is still ordinal practice: a wrong animal says its own place.

/// (emoji, name): racers, one per lane. They face left on Noto Color Emoji
/// and the race runs right to left (check them in the shots, §2.5 step 5).
const List<(String, String)> kRacers = [
  ('🐢', 'turtle'),
  ('🐇', 'rabbit'),
  ('🐌', 'snail'),
  ('🐎', 'horse'),
  ('🐕', 'dog'),
  ('🐈', 'cat'),
  ('🐖', 'pig'),
  ('🐄', 'cow'),
  ('🐓', 'rooster'),
  ('🦆', 'duck'),
];

@immutable
class RaceRound {
  const RaceRound(this.racers, this.places, this.asks);

  /// Racer indexes into [kRacers], one per lane, top to bottom.
  final List<int> racers;

  /// places[lane] = 1-based finishing place, a permutation.
  final List<int> places;

  /// The places asked, in order; 0 means "last". Level 4: [1, 2, 3, 4, 5].
  final List<int> asks;

  int get lanes => racers.length;
}

/// A round at [level] (the ladder above), never with the same first ask
/// and winner as [last]'s.
RaceRound raceRound(int level, Random rng, {RaceRound? last}) {
  for (var i = 0;; i++) {
    final r = _round(level, rng);
    final a = r, b = last;
    if (b == null || a.asks.first != b.asks.first || a.racers[a.places.indexOf(1)] != b.racers[b.places.indexOf(1)] || i >= 20) return r;
  }
}

RaceRound _round(int level, Random rng) {
  final lanes = level >= 3 ? 5 : 3;
  final racers = [for (var i = 0; i < kRacers.length; i++) i]..shuffle(rng);
  racers.length = lanes;
  final places = [for (var l = 1; l <= lanes; l++) l]..shuffle(rng);
  late List<int> asks;
  switch (level) {
    case <= 1:
      asks = [rng.nextBool() ? 1 : 0];
    case 2:
      asks = [1 + rng.nextInt(3)];
    case 3:
      asks = [rng.nextBool() ? 0 : 1 + rng.nextInt(5)];
    default:
      asks = [1, 2, 3, 4, 5];
  }
  return RaceRound(racers, places, asks);
}

/// A wrong pick is a slip: the first is "helped", more a miss.
String raceResult(int slips) => countingResult(slips);

/// "last", "1st", "2nd", "3rd", "4th", "5th" — labels.
String ordinal(int place) => const ['last', '1st', '2nd', '3rd', '4th', '5th'][place];

/// "last", "first", "second", "third", "fourth", "fifth" — spoken words.
String ordinalWord(int place) => const ['last', 'first', 'second', 'third', 'fourth', 'fifth'][place];
