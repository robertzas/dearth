import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Alphabet Train (SPEC FR-TOY-03, Appendix B: alphabet order). A train
/// pulls in with a letter block in each carriage, in ABC order, and an
/// empty carriage. As it stops the voice reads the letters, one carriage
/// at a time, then asks "What comes next?" (or "Which letter is
/// missing?"). Blocks wait on the platform; she taps the one that belongs
/// and it hops into the glowing carriage. Once the train is whole, the
/// voice reads it front to back as each carriage bounces, says "All
/// aboard! Choo choo!", and the train chugs away. A wrong block wiggles and
/// says its letter; after two, or a long pause, the right block glows.
class TrainGame extends StatefulWidget {
  const TrainGame(this.c, {super.key});
  final GameController c;

  @override
  State<TrainGame> createState() => TrainGameState();
}

const List<Color> _kCarPaints = [Color(0xFF3E8EF7), Color(0xFF30A46C), Color(0xFFF2A516), Color(0xFF8E4EC6), Color(0xFFF76B15)];

@visibleForTesting
class TrainGameState extends State<TrainGame> {
  TrainRound? _round;

  /// The gaps filled so far.
  final _filled = <int>{};
  final _used = <int>{};
  final _hops = <int, int>{};
  final _wiggles = <int, int>{};
  int _deal = 0, _slips = 0, _slipsHere = 0;
  bool _arrived = false, _asked = false, _done = false, _leaving = false, _glow = false;
  final _timers = <Timer>[];
  Timer? _idle;

  @visibleForTesting
  TrainRound get debugRound => _round!;

  @visibleForTesting
  bool get debugAsked => _asked;

  @visibleForTesting
  bool get debugHint => _glow;

