import 'package:drift/drift.dart';

import 'tables.dart';

export 'tables.dart';

part 'database.g.dart';

/// The single Dearth database class. Devices and the Hub use the same schema;
/// device-local tables stay empty on the Hub and Hub-only tables stay empty on
/// devices (SPEC §8.1).
@DriftDatabase(
  tables: [
    Households,
    Profiles,
    Devices,
    Settings,
    CalendarSources,
    Events,
    Lists,
    ListItems,
    Notes,
    Recipes,
    MealEntries,
    ShoppingStates,
    RecipeRatings,
    Chores,
    ChoreInstances,
    Routines,
    RoutineRuns,
    Rewards,
    Redemptions,
    LedgerEntries,
    StickerPlacements,
    FeelingEntries,
    GameEvents,
    Artworks,
    MusicTiles,
    PhotoSources,
    PhotoItems,
    PhotoCollections,
    WeatherReports,
    KitchenTimers,
    HomeLayouts,
    Outbox,
    KvEntries,
    OpLog,
    DeviceAuths,
    Pairings,
    Secrets,
    Blobs,
    JobStates,
    RecipeCache,
  ],
)
class DearthDb extends _$DearthDb {
  DearthDb(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // Additive migrations go here, keyed by version (SPEC §8.4.5).
          if (from < 2) await m.createTable(recipeCache);
        },
      );

  // ── Device-local key/value helpers ────────────────────────────────────────

  Future<String?> kvGet(String key) async =>
      (await (select(kvEntries)..where((t) => t.key.equals(key))).getSingleOrNull())?.value;

  Future<void> kvSet(String key, String value) =>
      into(kvEntries).insertOnConflictUpdate(KvEntry(key: key, value: value));

  Future<void> kvDelete(String key) => (delete(kvEntries)..where((t) => t.key.equals(key))).go();

  Stream<String?> kvWatch(String key) =>
      (select(kvEntries)..where((t) => t.key.equals(key))).watchSingleOrNull().map((e) => e?.value);
}
