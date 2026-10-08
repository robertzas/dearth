import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/data/household.dart';
import '../../core/data/household_data.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../shared/face_photo.dart';
import '../../shared/recipe_visual.dart';
import 'cook_mode.dart';
import 'meal_ops.dart';
import 'meals_data.dart';
import 'plan_target.dart';
import 'recipe_card.dart';
import 'recipe_editor.dart';

/// Opens a recipe (SPEC FR-RCP-06). With [entry] it is that plan entry: the
/// servings are the entry's, and it can come off the plan.
Future<void> showRecipeSheet(BuildContext context, RecipeData recipe, {MealEntry? entry}) => showDSheet<void>(
      context,
      id: 'recipe.sheet',
      title: recipe.title,
      width: 760 * DTheme.of(context).scale,
      actions: [_EditButton(recipe: recipe, entry: entry), _SaveButton(recipe: recipe)],
      builder: (_) => RecipeDetail(recipe: recipe, entry: entry),
    );

/// Edit (SPEC FR-RCP-01): the family's version of any recipe, kept in the
/// box.
class _EditButton extends ConsumerWidget {
  const _EditButton({required this.recipe, this.entry});
  final RecipeData recipe;
  final MealEntry? entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) => DIconButton(
        icon: Icons.edit_outlined,
        label: 'Edit recipe',
        id: 'recipe.edit',
        tone: DButtonTone.ghost,
        onPressed: () async {
          final nav = Navigator.of(context);
          final toast = ref.read(toastProvider);
          final local = localRowOf(ref.read(localRecipesProvider).value ?? const {}, recipe);
          final updated = await showRecipeEditor(context, recipe: familyVersion(recipe, local), local: local);
          if (updated == null) return;
          toast.show('Saved ${updated.title}', emoji: '📖');
          // The sheet's title is fixed when it opens: open it again.
          nav.pop();
          await showRecipeSheet(nav.context, updated, entry: entry);
        },
      );
}

/// The family box toggle in the sheet header.
class _SaveButton extends ConsumerWidget {
  const _SaveButton({required this.recipe});
  final RecipeData recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final local = ref.watch(localRecipesProvider.select((m) => m.value == null ? null : localRowOf(m.value!, recipe)));
    final saved = local?.saved ?? false;
    return DIconButton(
      icon: saved ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
      label: saved ? 'In the recipe box' : 'Save to the recipe box',
      id: 'recipe.save',
      tone: DButtonTone.ghost,
      color: saved ? t.colors.accent : null,
      onPressed: () async {
        final w = ref.read(writerProvider);
        await w.commit(saveRecipeOps(w.op, recipe, existing: local, saved: !saved, nowMs: ref.read(appClockProvider).nowMs()));
        ref.read(toastProvider).show(saved ? 'Taken out of the recipe box' : 'Saved to the recipe box', emoji: saved ? '📤' : '📥');
      },
    );
  }
}

class RecipeDetail extends ConsumerStatefulWidget {
  const RecipeDetail({super.key, required this.recipe, this.entry});
  final RecipeData recipe;
  final MealEntry? entry;

  @override
  ConsumerState<RecipeDetail> createState() => _RecipeDetailState();
}

class _RecipeDetailState extends ConsumerState<RecipeDetail> {
  late int _servings = widget.entry?.servings ?? widget.recipe.servings;
  bool? _metric;

  /// The family's version when they have one (their edits win).
  RecipeData get _r => familyVersion(widget.recipe, _local());

