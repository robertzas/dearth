# Before you commit a Toybox game

Go through this with the game open in your renders and the diff in front
of you. Each item is here because a game once shipped, or nearly shipped,
without it.

## Learning and design

- [ ] The skill is the mechanic, not a quiz added on top.
- [ ] The Appendix B row (ages, skills, how it plays, ladder) describes
      what was built.
- [ ] Level 1 is winnable by the youngest kid in the age band; the top
      level stretches the oldest. Each level changes something real.
- [ ] Rounds vary, and the same answer or picture never comes twice in a
      row.
- [ ] Slips map to `win` / `helped` / `miss` fairly for the round's size.

## A pre-reader can play it

- [ ] Within three seconds of a round, the picture and the voice make it
      clear what to do. Nothing requires reading.
- [ ] Every touch answers at once: a sound, a hop or a wiggle.
- [ ] A wrong pick: `c.cue()`, a wiggle, maybe a word; after two, the
      answer glows; after a long pause, the same glow without a slip.
      Nothing says "wrong"; no failure screen.
- [ ] Targets are big (about 64 px or more on a wall) with generous hit
      areas; drags snap when close and float back otherwise.
- [ ] The prompt is spoken ~600 ms into the round, the pill's 🔊 says it
      again, and effects sit under the voice.
- [ ] A reward moment of the game's own, then `finishRound()` with an
      Emoji-12 emoji, then the next round by itself. Calm games pass
      `calm: true`.
- [ ] No destructive actions, links, text entry, network or settings.

## Voice

- [ ] New lines reuse existing clips where they can, and are short and
      warm.
- [ ] Checked with `scripts/phonemes.py`: no "zed", no article "a" for
      the letter A, no British words, letter sounds in `[[ ]]`.
- [ ] Clips made with `voice.py` (not `--all`); both voice guards pass;
      clips are LFS; the new clip ids are listed in the report.

## Looks right

- [ ] Rendered at 390×844, 844×390, 1080×1920 and 1920×1080, fresh and
      at a hint and at the finish, and reviewed: nothing cut off,
      crowded or tiny on the phone; aligned; same family as the other
      games (backdrop, tiles, ink, Fredoka).
- [ ] The launcher tile looks good (paint a `GameIcon` if the emoji
      doesn't).

## Runs well on the frame

- [ ] No `BackdropFilter`, `ShaderMask`, `Opacity` over a subtree,
      animated blur, or `saveLayer` per frame.
- [ ] Moving parts sit in `RepaintBoundary`s and repaint from a
      `ValueNotifier`, not a board-wide `setState`.
- [ ] Continuous motion skips frames on T1 (30 fps); particles respect
      `policy.maxParticles`.
- [ ] Geometry and unioned paths are built once per size, not per frame.
- [ ] Every `Timer`, `Ticker` and controller is cancelled or disposed.

## Testable

- [ ] Every element a journey touches has a `tid`, and its label carries
      its state.
- [ ] `tid`'d controls keep a non-null `onTap` in every state.
- [ ] A lasting "done" label exists for tests to wait on.
- [ ] Debug getters (`debugRound`…) on a `@visibleForTesting` state class.

## Tests

- [ ] Core: the ladder, content over 200 seeds, results, the data.
- [ ] Widget: a play-through with the clips said and the round recorded;
      slips and hints; `expectNoFallbackText`; the layout loop at four
      sizes for level 1 and the busiest level.
- [ ] E2E: a journey played from the labels, green on all four projects.

## Docs and ship

- [ ] SPEC (Appendix B row, FR-TOY-03 list), README (Toybox paragraph),
      PROGRESS (6.2 line, Log entry with test counts, findings, In
      progress cleared).
- [ ] `python3 skills/toybox-game/scripts/check_game.py <id>` shows only ✓.
- [ ] `tool/check.sh --fast` is green; the Toybox E2E specs are green.
- [ ] The temporary `apps/dearth_app/test/zz_shots_test.dart` is gone.
- [ ] The commit names only this game's paths; the message says what and
      why, with test counts.
- [ ] Deployed with `tool/deploy_frame.sh <frame-ip> --build`; reported;
      stopped.
