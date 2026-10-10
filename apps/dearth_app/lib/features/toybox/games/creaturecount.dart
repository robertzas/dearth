import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'creature.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Creature Count (SPEC FR-TOY-03, Appendix B: counting out a set). A bare
/// creature asks for parts: "Give it three eyes!" A big button per asked
/// part adds one (each says the new count) and hops; a tap on a placed part
/// takes it off; the dance button checks — right and the creature dances
/// and says "Yay! Three eyes!", wrong and it shakes with "More eyes,
/// please!" or "Too many eyes!" while the parts stay to be fixed. Level 1
/// shows outlines where the parts go; after two slips every level does. The
/// top level asks with the numeral alone. Build-a-Creature's bodies, with
/// none of its face: the parts are hers to place.
class CreatureCountGame extends StatefulWidget {
  const CreatureCountGame(this.c, {super.key});
  final GameController c;

  @override
  State<CreatureCountGame> createState() => CreatureCountGameState();
}

@visibleForTesting
class CreatureCountGameState extends State<CreatureCountGame> with TickerProviderStateMixin {
  static const _danceSeconds = 2.4;

  CreatureCountRound? _round;

  /// How many of each asked part she has placed.
  final _counts = <CountPart, int>{};

  /// Hop and wiggle counts for the part buttons.
  final _adds = <CountPart, int>{};
  final _maxed = <CountPart, int>{};
  int _slips = 0, _deal = 0, _shakes = 0, _danceHops = 0;
  bool _hint = false, _solved = false, _toldDance = false;
  final _timers = <Timer>[];
  Timer? _idle;

  /// Seconds into the dance; null when standing still.
  final _dance = ValueNotifier<double?>(null);
  late final Ticker _ticker = createTicker(_tick);
  int _frames = 0;

  @visibleForTesting
  CreatureCountRound get debugRound => _round!;

  /// How many of each part are placed.
  @visibleForTesting
  Map<CountPart, int> get debugCounts => Map.of(_counts);

  /// Whether the outlines show where the parts go.
  @visibleForTesting
  bool get debugGuides => _round!.guides || _hint;

