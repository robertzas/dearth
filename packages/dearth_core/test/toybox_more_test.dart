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
}
