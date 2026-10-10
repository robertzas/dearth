import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';

/// Creature paint, bright and friendly, in [kCreaturePaints] order.
const List<Color> kCreatureColors = [
  Color(0xFFFF8FB8),
  Color(0xFF6EC6FF),
  Color(0xFF7BD96B),
  Color(0xFFB48CF0),
  Color(0xFFFFA54F),
  Color(0xFFFFD54F),
  Color(0xFF4DD0C4),
  Color(0xFFF2645A),
];

/// "Wobblesaurus, pink: a round body, googly eyes, bunny ears" (the parts
/// [parts] shows).
String _describe(Creature c, List<CreaturePart> parts) =>
    '${c.name}, ${kCreaturePaints[c.color]}: ${[for (final p in parts) kCreaturePartWords[p]![c[p]]].join(', ')}';

/// Build-a-Creature (SPEC FR-TOY-03, Appendix B: creativity and language).
/// A big button per part changes it (body and face first; top and legs,
/// then arms and tail, unlock with play) and the voice names what she
/// picked ("Bunny ears!"); paint pots color it ("Purple!"), the dice
/// surprises her, and the dance button (or a tap on the creature) makes it
/// dance to a little tune and say its silly name ("I'm a Wobblesaurus!").
class CreatureGame extends StatefulWidget {
  const CreatureGame(this.c, {super.key});
  final GameController c;

  @override
  State<CreatureGame> createState() => CreatureGameState();
}

@visibleForTesting
class CreatureGameState extends State<CreatureGame> with SingleTickerProviderStateMixin {
  static const _danceSeconds = 3.4;

  late Creature _creature = randomCreature(widget.c.level, widget.c.random);
  late final Ticker _ticker = createTicker(_tick);

  /// Seconds into the dance; null when standing still.
  final _dance = ValueNotifier<double?>(null);
  final _tune = <Timer>[];
  Timer? _hello;
  int _frames = 0, _changes = 0;

  @visibleForTesting
  Creature get debugCreature => _creature;

  List<CreaturePart> get _parts => creatureParts(widget.c.level);

  @override
  void initState() {
    super.initState();
    _hello = Timer(const Duration(milliseconds: 600), () => widget.c.say(VoiceLine.makeCreature));
  }

  @override
  void dispose() {
    _hello?.cancel();
    _ticker.dispose();
    _dance.dispose();
    for (final t in _tune) {
      t.cancel();
    }
    super.dispose();
  }

  void _change(CreaturePart part) {
    widget.c.sound(Sfx.pop, volume: 0.6, rate: 0.85 + (_changes++ % 5) * 0.08);
    setState(() => _creature = _creature.next(part));
    widget.c.say(creaturePartClip(part, _creature[part]));
  }

  void _paint(int color) {
    widget.c.sound(Sfx.blip, volume: 0.5);
    setState(() => _creature = _creature.withColor(color));
    widget.c.say(colorClip(kCreaturePaints[color]));
  }

  void _surprise() {
    widget.c.sound(Sfx.sparkle, volume: 0.6);
    setState(() => _creature = randomCreature(widget.c.level, widget.c.random));
  }

  void _startDance() {
    if (_dance.value != null) return;
    widget.c.say(creatureClip(_creature));
    _frames = 0;
    _dance.value = 0;
    unawaited(_ticker.start());
    // A little tune: a pentatonic run up and back, with a drum on the beat.
    const notes = [60, 64, 67, 72, 69, 67, 64, 67, 72, 76, 72, 67];
    for (var i = 0; i < notes.length; i++) {
      _tune.add(Timer(Duration(milliseconds: 250 * i), () {
        widget.c.sound(Sfx.xylophone, volume: 0.7, rate: math.pow(2, (notes[i] - kXylophoneBaseMidi) / 12).toDouble());
        if (i.isEven) widget.c.sound(i % 4 == 0 ? Sfx.kick : Sfx.hat, volume: 0.5);
      }));
    }
    setState(() {});
  }

