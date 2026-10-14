import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'voice_widgets.dart';

/// Bubble colors, with the dot that "calls" them to pre-readers.
const List<(String name, Color color)> kBubbleColors = [
  ('blue', Color(0xFF3D9BF0)),
  ('red', Color(0xFFF2545B)),
  ('yellow', Color(0xFFF7C531)),
  ('green', Color(0xFF4CC46A)),
  ('purple', Color(0xFFA066E8)),
];

/// Bubble Pop & Fireworks (SPEC FR-TOY-02, Appendix B: cause and effect).
/// Bubbles float up; a tap pops one, a finger draws fireworks. Later levels
/// rise faster, then call a color ("pop the blue ones!"): the others just
/// bounce away — never a failure.
class BubbleGame extends ConsumerStatefulWidget {
  const BubbleGame(this.c, {super.key});
  final GameController c;

  @override
  ConsumerState<BubbleGame> createState() => BubbleGameState();
}

class _Bubble {
  _Bubble(this.x, this.y, this.r, this.color, this.phase, this.speed);
  double x, y;
  final double r;
  final int color;
  final double phase;
  double speed;

  /// A bounce on a wrong color: grows, then settles (seconds left).
  double wobble = 0;
}

class _Spark {
  _Spark(this.x, this.y, this.vx, this.vy, this.color, this.size, this.life);
  double x, y, vx, vy, life;
  final Color color;
  final double size;
  final double maxLife = 0.9;
}

@visibleForTesting
class BubbleGameState extends ConsumerState<BubbleGame> with SingleTickerProviderStateMixin {
  late final AmbientTicker _ticker = AmbientTicker(this, _tick, fps: () => DTheme.of(context).policy.ambientFps);
  final _bubbles = <_Bubble>[];
  final _sparks = <_Spark>[];
  final _repaint = ValueNotifier<int>(0);
  Size _size = Size.zero;
  Duration _last = Duration.zero;
  double _clock = 0, _spawnIn = 0, _sparkleSoundAt = -1;
  late BubbleRound _round;
  int _popped = 0, _slips = 0;

  /// The called color's index (color-call levels).
  int? _call;

  math.Random get _rng => widget.c.random;

  /// Bubble centers, for tests.
  @visibleForTesting
  List<(Offset, String)> get debugBubbles => [for (final b in _bubbles) (Offset(b.x, b.y), kBubbleColors[b.color].$1)];

  @visibleForTesting
  String? get debugCall => _call == null ? null : kBubbleColors[_call!].$1;

  @override
  void initState() {
    super.initState();
    _newRound();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _ask?.cancel();
    _repaint.dispose();
    super.dispose();
  }

  Timer? _ask;

  void _sayCall() {
    if (!mounted) return;
    final call = _call;
    widget.c.say(call == null ? VoiceLine.bubblesStart : bubblesCallClip(kBubbleColors[call].$1));
  }

  void _newRound() {
    _round = bubbleRound(widget.c.level);
    _popped = _slips = 0;
    _call = _round.colorCall ? _rng.nextInt(kBubbleColors.length) : null;
    _ask?.cancel();
    _ask = Timer(const Duration(milliseconds: 700), _sayCall);
    if (mounted) setState(() {});
  }

  int get _crowd => (6 + widget.c.level * 2).clamp(6, 12);

