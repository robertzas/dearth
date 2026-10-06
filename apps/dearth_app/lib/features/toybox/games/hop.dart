import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// C major from middle C: pad n's note, so the number line has a tune and
/// hopping down it goes down.
const List<int> _scale = [60, 62, 64, 65, 67, 69, 71, 72, 74, 76, 77];

const Color _padFill = Color(0xFF8FD889), _padInk = Color(0xFF3E8E46), _numeral = Color(0xFF1F4D2A);

/// Frog Hop (SPEC FR-TOY-03, Appendix B: the number line, one more and one
/// less, first adding). Lily pads numbered 0–5, then 0–10, make a number
/// line: across the water on a wide screen, up it on a tall one. A frog
/// sits on one. The voice asks ("Hop to six!", "One more than four!",
/// "Three and two more!"); she taps a pad, and on the right one the frog
/// hops there a pad at a time, a rising note per pad and an arc over the
/// water for each hop, and the voice says where it landed. A wrong pad
/// wiggles and says its number; after two slips, or a long pause, the right
/// pad glows.
class HopGame extends StatefulWidget {
  const HopGame(this.c, {super.key});
  final GameController c;

  @override
  State<HopGame> createState() => HopGameState();
}

@visibleForTesting
class HopGameState extends State<HopGame> with SingleTickerProviderStateMixin {
  /// One hop's time: quick enough to feel like a frog, slow enough to count.
  static const hopTime = Duration(milliseconds: 340);

  late HopRound _round;
  final _wiggles = <int, int>{};
  int _slips = 0, _landed = 0, _deal = 0;
  bool _solved = false, _nudge = false;
  Timer? _ask, _idle, _next;
  late final AnimationController _hop = AnimationController(vsync: this)..addListener(_onHop);

  @visibleForTesting
  HopRound get debugRound => _round;

  /// The pad the frog is on (or flying from).
  int get _at => _solved ? _round.target : _round.from;

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  @override
  void dispose() {
    for (final t in [_ask, _idle, _next]) {
      t?.cancel();
    }
    _hop.dispose();
    super.dispose();
  }

  void _newRound() {
    _round = hopRound(widget.c.level, widget.c.random, last: _deal == 0 ? null : _round.target);
    _wiggles.clear();
    _slips = _landed = 0;
    _solved = _nudge = false;
    _deal++;
    _hop.value = 0;
    _ask?.cancel();
    // A beat for the pads to land before the question.
    _ask = Timer(const Duration(milliseconds: 600), _sayPrompt);
    _waitIdle();
    if (mounted) setState(() {});
  }

  void _sayPrompt() => widget.c.say(hopAskClip(_round));

