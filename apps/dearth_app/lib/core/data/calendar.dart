import 'dart:convert';

import 'package:dearth_core/dearth_core.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'household.dart';

/// A span of household-local days: [start] inclusive, [days] long.
@immutable
class DayRange {
  const DayRange(this.start, this.days);
  factory DayRange.single(LocalDate d) => DayRange(d, 1);

  final LocalDate start;
  final int days;

  LocalDate get end => start.addDays(days);
  Iterable<LocalDate> get dates => dateRange(start, end);
  bool contains(LocalDate d) => !d.isBefore(start) && d.isBefore(end);

  @override
  bool operator ==(Object other) => other is DayRange && other.start == start && other.days == days;
  @override
  int get hashCode => Object.hash(start, days);
  @override
  String toString() => 'DayRange(${start.iso} +$days)';
}

final calendarSourcesProvider = StreamProvider<List<CalendarSource>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.calendarSources)
        ..where((s) => s.deleted.equals(false))
        ..orderBy([(s) => OrderingTerm.asc(s.sortKey), (s) => OrderingTerm.asc(s.name)]))
      .watch();
});

final calendarSourceMapProvider = Provider<Map<String, CalendarSource>>(
  (ref) => {
    for (final s in ref.watch(calendarSourcesProvider).value ?? const <CalendarSource>[]) s.id: s,
    for (final s in ref.watch(virtualCalendarsProvider)) s.id: s,
  },
);

/// Ids of calendars switched on (null until loaded).
final enabledCalendarIdsProvider = Provider<Set<String>?>((ref) {
  final list = ref.watch(calendarSourcesProvider).value;
  return list == null ? null : {for (final s in [...list, ...ref.watch(virtualCalendarsProvider)]) if (s.enabled) s.id};
});

// ─────────────────────────── Birthdays & holidays ───────────────────────────

/// Read-only calendars computed on each device (FR-CAL-18): birthdays from
/// profiles, and bundled public holidays and family observances. Nothing
/// is stored, so they can't drift out of date or need the Hub.
abstract final class VirtualCalendars {
  static const birthdays = 'virtual:birthdays';
  static const holidays = 'virtual:holidays';
}

@immutable
class VirtualCalendarSettings {
  const VirtualCalendarSettings({required this.birthdays, required this.holidays, required this.country, required this.observances});
  final bool birthdays;
  final bool holidays;

  /// ISO country with bundled rules, or null (holidays unavailable).
  final String? country;
  final bool observances;
}

final virtualCalendarSettingsProvider = Provider<VirtualCalendarSettings>((ref) {
  final v = ref.watch(settingMapProvider(SettingKeys.calendarVirtual));
  final zone = ref.watch(householdTimeProvider).zoneName;
  final country = v['country'] is String ? v['country']! as String : holidayCountryForZone(zone);
  return VirtualCalendarSettings(
    birthdays: v['birthdays'] as bool? ?? true,
    holidays: v['holidays'] as bool? ?? true,
    country: kHolidayCountries.containsKey(country) ? country : null,
    observances: v['observances'] as bool? ?? true,
  );
});

CalendarSource _virtualSource(String id, String name, int color, {required bool enabled}) => CalendarSource(
      id: id,
      syncClock: '{}',
      syncHlc: '',
      syncSeq: 0,
      deleted: false,
      kind: 'virtual',
      name: name,
      color: color,
      defaultProfileIds: '[]',
      writable: false,
      visibleRoles: '[]',
      isDefault: false,
      enabled: enabled,
      sortKey: 'z',
    );

final virtualCalendarsProvider = Provider<List<CalendarSource>>((ref) {
  final s = ref.watch(virtualCalendarSettingsProvider);
  return [
    _virtualSource(VirtualCalendars.birthdays, 'Birthdays', 0xFFE0457B, enabled: s.birthdays),
    if (s.country != null) _virtualSource(VirtualCalendars.holidays, 'Holidays · ${kHolidayCountries[s.country]}', 0xFF2E9E6A, enabled: s.holidays),
  ];
});

