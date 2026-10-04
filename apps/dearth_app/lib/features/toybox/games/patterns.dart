import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';

/// Patterns (SPEC FR-TOY-03, Appendix B: logic). "What comes next?": a row
/// of pictures that repeat (AB, then AAB, then ABC) ends in a question
/// mark, and she picks what goes there. The top level grows towers: one,
/// two, three… how tall is the next? A wrong pick wiggles away; after two,
/// the right one glows.
class PatternsGame extends StatefulWidget {
  const PatternsGame(this.c, {super.key});
  final GameController c;

  @override
  State<PatternsGame> createState() => PatternsGameState();
}

@visibleForTesting
class PatternsGameState extends State<PatternsGame> {
  late PatternRound _round;
  final _tried = <int>{};
  final _wiggles = <int, int>{};
  int _slips = 0, _deal = 0;
  bool _solved = false;
  Timer? _next;

  @visibleForTesting
  PatternRound get debugRound => _round;

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  @override
  void dispose() {
    _next?.cancel();
    super.dispose();
  }

  void _newRound() {
    _round = patternRound(widget.c.level, widget.c.random);
    _tried.clear();
    _slips = 0;
    _solved = false;
    _deal++;
    if (mounted) setState(() {});
  }

  void _pick(int i) {
    if (_solved || _tried.contains(i)) return;
    if (_round.choices[i] != _round.answer) {
      _slips++;
      widget.c.cue();
      setState(() {
        _tried.add(i);
        _wiggles[i] = (_wiggles[i] ?? 0) + 1;
      });
      return;
    }
    widget.c.sound(Sfx.snap);
    setState(() => _solved = true);
    unawaited(widget.c.finishRound(countingResult(_slips), emoji: _round.answer.characters.first));
    _next = Timer(const Duration(milliseconds: 2400), _newRound);
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round;
    return Backdrop(
      top: const Color(0xFFF3EEFF),
      bottom: const Color(0xFFFFF4E6),
      child: PlayArea(
        child: LayoutBuilder(builder: (context, box) {
          final count = r.shown.length + 1;
          final wide = box.maxWidth > box.maxHeight;
          Widget tower(String p, double e) => Column(mainAxisSize: MainAxisSize.min, verticalDirection: VerticalDirection.up, children: [for (final c in p.characters) DEmoji(c, size: e)]);
          final List<Widget> row;
          final List<Widget> choices;
          if (r.towers) {
            // One emoji size for the towers and the answers, sized by the
            // tallest of them.
            final tallest = [...r.shown, ...r.choices].map((p) => p.characters.length).reduce(math.max);
            final e = math.min(math.min(box.maxHeight * 0.42 / (tallest + 0.6), box.maxWidth / (count * 1.5)), 96 * t.scale);
            row = [
              for (final (i, p) in r.shown.indexed) tid('patterns.item.$i', Semantics(label: p, excludeSemantics: true, child: SizedBox(width: e * 1.4, child: Center(child: tower(p, e))))),
              tid(
                'patterns.slot',
                Semantics(
                  label: _solved ? r.answer : 'What comes next?',
                  excludeSemantics: true,
                  child: SizedBox(width: e * 1.4, child: Center(child: _solved ? Hop(count: 1, child: tower(r.answer, e)) : _Question(size: e * 1.2))),
                ),
              ),
            ];
            choices = [
              for (final (i, p) in r.choices.indexed)
                PictureTile(
                  id: 'patterns.choice.$i',
                  label: p,
                  size: e * (tallest + 0.7),
                  width: e * 1.8,
                  tried: _tried.contains(i),
                  hint: _slips >= 2 && p == r.answer && !_solved,
                  wiggles: _wiggles[i] ?? 0,
                  onTap: () => _pick(i),
                  child: tower(p, e * 0.92),
                ),
            ];
          } else {
            // A long row wraps on a tall screen.
            final perRow = wide ? count : math.min(count, 5);
            final lines = (count / perRow).ceil();
            final cell = math.min(math.min(box.maxWidth / perRow * 0.9, box.maxHeight * 0.48 / lines), 210 * t.scale);
            final choice = math.min(math.min(box.maxWidth / 3.4, box.maxHeight * 0.3), 230 * t.scale);
            row = [
              for (final (i, p) in r.shown.indexed) tid('patterns.item.$i', Semantics(label: p, excludeSemantics: true, child: SizedBox.square(dimension: cell, child: Center(child: DEmoji(p, size: cell * 0.78))))),
              tid(
                'patterns.slot',
                Semantics(
                  label: _solved ? r.answer : 'What comes next?',
                  excludeSemantics: true,
                  child: SizedBox.square(dimension: cell, child: Center(child: _solved ? Hop(count: 1, child: DEmoji(r.answer, size: cell * 0.78)) : _Question(size: cell * 0.86))),
                ),
              ),
            ];
            choices = [
              for (final (i, p) in r.choices.indexed)
                PictureTile(
                  id: 'patterns.choice.$i',
                  label: p,
                  size: choice,
                  tried: _tried.contains(i),
                  hint: _slips >= 2 && p == r.answer && !_solved,
                  wiggles: _wiggles[i] ?? 0,
                  onTap: () => _pick(i),
                  child: DEmoji(p, size: choice * 0.62),
                ),
            ];
          }
          return Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Wrap(
                key: ValueKey(_deal),
                alignment: WrapAlignment.center,
                crossAxisAlignment: r.towers ? WrapCrossAlignment.end : WrapCrossAlignment.center,
                children: row,
              ),
              Wrap(alignment: WrapAlignment.center, spacing: t.space.lg, runSpacing: t.space.lg, children: choices),
            ],
          );
        }),
      ),
    );
  }
}

/// The empty place at the end of the row: a dashed ring with a "?" that
/// breathes.
class _Question extends StatefulWidget {
  const _Question({required this.size});
  final double size;

  @override
  State<_Question> createState() => _QuestionState();
}

class _QuestionState extends State<_Question> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.04).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
          child: SizedBox.square(
            dimension: widget.size,
            child: CustomPaint(painter: const _DashedRing(), child: Center(child: DEmoji('❓', size: widget.size * 0.5))),
          ),
        ),
      );
}

class _DashedRing extends CustomPainter {
  const _DashedRing();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2 - 4;
    final c = size.center(Offset.zero);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(3, r * 0.06)
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF9B8CE8);
    const dashes = 18;
    for (var i = 0; i < dashes; i++) {
      final a = i * 2 * math.pi / dashes;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), a, math.pi / dashes, false, p);
    }
  }

  @override
  bool shouldRepaint(_DashedRing old) => false;
}
