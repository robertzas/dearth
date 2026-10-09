import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';

/// The colors the monster's sign paints, by food color.
const Map<String, Color> kFoodColors = {
  'red': Color(0xFFE53935),
  'yellow': Color(0xFFFDD835),
  'green': Color(0xFF43A047),
  'purple': Color(0xFF8E24AA),
  'orange': Color(0xFFFB8C00),
  'pink': Color(0xFFF06292),
  'brown': Color(0xFF8D6E63),
  'blue': Color(0xFF1E88E5),
};

/// A kind of food on the sign: two that are never on the tray.
const Map<String, List<String>> _kindSigns = {
  'fruit': ['🍉', '🍑'],
  'vegetable': ['🥬', '🥔'],
  'treat': ['🍬', '🍭'],
};

/// What the sign says, for grown-ups and screen readers.
String monsterSignLabel(MonsterRule r) {
  final kind = switch (r.kind) { 'fruit' => 'fruit', 'vegetable' => 'vegetables', 'treat' => 'treats', _ => null };
  final what = [?r.color, if (r.round == true) 'round'].join(' and ');
  if (kind == null) return 'Only $what food';
  return what.isEmpty ? 'Only $kind' : 'Only $what $kind';
}

/// Feed the Monster (SPEC FR-TOY-02, Appendix B: classification). A hungry
/// monster eats only what its sign shows: one color, then a shape or a kind
/// of food, then two at once ("red AND round"). She taps a food, or drags it
/// to the mouth. The right ones get munched; the others get a polite head
/// shake and go back to their plate. After two of those, the foods it wants
/// glow.
class MonsterGame extends StatefulWidget {
  const MonsterGame(this.c, {super.key});
  final GameController c;

  @override
  State<MonsterGame> createState() => MonsterGameState();
}

@visibleForTesting
class MonsterGameState extends State<MonsterGame> with TickerProviderStateMixin {
  final _area = GlobalKey();
  late MonsterRound _round;
  final _eaten = <int>{};
  final _wiggles = <int, int>{};
  int? _flying, _dragging;
  Offset _dragAt = Offset.zero, _grip = Offset.zero;
  int _slips = 0, _deal = 0;
  bool _full = false;
  _Layout? _layout;

