import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';

/// Each shape's color: bright and distinct, like painted wooden toys.
const Map<ToyShape, Color> kShapeColors = {
  ToyShape.circle: Color(0xFFF2545B),
  ToyShape.square: Color(0xFF3D8FE0),
  ToyShape.triangle: Color(0xFFF7C531),
  ToyShape.star: Color(0xFFF28C38),
  ToyShape.heart: Color(0xFFF06BA8),
  ToyShape.hexagon: Color(0xFF4CC46A),
  ToyShape.oval: Color(0xFFA066E8),
  ToyShape.diamond: Color(0xFF2EB8A6),
};

/// [shape]'s outline in an [s]-sized box.
Path shapePath(ToyShape shape, double s) {
  Path poly(List<(double, double)> pts) {
    final p = Path()..moveTo(pts.first.$1 * s, pts.first.$2 * s);
    for (final (x, y) in pts.skip(1)) {
      p.lineTo(x * s, y * s);
    }
    return p..close();
  }

  List<(double, double)> ring(int n, double r, {double r2 = 0, double cy = 0.5, double start = -math.pi / 2}) => [
        for (var i = 0; i < n * (r2 > 0 ? 2 : 1); i++)
          if (r2 > 0)
            (0.5 + (i.isEven ? r : r2) * math.cos(start + i * math.pi / n), cy + (i.isEven ? r : r2) * math.sin(start + i * math.pi / n))
          else
            (0.5 + r * math.cos(start + i * 2 * math.pi / n), cy + r * math.sin(start + i * 2 * math.pi / n)),
      ];

  return switch (shape) {
    ToyShape.circle => Path()..addOval(Rect.fromLTWH(0.06 * s, 0.06 * s, 0.88 * s, 0.88 * s)),
    ToyShape.square => Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0.1 * s, 0.1 * s, 0.8 * s, 0.8 * s), Radius.circular(0.08 * s))),
    ToyShape.triangle => poly(const [(0.5, 0.08), (0.95, 0.88), (0.05, 0.88)]),
    ToyShape.star => poly(ring(5, 0.48, r2: 0.2, cy: 0.53)),
    ToyShape.heart => Path()
      ..moveTo(0.5 * s, 0.9 * s)
      ..cubicTo(0.1 * s, 0.64 * s, 0.0, 0.38 * s, 0.18 * s, 0.2 * s)
      ..cubicTo(0.33 * s, 0.06 * s, 0.47 * s, 0.12 * s, 0.5 * s, 0.27 * s)
      ..cubicTo(0.53 * s, 0.12 * s, 0.67 * s, 0.06 * s, 0.82 * s, 0.2 * s)
      ..cubicTo(s, 0.38 * s, 0.9 * s, 0.64 * s, 0.5 * s, 0.9 * s)
      ..close(),
    ToyShape.hexagon => poly(ring(6, 0.46)),
    ToyShape.oval => Path()..addOval(Rect.fromLTWH(0.03 * s, 0.22 * s, 0.94 * s, 0.56 * s)),
    ToyShape.diamond => poly(const [(0.5, 0.03), (0.84, 0.5), (0.5, 0.97), (0.16, 0.5)]),
  };
}

/// Shape Sorter (SPEC FR-TOY-02, Appendix B: shapes and spatial sense).
/// Painted shapes wait in a tray under a wooden board; she drags each into
/// its hole, where it snaps in. A wrong hole bounces it gently back. Tapping
/// a shape and then a hole works too. At the top level the holes are
/// turned, so a shape has to be recognized rather than matched.
class ShapeGame extends StatefulWidget {
  const ShapeGame(this.c, {super.key});
  final GameController c;

  @override
  State<ShapeGame> createState() => ShapeGameState();
}

@visibleForTesting
class ShapeGameState extends State<ShapeGame> {
  final _area = GlobalKey();
  late ShapeRound _round;
  List<ToyShape> _tray = const [];
  Map<ToyShape, double> _angles = const {};
  final _placed = <ToyShape>{};
  final _bounces = <ToyShape, int>{};
  int _slips = 0, _deal = 0;
  ToyShape? _dragging, _selected;

  /// The dragged shape's center, and where the finger holds it.
  Offset _dragAt = Offset.zero, _grip = Offset.zero;
  Timer? _next;
  _Layout? _layout;

