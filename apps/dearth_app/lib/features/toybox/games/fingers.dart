import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Finger Count (SPEC FR-TOY-03, Appendix B: fingers as numbers). "Show me
/// three fingers!": a big cartoon hand, and she raises them one at a time
/// — in order first, then any finger, then two hands for 6–10, where a tap
/// on the left palm raises a whole hand ("Five! A whole hand!"). The high
/// five button checks: right and the hand waves ("Three fingers!", and for
/// 6–10 "Five and three more make eight!"), wrong and "More fingers!" or
/// "Too many fingers!" while the fingers stay to fix. After two slips the
/// fingers that should be up are outlined. The top level turns it around:
/// the hand shows fingers and she picks the numeral.
class FingerGame extends StatefulWidget {
  const FingerGame(this.c, {super.key});
  final GameController c;

  @override
  State<FingerGame> createState() => FingerGameState();
}

@visibleForTesting
class FingerGameState extends State<FingerGame> with TickerProviderStateMixin {
  static const _shownHand = 1; // the right hand plays one-hand rounds
  static const _readHand = 0; // the left hand fills first (read mode)

  FingerRound? _round;

  /// Fingers up, [hand][finger]: hand 0 the left, 1 the right.
  late List<List<bool>> _up;
  final _tried = <int>{};
  final _wiggles = <int, int>{};
  int _slips = 0, _deal = 0, _doneHops = 0;
  bool _hint = false, _solved = false, _toldHighFive = false;
  final _timers = <Timer>[];
  Timer? _idle;

  /// Bumped on every change of the fingers, so the hands repaint.
  final _bump = ValueNotifier<int>(0);
  late final AnimationController _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  @visibleForTesting
  FingerRound get debugRound => _round!;

  /// How many fingers are up across the shown hands.
  @visibleForTesting
  int get debugUp => _total();

  @visibleForTesting
  bool get debugHint => _hint;

  @visibleForTesting
  bool get debugSolved => _solved;

  int _total() => [for (var h = 0; h < 2; h++) if (_shows(h)) _up[h].where((u) => u).length].fold(0, (a, b) => a + b);

  /// Whether hand [h] (0 left, 1 right) is on screen this round.
  bool _shows(int h) {
    final r = _round!;
    if (r.hands == 2) return true;
    return h == (r.mode == FingerMode.read ? _readHand : _shownHand);
  }

  @override
  void initState() {
    super.initState();
    _up = [for (var h = 0; h < 2; h++) List<bool>.filled(5, false)];
    _newRound();
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _idle?.cancel();
    _wave.dispose();
    _bump.dispose();
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
    _wave.stop();
    _wave.value = 0;
    _idle?.cancel();
    final r = _round = fingerRound(widget.c.level, widget.c.random, last: _round);
    _up = [for (var h = 0; h < 2; h++) List<bool>.filled(5, false)];
    if (r.mode == FingerMode.read) {
      // The left hand fills first: five and some more.
      for (var i = 0; i < math.min(r.want, 5); i++) {
        _up[_readHand][i] = true;
      }
      for (var i = 0; i < r.want - 5; i++) {
        _up[_shownHand][i] = true;
      }
    }
    _tried.clear();
    _wiggles.clear();
    _slips = 0;
    _hint = _solved = false;
    _deal++;
    _bump.value++;
    // A beat for the round to land, then the order; the high five's job
    // is explained once a session.
    _after(const Duration(milliseconds: 600), () => _sayPrompt(tellHighFive: true));
    _waitIdle();
    if (mounted) setState(() {});
  }

