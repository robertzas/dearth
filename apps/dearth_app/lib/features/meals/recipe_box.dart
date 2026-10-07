import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/sync/hub_api.dart';
import 'discover_view.dart';
import 'meal_ops.dart';
import 'meals_data.dart';
import 'recipe_editor.dart';
import 'recipe_sheet.dart';

/// The family recipe box (SPEC FR-RCP-01/02): saved recipes, recipes of the
/// family's own, and on a Hub, importing any recipe page by its link.
class RecipeBoxView extends ConsumerWidget {
  const RecipeBoxView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final box = ref.watch(recipeBoxProvider);
    final canImport = ref.watch(hubApiProvider) != null;
    return ListView(
      children: [
        // A wrap, not a row: two buttons and the count don't fit across a phone.
        Wrap(
          spacing: t.space.sm,
          runSpacing: t.space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Text(
              box.isEmpty ? 'Recipes you save or write show up here.' : '${box.length} recipe${box.length == 1 ? '' : 's'} in the box',
              style: t.text.body.copyWith(color: t.colors.inkSecondary),
            ),
            Wrap(
              spacing: t.space.sm,
              runSpacing: t.space.sm,
              children: [
                DButton(label: 'New recipe', icon: Icons.add_rounded, id: 'box.new', onPressed: () => _create(context, ref)),
                if (canImport) DButton(label: 'Import from a link', icon: Icons.link_rounded, tone: DButtonTone.tonal, id: 'box.import', onPressed: () => _import(context, ref)),
              ],
            ),
          ],
        ),
        SizedBox(height: t.gutter),
        if (box.isEmpty)
          const DEmptyState(
            id: 'box.empty',
            emoji: '📖',
            title: 'Your recipe box is empty',
            message: 'Write down a family recipe with “New recipe”, or open any recipe and tap the bookmark to keep it here.',
          )
        else
          RecipeGrid(recipes: [for (final r in box) RecipeData.fromRow(r)], onOpen: (r) => showRecipeSheet(context, r)),
      ],
    );
  }

  /// A recipe of their own (SPEC FR-RCP-01): once saved it opens like any
  /// other, ready to plan, shop and cook.
  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final r = await showRecipeEditor(context);
    if (r == null || !context.mounted) return;
    ref.read(toastProvider).show('Added ${r.title} to the recipe box', emoji: '📖');
    await showRecipeSheet(context, r);
  }

  /// URL import runs on the Hub (schema.org Recipe; SPEC FR-RCP-01).
  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final url = TextEditingController();
    final go = await showDSheet<bool>(
      context,
      id: 'box.import.sheet',
      title: 'Import a recipe',
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DTextField(id: 'box.import.url', controller: url, hint: 'https://…', keyboardType: TextInputType.url, autofocus: true, onSubmitted: (_) => Navigator.of(sheet).pop(true)),
          SizedBox(height: DTheme.of(sheet).space.md),
          DButton(label: 'Import', id: 'box.import.go', onPressed: () => Navigator.of(sheet).pop(true)),
        ],
      ),
    );
    final link = url.text.trim();
    url.dispose();
    final api = ref.read(hubApiProvider);
    if (go != true || link.isEmpty || api == null) return;
    final toast = ref.read(toastProvider);
    try {
      final recipe = RecipeData.fromJson(await api.post('/api/recipes/import', {'url': link}));
      final w = ref.read(writerProvider);
      await w.commit(saveRecipeOps(w.op, recipe, existing: localRowOf(ref.read(localRecipesProvider).value ?? const {}, recipe), saved: true, nowMs: ref.read(appClockProvider).nowMs()));
      toast.show('Imported ${recipe.title}', emoji: '📥');
      if (context.mounted) await showRecipeSheet(context, recipe);
    } on HubApiException catch (e) {
      toast.show(e.friendly, emoji: '⚠️', tone: DBannerTone.warning);
    }
  }
}
