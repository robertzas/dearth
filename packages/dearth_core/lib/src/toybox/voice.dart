import 'dart:math';

import 'balance.dart';
import 'biglittle.dart';
import 'busstop.dart';
import 'compare.dart';
import 'cookies.dart';
import 'creature.dart';
import 'creaturecount.dart';
import 'dots.dart';
import 'dressup.dart';
import 'fishing.dart';
import 'freeze.dart';
import 'hear.dart';
import 'hop.dart';
import 'lettercreature.dart';
import 'lettermonster.dart';
import 'rocket.dart';
import 'sight.dart';
import 'spell.dart';
import 'storytime.dart';
import 'tally.dart';
import 'voice_lengths.g.dart';
import 'whosthat.dart';
import 'words.dart';
import 'zoo.dart';

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

/// A letter's sound alone, as a tile says it: "Buh." Two letters that make
/// one sound (sh) have one too.
String soundClip(String letter) => 'sound_${letter.toLowerCase()}';

/// "Which letter says mmm?", "Which letters say shh?"
String hearAskClip(String answer) => 'hear_$answer';

/// The answer's reward: [letterClip] for a letter ("M. Muh, muh, monkey."),
/// and for two letters "S, H. Shuh, shuh, shell."
String hearYesClip(String answer) => answer.length == 1 ? letterClip(answer) : 'digraph_$answer';

/// "Find the word: go.", "Find the words: the bus."
String sightAskClip(String word) => 'sight_find_${sightSlug(word)}';

/// The word read out: "Go."
String sightWordClip(String word) => 'sight_${sightSlug(word)}';

/// "Five is more than three."
String balanceMoreClip(int more, int fewer) => 'balance_${more}_$fewer';

/// "Which bus has more kids?", "Which bus has fewer kids?", "Line up the
/// buses. Fewest kids first!"
String compareAskClip(CompareAsk ask) => 'compare_ask_${ask.name}';

/// Said after the bus's number: "That bus has more kids!", "That bus has
/// fewer kids!", "All lined up, from fewest to most!"
String compareYesClip(CompareAsk ask) => 'compare_yes_${ask.name}';

/// "Find your name!", "Find the name I spell.", "Let's spell a name, letter
/// by letter!" Names are the family's own, so the voice spells them
/// ([zooSpellClips]) rather than saying them.
String zooAskClip(ZooMode mode) => 'zoo_ask_${mode.name}';

/// When the animal gets its card: "That's your name! Thank you!", "Thank
/// you!", "You spelled it! Thank you!"
String zooYesClip(ZooMode mode) => 'zoo_yes_${mode.name}';

/// [name] spelled out, one letter-name clip a letter.
List<String> zooSpellClips(String name) => [for (final l in name.split('')) letterNameClip(l)];

/// A finished count of bunnies: "One bunny!", "Seven bunnies!"
String tallyBunniesClip(int n) => 'tally_$n';

/// "It's snowy today! What should Buddy wear?" (or, with no forecast,
/// "Let's pretend it's snowy! What should Buddy wear?").
String dressDayClip(DressWeather w, {required bool pretend}) => 'dress_${pretend ? 'pretend' : 'day'}_${w.name}';

/// "What should Buddy wear on top?", "And on the legs?", "What shoes?",
/// "One more thing!"
String dressSlotClip(DressSlot slot) => 'dress_slot_${slot.name}';

/// The item's name when picked: "Boots!", "A sun hat!"
String dressItemClip(DressItem item) => 'dress_item_${item.name}';

/// "Dance like a frog!", "Hop like a bunny!"
String freezeAnimalClip(FreezeAnimal a) => 'freeze_${a.name}';

/// Cookie Count's monster: "I want five cookies!"
String cookieAskClip(int n) => 'cookies_ask_$n';

/// When the plate is right: "Five cookies! Yum, yum!"
String cookieYumClip(int n) => 'cookies_yum_$n';

/// Too few on the plate: "More, please! I want five."
String cookieMoreClip(int n) => 'cookies_more_$n';

/// Too many: "Too many! I want five."
String cookieFewerClip(int n) => 'cookies_fewer_$n';

/// Creature Count: "Give it three eyes!"
String ccountAskClip(CountPart p, int n) => 'ccount_ask_${p.name}_$n';

/// The second part at level 3: "And two legs!"
String ccountAndClip(CountPart p, int n) => 'ccount_and_${p.name}_$n';

/// Level 4: "Give it this many spots!"
String ccountManyClip(CountPart p) => 'ccount_many_${p.name}';

/// Too few: "More eyes, please!"
String ccountMoreClip(CountPart p) => 'ccount_more_${p.name}';

/// Too many: "Too many eyes!"
String ccountFewerClip(CountPart p) => 'ccount_fewer_${p.name}';

