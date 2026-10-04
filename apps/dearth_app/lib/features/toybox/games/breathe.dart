import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Breathing Buddy (SPEC FR-TOY-03, Appendix B: a calm-down). Her buddy
/// holds a balloon. She taps it, and the voice breathes with her: "Breathe
/// in, and smell the flower" as the balloon fills over four seconds, "and
/// blow out the candle" as it empties over five and the flame bends away.
/// Three breaths, then four, then five; a dot fills for each. No cheering
/// at the end, only a quiet "well done".
class BreatheGame extends StatefulWidget {
  const BreatheGame(this.c, {super.key});
  final GameController c;

  @override
  State<BreatheGame> createState() => BreatheGameState();
}

/// Where a session is.
enum BreathStep { ready, starting, breatheIn, breatheOut, done }

@visibleForTesting
class BreatheGameState extends State<BreatheGame> with SingleTickerProviderStateMixin {
  static const intro = 3.6, breatheIn = 4.0, breatheOut = 5.0;

  late final Ticker _ticker = createTicker(_tick);

  /// Seconds since the session started.
  final _clock = ValueNotifier<double>(0);
  BreathStep _step = BreathStep.ready;
  int _breaths = 3, _breathed = 0, _frames = 0;
  Timer? _rest;

  @visibleForTesting
  BreathStep get debugStep => _step;

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    _rest?.cancel();
    super.dispose();
  }

  void _start() {
    if (_step != BreathStep.ready && _step != BreathStep.done) return;
    _rest?.cancel();
    widget.c.sound(Sfx.pop, volume: 0.4);
    widget.c.say(VoiceLine.breatheStart);
    setState(() {
      _breaths = breathsFor(widget.c.level);
      _breathed = 0;
      _step = BreathStep.starting;
    });
    _clock.value = 0;
    _frames = 0;
    if (_ticker.isActive) _ticker.stop();
    unawaited(_ticker.start());
  }

  /// The step at [t] seconds in, and how far through it (0…1).
  (BreathStep, int, double) _at(double t) {
    if (t < intro) return (BreathStep.starting, 0, t / intro);
    final s = t - intro;
    final i = s ~/ (breatheIn + breatheOut);
    if (i >= _breaths) return (BreathStep.done, _breaths, 1);
    final r = s - i * (breatheIn + breatheOut);
    return r < breatheIn ? (BreathStep.breatheIn, i, r / breatheIn) : (BreathStep.breatheOut, i, (r - breatheIn) / breatheOut);
  }

  void _tick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    final (step, i, _) = _at(t);
    if (step != _step || i != _breathed) {
      _enter(step, i);
      if (!mounted) return;
    }
    // A slow animation: 30 fps is plenty on the slowest displays.
    if (DTheme.of(context).policy.ambientFps < 60 && (_frames++).isOdd) return;
    _clock.value = t;
  }

  void _enter(BreathStep step, int i) {
    switch (step) {
      case BreathStep.breatheIn:
        widget.c.say(VoiceLine.breatheIn);
      case BreathStep.breatheOut:
        widget.c.say(VoiceLine.breatheOut);
      case BreathStep.done:
        _ticker.stop();
        widget.c.say(VoiceLine.breatheDone);
        widget.c.sound(Sfx.sparkle, volume: 0.4);
        unawaited(widget.c.finishRound(GameResult.played, emoji: '🌬️', calm: true));
      case BreathStep.ready || BreathStep.starting:
        break;
    }
    setState(() {
      _step = step;
      _breathed = i;
    });
  }

  /// How full the balloon is at [t]: empty at rest, filling as she
  /// breathes in, emptying as she breathes out.
  double _fill(double t) {
    final (step, _, p) = _at(t);
    final eased = Curves.easeInOut.transform(p.clamp(0, 1));
    return switch (step) {
      BreathStep.breatheIn => eased,
      BreathStep.breatheOut => 1 - eased,
      _ => 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final buddy = buddyEmoji(widget.c.kid.buddy);
    final (label, hint) = switch (_step) {
      BreathStep.ready => ('Tap the balloon to start', '👆'),
      BreathStep.starting => ('Get ready', '🎈'),
      BreathStep.breatheIn => ('Breathe in: smell the flower', '🌸'),
      BreathStep.breatheOut => ('Breathe out: blow out the candle', '🕯️'),
      BreathStep.done => ('All calm. Tap the balloon to go again', '💜'),
    };
    return Backdrop(
      top: const Color(0xFFE9E4FF),
      bottom: const Color(0xFFFFE9DE),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 130,
            child: LayoutBuilder(builder: (context, box) {
              // Wide: flower, balloon and candle side by side. Tall: the
              // balloon big in the middle, flower and candle under it.
              final wide = box.maxWidth > box.maxHeight;
              final unit = wide ? math.min(box.maxWidth / 3.4, box.maxHeight / 1.5) : math.min(box.maxWidth / 1.6, box.maxHeight / 2.6);
              final inhaling = _step == BreathStep.breatheIn;
              final exhaling = _step == BreathStep.breatheOut;
              final flower = _Card(
                id: 'breathe.flower',
                label: 'Flower',
                size: unit * 0.62,
                glow: inhaling,
                child: ValueListenableBuilder<double>(
                  valueListenable: _clock,
                  builder: (context, c, child) => Transform.scale(scale: 1 + 0.14 * (inhaling ? _fill(c) : 0), child: child),
                  child: DEmoji('🌸', size: unit * 0.36),
                ),
              );
              final balloon = DPressable(
                id: 'breathe.balloon',
                semanticLabel: label,
                excludeSemantics: true,
                onTap: _start,
                pressedScale: 0.96,
                child: SizedBox(
                  width: unit * 1.1,
                  height: unit * 1.45,
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      Positioned.fill(
                        bottom: unit * 0.3,
                        child: RepaintBoundary(child: CustomPaint(painter: _BalloonPainter(_clock, _fill))),
                      ),
                      DEmoji(buddy, size: unit * 0.4),
                    ],
                  ),
                ),
              );
              final candle = _Card(
                id: 'breathe.candle',
                label: 'Candle',
                size: unit * 0.62,
                glow: exhaling,
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: Size(unit * 0.3, unit * 0.48),
                    painter: _CandlePainter(_clock, (c) {
                      final (step, _, p) = _at(c);
                      // The flame bends away and goes out as she blows;
                      // it's lit again for the next breath.
                      return switch (step) {
                        BreathStep.breatheOut => (1 - Curves.easeIn.transform((p * 1.25).clamp(0, 1)), p),
                        _ => (1.0, 0.0),
                      };
                    }),
                  ),
                ),
              );
              return Column(
                children: [
                  Expanded(
                    child: Center(
                      child: wide
                          ? Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, crossAxisAlignment: CrossAxisAlignment.end, children: [flower, balloon, candle])
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                balloon,
                                SizedBox(height: unit * 0.12),
                                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [flower, candle]),
                              ],
                            ),
                    ),
                  ),
                  SizedBox(height: t.space.md),
                  tid(
                    'breathe.dots',
                    Semantics(
                      label: '${_step == BreathStep.done ? _breaths : _breathed} of $_breaths breaths',
                      excludeSemantics: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < _breaths; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 400),
                              margin: EdgeInsets.symmetric(horizontal: t.space.xs),
                              width: 26 * t.scale,
                              height: 26 * t.scale,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i < _breathed || _step == BreathStep.done ? const Color(0xFFA27BEF) : Colors.white,
                                border: Border.all(color: const Color(0xFFA27BEF), width: 3),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'breathe.ask',
              label: label,
              children: [DEmoji('🌬️', size: 44 * t.scale), SizedBox(width: t.space.sm), DEmoji(hint, size: 44 * t.scale)],
            ),
          ),
        ],
      ),
    );
  }
}

