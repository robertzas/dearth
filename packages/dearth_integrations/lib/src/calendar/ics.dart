import 'package:dearth_core/dearth_core.dart';
import 'package:timezone/timezone.dart' as tz;

import 'event_draft.dart';

/// Windows zone names seen in Outlook/Exchange ICS exports.
const Map<String, String> _windowsZones = {
  'Eastern Standard Time': 'America/New_York',
  'Central Standard Time': 'America/Chicago',
  'Mountain Standard Time': 'America/Denver',
  'US Mountain Standard Time': 'America/Phoenix',
  'Pacific Standard Time': 'America/Los_Angeles',
  'Alaskan Standard Time': 'America/Anchorage',
  'Hawaiian Standard Time': 'Pacific/Honolulu',
  'GMT Standard Time': 'Europe/London',
  'W. Europe Standard Time': 'Europe/Berlin',
  'Romance Standard Time': 'Europe/Paris',
  'Central Europe Standard Time': 'Europe/Budapest',
  'AUS Eastern Standard Time': 'Australia/Sydney',
  'UTC': 'UTC',
};

class _Prop {
  _Prop(this.name, this.params, this.value);
  final String name;
  final Map<String, String> params;
  final String value;
}

/// Parses an iCalendar feed into drafts (SPEC §13.3). Defensive: folded
/// lines, TZID parameters, floating times, DATE values, EXDATE lists,
/// RECURRENCE-ID overrides, DURATION and text escapes.
List<EventDraft> parseIcs(String text, {required String defaultTz}) {
  ensureTimeZones();
  final defaultLoc = locationOrUtc(defaultTz);
  final lines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final unfolded = <String>[];
  for (final l in lines) {
    if ((l.startsWith(' ') || l.startsWith('\t')) && unfolded.isNotEmpty) {
      unfolded[unfolded.length - 1] += l.substring(1);
    } else if (l.isNotEmpty) {
      unfolded.add(l);
    }
  }

  final out = <EventDraft>[];
  List<_Prop>? current;
  var depth = 0;
  for (final line in unfolded) {
    if (line == 'BEGIN:VEVENT') {
      current = [];
      depth = 0;
      continue;
    }
    if (current == null) continue;
    if (line.startsWith('BEGIN:')) depth++;
    if (line.startsWith('END:') && line != 'END:VEVENT') {
      depth--;
      continue;
    }
    if (line == 'END:VEVENT') {
      final d = _build(current, defaultLoc);
      if (d != null) out.add(d);
      current = null;
      continue;
    }
    if (depth > 0) continue; // nested VALARM etc.
    final p = _parseLine(line);
    if (p != null) current.add(p);
  }
  return out;
}

_Prop? _parseLine(String line) {
  // name *(;param=value) : value — colons inside quoted params are allowed.
  var inQuotes = false;
  var colon = -1;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') inQuotes = !inQuotes;
    if (c == ':' && !inQuotes) {
      colon = i;
      break;
    }
  }
  if (colon < 0) return null;
  final head = line.substring(0, colon).split(';');
  final params = <String, String>{};
  for (final p in head.skip(1)) {
    final eq = p.indexOf('=');
    if (eq > 0) params[p.substring(0, eq).toUpperCase()] = p.substring(eq + 1).replaceAll('"', '');
  }
  return _Prop(head.first.toUpperCase(), params, line.substring(colon + 1));
}

String _unescape(String v) => v.replaceAllMapped(RegExp(r'\\([\\;,nN])'), (m) => switch (m[1]) {
      'n' || 'N' => '\n',
      final other => other!,
    });

tz.Location _zone(Map<String, String> params, tz.Location fallback) {
  final id = params['TZID'];
  if (id == null) return fallback;
  final mapped = _windowsZones[id] ?? id.replaceFirst(RegExp(r'^/'), '');
  final loc = locationOrUtc(mapped);
  return loc.name == 'UTC' && mapped != 'UTC' && mapped != 'Etc/UTC' ? fallback : loc;
}

