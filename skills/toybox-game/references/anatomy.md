# Anatomy of a Toybox game

Where everything lives, the APIs a game uses, and templates in the house
style (lines run long, ~160–200 columns; don't `dart format` existing
files; comments say *why*).

## Contents

1. File map
2. The game host (`GameController`) and the shared widgets
3. Sounds
4. Existing games by mechanic (copy from the closest)
5. Template: core rules
6. Template: the game widget
7. Template: widget tests
8. Template: E2E journey
9. Naming

## 1. File map

| What | Where |
|---|---|
| Catalog (`GameInfo`: id, title, emoji, `minMonths`, skills, levels, `freePlay`) | `packages/dearth_core/lib/src/toybox/games.dart` (`kLaunchGames`, `kExpansionGames`) |
| Ladder and results (`nextLevel`, `freePlayLevel`, `startLevel`, `GameResult`) | same file |
| Result helpers (`resultFor(slips, allowed:)`, `countingResult`) | `packages/dearth_core/lib/src/toybox/rounds.dart` |
| A game's rules | `packages/dearth_core/lib/src/toybox/<game>.dart`, exported from `packages/dearth_core/lib/dearth_core.dart` |
| Words, letters, rhymes, pictures | `toybox/words.dart` (`kWords`, `kLetterSounds`, `kRhymes`, `voiceSlug`) |
| Voice lines and clip ids | `toybox/voice.dart` (see `voice.md`) |
| Core tests | `packages/dearth_core/test/toybox_*_test.dart` (`toybox_test.dart` holds the Emoji 12 guard) |
| Playfield | `apps/dearth_app/lib/features/toybox/games/<game>.dart` |
| Registry (id → builder; unregistered games stay hidden) | `apps/dearth_app/lib/features/toybox/games/registry.dart` |
| Host: levels, recording, celebration, time limits | `apps/dearth_app/lib/features/toybox/game_host.dart` |
| Launcher, painted tile icons (`GameIcon`), tile hues | `apps/dearth_app/lib/features/toybox/toybox_screen.dart` |
| Shared game widgets | `games/game_widgets.dart`, `games/voice_widgets.dart` |
| Sound effects, voice playback | `apps/dearth_app/lib/core/sound.dart` (+ `sound_native.dart`, `sound_web.dart`) |
| Voice clips | `apps/dearth_app/assets/voice/<clip>.mp3` (Git LFS) |
| Widget tests and helpers | `apps/dearth_app/test/toybox_*_test.dart`, `test/support/app_harness.dart`, `test/support/toybox_harness.dart` |
| E2E journeys and helpers | `e2e/tests/toybox*.spec.ts`, `e2e/tests/helpers.ts` |
| Docs | `SPEC.md` §10.8 + Appendix B, `README.md` (Toybox paragraph), `PROGRESS.md` |

## 2. The game host and shared widgets

A game gets a `GameController c` and nothing else from the app; it never
reads Riverpod providers or the clock itself.

| `c.` | Use |
|---|---|
| `level` | The level for this round (the host recomputes it after each `finishRound`). |
| `random` | The round source of randomness (`math.Random`). |
| `kid` | The `Profile` playing: `kid.name` (tracing her name, a favorite letter). |
| `game` | Its `GameInfo`. |
| `sound(Sfx, volume:, rate:)` | An effect at the Toybox volume (capped by grown-ups). |
| `say(clipId)` | A voice clip; stops the previous one. |
| `cue()` | The gentle "try again" sound. Show your own hint alongside. |
| `finishRound(result, emoji:, level:, calm:)` | Records the round (`game_events`), celebrates unless `miss` or `calm`, moves the ladder. Await nothing after it; schedule the next round with a `Timer`. |

The host also draws the home button (top left, `game.home`), the "minutes
left" chip and the bedtime screen, and records free-play sessions when the
kid leaves (at least 3 s).

Shared widgets (read their doc comments before use):

- `Backdrop(top:, bottom:, child:)`: the soft two-color background.
- `PlayArea(top: 96…140, child:)`: padded, safe area under the home row;
  use `top: 140` when a `TopPrompt` sits above.
