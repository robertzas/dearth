import 'dart:async';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../shared/recipe_visual.dart';
import 'meal_ops.dart';
import 'meals_data.dart';
import 'recipe_card.dart';

/// Free-text entries offered for any slot (SPEC FR-MEAL-01).
const List<(String id, String title, String emoji)> kQuickMeals = [
  ('leftovers', 'Leftovers', '🥡'),
  ('eat-out', 'Eat out', '🍽️'),
  ('takeout', 'Takeout', '🛵'),
];

/// Fills a plan slot: search the recipe box and providers, take a "Pairs
/// with your plan" suggestion, or add a free-text entry.
Future<void> showPlanPicker(BuildContext context, {required LocalDate date, required String slot, required String title}) => showDSheet<void>(
      context,
      id: 'plan.sheet',
      title: title,
      builder: (_) => _PlanPicker(date: date, slot: slot),
    );

class _PlanPicker extends ConsumerStatefulWidget {
  const _PlanPicker({required this.date, required this.slot});
  final LocalDate date;
  final String slot;

  @override
  ConsumerState<_PlanPicker> createState() => _PlanPickerState();
}

class _PlanPickerState extends ConsumerState<_PlanPicker> {
  final _text = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = v.trim());
    });
  }

  Future<void> _planRecipe(RecipeData r) async {
    final w = ref.read(writerProvider);
    await w.commit(planRecipeOps(
      w.op,
      recipe: r,
      existing: localRowOf(ref.read(localRecipesProvider).value ?? const {}, r),
      date: widget.date,
      slot: widget.slot,
      servings: ref.read(defaultServingsProvider),
      nowMs: ref.read(appClockProvider).nowMs(),
    ));
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<void> _planText(String title) async {
    if (title.trim().isEmpty) return;
    final w = ref.read(writerProvider);
    await w.commit(planTextOps(w.op, title: title, date: widget.date, slot: widget.slot));
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DTextField(
          id: 'plan.search',
          controller: _text,
          hint: 'Search recipes, or type a meal',
          prefix: const Icon(Icons.search_rounded),
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: (v) {
            _debounce?.cancel();
            setState(() => _query = v.trim());
          },
        ),
        SizedBox(height: t.space.sm),
        Wrap(
          spacing: t.space.xs,
          runSpacing: t.space.xs,
          children: [
            for (final (id, title, emoji) in kQuickMeals) DChip(label: title, emoji: emoji, id: 'plan.quick.$id', onTap: () => _planText(title)),
          ],
        ),
        SizedBox(height: t.space.md),
        if (_query.isEmpty) ..._suggestions(t) else ..._results(t),
      ],
    );
  }

  List<Widget> _results(DTheme t) {
    final results = ref.watch(recipeSearchProvider(_query));
    return [
      _ChoiceRow(
        id: 'plan.text',
        emoji: recipeEmojiFor(const [], null, _query),
        title: 'Add “$_query”',
        subtitle: 'Just the name, no recipe',
        onTap: () => _planText(_query),
      ),
      ...results.when(
        data: (list) => [
          if (list.isEmpty) Padding(padding: EdgeInsets.all(t.space.md), child: Text('No recipes match “$_query”.', style: t.text.caption)),
          for (final r in list) _RecipeChoice(recipe: r, id: 'plan.result.${r.sourceId ?? r.id}', onTap: () => _planRecipe(r)),
        ],
        loading: () => [for (var i = 0; i < 3; i++) Padding(padding: EdgeInsets.only(bottom: t.space.xs), child: DSkeleton(height: 56 * t.scale))],
        error: (e, _) => [Text('Search isn’t available right now.', style: t.text.caption)],
      ),
    ];
  }

  List<Widget> _suggestions(DTheme t) {
    final pairs = ref.watch(planPairsProvider).value ?? const <ReuseScore>[];
    final box = ref.watch(recipeBoxProvider);
    final quick = ref.watch(recipeFeedProvider(RecipeFeed.quick)).value ?? const <RecipeData>[];
    final shown = <String>{};
    List<RecipeData> fresh(Iterable<RecipeData> rs, int n) => [for (final r in rs) if (shown.add(localRecipeId(r))) r].take(n).toList();
    final pairList = fresh(pairs.map((p) => p.recipe), 4);
    final why = {for (final p in pairs) p.recipe.id: p.explanation};
    final boxList = fresh(box.map(RecipeData.fromRow), 6);
    final quickList = fresh(quick, 4);
    return [
      if (pairList.isNotEmpty) ...[
        const _Heading('Pairs with your plan'),
        for (final r in pairList) _RecipeChoice(recipe: r, subtitle: why[r.id], id: 'plan.pair.${r.sourceId ?? r.id}', onTap: () => _planRecipe(r)),
      ],
      if (boxList.isNotEmpty) ...[
        const _Heading('From the recipe box'),
        for (final r in boxList) _RecipeChoice(recipe: r, id: 'plan.box.${r.sourceId ?? r.id}', onTap: () => _planRecipe(r)),
      ],
      if (quickList.isNotEmpty) ...[
        const _Heading('Quick weeknights'),
        for (final r in quickList) _RecipeChoice(recipe: r, id: 'plan.quick-recipe.${r.sourceId ?? r.id}', onTap: () => _planRecipe(r)),
      ],
    ];
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: t.space.sm, bottom: t.space.xs),
      child: Text(text.toUpperCase(), style: t.text.overline.copyWith(color: t.colors.inkSecondary)),
    );
  }
}

class _RecipeChoice extends ConsumerWidget {
  const _RecipeChoice({required this.recipe, required this.id, required this.onTap, this.subtitle});
  final RecipeData recipe;
  final String id;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final local = ref.watch(localRecipesProvider.select((m) => m.value == null ? null : localRowOf(m.value!, recipe)));
    return DListRow(
      id: id,
      title: recipe.title,
      subtitle: subtitle ?? recipeMeta(recipe),
      leading: SizedBox(
        width: 52 * t.scale,
        child: RecipeVisual(recipe: local, data: recipe, title: recipe.title, height: 52 * t.scale, radius: BorderRadius.circular(t.radius.s)),
      ),
      trailing: Icon(Icons.add_circle_outline_rounded, color: t.colors.accent),
      onTap: onTap,
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.id, required this.emoji, required this.title, required this.subtitle, required this.onTap});
  final String id;
  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return DListRow(
      id: id,
      title: title,
      subtitle: subtitle,
      leading: SizedBox(width: 52 * t.scale, child: Center(child: DEmoji(emoji, size: 30 * t.scale))),
      trailing: Icon(Icons.add_circle_outline_rounded, color: t.colors.accent),
      onTap: onTap,
    );
  }
}
