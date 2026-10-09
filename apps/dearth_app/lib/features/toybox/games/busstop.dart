import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'bus.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Bus Stop (SPEC FR-TOY-03, Appendix B: first adding and taking away).
/// Who Has More?'s double-decker pulls in with kids in its windows ("Three
/// kids are on the bus."). Kids waiting at the stop walk to the door and
/// climb on one at a time, each filling a window with a pop ("Two more get
/// on!"); later some climb off first and walk away. Then "How many kids are
/// on the bus now?" and three number cards: the answer, the number it
/// started with, and a neighbor. The right card puts the number on the
/// roof sign, the voice says "Five kids on the bus!" and the bus drives
/// off. A wrong card wiggles and says its number, and the windows light up
/// one by one as the voice counts the kids; then the right card glows.
class BusStopGame extends StatefulWidget {
  const BusStopGame(this.c, {super.key});
  final GameController c;

  @override
  State<BusStopGame> createState() => BusStopGameState();
}

@visibleForTesting
class BusStopGameState extends State<BusStopGame> {
  BusStopRound? _round;
  Color _paint = kBusPaints.first;
  int _deal = 0, _onBus = 0, _waiting = 0, _slips = 0, _lit = 0, _busHops = 0, _next = 0;
  bool _arrived = false, _asked = false, _solved = false, _leaving = false, _glow = false, _counted = false;
  final _walkers = <int, _Walk>{};
  final _wiggles = <int, int>{};
  final _timers = <Timer>[];
  Timer? _idle;

  @visibleForTesting
  BusStopRound get debugRound => _round!;

  /// Kids in the windows now.
  @visibleForTesting
  int get debugOnBus => _onBus;

  /// Whether the question has been asked and the cards are out.
  @visibleForTesting
  bool get debugAsked => _asked;

