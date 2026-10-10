# Plan: six number games built on her longest-played games

Status: **planned, not started** (2026-10-09). Nothing in this plan exists
in code yet. Update the status table in §0 as you go.

This file is a complete brief for building six Toybox games. It is written
so a model with no memory of the session that planned it can pick up any
one game and finish it. Read it top to bottom once, then work on one game
at a time.

---

## 0. Status and order

| # | Game | id | Status | Built on (her favorite) | Teaches |
|---|---|---|---|---|---|
| 1 | Creature Count | `creaturecount` | ✅ built and pushed 2026-10-10 | Build-a-Creature | Counting out a set |
| 2 | Snack Snap | `snacksnap` | ✅ built and pushed 2026-10-10 | Feed the Monster | Seeing amounts at a glance |
| 3 | Finger Count | `fingers` | ✅ built and pushed 2026-10-10 | Number Tracing | Fingers as numbers |
| 4 | Animal Race | `race` | ✅ built and pushed 2026-10-10 | Who Has More? | First, second, third |
| 5 | Bead Slider | `beads` | ✅ built and pushed 2026-10-10 | Tallies | Fives and tens |
| 6 | Fair Share | `share` | ⬜ not started | Feed the Monster | Sharing equally |

Build them in this order. Games 1–3 are for her age now (2½); 4–6 are a
little older.

**Open questions for the owner — answered 2026-10-10** (the owner said
"build in the games in <this file>"):

1. Are these six right? **Yes** — build the six as planned.
2. Should games 4–6 be visible for her now, or only at their ages?
   **Visible for Ava now**: `minMonths: 30` for all six, overriding the
   36/42 below (Animal Race, Bead Slider, Fair Share). Appendix B rows
   say 2½+.
3. Build all six chained with one report at the end, or one at a time
   with a stop after each for the owner to try it on the frame?
   **All six chained**, one report at the end. Keep CI green between
   games; deploy + perf gate + report once at the end.

---

## 1. Why these games (the evidence)

The owner asked (2026-10-09): "make several more games based on the
previous most played games based on time", then "we also want those games
to help learn numbers".

With the owner's permission, the per-game total play time over the four
weeks to 2026-10-09 was read once from the kitchen frame
(`game_events.duration_ms` summed by game; nothing else was read). The
top six:

| Game (id) | Minutes | Rounds |
|---|---|---|
| Number Tracing (`numbers`) | 9.3 | 34 |
| Feed the Monster (`monster`) | 8.0 | 22 |
| Build-a-Creature (`creature`) | 4.5 | 5 |
| Tallies (`tally`) | 4.3 | 15 |
| Who Has More? (`compare`) | 3.4 | 22 |
| Sight Words (`sight`) | 2.3 | 16 |

Every other game had under 1.5 minutes. **Do not read the frame's
database again** for this work: the owner's standing rule is not to
inspect family data on the frame, and this one read was a one-off
exception.

