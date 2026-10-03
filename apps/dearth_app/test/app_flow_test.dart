import 'package:dearth_app/app/app.dart';
import 'package:dearth_app/app/grown_up.dart';
import 'package:dearth_app/core/env.dart';
import 'package:dearth_app/core/providers.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// App-level flows on a native in-memory database (SPEC §16.1 app logic).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<(ProviderContainer, DearthDb)> boot(WidgetTester tester) async {
    ensureTimeZones();
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = DearthDb(NativeDatabase.memory());
    final container = ProviderContainer(overrides: [
      envProvider.overrideWithValue(AppEnv(e2e: true, fakeNow: DateTime(2026, 10, 3, 8, 30))),
      dbProvider.overrideWithValue(db),
      nodeIdProvider.overrideWithValue('dtest'),
      actorProvider.overrideWith((ref) => ref.watch(grownUpActorProvider)),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const DearthApp()));
    return (container, db);
  }

  /// Unmounts the app and disposes providers (minute ticker, streams) so no
  /// timers outlive the test.
  Future<void> shutdown(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    // Let drift's stream-cache timers fire (the in-memory db needs no close).
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> settle(WidgetTester tester, [int frames = 20]) async {
    for (var i = 0; i < frames; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Finder byId(String id) => find.byWidgetPredicate((w) => w is Semantics && w.properties.identifier == id);

  testWidgets('FR-SET-01: first run shows onboarding; the demo leads Home', (tester) async {
    final handle = tester.ensureSemantics();
    final (container, _) = await boot(tester);
    await settle(tester);
    expect(byId('screen.onboarding'), findsOneWidget);
    await tester.tap(byId('onboarding.demo'));
    await settle(tester, 30);
    expect(container.read(sessionProvider).isDemo, isTrue);
    expect(byId('screen.home'), findsOneWidget);
    await shutdown(tester, container);
    handle.dispose();
  });
}
