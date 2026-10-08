import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/grown_up.dart';
import '../../core/data/calendar.dart';
import '../../core/data/household.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import 'event_editor.dart';
import 'event_ops.dart';
import 'event_visuals.dart';

/// Opens the details sheet for one occurrence (FR-CAL-05…08 tap target).
Future<void> showEventSheet(BuildContext context, WidgetRef ref, Occurrence o) =>
    showDSheet<void>(context, id: 'event.sheet', builder: (_) => EventDetails(occurrence: o));

class EventDetails extends ConsumerWidget {
  const EventDetails({super.key, required this.occurrence});
  final Occurrence occurrence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final c = t.colors;
    final o = occurrence;
    final ctx = EventContext.watch(ref);
    final time = ref.watch(householdTimeProvider);
    final h24 = ref.watch(clock24Provider);
    final today = ref.watch(todayProvider);
    final palette = eventPalette(t, o, ctx.people, ctx.sources);
    final people = [for (final id in o.profileIds) ?ctx.people[id]];
    final source = ctx.sources[o.event.sourceId];
    final writable = source?.writable ?? true;
    final startDay = o.startDate ?? time.dateOfMs(o.startMs);

    final String when;
    if (o.allDay) {
      final last = (o.endDate ?? startDay.addDays(1)).addDays(-1);
      when = last == startDay ? '${relativeDayName(startDay, today)}, ${monthDay(startDay)} · All day' : '${monthDay(startDay)} – ${monthDay(last)} · All day';
    } else {
      when = '${relativeDayName(startDay, today)}, ${monthDay(startDay)} · ${formatTimeRange(time.wall(o.startMs), time.wall(o.endMs), h24: h24)}';
    }
    final days = today.daysUntil(startDay);

    Widget info(IconData icon, String text, {String? id}) => Padding(
          padding: EdgeInsets.symmetric(vertical: t.space.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: t.iconSm, color: c.inkSecondary),
              SizedBox(width: t.space.sm),
              Expanded(child: id == null ? Text(text, style: t.text.body) : tid(id, Text(text, style: t.text.body))),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 84 * t.scale,
              height: 84 * t.scale,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: palette.tint, borderRadius: t.radius.card),
              child: DEmoji(eventEmoji(o.event, learned: ctx.learned), size: 56 * t.scale),
            ),
            SizedBox(width: t.space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tid('event.sheet.title', Text(o.event.title, style: t.text.h2)),
                  SizedBox(height: t.space.xxs),
                  Text(when, style: t.text.body.copyWith(color: c.inkSecondary)),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: t.space.md),
        if (o.event.rrule?.isNotEmpty ?? false)
          info(Icons.repeat_rounded, describeRrule(o.event.rrule))
        else if (o.event.recurringParentId != null)
          info(Icons.repeat_rounded, 'Repeats · this day was changed'),
        if (people.isNotEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: t.space.xs),
            child: Row(
              children: [
                AvatarStack(people: people, size: 36 * t.scale),
                SizedBox(width: t.space.sm),
                Expanded(child: Text(people.map((p) => p.name).join(', '), style: t.text.body)),
              ],
            ),
          ),
        if (o.event.location != null) info(Icons.place_rounded, o.event.location!),
        if (watchEventForecast(ref, o) case final f?)
          Padding(
            padding: EdgeInsets.symmetric(vertical: t.space.xs),
            child: Row(
              children: [
                SizedBox(width: t.iconSm, child: Center(child: DEmoji(f.emoji, size: t.iconSm))),
                SizedBox(width: t.space.sm),
                Expanded(child: tid('event.sheet.weather', Text(describeEventForecast(f, imperial: ref.watch(imperialProvider)), style: t.text.body))),
              ],
            ),
          ),
        if (o.event.notes != null) info(Icons.notes_rounded, o.event.notes!),
        if (effectiveReminders(o.event, writable: writable, calendarDefault: ref.watch(calendarRemindersProvider)[o.event.sourceId] ?? const [])
            case final leads when leads.isNotEmpty)
          info(Icons.notifications_active_rounded, leads.map((m) => describeReminder(m, allDay: o.allDay, h24: h24)).join(', '), id: 'event.sheet.reminders'),
        if (o.event.countdown && days > 0)
          info(Icons.hourglass_bottom_rounded, '$days ${days == 1 ? 'day' : 'days'} to go · ${'🌙' * days.clamp(0, 7)} $days ${days == 1 ? 'sleep' : 'sleeps'}', id: 'event.sheet.countdown'),
        if (source != null)
          Padding(
            padding: EdgeInsets.symmetric(vertical: t.space.xs),
            child: Row(
              children: [
                Container(width: 14 * t.scale, height: 14 * t.scale, decoration: BoxDecoration(color: Color(source.color), shape: BoxShape.circle)),
                SizedBox(width: t.space.sm),
                Text('${source.name}${writable ? '' : ' · read-only'}', style: t.text.caption),
              ],
            ),
          ),
        SizedBox(height: t.space.lg),
        if (writable)
          Wrap(
            spacing: t.space.sm,
            runSpacing: t.space.sm,
            children: [
              DButton(
                label: 'Edit',
                icon: Icons.edit_rounded,
                id: 'event.sheet.edit',
                onPressed: () {
                  Navigator.of(context).pop();
                  showEventEditor(context, ref, occurrence: o);
                },
              ),
              DButton(
                label: o.event.countdown ? 'Stop countdown' : 'Count down',
                icon: Icons.hourglass_top_rounded,
                tone: DButtonTone.tonal,
                id: 'event.sheet.countdown.toggle',
                onPressed: () async {
                  await ref.read(writerProvider).upsert('events', masterIdOf(o), {'countdown': !o.event.countdown});
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
              DButton(
                label: 'Delete',
                icon: Icons.delete_outline_rounded,
                tone: DButtonTone.neutral,
                id: 'event.sheet.delete',
                onPressed: () => deleteOccurrence(context, ref, o),
              ),
            ],
          ),
      ],
    );
  }
}

