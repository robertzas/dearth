import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

const Color _ink = Color(0xFF7C4DFF);

/// Letter & Name Tracing (SPEC FR-TOY-03, Appendix B: pre-writing). Lines
/// first, then curves, then capitals, then her own name, a letter at a
/// time. A green dot shows where each stroke starts and little arrows which
/// way it goes; the ink follows her finger only along the path. Each letter
/// is named as it comes up and sounded out when it's done ("B. Buh, buh,
/// ball.").
class TracingGame extends StatefulWidget {
  const TracingGame(this.c, {super.key});
  final GameController c;

  @override
  State<TracingGame> createState() => TracingGameState();
}

@visibleForTesting
class TracingGameState extends State<TracingGame> {
  List<String> _glyphs = const [];
  int _at = 0, _slips = 0, _strokes = 0, _deal = 0;
  bool _done = false;
  Timer? _next, _ask;

  @visibleForTesting
  List<String> get debugGlyphs => _glyphs;

  @visibleForTesting
  int get debugAt => _at;

  bool get _isName => _glyphs.length > 1;

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  @override
  void dispose() {
    _next?.cancel();
    _ask?.cancel();
    super.dispose();
  }

  void _newRound() {
    _glyphs = letterTraceRound(widget.c.level, widget.c.random, name: widget.c.kid.name, last: _glyphs.length == 1 ? _glyphs.single : null);
    _at = 0;
    _slips = 0;
    _strokes = 0;
    _done = false;
    _deal++;
    _ask?.cancel();
    _ask = Timer(const Duration(milliseconds: 600), () {
      if (_isName) {
        widget.c.say(VoiceLine.traceName);
        _ask = Timer(const Duration(milliseconds: 1800), _sayGlyph);
      } else {
        _sayGlyph();
      }
    });
    if (mounted) setState(() {});
  }

  void _sayGlyph() {
    final g = _glyphs[_at];
    if (!glyphFor(g).isStroke) widget.c.say(letterNameClip(g));
  }

  void _onTrace(TraceEvent e, Tracer t) {
    switch (e) {
      case TraceEvent.strayed:
        widget.c.cue();
      case TraceEvent.strokeDone:
        widget.c.sound(Sfx.pop, volume: 0.5);
      case TraceEvent.glyphDone:
        _glyphDone(t);
      case TraceEvent.none || TraceEvent.started || TraceEvent.moved:
        break;
    }
  }

