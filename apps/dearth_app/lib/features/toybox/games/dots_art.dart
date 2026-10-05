import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'dots_pictures.dart';

/// How a finished Dot-to-Dot picture looks and comes alive (SPEC FR-TOY-03,
/// Appendix B): its colors, the parts painted inside its outline (a roof, a
/// belly, stripes), the details on top (eyes, windows, a string) and a few
/// seconds of motion: the star twinkles, the heart beats, the chimney
/// smokes, the fish swims, the car's wheels turn. Everything is drawn in the
/// outline's 1000 box, and fading in multiplies each paint's alpha, so
/// nothing needs a layer (AGENTS rule 8).
///
/// [t] is how long the picture has been alive (s), [reveal] how far it has
/// faded in (0 → 1). The line she drew turns from [ink] into the picture's
/// own outline color. A [still] picture (reduced motion) fills in but
/// doesn't move.
void paintDotPicture(Canvas canvas, DotArt art, Path outline, {required double t, required double reveal, required double lineWidth, required Color ink, bool still = false}) {
  final style = _styles[art.id]!;
  final line = Paint()
    ..color = Color.lerp(ink, style.dark, reveal)!
    ..style = PaintingStyle.stroke
    ..strokeWidth = lineWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  canvas.save();
  style.paint(_Scene(canvas, style, art.id, outline, t, reveal, line, still: still));
  canvas.restore();
}

/// The outline color a picture ends with (the line she drew turns into it).
Color dotPictureOutline(String id) => _styles[id]!.dark;

/// Cuts a picture's painted parts (a roof, a belly) out of its outline
/// ahead of time: path operations are slow on the frame's CPU, so a round
/// does it while its dots appear, not on the frame the picture is revealed.
void prepareDotPicture(DotArt art, Path outline) => _regionsOf(art.id, outline);

final Map<String, List<(Path, Color)>> _cut = {};

List<(Path, Color)> _regionsOf(String id, Path outline) => _cut[id] ??= [
      for (final (shape, color) in _styles[id]!.regions?.call() ?? const <(Path, Color)>[]) (Path.combine(PathOperation.intersect, outline, shape), color),
    ];

class _Style {
  const _Style(this.fill, this.paint, {this.regions});
  final Color fill;
  final void Function(_Scene x) paint;

  /// Parts painted over the fill; cut to the outline once, on first use.
  final List<(Path, Color)> Function()? regions;

  Color get dark => Color.lerp(fill, const Color(0xFF2B2440), 0.55)!;
}

class _Scene {
  _Scene(this.c, this.style, this.id, this.outline, this.t, this.reveal, this.line, {required this.still});
  final Canvas c;
  final _Style style;
  final String id;
  final Path outline;
  final double t, reveal;
  final Paint line;
  final bool still;

  Color get dark => style.dark;

  /// How strongly it moves: the motion eases in over half a second (and
  /// stays off with reduced motion, taking the smoke and sparkles with it).
  double get amp => still ? 0 : Curves.easeOut.transform((t / 0.5).clamp(0.0, 1.0));

  /// The picture itself: the fill, its painted parts and the outline.
  void shape() {
    c.drawPath(outline, fill(style.fill));
    for (final (path, color) in _regionsOf(id, outline)) {
      c.drawPath(path, fill(color));
    }
    c.drawPath(outline, line);
  }

  Paint fill(Color color, [double a = 1]) => Paint()..color = color.withValues(alpha: color.a * reveal * a.clamp(0.0, 1.0));

  Paint stroke(Color color, double width, [double a = 1]) => Paint()
    ..color = color.withValues(alpha: color.a * reveal * a.clamp(0.0, 1.0))
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void shift(double dx, double dy) => c.translate(dx, dy);

  void turn(Offset pivot, double angle) {
    c.translate(pivot.dx, pivot.dy);
    c.rotate(angle);
    c.translate(-pivot.dx, -pivot.dy);
  }

