import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'shapes.dart';
import 'voice_widgets.dart';

/// The colors I Spy names, as paint.
const Map<String, Color> kSpyPaint = {
  'red': Color(0xFFE53935),
  'orange': Color(0xFFFB8C00),
  'yellow': Color(0xFFFDD835),
  'green': Color(0xFF43A047),
  'blue': Color(0xFF1E88E5),
  'purple': Color(0xFF8E24AA),
  'pink': Color(0xFFF06292),
  'brown': Color(0xFF8D6E63),
  'white': Color(0xFFFFFFFF),
  'black': Color(0xFF212121),
};

const Map<String, ToyShape> _spyShapes = {
  'round': ToyShape.circle,
  'star': ToyShape.star,
  'heart': ToyShape.heart,
  'triangle': ToyShape.triangle,
  'square': ToyShape.square,
};

/// I Spy (SPEC FR-TOY-03, Appendix B: vocabulary and attention). Things are
/// scattered over a meadow and the voice spies one: something yellow, then
/// something round, then something that starts with B. The pill shows the
/// clue too (a dab of paint, a shape, a letter). Every thing says its name
/// when tapped; after two misses the one she's looking for glows.
class SpyGame extends StatefulWidget {
  const SpyGame(this.c, {super.key});
  final GameController c;

  @override
  State<SpyGame> createState() => SpyGameState();
}

@visibleForTesting
class SpyGameState extends State<SpyGame> {
  SpyRound? _round;

  /// How far each thing is nudged off its square (a fraction of it) and how
  /// big it is, so the meadow looks scattered rather than tiled.
  List<(Offset, double)> _spots = const [];
  final _tried = <String>{};
  final _wiggles = <String, int>{};
  int _slips = 0, _deal = 0;
  bool _solved = false;
  Timer? _next, _ask;

  @visibleForTesting
  SpyRound get debugRound => _round!;

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  @override
  void dispose() {
    _next?.cancel();
    _ask?.cancel();
    super.dispose();
  }

  void _newRound() {
    final rng = widget.c.random;
    final r = _round = spyRound(widget.c.level, rng, last: _round?.answer.word);
    _spots = [
      for (var i = 0; i < r.things.length; i++) (Offset((rng.nextDouble() - 0.5) * 0.3, (rng.nextDouble() - 0.5) * 0.25), 0.85 + rng.nextDouble() * 0.2),
    ];
    _tried.clear();
    _slips = 0;
    _solved = false;
    _deal++;
    _ask?.cancel();
    _ask = Timer(const Duration(milliseconds: 600), _sayPrompt);
    if (mounted) setState(() {});
  }

  void _sayPrompt() => widget.c.say(spyClip(_round!.clue, _round!.value));

  void _pick(PictureWord w) {
    final r = _round!;
    if (_solved || _tried.contains(w.word)) return;
    widget.c.say(w.clip);
    if (w != r.answer) {
      _slips++;
      widget.c.cue();
      setState(() {
        _tried.add(w.word);
        _wiggles[w.word] = (_wiggles[w.word] ?? 0) + 1;
      });
      return;
    }
    widget.c.sound(Sfx.sparkle);
    setState(() => _solved = true);
    unawaited(widget.c.finishRound(countingResult(_slips), emoji: w.emoji));
    _next = Timer(const Duration(milliseconds: 2800), _newRound);
  }

  String get _clueText => switch (_round!.clue) {
        SpyClue.color => 'something ${_round!.value}',
        SpyClue.shape => _round!.value == 'round' || _round!.value == 'square' ? 'something ${_round!.value}' : 'something shaped like a ${_round!.value}',
        SpyClue.letter => 'something that starts with ${_round!.value}',
      };

