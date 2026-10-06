import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Sight Words (SPEC FR-TOY-03, Appendix B: early reading, whole words).
/// Street signs stand along a road, each with a word in the print she
/// traces; a little bus waits at the start. The voice asks "Find the word
/// go." She taps a sign: a wrong one wiggles and reads itself out (so a
/// slip is still reading), and after two the right one glows; a long pause
/// asks again. The right one sends the bus along the road to stop under it,
/// and the voice reads the word.
class SightGame extends StatefulWidget {
  const SightGame(this.c, {super.key});
  final GameController c;

  @override
  State<SightGame> createState() => SightGameState();
}

@visibleForTesting
class SightGameState extends State<SightGame> {
  SightRound? _round;
  final _wiggles = <int, int>{}, _hops = <int, int>{};
  int _slips = 0, _deal = 0;

  /// The sign the bus drives to, once she's found it.
  int? _stop;
  bool _arrived = false;
  Timer? _ask, _idle, _arrive, _next;

  @visibleForTesting
  SightRound get debugRound => _round!;

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  @override
  void dispose() {
    for (final t in [_ask, _idle, _arrive, _next]) {
      t?.cancel();
    }
    super.dispose();
  }

  void _newRound() {
    _round = sightRound(widget.c.level, widget.c.random, last: _round?.word);
    _wiggles.clear();
    _hops.clear();
    _slips = 0;
    _stop = null;
    _arrived = false;
    _deal++;
    _ask?.cancel();
    // A beat for the signs to stand before the question.
    _ask = Timer(const Duration(milliseconds: 600), _sayPrompt);
    _waitIdle();
    if (mounted) setState(() {});
  }

  void _sayPrompt() => widget.c.say(sightAskClip(_round!.word));

  /// A long pause asks again (not a slip).
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 12), () {
      if (!mounted || _stop != null) return;
      _sayPrompt();
      _waitIdle();
    });
  }

  void _tap(int i) {
    final r = _round!;
    final word = r.signs[i];
    if (_stop != null) {
      // Found: any sign just reads itself.
      widget.c.say(sightWordClip(word));
      setState(() => _hops[i] = (_hops[i] ?? 0) + 1);
      return;
    }
    _waitIdle();
    if (word != r.word) {
      _slips++;
      widget.c.cue();
      widget.c.say(sightWordClip(word));
      setState(() => _wiggles[i] = (_wiggles[i] ?? 0) + 1);
      return;
    }
    _idle?.cancel();
    widget.c.sound(Sfx.blip, volume: 0.5);
    setState(() => _stop = i);
    // The bus pulls up under the sign, then the word is read.
    _arrive = Timer(_drive, () {
      if (!mounted) return;
      widget.c.say(sightWordClip(word));
      widget.c.sound(Sfx.sparkle, volume: 0.5);
      setState(() {
        _arrived = true;
        _hops[i] = (_hops[i] ?? 0) + 1;
      });
      unawaited(widget.c.finishRound(sightResult(_slips), emoji: '🚌'));
      _next = Timer(afterVoice(sightWordClip(word), atLeast: const Duration(milliseconds: 2800)), _newRound);
    });
  }

  static const _drive = Duration(milliseconds: 1100);

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    final found = _stop != null;
    return Backdrop(
      top: const Color(0xFFDDF0FF),
      bottom: const Color(0xFFE6F5DA),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final l = _Layout.of(box.biggest, r.signs);
              final busAt = _stop == null ? l.busStart : l.signs[_stop!].dx;
              return Stack(
                key: ValueKey(_deal),
                clipBehavior: Clip.none,
                children: [
                  // The road.
                  Positioned(
                    left: -t.space.lg,
                    right: -t.space.lg,
                    top: l.road,
                    height: l.roadHeight,
                    child: RepaintBoundary(child: CustomPaint(painter: _RoadPainter())),
                  ),
                  // Posts behind every board, standing on the kerb.
                  for (final c in l.signs)
                    Positioned(
                      left: c.dx - l.board.height * 0.06,
                      top: c.dy,
                      width: l.board.height * 0.12,
                      height: l.road - c.dy + l.roadHeight * 0.06,
                      child: DecoratedBox(decoration: BoxDecoration(color: const Color(0xFF8C8FA3), borderRadius: BorderRadius.circular(l.board.height * 0.04))),
                    ),
                  for (var i = 0; i < r.signs.length; i++) _sign(i, l),
                  AnimatedPositioned(
                    duration: _drive,
                    curve: Curves.easeInOutCubic,
                    left: busAt - l.bus / 2,
                    top: l.road + l.roadHeight * 0.5 - l.bus * 0.62,
                    child: tid(
                      'sight.bus',
                      Semantics(
                        label: _arrived ? 'Bus at ${r.word}' : 'Bus waiting',
                        excludeSemantics: true,
                        child: IgnorePointer(child: DEmoji('🚌', size: l.bus)),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'sight.ask',
              label: found ? 'You found ${r.word}!' : 'Find the word${r.word.contains(' ') ? 's' : ''} ${r.word}',
              onSayAgain: _sayPrompt,
              children: [DEmoji('🚏', size: 44 * t.scale), SizedBox(width: t.space.xs), DEmoji('👀', size: 44 * t.scale)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sign(int i, _Layout l) {
    final r = _round!;
    final word = r.signs[i];
    final c = l.signs[i];
    final hint = _stop == null && _slips >= 2 && word == r.word;
    return Positioned(
      left: c.dx - l.board.width / 2,
      top: c.dy - l.board.height / 2,
      child: DPressable(
        id: 'sight.sign.$i',
        semanticLabel: 'Sign: $word${_stop == i ? ', found' : ''}',
        excludeSemantics: true,
        onTap: () => _tap(i),
        pressedScale: 0.95,
        borderRadius: BorderRadius.circular(l.board.height * 0.2),
        child: Hop(
          count: _hops[i] ?? 0,
          child: Wiggle(
            count: _wiggles[i] ?? 0,
            child: _Sign(word: word, size: l.board, letters: l.letters, color: _kSignColors[i % _kSignColors.length], glow: hint, lit: _stop == i && _arrived),
          ),
        ),
      ),
    );
  }
}

/// Street-sign borders, left to right.
const List<Color> _kSignColors = [Color(0xFF2E9E5B), Color(0xFF2F6FD6), Color(0xFFF2A93B), Color(0xFFE0414F)];

const Color _ink = Color(0xFF2B2440);

/// A sign board: white with a colored rim and the word in the Toybox's
/// print, all letters on one baseline, as tall as on every other sign.
class _Sign extends StatelessWidget {
  const _Sign({required this.word, required this.size, required this.letters, required this.color, required this.glow, required this.lit});
  final String word;
  final Size size;

  /// Letter height, shared by the round's signs.
  final double letters;
  final Color color;
  final bool glow, lit;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final h = size.height;
    return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
      width: size.width,
      height: h,
      alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: h * 0.16, vertical: h * 0.1),
            decoration: BoxDecoration(
              color: lit ? const Color(0xFFFFF4C2) : Colors.white,
              borderRadius: BorderRadius.circular(h * 0.2),
              border: Border.all(color: glow ? const Color(0xFFFFC93C) : color, width: glow ? h * 0.09 : h * 0.06),
              // A solid halo, not a blur: blurs are too slow to animate on a frame.
              boxShadow: [BoxShadow(color: glow ? const Color(0x88FFD54F) : const Color(0x00FFD54F), spreadRadius: glow ? 10 : 0), ...t.elevation.e1],
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final ch in word.split(''))
                    ch == ' '
                        ? SizedBox(width: letters * _space)
                        : Padding(
                            padding: EdgeInsets.symmetric(horizontal: letters * _kern / 2),
                            child: GlyphView(ch, height: letters, color: _ink, frameTop: 0, frameBottom: 14),
                          ),
                ],
              ),
            ),
    );
  }
}