  @visibleForTesting
  bool get debugSolved => _solved;

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _idle?.cancel();
    _ticker.dispose();
    _dance.dispose();
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
    _ticker.stop();
    _dance.value = null;
    _idle?.cancel();
    _round = creatureCountRound(widget.c.level, widget.c.random, last: _round);
    _counts.clear();
    _adds.clear();
    _maxed.clear();
    _slips = 0;
    _hint = _solved = false;
    _deal++;
    // A beat for the round to land before the order; the dance button's job
    // is explained once a session.
    _after(const Duration(milliseconds: 600), () => _sayPrompt(tellDance: true));
    _waitIdle();
    if (mounted) setState(() {});
  }

  /// The clips that ask this round's parts, in order.
  List<String> _promptClips(CreatureCountRound r) => [
        if (r.numeral) ccountManyClip(r.asks.first.part) else ccountAskClip(r.asks.first.part, r.asks.first.n),
        if (!r.numeral && r.asks.length == 2) ccountAndClip(r.asks[1].part, r.asks[1].n),
      ];

  void _sayPrompt({bool tellDance = false}) {
    final clips = _promptClips(_round!);
    var at = Duration.zero;
    for (final clip in clips) {
      if (at == Duration.zero) {
        widget.c.say(clip);
      } else {
        _after(at, () => widget.c.say(clip));
      }
      at += afterVoice(clip);
    }
    if (tellDance && !_toldDance) {
      _toldDance = true;
      _after(at, () => widget.c.say(VoiceLine.ccountDance));
    }
  }

  /// A long pause asks again. Not a slip.
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 11), () {
      if (!mounted || _solved) return;
      _sayPrompt();
      _waitIdle();
    });
  }

  void _add(CountPart p) {
    if (_solved) return;
    _waitIdle();
    if ((_counts[p] ?? 0) >= kCountPartMax[p]!) {
      // The body is full: a shake, not a slip.
      widget.c.sound(Sfx.boing, volume: 0.4);
      setState(() => _maxed[p] = (_maxed[p] ?? 0) + 1);
      return;
    }
    widget.c.sound(Sfx.pop, volume: 0.5);
    setState(() {
      _counts[p] = (_counts[p] ?? 0) + 1;
      _adds[p] = (_adds[p] ?? 0) + 1;
    });
    // The count as it lands.
    _after(const Duration(milliseconds: 250), () => widget.c.say(numberClip(_counts[p] ?? 0)));
  }

  /// Whatever placed part she tapped, the last of its kind comes off, so
  /// the numbering stays one to n.
  void _remove(CountPart p) {
    if (_solved) return;
    final n = _counts[p] ?? 0;
    if (n == 0) return;
    _waitIdle();
    widget.c.sound(Sfx.snap, volume: 0.45);
    setState(() => _counts[p] = n - 1);
    widget.c.say(numberClip(n - 1));
  }

  /// The dance button: the round's check.
  void _check() {
    final r = _round!;
    if (_solved) return;
    _waitIdle();
    widget.c.sound(Sfx.ding, volume: 0.5);
    setState(() => _danceHops++);
    if (r.asks.every((a) => (_counts[a.part] ?? 0) == 0)) {
      // Nothing added at all: ask again, not a slip.
      _sayPrompt();
      return;
    }
    CountAsk? wrong;
    for (final a in r.asks) {
      if ((_counts[a.part] ?? 0) != a.n) {
        wrong = a;
        break;
      }
    }
    if (wrong == null) {
      _win();
      return;
    }
    _slips++;
    widget.c.cue();
    final have = _counts[wrong.part] ?? 0;
    widget.c.say(have < wrong.n ? ccountMoreClip(wrong.part) : ccountFewerClip(wrong.part));
    setState(() {
      _shakes++;
      if (_slips >= 2) _hint = true;
    });
  }

  /// Right: the creature dances and the parts are celebrated.
  void _win() {
    _idle?.cancel();
    setState(() => _solved = true);
    final r = _round!;
    // Level 3's second part is celebrated with its and-clip ("And two
    // legs!"), the way it was asked.
    final clips = [for (final a in r.asks) ccountYayClip(a.part, a.n)];
    if (r.asks.length == 2) clips[1] = ccountAndClip(r.asks[1].part, r.asks[1].n);
    var at = Duration.zero;
    for (final clip in clips) {
      if (at == Duration.zero) {
        widget.c.say(clip);
      } else {
        _after(at, () => widget.c.say(clip));
      }
      at += afterVoice(clip);
    }
    _startDance();
    _after(const Duration(milliseconds: 1200), () => unawaited(widget.c.finishRound(creatureCountResult(_slips), emoji: '🐙')));
    _after(at - afterVoice(clips.last) + afterVoice(clips.last, atLeast: const Duration(milliseconds: 3200)), _newRound);
  }

  void _startDance() {
    if (_dance.value != null) return;
    _frames = 0;
    _dance.value = 0;
    unawaited(_ticker.start());
    // A little tune under the voice: a pentatonic run up and back.
    const notes = [60, 64, 67, 72, 69, 67, 64, 67, 72];
    for (var i = 0; i < notes.length; i++) {
      _after(Duration(milliseconds: 250 * i), () {
        widget.c.sound(Sfx.xylophone, volume: 0.7, rate: math.pow(2, (notes[i] - kXylophoneBaseMidi) / 12).toDouble());
        if (i % 4 == 0) widget.c.sound(Sfx.kick, volume: 0.5);
      });
    }
  }

  void _tick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    if (t >= _danceSeconds) {
      _ticker.stop();
      _dance.value = null;
      if (mounted) setState(() {});
      return;
    }
    // Ambient motion: 30 fps is plenty on the slowest displays.
    if (DTheme.of(context).policy.ambientFps < 60 && (_frames++).isOdd) return;
    _dance.value = t;
  }

  String _askLabel() {
    final r = _round!;
    if (_solved) return 'Yay! ${[for (final a in r.asks) countPartLabel(a.part, a.n)].join(' and ')}';
    if (r.numeral) {
      final a = r.asks.first;
      return 'Give it this many ${kCountPartWords[a.part]!.$2}: ${a.n}';
    }
    return 'Give it ${[for (final a in r.asks) countPartLabel(a.part, a.n)].join(' and ')}';
  }

  String _creatureLabel() {
    final r = _round!;
    return 'Creature: ${[for (final a in r.asks) countPartLabel(a.part, _counts[a.part] ?? 0)].join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    return Backdrop(
      top: const Color(0xFFE9F6FF),
      bottom: const Color(0xFFFFF0F6),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final wide = box.maxWidth > box.maxHeight;
              final gap = math.max(16.0, math.min(box.maxWidth, box.maxHeight) * 0.03);
              final side = wide ? math.min(box.maxHeight, box.maxWidth * 0.58) : math.min(box.maxWidth, box.maxHeight * 0.58);
              final nButtons = r.asks.length + 1;
              var d = math.max(72 * t.scale, math.min((wide ? box.maxHeight * 0.24 : box.maxHeight * 0.2), 150 * t.scale));
              d = math.min(d, (wide ? (box.maxHeight - gap) / 2 : (box.maxWidth - gap * (nButtons - 1)) / nButtons));
              final controls = Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: d * 0.18,
                    runSpacing: d * 0.18,
                    children: [for (final a in r.asks) _partButton(context, a.part, d)],
                  ),
                  SizedBox(height: d * 0.22),
                  _danceButton(context, d),
                ],
              );
              final me = _creature(side);
              // Wide: the creature on the left, the controls beside it.
              // Tall: the creature on top, the controls in a row under it.
              final board = wide
                  ? Row(key: ValueKey(_deal), children: [me, Expanded(child: Center(child: controls))])
                  : Column(
                      key: ValueKey(_deal),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [me, SizedBox(height: gap * 1.5), controls],
                    );
              return board;
            }),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'creaturecount.ask',
              label: _askLabel(),
              onSayAgain: _sayPrompt,
              children: [
                for (var i = 0; i < r.asks.length; i++) ...[
                  if (i > 0) SizedBox(width: t.space.sm),
                  for (final digit in '${r.asks[i].n}'.split('')) GlyphView(digit, height: 52 * t.scale, color: const Color(0xFF6B4FB8)),
                  SizedBox(width: t.space.xs),
                  SizedBox.square(dimension: 44 * t.scale, child: CustomPaint(painter: _PartIconPainter(r.asks[i].part))),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The creature and, over each placed part, a box that takes it off.
  Widget _creature(double side) {
    final r = _round!;
    final b = creatureBodyBox(r.body);
    final boxes = <Widget>[
      for (final a in r.asks)
        for (var i = 0; i < (_counts[a.part] ?? 0); i++) _partBox(a.part, i, side, b),
    ];
    return SizedBox.square(
      dimension: side,
      child: Wiggle(
        count: _shakes,
        child: Stack(
          children: [
            tid(
              'creaturecount.creature',
              Semantics(
                button: true,
                label: _creatureLabel(),
                excludeSemantics: true,
                onTap: _sayPrompt,
                child: GestureDetector(
                  excludeFromSemantics: true,
                  behavior: HitTestBehavior.opaque,
                  onTap: _sayPrompt,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: Size.square(side),
                      // A copy, so shouldRepaint sees the change (the state's
                      // own map mutates in place).
                      painter: _CountCreaturePainter(round: r, counts: Map.of(_counts), guides: r.guides || _hint, dance: _dance),
                    ),
                  ),
                ),
              ),
            ),
            ...boxes,
          ],
        ),
      ),
    );
  }

  /// One transparent box over placed part [i] of [p]: tapping it takes the
  /// last of that part off.
  Widget _partBox(CountPart p, int i, double side, _Box b) {
    final (x, y, r) = _partSpots(p, _counts[p]!, _round!.body, b)[i];
    final half = 1.2 * r;
    final word = kCountPartWords[p]!.$1;
    return Positioned.fromRect(
      rect: Rect.fromLTWH((x - half) * side, (y - half) * side, half * 2 * side, half * 2 * side),
      child: tid(
        'creaturecount.part.${p.name}.$i',
        Semantics(
          label: '${word[0].toUpperCase()}${word.substring(1)} ${i + 1}',
          excludeSemantics: true,
          child: GestureDetector(
            excludeFromSemantics: true,
            behavior: HitTestBehavior.opaque,
            onTap: () => _remove(p),
          ),
        ),
      ),
    );
  }

  Widget _partButton(BuildContext context, CountPart p, double d) {
    final t = DTheme.of(context);
    final word = kCountPartWords[p]!.$1;
    return DPressable(
      id: 'creaturecount.add.${p.name}',
      semanticLabel: 'Add ${p == CountPart.eyes ? 'an' : 'a'} $word',
      excludeSemantics: true,
      onTap: () => _add(p),
      borderRadius: BorderRadius.circular(d / 2),
      child: Hop(
        count: _adds[p] ?? 0,
        child: Wiggle(
          count: _maxed[p] ?? 0,
          child: Container(
            width: d,
            height: d,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFE3DCF5), width: 3), boxShadow: t.elevation.e1),
            child: SizedBox.square(dimension: d * 0.62, child: CustomPaint(painter: _PartIconPainter(p))),
          ),
        ),
      ),
    );
  }

  Widget _danceButton(BuildContext context, double d) {
    final t = DTheme.of(context);
    return DPressable(
      id: 'creaturecount.dance',
      semanticLabel: 'Make it dance',
      excludeSemantics: true,
      onTap: _check,
      borderRadius: BorderRadius.circular(d / 2),
      child: Hop(
        count: _danceHops,
        child: Container(
          width: d,
          height: d,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFE3DCF5), width: 3), boxShadow: t.elevation.e1),
          child: DEmoji('🎵', size: d * 0.5),
        ),
      ),
    );
  }
}

