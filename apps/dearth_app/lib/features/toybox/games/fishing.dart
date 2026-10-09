import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Number Fishing (SPEC FR-TOY-03, Appendix B: reading numerals, the
/// biggest number, pairs that make five). Fish with numbers on their sides
/// swim back and forth across a pond, a lane each. The voice calls one
/// ("Find the number seven."), later "Catch the biggest number!", then
/// "Catch two fish that make five!". She taps the fish and it leaps out of
/// the water in an arc into the bucket on the bank, saying its number; a
/// pair that makes five is said together ("Two and three make five!"). A
/// wrong fish wiggles and says its number; after two slips, or a long
/// pause, the right one gets a golden ring.
class FishingGame extends StatefulWidget {
  const FishingGame(this.c, {super.key});
  final GameController c;

  @override
  State<FishingGame> createState() => FishingGameState();
}

const List<Color> _kFishPaints = [Color(0xFFFF8A3D), Color(0xFF2EC4B6), Color(0xFFF06292), Color(0xFFFFC93C), Color(0xFF8E7CF0)];

@visibleForTesting
class FishingGameState extends State<FishingGame> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _time = ValueNotifier<double>(0);
  FishRound? _round;
  List<double> _phases = const [];
  final _caught = <int>[];
  final _leaping = <int>{};
  final _wiggles = <int, int>{};
  int _slips = 0, _deal = 0, _bucketHops = 0, _frames = 0;
  bool _done = false, _glow = false, _slow = false;
  Duration _last = Duration.zero;
  final _timers = <Timer>[];
  Timer? _idle;

  @visibleForTesting
  FishRound get debugRound => _round!;

  @visibleForTesting
  List<int> get debugCaught => List.unmodifiable(_caught);

  @visibleForTesting
  bool get debugHint => _glow;

  @override
  void initState() {
    super.initState();
    _newRound();
    _ticker.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ambient motion at 30 fps on the slowest displays (SPEC §12.3).
    _slow = DTheme.of(context).policy.ambientFps < 60;
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _idle?.cancel();
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  void _after(Duration d, VoidCallback f) => _timers.add(Timer(d, () {
        if (mounted) f();
      }));

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    if (_slow && (_frames++).isOdd) return;
    _time.value += dt;
  }

  void _newRound() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    final r = _round = fishRound(widget.c.level, widget.c.random, last: _round);
    _phases = [for (var i = 0; i < r.fish.length; i++) widget.c.random.nextDouble() * math.pi * 2];
    _caught.clear();
    _leaping.clear();
    _wiggles.clear();
    _slips = 0;
    _done = _glow = false;
    _deal++;
    _after(const Duration(milliseconds: 700), _sayAsk);
    _waitIdle();
    if (mounted) setState(() {});
  }

  void _sayAsk() => widget.c.say(fishAskClip(_round!));

  /// A long pause asks again and rings the fish she's after (not a slip).
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 11), () {
      if (!mounted || _done) return;
      _sayAsk();
      setState(() => _glow = true);
    });
  }

  /// Seconds for a fish to swim across and back: slower for the youngest.
  double get _period => switch (widget.c.level) { <= 1 => 16, 2 => 14, _ => 12 };

  void _tapFish(int n) {
    final r = _round!;
    if (_done || _caught.contains(n)) return;
    _waitIdle();
    final wanted = r.ask == FishAsk.makeFive && _caught.isNotEmpty ? {5 - _caught.first} : r.catches;
    if (!wanted.contains(n)) {
      _slips++;
      widget.c.cue();
      widget.c.say(numberClip(n));
      setState(() {
        _wiggles[n] = (_wiggles[n] ?? 0) + 1;
        if (_slips >= 2) _glow = true;
      });
      return;
    }
    widget.c.sound(Sfx.pop, volume: 0.6);
    widget.c.say(numberClip(n));
    setState(() {
      _caught.add(n);
      _leaping.add(n);
    });
    // Into the bucket with a splash.
    _after(const Duration(milliseconds: 750), () {
      widget.c.sound(Sfx.sparkle, volume: 0.4);
      setState(() {
        _leaping.remove(n);
        _bucketHops++;
      });
    });
    final finished = r.ask == FishAsk.makeFive ? _caught.length == 2 : true;
    if (!finished) return;
    _idle?.cancel();
    setState(() => _done = true);
    unawaited(widget.c.finishRound(fishResult(r, _slips), emoji: '🐟'));
    var next = afterVoice(numberClip(n), atLeast: const Duration(milliseconds: 2600));
    if (r.ask == FishAsk.makeFive) {
      final pair = fishPairClip(_caught[0], _caught[1]);
      _after(afterVoice(numberClip(n), atLeast: const Duration(milliseconds: 900)), () => widget.c.say(pair));
      next = afterVoice(numberClip(n), atLeast: const Duration(milliseconds: 900)) + afterVoice(pair, atLeast: const Duration(milliseconds: 2000));
    }
    _after(next, _newRound);
  }

  String _askLabel() {
    final r = _round!;
    if (_done) {
      return switch (r.ask) {
        FishAsk.find => 'Caught ${r.target}',
        FishAsk.biggest => 'Caught ${r.catches.single}, the biggest',
        FishAsk.makeFive => '${_caught[0]} and ${_caught[1]} make five',
      };
    }
    return switch (r.ask) {
      FishAsk.find => 'Find the number ${r.target}',
      FishAsk.biggest => 'Catch the biggest number',
      FishAsk.makeFive => _caught.isEmpty ? 'Catch two fish that make five' : 'Catch two fish that make five: ${_caught.first} and?',
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFFDDF3C9)),
        PlayArea(
          top: 130,
          child: LayoutBuilder(builder: (context, box) {
            final l = _Layout.of(box.biggest, r.fish.length);
            return Stack(
              key: ValueKey(_deal),
              clipBehavior: Clip.none,
              children: [
                // The water, from just above the top lane out past the play
                // area's padding to the screen's edges.
                Positioned(left: -400, right: -400, top: l.top - l.laneHeight * 0.12, bottom: -400, child: const RepaintBoundary(child: CustomPaint(painter: _PondPainter()))),
                Positioned.fromRect(
                  rect: l.bucket,
                  child: tid(
                    'fishing.bucket',
                    Semantics(
                      label: 'Bucket: ${_caught.length - _leaping.length} fish',
                      excludeSemantics: true,
                      child: Hop(count: _bucketHops, child: RepaintBoundary(child: CustomPaint(painter: _BucketPainter(_caught.length - _leaping.length)))),
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _time,
                  builder: (context, _) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (var i = 0; i < r.fish.length; i++)
                        if (!_caught.contains(r.fish[i]) || _leaping.contains(r.fish[i])) _fish(i, l),
                    ],
                  ),
                ),
              ],
            );
          }),
        ),
        TopPrompt(child: PromptPill(id: 'fishing.ask', label: _askLabel(), onSayAgain: _sayAsk, children: [DEmoji('🎣', size: 40 * t.scale)])),
      ],
    );
  }

  Widget _fish(int i, _Layout l) {
    final r = _round!;
    final n = r.fish[i];
    final a = 2 * math.pi * _time.value / _period + _phases[i];
    final x = l.swimLeft + l.swimRange * (0.5 + 0.5 * math.sin(a));
    final left = math.cos(a) < 0;
    final at = Offset(x, l.lane(i));
    final glow = _glow && !_done && (r.ask == FishAsk.makeFive && _caught.isNotEmpty ? n == 5 - _caught.first : r.catches.contains(n));
    final body = _FishView(number: n, color: _kFishPaints[i % _kFishPaints.length], facingLeft: left, glow: glow, size: l.fish);
    if (_leaping.contains(n)) {
      // Out of the water in an arc, into the bucket.
      return TweenAnimationBuilder<double>(
        key: ValueKey('leap$n'),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOut,
        builder: (context, k, child) {
          final to = l.bucket.center - Offset(l.fish.width / 2, l.fish.height / 2);
          final p = Offset.lerp(at, to, k)! - Offset(0, math.sin(k * math.pi) * l.fish.height * 2.2);
          final s = 1 - 0.5 * k;
          return Positioned(left: p.dx, top: p.dy, width: l.fish.width * s, height: l.fish.height * s, child: child!);
        },
        child: IgnorePointer(child: body),
      );
    }
    return Positioned(
      key: ValueKey('fish$n'),
      left: at.dx,
      top: at.dy,
      width: l.fish.width,
      height: l.fish.height,
      child: DPressable(
        id: 'fishing.fish.$n',
        semanticLabel: '$n',
        excludeSemantics: true,
        onTap: () => _tapFish(n),
        borderRadius: BorderRadius.circular(l.fish.height / 2),
        pressedScale: 0.94,
        child: Wiggle(count: _wiggles[n] ?? 0, child: body),
      ),
    );
  }
}

