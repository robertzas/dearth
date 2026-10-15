import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

enum _Phase { roll, rolling, hop, land, moving, done }

/// Dice Dash (SPEC FR-TOY-03, Appendix B: dice patterns, counting on,
/// adding). A board game with no one to lose to. She taps the big die; it
/// tumbles and lands; the voice says the number ("Four! Hop four times!")
/// and the next square glows. Each tap on it hops her buddy one square,
/// counted out loud, until the dots are used up. Ladders carry her up,
/// slides whisk her down, and the birthday cake at the end is the round.
/// Level 3 asks where she'll land first (she taps that square: counting
/// on), level 4 rolls two dice that add up.
class DiceGame extends StatefulWidget {
  const DiceGame(this.c, {super.key});
  final GameController c;

  @override
  State<DiceGame> createState() => DiceGameState();
}

@visibleForTesting
class DiceGameState extends State<DiceGame> with RoundVoice {
  late DiceBoard _board;
  int _at = 0, _deal = 0, _slips = 0, _wrongHere = 0;

  /// The last roll, and the dots still to hop.
  List<int> _roll = const [];
  int _left = 0;

  /// Faces shown while the die tumbles.
  List<int> _shown = const [1];
  _Phase _phase = _Phase.roll;
  bool _rolledOnce = false;
  final _wiggles = <int, int>{};
  int _tokenHops = 0, _dieHops = 0;
  final _timers = <Timer>[];

  @visibleForTesting
  DiceBoard get debugBoard => _board;

  @visibleForTesting
  int get debugAt => _at;

  @visibleForTesting
  List<int> get debugRoll => _roll;

  /// Where the roll lands, before ladders and slides.
  @visibleForTesting
  int get debugLanding => _board.landing(_at, _left);

  @override
  GameController get voiceOf => widget.c;

  @override
  String? get promptClip => switch (_phase) {
        _Phase.roll => _rolledOnce ? VoiceLine.diceAgain : VoiceLine.diceRoll,
        _Phase.hop || _Phase.land => _rollClip(),
        _ => null,
      };

  int get _total => _roll.fold(0, (a, b) => a + b);

  String _rollClip() => _roll.length == 2 ? diceTwoClip(_roll[0], _roll[1]) : (_board.mode == DiceMode.landOn ? diceLandClip(_total) : diceHopClip(_total));

