import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Who Has More? (SPEC FR-TOY-03, Appendix B: comparing numerals). Double-
/// decker buses pull in one after another, each with its route number on a
/// sign on the roof, and the voice names each number as its bus stops. Then
/// it asks "Which bus has more kids?" (later "fewer"). The windows are empty
/// until she answers: the right bus honks and hops, the kids pop into every
/// bus's windows, ten to a deck (so 13 is a full deck and three more), and
/// the voice says "Seven. That bus has more kids!" A wrong bus wiggles and
/// says its number, the kids show so she can see who has more, and the
/// right bus glows. A long pause asks again and shows the kids. The top
/// level lines three buses up at the stop, fewest first.
class CompareGame extends StatefulWidget {
  const CompareGame(this.c, {super.key});
  final GameController c;

  @override
  State<CompareGame> createState() => CompareGameState();
}

/// Bus paints: bright, and far enough apart that no two buses look alike.
const List<Color> _kBusPaints = [Color(0xFFE5484D), Color(0xFF3E8EF7), Color(0xFF30A46C), Color(0xFFF2A516), Color(0xFF8E4EC6), Color(0xFFF76B15)];

@visibleForTesting
class CompareGameState extends State<CompareGame> {
  CompareRound? _round;
  List<Color> _paints = const [];
  int _deal = 0, _arrived = 0, _slips = 0, _slipsHere = 0;
  bool _asked = false, _shown = false, _solved = false, _leaving = false;
  final _lined = <int>[];
  final _wiggles = <int, int>{};
  final _hops = <int, int>{};
  final _timers = <Timer>[];
  Timer? _idle;

  @visibleForTesting
  CompareRound get debugRound => _round!;

  /// How many buses have pulled in.
  @visibleForTesting
  int get debugArrived => _arrived;

  /// Whether the question has been asked (taps before it don't count).
  @visibleForTesting
  bool get debugAsked => _asked;

  /// Whether every bus shows its kids.
  @visibleForTesting
  bool get debugKidsShown => _shown;

