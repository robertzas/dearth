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

/// One VEVENT as parsed, with what [_resolve] needs beyond the draft.
class _Built {
  _Built(this.draft, this.rdates, {required this.thisAndFuture});
  EventDraft draft;

  /// RDATE instants (start, optional end from a PERIOD).
  final List<(int, int?)> rdates;

  /// A RECURRENCE-ID;RANGE=THISANDFUTURE override: it changes this
  /// instance and every later one.
  final bool thisAndFuture;
}

/// Parses an iCalendar feed into drafts (SPEC §13.3). Defensive: folded
/// lines, TZID parameters, floating times, DATE values, EXDATE and RDATE
/// lists, RECURRENCE-ID overrides (RANGE=THISANDFUTURE splits the series),
/// DURATION and text escapes.
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

  final out = <_Built>[];
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
  return _resolve(out, defaultLoc);
}

/// Applies what spans VEVENTs: THISANDFUTURE overrides end their series at
/// that instance and start a new one, and RDATEs become events of their own
/// (an event row holds one RRULE, not a list of extra dates). School and club
/// feeds use both; dropping them silently put wrong events on the wall.
List<EventDraft> _resolve(List<_Built> built, tz.Location fallback) {
  final masters = {for (final b in built) if (b.draft.recurringRemoteId == null && b.draft.rrule != null) b.draft.remoteId: b};
  final splits = [for (final b in built) if (b.thisAndFuture && masters.containsKey(b.draft.recurringRemoteId)) b]
    ..sort((a, b) => a.draft.originalStartMs!.compareTo(b.draft.originalStartMs!));
  for (final s in splits) {
    final o = s.draft;
    final from = o.originalStartMs!;
    // Later splits of the same series cut the newest piece.
    final series = masters[o.recurringRemoteId]!;
    final m = series.draft;
    if (m.rrule == null) continue; // an earlier split used up its count
    final delta = o.startMs - from;
    final loc = m.tz == null ? fallback : locationOrUtc(m.tz!);
    final count = int.tryParse(_ruleParts(m.rrule!)['COUNT'] ?? '');
    final before = count == null ? 0 : _instancesBefore(m, from, loc);
    series.draft = _draft(m, rrule: _withEnd(m.rrule!, until: _icsUtc(from - 1000)), exdates: [for (final x in m.exdates) if (x < from) x]);
    final remaining = count == null ? null : count - before;
    s.draft = _draft(
      o,
      rrule: remaining != null && remaining <= 0 ? null : _withEnd(m.rrule!, count: remaining),
      exdates: [for (final x in m.exdates) if (x >= from) x + delta],
      recurringRemoteId: null,
      originalStartMs: null,
    );
    masters[o.recurringRemoteId!] = s;
    // Overrides of later instances name them by their original times.
    for (final b in built) {
      final d = b.draft;
      if (b != s && d.recurringRemoteId == o.recurringRemoteId && d.originalStartMs != null && d.originalStartMs! > from) {
        b.draft = _draft(d, recurringRemoteId: o.remoteId, originalStartMs: d.originalStartMs! + delta);
      }
    }
  }

  final overridden = <String, Set<int>>{};
  for (final b in built) {
    final d = b.draft;
    if (d.recurringRemoteId != null && d.originalStartMs != null) overridden.putIfAbsent(d.recurringRemoteId!, () => {}).add(d.originalStartMs!);
  }
  final out = <EventDraft>[];
  for (final b in built) {
    final d = b.draft;
    out.add(d);
    final skip = {...d.exdates, ...?overridden[d.remoteId], d.startMs};
    for (final (start, end) in b.rdates) {
      if (!skip.add(start)) continue;
      final length = end != null && end > start ? end - start : d.endMs - d.startMs;
      final days = d.allDay ? LocalDate.parse(d.startDate!).daysUntil(LocalDate.parse(d.endDate!)) : 0;
      final day = d.allDay ? tz.TZDateTime.fromMillisecondsSinceEpoch(fallback, start) : null;
      final startDate = day == null ? null : LocalDate(day.year, day.month, day.day);
      out.add(EventDraft(
        remoteId: '${d.remoteId}#rdate:$start',
        title: d.title,
        allDay: d.allDay,
        startMs: start,
        endMs: start + length,
        startDate: startDate?.iso,
        endDate: startDate?.addDays(days < 1 ? 1 : days).iso,
        tz: d.tz,
        location: d.location,
        notes: d.notes,
        status: d.status,
        updatedMs: d.updatedMs,
      ));
    }
  }
  return out;
}

