import 'package:meta/meta.dart';

/// A Toybox game (SPEC §10.8, Appendix B).
@immutable
class GameInfo {
  const GameInfo(this.id, this.title, this.emoji, {required this.minMonths, required this.skills, required this.levels, this.freePlay = false});

  /// Stable id: game_events.game, settings keys, test ids.
  final String id;

  /// For grown-ups; kids pick by picture.
  final String title;
  final String emoji;

  /// The age it starts to suit (Appendix B: starting points, not limits).
  final int minMonths;
  final List<String> skills;

  /// Steps on its difficulty ladder.
  final int levels;

  /// No winning or losing (painting, instruments): sessions are logged as
  /// "played" and the ladder moves by time spent instead.
  final bool freePlay;
}

/// Every game, launcher order: the launch set (FR-TOY-02), then the
/// expansion set (FR-TOY-03).
const List<GameInfo> kGames = [...kLaunchGames, ...kExpansionGames];

/// The launch set (FR-TOY-02).
const List<GameInfo> kLaunchGames = [
  GameInfo('bubbles', 'Bubble Pop', '🎈', minMonths: 24, skills: ['Cause and effect'], levels: 4),
  GameInfo('paint', 'Paint Studio', '🎨', minMonths: 24, skills: ['Creativity', 'Fine motor'], levels: 3, freePlay: true),
  GameInfo('coloring', 'Magic Coloring', '🖍️', minMonths: 24, skills: ['Colors', 'Fine motor'], levels: 5),
  GameInfo('farm', 'Animal Farm', '🐮', minMonths: 24, skills: ['Vocabulary', 'Listening'], levels: 3),
  GameInfo('shapes', 'Shape Sorter', '🔺', minMonths: 24, skills: ['Shapes', 'Spatial'], levels: 5),
  GameInfo('music', 'Xylophone & Drums', '🎵', minMonths: 24, skills: ['Music', 'Rhythm'], levels: 3, freePlay: true),
  GameInfo('jigsaw', 'Jigsaw', '🧩', minMonths: 24, skills: ['Spatial reasoning'], levels: 7),
  GameInfo('memory', 'Memory Match', '🃏', minMonths: 30, skills: ['Working memory'], levels: 6),
  GameInfo('monster', 'Feed the Monster', '👾', minMonths: 30, skills: ['Classification'], levels: 4),
  GameInfo('counting', 'Counting Garden', '🌻', minMonths: 36, skills: ['Number sense'], levels: 4),
];

/// The expansion set (FR-TOY-03), in launcher order after the launch set.
const List<GameInfo> kExpansionGames = [
  GameInfo('patterns', 'Patterns', '🔁', minMonths: 36, skills: ['Logic'], levels: 4),
  GameInfo('oddone', 'Odd One Out', '🔍', minMonths: 36, skills: ['Categorizing'], levels: 4),
  GameInfo('shadows', 'Shadow Match', '👤', minMonths: 30, skills: ['Seeing shapes'], levels: 4),
  GameInfo('sizes', 'Small to Big', '📏', minMonths: 30, skills: ['Ordering'], levels: 4),
  GameInfo('mazes', 'Finger Mazes', '🧭', minMonths: 36, skills: ['Planning', 'Fine motor'], levels: 4),
  GameInfo('stories', 'What Happens Next', '🎞️', minMonths: 42, skills: ['Stories', 'Cause and effect'], levels: 3),
  GameInfo('sudoku', 'Picture Sudoku', '🧮', minMonths: 48, skills: ['Logic'], levels: 6),
  GameInfo('differences', 'Spot the Difference', '🔎', minMonths: 48, skills: ['Attention'], levels: 5),
  GameInfo('letters', 'Letter Sounds', '🔤', minMonths: 36, skills: ['Phonics'], levels: 5),
  GameInfo('rhymes', 'Rhyme Time', '🎩', minMonths: 48, skills: ['Hearing sounds'], levels: 3),
  GameInfo('ispy', 'I Spy', '👀', minMonths: 36, skills: ['Vocabulary', 'Attention'], levels: 5),
  GameInfo('tracing', 'Letter & Name Tracing', '✏️', minMonths: 42, skills: ['Pre-writing'], levels: 5),
  GameInfo('numbers', 'Number Tracing', '🔢', minMonths: 42, skills: ['Numerals'], levels: 3),
  // A calm-down: breaths aren't won, so sessions move it along (3 → 5 breaths).
  GameInfo('breathe', 'Breathing Buddy', '🌬️', minMonths: 36, skills: ['Calming down'], levels: 3, freePlay: true),
  // Nothing to win: more parts and paints unlock with play.
  GameInfo('creature', 'Build-a-Creature', '🦕', minMonths: 30, skills: ['Creativity', 'Language'], levels: 3, freePlay: true),
];

