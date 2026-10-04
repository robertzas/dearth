import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';

/// Small to Big (SPEC FR-TOY-03 "Size Order", Appendix B: seriation). The
/// same picture in three to six sizes, mixed up on a shelf. She taps the
/// smallest first; each one hops down into a line, smallest to biggest, on a
/// rising note. A wrong one wiggles; after two, the right one glows.
class SizesGame extends StatefulWidget {
  const SizesGame(this.c, {super.key});
  final GameController c;

  @override
  State<SizesGame> createState() => SizesGameState();
}

@visibleForTesting
class SizesGameState extends State<SizesGame> {
  late SizeRound _round;

  /// Indices of the pictures in the line, in the order they joined it.
  final _line = <int>[];
  final _wiggles = <int, int>{};
  int _slips = 0, _deal = 0;
  Timer? _next;

  @visibleForTesting
  SizeRound get debugRound => _round;

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
    _round = sizeRound(widget.c.level, widget.c.random);
    _line.clear();
    _slips = 0;
    _deal++;
    if (mounted) setState(() {});
  }

  void _tap(int i) {
    if (_line.contains(i) || _line.length == _round.scales.length) return;
    final next = _round.order[_line.length];
    if (i != next) {
      _slips++;
      widget.c.cue();
      setState(() => _wiggles[i] = (_wiggles[i] ?? 0) + 1);
      return;
    }
    // Up the scale, one note per size.
    widget.c.sound(Sfx.blip, rate: math.pow(2, const [0, 2, 4, 5, 7, 9][_line.length.clamp(0, 5)] / 12).toDouble());
    setState(() => _line.add(i));
    if (_line.length == _round.scales.length) {
      unawaited(widget.c.finishRound(expansionResult(_slips, size: _round.scales.length), emoji: _round.emoji));
      _next = Timer(const Duration(milliseconds: 2600), _newRound);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _round;
    final n = r.scales.length;
    return Backdrop(
      top: const Color(0xFFE7F4FF),
      bottom: const Color(0xFFFFF0DC),
      child: PlayArea(
        child: LayoutBuilder(builder: (context, box) {
          final big = math.min(box.maxWidth / (n + 0.6), box.maxHeight * 0.38);
          final shelfY = box.maxHeight * 0.42, lineY = box.maxHeight * 0.95;
          double x(int k) => box.maxWidth * (k + 0.5) / n;
          final placedAt = {for (final (k, i) in _line.indexed) i: k};
          return Stack(
            key: ValueKey(_deal),
            clipBehavior: Clip.none,
            children: [
              // The shelf, and the line's places from small to big.
              Positioned(left: 0, right: 0, top: shelfY, height: 10, child: const DecoratedBox(decoration: BoxDecoration(color: Color(0xFFC9A27A), borderRadius: BorderRadius.all(Radius.circular(5))))),
              for (var k = 0; k < n; k++)
                Positioned(
                  left: x(k) - big * 0.5,
                  top: lineY - big,
                  width: big,
                  height: big,
                  child: tid(
                    'sizes.slot.$k',
                    Semantics(
                      label: 'Place ${k + 1}',
                      excludeSemantics: true,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: big * r.scales[r.order[k]] * 0.8,
                          height: big * r.scales[r.order[k]] * 0.8,
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0x33000000), width: 3)),
                        ),
                      ),
                    ),
                  ),
                ),
              for (var i = 0; i < n; i++)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutBack,
                  left: (placedAt.containsKey(i) ? x(placedAt[i]!) : x(i)) - big / 2,
                  top: (placedAt.containsKey(i) ? lineY : shelfY) - big,
                  width: big,
                  height: big,
                  child: DPressable(
                    id: 'sizes.item.$i',
                    semanticLabel: placedAt.containsKey(i) ? 'In the line' : '${(r.scales[i] * 100).round()}%',
                    excludeSemantics: true,
                    onTap: () => _tap(i),
                    pressedScale: 0.94,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Wiggle(
                        count: _wiggles[i] ?? 0,
                        child: _Glow(
                          on: _slips >= 2 && !placedAt.containsKey(i) && _line.length < n && r.order[_line.length] == i,
                          child: DEmoji(r.emoji, size: big * r.scales[i]),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }
}

/// A soft golden halo behind the one to tap next (a hint).
class _Glow extends StatelessWidget {
  const _Glow({required this.on, required this.child});
  final bool on;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(shape: BoxShape.circle, color: on ? const Color(0x66FFD54F) : const Color(0x00FFD54F)),
        child: child,
      );
}
