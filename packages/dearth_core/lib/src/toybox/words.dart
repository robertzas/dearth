import 'dart:math';

import 'package:meta/meta.dart';


// The voice games' content (SPEC FR-TOY-03, Appendix B): picture words,
// letter sounds, rhymes and I Spy scenes, as rounds made from a Random so a
// test can replay them. Everything the games say is a bundled clip (see
// voice.dart). Every picture is an Emoji 12 glyph: the kitchen frame
// (Android 10) draws nothing newer.

T _pick<T>(List<T> xs, Random rng) => xs[rng.nextInt(xs.length)];

int _step(List<int> ladder, int level) => ladder[(level - 1).clamp(0, ladder.length - 1)];

// ───────────────────────────────── Words ────────────────────────────────────

/// The colors I Spy asks for.
const List<String> kSpyColors = ['red', 'orange', 'yellow', 'green', 'blue', 'purple', 'pink', 'brown', 'white', 'black'];

/// The outlines I Spy asks for.
const List<String> kSpyShapes = ['round', 'star', 'heart', 'triangle', 'square'];

/// A picture and its word.
@immutable
class PictureWord {
  const PictureWord(this.word, this.emoji, {this.color, this.shape});
  final String word;
  final String emoji;

  /// The color anyone would call it (one of [kSpyColors]), only when it is
  /// unmistakable in every emoji font: a bee is yellow *and* black, so it
  /// has none.
  final String? color;

  /// Its outline (one of [kSpyShapes]), when that's what it is.
  final String? shape;

  /// The clip that says it.
  String get clip => 'word_${voiceSlug(word)}';

  @override
  String toString() => word;
}

/// A clip id: lower case letters, digits and underscores ("yo-yo" → "yo_yo").
String voiceSlug(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '_');

