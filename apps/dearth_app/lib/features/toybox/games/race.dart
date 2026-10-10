import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Animal Race (SPEC FR-TOY-03, Appendix B: ordinal words). Three animals
/// (then five) race right to left across their lanes, cross the finish
/// line in order and coast to a stop — the order stays on screen. "Who
/// came second?" She taps the animal and a ribbon pins on; a wrong one
/// hops and says its own place ("I came third!"), so a slip is still
/// ordinal practice. The say-again button replays the race. At the top
/// she ribbons all five, first to fifth.
class RaceGame extends StatefulWidget {
  const RaceGame(this.c, {super.key});
  final GameController c;

  @override
  State<RaceGame> createState() => RaceGameState();
}

@visibleForTesting
class RaceGameState extends State<RaceGame> with TickerProviderStateMixin {
  RaceRound? _round;

  /// Seconds since the gun; null before it.
  final _t = ValueNotifier<double?>(null);
  late final Ticker _ticker = createTicker(_tick);
  int _frames = 0;
  bool _racing = true;

  int _ask = 0, _slips = 0, _deal = 0;
  bool _hint = false, _solved = false;

  /// Ribbons pinned: lane → place.
  final _ribbons = <int, int>{};
  final _wiggles = <int, int>{};
  final _timers = <Timer>[];
  Timer? _idle;

  @visibleForTesting
  RaceRound get debugRound => _round!;

  /// How far the race has run, in seconds; null before the gun.
  @visibleForTesting
  double? get debugT => _t.value;

  @visibleForTesting
  bool get debugRacing => _racing;

  @visibleForTesting
  bool get debugHint => _hint;

  @visibleForTesting
  bool get debugSolved => _solved;

  /// The ribbons pinned so far: lane → place.
  @visibleForTesting
  Map<int, int> get debugRibbons => Map.of(_ribbons);

