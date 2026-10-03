import 'package:dearth_core/dearth_core.dart';
import 'package:flutter/foundation.dart';

/// Setting up chores, routines and rewards (SPEC FR-KID-01/04/06/11/14):
/// schedules in plain words, and the row fields the editors write.

/// How a chore or routine repeats, as the editor offers it.
enum ScheduleKind {
  daily('Every day'),
  weekdays('Weekdays'),
  weekends('Weekends'),
  days('Some days'),

  /// Anything the editor can't express (intervals, monthly…): kept as is.
  custom('Custom');

  const ScheduleKind(this.label);
  final String label;
}

const List<String> kWeekdayCodes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
const List<String> kWeekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// The RRULE for a schedule (daily granularity; ISO weekdays 1–7).
String scheduleRule(ScheduleKind kind, {Set<int> days = const {}, String? custom}) => switch (kind) {
      ScheduleKind.daily => 'FREQ=DAILY',
      ScheduleKind.weekdays => 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR',
      ScheduleKind.weekends => 'FREQ=WEEKLY;BYDAY=SA,SU',
      ScheduleKind.days => days.isEmpty ? 'FREQ=DAILY' : 'FREQ=WEEKLY;BYDAY=${(days.toList()..sort()).map((d) => kWeekdayCodes[d - 1]).join(',')}',
      ScheduleKind.custom => custom ?? 'FREQ=DAILY',
    };

/// What an RRULE means in editor terms.
(ScheduleKind, Set<int>) scheduleOf(String rrule) {
  final parts = {
    for (final p in rrule.toUpperCase().split(';'))
      if (p.contains('=')) p.substring(0, p.indexOf('=')): p.substring(p.indexOf('=') + 1),
  };
  final freq = parts['FREQ'];
  final interval = int.tryParse(parts['INTERVAL'] ?? '1') ?? 1;
  final extra = parts.keys.toSet().difference({'FREQ', 'INTERVAL', 'BYDAY', 'WKST'});
  if (interval != 1 || extra.isNotEmpty) return (ScheduleKind.custom, const {});
  if (freq == 'DAILY' && !parts.containsKey('BYDAY')) return (ScheduleKind.daily, const {});
  if (freq != 'WEEKLY' && freq != 'DAILY') return (ScheduleKind.custom, const {});
  final byday = parts['BYDAY'];
  if (byday == null) return (ScheduleKind.custom, const {});
  final days = <int>{};
  for (final code in byday.split(',')) {
    final i = kWeekdayCodes.indexOf(code.trim());
    if (i < 0) return (ScheduleKind.custom, const {});
    days.add(i + 1);
  }
  if (days.length == 7) return (ScheduleKind.daily, const {});
  if (setEquals(days, const {1, 2, 3, 4, 5})) return (ScheduleKind.weekdays, days);
  if (setEquals(days, const {6, 7})) return (ScheduleKind.weekends, days);
  return (ScheduleKind.days, days);
}

/// "Every day", "Weekdays", "Mon, Thu".
String describeSchedule(String rrule) {
  final (kind, days) = scheduleOf(rrule);
  return kind == ScheduleKind.days ? [for (final d in days.toList()..sort()) kWeekdayShort[d - 1]].join(', ') : kind.label;
}

/// Morning/evening chores sort and show in their part of the day.
const List<(String id, String label)> kTimeWindows = [('any', 'Any time'), ('morning', 'Morning'), ('evening', 'Evening')];

/// "⭐ 1 · 🫙 · sticker"
String describeRewards(Chore c) => [
      if (c.adult) 'family jar' else ...[
        if (c.stars > 0) '⭐ ${c.stars}',
        if (c.jar > 0) '🫙',
        if (c.sticker) 'sticker',
      ],
      if (c.needsApproval) 'needs a grown-up’s OK',
    ].join(' · ');

/// Row fields for a chore (column names; JSON lists encoded by Mutator).
Map<String, Object?> choreFields({
  required String title,
  required String? emoji,
  required List<String> assignees,
  required String rrule,
  required String window,
  required int stars,
  required bool jar,
  required bool sticker,
  required bool needsApproval,
  required bool adult,
  String? voiceLine,
  required String anchorDate,
}) =>
    {
      'title': title.trim(),
      'emoji': emoji,
      'assignees': assignees,
      'rrule': rrule,
      'window': window,
      'stars': adult ? 0 : stars.clamp(0, 10),
      'jar': adult || !jar ? 0 : 1,
      'sticker': !adult && sticker,
      'needs_approval': needsApproval,
      'adult': adult,
      'voice_line': (voiceLine?.trim().isEmpty ?? true) ? null : voiceLine!.trim(),
      'anchor_date': anchorDate,
      'active': true,
      'deleted': false,
    };

/// A library chore for [kidId] (SPEC FR-KID-04).
Map<String, Object?> choreFromTemplate(ChoreTemplate tpl, {required String kidId, required String anchorDate}) => choreFields(
      title: tpl.title,
      emoji: tpl.emoji,
      assignees: [kidId],
      rrule: tpl.rrule,
      window: tpl.window,
      stars: 1,
      jar: true,
      sticker: true,
      needsApproval: false,
      adult: false,
      voiceLine: tpl.voiceLine,
      anchorDate: anchorDate,
    );

/// Library chores a kid of [ageYears] can do, easiest first; ones already
/// on their chart (same title) left out.
List<ChoreTemplate> choreIdeasFor(double? ageYears, {Iterable<String> existingTitles = const []}) {
  final have = {for (final t in existingTitles) t.trim().toLowerCase()};
  return [
    for (final c in kChoreLibrary)
      if ((ageYears == null || c.minAge <= ageYears + 0.5) && !have.contains(c.title.toLowerCase())) c,
  ]..sort((a, b) => a.minAge.compareTo(b.minAge));
}

/// Row fields for a routine.
Map<String, Object?> routineFields({
  required String title,
  required String? emoji,
  required String kind,
  required List<String> profileIds,
  required List<RoutineStep> steps,
  required String rrule,
  String? startTime,
  required String anchorDate,
}) =>
    {
      'title': title.trim(),
      'emoji': emoji,
      'kind': kind,
      'profile_ids': profileIds,
      'steps': [for (final s in steps) s.toJson()],
      'rrule': rrule,
      'start_time': startTime,
      'anchor_date': anchorDate,
      'active': true,
      'deleted': false,
    };

/// Reward kinds (SPEC FR-KID-13/14/15) and the currency each spends.
enum RewardKind {
  store('store', 'Star store', Currency.star),
  surprise('surprise', 'Jar surprise', Currency.jar),
  family('family', 'Family goal', Currency.family);

  const RewardKind(this.id, this.label, this.currency);
  final String id;
  final String label;
  final String currency;

  static RewardKind parse(String? id) => values.firstWhere((k) => k.id == id, orElse: () => store);
}

Map<String, Object?> rewardFields({required String title, required String? emoji, required RewardKind kind, required int cost}) => {
      'title': title.trim(),
      'emoji': emoji,
      'kind': kind.id,
      'currency': kind.currency,
      // Surprises cost the whole jar, not a price.
      'cost': kind == RewardKind.surprise ? 0 : cost.clamp(1, 999),
      'active': true,
      'deleted': false,
    };

/// A kid's age in years on [today] (null without a birthday).
double? ageOn(String? birthday, LocalDate today) {
  final b = LocalDate.tryParse(birthday);
  if (b == null) return null;
  return today.utcMidnight.difference(b.utcMidnight).inDays / 365.25;
}
