import 'dart:convert';

import 'package:dearth_core/dearth_core.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/household.dart';
import '../../core/providers.dart';
import '../../shared/face_photo.dart';
import '../kids/kids_data.dart';

/// The grown-ups' Toybox rules (SPEC FR-TOY-05), one household setting.
@immutable
class ToyboxSettings {
  const ToyboxSettings({this.off = const {}, this.budgetMinutes, this.opens, this.closes, this.volume = 1, this.pins = const {}});

  factory ToyboxSettings.from(Map<String, Object?> v) => ToyboxSettings(
        off: {for (final g in v['off'] is List ? v['off']! as List : const []) '$g'},
        budgetMinutes: (v['budget'] as num?)?.toInt(),
        opens: v['opens'] as String?,
        closes: v['closes'] as String?,
        volume: ((v['volume'] as num?)?.toDouble() ?? 1).clamp(0, 1).toDouble(),
        pins: {
          if (v['pins'] is Map)
            for (final e in (v['pins']! as Map).entries)
              if (e.value is num) '${e.key}': (e.value as num).toInt(),
        },
      );

  /// Games a grown-up switched off, by `kidId.gameId`.
  final Set<String> off;

  Set<String> _games(Set<String> keys, String kidId) => {
        for (final k in keys)
          if (k.startsWith('$kidId.')) k.substring(kidId.length + 1),
      };

  Set<String> offFor(String kidId) => _games(off, kidId);

  /// Shows or hides [game] for a kid (every game is on until a grown-up
  /// switches it off).
  ToyboxSettings withGame(String kidId, String game, {required bool on}) {
    final key = '$kidId.$game';
    return copyWith(off: {...off}..remove(key)..addAll([if (!on) key]));
  }

  /// Minutes a day per kid; null: no limit.
  final int? budgetMinutes;

  /// Opening hours ("HH:MM"); null: always open.
  final String? opens;
  final String? closes;

  /// The loudest the Toybox plays, 0…1.
  final double volume;

  /// Levels a grown-up pinned, by `kidId.gameId`.
  final Map<String, int> pins;

  int? pinFor(String kidId, String game) => pins['$kidId.$game'];

  Map<String, Object?> toJson() => {
        'off': (off.toList()..sort()),
        'budget': ?budgetMinutes,
        'opens': ?opens,
        'closes': ?closes,
        'volume': volume,
        'pins': pins,
      };

  ToyboxSettings copyWith({Set<String>? off, int? Function()? budgetMinutes, (String?, String?)? hours, double? volume, Map<String, int>? pins}) => ToyboxSettings(
        off: off ?? this.off,
        budgetMinutes: budgetMinutes == null ? this.budgetMinutes : budgetMinutes(),
        opens: hours == null ? opens : hours.$1,
        closes: hours == null ? closes : hours.$2,
        volume: volume ?? this.volume,
        pins: pins ?? this.pins,
      );
}

final toyboxSettingsProvider = Provider<ToyboxSettings>((ref) => ToyboxSettings.from(ref.watch(settingMapProvider(SettingKeys.toybox))));

Future<void> saveToyboxSettings(WidgetRef ref, ToyboxSettings s) {
  final w = ref.read(writerProvider);
  return w.commit([settingOp(w, SettingKeys.toybox, s.toJson())]);
}

// ─────────────────────────────── Who's playing ──────────────────────────────

class ToyboxKidController extends Notifier<String?> {
  @override
  String? build() => null;

  void choose(String kidId) => state = kidId;
}

final _toyboxKidChoiceProvider = NotifierProvider<ToyboxKidController, String?>(ToyboxKidController.new);

/// The kid playing: the one picked in the Toybox, else the Kids screen's
/// tab, else the first kid.
final toyboxKidProvider = Provider<Profile?>((ref) {
  final kids = ref.watch(kidsProvider);
  final chosen = ref.watch(_toyboxKidChoiceProvider) ?? ref.watch(kidsTabProvider);
  return kids.where((k) => k.id == chosen).firstOrNull ?? kids.firstOrNull;
});

void chooseToyboxKid(WidgetRef ref, String kidId) => ref.read(_toyboxKidChoiceProvider.notifier).choose(kidId);

/// The kid's age in months, which picks their games (FR-TOY-01).
final kidMonthsProvider = Provider.family<int, String>((ref, kidId) {
  final kid = ref.watch(profileMapProvider)[kidId];
  final today = ref.watch(todayProvider);
  final born = LocalDate.tryParse(kid?.birthday);
  return ageInMonths(today: today.utcMidnight, birthday: born?.utcMidnight, stage: kid?.kidStage);
});