  double get _raceEnd => 2.4 + (_round!.lanes - 1) * 0.35 + 0.9;

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
    _idle?.cancel();
    _ticker.dispose();
    _t.dispose();
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
    _ticker.stop();
    _idle?.cancel();
    _round = raceRound(widget.c.level, widget.c.random, last: _round);
    _ask = 0;
    _slips = 0;
    _hint = _solved = false;
    _ribbons.clear();
    _wiggles.clear();
    _deal++;
    _t.value = null;
    _racing = true;
    // A beat for the round to land, then the gun starts the race.
    _after(const Duration(milliseconds: 600), () {
      widget.c.sound(Sfx.ding, volume: 0.4);
      widget.c.say(VoiceLine.raceGo);
      _frames = 0;
      _t.value = 0;
      unawaited(_ticker.start());
    });
    if (mounted) setState(() {});
  }

  void _tick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    if (t >= _raceEnd) {
      _ticker.stop();
      _t.value = _raceEnd;
      setState(() => _racing = false);
      _askNow();
      _waitIdle();
      return;
    }
    // The race is the game's own animation, but on the slowest displays
    // every other frame is plenty.
    if (DTheme.of(context).policy.ambientFps < 60 && (_frames++).isOdd) return;
    _t.value = t;
  }

  int get _want => _round!.asks[_ask.clamp(0, _round!.asks.length - 1)];

  void _askNow() => widget.c.say(raceAskClip(_want));

  /// The 🔊 button: the race runs again, then the same question. Not a
  /// slip, and the ribbons she has won stay pinned.
  void _replay() {
    if (_racing || _solved) return;
    _idle?.cancel();
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    widget.c.say(VoiceLine.raceGo);
    _frames = 0;
    _t.value = 0;
    setState(() => _racing = true);
    unawaited(_ticker.start());
  }

  /// A long pause asks again. Not a slip.
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 11), () {
      if (!mounted || _solved || _racing) return;
      _askNow();
      _waitIdle();
    });
  }

  void _pick(int lane) {
    final r = _round!;
    if (_racing || _solved) return;
    _waitIdle();
    final place = r.places[lane];
    final want = _want;
    final right = want == 0 ? place == r.lanes : place == want;
    if (!right) {
      _slips++;
      widget.c.cue();
      widget.c.say(raceCameClip(place));
      setState(() {
        _wiggles[lane] = (_wiggles[lane] ?? 0) + 1;
        _hint = _slips >= 2;
      });
      return;
    }
    widget.c.sound(Sfx.sparkle);
    widget.c.say(racePlaceClip(place));
    setState(() => _ribbons[lane] = place);
    _ask++;
    if (_ask < r.asks.length) {
      _after(afterVoice(racePlaceClip(place)), _askNow);
      return;
    }
    setState(() => _solved = true);
    unawaited(widget.c.finishRound(raceResult(_slips), emoji: '🏁'));
    _after(const Duration(milliseconds: 3200), _newRound);
  }

  String _askLabel() {
    final r = _round!;
    if (_racing) return 'Ready, set, go!';
    if (_solved) return r.asks.length > 1 ? 'Yes! All in order' : 'Yes! ${ordinalWord(r.asks.first)}';
    final want = _want;
    if (r.asks.length > 1) return 'Put them in order: ${ordinal(want)}';
    return 'Who came ${ordinal(want)}?';
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    return Backdrop(
      top: const Color(0xFFE3F6FF),
      bottom: const Color(0xFFE6F7DA),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final wide = box.maxWidth > box.maxHeight;
              final trackW = wide ? box.maxWidth : box.maxWidth * 0.92;
              final laneH = math.min(box.maxHeight / r.lanes, 230 * t.scale);
              final track = Rect.fromCenter(center: Offset(box.maxWidth / 2, box.maxHeight / 2), width: trackW, height: laneH * r.lanes);
              return Stack(
                key: ValueKey(_deal),
                clipBehavior: Clip.none,
                children: [
                  Positioned.fromRect(
                    rect: track,
                    child: RepaintBoundary(child: CustomPaint(size: track.size, painter: _TrackPainter(round: r, t: _t, ribbons: Map.of(_ribbons), hintLane: _hint ? _wantedLane : -1, listenable: _t))),
                  ),
                  for (var lane = 0; lane < r.lanes; lane++) _animalBox(lane, track, laneH),
                ],
              );
            }),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'race.ask',
              label: _askLabel(),
              onSayAgain: _replay,
              // While she answers, the ribbon she's looking for: the place
              // asked, on the rosette the winner will wear.
              children: [
                if (_racing || _solved)
                  DEmoji('🏁', size: 44 * t.scale)
                else
                  SizedBox.square(dimension: 64 * t.scale, child: CustomPaint(painter: _RosettePainter(_want == 0 ? r.lanes : _want, last: _want == 0))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int get _wantedLane {
    final r = _round!;
    final want = _want;
    if (want == 0) return r.places.indexOf(r.lanes);
    return r.places.indexOf(want);
  }

  /// A box over where lane [lane]'s animal comes to rest.
  Widget _animalBox(int lane, Rect track, double laneH) {
    final r = _round!;
    final (emoji, name) = kRacers[r.racers[lane]];
    final place = r.places[lane];
    final rest = _restX(lane, track);
    final side = math.min(laneH * 0.85, 170.0);
    final row = track.top + laneH * (lane + 0.5);
    return Positioned.fromRect(
      rect: Rect.fromCenter(center: Offset(rest, row), width: side, height: side),
      child: Wiggle(
        count: _wiggles[lane] ?? 0,
        child: tid(
          'race.animal.$lane',
          Semantics(
            label: '${name[0].toUpperCase()}${name.substring(1)}, ${_racing ? 'racing' : 'came ${ordinal(place)}'}',
            excludeSemantics: true,
            child: GestureDetector(
              excludeFromSemantics: true,
              behavior: HitTestBehavior.opaque,
              onTap: () => _pick(lane),
            ),
          ),
        ),
      ),
    );
  }

  double _restX(int lane, Rect track) => track.left + track.width * (0.30 - _restFrac(lane));

  double _restFrac(int lane) {
    final r = _round!;
    final step = r.lanes == 3 ? 0.09 : 0.055;
    return (r.lanes - r.places[lane]) * step + 0.02;
  }
}

/// The track: grass lanes, the checkered finish line on the left, and the
/// racers at [t] seconds into the race (null before the gun), drawn as
/// pictures recorded once per size. Ribbons pin beside the winners, and
/// the animal to tap glows after two slips.
class _TrackPainter extends CustomPainter {
  _TrackPainter({required this.round, required this.t, required this.ribbons, required this.hintLane, required Listenable listenable}) : super(repaint: listenable);

  final RaceRound round;
  final ValueNotifier<double?> t;
  final Map<int, int> ribbons;
  final int hintLane;

  static final _pictures = <(String, double), (ui.Picture, Size)>{};


  (ui.Picture, Size) _emoji(String emoji, double height) => _pictures[(emoji, height)] ??= () {
        final rec = ui.PictureRecorder();
        final canvas = Canvas(rec);
        final tp = TextPainter(
          text: TextSpan(text: emoji, style: TextStyle(fontSize: height * 0.8, height: 1.0, inherit: false, fontFamilyFallback: const ['Noto Color Emoji', 'Apple Color Emoji', 'Segoe UI Emoji'])),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset.zero);
        return (rec.endRecording(), tp.size);
      }();

  double _x(int lane, double seconds, double w) {
    final place = round.places[lane];
    final T = 2.4 + (place - 1) * 0.35;
    const startX = 0.95, lineX = 0.30;
    if (seconds >= T) {
      final k = math.min(1.0, (seconds - T) / 0.8);
      final step = round.lanes == 3 ? 0.09 : 0.055;
      final rest = lineX - ((round.lanes - place) * step + 0.02);
      return ui.lerpDouble(lineX, rest, Curves.easeOut.transform(k))! * w;
    }
    final k = math.min(seconds / T, 1.0);
    // A little jockeying that dies out before the line.
    final wobble = 0.018 * math.sin(seconds * 7 + lane) * math.sin(k * math.pi);
    return (startX + (lineX - startX) * k + wobble) * w;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final laneH = h / round.lanes;
    // The lanes: grass, alternating a mown stripe.
    for (var lane = 0; lane < round.lanes; lane++) {
      canvas.drawRect(Rect.fromLTWH(0, laneH * lane, w, laneH), Paint()..color = lane.isEven ? const Color(0xFFA8DFA0) : const Color(0xFFBCE9B0));
    }
    // The start line on the right, where the animals wait.
    canvas
      ..drawLine(Offset(w * 0.95, 0), Offset(w * 0.95, h), Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..strokeWidth = math.max(3, w * 0.004)
        ..strokeCap = StrokeCap.round)
      // The checkered finish line on the left.
      ..drawRect(Rect.fromLTWH(w * 0.30, 0, w * 0.012, h), Paint()..color = const Color(0xFF2B2440));
    final cell = laneH * 0.2;
    for (var row = 0; row * cell < h; row++) {
      final cellRect = Rect.fromLTWH(w * 0.30 + w * 0.012 + (row.isEven ? 0 : w * 0.012), row * cell, w * 0.012, cell);
      canvas.drawRect(cellRect, Paint()..color = row.isEven ? Colors.white : const Color(0xFF2B2440));
    }
    final seconds = t.value;
    final emojiH = laneH * 0.72;
    for (var lane = 0; lane < round.lanes; lane++) {
      final (emoji, _) = kRacers[round.racers[lane]];
      final (pic, picSize) = _emoji(emoji, emojiH);
      final cx = seconds == null ? w * 0.95 : _x(lane, seconds, w);
      final cy = laneH * (lane + 0.5);
      // A soft shadow under the animal.
      canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy + emojiH * 0.38), width: picSize.width * 0.8, height: emojiH * 0.14), Paint()..color = const Color(0x222B2440));
      canvas
        ..save()
        ..translate(cx - picSize.width / 2, cy - emojiH * 0.42)
        ..drawPicture(pic)
        ..restore();
      if (hintLane == lane) {
        canvas.drawCircle(Offset(cx, cy), emojiH * 0.6, Paint()
          ..color = const Color(0x88FFD54F)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(4, w * 0.005));
      }
      final place = ribbons[lane];
      if (place != null) {
        _rosette(canvas, Offset(cx + emojiH * 0.75, cy - emojiH * 0.25), emojiH * 0.42, place);
      }
    }
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.round != round || old.hintLane != hintLane || !_same(old.ribbons, ribbons);
}

