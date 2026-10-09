import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'monster.dart';
import 'voice_widgets.dart';

/// Cookie Count (SPEC FR-TOY-03, Appendix B: making a set of a given size).
/// Feed the Monster's purple cousin holds up a number: "I want five
/// cookies!" She taps the jar and a cookie flies to the plate as the voice
/// says the new count; tapping a cookie on the plate puts it back. The plate
/// is a ten frame (two rows of five), so seven always looks like five and
/// two. When she thinks it's right she rings the bell: the monster gobbles
/// them one by one ("Five cookies! Yum, yum!"), or shakes its head and asks
/// for more or fewer, and the cookies stay so she can fix the plate. After
/// two wrong rings, a spot shows on the plate for each cookie it wants. A
/// long pause asks again. The top level starts with cookies on the plate,
/// too few or too many.
class CookieGame extends StatefulWidget {
  const CookieGame(this.c, {super.key});
  final GameController c;

  @override
  State<CookieGame> createState() => CookieGameState();
}

@visibleForTesting
class CookieGameState extends State<CookieGame> with TickerProviderStateMixin {
  CookieRound? _round;

  /// The cookies on the plate, oldest first, by identity: each keeps its
  /// own flight as the others shift.
  final _plate = <int>[];

  /// Cookies flying back to the jar, with the spot they left.
  final _returning = <int, int>{};
  final _eaten = <int>{};

  /// The cookies the round started with (the top level): already there,
  /// not flown in.
  final _prefilled = <int>{};
  int _next = 0, _slips = 0, _deal = 0, _jarHops = 0, _bellHops = 0, _jarWiggles = 0;
  bool _hint = false, _solved = false, _toldBell = false;
  final _timers = <Timer>[];
  Timer? _idle;
  _Layout? _layout;