  void grow(Offset pivot, double sx, [double? sy]) {
    c.translate(pivot.dx, pivot.dy);
    c.scale(sx, sy ?? sx);
    c.translate(-pivot.dx, -pivot.dy);
  }

  /// A wave between -1 and 1, [hz] times a second.
  double wave(double hz, [double phase = 0]) => math.sin(t * 2 * math.pi * hz + phase);
}

// ─────────────────────────────── Drawing kit ───────────────────────────────

const Color _faceInk = Color(0xFF3B2F4A);
const Color _cheek = Color(0x77FF7A9C);

Path _poly(List<double> xy) {
  final p = Path()..moveTo(xy[0], xy[1]);
  for (var i = 2; i < xy.length; i += 2) {
    p.lineTo(xy[i], xy[i + 1]);
  }
  return p..close();
}

/// A smooth closed shape through the points (a Catmull-Rom loop).
Path _blob(List<double> xy) {
  final pts = [for (var i = 0; i < xy.length; i += 2) Offset(xy[i], xy[i + 1])];
  final n = pts.length;
  final p = Path()..moveTo(pts[0].dx, pts[0].dy);
  for (var i = 0; i < n; i++) {
    final p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n];
    final c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6;
    p.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return p..close();
}

/// A smooth open line through the points.
Path _curve(List<double> xy) {
  final pts = [for (var i = 0; i < xy.length; i += 2) Offset(xy[i], xy[i + 1])];
  final p = Path()..moveTo(pts[0].dx, pts[0].dy);
  for (var i = 0; i < pts.length - 1; i++) {
    final p0 = pts[math.max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[math.min(pts.length - 1, i + 2)];
    final c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6;
    p.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return p;
}

Path _rect(double l, double t, double r, double b) => Path()..addRect(Rect.fromLTRB(l, t, r, b));

/// 0 → 1 → 0 during a quick blink every [every] seconds.
double _blink(double t, {double every = 2.4, double at = 1.2}) {
  final p = (t - at) % every;
  return p < 0.18 ? math.sin(p / 0.18 * math.pi) : 0;
}

/// Two eyes with a shine, a smile and rosy cheeks, [size] wide.
void _face(_Scene x, Offset at, double size, {double blink = 0}) {
  for (final side in const [-1.0, 1.0]) {
    final eye = at + Offset(side * size * 0.34, -size * 0.06);
    x.c.drawOval(Rect.fromCenter(center: eye, width: size * 0.16, height: size * 0.22 * (1 - 0.88 * blink)), x.fill(_faceInk));
    if (blink < 0.5) x.c.drawCircle(eye + Offset(size * 0.03, -size * 0.045), size * 0.035, x.fill(Colors.white));
    x.c.drawOval(Rect.fromCenter(center: at + Offset(side * size * 0.52, size * 0.14), width: size * 0.2, height: size * 0.12), x.fill(_cheek));
  }
  final smile = Path()
    ..moveTo(at.dx - size * 0.15, at.dy + size * 0.12)
    ..quadraticBezierTo(at.dx, at.dy + size * 0.3, at.dx + size * 0.15, at.dy + size * 0.12);
  x.c.drawPath(smile, x.stroke(_faceInk, size * 0.055));
}

/// A four-pointed twinkle of radius [r].
void _twinkle(_Scene x, Offset at, double r, Color color) {
  if (r < 2) return;
  final p = Path()
    ..moveTo(at.dx, at.dy - r)
    ..quadraticBezierTo(at.dx, at.dy, at.dx + r, at.dy)
    ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy + r)
    ..quadraticBezierTo(at.dx, at.dy, at.dx - r, at.dy)
    ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy - r)
    ..close();
  x.c.drawPath(p, x.fill(color));
}

