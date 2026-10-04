import 'package:dearth_core/dearth_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/display_state.dart';
import '../../core/data/calendar.dart';
import '../../core/data/household.dart';
import '../../core/data/household_data.dart';
import '../../shared/recipe_visual.dart';
import '../kids/kids_data.dart';
import 'event_visuals.dart';

/// When dinner goes on a kid's timeline. Meal slots carry no time yet.
const int kDinnerMinute = 18 * 60;

/// One picture on a kid's timeline (SPEC FR-CAL-10): an event, a routine or
/// dinner.
@immutable
class KidStop {
  const KidStop({required this.id, required this.emoji, required this.title, required this.span, this.occurrence, this.routine, this.people = const []});

  /// Stable within a day, for test ids: `event-…`, `routine-…`, `dinner`.
  final String id;
  final String emoji;
  final String title;

  /// Minutes after midnight, household time.
  final TimelineSpan span;
  final Occurrence? occurrence;
  final RoutineToday? routine;
  final List<String> people;

  /// Over by [minute]: past its end, or 30 min after a moment.
  bool doneBy(int minute) => (span.end ?? span.start + 30) <= minute;

  /// Happening at [minute].
  bool runningAt(int minute) => span.start <= minute && !doneBy(minute);
}

/// A kid's day: timed pictures in order, and what the whole day is
/// ("Halloween", "Ava turns 3").
@immutable
class KidDay {
  const KidDay(this.stops, this.allDay);
  final List<KidStop> stops;
  final List<KidStop> allDay;

  static const empty = KidDay([], []);
}

/// [kidId] null: the whole family's day (a household without kids).
final kidDayProvider = Provider.family<KidDay, (String?, LocalDate)>((ref, key) {
  final (kidId, date) = key;
  final time = ref.watch(householdTimeProvider);
  final learned = ref.watch(learnedIconsProvider);
  final occurrences = ref.watch(occurrencesProvider(DayRange(date, 1))).value;
  if (occurrences == null) return KidDay.empty;
  final dayStart = time.startOfDayMs(date), dayEnd = time.startOfDayMs(date.addDays(1));
  int minuteOf(int ms) => ms <= dayStart ? 0 : (ms >= dayEnd ? 24 * 60 : time.minuteOfDay(ms));

  final stops = <KidStop>[];
  final allDay = <KidStop>[];
  for (final o in occurrences) {
    final who = o.profileIds;
    if (kidId != null && who.isNotEmpty && !who.contains(kidId)) continue;
    final stop = KidStop(
      id: 'event-${o.event.id}',
      emoji: eventEmoji(o.event, learned: learned),
      title: o.event.title,
      span: o.allDay ? const TimelineSpan(0) : TimelineSpan(minuteOf(o.startMs), minuteOf(o.endMs)),
      occurrence: o,
      people: who,
    );
    (o.allDay ? allDay : stops).add(stop);
  }

  if (kidId != null) {
    final today = ref.watch(todayProvider);
    final routines = date == today
        ? ref.watch(kidRoutinesTodayProvider(kidId))
        : [
            for (final r in ref.watch(routinesProvider).value ?? const <Routine>[])
              if (_forKid(r, kidId) && isDueOn(r.rrule, LocalDate.tryParse(r.anchorDate) ?? date, date)) RoutineToday(r, decodeSteps(r.steps), null, date, kidId),
          ];
    for (final r in routines) {
      final at = _minuteOf(r.routine.startTime);
      if (at == null) continue; // a routine without a start time has no place on the line
      stops.add(KidStop(id: 'routine-${r.routine.id}', emoji: r.routine.emoji ?? '⭐', title: r.routine.title, span: TimelineSpan(at), routine: r, people: [kidId]));
    }
  }

  final meals = ref.watch(mealsInRangeProvider(DayRange(date, 1))).value ?? const <PlannedMeal>[];
  final dinner = meals.where((m) => m.entry.slot == 'dinner').firstOrNull;
  if (dinner != null) {
    stops.add(KidStop(id: 'dinner', emoji: recipeEmoji(dinner.recipe, dinner.title), title: dinner.title, span: const TimelineSpan(kDinnerMinute)));
  }

  stops.sort((a, b) => a.span.start.compareTo(b.span.start));
  return KidDay(stops, allDay);
});

bool _forKid(Routine r, String kidId) {
  final who = decodeStringList(r.profileIds);
  return who.isEmpty || who.contains(kidId);
}

int? _minuteOf(String? hhmm) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm ?? '');
  return m == null ? null : int.parse(m[1]!) * 60 + int.parse(m[2]!);
}

/// When the day starts and ends for the timeline: the night schedule's end
/// and start, or 7:00 and 20:00 without one.
final kidDayBoundsProvider = Provider<(int wake, int bedtime)>((ref) {
  final night = ref.watch(nightWindowProvider);
  if (night == null) return (7 * 60, 20 * 60);
  final (start, end) = night;
  return (end, start);
});
