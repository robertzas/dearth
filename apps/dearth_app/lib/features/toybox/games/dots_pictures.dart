import 'dart:math' as math;
import 'dart:ui' as ui show PathMetric;

import 'package:material_ui/material_ui.dart';

/// Dot-to-Dot's pictures (SPEC FR-TOY-03, Appendix B), drawn in code. Each
/// picture is one closed outline in a 1000 × 1000 box, through anchors
/// flagged corner (a sharp point) or smooth (a gentle curve). A dot sits on
/// every corner and the other dots share the gaps between them evenly, so
/// the dots alone already hint at the shape; joining two dots draws the real
/// outline between them (curves included), so even five dots make the
/// picture.

/// One anchor of an outline: `(x, y, corner)` in the 1000 box, in drawing
/// order around the shape. Anchor 0 is where dot 1 (or A) sits.
typedef Anchor = (double, double, bool);

class DotArt {
  const DotArt(this.id, this.anchors);
  final String id;
  final List<Anchor> anchors;
}

// Corners at the points, so every point gets a dot; the inner corners are
// wide enough apart that the dots beside a point never crowd.
const _star = DotArt('star', [
  (500, 120, true), (611, 377, true), (890, 403, true), (680, 588, true), (741, 862, true), //
  (500, 719, true), (259, 862, true), (320, 588, true), (110, 403, true), (389, 377, true),
]);

const _heart = DotArt('heart', [
  (500, 300, true), (720, 170, false), (880, 390, false), (500, 850, true), (120, 390, false), (280, 170, false),
]);

// The chimney is part of the outline, so the line she draws already says
// "house"; its smoke comes out of the top.
const _house = DotArt('house', [
  (500, 150, true), (600, 268, true), (600, 170, true), (700, 170, true), (700, 386, true), //
  (780, 480, true), (780, 830, true), (220, 830, true), (220, 480, true),
]);

// A fan tail: a forked one pinches its dots together at the tips or in
// the fork.
const _fish = DotArt('fish', [
  (110, 520, false), (370, 310, false), (680, 410, false), (880, 240, true), (940, 520, false), //
  (880, 800, true), (680, 630, false), (370, 730, false),
]);

// Round on top, narrowing to the knot.
const _balloon = DotArt('balloon', [
  (500, 60, false), (700, 110, false), (810, 300, false), (770, 520, false), (620, 690, false), //
  (500, 770, true), (380, 690, false), (230, 520, false), (190, 300, false), (300, 110, false),
]);

const _apple = DotArt('apple', [
  (500, 300, true), (690, 260, false), (820, 510, false), (670, 800, false), (500, 850, false), //
  (330, 800, false), (180, 510, false), (310, 260, false),
]);

const _rocket = DotArt('rocket', [
  (500, 80, true), (610, 280, false), (625, 540, false), (775, 730, true), (630, 800, true), //
  (575, 865, true), (425, 865, true), (370, 800, true), (225, 730, true), (375, 540, false), (390, 280, false),
]);

// A round body, the tail stock rising at the back, and two flukes.
const _whale = DotArt('whale', [
  (90, 560, false), (180, 380, false), (390, 300, false), (600, 330, false), (720, 410, false), //
  (770, 330, false), (720, 170, true), (830, 230, true), (930, 150, true), (890, 330, false), //
  (830, 480, false), (700, 630, false), (450, 710, false), (210, 690, false),
]);

const _crown = DotArt('crown', [
  (170, 330, true), (360, 520, true), (500, 230, true), (640, 520, true), (830, 330, true), (780, 800, true), (220, 800, true),
]);

const _butterfly = DotArt('butterfly', [
  (500, 330, true), (640, 170, false), (830, 210, false), (840, 410, false), (560, 500, true), //
  (770, 600, false), (750, 770, false), (600, 810, false), (500, 710, true), (400, 810, false), //
  (250, 770, false), (230, 600, false), (440, 500, true), (160, 410, false), (170, 210, false), (360, 170, false),
]);