  /// The buses lined up so far, by index, fewest first.
  @visibleForTesting
  List<int> get debugLined => List.unmodifiable(_lined);

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
    final r = compareRound(widget.c.level, widget.c.random, last: _round);
    _round = r;
    _paints = ([..._kBusPaints]..shuffle(widget.c.random)).take(r.buses.length).toList();
    _deal++;
    _arrived = _slips = _slipsHere = 0;
    _asked = _shown = _solved = _leaving = false;
    _lined.clear();
    _wiggles.clear();
    _hops.clear();
    _after(const Duration(milliseconds: 300), _arrive);
    if (mounted) setState(() {});
  }

  /// The next bus pulls in with a toot, and the voice reads its number as
  /// it stops: one number per bus, so the words never run ahead of what she
  /// sees.
  void _arrive() {
    final r = _round!;
    final i = _arrived;
    setState(() => _arrived++);
    widget.c.sound(Sfx.honk, volume: 0.35);
    final clip = numberClip(r.buses[i]);
    _after(const Duration(milliseconds: 750), () => widget.c.say(clip));
    _after(const Duration(milliseconds: 750) + afterVoice(clip, atLeast: const Duration(milliseconds: 900)), _arrived < r.buses.length ? _arrive : _ask);
  }

  void _ask() {
    setState(() => _asked = true);
    _sayPrompt();
    _waitIdle();
  }

  void _sayPrompt() => widget.c.say(compareAskClip(_round!.ask));

  /// A long pause asks again and lets her see the kids (not a slip).
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 12), () {
      if (!mounted || _solved) return;
      setState(() => _shown = true);
      _sayPrompt();
      _waitIdle();
    });
  }

  void _tap(int i) {
    final r = _round!;
    if (i >= _arrived || _leaving) return;
    final n = r.buses[i];
    if (!_asked || _solved || _lined.contains(i)) {
      // Before the question, after the answer, or already in line: the bus
      // just toots and says its number.
      widget.c.sound(Sfx.honk, volume: 0.35);
      widget.c.say(numberClip(n));
      setState(() => _hops[i] = (_hops[i] ?? 0) + 1);
      return;
    }
    _waitIdle();
    final order = r.ask == CompareAsk.order;
    if (order ? n != r.lineUp[_lined.length] : i != r.answer) {
      _slips++;
      _slipsHere++;
      widget.c.cue();
      widget.c.say(numberClip(n));
      setState(() {
        _wiggles[i] = (_wiggles[i] ?? 0) + 1;
        _shown = true;
      });
      return;
    }
    widget.c.sound(Sfx.honk, volume: 0.5);
    widget.c.say(numberClip(n));
    setState(() {
      _hops[i] = (_hops[i] ?? 0) + 1;
      _slipsHere = 0;
      if (order) _lined.add(i);
      _solved = !order || _lined.length == r.buses.length;
      if (_solved) _shown = true;
    });
    if (!_solved) return;
    _idle?.cancel();
    final yes = compareYesClip(r.ask);
    _after(afterVoice(numberClip(n), atLeast: const Duration(milliseconds: 700)), () {
      widget.c.say(yes);
      // The line hops from fewest to most as the voice says so.
      if (order) {
        for (var k = 0; k < _lined.length; k++) {
          final b = _lined[k];
          _after(Duration(milliseconds: 350 * k), () => setState(() => _hops[b] = (_hops[b] ?? 0) + 1));
        }
      }
      unawaited(widget.c.finishRound(compareResult(r, _slips), emoji: '🚌'));
      _after(afterVoice(yes, atLeast: const Duration(milliseconds: 2600)), () {
        setState(() => _leaving = true);
        _after(const Duration(milliseconds: 950), _newRound);
      });
    });
  }

  String _askLabel() {
    final r = _round!;
    if (_solved) {
      return switch (r.ask) {
        CompareAsk.more => '${r.buses[r.answer]} has more',
        CompareAsk.fewer => '${r.buses[r.answer]} has fewer',
        CompareAsk.order => 'In order: ${r.lineUp.join(', ')}',
      };
    }
    if (!_asked) return 'Here come the buses';
    return switch (r.ask) {
      CompareAsk.more => 'Which bus has more kids?',
      CompareAsk.fewer => 'Which bus has fewer kids?',
      CompareAsk.order => 'Line up the buses, fewest first',
    };
  }

  String _busLabel(int i) {
    final n = _round!.buses[i];
    return [
      'Bus $n',
      if (i >= _arrived) 'coming',
      if (_lined.contains(i)) 'in line',
      if (_shown || _lined.contains(i)) '$n kid${n == 1 ? '' : 's'}',
    ].join(', ');
  }

  bool _glows(int i) {
    final r = _round!;
    if (_solved || !_asked) return false;
    if (r.ask == CompareAsk.order) return _slipsHere >= 2 && r.buses[i] == r.lineUp[_lined.length];
    return _slips >= 1 && i == r.answer;
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    return Backdrop(
      top: const Color(0xFFDDF1FF),
      bottom: const Color(0xFFEAF6E4),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final l = _Layout.of(box.biggest, r.buses.length);
              return Stack(
                key: ValueKey(_deal),
                children: [
                  Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _StreetPainter(l)))),
                  for (var i = 0; i < r.buses.length; i++) _bus(i, l, box.maxWidth),
                ],
              );
            }),
          ),
          TopPrompt(
            child: PromptPill(id: 'compare.ask', label: _askLabel(), onSayAgain: _sayPrompt, children: [DEmoji('🚌', size: 40 * t.scale)]),
          ),
        ],
      ),
    );
  }

  Widget _bus(int i, _Layout l, double width) {
    final r = _round!;
    final n = r.buses[i];
    final line = _lined.indexOf(i);
    // Waiting off to the right, at its place (or its bay in the line), or
    // gone off to the left.
    final home = line >= 0 ? l.bays[line] : l.slots[i];
    final at = _leaving ? Offset(-l.bus - 40, home.dy) : (i < _arrived ? home : Offset(width + 40, home.dy));
    final kids = _shown || line >= 0;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 850),
      curve: Curves.easeInOutCubic,
      left: at.dx,
      top: at.dy,
      width: l.bus,
      height: l.bus * _Layout.aspect,
      child: DPressable(
        id: 'compare.bus.$i',
        semanticLabel: _busLabel(i),
        excludeSemantics: true,
        onTap: () => _tap(i),
        borderRadius: BorderRadius.circular(l.bus * 0.06),
        // The kids' count lives above the hop and wiggle, which remount
        // what they hold: a second wiggle mustn't empty the bus again.
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: kids ? n.toDouble() : 0),
          duration: Duration(milliseconds: 250 + 45 * n),
          builder: (context, k, _) => Hop(
            count: _hops[i] ?? 0,
            child: Wiggle(
              count: _wiggles[i] ?? 0,
              child: _BusView(number: n, color: _paints[i], kids: k, glow: _glows(i), seed: _deal * 7 + i, width: l.bus),
            ),
          ),
        ),
      ),
    );
  }
}

