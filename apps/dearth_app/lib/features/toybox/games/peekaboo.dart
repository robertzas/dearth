import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

enum _Phase { arriving, hiding, asking, done }

/// Peekaboo Pals (SPEC FR-TOY-03, Appendix B: parts of a number, the
/// missing part). Friends hop into the meadow one by one, counted out loud
/// ("Five friends are playing!"); then some run behind the bush. How many
/// are hiding? She picks a number tile; then "Peekaboo!" and the hiders pop
/// up over the bush ("Three were hiding!"). Wrong tiles fade, and after
/// two the bush giggles and the right tile glows. At the top the friends
/// are only a number on a sign, and some were hiding before she looked.
class PeekabooGame extends StatefulWidget {
  const PeekabooGame(this.c, {super.key});
  final GameController c;

  @override
  State<PeekabooGame> createState() => PeekabooGameState();
}

@visibleForTesting
class PeekabooGameState extends State<PeekabooGame> with RoundVoice {
  PeekabooRound? _round;
  _Phase _phase = _Phase.arriving;
  int _arrived = 0, _slips = 0, _deal = 0, _bushShakes = 0;
  final _tried = <int>{};
  final _timers = <Timer>[];

  @visibleForTesting
  PeekabooRound get debugRound => _round!;

  @visibleForTesting
  bool get debugAsking => _phase == _Phase.asking;

  @override
  GameController get voiceOf => widget.c;

