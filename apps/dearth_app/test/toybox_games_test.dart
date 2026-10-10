import 'dart:math' as math;

import 'package:dearth_app/app/router.dart';
import 'package:dearth_app/core/data/household.dart';
import 'package:dearth_app/core/sound.dart';
import 'package:dearth_app/features/toybox/games/farm.dart';
import 'package:dearth_app/features/toybox/games/music.dart';
import 'package:dearth_app/features/toybox/toybox_data.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/app_harness.dart';

/// The launch-set games (SPEC FR-TOY-02), played through the Toybox on the
/// demo household.
void main() {
  Future<List<GameEvent>> rounds(AppHarness h) async => (await h.tester.runAsync(() => h.db.select(h.db.gameEvents).get()))!;

  Future<AppHarness> open(WidgetTester tester, String game, {RecordingSound? sound, int? level}) async {
    final h = await AppHarness.demo(tester, sound: sound ?? RecordingSound());
    if (level != null) await h.write((w) => [settingOp(w, SettingKeys.toybox, ToyboxSettings(pins: {'p-ava.$game': level}).toJson())]);
    h.container.read(routerProvider).go('/toybox');
    await h.settle();
    // The launcher's grid is lazy and the expansion games are many: the
    // tile can be below the fold, where a tap misses. Drag until it is
    // built and visible, then scroll it fully into view.
    final tile = byId('toybox.game.$game');
    await tester.dragUntilVisible(tile, find.descendant(of: find.byType(GridView), matching: find.byType(Scrollable)).first, const Offset(0, -180), maxIteration: 60);
    await tester.ensureVisible(tile);
    await h.settle();
    await tester.tap(tile);
    await h.settle();
    return h;
  }

  testWidgets('xylophone bars ring up the pentatonic scale on touch; drums sound their own', (tester) async {
    final handle = tester.ensureSemantics();
    final sound = RecordingSound();
    final h = await open(tester, 'music', sound: sound);
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

  testWidgets('echo me: the toy plays a tune, she plays it back, and it counts as a win at level 2', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await open(tester, 'music');
    await tester.tap(byId('music.echo'));
    await tester.pump(const Duration(seconds: 3));
    final tune = tester.state<MusicGameState>(find.byType(MusicGame)).debugTune;
    expect(tune.length, 3);
    for (final bar in tune) {
      await tester.tap(byId('music.bar.$bar'));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await h.settle();
    expect((await rounds(h)).map((e) => (e.game, e.level, e.result)), [('music', 2, 'win')]);
    await h.shutdown();
    handle.dispose();
  });

  testWidgets('farm: every animal says hello in its own voice; meeting all six is a round', (tester) async {
    final handle = tester.ensureSemantics();
    final sound = RecordingSound();
    final h = await open(tester, 'farm', sound: sound);
    // The six on the meadow, picked before any tap (the round restarts after).
    final present = [for (final a in kFarmAnimals) if (byId('farm.animal.${a.id}').evaluate().isNotEmpty) a];
    expect(present.length, 6);
    for (final a in present) {
      final before = sound.played.length;
      await tester.tap(byId('farm.animal.${a.id}'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(byId('farm.says.${a.id}'), findsOneWidget, reason: a.id);
      expect(sound.played[before].$1, Sfx.values.byName(a.id), reason: 'its own voice');
    }
    expect(sound.played.last.$1, Sfx.cheer, reason: 'everyone met');
    await h.settle();
    expect((await rounds(h)).map((e) => (e.game, e.level, e.result)), [('farm', 1, 'win')]);
    await tester.pump(const Duration(seconds: 3));
    await h.shutdown();
    handle.dispose();
  });

  testWidgets('farm, find it: “who says…?” — two wrong tries light up the right one, and the round counts as helped', (tester) async {
    final handle = tester.ensureSemantics();
    final sound = RecordingSound();
    final h = await open(tester, 'farm', sound: sound, level: 2);
    await tester.pump(const Duration(seconds: 1));
    final target = tester.state<FarmGameState>(find.byType(FarmGame)).debugFind!;
    expect(sound.played.last.$1, Sfx.values.byName(target), reason: 'the farm asks with the sound');
    final others = [for (final a in kFarmAnimals) if (a.id != target && byId('farm.animal.${a.id}').evaluate().isNotEmpty) a.id];
    expect(others.length, 2);
    for (final o in others) {
      await tester.tap(byId('farm.animal.$o'));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(byId('farm.animal.$target'));
    await h.settle();
    expect((await rounds(h)).map((e) => (e.game, e.level, e.result)), [('farm', 2, 'helped')]);
    await tester.pump(const Duration(seconds: 3));
    await h.shutdown();
    handle.dispose();
  });
}
