import 'package:dearth_app/features/calendar/event_ops.dart' show MakeOp;
import 'package:dearth_app/features/meals/cook_mode.dart' show ingredientsForStep;
import 'package:dearth_app/features/meals/meal_ops.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_integrations/dearth_integrations.dart' show recipeCatalog;
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Meal planning, ratings and "add to list" (SPEC §10.5) through a real
/// device database.
void main() {
  late DearthDb db;
  late Mutator m;
  const saturday = LocalDate(2026, 10, 3);

  MakeOp op() => (table, id, fields, {kind = OpKind.upsert}) => m.makeOp(table, id, fields, kind: kind);
  RecipeData catalog(String sourceId) => recipeCatalog.firstWhere((r) => r.sourceId == sourceId);
  Future<List<Recipe>> recipes() => (db.select(db.recipes)..where((r) => r.deleted.equals(false))).get();
  Future<List<MealEntry>> entries() => (db.select(db.mealEntries)..where((e) => e.deleted.equals(false))).get();
  Future<List<ListItem>> items() => (db.select(db.listItems)..where((i) => i.deleted.equals(false))..orderBy([(i) => OrderingTerm.asc(i.sortKey)])).get();

  setUp(() {
    db = DearthDb(NativeDatabase.memory());
    m = Mutator(store: SyncStore(db), clock: HlcClock('test'), sink: (_) async {});
  });

  tearDown(() => db.close());

  group('FR-RCP-02 / FR-MEAL-01: planning', () {
    test('a provider recipe gets a stable local id (the demo seed’s)', () {
      final tacos = catalog('chicken-tacos');
      expect(localRecipeId(tacos), stableId('recipe', ['catalog', 'chicken-tacos']));
      const mine = RecipeData(id: 'r1', source: 'box', title: 'Grandma’s stew');
      expect(localRecipeId(mine), 'r1');
    });

    test('planning copies the recipe once, then only adds entries', () async {
      final tacos = catalog('chicken-tacos');
      await m.commit(planRecipeOps(op(), recipe: tacos, date: saturday, slot: 'dinner', servings: 4));
      final copied = (await recipes()).single;
      expect(copied.id, localRecipeId(tacos));
      expect(copied.saved, isFalse, reason: 'planning is not saving');
      expect(copied.title, 'Chicken soft tacos');

      // The family edits the local copy; planning again must not overwrite it.
      await m.commit([op()('recipes', copied.id, {'title': 'Taco night!'})]);
      final ops = planRecipeOps(op(), recipe: tacos, existing: (await recipes()).single, date: saturday.addDays(1), slot: 'dinner', servings: 6);
      expect(ops.where((o) => o.table == 'recipes'), isEmpty);
      await m.commit(ops);
      expect((await recipes()).single.title, 'Taco night!');
      final planned = await entries();
      expect(planned.map((e) => (e.date, e.slot, e.recipeId, e.servings)).toSet(), {
        ('2026-10-03', 'dinner', copied.id, 4),
        ('2026-10-04', 'dinner', copied.id, 6),
      });
    });

    test('free-text entries, moves, servings and removal', () async {
      await m.commit(planTextOps(op(), title: '  Leftovers ', date: saturday, slot: 'lunch', entryId: 'e1'));
      expect((await entries()).single.title, 'Leftovers');
      await m.commit(moveMealOps(op(), 'e1', date: saturday.addDays(1), slot: 'dinner'));
      await m.commit(mealServingsOps(op(), 'e1', 3));
      final e = (await entries()).single;
      expect((e.date, e.slot, e.servings, e.recipeId), ('2026-10-04', 'dinner', 3, null));
      await m.commit(removeMealOps(op(), 'e1'));
      expect(await entries(), isEmpty);
    });

    test('saving toggles the box flag without touching the recipe', () async {
      final soup = catalog('chicken-noodle-soup');
      await m.commit(saveRecipeOps(op(), soup, saved: true));
      expect((await recipes()).single.saved, isTrue);
      await m.commit(saveRecipeOps(op(), soup, existing: (await recipes()).single, saved: false));
      final r = (await recipes()).single;
      expect((r.saved, r.title), (false, 'Chicken noodle soup'));
    });
  });

  group('FR-RCP-06: ratings', () {
    test('one rating per person per recipe; tapping the same face clears it', () async {
      await m.commit(rateRecipeOps(op(), recipeId: 'r', profileId: 'ava', score: 2, nowMs: 1));
      await m.commit(rateRecipeOps(op(), recipeId: 'r', profileId: 'ava', score: -2, nowMs: 2));
      await m.commit(rateRecipeOps(op(), recipeId: 'r', profileId: 'dad', score: 1, nowMs: 3));
      final rows = await (db.select(db.recipeRatings)..where((r) => r.deleted.equals(false))).get();
      expect({for (final r in rows) r.profileId: r.score}, {'ava': -2, 'dad': 1});
      expect(rows.map((r) => r.id).toSet(), {ratingId('r', 'ava'), ratingId('r', 'dad')});
      await m.commit(rateRecipeOps(op(), recipeId: 'r', profileId: 'dad', score: null, nowMs: 4));
      expect((await (db.select(db.recipeRatings)..where((r) => r.deleted.equals(false))).get()).single.profileId, 'ava');
    });
  });

  group('FR-RCP-06 / FR-SHOP-01..03: add to the shopping list', () {
    test('skips staples and items already open; sorts after the list', () async {
      await m.commit([
        op()('list_items', 'milk', {'list_id': 'shop', 'text': 'Limes', 'sort_key': 'm'}),
        op()('list_items', 'done', {'list_id': 'shop', 'text': 'Cilantro', 'checked': true, 'sort_key': 'n'}),
      ]);
      final tacos = catalog('chicken-tacos');
      final res = addToListOps(op(), listId: 'shop', ingredients: tacos.ingredients, existing: await items(), lastSortKey: 'm');
      expect(res.staples, 1, reason: 'olive oil is a pantry staple');
      expect(res.alreadyListed, 1, reason: 'limes are already on the list');
      await m.commit(res.ops);
      final all = await items();
      final texts = [for (final i in all) i.itemText];
      expect(texts.first, 'Limes');
      expect(texts, contains('Cilantro'), reason: 'a checked item doesn’t count as listed');
      expect(texts.where((t) => t.toLowerCase().contains('olive')), isEmpty);
      final chicken = all.firstWhere((i) => i.itemText.toLowerCase().contains('chicken'));
      expect(chicken.category, Aisle.meatSeafood.name);
      expect(chicken.note, '1 lb');
      final keys = [for (final i in all) i.sortKey];
      expect(keys, [...keys]..sort(), reason: 'new items keep recipe order after the list');
    });

    test('the week’s lines merge shared ingredients and name their recipes', () async {
      final lines = consolidate([
        PlannedRecipe(catalog('chicken-tacos'), 4, label: 'Chicken soft tacos (Mon)'),
        PlannedRecipe(catalog('fish-tacos'), 4, label: 'Fish tacos (Thu)'),
      ]);
      final res = addLinesToListOps(op(), listId: 'shop', lines: lines, existing: const []);
      await m.commit(res.ops);
      final limes = (await items()).firstWhere((i) => i.itemText.toLowerCase().startsWith('lime'));
      expect(limes.note, contains('4'));
      expect(limes.note, contains('for Chicken soft tacos (Mon), Fish tacos (Thu)'));
    });
  });

  group('FR-RCP-07: cook mode', () {
    test('a step highlights the ingredients it names', () {
      final salmon = catalog('teriyaki-salmon');
      List<String> keys(String step) => [for (final i in ingredientsForStep(step, salmon.ingredients)) i.key];
      expect(keys('Cook the rice for 18 minutes.'), ['rice']);
      expect(keys('Simmer soy sauce, honey, vinegar, ginger and garlic for 3 minutes.'), containsAll(['soy sauce', 'honey', 'rice vinegar', 'garlic']));
      final tacos = catalog('chicken-tacos');
      expect([for (final i in ingredientsForStep('Toss the chicken with taco seasoning and oil.', tacos.ingredients)) i.key], contains(tacos.ingredients.first.key));
    });
  });
}
