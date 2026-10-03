import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/calendar.dart';
import '../../../core/data/household.dart';
import '../../../core/format.dart';
import '../../../core/providers.dart';
import '../calendar_state.dart';
import '../event_editor.dart';
import '../event_ops.dart';
import '../event_sheet.dart';
import '../event_visuals.dart';

/// Day, 3-day and week time grid (FR-CAL-05/06). The hour lines are one
/// cached painter; event blocks are laid out once per data change; only the
/// now-line repaints each minute (SPEC §12.3).
class TimeGrid extends ConsumerStatefulWidget {
  const TimeGrid({super.key, required this.range});
  final DayRange range;

  @override
  ConsumerState<TimeGrid> createState() => _TimeGridState();
}

class _TimeGridState extends ConsumerState<TimeGrid> {
  final _scroll = ScrollController();
  bool _scrolled = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _initialScroll(double hourH) {
    // Wait for the household's time zone; the first frames may still be UTC.
    if (_scrolled || !ref.read(householdProvider).hasValue) return;
    _scrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final time = ref.read(householdTimeProvider);
      final today = ref.read(todayProvider);
      final minute = widget.range.contains(today) ? time.minuteOfDay(time.nowMs()) - 90 : 7 * 60;
      _scroll.jumpTo((minute / 60 * hourH).clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final range = widget.range;
    final hourH = (t.isPhone ? 52 : 64) * t.scale;
    final gutter = (t.isPhone ? 44 : 68) * t.scale;
    final time = ref.watch(householdTimeProvider);
    final filter = ref.watch(calendarFilterProvider).value ?? const <String>{};
    final occ = ref.watch(occurrencesProvider(range)).value ?? const <Occurrence>[];
    final ctx = EventContext.watch(ref);
    final visible = [for (final o in occ) if (passesFilter(o, filter)) o];
    final byDay = groupByDay(visible, range, time);
    final days = range.dates.toList();

    final allDay = {for (final d in days) d: [for (final o in byDay[d]!) if (o.allDay || _coversWholeDay(o, d, time)) o]};
    final timed = {
      for (final d in days)
        d: layoutDay([
          for (final o in byDay[d]!)
            if (!o.allDay && !_coversWholeDay(o, d, time)) _clip(o, d, time),
        ], minDuration: 30),
    };
    final maxAllDay = allDay.values.fold<int>(0, (m, l) => math.max(m, l.length));
    _initialScroll(hourH);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DayHeaders(days: days, gutter: gutter),
        if (maxAllDay > 0) _AllDayLane(days: days, gutter: gutter, items: allDay, ctx: ctx, rows: math.min(maxAllDay, 3)),
        SizedBox(height: t.space.xs),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(color: t.colors.surfaceRaised, borderRadius: t.radius.card, border: Border.all(color: t.colors.outline)),
            child: ClipRRect(
              borderRadius: t.radius.card,
              child: SingleChildScrollView(
                controller: _scroll,
                child: SizedBox(
                  height: hourH * 24,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _GridPainter(
                              hourH: hourH,
                              gutter: gutter,
                              columns: days.length,
                              line: t.colors.outline,
                              halfLine: t.colors.outline.withValues(alpha: 0.45),
                              label: t.text.caption.copyWith(fontSize: 13 * t.scale, fontWeight: FontWeight.w700),
                              h24: ref.watch(clock24Provider),
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        left: gutter,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final d in days)
                              Expanded(child: _DayColumn(day: d, placed: timed[d]!, hourH: hourH, ctx: ctx)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static bool _coversWholeDay(Occurrence o, LocalDate d, HouseholdTime time) =>
      !o.allDay && o.startMs <= time.startOfDayMs(d) && o.endMs >= time.startOfDayMs(d.addDays(1));

  static TimedItem<Occurrence> _clip(Occurrence o, LocalDate d, HouseholdTime time) {
    final dayStart = time.startOfDayMs(d);
    final dayEnd = time.startOfDayMs(d.addDays(1));
    final s = math.max(o.startMs, dayStart);
    final e = math.min(o.endMs, dayEnd);
    return TimedItem(o, ((s - dayStart) / 60000).round(), ((e - dayStart) / 60000).round());
  }
}

class _DayHeaders extends ConsumerWidget {
  const _DayHeaders({required this.days, required this.gutter});
  final List<LocalDate> days;
  final double gutter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final c = t.colors;
    final today = ref.watch(todayProvider);
    final report = ref.watch(weatherProvider).value;
    final imperial = ref.watch(imperialProvider);
    return Row(
      children: [
        SizedBox(width: gutter),
        for (final d in days)
          Expanded(
            child: DPressable(
              id: 'cal.dayhead.${d.iso}',
              onTap: () => ref.read(calNavProvider.notifier).show(d, view: CalView.day),
              borderRadius: t.radius.card,
              child: Builder(builder: (context) {
                final wx = report?.dayFor(d.iso);
                final isToday = d == today;
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: t.space.xs),
                  child: Column(
                    children: [
                      Text(weekdayShort(d).toUpperCase(), style: t.text.overline.copyWith(color: isToday ? c.accent : null)),
                      SizedBox(height: 2 * t.scale),
                      Container(
                        width: 44 * t.scale,
                        height: 44 * t.scale,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: isToday ? c.accent : null, shape: BoxShape.circle),
                        child: Text('${d.day}', style: t.text.title.copyWith(color: isToday ? c.onAccent : null, fontWeight: FontWeight.w800)),
                      ),
                      if (wx != null)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            DEmoji(conditionEmoji(wx.condition), size: 22 * t.scale),
                            SizedBox(width: 2 * t.scale),
                            Text(
                              '${formatTemp(wx.highC, imperial: imperial)}/${formatTemp(wx.lowC, imperial: imperial)}',
                              style: t.text.caption.copyWith(fontSize: 14 * t.scale, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                    ],
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

class _AllDayLane extends StatelessWidget {
  const _AllDayLane({required this.days, required this.gutter, required this.items, required this.ctx, required this.rows});
  final List<LocalDate> days;
  final double gutter;
  final Map<LocalDate, List<Occurrence>> items;
  final EventContext ctx;
  final int rows;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final chipH = 32 * t.scale;
    return Padding(
      padding: EdgeInsets.only(top: t.space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: gutter, child: Padding(padding: EdgeInsets.only(top: 6 * t.scale), child: Text('all day', style: t.text.caption.copyWith(fontSize: 13 * t.scale)))),
          for (final d in days)
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 2 * t.scale),
                child: SizedBox(
                  height: rows * (chipH + 4 * t.scale),
                  child: Column(
                    children: [
                      for (final (i, o) in items[d]!.take(rows).indexed)
                        if (i == rows - 1 && items[d]!.length > rows)
                          _MoreChip(count: items[d]!.length - rows + 1, height: chipH)
                        else
                          _AllDayChip(occurrence: o, ctx: ctx, height: chipH),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AllDayChip extends ConsumerWidget {
  const _AllDayChip({required this.occurrence, required this.ctx, required this.height});
  final Occurrence occurrence;
  final EventContext ctx;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final p = eventPalette(t, occurrence, ctx.people, ctx.sources);
    return Padding(
      padding: EdgeInsets.only(bottom: 4 * t.scale),
      child: DPressable(
        id: 'event.allday.${occurrence.event.id}',
        onTap: () => showEventSheet(context, ref, occurrence),
        semanticLabel: occurrence.event.title,
        borderRadius: BorderRadius.circular(10 * t.scale),
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: t.space.xs),
          decoration: BoxDecoration(color: p.solid, borderRadius: BorderRadius.circular(10 * t.scale)),
          child: Row(
            children: [
              DEmoji(eventEmoji(occurrence.event, learned: ctx.learned), size: height * 0.66),
              SizedBox(width: 4 * t.scale),
              Expanded(
                child: Text(
                  occurrence.event.title,
                  style: t.text.caption.copyWith(color: _onColor(p.solid), fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _onColor(Color c) => c.computeLuminance() > 0.45 ? const Color(0xFF1E1C24) : Colors.white;

class _MoreChip extends StatelessWidget {
  const _MoreChip({required this.count, required this.height});
  final int count;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Container(
      height: height,
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.symmetric(horizontal: t.space.xs),
      child: Text('+$count more', style: t.text.caption.copyWith(fontWeight: FontWeight.w800)),
    );
  }
}

class _DayColumn extends ConsumerWidget {
  const _DayColumn({required this.day, required this.placed, required this.hourH, required this.ctx});
  final LocalDate day;
  final List<PlacedItem<Occurrence>> placed;
  final double hourH;
  final EventContext ctx;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final isToday = ref.watch(todayProvider) == day;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          // Tap an empty slot to add an event there (snapped to 30 min).
          final minute = ((d.localPosition.dy / hourH * 60) ~/ 30 * 30).clamp(0, 23 * 60 + 30);
          showEventEditor(context, ref, draft: EventDraft(
            title: '',
            date: day,
            startMinute: minute,
            sourceId: ref.read(defaultCalendarProvider)?.id ?? Ids.familyCalendar,
          ));
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (isToday) Positioned.fill(child: ColoredBox(color: t.colors.accent.withValues(alpha: t.colors.isDark ? 0.06 : 0.035))),
            for (final p in placed)
              Positioned(
                top: p.startMin / 60 * hourH + 1,
                height: math.max((p.endMin - p.startMin) / 60 * hourH - 2, 22 * t.scale),
                left: p.leftFraction * w + 2 * t.scale,
                width: p.widthFraction * w - 4 * t.scale,
                child: _EventBlock(occurrence: p.value, ctx: ctx, height: math.max((p.endMin - p.startMin) / 60 * hourH - 2, 22 * t.scale)),
              ),
            if (isToday) Positioned.fill(child: _NowLine(hourH: hourH)),
          ],
        ),
      );
    });
  }
}

class _EventBlock extends ConsumerWidget {
  const _EventBlock({required this.occurrence, required this.ctx, required this.height});
  final Occurrence occurrence;
  final EventContext ctx;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final o = occurrence;
    final p = eventPalette(t, o, ctx.people, ctx.sources);
    final time = ref.watch(householdTimeProvider);
    final h24 = ref.watch(clock24Provider);
    final lineH = 22 * t.scale;
    final roomy = height >= lineH * 2.4;
    final title = Text(o.event.title, style: t.text.label.copyWith(color: p.ink, fontWeight: FontWeight.w800), maxLines: roomy ? 2 : 1, overflow: TextOverflow.ellipsis);
    return DPressable(
      id: 'event.block.${o.event.id}',
      onTap: () => showEventSheet(context, ref, o),
      semanticLabel: '${o.event.title}, ${formatTime(time.wall(o.startMs), h24: h24)}',
      borderRadius: BorderRadius.circular(10 * t.scale),
      child: Container(
        decoration: BoxDecoration(
          color: p.tint,
          borderRadius: BorderRadius.circular(10 * t.scale),
          border: Border.all(color: t.colors.surfaceRaised),
        ),
        clipBehavior: Clip.hardEdge,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StripedEdge(colors: p.stripes, width: 5 * t.scale, radius: 0),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 6 * t.scale, vertical: 3 * t.scale),
                child: roomy
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [DEmoji(eventEmoji(o.event, learned: ctx.learned), size: 22 * t.scale), SizedBox(width: 4 * t.scale), Expanded(child: title)]),
                          Text(
                            formatTimeRange(time.wall(o.startMs), time.wall(o.endMs), h24: h24),
                            style: t.text.caption.copyWith(fontSize: 13 * t.scale, color: p.ink.withValues(alpha: 0.85)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      )
                    : Row(children: [DEmoji(eventEmoji(o.event, learned: ctx.learned), size: 18 * t.scale), SizedBox(width: 4 * t.scale), Expanded(child: title)]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The red now-line; the only part of the grid that ticks.
class _NowLine extends ConsumerWidget {
  const _NowLine({required this.hourH});
  final double hourH;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final now = ref.watch(nowMinuteMsProvider);
    final time = ref.watch(householdTimeProvider);
    final y = time.minuteOfDay(now) / 60 * hourH;
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(painter: _NowPainter(y, t.colors.danger, 2.5 * t.scale)),
      ),
    );
  }
}

class _NowPainter extends CustomPainter {
  _NowPainter(this.y, this.color, this.stroke);
  final double y;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = stroke;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    canvas.drawCircle(Offset(0, y), stroke * 2.4, p);
  }

  @override
  bool shouldRepaint(_NowPainter old) => old.y != y || old.color != color;
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.hourH, required this.gutter, required this.columns, required this.line, required this.halfLine, required this.label, required this.h24});
  final double hourH;
  final double gutter;
  final int columns;
  final Color line;
  final Color halfLine;
  final TextStyle label;
  final bool h24;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Paint()..color = line;
    final half = Paint()..color = halfLine;
    for (var h = 0; h < 24; h++) {
      final y = h * hourH;
      if (h > 0) canvas.drawRect(Rect.fromLTWH(gutter, y, size.width - gutter, 1), full);
      canvas.drawRect(Rect.fromLTWH(gutter, y + hourH / 2, size.width - gutter, 1), half);
      if (h == 0) continue;
      final text = h24 ? '${h.toString().padLeft(2, '0')}:00' : '${h % 12 == 0 ? 12 : h % 12} ${h < 12 ? 'AM' : 'PM'}';
      final tp = TextPainter(text: TextSpan(text: text, style: label), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(gutter - tp.width - 8, y - tp.height / 2));
    }
    final colW = (size.width - gutter) / columns;
    for (var i = 0; i <= columns - 1; i++) {
      canvas.drawRect(Rect.fromLTWH(gutter + i * colW, 0, 1, size.height), full);
    }
  }

  @override
  bool shouldRepaint(_GridPainter o) => o.hourH != hourH || o.gutter != gutter || o.columns != columns || o.line != line || o.label != label || o.h24 != h24;
}