  void _sayPrompt({bool tellHighFive = false}) {
    final r = _round!;
    final clip = r.mode == FingerMode.read ? VoiceLine.fingersWhich : fingersShowClip(r.want);
    widget.c.say(clip);
    if (tellHighFive && r.mode != FingerMode.read && !_toldHighFive) {
      _toldHighFive = true;
      _after(afterVoice(clip), () => widget.c.say(VoiceLine.fingersHighFive));
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

  void _changed({String? say}) {
    _bump.value++;
    if (say != null) widget.c.say(say);
    if (mounted) setState(() {});
  }

  /// Raises the next finger in counting order (thumb to pinky) on the
  /// hand she plays one-handed rounds with.
  void _raiseNext(int h) {
    final i = _up[h].indexOf(false);
    if (i < 0) {
      widget.c.sound(Sfx.boing, volume: 0.4);
      return;
    }
    widget.c.sound(Sfx.pop, volume: 0.5);
    _up[h][i] = true;
    _changed(say: numberClip(_total()));
  }

  /// Lowers the last raised finger on [h].
  void _lowerLast(int h) {
    for (var i = 4; i >= 0; i--) {
      if (_up[h][i]) {
        widget.c.sound(Sfx.snap, volume: 0.45);
        _up[h][i] = false;
        _changed(say: numberClip(_total()));
        return;
      }
    }
  }

  void _tapFinger(int h, int i) {
    if (_solved) return;
    final r = _round!;
    _waitIdle();
    switch (r.mode) {
      case FingerMode.inOrder:
        // One hand, in order: a raised finger lowers the last one, any
        // other tap raises the next.
        _up[h][i] ? _lowerLast(h) : _raiseNext(h);
      case FingerMode.any:
      case FingerMode.twoHands:
        widget.c.sound(_up[h][i] ? Sfx.snap : Sfx.pop, volume: 0.5);
        _up[h][i] = !_up[h][i];
        _changed(say: numberClip(_total()));
      case FingerMode.read:
        break;
    }
  }

  void _tapPalm(int h) {
    if (_solved) return;
    final r = _round!;
    _waitIdle();
    if (r.mode == FingerMode.twoHands && h == 0) {
      // The left hand gives the five at once.
      if (_up[0].every((u) => u)) {
        widget.c.sound(Sfx.boing, volume: 0.4);
        return;
      }
      widget.c.sound(Sfx.pop, volume: 0.5);
      _up[0] = List<bool>.filled(5, true);
      _changed(say: VoiceLine.fingersFive);
      return;
    }
    if (r.mode == FingerMode.inOrder) _raiseNext(h);
  }

  /// The high five button: the round's check.
  void _done() {
    final r = _round!;
    if (_solved) return;
    _waitIdle();
    widget.c.sound(Sfx.ding, volume: 0.5);
    setState(() => _doneHops++);
    if (_total() == r.want) {
      _win();
      return;
    }
    _slips++;
    widget.c.cue();
    widget.c.say(_total() < r.want ? VoiceLine.fingersMore : VoiceLine.fingersFewer);
    setState(() => _hint = _slips >= 2);
  }

  /// Read mode: she picks the numeral for the fingers she sees.
  void _pick(int n) {
    final r = _round!;
    if (_solved || _tried.contains(n)) return;
    _waitIdle();
    if (n == r.want) {
      widget.c.sound(Sfx.sparkle);
      _win();
      return;
    }
    _slips++;
    widget.c.cue();
    widget.c.say(numberClip(n));
    setState(() {
      _tried.add(n);
      _wiggles[n] = (_wiggles[n] ?? 0) + 1;
      _hint = _slips >= 2;
    });
  }

  void _win() {
    _idle?.cancel();
    setState(() => _solved = true);
    final r = _round!;
    final clips = [if (r.want <= 5) fingersYayClip(r.want) else fingersYayClip(r.want), if (r.want > 5) fingersMakeClip(r.want)];
    var at = Duration.zero;
    for (final clip in clips) {
      if (at == Duration.zero) {
        widget.c.say(clip);
      } else {
        _after(at, () => widget.c.say(clip));
      }
      at += afterVoice(clip);
    }
    unawaited(_wave.forward(from: 0));
    _after(const Duration(milliseconds: 1200), () => unawaited(widget.c.finishRound(fingerResult(_slips), emoji: '🖐️')));
    _after(at - afterVoice(clips.last) + afterVoice(clips.last, atLeast: const Duration(milliseconds: 3200)), _newRound);
  }

  String _askLabel() {
    final r = _round!;
    if (_solved) return 'Yay! ${r.want} finger${r.want == 1 ? '' : 's'}';
    return r.mode == FingerMode.read ? 'How many fingers?' : 'Show ${r.want}';
  }

  String _handLabel(int h) => '${h == 0 ? 'Left' : 'Right'} hand: ${_up[h].where((u) => u).length} ${_up[h].where((u) => u).length == 1 ? 'finger' : 'fingers'} up';

  /// The fingers that should be up on hand [h], for the outlines after two
  /// slips: the left hand first, in counting order.
  int _hintOn(int h) {
    final r = _round!;
    if (!_hint) return 0;
    if (h == 0) return math.min(r.want, 5);
    return math.max(0, r.want - 5);
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    return Backdrop(
      top: const Color(0xFFFFF7E6),
      bottom: const Color(0xFFE6F4FF),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final wide = box.maxWidth > box.maxHeight;
              final two = r.hands == 2;
              final side = wide
                  ? math.min(box.maxHeight * 0.85, box.maxWidth * 0.32)
                  : two
                      ? math.min(box.maxWidth * 0.45, box.maxHeight * 0.5)
                      : math.min(box.maxWidth * 0.5, box.maxHeight * 0.55);
              final hands = [for (var h = 0; h < 2; h++) if (_shows(h)) h];
              Widget handsRow() => Row(mainAxisSize: MainAxisSize.min, children: [for (final h in hands) _hand(h, side)]);
              Widget? beside;
              if (r.mode == FingerMode.read) {
                final tile = math.min(math.min((wide ? box.maxHeight : box.maxHeight - side) / 3.6, box.maxWidth * 0.3), 300 * t.scale);
                beside = wide
                    ? TileRows(per: 1, children: [for (final n in r.choices) _choice(n, tile)])
                    : Padding(
                        // The 1.12 covers each tile's own padding in the row.
                        padding: EdgeInsets.only(top: side * 0.08),
                        child: TileRows(per: 3, children: [for (final n in r.choices) _choice(n, math.min(tile, (box.maxWidth - 24) / 3.4))]),
                      );
              } else {
                final d = math.max(72 * t.scale, math.min(box.maxHeight * 0.24, 150 * t.scale));
                beside = _doneButton(context, d);
              }
              // Wide: the hands centered, the check (or the numbers) beside
              // them. Tall: the hands on top, it under them.
              return wide
                  ? Row(key: ValueKey(_deal), children: [Expanded(child: Center(child: handsRow())), beside])
                  : Column(
                      key: ValueKey(_deal),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [handsRow(), beside],
                    );
            }),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'fingers.ask',
              label: _askLabel(),
              onSayAgain: _sayPrompt,
              children: r.mode == FingerMode.read
                  ? [DEmoji('✋', size: 44 * t.scale)]
                  : [
                      for (final d in '${r.want}'.split('')) GlyphView(d, height: 52 * t.scale, color: const Color(0xFF6B4FB8)),
                    ],
            ),
          ),
        ],
      ),
    );
  }

  /// One hand and, over each finger and the palm, the boxes she taps.
  Widget _hand(int h, double side) {
    final r = _round!;
    final left = h == 0;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: side * 0.02),
      child: SizedBox.square(
        dimension: side,
        child: Stack(
          children: [
            tid(
              'fingers.hand.${left ? 'left' : 'right'}',
              Semantics(
                label: _handLabel(h),
                excludeSemantics: true,
                child: RepaintBoundary(
                  child: CustomPaint(size: Size.square(side), painter: _HandPainter(up: List.of(_up[h]), hint: _hintOn(h), wave: _wave, mirrored: left, bump: _bump)),
                ),
              ),
            ),
            if (r.mode != FingerMode.read) ...[
              _palmBox(h, side),
              for (var i = 0; i < 5; i++) _fingerBox(h, i, side),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fingerBox(int h, int i, double side) {
    final b = _boxFor(h, fingerBox(i, _up[h][i]), side);
    return Positioned.fromRect(
      rect: b,
      child: tid(
        'fingers.finger.${h == 0 ? 'left' : 'right'}.$i',
        Semantics(
          label: '${kFingerNames[i]}, ${_up[h][i] ? 'up' : 'down'}',
          excludeSemantics: true,
          child: GestureDetector(
            excludeFromSemantics: true,
            behavior: HitTestBehavior.opaque,
            onTap: () => _tapFinger(h, i),
          ),
        ),
      ),
    );
  }

  Widget _palmBox(int h, double side) {
    // The palm's lower half, clear of the finger and thumb boxes.
    final b = _boxFor(h, const Rect.fromLTRB(0.30, 0.66, 0.70, 0.88), side);
    return Positioned.fromRect(
      rect: b,
      child: tid(
        'fingers.palm.${h == 0 ? 'left' : 'right'}',
        Semantics(
          label: h == 0 ? 'Left hand' : 'Right hand',
          excludeSemantics: true,
          child: GestureDetector(
            excludeFromSemantics: true,
            behavior: HitTestBehavior.opaque,
            onTap: () => _tapPalm(h),
          ),
        ),
      ),
    );
  }

  Rect _boxFor(int h, Rect fractions, double side) {
    final left = h == 0;
    final f = left ? Rect.fromLTRB(1 - fractions.right, fractions.top, 1 - fractions.left, fractions.bottom) : fractions;
    return Rect.fromLTWH(f.left * side, f.top * side, f.width * side, f.height * side);
  }

  Widget _doneButton(BuildContext context, double d) {
    final t = DTheme.of(context);
    return DPressable(
      id: 'fingers.done',
      semanticLabel: 'High five',
      excludeSemantics: true,
      onTap: _done,
      borderRadius: BorderRadius.circular(d / 2),
      child: Hop(
        count: _doneHops,
        child: Container(
          width: d,
          height: d,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFE3DCF5), width: 3), boxShadow: t.elevation.e1),
          child: DEmoji('✋', size: d * 0.5),
        ),
      ),
    );
  }

  Widget _choice(int n, double size) {
    return Padding(
      padding: EdgeInsets.all(size * 0.06),
      child: PictureTile(
        id: 'fingers.choice.$n',
        label: '$n',
        size: size,
        onTap: () => _pick(n),
        tried: _tried.contains(n),
        hint: _hint && n == _round!.want && !_solved,
        wiggles: _wiggles[n] ?? 0,
        hops: _solved && n == _round!.want ? 1 : 0,
        child: Row(mainAxisSize: MainAxisSize.min, children: [for (final d in '$n'.split('')) GlyphView(d, height: size * 0.5, color: const Color(0xFF6B4FB8))]),
      ),
    );
  }
}

