import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';

// Alphabet Train (SPEC FR-TOY-03, Appendix B: alphabet order). A train
// pulls in with a letter in each carriage, in ABC order, and a carriage
// with nothing in it. The voice reads the letters as the carriages stop
// and asks "What comes next?" (later "Which letter is missing?"); she taps
// the letter block that belongs there and it flies into the carriage. Once
// the train is whole the voice reads it front to back, one carriage at a
// time, and it chugs away. Dot-to-Dot's letter pictures walk the alphabet
// from A; this asks where a letter sits from anywhere in it. The ladder:
// the next of three capitals → a missing one in four → small letters, five
// carriages → two gaps. Drawing lives in the app.

enum TrainAsk { next, missing }

@immutable
class TrainRound {
  const TrainRound(this.letters, this.gaps, this.choices, {required this.small});

  /// The carriages' letters in order, upper case, the gaps' included.
  final List<String> letters;

  /// The empty carriages, left to right.
  final List<int> gaps;

  /// The blocks on the platform, upper case: every gap's letter and some
  /// near it in the alphabet.
  final List<String> choices;

  /// Whether the letters are small.
  final bool small;

  TrainAsk get ask => gaps.length == 1 && gaps.single == letters.length - 1 ? TrainAsk.next : TrainAsk.missing;
}

const String kAlphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

/// A round at [level] (Appendix B ladder): three capitals, the third
/// missing (3 blocks) → four capitals, one of the last three missing (3) →
/// five small letters, one missing (4) → five small letters, two missing
/// (4). Not starting at the same letter as [last].
TrainRound trainRound(int level, Random rng, {TrainRound? last}) {
  for (var i = 0;; i++) {
    final r = _round(level, rng);
    if (last == null || r.letters.first != last.letters.first || i >= 20) return r;
  }
}

TrainRound _round(int level, Random rng) {
  final (n, blocks, small) = switch (level) { <= 1 => (3, 3, false), 2 => (4, 3, false), 3 => (5, 4, true), _ => (5, 4, true) };
  final start = rng.nextInt(kAlphabet.length - n + 1);
  final letters = kAlphabet.substring(start, start + n).split('');
  final List<int> gaps;
  switch (level) {
    case <= 1:
      gaps = [n - 1];
    case 2 || 3:
      gaps = [1 + rng.nextInt(n - 1)];
    default:
      final picks = ([for (var g = 1; g < n; g++) g]..shuffle(rng)).take(2).toList()..sort();
      gaps = picks;
  }
  // Decoys: the letters nearest the gap that aren't on the train (the
  // confusions that matter: one before it, one after). At the ends of the
  // alphabet they all come from one side, further off.
  final near = <String>[];
  for (final d in [for (var k = 1; k < kAlphabet.length; k++) ...[k, -k]]) {
    for (final g in gaps) {
      final k = start + g + d;
      if (k < 0 || k >= kAlphabet.length) continue;
      final c = kAlphabet[k];
      if (!letters.contains(c) && !near.contains(c)) near.add(c);
    }
  }
  final choices = [for (final g in gaps) letters[g], ...near.take(blocks - gaps.length)]..shuffle(rng);
  return TrainRound(letters, gaps, choices, small: small);
}

/// Three blocks for one gap: right first time is a win, one slip helped.
/// Two gaps take two picks, so one slip is still a win.
String trainResult(TrainRound r, int slips) => r.gaps.length > 1 ? resultFor(slips, allowed: 1) : countingResult(slips);
