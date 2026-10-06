import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Banana Balance (SPEC FR-TOY-03, Appendix B: comparing quantities). A
/// see-saw with a monkey on the middle and a pile of bananas (later a number
/// card) on each end. The voice asks "Which side has more?" She taps a side:
/// the right one goes down, because the heavier side always does, the
/// monkey hops, and the voice says "Five is more than three." A wrong side
/// wiggles and says how many it has ("Three."), and the side with more
/// glows; a long pause asks again.
class BalanceGame extends StatefulWidget {
  const BalanceGame(this.c, {super.key});
  final GameController c;

  @override
  State<BalanceGame> createState() => BalanceGameState();
}

@visibleForTesting
class BalanceGameState extends State<BalanceGame> {
  BalanceRound? _round;
  int _slips = 0, _deal = 0, _monkeyHops = 0;
  final _wiggles = <bool, int>{};
  bool _solved = false;
  Timer? _ask, _idle, _say, _next;

  @visibleForTesting
  BalanceRound get debugRound => _round!;

  /// The plank's tilt: 0 level, negative when the left side is down.
  @visibleForTesting
  double get debugTilt => _solved ? (_round!.leftMore ? -_tilt : _tilt) : 0;
  static const _tilt = 0.17;

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  @override
  void dispose() {
    for (final t in [_ask, _idle, _say, _next]) {
      t?.cancel();
    }
    super.dispose();
  }

  void _newRound() {
    _round = balanceRound(widget.c.level, widget.c.random, last: _round);
    _slips = 0;
    _solved = false;
    _wiggles.clear();
    _deal++;
    _ask?.cancel();
    // The plank levels out and the new loads land before the question.
    _ask = Timer(const Duration(milliseconds: 700), _sayPrompt);
    _waitIdle();
    if (mounted) setState(() {});
  }

  void _sayPrompt() => widget.c.say(_solved ? balanceMoreClip(_round!.more, _round!.fewer) : VoiceLine.balanceAsk);

  /// A long pause asks again (not a slip).
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 12), () {
      if (!mounted || _solved) return;
      _sayPrompt();
      _waitIdle();
    });
  }

  void _tap(bool left) {
    final r = _round!;
    final side = left ? r.left : r.right;
    if (_solved) {
      widget.c.say(numberClip(side.count));
      return;
    }
    _waitIdle();
    if (left != r.leftMore) {
      _slips++;
      widget.c.cue();
      widget.c.say(numberClip(side.count));
      setState(() => _wiggles[left] = (_wiggles[left] ?? 0) + 1);
      return;
    }
    _idle?.cancel();
    widget.c.sound(Sfx.boing, volume: 0.5);
    setState(() {
      _solved = true;
      _monkeyHops++;
    });
    // As the plank comes down, the voice says why.
    _say = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      final clip = balanceMoreClip(r.more, r.fewer);
      widget.c.say(clip);
      unawaited(widget.c.finishRound(balanceResult(_slips), emoji: '🍌'));
      _next = Timer(afterVoice(clip, atLeast: const Duration(milliseconds: 3000)), _newRound);
    });
  }

  String _describe(BalanceSide s) => s.numeral ? 'card ${s.count}' : '${s.count} banana${s.count == 1 ? '' : 's'}';

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    return Backdrop(
      top: const Color(0xFFE4F6FF),
      bottom: const Color(0xFFFFF4D6),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final l = _Layout.of(box.biggest);
              return Stack(
                key: ValueKey(_deal),
                clipBehavior: Clip.none,
                children: [
                  // The stand, under the plank's middle.
                  Positioned(
                    left: l.pivot.dx - l.stand.width / 2,
                    top: l.pivot.dy,
                    width: l.stand.width,
                    height: l.stand.height,
                    child: const RepaintBoundary(child: CustomPaint(painter: _StandPainter())),
                  ),
                  Positioned(
                    left: l.pivot.dx - l.plank / 2,
                    top: l.pivot.dy - l.load,
                    width: l.plank,
                    height: l.load + l.thick,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: debugTilt),
                      duration: const Duration(milliseconds: 1100),
                      curve: Curves.elasticOut,
                      builder: (context, a, child) => Transform.rotate(angle: a, alignment: Alignment(0, 1 - l.thick / (l.load + l.thick)), child: child),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // The plank.
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: l.thick,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0xFFC8874B),
                                borderRadius: BorderRadius.circular(l.thick / 2),
                                border: Border.all(color: const Color(0xFF8E5A2C), width: math.max(2, l.thick * 0.12)),
                              ),
                            ),
                          ),
                          for (final left in const [true, false])
                            Positioned(
                              left: left ? 0 : null,
                              right: left ? null : 0,
                              bottom: l.thick * 0.6,
                              width: l.side,
                              height: l.load,
                              child: _sideOf(left, l),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // The monkey rides the middle, where the plank doesn't move.
                  Positioned(
                    left: l.pivot.dx - l.monkey / 2,
                    top: l.pivot.dy - l.monkey * 0.92,
                    child: IgnorePointer(child: Hop(count: _monkeyHops, child: DEmoji('🐒', size: l.monkey))),
                  ),
                ],
              );
            }),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'balance.ask',
              label: _solved ? '${r.more} is more than ${r.fewer}' : 'Which side has more?',
              onSayAgain: _sayPrompt,
              children: [DEmoji('🍌', size: 40 * t.scale), SizedBox(width: t.space.xs), DEmoji('⚖️', size: 40 * t.scale)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sideOf(bool left, _Layout l) {
    final r = _round!;
    final side = left ? r.left : r.right;
    final more = left == r.leftMore;
    final glow = !_solved && _slips >= 1 && more;
    return DPressable(
      id: 'balance.side.${left ? 'left' : 'right'}',
      semanticLabel: '${left ? 'Left' : 'Right'}: ${_describe(side)}${_solved && more ? ', more' : ''}',
      excludeSemantics: true,
      onTap: () => _tap(left),
      pressedScale: 0.96,
      borderRadius: BorderRadius.circular(l.side * 0.1),
      child: Wiggle(
        count: _wiggles[left] ?? 0,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: side.numeral ? _Card(count: side.count, size: math.min(l.side * 0.5, l.load * 0.42)) : _Pile(count: side.count, size: l.banana, rows: l.rows),
              ),
            ),
            _Plate(width: l.side * 0.9, glow: glow),
          ],
        ),
      ),
    );
  }
}

