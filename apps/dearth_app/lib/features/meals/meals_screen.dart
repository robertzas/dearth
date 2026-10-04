import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import 'discover_view.dart';
import 'meals_data.dart';
import 'planner.dart';
import 'recipe_box.dart';

enum MealsTab {
  plan('Plan'),
  discover('Discover'),
  box('Recipes');

  const MealsTab(this.label);
  final String label;
}

class MealsTabController extends Notifier<MealsTab> {
  @override
  MealsTab build() => MealsTab.plan;

  void show(MealsTab tab) => state = tab;
}

/// Shared so Home's dinner card can open Meals on the plan.
final mealsTabProvider = NotifierProvider<MealsTabController, MealsTab>(MealsTabController.new);

/// Meals (SPEC §10.5): the week's plan, recipe discovery and the family box.
class MealsScreen extends ConsumerWidget {
  const MealsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final tab = ref.watch(mealsTabProvider);
    final week = ref.watch(mealWeekProvider);
    final offset = ref.watch(mealWeekOffsetProvider);
    final nav = ref.read(mealWeekOffsetProvider.notifier);
    final tabs = DSegmented<MealsTab>(
      options: [for (final x in MealsTab.values) (x, x.label)],
      value: tab,
      idPrefix: 'meals.tab',
      onChanged: ref.read(mealsTabProvider.notifier).show,
    );
    final weekNav = [
      DIconButton(icon: Icons.chevron_left_rounded, label: 'Previous week', id: 'meals.prev', onPressed: () => nav.step(-1)),
      if (offset != 0) DButton(label: 'This week', tone: DButtonTone.tonal, size: DButtonSize.sm, id: 'meals.today', onPressed: nav.thisWeek),
      DIconButton(icon: Icons.chevron_right_rounded, label: 'Next week', id: 'meals.next', onPressed: () => nav.step(1)),
    ];
    final subtitle = switch (tab) {
      MealsTab.plan => '${offset == 0 ? 'This week' : (offset == 1 ? 'Next week' : (offset == -1 ? 'Last week' : 'Week of'))} · ${formatDateSpan(week.start, week.end.addDays(-1))}',
      MealsTab.discover => 'Find something new, or something that uses what you’re buying',
      MealsTab.box => 'The family’s saved recipes',
    };
    final header = t.isPhone
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DPageHeader(title: 'Meals', subtitle: subtitle, actions: tab == MealsTab.plan ? weekNav : const []),
              SizedBox(height: t.space.sm),
              tabs,
            ],
          )
        : DPageHeader(
            title: 'Meals',
            subtitle: subtitle,
            actions: [
              if (tab == MealsTab.plan) ...[...weekNav, SizedBox(width: t.space.md)],
              tabs,
            ],
          );
    return screenTid(
      'screen.meals',
      Padding(
        padding: EdgeInsets.fromLTRB(t.pageMargin, t.pageMargin, t.pageMargin, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            SizedBox(height: t.gutter),
            Expanded(
              child: switch (tab) {
                MealsTab.plan => Padding(padding: EdgeInsets.only(bottom: t.pageMargin), child: const MealPlanner()),
                MealsTab.discover => const DiscoverView(),
                MealsTab.box => const RecipeBoxView(),
              },
            ),
          ],
        ),
      ),
    );
  }
}
