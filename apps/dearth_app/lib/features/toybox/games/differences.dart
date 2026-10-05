import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';

/// Spot the Difference (SPEC FR-TOY-03, Appendix B: attention). Two little
/// scenes, nearly the same: something missing, something swapped, and at
/// the later levels something turned, smaller or moved. A tap on a
/// difference (in either picture) rings it in both. Three to seven to find;
/// after a while without one, a gentle pulse shows where to look.
class DifferencesGame extends StatefulWidget {
  const DifferencesGame(this.c, {super.key});
  final GameController c;

  @override
  State<DifferencesGame> createState() => DifferencesGameState();
}

@visibleForTesting
class DifferencesGameState extends State<DifferencesGame> {
  late DifferenceRound _round;
  final _found = <int>{};
  int _misses = 0, _deal = 0;
  int? _hint;
  Offset? _puff;
  int _puffs = 0;
  Timer? _next, _hinter;

  @visibleForTesting
  DifferenceRound get debugRound => _round;

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  @override
  void dispose() {
    _next?.cancel();
    _hinter?.cancel();
    super.dispose();
  }

  void _newRound() {
    _round = differenceRound(widget.c.level, widget.c.random);
    _found.clear();
    _misses = 0;
    _hint = null;
    _deal++;
    _armHint();
    if (mounted) setState(() {});
  }

  /// After 25 seconds without a find, one of the rest pulses.
  void _armHint() {
    _hinter?.cancel();
    _hinter = Timer(const Duration(seconds: 25), () {
      if (!mounted) return;
      final left = [for (var i = 0; i < _round.spots.length; i++) if (!_found.contains(i)) i];
      if (left.isNotEmpty) setState(() => _hint = left.first);
    });
  }