/// A white oval highlight, tilted by [angle].
void _shine(_Scene x, Offset at, double w, double h, double angle, [double a = 0.5]) {
  x.c.save();
  x.turn(at, angle);
  x.c.drawOval(Rect.fromCenter(center: at, width: w, height: h), x.fill(Colors.white, a));
  x.c.restore();
}

/// A flame hanging from [x], [y]: [w] half-wide, [h] long.
Path _flame(double x, double y, double w, double h) => Path()
  ..moveTo(x - w, y)
  ..quadraticBezierTo(x - w * 0.7, y + h * 0.65, x, y + h)
  ..quadraticBezierTo(x + w * 0.7, y + h * 0.65, x + w, y)
  ..close();

/// Thin diagonal strips both ways across the cone (x 290–710, y 480–870),
/// for a waffle pattern.
Path _waffle() {
  final p = Path();
  void strip(Offset a, Offset b) {
    final n = Offset(-(b - a).dy, (b - a).dx) / (b - a).distance * 5;
    p.addPolygon([a + n, b + n, b - n, a - n], true);
  }

  // Down-right lines y = x − k, then down-left lines y = k − x.
  for (var k = -620.0; k <= 260; k += 68) {
    strip(Offset(k, 0), Offset(k + 1000, 1000));
  }
  for (var k = 740.0; k <= 1620; k += 68) {
    strip(Offset(k, 0), Offset(k - 1000, 1000));
  }
  return p;
}

// ───────────────────────────────── Pictures ─────────────────────────────────