/// The games this kid sees, launcher order (FR-TOY-01): new games they
/// haven't played a round of yet, then their favorites of the last two
/// weeks, then the rest, the ones that suit their age first.
final kidGamesProvider = Provider.family<List<GameInfo>, String>((ref, kidId) {
  final s = ref.watch(toyboxSettingsProvider);
  var games = gamesFor(ref.watch(kidMonthsProvider(kidId)), off: s.offFor(kidId));
  // Who's That? needs faces: two people with photos, one the voice can ask for.
  if (!whoPlayable(whoFaces(ref.watch(familyProvider), kidId))) games = [for (final g in games) if (g.id != 'whosthat') g];
  final today = ref.watch(todayProvider);
  // Played on any display (rounds sync), not just opened here: a game she
  // peeked into stays up top until she's played it.
  final events = ref.watch(_kidRoundsProvider(kidId)).value ?? const <GameEvent>[];
  final since = ref.watch(householdTimeProvider).startOfDayMs(today.addDays(-13));
  final recent = <String, int>{};
  for (final e in events) {
    if (e.atMs >= since) recent[e.game] = (recent[e.game] ?? 0) + 1;
  }
  return launcherOrder(games, tried: {for (final e in events) e.game}, recentRounds: recent, today: today.iso);
});

/// The household's faces for Who's That? (SPEC FR-TOY-03): everyone with a
/// face photo (or, with [photosOnly] off, everyone), and the clip that asks
/// for them (the child playing is "you").
List<WhoFace> whoFaces(List<Profile> people, String kidId, {bool photosOnly = true}) => [
      for (final p in people)
        if (!photosOnly || FaceCrop.parse(p.avatarBlob) != null)
          WhoFace(p.id, whoAskFor(name: p.name, nickname: p.nickname, emoji: p.emoji, you: p.id == kidId, pet: p.role == ProfileRole.pet)),
    ];

// ─────────────────────────────── Rounds & levels ────────────────────────────

/// A kid's recent rounds, newest first (enough for every game's ladder and
/// today's time).
final _kidRoundsProvider = StreamProvider.family<List<GameEvent>, String>((ref, kidId) {
  final db = ref.watch(dbProvider);
  return (db.select(db.gameEvents)
        ..where((e) => e.profileId.equals(kidId) & e.deleted.equals(false))
        ..orderBy([(e) => OrderingTerm.desc(e.atMs)])
        ..limit(500))
      .watch();
});

/// A kid's rounds of a game, oldest first.
final gameRoundsProvider = Provider.family<List<GameRound>, (String, String)>((ref, key) {
  final (kidId, gameId) = key;
  final events = ref.watch(_kidRoundsProvider(kidId)).value ?? const <GameEvent>[];
  return [for (final e in events.reversed) if (e.game == gameId) (level: e.level, result: e.result)];
});

/// The level [game] starts at for a kid (FR-TOY-04).
final gameLevelProvider = Provider.family<int, (String, String)>((ref, key) {
  final game = gameById(key.$2);
  if (game == null) return 1;
  return startLevel(game, ref.watch(gameRoundsProvider(key)), pinned: ref.watch(toyboxSettingsProvider).pinFor(key.$1, key.$2));
});

/// Milliseconds a kid has played today.
final playedTodayMsProvider = Provider.family<int, String>((ref, kidId) {
  final since = ref.watch(householdTimeProvider).startOfDayMs(ref.watch(todayProvider));
  final events = ref.watch(_kidRoundsProvider(kidId)).value ?? const <GameEvent>[];
  return events.where((e) => e.atMs >= since).fold(0, (sum, e) => sum + e.durationMs);
});

/// Whether the Toybox is open for a kid now, and the minutes left today
/// (null: no budget).
@immutable
class ToyboxTime {
  const ToyboxTime({required this.open, this.minutesLeft, this.why});
  final bool open;
  final int? minutesLeft;

  /// Why it's closed: "budget" or "hours".
  final String? why;
}

final toyboxTimeProvider = Provider.family<ToyboxTime, String>((ref, kidId) {
  final s = ref.watch(toyboxSettingsProvider);
  ref.watch(nowMinuteMsProvider);
  final time = ref.watch(householdTimeProvider);
  final left = minutesLeft(ref.watch(playedTodayMsProvider(kidId)), budgetMinutes: s.budgetMinutes);
  if (!toyboxOpen(time.minuteOfDay(time.nowMs()), opens: s.opens, closes: s.closes)) return ToyboxTime(open: false, minutesLeft: left, why: 'hours');
  if (left == 0) return const ToyboxTime(open: false, minutesLeft: 0, why: 'budget');
  return ToyboxTime(open: true, minutesLeft: left);
});

/// Writes one finished round (append-only, AGENTS.md rule 4).
Future<void> recordRound(WidgetRef ref, {required String kidId, required String game, required int level, required String result, required int durationMs}) {
  final w = ref.read(writerProvider);
  return w.insertOnly('game_events', newId(), {
    'profile_id': kidId,
    'game': game,
    'level': level,
    'result': result,
    'duration_ms': durationMs,
    'at_ms': ref.read(householdTimeProvider).nowMs(),
  });
}

// ─────────────────────────────── "New!" sparkle ─────────────────────────────

/// Games a kid has opened on this display (device-local).
final seenGamesProvider = StreamProvider.family<Set<String>, String>((ref, kidId) {
  final db = ref.watch(dbProvider);
  return db.kvWatch('toybox.seen.$kidId').map((v) => decodeStringList(v).toSet());
});

Future<void> markGameSeen(WidgetRef ref, String kidId, String game) async {
  final db = ref.read(dbProvider);
  final seen = decodeStringList(await db.kvGet('toybox.seen.$kidId')).toSet()..add(game);
  await db.kvSet('toybox.seen.$kidId', jsonEncode(seen.toList()..sort()));
}
