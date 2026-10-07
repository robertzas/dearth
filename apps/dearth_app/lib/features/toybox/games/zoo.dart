import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Name Zoo (SPEC FR-TOY-03, Appendix B: reading first names). Animals
/// queue at the zoo gate; the one at the front holds up an empty name card
/// in a speech bubble. The voice asks ("Find your name!", "Find the name I
/// spell.") and spells the name, a letter-name clip a letter: the names are
/// the family's own, which no bundled clip can say. She taps the card that
/// says it: the name fills the bubble, the animal hops and says "Thank
/// you!", and walks in through the gate. A wrong card wiggles and fades,
/// the bubble shows the name's first letter and the voice spells it again;
/// two slips light the right card. At the top level she builds a short name
/// from letter tiles into slots that show it faintly, each tile saying its
/// letter. A long pause spells the name again.
class ZooGame extends StatefulWidget {
  const ZooGame(this.c, {super.key});
  final GameController c;

  @override
  State<ZooGame> createState() => ZooGameState();
}

@visibleForTesting
class ZooGameState extends State<ZooGame> {
  ZooRound? _round;
  List<String> _queue = const [];
  int _deal = 0, _slips = 0, _slipsHere = 0, _placed = 0, _animalHops = 0;
  bool _solved = false, _walking = false;
  final _tried = <int>{};
  final _used = <int, int>{}; // tile → slot
  final _wiggles = <int, int>{};
  final _hops = <int, int>{};
  final _timers = <Timer>[];
  final _spelling = <Timer>[];
  Timer? _idle;

  @visibleForTesting
  ZooRound get debugRound => _round!;

  /// Build: how many letters are in their slots.
  @visibleForTesting
  int get debugPlaced => _placed;

  /// Build: the tiles already in slots.
  @visibleForTesting
  Set<int> get debugUsed => _used.keys.toSet();

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  @override
  void dispose() {
    for (final t in [..._timers, ..._spelling]) {
      t.cancel();
    }
    _idle?.cancel();
    super.dispose();
  }

  void _after(Duration d, VoidCallback f, {List<Timer>? into}) => (into ?? _timers).add(Timer(d, () {
        if (mounted) f();
      }));

  void _stopSpelling() {
    for (final t in _spelling) {
      t.cancel();
    }
    _spelling.clear();
  }

