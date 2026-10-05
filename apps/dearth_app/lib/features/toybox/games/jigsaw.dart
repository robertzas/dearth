import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/providers.dart';
import '../../../core/sound.dart';
import '../../../core/sync/hub_api.dart';
import '../../photos/art_pack.dart';
import '../../photos/photos_data.dart';
import '../game_host.dart';

/// One edge of a piece, from [from] along [dir] for [len], with a tab that
/// sticks out (+1), a hole that goes in (−1) or nothing (0). [m] sizes the
/// tab: the cell's shorter side. The tab is symmetric, so two neighbors
/// trace the same curve from opposite ends and interlock exactly.
void _edge(Path p, Offset from, Offset dir, double len, int tab, double m) {
  if (tab == 0) {
    p.lineTo(from.dx + dir.dx * len, from.dy + dir.dy * len);
    return;
  }
  // Outward is to the left of travel on a clockwise outline (y down).
  final out = Offset(dir.dy, -dir.dx) * tab.toDouble();
  Offset at(double u, double v) => from + dir * (len / 2 + u * m) + out * (v * m);
  final a = at(-0.12, 0);
  p.lineTo(a.dx, a.dy);
  void cubic(Offset c1, Offset c2, Offset to) => p.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, to.dx, to.dy);
  cubic(at(-0.08, 0.06), at(-0.24, 0.12), at(-0.16, 0.2));
  cubic(at(-0.1, 0.32), at(0.1, 0.32), at(0.16, 0.2));
  cubic(at(0.24, 0.12), at(0.08, 0.06), at(0.12, 0));
  p.lineTo(from.dx + dir.dx * len, from.dy + dir.dy * len);
}

/// The outline of piece ([r], [c]) in its own box: the cell sits at
/// ([pad], [pad]) and tabs reach into the padding.
@visibleForTesting
Path jigsawPiecePath(int r, int c, {required int rows, required int cols, required ({List<List<int>> right, List<List<int>> down}) tabs, required Size cell, required double pad}) {
  final top = r == 0 ? 0 : -tabs.down[r - 1][c];
  final bottom = r == rows - 1 ? 0 : tabs.down[r][c];
  final left = c == 0 ? 0 : -tabs.right[r][c - 1];
  final right = c == cols - 1 ? 0 : tabs.right[r][c];
  final m = math.min(cell.width, cell.height);
  final w = cell.width, h = cell.height;
  final p = Path()..moveTo(pad, pad);
  _edge(p, Offset(pad, pad), const Offset(1, 0), w, top, m);
  _edge(p, Offset(pad + w, pad), const Offset(0, 1), h, right, m);
  _edge(p, Offset(pad + w, pad + h), const Offset(-1, 0), w, bottom, m);
  _edge(p, Offset(pad, pad + h), const Offset(0, -1), h, left, m);
  return p..close();
}

/// Jigsaw (SPEC FR-TOY-02, Appendix B: spatial reasoning). A family photo
/// from the photo frame, or a painted scene when there are none, cut into
/// 2 → 24 tabbed pieces scattered around the board. A piece dropped near its
/// spot snaps in; dropped on another piece's spot, it hops back; anywhere
/// else, it stays where she put it. The first levels show the picture
/// faintly on the board.
class JigsawGame extends ConsumerStatefulWidget {
  const JigsawGame(this.c, {super.key});
  final GameController c;

  @override
  ConsumerState<JigsawGame> createState() => JigsawGameState();
}

@visibleForTesting
class JigsawGameState extends ConsumerState<JigsawGame> {
  final _area = GlobalKey();
  ui.Image? _image;
  bool _photo = false;
  int _rows = 1, _cols = 2, _deal = 0, _slips = 0, _ticket = 0;
  bool _wide = true, _done = false;
  ({List<List<int>> right, List<List<int>> down}) _tabs = (right: const [], down: const []);

  /// Each piece's cell in its waiting area's grid, and a little jitter so
  /// they look tossed rather than lined up.
  List<int> _waitSlot = const [];
  List<Offset> _jitter = const [];
  final _placed = <int>{};
  final _moved = <int, Offset>{};
  final _hops = <int, int>{};
  List<int> _order = const [];
  int? _dragging;
  Offset _dragAt = Offset.zero, _grip = Offset.zero;
  Timer? _next;
  _Layout? _layout;

  /// The size the picture was made for (a new round makes a new one).
  Size? _madeFor;

