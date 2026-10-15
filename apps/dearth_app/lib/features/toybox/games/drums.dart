import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

enum _Phase { intro, beating, asking, playing, done }

/// The time between the bear's beats: slow enough to count each one.
const Duration _beat = Duration(milliseconds: 700);

/// Drum Count (SPEC FR-TOY-03, Appendix B: counting sounds and actions).
/// A bear with a big drum. It plays some beats and she says how many,
/// from number tiles with dots: first the voice counts along, then she
/// counts alone, watching. Then it's her turn: "Play four beats on the
/// drum!" She drums, each beat counted out loud, and when she stops the
/// bear checks. At the top a curtain hides the bear and only her ears
/// count. The 🔊 plays the beats again. Wrong tiles fade; after two the
/// right one glows.
class DrumsGame extends StatefulWidget {
  const DrumsGame(this.c, {super.key});
  final GameController c;

  @override
  State<DrumsGame> createState() => DrumsGameState();
}

@visibleForTesting
class DrumsGameState extends State<DrumsGame> with RoundVoice {
  DrumRound? _round;
  _Phase _phase = _Phase.intro;
  int _hits = 0, _played = 0, _slips = 0, _deal = 0;
  final _tried = <int>{};
  final _timers = <Timer>[];
  Timer? _done;

  /// The bear's beats this round, for screen readers and tests (the drum's
  /// label): what a hearing child takes in. Behind the curtain it isn't told.
  int _bearBeats = 0;

  @visibleForTesting
  DrumRound get debugRound => _round!;

  @visibleForTesting
  int get debugPlayed => _played;

  @override
  GameController get voiceOf => widget.c;

  @override
  String? get promptClip {
    final r = _round;
    if (r == null) return null;
    return switch (_phase) {
      _Phase.asking => VoiceLine.drumAsk,
      _Phase.playing => drumPlayClip(r.beats),
      _ => null,
    };
  }

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  @override
  void dispose() {
    _cancel();
    _done?.cancel();
    super.dispose();
  }

  void _cancel() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  void _after(Duration d, VoidCallback f) => _timers.add(Timer(d, () {
        if (mounted) f();
      }));

  void _newRound() {
    _cancel();
    _round = drumRound(widget.c.level, widget.c.random, last: _round);
    _tried.clear();
    _slips = _played = 0;
    _deal++;
    _phase = _Phase.intro;
    final r = _round!;
    if (r.mode == DrumMode.play) {
      _after(const Duration(milliseconds: 700), () {
        setState(() => _phase = _Phase.playing);
        askSoon(after: Duration.zero);
      });
    } else {
      final intro = switch (r.mode) { DrumMode.countAlong => VoiceLine.drumAlong, DrumMode.hidden => VoiceLine.drumHidden, _ => VoiceLine.drumWatch };
      _after(const Duration(milliseconds: 700), () {
        widget.c.say(intro);
        _after(afterVoice(intro), _playBeats);
      });
    }
    if (mounted) setState(() {});
  }

  /// The bear plays the round's beats, then asks.
  void _playBeats() {
    final r = _round!;
    quiet();
    setState(() {
      _phase = _Phase.beating;
      _bearBeats = 0;
    });
    for (var k = 0; k < r.beats; k++) {
      _after(_beat * k, () {
        widget.c.sound(Sfx.kick);
        if (r.mode == DrumMode.countAlong) widget.c.say(numberClip(k + 1));
        setState(() {
          _hits++;
          _bearBeats++;
        });
      });
    }
    _after(_beat * r.beats + const Duration(milliseconds: 300), () {
      setState(() => _phase = _Phase.asking);
      askSoon(after: Duration.zero);
    });
  }

  /// Her drum: in her turn a counted beat; otherwise a soft boom only
  /// while nobody is counting.
  void _tapDrum() {
    stillHere();
    final c = widget.c;
    switch (_phase) {
      case _Phase.playing:
        _played++;
        c.sound(Sfx.kick);
        c.say(numberClip(_played));
        setState(() => _hits++);
        // When she stops, the bear listens back.
        _done?.cancel();
        _done = Timer(kDrumDoneAfter, _checkPlayed);
      case _Phase.asking || _Phase.done:
        c.sound(Sfx.tom, volume: 0.4);
        setState(() => _hits++);
      case _Phase.intro || _Phase.beating:
        break;
    }
  }

  void _checkPlayed() {
    if (!mounted || _phase != _Phase.playing) return;
    final r = _round!;
    final c = widget.c;
    if (_played == r.beats) {
      _win();
      return;
    }
    // What she played, then the ask again.
    _slips++;
    c.cue();
    final was = drumWasClip(_played.clamp(1, 9));
    c.say(was);
    _played = 0;
    _after(afterVoice(was), sayPrompt);
    setState(() {});
  }

