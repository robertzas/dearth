import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'coloring_pictures.dart';

/// The crayon box.
const List<(String, Color)> kCrayons = [
  ('red', Color(0xFFF44336)),
  ('orange', Color(0xFFFF9800)),
  ('yellow', Color(0xFFFFE135)),
  ('lime', Color(0xFF9CCC65)),
  ('green', Color(0xFF3FA34D)),
  ('sky', Color(0xFF6CCBF5)),
  ('blue', Color(0xFF2F6FDB)),
  ('purple', Color(0xFF9157C9)),
  ('pink', Color(0xFFF59AC0)),
  ('brown', Color(0xFF9A6B4F)),
  ('gray', Color(0xFFA7A9B5)),
  ('white', Color(0xFFFFFFFF)),
];

const Color _ink = Color(0xFF2B2B38);

/// A picture made ready to color: each part's visible area (what the parts
/// above it leave showing), and a spot well inside each one.
class PreparedPicture {
  PreparedPicture._(this.picture, this.visible, this.anchors);

  factory PreparedPicture.of(ColoringPicture p) {
    final n = p.regions.length;
    final visible = List<Path>.filled(n, Path());
    Path? above;
    for (var i = n - 1; i >= 0; i--) {
      final r = p.regions[i];
      visible[i] = above == null ? r : Path.combine(PathOperation.difference, r, above);
      above = above == null ? r : Path.combine(PathOperation.union, above, r);
    }
    return PreparedPicture._(p, visible, [for (final v in visible) _anchor(v)]);
  }

  final ColoringPicture picture;
  final List<Path> visible;
  final List<Offset> anchors;

  /// The part under [p] (picture coordinates).
  int? partAt(Offset p) {
    for (var i = visible.length - 1; i >= 0; i--) {
      if (visible[i].contains(p)) return i;
    }
    return null;
  }
}

/// A point deep inside [path]: its middle when that is well inside, else the
/// deepest of a grid of tries.
Offset _anchor(Path path) {
  final b = path.getBounds();
  double depth(Offset p) {
    if (!path.contains(p)) return -1;
    for (var d = 2.0; d < 256; d *= 2) {
      for (var a = 0; a < 8; a++) {
        if (!path.contains(p + Offset(math.cos(a * math.pi / 4), math.sin(a * math.pi / 4)) * d)) return d / 2;
      }
    }
    return 256;
  }

  var best = b.center;
  var bestDepth = depth(best);
  if (bestDepth >= math.min(32, b.shortestSide / 4)) return best;
  const steps = 12;
  for (var x = 0; x < steps; x++) {
    for (var y = 0; y < steps; y++) {
      final p = Offset(b.left + b.width * (x + 0.5) / steps, b.top + b.height * (y + 0.5) / steps);
      final d = depth(p);
      if (d > bestDepth) (best, bestDepth) = (p, d);
    }
  }
  return best;
}

/// Where a picture sits in a [box]: as big as fits, centered.
({Offset offset, double scale}) fitPicture(Size box) {
  final k = math.min(box.width / kPictureSize.width, box.height / kPictureSize.height);
  return (offset: Offset((box.width - kPictureSize.width * k) / 2, (box.height - kPictureSize.height * k) / 2), scale: k);
}

/// Magic Coloring (SPEC FR-TOY-02, Appendix B: colors and fine motor). Pick a
/// crayon, tap a part, and color spreads from her finger to fill it. Pictures
/// grow from four big parts to more than two dozen small ones as she climbs.
/// A finished picture is celebrated; she can keep recoloring, or tap the
/// arrow for the next one.
class ColoringGame extends StatefulWidget {
  const ColoringGame(this.c, {super.key});
  final GameController c;

  @override
  State<ColoringGame> createState() => ColoringGameState();
}

class _Wipe {
  const _Wipe(this.part, this.from, this.color);
  final int part;
  final Offset from;
  final Color color;
}

@visibleForTesting
class ColoringGameState extends State<ColoringGame> with SingleTickerProviderStateMixin {
  static List<ColoringPicture>? _all;
  static final _prepared = <String, PreparedPicture>{};