final Map<String, _Style> _styles = {
  'star': _Style(const Color(0xFFFFD54F), (x) {
    const middle = Offset(500, 530);
    x.turn(middle, 0.1 * x.wave(0.75) * x.amp);
    x.grow(middle, 1 + 0.05 * x.wave(1.5) * x.amp);
    x.shape();
    _face(x, const Offset(500, 560), 250, blink: _blink(x.t));
    for (final (i, p) in const [Offset(170, 170), Offset(850, 190), Offset(900, 760), Offset(110, 740)].indexed) {
      _twinkle(x, p, 46 * math.max(0, x.wave(0.9, i * 1.7)) * x.amp, const Color(0xFFFFC93C));
    }
  }),
  'heart': _Style(const Color(0xFFFF6F91), (x) {
    // Lub-dub.
    final q = x.t % 0.85;
    double bump(double at) => math.exp(-math.pow((q - at) / 0.055, 2).toDouble());
    x.grow(const Offset(500, 560), 1 + 0.09 * (bump(0.1) + 0.6 * bump(0.3)) * x.amp);
    x.shape();
    _shine(x, const Offset(290, 330), 110, 52, -0.6, 0.55);
    _face(x, const Offset(500, 520), 270, blink: _blink(x.t, at: 0.9));
  }),
  'house': _Style(
    const Color(0xFFFFE3B8),
    (x) {
      // Smoke curls up out of the chimney.
      for (var k = 0; k < 3; k++) {
        final p = (x.t * 0.55 + k / 3) % 1;
        x.c.drawCircle(Offset(650 + 24 * math.sin(p * 5 + k), 150 - p * 140), 20 + 34 * p, x.fill(const Color(0xFFC9C2DA), (1 - p) * x.amp));
      }
      x.shape();
      final door = Path()..addRRect(RRect.fromLTRBAndCorners(440, 650, 560, 830, topLeft: const Radius.circular(60), topRight: const Radius.circular(60)));
      x.c.drawPath(door, x.fill(const Color(0xFF9C6B4E)));
      x.c.drawPath(door, x.stroke(x.dark, 10));
      x.c.drawCircle(const Offset(535, 745), 11, x.fill(const Color(0xFFFFC93C)));
      // The lights come on.
      final glow = ((x.t - 0.8) / 0.5).clamp(0.0, 1.0);
      for (final left in const [270.0, 620.0]) {
        final w = Rect.fromLTWH(left, 540, 110, 100);
        x.c.drawRect(w, x.fill(Color.lerp(const Color(0xFF9AD7FF), const Color(0xFFFFE57A), glow)!));
        x.c.drawRect(w, x.stroke(x.dark, 10));
        x.c.drawLine(Offset(w.center.dx, w.top), Offset(w.center.dx, w.bottom), x.stroke(x.dark, 8));
        x.c.drawLine(Offset(w.left, w.center.dy), Offset(w.right, w.center.dy), x.stroke(x.dark, 8));
      }
    },
    regions: () => [
      (_poly([500, 150, 780, 480, 220, 480]), const Color(0xFFE8574F)),
      (_poly([600, 170, 700, 170, 700, 386, 600, 268]), const Color(0xFFC0603F)),
    ],
  ),
  'fish': _Style(
    const Color(0xFFFF9F43),
    (x) {
      x.shift(28 * x.wave(0.45) * x.amp, 14 * x.wave(0.9) * x.amp);
      x.turn(const Offset(500, 520), 0.06 * x.wave(0.9, 0.6) * x.amp);
      x.shape();
      x.c.drawCircle(const Offset(290, 470), 44, x.fill(Colors.white));
      x.c.drawCircle(const Offset(290, 470), 44, x.stroke(x.dark, 8));
      x.c.drawCircle(Offset(280, 474 + 4 * x.wave(0.5)), 24, x.fill(_faceInk));
      x.c.drawCircle(const Offset(272, 464), 8, x.fill(Colors.white));
      x.c.drawPath(_curve([168, 572, 212, 604, 256, 584]), x.stroke(_faceInk, 12));
      // Bubbles from its mouth.
      for (var k = 0; k < 3; k++) {
        final p = (x.t * 0.6 + k / 3) % 1;
        x.c.drawCircle(Offset(80 - 20 * p + 12 * math.sin(p * 7 + k), 470 - p * 340), 14 + 20 * p, x.stroke(const Color(0xFF6EC6FF), 8, (1 - p) * x.amp));
      }
    },
    regions: () => [
      (_rect(700, 0, 1000, 1000), const Color(0xFFFF7A2F)),
      (_rect(440, 0, 490, 1000)..addRect(const Rect.fromLTRB(560, 0, 605, 1000)), const Color(0xFFFFC27A)),
    ],
  ),
  'balloon': _Style(const Color(0xFFF2645A), (x) {
    x.shift(0, -22 * x.wave(0.4) * x.amp);
    x.turn(const Offset(500, 960), 0.07 * x.wave(0.55) * x.amp);
    final w = 22 * x.wave(1.1) * x.amp;
    x.c.drawPath(_curve([500, 790, 530 + w, 850, 470 - w, 905, 505 + w / 2, 960]), x.stroke(const Color(0xFF8A80A8), 8));
    x.shape();
    x.c.drawPath(_poly([500, 760, 532, 800, 468, 800]), x.fill(x.dark));
    _shine(x, const Offset(370, 250), 80, 150, -0.5);
  }),
  'apple': _Style(const Color(0xFFEF4C4C), (x) {
    // Hops, squashing a little as it lands.
    final b = math.sin(x.t * math.pi * 1.4).abs();
    x.shift(0, -40 * b * x.amp);
    x.grow(const Offset(500, 850), 1 + 0.05 * (1 - b) * x.amp, 1 - 0.06 * (1 - b) * x.amp);
    x.c.drawPath(_curve([500, 310, 505, 250, 525, 190]), x.stroke(const Color(0xFF7A4E2D), 24));
    final leaf = _blob([545, 225, 610, 175, 690, 185, 640, 245]);
    x.c.drawPath(leaf, x.fill(const Color(0xFF6CC56A)));
    x.c.drawPath(leaf, x.stroke(const Color(0xFF3F8F4A), 9));
    x.shape();
    _shine(x, const Offset(320, 420), 70, 130, 0.35, 0.45);
    _face(x, const Offset(500, 580), 240, blink: _blink(x.t, at: 1.6));
  }),
  'rocket': _Style(
    const Color(0xFFEEF2FA),
    (x) {
      // Engines on: it shakes, then starts to lift.
      final lift = Curves.easeIn.transform((x.t / 4.4).clamp(0.0, 1.0));
      x.shift(3 * x.wave(14) * x.amp, -70 * lift * x.amp);
      final h = (110 + 35 * x.wave(7) + 20 * x.wave(11.3)) * x.amp;
      if (h > 4) {
        x.c.drawPath(_flame(500, 866, 70, h), x.fill(const Color(0xFFFF8A3C)));
        x.c.drawPath(_flame(500, 866, 40, h * 0.62), x.fill(const Color(0xFFFFD54F)));
      }
      x.shape();
      x.c.drawCircle(const Offset(500, 420), 78, x.fill(const Color(0xFF6EC6FF)));
      x.c.drawCircle(const Offset(500, 420), 78, x.stroke(const Color(0xFFB4BFD6), 18));
      x.c.drawCircle(const Offset(476, 396), 18, x.fill(Colors.white, 0.8));
    },
    regions: () => [
      (_rect(0, 0, 1000, 235), const Color(0xFFF2645A)),
      (_rect(0, 600, 392, 1000)..addRect(const Rect.fromLTRB(608, 600, 1000, 1000)), const Color(0xFFF2645A)),
    ],
  ),
  'whale': _Style(
    const Color(0xFF6EA8F0),
    (x) {
      x.shift(0, 12 * x.wave(0.6) * x.amp);
      x.turn(const Offset(480, 520), 0.035 * x.wave(0.6, 1) * x.amp);
      // The spout, in bursts.
      final p = (x.t * 0.8) % 1;
      final up = math.sin(p * math.pi) * x.amp;
      if (up > 0.05) {
        final top = 290 - 230 * up;
        x.c.drawLine(const Offset(380, 290), Offset(380, top), x.stroke(const Color(0xFF8FD3FF), 22));
        for (final s in const [-1.0, 0.0, 1.0]) {
          x.c.drawCircle(Offset(380 + s * 75 * up, top + (s == 0 ? -10 : 30) * up), 20 * up + 6, x.fill(const Color(0xFF8FD3FF), 1 - p * 0.5));
        }
      }
      x.shape();
      x.c.drawCircle(const Offset(250, 510), 26, x.fill(_faceInk));
      x.c.drawCircle(const Offset(242, 501), 8, x.fill(Colors.white));
      x.c.drawPath(_curve([140, 612, 192, 640, 250, 628]), x.stroke(_faceInk, 12));
      x.c.drawOval(Rect.fromCenter(center: const Offset(300, 590), width: 60, height: 34), x.fill(_cheek));
    },
    regions: () => [
      (Path()..addOval(Rect.fromCenter(center: const Offset(440, 705), width: 680, height: 230)), const Color(0xFFCFE4FF)),
    ],
  ),
  'crown': _Style(
    const Color(0xFFFFC93C),
    (x) {
      x.turn(const Offset(500, 800), 0.06 * x.wave(0.7) * x.amp);
      x.shift(0, -14 * math.sin(x.t * math.pi * 1.4).abs() * x.amp);
      x.shape();
      for (final (p, color) in const [(Offset(320, 730), Color(0xFFE84A5F)), (Offset(500, 730), Color(0xFF4C7BF4)), (Offset(680, 730), Color(0xFF4CC46A))]) {
        x.c.drawCircle(p, 36, x.fill(color));
        x.c.drawCircle(p, 36, x.stroke(x.dark, 8));
        x.c.drawCircle(p + const Offset(-11, -12), 9, x.fill(Colors.white, 0.8));
      }
      for (final p in const [Offset(170, 330), Offset(500, 230), Offset(830, 330)]) {
        x.c.drawCircle(p, 34, x.fill(const Color(0xFFFFE57A)));
        x.c.drawCircle(p, 34, x.stroke(x.dark, 9));
      }
      for (final (i, p) in const [Offset(330, 140), Offset(690, 130), Offset(90, 600), Offset(910, 560)].indexed) {
        _twinkle(x, p, 44 * math.max(0, x.wave(0.8, i * 1.3)) * x.amp, const Color(0xFFFFC93C));
      }
      _twinkle(x, const Offset(500, 450), 40 * math.max(0, x.wave(0.8, 2.2)) * x.amp, Colors.white);
    },
    regions: () => [(_rect(0, 660, 1000, 1000), const Color(0xFFF2A93B))],
  ),
  'butterfly': _Style(
    const Color(0xFFB48CF0),
    (x) {
      x.shift(0, -16 * x.wave(0.55) * x.amp);
      // The wings fold toward the body and open again; the body stays.
      final open = 0.5 + 0.5 * math.cos(x.t * 2 * math.pi * 1.1);
      x.c.save();
      x.grow(const Offset(500, 500), 1 - 0.45 * (1 - open) * x.amp, 1);
      x.shape();
      for (final s in const [-1.0, 1.0]) {
        x.c.drawCircle(Offset(500 + s * 165, 320), 52, x.fill(Colors.white, 0.75));
        x.c.drawCircle(Offset(500 + s * 165, 320), 26, x.fill(const Color(0xFFFF8FB8)));
        x.c.drawCircle(Offset(500 + s * 160, 680), 38, x.fill(const Color(0xFFFFE066)));
      }
      x.c.restore();
      const body = Color(0xFF4A3F6B);
      x.c.drawRRect(RRect.fromLTRBR(470, 320, 530, 760, const Radius.circular(30)), x.fill(body));
      x.c.drawCircle(const Offset(500, 300), 42, x.fill(body));
      for (final s in const [-1.0, 1.0]) {
        x.c.drawPath(_curve([500 + s * 12, 268, 500 + s * 50, 200, 500 + s * 95, 160]), x.stroke(body, 10));
        x.c.drawCircle(Offset(500 + s * 95, 160), 14, x.fill(body));
        x.c.drawCircle(Offset(500 + s * 15, 294), 7, x.fill(Colors.white));
      }
      x.c.drawPath(_curve([488, 316, 500, 322, 512, 316]), x.stroke(Colors.white, 5));
    },
    regions: () => [(_rect(0, 505, 1000, 1000), const Color(0xFFFF8FB8))],
  ),
  'cat': _Style(const Color(0xFFFFA54F), (x) {
    x.turn(const Offset(500, 820), 0.07 * x.wave(0.5) * x.amp);
    x.shape();
    for (final ear in [_poly([248, 224, 341, 312, 221, 373]), _poly([752, 224, 659, 312, 779, 373])]) {
      x.c.drawPath(ear, x.fill(const Color(0xFFFF9EB5)));
    }
    for (final s in const [-1.0, 1.0]) {
      x.c.drawOval(Rect.fromCenter(center: Offset(500 + s * 52, 655), width: 120, height: 88), x.fill(const Color(0xFFFFF4E6)));
      x.c.drawOval(Rect.fromCenter(center: Offset(500 + s * 215, 610), width: 70, height: 40), x.fill(_cheek));
    }
    final b = _blink(x.t, every: 1.9, at: 0.7);
    for (final s in const [-1.0, 1.0]) {
      final eye = Offset(500 + s * 125, 520);
      x.c.drawOval(Rect.fromCenter(center: eye, width: 50, height: 70 * (1 - 0.9 * b)), x.fill(_faceInk));
      if (b < 0.5) x.c.drawCircle(eye + const Offset(9, -13), 9, x.fill(Colors.white));
    }
    x.c.drawPath(_poly([472, 600, 528, 600, 500, 632]), x.fill(const Color(0xFFFF6F91)));
    x.c.drawPath(_curve([500, 632, 480, 668, 450, 662]), x.stroke(_faceInk, 9));
    x.c.drawPath(_curve([500, 632, 520, 668, 550, 662]), x.stroke(_faceInk, 9));
    // Whiskers twitch.
    final tw = 8 * x.wave(1.3) * x.amp;
    for (final s in const [-1.0, 1.0]) {
      for (final k in const [-1.0, 0.0, 1.0]) {
        x.c.drawLine(Offset(500 + s * 110, 650 + k * 22), Offset(500 + s * 270, 630 + k * 45 + tw), x.stroke(const Color(0xFF6B4A3A), 7));
      }
    }
  }),
  'sun': _Style(const Color(0xFFFFB938), (x) {
    const middle = Offset(500, 500);
    x.grow(middle, 1 + 0.03 * x.wave(0.8) * x.amp);
    // The rays turn; the face stays upright.
    x.c.save();
    x.turn(middle, x.t * 0.5 * x.amp);
    x.shape();
    x.c.restore();
    x.c.drawCircle(middle, 262, x.fill(const Color(0xFFFFE066)));
    x.c.drawCircle(middle, 262, x.stroke(const Color(0xFFF2A93B), 10));
    _face(x, const Offset(500, 520), 300, blink: _blink(x.t, at: 1.0));
  }),
  'umbrella': _Style(
    const Color(0xFF4DD0C4),
    (x) {
      // Rain falls around it and stops on the canopy.
      for (var k = 0; k < 14; k++) {
        final px = 60 + 880 * ((k * 0.618034) % 1);
        final py = -40 + (x.t * 650 + k * 173) % 1040;
        final canopy = (px - 500).abs() < 390 ? 110 + 400 * math.pow((px - 500) / 390, 2) : 960.0;
        if (py > canopy) continue;
        x.c.drawLine(Offset(px, py), Offset(px - 8, py + 38), x.stroke(const Color(0xFF6EC6FF), 9, x.amp));
      }
      x.turn(const Offset(500, 860), 0.05 * x.wave(0.5) * x.amp);
      final handle = Path()
        ..moveTo(500, 540)
        ..lineTo(500, 820)
        ..arcToPoint(const Offset(420, 820), radius: const Radius.circular(40))
        ..lineTo(420, 800);
      x.c.drawPath(handle, x.stroke(const Color(0xFF8D5A3B), 22));
      x.c.drawLine(const Offset(500, 140), const Offset(500, 100), x.stroke(x.dark, 14));
      x.shape();
    },
    regions: () => [
      (_poly([500, 140, 766, 700, 500, 700])..addPolygon(const [Offset(500, 140), Offset(234, 700), Offset(-32, 700)], true), const Color(0xFF34B1A6)),
    ],
  ),
  'car': _Style(
    const Color(0xFFF2645A),
    (x) {
      // Puffs from the exhaust drift back.
      for (var k = 0; k < 3; k++) {
        final p = (x.t * 0.9 + k / 3) % 1;
        x.c.drawCircle(Offset(110 - 110 * p, 670 - 40 * p), 12 + 26 * p, x.fill(const Color(0xFFD9D4E4), (1 - p) * 0.9 * x.amp));
      }
      x.shift(10 * x.wave(0.35) * x.amp, -7 * math.sin(x.t * 2 * math.pi * 2.2).abs() * x.amp);
      x.shape();
      x.c.drawLine(const Offset(480, 535), const Offset(480, 690), x.stroke(x.dark, 8));
      x.c.drawRRect(RRect.fromLTRBR(505, 560, 555, 576, const Radius.circular(8)), x.fill(x.dark));
      x.c.drawOval(Rect.fromCenter(center: const Offset(850, 600), width: 34, height: 46), x.fill(const Color(0xFFFFE066)));
      x.c.drawRRect(RRect.fromLTRBR(132, 585, 152, 625, const Radius.circular(6)), x.fill(const Color(0xFFB8323F)));
      // The wheels turn.
      final spin = x.t * 7 * x.amp;
      for (final w in const [Offset(330, 700), Offset(730, 700)]) {
        x.c.drawCircle(w, 62, x.fill(const Color(0xFF3B3355)));
        x.c.drawCircle(w, 28, x.fill(const Color(0xFFD9D2EC)));
        for (var k = 0; k < 4; k++) {
          final d = Offset(math.cos(spin + k * math.pi / 2), math.sin(spin + k * math.pi / 2));
          x.c.drawLine(w + d * 10, w + d * 50, x.stroke(const Color(0xFFD9D2EC), 9));
        }
      }
    },
    regions: () => [
      (_poly([290, 515, 362, 412, 470, 404, 470, 515])..addPolygon(const [Offset(495, 402), Offset(600, 395), Offset(690, 512), Offset(495, 515)], true), const Color(0xFFCDEBFF)),
    ],
  ),
  'icecream': _Style(
    const Color(0xFFE8B36A),
    (x) {
      x.turn(const Offset(500, 870), 0.05 * x.wave(0.7) * x.amp);
      x.shape();
      // Sprinkles land one by one.
      const sprinkles = [
        (380.0, 330.0, 0.5, Color(0xFF4C7BF4)), (450.0, 262.0, -0.4, Color(0xFFFFD54F)), (560.0, 282.0, 0.9, Color(0xFF4CC46A)), //
        (622.0, 362.0, -0.2, Color(0xFFFFFFFF)), (342.0, 420.0, 1.2, Color(0xFFB48CF0)), (500.0, 382.0, 0.1, Color(0xFFFF7A2F)),
        (432.0, 442.0, -0.9, Color(0xFF4DD0C4)), (602.0, 440.0, 0.6, Color(0xFFFFD54F)),
      ];
      for (final (i, (sx, sy, angle, color)) in sprinkles.indexed) {
        final pop = Curves.easeOutBack.transform(((x.t - 0.2 - i * 0.12) / 0.3).clamp(0.0, 1.0));
        if (pop <= 0) continue;
        x.c.save();
        x.c.translate(sx, sy);
        x.c.rotate(angle);
        x.c.scale(pop);
        x.c.drawRRect(RRect.fromLTRBR(-22, -8, 22, 8, const Radius.circular(8)), x.fill(color));
        x.c.restore();
      }
      // A cherry bounces on top.
      final cherry = Offset(500, 160 - 40 * math.sin(x.t * math.pi * 1.5).abs() * x.amp);
      x.c.drawPath(_curve([cherry.dx, cherry.dy - 30, cherry.dx + 20, cherry.dy - 75, cherry.dx + 50, cherry.dy - 95]), x.stroke(const Color(0xFF6B4A3A), 9));
      x.c.drawCircle(cherry, 42, x.fill(const Color(0xFFE8374B)));
      x.c.drawCircle(cherry, 42, x.stroke(const Color(0xFF8E1F33), 8));
      x.c.drawCircle(cherry + const Offset(-13, -14), 10, x.fill(Colors.white, 0.8));
    },
    regions: () => [
      (Path.combine(PathOperation.intersect, _waffle(), _poly([290, 482, 710, 482, 500, 870])), const Color(0xFFC98F45)),
      (
        _rect(0, 0, 1000, 482)
          ..addOval(Rect.fromCircle(center: const Offset(365, 482), radius: 38))
          ..addOval(Rect.fromCircle(center: const Offset(465, 500), radius: 50))
          ..addOval(Rect.fromCircle(center: const Offset(580, 488), radius: 42))
          ..addOval(Rect.fromCircle(center: const Offset(660, 478), radius: 30)),
        const Color(0xFFFF8FB8),
      ),
    ],
  ),
};
