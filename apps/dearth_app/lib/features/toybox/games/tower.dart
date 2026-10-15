import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'cookies.dart' show BellPainter;
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// The blocks' colors, bottom up: a rainbow, so each one is its own.
const List<Color> kTowerBlocks = [
  Color(0xFFE94B4B), Color(0xFFF28C38), Color(0xFFF5C334), Color(0xFF6CC04A), Color(0xFF2EB8A6), //
  Color(0xFF3D8FE0), Color(0xFF6A5ACD), Color(0xFFB25FD6), Color(0xFFF06BA8), Color(0xFF8D6E63),
];

const Color _red = Color(0xFFD64545);

/// Block Tower (SPEC FR-TOY-03, Appendix B: counting to a number, taller
/// and shorter, one more and one less). The giraffe wants the star:
/// "Build a tower five blocks tall!" A tap on the pile drops a block that
/// lands with a bounce and is counted out loud; a tap on the top block
/// takes it off. The bell checks: right, and the giraffe climbs to the top
/// and gets the star, then the tower comes down in a happy crash. Too
/// short or too tall, the voice says which; after two, the right height
/// shows as an outline (it always does at the first level). Then a red
/// tower to match, and one taller or shorter than it.
class TowerGame extends StatefulWidget {
  const TowerGame(this.c, {super.key});
  final GameController c;

  @override
  State<TowerGame> createState() => TowerGameState();
}

@visibleForTesting
class TowerGameState extends State<TowerGame> with RoundVoice {
  TowerRound? _round;
  int _height = 0, _slips = 0, _deal = 0, _pileHops = 0, _bellHops = 0, _topWiggles = 0;
  bool _won = false, _crashing = false;
  final _timers = <Timer>[];

  @visibleForTesting
  TowerRound get debugRound => _round!;

  @visibleForTesting
  int get debugHeight => _height;

  @override
  GameController get voiceOf => widget.c;

