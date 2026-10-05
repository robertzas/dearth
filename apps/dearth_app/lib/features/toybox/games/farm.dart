import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';

/// Where the animals stand, as fractions of the meadow: six, or three.
const List<Offset> _six = [Offset(0.16, 0.6), Offset(0.4, 0.68), Offset(0.64, 0.6), Offset(0.86, 0.7), Offset(0.27, 0.86), Offset(0.7, 0.87)];
const List<Offset> _three = [Offset(0.2, 0.7), Offset(0.5, 0.78), Offset(0.8, 0.7)];

/// Animal Farm (SPEC FR-TOY-02, Appendix B: vocabulary and listening). A
/// tap makes an animal say hello, with its real voice and its name. Then
/// "who says…?": the farm plays a sound and she finds the animal. A wrong
/// one says its own hello (that's learning too), and after two the right
/// one starts to glow.
class FarmGame extends StatefulWidget {
  const FarmGame(this.c, {super.key});
  final GameController c;

  @override
  State<FarmGame> createState() => FarmGameState();
}

@visibleForTesting
class FarmGameState extends State<FarmGame> {
  late FarmRound _round;
  final _met = <String>{};
  int _slips = 0;
  String? _talking;
  int _talkTicket = 0;
  final _bounces = <String, int>{};
  Timer? _ask;

  /// The pause between a round won and the next: time to enjoy it.
  Timer? _next;

  /// The animal to find, for tests.
  @visibleForTesting
  String? get debugFind => _round.find?.id;

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  @override
  void dispose() {
    _ask?.cancel();
    _next?.cancel();
    super.dispose();
  }

  void _newRound() {
    _round = farmRound(widget.c.level, widget.c.random);
    _met.clear();
    _slips = 0;
    if (_round.find != null) _ask = Timer(const Duration(milliseconds: 700), _askAgain);
    if (mounted) setState(() {});
  }

  void _askAgain() {
    final find = _round.find;
    if (find != null && mounted) widget.c.sound(Sfx.values.byName(find.id));
  }

  void _hello(FarmAnimal a) {
    widget.c.sound(Sfx.values.byName(a.id));
    final ticket = ++_talkTicket;
    setState(() {
      _talking = a.id;
      _bounces[a.id] = (_bounces[a.id] ?? 0) + 1;
    });
    Timer(const Duration(milliseconds: 2200), () {
      if (mounted && _talkTicket == ticket) setState(() => _talking = null);
    });
  }

  void _tap(FarmAnimal a) {
    _hello(a);
    final find = _round.find;
    if (find == null) {
      // Free play: meeting everyone is the round.
      if (_met.add(a.id) && _met.length == _round.animals.length) _won(GameResult.win, a);
      return;
    }
    if (a.id == find.id) {
      _ask?.cancel();
      _won(resultFor(_slips, allowed: 1), a);
    } else {
      _slips++;
    }
  }

  void _won(String result, FarmAnimal a) {
    unawaited(widget.c.finishRound(result, emoji: a.emoji));
    _next = Timer(const Duration(milliseconds: 2400), _newRound);
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final find = _round.find;
    final spots = _round.animals.length == 3 ? _three : _six;
    return LayoutBuilder(builder: (context, box) {
      final size = (box.biggest.shortestSide * 0.17).clamp(64.0, 180.0);
      return Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(child: CustomPaint(painter: _FarmPainter())),
          for (final (i, a) in _round.animals.indexed)
            Positioned(
              left: spots[i].dx * box.maxWidth - size / 2,
              top: spots[i].dy * box.maxHeight - size / 2,
              child: _Animal(
                animal: a,
                size: size,
                bounces: _bounces[a.id] ?? 0,
                talking: _talking == a.id,
                // After two wrong tries, the right one glows.
                glow: find?.id == a.id && _slips >= 2,
                onTap: () => _tap(a),
              ),
            ),
          if (find != null)
            Positioned(
              top: t.space.md,
              left: 0,
              right: 0,
              child: Center(
                child: DPressable(
                  id: 'farm.listen',
                  semanticLabel: 'Who says this? Listen again',
                  excludeSemantics: true,
                  borderRadius: t.radius.pill,
                  onTap: _askAgain,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: t.space.lg, vertical: t.space.sm),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: t.radius.pill, boxShadow: t.elevation.e1),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [DEmoji('🔊', size: 44 * t.scale), SizedBox(width: t.space.sm), DEmoji('❓', size: 44 * t.scale)]),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _Animal extends StatelessWidget {
  const _Animal({required this.animal, required this.size, required this.bounces, required this.talking, required this.glow, required this.onTap});
  final FarmAnimal animal;
  final double size;
  final int bounces;
  final bool talking, glow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final body = DPressable(
      id: 'farm.animal.${animal.id}',
      semanticLabel: animal.name,
      excludeSemantics: true,
      onTap: onTap,
      borderRadius: BorderRadius.circular(size),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (glow) _Glow(size: size),
            TweenAnimationBuilder<double>(
              key: ValueKey(bounces),
              tween: Tween(begin: bounces == 0 ? 0 : 1, end: 0),
              duration: const Duration(milliseconds: 700),
              builder: (context, k, child) => Transform.translate(offset: Offset(0, -size * 0.22 * math.sin(k * math.pi) * k), child: child),
              child: DEmoji(animal.emoji, size: size * 0.86),
            ),
          ],
        ),
      ),
    );
    // The speech bubble sits beside the button, not in it: the button
    // excludes its children's semantics, so the web would never see it.
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        body,
        if (talking)
          Positioned(
            bottom: size * 0.92,
            child: IgnorePointer(
              child: tid(
                'farm.says.${animal.id}',
                Container(
                  padding: EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.xs),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(t.radius.m), boxShadow: t.elevation.e1),
                  child: Text('${animal.name} · ${animal.says}', maxLines: 1, softWrap: false, style: t.text.kidBody.copyWith(color: const Color(0xFF1E1C24))),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A soft pulsing ring: the hint.
class _Glow extends StatefulWidget {
  const _Glow({required this.size});
  final double size;

  @override
  State<_Glow> createState() => _GlowState();
}

class _GlowState extends State<_Glow> with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final Ticker _ticker = createTicker(_tick);
  int _frames = 0;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _pulse.dispose();
    super.dispose();
  }

  // The hint ring breathes forever: on the slowest displays it does so at
  // the tier's ambient fps, not every vsync (SPEC §12.3).
  void _tick(Duration elapsed) {
    if (DTheme.of(context).policy.ambientFps < 60 && (_frames++).isOdd) return;
    final cycle = _pulse.duration!.inMilliseconds * 2; // forward, then reverse
    final p = (elapsed.inMilliseconds % cycle) / cycle;
    _pulse.value = p < 0.5 ? p * 2 : 2 - p * 2;
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1.15).animate(_pulse),
          child: Container(
            width: widget.size * 1.1,
            height: widget.size * 1.1,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0xAAFFF2A8), Color(0x00FFF2A8)])),
          ),
        ),
      );
}

