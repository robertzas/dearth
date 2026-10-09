import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';
import 'sight.dart';

// Word Pop (SPEC FR-TOY-03, Appendix B: early reading, at speed). Bubble
// Pop's bubbles drift up the screen, each with a word printed on it. The
// voice asks for one ("Find the word: go."), and she pops three bubbles that
// say it; each pop reads the word aloud. A bubble with another word bounces
// and reads itself, so a slip is still reading. Sight Words asks for a
// word among signs that stand still; here the same words float, and seeing
// one at a glance is the point. The ladder follows Sight Words' word lists:
// two letters (each starting differently) → three letters → four letters
// with a look-alike start → four letters, more words and quicker bubbles.
// Drawing lives in the app.

@immutable
class WordPopRound {
  const WordPopRound(this.word, this.words, {required this.bubbles, required this.speed});

  /// The word to pop.
  final String word;

  /// The words the bubbles carry, [word] among them.
  final List<String> words;

  /// Bubbles up at once.
  final int bubbles;

  /// How fast they rise, in screen heights a second.
  final double speed;
}

/// Bubbles with the word she's after, to pop in a round.
const int kWordPops = 3;

/// A round at [level] (Appendix B ladder): Sight Words' two-letter (3
/// words, 5 bubbles, slow) → three-letter (4, 6) → four-letter with a look-
/// alike start (4, 7) → four-letter (5 words, 8 bubbles, quicker). Never the
/// same word as [last].
WordPopRound wordPopRound(int level, Random rng, {String? last}) {
  final s = sightRound(min(level, 3), rng, last: last);
  final words = [...s.signs];
  if (level >= 4) {
    words.add(([for (final w in kSightFour) if (!words.contains(w)) w]..shuffle(rng)).first);
  }
  final (bubbles, speed) = switch (level) { <= 1 => (5, 1 / 14), 2 => (6, 1 / 12), 3 => (7, 1 / 11), _ => (8, 1 / 8) };
  return WordPopRound(s.word, words, bubbles: bubbles, speed: speed);
}

/// The word on the next bubble to float up: the one she's after when fewer
/// than two are up (there's always one to find), never when three are (so
/// the sky isn't all one word and she has to read), otherwise a quarter of
/// the time.
String wordPopNext(WordPopRound r, int targetsUp, Random rng) {
  if (targetsUp < 2) return r.word;
  if (targetsUp < 3 && rng.nextDouble() < 1 / 4) return r.word;
  final others = [for (final w in r.words) if (w != r.word) w];
  return others[rng.nextInt(others.length)];
}

/// Three pops among moving bubbles: a stray tap is fine; two or three
/// slips are "helped", more a miss.
String wordPopResult(int slips) => resultFor(slips, allowed: 1);
