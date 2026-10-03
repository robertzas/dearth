import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_integrations/dearth_integrations.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('demo seed applies cleanly on top of household defaults', () async {
    final db = DearthDb(NativeDatabase.memory());
    addTearDown(db.close);
    final store = SyncStore(db);
    final m = Mutator(store: store, clock: HlcClock('demo'), sink: (_) async {});
    final time = HouseholdTime.named('America/Denver');
    await m.commit(householdDefaultOps(m, timezone: time.zoneName));
    await m.commit(await demoSeedOps(m, time));

    final profiles = await db.select(db.profiles).get();
    expect(profiles.map((p) => p.name), containsAll(['Mom', 'Dad', 'Ava', 'Biscuit']));
    final ava = profiles.firstWhere((p) => p.id == DemoIds.ava);
    expect(ava.kidStage, KidStage.little);

    final events = await db.select(db.events).get();
    final today = time.today();
    final occ = RecurrenceExpander(time).forDay(events, today);
    expect(occ.map((o) => o.event.title), contains('Library story time'));

    final due = dueChores(await db.select(db.chores).get(), today);
    expect(due.where((d) => d.profileId == DemoIds.ava).length, greaterThanOrEqualTo(4));

    final ledger = await db.select(db.ledgerEntries).get();
    expect(balances(ledger, DemoIds.ava)[Currency.sticker], 6);

    final meals = await db.select(db.mealEntries).get();
    expect(meals.length, 7);
    final recipes = await db.select(db.recipes).get();
    expect(recipes.every((r) => RecipeData.fromRow(r).ingredients.isNotEmpty), isTrue);

    final weather = WeatherReport.tryDecode((await db.select(db.weatherReports).getSingle()).data);
    expect(weather!.daily.length, 10);
    expect((await db.select(db.musicTiles).get()).length, kBuiltinSongs.length);
  });
}
