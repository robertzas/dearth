import 'package:meta/meta.dart';

import '../time/local_date.dart';

/// Result of parsing a natural-language quick-add line (FR-CAL-12).
@immutable
class QuickAddResult {
  const QuickAddResult({
    required this.title,
    required this.date,
    required this.allDay,
    this.startMinute,
    this.durationMinutes = 60,
    this.profileIds = const [],
    this.endDate,
  });

  final String title;
  final LocalDate date;
  final bool allDay;

  /// Minutes after local midnight (timed events only).
  final int? startMinute;
  final int durationMinutes;
  final List<String> profileIds;

  /// Exclusive end date for multi-day all-day events ("Mon-Wed").
  final LocalDate? endDate;

  @override
  String toString() =>
      'QuickAddResult($title, ${date.iso}, ${allDay ? 'all-day' : '${startMinute! ~/ 60}:${(startMinute! % 60).toString().padLeft(2, '0')} +${durationMinutes}m'}, $profileIds)';
}

const _weekdays = {
  'monday': 1, 'mon': 1, 'tuesday': 2, 'tue': 2, 'tues': 2, 'wednesday': 3, 'wed': 3, //
  'thursday': 4, 'thu': 4, 'thur': 4, 'thurs': 4, 'friday': 5, 'fri': 5, //
  'saturday': 6, 'sat': 6, 'sunday': 7, 'sun': 7,
};
const _months = {
  'january': 1, 'jan': 1, 'february': 2, 'feb': 2, 'march': 3, 'mar': 3, 'april': 4, 'apr': 4, //
  'may': 5, 'june': 6, 'jun': 6, 'july': 7, 'jul': 7, 'august': 8, 'aug': 8, //
  'september': 9, 'sep': 9, 'sept': 9, 'october': 10, 'oct': 10, 'november': 11, 'nov': 11, //
  'december': 12, 'dec': 12,
};
const _dayParts = {'morning': 9 * 60, 'afternoon': 14 * 60, 'evening': 18 * 60, 'tonight': 19 * 60, 'noon': 12 * 60, 'midnight': 0};
const _connectors = {'at', 'on', 'for', 'from', 'with', '@'};

