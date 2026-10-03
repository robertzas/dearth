import 'dart:async';
import 'dart:convert';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_integrations/dearth_integrations.dart' show demoSeedOps;
import 'package:dearth_ui/dearth_ui.dart';
import 'package:drift/drift.dart' show TableOrViewStatements;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import 'env.dart';
import 'session.dart';
import 'sync/hub_api.dart';
import 'sync/sync_client.dart';

// ───────────────────────── Bootstrap-provided values ─────────────────────────
// Overridden in main() once the database is open (SPEC §12.8: local data
// renders before any network).

final envProvider = Provider<AppEnv>((ref) => const AppEnv());
final dbProvider = Provider<DearthDb>((ref) => throw StateError('dbProvider is overridden at startup'));
final nodeIdProvider = Provider<String>((ref) => throw StateError('nodeIdProvider is overridden at startup'));
final initialSessionProvider = Provider<Session>((ref) => const Session());

final appClockProvider = Provider<AppClock>((ref) => AppClock(startAt: ref.watch(envProvider).fakeNow));
final storeProvider = Provider<SyncStore>((ref) => SyncStore(ref.watch(dbProvider)));
final hlcProvider = Provider<HlcClock>((ref) => HlcClock(ref.watch(nodeIdProvider)));
final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore(ref.watch(dbProvider)));

/// App-wide toasts (sync rejections, undo offers…).
final toastProvider = Provider<DToastController>((ref) {
  final c = DToastController();
  ref.onDispose(c.dispose);
  return c;
});

// ─────────────────────────────── Session ────────────────────────────────────

class SessionController extends Notifier<Session> {
  @override
  Session build() => ref.watch(initialSessionProvider);

  Future<void> set(Session s) async {
    await ref.read(sessionStoreProvider).save(s);
    state = s;
  }

  /// Seeds a local demo household and switches to demo mode.
  Future<void> startDemo({String? role}) async {
    final db = ref.read(dbProvider);
    await ref.read(sessionStoreProvider).wipe();
    final tz = await deviceTimeZone();
    final m = Mutator(store: ref.read(storeProvider), clock: ref.read(hlcProvider), sink: (_) async {});
    final time = HouseholdTime.named(tz, clock: ref.read(appClockProvider).now);
    final r = role ?? ref.read(envProvider).role ?? DeviceRole.kitchen;
    await m.commit([
      ...householdDefaultOps(m, timezone: tz),
      ...await demoSeedOps(m, time),
      m.makeOp('devices', Session.demoDeviceId, {'name': 'This display', 'role': r, 'platform': AppEnv.platformName}),
    ]);
    await db.kvSet('demo.seeded', time.today().iso);
    await set(Session(mode: SessionMode.demo, role: r, admin: true, deviceName: 'This display'));
  }

  /// Completes pairing with a Hub (SPEC §9.2). Local data is replaced by the
  /// Hub snapshot on first sync.
  Future<void> pairedWith(Uri hub, PairResult r, {String? name}) async {
    await ref.read(sessionStoreProvider).wipe();
    await set(Session(
      mode: SessionMode.hub,
      hubUrl: hub.toString(),
      deviceId: r.deviceId,
      token: r.token,
      role: r.role ?? DeviceRole.kitchen,
      admin: r.admin,
      deviceName: name,
    ));
  }

  /// Forgets the Hub or demo data and returns to onboarding.
  Future<void> reset() async {
    await ref.read(sessionStoreProvider).wipe();
    await set(const Session());
  }
}

final sessionProvider = NotifierProvider<SessionController, Session>(SessionController.new);

/// IANA zone of this device (falls back to the demo household's zone).
Future<String> deviceTimeZone() async {
  try {
    final info = await FlutterTimezone.getLocalTimezone();
    final name = info.identifier;
    if (locationOrUtc(name).name == name) return name;
  } on Object {
    // Platform without the plugin: fall through.
  }
  return 'America/Denver';
}

// ──────────────────────────────── Hub & sync ────────────────────────────────

final hubApiProvider = Provider<HubApi?>((ref) {
  final s = ref.watch(sessionProvider);
  if (!s.isHub) return null;
  final api = HubApi(Uri.parse(s.hubUrl!), token: s.token);
  ref.onDispose(api.close);
  return api;
});

/// Handles remote commands; replaced by the app shell once it is mounted.
final commandHandlerProvider = Provider<CommandHandler>((ref) => (cmd, args) async => {'handled': false});

/// Extra telemetry fields (frame stats, display class…); set by the shell.
final telemetrySourceProvider = Provider<Map<String, Object?> Function()>((ref) => () => const {});

