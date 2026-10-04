import 'dart:math' as math;

import 'package:dearth_app/core/sound.dart';
import 'package:dearth_app/features/toybox/games/jigsaw.dart';
import 'package:dearth_app/features/toybox/games/memory.dart';
import 'package:dearth_app/features/toybox/games/shapes.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_harness.dart';
import 'support/toybox_harness.dart';

/// The Toybox's puzzles (SPEC FR-TOY-02): Memory Match, Shape Sorter and
/// Jigsaw, played through the Toybox on the demo household.
void main() {
  group('Memory Match', () {
    testWidgets('the faces show, then turn; two that differ turn back; found pairs stay up; a full board is a win', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'memory', sound: sound);
      final game = tester.state<MemoryGameState>(find.byType(MemoryGame));
      final deck = game.debugDeck;
      expect(deck.length, 4, reason: 'two pairs at level 1');
      expect(byId('memory.look'), findsOneWidget);
      expect(labelOf(tester, 'memory.card.0'), deck[0], reason: 'a peek at every face');
      expectNoFallbackText(byId('screen.game'));

      await tester.pump(const Duration(milliseconds: 2400));
      await h.settle(4);
      expect(byId('memory.look'), findsNothing);
      expect(labelOf(tester, 'memory.card.0'), 'Card 1');

      // Two that differ: they show, then turn back over.
      final first = deck[0];
      final other = deck.indexWhere((f) => f != first);
      await tester.tap(byId('memory.card.0'));
      await tester.tap(byId('memory.card.$other'));
      await tester.pump(const Duration(milliseconds: 100));
      expect((labelOf(tester, 'memory.card.0'), labelOf(tester, 'memory.card.$other')), (first, deck[other]));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(labelOf(tester, 'memory.card.$other'), 'Card ${other + 1}');

      // Every pair, found.
      final pairs = <String, List<int>>{};
      for (final (i, f) in deck.indexed) {
        (pairs[f] ??= []).add(i);
      }
      for (final [a, b] in pairs.values) {
        await tester.tap(byId('memory.card.$a'));
        await tester.tap(byId('memory.card.$b'));
        await tester.pump(const Duration(milliseconds: 600));
        expect(labelOf(tester, 'memory.card.$a'), deck[a], reason: 'a pair stays up');
      }
      await h.settle();
      expect(await toyboxRounds(h), [('memory', 1, 'win')], reason: 'one slip on two pairs is still a win');
      expect(sound.played.map((p) => p.$1), containsAllInOrder([Sfx.tap, Sfx.tap, Sfx.sparkle, Sfx.sparkle, Sfx.cheer]));
      await tester.pump(const Duration(seconds: 3));
      await h.settle();
      expect(game.debugDeck, isNot(same(deck)), reason: 'a new board');
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a third card turns a pair that differs straight back; the top level deals twelve pairs, no peek', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await openToyboxGame(tester, 'memory', level: 6);
      final game = tester.state<MemoryGameState>(find.byType(MemoryGame));
      expect(game.debugDeck.length, 24);
      expect(game.debugPeeking, isFalse);
      final deck = game.debugDeck;
      final b = deck.indexWhere((f) => f != deck[0]);
      final c = deck.indexed.firstWhere((e) => e.$1 != 0 && e.$1 != b).$1;
      await tester.tap(byId('memory.card.0'));
      await tester.tap(byId('memory.card.$b'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(byId('memory.card.$c'));
      await tester.pump(const Duration(milliseconds: 400));
      expect((labelOf(tester, 'memory.card.0'), labelOf(tester, 'memory.card.$c')), ('Card 1', deck[c]));
      // The cards fit the wall: none hangs off the screen.
      for (var i = 0; i < 24; i++) {
        final r = tester.getRect(byId('memory.card.$i'));
        expect(const Rect.fromLTWH(0, 0, 1920, 1080).contains(r.bottomRight - const Offset(1, 1)), isTrue, reason: 'card $i at $r');
      }
      await h.shutdown();
      handle.dispose();
    });

    test('the board grid makes the biggest cards that fit', () {
      expect(memoryGrid(4, const Size(1800, 900)).cols, 4);
      expect(memoryGrid(4, const Size(800, 1400)).cols, 2);
      final wall = memoryGrid(24, const Size(1800, 900), gap: 14);
      expect(wall.cols * ((24 / wall.cols).ceil()), greaterThanOrEqualTo(24));
      expect(wall.card.height * (24 / wall.cols).ceil() + 14 * ((24 / wall.cols).ceil() - 1), lessThanOrEqualTo(900));
      expect(memoryGrid(4, const Size(1800, 900), maxWidth: 300).card.width, 300);
    });
  });

  group('Shape Sorter', () {
    Future<void> dragTo(WidgetTester tester, String from, String to) async {
      final a = tester.getCenter(byId(from)), b = tester.getCenter(byId(to));
      await tester.dragFrom(a, b - a);
      // The glide starts on the next frame.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('shapes drag into their holes; a wrong hole bounces one back; a full board is a win', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'shapes', sound: sound);
      final game = tester.state<ShapeGameState>(find.byType(ShapeGame));
      expect(game.debugShapes.toSet(), {ToyShape.circle, ToyShape.square});
      expectNoFallbackText(byId('screen.game'));
      final home = tester.getCenter(byId('shapes.piece.circle'));

      await dragTo(tester, 'shapes.piece.circle', 'shapes.hole.square');
      expect(sound.played.last.$1, Sfx.boing, reason: 'not that hole');
      await h.settle(4);
      expect((tester.getCenter(byId('shapes.piece.circle')) - home).distance, lessThan(2), reason: 'back in the tray');

      await dragTo(tester, 'shapes.piece.circle', 'shapes.hole.circle');
      expect(sound.played.last.$1, Sfx.snap);
      await h.settle(4);
      expect((tester.getCenter(byId('shapes.piece.circle')) - tester.getCenter(byId('shapes.hole.circle'))).distance, lessThan(2), reason: 'in its hole');

      await dragTo(tester, 'shapes.piece.square', 'shapes.hole.square');
      await h.settle();
      expect(await toyboxRounds(h), [('shapes', 1, 'win')], reason: 'one slip on two shapes is still a win');
      expect(sound.played.map((p) => p.$1), contains(Sfx.cheer));
      await tester.pump(const Duration(seconds: 3));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a shape can be tapped, then its hole; at the top level eight shapes meet turned holes', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await openToyboxGame(tester, 'shapes', level: 5);
      final game = tester.state<ShapeGameState>(find.byType(ShapeGame));
      expect((game.debugShapes.length, game.debugRotated), (8, true));
      await tester.tap(byId('shapes.piece.star'));
      await tester.pump();
      await tester.tap(byId('shapes.hole.star'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect((tester.getCenter(byId('shapes.piece.star')) - tester.getCenter(byId('shapes.hole.star'))).distance, lessThan(2));
      final star = tester.widget<AnimatedRotation>(find.descendant(of: byId('shapes.piece.star'), matching: find.byType(AnimatedRotation)));
      expect(star.turns.abs() * 360, inInclusiveRange(15, 35), reason: 'turned to fit its hole');
      for (final s in ToyShape.values) {
        final r = tester.getRect(byId('shapes.piece.${s.name}'));
        expect(const Rect.fromLTWH(0, 0, 1920, 1080).contains(r.center), isTrue, reason: '${s.name} at $r');
      }
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('on a portrait display the board and tray stack and every shape fits', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await openToyboxGame(tester, 'shapes', level: 4, size: const Size(1080, 1920));
      for (final s in tester.state<ShapeGameState>(find.byType(ShapeGame)).debugShapes) {
        final piece = tester.getRect(byId('shapes.piece.${s.name}')), hole = tester.getRect(byId('shapes.hole.${s.name}'));
        expect(piece.top, greaterThan(hole.bottom), reason: 'the tray is under the board');
        expect(const Rect.fromLTWH(0, 0, 1080, 1920).contains(piece.bottomRight - const Offset(1, 1)), isTrue);
      }
      await h.shutdown();
      handle.dispose();
    });
  });

  group('Jigsaw', () {
    Future<void> dragTo(WidgetTester tester, String from, Offset to) async {
      final a = tester.getCenter(byId(from));
      await tester.dragFrom(a, to - a);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('two pieces of a painted scene snap into their spots; the finished picture is a win, then a new one', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'jigsaw', sound: sound);
      final game = tester.state<JigsawGameState>(find.byType(JigsawGame));
      expect((game.debugReady, game.debugPhoto), (true, false), reason: 'no family photos in the demo: a painted scene');
      expect(game.debugGrid, (rows: 1, cols: 2));
      expectNoFallbackText(byId('screen.game'));
      for (final (n, id) in ['0.0', '0.1'].indexed) {
        await dragTo(tester, 'jigsaw.piece.$id', tester.getCenter(byId('jigsaw.slot.$id')));
        expect(labelOf(tester, 'jigsaw.board'), 'Puzzle: ${n + 1} of 2 in place', reason: id);
      }
      expect(sound.played.where((p) => p.$1 == Sfx.snap).length, 2);
      await h.settle();
      expect(await toyboxRounds(h), [('jigsaw', 1, 'win')]);
      await tester.pump(const Duration(milliseconds: 3500));
      await h.settle(4);
      expect(labelOf(tester, 'jigsaw.board'), startsWith('Puzzle: 0 of'), reason: 'a new puzzle');
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a piece dropped on another’s spot hops back; dropped anywhere else it stays put', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'jigsaw', sound: sound, level: 3);
      final game = tester.state<JigsawGameState>(find.byType(JigsawGame));
      expect(game.debugGrid, (rows: 2, cols: 3));
      final home = tester.getCenter(byId('jigsaw.piece.0.0'));
      await dragTo(tester, 'jigsaw.piece.0.0', tester.getCenter(byId('jigsaw.slot.1.2')));
      expect(sound.played.last.$1, Sfx.boing);
      expect((tester.getCenter(byId('jigsaw.piece.0.0')) - home).distance, lessThan(2));
      expect(labelOf(tester, 'jigsaw.piece.0.0'), 'Piece');

      final board = tester.getRect(byId('jigsaw.board'));
      final spot = Offset(board.left / 2, board.center.dy);
      await dragTo(tester, 'jigsaw.piece.0.0', spot);
      expect((tester.getCenter(byId('jigsaw.piece.0.0')) - spot).distance, lessThan(30), reason: 'where she left it');
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('twenty-four pieces wait above and below the board on a portrait display', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await openToyboxGame(tester, 'jigsaw', level: 7, size: const Size(1080, 1920));
      final game = tester.state<JigsawGameState>(find.byType(JigsawGame));
      expect(game.debugGrid, (rows: 6, cols: 4));
      final board = tester.getRect(byId('jigsaw.board'));
      for (var r = 0; r < 6; r++) {
        for (var c = 0; c < 4; c++) {
          final p = tester.getCenter(byId('jigsaw.piece.$r.$c'));
          expect(const Rect.fromLTWH(0, 0, 1080, 1920).contains(p), isTrue, reason: '$r.$c at $p');
          expect(board.contains(p), isFalse, reason: '$r.$c waits off the board');
        }
      }
      await h.shutdown();
      handle.dispose();
    });

    test('the pieces interlock: every tab fills the hole next to it', () {
      const rows = 4, cols = 6, cell = Size(150, 120), pad = 36.0;
      final tabs = jigsawTabs(rows, cols, math.Random(7));
      Path piece(int r, int c) => jigsawPiecePath(r, c, rows: rows, cols: cols, tabs: tabs, cell: cell, pad: pad).shift(Offset(c * cell.width - pad, r * cell.height - pad));
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols - 1; c++) {
          // Just past the edge, in the tab's direction: in exactly one piece.
          final out = tabs.right[r][c].toDouble();
          final p = Offset((c + 1) * cell.width + out * 0.2 * cell.height, (r + 0.5) * cell.height);
          expect((piece(r, c).contains(p), piece(r, c + 1).contains(p)), out > 0 ? (true, false) : (false, true), reason: 'right of $r.$c');
        }
      }
      for (var r = 0; r < rows - 1; r++) {
        for (var c = 0; c < cols; c++) {
          final out = tabs.down[r][c].toDouble();
          final p = Offset((c + 0.5) * cell.width, (r + 1) * cell.height + out * 0.2 * cell.height);
          expect((piece(r, c).contains(p), piece(r + 1, c).contains(p)), out > 0 ? (true, false) : (false, true), reason: 'below $r.$c');
        }
      }
      // Outer edges stay straight.
      expect(piece(0, 0).getBounds().topLeft, Offset.zero);
    });
  });
}
