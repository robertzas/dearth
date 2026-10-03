import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';

import 'recipe_provider.dart';

/// A bundled, offline recipe catalog: powers demo mode, Solo mode without
/// network, and deterministic E2E tests (`DEARTH_FAKE_PROVIDERS`). Recipes
/// intentionally share ingredients so plan-aware suggestions have something
/// to find.
typedef _R = (String id, String title, String cuisine, String category, int servings, int minutes, String emoji, List<String> ing, List<String> steps);

const List<_R> _catalog = [
  ('chicken-tacos', 'Chicken soft tacos', 'Mexican', 'Dinner', 4, 30, '🌮', [
    '1 lb boneless chicken thighs', '1 tbsp taco seasoning', '1 tbsp olive oil', '8 small flour tortillas', //
    '1 bunch cilantro', '2 limes', '1 cup shredded cheddar', '1 cup salsa', '1/2 cup sour cream',
  ], [
    'Toss the chicken with taco seasoning and oil.', 'Cook in a hot skillet 6–7 minutes per side, then slice.', //
    'Warm the tortillas.', 'Fill with chicken, cheese, salsa, cilantro and a squeeze of lime.',
  ]),
  ('cilantro-lime-rice', 'Cilantro lime rice', 'Mexican', 'Side', 4, 25, '🍚', [
    '1 cup long-grain rice', '2 cups chicken broth', '1 tbsp butter', '1/2 bunch cilantro', '2 limes', 'Salt to taste',
  ], [
    'Rinse the rice.', 'Simmer rice in broth with butter, covered, for 18 minutes.', 'Rest 5 minutes, then fold in chopped cilantro and lime juice.',
  ]),
  ('black-bean-soup', 'Black bean soup', 'Mexican', 'Soup', 6, 40, '🥣', [
    '2 cans black beans', '1 onion, diced', '3 cloves garlic, minced', '1 red bell pepper, diced', //
    '4 cups vegetable broth', '2 tsp cumin', '1 lime', '1/2 cup sour cream', '1/4 bunch cilantro',
  ], [
    'Soften onion and pepper in a pot for 8 minutes.', 'Add garlic and cumin for 1 minute.', //
    'Add beans and broth; simmer 20 minutes.', 'Blend half the soup, stir in lime juice, and top with sour cream and cilantro.',
  ]),
  ('quesadillas', 'Cheesy bean quesadillas', 'Mexican', 'Lunch', 4, 15, '🧀', [
    '8 flour tortillas', '2 cups shredded cheddar', '1 can black beans, drained', '1 red bell pepper, diced', '1/2 cup salsa', '1/2 cup sour cream',
  ], [
    'Sprinkle cheese, beans and pepper over half the tortillas; top with the rest.', 'Cook 3 minutes per side until golden.', 'Cut into wedges; serve with salsa and sour cream.',
  ]),
  ('burrito-bowls', 'Burrito bowls', 'Mexican', 'Dinner', 4, 35, '🌯', [
    '1 lb ground beef', '1 tbsp taco seasoning', '1 cup rice', '1 can black beans', '1 cup corn', '1 cup salsa', //
    '1 bunch cilantro', '2 limes', '1 avocado', '1 cup shredded cheddar',
  ], [
    'Cook the rice for 18 minutes.', 'Brown the beef with taco seasoning for 8 minutes.', 'Warm beans and corn.', //
    'Build bowls with rice, beef, beans, corn, salsa, avocado, cheese, cilantro and lime.',
  ]),
  ('fish-tacos', 'Fish tacos', 'Mexican', 'Dinner', 4, 30, '🐟', [
    '1 lb cod', '1 tsp chili powder', '8 corn tortillas', '2 cups shredded cabbage', '1 bunch cilantro', '2 limes', '1/2 cup sour cream', '1 avocado',
  ], [
    'Season the cod with chili powder and salt.', 'Bake at 400°F for 12 minutes, then flake.', 'Mix sour cream with lime juice.', 'Fill tortillas with fish, cabbage, avocado, cilantro and lime crema.',
  ]),
  ('spaghetti-bolognese', 'Spaghetti bolognese', 'Italian', 'Dinner', 6, 45, '🍝', [
    '1 lb spaghetti', '1 lb ground beef', '1 onion, diced', '2 carrots, diced', '2 stalks celery, diced', '3 cloves garlic, minced', //
    '1 (28 oz) can crushed tomatoes', '2 tbsp tomato paste', '1/2 cup milk', '1/2 cup grated parmesan', '2 tbsp olive oil',
  ], [
    'Soften onion, carrot and celery in oil for 10 minutes.', 'Add beef and garlic; brown for 8 minutes.', //
    'Stir in tomato paste, tomatoes and milk; simmer 25 minutes.', 'Cook spaghetti for 10 minutes; toss with sauce and parmesan.',
  ]),
  ('mac-and-cheese', 'Baked mac and cheese', 'American', 'Dinner', 6, 40, '🧀', [
    '1 lb elbow macaroni', '4 tbsp butter', '1/4 cup flour', '3 cups milk', '3 cups shredded cheddar', '1/2 cup grated parmesan', '1/2 cup panko', '1 tsp mustard powder',
  ], [
    'Cook macaroni for 6 minutes; drain.', 'Melt butter, whisk in flour, then milk; simmer 5 minutes until thick.', //
    'Stir in cheddar and mustard; fold in pasta.', 'Top with panko and parmesan; bake at 375°F for 20 minutes.',
  ]),
  ('chicken-noodle-soup', 'Chicken noodle soup', 'American', 'Soup', 6, 45, '🍲', [
    '1 lb chicken breast', '8 cups chicken broth', '2 carrots, sliced', '2 stalks celery, sliced', '1 onion, diced', //
    '2 cloves garlic, minced', '8 oz egg noodles', '1/4 bunch parsley', '1 tbsp butter',
  ], [
    'Soften onion, carrot and celery in butter for 8 minutes.', 'Add broth and chicken; simmer 20 minutes.', //
    'Shred the chicken and return it to the pot.', 'Add noodles and cook 8 minutes; finish with parsley.',
  ]),
  ('fried-rice', 'Veggie fried rice', 'Chinese', 'Dinner', 4, 25, '🍳', [
    '3 cups cooked rice', '3 eggs', '1 cup frozen peas and carrots', '4 green onions, sliced', '3 tbsp soy sauce', //
    '2 cloves garlic, minced', '1 tbsp sesame oil', '1 tbsp vegetable oil',
  ], [
    'Scramble the eggs in oil; set aside.', 'Fry garlic and vegetables for 3 minutes.', 'Add rice and soy sauce; fry 5 minutes.', 'Fold in eggs, green onions and sesame oil.',
  ]),
  ('teriyaki-salmon', 'Teriyaki salmon', 'Japanese', 'Dinner', 4, 25, '🍣', [
    '4 salmon fillets', '1/3 cup soy sauce', '2 tbsp honey', '1 tbsp rice vinegar', '1 tbsp grated ginger', '2 cloves garlic, minced', //
    '2 green onions', '1 tsp sesame seeds', '1 cup rice',
  ], [
    'Cook the rice for 18 minutes.', 'Simmer soy sauce, honey, vinegar, ginger and garlic for 3 minutes.', //
    'Brush salmon with sauce; bake at 400°F for 12 minutes.', 'Top with green onions and sesame seeds.',
  ]),
  ('lemon-herb-chicken', 'Sheet-pan lemon herb chicken', 'Mediterranean', 'Dinner', 4, 45, '🍋', [
    '2 lb chicken thighs', '1 lb baby potatoes, halved', '2 cups broccoli florets', '1 lemon', '3 cloves garlic, minced', //
    '2 tbsp olive oil', '1 tsp dried oregano', '1/4 bunch parsley',
  ], [
    'Toss potatoes with oil and roast at 425°F for 15 minutes.', 'Add chicken, garlic, oregano and lemon slices; roast 20 minutes.', //
    'Add broccoli for the last 10 minutes.', 'Finish with parsley and lemon juice.',
  ]),
  ('banana-pancakes', 'Banana pancakes', 'American', 'Breakfast', 4, 20, '🥞', [
    '1 1/2 cups flour', '2 ripe bananas', '1 cup milk', '1 egg', '2 tbsp sugar', '2 tsp baking powder', '2 tbsp butter, melted', 'Maple syrup for serving',
  ], [
    'Mash the bananas; whisk in milk, egg and butter.', 'Stir in flour, sugar and baking powder until just combined.', //
    'Cook 1/4-cup scoops for 2 minutes per side.', 'Serve warm with maple syrup.',
  ]),
  ('turkey-meatballs', 'Turkey meatballs & spaghetti', 'Italian', 'Dinner', 4, 35, '🍝', [
    '1 lb ground turkey', '1/2 cup panko', '1 egg', '1/4 cup grated parmesan', '2 cloves garlic, minced', '1/4 bunch parsley', //
    '1 jar marinara sauce', '1 lb spaghetti',
  ], [
    'Mix turkey, panko, egg, parmesan, garlic and parsley.', 'Roll into 1-inch balls; bake at 400°F for 15 minutes.', //
    'Simmer meatballs in marinara for 10 minutes.', 'Serve over spaghetti.',
  ]),
  ('flatbread-pizza', 'Margherita flatbread pizza', 'Italian', 'Dinner', 4, 20, '🍕', [
    '2 naan flatbreads', '1 cup marinara sauce', '8 oz fresh mozzarella', '2 tomatoes, sliced', '1 bunch basil', '1 tbsp olive oil',
  ], [
    'Heat the oven to 450°F.', 'Spread marinara on the flatbreads; add mozzarella and tomato.', 'Bake 10 minutes until bubbly.', 'Top with basil and a drizzle of oil.',
  ]),
  ('greek-chicken-wraps', 'Greek chicken wraps', 'Greek', 'Lunch', 4, 25, '🥙', [
    '1 lb chicken breast', '4 pitas', '1 cucumber', '2 tomatoes', '1/2 red onion', '1 cup greek yogurt', '1/2 cup crumbled feta', //
    '1 lemon', '1 tsp dried oregano', '2 cloves garlic, minced',
  ], [
    'Season chicken with oregano, lemon and garlic; grill 6 minutes per side.', 'Grate half the cucumber into yogurt for tzatziki.', //
    'Slice the remaining vegetables.', 'Wrap chicken, vegetables, feta and tzatziki in warm pitas.',
  ]),
  ('beef-chili', 'Beef and bean chili', 'American', 'Dinner', 6, 60, '🌶️', [
    '1 lb ground beef', '1 onion, diced', '1 red bell pepper, diced', '3 cloves garlic, minced', '2 cans kidney beans', '1 can black beans', //
    '1 (28 oz) can crushed tomatoes', '2 tbsp chili powder', '2 tsp cumin', '1 cup shredded cheddar', '1/2 cup sour cream', '2 green onions',
  ], [
    'Brown beef with onion and pepper for 10 minutes.', 'Add garlic and spices for 1 minute.', 'Add beans and tomatoes; simmer 40 minutes.', //
    'Top with cheddar, sour cream and green onions.',
  ]),
  ('broccoli-cheddar-soup', 'Broccoli cheddar soup', 'American', 'Soup', 4, 35, '🥦', [
    '4 cups broccoli florets', '1 onion, diced', '2 carrots, grated', '4 tbsp butter', '1/4 cup flour', '2 cups milk', '2 cups chicken broth', '2 cups shredded cheddar',
  ], [
    'Soften onion in butter for 5 minutes.', 'Whisk in flour, then milk and broth; simmer 5 minutes.', //
    'Add broccoli and carrot; simmer 15 minutes.', 'Stir in cheddar until melted.',
  ]),
  ('minestrone', 'Minestrone', 'Italian', 'Soup', 6, 45, '🥣', [
    '1 onion, diced', '2 carrots, diced', '2 stalks celery, diced', '2 zucchini, diced', '3 cloves garlic, minced', '1 can diced tomatoes', //
    '1 can cannellini beans', '6 cups vegetable broth', '1 cup small pasta', '2 cups spinach', '1/2 cup grated parmesan', '1 bunch basil',
  ], [
    'Soften onion, carrot and celery for 8 minutes.', 'Add zucchini and garlic for 3 minutes.', 'Add tomatoes, beans and broth; simmer 15 minutes.', //
    'Add pasta for 8 minutes, then spinach.', 'Serve with parmesan and basil.',
  ]),
  ('shepherds-pie', "Shepherd's pie", 'British', 'Dinner', 6, 60, '🥧', [
    '1 lb ground beef', '1 onion, diced', '2 carrots, diced', '1 cup frozen peas', '2 tbsp tomato paste', '1 cup beef broth', //
    '2 lb potatoes', '1/2 cup milk', '4 tbsp butter', '1 tbsp worcestershire sauce',
  ], [
    'Boil potatoes 15 minutes; mash with milk and butter.', 'Brown beef with onion and carrot for 10 minutes.', //
    'Add tomato paste, broth, worcestershire and peas; simmer 10 minutes.', 'Top with mash and bake at 400°F for 20 minutes.',
  ]),
  ('overnight-oats', 'Blueberry overnight oats', 'American', 'Breakfast', 2, 5, '🫐', [
    '1 cup rolled oats', '1 cup milk', '1/2 cup greek yogurt', '1 tbsp maple syrup', '1 cup blueberries', '1 banana',
  ], [
    'Stir oats, milk, yogurt and maple syrup together.', 'Fold in blueberries; refrigerate overnight.', 'Top with sliced banana.',
  ]),
  ('chicken-stir-fry', 'Chicken & broccoli stir-fry', 'Chinese', 'Dinner', 4, 25, '🥢', [
    '1 lb chicken breast', '2 cups broccoli florets', '1 red bell pepper', '2 carrots', '3 tbsp soy sauce', '1 tbsp honey', '1 tbsp cornstarch', //
    '2 cloves garlic, minced', '1 tbsp grated ginger', '2 green onions', '1 cup rice',
  ], [
    'Cook the rice for 18 minutes.', 'Stir-fry sliced chicken for 6 minutes; set aside.', 'Stir-fry vegetables with garlic and ginger for 4 minutes.', //
    'Add chicken and a sauce of soy, honey and cornstarch; cook 2 minutes.',
  ]),
  ('pesto-pasta', 'Pesto pasta with peas', 'Italian', 'Dinner', 4, 20, '🌿', [
    '1 lb penne', '1/2 cup basil pesto', '1 cup frozen peas', '1 cup cherry tomatoes', '1/2 cup grated parmesan', '1 lemon',
  ], [
    'Cook penne for 10 minutes, adding peas for the last 2.', 'Toss with pesto, halved tomatoes and lemon juice.', 'Finish with parmesan.',
  ]),
  ('fruit-smoothie', 'Strawberry banana smoothie', 'American', 'Snack', 2, 5, '🥤', [
    '1 banana', '1 cup frozen strawberries', '1/2 cup greek yogurt', '1 cup milk', '1 tbsp honey', '1 cup spinach',
  ], [
    'Blend everything for 1 minute until smooth.', 'Pour and enjoy.',
  ]),
];

