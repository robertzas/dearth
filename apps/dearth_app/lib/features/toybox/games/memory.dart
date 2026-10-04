import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';

const Color _hue = Color(0xFF7067E8);
const Color _matchedRing = Color(0xFF4CC46A);

/// Memory Match (SPEC FR-TOY-02, Appendix B: working memory). The cards lie
/// face down and she turns two at a time. A pair stays up with a sparkle; two
/// that differ just turn back over, so nothing is ever "wrong". The first
/// levels show every face for a moment before the cards turn.
class MemoryGame extends StatefulWidget {
  const MemoryGame(this.c, {super.key});
  final GameController c;

  @override
  State<MemoryGame> createState() => MemoryGameState();
}

@visibleForTesting
class MemoryGameState extends State<MemoryGame> {
  List<String> _deck = const [];
  final _up = <int>[];
  final _matched = <int>{};
  int _misses = 0, _deal = 0;
  bool _peeking = false;

  /// Two different faces showing, about to turn back.
  bool _differ = false;
  Timer? _timer;

  /// The faces in board order, for tests.
  @visibleForTesting
  List<String> get debugDeck => _deck;

  @visibleForTesting
  bool get debugPeeking => _peeking;

  @override
  void initState() {
    super.initState();
    _newBoard();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _newBoard() {
    _timer?.cancel();
    final level = widget.c.level;
    _deck = memoryDeck(level, widget.c.random);
    _deal++;
    _up.clear();
    _matched.clear();
    _misses = 0;
    _differ = false;
    _peeking = memoryPeek(level);
    if (_peeking) {
      _timer = Timer(const Duration(milliseconds: 2200), () {
        if (mounted) setState(() => _peeking = false);
      });
    }
    if (mounted) setState(() {});
  }

  void _turn(int i) {
    if (_peeking || _matched.contains(i) || _up.contains(i)) return;
    if (_differ) {
      // She is already after the next card: turn the last two back now.
      _timer?.cancel();
      _up.clear();
      _differ = false;
    }
    if (_up.length == 2) return; // a pair settling in
    widget.c.sound(Sfx.tap, volume: 0.7);
    setState(() => _up.add(i));
    if (_up.length < 2) return;
    final a = _up[0], b = _up[1];
    if (_deck[a] == _deck[b]) {
      _timer = Timer(const Duration(milliseconds: 420), () => _pair(a, b));
    } else {
      _misses++;
      _differ = true;
      _timer = Timer(const Duration(milliseconds: 1300), () {
        if (!mounted) return;
        setState(() {
          _up.clear();
          _differ = false;
        });
      });
    }
  }

  void _pair(int a, int b) {
    if (!mounted) return;
    widget.c.sound(Sfx.sparkle);
    setState(() {
      _matched
        ..add(a)
        ..add(b);
      _up.clear();
    });
    if (_matched.length < _deck.length) return;
    unawaited(widget.c.finishRound(memoryResult(_deck.length ~/ 2, _misses), emoji: _deck[a]));
    _timer = Timer(const Duration(milliseconds: 2600), _newBoard);
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFEDEBFF), Color(0xFFDDF3FF)])),
      child: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(t.space.lg, 96 * t.scale, t.space.lg, t.space.lg),
              child: LayoutBuilder(builder: (context, box) {
                final gap = 14 * t.scale;
                final grid = memoryGrid(_deck.length, box.biggest, gap: gap, maxWidth: 300 * t.scale);
                return Center(
                  child: SizedBox(
                    width: grid.cols * grid.card.width + gap * (grid.cols - 1),
                    child: Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      alignment: WrapAlignment.center,
                      children: [
                        for (var i = 0; i < _deck.length; i++)
                          _Card(
                            key: ValueKey('$_deal.$i'),
                            index: i,
                            face: _deck[i],
                            up: _peeking || _up.contains(i) || _matched.contains(i),
                            matched: _matched.contains(i),
                            size: grid.card,
                            onTap: () => _turn(i),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          if (_peeking)
            Positioned(
              top: t.space.md,
              left: 0,
              right: 0,
              child: SafeArea(child: Center(child: tid('memory.look', Semantics(label: 'Look!', excludeSemantics: true, child: GamePill(children: [DEmoji('👀', size: 44 * t.scale)]))))),
            ),
        ],
      ),
    );
  }
}

/// The columns that make [n] cards (width ÷ height = [aspect]) as big as
/// they can be in [area], up to [maxWidth] each.
@visibleForTesting
({int cols, Size card}) memoryGrid(int n, Size area, {double gap = 12, double aspect = 0.82, double maxWidth = double.infinity}) {
  final grids = [
    for (var cols = 1; cols <= n; cols++)
      (cols: cols, rows: (n / cols).ceil(), w: math.min(math.min((area.width - gap * (cols - 1)) / cols, (area.height - gap * ((n / cols).ceil() - 1)) / (n / cols).ceil() * aspect), maxWidth)),
  ];
  final biggest = grids.map((g) => g.w).reduce(math.max);
  // Among the biggest cards, the squarest board with no gaps is easiest to
  // scan; a wide screen takes the extra column, a tall one the extra row.
  double score(({int cols, int rows, double w}) g) => (g.cols - g.rows).abs() + 3.0 * (g.cols * g.rows - n) + (area.width >= area.height ? -g.cols : g.cols) * 0.01;
  final best = grids.where((g) => g.w >= biggest - 1).reduce((a, b) => score(b) < score(a) ? b : a);
  return (cols: best.cols, card: Size(best.w, best.w / aspect));
}

class _Card extends StatelessWidget {
  const _Card({super.key, required this.index, required this.face, required this.up, required this.matched, required this.size, required this.onTap});
  final int index;
  final String face;
  final bool up, matched;
  final Size size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size.width * 0.14);
    return DPressable(
      id: 'memory.card.$index',
      // The face is read out once it shows, the way she sees it.
      semanticLabel: up ? face : 'Card ${index + 1}',
      excludeSemantics: true,
      onTap: onTap,
      pressedScale: 0.94,
      borderRadius: radius,
      child: RepaintBoundary(
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: up ? 1 : 0),
          duration: const Duration(milliseconds: 340),
          curve: Curves.easeInOutCubic,
          builder: (context, k, _) {
            final showFace = k >= 0.5;
            final m = Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(math.pi * k);
            // Past halfway the card shows its other side, not a mirror image.
            if (showFace) m.rotateY(math.pi);
            return Transform(
              alignment: Alignment.center,
              transform: m,
              child: SizedBox.fromSize(size: size, child: showFace ? _Face(face: face, matched: matched, radius: radius) : _Back(radius: radius)),
            );
          },
        ),
      ),
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({required this.face, required this.matched, required this.radius});
  final String face;
  final bool matched;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return LayoutBuilder(builder: (context, box) {
      final card = DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: radius,
          border: Border.all(color: matched ? _matchedRing : const Color(0xFFD9D6FA), width: box.maxWidth * (matched ? 0.05 : 0.025)),
          boxShadow: t.elevation.e1,
        ),
        child: Center(child: DEmoji(face, size: box.maxWidth * 0.62)),
      );
      if (!matched) return card;
      // A found pair hops once.
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 1.12, end: 1),
        duration: const Duration(milliseconds: 600),
        curve: Curves.elasticOut,
        builder: (context, s, child) => Transform.scale(scale: s, child: child),
        child: card,
      );
    });
  }
}

class _Back extends StatelessWidget {
  const _Back({required this.radius});
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(_hue, Colors.white, 0.3)!, _hue]),
          boxShadow: DTheme.of(context).elevation.e1,
        ),
        child: const CustomPaint(painter: _BackPainter()),
      );
}

/// A card back: an inset frame and a four-point sparkle.
class _BackPainter extends CustomPainter {
  const _BackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final frame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.025
      ..color = Colors.white.withValues(alpha: 0.55);
    canvas.drawRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(s * 0.08), Radius.circular(s * 0.09)), frame);
    final c = size.center(Offset.zero);
    final r = s * 0.24, w = s * 0.06;
    final star = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + w, c.dy - w, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + w, c.dy + w, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - w, c.dy + w, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - w, c.dy - w, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(star, Paint()..color = Colors.white.withValues(alpha: 0.9));
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.6);
    for (final (dx, dy) in [(-0.3, -0.3), (0.3, 0.3), (0.3, -0.3), (-0.3, 0.3)]) {
      canvas.drawCircle(c + Offset(dx * s, dy * s), s * 0.03, dot);
    }
  }

  @override
  bool shouldRepaint(_BackPainter old) => false;
}
