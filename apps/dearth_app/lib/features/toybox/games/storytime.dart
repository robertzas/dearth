import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Story Time (SPEC FR-TOY-03, Appendix B: language, listening, print
/// awareness). A shelf of picture books; she picks one by its cover and the
/// voice says the title and reads it a page at a time. Each page is a
/// painted scene of things she can tap to hear their names, with the
/// sentence printed big underneath (lit while it's read: words on a page
/// are what the voice says). Arrows at the sides turn the pages; the first
/// page's back arrow and the last page's next arrow lead to the shelf. The
/// last page ends "The end!". Free play: longer books join the shelf with
/// visits (four pages → six → eight).
class StoryGame extends StatefulWidget {
  const StoryGame(this.c, {super.key});
  final GameController c;

  @override
  State<StoryGame> createState() => StoryGameState();
}

/// Each book's cover color.
const Map<String, Color> _kCovers = {
  'rabbit': Color(0xFFF7A8C4),
  'duck': Color(0xFFFFD166),
  'bear': Color(0xFFD9A066),
  'balloon': Color(0xFFEF6F8C),
  'rain': Color(0xFF7FB2E5),
  'panda': Color(0xFF8FD3A8),
  'rocket': Color(0xFF9A8CF6),
  'turtle': Color(0xFF4FC1B0),
  'snowman': Color(0xFFA8D4FF),
};

@visibleForTesting
class StoryGameState extends State<StoryGame> {
  late final List<StoryBook> _shelf = storyShelf(widget.c.level);
  StoryBook? _book;
  int _page = 0, _turnDir = 1, _nudges = 0, _opened = 0;
  bool _reading = false, _ended = false, _finished = false;
  final _hops = <int, int>{};
  final _bookHops = <String, int>{};
  final _timers = <Timer>[];

  /// The open book (null on the shelf).
  @visibleForTesting
  StoryBook? get debugBook => _book;

  @visibleForTesting
  int get debugPage => _page;

  @visibleForTesting
  List<StoryBook> get debugShelf => _shelf;

  @override
  void initState() {
    super.initState();
    _after(const Duration(milliseconds: 600), () => widget.c.say(VoiceLine.storyPick));
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  void _cancel() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  void _after(Duration d, VoidCallback f) => _timers.add(Timer(d, () {
        if (mounted) f();
      }));

  void _open(StoryBook book) {
    _cancel();
    widget.c.sound(Sfx.pop, volume: 0.4);
    widget.c.say(book.titleClip);
    setState(() {
      _bookHops[book.id] = (_bookHops[book.id] ?? 0) + 1;
      _book = book;
      _page = 0;
      _turnDir = 1;
      _ended = _finished = false;
      _hops.clear();
      _opened++;
    });
    // The title, then the first page.
    _after(afterVoice(book.titleClip), _readPage);
  }

  /// Reads the page aloud; on the last page, "The end!" follows.
  void _readPage() {
    final book = _book;
    if (book == null) return;
    _cancel();
    final clip = book.pageClip(_page);
    widget.c.say(clip);
    setState(() => _reading = true);
    _after(afterVoice(clip), () {
      setState(() => _reading = false);
      if (_page == book.pages.length - 1) {
        widget.c.say(VoiceLine.storyEnd);
        setState(() => _ended = true);
        if (!_finished) {
          _finished = true;
          // Calm: a story ends quietly, no confetti over the last page.
          unawaited(widget.c.finishRound(GameResult.played, emoji: '📖', calm: true));
        }
        _after(afterVoice(VoiceLine.storyEnd, atLeast: const Duration(seconds: 2)), _nudge);
      } else {
        _nudge();
      }
    });
  }

  /// The arrow forward (or to the shelf) hops now and then while she looks.
  void _nudge() {
    setState(() => _nudges++);
    _after(const Duration(seconds: 8), _nudge);
  }

  void _turn(int by) {
    final book = _book!;
    final to = _page + by;
    if (to < 0 || to >= book.pages.length) return;
    _cancel();
    widget.c.sound(Sfx.blip, volume: 0.35);
    setState(() {
      _page = to;
      _turnDir = by.sign;
      _reading = false;
      _hops.clear();
    });
    // Let the page slide in first.
    _after(const Duration(milliseconds: 350), _readPage);
  }

  void _toShelf() {
    _cancel();
    widget.c.sound(Sfx.blip, volume: 0.35);
    setState(() {
      _book = null;
      _reading = false;
    });
    _after(const Duration(milliseconds: 400), () => widget.c.say(VoiceLine.storyPick));
  }

  void _tapThing(int i, StoryThing thing) {
    widget.c.say(thing.picture.clip);
    setState(() => _hops[i] = (_hops[i] ?? 0) + 1);
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final book = _book;
    return Backdrop(
      top: const Color(0xFFFFF4E0),
      bottom: const Color(0xFFF3EAFB),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(top: 140, child: book == null ? _buildShelf(t) : _buildBook(t, book)),
          TopPrompt(
            child: book == null
                ? PromptPill(
                    id: 'story.ask',
                    label: 'Pick a story',
                    onSayAgain: () => widget.c.say(VoiceLine.storyPick),
                    children: [DEmoji('📚', size: 40 * t.scale), SizedBox(width: t.space.xs), DEmoji('👆', size: 40 * t.scale)],
                  )
                : PromptPill(
                    id: 'story.ask',
                    label: book.title,
                    onSayAgain: _readPage,
                    children: [DEmoji(book.coverPicture.emoji, size: 40 * t.scale), SizedBox(width: t.space.xs), DEmoji('📖', size: 40 * t.scale)],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildShelf(DTheme t) => LayoutBuilder(builder: (context, box) {
        final n = _shelf.length;
        final per = box.maxWidth > box.maxHeight ? math.min(n, 3) : math.min(n, 2);
        final rows = (n / per).ceil();
        final gap = t.space.lg;
        // Books stand taller than wide, as books do.
        final w = math.min(box.maxWidth / per - gap, (box.maxHeight / rows - gap) * 0.78);
        return Center(
          child: TileRows(
            per: per,
            children: [
              for (final b in _shelf)
                Padding(
                  padding: EdgeInsets.all(gap / 2),
                  child: DPressable(
                    id: 'story.book.${b.id}',
                    semanticLabel: b.title,
                    excludeSemantics: true,
                    onTap: () => _open(b),
                    borderRadius: BorderRadius.circular(w * 0.08),
                    child: Hop(count: _bookHops[b.id] ?? 0, child: _Cover(book: b, width: w)),
                  ),
                ),
            ],
          ),
        );
      });

  Widget _buildBook(DTheme t, StoryBook book) => LayoutBuilder(builder: (context, box) {
        final page = book.pages[_page];
        final first = _page == 0, last = _page == book.pages.length - 1;
        final wide = box.maxWidth > box.maxHeight;
        final arrow = (box.biggest.shortestSide * 0.15).clamp(56.0, 150.0);
        final gap = t.space.md;
        // The picture and its words; the arrows beside them on a wall, under them on a phone.
        final sideW = wide ? box.maxWidth - 2 * (arrow + gap) : box.maxWidth;
        final textH = (box.maxHeight * (wide ? 0.2 : 0.16)).clamp(48.0, 220.0);
        final roomH = box.maxHeight - textH - gap - (wide ? 0 : arrow + gap);
        // Between 4:3 and 2:1, as big as fits.
        final sceneH = math.min(roomH, sideW / (4 / 3));
        final sceneW = math.min(sideW, sceneH * 2);
        final back = first
            ? _Arrow(id: 'story.shelf', label: 'Back to the books', emoji: '📚', size: arrow, hops: 0, onTap: _toShelf)
            : _Arrow(id: 'story.back', label: 'Page back', forward: false, size: arrow, hops: 0, onTap: () => _turn(-1));
        final next = last
            ? _Arrow(id: 'story.shelf', label: 'Back to the books', emoji: '📚', size: arrow, hops: _ended ? _nudges : 0, glow: _ended, onTap: _toShelf)
            : _Arrow(id: 'story.next', label: 'Next page', size: arrow, hops: _nudges, glow: !_reading, onTap: () => _turn(1));
        final pageView = TweenAnimationBuilder<double>(
          // Each page slides in from the side it was turned from.
          key: ValueKey('$_opened.$_page'),
          tween: Tween(begin: _turnDir * sceneW * 0.08, end: 0),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          builder: (context, dx, child) => Transform.translate(offset: Offset(dx, 0), child: child),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Scene(page: page, width: sceneW, height: sceneH, hops: _hops, onTap: _tapThing),
              SizedBox(height: gap),
              _Words(page: page, label: 'Page ${_page + 1} of ${book.pages.length}: ${page.text}', width: sceneW, height: textH, reading: _reading),
            ],
          ),
        );
        if (wide) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [back, SizedBox(width: gap), pageView, SizedBox(width: gap), next],
          );
        }
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            pageView,
            SizedBox(height: gap),
            SizedBox(width: sceneW, child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [back, next])),
          ],
        );
      });
}

