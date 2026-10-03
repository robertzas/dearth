import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/data/household.dart';
import '../../core/format.dart';
import 'event_sheet.dart';
import 'event_visuals.dart';

/// One event in a list (Home agenda, Agenda view, day sheets).
class AgendaRow extends ConsumerWidget {
  const AgendaRow({super.key, required this.occurrence, required this.ctx, this.past = false, this.dense = false, this.showPeople = true});

  final Occurrence occurrence;
  final EventContext ctx;
  final bool past;
  final bool dense;
  final bool showPeople;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final c = t.colors;
    final o = occurrence;
    final time = ref.watch(householdTimeProvider);
    final h24 = ref.watch(clock24Provider);
    final palette = eventPalette(t, o, ctx.people, ctx.sources);
    final people = [for (final id in o.profileIds) ?ctx.people[id]];
    final emoji = eventEmoji(o.event, learned: ctx.learned);
    final ink = past ? c.inkTertiary : c.inkPrimary;
    final start = time.wall(o.startMs);
    final timeLabel = o.allDay ? 'All day' : formatTime(start, h24: h24).replaceAll(RegExp(r' [AP]M$'), '');
    final meridiem = o.allDay || h24 ? null : formatMeridiem(start);
    final meta = <String>[
      if (!o.allDay) formatDuration(((o.endMs - o.startMs) / 60000).round()),
      if (o.isMultiDay && o.allDay) '${o.startDate!.daysUntil(o.endDate!)} days',
      if (o.event.location != null) o.event.location!,
      if (!showPeople && people.isNotEmpty) people.map((p) => p.name).join(', '),
    ];
    final rowH = (dense ? 60 : 72) * t.scale;
    // The row speaks for its children (excludeSemantics), forecast included.
    final forecast = past ? null : watchEventForecast(ref, o);

    return DPressable(
      id: 'event.${o.event.id}',
      semanticLabel: [
        o.event.title,
        o.allDay ? 'all day' : formatTime(start, h24: h24),
        if (forecast != null) 'forecast ${describeEventForecast(forecast, imperial: ref.watch(imperialProvider), separator: ', ')}',
      ].join(', '),
      onTap: () => showEventSheet(context, ref, o),
      excludeSemantics: true,
      borderRadius: t.radius.card,
      pressedScale: 0.985,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: rowH),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: t.space.xs),
          child: Row(
            children: [
              SizedBox(
                width: (dense ? 64 : 76) * t.scale,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(timeLabel, style: (o.allDay ? t.text.caption.copyWith(fontWeight: FontWeight.w800) : t.text.numeral).copyWith(color: past ? c.inkTertiary : null)),
                    if (meridiem != null) Text(meridiem, style: t.text.caption.copyWith(fontSize: 13 * t.scale, color: past ? c.inkTertiary : null)),
                  ],
                ),
              ),
              SizedBox(width: t.space.sm),
              SizedBox(height: rowH - t.space.md, child: StripedEdge(colors: past ? [c.outline] : palette.stripes, width: 5 * t.scale)),
              SizedBox(width: t.space.sm),
              DEmoji(emoji, size: (dense ? 32 : 40) * t.scale),
              SizedBox(width: t.space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      o.event.title,
                      style: (dense ? t.text.body : t.text.title.copyWith(fontSize: 24 * t.scale)).copyWith(color: ink, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (meta.isNotEmpty)
                      Text(meta.join(' · '), style: t.text.caption.copyWith(color: past ? c.inkTertiary : null), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (forecast != null) ...[SizedBox(width: t.space.xs), EventWeather(occurrence: o, size: (dense ? 24 : 28) * t.scale)],
              if (showPeople && people.isNotEmpty) ...[SizedBox(width: t.space.xs), AvatarStack(people: people, size: (dense ? 30 : 36) * t.scale)],
            ],
          ),
        ),
      ),
    );
  }
}

/// The "now" divider between past and upcoming events.
class NowDivider extends StatelessWidget {
  const NowDivider({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final c = t.colors.danger;
    return tid(
      'agenda.now',
      Padding(
        padding: EdgeInsets.symmetric(vertical: t.space.xxs),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: t.space.xs, vertical: 2 * t.scale),
              decoration: BoxDecoration(color: c, borderRadius: t.radius.pill),
              child: Text(label, style: t.text.caption.copyWith(fontSize: 13 * t.scale, color: Colors.white, fontWeight: FontWeight.w800)),
            ),
            Expanded(child: Container(height: 2 * t.scale, color: c)),
          ],
        ),
      ),
    );
  }
}
