import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';

const List<String> _flowers = ['🌷', '🌻', '🌼', '🌸', '🌺'];

/// Each count's note, up a major scale from the blip's C: counting has a
/// tune, and ten sounds higher than three.
const List<int> _scale = [0, 2, 4, 5, 7, 9, 11, 12, 14, 16];

/// Where 1–6 flowers stand in a flash round: dice faces, the patterns eyes
/// learn to see at a glance (columns and rows, 0…2).
const List<List<(int, int)>> _dice = [
  [(1, 1)],
  [(0, 0), (2, 2)],
  [(0, 0), (1, 1), (2, 2)],
  [(0, 0), (2, 0), (0, 2), (2, 2)],
  [(0, 0), (2, 0), (1, 1), (0, 2), (2, 2)],
  [(0, 0), (2, 0), (0, 1), (2, 1), (0, 2), (2, 2)],
];

enum _Phase { counting, flash, asking, done }

/// Counting Garden (SPEC FR-TOY-02, Appendix B: number sense). Buds wait in
/// a garden bed; each tap makes one bloom with a rising note and its number,
/// so counting has a sound and a shape. Then "how many?": she picks the
/// answer from numbers drawn with their dots. The top level only flashes
/// the flowers (subitizing). A wrong answer gets a soft "uh-uh" and another
/// look; after two, the right one glows.
class CountingGame extends StatefulWidget {
  const CountingGame(this.c, {super.key});
  final GameController c;

  @override
  State<CountingGame> createState() => CountingGameState();
}

@visibleForTesting
class CountingGameState extends State<CountingGame> {
  late CountingRound _round;
  late String _flower;
  final _bloomed = <int>[];
  final _tried = <int>{};
  _Phase _phase = _Phase.counting;

  /// Flash rounds: whether the flowers are showing.
  bool _showing = false;
  int _slips = 0, _deal = 0;
  Timer? _timer;

  @visibleForTesting
  int get debugCount => _round.count;

  @visibleForTesting
  bool get debugShowing => _showing;

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _newRound() {
    _timer?.cancel();
    final rng = widget.c.random;
    _round = countingRound(widget.c.level, rng);
    _flower = _flowers[rng.nextInt(_flowers.length)];
    _bloomed.clear();
    _tried.clear();
    _slips = 0;
    _deal++;
    if (_round.flash) {
      _phase = _Phase.flash;
      _flashThen();
    } else {
      _phase = _Phase.counting;
      _showing = false;
    }
    if (mounted) setState(() {});
  }

  /// Shows the flowers for a moment, then asks.
  void _flashThen() {
    if (mounted) setState(() => _showing = true);
    widget.c.sound(Sfx.sparkle, volume: 0.6);
    _timer = Timer(const Duration(milliseconds: 1700), () {
      if (!mounted) return;
      setState(() {
        _showing = false;
        _phase = _Phase.asking;
      });
    });
  }

  void _note(int n) => widget.c.sound(Sfx.blip, rate: math.pow(2, _scale[(n - 1).clamp(0, _scale.length - 1)] / 12).toDouble());

  void _tapBud(int i) {
    if (_phase != _Phase.counting || _bloomed.contains(i)) return;
    setState(() => _bloomed.add(i));
    _note(_bloomed.length);
    if (_bloomed.length == _round.count) {
      _timer = Timer(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _phase = _Phase.asking);
      });
    }
  }

  void _answer(int n) {
    if (_phase != _Phase.asking || _tried.contains(n)) return;
    if (n != _round.count) {
      _slips++;
      widget.c.cue();
      setState(() => _tried.add(n));
      // Another look at a flash; counted flowers are still there to recount.
      if (_round.flash) {
        setState(() => _phase = _Phase.flash);
        _flashThen();
      }
      return;
    }
    setState(() {
      _phase = _Phase.done;
      _showing = true;
    });
    unawaited(widget.c.finishRound(countingResult(_slips), emoji: _flower));
    _timer = Timer(const Duration(milliseconds: 2800), _newRound);
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final asking = _phase == _Phase.asking;
    return Stack(
      fit: StackFit.expand,
      children: [
        const RepaintBoundary(child: CustomPaint(painter: _GardenPainter())),
        SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(t.space.lg, 96 * t.scale, t.space.lg, t.space.lg),
            child: LayoutBuilder(builder: (context, box) {
              final wide = box.maxWidth > box.maxHeight;
              final bed = _Bed(
                key: ValueKey(_deal),
                round: _round,
                flower: _flower,
                bloomed: _bloomed,
                // Counted flowers stay open; a flash shows them only for a moment.
                open: (i) => _round.flash ? (_showing || _phase == _Phase.done) : _bloomed.contains(i),
                covered: _round.flash && !_showing && _phase != _Phase.done,
                dancing: _phase == _Phase.done,
                onTap: _tapBud,
              );
              final choices = _Choices(
                choices: _round.choices,
                tried: _tried,
                hint: _slips >= 2 ? _round.count : null,
                onTap: _answer,
                vertical: wide,
              );
              return wide
                  ? Row(children: [Expanded(child: bed), if (asking) ...[SizedBox(width: t.space.xl), choices]])
                  : Column(children: [Expanded(child: bed), if (asking) ...[SizedBox(height: t.space.xl), choices]]);
            }),
          ),
        ),
        if (asking)
          Positioned(
            top: t.space.md,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Center(
                child: tid('counting.ask', Semantics(label: 'How many?', excludeSemantics: true, child: GamePill(children: [DEmoji(_flower, size: 44 * t.scale), SizedBox(width: t.space.xs), DEmoji('❓', size: 44 * t.scale)]))),
              ),
            ),
          ),
      ],
    );
  }
}