  @visibleForTesting
  bool get debugHint => _glow;

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
    _idle?.cancel();
    final r = _round = busStopRound(widget.c.level, widget.c.random, last: _round);
    _paint = kBusPaints[widget.c.random.nextInt(kBusPaints.length)];
    _deal++;
    _onBus = r.start;
    _waiting = r.on;
    _slips = _lit = 0;
    _arrived = _asked = _solved = _leaving = _glow = _counted = false;
    _walkers.clear();
    _wiggles.clear();
    // The bus pulls in, then says how many are on board.
    _after(const Duration(milliseconds: 100), () {
      setState(() => _arrived = true);
      widget.c.sound(Sfx.honk, volume: 0.35);
    });
    final start = busStartClip(r.start);
    _after(const Duration(milliseconds: 1100), () => widget.c.say(start));
    _after(const Duration(milliseconds: 1100) + afterVoice(start), r.off > 0 ? _getOff : _getOn);
    if (mounted) setState(() {});
  }

  static const _step = Duration(milliseconds: 900);

  /// "Two get off!", then one at a time: a window empties and a kid steps
  /// out of the door and walks away.
  void _getOff() {
    final r = _round!;
    final line = busOffClip(r.off);
    widget.c.say(line);
    final lead = afterVoice(line, atLeast: const Duration(milliseconds: 1200));
    for (var k = 0; k < r.off; k++) {
      _after(lead + _step * k, () {
        widget.c.sound(Sfx.pop, volume: 0.45);
        final id = _next++;
        setState(() {
          _onBus--;
          _walkers[id] = const _Walk(off: true);
        });
        _after(const Duration(milliseconds: 1500), () => setState(() => _walkers.remove(id)));
      });
    }
    _after(lead + _step * r.off + const Duration(milliseconds: 500), r.on > 0 ? _getOn : _ask);
  }

  /// "Two more get on!", then one at a time: a kid walks from the stop to
  /// the door and a window fills.
  void _getOn() {
    final r = _round!;
    final line = busOnClip(r.on);
    widget.c.say(line);
    final lead = afterVoice(line, atLeast: const Duration(milliseconds: 1200));
    for (var k = 0; k < r.on; k++) {
      _after(lead + _step * k, () {
        final id = _next++;
        setState(() {
          _waiting--;
          _walkers[id] = _Walk(off: false, spot: _waiting);
        });
        _after(const Duration(milliseconds: 700), () {
          widget.c.sound(Sfx.pop, volume: 0.45);
          setState(() {
            _walkers.remove(id);
            _onBus++;
          });
        });
      });
    }
    _after(lead + _step * r.on + const Duration(milliseconds: 500), _ask);
  }

  void _ask() {
    setState(() => _asked = true);
    _sayAsk();
    _waitIdle();
  }

  void _sayAsk() => widget.c.say(VoiceLine.busStopAsk);

  /// A long pause asks again (not a slip).
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 12), () {
      if (!mounted || _solved) return;
      _sayAsk();
      _waitIdle();
    });
  }

  void _tapBus() {
    widget.c.sound(Sfx.honk, volume: 0.35);
    setState(() => _busHops++);
  }

  void _tapCard(int i) {
    final r = _round!;
    if (!_asked || _solved) return;
    final n = r.choices[i];
    _waitIdle();
    if (n != r.answer) {
      _slips++;
      widget.c.cue();
      widget.c.say(numberClip(n));
      setState(() => _wiggles[i] = (_wiggles[i] ?? 0) + 1);
      if (!_counted) {
        _counted = true;
        _countWindows(afterVoice(numberClip(n), atLeast: const Duration(milliseconds: 800)));
      }
      return;
    }
    _idle?.cancel();
    widget.c.sound(Sfx.honk, volume: 0.5);
    setState(() {
      _solved = true;
      _busHops++;
    });
    final yes = busNowClip(r.answer);
    widget.c.say(yes);
    unawaited(widget.c.finishRound(busStopResult(_slips), emoji: '🚌'));
    _after(afterVoice(yes, atLeast: const Duration(milliseconds: 2600)), () {
      setState(() => _leaving = true);
      _after(const Duration(milliseconds: 1000), _newRound);
    });
  }

  /// The hint: the windows light one by one as the voice counts the kids,
  /// one number each so the words keep pace; then the right card glows.
  void _countWindows(Duration lead) {
    final n = _round!.answer;
    for (var k = 1; k <= n; k++) {
      _after(lead + const Duration(milliseconds: 750) * (k - 1), () {
        if (_solved) return;
        widget.c.say(numberClip(k));
        setState(() => _lit = k);
      });
    }
    _after(lead + const Duration(milliseconds: 750) * n, () => setState(() => _glow = true));
  }

  String _askLabel() {
    final r = _round!;
    if (_solved) return '${r.answer} kid${r.answer == 1 ? '' : 's'} on the bus';
    return _asked ? 'How many kids are on the bus now?' : 'Here comes the bus';
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    return Backdrop(
      top: const Color(0xFFDDF1FF),
      bottom: const Color(0xFFFFF1DC),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final l = _Layout.of(box.biggest);
              final busAt = _leaving ? Offset(-l.bus.width - 40, l.bus.top) : (_arrived ? l.bus.topLeft : Offset(box.maxWidth + 40, l.bus.top));
              return Stack(
                key: ValueKey(_deal),
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _StreetPainter(l)))),
                  for (var k = 0; k < _waiting; k++)
                    Positioned.fromRect(rect: l.kidAt(l.spot(k)), child: _KidFigure(seed: _deal * 11 + k)),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeInOutCubic,
                    left: busAt.dx,
                    top: busAt.dy,
                    width: l.bus.width,
                    height: l.bus.height,
                    child: DPressable(
                      id: 'busstop.bus',
                      semanticLabel: 'Bus: $_onBus kid${_onBus == 1 ? '' : 's'}',
                      excludeSemantics: true,
                      onTap: _tapBus,
                      borderRadius: BorderRadius.circular(l.bus.width * 0.06),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: _onBus.toDouble()),
                        duration: const Duration(milliseconds: 250),
                        builder: (context, k, _) => Hop(
                          count: _busHops,
                          child: BusView(sign: _solved ? '${r.answer}' : '', color: _paint, kids: k, glow: false, seed: _deal * 5, width: l.bus.width, lit: _lit),
                        ),
                      ),
                    ),
                  ),
                  for (final e in _walkers.entries) _walker(e.key, e.value, l),
                  if (_asked)
                    Positioned.fromRect(
                      rect: l.cards,
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < r.choices.length; i++)
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: l.card * 0.08),
                                child: PictureTile(
                                  id: 'busstop.card.$i',
                                  label: '${r.choices[i]}',
                                  size: l.card,
                                  onTap: () => _tapCard(i),
                                  hint: _glow && r.choices[i] == r.answer && !_solved,
                                  tried: _solved && r.choices[i] != r.answer,
                                  wiggles: _wiggles[i] ?? 0,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [for (final d in '${r.choices[i]}'.split('')) GlyphView(d, height: l.card * 0.56, color: BusPainter.ink)],
                                  ),
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
            child: PromptPill(id: 'busstop.ask', label: _askLabel(), onSayAgain: _asked ? _sayAsk : () => widget.c.say(busStartClip(r.start)), children: [DEmoji('🚍', size: 40 * t.scale)]),
          ),
        ],
      ),
    );
  }

  /// A kid on the move: from a stop spot to the door (getting on), or out
  /// of the door and away past the stop (getting off).
  Widget _walker(int id, _Walk w, _Layout l) {
    final from = w.off ? l.door : l.spot(w.spot);
    final to = w.off ? l.away : l.door;
    return TweenAnimationBuilder<double>(
      key: ValueKey('w$id'),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: w.off ? 1400 : 700),
      curve: Curves.easeInOut,
      builder: (context, k, child) {
        final at = Offset.lerp(from, to, k)!;
        // A bounce in the step.
        final bob = math.sin(k * math.pi * 6).abs() * l.kid * 0.06;
        // Getting on, the kid shrinks into the door at the end.
        final s = w.off ? 1.0 : (k < 0.8 ? 1.0 : 1 - (k - 0.8) / 0.2);
        final rect = l.kidAt(at - Offset(0, bob));
        return Positioned.fromRect(rect: Rect.fromCenter(center: rect.center, width: rect.width * s, height: rect.height * s), child: child!);
      },
      child: IgnorePointer(child: _KidFigure(seed: _deal * 13 + id)),
    );
  }
}

