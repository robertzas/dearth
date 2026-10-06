import 'dart:math';

import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

/// The Toybox's number and letter games (SPEC FR-TOY-03, Appendix B).
void main() {
  group('Dot-to-Dot', () {
    test('FR-TOY-03: 1→5, 1→10, 1→15, 1→20, then A→M and A→Z', () {
      expect(dotLabels(1), ['1', '2', '3', '4', '5']);
      expect(dotLabels(2), hasLength(10));
      expect(dotLabels(2).last, '10');
      expect(dotLabels(3).length, 15);
      expect(dotLabels(4).last, '20');
      expect(dotLabels(5), hasLength(13));
      expect(dotLabels(5).first, 'A');
      expect(dotLabels(5).last, 'M');
      expect(dotLabels(6), hasLength(26));
      expect(dotLabels(6).last, 'Z');
      for (final labels in [for (var l = 1; l <= 6; l++) dotLabels(l)]) {
        // In order and without repeats, so "number three" or "letter E" is
        // always findable.
        expect(labels.toSet().length, labels.length);
      }
    });

    test('a round never repeats a recent picture, and every picture has every level', () {
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        var recent = <String>[];
        for (var level = 1; level <= 6; level++) {
          final r = dotsRound(level, rng, recent: recent);
          expect(r.labels, dotLabels(level));
          expect(r.picture.id, isNot(isIn(recent)), reason: 'seed $seed level $level must not reuse a recent picture');
          recent = [r.picture.id, ...recent].take(4).toList();
        }
      }
      // With everything recent it still deals a round.
      final r = dotsRound(1, Random(1), recent: [for (final p in kDotPictures) p.id]);
      expect(kDotPictures, contains(r.picture));
    });

    test('every picture says "It\'s a/an …!", with the right article', () {
      for (final p in kDotPictures) {
        expect(kVoiceLines[dotsDoneClip(p)], "It's ${p.phrase}!");
        final noun = p.phrase.replaceFirst(RegExp('^(an?|the) '), '');
        final article = RegExp('^[aeiou]').hasMatch(noun.toLowerCase()) ? 'an' : 'a';
        expect(p.phrase, anyOf(startsWith('$article '), startsWith('the ')), reason: '${p.id} wants "$article $noun"');
      }
      expect(kDotPictures.map((p) => p.id).toSet(), hasLength(kDotPictures.length), reason: 'no two pictures share an id');
    });

    test('slips: one spare slip and one more per ten dots, then helped, then a miss', () {
      expect(dotsResult(0, 5), GameResult.win);
      expect(dotsResult(1, 5), GameResult.win);
      expect(dotsResult(2, 5), GameResult.helped);
      expect(dotsResult(4, 5), GameResult.miss);
      expect(dotsResult(1, 10), GameResult.win);
      expect(dotsResult(2, 20), GameResult.win);
      expect(dotsResult(5, 20), GameResult.helped);
      expect(dotsResult(8, 26), GameResult.miss);
      expect(dotsResult(0, 26), GameResult.win);
    });
  });

  group('Big & Little Letters', () {
    test('FR-TOY-03: 3 look-alike pairs → 5 pairs that look different → b, d, p and q', () {
      expect({...kLookAlikeLetters, ...kDifferentLetters, ...kMirrorLetters}, hasLength(26), reason: 'every letter, once');
      for (final l in [...kLookAlikeLetters, ...kDifferentLetters, ...kMirrorLetters]) {
        expect(hasGlyph(l) && hasGlyph(l.toUpperCase()), isTrue, reason: l);
      }
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        for (final (level, pool, n) in [(1, kLookAlikeLetters, 3), (2, kDifferentLetters, 5), (3, kMirrorLetters, 4)]) {
          final r = bigLittleRound(level, rng);
          expect(r.letters, hasLength(n), reason: 'seed $seed, level $level');
          expect(r.letters.toSet(), hasLength(n), reason: 'no letter twice');
          expect(pool, containsAll(r.letters));
          expect(r.tray.toSet(), r.letters.toSet(), reason: 'a small letter for every capital');
          for (var i = 0; i < n; i++) {
            expect(r.tray[i], isNot(r.letters[i]), reason: 'seed $seed: ${r.tray[i]} starts under its own capital');
          }
        }
      }
    });

    test('a new round never deals the same letters again', () {
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        for (var level = 1; level <= 3; level++) {
          final a = bigLittleRound(level, rng);
          final b = bigLittleRound(level, rng, last: a.letters);
          if (level < 3) {
            expect(b.letters.toSet().containsAll(a.letters), isFalse, reason: 'seed $seed, level $level');
          } else {
            expect(b.letters, isNot(a.letters), reason: 'the mirror four come in a new order');
          }
        }
      }
    });

    test('slips: three pairs want none for a win; four or five allow one', () {
      expect(bigLittleResult(0, pairs: 3), GameResult.win);
      expect(bigLittleResult(1, pairs: 3), GameResult.helped);
      expect(bigLittleResult(1, pairs: 5), GameResult.win);
      expect(bigLittleResult(1, pairs: 4), GameResult.win);
      expect(bigLittleResult(3, pairs: 4), GameResult.helped);
      expect(bigLittleResult(4, pairs: 5), GameResult.miss);
    });
  });

  group('Frog Hop', () {
    test('FR-TOY-03: pads 0–5 → 0–10 → one more or one less → adding 1–3 more', () {
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        for (var level = 1; level <= 4; level++) {
          final r = hopRound(level, rng);
          final why = 'seed $seed, level $level';
          expect(r.pads, level == 1 ? 6 : 11, reason: why);
          expect(r.from, inInclusiveRange(0, r.pads - 1), reason: why);
          expect(r.target, inInclusiveRange(0, r.pads - 1), reason: why);
          expect(r.target, isNot(r.from), reason: 'the frog never starts on the answer ($why)');
          switch (level) {
            case 1 || 2:
              expect(r.mode, HopMode.find, reason: why);
            case 3:
              expect(r.mode, isIn([HopMode.oneMore, HopMode.oneLess]), reason: why);
              expect(r.target - r.from, r.mode == HopMode.oneMore ? 1 : -1, reason: why);
            default:
              expect(r.mode, HopMode.add, reason: why);
              expect(r.hops, inInclusiveRange(1, 3), reason: why);
              expect(r.from, greaterThan(0), reason: why);
              expect(r.target, lessThanOrEqualTo(10), reason: why);
          }
        }
      }
    });

    test('every pad, both neighbours and every sum come up; never the same target twice running', () {
      final seen = <String>{};
      for (var seed = 0; seed < 400; seed++) {
        final rng = Random(seed);
        int? last;
        for (var level = 1; level <= 4; level++) {
          for (var i = 0; i < 3; i++) {
            final r = hopRound(level, rng, last: last);
            if (i > 0) expect(r.target, isNot(last), reason: 'seed $seed, level $level');
            last = r.target;
            seen.add(hopAskClip(r));
          }
          last = null;
        }
      }
      expect(seen, hasLength(11 + 10 + 10 + kHopSums.length));
      expect(kHopSums, hasLength(9 + 8 + 7));
    });

    test('slips: right first time is a win, one slip is helped, then a miss', () {
      expect([for (var s = 0; s <= 2; s++) hopResult(s)], [GameResult.win, GameResult.helped, GameResult.miss]);
    });
  });
}
