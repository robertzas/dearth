import 'package:meta/meta.dart';

/// A Toybox game (SPEC §10.8, Appendix B).
@immutable
class GameInfo {
  const GameInfo(this.id, this.title, this.emoji, {required this.minMonths, required this.skills, required this.levels, this.freePlay = false, this.added});

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

  /// When it joined the Toybox ("YYYY-MM-DD"), for games added after the
  /// first sets: until a kid tries it, it's one of the new games at the top
  /// of their launcher (see [launcherOrder]).
  final String? added;
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
  // Numbers and letters (added 2026-10-04).
  GameInfo('dots', 'Dot-to-Dot', '⭐', minMonths: 36, skills: ['Number order', 'Alphabet'], levels: 6),
  GameInfo('biglittle', 'Big & Little Letters', '🔠', minMonths: 42, skills: ['Alphabet', 'Capitals and small letters'], levels: 3),
  GameInfo('hop', 'Frog Hop', '🐸', minMonths: 42, skills: ['Number line', 'One more, one less', 'Adding'], levels: 4),
  GameInfo('spell', 'Word Builder', '🔡', minMonths: 54, skills: ['Phonics', 'Blending', 'Spelling'], levels: 4),
  GameInfo('hear', 'Hear the Sound', '👂', minMonths: 36, skills: ['Phonics', 'Listening'], levels: 4),
  GameInfo('sight', 'Sight Words', '🚏', minMonths: 48, skills: ['Early reading'], levels: 4),
  GameInfo('balance', 'Banana Balance', '🍌', minMonths: 36, skills: ['Comparing quantities', 'More and fewer'], levels: 4),
  // Nothing to win: her own beats. Visits unlock levels.
  GameInfo('sequencer', 'Music Sequencer', '🥁', minMonths: 48, skills: ['Patterns', 'Rhythm', 'Music'], levels: 4, freePlay: true),
  // Nothing to win: the screen can't see her freeze. Visits unlock levels.
  GameInfo('freeze', 'Freeze Dance', '🕺', minMonths: 24, skills: ['Movement', 'Self-control', 'Listening'], levels: 3, freePlay: true),
  // Shown once two people have face photos (Settings → People).
  GameInfo('whosthat', "Who's That?", '👪', minMonths: 24, skills: ['Family', 'Recognizing faces'], levels: 3),
  // Nothing to win: books are read, not solved. Visits unlock longer ones.
  GameInfo('storytime', 'Story Time', '📖', minMonths: 24, skills: ['Listening', 'Language', 'Print awareness'], levels: 3, freePlay: true),
  GameInfo('dressup', 'Weather Dress-Up', '🧥', minMonths: 30, skills: ['Reasoning', 'Weather', 'Getting dressed'], levels: 3),
  GameInfo('hundred', 'Hundred Square', '💯', minMonths: 60, skills: ['Counting past twenty', 'Place value'], levels: 4),
  GameInfo('tally', 'Tallies', '🐇', minMonths: 42, skills: ['Keeping count', 'Counting on', 'Tally marks'], levels: 3),
  GameInfo('zoo', 'Name Zoo', '🦒', minMonths: 42, skills: ['Reading names', 'Letter names', 'Spelling'], levels: 3),
  GameInfo('compare', 'Who Has More?', '🚌', minMonths: 42, skills: ['Comparing numbers', 'More and fewer', 'Number order'], levels: 4),
  // More numbers and letters, built on the games played most (added 2026-10-08).
  GameInfo('cookies', 'Cookie Count', '🍪', minMonths: 36, skills: ['Counting out', 'Making a set', 'Adding and taking away'], levels: 4, added: '2026-10-08'),
  GameInfo('lettermonster', 'Letter Monster', '😋', minMonths: 36, skills: ['Letter names', 'Small letters', 'Letter sounds', 'First sounds'], levels: 4, added: '2026-10-08'),
  GameInfo('busstop', 'Bus Stop', '🚍', minMonths: 42, skills: ['Adding', 'Taking away', 'Counting on'], levels: 4, added: '2026-10-08'),
  GameInfo('wordpop', 'Word Pop', '💬', minMonths: 48, skills: ['Early reading', 'Reading at a glance'], levels: 4, added: '2026-10-08'),
  GameInfo('rocket', 'Rocket Countdown', '🚀', minMonths: 42, skills: ['Counting back', 'Number order', 'Numerals to twenty'], levels: 4, added: '2026-10-08'),
  GameInfo('train', 'Alphabet Train', '🚂', minMonths: 42, skills: ['Alphabet order', 'Letter names', 'Small letters'], levels: 4, added: '2026-10-08'),
  GameInfo('fishing', 'Number Fishing', '🎣', minMonths: 42, skills: ['Reading numerals', 'Biggest number', 'Pairs that make five'], levels: 4, added: '2026-10-08'),
  GameInfo('lettercreature', 'Letter Creatures', '🐲', minMonths: 42, skills: ['First sounds', 'Letter sounds', 'Creativity'], levels: 3, added: '2026-10-08'),
  // Six number games built on her longest-played games (added 2026-10-10; the
  // owner chose minMonths 30 for all six, Ava's age, so she sees every one).
  GameInfo('creaturecount', 'Creature Count', '🐙', minMonths: 30, skills: ['Counting out a set', 'Reading numerals', 'Counting two things'], levels: 4, added: '2026-10-10'),
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

/// The games a kid of [months] sees: every game but those a grown-up
/// switched [off] (owner, 2026-10-07: all games are on by default; ages are
/// starting points, not limits). The ones that suit their age come first,
/// so a toddler finds hers at the top and the bigger kids' games after.
List<GameInfo> gamesFor(int months, {Set<String> off = const {}}) => [
      for (final g in kGames)
        if (g.minMonths <= months && !off.contains(g.id)) g,
      for (final g in kGames)
        if (g.minMonths > months && !off.contains(g.id)) g,
    ];

/// How long a game counts as new after it's [GameInfo.added].
const int kNewGameDays = 30;

/// How many favorites lead a kid's launcher.
const int kFavoriteGames = 6;

/// The launcher's order for a kid (FR-TOY-01, owner request 2026-10-08):
/// games added in the last [kNewGameDays] that they haven't [tried] yet,
/// newest first, so new games are found; then their favorites, the games
/// with the most [recentRounds] (three or more; rounds and play sessions of
/// the last two weeks), most first, so what they love is at hand; then the
/// rest of [games] in its own order (the ones that suit their age first).
/// A new game drops into place once tried.
List<GameInfo> launcherOrder(List<GameInfo> games, {required Set<String> tried, required Map<String, int> recentRounds, required String today}) {
  final todayDate = DateTime.parse(today);
  bool fresh(GameInfo g) => g.added != null && !tried.contains(g.id) && todayDate.difference(DateTime.parse(g.added!)).inDays < kNewGameDays;
  // Ties keep [games]' order (List.sort isn't stable).
  int place(GameInfo a, GameInfo b) => games.indexOf(a).compareTo(games.indexOf(b));
  final news = [for (final g in games) if (fresh(g)) g]..sort((a, b) => b.added!.compareTo(a.added!) != 0 ? b.added!.compareTo(a.added!) : place(a, b));
  final rest = [for (final g in games) if (!fresh(g)) g];
  int rounds(GameInfo g) => recentRounds[g.id] ?? 0;
  final favorites = [for (final g in rest) if (rounds(g) >= 3) g]..sort((a, b) => rounds(b) != rounds(a) ? rounds(b).compareTo(rounds(a)) : place(a, b));
  final top = favorites.take(kFavoriteGames).toSet();
  return [...news, ...top, for (final g in rest) if (!top.contains(g)) g];
}

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