/// Every picture word the voice games show.
const List<PictureWord> kWords = [
  PictureWord('apple', '🍎', color: 'red'),
  PictureWord('ant', '🐜'),
  PictureWord('alligator', '🐊', color: 'green'),
  PictureWord('ball', '⚽', shape: 'round'),
  PictureWord('bee', '🐝'),
  PictureWord('banana', '🍌', color: 'yellow'),
  PictureWord('bear', '🐻', color: 'brown'),
  PictureWord('bus', '🚌'),
  PictureWord('cat', '🐱'),
  PictureWord('car', '🚗', color: 'red'),
  PictureWord('cake', '🍰'),
  PictureWord('cow', '🐮'),
  PictureWord('carrot', '🥕', color: 'orange'),
  PictureWord('cookie', '🍪', color: 'brown', shape: 'round'),
  PictureWord('corn', '🌽', color: 'yellow'),
  PictureWord('dog', '🐶'),
  PictureWord('duck', '🦆'),
  PictureWord('drum', '🥁'),
  PictureWord('dinosaur', '🦕'),
  PictureWord('dolphin', '🐬', color: 'blue'),
  PictureWord('egg', '🥚', color: 'white'),
  PictureWord('elephant', '🐘'),
  PictureWord('fish', '🐟', color: 'blue'),
  PictureWord('frog', '🐸', color: 'green'),
  PictureWord('fox', '🦊', color: 'orange'),
  PictureWord('fire', '🔥'),
  PictureWord('fork', '🍴'),
  PictureWord('goat', '🐐'),
  PictureWord('gift', '🎁', shape: 'square'),
  PictureWord('guitar', '🎸'),
  PictureWord('ghost', '👻', color: 'white'),
  PictureWord('gorilla', '🦍'),
  PictureWord('hat', '🎩', color: 'black'),
  PictureWord('horse', '🐴', color: 'brown'),
  PictureWord('house', '🏠'),
  PictureWord('heart', '❤️', color: 'red', shape: 'heart'),
  PictureWord('hippo', '🦛'),
  PictureWord('iguana', '🦎', color: 'green'),
  PictureWord('juice', '🧃'),
  PictureWord('jeans', '👖', color: 'blue'),
  PictureWord('key', '🔑'),
  PictureWord('kite', '🪁'),
  PictureWord('kangaroo', '🦘'),
  PictureWord('koala', '🐨'),
  PictureWord('king', '🤴'),
  PictureWord('lion', '🦁'),
  PictureWord('lemon', '🍋', color: 'yellow'),
  PictureWord('leaf', '🍃', color: 'green'),
  PictureWord('ladybug', '🐞', color: 'red'),
  PictureWord('lollipop', '🍭'),
  PictureWord('monkey', '🐒', color: 'brown'),
  PictureWord('moon', '🌙'),
  PictureWord('mouse', '🐭'),
  PictureWord('milk', '🥛', color: 'white'),
  PictureWord('mushroom', '🍄'),
  PictureWord('nose', '👃'),
  PictureWord('noodles', '🍜'),
  PictureWord('octopus', '🐙'),
  PictureWord('otter', '🦦', color: 'brown'),
  PictureWord('ox', '🐂'),
  PictureWord('pig', '🐷', color: 'pink'),
  PictureWord('penguin', '🐧'),
  PictureWord('pizza', '🍕', shape: 'triangle'),
  PictureWord('pear', '🍐', color: 'green'),
  PictureWord('pumpkin', '🎃', color: 'orange'),
  PictureWord('panda', '🐼'),
  PictureWord('queen', '👸'),
  PictureWord('rabbit', '🐰'),
  PictureWord('rainbow', '🌈'),
  PictureWord('rocket', '🚀'),
  PictureWord('robot', '🤖'),
  PictureWord('ring', '💍'),
  PictureWord('sun', '🌞', color: 'yellow'),
  PictureWord('snake', '🐍', color: 'green'),
  PictureWord('socks', '🧦'),
  PictureWord('star', '⭐', color: 'yellow', shape: 'star'),
  PictureWord('strawberry', '🍓', color: 'red'),
  PictureWord('turtle', '🐢', color: 'green'),
  PictureWord('tiger', '🐯'),
  PictureWord('tree', '🌳', color: 'green'),
  PictureWord('train', '🚂'),
  PictureWord('tomato', '🍅', color: 'red'),
  PictureWord('tooth', '🦷', color: 'white'),
  PictureWord('tent', '⛺', shape: 'triangle'),
  PictureWord('umbrella', '☂️', color: 'purple'),
  PictureWord('van', '🚐'),
  PictureWord('violin', '🎻', color: 'brown'),
  PictureWord('volcano', '🌋'),
  PictureWord('whale', '🐳', color: 'blue'),
  PictureWord('watermelon', '🍉'),
  PictureWord('web', '🕸️'),
  PictureWord('box', '📦', shape: 'square'),
  PictureWord('yo-yo', '🪀'),
  PictureWord('yarn', '🧶'),
  PictureWord('zebra', '🦓'),
  // Rhymes.
  PictureWord('bat', '🦇'),
  PictureWord('bug', '🐛'),
  PictureWord('mug', '☕'),
  PictureWord('clock', '⏰'),
  PictureWord('lock', '🔒'),
  PictureWord('boat', '⛵'),
  PictureWord('coat', '🧥'),
  PictureWord('rain', '🌧️'),
  PictureWord('plane', '✈️'),
  PictureWord('crown', '👑'),
  PictureWord('clown', '🤡'),
  PictureWord('spoon', '🥄'),
  PictureWord('balloon', '🎈', color: 'red'),
  PictureWord('chair', '🪑'),
  PictureWord('bell', '🔔'),
  PictureWord('shell', '🐚'),
  PictureWord('dice', '🎲'),
  PictureWord('rice', '🍚'),
  PictureWord('ice', '🧊'),
  PictureWord('pan', '🍳'),
  PictureWord('man', '👨'),
  PictureWord('snail', '🐌'),
  // I Spy.
  PictureWord('orange', '🍊', color: 'orange', shape: 'round'),
  PictureWord('basketball', '🏀', color: 'orange', shape: 'round'),
  PictureWord('chick', '🐥', color: 'yellow'),
  PictureWord('broccoli', '🥦', color: 'green'),
  PictureWord('cucumber', '🥒', color: 'green'),
  PictureWord('butterfly', '🦋', color: 'blue'),
  PictureWord('grapes', '🍇', color: 'purple'),
  PictureWord('eggplant', '🍆', color: 'purple'),
  PictureWord('flamingo', '🦩', color: 'pink'),
  PictureWord('flower', '🌸', color: 'pink'),
  PictureWord('potato', '🥔', color: 'brown'),
  PictureWord('cloud', '☁️', color: 'white'),
  PictureWord('snowman', '⛄', color: 'white'),
  PictureWord('spider', '🕷️', color: 'black'),
  PictureWord('cheese', '🧀', shape: 'triangle'),
  PictureWord('picture', '🖼️', shape: 'square'),
  // Word Builder: words spelled the way they sound.
  PictureWord('rat', '🐀'),
  PictureWord('map', '🗺️'),
  PictureWord('cap', '🧢'),
  PictureWord('bag', '👜'),
  PictureWord('bed', '🛏️'),
  PictureWord('leg', '🦵'),
  PictureWord('pen', '🖊️'),
  PictureWord('pin', '📌'),
  PictureWord('cup', '🥤'),
  PictureWord('crab', '🦀'),
  PictureWord('flag', '🚩'),
  PictureWord('hand', '✋'),
  PictureWord('sled', '🛷'),
  PictureWord('plug', '🔌'),
  PictureWord('vest', '🦺'),
  PictureWord('lips', '👄'),
  // Hear the Sound: th (shell and chick are above).
  PictureWord('thumb', '👍'),
];

