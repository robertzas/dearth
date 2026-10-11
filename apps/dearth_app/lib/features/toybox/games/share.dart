import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'cookies.dart';
import 'game_widgets.dart';
import 'monster.dart';
import 'voice_widgets.dart';

/// Fair Share (SPEC FR-TOY-03, Appendix B: sharing equally). Two or three
/// of Feed the Monster's monsters with empty plates, and a tray of
/// cupcakes: "Share the cupcakes so everyone has the same!" A press
/// anywhere on a plate (or its monster) gives it one from the tray and says
/// how many it has; a drag that starts anywhere on a plate carries one of
/// its cupcakes to another plate or back to the tray, and one that starts
/// on the tray lands on the plate it's dropped on. The bell checks. Fair and square: everyone eats — "Three each! Fair
/// and square!" Unequal: the one with fewest shakes and complains; equal
/// but more still on the tray: "There are more to share!" — a slip either
/// way, and the cupcakes stay to fix. After two slips each plate shows
/// dotted spots for its fair share, and the cupcakes past them wiggle on a
/// slip. The top level always leaves one over: "One left over, for later!"
class ShareGame extends StatefulWidget {
  const ShareGame(this.c, {super.key});
  final GameController c;

  @override
  State<ShareGame> createState() => ShareGameState();
}

/// Where a dragged cupcake came from: a plate's index, or the tray.
const int _fromTray = -1;

@visibleForTesting
class ShareGameState extends State<ShareGame> with TickerProviderStateMixin {
  ShareRound? _round;

  /// Cupcakes on each plate.
  late List<int> _plates;
  int _tray = 0, _slips = 0, _deal = 0, _bellHops = 0, _flightId = 0, _trayWiggles = 0, _extraWiggles = 0;
  bool _hint = false, _solved = false, _toldBell = false;
  final _plateWiggles = <int, int>{};

  /// Cupcakes flying in to each plate, and to the tray, not drawn yet.
  final _coming = <int, int>{};
  int _comingTray = 0;

  /// Cupcakes eaten off each plate during the celebration.
  final _eaten = <int, int>{};

  /// Flights under way: id → (from, to).
  final _flights = <int, (Offset, Offset)>{};

  /// One finger plays at a time (a second finger or a resting palm can't
  /// take the cupcake in her hand): the pointer, where it went down, and
  /// what it went down on (a plate, [_fromTray], or nothing to share).
  /// Presses and drags are read from raw pointer events over the whole play
  /// area rather than per-cupcake gesture detectors: a small child's press
  /// slides, and a tap recognizer drops a press that moves past its slop
  /// (on a plate it did nothing; on a cupcake it became a drag that floated
  /// home), and a drag had to start on a cupcake exactly.
  int? _pointer, _downOn;
  Offset _downAt = Offset.zero;

  /// The plate (or [_fromTray]) the cupcake in her hand came from.
  int? _carrying;

  /// The cupcake in her hand (play-area coordinates). Only its overlay and
  /// the monsters' eyes follow it, not the whole playfield.
  final _hand = ValueNotifier<Offset>(Offset.zero);