  void _tick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    if (t >= _danceSeconds) {
      _ticker.stop();
      _tune.clear();
      _dance.value = null;
      if (mounted) setState(() {});
      return;
    }
    // Ambient motion: 30 fps is plenty on the slowest displays.
    if (DTheme.of(context).policy.ambientFps < 60 && (_frames++).isOdd) return;
    _dance.value = t;
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final parts = _parts;
    final colors = creatureColors(widget.c.level);
    final dancing = _dance.value != null;
    return Backdrop(
      top: const Color(0xFFFFF0F7),
      bottom: const Color(0xFFEAF7FF),
      child: PlayArea(
        top: 100,
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth > box.maxHeight;
          final stage = wide ? math.min(box.maxWidth * 0.55, box.maxHeight) : math.min(box.maxWidth, box.maxHeight * 0.55);
          final button = math.min(stage * 0.2, 120 * t.scale);
          final me = tid(
            'creature.me',
            Semantics(
              label: '${_describe(_creature, parts)}${dancing ? ', dancing' : ''}',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: _startDance,
                child: RepaintBoundary(
                  child: CustomPaint(size: Size.square(stage), painter: CreaturePainter(_creature, dance: _dance)),
                ),
              ),
            ),
          );
          final controls = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                spacing: button * 0.18,
                runSpacing: button * 0.18,
                children: [
                  for (final p in parts)
                    _RoundButton(
                      id: 'creature.part.${p.name}',
                      label: 'Change the ${p.name}',
                      size: button,
                      onTap: () => _change(p),
                      child: CustomPaint(size: Size.square(button * 0.86), painter: CreaturePainter.icon(p, _creature)),
                    ),
                ],
              ),
              SizedBox(height: button * 0.3),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: button * 0.12,
                runSpacing: button * 0.12,
                children: [
                  for (var i = 0; i < colors; i++)
                    DPressable(
                      id: 'creature.color.$i',
                      semanticLabel: '${kCreaturePaints[i]} paint',
                      selected: _creature.color == i,
                      excludeSemantics: true,
                      onTap: () => _paint(i),
                      borderRadius: BorderRadius.circular(button),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: button * 0.62,
                        height: button * 0.62,
                        decoration: BoxDecoration(
                          color: kCreatureColors[i],
                          shape: BoxShape.circle,
                          border: Border.all(color: _creature.color == i ? const Color(0xFF3B3355) : Colors.white, width: _creature.color == i ? 5 : 3),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: button * 0.3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RoundButton(id: 'creature.surprise', label: 'Surprise me', size: button, onTap: _surprise, child: DEmoji('🎲', size: button * 0.5)),
                  SizedBox(width: button * 0.3),
                  _RoundButton(id: 'creature.dance', label: 'Dance!', size: button * 1.25, onTap: _startDance, glow: !dancing, child: DEmoji('💃', size: button * 0.65)),
                ],
              ),
            ],
          );
          return Center(
            child: wide
                ? Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [me, Flexible(child: controls)])
                : Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [me, Flexible(child: SingleChildScrollView(child: controls))]),
          );
        }),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.id, required this.label, required this.size, required this.onTap, required this.child, this.glow = false});
  final String id, label;
  final double size;
  final VoidCallback onTap;
  final Widget child;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return DPressable(
      id: id,
      semanticLabel: label,
      excludeSemantics: true,
      onTap: onTap,
      pressedScale: 0.92,
      borderRadius: BorderRadius.circular(size / 2),
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: glow ? const Color(0xFFFFC93C) : const Color(0xFFE3DCF5), width: glow ? 5 : 3),
          boxShadow: t.elevation.e1,
        ),
        child: child,
      ),
    );
  }
}

/// Where a body's edges are (fractions of the canvas), so parts attach.
class _Body {
  const _Body(this.top, this.bottom, this.left, this.right, this.faceY);
  final double top, bottom, left, right, faceY;
  double get midY => (top + bottom) / 2;
  double get k => (right - left) / 0.5;
}

