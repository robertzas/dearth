import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'shapes.dart';

/// Odd One Out (SPEC FR-TOY-03, Appendix B: categorizing). Four pictures,
/// one doesn't belong: by color first (a banana among red fruit), then by
/// shape, then by kind (an apple among animals), then by what things are for
/// (a drum among things that fly). A wrong tap wiggles; after two, the odd
/// one glows.
class OddOneGame extends StatefulWidget {
  const OddOneGame(this.c, {super.key});
  final GameController c;

  @override
  State<OddOneGame> createState() => OddOneGameState();
}

@visibleForTesting
class OddOneGameState extends State<OddOneGame> {
  late OddRound _round;
  final _tried = <int>{};
  final _wiggles = <int, int>{};
  int _slips = 0, _deal = 0;
  bool _solved = false;
  Timer? _next;

  @visibleForTesting
  OddRound get debugRound => _round;

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
    _round = oddOneOut(widget.c.level, widget.c.random);
    _tried.clear();
    _slips = 0;
    _solved = false;
    _deal++;
    if (mounted) setState(() {});
  }

  void _pick(int i) {
    if (_solved || _tried.contains(i)) return;
    if (i != _round.odd) {
      _slips++;
      widget.c.cue();
      setState(() {
        _tried.add(i);
        _wiggles[i] = (_wiggles[i] ?? 0) + 1;
      });
      return;
    }
    widget.c.sound(Sfx.sparkle);
    setState(() => _solved = true);
    final odd = _round.items[i];
    unawaited(widget.c.finishRound(countingResult(_slips), emoji: odd.emoji ?? '🔍'));
    _next = Timer(const Duration(milliseconds: 2400), _newRound);
  }

  static String _label(OddItem i) => i.emoji ?? i.shape!.name;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final colors = kShapeColors.values.toList();
    return Backdrop(
      top: const Color(0xFFE8F6FF),
      bottom: const Color(0xFFF2FFF0),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 120,
            child: LayoutBuilder(builder: (context, box) {
              final wide = box.maxWidth > box.maxHeight;
              final per = wide ? 4 : 2;
              final rows = 4 ~/ per;
              final size = math.min(math.min(box.maxWidth / per * 0.82, box.maxHeight / rows * 0.82), 260 * t.scale);
              Widget tile(int i) {
                final item = _round.items[i];
                return Padding(
                  padding: EdgeInsets.all(size * 0.06),
                  child: PictureTile(
                    id: 'oddone.item.$i',
                    label: _label(item),
                    size: size,
                    tried: _tried.contains(i),
                    hint: _slips >= 2 && i == _round.odd && !_solved,
                    wiggles: _wiggles[i] ?? 0,
                    hops: _solved && i == _round.odd ? 1 : 0,
                    onTap: () => _pick(i),
                    child: item.emoji != null ? DEmoji(item.emoji!, size: size * 0.62) : ToyShapeView(item.shape!, size: size * 0.62, color: colors[item.color % colors.length]),
                  ),
                );
              }

              return Center(
                key: ValueKey(_deal),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var r = 0; r < rows; r++) Row(mainAxisSize: MainAxisSize.min, children: [for (var c = 0; c < per; c++) tile(r * per + c)]),
                  ],
                ),
              );
            }),
          ),
          Positioned(
            top: t.space.md,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Center(
                child: tid(
                  'oddone.ask',
                  Semantics(
                    label: _solved ? 'You found it!' : 'Which one is different?',
                    excludeSemantics: true,
                    child: GamePill(children: [DEmoji('🔍', size: 44 * t.scale), SizedBox(width: t.space.xs), DEmoji('❓', size: 44 * t.scale)]),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