/// A body's edges, as fractions of the square canvas.
typedef _Box = ({double top, double bottom, double left, double right, double faceY});

/// Where a part sits: (x, y, radius), fractions of the square canvas.
typedef _Spot = (double, double, double);

/// The top edge of body [shape] at [x] (fractions): the exact outline the
/// app draws, so horns sit on it, not above it.
double _bodyTop(int shape, double x) => switch (shape) {
      1 => 0.56 - 0.28 * math.sqrt(math.max(0, 1 - math.pow((x - 0.5) / 0.21, 2).toDouble())),
      3 => x < 0.40
          ? 0.47 - math.sqrt(math.max(0, 0.0169 - math.pow(x - 0.40, 2).toDouble()))
          : x > 0.60
              ? 0.47 - math.sqrt(math.max(0, 0.0169 - math.pow(x - 0.60, 2).toDouble()))
              : 0.34,
      _ => 0.58 - math.sqrt(math.max(0, 0.0625 - math.pow(x - 0.5, 2).toDouble())),
    };

/// Where each of [n] copies of [part] sits on body [shape] (fractions of
/// the square canvas), for the painter and the tap boxes: eyes in rows of
/// three around the face line, legs spread along the bottom, horns along
/// the top edge, spots in a three-by-three grid below the face.
List<_Spot> _partSpots(CountPart part, int n, int shape, _Box b) {
  final k = (b.right - b.left) / 0.5;
  switch (part) {
    case CountPart.eyes:
      final rows = (n + 2) ~/ 3;
      final out = <_Spot>[];
      for (var r = 0; r < rows; r++) {
        final m = math.min(3, n - 3 * r);
        final y = b.faceY + (r - (rows - 1) / 2) * 0.10;
        for (var i = 0; i < m; i++) {
          out.add((0.5 + (i - (m - 1) / 2) * 0.11 * k, y, 0.045 * k));
        }
      }
      return out;
    case CountPart.legs:
      return [
        for (var i = 0; i < n; i++) (b.left + 0.06 + (b.right - b.left - 0.12) * (n == 1 ? 0.5 : i / (n - 1)), b.bottom + 0.05, 0.05 * k),
      ];
    case CountPart.horns:
      return [
        for (var i = 0; i < n; i++)
          () {
            final x = b.left + 0.08 + (b.right - b.left - 0.16) * (n == 1 ? 0.5 : i / (n - 1));
            return (x, _bodyTop(shape, x) - 0.035 * k, 0.04 * k);
          }(),
      ];
    case CountPart.spots:
      // Dice-like: the middle, the corners, then between.
      const cells = [4, 0, 8, 2, 6, 3, 5, 1, 7];
      return [
        for (var i = 0; i < n; i++)
          (0.5 + (cells[i] % 3 - 1) * 0.09 * k, b.faceY + 0.11 + (cells[i] ~/ 3) * 0.075, 0.032 * k),
      ];
  }
}

