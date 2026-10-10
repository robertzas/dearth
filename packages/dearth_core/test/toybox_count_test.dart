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
}
