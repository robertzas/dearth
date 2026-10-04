import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'coloring.dart' show kCrayons;

enum PaintTool { brush, crayon, marker, spray, rainbow, stamp }

/// The paint box: the crayons and black.
const List<(String, Color)> kPaints = [...kCrayons, ('black', Color(0xFF26232E))];

const List<String> kStamps = ['⭐', '❤️', '🌸', '🦋', '🐶', '🐱', '🌈', '🍎', '🚗', '🎈', '🐟', '☀️'];

/// Sheets of paper: plain ones from the start, painted scenes once stamps
/// unlock.
enum Paper { white, cream, night, sky, meadow, sea, space }

const List<Paper> _plainPapers = [Paper.white, Paper.cream, Paper.night, Paper.sky];

/// One stroke or one trail of stamps, in paper fractions (0…1) so it
/// survives a turn of the display.
class _Mark {
  _Mark(this.tool, this.color, this.seed, {required this.mirror, this.stamp});
  final PaintTool tool;
  final Color color;
  final int seed;
  final bool mirror;
  final String? stamp;
  final points = <Offset>[];
}

/// What undo takes back: a mark, or a new sheet (the old one comes back).
sealed class _Step {}

class _Drew extends _Step {
  _Drew(this.mark);
  final _Mark mark;
}

class _NewSheet extends _Step {
  _NewSheet(this.marks, this.paper);
  final List<_Mark> marks;
  final Paper paper;
}

/// Paint Studio (SPEC FR-TOY-02, Appendix B: creativity and fine motor).
/// Paper and paint, nothing to win. Brush, crayon, marker, spray and a
/// rainbow brush in a box of colors; stamps and painted backgrounds unlock
/// with play (level 2), then a mirror that paints both halves at once
/// (level 3). Undo takes back any mark, and a new sheet keeps the old one a
/// single undo away: nothing she does here is lost for good.
class PaintGame extends StatefulWidget {
  const PaintGame(this.c, {super.key});
  final GameController c;

  @override
  State<PaintGame> createState() => PaintGameState();
}

@visibleForTesting
class PaintGameState extends State<PaintGame> {
  final _marks = <_Mark>[];
  final _history = <_Step>[];
  PaintTool _tool = PaintTool.brush;
  int _color = 6;
  int _stamp = 0;
  bool _mirror = false;
  bool _choosingPaper = false;
  Paper _paper = Paper.white;
  _Mark? _current;
  int? _pointer;
  Size _size = Size.zero;
  int _seed = 1;

  /// Finished marks, painted once into a picture of the sheet.
  ui.Image? _baked;
  int _bakedCount = 0;
  Size _bakedSize = Size.zero;
  final _live = ValueNotifier<int>(0);

  late final PaintKit _kit = paintKit(widget.c.level);

  @visibleForTesting
  int get debugMarks => _marks.length;

  @visibleForTesting
  Paper get debugPaper => _paper;

  @override
  void dispose() {
    _live.dispose();
    final old = _baked;
    _baked = null;
    old?.dispose();
    super.dispose();
  }

  /// The display's pixel ratio, read in build (handlers bake too).
  double _dpr = 1;

