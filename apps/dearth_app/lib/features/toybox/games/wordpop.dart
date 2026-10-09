import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'bubbles.dart';
import 'voice_widgets.dart';

/// Word Pop (SPEC FR-TOY-03, Appendix B: early reading, at a glance).
/// Bubble Pop's bubbles drift up the screen with a word printed on each, in
/// the Toybox's print. The voice asks for one ("Find the word: go."), and
/// she pops three bubbles that say it: each bursts with a pop and the voice
/// reads it, and a bubble fills in the pill at the top. A bubble with
/// another word bounces and reads itself, so a slip is still reading; after
/// two, or a long pause, the bubbles she's after get a golden ring. There
/// are always at least two of them up.
class WordPopGame extends StatefulWidget {
  const WordPopGame(this.c, {super.key});
  final GameController c;

  @override
  State<WordPopGame> createState() => WordPopGameState();
}

class _Bubble {
  _Bubble(this.id, this.word, this.x, this.y, this.color, this.phase, this.speed);
  final int id;
  final String word;
  double x, y;
  final int color;
  final double phase;
  double speed;

  /// A bounce on a wrong word (seconds left).
  double wobble = 0;
}

class _Spark {
  _Spark(this.x, this.y, this.vx, this.vy, this.color, this.size);
  double x, y, vx, vy, life = 0.7;
  final Color color;
  final double size;
}