/// Emoji for a catalog recipe id (UI placeholder art).
String? catalogEmoji(String recipeId) {
  final id = recipeId.startsWith('catalog:') ? recipeId.substring(8) : recipeId;
  for (final r in _catalog) {
    if (r.$1 == id) return r.$7;
  }
  return null;
}

List<RecipeData>? _built;

/// The bundled catalog as normalized recipes (built once).
List<RecipeData> get recipeCatalog => _built ??= [
      for (final r in _catalog)
        RecipeData(
          id: providerRecipeId('catalog', r.$1),
          source: 'catalog',
          sourceId: r.$1,
          title: r.$2,
          cuisine: r.$3,
          category: r.$4,
          servings: r.$5,
          totalMin: r.$6,
          tags: [r.$4.toLowerCase(), r.$7],
          ingredients: [for (final l in r.$8) parseIngredientLine(l)],
          steps: r.$9,
          attribution: 'Dearth family recipes',
        ),
    ];

/// Offline provider over [recipeCatalog] (demo, Solo-offline, E2E).
class CatalogRecipes implements RecipeProvider {
  CatalogRecipes({int seed = 7}) : _random = math.Random(seed);
  final math.Random _random;

  @override
  String get id => 'catalog';
  @override
  String get displayName => 'Family recipes';

