import 'package:dearth_core/dearth_core.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'calendar.dart';
import 'household.dart';

// ──────────────────────────────── Lists ─────────────────────────────────────

final listsProvider = StreamProvider<List<DList>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.lists)
        ..where((l) => l.deleted.equals(false) & l.isTemplate.equals(false))
        ..orderBy([(l) => OrderingTerm.asc(l.sortKey), (l) => OrderingTerm.asc(l.title)]))
      .watch();
});

final listItemsProvider = StreamProvider.family<List<ListItem>, String>((ref, listId) {
  final db = ref.watch(dbProvider);
  return (db.select(db.listItems)
        ..where((i) => i.listId.equals(listId) & i.deleted.equals(false))
        ..orderBy([(i) => OrderingTerm.asc(i.checked), (i) => OrderingTerm.asc(i.sortKey)]))
      .watch();
});

/// Unchecked item counts per list (badges, Home preview).
final openItemCountsProvider = StreamProvider<Map<String, int>>((ref) {
  final db = ref.watch(dbProvider);
  final count = db.listItems.id.count();
  final q = db.selectOnly(db.listItems)
    ..addColumns([db.listItems.listId, count])
    ..where(db.listItems.deleted.equals(false) & db.listItems.checked.equals(false))
    ..groupBy([db.listItems.listId]);
  return q.watch().map((rows) => {for (final r in rows) r.read(db.listItems.listId)!: r.read(count) ?? 0});
});

// ──────────────────────────────── Notes ─────────────────────────────────────

/// Notes and announcements that are live now (FR-NOTE-01).
final activeNotesProvider = Provider<List<Note>>((ref) {
  final notes = ref.watch(_notesProvider).value ?? const <Note>[];
  final now = ref.watch(nowMinuteMsProvider);
  return [
    for (final n in notes)
      if ((n.startsMs == null || n.startsMs! <= now) && (n.expiresMs == null || n.expiresMs! > now)) n,
  ];
});

final _notesProvider = StreamProvider<List<Note>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.notes)
        ..where((n) => n.deleted.equals(false))
        ..orderBy([(n) => OrderingTerm.desc(n.pinned), (n) => OrderingTerm.asc(n.sortKey), (n) => OrderingTerm.desc(n.id)]))
      .watch();
});

// ──────────────────────────────── Meals ─────────────────────────────────────

@immutable
class PlannedMeal {
  const PlannedMeal(this.entry, this.recipe);
  final MealEntry entry;
  final Recipe? recipe;
  String get title => recipe?.title ?? entry.title ?? 'Meal';
}

final mealSlotsProvider = Provider<List<(String id, String label, String emoji)>>((ref) {
  final v = ref.watch(settingProvider(SettingKeys.mealSlots)).value;
  final slots = <(String, String, String)>[
    if (v is List)
      for (final s in v)
        if (s is Map) ('${s['id']}', '${s['label'] ?? s['id']}', '${s['emoji'] ?? '🍽️'}'),
  ];
  return slots.isEmpty ? const [('breakfast', 'Breakfast', '🥣'), ('lunch', 'Lunch', '🥪'), ('dinner', 'Dinner', '🍽️')] : slots;
});

final mealsInRangeProvider = StreamProvider.family<List<PlannedMeal>, DayRange>((ref, range) {
  final db = ref.watch(dbProvider);
  final q = db.select(db.mealEntries).join([leftOuterJoin(db.recipes, db.recipes.id.equalsExp(db.mealEntries.recipeId))])
    ..where(db.mealEntries.deleted.equals(false) &
        db.mealEntries.date.isBiggerOrEqualValue(range.start.iso) &
        db.mealEntries.date.isSmallerThanValue(range.end.iso))
    ..orderBy([OrderingTerm.asc(db.mealEntries.date), OrderingTerm.asc(db.mealEntries.sortKey)]);
  return q.watch().map((rows) => [
        for (final r in rows) PlannedMeal(r.readTable(db.mealEntries), r.readTableOrNull(db.recipes)),
      ]);
});

/// Tonight's dinner and tomorrow's (FR-MEAL-05).
final dinnerPreviewProvider = Provider<(PlannedMeal?, PlannedMeal?)>((ref) {
  final today = ref.watch(todayProvider);
  final meals = ref.watch(mealsInRangeProvider(DayRange(today, 2))).value ?? const <PlannedMeal>[];
  PlannedMeal? pick(LocalDate d) {
    final day = meals.where((m) => m.entry.date == d.iso).toList();
    return day.where((m) => m.entry.slot == 'dinner').firstOrNull ?? day.lastOrNull;
  }

  return (pick(today), pick(today.addDays(1)));
});

// ──────────────────────────────── Kids ──────────────────────────────────────

final choresProvider = StreamProvider<List<Chore>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.chores)
        ..where((c) => c.deleted.equals(false))
        ..orderBy([(c) => OrderingTerm.asc(c.sortKey), (c) => OrderingTerm.asc(c.title)]))
      .watch();
});

final _choreInstancesProvider = StreamProvider.family<List<ChoreInstance>, String>((ref, isoDate) {
  final db = ref.watch(dbProvider);
  return (db.select(db.choreInstances)..where((c) => c.date.equals(isoDate) & c.deleted.equals(false))).watch();
});

/// A due chore with its completion state for one day.
@immutable
class ChoreToday {
  const ChoreToday(this.due, this.instance);
  final DueChore due;
  final ChoreInstance? instance;
  String get status => instance?.status ?? ChoreStatus.pending;
  bool get done => ChoreStatus.isComplete(status);
  bool get waitingApproval => status == ChoreStatus.done && due.chore.needsApproval;
}

final choresForDayProvider = Provider.family<List<ChoreToday>, LocalDate>((ref, day) {
  final chores = ref.watch(choresProvider).value ?? const <Chore>[];
  final instances = {for (final i in ref.watch(_choreInstancesProvider(day.iso)).value ?? const <ChoreInstance>[]) i.id: i};
  return [for (final d in dueChores(chores, day)) ChoreToday(d, instances[d.instanceId])];
});

final choresTodayProvider = Provider<List<ChoreToday>>((ref) => ref.watch(choresForDayProvider(ref.watch(todayProvider))));

final ledgerProvider = StreamProvider<List<LedgerEntry>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.ledgerEntries)..where((l) => l.deleted.equals(false))).watch();
});

/// Balances per currency for a profile (null = family pool).
final balancesProvider = Provider.family<Map<String, int>, String?>((ref, profileId) {
  final entries = ref.watch(ledgerProvider).value ?? const <LedgerEntry>[];
  return balances(entries, profileId);
});