  void _pick(int n) {
    stillHere();
    if (_phase != _Phase.asking || _tried.contains(n)) return;
    if (n != _round!.beats) {
      _slips++;
      widget.c.cue();
      setState(() => _tried.add(n));
      return;
    }
    _win();
  }

  void _win() {
    final r = _round!;
    quiet();
    widget.c.say(drumYesClip(r.beats));
    setState(() => _phase = _Phase.done);
    unawaited(widget.c.finishRound(drumResult(_slips), emoji: '🥁'));
    _after(afterVoice(drumYesClip(r.beats), atLeast: const Duration(milliseconds: 2800)), _newRound);
  }

  /// The 🔊: the beats again (or what to play).
  void _again() {
    stillHere();
    if (_phase == _Phase.asking) {
      _playBeats();
    } else {
      sayPrompt();
    }
  }

  String _askLabel() {
    final r = _round!;
    return switch (_phase) {
      _Phase.playing => 'Play ${r.beats} beats ($_played so far)',
      _Phase.done => '${r.beats} beats!',
      _Phase.asking => 'How many beats?',
      _ => 'Listen',
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    final curtain = r.mode == DrumMode.hidden && _phase != _Phase.done;
    final choosing = r.mode != DrumMode.play;
    final hint = _slips >= 2 || idleHint;
    return Backdrop(
      top: const Color(0xFFFFF1DE),
      bottom: const Color(0xFFF6E3FF),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final wide = box.maxWidth > box.maxHeight;
              final stage = math.min(wide ? box.maxHeight : box.maxHeight * 0.62, wide ? box.maxWidth * (choosing ? 0.55 : 0.8) : box.maxWidth);
              final tile = math.min(math.min(wide ? box.maxHeight / 3.6 : box.maxWidth / 3.6, 220 * t.scale), wide ? box.maxWidth * 0.2 : box.maxHeight * 0.3);
              final band = _Stage(
                key: ValueKey(_deal),
                size: stage,
                hits: _hits,
                curtain: curtain,
                playing: _phase == _Phase.playing,
                label: _phase == _Phase.playing
                    ? 'Drum: $_played ${_played == 1 ? 'beat' : 'beats'}'
                    : (r.mode == DrumMode.hidden || _bearBeats == 0 ? 'Drum' : 'Drum: the bear played $_bearBeats ${_bearBeats == 1 ? 'beat' : 'beats'}'),
                onTap: _tapDrum,
              );
              final tiles = Flex(
                direction: wide ? Axis.vertical : Axis.horizontal,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final n in r.choices)
                    Padding(
                      padding: EdgeInsets.all(tile * 0.06),
                      child: PictureTile(
                        id: 'drums.choice.$n',
                        label: '$n',
                        size: tile,
                        tried: _tried.contains(n),
                        hint: hint && _phase == _Phase.asking && n == r.beats,
                        onTap: () => _pick(n),
                        child: NumberDots(n: n, size: tile),
                      ),
                    ),
                ],
              );
              final answers = Visibility(visible: choosing && (_phase == _Phase.asking || _phase == _Phase.done), maintainSize: choosing, maintainAnimation: true, maintainState: true, child: tiles);
              return wide
                  ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [band, if (choosing) ...[SizedBox(width: t.space.xl * 2), answers]])
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [band, if (choosing) ...[SizedBox(height: t.space.lg), answers]]);
            }),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'drums.ask',
              label: _askLabel(),
              onSayAgain: _again,
              children: [
                DEmoji(r.mode == DrumMode.hidden ? '👂' : '🐻', size: 44 * t.scale),
                SizedBox(width: t.space.xs),
                if (r.mode == DrumMode.play)
                  for (final digit in '${r.beats}'.split('')) GlyphView(digit, height: 52 * t.scale, color: const Color(0xFF6B4FB8))
                else
                  DEmoji(_phase == _Phase.done ? '✨' : '❓', size: 40 * t.scale),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The bear and its drum (behind a curtain at the top level): the skin
/// flashes and the stick swings on every beat; the whole drum is the
/// button.
class _Stage extends StatelessWidget {
  const _Stage({super.key, required this.size, required this.hits, required this.curtain, required this.playing, required this.label, required this.onTap});
  final double size;
  final int hits;
  final bool curtain, playing;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The bear peeks over the drum, bobbing to each beat.
            Positioned(
              left: size * 0.22,
              top: 0,
              child: IgnorePointer(child: Hop(count: hits, child: DEmoji('🐻', size: size * 0.5))),
            ),
            Positioned(
              left: size * 0.08,
              right: size * 0.08,
              bottom: 0,
              height: size * 0.6,
              child: tid(
                'drums.drum',
                Semantics(
                  button: true,
                  label: label,
                  onTap: onTap,
                  excludeSemantics: true,
                  child: Listener(
                    // On the finger going down: a drum can't wait.
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) => onTap(),
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey(hits),
                      tween: Tween(begin: hits == 0 ? 0 : 1, end: 0),
                      duration: const Duration(milliseconds: 260),
                      builder: (context, k, child) => Transform.scale(scale: 1 + 0.04 * k, child: child),
                      child: RepaintBoundary(child: CustomPaint(painter: _DrumPainter(glow: playing))),
                    ),
                  ),
                ),
              ),
            ),
            // A drumstick, swinging down on each beat.
            Positioned(
              right: size * 0.1,
              top: size * 0.24,
              child: IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey('stick$hits'),
                  tween: Tween(begin: hits == 0 ? 0 : 1, end: 0),
                  duration: const Duration(milliseconds: 300),
                  builder: (context, k, child) => Transform.rotate(angle: -0.5 + 0.7 * k, alignment: Alignment.bottomRight, child: child),
                  child: SizedBox(width: size * 0.3, height: size * 0.06, child: const RepaintBoundary(child: CustomPaint(painter: _StickPainter()))),
                ),
              ),
            ),
            if (curtain)
              Positioned.fill(
                child: IgnorePointer(
                  child: tid('drums.curtain', Semantics(label: 'Curtain closed', excludeSemantics: true, child: const RepaintBoundary(child: CustomPaint(isComplex: true, painter: _CurtainPainter())))),
                ),
              ),
          ],
        ),
      );
}

