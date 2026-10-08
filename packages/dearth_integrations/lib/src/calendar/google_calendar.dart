import 'dart:convert';
import 'dart:math';

import 'package:dearth_core/dearth_core.dart';
import 'package:meta/meta.dart';
import 'package:timezone/timezone.dart' as tz;

import '../http/fetcher.dart';
import 'event_draft.dart';

/// The sync token expired (HTTP 410): do a full resync of that calendar.
class SyncTokenExpired implements Exception {
  @override
  String toString() => 'SyncTokenExpired';
}

/// The event changed remotely since our copy (HTTP 412 on If-Match).
class EtagConflict implements Exception {
  EtagConflict(this.eventId);
  final String eventId;
  @override
  String toString() => 'EtagConflict($eventId)';
}

@immutable
class GoogleCalendarInfo {
  const GoogleCalendarInfo({required this.id, required this.summary, required this.primary, required this.writable, this.colorHex, this.timeZone});
  final String id;
  final String summary;
  final bool primary;
  final bool writable;
  final String? colorHex;
  final String? timeZone;
}

@immutable
class GoogleEventsPage {
  const GoogleEventsPage({required this.events, this.nextPageToken, this.nextSyncToken});
  final List<EventDraft> events;
  final String? nextPageToken;
  final String? nextSyncToken;
}

@immutable
class WatchChannel {
  const WatchChannel({required this.id, required this.resourceId, required this.expirationMs});
  final String id;
  final String resourceId;
  final int expirationMs;
}

/// Google Calendar API v3 (SPEC §13.2). [token] returns a fresh access token
/// (the Hub refreshes it as needed).
class GoogleCalendarApi {
  GoogleCalendarApi(this.fetcher, this.token, {this.defaultTz = 'UTC', Uri? base})
      : base = base ?? Uri.parse('https://www.googleapis.com/calendar/v3');

  final Fetcher fetcher;
  final Future<String> Function() token;
  final String defaultTz;
  final Uri base;
  static const provider = 'google-calendar';

  Future<Map<String, String>> _auth() async => {'Authorization': 'Bearer ${await token()}'};
  Uri _u(String path, [Map<String, String>? q]) => Uri.parse('$base$path').replace(queryParameters: q);
  String _cal(String id) => Uri.encodeComponent(id);

  Future<List<GoogleCalendarInfo>> calendarList() async {
    final out = <GoogleCalendarInfo>[];
    String? page;
    do {
      final j = asObject(
        await fetcher.getJson(provider, _u('/users/me/calendarList', {'maxResults': '250', 'pageToken': ?page}), headers: await _auth()),
        provider,
      );
      for (final c in j.arr('items')) {
        if (c is! Map<String, Object?>) continue;
        final role = c.str('accessRole') ?? 'reader';
        out.add(GoogleCalendarInfo(
          id: c.str('id') ?? '',
          summary: c.str('summaryOverride') ?? c.str('summary') ?? 'Calendar',
          primary: c.boolean('primary') ?? false,
          writable: role == 'owner' || role == 'writer',
          colorHex: c.str('backgroundColor'),
          timeZone: c.str('timeZone'),
        ));
      }
      page = j.str('nextPageToken');
    } while (page != null);
    return out;
  }

  /// One page of events. With [syncToken] only changes are returned
  /// (including cancellations); on 410 throws [SyncTokenExpired].
  Future<GoogleEventsPage> listEvents(String calendarId, {String? syncToken, String? pageToken, int? timeMinMs}) async {
    final q = <String, String>{
      'maxResults': '2500',
      'singleEvents': 'false',
      'pageToken': ?pageToken,
    };
    if (syncToken != null) {
      q['syncToken'] = syncToken;
    } else {
      q['showDeleted'] = 'false';
      if (timeMinMs != null) q['timeMin'] = DateTime.fromMillisecondsSinceEpoch(timeMinMs, isUtc: true).toIso8601String();
    }
    try {
      final j = asObject(await fetcher.getJson(provider, _u('/calendars/${_cal(calendarId)}/events', q), headers: await _auth()), provider);
      return GoogleEventsPage(
        events: [for (final e in j.arr('items')) if (e is Map<String, Object?>) eventFromGoogle(e, defaultTz: defaultTz)],
        nextPageToken: j.str('nextPageToken'),
        nextSyncToken: j.str('nextSyncToken'),
      );
    } on ProviderException catch (e) {
      if (e.status == 410) throw SyncTokenExpired();
      rethrow;
    }
  }