  /// Paints the finished marks into [_baked]: only the new ones when it
  /// can, everything after an undo or a new size.
  void _bake({bool all = false}) {
    if (_size.isEmpty) return;
    // Enough pixels to stay crisp, not so many that a phone runs short.
    final dpr = math.min(_dpr, math.sqrt(2600000 / (_size.width * _size.height)));
    final px = Size((_size.width * dpr).ceilToDouble(), (_size.height * dpr).ceilToDouble());
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec)..scale(px.width / _size.width, px.height / _size.height);
    final old = _baked;
    var from = 0;
    if (!all && old != null && _bakedSize == _size && _bakedCount <= _marks.length) {
      canvas.drawImageRect(old, Offset.zero & Size(old.width.toDouble(), old.height.toDouble()), Offset.zero & _size, Paint());
      from = _bakedCount;
    }
    for (final m in _marks.skip(from)) {
      _paintMark(canvas, _size, m);
    }
    final picture = rec.endRecording();
    _baked = picture.toImageSync(px.width.toInt(), px.height.toInt());
    picture.dispose();
    _bakedCount = _marks.length;
    _bakedSize = _size;
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null || _choosingPaper) return;
    _pointer = e.pointer;
    final m = _current = _Mark(_tool, kPaints[_color].$2, _seed++, mirror: _mirror, stamp: _tool == PaintTool.stamp ? kStamps[_stamp] : null);
    m.points.add(_norm(e.localPosition));
    if (_tool == PaintTool.stamp) widget.c.sound(Sfx.pop, volume: 0.7, rate: 0.85 + (_seed % 5) * 0.08);
    _live.value++;
  }

  void _move(PointerMoveEvent e) {
    final m = _current;
    if (e.pointer != _pointer || m == null) return;
    final p = _norm(e.localPosition);
    final last = m.points.last;
    final unit = _size.shortestSide;
    final d = Offset((p.dx - last.dx) * _size.width, (p.dy - last.dy) * _size.height).distance;
    if (m.tool == PaintTool.stamp) {
      // A trail of stamps, spaced so they don't pile up.
      if (d < unit * 0.13) return;
      widget.c.sound(Sfx.pop, volume: 0.5, rate: 0.85 + (m.points.length % 5) * 0.08);
    } else if (d < 2) {
      return;
    }
    m.points.add(p);
    // A long scribble is put down in pieces, so drawing it stays cheap.
    if (m.points.length >= 240 && m.tool != PaintTool.stamp) {
      _commit();
      final next = _current = _Mark(m.tool, m.color, _seed++, mirror: m.mirror);
      next.points.add(p);
    }
    _live.value++;
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _commit();
  }

  void _commit() {
    final m = _current;
    if (m == null) return;
    _current = null;
    setState(() {
      _marks.add(m);
      _history.add(_Drew(m));
      _bake();
    });
    _live.value++;
  }

  Offset _norm(Offset p) => _size.isEmpty ? Offset.zero : Offset((p.dx / _size.width).clamp(0, 1), (p.dy / _size.height).clamp(0, 1));

  void _undo() {
    if (_history.isEmpty) return;
    widget.c.sound(Sfx.blip, volume: 0.5, rate: 0.75);
    setState(() {
      switch (_history.removeLast()) {
        case _Drew(:final mark):
          _marks.remove(mark);
        case _NewSheet(:final marks, :final paper):
          _marks
            ..clear()
            ..addAll(marks);
          _paper = paper;
      }
      _bake(all: true);
    });
  }

  void _newSheet(Paper paper) {
    widget.c.sound(Sfx.sparkle, volume: 0.6);
    setState(() {
      _history.add(_NewSheet([..._marks], _paper));
      _marks.clear();
      _paper = paper;
      _choosingPaper = false;
      _bake(all: true);
    });
  }

  void _pickTool(PaintTool t) {
    widget.c.sound(Sfx.tap, volume: 0.6);
    setState(() => _tool = t);
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    _dpr = MediaQuery.devicePixelRatioOf(context);
    return ColoredBox(
      color: const Color(0xFFF3EEE6),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(t.space.md, 96 * t.scale, t.space.md, t.space.md),
          child: LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth > box.maxHeight;
            final b = 72 * t.scale;
            final tools = <Widget>[
              for (final tool in PaintTool.values)
                if (tool != PaintTool.stamp || _kit.stamps)
                  _RoundButton(
                    id: 'paint.tool.${tool.name}',
                    label: tool.name,
                    // Each tool shows what it paints, in the color she picked.
                    emoji: tool == PaintTool.stamp ? kStamps[_stamp] : null,
                    sample: tool == PaintTool.stamp ? null : _ToolSample(tool, kPaints[_color].$2),
                    size: b,
                    selected: _tool == tool,
                    onTap: () => _pickTool(tool),
                  ),
              if (_kit.mirror)
                _RoundButton(id: 'paint.mirror', label: _mirror ? 'Mirror on' : 'Mirror off', emoji: '🦋', size: b, selected: _mirror, onTap: () => setState(() => _mirror = !_mirror)),
            ];
            final actions = <Widget>[
              _RoundButton(id: 'paint.undo', label: 'Undo', emoji: '↩️', size: b, onTap: _undo),
              _RoundButton(id: 'paint.new', label: 'New paper', emoji: '📄', size: b, selected: _choosingPaper, onTap: () => setState(() => _choosingPaper = !_choosingPaper)),
            ];
            final swatches = _tool == PaintTool.stamp
                ? [for (final (i, s) in kStamps.indexed) _RoundButton(id: 'paint.stamp.$i', label: 'Stamp ${i + 1}', emoji: s, size: b * 0.86, selected: _stamp == i, onTap: () => setState(() => _stamp = i))]
                : [for (final (i, (name, color)) in kPaints.indexed) _ColorDot(id: 'paint.color.$name', label: name, color: color, size: b * 0.82, selected: _color == i, onTap: () => setState(() => _color = i))];
            final gap = t.space.sm;
            // Strips shrink to fit a phone rather than overflow.
            Widget strip(List<Widget> items, Axis axis, {int lines = 1}) {
              final per = (items.length / lines).ceil();
              return FittedBox(
                fit: BoxFit.scaleDown,
                child: Flex(
                direction: axis == Axis.vertical ? Axis.horizontal : Axis.vertical,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var l = 0; l < lines; l++)
                    Flex(
                      direction: axis,
                      mainAxisSize: MainAxisSize.min,
                      children: [for (final w in items.skip(l * per).take(per)) Padding(padding: EdgeInsets.all(gap / 2), child: w)],
                    ),
                ],
                ),
              );
            }

            final paper = Expanded(child: _paperView(t));
            if (wide) {
              return Row(
                children: [
                  Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Flexible(child: strip(tools, Axis.vertical)), strip(actions, Axis.vertical)]),
                  SizedBox(width: t.space.md),
                  paper,
                  SizedBox(width: t.space.md),
                  Center(child: strip(swatches, Axis.vertical, lines: 2)),
                ],
              );
            }
            return Column(
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Flexible(child: strip(tools, Axis.horizontal)), strip(actions, Axis.horizontal)]),
                SizedBox(height: t.space.md),
                paper,
                SizedBox(height: t.space.md),
                strip(swatches, Axis.horizontal, lines: 2),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _paperView(DTheme t) => LayoutBuilder(builder: (context, box) {
        final size = box.biggest;
        if (size != _size) {
          _size = size;
          // A new shape of paper: every mark, redrawn to fit.
          if (_marks.isNotEmpty) _bake(all: true);
        }
        final n = _marks.length;
        return Stack(
          children: [
            Positioned.fill(
              child: tid(
                'paint.paper',
                Semantics(
                  label: 'Painting: $n ${n == 1 ? 'mark' : 'marks'}',
                  excludeSemantics: true,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _down,
                    onPointerMove: _move,
                    onPointerUp: _up,
                    onPointerCancel: _up,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(t.radius.m),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          RepaintBoundary(child: CustomPaint(painter: _PaperPainter(_paper))),
                          RepaintBoundary(child: CustomPaint(painter: _BakedPainter(_baked, _bakedSize))),
                          RepaintBoundary(child: CustomPaint(painter: _LivePainter(this, _live))),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_choosingPaper) Positioned.fill(child: _PaperChooser(scenes: _kit.scenes, onPick: _newSheet, onClose: () => setState(() => _choosingPaper = false))),
          ],
        );
      });
}

// ──────────────────────────────── Painting ─────────────────────────────────

final Map<(String, double), TextPainter> _stampCache = {};

TextPainter _stampPainter(String emoji, double size) => _stampCache.putIfAbsent((emoji, size), () {
      if (_stampCache.length > 64) _stampCache.clear();
      return TextPainter(
        text: TextSpan(text: emoji, style: TextStyle(fontSize: size, height: 1, inherit: false, fontFamilyFallback: const ['Noto Color Emoji', 'Apple Color Emoji', 'Segoe UI Emoji'])),
        textDirection: TextDirection.ltr,
      )..layout();
    });

Path _smooth(List<Offset> pts) {
  final p = Path()..moveTo(pts.first.dx, pts.first.dy);
  if (pts.length == 1) return p..lineTo(pts.first.dx + 0.01, pts.first.dy);
  for (var i = 1; i < pts.length - 1; i++) {
    final mid = (pts[i] + pts[i + 1]) / 2;
    p.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
  }
  return p..lineTo(pts.last.dx, pts.last.dy);
}

/// Paints [m] on a sheet of size [s]. Line widths follow the sheet's shorter
/// side, or [unit] (a tool button's sample, drawn at sheet scale).
void _paintMark(Canvas canvas, Size s, _Mark m, {double? unit}) {
  _drawMark(canvas, s, m, flip: false, unit: unit ?? s.shortestSide);
  if (m.mirror) _drawMark(canvas, s, m, flip: true, unit: unit ?? s.shortestSide);
}

void _drawMark(Canvas canvas, Size s, _Mark m, {required bool flip, required double unit}) {
  if (m.points.isEmpty) return;
  final pts = [for (final p in m.points) Offset((flip ? 1 - p.dx : p.dx) * s.width, p.dy * s.height)];
  Paint line(double width, Color color) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = color;
  switch (m.tool) {
    case PaintTool.brush:
      canvas.drawPath(_smooth(pts), line(unit * 0.024, m.color));
    case PaintTool.marker:
      // One path, so a see-through marker doesn't darken where it crosses itself.
      canvas.drawPath(_smooth(pts), line(unit * 0.042, m.color.withValues(alpha: 0.5)));
    case PaintTool.crayon:
      final path = _smooth(pts);
      canvas.drawPath(path, line(unit * 0.02, m.color.withValues(alpha: 0.82)));
      // Wax grain: thin strands a little off the line, lighter and darker.
      final rng = math.Random(m.seed);
      for (var k = 0; k < 4; k++) {
        final o = Offset((rng.nextDouble() - 0.5) * unit * 0.014, (rng.nextDouble() - 0.5) * unit * 0.014);
        final shade = Color.lerp(m.color, k.isEven ? Colors.white : Colors.black, 0.25)!;
        canvas.drawPath(path.shift(o), line(unit * 0.004, shade.withValues(alpha: 0.45)));
      }
    case PaintTool.spray:
      final dots = <Offset>[];
      for (final (i, p) in pts.indexed) {
        final rng = math.Random(m.seed * 997 + i);
        for (var k = 0; k < 12; k++) {
          final r = unit * 0.036 * math.sqrt(rng.nextDouble()), a = rng.nextDouble() * math.pi * 2;
          dots.add(p + Offset(math.cos(a) * r, math.sin(a) * r));
        }
      }
      canvas.drawPoints(ui.PointMode.points, dots, line(unit * 0.006, m.color.withValues(alpha: 0.85)));
    case PaintTool.rainbow:
      var run = 0.0;
      final paint = line(unit * 0.03, Colors.red);
      if (pts.length == 1) {
        canvas.drawPoints(ui.PointMode.points, pts, paint..color = HSVColor.fromAHSV(1, (m.seed * 47) % 360, 0.8, 0.95).toColor());
      }
      for (var i = 1; i < pts.length; i++) {
        run += (pts[i] - pts[i - 1]).distance;
        paint.color = HSVColor.fromAHSV(1, (m.seed * 47 + run / unit * 300) % 360, 0.8, 0.95).toColor();
        canvas.drawLine(pts[i - 1], pts[i], paint);
      }
    case PaintTool.stamp:
      final size = unit * 0.12;
      final tp = _stampPainter(m.stamp ?? '⭐', size);
      for (final p in pts) {
        tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
      }
  }
}

class _BakedPainter extends CustomPainter {
  const _BakedPainter(this.image, this.size);
  final ui.Image? image;
  final Size size;

  @override
  void paint(Canvas canvas, Size box) {
    final img = image;
    if (img == null) return;
    canvas.drawImageRect(img, Offset.zero & Size(img.width.toDouble(), img.height.toDouble()), Offset.zero & size, Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(_BakedPainter old) => old.image != image || old.size != size;
}

/// The mark being drawn right now, and nothing else.
class _LivePainter extends CustomPainter {
  _LivePainter(this.s, Listenable live) : super(repaint: live);
  final PaintGameState s;

  @override
  void paint(Canvas canvas, Size size) {
    final m = s._current;
    if (m != null) _paintMark(canvas, size, m);
  }

  @override
  bool shouldRepaint(_LivePainter old) => false;
}

/// A sheet: a plain color, or a painted scene to paint on.
class _PaperPainter extends CustomPainter {
  const _PaperPainter(this.paper);
  final Paper paper;

  @override
  void paint(Canvas canvas, Size size) => paintPaper(canvas, size, paper);

  @override
  bool shouldRepaint(_PaperPainter old) => old.paper != paper;
}

void paintPaper(Canvas canvas, Size size, Paper paper) {
  final r = Offset.zero & size;
  final w = size.width, h = size.height;
  Paint grad(List<Color> colors, Rect rect) => Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors).createShader(rect);
  switch (paper) {
    case Paper.white:
      canvas.drawRect(r, Paint()..color = Colors.white);
    case Paper.cream:
      canvas.drawRect(r, Paint()..color = const Color(0xFFFFF4DC));
    case Paper.night:
      canvas.drawRect(r, Paint()..color = const Color(0xFF1C2140));
    case Paper.sky:
      canvas.drawRect(r, Paint()..color = const Color(0xFFDDF1FF));
    case Paper.meadow:
      canvas.drawRect(r, grad(const [Color(0xFF9AD8FF), Color(0xFFE2F4FF)], r));
      final hill = Path()
        ..moveTo(0, h * 0.7)
        ..quadraticBezierTo(w * 0.35, h * 0.58, w * 0.7, h * 0.68)
        ..quadraticBezierTo(w * 0.88, h * 0.72, w, h * 0.66)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      canvas
        ..drawPath(hill, grad(const [Color(0xFF9FD86F), Color(0xFF6DBB4C)], Rect.fromLTWH(0, h * 0.58, w, h * 0.42)))
        ..drawCircle(Offset(w * 0.86, h * 0.16), size.shortestSide * 0.08, Paint()..color = const Color(0xFFFFD54F));
    case Paper.sea:
      canvas
        ..drawRect(Rect.fromLTWH(0, 0, w, h * 0.4), grad(const [Color(0xFF9AD8FF), Color(0xFFDDF3FF)], Rect.fromLTWH(0, 0, w, h * 0.4)))
        ..drawRect(Rect.fromLTWH(0, h * 0.4, w, h * 0.6), grad(const [Color(0xFF4FB3E8), Color(0xFF1F6FB2)], Rect.fromLTWH(0, h * 0.4, w, h * 0.6)));
      final sand = Path()
        ..moveTo(0, h * 0.88)
        ..quadraticBezierTo(w * 0.5, h * 0.8, w, h * 0.9)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      canvas.drawPath(sand, Paint()..color = const Color(0xFFF1D9A6));
    case Paper.space:
      canvas.drawRect(r, grad(const [Color(0xFF0B1030), Color(0xFF26306B)], r));
      final rng = math.Random(11);
      final star = Paint();
      for (var i = 0; i < 90; i++) {
        star.color = Color.fromRGBO(255, 255, 240, 0.4 + rng.nextDouble() * 0.6);
        canvas.drawCircle(Offset(rng.nextDouble() * w, rng.nextDouble() * h), 0.8 + rng.nextDouble() * 1.6, star);
      }
      canvas.drawCircle(Offset(w * 0.82, h * 0.2), size.shortestSide * 0.09, Paint()..color = const Color(0xFFF2E7C9));
  }
}

// ─────────────────────────────────── Controls ──────────────────────────────

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.id, required this.label, this.emoji, this.sample, required this.size, required this.onTap, this.selected = false});
  final String id, label;
  final String? emoji;

  /// Painted instead of an emoji: a tool's stroke.
  final CustomPainter? sample;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return DPressable(
      id: id,
      semanticLabel: label,
      selected: selected,
      excludeSemantics: true,
      onTap: onTap,
      borderRadius: BorderRadius.circular(size),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF1C2) : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? const Color(0xFFF2B33D) : const Color(0xFFE6DFD3), width: selected ? 4 : 2),
          boxShadow: t.elevation.e1,
        ),
        alignment: Alignment.center,
        child: sample != null ? ClipOval(child: CustomPaint(size: Size.square(size), painter: sample)) : DEmoji(emoji ?? '', size: size * 0.56),
      ),
    );
  }
}

