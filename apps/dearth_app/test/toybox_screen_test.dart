import 'package:dearth_app/app/router.dart';
import 'package:dearth_app/core/data/household.dart';
import 'package:dearth_app/core/sound.dart';
import 'package:dearth_app/features/toybox/games/bubbles.dart';
import 'package:dearth_app/features/toybox/toybox_data.dart';
import 'package:dearth_app/features/toybox/toybox_screen.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// The Toybox (SPEC §10.8): the launcher, the game host and its rules, on
/// the demo household (Ava is 2½).
void main() {
  Future<List<GameEvent>> rounds(AppHarness h) async => (await h.tester.runAsync(() => h.db.select(h.db.gameEvents).get()))!;

  Future<void> toybox(AppHarness h) async {
    h.container.read(routerProvider).go('/toybox');
    await h.settle();
  }

  testWidgets('FR-TOY-01: Ava’s Toybox has every game, hers first, “new!” until she opens one', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await AppHarness.demo(tester);
    await toybox(h);
    for (final g in kGames.where((g) => g.minMonths <= 30)) {
      expect(byId('toybox.game.${g.id}'), findsOneWidget, reason: g.id);
    }
    final shown = [for (final g in h.container.read(kidGamesProvider('p-ava'))) g.id];
    expect(shown, hasLength(kGames.length), reason: 'every game is on by default');
    expect(shown.indexOf('counting'), greaterThan(shown.indexOf('memory')), reason: 'counting is for 3+, so it comes after hers');
    expect(byId('toybox.new.bubbles'), findsOneWidget);

    await tester.tap(byId('toybox.game.bubbles'));
    await h.settle();
    expect(byId('game.bubbles'), findsOneWidget);
    expectNoFallbackText(byId('screen.game'));
    await tester.tap(byId('game.home'));
    await h.settle();
    expect(byId('screen.toybox'), findsOneWidget);
    expect(byId('toybox.new.bubbles'), findsNothing, reason: 'opened now');
    await h.shutdown();
    handle.dispose();
  });

  testWidgets('FR-TOY-02/04: twelve pops finish a Bubble Pop round: recorded as a win and celebrated', (tester) async {
    final handle = tester.ensureSemantics();
    final sound = RecordingSound();
    final h = await AppHarness.demo(tester, sound: sound);
    await toybox(h);
    await tester.tap(byId('toybox.game.bubbles'));
    await h.settle();
    final game = tester.state<BubbleGameState>(find.byType(BubbleGame));
    var popped = 0;
    for (var guard = 0; popped < 12 && guard < 200; guard++) {
      await tester.pump(const Duration(milliseconds: 200));
      final bubbles = game.debugBubbles.where((b) => b.$1.dy > 60 && b.$1.dy < 1000).toList();
      if (bubbles.isEmpty) continue;
      await tester.tapAt(bubbles.first.$1 + const Offset(0, -2));
      popped++;
    }
    await h.settle();
    final events = await rounds(h);
    expect(events.map((e) => (e.game, e.level, e.result)), [('bubbles', 1, 'win')]);
    expect(sound.played.where((p) => p.$1 == Sfx.pop).length, greaterThanOrEqualTo(12));
    expect(sound.played.map((p) => p.$1), contains(Sfx.cheer));
    await tester.tap(byId('game.home'));
    await h.settle();
    await h.shutdown();
    handle.dispose();
  });

  testWidgets('FR-TOY-05: when the day’s Toybox time is used up, a game says goodnight and the Toybox sleeps', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await AppHarness.demo(tester);
    await h.write((w) => [settingOp(w, SettingKeys.toybox, const ToyboxSettings(budgetMinutes: 15).toJson())]);
    await toybox(h);
    expect(byId('toybox.timeleft'), findsOneWidget);
    await tester.tap(byId('toybox.game.farm'));
    await h.settle();
    Future<void> played(String id, int minutes) async {
      final now = h.container.read(householdTimeProvider).nowMs();
      await h.write((w) => [w.op('game_events', id, {'profile_id': 'p-ava', 'game': 'memory', 'duration_ms': minutes * 60000, 'at_ms': now, 'result': 'win'}, kind: OpKind.insertOnly)]);
      await tester.pump(const Duration(seconds: 6));
      await h.settle();
    }

    await played('a', 13);
    expect(byId('game.timeleft'), findsOneWidget, reason: 'two minutes left: a warning');
    expect(byId('game.sleeping'), findsNothing);
    await played('b', 2);
    expect(byId('game.sleeping'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    await h.settle();
    expect(byId('screen.toybox'), findsOneWidget);
    expect(byId('toybox.sleeping'), findsOneWidget);
    await h.shutdown();
    handle.dispose();
  });

  test('FR-TOY-01: every game has its own tile hue — kids find games by color', () {
    for (final g in kGames) {
      expect(kGameHues[g.id], isNotNull, reason: '${g.id} has no tile hue and would fall back to the accent');
    }
    expect(
      {for (final g in kGames) kGameHues[g.id]!.toARGB32()}.length,
      kGames.length,
      reason: 'two games share a tile color; the launcher is read by picture and color',
    );
  });
}
