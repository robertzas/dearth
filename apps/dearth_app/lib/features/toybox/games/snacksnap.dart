import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'monster.dart';
import 'voice_widgets.dart';

/// Snack Snap (SPEC FR-TOY-03, Appendix B: seeing amounts at a glance).
/// Feed the Monster's orange cousin asks for a number of treats — "Four
/// treats, please!" — and plates show amounts as a pattern she must take
/// in at a glance: dots in rows, dice pips, then a ten-frame. A wrong
/// plate says its own amount ("That's three!") while it fades, so a slip
/// is still subitizing practice; two slips light the right plate. The
/// top level flashes the plates and covers them: look, then choose from
/// memory, with the say-again button for one more peek (a peeked round
/// can't be a clean win).
class SnackSnapGame extends StatefulWidget {
  const SnackSnapGame(this.c, {super.key});
  final GameController c;

  @override
  State<SnackSnapGame> createState() => SnackSnapGameState();
}

@visibleForTesting
class SnackSnapGameState extends State<SnackSnapGame> with TickerProviderStateMixin {
  SnackRound? _round;
  final _tried = <int>{};

  /// Covers taken off a plate (a tap chooses it).
  final _lifted = <int>{};

  /// Treats already flown off each plate, keyed by plate.
  final _hidden = <int, int>{};
  final _wiggles = <int, int>{};
  int _slips = 0, _deal = 0;
  bool _hint = false, _solved = false, _covered = false, _peeked = false;
  final _timers = <Timer>[];
  Timer? _idle;
  _Layout? _layout;