  void _spawn({bool anywhere = false}) {
    if (_size.isEmpty) return;
    final r = (_size.shortestSide * (0.07 + _rng.nextDouble() * 0.06)).clamp(36.0, 120.0);
    // Called colors come up often enough to find.
    final color = _call != null && _rng.nextDouble() < 0.45 ? _call! : _rng.nextInt(kBubbleColors.length);
    final y = anywhere ? _size.height * (0.3 + _rng.nextDouble() * 0.7) : _size.height + r;
    _bubbles.add(_Bubble(r + _rng.nextDouble() * (_size.width - 2 * r), y, r, color, _rng.nextDouble() * math.pi * 2, _size.height / _round.riseSeconds * (0.8 + _rng.nextDouble() * 0.4)));
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.08);
    _last = elapsed;
    _clock += dt;
    if (_bubbles.isEmpty && !_size.isEmpty) {
      for (var i = 0; i < _crowd ~/ 2; i++) {
        _spawn(anywhere: true);
      }
    }
    _spawnIn -= dt;
    if (_bubbles.length < _crowd && _spawnIn <= 0) {
      _spawn();
      _spawnIn = _round.riseSeconds / _crowd;
    }
    for (final b in _bubbles) {
      b.y -= b.speed * dt;
      b.x += math.sin(_clock * 1.3 + b.phase) * 18 * dt;
      if (b.wobble > 0) b.wobble = math.max(0, b.wobble - dt);
    }
    _bubbles.removeWhere((b) => b.y + b.r < 0);
    for (final s in _sparks) {
      s
        ..x += s.vx * dt
        ..y += s.vy * dt
        ..vy += 420 * dt
        ..life -= dt;
    }
    _sparks.removeWhere((s) => s.life <= 0);
    _repaint.value++;
  }

  /// The tier's particle budget (SPEC §12.3): fingers sweeping all at once
  /// would otherwise pile up hundreds of sparks.
  bool get _sparksFull => _sparks.length >= DTheme.of(context).policy.maxParticles;

  void _burst(double x, double y, Color color, {int count = 14, double speed = 260}) {
    for (var i = 0; i < count && !_sparksFull; i++) {
      final a = _rng.nextDouble() * math.pi * 2, v = speed * (0.4 + _rng.nextDouble() * 0.8);
      _sparks.add(_Spark(x, y, math.cos(a) * v, math.sin(a) * v - 120, color, 4 + _rng.nextDouble() * 6, 0.5 + _rng.nextDouble() * 0.4));
    }
  }

  /// Where each finger last drew sparkles, by pointer.
  final _fingers = <int, Offset>{};

  // A finger going down pops at once (a tap that waited for the finger to
  // lift felt late, and one that slid a little became a drag and popped
  // nothing). Every finger plays: toddlers use several.
  void _down(PointerDownEvent e) {
    final p = e.localPosition;
    _fingers[e.pointer] = p;
    for (final b in _bubbles.reversed) {
      if ((Offset(b.x, b.y) - p).distance <= b.r * 1.2) {
        _pop(b);
        return;
      }
    }
    _burst(p.dx, p.dy, Colors.white, count: 6, speed: 140);
  }

  void _move(PointerMoveEvent e) {
    final last = _fingers[e.pointer];
    if (last == null || (e.localPosition - last).distance < 6) return;
    _fingers[e.pointer] = e.localPosition;
    // A finger sweeping through a bubble pops it too.
    for (final b in _bubbles.reversed) {
      if ((Offset(b.x, b.y) - e.localPosition).distance <= b.r) {
        _pop(b);
        break;
      }
    }
    _trail(e.localPosition);
  }

  void _up(PointerEvent e) => _fingers.remove(e.pointer);

  void _pop(_Bubble b) {
    final c = widget.c;
    if (_call != null && b.color != _call) {
      if (b.wobble > 0) return; // already bouncing away
      // The wrong color bounces away: a boing, a wobble, a little lift.
      b
        ..wobble = 0.5
        ..speed *= 1.6;
      c.sound(Sfx.boing, volume: 0.7);
      _slips++;
      return;
    }
    _bubbles.remove(b);
    _burst(b.x, b.y, kBubbleColors[b.color].$2);
    // Small bubbles pop higher.
    c.sound(Sfx.pop, rate: (1.45 - b.r / 120 * 0.7).clamp(0.75, 1.5));
    // Pops counted out loud: one, two, three…
    widget.c.say(numberClip(_popped + 1));
    if (++_popped >= _round.targets) {
      final result = _call == null ? GameResult.win : resultFor(_slips, allowed: 2);
      c.finishRound(result, emoji: '🎈').then((_) => _newRound());
    } else {
      setState(() {});
    }
  }

  void _trail(Offset p) {
    for (var i = 0; i < 3 && !_sparksFull; i++) {
      final color = kBubbleColors[_rng.nextInt(kBubbleColors.length)].$2;
      _sparks.add(_Spark(p.dx, p.dy, (_rng.nextDouble() - 0.5) * 160, -60 - _rng.nextDouble() * 120, color, 3 + _rng.nextDouble() * 5, 0.6 + _rng.nextDouble() * 0.4));
    }
    if (_clock - _sparkleSoundAt > 0.35) {
      _sparkleSoundAt = _clock;
      widget.c.sound(Sfx.sparkle, volume: 0.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final call = _call;
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF8FD3FE), Color(0xFFE3F5FF)])),
        ),
        LayoutBuilder(builder: (context, box) {
          _size = box.biggest;
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _up,
            child: RepaintBoundary(child: CustomPaint(painter: _BubblePainter(this, _repaint), size: Size.infinite)),
          );
        }),
        // A lasting count for screen readers and tests: the bubbles
        // themselves are paint.
        Positioned(left: 0, bottom: 0, width: 1, height: 1, child: tid('bubbles.popped', Semantics(label: 'Popped $_popped', excludeSemantics: true, child: const SizedBox.expand()))),
        if (call != null)
          TopPrompt(
            child: PromptPill(
              id: 'bubbles.call',
              label: 'Pop the ${kBubbleColors[call].$1} ones',
              onSayAgain: _sayCall,
              children: [
                DEmoji('👆', size: 40 * t.scale),
                SizedBox(width: t.space.sm),
                Container(width: 44 * t.scale, height: 44 * t.scale, decoration: BoxDecoration(color: kBubbleColors[call].$2, shape: BoxShape.circle)),
                SizedBox(width: t.space.sm),
                Text('${_round.targets - _popped}', style: t.text.kidTitle),
              ],
            ),
          ),
      ],
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter(this.s, Listenable repaint) : super(repaint: repaint);
  final BubbleGameState s;

  /// One glossy fill per color for a bubble of radius 1 at the origin,
  /// scaled into place: a gradient shader per bubble per frame was a dozen
  /// allocations a frame on the frame's slow CPU.
  static final List<Shader> _fills = [
    for (final (_, color) in kBubbleColors)
      RadialGradient(
        center: const Alignment(-0.35, -0.35),
        colors: [Colors.white.withValues(alpha: 0.75), color.withValues(alpha: 0.55), color.withValues(alpha: 0.85)],
        stops: const [0, 0.55, 1],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1)),
  ];
  static final Rect _shine = Rect.fromCenter(center: const Offset(-0.38, -0.42), width: 0.42, height: 0.26);

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint();
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.85);
    final shine = Paint()..color = Colors.white.withValues(alpha: 0.8);
    for (final b in s._bubbles) {
      final grow = b.wobble > 0 ? 1 + 0.18 * math.sin(b.wobble / 0.5 * math.pi * 3) * (b.wobble / 0.5) : 1.0;
      final r = b.r * grow;
      fill.shader = _fills[b.color];
      rim.strokeWidth = 2.5 / r;
      canvas
        ..save()
        ..translate(b.x, b.y)
        ..scale(r)
        ..drawCircle(Offset.zero, 1, fill)
        ..drawCircle(Offset.zero, 1, rim)
        ..drawOval(_shine, shine)
        ..restore();
    }
    final spark = Paint();
    for (final p in s._sparks) {
      spark.color = p.color.withValues(alpha: (p.life / p.maxLife).clamp(0, 1));
      canvas.drawCircle(Offset(p.x, p.y), p.size, spark);
    }
  }

  @override
  bool shouldRepaint(_BubblePainter old) => false;
}
