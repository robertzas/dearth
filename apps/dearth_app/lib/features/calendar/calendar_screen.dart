import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/data/calendar.dart';
import '../../core/data/household.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import 'calendar_state.dart';
import 'event_editor.dart';
import 'event_ops.dart';
import 'quick_add.dart';
import 'views/agenda_view.dart';
import 'views/month_view.dart';
import 'views/time_grid.dart';

/// The calendar (SPEC §10.2): day, 3-day, week, month and agenda views with
/// person filters, quick add and the full editor.
class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final nav = ref.watch(calNavProvider);
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final view = nav.view ?? (landscape && !t.isPhone ? CalView.week : CalView.agenda);
    final weekStart = ref.watch(weekStartProvider);
    final range = visibleRange(view, nav.anchor, weekStart);
    final controller = ref.read(calNavProvider.notifier);

    final title = switch (view) {
      CalView.month => monthYear(nav.anchor),
      CalView.agenda => 'From ${monthDay(range.start)}',
      CalView.day => longDate(range.start),
      _ => formatDateSpan(range.start, range.end.addDays(-1)),
    };
    final views = [
      CalView.day,
      CalView.threeDay,
      if (!t.isPhone || landscape) CalView.week,
      CalView.month,
      CalView.agenda,
    ];

    final nav3 = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DIconButton(icon: Icons.chevron_left_rounded, label: 'Previous', id: 'cal.prev', onPressed: () => controller.step(view, -1)),
        SizedBox(width: t.space.xs),
        DIconButton(icon: Icons.chevron_right_rounded, label: 'Next', id: 'cal.next', onPressed: () => controller.step(view, 1)),
        SizedBox(width: t.space.sm),
        DButton(label: 'Today', tone: DButtonTone.tonal, size: DButtonSize.sm, id: 'cal.today', onPressed: controller.today),
      ],
    );
    final switcher = DSegmented<CalView>(
      idPrefix: 'cal.view',
      dense: t.isPhone,
      options: [for (final v in views) (v, v.label)],
      value: view,
      onChanged: controller.setView,
    );

    final body = switch (view) {
      CalView.month => MonthView(anchor: nav.anchor, range: range),
      CalView.agenda => AgendaView(start: range.start),
      _ => TimeGrid(range: range, key: ValueKey('grid-${view.name}')),
    };

    return tid(
      'screen.calendar',
      Padding(
        padding: EdgeInsets.fromLTRB(t.pageMargin, t.pageMargin, t.pageMargin, t.isPhone ? 0 : t.pageMargin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (t.isPhone) ...[
              Row(
                children: [
                  Expanded(child: tid('cal.title', Text(title, style: t.text.title, maxLines: 1, overflow: TextOverflow.ellipsis))),
                  nav3,
                ],
              ),
              SizedBox(height: t.space.sm),
              SingleChildScrollView(scrollDirection: Axis.horizontal, child: switcher),
            ] else ...[
              Row(
                children: [
                  nav3,
                  SizedBox(width: t.space.lg),
                  Expanded(child: tid('cal.title', Text(title, style: t.text.h2, maxLines: 1, overflow: TextOverflow.ellipsis))),
                  switcher,
                  SizedBox(width: t.space.md),
                  DButton(label: 'Add', icon: Icons.add_rounded, id: 'cal.add', onPressed: () => showEventEditor(context, ref, draft: _draftFor(ref, nav.anchor))),
                ],
              ),
              SizedBox(height: t.space.md),
              Row(
                children: [
                  const Expanded(child: _FilterChips()),
                  SizedBox(width: t.space.md),
                  SizedBox(width: 520 * t.scale, child: const QuickAddField()),
                ],
              ),
            ],
            if (t.isPhone) ...[SizedBox(height: t.space.sm), const _FilterChips()],
            SizedBox(height: t.space.md),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragEnd: view == CalView.agenda
                    ? null
                    : (d) {
                        final v = d.primaryVelocity ?? 0;
                        if (v.abs() > 350) controller.step(view, v < 0 ? 1 : -1);
                      },
                child: body,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

EventDraft _draftFor(WidgetRef ref, LocalDate date) {
  final today = ref.read(todayProvider);
  return EventDraft(
    title: '',
    date: date.isBefore(today) ? today : date,
    sourceId: ref.read(defaultCalendarProvider)?.id ?? Ids.familyCalendar,
  );
}

/// Person filter chips, persisted per device (FR-CAL-11).
class _FilterChips extends ConsumerWidget {
  const _FilterChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final people = ref.watch(familyProvider);
    final filter = ref.watch(calendarFilterProvider).value ?? const <String>{};
    final db = ref.read(dbProvider);
    if (people.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          DChip(id: 'cal.filter.all', label: 'Everyone', selected: filter.isEmpty, dense: t.isPhone, onTap: () => setCalendarFilter(db, const {})),
          for (final p in people) ...[
            SizedBox(width: t.space.xs),
            DChip(
              id: 'cal.filter.${p.id}',
              label: p.name,
              emoji: p.emoji,
              dense: t.isPhone,
              personColor: t.person(p.color),
              selected: filter.contains(p.id),
              onTap: () {
                final next = {...filter};
                next.contains(p.id) ? next.remove(p.id) : next.add(p.id);
                setCalendarFilter(db, next);
              },
            ),
          ],
        ],
      ),
    );
  }
}
