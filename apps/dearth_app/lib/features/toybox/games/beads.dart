import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'cookies.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Bead Slider (SPEC FR-TOY-03, Appendix B: fives and tens). A counting
/// rack (rekenrek): rows of ten beads, five red and five white, all
/// starting on the right. "Show seven!" A tap or a swipe slides beads
/// across — each change says the total — and the bell checks: right and
/// the rack chimes and the voice names the structure ("Five and two make
/// seven!", "Ten and four make fourteen!"); wrong asks for more or fewer
/// while the beads stay to fix. After two slips a dashed marker shows
/// where to stop. At the top the beads are already across and she reads
/// them from the rack.
class BeadGame extends StatefulWidget {
  const BeadGame(this.c, {super.key});
  final GameController c;

  @override
  State<BeadGame> createState() => BeadGameState();
}

@visibleForTesting
class BeadGameState extends State<BeadGame> with TickerProviderStateMixin {
  BeadRound? _round;

  /// Beads pushed left, one count per row.
  late List<int> _left;

  /// Each row's count before its last slide: the beads between the two
  /// glide across while the slide runs.
  late List<int> _from;
  late List<AnimationController> _slide;
  int _slips = 0, _deal = 0, _bellHops = 0;
  bool _hint = false, _solved = false, _toldBell = false;
  final _tried = <int>{};
  final _wiggles = <int, int>{};
  final _timers = <Timer>[];
  Timer? _idle;

  @visibleForTesting
  BeadRound get debugRound => _round!;

  /// How many beads are across, all rows added.
  @visibleForTesting
  int get debugTotal => _left.fold(0, (a, b) => a + b);

  /// The beads pushed left, top row first.
  @visibleForTesting
  List<int> get debugLeft => List.of(_left);

  @visibleForTesting
  bool get debugHint => _hint;

  @visibleForTesting
  bool get debugSolved => _solved;

  @override
  void initState() {
    super.initState();
    _left = [0, 0];
    _from = [0, 0];
    _slide = [for (var r = 0; r < 2; r++) AnimationController(vsync: this, duration: const Duration(milliseconds: 180))];
    _newRound();
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _idle?.cancel();
    for (final s in _slide) {
      s.dispose();
    }
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
    _idle?.cancel();
    final r = _round = beadRound(widget.c.level, widget.c.random, last: _round);
    _left = [for (var row = 0; row < 2; row++) 0];
    if (r.read) {
      // The beads start across, the top row filling first.
      _left[0] = math.min(r.want, 10);
      _left[1] = math.max(0, r.want - 10);
    }
    _from = List.of(_left);
    for (final s in _slide) {
      s
        ..stop()
        ..value = 1;
    }
    _tried.clear();
    _wiggles.clear();
    _slips = 0;
    _hint = _solved = false;
    _deal++;
    // A beat for the round to land, then the order; the bell's job is
    // explained once a session (Cookie Count's bell clip).
    _after(const Duration(milliseconds: 600), () {
      _sayPrompt();
      if (!_toldBell) {
        _toldBell = true;
        _after(afterVoice(_askClip()), () => widget.c.say(VoiceLine.cookiesBell));
      }
    });
    _waitIdle();
    if (mounted) setState(() {});
  }

  String _askClip() => _round!.read ? VoiceLine.beadsWhich : beadsShowClip(_round!.want);

  void _sayPrompt() => widget.c.say(_askClip());