  /// A tap at [p] (fractions of the picture, which is [aspect] wide per
  /// unit of height).
  void _tapAt(Offset p, double aspect) {
    if (_found.length == _round.spots.length) return;
    int? hit;
    var best = double.infinity;
    for (final (i, (x, y, r)) in _round.spots.indexed) {
      if (_found.contains(i)) continue;
      final d = Offset((p.dx - x) * aspect, p.dy - y).distance;
      if (d <= r * 1.2 && d < best) (best, hit) = (d, i);
    }
    if (hit == null) {
      _misses++;
      setState(() {
        _puff = p;
        _puffs++;
      });
      return;
    }
    widget.c.sound(Sfx.sparkle);
    setState(() {
      _found.add(hit!);
      if (_hint == hit) _hint = null;
    });
    _armHint();
    if (_found.length == _round.spots.length) {
      _hinter?.cancel();
      unawaited(widget.c.finishRound(resultFor(_misses, allowed: _round.spots.length), emoji: '🔎'));
      _next = Timer(const Duration(milliseconds: 3000), _newRound);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final n = _round.spots.length;
    return Backdrop(
      top: const Color(0xFFF5F1E8),
      bottom: const Color(0xFFEDE6D8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 120,
            child: LayoutBuilder(builder: (context, box) {
              final wide = box.maxWidth > box.maxHeight;
              // Two pictures of 4:3, side by side or one above the other.
              final w = wide ? math.min((box.maxWidth - t.space.lg) / 2, box.maxHeight * 4 / 3) : math.min(box.maxWidth, (box.maxHeight - t.space.lg) / 2 * 4 / 3);
              final size = Size(w, w * 3 / 4);
              final pictures = [
                for (final (side, parts) in [('left', _round.left), ('right', _round.right)])
                  _Picture(
                    key: ValueKey('$_deal.$side'),
                    id: 'differences.$side',
                    label: 'Found ${_found.length} of $n',
                    kit: _round.kit,
                    parts: parts,
                    size: size,
                    spots: _round.spots,
                    found: _found,
                    hint: _hint,
                    puff: _puff,
                    puffs: _puffs,
                    showSpots: side == 'right',
                    onTap: (p) => _tapAt(p, size.width / size.height),
                  ),
              ];
              return Center(
                child: wide
                    ? Row(mainAxisSize: MainAxisSize.min, children: [pictures[0], SizedBox(width: t.space.lg), pictures[1]])
                    : Column(mainAxisSize: MainAxisSize.min, children: [pictures[0], SizedBox(height: t.space.lg), pictures[1]]),
              );
            }),
          ),
          Positioned(
            top: t.space.md,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Center(
                child: tid(
                  'differences.count',
                  Semantics(
                    label: 'Found ${_found.length} of $n',
                    excludeSemantics: true,
                    child: GamePill(children: [
                      DEmoji('🔎', size: 40 * t.scale),
                      SizedBox(width: t.space.sm),
                      for (var i = 0; i < n; i++)
                        i < _found.length
                            ? DEmoji('⭐', size: 30 * t.scale)
                            // Still to find: an empty ring where its star goes.
                            : Container(
                                width: 22 * t.scale,
                                height: 22 * t.scale,
                                margin: EdgeInsets.all(4 * t.scale),
                                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFC9BFA8), width: 3 * t.scale)),
                              ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Picture extends StatelessWidget {
  const _Picture({
    super.key,
    required this.id,
    required this.label,
    required this.kit,
    required this.parts,
    required this.size,
    required this.spots,
    required this.found,
    required this.hint,
    required this.puff,
    required this.puffs,
    required this.showSpots,
    required this.onTap,
  });

  final String id, label, kit;
  final List<ScenePart> parts;
  final Size size;
  final List<(double, double, double)> spots;
  final Set<int> found;
  final int? hint;
  final Offset? puff;
  final int puffs;

  /// Spot nodes for screen readers and tests, on one of the two pictures.
  final bool showSpots;
  final ValueChanged<Offset> onTap;

  @override
  Widget build(BuildContext context) {
    final w = size.width, h = size.height;
    return SizedBox.fromSize(
      size: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(h * 0.06),
        child: Stack(
          children: [
            Positioned.fill(
              child: tid(
                id,
                Semantics(
                  label: label,
                  excludeSemantics: true,
                  child: GestureDetector(
                    excludeFromSemantics: true,
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => onTap(Offset(d.localPosition.dx / w, d.localPosition.dy / h)),
                    child: RepaintBoundary(child: CustomPaint(painter: _Backdrop(kit))),
                  ),
                ),
              ),
            ),
            for (final p in parts)
              if (p.size > 0)
                Positioned(
                  left: p.x * w - p.size * h / 2,
                  top: p.y * h - p.size * h / 2,
                  child: IgnorePointer(
                    child: Transform.flip(flipX: p.flipped, child: DEmoji(p.emoji, size: p.size * h)),
                  ),
                ),
            // Found rings, the hint, and a puff where a tap found nothing.
            Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _Rings(spots, found)))),
            if (hint != null) Positioned(left: spots[hint!].$1 * w - spots[hint!].$3 * h, top: spots[hint!].$2 * h - spots[hint!].$3 * h, child: IgnorePointer(child: _Pulse(size: spots[hint!].$3 * h * 2))),
            if (puff != null)
              Positioned(
                left: puff!.dx * w - h * 0.05,
                top: puff!.dy * h - h * 0.05,
                child: IgnorePointer(child: _Puff(key: ValueKey(puffs), size: h * 0.1)),
              ),
            if (showSpots)
              for (final (i, (x, y, _)) in spots.indexed)
                Positioned(
                  left: x * w - 12,
                  top: y * h - 12,
                  child: tid('differences.spot.$i', Semantics(label: found.contains(i) ? 'Found' : 'Difference ${i + 1}', excludeSemantics: true, child: const SizedBox.square(dimension: 24))),
                ),
          ],
        ),
      ),
    );
  }
}

/// A plain backdrop per scene kit: drawn once.
class _Backdrop extends CustomPainter {
  const _Backdrop(this.kit);
  final String kit;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    Paint grad(List<Color> colors, Rect r) => Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors).createShader(r);
    final all = Offset.zero & s;
    switch (kit) {
      case 'sea':
        canvas.drawRect(all, grad(const [Color(0xFF7FD3F7), Color(0xFF2C7FC2)], all));
        canvas.drawPath(
          Path()
            ..moveTo(0, h * 0.86)
            ..quadraticBezierTo(w * 0.5, h * 0.78, w, h * 0.88)
            ..lineTo(w, h)
            ..lineTo(0, h)
            ..close(),
          Paint()..color = const Color(0xFFF1D9A6),
        );
      case 'space':
        canvas.drawRect(all, grad(const [Color(0xFF0B1030), Color(0xFF2A2F6B)], all));
        final rng = math.Random(5);
        final star = Paint()..color = const Color(0xCCFFFFF0);
        for (var i = 0; i < 70; i++) {
          canvas.drawCircle(Offset(rng.nextDouble() * w, rng.nextDouble() * h), 0.8 + rng.nextDouble() * 1.5, star);
        }
      case 'farm':
        canvas.drawRect(all, grad(const [Color(0xFFA6DCFF), Color(0xFFE6F6FF)], all));
        canvas.drawRect(Rect.fromLTWH(0, h * 0.45, w, h * 0.55), grad(const [Color(0xFFB9E07A), Color(0xFF86C24E)], Rect.fromLTWH(0, h * 0.45, w, h * 0.55)));
        final wood = Paint()..color = const Color(0xFFC79A6B);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.44, w, h * 0.015), wood);
      default:
        canvas.drawRect(all, grad(const [Color(0xFF9ED8FF), Color(0xFFE2F4FF)], all));
        canvas.drawPath(
          Path()
            ..moveTo(0, h * 0.5)
            ..quadraticBezierTo(w * 0.4, h * 0.4, w, h * 0.52)
            ..lineTo(w, h)
            ..lineTo(0, h)
            ..close(),
          grad(const [Color(0xFF9FD86F), Color(0xFF6DBB4C)], Rect.fromLTWH(0, h * 0.4, w, h * 0.6)),
        );
    }
  }