  late PreparedPicture _pic;
  List<Color?> _fills = const [];
  int _crayon = 0;
  bool _done = false;
  final _recent = <String>[];
  late final AnimationController _wipe = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _settleWipe();
    });
  _Wipe? _wiping;

  @visibleForTesting
  String get debugPicture => _pic.picture.id;

  @visibleForTesting
  List<Color?> get debugFills => _fills;

  @override
  void initState() {
    super.initState();
    _newPicture();
  }

  @override
  void dispose() {
    _wipe.dispose();
    super.dispose();
  }

  void _newPicture() {
    final all = _all ??= [for (final make in kColoringPictures) make()];
    final level = widget.c.level;
    final fits = [for (final p in all) if (coloringFits(p.regions.length, level)) p];
    final fresh = [for (final p in fits) if (!_recent.contains(p.id)) p];
    final pool = fresh.isEmpty ? fits : fresh;
    final pick = pool[widget.c.random.nextInt(pool.length)];
    _recent.add(pick.id);
    if (_recent.length > 2) _recent.removeAt(0);
    _pic = _prepared.putIfAbsent(pick.id, () => PreparedPicture.of(pick));
    _fills = List<Color?>.filled(_pic.visible.length, null);
    _done = false;
    _wiping = null;
    if (mounted) setState(() {});
  }

  void _tapAt(Offset local, Size box) {
    final f = fitPicture(box);
    final p = (local - f.offset) / f.scale;
    final part = _pic.partAt(p);
    if (part != null) _fill(part, p);
  }

  void _fill(int part, Offset from) {
    _settleWipe();
    final color = kCrayons[_crayon].$2;
    if (_fills[part] == color) return;
    widget.c.sound(Sfx.sparkle, volume: 0.45);
    setState(() => _wiping = _Wipe(part, from, color));
    unawaited(_wipe.forward(from: 0));
  }

  /// The spreading color has filled its part: keep it.
  void _settleWipe() {
    final w = _wiping;
    if (w == null) return;
    _wiping = null;
    setState(() => _fills = [..._fills]..[w.part] = w.color);
    if (!_done && _fills.every((f) => f != null)) {
      _done = true;
      unawaited(widget.c.finishRound(GameResult.win, emoji: _pic.picture.emoji));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return ColoredBox(
      color: const Color(0xFFFFF8EC),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(t.space.lg, 96 * t.scale, t.space.lg, t.space.lg),
          child: LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth > box.maxHeight;
            final palette = _Palette(selected: _crayon, vertical: wide, onPick: (i) => setState(() => _crayon = i));
            final canvas = Expanded(child: _canvas(t));
            return wide ? Row(children: [canvas, SizedBox(width: t.space.lg), palette]) : Column(children: [canvas, SizedBox(height: t.space.lg), palette]);
          }),
        ),
      ),
    );
  }

  Widget _canvas(DTheme t) => LayoutBuilder(builder: (context, box) {
        final size = box.biggest;
        final f = fitPicture(size);
        final colored = _fills.where((c) => c != null).length;
        return Stack(
          children: [
            Positioned.fill(
              child: tid(
                'coloring.canvas',
                Semantics(
                  label: 'Colored $colored of ${_fills.length}',
                  excludeSemantics: true,
                  child: GestureDetector(
                    excludeFromSemantics: true,
                    behavior: HitTestBehavior.opaque,
                    // On the finger going down: the color answers at once.
                    onTapDown: (d) => _tapAt(d.localPosition, size),
                    child: RepaintBoundary(child: CustomPaint(painter: _PicturePainter(_pic, _fills), size: Size.infinite)),
                  ),
                ),
              ),
            ),
            Positioned.fill(child: IgnorePointer(child: RepaintBoundary(child: CustomPaint(painter: _WipePainter(_pic, _wipe, _wiping))))),
            // A spot inside each part, for screen readers and tests: a tap on
            // it lands on the picture underneath.
            for (final (i, a) in _pic.anchors.indexed)
              Positioned(
                left: f.offset.dx + a.dx * f.scale - 12,
                top: f.offset.dy + a.dy * f.scale - 12,
                child: tid('coloring.region.$i', Semantics(label: 'Part ${i + 1}', onTap: () => _fill(i, a), excludeSemantics: true, child: const SizedBox.square(dimension: 24))),
              ),
            if (_done)
              Positioned(
                right: f.offset.dx + t.space.sm,
                top: f.offset.dy + t.space.sm,
                child: _NextButton(onTap: _newPicture),
              ),
          ],
        );
      });
}

/// The picture: every part's color (white until colored), then the outlines
/// and painted details on top. Repaints only when a color lands.
class _PicturePainter extends CustomPainter {
  const _PicturePainter(this.pic, this.fills);
  final PreparedPicture pic;
  final List<Color?> fills;

  @override
  void paint(Canvas canvas, Size size) {
    final f = fitPicture(size);
    canvas
      ..translate(f.offset.dx, f.offset.dy)
      ..scale(f.scale);
    final fill = Paint();
    for (final (i, v) in pic.visible.indexed) {
      fill.color = fills[i] ?? Colors.white;
      canvas.drawPath(v, fill);
    }
    _outlines(canvas, pic, pic.visible);
  }

