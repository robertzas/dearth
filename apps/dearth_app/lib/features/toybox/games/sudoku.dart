import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';

/// Picture Sudoku (SPEC FR-TOY-03, Appendix B: logic). A 4 × 4 board of
/// fruit where every row, column and corner square holds each fruit once,
/// with one to six empty places. She taps an empty place (the first one is
/// chosen for her) and then the fruit that belongs; a wrong fruit wiggles.
class SudokuGame extends StatefulWidget {
  const SudokuGame(this.c, {super.key});
  final GameController c;

  @override
  State<SudokuGame> createState() => SudokuGameState();
}

@visibleForTesting
class SudokuGameState extends State<SudokuGame> {
  late SudokuRound _round;
  final _filled = <int>{};
  final _wiggles = <int, int>{};
  int? _chosen;
  int _slips = 0, _deal = 0;
  Timer? _next;

  @visibleForTesting
  SudokuRound get debugRound => _round;

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
    _round = sudokuRound(widget.c.level, widget.c.random);
    _filled.clear();
    _slips = 0;
    _deal++;
    _chosen = _open.firstOrNull;
    if (mounted) setState(() {});
  }

  List<int> get _open => [for (final i in _round.blanks.toList()..sort()) if (!_filled.contains(i)) i];

  void _choose(int cell) {
    if (!_round.blanks.contains(cell) || _filled.contains(cell)) return;
    widget.c.sound(Sfx.tap, volume: 0.5);
    setState(() => _chosen = cell);
  }

  void _place(int fruit) {
    final cell = _chosen ?? _open.firstOrNull;
    if (cell == null) return;
    if (_round.solution[cell] != fruit) {
      _slips++;
      widget.c.cue();
      setState(() => _wiggles[fruit] = (_wiggles[fruit] ?? 0) + 1);
      return;
    }
    widget.c.sound(Sfx.snap);
    setState(() {
      _filled.add(cell);
      _chosen = _open.firstOrNull;
    });
    if (_open.isEmpty) {
      unawaited(widget.c.finishRound(expansionResult(_slips, size: _round.blanks.length + 2), emoji: kSudokuFruit[fruit]));
      _next = Timer(const Duration(milliseconds: 2600), _newRound);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Backdrop(
      top: const Color(0xFFFFF4E0),
      bottom: const Color(0xFFFFE4EC),
      child: PlayArea(
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth > box.maxHeight;
          final board = math.min(wide ? math.min(box.maxHeight, box.maxWidth * 0.62) : math.min(box.maxWidth, box.maxHeight * 0.66), 760 * t.scale);
          final button = math.min(board / 4.4, 150 * t.scale);
          final next = _chosen == null ? null : _round.solution[_chosen!];
          final fruits = [
            for (var k = 0; k < 4; k++)
              Padding(
                padding: EdgeInsets.all(button * 0.1),
                child: PictureTile(
                  id: 'sudoku.fruit.$k',
                  label: kSudokuFruit[k],
                  size: button,
                  hint: _slips >= 2 && k == next,
                  wiggles: _wiggles[k] ?? 0,
                  onTap: () => _place(k),
                  child: DEmoji(kSudokuFruit[k], size: button * 0.66),
                ),
              ),
          ];
          final grid = SizedBox.square(dimension: board, child: _board(board));
          return Center(
            child: wide
                ? Row(mainAxisSize: MainAxisSize.min, children: [grid, SizedBox(width: t.space.xl), Column(mainAxisSize: MainAxisSize.min, children: fruits)])
                : Column(mainAxisSize: MainAxisSize.min, children: [grid, SizedBox(height: t.space.xl), Row(mainAxisSize: MainAxisSize.min, children: fruits)]),
          );
        }),
      ),
    );
  }

  Widget _board(double board) {
    final cell = board / 4;
    return Container(
      key: ValueKey(_deal),
      decoration: BoxDecoration(color: const Color(0xFF7A5C46), borderRadius: BorderRadius.circular(cell * 0.18)),
      padding: EdgeInsets.all(cell * 0.06),
      child: Column(
        children: [
          for (var r = 0; r < 4; r++)
            Expanded(
              child: Row(
                children: [
                  for (var c = 0; c < 4; c++)
                    Expanded(
                      child: Padding(
                        // Wider gaps between the corner squares.
                        padding: EdgeInsets.fromLTRB(c == 2 ? cell * 0.05 : cell * 0.015, r == 2 ? cell * 0.05 : cell * 0.015, c == 1 ? cell * 0.05 : cell * 0.015, r == 1 ? cell * 0.05 : cell * 0.015),
                        child: _cell(r * 4 + c, cell),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(int i, double cell) {
    final blank = _round.blanks.contains(i), filled = _filled.contains(i), chosen = _chosen == i;
    final fruit = kSudokuFruit[_round.solution[i]];
    final shows = !blank || filled;
    return DPressable(
      id: 'sudoku.cell.$i',
      semanticLabel: shows ? fruit : (chosen ? 'Empty, chosen' : 'Empty'),
      excludeSemantics: true,
      onTap: () => _choose(i),
      pressedScale: 0.96,
      borderRadius: BorderRadius.circular(cell * 0.14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: blank && !filled ? (chosen ? const Color(0xFFFFF3C4) : const Color(0xFFFFFBF2)) : const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(cell * 0.14),
          border: Border.all(color: chosen ? const Color(0xFFF2B33D) : const Color(0x00000000), width: cell * 0.05),
        ),
        alignment: Alignment.center,
        child: shows ? (filled ? Hop(count: 1, child: DEmoji(fruit, size: cell * 0.62)) : DEmoji(fruit, size: cell * 0.62)) : DEmoji('❔', size: cell * 0.4),
      ),
    );
  }
}