/// [kWords] by word.
final Map<String, PictureWord> kWordsByName = {for (final w in kWords) w.word: w};

PictureWord wordNamed(String word) => kWordsByName[word] ?? (throw ArgumentError.value(word, 'word', 'not in kWords'));

// ───────────────────────────── Letter Sounds ────────────────────────────────

/// A letter, the sound it makes and words that start with it.
@immutable
class LetterSound {
  const LetterSound(this.letter, this.sound, this.words, {this.starts = true});

  /// Upper case.
  final String letter;

  /// The sound, in the voice's phonemes (espeak's IPA, see voice.dart): a
  /// short vowel, "buh" for a stop, a long "sss". Text can't spell these.
  final String sound;

  /// Words with that sound, its own picture first (all in [kWords]).
  final List<String> words;

  /// False for X: its words (fox, box) end with its sound.
  final bool starts;

  String get id => letter.toLowerCase();
  PictureWord get picture => wordNamed(words.first);
}

const List<LetterSound> kLetterSounds = [
  LetterSound('A', 'ˈa', ['apple', 'ant', 'alligator']),
  LetterSound('B', 'bˈʌ', ['ball', 'bee', 'banana', 'bear', 'bus']),
  LetterSound('C', 'kˈʌ', ['cat', 'car', 'cake', 'cow', 'carrot', 'cookie', 'corn']),
  LetterSound('D', 'dˈʌ', ['dog', 'duck', 'drum', 'dinosaur', 'dolphin']),
  LetterSound('E', 'ˈɛ', ['egg', 'elephant']),
  LetterSound('F', 'fˈʌ', ['fish', 'frog', 'fox', 'fire', 'fork']),
  LetterSound('G', 'ɡˈʌ', ['goat', 'gift', 'guitar', 'ghost', 'gorilla']),
  LetterSound('H', 'hˈʌ', ['hat', 'horse', 'house', 'heart', 'hippo']),
  LetterSound('I', 'ˈɪ', ['iguana']),
  LetterSound('J', 'dʒˈʌ', ['juice', 'jeans']),
  LetterSound('K', 'kˈʌ', ['key', 'kite', 'kangaroo', 'koala', 'king']),
  LetterSound('L', 'lˈʌ', ['lion', 'lemon', 'leaf', 'ladybug', 'lollipop']),
  LetterSound('M', 'mˈʌ', ['monkey', 'moon', 'mouse', 'milk', 'mushroom']),
  LetterSound('N', 'nˈʌ', ['nose', 'noodles']),
  LetterSound('O', 'ˈɒ', ['octopus', 'otter', 'ox']),
  LetterSound('P', 'pˈʌ', ['pig', 'penguin', 'pizza', 'pear', 'pumpkin', 'panda']),
  LetterSound('Q', 'kwˈʌ', ['queen']),
  LetterSound('R', 'ɹˈʌ', ['rabbit', 'rainbow', 'rocket', 'robot', 'ring']),
  LetterSound('S', 'sˈʌ', ['sun', 'snake', 'socks', 'star', 'strawberry']),
  LetterSound('T', 'tˈʌ', ['turtle', 'tiger', 'tree', 'train', 'tomato', 'tooth']),
  LetterSound('U', 'ˈʌ', ['umbrella']),
  LetterSound('V', 'vˈʌ', ['van', 'violin', 'volcano']),
  LetterSound('W', 'wˈʌ', ['whale', 'watermelon', 'web']),
  LetterSound('X', 'ks', ['fox', 'box'], starts: false),
  LetterSound('Y', 'jˈʌ', ['yo-yo', 'yarn']),
  LetterSound('Z', 'zˈʌ', ['zebra']),
];