/// A short squiggle in [tool]'s stroke and [color], at the size it paints.
class _ToolSample extends CustomPainter {
  const _ToolSample(this.tool, this.color);
  final PaintTool tool;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final m = _Mark(tool, color, 7, mirror: false);
    for (var i = 0; i <= 12; i++) {
      final x = 0.22 + 0.56 * i / 12;
      m.points.add(Offset(x, 0.5 + 0.16 * math.sin(i / 12 * math.pi * 2)));
    }
    _paintMark(canvas, size, m, unit: size.shortestSide * 6.5);
  }

  @override
  bool shouldRepaint(_ToolSample old) => old.tool != tool || old.color != color;
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.id, required this.label, required this.color, required this.size, required this.selected, required this.onTap});
  final String id, label;
  final Color color;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DPressable(
        id: id,
        semanticLabel: label,
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
              boxShadow: [BoxShadow(color: const Color(0x2E000000), offset: Offset(0, selected ? 5 : 3))],
            ),
          ),
        ),
      );
}

/// A row of fresh sheets to choose from, over the painting.
class _PaperChooser extends StatelessWidget {
  const _PaperChooser({required this.scenes, required this.onPick, required this.onClose});
  final bool scenes;
  final ValueChanged<Paper> onPick;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final d = 104 * t.scale;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      child: ColoredBox(
        color: const Color(0x66000000),
        child: Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: t.space.md,
            runSpacing: t.space.md,
            children: [
              for (final p in [..._plainPapers, if (scenes) ...[Paper.meadow, Paper.sea, Paper.space]])
                DPressable(
                  id: 'paint.paper.${p.name}',
                  semanticLabel: '${p.name} paper',
                  excludeSemantics: true,
                  onTap: () => onPick(p),
                  borderRadius: BorderRadius.circular(t.radius.m),
                  child: Container(
                    width: d * 1.3,
                    height: d,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(t.radius.m), border: Border.all(color: Colors.white, width: 4), boxShadow: t.elevation.e2),
                    child: ClipRRect(borderRadius: BorderRadius.circular(t.radius.m - 4), child: CustomPaint(painter: _PaperPainter(p))),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
