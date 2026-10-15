import 'package:dearth_app/core/sound.dart';
import 'package:dearth_app/features/toybox/games/dice.dart';
import 'package:dearth_app/features/toybox/games/drums.dart';
import 'package:dearth_app/features/toybox/games/peekaboo.dart';
import 'package:dearth_app/features/toybox/games/tower.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_harness.dart';
import 'support/toybox_harness.dart';

/// The fourth set (SPEC FR-TOY-03, 2026-10-13): Dice Dash, Block Tower,
/// Drum Count and Peekaboo Pals, played through the Toybox.
void main() {
  for (final size in const [Size(390, 844), Size(844, 390), Size(1080, 1920), Size(1920, 1080)]) {
    testWidgets('every game of the fourth set lays out on a ${size.width.toInt()}×${size.height.toInt()} screen at its busiest level', (tester) async {
      await expectGamesLayOut(tester, const [('dice', 1), ('dice', 4), ('tower', 1), ('tower', 4), ('drums', 1), ('drums', 4), ('peekaboo', 3), ('peekaboo', 4)], size: size);
    });
  }

  Future<void> seconds(WidgetTester tester, double s) async {
    for (var i = 0; i < (s * 10).round(); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('Dice Dash', () {
    testWidgets('FR-TOY-03: roll, hear the number, hop square by square counting, all the way to the cake', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'dice', sound: sound, level: 1);
      final game = tester.state<DiceGameState>(find.byType(DiceGame));
      expect(sound.said, [VoiceLine.diceRoll]);
      expectNoFallbackText(byId('screen.game'));
      var slipped = false;
      for (var turn = 0; turn < 20 && game.debugAt < game.debugBoard.cake; turn++) {
        await tester.tap(byId('dice.die'));
        await seconds(tester, 1);
        final n = game.debugRoll.single;
        expect(n, inInclusiveRange(1, 3));
        expect(sound.said.last, diceHopClip(n), reason: '"Two! Hop two times!"');
        if (!slipped && game.debugAt + 3 < game.debugBoard.cake) {
          // Not that square: a soft "uh-uh", and she stays put.
          await tester.tap(byId('dice.square.${game.debugAt + 3}'));
          await tester.pump(const Duration(milliseconds: 100));
          expect(sound.played.last.$1, Sfx.nope);
          slipped = true;
        }
        for (var k = 1; k <= n && game.debugAt < game.debugBoard.cake; k++) {
          final from = game.debugAt;
          await tester.tap(byId('dice.square.${from + 1}'));
          await tester.pump(const Duration(milliseconds: 100));
          expect(game.debugAt, from + 1);
          expect(sound.said.last, numberClip(k), reason: 'each hop counted');
        }
        await seconds(tester, 2);
      }
      expect(game.debugAt, game.debugBoard.cake);
      expect(sound.said, contains(VoiceLine.diceCake));
      expect(await toyboxRounds(h), [('dice', 1, 'win')], reason: 'one slip on a whole board is still a win');
      await seconds(tester, 5);
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('level 3: she says where she will land; a wrong square wiggles, after two the right one glows', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'dice', sound: sound, level: 3);
      final game = tester.state<DiceGameState>(find.byType(DiceGame));
      await tester.tap(byId('dice.die'));
      await seconds(tester, 1);
      final target = game.debugLanding;
      expect(sound.said.last, diceLandClip(game.debugRoll.single));
      final wrong = target == 1 ? 2 : target - 1;
      for (var i = 0; i < 2; i++) {
        await tester.tap(byId('dice.square.$wrong'));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(labelOf(tester, 'dice.square.$target'), contains('glowing'));
      await tester.tap(byId('dice.square.$target'));
      await seconds(tester, 6);
      expect(game.debugAt, game.debugBoard.afterJump(target), reason: 'it hopped there by itself (and took any ladder or slide)');
      await h.shutdown();
      handle.dispose();
    });
  });

  group('Block Tower', () {
    Future<void> tapTop(WidgetTester tester, int height) async {
      final r = tester.getRect(byId('tower.tower'));
      final block = r.height / (kTowerMax + 0.6);
      await tester.tapAt(Offset(r.center.dx, r.bottom - block * (height - 0.5)));
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('FR-TOY-03: each block is counted; too tall says so and the top one comes off; the bell at the right height is a helped round', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'tower', sound: sound, level: 1);
      final game = tester.state<TowerGameState>(find.byType(TowerGame));
      final n = game.debugRound.target;
      expect(sound.said, [towerBuildClip(n)]);
      expectNoFallbackText(byId('screen.game'));
      for (var k = 1; k <= n + 1; k++) {
        await tester.tap(byId('tower.pile'));
        await tester.pump(const Duration(milliseconds: 450));
        expect(sound.said.last, numberClip(k));
      }
      expect(labelOf(tester, 'tower.tower'), 'Tower: ${n + 1} blocks');
      await tester.tap(byId('tower.bell'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, VoiceLine.towerTall);
      await tapTop(tester, n + 1);
      expect(game.debugHeight, n);
      await tester.tap(byId('tower.bell'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, towerYesClip(n));
      await h.settle();
      expect(await toyboxRounds(h), [('tower', 1, 'helped')]);
      await seconds(tester, 6);
      expect(sound.said, contains(VoiceLine.towerCrash), reason: 'then it tumbles down');
      expect(game.debugHeight, 0, reason: 'a new tower to build');
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('level 4: one taller or shorter than the red tower', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'tower', sound: sound, level: 4);
      final r = tester.state<TowerGameState>(find.byType(TowerGame)).debugRound;
      expect(r.target, r.ask == TowerAsk.oneMore ? r.other + 1 : r.other - 1);
      expect(sound.said, [r.ask == TowerAsk.oneMore ? VoiceLine.towerMore : VoiceLine.towerLess]);
      expect(labelOf(tester, 'tower.red'), 'Red tower: ${r.other} blocks');
      for (var k = 0; k < r.target; k++) {
        await tester.tap(byId('tower.pile'));
        await tester.pump(const Duration(milliseconds: 200));
      }
      await tester.tap(byId('tower.bell'));
      await h.settle();
      expect(await toyboxRounds(h), [('tower', 4, 'win')]);
      await seconds(tester, 6);
      await h.shutdown();
      handle.dispose();
    });
  });

  group('Drum Count', () {
    testWidgets('FR-TOY-03: the bear drums and the voice counts along; the right number is a win', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'drums', sound: sound, level: 1);
      final r = tester.state<DrumsGameState>(find.byType(DrumsGame)).debugRound;
      await seconds(tester, 8);
      expect(sound.said, [VoiceLine.drumAlong, for (var k = 1; k <= r.beats; k++) numberClip(k), VoiceLine.drumAsk]);
      expect(sound.played.where((p) => p.$1 == Sfx.kick).length, r.beats);
      expectNoFallbackText(byId('screen.game'));
      final wrong = r.choices.firstWhere((c) => c != r.beats);
      await tester.tap(byId('drums.choice.$wrong'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.played.last.$1, Sfx.nope);
      await tester.tap(byId('drums.choice.${r.beats}'));
      await h.settle();
      expect(sound.said.last, drumYesClip(r.beats));
      expect(await toyboxRounds(h), [('drums', 1, 'helped')]);
      await seconds(tester, 4);
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('her turn: each beat counted; too many and the bear says what she played; the right number is a round', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'drums', sound: sound, level: 3);
      final game = tester.state<DrumsGameState>(find.byType(DrumsGame));
      final n = game.debugRound.beats;
      await seconds(tester, 1);
      expect(sound.said.last, drumPlayClip(n));
      for (var k = 1; k <= n + 1; k++) {
        await tester.tap(byId('drums.drum'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(sound.said.last, numberClip(k));
      }
      await seconds(tester, 2);
      expect(sound.said, contains(drumWasClip(n + 1)));
      expect(game.debugPlayed, 0, reason: 'she plays again');
      await seconds(tester, 4);
      for (var k = 1; k <= n; k++) {
        await tester.tap(byId('drums.drum'));
        await tester.pump(const Duration(milliseconds: 300));
      }
      await seconds(tester, 2);
      expect(sound.said.last, drumYesClip(n));
      expect(await toyboxRounds(h), [('drums', 3, 'helped')]);
      await seconds(tester, 4);
      await h.shutdown();
      handle.dispose();
    });
  });

  group('Peekaboo Pals', () {
    testWidgets('FR-TOY-03: friends come in counted, some hide; how many are hiding; "Peekaboo!" and they pop out', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'peekaboo', sound: sound, level: 2);
      final game = tester.state<PeekabooGameState>(find.byType(PeekabooGame));
      final r = game.debugRound;
      for (var i = 0; i < 200 && !game.debugAsking; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(sound.said, [for (var k = 1; k <= r.total; k++) numberClip(k), peekPlayClip(r.total), VoiceLine.peekHide, VoiceLine.peekAsk]);
      expect(labelOf(tester, 'peekaboo.ask'), 'How many are hiding? ${r.showing} showing');
      expectNoFallbackText(byId('screen.game'));
      await tester.tap(byId('peekaboo.choice.${r.hiding}'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said.last, VoiceLine.peekBoo);
      await seconds(tester, 3);
      expect(sound.said.last, peekYesClip(r.hiding));
      expect(await toyboxRounds(h), [('peekaboo', 2, 'win')]);
      await seconds(tester, 4);
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('level 4: the total is on a sign; two wrong picks light up the answer', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'peekaboo', sound: sound, level: 4);
      final r = tester.state<PeekabooGameState>(find.byType(PeekabooGame)).debugRound;
      await seconds(tester, 1);
      expect(sound.said, [peekSignClip(r.total)]);
      expect(labelOf(tester, 'peekaboo.sign'), '${r.total} friends');
      for (final c in r.choices.where((c) => c != r.hiding).take(2)) {
        await tester.tap(byId('peekaboo.choice.$c'));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(byId('peekaboo.choice.${r.hiding}'));
      await h.settle();
      expect(await toyboxRounds(h), [('peekaboo', 4, r.choices.length > 2 ? 'miss' : 'helped')]);
      await seconds(tester, 6);
      await h.shutdown();
      handle.dispose();
    });
  });
}