const List<_Body> _bodies = [
  _Body(0.33, 0.83, 0.25, 0.75, 0.52),
  _Body(0.28, 0.84, 0.29, 0.71, 0.48),
  _Body(0.32, 0.84, 0.24, 0.76, 0.50),
  _Body(0.34, 0.83, 0.27, 0.73, 0.50),
  _Body(0.31, 0.85, 0.24, 0.76, 0.54),
  _Body(0.31, 0.85, 0.23, 0.77, 0.54),
];

/// A body's edges and face line, as fractions of the canvas (Creature Count
/// places parts on them).
({double top, double bottom, double left, double right, double faceY}) creatureBodyBox(int shape) {
  final b = _bodies[shape];
  return (top: b.top, bottom: b.bottom, left: b.left, right: b.right, faceY: b.faceY);
}

/// Draws a creature, part by part: tail behind, then legs, body, arms, top
/// and face. While dancing it bounces, squashes and sways, and waves its
/// arms. [CreaturePainter.icon] draws one part on a plain round body, for
/// the part buttons.
class CreaturePainter extends CustomPainter {
  CreaturePainter(this.creature, {this.dance}) : only = null, super(repaint: dance);

  CreaturePainter.icon(CreaturePart part, this.creature)
      : only = part,
        dance = null;

  final Creature creature;
  final ValueNotifier<double?>? dance;

  /// Draw only this part (on a plain body), for a button.
  final CreaturePart? only;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final c = creature;
    final color = only == null || only == CreaturePart.body ? kCreatureColors[c.color % kCreatureColors.length] : const Color(0xFFD9D2EC);
    final dark = Color.lerp(color, const Color(0xFF2B2440), 0.45)!;
    final light = Color.lerp(color, Colors.white, 0.45)!;
    int option(CreaturePart p) => only == null || only == p ? c[p] : (p == CreaturePart.body ? 0 : -1);
    final body = option(CreaturePart.body).clamp(0, _bodies.length - 1);
    final b = _bodies[body];
    Offset u(double x, double y) => Offset(x * s, y * s);
    // A button shows its part up close, inside the round button.
    if (only != null) {
      final (fx, fy, zoom) = switch (only!) {
        CreaturePart.body => (0.5, b.midY + 0.02, 1.35),
        CreaturePart.face => (0.5, b.faceY + 0.03, 2.0),
        CreaturePart.top => (0.5, b.top - 0.04, 1.8),
        CreaturePart.legs => (0.5, b.bottom + 0.03, 1.8),
        CreaturePart.arms => (0.5, b.midY, 1.15),
        CreaturePart.tail => (b.right + 0.1, b.bottom - 0.1, 1.7),
      };
      canvas.save();
      canvas.clipPath(Path()..addOval(Offset.zero & size));
      canvas.translate(s / 2, s / 2);
      canvas.scale(zoom);
      canvas.translate(-fx * s, -fy * s);
    }
    final outline = Paint()
      ..color = dark
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.014
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    void fill(Path p, Color c) {
      canvas.drawPath(p, Paint()..color = c);
      canvas.drawPath(p, outline);
    }

    // The dance: bounce, squash and sway around the feet.
    final t = dance?.value;
    final beat = t == null ? 0.0 : math.sin(t * math.pi * 2.6);
    final wave = t == null ? 0.0 : math.sin(t * math.pi * 5.2) * 0.45;
    if (only == null) {
      final ground = b.bottom + (option(CreaturePart.legs) > 0 ? 0.1 : 0.02);
      canvas.drawOval(Rect.fromCenter(center: u(0.5, ground), width: s * 0.42 * b.k * (1 - beat.abs() * 0.15), height: s * 0.05), Paint()..color = const Color(0x1A2B2440));
      if (t != null) {
        canvas.save();
        canvas.translate(s * 0.5, s * ground);
        canvas.rotate(beat * 0.09);
        canvas.scale(1 + beat.abs() * 0.03, 1 - beat.abs() * 0.05);
        canvas.translate(-s * 0.5, -s * ground - beat.abs() * s * 0.07);
      }
    }
    final k = b.k;

