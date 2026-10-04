import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// The bundled art pack (SPEC FR-SSV-06 fallback): flat landscape
/// illustrations painted in code, so the frame never shows a blank screen
/// and the app ships no extra image assets. Each scene paints once per size.
const int kArtCount = 8;

const List<String> kArtTitles = [
  'Morning hills',
  'Sunset bay',
  'Starry night',
  'Snowy peaks',
  'Desert dunes',
  'Lavender fields',
  'Forest lake',
  'Northern lights',
];

class ArtScene extends StatelessWidget {
  const ArtScene(this.index, {super.key});
  final int index;

  @override
  Widget build(BuildContext context) => RepaintBoundary(child: CustomPaint(painter: _ArtPainter(index % kArtCount), size: Size.infinite));
}

/// Paints art scene [index] into [canvas] (the Toybox's jigsaw cuts it up).
void paintArt(Canvas canvas, Size size, int index) => _ArtPainter(index % kArtCount).paint(canvas, size);

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.index);
  final int index;

  @override
  void paint(Canvas canvas, Size s) {
    switch (index) {
      case 0:
        _sky(canvas, s, const [Color(0xFFFFD9B0), Color(0xFFFFEFD9), Color(0xFFBFE3F5)]);
        _sun(canvas, Offset(s.width * 0.72, s.height * 0.3), s.shortestSide * 0.09, const Color(0xFFFFF4C9));
        _hills(canvas, s, 0.58, 0.05, const Color(0xFFA8D5A2), 1.3);
        _hills(canvas, s, 0.68, 0.06, const Color(0xFF7DBF7A), 2.1);
        _hills(canvas, s, 0.8, 0.05, const Color(0xFF4E9A5E), 1.7);
        _treesPaint(canvas, s, 0.8, const Color(0xFF2F6B44), 7);
      case 1:
        _sky(canvas, s, const [Color(0xFF4B3B8F), Color(0xFFE0617A), Color(0xFFFFB46B)]);
        _sun(canvas, Offset(s.width * 0.5, s.height * 0.62), s.shortestSide * 0.13, const Color(0xFFFFE6A3));
        final sea = Rect.fromLTWH(0, s.height * 0.62, s.width, s.height * 0.38);
        canvas.drawRect(sea, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE48A7A), Color(0xFF3B2E70)]).createShader(sea));
        final shimmer = Paint()..color = const Color(0x66FFE6A3);
        for (var i = 0; i < 9; i++) {
          final y = s.height * (0.65 + i * 0.035);
          final w = s.width * (0.22 - i * 0.018);
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(s.width * 0.5, y), width: w, height: s.height * 0.006), const Radius.circular(4)), shimmer);
        }
      case 2:
        _sky(canvas, s, const [Color(0xFF0B1030), Color(0xFF1C2457), Color(0xFF34407A)]);
        final r = math.Random(7);
        final star = Paint();
        for (var i = 0; i < 160; i++) {
          final p = Offset(r.nextDouble() * s.width, r.nextDouble() * s.height * 0.7);
          star.color = Color.fromRGBO(255, 255, 240, 0.4 + r.nextDouble() * 0.6);
          canvas.drawCircle(p, 0.6 + r.nextDouble() * 1.8, star);
        }
        _sun(canvas, Offset(s.width * 0.25, s.height * 0.22), s.shortestSide * 0.07, const Color(0xFFFFF7DA));
        canvas.drawCircle(Offset(s.width * 0.25 + s.shortestSide * 0.03, s.height * 0.22 - s.shortestSide * 0.02), s.shortestSide * 0.065, Paint()..color = const Color(0xFF141A44));
        _hills(canvas, s, 0.74, 0.06, const Color(0xFF1A2147), 1.4);
        _hills(canvas, s, 0.84, 0.05, const Color(0xFF0E1330), 2.2);
      case 3:
        _sky(canvas, s, const [Color(0xFF9CC8EC), Color(0xFFD4E9F7), Color(0xFFF2F7FB)]);
        _mountains(canvas, s, 0.35, const Color(0xFF8A9BB8), 4, 0.6);
        _mountains(canvas, s, 0.48, const Color(0xFF6A7C9C), 3, 1.3);
        canvas.drawRect(Rect.fromLTWH(0, s.height * 0.82, s.width, s.height * 0.18), Paint()..color = const Color(0xFFF4F8FC));
        _treesPaint(canvas, s, 0.86, const Color(0xFF3E5A5A), 11);
      case 4:
        _sky(canvas, s, const [Color(0xFFFFC97A), Color(0xFFFFE3B0), Color(0xFFFFF1D6)]);
        _sun(canvas, Offset(s.width * 0.3, s.height * 0.28), s.shortestSide * 0.1, const Color(0xFFFFF8E6));
        _hills(canvas, s, 0.6, 0.08, const Color(0xFFF2B36B), 0.9);
        _hills(canvas, s, 0.72, 0.07, const Color(0xFFE39A52), 1.6);
        _hills(canvas, s, 0.86, 0.05, const Color(0xFFC77B3C), 1.2);
      case 5:
        _sky(canvas, s, const [Color(0xFFB9C7F2), Color(0xFFE8D9F5), Color(0xFFFCE9EF)]);
        _hills(canvas, s, 0.5, 0.03, const Color(0xFFA7B79B), 1.1);
        final field = Rect.fromLTWH(0, s.height * 0.55, s.width, s.height * 0.45);
        canvas.drawRect(field, Paint()..color = const Color(0xFF8D6FC4));
        final row = Paint()
          ..color = const Color(0xFFB59AE6)
          ..strokeWidth = s.width * 0.012
          ..strokeCap = StrokeCap.round;
        for (var i = -10; i <= 10; i++) {
          canvas.drawLine(Offset(s.width * 0.5 + i * s.width * 0.02, s.height * 0.56), Offset(s.width * 0.5 + i * s.width * 0.16, s.height * 1.02), row);
        }
      case 6:
        _sky(canvas, s, const [Color(0xFFCDE8E4), Color(0xFFE9F4EC), Color(0xFFF5F0E1)]);
        _mountains(canvas, s, 0.42, const Color(0xFF7FA79A), 3, 0.4);
        _treesPaint(canvas, s, 0.6, const Color(0xFF3F7A5B), 15);
        final lake = Rect.fromLTWH(0, s.height * 0.6, s.width, s.height * 0.4);
        canvas.drawRect(lake, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF8FC1C7), Color(0xFF4E8C99)]).createShader(lake));
        canvas.save();
        canvas.translate(0, s.height * 1.2);
        canvas.scale(1, -1);
        _treesPaint(canvas, s, 0.6, const Color(0x553F7A5B), 15);
        canvas.restore();
      default:
        _sky(canvas, s, const [Color(0xFF071A2B), Color(0xFF0E2E45), Color(0xFF18465E)]);
        for (final (x, c) in [(0.3, const Color(0x5539E6A2)), (0.55, const Color(0x4459D2E6)), (0.75, const Color(0x3363F2B3))]) {
          final rect = Rect.fromCenter(center: Offset(s.width * x, s.height * 0.3), width: s.width * 0.5, height: s.height * 0.5);
          canvas.drawOval(rect, Paint()..shader = RadialGradient(colors: [c, c.withValues(alpha: 0)]).createShader(rect));
        }
        _hills(canvas, s, 0.78, 0.05, const Color(0xFF0A2232), 1.5);
        _treesPaint(canvas, s, 0.84, const Color(0xFF041019), 13);
    }
  }

  void _sky(Canvas canvas, Size s, List<Color> colors) {
    final r = Offset.zero & s;
    canvas.drawRect(r, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors).createShader(r));
  }

  void _sun(Canvas canvas, Offset c, double r, Color color) {
    canvas.drawCircle(c, r * 1.8, Paint()..color = color.withValues(alpha: 0.25));
    canvas.drawCircle(c, r, Paint()..color = color);
  }

  void _hills(Canvas canvas, Size s, double base, double amp, Color color, double phase) {
    final path = Path()..moveTo(0, s.height);
    for (var i = 0; i <= 40; i++) {
      final x = s.width * i / 40;
      final y = s.height * (base + amp * math.sin(i / 40 * math.pi * 2 * 0.9 + phase) + amp * 0.4 * math.sin(i / 40 * math.pi * 5 + phase * 2));
      path.lineTo(x, y);
    }
    path
      ..lineTo(s.width, s.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _mountains(Canvas canvas, Size s, double top, Color color, int peaks, double seed) {
    final path = Path()..moveTo(0, s.height);
    final w = s.width / peaks;
    for (var i = 0; i < peaks; i++) {
      final peakY = s.height * (top + 0.08 * math.sin(i * 1.7 + seed));
      path
        ..lineTo(w * i, s.height * 0.75)
        ..lineTo(w * (i + 0.5), peakY)
        ..lineTo(w * (i + 1), s.height * 0.75);
    }
    path
      ..lineTo(s.width, s.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    for (var i = 0; i < peaks; i++) {
      final peakY = s.height * (top + 0.08 * math.sin(i * 1.7 + seed));
      final cap = Path()
        ..moveTo(w * (i + 0.5), peakY)
        ..lineTo(w * (i + 0.5) - w * 0.09, peakY + s.height * 0.07)
        ..lineTo(w * (i + 0.5) + w * 0.09, peakY + s.height * 0.07)
        ..close();
      canvas.drawPath(cap, Paint()..color = const Color(0xFFF7FAFD));
    }
  }

  void _treesPaint(Canvas canvas, Size s, double base, Color color, int count) {
    final r = math.Random(count * 31 + index);
    final paint = Paint()..color = color;
    for (var i = 0; i < count; i++) {
      final x = s.width * (i + r.nextDouble() * 0.8) / count;
      final h = s.height * (0.07 + r.nextDouble() * 0.06);
      final w = h * 0.45;
      final y = s.height * base;
      canvas.drawPath(
        Path()
          ..moveTo(x, y - h)
          ..lineTo(x - w / 2, y)
          ..lineTo(x + w / 2, y)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ArtPainter old) => old.index != index;
}