/// The bank and the bucket at the top, the lanes of the pond under it.
class _Layout {
  _Layout(this.bucket, this.top, this.laneHeight, this.fish, this.swimLeft, this.swimRange);

  factory _Layout.of(Size a, int n) {
    final bank = math.min(a.height * 0.16, a.width * 0.24);
    final bucket = Rect.fromLTWH(a.width - bank * 1.1, 0, bank, bank);
    final top = bank + a.height * 0.03;
    final laneHeight = (a.height - top) / n;
    final h = math.min(laneHeight * 0.92, a.width * 0.22);
    final fish = Size(h * 1.6, h);
    return _Layout(bucket, top, laneHeight, fish, 0, a.width - fish.width);
  }

  final Rect bucket;
  final double top, laneHeight, swimLeft, swimRange;
  final Size fish;

  /// The top of lane [i]'s fish.
  double lane(int i) => top + laneHeight * i + (laneHeight - fish.height) / 2;
}

/// The water: two blues, ripples, and a wavy edge along the top.
class _PondPainter extends CustomPainter {
  const _PondPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..drawRect(Offset.zero & size, Paint()..color = const Color(0xFF7CC8F0))
      ..drawRect(Rect.fromLTWH(0, size.height * 0.55, size.width, size.height * 0.45), Paint()..color = const Color(0xFF5BB3E6));
    final ripple = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final rng = math.Random(4);
    for (var k = 0; k < 26; k++) {
      final c = Offset(rng.nextDouble() * size.width, 24 + rng.nextDouble() * (size.height - 48));
      final w = 30 + rng.nextDouble() * 50;
      canvas.drawArc(Rect.fromCenter(center: c, width: w, height: w * 0.3), math.pi * 1.1, math.pi * 0.8, false, ripple);
    }
    final edge = Path()..moveTo(0, 0);
    for (var x = 0.0; x <= size.width; x += 40) {
      edge
        ..quadraticBezierTo(x + 10, -8, x + 20, 0)
        ..quadraticBezierTo(x + 30, 8, x + 40, 0);
    }
    canvas.drawPath(
      edge,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
  }