  @override
  bool shouldRepaint(_Backdrop old) => old.kit != kit;
}

class _Rings extends CustomPainter {
  const _Rings(this.spots, this.found);
  final List<(double, double, double)> spots;
  final Set<int> found;

  @override
  void paint(Canvas canvas, Size s) {
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(4, s.height * 0.012)
      ..color = const Color(0xFFFF4D8D);
    for (final i in found) {
      final (x, y, r) = spots[i];
      canvas.drawCircle(Offset(x * s.width, y * s.height), r * s.height, ring);
    }
  }

  @override
  bool shouldRepaint(_Rings old) => old.found.length != found.length || old.spots != spots;
}

/// The hint: a soft ring that breathes.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.size});
  final double size;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
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
    _c.dispose();
    super.dispose();
  }

  // The hint breathes forever: on the slowest displays it does so at the
  // tier's ambient fps, not every vsync (SPEC §12.3).
  void _tick(Duration elapsed) {
    if (DTheme.of(context).policy.ambientFps < 60 && (_frames++).isOdd) return;
    final cycle = _c.duration!.inMilliseconds * 2; // forward, then reverse
    final p = (elapsed.inMilliseconds % cycle) / cycle;
    _c.value = p < 0.5 ? p * 2 : 2 - p * 2;
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.85, end: 1.1).animate(_c),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xAAFFD54F), width: 6)),
          ),
        ),
      );
}

/// A little gray puff where a tap found nothing: no sound, no fuss.
class _Puff extends StatelessWidget {
  const _Puff({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 500),
        builder: (context, k, _) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Color.fromRGBO(255, 255, 255, 0.7 * (1 - k)), border: Border.all(color: Color.fromRGBO(120, 110, 100, 0.5 * (1 - k)), width: 3)),
        ),
      );
}
