import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';

// Sight Words (SPEC FR-TOY-03, Appendix B: early reading, whole words).
// Words on street signs, the way a child first reads: STOP, the bus's
// name, a label. The voice asks for a word ("Find the word go."), she taps
// the sign that says it, and a little bus drives along the road and stops
// under it. A wrong sign reads itself out, so a slip is still reading. The
// words are the commonest in early books (the Dolch pre-primer and primer
// lists): the ones worth knowing at a glance because sounding them out
// doesn't work ("the", "said"). Drawing lives in the app.

/// Two letters: the first words she meets.
const List<String> kSightTwo = ['a', 'I', 'go', 'no', 'up', 'me', 'my', 'is', 'in', 'it', 'to', 'we', 'on', 'at'];

/// Three letters.
const List<String> kSightThree = ['the', 'and', 'can', 'see', 'you', 'big', 'red', 'run', 'not', 'yes', 'for', 'are', 'she', 'was', 'get', 'fun'];

/// Four letters, where a glance at the first letter isn't enough.
const List<String> kSightFour = ['here', 'with', 'look', 'play', 'come', 'jump', 'said', 'help', 'like', 'down', 'blue', 'have', 'this', 'what', 'went', 'from'];

/// Two-word labels: a sight word and a picture word.
const List<String> kSightLabels = ['the bus', 'the sun', 'a bus', 'a cat', 'my cat', 'my dog', 'big dog', 'red bus', 'I can', 'I see', 'go up', 'look up', 'come here', 'look here'];

/// Every word or label the game asks for.
List<String> get kSightWords => [...kSightTwo, ...kSightThree, ...kSightFour, ...kSightLabels];

@immutable
class SightRound {
  const SightRound(this.word, this.signs);

  /// The word (or two) to find.
  final String word;

  /// The signs, left to right, [word] among them.
  final List<String> signs;
}

/// A round at [level]: one of three two-letter words, each starting with a
/// different letter (the first letter is enough, at first) → one of four
/// three-letter words → one of four four-letter words, one of them starting
/// like the answer (here and have: look past the first letter) → one of four
/// labels, the others sharing a word with it (the bus, the sun, a bus).
/// Never the same word as [last].
SightRound sightRound(int level, Random rng, {String? last}) {
  final (pool, n) = switch (level) {
    <= 1 => (kSightTwo, 3),
    2 => (kSightThree, 4),
    3 => (kSightFour, 4),
    _ => (kSightLabels, 4),
  };
  final word = ([for (final w in pool) if (w != last) w]..shuffle(rng)).first;
  final others = [for (final w in pool) if (w != word) w]..shuffle(rng);
  final picks = <String>[];
  bool sameStart(String a, String b) => a[0].toLowerCase() == b[0].toLowerCase();
  bool sharesWord(String a, String b) => a.split(' ').any(b.split(' ').contains);
  switch (level) {
    case <= 1:
      for (final w in others) {
        if (picks.length == n - 1) break;
        if (![word, ...picks].any((p) => sameStart(p, w))) picks.add(w);
      }
    case 3:
      // A look-alike first, when there is one, then any.
      picks.addAll(others.where((w) => sameStart(w, word)).take(1));
      picks.addAll(others.where((w) => !picks.contains(w)).take(n - 1 - picks.length));
    case >= 4:
      picks.addAll(others.where((w) => sharesWord(w, word)).take(n - 1));
      picks.addAll(others.where((w) => !picks.contains(w)).take(n - 1 - picks.length));
    default:
      picks.addAll(others.take(n - 1));
  }
  return SightRound(word, [word, ...picks]..shuffle(rng));
}

/// A clip id for a word or label: "the bus" → "the_bus", "I" → "i".
String sightSlug(String word) => word.toLowerCase().replaceAll(' ', '_');

/// Like the other pick-one games: right first time wins, one slip is
/// helped, more is a miss.
String sightResult(int slips) => countingResult(slips);
