import 'package:dearth_core/dearth_core.dart';
import 'package:flutter/foundation.dart';

/// What a recurring edit or delete applies to (FR-CAL-13).
enum EditScope { single, following, all }

/// Editable fields of an event, in household-local terms.
@immutable
class EventDraft {
  const EventDraft({
    required this.title,
    required this.date,
    required this.sourceId,
    this.icon,
    this.allDay = false,
    this.endDate,
    this.startMinute = 9 * 60,
    this.durationMinutes = 60,
    this.rrule,
    this.profileIds = const [],
    this.location,
    this.notes,
    this.countdown = false,
    this.reminders = const [],
    this.followsCalendar = false,
  });

  factory EventDraft.fromOccurrence(Occurrence o, HouseholdTime time, {Event? master}) {
    final e = o.event;
    final start = o.allDay ? o.startDate! : time.dateOfMs(o.startMs);
    return EventDraft(
      title: e.title,
      icon: e.icon,
      date: start,
      sourceId: e.sourceId,
      allDay: o.allDay,
      endDate: o.allDay ? o.endDate : null,
      startMinute: o.allDay ? 9 * 60 : time.minuteOfDay(o.startMs),
      durationMinutes: o.allDay ? 60 : ((o.endMs - o.startMs) / 60000).round().clamp(5, 24 * 60 * 14),
      rrule: (master ?? e).rrule,
      profileIds: o.profileIds,
      location: e.location,
      notes: e.notes,
      countdown: e.countdown,
      reminders: decodeReminders(e.reminders),
      followsCalendar: followsCalendarReminders(e.reminders),
    );
  }

  final String title;
  final String? icon;
  final LocalDate date;
  final String sourceId;
  final bool allDay;

  /// All-day only: exclusive end date (null = one day).
  final LocalDate? endDate;
  final int startMinute;
  final int durationMinutes;
  final String? rrule;
  final List<String> profileIds;
  final String? location;
  final String? notes;
  final bool countdown;

  /// Minutes before the start (FR-CAL-20); empty = no reminder.
  final List<int> reminders;

  /// The event reminds with its calendar's default instead of [reminders]
  /// (a Google event on "use default"), until the reminders are changed.
  final bool followsCalendar;

  EventDraft copyWith({
    String? title,
    String? icon,
    bool clearIcon = false,
    LocalDate? date,
    String? sourceId,
    bool? allDay,
    LocalDate? endDate,
    bool clearEndDate = false,
    int? startMinute,
    int? durationMinutes,
    String? rrule,
    bool clearRrule = false,
    List<String>? profileIds,
    String? location,
    String? notes,
    bool? countdown,
    List<int>? reminders,
    bool? followsCalendar,
  }) =>
      EventDraft(
        title: title ?? this.title,
        icon: clearIcon ? null : (icon ?? this.icon),
        date: date ?? this.date,
        sourceId: sourceId ?? this.sourceId,
        allDay: allDay ?? this.allDay,
        endDate: clearEndDate ? null : (endDate ?? this.endDate),
        startMinute: startMinute ?? this.startMinute,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        rrule: clearRrule ? null : (rrule ?? this.rrule),
        profileIds: profileIds ?? this.profileIds,
        location: location ?? this.location,
        notes: notes ?? this.notes,
        countdown: countdown ?? this.countdown,
        reminders: reminders ?? this.reminders,
        // Picking reminders makes them the event's own.
        followsCalendar: followsCalendar ?? (reminders == null && this.followsCalendar),
      );

  /// Column values for `events` (SPEC §8.2), computed in household time.
  Map<String, Object?> fields(HouseholdTime time, {bool includeRrule = true}) {
    final end = allDay ? (endDate != null && endDate!.isAfter(date) ? endDate! : date.addDays(1)) : null;
    final startMs = allDay ? time.startOfDayMs(date) : time.msAt(date, startMinute ~/ 60, startMinute % 60);
    return {
      'title': title.trim(),
      'icon': icon,
      'all_day': allDay,
      'start_date': allDay ? date.iso : null,
      'end_date': allDay ? end!.iso : null,
      'start_ms': startMs,
      'end_ms': allDay ? time.startOfDayMs(end!) : startMs + durationMinutes * 60000,
      'tz': time.zoneName,
      if (includeRrule) 'rrule': rrule,
      'profile_ids': profileIds,
      'location': (location?.trim().isEmpty ?? true) ? null : location!.trim(),
      'notes': (notes?.trim().isEmpty ?? true) ? null : notes!.trim(),
      'countdown': countdown,
      'reminders': followsCalendar ? kCalendarReminders : ([...reminders]..sort()),
      'source_id': sourceId,
    };
  }
}

