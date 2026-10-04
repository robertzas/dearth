import 'package:dearth_app/core/sound.dart';
import 'package:dearth_app/features/toybox/games/coloring.dart';
import 'package:dearth_app/features/toybox/games/coloring_pictures.dart';
import 'package:dearth_app/features/toybox/games/paint.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_harness.dart';
import 'support/toybox_harness.dart';

/// The Toybox's art games (SPEC FR-TOY-02): Magic Coloring and Paint
/// Studio, played through the Toybox on the demo household.
void main() {
  group('Magic Coloring', () {
    test('every picture suits one level, each level has pictures, and a tap inside each part finds it', () {
      final pictures = [for (final make in kColoringPictures) make()];
      expect(pictures.map((p) => p.id).toSet().length, pictures.length);
      for (var level = 1; level <= 5; level++) {
        expect(pictures.where((p) => coloringFits(p.regions.length, level)).length, greaterThanOrEqualTo(2), reason: 'level $level');
      }
      for (final p in pictures) {
        expect([for (var l = 1; l <= 5; l++) coloringFits(p.regions.length, l)].where((f) => f).length, 1, reason: '${p.id}: ${p.regions.length} parts');
        final ready = PreparedPicture.of(p);
        for (final (i, a) in ready.anchors.indexed) {
          expect(ready.partAt(a), i, reason: '${p.id} part $i at $a');
          // Well inside, not on a line.
          for (final d in const [Offset(8, 0), Offset(-8, 0), Offset(0, 8), Offset(0, -8)]) {
            expect(ready.visible[i].contains(a + d), isTrue, reason: '${p.id} part $i is too thin at $a');
          }
          expect(const Offset(0, 0) & kPictureSize, predicate<Rect>((r) => r.contains(a)), reason: '${p.id} part $i');
        }
      }
    });

    testWidgets('a crayon and a tap color a part from the finger out; a full picture is a win, then the arrow brings another', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'coloring', sound: sound);
      final game = tester.state<ColoringGameState>(find.byType(ColoringGame));
      final first = game.debugPicture;
      final parts = game.debugFills.length;
      expect(parts, inInclusiveRange(3, 5), reason: 'level 1: big parts');
      expect(labelOf(tester, 'coloring.canvas'), 'Colored 0 of $parts');
      expectNoFallbackText(byId('screen.game'));

      await tester.tap(byId('coloring.color.blue'));
      await tester.pump();
      await tester.tap(byId('coloring.region.0'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(game.debugFills[0], isNull, reason: 'still spreading');
      await tester.pump(const Duration(milliseconds: 300));
      expect(game.debugFills[0], kCrayons.firstWhere((c) => c.$1 == 'blue').$2);
      expect(sound.played.last.$1, Sfx.sparkle);

      await tester.tap(byId('coloring.color.yellow'));
      for (var i = 1; i < parts; i++) {
        await tester.tap(byId('coloring.region.$i'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(labelOf(tester, 'coloring.canvas'), 'Colored $parts of $parts');
      await h.settle();
      expect(await toyboxRounds(h), [('coloring', 1, 'win')]);
      expect(byId('coloring.next'), findsOneWidget);

      // Recoloring a finished picture is fine and records nothing more.
      await tester.tap(byId('coloring.color.red'));
      await tester.tap(byId('coloring.region.0'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await h.settle(4);
      expect((await toyboxRounds(h)).length, 1);

      await tester.tap(byId('coloring.next'));
      await tester.pump();
      expect(game.debugPicture, isNot(first));
      expect(game.debugFills.every((f) => f == null), isTrue);
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('the top level brings two dozen small parts, every one reachable on a portrait display', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await openToyboxGame(tester, 'coloring', level: 5, size: const Size(1080, 1920));
      final game = tester.state<ColoringGameState>(find.byType(ColoringGame));
      expect(game.debugFills.length, greaterThanOrEqualTo(24));
      for (var i = 0; i < game.debugFills.length; i++) {
        expect(const Rect.fromLTWH(0, 0, 1080, 1920).contains(tester.getCenter(byId('coloring.region.$i'))), isTrue);
      }
      await tester.tap(byId('coloring.region.${game.debugFills.length - 1}'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(game.debugFills.last, isNotNull, reason: 'the smallest part takes a tap too');
      await h.shutdown();
      handle.dispose();
    });
  });

  group('Paint Studio', () {
    Future<void> scribble(WidgetTester tester, {Offset from = Offset.zero, Offset by = const Offset(220, 90)}) async {
      final paper = tester.getRect(byId('paint.paper'));
      await tester.dragFrom(paper.center + from, by);
      await tester.pump();
    }

    testWidgets('a stroke goes on the paper at once; undo takes marks back one by one', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await openToyboxGame(tester, 'paint');
      expect(labelOf(tester, 'paint.paper'), 'Painting: 0 marks');
      expect(byId('paint.tool.stamp'), findsNothing, reason: 'stamps come at level 2');
      expect(byId('paint.mirror'), findsNothing, reason: 'the mirror comes at level 3');
      expectNoFallbackText(byId('screen.game'));
      await scribble(tester);
      expect(labelOf(tester, 'paint.paper'), 'Painting: 1 mark');
      for (final tool in ['crayon', 'marker', 'spray', 'rainbow']) {
        await tester.tap(byId('paint.tool.$tool'));
        await tester.tap(byId('paint.color.red'));
        await scribble(tester, from: const Offset(-200, -100));
      }
      expect(tester.state<PaintGameState>(find.byType(PaintGame)).debugMarks, 5);
      await tester.tap(byId('paint.undo'));
      await tester.pump();
      expect(labelOf(tester, 'paint.paper'), 'Painting: 4 marks');
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a new sheet starts fresh, and undo brings the last painting back', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await openToyboxGame(tester, 'paint');
      final game = tester.state<PaintGameState>(find.byType(PaintGame));
      await scribble(tester);
      await scribble(tester, from: const Offset(-150, 60));
      await tester.tap(byId('paint.new'));
      await tester.pump();
      expect(byId('paint.paper.meadow'), findsNothing, reason: 'scenes come at level 2');
      await tester.tap(byId('paint.paper.night'));
      await tester.pump();
      expect((game.debugMarks, game.debugPaper), (0, Paper.night));
      await tester.tap(byId('paint.undo'));
      await tester.pump();
      expect((game.debugMarks, game.debugPaper), (2, Paper.white), reason: 'nothing is lost for good');
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('stamps and painted papers at level 2, the mirror at 3; a long scribble is put down in pieces', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'paint', sound: sound, level: 3);
      final game = tester.state<PaintGameState>(find.byType(PaintGame));
      await tester.tap(byId('paint.tool.stamp'));
      await tester.pump();
      await tester.tap(byId('paint.stamp.3'));
      await tester.tap(byId('paint.paper'));
      await tester.pump();
      expect(game.debugMarks, 1);
      expect(sound.played.last.$1, Sfx.pop);
      await tester.tap(byId('paint.mirror'));
      await tester.pump();
      expect(labelOf(tester, 'paint.mirror'), 'Mirror on');

      await tester.tap(byId('paint.tool.brush'));
      final paper = tester.getRect(byId('paint.paper'));
      final g = await tester.startGesture(paper.center);
      for (var i = 0; i < 300; i++) {
        await g.moveBy(Offset(i.isEven ? 3 : -2, 1.2));
      }
      await g.up();
      await tester.pump();
      expect(game.debugMarks, 3, reason: 'one stamp and a scribble in two pieces');

      await tester.tap(byId('paint.new'));
      await tester.pump();
      await tester.tap(byId('paint.paper.meadow'));
      await tester.pump();
      expect(game.debugPaper, Paper.meadow);
      await h.shutdown();
      handle.dispose();
    });
  });
}