@visibleForTesting
class WordPopGameState extends State<WordPopGame> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _bubbles = <_Bubble>[];
  final _sparks = <_Spark>[];
  final _repaint = ValueNotifier<int>(0);

  /// Bumped when bubble positions are worth re-announcing (the test-id
  /// layer): every other moving frame, not every one.
  final _moved = ValueNotifier<int>(0);
  Size _size = Size.zero;
  double _radius = 60;
  Duration _last = Duration.zero;
  double _clock = 0, _spawnIn = 0;
  int _frames = 0, _next = 0, _popped = 0, _slips = 0;
  bool _done = false, _glow = false;
  WordPopRound? _round;
  final _words = <String, (ui.Picture, Size)>{};
  double _wordsFor = 0;
  final _timers = <Timer>[];
  Timer? _idle;
  bool _slow = false;

  math.Random get _rng => widget.c.random;

  @visibleForTesting
  WordPopRound get debugRound => _round!;

  /// The bubbles up now: id, word, centre in the play area.
  @visibleForTesting
  List<(int, String, Offset)> get debugBubbles => [for (final b in _bubbles) (b.id, b.word, Offset(b.x, b.y))];

  @visibleForTesting
  int get debugPopped => _popped;

  /// The sky's size and a bubble's radius.
  @visibleForTesting
  (Size, double) get debugSky => (_size, _radius);

  @visibleForTesting
  bool get debugHint => _glow;

  @override
  void initState() {
    super.initState();
    _newRound();
    _ticker.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ambient motion at 30 fps on the slowest displays (SPEC §12.3).
    _slow = DTheme.of(context).policy.ambientFps < 60;
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _idle?.cancel();
    _ticker.dispose();
    _repaint.dispose();
    _moved.dispose();
    for (final (p, _) in _words.values) {
      p.dispose();
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
    _round = wordPopRound(widget.c.level, _rng, last: _round?.word);
    _popped = _slips = 0;
    _done = _glow = false;
    // A fresh sky of the new words.
    _bubbles.clear();
    _spawnIn = 0;
    _after(const Duration(milliseconds: 600), _sayAsk);
    _waitIdle();
    if (mounted) setState(() {});
  }

  void _sayAsk() => widget.c.say(sightAskClip(_round!.word));

  /// A long pause asks again and rings the bubbles she's after (not a slip).
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 10), () {
      if (!mounted || _done) return;
      _sayAsk();
      setState(() => _glow = true);
    });
  }

  void _spawn({bool anywhere = false}) {
    final r = _round!;
    if (_size.isEmpty) return;
    final word = wordPopNext(r, _bubbles.where((b) => b.word == r.word).length, _rng);
    var x = _radius + _rng.nextDouble() * (_size.width - 2 * _radius);
    var y = anywhere ? _size.height * (0.35 + _rng.nextDouble() * 0.6) : _size.height + _radius;
    // Room to breathe: a few tries for a spot clear of the others.
    for (var i = 0; i < 12 && _bubbles.any((b) => (Offset(b.x, b.y) - Offset(x, y)).distance < _radius * 2.1); i++) {
      x = _radius + _rng.nextDouble() * (_size.width - 2 * _radius);
      if (anywhere) y = _size.height * (0.35 + _rng.nextDouble() * 0.6);
    }
    final speed = _size.height * r.speed * (0.85 + _rng.nextDouble() * 0.3);
    _bubbles.add(_Bubble(_next++, word, x, y, _rng.nextInt(kBubbleColors.length), _rng.nextDouble() * math.pi * 2, speed));
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    if (_slow && (_frames++).isOdd) return;
    final r = _round;
    if (r == null || _size.isEmpty) return;
    _clock += dt;
    if (_bubbles.isEmpty) {
      for (var i = 0; i < r.bubbles; i++) {
        _spawn(anywhere: true);
      }
    }
    _spawnIn -= dt;
    if (_bubbles.length < r.bubbles && _spawnIn <= 0) {
      _spawn();
      _spawnIn = 1 / r.speed / r.bubbles;
    }
    for (final b in _bubbles) {
      b.y -= b.speed * dt;
      b.x = (b.x + math.sin(_clock * 1.1 + b.phase) * _radius * 0.25 * dt).clamp(_radius, _size.width - _radius);
      if (b.wobble > 0) b.wobble = math.max(0, b.wobble - dt);
    }
    // Bubbles nudge each other apart: two words on top of each other can't
    // be read.
    for (var i = 0; i < _bubbles.length; i++) {
      for (var j = i + 1; j < _bubbles.length; j++) {
        final a = _bubbles[i], b = _bubbles[j];
        final d = Offset(b.x - a.x, b.y - a.y);
        final gap = _radius * 2.1 - d.distance;
        if (gap <= 0) continue;
        final dir = d.distance < 1 ? const Offset(1, 0) : d / d.distance;
        final push = dir * math.min(gap, _radius * 3 * dt) / 2;
        a
          ..x = (a.x - push.dx).clamp(_radius, _size.width - _radius)
          ..y -= push.dy;
        b
          ..x = (b.x + push.dx).clamp(_radius, _size.width - _radius)
          ..y += push.dy;
      }
    }
    _bubbles.removeWhere((b) => b.y <= _radius * 0.08);
    for (final s in _sparks) {
      s
        ..x += s.vx * dt
        ..y += s.vy * dt
        ..vy += 380 * dt
        ..life -= dt;
    }
    _sparks.removeWhere((s) => s.life <= 0);
    _repaint.value++;
    if (_frames.isEven || !_slow) _moved.value++;
  }

  void _burst(double x, double y, Color color, {int count = 14, double speed = 240}) {
    final n = math.min(count, DTheme.of(context).policy.maxParticles);
    for (var i = 0; i < n; i++) {
      final a = _rng.nextDouble() * math.pi * 2, v = speed * (0.4 + _rng.nextDouble() * 0.8);
      _sparks.add(_Spark(x, y, math.cos(a) * v, math.sin(a) * v - 100, color, 4 + _rng.nextDouble() * 5));
    }
  }

  void _tapDown(TapDownDetails d) {
    final p = d.localPosition;
    for (final b in _bubbles.reversed) {
      if ((Offset(b.x, b.y) - p).distance <= _radius * 1.15) {
        _tapBubble(b);
        return;
      }
    }
    _burst(p.dx, p.dy, Colors.white, count: 5, speed: 120);
  }

  void _tapBubble(_Bubble b) {
    final c = widget.c;
    final r = _round!;
    if (_done) {
      // Between rounds a bubble just pops.
      _bubbles.remove(b);
      _burst(b.x, b.y, kBubbleColors[b.color].$2);
      c.sound(Sfx.pop, volume: 0.6);
      return;
    }
    if (b.word != r.word) {
      // Another word bounces up and reads itself.
      b
        ..wobble = 0.5
        ..speed *= 1.4;
      _slips++;
      c.cue();
      c.say(sightWordClip(b.word));
      if (_slips >= 2 && !_glow) setState(() => _glow = true);
      return;
    }
    _bubbles.remove(b);
    _burst(b.x, b.y, kBubbleColors[b.color].$2);
    c.sound(Sfx.pop, volume: 0.7);
    c.say(sightWordClip(b.word));
    _waitIdle();
    setState(() => _popped++);
    if (_popped < kWordPops) return;
    _idle?.cancel();
    setState(() => _done = true);
    unawaited(c.finishRound(wordPopResult(_slips), emoji: '🎈'));
    _after(afterVoice(sightWordClip(b.word), atLeast: const Duration(milliseconds: 3000)), _newRound);
  }

  /// [word] in the Toybox's print, [height] tall, recorded once and drawn
  /// on every bubble that carries it.
  (ui.Picture, Size) _wordPicture(String word, double height) {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    const weight = 1.3, band = 14.0;
    final unit = height / (band + weight);
    final pad = height * 0.03;
    var x = 0.0;
    for (final ch in word.split('')) {
      if (ch == ' ') {
        x += height * 0.3;
        continue;
      }
      final g = glyphFor(ch);
      final w = (g.width + weight) * unit;
      canvas
        ..save()
        ..translate(x + pad, 0);
      GlyphPainter(g, color: const Color(0xFF2B2440), frameTop: 0, frameBottom: band).paint(canvas, Size(w, height));
      canvas.restore();
      x += w + pad * 2;
    }
    return (rec.endRecording(), Size(x, height));
  }

  (ui.Picture, Size) _picture(String word) {
    final h = _radius * 0.46;
    if (_wordsFor != h) {
      for (final (p, _) in _words.values) {
        p.dispose();
      }
      _words.clear();
      _wordsFor = h;
    }
    return _words[word] ??= _wordPicture(word, h);
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF9AD8FF), Color(0xFFEFF9FF)])),
        ),
        // The sky starts under the pill: bubbles shrink away before they reach it.
        Padding(
          padding: EdgeInsets.only(top: 100 * t.scale),
          child: LayoutBuilder(builder: (context, box) {
          final size = box.biggest;
          if (size != _size) {
            _size = size;
            _radius = (size.shortestSide * 0.15).clamp(48.0, 170.0);
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: _tapDown,
                excludeFromSemantics: true,
                child: RepaintBoundary(child: CustomPaint(painter: _WordBubblePainter(this, _repaint), size: Size.infinite)),
              ),
              // Where each bubble is, for tests and screen readers. Empty
              // boxes take no touches: the painter's detector does that.
              ValueListenableBuilder<int>(
                valueListenable: _moved,
                builder: (context, _, _) => Stack(
                  children: [
                    for (final b in _bubbles)
                      Positioned(
                        left: b.x - _radius,
                        top: b.y - _radius,
                        width: _radius * 2,
                        height: _radius * 2,
                        child: tid('wordpop.bubble.${b.id}', Semantics(label: b.word, excludeSemantics: true, child: const SizedBox.expand())),
                      ),
                  ],
                ),
              ),
            ],
          );
        }),
        ),
        TopPrompt(
          child: PromptPill(
            id: 'wordpop.ask',
            label: _done ? 'Popped ${r.word}: $kWordPops of $kWordPops' : 'Pop the word ${r.word}: $_popped of $kWordPops',
            onSayAgain: _sayAsk,
            children: [
              for (var i = 0; i < kWordPops; i++)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: t.space.xs),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 40 * t.scale,
                    height: 40 * t.scale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _popped ? kBubbleColors[i % kBubbleColors.length].$2 : Colors.white,
                      border: Border.all(color: const Color(0xFFB9D9F2), width: 3),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WordBubblePainter extends CustomPainter {
  _WordBubblePainter(this.s, Listenable repaint) : super(repaint: repaint);
  final WordPopGameState s;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint();
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white.withValues(alpha: 0.9);
    final gold = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s._radius * 0.1
      ..color = const Color(0xFFFFC93C);
    final shine = Paint()..color = Colors.white.withValues(alpha: 0.85);
    final label = Paint()..color = Colors.white.withValues(alpha: 0.82);
    final want = s._round?.word;
    for (final b in s._bubbles) {
      final grow = b.wobble > 0 ? 1 + 0.16 * math.sin(b.wobble / 0.5 * math.pi * 3) * (b.wobble / 0.5) : 1.0;
      // Near the top it shrinks away to nothing (no fading: that would need
      // a layer a bubble, too slow on the frame).
      final away = (b.y / (s._radius * 1.6)).clamp(0.0, 1.0);
      if (away <= 0.05) continue;
      final r = s._radius * grow * away, c = Offset(b.x, b.y), color = kBubbleColors[b.color].$2;
      fill.shader = RadialGradient(
        center: const Alignment(-0.35, -0.35),
        colors: [Colors.white.withValues(alpha: 0.75), color.withValues(alpha: 0.5), color.withValues(alpha: 0.8)],
        stops: const [0, 0.55, 1],
      ).createShader(Rect.fromCircle(center: c, radius: r));
      canvas
        ..drawCircle(c, r, fill)
        ..drawCircle(c, r, rim);
      if (s._glow && b.word == want && !s._done) canvas.drawCircle(c, r * 1.06, gold);
      // The word on a pale band so it reads on any color.
      final (pic, wordSize) = s._picture(b.word);
      final band = RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: (wordSize.width + s._radius * 0.24) * away, height: wordSize.height * 1.35 * away), Radius.circular(wordSize.height * 0.4 * away));
      canvas
        ..drawRRect(band, label)
        ..drawOval(Rect.fromCenter(center: c + Offset(-r * 0.4, -r * 0.5), width: r * 0.36, height: r * 0.2), shine)
        ..save()
        ..translate(c.dx, c.dy)
        ..scale(away)
        ..translate(-wordSize.width / 2, -wordSize.height / 2)
        ..drawPicture(pic)
        ..restore();
    }
    final spark = Paint();
    for (final p in s._sparks) {
      spark.color = p.color.withValues(alpha: (p.life / 0.7).clamp(0, 1));
      canvas.drawCircle(Offset(p.x, p.y), p.size, spark);
    }
  }

  @override
  bool shouldRepaint(_WordBubblePainter old) => false;
}

/// The launcher tile's picture: a bubble that says "go".
class WordPopIcon extends StatelessWidget {
  const WordPopIcon({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(center: const Alignment(-0.35, -0.35), colors: [Colors.white, kBubbleColors[0].$2.withValues(alpha: 0.7)]),
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: Center(child: PrintedWord('go', height: size * 0.34)),
        ),
      );
}