/// The garden bed: buds that bloom, each with its number.
class _Bed extends StatelessWidget {
  const _Bed({super.key, required this.round, required this.flower, required this.bloomed, required this.open, required this.covered, required this.dancing, required this.onTap});
  final CountingRound round;
  final String flower;
  final List<int> bloomed;
  final bool Function(int) open;
  final bool covered, dancing;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final n = round.count;
        // Counting: one row, or two like a ten-frame. A flash: dice faces.
        final List<Offset> spots;
        final double cell;
        if (round.flash) {
          cell = math.min(box.maxWidth, box.maxHeight) / 3.2;
          final origin = Offset(box.maxWidth / 2 - cell, box.maxHeight / 2 - cell);
          spots = [for (final (x, y) in _dice[(n - 1).clamp(0, 5)]) origin + Offset(x * cell, y * cell)];
        } else {
          final rows = n > 5 ? 2 : 1;
          // A few buds are big; a row of five still fits.
          cell = math.min(math.min(box.maxWidth / (math.min(n, 5) + 0.8), box.maxHeight / (rows + 0.8)), 300 * DTheme.of(context).scale);
          spots = [
            for (var i = 0; i < n; i++)
              Offset(
                box.maxWidth / 2 + ((i % 5) - ((i ~/ 5 == rows - 1 ? n - (rows - 1) * 5 : 5) - 1) / 2) * cell,
                box.maxHeight / 2 + ((i ~/ 5) - (rows - 1) / 2) * cell * 1.1,
              ),
          ];
        }
        final size = cell * 0.82;
        return Stack(
          children: [
            Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _SoilPainter(spots: spots, cell: cell)))),
            for (final (i, p) in spots.indexed)
              Positioned(
                left: p.dx - size / 2,
                top: p.dy - size / 2,
                child: _Plant(
                  index: i,
                  emoji: covered ? '🌿' : (open(i) ? flower : '🌱'),
                  number: round.flash ? null : (bloomed.contains(i) ? bloomed.indexOf(i) + 1 : null),
                  size: size,
                  dancing: dancing,
                  onTap: () => onTap(i),
                ),
              ),
          ],
        );
      });
}

