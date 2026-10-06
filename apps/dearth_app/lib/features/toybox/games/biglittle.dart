import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Big & Little Letters (SPEC FR-TOY-03, Appendix B: capitals and small
/// letters). Capitals wait on cards along the top; small letters wait on
/// round tokens below. She drags each small letter to its capital (or taps
/// it, then the card); it settles beside the capital and the voice names
/// the pair: "Big C, little c." A wrong card sends it back with a wiggle
/// and the voice names the letter she's holding; after two slips, or a long
/// pause, its card glows. Tapping a letter says its name. The letters are
/// the ball-and-stick shapes she traces, small ones on a shared baseline
/// so p and q hang below b and d.
class BigLittleGame extends StatefulWidget {
  const BigLittleGame(this.c, {super.key});
  final GameController c;

  @override
  State<BigLittleGame> createState() => BigLittleGameState();
}

@visibleForTesting
class BigLittleGameState extends State<BigLittleGame> {
  final _area = GlobalKey();
  late BigLittleRound _round;
  final _placed = <String>{};
  final _wiggles = <String, int>{}, _tokenHops = <String, int>{}, _cardHops = <String, int>{};
  int _slips = 0, _deal = 0;
  String? _dragging, _selected, _nudge;
  Offset _dragAt = Offset.zero, _grip = Offset.zero;
  Timer? _ask, _idle, _finish, _next;
  _Layout? _layout;

  @visibleForTesting
  BigLittleRound get debugRound => _round;

  bool get _done => _placed.length == _round.letters.length;

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  @override
  void dispose() {
    for (final t in [_ask, _idle, _finish, _next]) {
      t?.cancel();
    }
    super.dispose();
  }

  void _newRound() {
    final last = _deal == 0 ? const <String>[] : _round.letters;
    _round = bigLittleRound(widget.c.level, widget.c.random, last: last);
    _placed.clear();
    _wiggles.clear();
    _slips = 0;
    _dragging = _selected = _nudge = null;
    _deal++;
    _ask?.cancel();
    // A beat for the letters to land before the voice.
    _ask = Timer(const Duration(milliseconds: 600), _sayPrompt);
    _waitIdle();
    if (mounted) setState(() {});
  }

  void _sayPrompt() => widget.c.say(_done ? VoiceLine.bigLittleDone : VoiceLine.bigLittleStart);

  /// A long pause nudges the next small letter and lights its card, without
  /// counting a slip.
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 12), () {
      if (!mounted || _done) return;
      final l = _round.tray.firstWhere((l) => !_placed.contains(l));
      widget.c.say(letterNameClip(l));
      setState(() {
        _nudge = l;
        _tokenHops[l] = (_tokenHops[l] ?? 0) + 1;
      });
      _waitIdle();
    });
  }

  /// Tries small [letter] on the card of [capital].
  void _fit(String letter, String capital) {
    _waitIdle();
    if (letter != capital) {
      _slips++;
      widget.c.cue();
      widget.c.say(letterNameClip(letter));
      setState(() {
        _wiggles[letter] = (_wiggles[letter] ?? 0) + 1;
        _selected = null;
      });
      return;
    }
    widget.c.sound(Sfx.snap);
    widget.c.say(bigLittleClip(letter));
    setState(() {
      _placed.add(letter);
      _cardHops[letter] = (_cardHops[letter] ?? 0) + 1;
      _selected = null;
      if (_nudge == letter) _nudge = null;
    });
    if (!_done) return;
    _idle?.cancel();
    // The last pair is named in full before the cheer.
    _finish = Timer(afterVoice(bigLittleClip(letter)), () {
      if (!mounted) return;
      widget.c.say(VoiceLine.bigLittleDone);
      widget.c.sound(Sfx.sparkle, volume: 0.6);
      setState(() {
        for (final l in _round.letters) {
          _cardHops[l] = (_cardHops[l] ?? 0) + 1;
        }
      });
      unawaited(widget.c.finishRound(bigLittleResult(_slips, pairs: _round.letters.length), emoji: '🔠'));
      _next = Timer(afterVoice(VoiceLine.bigLittleDone, atLeast: const Duration(milliseconds: 2800)), _newRound);
    });
  }

  void _tapLittle(String l) {
    if (_placed.contains(l)) return;
    widget.c.sound(Sfx.tap, volume: 0.5);
    widget.c.say(letterNameClip(l));
    setState(() => _selected = _selected == l ? null : l);
  }

  void _tapBig(String l) {
    final s = _selected;
    if (s != null && !_placed.contains(l)) return _fit(s, l);
    widget.c.say(_placed.contains(l) ? bigLittleClip(l) : letterNameClip(l));
    setState(() => _cardHops[l] = (_cardHops[l] ?? 0) + 1);
  }

  Offset _local(Offset global) => (_area.currentContext!.findRenderObject()! as RenderBox).globalToLocal(global);

  void _dragEnd() {
    final l = _dragging, layout = _layout;
    if (l == null || layout == null) return;
    _dragging = null;
    String? near;
    var best = double.infinity;
    for (final (i, c) in _round.letters.indexed) {
      if (_placed.contains(c)) continue;
      final d = (layout.cards[i] - _dragAt).distance;
      if (d < best) (best, near) = (d, c);
    }
    if (near != null && best < layout.card * 0.62) {
      _fit(l, near);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Backdrop(
      top: const Color(0xFFEFF4FF),
      bottom: const Color(0xFFFFF3E2),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(
              key: _area,
              builder: (context, box) {
                final l = _layout = _Layout.of(box.biggest, _round.letters.length);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final (i, c) in _round.letters.indexed) _card(c, i, l),
                    for (final (i, s) in _round.tray.indexed) _token(s, i, l),
                  ],
                );
              },
            ),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'biglittle.ask',
              label: _done ? 'All found!' : 'Little letters find big letters',
              onSayAgain: _sayPrompt,
              children: [
                GlyphView('B', height: 44 * t.scale, color: kConsonantColor),
                SizedBox(width: t.space.xs),
                GlyphView('b', height: 44 * t.scale, color: kConsonantColor, frameTop: 0, frameBottom: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(String c, int i, _Layout l) {
    final placed = _placed.contains(c);
    final glow = !placed && (_nudge == c || (_slips >= 2 && (_dragging ?? _selected) == c));
    final upper = c.toUpperCase();
    return Positioned(
      left: l.cards[i].dx - l.card / 2,
      top: l.cards[i].dy - l.card / 2,
      child: tid(
        'biglittle.big.$i',
        Semantics(
          button: true,
          label: placed ? 'Big $upper, little $c' : 'Big $upper',
          onTap: () => _tapBig(c),
          excludeSemantics: true,
          child: GestureDetector(
            excludeFromSemantics: true,
            behavior: HitTestBehavior.opaque,
            onTap: () => _tapBig(c),
            child: Hop(count: _cardHops[c] ?? 0, child: _Card(letter: c, size: l.card, glow: glow, paired: placed)),
          ),
        ),
      ),
    );
  }

  Widget _token(String s, int i, _Layout l) {
    final placed = _placed.contains(s), dragging = _dragging == s;
    final card = l.cards[_round.letters.indexOf(s)];
    // Settling, it flies to where the card draws the pair's small letter.
    final center = placed ? card + Offset(l.card * 0.2, l.card * 0.05) : (dragging ? _dragAt : l.tray[i]);
    return AnimatedPositioned(
      key: ValueKey('$_deal.$i'),
      duration: dragging ? Duration.zero : const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      left: center.dx - l.token / 2,
      top: center.dy - l.token / 2,
      child: IgnorePointer(
        ignoring: placed,
        child: tid(
          'biglittle.little.$i',
          Semantics(
            button: true,
            label: placed ? 'Little $s, home' : 'Little $s',
            onTap: () => _tapLittle(s),
            excludeSemantics: true,
            child: GestureDetector(
              excludeFromSemantics: true,
              dragStartBehavior: DragStartBehavior.down,
              onTap: () => _tapLittle(s),
              onPanStart: (d) => setState(() {
                _dragging = s;
                _selected = null;
                _grip = center - _local(d.globalPosition);
                _dragAt = center;
              }),
              onPanUpdate: (d) => setState(() => _dragAt = _local(d.globalPosition) + _grip),
              onPanEnd: (_) => _dragEnd(),
              onPanCancel: _dragEnd,
              child: AnimatedScale(
                scale: placed ? 0.7 : (dragging || _selected == s ? 1.12 : 1),
                duration: const Duration(milliseconds: 220),
                // A small token fading out as the card takes over: cheap.
                child: AnimatedOpacity(
                  opacity: placed ? 0 : 1,
                  duration: const Duration(milliseconds: 300),
                  child: Hop(
                    count: _tokenHops[s] ?? 0,
                    child: Wiggle(count: _wiggles[s] ?? 0, child: _Token(letter: s, size: l.token)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A capital on its card. Once paired, the card shows the pair the way
/// alphabet charts do, "Cc" on one baseline.
class _Card extends StatelessWidget {
  const _Card({required this.letter, required this.size, required this.glow, required this.paired});
  final String letter;
  final double size;
  final bool glow, paired;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = BorderRadius.circular(size * 0.2);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: r,
        border: Border.all(color: glow ? const Color(0xFFFFC93C) : (paired ? const Color(0xFFB8E3C4) : const Color(0xFFE3DCF5)), width: glow ? 7 : 3),
        boxShadow: [BoxShadow(color: glow ? const Color(0x88FFD54F) : const Color(0x00FFD54F), spreadRadius: glow ? 10 : 0), ...t.elevation.e1],
      ),
      padding: EdgeInsets.all(size * 0.1),
      child: Center(
        child: paired
            ? FittedBox(fit: BoxFit.scaleDown, child: LetterPair(letter, height: size * 0.72))
            : GlyphView(letter.toUpperCase(), height: size * 0.58, color: letterColor(letter)),
      ),
    );
  }
}

/// A small letter on its round token, on the shared baseline (0…14) so its
/// size and drop below the line are its own.
class _Token extends StatelessWidget {
  const _Token({required this.letter, required this.size});
  final String letter;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFFFF4D6),
        border: Border.all(color: const Color(0xFFF2C46B), width: 3),
        boxShadow: t.elevation.e1,
      ),
      child: GlyphView(letter, height: size * 0.82, color: letterColor(letter), frameTop: 0, frameBottom: 14),
    );
  }
}

/// Cards on top, tokens below. A narrow screen takes two rows of each for
/// more than three letters; each row is centred, so five make 3 + 2.
class _Layout {
  _Layout(this.cards, this.tray, this.card, this.token);

  factory _Layout.of(Size area, int n) {
    final rows = n > 3 && area.width < area.height * 0.8 ? 2 : 1;
    final cols = (n / rows).ceil();
    final card = math.min(math.min(area.width / cols * 0.8, area.height * 0.46 / rows * 0.84), 320.0);
    List<Offset> grid(double top, double height) => [
          for (var i = 0; i < n; i++)
            Offset(
              area.width * ((i % cols) + 0.5 + (cols - math.min(cols, n - (i ~/ cols) * cols)) / 2) / cols,
              top + height * ((i ~/ cols) + 0.5) / rows,
            ),
        ];
    return _Layout(grid(0, area.height * 0.5), grid(area.height * 0.54, area.height * 0.46), card, card * 0.84);
  }

  final List<Offset> cards, tray;
  final double card, token;
}
