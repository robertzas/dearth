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
}
