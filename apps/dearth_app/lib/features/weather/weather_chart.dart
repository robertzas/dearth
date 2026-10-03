import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

/// The combined next-hours chart (FR-WX-06): condition icons and a
/// temperature line, rain-probability bars labeled with amounts, a sunshine
/// band and a UV band — one painter, repainted only when data changes.
class HourlyChart extends StatelessWidget {
  const HourlyChart({
    super.key,
    required this.hours,
    required this.imperial,
    required this.hourLabel,
    required this.nowMs,
  });

  final List<WxHour> hours;
  final bool imperial;
  final String Function(int ms) hourLabel;
  final int nowMs;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return RepaintBoundary(
      child: SizedBox(
        height: 300 * t.scale,
        child: CustomPaint(
          size: Size.infinite,
          painter: _HourlyPainter(
            hours: hours,
            imperial: imperial,
            labels: [for (final h in hours) hourLabel(h.timeMs)],
            scale: t.scale,
            colors: t.colors,
            caption: t.text.caption,
            label: t.text.label,
          ),
        ),
      ),
    );
  }
}

/// Emoji need the color-emoji fallback (painters don't inherit DEmoji's).
const _emojiStyle = TextStyle(fontFamilyFallback: ['Noto Color Emoji', 'Apple Color Emoji', 'Segoe UI Emoji']);

class _HourlyPainter extends CustomPainter {
  _HourlyPainter({
    required this.hours,
    required this.imperial,
    required this.labels,
    required this.scale,
    required this.colors,
    required this.caption,
    required this.label,
    // Repaint when fonts change: on the web the color-emoji font arrives
    // after the first paint, and text painted before that shows as tofu.
  }) : super(repaint: PaintingBinding.instance.systemFonts);

  final List<WxHour> hours;
  final bool imperial;
  final List<String> labels;
  final double scale;
  final DColors colors;
  final TextStyle caption;
  final TextStyle label;

  void _text(Canvas canvas, String s, Offset center, TextStyle style) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (hours.length < 2) return;
    final n = hours.length;
    final colW = size.width / n;
    final every = n > 30 ? 4 : (n > 16 ? 3 : 2);
    final small = caption.copyWith(fontSize: 13 * scale, fontWeight: FontWeight.w700);

    // Layout bands top → bottom.
    final emojiY = 18 * scale;
    // Peak labels sit 14 above the curve; keep them clear of the icon row.
    final tempTop = 56 * scale, tempBottom = 120 * scale;
    final rainTop = 138 * scale, rainBottom = 210 * scale;
    final sunTop = 220 * scale, sunH = 16 * scale;
    final uvTop = 242 * scale, uvH = 16 * scale;
    final labelY = 280 * scale;

