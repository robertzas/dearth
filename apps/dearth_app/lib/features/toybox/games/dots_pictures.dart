import 'dart:math' as math;
import 'dart:ui' as ui show PathMetric;

import 'package:material_ui/material_ui.dart';

/// Dot-to-Dot's pictures (SPEC FR-TOY-03, Appendix B), drawn in code. Each
/// picture is a single closed outline in a 1000 × 1000 box, built from
/// anchors flagged corner (a sharp point) or smooth (a gentle curve). The
/// dots sit on the outline at even arc lengths, snapped onto corners nearby,
/// and connecting them draws the *real* outline (curves included), so even
/// five dots make the shape. When it's done, the picture fills in and comes
/// alive for a few seconds.

/// One anchor of an outline: `(x, y, corner)` in the 1000 box, in drawing
/// order around the shape.
typedef Anchor = (double, double, bool);

class DotArt {
  const DotArt(this.id, this.anchors, this.center);
  final String id;
  final List<Anchor> anchors;

  /// Where the finished picture's alive motion turns around.
  final Offset center;
}

const _star = DotArt('star', [
  (500, 150, true), (588, 399, true), (643, 474, true), (643, 566, true), (588, 641, true), (500, 670, true), (412, 641, true), (357, 566, true), (357, 474, true), (412, 399, true),
], Offset(500, 480));

const _heart = DotArt('heart', [
  (500, 330, true), (720, 210, false), (860, 410, false), (500, 830, true), (140, 410, false), (280, 210, false),
], Offset(500, 520));

const _house = DotArt('house', [
  (500, 160, true), (760, 470, true), (760, 820, true), (240, 820, true), (240, 470, true),
], Offset(500, 540));

const _fish = DotArt('fish', [
  (160, 520, false), (400, 320, false), (690, 430, false), (880, 260, true), (770, 520, true), (880, 780, true), (690, 610, false), (400, 720, false),
], Offset(480, 520));

const _balloon = DotArt('balloon', [
  (500, 60, false), (800, 380, false), (560, 690, false), (500, 760, true), (440, 690, false), (200, 380, false),
], Offset(500, 760));

const _apple = DotArt('apple', [
  (500, 300, true), (690, 270, false), (810, 520, false), (660, 800, false), (500, 850, false), (340, 800, false), (190, 520, false), (310, 270, false),
], Offset(500, 560));

const _rocket = DotArt('rocket', [
  (500, 90, true), (600, 300, false), (615, 560, false), (740, 700, true), (620, 775, true), (560, 845, true), (440, 845, true), (380, 775, true), (260, 700, true), (385, 560, false), (400, 300, false),
], Offset(500, 470));

const _whale = DotArt('whale', [
  (170, 560, false), (350, 320, false), (580, 290, false), (760, 340, false), (850, 190, true), (790, 310, false), (890, 390, true), (810, 470, false), (560, 700, false), (290, 710, false),
], Offset(500, 510));

const _crown = DotArt('crown', [
  (240, 730, true), (240, 560, true), (330, 300, true), (420, 430, true), (500, 240, true), (580, 430, true), (670, 300, true), (760, 560, true), (760, 730, true),
], Offset(500, 490));

const _butterfly = DotArt('butterfly', [
  (500, 310, false), (690, 220, false), (770, 420, false), (575, 510, false), (690, 650, false), (515, 760, false), (485, 760, false), (310, 650, false), (425, 510, false), (230, 420, false), (310, 220, false),
], Offset(500, 500));

const _cat = DotArt('cat', [
  (320, 420, true), (260, 230, true), (500, 340, false), (740, 230, true), (840, 420, true), (870, 620, false), (500, 800, false), (130, 620, false),
], Offset(500, 560));

final _sun = DotArt('sun', [
  for (var k = 0; k < 16; k++)
    (
      500 + (k.isEven ? 430 : 295) * math.cos(-math.pi / 2 + k * math.pi / 8),
      500 + (k.isEven ? 430 : 295) * math.sin(-math.pi / 2 + k * math.pi / 8),
      true
    ),
], const Offset(500, 500));

const _umbrella = DotArt('umbrella', [
  (500, 155, true), (620, 165, false), (720, 260, false), (850, 560, true), (780, 400, false), (710, 560, true), (640, 400, false), (570, 560, true), (500, 400, false), (430, 560, true), (360, 400, false), (290, 560, true), (220, 400, false), (150, 560, true), (280, 260, false), (380, 165, false),
], Offset(500, 470));