  void _newRound() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _stopSpelling();
    _idle?.cancel();
    final rng = widget.c.random;
    final r = zooRound(widget.c.level, rng, kid: widget.c.kid.name, family: widget.c.family, last: _round);
    _round = r;
    _queue = ([...kZooAnimals.where((a) => a != r.animal)]..shuffle(rng)).take(2).toList();
    _deal++;
    _slips = _slipsHere = _placed = 0;
    _solved = _walking = false;
    _tried.clear();
    _used.clear();
    _wiggles.clear();
    _hops.clear();
    // The animal steps up before the question.
    _after(const Duration(milliseconds: 600), _ask);
    _waitIdle();
    if (mounted) setState(() {});
  }

  /// The question, then the name spelled out.
  void _ask() {
    final clip = zooAskClip(_round!.mode);
    widget.c.say(clip);
    _spell(after: afterVoice(clip));
  }

  /// Spells the name, a letter a beat, from [after]; a new spelling (or an
  /// answer) cuts the old one off.
  void _spell({Duration after = Duration.zero}) {
    _stopSpelling();
    var at = after;
    for (final clip in zooSpellClips(_round!.name)) {
      _after(at, () => widget.c.say(clip), into: _spelling);
      at += afterVoice(clip, atLeast: const Duration(milliseconds: 650));
    }
  }

  void _sayAgain() {
    _waitIdle();
    _ask();
  }

  /// A long pause spells the name again (not a slip).
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 12), () {
      if (!mounted || _solved) return;
      _ask();
      _waitIdle();
    });
  }

  void _tapCard(int i) {
    final r = _round!;
    if (_solved) return;
    _waitIdle();
    if (r.cards[i] != r.name) {
      if (!_tried.add(i)) return; // already tried: it stays faded
      _slips++;
      widget.c.cue();
      setState(() => _wiggles[i] = (_wiggles[i] ?? 0) + 1);
      // Again, slowly, with the first letter now in the bubble.
      _spell(after: const Duration(milliseconds: 700));
      return;
    }
    _stopSpelling();
    _idle?.cancel();
    widget.c.sound(Sfx.sparkle, volume: 0.5);
    setState(() {
      _solved = true;
      _hops[i] = (_hops[i] ?? 0) + 1;
      _animalHops++;
    });
    _thank();
  }

  void _tapTile(int i) {
    final r = _round!;
    if (_solved || _used.containsKey(i)) return;
    _waitIdle();
    final need = r.letters[_placed];
    final letter = r.tiles[i];
    if (letter != need) {
      _slips++;
      _slipsHere++;
      _stopSpelling();
      widget.c.cue();
      // The letter it needs, by name: what she's listening for.
      widget.c.say(letterNameClip(need));
      setState(() => _wiggles[i] = (_wiggles[i] ?? 0) + 1);
      return;
    }
    _stopSpelling();
    widget.c.sound(Sfx.snap, volume: 0.5);
    widget.c.say(letterNameClip(letter));
    setState(() {
      _used[i] = _placed++;
      _slipsHere = 0;
      _solved = _placed == r.letters.length;
      if (_solved) _animalHops++;
    });
    if (!_solved) return;
    _idle?.cancel();
    _after(afterVoice(letterNameClip(letter), atLeast: const Duration(milliseconds: 600)), _thank);
  }

  /// The animal thanks her and walks in through the gate.
  void _thank() {
    final r = _round!;
    final yes = zooYesClip(r.mode);
    widget.c.say(yes);
    unawaited(widget.c.finishRound(zooResult(r, _slips), emoji: r.animal));
    _after(afterVoice(yes, atLeast: const Duration(milliseconds: 2200)), () {
      setState(() => _walking = true);
      _after(const Duration(milliseconds: 1000), _newRound);
    });
  }

  String _askLabel() {
    final r = _round!;
    if (_solved) return '${r.name}, thank you!';
    return switch (r.mode) {
      ZooMode.own => 'Find your name: ${r.name}',
      ZooMode.family => 'Find the name: ${r.name}',
      ZooMode.build => 'Spell ${r.name}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Backdrop(
      top: const Color(0xFFDDF2FF),
      bottom: const Color(0xFFE2F3D2),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final wide = box.maxWidth > box.maxHeight;
              final gap = t.space.md;
              final scene = _scene(t);
              final choices = LayoutBuilder(builder: (context, b) => _round!.mode == ZooMode.build ? _tilesOf(b.biggest, gap) : _cardsOf(b.biggest, gap));
              return KeyedSubtree(
                key: ValueKey(_deal),
                child: wide
                    ? Row(children: [Expanded(flex: 11, child: scene), SizedBox(width: gap), Expanded(flex: 9, child: choices)])
                    : Column(children: [Expanded(flex: 9, child: scene), SizedBox(height: gap), Expanded(flex: 10, child: choices)]),
              );
            }),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'zoo.ask',
              label: _askLabel(),
              onSayAgain: _sayAgain,
              children: [DEmoji(_round!.mode == ZooMode.own ? widget.c.kid.emoji ?? '🙂' : '🎟️', size: 40 * t.scale), SizedBox(width: t.space.xs), DEmoji('🔤', size: 40 * t.scale)],
            ),
          ),
        ],
      ),
    );
  }

  /// The gate, the animal at the front with its bubble, and the queue.
  Widget _scene(DTheme t) => LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final animal = math.min(h * 0.38, w * 0.3);
        final bubbleW = math.min(w * 0.62, h * 1.5);
        final bubbleH = math.min(h * 0.36, bubbleW * 0.42);
        final ax = w * 0.52, ay = h * 0.94 - animal;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            const Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _GatePainter()))),
            // The queue, waiting their turn.
            for (final (i, a) in _queue.indexed)
              Positioned(
                left: w * (0.76 + i * 0.13) - animal * (0.32 - i * 0.04),
                top: h * 0.94 - animal * (0.64 - i * 0.08),
                child: IgnorePointer(child: DEmoji(a, size: animal * (0.64 - i * 0.08))),
              ),
            // The animal at the front walks in through the gate when it has its card.
            AnimatedPositioned(
              duration: const Duration(milliseconds: 950),
              curve: Curves.easeInCubic,
              left: _walking ? w * 0.18 - animal / 2 : ax - animal / 2,
              top: ay,
              width: animal,
              height: animal,
              child: IgnorePointer(child: Hop(count: _animalHops, child: DEmoji(_round!.animal, size: animal))),
            ),
            if (!_walking)
              Positioned(
                left: (ax + animal * 0.15 - bubbleW / 2).clamp(0, w - bubbleW),
                top: math.max(0, ay - bubbleH - animal * 0.08),
                width: bubbleW,
                height: bubbleH,
                child: _bubble(t, Size(bubbleW, bubbleH)),
              ),
          ],
        );
      });

  /// The speech bubble: the card the animal needs, empty until she finds
  /// it (with the first letter after a slip), or the slots she spells into.
  Widget _bubble(DTheme t, Size size) {
    final r = _round!;
    final pad = size.height * 0.14;
    final Widget inside;
    if (r.mode == ZooMode.build) {
      inside = _slots(size.width - pad * 2, size.height - pad * 2);
    } else if (_solved) {
      inside = FittedBox(fit: BoxFit.scaleDown, child: PrintedWord(r.name, height: size.height * 0.42));
    } else {
      // An empty card; after a slip, the name's first letter on it.
      inside = Container(
        width: size.height * 1.5,
        height: size.height * 0.7,
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.only(left: size.height * 0.12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEF),
          borderRadius: BorderRadius.circular(size.height * 0.1),
          border: Border.all(color: const Color(0xFFE2C08D), width: math.max(2, size.height * 0.025)),
        ),
        child: _slips >= 1 ? GlyphView(r.letters.first, height: size.height * 0.38, color: const Color(0xFF2B2440), frameTop: 0, frameBottom: 14) : null,
      );
    }
    return tid(
      'zoo.board',
      Semantics(
        label: r.mode == ZooMode.build ? (_solved ? '${r.name} spelled' : 'Spelling ${r.name}: $_placed of ${r.letters.length}') : (_solved ? 'Card: ${r.name}' : (_slips >= 1 ? 'Card starting with ${r.letters.first}' : 'An empty card')),
        excludeSemantics: true,
        child: CustomPaint(
          painter: const _BubblePainter(),
          child: Padding(padding: EdgeInsets.all(pad), child: Center(child: inside)),
        ),
      ),
    );
  }

  /// Build: one slot a letter, the name faint in them until each is placed.
  Widget _slots(double width, double height) {
    final r = _round!;
    final n = r.letters.length;
    final side = math.min(height, (width - (n - 1) * 6) / n);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < n; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: side,
            height: side,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: i < _placed ? Colors.white : const Color(0xFFFFFBEF),
              borderRadius: BorderRadius.circular(side * 0.16),
              border: Border.all(color: i == _placed && !_solved ? const Color(0xFFFFB020) : const Color(0xFFE2C08D), width: i == _placed && !_solved ? side * 0.06 : side * 0.03),
            ),
            child: GlyphView(
              r.letters[i],
              height: side * 0.62,
              color: i < _placed ? const Color(0xFF2B2440) : const Color(0x332B2440),
              frameTop: 0,
              frameBottom: 14,
            ),
          ),
        ],
      ],
    );
  }

  /// Name cards, as large as fit: one column or two, whichever lets them
  /// be bigger.
  Widget _cardsOf(Size area, double gap) {
    final r = _round!;
    final n = r.cards.length;
    const aspect = 2.6;
    var best = (cols: 1, h: 0.0);
    // Each card sits in a cell with half a gap of padding all round.
    for (final cols in [1, 2]) {
      final rows = (n / cols).ceil();
      final h = math.min(area.height / rows - gap, (area.width / cols - gap) / aspect);
      if (h > best.h) best = (cols: cols, h: h);
    }
    final h = math.min(best.h, 240.0 * DTheme.of(context).scale);
    final letters = h * 0.42;
    return Center(
      child: TileRows(
        per: best.cols,
        children: [
          for (var i = 0; i < n; i++)
            Padding(
              padding: EdgeInsets.all(gap / 2),
              child: _Card(
                id: 'zoo.card.$i',
                name: r.cards[i],
                label: '${r.cards[i]}${_solved && r.cards[i] == r.name ? ', given' : (_tried.contains(i) ? ', tried' : '')}',
                size: Size(h * aspect, h),
                letters: letters,
                tried: _tried.contains(i),
                glow: !_solved && _slips >= 2 && r.cards[i] == r.name,
                wiggles: _wiggles[i] ?? 0,
                hops: _hops[i] ?? 0,
                onTap: () => _tapCard(i),
              ),
            ),
        ],
      ),
    );
  }

  /// Letter tiles in rows, as large as fit.
  Widget _tilesOf(Size area, double gap) {
    final r = _round!;
    final n = r.tiles.length;
    var best = (cols: n, side: 0.0);
    for (var cols = 2; cols <= n; cols++) {
      final rows = (n / cols).ceil();
      final side = math.min(area.width / cols, area.height / rows) - gap;
      if (side > best.side) best = (cols: cols, side: side);
    }
    final side = math.min(best.side, 200.0 * DTheme.of(context).scale);
    final need = _solved ? null : r.letters[_placed];
    var glowing = false;
    return Center(
      child: TileRows(
        per: best.cols,
        children: [
          for (var i = 0; i < n; i++)
            Padding(
              padding: EdgeInsets.all(gap / 2),
              child: Builder(builder: (context) {
                // Two slips on a letter light one tile that fits.
                final glow = !glowing && need != null && _slipsHere >= 2 && !_used.containsKey(i) && r.tiles[i] == need;
                if (glow) glowing = true;
                return PictureTile(
                  id: 'zoo.tile.$i',
                  label: 'Letter ${r.tiles[i]}${_used.containsKey(i) ? ', used' : ''}',
                  size: side,
                  tried: _used.containsKey(i),
                  hint: glow,
                  wiggles: _wiggles[i] ?? 0,
                  onTap: () => _tapTile(i),
                  child: GlyphView(r.tiles[i], height: side * 0.6, color: letterColor(r.tiles[i]), frameTop: 0, frameBottom: 14),
                );
              }),
            ),
        ],
      ),
    );
  }
}

