import 'dart:math' as math;

import 'package:dearth_app/core/sound.dart';
import 'package:dearth_app/features/toybox/games/counting.dart';
import 'package:dearth_app/features/toybox/games/monster.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_harness.dart';
import 'support/toybox_harness.dart';

/// The Toybox's thinking games (SPEC FR-TOY-02): Counting Garden and Feed
/// the Monster, played through the Toybox on the demo household.
void main() {
  group('Counting Garden', () {
    testWidgets('each bud blooms with its number on a rising note; a wrong “how many?” first makes the round “helped”', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'counting', sound: sound);
      final game = tester.state<CountingGameState>(find.byType(CountingGame));
      final n = game.debugCount;
      expect(n, inInclusiveRange(1, 3), reason: 'level 1 counts to three');
      expect(byId('counting.ask'), findsNothing, reason: 'count first');
      expectNoFallbackText(byId('screen.game'));
      for (var i = 0; i < n; i++) {
        await tester.tap(byId('counting.bud.$i'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(labelOf(tester, 'counting.bud.$i'), 'Flower ${i + 1}');
      }
      final rates = [for (var i = 0; i < sound.played.length; i++) if (sound.played[i].$1 == Sfx.blip) sound.rates[i]];
      expect(rates.length, n);
      for (var i = 1; i < rates.length; i++) {
        expect(rates[i], greaterThan(rates[i - 1]), reason: 'each count sounds higher');
      }
      await tester.pump(const Duration(milliseconds: 800));
      await h.settle(2);
      expect(byId('counting.ask'), findsOneWidget);
      final wrong = n == 1 ? 2 : n - 1;
      await tester.tap(byId('counting.choice.$wrong'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(sound.played.last.$1, Sfx.nope, reason: 'a gentle “uh-uh”');
      await tester.tap(byId('counting.choice.$n'));
      await h.settle();
      expect(await toyboxRounds(h), [('counting', 1, 'helped')]);
      await tester.pump(const Duration(seconds: 3));
      await h.settle(2);
      expect(byId('counting.ask'), findsNothing, reason: 'a new bed of buds');
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a flash round shows the flowers for a moment, then asks; right the first time is a win', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await openToyboxGame(tester, 'counting', level: 4);
      final game = tester.state<CountingGameState>(find.byType(CountingGame));
      expect(game.debugShowing, isTrue);
      expect(labelOf(tester, 'counting.bud.0'), 'Flower');
      await tester.pump(const Duration(milliseconds: 1800));
      await h.settle(2);
      expect(game.debugShowing, isFalse);
      expect(labelOf(tester, 'counting.bud.0'), 'Bud', reason: 'hidden under leaves');
      await tester.tap(byId('counting.choice.${game.debugCount}'));
      await h.settle();
      expect(await toyboxRounds(h), [('counting', 4, 'win')]);
      await tester.pump(const Duration(seconds: 3));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('ten flowers fit a portrait display in two rows', (tester) async {
      final handle = tester.ensureSemantics();
      final h = await openToyboxGame(tester, 'counting', level: 3, size: const Size(1080, 1920));
      final n = tester.state<CountingGameState>(find.byType(CountingGame)).debugCount;
      for (var i = 0; i < n; i++) {
        final r = tester.getRect(byId('counting.bud.$i'));
        expect(const Rect.fromLTWH(0, 0, 1080, 1920).contains(r.center), isTrue, reason: 'bud $i at $r');
      }
      final rows = {for (var i = 0; i < n; i++) tester.getCenter(byId('counting.bud.$i')).dy.round()};
      expect(rows.length, math.min(2, (n / 5).ceil()));
      await h.shutdown();
      handle.dispose();
    });
  });

  group('Feed the Monster', () {
    testWidgets('the monster munches what its sign shows and shakes its head at the rest; one refusal is still a win', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'monster', sound: sound);
      final round = tester.state<MonsterGameState>(find.byType(MonsterGame)).debugRound;
      expect(labelOf(tester, 'monster.sign'), 'Only ${round.rule.color} food', reason: 'level 1: one color');
      expectNoFallbackText(byId('screen.game'));
      final wants = [for (var i = 0; i < round.tray.length; i++) if (round.rule.accepts(round.tray[i])) i];
      final refuses = [for (var i = 0; i < round.tray.length; i++) if (!round.rule.accepts(round.tray[i])) i];
      final plate = tester.getCenter(byId('monster.food.${refuses.first}'));

      await tester.tap(byId('monster.food.${refuses.first}'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(sound.played.last.$1, Sfx.nope);
      await tester.pump(const Duration(milliseconds: 600));
      expect((tester.getCenter(byId('monster.food.${refuses.first}')) - plate).distance, lessThan(2), reason: 'back on its plate');

      for (final i in wants) {
        final before = sound.played.length;
        await tester.tap(byId('monster.food.$i'));
        await tester.pump(const Duration(milliseconds: 500));
        expect(sound.played.skip(before).map((p) => p.$1), contains(Sfx.munch), reason: round.tray[i].name);
        expect(labelOf(tester, 'monster.food.$i'), 'Eaten');
        await tester.pump(const Duration(milliseconds: 300));
      }
      await h.settle();
      expect(await toyboxRounds(h), [('monster', 1, 'win')]);
      await tester.pump(const Duration(seconds: 3));
      await h.shutdown();
      handle.dispose();
    });

    testWidgets('a food dragged to the mouth is eaten; at the top level the sign asks for two things at once', (tester) async {
      final handle = tester.ensureSemantics();
      final sound = RecordingSound();
      final h = await openToyboxGame(tester, 'monster', sound: sound, level: 4);
      final round = tester.state<MonsterGameState>(find.byType(MonsterGame)).debugRound;
      expect(labelOf(tester, 'monster.sign'), monsterSignLabel(round.rule));
      expect(monsterSignLabel(round.rule), anyOf(contains(' and '), matches(RegExp(r'^Only \w+ (fruit|vegetables|treats)$'))));
      final i = [for (var i = 0; i < round.tray.length; i++) if (round.rule.accepts(round.tray[i])) i].first;
      final from = tester.getCenter(byId('monster.food.$i')), to = tester.getCenter(byId('monster.mouth'));
      await tester.dragFrom(from, to - from);
      await tester.pump(const Duration(milliseconds: 300));
      expect(sound.played.map((p) => p.$1), contains(Sfx.munch));
      expect(labelOf(tester, 'monster.food.$i'), 'Eaten');
      await h.shutdown();
      handle.dispose();
    });

    test('the sign reads the rule the way a grown-up would say it', () {
      expect(monsterSignLabel(const MonsterRule(color: 'red')), 'Only red food');
      expect(monsterSignLabel(const MonsterRule(round: true)), 'Only round food');
      expect(monsterSignLabel(const MonsterRule(kind: 'vegetable')), 'Only vegetables');
      expect(monsterSignLabel(const MonsterRule(color: 'red', round: true)), 'Only red and round food');
      expect(monsterSignLabel(const MonsterRule(color: 'green', kind: 'fruit')), 'Only green fruit');
    });
  });
}