/// Returns (ms, isDate, localDate) for a DATE or DATE-TIME value.
(int, bool, LocalDate?)? _time(String value, Map<String, String> params, tz.Location fallback) {
  final v = value.trim();
  final dateOnly = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(v);
  if (dateOnly != null || params['VALUE'] == 'DATE') {
    final m = dateOnly ?? RegExp(r'^(\d{4})(\d{2})(\d{2})').firstMatch(v);
    if (m == null) return null;
    final d = LocalDate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    return (tz.TZDateTime(fallback, d.year, d.month, d.day).millisecondsSinceEpoch, true, d);
  }
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?(Z)?$').firstMatch(v);
  if (m == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.parse(m[i] ?? '0')];
  if (m[7] == 'Z') {
    return (DateTime.utc(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]).millisecondsSinceEpoch, false, null);
  }
  final loc = _zone(params, fallback);
  return (tz.TZDateTime(loc, parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]).millisecondsSinceEpoch, false, null);
}

int? _durationMs(String v) {
  final m = RegExp(r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$').firstMatch(v.trim());
  if (m == null) return null;
  int n(int i) => int.parse(m[i] ?? '0');
  final ms = ((n(2) * 7 + n(3)) * 86400 + n(4) * 3600 + n(5) * 60 + n(6)) * 1000;
  return m[1] == '-' ? -ms : ms;
}

EventDraft? _build(List<_Prop> props, tz.Location fallback) {
  _Prop? first(String name) => props.where((p) => p.name == name).firstOrNull;
  final uid = first('UID')?.value.trim();
  final dtStart = first('DTSTART');
  if (uid == null || uid.isEmpty || dtStart == null) return null;
  final start = _time(dtStart.value, dtStart.params, fallback);
  if (start == null) return null;
  final allDay = start.$2;
  final zone = allDay ? null : _zone(dtStart.params, fallback);

  int endMs;
  LocalDate? endDate;
  final dtEnd = first('DTEND');
  final duration = first('DURATION');
  final endTime = dtEnd == null ? null : _time(dtEnd.value, dtEnd.params, fallback);
  final durationMs = duration == null ? null : _durationMs(duration.value);
  if (endTime != null) {
    endMs = endTime.$1;
    endDate = endTime.$3;
  } else if (durationMs != null) {
    endMs = start.$1 + durationMs;
    if (allDay) endDate = start.$3!.addDays((durationMs / 86400000).ceil());
  } else {
    endMs = allDay ? start.$1 + 86400000 : start.$1;
    if (allDay) endDate = start.$3!.addDays(1);
  }

  final exdates = <int>[];
  for (final p in props.where((p) => p.name == 'EXDATE')) {
    for (final v in p.value.split(',')) {
      final t = _time(v, p.params, fallback);
      if (t != null) exdates.add(t.$1);
    }
  }
  final recurrenceId = first('RECURRENCE-ID');
  final recurrenceTime = recurrenceId == null ? null : _time(recurrenceId.value, recurrenceId.params, fallback);
  final rrule = first('RRULE')?.value;
  final status = first('STATUS')?.value.trim().toUpperCase() == 'CANCELLED' ? 'cancelled' : 'confirmed';
  final lastMod = first('LAST-MODIFIED') ?? first('DTSTAMP');
  final updated = lastMod == null ? null : _time(lastMod.value, lastMod.params, fallback)?.$1;

  return EventDraft(
    remoteId: recurrenceId == null ? uid : '$uid#${recurrenceId.value.trim()}',
    title: _unescape(first('SUMMARY')?.value ?? '(No title)').trim(),
    allDay: allDay,
    startMs: start.$1,
    endMs: endMs < start.$1 ? start.$1 : endMs,
    startDate: allDay ? start.$3!.iso : null,
    endDate: allDay ? (endDate ?? start.$3!.addDays(1)).iso : null,
    tz: zone?.name,
    location: first('LOCATION') == null ? null : _unescape(first('LOCATION')!.value),
    notes: first('DESCRIPTION') == null ? null : _unescape(first('DESCRIPTION')!.value),
    rrule: recurrenceId == null && rrule != null && rrule.isNotEmpty ? rrule : null,
    exdates: exdates,
    recurringRemoteId: recurrenceId == null ? null : uid,
    originalStartMs: recurrenceTime?.$1,
    status: status,
    updatedMs: updated,
  );
}
