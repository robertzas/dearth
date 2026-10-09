import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Rocket Countdown (SPEC FR-TOY-03, Appendix B: counting back, number
/// order). A rocket waits on its pad under a night sky of numbered stars.
/// "Count down from ten!": she taps the stars in order, ten, nine, eight…
/// Each says its number, a note plays a step higher than the last, the star
/// settles into a small lit one, and a segment of the rocket's fuel gauge
/// lights. At one: "Zero! Blast off!", and the rocket lifts off in flame
/// and smoke. A wrong star wiggles and says its own number; after two, or a
/// long pause, the voice asks for the next one ("Find the number seven.")
/// and its star glows.
class RocketGame extends StatefulWidget {
  const RocketGame(this.c, {super.key});
  final GameController c;

  @override
  State<RocketGame> createState() => RocketGameState();
}

@visibleForTesting
class RocketGameState extends State<RocketGame> with TickerProviderStateMixin {
  RocketRound? _round;

  /// Each star's place in the sky: a grid cell and a nudge within it, as
  /// fractions, so it fits any screen.
  List<Offset> _places = const [];
  int _done = 0, _slips = 0, _slipsHere = 0, _deal = 0;
  bool _glow = false, _launched = false;
  final _wiggles = <int, int>{};
  final _timers = <Timer>[];
  Timer? _idle;

  late final AnimationController _launch = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  late final AnimationController _rumble = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));

  @visibleForTesting
  RocketRound get debugRound => _round!;

  /// Stars tapped so far.
  @visibleForTesting
  int get debugDone => _done;

  @visibleForTesting
  bool get debugHint => _glow;

  int get _next => _round!.countdown[_done];

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _idle?.cancel();
    _launch.dispose();
    _rumble.dispose();
    super.dispose();
  }

  void _after(Duration d, VoidCallback f) => _timers.add(Timer(d, () {
        if (mounted) f();
      }));

  void _newRound() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    final r = _round = rocketRound(widget.c.level, widget.c.random, last: _round);
    final rng = widget.c.random;
    final cells = [for (var i = 0; i < r.start; i++) i]..shuffle(rng);
    _places = [for (final c in cells) Offset(c.toDouble(), 0) + Offset((rng.nextDouble() - 0.5) * 0.3, (rng.nextDouble() - 0.5) * 0.3)];
    _done = _slips = _slipsHere = 0;
    _glow = _launched = false;
    _wiggles.clear();
    _deal++;
    _launch.value = 0;
    _after(const Duration(milliseconds: 600), _sayStart);
    _waitIdle();
    if (mounted) setState(() {});
  }

  void _sayStart() => widget.c.say(rocketStartClip(_round!.start));

  /// A long pause asks for the next star and lights it (not a slip).
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 9), () {
      if (!mounted || _launched) return;
      widget.c.say(findNumberClip(_next));
      setState(() => _glow = true);
    });
  }

  void _tapStar(int n) {
    final r = _round!;
    if (_launched) return;
    final at = r.countdown.indexOf(n);
    if (at < _done) {
      // Already lit: it just says its number.
      widget.c.say(numberClip(n));
      return;
    }
    _waitIdle();
    if (n != _next) {
      _slips++;
      _slipsHere++;
      widget.c.cue();
      widget.c.say(numberClip(n));
      setState(() => _wiggles[n] = (_wiggles[n] ?? 0) + 1);
      if (_slipsHere >= 2) {
        _after(afterVoice(numberClip(n), atLeast: const Duration(milliseconds: 700)), () => widget.c.say(findNumberClip(_next)));
        setState(() => _glow = true);
      }
      return;
    }
    // A note a step higher each time: the countdown builds to the launch.
    final step = (_done * 10 / r.start).round();
    const scale = [0, 2, 4, 7, 9];
    final midi = 60 + 12 * (step ~/ 5) + scale[step % 5];
    widget.c.sound(Sfx.xylophone, volume: 0.45, rate: math.pow(2, (midi - kXylophoneBaseMidi) / 12).toDouble());
    widget.c.say(numberClip(n));
    unawaited(_rumble.forward(from: 0));
    setState(() {
      _done++;
      _slipsHere = 0;
      _glow = false;
    });
    if (_done < r.start) return;
    _idle?.cancel();
    setState(() => _launched = true);
    _after(afterVoice(numberClip(n), atLeast: const Duration(milliseconds: 700)), () {
      widget.c.say(VoiceLine.rocketBlastOff);
      // "Zero!" first, then up it goes on "Blast off!".
      _after(const Duration(milliseconds: 700), () {
        widget.c.sound(Sfx.boing, volume: 0.4, rate: 0.6);
        unawaited(_launch.forward(from: 0));
        unawaited(widget.c.finishRound(rocketResult(r, _slips), emoji: '🚀'));
      });
      _after(const Duration(milliseconds: 700) + _launch.duration! + const Duration(milliseconds: 900), _newRound);
    });
  }

  String _askLabel() {
    final r = _round!;
    if (_launched) return 'Blast off!';
    return 'Count down from ${r.start}: next $_next';
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    return Backdrop(
      top: const Color(0xFF141844),
      bottom: const Color(0xFF3B2D6E),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _SkyPainter()))),
          PlayArea(
            top: 130,
            child: LayoutBuilder(builder: (context, box) {
              final l = _Layout.of(box.biggest, r.start);
              return Stack(
                key: ValueKey(_deal),
                clipBehavior: Clip.none,
                children: [
                  Positioned.fromRect(
                    rect: l.pad,
                    child: RepaintBoundary(
                      child: CustomPaint(painter: _RocketPainter(launch: _launch, rumble: _rumble, fuel: _done / r.start, segments: r.start)),
                    ),
                  ),
                  for (var i = 0; i < r.start; i++) _star(r.countdown[i], l.star(_places[i]), l.starSize),
                ],
              );
            }),
          ),
          TopPrompt(child: PromptPill(id: 'rocket.ask', label: _askLabel(), onSayAgain: _sayStart, children: [DEmoji('🚀', size: 40 * t.scale)])),
        ],
      ),
    );
  }

  Widget _star(int n, Offset at, double size) {
    final r = _round!;
    final lit = r.countdown.indexOf(n) < _done;
    final glow = _glow && !_launched && n == _next;
    final s = lit ? size * 0.7 : size;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      left: at.dx - s / 2,
      top: at.dy - s / 2,
      width: s,
      height: s,
      child: DPressable(
        id: 'rocket.star.$n',
        semanticLabel: lit ? '$n, lit' : '$n',
        excludeSemantics: true,
        onTap: () => _tapStar(n),
        borderRadius: BorderRadius.circular(s / 2),
        pressedScale: 0.9,
        child: Wiggle(
          count: _wiggles[n] ?? 0,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _StarPainter(lit: lit, glow: glow)))),
              Padding(
                padding: EdgeInsets.only(top: s * 0.08),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [for (final d in '$n'.split('')) GlyphView(d, height: s * (n >= 10 ? 0.3 : 0.36), color: const Color(0xFF2B2440))],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The rocket and its pad on one side (left when wide, bottom when tall),
/// the stars in a grid of cells over the rest of the sky.
class _Layout {
  _Layout(this.pad, this.sky, this.cols, this.rows, this.n);

  factory _Layout.of(Size a, int n) {
    final gap = math.max(12.0, a.shortestSide * 0.03);
    final Rect pad, sky;
    if (a.width > a.height * 1.1) {
      final w = math.min(a.width * 0.24, a.height * 0.5);
      pad = Rect.fromLTWH(0, 0, w, a.height);
      sky = Rect.fromLTRB(w + gap, 0, a.width, a.height);
    } else {
      final h = math.min(a.height * 0.3, a.width * 0.9);
      pad = Rect.fromLTWH((a.width - h * 0.6) / 2, a.height - h, h * 0.6, h);
      sky = Rect.fromLTRB(0, 0, a.width, a.height - h - gap);
    }
    final cols = math.max(1, math.sqrt(n * sky.width / sky.height).ceil());
    final rows = (n / cols).ceil();
    return _Layout(pad, sky, cols, rows, n);
  }

  final Rect pad, sky;
  final int cols, rows, n;

  double get starSize => math.min(sky.width / cols, sky.height / rows) * 0.86;

  /// A star's centre: [place].dx rounds to its cell, and what's left over
  /// (with [place].dy) nudges it within the cell.
  Offset star(Offset place) {
    final cell = place.dx.round();
    final nudge = Offset(place.dx - cell, place.dy);
    final cw = sky.width / cols, ch = sky.height / rows;
    final row = cell ~/ cols, col = cell % cols;
    // A short last row is centred.
    final inRow = row == rows - 1 ? n - row * cols : cols;
    final x = sky.left + sky.width / 2 + (col - (inRow - 1) / 2) * cw + nudge.dx * cw * 0.4;
    return Offset(x, sky.top + ch * (row + 0.5) + nudge.dy * ch * 0.4);
  }
}

/// Faint background stars, fixed.
class _SkyPainter extends CustomPainter {
  const _SkyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(7);
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.5);
    for (var i = 0; i < 70; i++) {
      canvas.drawCircle(Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height), 0.8 + rng.nextDouble() * 1.6, dot);
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) => false;
}

