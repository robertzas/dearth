import 'package:dearth_app/core/sound.dart';
import 'package:dearth_app/features/toybox/games/creature.dart';
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
      await expectGamesLayOut(tester, const [('creature', 1), ('creature', 3)], size: size);
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
}
