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

/// Word Builder (SPEC FR-TOY-03, Appendix B: phonics, blending and
/// spelling). A picture, a strip of letter slots and a tray of small letters
/// in the Montessori colors, like a movable alphabet. The voice says the
/// word, then asks for the missing sound (or to build it all); every tile
/// says its sound when she touches it. She taps a tile, or drags it, into
/// the glowing slot; the slots fill left to right, the way the word is
/// read. A wrong tile wiggles back (she has heard its sound, which is the
/// lesson); after two, or a long pause, the right one glows and the voice
/// says the sound she needs. The payoff is blending: each letter hops as
/// the voice says its sound, then the letters slide together and the voice
/// says the word while the picture jumps.
class SpellGame extends StatefulWidget {
  const SpellGame(this.c, {super.key});
  final GameController c;

  @override
  State<SpellGame> createState() => SpellGameState();
}

@visibleForTesting
class SpellGameState extends State<SpellGame> {
  final _area = GlobalKey();
  late SpellRound _round;

  /// Slot → the tray tile that fills it.
  final _filled = <int, int>{};
  final _wiggles = <int, int>{}, _hops = <int, int>{}, _givenHops = <int, int>{};
  int _slips = 0, _slipsHere = 0, _deal = 0, _pictureHops = 0;
  bool _nudge = false, _blended = false;

  /// The slot whose sound the voice is saying while it blends.
  int? _lit;
  int? _dragging;
  Offset _dragAt = Offset.zero, _grip = Offset.zero;
  Timer? _ask, _idle, _blend, _next;
  _Layout? _layout;

  @visibleForTesting
  SpellRound get debugRound => _round;

  /// The slot to fill next (null once the word is whole).
  @visibleForTesting
  int? get debugActive => _active;

  /// A tray tile the next slot takes, or (with [right] false) one it doesn't.
  @visibleForTesting
  int debugTile({bool right = true}) {
    final a = _active!, used = _filled.values.toSet();
    return [for (final (i, l) in _round.tiles.indexed) if (!used.contains(i) && (l == _word[a]) == right) i].first;
  }

  String get _word => _round.letters;
  bool get _done => _round.missing.every(_filled.containsKey);

  /// The slot to fill next: the first empty one, left to right.
  int? get _active => _round.missing.where((i) => !_filled.containsKey(i)).firstOrNull;