- `PictureTile(id:, label:, size:, onTap:, tried:, hint:, wiggles:, hops:)`:
  a choosable white tile that fades when tried, glows as a hint, and keeps
  its handler (and its web test id) in every state.
- `Hop(count:)` / `Wiggle(count:)`: one hop or shake each time `count`
  grows. They remount their child: wrap only stateless content.
- `TopPrompt(child: PromptPill(id:, label:, onSayAgain:, children: [...]))`:
  the picture pill at the top with a 🔊 say-again button (`<id>.again`).
- `GamePill(children:)` (in `game_host.dart`): the pill without voice.
- `TileRows(per:, children:)`: fixed rows of `per` tiles, centred (games
  pass two per row on tall screens).
- `SubjectCard(id:, word:, size:, onTap:, hops:)`: the big "question"
  picture.
- `GlyphView` / `LetterPair`: ball-and-stick letters in Montessori colors
  (vowels blue, consonants red), the shapes the tracing game teaches.
- From `dearth_ui`: `DPressable(id:, semanticLabel:, excludeSemantics:,
  selected:, onTap:, borderRadius:, pressedScale:)`, `DEmoji(e, size:)`,
  `tid(id, child)`, `DTheme.of(context)` (`t.scale`, `t.space`, `t.radius`,
  `t.elevation`, `t.text.kidTitle`, `t.policy`).

## 3. Sounds

`Sfx` (in `core/sound.dart`): `pop`, `sparkle`, `boing`, `snap`, `munch`,
`nope` (what `cue()` plays), `cheer` (the host plays it on wins), `blip`,
`tap`, `success`; instruments `xylophone` (one bar, pitched by `rate`),
`kick`, `snare`, `hat`, `tom`; animals `cow`, `pig`, `sheep`, `rooster`,
`chicken`, `horse`, `dog`, `cat`, `frog`, `owl` (CC0 recordings, 1–2 s).

A xylophone note at MIDI `m`: `c.sound(Sfx.xylophone, rate: math.pow(2,
(m - kXylophoneBaseMidi) / 12).toDouble())`. A pentatonic run (60, 62, 64,
67, 69, 72…) can't sound wrong, which suits toddlers. Effects are
synthesized in `core/synth.dart`; a new one goes there, not into assets.

## 4. Existing games by mechanic

Read the closest one before writing yours; reuse its structure.

- **Tap to choose** (prompt, tiles, hint after two slips): `letters.dart`,
  `rhymes.dart`, `ispy.dart`, `oddone.dart`, `patterns.dart`,
  `counting.dart`, `sizes.dart`, `stories.dart`, `sudoku.dart`.
- **Find in a scene**: `differences.dart`, `ispy.dart`.
- **Drag to a target** (snap when close, float back otherwise):
  `shapes.dart`, `shadows.dart`, `jigsaw.dart`, `monster.dart`.
- **Trace or steer with a finger** (a `Listener` with geometry hit tests):
  `tracing.dart` (numbers too), `mazes.dart`.
- **Painting and free play**: `paint.dart`, `coloring.dart`, `music.dart`,
  `bubbles.dart`, `creature.dart`, `breathe.dart` (`calm: true`).
- **Memory and listening**: `memory.dart`, `farm.dart`.

## 5. Template: core rules

```dart
import 'dart:math';

import 'package:meta/meta.dart';

import 'games.dart';
import 'rounds.dart';

// Frog Hop (SPEC FR-TOY-03, Appendix B: number line, one more and one
// less, first adding). A frog sits on numbered lily pads; the voice asks
// for a pad ("Hop to six!"), then for one more or one less than where it
// sits, then for a sum as hops. Drawing lives in the app.

enum HopMode { find, oneMore, add }

@immutable
class HopRound {
  const HopRound(this.mode, this.pads, this.from, this.target);
  final HopMode mode;

  /// The pads on screen, in order (0–5, then 0–10).
  final List<int> pads;
  final int from, target;
}

/// A round at [level] (Appendix B ladder: 0–5 → 0–10 → one more or less →
/// adding), never the same target twice in a row.
HopRound hopRound(int level, Random rng, {int? last}) {
  …
}

/// Two tries are fine on a number line; more means it was too hard.
String hopResult(int slips) => resultFor(slips, allowed: 1);
```

