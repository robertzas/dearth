import 'package:meta/meta.dart';
import 'package:rrule/rrule.dart';
import 'package:timezone/timezone.dart' as tz;

import '../db/database.dart';
import '../time/household_time.dart';
import '../time/local_date.dart';
import '../util/json.dart';

/// One concrete appearance of an event on the calendar (a single event, a
/// recurring instance, or an exception that replaced an instance).
@immutable
class Occurrence {
  const Occurrence({
    required this.event,
    required this.startMs,
    required this.endMs,
    required this.allDay,
    this.startDate,
    this.endDate,
    this.recurring = false,
  });

  final Event event;
  final int startMs;
  final int endMs;
  final bool allDay;

  /// All-day only: first day (inclusive) and end day (exclusive).
  final LocalDate? startDate;
  final LocalDate? endDate;
  final bool recurring;

  /// Stable key for widgets and selection.
  String get key => '${event.id}@$startMs';
  List<String> get profileIds => decodeStringList(event.profileIds);
  int get durationMs => endMs - startMs;

  /// Days this occurrence touches (household-local), inclusive.
  List<LocalDate> daysTouched(HouseholdTime time) {
    if (allDay && startDate != null) {
      final end = endDate ?? startDate!.addDays(1);
      return [for (var d = startDate!; d.isBefore(end); d = d.addDays(1)) d];
    }
    final first = time.dateOfMs(startMs);
    final last = time.dateOfMs(endMs <= startMs ? startMs : endMs - 1);
    return [for (var d = first; !d.isAfter(last); d = d.addDays(1)) d];
  }

  bool get isMultiDay => allDay ? (endDate != null && startDate!.daysUntil(endDate!) > 1) : endMs - startMs >= 24 * 3600 * 1000;
}

/// Expands stored events into occurrences within a time window (SPEC
/// FR-CAL-23). Handles RRULE masters, EXDATEs, cancelled and modified
/// instances (Google's exception model) and all-day events. Recurrence is
/// computed in the event's wall-clock time so DST never shifts "9 am".
class RecurrenceExpander {
  RecurrenceExpander(this.time, {this.maxInstancesPerEvent = 1000});

  final HouseholdTime time;
  final int maxInstancesPerEvent;
  final Map<String, RecurrenceRule?> _ruleCache = {};

  /// Occurrences overlapping [fromMs, toMs), sorted by start then title.
  List<Occurrence> expand(Iterable<Event> events, {required int fromMs, required int toMs}) {
    final masters = <Event>[];
    final exceptionsByParent = <String, List<Event>>{};
    final out = <Occurrence>[];

    for (final e in events) {
      if (e.deleted) continue;
      if (e.recurringParentId != null) {
        exceptionsByParent.putIfAbsent(e.recurringParentId!, () => []).add(e);
      } else if (e.rrule != null && e.rrule!.isNotEmpty) {
        masters.add(e);
      } else if (e.status != 'cancelled') {
        final o = _single(e);
        if (o.startMs < toMs && _effectiveEnd(o) > fromMs) out.add(o);
      }
    }

    for (final m in masters) {
      if (m.status == 'cancelled') continue;
      final exceptions = exceptionsByParent.remove(m.id) ?? const [];
      final overridden = {for (final x in exceptions) if (x.originalStartMs != null) x.originalStartMs!};
      final exdates = decodeJsonList(m.exdates).whereType<num>().map((n) => n.toInt()).toSet();
      for (final o in _instances(m, fromMs: fromMs, toMs: toMs)) {
        if (exdates.contains(o.startMs) || overridden.contains(o.startMs)) continue;
        out.add(o);
      }
      for (final x in exceptions) {
        if (x.status == 'cancelled') continue;
        final o = _single(x, recurring: true);
        if (o.startMs < toMs && _effectiveEnd(o) > fromMs) out.add(o);
      }
    }
    // Orphan exceptions (master outside the loaded set) still render.
    for (final list in exceptionsByParent.values) {
      for (final x in list) {
        if (x.status == 'cancelled') continue;
        final o = _single(x, recurring: true);
        if (o.startMs < toMs && _effectiveEnd(o) > fromMs) out.add(o);
      }
    }

    out.sort(compareOccurrences);
    return out;
  }

  /// Occurrences touching one household-local day.
  List<Occurrence> forDay(Iterable<Event> events, LocalDate day) =>
      expand(events, fromMs: time.startOfDayMs(day), toMs: time.startOfDayMs(day.addDays(1)));

  int _effectiveEnd(Occurrence o) => o.endMs > o.startMs ? o.endMs : o.startMs + 1;