  Future<EventDraft?> get(String calendarId, String eventId) async {
    try {
      final j = await fetcher.getJson(provider, _u('/calendars/${_cal(calendarId)}/events/${Uri.encodeComponent(eventId)}'), headers: await _auth());
      return eventFromGoogle(asObject(j, provider), defaultTz: defaultTz);
    } on ProviderException catch (e) {
      if (e.isNotFound || e.status == 410) return null;
      rethrow;
    }
  }

  Future<EventDraft> insert(String calendarId, Map<String, Object?> body) async {
    final j = await fetcher.postJson(provider, _u('/calendars/${_cal(calendarId)}/events'), headers: await _auth(), body: body);
    return eventFromGoogle(asObject(j, provider), defaultTz: defaultTz);
  }

  Future<EventDraft> patch(String calendarId, String eventId, Map<String, Object?> body, {String? etag}) async {
    try {
      final res = await fetcher.send(
        provider,
        'PATCH',
        _u('/calendars/${_cal(calendarId)}/events/${Uri.encodeComponent(eventId)}'),
        headers: {...await _auth(), 'If-Match': ?etag},
        body: body,
        retry: false,
      );
      return eventFromGoogle(asObject(fetcher.decodeResponse(provider, res), provider), defaultTz: defaultTz);
    } on ProviderException catch (e) {
      if (e.status == 412) throw EtagConflict(eventId);
      rethrow;
    }
  }

  Future<void> delete(String calendarId, String eventId, {String? etag}) async {
    try {
      await fetcher.send(
        provider,
        'DELETE',
        _u('/calendars/${_cal(calendarId)}/events/${Uri.encodeComponent(eventId)}'),
        headers: {...await _auth(), 'If-Match': ?etag},
        retry: false,
      );
    } on ProviderException catch (e) {
      if (e.status == 412) throw EtagConflict(eventId);
      if (e.status == 410 || e.status == 404) return; // already gone
      rethrow;
    }
  }

  /// Push notifications to [address] (the Hub's HTTPS webhook).
  Future<WatchChannel> watch(String calendarId, {required String address, required String channelId, required String channelToken}) async {
    final j = asObject(
      await fetcher.postJson(provider, _u('/calendars/${_cal(calendarId)}/events/watch'), headers: await _auth(), body: {
        'id': channelId,
        'type': 'web_hook',
        'address': address,
        'token': channelToken,
      }),
      provider,
    );
    return WatchChannel(
      id: j.str('id') ?? channelId,
      resourceId: j.str('resourceId') ?? '',
      expirationMs: int.tryParse(j.str('expiration') ?? '') ?? DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch,
    );
  }

  /// A new secondary calendar owned by the signed-in account (FR-CAL-04);
  /// Google adds it to the account's calendar list.
  Future<String> createCalendar(String summary, {required String timeZone, String? description}) async {
    final j = asObject(
      await fetcher.postJson(provider, _u('/calendars'), headers: await _auth(), body: {'summary': summary, 'timeZone': timeZone, 'description': ?description}),
      provider,
    );
    final id = j.str('id');
    if (id == null || id.isEmpty) throw ProviderException(provider, 'Google made no calendar');
    return id;
  }

  /// Shares [calendarId] with [email]; Google emails them a link to add it.
  Future<void> share(String calendarId, String email, {String role = 'writer'}) async {
    await fetcher.postJson(provider, _u('/calendars/${_cal(calendarId)}/acl', {'sendNotifications': 'true'}), headers: await _auth(), body: {
      'role': role,
      'scope': {'type': 'user', 'value': email},
    });
  }