  void _glyphDone(Tracer t) {
    _slips += t.slips;
    _strokes += t.glyph.strokes.length;
    widget.c.sound(Sfx.sparkle);
    final g = _glyphs[_at];
    final last = _at == _glyphs.length - 1;
    if (!t.glyph.isStroke && !(last && _isName)) widget.c.say(letterClip(g));
    if (!last) {
      _next = Timer(const Duration(milliseconds: 2200), () {
        if (!mounted) return;
        setState(() => _at++);
        _sayGlyph();
      });
      return;
    }
    setState(() => _done = true);
    if (_isName) widget.c.say(VoiceLine.traceNameDone);
    unawaited(widget.c.finishRound(resultFor(_slips, allowed: _strokes), emoji: '✏️'));
    _next = Timer(const Duration(milliseconds: 3600), _newRound);
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final g = glyphFor(_glyphs[_at]);
    // Name letters share one band, so small letters stay small.
    final (top, bottom) = _isName ? (0.0, 14.0) : (g.isStroke ? (0.0, 10.0) : (0.0, g.bottom > 10.6 ? 14.0 : 10.0));
    final label = _isName ? 'Trace your name: ${_glyphs.join()}' : (g.isStroke ? 'Trace the line' : 'Trace ${g.char}');
    return Backdrop(
      top: const Color(0xFFFFFBF2),
      bottom: const Color(0xFFF1ECFF),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 130,
            child: TraceBoard(
              key: ValueKey('$_deal.$_at'),
              glyph: g,
              frameTop: top,
              frameBottom: bottom,
              paperLines: !g.isStroke,
              onEvent: _onTrace,
            ),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'tracing.ask',
              label: _done ? 'All traced!' : label,
              onSayAgain: () => _isName && _at == 0 ? widget.c.say(VoiceLine.traceName) : _sayGlyph(),
              children: [
                DEmoji('✏️', size: 44 * t.scale),
                SizedBox(width: t.space.sm),
                if (g.isStroke)
                  GlyphView(g.char, height: 44 * t.scale, color: _ink, weight: 1.6)
                else
                  // Her name as she writes it: done letters in color, this one
                  // in ink, the rest waiting in grey.
                  for (var i = 0; i < _glyphs.length; i++)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 2 * t.scale),
                      child: GlyphView(
                        _glyphs[i],
                        height: 52 * t.scale,
                        frameTop: 0,
                        frameBottom: 14,
                        color: i < _at || _done ? letterColor(_glyphs[i]) : (i == _at ? _ink : const Color(0xFFCFC8E0)),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Number Tracing (SPEC FR-TOY-03, Appendix B: numerals, 1–3 → 0–9). The
/// voice names the number; once it's traced, that many things pop up and
/// the voice counts them ("One, two, three.").
class NumbersGame extends StatefulWidget {
  const NumbersGame(this.c, {super.key});
  final GameController c;

  @override
  State<NumbersGame> createState() => NumbersGameState();
}

@visibleForTesting
class NumbersGameState extends State<NumbersGame> {
  static const _things = ['🍎', '⭐', '🐞', '🎈', '🐟', '🌸', '🍓', '🐥', '🦋', '🍪'];
  int? _n;
  String _thing = '🍎';
  int _shown = 0, _deal = 0;
  bool _done = false;
  Timer? _next, _ask, _count;

  @visibleForTesting
  int get debugNumber => _n!;

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  @override
  void dispose() {
    _next?.cancel();
    _ask?.cancel();
    _count?.cancel();
    super.dispose();
  }

  void _newRound() {
    final rng = widget.c.random;
    _n = numberTraceRound(widget.c.level, rng, last: _n);
    _thing = _things[rng.nextInt(_things.length)];
    _shown = 0;
    _done = false;
    _deal++;
    _ask?.cancel();
    _ask = Timer(const Duration(milliseconds: 600), _sayNumber);
    if (mounted) setState(() {});
  }

  void _sayNumber() => widget.c.say(numberClip(_n!));

  /// The pause for the cheer before counting starts, and the time each
  /// counted thing gets: a number clip runs up to ~0.75 s, and a beat of
  /// quiet after it keeps the words apart.
  static const _countLead = Duration(milliseconds: 1200);
  static const _countBeat = Duration(milliseconds: 1100);

  void _countOne() {
    setState(() => _shown++);
    widget.c.sound(Sfx.tap, volume: 0.35, rate: 1 + _shown * 0.06);
    widget.c.say(numberClip(_shown));
  }

  void _onTrace(TraceEvent e, Tracer t) {
    switch (e) {
      case TraceEvent.strayed:
        widget.c.cue();
      case TraceEvent.strokeDone:
        widget.c.sound(Sfx.pop, volume: 0.5);
      case TraceEvent.glyphDone:
        widget.c.sound(Sfx.sparkle);
        setState(() => _done = true);
        unawaited(widget.c.finishRound(resultFor(t.slips, allowed: t.glyph.strokes.length), emoji: '🔢'));
        // After the cheer, each thing pops up as the voice says its number:
        // one clip per thing, so the voice can never run ahead of what she
        // sees (a single "one, two, three" clip did, at a pace too quick to
        // follow on the frame's small speaker).
        _count = Timer(_countLead, () {
          if (!mounted) return;
          if (_n == 0) return widget.c.say(countClip(0));
          _countOne();
          _count = Timer.periodic(_countBeat, (timer) {
            if (!mounted || _shown >= _n!) return timer.cancel();
            _countOne();
          });
        });
        _next = Timer(_countLead + _countBeat * math.max(_n!, 1) + const Duration(milliseconds: 2400), _newRound);
      case TraceEvent.none || TraceEvent.started || TraceEvent.moved:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final n = _n!;
    // Not inside a Hop: its key changes with each cheer, which would start
    // the board (and its ink) over.
    final board = TraceBoard(key: ValueKey(_deal), glyph: glyphFor('$n'), onEvent: _onTrace);
    final things = tid(
      'numbers.count',
      Semantics(
        label: _done ? '$_shown of $n' : 'Nothing yet',
        excludeSemantics: true,
        child: LayoutBuilder(builder: (context, box) {
          final size = math.min(box.maxWidth / 3.4, box.maxHeight / 4.4).clamp(24.0, 110 * t.scale);
          return Center(
            child: n == 0 && _done
                ? DEmoji('🍽️', size: size * 1.6)
                : Wrap(
                    alignment: WrapAlignment.center,
                    spacing: size * 0.18,
                    runSpacing: size * 0.18,
                    children: [for (var i = 0; i < _shown; i++) Hop(count: 1, child: DEmoji(_thing, size: size))],
                  ),
          );
        }),
      ),
    );
    return Backdrop(
      top: const Color(0xFFF0FAFF),
      bottom: const Color(0xFFFFF5E8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 130,
            child: LayoutBuilder(
              builder: (context, box) => box.maxWidth > box.maxHeight
                  ? Row(children: [Expanded(flex: 3, child: board), Expanded(flex: 2, child: things)])
                  : Column(children: [Expanded(flex: 3, child: board), Expanded(flex: 2, child: things)]),
            ),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'numbers.ask',
              label: _done ? '$n!' : 'Trace $n',
              onSayAgain: _sayNumber,
              children: [DEmoji('✏️', size: 44 * t.scale), SizedBox(width: t.space.sm), GlyphView('$n', height: 48 * t.scale, color: _ink)],
            ),
          ),
        ],
      ),
    );
  }
}

/// One glyph to trace: writing lines, a soft dotted path, a green dot where
/// the stroke starts (or where she left it), arrows showing the way, and
/// ink that follows her finger. Only the first finger traces.
class TraceBoard extends StatefulWidget {
  const TraceBoard({super.key, required this.glyph, required this.onEvent, this.frameTop = 0, this.frameBottom = 10, this.paperLines = true});
  final Glyph glyph;
  final void Function(TraceEvent event, Tracer tracer) onEvent;

  /// The band the glyph sits in (glyph units): 0–10 for capitals and
  /// digits, 0–14 with room for descenders.
  final double frameTop, frameBottom;

  /// Top, middle and base lines, as on handwriting paper.
  final bool paperLines;

  @override
  State<TraceBoard> createState() => _TraceBoardState();
}

class _TraceBoardState extends State<TraceBoard> {
  late Tracer _tracer = Tracer(widget.glyph);
  final _inked = ValueNotifier<int>(0);
  int? _pointer;
  Offset _origin = Offset.zero;
  double _unit = 1;

  @override
  void didUpdateWidget(TraceBoard old) {
    super.didUpdateWidget(old);
    if (old.glyph != widget.glyph) {
      _tracer = Tracer(widget.glyph);
      _inked.value++;
    }
  }

  @override
  void dispose() {
    _inked.dispose();
    super.dispose();
  }

  math.Point<double> _toGlyph(Offset local) => math.Point((local.dx - _origin.dx) / _unit, (local.dy - _origin.dy) / _unit);

  Offset _toBoard(math.Point<double> p) => _origin + Offset(p.x * _unit, p.y * _unit);

  void _handle(TraceEvent e) {
    if (e == TraceEvent.none) return;
    _inked.value++;
    // The dot and the waypoints move when a stroke ends or she wanders off.
    if (e != TraceEvent.moved && e != TraceEvent.started) setState(() {});
    widget.onEvent(e, _tracer);
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.glyph;
    final tracer = _tracer;
    return LayoutBuilder(builder: (context, box) {
      const pad = 1.4;
      final band = widget.frameBottom - widget.frameTop;
      _unit = math.min(box.maxHeight / (band + pad * 2), box.maxWidth / (math.max(g.width, 6) + pad * 2));
      _origin = Offset((box.maxWidth - g.width * _unit) / 2, (box.maxHeight - band * _unit) / 2 - widget.frameTop * _unit);
      // About as wide as the path.
      final dot = 1.9 * _unit;
      final resume = tracer.resume;
      final pts = tracer.done ? const <math.Point<double>>[] : g.strokes[tracer.stroke];
      // Points along the rest of this stroke, for tests to trace through.
      final waypoints = [for (var i = tracer.reached; i < pts.length; i += 6) pts[i], if (pts.isNotEmpty) pts.last];
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          if (_pointer != null) return;
          _pointer = e.pointer;
          _handle(tracer.down(_toGlyph(e.localPosition)));
        },
        onPointerMove: (e) {
          if (e.pointer == _pointer) _handle(tracer.move(_toGlyph(e.localPosition)));
        },
        onPointerUp: (e) => _lift(e.pointer),
        onPointerCancel: (e) => _lift(e.pointer),
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(painter: _PaperPainter(g, _origin, _unit, lines: widget.paperLines, top: widget.frameTop)),
              ),
            ),
            Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _InkPainter(tracer, _origin, _unit, repaint: _inked)))),
            if (resume != null)
              Positioned(
                left: _toBoard(resume).dx - dot / 2,
                top: _toBoard(resume).dy - dot / 2,
                child: IgnorePointer(child: _StartDot(size: dot)),
              ),
            for (var i = 0; i < waypoints.length; i++)
              Positioned(
                left: _toBoard(waypoints[i]).dx - 6,
                top: _toBoard(waypoints[i]).dy - 6,
                // Not hit-testable: an empty box never takes the finger.
                child: tid('trace.point.$i', const SizedBox(width: 12, height: 12)),
              ),
            Positioned(
              left: 0,
              bottom: 0,
              child: tid(
                'trace.board',
                Semantics(
                  label: tracer.done ? '${g.char} traced' : 'Tracing ${g.char}: ${tracer.stroke} of ${g.strokes.length} done',
                  excludeSemantics: true,
                  child: const SizedBox(width: 12, height: 12),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  void _lift(int pointer) {
    if (pointer != _pointer) return;
    _pointer = null;
    _tracer.up();
  }
}

/// Handwriting lines and the glyph's path: a wide soft band with a dotted
/// middle.
class _PaperPainter extends CustomPainter {
  const _PaperPainter(this.g, this.origin, this.unit, {required this.lines, required this.top});
  final Glyph g;
  final Offset origin;
  final double unit;
  final bool lines;
  final double top;

  Offset _at(math.Point<double> p) => origin + Offset(p.x * unit, p.y * unit);

  @override
  void paint(Canvas canvas, Size size) {
    if (lines) {
      final line = Paint()
        ..color = const Color(0xFFBCD4F0)
        ..strokeWidth = math.max(2, unit * 0.12);
      for (final y in [0.0, 10.0]) {
        canvas.drawLine(Offset(0, origin.dy + y * unit), Offset(size.width, origin.dy + y * unit), line);
      }
      // The dashed middle line.
      final mid = origin.dy + 5 * unit;
      for (var x = 0.0; x < size.width; x += unit * 1.2) {
        canvas.drawLine(Offset(x, mid), Offset(x + unit * 0.6, mid), line);
      }
    }
    final band = Paint()
      ..color = const Color(0xFFE9E3F8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * unit
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final dots = Paint()..color = Colors.white;
    for (final s in g.strokes) {
      if (s.length == 1) {
        canvas.drawCircle(_at(s.first), unit * 1.1, Paint()..color = const Color(0xFFE9E3F8));
        continue;
      }
      final path = Path()..moveTo(_at(s.first).dx, _at(s.first).dy);
      for (final p in s.skip(1)) {
        path.lineTo(_at(p).dx, _at(p).dy);
      }
      canvas.drawPath(path, band);
      for (var i = 0; i < s.length; i += 4) {
        canvas.drawCircle(_at(s[i]), unit * 0.13, dots);
      }
    }
  }

  @override
  bool shouldRepaint(_PaperPainter old) => old.g != g || old.origin != origin || old.unit != unit || old.lines != lines;
}

/// What she has traced, and arrows along the rest of the current stroke.
class _InkPainter extends CustomPainter {
  _InkPainter(this.t, this.origin, this.unit, {required Listenable repaint}) : super(repaint: repaint);
  final Tracer t;
  final Offset origin;
  final double unit;

  Offset _at(math.Point<double> p) => origin + Offset(p.x * unit, p.y * unit);

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3 * unit
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void run(List<math.Point<double>> s, int upTo) {
      if (s.length == 1) {
        canvas.drawCircle(_at(s.first), unit * 0.85, Paint()..color = _ink);
        return;
      }
      if (upTo < 1) return;
      final path = Path()..moveTo(_at(s.first).dx, _at(s.first).dy);
      for (final p in s.skip(1).take(upTo)) {
        path.lineTo(_at(p).dx, _at(p).dy);
      }
      canvas.drawPath(path, ink);
    }

    final strokes = t.glyph.strokes;
    for (var i = 0; i < strokes.length && i < t.stroke; i++) {
      run(strokes[i], strokes[i].length);
    }
    if (t.done) return;
    final s = strokes[t.stroke];
    if (s.length > 1) run(s, t.reached);
    // Arrows: little chevrons pointing the way, every two and a half units.
    final arrow = Paint()
      ..color = const Color(0xFFB4A6E0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.22 * unit
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = t.reached + 6; i + 2 < s.length; i += 10) {
      final a = _at(s[i]), b = _at(s[i + 2]);
      final d = b - a;
      if (d.distance == 0) continue;
      final dir = d / d.distance;
      final side = Offset(-dir.dy, dir.dx);
      final tip = a + dir * unit * 0.35;
      canvas.drawPath(
        Path()
          ..moveTo((tip - dir * unit * 0.45 + side * unit * 0.4).dx, (tip - dir * unit * 0.45 + side * unit * 0.4).dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo((tip - dir * unit * 0.45 - side * unit * 0.4).dx, (tip - dir * unit * 0.45 - side * unit * 0.4).dy),
        arrow,
      );
    }
  }

  @override
  bool shouldRepaint(_InkPainter old) => old.t != t || old.origin != origin || old.unit != unit;
}

/// Where to put her finger: a green dot that gently breathes (at 30 fps on
/// the slowest displays; still with reduced motion).
class _StartDot extends StatefulWidget {
  const _StartDot({required this.size});
  final double size;

  @override
  State<_StartDot> createState() => _StartDotState();
}

class _StartDotState extends State<_StartDot> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _phase = ValueNotifier<double>(0);
  int _frames = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_ticker.start());
  }

  @override
  void dispose() {
    _ticker.dispose();
    _phase.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    final t = DTheme.of(context);
    if (t.reducedMotion) return;
    if (t.policy.ambientFps < 60 && (_frames++).isOdd) return;
    _phase.value = (elapsed.inMilliseconds % 1400) / 1400;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
        valueListenable: _phase,
        builder: (context, p, child) => Transform.scale(scale: 1 + 0.14 * math.sin(p * math.pi), child: child),
        // Painted once; only the scale changes.
        child: RepaintBoundary(
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: const Color(0xFF3CC36B),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: widget.size * 0.14),
            ),
          ),
        ),
      );
}