  /// Where the cupcake in her hand would land if she let go now: it glows.
  int? _hover;
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
    _hand.dispose();
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
    _plateWiggles.clear();
    _pointer = _downOn = _carrying = _hover = null;
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
    if (l != null) _lookAt(l.plates[i].center);
  }

  /// Every monster watches [p] (play-area coordinates).
  void _lookAt(Offset p) {
    final l = _layout;
    if (l == null) return;
    for (var m = 0; m < _round!.monsters; m++) {
      final d = p - l.eyes(m);
      _puppets[m].look.value = d.distance < 1 ? Offset.zero : d / math.max(d.distance, l.monsters[m].width * 0.6);
    }
  }

  /// Cupcakes drawn on plate [i] now: the ones landed, less any eaten and
  /// the one in her hand.
  int _shownOn(int i) => _plates[i] - (_coming[i] ?? 0) - (_eaten[i] ?? 0) - (_carrying == i ? 1 : 0);

  int get _shownOnTray => _tray - _comingTray - (_carrying == _fromTray ? 1 : 0);

  /// A tap on a plate, its cupcakes or its monster: one cupcake from the
  /// tray, if there is one.
  void _give(int i) {
    if (_solved || _carrying != null) return;
    _waitIdle();
    _lookAtPlate(i);
    if (_tray == 0) {
      // The tray is empty: a wiggle, not a slip.
      widget.c.sound(Sfx.boing, volume: 0.4);
      setState(() => _plateWiggles[i] = (_plateWiggles[i] ?? 0) + 1);
      return;
    }
    widget.c.sound(Sfx.pop, volume: 0.5);
    final l = _layout!;
    final from = l.traySpot(_shownOnTray - 1, _shownOnTray);
    _tray--;
    _plates[i]++;
    _coming[i] = (_coming[i] ?? 0) + 1;
    _fly(from, l.spot(i, _plates[i] - 1, _plates[i]), arriving: i);
    widget.c.say(numberClip(_plates[i]));
    setState(() {});
  }

  /// A tap on the tray: it wiggles and the ask comes again (the plates are
  /// what she taps).
  void _tapTray() {
    if (_solved) return;
    _waitIdle();
    widget.c.sound(Sfx.boing, volume: 0.3);
    setState(() => _trayWiggles++);
    _sayAsk();
  }

  /// How far a press moves before it picks a cupcake up: a little more
  /// than a tap's slop, so a press that slides still gives.
  double _pickUpAfter(_Layout l) => math.max(kTouchSlop, l.cupcake * 0.35);

  void _down(PointerDownEvent e) {
    final l = _layout;
    if (l == null || _solved) return;
    // A new finger takes over unless the one before is carrying a cupcake
    // (a palm that landed first doesn't lock her out).
    if (_pointer != null && _carrying != null) return;
    _pointer = e.pointer;
    _downAt = e.localPosition;
    _downOn = l.target(e.localPosition);
  }

  void _move(PointerMoveEvent e) {
    final l = _layout;
    if (e.pointer != _pointer || l == null || _solved) return;
    final p = e.localPosition;
    if (_carrying == null) {
      final from = _downOn;
      if (from == null || (p - _downAt).distance < _pickUpAfter(l)) return;
      if (from == _fromTray ? _shownOnTray <= 0 : _shownOn(from) <= 0) return;
      _waitIdle();
      widget.c.sound(Sfx.blip, volume: 0.35);
      setState(() => _carrying = from);
    }
    _hand.value = p;
    _lookAt(p);
    final over = l.target(p);
    if (over != _hover) setState(() => _hover = over);
  }

  void _up(PointerUpEvent e) {
    final l = _layout;
    if (e.pointer != _pointer || l == null) return;
    final p = e.localPosition;
    final on = _downOn, from = _carrying;
    _pointer = _downOn = null;
    if (from == null) {
      // A press: it counts where it went down, however much it slid.
      if (on != null && l.target(p) == on) _press(on);
      return;
    }
    if (l.target(p) == from && (p - _downAt).distance < l.cupcake) {
      // Barely moved and still over where it started: a press that slid.
      _home(p);
      _press(from);
      return;
    }
    _drop(p);
  }

  void _cancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = _downOn = null;
    if (_carrying != null) _home(_hand.value);
  }

  void _press(int on) => on == _fromTray ? _tapTray() : _give(on);

  /// The cupcake in her hand floats back to where it came from.
  void _home(Offset at) {
    final from = _carrying, l = _layout;
    if (from == null || l == null) return;
    final home = from == _fromTray ? l.traySpot(_shownOnTray, _shownOnTray + 1) : l.spot(from, _shownOn(from), _shownOn(from) + 1);
    if (from == _fromTray) {
      _comingTray++;
    } else {
      _coming[from] = (_coming[from] ?? 0) + 1;
    }
    _fly(at, home, arriving: from);
    setState(() => _carrying = _hover = null);
  }

  /// She lets go at [at]: on a plate it lands there, on the tray it goes
  /// back, anywhere else it floats home.
  void _drop(Offset at) {
    final from = _carrying, l = _layout;
    if (from == null || l == null) return;
    final to = l.target(at);
    if (to == null || to == from) {
      _home(at);
      _lookAt(at);
      return;
    }
    _waitIdle();
    if (from == _fromTray) {
      _tray--;
    } else {
      _plates[from]--;
    }
    // It settles into its place from her finger.
    if (to == _fromTray) {
      _tray++;
      _comingTray++;
      _fly(at, l.traySpot(_tray - 1, _tray), arriving: _fromTray);
      widget.c.sound(Sfx.snap, volume: 0.45);
      widget.c.say(numberClip(_plates[from]));
    } else {
      _plates[to]++;
      _coming[to] = (_coming[to] ?? 0) + 1;
      _fly(at, l.spot(to, _plates[to] - 1, _plates[to]), arriving: to);
      _lookAtPlate(to);
      widget.c.sound(Sfx.pop, volume: 0.5);
      widget.c.say(numberClip(_plates[to]));
    }
    setState(() => _carrying = _hover = null);
  }

  /// A cupcake flying [from] → [to]. [arriving] is the plate it lands on,
  /// [_fromTray] the tray, or null when it shrinks into a mouth.
  void _fly(Offset from, Offset to, {int? arriving}) {
    final id = _flightId++;
    _flights[id] = (from, to);
    _after(const Duration(milliseconds: 330), () {
      if (arriving == _fromTray) {
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
    if (_solved || _carrying != null) return;
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
        setState(() {
          _hint = _slips >= 2;
          // With the fair share dotted in, the extras show what to move.
          if (_hint) _extraWiggles++;
        });
      case ShareCheck.moreToShare:
        _slips++;
        widget.c.cue();
        widget.c.say(VoiceLine.shareMore);
        setState(() {
          _hint = _slips >= 2;
          if (_hint) _trayWiggles++;
        });
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
    // Round robin, the way they were shared: one bite each, then again.
    var step = 0;
    for (var k = 0; k < r.each; k++) {
      for (var i = 0; i < r.monsters; i++) {
        final plate = i;
        _after(Duration(milliseconds: 170 * step + 200), () {
          widget.c.sound(Sfx.munch, volume: 0.35);
          final n = _plates[plate] - (_eaten[plate] ?? 0);
          setState(() => _eaten[plate] = (_eaten[plate] ?? 0) + 1);
          _fly(l.spot(plate, n - 1, n), l.mouth(plate));
        });
        step++;
      }
    }
    final done = Duration(milliseconds: 170 * step + 500);
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
              return Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _down,
                onPointerMove: _move,
                onPointerUp: _up,
                onPointerCancel: _cancel,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < r.monsters; i++)
                      Positioned.fromRect(
                        key: ValueKey('m$_deal-$i'),
                        rect: l.monsters[i],
                        child: tid(
                          'share.monster.$i',
                          Semantics(
                            button: true,
                            label: 'Monster ${i + 1}',
                            excludeSemantics: true,
                            onTap: () => _give(i),
                            child: RepaintBoundary(
                              child: CustomPaint(painter: MonsterPainter(chew: _puppets[i].chew, shake: _puppets[i].shake, blink: _puppets[i].blink, open: _puppets[i].open, hop: _puppets[i].hop, look: _puppets[i].look, skin: MonsterSkin.values[i % MonsterSkin.values.length])),
                            ),
                          ),
                        ),
                      ),
                    for (var i = 0; i < r.monsters; i++) ..._plate(i, l),
                    ..._trayArea(l),
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
                    for (final e in _flights.entries) _flight(e.key, e.value, l.cupcake),
                    // The cupcake in her hand, a little bigger, over everything.
                    if (_carrying != null)
                      ValueListenableBuilder<Offset>(
                        valueListenable: _hand,
                        builder: (context, at, child) => Positioned(
                          left: at.dx - l.cupcake * 0.7,
                          top: at.dy - l.cupcake * 0.7,
                          width: l.cupcake * 1.4,
                          height: l.cupcake * 1.4,
                          child: child!,
                        ),
                        child: IgnorePointer(child: RepaintBoundary(child: Center(child: DEmoji('🧁', size: l.cupcake * 1.4)))),
                      ),
                  ],
                ),
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

  /// A cupcake: its label and test id (the play area's pointer handler
  /// does the pressing and carrying).
  Widget _cake(String id, String label, VoidCallback onTap, double size) => tid(
        id,
        Semantics(
          label: label,
          excludeSemantics: true,
          onTap: onTap,
          child: Center(child: DEmoji('🧁', size: size)),
        ),
      );

  /// One plate: the plate (a tap gives it one) and its cupcakes, laid out
  /// in even rows of three for however many it holds.
  List<Widget> _plate(int i, _Layout l) {
    final r = _round!;
    final shown = _shownOn(i);
    final each = r.each;
    return [
      Positioned.fromRect(
        key: ValueKey('p$_deal-$i'),
        rect: l.plates[i],
        child: tid(
          'share.plate.$i',
          Semantics(
            button: true,
            label: 'Plate ${i + 1}: ${_plates[i]} cupcake${_plates[i] == 1 ? '' : 's'}',
            excludeSemantics: true,
            onTap: () => _give(i),
            child: Wiggle(
              count: _plateWiggles[i] ?? 0,
              child: RepaintBoundary(child: CustomPaint(size: Size.infinite, painter: _PlatePainter(spots: _hint ? each : 0, cake: l.cakeSize(each) / l.plates[i].width, glow: _hover == i && _carrying != i))),
            ),
          ),
        ),
      ),
      for (var k = 0; k < shown; k++)
        AnimatedPositioned(
          key: ValueKey('c$_deal-$i-$k'),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          left: l.spot(i, k, shown).dx - l.cakeSize(shown) / 2,
          top: l.spot(i, k, shown).dy - l.cakeSize(shown) / 2,
          width: l.cakeSize(shown),
          height: l.cakeSize(shown),
          child: Wiggle(
            count: _hint && k >= each ? _extraWiggles : 0,
            child: _cake('share.cupcake.$i.$k', 'Cupcake ${k + 1} on plate ${i + 1}', () => _give(i), l.cakeSize(shown)),
          ),
        ),
    ];
  }

  List<Widget> _trayArea(_Layout l) {
    final shown = _shownOnTray;
    return [
      Positioned.fromRect(
        rect: l.tray,
        child: tid(
          'share.tray',
          Semantics(
            label: 'Tray: $_tray cupcake${_tray == 1 ? '' : 's'}',
            excludeSemantics: true,
            onTap: _tapTray,
            child: Wiggle(
              count: _trayWiggles,
              child: RepaintBoundary(child: CustomPaint(size: Size.infinite, painter: _TrayPainter(glow: _hover == _fromTray && _carrying != _fromTray))),
            ),
          ),
        ),
      ),
      for (var k = 0; k < shown; k++)
        AnimatedPositioned(
          key: ValueKey('t$_deal-$k'),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          left: l.traySpot(k, shown).dx - l.cupcake / 2,
          top: l.traySpot(k, shown).dy - l.cupcake / 2,
          width: l.cupcake,
          height: l.cupcake,
          child: _cake('share.traycake.$k', 'Cupcake ${k + 1} on the tray', _tapTray, l.cupcake),
        ),
    ];
  }

  /// A cupcake on its way somewhere: onto a plate, back to the tray, or
  /// shrinking into a mouth.
  Widget _flight(int id, (Offset, Offset) ends, double size) => TweenAnimationBuilder<Offset>(
        key: ValueKey('s$id'),
        tween: Tween(begin: ends.$1, end: ends.$2),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInCubic,
        builder: (context, at, child) => Positioned(left: at.dx - size / 2, top: at.dy - size / 2, width: size, height: size, child: at != ends.$2 ? child! : const SizedBox.shrink()),
        child: IgnorePointer(child: Center(child: DEmoji('🧁', size: size))),
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

/// Where the monsters, plates, tray and bell stand in the play area, in
/// three bands: the monsters, their plates under them, and the tray (with
/// the bell beside it when wide, under it when tall).
class _Layout {
  _Layout(this.monsters, this.plates, this.tray, this.bell, this.cupcake);
  final List<Rect> monsters;
  final List<Rect> plates;
  final Rect tray;
  final Rect bell;

  /// A cupcake on the tray (and in flight, and in her hand).
  final double cupcake;

  factory _Layout.of(Size a, int count, double scale) {
    final gap = math.max(12.0, a.shortestSide * 0.03);
    final wide = a.width > a.height;
    final bellD = math.max(72 * scale, math.min(150 * scale, wide ? a.height * 0.2 : a.width * 0.3));
    final trayH = wide ? math.max(bellD, a.height * 0.2) : math.min(a.height * 0.15, a.width * 0.32);
    final room = a.height - trayH - gap * 2 - (wide ? 0 : bellD + gap);
    final column = a.width / count;
    final mb = math.min(column * (wide ? 0.6 : 0.8), room * 0.46);
    final ps = math.min(math.min(room - mb - gap * 0.5, column * 0.9), mb * 1.15);
    final pitch = math.max(mb, ps) + math.max(gap, column * 0.08);
    final left = (a.width - pitch * (count - 1)) / 2;
    // The bands sit together in the middle when there's height to spare.
    final used = mb + gap * 0.5 + ps + gap + trayH + (wide ? 0 : gap + bellD);
    final top = math.max(0.0, (a.height - used) / 2);
    final monsters = [for (var i = 0; i < count; i++) Rect.fromCenter(center: Offset(left + i * pitch, top + mb / 2), width: mb, height: mb)];
    final plates = [for (var i = 0; i < count; i++) Rect.fromCenter(center: Offset(monsters[i].center.dx, top + mb + gap * 0.5 + ps / 2), width: ps, height: ps)];
    final trayTop = top + mb + gap * 0.5 + ps + gap;
    // Room for twelve cupcakes in two rows of six.
    final cupcake = math.min(trayH * 0.38, math.min(ps * 0.27, (wide ? a.width - bellD - gap * 3 : a.width) / 8));
    final trayW = math.min(cupcake * 8, wide ? a.width - bellD - gap * 3 : a.width * 0.96);
    final Rect tray, bell;
    if (wide) {
      final x = (a.width - trayW - bellD - gap * 2) / 2;
      tray = Rect.fromLTWH(x, trayTop, trayW, trayH);
      bell = Rect.fromLTWH(tray.right + gap * 2, trayTop + (trayH - bellD) / 2, bellD, bellD);
    } else {
      tray = Rect.fromLTWH((a.width - trayW) / 2, trayTop, trayW, trayH);
      bell = Rect.fromCenter(center: Offset(a.width / 2, tray.bottom + gap + bellD / 2), width: bellD, height: bellD);
    }
    return _Layout(monsters, plates, tray, bell, cupcake);
  }

  Offset mouth(int i) => monsters[i].topLeft + Offset(MonsterPainter.mouthAt.dx * monsters[i].width, MonsterPainter.mouthAt.dy * monsters[i].height);
  Offset eyes(int i) => monsters[i].topLeft + Offset(MonsterPainter.eyesAt.dx * monsters[i].width, MonsterPainter.eyesAt.dy * monsters[i].height);

  /// A cupcake's size on a plate holding [n]: three to a row up to six,
  /// four to a row past that.
  double cakeSize(int n) => plates.first.width * (n <= 6 ? 0.27 : 0.2);

  /// Cupcake [k] of the [n] on plate [i] (play-area coordinates).
  Offset spot(int i, int k, int n) => plates[i].topLeft + _cakeSpot(k, n, plates[i].size);

  /// Cupcake [k] of the [n] on the tray: even rows of up to six.
  Offset traySpot(int k, int n) {
    final (col, row, inRow, rows) = _evenRows(k, n, 6);
    return tray.center + Offset((col - (inRow - 1) / 2) * cupcake * 1.15, (row - (rows - 1) / 2) * cupcake * 1.1);
  }

  /// What's under [p]: a plate's index (its monster counts as the plate),
  /// the tray, or null (the bell, or nothing). A press there gives (or
  /// wiggles the tray), a drag from there carries one of its cupcakes, and
  /// a cupcake dropped there lands on it. Generous edges, for small
  /// fingers.
  int? target(Offset p) {
    if (bell.contains(p)) return null;
    for (var i = 0; i < plates.length; i++) {
      if (plates[i].inflate(plates[i].width * 0.15).contains(p) || monsters[i].contains(p)) return i;
    }
    if (tray.inflate(cupcake * 0.5).contains(p)) return _fromTray;
    return null;
  }
}

/// Item [k] of [n] in even rows of at most [per] (the longer rows first):
/// (column, row, items in that row, rows).
(int, int, int, int) _evenRows(int k, int n, int per) {
  if (k < 0 || k >= n) return (0, 0, 1, 1);
  final rows = (n + per - 1) ~/ per;
  final base = n ~/ rows, extra = n % rows;
  var row = 0, first = 0;
  while (true) {
    final inRow = base + (row < extra ? 1 : 0);
    if (k < first + inRow) return (k - first, row, inRow, rows);
    first += inRow;
    row++;
  }
}

/// Where cupcake [k] of [n] sits on a plate of [size], from its top left:
/// even rows, three to a row up to six (four past that), centered.
Offset _cakeSpot(int k, int n, Size size) {
  final per = n <= 6 ? 3 : 4;
  final pitch = size.width * (n <= 6 ? 0.28 : 0.21);
  final (col, row, inRow, rows) = _evenRows(k, n, per);
  return Offset(size.width / 2 + (col - (inRow - 1) / 2) * pitch, size.height / 2 + (row - (rows - 1) / 2) * pitch);
}

/// A round white plate with a rim, and (after two slips) a dashed spot for
/// each cupcake of its fair share, where those cupcakes would sit.
class _PlatePainter extends CustomPainter {
  const _PlatePainter({required this.spots, required this.cake, this.glow = false});
  final int spots;

  /// A cupcake in her hand would land here.
  final bool glow;

  /// A cupcake's size, as a share of the plate's width.
  final double cake;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(size.width / 2, size.height / 2);
    canvas
      ..drawOval(Rect.fromCircle(center: c + Offset(0, s * 0.04), radius: s * 0.48), Paint()..color = const Color(0x142B2440))
      ..drawCircle(c, s * 0.48, Paint()..color = Colors.white)
      ..drawCircle(
        c,
        s * 0.42,
        Paint()
          ..color = const Color(0xFFEFEAF6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2, s * 0.02),
      );
    if (glow) {
      canvas.drawCircle(
        c,
        s * 0.44,
        Paint()
          ..color = _glow
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.07,
      );
    }
    final dash = Paint()
      ..color = const Color(0xFFB9A6E0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, s * 0.025)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < spots; i++) {
      final at = _cakeSpot(i, spots, size);
      const n = 10;
      for (var k = 0; k < n; k++) {
        final a = k * 2 * math.pi / n;
        canvas.drawArc(Rect.fromCircle(center: at, radius: s * cake * 0.5), a, math.pi / n, false, dash);
      }
    }
  }

  @override
  bool shouldRepaint(_PlatePainter old) => old.spots != spots || old.cake != cake || old.glow != glow;
}

/// Where a cupcake in her hand would land.
const _glow = Color(0xCCFFC94D);

/// The tray: a flat basket with a rim.
class _TrayPainter extends CustomPainter {
  const _TrayPainter({this.glow = false});
  final bool glow;

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
    if (glow) {
      canvas.drawRRect(
        r.deflate(size.height * 0.08),
        Paint()
          ..color = _glow
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.height * 0.08,
      );
    }
  }

  @override
  bool shouldRepaint(_TrayPainter old) => old.glow != glow;
}
