import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_hub/dearth_hub.dart';
import 'package:dearth_integrations/dearth_integrations.dart' show Fetcher, RecipeQuery;
import 'package:drift/drift.dart' show BooleanExpressionOperators, driftRuntimeOptions;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _admin = {'x-dearth-admin': 'test-admin', 'content-type': 'application/json'};

/// A test device speaking the sync protocol.
class TestDevice {
  TestDevice(this.hub, this.token);
  final DearthHub hub;
  final String token;
  late WebSocketChannel ws;
  final messages = StreamController<SyncMessage>.broadcast();
  final received = <SeqOp>[];
  int seq = 0;
  final clock = HlcClock('dev${DateTime.now().microsecondsSinceEpoch}');

  Future<WelcomeMsg> connect({int since = -1}) async {
    ws = WebSocketChannel.connect(Uri.parse('ws://127.0.0.1:${hub.port}/api/sync'));
    ws.stream.listen((f) {
      final m = SyncMessage.decode(f as String);
      if (m is OpsMsg) {
        received.addAll(m.ops);
        seq = m.upTo;
      }
      messages.add(m);
    });
    final welcome = messages.stream.firstWhere((m) => m is WelcomeMsg || m is ErrorMsg);
    ws.sink.add(HelloMsg(token: token, since: since < 0 ? seq : since).encode());
    final w = await welcome.timeout(const Duration(seconds: 5));
    if (w is ErrorMsg) throw StateError('hello rejected: ${w.code}');
    return w as WelcomeMsg;
  }

  Future<AckMsg> push(List<Op> ops) async {
    final ack = messages.stream.firstWhere((m) => m is AckMsg).timeout(const Duration(seconds: 5));
    ws.sink.add(PushMsg(batch: newId(), ops: ops).encode());
    return await ack as AckMsg;
  }

  Op op(String table, String id, Map<String, Object?> fields, {OpKind kind = OpKind.upsert, String? actor}) =>
      Op(id: newId(), table: table, rowId: id, kind: kind, fields: fields, hlc: clock.tick().pack(), actor: actor);

  Future<void> close() async => ws.sink.close();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late DearthHub hub;
  late Directory dir;

  Uri u(String path) => Uri.parse('http://127.0.0.1:${hub.port}$path');
  Future<Map<String, Object?>> postJson(String path, Object body, {Map<String, String>? headers}) async {
    final r = await http.post(u(path), headers: {'content-type': 'application/json', ...?headers}, body: jsonEncode(body));
    expect(r.statusCode, lessThan(300), reason: '$path → ${r.statusCode} ${r.body}');
    return jsonDecode(r.body) as Map<String, Object?>;
  }

