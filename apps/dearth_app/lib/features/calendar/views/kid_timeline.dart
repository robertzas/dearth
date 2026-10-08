import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/display_state.dart';
import '../../../core/data/calendar.dart';
import '../../../core/data/household.dart';
import '../../../core/format.dart';
import '../../../core/providers.dart';
import '../../../shared/face_photo.dart';
import '../../kids/routine_run.dart';
import '../event_visuals.dart';
import '../kid_day.dart';

/// The kid timeline view (SPEC FR-CAL-10): one picture timeline per kid for
/// a day. The calendar's person filter picks whose; a household without
/// kids sees the family's day.
class KidTimelineView extends ConsumerWidget {
  const KidTimelineView({super.key, required this.date});
  final LocalDate date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final kids = ref.watch(kidsProvider);
    final family = ref.watch(familyProvider);
    final filter = ref.watch(calendarFilterProvider).value ?? const <String>{};
    final people = <Profile?>[
      if (filter.isEmpty) ...kids else ...family.where((p) => filter.contains(p.id) && p.role != ProfileRole.pet),
    ];
    if (people.isEmpty) people.add(null);
    return ListView.separated(
      itemCount: people.length,
      separatorBuilder: (_, _) => SizedBox(height: t.gutter),
      itemBuilder: (context, i) {
        final p = people[i];
        return DCard(
          padding: EdgeInsets.all(t.space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (p != null) ...[ProfileAvatar(p, size: 40 * t.scale), SizedBox(width: t.space.sm)],
                  Expanded(child: Text(p == null ? 'Our day' : '${p.name}’s day', style: t.text.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
              SizedBox(height: t.space.sm),
              KidTimeline(kid: p, date: date),
            ],
          ),
        );
      },
    );
  }
}

/// One kid's day as big pictures in morning, afternoon and evening bands,
/// with the sun (or the moon, after dark) marking now (SPEC FR-CAL-10).
/// Pre-readers follow order, not clock faces: pictures are evenly spaced in
/// their part of the day, and the path fills in as the day goes by. Runs left
/// to right where there's room, top to bottom on narrow screens.
class KidTimeline extends ConsumerWidget {
  const KidTimeline({super.key, required this.kid, required this.date, this.compact = false});

  /// Null: the whole family.
  final Profile? kid;
  final LocalDate date;

  /// Smaller pictures, for the Kids screen.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final id = 'timeline.${kid?.id ?? 'family'}';
    final day = ref.watch(kidDayProvider((kid?.id, date)));
    final (wake, bedtime) = ref.watch(kidDayBoundsProvider);
    final time = ref.watch(householdTimeProvider);
    final today = ref.watch(todayProvider);
    final nowMs = ref.watch(nowMinuteMsProvider);
    // Before today everything is done; after today, nothing is.
    final now = date == today ? time.minuteOfDay(nowMs) : (date.isBefore(today) ? 24 * 60 : -1);
    final layout = layoutKidTimeline([for (final s in day.stops) s.span], wake: wake, bedtime: bedtime);
    final ctx = EventContext.watch(ref);
    final night = !ref.watch(isDaylightProvider);
    final h24 = ref.watch(clock24Provider);

