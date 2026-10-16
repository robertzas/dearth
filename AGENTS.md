# AGENTS.md — working on Dearth

**Dearth** is a family command center for wall-mounted touchscreens: a
shared calendar, meals and recipes, chores and rewards, a toddler
Toybox, photos, and weather. It runs fast on a cheap Android frame,
looks good enough to leave on the wall, and keeps the family's data on
its own hardware — local-first, no subscription, no vendor cloud. Two
experiences drive every design call: **the five-second glance** (anyone
across the kitchen knows what's happening today) and **the five-minute
delight** (a 2.5-year-old can play in the Toybox and nothing she taps
can break the family's data). The full product contract is `SPEC.md`.

This file is the working manual and is **self-contained**: read it
before any task. The other documents carry detail on demand:

| Doc | What it's for |
|---|---|
| `PROGRESS.md` | Where the build is: state, open items, what's waiting on the owner, how to resume after an interruption. Update it when a step starts and finishes. |
| `SPEC.md` | The product contract. Requirement IDs (`FR-CAL-12`) are referenced from code comments and test names; sections (`SPEC §12.9`) from code, tests and tools. Changing specified behavior means updating SPEC in the same commit. |
| `SUGGESTIONS.md` | Verified open improvements (each checked against the code; fixed or disproven items are removed). |
| `skills/` | Task playbooks. `skills/toybox-game/SKILL.md` (design for pre-readers, rules, voice clips, art, speed on the frame, tests, docs, deploy) — read it before touching `lib/features/toybox/` or `dearth_core`'s `src/toybox/`. |
| `README.md` | User-facing setup: the Hub, Google OAuth, photos, the frame, updating, Android signing. |

## Layout

| Path | What lives there |
|---|---|
| `packages/dearth_core` | Pure Dart. Drift schema (`lib/src/db/tables.dart`), sync (HLC, ops, merge, protocol, `SyncStore`, `Mutator`), and domain logic (calendar, recipes, kids, weather models, solar). **No Flutter imports.** |
| `packages/dearth_integrations` | Pure Dart provider adapters (weather, Google, ICS, photos, recipes, music) behind small interfaces, with fixture-based tests. |
| `packages/dearth_ui` | Flutter design system: tokens, themes, display classes, `uiScale`, tiers, motion, components. No app state. |
| `hub/dearth_hub` | Dart server: sync authority, pairing, blobs, jobs, integrations, admin API, web hosting. |
| `apps/dearth_app` | The Flutter app for every platform. Feature-first folders under `lib/features/<feature>/`. Solo mode's built-in Hub lives in `lib/core/solo/`. |
| `e2e/` | Playwright end-to-end suite against the web build and a test Hub. |
| `tool/` | `check.sh`, `codegen.sh`, `build_all.sh`, `e2e.sh`, `dev_hub.sh`, `web_assets.sh`, `deploy_frame.sh`, `perf_gate.sh` (see Commands). `icons/` (SVG source of every app icon, `make_icons.sh`). `fonts/make_emoji_font.sh` (builds `DearthEmoji.ttf`: the emoji Android 10's font lacks, from a pinned Noto Color Emoji). `perf/` (perf-gate baselines). `sounds/` (the Toybox voice). `find_adb.sh` (how both ADB scripts find adb). `web_assets.sh` pins `sqlite3.wasm` by SHA-256: a new sqlite3 version needs its hash added there. |
| `skills/` | Task playbooks for agents, checked in with the code: `toybox-game/` (adding a Toybox game). |
| `.github/` | `workflows/build.yml`: every push to `main` runs the gate and the E2E suite, builds every platform plus the Hub image, and publishes a GitHub release `v<major>.<minor>.<run>` (major and minor from the app's pubspec, the patch is the run number). `actions/setup`: shared Flutter, pub and LFS setup. `actions/hub-build`: one Hub bundle from the Hub-only workspace (`hub/pubspec.workspace.yaml`, also used by the Dockerfile). |
| `compose.yml`, `Dockerfile` | Hub deployment (SPEC §14.6) and its Watchtower updater. |

## Golden rules

1. **Never leave the tree red; CI is the test runner.** Don't run the
   suites or E2E locally. When a step is ready, commit and push to `main`;
   the `build.yml` run (gate, E2E, every platform) is the check; a newer
   push cancels every older run on its branch, so batch related commits. If it
   fails, read the failing job, fix, push again, and repeat until green
   before starting anything new. If a session is interrupted, the next
   one checks the latest run and fixes or reverts first (see
   `PROGRESS.md`).
2. **All synced writes go through `Mutator`** (devices) or the Hub's op
   pipeline. Never `INSERT`/`UPDATE` a synced table directly: it bypasses
   HLC stamping, replication and the outbox.
3. **Synced columns are nullable or defaulted.** Op field keys are SQL
   column names (`start_ms`, `profile_ids`). JSON columns hold encoded text;
   `Mutator` encodes `Map`/`List` values for you.
4. **Append-only tables** (`ledger_entries`, `feeling_entries`,
   `game_events`) use `Mutator.insertOnly` and are never updated. Balances
   are sums. Concurrent inserts of the same deterministic id converge
   first-writer-wins (lowest HLC).
5. **Natural-key rows use `stableId(kind, parts)`** (chore instances, routine
   runs, shopping states) so devices converge offline.
6. **Instants are epoch ms (UTC); local dates are `LocalDate`/`YYYY-MM-DD`.**
   Every "today" decision goes through `HouseholdTime`. No ad-hoc
   `DateTime.now()` in feature code.
7. **Integrations run on the Hub** (in Solo mode, the Hub built into the
   app: `core/solo/`). Widgets never call providers or HTTP.
8. **Performance is a requirement** (SPEC §12). Don't use `BackdropFilter`,
   `ShaderMask`, `Opacity` over large subtrees, or animated blur in feature
   code. Give independently animating regions a `RepaintBoundary`. Decode
   images at display size. Ambient animations are capped at 30 fps on T1 —
   via `AmbientTicker`, never a plain `Ticker` that skips updates (see
   Performance).
9. **Kid surfaces have no destructive actions.** Anything irreversible needs
   grown-up mode (PIN).
10. **Test identifiers are a contract.** Widgets on user journeys use
    `tid('area.thing', child)` (a `Semantics(identifier:)`). Playwright
    selects them via `flt-semantics-identifier`. Renaming one means updating
    `e2e/`. When a test needs to read text, put the `tid` on a node that
    carries the text itself: a leaf, or `Semantics(label: …,
    excludeSemantics: true)` directly inside the `tid`. A container's
    children are separate DOM nodes, so the container exposes no text.
11. **Write in bulk.** Many ops go into one `Mutator.commit` (or
    `DataWriter.commit`), which applies them with `SyncStore.applyOpsBulk`
    inside a single transaction. Raw maintenance writes use `db.batch`.
    Never `await` one statement per row in a loop: on the web, every
    statement is a round trip to the drift worker (hundreds of ms while
    frames are busy). Seeding the onboarding demo one statement at a time
    once made it look hung.
12. **Import Material from `package:material_ui/material_ui.dart`**, never
    `package:flutter/material.dart`. Flutter 3.47 moved Material into its
    own package, and go_router only recognizes material_ui's `MaterialApp`.
13. **Binary files go through Git LFS.** `.gitattributes` lists the
    extensions (images, fonts, wasm, archives, media — including the
    Toybox's mp3 clips). Check `git lfs ls-files` before committing a new
    kind of binary. Generated text (`database.g.dart`, `web/drift_worker.js`)
    stays in plain git.

## Product modes (SPEC §7.2)

| Mode | What it is |
|---|---|
| **Hub** | Docker Hub on the LAN/HTTPS domain; devices pair with a QR + code, get a bearer token, sync over one WebSocket. |
| **Solo** | The real Hub runs inside the app on 127.0.0.1 (`core/solo/`): every feature works on one device with no server. Households move Solo ↔ Hub with data and blobs (imported rows are stamped with the target's clock so the family's settings win). |
| **Toybox only** | A network-free first-run mode: one child + grown-up PIN, only the Toybox and trimmed Settings. |
| **Demo** | `?demo=1`: a seeded household at a fixed clock, in every build — how E2E and the perf gate run. |

## Commands

| Purpose | Command |
|---|---|
| Everything green? | the latest `build.yml` run on `main` (`tool/check.sh` reproduces the gate locally, `--serial` one at a time) |
| Regenerate drift code | `tool/codegen.sh` (after editing `tables.dart`) |
| Run the Hub locally | `tool/dev_hub.sh` |
| Run the app (web / linux) | `cd apps/dearth_app && flutter run -d chrome` / `-d linux` |
| Build all host-buildable targets | `tool/build_all.sh` (CI builds iOS/macOS/Windows on their own runners) |
| Web E2E (Playwright, 4 viewports) | `CHROME_PATH=/usr/bin/google-chrome-stable tool/e2e.sh <area>` (`SKIP_BUILD=1` reuses the web build) |
| Web DB runtime (sqlite3.wasm, drift worker) | `tool/web_assets.sh` |
| App icons from the SVG source | `tool/icons/make_icons.sh` |
| Set up, check or update the kitchen frame | `tool/deploy_frame.sh 10.0.1.148` (`--check` changes nothing; `--help`) |
| Perf gate on the kitchen frame (SPEC §12.9) | `tool/perf_gate.sh 10.0.1.148` (~15–20 min, unattended; ends in a Markdown report; `--update-baseline` after an accepted change) |
| Regenerate / remake voice clips | `tool/sounds/voice.py` (all; or `<clip_id>` for one) |

## The kitchen frame (the T1 target)

The reference device is a Joyhong JT215M-H01 (Allwinner A133-class,
board `ceres`); SPEC §6.1 has the full measured profile. What matters
while coding:

- **32-bit only** (`armeabi-v7a`, zygote32): every native dependency must
  ship armeabi-v7a; CI builds `android-arm` for it.
- **Android 10 (API 29), test-keys, rooted adbd** (LAN port 5555, no
  authorization) — how `deploy_frame.sh` and the app's own silent updater
  (`LocalAdb`) reach it. `adb screencap` returns nothing (FreeKiosk sets
  `disable-screen-capture`): read the screen with `uiautomator dump`
  (Flutter semantics appear as content-desc nodes with bounds) or the
  app's own remote screenshot (FR-ADM-02).
- **No Google Play Services** (no `google_sign_in`, no FCM) and **no TTS
  engine** — OAuth happens on the Hub; Toybox voice clips are bundled.
- **2 GB RAM, `ro.config.low_ram=true`** → auto-detects tier **T1**.
  4× Cortex-A53 @ 1.5 GHz.
- **GPU PowerVR GE8300**: its Vulkan driver is denylisted, so the engine
  picks **Impeller-GLES**. Fill-rate bound, no clock headroom. 1080p @
  **56 Hz** (17.9 ms frame budget); density override 173 → ≈1777×1000 dp
  in landscape.
- **No RTC**: boots at its ROM's build date. `ClockCheck`/`ClockLayer`
  cover the app with "Setting the time…" and hold sync until the clock
  is plausible (FR-DSP-05).
- **Sensors**: ambient light (pt3r850) drives the app's own brightness
  curve and night-when-dark (FR-DSP-02); the accelerometer orients wall
  displays (`fullSensor`).
- **Emoji**: the system font draws Emoji 12 at most. `DearthEmoji.ttf`
  (`tool/fonts/make_emoji_font.sh`) bundles the 136 single-code-point
  emoji Android 10 lacks, loads before the first frame (not web/Apple)
  and sits last in every fallback list. `DEmoji` draws content emoji as
  images (see Performance).
- **FreeKiosk** (pinned) is Device Owner and HOME launcher in External
  App mode locked to Dearth (`app.dearth`). Dearth owns the exit gesture
  (hold the clock 3 s → corner sequence → Dearth PIN → kiosk menu);
  FreeKiosk's own fallback is an invisible 48 dp corner button (5 quick
  taps → its PIN), and Dearth keeps that corner clear
  (`kKioskCornerClearance`). Its REST bridge on 127.0.0.1 handles screen
  off/on, status and reboot (SPEC §13.9). Its boot screen can stick when
  NTP moves the clock; `KioskWatch` unsticks it two minutes after boot.
- **Keyboard**: HeliBoard 4.2 (pinned, no network) is the only enabled
  keyboard. The ROM's **AWBMS** background manager silently refuses to
  start services of off-whitelist apps, so Dearth re-whitelists the
  keyboard's package at every launch over root adbd (`keyboard_allow.dart`).
  Dearth's fields ask for no auto-correct and close on a tap elsewhere.
- **Never disable `com.waophoto.fota`** — every app crash-loops without it
  (`deploy_frame.sh` keeps the vendor-app list).

## Performance on the frame (SPEC §12 is the contract)

Budgets (§12.1): 17.9 ms total (build p90 ≤ 7 ms, raster p90 ≤ 10 ms),
< 1 % janky frames, no frame > 50 ms outside cold start. **No fixed PSS
ceiling** (owner, 2026-10-11): the perf gate watches growth and the
baseline. Release builds for displays should pass the perf gate on the
frame.

Measured laws of the GE8300 under Impeller — re-verify on every Flutter
upgrade with `tool/perf_gate.sh`:

- **Impeller keeps no raster cache**: every frame in which anything moves
  redraws everything. Costly fills are what hurt.
- **Gradients are the killer**: a full-screen corner-to-corner gradient
  costs ~73 ms/frame there (top-to-bottom ~5 ms); gradients inside paths,
  rounded cards and scaling radial glows are the same slow kind. Use flat
  fills (launcher tiles are solid `hue` fills: scroll went 14.4 → 45.2
  fps) or paint scenery once.
- **`DStillPaint`** (dearth_ui) renders a still `CustomPainter` into an
  image at its box's pixel size and draws that, repainting only when
  `shouldRepaint` or the size says so (`shareKey:` shares one image
  between same-sized boxes; `outset:` keeps a drop shadow). 14 games'
  still scenery, card backs and pieces went through it (Memory Match
  raster p90 83 → 16 ms).
- **Emoji as text under a changing transform** (press, pop-in,
  celebration, card flip) is re-decoded and re-uploaded every frame:
  twelve pulsing emoji ran at 7 fps; drawn from images, 57 fps. `DEmoji`
  draws each emoji once into an image at its on-screen size (LRU 24 MB;
  text on the web, whose emoji font loads late) and takes `tint:` for
  shadows without a `ColorFiltered` layer.
- **A plain `Ticker` that skips updates still requests every vsync**, so
  a "30 fps cap" that only skips updates draws every frame at full
  raster. `AmbientTicker` (dearth_ui) mutes itself between ticks — use it
  for all ambient motion on T1.
- **`SnapshotWidget` pieces are offscreen passes retaken whenever a piece
  lifts or remounts** — they made Shape Sorter *worse* (103 → 226 frames
  over 50 ms). Prefer `DStillPaint` or cached `ui.Picture`s.
- **Measure with** `dumpsys SurfaceFlinger --latency` or the perf gate.
  HWUI `gfxinfo` sees nothing under a Flutter surface (its `Pipeline=`
  line describes the Android window, not Flutter) — an armchair-diagnosis
  trap.

**Renderer decision (owner, final 2026-10-05): Impeller-GLES at 1080p**,
no manifest flag. The deprecated Skia opt-out measured 56.8 fps against
14 on the old Toybox grid, and lower resolutions reached 57 fps, but
both were rejected — renderer longevity, photo and text crispness. The
gap is closed app-side (§12.2 has the evidence matrix and the
escalation ladder).

Tiers set the effects budget (§6.2): **T1** (RAM ≤ 3 GB or weak
Impeller-GLES GPUs: no runtime blurs, ambient ≤ 30 fps, capped
celebrations, image cache 48 MB, keep-alive Home + current screen), T2,
T3. Display classes (Wall-L / Wall-P / Tablet / Phone) pick layout and
navigation; `uiScale` comes from the configured diagonal and viewing
distance (§11.2), 80–140 %.

## Data, sync and migrations (SPEC §8 is the contract)

- Ops merge **field-level last-writer-wins** under Hybrid Logical Clocks;
  ties are impossible (node id breaks them). A device's database is a
  replica — a wiped device re-bootstraps from the Hub's scoped snapshot.
- **Solo mode** runs the real Hub inside the app (rule 7); moving a
  household Solo ↔ Hub copies synced tables and blobs, stamps imported
  rows with the target's clock (a fresh Hub's defaults would otherwise
  win), and leaves integration secrets behind (§8.7).
- Scopes (§8.5) are implemented at **table granularity** in v1;
  row-level rules (private lists, per-calendar visible roles) are a
  known follow-up.
- **Schema migrations stay additive** (§8.4.5): bump `schemaVersion`,
  add `if (from < N)` steps in `DearthDb.migration`, and extend
  `packages/dearth_core/test/schema_test.dart` to upgrade a database
  file at the old version. Hub-only tables are created on devices too
  and stay empty there.
- **Android Keystore is shared by every build of `app.dearth`**: anything
  that starts a demo/session in-process on the device (the perf-gate
  scenarios) must use `SessionStore(secure: false)`, or it wipes the
  installed app's Hub token.

## Toybox and its voice

Read `skills/toybox-game/SKILL.md` first. Invariants that outlive the
skill:

- **59 games ship** (SPEC §10.8, Appendix B is the per-game design
  contract), all on by default — ages are starting points (FR-TOY-01).
  Launcher order: new-and-unplayed first, then favorites (last 14 days),
  then the rest by stage.
- **A game id is forever** — it is stored in every `game_events` row
  (append-only; the level ladder is recomputed from rounds, so it
  converges across displays with no level table).
- All game art is drawn in code; still scenery goes through
  `DStillPaint`; every clip is bundled (the frame has no TTS). New mp3s
  are LFS binaries (rule 13).
- The voice is **Maya-1** (Apache-2.0, `tool/sounds/voice.py`): a voice
  *designed* from a written description (a warm preschool teacher) —
  **never a clone of a real person**, even if asked: the clips ship in a
  public repo's releases. Lines live in `dearth_core`'s
  `toybox/voice.dart`; letter sounds are authored as `[[IPA]]` and
  respelled by `RESPELL` in voice.py (the build fails on an unmapped
  span). voice.py keeps a hash index (only changed lines are remade),
  writes each clip's length to `voice_lengths.g.dart`, and
  `afterVoice(clip)` lets a line finish before the next. It runs on the
  local RTX 3070 (Maya1 is 3.3 B; the first regeneration downloads ~7 GB
  of model; venv `~/.cache/dearth/venv-voice`).
  `tool/sounds/preview.py` prints the respelled text (`--say` makes a
  clip to hear). The owner has yet to audition the `letter_*`/`sound_*`
  respellings on the frame; `python3 tool/sounds/voice.py letter_b`
  remakes one after a `RESPELL` tweak.

## Releases and updates (SPEC §15.3)

- Every green push to `main` publishes **`v<major>.<minor>.<run>`** with
  an APK per ABI, all signed with the one release key (GitHub secrets;
  local builds read `apps/dearth_app/android/key.properties`, gitignored
  — the key is in `~/.config/dearth/android-release.jks` and must be
  backed up). `deploy_frame.sh --build` and the perf gate build with the
  installed build number, so neither is a downgrade.
- The app updates **from GitHub releases itself** (not through the Hub —
  the one network call outside it besides the FreeKiosk bridge): it
  checks `releases/latest` two minutes after start, every four hours,
  and when Settings → Updates opens; picks the ABI asset and verifies
  its SHA-256. On the frame it installs silently through its own root
  adbd (`cat apk | pm install -r -S size` in the foreground; the new
  version self-starts from `MY_PACKAGE_REPLACED`); elsewhere a
  `PackageInstaller` session and Android's confirm screen. Per display:
  When I tap (default) / Nightly / When idle; never while a timer runs.
- The Hub updates itself through the Watchtower beside it in
  `compose.yml` (token-protected, label-scoped; README → Updating the
  Hub). Hubs without the updater only report.
- Release-per-push is by design (it feeds the updates); a retention
  prune is an open suggestion, not done.
- **The frame perf gate can't run in CI** (it needs the hardware): a
  display set to update by itself runs whatever passed CI, so run
  `tool/perf_gate.sh` on the frame before display releases. It is
  unattended: it asks the app what it is, gets a single-use rejoin code
  from the device's Hub, resets (clears) the app for a clean demo-mode
  measurement, puts the device back as the same device id and waits
  until it syncs live. Solo/Toybox-only/demo displays are never reset
  (`--no-reset` for any). Ask the owner before long runs there — it is
  a household device in use.

## Testing

CI runs everything below on every push (golden rule 1); these are the
commands it uses, for reproducing a failure it reports.

- `dearth_core`, `dearth_integrations`, `dearth_hub`: `dart test`. Provider
  adapters are tested against recorded fixtures; no network in tests.
- `dearth_ui`, `dearth_app`: `flutter test` (unit + widget). Widget tests
  run as Android: platform channels report missing-plugin errors as
  their own failures, so the harness (`test/support/`) fakes them.
- End to end: `tool/e2e.sh` builds the web app, starts a Hub with
  `DEARTH_FAKE_PROVIDERS=1` on a temp data dir, and runs Playwright across
  the Wall-L, Wall-P, Tablet and Phone projects. `SKIP_BUILD=1` reuses the
  last web build. `CHROME_PATH=/usr/bin/google-chrome-stable` uses a system
  Chrome instead of downloading one. Extra arguments go to
  `playwright test`, e.g. `tool/e2e.sh tests/calendar.spec.ts`. CI splits
  the suite across sixteen runners (`--shard=N/16`: the runners free under
  the free plan's 20-job limit when the web build lands, see the top of
  `build.yml`) against the Hub job's compiled binary
  (`DEARTH_HUB_BIN`); locally it runs three
  browsers (more starve each other and journeys time out). Playwright's
  runner needs Node: under Bun it can't load its TypeScript config, and
  the time is all in the browser anyway.
- `tool/check.sh` runs analyze and every suite at once after codegen
  (`--serial` for one at a time). CI runs it in groups on separate runners
  (`--only=codegen`, `--only=analyze`, `--only=core,integrations,hub,ui`,
  and `--only=app --shard=N/4`, which splits the app's tests four ways);
  the failing job's name gives the command that reproduces it.
- E2E specs drive the app through `e2e/tests/helpers.ts`:
  - `openDemo(page, route)` starts a seeded local household at a fixed
    clock (`?demo=1&e2e=1&now=…`).
  - `tap()` clicks the centre of the node, as a finger would. Empty
    semantics containers can overlap it in the DOM, and Flutter hit-tests
    the pointer position itself.
  - `expectText()` polls the aria-label and the text content.
  - `scrollTo()` wheels lazy lists until a `tid` is built (wall side
    sheets start near the middle: it wheels over the target's own column).
  - `goTo()` uses whichever navigation chrome the layout shows.
  - Widget tests that open a Toybox game must scroll the launcher tile
    into view (`openToyboxGame` does it and fails unless the game opened;
    it takes provider `overrides`).
- Name tests after requirements where possible: `FR-CAL-12: quick add …`.
- Flaky watch: the meals FR-RCP-01 scaling journey (CI shard 5/16) failed
  twice at one stepper step and passed elsewhere — if it fails, rerun
  before digging.

## Code generation

Drift code lives next to the schema (`database.g.dart`) and is committed.
After editing `tables.dart`, run `tool/codegen.sh`. Builders take ~90 s the
first time.

## Style

- Strict analysis (`analysis_options.yaml` at the root). No `dynamic`, no
  `print` (use `package:logging` / the app logger).
- The code isn't `dart format`-ed (lines run to ~160–200 columns). Don't
  run the formatter on existing files: it reflows unrelated code and buries
  the real change in the diff.
- Prefer small, composable widgets with `const` constructors.
- Riverpod: narrow providers, `select` in widgets, no business logic in
  `build`. Riverpod 3 pauses providers that nothing listens to, so in an
  event handler `ref.read(p).value` is null and `ref.read(p.future)` can
  wait forever unless a visible widget watches `p`. For one-off reads,
  query the database directly (e.g. `shoppingListOnce(db)`).
- Comments explain *why*. Reference spec sections (`SPEC §8.4`) when a rule
  comes from there.

## Gotchas that cost time (all verified)

- `DTheme` exposes the type scale as `text`, not `type`:
  `ThemeExtension.type` is the extension lookup key; overriding it made
  `DTheme.of(context)` fail.
- Text drawn above the Navigator (toast host, overlays) or in the display
  layer (screensaver, night clock — rendered above the app's Navigator
  while the app sits under `TickerMode(enabled: false)`) needs its own
  `Material(type: transparency)` ancestor or Flutter draws the yellow
  debug underline; the display layer also needs its own Navigator for
  sheets, and it must *listen* to what it shows (Riverpod 3 pauses the
  subscriptions of consumers under a disabled TickerMode, so a `ref.read`
  can be empty or stale). `expectNoFallbackText()` in
  `test/support/app_harness.dart` catches fallback-styled text.
- A `GestureDetector` inside a `tid` forms its own semantics node and
  drops the id: use `excludeFromSemantics: true` when the gesture needs
  a pointer position anyway. Related: Flutter web drops a node's
  `flt-semantics-identifier` when its role changes — keep a tid'd
  control's `onTap` non-null (do nothing instead).
- Never derive an id from `String.hashCode` — the web and the VM hash
  strings differently (holiday ids are name slugs; deterministic ids are
  UUIDv5 via `stableId`).
- A quick second tap can race a widget's own in-flight animation (a
  flying cookie caught a tap and flew straight back): make moving
  pieces ignore taps while animating.
- Review renders that pump in one frame show implicit animations mid-
  flight: pump review screenshots in steps.
- A backgrounded shell function's `$!` is the subshell, not `adb` — adb
  logcat readers leak in perf tooling without explicit pids.

## Where the build is

`PROGRESS.md` holds the live state, open items and owner-pending
actions. Summary as of 2026-10-15:

- **M1–M3 built and shipping**: Home, Calendar (Google two-way + ICS +
  People + kid timeline + reminders + Family offer), Weather, Photos &
  screensaver, Settings (grouped, searchable), Meals (aggregated search,
  planner, cook mode, family box, synced kitchen timers), Lists (Google
  Tasks sync), Kids (chart, celebrations, approvals — approve or "Not
  yet" — routines, reward jar, star bank, stickers), Solo and Toybox-only
  modes, the Android platform channel (brightness, night, screen off,
  clock check), FreeKiosk bridge, device removal, GitHub self-updates
  for app and Hub. Frame on v0.1.126; CI green.
- **59 Toybox games**, all voiced (Maya-1) and audited for frame speed
  (2026-10-13/14).
- **Deferred**: the Music box (owner, 2026-10-05) — its requirements stand
  in SPEC §10.9/§13.7 for when it comes back.
- **Known open**: standing perf misses (week paging ~216 ms and month
  ~370 ms builds; navigate swings ~95–160 ms with the same build — cause
  unknown, the gate re-measures), the nav rail overflows at 720p +
  userScale 1.6, and everything in `SUGGESTIONS.md` and
  `PROGRESS.md` → Open items.
