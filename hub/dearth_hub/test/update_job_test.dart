import 'dart:convert';
import 'dart:io';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_hub/dearth_hub.dart';
import 'package:dearth_integrations/dearth_integrations.dart' show Fetcher;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// The Hub updates itself through the Watchtower beside it (SPEC FR-ADM-04,
/// §15.3), against a fake GitHub and a fake Watchtower.
void main() {
  late Directory dir;
  late DearthHub hub;
  late String latestTag;
  late List<http.Request> updaterCalls;

  HubConfig config({bool updater = true}) => HubConfig(
        dataDir: dir.path,
        secretKey: 'k' * 32,
        port: 0,
        host: '127.0.0.1',
        adminPassword: 'test-admin',
        jobsEnabled: false,
        updaterUrl: updater ? 'http://updater:8080' : null,
        updaterToken: updater ? 'update-token' : null,
      );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dearth-hub-update');
    latestTag = 'v0.1.97';
    updaterCalls = [];
    final client = MockClient((req) async {
      if (req.url.host == 'api.github.com' && req.url.path == '/repos/robertzas/dearth/releases/latest') {
        return http.Response(jsonEncode({'tag_name': latestTag, 'draft': false}), 200, headers: {'content-type': 'application/json'});
      }
      if (req.url.host == 'updater') {
        updaterCalls.add(req);
        return req.headers['authorization'] == 'Bearer update-token' ? http.Response('', 202) : http.Response('', 401);
      }
      return http.Response('', 404);
    });
    hub = await DearthHub.start(config(), fetcher: Fetcher(client: client, sleep: (_) async {}));
  });

  tearDown(() async {
    await hub.stop();
    await dir.delete(recursive: true);
  });

  HubUpdateJob job(String version, {bool updater = true}) =>
      HubUpdateJob(hub.context.integrations, config(updater: updater), version: version);

  test('a newer release waits for a grown-up by default; Install asks the updater, and the restarted Hub knows it worked', () async {
    final j = job('0.1.96');
    await j.run();
    expect(j.latest, const AppVersion(0, 1, 97));
    expect(j.available, isTrue);
    expect(updaterCalls, isEmpty, reason: 'manual: nothing installs by itself');
    expect((await j.status())['mode'], HubUpdateMode.manual);

    await j.install();
    expect(updaterCalls, hasLength(1));
    expect(updaterCalls.single.method, 'POST');
    expect(updaterCalls.single.url.path, '/v1/update');
    expect(updaterCalls.single.url.queryParameters['async'], 'true');
    expect(j.installing, isTrue);
    j.dispose();

    // Watchtower recreated the container: the new Hub starts on 0.1.97.
    final after = job('0.1.97');
    expect(after.error, isNull);
    await after.run();
    expect(after.available, isFalse);
    expect((await after.status())['version'], '0.1.97');
  });

  test('a Hub that came back on the old version calls the install failed and never retries it by itself', () async {
    await hub.context.integrations.putSetting(SettingKeys.hubUpdates, {'mode': HubUpdateMode.auto});
    final j = job('0.1.96');
    await j.run();
    expect(updaterCalls, hasLength(1), reason: 'auto: installs as soon as it sees it');
    j.dispose();

    final again = job('0.1.96');
    expect(again.error, contains('0.1.97 didn’t install'));
    await again.run();
    expect(updaterCalls, hasLength(1), reason: 'the failed release is not tried again by itself');

    latestTag = 'v0.1.98';
    await again.run();
    expect(updaterCalls, hasLength(2), reason: 'a newer release is');
    again.dispose();
  });

  test('without an updater, or on a development build, it only tells', () async {
    await hub.context.integrations.putSetting(SettingKeys.hubUpdates, {'mode': HubUpdateMode.auto});
    final bare = job('0.1.96', updater: false);
    await bare.run();
    expect(bare.available, isTrue);
    expect((await bare.status())['canInstall'], isFalse);
    expect(bare.install, throwsA(isA<StateError>()));

    final dev = job('0.1.0-dev');
    await dev.run();
    expect(dev.available, isTrue, reason: 'a release can replace it when a grown-up asks');
    expect(updaterCalls, isEmpty, reason: 'but it never updates by itself');
  });

  test('Settings reads the Hub’s update status (admins only)', () async {
    final u = hub.url.replace(path: '/api/admin/update');
    expect((await http.get(u)).statusCode, 401);
    final res = await http.get(u, headers: {'x-dearth-admin': 'test-admin'});
    expect(res.statusCode, 200);
    final body = jsonDecode(res.body) as Map<String, Object?>;
    expect(body['canInstall'], isTrue);
    expect(body['mode'], HubUpdateMode.manual);
    expect(body.keys, containsAll(['version', 'latest', 'available', 'installing', 'error']));
  });
}
