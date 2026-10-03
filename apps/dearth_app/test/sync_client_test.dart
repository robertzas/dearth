import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dearth_app/core/sync/hub_api.dart';
import 'package:dearth_app/core/sync/sync_client.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_hub/dearth_hub.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The device sync client against a real in-process Hub (SPEC §8.4, §16.1).
void main() {
  // Each simulated device has its own in-memory database on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;
  late DearthHub hub;
  final cleanups = <Future<void> Function()>[];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dearth-sync-');
    hub = await DearthHub.start(
      HubConfig(dataDir: dir.path, secretKey: 'a' * 64, port: 0, host: '127.0.0.1', fakeProviders: true, autoApprove: true, jobsEnabled: false),
      inMemory: true,
    );
  });

  tearDown(() async {
    for (final c in cleanups.reversed) {
      await c();
    }
    cleanups.clear();
    await hub.stop();
    await dir.delete(recursive: true);
  });

  Future<void> eventually(FutureOr<bool> Function() check, {String? reason}) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!await check()) {
      if (DateTime.now().isAfter(deadline)) fail('Timed out waiting${reason == null ? '' : ' for $reason'}');
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }

  Future<_Device> device(String name) async {
    final api = HubApi(hub.url);
    final ticket = await api.startPairing(name: name, platform: 'test');
    final paired = await api.pairingStatus(ticket);
    expect(paired.approved, isTrue);
    api.token = paired.token;
    final d = _Device(name, api, paired.token!);
    cleanups.add(d.dispose);
    d.client.start();
    await eventually(() => d.client.state.phase == SyncPhase.live, reason: '$name to go live');
    return d;
  }

  test('§8.4.6 a new device bootstraps the household from a snapshot', () async {
    final a = await device('a');
    final household = await a.store.readRow('households', Ids.household);
    expect(household, isNotNull);
    expect(int.parse((await a.db.kvGet(SyncClient.cursorKey))!), greaterThan(0));
  });

  test('§8.4.3 a write on one device reaches another live', () async {
    final a = await device('a');
    final b = await device('b');
    await a.write('list_items', 'milk', {'list_id': Ids.shoppingList, 'text': 'Milk'});
    await eventually(() async => (await b.store.readRow('list_items', 'milk'))?['text'] == 'Milk', reason: 'fan-out');
    await eventually(() async => (await a.db.select(a.db.outbox).get()).isEmpty, reason: 'ack to clear the outbox');
  });

  test('§8.4.3 offline writes queue durably and flush on reconnect', () async {
    final a = await device('a');
    final b = await device('b');
    await a.client.stop();
    await a.write('list_items', 'eggs', {'list_id': Ids.shoppingList, 'text': 'Eggs'});
    expect(await a.db.select(a.db.outbox).get(), hasLength(1));
    a.client.start();
    await eventually(() async => (await b.store.readRow('list_items', 'eggs')) != null, reason: 'queued op to arrive');
  });

  test('§8.4.2 concurrent edits converge field by field', () async {
    final a = await device('a');
    final b = await device('b');
    await a.write('list_items', 'x', {'list_id': Ids.shoppingList, 'text': 'Bread', 'qty': 1});
    await eventually(() async => (await b.store.readRow('list_items', 'x')) != null);
    await a.write('list_items', 'x', {'text': 'Sourdough bread'});
    await b.write('list_items', 'x', {'qty': 2});
    Future<bool> converged() async {
      final ra = await a.store.readRow('list_items', 'x');
      final rb = await b.store.readRow('list_items', 'x');
      return ra?['text'] == 'Sourdough bread' && rb?['text'] == 'Sourdough bread' && ra?['qty'] == 2 && rb?['qty'] == 2;
    }

    await eventually(converged, reason: 'both fields on both devices');
  });

  test('§8.4.3 a rejected op is rolled back by a repair', () async {
    final a = await device('a');
    final hubRow = await a.store.readRow('households', Ids.household);
    final rejections = <Rejection>[];
    a.rejected = rejections.add;
    // Devices may not write Hub-only tables (weather is integration-owned).
    await a.write('weather_reports', Ids.weather, {'data': jsonEncode({'bogus': true})});
    await eventually(() => rejections.isNotEmpty, reason: 'the rejection');
    expect(rejections.single.reason, 'hub_only');
    await eventually(() async => (await a.store.readRow('weather_reports', Ids.weather)) == null, reason: 'the repair to drop the bogus row');
    expect((await a.store.readRow('households', Ids.household))?['name'], hubRow?['name']);
  });

  test('§9.2 revoking a device disconnects it at once', () async {
    final a = await device('a');
    await hub.context.auth.revoke(a.client.deviceId!);
    await hub.context.connections.disconnect(a.client.deviceId!);
    await eventually(() => a.client.state.phase == SyncPhase.unauthorized, reason: 'unauthorized state');
  });
}

class _Device {
  _Device(this.name, this.api, String token) {
    db = DearthDb(NativeDatabase.memory());
    store = SyncStore(db);
    final clock = HlcClock(name);
    mutator = Mutator(
      store: store,
      clock: clock,
      sink: (ops) async {
        for (final op in ops) {
          await db.into(db.outbox).insert(OutboxCompanion.insert(opId: op.id, opJson: jsonEncode(op.toJson()), createdMs: 0));
        }
      },
    );
    client = SyncClient(
      db: db,
      store: store,
      clock: clock,
      api: api,
      token: token,
      appVersion: 'test',
      platform: 'test',
      onRejected: (r) => rejected?.call(r.single),
    );
  }

  final String name;
  final HubApi api;
  late final DearthDb db;
  late final SyncStore store;
  late final Mutator mutator;
  late final SyncClient client;
  void Function(Rejection r)? rejected;

  Future<void> write(String table, String id, Map<String, Object?> fields) async {
    await mutator.upsert(table, id, fields);
    client.kick();
  }

  Future<void> dispose() async {
    await client.dispose();
    api.close();
    await db.close();
  }
}