/// [d] with some fields replaced; [_keep] tells "unchanged" apart from null.
EventDraft _draft(
  EventDraft d, {
  Object? rrule = _keep,
  List<int>? exdates,
  Object? recurringRemoteId = _keep,
  Object? originalStartMs = _keep,
}) =>
    EventDraft(
      remoteId: d.remoteId,
      title: d.title,
      allDay: d.allDay,
      startMs: d.startMs,
      endMs: d.endMs,
      startDate: d.startDate,
      endDate: d.endDate,
      tz: d.tz,
      etag: d.etag,
      location: d.location,
      notes: d.notes,
      rrule: identical(rrule, _keep) ? d.rrule : rrule as String?,
      exdates: exdates ?? d.exdates,
      recurringRemoteId: identical(recurringRemoteId, _keep) ? d.recurringRemoteId : recurringRemoteId as String?,
      originalStartMs: identical(originalStartMs, _keep) ? d.originalStartMs : originalStartMs as int?,
      status: d.status,
      updatedMs: d.updatedMs,
      reminders: d.reminders,
      keptReminders: d.keptReminders,
    );

const Object _keep = Object();

Map<String, String> _ruleParts(String rrule) => {
      for (final part in rrule.replaceFirst(RegExp('^RRULE:', caseSensitive: false), '').split(';'))
        if (part.contains('=')) part.substring(0, part.indexOf('=')).toUpperCase(): part.substring(part.indexOf('=') + 1),
    };

/// [rrule] ending at [until] (UTC) or after [count] instances instead of how
/// it ended before.
String _withEnd(String rrule, {String? until, int? count}) => [
      for (final e in _ruleParts(rrule).entries)
        if (e.key != 'COUNT' && e.key != 'UNTIL') '${e.key}=${e.value}',
      if (until != null) 'UNTIL=$until',
      if (count != null) 'COUNT=$count',
    ].join(';');

String _icsUtc(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}${two(t.month)}${two(t.day)}T${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
}

/// How many of [m]'s instances start before [ms].
int _instancesBefore(EventDraft m, int ms, tz.Location loc) {
  final rule = parseRrule(m.rrule!, loc);
  if (rule == null) return 0;
  DateTime floating(int at) {
    final t = tz.TZDateTime.fromMillisecondsSinceEpoch(loc, at);
    return DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second);
  }

  return rule.getInstances(start: floating(m.startMs), before: floating(ms)).take(10000).length;
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

_Built? _build(List<_Prop> props, tz.Location fallback) {
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
  final rdates = <(int, int?)>[];
  for (final p in props.where((p) => p.name == 'RDATE')) {
    for (final v in p.value.split(',')) {
      // VALUE=PERIOD: start/end or start/duration.
      final period = v.split('/');
      final t = _time(period.first, p.params, fallback);
      if (t == null) continue;
      final end = period.length < 2 ? null : (_time(period[1], p.params, fallback)?.$1 ?? (_durationMs(period[1]) == null ? null : t.$1 + _durationMs(period[1])!));
      rdates.add((t.$1, end));
    }
  }
  final recurrenceId = first('RECURRENCE-ID');
  final recurrenceTime = recurrenceId == null ? null : _time(recurrenceId.value, recurrenceId.params, fallback);
  final rrule = first('RRULE')?.value;
  final status = first('STATUS')?.value.trim().toUpperCase() == 'CANCELLED' ? 'cancelled' : 'confirmed';
  final lastMod = first('LAST-MODIFIED') ?? first('DTSTAMP');
  final updated = lastMod == null ? null : _time(lastMod.value, lastMod.params, fallback)?.$1;

  final draft = EventDraft(
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
  return _Built(draft, rdates, thisAndFuture: recurrenceId != null && recurrenceId.params['RANGE']?.toUpperCase() == 'THISANDFUTURE');
}
