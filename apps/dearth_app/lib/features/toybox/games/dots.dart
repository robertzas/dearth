import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'dots_art.dart';
import 'dots_pictures.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// The line she draws: the tracing games' ink.
const Color _ink = Color(0xFF7C4DFF);
const Color _numberInk = Color(0xFF2B2440);
const Color _ring = Color(0xFFC9BCF2);
const Color _gold = Color(0xFFFFC93C);

/// A pentatonic climb for the joined dots (MIDI): no wrong notes, and back
/// to the bottom after ten.
const List<int> _notes = [60, 62, 64, 67, 69, 72, 74, 76, 79, 81];

double _rate(int midi) => math.pow(2, (midi - kXylophoneBaseMidi) / 12).toDouble();

/// Dot-to-Dot (SPEC FR-TOY-03, Appendix B: number order, numerals, alphabet
/// order). Numbered dots (1→5 up to 1→20, then A→M and A→Z) sit around a
/// hidden picture. She taps them in order, or draws through them with a
/// finger; each joined dot says its number or letter over a xylophone note,
/// and the line between two dots follows the picture's real outline, so the
/// shape appears as she goes. A wrong dot wiggles and the voice says which
/// one to find; after two (or a long pause) a golden ring shows it. The last
/// dot closes the shape, the picture fills in, says what it is ("It's a
/// star!") and comes alive for a few seconds.
class DotsGame extends StatefulWidget {
  const DotsGame(this.c, {super.key});
  final GameController c;

  @override
  State<DotsGame> createState() => DotsGameState();
}

@visibleForTesting
class DotsGameState extends State<DotsGame> with SingleTickerProviderStateMixin {
  // How long each part of the drawing takes (s).
  static const _grow = 0.28;
  static const _close = 0.5;
  static const _fill = 0.6;
  static const _alive = 4.4;

  late DotsRound _round;
  late DotGeometry _geo;
  final _recent = <String>[];
  int _joined = 0, _slips = 0, _misses = 0, _deal = 0, _frames = 0;
  bool _hint = false, _revealed = false;
  final _hops = <int, int>{};
  final _wiggles = <int, int>{};
  Timer? _ask, _idle, _finish, _next;
  final _tune = <Timer>[];

  // The drawing's clock (s): it only runs while something moves.
  late final Ticker _ticker = createTicker(_tick);
  double _now = 0, _base = 0, _joinedAt = -10, _doneAt = -1;
  final _clock = ValueNotifier<double>(0);

  /// Her finger, while she draws (box units).
  final _finger = ValueNotifier<Offset?>(null);
  int? _pointer, _pressed;
  Offset _downAt = Offset.zero;
  bool _drew = false;

  // Set by the layout: board pixels per box unit, and the dot size.
  double _px = 1, _dot = 40;

  @visibleForTesting
  DotsRound get debugRound => _round;

  @visibleForTesting
  int get debugJoined => _joined;

  @visibleForTesting
  int get debugSlips => _slips;

  @visibleForTesting
  bool get debugHint => _hint;

  int get _count => _round.labels.length;
  bool get _done => _joined >= _count;

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  @override
  void dispose() {
    _ask?.cancel();
    _idle?.cancel();
    _finish?.cancel();
    _next?.cancel();
    for (final t in _tune) {
      t.cancel();
    }
    _ticker.dispose();
    _clock.dispose();
    _finger.dispose();
    super.dispose();
  }

  void _newRound() {
    _round = dotsRound(widget.c.level, widget.c.random, recent: _recent);
    _recent.insert(0, _round.picture.id);
    if (_recent.length > 4) _recent.removeLast();
    _geo = DotGeometry.of(dotArtOf(_round.picture.id), _count);
    prepareDotPicture(_geo.art, _geo.path);
    _joined = 0;
    _slips = 0;
    _misses = 0;
    _hint = false;
    _revealed = false;
    _deal++;
    _hops.clear();
    _wiggles.clear();
    _joinedAt = -10;
    _doneAt = -1;
    _pointer = null;
    _pressed = null;
    _finger.value = null;
    for (final t in _tune) {
      t.cancel();
    }
    _tune.clear();
    _ask?.cancel();
    // A beat for the dots to land before the voice.
    _ask = Timer(const Duration(milliseconds: 600), _sayPrompt);
    _waitIdle();
    if (mounted) setState(() {});
  }

  String _nameClip(String label) => _round.letters ? letterNameClip(label) : numberClip(int.parse(label));
  String _findClip(String label) => _round.letters ? findLetterClip(label) : findNumberClip(int.parse(label));

