import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'creature.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Letter Creatures (SPEC FR-TOY-03, Appendix B: first sounds). Build-a-
/// Creature's parts, picked by sound. A creature grows on the stage a part
/// at a time: the pill shows a letter and the voice asks "Find a body that
/// starts with rrr!"; three or four painted parts wait beside it. The right
/// one goes onto the creature as the voice links sound and word ("Rrr, rrr,
/// round!"); another says its own name ("Bunny ears!") and wiggles, and
/// after two of those, or a long pause, the right part glows. Once every
/// part is on, the creature dances to a little tune and says its silly name.
class LetterCreatureGame extends StatefulWidget {
  const LetterCreatureGame(this.c, {super.key});
  final GameController c;

  @override
  State<LetterCreatureGame> createState() => LetterCreatureGameState();
}

@visibleForTesting
class LetterCreatureGameState extends State<LetterCreatureGame> with SingleTickerProviderStateMixin {
  static const _danceSeconds = 3.4;

  LetterCreatureRound? _round;
  int _step = 0, _slips = 0, _slipsHere = 0, _deal = 0, _frames = 0, _hops = 0;
  bool _glow = false, _done = false, _toldStart = false;
  final _wiggles = <int, int>{};
  final _timers = <Timer>[];
  Timer? _idle;
  late final Ticker _ticker = createTicker(_tick);

  /// Seconds into the dance; null when standing still.
  final _dance = ValueNotifier<double?>(null);

  @visibleForTesting
  LetterCreatureRound get debugRound => _round!;

  /// The part being picked now (its index in the round's steps).
  @visibleForTesting
  int get debugStep => _step;

  @visibleForTesting
  bool get debugHint => _glow;

  @visibleForTesting
  bool get debugDone => _done;

  LetterCreatureStep get _now => _round!.steps[_step];

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
    _dance.dispose();
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
    _round = letterCreatureRound(widget.c.level, widget.c.random, last: _round);
    _step = _slips = _slipsHere = 0;
    _glow = _done = false;
    _wiggles.clear();
    _deal++;
    // "Let's make a silly creature!" once a session, then the first part.
    var lead = const Duration(milliseconds: 600);
    if (!_toldStart) {
      _toldStart = true;
      _after(lead, () => widget.c.say(VoiceLine.makeCreature));
      lead += afterVoice(VoiceLine.makeCreature);
    }
    _after(lead, _ask);
    if (mounted) setState(() {});
  }

  void _ask() {
    widget.c.say(letterCreatureAskClip(_now));
    _waitIdle();
  }

  /// A long pause asks again and lights the right part (not a slip).
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 11), () {
      if (!mounted || _done) return;
      widget.c.say(letterCreatureAskClip(_now));
      setState(() => _glow = true);
    });
  }

  void _pick(int option) {
    if (_done) return;
    final s = _now;
    _waitIdle();
    if (option != s.answer) {
      _slips++;
      _slipsHere++;
      widget.c.cue();
      widget.c.say(creaturePartClip(s.part, option));
      setState(() {
        _wiggles[option] = (_wiggles[option] ?? 0) + 1;
        if (_slipsHere >= 2) _glow = true;
      });
      return;
    }
    widget.c.sound(Sfx.pop, volume: 0.6, rate: 0.9 + _step * 0.08);
    final yes = letterCreatureYesClip(s.part, option);
    widget.c.say(yes);
    final last = _step == _round!.steps.length - 1;
    setState(() {
      _hops++;
      _slipsHere = 0;
      _glow = false;
      _wiggles.clear();
      if (last) {
        _done = true;
      } else {
        _step++;
      }
    });
    if (!last) {
      _after(afterVoice(yes, atLeast: const Duration(milliseconds: 1200)), _ask);
      return;
    }
    _idle?.cancel();
    unawaited(widget.c.finishRound(letterCreatureResult(_round!, _slips), emoji: '🐲'));
    _after(afterVoice(yes, atLeast: const Duration(milliseconds: 1000)), _startDance);
    _after(afterVoice(yes, atLeast: const Duration(milliseconds: 1000)) + const Duration(milliseconds: 4800), _newRound);
  }

  void _startDance() {
    widget.c.say(creatureClip(_round!.creature));
    _frames = 0;
    _dance.value = 0;
    unawaited(_ticker.start());
    // Build-a-Creature's tune: a pentatonic run up and back, a drum on the beat.
    const notes = [60, 64, 67, 72, 69, 67, 64, 67, 72, 76, 72, 67];
    for (var i = 0; i < notes.length; i++) {
      _after(Duration(milliseconds: 250 * i), () {
        widget.c.sound(Sfx.xylophone, volume: 0.6, rate: math.pow(2, (notes[i] - kXylophoneBaseMidi) / 12).toDouble());
        if (i.isEven) widget.c.sound(i % 4 == 0 ? Sfx.kick : Sfx.hat, volume: 0.45);
      });
    }
  }

  void _tick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    if (t >= _danceSeconds) {
      _ticker.stop();
      _dance.value = null;
      return;
    }
    // Ambient motion: 30 fps is plenty on the slowest displays.
    if (DTheme.of(context).policy.ambientFps < 60 && (_frames++).isOdd) return;
    _dance.value = t;
  }

  /// The creature so far: the parts picked before this step (all of them
  /// once done).
  Creature get _sofar {
    final r = _round!;
    final picked = _done ? r.steps : r.steps.take(_step);
    return Creature({for (final s in picked) s.part: s.answer}, r.color);
  }

  String _askLabel() {
    if (_done) return "I'm a ${_round!.creature.name}";
    final s = _now;
    final what = switch (s.part) {
      CreaturePart.body => 'a body',
      CreaturePart.face => 'eyes',
      CreaturePart.top => 'something for the top',
      CreaturePart.legs => 'legs',
      CreaturePart.arms => 'arms',
      CreaturePart.tail => 'a tail',
    };
    return 'Find $what: ${s.letter}';
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    final s = _now;
    final sofar = _sofar;
    final hasFace = _done || _step > r.steps.indexWhere((x) => x.part == CreaturePart.face);
    return Backdrop(
      top: const Color(0xFFFFF0F6),
      bottom: const Color(0xFFE9F7EF),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final l = _Layout.of(box.biggest, s.choices.length);
              return Stack(
                key: ValueKey(_deal),
                children: [
                  Positioned.fromRect(
                    rect: l.stage,
                    child: tid(
                      'lettercreature.creature',
                      Semantics(
                        label: _done ? sofar.name : 'Parts: ${_done ? r.steps.length : _step} of ${r.steps.length}',
                        excludeSemantics: true,
                        child: Hop(
                          count: _hops,
                          child: _step == 0 && !_done
                              ? _Mystery(size: l.stage.shortestSide)
                              : RepaintBoundary(
                                  child: CustomPaint(
                                    // Until it has eyes, just the body.
                                    painter: hasFace ? CreaturePainter(sofar, dance: _dance) : CreaturePainter.icon(CreaturePart.body, sofar),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                  for (var i = 0; i < s.choices.length; i++)
                    Positioned.fromRect(
                      rect: l.option(i),
                      child: PictureTile(
                        id: 'lettercreature.option.$i',
                        label: kCreaturePartWords[s.part]![s.choices[i]],
                        size: l.optionSize,
                        onTap: () => _pick(s.choices[i]),
                        hint: _glow && !_done && s.choices[i] == s.answer,
                        tried: _done,
                        wiggles: _wiggles[s.choices[i]] ?? 0,
                        child: Padding(
                          padding: EdgeInsets.all(l.optionSize * 0.08),
                          child: RepaintBoundary(child: CustomPaint(size: Size.infinite, painter: CreaturePainter.icon(s.part, Creature({s.part: s.choices[i]}, r.color)))),
                        ),
                      ),
                    ),
                ],
              );
            }),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'lettercreature.ask',
              label: _askLabel(),
              onSayAgain: _done ? null : () => widget.c.say(letterCreatureAskClip(_now)),
              children: [_done ? DEmoji('🎉', size: 44 * t.scale) : LetterPair(s.letter, height: 52 * t.scale)],
            ),
          ),
        ],
      ),
    );
  }
}

