import 'dart:math';

import 'package:meta/meta.dart';

// Letter, name and number tracing (SPEC FR-TOY-03, Appendix B: lines →
// curves → letters → her own name; numbers 1–3 → 0–9). Glyphs are ball-and-
// stick shapes, the way preschools teach them, as strokes in writing order.
// The same shapes draw the letters in Letter Sounds, so she sees one "a"
// everywhere.

T _pick<T>(List<T> xs, Random rng) => xs[rng.nextInt(xs.length)];

/// Strokes in a box where capitals stand 10 units tall: y = 0 at the top,
/// 5 at the middle line, 10 on the baseline, descenders down to 14. Each
/// stroke is M x,y (start), L x,y (line), A cx,cy,rx,ry,from,to (an arc,
/// in degrees: 0 points right, 90 down, increasing turns clockwise) or
/// D x,y (a dot); strokes are split by "|".
const Map<String, String> _specs = {
  'A': 'M4,0 L0,10 | M4,0 L8,10 | M2,6 L6,6',
  'B': 'M0,0 L0,10 | M0,0 L3.5,0 A3.5,2.5,2.5,2.5,-90,90 L0,5 | M0,5 L4,5 A4,7.5,2.5,2.5,-90,90 L0,10',
  'C': 'A4.5,5,4.5,5,-40,-320',
  'D': 'M0,0 L0,10 | M0,0 L2,0 A2,5,5,5,-90,90 L0,10',
  'E': 'M0,0 L0,10 | M0,0 L6,0 | M0,5 L5,5 | M0,10 L6,10',
  'F': 'M0,0 L0,10 | M0,0 L6,0 | M0,5 L5,5',
  'G': 'A4.5,5,4.5,5,-40,-330 L8.4,5.5 L5.5,5.5',
  'H': 'M0,0 L0,10 | M7,0 L7,10 | M0,5 L7,5',
  'I': 'M2,0 L2,10 | M0,0 L4,0 | M0,10 L4,10',
  'J': 'M5,0 L5,7.5 A2.75,7.5,2.25,2.5,0,180',
  'K': 'M0,0 L0,10 | M6,0 L0.4,5.4 L6.5,10',
  'L': 'M0,0 L0,10 L6,10',
  'M': 'M0,0 L0,10 | M0,0 L4.5,6.5 L9,0 L9,10',
  'N': 'M0,0 L0,10 | M0,0 L7,10 L7,0',
  'O': 'A4.5,5,4.5,5,-90,-450',
  'P': 'M0,0 L0,10 | M0,0 L3.5,0 A3.5,2.75,2.75,2.75,-90,90 L0,5.5',
  'Q': 'A4.5,5,4.5,5,-90,-450 | M5.5,7 L9,10.5',
  'R': 'M0,0 L0,10 | M0,0 L3.5,0 A3.5,2.75,2.75,2.75,-90,90 L0,5.5 L6.5,10',
  'S': 'A3.5,2.5,3,2.5,-30,-270 A3.5,7.5,3.2,2.5,-90,150',
  'T': 'M0,0 L7,0 | M3.5,0 L3.5,10',
  'U': 'M0,0 L0,6.5 A3.5,6.5,3.5,3.5,180,0 L7,0',
  'V': 'M0,0 L4,10 L8,0',
  'W': 'M0,0 L2.75,10 L5.5,2.5 L8.25,10 L11,0',
  'X': 'M0,0 L7,10 | M7,0 L0,10',
  'Y': 'M0,0 L3.5,5 | M7,0 L3.5,5 L3.5,10',
  'Z': 'M0,0 L7,0 L0,10 L7,10',
  'a': 'A2.5,7.5,2.5,2.5,-30,-390 | M5,5 L5,10',
  'b': 'M0,0 L0,10 | A2.5,7.5,2.5,2.5,180,540',
  'c': 'A2.75,7.5,2.75,2.5,-40,-320',
  'd': 'A2.5,7.5,2.5,2.5,-30,-390 | M5,0 L5,10',
  'e': 'M0.2,7.5 L5,7.5 A2.6,7.5,2.4,2.5,0,-320',
  'f': 'A3.2,1.8,1.6,1.6,-20,-180 L1.6,10 | M0,5 L3.4,5',
  'g': 'A2.5,7.5,2.5,2.5,-30,-390 | M5,5 L5,12 A2.5,12,2.5,2,0,150',
  'h': 'M0,0 L0,10 | M0,7.5 A2.5,7.5,2.5,2.5,180,360 L5,10',
  'i': 'M0.5,5 L0.5,10 | D0.5,2.6',
  'j': 'M3,5 L3,12 A1.5,12,1.5,2,0,160 | D3,2.6',
  'k': 'M0,0 L0,10 | M4.5,5 L0.4,7.6 L5,10',
  'l': 'M0.5,0 L0.5,10',
  'm': 'M0,5 L0,10 | M0,7.2 A2,7.2,2,2.2,180,360 L4,10 | M4,7.2 A6,7.2,2,2.2,180,360 L8,10',
  'n': 'M0,5 L0,10 | M0,7.5 A2.5,7.5,2.5,2.5,180,360 L5,10',
  'o': 'A2.5,7.5,2.5,2.5,-90,-450',
  'p': 'M0,5 L0,14 | A2.5,7.5,2.5,2.5,180,540',
  'q': 'A2.5,7.5,2.5,2.5,-30,-390 | M5,5 L5,14',
  'r': 'M0,5 L0,10 | M0,7.5 A2.5,7.5,2.5,2.5,180,300',
  's': 'A2,6.25,1.8,1.25,-30,-270 A2,8.75,1.9,1.25,-90,150',
  't': 'M2,1.5 L2,10 | M0,5 L4,5',
  'u': 'M0,5 L0,7.5 A2.5,7.5,2.5,2.5,180,0 L5,5 | M5,5 L5,10',
  'v': 'M0,5 L2.5,10 L5,5',
  'w': 'M0,5 L2,10 L4,6 L6,10 L8,5',
  'x': 'M0,5 L5,10 | M5,5 L0,10',
  'y': 'M0,5 L2.5,10 | M5,5 L1.5,14',
  'z': 'M0,5 L5,5 L0,10 L5,10',
  '0': 'A3,5,3,5,-90,-450',
  '1': 'M1,1.5 L2.5,0 L2.5,10',
  '2': 'A3,3,2.8,2.8,-160,30 L0,10 L6,10',
  '3': 'A2.8,2.5,2.8,2.5,-150,90 A2.8,7.5,3,2.5,-90,150',
  '4': 'M0.5,0 L0.5,6 L7,6 | M5,0 L5,10',
  '5': 'M1.1,0 L1.07,4.7 A3,7,3,3,-130,150 | M1.1,0 L5.8,0',
  '6': 'A5,6.5,4.8,6,-92,-180 A3,7.2,2.8,2.8,180,-180',
  '7': 'M0,0 L6,0 L2,10',
  '8': 'A3,2.5,2.6,2.5,-30,-270 A3,7.5,3,2.5,-90,270 A3,2.5,2.6,2.5,90,-30',
  '9': 'A3,3,2.8,3,0,-360 L5.8,10',
  // Pre-writing strokes.
  'down': 'M0,0 L0,10',
  'across': 'M0,5 L9,5',
  'slant': 'M0,0 L8,10',
  'slant-back': 'M8,0 L0,10',
  'cross': 'M4,0 L4,10 | M0,5 L8,5',
  'zigzag': 'M0,2 L2.5,8 L5,2 L7.5,8 L10,2',
  'hill': 'A5,10,5,8,180,360',
  'cup': 'A5,2,5,8,180,0',
  'curve': 'A5,5,5,5,-40,-320',
  'circle': 'A5,5,5,5,-90,-450',
  'wave': 'A2.5,5,2.5,3,180,360 A7.5,5,2.5,3,180,0 A12.5,5,2.5,3,180,360',
};

