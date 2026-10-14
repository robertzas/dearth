import 'dart:math' as math;

import 'package:dearth_app/core/sound.dart';
import 'package:dearth_app/features/toybox/games/bubbles.dart';
import 'package:dearth_app/features/toybox/games/farm.dart';
import 'package:dearth_app/features/toybox/games/music.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_harness.dart';
import 'support/toybox_harness.dart';

/// The launch-set games (SPEC FR-TOY-02), played through the Toybox on the
/// demo household.
void main() {
  for (final size in const [Size(390, 844), Size(844, 390), Size(1080, 1920), Size(1920, 1080)]) {
    testWidgets('every launch-set toy lays out on a ${size.width.toInt()}×${size.height.toInt()} screen at its busiest level', (tester) async {
      await expectGamesLayOut(tester, const [('bubbles', 1), ('bubbles', 4), ('music', 1), ('music', 3), ('farm', 1), ('farm', 3)], size: size);
    });
  }

  group('Xylophone & Drums', () {
    testWidgets('xylophone bars ring up the pentatonic scale on touch; drums sound their own', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'music', sound: sound);
      for (var i = 0; i < 8; i++) {
        await tester.tap(byId('music.bar.$i'));
      }
      await tester.tap(byId('music.drum.kick'));
      await tester.tap(byId('music.drum.hat'));
      await h.settle(5);
      final bars = [for (var i = 0; i < sound.played.length; i++) if (sound.played[i].$1 == Sfx.xylophone) sound.rates[i]];
      expect(bars, [for (final m in kXylophoneMidi) closeTo(math.pow(2, (m - 60) / 12), 1e-9)]);
      expect(sound.played.map((p) => p.$1), containsAll([Sfx.kick, Sfx.hat]));
      expectNoFallbackText(byId('screen.game'));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('echo me: the parrot says what to do, plays a tune, says "your turn"; played back, it is a win at level 2', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'music', sound: sound);
      await tester.tap(byId('music.echo'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.said, [VoiceLine.musicEcho]);
      final tune = tester.state<MusicGameState>(find.byType(MusicGame)).debugTune;
      expect(tune.length, 3);
      // A tap while the parrot plays dips its bar but makes no sound.
      final before = sound.played.length;
      await tester.tap(byId('music.bar.${tune.first}'));
      expect(sound.played.length, before, reason: 'the tune stays clear');
      await h.settle(120);
      expect(sound.said.last, VoiceLine.musicTurn);
      for (final bar in tune) {
        await tester.tap(byId('music.bar.$bar'));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await h.settle();
      expect(sound.said.last, VoiceLine.musicYes);
      expect(await toyboxRounds(h), [('music', 2, 'win')]);
      await h.shutdown();
      handle.dispose();
    });
  });

  group('Animal Farm', () {
    testWidgets('every animal says hello in its own voice, then its name; meeting all six is a round', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'farm', sound: sound);
      // The six on the meadow, picked before any tap (the round restarts after).
      final present = [for (final a in kFarmAnimals) if (byId('farm.animal.${a.id}').evaluate().isNotEmpty) a];
      expect(present.length, 6);
      for (final a in present) {
        final before = sound.played.length;
        await tester.tap(byId('farm.animal.${a.id}'));
        await tester.pump(const Duration(milliseconds: 50));
        expect(byId('farm.says.${a.id}'), findsOneWidget, reason: a.id);
        expect(sound.played[before].$1, Sfx.values.byName(a.id), reason: 'its own voice');
        await tester.pump(const Duration(milliseconds: 1400));
        expect(sound.said.last, farmNameClip(a), reason: 'then its name');
      }
      expect(sound.played.last.$1, Sfx.cheer, reason: 'everyone met');
      await h.settle();
      expect(await toyboxRounds(h), [('farm', 1, 'win')]);
      await tester.pump(const Duration(seconds: 3));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('find it: "Who says this?" and the sound; two wrong tries light up the right one; "Yes! The cow says moo!"; helped', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'farm', sound: sound, level: 2);
      await h.settle(80);
      final target = tester.state<FarmGameState>(find.byType(FarmGame)).debugFind!;
      expect(sound.said.first, VoiceLine.farmWho);
      expect(sound.played.last.$1, Sfx.values.byName(target), reason: 'then the sound to find');
      final others = [for (final a in kFarmAnimals) if (a.id != target && byId('farm.animal.${a.id}').evaluate().isNotEmpty) a.id];
      expect(others.length, 2);
      for (final o in others) {
        await tester.tap(byId('farm.animal.$o'));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(byId('farm.animal.$target'));
      await h.settle(40);
      expect(sound.said.last, farmYesClip(kFarmAnimals.firstWhere((a) => a.id == target)));
      expect(await toyboxRounds(h), [('farm', 2, 'helped')]);
      await tester.pump(const Duration(seconds: 5));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a long pause asks again, twice at most, and lights the answer', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'farm', sound: sound, level: 2);
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(sound.said.where((c) => c == VoiceLine.farmWho).length, 3, reason: 'the question, then two nudges, then quiet');
      await h.shutdown();
      handle.dispose();
    });
  });

  group('Bubble Pop', () {
    // On screen and clear of the home button and the call pill above.
    bool reachable((Offset, String) b) => b.$1.dy > 220 && b.$1.dy < 1020 && b.$1.dx > 60 && b.$1.dx < 1860;

    testWidgets('a finger going down pops a bubble at once and counts it; a full round is a win', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'bubbles', sound: sound);
      await tester.pump(const Duration(milliseconds: 800));
      expect(sound.said, [VoiceLine.bubblesStart]);
      final game = tester.state<BubbleGameState>(find.byType(BubbleGame));
      final origin = tester.getTopLeft(byId('game.bubbles'));
      for (var popped = 0; popped < 12; popped++) {
        // The bubbles keep rising: read where one is now, put a finger down on it.
        var tries = 0;
        while (!game.debugBubbles.any(reachable) && tries++ < 200) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        final (at, _) = game.debugBubbles.firstWhere(reachable);
        final gesture = await tester.startGesture(origin + at);
        await tester.pump(const Duration(milliseconds: 16));
        expect(sound.said.last, numberClip(popped + 1), reason: 'popped on the way down, counted');
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 50));
      }
      await h.settle();
      expect(await toyboxRounds(h), [('bubbles', 1, 'win')]);
      expectNoFallbackText(byId('screen.game'));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a color call: "Pop the blue bubbles!"; another color bounces away without counting', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'bubbles', sound: sound, level: 3);
      await tester.pump(const Duration(milliseconds: 800));
      final game = tester.state<BubbleGameState>(find.byType(BubbleGame));
      final call = game.debugCall!;
      expect(sound.said, [bubblesCallClip(call)]);
      expect(labelOf(tester, 'bubbles.call'), 'Pop the $call ones');
      final origin = tester.getTopLeft(byId('game.bubbles'));
      var tries = 0;
      while (!game.debugBubbles.any((b) => b.$2 != call && reachable(b)) && tries++ < 200) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final other = game.debugBubbles.firstWhere((b) => b.$2 != call && reachable(b));
      await tester.tapAt(origin + other.$1);
      await tester.pump(const Duration(milliseconds: 50));
      expect(sound.played.last.$1, Sfx.boing);
      expect(sound.said.where((c) => c.startsWith('num_')), isEmpty, reason: 'not counted');
      await h.shutdown();
      handle.dispose();
    });
  });
}