/// Where finger [i] can be tapped, as fractions of the hand's square
/// (right-hand coordinates; the left hand mirrors them): the finger's
/// column from its tip down into the palm, the thumb where it lies.
Rect fingerBox(int i, bool up) {
  const xs = [0.24, 0.30, 0.42, 0.54, 0.66];
  const lens = [0.30, 0.36, 0.40, 0.37, 0.30];
  if (i == 0) return up ? const Rect.fromLTRB(0.0, 0.36, 0.31, 0.73) : const Rect.fromLTRB(0.18, 0.55, 0.56, 0.72);
  return Rect.fromLTRB(xs[i] - 0.06, 0.48 - lens[i] - 0.04, xs[i] + 0.06, 0.53);
}

/// A friendly cartoon hand, palm out: a rounded palm and five capsule
/// fingers — up ones drawn tall, down ones folded into knuckle bumps. The
/// thumb points out to the side when up and lies across the palm when
/// down. While [wave] runs the hand rocks around its wrist; when [hint]
/// fingers should be up but aren't, their shape is outlined softly. The
/// left hand is the same drawing mirrored.
class _HandPainter extends CustomPainter {
  _HandPainter({required this.up, required this.hint, required this.wave, required this.mirrored, required this.bump})
      : super(repaint: Listenable.merge([bump, wave]));