Number skills the existing games already teach (don't duplicate them):
counting objects (Counting Garden, Tallies), reading and tracing numerals
(Number Tracing, Number Fishing, Hundred Square), comparing (Who Has More?,
Banana Balance), the number line and one more/one less (Frog Hop), adding
and taking away (Bus Stop, Cookie Count), counting back (Rocket Countdown),
counting out a set of cookies (Cookie Count).

The gaps these six fill: seeing small amounts without counting
(subitizing), fingers as a number model, five-and-ten structure (the
rekenrek), ordinal numbers, equal sharing (early division), and counting
parts onto something she builds.

---

## 2. Before you start any game

### 2.1 Read, in this order

1. `AGENTS.md` (repo rules; they win over anything here).
2. `PROGRESS.md` (the **In progress** line, recent log).
3. `skills/toybox-game/SKILL.md` (the playbook: every step below comes
   from it) and its references:
   - `skills/toybox-game/references/anatomy.md` (file map, APIs, templates)
   - `skills/toybox-game/references/voice.md` (voice lines, Piper traps)
   - `skills/toybox-game/references/checklist.md` (review checklist)
4. The existing game named as the model in each game's section below.
   Copy its structure; don't invent a new one.

### 2.2 Rules that bite (from AGENTS.md and the playbook)

- **CI is the test runner.** Don't run the full suites or E2E locally.
  You may run a single test file to reproduce a failure CI reported.
- **Never `git add -A`.** The tree holds the owner's `SUGGESTIONS.md`,
  which must not be committed. Add only this game's files by name.
- **Never run `dart format`** on existing files (lines run to ~200
  columns; formatting buries the diff).
- **Import Material from `package:material_ui/material_ui.dart`**, never
  `package:flutter/material.dart`.
- **No `print`** (use `debugPrint` only in tests/tools), **no `dynamic`**,
  **no `DateTime.now()`** in game code.
- **Games never read Riverpod providers.** Everything comes through the
  `GameController c`.
- **Kid surface:** no text entry, no links, no destructive actions, never
  the word "wrong", no failure screen.
- **Performance (the frame is a 32-bit Android 10 photo frame with a weak
  GPU):** no `BackdropFilter`, `ShaderMask`, `Opacity` over big subtrees,
  animated blurs, or a `saveLayer` per frame. Put moving regions in a
  `RepaintBoundary`. Drive per-frame motion with a `ValueNotifier` that a
  `CustomPainter` listens to (`super(repaint: notifier)`), not `setState`.
  On the frame (T1), skip every other ticker frame:
  `if (DTheme.of(context).policy.ambientFps < 60 && (_frames++).isOdd) return;`.
  Respect `DTheme.of(context).policy.maxParticles`.
- **Emoji must be Emoji 12 or older** (the frame is Android 10). The core
  test `every picture is an Emoji 12 glyph` in
  `packages/dearth_core/test/toybox_test.dart` checks `kGames` emoji and
  picture lists; add any new emoji list to it.
- **Test ids are a contract** (`tid('<id>.<thing>', …)`): put readable text
  on the node itself (`Semantics(label: …, excludeSemantics: true)` right
  inside the `tid`). Keep `onTap` non-null in every state.

### 2.3 APIs you will use (verified 2026-10-09)

Core (`packages/dearth_core`):

- `GameInfo(id, title, emoji, minMonths: int, skills: [...], levels: int, freePlay: bool = false, added: 'YYYY-MM-DD')`
  goes in `kExpansionGames` in `lib/src/toybox/games.dart` (after
  `lettercreature`). `added` is the date you build it: the launcher shows
  games added in the last 30 days first.
- Results: `GameResult.win`, `GameResult.helped`, `GameResult.miss`.
  `countingResult(slips)` (0 → win, 1 → helped, 2+ → miss) and
  `resultFor(slips, allowed: n)` are in `lib/src/toybox/rounds.dart`.
- Voice: `lib/src/toybox/voice.dart`. Clip-id functions sit near the top
  (e.g. `String cookieAskClip(int n) => 'cookies_ask_$n';`); one-off clips
  are `static const` fields of the `VoiceLine` class; the words go in the
  `_lines()` function as `lines[id] = 'Text.';`. Helpers available inside
  `_lines()`: `numberWord(n)` ("seven", "fourteen"), `_cap(s)` (capitalize),
  `_numbers` (zero…twenty). Existing clips you can reuse:
  `numberClip(n)` = `num_<n>` ("Seven."), `countClip(n)` ("One, two,
  three."), `VoiceLine.cookiesBell` = `cookies_bell` ("Then ring the
  bell!"). `afterVoice(clip, atLeast: Duration)` returns how long to wait
  for a clip to finish (use it; never guess clip lengths).
- Export each new rules file from `packages/dearth_core/lib/dearth_core.dart`
  (alphabetical among the `src/toybox/` exports).

App (`apps/dearth_app/lib/features/toybox/`):

- `GameController c`: `c.level`, `c.random` (`math.Random`), `c.kid`,
  `c.sound(Sfx, volume:, rate:)`, `c.say(clipId)` (stops the previous
  clip), `c.cue()` (the soft "try again" sound, `Sfx.nope`),
  `c.finishRound(result, emoji: '…', calm: false)` (records, celebrates a
  win, moves the level; don't await anything after it; schedule the next
  round with a `Timer`).
- `Sfx` values: `pop, sparkle, boing, snap, munch, nope, cheer, blip, honk,
  ding, xylophone, kick, snare, hat, tom` and animal sounds `cow, pig,
  sheep, rooster, chicken, horse, dog, cat, frog, owl`. A xylophone note
  at MIDI `m`: `rate: math.pow(2, (m - kXylophoneBaseMidi) / 12).toDouble()`.
- Shared widgets (`games/game_widgets.dart`, `games/voice_widgets.dart`):
  `Backdrop(top:, bottom:, child:)`, `PlayArea(top: 140, child:)`,
  `PictureTile(id:, label:, child:, size:, onTap:, tried:, hint:, wiggles:, hops:, width:)`,
  `Hop(count:, child:)`, `Wiggle(count:, child:)` (both remount their
  child: wrap only stateless content), `TopPrompt(child:)`,
  `PromptPill(id:, label:, children:, onSayAgain:)` (adds a 🔊 button with
  id `<id>.again`), `TileRows(per:, children:)`,
  `GlyphView(char, height:, color:)` (ball-and-stick numerals and letters).
- From `dearth_ui`: `DPressable(id:, semanticLabel:, excludeSemantics: true, onTap:, borderRadius:)`,
  `DEmoji(e, size:)`, `tid(id, child)`, `DTheme.of(context)` (`.scale`,
  `.space`, `.policy`).
- Feed the Monster's painter (`games/monster.dart`):
  `MonsterPainter(chew:, shake:, blink:, open:, hop:, look:, skin:)` where
  the first five are `Animation<double>` (use `AnimationController`s) and
  `look` is a `ValueListenable<Offset>`. Skins: `MonsterSkin.green`,
  `.purple`, `.orange`. `MonsterPainter.mouthAt` / `.eyesAt` give the mouth
  and eyes as fractions of its box. `games/cookies.dart` shows how to drive
  it (blink timer, chew on eat, shake on a slip, look toward taps). Its
  `CookiePainter()` is public.
- Registry: add `'<id>': <Name>Game.new,` and the import in
  `games/registry.dart`. A game that isn't registered stays hidden.

Tests:

- Widget tests open a game through the real Toybox:
  `final h = await openToyboxGame(tester, '<id>', sound: sound, level: 2, size: const Size(1920, 1080));`
  (from `test/support/toybox_harness.dart`; it opens games aimed older
  than the demo kid early). Then `tester.state<XGameState>(find.byType(XGame))`,
  `sound.said` (clip ids in order), `sound.played` (`(Sfx, volume)` pairs),
  `labelOf(tester, '<tid>')`, `byId('<tid>')`, `await h.settle()`,
  `await toyboxRounds(h)` (recorded `(game, level, result)`),
  `expectNoFallbackText(byId('screen.game'))`, `await h.shutdown()`.
  Wrap with `final handle = tester.ensureSemantics(); … handle.dispose();`.
  Timers only advance with `await tester.pump(duration)`.
- Layout: `await expectGamesLayOut(tester, [('<id>', 1), ('<id>', 4)], size: size);`
  inside a loop over `Size(390, 844), Size(844, 390), Size(1080, 1920), Size(1920, 1080)`.
  An overflow fails it.
- E2E: `await openToyboxGame(page, '<id>')`, `tid(page, id)`,
  `tap(locator)`, `textOf(locator)`, `expectText(locator, textOrRegex)`,
  `idsUnder(page, prefix)`, `expectCheered(page)` (reads the host's lasting
  cheer count) from `e2e/tests/helpers.ts`.

### 2.4 Where new things go (all six games)

| What | Path |
|---|---|
| Core rules (one file per game) | `packages/dearth_core/lib/src/toybox/<id>.dart` |
| Core tests (one new file for this set) | `packages/dearth_core/test/toybox_count_test.dart` |
| Voice lines and clip ids | `packages/dearth_core/lib/src/toybox/voice.dart` |
| Core voice guard (`asked` list, ~line 212) | `packages/dearth_core/test/toybox_voice_test.dart` |
| Playfield (one file per game) | `apps/dearth_app/lib/features/toybox/games/<id>.dart` |
| Registry | `apps/dearth_app/lib/features/toybox/games/registry.dart` |
| Widget tests (one new file for this set) | `apps/dearth_app/test/toybox_count_test.dart` |
| App voice guard (no edit; it must pass) | `apps/dearth_app/test/toybox_voice_test.dart` |
| E2E (one new file for this set) | `e2e/tests/toybox_count.spec.ts` |
| Clips (generated, Git LFS) | `apps/dearth_app/assets/voice/<clip>.mp3` + `tool/sounds/voice_index.json` |
| Docs | `SPEC.md` (FR-TOY-03 list + Appendix B row), `README.md` (Toybox paragraph), `PROGRESS.md` |

The first game creates the three new test files; later games add to them.
Open the new test files with the same imports as
`apps/dearth_app/test/toybox_more_test.dart` and
`e2e/tests/toybox_more.spec.ts` (copy their headers).

### 2.5 The steps for every game (the playbook, condensed)

1. Mark the game "in progress" in `PROGRESS.md` and in §0 above.
2. Core: `GameInfo`, rules file, export, core tests.
3. Voice: clip-id functions and lines in `voice.dart`; check them with
   `python3 skills/toybox-game/scripts/phonemes.py --ids <prefix>`; make
   clips with `python3 tool/sounds/voice.py` (it makes only new or changed
   lines; **never `--all`**); add every clip the game asks for to the core
   guard's `asked` list.
4. Playfield widget; register it.
5. Look at it: copy `skills/toybox-game/scripts/shots_test.dart.tmpl` to
   `apps/dearth_app/test/zz_shots_test.dart` and run
   `cd apps/dearth_app && SHOT_GAME=<id> SHOT_LEVELS=1,2,3,4 flutter test --no-pub test/zz_shots_test.dart`
   (instructions at the template's top; PNGs go to `$SHOT_OUT`, default
   `<system temp>/toybox-shots`; add hint/finished states in its `states`
   list). Open the PNGs with the Read tool and fix what looks wrong (sizes, crowding on the
   390×844 phone, contrast, alignment). **Delete `zz_shots_test.dart`
   before committing.**
6. Widget tests + layout entries; the E2E journey.
7. Docs: SPEC FR-TOY-03 list and Appendix B row, README, PROGRESS (the 6.2
   Toybox line, a dated Log entry with test counts, findings).
8. `python3 skills/toybox-game/scripts/check_game.py <id>` (checks the
   game is wired in everywhere).
9. `flutter analyze` in `apps/dearth_app` and `dart analyze` in
   `packages/dearth_core`: no issues.
10. Commit only this game's paths (list them by name; include the new
    `.mp3` files and `tool/sounds/voice_index.json`; check one clip with
    `git check-attr filter -- apps/dearth_app/assets/voice/<clip>.mp3`,
    which must say `lfs`). Message `feat(toybox): <Game name>` with a body
    (what it does, why, test counts) and the attribution line the session
    asks for.
11. `git push origin main`; watch the `build.yml` run
    (`gh run list --workflow build.yml -L 1`, then `gh run watch <id>`). If
    a job fails: `gh run view --job <job-id> --log-failed`, fix, push,
    repeat until green.
12. Deploy: `tool/deploy_frame.sh 10.0.1.148 --build`.
13. Optional, recommended once per game: `tool/perf_gate.sh 10.0.1.148`
    (about 10 minutes). It must pass (nothing slower than the baseline).
14. Report to the owner: what the game does, what was verified, and the
    new clip ids to listen to on the frame (remake one with
    `python3 tool/sounds/voice.py <clip-id>`). Then stop, unless the owner
    said to chain the games.

### 2.6 Shared conventions for all six games

- **Round rhythm:** the prompt is said 600 ms after a round appears;
  praise on success; `finishRound()`; the next round about 3 s later
  (`afterVoice(lastClip, atLeast: const Duration(milliseconds: 3000))`).
- **Idle:** 11 s without a touch says the prompt again. This is not a slip.
- **Slips:** a wrong answer plays `c.cue()`, the thing wiggles, and the
  voice says something useful (what she picked, or "more"/"fewer"). After
  2 slips, show the hint. Result: `countingResult(slips)` unless the game
  says otherwise.
- **Timers:** keep every `Timer` in a list and cancel them all in
  `dispose()` and at the start of each round (copy `_after()` from
  `cookies.dart`).
- **The pill** (`<id>.ask`) always carries a lasting label: the question
  while playing, a "Yay!…" text once solved. E2E waits for it.
- **The kid's level:** the host picks it. Never set it yourself.

---

## 3. Game 1: Creature Count (`creaturecount`)

### 3.1 Summary

- **Title:** Creature Count. **Emoji:** `🐙`. **minMonths:** 30.
  **levels:** 4. **skills:** `['Counting out a set', 'Reading numerals', 'Counting two things']`.
- **Built on:** Build-a-Creature (4.5 min) for the creature, and Cookie
  Count's count-out-then-check mechanic.
- **Teaches:** making a set of a given size ("give it three eyes"), which
  is harder than "how many are there?" because she must stop at the right
  number. The top level links the numeral to the amount (Number Tracing,
  her most-played game).
- **Model files:** `games/cookies.dart` (structure, timers, the bell
  check), `games/creature.dart` (the creature's look and dance).

### 3.2 How a round plays

1. A creature with only a body (no face, legs or horns) stands in the
   play area. The pill shows the number (`GlyphView`) and a small picture
   of the part.
2. The voice: "Give it three eyes!" (two parts at level 3: "Give it three
   eyes!" then "And two legs!"). The first round of a session adds "Then
   make it dance!".
3. One big round button per asked part (eye, leg, horn or spot). Each tap
   adds one part to the creature (`Sfx.pop`, the button hops) and 250 ms
   later says the new count (`numberClip(n)`). At the part's maximum the
   button wiggles with `Sfx.boing` and nothing is added (not a slip).
4. Tapping a part on the creature takes it off (`Sfx.snap`) and says the
   new count.
5. The dance button (🎵) checks:
   - All counts right: the creature dances (≈2.4 s bounce), the voice
     says "Yay! Three eyes!" (plus "And two legs!" for two parts), then
     `finishRound(countingResult(slips), emoji: '🐙')`, then the next
     round.
   - No parts added at all: say the prompt again (not a slip).
   - Wrong: `slips++`, `c.cue()`, the creature shakes, and the voice
     names the first wrong part in ask order: too few gives "More eyes,
     please!", too many gives "Too many eyes!". The parts stay so she can
     fix them.
6. After 2 slips (and always at level 1): faint outlines show where each
   wanted part goes.

### 3.3 Ladder

| Level | What she makes | Range | Guides |
|---|---|---|---|
| 1 | One part | 1–3 | Outlines shown from the start |
| 2 | One part | 1–5 | After 2 slips |
| 3 | Two different parts | 1–4 each | After 2 slips |
| 4 | One part, numeral only ("Give it this many spots!") | 3 to the part's max | After 2 slips |

Part maximums: eyes 6, legs 8, horns 6, spots 9.

### 3.4 Core rules (`packages/dearth_core/lib/src/toybox/creaturecount.dart`)

```dart
import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';

// Creature Count (SPEC FR-TOY-03, Appendix B: counting out a set). A bare
// creature asks for parts: "Give it three eyes!" She adds them one at a
// time (each says the count), takes extras off, and makes it dance to
// check. Build-a-Creature's creatures and Cookie Count's "make this many":
// she must stop at the number. The ladder: one part 1–3 with outlines →
// 1–5 → two parts at once → the numeral alone. Drawing lives in the app.

enum CountPart { eyes, legs, horns, spots }

/// The most of each part a creature can wear (what fits on its body).
const Map<CountPart, int> kCountPartMax = {CountPart.eyes: 6, CountPart.legs: 8, CountPart.horns: 6, CountPart.spots: 9};

/// (one, many): "eye", "eyes".
const Map<CountPart, (String, String)> kCountPartWords = {
  CountPart.eyes: ('eye', 'eyes'),
  CountPart.legs: ('leg', 'legs'),
  CountPart.horns: ('horn', 'horns'),
  CountPart.spots: ('spot', 'spots'),
};

/// "3 eyes", "1 eye" (labels).
String countPartLabel(CountPart p, int n) => '$n ${n == 1 ? kCountPartWords[p]!.$1 : kCountPartWords[p]!.$2}';

/// The bodies whose edges the parts fit: Build-a-Creature's round, egg and
/// square bodies (the spiky and fluffy ones have uneven tops).
const List<int> kCountBodies = [0, 1, 3];

@immutable
class CountAsk {
  const CountAsk(this.part, this.n);
  final CountPart part;
  final int n;
}

@immutable
class CreatureCountRound {
  const CreatureCountRound(this.asks, {required this.body, required this.color, this.numeral = false, this.guides = false});

  /// One part, or two different parts (level 3), in the order asked.
  final List<CountAsk> asks;

  /// One of [kCountBodies].
  final int body;

  /// An index into the app's `kCreatureColors` (0–7).
  final int color;

  /// The voice says "this many": the numeral in the pill is the question.
  final bool numeral;

  /// Outlines show where the parts go from the start (level 1).
  final bool guides;
}

/// A round at [level] (the ladder above), never with the same first ask
/// as [last].
CreatureCountRound creatureCountRound(int level, Random rng, {CreatureCountRound? last}) {
  for (var i = 0;; i++) {
    final r = _round(level, rng);
    final a = r.asks.first, b = last?.asks.first;
    if (b == null || a.part != b.part || a.n != b.n || i >= 20) return r;
  }
}

CreatureCountRound _round(int level, Random rng) {
  final body = kCountBodies[rng.nextInt(kCountBodies.length)];
  final color = rng.nextInt(8);
  CountPart part() => CountPart.values[rng.nextInt(CountPart.values.length)];
  switch (level) {
    case <= 1:
      return CreatureCountRound([CountAsk(part(), 1 + rng.nextInt(3))], body: body, color: color, guides: true);
    case 2:
      final p = part();
      return CreatureCountRound([CountAsk(p, 1 + rng.nextInt(min(5, kCountPartMax[p]!)))], body: body, color: color);
    case 3:
      final p = part();
      var q = part();
      while (q == p) {
        q = part();
      }
      return CreatureCountRound([CountAsk(p, 1 + rng.nextInt(4)), CountAsk(q, 1 + rng.nextInt(4))], body: body, color: color);
    default:
      final p = part();
      return CreatureCountRound([CountAsk(p, 3 + rng.nextInt(kCountPartMax[p]! - 2))], body: body, color: color, numeral: true);
  }
}

/// A slip is a dance with the wrong count: the first is "helped", more a
/// miss (one right answer, and she fixes the creature each time).
String creatureCountResult(int slips) => countingResult(slips);
```

Add to `games.dart` (in `kExpansionGames`, after `lettercreature`; set
`added` to the date you build it):

```dart
GameInfo('creaturecount', 'Creature Count', '🐙', minMonths: 30, skills: ['Counting out a set', 'Reading numerals', 'Counting two things'], levels: 4, added: '2026-10-XX'),
```

### 3.5 Voice

Clip-id functions (in `voice.dart`, near the cookie ones):

```dart
/// "Give it three eyes!"
String ccountAskClip(CountPart p, int n) => 'ccount_ask_${p.name}_$n';

/// The second part at level 3: "And two legs!"
String ccountAndClip(CountPart p, int n) => 'ccount_and_${p.name}_$n';

/// Level 4: "Give it this many spots!"
String ccountManyClip(CountPart p) => 'ccount_many_${p.name}';

/// Too few: "More eyes, please!"
String ccountMoreClip(CountPart p) => 'ccount_more_${p.name}';

/// Too many: "Too many eyes!"
String ccountFewerClip(CountPart p) => 'ccount_fewer_${p.name}';

/// Right: "Yay! Three eyes!"
String ccountYayClip(CountPart p, int n) => 'ccount_yay_${p.name}_$n';
```

`VoiceLine`: `static const ccountDance = 'ccount_dance';`

Lines (in `_lines()`):

```dart
for (final p in CountPart.values) {
  final (one, many) = kCountPartWords[p]!;
  String words(int n) => n == 1 ? 'one $one' : '${numberWord(n)} $many';
  for (var n = 1; n <= kCountPartMax[p]!; n++) {
    lines[ccountAskClip(p, n)] = 'Give it ${words(n)}!';
    lines[ccountYayClip(p, n)] = 'Yay! ${_cap(words(n))}!';
  }
  for (var n = 1; n <= 4; n++) {
    lines[ccountAndClip(p, n)] = 'And ${words(n)}!';
  }
  lines[ccountManyClip(p)] = 'Give it this many $many!';
  lines[ccountMoreClip(p)] = 'More $many, please!';
  lines[ccountFewerClip(p)] = 'Too many $many!';
}
lines[VoiceLine.ccountDance] = 'Then make it dance!';
```

That's 87 clips (ask 29, yay 29, and 16, many 4, more 4, fewer 4, dance 1).
Check them: `python3 skills/toybox-game/scripts/phonemes.py --ids ccount_`
(look for "one" read like "on": `voice.dart` already fixes it for every
line via `_american`; confirm in the output).

Core guard `asked` list additions:

```dart
for (final p in CountPart.values) ...[
  for (var n = 1; n <= kCountPartMax[p]!; n++) ...[ccountAskClip(p, n), ccountYayClip(p, n)],
  for (var n = 1; n <= 4; n++) ccountAndClip(p, n),
  ccountManyClip(p), ccountMoreClip(p), ccountFewerClip(p),
],
VoiceLine.ccountDance,
```

### 3.6 Shared groundwork: Build-a-Creature's body shapes

In `games/creature.dart`, `_bodies` (a list of `_Body(top, bottom, left, right, faceY)`,
fractions of the square canvas) and `CreaturePainter._bodyPath(shape, s)`
(cached `Path`) are private. Make them usable from another file without
changing their behavior:

```dart
/// A body's edges and face line, as fractions of the canvas (Creature Count
/// places parts on them).
({double top, double bottom, double left, double right, double faceY}) creatureBodyBox(int shape) {
  final b = _bodies[shape];
  return (top: b.top, bottom: b.bottom, left: b.left, right: b.right, faceY: b.faceY);
}
```

and inside `CreaturePainter`:

```dart
/// Body [shape]'s outline at canvas size [s] (cached).
static Path bodyPath(int shape, double s) => _bodyPath(shape, s);
```

Values today (shape: top, bottom, left, right, faceY): 0 round
`0.33, 0.83, 0.25, 0.75, 0.52`; 1 egg `0.28, 0.84, 0.29, 0.71, 0.48`;
3 square `0.34, 0.83, 0.27, 0.73, 0.50`. Body colors: `kCreatureColors`
(public). Outline color: `Color.lerp(color, const Color(0xFF2B2440), 0.45)`;
light shade: `Color.lerp(color, Colors.white, 0.45)`; outline width
`s * 0.014`.

### 3.7 Playfield (`games/creaturecount.dart`)

**Classes:** `CreatureCountGame` (StatefulWidget taking `GameController c`)
and `@visibleForTesting class CreatureCountGameState extends State<CreatureCountGame> with TickerProviderStateMixin`.

**State:** `CreatureCountRound? _round`; `final _counts = <CountPart, int>{}`;
`int _slips = 0, _deal = 0, _shakes = 0`; `final _adds = <CountPart, int>{}`
(Hop counts per button); `final _maxed = <CountPart, int>{}` (Wiggle
counts); `bool _hint = false, _solved = false, _toldDance = false`;
`final _timers = <Timer>[]`; `Timer? _idle`; a `Ticker` or
`AnimationController(duration: 2400 ms)` for the dance feeding a
`ValueNotifier<double?> _dance` (null when not dancing).

**Debug getters:** `debugRound`, `debugCounts` (`Map<CountPart, int>`),
`debugGuides` (`_round!.guides || _hint`), `debugSolved`.

**Part positions.** Write one pure function used by both the painter and
the tap overlay, in canvas fractions (multiply by the canvas side `s`).
`k = (right - left) / 0.5`.

- **Eyes** (n ≤ 6): rows of at most 3; `rows = (n + 2) ~/ 3`; row r has
  `min(3, n - 3r)` eyes; y = `faceY + (r - (rows - 1) / 2) * 0.10`;
  x of eye i in a row of m = `0.5 + (i - (m - 1) / 2) * 0.11 * k`. Radius
  `0.045 * k`. Draw: white circle, dark outline, a dark pupil of 0.45×
  radius slightly below center, a tiny white shine.
- **Legs** (n ≤ 8): x_i = `left + 0.06 + (right - left - 0.12) * (n == 1 ? 0.5 : i / (n - 1))`.
  Leg: rounded rect from y `bottom - 0.04` to `bottom + 0.09`, width
  `0.04 * k`, dark fill; foot: oval at `bottom + 0.09`, width `0.07 * k`,
  height `0.035 * k`.
- **Horns** (n ≤ 6): x_i = `left + 0.08 + (right - left - 0.16) * (n == 1 ? 0.5 : i / (n - 1))`.
  The body's top at x: `midY - (midY - top) * sqrt(max(0, 1 - pow((x - 0.5) / ((right - left) / 2), 2)))`
  where `midY = (top + bottom) / 2`. Horn: a triangle with base width
  `0.05 * k` on the top edge (sunk 0.01 into the body), height `0.08 * k`,
  tilted outward by `(x - 0.5) * 1.2` radians, light fill, dark outline.
  Draw horns **before** the body so their bases tuck under it.
- **Spots** (n ≤ 9): a 3×3 grid, x ∈ `{0.5 - 0.09k, 0.5, 0.5 + 0.09k}`,
  rows y = `faceY + 0.11 + r * 0.075` (r = 0, 1, 2). Fill order (dice-like):
  grid cells `[4, 0, 8, 2, 6, 3, 5, 1, 7]` (cell = row * 3 + col). Radius
  `0.032 * k`, fill the light shade, no outline.
- At level 3 eyes and spots can both appear: eyes sit at faceY and spots
  below it, so they don't collide. Check every body in the shots (§2.5
  step 5) at n = max for each part, and adjust the numbers if anything
  leaves the body or overlaps.

**Painter** (`_CountCreaturePainter extends CustomPainter`, `super(repaint: _dance)`):
paints in this order: legs, horns, body (`CreaturePainter.bodyPath`: fill
with color, stroke with outline), spots, eyes, then the guides (each
wanted part not yet placed, as its shape at alpha 0.25 with no fill
color: outline only). While `_dance.value` is not null, bounce and sway
around the feet exactly like `creature.dart` (`beat = sin(t * pi * 2.6)`;
translate/rotate/scale). Wrap the `CustomPaint` in a `RepaintBoundary`.
A part added in the last 200 ms scales from 0.4 to 1 (keep
`_bornAt[part]` per new index and repaint from a short controller), or
skip this polish if time is short.

**Layout** (`LayoutBuilder` inside `PlayArea(top: 140)`, size from the box):
- Wide (`w > h`): the creature square `side = min(h, w * 0.58)`, at the
  left-center; the controls in a column to its right, centered
  vertically: one or two part buttons (diameter `min(h * 0.24, 150 * t.scale)`,
  at least `72 * t.scale`), then the dance button (same diameter) below
  with a gap of `t.space.lg`.
- Tall: the creature square `side = min(w, h * 0.58)` at the top-center;
  the buttons in a row below it, centered.
- Put the whole board in a `Stack(key: ValueKey(_deal))` so each round
  starts clean.

**Buttons:**
- Part button: `DPressable(id: 'creaturecount.add.${p.name}', semanticLabel: 'Add ${p == CountPart.eyes ? 'an' : 'a'} ${kCountPartWords[p]!.$1}', excludeSemantics: true, onTap: () => _add(p), borderRadius: …)`
  containing `Hop(count: _adds[p] ?? 0, child: Wiggle(count: _maxed[p] ?? 0, child: <white disc with lilac border and a painted icon of one part>))`.
  The icon: reuse the part drawing on a plain light-grey mini body.
- Dance button: `DPressable(id: 'creaturecount.dance', semanticLabel: 'Make it dance', …)`
  with `DEmoji('🎵', size: …)` on a white disc.
- Taking a part off: over the creature, one transparent `Positioned` box
  per placed part (side `2.4 × radius`, centered on the part), each
  `tid('creaturecount.part.${p.name}.$i', Semantics(label: '${_cap(kCountPartWords[p]!.$1)} ${i + 1}', excludeSemantics: true, child: GestureDetector(excludeFromSemantics: true, behavior: HitTestBehavior.opaque, onTap: () => _remove(p))))`.
  Always remove the last part of that kind (the one with the highest
  index), whatever box was tapped, so the numbering stays 1…n.

**Labels (a contract for tests):**
- Pill `creaturecount.ask`:
  - playing, one part: `'Give it ${countPartLabel(p, n)}'`, e.g. "Give it 3 eyes", "Give it 1 eye";
  - two parts: `'Give it 3 eyes and 2 legs'`;
  - level 4: `'Give it this many spots: 7'`;
  - solved: `'Yay! 3 eyes'` or `'Yay! 3 eyes and 2 legs'`.
  Pill children: per ask, `GlyphView('$n', height: 52 * t.scale, color: const Color(0xFF6B4FB8))`
  then the part icon (44 × scale).
- Creature: `tid('creaturecount.creature', Semantics(label: 'Creature: ${[for (a in asks) countPartLabel(a.part, _counts[a.part] ?? 0)].join(', ')}', excludeSemantics: true, …))`,
  e.g. "Creature: 2 eyes" or "Creature: 0 eyes, 1 leg". Tapping the
  creature itself says the prompt again.

**Timing:** prompt at 600 ms; at level 3 the and-clip after
`afterVoice(askClip)`; the first round of a session then says
`VoiceLine.ccountDance` after the previous clip. The count clip 250 ms
after a part lands. On a right dance: `_solved = true`, start the dance,
say the yay clip (and at level 3, the and-clip for the second part after
`afterVoice`), call `finishRound` 1200 ms in, and start the next round at
`afterVoice(lastClip, atLeast: const Duration(milliseconds: 3200))`.
Backdrop colors: `top: Color(0xFFE9F6FF)`, `bottom: Color(0xFFFFF0F6)`.

### 3.8 Tests

Core (`packages/dearth_core/test/toybox_count_test.dart`, group
`'FR-TOY-03 Creature Count'`):

1. `'the ladder: one part 1–3 with outlines, 1–5, two parts up to four, the numeral from three'`.
   For seed 0–199 and level 1–4, check: level 1 has one ask with n in
   1–3 and `guides`; level 2 has one ask with n in 1 to
   `min(5, max)`; level 3 has two asks with different parts and n in
   1–4; level 4 has one ask with `numeral`, n from 3 to the part's max.
   Every level: `kCountBodies.contains(body)`, `color` in 0–7.
2. `'never the same first ask twice in a row'`: chain 200 rounds per level
   passing `last:`; the first ask (part and n) never repeats the previous.
3. `'a wrong dance is helped once, then a miss'`: results for 0, 1, 2, 3.
4. `'labels: "3 eyes", "1 eye"'` for `countPartLabel`.

Widget (`apps/dearth_app/test/toybox_count_test.dart`, group
`'Creature Count'`):

1. `'FR-TOY-03: the voice asks; each tap adds a part and says the count; the right dance wins'`:
   level 2; pump 700 ms; `sound.said.first == ccountAskClip(p, n)`; tap
   `creaturecount.add.<p>` n times, pumping 300 ms after each;
   `sound.said` contains `numberClip(1)…numberClip(n)` in order;
   `labelOf(tester, 'creaturecount.creature') == 'Creature: ${countPartLabel(p, n)}'`;
   tap `creaturecount.dance`, pump; the pill reads `'Yay! …'`;
   `sound.said` contains `ccountYayClip(p, n)`; `await h.settle()`;
   `toyboxRounds(h) == [('creaturecount', 2, 'win')]`;
   `expectNoFallbackText(byId('screen.game'))`; pump 5 s; shutdown.
2. `'one too many: "Too many", a part taken off, then right is helped'`:
   level 2; add n + 1 (if n + 1 > max, use a seed or round where it
   isn't, or add n then test "more" instead); dance; `sound.played`
   contains `(Sfx.nope, …)`; `sound.said.last == ccountFewerClip(p)`; tap
   `creaturecount.part.<p>.<n>`; `numberClip(n)` said; dance; recorded
   `helped`.
3. `'two slips show the outlines and make a miss'`: dance with zero
   parts (only re-asks, `debugCounts` all 0, no slip), then with 1 too
   few twice: `debugGuides` true; finish right: `miss`.
4. `'level 3 asks for two parts and needs both'`: the and-clip follows
   the ask-clip; making only the first part right gives the second
   part's more-clip.
5. `'level 4 says "this many" and shows the numeral'`:
   `sound.said.first == ccountManyClip(p)`; the pill label ends with
   `': $n'`.
6. `'a full part button wiggles and adds nothing'`: add to the max, tap
   once more: the count is unchanged and there's no slip (a later right
   dance is a win).

Layout (a loop over the four sizes, the test named
`'every game of the third set lays out on a W×H screen at its busiest level'`):
`('creaturecount', 1), ('creaturecount', 3), ('creaturecount', 4)`.
Later games add their entries to this same loop.

E2E (`e2e/tests/toybox_count.spec.ts`, inside
`test.describe('Toybox third set', …)`):

```ts
test('FR-TOY-03: Creature Count — she gives the creature as many parts as the voice asks for and makes it dance', async ({ page }) => {
  await openToyboxGame(page, 'creaturecount');
  await expectText(tid(page, 'creaturecount.ask'), /^Give it \d+ (eye|leg|horn|spot)s?$/);
  const [, n, part] = (await textOf(tid(page, 'creaturecount.ask'))).match(/Give it (\d+) (eye|leg|horn|spot)/)!;
  for (let i = 1; i <= Number(n); i++) {
    await tap(tid(page, `creaturecount.add.${part}s`));
    await expectText(tid(page, 'creaturecount.creature'), `Creature: ${i} ${part}${i === 1 ? '' : 's'}`);
  }
  await tap(tid(page, 'creaturecount.dance'));
  await expectText(tid(page, 'creaturecount.ask'), /^Yay! /);
  await expectCheered(page);
});
```

(The demo kid opens it at level 1, so the label has one part. The enum
names are plural, `eyes` etc., hence `${part}s` in the button id.)

### 3.9 Docs

- SPEC FR-TOY-03: add "Creature Count" to the list of games.
- SPEC Appendix B row (copy the column format of the Cookie Count row,
  `SPEC.md` ~line 2941): `| Creature Count | 2½+ | Counting out a set, reading numerals | A bare creature asks for parts ("Give it three eyes!"): a button per part adds one, each saying the new count; a tap on a part takes it off; the dance button checks — right: it dances and says "Yay! Three eyes!"; wrong: "More eyes, please!" or "Too many eyes!", and two slips show outlines where the parts go. Eyes, legs, horns and spots on Build-a-Creature's bodies | one part 1–3 with outlines → 1–5 → two parts at once → the numeral alone ("Give it this many spots!", up to nine) | M4 |`
- README: add Creature Count to the Toybox paragraph's list of games.
- PROGRESS: the 6.2 Toybox line, a Log entry, and §0 of this file.

---

## 4. Game 2: Snack Snap (`snacksnap`)

### 4.1 Summary

- **Title:** Snack Snap. **Emoji:** `🥨`. **minMonths:** 30. **levels:**
  4. **skills:** `['Seeing amounts at a glance', 'Matching amounts to numbers', 'Ten-frames']`.
- **Built on:** Feed the Monster (8.0 min): the same painted monster,
  orange skin.
- **Teaches:** subitizing, recognizing 1–5 (later up to 10 in a
  ten-frame) without counting one by one. It's the base of number sense
  and no game trains it yet.
- **Model files:** `games/cookies.dart` (monster driving, chew, eat),
  `games/counting.dart` or `games/oddone.dart` (tap one of several
  tiles, hint, tried).

### 4.2 How a round plays

1. The monster sits at the top-left (wide) or top (tall). The pill shows
   the wanted number (`GlyphView`) and 🥨.
2. The voice: "Four treats, please!"
3. Three or four plates show different amounts of treats as a pattern
   (dots in rows, dice pips or a ten-frame).
4. She taps a plate:
   - Right: the treats fly to the monster's mouth one by one (≈150 ms
     apart, `Sfx.munch` each), the monster chews and hops, and the voice
     says "Four! Yum!". `finishRound(countingResult(slips), emoji: '🥨')`.
   - Wrong: the plate wiggles and fades (`tried`), the voice says "That's
     three!", `slips++`, `c.cue()`.
5. After 2 slips the right plate glows (`hint: true`).
6. **Flash (level 4):** the voice first says "Quick, look!", then the
   want-clip. The plates show for 2000 ms, then each is covered by a
   plate-cover dome. She taps a covered plate to choose it (the cover
   lifts). The 🔊 say-again button replays the ask and shows the plates
   again for 1500 ms; if she used it, the best result is `helped`.

### 4.3 Ladder

| Level | Want | Plates | Pattern | Flash |
|---|---|---|---|---|
| 1 | 1–3 | 3 (exactly 1, 2, 3, shuffled) | row | no |
| 2 | 1–6 | 3, distinct, from want ± 1–2, all in 1–6 | dice | no |
| 3 | 5–10 | 4, distinct, include want ± 1, all in 5–10 | ten-frame | no |
| 4 | 1–6 | 4, distinct, from want ± 1–2, all in 1–6 | row or dice, mixed | yes (2 s) |

### 4.4 Core rules (`lib/src/toybox/snacksnap.dart`)

```dart
enum SnackPattern { row, dice, frame }

@immutable
class SnackPlate {
  const SnackPlate(this.n, this.pattern);
  final int n;
  final SnackPattern pattern;
}

@immutable
class SnackRound {
  const SnackRound(this.want, this.plates, {this.flash = false});
  final int want;
  final List<SnackPlate> plates;
  final bool flash;
  int get answer => plates.indexWhere((p) => p.n == want);
}

/// A round at [level]; the want never repeats [last]'s.
SnackRound snackRound(int level, Random rng, {SnackRound? last});

/// Where a plate's treats sit, as (x, y) in a unit square (0–1), so the
/// app draws them and the tests check them: row (rows of up to 3,
/// centered), dice (the standard pips for 1–6), frame (2 rows × 5,
/// filling the top row left to right first).
List<(double, double)> snackDots(SnackPlate p);

/// A wrong plate is a slip: the first is "helped", more a miss.
String snackResult(int slips, {bool peeked = false}) => peeked && slips == 0 ? GameResult.helped : countingResult(slips);
```

Dice pips (x, y): 1 `(0.5,0.5)`; 2 `(0.25,0.25),(0.75,0.75)`; 3 adds
the center to 2; 4 `(0.25,0.25),(0.75,0.25),(0.25,0.75),(0.75,0.75)`;
5 adds the center to 4; 6 is 4 plus `(0.25,0.5),(0.75,0.5)`.
Row: up to 3 per row, row spacing 0.3, spacing 0.3, centered. Frame: cells
at x = `0.1 + col * 0.2`, y = `0.3` (top row) and `0.7` (bottom row);
draw empty cells as faint squares so the "frame" is visible.

Generate distractors by trying random values in range until there are
enough distinct ones (cap the attempts; the ranges always allow it).
Shuffle the plates with `rng`.

`GameInfo('snacksnap', 'Snack Snap', '🥨', minMonths: 30, skills: ['Seeing amounts at a glance', 'Matching amounts to numbers', 'Ten-frames'], levels: 4, added: '…'),`

### 4.5 Voice

```dart
String snackWantClip(int n) => 'snack_want_$n';   // "Four treats, please!" / "One treat, please!"
String snackThatsClip(int n) => 'snack_thats_$n'; // "That's three!"
String snackYumClip(int n) => 'snack_yum_$n';     // "Four! Yum!"
// VoiceLine: static const snackLook = 'snack_look'; // "Quick, look!"
```

Lines for n = 1–10: `want` = `'${_cap(numberWord(n))} treat${n == 1 ? '' : 's'}, please!'`;
`thats` = `"That's ${numberWord(n)}!"`; `yum` = `'${_cap(numberWord(n))}! Yum!'`.
31 clips. Add all to the core guard's `asked` list.

### 4.6 Playfield (`games/snacksnap.dart`)

- `SnackSnapGame` / `@visibleForTesting SnackSnapGameState` with
  `TickerProviderStateMixin` (the monster's five controllers, as in
  `cookies.dart`: chew 900 ms, shake 650 ms, blink 90 ms, open 220 ms,
  hop 900 ms, a `ValueNotifier<Offset> _look`, and a blink timer every
  4.1 s).
- Debug getters: `debugRound`, `debugCovered` (bool), `debugSolved`.
- Layout (inside `PlayArea(top: 140)`): wide: the monster square
  `min(h * 0.75, w * 0.3)` at the left, the plates in one row to its
  right (tile size `min((rightWidth - gaps) / plates, h * 0.6)`). Tall:
  the monster at the top (`w * 0.45`), plates below via
  `TileRows(per: 2, …)`.
- Each plate:
  `PictureTile(id: 'snacksnap.plate.$i', label: covered ? 'Covered plate' : 'Plate with ${p.n} treat${p.n == 1 ? '' : 's'}', size: tile, onTap: () => _pick(i), tried: _tried.contains(i), hint: _hint && i == r.answer, wiggles: _wiggles[i] ?? 0, child: RepaintBoundary(child: CustomPaint(painter: _PlatePainter(p, covered: …))))`.
  `_PlatePainter` draws a round plate (white with a soft rim), the treats
  at `snackDots` positions (a pretzel-brown ring `0xFFC98A3D` with a
  darker outline, radius ≈ 0.09 of the plate; 0.07 for the frame), and
  when covered a silver dome (`0xFFCFD6E3` with a lighter highlight arc
  and a knob).
- Eating: on the right pick, animate each treat from its plate position to
  the monster's mouth (`MonsterPainter.mouthAt` × the monster's box) with
  one `AnimationController` per treat or one shared controller and
  staggered intervals. Hide eaten treats. Open the mouth while eating,
  then chew and hop.
