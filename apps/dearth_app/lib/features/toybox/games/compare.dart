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
    _paints = ([...kBusPaints]..shuffle(widget.c.random)).take(r.buses.length).toList();
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
              child: BusView(sign: '$n', color: _paints[i], kids: k, glow: _glows(i), seed: _deal * 7 + i, width: l.bus),
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
        child: Center(child: SizedBox(width: size, height: size * _Layout.aspect, child: BusView(sign: '7', color: kBusPaints.first, kids: 7, glow: false, seed: 3, width: size))),
      );
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
  static const aspect = kBusAspect;

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