/// The default reminders of [d]'s calendar that fit it (timed or all-day),
/// for new events from any path: editor, quick add (FR-CAL-20).
List<int> defaultReminders(Map<String, List<int>> byCalendar, EventDraft d) {
  final choices = d.allDay ? kAllDayReminderChoices : kTimedReminderChoices;
  return [for (final m in byCalendar[d.sourceId] ?? const <int>[]) if (choices.contains(m)) m];
}

/// Deterministic id of the exception row overriding one instance, so two
/// devices editing the same instance converge (SPEC §8.3).
String exceptionId(String masterId, int originalStartMs) => stableId('event_exception', [masterId, originalStartMs]);

typedef MakeOp = Op Function(String table, String id, Map<String, Object?> fields, {OpKind kind});

/// Ops to create a new event.
List<Op> createEventOps(MakeOp op, EventDraft d, HouseholdTime time, {String? id}) =>
    [op('events', id ?? newId(), {...d.fields(time), 'status': 'confirmed', 'deleted': false})];

/// The master row of [o] (itself for single events and masters).
String masterIdOf(Occurrence o) => o.event.recurringParentId ?? o.event.id;

bool isRecurring(Occurrence o) => o.recurring || o.event.recurringParentId != null || (o.event.rrule?.isNotEmpty ?? false);

/// Ops to apply [d] to occurrence [o] with [scope].
///
/// [master] is required for recurring occurrences; [exceptions] are the
/// master's exception rows (cleaned up by "this and following").
List<Op> updateEventOps(
  MakeOp op,
  Occurrence o,
  EventDraft d,
  EditScope scope,
  HouseholdTime time, {
  Event? master,
  List<Event> exceptions = const [],
}) {
  if (!isRecurring(o)) return [op('events', o.event.id, d.fields(time))];
  final m = master ?? o.event;
  switch (scope) {
    case EditScope.single:
      final id = o.event.recurringParentId != null ? o.event.id : exceptionId(m.id, o.startMs);
      return [
        op('events', id, {
          ...d.fields(time, includeRrule: false),
          'rrule': null,
          'recurring_parent_id': m.id,
          'original_start_ms': o.event.originalStartMs ?? o.startMs,
          'status': 'confirmed',
          'deleted': false,
        }),
      ];
    case EditScope.all:
      return _updateSeries(op, o, d, m, time, exceptions);
    case EditScope.following:
      final original = o.event.originalStartMs ?? o.startMs;
      if (_isFirstInstance(m, original, time)) return _updateSeries(op, o, d, m, time, exceptions);
      return [
        op('events', m.id, {'rrule': rruleWithUntil(m.rrule ?? '', untilBefore(original, m.allDay, time))}),
        for (final x in exceptions)
          if ((x.originalStartMs ?? 0) >= original) op('events', x.id, const {}, kind: OpKind.delete),
        ...createEventOps(op, d, time),
      ];
  }
}

/// Ops to delete occurrence [o] with [scope].
List<Op> deleteEventOps(MakeOp op, Occurrence o, EditScope scope, HouseholdTime time, {Event? master, List<Event> exceptions = const []}) {
  if (!isRecurring(o)) return [op('events', o.event.id, const {}, kind: OpKind.delete)];
  final m = master ?? o.event;
  switch (scope) {
    case EditScope.single:
      final id = o.event.recurringParentId != null ? o.event.id : exceptionId(m.id, o.startMs);
      // A cancelled exception hides the instance and merges cleanly.
      return [
        op('events', id, {
          'recurring_parent_id': m.id,
          'original_start_ms': o.event.originalStartMs ?? o.startMs,
          'source_id': m.sourceId,
          'title': o.event.title,
          'start_ms': o.startMs,
          'end_ms': o.endMs,
          'status': 'cancelled',
        }),
      ];
    case EditScope.following:
      final original = o.event.originalStartMs ?? o.startMs;
      if (_isFirstInstance(m, original, time)) return _deleteSeries(op, m, exceptions);
      return [
        op('events', m.id, {'rrule': rruleWithUntil(m.rrule ?? '', untilBefore(original, m.allDay, time))}),
        for (final x in exceptions)
          if ((x.originalStartMs ?? 0) >= original) op('events', x.id, const {}, kind: OpKind.delete),
      ];
    case EditScope.all:
      return _deleteSeries(op, m, exceptions);
  }
}