/// Between words and around letters, in letter heights.
const double _space = 0.32, _kern = 0.05;

/// [word]'s width at a letter height of 1: each glyph's own width on the
/// shared 0…14 band (stroke 1.3), as [GlyphView] draws it.
double _wordWidth(String word) {
  var w = 0.0;
  for (final ch in word.split('')) {
    w += ch == ' ' ? _space : (glyphFor(ch).width + 1.3) / 15.3 + _kern;
  }
  return w;
}

/// A grey road with a dashed middle line, the width of the play area.
class _RoadPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height * 0.2));
    canvas.drawRRect(r, Paint()..color = const Color(0xFF6E7183));
    // Kerbs.
    final kerb = Paint()..color = const Color(0xFFB9BCCB);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height * 0.08), kerb);
    final dash = Paint()..color = const Color(0xFFFFF6D8);
    final y = size.height * 0.62, w = size.height * 0.5, h = size.height * 0.06;
    for (var x = w * 0.5; x < size.width; x += w * 1.8) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y - h / 2, w, h), Radius.circular(h / 2)), dash);
    }
  }

  @override
  bool shouldRepaint(_RoadPainter old) => false;
}

/// Signs in a row on a wide screen, rows of two on a tall one; the road
/// along the bottom, sized to the signs, with the bus at its left end.
class _Layout {
  _Layout(this.signs, this.board, this.letters, this.road, this.roadHeight, this.bus, this.busStart);

  factory _Layout.of(Size area, List<String> words) {
    final n = words.length;
    final wide = area.width > area.height * 0.9;
    final per = wide ? n : 2;
    final rows = (n / per).ceil();
    // Boards 1.9 : 1, as big as a cell allows with room for the road.
    final cellW = area.width / per;
    final boardW = math.min(math.min(cellW * 0.86, area.height * 0.72 / rows * 1.9 / 1.5), 420.0);
    final board = Size(boardW, boardW / 1.9);
    final roadHeight = math.min(area.height * 0.16, board.height * 1.25).clamp(56.0, 180.0);
    final road = area.height - roadHeight;
    final cellH = (road - board.height * 0.3) / rows;
    final signs = <Offset>[
      for (var i = 0; i < n; i++)
        Offset(
          area.width / 2 + (i % per - (math.min(per, n - (i ~/ per) * per) - 1) / 2) * cellW,
          // A little above the middle of its band: a post shows beneath.
          cellH * (i ~/ per + 0.42),
        ),
    ];
    // One letter size for every sign: the longest word fits its board.
    final inner = board.width - board.height * 0.44;
    final longest = words.map(_wordWidth).reduce(math.max);
    final letters = math.min(board.height * 0.56, inner / longest);
    final bus = roadHeight * 0.95;
    return _Layout(signs, board, letters, road, roadHeight, bus, bus * 0.55);
  }

  final List<Offset> signs;
  final Size board;
  final double letters, road, roadHeight, bus, busStart;
}
