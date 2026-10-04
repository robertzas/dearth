import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_integrations/dearth_integrations.dart' show catalogPhotoUrl;
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/providers.dart';
import '../core/sync/hub_api.dart';

/// A recipe's photo (Hub blob or proxied URL, decoded at display size;
/// SPEC §12.5) or, without one, its emoji on a warm food-toned gradient.
class RecipeVisual extends ConsumerWidget {
  const RecipeVisual({super.key, this.recipe, this.data, required this.title, required this.height, this.radius});

  /// A local recipe row, or [data] for a recipe that isn't local yet
  /// (search and discover results).
  final Recipe? recipe;
  final RecipeData? data;
  final String title;
  final double height;
  final BorderRadius? radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final r = radius ?? t.radius.card;
    final api = ref.watch(hubApiProvider);
    // Tests stay offline: no photos from other sites.
    final remote = !ref.watch(envProvider).e2e;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return SizedBox(
      height: height,
      child: LayoutBuilder(builder: (context, box) {
        final w = (box.maxWidth.isFinite ? box.maxWidth : 600) * dpr;
        // A catalog recipe saved before the catalog had photos finds its own.
        final link = recipe?.imageUrl ?? data?.imageUrl ?? (recipe?.source == 'catalog' ? catalogPhotoUrl(recipe?.sourceId) : null);
        final url = _imageUrl(recipe?.imageBlob ?? data?.imageBlob, remote ? link : null, api, w.round());
        final emoji = data != null && recipe == null ? recipeEmojiFor(data!.tags, data!.category, title) : recipeEmoji(recipe, title);
        final fallback = _EmojiTile(emoji: emoji, seed: title, radius: r);
        if (url == null) return fallback;
        return ClipRRect(
          borderRadius: r,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            width: double.infinity,
            height: height,
            cacheWidth: w.round(),
            errorBuilder: (_, _, _) => fallback,
            frameBuilder: (context, child, frame, sync) => sync || frame != null ? child : fallback,
          ),
        );
      }),
    );
  }

  static String? _imageUrl(String? blob, String? u, HubApi? api, int width) {
    final sha = blobSha(blob);
    if (sha != null && api != null) return api.blobUrl(sha, width: width).toString();
    if (u == null || u.isEmpty) return null;
    return api != null ? api.imageProxy(u, width: width).toString() : u;
  }
}

/// A recipe's emoji: a tag that is an emoji, else one by category/title.
String recipeEmoji(Recipe? r, String title) => recipeEmojiFor(decodeStringList(r?.tags), r?.category, title);

String recipeEmojiFor(List<String> tags, String? category, String title) {
  for (final tag in tags) {
    if (tag.isNotEmpty && tag.runes.first > 0x2000) return tag;
  }
  final s = '${category ?? ''} $title'.toLowerCase();
  const map = {
    'pizza': '🍕', 'taco': '🌮', 'burrito': '🌯', 'pasta': '🍝', 'spaghetti': '🍝', 'noodle': '🍜', 'soup': '🥣', //
    'salad': '🥗', 'curry': '🍛', 'rice': '🍚', 'salmon': '🐟', 'fish': '🐟', 'chicken': '🍗', 'burger': '🍔',
    'pancake': '🥞', 'egg': '🍳', 'breakfast': '🥞', 'dessert': '🍰', 'cake': '🍰', 'cookie': '🍪', 'sandwich': '🥪',
    'steak': '🥩', 'beef': '🥩', 'pork': '🥓', 'shrimp': '🍤', 'sushi': '🍣', 'out': '🍽️', 'leftover': '🥡',
  };
  for (final e in map.entries) {
    if (s.contains(e.key)) return e.value;
  }
  return '🍽️';
}

class _EmojiTile extends StatelessWidget {
  const _EmojiTile({required this.emoji, required this.seed, required this.radius});
  final String emoji;
  final String seed;
  final BorderRadius radius;

  static const _palettes = [
    (Color(0xFFFFE3C2), Color(0xFFFFB98A)),
    (Color(0xFFFFF0B3), Color(0xFFFFCF6B)),
    (Color(0xFFDDF3D2), Color(0xFFA9DB8E)),
    (Color(0xFFFFD6D1), Color(0xFFF59C8F)),
    (Color(0xFFE7DEFF), Color(0xFFBBA6F5)),
    (Color(0xFFD5ECFF), Color(0xFF9CCBF5)),
  ];

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final (a, b) = _palettes[seed.hashCode.abs() % _palettes.length];
    final dim = t.colors.isDark;
    return LayoutBuilder(builder: (context, box) {
      final size = (box.maxHeight.isFinite ? box.maxHeight : 120) * 0.62;
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dim ? [Color.lerp(a, t.colors.surfaceRaised, 0.75)!, Color.lerp(b, t.colors.surfaceRaised, 0.7)!] : [a, b],
          ),
        ),
        child: Center(child: DEmoji(emoji, size: size)),
      );
    });
  }
}
