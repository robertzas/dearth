import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/data/calendar.dart';
import '../../core/data/household.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../calendar/agenda_row.dart';
import '../calendar/calendar_state.dart';
import '../calendar/event_editor.dart';
import '../calendar/event_ops.dart';
import '../calendar/event_sheet.dart';
import '../calendar/event_visuals.dart';
import 'home_card.dart';

/// Today's agenda with a now-line, then tomorrow (SPEC §11.7 TODAY column).
class AgendaCard extends ConsumerWidget {
  const AgendaCard({super.key, this.days = const [0, 1], this.expand = true, this.title});

  /// Offsets from today to show (0 = today).
  final List<int> days;
  final bool expand;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final today = ref.watch(todayProvider);
    final async = ref.watch(soonOccurrencesProvider);
    final filter = ref.watch(calendarFilterProvider).value ?? const <String>{};
    final time = ref.watch(householdTimeProvider);
    final now = ref.watch(nowMinuteMsProvider);
    final h24 = ref.watch(clock24Provider);
    final ctx = EventContext.watch(ref);
    final all = (async.value ?? const <Occurrence>[]).where((o) => passesFilter(o, filter)).toList();
    final byDay = groupByDay(all, DayRange(today, 3), time);

    final children = <Widget>[];
    for (final offset in days) {
      final day = today.addDays(offset);
      final items = byDay[day] ?? const <Occurrence>[];
      // The card title already names the first day.
      if (offset != days.first) {
        children.add(Padding(
          padding: EdgeInsets.only(top: children.isEmpty ? 0 : t.space.md, bottom: t.space.xxs),
          child: Row(
            children: [
              Text(relativeDayName(day, today).toUpperCase(), style: t.text.overline),
              SizedBox(width: t.space.xs),
              Text(monthDay(day), style: t.text.caption),
            ],
          ),
        ));
      }
      if (items.isEmpty) {
        children.add(Padding(
          padding: EdgeInsets.symmetric(vertical: t.space.sm),
          child: Text(offset == 0 ? 'Nothing on the calendar today' : 'Nothing planned', style: t.text.body.copyWith(color: t.colors.inkTertiary)),
        ));
        continue;
      }
      var nowShown = offset != 0;
      for (final o in items) {
        final past = offset == 0 && !o.allDay && o.endMs <= now;
        if (!nowShown && !o.allDay && o.startMs > now) {
          children.add(NowDivider(label: formatTime(time.wall(now), h24: h24)));
          nowShown = true;
        }
        children.add(AgendaRow(occurrence: o, ctx: ctx, past: past, dense: t.isPhone));
      }
      if (!nowShown && items.isNotEmpty) children.add(NowDivider(label: formatTime(time.wall(now), h24: h24)));
    }

    final list = expand
        ? ListView(padding: EdgeInsets.zero, children: children)
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
    return HomeCard(
      id: days.first == 0 ? 'home.agenda' : 'home.agenda.later',
      title: title ?? 'Today',
      expand: expand,
      onTitleTap: () {
        ref.read(calNavProvider.notifier).show(today, view: CalView.day);
        context.go('/calendar');
      },
      trailing: DIconButton(
        icon: Icons.add_rounded,
        label: 'Add event',
        id: 'home.agenda.add',
        tone: DButtonTone.tonal,
        size: 44 * t.scale,
        onPressed: () => showEventEditor(context, ref),
      ),
      child: list,
    );
  }
}

/// The next event with a live countdown and conflict warning (FR-CAL-16).
class UpNextCard extends ConsumerWidget {
  const UpNextCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final c = t.colors;
    final next = ref.watch(upNextProvider);
    final now = ref.watch(nowMinuteMsProvider);
    final time = ref.watch(householdTimeProvider);
    final h24 = ref.watch(clock24Provider);
    final ctx = EventContext.watch(ref);
    final today = ref.watch(todayProvider);

    if (next == null) {
      return const HomeCard(
        id: 'home.upnext',
        title: 'Up next',
        child: DEmptyState(emoji: '🌤️', title: 'Nothing else coming up', message: 'Enjoy the free time!', compact: true),
      );
    }
    final o = next.occurrence;
    final palette = eventPalette(t, o, ctx.people, ctx.sources);
    final people = [for (final id in o.profileIds) ?ctx.people[id]];
    final day = time.dateOfMs(o.startMs);
    final happening = o.startMs <= now;
    final countdown = happening ? 'Happening now' : formatIn(now, o.startMs);
    final dayPrefix = day == today ? '' : '${relativeDayName(day, today)} · ';

    return HomeCard(
      id: 'home.upnext',
      title: 'Up next',
      color: palette.tint,
      onTap: () => showEventSheet(context, ref, o),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              DEmoji(eventEmoji(o.event, learned: ctx.learned), size: 64 * t.scale),
              SizedBox(width: t.space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    tid('home.upnext.title', Text(o.event.title, style: t.text.h2, maxLines: 2, overflow: TextOverflow.ellipsis)),
                    tid(
                      'home.upnext.countdown',
                      Text(countdown, style: t.text.title.copyWith(color: happening ? c.success : palette.ink, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: t.space.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$dayPrefix${formatTimeRange(time.wall(o.startMs), time.wall(o.endMs), h24: h24)}${o.event.location == null ? '' : ' · ${o.event.location}'}',
                  style: t.text.body.copyWith(color: c.inkSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (people.isNotEmpty) AvatarStack(people: people, size: 36 * t.scale),
            ],
          ),
          if (next.conflicts.isNotEmpty) ...[
            SizedBox(height: t.space.sm),
            DBanner(
              id: 'home.upnext.conflict',
              tone: DBannerTone.warning,
              emoji: '⚠️',
              title: 'Double-booked',
              message: 'Overlaps ${next.conflicts.map((x) => x.event.title).join(', ')}',
            ),
          ],
        ],
      ),
    );
  }
}

/// Whether an occurrence is a (possibly edited) instance of a series.
bool occurrenceRepeats(Occurrence o) => isRecurring(o);