  /// A long pause asks again. Not a slip.
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 11), () {
      if (!mounted || _solved) return;
      _sayPrompt();
      _waitIdle();
    });
  }

  /// The bead nearest [x] (the row's own coordinates), wherever the beads
  /// sit now.
  int _beadAt(int row, double x, double d) {
    var best = 0;
    for (var i = 1; i < 10; i++) {
      if ((x - _beadX(i, _left[row], d)).abs() < (x - _beadX(best, _left[row], d)).abs()) best = i;
    }
    return best;
  }

  /// Slides row [row]'s beads by the rekenrek rule: a bead to the right
  /// of the finger takes everything left of it across; a bead already
  /// across takes everything from it back.
  void _slideBy(int row, int i) {
    final r = _round!;
    if (r.read || _solved) return;
    final now = i >= _left[row] ? i + 1 : i;
    if (now == _left[row]) return;
    _waitIdle();
    widget.c.sound(Sfx.blip, volume: 0.4);
    setState(() {
      // A slide that's still running finishes at once: the new one starts
      // from where the beads were going.
      _from[row] = _left[row];
      _left[row] = now;
      _slide[row]
        ..stop()
        ..forward(from: 0);
    });
    widget.c.say(numberClip(debugTotal));
  }

  /// The bell: the round's check. Any split across the rows is right.
  void _ring() {
    final r = _round!;
    if (_solved) return;
    _waitIdle();
    widget.c.sound(Sfx.ding, volume: 0.6);
    setState(() => _bellHops++);
    if (debugTotal == r.want) {
      _win();
      return;
    }
    _slips++;
    widget.c.cue();
    widget.c.say(debugTotal < r.want ? VoiceLine.beadsMore : VoiceLine.beadsFewer);
    setState(() => _hint = _slips >= 2);
  }

  /// Read mode: she picks the number for the beads she sees.
  void _pick(int n) {
    final r = _round!;
    if (_solved || _tried.contains(n)) return;
    _waitIdle();
    if (n == r.want) {
      widget.c.sound(Sfx.sparkle);
      _win();
      return;
    }
    _slips++;
    widget.c.cue();
    widget.c.say(numberClip(n));
    setState(() {
      _tried.add(n);
      _wiggles[n] = (_wiggles[n] ?? 0) + 1;
      _hint = _slips >= 2;
    });
  }

  void _win() {
    _idle?.cancel();
    setState(() => _solved = true);
    final r = _round!;
    final yay = beadsYayClip(r.want);
    widget.c.say(yay);
    // A rising chime, the way a rack of beads runs under a hand.
    const notes = [60, 64, 67, 72];
    for (var i = 0; i < notes.length; i++) {
      _after(Duration(milliseconds: 120 * i + 150), () {
        widget.c.sound(Sfx.xylophone, volume: 0.7, rate: math.pow(2, (notes[i] - kXylophoneBaseMidi) / 12).toDouble());
      });
    }
    _after(const Duration(milliseconds: 1200), () => unawaited(widget.c.finishRound(beadResult(_slips), emoji: '🔴')));
    _after(afterVoice(yay, atLeast: const Duration(milliseconds: 3200)), _newRound);
  }

  String _askLabel() {
    final r = _round!;
    if (r.read) return _solved ? 'Yay! ${r.want}' : 'How many beads?';
    return _solved ? 'Yay! ${r.want}' : 'Show ${r.want}';
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    return Backdrop(
      top: const Color(0xFFFFF3E3),
      bottom: const Color(0xFFEAF2FF),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final wide = box.maxWidth > box.maxHeight;
              final dd = math.max(72 * t.scale, math.min(box.maxHeight * 0.24, 150 * t.scale));
              // Wide: the bell (or the numbers) stands beside the rack.
              final room = wide ? box.maxWidth - (r.read ? box.maxWidth * 0.3 : dd) - 32 * t.scale : box.maxWidth;
              final rackW = math.min(room * 0.96, 1150 * t.scale);
              final d = rackW / kRackBeads;
              final rowH = d * 1.6;
              final rows = [for (var row = 0; row < r.rows; row++) row];
              final rackH = r.rows * rowH + (r.rows - 1) * d * 0.4;
              Widget? beside;
              if (r.read) {
                final tile = math.min(math.min((wide ? box.maxHeight : box.maxHeight - rackH) / 3.6, box.maxWidth * 0.3), 300 * t.scale);
                beside = wide
                    ? TileRows(per: 1, children: [for (final n in r.choices) _choice(context, n, tile)])
                    : TileRows(per: 3, children: [for (final n in r.choices) _choice(context, n, math.min(tile, (box.maxWidth - 24) / 3.4))]);
              } else {
                beside = DPressable(
                  id: 'beads.bell',
                  semanticLabel: 'Bell',
                  excludeSemantics: true,
                  onTap: _ring,
                  borderRadius: BorderRadius.circular(dd / 2),
                  child: Hop(count: _bellHops, child: SizedBox.square(dimension: dd, child: const RepaintBoundary(child: CustomPaint(painter: BellPainter(), size: Size.infinite)))),
                );
              }
              final rack = Column(
                key: ValueKey(_deal),
                mainAxisSize: MainAxisSize.min,
                children: [for (final row in rows) _row(context, row, rackW, d, rowH)],
              );
              // Wide: the rack centered, the bell (or the numbers) beside
              // it. Tall: the rack on top, it under.
              return wide
                  ? Row(children: [Expanded(child: Center(child: rack)), beside])
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: [Center(child: rack), SizedBox(height: d * 0.8), beside]);
            }),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'beads.ask',
              label: _askLabel(),
              onSayAgain: _sayPrompt,
              // Reading the rack, the number is hers to find: a bead, not
              // the answer.
              children: r.read && !_solved
                  ? [SizedBox(width: 72 * t.scale, height: 44 * t.scale, child: const CustomPaint(painter: _BeadsIconPainter()))]
                  : [for (final digit in '${r.want}'.split('')) GlyphView(digit, height: 52 * t.scale, color: const Color(0xFF6B4FB8))],
            ),
          ),
        ],
      ),
    );
  }

  /// One rack row: the frame, the beads, and over them the boxes she taps
  /// and drags.
  Widget _row(BuildContext context, int row, double rackW, double d, double rowH) {
    final box = Rect.fromLTWH(0, 0, rackW, rowH);
    final left = _left[row];
    Widget beadBox(int i) {
      final x = _beadX(i, left, d);
      final side = math.max(d, 44 * DTheme.of(context).scale);
      return Positioned.fromRect(
        rect: Rect.fromCenter(center: Offset(x, rowH / 2), width: side, height: side),
        child: tid(
          'beads.bead.$row.$i',
          Semantics(
            label: 'Bead ${i + 1}, ${i < 5 ? 'red' : 'white'}, ${i < left ? 'left' : 'right'}',
            excludeSemantics: true,
            onTap: () => _slideBy(row, i),
            child: const SizedBox.expand(),
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(vertical: d * 0.2),
      child: SizedBox(
        width: rackW,
        height: rowH,
        child: Stack(
          children: [
            Positioned.fromRect(
              rect: box,
              child: RepaintBoundary(
                child: CustomPaint(
                  size: box.size,
                  painter: _RowPainter(left: _left[row], from: _from[row], slide: _slide[row], hintAt: _hintStop(row)),
                ),
              ),
            ),
            // The row's lasting label, on a node of its own.
            Positioned(
              left: 0,
              top: 0,
              width: 1,
              height: 1,
              child: tid(
                'beads.row.$row',
                Semantics(
                  label: '${row == 0 ? 'Top' : 'Bottom'} row: $left ${left == 1 ? 'bead' : 'beads'} across',
                  excludeSemantics: true,
                  child: const SizedBox(width: 1, height: 1),
                ),
              ),
            ),
            Listener(
              behavior: HitTestBehavior.opaque,
              // A touch moves the bead under it at once, so a swipe that
              // starts on a bead pushes it (and its neighbors) across.
              onPointerDown: (e) => _slideBy(row, _beadAt(row, e.localPosition.dx, d)),
              child: SizedBox.expand(child: Stack(children: [for (var i = 0; i < 10; i++) beadBox(i)])),
            ),
          ],
        ),
      ),
    );
  }

  /// Where the hint's dashed marker sits in row [row]: after the wanted
  /// beads on the top row, or after the rest on the bottom.
  int _hintStop(int row) {
    final r = _round!;
    if (!_hint || r.read) return -1;
    if (r.rows == 1) return r.want;
    return row == 0 ? 10 : r.want - 10;
  }

  Widget _choice(BuildContext context, int n, double size) {
    return Padding(
      padding: EdgeInsets.all(size * 0.06),
      child: PictureTile(
        id: 'beads.choice.$n',
        label: '$n',
        size: size,
        onTap: () => _pick(n),
        tried: _tried.contains(n),
        hint: _hint && n == _round!.want && !_solved,
        wiggles: _wiggles[n] ?? 0,
        hops: _solved && n == _round!.want ? 1 : 0,
        child: Row(mainAxisSize: MainAxisSize.min, children: [for (final digit in '$n'.split('')) GlyphView(digit, height: size * 0.5, color: const Color(0xFF6B4FB8))]),
      ),
    );
  }
}

/// A rack row is this many beads wide: ten beads, a four-bead gap to slide
/// across, and the frame's ends.
const double kRackBeads = 16;

/// Where bead [i] (0–9) sits, in bead widths [d] from the row's left
/// edge, with [left] beads across: packed against the left end when it's
/// across, against the right end when not, so the gap shows between.
double _beadX(int i, int left, double d) => (i < left ? 1.5 + i : kRackBeads - 1.5 - (9 - i)) * d;

/// One rack row: a wooden frame, a metal rod, and ten beads — five red,
/// five white — the ones across on the left. While a slide runs, the beads
/// between [from] and [left] glide to their new end. A dashed marker shows
/// where to stop after two slips.
class _RowPainter extends CustomPainter {
  _RowPainter({required this.left, required this.from, required this.slide, required this.hintAt}) : super(repaint: slide);

  final int left;
  final int from;

  /// The row's slide: painted count = from → left.
  final Animation<double> slide;
  final int hintAt;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final d = w / kRackBeads;
    final k = slide.isCompleted ? 1.0 : Curves.easeOutCubic.transform(slide.value);
    const wood = Color(0xFFB7814C);
    final ink = Color.lerp(wood, const Color(0xFF2B2440), 0.45)!;
    canvas
      ..drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(d * 0.5)), Paint()..color = wood)
      ..drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(d * 0.5)),
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, d * 0.12),
      )
      // The metal rod.
      ..drawLine(Offset(d * 0.8, h / 2), Offset(w - d * 0.8, h / 2), Paint()
        ..color = const Color(0xFF9AA0A8)
        ..strokeWidth = d * 0.16
        ..strokeCap = StrokeCap.round);
    for (var i = 0; i < 10; i++) {
      final x = ui.lerpDouble(_beadX(i, from, d), _beadX(i, left, d), k)!;
      final c = Offset(x, h / 2);
      final r = d * 0.46;
      final red = i < 5;
      canvas.drawCircle(c, r, Paint()..color = red ? const Color(0xFFE5484D) : const Color(0xFFF7F7F7));
      if (!red) {
        canvas.drawCircle(c, r, Paint()
          ..color = const Color(0xFFB9BEC7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, d * 0.05));
      }
      canvas.drawCircle(c + Offset(-r * 0.3, -r * 0.3), r * 0.16, Paint()..color = (red ? Colors.white : const Color(0xFFD9DDE3)).withValues(alpha: 0.9));
    }
    if (hintAt > 0 && hintAt <= 10) {
      final x = _beadX(hintAt - 1, 10, d) + d / 2;
      final dash = Paint()
        ..color = const Color(0xFF6B4FB8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, d * 0.1)
        ..strokeCap = StrokeCap.round;
      const n = 5;
      for (var k = 0; k < n; k++) {
        final a = k * 2 * math.pi / n;
        canvas.drawArc(Rect.fromCircle(center: Offset(x, h / 2), radius: d * 0.3), a, math.pi / n, false, dash);
      }
    }
  }

  @override
  bool shouldRepaint(_RowPainter old) => old.left != left || old.from != from || old.hintAt != hintAt;
}

/// A red bead and a white one on a rod, for the pill while she reads the
/// rack.
class _BeadsIconPainter extends CustomPainter {
  const _BeadsIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height * 0.36;
    final y = size.height / 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), Paint()
      ..color = const Color(0xFF9AA0A8)
      ..strokeWidth = size.height * 0.1
      ..strokeCap = StrokeCap.round);
    for (final (x, red) in [(size.width * 0.32, true), (size.width * 0.68, false)]) {
      final c = Offset(x, y);
      canvas.drawCircle(c, r, Paint()..color = red ? const Color(0xFFE5484D) : const Color(0xFFF7F7F7));
      if (!red) {
        canvas.drawCircle(c, r, Paint()
          ..color = const Color(0xFFB9BEC7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, r * 0.1));
      }
      canvas.drawCircle(c + Offset(-r * 0.3, -r * 0.3), r * 0.16, Paint()..color = (red ? Colors.white : const Color(0xFFD9DDE3)).withValues(alpha: 0.9));
    }
  }

  @override
  bool shouldRepaint(_BeadsIconPainter old) => false;
}