GameInfo? gameById(String id) => kGames.where((g) => g.id == id).firstOrNull;

/// How a round ended (game_events.result). Nothing is ever shown as a loss:
/// a miss only means a gentle "try again" and, after a few, an easier level.
abstract final class GameResult {
  static const String win = 'win';

  /// Won with help (a hint, a highlighted answer): neither up nor down.
  static const String helped = 'helped';
  static const String miss = 'miss';

  /// A free-play session (painting, instruments).
  static const String played = 'played';
}

/// One finished round, oldest first.
typedef GameRound = ({int level, String result});

/// The level to play next (SPEC FR-TOY-04): up after three wins in a row at
/// the current level, down after three misses in a row, otherwise the same.
/// A parent's [pinned] level wins. Always within 1…[maxLevel].
int nextLevel(List<GameRound> rounds, {required int maxLevel, int? pinned}) {
  int clamp(int l) => l < 1 ? 1 : (l > maxLevel ? maxLevel : l);
  if (pinned != null) return clamp(pinned);
  final scored = [for (final r in rounds) if (r.result != GameResult.played) r];
  if (scored.isEmpty) return 1;
  final current = clamp(scored.last.level);
  // The streak at the current level, newest first.
  final atLevel = scored.reversed.takeWhile((r) => r.level == current).take(3).toList();
  if (atLevel.length == 3 && atLevel.every((r) => r.result == GameResult.win)) return clamp(current + 1);
  if (atLevel.length == 3 && atLevel.every((r) => r.result == GameResult.miss)) return clamp(current - 1);
  return current;
}

/// Free-play games (painting, instruments) have no wins: their tools unlock
/// with play instead, a level every three sessions.
int freePlayLevel(List<GameRound> rounds, {required int maxLevel}) {
  final sessions = rounds.where((r) => r.result == GameResult.played).length;
  final level = 1 + sessions ~/ 3;
  return level > maxLevel ? maxLevel : level;
}

/// The level a game starts at: the adaptive ladder, and for free-play games
/// at least what their sessions unlocked. A parent's pin wins.
int startLevel(GameInfo game, List<GameRound> rounds, {int? pinned}) {
  final ladder = nextLevel(rounds, maxLevel: game.levels, pinned: pinned);
  if (pinned != null || !game.freePlay) return ladder;
  final unlocked = freePlayLevel(rounds, maxLevel: game.levels);
  return unlocked > ladder ? unlocked : ladder;
}

/// The age, in whole months, that picks a kid's games: from their birthday,
/// else the middle of their stage (2–3, 3–4, 4–5).
int ageInMonths({required DateTime today, DateTime? birthday, String? stage}) {
  if (birthday != null) {
    var months = (today.year - birthday.year) * 12 + today.month - birthday.month;
    if (today.day < birthday.day) months--;
    return months < 0 ? 0 : months;
  }
  return switch (stage) { 'preschool' => 42, 'prek' => 54, _ => 30 };
}

/// The games a kid of [months] sees: the ones that suit their age, minus
/// those a grown-up switched [off], plus any they opened [early] (ages are
/// starting points, not limits).
List<GameInfo> gamesFor(int months, {Set<String> off = const {}, Set<String> early = const {}}) => [
      for (final g in kGames)
        if ((g.minMonths <= months && !off.contains(g.id)) || early.contains(g.id)) g,
    ];

/// Toybox time today (FR-TOY-05): minutes left of [budgetMinutes] after
/// [playedMs]; null without a budget.
int? minutesLeft(int playedMs, {int? budgetMinutes}) {
  if (budgetMinutes == null || budgetMinutes <= 0) return null;
  final left = budgetMinutes - playedMs / 60000;
  return left <= 0 ? 0 : left.ceil();
}

/// Whether the Toybox is open at [minuteOfDay] given its hours ("HH:MM"
/// open and close; null or equal means always open). A window can run past
/// midnight.
bool toyboxOpen(int minuteOfDay, {String? opens, String? closes}) {
  int? parse(String? s) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s ?? '');
    return m == null ? null : int.parse(m[1]!) * 60 + int.parse(m[2]!);
  }

  final o = parse(opens), c = parse(closes);
  if (o == null || c == null || o == c) return true;
  return o < c ? minuteOfDay >= o && minuteOfDay < c : minuteOfDay >= o || minuteOfDay < c;
}
