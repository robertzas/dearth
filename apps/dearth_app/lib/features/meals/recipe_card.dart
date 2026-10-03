import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import '../../shared/recipe_visual.dart';
import 'meal_ops.dart';
import 'meals_data.dart';

/// The test id of a recipe tile: provider recipes by their source id, so
/// specs can name catalog recipes (`recipe.chicken-tacos`).
String recipeTileId(RecipeData r) => 'recipe.${r.sourceId ?? r.id}';

/// "30 min · Mexican · 😋"
String recipeMeta(RecipeData r, {double? rating}) => [
      if (r.minutes != null) formatDuration(r.minutes!),
      if (r.cuisine != null && r.cuisine!.isNotEmpty) r.cuisine!,
      if (rating != null) ratingFace(rating),
    ].join(' · ');

/// The face closest to a mean rating.
String ratingFace(double mean) {
  var best = kRatingFaces.first;
  for (final f in kRatingFaces) {
    if ((f.$1 - mean).abs() < (best.$1 - mean).abs()) best = f;
  }
  return best.$2;
}

/// A recipe card (SPEC FR-RCP-05): picture, title, time, cuisine, family
/// rating and an optional plan badge ("Uses your cilantro · adds 2 items").
class RecipeTile extends ConsumerWidget {
  const RecipeTile({super.key, required this.recipe, this.badge, this.onTap, this.imageHeight});
  final RecipeData recipe;
  final String? badge;
  final VoidCallback? onTap;
  final double? imageHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final local = ref.watch(localRecipesProvider.select((m) => m.value == null ? null : localRowOf(m.value!, recipe)));
    final rating = ref.watch(familyRatingProvider.select((m) => m[local?.id ?? localRecipeId(recipe)]));
    final meta = recipeMeta(recipe, rating: rating);
    return DCard(
      id: recipeTileId(recipe),
      semanticLabel: [recipe.title, meta, ?badge].where((s) => s.isNotEmpty).join(', '),
      padding: EdgeInsets.all(t.space.sm),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          RecipeVisual(recipe: local, data: recipe, title: recipe.title, height: imageHeight ?? 120 * t.scale, radius: BorderRadius.circular(t.radius.s)),
          SizedBox(height: t.space.sm),
          Text(recipe.title, style: t.text.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
          if (meta.isNotEmpty) Text(meta, style: t.text.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
          if (badge != null) ...[
            SizedBox(height: t.space.xs),
            Text(badge!, style: t.text.caption.copyWith(color: t.colors.accent, fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

/// A horizontal row of recipe tiles under a section title.
class RecipeRow extends StatelessWidget {
  const RecipeRow({super.key, required this.recipes, required this.onOpen, this.badges = const {}, this.tileWidth});
  final List<RecipeData> recipes;
  final void Function(RecipeData r) onOpen;
  final Map<String, String> badges;
  final double? tileWidth;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final w = tileWidth ?? (t.isPhone ? 168 : 220) * t.scale;
    return SizedBox(
      height: w * 0.55 + 120 * t.scale + (badges.isEmpty ? 0 : 36 * t.scale),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: recipes.length,
        separatorBuilder: (_, _) => SizedBox(width: t.space.sm),
        itemBuilder: (context, i) => SizedBox(
          width: w,
          child: RecipeTile(recipe: recipes[i], badge: badges[recipes[i].id], imageHeight: w * 0.55, onTap: () => onOpen(recipes[i])),
        ),
      ),
    );
  }
}
