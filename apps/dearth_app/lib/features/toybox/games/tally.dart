import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Tallies (SPEC FR-TOY-03, Appendix B: keeping count). A chalkboard on a
/// meadow; bunnies hop up one at a time and wait in front of it. She taps
/// the board (or the bunny): a chalk line draws itself, the voice says the
/// count, and the bunny hops off happy; the fifth line crosses the four.
/// A tap with no bunny waiting makes no mark (one bunny, one mark) and the
/// board shakes. When the last bunny has gone, the marks light up as the
/// voice counts them back (by the bundle once she counts on) and says how
/// many bunnies came. At the top level the board holds a finished tally:
/// "How many marks?", and she picks the numeral; a wrong one has the voice
/// count the marks, lighting them, and two slips light the answer.
class TallyGame extends StatefulWidget {
  const TallyGame(this.c, {super.key});
  final GameController c;

  @override
  State<TallyGame> createState() => TallyGameState();
}

enum _Bunny { none, coming, waiting, leaving }

@visibleForTesting
class TallyGameState extends State<TallyGame> {
  TallyRound? _round;
  int _deal = 0, _marked = 0, _lit = 0, _slips = 0, _boardWiggles = 0, _bunnyHops = 0, _bunnyIndex = 0;
  _Bunny _bunny = _Bunny.none;
  bool _settling = false, _counting = false, _done = false, _hint = false;
  final _tried = <int>{};
  final _wiggles = <int, int>{};
  final _hops = <int, int>{};
  final _timers = <Timer>[];
  Timer? _idle;

  @visibleForTesting
  TallyRound get debugRound => _round!;

  /// Marks on the board now.
  @visibleForTesting
  int get debugMarks => _round!.start + _marked;

