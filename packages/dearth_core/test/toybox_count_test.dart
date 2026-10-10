import 'dart:math';

import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

/// The Toybox's third set, six number games built on her longest-played
/// games (SPEC FR-TOY-03, Appendix B): the rules of each game's rounds.
void main() {
  group('FR-TOY-03 Creature Count', () {
    test('the ladder: one part 1–3 with outlines, 1–5, two parts up to four, the numeral from three', () {
      for (var seed = 0; seed < 200; seed++) {
        for (var level = 1; level <= 4; level++) {
          final r = creatureCountRound(level, Random(seed));
          expect(kCountBodies, contains(r.body), reason: 'seed $seed level $level');
          expect(r.color, inInclusiveRange(0, 7));
          switch (level) {
            case 1:
              expect(r.asks, hasLength(1));
              expect(r.asks.single.n, inInclusiveRange(1, 3));
              expect(r.guides, isTrue, reason: 'level 1 shows where the parts go');
              expect(r.numeral, isFalse);
            case 2:
              expect(r.asks, hasLength(1));
              final a = r.asks.single;
              expect(a.n, inInclusiveRange(1, min(5, kCountPartMax[a.part]!)));
              expect(r.guides, isFalse);
            case 3:
              expect(r.asks, hasLength(2));
              expect(r.asks[0].part, isNot(r.asks[1].part), reason: 'two different parts');
              for (final a in r.asks) {
                expect(a.n, inInclusiveRange(1, 4));
              }
            default:
              expect(r.asks, hasLength(1));
              final a = r.asks.single;
              expect(r.numeral, isTrue);
              expect(a.n, inInclusiveRange(3, kCountPartMax[a.part]!), reason: 'the numeral from three to the part\'s max');
          }
          for (final a in r.asks) {
            expect(a.n, lessThanOrEqualTo(kCountPartMax[a.part]!), reason: 'every ask fits on the body');
          }
        }
      }
    });

    test('never the same first ask twice in a row', () {
      for (var level = 1; level <= 4; level++) {
        CreatureCountRound? last;
        for (var i = 0; i < 200; i++) {
          final r = creatureCountRound(level, Random(level * 1000 + i), last: last);
          if (last != null) {
            expect((r.asks.first.part, r.asks.first.n), isNot((last.asks.first.part, last.asks.first.n)), reason: 'level $level round $i');
          }
          last = r;
        }
      }
    });

    test('a wrong dance is helped once, then a miss', () {
      expect([for (var slips = 0; slips <= 3; slips++) creatureCountResult(slips)], [GameResult.win, GameResult.helped, GameResult.miss, GameResult.miss]);
    });

    test('labels: "3 eyes", "1 eye"', () {
      expect(countPartLabel(CountPart.eyes, 3), '3 eyes');
      expect(countPartLabel(CountPart.eyes, 1), '1 eye');
      expect(countPartLabel(CountPart.spots, 9), '9 spots');
      expect(countPartLabel(CountPart.legs, 1), '1 leg');
    });
  });

  group('FR-TOY-03 Snack Snap', () {
    test('the ladder: rows 1–3, dice 1–6, ten-frames 5–10, then the flash', () {
      for (var seed = 0; seed < 200; seed++) {
        for (var level = 1; level <= 4; level++) {
          final r = snackRound(level, Random(seed));
          final ns = [for (final p in r.plates) p.n];
          expect(ns.toSet().length, ns.length, reason: 'distinct amounts');
          expect(ns, contains(r.want));
          expect(r.plates.where((p) => p.n == r.want).length, 1, reason: 'exactly one plate equals the want');
          expect(r.answer, greaterThanOrEqualTo(0));
          switch (level) {
            case 1:
              expect(ns..sort(), [1, 2, 3], reason: 'exactly one, two and three');
              expect(r.plates.every((p) => p.pattern == SnackPattern.row), isTrue);
              expect(r.flash, isFalse);
            case 2:
              expect(r.want, inInclusiveRange(1, 6));
              expect(ns, everyElement(inInclusiveRange(1, 6)));
              expect(r.plates, hasLength(3));
              expect(r.plates.every((p) => p.pattern == SnackPattern.dice), isTrue);
              expect(r.flash, isFalse);
            case 3:
              expect(r.want, inInclusiveRange(5, 10));
              expect(ns, everyElement(inInclusiveRange(5, 10)));
              expect(r.plates, hasLength(4));
              expect(r.plates.every((p) => p.pattern == SnackPattern.frame), isTrue);
              expect(ns.any((n) => (n - r.want).abs() == 1), isTrue, reason: 'a neighbor beside the want');
              expect(r.flash, isFalse);
            default:
              expect(r.want, inInclusiveRange(1, 6));
              expect(ns, everyElement(inInclusiveRange(1, 6)));
              expect(r.plates, hasLength(4));
              expect(r.plates.every((p) => p.pattern == SnackPattern.row || p.pattern == SnackPattern.dice), isTrue);
              expect(r.flash, isTrue, reason: 'only the top level flashes');
          }
        }
      }
    });

    test('never the same want twice in a row', () {
      for (var level = 1; level <= 4; level++) {
        SnackRound? last;
        for (var i = 0; i < 200; i++) {
          final r = snackRound(level, Random(level * 1000 + i), last: last);
          if (last != null) {
            expect(r.want, isNot(last.want), reason: 'level $level round $i');
          }
          last = r;
        }
      }
    });

    test('dots: the right number, all on the plate, no two in one place', () {
      for (final pattern in SnackPattern.values) {
        for (var n = 1; n <= 10; n++) {
          final dots = snackDots(SnackPlate(n, pattern));
          expect(dots, hasLength(n), reason: '$pattern $n');
          for (final (x, y) in dots) {
            expect(x, inInclusiveRange(0, 1));
            expect(y, inInclusiveRange(0, 1));
          }
          expect(dots.toSet().length, n, reason: '$pattern $n');
        }
      }
      // Dice are the faces everyone knows.
      expect(snackDots(const SnackPlate(1, SnackPattern.dice)), [(0.5, 0.5)]);
      expect(snackDots(const SnackPlate(6, SnackPattern.dice)), hasLength(6));
      // The frame fills the top row first.
      expect(snackDots(const SnackPlate(5, SnackPattern.frame)).last, (0.9, 0.3));
      expect(snackDots(const SnackPlate(6, SnackPattern.frame))[5], (0.1, 0.7));
    });

    test('a wrong plate is helped once, then a miss; a peek can\'t be a clean win', () {
      expect([for (var slips = 0; slips <= 3; slips++) snackResult(slips)], [GameResult.win, GameResult.helped, GameResult.miss, GameResult.miss]);
      expect(snackResult(0, peeked: true), GameResult.helped);
      expect(snackResult(1, peeked: true), GameResult.helped);
      expect(snackResult(2, peeked: true), GameResult.miss);
    });
  });
}
