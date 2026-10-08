import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/data/calendar.dart';
import '../../core/data/household.dart';
import '../../core/data/household_data.dart';
import '../../core/format.dart';
import '../../shared/face_photo.dart';
import '../../shared/recipe_visual.dart';
import '../calendar/calendar_state.dart';
import '../calendar/event_sheet.dart';
import '../calendar/event_visuals.dart';
import '../kids/kids_data.dart';
import '../meals/meals_data.dart';
import '../meals/meals_screen.dart';
import '../meals/recipe_sheet.dart';
import 'home_card.dart';

// ────────────────────────────── Week strip ──────────────────────────────────

/// Seven days with weather and who's busy (SPEC §11.7 THIS WEEK).
class WeekStripCard extends ConsumerWidget {
  const WeekStripCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final c = t.colors;
    final today = ref.watch(todayProvider);
    final range = DayRange(today, 7);
    final occ = ref.watch(occurrencesProvider(range)).value ?? const <Occurrence>[];
    final time = ref.watch(householdTimeProvider);
    final report = ref.watch(weatherProvider).value;
    final imperial = ref.watch(imperialProvider);
    final people = ref.watch(profileMapProvider);
    final filter = ref.watch(calendarFilterProvider).value ?? const <String>{};
    final byDay = groupByDay([for (final o in occ) if (passesFilter(o, filter)) o], range, time);

