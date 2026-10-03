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
  (ref) => {for (final s in ref.watch(calendarSourcesProvider).value ?? const <CalendarSource>[]) s.id: s},
);

/// Ids of calendars switched on (null until loaded).
final enabledCalendarIdsProvider = Provider<Set<String>?>((ref) {
  final list = ref.watch(calendarSourcesProvider).value;
  return list == null ? null : {for (final s in list) if (s.enabled) s.id};
});

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
  return events.whenData((list) {
    final visible = enabled == null ? list : list.where((e) => e.sourceId.isEmpty || enabled.contains(e.sourceId));
    return RecurrenceExpander(time).expand(visible, fromMs: from, toMs: to);
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
  if (events.isEmpty) return const [];
  final time = ref.watch(householdTimeProvider);
  final today = ref.watch(todayProvider);
  final enabled = ref.watch(enabledCalendarIdsProvider);
  final visible = enabled == null ? events : events.where((e) => e.sourceId.isEmpty || enabled.contains(e.sourceId));
  final occ = RecurrenceExpander(time).expand(visible, fromMs: time.startOfDayMs(today), toMs: time.startOfDayMs(today.addDays(400)));
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

/// Learned title → emoji overrides (FR-CAL-15).
final learnedIconsProvider = Provider<Map<String, String>>((ref) {
  final v = ref.watch(settingProvider(SettingKeys.learnedIcons)).value;
  if (v is! Map) return const {};
  return {for (final e in v.entries) '${e.key}': '${e.value}'};
});