  late final AnimationController _chew = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 90));
  late final AnimationController _open = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  late final AnimationController _hop = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  final _look = ValueNotifier<Offset>(Offset.zero);
  Timer? _blinker, _arrive, _next;

  @visibleForTesting
  MonsterRound get debugRound => _round;

  @override
  void initState() {
    super.initState();
    _newRound();
    _blinker = Timer.periodic(const Duration(milliseconds: 3700), (_) => _blink.forward(from: 0).then((_) => _blink.reverse()));
  }

  @override
  void dispose() {
    _blinker?.cancel();
    _arrive?.cancel();
    _next?.cancel();
    for (final c in [_chew, _shake, _blink, _open, _hop]) {
      c.dispose();
    }
    _look.dispose();
    super.dispose();
  }

  void _newRound() {
    _round = monsterRound(widget.c.level, widget.c.random);
    _eaten.clear();
    _slips = 0;
    _deal++;
    _flying = _dragging = null;
    _full = false;
    _look.value = Offset.zero;
    if (mounted) setState(() {});
  }

  bool _wants(int i) => _round.rule.accepts(_round.tray[i]);

  /// Turns the monster's eyes toward [p] (playfield coordinates).
  void _lookAt(Offset p) {
    final l = _layout;
    if (l == null) return;
    final d = p - l.eyes;
    _look.value = d.distance < 1 ? Offset.zero : d / math.max(d.distance, l.monster.width * 0.6);
  }

  void _feed(int i) {
    if (_flying != null || _dragging != null || _eaten.contains(i) || _full) return;
    final l = _layout;
    if (l != null) _lookAt(l.plates[i]);
    setState(() => _flying = i);
    unawaited(_open.forward());
    _arrive = Timer(const Duration(milliseconds: 420), () => _taste(i));
  }

  /// [i] is at the mouth: munched, or politely refused.
  void _taste(int i) {
    if (!mounted) return;
    final c = widget.c;
    unawaited(_open.reverse());
    if (_wants(i)) {
      c.sound(Sfx.munch);
      unawaited(_chew.forward(from: 0));
      setState(() {
        _eaten.add(i);
        _flying = null;
      });
      if (_eaten.length == _round.toEat) {
        _full = true;
        unawaited(_hop.forward(from: 0));
        unawaited(c.finishRound(monsterResult(_slips), emoji: '😋'));
        _next = Timer(const Duration(milliseconds: 2600), _newRound);
      }
    } else {
      _slips++;
      c.cue();
      unawaited(_shake.forward(from: 0));
      setState(() {
        _flying = null;
        _wiggles[i] = (_wiggles[i] ?? 0) + 1;
      });
    }
    _look.value = Offset.zero;
  }

  Offset _local(Offset global) => (_area.currentContext!.findRenderObject()! as RenderBox).globalToLocal(global);

  void _dragStart(int i, DragStartDetails d) {
    final l = _layout;
    if (l == null || _flying != null || _eaten.contains(i) || _full) return;
    final p = _local(d.globalPosition);
    setState(() {
      _dragging = i;
      _grip = l.plates[i] - p;
      _dragAt = l.plates[i];
    });
  }

  void _dragUpdate(DragUpdateDetails d) {
    final l = _layout;
    if (_dragging == null || l == null) return;
    setState(() => _dragAt = _local(d.globalPosition) + _grip);
    _lookAt(_dragAt);
    // It opens wide as the food comes near.
    final near = (_dragAt - l.mouth).distance < l.food * 1.8;
    if (near != (_open.status == AnimationStatus.forward || _open.status == AnimationStatus.completed)) {
      unawaited(near ? _open.forward() : _open.reverse());
    }
  }

  void _dragEnd() {
    final i = _dragging, l = _layout;
    if (i == null || l == null) return;
    _dragging = null;
    if ((_dragAt - l.mouth).distance < l.food * 1.2) {
      _taste(i);
    } else {
      unawaited(_open.reverse());
      _look.value = Offset.zero;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF3E0), Color(0xFFFFE0F0)])),
      child: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(t.space.lg, 110 * t.scale, t.space.lg, t.space.lg),
              child: LayoutBuilder(
                key: _area,
                builder: (context, box) {
                  final l = _layout = _Layout.of(box.biggest, _round.tray.length);
                  final hint = _slips >= 2;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fromRect(
                        rect: l.monster,
                        child: RepaintBoundary(
                          child: CustomPaint(painter: MonsterPainter(chew: _chew, shake: _shake, blink: _blink, open: _open, hop: _hop, look: _look)),
                        ),
                      ),
                      Positioned.fromRect(
                        rect: Rect.fromCircle(center: l.mouth, radius: l.food * 0.8),
                        child: tid('monster.mouth', Semantics(label: 'The monster’s mouth', excludeSemantics: true, child: const SizedBox.expand())),
                      ),
                      for (var i = 0; i < _round.tray.length; i++) ...[
                        Positioned(
                          left: l.plates[i].dx - l.food * 0.7,
                          top: l.plates[i].dy - l.food * 0.7,
                          child: IgnorePointer(child: _Plate(size: l.food * 1.4, glow: hint && _wants(i) && !_eaten.contains(i))),
                        ),
                        _foodAt(i, l),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
          Positioned(top: t.space.md, left: 0, right: 0, child: SafeArea(child: Center(child: _Sign(rule: _round.rule)))),
        ],
      ),
    );
  }

  Widget _foodAt(int i, _Layout l) {
    final food = _round.tray[i];
    final eaten = _eaten.contains(i);
    final dragging = _dragging == i;
    final at = eaten || _flying == i ? l.mouth : (dragging ? _dragAt : l.plates[i]);
    return AnimatedPositioned(
      key: ValueKey('$_deal.$i'),
      duration: dragging ? Duration.zero : const Duration(milliseconds: 400),
      curve: _flying == i ? Curves.easeInCubic : Curves.easeOutBack,
      left: at.dx - l.food / 2,
      top: at.dy - l.food / 2,
      child: tid(
        'monster.food.$i',
        Semantics(
          button: true,
          label: eaten ? 'Eaten' : food.name,
          onTap: () => _feed(i),
          excludeSemantics: true,
          child: GestureDetector(
            excludeFromSemantics: true,
            dragStartBehavior: DragStartBehavior.down,
            onTap: () => _feed(i),
            onPanStart: (d) => _dragStart(i, d),
            onPanUpdate: _dragUpdate,
            onPanEnd: (_) => _dragEnd(),
            onPanCancel: _dragEnd,
            child: AnimatedScale(
              // Into the mouth it goes.
              scale: eaten ? 0 : (dragging ? 1.15 : 1),
              duration: Duration(milliseconds: eaten ? 260 : 160),
              child: _Wobble(wobbles: _wiggles[i] ?? 0, child: DEmoji(food.emoji, size: l.food)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the monster stands and the plates sit for a playfield [area].
class _Layout {
  _Layout(this.monster, this.plates, this.food);

  factory _Layout.of(Size area, int n) {
    final wide = area.width > area.height * 1.1;
    final Rect monster, tray;
    if (wide) {
      monster = Rect.fromLTWH(area.width * 0.02, area.height * 0.04, area.width * 0.4, area.height * 0.92);
      tray = Rect.fromLTWH(area.width * 0.46, area.height * 0.08, area.width * 0.54, area.height * 0.84);
    } else {
      monster = Rect.fromLTWH(area.width * 0.12, 0, area.width * 0.76, area.height * 0.5);
      tray = Rect.fromLTWH(0, area.height * 0.56, area.width, area.height * 0.44);
    }
    final rows = n <= 4 ? (wide ? 2 : 1) : 2;
    final cols = (n / rows).ceil();
    final food = math.min(tray.width / cols, tray.height / rows) * 0.56;
    final plates = [
      for (var i = 0; i < n; i++) Offset(tray.left + tray.width * ((i % cols) + 0.5) / cols, tray.top + tray.height * ((i ~/ cols) + 0.5) / rows),
    ];
    // The monster keeps its shape: as wide as it is tall, standing on the floor.
    final side = math.min(monster.width, monster.height);
    final body = Rect.fromLTWH(monster.center.dx - side / 2, monster.bottom - side, side, side);
    return _Layout(body, plates, food);
  }

  final Rect monster;
  final List<Offset> plates;

  /// A food's size.
  final double food;

  Offset get mouth => Offset(monster.center.dx, monster.top + monster.height * 0.62);
  Offset get eyes => Offset(monster.center.dx, monster.top + monster.height * 0.33);
}

/// What the monster eats today, in pictures: a splash of its color, a ring
/// for round, two foods for a kind.
class _Sign extends StatelessWidget {
  const _Sign({required this.rule});
  final MonsterRule rule;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final d = 48 * t.scale;
    final parts = <Widget>[
      if (rule.color != null)
        Container(
          width: d,
          height: d,
          decoration: BoxDecoration(color: kFoodColors[rule.color] ?? Colors.grey, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: t.elevation.e1),
        ),
      if (rule.round == true)
        Container(width: d, height: d, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF3B3355), width: d * 0.16))),
      if (rule.kind != null) Row(mainAxisSize: MainAxisSize.min, children: [for (final e in _kindSigns[rule.kind] ?? const ['🍽️']) DEmoji(e, size: d)]),
    ];
    return tid(
      'monster.sign',
      Semantics(
        label: monsterSignLabel(rule),
        excludeSemantics: true,
        child: GamePill(children: [
          DEmoji('😋', size: 44 * t.scale),
          SizedBox(width: t.space.sm),
          for (final (i, p) in parts.indexed) ...[
            if (i > 0) Padding(padding: EdgeInsets.symmetric(horizontal: t.space.xs), child: Text('+', style: t.text.kidTitle.copyWith(color: const Color(0xFF3B3355)))),
            p,
          ],
        ]),
      ),
    );
  }
}

class _Plate extends StatelessWidget {
  const _Plate({required this.size, required this.glow});
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: glow ? const Color(0xFFFFC93C) : const Color(0xFFF1DCE6), width: glow ? size * 0.06 : size * 0.03),
          // A solid halo, not a blur: blurs are too slow to animate on a frame.
          // Always first, so only the halo animates.
          boxShadow: [BoxShadow(color: glow ? const Color(0x77FFD54F) : const Color(0x00FFD54F), spreadRadius: glow ? 10 : 0), const BoxShadow(color: Color(0x14000000), offset: Offset(0, 4))],
        ),
      );
}