/// The rosette for the place she's asked about, in the prompt pill. "Last"
/// gets the last place's colors and the word.
class _RosettePainter extends CustomPainter {
  const _RosettePainter(this.place, {this.last = false});
  final int place;
  final bool last;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide * 0.4;
    _rosette(canvas, Offset(size.width / 2, size.height / 2 - r * 0.25), r, place, text: last ? 'last' : null);
  }

  @override
  bool shouldRepaint(_RosettePainter old) => old.place != place || old.last != last;
}

final _labels = <(String, double, int), (ui.Picture, Size)>{};

/// [text] in the Toybox's print, [height] tall, in [color], recorded once
/// (Word Pop caches its words the same way).
(ui.Picture, Size) _label(String text, double height, Color color) => _labels[(text, height, color.toARGB32())] ??= () {
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      const weight = 1.3, band = 14.0;
      final unit = height / (band + weight);
      var x = 0.0;
      for (final ch in text.split('')) {
        final g = glyphFor(ch);
        final w = (g.width + weight) * unit;
        canvas
          ..save()
          ..translate(x, 0);
        GlyphPainter(g, color: color, frameTop: 0, frameBottom: band).paint(canvas, Size(w, height));
        canvas.restore();
        x += w;
      }
      return (rec.endRecording(), Size(x, height));
    }();

