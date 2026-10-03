import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/grown_up.dart';
import '../../../core/data/calendar.dart';
import '../../../core/data/household.dart';
import '../../../core/format.dart';
import '../../../core/providers.dart';
import '../calendar_state.dart';
import '../event_editor.dart';
import '../event_ops.dart';
import '../event_sheet.dart';
import '../event_visuals.dart';

/// One column of the time grid: a day (day, 3-day and week views), or one
/// person's day in the People view (FR-CAL-09), where [family] holds the
/// events that have no people.
@immutable
class GridColumn {
  const GridColumn(this.day, {this.person, this.family = false});
  final LocalDate day;
  final Profile? person;
  final bool family;

  bool accepts(Occurrence o) {
    if (person != null) return o.profileIds.contains(person!.id);
    if (family) return o.profileIds.isEmpty;
    return true;
  }

  /// The same lane on another day (a dragged event stays with its person).
  bool sameLane(GridColumn other) => other.person?.id == person?.id && other.family == family;

  String get id => person != null ? '${day.iso}.${person!.id}' : (family ? '${day.iso}.family' : day.iso);
}

/// The People view's lanes for [days]: a Family lane when some event has no
/// people, then one per person. The filter chips choose whose lanes show;
/// pets only get a lane when they have something on.
List<GridColumn> peopleColumns(List<LocalDate> days, List<Profile> family, Set<String> filter, List<Occurrence> occ) {
  final lanes = [
    for (final p in family)
      if ((filter.isEmpty || filter.contains(p.id)) && (p.role != ProfileRole.pet || occ.any((o) => o.profileIds.contains(p.id)))) p,
  ];
  final hasFamily = occ.any((o) => o.profileIds.isEmpty);
  return [
    for (final d in days) ...[
      if (hasFamily) GridColumn(d, family: true),
      for (final p in lanes) GridColumn(d, person: p),
    ],
  ];
}

/// Snaps minutes to the 15-minute grid used by drag and resize (FR-CAL-14).
int snap15(num minutes) => (minutes / 15).round() * 15;

/// Day, 3-day, week and People time grid (FR-CAL-05/06/09). The hour lines
/// are one cached painter; event blocks are laid out once per data change;
/// only the now-line repaints each minute (SPEC §12.3). A long press lifts
/// an event to move it, or near its bottom edge to resize it (FR-CAL-14).
class TimeGrid extends ConsumerStatefulWidget {
  const TimeGrid({super.key, required this.range, this.people = false});
  final DayRange range;

  /// One lane per person per day (FR-CAL-09).
  final bool people;

  @override
  ConsumerState<TimeGrid> createState() => _TimeGridState();
}

class _TimeGridState extends ConsumerState<TimeGrid> {
  final _scroll = ScrollController();
  final _gridKey = GlobalKey();
  final _viewportKey = GlobalKey();
  final _drag = ValueNotifier<_Drag?>(null);
  Timer? _autoScroll;
  bool _scrolled = false;

  // Geometry of the last build, for drag hit-testing.
  List<GridColumn> _columns = const [];
  double _hourH = 64;
  double _gutter = 68;