  late final AnimationController _chew = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 90));
  late final AnimationController _open = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  late final AnimationController _hop = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  final _look = ValueNotifier<Offset>(Offset.zero);
  Timer? _blinker;

  @visibleForTesting
  SnackRound get debugRound => _round!;

  /// Whether the flash level's covers are on.
  @visibleForTesting
  bool get debugCovered => _covered;

  @visibleForTesting
  bool get debugHint => _hint;

  @visibleForTesting
  bool get debugSolved => _solved;

  @override
  void initState() {
    super.initState();
    _newRound();
    _blinker = Timer.periodic(const Duration(milliseconds: 4100), (_) => _blink.forward(from: 0).then((_) => _blink.reverse()));
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _idle?.cancel();
    _blinker?.cancel();
    for (final c in [_chew, _shake, _blink, _open, _hop]) {
      c.dispose();
    }
    _look.dispose();
    super.dispose();
  }

  void _after(Duration d, VoidCallback f) => _timers.add(Timer(d, () {
        if (mounted) f();
      }));

  void _newRound() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    final r = _round = snackRound(widget.c.level, widget.c.random, last: _round);
    _tried.clear();
    _lifted.clear();
    _hidden.clear();
    _wiggles.clear();
    _slips = 0;
    _hint = _solved = _covered = _peeked = false;
    _deal++;
    _look.value = Offset.zero;
    // A beat for the round to land, then the order; the flash level tells
    // her to look first, then covers the plates after the ask.
    _after(const Duration(milliseconds: 600), () {
      if (r.flash) {
        widget.c.say(VoiceLine.snackLook);
        _after(afterVoice(VoiceLine.snackLook), () => widget.c.say(snackWantClip(r.want)));
        _after(afterVoice(VoiceLine.snackLook) + const Duration(milliseconds: 2000), () {
          if (!_solved) setState(() => _covered = true);
        });
      } else {
        widget.c.say(snackWantClip(r.want));
      }
    });
    _waitIdle();
    if (mounted) setState(() {});
  }

  /// The pill's 🔊 and a tap on the monster: the ask again, and at the
  /// flash level one more peek at the plates.
  void _sayAgain() {
    final r = _round!;
    widget.c.say(snackWantClip(r.want));
    if (r.flash && !_solved) {
      _peeked = true;
      setState(() => _covered = false);
      _after(const Duration(milliseconds: 1500), () {
        if (!_solved) setState(() => _covered = true);
      });
    }
  }

  /// A long pause asks again. Not a slip.
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 11), () {
      if (!mounted || _solved) return;
      widget.c.say(snackWantClip(_round!.want));
      _waitIdle();
    });
  }

  void _lookAt(Offset p) {
    final l = _layout;
    if (l == null) return;
    final d = p - l.eyes;
    _look.value = d.distance < 1 ? Offset.zero : d / math.max(d.distance, l.monster.width * 0.6);
  }

  void _pick(int i) {
    final r = _round!;
    if (_solved || _tried.contains(i)) return;
    _waitIdle();
    final l = _layout;
    if (l != null) _lookAt(l.plates[i].center);
    if (i == r.answer) {
      _serve(i);
      return;
    }
    _slips++;
    widget.c.cue();
    widget.c.say(snackThatsClip(r.plates[i].n));
    setState(() {
      _tried.add(i);
      _lifted.add(i);
      _wiggles[i] = (_wiggles[i] ?? 0) + 1;
      _hint = _slips >= 2;
    });
  }

  /// Right: the treats fly to the monster one by one, then it chews and
  /// hops.
  void _serve(int i) {
    final r = _round!;
    _idle?.cancel();
    setState(() {
      _solved = true;
      _lifted.add(i);
    });
    final yum = snackYumClip(r.want);
    widget.c.say(yum);
    unawaited(_open.forward());
    final n = r.plates[i].n;
    for (var k = 0; k < n; k++) {
      _after(Duration(milliseconds: 150 * k + 150), () {
        widget.c.sound(Sfx.munch, volume: 0.35);
        setState(() => _hidden[i] = k + 1);
      });
    }
    final done = Duration(milliseconds: 150 * n + 500);
    _after(done, () {
      unawaited(_open.reverse());
      unawaited(_chew.forward(from: 0));
      unawaited(_hop.forward(from: 0));
      _look.value = Offset.zero;
      unawaited(widget.c.finishRound(snackResult(_slips, peeked: _peeked), emoji: '🥨'));
    });
    _after(afterVoice(yum, atLeast: done + const Duration(milliseconds: 2200)), _newRound);
  }

  String _askLabel() {
    final n = _round!.want;
    return _solved ? 'Yum! $n treat${n == 1 ? '' : 's'}' : 'Snack: $n treat${n == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    return Backdrop(
      top: const Color(0xFFFFF4E0),
      bottom: const Color(0xFFE8F5E9),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final l = _layout = _Layout.of(box.biggest, r.plates.length, t.scale);
              return Stack(
                key: ValueKey(_deal),
                clipBehavior: Clip.none,
                children: [
                  Positioned.fromRect(
                    rect: l.monster,
                    child: tid(
                      'snacksnap.monster',
                      Semantics(
                        button: true,
                        label: 'The monster',
                        excludeSemantics: true,
                        onTap: _sayAgain,
                        child: GestureDetector(
                          excludeFromSemantics: true,
                          onTap: _sayAgain,
                          child: RepaintBoundary(child: CustomPaint(painter: MonsterPainter(chew: _chew, shake: _shake, blink: _blink, open: _open, hop: _hop, look: _look, skin: MonsterSkin.orange))),
                        ),
                      ),
                    ),
                  ),
                  for (var i = 0; i < r.plates.length; i++)
                    Positioned.fromRect(
                      rect: l.plates[i],
                      child: PictureTile(
                        id: 'snacksnap.plate.$i',
                        label: _covered && !_lifted.contains(i) ? 'Covered plate' : 'Plate with ${r.plates[i].n} treat${r.plates[i].n == 1 ? '' : 's'}',
                        size: l.plates[i].width,
                        onTap: () => _pick(i),
                        tried: _tried.contains(i),
                        hint: _hint && i == r.answer && !_solved,
                        wiggles: _wiggles[i] ?? 0,
                        hops: _solved && i == r.answer ? 1 : 0,
                        child: RepaintBoundary(child: CustomPaint(painter: _PlatePainter(plate: r.plates[i], hidden: _hidden[i] ?? 0, covered: _covered && !_lifted.contains(i)), size: Size.infinite)),
                      ),
                    ),
                  // Treats on their way to the monster's mouth.
                  for (var i = 0; i < r.plates.length; i++)
                    for (var k = 0; k < (_hidden[i] ?? 0); k++)
                      _flying('f$i-$k', l.treatAt(i, k, r.plates[i]), l.mouth, l.treatSize(r.plates[i])),
                ],
              );
            }),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'snacksnap.ask',
              label: _askLabel(),
              onSayAgain: _sayAgain,
              children: [
                for (final d in '${r.want}'.split('')) GlyphView(d, height: 52 * t.scale, color: const Color(0xFF6B4FB8)),
                SizedBox(width: t.space.sm),
                DEmoji('🥨', size: 44 * t.scale),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A treat flying to the monster's mouth, shrinking as it goes.
  Widget _flying(String key, Offset from, Offset to, double size) => TweenAnimationBuilder<double>(
        key: ValueKey(key),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInCubic,
        builder: (context, k, child) {
          final at = Offset.lerp(from, to, k)!;
          final s = size * (1 - 0.8 * k);
          return Positioned(left: at.dx - s / 2, top: at.dy - s / 2, width: s, height: s, child: k >= 1 ? const SizedBox.shrink() : child!);
        },
        child: const IgnorePointer(child: RepaintBoundary(child: CustomPaint(painter: _TreatPainter(), size: Size.infinite))),
      );
}

