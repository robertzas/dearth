import 'package:dearth_core/dearth_core.dart';
import 'package:meta/meta.dart';

/// Search filters shared by every provider (SPEC FR-RCP-03).
@immutable
class RecipeQuery {
  const RecipeQuery({
    this.text,
    this.includeIngredients = const [],
    this.excludeIngredients = const [],
    this.cuisine,
    this.category,
    this.diet,
    this.maxMinutes,
    this.sortByPopularity = false,
    this.limit = 20,
  });

  final String? text;
  final List<String> includeIngredients;
  final List<String> excludeIngredients;
  final String? cuisine;
  final String? category;
  final String? diet;
  final int? maxMinutes;
  final bool sortByPopularity;
  final int limit;

  String get cacheKey => [
        text, includeIngredients.join(','), excludeIngredients.join(','), cuisine, category, diet, maxMinutes, //
        sortByPopularity, limit,
      ].join('|');
}

/// A recipe provider (SPEC §13.6). Results are normalized [RecipeData] whose
/// `id` is `<provider>:<sourceId>` until saved locally.
abstract interface class RecipeProvider {
  String get id;
  String get displayName;

  Future<List<RecipeData>> search(RecipeQuery query);
  Future<List<RecipeData>> random(int count, {String? tag});
  Future<RecipeData?> lookup(String sourceId);
  Future<List<String>> cuisines();
}

/// Provider-qualified id for unsaved results.
String providerRecipeId(String provider, String sourceId) => '$provider:$sourceId';
