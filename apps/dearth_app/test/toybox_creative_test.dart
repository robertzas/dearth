import 'package:dearth_app/core/sound.dart';
import 'package:dearth_app/features/toybox/games/creature.dart';
import 'package:dearth_app/features/toybox/games/dressup.dart';
import 'package:dearth_app/features/toybox/games/freeze.dart';
import 'package:dearth_app/features/toybox/games/sequencer.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_harness.dart';
import 'support/toybox_harness.dart';

/// The Toybox's make-and-move games (SPEC FR-TOY-03), played through the
/// Toybox on the demo household.
void main() {
  for (final size in const [Size(390, 844), Size(844, 390), Size(1080, 1920), Size(1920, 1080)]) {
    testWidgets('every make-and-move game lays out on a ${size.width.toInt()}×${size.height.toInt()} screen at its busiest level', (tester) async {
      await expectGamesLayOut(tester, const [('creature', 1), ('creature', 3), ('freeze', 1), ('freeze', 3), ('sequencer', 1), ('sequencer', 4), ('dressup', 1), ('dressup', 3)], size: size);
    });
  }

  group('Build-a-Creature', () {
    String describe(Creature c, List<CreaturePart> parts) => '${c.name}, ${kCreaturePaints[c.color]}: ${[for (final p in parts) kCreaturePartWords[p]![c[p]]].join(', ')}';

    testWidgets('FR-TOY-03: a hello, then a part button changes its part and names it, and a paint recolors it', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'creature', sound: sound);
      final state = tester.state<CreatureGameState>(find.byType(CreatureGame));
      expectNoFallbackText(byId('screen.game'));
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said, [VoiceLine.makeCreature]);
      // Level 1: body and face, four paints.
      expect(byId('creature.part.body'), findsOneWidget);
      expect(byId('creature.part.face'), findsOneWidget);
      expect(byId('creature.part.top'), findsNothing);
      expect(byId('creature.color.3'), findsOneWidget);
      expect(byId('creature.color.4'), findsNothing);

      final before = state.debugCreature;
      await tester.tap(byId('creature.part.face'));
      await tester.pump();
      final after = state.debugCreature;
      expect(after[CreaturePart.face], (before[CreaturePart.face] + 1) % kCreatureOptions[CreaturePart.face]!);
      expect(after[CreaturePart.body], before[CreaturePart.body]);
      expect(sound.said.last, creaturePartClip(CreaturePart.face, after[CreaturePart.face]));
      expect(labelOf(tester, 'creature.me'), describe(after, creatureParts(1)));

      final paint = (after.color + 1) % 4;
      await tester.tap(byId('creature.color.$paint'));
      await tester.pump();
      expect(state.debugCreature.color, paint);
      expect(sound.said.last, colorClip(kCreaturePaints[paint]));
      expect(labelOf(tester, 'creature.color.$paint'), '${kCreaturePaints[paint]} paint');
      expect(labelOf(tester, 'creature.me'), describe(state.debugCreature, creatureParts(1)));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('the dance: its silly name and a tune, a few seconds of dancing, then it stands still', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'creature', sound: sound);
      final state = tester.state<CreatureGameState>(find.byType(CreatureGame));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(byId('creature.dance'));
      await tester.pump();
      expect(sound.said.last, creatureClip(state.debugCreature));
      expect(labelOf(tester, 'creature.me'), endsWith(', dancing'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(sound.played.where((p) => p.$1 == Sfx.xylophone).length, greaterThanOrEqualTo(8));
      // Tapping while it dances doesn't start it over.
      final said = sound.said.length;
      await tester.tap(byId('creature.me'));
      await tester.pump();
      expect(sound.said, hasLength(said));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(labelOf(tester, 'creature.me'), isNot(endsWith(', dancing')));
      // Free play: nothing to win, so no cheering.
      expect(byId('celebration'), findsNothing);
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('level 3: six part buttons, eight paints, and a surprise with every part on', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await openToyboxGame(tester, 'creature', level: 3);
      final state = tester.state<CreatureGameState>(find.byType(CreatureGame));
      for (final p in CreaturePart.values) {
        expect(byId('creature.part.${p.name}'), findsOneWidget, reason: '$p');
      }
      expect(byId('creature.color.7'), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        await tester.tap(byId('creature.surprise'));
        await tester.pump();
        final c = state.debugCreature;
        for (final p in [CreaturePart.top, CreaturePart.legs, CreaturePart.arms, CreaturePart.tail]) {
          expect(c[p], greaterThan(0), reason: '$p');
        }
        expect(labelOf(tester, 'creature.me'), describe(c, CreaturePart.values));
      }
      await h.shutdown();
      handle.dispose();
    });
  });

  group('Freeze Dance', () {
    FreezeGameState game(WidgetTester tester) => tester.state<FreezeGameState>(find.byType(FreezeGame));

    testWidgets('FR-TOY-03: music while it dances; "Freeze!" and silence; "Dance!" and on; "Great dancing!" at the end', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'freeze', sound: sound, level: 1);
      final song = game(tester).debugSong;
      expectNoFallbackText(byId('screen.game'));
      expect(labelOf(tester, 'freeze.state'), 'Ready to dance');
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said, [VoiceLine.freezeStart]);
      await tester.pump(afterVoice(VoiceLine.freezeStart) + const Duration(seconds: 2));
      expect(labelOf(tester, 'freeze.state'), 'Dancing');
      expect(sound.played.map((p) => p.$1), containsAll([Sfx.xylophone, Sfx.kick, Sfx.hat]), reason: 'the tune and the drums');
      // To the freeze: the voice says so, and the music stops dead.
      for (var i = 0; i < 120 && !game(tester).debugFrozen; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(sound.said.last, VoiceLine.freezeStop);
      expect(labelOf(tester, 'freeze.state'), 'Frozen');
      final heard = sound.played.length;
      await tester.pump(const Duration(milliseconds: 2500));
      expect(sound.played.length, heard, reason: 'silence while frozen');
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said.last, VoiceLine.freezeGo);
      expect(game(tester).debugDancing, isTrue);
      // The rest of the song.
      final rest = song.skip(1).fold<int>(0, (ms, t) => ms + t.danceMs + t.freezeMs);
      await tester.pump(Duration(milliseconds: rest));
      expect(sound.said.last, VoiceLine.freezeDone);
      expect(labelOf(tester, 'freeze.state'), 'Great dancing!');
      await h.settle();
      expect(await toyboxRounds(h), [('freeze', 1, 'win')]);
      await tester.pump(const Duration(seconds: 6));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('the top level: each dance is an animal\'s, named by the voice', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'freeze', sound: sound, level: 3);
      final first = game(tester).debugSong.first.animal!;
      await tester.pump(const Duration(milliseconds: 700) + afterVoice(VoiceLine.freezeStart) + const Duration(milliseconds: 300));
      expect(sound.said.last, freezeAnimalClip(first));
      expect(labelOf(tester, 'freeze.state'), 'Dancing like a ${first.name}');
      await tester.tap(byId('freeze.buddy'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.played.where((p) => p.$1 == Sfx.sparkle), hasLength(1), reason: 'a tap makes it twirl');
      await h.shutdown();
      handle.dispose();
    });
  });

  group('Music Sequencer', () {
    SequencerGameState game(WidgetTester tester) => tester.state<SequencerGameState>(find.byType(SequencerGame));

    testWidgets('FR-TOY-03: a beat plays from the start; the playhead loops; a square she lights calls at once and on every pass', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'sequencer', sound: sound, level: 1);
      expectNoFallbackText(byId('screen.game'));
      expect(game(tester).debugSize.steps, 4);
      expect(labelOf(tester, 'seq.board'), 'Ready');
      await tester.pump(const Duration(milliseconds: 700));
      expect(sound.said, [VoiceLine.seqStart]);
      await tester.pump(afterVoice(VoiceLine.seqStart));
      expect(labelOf(tester, 'seq.board'), matches(RegExp(r'^Step [1-4] of 4$')));
      // The starter beat: the dog on step 1, the cat on step 3.
      await tester.pump(const Duration(milliseconds: kSeqStepMs * 4));
      expect(sound.played.map((p) => p.$1), containsAll([Sfx.dogBeat, Sfx.catBeat]));
      expect(labelOf(tester, 'seq.cell.cat.1'), 'Cat 2: off');
      final before = sound.played.where((p) => p.$1 == Sfx.catBeat).length;
      await tester.tap(byId('seq.cell.cat.1'));
      await tester.pump();
      expect(labelOf(tester, 'seq.cell.cat.1'), 'Cat 2: on');
      expect(sound.played.where((p) => p.$1 == Sfx.catBeat).length, before + 1, reason: 'it calls at once');
      // A whole pass: the cat now calls twice (steps 2 and 3).
      final mark = sound.played.where((p) => p.$1 == Sfx.catBeat).length;
      await tester.pump(const Duration(milliseconds: kSeqStepMs * 4));
      expect(sound.played.where((p) => p.$1 == Sfx.catBeat).length, mark + 2);
      // Off again, and the dice deals a new beat.
      await tester.tap(byId('seq.cell.cat.1'));
      await tester.pump();
      expect(labelOf(tester, 'seq.cell.cat.1'), 'Cat 2: off');
      await tester.tap(byId('seq.dice'));
      await tester.pump();
      expect(game(tester).debugGrid.every((row) => row.any((on) => on)), isTrue);
      await tester.tap(byId('seq.track.dog'));
      await tester.pump();
      expect(sound.played.last.$1, Sfx.dogBeat);
      await h.shutdown();
      handle.dispose();
    });
  });

  group('Weather Dress-Up', () {
    DressGameState game(WidgetTester tester) => tester.state<DressGameState>(find.byType(DressGame));

    testWidgets('FR-TOY-03: the day is said; a pick that suits goes on the buddy and is named; dressed, "Ready to go outside!"', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'dressup', sound: sound, level: 2);
      // A pretend first round turns into the real day if the forecast comes within 450 ms.
      await tester.pump(const Duration(milliseconds: 1200));
      final r = game(tester).debugRound;
      expectNoFallbackText(byId('screen.game'));
      expect(sound.said, [dressDayClip(r.weather, pretend: r.pretend)]);
      expect(labelOf(tester, 'dress.buddy'), 'Buddy: 0 of 2 dressed');
      // A wrong one first: named, faded, not worn.
      final top = r.picks.first;
      final wrong = top.choices.firstWhere((i) => !top.suits.contains(i));
      await tester.tap(byId('dress.item.${wrong.name}'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(sound.said.last, dressItemClip(wrong));
      expect(labelOf(tester, 'dress.item.${wrong.name}'), '${wrong.name}, tried');
      expect(game(tester).debugWorn, isEmpty);
      for (final (k, p) in r.picks.indexed) {
        final right = p.choices.firstWhere(p.suits.contains);
        await tester.tap(byId('dress.item.${right.name}'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(sound.said.last, dressItemClip(right));
        expect(labelOf(tester, 'dress.buddy'), startsWith('Buddy: ${k + 1} of 2 dressed'));
        await tester.pump(const Duration(seconds: 2));
        if (k == 0) expect(sound.said.last, dressSlotClip(DressSlot.feet), reason: 'then: what shoes?');
      }
      expect(sound.said.last, VoiceLine.dressDone);
      expect(labelOf(tester, 'dress.ask'), 'Ready to go outside');
      await h.settle();
      expect(await toyboxRounds(h), [('dressup', 2, 'win')], reason: 'one slip over two parts is fine');
      await tester.pump(const Duration(seconds: 5));
      await h.shutdown();
      handle.dispose();
    });
  });
}