@immutable
class _Walk {
  const _Walk({required this.off, this.spot = 0});
  final bool off;
  final int spot;
}

/// Where the bus stops, where kids wait (feet on the curb), and where the
/// number cards go. Wide: the bus on the left, the stop to its right, the
/// cards below. Tall: the bus on top, the stop under it, the cards below.
class _Layout {
  _Layout(this.bus, this.stop, this.cards, this.kid, this.card, this.awayX);

  factory _Layout.of(Size a) {
    final gap = math.max(12.0, a.shortestSide * 0.03);
    if (a.width > a.height * 1.1) {
      final top = a.height * 0.68;
      final w = math.min(a.width * 0.56, top / kBusAspect);
      final bus = Rect.fromLTWH(a.width * 0.02, (top - w * kBusAspect) / 2, w, w * kBusAspect);
      final kid = w * 0.22;
      final feet = bus.top + w * 0.66;
      final stop = Rect.fromLTRB(bus.right + gap * 2, feet - kid, a.width - gap, feet);
      final card = math.min(a.height - top - gap, a.width * 0.14);
      return _Layout(bus, stop, Rect.fromLTWH(0, top + gap / 2, a.width, a.height - top - gap / 2), kid, card, a.width + kid);
    }
    final w = a.width * 0.94;
    final bus = Rect.fromLTWH((a.width - w) / 2, 0, w, w * kBusAspect);
    final kid = w * 0.22;
    final feet = bus.bottom + kid + gap;
    final stop = Rect.fromLTRB(a.width * 0.3, feet - kid, a.width - gap, feet);
    final rest = Rect.fromLTRB(0, feet + gap, a.width, a.height);
    final card = math.min(a.width * 0.28, rest.height - gap);
    return _Layout(bus, stop, rest, kid, card, a.width + kid);
  }

  final Rect bus, stop, cards;

  /// A kid's height, and a number card's size.
  final double kid, card;
  final double awayX;

  /// Where kids step on: the bottom of the door.
  Offset get door => Offset(bus.left + bus.width * 0.545, bus.top + bus.width * 0.6);

  /// Off past the stop, out of sight.
  Offset get away => Offset(awayX, stop.bottom);

  /// Waiting spot [k] (feet), nearest the door first.
  Offset spot(int k) => Offset(stop.left + kid * 0.4 + k * kid * 0.62, stop.bottom);

  /// A kid's box with its feet at [feet].
  Rect kidAt(Offset feet) => Rect.fromLTWH(feet.dx - kid * 0.28, feet.dy - kid, kid * 0.56, kid);
}