  @visibleForTesting
  List<ToyShape> get debugShapes => _round.shapes;

  @visibleForTesting
  bool get debugRotated => _round.rotated;

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  @override
  void dispose() {
    _next?.cancel();
    super.dispose();
  }

  void _newRound() {
    final rng = widget.c.random;
    _round = shapeRound(widget.c.level, rng);
    _tray = [..._round.shapes]..shuffle(rng);
    // Turned holes lean 15–35° either way; a circle looks the same anyway.
    _angles = {
      for (final s in _round.shapes)
        s: !_round.rotated || s == ToyShape.circle ? 0 : (rng.nextBool() ? 1 : -1) * (15 + rng.nextInt(21)) * math.pi / 180,
    };
    _placed.clear();
    _slips = 0;
    _deal++;
    _dragging = _selected = null;
    if (mounted) setState(() {});
  }

  /// Puts [shape] down at [at] (its center): in its hole if it's close,
  /// back in the tray if not. A different hole counts as a slip.
  void _drop(ToyShape shape, Offset at) {
    final l = _layout;
    if (l == null) return;
    ToyShape? near;
    var best = double.infinity;
    for (final (i, s) in _round.shapes.indexed) {
      if (_placed.contains(s)) continue;
      final d = (l.holes[i] - at).distance;
      if (d < best) (best, near) = (d, s);
    }
    if (near != null && best <= l.size * 0.62) {
      _fit(shape, near);
    } else {
      setState(() {});
    }
  }

  /// Tries [shape] in [hole]'s hole.
  void _fit(ToyShape shape, ToyShape hole) {
    final c = widget.c;
    if (shape != hole) {
      _slips++;
      c.sound(Sfx.boing, volume: 0.7);
      setState(() {
        _bounces[shape] = (_bounces[shape] ?? 0) + 1;
        _selected = null;
      });
      return;
    }
    c.sound(Sfx.snap);
    setState(() {
      _placed.add(shape);
      _selected = null;
    });
    if (_placed.length == _round.shapes.length) {
      unawaited(c.finishRound(shapeResult(_round.shapes.length, _slips), emoji: '🔺'));
      _next = Timer(const Duration(milliseconds: 2600), _newRound);
    }
  }

  void _tapPiece(ToyShape s) {
    if (_placed.contains(s)) return;
    widget.c.sound(Sfx.tap, volume: 0.6);
    setState(() => _selected = _selected == s ? null : s);
  }

  void _tapHole(ToyShape hole) {
    if (_placed.contains(hole)) return;
    final s = _selected;
    if (s == null) {
      // A hint, not a move: the shape that fits gives a little hop.
      setState(() => _bounces[hole] = (_bounces[hole] ?? 0) + 1);
      return;
    }
    _fit(s, hole);
  }

  Offset _local(Offset global) => (_area.currentContext!.findRenderObject()! as RenderBox).globalToLocal(global);

  void _dragStart(ToyShape s, DragStartDetails d, Offset center) {
    final p = _local(d.globalPosition);
    setState(() {
      _dragging = s;
      _selected = null;
      _grip = center - p;
      _dragAt = center;
    });
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (_dragging == null) return;
    setState(() => _dragAt = _local(d.globalPosition) + _grip);
  }

