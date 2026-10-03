import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/data/calendar.dart';
import '../../core/data/household.dart';
import '../../core/data/household_data.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../shared/recipe_visual.dart';
import 'meal_ops.dart';
import 'meals_data.dart';
import 'plan_picker.dart';
import 'recipe_sheet.dart';

typedef MealSlot = (String id, String label, String emoji);

/// The week planner (SPEC FR-MEAL-01/02): days × meal slots under a summary
/// of the week's shopping. Landscape walls and tablets get a grid; portrait
/// walls and phones a day-by-day list.
class MealPlanner extends ConsumerWidget {
  const MealPlanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final week = ref.watch(mealWeekProvider);
    final meals = ref.watch(mealsInRangeProvider(week)).value ?? const <PlannedMeal>[];
    final slots = ref.watch(mealSlotsProvider);
    final size = MediaQuery.sizeOf(context);
    final wide = !t.isPhone && size.width > size.height && size.width > 1000 * t.scale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SummaryBar(),
        SizedBox(height: t.space.md),
        Expanded(child: wide ? _PlanGrid(week: week, slots: slots, meals: meals) : _PlanList(week: week, slots: slots, meals: meals)),
      ],
    );
  }
}

List<PlannedMeal> _entriesFor(List<PlannedMeal> meals, LocalDate d, String slot) => [
      for (final m in meals)
        if (m.entry.date == d.iso && m.entry.slot == slot) m,
    ];

String _slotDay(MealSlot slot, LocalDate d) => '${slot.$2} on ${weekdayLong(d)}';

Future<void> _openEntry(BuildContext context, WidgetRef ref, PlannedMeal m) async {
  final r = m.recipe;
  if (r != null) return showRecipeSheet(context, RecipeData.fromRow(r), entry: m.entry);
  return showDSheet<void>(
    context,
    id: 'meal.sheet',
    title: m.title,
    builder: (sheet) => Wrap(
      spacing: DTheme.of(sheet).space.sm,
      children: [
        DButton(
          label: 'Take off the plan',
          icon: Icons.delete_outline_rounded,
          tone: DButtonTone.tonal,
          id: 'meal.remove',
          onPressed: () async {
            final w = ref.read(writerProvider);
            await w.commit(removeMealOps(w.op, m.entry.id));
            if (sheet.mounted) Navigator.of(sheet).maybePop();
            ref.read(toastProvider).show(
                  'Took “${m.title}” off the plan',
                  emoji: '🗑️',
                  actionLabel: 'Undo',
                  onAction: () => w.upsert('meal_entries', m.entry.id, const {'deleted': false}),
                );
          },
        ),
      ],
    ),
  );
}

void _pick(BuildContext context, WidgetRef ref, LocalDate d, MealSlot slot) => showPlanPicker(
      context,
      date: d,
      slot: slot.$1,
      title: '${slot.$2} · ${relativeDayName(d, ref.read(todayProvider))}',
    );

/// "5 meals · 31 to buy · 8 shared" and the week's "Add to list".
class _SummaryBar extends ConsumerWidget {
  const _SummaryBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final s = ref.watch(planSummaryProvider);
    final text = s.meals == 0
        ? 'Nothing planned this week yet. Tap a slot to add a meal.'
        : [
            '${s.meals} meal${s.meals == 1 ? '' : 's'} planned',
            if (s.toBuy > 0) '${s.toBuy} ingredient${s.toBuy == 1 ? '' : 's'} to buy',
            if (s.shared > 0) '${s.shared} shared between recipes',
          ].join(' · ');
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
            decoration: BoxDecoration(color: t.colors.accentTint, borderRadius: t.radius.pill),
            child: Row(
              children: [
                const DEmoji('🧺', size: 22),
                SizedBox(width: t.space.sm),
                Expanded(child: tid('meals.summary', Text(text, style: t.text.label, maxLines: 2, overflow: TextOverflow.ellipsis))),
              ],
            ),
          ),
        ),
        if (s.toBuy > 0) ...[
          SizedBox(width: t.space.sm),
          DButton(label: t.isPhone ? 'To list' : 'Add week to list', icon: Icons.add_shopping_cart_rounded, tone: DButtonTone.tonal, id: 'meals.week.tolist', onPressed: () => _addWeek(ref, s)),
        ],
      ],
    );
  }

  Future<void> _addWeek(WidgetRef ref, PlanSummary s) async {
    final toast = ref.read(toastProvider);
    final list = await shoppingListOnce(ref.read(dbProvider));
    if (list == null) {
      toast.show('Make a shopping list in Lists first', emoji: '🛒');
      return;
    }
    final existing = await listItemsOnce(ref.read(dbProvider), list.id);
    final last = existing.where((i) => !i.checked).map((i) => i.sortKey).fold<String?>(null, (a, b) => a == null || b.compareTo(a) > 0 ? b : a);
    final w = ref.read(writerProvider);
    final res = addLinesToListOps(w.op, listId: list.id, lines: s.lines, existing: existing, lastSortKey: last, metric: !ref.read(imperialProvider));
    await w.commit(res.ops);
    final staples = res.staples == 0 ? '' : ' · check you have ${res.staples} pantry staple${res.staples == 1 ? '' : 's'}';
    toast.show(
      res.added == 0 ? 'Everything is already on ${list.title}$staples' : 'Added ${res.added} item${res.added == 1 ? '' : 's'} to ${list.title}$staples',
      emoji: '🛒',
      actionLabel: res.added == 0 ? null : 'Undo',
      onAction: res.added == 0 ? null : () => w.commit([for (final o in res.ops) w.op('list_items', o.rowId, const {}, kind: OpKind.delete)]),
    );
  }
}

