import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/data/household.dart';
import '../../core/sound.dart';
import '../kids/celebration.dart';
import 'games/registry.dart';
import 'toybox_data.dart';

/// What a game gets from the Toybox (SPEC FR-TOY-04/05/08): its level, a
/// random source, sounds at the Toybox's volume, and the round book-keeping.
/// Games draw and play; the host records, celebrates and keeps time.
class GameController {
  GameController._(this._state);
  final _GameScreenState _state;

  GameInfo get game => _state.widget.game;
  Profile get kid => _state.widget.kid;
  math.Random get random => _state._random;

  /// The level this round is at.
  int get level => _state._level;

  /// Plays [sfx] at the Toybox's volume (capped by the grown-ups).
  void sound(Sfx sfx, {double volume = 1, double rate = 1}) => _state._sound(sfx, volume: volume, rate: rate);

  /// Speaks a voice clip at the Toybox's volume (letters, words, prompts).
  void say(String clip) => _state._say(clip);

  /// A gentle "try again": a soft sound, never a failure screen. The game
  /// shows its own hint.
  void cue() => sound(Sfx.nope, volume: 0.6);

  /// A round ended: records it, celebrates a win, and moves the ladder (the
  /// next round reads [level]). [level] overrides the round's level, for a
  /// mode played at its own (the music toy's echo game). A [calm] round
  /// isn't cheered: confetti would undo a calm-down.
  Future<void> finishRound(String result, {String? emoji, int? level, bool calm = false}) => _state._finishRound(result, emoji: emoji, level: level, calm: calm);
}

/// Builds one game's playfield.
typedef GameBuilder = Widget Function(GameController controller);