/// Before the body: a soft egg with a question mark, waiting to hatch.
class _Mystery extends StatelessWidget {
  const _Mystery({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: size * 0.62,
          height: size * 0.74,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF4EEFF),
            borderRadius: BorderRadius.all(Radius.elliptical(size * 0.31, size * 0.37)),
            border: Border.all(color: const Color(0xFFD5C8F2), width: 5),
          ),
          child: Text('?', style: DTheme.of(context).text.kidTitle.copyWith(fontSize: size * 0.3, height: 1, color: const Color(0xFFB4A3E0))),
        ),
      );
}

/// The stage and the parts to choose from. Wide: the stage on the left,
/// the parts in a 2×2 grid (or a column of three) on the right. Tall: the
/// stage on top, the parts in a row (or 2×2) under it.
class _Layout {
  _Layout(this.stage, this._options, this.optionSize);

  factory _Layout.of(Size a, int n) {
    final gap = math.max(12.0, a.shortestSide * 0.03);
    if (a.width > a.height * 1.1) {
      final side = math.min(a.width * 0.5, a.height);
      final stage = Rect.fromLTWH(a.width * 0.02, (a.height - side) / 2, side, side);
      final right = Rect.fromLTRB(stage.right + gap * 2, 0, a.width, a.height);
      final cols = 2, rows = (n / 2).ceil();
      final size = math.min((right.width - gap) / cols, (a.height - gap * (rows - 1)) / rows) * 0.92;
      return _Layout(stage, _grid(right, n, cols, size, gap), size);
    }
    final side = math.min(a.width * 0.9, a.height * 0.5);
    final stage = Rect.fromLTWH((a.width - side) / 2, 0, side, side);
    final below = Rect.fromLTRB(0, stage.bottom + gap, a.width, a.height);
    final cols = n == 4 && below.height > a.width * 0.5 ? 2 : n;
    final rows = (n / cols).ceil();
    final size = math.min((a.width - gap * (cols - 1)) / cols, (below.height - gap * (rows - 1)) / rows) * 0.92;
    return _Layout(stage, _grid(below, n, cols, size, gap), size);
  }

  static List<Rect> _grid(Rect area, int n, int cols, double size, double gap) {
    final rows = (n / cols).ceil();
    final top = area.top + (area.height - rows * size - (rows - 1) * gap) / 2;
    return [
      for (var i = 0; i < n; i++)
        () {
          final row = i ~/ cols;
          final inRow = row == rows - 1 ? n - row * cols : cols;
          final left = area.left + (area.width - inRow * size - (inRow - 1) * gap) / 2;
          return Rect.fromLTWH(left + (i % cols) * (size + gap), top + row * (size + gap), size, size);
        }(),
    ];
  }

  final Rect stage;
  final List<Rect> _options;
  final double optionSize;

  Rect option(int i) => _options[i];
}