  Occurrence _single(Event e, {bool recurring = false}) {
    if (e.allDay) {
      final s = LocalDate.tryParse(e.startDate) ?? time.dateOfMs(e.startMs);
      final end = LocalDate.tryParse(e.endDate) ?? s.addDays(1);
      return Occurrence(
        event: e,
        startMs: time.startOfDayMs(s),
        endMs: time.startOfDayMs(end.isAfter(s) ? end : s.addDays(1)),
        allDay: true,
        startDate: s,
        endDate: end.isAfter(s) ? end : s.addDays(1),
        recurring: recurring,
      );
    }
    return Occurrence(event: e, startMs: e.startMs, endMs: e.endMs < e.startMs ? e.startMs : e.endMs, allDay: false, recurring: recurring);
  }

  Iterable<Occurrence> _instances(Event m, {required int fromMs, required int toMs}) sync* {
    final loc = locationOrUtc(m.tz ?? time.zoneName);
    final rule = _rule(m.rrule!, loc);
    if (rule == null) {
      yield _single(m);
      return;
    }
    if (m.allDay) {
      final s = LocalDate.tryParse(m.startDate) ?? time.dateOfMs(m.startMs);
      final spanDays = () {
        final e = LocalDate.tryParse(m.endDate);
        return e != null && e.isAfter(s) ? s.daysUntil(e) : 1;
      }();
      final fromDate = time.dateOfMs(fromMs).addDays(-spanDays);
      final toDate = time.dateOfMs(toMs).addDays(1);
      final instances = rule.getInstances(
        start: s.utcMidnight,
        after: fromDate.utcMidnight,
        includeAfter: true,
        before: toDate.utcMidnight,
      );
      var n = 0;
      for (final f in instances) {
        if (++n > maxInstancesPerEvent) break;
        final d = LocalDate(f.year, f.month, f.day);
        final o = Occurrence(
          event: m,
          startMs: time.startOfDayMs(d),
          endMs: time.startOfDayMs(d.addDays(spanDays)),
          allDay: true,
          startDate: d,
          endDate: d.addDays(spanDays),
          recurring: true,
        );
        if (o.startMs < toMs && o.endMs > fromMs) yield o;
      }
      return;
    }
    final duration = (m.endMs - m.startMs).clamp(0, 400 * 24 * 3600 * 1000);
    final start = _floating(tz.TZDateTime.fromMillisecondsSinceEpoch(loc, m.startMs));
    final after = _floating(tz.TZDateTime.fromMillisecondsSinceEpoch(loc, fromMs - duration - 1));
    final before = _floating(tz.TZDateTime.fromMillisecondsSinceEpoch(loc, toMs));
    final instances = rule.getInstances(
      start: start,
      after: after.isBefore(start) ? start : after,
      includeAfter: true,
      before: before,
    );
    var n = 0;
    for (final f in instances) {
      if (++n > maxInstancesPerEvent) break;
      final startMs = tz.TZDateTime(loc, f.year, f.month, f.day, f.hour, f.minute, f.second).millisecondsSinceEpoch;
      if (startMs >= toMs) break;
      if (startMs + (duration == 0 ? 1 : duration) <= fromMs) continue;
      yield Occurrence(event: m, startMs: startMs, endMs: startMs + duration, allDay: false, recurring: true);
    }
  }

  RecurrenceRule? _rule(String raw, tz.Location loc) {
    final key = '${loc.name}|$raw';
    return _ruleCache.putIfAbsent(key, () => parseRrule(raw, loc));
  }

  static DateTime _floating(tz.TZDateTime t) => DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second);
}

/// Parses an RRULE string (with or without the `RRULE:` prefix) into a rule
/// over *floating* wall-clock time. A UTC `UNTIL` is converted to the event's
/// wall clock first so the last instance is neither lost nor duplicated.
RecurrenceRule? parseRrule(String raw, tz.Location loc) {
  var body = raw.trim();
  if (body.isEmpty) return null;
  if (body.toUpperCase().startsWith('RRULE:')) body = body.substring(6);
  final parts = <String>[];
  for (final part in body.split(';')) {
    if (part.isEmpty) continue;
    final eq = part.indexOf('=');
    if (eq < 0) continue;
    final k = part.substring(0, eq).toUpperCase();
    var v = part.substring(eq + 1);
    if (k == 'UNTIL') {
      v = _untilToFloating(v, loc);
    }
    parts.add('$k=$v');
  }
  try {
    return RecurrenceRule.fromString('RRULE:${parts.join(';')}');
  } on Object {
    return null;
  }
}

String _untilToFloating(String v, tz.Location loc) {
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$').firstMatch(v);
  if (m == null) return v;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  if (m[4] == null) {
    // Date-only UNTIL: include the whole day.
    return '${m[1]}${m[2]}${m[3]}T235959Z';
  }
  final h = int.parse(m[4]!), mi = int.parse(m[5]!), s = int.parse(m[6]!);
  if (m[7] == null) return '${m[1]}${m[2]}${m[3]}T${m[4]}${m[5]}${m[6]}Z';
  final local = tz.TZDateTime.from(DateTime.utc(y, mo, d, h, mi, s), loc);
  String p2(int n) => n.toString().padLeft(2, '0');
  return '${local.year}${p2(local.month)}${p2(local.day)}T${p2(local.hour)}${p2(local.minute)}${p2(local.second)}Z';
}

