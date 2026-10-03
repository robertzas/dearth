import 'package:dearth_core/dearth_core.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/household.dart';
import '../../core/data/household_data.dart';
import '../../core/providers.dart';

/// The Kids screen's tab for the grown-ups' chores.
const String kGrownUpsTab = 'grown-ups';

class KidsTabController extends Notifier<String?> {
  @override
  String? build() => null;

  void show(String tab) => state = tab;
}

final _kidsTabChoiceProvider = NotifierProvider<KidsTabController, String?>(KidsTabController.new);

/// The selected tab: a kid's profile id, or [kGrownUpsTab]. Defaults to the
/// first kid.
final kidsTabProvider = Provider<String>((ref) {
  final choice = ref.watch(_kidsTabChoiceProvider);
  final kids = ref.watch(kidsProvider);
  if (choice == kGrownUpsTab) return choice!;
  if (choice != null && kids.any((k) => k.id == choice)) return choice;
  return kids.isEmpty ? kGrownUpsTab : kids.first.id;
});

void showKidsTab(WidgetRef ref, String tab) => ref.read(_kidsTabChoiceProvider.notifier).show(tab);

/// A kid's chores today: their own and the Anyone pool's kid chores
/// (SPEC FR-KID-01/02).
final kidChoresTodayProvider = Provider.family<List<ChoreToday>, String>((ref, kidId) => [
      for (final c in ref.watch(choresTodayProvider))
        if (!c.due.chore.adult && (c.due.profileId == kidId || c.due.profileId == null)) c,
    ]);

/// The grown-ups' household chores today (SPEC FR-KID-05).
final adultChoresTodayProvider = Provider<List<ChoreToday>>((ref) => [
      for (final c in ref.watch(choresTodayProvider))
        if (c.due.chore.adult) c,
    ]);

/// Completions waiting for a grown-up (SPEC FR-KID-03).
final waitingApprovalProvider = Provider<List<ChoreToday>>((ref) => [
      for (final c in ref.watch(choresTodayProvider))
        if (c.waitingApproval) c,
    ]);

// ──────────────────────────────── Routines ─────────────────────────────────

final routinesProvider = StreamProvider<List<Routine>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.routines)
        ..where((r) => r.deleted.equals(false) & r.active.equals(true))
        ..orderBy([(r) => OrderingTerm.asc(r.sortKey), (r) => OrderingTerm.asc(r.title)]))
      .watch();
});

final _routineRunsProvider = StreamProvider.family<List<RoutineRun>, String>((ref, isoDate) {
  final db = ref.watch(dbProvider);
  return (db.select(db.routineRuns)..where((r) => r.date.equals(isoDate) & r.deleted.equals(false))).watch();
});

/// A routine due today with its steps and today's run.
@immutable
class RoutineToday {
  const RoutineToday(this.routine, this.steps, this.run, this.date, this.profileId);
  final Routine routine;
  final List<RoutineStep> steps;
  final RoutineRun? run;
  final LocalDate date;
  final String? profileId;

  List<String> get doneSteps => decodeStringList(run?.doneSteps);
  bool get done => run?.status == 'done';
  int get progress => steps.where((s) => doneSteps.contains(s.id)).length;
}

final kidRoutinesTodayProvider = Provider.family<List<RoutineToday>, String>((ref, kidId) {
  final today = ref.watch(todayProvider);
  final routines = ref.watch(routinesProvider).value ?? const <Routine>[];
  final runs = {for (final r in ref.watch(_routineRunsProvider(today.iso)).value ?? const <RoutineRun>[]) r.id: r};
  return [
    for (final r in routines)
      if (_forKid(r, kidId) && isDueOn(r.rrule, LocalDate.tryParse(r.anchorDate) ?? today, today))
        RoutineToday(r, decodeSteps(r.steps), runs[routineRunId(r.id, today, kidId)], today, kidId),
  ];
});

bool _forKid(Routine r, String kidId) {
  final who = decodeStringList(r.profileIds);
  return who.isEmpty || who.contains(kidId);
}

// ──────────────────────────────── Rewards ──────────────────────────────────

final rewardsProvider = StreamProvider<List<Reward>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.rewards)
        ..where((r) => r.deleted.equals(false) & r.active.equals(true))
        ..orderBy([(r) => OrderingTerm.asc(r.cost), (r) => OrderingTerm.asc(r.title)]))
      .watch();
});

final redemptionsProvider = StreamProvider<List<Redemption>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.redemptions)
        ..where((r) => r.deleted.equals(false))
        ..orderBy([(r) => OrderingTerm.desc(r.requestedMs)]))
      .watch();
});

final stickerPlacementsProvider = StreamProvider.family<List<StickerPlacement>, String>((ref, kidId) {
  final db = ref.watch(dbProvider);
  return (db.select(db.stickerPlacements)
        ..where((s) => s.profileId.equals(kidId) & s.deleted.equals(false))
        ..orderBy([(s) => OrderingTerm.asc(s.atMs)]))
      .watch();
});

/// Tokens that fill a reward jar (SPEC FR-KID-13).
final jarCapacityProvider = Provider<int>((ref) {
  final v = ref.watch(settingProvider('kids.jarSize')).value;
  return v is num && v >= 3 ? v.toInt() : 10;
});

/// The kid's sticker book theme (SPEC FR-KID-12).
final stickerThemeProvider = Provider.family<String, String>((ref, kidId) {
  final v = ref.watch(settingProvider('kids.stickerTheme.$kidId')).value;
  return v is String && kStickerThemes.containsKey(v) ? v : 'farm';
});

/// The pinned star goal (SPEC FR-KID-14): the chosen store reward, else the
/// cheapest one.
final kidGoalProvider = Provider.family<Reward?, String>((ref, kidId) {
  final store = [for (final r in ref.watch(rewardsProvider).value ?? const <Reward>[]) if (r.kind == 'store' && r.currency == Currency.star) r];
  final chosen = ref.watch(settingProvider('kids.goal.$kidId')).value;
  return store.where((r) => r.id == chosen).firstOrNull ?? store.firstOrNull;
});

/// The family team goal (SPEC FR-KID-15).
final familyGoalProvider = Provider<Reward?>((ref) => [
      for (final r in ref.watch(rewardsProvider).value ?? const <Reward>[])
        if (r.kind == 'family') r,
    ].firstOrNull);

/// The ledger rows about one completion or run, read once for an action
/// (handlers don't rely on providers staying live; AGENTS.md → Style).
Future<List<LedgerEntry>> ledgerFor(DearthDb db, String refTable, String refId) =>
    (db.select(db.ledgerEntries)..where((e) => e.refTable.equals(refTable) & e.refId.equals(refId) & e.deleted.equals(false))).get();

/// The profile id inside an actor string (`profile:<id>`).
String? actorProfileId(String? actor) => actor != null && actor.startsWith('profile:') ? actor.substring(8) : null;