LetterSound letterSound(String letter) => kLetterSounds.firstWhere((l) => l.letter == letter.toUpperCase());

/// Letters that make the same sound: never offered side by side when a sound
/// is the question (cat could start with C or K).
const List<Set<String>> kSameSound = [
  {'C', 'K', 'Q'},
];

/// Whether [a] and [b] can't both be offered for one sound.
bool soundsClash(String a, String b) => a == b || kSameSound.any((g) => g.contains(a) && g.contains(b));

/// What a Letter Sounds round asks (Appendix B: hear → find the letter →
/// first-sound game).
enum LetterMode { hear, find, firstSound }

@immutable
class LetterRound {
  const LetterRound(this.mode, this.letters, {this.answer, this.word});
  final LetterMode mode;

  /// The letter tiles, in order.
  final List<LetterSound> letters;

  /// The letter to find ([LetterMode.find], [LetterMode.firstSound]).
  final LetterSound? answer;

  /// The picture whose first sound is asked ([LetterMode.firstSound]).
  final PictureWord? word;
}

/// Letter tiles per level: four to hear, then find one among 2 → 3, then
/// the first sound of a picture among 3 → 4.
const List<(LetterMode, int)> kLetterLevels = [
  (LetterMode.hear, 4),
  (LetterMode.find, 2),
  (LetterMode.find, 3),
  (LetterMode.firstSound, 3),
  (LetterMode.firstSound, 4),
];

/// A Letter Sounds round. [favorite] (the first letter of her name) turns up
/// in half the rounds she only listens to: "A, a, apple" is Ava's.
LetterRound letterRound(int level, Random rng, {String? favorite, String? last}) {
  final (mode, count) = kLetterLevels[(level - 1).clamp(0, kLetterLevels.length - 1)];
  final pool = [for (final l in kLetterSounds) if (mode != LetterMode.firstSound || l.starts) l];
  if (mode == LetterMode.hear) {
    final fav = favorite == null ? null : kLetterSounds.where((l) => l.letter == favorite.toUpperCase()).firstOrNull;
    final picks = <LetterSound>[if (fav != null && rng.nextBool()) fav];
    for (final l in [...kLetterSounds]..shuffle(rng)) {
      if (picks.length == count) break;
      if (!picks.contains(l)) picks.add(l);
    }
    return LetterRound(mode, picks..shuffle(rng));
  }
  final candidates = [for (final l in pool) if (l.letter != last) l];
  final answer = _pick(candidates, rng);
  // Any other letter for "find"; for a sound, none that makes it too (and
  // not X, whose words only end with its sound).
  final others = [for (final l in kLetterSounds) if (!soundsClash(l.letter, answer.letter) && (mode == LetterMode.find || l.starts)) l]..shuffle(rng);
  final letters = [answer, ...others.take(count - 1)]..shuffle(rng);
  return LetterRound(mode, letters, answer: answer, word: mode == LetterMode.firstSound ? wordNamed(_pick(answer.words, rng)) : null);
}

// ─────────────────────────────── Rhyme Time ─────────────────────────────────

/// Words that rhyme, the one asked about first.
@immutable
class RhymeFamily {
  const RhymeFamily(this.vowel, this.words);

  /// Its vowel sound: a wrong choice never shares it, so "cat" isn't asked
  /// against "van" (too close for a four-year-old's ear).
  final String vowel;
  final List<String> words;

  PictureWord get anchor => wordNamed(words.first);
}

const List<RhymeFamily> kRhymes = [
  RhymeFamily('a', ['cat', 'hat', 'bat']),
  RhymeFamily('o', ['dog', 'frog']),
  RhymeFamily('ee', ['bee', 'tree', 'key']),
  RhymeFamily('ay', ['cake', 'snake']),
  RhymeFamily('u', ['bug', 'mug']),
  RhymeFamily('ar', ['car', 'star', 'guitar']),
  RhymeFamily('o', ['clock', 'lock']),
  RhymeFamily('oh', ['goat', 'boat', 'coat']),
  RhymeFamily('ow', ['mouse', 'house']),
  RhymeFamily('ay', ['train', 'rain', 'plane']),
  RhymeFamily('ow', ['crown', 'clown']),
  RhymeFamily('o', ['fox', 'box', 'socks']),
  RhymeFamily('oo', ['moon', 'spoon', 'balloon']),
  RhymeFamily('air', ['bear', 'pear', 'chair']),
  RhymeFamily('i', ['ring', 'king']),
  RhymeFamily('e', ['bell', 'shell']),
  RhymeFamily('eye', ['dice', 'rice', 'ice']),
  RhymeFamily('a', ['van', 'pan', 'man']),
  RhymeFamily('ay', ['whale', 'snail']),
];