/// Points along a stroke are this far apart (glyph units).
const double kTraceStep = 0.25;

/// A shape to trace: its strokes in writing order, each a run of points
/// [kTraceStep] apart (a dot is one point).
@immutable
class Glyph {
  const Glyph._(this.char, this.strokes, this.width, this.top, this.bottom);

  /// The character, or a pre-writing stroke's name ("zigzag").
  final String char;
  final List<List<Point<double>>> strokes;

  /// From x = 0.
  final double width;

  /// Where the ink starts and ends, top to bottom.
  final double top, bottom;

  /// Whether it's a pre-writing stroke rather than a letter or digit.
  bool get isStroke => char.length > 1;
}

final Map<String, Glyph> _glyphs = {};

/// Whether [char] can be traced.
bool hasGlyph(String char) => _specs.containsKey(char);

/// The glyph for [char] (a letter, a digit or a pre-writing stroke's name).
Glyph glyphFor(String char) => _glyphs[char] ??= _parse(char, _specs[char] ?? (throw ArgumentError.value(char, 'char', 'no glyph')));

Glyph _parse(String char, String spec) {
  final strokes = <List<Point<double>>>[];
  for (final part in spec.split('|')) {
    final pts = <Point<double>>[];
    void lineTo(Point<double> p) {
      if (pts.isEmpty) {
        pts.add(p);
        return;
      }
      final a = pts.last;
      final n = (a.distanceTo(p) / kTraceStep).ceil();
      for (var i = 1; i <= n; i++) {
        pts.add(Point(a.x + (p.x - a.x) * i / n, a.y + (p.y - a.y) * i / n));
      }
    }

    for (final cmd in part.trim().split(RegExp(r'\s+'))) {
      final v = [for (final s in cmd.substring(1).split(',')) double.parse(s)];
      switch (cmd[0]) {
        case 'M' || 'D':
          pts.add(Point(v[0], v[1]));
        case 'L':
          lineTo(Point(v[0], v[1]));
        case 'A':
          final (cx, cy, rx, ry, from, to) = (v[0], v[1], v[2], v[3], v[4] * pi / 180, v[5] * pi / 180);
          final n = max(2, ((to - from).abs() * max(rx, ry) / kTraceStep).ceil());
          for (var i = 0; i <= n; i++) {
            final a = from + (to - from) * i / n;
            final p = Point(cx + rx * cos(a), cy + ry * sin(a));
            // The first point joins the stroke (with a line if it doesn't
            // start where the last part ended).
            if (i == 0 && pts.isNotEmpty && pts.last.distanceTo(p) < kTraceStep) continue;
            if (i == 0) {
              lineTo(p);
            } else {
              pts.add(p);
            }
          }
        default:
          throw FormatException('bad glyph command "$cmd" in $char');
      }
    }
    strokes.add(pts);
  }
  final all = [for (final s in strokes) ...s];
  final minX = all.map((p) => p.x).reduce(min);
  final shifted = [
    for (final s in strokes) [for (final p in s) Point(p.x - minX, p.y)],
  ];
  return Glyph._(
    char,
    shifted,
    all.map((p) => p.x).reduce(max) - minX,
    all.map((p) => p.y).reduce(min),
    all.map((p) => p.y).reduce(max),
  );
}

