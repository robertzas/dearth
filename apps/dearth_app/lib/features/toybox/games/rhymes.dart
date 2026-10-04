import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Rhyme Time (SPEC FR-TOY-03, Appendix B: hearing sounds). The voice says
/// a picture ("Cat. What rhymes with cat?") and she picks the one that
/// rhymes from 2 → 4. Every picture says its word when tapped, so she can
/// listen for the rhyme; the right one is cheered with both words ("Cat,
/// hat. They rhyme!"). After two misses the rhyme glows.
class RhymesGame extends StatefulWidget {
  const RhymesGame(this.c, {super.key});
  final GameController c;

  @override
  State<RhymesGame> createState() => RhymesGameState();
}

@visibleForTesting
class RhymesGameState extends State<RhymesGame> {
  RhymeRound? _round;
  final _tried = <String>{};
  final _wiggles = <String, int>{};
  int _slips = 0, _deal = 0, _cheers = 0;
  bool _solved = false;
  Timer? _next, _ask;

  @visibleForTesting
  RhymeRound get debugRound => _round!;

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
    _round = rhymeRound(widget.c.level, widget.c.random, last: _round?.anchor.word);
    _tried.clear();
    _slips = 0;
    _solved = false;
    _deal++;
    _ask?.cancel();
    _ask = Timer(const Duration(milliseconds: 600), _sayPrompt);
    if (mounted) setState(() {});
  }

  void _sayPrompt() => widget.c.say(rhymeAskClip(_round!.anchor));

  void _pick(PictureWord w) {
    final r = _round!;
    if (_solved || _tried.contains(w.word)) return;
    if (w != r.match) {
      _slips++;
      widget.c.cue();
      // Its word, so she hears that it doesn't rhyme.
      widget.c.say(w.clip);
      setState(() {
        _tried.add(w.word);
        _wiggles[w.word] = (_wiggles[w.word] ?? 0) + 1;
      });
      return;
    }
    widget.c.sound(Sfx.sparkle);
    widget.c.say(rhymeYesClip(r.anchor, r.match));
    setState(() {
      _solved = true;
      _cheers++;
    });
    unawaited(widget.c.finishRound(countingResult(_slips), emoji: r.match.emoji));
    _next = Timer(const Duration(milliseconds: 3400), _newRound);
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    return Backdrop(
      top: const Color(0xFFF3EBFF),
      bottom: const Color(0xFFFFF3E6),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 130,
            child: LayoutBuilder(builder: (context, box) {
              final n = r.choices.length;
              // The word to rhyme with, big, above the choices: one row of
              // them on a wide screen, rows of two on a tall one.
              final per = box.maxWidth > box.maxHeight ? n : math.min(n, 2);
              final rows = (n / per).ceil();
              final size = math.min(math.min(box.maxWidth / per * 0.82, box.maxHeight / (rows + 1.3) * 0.72), 260 * t.scale);
              return Center(
                key: ValueKey(_deal),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SubjectCard(id: 'rhymes.word', word: r.anchor, size: size * 1.15, hops: _cheers, onTap: _sayPrompt),
                    SizedBox(height: size * 0.12),
                    TileRows(
                      per: per,
                      children: [
                        for (final w in r.choices)
                          Padding(
                            padding: EdgeInsets.all(size * 0.06),
                            child: PictureTile(
                              id: 'rhymes.choice.${w.word}',
                              label: w.word,
                              size: size,
                              tried: _tried.contains(w.word),
                              hint: _slips >= 2 && w == r.match && !_solved,
                              wiggles: _wiggles[w.word] ?? 0,
                              hops: _solved && w == r.match ? _cheers : 0,
                              onTap: () => _pick(w),
                              child: DEmoji(w.emoji, size: size * 0.62),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'rhymes.ask',
              label: _solved ? '${r.anchor.word}, ${r.match.word}: they rhyme!' : 'What rhymes with ${r.anchor.word}?',
              onSayAgain: _sayPrompt,
              children: [DEmoji('👂', size: 44 * t.scale), SizedBox(width: t.space.xs), DEmoji('🎶', size: 44 * t.scale), DEmoji(_solved ? '💜' : '❓', size: 44 * t.scale)],
            ),
          ),
        ],
      ),
    );
  }
}
