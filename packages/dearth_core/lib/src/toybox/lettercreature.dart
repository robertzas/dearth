import 'dart:math';

import 'package:meta/meta.dart';

import 'creature.dart';
import 'rounds.dart';

// Letter Creatures (SPEC FR-TOY-03, Appendix B: first sounds). Build-a-
// Creature's parts, picked by sound: "Find a body that starts with rrr!",
// with the letter in the pill and three or four parts to choose from. The
// right one goes onto the creature and the voice links sound and word
// ("Rrr, round!"); another one says its own name. Part by part a creature
// grows, and at the end it dances and says its silly name. Letter Sounds
// asks for first sounds of pictures; here the same skill builds something
// she made. The ladder: body and eyes (three to choose from) → top and legs
// too → arms and tail too, four to choose from. Drawing lives in the app.

/// Each option a part can be picked by: its option, its key word (the
/// word whose first sound picks it) and that word's first letter. Options
/// whose name starts with a muddled sound ("one big eye", "three eyes")
/// or shares a letter with another of the same part ("a spiky body") are
/// left out.
const Map<CreaturePart, List<(int, String, String)>> kCreatureSounds = {
  CreaturePart.body: [(0, 'round', 'R'), (1, 'egg', 'E'), (2, 'pear', 'P'), (3, 'square', 'S'), (5, 'fluffy', 'F')],
  CreaturePart.face: [(0, 'googly', 'G'), (3, 'sleepy', 'S'), (4, 'happy', 'H'), (5, 'long', 'L')],
  CreaturePart.top: [(1, 'horns', 'H'), (2, 'bunny', 'B'), (3, 'antennae', 'A'), (4, 'tuft', 'T'), (5, 'party', 'P')],
  CreaturePart.legs: [(1, 'two', 'T'), (2, 'four', 'F'), (4, 'bird', 'B'), (5, 'wheels', 'W')],
  CreaturePart.arms: [(1, 'little', 'L'), (2, 'wings', 'W'), (3, 'fins', 'F'), (4, 'noodle', 'N')],
  CreaturePart.tail: [(1, 'curly', 'C'), (2, 'fluffy', 'F'), (3, 'spiky', 'S'), (4, 'long', 'L')],
};

@immutable
class LetterCreatureStep {
  const LetterCreatureStep(this.part, this.answer, this.choices);
  final CreaturePart part;

  /// The option to pick.
  final int answer;

  /// The options on offer, the answer among them.
  final List<int> choices;

  (int, String, String) get _key => kCreatureSounds[part]!.firstWhere((k) => k.$1 == answer);

  /// The letter whose sound picks it.
  String get letter => _key.$3;

  /// Its key word: "round".
  String get word => _key.$2;
}

@immutable
class LetterCreatureRound {
  const LetterCreatureRound(this.steps, this.color);

  /// One a part, in the order the creature is built.
  final List<LetterCreatureStep> steps;

  /// Its paint.
  final int color;

  /// The creature once every step is picked.
  Creature get creature => Creature({for (final s in steps) s.part: s.answer}, color);
}

/// A round at [level] (Appendix B ladder): body and eyes, three to choose
/// from → top and legs too → arms and tail too, four to choose from. Not
/// the same body as [last].
LetterCreatureRound letterCreatureRound(int level, Random rng, {LetterCreatureRound? last}) {
  for (var i = 0;; i++) {
    final r = _round(level, rng);
    if (last == null || r.steps.first.answer != last.steps.first.answer || i >= 20) return r;
  }
}

LetterCreatureRound _round(int level, Random rng) {
  final n = level >= 3 ? 4 : 3;
  final steps = [
    for (final part in creatureParts(level))
      () {
        final keys = [...kCreatureSounds[part]!]..shuffle(rng);
        final choices = [for (final k in keys.take(n)) k.$1];
        return LetterCreatureStep(part, choices.first, choices..shuffle(rng));
      }(),
  ];
  return LetterCreatureRound(steps, rng.nextInt(creatureColors(level)));
}

/// A slip a part is fine for a creature of four or six; more is "helped".
String letterCreatureResult(LetterCreatureRound r, int slips) => resultFor(slips, allowed: r.steps.length ~/ 2);