Core test (in `packages/dearth_core/test/toybox_<family>_test.dart`):

```dart
test('FR-TOY-03 Frog Hop: 0–5, then 0–10, then one more or less, then adding', () {
  for (var seed = 0; seed < 200; seed++) {
    for (var level = 1; level <= gameById('hop')!.levels; level++) {
      final r = hopRound(level, Random(seed));
      expect(r.pads, contains(r.target), reason: 'seed $seed, level $level');
      …
    }
  }
});
```

## 6. Template: the game widget

```dart
import 'dart:async';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Frog Hop (SPEC FR-TOY-03, Appendix B: …). What she does, what the voice
/// says, how hints work: the comment a newcomer reads first.
class HopGame extends StatefulWidget {
  const HopGame(this.c, {super.key});
  final GameController c;

  @override
  State<HopGame> createState() => HopGameState();
}

@visibleForTesting
class HopGameState extends State<HopGame> {
  late HopRound _round;
  final _wiggles = <int, int>{};
  int _slips = 0, _hops = 0;
  bool _solved = false;
  Timer? _ask, _next;

  @visibleForTesting
  HopRound get debugRound => _round;

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  @override
  void dispose() {
    _ask?.cancel();
    _next?.cancel();
    super.dispose();
  }

  void _newRound() {
    _round = hopRound(widget.c.level, widget.c.random, last: _solved ? _round.target : null);
    _slips = 0;
    _solved = false;
    _wiggles.clear();
    _ask?.cancel();
    // A beat for the new round to land before the question.
    _ask = Timer(const Duration(milliseconds: 600), _sayPrompt);
    if (mounted) setState(() {});
  }

  void _sayPrompt() => widget.c.say(hopAskClip(_round));

  void _tapPad(int pad) {
    if (_solved) return; // keep the handler; just ignore late taps
    if (pad != _round.target) {
      _slips++;
      widget.c.cue();
      setState(() => _wiggles[pad] = (_wiggles[pad] ?? 0) + 1);
      return;
    }
    widget.c.sound(Sfx.sparkle);
    widget.c.say(numberClip(pad));
    setState(() {
      _solved = true;
      _hops++;
    });
    unawaited(widget.c.finishRound(hopResult(_slips), emoji: '🐸'));
    _next = Timer(const Duration(milliseconds: 3200), _newRound);
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Backdrop(
      top: const Color(0xFFE8F7FF),
      bottom: const Color(0xFFDFF5E3),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              // Size everything from the box: 390×844 phones to 1920×1080 walls.
              final wide = box.maxWidth > box.maxHeight;
              …
            }),
          ),
          TopPrompt(
            child: PromptPill(id: 'hop.ask', label: _solved ? 'You did it!' : 'Hop to ${_round.target}', onSayAgain: _sayPrompt, children: [DEmoji('🐸', size: 44 * t.scale)]),
          ),
        ],
      ),
    );
  }
}
```

Then register it: `'hop': HopGame.new,` in `registry.dart` (and the import).

Continuous motion: drive a `CustomPainter` from a `ValueNotifier` fed by a
`Ticker`, and skip frames on T1:

```dart
void _tick(Duration elapsed) {
  // Ambient motion: 30 fps is plenty on the slowest displays.
  if (DTheme.of(context).policy.ambientFps < 60 && (_frames++).isOdd) return;
  _time.value = elapsed.inMicroseconds / 1e6;
}
…
RepaintBoundary(child: CustomPaint(painter: _Painter(…, time: _time)))  // _Painter: super(repaint: time)
```

## 7. Template: widget tests

