import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';
import 'words.dart';

// Hear the Sound (SPEC FR-TOY-03, Appendix B: phonics, listening). A parrot
// says a sound on its own, no word to lean on ("Which letter says mmm?"),
// and she taps the letter that makes it. A wrong letter says its own sound,
// so every slip is a comparison she hears. The right one says its name, its
// sound and its picture. The ladder: five easy, distinct sounds → more
// sounds → a sound beside the one it's mixed up with (b/p, d/t) → two
// letters that make one sound (sh, ch, th). Drawing lives in the app.

/// The first sounds: long-held or crisp, and nothing like each other.
const List<String> kEasySounds = ['a', 'm', 's', 'p', 't'];

/// The second step: more letters, still far apart.
const List<String> kMoreSounds = ['a', 'm', 's', 'p', 't', 'i', 'n', 'o', 'f', 'l', 'b', 'd'];

/// Sounds made in the same place in the mouth: the pairs early readers mix up.
const List<(String, String)> kSoundPairs = [('b', 'p'), ('d', 't'), ('k', 'g'), ('f', 'v'), ('m', 'n')];

/// Two letters, one sound.
@immutable
class Digraph {
  const Digraph(this.letters, this.sound, this.word);

  /// Small letters, "sh".
  final String letters;

  /// In the voice's phonemes, with the short "uh" consonants get (see
  /// [LetterSound.sound]).
  final String sound;

  /// Its picture word (in [kWords]).
  final String word;

  PictureWord get picture => wordNamed(word);
}

const List<Digraph> kDigraphs = [
  Digraph('sh', 'ʃˈʌ', 'shell'),
  Digraph('ch', 'tʃˈʌ', 'chick'),
  Digraph('th', 'θˈʌ', 'thumb'),
];

Digraph? digraphOf(String id) => kDigraphs.where((d) => d.letters == id).firstOrNull;

/// What a round asks: a sound, by the letter (or two) that makes it.
@immutable
class HearRound {
  const HearRound(this.answer, this.choices);

  /// "m", or a digraph's letters, "sh".
  final String answer;

  /// The tiles, in order, [answer] among them.
  final List<String> choices;

  bool get digraph => answer.length > 1;
}

/// Letters that make the same sound: never offered side by side.
bool _sameSound(String a, String b) => a == b || soundsClash(a.toUpperCase(), b.toUpperCase());

/// Whether two letters are a [kSoundPairs] pair.
bool _paired(String a, String b) => kSoundPairs.any((p) => (p.$1 == a && p.$2 == b) || (p.$1 == b && p.$2 == a));

/// A round at [level]: one of [kEasySounds] against another → one of
/// [kMoreSounds] against two that sound nothing like it → one of a
/// [kSoundPairs] pair against its partner and one more → sh, ch or th
/// against the other two and a single letter of its own ("s" for "sh"),
/// the near miss. Never the same answer as [last].
HearRound hearRound(int level, Random rng, {String? last}) {
  T pick<T>(List<T> xs) => xs[rng.nextInt(xs.length)];
  switch (level) {
    case <= 2:
      final pool = level <= 1 ? kEasySounds : kMoreSounds;
      final answer = pick([for (final l in pool) if (l != last) l]);
      final others = [for (final l in pool) if (!_sameSound(l, answer) && !_paired(l, answer)) l]..shuffle(rng);
      // Not two that sound alike among the wrong ones either.
      final wrong = <String>[];
      for (final l in others) {
        if (wrong.length == (level <= 1 ? 1 : 2)) break;
        if (wrong.every((w) => !_paired(w, l))) wrong.add(l);
      }
      return HearRound(answer, [answer, ...wrong]..shuffle(rng));
    case 3:
      final pair = pick([for (final p in kSoundPairs) if (p.$1 != last && p.$2 != last) p]);
      final (answer, partner) = rng.nextBool() ? pair : (pair.$2, pair.$1);
      final third = pick([for (final l in kMoreSounds) if (!_sameSound(l, answer) && !_sameSound(l, partner) && !_paired(l, answer) && !_paired(l, partner)) l]);
      return HearRound(answer, [answer, partner, third]..shuffle(rng));
    default:
      final d = pick([for (final d in kDigraphs) if (d.letters != last) d]);
      return HearRound(d.letters, [for (final o in kDigraphs) o.letters, d.letters[0]]..shuffle(rng));
  }
}

/// Every letter or digraph a round can ask for.
List<String> get kHearAnswers => {...kMoreSounds, for (final p in kSoundPairs) ...[p.$1, p.$2], for (final d in kDigraphs) d.letters}.toList();

/// Like the other pick-one games: right first time wins, one slip is
/// helped, more is a miss.
String hearResult(int slips) => countingResult(slips);