const _cat = DotArt('cat', [
  (230, 160, true), (400, 320, true), (500, 300, false), (600, 320, true), (770, 160, true), //
  (820, 430, true), (860, 610, false), (500, 820, false), (140, 610, false), (180, 430, true),
]);

// Eight rays: points at 430, the valleys between them at 300.
final _sun = DotArt('sun', [
  for (var k = 0; k < 16; k++)
    (
      500 + (k.isEven ? 430 : 300) * math.cos(-math.pi / 2 + k * math.pi / 8),
      500 + (k.isEven ? 430 : 300) * math.sin(-math.pi / 2 + k * math.pi / 8),
      true,
    ),
]);

// A dome with four shallow scallops between the rib tips; the handle is
// drawn when the picture is done.
const _umbrella = DotArt('umbrella', [
  (500, 140, true), (700, 190, false), (840, 330, false), (880, 540, true), (785, 490, false), //
  (690, 540, true), (595, 490, false), (500, 540, true), (405, 490, false), (310, 540, true), //
  (215, 490, false), (120, 540, true), (160, 330, false), (300, 190, false),
]);

// Round wheel arches (the wheels go in them at the end).
const _car = DotArt('car', [
  (130, 700, true), (130, 560, true), (260, 520, true), (350, 390, true), (610, 380, true), //
  (720, 510, true), (860, 550, true), (880, 700, true), (800, 700, true), (779, 651, false), //
  (730, 630, false), (681, 651, false), (660, 700, true), (400, 700, true), (379, 651, false), //
  (330, 630, false), (281, 651, false), (260, 700, true),
]);

const _icecream = DotArt('icecream', [
  (290, 480, true), (310, 300, false), (500, 190, false), (690, 300, false), (710, 480, true), (500, 870, true),
]);

final List<DotArt> _all = [_star, _heart, _house, _fish, _balloon, _apple, _rocket, _whale, _crown, _butterfly, _cat, _sun, _umbrella, _car, _icecream];

/// The outlines by id (matching `kDotPictures` in dearth_core).
final Map<String, DotArt> dotArts = {for (final a in _all) a.id: a};

/// A picture's outline.
DotArt dotArtOf(String id) => dotArts[id]!;

/// The outline's segments as cubic Béziers `(from, control 1, control 2,
/// to)`: segment i runs from anchor i to anchor i + 1, the last back to
/// anchor 0. Straight between two corners; a Catmull-Rom curve through
/// smooth anchors that eases out of a corner rather than whipping round it.
List<(Offset, Offset, Offset, Offset)> _segments(DotArt art) {
  final pts = [for (final a in art.anchors) Offset(a.$1, a.$2)];
  final corner = [for (final a in art.anchors) a.$3];
  final n = pts.length;
  return [
    for (var i = 0; i < n; i++)
      () {
        final am = pts[(i - 1 + n) % n], a0 = pts[i], a1 = pts[(i + 1) % n], a2 = pts[(i + 2) % n];
        final c1 = corner[i] ? a0 + (a1 - a0) / 3 : a0 + (a1 - am) / 6;
        final c2 = corner[(i + 1) % n] ? a1 - (a1 - a0) / 3 : a1 - (a2 - a0) / 6;
        return (a0, c1, c2, a1);
      }(),
  ];
}

Path _cubics(Iterable<(Offset, Offset, Offset, Offset)> segs) {
  final p = Path()..moveTo(segs.first.$1.dx, segs.first.$1.dy);
  for (final (_, c1, c2, b) in segs) {
    p.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, b.dx, b.dy);
  }
  return p;
}

/// The closed outline through the anchors, in the 1000 box.
Path outlineOf(DotArt art) => _cubics(_segments(art))..close();

/// Where a picture's dots sit for a round of [count] dots, in the 1000 box,
/// and the outline between them. Built once per picture and count.
class DotGeometry {
  DotGeometry._(this.art, this.path, this.metric, this.dots, this.points, this.minGap);

  /// The geometry for [count] dots on [art].
  factory DotGeometry.of(DotArt art, int count) => _cache[(art.id, count)] ??= _build(art, count);

  static final Map<(String, int), DotGeometry> _cache = {};

  final DotArt art;

