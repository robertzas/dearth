import 'biglittle.dart';
import 'creature.dart';
import 'dots.dart';
import 'hop.dart';
import 'voice_lengths.g.dart';
import 'words.dart';

// What the Toybox says (SPEC FR-TOY-03). The kitchen frame has no
// text-to-speech, so every line is a clip bundled with the app
// (assets/voice/<id>.mp3), made offline by tool/sounds/voice.py with Piper
// and its public-domain LJSpeech voice. The games ask for clips by the ids
// built here, and the generator reads [kVoiceLines] (through
// packages/dearth_core/tool/voice_lines.dart), so the two can't disagree.

/// Text inside [[ ]] is in the voice's own phonemes (espeak's IPA, as
/// Piper reads it): the letter sounds, which no spelling gives ("buh", a
/// short "a"). Consonants are said with a short "uh": alone, the voice
/// slips a vowel in front of them ("sss" comes out "ess").
String _sound(LetterSound l) => '[[${l.sound}]]';

String _cap(String s) => s[0].toUpperCase() + s.substring(1);

/// "B. Buh, buh, ball.": the letter, its sound twice and its picture.
String letterClip(String letter) => 'letter_${letter.toLowerCase()}';

/// "Find the letter B."
String findLetterClip(String letter) => 'find_${letter.toLowerCase()}';

/// Just the letter's name: "B."
String letterNameClip(String letter) => 'name_${letter.toLowerCase()}';

/// "Bee. Which letter does bee start with?"
String firstSoundClip(PictureWord w) => 'first_${voiceSlug(w.word)}';

/// "Buh, buh, bee.": the first sound, as a hint.
String firstSoundHintClip(PictureWord w) => 'hint_${voiceSlug(w.word)}';

/// "Cat. What rhymes with cat?"
String rhymeAskClip(PictureWord anchor) => 'rhyme_${voiceSlug(anchor.word)}';

/// "Cat, hat. They rhyme!"
String rhymeYesClip(PictureWord anchor, PictureWord match) => 'rhymes_${voiceSlug(anchor.word)}_${voiceSlug(match.word)}';

/// "I spy, with my little eye, something yellow!"
String spyClip(SpyClue clue, String value) => 'spy_${clue.name}_${voiceSlug(value)}';

/// How long to wait after starting [clip] before the next line, so it
/// isn't cut off (a new clip stops the one before): its length plus a
/// breath, and never less than [atLeast]. A line whose clip hasn't been
/// made yet counts as two seconds.
Duration afterVoice(String clip, {Duration atLeast = Duration.zero}) {
  final d = Duration(milliseconds: (kVoiceMs[clip] ?? 2000) + 350);
  return d > atLeast ? d : atLeast;
}

/// "Big C, little c."
String bigLittleClip(String letter) => 'biglittle_${letter.toLowerCase()}';

/// What Frog Hop asks: "Hop to six!", "One more than four!", "One less
/// than four!", "Three and two more!".
String hopAskClip(HopRound r) => switch (r.mode) {
      HopMode.find => 'hop_to_${r.target}',
      HopMode.oneMore => 'hop_more_${r.from}',
      HopMode.oneLess => 'hop_less_${r.from}',
      HopMode.add => 'hop_add_${r.from}_${r.hops}',
    };

/// "Three."
String numberClip(int n) => 'num_$n';

/// "One, two, three."
String countClip(int n) => 'count_$n';

/// "Purple!"
String colorClip(String color) => 'color_${voiceSlug(color)}';

/// "Find the number seven."
String findNumberClip(int n) => 'find_num_$n';

/// "It's a star!": the picture the dots made.
String dotsDoneClip(DotPicture p) => 'dots_${p.id}';

/// Lines that aren't about one letter or word.
abstract final class VoiceLine {
  static const traceName = 'trace_name';
  static const traceNameDone = 'trace_name_done';
  static const breatheStart = 'breathe_start';
  static const breatheIn = 'breathe_in';
  static const breatheOut = 'breathe_out';
  static const breatheDone = 'breathe_done';
  static const makeCreature = 'make_creature';
  static const dotsNumbers = 'dots_numbers';
  static const dotsLetters = 'dots_letters';
  static const bigLittleStart = 'biglittle_start';
  static const bigLittleDone = 'biglittle_done';
}

const List<String> _numbers = [
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', //
  'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty',
];

/// Where espeak's English (which this voice was trained on) says another
/// word than an American would: a letter Z is "zed", a zebra a "zebb-ra".
/// Accents are fine (the voice says its own vowels); these words aren't.
const Map<String, String> _american = {
  'Z': '[[zˈiː]]',
  'zebra': '[[zˈiːbɹə]]',
  'banana': '[[bɐnˈanə]]',
  'tomato': '[[təmˈeɪtəʊ]]',
  // espeak's "one" rhymes with "on"; the American one rhymes with "sun".
  'one': '[[wˈʌn]]',
};

final RegExp _americanWord = RegExp('\\b(${_american.keys.join('|')})\\b', caseSensitive: false);

/// [line] with [_american] words in their phonemes (outside [[ ]] only).
String _americanize(String line) => line.splitMapJoin(
      RegExp(r'\[\[.*?\]\]'),
      onMatch: (m) => m[0]!,
      onNonMatch: (text) => text.replaceAllMapped(_americanWord, (m) => _american[m[0]!] ?? _american[m[0]!.toLowerCase()] ?? _american[m[0]!.toUpperCase()] ?? m[0]!),
    );