  /// A tray tile carrying the letter the active slot needs.
  int? get _answerTile {
    final a = _active;
    if (a == null) return null;
    final used = _filled.values.toSet();
    for (final (i, l) in _round.tiles.indexed) {
      if (l == _word[a] && !used.contains(i)) return i;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  @override
  void dispose() {
    for (final t in [_ask, _idle, _blend, _next]) {
      t?.cancel();
    }
    super.dispose();
  }

  void _newRound() {
    _round = spellRound(widget.c.level, widget.c.random, last: _deal == 0 ? null : _word);
    _filled.clear();
    _wiggles.clear();
    _hops.clear();
    _givenHops.clear();
    _slips = _slipsHere = 0;
    _nudge = _blended = false;
    _lit = _dragging = null;
    _deal++;
    _ask?.cancel();
    // A beat for the tiles to land before the voice.
    _ask = Timer(const Duration(milliseconds: 600), _sayPrompt);
    _waitIdle();
    if (mounted) setState(() {});
  }

  /// The word, then what to do with it.
  void _sayPrompt() {
    if (_done) return widget.c.say(_round.word.clip);
    widget.c.say(_round.word.clip);
    _ask?.cancel();
    _ask = Timer(afterVoice(_round.word.clip), () {
      if (mounted && !_done) widget.c.say(_round.missing.length == 1 ? VoiceLine.spellMissing : VoiceLine.spellBuild);
    });
  }

  /// A long pause lights the tile she needs and says its sound, without
  /// counting a slip.
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 12), () {
      final a = _active;
      if (!mounted || a == null) return;
      widget.c.say(soundClip(_word[a]));
      setState(() => _nudge = true);
      _waitIdle();
    });
  }

  void _tapTile(int i) {
    final slot = _filled.entries.where((e) => e.value == i).firstOrNull?.key;
    widget.c.sound(Sfx.tap, volume: 0.4);
    widget.c.say(soundClip(_round.tiles[i]));
    if (slot != null || _done) {
      // A tile in the word just says its sound again.
      setState(() => _hops[i] = (_hops[i] ?? 0) + 1);
      return;
    }
    _try(i);
  }

  /// Tries tray tile [i] in the active slot.
  void _try(int i) {
    final a = _active;
    if (a == null) return;
    _waitIdle();
    final letter = _round.tiles[i];
    if (letter != _word[a]) {
      _slips++;
      _slipsHere++;
      widget.c.cue();
      setState(() => _wiggles[i] = (_wiggles[i] ?? 0) + 1);
      return;
    }
    widget.c.sound(Sfx.snap, volume: 0.6);
    setState(() {
      _filled[a] = i;
      _slipsHere = 0;
      _nudge = false;
    });
    if (!_done) return;
    _idle?.cancel();
    _ask?.cancel();
    // Its sound finishes, then the word is read back sound by sound.
    _blend = Timer(afterVoice(soundClip(letter), atLeast: const Duration(milliseconds: 700)), () => _sound(0));
  }

  /// Blending: slot [i] hops and says its sound, then the next; after the
  /// last, the letters close up and the voice says the word.
  void _sound(int i) {
    if (!mounted) return;
    if (i == _word.length) {
      widget.c.say(_round.word.clip);
      widget.c.sound(Sfx.sparkle, volume: 0.5);
      setState(() {
        _lit = null;
        _blended = true;
        _pictureHops++;
      });
      _blend = Timer(afterVoice(_round.word.clip, atLeast: const Duration(milliseconds: 900)), () {
        if (!mounted) return;
        unawaited(widget.c.finishRound(spellResult(_slips, missing: _round.missing.length), emoji: _round.word.emoji));
        _next = Timer(const Duration(milliseconds: 2800), _newRound);
      });
      return;
    }
    widget.c.say(soundClip(_word[i]));
    setState(() => _lit = i);
    _blend = Timer(afterVoice(soundClip(_word[i]), atLeast: const Duration(milliseconds: 650)), () => _sound(i + 1));
  }

  Offset _local(Offset global) => (_area.currentContext!.findRenderObject()! as RenderBox).globalToLocal(global);

  void _dragEnd() {
    final i = _dragging, l = _layout, a = _active;
    if (i == null || l == null) return;
    _dragging = null;
    // Dropped on or near any empty slot: it tries the one that's open.
    final near = a != null && _round.missing.any((s) => !_filled.containsKey(s) && (l.slots[s] - _dragAt).distance < l.slot * 0.9);
    if (near) {
      _try(i);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final w = _round.word;
    final single = _round.missing.length == 1;
    return Backdrop(
      top: const Color(0xFFEAF6EE),
      bottom: const Color(0xFFFFF1E0),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(
              key: _area,
              builder: (context, box) {
                final l = _layout = _Layout.of(box.biggest, _word.length, _round.tiles.length, blended: _blended);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: l.picture.dx - l.pictureSize / 2,
                      top: l.picture.dy - l.pictureSize / 2,
                      child: SubjectCard(id: 'spell.picture', word: w, size: l.pictureSize, hops: _pictureHops, onTap: _sayPrompt),
                    ),
                    for (var s = 0; s < _word.length; s++) _slot(s, l),
                    for (var s = 0; s < _word.length; s++)
                      if (!_round.missing.contains(s)) _given(s, l),
                    for (var i = 0; i < _round.tiles.length; i++) _tile(i, l),
                  ],
                );
              },
            ),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'spell.ask',
              label: _done ? 'You built ${w.word}!' : (single ? 'Which sound is missing in ${w.word}?' : 'Build ${w.word}'),
              onSayAgain: _sayPrompt,
              children: [
                DEmoji(w.emoji, size: 40 * t.scale),
                SizedBox(width: t.space.sm),
                for (var s = 0; s < _word.length; s++)
                  Container(
                    width: 22 * t.scale,
                    height: 28 * t.scale,
                    margin: EdgeInsets.symmetric(horizontal: 2 * t.scale),
                    decoration: BoxDecoration(
                      color: _round.missing.contains(s) && !_filled.containsKey(s) ? Colors.white : letterColor(_word[s]).withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(6 * t.scale),
                      border: Border.all(color: const Color(0xFFD9CFF0), width: 2),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The slot's place in the word: a soft well, the open one ringed in gold.
  Widget _slot(int s, _Layout l) {
    final empty = _round.missing.contains(s) && !_filled.containsKey(s);
    final active = empty && _active == s;
    final glow = active && (_nudge || _slipsHere >= 2);
    final letter = empty ? null : _word[s];
    return AnimatedPositioned(
      key: ValueKey('slot.$_deal.$s'),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
      left: l.slots[s].dx - l.slot / 2,
      top: l.slots[s].dy - l.slot / 2,
      child: tid(
        'spell.slot.$s',
        Semantics(
          label: letter != null ? 'Slot ${s + 1}: $letter' : 'Slot ${s + 1}: empty${active ? ', next' : ''}',
          excludeSemantics: true,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: l.slot,
            height: l.slot,
            decoration: BoxDecoration(
              color: empty ? const Color(0x66FFFFFF) : const Color(0x00FFFFFF),
              borderRadius: BorderRadius.circular(l.slot * 0.2),
              border: Border.all(color: empty ? (active ? const Color(0xFFFFC93C) : const Color(0xFFD9CFF0)) : const Color(0x00FFFFFF), width: active ? 5 : 3),
              // A solid halo, not a blur: blurs are too slow to animate on a frame.
              boxShadow: [BoxShadow(color: glow ? const Color(0x88FFD54F) : const Color(0x00FFD54F), spreadRadius: glow ? 10 : 0)],
            ),
          ),
        ),
      ),
    );
  }

  /// One hop when the blending voice reaches [slot]; it stays counted, so
  /// closing up doesn't hop again.
  int _blendHop(int slot) => _blended || (_lit != null && _lit! >= slot) ? 1 : 0;

  /// A letter the word starts with already in place.
  Widget _given(int s, _Layout l) => AnimatedPositioned(
        key: ValueKey('given.$_deal.$s'),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOutCubic,
        left: l.slots[s].dx - l.slot / 2,
        top: l.slots[s].dy - l.slot / 2,
        child: GestureDetector(
          excludeFromSemantics: true,
          behavior: HitTestBehavior.opaque,
          onTap: () {
            widget.c.say(soundClip(_word[s]));
            setState(() => _givenHops[s] = (_givenHops[s] ?? 0) + 1);
          },
          child: Hop(count: (_givenHops[s] ?? 0) + _blendHop(s), child: _LetterTile(letter: _word[s], size: l.slot, lit: _lit == s)),
        ),
      );

  Widget _tile(int i, _Layout l) {
    final letter = _round.tiles[i];
    final slot = _filled.entries.where((e) => e.value == i).firstOrNull?.key;
    final dragging = _dragging == i;
    final center = slot != null ? l.slots[slot] : (dragging ? _dragAt : l.tray[i]);
    final size = slot != null ? l.slot : l.tile;
    final hint = slot == null && _answerTile == i && (_nudge || _slipsHere >= 2);
    final lit = slot != null && _lit == slot;
    final hops = (_hops[i] ?? 0) + (slot == null ? 0 : _blendHop(slot));
    // The box moves and grows from the tray into its slot; the tile fills it.
    return AnimatedPositioned(
      key: ValueKey('tile.$_deal.$i'),
      duration: dragging ? Duration.zero : const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      left: center.dx - size / 2,
      top: center.dy - size / 2,
      width: size,
      height: size,
      child: tid(
        'spell.tile.$i',
        Semantics(
          button: true,
          label: slot != null ? 'Letter $letter, placed' : 'Letter $letter',
          onTap: () => _tapTile(i),
          excludeSemantics: true,
          child: GestureDetector(
            excludeFromSemantics: true,
            dragStartBehavior: DragStartBehavior.down,
            onTap: () => _tapTile(i),
            onPanStart: slot != null || _done
                ? null
                : (d) {
                    widget.c.say(soundClip(letter));
                    setState(() {
                      _dragging = i;
                      _grip = center - _local(d.globalPosition);
                      _dragAt = center;
                    });
                  },
            onPanUpdate: slot != null || _done ? null : (d) => setState(() => _dragAt = _local(d.globalPosition) + _grip),
            onPanEnd: slot != null || _done ? null : (_) => _dragEnd(),
            onPanCancel: slot != null || _done ? null : _dragEnd,
            child: AnimatedScale(
              // The extra letters bow out once the word is whole.
              scale: dragging ? 1.1 : (slot == null && _done ? 0.0 : 1),
              duration: Duration(milliseconds: slot == null && _done ? 450 : 200),
              curve: Curves.easeInBack,
              child: Hop(
                count: hops,
                child: Wiggle(
                  count: _wiggles[i] ?? 0,
                  child: LayoutBuilder(builder: (context, box) => _LetterTile(letter: letter, size: box.maxWidth, glow: hint, lit: lit)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small letter on a cream tile, on the shared baseline (0…14) so a word
/// of tiles reads as a word: b and d reach up, g and p hang down.
class _LetterTile extends StatelessWidget {
  const _LetterTile({required this.letter, required this.size, this.glow = false, this.lit = false});
  final String letter;
  final double size;
  final bool glow, lit;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: lit ? const Color(0xFFFFF0B8) : const Color(0xFFFFFAF0),
        borderRadius: BorderRadius.circular(size * 0.2),
        border: Border.all(color: glow || lit ? const Color(0xFFFFC93C) : const Color(0xFFEAD7B0), width: glow ? 7 : 3),
        boxShadow: [BoxShadow(color: glow ? const Color(0x88FFD54F) : const Color(0x00FFD54F), spreadRadius: glow ? 10 : 0), ...t.elevation.e1],
      ),
      child: GlyphView(letter, height: size * 0.78, color: letterColor(letter), frameTop: 0, frameBottom: 14),
    );
  }
}

/// Where everything sits. A tall or square screen stacks the picture, the
/// word and the tray; a wide one puts the picture on the left. The tray
/// takes two rows (3 + 2) when five tiles won't fit big in one.
class _Layout {
  _Layout(this.picture, this.pictureSize, this.slots, this.slot, this.tray, this.tile);

  factory _Layout.of(Size area, int n, int k, {required bool blended}) {
    final wide = area.width > area.height * 1.45;
    final (left, width) = wide ? (area.width * 0.34, area.width * 0.66) : (0.0, area.width);
    final picture = wide ? Offset(area.width * 0.16, area.height * 0.5) : Offset(area.width / 2, area.height * 0.16);
    final pictureSize = wide ? math.min(area.width * 0.26, area.height * 0.62) : math.min(area.height * 0.27, area.width * 0.56);
    // Word band and tray band, as fractions of the height.
    final (wordY, trayTop, trayBottom) = wide ? (0.3, 0.56, 1.0) : (0.47, 0.64, 1.0);
    final band = area.height * (wide ? 0.44 : 0.26);
    final slot = math.min(math.min(width / (n + (n - 1) * 0.16) * 0.9, band * 0.84), 230.0);
    // Closed up when it's read as one word.
    final gap = slot * (blended ? 0.0 : 0.16);
    final wordWidth = n * slot + (n - 1) * gap;
    final slots = [for (var i = 0; i < n; i++) Offset(left + (width - wordWidth) / 2 + slot / 2 + i * (slot + gap), area.height * wordY)];
    final rows = k > 3 && width < area.height * 0.75 ? 2 : 1;
    final per = (k / rows).ceil();
    final trayHeight = area.height * (trayBottom - trayTop);
    final tile = math.min(math.min(width / (per + (per - 1) * 0.3) * 0.92, trayHeight / rows * 0.78), slot);
    final tray = <Offset>[];
    for (var i = 0; i < k; i++) {
      final row = i ~/ per, inRow = math.min(per, k - row * per), col = i % per;
      final rowWidth = inRow * tile + (inRow - 1) * tile * 0.3;
      tray.add(Offset(left + (width - rowWidth) / 2 + tile / 2 + col * tile * 1.3, area.height * trayTop + trayHeight * (row + 0.5) / rows));
    }
    return _Layout(picture, pictureSize, slots, slot, tray, tile);
  }

  final Offset picture;
  final double pictureSize;
  final List<Offset> slots, tray;
  final double slot, tile;
}