/// A name card: white, a warm border, the name in the Toybox's print; it
/// fades once tried and glows as a hint.
class _Card extends StatelessWidget {
  const _Card({
    required this.id,
    required this.name,
    required this.label,
    required this.size,
    required this.letters,
    required this.tried,
    required this.glow,
    required this.wiggles,
    required this.hops,
    required this.onTap,
  });
  final String id, name, label;
  final Size size;
  final double letters;
  final bool tried, glow;
  final int wiggles, hops;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final h = size.height;
    return DPressable(
      id: id,
      semanticLabel: label,
      excludeSemantics: true,
      onTap: onTap,
      borderRadius: BorderRadius.circular(h * 0.18),
      child: Hop(
        count: hops,
        child: Wiggle(
          count: wiggles,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: size.width,
            height: h,
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: h * 0.2, vertical: h * 0.12),
            decoration: BoxDecoration(
              color: tried ? const Color(0xFFF1EEF6) : Colors.white,
              borderRadius: BorderRadius.circular(h * 0.18),
              border: Border.all(color: glow ? const Color(0xFFFFC93C) : const Color(0xFFE2C08D), width: glow ? h * 0.07 : h * 0.04),
              // A solid halo, not a blur: blurs are too slow to animate on a frame.
              boxShadow: [BoxShadow(color: glow ? const Color(0x88FFD54F) : const Color(0x00FFD54F), spreadRadius: glow ? 10 : 0), if (!tried) ...t.elevation.e1],
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: PrintedWord(name, height: letters, color: tried ? const Color(0x662B2440) : const Color(0xFF2B2440)),
            ),
          ),
        ),
      ),
    );
  }
}

