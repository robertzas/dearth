import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import 'meals_data.dart';
import 'recipe_card.dart';
import 'recipe_sheet.dart';

/// Discover (SPEC FR-RCP-03/04/09): search, then feeds: pairs with this
/// week's plan, quick weeknights, family favorites, popular, and a
/// "Surprise me" pick.
class DiscoverView extends ConsumerStatefulWidget {
  const DiscoverView({super.key});

  @override
  ConsumerState<DiscoverView> createState() => _DiscoverViewState();
}

class _DiscoverViewState extends ConsumerState<DiscoverView> {
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
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = v.trim());
    });
  }

  void _open(RecipeData r) => showRecipeSheet(context, r);

  Future<void> _surprise() async {
    try {
      final pool = await ref.read(recipeSourceProvider).feed(RecipeFeed.surprise);
      if (pool.isEmpty || !mounted) return;
      _open(pool[math.Random().nextInt(pool.length)]);
    } on Object {
      ref.read(toastProvider).show('Couldn’t pick one right now', emoji: '🎲');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final g = t.gutter;
    return ListView(
      children: [
        Row(
          children: [
            Expanded(
              child: DTextField(
                id: 'meals.search',
                controller: _text,
                hint: 'Search recipes, ingredients or cuisines',
                prefix: const Icon(Icons.search_rounded),
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: (v) {
                  _debounce?.cancel();
                  setState(() => _query = v.trim());
                },
              ),
            ),
            SizedBox(width: t.space.sm),
            DButton(label: 'Surprise me', emoji: '🎲', tone: DButtonTone.tonal, id: 'discover.surprise', onPressed: _surprise),
          ],
        ),
        SizedBox(height: g),
        if (_query.isNotEmpty) _Results(query: _query, onOpen: _open) else ..._feeds(t),
        SizedBox(height: g),
      ],
    );
  }

  List<Widget> _feeds(DTheme t) {
    final pairs = ref.watch(planPairsProvider).value ?? const <ReuseScore>[];
    final favorites = ref.watch(familyFavoritesProvider);
    final gap = SizedBox(height: t.gutter);
    return [
      if (pairs.isNotEmpty) ...[
        DSection(
          id: 'discover.pairs',
          title: 'Pairs with your plan',
          child: RecipeRow(
            recipes: [for (final p in pairs) p.recipe],
            badges: {for (final p in pairs) p.recipe.id: p.explanation},
            onOpen: _open,
          ),
        ),
        gap,
      ],
      _FeedSection(feed: RecipeFeed.quick, onOpen: _open),
      gap,
      if (favorites.isNotEmpty) ...[
        DSection(
          id: 'discover.favorites',
          title: 'Family favorites',
          child: RecipeRow(recipes: [for (final r in favorites) RecipeData.fromRow(r)], onOpen: _open),
        ),
        gap,
      ],
      _FeedSection(feed: RecipeFeed.popular, onOpen: _open),
    ];
  }
}

class _FeedSection extends ConsumerWidget {
  const _FeedSection({required this.feed, required this.onOpen});
  final RecipeFeed feed;
  final void Function(RecipeData) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final items = ref.watch(recipeFeedProvider(feed));
    return DSection(
      id: 'discover.${feed.id}',
      title: '${feed.emoji} ${feed.label}',
      child: items.when(
        data: (list) => list.isEmpty ? Text('Nothing here yet.', style: t.text.caption) : RecipeRow(recipes: list, onOpen: onOpen),
        loading: () => SizedBox(height: 200 * t.scale, child: const Row(children: [Expanded(child: DSkeleton()), SizedBox(width: 12), Expanded(child: DSkeleton()), SizedBox(width: 12), Expanded(child: DSkeleton())])),
        error: (_, _) => Text('Recipes aren’t available right now.', style: t.text.caption),
      ),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.query, required this.onOpen});
  final String query;
  final void Function(RecipeData) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final results = ref.watch(recipeSearchProvider(query));
    return results.when(
      data: (list) => list.isEmpty
          ? DEmptyState(id: 'discover.empty', emoji: '🔎', title: 'No recipes match “$query”', message: 'Try an ingredient (“chicken”) or a cuisine (“Mexican”).')
          : RecipeGrid(recipes: list, onOpen: onOpen),
      loading: () => Padding(padding: EdgeInsets.all(t.space.xl), child: const Center(child: CircularProgressIndicator())),
      error: (_, _) => const DEmptyState(emoji: '📡', title: 'Search isn’t available right now', message: 'Your recipe box still works offline.'),
    );
  }
}

/// Recipe tiles in as many columns as fit.
class RecipeGrid extends StatelessWidget {
  const RecipeGrid({super.key, required this.recipes, required this.onOpen});
  final List<RecipeData> recipes;
  final void Function(RecipeData) onOpen;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return LayoutBuilder(builder: (context, box) {
      final gap = t.space.sm;
      final cols = math.max(2, (box.maxWidth / ((t.isPhone ? 170 : 240) * t.scale)).floor());
      final w = (box.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final r in recipes) SizedBox(width: w, child: RecipeTile(recipe: r, imageHeight: w * 0.6, onTap: () => onOpen(r))),
        ],
      );
    });
  }
}