  @visibleForTesting
  bool get debugDone => _done;

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
    super.dispose();
  }

  void _after(Duration d, VoidCallback f) => _timers.add(Timer(d, () {
        if (mounted) f();
      }));

  String _shown(String letter) => _round!.small ? letter.toLowerCase() : letter;

  int? get _gap {
    final open = [for (final g in _round!.gaps) if (!_filled.contains(g)) g];
    return open.isEmpty ? null : open.first;
  }

  void _newRound() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _idle?.cancel();
    final r = _round = trainRound(widget.c.level, widget.c.random, last: _round);
    _filled.clear();
    _used.clear();
    _hops.clear();
    _wiggles.clear();
    _slips = _slipsHere = 0;
    _arrived = _asked = _done = _leaving = _glow = false;
    _deal++;
    _after(const Duration(milliseconds: 100), () {
      setState(() => _arrived = true);
      widget.c.sound(Sfx.honk, volume: 0.3, rate: 0.8);
    });
    // The letters read out as the carriages stand, one each, then the question.
    const lead = Duration(milliseconds: 1500);
    var at = lead;
    for (var i = 0; i < r.letters.length; i++) {
      if (r.gaps.contains(i)) continue;
      final k = i;
      _after(at, () {
        widget.c.say(letterNameClip(r.letters[k]));
        setState(() => _hops[k] = (_hops[k] ?? 0) + 1);
      });
      at += const Duration(milliseconds: 750);
    }
    _after(at + const Duration(milliseconds: 200), _ask);
    if (mounted) setState(() {});
  }

  void _ask() {
    setState(() => _asked = true);
    _sayAsk();
    _waitIdle();
  }

  void _sayAsk() => widget.c.say(_round!.ask == TrainAsk.next ? VoiceLine.trainNext : VoiceLine.trainMissing);

  /// A long pause asks again and lights the right block (not a slip).
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 11), () {
      if (!mounted || _done) return;
      _sayAsk();
      setState(() => _glow = true);
    });
  }

  void _tapBlock(int i) {
    final r = _round!;
    final letter = r.choices[i];
    if (_used.contains(i) || _done) return;
    if (!_asked) {
      // Before the question a block just says its letter.
      widget.c.say(letterNameClip(letter));
      return;
    }
    _waitIdle();
    final gap = _gap!;
    if (letter != r.letters[gap]) {
      _slips++;
      _slipsHere++;
      widget.c.cue();
      widget.c.say(letterNameClip(letter));
      setState(() {
        _wiggles[i] = (_wiggles[i] ?? 0) + 1;
        if (_slipsHere >= 2) _glow = true;
      });
      return;
    }
    widget.c.sound(Sfx.snap, volume: 0.5);
    widget.c.say(letterNameClip(letter));
    setState(() {
      _used.add(i);
      _filled.add(gap);
      _hops[gap] = (_hops[gap] ?? 0) + 1;
      _slipsHere = 0;
      _glow = false;
    });
    if (_gap != null) return;
    _idle?.cancel();
    setState(() => _done = true);
    unawaited(widget.c.finishRound(trainResult(r, _slips), emoji: '🚂'));
    // The whole train, front to back, a carriage at a time.
    var at = afterVoice(letterNameClip(letter), atLeast: const Duration(milliseconds: 900));
    for (var k = 0; k < r.letters.length; k++) {
      _after(at, () {
        widget.c.say(letterNameClip(r.letters[k]));
        setState(() => _hops[k] = (_hops[k] ?? 0) + 1);
      });
      at += const Duration(milliseconds: 700);
    }
    _after(at + const Duration(milliseconds: 200), () {
      widget.c.say(VoiceLine.trainGo);
      widget.c.sound(Sfx.honk, volume: 0.4, rate: 0.8);
    });
    _after(at + afterVoice(VoiceLine.trainGo, atLeast: const Duration(milliseconds: 1500)), () => setState(() => _leaving = true));
    _after(at + afterVoice(VoiceLine.trainGo, atLeast: const Duration(milliseconds: 1500)) + const Duration(milliseconds: 1300), _newRound);
  }

  String _askLabel() {
    final r = _round!;
    final line = [for (var i = 0; i < r.letters.length; i++) r.gaps.contains(i) && !_filled.contains(i) ? '_' : _shown(r.letters[i])].join(', ');
    if (_done) return line;
    if (!_asked) return 'Here comes the train';
    return '${r.ask == TrainAsk.next ? 'What comes next?' : 'Which letter is missing?'} $line';
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    return Backdrop(
      top: const Color(0xFFDFF3FF),
      bottom: const Color(0xFFEAF6DA),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final l = _Layout.of(box.biggest, r.letters.length, r.choices.length);
              final trainX = _leaving ? -l.trainWidth - 60 : (_arrived ? l.trainLeft : box.maxWidth + 40);
              return Stack(
                key: ValueKey(_deal),
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _TrackPainter(l.railY, l.unit)))),
                  AnimatedPositioned(
                    duration: Duration(milliseconds: _leaving ? 1200 : 1300),
                    curve: _leaving ? Curves.easeInCubic : Curves.easeOutCubic,
                    left: trainX,
                    top: l.railY - l.unit * 1.15,
                    width: l.trainWidth,
                    height: l.unit * 1.15,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        SizedBox(width: l.unit * 1.3, height: l.unit * 1.15, child: const RepaintBoundary(child: CustomPaint(painter: _EnginePainter()))),
                        for (var i = 0; i < r.letters.length; i++) _car(i, l),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: l.blocksTop,
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < r.choices.length; i++)
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: l.block * 0.1),
                              child: PictureTile(
                                id: 'train.block.$i',
                                label: _used.contains(i) ? 'Used' : _shown(r.choices[i]),
                                size: l.block,
                                onTap: () => _tapBlock(i),
                                tried: _used.contains(i),
                                hint: _glow && !_done && _gap != null && r.choices[i] == r.letters[_gap!],
                                wiggles: _wiggles[i] ?? 0,
                                child: _used.contains(i)
                                    ? const SizedBox.shrink()
                                    : GlyphView(_shown(r.choices[i]), height: l.block * 0.62, color: letterColor(r.choices[i]), frameTop: 0, frameBottom: 14),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
          TopPrompt(child: PromptPill(id: 'train.ask', label: _askLabel(), onSayAgain: _asked ? _sayAsk : null, children: [DEmoji('🚂', size: 40 * t.scale)])),
        ],
      ),
    );
  }

  Widget _car(int i, _Layout l) {
    final r = _round!;
    final empty = r.gaps.contains(i) && !_filled.contains(i);
    final letter = r.letters[i];
    return Padding(
      padding: EdgeInsets.only(left: l.unit * 0.08),
      child: tid(
        'train.car.$i',
        Semantics(
          label: empty ? 'Empty' : _shown(letter),
          excludeSemantics: true,
          child: SizedBox(
            width: l.unit * 0.92,
            height: l.unit * 1.15,
            child: Stack(
              children: [
                Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _CarPainter(_kCarPaints[i % _kCarPaints.length])))),
                Positioned(
                  left: l.unit * 0.1,
                  right: l.unit * 0.1,
                  top: 0,
                  height: l.unit * 0.72,
                  child: Hop(
                    count: _hops[i] ?? 0,
                    child: empty
                        ? _EmptySlot(glow: _asked && i == _gap, size: l.unit)
                        : DecoratedBox(
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(l.unit * 0.12), border: Border.all(color: const Color(0xFFE3DCF5), width: 3)),
                            child: Center(child: GlyphView(_shown(letter), height: l.unit * 0.5, color: letterColor(letter), frameTop: 0, frameBottom: 14)),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The empty carriage's place: a dashed-looking pale box, golden while it's
/// the one to fill.
class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.glow, required this.size});
  final bool glow;
  final double size;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: glow ? const Color(0xFFFFF4C2) : Colors.white.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: glow ? const Color(0xFFFFC93C) : const Color(0xFFBDB3D9), width: glow ? 5 : 3),
        ),
        child: Center(child: Text('?', style: DTheme.of(context).text.kidTitle.copyWith(fontSize: size * 0.4, height: 1, color: const Color(0xFF9C8FC4)))),
      );
}