/// Right: "Yay! Three eyes!"
String ccountYayClip(CountPart p, int n) => 'ccount_yay_${p.name}_$n';

/// What Letter Monster wants: "I want the letter B!", "I want the letter
/// that says buh!", or a picture's first sound ([firstSoundClip]).
String letterMonsterAskClip(LetterMonsterRound r) => switch (r.ask) {
      LetterMonsterAsk.name || LetterMonsterAsk.small => 'lmon_want_${r.letter.toLowerCase()}',
      LetterMonsterAsk.sound => 'lmon_says_${r.letter.toLowerCase()}',
      LetterMonsterAsk.picture => firstSoundClip(r.word!),
    };

/// The bus pulls in: "Three kids are on the bus."
String busStartClip(int n) => 'busstop_start_$n';

/// "Two more get on!"
String busOnClip(int n) => 'busstop_on_$n';

/// "Two get off!"
String busOffClip(int n) => 'busstop_off_$n';

/// The answer: "Five kids on the bus!"
String busNowClip(int n) => 'busstop_now_$n';

/// "Count down from ten!"
String rocketStartClip(int n) => 'rocket_from_$n';

/// What Number Fishing asks: "Find the number seven.", "Catch the biggest
/// number!", "Catch two fish that make five!"
String fishAskClip(FishRound r) => switch (r.ask) {
      FishAsk.find => findNumberClip(r.target!),
      FishAsk.biggest => 'fish_biggest',
      FishAsk.makeFive => 'fish_five',
    };

/// A pair that makes five, caught: "Two and three make five!"
String fishPairClip(int a, int b) => 'fish_pair_${min(a, b)}';

/// What Letter Creatures asks: "Find a body that starts with rrr!"
String letterCreatureAskClip(LetterCreatureStep s) => 'lc_${s.part.name}_${s.letter.toLowerCase()}';

/// The right part, sound and word together: "Rrr, rrr, round!"
String letterCreatureYesClip(CreaturePart part, int option) => 'lc_yes_${part.name}_$option';

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
  static const balanceAsk = 'balance_ask';
  static const spellMissing = 'spell_missing';
  static const spellBuild = 'spell_build';
  static const tallyStart = 'tally_start';
  static const tallyFive = 'tally_five';
  static const tallyTap = 'tally_tap';
  static const tallyAsk = 'tally_ask';
  static const hundredHiding = 'hundred_hiding';
  static const freezeStart = 'freeze_start';
  static const freezeStop = 'freeze_stop';
  static const freezeGo = 'freeze_go';
  static const freezeDone = 'freeze_done';
  static const seqStart = 'seq_start';
  static const dressDone = 'dress_done';
  static const storyPick = 'story_pick';
  static const storyEnd = 'story_end';
  static const whoYes = 'who_yes';
  static const whoYesYou = 'who_yes_you';
  static const cookiesBell = 'cookies_bell';
  static const ccountDance = 'ccount_dance';
  static const busStopAsk = 'busstop_ask';
  static const rocketBlastOff = 'rocket_blastoff';
  static const trainNext = 'train_next';
  static const trainMissing = 'train_missing';
  static const trainGo = 'train_go';
}

const List<String> _numbers = [
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', //
  'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty',
];

/// [n] (0–100) in words: "fifty-four", "one hundred".
String numberWord(int n) {
  if (n <= 20) return _numbers[n];
  if (n == 100) return 'one hundred';
  const tens = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];
  return n % 10 == 0 ? tens[n ~/ 10] : '${tens[n ~/ 10]}-${_numbers[n % 10]}';
}

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

