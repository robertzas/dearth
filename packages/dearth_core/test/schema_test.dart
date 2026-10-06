import 'dart:io';

import 'package:dearth_core/dearth_core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

/// Schema migrations (SPEC §8.4.5): a database made by an older version
/// opens in this one with its data intact and the new tables added.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('version 1 → 2: the Hub gains its recipe cache; existing rows stay', () async {
    final dir = await Directory.systemTemp.createTemp('dearth-schema');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/dearth.db');

    // A version 1 database: today's tables without the recipe cache.
    var db = DearthDb(NativeDatabase(file));
    await db.into(db.jobStates).insert(JobStatesCompanion.insert(id: 'photos'));
    await db.customStatement('DROP TABLE recipe_cache');
    await db.customStatement('PRAGMA user_version = 1');
    await db.close();

    db = DearthDb(NativeDatabase(file));
    addTearDown(db.close);
    expect(await db.select(db.recipeCache).get(), isEmpty, reason: 'the table exists');
    await db.into(db.recipeCache).insert(RecipeCacheCompanion.insert(id: 'themealdb:1', source: 'themealdb', title: 'Tacos', data: '{}', firstSeenMs: 1, lastSeenMs: 1));
    expect(await db.select(db.recipeCache).get(), hasLength(1));
    expect((await db.select(db.jobStates).get()).single.id, 'photos');
    expect(await db.customSelect('PRAGMA user_version').map((r) => r.read<int>('user_version')).getSingle(), db.schemaVersion);
  });
}