/// A shake each time [wobbles] grows: "not that one".
class _Wobble extends StatelessWidget {
  const _Wobble({required this.wobbles, required this.child});
  final int wobbles;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        key: ValueKey(wobbles),
        tween: Tween(begin: wobbles == 0 ? 0 : 1, end: 0),
        duration: const Duration(milliseconds: 600),
        builder: (context, k, child) => Transform.rotate(angle: math.sin(k * math.pi * 5) * 0.3 * k, child: child),
        child: child,
      );
}

/// The monster: a round body (green by default; Cookie Count's and Letter
/// Monster's are their own colors), two horns, big eyes that follow the food
/// and blink, and a mouth that opens, chews and smiles. Its animations
/// repaint only this layer.
class MonsterPainter extends CustomPainter {
  MonsterPainter({
    required this.chew,
    required this.shake,
    required this.blink,
    required this.open,
    required this.hop,
    required this.look,
    this.skin = MonsterSkin.green,
  }) : super(repaint: Listenable.merge([chew, shake, blink, open, hop, look]));
  final Animation<double> chew, shake, blink, open, hop;
  final ValueListenable<Offset> look;
  final MonsterSkin skin;

  /// Where its mouth and eyes are, as fractions of its box.
  static const mouthAt = Offset(0.5, 0.62), eyesAt = Offset(0.5, 0.33);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final s = shake.value, hp = hop.value;
    canvas
      ..save()
      ..translate(w / 2, h)
      // A head shake for "no thank you"; a happy hop when it's full.
      ..rotate(s == 0 ? 0 : math.sin(s * math.pi * 4) * 0.1 * (1 - s))
      ..translate(0, hp == 0 ? 0 : -math.sin(hp * math.pi * 2).abs() * h * 0.06 * (1 - hp))
      ..translate(-w / 2, -h);