```dart
testWidgets('FR-TOY-03 Frog Hop: the voice asks for a pad, the right pad wins', (tester) async {
  final handle = tester.ensureSemantics(); // labelOf() needs semantics
  final sound = RecordingSound();
  final h = await openToyboxGame(tester, 'hop', sound: sound, level: 1);
  final state = tester.state<HopGameState>(find.byType(HopGame));
  expectNoFallbackText(byId('screen.game'));
  await tester.pump(const Duration(milliseconds: 700));
  expect(sound.said, [hopAskClip(state.debugRound)]);
  await tester.tap(byId('hop.pad.${state.debugRound.target}'));
  await tester.pump();
  expect(labelOf(tester, 'hop.ask'), 'You did it!');
  await h.settle();
  expect(await toyboxRounds(h), [('hop', 1, 'win')]);
  await tester.pump(const Duration(seconds: 4)); // let the next round's timers run out
  await h.shutdown();
  handle.dispose();
});
```

Helpers: `byId(id)` finds a `tid`; `labelOf(tester, id)` reads its label;
`RecordingSound` keeps `played` (`(Sfx, volume)`), `rates` and `said`;
`h.settle()`, `h.shutdown()`; `toyboxRounds(h)` lists recorded rounds as
`(game, level, result)`. `openToyboxGame` opens games aimed older than the
demo kid (2½) early, pins `level`, sizes the screen (`size:`), scrolls to
the tile and fails unless the game opened. Timers and tickers advance only
with `tester.pump(duration)`.

The layout check is a loop in each family's test file:

```dart
for (final size in const [Size(390, 844), Size(844, 390), Size(1080, 1920), Size(1920, 1080)]) {
  testWidgets('every … game lays out on a ${size.width.toInt()}×${size.height.toInt()} screen at its busiest level', (tester) async {
    for (final (game, level) in const [('hop', 1), ('hop', 4)]) {
      final h = await openToyboxGame(tester, game, level: level, size: size);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull, reason: '$game $level'); // overflows throw
      await h.shutdown();
    }
  });
}
```

## 8. Template: E2E journey

```ts
import { expect, Page, test } from '@playwright/test';
import { expectText, idsUnder, openToyboxGame, tap, textOf, tid } from './helpers';

const label = async (page: Page, id: string): Promise<string> => (await textOf(tid(page, id))).trim();

test('FR-TOY-03: Frog Hop — she hops the frog to the pad the voice asks for', async ({ page }) => {
  await openToyboxGame(page, 'hop', true); // aimed at 3½+, so opened early for Ava (2½)
  await expectText(tid(page, 'hop.ask'), /Hop to \d+/);
  const target = (await label(page, 'hop.ask')).split(' ').pop()!;
  await tap(tid(page, `hop.pad.${target}`));
  await expectText(tid(page, 'hop.ask'), 'You did it!'); // a lasting label, not the celebration
});
```

Helpers: `tap()` clicks a node's centre (Flutter hit-tests it), `textOf()`
reads aria-label and text, `expectText()` polls, `idsUnder(page, prefix)`
lists ids in index order, `drag(page, from, to)`, `scrollTo(page, id)`,
`hold()`. Pin a level in Settings with `toybox.pin.<game>.<level>` (after
`toybox.on.<game>`). Run with `CHROME_PATH=/usr/bin/google-chrome-stable
tool/e2e.sh toybox` (every Toybox spec; or `tests/<spec>`), and
`SKIP_BUILD=1` to reuse the last web build.

## 9. Naming

| Thing | Pattern | Example |
|---|---|---|
| Game id | short, lowercase, stable forever | `creature`, `ispy`, `letters` |
| Test ids | `<id>.<thing>[.<key>]` | `letters.letter.B`, `creature.part.face`, `trace.point.3` |
| Prompt pill | `<id>.ask` (+ `<id>.ask.again`) | `rhymes.ask` |
| Clip ids | `<id or kind>_<thing>`, `[a-z0-9_]+` | `find_b`, `breathe_in`, `creature_body_2` |
| Debug getters | `debugRound`, `debug<Thing>` on the `@visibleForTesting` state | `debugCreature` |
| Test names | `FR-TOY-03 <Game>: <behavior>` | `FR-TOY-03 Rhyme Time: …` |
| Commit | `feat(toybox): <Game>` | `feat(toybox): Build-a-Creature` |