  @override
  Future<List<RecipeData>> search(RecipeQuery query) async {
    final text = query.text?.toLowerCase().trim() ?? '';
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final scored = <(RecipeData, int)>[];
    for (final r in recipeCatalog) {
      final hay = '${r.title} ${r.cuisine} ${r.category} ${r.ingredients.map((i) => i.key).join(' ')}'.toLowerCase();
      if (words.isNotEmpty && !words.every(hay.contains)) continue;
      if (query.cuisine != null && r.cuisine?.toLowerCase() != query.cuisine!.toLowerCase()) continue;
      if (query.category != null && r.category?.toLowerCase() != query.category!.toLowerCase()) continue;
      if (query.maxMinutes != null && (r.totalMin ?? 0) > query.maxMinutes!) continue;
      if (query.excludeIngredients.any((ex) => r.ingredients.any((i) => i.key.contains(ex.toLowerCase())))) continue;
      final hits = query.includeIngredients.where((inc) => r.ingredients.any((i) => i.key.contains(inc.toLowerCase()))).length;
      if (query.includeIngredients.isNotEmpty && hits == 0) continue;
      final titleHit = words.isNotEmpty && r.title.toLowerCase().contains(text) ? 10 : 0;
      scored.add((r, hits * 3 + titleHit));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    return scored.take(query.limit).map((e) => e.$1).toList();
  }

  @override
  Future<List<RecipeData>> random(int count, {String? tag}) async {
    final pool = [...recipeCatalog.where((r) => tag == null || r.tags.contains(tag.toLowerCase()))]..shuffle(_random);
    return pool.take(count).toList();
  }

  @override
  Future<RecipeData?> lookup(String sourceId) async =>
      recipeCatalog.where((r) => r.sourceId == sourceId || r.id == sourceId).firstOrNull;

  @override
  Future<List<String>> cuisines() async => {for (final r in recipeCatalog) r.cuisine!}.toList()..sort();
}