  Recipe? _local() => localRowOf(ref.read(localRecipesProvider).value ?? const {}, widget.recipe);

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final metric = _metric ?? !ref.watch(imperialProvider);
    final local = ref.watch(localRecipesProvider.select((m) => m.value == null ? null : localRowOf(m.value!, widget.recipe)));
    final ingredients = _r.scaledIngredients(_servings);
    final entry = widget.entry;
    final gap = SizedBox(height: t.space.lg);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RecipeVisual(recipe: local, data: _r, title: _r.title, height: (t.isPhone ? 180 : 230) * t.scale),
        SizedBox(height: t.space.sm),
        tid('recipe.meta', Text(recipeMeta(_r).isEmpty ? 'Recipe' : recipeMeta(_r), style: t.text.body.copyWith(color: t.colors.inkSecondary))),
        if (entry != null) ...[SizedBox(height: t.space.sm), _PlannedBanner(entry: entry)],
        SizedBox(height: t.space.md),
        Wrap(
          spacing: t.space.sm,
          runSpacing: t.space.sm,
          children: [
            if (entry == null) DButton(label: 'Add to plan', icon: Icons.event_available_rounded, id: 'recipe.plan', onPressed: _plan),
            DButton(
              label: 'Add to list',
              icon: Icons.add_shopping_cart_rounded,
              tone: entry == null ? DButtonTone.tonal : DButtonTone.primary,
              id: 'recipe.tolist',
              onPressed: () => _toList(ingredients, metric),
            ),
            if (_r.steps.isNotEmpty)
              DButton(label: 'Cook', icon: Icons.soup_kitchen_rounded, tone: DButtonTone.tonal, id: 'recipe.cook', onPressed: () => openCookMode(context, _r, servings: _servings)),
          ],
        ),
        gap,
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: t.space.md,
          runSpacing: t.space.sm,
          children: [
            Text('Ingredients', style: t.text.title),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DStepper(
                  id: 'recipe.servings',
                  value: _servings,
                  max: 24,
                  format: (v) => '$v',
                  onChanged: _setServings,
                ),
                Text(_servings == 1 ? 'serving' : 'servings', style: t.text.caption),
              ],
            ),
            DSegmented<bool>(
              options: const [(false, 'US'), (true, 'Metric')],
              value: metric,
              dense: true,
              idPrefix: 'recipe.units',
              onChanged: (v) => setState(() => _metric = v),
            ),
          ],
        ),
        SizedBox(height: t.space.sm),
        for (final (i, ing) in ingredients.indexed) ...[
          // A group's name over its ingredients ("For the glaze").
          if (ing.group case final g? when i == 0 || ingredients[i - 1].group != g)
            Padding(padding: EdgeInsets.only(top: t.space.sm, bottom: t.space.xxs), child: Text(g, style: t.text.bodyStrong)),
          _IngredientRow(ingredient: ing, metric: metric, index: i),
        ],
        gap,
        if (_r.steps.isNotEmpty) ...[
          Text('Steps', style: t.text.title),
          SizedBox(height: t.space.sm),
          for (final (i, s) in _r.steps.indexed) _StepRow(number: i + 1, text: s),
          gap,
        ],
        if (local?.notes case final notes? when notes.trim().isNotEmpty) ...[
          Text('Notes', style: t.text.title),
          SizedBox(height: t.space.sm),
          tid('recipe.notes', Text(notes.trim(), style: t.text.body)),
          gap,
        ],
        Text('How did everyone like it?', style: t.text.title),
        SizedBox(height: t.space.sm),
        _Ratings(recipe: _r),
        if (_r.attribution != null || _r.url != null) ...[
          SizedBox(height: t.space.md),
          Text([recipeCredit(_r), ?_r.url].join(' · '), style: t.text.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ],
    );
  }

  /// Per-entry servings persist (SPEC FR-MEAL-03); otherwise they only
  /// scale this view and what "Add to plan"/"Add to list" use.
  void _setServings(int v) {
    setState(() => _servings = v);
    final entry = widget.entry;
    if (entry != null) {
      final w = ref.read(writerProvider);
      w.commit(mealServingsOps(w.op, entry.id, v));
    }
  }

  Future<void> _plan() async {
    final target = await pickPlanTarget(context, title: 'Plan ${_r.title}');
    if (target == null || !mounted) return;
    final (date, slot) = target;
    final w = ref.read(writerProvider);
    await w.commit(planRecipeOps(
      w.op,
      recipe: _r,
      existing: _local(),
      date: date,
      slot: slot,
      servings: _servings,
      nowMs: ref.read(appClockProvider).nowMs(),
    ));
    if (!mounted) return;
    final slotLabel = ref.read(mealSlotsProvider).where((s) => s.$1 == slot).firstOrNull?.$2 ?? slot;
    ref.read(toastProvider).show('Planned for ${relativeDayName(date, ref.read(todayProvider))} · $slotLabel', emoji: '🗓️');
  }

  Future<void> _toList(List<Ingredient> ingredients, bool metric) async {
    final list = await shoppingListOnce(ref.read(dbProvider));
    final toast = ref.read(toastProvider);
    if (list == null) {
      toast.show('Make a shopping list in Lists first', emoji: '🛒');
      return;
    }
    final existing = await listItemsOnce(ref.read(dbProvider), list.id);
    final last = existing.where((i) => !i.checked).map((i) => i.sortKey).fold<String?>(null, (a, b) => a == null || b.compareTo(a) > 0 ? b : a);
    final w = ref.read(writerProvider);
    final res = addToListOps(w.op, listId: list.id, ingredients: ingredients, existing: existing, lastSortKey: last, metric: metric);
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

class _PlannedBanner extends ConsumerWidget {
  const _PlannedBanner({required this.entry});
  final MealEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final date = LocalDate.tryParse(entry.date);
    final slot = ref.watch(mealSlotsProvider).where((s) => s.$1 == entry.slot).firstOrNull;
    return DBanner(
      id: 'recipe.planned',
      emoji: slot?.$3 ?? '🗓️',
      title: 'Planned for ${date == null ? entry.date : relativeDayName(date, today)} · ${slot?.$2 ?? entry.slot}',
      action: DButton(
        label: 'Remove',
        tone: DButtonTone.ghost,
        size: DButtonSize.sm,
        id: 'recipe.unplan',
        onPressed: () async {
          final w = ref.read(writerProvider);
          await w.commit(removeMealOps(w.op, entry.id));
          if (context.mounted) Navigator.of(context).maybePop();
          ref.read(toastProvider).show(
                'Taken off the plan',
                emoji: '🗑️',
                actionLabel: 'Undo',
                onAction: () => w.upsert('meal_entries', entry.id, const {'deleted': false}),
              );
        },
      ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({required this.ingredient, required this.metric, required this.index});
  final Ingredient ingredient;
  final bool metric;
  final int index;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final text = ingredient.describe(metric: metric);
    final note = ingredient.isStaple ? 'pantry' : (ingredient.optional ? 'optional' : null);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 9 * t.scale, right: t.space.sm),
            child: Container(width: 7 * t.scale, height: 7 * t.scale, decoration: BoxDecoration(color: t.colors.accent, shape: BoxShape.circle)),
          ),
          Expanded(child: tid('recipe.ingredient.$index', Text(text, style: t.text.body))),
          if (note != null) Text(note, style: t.text.caption.copyWith(color: t.colors.inkTertiary)),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.number, required this.text});
  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30 * t.scale,
            height: 30 * t.scale,
            margin: EdgeInsets.only(right: t.space.sm),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: t.colors.accentTint, shape: BoxShape.circle),
            child: Text('$number', style: t.text.label.copyWith(color: t.colors.accent, fontWeight: FontWeight.w800)),
          ),
          Expanded(child: Text(text, style: t.text.body)),
        ],
      ),
    );
  }
}