    // Tail, behind everything.
    switch (option(CreaturePart.tail)) {
      case 1:
        final p = Path()..moveTo(b.right * s - s * 0.03, (b.bottom - 0.1) * s);
        for (var i = 0; i <= 24; i++) {
          final a = i / 24 * math.pi * 3.2;
          final r = (0.09 - i * 0.0025) * k;
          p.lineTo((b.right + 0.08 * k + math.cos(a + math.pi) * r) * s, (b.bottom - 0.12 - math.sin(a + math.pi) * r * 0.8) * s);
        }
        canvas.drawPath(p, Paint()
          ..color = dark
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.05 * k
          ..strokeCap = StrokeCap.round);
        canvas.drawPath(p, Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.03 * k
          ..strokeCap = StrokeCap.round);
      case 2:
        fill(_puff(body, s), Colors.white);
      case 3:
        final base = u(b.right - 0.04, b.bottom - 0.12);
        final tip = u(b.right + 0.17 * k, b.bottom - 0.03);
        final tail = Path()
          ..moveTo(base.dx, base.dy - s * 0.05 * k)
          ..quadraticBezierTo(base.dx + s * 0.1 * k, base.dy - s * 0.04 * k, tip.dx, tip.dy)
          ..quadraticBezierTo(base.dx + s * 0.08 * k, base.dy + s * 0.07 * k, base.dx, base.dy + s * 0.06 * k)
          ..close();
        for (var i = 0; i < 3; i++) {
          final x = base.dx + s * (0.04 + i * 0.045) * k, y = base.dy - s * (0.045 - i * 0.01) * k;
          fill(
            Path()
              ..moveTo(x - s * 0.018 * k, y + s * 0.01)
              ..lineTo(x, y - s * 0.04 * k)
              ..lineTo(x + s * 0.018 * k, y + s * 0.01)
              ..close(),
            light,
          );
        }
        fill(tail, color);
      case 4:
        final p = Path()
          ..moveTo((b.right - 0.03) * s, (b.bottom - 0.08) * s)
          ..cubicTo((b.right + 0.08 * k) * s, (b.bottom - 0.02) * s, (b.right + 0.12 * k) * s, (b.bottom - 0.16) * s, (b.right + 0.15 * k) * s, (b.bottom - 0.22) * s);
        canvas.drawPath(p, Paint()
          ..color = dark
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.018 * k
          ..strokeCap = StrokeCap.round);
        fill(Path()..addOval(Rect.fromCircle(center: u(b.right + 0.15 * k, b.bottom - 0.23), radius: s * 0.035 * k)), dark);
    }