  Future<void> stopChannel(String channelId, String resourceId) async {
    await fetcher.postJson(provider, _u('/channels/stop'), headers: await _auth(), body: {'id': channelId, 'resourceId': resourceId});
  }
}

/// Dearth anchors all-day reminders at [kAllDayReminderHour] on the day,
/// Google at midnight.
const int _allDayAnchorMinutes = kAllDayReminderHour * 60;

/// Google allows five reminders per event.
const int _maxGoogleReminders = 5;

/// Google `reminders` → `events.reminders`: popup reminders as leads,
/// [kCalendarReminders] for `useDefault`, null when the event has none
/// listed (left alone).
String? remindersFromGoogle(Map<String, Object?>? r, {required bool allDay}) {
  if (r == null || r.isEmpty) return null;
  if (r.boolean('useDefault') ?? false) return kCalendarReminders;
  final leads = <int>{
    for (final o in r.arr('overrides').whereType<Map<String, Object?>>())
      if (o.str('method') == 'popup' && o['minutes'] is num)
        // "On the day at 9 am" can't come before Dearth's 8:00 anchor: it
        // becomes "Morning of".
        allDay ? max(0, (o['minutes']! as num).round() + _allDayAnchorMinutes) : max(0, (o['minutes']! as num).round()),
  }.toList()
    ..sort();
  return jsonEncode(leads);
}

/// Reminders Dearth doesn't show (email), to send back untouched.
List<Map<String, Object?>> keptRemindersFromGoogle(Map<String, Object?>? r) => [
      for (final o in (r ?? const {}).arr('overrides').whereType<Map<String, Object?>>())
        if (o.str('method') != 'popup') {'method': o.str('method'), 'minutes': o['minutes']},
    ];

/// `events.reminders` → Google `reminders`. All-day leads before midnight
/// of the day (Dearth's "Morning of") have no Google form and stay on the
/// wall only.
Map<String, Object?> googleReminders(String? stored, {required bool allDay, List<Map<String, Object?>> kept = const []}) {
  if (followsCalendarReminders(stored)) return {'useDefault': true};
  final popups = [
    for (final lead in decodeReminders(stored))
      if (!allDay || lead >= _allDayAnchorMinutes) {'method': 'popup', 'minutes': allDay ? lead - _allDayAnchorMinutes : lead},
  ];
  return {'useDefault': false, 'overrides': [...popups, ...kept].take(_maxGoogleReminders).toList()};
}

/// All-day leads Google can't hold ([googleReminders] leaves them out), so
/// a pull keeps them on the row.
List<int> wallOnlyReminders(String? stored, {required bool allDay}) =>
    allDay ? [for (final lead in decodeReminders(stored)) if (lead < _allDayAnchorMinutes) lead] : const [];

