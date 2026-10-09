import 'dart:async';
import 'dart:convert';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_integrations/dearth_integrations.dart' show DemoIds, demoSeedOps;
import 'package:dearth_ui/dearth_ui.dart';
import 'package:drift/drift.dart' show TableOrViewStatements;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

import '../shared/face_photo.dart';
import 'env.dart';
import 'session.dart';
import 'solo/built_in_hub.dart';
import 'solo/household_move.dart';
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
      // Faces with no photo behind them (no Hub): each shows its emoji.
      if (ref.read(envProvider).demoFaces)
        for (final id in [DemoIds.mom, DemoIds.dad, DemoIds.ava, DemoIds.dog])
          m.makeOp('profiles', id, {'avatar_blob': FaceCrop('demo-$id', aspect: 1, x: 0, y: 0, w: 1).encode()}),
    ]);
    await db.kvSet('demo.seeded', time.today().iso);
    await set(Session(mode: SessionMode.demo, role: r, admin: true, deviceName: 'This display'));
  }

  /// Sets this device up as just the Toybox for one kid (SPEC §7.2 "Toybox
  /// only"): a household of the kid and a grown-up with [pin] (the Toybox
  /// settings and leaving the mode need one), nothing else, nothing
  /// synced. [age] in years picks the games that suit them first; the
  /// birthday is the first of this month that many years ago, close enough
  /// for that.
  Future<void> startToybox({required String kid, required int age, required String pin, String? grownUp}) async {
    final db = ref.read(dbProvider);
    await ref.read(sessionStoreProvider).wipe();
    final tz = await deviceTimeZone();
    final m = Mutator(store: ref.read(storeProvider), clock: ref.read(hlcProvider), sink: (_) async {});
    final time = HouseholdTime.named(tz, clock: ref.read(appClockProvider).now);
    final today = time.today();
    final birthday = LocalDate(today.year - age, today.month, 1);
    final adult = grownUp?.trim().isNotEmpty ?? false ? grownUp!.trim() : 'Grown-up';
    await m.commit([
      ...householdDefaultOps(m, timezone: tz, name: '${kid.trim()}’s Toybox'),
      m.makeOp('profiles', newId(), {
        'name': kid.trim(), 'role': ProfileRole.child, 'color': 8, 'emoji': '🧒', 'birthday': birthday.iso, //
        'kid_stage': KidStage.forAge(age.toDouble()), 'buddy': 'bunny', 'sort_key': 'a',
      }),
      m.makeOp('profiles', newId(), {'name': adult, 'role': ProfileRole.adult, 'color': 3, 'emoji': '🧑', 'pin_hash': hashPin(pin), 'sort_key': 'b'}),
      m.makeOp('devices', Session.demoDeviceId, {'name': 'This tablet', 'role': DeviceRole.kidRoom, 'platform': AppEnv.platformName}),
    ]);
    await db.kvSet('toybox.since', today.iso);
    await set(const Session(mode: SessionMode.toybox, role: DeviceRole.kidRoom, admin: true, deviceName: 'This tablet'));
  }

  /// Runs this device on its own (SPEC §7.2 "Solo mode"): a fresh Hub built
  /// into the app, holding a household named [family] with one grown-up
  /// ([grownUp], [pin]), and this device paired to it as an admin.
  Future<void> startSolo({required String family, required String grownUp, required String pin, required String role, required String deviceName}) async {
    await ref.read(sessionStoreProvider).wipe();
    await BuiltInHub.erase();
    final hub = await BuiltInHub.start(
      timezone: await deviceTimeZone(),
      enroll: (name: deviceName, role: role),
      setup: [
        ('households', Ids.household, {'name': family}),
        ('profiles', newId(), {'name': grownUp, 'role': ProfileRole.adult, 'color': 3, 'emoji': '🧑', 'pin_hash': hashPin(pin), 'sort_key': 'a'}),
      ],
    );
    await _adopt(hub, await _claim(hub, deviceName), deviceName);
  }

  /// Moves this device from its Hub to one built into the app, bringing the
  /// family's data along (SPEC §7.2). Copying everything out needs admin
  /// rights there: this device's, or the Hub's admin [password]. The Hub
  /// keeps its copy; this device simply stops syncing with it.
  Future<void> runOnThisDevice({String? password, MoveProgress? onProgress}) async {
    final s = state;
    if (s.mode != SessionMode.hub || !s.isHub) throw StateError('Not paired with a Hub');
    final from = HubApi(Uri.parse(s.hubUrl!), token: s.token, adminPassword: s.admin ? null : password);
    final name = s.deviceName ?? 'This display';
    try {
      // Admin rights first, before anything is started or copied.
      await from.missingBlobs(const []);
      final household = await (ref.read(dbProvider).select(ref.read(dbProvider).households)..where((h) => h.id.equals(Ids.household))).getSingleOrNull();
      onProgress?.call('Starting the Hub on this device…', null);
      await BuiltInHub.erase();
      final hub = await BuiltInHub.start(timezone: household?.timezone ?? await deviceTimeZone(), enroll: (name: name, role: s.role));
      final paired = await _claim(hub, name);
      final to = HubApi(hub.url, token: paired.token);
      try {
        await moveHousehold(from, to, onProgress: onProgress);
      } on Object {
        await BuiltInHub.erase();
        rethrow;
      } finally {
        to.close();
      }
      await ref.read(sessionStoreProvider).wipe();
      await _adopt(hub, paired, name);
    } finally {
      from.close();
    }
  }

  /// Moves a household running on its own to the Hub at [target] (its admin
  /// [password]), then pairs this device there and removes the built-in Hub
  /// (SPEC §7.2). The family's data, photos and pictures come along; where
  /// the Hub already has the same rows, this household's win.
  Future<void> moveToHub(Uri target, String password, {MoveProgress? onProgress}) async {
    final s = state;
    if (!s.isSolo) throw StateError('Not running on its own');
    // Its own client: hubApiProvider watches this session, so reading it
    // from here is a dependency cycle.
    final from = HubApi(Uri.parse(s.hubUrl!), token: s.token);
    final to = HubApi(target, adminPassword: password);
    try {
      await to.health();
      // A wrong password stops here, before anything is copied.
      await to.missingBlobs(const []);
      await moveHousehold(from, to, onProgress: onProgress);
      onProgress?.call('Connecting this device…', null);
      final ticket = await to.startPairing(name: s.deviceName ?? 'Display', platform: AppEnv.platformName, role: s.role);
      await to.approveWithPassword(password, ticket.code, role: s.role, name: s.deviceName);
      final r = await to.pairingStatus(ticket);
      if (!r.approved) throw HubApiException(0, 'pairing_failed', 'The Hub didn’t pair this device. Try again.');
      await pairedWith(target, r, name: s.deviceName);
      await BuiltInHub.erase();
    } finally {
      from.close();
      to.close();
    }
  }

  Future<PairResult> _claim(BuiltInHub hub, String name) async {
    final api = HubApi(hub.url);
    try {
      final r = await api.claim(hub.enrollCode!, platform: AppEnv.platformName, name: name);
      if (!r.approved) throw StateError('The built-in Hub didn’t pair this device (${r.status})');
      return r;
    } finally {
      api.close();
    }
  }

  Future<void> _adopt(BuiltInHub hub, PairResult r, String name) => set(Session(
        mode: SessionMode.solo,
        hubUrl: hub.url.toString(),
        deviceId: r.deviceId,
        token: r.token,
        role: r.role ?? DeviceRole.kitchen,
        admin: true,
        deviceName: name,
      ));

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

  /// Forgets the Hub or demo data and returns to onboarding. On its own,
  /// that deletes the household: the built-in Hub held the only copy.
  Future<void> reset() async {
    if (state.isSolo) await BuiltInHub.erase();
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

/// The Hub built into this app while the device runs on its own (SPEC §7.2
/// "Solo mode"): started with the app on the port it had last time (when
/// free), stopped when the device leaves the mode, started again if it
/// ever falls over.
final builtInHubProvider = FutureProvider<BuiltInHub?>((ref) async {
  final solo = ref.watch(sessionProvider.select((s) => s.isSolo));
  if (!solo || !BuiltInHub.supported) return null;
  final saved = Uri.parse(ref.read(sessionProvider).hubUrl!);
  final running = BuiltInHub.current;
  final hub = running != null && running.url == saved ? running : await BuiltInHub.start(port: saved.port, timezone: await deviceTimeZone());
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    unawaited(hub.stop());
  });
  unawaited(hub.exited.then((_) {
    if (!disposed) Timer(const Duration(seconds: 2), ref.invalidateSelf);
  }));
  if (hub.url != saved) {
    await ref.read(sessionProvider.notifier).set(ref.read(sessionProvider).copyWith(hubUrl: hub.url.toString()));
  }
  return hub;
});

final hubApiProvider = Provider<HubApi?>((ref) {
  final s = ref.watch(sessionProvider);
  if (!s.isHub) return null;
  // On its own, the API is there once the built-in Hub has started.
  if (s.isSolo && ref.watch(builtInHubProvider).value == null) return null;
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
  final hub = ref.watch(sessionProvider.select((s) => s.isHub));
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