    final g = _Geometry(t, compact);
    final timeline = LayoutBuilder(builder: (context, box) {
      // The compact strip stays one row: on a phone it scrolls sideways
      // rather than pushing the chart below it off the screen.
      final vertical = !compact && box.maxWidth < 560 * t.scale;
      // Long enough that every picture gets its slot; scrolls past the screen.
      var length = vertical ? 0.0 : box.maxWidth;
      for (final b in layout.bands) {
        if (b.count > 0) length = math.max(length, b.count * g.slot / (b.to - b.from));
      }
      if (vertical) length = math.max(length, 3 * g.slot);
      final across = vertical ? box.maxWidth : g.across;
      final size = vertical ? Size(across, length) : Size(length, across);
      Offset at(double along, double cross) => vertical ? Offset(cross, along) : Offset(along, cross);
      final pathCross = g.markerLane + g.circle / 2 + (vertical ? 0 : g.header);
      final markerCross = g.markerLane / 2 + (vertical ? 0 : g.header);
      final nowAt = date == today ? layout.at(now) * length : (date.isBefore(today) ? length : 0.0);
      final marker = at(nowAt, markerCross);

      final stops = <Widget>[];
      for (var i = 0; i < day.stops.length; i++) {
        final s = day.stops[i];
        final band = layout.bands.firstWhere((b) => b.part == s.span.part);
        final slot = (band.to - band.from) * length / band.count;
        final c = at(layout.centers[i] * length, pathCross);
        // Down the side, a stop is its row; along the top, it takes the
        // height its picture and two lines of text need.
        stops.add(Positioned(
          left: vertical ? c.dx - g.circle / 2 : c.dx - slot / 2,
          top: vertical ? c.dy - slot / 2 : c.dy - g.circle / 2,
          width: vertical ? across - (c.dx - g.circle / 2) : slot,
          height: vertical ? slot : null,
          child: _Stop(
            id: '$id.stop.${s.id}',
            stop: s,
            vertical: vertical,
            geometry: g,
            palette: _paletteFor(t, s, ctx, kid),
            done: s.doneBy(now),
            running: date == today && s.runningAt(now),
            timeLabel: formatTime(time.wall(time.startOfDayMs(date) + s.span.start * 60000), h24: h24, compact: true),
            onTap: () => showKidStop(context, ref, s, kid: kid, date: date),
          ),
        ));
      }

      final children = <Widget>[
        for (final b in layout.bands)
          Positioned.fromRect(
            rect: vertical
                ? Rect.fromLTWH(0, b.from * length + 2 * t.scale, across, (b.to - b.from) * length - 4 * t.scale)
                : Rect.fromLTWH(b.from * length + 2 * t.scale, 0, (b.to - b.from) * length - 4 * t.scale, across),
            child: _Band(part: b.part, vertical: vertical),
          ),
        Positioned.fill(
          child: CustomPaint(
            painter: _PathPainter(
              vertical: vertical,
              cross: pathCross,
              done: nowAt,
              marker: date == today ? markerCross : null,
              doneColor: t.colors.accent,
              aheadColor: t.colors.outline,
              width: (compact ? 4 : 5) * t.scale,
            ),
          ),
        ),
        ...stops,
        if (date == today)
          Positioned(
            left: marker.dx - g.marker / 2,
            top: marker.dy - g.marker / 2,
            child: tid(
              '$id.now',
              Semantics(
                label: 'Now, ${formatTime(time.wall(nowMs), h24: h24)}',
                excludeSemantics: true,
                child: RepaintBoundary(child: _NowMarker(size: g.marker, emoji: night ? '🌙' : '☀️')),
              ),
            ),
          ),
      ];
      final body = SizedBox(width: size.width, height: size.height, child: Stack(clipBehavior: Clip.none, children: children));
      if (vertical || length <= box.maxWidth) return body;
      // Too long for the screen: it opens with now a third of the way in.
      return SizedBox(height: size.height, child: _SidewaysScroll(start: (nowAt - box.maxWidth / 3).clamp(0, length - box.maxWidth), extent: length, child: body));
    });

    return tid(
      id,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (day.allDay.isNotEmpty) ...[
            Wrap(
              spacing: t.space.xs,
              runSpacing: t.space.xs,
              children: [
                for (final s in day.allDay)
                  DChip(id: '$id.allday.${s.id}', label: s.title, emoji: s.emoji, dense: compact, onTap: () => showKidStop(context, ref, s, kid: kid, date: date)),
              ],
            ),
            SizedBox(height: t.space.sm),
          ],
          if (day.stops.isEmpty && day.allDay.isEmpty)
            DEmptyState(id: '$id.empty', emoji: '🌈', title: 'A free day', message: 'Nothing on the calendar. Time to play!', compact: true)
          else
            timeline,
        ],
      ),
    );
  }
}

/// Pans a strip longer than the screen sideways with a finger, starting at
/// [start]. Not a scroll view: on the web, a sideways scrollable inside the
/// page's vertical one made the page drop the test ids of the nodes around it.
class _SidewaysScroll extends StatefulWidget {
  const _SidewaysScroll({required this.start, required this.extent, required this.child});
  final double start;

  /// The strip's full length.
  final double extent;
  final Widget child;

  @override
  State<_SidewaysScroll> createState() => _SidewaysScrollState();
}

class _SidewaysScrollState extends State<_SidewaysScroll> {
  late double _offset = widget.start;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final max = math.max(0.0, widget.extent - box.maxWidth);
        final offset = _offset.clamp(0.0, max);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: (d) => setState(() => _offset = (offset - d.delta.dx).clamp(0.0, max)),
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: widget.extent,
              maxWidth: widget.extent,
              child: Transform.translate(offset: Offset(-offset, 0), child: widget.child),
            ),
          ),
        );
      });
}

