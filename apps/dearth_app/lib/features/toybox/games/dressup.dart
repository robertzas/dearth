import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Weather Dress-Up (SPEC FR-TOY-03, Appendix B: reasoning, self-care). The
/// sky looks like today's real forecast and the voice says it ("It's snowy
/// today! What should Buddy wear?"). A painted paper-doll buddy stands in
/// the middle; under it, three things to wear for one part at a time: the
/// top, then the shoes, then the legs and one more thing. A pick that suits
/// the day goes on the buddy and the voice names it ("Boots!"); one that
/// doesn't wiggles, says its name and fades; two slips light one that
/// suits. Dressed: "Ready to go outside!" and a hop. Without a forecast the
/// game pretends ("Let's pretend it's rainy!").
class DressGame extends StatefulWidget {
  const DressGame(this.c, {super.key});
  final GameController c;

  @override
  State<DressGame> createState() => DressGameState();
}

@visibleForTesting
class DressGameState extends State<DressGame> {
  DressRound? _round;
  int _deal = 0, _pick = 0, _slips = 0, _slipsHere = 0, _hops = 0;
  bool _done = false;
  final _worn = <DressSlot, DressItem>{};
  final _tried = <DressItem>{};
  final _wiggles = <DressItem, int>{};
  final _timers = <Timer>[];
  Timer? _idle;

  @visibleForTesting
  DressRound get debugRound => _round!;

  @visibleForTesting
  Map<DressSlot, DressItem> get debugWorn => Map.unmodifiable(_worn);

  @override
  void initState() {
    super.initState();
    _newRound();
    // The forecast can still be on its way the moment the game opens: a
    // first pretend round becomes the real day if it arrives in time.
    _after(const Duration(milliseconds: 450), () {
      if (_round!.pretend && widget.c.weather != null) _newRound();
    });
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _idle?.cancel();
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
    _round = dressRound(widget.c.level, widget.c.random, weather: widget.c.weather, last: _round);
    _deal++;
    _pick = _slips = _slipsHere = 0;
    _done = false;
    _worn.clear();
    _tried.clear();
    _wiggles.clear();
    _after(const Duration(milliseconds: 600), _sayDay);
    if (mounted) setState(() {});
  }

  void _sayDay() {
    final r = _round!;
    final clip = dressDayClip(r.weather, pretend: r.pretend);
    widget.c.say(clip);
    _waitIdle();
  }

  DressPick get _current => _round!.picks[_pick];

  void _sayPick() {
    widget.c.say(dressSlotClip(_current.slot));
    _waitIdle();
  }

  void _sayAgain() => _pick == 0 ? _sayDay() : _sayPick();