// ──────────────────────────────── Tracing ───────────────────────────────────

/// What a finger did to a [Tracer].
enum TraceEvent {
  /// Nothing to follow there (a touch away from the green dot).
  none,

  /// Tracing a stroke (again).
  started,
  moved,

  /// Wandered off the path: tracing pauses where she left it.
  strayed,
  strokeDone,
  glyphDone,
}

/// Follows a finger along a [Glyph]'s strokes. A stroke starts at its green
/// dot and the ink only goes as far as the finger has followed the path, so
/// a scribble draws nothing and wandering off just pauses it: she picks up
/// where she left. Positions are in glyph units.
class Tracer {
  Tracer(this.glyph, {this.tolerance = 1.6});
  final Glyph glyph;

  /// How far from the path a finger may be (glyph units).
  final double tolerance;

  /// The stroke being traced; [Glyph.strokes].length when all are done.
  int stroke = 0;

  /// The farthest point reached on it.
  int reached = 0;

  /// Times the finger wandered off the path.
  int slips = 0;

  bool _active = false, _strayed = false;

  bool get done => stroke >= glyph.strokes.length;

  /// Whether a finger is tracing right now.
  bool get tracing => _active;

  /// Where the current stroke picks up: its start, or where she left it.
  Point<double>? get resume => done ? null : glyph.strokes[stroke][reached];

  /// Points ahead of [reached] a finger may jump to (about three units): a
  /// quick finger skips a few, but not a corner or a loop's other side.
  static const _window = 12;

