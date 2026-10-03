import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/calendar.dart';
import '../../../core/data/household.dart';
import '../../../core/format.dart';
import '../agenda_row.dart';
import '../calendar_state.dart';
import '../event_editor.dart';
import '../event_ops.dart';
import '../event_visuals.dart';

/// Month grid with event chips and "+N" overflow (FR-CAL-07).
class MonthView extends ConsumerWidget {
  const MonthView({super.key, required this.anchor, required this.range});
  final LocalDate anchor;
  final DayRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final c = t.colors;
    final time = ref.watch(householdTimeProvider);
    final today = ref.watch(todayProvider);
    final filter = ref.watch(calendarFilterProvider).value ?? const <String>{};
    final occ = ref.watch(occurrencesProvider(range)).value ?? const <Occurrence>[];
    final ctx = EventContext.watch(ref);
    final byDay = groupByDay([for (final o in occ) if (passesFilter(o, filter)) o], range, time);
    final days = range.dates.toList();

    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(child: Center(child: Text(weekdayShort(days[i]).toUpperCase(), style: t.text.overline))),
          ],
        ),
        SizedBox(height: t.space.xs),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(color: c.surfaceRaised, borderRadius: t.radius.card, border: Border.all(color: c.outline)),
            child: LayoutBuilder(builder: (context, box) {
              final cellH = box.maxHeight / 6;
              final chipH = (t.isPhone ? 18 : 26) * t.scale;
              final headH = (t.isPhone ? 24 : 34) * t.scale;
              final maxChips = math.max(0, ((cellH - headH - 4) / (chipH + 3 * t.scale)).floor());
              return Column(
                children: [
                  for (var w = 0; w < 6; w++)
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var d = 0; d < 7; d++)
                            Expanded(
                              child: _MonthCell(
                                day: days[w * 7 + d],
                                inMonth: days[w * 7 + d].month == anchor.month,
                                isToday: days[w * 7 + d] == today,
                                items: byDay[days[w * 7 + d]] ?? const [],
                                ctx: ctx,
                                maxChips: maxChips,
                                chipH: chipH,
                                headH: headH,
                                lastCol: d == 6,
                                lastRow: w == 5,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _MonthCell extends ConsumerWidget {
  const _MonthCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.items,
    required this.ctx,
    required this.maxChips,
    required this.chipH,
    required this.headH,
    required this.lastCol,
    required this.lastRow,
  });
  final LocalDate day;
  final bool inMonth;
  final bool isToday;
  final List<Occurrence> items;
  final EventContext ctx;
  final int maxChips;
  final double chipH;
  final double headH;
  final bool lastCol;
  final bool lastRow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final c = t.colors;
    final overflow = items.length > maxChips;
    final shown = items.take(overflow ? math.max(0, maxChips - 1) : maxChips).toList();
    final h24 = ref.watch(clock24Provider);
    final time = ref.watch(householdTimeProvider);
    return DPressable(
      id: 'cal.month.${day.iso}',
      semanticLabel: '${longDate(day)}, ${items.length} events',
      excludeSemantics: true,
      pressedScale: 1,
      onTap: () => showDaySheet(context, ref, day),
      child: Container(
        decoration: BoxDecoration(
          color: inMonth ? null : c.surfaceSunken.withValues(alpha: 0.5),
          border: Border(
            right: lastCol ? BorderSide.none : BorderSide(color: c.outline),
            bottom: lastRow ? BorderSide.none : BorderSide(color: c.outline),
          ),
        ),
        padding: EdgeInsets.all(3 * t.scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: headH,
              child: Align(
                alignment: Alignment.topLeft,
                child: Container(
                  width: headH * 0.92,
                  height: headH * 0.92,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: isToday ? c.accent : null, shape: BoxShape.circle),
                  child: Text(
                    '${day.day}',
                    style: t.text.label.copyWith(
                      fontSize: (t.isPhone ? 13 : 17) * t.scale,
                      color: isToday ? c.onAccent : (inMonth ? c.inkPrimary : c.inkTertiary),
                      fontWeight: isToday ? FontWeight.w800 : FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            for (final o in shown)
              Padding(
                padding: EdgeInsets.only(bottom: 3 * t.scale),
                child: _MonthChip(occurrence: o, ctx: ctx, height: chipH, timeLabel: o.allDay ? null : formatTime(time.wall(o.startMs), h24: h24, compact: true)),
              ),
            if (overflow)
              Padding(
                padding: EdgeInsets.only(left: 4 * t.scale),
                child: Text('+${items.length - shown.length}', style: t.text.caption.copyWith(fontSize: 13 * t.scale, fontWeight: FontWeight.w800)),
              ),
          ],
        ),
      ),
    );
  }
}

class _MonthChip extends StatelessWidget {
  const _MonthChip({required this.occurrence, required this.ctx, required this.height, this.timeLabel});
  final Occurrence occurrence;
  final EventContext ctx;
  final double height;
  final String? timeLabel;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final p = eventPalette(t, occurrence, ctx.people, ctx.sources);
    final allDay = occurrence.allDay;
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: 4 * t.scale),
      decoration: BoxDecoration(color: allDay ? p.solid : p.tint, borderRadius: BorderRadius.circular(6 * t.scale)),
      child: Row(
        children: [
          if (!t.isPhone) ...[DEmoji(eventEmoji(occurrence.event, learned: ctx.learned), size: height * 0.7), SizedBox(width: 3 * t.scale)],
          Expanded(
            child: Text(
              timeLabel == null || t.isPhone ? occurrence.event.title : '$timeLabel ${occurrence.event.title}',
              style: t.text.caption.copyWith(
                fontSize: (t.isPhone ? 11 : 14) * t.scale,
                fontWeight: FontWeight.w700,
                color: allDay ? (p.solid.computeLuminance() > 0.45 ? const Color(0xFF1E1C24) : Colors.white) : p.ink,
              ),
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
            ),
          ),
        ],
      ),
    );
  }
}

/// A day's events in a sheet (month view taps; FR-CAL-07).
Future<void> showDaySheet(BuildContext context, WidgetRef ref, LocalDate day) => showDSheet<void>(
      context,
      title: longDate(day),
      id: 'cal.daysheet',
      builder: (sheet) => Consumer(builder: (context, ref, _) {
        final t = DTheme.of(context);
        final filter = ref.watch(calendarFilterProvider).value ?? const <String>{};
        final occ = ref.watch(occurrencesProvider(DayRange.single(day))).value ?? const <Occurrence>[];
        final ctx = EventContext.watch(ref);
        final items = [for (final o in occ) if (passesFilter(o, filter)) o];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (items.isEmpty)
              const DEmptyState(emoji: '🗓️', title: 'A free day', message: 'Nothing planned yet.', compact: true)
            else
              for (final o in items) AgendaRow(occurrence: o, ctx: ctx),
            SizedBox(height: t.space.md),
            Row(
              children: [
                Expanded(
                  child: DButton(
                    label: 'Open day',
                    tone: DButtonTone.neutral,
                    expand: true,
                    id: 'cal.daysheet.open',
                    onPressed: () {
                      Navigator.of(sheet).pop();
                      ref.read(calNavProvider.notifier).show(day, view: CalView.day);
                    },
                  ),
                ),
                SizedBox(width: t.space.sm),
                Expanded(
                  child: DButton(
                    label: 'Add event',
                    icon: Icons.add_rounded,
                    expand: true,
                    id: 'cal.daysheet.add',
                    onPressed: () {
                      Navigator.of(sheet).pop();
                      showEventEditor(context, ref, draft: EventDraft(title: '', date: day, sourceId: ref.read(defaultCalendarProvider)?.id ?? Ids.familyCalendar));
                    },
                  ),
                ),
              ],
            ),
          ],
        );
      }),
    );
