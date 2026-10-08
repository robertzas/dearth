import 'dart:convert';
import 'dart:io';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_hub/dearth_hub.dart';
import 'package:dearth_integrations/dearth_integrations.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// An in-memory Google Calendar API: calendars, their sharing, events
/// (series, instance exceptions) and what was asked of it.
class FakeGoogleCalendar {
  final calendars = <String, String>{'primary': 'a@example.com'};
  final acl = <String, List<String>>{};
  final events = <String, Map<String, Map<String, Object?>>>{'primary': {}};
  final writes = <String>[];
  var _n = 0;

  Map<String, Object?> put(String cal, Map<String, Object?> e) {
    final id = e['id'] as String? ?? 'e${++_n}';
    return events[cal]![id] = {
      ...e,
      'id': id,
      'status': e['status'] ?? 'confirmed',
      'etag': '"${++_n}"',
      'updated': DateTime.now().toUtc().add(Duration(milliseconds: _n)).toIso8601String(),
    };
  }

  Map<String, Object?>? bySummary(String cal, String summary) => events[cal]!.values.where((e) => e['summary'] == summary).firstOrNull;

  Future<http.Response> handle(http.Request r) async {
    final s = [for (final p in r.url.pathSegments) Uri.decodeComponent(p)]; // calendar/v3/…
    http.Response ok(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    Map<String, Object?> body() => jsonDecode(r.body) as Map<String, Object?>;
    if (s.length == 3 && s[2] == 'calendars' && r.method == 'POST') {
      final id = 'cal${++_n}@group.calendar.google.com';
      calendars[id] = body()['summary']! as String;
      events[id] = {};
      writes.add('calendar ${calendars[id]}');
      return ok({'id': id, 'summary': calendars[id]});
    }
    if (s.length < 5 || s[2] != 'calendars') return http.Response('no route ${r.method} ${r.url}', 599);
    final cal = s[3];
    if (s[4] == 'acl') {
      final b = body();
      acl.putIfAbsent(cal, () => []).add('${(b['scope']! as Map)['value']} ${b['role']}');
      return ok({'id': 'user:x', 'role': b['role']});
    }
    final all = events[cal];
    if (all == null) return http.Response('no calendar', 404);
    if (s.length == 5 && r.method == 'GET') return ok({'items': all.values.toList(), 'nextSyncToken': 'sync${++_n}'});
    if (s.length == 5 && r.method == 'POST') {
      final e = put(cal, body());
      writes.add('insert ${e['summary']}');
      return ok(e);
    }
    final id = s[5];
    final existing = all[id];
    // An instance of a series: Google knows it before it's an exception.
    final series = existing == null && id.contains('_') ? all[id.substring(0, id.lastIndexOf('_'))] : null;
    if (existing == null && series == null) return http.Response('not found', 404);
    final instance = series == null ? const <String, Object?>{} : {'recurringEventId': series['id'], 'originalStartTime': {'dateTime': id.substring(id.lastIndexOf('_') + 1)}};
    if (r.method == 'GET') return ok(existing!);
    if (r.method == 'PATCH') {
      final e = put(cal, {...?existing, ...instance, ...body(), 'id': id});
      writes.add('patch ${e['summary']}');
      return ok(e);
    }
    if (r.method == 'DELETE') {
      if (existing?['status'] == 'cancelled') return http.Response('gone', 410);
      put(cal, {...?existing, ...instance, 'id': id, 'status': 'cancelled'});
      writes.add('cancel $id');
      return http.Response('', 204);
    }
    return http.Response('no route ${r.method} ${r.url}', 599);
  }
}

/// Google Calendar on the Hub, end to end against a fake API: the shared
/// Family calendar (FR-CAL-04) and reminders both ways (FR-CAL-20).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late DearthHub hub;
  late Directory dir;
  late FakeGoogleCalendar google;
  const phone = DeviceIdentity(deviceId: 'phone', role: 'phone', admin: true);
  final denver = HouseholdTime.named('America/Denver');

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dearth-gcal-test');
    google = FakeGoogleCalendar();
    hub = await DearthHub.start(
      HubConfig(dataDir: dir.path, secretKey: 'k' * 32, port: 0, host: '127.0.0.1', fakeProviders: true, adminPassword: 'test-admin', jobsEnabled: false),
      inMemory: true,
      listen: false,
      fetcher: Fetcher(client: MockClient(google.handle), maxRetries: 1, sleep: (_) async {}),
    );
    await hub.context.kernel.upsert('households', Ids.household, {'timezone': 'America/Denver'});
    await hub.context.vault.putJson('${SecretIds.googleAccountPrefix}a@example.com', {
      'email': 'a@example.com',
      'tokens': OAuthTokens(
        accessToken: 'tok',
        refreshToken: 'refresh',
        expiresAtMs: DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch,
        scope: [...GoogleOAuth.calendarScopes, GoogleOAuth.appCalendarsScope, GoogleOAuth.sharingScope].join(' '),
      ).toJson(),
    });
  });

  tearDown(() async {
    await hub.stop();
    await dir.delete(recursive: true);
  });

  Future<void> round() => hub.context.scheduler.runAndWait('google-calendar');
  Future<Event?> row(String id) => (hub.db.select(hub.db.events)..where((t) => t.id.equals(id))).getSingleOrNull();
  Future<void> fromPhone(String id, Map<String, Object?> fields) async {
    final (_, rejected) = await hub.context.kernel.accept(phone, [hub.context.kernel.mutator.makeOp('events', id, fields)]);
    expect(rejected, isEmpty);
  }

  int at(int day, int h) => denver.msAt(LocalDate(2026, 10, day), h);

  test('FR-CAL-04: the Family calendar is made in Google, shared, made the default, and takes the Hub’s events along', () async {
    final k = hub.context.kernel;
    await k.upsert('calendar_sources', Ids.familyCalendar, {'kind': 'local', 'name': 'Family', 'writable': true, 'is_default': true, 'enabled': true});
    await hub.context.integrations.putSetting(SettingKeys.calendarReminders, {Ids.familyCalendar: [15]});
    Map<String, Object?> ev(String title, int start, {String? rrule, String reminders = '[15]'}) =>
        {'source_id': Ids.familyCalendar, 'title': title, 'start_ms': start, 'end_ms': start + 3600000, 'tz': 'America/Denver', 'rrule': rrule, 'reminders': reminders, 'status': 'confirmed'};
    await k.upsert('events', 'dentist', ev('Dentist', at(14, 15)));
    await k.upsert('events', 'swim', ev('Swim', at(10, 17), rrule: 'FREQ=WEEKLY;COUNT=4'));
    // "This event" edits on the wall: one Swim moved later, one skipped.
    await k.upsert('events', 'swim-late', {...ev('Swim (late)', at(17, 18)), 'recurring_parent_id': 'swim', 'original_start_ms': at(17, 17)});
    await k.upsert('events', 'swim-off', {...ev('Swim', at(24, 17)), 'recurring_parent_id': 'swim', 'original_start_ms': at(24, 17), 'status': 'cancelled'});
    await k.upsert('events', 'trip', {
      'source_id': Ids.familyCalendar, 'title': 'Trip', 'all_day': true, 'start_date': '2026-10-20', 'end_date': '2026-10-22', //
      'start_ms': denver.startOfDayMs(const LocalDate(2026, 10, 20)), 'end_ms': denver.startOfDayMs(const LocalDate(2026, 10, 22)), 'reminders': '[0,840]',
    });

    final made = await hub.context.google.createFamilyCalendar(account: 'a@example.com', share: ['B@example.com', 'a@example.com'], move: true);
    expect(made['shared'], ['b@example.com'], reason: 'not with the account that owns it');
    expect(made['moved'], 5);
    await round();

    final cal = google.calendars.entries.singleWhere((e) => e.value == 'Family').key;
    expect(google.acl[cal], ['b@example.com writer']);
    final source = made['source']! as String;
    final sources = {for (final s in await hub.db.select(hub.db.calendarSources).get()) s.id: s};
    expect((sources[source]!.remoteId, sources[source]!.isDefault, sources[source]!.enabled), (cal, true, true));
    expect((sources[Ids.familyCalendar]!.isDefault, sources[Ids.familyCalendar]!.enabled), (false, false), reason: 'the Hub’s own Family steps aside');
    expect((await hub.context.integrations.setting(SettingKeys.calendarGoogleFamily))['source'], source);
    expect((await hub.context.integrations.setting(SettingKeys.calendarReminders))[source], [15], reason: 'new events keep starting with its reminders');

    // Up in Google: the one-off, the series, its moved and skipped instances.
    final dentist = google.bySummary(cal, 'Dentist')!;
    expect(dentist['reminders'], {'useDefault': false, 'overrides': [{'method': 'popup', 'minutes': 15}]});
    final swim = google.bySummary(cal, 'Swim')!;
    expect(swim['recurrence'], ['RRULE:FREQ=WEEKLY;COUNT=4']);
    final late = google.events[cal]!['${swim['id']}_20261017T230000Z']!;
    expect((late['summary'], late['recurringEventId']), ('Swim (late)', swim['id']));
    expect(google.events[cal]!['${swim['id']}_20261024T230000Z']!['status'], 'cancelled');
    expect(google.bySummary(cal, 'Trip')!['reminders'], {'useDefault': false, 'overrides': [{'method': 'popup', 'minutes': 360}]}, reason: '"Morning of" has no Google form');

    // Back down: the same rows, now with remote ids; nothing doubled or dropped.
    final rows = await (hub.db.select(hub.db.events)..where((t) => t.sourceId.equals(source))).get();
    expect(rows.map((e) => (e.id, e.deleted)).toSet(), {('dentist', false), ('swim', false), ('swim-late', false), ('swim-off', false), ('trip', false)});
    expect(rows.every((e) => e.remoteId != null), isTrue);
    expect(decodeReminders((await row('trip'))!.reminders), [0, 840], reason: 'the wall keeps its morning reminder');

    // Asking again doesn't make a second calendar.
    google.writes.clear();
    expect((await hub.context.google.createFamilyCalendar(account: 'a@example.com'))['source'], source);
    expect(google.writes, isEmpty);
  });

  test('FR-CAL-20: reminders come down from Google and go back up without losing a parent’s own', () async {
    final k = hub.context.kernel;
    final source = stableId('gcal', ['a@example.com', 'primary']);
    await k.upsert('calendar_sources', source, {'kind': 'google', 'account_id': 'a@example.com', 'remote_id': 'primary', 'name': 'Alex', 'writable': true, 'enabled': true});
    String iso(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();
    final practice = google.put('primary', {
      'summary': 'Practice', 'start': {'dateTime': iso(at(12, 16))}, 'end': {'dateTime': iso(at(12, 17))}, 'reminders': {'useDefault': true}, //
    });
    final dinner = google.put('primary', {
      'summary': 'Dinner', 'start': {'dateTime': iso(at(13, 18))}, 'end': {'dateTime': iso(at(13, 19))},
      'reminders': {'useDefault': false, 'overrides': [{'method': 'popup', 'minutes': 10}, {'method': 'email', 'minutes': 60}]},
    });
    await round();
    final practiceId = EventDraft.localId(source, practice['id']! as String), dinnerId = EventDraft.localId(source, dinner['id']! as String);
    expect((await row(practiceId))!.reminders, kCalendarReminders, reason: 'follows the calendar: quiet on the wall until the family sets a default');
    expect(decodeReminders((await row(dinnerId))!.reminders), [10]);

    // A title edit on the wall leaves Google's reminders as they were.
    google.writes.clear();
    await fromPhone(practiceId, {'title': 'Soccer practice'});
    await round();
    expect(google.writes, ['patch Soccer practice']);
    expect(google.events['primary']![practice['id']]!['reminders'], {'useDefault': true});

    // New reminders from the wall replace the popups and keep the email.
    await fromPhone(dinnerId, {'reminders': '[30,60]'});
    await round();
    expect(google.events['primary']![dinner['id']]!['reminders'], {
      'useDefault': false,
      'overrides': [{'method': 'popup', 'minutes': 30}, {'method': 'popup', 'minutes': 60}, {'method': 'email', 'minutes': 60}],
    });
    expect(decodeReminders((await row(dinnerId))!.reminders), [30, 60]);

    // On a phone, Google: back to the default.
    google.put('primary', {...google.events['primary']![dinner['id']]!, 'reminders': {'useDefault': true}});
    await round();
    expect((await row(dinnerId))!.reminders, kCalendarReminders);
  });
}