/// A five-pointed star: bright gold to tap, pale and small once lit.
class _StarPainter extends CustomPainter {
  const _StarPainter({required this.lit, required this.glow});
  final bool lit, glow;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final path = Path();
    for (var k = 0; k < 10; k++) {
      final a = -math.pi / 2 + k * math.pi / 5;
      final rr = k.isEven ? r * 0.98 : r * 0.5;
      final p = c + Offset(math.cos(a), math.sin(a)) * rr;
      k == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    // A solid halo, not a blur: blurs are too slow on the frame.
    if (glow) canvas.drawCircle(c, r * 1.02, Paint()..color = const Color(0x66FFE27A));
    canvas
      ..drawPath(path, Paint()..color = lit ? const Color(0xFFFFF4C2) : const Color(0xFFFFD34D))
      ..drawPath(
        path,
        Paint()
          ..color = lit ? const Color(0xFFE8C766) : const Color(0xFFE09B12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, r * 0.06)
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.lit != lit || old.glow != glow;
}

/// The rocket on its pad, with a fuel gauge of [segments] beside it filled
/// to [fuel]. It shivers on each count ([rumble]) and lifts off in flame and
/// smoke ([launch]).
class _RocketPainter extends CustomPainter {
  _RocketPainter({required this.launch, required this.rumble, required this.fuel, required this.segments}) : super(repaint: Listenable.merge([launch, rumble]));
  final Animation<double> launch, rumble;
  final double fuel;
  final int segments;

  static const _ink = Color(0xFF2B2440);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final up = Curves.easeIn.transform(launch.value);
    final body = Rect.fromCenter(center: Offset(w * 0.42, h * 0.52), width: w * 0.42, height: h * 0.62);
    // The pad.
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.06, h * 0.93, w * 0.78, h * 0.99), Radius.circular(h * 0.015)), Paint()..color = const Color(0xFF6E6A86));
    // Smoke billows from the pad as it goes.
    if (launch.value > 0) {
      final puff = Paint()..color = Colors.white.withValues(alpha: (0.85 * (1 - launch.value)).clamp(0, 1));
      for (var k = 0; k < 6; k++) {
        final spread = (k - 2.5) * w * 0.12 * (0.4 + launch.value);
        canvas.drawCircle(Offset(w * 0.42 + spread, h * 0.93), w * (0.08 + 0.1 * launch.value) * (1 - (k - 2.5).abs() * 0.08), puff);
      }
    }
    // The fuel gauge: a segment per star, filling bottom up.
    final gauge = Rect.fromLTRB(w * 0.82, h * 0.25, w * 0.96, h * 0.9);
    canvas.drawRRect(RRect.fromRectAndRadius(gauge, Radius.circular(w * 0.04)), Paint()..color = const Color(0x33FFFFFF));
    final seg = (gauge.height - w * 0.02) / segments;
    final lit = (fuel * segments).round();
    for (var i = 0; i < segments; i++) {
      final y = gauge.bottom - w * 0.01 - (i + 1) * seg;
      final color = i < lit ? Color.lerp(const Color(0xFF4CC46A), const Color(0xFFFF7A3D), i / math.max(1, segments - 1))! : const Color(0x22FFFFFF);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(gauge.left + w * 0.015, y + seg * 0.12, gauge.width - w * 0.03, seg * 0.76), Radius.circular(seg * 0.2)), Paint()..color = color);
    }

    canvas.save();
    final shiver = rumble.value == 0 || rumble.value == 1 ? 0.0 : math.sin(rumble.value * math.pi * 8) * w * 0.012 * (1 - rumble.value);
    canvas.translate(shiver, -up * (h * 1.6));
    // Flame under it while it flies.
    if (launch.value > 0) {
      final flick = 0.85 + 0.15 * math.sin(launch.value * 90);
      final base = body.bottom;
      final flame = Path()
        ..moveTo(body.left + body.width * 0.2, base)
        ..quadraticBezierTo(body.center.dx, base + body.height * 0.75 * flick, body.right - body.width * 0.2, base)
        ..close();
      final inner = Path()
        ..moveTo(body.left + body.width * 0.32, base)
        ..quadraticBezierTo(body.center.dx, base + body.height * 0.45 * flick, body.right - body.width * 0.32, base)
        ..close();
      canvas
        ..drawPath(flame, Paint()..color = const Color(0xFFFF7A3D))
        ..drawPath(inner, Paint()..color = const Color(0xFFFFE27A));
    }
    final ink = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, w * 0.018)
      ..strokeJoin = StrokeJoin.round;
    // Fins.
    final fins = Path()
      ..moveTo(body.left, body.bottom - body.height * 0.3)
      ..lineTo(body.left - body.width * 0.35, body.bottom + body.height * 0.02)
      ..lineTo(body.left + body.width * 0.1, body.bottom - body.height * 0.06)
      ..close()
      ..moveTo(body.right, body.bottom - body.height * 0.3)
      ..lineTo(body.right + body.width * 0.35, body.bottom + body.height * 0.02)
      ..lineTo(body.right - body.width * 0.1, body.bottom - body.height * 0.06)
      ..close();
    canvas
      ..drawPath(fins, Paint()..color = const Color(0xFFE5484D))
      ..drawPath(fins, ink);
    // The body: a tall capsule with a pointed nose.
    final hull = Path()
      ..moveTo(body.center.dx, body.top - body.height * 0.18)
      ..quadraticBezierTo(body.right + body.width * 0.05, body.top + body.height * 0.1, body.right, body.top + body.height * 0.35)
      ..lineTo(body.right, body.bottom - body.height * 0.04)
      ..quadraticBezierTo(body.center.dx, body.bottom + body.height * 0.03, body.left, body.bottom - body.height * 0.04)
      ..lineTo(body.left, body.top + body.height * 0.35)
      ..quadraticBezierTo(body.left - body.width * 0.05, body.top + body.height * 0.1, body.center.dx, body.top - body.height * 0.18)
      ..close();
    canvas
      ..drawPath(hull, Paint()..color = const Color(0xFFF4F1FA))
      ..save()
      ..clipPath(hull)
      ..drawRect(Rect.fromLTRB(body.left - w, body.top - body.height, body.right + w, body.top + body.height * 0.12), Paint()..color = const Color(0xFFE5484D))
      ..drawRect(Rect.fromLTRB(body.left - w, body.bottom - body.height * 0.14, body.right + w, body.bottom + w), Paint()..color = const Color(0xFF3E8EF7))
      ..restore()
      ..drawPath(hull, ink);
    // The window.
    final win = Offset(body.center.dx, body.top + body.height * 0.36);
    canvas
      ..drawCircle(win, body.width * 0.24, Paint()..color = const Color(0xFF9FD4EE))
      ..drawCircle(win + Offset(-body.width * 0.07, -body.width * 0.07), body.width * 0.07, Paint()..color = Colors.white.withValues(alpha: 0.9))
      ..drawCircle(win, body.width * 0.24, ink)
      ..restore();
  }

  @override
  bool shouldRepaint(_RocketPainter old) => old.fuel != fuel || old.segments != segments;
}
