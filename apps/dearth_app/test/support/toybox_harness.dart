import 'dart:async';

import 'package:dearth_app/app/router.dart';
import 'package:dearth_app/core/data/household.dart';
import 'package:dearth_app/features/toybox/game_host.dart';
import 'package:dearth_app/features/toybox/toybox_data.dart';
import 'package:dearth_app/features/toybox/toybox_screen.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'app_harness.dart';

/// Opens [game] from Ava's Toybox on the demo household (she is 2½), at a
/// pinned [level] when given (every game is on by default).
/// Fails unless the game opened.
Future<AppHarness> openToyboxGame(WidgetTester tester, String game, {RecordingSound? sound, int? level, Size size = const Size(1920, 1080)}) async {
  final h = await AppHarness.demo(tester, sound: sound ?? RecordingSound(), size: size);
  final settings = ToyboxSettings(pins: {'p-ava.$game': ?level});
  await h.write((w) => [settingOp(w, SettingKeys.toybox, settings.toJson())]);
  h.container.read(routerProvider).go('/toybox');
  await h.settle();
  // On small screens the tile can be below the fold, where a tap misses
  // and the test would quietly go on looking at the launcher. The grid is
  // lazy, so drag it until the tile is built and visible, then scroll it
  // fully into view.
  final tile = byId('toybox.game.$game');
  // The launcher's grid, not the page around it (every game is on, so the
  // grid is long, and other scrollables share the screen).
  await tester.dragUntilVisible(tile, find.descendant(of: find.byType(GridView), matching: find.byType(Scrollable)).first, const Offset(0, -180), maxIteration: 60);
  await tester.ensureVisible(tile);
  await h.settle();
  await tester.tap(tile);
  await h.settle();
  expect(byId('game.$game'), findsOneWidget, reason: '$game should be open');
  return h;
}

/// Opens each (game, level) of [games] in turn at [size] and fails on any
/// layout error (an overflow throws). The app boots once for all of them:
/// booting and seeding the demo household is most of what opening a game
/// costs, so a game is pushed over the Toybox and popped again instead.
Future<void> expectGamesLayOut(WidgetTester tester, List<(String, int)> games, {required Size size}) async {
  final h = await AppHarness.demo(tester, size: size);
  h.container.read(routerProvider).go('/toybox');
  await h.settle();
  final ava = (await tester.runAsync(() => (h.db.select(h.db.profiles)..where((p) => p.id.equals('p-ava'))).getSingle()))!;
  for (final (game, level) in games) {
    final info = gameById(game)!;
    await h.write((w) => [settingOp(w, SettingKeys.toybox, ToyboxSettings(pins: {'p-ava.$game': level}).toJson())]);
    final navigator = Navigator.of(tester.element(find.byType(ToyboxScreen)), rootNavigator: true);
    unawaited(navigator.push<void>(PageRouteBuilder<void>(pageBuilder: (_, _, _) => GameScreen(game: info, kid: ava))));
    await h.settle(5);
    expect(byId('game.$game'), findsOneWidget, reason: '$game should be open');
    expect(tester.state<GameScreenState>(find.byType(GameScreen)).debugLevel, level, reason: '$game opened at its pinned level');
    await tester.pump(const Duration(seconds: 1));
    // An overflow would have been thrown as a layout error.
    expect(tester.takeException(), isNull, reason: '$game $level at ${size.width.toInt()}×${size.height.toInt()}');
    navigator.pop();
    await h.settle(3);
  }
  await h.shutdown();
}

/// Every recorded round, oldest first, as (game, level, result).
Future<List<(String, int, String)>> toyboxRounds(AppHarness h) async {
  final events = (await h.tester.runAsync(() => (h.db.select(h.db.gameEvents)..orderBy([(e) => OrderingTerm.asc(e.atMs)])).get()))!;
  return [for (final e in events) (e.game, e.level, e.result)];
}