/// "All events": patch the master. If the series moved in time, existing
/// instance overrides no longer line up with any instance, so drop them.
List<Op> _updateSeries(MakeOp op, Occurrence o, EventDraft d, Event m, HouseholdTime time, List<Event> exceptions) {
  final f = _shiftedSeriesFields(o, d, m, time);
  final moved = f['start_ms'] != m.startMs || f['start_date'] != m.startDate;
  return [
    op('events', m.id, f),
    if (moved)
      for (final x in exceptions) op('events', x.id, const {}, kind: OpKind.delete),
  ];
}

List<Op> _deleteSeries(MakeOp op, Event m, List<Event> exceptions) => [
      op('events', m.id, const {}, kind: OpKind.delete),
      for (final x in exceptions) op('events', x.id, const {}, kind: OpKind.delete),
    ];

bool _isFirstInstance(Event m, int originalStartMs, HouseholdTime time) =>
    m.allDay ? time.dateOfMs(originalStartMs) == (LocalDate.tryParse(m.startDate) ?? time.dateOfMs(m.startMs)) : originalStartMs <= m.startMs;

/// Series fields for "all events": keeps the series anchored, shifted by
/// however far this occurrence was moved.
Map<String, Object?> _shiftedSeriesFields(Occurrence o, EventDraft d, Event m, HouseholdTime time) {
  final f = d.fields(time);
  if (d.allDay) {
    final shiftDays = (o.startDate ?? time.dateOfMs(o.startMs)).daysUntil(d.date);
    final masterStart = (LocalDate.tryParse(m.startDate) ?? time.dateOfMs(m.startMs)).addDays(shiftDays);
    final span = d.endDate != null && d.endDate!.isAfter(d.date) ? d.date.daysUntil(d.endDate!) : 1;
    return {
      ...f,
      'start_date': masterStart.iso,
      'end_date': masterStart.addDays(span).iso,
      'start_ms': time.startOfDayMs(masterStart),
      'end_ms': time.startOfDayMs(masterStart.addDays(span)),
    };
  }
  final newStart = f['start_ms']! as int;
  final shift = newStart - o.startMs;
  final masterStart = m.startMs + shift;
  return {...f, 'start_ms': masterStart, 'end_ms': masterStart + d.durationMinutes * 60000};
}

/// UNTIL value ending a series just before the instance at [originalStartMs].
String untilBefore(int originalStartMs, bool allDay, HouseholdTime time) {
  if (allDay) return time.dateOfMs(originalStartMs).addDays(-1).iso.replaceAll('-', '');
  final t = DateTime.fromMillisecondsSinceEpoch(originalStartMs - 1000, isUtc: true);
  String p(int n) => n.toString().padLeft(2, '0');
  return '${t.year}${p(t.month)}${p(t.day)}T${p(t.hour)}${p(t.minute)}${p(t.second)}Z';
}

/// Sets UNTIL on an RRULE (dropping COUNT, which can't coexist with it).
String rruleWithUntil(String rrule, String until) {
  var body = rrule.trim();
  final prefixed = body.toUpperCase().startsWith('RRULE:');
  if (prefixed) body = body.substring(6);
  final parts = [
    for (final p in body.split(';'))
      if (p.isNotEmpty && !p.toUpperCase().startsWith('UNTIL=') && !p.toUpperCase().startsWith('COUNT=')) p,
    'UNTIL=$until',
  ];
  return '${prefixed ? 'RRULE:' : ''}${parts.join(';')}';
}