    // Feet, horns, body, belly.
    final dark = Paint()..color = skin.dark;
    canvas
      ..drawOval(Rect.fromCenter(center: Offset(w * 0.32, h * 0.95), width: w * 0.26, height: h * 0.1), dark)
      ..drawOval(Rect.fromCenter(center: Offset(w * 0.68, h * 0.95), width: w * 0.26, height: h * 0.1), dark);
    final horn = Paint()..color = const Color(0xFFFFB74D);
    for (final x in [0.3, 0.7]) {
      canvas.drawPath(
        Path()
          ..moveTo(w * (x - 0.07), h * 0.2)
          ..quadraticBezierTo(w * (x - 0.02), h * 0.02, w * (x + (x < 0.5 ? -0.04 : 0.04)), h * 0.04)
          ..quadraticBezierTo(w * (x + 0.03), h * 0.12, w * (x + 0.07), h * 0.2)
          ..close(),
        horn,
      );
    }
    final body = Path()
      ..moveTo(w * 0.5, h * 0.1)
      ..cubicTo(w * 0.86, h * 0.1, w * 0.98, h * 0.42, w * 0.94, h * 0.66)
      ..cubicTo(w * 0.9, h * 0.9, w * 0.72, h * 0.95, w * 0.5, h * 0.95)
      ..cubicTo(w * 0.28, h * 0.95, w * 0.1, h * 0.9, w * 0.06, h * 0.66)
      ..cubicTo(w * 0.02, h * 0.42, w * 0.14, h * 0.1, w * 0.5, h * 0.1)
      ..close();
    canvas
      ..drawPath(body, Paint()..color = skin.body)
      ..drawOval(Rect.fromCenter(center: Offset(w * 0.5, h * 0.74), width: w * 0.56, height: h * 0.36), Paint()..color = skin.belly);
    for (final (x, y, r) in [(0.2, 0.5, 0.025), (0.8, 0.46, 0.03), (0.74, 0.26, 0.02), (0.28, 0.3, 0.018)]) {
      canvas.drawCircle(Offset(w * x, h * y), w * r, dark);
    }