  @override
  void dispose() {
    _autoScroll?.cancel();
    _drag.dispose();
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
      // Open on a whole hour, with its line a little below the top edge so
      // the hour label (centered on the line) isn't clipped.
      final hour = widget.range.contains(today) ? (time.minuteOfDay(time.nowMs()) - 90) ~/ 60 : 7;
      _scroll.jumpTo((hour * hourH - hourH * 0.2).clamp(0, _scroll.position.maxScrollExtent));
    });
  }

  // ─────────────────────────── Drag & resize ────────────────────────────

  Offset? _gridLocal(Offset global) {
    final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.globalToLocal(global);
  }

  Future<void> _lift(int column, PlacedItem<Occurrence> placed, LongPressStartDetails d, {required bool resize}) async {
    final o = placed.value;
    final source = ref.read(calendarSourceMapProvider)[o.event.sourceId];
    if (source != null && !source.writable) {
      ref.read(toastProvider).show('“${source.name}” is read-only', emoji: '🔒');
      return;
    }
    if (!ref.read(grownUpProvider.notifier).isOpen) {
      await ensureGrownUp(context, ref, reason: 'Moving events needs a grown-up');
      return;
    }
    final local = _gridLocal(d.globalPosition);
    if (local == null) return;
    final time = ref.read(householdTimeProvider);
    final day = _columns[column].day;
    final start = time.dateOfMs(o.startMs);
    final startMin = day.daysUntil(start) * 1440 + time.minuteOfDay(o.startMs);
    final duration = ((o.endMs - o.startMs) / 60000).round();
    unawaited(HapticFeedback.mediumImpact());
    setState(() => _drag.value = _Drag(occurrence: o, column: column, startMin: startMin, endMin: startMin + duration, resize: resize, anchor: local));
  }

  void _move(Offset global) {
    final d = _drag.value;
    final local = _gridLocal(global);
    if (d == null || local == null) return;
    d.lastGlobal = global;
    final dy = (local.dy - d.anchor.dy) / _hourH * 60;
    final int start;
    final int end;
    if (d.resize) {
      start = d.startMin;
      end = snap15(d.endMin + dy).clamp(math.max(d.startMin, 0) + 15, 24 * 60);
    } else {
      final duration = d.endMin - d.startMin;
      start = snap15(d.startMin + dy).clamp(math.min(d.startMin, 0), 24 * 60 - 15);
      end = start + duration;
    }
    // Days follow the finger across columns; a lane keeps its person.
    var column = d.column;
    if (!d.resize && _columns.length > 1) {
      final box = _gridKey.currentContext!.findRenderObject()! as RenderBox;
      final colW = (box.size.width - _gutter) / _columns.length;
      final under = ((local.dx - _gutter) / colW).floor().clamp(0, _columns.length - 1);
      final origin = _columns[d.column];
      if (_columns[under].sameLane(origin)) column = under;
    }
    if (start != d.newStart || end != d.newEnd || column != d.targetColumn) {
      unawaited(HapticFeedback.selectionClick());
      _drag.value = d.copyWith(newStart: start, newEnd: end, targetColumn: column);
    }
    _edgeScroll(global);
  }

  /// Scrolls while the finger rests near the top or bottom edge.
  void _edgeScroll(Offset global) {
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final y = box.globalToLocal(global).dy;
    final edge = 56 * DTheme.of(context).scale;
    final dir = y < edge ? -1 : (y > box.size.height - edge ? 1 : 0);
    if (dir == 0) {
      _autoScroll?.cancel();
      _autoScroll = null;
      return;
    }
    _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      final d = _drag.value;
      if (d == null || !_scroll.hasClients) return;
      final p = _scroll.position;
      final next = (p.pixels + dir * 9).clamp(0.0, p.maxScrollExtent);
      if (next == p.pixels) return;
      _scroll.jumpTo(next);
      _move(d.lastGlobal ?? global);
    });
  }

  Future<void> _drop() async {
    _autoScroll?.cancel();
    _autoScroll = null;
    final d = _drag.value;
    setState(() => _drag.value = null);
    if (d == null || !d.changed) return;
    unawaited(HapticFeedback.lightImpact());
    final time = ref.read(householdTimeProvider);
    final o = d.occurrence;
    final (date, minute) = wallAt(_columns[d.targetColumn].day, d.newStart);
    final moved = EventDraft.fromOccurrence(o, time).copyWith(date: date, startMinute: minute, durationMinutes: d.newEnd - d.newStart);
    final when = _dragLabel(time, d, _columns, h24: ref.read(clock24Provider));
    await moveOccurrence(context, ref, o, moved, summary: when, resized: d.resize);
  }

  void _cancelDrag() {
    _autoScroll?.cancel();
    _autoScroll = null;
    if (_drag.value != null) setState(() => _drag.value = null);
  }

  // ────────────────────────────── Build ─────────────────────────────────

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
    final days = range.dates.toList();
    final columns = widget.people ? peopleColumns(days, ref.watch(familyProvider), filter, occ) : [for (final d in days) GridColumn(d)];
    // The People view filters lanes, not events.
    final visible = widget.people ? occ : [for (final o in occ) if (passesFilter(o, filter)) o];
    final byDay = groupByDay(visible, range, time);

    final allDay = [
      for (final c in columns) [for (final o in byDay[c.day]!) if (c.accepts(o) && (o.allDay || _coversWholeDay(o, c.day, time))) o],
    ];
    final timed = [
      for (final c in columns)
        layoutDay([
          for (final o in byDay[c.day]!)
            if (c.accepts(o) && !o.allDay && !_coversWholeDay(o, c.day, time)) _clip(o, c.day, time),
        ], minDuration: 30),
    ];
    final maxAllDay = allDay.fold<int>(0, (m, l) => math.max(m, l.length));
    _columns = columns;
    _hourH = hourH;
    _gutter = gutter;
    _initialScroll(hourH);

    if (columns.isEmpty) {
      return const DEmptyState(emoji: '👪', title: 'Nobody to show yet', message: 'Add family members in Settings → People to see who’s where.');
    }
    final lanesPerDay = columns.length ~/ days.length;
    final dragging = _drag.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.people) _PeopleHeaders(columns: columns, gutter: gutter, days: days) else _DayHeaders(days: days, gutter: gutter),
        if (maxAllDay > 0) _AllDayLane(columns: columns, gutter: gutter, items: allDay, ctx: ctx, rows: math.min(maxAllDay, 3)),
        SizedBox(height: t.space.xs),
        Expanded(
          child: DecoratedBox(
            key: _viewportKey,
            decoration: BoxDecoration(color: t.colors.surfaceRaised, borderRadius: t.radius.card, border: Border.all(color: t.colors.outline)),
            child: ClipRRect(
              borderRadius: t.radius.card,
              child: SingleChildScrollView(
                controller: _scroll,
                // A lifted event owns the finger; the grid scrolls at the edges.
                physics: dragging != null ? const NeverScrollableScrollPhysics() : null,
                child: SizedBox(
                  key: _gridKey,
                  height: hourH * 24,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _GridPainter(
                              hourH: hourH,
                              gutter: gutter,
                              columns: columns.length,
                              groupEvery: widget.people && days.length > 1 ? lanesPerDay : 0,
                              line: t.colors.outline,
                              halfLine: t.colors.outline.withValues(alpha: 0.45),
                              groupLine: t.colors.inkTertiary,
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
                            for (final (i, c) in columns.indexed)
                              Expanded(
                                child: _DayColumn(
                                  column: c,
                                  placed: timed[i],
                                  hourH: hourH,
                                  ctx: ctx,
                                  lifted: dragging?.column == i ? dragging!.key : null,
                                  onLift: (p, d, {required resize}) => _lift(i, p, d, resize: resize),
                                  onDrag: _move,
                                  onDrop: _drop,
                                  onCancel: _cancelDrag,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (dragging != null)
                        Positioned.fill(
                          child: ValueListenableBuilder<_Drag?>(
                            valueListenable: _drag,
                            builder: (context, d, _) => d == null ? const SizedBox.shrink() : _LiftedBlock(drag: d, columns: columns, gutter: gutter, hourH: hourH, ctx: ctx),
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

/// A lifted event: where it came from and where the finger has taken it, in
/// minutes from the origin column's midnight (snapped to 15 minutes).
class _Drag {
  _Drag({
    required this.occurrence,
    required this.column,
    required this.startMin,
    required this.endMin,
    required this.resize,
    required this.anchor,
    int? newStart,
    int? newEnd,
    int? targetColumn,
  })  : newStart = newStart ?? startMin,
        newEnd = newEnd ?? endMin,
        targetColumn = targetColumn ?? column;

  final Occurrence occurrence;
  final int column;
  final int startMin;
  final int endMin;
  final bool resize;
  final Offset anchor;
  final int newStart;
  final int newEnd;
  final int targetColumn;
  Offset? lastGlobal;

  String get key => occurrence.key;
  bool get changed => newStart != startMin || newEnd != endMin || targetColumn != column;

  _Drag copyWith({required int newStart, required int newEnd, required int targetColumn}) => _Drag(
        occurrence: occurrence,
        column: column,
        startMin: startMin,
        endMin: endMin,
        resize: resize,
        anchor: anchor,
        newStart: newStart,
        newEnd: newEnd,
        targetColumn: targetColumn,
      )..lastGlobal = lastGlobal;
}

/// The household-local date and minute of day [minutes] after [day]'s
/// midnight (negative or past 24 h roll into the neighboring days).
(LocalDate, int) wallAt(LocalDate day, int minutes) => (day.addDays((minutes / 1440).floor()), minutes % 1440);

/// "10:15–11:15", with the weekday when the event changes day, or the new
/// length when resizing.
String _dragLabel(HouseholdTime time, _Drag d, List<GridColumn> columns, {required bool h24}) {
  final (date, minute) = wallAt(columns[d.targetColumn].day, d.newStart);
  final startMs = time.msAt(date, minute ~/ 60, minute % 60);
  final minutes = d.newEnd - d.newStart;
  final range = formatTimeRange(time.wall(startMs), time.wall(startMs + minutes * 60000), h24: h24);
  if (d.resize) return '$range · ${formatDuration(minutes)}';
  return d.targetColumn != d.column || date != columns[d.targetColumn].day ? '${weekdayShort(date)} $range' : range;
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

/// Avatar headers for the People lanes, under a day row when it spans days.
class _PeopleHeaders extends ConsumerWidget {
  const _PeopleHeaders({required this.columns, required this.gutter, required this.days});
  final List<GridColumn> columns;
  final double gutter;
  final List<LocalDate> days;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final today = ref.watch(todayProvider);
    final lanes = columns.length ~/ days.length;
    final avatar = (t.isPhone ? 34 : 44) * t.scale;
    return Column(
      children: [
        if (days.length > 1)
          Row(
            children: [
              SizedBox(width: gutter),
              for (final d in days)
                Expanded(
                  flex: lanes,
                  child: DPressable(
                    id: 'cal.dayhead.${d.iso}',
                    onTap: () => ref.read(calNavProvider.notifier).show(d, view: CalView.people),
                    borderRadius: t.radius.card,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: t.space.xxs),
                      child: Text(
                        '${weekdayShort(d)} ${d.day}',
                        textAlign: TextAlign.center,
                        style: t.text.label.copyWith(fontWeight: FontWeight.w800, color: d == today ? t.colors.accent : null),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        Row(
          children: [
            SizedBox(width: gutter),
            for (final c in columns)
              Expanded(
                child: tid(
                  'cal.lane.${c.id}',
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: t.space.xs, horizontal: 2 * t.scale),
                    child: Column(
                      children: [
                        if (c.person != null)
                          DAvatar(colorIndex: c.person!.color, emoji: c.person!.emoji, name: c.person!.name, size: avatar)
                        else
                          Container(
                            width: avatar,
                            height: avatar,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: t.colors.surfaceSunken, shape: BoxShape.circle),
                            child: DEmoji('👪', size: avatar * 0.6),
                          ),
                        SizedBox(height: 2 * t.scale),
                        Text(
                          c.person?.name ?? 'Family',
                          style: t.text.caption.copyWith(fontWeight: FontWeight.w800, color: t.colors.inkPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _AllDayLane extends StatelessWidget {
  const _AllDayLane({required this.columns, required this.gutter, required this.items, required this.ctx, required this.rows});
  final List<GridColumn> columns;
  final double gutter;
  final List<List<Occurrence>> items;
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
          for (final (c, list) in [for (final (i, c) in columns.indexed) (c, items[i])])
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 2 * t.scale),
                child: SizedBox(
                  height: rows * (chipH + 4 * t.scale),
                  child: Column(
                    children: [
                      for (final (i, o) in list.take(rows).indexed)
                        if (i == rows - 1 && list.length > rows)
                          _MoreChip(day: c.day, count: list.length - rows + 1, height: chipH)
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

class _MoreChip extends ConsumerWidget {
  const _MoreChip({required this.day, required this.count, required this.height});
  final LocalDate day;
  final int count;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    return DPressable(
      onTap: () => ref.read(calNavProvider.notifier).show(day, view: CalView.day),
      semanticLabel: '$count more on ${weekdayShort(day)}',
      borderRadius: BorderRadius.circular(10 * t.scale),
      child: Container(
        height: height,
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.symmetric(horizontal: t.space.xs),
        child: Text('+$count more', style: t.text.caption.copyWith(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

typedef _LiftCallback = void Function(PlacedItem<Occurrence> placed, LongPressStartDetails details, {required bool resize});

class _DayColumn extends ConsumerWidget {
  const _DayColumn({
    required this.column,
    required this.placed,
    required this.hourH,
    required this.ctx,
    required this.lifted,
    required this.onLift,
    required this.onDrag,
    required this.onDrop,
    required this.onCancel,
  });
  final GridColumn column;
  final List<PlacedItem<Occurrence>> placed;
  final double hourH;
  final EventContext ctx;

  /// Key of the event lifted from this column (drawn as a ghost).
  final String? lifted;
  final _LiftCallback onLift;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDrop;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final day = column.day;
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
            profileIds: [?column.person?.id],
            sourceId: ref.read(defaultCalendarProvider)?.id ?? Ids.familyCalendar,
          ));
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (isToday) Positioned.fill(child: ColoredBox(color: t.colors.accent.withValues(alpha: t.colors.isDark ? 0.06 : 0.035))),
            for (final p in placed)
              Builder(builder: (context) {
                final height = math.max((p.endMin - p.startMin) / 60 * hourH - 2, 22 * t.scale);
                return Positioned(
                  top: p.startMin / 60 * hourH + 1,
                  height: height,
                  left: p.leftFraction * w + 2 * t.scale,
                  width: p.widthFraction * w - 4 * t.scale,
                  child: RawGestureDetector(
                    gestures: {
                      LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                        () => LongPressGestureRecognizer(duration: const Duration(milliseconds: 600)),
                        (r) => r
                          // Near the bottom edge resizes; anywhere else moves.
                          ..onLongPressStart = (d) {
                            onLift(p, d, resize: d.localPosition.dy > height - math.min(20 * t.scale, height / 3));
                          }
                          ..onLongPressMoveUpdate = (d) {
                            onDrag(d.globalPosition);
                          }
                          ..onLongPressEnd = (_) {
                            onDrop();
                          }
                          ..onLongPressCancel = onCancel,
                      ),
                    },
                    child: _EventBlock(occurrence: p.value, ctx: ctx, height: height, ghost: lifted == p.value.key),
                  ),
                );
              }),
            if (isToday) Positioned.fill(child: _NowLine(hourH: hourH)),
          ],
        ),
      );
    });
  }
}

class _EventBlock extends ConsumerWidget {
  const _EventBlock({required this.occurrence, required this.ctx, required this.height, this.ghost = false, this.lifted = false, this.timeLabel});
  final Occurrence occurrence;
  final EventContext ctx;
  final double height;

  /// The spot a lifted event left (faded).
  final bool ghost;

  /// Drawn under the finger while moving: raised, with a resize grip.
  final bool lifted;

  /// Replaces the time line while dragging (the time it will land on).
  final String? timeLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final o = occurrence;
    final p = eventPalette(t, o, ctx.people, ctx.sources);
    final time = ref.watch(householdTimeProvider);
    final h24 = ref.watch(clock24Provider);
    // As many title lines as fit above the time line: narrow lanes wrap
    // titles, and a block never overflows its slot.
    final titleStyle = t.text.label.copyWith(color: p.ink, fontWeight: FontWeight.w800);
    final timeStyle = t.text.caption.copyWith(fontSize: 13 * t.scale, color: p.ink.withValues(alpha: 0.85), fontWeight: lifted ? FontWeight.w800 : null);
    final titleLine = titleStyle.fontSize! * (titleStyle.height ?? 1.25);
    final timeLine = timeStyle.fontSize! * (timeStyle.height ?? 1.25);
    final border = lifted ? 2.0 : 1.0;
    final inner = height - 6 * t.scale - 2 * border; // padding and the border's inset
    final twoRows = inner >= titleLine + timeLine;
    final lines = twoRows ? ((inner - timeLine) / titleLine).floor().clamp(1, 3) : 1;
    final title = Text(o.event.title, style: titleStyle, maxLines: lines, overflow: TextOverflow.ellipsis);
    final times = Text(timeLabel ?? formatTimeRange(time.wall(o.startMs), time.wall(o.endMs), h24: h24), style: timeStyle, maxLines: 1, overflow: TextOverflow.ellipsis);
    final emoji = eventEmoji(o.event, learned: ctx.learned);
    final block = Container(
      decoration: BoxDecoration(
        color: ghost ? p.tint.withValues(alpha: 0.4) : p.tint,
        borderRadius: BorderRadius.circular(10 * t.scale),
        border: Border.all(color: lifted ? p.solid : t.colors.surfaceRaised, width: border),
        boxShadow: lifted ? t.elevation.e2 : null,
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StripedEdge(colors: p.stripes, width: 5 * t.scale, radius: 0),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6 * t.scale, vertical: 3 * t.scale),
                  child: twoRows
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: lines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                              children: [DEmoji(emoji, size: 22 * t.scale), SizedBox(width: 4 * t.scale), Expanded(child: title)],
                            ),
                            if (timeLabel != null)
                              times
                            else
                              // The forecast joins the time where the lane has room.
                              LayoutBuilder(
                                builder: (context, box) => Row(
                                  children: [
                                    Flexible(child: times),
                                    if (box.maxWidth >= 150 * t.scale) ...[SizedBox(width: 4 * t.scale), EventWeather(occurrence: o, size: 14 * t.scale, color: p.ink)],
                                  ],
                                ),
                              ),
                          ],
                        )
                      // Short and lifted: the time it will land on matters most.
                      : Row(children: [DEmoji(emoji, size: 18 * t.scale), SizedBox(width: 4 * t.scale), Expanded(child: timeLabel != null ? times : title)]),
                ),
              ),
            ],
          ),
          if (lifted)
            Positioned(
              left: 0,
              right: 0,
              bottom: 3 * t.scale,
              child: Center(
                child: Container(width: 28 * t.scale, height: 4 * t.scale, decoration: BoxDecoration(color: p.ink.withValues(alpha: 0.45), borderRadius: t.radius.pill)),
              ),
            ),
        ],
      ),
    );
    if (lifted) return block;
    return DPressable(
      id: 'event.block.${o.event.id}',
      onTap: () => showEventSheet(context, ref, o),
      semanticLabel: '${o.event.title}, ${formatTime(time.wall(o.startMs), h24: h24)}',
      borderRadius: BorderRadius.circular(10 * t.scale),
      child: block,
    );
  }
}

/// The event under the finger: raised, slightly larger, showing the time it
/// will land on (FR-CAL-14 visual feedback).
class _LiftedBlock extends ConsumerWidget {
  const _LiftedBlock({required this.drag, required this.columns, required this.gutter, required this.hourH, required this.ctx});
  final _Drag drag;
  final List<GridColumn> columns;
  final double gutter;
  final double hourH;
  final EventContext ctx;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final time = ref.watch(householdTimeProvider);
    final h24 = ref.watch(clock24Provider);
    final label = _dragLabel(time, drag, columns, h24: h24);
    return IgnorePointer(
      child: LayoutBuilder(builder: (context, box) {
        final colW = (box.maxWidth - gutter) / columns.length;
        final top = math.max(drag.newStart, 0) / 60 * hourH;
        final bottom = math.min(drag.newEnd, 24 * 60) / 60 * hourH;
        return Stack(
          children: [
            Positioned(
              left: gutter + drag.targetColumn * colW,
              width: colW,
              top: top,
              height: math.max(bottom - top, 28 * t.scale),
              child: Transform.scale(
                scale: 1.03,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2 * t.scale),
                  child: tid('cal.drag', _EventBlock(occurrence: drag.occurrence, ctx: ctx, height: math.max(bottom - top, 28 * t.scale), lifted: true, timeLabel: label)),
                ),
              ),
            ),
          ],
        );
      }),
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
  _GridPainter({
    required this.hourH,
    required this.gutter,
    required this.columns,
    required this.groupEvery,
    required this.line,
    required this.halfLine,
    required this.groupLine,
    required this.label,
    required this.h24,
  });
  final double hourH;
  final double gutter;
  final int columns;

  /// Draws a stronger line every [groupEvery] columns (day groups in the
  /// three-day People view); 0 = none.
  final int groupEvery;
  final Color line;
  final Color halfLine;
  final Color groupLine;
  final TextStyle label;
  final bool h24;

  @override
  void paint(Canvas canvas, Size size) {
    final full = Paint()..color = line;
    final half = Paint()..color = halfLine;
    final group = Paint()..color = groupLine;
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
      final strong = groupEvery > 0 && i > 0 && i % groupEvery == 0;
      canvas.drawRect(Rect.fromLTWH(gutter + i * colW - (strong ? 1 : 0), 0, strong ? 2 : 1, size.height), strong ? group : full);
    }
  }

  @override
  bool shouldRepaint(_GridPainter o) =>
      o.hourH != hourH || o.gutter != gutter || o.columns != columns || o.groupEvery != groupEvery || o.line != line || o.groupLine != groupLine || o.label != label || o.h24 != h24;
}