/// Each family member rates with a face (SPEC FR-RCP-06), kids included.
class _Ratings extends ConsumerWidget {
  const _Ratings({required this.recipe});
  final RecipeData recipe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final people = [for (final p in ref.watch(familyProvider)) if (p.role != 'pet') p];
    final local = ref.watch(localRecipesProvider.select((m) => m.value == null ? null : localRowOf(m.value!, recipe)));
    final rid = local?.id ?? localRecipeId(recipe);
    final scores = ref.watch(recipeRatingsProvider.select((m) => m.value?[rid] ?? const <String, int>{}));
    return Column(
      children: [
        for (final p in people)
          Padding(
            padding: EdgeInsets.only(bottom: t.space.xs),
            child: Row(
              children: [
                ProfileAvatar(p, size: 36 * t.scale, ring: false),
                SizedBox(width: t.space.sm),
                Expanded(child: Text(p.nickname ?? p.name, style: t.text.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis)),
                for (final (score, emoji, label) in kRatingFaces)
                  DPressable(
                    id: 'recipe.rate.${p.id}.$score',
                    semanticLabel: '${p.name}: $label',
                    selected: scores[p.id] == score,
                    excludeSemantics: true,
                    borderRadius: t.radius.pill,
                    onTap: () async {
                      final w = ref.read(writerProvider);
                      final now = ref.read(appClockProvider).nowMs();
                      await w.commit([
                        ...copyRecipeOps(w.op, recipe, existing: local, nowMs: now),
                        ...rateRecipeOps(w.op, recipeId: rid, profileId: p.id, score: scores[p.id] == score ? null : score, nowMs: now),
                      ]);
                    },
                    child: AnimatedContainer(
                      duration: t.motion(DMotion.fast),
                      width: 44 * t.scale,
                      height: 44 * t.scale,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scores[p.id] == score ? t.colors.accentTint : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Opacity(
                        opacity: scores[p.id] == null || scores[p.id] == score ? 1 : 0.4,
                        child: DEmoji(emoji, size: 26 * t.scale),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