/// Sizes along and across the line.
class _Geometry {
  _Geometry(DTheme t, bool compact)
      : circle = (compact ? 64 : 88) * t.scale,
        slot = (compact ? 96 : 124) * t.scale,
        header = 28 * t.scale,
        markerLane = (compact ? 34 : 44) * t.scale,
        marker = (compact ? 30 : 38) * t.scale,
        labels = (compact ? 52 : 60) * t.scale;
  final double circle, slot, header, markerLane, marker, labels;

  /// Height of a left-to-right timeline.
  double get across => header + markerLane + circle + labels + 8;
}

EventPalette _paletteFor(DTheme t, KidStop s, EventContext ctx, Profile? kid) {
  final o = s.occurrence;
  if (o != null) return eventPalette(t, o, ctx.people, ctx.sources);
  final color = s.routine != null && kid != null ? t.person(kid.color).solid : t.colors.vizWarm;
  return EventPalette(solid: color, tint: t.colors.tintOf(color), ink: t.colors.inkPrimary, stripes: [color]);
}

/// A part of the day's stretch: a soft sky for the time of day.
class _Band extends StatelessWidget {
  const _Band({required this.part, required this.vertical});
  final DayPart part;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final c = t.colors;
    final hue = switch (part) { DayPart.morning => c.vizSun, DayPart.afternoon => c.vizCool, DayPart.evening => c.vizUv };
    return DecoratedBox(
      decoration: BoxDecoration(color: c.tintOf(hue, 0.12), borderRadius: BorderRadius.circular(t.radius.s)),
      child: LayoutBuilder(
        // A part with nothing in it is narrow: its sun or moon says enough.
        builder: (context, box) => Align(
          alignment: vertical ? Alignment.topRight : Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: t.space.sm, vertical: t.space.xxs),
            child: Text(
              box.maxWidth < 110 * t.scale ? part.emoji : '${part.emoji} ${part.label}',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: t.text.caption.copyWith(color: c.inkSecondary, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

/// The line through the pictures: filled in up to now.
class _PathPainter extends CustomPainter {
  _PathPainter({required this.vertical, required this.cross, required this.done, required this.marker, required this.doneColor, required this.aheadColor, required this.width});
  final bool vertical;
  final double cross;
  final double done;

  /// Where the now marker sits across the line (today only): a short stem
  /// joins it to the line.
  final double? marker;
  final Color doneColor, aheadColor;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final length = vertical ? size.height : size.width;
    Offset at(double along, double c) => vertical ? Offset(c, along) : Offset(along, c);
    final paint = Paint()
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final pad = width * 2;
    canvas.drawLine(at(pad, cross), at(length - pad, cross), paint..color = aheadColor);
    if (done > pad) canvas.drawLine(at(pad, cross), at(done.clamp(pad, length - pad), cross), paint..color = doneColor);
    final m = marker;
    if (m != null) canvas.drawLine(at(done, m), at(done, cross), paint..color = doneColor);
  }

  @override
  bool shouldRepaint(_PathPainter old) =>
      old.done != done || old.cross != cross || old.marker != marker || old.vertical != vertical || old.doneColor != doneColor || old.aheadColor != aheadColor;
}

class _Stop extends StatelessWidget {
  const _Stop({
    required this.id,
    required this.stop,
    required this.vertical,
    required this.geometry,
    required this.palette,
    required this.done,
    required this.running,
    required this.timeLabel,
    required this.onTap,
  });
  final String id;
  final KidStop stop;
  final bool vertical;
  final _Geometry geometry;
  final EventPalette palette;
  final bool done, running;
  final String timeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final d = geometry.circle;
    final circle = SizedBox(
      width: d,
      height: d,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.tint,
                shape: BoxShape.circle,
                border: Border.all(color: running ? palette.solid : palette.solid.withValues(alpha: done ? 0.25 : 0.5), width: (running ? 5 : 2) * t.scale),
              ),
              child: Center(child: Opacity(opacity: done ? 0.45 : 1, child: DEmoji(stop.emoji, size: d * 0.5))),
            ),
          ),
          if (done)
            Positioned(
              right: -2 * t.scale,
              top: -2 * t.scale,
              child: Container(
                width: d * 0.34,
                height: d * 0.34,
                decoration: BoxDecoration(color: t.colors.success, shape: BoxShape.circle, border: Border.all(color: t.colors.surfaceRaised, width: 2 * t.scale)),
                child: Icon(Icons.check_rounded, size: d * 0.24, color: Colors.white),
              ),
            ),
        ],
      ),
    );
    final title = Text(
      stop.title,
      maxLines: vertical ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      textAlign: vertical ? TextAlign.start : TextAlign.center,
      style: t.text.label.copyWith(fontWeight: running ? FontWeight.w800 : FontWeight.w600, color: done ? t.colors.inkSecondary : t.colors.inkPrimary),
    );
    final when = Text(running ? 'Now' : timeLabel, maxLines: 1, style: t.text.caption.copyWith(color: running ? palette.ink : t.colors.inkSecondary, fontWeight: running ? FontWeight.w800 : null));
    final label = '${stop.title}, ${running ? 'now' : timeLabel}${done ? ', done' : ''}';
    return DPressable(
      id: id,
      semanticLabel: label,
      excludeSemantics: true,
      onTap: onTap,
      borderRadius: BorderRadius.circular(t.radius.s),
      child: vertical
          ? Row(
              children: [
                circle,
                SizedBox(width: t.space.sm),
                Expanded(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [title, when])),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [circle, SizedBox(height: t.space.xxs), title, when],
            ),
    );
  }
}