  Future<String> pairDevice(String name, {String role = 'kitchen', bool admin = false}) async {
    final start = await postJson('/api/pair/start', {'name': name, 'platform': 'test', 'role': role});
    var status = await postJson('/api/pair/status', {'pairingId': start['pairingId'], 'secret': start['secret']});
    expect(status['status'], 'pending');
    await postJson('/api/admin/pair/approve', {'code': start['code'], 'role': role, 'admin': admin}, headers: _admin);
    status = await postJson('/api/pair/status', {'pairingId': start['pairingId'], 'secret': start['secret']});
    expect(status['status'], 'approved');
    final again = await postJson('/api/pair/status', {'pairingId': start['pairingId'], 'secret': start['secret']});
    expect(again['status'], 'claimed', reason: 'token is issued exactly once');
    return status['token']! as String;
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dearth-hub-test');
    hub = await DearthHub.start(
      HubConfig(dataDir: dir.path, secretKey: 'k' * 32, port: 0, host: '127.0.0.1', fakeProviders: true, adminPassword: 'test-admin', jobsEnabled: false),
      inMemory: true,
    );
  });

  tearDown(() async {
    await hub.stop();
    await dir.delete(recursive: true);
  });

  test('health', () async {
    final r = jsonDecode((await http.get(u('/api/health'))).body) as Map<String, Object?>;
    expect(r['ok'], isTrue);
    expect(r['schema'], kSchemaMajor);
  });

  test('pairing, enrollment and admin auth', () async {
    final token = await pairDevice('Kitchen');
    expect(token, hasLength(64));
    final enroll = await postJson('/api/admin/enroll', {'name': 'Frame', 'role': 'kitchen', 'orientation': 'landscape'}, headers: _admin);
    final claimed = await postJson('/api/pair/claim', {'code': enroll['code'], 'platform': 'android'});
    expect(claimed['status'], 'approved');
    final bad = await http.post(u('/api/pair/claim'), body: jsonEncode({'code': enroll['code']}));
    expect(bad.statusCode, 404, reason: 'codes are single-use');
    final wrongPw = await http.get(u('/api/admin/status'), headers: {'x-dearth-admin': 'nope'});
    expect(wrongPw.statusCode, 403);
    final noAuth = await http.get(u('/api/sync/snapshot'));
    expect(noAuth.statusCode, 401);
  });

  test('FR-ADM-01: an admin removes a device, a display removes itself; both leave the list and their tokens stop working', () async {
    final keep = await pairDevice('Kitchen');
    final old = await pairDevice('Old tablet');
    final leaving = await pairDevice('Playroom');
    Future<List<String>> names() async {
      final r = jsonDecode((await http.get(u('/api/admin/status'), headers: _admin)).body) as Map<String, Object?>;
      return [for (final d in r['devices']! as List) (d as Map<String, Object?>)['name']! as String];
    }

    final oldId = (await hub.context.auth.deviceForToken(old))!.deviceId;
    final removed = await http.delete(u('/api/admin/devices/$oldId'), headers: _admin);
    expect(removed.statusCode, 200);
    final bye = await http.delete(u('/api/devices/self'), headers: {'authorization': 'Bearer $leaving'});
    expect(bye.statusCode, 200);
    expect(await names(), ['Kitchen']);
    for (final token in [old, leaving]) {
      final r = await http.get(u('/api/sync/snapshot'), headers: {'authorization': 'Bearer $token'});
      expect(r.statusCode, 401, reason: 'a removed device has to pair again');
    }
    expect((await http.get(u('/api/sync/snapshot'), headers: {'authorization': 'Bearer $keep'})).statusCode, 200);
    expect((await http.delete(u('/api/devices/self'))).statusCode, 401);
  });

  test('a display that asks for a rejoin code comes back as itself after a reset, settings kept; the old token stops', () async {
    final old = await pairDevice('Kitchen frame', admin: true);
    final id = (await hub.context.auth.deviceForToken(old))!.deviceId;
    await hub.context.kernel.upsert('devices', id, {'settings': '{"theme":"evening"}', 'orientation': 'landscape'});
    final ticket = await postJson('/api/devices/self/rejoin', {'minutes': 30}, headers: {'authorization': 'Bearer $old'});
    expect(ticket['deviceId'], id);
    expect(ticket['expiresInS'], 1800);
    // The frame is wiped; its new install claims the code.
    final claimed = await postJson('/api/pair/claim', {'code': ticket['code'], 'platform': 'android', 'model': 'JT215M'});
    expect(claimed['deviceId'], id, reason: 'the same device, not a new one');
    expect(claimed['name'], 'Kitchen frame');
    expect(claimed['admin'], isTrue);
    final row = await hub.context.kernel.store.readRow('devices', id);
    expect(row!['settings'], '{"theme":"evening"}');
    expect(row['orientation'], 'landscape');
    expect(row['model'], 'JT215M');
    final status = jsonDecode((await http.get(u('/api/admin/status'), headers: _admin)).body) as Map<String, Object?>;
    expect((status['devices']! as List), hasLength(1), reason: 'no second entry for the frame');
    expect((await http.get(u('/api/sync/snapshot'), headers: {'authorization': 'Bearer $old'})).statusCode, 401);
    expect((await http.get(u('/api/sync/snapshot'), headers: {'authorization': 'Bearer ${claimed['token']}'})).statusCode, 200);
    expect((await http.post(u('/api/pair/claim'), body: jsonEncode({'code': ticket['code']}))).statusCode, 404, reason: 'single use');

    // A device removed after it made its code stays removed.
    final again = await postJson('/api/devices/self/rejoin', {}, headers: {'authorization': 'Bearer ${claimed['token']}'});
    await http.delete(u('/api/admin/devices/$id'), headers: _admin);
    expect((await http.post(u('/api/pair/claim'), body: jsonEncode({'code': again['code']}))).statusCode, 404);
  });

  test('sync: snapshot bootstrap, live fan-out, ACLs and hub-owned fields', () async {
    final kitchen = TestDevice(hub, await pairDevice('Kitchen', admin: true));
    final kid = TestDevice(hub, await pairDevice('Ava room', role: DeviceRole.kidRoom));

    // New devices bootstrap from a snapshot.
    final w = await kitchen.connect(since: 0);
    expect(w.snapshotRequired, isTrue);
    final snap = jsonDecode((await http.get(u('/api/sync/snapshot'), headers: {'authorization': 'Bearer ${kitchen.token}'})).body) as Map<String, Object?>;
    final tables = snap['tables']! as Map<String, Object?>;
    expect((tables['households']! as List), isNotEmpty);
    expect(tables.containsKey('lists'), isTrue);
    final kidSnap = jsonDecode((await http.get(u('/api/sync/snapshot'), headers: {'authorization': 'Bearer ${kid.token}'})).body) as Map<String, Object?>;
    expect((kidSnap['tables']! as Map).containsKey('lists'), isFalse, reason: 'kid room never receives adult lists');
    await kitchen.close();

    kitchen.seq = snap['seq']! as int;
    await kitchen.connect();
    kid.seq = kidSnap['seq']! as int;
    await kid.connect();

    // Kitchen creates an event; the kid room receives it live.
    final got = kid.messages.stream.where((m) => m is OpsMsg && m.ops.any((o) => o.op.rowId == 'ev1')).first.timeout(const Duration(seconds: 5));
    final ack = await kitchen.push([kitchen.op('events', 'ev1', {'title': 'Swim', 'start_ms': 1, 'etag': 'forged'})]);
    expect(ack.accepted, hasLength(1));
    await got;
    final row = await hub.context.kernel.store.readRow('events', 'ev1');
    expect(row!['title'], 'Swim');
    expect(row['etag'], isNull, reason: 'devices cannot write integration-owned fields');

    // Kid room may complete chores but not edit chore definitions or approve.
    final denied = await kid.push([kid.op('chores', 'c1', {'title': 'hacked'})]);
    expect(denied.rejected.single.reason, 'acl:role');
    final approve = await kid.push([kid.op('chore_instances', 'ci1', {'status': 'approved'})]);
    expect(approve.rejected.single.reason, 'acl:approval_requires_adult');
    final done = await kid.push([kid.op('chore_instances', 'ci1', {'status': 'done', 'chore_id': 'c1', 'date': '2026-10-02'})]);
    expect(done.accepted, hasLength(1));

    // Adults approve with an adult actor.
    await hub.context.kernel.upsert('profiles', 'p-mom', {'name': 'Mom', 'role': 'adult'});
    final adultApprove = await kitchen.push([kitchen.op('chore_instances', 'ci1', {'status': 'approved'}, actor: 'profile:p-mom')]);
    expect(adultApprove.accepted, hasLength(1));

    // Duplicate pushes are idempotent.
    final dupOp = kitchen.op('notes', 'n1', {'body': 'hi'});
    expect((await kitchen.push([dupOp])).accepted, [dupOp.id]);
    expect((await kitchen.push([dupOp])).accepted, [dupOp.id]);

    // Reconnecting with a cursor replays only newer ops.
    await kitchen.close();
    final before = kitchen.received.length;
    await hub.context.kernel.upsert('notes', 'n2', {'body': 'while offline'});
    await kitchen.connect();
    await kitchen.messages.stream.firstWhere((m) => m is OpsMsg && m.live).timeout(const Duration(seconds: 5));
    expect(kitchen.received.skip(before).map((o) => o.op.rowId), contains('n2'));
    await kitchen.close();
    await kid.close();
  });

  test('blobs: upload, content addressing and variants', () async {
    final token = await pairDevice('Phone', role: DeviceRole.personal);
    final file = File('${dir.path}/test.jpg');
    final made = await Process.run('vips', ['black', file.path, '320', '200']).catchError((Object _) => ProcessResult(0, 1, '', ''));
    final bytes = made.exitCode == 0 ? file.readAsBytesSync() : utf8.encode('not really an image');
    final r = await http.post(u('/api/blobs'), headers: {'authorization': 'Bearer $token', 'content-type': made.exitCode == 0 ? 'image/jpeg' : 'text/plain'}, body: bytes);
    expect(r.statusCode, 200, reason: r.body);
    final meta = jsonDecode(r.body) as Map<String, Object?>;
    final sha = meta['sha']! as String;
    final back = await http.get(u('/api/blobs/$sha'));
    expect(back.bodyBytes, bytes);
    if (made.exitCode == 0) {
      expect(meta['width'], 320);
      final small = await http.get(u('/api/blobs/$sha?w=64&h=64'));
      expect(small.statusCode, 200);
      expect(small.headers['content-type'], 'image/jpeg');
      expect(small.bodyBytes.length, lessThan(bytes.length));
    }
    expect((await http.get(u('/api/blobs/${'0' * 64}'))).statusCode, 404);
  });

  test('recipes (fake providers): search, discover, recommend', () async {
    final token = await pairDevice('Phone', role: DeviceRole.personal);
    final h = {'authorization': 'Bearer $token'};
    final search = jsonDecode((await http.get(u('/api/recipes/search?q=soup'), headers: h)).body) as List;
    expect(search, isNotEmpty);
    final popular = jsonDecode((await http.get(u('/api/recipes/discover/popular?limit=5'), headers: h)).body) as List;
    expect(popular.length, 5);
    final tacos = (jsonDecode((await http.get(u('/api/recipes/search?q=chicken%20tacos'), headers: h)).body) as List).first;
    final rec = jsonDecode((await http.post(u('/api/recipes/recommend'), headers: {...h, 'content-type': 'application/json'}, body: jsonEncode({'recipes': [tacos], 'limit': 5}))).body) as List;
    expect(rec, isNotEmpty);
    expect((rec.first as Map)['why'], startsWith('Uses your'));
  });

  test('FR-RCP-11: "pairs with your plan" offers the family\'s own recipes from the box', () async {
    final token = await pairDevice('Phone', role: DeviceRole.personal);
    final h = {'authorization': 'Bearer $token', 'content-type': 'application/json'};
    final lines = ['2 limes', '1 bunch cilantro', '1 can black beans', '1 red onion', '8 corn tortillas'];
    await hub.context.kernel.upsert('recipes', 'fam-1', {
      'source': 'box',
      'title': 'Grandma Rose’s Bean Tostadas',
      'servings': 4,
      'ingredients': [for (final l in lines) parseIngredientLine(l).toJson()],
      'steps': ['Warm the beans.', 'Pile everything on the tortillas.'],
      'saved': true,
      'deleted': false,
    });
    final planned = RecipeData(id: 'p1', source: 'test', title: 'Lime Chicken', ingredients: [for (final l in ['2 limes', '1 bunch cilantro', '1 lb chicken']) parseIngredientLine(l)]);
    final rec = jsonDecode((await http.post(u('/api/recipes/recommend'), headers: h, body: jsonEncode({'recipes': [planned.toJson()], 'limit': 40}))).body) as List;
    final mine = rec.map((r) => (r as Map)['recipe'] as Map).where((r) => r['id'] == 'fam-1').toList();
    expect(mine, hasLength(1));
    expect(mine.single['title'], 'Grandma Rose’s Bean Tostadas');
  });

  test('every recipe an API returns is kept for good: offline, and after a restart, a search still finds it', () async {
    final fixture = File('../../packages/dearth_integrations/test/fixtures/themealdb_search.json').readAsStringSync();
    var online = true;
    final client = MockClient((req) async {
      if (!online) return http.Response('', 503);
      if (req.url.host.contains('themealdb') && req.url.path.endsWith('search.php')) return http.Response(fixture, 200, headers: {'content-type': 'application/json'});
      return http.Response('', 404);
    });
    final dir2 = await Directory.systemTemp.createTemp('dearth-hub-recipes');
    addTearDown(() => dir2.delete(recursive: true));
    Future<DearthHub> start() => DearthHub.start(
          HubConfig(dataDir: dir2.path, secretKey: 'k' * 32, port: 0, host: '127.0.0.1', adminPassword: 'test-admin', jobsEnabled: false),
          fetcher: Fetcher(client: client, sleep: (_) async {}),
        );
    var hub2 = await start();
    const query = RecipeQuery(text: 'breadfruit');
    final first = await hub2.context.recipes.search(query);
    expect(first.map((r) => r.title), contains('Breadfruit Tacos'));
    final kept = await hub2.db.select(hub2.db.recipeCache).get();
    expect(kept.map((r) => r.source).toSet(), {'themealdb'}, reason: 'API recipes, not the bundled catalog');
    expect(kept.map((r) => r.title), containsAll(['Breadfruit Tacos', 'Crock Pot Chicken Baked Tacos']));
    await hub2.stop();

    // The Hub restarts with the internet gone: the recipe is still there.
    online = false;
    hub2 = await start();
    addTearDown(hub2.stop);
    final again = await hub2.context.recipes.search(query);
    expect(again.map((r) => r.title), contains('Breadfruit Tacos'));
    final tacos = again.firstWhere((r) => r.title == 'Breadfruit Tacos');
    expect(tacos.ingredients, isNotEmpty, reason: 'the whole recipe, not just its name');
    expect(await hub2.context.recipes.known(tacos.id), isNotNull);
    expect(await hub2.context.recipes.rememberedCount(), kept.length);
  });

  test('integration secrets are write-only; weather job writes the merged report', () async {
    final put = await http.put(u('/api/admin/integrations/weather'), headers: _admin, body: jsonEncode({'apiKey': 'SECRET-123', 'stationId': 'KCOAURORA123'}));
    expect(put.statusCode, 200);
    final view = (await http.get(u('/api/admin/integrations'), headers: _admin)).body;
    expect(view, contains('"hasKey":true'));
    expect(view, isNot(contains('SECRET-123')));

    await hub.context.kernel.upsert('households', Ids.household, {'lat': 39.71, 'lon': -104.7, 'timezone': 'America/Denver', 'location_label': 'Aurora, CO'});
    await hub.context.scheduler.runAndWait('weather');
    final row = await hub.context.kernel.store.readRow('weather_reports', Ids.weather);
    final report = WeatherReport.tryDecode(row!['data'] as String?)!;
    expect(report.daily, hasLength(10));
    expect(report.hourly, hasLength(48));
  });

  test('ICS job imports, keeps annotations and tombstones removed events', () async {
    var feed = File('../../packages/dearth_integrations/test/fixtures/school.ics').existsSync()
        ? File('../../packages/dearth_integrations/test/fixtures/school.ics').readAsStringSync()
        : 'BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:a@x\nDTSTART;VALUE=DATE:20261009\nSUMMARY:No school\nEND:VEVENT\n'
            'BEGIN:VEVENT\nUID:b@x\nDTSTART:20261015T150000Z\nDTEND:20261015T160000Z\nSUMMARY:Conferences\nEND:VEVENT\nEND:VCALENDAR\n';
    final server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) {
      req.response
        ..headers.contentType = ContentType('text', 'calendar')
        ..write(feed);
      unawaited(req.response.close());
    });
    addTearDown(() => server.close(force: true));
    final created = await postJson('/api/admin/calendars/ics', {'name': 'School', 'url': 'http://127.0.0.1:${server.port}/cal.ics'}, headers: _admin);
    await hub.context.scheduler.runAndWait('ics');
    final db = hub.db;
    var events = await (db.select(db.events)..where((t) => t.sourceId.equals(created['id']! as String))).get();
    expect(events.where((e) => !e.deleted).map((e) => e.title), containsAll(['No school', 'Conferences']));
    // A device annotates an event; re-import must keep it.
    final noSchool = events.firstWhere((e) => e.title == 'No school');
    await hub.context.kernel.upsert('events', noSchool.id, {'profile_ids': ['p-ava']});
    feed = feed.replaceAll(RegExp(r'BEGIN:VEVENT\nUID:b@x[\s\S]*?END:VEVENT\n'), '');
    await hub.context.kernel.upsert('calendar_sources', created['id']! as String, {'last_sync_ms': null});
    await hub.context.jobs.write('ics:${created['id']}', data: {'fetchedMs': 0});
    await hub.context.scheduler.runAndWait('ics');
    events = await (db.select(db.events)..where((t) => t.sourceId.equals(created['id']! as String))).get();
    expect(events.firstWhere((e) => e.title == 'Conferences').deleted, isTrue);
    expect(events.firstWhere((e) => e.title == 'No school').profileIds, '["p-ava"]');
  });

  test('photo sources: the same album twice is refused, old duplicates fold, removing takes its photos', () async {
    final first = await postJson('/api/admin/photos/sources', {'kind': 'folder', 'config': {'path': '/photos/family'}}, headers: _admin);
    final again = await http.post(u('/api/admin/photos/sources'), headers: _admin, body: jsonEncode({'kind': 'folder', 'config': {'path': '/photos/family/'}}));
    expect(again.statusCode, 409, reason: 'one folder, written two ways');
    // A duplicate added before the Hub refused them, with photos of its own.
    final kernel = hub.context.kernel;
    final keep = first['id']! as String;
    final copy = await kernel.create('photo_sources', {'kind': 'folder', 'name': 'Family', 'config': {'path': '/photos/family'}, 'enabled': true});
    await kernel.upsert('photo_sources', keep, {'item_count': 2});
    for (final (source, n) in [(keep, 2), (copy, 1)]) {
      for (var i = 0; i < n; i++) {
        await kernel.upsert('photo_items', '$source-$i', {'source_id': source, 'remote_id': '$i.jpg', 'blob_ref': 'sha$i'});
      }
    }
    await hub.context.scheduler.runAndWait('photos');
    final db = hub.db;
    final live = await (db.select(db.photoSources)..where((t) => t.deleted.equals(false))).get();
    expect(live.map((s) => s.id), [keep], reason: 'the copy with more photos stays');
    final items = await db.select(db.photoItems).get();
    expect(items.where((i) => i.sourceId == copy).every((i) => i.deleted), isTrue);
    expect(items.where((i) => i.sourceId == keep).every((i) => !i.deleted), isTrue);

    final removed = await http.delete(u('/api/admin/photos/sources/$keep'), headers: _admin);
    expect(removed.statusCode, 200);
    expect((await db.select(db.photoSources).get()).every((s) => s.deleted), isTrue);
    expect((await db.select(db.photoItems).get()).every((i) => i.deleted), isTrue);
    // Gone, it can be added again.
    await postJson('/api/admin/photos/sources', {'kind': 'folder', 'config': {'path': '/photos/family'}}, headers: _admin);
  });

  test('Amazon albums: a big one comes in batches from one listing; a busy reply pauses the source', () async {
    // A 1×1 PNG for every thumbnail.
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');
    var listings = 0, thumbs = 0;
    var busy = false;
    const json = {'content-type': 'application/json'};
    final amazon = MockClient((req) async {
      final path = req.url.path;
      if (path.contains('/photosGroups/shares/')) return http.Response(jsonEncode({'name': 'Family'}), 200, headers: json);
      if (path.contains('/search/groups/')) {
        listings++;
        final first = req.url.queryParameters['offset'] == '0';
        return http.Response(jsonEncode({
          'count': 155,
          'data': [
            if (first)
              for (var i = 0; i < 155; i++) {'id': 'p$i', 'ownerId': 'O1', 'kind': 'FILE', 'contentProperties': {'contentType': 'image/png', 'image': {'width': 1, 'height': 1}}},
          ],
        }), 200, headers: json);
      }
      if (req.url.host.startsWith('thumbnails')) {
        thumbs++;
        return busy ? http.Response('', 503) : http.Response.bytes(png, 200, headers: {'content-type': 'image/png'});
      }
      return http.Response('', 404);
    });
    final dir2 = await Directory.systemTemp.createTemp('dearth-hub-amazon');
    final hub2 = await DearthHub.start(
      HubConfig(dataDir: dir2.path, secretKey: 'k' * 32, port: 0, host: '127.0.0.1', adminPassword: 'test-admin', jobsEnabled: false),
      inMemory: true,
      fetcher: Fetcher(client: amazon, sleep: (_) async {}),
    );
    addTearDown(() async {
      await hub2.stop();
      await dir2.delete(recursive: true);
    });
    final db = hub2.db;
    Future<List<PhotoItem>> items(String source) => (db.select(db.photoItems)..where((t) => t.sourceId.equals(source) & t.deleted.equals(false))).get();
    Future<PhotoSource> source(String id) => (db.select(db.photoSources)..where((t) => t.id.equals(id))).getSingle();
    final family = await hub2.context.kernel.create('photo_sources', {
      'kind': 'amazon',
      'name': 'Photos',
      'config': {'shareUrl': 'https://www.amazon.com/photos/shared/GrOuPiD1234567890ab.SeCrEtToKeN987'},
      'enabled': true,
    });
    await hub2.context.scheduler.runAndWait('photos');
    expect(await items(family), hasLength(150), reason: 'a batch at a time');
    expect((await source(family)).status, 'adding photos · 150 of 155');
    expect(listings, 1);
    // The catch-up batch downloads from the same listing: no new listing.
    await hub2.context.scheduler.runAndWait('photos');
    expect(await items(family), hasLength(155));
    expect(listings, 1, reason: 'listing a big album every 20 s is what got the Hub refused');
    expect((await source(family)).name, 'Family');

    // Another album, while Amazon is refusing thumbnails.
    busy = true;
    final party = await hub2.context.kernel.create('photo_sources', {
      'kind': 'amazon',
      'config': {'shareUrl': 'https://www.amazon.com/photos/shared/PaRtYiD1234567890ab.SeCrEtToKeN123'},
      'enabled': true,
    });
    await hub2.context.scheduler.runAndWait('photos');
    expect(await items(party), isEmpty);
    expect((await source(party)).status, startsWith('paused'));
    final asked = thumbs;
    await hub2.context.scheduler.runAndWait('photos');
    expect(thumbs, asked, reason: 'a paused source is left alone until its wait is over');
    expect(await items(family), hasLength(155), reason: 'the other album is untouched');
  });

  test('§7.2 moving a household: export with its blobs, import into another Hub, the moving household takes over', () async {
    final token = await pairDevice('Kitchen', admin: true);
    final dev = TestDevice(hub, token);
    await dev.connect();
    final avatar = utf8.encode('a face photo, uploaded');
    final up = await http.post(u('/api/blobs'), headers: {'authorization': 'Bearer $token', 'content-type': 'image/jpeg'}, body: avatar);
    final sha = (jsonDecode(up.body) as Map<String, Object?>)['sha']! as String;
    await dev.push([
      dev.op('profiles', 'ava', {'name': 'Ava', 'role': 'child', 'avatar_blob': jsonEncode({'sha': sha, 'aspect': 1, 'crop': [0, 0, 1]})}),
      dev.op('list_items', 'milk', {'list_id': Ids.shoppingList, 'text': 'Milk'}),
      dev.op('list_items', 'gone', {'list_id': Ids.shoppingList, 'text': 'Gone'}),
      dev.op('ledger_entries', 'l1', {'profile_id': 'ava', 'currency': 'star', 'delta': 2, 'reason': 'chore'}, kind: OpKind.insertOnly),
    ]);
    await dev.push([dev.op('list_items', 'gone', const {}, kind: OpKind.delete)]);
    await dev.close();
    // A JSON reference keeps its blob through the clean-up.
    expect(await referencedBlobs(hub.db), contains(sha));

    final dir2 = await Directory.systemTemp.createTemp('dearth-hub-test2');
    final other = await DearthHub.start(
      HubConfig(dataDir: dir2.path, secretKey: 'm' * 32, port: 0, host: '127.0.0.1', fakeProviders: true, adminPassword: 'test-admin', jobsEnabled: false, useVips: false),
      inMemory: true,
      timezone: 'Europe/Paris',
    );
    addTearDown(() async {
      await other.stop();
      await dir2.delete(recursive: true);
    });
    Uri o(String path) => Uri.parse('http://127.0.0.1:${other.port}$path');
    expect((await other.db.select(other.db.households).getSingle()).timezone, 'Europe/Paris', reason: 'the built-in Hub passes the device zone');
    await hub.context.kernel.upsert('households', Ids.household, {'name': 'The Moving Family'});
    await other.context.kernel.upsert('list_items', 'milk', {'list_id': Ids.shoppingList, 'text': 'Oat milk'});

    // Exported after the new Hub booted: its defaults are newer, and must still lose.
    final export = jsonDecode((await http.get(u('/api/admin/export?blobs=1'), headers: _admin)).body) as Map<String, Object?>;
    expect([for (final b in export['blobs']! as List) (b as Map)['sha']], [sha]);
    final missing = await http.post(o('/api/admin/blobs/missing'), headers: _admin, body: jsonEncode({'shas': [sha]}));
    expect((jsonDecode(missing.body) as Map)['missing'], [sha]);
    final put = await http.put(o('/api/admin/blobs/$sha?origin=upload'), headers: {..._admin, 'content-type': 'image/jpeg'}, body: avatar);
    expect(put.statusCode, 200, reason: put.body);
    final wrong = await http.put(o('/api/admin/blobs/${'0' * 64}'), headers: {..._admin, 'content-type': 'image/jpeg'}, body: avatar);
    expect(wrong.statusCode, 400, reason: 'the bytes must match the sha');

    final imported = await http.post(o('/api/admin/import'), headers: _admin, body: jsonEncode(export));
    expect(imported.statusCode, 200, reason: imported.body);
    final ava = await (other.db.select(other.db.profiles)..where((p) => p.id.equals('ava'))).getSingle();
    expect(ava.name, 'Ava');
    expect(blobShaOf(ava.avatarBlob), sha);
    final household = await other.db.select(other.db.households).getSingle();
    expect(household.name, 'The Moving Family');
    expect(household.timezone, isNot('Europe/Paris'), reason: 'the moving household’s settings win over the new Hub’s defaults');
    expect((await other.context.kernel.store.readRow('list_items', 'milk'))?['text'], 'Milk');
    expect((await other.context.kernel.store.readRow('list_items', 'gone'))?['deleted'], 1, reason: 'tombstones come along');
    expect(await other.context.kernel.store.readRow('ledger_entries', 'l1'), isNotNull);
    expect(await other.db.select(other.db.devices).get(), isEmpty, reason: 'each Hub registers its own devices');
    expect((await http.get(o('/api/blobs/$sha'))).bodyBytes, avatar);
  });

  test('demo seed endpoint builds a full household', () async {
    await postJson('/api/admin/demo-seed', const <String, Object?>{}, headers: _admin);
    final profiles = await hub.db.select(hub.db.profiles).get();
    expect(profiles.map((p) => p.name), contains('Ava'));
  });
}