/// Recurrence presets offered by the event and chore editors (FR-CAL-13).
enum RepeatPreset { none, daily, weekdays, weekly, biweekly, monthlyByDay, monthlyByWeekday, yearly, custom }

const _byDayCodes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

/// Builds an RRULE body (no `RRULE:` prefix) for a preset anchored on [anchor].
String? buildRrule(RepeatPreset preset, LocalDate anchor, {Set<int>? weekdays, LocalDate? until, int? count}) {
  String suffix() => [
        if (until != null) 'UNTIL=${until.iso.replaceAll('-', '')}T235959Z',
        if (until == null && count != null) 'COUNT=$count',
      ].map((e) => ';$e').join();
  switch (preset) {
    case RepeatPreset.none:
    case RepeatPreset.custom:
      return null;
    case RepeatPreset.daily:
      return 'FREQ=DAILY${suffix()}';
    case RepeatPreset.weekdays:
      return 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR${suffix()}';
    case RepeatPreset.weekly:
    case RepeatPreset.biweekly:
      final days = (weekdays == null || weekdays.isEmpty) ? {anchor.weekday} : weekdays;
      final byDay = (days.toList()..sort()).map((d) => _byDayCodes[d - 1]).join(',');
      return 'FREQ=WEEKLY${preset == RepeatPreset.biweekly ? ';INTERVAL=2' : ''};BYDAY=$byDay${suffix()}';
    case RepeatPreset.monthlyByDay:
      return 'FREQ=MONTHLY;BYMONTHDAY=${anchor.day}${suffix()}';
    case RepeatPreset.monthlyByWeekday:
      final nth = ((anchor.day - 1) ~/ 7) + 1;
      final isLast = anchor.addDays(7).month != anchor.month;
      return 'FREQ=MONTHLY;BYDAY=${isLast && nth >= 4 ? -1 : nth}${_byDayCodes[anchor.weekday - 1]}${suffix()}';
    case RepeatPreset.yearly:
      return 'FREQ=YEARLY${suffix()}';
  }
}

const _dayNames = {
  'MO': 'Mon', 'TU': 'Tue', 'WE': 'Wed', 'TH': 'Thu', 'FR': 'Fri', 'SA': 'Sat', 'SU': 'Sun', //
};

/// A short human description of common RRULEs ("Every week on Tue, Thu").
String describeRrule(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 'Does not repeat';
  var body = raw.trim();
  if (body.toUpperCase().startsWith('RRULE:')) body = body.substring(6);
  final map = <String, String>{};
  for (final p in body.split(';')) {
    final i = p.indexOf('=');
    if (i > 0) map[p.substring(0, i).toUpperCase()] = p.substring(i + 1).toUpperCase();
  }
  final interval = int.tryParse(map['INTERVAL'] ?? '1') ?? 1;
  final every = interval == 1 ? 'Every' : 'Every $interval';
  String tail() {
    if (map['COUNT'] != null) return ', ${map['COUNT']} times';
    final u = map['UNTIL'];
    if (u != null && u.length >= 8) return ', until ${u.substring(0, 4)}-${u.substring(4, 6)}-${u.substring(6, 8)}';
    return '';
  }

  switch (map['FREQ']) {
    case 'DAILY':
      return '${interval == 1 ? 'Every day' : '$every days'}${tail()}';
    case 'WEEKLY':
      final days = (map['BYDAY'] ?? '').split(',').where((d) => d.isNotEmpty).toList();
      if (days.length == 5 && !days.contains('SA') && !days.contains('SU')) return 'Every weekday${tail()}';
      final names = days.map((d) => _dayNames[d] ?? d).join(', ');
      return '${interval == 1 ? 'Every week' : '$every weeks'}${names.isEmpty ? '' : ' on $names'}${tail()}';
    case 'MONTHLY':
      if (map['BYMONTHDAY'] != null) return '${interval == 1 ? 'Every month' : '$every months'} on day ${map['BYMONTHDAY']}${tail()}';
      final m = RegExp(r'^(-?\d)(\w\w)$').firstMatch(map['BYDAY'] ?? '');
      if (m != null) {
        const ord = {'1': 'first', '2': 'second', '3': 'third', '4': 'fourth', '-1': 'last'};
        return '${interval == 1 ? 'Every month' : '$every months'} on the ${ord[m[1]] ?? m[1]} ${_dayNames[m[2]] ?? m[2]}${tail()}';
      }
      return '${interval == 1 ? 'Every month' : '$every months'}${tail()}';
    case 'YEARLY':
      return '${interval == 1 ? 'Every year' : '$every years'}${tail()}';
    default:
      return 'Custom repeat';
  }
}

/// Calendar order: by start, all-day first, then by title.
int compareOccurrences(Occurrence a, Occurrence b) {
  final c = a.startMs.compareTo(b.startMs);
  if (c != 0) return c;
  if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
  return a.event.title.compareTo(b.event.title);
}