/// Choices per level: 2 → 4.
const List<int> kRhymeChoices = [2, 3, 4];

@immutable
class RhymeRound {
  const RhymeRound(this.anchor, this.match, this.choices);

  /// The word to rhyme with.
  final PictureWord anchor;
  final PictureWord match;

  /// [match] among words that don't rhyme with [anchor] (or each other).
  final List<PictureWord> choices;
}

RhymeRound rhymeRound(int level, Random rng, {String? last}) {
  final count = _step(kRhymeChoices, level);
  final family = _pick([for (final f in kRhymes) if (f.words.first != last) f], rng);
  final match = wordNamed(_pick(family.words.sublist(1), rng));
  final others = [for (final f in kRhymes) if (f.vowel != family.vowel) f]..shuffle(rng);
  final wrong = [for (final f in others.take(count - 1)) wordNamed(_pick(f.words, rng))];
  return RhymeRound(family.anchor, match, [match, ...wrong]..shuffle(rng));
}

// ──────────────────────────────── I Spy ─────────────────────────────────────

/// What an I Spy clue is about (Appendix B: colors → shapes → letters).
enum SpyClue { color, shape, letter }

/// The clue and how many things are in the scene, per level.
const List<(SpyClue, int)> kSpyLevels = [(SpyClue.color, 4), (SpyClue.color, 6), (SpyClue.shape, 5), (SpyClue.shape, 6), (SpyClue.letter, 6)];

@immutable
class SpyRound {
  const SpyRound(this.clue, this.value, this.answer, this.things);
  final SpyClue clue;

  /// The color, shape or letter asked for.
  final String value;
  final PictureWord answer;

  /// Everything in the scene, [answer] among them; nothing else fits the clue.
  final List<PictureWord> things;
}

SpyRound spyRound(int level, Random rng, {String? last}) {
  final (clue, count) = kSpyLevels[(level - 1).clamp(0, kSpyLevels.length - 1)];
  switch (clue) {
    case SpyClue.color:
      final colored = [for (final w in kWords) if (w.color != null) w];
      final answer = _pick([for (final w in colored) if (w.word != last) w], rng);
      // One of each other color, so the scene is a rainbow.
      final colors = [for (final c in kSpyColors) if (c != answer.color) c]..shuffle(rng);
      final rest = [for (final c in colors.take(count - 1)) _pick([for (final w in colored) if (w.color == c) w], rng)];
      return SpyRound(clue, answer.color!, answer, [answer, ...rest]..shuffle(rng));
    case SpyClue.shape:
      final shaped = [for (final w in kWords) if (w.shape != null) w];
      final answer = _pick([for (final w in shaped) if (w.word != last) w], rng);
      final rest = [for (final w in shaped) if (w.shape != answer.shape) w]..shuffle(rng);
      return SpyRound(clue, answer.shape!, answer, [answer, ...rest.take(count - 1)]..shuffle(rng));
    case SpyClue.letter:
      final letter = _pick([for (final l in kLetterSounds) if (l.starts) l], rng);
      final answer = wordNamed(_pick(letter.words, rng));
      // Words of other letters, one per letter, none that starts with this
      // one's letter or sound.
      final others = [for (final l in kLetterSounds) if (l.starts && !soundsClash(l.letter, letter.letter)) l]..shuffle(rng);
      final rest = <PictureWord>[];
      for (final l in others) {
        if (rest.length == count - 1) break;
        final w = wordNamed(_pick(l.words, rng));
        if (w.word[0].toUpperCase() != letter.letter) rest.add(w);
      }
      return SpyRound(clue, letter.letter, answer, [answer, ...rest]..shuffle(rng));
  }
}

/// Every picture the voice games show, for the Emoji 12 guard.
List<String> get kWordPictures => [for (final w in kWords) w.emoji];