  TraceEvent down(Point<double> p) {
    _strayed = false;
    if (done) return TraceEvent.none;
    final pts = glyph.strokes[stroke];
    if (p.distanceTo(pts[reached]) > tolerance * 1.4) return TraceEvent.none;
    if (pts.length == 1) return _finish(p);
    _active = true;
    return TraceEvent.started;
  }

  TraceEvent move(Point<double> p) {
    if (done) return TraceEvent.none;
    final pts = glyph.strokes[stroke];
    if (!_active) {
      // Back on the path where she left it: carry on.
      if (p.distanceTo(pts[reached]) > tolerance) return TraceEvent.none;
      _active = true;
      _strayed = false;
    }
    var best = -1;
    var nearest = double.infinity;
    final end = min(pts.length - 1, reached + _window);
    for (var i = reached; i <= end; i++) {
      final d = p.distanceTo(pts[i]);
      nearest = min(nearest, d);
      if (d <= tolerance) best = i;
    }
    if (best < 0) {
      if (nearest > tolerance * 2 && !_strayed) {
        _strayed = true;
        _active = false;
        slips++;
        return TraceEvent.strayed;
      }
      return TraceEvent.none;
    }
    reached = best;
    if (reached >= pts.length - 2) return _finish(p);
    return TraceEvent.moved;
  }

  void up() {
    _active = false;
    _strayed = false;
  }

  TraceEvent _finish(Point<double> p) {
    stroke++;
    reached = 0;
    _active = false;
    if (done) return TraceEvent.glyphDone;
    // A stroke that starts where the finger is (B's second bump) carries on.
    if (p.distanceTo(glyph.strokes[stroke].first) <= tolerance && glyph.strokes[stroke].length > 1) _active = true;
    return TraceEvent.strokeDone;
  }
}

// ───────────────────────────────── Rounds ───────────────────────────────────

/// Pre-writing strokes, then curves (Appendix B: lines → curves → letters →
/// name).
const List<String> kTraceLines = ['down', 'across', 'slant', 'slant-back', 'cross', 'zigzag'];
const List<String> kTraceCurves = ['hill', 'cup', 'curve', 'circle', 'wave'];

/// Capitals made only of straight lines: the first letters to trace.
const String kStraightCapitals = 'AEFHIKLMNTVWXYZ';

/// What a Letter Tracing round traces, one glyph after another: a stroke
/// (levels 1–2), a capital of straight lines (3), any capital (4), her own
/// name (5; a capital when it has no letters to trace).
List<String> letterTraceRound(int level, Random rng, {String? name, String? last}) {
  String pick(Iterable<String> from) => _pick([for (final c in from) if (c != last) c], rng);
  final capitals = [for (var c = 65; c <= 90; c++) String.fromCharCode(c)];
  return switch (level) {
    <= 1 => [pick(kTraceLines)],
    2 => [pick(kTraceCurves)],
    3 => [pick(kStraightCapitals.split(''))],
    4 => [pick(capitals)],
    _ => nameGlyphs(name ?? '').isEmpty ? [pick(capitals)] : nameGlyphs(name!),
  };
}

const Map<String, String> _plain = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', //
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y',
};

/// The letters of [name] to trace, the first a capital and the rest as
/// written ("Ava" → A, v, a; "Zoë" → Z, o, e), at most ten.
List<String> nameGlyphs(String name) {
  final out = <String>[];
  for (final ch in name.trim().split('')) {
    final lower = ch.toLowerCase();
    final plain = _plain[lower] ?? lower;
    final c = ch == lower ? plain : plain.toUpperCase();
    final glyph = out.isEmpty ? c.toUpperCase() : c;
    if (RegExp('^[a-zA-Z]\$').hasMatch(glyph)) out.add(glyph);
    if (out.length == 10) break;
  }
  return out;
}

/// Digits per level (Appendix B: 1–3 → 0–9).
const List<String> kNumberLevels = ['123', '12345', '0123456789'];

/// The digit a Number Tracing round traces (not [last] again).
int numberTraceRound(int level, Random rng, {int? last}) {
  final digits = kNumberLevels[(level - 1).clamp(0, kNumberLevels.length - 1)];
  return int.parse(_pick([for (final d in digits.split('')) if (d != '$last') d], rng));
}
