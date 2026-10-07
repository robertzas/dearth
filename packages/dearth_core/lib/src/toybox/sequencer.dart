import 'dart:math';

import 'package:meta/meta.dart';

// Music Sequencer (SPEC FR-TOY-03, Appendix B: patterns, music). Rows of
// animals, columns of steps: a playhead loops across and every lit square
// makes its animal's short call. She lights and darkens squares and hears
// the pattern change on the next pass: a rhythm is a pattern she can see.
// There are no right answers (free play; levels unlock with visits): four
// steps and two animals → eight steps → three animals → four. Drawing and
// sound live in the app.

/// A row of the grid: the animal and its sound effect's name in the app.
enum SeqTrack {
  dog('🐶', 'dogBeat'),
  cat('🐱', 'catBeat'),
  frog('🐸', 'frogBeat'),
  chicken('🐔', 'chickenBeat');

  const SeqTrack(this.emoji, this.sound);
  final String emoji;

  /// The app's `Sfx` name for its call.
  final String sound;
}

/// A loop's shape: how many steps across and which animals.
@immutable
class SeqSize {
  const SeqSize(this.steps, this.tracks);
  final int steps;
  final List<SeqTrack> tracks;
}

/// The grid at [level]: 4 steps × dog and cat → 8 × 2 → 8 × 3 (+ frog) →
/// 8 × 4 (+ chicken).
SeqSize sequencerSize(int level) => switch (level) {
      <= 1 => const SeqSize(4, [SeqTrack.dog, SeqTrack.cat]),
      2 => const SeqSize(8, [SeqTrack.dog, SeqTrack.cat]),
      3 => const SeqSize(8, [SeqTrack.dog, SeqTrack.cat, SeqTrack.frog]),
      _ => const SeqSize(8, [SeqTrack.dog, SeqTrack.cat, SeqTrack.frog, SeqTrack.chicken]),
    };

/// Milliseconds a step: a relaxed walking beat.
const int kSeqStepMs = 330;

/// A pattern for [size]: one row per track, true where a square is lit.
/// [random] makes a fresh one (the dice): each row lit on a third to a half
/// of its steps, never empty; otherwise the starter, a plain beat that
/// plays as soon as the game opens (dog on the beat, cat between, frog and
/// chicken answering).
List<List<bool>> sequencerPattern(SeqSize size, {Random? random}) {
  final n = size.steps;
  if (random != null) {
    return [
      for (final _ in size.tracks)
        () {
          final row = List.filled(n, false);
          final lit = n ~/ 3 + random.nextInt(n ~/ 2 - n ~/ 3 + 1);
          final steps = [for (var i = 0; i < n; i++) i]..shuffle(random);
          for (final s in steps.take(max(1, lit))) {
            row[s] = true;
          }
          return row;
        }(),
    ];
  }
  bool starter(SeqTrack t, int i) => switch (t) {
        SeqTrack.dog => i % 4 == 0,
        SeqTrack.cat => i % 4 == 2,
        SeqTrack.frog => i % 8 == 3,
        SeqTrack.chicken => i % 8 == 7,
      };
  return [
    for (final t in size.tracks) [for (var i = 0; i < n; i++) starter(t, i)],
  ];
}