  /// The closed outline.
  final Path path;
  final ui.PathMetric metric;

  /// Each dot's distance along the outline from anchor 0, in join order.
  final List<double> dots;

  /// Each dot's position.
  final List<Offset> points;

  /// The smallest distance between any two dots: dots are drawn smaller.
  final double minGap;

  double get length => metric.length;

  /// The outline from arc length [from] to [to].
  Path between(double from, double to) => metric.extractPath(from, to);

  static DotGeometry _build(DotArt art, int count) {
    final segs = _segments(art);
    final path = _cubics(segs)..close();
    final metric = path.computeMetrics().single;
    final l = metric.length;
    // Each anchor's arc length: the length of the segments before it.
    final arcs = <double>[0];
    for (final s in segs.take(segs.length - 1)) {
      arcs.add(arcs.last + _cubics([s]).computeMetrics().single.length);
    }
    // Dot 1 at the start, and one on every corner where there are enough.
    final fixed = [
      for (var i = 0; i < arcs.length; i++)
        if (i == 0 || art.anchors[i].$3) arcs[i],
    ];
    List<Offset> at(List<double> arcs) => [for (final a in arcs) metric.getTangentForOffset(a)!.position];
    var dots = fixed.length <= count ? _fillGaps(fixed, l, count) : _evenSnapped(fixed, l, count);
    var points = at(dots);
    // Corners close together (a whale's tail) would bunch a few dots in one
    // place and leave the rest of the shape bare: then even steps are better.
    if (fixed.length <= count) {
      final even = _evenSnapped(fixed, l, count);
      final evenPoints = at(even);
      if (_minGap(evenPoints) > 1.5 * _minGap(points)) {
        dots = even;
        points = evenPoints;
      }
    }
    return DotGeometry._(art, path, metric, dots, points, _minGap(points));
  }
}

/// How big a round's dots are on a [board] pixels wide: big when there are
/// few (a tenth of the board for five, for the youngest), smaller as they
/// multiply, and always smaller than the gap between the closest two, so no
/// two dots ever touch.
double dotDiameter(double board, DotGeometry g) => math.min(board * (0.115 - 0.002 * g.dots.length), g.minGap * board / 1000 * 0.92);

double _minGap(List<Offset> points) {
  var gap = double.infinity;
  for (var i = 0; i < points.length; i++) {
    for (var j = i + 1; j < points.length; j++) {
      gap = math.min(gap, (points[i] - points[j]).distance);
    }
  }
  return gap;
}

/// A dot on every fixed point, then the rest into the gaps between them,
/// each time splitting whichever gap is widest: as even as the corners
/// allow. Equal gaps (a star's arms) take turns around the shape, so one
/// side doesn't fill up first.
List<double> _fillGaps(List<double> fixed, double l, int count) {
  final m = fixed.length;
  double gap(int i) => (i + 1 < m ? fixed[i + 1] : l) - fixed[i];
  final extra = List<int>.filled(m, 0);
  var from = 0;
  for (var k = m; k < count; k++) {
    var best = 0;
    var span = -1.0;
    for (var j = 0; j < m; j++) {
      final i = (from + j) % m;
      final s = gap(i) / (extra[i] + 1);
      if (s > span * 1.001) {
        best = i;
        span = s;
      }
    }
    extra[best]++;
    from = (best + m ~/ 2) % m;
  }
  return [
    for (var i = 0; i < m; i++)
      for (var j = 0; j <= extra[i]; j++) fixed[i] + gap(i) * j / (extra[i] + 1),
  ];
}

/// Fewer dots than corners: even steps from the start, each moved onto a
/// corner less than a third of a step away, so the points that can have a
/// dot get one. (A step apart, two dots can never land on one corner.)
List<double> _evenSnapped(List<double> corners, double l, int count) {
  final step = l / count;
  return [
    for (var k = 0; k < count; k++)
      () {
        final arc = step * k;
        double? best;
        for (final c in corners) {
          final d = (c - arc).abs();
          if (d < step / 3 && (best == null || d < (best - arc).abs())) best = c;
        }
        return best ?? arc;
      }(),
  ];
}