/// Where the monster and the plates stand in the play area. Wide: the
/// monster on the left, the plates in one row beside it. Tall: the
/// monster on top, the plates in rows of two below.
class _Layout {
  _Layout(this.monster, this.plates);
  final Rect monster;
  final List<Rect> plates;

  factory _Layout.of(Size a, int count, double scale) {
    final gap = math.max(12.0, a.shortestSide * 0.03);
    if (a.width > a.height * 1.1) {
      final side = math.min(a.height * 0.75, a.width * 0.3);
      final monster = Rect.fromLTWH(0, (a.height - side) / 2, side, side);
      final left = side + gap * 2;
      final tile = math.min(math.min((a.width - left - gap * (count - 1)) / count, a.height * 0.6), 320 * scale);
      final y = a.height / 2;
      return _Layout(monster, [
        for (var i = 0; i < count; i++) Rect.fromCenter(center: Offset(left + (a.width - left) / 2 + (i - (count - 1) / 2) * (tile + gap), y), width: tile, height: tile),
      ]);
    }
    final side = math.min(a.width * 0.45, a.height * 0.42);
    final monster = Rect.fromLTWH((a.width - side) / 2, 0, side, side);
    const per = 2;
    final rows = (count + per - 1) ~/ per;
    final below = a.height - side - gap;
    final tile = math.min(math.min((a.width - gap * (per - 1)) / per, below / rows - gap), 320 * scale);
    return _Layout(monster, [
      for (var i = 0; i < count; i++)
        () {
          final row = i ~/ per;
          final inRow = math.min(per, count - row * per);
          final x = a.width / 2 + (i % per - (inRow - 1) / 2) * (tile + gap);
          final y = side + gap + below / 2 + (row - (rows - 1) / 2) * (tile + gap);
          return Rect.fromCenter(center: Offset(x, y), width: tile, height: tile);
        }(),
    ]);
  }

  Offset get mouth => monster.topLeft + Offset(MonsterPainter.mouthAt.dx * monster.width, MonsterPainter.mouthAt.dy * monster.height);
  Offset get eyes => monster.topLeft + Offset(MonsterPainter.eyesAt.dx * monster.width, MonsterPainter.eyesAt.dy * monster.height);

  /// Treat [k]'s resting spot on plate [i], in play-area coordinates.
  Offset treatAt(int i, int k, SnackPlate p) {
    final rect = plates[i];
    final (x, y) = snackDots(p)[k];
    return rect.center + Offset((x - 0.5) * rect.width * 0.8, (y - 0.5) * rect.height * 0.8);
  }

