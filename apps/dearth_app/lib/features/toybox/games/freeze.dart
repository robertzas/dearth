import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'creature.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Freeze Dance (SPEC FR-TOY-03, Appendix B: movement, self-regulation). A
/// creature from Build-a-Creature dances to a cheerful loop the app plays
/// itself (a xylophone tune over kick, snare and hat). The music stops, the
/// voice says "Freeze!" and the buddy freezes mid-move inside a block of
/// ice; "Dance!" and the music starts again. At the top level each dance is
/// an animal's: the buddy becomes a frog and hops ("Dance like a frog!"),
/// a snake and wiggles, an elephant and stomps. After the song, "Great
/// dancing!" The screen can't see her, so nothing is scored: free play.
/// Tapping the buddy makes it twirl.
class FreezeGame extends StatefulWidget {
  const FreezeGame(this.c, {super.key});
  final GameController c;

  @override
  State<FreezeGame> createState() => FreezeGameState();
}

enum _Phase { ready, dancing, frozen, done }

@visibleForTesting
class FreezeGameState extends State<FreezeGame> with SingleTickerProviderStateMixin {
  late List<FreezeTurn> _song;
  late Creature _creature;
  int _turn = 0, _step = 0, _frames = 0, _twirls = 0, _songs = 0;
  _Phase _phase = _Phase.ready;
  Duration _danced = Duration.zero, _from = Duration.zero;
  late final Ticker _ticker = createTicker(_tick);
  final _dance = ValueNotifier<double?>(0);
  final _timers = <Timer>[];
  Timer? _beat;

  @visibleForTesting
  List<FreezeTurn> get debugSong => _song;

  @visibleForTesting
  bool get debugDancing => _phase == _Phase.dancing;

  @visibleForTesting
  bool get debugFrozen => _phase == _Phase.frozen;

  @override
  void initState() {
    super.initState();
    _newSong();
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _beat?.cancel();
    _ticker.dispose();
    _dance.dispose();
    super.dispose();
  }

  void _after(Duration d, VoidCallback f) => _timers.add(Timer(d, () {
        if (mounted) f();
      }));