/// Parses lines like "Swim Saturday 9am Ava", "Dentist tue 3:30pm mom 1h",
/// "Grandma visits next Friday", "Soccer 5-6:30pm Ava Dad", "Pizza night
/// tonight". Unrecognized words form the title. No time → all-day.
///
/// [peopleByWord] maps lower-case names/nicknames to profile ids.
QuickAddResult? parseQuickAdd(
  String input, {
  required LocalDate today,
  Map<String, String> peopleByWord = const {},
}) {
  final raw = input.trim().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  if (raw.isEmpty) return null;

  LocalDate? date;
  LocalDate? endDate;
  int? start;
  int? end;
  int? duration;
  final people = <String>[];
  final title = <String>[];

  String norm(String t) => t.toLowerCase().replaceAll(RegExp(r"^[(\[]+|[.,!?;:)\]]+$|'s$"), '');

  for (var i = 0; i < raw.length; i++) {
    final tok = norm(raw[i]);
    final next = i + 1 < raw.length ? norm(raw[i + 1]) : null;

    // People: "Ava", "mom", also "Ava's".
    final person = peopleByWord[tok];
    if (person != null) {
      if (!people.contains(person)) people.add(person);
      continue;
    }

    // Relative dates.
    if (tok == 'today') {
      date = today;
      continue;
    }
    if (tok == 'tomorrow' || tok == 'tmrw') {
      date = today.addDays(1);
      continue;
    }
    if (tok == 'tonight') {
      date ??= today;
      start ??= _dayParts['tonight'];
      continue;
    }
    if ((tok == 'next' || tok == 'this') && next != null && _weekdays.containsKey(next)) {
      date = _nextWeekday(today, _weekdays[next]!, nextWeek: tok == 'next');
      i++;
      continue;
    }
    if (tok == 'in' && next != null && i + 2 < raw.length) {
      final n = int.tryParse(next);
      final unit = norm(raw[i + 2]);
      if (n != null && (unit.startsWith('day') || unit.startsWith('week'))) {
        date = today.addDays(unit.startsWith('week') ? n * 7 : n);
        i += 2;
        continue;
      }
    }
    if (_weekdays.containsKey(tok)) {
      // "mon-wed" style ranges for all-day spans.
      date = _nextWeekday(today, _weekdays[tok]!, nextWeek: false);
      continue;
    }
    final dayRange = RegExp(r'^([a-z]+)-([a-z]+)$').firstMatch(tok);
    if (dayRange != null && _weekdays.containsKey(dayRange[1]) && _weekdays.containsKey(dayRange[2])) {
      date = _nextWeekday(today, _weekdays[dayRange[1]]!, nextWeek: false);
      var e = _nextWeekday(date, _weekdays[dayRange[2]]!, nextWeek: false);
      if (!e.isAfter(date)) e = e.addDays(7);
      endDate = e.addDays(1);
      continue;
    }
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(tok)) {
      date = LocalDate.tryParse(tok) ?? date;
      continue;
    }
    final slash = RegExp(r'^(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?$').firstMatch(tok);
    if (slash != null) {
      final m = int.parse(slash[1]!), d = int.parse(slash[2]!);
      if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
        var y = slash[3] != null ? int.parse(slash[3]!) + (slash[3]!.length == 2 ? 2000 : 0) : today.year;
        var candidate = LocalDate(y, m, d);
        if (slash[3] == null && candidate.isBefore(today)) candidate = LocalDate(++y, m, d);
        date = candidate;
        continue;
      }
    }
    if (_months.containsKey(tok) && next != null) {
      final d = int.tryParse(next.replaceAll(RegExp(r'(st|nd|rd|th)$'), ''));
      if (d != null && d >= 1 && d <= 31) {
        var candidate = LocalDate(today.year, _months[tok]!, d);
        if (candidate.isBefore(today)) candidate = LocalDate(today.year + 1, _months[tok]!, d);
        date = candidate;
        i++;
        continue;
      }
    }

    // Times and time ranges.
    if (_dayParts.containsKey(tok)) {
      start = _dayParts[tok];
      continue;
    }
    if (tok == 'all' && next == 'day') {
      start = null;
      end = null;
      i++;
      continue;
    }
    final range = RegExp(r'^(\d{1,2})(?::(\d{2}))?(am|pm|a|p)?-(\d{1,2})(?::(\d{2}))?(am|pm|a|p)?$').firstMatch(tok);
    if (range != null) {
      final endMer = range[6] ?? range[3];
      final startMer = range[3] ?? endMer;
      final s = _toMinutes(int.parse(range[1]!), int.parse(range[2] ?? '0'), startMer);
      final e = _toMinutes(int.parse(range[4]!), int.parse(range[5] ?? '0'), endMer);
      if (s != null && e != null) {
        start = s;
        // "11-1pm": the end is after the start, so the start must be am.
        end = e > s ? e : e + 12 * 60;
        if (end > 24 * 60) end = e;
        continue;
      }
    }
    final time = RegExp(r'^(\d{1,2})(?::(\d{2}))?(am|pm|a|p)?$').firstMatch(tok);
    final isClockLike = time != null && (time[3] != null || time[2] != null || (i > 0 && norm(raw[i - 1]) == 'at'));
    if (isClockLike) {
      final mer = time[3] ?? ((next == 'am' || next == 'pm') ? next : null);
      final m = _toMinutes(int.parse(time[1]!), int.parse(time[2] ?? '0'), mer);
      if (m != null) {
        start = m;
        if (time[3] == null && (next == 'am' || next == 'pm')) i++;
        continue;
      }
    }

    // Durations: 1h, 90m, 1.5h, "for 2 hours".
    final dur = RegExp(r'^(\d+(?:\.\d+)?)(h|hr|hrs|hour|hours|m|min|mins|minutes)$').firstMatch(tok);
    if (dur != null) {
      final v = double.parse(dur[1]!);
      duration = (dur[2]!.startsWith('h') ? v * 60 : v).round();
      continue;
    }
    final n = double.tryParse(tok);
    if (n != null && next != null && RegExp(r'^(h|hr|hrs|hour|hours|m|min|mins|minutes)$').hasMatch(next)) {
      duration = (next.startsWith('h') ? n * 60 : n).round();
      i++;
      continue;
    }

    // Connector words are dropped only when they glue a date/time phrase.
    if (_connectors.contains(tok) && next != null && _looksTemporal(next, peopleByWord)) continue;

    title.add(raw[i]);
  }

  final text = title.join(' ').trim();
  if (text.isEmpty) return null;
  final day = date ?? today;
  if (start == null) {
    return QuickAddResult(title: text, date: day, allDay: true, profileIds: people, endDate: endDate);
  }
  final minutes = duration ?? (end != null ? end - start : 60);
  return QuickAddResult(
    title: text,
    date: day,
    allDay: false,
    startMinute: start,
    durationMinutes: minutes <= 0 ? 60 : minutes,
    profileIds: people,
  );
}

bool _looksTemporal(String t, Map<String, String> people) =>
    t == 'today' ||
    t == 'tomorrow' ||
    t == 'tonight' ||
    t == 'noon' ||
    t == 'next' ||
    _weekdays.containsKey(t) ||
    _months.containsKey(t) ||
    _dayParts.containsKey(t) ||
    people.containsKey(t) ||
    RegExp(r'^\d').hasMatch(t);

LocalDate _nextWeekday(LocalDate from, int weekday, {required bool nextWeek}) {
  var delta = (weekday - from.weekday) % 7;
  if (nextWeek && delta == 0) delta = 7;
  if (nextWeek && delta < 7 && from.addDays(delta).startOfWeek(1) == from.startOfWeek(1)) delta += 7;
  return from.addDays(delta);
}

int? _toMinutes(int hour, int minute, String? meridiem) {
  if (minute > 59) return null;
  var h = hour;
  final m = meridiem?.startsWith('p') ?? false;
  final a = meridiem?.startsWith('a') ?? false;
  if (m || a) {
    if (h < 1 || h > 12) return null;
    if (m && h < 12) h += 12;
    if (a && h == 12) h = 0;
  } else {
    if (h > 23) return null;
    // Bare "at 5" for family events is more often 5 pm than 5 am.
    if (h >= 1 && h <= 6) h += 12;
  }
  return h * 60 + minute;
}
