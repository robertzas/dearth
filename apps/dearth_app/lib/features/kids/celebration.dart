import 'dart:math' as math;

import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

/// Celebration styles from the catalog (SPEC FR-KID-20).
enum CelebrationStyle { confetti, stars, bubbles }

CelebrationStyle? _last;

/// Praise for effort, not totals (SPEC FR-KID-21).
const List<String> kPraise = ['You did it yourself!', 'Great helping!', 'Wow, look at you!', 'High five!', 'Super job!', 'You’re a big helper!'];

String randomPraise([math.Random? r]) => kPraise[(r ?? math.Random()).nextInt(kPraise.length)];

/// Plays a celebration over the whole app (SPEC FR-KID-03/20): a particle
/// burst, the buddy dancing, and praise. Styles never repeat twice in a
/// row; [calm] (bedtime) is slow sparkles; reduced motion shows only the
/// praise. It never blocks taps.
void celebrate(BuildContext context, {required String emoji, String? buddy, required String message, bool calm = false, bool big = false}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final choices = calm
      ? const [CelebrationStyle.stars]
      : [
          for (final s in CelebrationStyle.values)
            if (s != _last) s,
        ];
  final style = choices[math.Random().nextInt(choices.length)];
  _last = style;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Celebration(style: style, emoji: emoji, buddy: buddy, message: message, calm: calm, big: big, onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

class _Particle {
  _Particle(math.Random r)
    : x = r.nextDouble(),
      speed = r.nextDouble(),
      phase = r.nextDouble() * math.pi * 2,
      spin = (r.nextDouble() - 0.5) * 14,
      angle = r.nextDouble() * math.pi * 2,
      size = 0.6 + r.nextDouble() * 0.8,
      color = r.nextInt(_colors.length),
      delay = r.nextDouble() * 0.25;

  final double x, speed, phase, spin, angle, size, delay;
  final int color;
}

const _colors = [Color(0xFFFF6B6B), Color(0xFFFFC145), Color(0xFF4ECDC4), Color(0xFF5B5BD6), Color(0xFFFF8FD8), Color(0xFF7ED957)];

class _Celebration extends StatefulWidget {
  const _Celebration({
    required this.style,
    required this.emoji,
    required this.buddy,
    required this.message,
    required this.calm,
    required this.big,
    required this.onDone,
  });

  final CelebrationStyle style;
  final String emoji;
  final String? buddy;
  final String message;
  final bool calm;
  final bool big;
  final VoidCallback onDone;

  @override
  State<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<_Celebration> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.calm ? 3200 : (widget.big ? 3000 : 2300)),
  );
  List<_Particle> _particles = const [];

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_particles.isEmpty) {
      final t = DTheme.of(context);
      final n = math.min(t.policy.maxParticles, widget.big ? 140 : (widget.calm ? 40 : 80));
      final r = math.Random();
      _particles = [for (var i = 0; i < n; i++) _Particle(r)];
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final pill = Container(
      padding: EdgeInsets.symmetric(horizontal: t.space.xl, vertical: t.space.md),
      decoration: BoxDecoration(color: t.colors.accent, borderRadius: t.radius.pill, boxShadow: t.elevation.e2),
      child: Text(
        widget.message,
        style: t.text.kidTitle.copyWith(color: t.colors.onAccent),
        textAlign: TextAlign.center,
      ),
    );
    // Fade in fast, hold, fade out over the last fifth.
    final fade = CurvedAnimation(
      parent: _c,
      curve: const Interval(0, 1, curve: _HoldFade()),
    );
    // An overlay entry has no route Material above it: supply the text
    // defaults (no debug underline).
    if (t.reducedMotion) {
      return IgnorePointer(
        child: Material(
          type: MaterialType.transparency,
          child: Center(
            child: FadeTransition(opacity: fade, child: tid('celebration', pill)),
          ),
        ),
      );
    }
    final s = (widget.big ? 150 : 112) * t.scale;
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(child: CustomPaint(painter: _ParticlePainter(_c, _particles, widget.style))),
            Center(
              child: FadeTransition(
                opacity: fade,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, child) {
                    final p = _c.value;
                    // Pop in with overshoot, then a little dance.
                    final pop = Curves.elasticOut.transform((p / 0.35).clamp(0.0, 1.0));
                    final wiggle = widget.calm ? 0.0 : math.sin(p * math.pi * 8) * 0.12 * (1 - p);
                    return Transform.scale(
                      scale: 0.4 + 0.6 * pop,
                      child: Transform.rotate(angle: wiggle, child: child),
                    );
                  },
                  child: tid(
                    'celebration',
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.buddy != null) ...[DEmoji(widget.buddy!, size: s), SizedBox(width: t.space.md)],
                            DEmoji(widget.emoji, size: s),
                          ],
                        ),
                        SizedBox(height: t.space.lg),
                        pill,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opacity curve: in over the first 8 %, out over the last 20 %.
class _HoldFade extends Curve {
  const _HoldFade();

  @override
  double transformInternal(double t) => t < 0.08 ? t / 0.08 : (t > 0.8 ? (1 - t) / 0.2 : 1);
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter(this.anim, this.particles, this.style) : super(repaint: anim);
  final Animation<double> anim;
  final List<_Particle> particles;
  final CelebrationStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final unit = math.min(size.width, size.height) / 60;
    for (final q in particles) {
      final p = ((anim.value - q.delay) / (1 - q.delay)).clamp(0.0, 1.0);
      if (p <= 0) continue;
      final alpha = p > 0.8 ? (1 - p) / 0.2 : 1.0;
      paint.color = _colors[q.color].withValues(alpha: alpha);
      switch (style) {
        case CelebrationStyle.confetti:
          final x = (q.x + math.sin(p * 6 + q.phase) * 0.03) * size.width;
          final y = (-0.1 + p * (1.15 + q.speed * 0.4)) * size.height;
          canvas.save();
          canvas.translate(x, y);
          canvas.rotate(q.angle + p * q.spin);
          canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: unit * q.size * 1.6, height: unit * q.size * 0.8), paint);
          canvas.restore();
        case CelebrationStyle.stars:
          final d = Curves.easeOutCubic.transform(p) * (0.25 + q.speed * 0.35) * size.longestSide;
          final c = size.center(Offset.zero) + Offset(math.cos(q.angle), math.sin(q.angle)) * d;
          canvas.drawPath(_star(c, unit * q.size * 1.3, q.angle + p * q.spin * 0.3), paint);
        case CelebrationStyle.bubbles:
          final x = (q.x + math.sin(p * 4 + q.phase) * 0.04) * size.width;
          final y = (1.1 - p * (1.2 + q.speed * 0.5)) * size.height;
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = unit * 0.25;
          canvas.drawCircle(Offset(x, y), unit * q.size * 1.5, paint);
          paint.style = PaintingStyle.fill;
      }
    }
  }

  static Path _star(Offset c, double r, double rotation) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final a = rotation + i * math.pi / 5 - math.pi / 2;
      final rr = i.isEven ? r : r * 0.45;
      final pt = c + Offset(math.cos(a), math.sin(a)) * rr;
      i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.particles != particles || old.style != style;
}
