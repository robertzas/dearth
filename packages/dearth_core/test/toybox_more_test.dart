import 'dart:math';

import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

/// The Toybox's second set of number and letter games (SPEC FR-TOY-03,
/// Appendix B), built on the games the family's kid plays most.
void main() {
  group('Cookie Count', () {
    test('FR-TOY-03: 1–5 with spots → 2–5 → 5–10 → a plate that starts one to three off', () {
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        for (var level = 1; level <= gameById('cookies')!.levels; level++) {
          final r = cookieRound(level, rng);
          final why = 'seed $seed, level $level: want ${r.want}, start ${r.start}';
          final (lo, hi) = switch (level) { 1 => (1, 5), 2 => (2, 5), 3 => (5, 10), _ => (3, 10) };
          expect(r.want, inInclusiveRange(lo, hi), reason: why);
          expect(r.spots, level == 1, reason: why);
          if (level < 4) {
            expect(r.start, 0, reason: why);
          } else {
            expect((r.start - r.want).abs(), inInclusiveRange(1, 3), reason: 'too few or too many, never right ($why)');
            expect(r.start, inInclusiveRange(1, kCookiePlate), reason: why);
          }
        }
      }
    });

    test('every number comes up, the top level both adds and takes away, and never the same number twice running', () {
      final seen = <int>{};
      var over = 0, under = 0;
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        CookieRound? last;
        for (var i = 0; i < 6; i++) {
          final r = cookieRound(4, rng, last: last);
          if (last != null) expect(r.want, isNot(last.want));
          last = r;
          seen.add(r.want);
          r.start > r.want ? over++ : under++;
        }
      }
      expect(seen, {for (var n = 3; n <= 10; n++) n});
      expect(over, greaterThan(300));
      expect(under, greaterThan(300));
    });

    test('slips: the right plate first time is a win, one wrong ring is helped, then a miss', () {
      expect([for (var s = 0; s <= 2; s++) cookieResult(s)], [GameResult.win, GameResult.helped, GameResult.miss]);
    });

    test('the monster can ask for, praise and correct every number on the plate', () {
      for (var n = 1; n <= kCookiePlate; n++) {
        for (final clip in [cookieAskClip(n), cookieYumClip(n), cookieMoreClip(n), cookieFewerClip(n)]) {
          expect(kVoiceLines, contains(clip));
        }
      }
      expect(kVoiceLines[cookieAskClip(1)], 'I want [[wˈʌn]] cookie!');
      expect(kVoiceLines[cookieAskClip(5)], 'I want five cookies!');
    });
  });

  group('Letter Monster', () {
    test('FR-TOY-03: capitals by name (3) → small letters by name (4) → by sound (4) → a picture\'s first sound (5)', () {
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        for (var level = 1; level <= gameById('lettermonster')!.levels; level++) {
          final r = letterMonsterRound(level, rng);
          final why = 'seed $seed, level $level: ${r.letter} in ${r.choices}';
          expect(r.ask, LetterMonsterAsk.values[level - 1], reason: why);
          expect(r.choices, hasLength(switch (level) { 1 => 3, 4 => 5, _ => 4 }), reason: why);
          expect(r.choices.toSet(), hasLength(r.choices.length), reason: 'never two the same ($why)');
          expect(r.choices, contains(r.letter), reason: why);
          expect(r.small, level > 1, reason: why);
          expect(kVoiceLines, contains(letterMonsterAskClip(r)), reason: why);
          if (r.ask == LetterMonsterAsk.picture) {
            expect(r.word, isNotNull, reason: why);
            expect(kLetterSounds.firstWhere((l) => l.letter == r.letter).words, contains(r.word!.word), reason: why);
          }
          if (level >= 3) {
            String sound(String c) => kLetterSounds.firstWhere((l) => l.letter == c).sound;
            expect(r.choices.map(sound).toSet(), hasLength(r.choices.length), reason: 'no two biscuits make one sound, like C and K ($why)');
            expect(r.letter, isNot('X'), reason: 'X\'s sound ends its words');
          }
        }
      }
    });

    test('the first level never puts look-alikes side by side; small letters bring their mirror twin', () {
      const twins = [{'B', 'D'}, {'P', 'Q'}, {'M', 'W'}, {'E', 'F'}, {'U', 'V'}];
      var mirrored = 0;
      for (var seed = 0; seed < 300; seed++) {
        final one = letterMonsterRound(1, Random(seed));
        for (final t in twins) {
          expect(one.choices.where(t.contains).length, lessThan(2), reason: '${one.choices}');
        }
        final two = letterMonsterRound(2, Random(seed));
        if (two.letter == 'B') {
          expect(two.choices, contains('D'));
          mirrored++;
        }
      }
      expect(mirrored, greaterThan(0));
    });

    test('every letter comes up, never the same one twice running', () {
      final seen = <String>{};
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        LetterMonsterRound? last;
        for (var i = 0; i < 5; i++) {
          final r = letterMonsterRound(1, rng, last: last);
          if (last != null) expect(r.letter, isNot(last.letter));
          last = r;
          seen.add(r.letter);
        }
      }
      expect(seen, hasLength(26));
    });

    test('slips: right first time is a win, one slip helped, then a miss', () {
      expect([for (var s = 0; s <= 2; s++) letterMonsterResult(s)], [GameResult.win, GameResult.helped, GameResult.miss]);
      expect(kVoiceLines['lmon_want_b'], 'I want the letter B!');
      expect(kVoiceLines['lmon_says_b'], 'I want the letter that says [[bˈʌ]]!');
    });
  });

  group('Bus Stop', () {
    test('FR-TOY-03: get on, to five → get on, to ten → get off → off, then on', () {
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        for (var level = 1; level <= gameById('busstop')!.levels; level++) {
          final r = busStopRound(level, rng);
          final why = 'seed $seed, level $level: ${r.start} -${r.off} +${r.on} in ${r.choices}';
          expect(r.mode, switch (level) { 1 || 2 => BusStopMode.on, 3 => BusStopMode.off, _ => BusStopMode.both }, reason: why);
          expect(r.answer, inInclusiveRange(1, level == 1 ? 5 : kBusStopMax), reason: why);
          expect(r.start, inInclusiveRange(1, kBusStopMax), reason: why);
          expect(r.on > 0, r.mode != BusStopMode.off, reason: why);
          expect(r.off > 0, r.mode != BusStopMode.on, reason: why);
          expect(r.on, lessThanOrEqualTo(4), reason: 'a voice line for each ($why)');
          expect(r.off, lessThanOrEqualTo(3), reason: why);
          expect(r.choices, hasLength(3), reason: why);
          expect(r.choices.toSet(), hasLength(3), reason: why);
          expect(r.choices, contains(r.answer), reason: why);
          if (r.start != r.answer) expect(r.choices, contains(r.start), reason: 'forgetting the change is the decoy ($why)');
          expect(r.choices.every((c) => c >= 0 && c <= kBusStopMax), isTrue, reason: why);
        }
      }
    });

    test('never the same story twice running; slips are counting slips', () {
      for (var seed = 0; seed < 100; seed++) {
        final rng = Random(seed);
        BusStopRound? last;
        for (var i = 0; i < 6; i++) {
          final r = busStopRound(4, rng, last: last);
          if (last != null) expect((r.start, r.on, r.off), isNot((last.start, last.on, last.off)));
          last = r;
        }
      }
      expect([for (var s = 0; s <= 2; s++) busStopResult(s)], [GameResult.win, GameResult.helped, GameResult.miss]);
      expect(kVoiceLines[busStartClip(1)], '[[wˈʌn]] kid is on the bus.');
      expect(kVoiceLines[busOnClip(2)], 'Two more get on!');
    });
  });

  group('Word Pop', () {
    test('FR-TOY-03: Sight Words\' lists, more bubbles and quicker as it climbs', () {
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        for (var level = 1; level <= gameById('wordpop')!.levels; level++) {
          final r = wordPopRound(level, rng);
          final why = 'seed $seed, level $level: ${r.word} in ${r.words}';
          final pool = switch (level) { 1 => kSightTwo, 2 => kSightThree, _ => kSightFour };
          expect(r.words.every(pool.contains), isTrue, reason: why);
          expect(r.words, contains(r.word), reason: why);
          expect(r.words.toSet(), hasLength(r.words.length), reason: why);
          expect(r.words, hasLength(switch (level) { 1 => 3, 4 => 5, _ => 4 }), reason: why);
          expect(r.bubbles, greaterThan(r.words.length), reason: why);
          for (final w in r.words) {
            expect(kVoiceLines, contains(sightWordClip(w)), reason: 'every bubble reads itself ($why)');
          }
          expect(kVoiceLines, contains(sightAskClip(r.word)), reason: why);
        }
      }
      expect([for (var l = 1; l <= 4; l++) wordPopRound(l, Random(1)).speed], orderedEquals([...[for (var l = 1; l <= 4; l++) wordPopRound(l, Random(1)).speed]]..sort()));
    });

    test('there are always two bubbles to find, never more than three; otherwise a quarter carry the word', () {
      final r = wordPopRound(2, Random(3));
      final rng = Random(5);
      expect([for (var i = 0; i < 50; i++) wordPopNext(r, 1, rng)].every((w) => w == r.word), isTrue);
      final picks = [for (var i = 0; i < 3000; i++) wordPopNext(r, 2, rng)];
      expect(picks.where((w) => w == r.word).length, inInclusiveRange(600, 900));
      expect(picks.toSet(), r.words.toSet());
      expect([for (var i = 0; i < 200; i++) wordPopNext(r, 3, rng)], everyElement(isNot(r.word)));
      expect([for (var s = 0; s <= 4; s++) wordPopResult(s)], [GameResult.win, GameResult.win, GameResult.helped, GameResult.helped, GameResult.miss]);
    });

    test('never the same word twice running', () {
      for (var seed = 0; seed < 100; seed++) {
        final rng = Random(seed);
        String? last;
        for (var i = 0; i < 5; i++) {
          final r = wordPopRound(3, rng, last: last);
          expect(r.word, isNot(last));
          last = r.word;
        }
      }
    });
  });

  group('Rocket Countdown', () {
    test('FR-TOY-03: from five → from ten → from 11–15 → from twenty, always down to one', () {
      for (var seed = 0; seed < 100; seed++) {
        final rng = Random(seed);
        for (var level = 1; level <= gameById('rocket')!.levels; level++) {
          final r = rocketRound(level, rng);
          final why = 'seed $seed, level $level: from ${r.start}';
          expect(r.start, switch (level) { 1 => 5, 2 => 10, 3 => inInclusiveRange(11, 15), _ => 20 }, reason: why);
          expect(r.countdown, [for (var n = r.start; n >= 1; n--) n], reason: why);
          expect(kRocketStarts, contains(r.start), reason: why);
          expect(kVoiceLines, contains(rocketStartClip(r.start)), reason: why);
          for (final n in r.countdown) {
            expect(kVoiceLines, contains(numberClip(n)), reason: why);
            expect(kVoiceLines, contains(findNumberClip(n)), reason: 'the hint asks for it ($why)');
          }
        }
      }
      expect(kVoiceLines[rocketStartClip(10)], 'Count down from ten!');
    });

    test('the teens never start at the same number twice running; long countdowns allow two slips', () {
      for (var seed = 0; seed < 100; seed++) {
        final rng = Random(seed);
        RocketRound? last;
        for (var i = 0; i < 5; i++) {
          final r = rocketRound(3, rng, last: last);
          if (last != null) expect(r.start, isNot(last.start));
          last = r;
        }
      }
      expect([for (var s = 0; s <= 4; s++) rocketResult(const RocketRound(10), s)], [GameResult.win, GameResult.win, GameResult.helped, GameResult.helped, GameResult.miss]);
      expect([for (var s = 0; s <= 2; s++) rocketResult(const RocketRound(20), s)], [GameResult.win, GameResult.win, GameResult.win]);
    });
  });

  group('Alphabet Train', () {
    test('FR-TOY-03: the next of three capitals → a missing one of four → small letters, five → two gaps', () {
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        for (var level = 1; level <= gameById('train')!.levels; level++) {
          final r = trainRound(level, rng);
          final why = 'seed $seed, level $level: ${r.letters} gaps ${r.gaps} blocks ${r.choices}';
          expect(r.letters, hasLength(switch (level) { 1 => 3, 2 => 4, _ => 5 }), reason: why);
          expect(kAlphabet, contains(r.letters.join()), reason: 'in ABC order ($why)');
          expect(r.gaps, hasLength(level == 4 ? 2 : 1), reason: why);
          expect(r.gaps.contains(0), isFalse, reason: 'the first carriage always shows where it starts ($why)');
          expect(r.ask, level == 1 ? TrainAsk.next : isIn(TrainAsk.values), reason: why);
          expect(r.small, level >= 3, reason: why);
          expect(r.choices, hasLength(level <= 2 ? 3 : 4), reason: why);
          expect(r.choices.toSet(), hasLength(r.choices.length), reason: why);
          for (final g in r.gaps) {
            expect(r.choices, contains(r.letters[g]), reason: why);
          }
          final shown = [for (var i = 0; i < r.letters.length; i++) if (!r.gaps.contains(i)) r.letters[i]];
          expect(r.choices.any(shown.contains), isFalse, reason: 'no block repeats a letter on the train ($why)');
        }
      }
    });

    test('starts move around the alphabet; slips: one gap is a counting slip, two gaps allow one', () {
      final starts = <String>{};
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        TrainRound? last;
        for (var i = 0; i < 4; i++) {
          final r = trainRound(2, rng, last: last);
          if (last != null) expect(r.letters.first, isNot(last.letters.first));
          last = r;
          starts.add(r.letters.first);
        }
      }
      expect(starts.length, greaterThan(20));
      const one = TrainRound(['A', 'B', 'C'], [2], ['C', 'D', 'E'], small: false), two = TrainRound(['A', 'B', 'C', 'D', 'E'], [1, 3], ['B', 'D', 'F', 'G'], small: true);
      expect([for (var s = 0; s <= 2; s++) trainResult(one, s)], [GameResult.win, GameResult.helped, GameResult.miss]);
      expect([for (var s = 0; s <= 2; s++) trainResult(two, s)], [GameResult.win, GameResult.win, GameResult.helped]);
    });
  });

  group('Number Fishing', () {
    test('FR-TOY-03: 1–5 among three → 6–20 with a look-alike → the biggest of three → two that make five', () {
      for (var seed = 0; seed < 300; seed++) {
        final rng = Random(seed);
        for (var level = 1; level <= gameById('fishing')!.levels; level++) {
          final r = fishRound(level, rng);
          final why = 'seed $seed, level $level: ${r.ask} ${r.fish} target ${r.target}';
          expect(r.ask, switch (level) { 1 || 2 => FishAsk.find, 3 => FishAsk.biggest, _ => FishAsk.makeFive }, reason: why);
          expect(r.fish, hasLength(switch (level) { 1 || 3 => 3, _ => 4 }), reason: why);
          expect(r.fish.toSet(), hasLength(r.fish.length), reason: why);
          expect(kVoiceLines, contains(fishAskClip(r)), reason: why);
          switch (level) {
            case 1:
              expect(r.fish.every((n) => n >= 1 && n <= 5), isTrue, reason: why);
            case 2:
              expect(r.target, inInclusiveRange(6, 20), reason: why);
              expect(r.fish.every((n) => n >= 1 && n <= 20), isTrue, reason: why);
              final twin = r.target! >= 10 ? r.target! % 10 : r.target! + 10;
              if (twin >= 1) expect(r.fish, contains(twin), reason: 'a fish that shares a digit ($why)');
            case 3:
              final s = [...r.fish]..sort();
              expect(s[2] - s[1], greaterThanOrEqualTo(2), reason: why);
            default:
              expect(r.catches, hasLength(2), reason: 'exactly one pair makes five ($why)');
              expect(r.catches.reduce((a, b) => a + b), 5, reason: why);
          }
          for (final n in r.fish) {
            expect(kVoiceLines, contains(numberClip(n)), reason: why);
          }
        }
      }
      expect(kVoiceLines[fishPairClip(3, 2)], 'Two and three make five!');
      expect(kVoiceLines[fishPairClip(0, 5)], 'Zero and five make five!');
    });

    test('slips: one fish is a counting round; a pair allows one slip', () {
      const one = FishRound(FishAsk.find, [1, 2, 3], target: 2), two = FishRound(FishAsk.makeFive, [2, 3, 1, 5]);
      expect([for (var s = 0; s <= 2; s++) fishResult(one, s)], [GameResult.win, GameResult.helped, GameResult.miss]);
      expect([for (var s = 0; s <= 2; s++) fishResult(two, s)], [GameResult.win, GameResult.win, GameResult.helped]);
      expect(two.catches, {2, 3});
    });
  });

  group('Letter Creatures', () {
    test('FR-TOY-03: body and eyes (3 to choose) → top and legs too → arms and tail too (4 to choose)', () {
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        for (var level = 1; level <= gameById('lettercreature')!.levels; level++) {
          final r = letterCreatureRound(level, rng);
          final why = 'seed $seed, level $level';
          expect([for (final s in r.steps) s.part], creatureParts(level), reason: why);
          expect(r.color, lessThan(creatureColors(level)), reason: why);
          for (final s in r.steps) {
            expect(s.choices, hasLength(level >= 3 ? 4 : 3), reason: why);
            expect(s.choices, contains(s.answer), reason: why);
            final letters = [for (final c in s.choices) kCreatureSounds[s.part]!.firstWhere((k) => k.$1 == c).$3];
            expect(letters.toSet(), hasLength(letters.length), reason: 'every choice starts with its own sound ($why)');
            expect(kVoiceLines, contains(letterCreatureAskClip(s)), reason: why);
            expect(kVoiceLines, contains(letterCreatureYesClip(s.part, s.answer)), reason: why);
            for (final c in s.choices) {
              expect(kVoiceLines, contains(creaturePartClip(s.part, c)), reason: 'a wrong one says its name ($why)');
            }
          }
          expect(kVoiceLines, contains(creatureClip(r.creature)), reason: why);
        }
      }
    });

    test('every key word starts with its letter, and the creature\'s name for each part says that word', () {
      for (final MapEntry(key: part, value: keys) in kCreatureSounds.entries) {
        for (final (option, word, letter) in keys) {
          expect(word[0].toUpperCase(), letter);
          expect(kCreaturePartWords[part]![option], contains(word), reason: '$part $option');
          expect(option, lessThan(kCreatureOptions[part]!));
        }
      }
      expect(kVoiceLines[letterCreatureAskClip(const LetterCreatureStep(CreaturePart.body, 0, [0]))], 'Find a body that starts with [[ɹˈʌ]]!');
      expect(kVoiceLines[letterCreatureYesClip(CreaturePart.top, 2)], '[[bˈʌ]], [[bˈʌ]], bunny!');
      final r = letterCreatureRound(3, Random(1));
      expect([for (var s = 0; s <= 7; s++) letterCreatureResult(r, s)], [...List.filled(4, GameResult.win), ...List.filled(4, GameResult.helped)]);
    });
  });
}