  void _newSong() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    final rng = widget.c.random;
    _song = freezeSong(widget.c.level, rng);
    _creature = randomCreature(3, rng);
    _turn = 0;
    _songs++;
    _phase = _Phase.ready;
    _after(const Duration(milliseconds: 600), () {
      widget.c.say(VoiceLine.freezeStart);
      _after(afterVoice(VoiceLine.freezeStart), _dancePart);
    });
    if (mounted) setState(() {});
  }

  /// The music starts (with the animal to dance like, at the top level).
  void _dancePart() {
    final turn = _song[_turn];
    final animal = turn.animal;
    if (animal != null) {
      widget.c.say(freezeAnimalClip(animal));
    } else if (_turn > 0) {
      widget.c.say(VoiceLine.freezeGo);
    }
    setState(() => _phase = _Phase.dancing);
    _step = 0;
    _beat?.cancel();
    // Eighth notes: a bar loops every 3.2 s.
    _beat = Timer.periodic(const Duration(milliseconds: 200), (_) => _playStep());
    _from = _danced;
    _ticker.start();
    _after(Duration(milliseconds: turn.danceMs), _freeze);
  }

  void _playStep() {
    if (!mounted) return;
    final s = _step++ % kFreezeTune.length;
    final note = kFreezeTune[s];
    if (note != null) widget.c.sound(Sfx.xylophone, volume: 0.5, rate: math.pow(2, (note - kXylophoneBaseMidi) / 12).toDouble());
    if (s % 8 == 0) widget.c.sound(Sfx.kick, volume: 0.5);
    if (s % 8 == 4) widget.c.sound(Sfx.snare, volume: 0.35);
    if (s.isOdd) widget.c.sound(Sfx.hat, volume: 0.22);
  }

  /// The music stops dead: "Freeze!", and the buddy holds its pose in ice.
  void _freeze() {
    _beat?.cancel();
    _ticker.stop();
    widget.c.say(VoiceLine.freezeStop);
    setState(() => _phase = _Phase.frozen);
    final turn = _song[_turn];
    _after(Duration(milliseconds: turn.freezeMs), () {
      if (++_turn < _song.length) {
        _dancePart();
      } else {
        _end();
      }
    });
  }

  void _end() {
    widget.c.say(VoiceLine.freezeDone);
    setState(() {
      _phase = _Phase.done;
      _twirls++;
    });
    unawaited(widget.c.finishRound(GameResult.win, emoji: '🕺'));
    _after(afterVoice(VoiceLine.freezeDone, atLeast: const Duration(seconds: 4)), _newSong);
  }

  void _tick(Duration elapsed) {
    // Ambient motion: 30 fps is plenty on the slowest displays.
    if (DTheme.of(context).policy.ambientFps < 60 && (_frames++).isOdd) return;
    _danced = _from + elapsed;
    _dance.value = _danced.inMicroseconds / 1e6;
  }

  void _tapBuddy() {
    if (_phase == _Phase.frozen) {
      // Frozen means frozen: a little shiver, nothing more.
      setState(() => _twirls++);
      return;
    }
    widget.c.sound(Sfx.sparkle, volume: 0.35);
    setState(() => _twirls++);
  }

  String get _stateLabel => switch (_phase) {
        _Phase.ready => 'Ready to dance',
        _Phase.dancing => _song[_turn].animal == null ? 'Dancing' : 'Dancing like a ${_song[_turn].animal!.name}',
        _Phase.frozen => 'Frozen',
        _Phase.done => 'Great dancing!',
      };

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final frozen = _phase == _Phase.frozen;
    final animal = _phase == _Phase.dancing || frozen ? _song[_turn].animal : null;
    return Backdrop(
      top: frozen ? const Color(0xFFDDF0FF) : const Color(0xFFFFE9F3),
      bottom: frozen ? const Color(0xFFEFF8FF) : const Color(0xFFE9E4FF),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final stage = math.min(box.maxWidth, box.maxHeight) * 0.86;
              return Center(
                child: SizedBox.square(
                  dimension: stage,
                  child: DPressable(
                    id: 'freeze.buddy',
                    semanticLabel: _stateLabel,
                    excludeSemantics: true,
                    onTap: _tapBuddy,
                    pressFeedback: false,
                    borderRadius: BorderRadius.circular(stage * 0.1),
                    child: Stack(
                      key: ValueKey(_songs),
                      fit: StackFit.expand,
                      children: [
                        Wiggle(
                          count: _twirls,
                          child: RepaintBoundary(
                            child: animal == null
                                ? CustomPaint(painter: CreaturePainter(_creature, dance: _dance))
                                : _AnimalDance(animal: animal, time: _dance, size: stage),
                          ),
                        ),
                        // The ice block, over the buddy while it's frozen.
                        IgnorePointer(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(end: frozen ? 1 : 0),
                            duration: const Duration(milliseconds: 220),
                            builder: (context, k, _) => k == 0
                                ? const SizedBox.shrink()
                                : Transform.scale(scale: 0.6 + 0.4 * Curves.easeOutBack.transform(k), child: RepaintBoundary(child: CustomPaint(painter: _IcePainter(k)))),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
          TopPrompt(
            child: tid(
              'freeze.state',
              Semantics(
                label: _stateLabel,
                excludeSemantics: true,
                child: GamePill(children: [
                  DEmoji(frozen ? '🧊' : (animal?.emoji ?? (_phase == _Phase.done ? '🎉' : '🎶')), size: 40 * t.scale),
                  SizedBox(width: t.space.xs),
                  DEmoji(frozen ? '✋' : '🕺', size: 40 * t.scale),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The buddy as an animal at the top level, moving the animal's way: the
/// frog hops, the snake wiggles, the elephant stomps, the bird flaps, the
/// fish swims. Frozen, it holds the pose (the time stops).
class _AnimalDance extends StatelessWidget {
  const _AnimalDance({required this.animal, required this.time, required this.size});
  final FreezeAnimal animal;
  final ValueNotifier<double?> time;
  final double size;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double?>(
        valueListenable: time,
        builder: (context, value, child) {
          final t = value ?? 0;
          final s = size;
          final (dx, dy, turn, squash) = switch (animal) {
            FreezeAnimal.frog => (0.0, -(math.sin(t * math.pi * 2)).abs() * s * 0.22, 0.0, 1.0),
            FreezeAnimal.bunny => (math.sin(t * math.pi) * s * 0.08, -(math.sin(t * math.pi * 3)).abs() * s * 0.16, 0.0, 1.0),
            FreezeAnimal.snake => (math.sin(t * math.pi * 2) * s * 0.14, 0.0, math.sin(t * math.pi * 2) * 0.25, 1.0),
            FreezeAnimal.elephant => (math.sin(t * math.pi * 0.75) * s * 0.06, 0.0, math.sin(t * math.pi * 1.5) * 0.06, 1 - (math.sin(t * math.pi * 1.5)).abs() * 0.12),
            FreezeAnimal.bird => (0.0, math.sin(t * math.pi * 2) * s * 0.06, math.sin(t * math.pi * 4) * 0.22, 1.0),
            FreezeAnimal.fish => (math.sin(t * math.pi * 1.2) * s * 0.18, math.sin(t * math.pi * 2.4) * s * 0.05, math.cos(t * math.pi * 1.2) * 0.2, 1.0),
          };
          return Transform.translate(
            offset: Offset(dx, dy),
            child: Transform.rotate(angle: turn, child: Transform.scale(scaleX: 1 + (1 - squash) * 0.6, scaleY: squash, alignment: Alignment.bottomCenter, child: child)),
          );
        },
        child: Center(child: DEmoji(animal.emoji, size: size * 0.62)),
      );
}

/// A block of ice: pale blue glass with bright edges and a few snowflakes,
/// faded in by [k] (0–1). Alpha in the paints, no layers: cheap on the frame.
class _IcePainter extends CustomPainter {
  const _IcePainter(this.k);
  final double k;

  Color _a(Color c) => c.withValues(alpha: c.a * k.clamp(0, 1));

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final block = RRect.fromRectAndRadius(Rect.fromCenter(center: size.center(Offset.zero), width: s * 0.86, height: s * 0.9), Radius.circular(s * 0.08));
    canvas
      ..drawRRect(block, Paint()..color = _a(const Color(0x6699D6FF)))
      ..drawRRect(
        block,
        Paint()
          ..color = _a(const Color(0xCCFFFFFF))
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.018,
      );
    // Glints on the glass.
    final glint = Paint()
      ..color = _a(const Color(0xB3FFFFFF))
      ..strokeWidth = s * 0.02
      ..strokeCap = StrokeCap.round;
    final o = block.outerRect.topLeft;
    canvas
      ..drawLine(o + Offset(s * 0.1, s * 0.16), o + Offset(s * 0.22, s * 0.06), glint)
      ..drawLine(o + Offset(s * 0.1, s * 0.3), o + Offset(s * 0.34, s * 0.06), glint);
    // Snowflakes: three crossed lines each.
    final flake = Paint()
      ..color = _a(Colors.white)
      ..strokeWidth = s * 0.012
      ..strokeCap = StrokeCap.round;
    for (final (x, y, r) in const [(0.86, 0.12, 0.05), (0.1, 0.82, 0.04), (0.92, 0.7, 0.035), (0.2, 0.08, 0.03)]) {
      final c = Offset(size.width * x, size.height * y);
      for (var k = 0; k < 3; k++) {
        final a = k * math.pi / 3;
        final d = Offset(math.cos(a), math.sin(a)) * s * r;
        canvas.drawLine(c - d, c + d, flake);
      }
    }
  }

  @override
  bool shouldRepaint(_IcePainter old) => old.k != k;
}
