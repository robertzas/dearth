import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

import '../theme/dearth_theme.dart';

/// A high/low range bar on a shared scale (10-day forecast; SPEC §11.8
/// `DRangeBar`). The bar is a cool→warm gradient clipped to [low, high].
class DRangeBar extends StatelessWidget {
  const DRangeBar({super.key, required this.min, required this.max, required this.low, required this.high, this.now, this.height});

  /// Scale bounds (e.g. the lowest low and highest high of the week).
  final double min;
  final double max;
  final double low;
  final double high;

  /// Optional current-value dot (today).
  final double? now;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return SizedBox(
      height: height ?? 10 * t.scale,
      child: CustomPaint(
        painter: _RangeBarPainter(
          min: min,
          max: max,
          low: low,
          high: high,
          now: now,
          track: t.colors.surfaceSunken,
          cool: t.colors.vizCool,
          warm: t.colors.vizWarm,
          dot: t.colors.inkPrimary,
          ring: t.colors.surfaceRaised,
        ),
      ),
    );
  }
}

class _RangeBarPainter extends CustomPainter {
  _RangeBarPainter({
    required this.min,
    required this.max,
    required this.low,
    required this.high,
    required this.now,
    required this.track,
    required this.cool,
    required this.warm,
    required this.dot,
    required this.ring,
  });
  final double min, max, low, high;
  final double? now;
  final Color track, cool, warm, dot, ring;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = track);
    final span = (max - min).abs() < 0.001 ? 1.0 : max - min;
    double x(double v) => ((v - min) / span).clamp(0.0, 1.0) * size.width;
    final l = x(low), h = math.max(x(high), x(low) + size.height);
    final rect = Rect.fromLTRB(l, 0, h.clamp(0, size.width), size.height);
    final shader = LinearGradient(colors: [cool, warm]).createShader(Offset.zero & size);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, r), Paint()..shader = shader);
    if (now != null) {
      final c = Offset(x(now!).clamp(size.height / 2, size.width - size.height / 2), size.height / 2);
      canvas.drawCircle(c, size.height * 0.75, Paint()..color = ring);
      canvas.drawCircle(c, size.height * 0.48, Paint()..color = dot);
    }
  }

  @override
  bool shouldRepaint(_RangeBarPainter o) =>
      o.min != min || o.max != max || o.low != low || o.high != high || o.now != now || o.track != track || o.cool != cool || o.warm != warm;
}

/// A smooth line through [values] with an optional soft fill (temperature).
/// Null values break the line.
class DSparkline extends StatelessWidget {
  const DSparkline({super.key, required this.values, this.color, this.fill = true, this.strokeWidth, this.minValue, this.maxValue, this.highlightIndex});
  final List<double?> values;
  final Color? color;
  final bool fill;
  final double? strokeWidth;
  final double? minValue;
  final double? maxValue;
  final int? highlightIndex;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final col = color ?? t.colors.vizWarm;
    return RepaintBoundary(
      child: CustomPaint(
        painter: SparklinePainter(
          values: values,
          color: col,
          fill: fill ? col.withValues(alpha: t.colors.isDark ? 0.22 : 0.16) : null,
          stroke: strokeWidth ?? 3 * t.scale,
          minValue: minValue,
          maxValue: maxValue,
          highlightIndex: highlightIndex,
          dotRing: t.colors.surfaceRaised,
        ),
        size: Size.infinite,
      ),
    );
  }
}

/// Paints a sparkline; also used directly by composite charts.
class SparklinePainter extends CustomPainter {
  SparklinePainter({
    required this.values,
    required this.color,
    required this.stroke,
    this.fill,
    this.minValue,
    this.maxValue,
    this.highlightIndex,
    this.dotRing,
    this.padTop = 0,
    this.padBottom = 0,
  });
  final List<double?> values;
  final Color color;
  final Color? fill;
  final double stroke;
  final double? minValue;
  final double? maxValue;
  final int? highlightIndex;
  final Color? dotRing;
  final double padTop;
  final double padBottom;