/// A white card for the flower and the candle, softly lit while it's their
/// turn.
class _Card extends StatelessWidget {
  const _Card({required this.id, required this.label, required this.size, required this.glow, required this.child});
  final String id, label;
  final double size;
  final bool glow;
  final Widget child;

  @override
  Widget build(BuildContext context) => tid(
        id,
        Semantics(
          label: glow ? '$label, now' : label,
          excludeSemantics: true,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: glow ? const Color(0xFFFFC93C) : const Color(0xFFE3DCF5), width: glow ? 7 : 3),
              // A solid halo, first in the list: never an animated blur.
              boxShadow: [BoxShadow(color: glow ? const Color(0x66FFD54F) : const Color(0x00FFD54F), spreadRadius: glow ? 12 : 0)],
            ),
            child: child,
          ),
        ),
      );
}

/// The balloon, its knot at the buddy's hand, growing upward as it fills.
class _BalloonPainter extends CustomPainter {
  _BalloonPainter(this.clock, this.fill) : super(repaint: clock);
  final ValueListenable<double> clock;
  final double Function(double t) fill;

  @override
  void paint(Canvas canvas, Size size) {
    final f = fill(clock.value);
    final scale = 0.5 + 0.5 * f;
    final w = size.width * 0.78 * scale, h = size.height * 0.8 * scale;
    final knot = Offset(size.width / 2, size.height - size.height * 0.12);
    // The string, down to the buddy.
    canvas.drawPath(
      Path()
        ..moveTo(knot.dx, knot.dy)
        ..quadraticBezierTo(knot.dx - size.width * 0.06, size.height - size.height * 0.05, knot.dx, size.height),
      Paint()
        ..color = const Color(0xFF8C82A8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    final body = Rect.fromCenter(center: Offset(knot.dx, knot.dy - h / 2 - 4), width: w, height: h);
    canvas.drawOval(body, Paint()..color = const Color(0xFFF2709C));
    canvas.drawPath(
      Path()
        ..moveTo(knot.dx - 9, knot.dy)
        ..lineTo(knot.dx + 9, knot.dy)
        ..lineTo(knot.dx, knot.dy - 10)
        ..close(),
      Paint()..color = const Color(0xFFD9547F),
    );
    // A shine, so it reads as round.
    canvas.drawOval(
      Rect.fromCenter(center: body.topLeft + Offset(w * 0.3, h * 0.26), width: w * 0.18, height: h * 0.26),
      Paint()..color = const Color(0x66FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_BalloonPainter old) => false;
}

/// A candle whose flame bends away and shrinks as she blows.
class _CandlePainter extends CustomPainter {
  _CandlePainter(this.clock, this.flame) : super(repaint: clock);
  final ValueListenable<double> clock;

  /// The flame's height (0 = out) and how far it bends, at a time.
  final (double, double) Function(double t) flame;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final top = h * 0.42;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.22, top, w * 0.56, h - top), Radius.circular(w * 0.1)), Paint()..color = const Color(0xFFFFF1D6));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.22, top, w * 0.56, h * 0.08), Radius.circular(w * 0.1)), Paint()..color = const Color(0xFFF5DDB0));
    final wick = Offset(w / 2, top);
    canvas.drawLine(wick, wick.translate(0, -h * 0.06), Paint()
      ..color = const Color(0xFF4A3F35)
      ..strokeWidth = 3);
    final (height, bend) = flame(clock.value);
    if (height <= 0.02) return;
    final fh = h * 0.36 * height;
    final base = wick.translate(0, -h * 0.05);
    final tip = base.translate(bend * w * 0.45, -fh);
    Path drop(double k) => Path()
      ..moveTo(base.dx, base.dy)
      ..quadraticBezierTo(base.dx - w * 0.2 * k, base.dy - fh * 0.35, tip.dx, base.dy - (base.dy - tip.dy) * k)
      ..quadraticBezierTo(base.dx + w * 0.2 * k, base.dy - fh * 0.35, base.dx, base.dy)
      ..close();
    canvas.drawPath(drop(1), Paint()..color = const Color(0xFFFF9F1C));
    canvas.drawPath(drop(0.6), Paint()..color = const Color(0xFFFFE066));
  }

  @override
  bool shouldRepaint(_CandlePainter old) => false;
}