  @override
  String? get promptClip {
    final r = _round;
    if (r == null || _phase != _Phase.asking) return null;
    return r.sign ? peekSignClip(r.total) : VoiceLine.peekAsk;
  }

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
    _round = peekabooRound(widget.c.level, widget.c.random, last: _round);
    final r = _round!;
    _tried.clear();
    _slips = 0;
    _deal++;
    if (r.sign) {
      // The hiders are already hiding: only the ones showing come in.
      _arrived = r.total;
      _phase = _Phase.asking;
      askSoon(after: const Duration(milliseconds: 700));
    } else {
      _arrived = 0;
      _phase = _Phase.arriving;
      // Each friend hops in with its number; then how many, then they hide.
      for (var k = 0; k < r.total; k++) {
        _after(Duration(milliseconds: 600 + 650 * k), () {
          widget.c.sound(Sfx.pop, volume: 0.5, rate: 0.9 + k * 0.05);
          widget.c.say(numberClip(k + 1));
          setState(() => _arrived = k + 1);
        });
      }
      final counted = Duration(milliseconds: 600 + 650 * r.total) + afterVoice(numberClip(r.total)) - const Duration(milliseconds: 400);
      _after(counted, () => widget.c.say(peekPlayClip(r.total)));
      final played = counted + afterVoice(peekPlayClip(r.total));
      _after(played, () {
        widget.c.say(VoiceLine.peekHide);
        widget.c.sound(Sfx.boing, volume: 0.4);
        setState(() => _phase = _Phase.hiding);
      });
      _after(played + afterVoice(VoiceLine.peekHide, atLeast: const Duration(milliseconds: 1200)), () {
        setState(() => _phase = _Phase.asking);
        askSoon(after: Duration.zero);
      });
    }
    if (mounted) setState(() {});
  }

  void _pick(int n) {
    stillHere();
    final r = _round!;
    if (_phase != _Phase.asking || _tried.contains(n)) return;
    if (n != r.hiding) {
      _slips++;
      widget.c.cue();
      setState(() {
        _tried.add(n);
        _bushShakes++;
      });
      return;
    }
    quiet();
    final c = widget.c;
    c.say(VoiceLine.peekBoo);
    c.sound(Sfx.sparkle);
    setState(() => _phase = _Phase.done);
    unawaited(c.finishRound(peekabooResult(_slips), emoji: r.friend));
    _after(afterVoice(VoiceLine.peekBoo), () => c.say(peekYesClip(r.hiding)));
    _after(afterVoice(VoiceLine.peekBoo) + afterVoice(peekYesClip(r.hiding), atLeast: const Duration(milliseconds: 2400)), _newRound);
  }

  /// The bush: a tap makes it giggle (a peek is fun, never a slip).
  void _tapBush() {
    stillHere();
    widget.c.sound(Sfx.boing, volume: 0.4, rate: 1.3);
    setState(() => _bushShakes++);
  }

  String _askLabel() {
    final r = _round!;
    return switch (_phase) {
      _Phase.arriving => '$_arrived friends',
      _Phase.hiding => 'Hiding!',
      _Phase.asking => r.sign ? '${r.total} friends: how many are hiding? ${r.showing} showing' : 'How many are hiding? ${r.showing} showing',
      _Phase.done => '${r.hiding} were hiding!',
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    final hint = _slips >= 2 || idleHint;
    return Backdrop(
      top: const Color(0xFFD7F0FF),
      bottom: const Color(0xFFEAF8DF),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(child: CustomPaint(isComplex: true, painter: _MeadowPainter())),
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final wide = box.maxWidth > box.maxHeight;
              final sceneW = wide ? box.maxWidth * 0.72 : box.maxWidth;
              final sceneH = wide ? box.maxHeight : box.maxHeight * 0.62;
              final tile = math.min(math.min(wide ? box.maxHeight / 3.6 : box.maxWidth / 3.6, 220 * t.scale), wide ? box.maxWidth * 0.22 : box.maxHeight * 0.3);
              final scene = SizedBox(
                key: ValueKey(_deal),
                width: sceneW,
                height: sceneH,
                child: _Scene(round: r, arrived: _arrived, phase: _phase, bushShakes: _bushShakes, onBush: _tapBush),
              );
              final tiles = Flex(
                direction: wide ? Axis.vertical : Axis.horizontal,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final n in r.choices)
                    Padding(
                      padding: EdgeInsets.all(tile * 0.06),
                      child: PictureTile(
                        id: 'peekaboo.choice.$n',
                        label: '$n',
                        size: tile,
                        tried: _tried.contains(n),
                        hint: hint && _phase == _Phase.asking && n == r.hiding,
                        onTap: () => _pick(n),
                        child: NumberDots(n: n, size: tile),
                      ),
                    ),
                ],
              );
              final answers = Visibility(visible: _phase == _Phase.asking || _phase == _Phase.done, maintainSize: true, maintainAnimation: true, maintainState: true, child: tiles);
              return wide
                  ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [scene, SizedBox(width: t.space.lg), answers])
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [scene, SizedBox(height: t.space.lg), answers]);
            }),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'peekaboo.ask',
              label: _askLabel(),
              onSayAgain: sayPrompt,
              children: [
                if (r.sign) ...[for (final digit in '${r.total}'.split('')) GlyphView(digit, height: 52 * t.scale, color: const Color(0xFF6B4FB8)), SizedBox(width: t.space.xs)],
                DEmoji(r.friend, size: 40 * t.scale),
                SizedBox(width: t.space.xs),
                DEmoji('🌳', size: 40 * t.scale),
                DEmoji(_phase == _Phase.done ? '🙌' : '❓', size: 40 * t.scale),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The meadow: friends in a row on the grass, the bush they hide behind,
/// and (at the top level) the sign with how many play.
class _Scene extends StatelessWidget {
  const _Scene({required this.round, required this.arrived, required this.phase, required this.bushShakes, required this.onBush});
  final PeekabooRound round;
  final int arrived;
  final _Phase phase;
  final int bushShakes;
  final VoidCallback onBush;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final r = round;
        final bush = Rect.fromCenter(center: Offset(w * 0.76, h * 0.66), width: math.min(w * 0.42, h * 0.7), height: math.min(w * 0.3, h * 0.5));
        // The row stays clear of the bush on the right.
        final rowW = math.max(0.0, bush.left - w * 0.08);
        final friend = math.min(math.min(rowW / (r.total <= 5 ? math.max(r.total, 3) : 5) * 0.95, h * 0.28), 180.0);
        final perRow = r.total <= 5 ? r.total : 5;
        // Who shows and who hides: the hiders are the last ones in.
        Offset place(int i) {
          final row = i ~/ 5, col = i % 5;
          final inRow = math.min(perRow, r.total - row * 5);
          return Offset(w * 0.04 + rowW * (col + 0.5 + (perRow - inRow) / 2) / perRow, h * 0.62 + row * friend * 0.9 - (r.total > 5 ? friend * 0.45 : 0));
        }

        Offset hideAt(int k) => bush.center + Offset((k - (r.hiding - 1) / 2) * friend * 0.35, bush.height * 0.1);
        Offset popAt(int k) => Offset(bush.center.dx + (k - (r.hiding - 1) / 2) * friend * 0.75, bush.top - friend * 0.35);
        final hiders = [for (var i = r.showing; i < r.total; i++) i];
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < r.total; i++)
              if (_visible(i))
                AnimatedPositioned(
                  duration: Duration(milliseconds: phase == _Phase.done ? 500 : 900),
                  curve: phase == _Phase.done ? Curves.easeOutBack : Curves.easeInOut,
                  left: _spot(i, place, hideAt, popAt, hiders).dx - friend / 2,
                  top: _spot(i, place, hideAt, popAt, hiders).dy - friend / 2,
                  child: IgnorePointer(
                    child: tid(
                      'peekaboo.friend.$i',
                      Semantics(
                        label: hiders.contains(i) && phase != _Phase.done && phase != _Phase.arriving ? 'A friend, hiding' : 'A friend',
                        excludeSemantics: true,
                        child: Hop(count: i < arrived ? 1 : 0, child: DEmoji(r.friend, size: friend)),
                      ),
                    ),
                  ),
                ),
            // The bush, in front of whoever hides behind it.
            Positioned.fromRect(
              rect: bush,
              child: tid(
                'peekaboo.bush',
                Semantics(
                  button: true,
                  label: 'The bush',
                  onTap: onBush,
                  excludeSemantics: true,
                  child: GestureDetector(
                    excludeFromSemantics: true,
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => onBush(),
                    child: Wiggle(count: bushShakes, child: const RepaintBoundary(child: CustomPaint(painter: _BushPainter()))),
                  ),
                ),
              ),
            ),
            if (r.sign)
              Positioned(
                left: w * 0.06,
                top: h * 0.06,
                child: tid(
                  'peekaboo.sign',
                  Semantics(label: '${r.total} friends', excludeSemantics: true, child: _Sign(n: r.total, friend: r.friend, size: math.min(h * 0.32, w * 0.28))),
                ),
              ),
          ],
        );
      });

  bool _visible(int i) => round.sign ? true : i < arrived;

  /// Where friend [i] is now: in the row, behind the bush, or popping up.
  Offset _spot(int i, Offset Function(int) place, Offset Function(int) hideAt, Offset Function(int) popAt, List<int> hiders) {
    final k = hiders.indexOf(i);
    if (k < 0) return place(i);
    return switch (phase) {
      _Phase.arriving => round.sign ? hideAt(k) : place(i),
      _Phase.hiding || _Phase.asking => hideAt(k),
      _Phase.done => popAt(k),
    };
  }
}