  /// Whether a bunny is waiting for its mark.
  @visibleForTesting
  bool get debugWaiting => _bunny == _Bunny.waiting;

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
    final r = tallyRound(widget.c.level, widget.c.random, last: _round);
    _round = r;
    _deal++;
    _marked = _lit = _slips = _boardWiggles = _bunnyHops = _bunnyIndex = 0;
    _bunny = _Bunny.none;
    _settling = _counting = _done = _hint = false;
    _tried.clear();
    _wiggles.clear();
    _hops.clear();
    _after(const Duration(milliseconds: 600), _intro);
    if (mounted) setState(() {});
  }

  String get _introClip => switch (_round!.mode) { TallyMode.mark => VoiceLine.tallyStart, TallyMode.countOn => VoiceLine.tallyFive, TallyMode.read => VoiceLine.tallyAsk };

  void _intro() {
    final r = _round!;
    widget.c.say(_introClip);
    if (r.mode == TallyMode.read) {
      _waitIdle();
      return;
    }
    // "Five bunnies already!": the bundle lights while it's said.
    if (r.mode == TallyMode.countOn) setState(() => _lit = r.start);
    _after(afterVoice(_introClip), () {
      setState(() => _lit = 0);
      _bringBunny();
    });
  }

  /// The next bunny hops in from the right and waits.
  void _bringBunny() {
    setState(() {
      _bunnyIndex = _marked;
      _bunny = _Bunny.coming;
    });
    // Built off to the right first, so the move in animates.
    _after(const Duration(milliseconds: 40), () => setState(() => _bunny = _Bunny.waiting));
    _waitIdle();
  }

  /// A long wait: the board glows and the voice says what to do (not a slip).
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 9), () {
      if (!mounted || _done) return;
      final read = _round!.mode == TallyMode.read;
      if (!read && _bunny != _Bunny.waiting) return;
      setState(() => _hint = !read);
      widget.c.say(read ? VoiceLine.tallyAsk : VoiceLine.tallyTap);
      _waitIdle();
    });
  }

  /// A tap on the board or the bunny.
  void _mark() {
    final r = _round!;
    if (r.mode == TallyMode.read || _done || _counting || _settling) return;
    if (_bunny != _Bunny.coming && _bunny != _Bunny.waiting) {
      // No bunny to mark: one bunny, one mark.
      _slips++;
      widget.c.cue();
      setState(() => _boardWiggles++);
      return;
    }
    _idle?.cancel();
    widget.c.sound(Sfx.snap, volume: 0.45);
    widget.c.say(numberClip(r.start + _marked + 1));
    setState(() {
      _marked++;
      _hint = false;
      _settling = true;
      _bunnyHops++;
    });
    // A happy hop, then off to the left; a quick second tap isn't a slip.
    _after(const Duration(milliseconds: 450), () => setState(() => _settling = false));
    _after(const Duration(milliseconds: 300), () => setState(() => _bunny = _Bunny.leaving));
    _after(const Duration(milliseconds: 1150), () {
      if (_marked < r.bunnies) {
        _bringBunny();
      } else {
        setState(() => _bunny = _Bunny.none);
        _countBack(then: _finish);
      }
    });
  }

  /// Lights the marks as the voice counts them: one by one at first, by
  /// the bundle once she counts on (and when reading).
  void _countBack({required VoidCallback then}) {
    final r = _round!;
    setState(() => _counting = true);
    var at = const Duration(milliseconds: 300);
    for (final k in tallyCountBack(r.total, byFives: r.mode != TallyMode.mark)) {
      _after(at, () {
        setState(() => _lit = k);
        widget.c.say(numberClip(k));
      });
      at += afterVoice(numberClip(k), atLeast: const Duration(milliseconds: 850));
    }
    _after(at, () {
      setState(() => _counting = false);
      then();
    });
  }

  void _finish() {
    final r = _round!;
    final clip = tallyBunniesClip(r.total);
    widget.c.say(clip);
    setState(() => _done = true);
    unawaited(widget.c.finishRound(tallyResult(r, _slips), emoji: '🐇'));
    _after(afterVoice(clip, atLeast: const Duration(milliseconds: 2800)), _newRound);
  }

  void _pick(int n) {
    final r = _round!;
    if (_done) return;
    _waitIdle();
    if (n != r.total) {
      if (!_tried.add(n) || _counting) return;
      _slips++;
      widget.c.cue();
      setState(() => _wiggles[n] = (_wiggles[n] ?? 0) + 1);
      // Count them together, lighting each: the help a grown-up would give.
      _countBack(then: () => setState(() => _lit = 0));
      return;
    }
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _idle?.cancel();
    widget.c.sound(Sfx.sparkle, volume: 0.5);
    widget.c.say(numberClip(n));
    setState(() {
      _done = true;
      _counting = false;
      _lit = r.total;
      _hops[n] = (_hops[n] ?? 0) + 1;
    });
    unawaited(widget.c.finishRound(tallyResult(r, _slips), emoji: '🐇'));
    _after(const Duration(milliseconds: 3200), _newRound);
  }

  String _askLabel() {
    final r = _round!;
    return switch (r.mode) {
      TallyMode.read => _done ? '${r.total} marks' : 'How many marks?',
      _ when _done => '${r.total} bunn${r.total == 1 ? 'y' : 'ies'}',
      TallyMode.mark => 'Make a mark for each bunny',
      TallyMode.countOn => 'Five already: count on',
    };
  }

  String _bunnyLabel() {
    final r = _round!;
    final which = 'Bunny ${_bunnyIndex + 1} of ${r.bunnies}';
    return switch (_bunny) {
      _Bunny.none => 'No bunny',
      _Bunny.coming => '$which, coming',
      _Bunny.waiting => '$which, waiting',
      _Bunny.leaving => '$which, hopping away',
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    return Backdrop(
      top: const Color(0xFFDDF2FF),
      bottom: const Color(0xFFD8EFC4),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth, h = box.maxHeight;
              final gap = t.space.md;
              final wide = w > h;
              final boardH = wide ? math.min(h * 0.52, w * 0.8 / 2.1) : math.min(w * 0.94 / 2.1, h * 0.4);
              final boardW = boardH * 2.1;
              final below = h - boardH - gap;
              // The bunny stands at the board: on a tall screen the two sit
              // together a little above the middle, not at the far ends.
              final bunny = math.min(below * 0.85, math.min(w * (wide ? 0.3 : 0.42), 340.0 * t.scale));
              final top = wide ? 0.0 : math.max(0.0, (h - boardH - gap * 2 - bunny) * 0.4);
              return Stack(
                key: ValueKey(_deal),
                children: [
                  Positioned(left: (w - boardW) / 2, top: top, width: boardW, height: boardH, child: _board()),
                  if (r.mode == TallyMode.read)
                    Positioned(left: 0, right: 0, top: top + boardH + gap, height: math.min(below, bunny * 1.4), child: _choices(Size(w, math.min(below, bunny * 1.4)), gap))
                  else
                    ..._meadow(w, wide ? h : top + boardH + gap * 2 + bunny, bunny),
                ],
              );
            }),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'tally.ask',
              label: _askLabel(),
              onSayAgain: () => widget.c.say(_introClip),
              children: [DEmoji('🐇', size: 40 * t.scale), SizedBox(width: t.space.xs), DEmoji('✏️', size: 36 * t.scale)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _board() {
    final r = _round!;
    final marks = r.start + _marked;
    return DPressable(
      id: 'tally.board',
      semanticLabel: 'Tally: $marks mark${marks == 1 ? '' : 's'}',
      excludeSemantics: true,
      onTap: _mark,
      pressFeedback: false,
      borderRadius: BorderRadius.circular(16),
      child: Wiggle(
        count: _boardWiggles,
        // The newest line draws itself in.
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: marks.toDouble()),
          duration: const Duration(milliseconds: 300),
          builder: (context, drawn, _) => RepaintBoundary(child: CustomPaint(painter: _BoardPainter(drawn: drawn, lit: _lit, glow: _hint), size: Size.infinite)),
        ),
      ),
    );
  }

  /// The path, its bottom at [floor], and the bunny on it.
  List<Widget> _meadow(double w, double floor, double size) {
    final y = floor - size;
    final x = switch (_bunny) {
      _Bunny.none || _Bunny.coming => w + size * 0.2,
      _Bunny.waiting => (w - size) / 2,
      _Bunny.leaving => -size * 1.2,
    };
    return [
      Positioned(left: 0, right: 0, top: floor - size * 0.32, height: size * 0.32, child: const RepaintBoundary(child: CustomPaint(painter: _PathPainter()))),
      if (_bunny != _Bunny.none)
        AnimatedPositioned(
          key: ValueKey('bunny$_bunnyIndex'),
          duration: Duration(milliseconds: _bunny == _Bunny.leaving ? 800 : 950),
          curve: _bunny == _Bunny.leaving ? Curves.easeIn : Curves.easeOut,
          left: x,
          top: y,
          width: size,
          height: size,
          child: DPressable(
            id: 'tally.bunny',
            semanticLabel: _bunnyLabel(),
            excludeSemantics: true,
            onTap: _mark,
            pressFeedback: false,
            borderRadius: BorderRadius.circular(size / 2),
            child: Hop(
              count: _bunnyHops,
              // Bounding along while it moves; still while it waits.
              child: TweenAnimationBuilder<double>(
                key: ValueKey(_bunny),
                tween: Tween(begin: 0, end: _bunny == _Bunny.waiting ? 0 : 1),
                duration: const Duration(milliseconds: 900),
                builder: (context, k, child) => Transform.translate(offset: Offset(0, -(math.sin(k * math.pi * 3)).abs() * size * 0.16), child: child),
                child: DEmoji('🐇', size: size * 0.9),
              ),
            ),
          ),
        ),
    ];
  }

  /// Read: three numeral cards.
  Widget _choices(Size area, double gap) {
    final r = _round!;
    final side = math.min(math.min((area.width - gap * 4) / 3, area.height - gap), 190.0 * DTheme.of(context).scale);
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final n in r.choices)
            Padding(
              padding: EdgeInsets.all(gap / 2),
              child: PictureTile(
                id: 'tally.card.$n',
                label: '$n${_tried.contains(n) ? ', tried' : ''}',
                size: side,
                tried: _tried.contains(n),
                hint: !_done && _slips >= 2 && n == r.total,
                wiggles: _wiggles[n] ?? 0,
                hops: _hops[n] ?? 0,
                onTap: () => _pick(n),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [for (final d in '$n'.split('')) GlyphView(d, height: side * 0.5, color: const Color(0xFF2B2440))],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A chalkboard in a wooden frame with tally marks in chalk: up to two
/// bundles of four lines crossed by a fifth. [drawn] marks are drawn, the
/// last one partly while it goes on; the first [lit] glow yellow as they're
/// counted; [glow] rings the board as a hint.
class _BoardPainter extends CustomPainter {
  _BoardPainter({required this.drawn, required this.lit, required this.glow});
  final double drawn;
  final int lit;
  final bool glow;

  static const _chalk = Color(0xFFF7F4EA), _lit = Color(0xFFFFE066);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final frame = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(h * 0.08));
    if (glow) canvas.drawRRect(frame.inflate(h * 0.04), Paint()..color = const Color(0x99FFD54F));
    canvas
      ..drawRRect(frame, Paint()..color = const Color(0xFFB4743E))
      ..drawRRect(frame, Paint()
        ..color = const Color(0xFF8E5A2C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, h * 0.02));
    final slate = RRect.fromRectAndRadius(Rect.fromLTRB(h * 0.08, h * 0.08, w - h * 0.08, h * 0.92), Radius.circular(h * 0.04));
    canvas.drawRRect(slate, Paint()..color = const Color(0xFF2F5D50));
    final inner = slate.outerRect.deflate(h * 0.1);
    // Two bundle places side by side.
    final groupW = inner.width * 0.4, gap = inner.width * 0.2;
    final top = inner.top + inner.height * 0.08, bottom = inner.bottom - inner.height * 0.08;
    final whole = drawn.floor();
    for (var i = 0; i < kTallyMax; i++) {
      final part = i < whole ? 1.0 : (i == whole ? drawn - whole : 0.0);
      if (part <= 0) continue;
      final g = i ~/ 5, j = i % 5;
      final gx = inner.left + g * (groupW + gap);
      // Hand-drawn: each line leans a little its own way.
      final lean = (math.sin(i * 12.9898) * 43758.5453 % 1) * groupW * 0.04;
      final (from, to) = j < 4
          ? (Offset(gx + groupW * (0.12 + j * 0.25) + lean, top), Offset(gx + groupW * (0.12 + j * 0.25) - lean, bottom))
          : (Offset(gx - groupW * 0.04, bottom - inner.height * 0.12), Offset(gx + groupW * 1.0, top + inner.height * 0.12));
      final paint = Paint()
        ..color = i < lit ? _lit : _chalk
        ..strokeWidth = h * (i < lit ? 0.07 : 0.055)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(from, Offset.lerp(from, to, part)!, paint);
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) => old.drawn != drawn || old.lit != lit || old.glow != glow;
}

/// A sandy path across the meadow for the bunnies.
class _PathPainter extends CustomPainter {
  const _PathPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(0, size.height * 0.25, size.width, size.height * 0.6), Radius.circular(size.height * 0.3));
    canvas.drawRRect(r, Paint()..color = const Color(0xFFE6D3A3));
    // Tufts of grass along the edge.
    final grass = Paint()
      ..color = const Color(0xFF7CB65A)
      ..strokeWidth = math.max(2, size.height * 0.05)
      ..strokeCap = StrokeCap.round;
    for (var x = size.width * 0.05; x < size.width; x += size.width * 0.11) {
      final b = Offset(x, size.height * 0.28);
      canvas
        ..drawLine(b, b + Offset(-size.height * 0.08, -size.height * 0.22), grass)
        ..drawLine(b, b + Offset(size.height * 0.06, -size.height * 0.26), grass);
    }
  }

  @override
  bool shouldRepaint(_PathPainter old) => false;
}