/// A book standing on the shelf: a colored cover with a darker spine, the
/// pages' edge, and its picture big in the middle.
class _Cover extends StatelessWidget {
  const _Cover({required this.book, required this.width});
  final StoryBook book;
  final double width;

  @override
  Widget build(BuildContext context) {
    final color = _kCovers[book.id] ?? const Color(0xFFB9A7F5);
    final h = width / 0.78;
    final r = width * 0.08;
    return SizedBox(
      width: width,
      height: h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.only(topRight: Radius.circular(r), bottomRight: Radius.circular(r), topLeft: Radius.circular(r * 0.4), bottomLeft: Radius.circular(r * 0.4)),
          border: Border.all(color: Color.lerp(color, const Color(0xFF2B2440), 0.35)!, width: math.max(2, width * 0.012)),
          boxShadow: const [BoxShadow(color: Color(0x332B2440), offset: Offset(0, 6), blurRadius: 10)],
        ),
        child: Row(
          children: [
            // The spine.
            Container(width: width * 0.1, color: Color.lerp(color, const Color(0xFF2B2440), 0.22)),
            Expanded(
              child: Center(
                child: Container(
                  width: width * 0.66,
                  height: width * 0.66,
                  decoration: const BoxDecoration(color: Color(0xF2FFFFFF), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: DEmoji(book.coverPicture.emoji, size: width * 0.42),
                ),
              ),
            ),
            // The pages' edge.
            Container(
              width: width * 0.04,
              margin: EdgeInsets.symmetric(vertical: h * 0.04),
              decoration: BoxDecoration(color: const Color(0xFFFFFBF2), borderRadius: BorderRadius.horizontal(right: Radius.circular(r * 0.4))),
            ),
          ],
        ),
      ),
    );
  }
}

