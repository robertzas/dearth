import 'dart:math';

import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

/// The launch set and the first expansion batch (SPEC FR-TOY-02/03): their
/// ladders and content over many seeds, their results, and the voice lines
/// they were given in 2026-10 (they were built before the Toybox spoke).
void main() {
  int levels(String id) => gameById(id)!.levels;

  test('FR-TOY-02 Bubble Pop: slow free popping, then faster, then a color to call, never more than it can show', () {
    final rounds = [for (var l = 1; l <= levels('bubbles'); l++) bubbleRound(l)];
    expect([for (final r in rounds) r.colorCall], [false, false, true, true]);
    for (var i = 1; i < rounds.length; i++) {
      if (rounds[i].colorCall == rounds[i - 1].colorCall) expect(rounds[i].riseSeconds, lessThan(rounds[i - 1].riseSeconds), reason: 'level ${i + 1} rises faster');
    }
    for (final r in rounds) {
      expect(r.targets, inInclusiveRange(8, 15));
      if (r.colorCall) expect(r.targets, lessThanOrEqualTo(10), reason: 'only some bubbles count');
    }
    for (final c in const ['blue', 'red', 'yellow', 'green', 'purple']) {
      expect(kVoiceLines[bubblesCallClip(c)], 'Pop the $c bubbles!');
    }
  });

  test('FR-TOY-02 Animal Farm: free play with six, then "who says…?" among three, then six; every animal is named and answered', () {
    for (var seed = 0; seed < 200; seed++) {
      for (var level = 1; level <= levels('farm'); level++) {
        final r = farmRound(level, Random(seed));
        expect(r.animals.length, level == 2 ? 3 : 6, reason: 'seed $seed, level $level');
        expect(r.animals.map((a) => a.id).toSet().length, r.animals.length, reason: 'no animal twice');
        if (level == 1) {
          expect(r.find, isNull);
        } else {
          expect(r.animals, contains(r.find));
        }
      }
    }
    for (final a in kFarmAnimals) {
      expect(kVoiceLines, contains(farmNameClip(a)), reason: a.id);
      expect(kVoiceLines[farmYesClip(a)], startsWith('Yes! The ${a.id} says '));
    }
    // The ones the picture words already have use their clip.
    expect(farmNameClip(kFarmAnimals.firstWhere((a) => a.id == 'cow')), 'word_cow');
  });

  test('FR-TOY-02 Shape Sorter: 2 → 8 different shapes, holes turned only at the top; each shape has its name', () {
    for (var seed = 0; seed < 200; seed++) {
      for (var level = 1; level <= levels('shapes'); level++) {
        final r = shapeRound(level, Random(seed));
        expect(r.shapes.length, kShapeCounts[level - 1]);
        expect(r.shapes.toSet().length, r.shapes.length);
        expect(r.rotated, level == levels('shapes'));
      }
    }
    expect(shapeResult(8, 2), GameResult.win, reason: 'a slip per four shapes is fine');
    expect(shapeResult(2, 1), GameResult.win);
    expect(shapeResult(2, 2), isNot(GameResult.win));
    for (final s in ToyShape.values) {
      expect(kVoiceLines[shapeNameClip(s)], '${s.name[0].toUpperCase()}${s.name.substring(1)}!');
    }
  });

  test('FR-TOY-02 Counting Garden: 1–3, 1–5, 1–10, then flashes of 1–6; the answer is always among near choices', () {
    for (var seed = 0; seed < 200; seed++) {
      for (var level = 1; level <= levels('counting'); level++) {
        final r = countingRound(level, Random(seed));
        final top = const [3, 5, 10, 6][level - 1];
        expect(r.count, inInclusiveRange(1, top), reason: 'seed $seed, level $level');
        expect(r.choices, contains(r.count));
        expect(r.choices.length, level == 1 ? 2 : 3);
        expect(r.choices, orderedEquals([...r.choices]..sort()), reason: 'answers read small to big');
        expect(r.choices.every((c) => (c - r.count).abs() <= 2), isTrue, reason: 'near misses only: ${r.choices} for ${r.count}');
        expect(r.flash, level == 4);
      }
    }
    for (var n = 1; n <= 10; n++) {
      expect(kVoiceLines, contains(countingYesClip(n)));
    }
    expect(kVoiceLines[countingYesClip(3)], 'Three flowers!');
  });

  test('FR-TOY-02 Feed the Monster: every rule a round can pick has a spoken line, and the line says the rule', () {
    final picked = <String>{};
    for (var seed = 0; seed < 400; seed++) {
      for (var level = 1; level <= levels('monster'); level++) {
        picked.add(monsterRound(level, Random(seed)).rule.words);
      }
    }
    expect(picked, kMonsterRules.map((r) => r.words).toSet(), reason: 'kMonsterRules is exactly what the rounds pick');
    for (final r in kMonsterRules) {
      final line = kVoiceLines[monsterRuleClip(r)]!;
      if (r.color != null) expect(line, contains(r.color), reason: line);
      if (r.round == true) expect(line, contains('round'), reason: line);
    }
    expect(kVoiceLines[monsterRuleClip(const MonsterRule(color: 'red', kind: 'fruit'))], 'I only eat red fruit!');
  });

  test('FR-TOY-02 Magic Coloring: the bands climb from a few big parts to many small ones, without gaps', () {
    for (var level = 1; level < kColoringBands.length; level++) {
      expect(kColoringBands[level].$1, kColoringBands[level - 1].$2 + 1, reason: 'band ${level + 1} starts where $level ends');
    }
    expect(coloringFits(4, 1), isTrue);
    expect(coloringFits(4, 2), isFalse);
    expect(coloringFits(26, 5), isTrue);
    // Every crayon says its color.
    for (final c in kCrayonWords.keys) {
      expect(kVoiceLines, contains(colorClip(c)));
    }
    expect(kVoiceLines[colorClip('sky')], 'Light blue!');
  });

  test('FR-TOY-03 Patterns: AB, AAB, ABC, then towers; the answer is a choice and continues the rule', () {
    for (var seed = 0; seed < 200; seed++) {
      for (var level = 1; level <= levels('patterns'); level++) {
        final r = patternRound(level, Random(seed));
        expect(r.choices, contains(r.answer), reason: 'seed $seed, level $level');
        expect(r.choices.toSet().length, r.choices.length);
        expect(r.towers, level >= 4);
        if (r.towers) {
          // The same picture repeated: each tower one picture taller.
          final heights = [for (final p in [...r.shown, r.answer]) p.length];
          final step = heights[1] - heights[0];
          expect(step, greaterThan(0));
          for (var i = 1; i < heights.length; i++) {
            expect(heights[i] - heights[i - 1], step, reason: 'each tower one taller');
          }
        } else {
          // The unit repeats: the answer is what came one unit earlier.
          final unit = level == 1 ? 2 : 3;
          final all = [...r.shown, r.answer];
          expect(all.last, all[all.length - 1 - unit]);
        }
      }
    }
  });

  test('FR-TOY-03 Odd One Out: four pictures, exactly one odd by the level\'s rule', () {
    const rules = ['color', 'shape', 'kind', 'use'];
    for (var seed = 0; seed < 200; seed++) {
      for (var level = 1; level <= levels('oddone'); level++) {
        final r = oddOneOut(level, Random(seed));
        expect(r.items.length, 4);
        expect(r.rule, rules[level - 1]);
        final odd = r.items[r.odd];
        final rest = [for (final (i, x) in r.items.indexed) if (i != r.odd) x];
        if (r.rule == 'shape') {
          expect(rest.map((x) => x.shape).toSet().length, 1);
          expect(odd.shape, isNot(rest.first.shape));
        } else if (r.rule == 'color') {
          final color = {for (final f in kFoods) f.emoji: f.color};
          expect(rest.map((x) => color[x.emoji]).toSet().length, 1, reason: 'seed $seed');
          expect(color[odd.emoji], isNot(color[rest.first.emoji]));
        } else {
          final groups = r.rule == 'kind' ? kKinds : kUses;
          final home = groups.entries.firstWhere((g) => g.value.contains(rest.first.emoji)).key;
          expect(rest.every((x) => groups[home]!.contains(x.emoji)), isTrue);
          expect(groups[home], isNot(contains(odd.emoji)), reason: 'seed $seed: ${odd.emoji} in $home');
        }
      }
      expect(kVoiceLines, contains(oddYesClip(rules[seed % 4])));
    }
  });

  test('FR-TOY-03 Shadow Match: 2 → 6 pictures, shadows the same set shuffled, one family at the top', () {
    for (var seed = 0; seed < 200; seed++) {
      for (var level = 1; level <= levels('shadows'); level++) {
        final r = shadowRound(level, Random(seed));
        expect(r.pictures.length, kShadowCounts[level - 1]);
        expect(r.pictures.toSet().length, r.pictures.length);
        expect(r.shadows.toSet(), r.pictures.toSet());
        if (level >= 3) {
          expect(kShadowFamilies.values.any((f) => r.pictures.every(f.contains)), isTrue, reason: 'one family: they look alike');
        }
      }
    }
  });

  test('FR-TOY-03 Small to Big: 3 → 6 sizes, evenly apart, never already in order', () {
    for (var seed = 0; seed < 200; seed++) {
      for (var level = 1; level <= levels('sizes'); level++) {
        final r = sizeRound(level, Random(seed));
        expect(r.scales.length, kSizeCounts[level - 1]);
        final sorted = [...r.scales]..sort();
        expect(sorted.first, closeTo(0.35, 1e-9));
        expect(sorted.last, closeTo(1, 1e-9));
        expect([for (final i in r.order) r.scales[i]], orderedEquals(sorted));
        expect(r.scales.join(), isNot(sorted.join()), reason: 'not already in order');
        expect(r.scales.join(), isNot(sorted.reversed.join()), reason: 'nor backwards');
      }
    }
  });

  test('FR-TOY-03 Picture Sudoku: a valid board with 1 → 6 blanks and exactly one way to fill them', () {
    for (var seed = 0; seed < 200; seed++) {
      for (var level = 1; level <= levels('sudoku'); level++) {
        final r = sudokuRound(level, Random(seed));
        expect(sudokuValid(r.solution), isTrue);
        expect(r.blanks.length, lessThanOrEqualTo(kSudokuBlanks[level - 1]));
        expect(r.blanks.length, greaterThanOrEqualTo(1));
        final work = [for (var i = 0; i < 16; i++) r.blanks.contains(i) ? -1 : r.solution[i]];
        expect(sudokuSolutions(work), 1, reason: 'seed $seed, level $level');
      }
    }
    // Each fruit says its name as it goes in.
    for (final f in kSudokuFruit) {
      expect(emojiWordClip(f), isNotNull, reason: f);
    }
  });

  test('FR-TOY-03 Spot the Difference: 3 → 7 differences, each a real change, kept apart', () {
    for (var seed = 0; seed < 200; seed++) {
      for (var level = 1; level <= levels('differences'); level++) {
        final r = differenceRound(level, Random(seed));
        expect(r.spots.length, kDifferenceCounts[level - 1]);
        expect(r.left.length, r.right.length);
        var changed = 0;
        for (var k = 0; k < r.left.length; k++) {
          final a = r.left[k], b = r.right[k];
          if (a.emoji != b.emoji || a.size != b.size || a.flipped != b.flipped || a.y != b.y) changed++;
        }
        expect(changed, r.spots.length, reason: 'seed $seed, level $level');
      }
    }
  });

  test('FR-TOY-03 What Happens Next: 3 → 5 cards, never already in order, and every story is told aloud', () {
    expect(kStoryTellings.length, kStories.length);
    for (var seed = 0; seed < 200; seed++) {
      for (var level = 1; level <= levels('stories'); level++) {
        final r = storyRound(level, Random(seed));
        expect(r.story.length, kStoryLengths[level - 1]);
        expect(r.cards.toSet(), r.story.toSet());
        expect(r.cards.join(), isNot(r.story.join()));
        final i = kStories.indexWhere((s) => s.join() == r.story.join());
        expect(kVoiceLines[storyTellingClip(i)], kStoryTellings[i]);
      }
    }
  });

  test('FR-TOY-03 Finger Mazes: a perfect maze, start bottom-left and home top-right, one way through', () {
    for (var seed = 0; seed < 200; seed++) {
      for (var level = 1; level <= levels('mazes'); level++) {
        final m = mazeRound(level, Random(seed));
        final cells = m.cols * m.rows;
        expect(m.open.length, cells - 1, reason: 'a tree: one way between any two squares');
        final path = m.path(m.start);
        expect(path.first, m.start);
        expect(path.last, m.home);
        for (var i = 1; i < path.length; i++) {
          expect(m.connected(path[i - 1], path[i]), isTrue);
        }
      }
    }
  });

  test('the first games say what a picture is when the voice has its word', () {
    expect(wordForEmoji('🍎')?.word, 'apple');
    expect(wordForEmoji('❤️')?.word, 'heart');
    expect(wordForEmoji('❤')?.word, 'heart', reason: 'with or without the emoji variation selector');
    expect(wordForEmoji('🛸'), isNull);
  });
}