  @override
  bool shouldRepaint(_PicturePainter old) => old.pic != pic || old.fills != fills;
}

Paint get _inkStroke => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = 7
  ..strokeJoin = StrokeJoin.round
  ..strokeCap = StrokeCap.round
  ..color = _ink;

/// Outlines of [parts], the picture's lines, and its painted details.
void _outlines(Canvas canvas, PreparedPicture pic, Iterable<Path> parts) {
  final ink = _inkStroke;
  for (final v in parts) {
    canvas.drawPath(v, ink);
  }
  for (final l in pic.picture.lines) {
    canvas.drawPath(l, ink);
  }
  final thin = _inkStroke..strokeWidth = 4;
  for (final (p, c) in pic.picture.fixed) {
    canvas.drawPath(p, Paint()..color = c);
    if (c != _ink) canvas.drawPath(p, thin);
  }
}

/// Color spreading from the finger across one part, clipped to it, with the
/// lines redrawn on top.
class _WipePainter extends CustomPainter {
  _WipePainter(this.pic, this.t, this.wipe) : super(repaint: t);
  final PreparedPicture pic;
  final Animation<double> t;
  final _Wipe? wipe;

  @override
  void paint(Canvas canvas, Size size) {
    final w = wipe;
    if (w == null || t.value == 0) return;
    final f = fitPicture(size);
    canvas
      ..translate(f.offset.dx, f.offset.dy)
      ..scale(f.scale);
    final part = pic.visible[w.part];
    final b = part.getBounds();
    final reach = [b.topLeft, b.topRight, b.bottomLeft, b.bottomRight].map((c) => (c - w.from).distance).reduce(math.max);
    canvas
      ..save()
      ..clipPath(part)
      ..drawCircle(w.from, reach * Curves.easeOutCubic.transform(t.value), Paint()..color = w.color)
      ..restore();
    _outlines(canvas, pic, [part]);
  }

  @override
  bool shouldRepaint(_WipePainter old) => old.wipe != wipe || old.pic != pic;
}

class _Palette extends StatelessWidget {
  const _Palette({required this.selected, required this.vertical, required this.onPick});
  final int selected;
  final bool vertical;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return LayoutBuilder(builder: (context, box) {
      // Two lines of six crayons, as big as the side allows.
      final long = vertical ? box.maxHeight : box.maxWidth;
      final d = math.min(88 * t.scale, long / 6 * 0.78);
      final gap = d * 0.22;
      final lines = [
        for (var row = 0; row < 2; row++)
          Flex(
            direction: vertical ? Axis.vertical : Axis.horizontal,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = row * 6; i < row * 6 + 6; i++) Padding(padding: EdgeInsets.all(gap / 2), child: _Swatch(index: i, size: d, selected: i == selected, onTap: () => onPick(i))),
            ],
          ),
      ];
      return Center(child: Flex(direction: vertical ? Axis.horizontal : Axis.vertical, mainAxisSize: MainAxisSize.min, children: lines));
    });
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.index, required this.size, required this.selected, required this.onTap});
  final int index;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (name, color) = kCrayons[index];
    return DPressable(
      id: 'coloring.color.$name',
      semanticLabel: name,
      selected: selected,
      excludeSemantics: true,
      onTap: onTap,
      borderRadius: BorderRadius.circular(size),
      child: AnimatedScale(
        scale: selected ? 1.18 : 1,
        duration: const Duration(milliseconds: 160),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: selected ? Colors.white : Color.lerp(color, Colors.black, 0.18)!, width: selected ? size * 0.1 : size * 0.05),
            // A crisp offset shadow: no blur to redraw while it scales.
            boxShadow: [BoxShadow(color: const Color(0x2E000000), offset: Offset(0, selected ? 5 : 3))],
          ),
          child: selected ? Icon(Icons.check_rounded, size: size * 0.5, color: color.computeLuminance() > 0.6 ? _ink : Colors.white) : null,
        ),
      ),
    );
  }
}

/// "Another picture": appears when every part has a color.
class _NextButton extends StatelessWidget {
  const _NextButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final d = 88 * t.scale;
    return DPressable(
      id: 'coloring.next',
      semanticLabel: 'Next picture',
      excludeSemantics: true,
      onTap: onTap,
      borderRadius: BorderRadius.circular(d),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.elasticOut,
        builder: (context, k, child) => Transform.scale(scale: k, child: child),
        child: Container(
          width: d,
          height: d,
          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: t.elevation.e2),
          alignment: Alignment.center,
          child: DEmoji('➡️', size: d * 0.56),
        ),
      ),
    );
  }
}