/// The launcher tile's picture: a red double-decker, route 7, full of kids.
class CompareIcon extends StatelessWidget {
  const CompareIcon({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Center(child: SizedBox(width: size, height: size * _Layout.aspect, child: _BusView(number: 7, color: _kBusPaints.first, kids: 7, glow: false, seed: 3, width: size))),
      );
}

/// One bus: painted body and windows, and the route number on its roof
/// sign in the Toybox's print.
class _BusView extends StatelessWidget {
  const _BusView({required this.number, required this.color, required this.kids, required this.glow, required this.seed, required this.width});
  final int number, seed;
  final Color color;
  final double kids, width;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final sign = width * 0.27;
    final dark = Color.lerp(color, _BusPainter.ink, 0.45)!;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _BusPainter(color: color, kids: kids, glow: glow, seed: seed)))),
        Positioned(
          left: (width - sign) / 2,
          top: 0,
          width: sign,
          height: sign,
          child: DecoratedBox(
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: dark, width: math.max(2, width * 0.014))),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [for (final d in '$number'.split('')) GlyphView(d, height: sign * 0.5, color: _BusPainter.ink)],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A double-decker, front to the left (buses pull in leftward), in a box
/// [_Layout.aspect] times as tall as it is wide: the roof sign's space on
/// top, two decks of ten windows (five, a door or pillar, five), wheels at
/// the bottom. [kids] fill the windows lower deck first, front to back, the
/// last one growing in.
class _BusPainter extends CustomPainter {
  _BusPainter({required this.color, required this.kids, required this.glow, required this.seed});
  final Color color;
  final double kids;
  final bool glow;
  final int seed;

  static const ink = Color(0xFF2B2440);
  static const _glass = Color(0xFFCFEFFF);
  static const _skins = [Color(0xFFF6D3B3), Color(0xFFE0AC85), Color(0xFFB97A55), Color(0xFF8D5A3B), Color(0xFFFFE0C7)];
  static const _hair = [Color(0xFF3B2A20), Color(0xFF6B4226), Color(0xFFE2B04A), Color(0xFF1F1A17), Color(0xFFB5502B)];
  static const _shirts = [Color(0xFFFF8A65), Color(0xFF4FC3F7), Color(0xFFAED581), Color(0xFFFFD54F), Color(0xFFBA68C8), Color(0xFFF06292)];