/// A white speech bubble with a tail down to the animal.
class _BubblePainter extends CustomPainter {
  const _BubblePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height * 0.2;
    final body = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(r));
    final tail = Path()
      ..moveTo(size.width * 0.38, size.height - 1)
      ..lineTo(size.width * 0.42, size.height + size.height * 0.18)
      ..lineTo(size.width * 0.5, size.height - 1)
      ..close();
    final fill = Paint()..color = Colors.white;
    final edge = Paint()
      ..color = const Color(0xFFD9D2E9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, size.height * 0.02);
    canvas
      ..drawPath(tail, fill)
      ..drawRRect(body, fill)
      ..drawRRect(body, edge);
  }

  @override
  bool shouldRepaint(_BubblePainter old) => false;
}

/// The zoo gate: two posts and a green arch, open in the middle.
class _GatePainter extends CustomPainter {
  const _GatePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final postW = math.max(10.0, w * 0.05);
    final top = h * 0.3, bottom = h * 0.96;
    final wood = Paint()..color = const Color(0xFFB4743E);
    final ink = Paint()
      ..color = const Color(0xFF8E5A2C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, postW * 0.12);
    // The path in, under everything.
    canvas.drawOval(Rect.fromLTRB(w * 0.0, bottom - h * 0.06, w * 0.42, bottom + h * 0.04), Paint()..color = const Color(0xFFD9C9A3));
    for (final x in [w * 0.04, w * 0.32]) {
      final post = RRect.fromRectAndRadius(Rect.fromLTWH(x, top, postW, bottom - top), Radius.circular(postW * 0.25));
      canvas
        ..drawRRect(post, wood)
        ..drawRRect(post, ink);
    }
    final arch = Paint()
      ..color = const Color(0xFF4CAF6A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = postW * 1.1
      ..strokeCap = StrokeCap.round;
    final left = w * 0.04 + postW / 2, right = w * 0.32 + postW / 2;
    canvas.drawArc(Rect.fromLTRB(left, top - (right - left) * 0.35, right, top + (right - left) * 0.35), math.pi, math.pi, false, arch);
    // Bunting along the arch.
    const flags = [Color(0xFFFF8A65), Color(0xFFFFD54F), Color(0xFF4FC3F7), Color(0xFFBA68C8), Color(0xFFAED581)];
    for (var i = 0; i < 5; i++) {
      final a = math.pi + math.pi * (i + 0.5) / 5;
      final c = Offset((left + right) / 2 + math.cos(a) * (right - left) / 2, top + math.sin(a) * (right - left) * 0.35);
      final s = postW * 0.7;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - s / 2, c.dy + postW * 0.4)
          ..lineTo(c.dx + s / 2, c.dy + postW * 0.4)
          ..lineTo(c.dx, c.dy + postW * 0.4 + s)
          ..close(),
        Paint()..color = flags[i],
      );
    }
  }

  @override
  bool shouldRepaint(_GatePainter old) => false;
}