final syncClientProvider = Provider<SyncClient?>((ref) {
  final s = ref.watch(sessionProvider);
  final api = ref.watch(hubApiProvider);
  if (!s.isHub || api == null) return null;
  final env = ref.watch(envProvider);
  final client = SyncClient(
    db: ref.watch(dbProvider),
    store: ref.watch(storeProvider),
    clock: ref.watch(hlcProvider),
    api: api,
    token: s.token!,
    appVersion: env.appVersion,
    platform: AppEnv.platformName,
    onRejected: (rejected) => ref.read(toastProvider).show(
          rejected.any((r) => r.reason.startsWith('acl')) ? 'That change needs a grown-up' : 'One change couldn’t be saved',
          emoji: '↩️',
          tone: DBannerTone.warning,
        ),
    onCommand: (cmd, args) => ref.read(commandHandlerProvider)(cmd, args),
    telemetry: () => ref.read(telemetrySourceProvider)(),
  );
  client.start();
  ref.onDispose(() => unawaited(client.dispose()));
  return client;
});

final syncStateProvider = StreamProvider<SyncState>((ref) {
  final c = ref.watch(syncClientProvider);
  if (c == null) return Stream.value(const SyncState(SyncPhase.idle));
  final out = StreamController<SyncState>();
  out.add(c.state);
  final sub = c.states.listen(out.add);
  ref.onDispose(() {
    unawaited(sub.cancel());
    unawaited(out.close());
  });
  return out.stream;
});

/// Local changes waiting for the Hub (shown when sync is degraded).
final outboxCountProvider = StreamProvider<int>((ref) {
  final db = ref.watch(dbProvider);
  return db.outbox.count().watchSingle();
});

// ─────────────────────────────── Writing ────────────────────────────────────

/// The actor stamped on gated ops (`profile:<id>` while grown-up mode is
/// unlocked). Overridden by the grown-up controller.
final actorProvider = Provider<String?>((ref) => null);

final mutatorProvider = Provider<Mutator>((ref) {
  final db = ref.watch(dbProvider);
  final hub = ref.watch(sessionProvider.select((s) => s.mode == SessionMode.hub));
  return Mutator(
    store: ref.watch(storeProvider),
    clock: ref.watch(hlcProvider),
    sink: hub
        ? (ops) async {
            final now = DateTime.now().millisecondsSinceEpoch;
            await db.batch((b) => b.insertAll(db.outbox, [
                  for (final op in ops) OutboxCompanion.insert(opId: op.id, opJson: jsonEncode(op.toJson()), createdMs: now),
                ]));
          }
        : (_) async {},
  );
});

/// Every synced write in the app goes through this (AGENTS.md rule 2):
/// it stamps HLCs, applies locally, queues for the Hub and nudges sync.
class DataWriter {
  DataWriter(this._mutator, this._afterCommit, this._actor);
  final Mutator _mutator;
  final void Function() _afterCommit;
  final String? Function() _actor;

  Op op(String table, String id, Map<String, Object?> fields, {OpKind kind = OpKind.upsert}) =>
      _mutator.makeOp(table, id, fields, kind: kind, actor: _actor());

  Future<void> commit(List<Op> ops) async {
    await _mutator.commit(ops);
    _afterCommit();
  }

  Future<void> upsert(String table, String id, Map<String, Object?> fields) => commit([op(table, id, fields)]);

  Future<String> create(String table, Map<String, Object?> fields) async {
    final id = newId();
    await upsert(table, id, fields);
    return id;
  }

  Future<void> insertOnly(String table, String id, Map<String, Object?> fields) => commit([op(table, id, fields, kind: OpKind.insertOnly)]);

  Future<void> delete(String table, String id) => commit([op(table, id, const {}, kind: OpKind.delete)]);
}

final writerProvider = Provider<DataWriter>((ref) {
  final m = ref.watch(mutatorProvider);
  return DataWriter(m, () => ref.read(syncClientProvider)?.kick(), () => ref.read(actorProvider));
});

// ───────────────────────────────── Time ─────────────────────────────────────

/// Ticks at every minute boundary of the UI clock. Only clocks, countdowns
/// and "today" derive from this (SPEC §12.4: nothing else listens to time).
final minuteProvider = StreamProvider<DateTime>((ref) {
  final clock = ref.watch(appClockProvider);
  final out = StreamController<DateTime>();
  Timer? timer;
  void schedule() {
    final now = clock.now();
    final next = DateTime(now.year, now.month, now.day, now.hour, now.minute + 1);
    timer = Timer(next.difference(now) + const Duration(milliseconds: 15), () {
      out.add(clock.now());
      schedule();
    });
  }

  out.add(clock.now());
  schedule();
  ref.onDispose(() {
    timer?.cancel();
    unawaited(out.close());
  });
  return out.stream;
});

/// Current minute as epoch ms (rounded down), for countdowns.
final nowMinuteMsProvider = Provider<int>((ref) {
  final now = ref.watch(minuteProvider).value ?? ref.watch(appClockProvider).now();
  return now.millisecondsSinceEpoch - now.millisecondsSinceEpoch % 60000;
});
