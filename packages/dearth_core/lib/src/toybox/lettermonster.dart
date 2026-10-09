import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';
import 'words.dart';

// Letter Monster (SPEC FR-TOY-03, Appendix B: letter names and sounds). Feed
// the Monster's orange cousin eats only letter biscuits, and it says which
// one it wants: by the letter's name ("I want the letter B!"), then its
// sound ("I want the letter that says buh!"), then a picture's first sound
// ("Bee. Which letter does bee start with?"). She feeds it by tapping the
// biscuit or dragging it to the mouth. Letter Sounds and Hear the Sound ask
// the same questions as quiet tiles; this is the monster she plays longest,
// so the drill is feeding. The ladder: capitals by name among three that
// don't look alike → small letters by name among four, with a mirror or
// look-alike decoy when there is one → small letters by sound → a picture's
// first sound among five. Drawing lives in the app.

enum LetterMonsterAsk { name, small, sound, picture }

@immutable
class LetterMonsterRound {
  const LetterMonsterRound(this.ask, this.letter, this.choices, {this.word});
  final LetterMonsterAsk ask;

  /// The letter it wants, upper case.
  final String letter;

  /// The biscuits on the tray, upper case, the answer among them, never two
  /// the same.
  final List<String> choices;

  /// The picture whose first sound it wants ([LetterMonsterAsk.picture]).
  final PictureWord? word;

  /// Whether the biscuits show small letters.
  bool get small => ask != LetterMonsterAsk.name;
}

/// Capitals that are easy to mix up: never a decoy at the first level.
const List<Set<String>> _confusable = [
  {'B', 'D', 'P', 'Q', 'R'},
  {'M', 'W', 'N'},
  {'E', 'F'},
  {'O', 'Q', 'C', 'G'},
  {'U', 'V'},
  {'I', 'L', 'J', 'T'},
];

/// Small letters that are each other's mirror or turn: the decoy she has
/// to learn to tell apart.
const Map<String, String> _smallTwin = {'B': 'D', 'D': 'B', 'P': 'Q', 'Q': 'P', 'N': 'U', 'U': 'N', 'M': 'W', 'W': 'M', 'I': 'L', 'L': 'I', 'H': 'N'};

LetterSound _sound(String letter) => kLetterSounds.firstWhere((l) => l.letter == letter);

/// A round at [level] (Appendix B ladder): capitals by name (3) → small
/// letters by name (4) → by sound (4) → a picture's first sound (5). Not
/// the same letter as [last].
LetterMonsterRound letterMonsterRound(int level, Random rng, {LetterMonsterRound? last}) {
  for (var i = 0;; i++) {
    final r = _round(level, rng);
    if (last == null || r.letter != last.letter || i >= 20) return r;
  }
}

LetterMonsterRound _round(int level, Random rng) {
  final ask = switch (level) { <= 1 => LetterMonsterAsk.name, 2 => LetterMonsterAsk.small, 3 => LetterMonsterAsk.sound, _ => LetterMonsterAsk.picture };
  final n = switch (ask) { LetterMonsterAsk.name => 3, LetterMonsterAsk.picture => 5, _ => 4 };
  // Sounds and pictures need a letter whose sound starts its words (not X).
  final pool = [for (final l in kLetterSounds) if (ask == LetterMonsterAsk.name || ask == LetterMonsterAsk.small || l.starts) l.letter];
  final letter = pool[rng.nextInt(pool.length)];
  final picks = <String>[letter];
  bool fits(String c) {
    if (picks.contains(c)) return false;
    return switch (ask) {
      // Nothing that looks like another biscuit on the tray.
      LetterMonsterAsk.name => !picks.any((p) => _confusable.any((s) => s.contains(p) && s.contains(c))),
      LetterMonsterAsk.small => true,
      // Two letters that make one sound (C and K) can't both be there.
      _ => picks.every((p) => _sound(p).sound != _sound(c).sound),
    };
  }

  if (ask == LetterMonsterAsk.small && _smallTwin[letter] != null) picks.add(_smallTwin[letter]!);
  final rest = [for (final l in kLetterSounds) l.letter]..shuffle(rng);
  for (final c in rest) {
    if (picks.length >= n) break;
    if (fits(c)) picks.add(c);
  }
  picks.shuffle(rng);
  final word = ask == LetterMonsterAsk.picture ? wordNamed(_sound(letter).words[rng.nextInt(_sound(letter).words.length)]) : null;
  return LetterMonsterRound(ask, letter, picks, word: word);
}

/// One letter to find: right first time is a win, one slip is "helped",
/// more is a miss.
String letterMonsterResult(int slips) => countingResult(slips);
