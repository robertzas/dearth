import 'dart:math';

import 'package:meta/meta.dart';

import 'expansion.dart';
import 'words.dart';

// Word Builder (SPEC FR-TOY-03, Appendix B: phonics, blending and spelling).
// A picture, a strip of letter slots and a tray of small letters, the way a
// Montessori movable alphabet works: every tile says its sound, she puts the
// sounds she hears into the slots left to right, and once the word is whole
// the voice says each sound again and then blends them into the word. The
// ladder: the first letter missing (the easiest sound to hear) → the last →
// all three → four-letter words with blends (frog, drum). Drawing lives in
// the app.

/// Short words spelled the way they sound, one letter per sound, all in
/// [kWords] (the picture and its clip).
const List<String> kSpellWords = [
  'cat', 'hat', 'bat', 'rat', 'map', 'cap', 'van', 'pan', 'man', 'bag', //
  'bed', 'leg', 'pen', 'web', 'pig', 'pin', 'dog', 'sun', 'bus', 'bug', 'mug', 'cup',
];

/// Four letters, still one sound each: two consonants side by side.
const List<String> kSpellLongWords = ['frog', 'drum', 'crab', 'flag', 'milk', 'tent', 'gift', 'hand', 'sled', 'plug', 'vest', 'lips'];

/// The letters a tile can show: every letter whose sound alone is clear (X
/// says "ks" at the end of words, Q never comes without U).
const String kSpellLetters = 'abcdefghijklmnoprstuvwyz';

/// Sounds a four-year-old's ear mixes up: never offered against each other.
const List<String> _alike = ['bp', 'dt', 'cgk', 'fv', 'mn', 'sz'];

bool _soundsAlike(String a, String b) => a == b || _alike.any((g) => g.contains(a) && g.contains(b));

@immutable
class SpellRound {
  const SpellRound(this.word, this.missing, this.tiles);

  /// The picture and its word.
  final PictureWord word;

  /// The slots she fills, left to right; the others start with their letter.
  final List<int> missing;

  /// The letter tiles in the tray: the missing letters and a decoy or two.
  final List<String> tiles;

  String get letters => word.word;
}

/// A round at [level]: the first letter missing from a three-letter word,
/// with two other letters to choose from → the last letter → all three, with
/// one extra letter → a four-letter word, with one extra. Never the same
/// word as [last]. An extra letter never sounds like one in the word (no b
/// against p) and never spells another picture's word (no h for "_at": the
/// hat would be right too).
SpellRound spellRound(int level, Random rng, {String? last}) {
  final pool = level >= 4 ? kSpellLongWords : kSpellWords;
  final choices = [for (final w in pool) if (w != last) w];
  final word = choices[rng.nextInt(choices.length)];
  final missing = switch (level) {
    <= 1 => [0],
    2 => [word.length - 1],
    _ => [for (var i = 0; i < word.length; i++) i],
  };
  final decoys = missing.length == 1 ? 2 : 1;
  final known = {...kSpellWords, ...kSpellLongWords};
  bool fits(String l) {
    if (word.split('').any((w) => _soundsAlike(w, l))) return false;
    // In a one-letter round, another word with that letter in the gap.
    if (missing.length == 1) {
      final i = missing.single;
      return !known.contains(word.replaceRange(i, i + 1, l));
    }
    return true;
  }

  // A one-letter gap at the start or end of a short word is a consonant, so
  // the extras are consonants too: a vowel there would stand out.
  final extras = [for (final l in kSpellLetters.split('')) if (fits(l) && (missing.length > 1 || !_vowel(l))) l]..shuffle(rng);
  final tiles = [for (final i in missing) word[i], ...extras.take(decoys)]..shuffle(rng);
  return SpellRound(wordNamed(word), missing, tiles);
}

bool _vowel(String l) => 'aeiou'.contains(l);

/// One letter to find is a pick-one round (a slip is "helped"); a whole word
/// allows a slip per four letters.
String spellResult(int slips, {required int missing}) => expansionResult(slips, size: missing);