/// Little words said alone, as a word to read: espeak reads them unstressed
/// ("the" as a quick "thuh", "is" swallowed) or British ("was" with the
/// "o" of "hot"). Stressed, with American vowels.
const Map<String, String> _sightStressed = {
  'and': '[[ˈand]]',
  'are': '[[ˈɑːɹ]]',
  'at': '[[ˈat]]',
  'for': '[[fˈɔːɹ]]',
  'from': '[[fɹˈʌm]]',
  'is': '[[ˈɪz]]',
  'it': '[[ˈɪt]]',
  'she': '[[ʃˈiː]]',
  'the': '[[ðˈʌ]]',
  'to': '[[tˈuː]]',
  'was': '[[wˈʌz]]',
  'we': '[[wˈiː]]',
  'what': '[[wˈʌt]]',
  'with': '[[wˈɪð]]',
  'you': '[[jˈuː]]',
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
  // To a hundred: Hundred Square asks for any of them.
  for (var n = 0; n <= 100; n++) {
    lines[numberClip(n)] = '${_cap(numberWord(n))}.';
  }
  for (var n = 1; n <= 100; n++) {
    lines[findNumberClip(n)] = 'Find the number ${numberWord(n)}.';
  }
  lines[VoiceLine.hundredHiding] = "It's hiding! Where does it go?";
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
  for (final l in kSpellLetters.split('')) {
    lines[soundClip(l)] = '${_sound(letterSound(l))}.';
  }
  for (final d in kDigraphs) {
    final sound = '[[${d.sound}]]';
    lines[soundClip(d.letters)] = '$sound.';
    lines[hearYesClip(d.letters)] = '${d.letters.toUpperCase().split('').join(', ')}. $sound, $sound, ${d.word}.';
  }
  for (final a in kHearAnswers) {
    final sound = a.length == 1 ? _sound(letterSound(a)) : '[[${digraphOf(a)!.sound}]]';
    lines[hearAskClip(a)] = a.length == 1 ? 'Which letter says $sound?' : 'Which letters say $sound?';
  }
  for (final w in kSightWords) {
    final two = w.contains(' ');
    final said = _sightStressed[w];
    lines[sightAskClip(w)] = 'Find the word${two ? 's' : ''}: ${said ?? w}.';
    lines[sightWordClip(w)] = '${said ?? _cap(w)}.';
  }
  lines[VoiceLine.balanceAsk] = 'Which side has more?';
  for (final (more, fewer) in kBalancePairs) {
    lines[balanceMoreClip(more, fewer)] = '${_cap(_numbers[more])} is more than ${_numbers[fewer]}.';
  }
  lines[compareAskClip(CompareAsk.more)] = 'Which bus has more kids?';
  lines[compareAskClip(CompareAsk.fewer)] = 'Which bus has fewer kids?';
  lines[compareAskClip(CompareAsk.order)] = 'Line up the buses. Fewest kids first!';
  lines[compareYesClip(CompareAsk.more)] = 'That bus has more kids!';
  lines[compareYesClip(CompareAsk.fewer)] = 'That bus has fewer kids!';
  lines[compareYesClip(CompareAsk.order)] = 'All lined up, from fewest to most!';
  lines[zooAskClip(ZooMode.own)] = 'Find your name!';
  lines[zooAskClip(ZooMode.family)] = 'Find the name I spell.';
  lines[zooAskClip(ZooMode.build)] = "Let's spell a name, letter by letter!";
  lines[zooYesClip(ZooMode.own)] = "That's your name! Thank you!";
  lines[zooYesClip(ZooMode.family)] = 'Thank you!';
  lines[zooYesClip(ZooMode.build)] = 'You spelled it! Thank you!';
  lines[VoiceLine.tallyStart] = 'Make a mark for each bunny!';
  lines[VoiceLine.tallyFive] = "Five bunnies already! Let's count on.";
  lines[VoiceLine.tallyTap] = 'Tap the board for the bunny.';
  lines[VoiceLine.tallyAsk] = 'How many marks?';
  for (var n = 1; n <= kTallyMax; n++) {
    lines[tallyBunniesClip(n)] = '${_cap(_numbers[n])} bunn${n == 1 ? 'y' : 'ies'}!';
  }
  lines[VoiceLine.freezeStart] = "Let's dance! When the music stops, freeze!";
  lines[VoiceLine.freezeStop] = 'Freeze!';
  lines[VoiceLine.freezeGo] = 'Dance!';
  lines[VoiceLine.freezeDone] = 'Great dancing!';
  for (final a in FreezeAnimal.values) {
    lines[freezeAnimalClip(a)] = a.line;
  }
  lines[VoiceLine.seqStart] = 'Tap the squares to make music!';
  for (final w in DressWeather.values) {
    lines[dressDayClip(w, pretend: false)] = '${w.line} What should Buddy wear?';
    lines[dressDayClip(w, pretend: true)] = "Let's pretend ${w.line.replaceFirst("It's", "it's").replaceFirst(' today', '')} What should Buddy wear?";
  }
  lines[dressSlotClip(DressSlot.top)] = 'What should Buddy wear on top?';
  lines[dressSlotClip(DressSlot.legs)] = 'And on the legs?';
  lines[dressSlotClip(DressSlot.feet)] = 'What shoes?';
  lines[dressSlotClip(DressSlot.extra)] = 'One more thing!';
  for (final i in DressItem.values) {
    lines[dressItemClip(i)] = i.line;
  }
  lines[VoiceLine.dressDone] = 'Ready to go outside!';
  for (final MapEntry(key: key, value: word) in kWhoWords.entries) {
    lines['who_$key'] = "Where's $word?";
  }
  lines['who_you'] = 'Where are you?';
  lines['who_doggy'] = "Where's the doggy?";
  lines['who_kitty'] = "Where's the kitty?";
  for (final story in kStoryBooks) {
    lines[story.titleClip] = '${story.title}.';
    for (final (i, page) in story.pages.indexed) {
      lines[story.pageClip(i)] = page.text;
    }
  }
  lines[VoiceLine.storyPick] = 'Pick a story!';
  lines[VoiceLine.storyEnd] = 'The end!';
  lines[VoiceLine.whoYes] = 'Yes! You found them!';
  lines[VoiceLine.whoYesYou] = "That's you!";
  for (var n = 1; n <= kCookiePlate; n++) {
    final cookies = '${numberWord(n)} cookie${n == 1 ? '' : 's'}';
    lines[cookieAskClip(n)] = 'I want $cookies!';
    lines[cookieYumClip(n)] = '${_cap(cookies)}! Yum, yum!';
    lines[cookieMoreClip(n)] = 'More, please! I want ${numberWord(n)}.';
    lines[cookieFewerClip(n)] = 'Too many! I want ${numberWord(n)}.';
  }
  for (final p in CountPart.values) {
    final (one, many) = kCountPartWords[p]!;
    String words(int n) => n == 1 ? 'one $one' : '${numberWord(n)} $many';
    for (var n = 1; n <= kCountPartMax[p]!; n++) {
      lines[ccountAskClip(p, n)] = 'Give it ${words(n)}!';
      lines[ccountYayClip(p, n)] = 'Yay! ${_cap(words(n))}!';
    }
    for (var n = 1; n <= 4; n++) {
      lines[ccountAndClip(p, n)] = 'And ${words(n)}!';
    }
    lines[ccountManyClip(p)] = 'Give it this many $many!';
    lines[ccountMoreClip(p)] = 'More $many, please!';
    lines[ccountFewerClip(p)] = 'Too many $many!';
  }
  lines[VoiceLine.ccountDance] = 'Then make it dance!';
  for (final l in kLetterSounds) {
    lines[letterMonsterAskClip(LetterMonsterRound(LetterMonsterAsk.name, l.letter, [l.letter]))] = 'I want the letter ${l.letter}!';
    if (l.starts) lines[letterMonsterAskClip(LetterMonsterRound(LetterMonsterAsk.sound, l.letter, [l.letter]))] = 'I want the letter that says ${_sound(l)}!';
  }
  for (var n = 1; n <= kBusStopMax; n++) {
    lines[busStartClip(n)] = n == 1 ? '${_cap(numberWord(n))} kid is on the bus.' : '${_cap(numberWord(n))} kids are on the bus.';
    lines[busNowClip(n)] = '${_cap(numberWord(n))} kid${n == 1 ? '' : 's'} on the bus!';
  }
  for (var n = 1; n <= 4; n++) {
    lines[busOnClip(n)] = n == 1 ? 'One more gets on!' : '${_cap(numberWord(n))} more get on!';
  }
  for (var n = 1; n <= 3; n++) {
    lines[busOffClip(n)] = n == 1 ? 'One gets off!' : '${_cap(numberWord(n))} get off!';
  }
  lines[VoiceLine.busStopAsk] = 'How many kids are on the bus now?';
  for (final n in kRocketStarts) {
    lines[rocketStartClip(n)] = 'Count down from ${numberWord(n)}!';
  }
  lines[VoiceLine.rocketBlastOff] = 'Zero! Blast off!';
  lines[VoiceLine.trainNext] = 'What comes next?';
  lines[VoiceLine.trainMissing] = 'Which letter is missing?';
  lines[VoiceLine.trainGo] = 'All aboard! Choo choo!';
  const lcAsk = {
    CreaturePart.body: 'a body that starts',
    CreaturePart.face: 'eyes that start',
    CreaturePart.top: 'something for the top that starts',
    CreaturePart.legs: 'legs that start',
    CreaturePart.arms: 'arms that start',
    CreaturePart.tail: 'a tail that starts',
  };
  for (final MapEntry(key: part, value: keys) in kCreatureSounds.entries) {
    for (final (option, word, letter) in keys) {
      final sound = _sound(letterSound(letter));
      lines[letterCreatureAskClip(LetterCreatureStep(part, option, [option]))] = 'Find ${lcAsk[part]} with $sound!';
      lines[letterCreatureYesClip(part, option)] = '$sound, $sound, $word!';
    }
  }
  lines['fish_biggest'] = 'Catch the biggest number!';
  lines['fish_five'] = 'Catch two fish that make five!';
  for (final (a, b) in kFivePairs) {
    lines[fishPairClip(a, b)] = '${_cap(numberWord(a))} and ${numberWord(b)} make five!';
  }
  lines[VoiceLine.cookiesBell] = 'Then ring the bell!';
  lines[VoiceLine.spellMissing] = 'Which sound is missing?';
  lines[VoiceLine.spellBuild] = "Let's build it, sound by sound!";
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
