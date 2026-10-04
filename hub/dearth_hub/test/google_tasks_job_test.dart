import 'dart:convert';
import 'dart:io';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_hub/dearth_hub.dart';
import 'package:dearth_integrations/dearth_integrations.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// An in-memory Google Tasks API: task lists, tasks, and what was asked of it.
class FakeGoogleTasks {
  final lists = <String, String>{};
  final tasks = <String, Map<String, Map<String, Object?>>>{};
  final writes = <String>[];
  var _n = 0;

  String _stamp() => DateTime.now().toUtc().toIso8601String();

  String addList(String title) {
    final id = 'L${++_n}';
    lists[id] = title;
    tasks[id] = {};
    return id;
  }

  /// A change made on a phone, in the Google Tasks app.
  Map<String, Object?> put(String list, String title, {String? id, bool completed = false, bool deleted = false, bool hidden = false, String? notes}) {
    final taskId = id ?? 'T${++_n}';
    return tasks[list]![taskId] = {
      'id': taskId,
      'title': title,
      'notes': ?notes,
      'status': completed ? 'completed' : 'needsAction',
      'updated': _stamp(),
      if (deleted) 'deleted': true,
      if (hidden) 'hidden': true,
    };
  }

  Map<String, Object?>? byTitle(String list, String title) => tasks[list]!.values.where((t) => t['title'] == title && t['deleted'] != true).firstOrNull;