class _PlanGrid extends ConsumerWidget {
  const _PlanGrid({required this.week, required this.slots, required this.meals});
  final DayRange week;
  final List<MealSlot> slots;
  final List<PlannedMeal> meals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final today = ref.watch(todayProvider);
    final days = week.dates.toList();
    final labelW = 104 * t.scale;
    return LayoutBuilder(builder: (context, box) {
      final headerH = 60 * t.scale;
      final rowH = ((box.maxHeight - headerH) / slots.length).clamp(140 * t.scale, 280 * t.scale);
      final grid = Column(
        children: [
          SizedBox(
            height: headerH,
            child: Row(
              children: [
                SizedBox(width: labelW),
                for (final d in days) Expanded(child: _DayHeader(date: d, today: today)),
              ],
            ),
          ),
          for (final s in slots)
            SizedBox(
              height: rowH,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: labelW,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        DEmoji(s.$3, size: 28 * t.scale),
                        SizedBox(height: t.space.xxs),
                        Text(s.$2, style: t.text.label.copyWith(color: t.colors.inkSecondary)),
                      ],
                    ),
                  ),
                  for (final d in days)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.all(t.space.xxs),
                        child: _Cell(date: d, slot: s, entries: _entriesFor(meals, d, s.$1), today: d == today),
                      ),
                    ),
                ],
              ),
            ),
        ],
      );
      return headerH + rowH * slots.length > box.maxHeight + 1 ? SingleChildScrollView(child: grid) : grid;
    });
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date, required this.today});
  final LocalDate date;
  final LocalDate today;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final isToday = date == today;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(weekdayShort(date).toUpperCase(), style: t.text.overline.copyWith(color: isToday ? t.colors.accent : t.colors.inkSecondary)),
        Container(
          margin: EdgeInsets.only(top: t.space.xxs),
          padding: EdgeInsets.symmetric(horizontal: t.space.xs),
          decoration: isToday ? BoxDecoration(color: t.colors.accent, borderRadius: t.radius.pill) : null,
          child: Text('${date.day}', style: t.text.title.copyWith(color: isToday ? t.colors.onAccent : t.colors.inkPrimary)),
        ),
      ],
    );
  }
}

