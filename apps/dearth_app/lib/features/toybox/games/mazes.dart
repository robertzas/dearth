import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';

/// Finger Mazes (SPEC FR-TOY-03, Appendix B: planning and motor control).
/// Her buddy waits in one corner and home is in the other; she drags the
/// buddy through the corridors, and it follows only where the maze is open
/// (a wall gives a soft boing). Wide paths first, then turns, branches and
/// dead ends. A tap on a neighbouring square steps there too, if no hedge
/// is in the way.
class MazesGame extends StatefulWidget {
  const MazesGame(this.c, {super.key});
  final GameController c;

  @override
  State<MazesGame> createState() => MazesGameState();
}

@visibleForTesting
class MazesGameState extends State<MazesGame> {
  final _area = GlobalKey();
  late MazeRound _maze;
  late int _at;
  final _trail = <int>[];
  int _bumps = 0, _deal = 0, _lastBump = -1;
  bool _dragging = false, _home = false;
  Timer? _next;
  _Geometry? _geo;

  @visibleForTesting
  MazeRound get debugMaze => _maze;

  @visibleForTesting
  int get debugAt => _at;

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
    _maze = mazeRound(widget.c.level, widget.c.random);
    _at = _maze.start;
    _trail
      ..clear()
      ..add(_at);
    _bumps = 0;
    _home = false;
    _deal++;
    if (mounted) setState(() {});
  }

  /// A tap on a square next to the buddy: one step if the way is open, a
  /// soft boing if a hedge is in the way. (Only a drag finds its way around.)
  void _tapCell(int cell) {
    if (_home || !_maze.neighbours(_at).contains(cell)) return;
    if (_maze.connected(_at, cell)) {
      _walk([_at, cell]);
    } else {
      _bump(cell);
    }
  }

  /// Follows a dragging finger toward [cell]: along open passages, at most
  /// three squares at a time (a quick finger), never through a wall.
  void _toward(int cell) {
    if (_home || cell == _at) return;
    // The way from here to [cell] through open passages, if it's close.
    final route = _route(_at, cell);
    if (route == null) {
      if (_maze.neighbours(_at).contains(cell)) _bump(cell);
      return;
    }
    _walk(route);
  }

  void _bump(int cell) {
    if (_lastBump == cell) return;
    _bumps++;
    _lastBump = cell;
    widget.c.sound(Sfx.boing, volume: 0.45);
  }

  void _walk(List<int> route) {
    final cell = route.last;
    _lastBump = -1;
    widget.c.sound(Sfx.tap, volume: 0.35, rate: _maze.path(_at).contains(cell) ? 1.2 : 0.9);
    setState(() {
      _at = cell;
      _trail.addAll(route.skip(1));
    });
    if (_at == _maze.home) {
      _home = true;
      unawaited(widget.c.finishRound(resultFor(_bumps, allowed: _maze.cols), emoji: '🏠'));
      _next = Timer(const Duration(milliseconds: 2800), _newRound);
    }
  }

  /// Cells from [from] to [to] within three steps through open passages.
  List<int>? _route(int from, int to) {
    final prev = <int, int>{from: from};
    var frontier = [from];
    for (var depth = 0; depth < 3 && frontier.isNotEmpty; depth++) {
      final next = <int>[];
      for (final c in frontier) {
        for (final n in _maze.neighbours(c)) {
          if (_maze.connected(c, n) && !prev.containsKey(n)) {
            prev[n] = c;
            next.add(n);
          }
        }
      }
      if (prev.containsKey(to)) break;
      frontier = next;
    }
    if (!prev.containsKey(to)) return null;
    final out = [to];
    while (out.last != from) {
      out.add(prev[out.last]!);
    }
    return out.reversed.toList();
  }

  int? _cellAt(Offset global) {
    final g = _geo;
    final box = _area.currentContext?.findRenderObject() as RenderBox?;
    if (g == null || box == null) return null;
    final p = box.globalToLocal(global) - g.origin;
    final c = (p.dx / g.cell).floor(), r = (p.dy / g.cell).floor();
    if (c < 0 || r < 0 || c >= _maze.cols || r >= _maze.rows) return null;
    return r * _maze.cols + c;
  }

  @override
  Widget build(BuildContext context) {
    final buddy = buddyEmoji(widget.c.kid.buddy);
    final m = _maze;
    return Backdrop(
      top: const Color(0xFFE6F7EA),
      bottom: const Color(0xFFFFF7DC),
      child: PlayArea(
        child: LayoutBuilder(
          key: _area,
          builder: (context, box) {
            final cell = math.min(box.maxWidth / m.cols, box.maxHeight / m.rows);
            final origin = Offset((box.maxWidth - cell * m.cols) / 2, (box.maxHeight - cell * m.rows) / 2);
            final g = _geo = _Geometry(origin, cell);
            Offset centerOf(int i) => origin + Offset((i % m.cols + 0.5) * cell, (i ~/ m.cols + 0.5) * cell);
            String ways(int i) => [
                  if (i >= m.cols && m.connected(i, i - m.cols)) 'up',
                  if (i < (m.rows - 1) * m.cols && m.connected(i, i + m.cols)) 'down',
                  if (i % m.cols > 0 && m.connected(i, i - 1)) 'left',
                  if (i % m.cols < m.cols - 1 && m.connected(i, i + 1)) 'right',
                ].join(' ');
            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) {
                final c = _cellAt(e.position);
                _dragging = c == _at;
                // A tap on a neighbour steps there (or bumps a hedge).
                if (c != null && !_dragging) _tapCell(c);
              },
              onPointerMove: (e) {
                if (!_dragging) return;
                final c = _cellAt(e.position);
                if (c != null) _toward(c);
              },
              onPointerUp: (_) => _dragging = false,
              onPointerCancel: (_) => _dragging = false,
              child: Stack(
                key: ValueKey(_deal),
                children: [
                  Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _MazePainter(m, g, _trail.length, _trail)))),
                  for (var i = 0; i < m.cols * m.rows; i++)
                    Positioned(
                      left: centerOf(i).dx - cell / 2,
                      top: centerOf(i).dy - cell / 2,
                      width: cell,
                      height: cell,
                      child: tid(
                        'mazes.cell.$i',
                        Semantics(
                          button: true,
                          label: 'Square ${i + 1}: ${ways(i)}${i == _at ? ', buddy here' : ''}${i == m.home ? ', home' : ''}',
                          onTap: () => _tapCell(i),
                          excludeSemantics: true,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  Positioned(left: centerOf(m.home).dx - cell * 0.32, top: centerOf(m.home).dy - cell * 0.32, child: IgnorePointer(child: DEmoji('🏠', size: cell * 0.64))),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 160),
                    left: centerOf(_at).dx - cell * 0.36,
                    top: centerOf(_at).dy - cell * 0.36,
                    child: IgnorePointer(
                      child: tid('mazes.buddy', Semantics(label: 'Buddy', excludeSemantics: true, child: Hop(count: _home ? 1 : 0, child: DEmoji(buddy, size: cell * 0.72)))),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Geometry {
  const _Geometry(this.origin, this.cell);
  final Offset origin;
  final double cell;
}

/// The maze: soft floor, the trail walked so far, and round-ended hedges.
/// Repaints only as the trail grows.
class _MazePainter extends CustomPainter {
  const _MazePainter(this.m, this.g, this.steps, this.trail);
  final MazeRound m;
  final _Geometry g;
  final int steps;
  final List<int> trail;

  @override
  void paint(Canvas canvas, Size size) {
    final c = g.cell, o = g.origin;
    final floor = Rect.fromLTWH(o.dx, o.dy, c * m.cols, c * m.rows);
    canvas.drawRRect(RRect.fromRectAndRadius(floor.inflate(c * 0.06), Radius.circular(c * 0.2)), Paint()..color = const Color(0xFFFFFBF0));
    Offset at(int i) => o + Offset((i % m.cols + 0.5) * c, (i ~/ m.cols + 0.5) * c);
    if (trail.length > 1) {
      final path = Path()..moveTo(at(trail.first).dx, at(trail.first).dy);
      for (final i in trail.skip(1)) {
        path.lineTo(at(i).dx, at(i).dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = c * 0.22
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0x55FFB74D),
      );
    }
    final hedge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(6, c * 0.12)
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF4E9A5E);
    // Outer hedge, then a wall wherever two neighbours aren't connected.
    canvas.drawRRect(RRect.fromRectAndRadius(floor, Radius.circular(c * 0.08)), hedge);
    for (var i = 0; i < m.cols * m.rows; i++) {
      final x = o.dx + (i % m.cols) * c, y = o.dy + (i ~/ m.cols) * c;
      if (i % m.cols < m.cols - 1 && !m.connected(i, i + 1)) canvas.drawLine(Offset(x + c, y), Offset(x + c, y + c), hedge);
      if (i < (m.rows - 1) * m.cols && !m.connected(i, i + m.cols)) canvas.drawLine(Offset(x, y + c), Offset(x + c, y + c), hedge);
    }
  }

  @override
  bool shouldRepaint(_MazePainter old) => old.steps != steps || old.m != m || old.g.cell != g.cell || old.g.origin != g.origin;
}