- Pill: `PromptPill(id: 'snacksnap.ask', label: solved ? 'Yum! $want treats' : 'Snack: $want treat${want == 1 ? '' : 's'}', onSayAgain: _sayAgain, children: [GlyphView('$want'…), DEmoji('🥨', size: 44 * t.scale)])`
  (for multi-digit numbers, one `GlyphView` per digit, as in `cookies.dart`).
  "Yum! 1 treats" is wrong: pluralize the solved label too.
- Monster: `tid('snacksnap.monster', Semantics(label: 'The monster', excludeSemantics: true, onTap: _sayAgain, child: GestureDetector(excludeFromSemantics: true, onTap: _sayAgain, child: RepaintBoundary(child: CustomPaint(painter: MonsterPainter(…, skin: MonsterSkin.orange))))))`.
- Backdrop: `top: Color(0xFFFFF4E0)`, `bottom: Color(0xFFE8F5E9)`.

### 4.7 Tests

Core: `snackDots` returns exactly `n` points, all within 0–1, distinct, for
every pattern and valid n; the ladder table above over 200 seeds (plate
count, ranges, distinct, exactly one plate equals want, flash only at
level 4); no repeated want; results including `peeked`.

Widget: (1) level 1: the want-clip is said; tapping the right plate says
the yum-clip and records a win; the pill reads "Yum! …". (2) A wrong
plate says its thats-clip, plays the cue and marks it tried; two wrong
plates turn the hint on (check `PictureTile` hint via a debug getter
`debugHint`); the right one then records a miss. (3) Level 4: snack_look
then want; after 2100 ms `debugCovered` is true and every plate label is
"Covered plate"; tapping the answer wins; with say-again first, it
records `helped`. Layout entries: `('snacksnap', 1), ('snacksnap', 3), ('snacksnap', 4)`.

