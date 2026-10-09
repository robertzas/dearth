import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dearth_app/core/providers.dart';
import 'package:dearth_app/core/session.dart';
import 'package:dearth_app/core/solo/built_in_hub.dart';
import 'package:dearth_app/core/sync/hub_api.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_hub/dearth_hub.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Solo mode (SPEC §7.2): the Hub built into the app, and moving a
/// household between it and a server. Real isolates and sockets, so these
/// are plain tests (a widget-test binding fakes HTTP).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory tmp;
  late DearthDb db;
  late ProviderContainer c;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('dearth-solo-');
    builtInHubDirOverride = '${tmp.path}/hub';
    db = DearthDb(NativeDatabase.memory());
    c = ProviderContainer(overrides: [dbProvider.overrideWithValue(db), nodeIdProvider.overrideWithValue('dtest')]);
  });

  tearDown(() async {
    c.dispose();
    await BuiltInHub.erase();
    await db.close();
    await tmp.delete(recursive: true);
  });

  Future<Map<String, List<Map<String, Object?>>>> tablesOf(HubApi api) async {
    final snap = await api.snapshot();
    return {
      for (final MapEntry(:key, :value) in (snap['tables']! as Map<String, Object?>).entries) key: [for (final r in value! as List) r as Map<String, Object?>],
    };
  }

  test('§7.2 Solo mode: a Hub inside the app, set up with the family, this device its admin, kept across restarts', () async {
    await c.read(sessionProvider.notifier).startSolo(family: 'The Parkers', grownUp: 'Sam', pin: '2468', role: DeviceRole.kitchen, deviceName: 'Kitchen');
    final s = c.read(sessionProvider);
    expect(s.isSolo, isTrue);
    expect(s.isHub, isTrue, reason: 'it syncs like any paired device');
    expect(s.admin, isTrue);
    final url = Uri.parse(s.hubUrl!);
    expect(url.host, '127.0.0.1', reason: 'nothing else on the network reaches it');

    final api = HubApi(url, token: s.token);
    addTearDown(api.close);
    var tables = await tablesOf(api);
    expect(tables['households']!.single['name'], 'The Parkers');
    final sam = tables['profiles']!.single;
    expect(sam['name'], 'Sam');
    expect(sam['role'], ProfileRole.adult);
    expect(verifyPin('2468', sam['pin_hash']! as String), isTrue);
    final status = await api.get('/api/admin/status');
    expect([for (final d in status['devices']! as List) (d as Map)['name']], ['Kitchen']);

    // Restarting (the app opening again) keeps the household and the
    // device's pairing; it asks for the same port (another, if that's taken).
    await BuiltInHub.current!.stop();
    expect(BuiltInHub.current, isNull);
    final again = await BuiltInHub.start(port: url.port);
    final api2 = HubApi(again.url, token: s.token);
    addTearDown(api2.close);
    tables = await tablesOf(api2);
    expect(tables['households']!.single['name'], 'The Parkers');
  });

  test('§7.2 moving: on its own → a Hub with the family and its pictures, and back to running on its own', () async {
    final server = await DearthHub.start(
      HubConfig(dataDir: '${tmp.path}/server', secretKey: 's' * 32, port: 0, host: '127.0.0.1', adminPassword: 'hub-pw', jobsEnabled: false, fakeProviders: true),
      inMemory: true,
    );
    addTearDown(server.stop);
    final session = c.read(sessionProvider.notifier);
    await session.startSolo(family: 'The Parkers', grownUp: 'Sam', pin: '2468', role: DeviceRole.kitchen, deviceName: 'Kitchen');

    // A face photo and a child who uses it, on the built-in Hub.
    final solo = c.read(sessionProvider);
    final local = HubApi(Uri.parse(solo.hubUrl!), token: solo.token);
    final face = Uint8List.fromList(utf8.encode('Ava’s face'));
    final sha = (await local.uploadBlob(face, 'image/jpeg'))['sha']! as String;
    await local.importHousehold({
      'schema': kSchemaMajor,
      'tables': {
        'profiles': [
          {'id': 'ava', 'name': 'Ava', 'role': ProfileRole.child, 'avatar_blob': jsonEncode({'sha': sha, 'aspect': 1, 'crop': [0, 0, 1]})},
        ],
      },
    });
    local.close();

    await expectLater(() => session.moveToHub(server.url, 'nope'), throwsA(isA<HubApiException>().having((e) => e.status, 'status', 403)));
    expect(c.read(sessionProvider).isSolo, isTrue, reason: 'a wrong password changes nothing');

    final steps = <String>[];
    await session.moveToHub(server.url, 'hub-pw', onProgress: (step, _) => steps.add(step));
    expect(steps, containsAll(['Copying photos and pictures…', 'Copying the family’s data…']));
    final moved = c.read(sessionProvider);
    expect(moved.isSolo, isFalse);
    expect(moved.mode, SessionMode.hub);
    expect(moved.hubUrl, server.url.toString());
    expect(moved.admin, isTrue);
    expect(BuiltInHub.current, isNull);
    expect(Directory(builtInHubDirOverride!).existsSync(), isFalse, reason: 'the built-in Hub is removed once the Hub has everything');
    final names = (await server.db.select(server.db.profiles).get()).map((p) => p.name);
    expect(names, containsAll(['Sam', 'Ava']));
    expect((await server.db.select(server.db.households).getSingle()).name, 'The Parkers');
    expect(await server.context.blobs.entry(sha), isNotNull);

    // And back: a copy comes to a new built-in Hub; the server keeps its own.
    await session.runOnThisDevice();
    final back = c.read(sessionProvider);
    expect(back.isSolo, isTrue);
    final api = HubApi(Uri.parse(back.hubUrl!), token: back.token);
    addTearDown(api.close);
    final tables = await tablesOf(api);
    expect(tables['households']!.single['name'], 'The Parkers');
    expect([for (final p in tables['profiles']!) p['name']], containsAll(['Sam', 'Ava']));
    expect((await api.blobBytes(sha)), face);
    expect((await server.db.select(server.db.profiles).get()), hasLength(2), reason: 'the Hub keeps its copy');
  });
}