  /// Y position of value [v] for a chart of [size].
  double yOf(double v, Size size) {
    final present = values.whereType<double>();
    final lo = minValue ?? (present.isEmpty ? 0 : present.reduce(math.min));
    final hi = maxValue ?? (present.isEmpty ? 1 : present.reduce(math.max));
    final span = (hi - lo).abs() < 0.001 ? 1.0 : hi - lo;
    final h = size.height - padTop - padBottom - stroke;
    return padTop + stroke / 2 + h * (1 - (v - lo) / span);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final dx = size.width / (values.length - 1);
    final segments = <List<Offset>>[];
    var current = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) {
        if (current.isNotEmpty) segments.add(current);
        current = [];
        continue;
      }
      current.add(Offset(i * dx, yOf(v, size)));
    }
    if (current.isNotEmpty) segments.add(current);

    for (final pts in segments) {
      if (pts.length < 2) continue;
      final path = _smooth(pts);
      if (fill != null) {
        final area = Path.from(path)
          ..lineTo(pts.last.dx, size.height)
          ..lineTo(pts.first.dx, size.height)
          ..close();
        final shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fill!, fill!.withValues(alpha: 0)],
        ).createShader(Offset.zero & size);
        canvas.drawPath(area, Paint()..shader = shader);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    final hi = highlightIndex;
    if (hi != null && hi >= 0 && hi < values.length && values[hi] != null) {
      final c = Offset(hi * dx, yOf(values[hi]!, size));
      canvas.drawCircle(c, stroke * 2.2, Paint()..color = dotRing ?? const Color(0xFFFFFFFF));
      canvas.drawCircle(c, stroke * 1.4, Paint()..color = color);
    }
  }

  static Path _smooth(List<Offset> p) {
    final path = Path()..moveTo(p.first.dx, p.first.dy);
    for (var i = 0; i < p.length - 1; i++) {
      final p0 = i > 0 ? p[i - 1] : p[i];
      final p1 = p[i];
      final p2 = p[i + 1];
      final p3 = i + 2 < p.length ? p[i + 2] : p2;
      // Catmull-Rom → cubic Bézier with tension 0.5, y-clamped to avoid overshoot.
      final c1 = Offset(p1.dx + (p2.dx - p0.dx) / 6, p1.dy + (p2.dy - p0.dy) / 6);
      final c2 = Offset(p2.dx - (p3.dx - p1.dx) / 6, p2.dy - (p3.dy - p1.dy) / 6);
      final minY = math.min(p1.dy, p2.dy), maxY = math.max(p1.dy, p2.dy);
      path.cubicTo(c1.dx, c1.dy.clamp(minY - 2, maxY + 2), c2.dx, c2.dy.clamp(minY - 2, maxY + 2), p2.dx, p2.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(SparklinePainter o) =>
      !listEquals(o.values, values) || o.color != color || o.fill != fill || o.stroke != stroke || o.highlightIndex != highlightIndex || o.minValue != minValue || o.maxValue != maxValue;
}

/// Vertical bars 0…1 (rain probability, sunshine minutes, UV).
class DBarStrip extends StatelessWidget {
  const DBarStrip({super.key, required this.values, this.color, this.gap, this.radius, this.alphaByValue = false});
  final List<double> values;
  final Color? color;
  final double? gap;
  final double? radius;

  /// Fade low values (sunshine band).
  final bool alphaByValue;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return CustomPaint(
      painter: _BarStripPainter(values, color ?? t.colors.vizRain, gap ?? 3 * t.scale, radius ?? 3 * t.scale, alphaByValue, t.colors.surfaceSunken),
      size: Size.infinite,
    );
  }
}

class _BarStripPainter extends CustomPainter {
  _BarStripPainter(this.values, this.color, this.gap, this.radius, this.alphaByValue, this.track);
  final List<double> values;
  final Color color;
  final double gap;
  final double radius;
  final bool alphaByValue;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final w = (size.width - gap * (values.length - 1)) / values.length;
    final paint = Paint();
    for (var i = 0; i < values.length; i++) {
      final v = values[i].clamp(0.0, 1.0);
      final x = i * (w + gap);
      if (alphaByValue) {
        paint.color = Color.lerp(track, color, v)!;
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, 0, w, size.height), Radius.circular(radius)), paint);
        continue;
      }
      final h = math.max(v * size.height, v > 0 ? 2.0 : 0.0);
      if (h <= 0) continue;
      paint.color = color.withValues(alpha: 0.35 + 0.65 * v);
      canvas.drawRRect(
        RRect.fromRectAndCorners(Rect.fromLTWH(x, size.height - h, w, h), topLeft: Radius.circular(radius), topRight: Radius.circular(radius)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarStripPainter o) => !listEquals(o.values, values) || o.color != color || o.gap != gap || o.alphaByValue != alphaByValue;
}
