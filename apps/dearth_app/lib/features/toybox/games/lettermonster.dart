import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'monster.dart';
import 'voice_widgets.dart';

/// Letter Monster (SPEC FR-TOY-03, Appendix B: letter names and sounds).
/// Feed the Monster's orange cousin eats only letter biscuits and says which
/// one it wants: "I want the letter B!", later "I want the letter that says
/// buh!", then a picture ("Bee. Which letter does bee start with?"). She
/// taps a biscuit or drags it to the mouth. The right one is munched and the
/// voice says "B. Buh, buh, ball."; another is politely refused (a head
/// shake, its own name said, back to its plate). After two of those, or a
/// long pause, the right biscuit's plate glows.
class LetterMonsterGame extends StatefulWidget {
  const LetterMonsterGame(this.c, {super.key});
  final GameController c;

  @override
  State<LetterMonsterGame> createState() => LetterMonsterGameState();
}

@visibleForTesting
class LetterMonsterGameState extends State<LetterMonsterGame> with TickerProviderStateMixin {
  final _area = GlobalKey();
  LetterMonsterRound? _round;
  final _wiggles = <int, int>{};
  int? _flying, _dragging;
  Offset _dragAt = Offset.zero, _grip = Offset.zero;
  int _slips = 0, _deal = 0;
  bool _eaten = false, _glow = false;
  _Layout? _layout;
  final _timers = <Timer>[];
  Timer? _idle;