  @override
  void initState() {
    super.initState();
    _newBoard();
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

  void _newBoard() {
    _board = diceBoard(widget.c.level, widget.c.random);
    _at = 0;
    _slips = 0;
    _roll = const [];
    _shown = [for (var i = 0; i < _board.dice; i++) 1];
    _phase = _Phase.roll;
    _rolledOnce = false;
    _deal++;
    askSoon();
    if (mounted) setState(() {});
  }

  /// The die tumbles through faces for a moment, then lands.
  void _tapDie() {
    stillHere();
    if (_phase != _Phase.roll) {
      // Not now: a little shake says so.
      setState(() => _dieHops++);
      return;
    }
    final c = widget.c;
    _roll = diceRoll(_board, c.random);
    _rolledOnce = true;
    _phase = _Phase.rolling;
    c.sound(Sfx.boing, volume: 0.5);
    for (var k = 0; k < 8; k++) {
      _after(Duration(milliseconds: 80 * k), () {
        c.sound(Sfx.tap, volume: 0.3, rate: 1.2);
        setState(() => _shown = [for (var i = 0; i < _board.dice; i++) 1 + c.random.nextInt(_board.faces)]);
      });
    }
    _after(const Duration(milliseconds: 720), () {
      c.sound(Sfx.snap);
      _left = _total;
      _wrongHere = 0;
      setState(() {
        _shown = _roll;
        _phase = _board.mode == DiceMode.landOn ? _Phase.land : _Phase.hop;
      });
      askSoon(after: const Duration(milliseconds: 150));
    });
  }

  void _tapSquare(int i) {
    stillHere();
    switch (_phase) {
      case _Phase.hop:
        if (i == _at + 1 || i == _at) {
          _hop();
        } else {
          _miss(i);
        }
      case _Phase.land:
        if (i == _board.landing(_at, _left)) {
          widget.c.sound(Sfx.sparkle, volume: 0.6);
          setState(() => _phase = _Phase.moving);
          _walk();
        } else {
          _miss(i);
        }
      default:
        if (i == _at) setState(() => _tokenHops++);
    }
  }

  /// Not that square: a wiggle, and after two the right one glows.
  void _miss(int i) {
    _slips++;
    _wrongHere++;
    widget.c.cue();
    setState(() => _wiggles[i] = (_wiggles[i] ?? 0) + 1);
  }

  /// One hop forward, counted.
  void _hop() {
    if (_left <= 0) return;
    final counted = _total - _left + 1;
    widget.c.say(numberClip(counted));
    widget.c.sound(Sfx.blip, volume: 0.5, rate: math.pow(2, const [0, 2, 4, 5, 7, 9, 11][(counted - 1).clamp(0, 6)] / 12).toDouble());
    setState(() {
      _at = math.min(_at + 1, _board.cake);
      _left--;
      _tokenHops++;
    });
    if (_left == 0 || _at == _board.cake) {
      setState(() => _phase = _Phase.moving);
      _after(afterVoice(numberClip(counted), atLeast: const Duration(milliseconds: 600)), _landed);
    }
  }

  /// Land-on mode: the buddy hops the counted squares by itself.
  void _walk() {
    if (_left <= 0 || _at == _board.cake) {
      _after(const Duration(milliseconds: 300), _landed);
      return;
    }
    final counted = _total - _left + 1;
    widget.c.say(numberClip(counted));
    setState(() {
      _at++;
      _left--;
      _tokenHops++;
    });
    _after(const Duration(milliseconds: 650), _walk);
  }

  /// On the square: a ladder or a slide, the cake, or the next roll.
  void _landed() {
    final c = widget.c;
    final to = _board.afterJump(_at);
    if (to != _at) {
      final up = to > _at;
      c.say(up ? VoiceLine.diceLadder : VoiceLine.diceSlide);
      c.sound(up ? Sfx.sparkle : Sfx.boing, volume: 0.6);
      _after(const Duration(milliseconds: 900), () {
        setState(() => _at = to);
        _after(afterVoice(up ? VoiceLine.diceLadder : VoiceLine.diceSlide, atLeast: const Duration(milliseconds: 900)), _landed);
      });
      return;
    }
    if (_at == _board.cake) {
      quiet();
      setState(() => _phase = _Phase.done);
      c.say(VoiceLine.diceCake);
      unawaited(c.finishRound(diceResult(_slips), emoji: '🎂'));
      _after(afterVoice(VoiceLine.diceCake, atLeast: const Duration(milliseconds: 3200)), _newBoard);
      return;
    }
    setState(() => _phase = _Phase.roll);
    askSoon(after: const Duration(milliseconds: 300));
  }

  /// The square to glow: the next hop, or (after two slips or a long
  /// pause) where the roll lands.
  int? get _glow => switch (_phase) {
        _Phase.hop => _at + 1,
        _Phase.land when _wrongHere >= 2 || idleHint => _board.landing(_at, _left),
        _ => null,
      };

  String _askLabel() => switch (_phase) {
        _Phase.roll || _Phase.rolling => 'Roll the dice',
        _Phase.hop => 'Hop $_left more',
        _Phase.land => 'Rolled $_total: where will you land?',
        _Phase.moving => 'Hopping',
        _Phase.done => 'You made it to the cake!',
      };

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final buddy = buddyEmoji(widget.c.kid.buddy);
    return Backdrop(
      top: const Color(0xFFE3F6FF),
      bottom: const Color(0xFFE9F8E1),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final wide = box.maxWidth > box.maxHeight * 1.1;
              final dieSize = math.min(260 * t.scale, wide ? math.min(box.maxWidth * 0.2, box.maxHeight * (_board.dice == 2 ? 0.4 : 0.6)) : box.maxHeight * 0.2);
              final dice = _Dice(faces: _shown, size: dieSize, sideBySide: !wide, rolling: _phase == _Phase.rolling, ready: _phase == _Phase.roll, hops: _dieHops, onTap: _tapDie, label: _phase == _Phase.roll ? 'Roll the dice' : 'Rolled $_total');
              final board = _Board(
                key: ValueKey(_deal),
                board: _board,
                at: _at,
                glow: _glow,
                buddy: buddy,
                wiggles: _wiggles,
                tokenHops: _tokenHops,
                onTap: _tapSquare,
              );
              return wide
                  ? Row(children: [Expanded(child: board), SizedBox(width: t.space.xl), dice])
                  : Column(children: [Expanded(child: board), SizedBox(height: t.space.lg), dice]);
            }),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'dice.ask',
              label: _askLabel(),
              onSayAgain: sayPrompt,
              children: [
                DEmoji(buddy, size: 40 * t.scale),
                SizedBox(width: t.space.xs),
                DEmoji('➡️', size: 30 * t.scale),
                SizedBox(width: t.space.xs),
                DEmoji('🎂', size: 40 * t.scale),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Where the squares sit: rows of six, winding up from the bottom left
/// like a board game's track.
class _Geo {
  _Geo(this.origin, this.cell, this.cols, this.rows);

  factory _Geo.of(Size area, int squares) {
    const cols = kDiceRow;
    final rows = (squares / cols).ceil();
    final cell = math.min(area.width / cols, area.height / rows);
    return _Geo(Offset((area.width - cell * cols) / 2, (area.height - cell * rows) / 2), cell, cols, rows);
  }

  final Offset origin;
  final double cell;
  final int cols, rows;

  Offset center(int i) {
    final row = i ~/ cols, k = i % cols;
    final col = row.isEven ? k : cols - 1 - k;
    return origin + Offset((col + 0.5) * cell, (rows - 1 - row + 0.5) * cell);
  }
}

class _Board extends StatelessWidget {
  const _Board({super.key, required this.board, required this.at, required this.glow, required this.buddy, required this.wiggles, required this.tokenHops, required this.onTap});
  final DiceBoard board;
  final int at;
  final int? glow;
  final String buddy;
  final Map<int, int> wiggles;
  final int tokenHops;
  final ValueChanged<int> onTap;

  String _label(int i) {
    final parts = [
      i == 0 ? 'Start' : (i == board.cake ? 'Cake' : 'Square $i'),
      if (i == at) 'you are here',
      if (i == glow) 'glowing',
      if (board.jumps[i] case final to?) to > i ? 'ladder up to $to' : 'slide down to $to',
    ];
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final g = _Geo.of(box.biggest, board.squares);
        final square = g.cell * 0.86;
        int? squareAt(Offset p) {
          for (var i = 0; i < board.squares; i++) {
            if ((g.center(i) - p).distance < g.cell * 0.5) return i;
          }
          return null;
        }

        return Listener(
          // On the finger going down: a hop can't wait for the tap to end.
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            final i = squareAt(e.localPosition);
            if (i != null) onTap(i);
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(child: RepaintBoundary(child: DStillPaint(painter: _BoardPainter(board, g), outset: EdgeInsets.all(g.cell * 0.4)))),
              for (var i = 0; i < board.squares; i++)
                Positioned(
                  left: g.center(i).dx - square / 2,
                  top: g.center(i).dy - square / 2,
                  width: square,
                  height: square,
                  child: tid(
                    'dice.square.$i',
                    Semantics(
                      button: true,
                      label: _label(i),
                      onTap: () => onTap(i),
                      excludeSemantics: true,
                      child: IgnorePointer(
                        child: Wiggle(
                          count: wiggles[i] ?? 0,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(square * 0.22),
                              border: Border.all(color: i == glow ? const Color(0xFFFFC93C) : const Color(0x00FFC93C), width: square * 0.08),
                              boxShadow: [BoxShadow(color: i == glow ? const Color(0x88FFD54F) : const Color(0x00FFD54F), spreadRadius: i == glow ? square * 0.08 : 0)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // The buddy hops square to square (and rides ladders and slides).
              AnimatedPositioned(
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeInOut,
                left: g.center(at).dx - square * 0.42,
                top: g.center(at).dy - square * 0.62,
                child: IgnorePointer(
                  child: tid(
                    'dice.token',
                    Semantics(
                      label: 'On ${at == 0 ? 'the start' : (at == board.cake ? 'the cake' : 'square $at')}',
                      excludeSemantics: true,
                      child: Hop(count: tokenHops, child: DEmoji(buddy, size: square * 0.84)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      });
}

/// The track: squares in soft colors with their numbers, a flag at the
/// start, the cake at the end, ladders and slides. Painted once.
class _BoardPainter extends CustomPainter {
  const _BoardPainter(this.board, this.g);
  final DiceBoard board;
  final _Geo g;

  static const _tiles = [Color(0xFFFFE8A3), Color(0xFFBDE7FF), Color(0xFFFFC9DE), Color(0xFFC8F2C2), Color(0xFFE3D4FF)];
  static const _ink = Color(0xFF2B2440);

  @override
  void paint(Canvas canvas, Size size) {
    final s = g.cell * 0.86;
    // The path that joins them, under the squares.
    final road = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = g.cell * 0.34
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFFE9DCC6);
    final line = Path()..moveTo(g.center(0).dx, g.center(0).dy);
    for (var i = 1; i < board.squares; i++) {
      line.lineTo(g.center(i).dx, g.center(i).dy);
    }
    canvas.drawPath(line, road);
    final fill = Paint();
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.04
      ..color = const Color(0x332B2440);
    for (var i = 0; i < board.squares; i++) {
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: g.center(i), width: s, height: s), Radius.circular(s * 0.22));
      fill.color = i == board.cake ? const Color(0xFFFFF3C4) : _tiles[i % _tiles.length];
      canvas
        ..drawRRect(r.shift(Offset(0, s * 0.05)), Paint()..color = const Color(0x22000000))
        ..drawRRect(r, fill)
        ..drawRRect(r, edge);
      if (i > 0 && i < board.cake) {
        final tp = TextPainter(
          text: TextSpan(text: '$i', style: TextStyle(fontFamily: 'Fredoka', package: 'dearth_ui', fontSize: s * 0.26, fontWeight: FontWeight.w600, color: const Color(0x992B2440))),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, g.center(i) + Offset(s * 0.42 - tp.width, -s * 0.44));
      }
    }
    for (final MapEntry(key: from, value: to) in board.jumps.entries) {
      to > from ? _ladder(canvas, g.center(from), g.center(to), s) : _slide(canvas, g.center(from), g.center(to), s);
    }
    _flag(canvas, g.center(0), s);
    _cake(canvas, g.center(board.cake), s);
  }

  void _ladder(Canvas canvas, Offset a, Offset b, double s) {
    final d = b - a;
    final n = Offset(-d.dy, d.dx) / d.distance * s * 0.16;
    final rail = Paint()
      ..strokeWidth = s * 0.07
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFB0703A);
    final rung = Paint()
      ..strokeWidth = s * 0.05
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFD69A5C);
    final steps = (d.distance / (s * 0.3)).round();
    for (var k = 1; k < steps; k++) {
      final p = a + d * (k / steps);
      canvas.drawLine(p - n, p + n, rung);
    }
    canvas
      ..drawLine(a - n, b - n, rail)
      ..drawLine(a + n, b + n, rail);
  }

  void _slide(Canvas canvas, Offset top, Offset bottom, double s) {
    final d = bottom - top;
    final bend = Offset(-d.dy, d.dx) * 0.25;
    final path = Path()
      ..moveTo(top.dx, top.dy)
      ..quadraticBezierTo(top.dx + d.dx / 2 + bend.dx, top.dy + d.dy / 2 + bend.dy, bottom.dx, bottom.dy);
    canvas
      ..drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.3
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFE85D75))
      ..drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.16
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFF9FB0));
  }

  void _flag(Canvas canvas, Offset c, double s) {
    final pole = Paint()
      ..strokeWidth = s * 0.05
      ..strokeCap = StrokeCap.round
      ..color = _ink;
    final foot = c + Offset(-s * 0.2, s * 0.32);
    canvas.drawLine(foot, foot - Offset(0, s * 0.62), pole);
    canvas.drawPath(
      Path()
        ..moveTo(foot.dx, foot.dy - s * 0.62)
        ..lineTo(foot.dx + s * 0.42, foot.dy - s * 0.5)
        ..lineTo(foot.dx, foot.dy - s * 0.36)
        ..close(),
      Paint()..color = const Color(0xFF4CC46A),
    );
  }

  /// A three-layer birthday cake with a candle: the goal.
  void _cake(Canvas canvas, Offset c, double s) {
    final w = s * 0.7, h = s * 0.18;
    final base = c + Offset(0, s * 0.3);
    final colors = [const Color(0xFFF7B2C4), const Color(0xFFFFF0D9), const Color(0xFFF7B2C4)];
    for (var k = 0; k < 3; k++) {
      final width = w * (1 - k * 0.18);
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: base - Offset(0, h * (k + 0.5)), width: width, height: h), Radius.circular(h * 0.3));
      canvas
        ..drawRRect(r, Paint()..color = colors[k])
        ..drawRRect(r, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.025
          ..color = const Color(0xFFB24A6A));
    }
    final top = base - Offset(0, h * 3);
    canvas
      ..drawRect(Rect.fromCenter(center: top - Offset(0, s * 0.08), width: s * 0.06, height: s * 0.16), Paint()..color = const Color(0xFF5B8DEF))
      ..drawOval(Rect.fromCenter(center: top - Offset(0, s * 0.21), width: s * 0.08, height: s * 0.12), Paint()..color = const Color(0xFFFFB627));
  }

  @override
  bool shouldRepaint(_BoardPainter old) => old.board != board || old.g.cell != g.cell || old.g.origin != g.origin;
}

/// The big die (or two): white with dots, tumbling while it rolls, a
/// gentle bounce when it's her turn to tap it.
class _Dice extends StatelessWidget {
  const _Dice({required this.faces, required this.size, required this.sideBySide, required this.rolling, required this.ready, required this.hops, required this.onTap, required this.label});
  final List<int> faces;
  final double size;

  /// Two dice side by side (under a tall board), else one above the other.
  final bool sideBySide;
  final bool rolling, ready;
  final int hops;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final each = faces.length == 2 ? size * 0.8 : size;
    return DPressable(
      id: 'dice.die',
      semanticLabel: label,
      excludeSemantics: true,
      onTap: onTap,
      borderRadius: BorderRadius.circular(size * 0.2),
      child: Wiggle(
        count: hops,
        child: Flex(
          direction: sideBySide ? Axis.horizontal : Axis.vertical,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, f) in faces.indexed)
              Padding(
                padding: EdgeInsets.all(each * 0.06),
                child: Transform.rotate(
                  // A tumbling die turns a little each face.
                  angle: rolling ? (f * 0.35 - 0.6) + i * 0.2 : 0,
                  child: SizedBox.square(dimension: each, child: RepaintBoundary(child: CustomPaint(painter: _DiePainter(f, glow: ready)))),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DiePainter extends CustomPainter {
  const _DiePainter(this.face, {required this.glow});
  final int face;
  final bool glow;

  static const _pips = {
    1: [(0.5, 0.5)],
    2: [(0.27, 0.27), (0.73, 0.73)],
    3: [(0.27, 0.27), (0.5, 0.5), (0.73, 0.73)],
    4: [(0.27, 0.27), (0.73, 0.27), (0.27, 0.73), (0.73, 0.73)],
    5: [(0.27, 0.27), (0.73, 0.27), (0.5, 0.5), (0.27, 0.73), (0.73, 0.73)],
    6: [(0.27, 0.25), (0.73, 0.25), (0.27, 0.5), (0.73, 0.5), (0.27, 0.75), (0.73, 0.75)],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final box = RRect.fromRectAndRadius((Offset.zero & Size.square(s)).deflate(s * 0.04), Radius.circular(s * 0.2));
    if (glow) canvas.drawRRect(box.inflate(s * 0.03), Paint()..color = const Color(0x66FFD54F));
    canvas
      ..drawRRect(box.shift(Offset(0, s * 0.04)), Paint()..color = const Color(0x33000000))
      ..drawRRect(box, Paint()..color = Colors.white)
      ..drawRRect(box, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.035
        ..color = const Color(0xFF2B2440));
    final pip = Paint()..color = const Color(0xFFE0414F);
    for (final (x, y) in _pips[face.clamp(1, 6)]!) {
      canvas.drawCircle(Offset(x * s, y * s), s * 0.085, pip);
    }
  }

  @override
  bool shouldRepaint(_DiePainter old) => old.face != face || old.glow != glow;
}
