import 'dart:math';

import 'package:meta/meta.dart';

// Freeze Dance (SPEC FR-TOY-03, Appendix B: movement, self-regulation).
// Music plays and a buddy dances; the music stops and the voice says
// "Freeze!": she freezes, like the buddy in its block of ice, until
// "Dance!". Stopping on a signal and starting again is the self-control
// the game practices; the screen can't see her, so nothing is scored, and
// the game is free play (levels unlock with visits). The ladder: long
// dances and steady three-second freezes → dances and pauses of uneven
// length, so she has to listen → animal moves ("Dance like a frog!").
// Drawing and music live in the app.

/// An animal move for the top level: the buddy becomes it.
enum FreezeAnimal {
  frog('🐸', 'Dance like a frog!'),
  bunny('🐇', 'Hop like a bunny!'),
  snake('🐍', 'Wiggle like a snake!'),
  elephant('🐘', 'Stomp like an elephant!'),
  bird('🐦', 'Flap like a bird!'),
  fish('🐟', 'Swim like a fish!');

  const FreezeAnimal(this.emoji, this.line);
  final String emoji;

  /// What the voice says when the music starts.
  final String line;
}

/// One stretch of dancing and the freeze after it.
@immutable
class FreezeTurn {
  const FreezeTurn(this.danceMs, this.freezeMs, {this.animal});
  final int danceMs, freezeMs;

  /// Top level: how to dance this time.
  final FreezeAnimal? animal;
}

/// A song at [level]: four long dances with three-second freezes → five
/// uneven dances (4–9 s) and freezes (1.5–5 s) → five dances as animals,
/// each a different one. The last turn's freeze ends the song.
List<FreezeTurn> freezeSong(int level, Random rng) {
  int between(int lo, int hi) => lo + rng.nextInt(hi - lo + 1);
  switch (level) {
    case <= 1:
      return [for (var i = 0; i < 4; i++) FreezeTurn(between(8000, 10000), 3000)];
    case 2:
      return [for (var i = 0; i < 5; i++) FreezeTurn(between(4000, 9000), between(1500, 5000))];
    default:
      final animals = [...FreezeAnimal.values]..shuffle(rng);
      return [for (var i = 0; i < 5; i++) FreezeTurn(between(6000, 9000), 3000, animal: animals[i])];
  }
}

/// The dance tune: a bar of eighth notes in C major pentatonic (MIDI;
/// null rests) that can't sound wrong, looped under the drums.
const List<int?> kFreezeTune = [72, null, 76, 79, 81, 79, 76, null, 74, null, 76, 72, 69, 72, 74, null];