  late final AnimationController _chew = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 90));
  late final AnimationController _open = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  late final AnimationController _hop = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  final _look = ValueNotifier<Offset>(Offset.zero);
  Timer? _blinker;

  @visibleForTesting
  CookieRound get debugRound => _round!;

  /// Cookies on the plate now.
  @visibleForTesting
  int get debugPlate => _plate.length;

  /// Whether the plate shows a spot for each cookie it wants.
  @visibleForTesting
  bool get debugSpots => _round!.spots || _hint;

  @visibleForTesting
  bool get debugSolved => _solved;

  @override
  void initState() {
    super.initState();
    _newRound();
    _blinker = Timer.periodic(const Duration(milliseconds: 4100), (_) => _blink.forward(from: 0).then((_) => _blink.reverse()));
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _idle?.cancel();
    _blinker?.cancel();
    for (final c in [_chew, _shake, _blink, _open, _hop]) {
      c.dispose();
    }
    _look.dispose();
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
    final r = _round = cookieRound(widget.c.level, widget.c.random, last: _round);
    _plate
      ..clear()
      ..addAll([for (var i = 0; i < r.start; i++) _next++]);
    _prefilled
      ..clear()
      ..addAll(_plate);
    _returning.clear();
    _eaten.clear();
    _slips = 0;
    _hint = _solved = false;
    _deal++;
    _look.value = Offset.zero;
    // A beat for the round to land, then the order; the bell's job is
    // explained once a session.
    _after(const Duration(milliseconds: 600), () {
      _sayAsk();
      if (!_toldBell) {
        _toldBell = true;
        _after(afterVoice(cookieAskClip(r.want)), () => widget.c.say(VoiceLine.cookiesBell));
      }
    });
    _waitIdle();
    if (mounted) setState(() {});
  }

  void _sayAsk() => widget.c.say(cookieAskClip(_round!.want));

  /// A long pause asks again, and reminds her of the bell once there's
  /// something on the plate. Not a slip.
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 11), () {
      if (!mounted || _solved) return;
      _sayAsk();
      if (_plate.isNotEmpty) _after(afterVoice(cookieAskClip(_round!.want)), () => widget.c.say(VoiceLine.cookiesBell));
      _waitIdle();
    });
  }

  void _lookAt(Offset p) {
    final l = _layout;
    if (l == null) return;
    final d = p - l.eyes;
    _look.value = d.distance < 1 ? Offset.zero : d / math.max(d.distance, l.monster.width * 0.6);
  }

  void _tapJar() {
    if (_solved) return;
    _waitIdle();
    if (_plate.length >= kCookiePlate) {
      // The plate is full: a shake, not a slip.
      widget.c.sound(Sfx.boing, volume: 0.4);
      setState(() => _jarWiggles++);
      return;
    }
    widget.c.sound(Sfx.pop, volume: 0.5);
    setState(() {
      _plate.add(_next++);
      _jarHops++;
    });
    final l = _layout;
    if (l != null) _lookAt(l.spot(_plate.length - 1));
    // The count as it lands.
    final n = _plate.length;
    _after(const Duration(milliseconds: 300), () => widget.c.say(numberClip(n)));
  }

  void _tapCookie(int id) {
    final at = _plate.indexOf(id);
    if (_solved || at < 0) return;
    _waitIdle();
    widget.c.sound(Sfx.snap, volume: 0.45);
    setState(() {
      _plate.removeAt(at);
      _returning[id] = at;
    });
    widget.c.say(numberClip(_plate.length));
    _after(const Duration(milliseconds: 450), () => setState(() => _returning.remove(id)));
  }

  void _ring() {
    final r = _round!;
    if (_solved) return;
    _waitIdle();
    widget.c.sound(Sfx.ding, volume: 0.6);
    setState(() => _bellHops++);
    if (_plate.isEmpty) {
      _sayAsk();
      return;
    }
    final l = _layout;
    if (l != null) _lookAt(l.plate.center);
    if (_plate.length == r.want) {
      _serve();
      return;
    }
    _slips++;
    widget.c.cue();
    unawaited(_shake.forward(from: 0));
    widget.c.say(_plate.length < r.want ? cookieMoreClip(r.want) : cookieFewerClip(r.want));
    setState(() => _hint = _slips >= 2);
    _after(const Duration(milliseconds: 900), () => _look.value = Offset.zero);
  }

  /// Right: it gobbles them one by one, last first, and says how many.
  void _serve() {
    final r = _round!;
    _idle?.cancel();
    setState(() => _solved = true);
    final yum = cookieYumClip(r.want);
    widget.c.say(yum);
    unawaited(_open.forward());
    final order = _plate.reversed.toList();
    for (final (k, id) in order.indexed) {
      _after(Duration(milliseconds: 250 + 200 * k), () {
        widget.c.sound(Sfx.munch, volume: 0.35);
        setState(() => _eaten.add(id));
      });
    }
    final done = Duration(milliseconds: 250 + 200 * order.length + 250);
    _after(done, () {
      unawaited(_open.reverse());
      unawaited(_chew.forward(from: 0));
      unawaited(_hop.forward(from: 0));
      _look.value = Offset.zero;
      unawaited(widget.c.finishRound(cookieResult(_slips), emoji: '🍪'));
    });
    final next = afterVoice(yum, atLeast: done + const Duration(milliseconds: 2200));
    _after(next > done ? next : done, _newRound);
  }

  String _askLabel() {
    final n = _round!.want;
    return _solved ? 'Yum! $n cookie${n == 1 ? '' : 's'}' : 'I want $n cookie${n == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    return Backdrop(
      top: const Color(0xFFFFF1E0),
      bottom: const Color(0xFFF3E6FF),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final l = _layout = _Layout.of(box.biggest);
              final spots = r.spots || _hint;
              return Stack(
                key: ValueKey(_deal),
                clipBehavior: Clip.none,
                children: [
                  Positioned.fromRect(
                    rect: l.monster,
                    child: tid(
                      'cookies.monster',
                      Semantics(
                        button: true,
                        label: 'The monster',
                        excludeSemantics: true,
                        onTap: _sayAsk,
                        child: GestureDetector(
                          excludeFromSemantics: true,
                          onTap: _sayAsk,
                          child: RepaintBoundary(
                            child: CustomPaint(painter: MonsterPainter(chew: _chew, shake: _shake, blink: _blink, open: _open, hop: _hop, look: _look, skin: MonsterSkin.purple)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: l.plate,
                    child: tid(
                      'cookies.plate',
                      Semantics(
                        label: 'Plate: ${_plate.length} cookie${_plate.length == 1 ? '' : 's'}',
                        excludeSemantics: true,
                        child: RepaintBoundary(child: CustomPaint(painter: _PlatePainter(spots: spots ? r.want : 0, cookie: l.cookie))),
                      ),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: l.jar,
                    child: DPressable(
                      id: 'cookies.jar',
                      semanticLabel: 'Cookie jar',
                      excludeSemantics: true,
                      onTap: _tapJar,
                      borderRadius: BorderRadius.circular(l.jar.width * 0.2),
                      child: Hop(count: _jarHops, child: Wiggle(count: _jarWiggles, child: const RepaintBoundary(child: CustomPaint(painter: _JarPainter(), size: Size.infinite)))),
                    ),
                  ),
                  Positioned.fromRect(
                    rect: l.bell,
                    child: DPressable(
                      id: 'cookies.bell',
                      semanticLabel: 'Bell',
                      excludeSemantics: true,
                      onTap: _ring,
                      borderRadius: BorderRadius.circular(l.bell.width / 2),
                      child: Hop(count: _bellHops, child: const RepaintBoundary(child: CustomPaint(painter: _BellPainter(), size: Size.infinite))),
                    ),
                  ),
                  for (final e in _returning.entries) _flying(e.key, from: l.spot(e.value), to: l.jar.center, size: l.cookie, shrink: true),
                  for (final (i, id) in _plate.indexed)
                    if (_eaten.contains(id)) _flying(id, from: l.spot(i), to: l.mouth, size: l.cookie, shrink: true) else _onPlate(id, i, l, fresh: !_prefilled.contains(id)),
                ],
              );
            }),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'cookies.ask',
              label: _askLabel(),
              onSayAgain: _sayAsk,
              children: [
                for (final d in '${r.want}'.split('')) GlyphView(d, height: 52 * t.scale, color: const Color(0xFF6B4FB8)),
                SizedBox(width: t.space.sm),
                SizedBox.square(dimension: 44 * t.scale, child: const CustomPaint(painter: CookiePainter())),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A cookie on the plate at [spot]: new ones fly in from the jar; the
  /// cookies the round started with are simply there.
  Widget _onPlate(int id, int spot, _Layout l, {required bool fresh}) {
    final to = l.spot(spot);
    return TweenAnimationBuilder<Offset>(
      key: ValueKey('c$id'),
      tween: Tween(begin: fresh ? l.jar.center : to, end: to),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      // In flight it ignores taps: a quick second tap on the jar would
      // otherwise catch the cookie leaving it and send it straight back.
      builder: (context, at, child) => Positioned(left: at.dx - l.cookie / 2, top: at.dy - l.cookie / 2, width: l.cookie, height: l.cookie, child: IgnorePointer(ignoring: at != to, child: child)),
      child: DPressable(
        id: 'cookies.cookie.$spot',
        semanticLabel: 'Cookie ${spot + 1}',
        excludeSemantics: true,
        onTap: () => _tapCookie(id),
        borderRadius: BorderRadius.circular(l.cookie / 2),
        child: RepaintBoundary(child: CustomPaint(painter: CookiePainter(seed: id))),
      ),
    );
  }

  /// A cookie on its way somewhere (into the mouth, back into the jar),
  /// shrinking as it goes.
  Widget _flying(int id, {required Offset from, required Offset to, required double size, bool shrink = false}) => TweenAnimationBuilder<double>(
        key: ValueKey('f$id'),
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInCubic,
        builder: (context, k, child) {
          final at = Offset.lerp(from, to, k)!;
          final s = size * (shrink ? 1 - 0.8 * k : 1);
          return Positioned(left: at.dx - s / 2, top: at.dy - s / 2, width: s, height: s, child: k >= 1 ? const SizedBox.shrink() : child!);
        },
        child: IgnorePointer(child: RepaintBoundary(child: CustomPaint(painter: CookiePainter(seed: id)))),
      );
}

/// Where the monster, plate, jar and bell stand in the play area. Wide: the
/// monster on the left, the plate above the jar and bell on the right.
/// Tall: the monster on top, then the plate, then the jar and bell.
class _Layout {
  _Layout(this.monster, this.plate, this.jar, this.bell);

  factory _Layout.of(Size a) {
    final gap = math.max(12.0, a.shortestSide * 0.03);
    if (a.width > a.height * 1.1) {
      final side = math.min(a.width * 0.38, a.height);
      final monster = Rect.fromLTWH(0, a.height - side, side, side);
      final right = Rect.fromLTRB(side + gap * 2, 0, a.width, a.height);
      final ph = math.min(right.width * 0.96 / 2, a.height * 0.5);
      final plate = Rect.fromCenter(center: Offset(right.center.dx, ph / 2 + gap / 2), width: ph * 2, height: ph);
      final rowTop = plate.bottom + gap;
      final item = math.min(a.height - rowTop, right.width * 0.36);
      final y = rowTop + (a.height - rowTop) / 2;
      return _Layout(
        monster,
        plate,
        Rect.fromCenter(center: Offset(right.left + right.width * 0.3, y), width: item * 0.86, height: item),
        Rect.fromCenter(center: Offset(right.left + right.width * 0.72, y), width: item, height: item),
      );
    }
    final side = math.min(a.width * 0.7, a.height * 0.4);
    final monster = Rect.fromLTWH((a.width - side) / 2, 0, side, side);
    final ph = math.min(a.width * 0.96 / 2, a.height * 0.26);
    final plate = Rect.fromCenter(center: Offset(a.width / 2, side + gap + ph / 2), width: ph * 2, height: ph);
    final rowTop = plate.bottom + gap;
    final item = math.min(a.height - rowTop, math.min(a.width * 0.36, a.height * 0.24));
    final y = rowTop + (a.height - rowTop) / 2;
    return _Layout(
      monster,
      plate,
      Rect.fromCenter(center: Offset(a.width * 0.3, y), width: item * 0.86, height: item),
      Rect.fromCenter(center: Offset(a.width * 0.7, y), width: item, height: item),
    );
  }

  final Rect monster, plate, jar, bell;

  Offset get mouth => monster.topLeft + Offset(MonsterPainter.mouthAt.dx * monster.width, MonsterPainter.mouthAt.dy * monster.height);
  Offset get eyes => monster.topLeft + Offset(MonsterPainter.eyesAt.dx * monster.width, MonsterPainter.eyesAt.dy * monster.height);

  /// A cookie's size: a ten frame's cell.
  double get cookie => plate.width * 0.142;

  /// Where cookie [i] (0–9) sits: two rows of five, filled row by row.
  Offset spot(int i) => _spot(plate, i);
}

Offset _spot(Rect plate, int i) => Offset(plate.left + plate.width * (0.16 + (i % 5) * 0.17), plate.top + plate.height * (i < 5 ? 0.31 : 0.69));

/// The plate: a wide white oval with a rim and, as a scaffold, a dashed
/// spot for each cookie the monster wants.
class _PlatePainter extends CustomPainter {
  const _PlatePainter({required this.spots, required this.cookie});
  final int spots;
  final double cookie;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas
      ..drawOval(r.shift(Offset(0, size.height * 0.05)), Paint()..color = const Color(0x1A2B2440))
      ..drawOval(r, Paint()..color = Colors.white)
      ..drawOval(
        r.deflate(size.height * 0.06),
        Paint()
          ..color = const Color(0xFFEADFF7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, size.height * 0.025),
      );
    final dash = Paint()
      ..color = const Color(0xFFB9A6E0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, cookie * 0.05)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < spots; i++) {
      final c = _spot(r, i);
      const n = 12;
      for (var k = 0; k < n; k += 1) {
        final a = k * 2 * math.pi / n;
        canvas.drawArc(Rect.fromCircle(center: c, radius: cookie * 0.5), a, math.pi / n, false, dash);
      }
    }
  }

  @override
  bool shouldRepaint(_PlatePainter old) => old.spots != spots || old.cookie != cookie;
}

/// A chocolate-chip cookie, painted: a golden disc, a darker edge, chips
/// placed by [seed] so no two look the same.
class CookiePainter extends CustomPainter {
  const CookiePainter({this.seed = 0});
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    canvas
      ..drawCircle(c, r * 0.96, Paint()..color = const Color(0xFFD99A4E))
      ..drawCircle(c + Offset(-r * 0.08, -r * 0.1), r * 0.74, Paint()..color = const Color(0xFFE8B66E))
      ..drawCircle(
        c,
        r * 0.94,
        Paint()
          ..color = const Color(0xFFA8662A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.08,
      );
    final rng = math.Random(seed * 13 + 5);
    final chip = Paint()..color = const Color(0xFF4A2B17);
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3 + rng.nextDouble() * 0.7;
      final d = r * (i.isEven ? 0.5 : 0.25) + rng.nextDouble() * r * 0.12;
      canvas.drawOval(Rect.fromCenter(center: c + Offset(math.cos(a) * d, math.sin(a) * d), width: r * 0.2, height: r * 0.16), chip);
    }
  }

  @override
  bool shouldRepaint(CookiePainter old) => old.seed != seed;
}

/// The cookie jar: a glass jar with a red lid, cookies stacked inside.
class _JarPainter extends CustomPainter {
  const _JarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final body = RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.06, h * 0.2, w * 0.94, h * 0.98), Radius.circular(w * 0.2));
    canvas.drawRRect(body, Paint()..color = const Color(0xFFE4F3FA));
    canvas
      ..save()
      ..clipRRect(body);
    final cookie = w * 0.3;
    for (final (x, y, s) in const [(0.28, 0.85, 1), (0.52, 0.86, 2), (0.76, 0.84, 3), (0.38, 0.68, 4), (0.64, 0.69, 5), (0.5, 0.52, 6)]) {
      canvas
        ..save()
        ..translate(w * x - cookie / 2, h * y - cookie / 2);
      CookiePainter(seed: s).paint(canvas, Size.square(cookie));
      canvas.restore();
    }
    canvas
      ..restore()
      // A glint on the glass.
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.16, h * 0.3, w * 0.07, h * 0.4), Radius.circular(w * 0.04)), Paint()..color = Colors.white.withValues(alpha: 0.75))
      ..drawRRect(
        body,
        Paint()
          ..color = const Color(0xFF8DBFD6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, w * 0.035),
      )
      // The lid and its knob.
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.12, h * 0.1, w * 0.88, h * 0.22), Radius.circular(w * 0.05)), Paint()..color = const Color(0xFFE5484D))
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.4, h * 0.02, w * 0.6, h * 0.11), Radius.circular(w * 0.05)), Paint()..color = const Color(0xFFC0343A));
  }

  @override
  bool shouldRepaint(_JarPainter old) => false;
}

