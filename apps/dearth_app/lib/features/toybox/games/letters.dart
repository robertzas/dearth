import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Letter Sounds (SPEC FR-TOY-03, Appendix B: phonics). First she just
/// listens: each letter she taps says its name, its sound and its picture
/// ("B. Buh, buh, ball.") and shows the picture. Then the voice asks her to
/// find a letter, then which letter a picture starts with. A wrong letter
/// says its own name (or the sound again); after two, the right one glows.
class LettersGame extends StatefulWidget {
  const LettersGame(this.c, {super.key});
  final GameController c;

  @override
  State<LettersGame> createState() => LettersGameState();
}

@visibleForTesting
class LettersGameState extends State<LettersGame> {
  LetterRound? _round;
  final _heard = <String>{};
  final _tried = <String>{};
  final _wiggles = <String, int>{};
  final _hops = <String, int>{};
  int _slips = 0, _deal = 0;
  bool _solved = false;
  Timer? _next, _ask;

  @visibleForTesting
  LetterRound get debugRound => _round!;

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
    final name = widget.c.kid.name.trim();
    _round = letterRound(widget.c.level, widget.c.random, favorite: name.isEmpty ? null : name[0], last: _round?.answer?.letter);
    _heard.clear();
    _tried.clear();
    _slips = 0;
    _solved = false;
    _deal++;
    _ask?.cancel();
    // A beat for the new letters to land before the question.
    _ask = Timer(const Duration(milliseconds: 600), _sayPrompt);
    if (mounted) setState(() {});
  }

  void _sayPrompt() {
    final r = _round!;
    switch (r.mode) {
      case LetterMode.hear:
        break;
      case LetterMode.find:
        widget.c.say(findLetterClip(r.answer!.letter));
      case LetterMode.firstSound:
        widget.c.say(firstSoundClip(r.word!));
    }
  }

  void _tap(LetterSound l) {
    final r = _round!;
    if (r.mode == LetterMode.hear) {
      widget.c.say(letterClip(l.letter));
      setState(() {
        _heard.add(l.letter);
        _hops[l.letter] = (_hops[l.letter] ?? 0) + 1;
      });
      if (_heard.length == r.letters.length && !_solved) {
        _solved = true;
        // After the last letter has had its say.
        _next = Timer(const Duration(milliseconds: 1800), () {
          unawaited(widget.c.finishRound(GameResult.win, emoji: l.picture.emoji));
          _next = Timer(const Duration(milliseconds: 2400), _newRound);
        });
      }
      return;
    }
    if (_solved || _tried.contains(l.letter)) return;
    if (l != r.answer) {
      _slips++;
      widget.c.cue();
      widget.c.say(r.mode == LetterMode.find ? letterNameClip(l.letter) : firstSoundHintClip(r.word!));
      setState(() {
        _tried.add(l.letter);
        _wiggles[l.letter] = (_wiggles[l.letter] ?? 0) + 1;
      });
      return;
    }
    widget.c.sound(Sfx.sparkle);
    widget.c.say(r.mode == LetterMode.find ? letterClip(l.letter) : firstSoundHintClip(r.word!));
    setState(() {
      _solved = true;
      _hops[l.letter] = (_hops[l.letter] ?? 0) + 1;
    });
    unawaited(widget.c.finishRound(countingResult(_slips), emoji: (r.word ?? l.picture).emoji));
    _next = Timer(const Duration(milliseconds: 3200), _newRound);
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    final (label, pill) = switch (r.mode) {
      LetterMode.hear => ('Tap a letter to hear it', [DEmoji('👂', size: 44 * t.scale), SizedBox(width: t.space.xs), DEmoji('🔤', size: 44 * t.scale)]),
      LetterMode.find => (_solved ? 'You found it!' : 'Find the letter ${r.answer!.letter}', [DEmoji('🔍', size: 44 * t.scale), SizedBox(width: t.space.xs), DEmoji('❓', size: 44 * t.scale)]),
      LetterMode.firstSound => (
          _solved ? 'You found it!' : 'Which letter does ${r.word!.word} start with?',
          [DEmoji('👂', size: 44 * t.scale), SizedBox(width: t.space.xs), DEmoji('🔤', size: 44 * t.scale), DEmoji('❓', size: 44 * t.scale)],
        ),
    };
    return Backdrop(
      top: const Color(0xFFFFF4E0),
      bottom: const Color(0xFFE8F4FF),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final n = r.letters.length;
              // One row on a wide screen; rows of two on a tall one. The
              // picture a first sound is asked about goes above, big.
              final per = box.maxWidth > box.maxHeight ? n : math.min(n, 2);
              final rows = (n / per).ceil();
              final subject = r.mode == LetterMode.firstSound ? r.word : null;
              final bands = rows + (subject == null ? 0 : 1.3);
              final size = math.min(math.min(box.maxWidth / per * 0.84, box.maxHeight / bands * 0.72), 300 * t.scale);
              return Center(
                key: ValueKey(_deal),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (subject != null) ...[
                      SubjectCard(id: 'letters.picture', word: subject, size: size * 1.15, hops: _solved ? 1 : 0, onTap: _sayPrompt),
                      SizedBox(height: size * 0.12),
                    ],
                    TileRows(
                      per: per,
                      children: [
                        for (final l in r.letters)
                          Padding(
                            padding: EdgeInsets.all(size * 0.06),
                            child: PictureTile(
                              id: 'letters.letter.${l.letter}',
                              label: 'Letter ${l.letter}${_heard.contains(l.letter) ? ', heard' : ''}',
                              size: size,
                              tried: _tried.contains(l.letter),
                              hint: _slips >= 2 && l == r.answer && !_solved,
                              wiggles: _wiggles[l.letter] ?? 0,
                              hops: _hops[l.letter] ?? 0,
                              onTap: () => _tap(l),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  LetterPair(l.letter, height: size * (r.mode == LetterMode.hear ? 0.5 : 0.62)),
                                  // Her picture word, once she has heard it.
                                  if (r.mode == LetterMode.hear) SizedBox(height: size * 0.3, child: _heard.contains(l.letter) ? DEmoji(l.picture.emoji, size: size * 0.26) : null),
                                ],
                              ),
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
            child: PromptPill(id: 'letters.ask', label: label, onSayAgain: r.mode == LetterMode.hear ? null : _sayPrompt, children: pill),
          ),
        ],
      ),
    );
  }
}