  Widget _clue(DTheme t) {
    final r = _round!;
    final s = 56 * t.scale;
    return switch (r.clue) {
      SpyClue.color => Container(
          width: s,
          height: s,
          decoration: BoxDecoration(color: kSpyPaint[r.value], shape: BoxShape.circle, border: Border.all(color: const Color(0x33000000), width: 2)),
        ),
      SpyClue.shape => ToyShapeView(_spyShapes[r.value]!, size: s, color: const Color(0xFF9E9AAE)),
      SpyClue.letter => LetterPair(r.value, height: s),
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    return Stack(
      fit: StackFit.expand,
      children: [
        const RepaintBoundary(child: CustomPaint(painter: _MeadowPainter())),
        PlayArea(
          top: 150,
          child: LayoutBuilder(builder: (context, box) {
            // A loose grid: three across a wide meadow, two up a tall one.
            final n = r.things.length;
            final cols = n <= 4 || box.maxWidth < box.maxHeight ? 2 : 3;
            final rows = (n / cols).ceil();
            final base = math.min(math.min(box.maxWidth / cols, box.maxHeight / rows) * 0.62, 220 * t.scale);
            Offset spot(int i) => Offset(
                  ((i % cols) + 0.5 + _spots[i].$1.dx) / cols * box.maxWidth,
                  ((i ~/ cols) + 0.5 + _spots[i].$1.dy) / rows * box.maxHeight,
                );
            return Stack(
              key: ValueKey(_deal),
              children: [
                for (var i = 0; i < n; i++)
                  Positioned(
                    left: spot(i).dx - base * _spots[i].$2 / 2,
                    top: spot(i).dy - base * _spots[i].$2 / 2,
                    child: _Thing(
                      word: r.things[i],
                      size: base * _spots[i].$2,
                      tried: _tried.contains(r.things[i].word),
                      hint: _slips >= 2 && r.things[i] == r.answer && !_solved,
                      found: _solved && r.things[i] == r.answer,
                      wiggles: _wiggles[r.things[i].word] ?? 0,
                      onTap: () => _pick(r.things[i]),
                    ),
                  ),
              ],
            );
          }),
        ),
        TopPrompt(
          child: PromptPill(
            id: 'ispy.ask',
            label: _solved ? 'You found it: ${r.answer.word}!' : 'I spy $_clueText',
            onSayAgain: _sayPrompt,
            children: [DEmoji('👁️', size: 48 * t.scale), SizedBox(width: t.space.sm), _clue(t)],
          ),
        ),
      ],
    );
  }
}

class _Thing extends StatelessWidget {
  const _Thing({required this.word, required this.size, required this.tried, required this.hint, required this.found, required this.wiggles, required this.onTap});
  final PictureWord word;
  final double size;
  final bool tried, hint, found;
  final int wiggles;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Color and shape in the label too, for grown-ups' screen readers.
    final label = [word.word, ?word.color, ?word.shape].join(', ');
    return DPressable(
      id: 'ispy.thing.${word.word}',
      semanticLabel: found ? '$label, found' : label,
      excludeSemantics: true,
      onTap: onTap,
      pressedScale: 0.92,
      borderRadius: BorderRadius.circular(size / 2),
      child: Hop(
        count: found ? 1 : 0,
        child: Wiggle(
          count: wiggles,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tried ? const Color(0x55FFFFFF) : const Color(0xAAFFFFFF),
              shape: BoxShape.circle,
              border: Border.all(color: hint || found ? const Color(0xFFFFC93C) : const Color(0x00FFC93C), width: 6),
              // A solid halo, never an animated blur.
              boxShadow: [BoxShadow(color: hint ? const Color(0x88FFD54F) : const Color(0x00FFD54F), spreadRadius: hint ? 10 : 0)],
            ),
            child: DEmoji(word.emoji, size: size * 0.66),
          ),
        ),
      ),
    );
  }
}

/// Sky and two rolling hills: plain enough that nothing on it looks like
/// something to find.
class _MeadowPainter extends CustomPainter {
  const _MeadowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFCDEBFF), Color(0xFFEAF7FF)]).createShader(Offset.zero & size),
    );
    final back = Path()
      ..moveTo(0, h * 0.5)
      ..quadraticBezierTo(w * 0.3, h * 0.36, w * 0.62, h * 0.5)
      ..quadraticBezierTo(w * 0.85, h * 0.6, w, h * 0.46)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(back, Paint()..color = const Color(0xFFBFE6A8));
    final front = Path()
      ..moveTo(0, h * 0.7)
      ..quadraticBezierTo(w * 0.45, h * 0.56, w, h * 0.72)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(front, Paint()..color = const Color(0xFFA5D98A));
  }

  @override
  bool shouldRepaint(_MeadowPainter old) => false;
}