    // Eyes that follow the food, and blink.
    final eyeR = w * 0.12;
    final lk = look.value;
    for (final x in [0.36, 0.64]) {
      final c = Offset(w * x, h * 0.33);
      canvas
        ..drawCircle(c, eyeR, Paint()..color = Colors.white)
        ..drawCircle(c + lk * eyeR * 0.42, eyeR * 0.5, Paint()..color = const Color(0xFF2B2240))
        ..drawCircle(c + lk * eyeR * 0.42 + Offset(-eyeR * 0.16, -eyeR * 0.18), eyeR * 0.16, Paint()..color = Colors.white);
      final b = blink.value;
      if (b > 0) {
        canvas
          ..save()
          ..clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: eyeR + 1)))
          ..drawRect(Rect.fromLTRB(c.dx - eyeR - 1, c.dy - eyeR - 1, c.dx + eyeR + 1, c.dy - eyeR + 2 * eyeR * b + 1), Paint()..color = skin.body)
          ..restore();
      }
    }

    // The mouth: a smile when closed; open wide, with teeth and a tongue,
    // when food comes; three chomps after a bite.
    final c = chew.value;
    final chomp = c == 0 || c == 1 ? 0.0 : math.sin(c * math.pi * 3).abs();
    final o = math.max(open.value, chomp * 0.55);
    final mouth = Offset(w * 0.5, h * 0.62);
    if (o < 0.06) {
      canvas.drawPath(
        Path()
          ..moveTo(mouth.dx - w * 0.16, mouth.dy - h * 0.02)
          ..quadraticBezierTo(mouth.dx, mouth.dy + h * 0.08, mouth.dx + w * 0.16, mouth.dy - h * 0.02),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.025
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF3B2A2A),
      );
    } else {
      final r = Rect.fromCenter(center: mouth, width: w * (0.3 + 0.08 * o), height: h * 0.26 * o);
      canvas
        ..drawOval(r, Paint()..color = const Color(0xFF7A1F2B))
        ..save()
        ..clipPath(Path()..addOval(r))
        ..drawOval(Rect.fromCenter(center: Offset(r.center.dx, r.bottom), width: r.width * 0.6, height: r.height * 0.7), Paint()..color = const Color(0xFFF06292));
      final tooth = Paint()..color = Colors.white;
      for (final x in [-0.22, 0.22]) {
        canvas.drawPath(
          Path()
            ..moveTo(r.center.dx + r.width * (x - 0.09), r.top)
            ..lineTo(r.center.dx + r.width * (x + 0.09), r.top)
            ..lineTo(r.center.dx + r.width * x, r.top + r.height * 0.28)
            ..close(),
          tooth,
        );
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(MonsterPainter old) => old.skin != skin;
}

/// A monster's colors: body, spots and feet, belly.
enum MonsterSkin {
  green(Color(0xFF7AC74F), Color(0xFF4E9A35), Color(0xFFBEE6A3)),
  purple(Color(0xFF9C7BE0), Color(0xFF6B4FB8), Color(0xFFD9CCF7)),
  orange(Color(0xFFF7A048), Color(0xFFCF6E1D), Color(0xFFFFD9A8));

  const MonsterSkin(this.body, this.dark, this.belly);
  final Color body, dark, belly;
}