  /// A long pause asks again and lights the pad, without counting a slip.
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 12), () {
      if (!mounted || _solved) return;
      _sayPrompt();
      setState(() => _nudge = true);
    });
  }

  void _tapPad(int n) {
    if (_solved) return; // keep the handler; just ignore taps while it hops
    if (n != _round.target) {
      _slips++;
      widget.c.cue();
      widget.c.say(numberClip(n));
      setState(() => _wiggles[n] = (_wiggles[n] ?? 0) + 1);
      _waitIdle();
      return;
    }
    _idle?.cancel();
    setState(() => _solved = true);
    _hop.duration = hopTime * _round.hops;
    unawaited(_hop.forward(from: 0).then((_) => _arrive()));
  }

  /// A note as the frog lands on each pad along the way.
  void _onHop() {
    final landed = (_hop.value * _round.hops + 1e-6).floor();
    if (landed <= _landed) return;
    _landed = landed;
    final pad = _round.from + (_round.target > _round.from ? landed : -landed);
    widget.c.sound(Sfx.xylophone, volume: 0.45, rate: math.pow(2, (_scale[pad] - kXylophoneBaseMidi) / 12).toDouble());
  }

  void _arrive() {
    if (!mounted) return;
    widget.c.say(numberClip(_round.target));
    unawaited(widget.c.finishRound(hopResult(_slips), emoji: '🐸'));
    _next = Timer(afterVoice(numberClip(_round.target), atLeast: const Duration(milliseconds: 2800)), _newRound);
    setState(() {});
  }

  String get _askLabel {
    final r = _round;
    if (_solved && !_hop.isAnimating) return 'Landed on ${r.target}!';
    return switch (r.mode) {
      HopMode.find => 'Hop to ${r.target}',
      HopMode.oneMore => 'One more than ${r.from}',
      HopMode.oneLess => 'One less than ${r.from}',
      HopMode.add => '${r.from} and ${r.hops} more',
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round;
    final pill = 44 * t.scale;
    return Backdrop(
      top: const Color(0xFFE3F6FF),
      bottom: const Color(0xFFB9E2F2),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final l = _Line.of(box.biggest, r.pads);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // The hops so far, as arcs over the water.
                  Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _ArcPainter(l, r, _hop)))),
                  for (var n = 0; n < r.pads; n++) _pad(n, l),
                  _frog(l),
                ],
              );
            }),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'hop.ask',
              label: _askLabel,
              onSayAgain: _sayPrompt,
              children: switch (r.mode) {
                HopMode.find => [DEmoji('🐸', size: pill), SizedBox(width: t.space.sm), _Numeral(r.target, height: pill, color: _numeral)],
                HopMode.oneMore || HopMode.oneLess => [
                    _Numeral(r.from, height: pill, color: _numeral),
                    DEmoji(r.mode == HopMode.oneMore ? '➕' : '➖', size: pill * 0.8),
                    _Numeral(1, height: pill, color: _numeral),
                  ],
                HopMode.add => [_Numeral(r.from, height: pill, color: _numeral), DEmoji('➕', size: pill * 0.8), _Numeral(r.hops, height: pill, color: _numeral)],
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _pad(int n, _Line l) {
    final c = l.pads[n];
    final glow = !_solved && n == _round.target && (_slips >= 2 || _nudge);
    final frogHere = n == _at && !_hop.isAnimating;
    return Positioned(
      left: c.dx - l.size / 2,
      top: c.dy - l.size / 2,
      child: tid(
        'hop.pad.$n',
        Semantics(
          button: true,
          label: frogHere ? '$n, frog' : '$n',
          onTap: () => _tapPad(n),
          excludeSemantics: true,
          child: GestureDetector(
            excludeFromSemantics: true,
            behavior: HitTestBehavior.opaque,
            onTap: () => _tapPad(n),
            child: Wiggle(count: _wiggles[n] ?? 0, child: _Pad(n: n, size: l.size, glow: glow, notch: -1.1 + (n * 0.37) % 0.6)),
          ),
        ),
      ),
    );
  }

  Widget _frog(_Line l) {
    final size = l.size * 0.82;
    return AnimatedBuilder(
      animation: _hop,
      builder: (context, child) {
        final at = _solved ? l.along(_round.from, _round.target, _hop.value) : l.seat(_round.from);
        return Positioned(left: at.dx - size / 2, top: at.dy - size / 2, child: child!);
      },
      child: IgnorePointer(
        child: tid('hop.frog', Semantics(label: 'Frog on $_at', child: RepaintBoundary(child: DEmoji('🐸', size: size)))),
      ),
    );
  }
}

/// A number in the Toybox's ball-and-stick digits (the shapes Number
/// Tracing teaches).
class _Numeral extends StatelessWidget {
  const _Numeral(this.n, {required this.height, required this.color});
  final int n;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, d) in '$n'.split('').indexed) ...[
            if (i > 0) SizedBox(width: height * 0.06),
            GlyphView(d, height: height, color: color),
          ],
        ],
      );
}

/// A lily pad seen from above, with its number. The notch sits near the
/// top, turned a little differently on each, and stops short of the middle
/// so it never crosses the numeral.
class _Pad extends StatelessWidget {
  const _Pad({required this.n, required this.size, required this.glow, required this.notch});
  final int n;
  final double size, notch;
  final bool glow;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(size: Size.square(size), painter: _PadPainter(glow: glow, notch: notch)),
            _Numeral(n, height: size * (n >= 10 ? 0.36 : 0.42), color: _numeral),
          ],
        ),
      );
}