/// The fills and lines of a creature of body color [color]: (dark, light).
(Color, Color) _inks(Color color) => (Color.lerp(color, const Color(0xFF2B2440), 0.45)!, Color.lerp(color, Colors.white, 0.45)!);

/// Draws copy [i] of [n] of [part] on body [shape] with box [b], at canvas
/// size [s]: in full color, or as a faint outline when [guide] (where a
/// wanted part goes).
void _drawPart(Canvas canvas, double s, _Box b, int shape, CountPart part, int i, int n, Color color, {bool guide = false}) {
  final k = (b.right - b.left) / 0.5;
  final (dark, light) = _inks(color);
  final (x, y, r) = _partSpots(part, n, shape, b)[i];
  Paint line() => Paint()
    ..color = (guide ? dark.withValues(alpha: 0.25) : dark)
    ..style = PaintingStyle.stroke
    ..strokeWidth = s * 0.012
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;
  switch (part) {
    case CountPart.eyes:
      final c = Offset(x * s, y * s);
      final radius = r * s;
      if (guide) {
        canvas.drawCircle(c, radius, line());
        return;
      }
      canvas
        ..drawCircle(c, radius, Paint()..color = Colors.white)
        ..drawCircle(c, radius, line());
      final pupil = c + Offset(0, radius * 0.15);
      canvas
        ..drawCircle(pupil, radius * 0.45, Paint()..color = const Color(0xFF2B2440))
        ..drawCircle(pupil + Offset(-radius * 0.18, -radius * 0.18), radius * 0.16, Paint()..color = Colors.white);
    case CountPart.legs:
      final lx = x * s;
      final leg = RRect.fromRectAndRadius(Rect.fromLTRB(lx - 0.02 * k * s, (b.bottom - 0.04) * s, lx + 0.02 * k * s, (b.bottom + 0.09) * s), Radius.circular(0.02 * k * s));
      final foot = Rect.fromCenter(center: Offset(lx, (b.bottom + 0.09) * s), width: 0.07 * k * s, height: 0.035 * k * s);
      if (guide) {
        canvas
          ..drawRRect(leg, line())
          ..drawOval(foot, line());
        return;
      }
      canvas
        ..drawRRect(leg, Paint()..color = dark)
        ..drawOval(foot, Paint()..color = dark);
    case CountPart.horns:
      final base = Offset(x * s, (_bodyTop(shape, x) + 0.01) * s);
      canvas.save();
      canvas.translate(base.dx, base.dy);
      canvas.rotate((x - 0.5) * 1.2);
      final horn = Path()
        ..moveTo(-0.025 * k * s, 0)
        ..lineTo(0, -0.08 * k * s)
        ..lineTo(0.025 * k * s, 0)
        ..close();
      if (guide) {
        canvas.drawPath(horn, line());
      } else {
        canvas
          ..drawPath(horn, Paint()..color = light)
          ..drawPath(horn, line());
      }
      canvas.restore();
    case CountPart.spots:
      final c = Offset(x * s, y * s);
      if (guide) {
        canvas.drawCircle(c, r * s, line());
        return;
      }
      canvas.drawCircle(c, r * s, Paint()..color = light);
  }
}

