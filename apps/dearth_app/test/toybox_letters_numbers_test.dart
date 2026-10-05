import 'package:dearth_app/core/sound.dart';
import 'package:dearth_app/features/toybox/games/dots.dart';
import 'package:dearth_app/features/toybox/games/dots_pictures.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_harness.dart';
import 'support/toybox_harness.dart';

/// The Toybox's number and letter games (SPEC FR-TOY-03, Appendix B),
/// played through the Toybox on the demo household. What they say is
/// checked by clip id.
void main() {
  for (final size in const [Size(390, 844), Size(844, 390), Size(1080, 1920), Size(1920, 1080)]) {
    testWidgets('every number and letter game lays out on a ${size.width.toInt()}×${size.height.toInt()} screen at its busiest level', (tester) async {
      for (final (game, level) in const [('dots', 1), ('dots', 4), ('dots', 6)]) {
        final h = await openToyboxGame(tester, game, level: level, size: size);
        await tester.pump(const Duration(seconds: 1));
        // An overflow would have been thrown as a layout error.
        expect(tester.takeException(), isNull, reason: '$game $level');
        await h.shutdown();
      }
    });
  }

  group('Dot-to-Dot', () {
    DotsGameState game(WidgetTester tester) => tester.state<DotsGameState>(find.byType(DotsGame));

    /// The dots not yet joined, farthest from the next one first: wrong
    /// taps that can't be mistaken for the right one.
    List<String> wrongDots(DotsGameState s) {
      final r = s.debugRound;
      final g = DotGeometry.of(dotArtOf(r.picture.id), r.labels.length);
      final next = g.points[s.debugJoined];
      final away = [for (var i = s.debugJoined + 1; i < r.labels.length; i++) i]..sort((a, b) => (g.points[b] - next).distance.compareTo((g.points[a] - next).distance));
      return [for (final i in away) r.labels[i]];
    }

    test('FR-TOY-03: every picture, at every level, has its dots apart, in order and on the paper', () {
      expect(dotArts.keys.toSet(), {for (final p in kDotPictures) p.id}, reason: 'an outline for every picture');
      for (final id in dotArts.keys) {
        for (var level = 1; level <= 6; level++) {
          final n = dotLabels(level).length;
          final g = DotGeometry.of(dotArtOf(id), n);
          final why = '$id with $n dots';
          expect(g.points, hasLength(n), reason: why);
          expect(g.dots.first, 0, reason: '$why: dot 1 sits where the outline starts');
          for (var i = 1; i < n; i++) {
            expect(g.dots[i], greaterThan(g.dots[i - 1]), reason: '$why: the dots go round in order');
          }
          // Far enough apart to read on a phone, and never touching on the
          // smallest board (a phone on its side) or the biggest.
          expect(g.minGap, greaterThanOrEqualTo(55), reason: why);
          for (final board in const [260.0, 356.0, 840.0, 1016.0]) {
            final d = dotDiameter(board, g);
            expect(d, lessThan(g.minGap * board / 1000), reason: '$why on a $board px board');
            expect(d, greaterThanOrEqualTo(14), reason: '$why on a $board px board');
          }
          final r = dotDiameter(1000, g) / 2;
          for (final p in g.points) {
            expect(p.dx >= r && p.dx <= 1000 - r && p.dy >= r && p.dy <= 1000 - r, isTrue, reason: '$why: $p is on the paper');
          }
        }
      }
      // The youngest get big dots: a tenth of the board.
      expect(dotDiameter(1000, DotGeometry.of(dotArtOf('star'), 5)), greaterThanOrEqualTo(100));
      // Five dots on a star are its five points.
      final star = DotGeometry.of(dotArtOf('star'), 5);
      expect([for (final p in star.points) (p.dx.round(), p.dy.round())], [(500, 120), (890, 403), (741, 862), (259, 862), (110, 403)]);
    });

    testWidgets('FR-TOY-03: she joins the dots in order; each says its number, and the picture says what it is', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'dots', sound: sound, level: 1);
      final r = game(tester).debugRound;
      expect(r.labels, ['1', '2', '3', '4', '5']);
      expectNoFallbackText(byId('screen.game'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said, [VoiceLine.dotsNumbers]);
      expect(labelOf(tester, 'dots.ask'), 'Start at 1');
      expect(labelOf(tester, 'dots.board'), 'Join the dots: 0 of 5');
      for (final l in r.labels) {
        await tester.tap(byId('dots.dot.$l'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(sound.said.last, numberClip(int.parse(l)));
        expect(labelOf(tester, 'dots.dot.$l'), '$l, joined');
      }
      expect(labelOf(tester, 'dots.board'), 'Join the dots: 5 of 5');
      // A note per dot, climbing.
      final notes = [
        for (var i = 0; i < sound.played.length; i++)
          if (sound.played[i].$1 == Sfx.xylophone) sound.rates[i],
      ];
      expect(notes, hasLength(5));
      for (var i = 1; i < notes.length; i++) {
        expect(notes[i], greaterThan(notes[i - 1]));
      }
      // The line closes the shape, and the picture says what it is.
      await tester.pump(const Duration(milliseconds: 900));
      expect(sound.said.last, dotsDoneClip(r.picture));
      expect(labelOf(tester, 'dots.ask'), "It's ${r.picture.phrase}!");
      expect(labelOf(tester, 'dots.board'), "It's ${r.picture.phrase}!");
      expect(sound.played.where((p) => p.$1 == Sfx.xylophone), hasLength(9), reason: 'and a run up the scale as it closes');
      await tester.pump(const Duration(milliseconds: 1600));
      await h.settle();
      expect(await toyboxRounds(h), [('dots', 1, 'win')]);
      // Then a new picture, not the same one.
      await tester.pump(const Duration(seconds: 4));
      expect(game(tester).debugJoined, 0);
      expect(game(tester).debugRound.picture, isNot(r.picture));
      expect(labelOf(tester, 'dots.board'), 'Join the dots: 0 of 5');
      await tester.pump(const Duration(seconds: 3));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a wrong dot wiggles and the voice says which to find; after two, the next dot glows', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'dots', sound: sound, level: 2);
      final r = game(tester).debugRound;
      expect(r.labels, hasLength(10));
      await tester.pump(const Duration(milliseconds: 700));
      final wrong = wrongDots(game(tester));
      await tester.tap(byId('dots.dot.${wrong[0]}'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.played.last.$1, Sfx.nope);
      expect(sound.said.last, findNumberClip(1));
      expect(labelOf(tester, 'dots.dot.1'), '1');
      await tester.tap(byId('dots.dot.${wrong[1]}'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(labelOf(tester, 'dots.dot.1'), '1, next');
      await tester.tap(byId('dots.dot.1'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(labelOf(tester, 'dots.dot.1'), '1, joined');
      expect(game(tester).debugHint, isFalse);
      expect(labelOf(tester, 'dots.ask'), 'What comes after 1?');
      // The speaker says which dot is next; that isn't a slip.
      await tester.tap(byId('dots.ask.again'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, findNumberClip(2));
      await tester.tap(byId('dots.dot.${wrongDots(game(tester)).first}'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(game(tester).debugSlips, 3);
      for (final l in r.labels.skip(1)) {
        await tester.tap(byId('dots.dot.$l'));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 2600));
      await h.settle();
      // Three slips in ten dots: helped (a win allows two).
      expect(await toyboxRounds(h), [('dots', 2, 'helped')]);
      await tester.pump(const Duration(seconds: 6));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('she can draw through the dots in one stroke', (tester) async {
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'dots', sound: sound, level: 1);
      final r = game(tester).debugRound;
      await tester.pump(const Duration(milliseconds: 700));
      final at = [for (final l in r.labels) tester.getCenter(byId('dots.dot.$l'))];
      final finger = await tester.startGesture(at.first);
      await tester.pump(const Duration(milliseconds: 16));
      for (var i = 1; i < at.length; i++) {
        for (var k = 1; k <= 6; k++) {
          await finger.moveTo(Offset.lerp(at[i - 1], at[i], k / 6)!);
          await tester.pump(const Duration(milliseconds: 16));
        }
      }
      await finger.up();
      expect(game(tester).debugJoined, 5);
      expect(game(tester).debugSlips, 0);
      expect(sound.said.where((c) => c.startsWith('num_')), [for (final l in r.labels) numberClip(int.parse(l))]);
      await tester.pump(const Duration(milliseconds: 2600));
      await h.settle();
      expect(await toyboxRounds(h), [('dots', 1, 'win')]);
      await tester.pump(const Duration(seconds: 6));
      await h.shutdown();
    });

    testWidgets('touching a dot she has already joined is never a slip', (tester) async {
      final h = await openToyboxGame(tester, 'dots', level: 1);
      await tester.pump(const Duration(milliseconds: 700));
      for (final l in ['1', '1', '2', '1', '2']) {
        await tester.tap(byId('dots.dot.$l'));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(game(tester).debugJoined, 2);
      expect(game(tester).debugSlips, 0);
      await tester.pump(const Duration(seconds: 2));
      await h.shutdown();
    });

    testWidgets('letters: A to M, each joined letter says its name, and a wrong one asks for the next', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'dots', sound: sound, level: 5);
      final r = game(tester).debugRound;
      expect(r.letters, isTrue);
      expect(r.labels.first, 'A');
      expect(r.labels.last, 'M');
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said, [VoiceLine.dotsLetters]);
      expect(labelOf(tester, 'dots.ask'), 'Start at A');
      await tester.tap(byId('dots.dot.A'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, letterNameClip('A'));
      await tester.tap(byId('dots.dot.${wrongDots(game(tester)).first}'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, findLetterClip('B'));
      expect(labelOf(tester, 'dots.ask'), 'What comes after A?');
      await tester.pump(const Duration(seconds: 2));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a long pause shows the next dot and says it again, without counting a slip', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'dots', sound: sound, level: 1);
      await tester.pump(const Duration(milliseconds: 700));
      expect(labelOf(tester, 'dots.dot.1'), '1');
      await tester.pump(const Duration(seconds: 9));
      expect(sound.said, [VoiceLine.dotsNumbers, VoiceLine.dotsNumbers]);
      expect(labelOf(tester, 'dots.dot.1'), '1, next');
      await tester.tap(byId('dots.dot.1'));
      await tester.pump(const Duration(seconds: 10));
      expect(sound.said.last, findNumberClip(2));
      expect(labelOf(tester, 'dots.dot.2'), '2, next');
      expect(game(tester).debugSlips, 0);
      await h.shutdown();
      handle.dispose();
    });
  });
}