/// One grid cell: its planned entries, or an add target.
class _Cell extends ConsumerWidget {
  const _Cell({required this.date, required this.slot, required this.entries, required this.today});
  final LocalDate date;
  final MealSlot slot;
  final List<PlannedMeal> entries;
  final bool today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    if (entries.isEmpty) {
      return DPressable(
        id: 'meals.add.${date.iso}.${slot.$1}',
        semanticLabel: 'Add ${slot.$2.toLowerCase()} on ${weekdayLong(date)}',
        excludeSemantics: true,
        borderRadius: t.radius.card,
        onTap: () => _pick(context, ref, date, slot),
        child: Container(
          decoration: BoxDecoration(
            color: today ? t.colors.accentTint.withValues(alpha: 0.5) : null,
            border: Border.all(color: t.colors.outline, width: 1.5),
            borderRadius: t.radius.card,
          ),
          child: Center(child: Icon(Icons.add_rounded, color: t.colors.inkTertiary, size: t.iconMd)),
        ),
      );
    }
    return Column(
      children: [
        for (final (i, m) in entries.indexed) ...[
          if (i > 0) SizedBox(height: t.space.xxs),
          Expanded(
            child: DCard(
              id: i == 0 ? 'meals.cell.${date.iso}.${slot.$1}' : 'meals.cell.${date.iso}.${slot.$1}.$i',
              semanticLabel: '${_slotDay(slot, date)}: ${m.title}',
              padding: EdgeInsets.all(t.space.xs),
              onTap: () => _openEntry(context, ref, m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, b) => RecipeVisual(recipe: m.recipe, title: m.title, height: b.maxHeight, radius: BorderRadius.circular(t.radius.s)),
                    ),
                  ),
                  SizedBox(height: t.space.xxs),
                  Text(m.title, style: t.text.label.copyWith(fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PlanList extends ConsumerWidget {
  const _PlanList({required this.week, required this.slots, required this.meals});
  final DayRange week;
  final List<MealSlot> slots;
  final List<PlannedMeal> meals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final today = ref.watch(todayProvider);
    return ListView(
      children: [
        for (final d in week.dates) ...[
          Padding(
            padding: EdgeInsets.only(top: t.space.md, bottom: t.space.xs),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: relativeDayName(d, today), style: t.text.title.copyWith(color: d == today ? t.colors.accent : null)),
                TextSpan(text: '  ${monthDay(d)}', style: t.text.body.copyWith(color: t.colors.inkSecondary)),
              ]),
            ),
          ),
          for (final s in slots) ...[
            for (final m in _entriesFor(meals, d, s.$1))
              Padding(padding: EdgeInsets.only(bottom: t.space.xs), child: _PlannedRow(date: d, slot: s, meal: m)),
            if (_entriesFor(meals, d, s.$1).isEmpty) Padding(padding: EdgeInsets.only(bottom: t.space.xs), child: _EmptyRow(date: d, slot: s)),
          ],
        ],
        SizedBox(height: t.space.lg),
      ],
    );
  }
}

class _PlannedRow extends ConsumerWidget {
  const _PlannedRow({required this.date, required this.slot, required this.meal});
  final LocalDate date;
  final MealSlot slot;
  final PlannedMeal meal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final side = 60 * t.scale;
    return DCard(
      id: 'meals.cell.${date.iso}.${slot.$1}',
      semanticLabel: '${_slotDay(slot, date)}: ${meal.title}',
      padding: EdgeInsets.all(t.space.xs),
      onTap: () => _openEntry(context, ref, meal),
      child: Row(
        children: [
          SizedBox(width: side, child: RecipeVisual(recipe: meal.recipe, title: meal.title, height: side, radius: BorderRadius.circular(t.radius.s))),
          SizedBox(width: t.space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(slot.$2.toUpperCase(), style: t.text.overline.copyWith(color: t.colors.inkSecondary)),
                Text(meal.title, style: t.text.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: t.colors.inkTertiary),
        ],
      ),
    );
  }
}

class _EmptyRow extends ConsumerWidget {
  const _EmptyRow({required this.date, required this.slot});
  final LocalDate date;
  final MealSlot slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    return DPressable(
      id: 'meals.add.${date.iso}.${slot.$1}',
      semanticLabel: 'Add ${slot.$2.toLowerCase()} on ${weekdayLong(date)}',
      excludeSemantics: true,
      borderRadius: t.radius.card,
      onTap: () => _pick(context, ref, date, slot),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: t.space.sm, vertical: t.space.xs),
        decoration: BoxDecoration(border: Border.all(color: t.colors.outline), borderRadius: t.radius.card),
        child: Row(
          children: [
            SizedBox(width: 60 * t.scale, child: Center(child: DEmoji(slot.$3, size: 24 * t.scale))),
            SizedBox(width: t.space.sm),
            Expanded(child: Text('Add ${slot.$2.toLowerCase()}', style: t.text.body.copyWith(color: t.colors.inkSecondary))),
            Icon(Icons.add_rounded, color: t.colors.inkTertiary),
          ],
        ),
      ),
    );
  }
}