class _PadPainter extends CustomPainter {
  const _PadPainter({required this.glow, required this.notch});
  final bool glow;
  final double notch;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 0.46;
    if (glow) canvas.drawCircle(c, r * 1.16, Paint()..color = const Color(0xAAFFD54F));
    // A circle with a narrow wedge cut into its rim, like a real lily pad.
    final pad = Path()
      ..moveTo(c.dx + math.cos(notch) * r * 0.62, c.dy + math.sin(notch) * r * 0.62)
      ..arcTo(Rect.fromCircle(center: c, radius: r), notch + 0.3, math.pi * 2 - 0.6, false)
      ..close();
    canvas.drawPath(pad, Paint()..color = _padFill);
    canvas.drawPath(
      pad,
      Paint()
        ..color = glow ? const Color(0xFFFFB300) : _padInk
        ..style = PaintingStyle.stroke
        ..strokeWidth = glow ? size.width * 0.05 : size.width * 0.03
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_PadPainter old) => old.glow != glow || old.notch != notch;
}

/// The hops made this round, as dashed arcs, drawn as the frog flies.
class _ArcPainter extends CustomPainter {
  _ArcPainter(this.line, this.round, this.hop) : super(repaint: hop);
  final _Line line;
  final HopRound round;
  final Animation<double> hop;

  @override
  void paint(Canvas canvas, Size size) {
    final done = hop.value * round.hops;
    if (done <= 0) return;
    final step = round.target > round.from ? 1 : -1;
    final paint = Paint()..color = const Color(0xCCFFFFFF);
    final dot = line.size * 0.028;
    for (var k = 0; k < round.hops && k < done; k++) {
      final a = round.from + k * step;
      final upTo = math.min(1.0, done - k);
      // Dots along the arc, as far as the frog has got.
      for (var u = 0.0; u <= upTo; u += 0.08) {
        canvas.drawCircle(line.arc(a, a + step, u), dot, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.line != line || old.round != round;
}

/// Where the pads are: a row across a wide screen, a column up a tall one
/// (0 at the bottom, as numbers grow up). The frog sits above a pad in a
/// row, beside it in a column, so its number stays in sight.
class _Line {
  _Line(this.pads, this.size, this.vertical);

  factory _Line.of(Size area, int n) {
    final vertical = area.height > area.width * 1.1;
    final along = vertical ? area.height : area.width;
    final across = vertical ? area.width : area.height;
    final size = math.min(math.min(along / n * 0.88, across * 0.3), 200.0);
    final gap = along / n;
    return _Line(
      [
        for (var i = 0; i < n; i++)
          vertical ? Offset(area.width * 0.6, area.height - gap * (i + 0.5)) : Offset(gap * (i + 0.5), area.height * 0.62),
      ],
      size,
      vertical,
    );
  }

  final List<Offset> pads;
  final double size;
  final bool vertical;

  /// Away from the pads, toward where the frog sits.
  Offset get _out => vertical ? const Offset(-1, 0) : const Offset(0, -1);

  /// Where the frog sits on pad [n]: on its far edge in a row, clear of
  /// its number beside a column.
  Offset seat(int n) => pads[n] + _out * (size * (vertical ? 0.9 : 0.72));

  /// The frog [u] (0…1) of the way through a hop from pad [a] to [b].
  Offset arc(int a, int b, double u) => Offset.lerp(seat(a), seat(b), u)! + _out * (size * 0.7 * math.sin(math.pi * u));

  /// The frog [t] (0…1) of the way through all its hops from [from] to [to].
  Offset along(int from, int to, double t) {
    final hops = (to - from).abs();
    if (hops == 0) return seat(to);
    final step = to > from ? 1 : -1;
    final k = math.min((t * hops).floor(), hops - 1);
    return arc(from + k * step, from + (k + 1) * step, t * hops - k);
  }
}
