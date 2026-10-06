import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Hear the Sound (SPEC FR-TOY-03, Appendix B: phonics, listening). A
/// parrot asks "Which letter says mmm?" and says the sound again whenever
/// she taps it: the sound alone, no picture word to lean on. She taps the
/// small letter that makes it. A wrong letter says its own sound (so the
/// slip is a comparison she hears) and wiggles; after two, the right one
/// glows, and a long pause has the parrot ask again. The right letter hops,
/// shows its picture and says its name, its sound and its word: "M. Muh,
/// muh, monkey." At the top level the sound is two letters (sh, ch, th),
/// shown together on one tile, beside a lone letter that's nearly right.
class HearGame extends StatefulWidget {
  const HearGame(this.c, {super.key});
  final GameController c;

  @override
  State<HearGame> createState() => HearGameState();
}

@visibleForTesting
class HearGameState extends State<HearGame> {
  HearRound? _round;
  final _tried = <String>{};
  final _wiggles = <String, int>{}, _hops = <String, int>{};
  int _slips = 0, _deal = 0, _parrotHops = 0;
  bool _solved = false;
  Timer? _ask, _idle, _next;

  @visibleForTesting
  HearRound get debugRound => _round!;

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  @override
  void dispose() {
    for (final t in [_ask, _idle, _next]) {
      t?.cancel();
    }
    super.dispose();
  }

  void _newRound() {
    _round = hearRound(widget.c.level, widget.c.random, last: _round?.answer);
    _tried.clear();
    _wiggles.clear();
    _hops.clear();
    _slips = 0;
    _solved = false;
    _deal++;
    _ask?.cancel();
    // A beat for the letters to land before the parrot asks.
    _ask = Timer(const Duration(milliseconds: 600), _sayPrompt);
    _waitIdle();
    if (mounted) setState(() {});
  }

  void _sayPrompt() {
    if (!mounted) return;
    widget.c.say(hearAskClip(_round!.answer));
    setState(() => _parrotHops++);
  }

  /// A long pause: the parrot asks again (not a slip).
  void _waitIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 12), () {
      if (!mounted || _solved) return;
      _sayPrompt();
      _waitIdle();
    });
  }

  /// The parrot says just the sound.
  void _tapParrot() {
    _waitIdle();
    widget.c.say(_solved ? hearYesClip(_round!.answer) : soundClip(_round!.answer));
    setState(() => _parrotHops++);
  }

  void _tap(String choice) {
    final r = _round!;
    if (_solved || _tried.contains(choice)) {
      // Found or already tried: it just says its sound again.
      widget.c.say(choice == r.answer && _solved ? hearYesClip(choice) : soundClip(choice));
      setState(() => _hops[choice] = (_hops[choice] ?? 0) + 1);
      return;
    }
    _waitIdle();
    if (choice != r.answer) {
      _slips++;
      widget.c.cue();
      widget.c.say(soundClip(choice));
      setState(() {
        _tried.add(choice);
        _wiggles[choice] = (_wiggles[choice] ?? 0) + 1;
      });
      return;
    }
    _idle?.cancel();
    widget.c.sound(Sfx.sparkle);
    widget.c.say(hearYesClip(choice));
    setState(() {
      _solved = true;
      _hops[choice] = (_hops[choice] ?? 0) + 1;
      _parrotHops++;
    });
    unawaited(widget.c.finishRound(hearResult(_slips), emoji: _picture(choice).emoji));
    _next = Timer(afterVoice(hearYesClip(choice), atLeast: const Duration(milliseconds: 3200)), _newRound);
  }

  PictureWord _picture(String choice) => choice.length == 1 ? letterSound(choice).picture : digraphOf(choice)!.picture;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    final ask = r.digraph ? 'Which letters say ${r.answer}?' : 'Which letter says ${r.answer}?';
    return Backdrop(
      top: const Color(0xFFE3F2FF),
      bottom: const Color(0xFFEAF7E4),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final n = r.choices.length;
              // One row on a wide screen; rows of two on a tall one. The
              // parrot sits above, a little bigger than a tile.
              final wide = box.maxWidth > box.maxHeight;
              final per = wide ? n : math.min(n, 2);
              final rows = (n / per).ceil();
              // A row's width in tile sizes: two-letter tiles are wider.
              double units(Iterable<String> row) => row.fold(0.0, (w, ch) => w + (ch.length > 1 ? 1.3 : 1) + 0.12);
              final widest = [for (var i = 0; i < n; i += per) units(r.choices.skip(i).take(per))].reduce(math.max);
              final size = math.min(math.min(box.maxWidth / widest * 0.96, box.maxHeight / (rows * 1.14 + 1.3)), 380 * t.scale);
              return Center(
                key: ValueKey(_deal),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Parrot(size: size * 1.05, hops: _parrotHops, onTap: _tapParrot),
                    SizedBox(height: size * 0.14),
                    TileRows(
                      per: per,
                      children: [
                        for (final ch in r.choices)
                          Padding(
                            padding: EdgeInsets.all(size * 0.06),
                            child: PictureTile(
                              id: 'hear.letter.$ch',
                              label: '${ch.length == 1 ? 'Letter' : 'Letters'} $ch${_solved && ch == r.answer ? ', found' : ''}',
                              size: size,
                              // Two letters get a wider tile, so each is as big as a single.
                              width: ch.length > 1 ? size * 1.3 : null,
                              tried: _tried.contains(ch),
                              hint: _slips >= 2 && ch == r.answer && !_solved,
                              wiggles: _wiggles[ch] ?? 0,
                              hops: _hops[ch] ?? 0,
                              onTap: () => _tap(ch),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (final l in ch.split(''))
                                        Padding(
                                          padding: EdgeInsets.symmetric(horizontal: size * 0.02),
                                          child: GlyphView(l, height: size * 0.54, color: letterColor(l), frameTop: 0, frameBottom: 14),
                                        ),
                                    ],
                                  ),
                                  // Its picture, once found.
                                  SizedBox(height: size * 0.3, child: _solved && ch == r.answer ? DEmoji(_picture(ch).emoji, size: size * 0.28) : null),
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
            child: PromptPill(
              id: 'hear.ask',
              label: _solved ? 'You found ${r.answer}!' : ask,
              onSayAgain: _sayPrompt,
              children: [DEmoji('🦜', size: 44 * t.scale), SizedBox(width: t.space.xs), DEmoji('👂', size: 44 * t.scale)],
            ),
          ),
        ],
      ),
    );
  }
}

/// The parrot that says the sound: tap it to hear it again. It bobs each
/// time it speaks.
class _Parrot extends StatelessWidget {
  const _Parrot({required this.size, required this.hops, required this.onTap});
  final double size;
  final int hops;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return DPressable(
      id: 'hear.parrot',
      semanticLabel: 'Parrot: hear the sound again',
      excludeSemantics: true,
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      child: Hop(
        count: hops,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFBFE6C8), width: 4), boxShadow: t.elevation.e1),
          child: DEmoji('🦜', size: size * 0.6),
        ),
      ),
    );
  }
}