  @override
  String? get promptClip {
    final r = _round;
    if (r == null || _won) return null;
    return switch (r.ask) {
      TowerAsk.build => towerBuildClip(r.target),
      TowerAsk.match => VoiceLine.towerMatch,
      TowerAsk.oneMore => VoiceLine.towerMore,
      TowerAsk.oneLess => VoiceLine.towerLess,
    };
  }

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
    super.dispose();
  }

  void _after(Duration d, VoidCallback f) => _timers.add(Timer(d, () {
        if (mounted) f();
      }));

  void _newRound() {
    _round = towerRound(widget.c.level, widget.c.random, last: _round);
    _height = 0;
    _slips = 0;
    _won = _crashing = false;
    _deal++;
    askSoon(after: const Duration(milliseconds: 700));
    if (mounted) setState(() {});
  }

  /// A block from the pile drops onto the tower, counted.
  void _add() {
    stillHere();
    if (_won) return;
    if (_height >= kTowerMax) {
      widget.c.cue();
      setState(() => _pileHops++);
      return;
    }
    widget.c.sound(Sfx.tap, volume: 0.6, rate: 0.9 + _height * 0.06);
    setState(() {
      _height++;
      _pileHops++;
    });
    widget.c.say(numberClip(_height));
  }

  /// The top block comes off again.
  void _takeOff() {
    stillHere();
    if (_won || _height == 0) return;
    widget.c.sound(Sfx.pop, volume: 0.5);
    setState(() {
      _height--;
      _topWiggles++;
    });
    if (_height > 0) widget.c.say(numberClip(_height));
  }

  /// The bell: tall enough?
  void _ring() {
    stillHere();
    final r = _round!;
    if (_won) return;
    setState(() => _bellHops++);
    final c = widget.c;
    if (_height != r.target) {
      _slips++;
      c.cue();
      c.say(_height < r.target ? VoiceLine.towerShort : VoiceLine.towerTall);
      return;
    }
    quiet();
    c.sound(Sfx.success);
    c.say(towerYesClip(r.target));
    setState(() => _won = true);
    unawaited(c.finishRound(towerResult(_slips), emoji: '🦒'));
    // The climb, the star, then the crash and a new round.
    final told = afterVoice(towerYesClip(r.target), atLeast: const Duration(milliseconds: 2200));
    _after(told, () {
      c.say(VoiceLine.towerCrash);
      c.sound(Sfx.boing, volume: 0.6);
      setState(() => _crashing = true);
    });
    _after(told + const Duration(milliseconds: 2000), _newRound);
  }

  String _askLabel() {
    final r = _round!;
    if (_won) return '${r.target} blocks tall!';
    return switch (r.ask) {
      TowerAsk.build => 'Build a tower ${r.target} blocks tall',
      TowerAsk.match => 'As tall as the red tower (${r.other})',
      TowerAsk.oneMore => 'One taller than the red tower (${r.other})',
      TowerAsk.oneLess => 'One shorter than the red tower (${r.other})',
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    final outline = r.outline || _slips >= 2 || idleHint;
    return Backdrop(
      top: const Color(0xFFCDEBFF),
      bottom: const Color(0xFFF2FAE8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(child: DStillPaint(painter: _ScenePainter())),
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final wide = box.maxWidth > box.maxHeight;
              // Ten blocks and a giraffe's head fit the height.
              final block = math.min(box.maxHeight / (kTowerMax + 1.6), (wide ? box.maxWidth * 0.62 : box.maxWidth * 0.9) / ((r.other > 0 ? 2 : 1) * 2.2 + 3.2));
              final side = math.min(math.min(block * 3, 230 * t.scale), wide ? box.maxHeight * 0.32 : box.maxWidth * 0.3);
              final towers = Row(
                key: ValueKey(_deal),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _Giraffe(size: block * 3, height: _height, block: block, climbing: _won && !_crashing),
                  SizedBox(width: block * 0.2),
                  _Tower(
                    id: 'tower.tower',
                    label: 'Tower: $_height ${_height == 1 ? 'block' : 'blocks'}',
                    height: _height,
                    block: block,
                    outline: outline ? r.target : null,
                    star: _won && !_crashing,
                    crashing: _crashing,
                    topWiggles: _topWiggles,
                    onTapTop: _takeOff,
                  ),
                  if (r.other > 0) ...[
                    SizedBox(width: block * 0.8),
                    _Tower(id: 'tower.red', label: 'Red tower: ${r.other} blocks', height: r.other, block: block, color: _red, crashing: false, topWiggles: 0, onTapTop: () {}),
                  ],
                ],
              );
              final controls = Flex(
                direction: wide ? Axis.vertical : Axis.horizontal,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DPressable(
                    id: 'tower.pile',
                    semanticLabel: 'Blocks',
                    excludeSemantics: true,
                    onTap: _add,
                    borderRadius: BorderRadius.circular(side * 0.2),
                    child: Hop(count: _pileHops, child: SizedBox.square(dimension: side, child: const RepaintBoundary(child: CustomPaint(painter: _PilePainter())))),
                  ),
                  SizedBox(width: side * 0.3, height: side * 0.3),
                  DPressable(
                    id: 'tower.bell',
                    semanticLabel: 'Bell',
                    excludeSemantics: true,
                    onTap: _ring,
                    borderRadius: BorderRadius.circular(side / 2),
                    child: Hop(count: _bellHops, child: SizedBox.square(dimension: side * 0.8, child: const RepaintBoundary(child: CustomPaint(painter: BellPainter(), size: Size.infinite)))),
                  ),
                ],
              );
              return wide
                  ? Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [towers, SizedBox(width: block * 1.5), Padding(padding: EdgeInsets.only(bottom: block * 0.5), child: controls)])
                  : Column(mainAxisAlignment: MainAxisAlignment.end, children: [Expanded(child: Align(alignment: Alignment.bottomCenter, child: towers)), SizedBox(height: t.space.lg), controls]);
            }),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'tower.ask',
              label: _askLabel(),
              onSayAgain: sayPrompt,
              children: [
                if (r.ask == TowerAsk.build)
                  for (final digit in '${r.target}'.split('')) GlyphView(digit, height: 52 * t.scale, color: const Color(0xFF6B4FB8))
                else ...[
                  _MiniTower(n: r.ask == TowerAsk.oneLess ? 3 : 2, color: kTowerBlocks[1], size: 52 * t.scale),
                  SizedBox(width: t.space.xs),
                  Text(switch (r.ask) { TowerAsk.oneMore => '+1', TowerAsk.oneLess => '−1', _ => '=' }, style: t.text.kidTitle.copyWith(color: const Color(0xFF6B4FB8))),
                  SizedBox(width: t.space.xs),
                  _MiniTower(n: 2, color: _red, size: 52 * t.scale),
                ],
                SizedBox(width: t.space.xs),
                DEmoji('🦒', size: 40 * t.scale),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A tower of [height] blocks standing on the ground: the newest one
/// drops in with a bounce; at the end they tumble apart.
class _Tower extends StatelessWidget {
  const _Tower({
    required this.id,
    required this.label,
    required this.height,
    required this.block,
    required this.crashing,
    required this.topWiggles,
    required this.onTapTop,
    this.color,
    this.outline,
    this.star = false,
  });
  final String id;
  final String label;
  final int height;
  final double block;
  final bool crashing;
  final int topWiggles;
  final VoidCallback onTapTop;
  final Color? color;

  /// The height to reach, as a dashed outline.
  final int? outline;
  final bool star;

  @override
  Widget build(BuildContext context) {
    final w = block * 2.2;
    final tall = math.max(height, outline ?? 0);
    return tid(
      id,
      Semantics(
        button: true,
        label: label,
        onTap: onTapTop,
        excludeSemantics: true,
        child: SizedBox(
          width: w,
          height: block * (kTowerMax + 0.6),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              // Her tower's spot: a wooden plank to build on.
              if (color == null)
                Positioned(
                  bottom: -block * 0.18,
                  child: IgnorePointer(
                    child: Container(
                      width: w * 1.2,
                      height: block * 0.2,
                      decoration: BoxDecoration(color: const Color(0xFFC98D52), borderRadius: BorderRadius.circular(block * 0.08), border: Border.all(color: const Color(0xFF8C5A2B), width: block * 0.04)),
                    ),
                  ),
                ),
              if (outline != null)
                Positioned(bottom: 0, child: IgnorePointer(child: SizedBox(width: w, height: block * outline!, child: const CustomPaint(painter: _OutlinePainter())))),
              for (var i = 0; i < height; i++)
                Positioned(
                  bottom: block * i,
                  child: _Block(
                    // Keyed by height: a new top block drops in, the others stay put.
                    key: ValueKey(i),
                    index: i,
                    width: w,
                    height: block,
                    color: color ?? kTowerBlocks[i % kTowerBlocks.length],
                    crashing: crashing,
                    wiggles: i == height - 1 ? topWiggles : 0,
                    onTap: i == height - 1 ? onTapTop : null,
                  ),
                ),
              if (star) Positioned(bottom: block * tall + block * 0.1, child: IgnorePointer(child: Hop(count: 1, child: DEmoji('⭐', size: block * 1.2)))),
            ],
          ),
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({super.key, required this.index, required this.width, required this.height, required this.color, required this.crashing, required this.wiggles, this.onTap});
  final int index;
  final double width, height;
  final Color color;
  final bool crashing;
  final int wiggles;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final face = SizedBox(width: width, height: height, child: RepaintBoundary(child: CustomPaint(painter: _BlockPainter(color))));
    // Drops in from a little above, then the crash sends each one off to
    // a side, spinning, alternate ones the other way.
    final dropped = TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 380),
      curve: Curves.bounceOut,
      builder: (context, k, child) => Transform.translate(offset: Offset(0, -height * 2.2 * k), child: child),
      child: face,
    );
    final body = crashing
        ? TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 700 + index * 40),
            curve: Curves.easeIn,
            builder: (context, k, child) {
              final dir = index.isEven ? 1.0 : -1.0;
              return Transform.translate(
                offset: Offset(dir * width * (0.6 + index * 0.25) * k, height * index * k),
                child: Transform.rotate(angle: dir * 1.4 * k, child: child),
              );
            },
            child: face,
          )
        : dropped;
    final wiggled = Wiggle(count: wiggles, child: body);
    return onTap == null ? IgnorePointer(child: wiggled) : GestureDetector(excludeFromSemantics: true, behavior: HitTestBehavior.opaque, onTapDown: (_) => onTap!(), child: wiggled);
  }
}

