import 'package:dearth_app/features/calendar/event_ops.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// FR-CAL-13 recurring edits ("this event / this and following / all") and
/// deletes, verified through real recurrence expansion.
void main() {
  late DearthDb db;
  late Mutator m;
  late HouseholdTime time;
  const masterId = 'swim';
  const monday = LocalDate(2026, 10, 5);

  MakeOp op() => (table, id, fields, {kind = OpKind.upsert}) => m.makeOp(table, id, fields, kind: kind);

  Future<List<Event>> events() => db.select(db.events).get();

  Future<List<Occurrence>> week(LocalDate start, [int days = 21]) async =>
      RecurrenceExpander(time).expand(await events(), fromMs: time.startOfDayMs(start), toMs: time.startOfDayMs(start.addDays(days)));

  Future<Event> master() async => (await events()).firstWhere((e) => e.id == masterId);

  setUp(() async {
    ensureTimeZones();
    db = DearthDb(NativeDatabase.memory());
    m = Mutator(store: SyncStore(db), clock: HlcClock('test'), sink: (_) async {});
    time = HouseholdTime.named('America/Denver', clock: () => DateTime.utc(2026, 10, 3, 15));
    // Weekly swim on Mondays 9:00–9:45, starting Oct 5.
    const d = EventDraft(title: 'Swim', date: monday, sourceId: 'cal', durationMinutes: 45, rrule: 'FREQ=WEEKLY;BYDAY=MO');
    await m.commit(createEventOps(op(), d, time, id: masterId));
  });

  tearDown(() => db.close());

  test('the series expands weekly', () async {
    final occ = await week(monday);
    expect(occ.map((o) => time.dateOfMs(o.startMs)), [monday, monday.addDays(7), monday.addDays(14)]);
  });

  test('FR-CAL-13 this event: one instance changes, the rest stay', () async {
    final second = (await week(monday))[1];
    final d = EventDraft.fromOccurrence(second, time, master: await master()).copyWith(title: 'Swim (pool closed?)', startMinute: 10 * 60);
    await m.commit(updateEventOps(op(), second, d, EditScope.single, time, master: await master()));
    final occ = await week(monday);
    expect(occ.map((o) => o.event.title), ['Swim', 'Swim (pool closed?)', 'Swim']);
    expect(time.minuteOfDay(occ[1].startMs), 10 * 60);
    expect(occ[1].event.id, exceptionId(masterId, second.startMs), reason: 'deterministic exception id');
  });

  test('FR-CAL-13 editing the same instance twice converges on one row', () async {
    final second = (await week(monday))[1];
    for (final title in ['A', 'B']) {
      final current = (await week(monday))[1];
      final d = EventDraft.fromOccurrence(current, time, master: await master()).copyWith(title: title);
      await m.commit(updateEventOps(op(), current, d, EditScope.single, time, master: await master()));
    }
    final rows = (await events()).where((e) => e.recurringParentId == masterId);
    expect(rows, hasLength(1));
    expect(rows.single.originalStartMs, second.startMs);
    expect((await week(monday))[1].event.title, 'B');
  });

  test('FR-CAL-13 this and following: the series splits at the instance', () async {
    final second = (await week(monday))[1];
    final d = EventDraft.fromOccurrence(second, time, master: await master()).copyWith(title: 'Swim (new coach)');
    await m.commit(updateEventOps(op(), second, d, EditScope.following, time, master: await master()));
    final occ = await week(monday);
    expect(occ.map((o) => o.event.title), ['Swim', 'Swim (new coach)', 'Swim (new coach)']);
    expect((await master()).rrule, contains('UNTIL='));
  });

  test('FR-CAL-13 all events: moving the series shifts every instance', () async {
    final first = (await week(monday)).first;
    final d = EventDraft.fromOccurrence(first, time, master: await master()).copyWith(startMinute: 16 * 60);
    await m.commit(updateEventOps(op(), first, d, EditScope.all, time, master: await master()));
    final occ = await week(monday);
    expect(occ, hasLength(3));
    expect(occ.every((o) => time.minuteOfDay(o.startMs) == 16 * 60), isTrue);
  });

  test('FR-CAL-13 delete this event hides only that instance', () async {
    final second = (await week(monday))[1];
    await m.commit(deleteEventOps(op(), second, EditScope.single, time, master: await master()));
    final occ = await week(monday);
    expect(occ.map((o) => time.dateOfMs(o.startMs)), [monday, monday.addDays(14)]);
  });

  test('FR-CAL-13 delete this and following ends the series', () async {
    final third = (await week(monday))[2];
    await m.commit(deleteEventOps(op(), third, EditScope.following, time, master: await master()));
    expect((await week(monday, 42)).map((o) => time.dateOfMs(o.startMs)), [monday, monday.addDays(7)]);
  });

  test('FR-CAL-13 delete all removes the series and its exceptions', () async {
    final second = (await week(monday))[1];
    final d = EventDraft.fromOccurrence(second, time, master: await master()).copyWith(title: 'Changed');
    await m.commit(updateEventOps(op(), second, d, EditScope.single, time, master: await master()));
    final exceptions = (await events()).where((e) => e.recurringParentId == masterId).toList();
    await m.commit(deleteEventOps(op(), second, EditScope.all, time, master: await master(), exceptions: exceptions));
    expect(await week(monday), isEmpty);
  });

  test('rruleWithUntil replaces COUNT and earlier UNTIL values', () {
    expect(rruleWithUntil('FREQ=WEEKLY;COUNT=10;BYDAY=MO', '20261012T150000Z'), 'FREQ=WEEKLY;BYDAY=MO;UNTIL=20261012T150000Z');
    expect(rruleWithUntil('RRULE:FREQ=DAILY;UNTIL=20270101', '20261231'), 'RRULE:FREQ=DAILY;UNTIL=20261231');
  });

  test('all-day drafts store dates and household-midnight instants', () {
    final f = const EventDraft(title: 'Trip', date: LocalDate(2026, 10, 10), endDate: LocalDate(2026, 10, 13), allDay: true, sourceId: 'cal').fields(time);
    expect(f['start_date'], '2026-10-10');
    expect(f['end_date'], '2026-10-13');
    expect(f['start_ms'], time.startOfDayMs(const LocalDate(2026, 10, 10)));
  });
}
