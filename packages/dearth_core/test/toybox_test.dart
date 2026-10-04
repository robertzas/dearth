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

  test('free-play games unlock a level every three sessions; their echo rounds still climb', () {
    final paint = gameById('paint')!, music = gameById('music')!;
    List<GameRound> sessions(int n) => [for (var i = 0; i < n; i++) r(1, 'played')];
    expect([for (final n in [0, 2, 3, 6, 9]) startLevel(paint, sessions(n))], [1, 1, 2, 3, 3]);
    expect(startLevel(paint, sessions(9), pinned: 1), 1);
    expect(startLevel(music, [r(2, 'win'), r(2, 'win'), r(2, 'win')]), 3);
    expect(startLevel(gameById('memory')!, sessions(9)), 1, reason: 'not a free-play game');
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

    test('a grown-up can open a game early; launcher order stays', () {
      final ids = gamesFor(30, early: {'counting'}).map((g) => g.id).toList();
      expect(ids, contains('counting'));
      expect(ids, [for (final g in kGames) if (ids.contains(g.id)) g.id], reason: 'in launcher order');
      expect(gamesFor(30, off: {'counting'}, early: {'counting'}).map((g) => g.id), contains('counting'), reason: 'early wins');
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
      expect([for (var l = 1; l <= 4; l++) memoryPeek(l)], [true, true, false, false]);
    });

    test('shapes: 2 → 8, the last level turns the holes', () {
      expect(shapeRound(1, Random(1)).shapes.toSet(), {ToyShape.circle, ToyShape.square});
      expect(shapeRound(4, Random(1)).shapes.length, 6);
      expect((shapeRound(4, Random(1)).rotated, shapeRound(5, Random(1)).rotated), (false, true));
      expect((shapeResult(2, 1), shapeResult(2, 2), shapeResult(8, 2), shapeResult(8, 7)), ('win', 'helped', 'win', 'miss'));
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
      expect([for (var slips = 0; slips < 3; slips++) countingResult(slips)], ['win', 'helped', 'miss']);
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
      expect((monsterResult(1), monsterResult(2), monsterResult(4)), ('win', 'helped', 'miss'));
    });

    test('jigsaw: 2 → 24 pieces, tabs on every inner edge', () {
      expect([for (var l = 1; l <= 7; l++) jigsawGrid(l)].map((g) => g.rows * g.cols), kJigsawPieces);
      expect(jigsawGrid(3, landscape: false), (rows: 3, cols: 2));
      final tabs = jigsawTabs(3, 4, Random(3));
      expect((tabs.right.length, tabs.right.first.length, tabs.down.length, tabs.down.first.length), (3, 3, 2, 4));
      expect(tabs.right.expand((e) => e).every((t) => t == 1 || t == -1), isTrue);
      expect((jigsawResult(2, 1), jigsawResult(2, 2), jigsawResult(24, 8), jigsawResult(24, 25)), ('win', 'helped', 'win', 'miss'));
    });

    test('coloring: bigger pictures as she climbs, every size has a level', () {
      expect([for (var l = 1; l <= 5; l++) coloringFits(4, l)], [true, false, false, false, false]);
      expect([for (var l = 1; l <= 5; l++) coloringFits(30, l)], [false, false, false, false, true]);
      for (var n = kColoringBands.first.$1; n <= kColoringBands.last.$2; n++) {
        expect([for (var l = 1; l <= 5; l++) coloringFits(n, l)].where((f) => f).length, 1, reason: '$n regions');
      }
    });

    test('paint: stamps and scenes at level 2, symmetry at 3', () {
      expect([for (var l = 1; l <= 3; l++) (paintKit(l).stamps, paintKit(l).scenes, paintKit(l).mirror)], [(false, false, false), (true, true, false), (true, true, true)]);
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

    test('every picture is an Emoji 12 glyph: the kitchen frame (Android 10) draws nothing newer', () {
      // Emoji 13+ in the blocks the toybox draws from (SPEC §6, Appendix A).
      const emoji12 = {0x1FA70, 0x1FA71, 0x1FA72, 0x1FA73, 0x1FA78, 0x1FA79, 0x1FA7A, 0x1FA80, 0x1FA81, 0x1FA82, 0x1FA90, 0x1FA91, 0x1FA92, 0x1FA93, 0x1FA94, 0x1FA95};
      const newer = {0x1F90C, 0x1F972, 0x1F977, 0x1F978, 0x1F979, 0x1F9A3, 0x1F9A4, 0x1F9AB, 0x1F9AC, 0x1F9AD, 0x1F9CB, 0x1F9CC, 0x1F6D6, 0x1F6D7, 0x1F6DC, 0x1F6DD, 0x1F6DE, 0x1F6DF, 0x1F6FB, 0x1F6FC, 0x1F7F0};
      bool draws(String e) => e.runes.every((cp) => !newer.contains(cp) && !(cp >= 0x1FA70 && cp <= 0x1FAFF && !emoji12.contains(cp)));
      final pictures = [
        for (final g in kGames) g.emoji,
        ...kMemoryFaces,
        for (final f in kFoods) f.emoji,
        for (final a in kFarmAnimals) a.emoji,
        ...kExpansionPictures,
      ];
      expect([for (final p in pictures) if (!draws(p)) p], isEmpty);
    });

    test('bubbles speed up, then call a color', () {
      expect([for (var l = 1; l <= 4; l++) bubbleRound(l).colorCall], [false, false, true, true]);
      expect(bubbleRound(2).riseSeconds, lessThan(bubbleRound(1).riseSeconds));
    });
  });

  group('expansion rounds (FR-TOY-03)', () {
    test('patterns: the answer continues the rule; the top level grows a tower', () {
      for (var seed = 0; seed < 60; seed++) {
        for (var level = 1; level <= 3; level++) {
          final r = patternRound(level, Random(seed));
          final unit = level == 1 ? 2 : 3;
          expect(r.shown.length, greaterThanOrEqualTo(unit * 2));
          for (var i = unit; i < r.shown.length; i++) {
            expect(r.shown[i], r.shown[i - unit], reason: 'seed $seed level $level');
          }
          expect(r.answer, r.shown[r.shown.length - unit]);
          expect(r.choices, contains(r.answer));
        }
        final t = patternRound(4, Random(seed));
        expect(t.towers, isTrue);
        final sizes = [for (final s in t.shown) s.runes.length];
        expect(t.answer.runes.length - sizes.last, sizes[1] - sizes[0]);
        expect(t.choices.toSet().length, 3);
      }
    });

    test('odd one out: three alike and one that isn’t, by color, shape, kind, then use', () {
      for (var seed = 0; seed < 80; seed++) {
        for (var level = 1; level <= 4; level++) {
          final r = oddOneOut(level, Random(seed));
          expect(r.items.length, 4);
          final rest = [for (var i = 0; i < 4; i++) if (i != r.odd) r.items[i]];
          final odd = r.items[r.odd];
          switch (r.rule) {
            case 'color':
              String color(OddItem i) => kFoods.firstWhere((f) => f.emoji == i.emoji).color;
              expect(rest.map(color).toSet().length, 1);
              expect(color(odd), isNot(color(rest.first)));
            case 'shape':
              expect(rest.map((i) => i.shape).toSet().length, 1);
              expect(odd.shape, isNot(rest.first.shape));
            default:
              final groups = r.rule == 'kind' ? kKinds : kUses;
              final home = groups.entries.firstWhere((e) => e.value.contains(rest.first.emoji)).key;
              expect(rest.every((i) => groups[home]!.contains(i.emoji)), isTrue, reason: '$seed ${r.rule}');
              expect(groups[home]!.contains(odd.emoji), isFalse);
          }
        }
      }
      // No picture belongs to two groups of one level.
      for (final groups in [kKinds, kUses]) {
        final all = [for (final g in groups.values) ...g];
        expect(all.toSet().length, all.length);
      }
    });

    test('shadows, sizes and stories: right counts, every picture once, never pre-solved', () {
      for (var seed = 0; seed < 40; seed++) {
        for (var level = 1; level <= 4; level++) {
          final sh = shadowRound(level, Random(seed));
          expect(sh.pictures.length, kShadowCounts[level - 1]);
          expect(sh.shadows.toSet(), sh.pictures.toSet());
          if (level >= 3) {
            expect(kShadowFamilies.values.any((f) => sh.pictures.every(f.contains)), isTrue, reason: 'look-alike shadows');
          }
          final sz = sizeRound(level, Random(seed));
          expect(sz.scales.length, kSizeCounts[level - 1]);
          expect([for (final i in sz.order) sz.scales[i]], [...sz.scales]..sort());
        }
        for (var level = 1; level <= 3; level++) {
          final st = storyRound(level, Random(seed));
          expect(st.story.length, kStoryLengths[level - 1]);
          expect([...st.cards]..sort(), [...st.story]..sort());
          expect(st.cards, isNot(st.story));
        }
      }
      expect((expansionResult(0), expansionResult(1), expansionResult(2)), ('win', 'helped', 'miss'));
      expect((expansionResult(1, size: 6), expansionResult(2, size: 6)), ('win', 'helped'));
    });

    test('picture sudoku: a valid grid with blanks that leave exactly one answer', () {
      for (var seed = 0; seed < 60; seed++) {
        for (var level = 1; level <= 6; level++) {
          final r = sudokuRound(level, Random(seed));
          expect(sudokuValid(r.solution), isTrue);
          expect(r.blanks.length, kSudokuBlanks[level - 1]);
          final puzzle = [for (var i = 0; i < 16; i++) r.blanks.contains(i) ? -1 : r.solution[i]];
          expect(sudokuSolutions(puzzle), 1);
        }
      }
    });

    test('spot the difference: the two pictures differ exactly where the spots are', () {
      for (var seed = 0; seed < 40; seed++) {
        for (var level = 1; level <= 5; level++) {
          final r = differenceRound(level, Random(seed));
          expect(r.spots.length, kDifferenceCounts[level - 1]);
          final changed = [for (var i = 0; i < r.left.length; i++) if (r.left[i] != r.right[i] && (r.left[i].emoji != r.right[i].emoji || r.left[i].size != r.right[i].size || r.left[i].flipped != r.right[i].flipped || r.left[i].y != r.right[i].y)) i];
          expect(changed.length, r.spots.length, reason: 'seed $seed level $level');
          for (final i in changed) {
            final p = r.left[i];
            expect(r.spots.any((s) => (s.$1 - p.x).abs() < 0.001 && (s.$2 - (p.y + r.right[i].y) / 2).abs() < 0.001), isTrue);
          }
          if (level <= 3) {
            expect(changed.every((i) => r.right[i].size == 0 || r.right[i].emoji != r.left[i].emoji), isTrue, reason: 'early levels: missing or swapped');
          }
        }
      }
    });

    test('finger mazes: one way home through a maze that grows', () {
      for (var seed = 0; seed < 40; seed++) {
        for (var level = 1; level <= 4; level++) {
          final m = mazeRound(level, Random(seed));
          expect((m.cols, m.rows), kMazeSizes[level - 1]);
          expect(m.open.length, m.cols * m.rows - 1, reason: 'a perfect maze is a tree');
          final path = m.path(m.start);
          expect((path.first, path.last), (m.start, m.home));
          for (var i = 1; i < path.length; i++) {
            expect(m.connected(path[i - 1], path[i]), isTrue);
          }
        }
      }
    });

    test('the expansion games join the catalog after the launch set', () {
      expect(kGames.take(kLaunchGames.length), kLaunchGames);
      expect(gameById('mazes')?.minMonths, 36);
      expect(kGames.map((g) => g.id).toSet().length, kGames.length);
    });
  });
}