  void _dragEnd() {
    final s = _dragging;
    if (s == null) return;
    _dragging = null;
    _drop(s, _dragAt);
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE6F6EE), Color(0xFFFDF1DC)])),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(t.space.lg, 96 * t.scale, t.space.lg, t.space.lg),
          child: LayoutBuilder(
            key: _area,
            builder: (context, box) {
              final l = _layout = _Layout.of(box.biggest, _round.shapes.length);
              final hint = _slips >= 2 ? (_dragging ?? _selected) : null;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fromRect(
                    rect: l.board,
                    child: RepaintBoundary(child: CustomPaint(painter: _BoardPainter(board: l.board, holes: l.holes, shapes: _round.shapes, angles: _angles, size: l.size))),
                  ),
                  for (final (i, s) in _round.shapes.indexed) ...[
                    if (hint == s) Positioned(left: l.holes[i].dx - l.size * 0.75, top: l.holes[i].dy - l.size * 0.75, child: _Glow(size: l.size * 1.5)),
                    Positioned(
                      left: l.holes[i].dx - l.size * 0.55,
                      top: l.holes[i].dy - l.size * 0.55,
                      child: tid(
                        'shapes.hole.${s.name}',
                        Semantics(
                          button: true,
                          label: '${s.name} hole',
                          onTap: () => _tapHole(s),
                          excludeSemantics: true,
                          child: GestureDetector(excludeFromSemantics: true, behavior: HitTestBehavior.opaque, onTap: () => _tapHole(s), child: SizedBox.square(dimension: l.size * 1.1)),
                        ),
                      ),
                    ),
                  ],
                  for (final (i, s) in _tray.indexed) _piece(s, l, l.tray[i]),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _piece(ToyShape s, _Layout l, Offset home) {
    final placed = _placed.contains(s);
    final dragging = _dragging == s;
    final center = placed ? l.holes[_round.shapes.indexOf(s)] : (dragging ? _dragAt : home);
    final lifted = dragging || _selected == s;
    return AnimatedPositioned(
      key: ValueKey('$_deal.${s.name}'),
      duration: dragging ? Duration.zero : const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      left: center.dx - l.size / 2,
      top: center.dy - l.size / 2,
      child: IgnorePointer(
        ignoring: placed,
        child: tid(
          'shapes.piece.${s.name}',
          Semantics(
            button: true,
            label: s.name,
            onTap: () => _tapPiece(s),
            excludeSemantics: true,
            child: GestureDetector(
              excludeFromSemantics: true,
              dragStartBehavior: DragStartBehavior.down,
              onTap: () => _tapPiece(s),
              onPanStart: (d) => _dragStart(s, d, center),
              onPanUpdate: _dragUpdate,
              onPanEnd: (_) => _dragEnd(),
              onPanCancel: _dragEnd,
              child: AnimatedRotation(
                turns: placed ? _angles[s]! / (2 * math.pi) : 0,
                duration: const Duration(milliseconds: 380),
                child: AnimatedScale(
                  scale: lifted ? 1.12 : (placed ? 0.96 : 1),
                  duration: const Duration(milliseconds: 160),
                  child: _Hop(
                    hops: _bounces[s] ?? 0,
                    child: RepaintBoundary(child: CustomPaint(size: Size.square(l.size), painter: _PiecePainter(s, lifted: lifted))),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where everything sits for a playfield [area] and [n] shapes: the board
/// on top, the tray below, holes and shapes in one or two rows.
class _Layout {
  _Layout(this.board, this.holes, this.tray, this.size);

  factory _Layout.of(Size area, int n) {
    final rows = n <= 4 ? 1 : 2;
    final cols = (n / rows).ceil();
    final board = Rect.fromLTWH(area.width * 0.05, 0, area.width * 0.9, area.height * 0.54);
    final trayBox = Rect.fromLTWH(area.width * 0.02, area.height * 0.6, area.width * 0.96, area.height * 0.4);
    final size = math.min(
      math.min(board.width / cols, board.height / rows) * 0.66,
      math.min(trayBox.width / cols, trayBox.height / rows) * 0.74,
    );
    List<Offset> grid(Rect r) => [
          for (var i = 0; i < n; i++)
            Offset(
              r.left + r.width * ((i % cols) + 0.5 + (i ~/ cols == rows - 1 ? (cols * rows - n) / 2 : 0)) / cols,
              r.top + r.height * ((i ~/ cols) + 0.5) / rows,
            ),
        ];
    return _Layout(board, grid(board), grid(trayBox), size);
  }

  final Rect board;
  final List<Offset> holes, tray;

  /// A shape's box.
  final double size;
}

/// A painted wooden shape, for other games (Odd One Out): [color] or its own.
class ToyShapeView extends StatelessWidget {
  const ToyShapeView(this.shape, {super.key, required this.size, this.color});
  final ToyShape shape;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: CustomPaint(size: Size.square(size), painter: _PiecePainter(shape, lifted: false, color: color)));
}

/// A painted wooden shape: a soft top light and a darker rim.
class _PiecePainter extends CustomPainter {
  const _PiecePainter(this.shape, {required this.lifted, this.color});
  final ToyShape shape;
  final bool lifted;
  final Color? color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final color = this.color ?? kShapeColors[shape]!;
    final path = shapePath(shape, s);
    // A shadow under it: further when it's lifted.
    canvas.drawPath(path.shift(Offset(0, s * (lifted ? 0.09 : 0.04))), Paint()..color = const Color(0x33000000));
    final bounds = Offset.zero & size;
    canvas.drawPath(
      path,
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(color, Colors.white, 0.3)!, color]).createShader(bounds),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.035
        ..strokeJoin = StrokeJoin.round
        ..color = Color.lerp(color, Colors.black, 0.25)!,
    );
  }

  @override
  bool shouldRepaint(_PiecePainter old) => old.shape != shape || old.lifted != lifted || old.color != color;
}

/// The wooden board and its holes, each a dark cut with a shadow along its
/// upper edge.
class _BoardPainter extends CustomPainter {
  const _BoardPainter({required this.board, required this.holes, required this.shapes, required this.angles, required this.size});
  final Rect board;
  final List<Offset> holes;
  final List<ToyShape> shapes;
  final Map<ToyShape, double> angles;
  final double size;

  @override
  void paint(Canvas canvas, Size area) {
    final r = Offset.zero & area;
    final wood = RRect.fromRectAndRadius(r, Radius.circular(area.shortestSide * 0.08));
    canvas.drawRRect(wood.shift(const Offset(0, 8)), Paint()..color = const Color(0x22000000));
    canvas.drawRRect(wood, Paint()..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFE7B57A), Color(0xFFC98D52)]).createShader(r));
    final grain = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, area.shortestSide * 0.006)
      ..color = const Color(0x1F7A4A1E);
    for (var i = 1; i < 7; i++) {
      final y = area.height * i / 7;
      canvas.drawPath(
        Path()
          ..moveTo(area.width * 0.03, y)
          ..cubicTo(area.width * 0.3, y - area.height * 0.04, area.width * 0.6, y + area.height * 0.04, area.width * 0.97, y),
        grain,
      );
    }
    final hole = size * 1.1;
    for (final (i, s) in shapes.indexed) {
      final c = holes[i] - board.topLeft;
      canvas
        ..save()
        ..translate(c.dx, c.dy)
        ..rotate(angles[s] ?? 0)
        ..translate(-hole / 2, -hole / 2);
      final path = shapePath(s, hole);
      canvas
        ..drawPath(path, Paint()..color = const Color(0xFF3A2312))
        ..clipPath(path)
        // The cut's lit lower part: the dark band left above it reads as depth.
        ..drawPath(path.shift(Offset(0, hole * 0.07)), Paint()..color = const Color(0xFF5E3B20))
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) => old.board != board || old.size != size || old.shapes != shapes || old.angles != angles;
}

/// A little hop each time [hops] grows: a wrong hole, or a hint.
class _Hop extends StatelessWidget {
  const _Hop({required this.hops, required this.child});
  final int hops;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        key: ValueKey(hops),
        tween: Tween(begin: hops == 0 ? 0 : 1, end: 0),
        duration: const Duration(milliseconds: 600),
        builder: (context, k, child) => Transform.translate(offset: Offset(math.sin(k * math.pi * 4) * 10 * k, -math.sin(k * math.pi) * 18), child: child),
        child: child,
      );
}

/// A soft pulsing ring around the hole that fits, after a couple of slips.
class _Glow extends StatefulWidget {
  const _Glow({required this.size});
  final double size;

  @override
  State<_Glow> createState() => _GlowState();
}

class _GlowState extends State<_Glow> with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final Ticker _ticker = createTicker(_tick);
  int _frames = 0;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _pulse.dispose();
    super.dispose();
  }

  // The hint ring breathes forever: on the slowest displays it does so at
  // the tier's ambient fps, not every vsync (SPEC §12.3).
  void _tick(Duration elapsed) {
    if (DTheme.of(context).policy.ambientFps < 60 && (_frames++).isOdd) return;
    final cycle = _pulse.duration!.inMilliseconds * 2; // forward, then reverse
    final p = (elapsed.inMilliseconds % cycle) / cycle;
    _pulse.value = p < 0.5 ? p * 2 : 2 - p * 2;
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.1).animate(_pulse),
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0xAAFFF2A8), Color(0x00FFF2A8)])),
            ),
          ),
        ),
      );
}