/// A shop counter bell: a golden dome on a dark base, a button on top.
class _BellPainter extends CustomPainter {
  const _BellPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2 + s * 0.08);
    final ink = Paint()
      ..color = const Color(0xFF8A5A10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, s * 0.025);
    // The base.
    final base = RRect.fromRectAndRadius(Rect.fromCenter(center: c + Offset(0, s * 0.2), width: s * 0.86, height: s * 0.14), Radius.circular(s * 0.05));
    canvas.drawRRect(base, Paint()..color = const Color(0xFF5B4A7A));
    // The dome, with a shine.
    final dome = Rect.fromCenter(center: c + Offset(0, s * 0.13), width: s * 0.72, height: s * 0.7);
    final path = Path()
      ..moveTo(dome.left, dome.center.dy)
      ..arcTo(dome, math.pi, math.pi, false)
      ..close();
    canvas
      ..drawPath(path, Paint()..color = const Color(0xFFF5C542))
      ..drawArc(dome.deflate(s * 0.08), math.pi * 1.15, math.pi * 0.3, false, Paint()
        ..color = Colors.white.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.04
        ..strokeCap = StrokeCap.round)
      ..drawPath(path, ink)
      // The plunger.
      ..drawRect(Rect.fromCenter(center: Offset(c.dx, dome.top - s * 0.02), width: s * 0.05, height: s * 0.08), Paint()..color = const Color(0xFF8A5A10))
      ..drawOval(Rect.fromCenter(center: Offset(c.dx, dome.top - s * 0.07), width: s * 0.2, height: s * 0.08), Paint()..color = const Color(0xFFF5C542))
      ..drawOval(Rect.fromCenter(center: Offset(c.dx, dome.top - s * 0.07), width: s * 0.2, height: s * 0.08), ink);
  }

  @override
  bool shouldRepaint(_BellPainter old) => false;
}