/// A wooden toy block: a rounded face, a lighter top edge, a darker rim.
class _BlockPainter extends CustomPainter {
  const _BlockPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius((Offset.zero & size).deflate(size.height * 0.03), Radius.circular(size.height * 0.18));
    canvas
      ..drawRRect(r, Paint()..color = color)
      ..drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(r.left + size.height * 0.1, r.top + size.height * 0.08, r.width - size.height * 0.2, size.height * 0.22), Radius.circular(size.height * 0.1)),
        Paint()..color = Colors.white.withValues(alpha: 0.35),
      )
      ..drawRRect(r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.height * 0.06
        ..color = Color.lerp(color, Colors.black, 0.3)!);
  }

  @override
  bool shouldRepaint(_BlockPainter old) => old.color != color;
}

/// The height to reach, dashed.
class _OutlinePainter extends CustomPainter {
  const _OutlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(3, size.width * 0.025)
      ..color = const Color(0x99A06CD5);
    final r = Offset.zero & size;
    final dash = size.width * 0.08;
    for (final (a, b) in [(r.topLeft, r.topRight), (r.topRight, r.bottomRight), (r.bottomLeft, r.topLeft)]) {
      final d = b - a;
      final n = (d.distance / (dash * 2)).floor();
      for (var k = 0; k < n; k++) {
        canvas.drawLine(a + d * (k * 2 / (n * 2)), a + d * ((k * 2 + 1) / (n * 2)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_OutlinePainter old) => false;
}

/// The pile she takes blocks from.
class _PilePainter extends CustomPainter {
  const _PilePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final b = Size(s * 0.42, s * 0.24);
    for (final (i, (x, y)) in const [(0.06, 0.66), (0.52, 0.66), (0.29, 0.4), (0.18, 0.14), (0.5, 0.14)].indexed) {
      canvas
        ..save()
        ..translate(x * s, y * s)
        ..rotate((i.isEven ? -1 : 1) * 0.06);
      _BlockPainter(kTowerBlocks[(i * 3) % kTowerBlocks.length]).paint(canvas, b);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PilePainter old) => false;
}

/// A little tower for the prompt pill.
class _MiniTower extends StatelessWidget {
  const _MiniTower({required this.n, required this.color, required this.size});
  final int n;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size * 0.5,
        height: size,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [for (var i = 0; i < n; i++) SizedBox(width: size * 0.46, height: size / 3.4, child: CustomPaint(painter: _BlockPainter(color)))],
        ),
      );
}

/// The giraffe beside the tower: climbs to the top when it's right.
class _Giraffe extends StatelessWidget {
  const _Giraffe({required this.size, required this.height, required this.block, required this.climbing});
  final double size;
  final int height;
  final double block;
  final bool climbing;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: block * (kTowerMax + 0.6),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 1400),
              curve: Curves.easeInOutBack,
              bottom: climbing ? block * math.max(0, height - 1) : 0,
              left: 0,
              child: IgnorePointer(child: tid('tower.giraffe', Semantics(label: climbing ? 'The giraffe climbs up' : 'The giraffe', excludeSemantics: true, child: DEmoji('🦒', size: size)))),
            ),
          ],
        ),
      );
}

/// A sunny day: sky, sun, a few clouds, and the grass the towers stand on.
/// Painted once.
class _ScenePainter extends CustomPainter {
  const _ScenePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawCircle(Offset(w * 0.9, h * 0.16), size.shortestSide * 0.07, Paint()..color = const Color(0xFFFFD54F));
    final cloud = Paint()..color = Colors.white.withValues(alpha: 0.85);
    for (final (x, y, r) in const [(0.14, 0.22, 0.045), (0.19, 0.2, 0.06), (0.25, 0.23, 0.04), (0.6, 0.3, 0.035), (0.65, 0.28, 0.05), (0.7, 0.31, 0.035)]) {
      canvas.drawCircle(Offset(w * x, h * y), size.shortestSide * r, cloud);
    }
    final ground = Path()
      ..moveTo(0, h * 0.95)
      ..quadraticBezierTo(w * 0.5, h * 0.91, w, h * 0.95)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(ground, Paint()..color = const Color(0xFF9BD27A));
  }

  @override
  bool shouldRepaint(_ScenePainter old) => false;
}

