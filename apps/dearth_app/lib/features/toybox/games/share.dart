import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'cookies.dart';
import 'game_widgets.dart';
import 'monster.dart';
import 'voice_widgets.dart';

/// Fair Share (SPEC FR-TOY-03, Appendix B: sharing equally). Two or three
/// of Feed the Monster's monsters with empty plates, and a tray of
/// cupcakes: "Share the cupcakes so everyone has the same!" A tap on a
/// plate gives it one (and says how many it has), a tap on a cupcake
/// takes it back, and the bell checks. Fair and square: everyone eats —
/// "Three each! Fair and square!" Unequal: the one with fewest shakes
/// and complains; equal but more still on the tray: "There are more to
/// share!" — a slip either way, and the cupcakes stay to fix. After two
/// slips each plate shows dotted spots for its fair share. The top level
/// always leaves one over: "One left over, for later!"
class ShareGame extends StatefulWidget {
  const ShareGame(this.c, {super.key});
  final GameController c;

  @override
  State<ShareGame> createState() => ShareGameState();
}

@visibleForTesting
class ShareGameState extends State<ShareGame> with TickerProviderStateMixin {
  ShareRound? _round;

  /// Cupcakes on each plate.
  late List<int> _plates;
  int _tray = 0, _slips = 0, _deal = 0, _bellHops = 0, _flightId = 0;
  bool _hint = false, _solved = false, _toldBell = false;

  /// Cupcakes flying in to each plate, and to the tray, not drawn yet.
  final _coming = <int, int>{};
  int _comingTray = 0;

  /// Cupcakes eaten off each plate during the celebration.
  final _eaten = <int, int>{};

  /// Flights under way: id → (from, to).
  final _flights = <int, (Offset, Offset)>{};
  final _timers = <Timer>[];
  Timer? _idle, _blinker;
  late final List<_Puppet> _puppets;
  _Layout? _layout;

  @visibleForTesting
  ShareRound get debugRound => _round!;

  @visibleForTesting
  List<int> get debugPlates => List.of(_plates);

  @visibleForTesting
  int get debugTray => _tray;

  @visibleForTesting
  bool get debugHint => _hint;

  @visibleForTesting
  bool get debugSolved => _solved;

