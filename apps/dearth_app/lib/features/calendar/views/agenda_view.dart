import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/calendar.dart';
import '../../../core/data/household.dart';
import '../../../core/format.dart';
import '../../../core/providers.dart';
import '../agenda_row.dart';
import '../event_visuals.dart';

/// Continuous list grouped by day with pinned day headers (FR-CAL-08).
/// Extends further into the future as you scroll.
class AgendaView extends ConsumerStatefulWidget {
  const AgendaView({super.key, required this.start});
  final LocalDate start;

  @override
  ConsumerState<AgendaView> createState() => _AgendaViewState();
}

class _AgendaViewState extends ConsumerState<AgendaView> {
  int _days = 60;

  @override
  void didUpdateWidget(AgendaView old) {
    super.didUpdateWidget(old);
    if (old.start != widget.start) _days = 60;
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final range = DayRange(widget.start, _days);
    final time = ref.watch(householdTimeProvider);
    final today = ref.watch(todayProvider);
    final now = ref.watch(nowMinuteMsProvider);
    final filter = ref.watch(calendarFilterProvider).value ?? const <String>{};
    final async = ref.watch(occurrencesProvider(range));
    final ctx = EventContext.watch(ref);
    final occ = async.value ?? const <Occurrence>[];
    final byDay = groupByDay([for (final o in occ) if (passesFilter(o, filter)) o], range, time);
    final days = [for (final d in range.dates) if (byDay[d]!.isNotEmpty || d == today) d];

    return NotificationListener<ScrollEndNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 600 && _days < 400) setState(() => _days += 60);
        return false;
      },
      child: CustomScrollView(
        slivers: [
          for (final d in days)
            SliverMainAxisGroup(
              slivers: [
                SliverPersistentHeader(pinned: true, delegate: _DayHeader(day: d, today: today, theme: t)),
                SliverPadding(
                  padding: EdgeInsets.only(bottom: t.space.sm),
                  sliver: SliverList.list(
                    children: byDay[d]!.isEmpty
                        ? [
                            Padding(
                              padding: EdgeInsets.all(t.space.md),
                              child: Text('Nothing planned today', style: t.text.body.copyWith(color: t.colors.inkTertiary)),
                            ),
                          ]
                        : [
                            for (final o in byDay[d]!)
                              AgendaRow(occurrence: o, ctx: ctx, past: d == today && !o.allDay && o.endMs <= now, dense: t.isPhone),
                          ],
                  ),
                ),
              ],
            ),
          if (days.isEmpty && async.hasValue)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: DEmptyState(emoji: '🗓️', title: 'Nothing coming up', message: 'Add an event with the + button or quick add.'),
            ),
          SliverToBoxAdapter(child: SizedBox(height: t.space.xxl)),
        ],
      ),
    );
  }
}

class _DayHeader extends SliverPersistentHeaderDelegate {
  _DayHeader({required this.day, required this.today, required this.theme});
  final LocalDate day;
  final LocalDate today;
  final DTheme theme;

  double get _h => 52 * theme.scale;

  @override
  double get minExtent => _h;
  @override
  double get maxExtent => _h;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final t = theme;
    final isToday = day == today;
    return tid(
      'agenda.day.${day.iso}',
      Container(
        color: t.colors.surface,
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Text(
              relativeDayName(day, today),
              style: t.text.title.copyWith(color: isToday ? t.colors.accent : null, fontWeight: FontWeight.w800),
            ),
            SizedBox(width: t.space.sm),
            Text(monthDay(day), style: t.text.body.copyWith(color: t.colors.inkSecondary)),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_DayHeader old) => old.day != day || old.today != today || old.theme != theme;
}