/// Asks which instances an edit or delete applies to (FR-CAL-13).
Future<EditScope?> pickScope(BuildContext context, {required bool delete}) => showDSheet<EditScope>(
      context,
      title: delete ? 'Delete repeating event' : 'Change repeating event',
      id: 'event.scope',
      builder: (sheet) {
        final t = DTheme.of(sheet);
        Widget row(EditScope s, String title, String subtitle, IconData icon) => DListRow(
              id: 'event.scope.${s.name}',
              title: title,
              subtitle: subtitle,
              leading: Icon(icon, color: t.colors.accent, size: t.iconMd),
              onTap: () => Navigator.of(sheet).pop(s),
            );
        return Column(
          children: [
            row(EditScope.single, 'This event', 'Only this day', Icons.event_rounded),
            row(EditScope.following, 'This and following', 'From this day on', Icons.east_rounded),
            row(EditScope.all, 'All events', 'Every day in the series', Icons.repeat_rounded),
          ],
        );
      },
    );

/// Loads the master and exception rows a recurring change needs.
Future<(Event?, List<Event>)> loadSeries(WidgetRef ref, Occurrence o) async {
  final db = ref.read(dbProvider);
  final id = masterIdOf(o);
  final master = await (db.select(db.events)..where((e) => e.id.equals(id))).getSingleOrNull();
  final exceptions = await (db.select(db.events)..where((e) => e.recurringParentId.equals(id) & e.deleted.equals(false))).get();
  return (master, exceptions);
}

Future<void> deleteOccurrence(BuildContext context, WidgetRef ref, Occurrence o) async {
  final recurring = isRecurring(o);
  final scope = recurring ? await pickScope(context, delete: true) : EditScope.all;
  if (scope == null || !context.mounted) return;
  if (!await ensureGrownUp(context, ref, reason: 'Deleting needs a grown-up')) return;
  final writer = ref.read(writerProvider);
  final time = ref.read(householdTimeProvider);
  final (master, exceptions) = recurring ? await loadSeries(ref, o) : (null, const <Event>[]);
  final ops = deleteEventOps(writer.op, o, scope, time, master: master, exceptions: exceptions);
  await writer.commit(ops);
  if (context.mounted) Navigator.of(context).maybePop();
  final undoable = !recurring || scope == EditScope.single;
  ref.read(toastProvider).show(
        'Deleted “${o.event.title}”',
        emoji: '🗑️',
        actionLabel: undoable ? 'Undo' : null,
        onAction: undoable
            ? () => writer.commit([
                  for (final op in ops)
                    if (op.kind == OpKind.delete)
                      writer.op('events', op.rowId, {'deleted': false})
                    else if (o.event.recurringParentId != null)
                      writer.op('events', op.rowId, {'status': 'confirmed'}) // an edited day: restore it
                    else
                      writer.op('events', op.rowId, {'deleted': true}), // drop the new cancellation
                ])
            : null,
      );
}

/// Applies a drag move or resize (FR-CAL-14): asks which instances a
/// repeating event's change applies to, writes it, and offers Undo where a
/// clean revert exists (one event, or one day of a series).
Future<void> moveOccurrence(BuildContext context, WidgetRef ref, Occurrence o, EventDraft moved, {required String summary, bool resized = false}) async {
  final recurring = isRecurring(o);
  final scope = recurring ? await pickScope(context, delete: false) : EditScope.all;
  if (scope == null) return;
  final writer = ref.read(writerProvider);
  final time = ref.read(householdTimeProvider);
  final (master, exceptions) = recurring ? await loadSeries(ref, o) : (null, const <Event>[]);
  final ops = updateEventOps(writer.op, o, moved, scope, time, master: master, exceptions: exceptions);
  await writer.commit(ops);
  final before = EventDraft.fromOccurrence(o, time, master: master);
  final List<Op>? undo = switch (scope) {
    _ when !recurring => [writer.op('events', o.event.id, before.fields(time))],
    // A plain instance got a new override row: dropping it restores the day.
    EditScope.single when o.event.recurringParentId == null => [writer.op('events', ops.single.rowId, const {}, kind: OpKind.delete)],
    EditScope.single => [writer.op('events', o.event.id, before.fields(time, includeRrule: false))],
    _ => null,
  };
  ref.read(toastProvider).show(
        '${resized ? 'Changed' : 'Moved'} “${o.event.title}” · $summary',
        emoji: resized ? '↕️' : '📅',
        actionLabel: undo == null ? null : 'Undo',
        onAction: undo == null ? null : () => writer.commit(undo),
      );
}

/// "Sat 4" style label for compact headers.
String dayChip(LocalDate d) => '${DateFormat('EEE').format(d.utcMidnight)} ${d.day}';
