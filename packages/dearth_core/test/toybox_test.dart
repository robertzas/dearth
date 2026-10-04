import 'dart:math';

import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

/// The Toybox's rules (SPEC §10.8, Appendix B): who sees which game, the
/// adaptive ladder, time limits, and every launch-set game's rounds.
void main() {
  GameRound r(int level, String result) => (level: level, result: result);

  group('adaptive difficulty (FR-TOY-04)', () {
    test('three wins in a row go up; three misses in a row go down', () {
      expect(nextLevel([], maxLevel: 5), 1);
      expect(nextLevel([r(1, 'win'), r(1, 'win')], maxLevel: 5), 1);
      expect(nextLevel([r(1, 'win'), r(1, 'win'), r(1, 'win')], maxLevel: 5), 2);
      expect(nextLevel([r(3, 'miss'), r(3, 'miss'), r(3, 'miss')], maxLevel: 5), 2);
      expect(nextLevel([r(3, 'miss'), r(3, 'win'), r(3, 'miss')], maxLevel: 5), 3, reason: 'mixed: stay');
    });

    test('a new level starts a new streak; help neither raises nor lowers it', () {
      expect(nextLevel([r(1, 'win'), r(1, 'win'), r(1, 'win'), r(2, 'win')], maxLevel: 5), 2);
      expect(nextLevel([r(2, 'win'), r(2, 'helped'), r(2, 'win')], maxLevel: 5), 2);
      expect(nextLevel([r(2, 'helped'), r(2, 'helped'), r(2, 'helped')], maxLevel: 5), 2);
    });

    test('free play doesn’t count; the ladder has ends; a parent’s pin wins', () {
      expect(nextLevel([r(2, 'win'), r(2, 'win'), r(1, 'played'), r(2, 'win')], maxLevel: 5), 3);
      expect(nextLevel([r(5, 'win'), r(5, 'win'), r(5, 'win')], maxLevel: 5), 5);
      expect(nextLevel([r(1, 'miss'), r(1, 'miss'), r(1, 'miss')], maxLevel: 5), 1);
      expect(nextLevel([r(1, 'win'), r(1, 'win'), r(1, 'win')], maxLevel: 5, pinned: 1), 1);
      expect(nextLevel([], maxLevel: 5, pinned: 9), 5);
    });
  });

  group('who plays what', () {
    test('age comes from the birthday, else the stage', () {
      final today = DateTime(2026, 10, 3);
      expect(ageInMonths(today: today, birthday: DateTime(2024, 4)), 30);
      expect(ageInMonths(today: today, birthday: DateTime(2024, 4, 5)), 29, reason: 'the 5th has not come yet');
      expect(ageInMonths(today: today, stage: 'preschool'), 42);
      expect(ageInMonths(today: today), 30);
    });

    test('games appear as a kid grows; grown-ups can switch any off', () {
      expect(gamesFor(24).map((g) => g.id), isNot(contains('memory')));
      expect(gamesFor(30).map((g) => g.id), containsAll(['memory', 'monster']));
      expect(gamesFor(30).map((g) => g.id), isNot(contains('counting')));
      expect(gamesFor(48).length, kGames.length);
      expect(gamesFor(48, off: {'paint'}).map((g) => g.id), isNot(contains('paint')));
    });

    test('a daily budget counts down; hours can run past midnight', () {
      expect(minutesLeft(5 * 60000), isNull);
      expect(minutesLeft(5 * 60000, budgetMinutes: 20), 15);
      expect(minutesLeft(19 * 60000 + 1, budgetMinutes: 20), 1, reason: 'part of a minute still counts');
      expect(minutesLeft(25 * 60000, budgetMinutes: 20), 0);
      expect(toyboxOpen(8 * 60), isTrue);
      expect(toyboxOpen(8 * 60, opens: '07:00', closes: '19:00'), isTrue);
      expect(toyboxOpen(19 * 60, opens: '07:00', closes: '19:00'), isFalse);
      expect(toyboxOpen(23 * 60, opens: '22:00', closes: '02:00'), isTrue);
    });
  });

  group('rounds (FR-TOY-02)', () {
    test('memory: 2 → 12 pairs, every face twice', () {
      for (var level = 1; level <= 6; level++) {
        final deck = memoryDeck(level, Random(level));
        expect(deck.length, 2 * kMemoryPairs[level - 1]);
        for (final face in deck.toSet()) {
          expect(deck.where((f) => f == face).length, 2);
        }
      }
      expect((memoryResult(4, 4), memoryResult(4, 9), memoryResult(4, 13)), ('win', 'helped', 'miss'));
    });

    test('shapes: 2 → 8, the last level turns the holes', () {
      expect(shapeRound(1, Random(1)).shapes.toSet(), {ToyShape.circle, ToyShape.square});
      expect(shapeRound(4, Random(1)).shapes.length, 6);
      expect((shapeRound(4, Random(1)).rotated, shapeRound(5, Random(1)).rotated), (false, true));
    });

    test('counting: the answer is always among the choices, which are near it', () {
      for (var seed = 0; seed < 50; seed++) {
        for (var level = 1; level <= 4; level++) {
          final round = countingRound(level, Random(seed));
          expect(round.choices, contains(round.count));
          expect(round.choices.toSet().length, round.choices.length);
          expect(round.choices.length, level == 1 ? 2 : 3);
          expect(round.count, inInclusiveRange(1, const [3, 5, 10, 6][level - 1]));
          expect(round.flash, level == 4);
        }
      }
    });

    test('monster: something to eat and something to refuse, every time', () {
      for (var seed = 0; seed < 200; seed++) {
        for (var level = 1; level <= 4; level++) {
          final round = monsterRound(level, Random(seed));
          expect(round.toEat, greaterThan(0), reason: 'seed $seed level $level ${round.rule}');
          expect(round.toEat, lessThan(round.tray.length), reason: 'seed $seed level $level ${round.rule} ${round.tray}');
          if (level == 1) {
            expect(round.tray.map((f) => f.color).toSet().length, 2, reason: 'two colors: ${round.tray}');
          }
          if (level >= 4) {
            expect([?round.rule.color, if (round.rule.round != null) 'r', ?round.rule.kind].length, 2);
          }
        }
      }
      expect(const MonsterRule(color: 'red', round: true).words, 'red and round');
    });

    test('jigsaw: 2 → 24 pieces, tabs on every inner edge', () {
      expect([for (var l = 1; l <= 7; l++) jigsawGrid(l)].map((g) => g.rows * g.cols), kJigsawPieces);
      expect(jigsawGrid(3, landscape: false), (rows: 3, cols: 2));
      final tabs = jigsawTabs(3, 4, Random(3));
      expect((tabs.right.length, tabs.right.first.length, tabs.down.length, tabs.down.first.length), (3, 3, 2, 4));
      expect(tabs.right.expand((e) => e).every((t) => t == 1 || t == -1), isTrue);
    });

    test('farm: free play, then find one among three, then six', () {
      expect(farmRound(1, Random(1)).find, isNull);
      final find = farmRound(2, Random(2));
      expect((find.animals.length, find.animals.contains(find.find)), (3, true));
      expect(farmRound(3, Random(3)).animals.length, 6);
    });

    test('xylophone echoes grow from three notes to five, never three alike in a row', () {
      expect(echoPattern(1, Random(1)), isEmpty);
      for (var seed = 0; seed < 100; seed++) {
        final p = echoPattern(3, Random(seed));
        expect(p.length, 5);
        for (var i = 2; i < p.length; i++) {
          expect(p[i] == p[i - 1] && p[i] == p[i - 2], isFalse);
        }
      }
      expect(kXylophoneMidi.length, 8);
    });

    test('bubbles speed up, then call a color', () {
      expect([for (var l = 1; l <= 4; l++) bubbleRound(l).colorCall], [false, false, true, true]);
      expect(bubbleRound(2).riseSeconds, lessThan(bubbleRound(1).riseSeconds));
    });
  });
}