  /// A long pause asks again (not a slip).
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 12), () {
      if (!mounted || _done) return;
      _sayAgain();
    });
  }

  void _choose(DressItem item) {
    if (_done) return;
    final p = _current;
    _waitIdle();
    if (!p.suits.contains(item)) {
      if (!_tried.add(item)) return;
      _slips++;
      _slipsHere++;
      widget.c.cue();
      widget.c.say(dressItemClip(item));
      setState(() => _wiggles[item] = (_wiggles[item] ?? 0) + 1);
      return;
    }
    widget.c.sound(Sfx.pop, volume: 0.5);
    final clip = dressItemClip(item);
    widget.c.say(clip);
    final last = _pick == _round!.picks.length - 1;
    setState(() {
      _worn[p.slot] = item;
      _hops++;
      if (last) _done = true;
    });
    if (last) {
      _idle?.cancel();
      _after(afterVoice(clip, atLeast: const Duration(milliseconds: 800)), () {
        widget.c.say(VoiceLine.dressDone);
        setState(() => _hops++);
        unawaited(widget.c.finishRound(dressResult(_round!, _slips), emoji: item.emoji));
        _after(afterVoice(VoiceLine.dressDone, atLeast: const Duration(milliseconds: 3200)), _newRound);
      });
      return;
    }
    _after(afterVoice(clip, atLeast: const Duration(milliseconds: 900)), () {
      setState(() {
        _pick++;
        _slipsHere = 0;
        _tried.clear();
        _wiggles.clear();
      });
      _sayPick();
    });
  }

  String _buddyLabel() {
    final r = _round!;
    final worn = [for (final s in DressSlot.values) if (_worn[s] != null) _worn[s]!.name];
    return 'Buddy: ${_worn.length} of ${r.picks.length} dressed${worn.isEmpty ? '' : ', ${worn.join(', ')}'}';
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    final (top, bottom) = switch (r.weather) {
      DressWeather.hot => (const Color(0xFFFFE08A), const Color(0xFFFFF4D6)),
      DressWeather.warm => (const Color(0xFFCDEBFF), const Color(0xFFFFF6DE)),
      DressWeather.cool => (const Color(0xFFD9E6F2), const Color(0xFFEFF3E6)),
      DressWeather.cold => (const Color(0xFFDDE7F5), const Color(0xFFF3F6FB)),
      DressWeather.rain => (const Color(0xFFB9C6D6), const Color(0xFFE3EAF1)),
      DressWeather.snow => (const Color(0xFFE6EEF7), const Color(0xFFFFFFFF)),
    };
    return Backdrop(
      top: top,
      bottom: bottom,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final wide = box.maxWidth > box.maxHeight;
              final gap = t.space.md;
              final choices = _done ? const <DressItem>[] : _current.choices;
              final tile = math.min(wide ? math.min((box.maxWidth * 0.45 - gap * 2) / 3, box.maxHeight * 0.4) : math.min((box.maxWidth - gap * 2) / 3, box.maxHeight * 0.26), 240.0 * t.scale);
              final buddy = Hop(
                count: _hops,
                child: tid(
                  'dress.buddy',
                  Semantics(
                    label: _buddyLabel(),
                    excludeSemantics: true,
                    child: _Buddy(worn: _worn, weather: r.weather),
                  ),
                ),
              );
              final picks = Wrap(
                alignment: WrapAlignment.center,
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final item in choices)
                    PictureTile(
                      id: 'dress.item.${item.name}',
                      label: '${item.name}${_tried.contains(item) ? ', tried' : ''}',
                      size: tile,
                      tried: _tried.contains(item),
                      hint: _slipsHere >= 2 && item == choices.firstWhere(_current.suits.contains),
                      wiggles: _wiggles[item] ?? 0,
                      onTap: () => _choose(item),
                      child: DEmoji(item.emoji, size: tile * 0.62),
                    ),
                ],
              );
              return KeyedSubtree(
                key: ValueKey(_deal),
                child: wide
                    ? Row(children: [Expanded(flex: 11, child: buddy), SizedBox(width: gap), Expanded(flex: 9, child: Center(child: picks))])
                    : Column(children: [Expanded(child: buddy), SizedBox(height: gap), SizedBox(height: tile + 8, child: Center(child: picks))]),
              );
            }),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'dress.ask',
              label: _done ? 'Ready to go outside' : 'It is ${r.weather.name}: ${_current.slot.name}',
              onSayAgain: _sayAgain,
              children: [DEmoji(r.weather.emoji, size: 44 * t.scale), SizedBox(width: t.space.xs), DEmoji('🧸', size: 40 * t.scale)],
            ),
          ),
        ],
      ),
    );
  }
}