  /// "Join the dots! Start at one.", then which dot comes next, then what
  /// the picture is.
  void _sayPrompt() {
    if (_done) {
      widget.c.say(dotsDoneClip(_round.picture));
    } else if (_joined == 0) {
      widget.c.say(_round.letters ? VoiceLine.dotsLetters : VoiceLine.dotsNumbers);
    } else {
      widget.c.say(_findClip(_round.labels[_joined]));
    }
  }

  /// A long pause shows the next dot and says it, without counting a slip.
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 9), () {
      if (!mounted || _done) return;
      _sayPrompt();
      setState(_showHint);
    });
  }

  void _showHint() {
    if (_hint) return;
    _hint = true;
    _hops[_joined] = (_hops[_joined] ?? 0) + 1;
  }

  void _join() {
    final i = _joined;
    _joined++;
    _misses = 0;
    _hint = false;
    _hops[i] = (_hops[i] ?? 0) + 1;
    _joinedAt = _now;
    widget.c.sound(Sfx.xylophone, volume: 0.45, rate: _rate(_notes[i % _notes.length]));
    widget.c.say(_nameClip(_round.labels[i]));
    if (_done) {
      _complete();
    } else {
      _waitIdle();
    }
    _animate();
    setState(() {});
  }

  void _slip(int dot) {
    _slips++;
    _misses++;
    widget.c.cue();
    widget.c.say(_findClip(_round.labels[_joined]));
    setState(() {
      _wiggles[dot] = (_wiggles[dot] ?? 0) + 1;
      if (_misses >= 2) _showHint();
    });
    _waitIdle();
  }

  /// The last dot: the line closes the shape with a run up the scale, the
  /// picture fills in and says what it is, the round is recorded, and a new
  /// picture comes once this one has had its moment.
  void _complete() {
    _idle?.cancel();
    _doneAt = _now + _grow;
    final closing = (_grow * 1000).round();
    for (final (k, midi) in const [72, 76, 79, 84].indexed) {
      _tune.add(Timer(Duration(milliseconds: closing + 110 * k), () => widget.c.sound(Sfx.xylophone, volume: 0.4, rate: _rate(midi))));
    }
    _finish = Timer(Duration(milliseconds: ((_grow + _close) * 1000).round()), () {
      if (!mounted) return;
      widget.c.sound(Sfx.sparkle, volume: 0.6);
      widget.c.say(dotsDoneClip(_round.picture));
      setState(() => _revealed = true);
      _finish = Timer(const Duration(milliseconds: 1500), () {
        unawaited(widget.c.finishRound(dotsResult(_slips, _count), emoji: _round.picture.emoji));
        _next = Timer(const Duration(milliseconds: 3500), _newRound);
      });
    });
  }

  // ── The clock ──────────────────────────────────────────────────────────

  bool get _moving => _now - _joinedAt < _grow || (_doneAt >= 0 && _now < _doneAt + _close + _fill + _alive);

  void _animate() {
    if (_ticker.isActive) return;
    _base = _now;
    _frames = 0;
    unawaited(_ticker.start());
  }

  void _tick(Duration elapsed) {
    _now = _base + elapsed.inMicroseconds / 1e6;
    if (!_moving) {
      _base = _now;
      _ticker.stop();
      _clock.value = _now;
      return;
    }
    // Ambient motion: 30 fps is plenty on the slowest displays.
    if (DTheme.of(context).policy.ambientFps < 60 && (_frames++).isOdd) return;
    _clock.value = _now;
  }

  // ── Her finger ─────────────────────────────────────────────────────────

  Offset _box(Offset local) => local / _px;

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _downAt = e.localPosition;
    _drew = false;
    _pressed = null;
    if (_done) return;
    final p = _box(e.localPosition);
    // Generous: a big dot, and the next one wins anything close.
    final reach = math.max(_dot * 0.85, 26.0) / _px;
    if ((_geo.points[_joined] - p).distance <= reach) {
      _join();
      _drew = true;
    } else {
      // A dot she has joined starts a line; any other dot is a slip if she
      // lifts without drawing to the right one.
      int? near;
      var best = reach;
      for (var i = 0; i < _count; i++) {
        final d = (_geo.points[i] - p).distance;
        if (d <= best) {
          best = d;
          near = i;
        }
      }
      if (near != null && near >= _joined) _pressed = near;
    }
    if (_joined > 0 && !_done) _finger.value = p;
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer || _done) return;
    final p = _box(e.localPosition);
    if ((_geo.points[_joined] - p).distance <= math.max(_dot * 0.6, 18.0) / _px) {
      _join();
      _drew = true;
    }
    _finger.value = _joined > 0 && !_done ? p : null;
  }

  void _up(PointerEvent e, {bool cancel = false}) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _finger.value = null;
    final pressed = _pressed;
    _pressed = null;
    if (cancel || _done || _drew || pressed == null) return;
    // A finger that wandered off isn't a tap on the wrong dot.
    if ((e.localPosition - _downAt).distance > math.max(_dot, 32.0)) return;
    _slip(pressed);
  }

  // ── Drawing ────────────────────────────────────────────────────────────

  String get _askLabel {
    if (_revealed) return "It's ${_round.picture.phrase}!";
    if (_done) return 'All joined';
    if (_joined == 0) return 'Start at ${_round.labels.first}';
    return 'What comes after ${_round.labels[_joined - 1]}?';
  }

  List<Widget> _pill(DTheme t) {
    if (_revealed) return [DEmoji(_round.picture.emoji, size: 48 * t.scale)];
    final s = 50 * t.scale;
    Widget mini(String text, {required bool filled}) => Container(
          width: s,
          height: s,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: filled ? _ink : Colors.white, shape: BoxShape.circle, border: Border.all(color: filled ? _ink : _ring, width: 3 * t.scale)),
          child: Text(text, style: t.text.kidTitle.copyWith(fontSize: s * (text.length > 1 ? 0.4 : 0.5), height: 1, fontWeight: FontWeight.w700, color: filled ? Colors.white : _numberInk)),
        );
    return [
      DEmoji('✏️', size: 40 * t.scale),
      SizedBox(width: t.space.sm),
      if (_joined == 0)
        mini(_round.labels.first, filled: false)
      else ...[
        mini(_round.labels[_joined - 1], filled: true),
        Icon(Icons.arrow_forward_rounded, size: 34 * t.scale, color: _numberInk),
        mini('?', filled: false),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final labels = _round.labels;
    return Backdrop(
      top: const Color(0xFFFFF8EC),
      bottom: const Color(0xFFEDEBFF),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 128,
            child: LayoutBuilder(builder: (context, box) {
              final board = math.min(box.maxWidth, box.maxHeight).floorToDouble();
              _px = board / 1000;
              _dot = dotDiameter(board, _geo);
              final lineWidth = math.max(4.0, math.min(_dot * 0.2, board * 0.013));
              return Center(
                child: SizedBox.square(
                  dimension: board,
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _down,
                    onPointerMove: _move,
                    onPointerUp: _up,
                    onPointerCancel: (e) => _up(e, cancel: true),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Positioned.fill(child: RepaintBoundary(child: _Paper())),
                        Positioned.fill(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: _BoardPainter(
                                geo: _geo,
                                joined: _joined,
                                joinedAt: _joinedAt,
                                doneAt: _doneAt,
                                clock: _clock,
                                finger: _finger,
                                lineWidth: lineWidth,
                                still: t.reducedMotion,
                              ),
                            ),
                          ),
                        ),
                        // The dots move on their own (hops, wiggles), so they
                        // repaint apart from the line and the paper.
                        Positioned.fill(
                          child: RepaintBoundary(
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                for (var i = 0; i < labels.length; i++)
                                  Positioned(
                                    left: _geo.points[i].dx * _px - _dot / 2,
                                    top: _geo.points[i].dy * _px - _dot / 2,
                                    width: _dot,
                                    height: _dot,
                                    child: tid(
                                      'dots.dot.${labels[i]}',
                                      Semantics(
                                        label: '${labels[i]}${i < _joined ? ', joined' : (_hint && i == _joined ? ', next' : '')}',
                                        excludeSemantics: true,
                                        child: _DotView(
                                          key: ValueKey('$_deal.$i'),
                                          label: labels[i],
                                          index: i,
                                          size: _dot,
                                          joined: i < _joined,
                                          hint: _hint && i == _joined,
                                          gone: _revealed,
                                          letters: _round.letters,
                                          hops: _hops[i] ?? 0,
                                          wiggles: _wiggles[i] ?? 0,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          bottom: 0,
                          child: tid(
                            'dots.board',
                            Semantics(
                              label: _revealed ? "It's ${_round.picture.phrase}!" : 'Join the dots: $_joined of ${labels.length}',
                              excludeSemantics: true,
                              child: const SizedBox(width: 12, height: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
          TopPrompt(child: PromptPill(id: 'dots.ask', label: _askLabel, onSayAgain: _sayPrompt, children: _pill(t))),
        ],
      ),
    );
  }
}

/// A sheet of paper under the dots.
class _Paper extends StatelessWidget {
  const _Paper();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(box.maxWidth * 0.06),
            border: Border.all(color: const Color(0xFFE3DCF5), width: 3),
            boxShadow: DTheme.of(context).elevation.e1,
          ),
        ),
      );
}

/// One dot: white with its number (or its letter, in the letter colors)
/// until joined, then filled with ink. It pops in with the round, hops when
/// joined or shown as the hint (a golden ring), wiggles when it's the wrong
/// one, and pops away when the picture is revealed.
class _DotView extends StatelessWidget {
  const _DotView({
    super.key,
    required this.label,
    required this.index,
    required this.size,
    required this.joined,
    required this.hint,
    required this.gone,
    required this.letters,
    required this.hops,
    required this.wiggles,
  });

  final String label;
  final int index;
  final double size;
  final bool joined, hint, gone, letters;
  final int hops, wiggles;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final face = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: joined ? _ink : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: hint ? _gold : (joined ? _ink : _ring), width: hint ? size * 0.14 : math.max(2, size * 0.07)),
        // A solid halo, not a blur: blurs are too slow on the frame.
        boxShadow: hint ? [BoxShadow(color: const Color(0x88FFD54F), spreadRadius: size * 0.22)] : null,
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: t.text.kidTitle.copyWith(
          fontSize: size * (label.length > 1 ? 0.42 : 0.5),
          height: 1,
          fontWeight: FontWeight.w700,
          color: joined ? Colors.white : (letters ? letterColor(label) : _numberInk),
        ),
      ),
    );
    // Staggered: the dots land one after another, in order.
    final popIn = t.motion(Duration(milliseconds: 260 + index * 30));
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: popIn,
      curve: Interval(index * 30 / (260 + index * 30), 1, curve: Curves.easeOutBack),
      builder: (context, k, child) => Transform.scale(scale: k, child: child),
      child: AnimatedScale(
        scale: gone ? 0 : 1,
        duration: t.motion(Duration(milliseconds: 220 + index * 12)),
        curve: Curves.easeInBack,
        child: Hop(count: hops, child: Wiggle(count: wiggles, child: face)),
      ),
    );
  }
}

/// The line she has drawn (growing into its newest dot), the line closing
/// the shape, her finger's line while she draws, and then the finished
/// picture coming alive. Drawn in the outline's 1000 box.
class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.geo,
    required this.joined,
    required this.joinedAt,
    required this.doneAt,
    required this.clock,
    required this.finger,
    required this.lineWidth,
    required this.still,
  }) : super(repaint: Listenable.merge([clock, finger]));

  final DotGeometry geo;
  final int joined;
  final double joinedAt, doneAt;
  final ValueNotifier<double> clock;
  final ValueNotifier<Offset?> finger;

  /// In board pixels.
  final double lineWidth;

  /// Reduced motion: the finished picture fills in but doesn't move.
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    final now = clock.value;
    final k = size.width / 1000;
    final w = lineWidth / k;
    canvas.save();
    canvas.scale(k);
    if (doneAt >= 0 && now >= doneAt + DotsGameState._close) {
      final alive = now - doneAt - DotsGameState._close;
      paintDotPicture(canvas, geo.art, geo.path, t: alive, reveal: Curves.easeOut.transform((alive / DotsGameState._fill).clamp(0.0, 1.0)), lineWidth: w, ink: _ink, still: still);
    } else {
      final line = Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      if (joined >= 2) {
        final grow = Curves.easeOut.transform(((now - joinedAt) / DotsGameState._grow).clamp(0.0, 1.0));
        final from = geo.dots[joined - 2], to = geo.dots[joined - 1];
        canvas.drawPath(geo.between(0, from + (to - from) * grow), line);
      }
      if (doneAt >= 0 && now >= doneAt) {
        final close = Curves.easeInOut.transform(((now - doneAt) / DotsGameState._close).clamp(0.0, 1.0));
        final from = geo.dots.last;
        canvas.drawPath(geo.between(from, from + (geo.length - from) * close), line);
      }
      final f = finger.value;
      if (f != null && joined >= 1 && doneAt < 0) {
        canvas.drawLine(
          geo.points[joined - 1],
          f,
          Paint()
            ..color = _ink.withValues(alpha: 0.35)
            ..strokeWidth = w * 0.55
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BoardPainter old) =>
      old.geo != geo || old.joined != joined || old.joinedAt != joinedAt || old.doneAt != doneAt || old.lineWidth != lineWidth || old.still != still;
}