/// The train row's unit (a carriage's width), where the rails run, and
/// the platform of blocks under them.
class _Layout {
  _Layout(this.unit, this.trainLeft, this.railY, this.blocksTop, this.block, this.n);

  factory _Layout.of(Size a, int n, int blocks) {
    final gap = math.max(12.0, a.shortestSide * 0.03);
    // The engine is 1.3 units, each carriage 1 (with its coupling).
    final unit = math.min(a.width / (n + 1.45), a.height * (a.width > a.height ? 0.36 : 0.26));
    final width = unit * (1.3 + n);
    final wide = a.width > a.height;
    final railY = a.height * (wide ? 0.5 : 0.36);
    final room = a.height - railY - gap * 2;
    // On a tall screen the blocks can be bigger than the carriages: there's room.
    final block = math.min(math.min(room, wide ? unit * 1.05 : unit * 1.6), a.width / (blocks * 1.25));
    return _Layout(unit, (a.width - width) / 2, railY, railY + gap + (room - block) / 2, block, n);
  }

  final double unit, trainLeft, railY, blocksTop, block;
  final int n;

  double get trainWidth => unit * (1.3 + n);
}

class _TrackPainter extends CustomPainter {
  const _TrackPainter(this.y, this.unit);
  final double y, unit;

  @override
  void paint(Canvas canvas, Size size) {
    final tie = Paint()..color = const Color(0xFFA27B5C);
    for (var x = 0.0; x < size.width; x += unit * 0.35) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y - unit * 0.02, unit * 0.14, unit * 0.1), Radius.circular(unit * 0.02)), tie);
    }
    canvas.drawRect(Rect.fromLTWH(0, y, size.width, unit * 0.035), Paint()..color = const Color(0xFF6E6A86));
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.y != y || old.unit != unit;
}