/// The paper-doll buddy, painted, with what it wears placed on it: the top
/// over its body, the legs' piece over its legs, shoes at its feet, and the
/// extra where it belongs (a hat on its head, glasses on its eyes, a scarf
/// at its neck, mittens and an umbrella at its hands).
class _Buddy extends StatelessWidget {
  const _Buddy({required this.worn, required this.weather});
  final Map<DressSlot, DressItem> worn;
  final DressWeather weather;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        // The figure's box: 0.62 wide for 1 tall.
        final h = math.min(box.maxHeight, box.maxWidth / 0.62);
        final w = h * 0.62;
        Widget at(double x, double y, String emoji, double size) => Positioned(left: w * x - h * size / 2, top: h * y - h * size / 2, child: DEmoji(emoji, size: h * size));
        final extra = worn[DressSlot.extra];
        return Center(
          child: SizedBox(
            width: w,
            height: h,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _BuddyPainter()))),
                if (worn[DressSlot.legs] case final legs?) at(0.5, 0.72, legs.emoji, 0.36),
                if (worn[DressSlot.top] case final top?) at(0.5, 0.47, top.emoji, 0.42),
                if (worn[DressSlot.feet] case final feet?) at(0.5, 0.93, feet.emoji, 0.16),
                if (extra != null)
                  switch (extra) {
                    DressItem.sunhat => at(0.5, 0.1, extra.emoji, 0.2),
                    DressItem.sunglasses => at(0.5, 0.2, extra.emoji, 0.14),
                    DressItem.scarf => at(0.5, 0.31, extra.emoji, 0.17),
                    DressItem.umbrella => at(0.94, 0.3, extra.emoji, 0.3),
                    _ => at(0.9, 0.55, extra.emoji, 0.13),
                  },
              ],
            ),
          ),
        );
      });
}

/// A friendly figure in a vest and undershorts: round head with a smile,
/// arms out a little, feet apart.
class _BuddyPainter extends CustomPainter {
  const _BuddyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    const skin = Color(0xFFF2C9A5), ink = Color(0xFF2B2440), hair = Color(0xFF6B4226);
    final outline = Paint()
      ..color = const Color(0xFFB98A68)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, h * 0.006);
    final skinPaint = Paint()..color = skin;
    // Legs and arms first, then the body over them.
    final limb = Paint()
      ..color = skin
      ..strokeWidth = h * 0.07
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(Offset(w * 0.4, h * 0.62), Offset(w * 0.36, h * 0.9), limb)
      ..drawLine(Offset(w * 0.6, h * 0.62), Offset(w * 0.64, h * 0.9), limb)
      ..drawLine(Offset(w * 0.3, h * 0.38), Offset(w * 0.1, h * 0.55), limb)
      ..drawLine(Offset(w * 0.7, h * 0.38), Offset(w * 0.9, h * 0.55), limb);
    final body = RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.27, h * 0.32, w * 0.73, h * 0.64), Radius.circular(w * 0.12));
    canvas
      ..drawRRect(body, Paint()..color = const Color(0xFFF7F4EE))
      ..drawRRect(body, outline);
    // The head.
    final head = Offset(w * 0.5, h * 0.18);
    final r = h * 0.12;
    canvas
      ..drawCircle(head, r, skinPaint)
      ..drawCircle(head, r, outline)
      ..drawArc(Rect.fromCircle(center: head, radius: r * 1.04), math.pi * 1.05, math.pi * 0.9, false, Paint()..color = hair)
      ..drawCircle(head + Offset(-r * 0.36, r * 0.05), r * 0.1, Paint()..color = ink)
      ..drawCircle(head + Offset(r * 0.36, r * 0.05), r * 0.1, Paint()..color = ink)
      ..drawArc(
        Rect.fromCircle(center: head + Offset(0, r * 0.2), radius: r * 0.4),
        0.2 * math.pi,
        0.6 * math.pi,
        false,
        Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.1
          ..strokeCap = StrokeCap.round,
      )
      ..drawCircle(head + Offset(-r * 0.62, r * 0.35), r * 0.14, Paint()..color = const Color(0x55F06292))
      ..drawCircle(head + Offset(r * 0.62, r * 0.35), r * 0.14, Paint()..color = const Color(0x55F06292));
  }

  @override
  bool shouldRepaint(_BuddyPainter old) => false;
}