  /// Window [i] (0–9 the lower deck, front to back; 10–19 the upper) of a
  /// bus [w] wide.
  static Rect window(int i, double w) {
    final col = i % 10, upper = i >= 10;
    final x = w * (0.135 + col * 0.079 + (col >= 5 ? 0.045 : 0));
    return Rect.fromLTWH(x, w * (upper ? 0.285 : 0.46), w * 0.064, w * (upper ? 0.11 : 0.105));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final dark = Color.lerp(color, ink, 0.45)!;
    final body = RRect.fromRectAndCorners(
      Rect.fromLTRB(w * 0.02, w * 0.25, w * 0.98, w * 0.62),
      topLeft: Radius.circular(w * 0.09),
      topRight: Radius.circular(w * 0.06),
      bottomLeft: Radius.circular(w * 0.03),
      bottomRight: Radius.circular(w * 0.03),
    );
    // A solid halo, not a blur: blurs are too slow on the frame.
    if (glow) canvas.drawRRect(body.inflate(w * 0.03), Paint()..color = const Color(0x99FFD54F));
    canvas.drawRRect(body, Paint()..color = color);
    // The cream band between the decks and the dark skirt.
    canvas
      ..save()
      ..clipRRect(body)
      ..drawRect(Rect.fromLTRB(0, w * 0.413, w, w * 0.44), Paint()..color = const Color(0xFFFFF4DC))
      ..drawRect(Rect.fromLTRB(0, w * 0.578, w, w * 0.62), Paint()..color = dark)
      ..restore();
    final glass = Paint()..color = _glass;
    final frame = Paint()
      ..color = dark
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, w * 0.006);
    // The windscreens at the front.
    for (final r in [Rect.fromLTRB(w * 0.035, w * 0.285, w * 0.115, w * 0.395), Rect.fromLTRB(w * 0.035, w * 0.46, w * 0.115, w * 0.565)]) {
      final rr = RRect.fromRectAndRadius(r, Radius.circular(w * 0.012));
      canvas
        ..drawRRect(rr, glass)
        ..drawRRect(rr, frame);
    }
    // The door, between the lower deck's fives.
    final door = RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.522, w * 0.455, w * 0.568, w * 0.605), Radius.circular(w * 0.008));
    canvas
      ..drawRRect(door, Paint()..color = const Color(0xFF9FD4EE))
      ..drawRRect(door, frame)
      ..drawLine(Offset(w * 0.545, w * 0.455), Offset(w * 0.545, w * 0.605), frame);
    final whole = kids.floor();
    for (var i = 0; i < 20; i++) {
      final r = window(i, w);
      final rr = RRect.fromRectAndRadius(r, Radius.circular(w * 0.012));
      canvas.drawRRect(rr, glass);
      if (i < whole) {
        _kid(canvas, r, i, 1);
      } else if (i == whole && kids > whole) {
        _kid(canvas, r, i, kids - whole);
      }
      canvas.drawRRect(rr, frame);
    }
    canvas
      ..drawRRect(
        body,
        Paint()
          ..color = dark
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, w * 0.012),
      )
      // A headlight.
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.03, w * 0.585, w * 0.075, w * 0.607), Radius.circular(w * 0.008)), Paint()..color = const Color(0xFFFFE066));
    for (final x in const [0.22, 0.8]) {
      canvas
        ..drawCircle(Offset(w * x, w * 0.62), w * 0.068, Paint()..color = ink)
        ..drawCircle(Offset(w * x, w * 0.62), w * 0.03, Paint()..color = const Color(0xFFB8B3C7));
    }
  }

  /// A kid looking out of window [win]: shoulders, a face, hair, eyes and a
  /// smile, [grow] from 0 (not there) to 1.
  void _kid(Canvas canvas, Rect win, int i, double grow) {
    final rng = math.Random(seed * 31 + i);
    final skin = _skins[rng.nextInt(_skins.length)];
    final hair = _hair[rng.nextInt(_hair.length)];
    final shirt = _shirts[rng.nextInt(_shirts.length)];
    final r = win.width * 0.34 * Curves.easeOutBack.transform(grow.clamp(0, 1));
    if (r < 0.5) return;
    final c = Offset(win.center.dx, win.top + win.height * 0.55);
    final face = ink.withValues(alpha: 0.85);
    canvas
      ..save()
      ..clipRect(win)
      ..drawOval(Rect.fromCenter(center: Offset(c.dx, win.bottom), width: r * 2.6, height: r * 1.5), Paint()..color = shirt)
      ..drawCircle(c, r, Paint()..color = skin)
      // Hair: the top of the head, down to the brow.
      ..drawArc(Rect.fromCircle(center: c, radius: r * 1.04), math.pi + 0.45, math.pi - 0.9, false, Paint()..color = hair)
      ..drawCircle(c + Offset(-r * 0.36, r * 0.02), r * 0.12, Paint()..color = face)
      ..drawCircle(c + Offset(r * 0.36, r * 0.02), r * 0.12, Paint()..color = face)
      ..drawArc(
        Rect.fromCircle(center: c + Offset(0, r * 0.1), radius: r * 0.42),
        0.25 * math.pi,
        0.5 * math.pi,
        false,
        Paint()
          ..color = face
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.12
          ..strokeCap = StrokeCap.round,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_BusPainter old) => old.kids != kids || old.glow != glow || old.color != color || old.seed != seed;
}