/// A big marching drum: a red shell with a zig-zag rope, a white skin.
class _DrumPainter extends CustomPainter {
  const _DrumPainter({required this.glow});
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final top = Rect.fromLTWH(w * 0.04, h * 0.02, w * 0.92, h * 0.32);
    final bottom = top.shift(Offset(0, h * 0.6));
    const ink = Color(0xFF2B2440);
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.015
      ..color = ink;
    final shell = Path()
      ..moveTo(top.left, top.center.dy)
      ..lineTo(bottom.left, bottom.center.dy)
      ..arcTo(bottom, math.pi, -math.pi, false)
      ..lineTo(top.right, top.center.dy)
      ..close();
    canvas
      ..drawPath(shell, Paint()..color = const Color(0xFFE0414F))
      ..drawPath(shell, outline);
    // The rope.
    final rope = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.012
      ..color = const Color(0xFFFFE08A);
    final zig = Path()..moveTo(top.left + w * 0.04, top.center.dy + h * 0.08);
    for (var i = 1; i <= 8; i++) {
      zig.lineTo(top.left + w * 0.04 + (top.width - w * 0.08) * i / 8, i.isOdd ? bottom.center.dy + h * 0.08 : top.center.dy + h * 0.1);
    }
    canvas.drawPath(zig, rope);
    // Rims and the skin.
    canvas
      ..drawOval(top.inflate(w * 0.01), Paint()..color = const Color(0xFFF5C334))
      ..drawOval(top.deflate(w * 0.015), Paint()..color = glow ? const Color(0xFFFFFBEA) : const Color(0xFFF7F3EC))
      ..drawOval(top.inflate(w * 0.01), outline);
  }

  @override
  bool shouldRepaint(_DrumPainter old) => old.glow != glow;
}

class _StickPainter extends CustomPainter {
  const _StickPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    canvas
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(h * 0.6, h * 0.25, size.width - h * 0.6, h * 0.5), Radius.circular(h * 0.25)), Paint()..color = const Color(0xFFC98D52))
      ..drawCircle(Offset(h * 0.6, h / 2), h * 0.5, Paint()..color = const Color(0xFFF7F3EC));
  }

  @override
  bool shouldRepaint(_StickPainter old) => false;
}

/// Red stage curtains, closed: she can only listen.
class _CurtainPainter extends CustomPainter {
  const _CurtainPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cloth = Paint()..color = const Color(0xFFB3263F);
    final fold = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.012
      ..color = const Color(0xFF7E1A2D);
    final r = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(w * 0.06));
    canvas.drawRRect(r, cloth);
    for (var i = 1; i < 8; i++) {
      final x = w * i / 8;
      canvas.drawPath(Path()
        ..moveTo(x, h * 0.12)
        ..quadraticBezierTo(x + w * 0.02, h * 0.55, x - w * 0.01, h), fold);
    }
    canvas
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h * 0.14), Radius.circular(w * 0.06)), Paint()..color = const Color(0xFF8C1D33))
      ..drawCircle(Offset(w * 0.5, h * 0.55), w * 0.05, Paint()..color = const Color(0xFFF5C334));
  }

  @override
  bool shouldRepaint(_CurtainPainter old) => false;
}