    return HomeCard(
      id: 'home.week',
      title: 'This week',
      child: Row(
        children: [
          for (final d in range.dates)
            Expanded(
              child: Builder(builder: (context) {
                final items = byDay[d] ?? const <Occurrence>[];
                final wx = report?.dayFor(d.iso);
                final isToday = d == today;
                final dots = <Color>[
                  for (final o in items.take(4))
                    o.profileIds.isNotEmpty && people[o.profileIds.first] != null ? t.person(people[o.profileIds.first]!.color).solid : c.inkTertiary,
                ];
                return DPressable(
                  id: 'home.week.${d.iso}',
                  semanticLabel: '${weekdayLong(d)}, ${items.length} events',
                  excludeSemantics: true,
                  onTap: () {
                    ref.read(calNavProvider.notifier).show(d, view: CalView.day);
                    context.go('/calendar');
                  },
                  borderRadius: t.radius.card,
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: t.space.xs),
                    decoration: BoxDecoration(color: isToday ? c.accentTint : null, borderRadius: t.radius.card),
                    child: Column(
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(isToday ? 'Today' : weekdayShort(d), maxLines: 1, style: t.text.caption.copyWith(fontWeight: FontWeight.w800, color: isToday ? c.accent : null)),
                        ),
                        SizedBox(height: t.space.xxs),
                        DEmoji(wx == null ? '·' : conditionEmoji(wx.condition), size: 34 * t.scale),
                        SizedBox(height: t.space.xxs),
                        Text(wx?.highC == null ? '–' : formatTemp(wx!.highC, imperial: imperial), style: t.text.label.copyWith(fontWeight: FontWeight.w800)),
                        Text(wx?.lowC == null ? '' : formatTemp(wx!.lowC, imperial: imperial), style: t.text.caption),
                        SizedBox(height: t.space.xs),
                        SizedBox(height: 10 * t.scale, child: dots.isEmpty ? null : PeopleDots(colors: dots, size: 8 * t.scale)),
                      ],
                    ),
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }
}

// ──────────────────────────── Notes & countdowns ────────────────────────────

class NotesCard extends ConsumerWidget {
  const NotesCard({super.key, this.expand = false});
  final bool expand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final notes = ref.watch(activeNotesProvider);
    final countdowns = ref.watch(countdownsProvider).take(4).toList();
    final ctx = EventContext.watch(ref);
    final hasKids = ref.watch(kidsProvider).isNotEmpty;

    final children = <Widget>[
      for (final n in notes.take(4))
        Padding(
          padding: EdgeInsets.only(bottom: t.space.xs),
          child: tid(
            'home.note.${n.id}',
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
              decoration: BoxDecoration(
                color: n.kind == 'announcement' ? t.colors.accentTint : kNoteColors[n.color % kNoteColors.length],
                borderRadius: t.radius.card,
              ),
              child: Row(
                children: [
                  DEmoji(n.kind == 'announcement' ? '📣' : '📝', size: 28 * t.scale),
                  SizedBox(width: t.space.sm),
                  Expanded(
                    child: Text(
                      n.body,
                      style: t.text.body.copyWith(color: n.kind == 'announcement' ? null : kNoteInk, fontWeight: FontWeight.w600),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      for (final cd in countdowns)
        DPressable(
          id: 'home.countdown.${cd.occurrence.event.id}',
          onTap: () => showEventSheet(context, ref, cd.occurrence),
          borderRadius: t.radius.card,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: t.space.xs),
            child: Row(
              children: [
                DEmoji(eventEmoji(cd.occurrence.event, learned: ctx.learned), size: 34 * t.scale),
                SizedBox(width: t.space.sm),
                Expanded(child: Text(cd.occurrence.event.title, style: t.text.body.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(cd.days == 0 ? 'Today!' : (cd.days == 1 ? 'Tomorrow' : '${cd.days} days'), style: t.text.label.copyWith(color: t.colors.accent, fontWeight: FontWeight.w800)),
                    if (hasKids && cd.days > 0 && cd.sleeps <= 14)
                      Text('${cd.sleeps} ${cd.sleeps == 1 ? 'sleep' : 'sleeps'} ${'🌙' * cd.sleeps.clamp(1, 3)}', style: t.text.caption.copyWith(fontSize: 14 * t.scale)),
                  ],
                ),
              ],
            ),
          ),
        ),
    ];
    final content = children.isEmpty
        ? const DEmptyState(emoji: '📝', title: 'No notes yet', message: 'Announcements and countdowns show up here.', compact: true)
        : (expand ? ListView(padding: EdgeInsets.zero, children: children) : Column(mainAxisSize: MainAxisSize.min, children: children));
    return HomeCard(id: 'home.notes', title: 'Notes & countdowns', expand: expand && children.isNotEmpty, child: content);
  }
}

// ──────────────────────────────── Dinner ────────────────────────────────────

class DinnerCard extends ConsumerWidget {
  const DinnerCard({super.key, this.imageHeight});
  final double? imageHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final (tonight, tomorrow) = ref.watch(dinnerPreviewProvider);
    void openMeals() {
      ref.read(mealsTabProvider.notifier).show(MealsTab.plan);
      ref.read(mealWeekOffsetProvider.notifier).thisWeek();
      context.go('/meals');
    }

    if (tonight == null) {
      return HomeCard(
        id: 'home.dinner',
        title: 'Tonight',
        onTap: openMeals,
        child: DEmptyState(
          emoji: '🍽️',
          title: 'What’s for dinner?',
          message: tomorrow == null ? 'Plan meals to see them here.' : 'Tomorrow: ${tomorrow.title}',
          compact: true,
        ),
      );
    }
    final r = tonight.recipe;
    final minutes = r?.totalMin;
    return HomeCard(
      id: 'home.dinner',
      title: tonight.entry.slot == 'dinner' ? 'Tonight' : 'Today',
      onTitleTap: openMeals,
      onTap: r == null ? openMeals : () => showRecipeSheet(context, RecipeData.fromRow(r), entry: tonight.entry),
      padding: EdgeInsets.fromLTRB(t.space.lg, t.space.md, t.space.lg, t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          RecipeVisual(recipe: r, title: tonight.title, height: imageHeight ?? 150 * t.scale),
          SizedBox(height: t.space.sm),
          tid('home.dinner.title', Text(tonight.title, style: t.text.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text(
            [
              if (minutes != null) formatDuration(minutes),
              if (r?.cuisine != null) r!.cuisine!,
              if (tomorrow != null) 'Tomorrow: ${tomorrow.title}',
            ].join(' · '),
            style: t.text.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────── Kids ─────────────────────────────────────

/// Chore progress per kid (avatar rings) with today's picture cards.
class KidsCard extends ConsumerWidget {
  const KidsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final kids = ref.watch(kidsProvider);
    final chores = ref.watch(choresTodayProvider);
    if (kids.isEmpty) return const SizedBox.shrink();
    return HomeCard(
      id: 'home.kids',
      title: kids.length == 1 ? '${kids.first.name}’s day' : 'Kids',
      onTap: () {
        showKidsTab(ref, kids.first.id);
        context.go('/kids');
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final kid in kids)
            Builder(builder: (context) {
              final mine = [for (final c in chores) if (c.due.profileId == kid.id && !c.due.chore.adult) c];
              final done = mine.where((c) => c.done).length;
              final jar = ref.watch(balancesProvider(kid.id))[Currency.jar] ?? 0;
              return Padding(
                padding: EdgeInsets.only(bottom: t.space.xs),
                child: Row(
                  children: [
                    ProfileAvatar(kid, size: 56 * t.scale, progress: mine.isEmpty ? null : done / mine.length),
                    SizedBox(width: t.space.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: t.space.xxs,
                            runSpacing: t.space.xxs,
                            children: [
                              for (final c in mine.take(6))
                                tid(
                                  'home.kids.chore.${c.due.chore.id}',
                                  Container(
                                    width: 44 * t.scale,
                                    height: 44 * t.scale,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: c.done ? t.colors.tintOf(t.colors.success, 0.18) : t.colors.surfaceSunken,
                                      borderRadius: BorderRadius.circular(12 * t.scale),
                                    ),
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        DEmoji(c.due.chore.emoji ?? '⭐', size: 30 * t.scale),
                                        if (c.done)
                                          Positioned(
                                            right: -6 * t.scale,
                                            bottom: -6 * t.scale,
                                            child: Icon(Icons.check_circle_rounded, size: 18 * t.scale, color: t.colors.success),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          SizedBox(height: t.space.xxs),
                          Text(
                            mine.isEmpty ? 'No chores today' : '$done of ${mine.length} done${jar > 0 ? ' · 🫙 $jar' : ''}',
                            style: t.text.caption,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ─────────────────────────────── Shopping ───────────────────────────────────

class ShoppingCard extends ConsumerWidget {
  const ShoppingCard({super.key, this.expand = false});
  final bool expand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final items = ref.watch(listItemsProvider(Ids.shoppingList)).value ?? const <ListItem>[];
    final open = [for (final i in items) if (!i.checked) i];
    final shown = open.take(expand ? 12 : 5).toList();
    return HomeCard(
      id: 'home.shopping',
      title: open.isEmpty ? 'Shopping' : 'Shopping · ${open.length}',
      expand: expand,
      onTap: () => context.go('/lists/${Ids.shoppingList}'),
      child: open.isEmpty
          ? Text('The list is empty 🎉', style: t.text.body.copyWith(color: t.colors.inkTertiary))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final i in shown)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 3 * t.scale),
                    child: Row(
                      children: [
                        Icon(Icons.circle_outlined, size: 18 * t.scale, color: t.colors.inkTertiary),
                        SizedBox(width: t.space.sm),
                        Expanded(child: Text(i.itemText, style: t.text.body, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                if (open.length > shown.length) Text('+ ${open.length - shown.length} more', style: t.text.caption),
              ],
            ),
    );
  }
}