E2E: open `snacksnap` (level 1), read the want from
`/^Snack: (\d+) treats?$/`, tap the plate whose label is
`Plate with ${want} treat…` (loop over `idsUnder(page, 'snacksnap.plate.')`
and `textOf`), expect the pill `/^Yum! /`, `expectCheered(page)`.

### 4.8 Docs

Appendix B row: `| Snack Snap | 2½+ | Seeing amounts at a glance | The orange monster asks for a number of treats ("Four treats, please!"); plates show amounts as rows, dice or ten-frames; she taps the plate with that many and the monster eats them; another plate wiggles and says its amount ("That's three!"), two slips light the right one. At the top the plates flash for two seconds and cover over | 1–3 in rows → dice 1–6 → ten-frames 5–10 → flashed plates | M4 |`

---

## 5. Game 3: Finger Count (`fingers`)

### 5.1 Summary

- **Title:** Finger Count. **Emoji:** `🖐️` (U+1F590 U+FE0F). **minMonths:**
  30. **levels:** 4. **skills:** `['Fingers as numbers', 'Counting to ten', 'Five and some more']`.
- **Built on:** Number Tracing (9.3 min, her most played): numerals and
  number words, now tied to the counting tool she always has.
- **Teaches:** showing a number on fingers, reading a number from fingers,
  and 6–10 as "a whole hand and some more".
