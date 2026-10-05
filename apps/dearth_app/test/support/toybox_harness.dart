import 'package:dearth_app/app/router.dart';
import 'package:dearth_app/core/data/household.dart';
import 'package:dearth_app/features/toybox/toybox_data.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'app_harness.dart';

/// Opens [game] from Ava's Toybox on the demo household (she is 2½), at a
/// pinned [level] when given. Games for older kids are opened early for her.
/// Fails unless the game opened.
Future<AppHarness> openToyboxGame(WidgetTester tester, String game, {RecordingSound? sound, int? level, Size size = const Size(1920, 1080)}) async {
  final h = await AppHarness.demo(tester, sound: sound ?? RecordingSound(), size: size);
  final info = gameById(game)!;
  final settings = ToyboxSettings(pins: {'p-ava.$game': ?level}, early: {if (info.minMonths > 30) 'p-ava.$game'});
  await h.write((w) => [settingOp(w, SettingKeys.toybox, settings.toJson())]);
  h.container.read(routerProvider).go('/toybox');
  await h.settle();
  // On small screens the tile can be below the fold, where a tap misses
  // and the test would quietly go on looking at the launcher. The grid is
  // lazy, so drag it until the tile is built and visible, then scroll it
  // fully into view.
  final tile = byId('toybox.game.$game');
  await tester.dragUntilVisible(tile, find.byType(Scrollable), const Offset(0, -180), maxIteration: 40);
  await tester.ensureVisible(tile);
  await h.settle();
  await tester.tap(tile);
  await h.settle();
  expect(byId('game.$game'), findsOneWidget, reason: '$game should be open');
  return h;
}

/// Every recorded round, oldest first, as (game, level, result).
Future<List<(String, int, String)>> toyboxRounds(AppHarness h) async {
  final events = (await h.tester.runAsync(() => (h.db.select(h.db.gameEvents)..orderBy([(e) => OrderingTerm.asc(e.atMs)])).get()))!;
  return [for (final e in events) (e.game, e.level, e.result)];
}