    // Temperature line.
    final temps = [for (final h in hours) h.tempC == null ? null : displayTemp(h.tempC!, imperial: imperial)];
    final present = temps.whereType<double>();
    if (present.isNotEmpty) {
      final lo = present.reduce(math.min) - 1, hi = present.reduce(math.max) + 1;
      double y(double v) => tempBottom - (v - lo) / (hi - lo) * (tempBottom - tempTop);
      final path = Path();
      var started = false;
      final pts = <Offset>[];
      for (var i = 0; i < n; i++) {
        final v = temps[i];
        if (v == null) continue;
        final p = Offset(colW * (i + 0.5), y(v));
        pts.add(p);
        if (!started) {
          path.moveTo(p.dx, p.dy);
          started = true;
        } else {
          final prev = pts[pts.length - 2];
          final mid = (prev.dx + p.dx) / 2;
          path.cubicTo(mid, prev.dy, mid, p.dy, p.dx, p.dy);
        }
      }
      final fill = Path.from(path)
        ..lineTo(pts.last.dx, tempBottom + 6 * scale)
        ..lineTo(pts.first.dx, tempBottom + 6 * scale)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [colors.vizWarm.withValues(alpha: colors.isDark ? 0.28 : 0.2), colors.vizWarm.withValues(alpha: 0)],
          ).createShader(Rect.fromLTRB(0, tempTop, size.width, tempBottom + 6 * scale)),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = colors.vizWarm
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * scale
          ..strokeCap = StrokeCap.round,
      );
      for (var i = 0; i < n; i += every) {
        final v = temps[i];
        if (v == null) continue;
        _text(canvas, '${v.round()}°', Offset(colW * (i + 0.5), y(v) - 14 * scale), label.copyWith(fontSize: 15 * scale, fontWeight: FontWeight.w800));
      }
    }

    // Condition icons.
    for (var i = 0; i < n; i += every) {
      _text(canvas, conditionEmoji(hours[i].condition, isDay: hours[i].isDay), Offset(colW * (i + 0.5), emojiY), _emojiStyle.copyWith(fontSize: 20 * scale));
    }

    // Rain probability bars with amounts.
    final rainPaint = Paint();
    canvas.drawRect(Rect.fromLTRB(0, rainBottom, size.width, rainBottom + 1), Paint()..color = colors.outline);
    for (var i = 0; i < n; i++) {
      final p = (hours[i].precipProb ?? 0) / 100;
      if (p <= 0.02) continue;
      final h = p * (rainBottom - rainTop);
      rainPaint.color = colors.vizRain.withValues(alpha: 0.3 + 0.7 * p);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(colW * i + colW * 0.18, rainBottom - h, colW * 0.64, h),
          topLeft: Radius.circular(3 * scale),
          topRight: Radius.circular(3 * scale),
        ),
        rainPaint,
      );
    }
    for (var i = 0; i < n; i += every) {
      final pp = hours[i].precipProb ?? 0;
      if (pp < 10) continue;
      final mm = hours.sublist(i, math.min(n, i + every)).fold<double>(0, (s, h) => s + (h.precipMm ?? 0));
      final amount = mm >= 0.1 ? ' ${imperial ? (mm / 25.4).toStringAsFixed(2) : mm.toStringAsFixed(1)}' : '';
      _text(canvas, '${pp.round()}%$amount', Offset(colW * (i + 0.5), rainTop - 6 * scale), small.copyWith(color: colors.vizRain));
    }

    // Sunshine and UV bands.
    final band = Paint();
    for (var i = 0; i < n; i++) {
      final sun = ((hours[i].sunshineMin ?? 0) / 60).clamp(0.0, 1.0);
      band.color = Color.lerp(colors.surfaceSunken, colors.vizSun, sun)!;
      canvas.drawRect(Rect.fromLTWH(colW * i, sunTop, colW + 0.5, sunH), band);
      final uv = ((hours[i].uvIndex ?? 0) / 10).clamp(0.0, 1.0);
      band.color = Color.lerp(colors.surfaceSunken, colors.vizUv, uv)!;
      canvas.drawRect(Rect.fromLTWH(colW * i, uvTop, colW + 0.5, uvH), band);
    }
    final bandLabel = small.copyWith(color: colors.inkSecondary, fontSize: 12 * scale);
    _text(canvas, 'sun', Offset(18 * scale, sunTop + sunH / 2), bandLabel.copyWith(color: colors.inkPrimary));
    _text(canvas, 'UV', Offset(14 * scale, uvTop + uvH / 2), bandLabel.copyWith(color: colors.inkPrimary));

    // Hour labels.
    for (var i = 0; i < n; i += every) {
      _text(canvas, labels[i], Offset(colW * (i + 0.5), labelY), small.copyWith(color: colors.inkSecondary));
    }
  }

  @override
  bool shouldRepaint(_HourlyPainter o) =>
      !listEquals(o.labels, labels) || o.hours.length != hours.length || (hours.isNotEmpty && o.hours.first.timeMs != hours.first.timeMs) || o.colors != colors || o.imperial != imperial || o.scale != scale;
}

/// Sunrise→sunset arc with the sun's current position (FR-WX-06 Sun & moon).
class SunArc extends StatelessWidget {
  const SunArc({super.key, required this.progress, required this.isDay});

  /// 0 at sunrise, 1 at sunset (clamped).
  final double progress;
  final bool isDay;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return CustomPaint(
      size: Size.infinite,
      painter: _SunArcPainter(progress.clamp(0, 1), isDay, t.colors, t.scale),
    );
  }
}

class _SunArcPainter extends CustomPainter {
  _SunArcPainter(this.p, this.isDay, this.colors, this.scale);
  final double p;
  final bool isDay;
  final DColors colors;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(12 * scale, 12 * scale, size.width - 24 * scale, (size.height - 24 * scale) * 2);
    final track = Paint()
      ..color = colors.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * scale
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, track);
    if (isDay) {
      canvas.drawArc(rect, math.pi, math.pi * p, false, track..color = colors.vizSun);
      final angle = math.pi + math.pi * p;
      final c = rect.center + Offset(math.cos(angle) * rect.width / 2, math.sin(angle) * rect.height / 2);
      canvas.drawCircle(c, 12 * scale, Paint()..color = colors.vizSun.withValues(alpha: 0.3));
      canvas.drawCircle(c, 7 * scale, Paint()..color = colors.vizSun);
    }
    canvas.drawRect(Rect.fromLTWH(0, size.height - 1, size.width, 1), Paint()..color = colors.outline);
  }

  @override
  bool shouldRepaint(_SunArcPainter o) => o.p != p || o.isDay != isDay || o.colors != colors;
}
