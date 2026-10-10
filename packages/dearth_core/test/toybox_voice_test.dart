import 'dart:math';

import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

/// The Toybox's voice games (SPEC FR-TOY-03, Appendix B): Letter Sounds,
/// Rhyme Time, I Spy, letter, name and number tracing, Breathing Buddy, and
/// the voice lines they say.
void main() {
  /// Moves a finger through [points]; how the stroke ended, if it did.
  TraceEvent follow(Tracer t, Iterable<Point<double>> points) {
    for (final p in points) {
      final e = t.move(p);
      if (e == TraceEvent.strokeDone || e == TraceEvent.glyphDone) return e;
    }
    return TraceEvent.none;
  }

  group('words and letter sounds', () {
    test('every letter, rhyme and picture word is a picture with a word', () {
      for (final l in kLetterSounds) {
        expect(l.words, isNotEmpty);
        for (final w in l.words) {
          expect(kWordsByName, contains(w), reason: '${l.letter}: $w');
          if (l.starts) expect(w[0].toUpperCase(), l.letter, reason: '$w starts with ${l.letter}');
        }
      }
      for (final f in kRhymes) {
        for (final w in f.words) {
          expect(kWordsByName, contains(w));
        }
      }
      expect(kLetterSounds.map((l) => l.letter).join(), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ');
      expect({for (final w in kWords) w.word}.length, kWords.length, reason: 'no word twice');
      for (final w in kWords) {
        if (w.color != null) expect(kSpyColors, contains(w.color));
        if (w.shape != null) expect(kSpyShapes, contains(w.shape));
      }
    });

    test('FR-TOY-03 Letter Sounds: hear four, then find a letter, then a picture\'s first sound', () {
      for (var seed = 0; seed < 80; seed++) {
        final hear = letterRound(1, Random(seed), favorite: 'a');
        expect(hear.mode, LetterMode.hear);
        expect(hear.letters.toSet().length, 4);
        for (final (level, mode, n) in [(2, LetterMode.find, 2), (3, LetterMode.find, 3), (4, LetterMode.firstSound, 3), (5, LetterMode.firstSound, 4)]) {
          final r = letterRound(level, Random(seed), last: 'B');
          expect(r.mode, mode);
          expect(r.letters.length, n);
          expect(r.letters, contains(r.answer));
          expect(r.answer!.letter, isNot('B'), reason: 'not the same letter twice in a row');
          final others = [for (final l in r.letters) if (l != r.answer) l.letter];
          expect(others.where((o) => soundsClash(o, r.answer!.letter)), isEmpty, reason: 'C never next to K for a sound');
          if (mode == LetterMode.firstSound) {
            expect(r.answer!.words, contains(r.word!.word));
            expect(r.answer!.starts, isTrue, reason: 'X only ends words');
            expect(others, isNot(contains('X')));
          }
        }
      }
      // Her own initial turns up in the rounds she listens to.
      expect([for (var s = 0; s < 40; s++) letterRound(1, Random(s), favorite: 'z').letters.any((l) => l.letter == 'Z')].where((x) => x).length, greaterThan(15));
    });

    test('FR-TOY-03 Rhyme Time: one rhyme among words that rhyme with nothing there, 2 → 4 choices', () {
      for (var seed = 0; seed < 120; seed++) {
        for (var level = 1; level <= 3; level++) {
          final r = rhymeRound(level, Random(seed));
          expect(r.choices.length, level + 1);
          expect(r.choices, contains(r.match));
          final family = kRhymes.firstWhere((f) => f.words.first == r.anchor.word);
          expect(family.words, contains(r.match.word));
          final vowels = <String>{};
          for (final c in r.choices.where((c) => c != r.match)) {
            final f = kRhymes.firstWhere((f) => f.words.contains(c.word));
            expect(f.vowel, isNot(family.vowel), reason: '${c.word} vs ${r.anchor.word}');
            expect(vowels.add(f.words.first), isTrue, reason: 'two wrong choices rhyme with each other');
          }
        }
      }
    });

    test('FR-TOY-03 I Spy: colors, then shapes, then letters, and only one thing fits the clue', () {
      for (var seed = 0; seed < 120; seed++) {
        for (var level = 1; level <= 5; level++) {
          final r = spyRound(level, Random(seed));
          final (clue, count) = kSpyLevels[level - 1];
          expect(r.clue, clue);
          expect(r.things.length, count);
          expect(r.things, contains(r.answer));
          final fits = switch (clue) {
            SpyClue.color => r.things.where((t) => t.color == r.value),
            SpyClue.shape => r.things.where((t) => t.shape == r.value),
            SpyClue.letter => r.things.where((t) => soundsClash(t.word[0].toUpperCase(), r.value)),
          };
          expect(fits, [r.answer], reason: 'seed $seed level $level: ${r.things}');
          if (clue == SpyClue.color) expect(r.things.every((t) => t.color != null), isTrue, reason: 'a thing of no set color could be any');
          if (clue == SpyClue.shape) expect(r.things.every((t) => t.shape != null), isTrue);
        }
      }
    });
  });

  group('tracing', () {
    test('every letter, digit and pre-writing stroke has a glyph in its box, its points a step apart', () {
      final chars = [for (var c = 65; c <= 90; c++) String.fromCharCode(c), for (var c = 97; c <= 122; c++) String.fromCharCode(c), for (var d = 0; d <= 9; d++) '$d', ...kTraceLines, ...kTraceCurves];
      for (final c in chars) {
        final g = glyphFor(c);
        expect(g.strokes, isNotEmpty, reason: c);
        final capital = RegExp('^[A-Z0-9]\$').hasMatch(c);
        expect(g.top, greaterThanOrEqualTo(capital ? -0.01 : -0.01), reason: c);
        expect(g.bottom, lessThanOrEqualTo(capital ? 10.6 : 14.01), reason: c);
        expect(g.width, inInclusiveRange(0, 15.01), reason: c);
        for (final s in g.strokes) {
          for (var i = 1; i < s.length; i++) {
            expect(s[i].distanceTo(s[i - 1]), lessThanOrEqualTo(kTraceStep * 1.05), reason: '$c: a gap at point $i');
          }
        }
      }
      // Ball-and-stick, in writing order: A starts at its top, O goes
      // round from the top, i ends with its dot.
      expect(glyphFor('A').strokes.first.first, const Point(4.0, 0.0));
      expect(glyphFor('O').strokes.single.first.y, closeTo(0, 0.01));
      expect(glyphFor('i').strokes.last.length, 1);
      expect(glyphFor('g').bottom, greaterThan(13));
    });

    test('FR-TOY-03 tracing: the ink follows a finger along the path, never a scribble', () {
      final o = glyphFor('O');
      // Straight from the start to the end point (the same place): nothing.
      final t = Tracer(o);
      expect(t.down(o.strokes[0].first), TraceEvent.started);
      expect(t.move(o.strokes[0][o.strokes[0].length - 3]), anyOf(TraceEvent.moved, TraceEvent.none));
      expect(t.reached, lessThan(13), reason: 'no jumping the loop');
      // A touch away from the green dot doesn't start anything.
      final far = Tracer(o);
      expect(far.down(const Point(4.5, 5)), TraceEvent.none);
      // Following it all the way round finishes it.
      final round = Tracer(o);
      round.down(o.strokes[0].first);
      expect(follow(round, o.strokes[0].skip(1)), TraceEvent.glyphDone);
      expect(round.slips, 0);
    });

    test('wandering off pauses the ink and counts once; back on the path it carries on', () {
      final a = glyphFor('A');
      final t = Tracer(a);
      final s = a.strokes[0];
      t.down(s.first);
      for (final p in s.take(10)) {
        t.move(p);
      }
      final reached = t.reached;
      expect(t.move(const Point(8, 1)), TraceEvent.strayed);
      expect(t.move(const Point(8, 2)), TraceEvent.none);
      expect(t.slips, 1);
      expect(t.reached, reached);
      expect(t.move(s[reached]), anyOf(TraceEvent.moved, TraceEvent.none));
      expect(follow(t, s.skip(reached)), TraceEvent.strokeDone);
      expect(t.stroke, 1);
      // A's second stroke starts back at the top: lift and start again.
      t.up();
      expect(t.down(a.strokes[1].first), TraceEvent.started);
    });

    test('a dot is a tap; a stroke that starts where the last ended carries on', () {
      final i = glyphFor('i');
      final t = Tracer(i);
      t.down(i.strokes[0].first);
      for (final p in i.strokes[0].skip(1)) {
        t.move(p);
      }
      expect(t.stroke, 1);
      t.up();
      expect(t.down(i.strokes[1].single), TraceEvent.glyphDone);
      final b = glyphFor('B');
      final tb = Tracer(b);
      for (var s = 0; s < 2; s++) {
        tb.down(b.strokes[s].first);
        for (final p in b.strokes[s].skip(1)) {
          tb.move(p);
        }
      }
      expect(tb.stroke, 2);
      expect(tb.tracing, isTrue, reason: 'the second bump starts where the first ended');
    });

    test('FR-TOY-03 Letter & Name Tracing: lines → curves → capitals → her name; numbers 1–3 → 0–9', () {
      for (var seed = 0; seed < 40; seed++) {
        expect(kTraceLines, contains(letterTraceRound(1, Random(seed)).single));
        expect(kTraceCurves, contains(letterTraceRound(2, Random(seed)).single));
        expect(kStraightCapitals, contains(letterTraceRound(3, Random(seed), last: 'A').single));
        expect(letterTraceRound(3, Random(seed), last: 'A').single, isNot('A'));
        expect(letterTraceRound(4, Random(seed)).single, matches(RegExp(r'^[A-Z]$')));
        expect(letterTraceRound(5, Random(seed), name: 'Ava'), ['A', 'v', 'a']);
        expect(letterTraceRound(5, Random(seed), name: '李').single, matches(RegExp(r'^[A-Z]$')), reason: 'a capital when the name has no letters to trace');
        expect(numberTraceRound(1, Random(seed), last: 2), isIn([1, 3]));
        expect(numberTraceRound(3, Random(seed)), inInclusiveRange(0, 9));
      }
      expect(nameGlyphs('zoë-Lou'), ['Z', 'o', 'e', 'L', 'o', 'u']);
      expect(nameGlyphs('Maximilianus Jr'), hasLength(10));
    });
  });

  group('voice', () {
    test('every clip a game asks for has a line, and every id is a file name', () {
      final ids = kVoiceLines.keys.toSet();
      for (final id in ids) {
        expect(id, matches(RegExp(r'^[a-z0-9_]+$')));
        expect(kVoiceLines[id]!.trim(), isNotEmpty);
      }
      final asked = <String>[
        for (final w in kWords) w.clip,
        for (final l in kLetterSounds) ...[letterClip(l.letter), findLetterClip(l.letter), letterNameClip(l.letter)],
        for (final l in kLetterSounds.where((l) => l.starts))
          for (final w in l.words) ...[firstSoundClip(wordNamed(w)), firstSoundHintClip(wordNamed(w)), spyClip(SpyClue.letter, l.letter)],
        for (final f in kRhymes) ...[rhymeAskClip(f.anchor), for (final m in f.words.skip(1)) rhymeYesClip(f.anchor, wordNamed(m))],
        for (final c in kSpyColors) spyClip(SpyClue.color, c),
        for (final s in kSpyShapes) spyClip(SpyClue.shape, s),
        for (var n = 0; n <= 100; n++) numberClip(n),
        for (var n = 0; n <= 10; n++) countClip(n),
        for (var n = 1; n <= 100; n++) findNumberClip(n),
        VoiceLine.hundredHiding,
        VoiceLine.freezeStart, VoiceLine.freezeStop, VoiceLine.freezeGo, VoiceLine.freezeDone,
        for (final a in FreezeAnimal.values) freezeAnimalClip(a),
        VoiceLine.seqStart,
        for (final w in DressWeather.values) ...[dressDayClip(w, pretend: false), dressDayClip(w, pretend: true)],
        for (final s in DressSlot.values) dressSlotClip(s),
        for (final i in DressItem.values) dressItemClip(i),
        VoiceLine.dressDone,
        for (final key in kWhoWords.keys) 'who_$key',
        'who_you', 'who_doggy', 'who_kitty', VoiceLine.whoYes, VoiceLine.whoYesYou,
        for (final b in kStoryBooks) ...[b.titleClip, for (var i = 0; i < b.pages.length; i++) b.pageClip(i)],
        VoiceLine.storyPick, VoiceLine.storyEnd,
        VoiceLine.traceName, VoiceLine.traceNameDone, VoiceLine.breatheStart, VoiceLine.breatheIn, VoiceLine.breatheOut, VoiceLine.breatheDone,
        VoiceLine.makeCreature, VoiceLine.dotsNumbers, VoiceLine.dotsLetters,
        for (final p in kDotPictures) dotsDoneClip(p),
        for (final n in kCreatureNames) creatureNameClip(n),
        for (final p in CreaturePart.values)
          for (var i = 0; i < kCreatureOptions[p]!; i++) creaturePartClip(p, i),
        for (final c in kCreaturePaints) colorClip(c),
        VoiceLine.bigLittleStart, VoiceLine.bigLittleDone,
        for (final l in [...kLookAlikeLetters, ...kDifferentLetters, ...kMirrorLetters]) bigLittleClip(l),
        for (var level = 1; level <= 4; level++)
          for (var seed = 0; seed < 300; seed++) hopAskClip(hopRound(level, Random(seed))),
        for (var n = 0; n <= 10; n++) hopAskClip(HopRound(HopMode.find, 11, n == 0 ? 1 : 0, n)),
        for (var n = 0; n <= 9; n++) hopAskClip(HopRound(HopMode.oneMore, 11, n, n + 1)),
        for (var n = 1; n <= 10; n++) hopAskClip(HopRound(HopMode.oneLess, 11, n, n - 1)),
        for (final (from, more) in kHopSums) hopAskClip(HopRound(HopMode.add, 11, from, from + more)),
        for (final l in kSpellLetters.split('')) soundClip(l),
        VoiceLine.spellMissing, VoiceLine.spellBuild,
        for (final a in kHearAnswers) ...[hearAskClip(a), hearYesClip(a), soundClip(a)],
        for (final w in kSightWords) ...[sightAskClip(w), sightWordClip(w)],
        VoiceLine.balanceAsk,
        for (final (more, fewer) in kBalancePairs) balanceMoreClip(more, fewer),
        for (final a in CompareAsk.values) ...[compareAskClip(a), compareYesClip(a)],
        for (final m in ZooMode.values) ...[zooAskClip(m), zooYesClip(m)],
        VoiceLine.tallyStart, VoiceLine.tallyFive, VoiceLine.tallyTap, VoiceLine.tallyAsk,
        for (var n = 1; n <= kTallyMax; n++) tallyBunniesClip(n),
        for (var n = 1; n <= kCookiePlate; n++) ...[cookieAskClip(n), cookieYumClip(n), cookieMoreClip(n), cookieFewerClip(n)],
        VoiceLine.cookiesBell,
        for (final p in CountPart.values) ...[
          for (var n = 1; n <= kCountPartMax[p]!; n++) ...[ccountAskClip(p, n), ccountYayClip(p, n)],
          for (var n = 1; n <= 4; n++) ccountAndClip(p, n),
          ccountManyClip(p), ccountMoreClip(p), ccountFewerClip(p),
        ],
        VoiceLine.ccountDance,
        for (var n = 1; n <= 10; n++) ...[snackWantClip(n), snackThatsClip(n), snackYumClip(n)],
        VoiceLine.snackLook,
        for (var n = 1; n <= 10; n++) ...[fingersShowClip(n), fingersYayClip(n)],
        for (var n = 6; n <= 10; n++) fingersMakeClip(n),
        VoiceLine.fingersMore,
        VoiceLine.fingersFewer,
        VoiceLine.fingersFive,
        VoiceLine.fingersWhich,
        VoiceLine.fingersHighFive,
        for (var place = 1; place <= 5; place++) ...[raceAskClip(place), raceCameClip(place), racePlaceClip(place)],
        raceAskClip(0),
        VoiceLine.raceGo,
        for (var n = 1; n <= kBusStopMax; n++) ...[busStartClip(n), busNowClip(n)],
        for (var n = 1; n <= 4; n++) busOnClip(n),
        for (var n = 1; n <= 3; n++) busOffClip(n),
        VoiceLine.busStopAsk,
        for (final n in kRocketStarts) rocketStartClip(n),
        VoiceLine.rocketBlastOff,
        VoiceLine.trainNext, VoiceLine.trainMissing, VoiceLine.trainGo,
        fishAskClip(const FishRound(FishAsk.biggest, [1, 2, 3])), fishAskClip(const FishRound(FishAsk.makeFive, [2, 3, 1, 5])),
        for (final (a, b) in kFivePairs) fishPairClip(a, b),
        for (final MapEntry(key: part, value: keys) in kCreatureSounds.entries)
          for (final (option, _, _) in keys) ...[letterCreatureAskClip(LetterCreatureStep(part, option, [option])), letterCreatureYesClip(part, option)],
        for (final l in kLetterSounds) ...[
          letterMonsterAskClip(LetterMonsterRound(LetterMonsterAsk.name, l.letter, [l.letter])),
          if (l.starts) letterMonsterAskClip(LetterMonsterRound(LetterMonsterAsk.sound, l.letter, [l.letter])),
        ],
      ];
      expect(asked.where((a) => !ids.contains(a)), isEmpty);
      expect(ids.difference(asked.toSet()), isEmpty, reason: 'no line nothing says');
      // Letter sounds are phonemes the voice reads as such.
      expect(kVoiceLines[letterClip('B')], 'B. [[bˈʌ]], [[bˈʌ]], ball.');
      expect(kVoiceLines[letterClip('X')], 'X. Fox, box.');
      // "One" in American phonemes (espeak's rhymes with "on").
      expect(kVoiceLines[countClip(3)], '[[wˈʌn]], two, three.');
      // Z is "zee", capital or small (espeak's English says "zed").
      expect(kVoiceLines[bigLittleClip('z')], 'Big [[zˈiː]], little [[zˈiː]].');
      expect(kVoiceLines[hopAskClip(const HopRound(HopMode.add, 11, 3, 5))], 'Three and two more!');
      expect(kVoiceLines[hopAskClip(const HopRound(HopMode.oneLess, 11, 4, 3))], '[[wˈʌn]] less than four!');
      // A tile says its sound alone, the way Letter Sounds says it.
      expect(kVoiceLines[soundClip('m')], '[[mˈʌ]].');
      expect(kVoiceLines[hearAskClip('m')], 'Which letter says [[mˈʌ]]?');
      expect(kVoiceLines[hearAskClip('sh')], 'Which letters say [[ʃˈʌ]]?');
      expect(kVoiceLines[hearYesClip('sh')], 'S, H. [[ʃˈʌ]], [[ʃˈʌ]], shell.');
      // A little word read alone is stressed, with its American vowel.
      expect(kVoiceLines[sightAskClip('was')], 'Find the word: [[wˈʌz]].');
      expect(kVoiceLines[sightWordClip('the bus')], 'The bus.');
      expect(kVoiceLines[balanceMoreClip(3, 1)], 'Three is more than [[wˈʌn]].');
      expect(kVoiceLines[sightAskClip('the bus')], 'Find the words: the bus.');
    });

    test('every line has a measured clip, so a game can let it finish', () {
      // A new or renamed line needs tool/sounds/voice.py, which measures it.
      expect(kVoiceMs.keys.toSet(), kVoiceLines.keys.toSet());
      expect(kVoiceMs.values.every((ms) => ms > 150 && ms < 10000), isTrue);
      expect(afterVoice(letterClip('V')), greaterThan(Duration(milliseconds: kVoiceMs[letterClip('V')]!)));
      expect(afterVoice(numberClip(1), atLeast: const Duration(seconds: 2)), const Duration(seconds: 2));
    });

    test('Breathing Buddy: 3 → 5 breaths', () {
      expect([for (var l = 1; l <= 4; l++) breathsFor(l)], [3, 4, 5, 5]);
    });
  });
}