  /// A treat's flying size: the painted ring's diameter.
  double treatSize(SnackPlate p) => plates.first.width * (p.pattern == SnackPattern.frame ? 0.14 : 0.18);
}

/// A pretzel: a fat brown ring with a dark edge and a glint of glaze.
void _paintTreat(Canvas canvas, Offset c, double r) {
  canvas
    ..drawCircle(c, r, Paint()..color = const Color(0xFF8A5A2B))
    ..drawCircle(c, r * 0.86, Paint()..color = const Color(0xFFC98A3D))
    ..drawCircle(c, r * 0.5, Paint()..color = Colors.white)
    ..drawArc(
      Rect.fromCircle(center: c, radius: r * 0.86),
      -1.3,
      1.1,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.16
        ..strokeCap = StrokeCap.round,
    );
}

class _TreatPainter extends CustomPainter {
  const _TreatPainter();

  @override
  void paint(Canvas canvas, Size size) => _paintTreat(canvas, size.center(Offset.zero), size.shortestSide / 2);

  @override
  bool shouldRepaint(_TreatPainter old) => false;
}

/// One plate: a round white plate, its [plate] treats as the pattern says
/// (the first [hidden] already flown), and the flash level's cover dome.
class _PlatePainter extends CustomPainter {
  const _PlatePainter({required this.plate, required this.hidden, required this.covered});
  final SnackPlate plate;
  final int hidden;
  final bool covered;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    canvas
      ..drawOval(Rect.fromCircle(center: c + Offset(0, s * 0.03), radius: s * 0.44), Paint()..color = const Color(0x142B2440))
      ..drawCircle(c, s * 0.44, Paint()..color = Colors.white)
      ..drawCircle(
        c,
        s * 0.38,
        Paint()
          ..color = const Color(0xFFEFEAF6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, s * 0.02),
      );
    // The ten-frame's empty cells, so the frame is what she sees.
    if (plate.pattern == SnackPattern.frame) {
      for (var row = 0; row < 2; row++) {
        for (var col = 0; col < 5; col++) {
          final at = c + Offset((0.1 + col * 0.2 - 0.5) * s * 0.8, ((row == 0 ? 0.3 : 0.7) - 0.5) * s * 0.8);
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: at, width: s * 0.13, height: s * 0.13), Radius.circular(s * 0.02)), Paint()..color = const Color(0x142B2440));
        }
      }
    }
    final dots = snackDots(plate);
    for (var k = hidden; k < dots.length; k++) {
      final (x, y) = dots[k];
      _paintTreat(canvas, c + Offset((x - 0.5) * s * 0.8, (y - 0.5) * s * 0.8), s * (plate.pattern == SnackPattern.frame ? 0.07 : 0.09));
    }
    if (covered) {
      // A silver plate cover: a dome with a shine and a knob.
      final dome = Rect.fromCircle(center: c + Offset(0, -s * 0.02), radius: s * 0.42);
      final path = Path()
        ..moveTo(dome.left, dome.center.dy)
        ..arcTo(dome, math.pi, math.pi, false)
        ..close();
      canvas
        ..drawPath(path, Paint()..color = const Color(0xFFCFD6E3))
        ..drawArc(
          dome.deflate(s * 0.07),
          math.pi * 1.15,
          math.pi * 0.32,
          false,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.035
            ..strokeCap = StrokeCap.round,
        )
        ..drawCircle(Offset(c.dx, dome.top + s * 0.03), s * 0.05, Paint()..color = const Color(0xFFAEB9CC))
        ..drawPath(
          path,
          Paint()
            ..color = const Color(0xFF8B98AC)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(2, s * 0.02),
        );
    }
  }

  @override
  bool shouldRepaint(_PlatePainter old) => old.plate.n != plate.n || old.plate.pattern != plate.pattern || old.hidden != hidden || old.covered != covered;
}