/// The id Google gives one instance of a series: the master's id and the
/// instance's original start (UTC for timed events, the date for all-day).
String googleInstanceId(String masterRemoteId, {required int originalStartMs, String? allDayDate}) {
  if (allDayDate != null) return '${masterRemoteId}_${allDayDate.replaceAll('-', '')}';
  final t = DateTime.fromMillisecondsSinceEpoch(originalStartMs, isUtc: true);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${masterRemoteId}_${t.year}${two(t.month)}${two(t.day)}T${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
}

int? _ms(Object? iso) => iso is String ? DateTime.tryParse(iso)?.millisecondsSinceEpoch : null;

/// Google event JSON → draft. All-day events keep their dates; recurring
/// masters keep RRULE and EXDATE lines (expanded locally).
EventDraft eventFromGoogle(Map<String, Object?> e, {required String defaultTz}) {
  final start = e.obj('start');
  final end = e.obj('end');
  final allDay = start['date'] != null;
  final eventTz = start.str('timeZone') ?? defaultTz;
  final loc = locationOrUtc(eventTz);
  int dateMs(String iso) {
    final d = LocalDate.parse(iso);
    return tz.TZDateTime(loc, d.year, d.month, d.day).millisecondsSinceEpoch;
  }

  final startMs = allDay ? dateMs(start.str('date')!) : (_ms(start['dateTime']) ?? 0);
  final endMs = allDay ? (end.str('date') == null ? startMs + 86400000 : dateMs(end.str('date')!)) : (_ms(end['dateTime']) ?? startMs);

  String? rrule;
  final exdates = <int>[];
  for (final line in e.arr('recurrence').whereType<String>()) {
    if (line.startsWith('RRULE:')) {
      rrule = line.substring(6);
    } else if (line.startsWith('EXDATE')) {
      final colon = line.indexOf(':');
      final params = line.substring(0, colon);
      final tzid = RegExp(r'TZID=([^;:]+)').firstMatch(params)?[1];
      final zone = locationOrUtc(tzid ?? eventTz);
      for (final v in line.substring(colon + 1).split(',')) {
        final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$').firstMatch(v.trim());
        if (m == null) continue;
        final p = [for (var i = 1; i <= 6; i++) int.parse(m[i] ?? '0')];
        exdates.add(m[7] == 'Z'
            ? DateTime.utc(p[0], p[1], p[2], p[3], p[4], p[5]).millisecondsSinceEpoch
            : tz.TZDateTime(zone, p[0], p[1], p[2], p[3], p[4], p[5]).millisecondsSinceEpoch);
      }
    }
  }
  final original = e.obj('originalStartTime');
  final originalMs = original['date'] != null ? dateMs(original.str('date')!) : _ms(original['dateTime']);
  return EventDraft(
    remoteId: e.str('id') ?? '',
    etag: e.str('etag'),
    title: e.str('summary') ?? '(No title)',
    allDay: allDay,
    startMs: startMs,
    endMs: endMs,
    startDate: allDay ? start.str('date') : null,
    endDate: allDay ? end.str('date') : null,
    tz: allDay ? null : eventTz,
    location: e.str('location'),
    notes: e.str('description'),
    rrule: rrule,
    exdates: exdates,
    recurringRemoteId: e.str('recurringEventId'),
    originalStartMs: originalMs,
    status: e.str('status') == 'cancelled' ? 'cancelled' : 'confirmed',
    updatedMs: _ms(e['updated']),
    reminders: e['reminders'] is Map<String, Object?> ? remindersFromGoogle(e.obj('reminders'), allDay: allDay) : null,
    keptReminders: e['reminders'] is Map<String, Object?> ? keptRemindersFromGoogle(e.obj('reminders')) : const [],
  );
}

/// Dearth event row → Google request body (outbound sync). With
/// [withReminders] the body sets the event's reminders too, keeping [kept]
/// (email reminders); without, Google keeps whatever the event has.
Map<String, Object?> googleBodyFromEvent(Event ev, {required String householdTz, bool withReminders = false, List<Map<String, Object?>> kept = const []}) {
  final zone = ev.tz ?? householdTz;
  String iso(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();
  final exdates = decodeJsonList(ev.exdates).whereType<num>().map((n) => n.toInt()).toList();
  return {
    'summary': ev.title,
    'location': ev.location,
    'description': ev.notes,
    'start': ev.allDay ? {'date': ev.startDate} : {'dateTime': iso(ev.startMs), 'timeZone': zone},
    'end': ev.allDay ? {'date': ev.endDate} : {'dateTime': iso(ev.endMs), 'timeZone': zone},
    if (ev.rrule != null && ev.rrule!.isNotEmpty)
      'recurrence': [
        'RRULE:${ev.rrule!.replaceFirst(RegExp('^RRULE:'), '')}',
        if (exdates.isNotEmpty)
          'EXDATE:${exdates.map((ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String().replaceAll(RegExp(r'[-:]'), '').replaceFirst(RegExp(r'\.\d+'), '')).join(',')}',
      ],
    if (withReminders) 'reminders': googleReminders(ev.reminders, allDay: ev.allDay, kept: kept),
  };
}