- **Model files:** `games/cookies.dart` (count out + check button),
  `games/fishing.dart` or `games/counting.dart` (numeral tiles at level 4).

### 5.2 How a round plays

- **Levels 1–3 (show):** one big hand (two at level 3), all fingers down.
  The voice: "Show me three fingers!". The pill shows the numeral.
  - Level 1: tapping anywhere on the hand raises the **next** finger in
    order (thumb, index, middle, ring, pinky) and says the count. Tapping
    a raised finger lowers the **last** raised one.
  - Levels 2–3: tapping a finger toggles that finger (up/down), any
    order; the voice says the total after each change.
  - Level 3: two hands; the left hand counts first. A tap on the left
    hand's palm raises all five at once and says "Five! A whole hand!".
  - The "high five" button (✋ on a white disc) checks: right gives the
    hand(s) a wave and "Three fingers!" (6–10: "Five and three more make
    eight!"); wrong gives "More fingers!" or "Too many fingers!",
    `slips++`, a cue. The first round of a session adds "Then give me a
    high five!" after the ask.
  - After 2 slips the fingers that should be up glow softly (an outline).
- **Level 4 (read):** one or two hands show 1–10 fingers already up (the
  left hand fills first). The voice: "How many fingers?". Three numeral
  tiles (`PictureTile` with a `GlyphView`): the answer and two near ones
  (± 1, or ± 5 for 6–10 when in range). Right: "Seven fingers!" Wrong:
  the tile wiggles and fades, the voice says the picked number
  (`numberClip`).

### 5.3 Ladder

| Level | Mode | Range | Hands |
|---|---|---|---|
| 1 | raise in order | 1–5 | one (right) |
| 2 | raise any | 1–5 | one |
| 3 | two hands | 6–10 | two |
| 4 | read | 1–10 (one hand if ≤ 5) | one or two |

### 5.4 Core rules (`lib/src/toybox/fingers.dart`)

```dart
enum FingerMode { inOrder, any, twoHands, read }

@immutable
class FingerRound {
  const FingerRound(this.mode, this.want, {this.choices = const []});
  final FingerMode mode;
  final int want;            // fingers to show (or shown, in read mode)
  final List<int> choices;   // read mode: 3 distinct numbers, want among them, all in 1–10
  int get hands => want > 5 ? 2 : 1;
}

FingerRound fingerRound(int level, Random rng, {FingerRound? last}); // want never repeats last's
String fingerResult(int slips) => countingResult(slips);

/// Fingers in counting order: thumb, index, middle, ring, pinky.
const List<String> kFingerNames = ['Thumb', 'Index finger', 'Middle finger', 'Ring finger', 'Pinky'];
```

`GameInfo('fingers', 'Finger Count', '🖐️', minMonths: 30, skills: ['Fingers as numbers', 'Counting to ten', 'Five and some more'], levels: 4, added: '…'),`

### 5.5 Voice

```dart
String fingersShowClip(int n) => 'fingers_show_$n'; // n 1–10: "Show me three fingers!" / "Show me one finger!"
String fingersYayClip(int n) => 'fingers_yay_$n';   // n 1–10: "Three fingers!" / "One finger!"
String fingersMakeClip(int n) => 'fingers_make_$n'; // n 6–10: "Five and three more make eight!" ("Five and five more make ten!")
// VoiceLine: fingersMore = 'fingers_more' ("More fingers!"), fingersFewer = 'fingers_fewer' ("Too many fingers!"),
//            fingersFive = 'fingers_five' ("Five! A whole hand!"), fingersWhich = 'fingers_which' ("How many fingers?"),
//            fingersHighFive = 'fingers_highfive' ("Then give me a high five!")
```

30 clips. Counts during play reuse `numberClip(n)`.

### 5.6 Playfield (`games/fingers.dart`)

- State: `List<List<bool>> _up` (per hand, 5 fingers), `_slips`, `_hint`,
  `_solved`, `_waves` (a controller for the wave), timers.
- Debug getters: `debugRound`, `debugUp` (total fingers up),
  `debugHint`, `debugSolved`.
- **The hand painter** (`_HandPainter`, one per hand, mirrored for the
  left hand with `canvas.scale(-1, 1)`): a friendly cartoon hand, skin
  `0xFFFFD3B0` with outline `0xFFB9805A` (stroke ≈ 2.5% of the width),
  palm a rounded rect (x 0.22–0.78, y 0.48–0.92 of its box, radius 0.12).
  Fingers are rounded capsules rooted at the top of the palm at x =
  0.30, 0.42, 0.54, 0.66 (index → pinky), widths 0.11, lengths 0.36,
  0.40, 0.37, 0.30. Up: drawn upright from the root. Down: folded,
  drawn as a short capsule (length 0.12) bent forward with a knuckle
  line. The thumb roots at (0.24, 0.66): up, it points out to the left at
  −50°, length 0.30; down, it lies across the palm. Raised fingers get a
  small sparkle when they rise (optional). Painter repaint: a
  `ValueNotifier<int>` bumped on every change, plus the wave controller
  (rotate the hand ±8° around the wrist).
- **Hit testing:** wrap each hand in a `Listener`/`GestureDetector`
  (`excludeFromSemantics: true`) that finds the finger whose capsule
  (inflated by 30%) contains the tap; else the palm. For tests, overlay
  `Positioned` transparent boxes per finger:
  `tid('fingers.finger.<hand>.<i>', Semantics(label: '${kFingerNames[i]}, ${up ? 'up' : 'down'}', excludeSemantics: true, child: GestureDetector(...)))`
  where `<hand>` is `left` or `right` and i is 0 = thumb … 4 = pinky,
  plus a palm box `tid('fingers.palm.<hand>', …)` labeled
  `'Left hand'`/`'Right hand'`.
- Hands: `tid('fingers.hand.<hand>', Semantics(label: 'Right hand: 3 fingers up', …))`.
- The check button: `DPressable(id: 'fingers.done', semanticLabel: 'High five', …)` with `DEmoji('✋')`.
- Level 4 choices: `TileRows(per: 3, children: [for (n in choices) PictureTile(id: 'fingers.choice.$n', label: '$n', child: GlyphView('$n', …), …)])`
  below the hands.
- Layout: wide: hand(s) centered, each `min(h * 0.85, w * 0.32)` square;
  the done button at the right. Tall: hands at the top (two hands side by
  side, each `w * 0.45`), the button or the tiles below.
- Pill `fingers.ask`: show mode `'Show $want'`, solved
  `'Yay! $want finger${want == 1 ? '' : 's'}'`; read mode
  `'How many fingers?'`, solved the same "Yay!…". Children: the numeral
  (show mode) or ✋ (read mode).
- Backdrop: `top: Color(0xFFFFF7E6)`, `bottom: Color(0xFFE6F4FF)`.

### 5.7 Tests

Core: the ladder over 200 seeds (mode by level, range, hands, choices
are 3 distinct values in 1–10 containing want, read mode only at level
4); no repeat; `kFingerNames.length == 5`.

Widget: (1) level 1: the show-clip; tapping the right palm n times
raises fingers in order (labels: `fingers.finger.right.0` "Thumb, up"
first) and says counts; done gives the yay-clip and a win. (2) Level 2:
toggling a finger down says the new total; too many then done gives the
fewer-clip and a cue; fixing it then done is `helped`. (3) Level 3: the
left palm says `fingers_five` and raises 5; finishing with the right hand
gives the make-clip. (4) Level 4: which-clip; the right choice wins; a
wrong one says its `numberClip` and is tried. Layout entries:
`('fingers', 1), ('fingers', 3), ('fingers', 4)`.

E2E: open `fingers` (level 1), parse `/^Show (\d+)$/`, tap
`fingers.palm.right` n times waiting each time for
`fingers.hand.right` = `Right hand: ${i} finger(s) up`, tap
`fingers.done`, expect `/^Yay! /`, `expectCheered`.

### 5.8 Docs

Appendix B row: `| Finger Count | 2½+ | Fingers as numbers, five and some more | A big cartoon hand: "Show me three fingers!" She raises fingers (in order at first, then any; two hands for 6–10, a tap on the palm raising a whole hand: "Five! A whole hand!") and gives it a high five to check: "Three fingers!" or "More fingers!"/"Too many fingers!"; two slips outline the fingers. At the top the hand shows fingers and she picks the number | 1–5 in order → 1–5 any fingers → 6–10 on two hands → read the hands | M4 |`

---

## 6. Game 4: Animal Race (`race`)

### 6.1 Summary

- **Title:** Animal Race. **Emoji:** `🏁`. **minMonths:** 36. **levels:**
  4. **skills:** `['First, second, third', 'Last', 'Putting in order']`.
- **Built on:** Who Has More? (3.4 min): comparing and lining up,
  now as a race.
- **Teaches:** ordinal numbers (first to fifth, last).
- **Model files:** `games/wordpop.dart` (a `Ticker` driving a painter on
  a `ValueNotifier`, T1 frame skipping, emoji drawn as cached pictures),
  `games/compare.dart` (Who Has More?'s look and tap-to-choose).

### 6.2 How a round plays

1. Lanes (3 or 5) with an animal each at the start line. The voice:
   "Ready, set, go!" (`race_go`).
2. The animals race across (≈3–4 s). Each has a finishing place; its
   speed is set so it crosses the line in that order (finish times
   `2.4 s + (place - 1) * 0.35 s`, with a little wobble in between: e.g.
   position `p(t) = t/T + 0.04 * sin(t * 7 + lane)`, clamped and
   monotonic at the end). **After crossing, each animal keeps going and
   eases to a stop** so earlier finishers stop further along: the order
   stays visible on screen.
3. The question: "Who came second?" (`race_ask_2`), or "Who came last?".
4. She taps an animal. Right: a rosette ribbon with the place pins onto
   it ("Second place!"), sparkle, `finishRound(countingResult(slips), emoji: '🏁')`.
   Wrong: that animal hops and says its own place ("I came third!"),
   `slips++`, cue. Taps during the race do nothing.
5. After 2 slips the right animal glows.
6. The 🔊 say-again button replays the race and asks again (not a slip).
7. **Level 4, the podium:** after the race the voice asks "Who came
   first?"; each right tap pins that ribbon and the next place is asked,
   up to fifth. Any wrong tap is a slip. One `finishRound` at the end.

### 6.3 Ladder

| Level | Animals | Asked |
|---|---|---|
| 1 | 3 | first or last |
| 2 | 3 | first, second or third |
| 3 | 5 | first to fifth, or last |
| 4 | 5 | all five in order (ribbons) |

### 6.4 Core rules (`lib/src/toybox/race.dart`)

```dart
/// (emoji, name): racers drawn from Emoji 12, facing left on Noto (the
/// race runs right to left; check every racer's direction in the shots).
const List<(String, String)> kRacers = [('🐢', 'turtle'), ('🐇', 'rabbit'), ('🐌', 'snail'), ('🐎', 'horse'), ('🐕', 'dog'), ('🐈', 'cat'), ('🐖', 'pig'), ('🐄', 'cow'), ('🐓', 'rooster'), ('🦆', 'duck')];

@immutable
class RaceRound {
  const RaceRound(this.racers, this.places, this.asks);
  final List<int> racers;   // indexes into kRacers, one per lane (top to bottom)
  final List<int> places;   // places[lane] = 1-based finishing place, a permutation
  final List<int> asks;     // places asked in order; 0 = "last". Level 4: [1, 2, 3, 4, 5]
}

RaceRound raceRound(int level, Random rng, {RaceRound? last}); // a different first ask, or a different winner, than last
String raceResult(int slips) => countingResult(slips);
String ordinal(int place) => const ['last', '1st', '2nd', '3rd', '4th', '5th'][place];       // labels
String ordinalWord(int place) => const ['last', 'first', 'second', 'third', 'fourth', 'fifth'][place];
```

**Check the racers' direction** before finalizing the list: render them
(the shots) and keep only emoji that face left on the frame's Noto Color
Emoji font; replace others with left-facing animals or flip them in
the painter with `canvas.scale(-1, 1)`.

`GameInfo('race', 'Animal Race', '🏁', minMonths: 36, skills: ['First, second, third', 'Last', 'Putting in order'], levels: 4, added: '…'),`

### 6.5 Voice

```dart
String raceAskClip(int place) => 'race_ask_${place == 0 ? 'last' : place}'; // "Who came first?" … "Who came fifth?", "Who came last?"
String raceCameClip(int place) => 'race_came_$place';                    // "I came third!" (1–5; the last animal of 3 says "I came third!")
String racePlaceClip(int place) => 'race_place_$place';                  // "First place!" … "Fifth place!"
// VoiceLine: raceGo = 'race_go' ("Ready, set, go!")
```

17 clips. `place` for "last" in the answer check means `places.length`.

### 6.6 Playfield (`games/race.dart`)

- One `Ticker` → `ValueNotifier<double> _t` (seconds since start); one
  `RepaintBoundary(CustomPaint(_TrackPainter(...)))` draws grass lanes, a
  checkered finish line near the left, and each racer at its position.
  Draw each emoji as a **cached `ui.Picture`** made once per size with a
  `TextPainter` (as Word Pop caches its words). Don't use one widget per
  racer per frame. T1: skip every other frame. Stop the ticker when all
  have stopped (≈4.5 s).
- Ribbons: a painted rosette (a circle with petals, gold `0xFFFFC94D`,
  silver `0xFFC9D1DC`, bronze `0xFFE0A26E`, then blue and green) with the
  place's ordinal on it (`1st`), pinned beside the animal.
- For taps and tests, after the race overlay one `Positioned` box per
  lane over the racer's resting place:
  `tid('race.animal.$lane', Semantics(label: '${_cap(name)}, came ${ordinal(place)}', excludeSemantics: true, child: GestureDetector(excludeFromSemantics: true, onTap: () => _pick(lane))))`.
  During the race the label is `'${_cap(name)}, racing'`.
- Pill `race.ask`: while racing `'Ready, set, go!'`; asking
  `'Who came ${ordinal(place)}?'` (`'Who came last?'`); solved
  `'Yes! ${ordinal(place)}'`; level 4 `'Put them in order: ${ordinal(next)}'`,
  solved `'Yes! All in order'`. Child: `DEmoji('🏁')`.
- Layout: wide: lanes stacked over the full width (lane height
  `min(h / lanes, 150 * t.scale)`); tall: same, narrower, with the
  racers at least `56 * t.scale` tall.
- Backdrop: `top: Color(0xFFE3F6FF)`, `bottom: Color(0xFFE6F7DA)`.

### 6.7 Tests

Core: `places` is a permutation of 1..lanes; racers distinct; asks per
level (level 1 only 1 or 0; level 4 exactly [1..5]); 200 seeds; no repeat.

Widget: (1) level 2: `race_go`, pump 5 s (the race ends), the ask-clip;
tapping the lane whose place matches wins and says the place-clip; the
animal's label reads "…, came 2nd". (2) A wrong lane says its came-clip,
cue, then 2 slips set `debugHint`. (3) Level 4: five right taps in place
order give one win; a wrong one in between gives `helped`. Use pumps in
frames (`for (i < 300) await tester.pump(const Duration(milliseconds: 16))`):
ticker-driven games crawl in tests (see PROGRESS findings). Layout entries:
`('race', 1), ('race', 3), ('race', 4)`.

E2E: open `race` (every game is on for the demo kid, whatever its
`minMonths`). Wait for `/^Who came (\d)(st|nd|rd|th)\?$|^Who came last\?$/`
(timeout 30 s; the race runs first). Read every `race.animal.*` label,
find the one ending `came <asked>` (for "last", the highest place), tap
it, expect `/^Yes! /`, `expectCheered`.

### 6.8 Docs

Appendix B row: `| Animal Race | 3+ | First, second, third, last | Three animals (then five) race across their lanes and coast to a stop in finishing order. "Who came second?" She taps the animal: a ribbon pins on ("Second place!"); another one says its own place ("I came third!"); two slips light the right one; the speaker replays the race. At the top she ribbons all five, first to fifth | first or last of 3 → 1st–3rd → 1st–5th of 5 → all five in order | M4 |`

---

## 7. Game 5: Bead Slider (`beads`)

### 7.1 Summary

- **Title:** Bead Slider. **Emoji:** `🔴` (🧮 is Picture Sudoku's; also
  paint a launcher icon, see below). **minMonths:** 42. **levels:** 4.
  **skills:** `['Fives and tens', 'Counting to twenty', 'Seeing seven as five and two']`.
- **Built on:** Tallies (4.3 min): grouping in fives, now with beads she
  moves.
- **Teaches:** the rekenrek (a two-row counting rack, 5 red + 5 white
  beads per row): 7 is "five and two", 14 is "ten and four".
- **Model files:** `games/tally.dart` (Tallies: counting on from five),
  `games/cookies.dart` (count out + the bell).

### 7.2 How a round plays

1. A wooden rack with one row (two rows at level 3+) of 10 beads, all on
   the right. The voice: "Show seven!"; the first round of a session
   adds the bell clip (reuse `VoiceLine.cookiesBell`, "Then ring the
   bell!").
2. **Moving beads:** each row keeps `left` (0–10, the beads pushed left).
   Tapping bead i of a row (0 = leftmost in the row's bead order):
   - if `i >= left` (the bead is on the right): `left = i + 1` (it and
     every bead to its left in the row slide left);
   - else: `left = i` (it and every bead to its right slide back).
   Also support a drag across the row: the bead under the finger sets
   `left` by the same rule as the finger moves. After each change the
   beads slide (180 ms) with `Sfx.blip`, and the voice says the total
   (`numberClip(total)`).
3. The bell (`Sfx.ding`) checks `total == want` (any split across rows is
   accepted). Right: the rack chimes a rising run (xylophone 60, 64, 67,
   72), the voice says the structure clip ("Five and two make seven!"),
   `finishRound(countingResult(slips), emoji: '🔴')`. Wrong: "More beads,
   please!" or "Too many beads!", `slips++`, cue.
4. After 2 slips: a dashed marker shows where to stop (after bead
   `want` on the top row, or the top row full plus a marker at
   `want − 10` on the bottom row).
5. **Level 4 (read):** the rack starts with beads already across (the
   top row fills first); the voice asks "How many beads?"; three numeral
   tiles (answer, ±1 and ±5 or ±10 where in range); right says
   `beadsYayClip(n)`; wrong wiggles and says `numberClip(picked)`.

### 7.3 Ladder

| Level | Rows | Want | Mode |
|---|---|---|---|
| 1 | 1 | 1–5 | show |
| 2 | 1 | 3–10 | show |
| 3 | 2 | 11–20 | show |
| 4 | 1 or 2 | 1–20 | read |

### 7.4 Core rules (`lib/src/toybox/beads.dart`)

```dart
@immutable
class BeadRound {
  const BeadRound(this.want, {this.rows = 1, this.read = false, this.choices = const []});
  final int want;
  final int rows;            // 1 or 2 (2 when want > 10 or at level 3)
  final bool read;           // level 4: beads start across; pick the number
  final List<int> choices;   // read mode: 3 distinct, want among them, 1–20
}

BeadRound beadRound(int level, Random rng, {BeadRound? last}); // want never repeats last's
String beadResult(int slips) => countingResult(slips);

/// How the voice builds [n]: 1–5 "Three!", 6–9 "Five and two make seven!", 10 "Ten! A whole row!",
/// 11–19 "Ten and four make fourteen!", 20 "Twenty! Two whole rows!" (the line text lives in voice.dart).
```

`GameInfo('beads', 'Bead Slider', '🔴', minMonths: 42, skills: ['Fives and tens', 'Counting to twenty', 'Seeing seven as five and two'], levels: 4, added: '…'),`

### 7.5 Voice

```dart
String beadsShowClip(int n) => 'beads_show_$n'; // 1–20: "Show seven!"
String beadsYayClip(int n) => 'beads_yay_$n';   // 1–20, by the rule above
// VoiceLine: beadsMore = 'beads_more' ("More beads, please!"), beadsFewer = 'beads_fewer' ("Too many beads!"),
//            beadsWhich = 'beads_which' ("How many beads?")
// Reuse VoiceLine.cookiesBell ("Then ring the bell!").
```

43 new clips. Check "Twenty" and "fourteen" with `phonemes.py`.

### 7.6 Playfield (`games/beads.dart`)

- State: `List<int> _left` (per row), per-row `AnimationController`s for
  the slide (store the old and new `left`; the painter lerps), `_slips`,
  `_hint`, `_solved`, timers.
- Debug getters: `debugRound`, `debugTotal`, `debugLeft` (list),
  `debugHint`.
- **Rack painter** (one per row, each in a `RepaintBoundary`): a wooden
  frame (`0xFFB7814C` with a darker edge) drawn once; a metal rod line;
  beads are circles (diameter `d`), red `0xFFE5484D` for 0–4 and white
  `0xFFF7F7F7` with a grey outline for 5–9; a highlight dot on each.
  Geometry: inner width W, `d = W / 14`; a left bead j sits at
  `x = margin + j * d`; a right bead j (j ≥ left) at
  `x = W - margin - (10 - j) * d`; the empty middle shows the gap.
- Taps: one transparent `Positioned` box per bead (`d` square) with
  `tid('beads.bead.$row.$i', Semantics(label: 'Bead ${i + 1}, ${i < 5 ? 'red' : 'white'}, ${i < left ? 'left' : 'right'}', …))`;
  the row: `tid('beads.row.$row', Semantics(label: '${row == 0 ? 'Top' : 'Bottom'} row: $left beads across', …))`
  (use "bead" when left is 1). A `Listener` on the row handles drags.
- Bell: `DPressable(id: 'beads.bell', semanticLabel: 'Bell', …)` (reuse a
  bell painter: `cookies.dart` has a private `_BellPainter`; copy it or
  make it public).
- Level 4 tiles: `TileRows(per: 3, …)` of `PictureTile(id: 'beads.choice.$n', label: '$n', child: GlyphView('$n'…))`.
- Pill `beads.ask`: show `'Show $want'`, solved `'Yay! $want'`; read
  `'How many beads?'`, solved `'Yay! $want'`.
- Layout: the rack `min(w * 0.92, 1100 * t.scale)` wide, each row about
  `d * 1.6` tall, centered; the bell to the right (wide) or below
  (tall). On the 390×844 phone, `d` is small (~25 px): make each bead's
  tap box at least `44 * t.scale` tall (taller than the bead) and rely on
  drag.
- Launcher icon: paint a mini rack (two rows, 5 red + 5 white) in
  `GameIcon` in `toybox_screen.dart` (see how Bubble Pop's and
  Build-a-Creature's icons are painted there) so the tile reads better
  than 🔴.
- Backdrop: `top: Color(0xFFFFF3E3)`, `bottom: Color(0xFFEAF2FF)`.

### 7.7 Tests

Core: the ladder (rows, ranges, read only at level 4, choices distinct
and containing want, all 1–20); no repeat; the yay-line rule (test the
lines map in `voice.dart` for n = 3, 7, 10, 14, 20).

Widget: (1) level 2: tapping `beads.bead.0.<want-1>` moves `want` beads
in one tap and says `numberClip(want)`; the bell gives the yay-clip and a
win. (2) Tapping a left bead slides beads back. (3) Wrong totals give the
more/fewer clips; 2 slips set `debugHint`. (4) Level 3: totals across
two rows; 14 as 10 + 4 wins with `beads_yay_14`. (5) Level 4: the
which-clip, the right tile wins. Layout entries: `('beads', 1), ('beads', 3), ('beads', 4)`.

E2E: open `beads` (every game is on for the demo kid), parse `/^Show (\d+)$/`; at level 1
(one row) tap `beads.bead.0.<want-1>`, expect the row label
`Top row: ${want} bead(s) across`, tap `beads.bell`, expect `/^Yay! /`,
`expectCheered`.

### 7.8 Docs

Appendix B row: `| Bead Slider | 3½+ | Fives and tens, counting to twenty | A counting rack (rekenrek): rows of ten beads, five red and five white. "Show seven!" A tap or a swipe slides beads across (each change says the total) and the bell checks: "Five and two make seven!", or "More beads, please!"/"Too many beads!"; two slips mark where to stop. At the top beads are already across and she picks the number | 1–5 on one row → 3–10 → 11–20 on two rows → read the rack | M4 |`

---

## 8. Game 6: Fair Share (`share`)

### 8.1 Summary

- **Title:** Fair Share. **Emoji:** `🧁`. **minMonths:** 42. **levels:**
  4. **skills:** `['Sharing equally', 'Same and different', 'Left over']`.
- **Built on:** Feed the Monster (8.0 min): two or three of its monsters.
- **Teaches:** equal sharing (early division) and leftovers.
- **Model files:** `games/cookies.dart` (jar → plate by tapping, the
  bell, the monster), `games/monster.dart` (skins).

### 8.2 How a round plays

1. Two or three monsters (skins green, purple, orange) at the top, each
   with an empty plate in front. A tray with N cupcakes at the bottom,
   the bell at the side.
2. The voice: "Share the cupcakes so everyone has the same!"
   (`share_ask`); the first round of a session adds the bell clip.
3. **Tap a plate** to move one cupcake from the tray onto it (`Sfx.pop`;
   the voice says that plate's count, `numberClip`). Tray empty: the
   plate wiggles, `Sfx.boing`, not a slip. **Tap a cupcake on a plate**
   to send it back to the tray (`Sfx.snap`). (Taps rather than drags:
   reliable for small fingers and in tests.)
4. The bell checks:
   - Fair (every plate holds `treats ~/ monsters` and the tray holds
     `treats % monsters`): every monster eats (staggered munches), hops
     and the voice says "Three each! Fair and square!"; at level 4 then
     "One left over, for later!".
     `finishRound(countingResult(slips), emoji: '🧁')`.
   - Plates equal but the tray holds more than the leftover (e.g. 2 each
     with 3 left): "There are more to share!", a slip.
   - Plates unequal: the monster with the fewest shakes and says "Hey! I
     have fewer!", a slip.
5. After 2 slips each plate shows dotted spots for its fair share.

### 8.3 Ladder

| Level | Monsters | Cupcakes | Leftover |
|---|---|---|---|
| 1 | 2 | 2, 4 or 6 | none |
| 2 | 2 | 4, 6, 8 or 10 | none |
| 3 | 3 | 3, 6, 9 or 12 | none |
| 4 | 2 or 3 | 2 monsters: 5, 7, 9; 3 monsters: 4, 7, 10 | always 1 |

### 8.4 Core rules (`lib/src/toybox/share.dart`)

```dart
@immutable
class ShareRound {
  const ShareRound(this.monsters, this.treats);
  final int monsters;  // 2 or 3
  final int treats;    // cupcakes on the tray at the start
  int get each => treats ~/ monsters;
  int get left => treats % monsters;
}

enum ShareCheck { fair, unequal, moreToShare }

ShareRound shareRound(int level, Random rng, {ShareRound? last}); // never the same (monsters, treats) as last
ShareCheck shareCheck(ShareRound r, List<int> plates, int tray);  // pure: what the bell finds
int fewestPlate(List<int> plates);                                // index of the monster who complains (first lowest)
String shareResult(int slips) => countingResult(slips);
```

`GameInfo('share', 'Fair Share', '🧁', minMonths: 42, skills: ['Sharing equally', 'Same and different', 'Left over'], levels: 4, added: '…'),`

### 8.5 Voice

```dart
String shareEachClip(int n) => 'share_each_$n'; // 1–6: "Three each! Fair and square!" ("One each! …")
// VoiceLine: shareAsk = 'share_ask' ("Share the cupcakes so everyone has the same!"),
//            shareFewer = 'share_fewer' ("Hey! I have fewer!"),
//            shareMore = 'share_more' ("There are more to share!"),
//            shareLeft = 'share_left' ("One left over, for later!")
// Reuse VoiceLine.cookiesBell and numberClip(n).
```

10 new clips.

### 8.6 Playfield (`games/share.dart`)

- Each monster needs its own five `AnimationController`s and `look`
  notifier (as in `cookies.dart`); keep them in small per-monster objects
  and dispose them all. Blink them at different times so they feel alive.
- State: `List<int> _plates`, `int _tray`, `_slips`, `_hint`,
  `_solved`, timers.
- Debug getters: `debugRound`, `debugPlates`, `debugTray`, `debugHint`.
- Layout: wide: monsters in a row across the top 55% (each box
  `min(w / monsters * 0.8, h * 0.45)`), plates under them, the tray along
  the bottom with cupcakes in up to two rows, the bell at the right.
  Tall (390×844 is the tightest case, 3 monsters): monster boxes about
  `w / 3 * 0.9` (~115 px), plates under them, the tray below and the
  bell under the tray. **Render the 390×844 three-monster level in the
  shots before writing tests.**
- Cupcakes: `DEmoji('🧁', size: …)` (Emoji 11, fine on the frame) or a
  small painter. A cupcake on a plate is tappable:
  `tid('share.cupcake.$plate.$i', Semantics(label: 'Cupcake ${i + 1} on plate ${plate + 1}', …))`.
- Plates: `tid('share.plate.$i', Semantics(label: 'Plate ${i + 1}: $n cupcake${n == 1 ? '' : 's'}', excludeSemantics: true, child: GestureDetector(excludeFromSemantics: true, onTap: () => _give(i), …)))`.
- Tray: `tid('share.tray', Semantics(label: 'Tray: $_tray cupcake${_tray == 1 ? '' : 's'}', …))`.
- Bell: `DPressable(id: 'share.bell', semanticLabel: 'Bell', …)`.
- Monsters: `tid('share.monster.$i', Semantics(label: 'Monster ${i + 1}', …))`.
- Pill `share.ask`: playing `'Share $treats cupcakes'`; solved
  `'$each each!'` or `'$each each, 1 left over'`. Children: 🧁.
- Backdrop: `top: Color(0xFFFFF0F5)`, `bottom: Color(0xFFEFF7E8)`.

### 8.7 Tests

Core: the ladder table over 200 seeds; `shareCheck` cases: fair with and
without a leftover, unequal, equal-but-more-to-share (e.g. 3 monsters, 9
cupcakes, plates `[2, 2, 2]`, tray 3); `fewestPlate`.

Widget: (1) level 1: the ask-clip; tapping plates alternately until the
tray is empty; the bell gives the each-clip and a win; the pill reads
"N each!". (2) Unequal gives `share_fewer`, a cue, the complaining
monster shakes; then fixing it gives `helped`. (3) Equal with cupcakes
left gives `share_more`. (4) Level 4: fair with one left gives the
each-clip then `share_left`. (5) Tapping a plate with an empty tray adds
nothing and isn't a slip. Layout entries: `('share', 1), ('share', 3), ('share', 4)`.

E2E: open `share` (every game is on for the demo kid), read N from `/^Share (\d+) cupcakes$/`
and the monster count from `idsUnder(page, 'share.plate.')`; tap the
plates round-robin N times (waiting on the tray label each time), tap
`share.bell`, expect `/ each/`, `expectCheered`.

### 8.8 Docs

Appendix B row: `| Fair Share | 3½+ | Sharing equally, left over | Two or three monsters with empty plates and a tray of cupcakes: "Share the cupcakes so everyone has the same!" A tap on a plate gives it one (and says how many it has), a tap on a cupcake takes it back, and the bell checks: "Three each! Fair and square!"; "Hey! I have fewer!" or "There are more to share!" when it isn't; two slips show each plate's share. At the top one is left over: "One left over, for later!" | 2 monsters, up to 6 → up to 10 → 3 monsters, up to 12 → one left over | M4 |`

---

## 9. Final checklist per game

Copy this list into your notes for each game and tick every line:

- [ ] PROGRESS **In progress** and §0 of this file say which game you're on.
- [ ] `GameInfo` in `kExpansionGames` with today's `added` date.
- [ ] Rules file with a header comment (what it teaches, the ladder),
      exported from `dearth_core.dart`.
- [ ] Core tests in `packages/dearth_core/test/toybox_count_test.dart`.
- [ ] Clip-id functions, `VoiceLine` constants, lines in `_lines()`.
- [ ] `phonemes.py --ids <prefix>` checked; `voice.py` made the clips.
- [ ] Every clip in the core guard's `asked` list.
- [ ] Playfield with `@visibleForTesting` state and debug getters,
      registered in `registry.dart`.
- [ ] Every touch answers within a frame (a sound, a hop or a wiggle).
- [ ] Lasting labels on the pill and on every element tests read.
- [ ] Rendered at four sizes and key states, looked at, and fixed;
      `zz_shots_test.dart` deleted.
- [ ] Widget tests + layout entries in `apps/dearth_app/test/toybox_count_test.dart`.
- [ ] E2E journey in `e2e/tests/toybox_count.spec.ts`.
- [ ] Emoji-12 guard updated if the game adds an emoji list.
- [ ] SPEC FR-TOY-03 list + Appendix B row; README Toybox paragraph;
      PROGRESS 6.2 line + Log entry (+ findings if anything surprised you).
- [ ] `check_game.py <id>` passes; `flutter analyze` and `dart analyze`
      are clean.
- [ ] Committed by explicit paths (no `SUGGESTIONS.md`), clips are LFS,
      `voice_index.json` included.
- [ ] Pushed; `build.yml` green (fixed and re-pushed until it was).
- [ ] Deployed with `tool/deploy_frame.sh 10.0.1.148 --build`.
- [ ] Perf gate run (`tool/perf_gate.sh 10.0.1.148`) and passing.
- [ ] Reported to the owner, with the new clip ids to listen to.

## 10. Traps seen before (from PROGRESS and the playbook)

- A launcher tile below the fold can't be tapped: `openToyboxGame`
  already scrolls to it; keep its "game opened" check in any helper.
- `Hop`/`Wiggle` remount their child: never wrap a stateful board in
  them.
- Ticker-driven games crawl in headless E2E and widget tests: pump in
  frames, assert lasting labels, retry taps on moving things.
- `expect()` inside a mocked callback that runs during a pump throws a
  guarded-call conflict: record, then assert after.
- Widget tests run as Android; a platform event channel with no plugin
  reports an error of its own. Games don't use platform channels, so
  this shouldn't come up.
- A test that ends with a periodic timer or ticker running fails ("A
  Timer is still pending"): call `h.shutdown()` at the end of every test.
- Piper reads "one" like "on", "Z" as "zed", "A" mid-sentence as "uh":
  `voice.dart`'s `_american` fixes "one"; avoid the others or write
  phonemes (`references/voice.md`).
- Don't remake clips the owner already approved (no `voice.py --all`).