/// The page's picture: its painted backdrop and the things in it, each one
/// a tap that says its name.
class _Scene extends StatelessWidget {
  const _Scene({required this.page, required this.width, required this.height, required this.hops, required this.onTap});
  final StoryPage page;
  final double width, height;
  final Map<int, int> hops;
  final void Function(int i, StoryThing thing) onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height * 0.06);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: Colors.white, width: math.max(3, height * 0.018)),
        boxShadow: const [BoxShadow(color: Color(0x2E2B2440), offset: Offset(0, 6), blurRadius: 12)],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _ScenePainter(page.scene)))),
            for (final (i, thing) in page.things.indexed)
              Positioned(
                left: thing.x * width - thing.size * height / 2,
                top: thing.y * height - thing.size * height / 2,
                width: thing.size * height,
                height: thing.size * height,
                child: DPressable(
                  id: 'story.thing.$i',
                  semanticLabel: thing.word,
                  excludeSemantics: true,
                  onTap: () => onTap(i, thing),
                  borderRadius: BorderRadius.circular(thing.size * height / 2),
                  child: Hop(count: hops[i] ?? 0, child: Center(child: DEmoji(thing.picture.emoji, size: thing.size * height * 0.9))),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The sentence, printed big under the picture; it lights while it's read.
class _Words extends StatelessWidget {
  const _Words({required this.page, required this.label, required this.width, required this.height, required this.reading});
  final StoryPage page;
  final String label;
  final double width, height;
  final bool reading;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return tid(
      'story.page',
      Semantics(
        label: label,
        excludeSemantics: true,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: width,
          height: height,
          padding: EdgeInsets.symmetric(horizontal: height * 0.3, vertical: height * 0.12),
          decoration: BoxDecoration(
            color: reading ? const Color(0xFFFFF3C4) : Colors.white,
            borderRadius: BorderRadius.circular(height * 0.3),
            border: Border.all(color: reading ? const Color(0xFFFFC93C) : const Color(0xFFE6DDF3), width: math.max(2, height * 0.03)),
          ),
          alignment: Alignment.center,
          // Shrinks to fit rather than overflow on a small screen.
          // Wraps at the box's width, big; shrinks only if two lines won't fit.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: math.max(40, width - height * 0.6)),
              child: Text(
                page.text,
                textAlign: TextAlign.center,
                style: t.text.kidTitle.copyWith(fontSize: (height * 0.36).clamp(16.0, 72.0), height: 1.15, color: const Color(0xFF2B2440)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A big round page-turn button: an arrow, or the shelf's books.
class _Arrow extends StatelessWidget {
  const _Arrow({required this.id, required this.label, required this.size, required this.hops, required this.onTap, this.forward = true, this.emoji, this.glow = false});
  final String id, label;

  /// Points right (a page on), else left.
  final bool forward;
  final String? emoji;
  final double size;
  final int hops;
  final bool glow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DPressable(
      id: id,
      semanticLabel: label,
      excludeSemantics: true,
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      child: Hop(
        count: hops,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: glow ? const Color(0xFFFFC93C) : const Color(0xFFD9D2E9), width: size * (glow ? 0.07 : 0.04)),
            boxShadow: const [BoxShadow(color: Color(0x262B2440), offset: Offset(0, 4), blurRadius: 8)],
          ),
          alignment: Alignment.center,
          child: emoji != null ? DEmoji(emoji!, size: size * 0.5) : CustomPaint(size: Size.square(size * 0.5), painter: _ArrowPainter(forward: forward)),
        ),
      ),
    );
  }
}

/// A fat rounded arrow, drawn in code (no icon font on the frame's kid screens).
class _ArrowPainter extends CustomPainter {
  const _ArrowPainter({required this.forward});
  final bool forward;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (!forward) {
      canvas
        ..translate(w, 0)
        ..scale(-1, 1);
    }
    final paint = Paint()
      ..color = const Color(0xFF6B4FD8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.17
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawLine(Offset(w * 0.12, h / 2), Offset(w * 0.86, h / 2), paint)
      ..drawPath(
        Path()
          ..moveTo(w * 0.52, h * 0.16)
          ..lineTo(w * 0.86, h / 2)
          ..lineTo(w * 0.52, h * 0.84),
        paint,
      );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.forward != forward;
}

/// A page's backdrop, painted flat: sky (or water, or a party wall), and
/// the ground things stand on, starting at about 62% down.
class _ScenePainter extends CustomPainter {
  const _ScenePainter(this.scene);
  final StoryScene scene;

  static const _ground = 0.62;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    void sky(Color top, Color bottom) => canvas.drawRect(
          Offset.zero & size,
          Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom]).createShader(Offset.zero & size),
        );
    // Two soft hills: the far one lighter, the near one the ground itself.
    void hills(Color far, Color near) {
      canvas.drawPath(
        Path()
          ..moveTo(0, h * (_ground - 0.02))
          ..quadraticBezierTo(w * 0.22, h * (_ground - 0.14), w * 0.5, h * (_ground - 0.03))
          ..quadraticBezierTo(w * 0.78, h * (_ground - 0.12), w, h * (_ground - 0.04))
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close(),
        Paint()..color = far,
      );
      canvas.drawPath(
        Path()
          ..moveTo(0, h * (_ground + 0.04))
          ..quadraticBezierTo(w * 0.5, h * (_ground - 0.04), w, h * (_ground + 0.03))
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close(),
        Paint()..color = near,
      );
    }

    // Dots scattered the same way every time (stars, snow, bubbles).
    void dots(int n, Color color, double r, {double from = 0, double to = 1, bool ring = false}) {
      final rng = math.Random(n * 31 + scene.index);
      final paint = Paint()
        ..color = color
        ..style = ring ? PaintingStyle.stroke : PaintingStyle.fill
        ..strokeWidth = r * 0.35;
      for (var i = 0; i < n; i++) {
        canvas.drawCircle(Offset(rng.nextDouble() * w, h * (from + rng.nextDouble() * (to - from))), r * (0.6 + rng.nextDouble() * 0.6), paint);
      }
    }

    switch (scene) {
      case StoryScene.day:
        sky(const Color(0xFF8FD3FF), const Color(0xFFDDF3FF));
        hills(const Color(0xFFB5E3A1), const Color(0xFF8BD17C));
      case StoryScene.sunset:
        sky(const Color(0xFFFF9E7A), const Color(0xFFFFD99A));
        hills(const Color(0xFF9CC98A), const Color(0xFF6FAE6A));
      case StoryScene.night:
        sky(const Color(0xFF1E2A5A), const Color(0xFF3E4C8C));
        dots(26, const Color(0xCCFFFFFF), h * 0.008, to: _ground - 0.1);
        hills(const Color(0xFF3C6A5C), const Color(0xFF2E5A4E));
      case StoryScene.rain:
        sky(const Color(0xFF98A8B8), const Color(0xFFD0DAE3));
        hills(const Color(0xFF9CC79A), const Color(0xFF79B472));
        final streak = Paint()
          ..color = const Color(0x997FB2E5)
          ..strokeWidth = math.max(1.5, h * 0.006)
          ..strokeCap = StrokeCap.round;
        final rng = math.Random(7);
        for (var i = 0; i < 40; i++) {
          final p = Offset(rng.nextDouble() * w, rng.nextDouble() * h * 0.9);
          canvas.drawLine(p, p + Offset(-h * 0.015, h * 0.05), streak);
        }
      case StoryScene.beach:
        sky(const Color(0xFF8FD3FF), const Color(0xFFDDF3FF));
        canvas.drawRect(Rect.fromLTRB(0, h * 0.44, w, h), Paint()..color = const Color(0xFF4FB3E8));
        final sand = Path()..moveTo(0, h * (_ground + 0.02));
        for (var i = 0; i <= 6; i++) {
          sand.quadraticBezierTo(w * (i + 0.5) / 6, h * (_ground - 0.03), w * (i + 1) / 6, h * (_ground + 0.02));
        }
        sand
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close();
        canvas.drawPath(sand, Paint()..color = const Color(0xFFF2D79B));
      case StoryScene.sea:
        sky(const Color(0xFF5BC0EB), const Color(0xFF1F6FA8));
        dots(14, const Color(0x88FFFFFF), h * 0.014, to: 0.85, ring: true);
        canvas.drawPath(
          Path()
            ..moveTo(0, h * 0.9)
            ..quadraticBezierTo(w * 0.3, h * 0.85, w * 0.6, h * 0.9)
            ..quadraticBezierTo(w * 0.85, h * 0.94, w, h * 0.88)
            ..lineTo(w, h)
            ..lineTo(0, h)
            ..close(),
          Paint()..color = const Color(0xFFE8C987),
        );
      case StoryScene.space:
        sky(const Color(0xFF141B3D), const Color(0xFF2E2A6B));
        dots(60, const Color(0xDDFFFFFF), h * 0.006);
      case StoryScene.snow:
        sky(const Color(0xFFC9DEF2), const Color(0xFFEFF6FC));
        hills(const Color(0xFFE4EEF8), const Color(0xFFFFFFFF));
        dots(40, const Color(0xEEFFFFFF), h * 0.01, to: 0.95);
      case StoryScene.party:
        sky(const Color(0xFFFFE3EC), const Color(0xFFFFF3E0));
        canvas.drawRect(Rect.fromLTRB(0, h * (_ground + 0.04), w, h), Paint()..color = const Color(0xFFE9C9A6));
        // Bunting across the top.
        const flags = [Color(0xFFEF6F8C), Color(0xFFFFD166), Color(0xFF6CC070), Color(0xFF7FB2E5), Color(0xFFA78BFA)];
        const n = 11;
        final string = Paint()
          ..color = const Color(0xFF8C7A99)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, h * 0.005);
        final sag = Path()
          ..moveTo(0, h * 0.06)
          ..quadraticBezierTo(w / 2, h * 0.16, w, h * 0.06);
        canvas.drawPath(sag, string);
        for (var i = 0; i < n; i++) {
          final x = w * (i + 0.5) / n;
          // On the string's curve: y = a quadratic through the three points.
          final f = x / w;
          final y = h * (0.06 + 0.2 * f * (1 - f));
          final fw = w / n * 0.36;
          canvas.drawPath(
            Path()
              ..moveTo(x - fw, y)
              ..lineTo(x + fw, y)
              ..lineTo(x, y + fw * 1.5)
              ..close(),
            Paint()..color = flags[i % flags.length],
          );
        }
    }
  }

  @override
  bool shouldRepaint(_ScenePainter old) => old.scene != scene;
}
