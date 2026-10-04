---
name: toybox-game
description: >-
  How to add or rework a game in Dearth's Toybox, the games for kids aged
  2–5 that run on a family wall display, and make it genuinely great:
  pre-reader design, adaptive levels, code-drawn art, bundled Piper voice
  clips, the game host, speed on a weak 32-bit frame, unit, widget, layout
  and end-to-end tests, docs, gate, commit and deploy. Use it whenever
  someone asks to build, finish, add, polish, fix or test a Toybox game,
  or one of the games planned in SPEC FR-TOY-03 / Appendix B (Dot-to-Dot,
  Big & Little Letters, Frog Hop, Word Builder, Freeze Dance, Music
  Sequencer, Weather Dress-Up, Who's That?, Story Time…), adds voice lines
  to a game, or designs a learning game for toddlers in this repo, even if
  they don't say "Toybox" or "skill".
---

# Adding a Toybox game

The Toybox (SPEC §10.8, FR-TOY-01…08, Appendix B) is a kid surface on a wall
display. Its players are 2 to 5 years old and most can't read. The main
display is a 32-bit Android photo frame with a weak GPU. The owner's bar is
"extremely high quality": a game should feel like a polished commercial
kids' app, run smoothly on that frame, and teach something real. This skill
collects how the first 25 games were built, including the mistakes that
cost time.

A game is six things, and every one ships together:

1. A **catalog entry** and **rules** in `packages/dearth_core` (pure Dart,
   unit-tested).
2. **Voice lines** in `dearth_core` and their **clips** in the app's
   assets (the frame has no text-to-speech).
3. A **playfield widget** in `apps/dearth_app/lib/features/toybox/games/`,
   registered by id.
4. **Tests**: core rules, widget play-throughs, a layout check at four
   screen sizes, and a Playwright journey on four viewports.
5. **Docs**: SPEC Appendix B, README, PROGRESS.
6. A **build** on the household's frame.

Read `AGENTS.md` and `PROGRESS.md` first; they're short and they win if
anything here disagrees with them. Then follow the steps below.

## One game per task

Finish one game end to end (green, committed, deployed), then stop and
report. Don't start the next game in the same task, even if a plan lists
several. The owner reviews each game on the real frame before the next one
starts, and a half-built second game leaves the tree red for whoever comes
next. Mark the step in PROGRESS.md's **In progress** when you start.

## Step 1: Design it before you code it

Write the design down before any code: the row in SPEC Appendix B (and
the FR-TOY-03 list) if it isn't there yet, and for yourself the decisions
below. Most games that disappoint skipped one of them.

- **The skill it teaches** and why this mechanic teaches it. The learning
  should *be* the play: in Dot-to-Dot the numbers are the path; in Letter
  Sounds tapping a letter is hearing it. A quiz bolted onto a toy teaches
  less and bores faster.
- **Overlap.** Read the catalog (`kGames` in `toybox/games.dart`, Appendix
  B). Don't build a second Counting Garden; find the gap.
- **The ladder.** 3 to 6 levels, each a real step (more items, subtler
  differences, a new mode), matching Appendix B. The host moves levels:
  three wins in a row go up, three misses come down (FR-TOY-04). Free-play
  games (no right answers: painting, instruments, a creature builder) set
  `freePlay: true` and unlock a level every three visits.
- **A round.** What she sees, hears and does, start to finish, in under a
  minute. What counts as a slip, how the hint appears, and how slips map
  to `win` / `helped` / `miss` (use `resultFor`, `countingResult` or a
  game-specific helper; never show failure, FR-TOY-04).
- **What the voice says**: the prompt, praise words, names of things, the
  hint. Every instruction a pre-reader needs must be spoken.
- **The reward moment**, specific to this game: the picture comes alive,
  the creature dances, the frog lands. The host adds confetti and a cheer;
  the game's own payoff is what makes it memorable.
- **Ids and labels** (`tid`s) for tests, and the label text E2E will read.
- **Age** (`minMonths`, Appendix B's starting point) and a launcher emoji
  that Android 10 can draw (Emoji 12 or older; a core test checks).

## Step 2: Core rules (`packages/dearth_core/lib/src/toybox/`)

- Add the `GameInfo` to `kExpansionGames` in `games.dart`: `id` (short,
  lowercase: it becomes test ids, settings keys and `game_events.game`),
  title, emoji, `minMonths`, `skills`, `levels`, `freePlay`.
- Put the rules in their own file (`creature.dart`, `tracing.dart`…), exported
  from `lib/dearth_core.dart`: level → round content, slip → result, the
  data (words, pictures, labels). Pure functions taking `Random`, so tests
  are deterministic and can sweep seeds.
- Avoid repeats: rounds take a `recent`/`last` argument so the same
  picture or answer doesn't come twice in a row.
- Unit-test the ladder and the content: every level produces valid rounds
  over 200 seeds, answers are unique, near misses are near, the data has
  no gaps. Name tests after requirements: `'FR-TOY-03 Rhyme Time: …'`.

Templates: `references/anatomy.md`.

## Step 3: Voice

Every line is a clip made offline by Piper and bundled; games ask for
clips by id. Add the id functions and lines in `toybox/voice.dart`, check
pronunciations, run `python3 tool/sounds/voice.py` (incremental: it makes
only new or changed lines), and update the two guard tests. Piper has
traps (an "A" read as the article, "zed" for Z, consonants that grow a
vowel), so read `references/voice.md` before writing lines, and use
`scripts/phonemes.py` to check them. You can't hear the clips; list the
new ones for the owner to listen to on the frame.

## Step 4: The playfield (`apps/dearth_app/lib/features/toybox/games/`)

- One file per game: a `StatefulWidget` taking the `GameController`
  (`c.level`, `c.random`, `c.kid`, `c.sound()`, `c.say()`, `c.cue()`,
  `c.finishRound()`), with a `@visibleForTesting` state class and debug
  getters for tests. Register it in `games/registry.dart`; until then the
  launcher hides the catalog entry.
- Build from the shared pieces so games feel like one family: `Backdrop`,
  `PlayArea`, `PictureTile`, `Hop`, `Wiggle` (`game_widgets.dart`);
  `TopPrompt`, `PromptPill` (with a say-again button), `TileRows`,
  `SubjectCard`, `GlyphView`, `LetterPair` (`voice_widgets.dart`). Look at
  a similar game first (`references/anatomy.md` lists them by mechanic).
- If an emoji makes a poor launcher tile, paint one: `GameIcon` in
  `toybox_screen.dart` already paints Bubble Pop's and Build-a-Creature's.

### Feel: designing for 2-to-5-year-olds

- **No reading.** Pictures, numbers and letters she's learning, and the
  voice. Text labels exist for grown-ups' screen readers and for tests.
- **Every touch answers within a frame**: a sound, a hop, a wiggle. Silence
  after a tap reads as "broken" to a toddler.
- **Mistakes are soft.** A wrong pick plays `c.cue()`, wiggles, maybe says
  what she picked; after two slips the right answer glows (`hint`). A long
  pause shows the same hint without counting a slip. Nothing ever says
  "wrong", and there's no failure screen.
- **Big, forgiving targets.** At least ~64 logical px on a wall (scale with
  `t.scale`); hit areas larger than the art; drags snap when close and
  float back when not; a tap that hits nothing does nothing.
- **Rhythm.** Prompt ~600 ms after a round appears (let it land), praise
  on success, `finishRound()` (the host records, celebrates and moves the
  ladder), next round after ~2.5–3.5 s. Calm-down games pass `calm: true`.
- **One voice at a time.** `say()` stops the clip before it, so a fast
  tapper hears only the latest. Keep effects under the voice (volume
  0.3–0.7); the host applies the grown-ups' volume cap.
- **Variety and growth.** Random content, no immediate repeats, levels
  that change what she does, not just how many.
- **Kid surface rules** (AGENTS rule 9): no destructive actions, no links,
  no text entry, no network, no settings. Time limits and bedtime are the
  host's job.

### Look: code-drawn and consistent

Art is drawn in code (`CustomPainter`, `Path`), so the app ships no image
files and everything stays crisp at any size; emoji are fine for pictures
of things. Match the family: soft two-color `Backdrop`s, white rounded
tiles with lilac borders, painted shapes outlined in dark ink (`0xFF2B2440`)
or a darker shade of their fill, bright but not neon fills, Fredoka for
kid text. `creature.dart`
and `coloring_pictures.dart` show the drawing style; reuse their helpers
(`_blob` Catmull-Rom loops, `_poly`) rather than inventing a new look.

### Speed: the kitchen frame is the target

Joyhong JT215M (SPEC §6, Appendix A): 32-bit ARMv7, 2 GB low-RAM Android 10,
PowerVR GE8300 on the OpenGL ES fallback, a 56 Hz panel. What keeps a game
smooth there (AGENTS rule 8, SPEC §12):

- No `BackdropFilter`, `ShaderMask`, `Opacity` over large subtrees, blurs
  that animate, or a `saveLayer` per frame. Fade by multiplying each
  paint's alpha instead.
- Put each independently moving region in a `RepaintBoundary`. Drive
  per-frame motion with a `ValueNotifier` that a `CustomPainter` listens
  to (`super(repaint: notifier)`), not with `setState` on the whole board.
- Cap continuous motion at 30 fps on T1: in a `Ticker` callback, skip
  every other frame when `DTheme.of(context).policy.ambientFps < 60`.
  Respect `policy.maxParticles`.
- Build geometry once per size and cache it: `Path.combine` and path
  metrics are slow on this CPU (Build-a-Creature caches its unioned
  outlines; a dance frame unions nothing).
- Stop tickers and cancel timers in `dispose`. Decode any image at its
  display size.

### Testability: ids and labels are a contract

- Give every element a journey touches a `tid('<game>.<thing>[.<i>]', …)`
  (AGENTS rule 10). Put the readable text on that node: a `PictureTile`
  label, or `Semantics(label: …, excludeSemantics: true)` right inside the
  `tid`.
- Make labels carry state in a parseable form: `'Letter B, heard'`,
  `'Tracing B: 2 of 3 done'`, `'Wobblesaurus, pink: a round body, googly
  eyes'`.
  Tests play from what the screen says, as a person would.
- Keep a `tid`'d control's `onTap` non-null in every state (do nothing
  instead). On the web, a node whose role changes loses its id.
- A `GestureDetector` inside a `tid` makes its own semantics node and
  swallows the id: use `excludeFromSemantics: true`, or a `Listener`.
- Expose a lasting label for "done" (`'You found it!'`, `'X traced'`). The
  celebration is gone in ~2 s, and headless E2E can be slower than that.

## Step 5: Look at it before you test it

Render the game to PNGs at the four layout sizes and at its key states
(fresh round, hint showing, finished), then look at them the way a
designer would: alignment, sizes of targets, crowding on the phone,
contrast, whether a 3-year-old could tell what to do. Copy
`scripts/shots_test.dart.tmpl` to `apps/dearth_app/test/zz_shots_test.dart`
and run it (instructions at its top: `SHOT_GAME`, `SHOT_LEVELS`). Crop
with ImageMagick (`magick`, `montage`) to inspect details. Fix, re-render, repeat. **Delete the shots test
before committing.** With every test green, this step still found
Build-a-Creature's part buttons too small to read, and showed that the
phone-size layout tests had been looking at the launcher, not the game.

## Step 6: Tests

- **Widget tests** (`apps/dearth_app/test/toybox_<family>_test.dart`),
  opened through the real Toybox with `openToyboxGame(tester, '<id>',
  level:, size:, sound: RecordingSound())`:
  - a play-through: the prompt clip is said, the right pick wins, and
    `toyboxRounds(h)` records `('<id>', level, 'win')`;
  - slips: the cue, the hint after two, the result `helped`/`miss`;
  - the voice: `sound.said` holds the expected clip ids in order;
  - `expectNoFallbackText(byId('screen.game'))` (catches unstyled text);
  - the **layout test**: add `('<id>', 1)` and `('<id>', <busiest level>)`
    to the "lays out on a W×H screen" loop, which runs 390×844, 844×390,
    1080×1920 and 1920×1080 and fails on any overflow.
- **E2E** (`e2e/tests/toybox_<family>.spec.ts`): one journey that plays a
  round from the labels on screen, on all four projects. The demo kid,
  Ava, is 2½: pass `early = true` to `openToyboxGame(page, '<id>', true)`
  for games aimed older than 30 months.
- The voice guards in both packages must pass (`references/voice.md`).

## Step 7: Docs

- `SPEC.md`: the Appendix B row (ages, skills, how it plays, ladder) and
  the FR-TOY-03 list, if not already there.
- `README.md`: add the game to the Toybox paragraph's list.
- `PROGRESS.md`: the 6.2 Toybox line (what it does, briefly), a dated
  **Log** entry with test counts, and anything surprising under
  **Decisions & findings**. Clear the **In progress** marker.

## Step 8: Verify, commit, deploy, stop

1. `python3 skills/toybox-game/scripts/check_game.py <id>`: every
   place the game must appear (catalog, registry, tests, E2E, docs,
   clips).
2. `tool/check.sh --fast`: analyze plus every unit and widget suite. It
   must be green; never leave the tree red (AGENTS rule 1).
3. `CHROME_PATH=/usr/bin/google-chrome-stable tool/e2e.sh toybox`: builds
   the web app and runs every Toybox journey (each spec whose path
   contains "toybox") on the four viewports. CI runs the full suite on
   push.
4. Commit only this game's paths, named explicitly (never `git add -A`:
   the tree may hold someone's unrelated work, like the owner's
   `SUGGESTIONS.md`). New clips must be LFS-tracked:
   `git check-attr filter -- <clip>` says `lfs`. Message: `feat(toybox):
   <Game>`, a body that says what it does and why, test counts, and the
   attribution line the session asks for.
5. Deploy: `tool/deploy_frame.sh <frame-ip> --build` (the household's
   address is in PROGRESS.md's command table). It builds the APK for the
   frame's CPU and installs it over the old one.
6. Stop and report: what the game does, what was verified, new clips to
   listen to, anything left for the owner (pushes go through the owner;
   CI publishes a release per push).

## Gotchas that cost hours

- **Tests that never opened the game.** A launcher tile below the fold
  can't be tapped. `openToyboxGame` now scrolls to it and fails if the
  game didn't open; keep that check in any helper you write.
- **`Hop`/`Wiggle` remount their child** (a `TweenAnimationBuilder` keyed
  on the count). Never wrap a stateful board in them.
- **Headless E2E is slow on wall sizes** (~200 ms per mouse step): assert
  lasting labels, not the celebration; drag through on-screen waypoints
  (`trace.point.N`) rather than long synthetic paths.
- **The test clock is fixed** (`AppHarness` pins `now`), so time-based host
  behavior (free-play sessions recorded on leave) can't be measured in a
  widget test; cover the rule in core tests instead.
- **Emoji 13+ draws as a box on the frame.** The core guard test lists
  every emoji the Toybox shows; add new picture lists to it.
- **Riverpod in games**: don't read providers from a game; everything comes
  through `GameController`. No `DateTime.now()` (AGENTS rule 6).
- **Piper is random on every run**, so `voice.py --all` changes every clip
  the owner already approved. Remake only what you changed.

## Reference files

- `references/anatomy.md`: file map, the `GameController` and widget
  APIs, sound effects, and code templates (core rules, game widget,
  widget test, E2E journey), with existing games grouped by mechanic.
- `references/voice.md`: voice lines, Piper and phonemes, pronunciation
  checks, making clips, the guard tests.
- `references/checklist.md`: the review checklist to run before
  committing.
- `scripts/check_game.py <id>`: checks that a game is wired in everywhere
  (catalog, registry, tests, E2E, docs, clips).
- `scripts/phonemes.py "line" …` or `--ids <prefix>`: shows how the voice
  will read lines, British and American side by side.
- `scripts/shots_test.dart.tmpl`: the PNG render test for the visual
  review (copy it into the app's tests; delete it after).