class _Plant extends StatelessWidget {
  const _Plant({required this.index, required this.emoji, required this.number, required this.size, required this.dancing, required this.onTap});
  final int index;
  final String emoji;
  final int? number;
  final double size;
  final bool dancing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final bloom = emoji != '🌱' && emoji != '🌿';
    return DPressable(
      id: 'counting.bud.$index',
      semanticLabel: number != null ? 'Flower $number' : (bloom ? 'Flower' : 'Bud'),
      excludeSemantics: true,
      onTap: onTap,
      pressedScale: 0.92,
      borderRadius: BorderRadius.circular(size),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // A pop as it opens; a sway when the round is won.
            TweenAnimationBuilder<double>(
              key: ValueKey('$emoji$dancing'),
              tween: Tween(begin: bloom ? 0 : 1, end: 1),
              duration: Duration(milliseconds: dancing ? 1400 : 420),
              curve: dancing ? Curves.linear : Curves.elasticOut,
              builder: (context, k, child) => Transform.rotate(
                angle: dancing ? math.sin(k * math.pi * 4) * 0.18 * (1 - k) : 0,
                child: Transform.scale(scale: dancing ? 1 : 0.4 + 0.6 * k, child: child),
              ),
              child: DEmoji(emoji, size: bloom ? size : size * 0.62),
            ),
            if (number != null)
              Positioned(
                top: -size * 0.18,
                child: Container(
                  width: size * 0.42,
                  height: size * 0.42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: t.elevation.e1),
                  child: Text('$number', style: t.text.kidTitle.copyWith(fontSize: size * 0.26, height: 1, color: const Color(0xFF2F3A1E))),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The answers: big numbers with their dots, two rows of five like a
/// ten-frame.
class _Choices extends StatelessWidget {
  const _Choices({required this.choices, required this.tried, required this.hint, required this.onTap, required this.vertical});
  final List<int> choices;
  final Set<int> tried;
  final int? hint;
  final ValueChanged<int> onTap;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final size = 150 * t.scale;
    final buttons = [
      for (final n in choices)
        Padding(
          padding: EdgeInsets.all(t.space.sm),
          child: DPressable(
            id: 'counting.choice.$n',
            semanticLabel: '$n',
            excludeSemantics: true,
            onTap: () => onTap(n),
            borderRadius: BorderRadius.circular(size * 0.24),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: size,
              height: size,
              decoration: BoxDecoration(
                // A number already tried fades back; the hint glows.
                color: tried.contains(n) ? const Color(0xFFE9E4D8) : Colors.white,
                borderRadius: BorderRadius.circular(size * 0.24),
                border: Border.all(color: hint == n ? const Color(0xFFFFC93C) : const Color(0xFFB9DFA0), width: hint == n ? 8 : 4),
                // A solid halo, not a blur: blurs are too slow to animate on a frame.
                // Always first, so only the halo animates (no blur change).
                boxShadow: [BoxShadow(color: hint == n ? const Color(0x88FFD54F) : const Color(0x00FFD54F), spreadRadius: hint == n ? 12 : 0), ...t.elevation.e1],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$n', style: t.text.kidDisplay.copyWith(fontSize: size * 0.42, height: 1, color: tried.contains(n) ? const Color(0xFFB0A894) : const Color(0xFF2F3A1E))),
                  SizedBox(height: size * 0.05),
                  _Dots(n: n, size: size * 0.11, color: tried.contains(n) ? const Color(0xFFCFC7B4) : const Color(0xFFE86A92)),
                ],
              ),
            ),
          ),
        ),
    ];
    // Shrinks to fit a phone rather than overflow.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: vertical ? Column(mainAxisSize: MainAxisSize.min, children: buttons) : Row(mainAxisSize: MainAxisSize.min, children: buttons),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.n, required this.size, required this.color});
  final int n;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    Widget row(int k) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [for (var i = 0; i < k; i++) Container(width: size, height: size, margin: EdgeInsets.all(size * 0.12), decoration: BoxDecoration(color: color, shape: BoxShape.circle))],
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [row(math.min(n, 5)), if (n > 5) row(n - 5)]);
  }
}

/// The sky, the sun and a lawn. Painted once.
class _GardenPainter extends CustomPainter {
  const _GardenPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final sky = Offset.zero & Size(w, h * 0.42);
    canvas
      ..drawRect(sky, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF9AD8FF), Color(0xFFDDF2FF)]).createShader(sky))
      ..drawCircle(Offset(w * 0.88, h * 0.12), size.shortestSide * 0.07, Paint()..color = const Color(0xFFFFD54F));
    final lawn = Rect.fromLTWH(0, h * 0.36, w, h * 0.64);
    final hill = Path()
      ..moveTo(0, h * 0.42)
      ..quadraticBezierTo(w * 0.3, h * 0.33, w * 0.6, h * 0.4)
      ..quadraticBezierTo(w * 0.85, h * 0.45, w, h * 0.38)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(hill, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF9FD86F), Color(0xFF6DBB4C)]).createShader(lawn));
  }

  @override
  bool shouldRepaint(_GardenPainter old) => false;
}

/// A mound of soil under each plant.
class _SoilPainter extends CustomPainter {
  const _SoilPainter({required this.spots, required this.cell});
  final List<Offset> spots;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    final soil = Paint()..color = const Color(0xFF8A5A36);
    final top = Paint()..color = const Color(0xFFA06C44);
    for (final p in spots) {
      final r = Rect.fromCenter(center: p + Offset(0, cell * 0.36), width: cell * 0.78, height: cell * 0.26);
      canvas
        ..drawOval(r, soil)
        ..drawOval(r.deflate(cell * 0.04).shift(Offset(0, -cell * 0.02)), top);
    }
  }

  @override
  bool shouldRepaint(_SoilPainter old) => old.cell != cell || old.spots.length != spots.length || (spots.isNotEmpty && old.spots.first != spots.first);
}
