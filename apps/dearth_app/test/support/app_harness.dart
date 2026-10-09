import 'package:dearth_app/app/app.dart';
import 'package:dearth_app/app/grown_up.dart';
import 'package:dearth_app/core/env.dart';
import 'package:dearth_app/core/providers.dart';
import 'package:dearth_app/core/sound.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:timezone/timezone.dart' as tz;

/// The whole app on a native in-memory database at a fixed clock, for
/// widget-level journeys (SPEC §16.1 app logic).
class AppHarness {
  AppHarness._(this.tester, this.container, this.db);
  final WidgetTester tester;
  final ProviderContainer container;
  final DearthDb db;

  /// 8:30 on a Saturday morning in the household's zone. Tests have no
  /// time-zone plugin, so the household falls back to Denver
  /// (`deviceTimeZone`); a plain `DateTime(…)` would be 8:30 on the machine
  /// running the tests, which on CI (UTC) is 2:30 in Denver.
  static tz.TZDateTime get defaultNow => tz.TZDateTime(locationOrUtc('America/Denver'), 2026, 10, 3, 8, 30);

  static Future<AppHarness> boot(WidgetTester tester, {Size size = const Size(1920, 1080), DateTime? now, SoundPlayer sound = const SilentSound(), List<Override> overrides = const []}) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    ensureTimeZones();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = DearthDb(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [
      envProvider.overrideWithValue(AppEnv(e2e: true, fakeNow: now ?? defaultNow)),
      dbProvider.overrideWithValue(db),
      nodeIdProvider.overrideWithValue('dtest'),
      actorProvider.overrideWith((ref) => ref.watch(grownUpActorProvider)),
      // Tests never open the host's audio device.
      soundProvider.overrideWithValue(sound),
      ...overrides,
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const DearthApp()));
    return AppHarness._(tester, container, db);
  }

  /// Boots, then starts the seeded demo household from onboarding.
  static Future<AppHarness> demo(WidgetTester tester, {Size size = const Size(1920, 1080), SoundPlayer sound = const SilentSound(), List<Override> overrides = const []}) async {
    final h = await boot(tester, size: size, sound: sound, overrides: overrides);
    await h.settle();
    // On a short screen the demo button is below the fold of the onboarding
    // card, where a tap misses.
    await tester.ensureVisible(byId('onboarding.demo'));
    await h.settle(2);
    await tester.tap(byId('onboarding.demo'));
    await h.settle(30);
    return h;
  }

  /// Pumps frames while letting the database (real async) make progress.
  Future<void> settle([int frames = 20]) async {
    for (var i = 0; i < frames; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Writes [ops] through the device writer (Mutator → bulk apply).
  Future<void> write(List<Op> Function(DataWriter w) ops) async {
    final w = container.read(writerProvider);
    await tester.runAsync(() => w.commit(ops(w)));
    await settle(5);
  }

  /// Unmounts the app and disposes providers (minute ticker, streams) so no
  /// timers outlive the test.
  Future<void> shutdown() async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    // Let drift's stream-cache timers fire (the in-memory db needs no close).
    await tester.pump(const Duration(seconds: 1));
  }
}

/// A `tid()` node (AGENTS.md rule 10).
Finder byId(String id) => find.byWidgetPredicate((w) => w is Semantics && w.properties.identifier == id);

/// The label a `tid()` node reads out.
String labelOf(WidgetTester tester, String id) => tester.getSemantics(byId(id)).label;

/// Fails if any text on screen inherits MaterialApp's fallback style (the
/// yellow double underline drawn for text outside every Material).
void expectNoFallbackText([Finder? within]) {
  final texts = within == null ? find.byType(RichText) : find.descendant(of: within, matching: find.byType(RichText));
  final bad = <String>[];
  for (final e in texts.evaluate()) {
    final rich = e.widget as RichText;
    final label = rich.text.style?.debugLabel ?? '';
    if (label.contains('fallback style') || rich.text.style?.decorationStyle == TextDecorationStyle.double) bad.add(rich.text.toPlainText());
  }
  expect(bad, isEmpty, reason: 'text outside a Material: $bad');
}

/// Records what would have played (chime assertions).
class RecordingSound implements SoundPlayer {
  final played = <(Sfx, double)>[];

  /// The rate of each sound in [played] (pitch, for instruments).
  final rates = <double>[];

  @override
  Future<void> play(Sfx sfx, {double volume = 1, double rate = 1}) async {
    played.add((sfx, volume));
    rates.add(rate);
  }

  /// Voice clips spoken, in order.
  final said = <String>[];

  @override
  Future<void> say(String clip, {double volume = 1}) async => said.add(clip);
}