  late final AnimationController _chew = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 90));
  late final AnimationController _open = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  late final AnimationController _hop = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  final _look = ValueNotifier<Offset>(Offset.zero);
  Timer? _blinker;

  @visibleForTesting
  LetterMonsterRound get debugRound => _round!;

  /// Whether the biscuit it wants glows (two slips, or a long pause).
  @visibleForTesting
  bool get debugHint => _glow;

  @visibleForTesting
  bool get debugEaten => _eaten;

  @override
  void initState() {
    super.initState();
    _newRound();
    _blinker = Timer.periodic(const Duration(milliseconds: 3900), (_) => _blink.forward(from: 0).then((_) => _blink.reverse()));
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
    _round = letterMonsterRound(widget.c.level, widget.c.random, last: _round);
    _wiggles.clear();
    _slips = 0;
    _deal++;
    _flying = _dragging = null;
    _eaten = _glow = false;
    _look.value = Offset.zero;
    _after(const Duration(milliseconds: 600), _sayAsk);
    _waitIdle();
    if (mounted) setState(() {});
  }

  void _sayAsk() => widget.c.say(letterMonsterAskClip(_round!));

  /// A long pause asks again and lights the answer's plate (not a slip).
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 12), () {
      if (!mounted || _eaten) return;
      _sayAsk();
      setState(() => _glow = true);
    });
  }

  bool _wants(int i) => _round!.choices[i] == _round!.letter;

  void _lookAt(Offset p) {
    final l = _layout;
    if (l == null) return;
    final d = p - l.eyes;
    _look.value = d.distance < 1 ? Offset.zero : d / math.max(d.distance, l.monster.width * 0.6);
  }

  void _feed(int i) {
    if (_flying != null || _dragging != null || _eaten) return;
    final l = _layout;
    if (l != null) _lookAt(l.plates[i]);
    setState(() => _flying = i);
    unawaited(_open.forward());
    _after(const Duration(milliseconds: 420), () => _taste(i));
  }

  /// [i] is at the mouth: munched, or politely refused.
  void _taste(int i) {
    final c = widget.c;
    final r = _round!;
    unawaited(_open.reverse());
    _look.value = Offset.zero;
    _waitIdle();
    if (_wants(i)) {
      _idle?.cancel();
      c.sound(Sfx.munch, volume: 0.6);
      unawaited(_chew.forward(from: 0));
      setState(() {
        _eaten = true;
        _flying = null;
      });
      final yes = letterClip(r.letter);
      _after(const Duration(milliseconds: 500), () {
        c.say(yes);
        unawaited(_hop.forward(from: 0));
        unawaited(c.finishRound(letterMonsterResult(_slips), emoji: '😋'));
      });
      _after(const Duration(milliseconds: 500) + afterVoice(yes, atLeast: const Duration(milliseconds: 2600)), _newRound);
      return;
    }
    _slips++;
    c.cue();
    c.say(letterNameClip(r.choices[i]));
    unawaited(_shake.forward(from: 0));
    setState(() {
      _flying = null;
      _wiggles[i] = (_wiggles[i] ?? 0) + 1;
      if (_slips >= 2) _glow = true;
    });
  }

  Offset _local(Offset global) => (_area.currentContext!.findRenderObject()! as RenderBox).globalToLocal(global);

  void _dragStart(int i, DragStartDetails d) {
    final l = _layout;
    if (l == null || _flying != null || _eaten) return;
    final p = _local(d.globalPosition);
    setState(() {
      _dragging = i;
      _grip = l.plates[i] - p;
      _dragAt = l.plates[i];
    });
  }

  void _dragUpdate(DragUpdateDetails d) {
    final l = _layout;
    if (_dragging == null || l == null) return;
    setState(() => _dragAt = _local(d.globalPosition) + _grip);
    _lookAt(_dragAt);
    // It opens wide as the biscuit comes near.
    final near = (_dragAt - l.mouth).distance < l.food * 1.8;
    if (near != (_open.status == AnimationStatus.forward || _open.status == AnimationStatus.completed)) {
      unawaited(near ? _open.forward() : _open.reverse());
    }
  }

  void _dragEnd() {
    final i = _dragging, l = _layout;
    if (i == null || l == null) return;
    _dragging = null;
    if ((_dragAt - l.mouth).distance < l.food * 1.2) {
      _taste(i);
    } else {
      unawaited(_open.reverse());
      _look.value = Offset.zero;
      setState(() {});
    }
  }

  String _askLabel() {
    final r = _round!;
    if (_eaten) return 'Yum! ${r.letter}';
    return switch (r.ask) {
      LetterMonsterAsk.name || LetterMonsterAsk.small => 'I want the letter ${r.letter}',
      LetterMonsterAsk.sound => 'I want the letter that says ${r.letter.toLowerCase()}',
      LetterMonsterAsk.picture => 'Starts like ${r.word!.word}: ${r.letter}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    return Backdrop(
      top: const Color(0xFFFFF4E0),
      bottom: const Color(0xFFE6F6FF),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(
              key: _area,
              builder: (context, box) {
                final l = _layout = _Layout.of(box.biggest, r.choices.length);
                return Stack(
                  key: ValueKey(_deal),
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fromRect(
                      rect: l.monster,
                      child: RepaintBoundary(
                        child: CustomPaint(painter: MonsterPainter(chew: _chew, shake: _shake, blink: _blink, open: _open, hop: _hop, look: _look, skin: MonsterSkin.orange)),
                      ),
                    ),
                    Positioned.fromRect(
                      rect: Rect.fromCircle(center: l.mouth, radius: l.food * 0.8),
                      child: tid('lettermonster.mouth', Semantics(label: 'The monster’s mouth', excludeSemantics: true, child: const SizedBox.expand())),
                    ),
                    // The picture it's thinking of: the whole clue at the top level, so big.
                    if (r.word != null)
                      Positioned.fromRect(
                        rect: Rect.fromCircle(center: l.monster.topRight + Offset(-l.monster.width * 0.08, l.monster.height * 0.1), radius: l.monster.width * 0.2),
                        child: DPressable(
                          id: 'lettermonster.picture',
                          semanticLabel: r.word!.word,
                          excludeSemantics: true,
                          onTap: _sayAsk,
                          borderRadius: BorderRadius.circular(l.monster.width),
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFFFD9A8), width: 4), boxShadow: t.elevation.e1),
                            child: Center(child: DEmoji(r.word!.emoji, size: l.monster.width * 0.24)),
                          ),
                        ),
                      ),
                    for (var i = 0; i < r.choices.length; i++) ...[
                      Positioned(
                        left: l.plates[i].dx - l.food * 0.7,
                        top: l.plates[i].dy - l.food * 0.7,
                        child: IgnorePointer(child: _Plate(size: l.food * 1.4, glow: _glow && _wants(i) && !_eaten)),
                      ),
                      _biscuitAt(i, l),
                    ],
                  ],
                );
              },
            ),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'lettermonster.ask',
              label: _askLabel(),
              onSayAgain: _sayAsk,
              children: [
                DEmoji('😋', size: 44 * t.scale),
                if (_eaten) ...[SizedBox(width: t.space.sm), GlyphView(r.small ? r.letter.toLowerCase() : r.letter, height: 48 * t.scale, color: letterColor(r.letter), frameTop: 0, frameBottom: 14)],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _biscuitAt(int i, _Layout l) {
    final r = _round!;
    final letter = r.choices[i];
    final eaten = _eaten && _wants(i);
    final dragging = _dragging == i;
    final at = eaten || _flying == i ? l.mouth : (dragging ? _dragAt : l.plates[i]);
    final shown = r.small ? letter.toLowerCase() : letter;
    return AnimatedPositioned(
      duration: dragging ? Duration.zero : const Duration(milliseconds: 400),
      curve: _flying == i ? Curves.easeInCubic : Curves.easeOutBack,
      left: at.dx - l.food / 2,
      top: at.dy - l.food / 2,
      child: tid(
        'lettermonster.food.$i',
        Semantics(
          button: true,
          label: eaten ? 'Eaten' : 'Letter $shown',
          onTap: () => _feed(i),
          excludeSemantics: true,
          child: GestureDetector(
            excludeFromSemantics: true,
            dragStartBehavior: DragStartBehavior.down,
            onTap: () => _feed(i),
            onPanStart: (d) => _dragStart(i, d),
            onPanUpdate: _dragUpdate,
            onPanEnd: (_) => _dragEnd(),
            onPanCancel: _dragEnd,
            child: AnimatedScale(
              scale: eaten ? 0 : (dragging ? 1.15 : 1),
              duration: Duration(milliseconds: eaten ? 260 : 160),
              child: Wiggle(count: _wiggles[i] ?? 0, child: LetterBiscuit(shown, size: l.food)),
            ),
          ),
        ),
      ),
    );
  }
}