Occurrence _virtualDay(String id, String sourceId, String title, String emoji, LocalDate d, HouseholdTime time, {List<String> people = const [], bool countdown = false}) {
  final start = time.startOfDayMs(d);
  final end = time.startOfDayMs(d.addDays(1));
  final e = Event(
    id: id,
    syncClock: '{}',
    syncHlc: '',
    syncSeq: 0,
    deleted: false,
    sourceId: sourceId,
    title: title,
    icon: emoji,
    startMs: start,
    endMs: end,
    allDay: true,
    startDate: d.iso,
    endDate: d.addDays(1).iso,
    exdates: '[]',
    countdown: countdown,
    reminders: '[]',
    profileIds: jsonEncode(people),
    status: 'confirmed',
  );
  return Occurrence(event: e, startMs: start, endMs: end, allDay: true, startDate: d, endDate: d.addDays(1));
}

/// A birthday in [year]; February 29 is celebrated on the 28th otherwise.
LocalDate birthdayIn(LocalDate born, int year) {
  final leapless = born.month == 2 && born.day == 29 && !(year % 4 == 0 && (year % 100 != 0 || year % 400 == 0));
  return LocalDate(year, born.month, leapless ? 28 : born.day);
}

/// Birthdays and holidays touching [range]. Kids' birthdays read "Ava
/// turns 3" and count down, like the holidays kids wait for; grown-ups'
/// ages stay private.
final virtualOccurrencesProvider = Provider.family<List<Occurrence>, DayRange>((ref, range) {
  final s = ref.watch(virtualCalendarSettingsProvider);
  final time = ref.watch(householdTimeProvider);
  final years = {for (final d in [range.start, range.end]) d.year};
  final out = <Occurrence>[];
  if (s.birthdays) {
    for (final p in ref.watch(familyProvider)) {
      final born = LocalDate.tryParse(p.birthday);
      if (born == null) continue;
      for (final y in years) {
        final d = birthdayIn(born, y);
        if (!range.contains(d) || d.isBefore(born)) continue;
        final kid = p.role == ProfileRole.child;
        final title = kid && y > born.year ? '${p.name} turns ${y - born.year}' : (y == born.year ? '${p.name} is born!' : '${p.name}’s birthday');
        out.add(_virtualDay('bday:${p.id}:$y', VirtualCalendars.birthdays, title, '🎂', d, time, people: [p.id], countdown: kid));
      }
    }
  }
  if (s.holidays && s.country != null) {
    for (final y in years) {
      for (final h in holidaysFor(y, s.country!, observances: s.observances)) {
        if (!range.contains(h.date)) continue;
        out.add(_virtualDay('holiday:${s.country}:${h.date.iso}:${_words(h.name).replaceAll(' ', '-')}', VirtualCalendars.holidays, h.name, h.emoji, h.date, time, countdown: h.kidFavorite));
      }
    }
  }
  return out;
});

String _words(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), ' ').trim();

/// Drops virtual days the family already has as a real event: a "Grandma's
/// birthday" event, or a subscribed holiday calendar.
List<Occurrence> withoutDuplicates(List<Occurrence> virtual, List<Occurrence> real, Map<String, Profile> people) {
  if (virtual.isEmpty) return virtual;
  final realByDay = <LocalDate, List<String>>{};
  for (final o in real) {
    if (o.allDay && o.startDate != null) (realByDay[o.startDate!] ??= []).add(_words(o.event.title));
  }
  return [
    for (final v in virtual)
      if (!(realByDay[v.startDate!] ?? const <String>[]).any((t) {
        if (v.event.sourceId == VirtualCalendars.holidays) return t == _words(v.event.title);
        final name = _words(people[v.profileIds.firstOrNull]?.name ?? '');
        return name.isNotEmpty && t.contains(name) && (t.contains('birthday') || t.contains('bday'));
      }))
        v,
  ];
}