/// A carriage: a painted wagon on two wheels with a coupling; the letter
/// block sits on it.
class _CarPainter extends CustomPainter {
  const _CarPainter(this.color);
  final Color color;

  static const _ink = Color(0xFF2B2440);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final dark = Color.lerp(color, _ink, 0.4)!;
    final body = RRect.fromRectAndRadius(Rect.fromLTRB(0, h * 0.58, w, h * 0.86), Radius.circular(w * 0.08));
    canvas
      // The coupling to the one in front.
      ..drawRect(Rect.fromLTWH(-w * 0.1, h * 0.76, w * 0.12, h * 0.04), Paint()..color = dark)
      ..drawRRect(body, Paint()..color = color)
      ..drawRRect(
        body,
        Paint()
          ..color = dark
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, w * 0.03),
      );
    for (final x in [0.26, 0.74]) {
      canvas
        ..drawCircle(Offset(w * x, h * 0.9), w * 0.11, Paint()..color = _ink)
        ..drawCircle(Offset(w * x, h * 0.9), w * 0.04, Paint()..color = const Color(0xFFB8B3C7));
    }
  }

  @override
  bool shouldRepaint(_CarPainter old) => old.color != color;
}

/// The engine: boiler, cab, chimney with a puff of smoke, cowcatcher and
/// wheels, facing left (the way it leaves).
class _EnginePainter extends CustomPainter {
  const _EnginePainter();

  static const _ink = Color(0xFF2B2440);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final red = Paint()..color = const Color(0xFFE5484D);
    final dark = Paint()..color = const Color(0xFF9C2F3A);
    final ink = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, w * 0.02)
      ..strokeJoin = StrokeJoin.round;
    final boiler = RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.08, h * 0.52, w * 0.66, h * 0.86), Radius.circular(h * 0.1));
    final cab = RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.6, h * 0.3, w * 0.98, h * 0.86), Radius.circular(h * 0.05));
    final roof = RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.56, h * 0.26, w * 1.0, h * 0.33), Radius.circular(h * 0.03));
    final chimney = Path()
      ..moveTo(w * 0.18, h * 0.52)
      ..lineTo(w * 0.15, h * 0.3)
      ..lineTo(w * 0.33, h * 0.3)
      ..lineTo(w * 0.3, h * 0.52)
      ..close();
    final catcher = Path()
      ..moveTo(w * 0.08, h * 0.7)
      ..lineTo(0, h * 0.9)
      ..lineTo(w * 0.12, h * 0.9)
      ..close();
    // Smoke.
    final puff = Paint()..color = Colors.white.withValues(alpha: 0.9);
    for (final (x, y, r) in const [(0.24, 0.2, 0.07), (0.3, 0.1, 0.09), (0.4, 0.03, 0.06)]) {
      canvas.drawCircle(Offset(w * x, h * y), w * r, puff);
    }
    canvas
      ..drawPath(catcher, Paint()..color = const Color(0xFF6E6A86))
      ..drawPath(chimney, dark)
      ..drawPath(chimney, ink)
      ..drawRRect(boiler, red)
      ..drawRRect(boiler, ink)
      ..drawRRect(cab, red)
      ..drawRRect(cab, ink)
      ..drawRRect(roof, dark)
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.7, h * 0.4, w * 0.9, h * 0.58), Radius.circular(h * 0.03)), Paint()..color = const Color(0xFFCFEFFF))
      ..drawCircle(Offset(w * 0.1, h * 0.66), h * 0.05, Paint()..color = const Color(0xFFFFE066));
    for (final (x, r) in const [(0.24, 0.1), (0.48, 0.1), (0.8, 0.13)]) {
      canvas
        ..drawCircle(Offset(w * x, h * 0.88), h * r, Paint()..color = _ink)
        ..drawCircle(Offset(w * x, h * 0.88), h * r * 0.4, Paint()..color = const Color(0xFFB8B3C7));
    }
  }

  @override
  bool shouldRepaint(_EnginePainter old) => false;
}