/// The creature she dresses: legs and horns tuck under the body, spots and
/// eyes sit on it, and guides outline where wanted parts still go. While
/// [dance] runs it bounces and sways around its feet, the way
/// Build-a-Creature's dance does.
class _CountCreaturePainter extends CustomPainter {
  _CountCreaturePainter({required this.round, required this.counts, required this.guides, required ValueNotifier<double?> dance})
      : _dance = dance,
        super(repaint: dance);

  final CreatureCountRound round;
  final Map<CountPart, int> counts;
  final bool guides;
  final ValueNotifier<double?> _dance;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final b = creatureBodyBox(round.body);
    final k = (b.right - b.left) / 0.5;
    final color = kCreatureColors[round.color % kCreatureColors.length];
    final (dark, _) = _inks(color);
    final t = _dance.value;
    final beat = t == null ? 0.0 : math.sin(t * math.pi * 2.6);
    final ground = b.bottom + ((counts[CountPart.legs] ?? 0) > 0 ? 0.1 : 0.02);
    canvas.drawOval(Rect.fromCenter(center: Offset(0.5 * s, ground * s), width: s * 0.42 * k * (1 - beat.abs() * 0.15), height: s * 0.05), Paint()..color = const Color(0x1A2B2440));
    if (t != null) {
      canvas.save();
      canvas.translate(s * 0.5, s * ground);
      canvas.rotate(beat * 0.09);
      canvas.scale(1 + beat.abs() * 0.03, 1 - beat.abs() * 0.05);
      canvas.translate(-s * 0.5, -s * ground - beat.abs() * s * 0.07);
    }
    for (var i = 0; i < (counts[CountPart.legs] ?? 0); i++) {
      _drawPart(canvas, s, b, round.body, CountPart.legs, i, counts[CountPart.legs]!, color);
    }
    for (var i = 0; i < (counts[CountPart.horns] ?? 0); i++) {
      _drawPart(canvas, s, b, round.body, CountPart.horns, i, counts[CountPart.horns]!, color);
    }
    final body = CreaturePainter.bodyPath(round.body, s);
    canvas
      ..drawPath(body, Paint()..color = color)
      ..drawPath(
        body,
        Paint()
          ..color = dark
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.014
          ..strokeJoin = StrokeJoin.round,
      );
    for (var i = 0; i < (counts[CountPart.spots] ?? 0); i++) {
      _drawPart(canvas, s, b, round.body, CountPart.spots, i, counts[CountPart.spots]!, color);
    }
    for (var i = 0; i < (counts[CountPart.eyes] ?? 0); i++) {
      _drawPart(canvas, s, b, round.body, CountPart.eyes, i, counts[CountPart.eyes]!, color);
    }
    if (guides) {
      for (final a in round.asks) {
        final have = counts[a.part] ?? 0;
        for (var i = have; i < a.n; i++) {
          _drawPart(canvas, s, b, round.body, a.part, i, a.n, color, guide: true);
        }
      }
    }
    if (t != null) canvas.restore();
  }

  @override
  bool shouldRepaint(_CountCreaturePainter old) =>
      old.round != round ||
      old.guides != guides ||
      CountPart.values.any((p) => (old.counts[p] ?? 0) != (counts[p] ?? 0));
}

/// One part on a plain grey body, for the part buttons and the pill.
class _PartIconPainter extends CustomPainter {
  const _PartIconPainter(this.part);
  final CountPart part;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    const shape = 0;
    final b = creatureBodyBox(shape);
    const color = Color(0xFFCFC7E8);
    final (dark, _) = _inks(color);
    if (part == CountPart.legs) _drawPart(canvas, s, b, shape, part, 0, 1, color);
    if (part == CountPart.horns) _drawPart(canvas, s, b, shape, part, 0, 1, color);
    final body = CreaturePainter.bodyPath(shape, s);
    canvas
      ..drawPath(body, Paint()..color = color)
      ..drawPath(
        body,
        Paint()
          ..color = dark
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.02
          ..strokeJoin = StrokeJoin.round,
      );
    if (part == CountPart.spots) _drawPart(canvas, s, b, shape, part, 0, 1, color);
    if (part == CountPart.eyes) _drawPart(canvas, s, b, shape, part, 0, 1, color);
  }

  @override
  bool shouldRepaint(_PartIconPainter old) => old.part != part;
}