  /// Piece outlines for this deal at this cell size: reused, so moving one
  /// piece repaints only that one.
  List<Path> _paths = const [];
  Size? _pathsFor;

  @visibleForTesting
  ({int rows, int cols}) get debugGrid => (rows: _rows, cols: _cols);

  @visibleForTesting
  bool get debugReady => _image != null;

  @visibleForTesting
  bool get debugPhoto => _photo;

  @override
  void dispose() {
    _next?.cancel();
    final old = _image;
    _image = null;
    old?.dispose();
    super.dispose();
  }

  /// Deals a new puzzle for a board shaped [wide] or tall.
  void _dealPuzzle(bool wide) {
    final rng = widget.c.random;
    final grid = jigsawGrid(widget.c.level, landscape: wide);
    _wide = wide;
    _rows = grid.rows;
    _cols = grid.cols;
    _tabs = jigsawTabs(_rows, _cols, rng);
    final n = _rows * _cols;
    // Pieces alternate sides; each side's cells are dealt out at random.
    final left = [for (var k = 0; k < (n + 1) ~/ 2; k++) k]..shuffle(rng);
    final right = [for (var k = 0; k < n ~/ 2; k++) k]..shuffle(rng);
    _waitSlot = [for (var i = 0; i < n; i++) i.isEven ? left[i ~/ 2] : right[i ~/ 2]];
    _jitter = [for (var i = 0; i < n; i++) Offset(rng.nextDouble() * 2 - 1, rng.nextDouble() * 2 - 1)];
    _order = [for (var i = 0; i < n; i++) i]..shuffle(rng);
    _placed.clear();
    _moved.clear();
    _slips = 0;
    _done = false;
    _deal++;
    _madeFor = null;
    _pathsFor = null;
    // The next picture is on its way; the last one goes once it's off screen.
    final old = _image;
    _image = null;
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  Path _pathOf(int i, _Layout l) {
    if (_pathsFor != l.cell) {
      _pathsFor = l.cell;
      _paths = [for (var j = 0; j < _rows * _cols; j++) jigsawPiecePath(j ~/ _cols, j % _cols, rows: _rows, cols: _cols, tabs: _tabs, cell: l.cell, pad: l.pad)];
    }
    return _paths[i];
  }

  void _newRound() {
    if (!mounted) return;
    setState(() => _dealPuzzle(_wide));
  }

  /// Makes the picture for a board of [px] pixels: a family photo when the
  /// photo frame has some, else a painted scene.
  Future<void> _makePicture(Size px) async {
    final ticket = ++_ticket;
    final api = ref.read(hubApiProvider);
    final pool = ref.read(screensaverPoolProvider) ?? const [];
    final photos = [for (final p in pool) if (blobSha(p.blobRef) != null) p];
    ui.Image? image;
    var photo = false;
    if (api != null && photos.isNotEmpty) {
      final p = photos[widget.c.random.nextInt(photos.length)];
      image = await _network(api.blobUrl(blobSha(p.blobRef)!, width: px.width.round(), height: px.height.round(), cover: true).toString());
      photo = image != null;
    }
    image ??= _art(px, widget.c.random.nextInt(kArtCount));
    if (!mounted || ticket != _ticket) {
      image.dispose();
      return;
    }
    final old = _image;
    setState(() {
      _image = image;
      _photo = photo;
    });
    // The old picture may still be on screen until this frame is drawn.
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  static ui.Image _art(Size px, int index) {
    final rec = ui.PictureRecorder();
    paintArt(Canvas(rec), px, index);
    final picture = rec.endRecording();
    final image = picture.toImageSync(px.width.round(), px.height.round());
    picture.dispose();
    return image;
  }

  static Future<ui.Image?> _network(String url) {
    final done = Completer<ui.Image?>();
    final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!done.isCompleted) done.complete(info.image.clone());
        info.dispose();
        stream.removeListener(listener);
      },
      onError: (_, _) {
        if (!done.isCompleted) done.complete(null);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return done.future.timeout(const Duration(seconds: 12), onTimeout: () => null);
  }

  Offset _home(int i, _Layout l) => _moved[i] ?? l.waiting(i, _waitSlot[i], _jitter[i]);

  Offset _centerOf(int i, _Layout l) {
    if (_placed.contains(i)) return l.target(i);
    if (_dragging == i) return _dragAt;
    return _home(i, l);
  }

  void _toTop(int i) => _order = [..._order.where((j) => j != i), i];

  Offset _local(Offset global) => (_area.currentContext!.findRenderObject()! as RenderBox).globalToLocal(global);

  void _dragStart(int i, DragStartDetails d) {
    final l = _layout;
    if (l == null || _placed.contains(i) || _done) return;
    final center = _centerOf(i, l);
    setState(() {
      _dragging = i;
      _grip = center - _local(d.globalPosition);
      _dragAt = center;
      _toTop(i);
    });
    widget.c.sound(Sfx.tap, volume: 0.5);
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (_dragging == null) return;
    setState(() => _dragAt = _local(d.globalPosition) + _grip);
  }

  void _dragEnd() {
    final i = _dragging, l = _layout;
    if (i == null || l == null) return;
    _dragging = null;
    if ((_dragAt - l.target(i)).distance <= l.snap) {
      _place(i);
      return;
    }
    for (var j = 0; j < _rows * _cols; j++) {
      if (j == i || _placed.contains(j)) continue;
      if ((_dragAt - l.target(j)).distance <= l.snap * 0.8) {
        // Another piece's spot: it hops back to wait.
        _slips++;
        widget.c.sound(Sfx.boing, volume: 0.6);
        setState(() {
          _moved.remove(i);
          _hops[i] = (_hops[i] ?? 0) + 1;
        });
        return;
      }
    }
    setState(() => _moved[i] = l.clamp(_dragAt));
  }

  /// Puts [i] in its spot (a snap, or a screen reader's tap).
  void _place(int i) {
    if (_placed.contains(i) || _done) return;
    widget.c.sound(Sfx.snap);
    setState(() {
      _placed.add(i);
      _moved.remove(i);
    });
    if (_placed.length == _rows * _cols) {
      _done = true;
      unawaited(widget.c.finishRound(jigsawResult(_rows * _cols, _slips), emoji: '🧩'));
      _next = Timer(const Duration(milliseconds: 3400), _newRound);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    // Watched, so the photo pool is ready when a picture is made.
    final pool = ref.watch(screensaverPoolProvider);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ColoredBox(
      color: const Color(0xFFEFE6D8),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(t.space.md, 96 * t.scale, t.space.md, t.space.md),
          child: LayoutBuilder(
            key: _area,
            builder: (context, box) {
              final wide = box.maxWidth >= box.maxHeight;
              if (_waitSlot.isEmpty || wide != _wide) _dealPuzzle(wide);
              final l = _layout = _Layout.of(box.biggest, rows: _rows, cols: _cols, wide: wide);
              final px = Size(math.min(l.board.width * dpr, 1600), math.min(l.board.height * dpr, 1600));
              if (_madeFor == null && pool != null) {
                _madeFor = px;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) unawaited(_makePicture(px));
                });
              }
              final image = _image;
              final n = _rows * _cols;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fromRect(
                    rect: l.board,
                    child: tid(
                      'jigsaw.board',
                      Semantics(
                        label: 'Puzzle: ${_placed.length} of $n in place',
                        excludeSemantics: true,
                        child: RepaintBoundary(
                          child: CustomPaint(painter: _BoardPainter(image: image, layout: l, tabs: _tabs, rows: _rows, cols: _cols, ghost: widget.c.level <= 3, done: _done)),
                        ),
                      ),
                    ),
                  ),
                  // Each spot, for screen readers and tests (a drop target).
                  for (var i = 0; i < n; i++)
                    Positioned.fromRect(
                      rect: Rect.fromCenter(center: l.target(i), width: l.cell.width * 0.5, height: l.cell.height * 0.5),
                      child: tid('jigsaw.slot.${i ~/ _cols}.${i % _cols}', Semantics(label: 'Spot', excludeSemantics: true, child: const SizedBox.expand())),
                    ),
                  if (image != null && !_done)
                    for (final i in [..._placed, ..._order.where((j) => !_placed.contains(j))]) _piece(i, l, image),
                  if (image == null) Center(child: DEmoji('🧩', size: 96 * t.scale)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _piece(int i, _Layout l, ui.Image image) {
    final r = i ~/ _cols, c = i % _cols;
    final center = _centerOf(i, l);
    final placed = _placed.contains(i), dragging = _dragging == i;
    final box = l.pieceBox;
    final path = _pathOf(i, l);
    return AnimatedPositioned(
      key: ValueKey('$_deal.$i'),
      duration: dragging ? Duration.zero : const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      left: center.dx - box.width / 2,
      top: center.dy - box.height / 2,
      width: box.width,
      height: box.height,
      child: IgnorePointer(
        ignoring: placed,
        // Scaled outside the test id, so its node shrinks with the piece
        // (screen readers and tests find it where it's drawn).
        child: AnimatedScale(
          // Waiting pieces are smaller, so they fit beside the board;
          // picked up or on the board, they're full size.
          scale: dragging ? 1.04 : (placed || l.board.contains(center) ? 1 : l.waitScale),
          duration: const Duration(milliseconds: 180),
          child: tid(
            'jigsaw.piece.$r.$c',
            Semantics(
              button: true,
              label: placed ? 'Piece in place' : 'Piece',
              onTap: () => _place(i),
              excludeSemantics: true,
              child: GestureDetector(
                excludeFromSemantics: true,
                dragStartBehavior: DragStartBehavior.down,
                onPanStart: (d) => _dragStart(i, d),
                onPanUpdate: _dragUpdate,
                onPanEnd: (_) => _dragEnd(),
                onPanCancel: _dragEnd,
                child: _Hop(
                  hops: _hops[i] ?? 0,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: box,
                      painter: _PiecePainter(image: image, path: path, origin: Offset(c * l.cell.width - l.pad, r * l.cell.height - l.pad), board: l.board.size, lifted: dragging, placed: placed),
                    ),
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

/// Where the board and the waiting pieces sit for a playfield [area].
class _Layout {
  _Layout(this.area, this.board, this.cols, this.rows, this.wide);

  factory _Layout.of(Size area, {required int rows, required int cols, required bool wide}) {
    final aspect = wide ? 4 / 3 : 3 / 4;
    final double w, h;
    if (wide) {
      h = math.min(area.height * 0.84, area.width * 0.56 / aspect);
      w = h * aspect;
    } else {
      w = math.min(area.width * 0.92, area.height * 0.52 * aspect);
      h = w / aspect;
    }
    return _Layout(area, Rect.fromCenter(center: area.center(Offset.zero), width: w, height: h), cols, rows, wide);
  }

  final Size area;
  final Rect board;
  final int cols, rows;
  final bool wide;

  Size get cell => Size(board.width / cols, board.height / rows);
  double get pad => math.min(cell.width, cell.height) * 0.3;
  Size get pieceBox => Size(cell.width + pad * 2, cell.height + pad * 2);

  /// How close counts as "in its spot".
  double get snap => math.min(cell.width, cell.height) * 0.32;

  /// The center of piece [i]'s spot on the board.
  Offset target(int i) => board.topLeft + Offset((i % cols + 0.5) * cell.width, (i ~/ cols + 0.5) * cell.height);

  List<Rect> get _zones => wide
      ? [Rect.fromLTRB(0, 0, board.left, area.height), Rect.fromLTRB(board.right, 0, area.width, area.height)]
      : [Rect.fromLTRB(0, 0, area.width, board.top), Rect.fromLTRB(0, board.bottom, area.width, area.height)];

  /// The waiting grid of a side holding [count] pieces: as square as it can be.
  static (int, int) _grid(Rect z, int count) {
    final across = math.sqrt(count * z.width / math.max(1, z.height)).round().clamp(1, math.max(1, count)).toInt();
    return (across, (count / across).ceil());
  }

  /// How small a waiting piece is drawn: small enough for its side's grid
  /// (with a little overlap), never tiny.
  double get waitScale {
    final z = _zones.first;
    final (across, down) = _grid(z, (rows * cols + 1) ~/ 2);
    final fit = math.min(z.width / across / pieceBox.width, z.height / down / pieceBox.height) * 1.15;
    return fit.clamp(0.5, 0.85);
  }

  /// Where piece [i] waits: beside the board (left or right) on a wide
  /// screen, above or below it on a tall one, in cell [slot] of a grid over
  /// that area (so no piece hides another's middle), nudged by [jitter].
  Offset waiting(int i, int slot, Offset jitter) {
    final z = _zones[i % 2];
    final n = rows * cols;
    final count = i.isEven ? (n + 1) ~/ 2 : n ~/ 2;
    final (across, down) = _grid(z, count);
    final cw = z.width / across, ch = z.height / down;
    final c = Offset(z.left + (slot % across + 0.5) * cw + jitter.dx * cw * 0.12, z.top + (slot ~/ across + 0.5) * ch + jitter.dy * ch * 0.12);
    // The whole (shrunken) piece on screen, when the side is big enough.
    final hw = math.min(pieceBox.width * waitScale / 2, z.width / 2), hh = math.min(pieceBox.height * waitScale / 2, z.height / 2);
    return Offset(c.dx.clamp(z.left + hw, z.right - hw), c.dy.clamp(z.top + hh, z.bottom - hh));
  }

  /// Keeps a dropped piece on the playfield, enough of it to grab.
  Offset clamp(Offset p) {
    final m = math.min(cell.width, cell.height) * 0.25;
    return Offset(p.dx.clamp(m, area.width - m), p.dy.clamp(m, area.height - m));
  }
}

/// The board: a paper backing, the picture faint (early levels) or whole
/// (when done), and the outline of every spot.
class _BoardPainter extends CustomPainter {
  const _BoardPainter({required this.image, required this.layout, required this.tabs, required this.rows, required this.cols, required this.ghost, required this.done});
  final ui.Image? image;
  final _Layout layout;
  final ({List<List<int>> right, List<List<int>> down}) tabs;
  final int rows, cols;
  final bool ghost, done;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas
      ..drawRRect(RRect.fromRectAndRadius(r.inflate(10), const Radius.circular(18)).shift(const Offset(0, 6)), Paint()..color = const Color(0x22000000))
      ..drawRRect(RRect.fromRectAndRadius(r.inflate(10), const Radius.circular(18)), Paint()..color = const Color(0xFFFFFCF6));
    final img = image;
    if (img != null && (ghost || done)) {
      canvas.drawImageRect(
        img,
        Offset.zero & Size(img.width.toDouble(), img.height.toDouble()),
        r,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromRGBO(0, 0, 0, done ? 1 : 0.22),
      );
    }
    if (done) return;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFCFC6B8);
    final cell = layout.cell, pad = layout.pad;
    for (var row = 0; row < rows; row++) {
      for (var c = 0; c < cols; c++) {
        canvas.drawPath(jigsawPiecePath(row, c, rows: rows, cols: cols, tabs: tabs, cell: cell, pad: pad).shift(Offset(c * cell.width - pad, row * cell.height - pad)), line);
      }
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) => old.image != image || old.done != done || old.ghost != ghost || old.layout.board != layout.board || old.tabs != tabs;
}

/// One piece: its part of the picture, clipped to its outline, with a lit
/// edge and a shadow that grows when it's picked up. It answers touches only
/// inside its outline, so overlapping pieces don't steal each other's.
class _PiecePainter extends CustomPainter {
  const _PiecePainter({required this.image, required this.path, required this.origin, required this.board, required this.lifted, required this.placed});
  final ui.Image image;
  final Path path;

  /// Where this piece's box sits on the board.
  final Offset origin;
  final Size board;
  final bool lifted, placed;

  @override
  void paint(Canvas canvas, Size size) {
    if (!placed) {
      // Translated, not path.shift: no new Path per paint.
      canvas.save();
      canvas.translate(0, lifted ? 8 : 3);
      canvas.drawPath(path, Paint()..color = Color.fromRGBO(0, 0, 0, lifted ? 0.28 : 0.2));
      canvas.restore();
    }
    canvas
      ..save()
      ..clipPath(path)
      ..translate(-origin.dx, -origin.dy)
      ..drawImageRect(image, Offset.zero & Size(image.width.toDouble(), image.height.toDouble()), Offset.zero & board, Paint()..filterQuality = FilterQuality.medium)
      ..restore();
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = placed ? 1 : 2.5
        ..color = Colors.white.withValues(alpha: placed ? 0.35 : 0.85),
    );
  }

  @override
  bool? hitTest(Offset position) => path.contains(position);

  @override
  bool shouldRepaint(_PiecePainter old) => old.image != image || old.path != path || old.lifted != lifted || old.placed != placed || old.origin != origin || old.board != board;
}

/// A hop back to the waiting area: "that's another piece's spot".
class _Hop extends StatelessWidget {
  const _Hop({required this.hops, required this.child});
  final int hops;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        key: ValueKey(hops),
        tween: Tween(begin: hops == 0 ? 0 : 1, end: 0),
        duration: const Duration(milliseconds: 500),
        builder: (context, k, child) => Transform.rotate(angle: math.sin(k * math.pi * 4) * 0.12 * k, child: child),
        child: child,
      );
}