/// The calendar new events land in (FR-CAL-02).
final defaultCalendarProvider = Provider<CalendarSource?>((ref) {
  final list = ref.watch(calendarSourcesProvider).value ?? const <CalendarSource>[];
  final writable = list.where((s) => s.writable && s.enabled).toList();
  return writable.where((s) => s.isDefault).firstOrNull ?? writable.firstOrNull;
});

/// Raw rows relevant to an epoch-ms window: recurring masters, exceptions
/// near the window, and single events overlapping it.
final _eventsInWindowProvider = StreamProvider.family<List<Event>, (int, int)>((ref, window) {
  final db = ref.watch(dbProvider);
  final (from, to) = window;
  const day = 86400000;
  return (db.select(db.events)
        ..where(
          (e) =>
              e.deleted.equals(false) &
              ((e.rrule.isNotNull() & e.rrule.equals('').not() & e.recurringParentId.isNull()) |
                  (e.recurringParentId.isNotNull() &
                      ((e.startMs.isSmallerThanValue(to) & e.endMs.isBiggerOrEqualValue(from)) |
                          (e.originalStartMs.isBiggerOrEqualValue(from - day) & e.originalStartMs.isSmallerThanValue(to + day)))) |
                  (e.startMs.isSmallerThanValue(to) & e.endMs.isBiggerOrEqualValue(from))),
        ))
      .watch();
});

/// Expanded occurrences touching [range], from enabled calendars, sorted.
final occurrencesProvider = Provider.family<AsyncValue<List<Occurrence>>, DayRange>((ref, range) {
  final time = ref.watch(householdTimeProvider);
  final from = time.startOfDayMs(range.start);
  final to = time.startOfDayMs(range.end);
  final events = ref.watch(_eventsInWindowProvider((from, to)));
  final enabled = ref.watch(enabledCalendarIdsProvider);
  final virtual = [
    for (final o in ref.watch(virtualOccurrencesProvider(range)))
      if (enabled == null || enabled.contains(o.event.sourceId)) o,
  ];
  final people = virtual.isEmpty ? const <String, Profile>{} : ref.watch(profileMapProvider);
  return events.whenData((list) {
    final visible = enabled == null ? list : list.where((e) => e.sourceId.isEmpty || enabled.contains(e.sourceId));
    final real = RecurrenceExpander(time).expand(visible, fromMs: from, toMs: to);
    if (virtual.isEmpty) return real;
    return [...real, ...withoutDuplicates(virtual, real, people)]..sort(compareOccurrences);
  });
});

/// Occurrences grouped by the days they touch.
Map<LocalDate, List<Occurrence>> groupByDay(List<Occurrence> items, DayRange range, HouseholdTime time) {
  final out = {for (final d in range.dates) d: <Occurrence>[]};
  for (final o in items) {
    for (final d in o.daysTouched(time)) {
      out[d]?.add(o);
    }
  }
  return out;
}

// ──────────────────────────── Profile filter ────────────────────────────────

/// Profile ids the calendar is filtered to on this device (FR-CAL-11).
/// Empty = everyone. Device-local (not synced).
final calendarFilterProvider = StreamProvider<Set<String>>((ref) {
  final db = ref.watch(dbProvider);
  return db.kvWatch('calendar.filter').map((v) => decodeStringList(v).toSet());
});

Future<void> setCalendarFilter(DearthDb db, Set<String> ids) => db.kvSet('calendar.filter', jsonEncode(ids.toList()..sort()));

/// Whether [o] passes the profile [filter]. Unassigned events concern the
/// whole family and always show.
bool passesFilter(Occurrence o, Set<String> filter) {
  if (filter.isEmpty) return true;
  final ids = o.profileIds;
  return ids.isEmpty || ids.any(filter.contains);
}

// ─────────────────────────── Countdowns & up next ───────────────────────────

/// One upcoming flagged occurrence (FR-CAL-17).
@immutable
class Countdown {
  const Countdown(this.occurrence, this.days, this.sleeps);
  final Occurrence occurrence;

  /// Calendar days from today to the start date.
  final int days;