/// The street: a road under each row of buses, and in the line-up the bays
/// they park in, first to last.
class _StreetPainter extends CustomPainter {
  const _StreetPainter(this.l);
  final _Layout l;

  @override
  void paint(Canvas canvas, Size size) {
    final road = Paint()..color = const Color(0xFFB9B4C4);
    final dash = Paint()..color = Colors.white.withValues(alpha: 0.85);
    for (final y in l.roads) {
      final h = l.bus * 0.1;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, y, size.width, h), Radius.circular(h / 2)), road);
      for (var x = h; x < size.width - h; x += h * 2.4) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y + h * 0.44, h * 1.2, h * 0.12), Radius.circular(h * 0.06)), dash);
      }
    }
    final bay = Paint()..color = Colors.white.withValues(alpha: 0.35);
    final edge = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, l.bus * 0.012);
    for (final b in l.bays) {
      final rr = RRect.fromRectAndRadius(Rect.fromLTWH(b.dx + l.bus * 0.02, b.dy + l.bus * 0.25, l.bus * 0.96, l.bus * 0.4), Radius.circular(l.bus * 0.05));
      canvas
        ..drawRRect(rr, bay)
        ..drawRRect(rr, edge);
    }
  }

  @override
  bool shouldRepaint(_StreetPainter old) => old.l != l;
}

/// Where the buses stand, sized to the play area. Two buses side by side
/// on a wide screen, one above the other on a tall one. Three to line up:
/// a waiting row above the bays on a wide screen (the line reads left to
/// right), a waiting column beside them on a tall one (top to bottom).
class _Layout {
  _Layout(this.bus, this.slots, this.bays, this.roads);

  /// A bus box's height over its width (the roof sign to the wheels).
  static const aspect = 0.7;

  factory _Layout.of(Size area, int count) {
    final gap = math.max(12.0, area.shortestSide * 0.04);
    final wide = area.width > area.height;
    late double w;
    final slots = <Offset>[], bays = <Offset>[];
    if (count == 2) {
      if (wide) {
        w = math.min((area.width - gap) / 2 * 0.94, area.height * 0.86 / aspect);
        final y = (area.height - w * aspect) / 2;
        for (final side in const [-1, 1]) {
          slots.add(Offset(area.width / 2 + side * (w / 2 + gap / 2) - w / 2, y));
        }
      } else {
        w = math.min(area.width * 0.94, (area.height - gap) / 2 / aspect * 0.94);
        final top = (area.height - 2 * w * aspect - gap) / 2;
        for (var i = 0; i < 2; i++) {
          slots.add(Offset((area.width - w) / 2, top + i * (w * aspect + gap)));
        }
      }
    } else if (wide) {
      w = math.min((area.width - 2 * gap) / 3 * 0.94, (area.height - gap * 1.5) / 2 / aspect);
      final left = (area.width - 3 * w - 2 * gap) / 2;
      final top = (area.height - 2 * w * aspect - gap * 1.5) / 2;
      for (var i = 0; i < count; i++) {
        slots.add(Offset(left + i * (w + gap), top));
        bays.add(Offset(left + i * (w + gap), top + w * aspect + gap * 1.5));
      }
    } else {
      w = math.min((area.width - 2 * gap) / 2, (area.height - 2 * gap) / 3 / aspect);
      final top = (area.height - 3 * w * aspect - 2 * gap) / 2;
      for (var i = 0; i < count; i++) {
        final y = top + i * (w * aspect + gap);
        slots.add(Offset(area.width / 2 - gap / 2 - w, y));
        bays.add(Offset(area.width / 2 + gap / 2, y));
      }
    }
    // A road under the wheels of each row.
    final roads = {for (final p in [...slots, ...bays]) p.dy + w * 0.6}.toList();
    return _Layout(w, slots, bays, roads);
  }

  final double bus;
  final List<Offset> slots, bays;
  final List<double> roads;
}