const _car = DotArt('car', [
  (150, 720, true), (150, 540, true), (260, 500, true), (360, 390, true), (620, 360, true), (730, 410, true), (860, 540, true), (870, 700, true), (800, 720, true), (730, 590, true), (660, 720, true), (420, 720, true), (350, 590, true), (280, 720, true),
], Offset(500, 540));

const _icecream = DotArt('icecream', [
  (300, 470, true), (340, 280, false), (500, 210, false), (660, 280, false), (700, 470, true), (500, 860, true),
], Offset(500, 420));

final List<DotArt> _all = [_star, _heart, _house, _fish, _balloon, _apple, _rocket, _whale, _crown, _butterfly, _cat, _sun, _umbrella, _car, _icecream];

/// The outlines by id (matching `kDotPictures` in dearth_core).
final Map<String, DotArt> dotArts = {for (final a in _all) a.id: a};

/// A picture's outline anchors and center.
DotArt dotArtOf(String id) => dotArts[id]!;

/// The closed outline through the anchors, in the 1000 box: straight
/// between corners, and a Catmull-Rom curve between smooth anchors that
/// eases out of a corner rather than whips round it.
Path outlineOf(DotArt art) {
  final pts = [for (final a in art.anchors) Offset(a.$1, a.$2)];
  final corner = [for (final a in art.anchors) a.$3];
  final n = pts.length;
  final path = Path()..moveTo(pts[0].dx, pts[0].dy);
  for (var i = 0; i < n; i++) {
    final am = pts[(i - 1 + n) % n], a0 = pts[i], a1 = pts[(i + 1) % n], a2 = pts[(i + 2) % n];
    final c1 = corner[i] ? a0 + (a1 - a0) / 3 : a0 + (a1 - am) / 6;
    final c2 = corner[(i + 1) % n] ? a1 - (a1 - a0) / 3 : a1 - (a2 - a0) / 6;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, a1.dx, a1.dy);
  }
  return path..close();
}

/// An outline scaled to a square board, with the dots' positions along it.
class DotGeometry {
  DotGeometry._(this.path, this.metric, this.dots);

  /// The outline scaled to the board (a 0…board square).
  final Path path;
  final ui.PathMetric metric;

  /// The dots' arc offsets along the outline (ascending; join order).
  final List<double> dots;

  static final Map<(String, int, int), DotGeometry> _cache = {};

  /// [count] dots for [art] on a board of [board] px (board size is
  /// quantized so geometry rebuilds rarely).
  factory DotGeometry.forBoard(DotArt art, int count, double board) {
    final q = (board / 4).round() * 4;
    final key = (art.id, count, q);
    final cached = _cache[key];
    if (cached != null) return cached;
    if (_cache.length > 24) _cache.clear();
    final path = outlineOf(art).transform(Matrix4.diagonal3Values(q / 1000, q / 1000, 1).storage);
    final metric = path.computeMetrics().single;
    final l = metric.length;

    // Where each anchor lands along the path (anchors lie on it exactly),
    // so dots can snap onto corners.
    const samples = 3200;
    final along = [for (var i = 0; i <= samples; i++) metric.getTangentForOffset(l * i / samples)!.position];
    final anchorArcs = <double>[
      for (final a in art.anchors)
        () {
          final target = Offset(a.$1, a.$2) * (q / 1000);
          var best = 0;
          var bestD = double.infinity;
          for (var i = 0; i <= samples; i++) {
            final d = (along[i] - target).distanceSquared;
            if (d < bestD) {
              bestD = d;
              best = i;
            }
          }
          return l * best / samples;
        }(),
    ];

    // [count] dots at even arc lengths; each is the start of the segment she
    // draws, so dot 1 sits at the first anchor (arc 0).
    final spacing = l / count;
    final dots = <double>[];
    for (var k = 0; k < count; k++) {
      var arc = (spacing * k) % l;
      var bestD = double.infinity, bestA = -1.0;
      for (final a in anchorArcs) {
        var d = (a - arc).abs();
        d = math.min(d, l - d);
        if (d < bestD) {
          bestD = d;
          bestA = a;
        }
      }
      if (bestD < spacing * 0.3) arc = bestA;
      dots.add(arc);
    }
    dots.sort();
    final g = DotGeometry._(path, metric, dots);
    _cache[key] = g;
    return g;
  }

  /// Dot [index] (0-based, join order) on the board.
  Offset dotAt(int index) => metric.getTangentForOffset(dots[index])!.position;

  /// The line so far once [joined] dots are joined: the dots label the
  /// outline in order, so it's the whole outline up to the last one (and
  /// the full closed path when all are joined).
  Path drawnPath(int joined) {
    if (joined <= 0) return Path();
    if (joined >= dots.length) return path;
    return metric.extractPath(0, dots[joined]);
  }
}
