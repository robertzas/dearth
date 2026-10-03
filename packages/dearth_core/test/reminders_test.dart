import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

/// On-display reminders (SPEC FR-CAL-13 reminders field, FR-CAL-20).
void main() {
  final denver = HouseholdTime.named('America/Denver');
  const today = LocalDate(2026, 10, 3);
  int at(int h, [int m = 0, LocalDate d = today]) => denver.msAt(d, h, m);

  Event ev(String id, {String reminders = '[]', bool allDay = false}) => Event(
        id: id,
        syncClock: '{}',
        syncHlc: '',
        syncSeq: 0,
        deleted: false,
        sourceId: 'local',
        title: id,
        startMs: 0,
        endMs: 0,
        allDay: allDay,
        exdates: '[]',
        countdown: false,
        reminders: reminders,
        profileIds: '[]',
        status: 'confirmed',
      );

  Occurrence timed(String id, int startMs, {String reminders = '[15]'}) =>
      Occurrence(event: ev(id, reminders: reminders), startMs: startMs, endMs: startMs + 3600000, allDay: false);

  Occurrence allDay(String id, LocalDate d, {String reminders = '[0]'}) => Occurrence(
        event: ev(id, reminders: reminders, allDay: true),
        startMs: denver.startOfDayMs(d),
        endMs: denver.startOfDayMs(d.addDays(1)),
        allDay: true,
        startDate: d,
        endDate: d.addDays(1),
      );

  List<int> own(Occurrence o) => decodeReminders(o.event.reminders);

  test('stored lead times decode sorted and distinct; junk is none', () {
    expect(decodeReminders('[60, 15, 15, 0]'), [0, 15, 60]);
    expect(decodeReminders('[-1, "x", 5.0]'), [5]);
    expect(decodeReminders('{'), isEmpty);
    expect(decodeReminders(null), isEmpty);
  });

  test('read-only calendars fall back to their default; writable ones keep their own', () {
    expect(effectiveReminders(ev('a'), writable: false, calendarDefault: const [1440]), [1440]);
    expect(effectiveReminders(ev('a', reminders: '[10]'), writable: false, calendarDefault: const [1440]), [10]);
    expect(effectiveReminders(ev('a'), writable: true, calendarDefault: const [1440]), isEmpty);
  });

  test('a reminder fires once its time comes, and only once', () {
    final swim = timed('swim', at(9));
    expect(dueReminders([swim], denver, nowMs: at(8, 44), fired: const {}, leadsOf: own).show, isEmpty);
    final due = dueReminders([swim], denver, nowMs: at(8, 45), fired: const {}, leadsOf: own);
    expect(due.show.single.key, '${swim.key}@15');
    expect(due.consumed, ['${swim.key}@15']);
    expect(dueReminders([swim], denver, nowMs: at(8, 50), fired: {due.consumed.single}, leadsOf: own).show, isEmpty);
  });

  test('a display that was off shows only the latest due lead, and nothing stale', () {
    final swim = timed('swim', at(9), reminders: '[1440, 60, 15]');
    final late = dueReminders([swim], denver, nowMs: at(8, 50), fired: const {}, leadsOf: own);
    expect(late.show.single.lead, 15);
    expect(late.consumed, hasLength(3), reason: 'the skipped leads never show later');
    expect(dueReminders([swim], denver, nowMs: at(9, 4), fired: const {}, leadsOf: own).show.single.lead, 15, reason: 'within the grace');
    expect(dueReminders([swim], denver, nowMs: at(9, 5), fired: const {}, leadsOf: own).show, isEmpty, reason: 'under way too long');
  });

  test('all-day events remind at 8:00: the morning of, the evening before, the day before', () {
    const tomorrow = LocalDate(2026, 10, 4);
    final trip = allDay('trip', tomorrow, reminders: '[0, 840, 1440]');
    expect(reminderAnchorMs(trip, denver), at(8, 0, tomorrow));
    expect(dueReminders([trip], denver, nowMs: at(8), fired: const {}, leadsOf: own).show.single.lead, 1440);
    expect(dueReminders([trip], denver, nowMs: at(18), fired: const {}, leadsOf: own).show.single.lead, 840);
    expect(dueReminders([trip], denver, nowMs: at(8, 0, tomorrow), fired: const {}, leadsOf: own).show.single.lead, 0);
  });

  test('reminder labels read naturally', () {
    expect(describeReminder(0, allDay: false), 'At start');
    expect(describeReminder(15, allDay: false), '15 min before');
    expect(describeReminder(60, allDay: false), '1 hour before');
    expect(describeReminder(120, allDay: false), '2 hours before');
    expect(describeReminder(1440, allDay: false), '1 day before');
    expect(describeReminder(840, allDay: true), 'Evening before');
  });
}