  @override
  void initState() {
    super.initState();
    _puppets = [for (var i = 0; i < 3; i++) _Puppet(this)];
    _plates = [0, 0, 0];
    _newRound();
    // One blinker for the crowd: they blink in rotation, never together.
    _blinker = Timer.periodic(const Duration(milliseconds: 4100), (t) {
      final p = _puppets[t.tick % _puppets.length];
      p.blink.forward(from: 0).then((_) => p.blink.reverse());
    });
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _idle?.cancel();
    _blinker?.cancel();
    for (final p in _puppets) {
      p.dispose();
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
    final r = _round = shareRound(widget.c.level, widget.c.random, last: _round);
    _plates = [for (var i = 0; i < r.monsters; i++) 0];
    _tray = r.treats;
    _coming.clear();
    _comingTray = 0;
    _eaten.clear();
    _flights.clear();
    _slips = 0;
    _hint = _solved = false;
    _deal++;
    for (final p in _puppets) {
      p.look.value = Offset.zero;
      p
        ..stop()
        ..zero();
    }
    // A beat for the round to land, then the order; the bell's job is
    // explained once a session (Cookie Count's bell clip).
    _after(const Duration(milliseconds: 600), () {
      widget.c.say(VoiceLine.shareAsk);
      if (!_toldBell) {
        _toldBell = true;
        _after(afterVoice(VoiceLine.shareAsk), () => widget.c.say(VoiceLine.cookiesBell));
      }
    });
    _waitIdle();
    if (mounted) setState(() {});
  }

  void _sayAsk() => widget.c.say(VoiceLine.shareAsk);

  /// A long pause asks again. Not a slip.
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 11), () {
      if (!mounted || _solved) return;
      _sayAsk();
      _waitIdle();
    });
  }

  void _lookAtPlate(int i) {
    final l = _layout;
    if (l == null) return;
    for (var m = 0; m < _round!.monsters; m++) {
      final eyes = l.eyes(m);
      final d = l.plates[i].center - eyes;
      _puppets[m].look.value = d.distance < 1 ? Offset.zero : d / math.max(d.distance, l.monsters[m].width * 0.6);
    }
  }

  /// A tap on a plate: one cupcake from the tray, if there is one.
  void _give(int i) {
    if (_solved) return;
    _waitIdle();
    _lookAtPlate(i);
    if (_tray == 0) {
      // The tray is empty: a wiggle, not a slip.
      widget.c.sound(Sfx.boing, volume: 0.4);
      return;
    }
    widget.c.sound(Sfx.pop, volume: 0.5);
    final l = _layout!;
    final from = l.traySpot(_tray - 1);
    _tray--;
    _plates[i]++;
    _coming[i] = (_coming[i] ?? 0) + 1;
    _fly(from, l.spot(i, _plates[i] - 1), arriving: i);
    widget.c.say(numberClip(_plates[i]));
    setState(() {});
  }

  /// A tap on a cupcake on a plate: back to the tray.
  void _takeBack(int plate) {
    if (_solved) return;
    _waitIdle();
    if (_plates[plate] == 0) return;
    widget.c.sound(Sfx.snap, volume: 0.45);
    final l = _layout!;
    final from = l.spot(plate, _plates[plate] - 1);
    _plates[plate]--;
    _tray++;
    _comingTray++;
    _fly(from, l.traySpot(_tray - 1), arriving: -1);
    widget.c.say(numberClip(_plates[plate]));
    setState(() {});
  }

  /// A cupcake flying [from] → [to]. [arriving] is the plate it lands on,
  /// -1 the tray, or null when it shrinks into a mouth.
  void _fly(Offset from, Offset to, {int? arriving}) {
    final id = _flightId++;
    _flights[id] = (from, to);
    _after(const Duration(milliseconds: 330), () {
      if (arriving == -1) {
        _comingTray--;
      } else if (arriving != null) {
        _coming[arriving] = (_coming[arriving] ?? 1) - 1;
      }
      setState(() => _flights.remove(id));
    });
  }

  /// The bell: the round's check.
  void _ring() {
    final r = _round!;
    if (_solved) return;
    _waitIdle();
    widget.c.sound(Sfx.ding, volume: 0.6);
    setState(() => _bellHops++);
    switch (shareCheck(r, _plates, _tray)) {
      case ShareCheck.fair:
        _win();
      case ShareCheck.unequal:
        _slips++;
        widget.c.cue();
        widget.c.say(VoiceLine.shareFewer);
        unawaited(_puppets[fewestPlate(_plates)].shake.forward(from: 0));
        setState(() => _hint = _slips >= 2);
      case ShareCheck.moreToShare:
        _slips++;
        widget.c.cue();
        widget.c.say(VoiceLine.shareMore);
        setState(() => _hint = _slips >= 2);
    }
  }

  /// Fair and square: everyone eats, a cupcake at a time.
  void _win() {
    _idle?.cancel();
    setState(() => _solved = true);
    final r = _round!;
    final each = shareEachClip(r.each);
    widget.c.say(each);
    final l = _layout!;
    for (var m = 0; m < r.monsters; m++) {
      unawaited(_puppets[m].open.forward());
    }
    var step = 0;
    for (var i = 0; i < r.monsters; i++) {
      for (var k = 0; k < _plates[i]; k++) {
        final plate = i;
        _after(Duration(milliseconds: 150 * step + 200), () {
          widget.c.sound(Sfx.munch, volume: 0.35);
          setState(() => _eaten[plate] = (_eaten[plate] ?? 0) + 1);
          final shown = _plates[plate] - _eaten[plate]!;
          _fly(l.spot(plate, shown), l.mouth(plate));
        });
        step++;
      }
    }
    final done = Duration(milliseconds: 150 * step + 500);
    _after(done, () {
      for (var m = 0; m < r.monsters; m++) {
        unawaited(_puppets[m].open.reverse());
        unawaited(_puppets[m].chew.forward(from: 0));
        unawaited(_puppets[m].hop.forward(from: 0));
        _puppets[m].look.value = Offset.zero;
      }
      unawaited(widget.c.finishRound(shareResult(_slips), emoji: '🧁'));
    });
    if (r.left == 1) {
      _after(afterVoice(each), () => widget.c.say(VoiceLine.shareLeft));
    }
    _after(afterVoice(each, atLeast: done + const Duration(milliseconds: 2200)), _newRound);
  }

  String _askLabel() {
    final r = _round!;
    if (_solved) return r.left == 1 ? '${r.each} each, 1 left over' : '${r.each} each!';
    return 'Share ${r.treats} cupcakes';
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    return Backdrop(
      top: const Color(0xFFFFF0F5),
      bottom: const Color(0xFFEFF7E8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final l = _layout = _Layout.of(box.biggest, r.monsters, t.scale);
              return Stack(
                key: ValueKey(_deal),
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < r.monsters; i++)
                    Positioned.fromRect(
                      rect: l.monsters[i],
                      child: tid(
                        'share.monster.$i',
                        Semantics(
                          label: 'Monster ${i + 1}',
                          excludeSemantics: true,
                          child: RepaintBoundary(child: CustomPaint(painter: MonsterPainter(chew: _puppets[i].chew, shake: _puppets[i].shake, blink: _puppets[i].blink, open: _puppets[i].open, hop: _puppets[i].hop, look: _puppets[i].look, skin: MonsterSkin.values[i % MonsterSkin.values.length]))),
                        ),
                      ),
                    ),
                  for (var i = 0; i < r.monsters; i++) _plate(i, l),
                  _trayArea(l),
                  Positioned.fromRect(
                    rect: l.bell,
                    child: DPressable(
                      id: 'share.bell',
                      semanticLabel: 'Bell',
                      excludeSemantics: true,
                      onTap: _ring,
                      borderRadius: BorderRadius.circular(l.bell.width / 2),
                      child: Hop(count: _bellHops, child: const RepaintBoundary(child: CustomPaint(painter: BellPainter(), size: Size.infinite))),
                    ),
                  ),
                  for (final e in _flights.entries) _flight(e.key, e.value),
                ],
              );
            }),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'share.ask',
              label: _askLabel(),
              onSayAgain: _sayAsk,
              children: [DEmoji('🧁', size: 44 * t.scale)],
            ),
          ),
        ],
      ),
    );
  }

  /// One plate: the plate, its cupcakes (each tappable back to the tray),
  /// and the tap that gives it one.
  Widget _plate(int i, _Layout l) {
    final shown = _plates[i] - (_coming[i] ?? 0);
    return Positioned.fromRect(
      rect: l.plates[i],
      child: Stack(
        children: [
          tid(
            'share.plate.$i',
            Semantics(
              label: 'Plate ${i + 1}: ${_plates[i]} cupcake${_plates[i] == 1 ? '' : 's'}',
              excludeSemantics: true,
              child: GestureDetector(
                excludeFromSemantics: true,
                behavior: HitTestBehavior.opaque,
                onTap: () => _give(i),
                child: RepaintBoundary(child: CustomPaint(size: Size.infinite, painter: _PlatePainter(spots: _hint ? _round!.each : 0))),
              ),
            ),
          ),
          for (var k = 0; k < shown; k++)
            Positioned.fromRect(
              // Inside the plate's own box: local, not play-area, coords.
              rect: l.spotRect(i, k).shift(-l.plates[i].topLeft),
              child: tid(
                'share.cupcake.$i.$k',
                Semantics(
                  label: 'Cupcake ${k + 1} on plate ${i + 1}',
                  excludeSemantics: true,
                  child: GestureDetector(
                    excludeFromSemantics: true,
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _takeBack(i),
                    child: Center(child: DEmoji('🧁', size: l.cupcake)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _trayArea(_Layout l) {
    final shown = _tray - _comingTray;
    return Positioned.fromRect(
      rect: l.tray,
      child: Stack(
        children: [
          tid(
            'share.tray',
            Semantics(
              label: 'Tray: $_tray cupcake${_tray == 1 ? '' : 's'}',
              excludeSemantics: true,
              child: const RepaintBoundary(child: CustomPaint(size: Size.infinite, painter: _TrayPainter())),
            ),
          ),
          for (var k = 0; k < shown; k++)
            Positioned.fromRect(
              rect: l.trayRect(k).shift(-l.tray.topLeft),
              child: IgnorePointer(child: Center(child: DEmoji('🧁', size: l.cupcake))),
            ),
        ],
      ),
    );
  }

  /// A cupcake on its way somewhere, shrinking into the mouth.
  Widget _flight(int id, (Offset, Offset) ends) => TweenAnimationBuilder<Offset>(
        key: ValueKey('s$id'),
        tween: Tween(begin: ends.$1, end: ends.$2),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInCubic,
        builder: (context, at, child) {
          final s = _layout?.cupcake ?? 40;
          return Positioned(left: at.dx - s / 2, top: at.dy - s / 2, width: s, height: s, child: at != ends.$2 ? child! : const SizedBox.shrink());
        },
        child: IgnorePointer(child: DEmoji('🧁', size: _layout?.cupcake ?? 40)),
      );
}

/// One monster's animation bundle.
class _Puppet {
  _Puppet(TickerProviderStateMixin vsync)
      : chew = AnimationController(vsync: vsync, duration: const Duration(milliseconds: 900)),
        shake = AnimationController(vsync: vsync, duration: const Duration(milliseconds: 650)),
        blink = AnimationController(vsync: vsync, duration: const Duration(milliseconds: 90)),
        open = AnimationController(vsync: vsync, duration: const Duration(milliseconds: 220)),
        hop = AnimationController(vsync: vsync, duration: const Duration(milliseconds: 900));

  final AnimationController chew, shake, blink, open, hop;
  final look = ValueNotifier<Offset>(Offset.zero);

  void stop() {
    for (final c in [chew, shake, blink, open, hop]) {
      c.stop();
    }
  }

  void zero() {
    for (final c in [chew, shake, blink, open, hop]) {
      c.value = 0;
    }
  }

  void dispose() {
    for (final c in [chew, shake, blink, open, hop]) {
      c.dispose();
    }
    look.dispose();
  }
}

/// Where the monsters, plates, tray and bell stand in the play area.
/// Wide: monsters across the top, plates under them, the tray along the
/// bottom with the bell beside it. Tall: the same, stacked, the bell
/// under the tray.
class _Layout {
  _Layout(this.monsters, this.plates, this.tray, this.bell, this.cupcake);
  final List<Rect> monsters;
  final List<Rect> plates;
  final Rect tray;
  final Rect bell;
  final double cupcake;

  factory _Layout.of(Size a, int count, double scale) {
    final gap = math.max(12.0, a.shortestSide * 0.03);
    final wide = a.width > a.height;
    final mb = wide ? math.min(a.width / count * 0.8, a.height * 0.42) : math.min(a.width / count * 0.9, a.height * 0.36);
    final ps = mb * 0.56;
    final ch = math.min(mb * 0.3, 64 * scale);
    final total = count * mb + (count - 1) * math.max(8.0, mb * 0.1);
    final top = (a.width - total) / 2;
    final monsters = [
      for (var i = 0; i < count; i++) Rect.fromLTWH(top + i * (mb + math.max(8.0, mb * 0.1)), 0, mb, mb),
    ];
    final plates = [
      for (var i = 0; i < count; i++) Rect.fromCenter(center: Offset(monsters[i].center.dx, mb + gap * 0.6 + ps / 2), width: ps, height: ps),
    ];
    final th = ch * 2.6;
    final bellD = math.max(72 * scale, math.min(150 * scale, wide ? a.height * 0.2 : a.width * 0.35));
    final Rect tray, bell;
    if (wide) {
      final trayTop = a.height - th;
      tray = Rect.fromLTWH(0, trayTop, a.width - bellD - gap * 2, th);
      bell = Rect.fromLTWH(a.width - bellD, trayTop + (th - bellD) / 2, bellD, bellD);
    } else {
      final trayTop = mb + gap * 0.6 + ps + gap;
      tray = Rect.fromLTWH(a.width * 0.02, trayTop, a.width * 0.96, th);
      bell = Rect.fromCenter(center: Offset(a.width / 2, trayTop + th + gap + bellD / 2), width: bellD, height: bellD);
    }
    return _Layout(monsters, plates, tray, bell, ch);
  }

  Offset mouth(int i) => monsters[i].topLeft + Offset(MonsterPainter.mouthAt.dx * monsters[i].width, MonsterPainter.mouthAt.dy * monsters[i].height);
  Offset eyes(int i) => monsters[i].topLeft + Offset(MonsterPainter.eyesAt.dx * monsters[i].width, MonsterPainter.eyesAt.dy * monsters[i].height);

  /// Cupcake [k]'s spot on plate [i]: rows of up to three, centered.
  Rect spotRect(int i, int k) {
    final r = plates[i];
    final n = k + 1;
    final rows = (n + 2) ~/ 3;
    final row = k ~/ 3;
    final m = math.min(3, n - row * 3);
    final inRow = k % 3;
    final dx = (inRow - (m - 1) / 2) * r.width * 0.3;
    final dy = (row - (rows - 1) / 2) * r.height * 0.3;
    return Rect.fromCenter(center: r.center + Offset(dx, dy), width: cupcake, height: cupcake);
  }

  Offset spot(int i, int k) => spotRect(i, k).center;

  /// Cupcake [k]'s spot on the tray: rows of up to six, centered.
  Rect trayRect(int k) {
    final n = k + 1;
    final rows = (n + 5) ~/ 6;
    final row = k ~/ 6;
    final m = math.min(6, n - row * 6);
    final inRow = k % 6;
    final dx = (inRow - (m - 1) / 2) * cupcake * 1.1;
    final dy = (row - (rows - 1) / 2) * cupcake * 1.1;
    return Rect.fromCenter(center: tray.center + Offset(dx, dy), width: cupcake, height: cupcake);
  }

  Offset traySpot(int k) => trayRect(k).center;
}

/// A round white plate with a rim, and (after two slips) a dashed spot for
/// each cupcake of its fair share.
class _PlatePainter extends CustomPainter {
  const _PlatePainter({required this.spots});
  final int spots;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    canvas
      ..drawOval(Rect.fromCircle(center: c + Offset(0, s * 0.04), radius: s * 0.46), Paint()..color = const Color(0x142B2440))
      ..drawCircle(c, s * 0.46, Paint()..color = Colors.white)
      ..drawCircle(
        c,
        s * 0.39,
        Paint()
          ..color = const Color(0xFFEFEAF6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, s * 0.02),
      );
    final dash = Paint()
      ..color = const Color(0xFFB9A6E0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, s * 0.03)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < spots; i++) {
      // Where cupcake i sits: rows of up to three, centered, the same
      // math as the layout's spotRect.
      final n = i + 1;
      final rows = (n + 2) ~/ 3;
      final row = i ~/ 3;
      final m = math.min(3, n - row * 3);
      final at = Offset(size.width / 2 + (i % 3 - (m - 1) / 2) * s * 0.3, size.height / 2 + (row - (rows - 1) / 2) * s * 0.3);
      const n2 = 10;
      for (var k = 0; k < n2; k++) {
        final a = k * 2 * math.pi / n2;
        canvas.drawArc(Rect.fromCircle(center: at, radius: s * 0.14), a, math.pi / n2, false, dash);
      }
    }
  }

  @override
  bool shouldRepaint(_PlatePainter old) => old.spots != spots;
}

/// The tray: a flat basket with a rim.
class _TrayPainter extends CustomPainter {
  const _TrayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(size.height * 0.4));
    canvas
      ..drawRRect(r.shift(Offset(0, size.height * 0.06)), Paint()..color = const Color(0x142B2440))
      ..drawRRect(r, Paint()..color = const Color(0xFFE8D9C0))
      ..drawRRect(
        r,
        Paint()
          ..color = const Color(0xFFC9AE8C)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, size.height * 0.05),
      );
  }

  @override
  bool shouldRepaint(_TrayPainter old) => false;
}