  final List<bool> up;
  final int hint;
  final Animation<double> wave;
  final bool mirrored;

  /// Bumped on any change of the fingers.
  final ValueNotifier<int> bump;

  static const _xs = [0.30, 0.42, 0.54, 0.66];
  static const _lens = [0.36, 0.40, 0.37, 0.30];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    if (mirrored) {
      canvas
        ..translate(s, 0)
        ..scale(-1, 1);
    }
    final w = wave.value;
    if (w > 0) {
      canvas
        ..translate(s * 0.5, s * 0.95)
        ..rotate(math.sin(w * math.pi * 5) * 0.14 * (1 - w * 0.4))
        ..translate(-s * 0.5, -s * 0.95);
    }
    const skin = Color(0xFFFFD3B0);
    const ink = Color(0xFFB9805A);
    final fill = Paint()..color = skin;
    final line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.025
      ..strokeJoin = StrokeJoin.round;
    void capsule(RRect r) => canvas
      ..drawRRect(r, fill)
      ..drawRRect(r, line);

    // The thumb, then the fingers, root under the palm's edge.
    final thumbUp = up[0];
    canvas.save();
    canvas.translate(s * 0.24, s * 0.66);
    canvas.rotate((thumbUp ? -50 : 80) * math.pi / 180);
    final tw = 0.11 * s;
    canvas
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-tw / 2, -0.30 * s, tw, 0.34 * s), Radius.circular(tw / 2)), fill)
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-tw / 2, -0.30 * s, tw, 0.34 * s), Radius.circular(tw / 2)), line);
    canvas.restore();
    for (var i = 1; i <= 4; i++) {
      final x = _xs[i - 1] * s, len = _lens[i - 1] * s, fw = 0.11 * s;
      if (up[i]) {
        capsule(RRect.fromRectAndRadius(Rect.fromLTWH(x - fw / 2, s * 0.48 - len, fw, len + 0.04 * s), Radius.circular(fw / 2)));
      } else {
        // Folded: a knuckle bump on the palm's top edge, with a crease.
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(x - fw / 2, s * 0.48 - 0.12, fw, 0.16 * s), Radius.circular(fw / 2));
        capsule(r);
        canvas.drawLine(Offset(x - fw * 0.28, s * 0.44), Offset(x + fw * 0.28, s * 0.44), line..strokeWidth = s * 0.016);
        line.strokeWidth = s * 0.025;
      }
    }
    // The palm.
    capsule(RRect.fromRectAndRadius(Rect.fromLTRB(0.22 * s, 0.48 * s, 0.78 * s, 0.92 * s), Radius.circular(0.12 * s)));
    // The outlines after two slips: the fingers that should be up, softly.
    if (hint > 0) {
      final glow = Paint()
        ..color = ink.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.02
        ..strokeJoin = StrokeJoin.round;
      for (var i = 0; i < hint && i < 5; i++) {
        if (up[i]) continue;
        if (i == 0) {
          canvas.save();
          canvas.translate(s * 0.24, s * 0.66);
          canvas.rotate(-50 * math.pi / 180);
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-0.055 * s, -0.30 * s, 0.11 * s, 0.34 * s), Radius.circular(0.055 * s)), glow);
          canvas.restore();
        } else {
          final x = _xs[i - 1] * s, len = _lens[i - 1] * s, fw = 0.11 * s;
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - fw / 2, s * 0.48 - len, fw, len + 0.04 * s), Radius.circular(fw / 2)), glow);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_HandPainter old) => old.up.length != up.length || old.hint != hint || old.mirrored != mirrored || List.of(old.up).join() != List.of(up).join();
}