class _NowMarker extends StatelessWidget {
  const _NowMarker({required this.size, required this.emoji});
  final double size;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: t.colors.surfaceRaised, shape: BoxShape.circle, border: Border.all(color: t.colors.accent, width: 2.5 * t.scale)),
      alignment: Alignment.center,
      child: DEmoji(emoji, size: size * 0.62),
    );
  }
}

/// A picture, big, with when it is: for kids who can't read the time yet, and
/// the grown-up reading it to them. A routine can start from here. Nothing on
/// it changes anything else (kid surfaces, AGENTS.md rule 9).
Future<void> showKidStop(BuildContext context, WidgetRef ref, KidStop stop, {required Profile? kid, required LocalDate date}) {
  return showDSheet<void>(context, id: 'timeline.sheet', builder: (_) => _StopSheet(stop: stop, kid: kid, date: date));
}

class _StopSheet extends ConsumerWidget {
  const _StopSheet({required this.stop, required this.kid, required this.date});
  final KidStop stop;
  final Profile? kid;
  final LocalDate date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final time = ref.watch(householdTimeProvider);
    final h24 = ref.watch(clock24Provider);
    final nowMs = ref.watch(nowMinuteMsProvider);
    final today = ref.watch(todayProvider);
    final people = ref.watch(profileMapProvider);
    final startMs = time.startOfDayMs(date) + stop.span.start * 60000;
    final now = time.minuteOfDay(nowMs);
    final allDay = stop.occurrence?.allDay ?? false;
    final when = allDay
        ? relativeDayName(date, today)
        : date != today
            ? '${relativeDayName(date, today)} at ${formatTime(time.wall(startMs), h24: h24)}'
            : stop.runningAt(now)
                ? 'Now!'
                : stop.doneBy(now)
                    ? 'Done ✓'
                    : 'At ${formatTime(time.wall(startMs), h24: h24)} · ${formatIn(nowMs, startMs)}';
    final who = [for (final id in stop.people) ?people[id]];
    final routine = stop.routine;
    return Padding(
      padding: EdgeInsets.all(t.space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DEmoji(stop.emoji, size: 120 * t.scale),
          SizedBox(height: t.space.md),
          tid('timeline.sheet.title', Text(stop.title, textAlign: TextAlign.center, style: t.text.kidTitle)),
          SizedBox(height: t.space.xs),
          tid('timeline.sheet.when', Text(when, textAlign: TextAlign.center, style: t.text.title.copyWith(color: t.colors.inkSecondary))),
          if (who.isNotEmpty) ...[SizedBox(height: t.space.md), AvatarStack(people: who, size: 44 * t.scale)],
          if (routine != null && kid != null && date == today && !routine.done) ...[
            SizedBox(height: t.space.lg),
            DButton(
              label: 'Start',
              emoji: routine.routine.emoji ?? '⭐',
              size: DButtonSize.lg,
              id: 'timeline.sheet.start',
              onPressed: () {
                Navigator.of(context).pop();
                openRoutine(context, routine, kid!);
              },
            ),
          ],
        ],
      ),
    );
  }
}
