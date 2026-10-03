import 'dart:convert';

import 'package:meta/meta.dart';

import '../db/database.dart';
import '../time/household_time.dart';
import 'recurrence.dart';

/// Reminder lead times the editor offers for timed events (minutes before).
const List<int> kTimedReminderChoices = [0, 5, 10, 15, 30, 60, 120, 1440];

/// All-day events remind relative to [kAllDayReminderHour] on their first
/// day: the morning of (0), the evening before (14 h earlier, 6 pm) and the
/// day before (24 h earlier).
const List<int> kAllDayReminderChoices = [0, 840, 1440];
const int kAllDayReminderHour = 8;

/// How long after its event starts a missed reminder is still worth showing
/// (a display that just rebooted).
const Duration kReminderGrace = Duration(minutes: 5);

/// The lead times stored on an event (`events.reminders`: a JSON list of
/// minutes before the start). Empty means none.
List<int> decodeReminders(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    final v = jsonDecode(json);
    if (v is! List) return const [];
    return ({for (final x in v) if (x is num && x >= 0) x.round()}.toList()..sort());
  } on FormatException {
    return const [];
  }
}

/// The lead times that apply to [e]: its own, or — for read-only calendars
/// (ICS), whose events can't carry their own — the calendar's default.
/// Writable calendars apply their default when an event is created instead.
List<int> effectiveReminders(Event e, {required bool writable, List<int> calendarDefault = const []}) {
  final own = decodeReminders(e.reminders);
  return own.isNotEmpty || writable ? own : calendarDefault;
}

/// "15 min before", "Morning of", "1 day before".
String describeReminder(int lead, {required bool allDay}) {
  if (allDay) {
    return switch (lead) {
      0 => 'Morning of',
      840 => 'Evening before',
      1440 => 'Day before',
      _ => '${_span(lead)} before',
    };
  }
  return lead == 0 ? 'At start' : '${_span(lead)} before';
}

String _span(int minutes) {
  if (minutes % 1440 == 0) return minutes == 1440 ? '1 day' : '${minutes ~/ 1440} days';
  if (minutes % 60 == 0) return minutes == 60 ? '1 hour' : '${minutes ~/ 60} hours';
  return '$minutes min';
}

/// One reminder of one occurrence.
@immutable
class DueReminder {
  const DueReminder(this.occurrence, this.lead, this.fireMs, this.anchorMs);
  final Occurrence occurrence;

  /// Minutes before [anchorMs].
  final int lead;
  final int fireMs;

  /// The event's start, or the reminder hour on an all-day event's first day.
  final int anchorMs;

  /// Stable across devices and restarts: one firing per instance and lead.
  String get key => '${occurrence.key}@$lead';
}

/// When reminders for [o] anchor: its start, or 8:00 on an all-day event's
/// first day.
int reminderAnchorMs(Occurrence o, HouseholdTime time) =>
    o.allDay && o.startDate != null ? time.msAt(o.startDate!, kAllDayReminderHour) : o.startMs;

/// Reminders due at [nowMs]: their time has come and their event hasn't
/// been under way longer than [kReminderGrace]. When several leads of one
/// occurrence are due (a display that was off), only the latest is
/// returned; [fired] holds keys already shown, and the caller records all
/// of [DueReminders.consumed] so the skipped ones don't show later.
DueReminders dueReminders(
  List<Occurrence> occurrences,
  HouseholdTime time, {
  required int nowMs,
  required Set<String> fired,
  required List<int> Function(Occurrence o) leadsOf,
}) {
  final show = <DueReminder>[];
  final consumed = <String>[];
  for (final o in occurrences) {
    final leads = leadsOf(o);
    if (leads.isEmpty) continue;
    final anchor = reminderAnchorMs(o, time);
    if (nowMs >= anchor + kReminderGrace.inMilliseconds) continue;
    DueReminder? latest;
    for (final lead in leads) {
      final r = DueReminder(o, lead, anchor - lead * 60000, anchor);
      if (r.fireMs > nowMs || fired.contains(r.key)) continue;
      consumed.add(r.key);
      if (latest == null || r.fireMs > latest.fireMs) latest = r;
    }
    if (latest != null) show.add(latest);
  }
  show.sort((a, b) => a.anchorMs.compareTo(b.anchorMs));
  return DueReminders(show, consumed);
}

@immutable
class DueReminders {
  const DueReminders(this.show, this.consumed);
  final List<DueReminder> show;
  final List<String> consumed;
}