  @override
  bool shouldRepaint(_PondPainter old) => false;
}

/// A fish with its number on a white patch; the body turns to face the
/// way it swims, the number never mirrors.
class _FishView extends StatelessWidget {
  const _FishView({required this.number, required this.color, required this.facingLeft, required this.glow, required this.size});
  final int number;
  final Color color;
  final bool facingLeft, glow;
  final Size size;

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Transform.flip(flipX: !facingLeft, child: RepaintBoundary(child: CustomPaint(painter: _FishPainter(color, glow)))),
          ),
          Positioned(
            left: size.width * (facingLeft ? 0.36 : 0.24),
            top: size.height * 0.18,
            width: size.height * 0.64,
            height: size.height * 0.64,
            child: DecoratedBox(
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [for (final d in '$number'.split('')) GlyphView(d, height: size.height * (number >= 10 ? 0.34 : 0.4), color: const Color(0xFF2B2440))],
                ),
              ),
            ),
          ),
        ],
      );
}

/// A fish facing left: an oval body, a tail, a fin, an eye.
class _FishPainter extends CustomPainter {
  const _FishPainter(this.color, this.glow);
  final Color color;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final dark = Color.lerp(color, const Color(0xFF2B2440), 0.35)!;
    final body = Rect.fromLTRB(w * 0.02, h * 0.08, w * 0.8, h * 0.92);
    // A solid halo, not a blur: blurs are too slow on the frame.
    if (glow) canvas.drawOval(body.inflate(h * 0.1), Paint()..color = const Color(0xAAFFD54F));
    final tail = Path()
      ..moveTo(w * 0.74, h * 0.5)
      ..lineTo(w * 0.99, h * 0.12)
      ..quadraticBezierTo(w * 0.9, h * 0.5, w * 0.99, h * 0.88)
      ..close();
    final fin = Path()
      ..moveTo(w * 0.3, h * 0.12)
      ..quadraticBezierTo(w * 0.45, -h * 0.08, w * 0.6, h * 0.14)
      ..close();
    final ink = Paint()
      ..color = dark
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, h * 0.04)
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(tail, Paint()..color = dark)
      ..drawPath(fin, Paint()..color = dark)
      ..drawOval(body, Paint()..color = color)
      ..drawOval(body, ink)
      ..drawCircle(Offset(w * 0.12, h * 0.4), h * 0.07, Paint()..color = const Color(0xFF2B2440))
      ..drawArc(Rect.fromCenter(center: Offset(w * 0.1, h * 0.6), width: h * 0.16, height: h * 0.12), 0.2, 2.2, false, ink);
  }

  @override
  bool shouldRepaint(_FishPainter old) => old.color != color || old.glow != glow;
}

/// The bucket on the bank, with a tail sticking out for each fish in it.
class _BucketPainter extends CustomPainter {
  const _BucketPainter(this.count);
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final ink = Paint()
      ..color = const Color(0xFF4A4560)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, w * 0.03)
      ..strokeCap = StrokeCap.round;
    // Tails first, behind the rim.
    for (var k = 0; k < count; k++) {
      final x = w * (0.35 + 0.15 * k);
      final tail = Path()
        ..moveTo(x, h * 0.4)
        ..lineTo(x - w * 0.08, h * 0.16)
        ..lineTo(x + w * 0.08, h * 0.16)
        ..close();
      canvas.drawPath(tail, Paint()..color = _kFishPaints[k % _kFishPaints.length]);
    }
    final pail = Path()
      ..moveTo(w * 0.14, h * 0.36)
      ..lineTo(w * 0.86, h * 0.36)
      ..lineTo(w * 0.76, h * 0.96)
      ..lineTo(w * 0.24, h * 0.96)
      ..close();
    canvas
      ..drawArc(Rect.fromLTRB(w * 0.18, h * 0.04, w * 0.82, h * 0.7), math.pi, math.pi, false, ink)
      ..drawPath(pail, Paint()..color = const Color(0xFF9CA6B8))
      ..drawRect(Rect.fromLTRB(w * 0.18, h * 0.55, w * 0.82, h * 0.63), Paint()..color = const Color(0xFFB9C2D2))
      ..drawPath(pail, ink)
      ..drawLine(Offset(w * 0.12, h * 0.36), Offset(w * 0.88, h * 0.36), ink);
  }

  @override
  bool shouldRepaint(_BucketPainter old) => old.count != count;
}