/// The farm: sky, sun, hills, a red barn and a fence. Painted once.
class _FarmPainter extends CustomPainter {
  const _FarmPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF8ED1FC), Color(0xFFD9F1FF)]).createShader(Offset.zero & size),
    );
    canvas.drawCircle(Offset(w * 0.86, h * 0.14), h * 0.08, Paint()..color = const Color(0xFFFFD54F));
    final cloud = Paint()..color = Colors.white.withValues(alpha: 0.9);
    for (final (x, y, r) in [(0.18, 0.13, 0.05), (0.24, 0.11, 0.065), (0.31, 0.135, 0.045), (0.55, 0.2, 0.04), (0.6, 0.18, 0.05)]) {
      canvas.drawCircle(Offset(w * x, h * y), h * r, cloud);
    }
    Path hill(double base, double amp, double phase) {
      final p = Path()..moveTo(0, h);
      for (var x = 0.0; x <= w; x += w / 40) {
        p.lineTo(x, h * base - h * amp * math.sin(x / w * math.pi * 2 + phase));
      }
      return p
        ..lineTo(w, h)
        ..close();
    }

    canvas.drawPath(hill(0.48, 0.04, 0.6), Paint()..color = const Color(0xFF9CD67A));
    // The barn, on the far hill.
    final barn = Rect.fromLTWH(w * 0.04, h * 0.27, w * 0.2, h * 0.2);
    canvas
      ..drawRect(barn, Paint()..color = const Color(0xFFC94A3B))
      ..drawPath(
        Path()
          ..moveTo(barn.left - w * 0.015, barn.top)
          ..lineTo(barn.center.dx, barn.top - h * 0.1)
          ..lineTo(barn.right + w * 0.015, barn.top)
          ..close(),
        Paint()..color = const Color(0xFF8C2F25),
      );
    final door = Rect.fromCenter(center: Offset(barn.center.dx, barn.bottom - barn.height * 0.3), width: barn.width * 0.38, height: barn.height * 0.6);
    final trim = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, w * 0.004);
    canvas
      ..drawRect(door, Paint()..color = const Color(0xFF9E3529))
      ..drawRect(door, trim)
      ..drawLine(door.topLeft, door.bottomRight, trim)
      ..drawLine(door.topRight, door.bottomLeft, trim);
    canvas.drawPath(hill(0.56, 0.03, 2.2), Paint()..color = const Color(0xFF7CC45E));
    // The fence along the meadow.
    final wood = Paint()..color = const Color(0xFFB5835A);
    final y = h * 0.53;
    for (var x = w * 0.3; x < w; x += w * 0.06) {
      canvas.drawRect(Rect.fromLTWH(x, y - h * 0.05, w * 0.012, h * 0.08), wood);
    }
    canvas
      ..drawRect(Rect.fromLTWH(w * 0.3, y - h * 0.035, w * 0.7, h * 0.012), wood)
      ..drawRect(Rect.fromLTWH(w * 0.3, y - h * 0.005, w * 0.7, h * 0.012), wood);
    final petals = Paint()..color = const Color(0xFFFFF59D);
    final rng = math.Random(4);
    for (var i = 0; i < 26; i++) {
      canvas.drawCircle(Offset(rng.nextDouble() * w, h * (0.6 + rng.nextDouble() * 0.38)), math.max(2, w * 0.004), petals);
    }
  }

  @override
  bool shouldRepaint(_FarmPainter old) => false;
}