/// Bananas piled the way a child would: four along the bottom, then three,
/// two and one (ten at most), so a pile reads at a glance; narrower and
/// taller on a tall screen ([rows]: how many each row holds, bottom up).
class _Pile extends StatelessWidget {
  const _Pile({required this.count, required this.size, required this.rows});
  final int count;
  final double size;
  final List<int> rows;

  @override
  Widget build(BuildContext context) {
    final rows = <int>[];
    var left = count;
    for (final cap in this.rows) {
      if (left == 0) break;
      final n = math.min(cap, left);
      rows.add(n);
      left -= n;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final n in rows.reversed)
          SizedBox(
            height: size * 0.78,
            child: Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < n; i++) SizedBox(width: size * 0.9, child: Center(child: DEmoji('🍌', size: size)))]),
          ),
      ],
    );
  }
}

/// A number card standing on the plate, in the Toybox's print.
class _Card extends StatelessWidget {
  const _Card({required this.count, required this.size});
  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(size * 0.18), border: Border.all(color: const Color(0xFFF2C46B), width: size * 0.05), boxShadow: t.elevation.e1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [for (final d in '$count'.split('')) GlyphView(d, height: size * 0.58, color: const Color(0xFF2B2440))],
      ),
    );
  }
}

/// A shallow dish at the end of the plank; it glows as a hint.
class _Plate extends StatelessWidget {
  const _Plate({required this.width, required this.glow});
  final double width;
  final bool glow;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: width,
        height: width * 0.12,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8EC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(width * 0.03), bottom: Radius.circular(width * 0.08)),
          border: Border.all(color: glow ? const Color(0xFFFFC93C) : const Color(0xFFE2C08D), width: glow ? 6 : 3),
          // A solid halo, not a blur: blurs are too slow to animate on a frame.
          boxShadow: [BoxShadow(color: glow ? const Color(0x88FFD54F) : const Color(0x00FFD54F), spreadRadius: glow ? 12 : 0)],
        ),
      );
}

/// The see-saw's stand: a wooden triangle on a little base.
class _StandPainter extends CustomPainter {
  const _StandPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final wood = Paint()..color = const Color(0xFFB4743E);
    final ink = Paint()
      ..color = const Color(0xFF8E5A2C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, w * 0.04)
      ..strokeJoin = StrokeJoin.round;
    final tri = Path()
      ..moveTo(w / 2, 0)
      ..lineTo(w * 0.92, h * 0.86)
      ..lineTo(w * 0.08, h * 0.86)
      ..close();
    canvas
      ..drawPath(tri, wood)
      ..drawPath(tri, ink);
    final base = RRect.fromRectAndRadius(Rect.fromLTWH(0, h * 0.84, w, h * 0.16), Radius.circular(h * 0.06));
    canvas
      ..drawRRect(base, Paint()..color = const Color(0xFF8E5A2C))
      ..drawCircle(Offset(w / 2, h * 0.06), w * 0.08, Paint()..color = const Color(0xFF6E4421));
  }

  @override
  bool shouldRepaint(_StandPainter old) => false;
}

/// The see-saw sized to the play area and centred in it: as wide as fits,
/// the loads above the plank, the stand below its middle. Piles are 4-3-2-1
/// on a wide screen and 3-3-2-1-1 on a tall one, where height is plenty
/// and width isn't.
class _Layout {
  _Layout(this.pivot, this.plank, this.thick, this.side, this.load, this.banana, this.monkey, this.stand, this.rows);

  factory _Layout.of(Size area) {
    final tall = area.height > area.width;
    final rows = tall ? const [3, 3, 2, 1, 1] : const [4, 3, 2, 1];
    final plank = math.min(area.width * 0.94, area.height * 1.7);
    final side = plank * 0.36;
    final thick = math.max(10.0, plank * 0.03);
    final stand = Size(plank * 0.16, math.min(plank * 0.16, area.height * 0.22));
    final load = math.min(area.height * 0.9 - stand.height, side * (tall ? 1.9 : 1.25));
    // Wide enough for the bottom row, tall enough for every row.
    final banana = math.min(side * 0.9 / (rows.first * 0.9), load * 0.86 / (rows.length * 0.78) - 2);
    // The whole see-saw, centred, a little above the middle.
    final pivotY = (area.height - load - stand.height) * 0.42 + load;
    return _Layout(Offset(area.width / 2, pivotY), plank, thick, side, load, banana, math.min(side * 0.42, load * 0.5), stand, rows);
  }

  final Offset pivot;
  final double plank, thick, side, load, banana, monkey;
  final Size stand;
  final List<int> rows;
}