  Future<http.Response> handle(http.Request r) async {
    final s = r.url.pathSegments; // tasks/v1/…
    http.Response ok(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    if (s.length == 5 && s[2] == 'users' && s[4] == 'lists') {
      if (r.method == 'GET') return ok({'items': [for (final e in lists.entries) {'id': e.key, 'title': e.value}]});
      final id = addList((jsonDecode(r.body) as Map)['title'] as String);
      writes.add('list ${lists[id]}');
      return ok({'id': id, 'title': lists[id]});
    }
    if (s.length >= 5 && s[2] == 'lists' && s[4] == 'tasks') {
      final list = s[3];
      final all = tasks[list];
      if (all == null) return http.Response('no list', 404);
      if (s.length == 5 && r.method == 'GET') {
        final since = DateTime.tryParse(r.url.queryParameters['updatedMin'] ?? '');
        return ok({
          'items': [
            for (final t in all.values)
              if (since == null || !DateTime.parse(t['updated']! as String).isBefore(since)) t,
          ],
        });
      }
      if (s.length == 5 && r.method == 'POST') {
        final b = jsonDecode(r.body) as Map<String, Object?>;
        final t = put(list, b['title']! as String, completed: b['status'] == 'completed', notes: (b['notes'] as String?)?.isEmpty ?? true ? null : b['notes'] as String?);
        writes.add('insert ${t['title']}');
        return ok(t);
      }
      final id = s[5];
      final existing = all[id];
      if (existing == null) return http.Response('not found', 404);
      if (r.method == 'PATCH') {
        final b = jsonDecode(r.body) as Map<String, Object?>;
        final t = put(list, b['title']! as String, id: id, completed: b['status'] == 'completed', notes: (b['notes'] as String?)?.isEmpty ?? true ? null : b['notes'] as String?);
        writes.add('patch ${t['title']}');
        return ok(t);
      }
      if (r.method == 'DELETE') {
        put(list, existing['title']! as String, id: id, deleted: true);
        writes.add('delete ${existing['title']}');
        return http.Response('', 204);
      }
    }
    return http.Response('no route ${r.method} ${r.url}', 599);
  }
}

/// List sync with Google Tasks on the Hub, end to end against a fake API.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late DearthHub hub;
  late Directory dir;
  late FakeGoogleTasks google;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dearth-tasks-test');
    google = FakeGoogleTasks();
    hub = await DearthHub.start(
      HubConfig(dataDir: dir.path, secretKey: 'k' * 32, port: 0, host: '127.0.0.1', fakeProviders: true, adminPassword: 'test-admin', jobsEnabled: false),
      inMemory: true,
      listen: false,
      fetcher: Fetcher(client: MockClient(google.handle), maxRetries: 1, sleep: (_) async {}),
    );
  });

  tearDown(() async {
    await hub.stop();
    await dir.delete(recursive: true);
  });

  Future<void> connect({required bool tasks}) => hub.context.vault.putJson('${SecretIds.googleAccountPrefix}me@example.com', {
        'email': 'me@example.com',
        'tokens': OAuthTokens(
          accessToken: 'tok',
          refreshToken: 'refresh',
          expiresAtMs: DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
          scope: ['openid', ...GoogleOAuth.calendarScopes, if (tasks) GoogleTasksApi.scope].join(' '),
        ).toJson(),
      });

  Future<List<ListItem>> items() async {
    final db = hub.db;
    return (db.select(db.listItems)..where((t) => t.listId.equals('list-shopping'))).get();
  }

  Future<void> round() => hub.context.scheduler.runAndWait('google-tasks');

  Future<void> later() => Future<void>.delayed(const Duration(milliseconds: 20));

  test('a shopping list syncs both ways with Google Tasks: new, done, renamed and deleted', () async {
    final k = hub.context.kernel;
    await k.upsert('lists', 'list-shopping', {'title': 'Shopping', 'kind': 'shopping', 'sort_key': 'a'});
    await k.upsert('list_items', 'milk', {'list_id': 'list-shopping', 'text': 'Milk', 'sort_key': 'm'});
    await k.upsert('list_items', 'eggs', {'list_id': 'list-shopping', 'text': 'Eggs', 'note': '1 dozen', 'checked': true, 'sort_key': 'n'});
    // The family already keeps a "Shopping" list in Google Tasks.
    final list = google.addList('Shopping');
    google
      ..put(list, 'milk')
      ..put(list, 'Bread');
    await k.upsert('settings', Ids.setting('household', SettingKeys.listsGoogleTasks), {
      'scope': 'household',
      'key': SettingKeys.listsGoogleTasks,
      'value': jsonEncode({'lists': ['list-shopping']}),
    });

    await connect(tasks: false);
    await round();
    expect(google.writes, isEmpty, reason: 'without the Tasks permission nothing happens');
    expect(hub.context.integrations.status['google-tasks']?['ok'], isFalse);

    await connect(tasks: true);
    await round();
    expect(google.lists.values, ['Shopping'], reason: 'the existing list is used, not a copy');
    expect(google.writes, ['insert Eggs'], reason: 'Milk matched the existing task instead of doubling');
    expect(google.byTitle(list, 'Eggs')?['status'], 'completed');
    expect(google.byTitle(list, 'Eggs')?['notes'], '1 dozen');
    final bread = (await items()).firstWhere((i) => i.itemText == 'Bread');
    expect((bread.checked, bread.deleted, bread.category), (false, false, 'bakery'), reason: 'a new task becomes an item, in its aisle');
    expect(hub.context.integrations.status['google-tasks']?['ok'], isTrue);

    // Nothing changed: a quiet round writes nothing on either side.
    google.writes.clear();
    await later();
    await round();
    expect(google.writes, isEmpty);

    // On a phone: Bread is bought and milk is crossed off for good. On a display: Eggs renamed.
    await later();
    google
      ..put(list, 'Bread', id: google.byTitle(list, 'Bread')!['id']! as String, completed: true)
      ..put(list, 'milk', id: google.byTitle(list, 'milk')!['id']! as String, deleted: true);
    await k.upsert('list_items', 'eggs', {'text': 'Free-range eggs'});
    await round();
    final now = {for (final i in await items()) i.itemText: (i.checked, i.deleted)};
    expect(now['Bread'], (true, false));
    expect(now['Milk'], (false, true), reason: 'deleted in Google, deleted here');
    expect(google.writes, ['patch Free-range eggs']);

    // A display deletes an item: its task goes too.
    google.writes.clear();
    await later();
    await k.delete('list_items', 'eggs');
    await round();
    expect(google.writes, ['delete Free-range eggs']);
  });
}