const Map<String, String> _shapeClues = {
  'round': 'something round',
  'star': 'something shaped like a star',
  'heart': 'something shaped like a heart',
  'triangle': 'something shaped like a triangle',
  'square': 'something square',
};

/// Every clip the Toybox can say, by id, with its words.
final Map<String, String> kVoiceLines = _lines();

Map<String, String> _lines() {
  final lines = <String, String>{};
  for (final w in kWords) {
    lines[w.clip] = '${_cap(w.word)}.';
  }
  for (final l in kLetterSounds) {
    // X's sound ends its words, so they say it: "X. Fox, box."
    lines[letterClip(l.letter)] = l.starts ? '${l.letter}. ${_sound(l)}, ${_sound(l)}, ${l.words.first}.' : '${l.letter}. ${_cap(l.words.join(', '))}.';
    lines[findLetterClip(l.letter)] = 'Find the letter ${l.letter}.';
    lines[letterNameClip(l.letter)] = '${l.letter}.';
    if (!l.starts) continue;
    for (final word in l.words) {
      final w = wordNamed(word);
      lines[firstSoundClip(w)] = '${_cap(word)}. Which letter does $word start with?';
      lines[firstSoundHintClip(w)] = '${_sound(l)}, ${_sound(l)}, $word.';
    }
  }
  for (final f in kRhymes) {
    lines[rhymeAskClip(f.anchor)] = '${_cap(f.anchor.word)}. What rhymes with ${f.anchor.word}?';
    for (final m in f.words.skip(1)) {
      lines[rhymeYesClip(f.anchor, wordNamed(m))] = '${_cap(f.anchor.word)}, $m. They rhyme!';
    }
  }
  const spy = 'I spy, with my little eye,';
  for (final c in kSpyColors) {
    lines[spyClip(SpyClue.color, c)] = '$spy something $c!';
  }
  for (final s in kSpyShapes) {
    lines[spyClip(SpyClue.shape, s)] = '$spy ${_shapeClues[s]}!';
  }
  for (final l in kLetterSounds.where((l) => l.starts)) {
    lines[spyClip(SpyClue.letter, l.letter)] = '$spy something that starts with ${l.letter}. ${_sound(l)}!';
  }
  for (var n = 0; n <= 20; n++) {
    lines[numberClip(n)] = '${_cap(_numbers[n])}.';
  }
  for (var n = 1; n <= 20; n++) {
    lines[findNumberClip(n)] = 'Find the number ${_numbers[n]}.';
  }
  lines[countClip(0)] = 'Zero. Nothing at all!';
  for (var n = 1; n <= 10; n++) {
    lines[countClip(n)] = '${_cap(_numbers.sublist(1, n + 1).join(', '))}.';
  }
  lines[VoiceLine.traceName] = "Let's write your name!";
  lines[VoiceLine.traceNameDone] = 'You wrote your name!';
  lines[VoiceLine.breatheStart] = "Let's take slow, big breaths, with your buddy.";
  lines[VoiceLine.breatheIn] = 'Breathe in, and smell the flower.';
  lines[VoiceLine.breatheOut] = 'And blow out the candle.';
  lines[VoiceLine.breatheDone] = 'Well done. Your body feels calm.';
  lines[VoiceLine.makeCreature] = "Let's make a silly creature!";
  for (final name in kCreatureNames) {
    lines[creatureNameClip(name)] = "I'm a $name!";
  }
  for (final MapEntry(key: part, value: words) in kCreaturePartWords.entries) {
    for (var i = 0; i < words.length; i++) {
      lines[creaturePartClip(part, i)] = '${_cap(words[i])}!';
    }
  }
  for (final c in kCreaturePaints) {
    lines[colorClip(c)] = '${_cap(c)}!';
  }
  lines[VoiceLine.dotsNumbers] = 'Join the dots! Start at one.';
  // Alone, "A" is read as the word "a".
  lines[VoiceLine.dotsLetters] = 'Join the dots! Start at [[ˈeɪ]].';
  for (final p in kDotPictures) {
    lines[dotsDoneClip(p)] = "It's ${p.phrase}!";
  }
  lines[VoiceLine.bigLittleStart] = 'Help the little letters find their big letters!';
  lines[VoiceLine.bigLittleDone] = 'You found them all!';
  for (final l in [...kLookAlikeLetters, ...kDifferentLetters, ...kMirrorLetters]) {
    lines[bigLittleClip(l)] = 'Big ${l.toUpperCase()}, little $l.';
  }
  for (var n = 0; n <= 10; n++) {
    lines[hopAskClip(HopRound(HopMode.find, 11, n == 0 ? 1 : 0, n))] = 'Hop to ${_numbers[n]}!';
  }
  for (var n = 0; n <= 9; n++) {
    lines[hopAskClip(HopRound(HopMode.oneMore, 11, n, n + 1))] = 'One more than ${_numbers[n]}!';
  }
  for (var n = 1; n <= 10; n++) {
    lines[hopAskClip(HopRound(HopMode.oneLess, 11, n, n - 1))] = 'One less than ${_numbers[n]}!';
  }
  for (final (from, more) in kHopSums) {
    lines[hopAskClip(HopRound(HopMode.add, 11, from, from + more))] = '${_cap(_numbers[from])} and ${_numbers[more]} more!';
  }
  return lines.map((id, line) => MapEntry(id, _americanize(line)));
}