/// A rosette with the place on it (or [text]): petals around a disc, two
/// tails.
void _rosette(Canvas canvas, Offset c, double r, int place, {String? text}) {
  const colors = [Color(0xFFFFC94D), Color(0xFFC9D1DC), Color(0xFFE0A26E), Color(0xFF7EA6E4), Color(0xFF7DC98F)];
  final color = colors[place - 1];
  const ink = Color(0xFF2B2440);
  // The tails.
  final tail = Paint()..color = const Color(0xFFE5484D);
  for (final dx in [-r * 0.32, r * 0.08]) {
    final path = Path()
      ..moveTo(c.dx + dx, c.dy + r * 0.5)
      ..lineTo(c.dx + dx + r * 0.3, c.dy + r * 1.3)
      ..lineTo(c.dx + dx + r * 0.55, c.dy + r * 1.3)
      ..lineTo(c.dx + dx + r * 0.25, c.dy + r * 0.5)
      ..close();
    canvas.drawPath(path, tail);
  }
  // Petals, then the disc.
  for (var p = 0; p < 8; p++) {
    final a = p * math.pi / 4;
    canvas.drawCircle(c + Offset(math.cos(a) * r * 0.8, math.sin(a) * r * 0.8), r * 0.34, Paint()..color = color.withValues(alpha: 0.75));
  }
  canvas
    ..drawCircle(c, r * 0.72, Paint()..color = color)
    ..drawCircle(c, r * 0.72, Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.09);
  final label = text ?? ordinal(place);
  // Longer words shrink to fit the disc.
  final (pic, size) = _label(label, r * (label.length > 3 ? 0.5 : 0.72), ink);
  canvas
    ..save()
    ..translate(c.dx - size.width / 2, c.dy - size.height / 2)
    ..drawPicture(pic)
    ..restore();
}

bool _same(Map<int, int> a, Map<int, int> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}