/// A round golden biscuit with its letter piped on in chocolate, in the
/// Toybox's ball-and-stick print.
class LetterBiscuit extends StatelessWidget {
  const LetterBiscuit(this.letter, {super.key, required this.size});
  final String letter;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _BiscuitPainter()))),
            GlyphView(letter, height: size * 0.62, color: const Color(0xFF5B3418), weight: 1.6, frameTop: 0, frameBottom: 14),
          ],
        ),
      );
}

class _BiscuitPainter extends CustomPainter {
  const _BiscuitPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    // A scalloped edge: a ring of bumps around the disc.
    final edge = Paint()..color = const Color(0xFFD9963F);
    for (var k = 0; k < 14; k++) {
      final a = k * 2 * math.pi / 14;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r * 0.82, r * 0.17, edge);
    }
    canvas
      ..drawCircle(c, r * 0.84, edge)
      ..drawCircle(c, r * 0.74, Paint()..color = const Color(0xFFF4CF87));
    // Docking holes, like a real biscuit.
    final dot = Paint()..color = const Color(0xFFE1AE5E);
    for (var k = 0; k < 8; k++) {
      final a = k * 2 * math.pi / 8 + 0.3;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r * 0.62, r * 0.035, dot);
    }
  }

  @override
  bool shouldRepaint(_BiscuitPainter old) => false;
}

/// Where the monster stands and the plates sit, as in Feed the Monster.
class _Layout {
  _Layout(this.monster, this.plates, this.food);

  factory _Layout.of(Size area, int n) {
    final wide = area.width > area.height * 1.1;
    final Rect monster, tray;
    if (wide) {
      monster = Rect.fromLTWH(area.width * 0.02, area.height * 0.04, area.width * 0.4, area.height * 0.92);
      tray = Rect.fromLTWH(area.width * 0.46, area.height * 0.08, area.width * 0.54, area.height * 0.84);
    } else {
      monster = Rect.fromLTWH(area.width * 0.12, 0, area.width * 0.76, area.height * 0.5);
      tray = Rect.fromLTWH(0, area.height * 0.56, area.width, area.height * 0.44);
    }
    final rows = n <= 3 ? 1 : 2;
    final cols = (n / rows).ceil();
    final food = math.min(tray.width / cols, tray.height / rows) * 0.62;
    final plates = <Offset>[];
    for (var i = 0; i < n; i++) {
      final row = i ~/ cols;
      // A short last row is centred under the full one.
      final inRow = row == rows - 1 ? n - row * cols : cols;
      final col = i % cols;
      final x = tray.left + tray.width / 2 + (col - (inRow - 1) / 2) * tray.width / cols;
      plates.add(Offset(x, tray.top + tray.height * (row + 0.5) / rows));
    }
    final side = math.min(monster.width, monster.height);
    final body = Rect.fromLTWH(monster.center.dx - side / 2, monster.bottom - side, side, side);
    return _Layout(body, plates, food);
  }

  final Rect monster;
  final List<Offset> plates;
  final double food;

  Offset get mouth => monster.topLeft + Offset(MonsterPainter.mouthAt.dx * monster.width, MonsterPainter.mouthAt.dy * monster.height);
  Offset get eyes => monster.topLeft + Offset(MonsterPainter.eyesAt.dx * monster.width, MonsterPainter.eyesAt.dy * monster.height);
}

class _Plate extends StatelessWidget {
  const _Plate({required this.size, required this.glow});
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: glow ? const Color(0xFFFFC93C) : const Color(0xFFDDEBF5), width: glow ? size * 0.06 : size * 0.03),
          // A solid halo, not a blur: blurs are too slow to animate on a frame.
          boxShadow: [BoxShadow(color: glow ? const Color(0x77FFD54F) : const Color(0x00FFD54F), spreadRadius: glow ? 10 : 0), const BoxShadow(color: Color(0x14000000), offset: Offset(0, 4))],
        ),
      );
}

/// The launcher tile's picture: the orange monster, mouth open for a
/// letter.
class LetterMonsterIcon extends StatelessWidget {
  const LetterMonsterIcon({super.key, required this.size});
  final double size;

  static final _still = ValueNotifier<Offset>(const Offset(0.3, 0.4));

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: MonsterPainter(
                    chew: kAlwaysDismissedAnimation,
                    shake: kAlwaysDismissedAnimation,
                    blink: kAlwaysDismissedAnimation,
                    open: const AlwaysStoppedAnimation(0.8),
                    hop: kAlwaysDismissedAnimation,
                    look: _still,
                    skin: MonsterSkin.orange,
                  ),
                ),
              ),
            ),
            Positioned(right: 0, bottom: 0, child: LetterBiscuit('A', size: size * 0.42)),
          ],
        ),
      );
}
