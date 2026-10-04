import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';

/// What Happens Next (SPEC FR-TOY-03 "Sequencing Stories", Appendix B:
/// narrative, cause and effect). A little story in three to five pictures
/// (egg, chick, hen) lies mixed up; she taps what happens first, then
/// next, and each card moves into the numbered line. A finished story plays
/// back, card by card, on a rising tune.
class StoriesGame extends StatefulWidget {
  const StoriesGame(this.c, {super.key});
  final GameController c;

  @override
  State<StoriesGame> createState() => StoriesGameState();
}

@visibleForTesting
class StoriesGameState extends State<StoriesGame> {
  late StoryRound _round;

  /// Card indices in the line, in story order.
  final _line = <int>[];
  final _wiggles = <int, int>{};
  int _slips = 0, _deal = 0, _playing = -1;
  Timer? _next, _player;

  @visibleForTesting
  StoryRound get debugRound => _round;

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  @override
  void dispose() {
    _next?.cancel();
    _player?.cancel();
    super.dispose();
  }

  void _newRound() {
    _round = storyRound(widget.c.level, widget.c.random);
    _line.clear();
    _slips = 0;
    _playing = -1;
    _deal++;
    if (mounted) setState(() {});
  }

  void _tap(int card) {
    if (_line.contains(card) || _line.length == _round.story.length) return;
    final want = _round.story[_line.length];
    if (_round.cards[card] != want) {
      _slips++;
      widget.c.cue();
      setState(() => _wiggles[card] = (_wiggles[card] ?? 0) + 1);
      return;
    }
    widget.c.sound(Sfx.snap);
    setState(() => _line.add(card));
    if (_line.length == _round.story.length) _playBack();
  }

  /// The finished story, card by card, then the round.
  void _playBack() {
    var k = 0;
    void step() {
      if (!mounted) return;
      if (k < _line.length) {
        widget.c.sound(Sfx.blip, rate: math.pow(2, const [0, 4, 7, 12, 16][k.clamp(0, 4)] / 12).toDouble());
        setState(() => _playing = k++);
        _player = Timer(const Duration(milliseconds: 420), step);
      } else {
        setState(() => _playing = -1);
        unawaited(widget.c.finishRound(expansionResult(_slips, size: _round.story.length), emoji: _round.story.last));
        _next = Timer(const Duration(milliseconds: 2400), _newRound);
      }
    }

    _player = Timer(const Duration(milliseconds: 350), step);
  }

  @override
  Widget build(BuildContext context) {
    final r = _round;
    final n = r.story.length;
    return Backdrop(
      top: const Color(0xFFFDF0FF),
      bottom: const Color(0xFFEAF6FF),
      child: PlayArea(
        child: LayoutBuilder(builder: (context, box) {
          final card = math.min(math.min(box.maxWidth / (n + 0.8), box.maxHeight * 0.36), 240.0);
          double x(int k) => box.maxWidth * (k + 0.5) / n;
          final lineY = box.maxHeight * 0.26, trayY = box.maxHeight * 0.74;
          final placedAt = {for (final (k, c) in _line.indexed) c: k};
          // The card that comes next, for the hint.
          final want = _line.length < n ? r.story[_line.length] : null;
          return Stack(
            key: ValueKey(_deal),
            children: [
              for (var k = 0; k < n; k++)
                Positioned(
                  left: x(k) - card / 2,
                  top: lineY - card / 2,
                  width: card,
                  height: card,
                  child: tid('stories.slot.$k', Semantics(label: 'Place ${k + 1}', excludeSemantics: true, child: _Slot(number: k + 1, size: card))),
                ),
              for (var i = 0; i < n; i++)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutBack,
                  left: (placedAt.containsKey(i) ? x(placedAt[i]!) : x(i)) - card / 2,
                  top: (placedAt.containsKey(i) ? lineY : trayY) - card / 2,
                  child: AnimatedScale(
                    scale: placedAt[i] == _playing ? 1.12 : 1,
                    duration: const Duration(milliseconds: 180),
                    child: PictureTile(
                      id: 'stories.card.$i',
                      label: placedAt.containsKey(i) ? 'Place ${placedAt[i]! + 1}: ${r.cards[i]}' : r.cards[i],
                      size: card,
                      hint: _slips >= 2 && !placedAt.containsKey(i) && r.cards[i] == want,
                      wiggles: _wiggles[i] ?? 0,
                      onTap: () => _tap(i),
                      child: DEmoji(r.cards[i], size: card * 0.64),
                    ),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }
}

/// A numbered place in the story's line.
class _Slot extends StatelessWidget {
  const _Slot({required this.number, required this.size});
  final int number;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(color: const Color(0x55A06CD5), width: size * 0.025),
        color: const Color(0x22FFFFFF),
      ),
      child: Center(child: Text('$number', style: t.text.kidDisplay.copyWith(fontSize: size * 0.36, color: const Color(0x55A06CD5)))),
    );
  }
}
