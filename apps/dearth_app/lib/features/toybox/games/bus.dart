import 'dart:math' as math;

import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import 'voice_widgets.dart';

// The double-decker of Who Has More? and Bus Stop, painted in code.

/// Bus paints: bright, and far enough apart that no two buses look alike.
const List<Color> kBusPaints = [Color(0xFFE5484D), Color(0xFF3E8EF7), Color(0xFF30A46C), Color(0xFFF2A516), Color(0xFF8E4EC6), Color(0xFFF76B15)];

/// A bus box's height over its width (the roof sign to the wheels).
const double kBusAspect = 0.7;

/// One bus: painted body and windows, and the route number on its roof
/// sign in the Toybox's print.
class BusView extends StatelessWidget {
  const BusView({super.key, required this.sign, required this.color, required this.kids, required this.glow, required this.seed, required this.width, this.lit = 0});

  /// What the roof sign says: a route number, or empty for "?".
  final String sign;
  final int seed;

  /// Lower-deck windows lit up, front to back, as kids are counted.
  final int lit;
  final Color color;
  final double kids, width;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final badge = width * 0.27;
    final dark = Color.lerp(color, BusPainter.ink, 0.45)!;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: BusPainter(color: color, kids: kids, glow: glow, seed: seed, lit: lit)))),
        Positioned(
          left: (width - badge) / 2,
          top: 0,
          width: badge,
          height: badge,
          child: DecoratedBox(
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: dark, width: math.max(2, width * 0.014))),
            child: Center(
              child: sign.isEmpty
                  // Not known yet: a question for her to answer.
                  ? Text('?', style: DTheme.of(context).text.kidTitle.copyWith(fontSize: badge * 0.55, height: 1, color: dark))
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [for (final d in sign.split('')) GlyphView(d, height: badge * 0.5, color: BusPainter.ink)],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A double-decker, front to the left (buses pull in leftward), in a box
/// [kBusAspect] times as tall as it is wide: the roof sign's space on
/// top, two decks of ten windows (five, a door or pillar, five), wheels at
/// the bottom. [kids] fill the windows lower deck first, front to back, the
/// last one growing in.
class BusPainter extends CustomPainter {
  BusPainter({required this.color, required this.kids, required this.glow, required this.seed, this.lit = 0});
  final Color color;
  final double kids;
  final bool glow;
  final int seed, lit;

  static const ink = Color(0xFF2B2440);
  static const _glass = Color(0xFFCFEFFF);
  static const skins = [Color(0xFFF6D3B3), Color(0xFFE0AC85), Color(0xFFB97A55), Color(0xFF8D5A3B), Color(0xFFFFE0C7)];
  static const hair = [Color(0xFF3B2A20), Color(0xFF6B4226), Color(0xFFE2B04A), Color(0xFF1F1A17), Color(0xFFB5502B)];
  static const shirts = [Color(0xFFFF8A65), Color(0xFF4FC3F7), Color(0xFFAED581), Color(0xFFFFD54F), Color(0xFFBA68C8), Color(0xFFF06292)];

  /// Window [i] (0–9 the lower deck, front to back; 10–19 the upper) of a
  /// bus [w] wide.
  static Rect window(int i, double w) {
    final col = i % 10, upper = i >= 10;
    final x = w * (0.135 + col * 0.079 + (col >= 5 ? 0.045 : 0));
    return Rect.fromLTWH(x, w * (upper ? 0.285 : 0.46), w * 0.064, w * (upper ? 0.11 : 0.105));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final dark = Color.lerp(color, ink, 0.45)!;
    final body = RRect.fromRectAndCorners(
      Rect.fromLTRB(w * 0.02, w * 0.25, w * 0.98, w * 0.62),
      topLeft: Radius.circular(w * 0.09),
      topRight: Radius.circular(w * 0.06),
      bottomLeft: Radius.circular(w * 0.03),
      bottomRight: Radius.circular(w * 0.03),
    );
    // A solid halo, not a blur: blurs are too slow on the frame.
    if (glow) canvas.drawRRect(body.inflate(w * 0.03), Paint()..color = const Color(0x99FFD54F));
    canvas.drawRRect(body, Paint()..color = color);
    // The cream band between the decks and the dark skirt.
    canvas
      ..save()
      ..clipRRect(body)
      ..drawRect(Rect.fromLTRB(0, w * 0.413, w, w * 0.44), Paint()..color = const Color(0xFFFFF4DC))
      ..drawRect(Rect.fromLTRB(0, w * 0.578, w, w * 0.62), Paint()..color = dark)
      ..restore();
    final glass = Paint()..color = _glass;
    final frame = Paint()
      ..color = dark
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, w * 0.006);
    // The windscreens at the front.
    for (final r in [Rect.fromLTRB(w * 0.035, w * 0.285, w * 0.115, w * 0.395), Rect.fromLTRB(w * 0.035, w * 0.46, w * 0.115, w * 0.565)]) {
      final rr = RRect.fromRectAndRadius(r, Radius.circular(w * 0.012));
      canvas
        ..drawRRect(rr, glass)
        ..drawRRect(rr, frame);
    }
    // The door, between the lower deck's fives.
    final door = RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.522, w * 0.455, w * 0.568, w * 0.605), Radius.circular(w * 0.008));
    canvas
      ..drawRRect(door, Paint()..color = const Color(0xFF9FD4EE))
      ..drawRRect(door, frame)
      ..drawLine(Offset(w * 0.545, w * 0.455), Offset(w * 0.545, w * 0.605), frame);
    final whole = kids.floor();
    for (var i = 0; i < 20; i++) {
      final r = window(i, w);
      final rr = RRect.fromRectAndRadius(r, Radius.circular(w * 0.012));
      canvas.drawRRect(rr, i < lit ? (Paint()..color = const Color(0xFFFFE27A)) : glass);
      if (i < whole) {
        _kid(canvas, r, i, 1);
      } else if (i == whole && kids > whole) {
        _kid(canvas, r, i, kids - whole);
      }
      canvas.drawRRect(rr, frame);
    }
    canvas
      ..drawRRect(
        body,
        Paint()
          ..color = dark
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, w * 0.012),
      )
      // A headlight.
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.03, w * 0.585, w * 0.075, w * 0.607), Radius.circular(w * 0.008)), Paint()..color = const Color(0xFFFFE066));
    for (final x in const [0.22, 0.8]) {
      canvas
        ..drawCircle(Offset(w * x, w * 0.62), w * 0.068, Paint()..color = ink)
        ..drawCircle(Offset(w * x, w * 0.62), w * 0.03, Paint()..color = const Color(0xFFB8B3C7));
    }
  }

  /// A kid looking out of window [win]: shoulders, a face, hair, eyes and a
  /// smile, [grow] from 0 (not there) to 1.
  void _kid(Canvas canvas, Rect win, int i, double grow) {
    final rng = math.Random(seed * 31 + i);
    final skin = skins[rng.nextInt(skins.length)];
    final hairColor = hair[rng.nextInt(hair.length)];
    final shirt = shirts[rng.nextInt(shirts.length)];
    final r = win.width * 0.34 * Curves.easeOutBack.transform(grow.clamp(0, 1));
    if (r < 0.5) return;
    final c = Offset(win.center.dx, win.top + win.height * 0.55);
    final face = ink.withValues(alpha: 0.85);
    canvas
      ..save()
      ..clipRect(win)
      ..drawOval(Rect.fromCenter(center: Offset(c.dx, win.bottom), width: r * 2.6, height: r * 1.5), Paint()..color = shirt)
      ..drawCircle(c, r, Paint()..color = skin)
      // Hair: the top of the head, down to the brow.
      ..drawArc(Rect.fromCircle(center: c, radius: r * 1.04), math.pi + 0.45, math.pi - 0.9, false, Paint()..color = hairColor)
      ..drawCircle(c + Offset(-r * 0.36, r * 0.02), r * 0.12, Paint()..color = face)
      ..drawCircle(c + Offset(r * 0.36, r * 0.02), r * 0.12, Paint()..color = face)
      ..drawArc(
        Rect.fromCircle(center: c + Offset(0, r * 0.1), radius: r * 0.42),
        0.25 * math.pi,
        0.5 * math.pi,
        false,
        Paint()
          ..color = face
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.12
          ..strokeCap = StrokeCap.round,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(BusPainter old) => old.kids != kids || old.glow != glow || old.color != color || old.seed != seed || old.lit != lit;
}
