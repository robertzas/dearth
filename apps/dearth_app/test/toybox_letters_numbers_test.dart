import 'package:dearth_app/core/sound.dart';
import 'package:dearth_app/features/toybox/games/biglittle.dart';
import 'package:dearth_app/features/toybox/games/dots.dart';
import 'package:dearth_app/features/toybox/games/dots_pictures.dart';
import 'package:dearth_app/features/toybox/games/hop.dart';
import 'package:dearth_app/features/toybox/games/spell.dart';
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
      await expectGamesLayOut(tester, const [('dots', 1), ('dots', 4), ('dots', 6), ('biglittle', 1), ('biglittle', 2), ('biglittle', 3), ('hop', 1), ('hop', 2), ('hop', 4), ('spell', 1), ('spell', 3), ('spell', 4)], size: size);
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

  group('Big & Little Letters', () {
    BigLittleGameState game(WidgetTester tester) => tester.state<BigLittleGameState>(find.byType(BigLittleGame));

    /// Taps small [letter], then the card of [capital].
    Future<void> pair(WidgetTester tester, String letter, String capital) async {
      final r = game(tester).debugRound;
      await tester.tap(byId('biglittle.little.${r.tray.indexOf(letter)}'));
      await tester.pump();
      await tester.tap(byId('biglittle.big.${r.letters.indexOf(capital)}'));
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('FR-TOY-03: each small letter finds its capital and the voice names the pair', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'biglittle', sound: sound, level: 1);
      final r = game(tester).debugRound;
      expect(r.letters, hasLength(3));
      expectNoFallbackText(byId('screen.game'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said, [VoiceLine.bigLittleStart]);
      expect(labelOf(tester, 'biglittle.ask'), 'Little letters find big letters');
      expect(labelOf(tester, 'biglittle.big.0'), 'Big ${r.letters[0].toUpperCase()}');
      expect(labelOf(tester, 'biglittle.little.0'), 'Little ${r.tray[0]}');
      for (final l in r.letters) {
        await pair(tester, l, l);
        expect(labelOf(tester, 'biglittle.big.${r.letters.indexOf(l)}'), 'Big ${l.toUpperCase()}, little $l');
        expect(labelOf(tester, 'biglittle.little.${r.tray.indexOf(l)}'), 'Little $l, home');
      }
      expect(labelOf(tester, 'biglittle.ask'), 'All found!');
      // Tapping a small letter says its name; a pair names both letters.
      expect(sound.said, [VoiceLine.bigLittleStart, for (final l in r.letters) ...[letterNameClip(l), bigLittleClip(l)]]);
      // The last pair is said in full before the cheer.
      await tester.pump(afterVoice(bigLittleClip(r.letters.last)));
      await h.settle();
      expect(sound.said.last, VoiceLine.bigLittleDone);
      expect(await toyboxRounds(h), [('biglittle', 1, 'win')]);
      await tester.pump(const Duration(seconds: 4));
      expect(game(tester).debugRound.letters.toSet(), isNot(r.letters.toSet()), reason: 'new letters next round');
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('she can drag a small letter onto its capital; dropped short, it floats back', (tester) async {
      final h = await openToyboxGame(tester, 'biglittle', level: 1);
      final r = game(tester).debugRound;
      final l = r.letters.first;
      final token = byId('biglittle.little.${r.tray.indexOf(l)}');
      final from = tester.getCenter(token);
      final card = tester.getCenter(byId('biglittle.big.0'));
      await tester.dragFrom(from, (card - from) * 0.3);
      await tester.pump(const Duration(milliseconds: 500));
      expect(labelOf(tester, 'biglittle.little.${r.tray.indexOf(l)}'), 'Little $l');
      expect(tester.getCenter(token), offsetMoreOrLessEquals(from, epsilon: 1));
      await tester.dragFrom(from, card - from);
      await tester.pump(const Duration(milliseconds: 500));
      expect(labelOf(tester, 'biglittle.big.0'), 'Big ${l.toUpperCase()}, little $l');
      await tester.pump(const Duration(seconds: 1));
      await h.shutdown();
    });

    testWidgets('b, d, p and q: a wrong card wiggles and names the letter she holds; two slips are helped', (tester) async {
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'biglittle', sound: sound, level: 3);
      final r = game(tester).debugRound;
      expect(r.letters.toSet(), {'b', 'd', 'p', 'q'});
      await tester.pump(const Duration(milliseconds: 700));
      final l = r.letters.first, wrong = r.letters[1];
      await pair(tester, l, wrong);
      expect(sound.played.map((p) => p.$1), contains(Sfx.nope));
      expect(sound.said.last, letterNameClip(l));
      expect(labelOf(tester, 'biglittle.big.1'), 'Big ${wrong.toUpperCase()}', reason: 'nothing paired');
      await pair(tester, l, wrong);
      for (final x in r.letters) {
        await pair(tester, x, x);
      }
      await tester.pump(afterVoice(bigLittleClip(r.letters.last)));
      await h.settle();
      expect(await toyboxRounds(h), [('biglittle', 3, 'helped')]);
      await tester.pump(const Duration(seconds: 4));
      await h.shutdown();
    });

    testWidgets('a long pause nudges the next small letter and says its name, without a slip', (tester) async {
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'biglittle', sound: sound, level: 2);
      final r = game(tester).debugRound;
      await tester.pump(const Duration(seconds: 13));
      expect(sound.said.last, letterNameClip(r.tray.first));
      await pair(tester, r.tray.first, r.tray.first);
      expect(sound.said.last, bigLittleClip(r.tray.first));
      await h.shutdown();
    });
  });

  group('Frog Hop', () {
    HopGameState game(WidgetTester tester) => tester.state<HopGameState>(find.byType(HopGame));

    /// Plays out every hop frame by frame, as a screen would: the hop starts
    /// on the frame after the tap, and each pad's note plays as it lands.
    Future<void> fly(WidgetTester tester, HopRound r) async {
      await tester.pump();
      for (var i = 0; i < r.hops; i++) {
        await tester.pump(HopGameState.hopTime);
      }
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('FR-TOY-03: "Hop to …": the right pad sends the frog there a pad at a time, and it says where it landed', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'hop', sound: sound, level: 1);
      final r = game(tester).debugRound;
      expect(r.mode, HopMode.find);
      expectNoFallbackText(byId('screen.game'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said, [hopAskClip(r)]);
      expect(labelOf(tester, 'hop.ask'), 'Hop to ${r.target}');
      expect(labelOf(tester, 'hop.pad.${r.from}'), '${r.from}, frog');
      expect(labelOf(tester, 'hop.frog'), 'Frog on ${r.from}');
      await tester.tap(byId('hop.pad.${r.target}'));
      await fly(tester, r);
      // A note for every pad it lands on, rising as the numbers grow.
      // Only the notes: the landing cheer has a rate too.
      final rates = [for (var i = 0; i < sound.played.length; i++) if (sound.played[i].$1 == Sfx.xylophone) sound.rates[i]];
      expect(rates, hasLength(r.hops));
      final rising = <double>[...rates]..sort();
      expect(rates, r.target > r.from ? rising : rising.reversed.toList());
      expect(sound.said.last, numberClip(r.target));
      expect(labelOf(tester, 'hop.ask'), 'Landed on ${r.target}!');
      expect(labelOf(tester, 'hop.pad.${r.target}'), '${r.target}, frog');
      await h.settle();
      expect(await toyboxRounds(h), [('hop', 1, 'win')]);
      await tester.pump(const Duration(seconds: 4));
      expect(labelOf(tester, 'hop.ask'), isNot('Landed on ${r.target}!'), reason: 'a new round');
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a wrong pad wiggles and says its number; after two, the right pad glows and the round is a miss', (tester) async {
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'hop', sound: sound, level: 3);
      final r = game(tester).debugRound;
      expect(r.mode, isIn([HopMode.oneMore, HopMode.oneLess]));
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said, [hopAskClip(r)]);
      final wrong = [for (var n = 0; n < r.pads; n++) n].firstWhere((n) => n != r.target && n != r.from);
      for (var i = 0; i < 2; i++) {
        await tester.tap(byId('hop.pad.$wrong'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(sound.said.last, numberClip(wrong));
      }
      expect(sound.played.where((p) => p.$1 == Sfx.nope), hasLength(2));
      expect(labelOf(tester, 'hop.frog'), 'Frog on ${r.from}', reason: 'a wrong pad never moves the frog');
      await tester.tap(byId('hop.pad.${r.target}'));
      await fly(tester, r);
      await h.settle();
      expect(await toyboxRounds(h), [('hop', 3, 'miss')]);
      await tester.pump(const Duration(seconds: 4));
      await h.shutdown();
    });

    testWidgets('adding: "3 and 2 more" hops the frog the extra pads from where it sits', (tester) async {
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'hop', sound: sound, level: 4);
      final r = game(tester).debugRound;
      expect(r.mode, HopMode.add);
      await tester.pump(const Duration(milliseconds: 700));
      expect(labelOf(tester, 'hop.ask'), '${r.from} and ${r.hops} more');
      expect(sound.said, [hopAskClip(r)]);
      await tester.tap(byId('hop.pad.${r.target}'));
      await fly(tester, r);
      expect(sound.played.where((p) => p.$1 == Sfx.xylophone), hasLength(r.hops));
      expect(labelOf(tester, 'hop.frog'), 'Frog on ${r.target}');
      await h.settle();
      expect(await toyboxRounds(h), [('hop', 4, 'win')]);
      await tester.pump(const Duration(seconds: 4));
      await h.shutdown();
    });

    testWidgets('a long pause asks again without counting a slip', (tester) async {
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'hop', sound: sound, level: 2);
      final r = game(tester).debugRound;
      await tester.pump(const Duration(seconds: 13));
      expect(sound.said, [hopAskClip(r), hopAskClip(r)]);
      await tester.tap(byId('hop.pad.${r.target}'));
      await fly(tester, r);
      await h.settle();
      expect(await toyboxRounds(h), [('hop', 2, 'win')]);
      await tester.pump(const Duration(seconds: 4));
      await h.shutdown();
    });
  });

  group('Word Builder', () {
    SpellGameState game(WidgetTester tester) => tester.state<SpellGameState>(find.byType(SpellGame));

    /// Fills every open slot with its tile, left to right.
    Future<void> build(WidgetTester tester) async {
      while (game(tester).debugActive != null) {
        await tester.tap(byId('spell.tile.${game(tester).debugTile()}'));
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    /// The word read back sound by sound, then the word, then the round.
    Future<void> blend(WidgetTester tester) async {
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    testWidgets('FR-TOY-03: the first sound is missing; its tile fills the slot, then the word is read back sound by sound', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'spell', sound: sound, level: 1);
      final r = game(tester).debugRound;
      final word = r.letters;
      expect(r.missing, [0]);
      expectNoFallbackText(byId('screen.game'));
      // The word, then once it has finished, what to do.
      await tester.pump(const Duration(seconds: 3));
      expect(sound.said, [r.word.clip, VoiceLine.spellMissing]);
      expect(labelOf(tester, 'spell.ask'), 'Which sound is missing in $word?');
      expect(labelOf(tester, 'spell.picture'), word);
      expect(labelOf(tester, 'spell.slot.0'), 'Slot 1: empty, next');
      expect(labelOf(tester, 'spell.slot.1'), 'Slot 2: ${word[1]}');
      final right = game(tester).debugTile();
      expect(labelOf(tester, 'spell.tile.$right'), 'Letter ${word[0]}');
      sound.said.clear();
      await tester.tap(byId('spell.tile.$right'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(sound.said, [soundClip(word[0])], reason: 'every tile says its sound');
      expect(labelOf(tester, 'spell.slot.0'), 'Slot 1: ${word[0]}');
      expect(labelOf(tester, 'spell.tile.$right'), 'Letter ${word[0]}, placed');
      expect(labelOf(tester, 'spell.ask'), 'You built $word!');
      await blend(tester);
      expect(sound.said.take(word.length + 2), [soundClip(word[0]), for (final l in word.split('')) soundClip(l), r.word.clip]);
      await h.settle();
      expect(await toyboxRounds(h), [('spell', 1, 'win')]);
      await tester.pump(const Duration(seconds: 4));
      expect(labelOf(tester, 'spell.ask'), isNot('You built $word!'), reason: 'a new round');
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a wrong tile says its sound and wiggles back; slips make the round "helped", then a miss', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'spell', sound: sound, level: 3);
      final r = game(tester).debugRound;
      expect(r.missing, [0, 1, 2]);
      expect(labelOf(tester, 'spell.ask'), 'Build ${r.letters}');
      await tester.pump(const Duration(seconds: 3));
      expect(sound.said.last, VoiceLine.spellBuild);
      final wrong = game(tester).debugTile(right: false);
      await tester.tap(byId('spell.tile.$wrong'));
      await tester.pump(const Duration(milliseconds: 600));
      expect(sound.said.last, soundClip(r.tiles[wrong]));
      expect(sound.played.where((p) => p.$1 == Sfx.nope), hasLength(1));
      expect(labelOf(tester, 'spell.tile.$wrong'), 'Letter ${r.tiles[wrong]}', reason: 'back in the tray');
      expect(labelOf(tester, 'spell.slot.0'), 'Slot 1: empty, next');
      await build(tester);
      expect(labelOf(tester, 'spell.slot.2'), 'Slot 3: ${r.letters[2]}');
      await blend(tester);
      await h.settle();
      expect(await toyboxRounds(h), [('spell', 3, 'helped')]);
      await tester.pump(const Duration(seconds: 4));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('four-letter words: a slip per word is still a win', (tester) async {
      final h = await openToyboxGame(tester, 'spell', level: 4);
      final r = game(tester).debugRound;
      expect(r.letters, hasLength(4));
      expect(r.tiles, hasLength(5));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(byId('spell.tile.${game(tester).debugTile(right: false)}'));
      await tester.pump(const Duration(milliseconds: 600));
      await build(tester);
      await blend(tester);
      await h.settle();
      expect(await toyboxRounds(h), [('spell', 4, 'win')]);
      await tester.pump(const Duration(seconds: 4));
      await h.shutdown();
    });

    testWidgets('a tile dragged onto the open slot goes in; dropped far away, it floats back', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'spell', sound: sound, level: 2);
      final r = game(tester).debugRound;
      final last = r.letters.length - 1;
      expect(r.missing, [last]);
      final right = game(tester).debugTile();
      final tile = byId('spell.tile.$right');
      // Nowhere near a slot: back to the tray.
      await tester.drag(tile, const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 500));
      expect(labelOf(tester, 'spell.tile.$right'), 'Letter ${r.letters[last]}');
      expect(sound.said, contains(soundClip(r.letters[last])), reason: 'picking it up says its sound');
      final to = tester.getCenter(byId('spell.slot.$last'));
      await tester.dragFrom(tester.getCenter(tile), to - tester.getCenter(tile));
      await tester.pump(const Duration(milliseconds: 500));
      expect(labelOf(tester, 'spell.slot.$last'), 'Slot ${last + 1}: ${r.letters[last]}');
      await blend(tester);
      await h.settle();
      expect(await toyboxRounds(h), [('spell', 2, 'win')]);
      await tester.pump(const Duration(seconds: 4));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a long pause says the sound she needs, without counting a slip', (tester) async {
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'spell', sound: sound, level: 1);
      final r = game(tester).debugRound;
      await tester.pump(const Duration(seconds: 13));
      expect(sound.said.last, soundClip(r.letters[0]));
      await build(tester);
      await blend(tester);
      await h.settle();
      expect(await toyboxRounds(h), [('spell', 1, 'win')]);
      await tester.pump(const Duration(seconds: 4));
      await h.shutdown();
    });
  });
}
