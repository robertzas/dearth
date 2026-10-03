import 'package:dearth_core/dearth_core.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'app/grown_up.dart';
import 'core/data/household.dart';
import 'core/db/open_db.dart';
import 'core/env.dart';
import 'core/errors.dart';
import 'core/platform/platform.dart';
import 'core/providers.dart';
import 'core/session.dart';
import 'features/calendar/calendar_state.dart';

/// Kept alive for the app's lifetime in E2E mode (SPEC §16.3).
SemanticsHandle? _semantics;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHandling();
  final env = AppEnv.fromPlatform();
  if (env.e2e) _semantics = SemanticsBinding.instance.ensureSemantics();
  ensureTimeZones();

  // SPEC §12.8: open the local replica and render from it before any network.
  final db = openDeviceDb();
  final sessions = SessionStore(db);
  if (env.reset) {
    await sessions.wipe();
    await sessions.save(const Session());
    replaceUrl(Uri.base.replace(queryParameters: {...Uri.base.queryParameters}..remove('reset')).toString());
  }
  var nodeId = await db.kvGet('node.id');
  if (nodeId == null) {
    nodeId = 'd${randomCode(10).toLowerCase()}';
    await db.kvSet('node.id', nodeId);
  }
  var session = await sessions.load();
  final base = <Override>[
    envProvider.overrideWithValue(env),
    dbProvider.overrideWithValue(db),
    nodeIdProvider.overrideWithValue(nodeId),
    actorProvider.overrideWith((ref) => ref.watch(grownUpActorProvider)),
    commandHandlerProvider.overrideWith(appCommandHandler),
    telemetrySourceProvider.overrideWith(appTelemetry),
  ];
  if (env.forceDemo && !session.isReady) {
    final seeding = ProviderContainer(overrides: [...base, initialSessionProvider.overrideWithValue(session)]);
    await seeding.read(sessionProvider.notifier).startDemo();
    seeding.dispose();
    session = await sessions.load();
  }
  // Read after any seeding so the first frame uses the household's zone.
  final household = await (db.select(db.households)..where((h) => h.id.equals(Ids.household))).getSingleOrNull();
  final savedView = await db.kvGet('calendar.view');

  final container = ProviderContainer(
    overrides: [
      ...base,
      initialSessionProvider.overrideWithValue(session),
      initialHouseholdProvider.overrideWithValue(household),
      savedCalendarViewProvider.overrideWithValue(savedView),
    ],
  );
  runApp(UncontrolledProviderScope(container: container, child: const DearthApp()));
  assert(_semantics != null || !env.e2e);
}
