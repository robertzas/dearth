import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Hundred Square (SPEC FR-TOY-03, Appendix B: counting past twenty, place
/// value). Number squares in rows of ten, in the Toybox's digits; a
/// ladybug waits at the corner. The voice asks "Find the number
/// fifty-four." She taps a square: the right one brings the ladybug flying
/// to it and lights its whole row (the fifties), and the voice says the
/// number. A wrong square wiggles and says its own number ("Forty-five.");
/// after two slips the right row glows, after three the square. At the top
/// level some squares are blank and the number she's asked for is one of
/// them: "It's hiding! Where does it go?" Its row and column say where.
class HundredGame extends StatefulWidget {
  const HundredGame(this.c, {super.key});
  final GameController c;

  @override
  State<HundredGame> createState() => HundredGameState();
}

@visibleForTesting
class HundredGameState extends State<HundredGame> {
  HundredRound? _round;
  int _deal = 0, _slips = 0;
  bool _solved = false;
  final _shown = <int>{}; // hidden squares a wrong tap uncovered
  final _wiggles = <int, int>{};
  final _timers = <Timer>[];
  Timer? _idle;

  @visibleForTesting
  HundredRound get debugRound => _round!;

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

  void _newRound() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _round = hundredRound(widget.c.level, widget.c.random, last: _round);
    _deal++;
    _slips = 0;
    _solved = false;
    _shown.clear();
    _wiggles.clear();
    _after(const Duration(milliseconds: 600), _ask);
    if (mounted) setState(() {});
  }

  void _ask() {
    final r = _round!;
    final find = findNumberClip(r.target);
    widget.c.say(find);
    if (r.hiding) _after(afterVoice(find), () => widget.c.say(VoiceLine.hundredHiding));
    _waitIdle();
  }

  /// A long pause asks again (not a slip).
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 12), () {
      if (!mounted || _solved) return;
      _ask();
    });
  }

  void _tap(int n) {
    final r = _round!;
    if (_solved) return;
    _waitIdle();
    if (n != r.target) {
      _slips++;
      widget.c.cue();
      widget.c.say(numberClip(n));
      setState(() {
        _wiggles[n] = (_wiggles[n] ?? 0) + 1;
        // A blank square she tried shows what it was hiding.
        if (r.hidden.contains(n)) _shown.add(n);
      });
      return;
    }
    _idle?.cancel();
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    widget.c.sound(Sfx.sparkle, volume: 0.5);
    setState(() => _solved = true);
    // The ladybug lands, then the number is said as its row lights.
    _after(const Duration(milliseconds: 550), () => widget.c.say(numberClip(n)));
    unawaited(widget.c.finishRound(hundredResult(r, _slips), emoji: '🐞'));
    _after(const Duration(milliseconds: 3400), _newRound);
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    return Backdrop(
      top: const Color(0xFFFFF6E0),
      bottom: const Color(0xFFE8F4FF),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final gap = math.max(3.0, box.maxWidth * 0.006);
              // Room for the ladybug at the top-left corner.
              final cell = math.min(math.min((box.maxWidth - 9 * gap) / 10.6, (box.maxHeight - (r.rows - 1) * gap) / (r.rows + 0.6)), 150.0 * t.scale);
              final gridW = cell * 10 + gap * 9, gridH = cell * r.rows + gap * (r.rows - 1);
              final left = (box.maxWidth - gridW) / 2 + cell * 0.3, top = (box.maxHeight - gridH) / 2 + cell * 0.3;
              Offset at(int n) => Offset(left + ((n - 1) % 10) * (cell + gap), top + ((n - 1) ~/ 10) * (cell + gap));
              final bug = cell * 0.62;
              final land = at(r.target) + Offset(cell - bug * 0.7, -bug * 0.3);
              return Stack(
                key: ValueKey(_deal),
                clipBehavior: Clip.none,
                children: [
                  for (var n = 1; n <= r.cells; n++)
                    Positioned(
                      left: at(n).dx,
                      top: at(n).dy,
                      width: cell,
                      height: cell,
                      child: _square(n, cell),
                    ),
                  // The ladybug flies from the corner to the number she found.
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeInOutBack,
                    left: _solved ? land.dx : left - bug * 0.75,
                    top: _solved ? land.dy : top - bug * 0.75,
                    width: bug,
                    height: bug,
                    child: IgnorePointer(child: Hop(count: _solved ? 1 : 0, child: DEmoji('🐞', size: bug))),
                  ),
                ],
              );
            }),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'hundred.ask',
              label: _solved ? '${r.target} found' : (r.hiding ? 'Find where ${r.target} goes' : 'Find ${r.target}'),
              onSayAgain: _ask,
              children: [DEmoji('🐞', size: 40 * t.scale), SizedBox(width: t.space.xs), DEmoji('🔢', size: 40 * t.scale)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _square(int n, double cell) {
    final r = _round!;
    final hidden = r.hidden.contains(n) && !_shown.contains(n) && !(_solved && n == r.target);
    final inRow = (n - 1) ~/ 10 == r.row;
    final lit = _solved && inRow;
    final rowHint = !_solved && _slips >= 2 && inRow;
    final cellHint = !_solved && _slips >= 3 && n == r.target;
    final found = _solved && n == r.target;
    final radius = BorderRadius.circular(cell * 0.18);
    return DPressable(
      id: 'hundred.cell.$n',
      semanticLabel: hidden ? 'Hidden square' : '$n${found ? ', found' : ''}',
      excludeSemantics: true,
      onTap: () => _tap(n),
      borderRadius: radius,
      child: Wiggle(
        count: _wiggles[n] ?? 0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: found ? const Color(0xFFFFD54F) : (lit ? const Color(0xFFFFF0B3) : (hidden ? const Color(0xFFEDE7F6) : Colors.white)),
            borderRadius: radius,
            border: Border.all(
              color: cellHint ? const Color(0xFFFFB020) : (rowHint ? const Color(0xFFFFC93C) : const Color(0xFFD9D2E9)),
              width: cellHint ? cell * 0.08 : (rowHint ? cell * 0.05 : math.max(1, cell * 0.025)),
            ),
          ),
          child: hidden
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [for (final d in '$n'.split('')) GlyphView(d, height: cell * (n == 100 ? 0.36 : 0.46), color: const Color(0xFF2B2440))],
                ),
        ),
      ),
    );
  }
}