  /// Nights until the day (the kid-friendly count).
  final int sleeps;
}

final _countdownEventsProvider = StreamProvider<List<Event>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.events)..where((e) => e.deleted.equals(false) & e.countdown.equals(true))).watch();
});

/// Next occurrence of each countdown-flagged event within ~13 months.
final countdownsProvider = Provider<List<Countdown>>((ref) {
  final events = ref.watch(_countdownEventsProvider).value ?? const <Event>[];
  final time = ref.watch(householdTimeProvider);
  final today = ref.watch(todayProvider);
  final enabled = ref.watch(enabledCalendarIdsProvider);
  final visible = enabled == null ? events : events.where((e) => e.sourceId.isEmpty || enabled.contains(e.sourceId));
  final real = RecurrenceExpander(time).expand(visible, fromMs: time.startOfDayMs(today), toMs: time.startOfDayMs(today.addDays(400)));
  // Kids' birthdays and the holidays they wait for count down in the last
  // month before them.
  final soon = DayRange(today, 31);
  final virtual = [
    for (final o in ref.watch(virtualOccurrencesProvider(soon)))
      if (o.event.countdown && (enabled == null || enabled.contains(o.event.sourceId))) o,
  ];
  final occ = [...real, ...withoutDuplicates(virtual, real.where((o) => soon.contains(o.startDate ?? time.dateOfMs(o.startMs))).toList(), ref.watch(profileMapProvider))]
    ..sort(compareOccurrences);
  final seen = <String>{};
  final out = <Countdown>[];
  for (final o in occ) {
    if (!seen.add(o.event.id)) continue;
    final start = o.startDate ?? time.dateOfMs(o.startMs);
    if (start.isBefore(today)) continue; // already running
    final days = today.daysUntil(start);
    out.add(Countdown(o, days, days));
  }
  out.sort((a, b) => a.days.compareTo(b.days));
  return out;
});

/// Today plus the next two days, for Up next, Home agenda and briefings.
final soonOccurrencesProvider = Provider<AsyncValue<List<Occurrence>>>((ref) {
  final today = ref.watch(todayProvider);
  return ref.watch(occurrencesProvider(DayRange(today, 3)));
});

/// The next timed occurrence that hasn't ended (FR-CAL-16), and any
/// same-person overlaps with it (conflict warning).
@immutable
class UpNext {
  const UpNext(this.occurrence, this.conflicts);
  final Occurrence occurrence;
  final List<Occurrence> conflicts;
}

final upNextProvider = Provider<UpNext?>((ref) {
  final list = ref.watch(soonOccurrencesProvider).value;
  if (list == null) return null;
  final now = ref.watch(nowMinuteMsProvider);
  final filter = ref.watch(calendarFilterProvider).value ?? const <String>{};
  final timed = [for (final o in list) if (!o.allDay && o.endMs > now && passesFilter(o, filter)) o];
  if (timed.isEmpty) return null;
  final next = timed.first;
  final people = next.profileIds.toSet();
  final conflicts = [
    for (final o in timed.skip(1))
      if (o.startMs < next.endMs && o.endMs > next.startMs && o.profileIds.any(people.contains)) o,
  ];
  return UpNext(next, conflicts);
});

/// Default reminder leads per calendar id (FR-CAL-20): prefilled on new
/// events, and applied to read-only calendars' events.
final calendarRemindersProvider = Provider<Map<String, List<int>>>((ref) {
  final v = ref.watch(settingMapProvider(SettingKeys.calendarReminders));
  return {
    for (final e in v.entries)
      if (e.value is List) e.key: ({for (final x in e.value! as List) if (x is num && x >= 0) x.round()}.toList()..sort()),
  };
});

/// Learned title → emoji overrides (FR-CAL-15).
final learnedIconsProvider = Provider<Map<String, String>>((ref) {
  final v = ref.watch(settingProvider(SettingKeys.learnedIcons)).value;
  if (v is! Map) return const {};
  return {for (final e in v.entries) '${e.key}': '${e.value}'};
});