/// The white pill at the top of a game that shows what it asks ("look!",
/// "how many?", what the monster eats). Pictures, not words: she can't read
/// yet.
class GamePill extends StatelessWidget {
  const GamePill({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: t.space.lg, vertical: t.space.sm),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: t.radius.pill, boxShadow: t.elevation.e1),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// Opens [game] full screen for [kid].
Future<void> openGame(BuildContext context, WidgetRef ref, GameInfo game, Profile kid) {
  unawaited(markGameSeen(ref, kid.id, game.id));
  return Navigator.of(context, rootNavigator: true).push<void>(PageRouteBuilder<void>(
    transitionDuration: DTheme.of(context).motion(DMotion.standard),
    pageBuilder: (_, _, _) => GameScreen(game: game, kid: kid),
    transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
  ));
}

/// The frame every game runs in: a big home button back to the Toybox,
/// the time left when it's short, and a calm "Toybox is sleeping" ending
/// when the day's time is up (FR-TOY-05). Kid surface: nothing here can
/// change or delete anything (AGENTS.md rule 9).
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key, required this.game, required this.kid});
  final GameInfo game;
  final Profile kid;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  late final GameController _controller = GameController._(this);
  final _random = math.Random();
  /// The kid's rounds of this game, stored and from this visit, oldest first.
  late final List<GameRound> _history = [...ref.read(gameRoundsProvider((widget.kid.id, widget.game.id)))];
  late int _level;

  /// Time played this visit that isn't in a recorded round yet.
  int _unrecordedFrom = 0;
  Timer? _clock;
  bool _warned = false;
  bool _sleeping = false;
  Timer? _byeBye;

  int get _now => ref.read(householdTimeProvider).nowMs();
  int? get _pinned => ref.read(toyboxSettingsProvider).pinFor(widget.kid.id, widget.game.id);

  @override
  void initState() {
    super.initState();
    _level = startLevel(widget.game, _history, pinned: _pinned);
    _unrecordedFrom = _now;
    _clock = Timer.periodic(const Duration(seconds: 5), (_) => _checkTime());
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkTime());
  }

  @override
  void dispose() {
    _clock?.cancel();
    _byeBye?.cancel();
    super.dispose();
  }

  void _sound(Sfx sfx, {double volume = 1, double rate = 1}) {
    final cap = ref.read(toyboxSettingsProvider).volume;
    if (cap <= 0) return;
    unawaited(ref.read(soundProvider).play(sfx, volume: (volume * cap).clamp(0, 1), rate: rate));
  }

  void _say(String clip) {
    final cap = ref.read(toyboxSettingsProvider).volume;
    if (cap <= 0) return;
    unawaited(ref.read(soundProvider).say(clip, volume: cap));
  }

  /// Records the time since the last record as a round. A short visit to a
  /// free-play game is a peek, not a play; a [finished] round always counts.
  Future<void> _record(String result, {int? level, bool finished = false}) async {
    final now = _now;
    final ms = now - _unrecordedFrom;
    _unrecordedFrom = now;
    if (ms < 3000 && result == GameResult.played && !finished) return;
    await recordRound(ref, kidId: widget.kid.id, game: widget.game.id, level: level ?? _level, result: result, durationMs: ms);
  }

  Future<void> _finishRound(String result, {String? emoji, int? level, bool calm = false}) async {
    _history.add((level: level ?? _level, result: result));
    if (result != GameResult.miss && !calm && mounted) {
      celebrate(context, emoji: emoji ?? widget.game.emoji, message: randomPraise(_random));
      _sound(Sfx.cheer);
    }
    await _record(result, level: level, finished: true);
    if (mounted) setState(() => _level = startLevel(widget.game, _history, pinned: _pinned));
    _checkTime();
  }

  /// Warns two minutes before the day's Toybox time runs out, and puts the
  /// Toybox to sleep when it has (FR-TOY-05).
  void _checkTime() {
    if (!mounted || _sleeping) return;
    final s = ref.read(toyboxSettingsProvider);
    final time = ref.read(householdTimeProvider);
    final played = ref.read(playedTodayMsProvider(widget.kid.id)) + (_now - _unrecordedFrom);
    final left = minutesLeft(played, budgetMinutes: s.budgetMinutes);
    final closed = !toyboxOpen(time.minuteOfDay(time.nowMs()), opens: s.opens, closes: s.closes);
    if (left == 0 || closed) {
      unawaited(_record(widget.game.freePlay ? GameResult.played : GameResult.helped));
      setState(() => _sleeping = true);
      _sound(Sfx.sparkle, volume: 0.5);
      _byeBye = Timer(const Duration(seconds: 8), () {
        if (mounted) Navigator.of(context).maybePop();
      });
    } else if (left != null && left <= 2 && !_warned) {
      setState(() => _warned = true);
    }
  }

  Future<void> _leave() async {
    await _record(GameResult.played);
    if (mounted) await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final builder = kGameBuilders[widget.game.id];
    final left = ref.watch(toyboxTimeProvider(widget.kid.id)).minutesLeft;
    return screenTid(
      'screen.game',
      PopScope(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) unawaited(_record(GameResult.played));
        },
        child: Material(
          color: t.colors.surface,
          child: Stack(
            fit: StackFit.expand,
            children: [
              tid('game.${widget.game.id}', builder == null ? Center(child: Text(widget.game.title, style: t.text.kidTitle)) : builder(_controller)),
              Positioned(
                left: t.space.md,
                top: t.space.md,
                child: SafeArea(
                  child: DPressable(
                    id: 'game.home',
                    semanticLabel: 'Back to the Toybox',
                    excludeSemantics: true,
                    onTap: _leave,
                    borderRadius: t.radius.pill,
                    child: Container(
                      width: 72 * t.scale,
                      height: 72 * t.scale,
                      decoration: BoxDecoration(color: t.colors.surfaceRaised.withValues(alpha: 0.92), shape: BoxShape.circle, boxShadow: t.elevation.e1),
                      alignment: Alignment.center,
                      child: DEmoji('🏠', size: 38 * t.scale),
                    ),
                  ),
                ),
              ),
              if (_warned && left != null && left > 0)
                Positioned(
                  right: t.space.md,
                  top: t.space.md,
                  child: SafeArea(
                    child: tid(
                      'game.timeleft',
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.xs),
                        decoration: BoxDecoration(color: t.colors.surfaceRaised.withValues(alpha: 0.92), borderRadius: t.radius.pill),
                        child: Text('⏳ $left more ${left == 1 ? 'minute' : 'minutes'}', style: t.text.title),
                      ),
                    ),
                  ),
                ),
              if (_sleeping) const _Sleeping(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The day's Toybox time is up: a calm goodnight, then back to the launcher.
class _Sleeping extends StatelessWidget {
  const _Sleeping();

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Positioned.fill(
      child: tid(
        'game.sleeping',
        ColoredBox(
          color: const Color(0xFF1B1E3A).withValues(alpha: 0.94),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DEmoji('😴', size: 140 * t.scale),
                SizedBox(height: t.space.lg),
                Text('The Toybox is sleeping', style: t.text.kidTitle.copyWith(color: Colors.white)),
                SizedBox(height: t.space.sm),
                Text('See you next time!', style: t.text.title.copyWith(color: Colors.white70)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