    // Legs.
    final legPaint = Paint()..color = dark;
    switch (option(CreaturePart.legs)) {
      case 1:
        for (final dx in [-0.1, 0.1]) {
          final x = 0.5 + dx * k;
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB((x - 0.035 * k) * s, (b.bottom - 0.04) * s, (x + 0.035 * k) * s, (b.bottom + 0.08) * s), Radius.circular(s * 0.03)), legPaint);
          canvas.drawOval(Rect.fromCenter(center: u(x + 0.015 * dx.sign, b.bottom + 0.085), width: s * 0.11 * k, height: s * 0.05 * k), legPaint);
        }
      case 2:
        for (final dx in [-0.17, -0.06, 0.06, 0.17]) {
          final x = 0.5 + dx * k;
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB((x - 0.03 * k) * s, (b.bottom - 0.06) * s, (x + 0.03 * k) * s, (b.bottom + 0.07) * s), Radius.circular(s * 0.03)), legPaint);
        }
      case 3:
        for (final dx in [-0.11, 0.0, 0.11]) {
          final p = Path()..moveTo((0.5 + dx * k) * s, (b.bottom - 0.04) * s);
          for (var i = 1; i <= 12; i++) {
            final y = b.bottom - 0.04 + i / 12 * 0.15;
            p.lineTo((0.5 + dx * k + math.sin(i / 12 * math.pi * 2 + dx * 9 + wave) * 0.025) * s, y * s);
          }
          canvas.drawPath(p, Paint()
            ..color = dark
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.05 * k
            ..strokeCap = StrokeCap.round);
          canvas.drawPath(p, Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.032 * k
            ..strokeCap = StrokeCap.round);
        }
      case 4:
        final bird = Paint()
          ..color = const Color(0xFFF2A33A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.016
          ..strokeCap = StrokeCap.round;
        for (final dx in [-0.08, 0.08]) {
          final foot = u(0.5 + dx * k, b.bottom + 0.1);
          canvas.drawLine(u(0.5 + dx * k, b.bottom - 0.03), foot, bird);
          for (final toe in [-0.6, 0.0, 0.6]) {
            canvas.drawLine(foot, foot + Offset(math.sin(toe), math.cos(toe) * 0.4) * s * 0.045, bird);
          }
        }
      case 5:
        for (final dx in [-0.12, 0.12]) {
          final centre = u(0.5 + dx * k, b.bottom + 0.035);
          canvas.drawCircle(centre, s * 0.06 * k, Paint()..color = const Color(0xFF4A4458));
          canvas.drawCircle(centre, s * 0.025 * k, Paint()..color = const Color(0xFFD6D2E0));
        }
    }

    // Body, with a lighter belly.
    final bodyPath = _bodyPath(body, s);
    fill(bodyPath, color);
    canvas.save();
    canvas.clipPath(bodyPath);
    canvas.drawOval(Rect.fromCenter(center: u(0.5, b.bottom - 0.08), width: s * 0.3 * k, height: s * 0.22), Paint()..color = light.withValues(alpha: 0.7));
    canvas.restore();

    // Arms, waving while it dances.
    final armOption = option(CreaturePart.arms);
    for (final side in [-1.0, 1.0]) {
      final root = u(side < 0 ? b.left + 0.02 : b.right - 0.02, b.midY);
      canvas.save();
      canvas.translate(root.dx, root.dy);
      canvas.rotate(side * -wave);
      switch (armOption) {
        case 1:
          final arm = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(side * s * 0.06 * k, -s * 0.03 * k), width: s * 0.13 * k, height: s * 0.06 * k), Radius.circular(s * 0.03 * k)));
          canvas.rotate(side * -0.5);
          fill(arm, color);
        case 2:
          for (var i = 0; i < 3; i++) {
            canvas.save();
            canvas.rotate(side * (-0.9 + i * 0.35));
            fill(Path()..addOval(Rect.fromCenter(center: Offset(side * s * 0.08 * k, 0), width: s * 0.15 * k, height: s * 0.055 * k)), light);
            canvas.restore();
          }
        case 3:
          fill(
            Path()
              ..moveTo(0, -s * 0.05 * k)
              ..quadraticBezierTo(side * s * 0.14 * k, -s * 0.02 * k, side * s * 0.1 * k, s * 0.06 * k)
              ..quadraticBezierTo(side * s * 0.04 * k, s * 0.04 * k, 0, s * 0.06 * k)
              ..close(),
            light,
          );
        case 4:
          final noodle = Path()
            ..moveTo(0, 0)
            ..cubicTo(side * s * 0.08 * k, -s * 0.08 * k, side * s * 0.12 * k, s * 0.06 * k, side * s * 0.18 * k, -s * 0.02 * k);
          canvas.drawPath(noodle, Paint()
            ..color = dark
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.032 * k
            ..strokeCap = StrokeCap.round);
          canvas.drawPath(noodle, Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.018 * k
            ..strokeCap = StrokeCap.round);
          fill(Path()..addOval(Rect.fromCircle(center: Offset(side * s * 0.18 * k, -s * 0.02 * k), radius: s * 0.028 * k)), color);
      }
      canvas.restore();
    }

    // On top.
    final top = b.top;
    switch (option(CreaturePart.top)) {
      case 1:
        for (final side in [-1.0, 1.0]) {
          final base = u(0.5 + side * 0.11 * k, top + 0.035);
          fill(
            Path()
              ..moveTo(base.dx - s * 0.035 * k, base.dy)
              ..quadraticBezierTo(base.dx - s * 0.02 * k + side * s * 0.02, base.dy - s * 0.1 * k, base.dx + side * s * 0.05 * k, base.dy - s * 0.14 * k)
              ..quadraticBezierTo(base.dx + side * s * 0.01, base.dy - s * 0.06 * k, base.dx + s * 0.035 * k, base.dy)
              ..close(),
            const Color(0xFFFFF3D6),
          );
        }
      case 2:
        for (final side in [-1.0, 1.0]) {
          canvas.save();
          canvas.translate(s * (0.5 + side * 0.09 * k), s * (top - 0.06 * k));
          canvas.rotate(side * 0.18);
          fill(Path()..addOval(Rect.fromCenter(center: Offset.zero, width: s * 0.085 * k, height: s * 0.24 * k)), color);
          canvas.drawOval(Rect.fromCenter(center: Offset(0, s * 0.01), width: s * 0.04 * k, height: s * 0.16 * k), Paint()..color = const Color(0xFFFFB3C7));
          canvas.restore();
        }
      case 3:
        for (final side in [-1.0, 1.0]) {
          final tip = u(0.5 + side * 0.14 * k, top - 0.14 * k);
          canvas.drawLine(u(0.5 + side * 0.06 * k, top + 0.02), tip, outline);
          fill(Path()..addOval(Rect.fromCircle(center: tip, radius: s * 0.035 * k)), const Color(0xFFFFD54F));
        }
      case 4:
        for (final i in [-1, 0, 1]) {
          final root = u(0.5 + i * 0.035 * k, top + 0.02);
          final tip = u(0.5 + i * 0.08 * k, top - 0.1 * k);
          fill(
            Path()
              ..moveTo(root.dx - s * 0.025 * k, root.dy)
              ..quadraticBezierTo(root.dx - s * 0.03 * k, tip.dy + s * 0.04 * k, tip.dx, tip.dy)
              ..quadraticBezierTo(root.dx + s * 0.03 * k, tip.dy + s * 0.05 * k, root.dx + s * 0.025 * k, root.dy)
              ..close(),
            dark,
          );
        }
      case 5:
        canvas.save();
        canvas.translate(s * 0.5, s * (top + 0.02));
        canvas.rotate(0.15);
        final hat = Path()
          ..moveTo(-s * 0.08 * k, 0)
          ..lineTo(0, -s * 0.2 * k)
          ..lineTo(s * 0.08 * k, 0)
          ..close();
        fill(hat, const Color(0xFF7C4DFF));
        canvas.save();
        canvas.clipPath(hat);
        for (var i = 0; i < 4; i++) {
          canvas.drawRect(Rect.fromLTWH(-s * 0.1 * k, -s * (0.04 + i * 0.05) * k, s * 0.2 * k, s * 0.02 * k), Paint()..color = const Color(0xFFFFD54F));
        }
        canvas.restore();
        fill(Path()..addOval(Rect.fromCircle(center: Offset(0, -s * 0.2 * k), radius: s * 0.03 * k)), const Color(0xFFFF8FB8));
        canvas.restore();
    }

    // The face.
    final face = option(CreaturePart.face);
    if (face >= 0) _face(canvas, s, face, b, dark, wave);
    if (only == null && t != null) canvas.restore();
    if (only != null) canvas.restore();
  }

  static final _paths = <(int, double), Path>{};
  static final _puffs = <(int, double), Path>{};

  /// Body [shape]'s outline at canvas size [s] (cached).
  static Path bodyPath(int shape, double s) => _bodyPath(shape, s);

  /// The fluffy tail, eight circles unioned (made once, like the bodies).
  static Path _puff(int body, double s) {
    if (_puffs.length > 48) _puffs.clear();
    return _puffs[(body, s)] ??= () {
      final b = _bodies[body], k = b.k;
      final centre = Offset((b.right + 0.02) * s, (b.bottom - 0.09) * s);
      final puff = Path();
      for (var i = 0; i < 7; i++) {
        final a = i / 7 * math.pi * 2;
        puff.addOval(Rect.fromCircle(center: centre + Offset(math.cos(a), math.sin(a)) * s * 0.035 * k, radius: s * 0.035 * k));
      }
      return Path.combine(PathOperation.union, puff, Path()..addOval(Rect.fromCircle(center: centre, radius: s * 0.045 * k)));
    }();
  }

  /// Body outlines by shape and size, made once: the fluffy one unions ten
  /// circles, too slow to redo every frame of a dance on a wall frame.
  static Path _bodyPath(int shape, double s) {
    if (_paths.length > 48) _paths.clear();
    return _paths[(shape, s)] ??= _makeBodyPath(shape, s);
  }

  static Path _makeBodyPath(int shape, double s) {
    Offset u(double x, double y) => Offset(x * s, y * s);
    switch (shape) {
      case 1:
        return Path()..addOval(Rect.fromCenter(center: u(0.5, 0.56), width: s * 0.42, height: s * 0.56));
      case 2:
        return Path()
          ..moveTo(0.5 * s, 0.32 * s)
          ..cubicTo(0.62 * s, 0.32 * s, 0.64 * s, 0.48 * s, 0.70 * s, 0.58 * s)
          ..cubicTo(0.80 * s, 0.72 * s, 0.72 * s, 0.84 * s, 0.5 * s, 0.84 * s)
          ..cubicTo(0.28 * s, 0.84 * s, 0.20 * s, 0.72 * s, 0.30 * s, 0.58 * s)
          ..cubicTo(0.36 * s, 0.48 * s, 0.38 * s, 0.32 * s, 0.5 * s, 0.32 * s)
          ..close();
      case 3:
        return Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(0.27 * s, 0.34 * s, 0.73 * s, 0.83 * s), Radius.circular(0.13 * s)));
      case 4:
        // Seven soft spikes.
        final centre = u(0.5, 0.58);
        final pts = [
          for (var i = 0; i < 14; i++) centre + Offset(math.cos(-math.pi / 2 + i * math.pi / 7), math.sin(-math.pi / 2 + i * math.pi / 7)) * s * (i.isEven ? 0.27 : 0.21),
        ];
        final p = Path()..moveTo((pts[13].dx + pts[0].dx) / 2, (pts[13].dy + pts[0].dy) / 2);
        for (var i = 0; i < 14; i++) {
          final next = pts[(i + 1) % 14];
          p.quadraticBezierTo(pts[i].dx, pts[i].dy, (pts[i].dx + next.dx) / 2, (pts[i].dy + next.dy) / 2);
        }
        return p..close();
      case 5:
        // Fluffy: a round body ringed with puffs.
        final centre = u(0.5, 0.58);
        var p = Path()..addOval(Rect.fromCircle(center: centre, radius: s * 0.2));
        for (var i = 0; i < 9; i++) {
          final a = -math.pi / 2 + i / 9 * math.pi * 2;
          p = Path.combine(PathOperation.union, p, Path()..addOval(Rect.fromCircle(center: centre + Offset(math.cos(a), math.sin(a)) * s * 0.2, radius: s * 0.075)));
        }
        return p;
      default:
        return Path()..addOval(Rect.fromCircle(center: u(0.5, 0.58), radius: s * 0.25));
    }
  }

  static void _face(Canvas canvas, double s, int face, _Body b, Color dark, double wave) {
    final k = b.k;
    final y = b.faceY;
    Offset u(double x, double yy) => Offset(x * s, yy * s);
    final e = 0.055 * k * s;
    final dx = 0.085 * k;
    final ink = Paint()
      ..color = const Color(0xFF2B2440)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.014
      ..strokeCap = StrokeCap.round;
    void eye(Offset c, double r, {double look = 0}) {
      canvas.drawCircle(c, r, Paint()..color = Colors.white);
      canvas.drawCircle(c, r, ink);
      final pupil = c + Offset(look * r * 0.25, r * 0.15);
      canvas.drawCircle(pupil, r * 0.5, Paint()..color = const Color(0xFF2B2440));
      canvas.drawCircle(pupil + Offset(-r * 0.18, -r * 0.18), r * 0.16, Paint()..color = Colors.white);
    }

    void cheeks() {
      for (final side in [-1.0, 1.0]) {
        canvas.drawOval(Rect.fromCenter(center: u(0.5 + side * 0.15 * k, y + 0.07 * k), width: s * 0.06 * k, height: s * 0.035 * k), Paint()..color = const Color(0x55FF6B8A));
      }
    }

    final mouthY = y + 0.1 * k;
    switch (face) {
      case 1:
        eye(u(0.5, y), e * 1.7, look: wave);
        canvas.drawOval(Rect.fromCenter(center: u(0.5, mouthY + 0.03 * k), width: s * 0.06 * k, height: s * 0.07 * k), Paint()..color = const Color(0xFF2B2440));
      case 2:
        eye(u(0.5 - dx * 1.15, y + 0.01), e * 0.8, look: wave);
        eye(u(0.5, y - 0.05 * k), e * 0.8, look: wave);
        eye(u(0.5 + dx * 1.15, y + 0.01), e * 0.8, look: wave);
        final grin = Path()
          ..moveTo((0.5 - 0.08 * k) * s, mouthY * s)
          ..quadraticBezierTo(0.5 * s, (mouthY + 0.1 * k) * s, (0.5 + 0.08 * k) * s, mouthY * s)
          ..close();
        canvas.drawPath(grin, Paint()..color = const Color(0xFF2B2440));
        for (final tx in [-0.03, 0.03]) {
          canvas.drawRect(Rect.fromLTWH((0.5 + tx * k - 0.015 * k) * s, mouthY * s, 0.03 * k * s, 0.025 * k * s), Paint()..color = Colors.white);
        }
      case 3:
        for (final side in [-1.0, 1.0]) {
          canvas.drawArc(Rect.fromCircle(center: u(0.5 + side * dx, y), radius: e * 0.8), 0.15 * math.pi, 0.7 * math.pi, false, ink);
        }
        canvas.drawArc(Rect.fromCenter(center: u(0.5, mouthY - 0.01 * k), width: s * 0.06 * k, height: s * 0.04 * k), 0.2 * math.pi, 0.6 * math.pi, false, ink);
        cheeks();
      case 4:
        for (final side in [-1.0, 1.0]) {
          canvas.drawArc(Rect.fromCircle(center: u(0.5 + side * dx, y + 0.02 * k), radius: e * 0.8), 1.15 * math.pi, 0.7 * math.pi, false, ink..strokeWidth = s * 0.018);
        }
        ink.strokeWidth = s * 0.014;
        final smile = Path()
          ..moveTo((0.5 - 0.09 * k) * s, (mouthY - 0.015 * k) * s)
          ..quadraticBezierTo(0.5 * s, (mouthY + 0.12 * k) * s, (0.5 + 0.09 * k) * s, (mouthY - 0.015 * k) * s)
          ..close();
        canvas.drawPath(smile, Paint()..color = const Color(0xFF2B2440));
        canvas.drawOval(Rect.fromCenter(center: u(0.5, mouthY + 0.04 * k), width: s * 0.06 * k, height: s * 0.035 * k), Paint()..color = const Color(0xFFFF7A93));
        cheeks();
      case 5:
        for (final side in [-1.0, 1.0]) {
          final c = u(0.5 + side * dx, y);
          eye(c, e, look: wave);
          for (final a in [-0.4, 0.0, 0.4]) {
            final from = c + Offset(math.sin(a), -math.cos(a)) * e;
            canvas.drawLine(from, from + Offset(math.sin(a), -math.cos(a)) * e * 0.55, ink);
          }
        }
        for (final side in [-1.0, 1.0]) {
          canvas.drawArc(Rect.fromCenter(center: u(0.5 + side * 0.025 * k, mouthY - 0.01 * k), width: s * 0.05 * k, height: s * 0.04 * k), 0, math.pi, false, ink);
        }
        cheeks();
      default:
        eye(u(0.5 - dx, y), e, look: wave);
        eye(u(0.5 + dx, y), e, look: wave);
        canvas.drawArc(Rect.fromCenter(center: u(0.5, mouthY - 0.02 * k), width: s * 0.12 * k, height: s * 0.07 * k), 0.15 * math.pi, 0.7 * math.pi, false, ink);
        cheeks();
    }
  }

  @override
  bool shouldRepaint(CreaturePainter old) => old.creature != creature || old.only != only;
}