/// A wooden sign: the number of friends and one of them.
class _Sign extends StatelessWidget {
  const _Sign({required this.n, required this.friend, required this.size});
  final int n;
  final String friend;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size * 1.1,
        height: size,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Positioned(bottom: 0, child: Container(width: size * 0.08, height: size * 0.5, color: const Color(0xFF8C5A2B))),
            Container(
              width: size * 1.1,
              height: size * 0.62,
              decoration: BoxDecoration(color: const Color(0xFFE7B57A), borderRadius: BorderRadius.circular(size * 0.08), border: Border.all(color: const Color(0xFF8C5A2B), width: size * 0.03)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final digit in '$n'.split('')) GlyphView(digit, height: size * 0.42, color: const Color(0xFF2B2440)),
                  SizedBox(width: size * 0.04),
                  DEmoji(friend, size: size * 0.34),
                ],
              ),
            ),
          ],
        ),
      );
}

/// A round, leafy bush: overlapping greens with a few darker leaves.
class _BushPainter extends CustomPainter {
  const _BushPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final dark = Paint()..color = const Color(0xFF3E9A4A);
    final mid = Paint()..color = const Color(0xFF54B95C);
    final light = Paint()..color = const Color(0xFF79CF6E);
    for (final (x, y, r, p) in [
      (0.22, 0.62, 0.3, dark), (0.5, 0.5, 0.38, dark), (0.78, 0.62, 0.3, dark), //
      (0.3, 0.52, 0.27, mid), (0.55, 0.4, 0.3, mid), (0.74, 0.5, 0.26, mid),
      (0.4, 0.36, 0.17, light), (0.62, 0.3, 0.14, light),
    ]) {
      canvas.drawCircle(Offset(w * x, h * y), math.min(w, h * 1.3) * r, p);
    }
    canvas.drawRect(Rect.fromLTWH(0, h * 0.82, w, h * 0.18), dark);
    final berry = Paint()..color = const Color(0xFFE94B6A);
    for (final (x, y) in const [(0.3, 0.55), (0.6, 0.45), (0.72, 0.68), (0.45, 0.7)]) {
      canvas.drawCircle(Offset(w * x, h * y), math.min(w, h) * 0.035, berry);
    }
  }

  @override
  bool shouldRepaint(_BushPainter old) => false;
}

/// Sky, a sun and the meadow's grass. Painted once.
class _MeadowPainter extends CustomPainter {
  const _MeadowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawCircle(Offset(w * 0.08, h * 0.18), size.shortestSide * 0.06, Paint()..color = const Color(0xFFFFD54F));
    final grass = Path()
      ..moveTo(0, h * 0.6)
      ..quadraticBezierTo(w * 0.35, h * 0.52, w * 0.65, h * 0.58)
      ..quadraticBezierTo(w * 0.85, h * 0.62, w, h * 0.56)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(grass, Paint()..color = const Color(0xFFA5DC86));
    final flower = Paint()..color = const Color(0xFFFFF59D);
    final rng = math.Random(9);
    for (var i = 0; i < 18; i++) {
      canvas.drawCircle(Offset(rng.nextDouble() * w, h * (0.66 + rng.nextDouble() * 0.32)), math.max(2, w * 0.004), flower);
    }
  }

  @override
  bool shouldRepaint(_MeadowPainter old) => false;
}
