import 'package:dearth_app/core/sound.dart';
import 'package:dearth_app/features/toybox/games/differences.dart';
import 'package:dearth_app/features/toybox/games/mazes.dart';
import 'package:dearth_app/features/toybox/games/oddone.dart';
import 'package:dearth_app/features/toybox/games/patterns.dart';
import 'package:dearth_app/features/toybox/games/shadows.dart';
import 'package:dearth_app/features/toybox/games/shapes.dart';
import 'package:dearth_app/features/toybox/games/sizes.dart';
import 'package:dearth_app/features/toybox/games/stories.dart';
import 'package:dearth_app/features/toybox/games/sudoku.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';
import 'support/toybox_harness.dart';

/// The Toybox's expansion set (SPEC FR-TOY-03), played through the Toybox
/// on the demo household (games for older kids are opened early for Ava).
void main() {
  group('Patterns', () {
    testWidgets('what comes next: a wrong pick wiggles away; the right one finishes the row', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'patterns', sound: sound);
      final r = tester.state<PatternsGameState>(find.byType(PatternsGame)).debugRound;
      expect(labelOf(tester, 'patterns.slot'), 'What comes next?');
      expectNoFallbackText(byId('screen.game'));
      final wrong = r.choices.indexWhere((c) => c != r.answer);
      await tester.tap(byId('patterns.choice.$wrong'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.played.last.$1, Sfx.nope);
      await tester.tap(byId('patterns.choice.${r.choices.indexOf(r.answer)}'));
      await h.settle();
      expect(labelOf(tester, 'patterns.slot'), r.answer);
      expect(await toyboxRounds(h), [('patterns', 1, 'helped')]);
      await tester.pump(const Duration(seconds: 3));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('the top level grows towers, and the next one up is a win', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await openToyboxGame(tester, 'patterns', level: 4);
      final r = tester.state<PatternsGameState>(find.byType(PatternsGame)).debugRound;
      expect(r.towers, isTrue);
      await tester.tap(byId('patterns.choice.${r.choices.indexOf(r.answer)}'));
      await h.settle();
      expect(await toyboxRounds(h), [('patterns', 4, 'win')]);
      await tester.pump(const Duration(seconds: 3));
      await h.shutdown();
      handle.dispose();
    });
  });

  group('Odd One Out', () {
    testWidgets('four pictures, one different: found after a slip is “helped”; shapes at level 2 are painted', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await openToyboxGame(tester, 'oddone');
      final r = tester.state<OddOneGameState>(find.byType(OddOneGame)).debugRound;
      expect(r.rule, 'color');
      expectNoFallbackText(byId('screen.game'));
      await tester.tap(byId('oddone.item.${(r.odd + 1) % 4}'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(byId('oddone.item.${r.odd}'));
      await h.settle();
      expect(await toyboxRounds(h), [('oddone', 1, 'helped')]);
      await tester.pump(const Duration(seconds: 3));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('level 2 compares painted shapes', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await openToyboxGame(tester, 'oddone', level: 2);
      final r = tester.state<OddOneGameState>(find.byType(OddOneGame)).debugRound;
      expect(r.rule, 'shape');
      expect(find.byType(ToyShapeView), findsNWidgets(4));
      await tester.tap(byId('oddone.item.${r.odd}'));
      await h.settle();
      expect(await toyboxRounds(h), [('oddone', 2, 'win')]);
      await tester.pump(const Duration(seconds: 3));
      await h.shutdown();
      handle.dispose();
    });
  });

  group('Shadow Match', () {
    testWidgets('a picture dragged onto its own shadow fills it; onto another, it hops back', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'shadows', sound: sound);
      final r = tester.state<ShadowsGameState>(find.byType(ShadowsGame)).debugRound;
      expect(r.pictures.length, 2);
      expectNoFallbackText(byId('screen.game'));
      Future<void> drag(int picture, int shadow) async {
        final a = tester.getCenter(byId('shadows.picture.$picture')), b = tester.getCenter(byId('shadows.shadow.$shadow'));
        await tester.dragFrom(a, b - a);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      }

      final first = r.pictures[0];
      await drag(0, r.shadows.indexWhere((s) => s != first));
      expect(sound.played.last.$1, Sfx.boing);
      for (var i = 0; i < r.pictures.length; i++) {
        await drag(i, r.shadows.indexOf(r.pictures[i]));
      }
      await h.settle();
      expect(labelOf(tester, 'shadows.shadow.${r.shadows.indexOf(first)}'), first);
      expect(await toyboxRounds(h), [('shadows', 1, 'helped')]);
      await tester.pump(const Duration(seconds: 3));
      await h.shutdown();
      handle.dispose();
    });
  });

  group('Small to Big', () {
    testWidgets('tapped smallest first, each joins the line on a rising note; a wrong one wiggles', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'sizes', sound: sound, level: 3);
      final r = tester.state<SizesGameState>(find.byType(SizesGame)).debugRound;
      expect(r.scales.length, 5);
      expectNoFallbackText(byId('screen.game'));
      await tester.tap(byId('sizes.item.${r.order.last}'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.played.last.$1, Sfx.nope, reason: 'the biggest isn’t first');
      for (final i in r.order) {
        await tester.tap(byId('sizes.item.$i'));
        await tester.pump(const Duration(milliseconds: 500));
        expect(labelOf(tester, 'sizes.item.$i'), 'In the line');
      }
      final rates = [for (var i = 0; i < sound.played.length; i++) if (sound.played[i].$1 == Sfx.blip) sound.rates[i]];
      expect(rates, orderedEquals([...rates]..sort()), reason: 'a rising scale');
      await h.settle();
      expect(await toyboxRounds(h), [('sizes', 3, 'win')], reason: 'one slip on five is still a win');
      await tester.pump(const Duration(seconds: 3));
      await h.shutdown();
      handle.dispose();
    });
  });

  group('Picture Sudoku', () {
    testWidgets('the first empty place is chosen; the right fruit fills it and the next is chosen', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'sudoku', sound: sound, level: 2);
      final r = tester.state<SudokuGameState>(find.byType(SudokuGame)).debugRound;
      final blanks = r.blanks.toList()..sort();
      expect(blanks.length, 2);
      expect(labelOf(tester, 'sudoku.cell.${blanks.first}'), 'Empty, chosen');
      expectNoFallbackText(byId('screen.game'));
      final right = r.solution[blanks.first];
      await tester.tap(byId('sudoku.fruit.${(right + 1) % 4}'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.played.last.$1, Sfx.nope);
      await tester.tap(byId('sudoku.fruit.$right'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(labelOf(tester, 'sudoku.cell.${blanks.first}'), kSudokuFruit[right]);
      expect(labelOf(tester, 'sudoku.cell.${blanks.last}'), 'Empty, chosen');
      await tester.tap(byId('sudoku.fruit.${r.solution[blanks.last]}'));
      await h.settle();
      expect(await toyboxRounds(h), [('sudoku', 2, 'win')]);
      await tester.pump(const Duration(seconds: 3));
      await h.shutdown();
      handle.dispose();
    });
  });

  group('What Happens Next', () {
    testWidgets('the cards go into the line in story order, then the story plays back', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'stories', sound: sound);
      final r = tester.state<StoriesGameState>(find.byType(StoriesGame)).debugRound;
      expect(r.story.length, 3);
      expectNoFallbackText(byId('screen.game'));
      final last = r.cards.indexOf(r.story.last);
      await tester.tap(byId('stories.card.$last'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.played.last.$1, Sfx.nope, reason: 'not first');
      for (final (k, picture) in r.story.indexed) {
        final i = r.cards.indexOf(picture);
        await tester.tap(byId('stories.card.$i'));
        await tester.pump(const Duration(milliseconds: 450));
        expect(labelOf(tester, 'stories.card.$i'), 'Place ${k + 1}: $picture');
      }
      await tester.pump(const Duration(seconds: 2));
      await h.settle();
      expect(sound.played.where((p) => p.$1 == Sfx.blip).length, 3, reason: 'the story plays back');
      expect(await toyboxRounds(h), [('stories', 1, 'helped')]);
      await tester.pump(const Duration(seconds: 3));
      await h.shutdown();
      handle.dispose();
    });
  });

  group('Spot the Difference', () {
    testWidgets('a tap on a difference rings it; a tap on nothing just puffs; all found is a win', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'differences', sound: sound);
      final r = tester.state<DifferencesGameState>(find.byType(DifferencesGame)).debugRound;
      expect(r.spots.length, 3);
      expectNoFallbackText(byId('screen.game'));
      // A corner where nothing changed.
      final left = tester.getRect(byId('differences.left'));
      await tester.tapAt(left.topLeft + const Offset(6, 6));
      await tester.pump(const Duration(milliseconds: 100));
      expect(labelOf(tester, 'differences.count'), 'Found 0 of 3');
      for (var i = 0; i < 3; i++) {
        await tester.tap(byId('differences.spot.$i'));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(labelOf(tester, 'differences.count'), 'Found 3 of 3');
      expect(sound.played.where((p) => p.$1 == Sfx.sparkle).length, 3);
      await h.settle();
      expect(await toyboxRounds(h), [('differences', 1, 'win')]);
      await tester.pump(const Duration(seconds: 4));
      await h.shutdown();
      handle.dispose();
    });
  });

  group('Finger Mazes', () {
    testWidgets('the buddy steps home through open squares; a wall says boing', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'mazes', sound: sound);
      final game = tester.state<MazesGameState>(find.byType(MazesGame));
      final m = game.debugMaze;
      expect((m.cols, m.rows), (3, 2));
      expect(labelOf(tester, 'mazes.cell.${m.start}'), contains('buddy here'));
      expectNoFallbackText(byId('screen.game'));
      final blocked = m.neighbours(m.start).where((n) => !m.connected(m.start, n)).firstOrNull;
      if (blocked != null) {
        await tester.tap(byId('mazes.cell.$blocked'));
        await tester.pump(const Duration(milliseconds: 50));
        expect(sound.played.last.$1, Sfx.boing);
        expect(game.debugAt, m.start, reason: 'walls hold');
      }
      for (final cell in m.path(m.start).skip(1)) {
        await tester.tap(byId('mazes.cell.$cell'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(game.debugAt, cell);
      }
      await h.settle();
      expect(await toyboxRounds(h), [('mazes', 1, 'win')]);
      await tester.pump(const Duration(seconds: 3));
      await h.shutdown();
      handle.dispose();
    });
  });
}