/// The road under the bus and the stop's sign on its pole.
class _StreetPainter extends CustomPainter {
  const _StreetPainter(this.l);
  final _Layout l;

  @override
  void paint(Canvas canvas, Size size) {
    final h = l.bus.width * 0.1;
    final y = l.bus.top + l.bus.width * 0.6;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, y, size.width, h), Radius.circular(h / 2)), Paint()..color = const Color(0xFFB9B4C4));
    final dash = Paint()..color = Colors.white.withValues(alpha: 0.85);
    for (var x = h; x < size.width - h; x += h * 2.4) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y + h * 0.44, h * 1.2, h * 0.12), Radius.circular(h * 0.06)), dash);
    }
    // The curb the kids wait on.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(l.stop.left - l.kid * 0.2, l.stop.bottom - l.kid * 0.04, l.stop.right, l.stop.bottom + l.kid * 0.08), Radius.circular(l.kid * 0.04)),
      Paint()..color = const Color(0xFFD9D3C7),
    );
    // The stop's pole and sign, at the far end of the curb.
    final x = l.stop.right - l.kid * 0.3;
    // Head height: a taller pole would reach into the bus above the curb on a tall screen.
    final sign = Offset(x, l.stop.bottom - l.kid * 1.05);
    canvas
      ..drawRect(Rect.fromLTWH(x - l.kid * 0.03, sign.dy, l.kid * 0.06, l.kid * 1.05), Paint()..color = const Color(0xFF8A8399))
      ..drawCircle(sign, l.kid * 0.17, Paint()..color = const Color(0xFF3E8EF7))
      ..drawCircle(
        sign,
        l.kid * 0.17,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = l.kid * 0.03,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: sign, width: l.kid * 0.2, height: l.kid * 0.1), Radius.circular(l.kid * 0.02)),
        Paint()..color = Colors.white,
      );
  }

  @override
  bool shouldRepaint(_StreetPainter old) => old.l.bus != l.bus || old.l.stop != l.stop;
}

/// A kid standing up: hair, face, a shirt, legs; colors from the bus kids'
/// set, chosen by [seed].
class _KidFigure extends StatelessWidget {
  const _KidFigure({required this.seed});
  final int seed;

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: CustomPaint(painter: _KidPainter(seed), size: Size.infinite));
}

class _KidPainter extends CustomPainter {
  const _KidPainter(this.seed);
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(seed * 17 + 3);
    final skin = BusPainter.skins[rng.nextInt(BusPainter.skins.length)];
    final hair = BusPainter.hair[rng.nextInt(BusPainter.hair.length)];
    final shirt = BusPainter.shirts[rng.nextInt(BusPainter.shirts.length)];
    final w = size.width, h = size.height;
    final ink = Paint()
      ..color = BusPainter.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, w * 0.05)
      ..strokeCap = StrokeCap.round;
    // Legs, then the shirt, then the head.
    final legs = Paint()
      ..color = const Color(0xFF4A5A8C)
      ..strokeWidth = w * 0.18
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(Offset(w * 0.36, h * 0.66), Offset(w * 0.34, h * 0.95), legs)
      ..drawLine(Offset(w * 0.64, h * 0.66), Offset(w * 0.66, h * 0.95), legs);
    final body = RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.12, h * 0.38, w * 0.88, h * 0.72), Radius.circular(w * 0.22));
    canvas
      ..drawRRect(body, Paint()..color = shirt)
      ..drawRRect(body, ink);
    final c = Offset(w * 0.5, h * 0.22);
    final r = w * 0.36;
    canvas
      ..drawCircle(c, r, Paint()..color = skin)
      ..drawArc(Rect.fromCircle(center: c, radius: r * 1.06), math.pi + 0.35, math.pi - 0.7, true, Paint()..color = hair)
      ..drawCircle(c, r, ink)
      ..drawCircle(c + Offset(-r * 0.36, r * 0.1), r * 0.11, Paint()..color = BusPainter.ink)
      ..drawCircle(c + Offset(r * 0.36, r * 0.1), r * 0.11, Paint()..color = BusPainter.ink)
      ..drawArc(Rect.fromCircle(center: c + Offset(0, r * 0.2), radius: r * 0.4), 0.25 * math.pi, 0.5 * math.pi, false, ink);
  }

  @override
  bool shouldRepaint(_KidPainter old) => old.seed != seed;
}
