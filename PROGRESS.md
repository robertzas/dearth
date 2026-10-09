# PROGRESS — build log & crash-recovery guide

This file is the single source of truth for **where the build is**. Any
session (human or agent) that starts work MUST read it first and update it
when a step starts and finishes. If a turn dies mid-step, the next session
resumes from here.

## How to resume after an interruption

1. Read this file top to bottom, then `SPEC.md` sections named by the
   current step.
2. Restore a green tree **before** new feature work: check the latest
   GitHub Actions run of `build.yml` on `main` (CI is the test runner; see
   AGENTS.md golden rule 1). If it failed, fix or revert the half-finished
   step listed under **In progress** below, push, and wait for green.
   Never stack new work on a red tree.
3. Continue with the first unchecked step. Update **In progress** first.
4. When a step completes: tick it, add a dated line to the **Log**, and note
   anything surprising under **Decisions & findings**.

Useful commands (details in `README.md`):

| Purpose | Command |
|---|---|
| Everything green? | the latest `build.yml` run on `main` (`tool/check.sh` reproduces the gate) |
| Regenerate drift code | `tool/codegen.sh` |
| Run the Hub locally | `tool/dev_hub.sh` |
| Run the app (web / linux) | `cd apps/dearth_app && flutter run -d chrome` / `-d linux` |
| Build all host-buildable targets | `tool/build_all.sh` (CI builds iOS/macOS/Windows too) |
| Web E2E (Playwright, 4 viewports) | `tool/e2e.sh` (`SKIP_BUILD=1` reuses the web build) |
| Web DB runtime (sqlite3.wasm, drift worker) | `tool/web_assets.sh` |
| App icons from the SVG source | `tool/icons/make_icons.sh` |
| Set up, check or update the kitchen frame | `tool/deploy_frame.sh 10.0.1.148` (`--check` changes nothing; `--help`) |

## In progress

- In progress (owner request 2026-10-08, chained by the owner: each green, committed and deployed, one report at the end): a second set of number and letter games built on the most-played ones (Who Has More?, Number Tracing, Sight Words, Tallies, Feed the Monster, Build-a-Creature): Cookie Count ✅ (2026-10-08), Letter Monster, Bus Stop, Word Pop, Rocket Countdown, Alphabet Train, Number Fishing, Letter Creatures; then a "Toybox only, offline" first-run mode in the main app (the owner chose it over a second APK).
- Done: 6.2 Toybox (owner request: the toybox and all of its games). Done: the launch set (10 games), the expansion set's first batch (8 games without voice), its voice games (Letter Sounds, Rhyme Time, I Spy, Letter & Name Tracing, Number Tracing, Breathing Buddy) with 513 Piper clips, Build-a-Creature, Dot-to-Dot, Big & Little Letters, Frog Hop, Word Builder, Hear the Sound, Sight Words, Banana Balance, Who Has More?, Name Zoo, Tallies, Hundred Square, Freeze Dance, Music Sequencer, Weather Dress-Up, Who's That? and Story Time: the whole expansion set. Owner request (2026-10-04): many number and letter games (3–6), all in SPEC (FR-TOY-03, Appendix B), built one at a time and each deployed to the frame (owner's rule: finish, deploy, stop): Dot-to-Dot ✅ (2026-10-05), Big & Little Letters ✅ (2026-10-05), Frog Hop ✅ (2026-10-06), Word Builder ✅ (2026-10-06), Hear the Sound ✅ (2026-10-06), Sight Words ✅ (2026-10-06), Banana Balance ✅ (2026-10-06), Who Has More? ✅ (2026-10-07), Name Zoo ✅ (2026-10-07), Tallies ✅ (2026-10-07), Hundred Square ✅ (2026-10-07), Freeze Dance ✅ (2026-10-07), Music Sequencer ✅ (2026-10-07), Weather Dress-Up ✅ (2026-10-07), Who's That? ✅ (2026-10-08), Story Time ✅ (2026-10-08): every planned game is built. Later: Toddler Lock (§9.3), Memory Match's family faces, saving paintings to a gallery (with the Proud wall, FR-KID-19). The owner should listen to the letter sounds on the frame (`tool/sounds/voice.py letter_b …` remakes single clips).
- Owner decisions (2026-10-04), in this order: (1) bundled catalog recipes get TheMealDB photos, shown when online (matched meals' image URLs; the Hub proxies them); (2) list sync goes to **Google Tasks** (two-way, to-do and shopping lists, over the Hub's Google connection; Keep has no API for personal accounts); (3) the Toybox expansion set, all 20 games, with letter, rhyme and I-Spy voices pre-generated offline by Piper (public-domain LJSpeech voice) and bundled (the frame has no TTS); Story Time uses family recordings.
- Done (2026-10-05, owner request): more free recipe sources, aggregated and normalized into one list on every search (FR-RCP-01, FR-RCP-13, §13.6; Settings → Recipes). The owner should add the RecipeAPI.io and RapidAPI (Tasty) keys there, then re-record those two fixtures from real responses (`packages/dearth_integrations/test/fixtures/recipeapi_search.json`, `tasty_list.json` follow the documented shapes).
- Done (2026-10-08): the family Google calendar offer (FR-CAL-04) and the Google reminders mapping on the Hub (FR-CAL-20, §13.2). The owner's Google project needs `calendar.app.created` and `calendar.acls` on its consent screen before accepting the offer.
- Next: Nager.Date holidays for other countries (FR-CAL-18), or 3.2 Android platform channel (FreeKiosk bridge, light sensor, a "setting the time…" state until the frame's clock syncs), 7.1 perf script. 6.3 Music box is **deferred** (owner, 2026-10-05): skip it until the owner brings it back.
- Then: 3.2 Android platform channel (FreeKiosk bridge, light sensor, a "setting the time…" state until the frame's clock syncs), 7.1 perf script.

## Plan & status

Milestones refer to `SPEC.md` §17. ✅ done · 🟡 partial · ⬜ not started · ⏸ deferred.

### Phase 1 — Foundations
- ✅ 1.1 Workspace scaffold: pub workspace, app (android/ios/web/linux/macos/windows), hub, core, integrations, ui; git init; LICENSE; lint config
- ✅ 1.2 PROGRESS.md, AGENTS.md, tool/check.sh, tool/codegen.sh, README.md (first version; final pass in 8.2)
- ✅ 1.3 dearth_core: ids, LocalDate/time, HLC, ops, merge, wire protocol + tests
- ✅ 1.4 dearth_core: drift schema (all tables), SyncStore (+ `applyOpsBulk`, batched `replaceAll`), Mutator + tests
- ✅ 1.5 dearth_core: calendar domain (recurrence, layout, quick-add, icons), solar, moon, weather model, palette + tests
- ✅ 1.6 dearth_core: recipes (parser, units, KB, scaling, consolidation, scoring), kids (schedules, ledger), PIN hashing + tests

### Phase 2 — Integrations & Hub
- ✅ 2.1 dearth_integrations: http abstraction, weather (Open-Meteo, NWS, WU, merge), recipes (TheMealDB, Spoonacular, URL import), ICS, Google OAuth + Calendar, photos (Amazon share, Immich, Google Picker), music (YouTube oEmbed, Spotify) + fixture tests
- ✅ 2.2 dearth_hub: config, storage, auth & pairing, sync WebSocket, snapshot, blobs + variants, admin API, OAuth endpoints, jobs, static web + tests
- ✅ 2.3 Docker image + compose files (image builds, healthcheck green, demo seeds; 411 MB — slimming is a follow-up)

### Phase 3 — App foundations
- ✅ 3.1 dearth_ui: tokens, themes (Light/Evening/Night), display classes, uiScale, tiers, components (pressable, buttons, chips, avatar, emoji, segmented, stepper, sheets, dialogs, toasts, banners, empty states, PIN pad, text field, hold-to-activate), charts + tests
- ✅ 3.3 Playwright E2E harness (`e2e/`): test Hub (fake providers, auto-approve, temp data dir), 4 viewport projects, `tid()` ids, `?e2e=1` semantics, journey specs (onboarding, pairing, home, calendar, lists, weather, photo frame, settings/PIN, kiosk, two-device sync)
- 🟡 3.2 App core: ✅ device DB (native isolate / web wasm worker), sync client (bootstrap, bulk apply, outbox, repair, backoff, commands, telemetry), session + pairing onboarding, demo mode, router + adaptive shell (rail / bottom bar / phone bar, keep-alive budget), grown-up mode (PIN, relock, lockout), kiosk hold gesture → PIN → kiosk menu, idle engine + display modes (screensaver, night), toasts, global error handling, wake lock, orientation per display (`app.dearth/display` channel: walls follow the accelerometer, phones keep their rotation lock, Settings → This display), immersive system bars on walls · ⬜ FreeKiosk bridge, light sensor, brightness, corner-sequence step of the exit gesture, frame-stat telemetry

### Phase 4 — M1 features
_Every feature step below ships with unit tests **and** its Playwright journey specs._
- ✅ 4.1 Home dashboard (Wall-L 3 columns, tablet 2 columns, Wall-P stacked, phone Today) + widgets: header (date/clock/weather/alerts/sync/lock), agenda + now-line, up next + conflicts, week strip, notes & countdowns, dinner, kids' chores, shopping
- 🟡 4.2 Calendar: ✅ day / 3-day / week / month / agenda, person filters, event sheet, full editor with recurring scopes (this / following / all), quick add with preview, countdowns, auto + learned icons · ✅ M2: People view (lanes per person, Family lane, 1 or 3 days), long-press drag to move and bottom-edge resize (15-min snaps, haptics, edge auto-scroll, scope for repeating events, Undo, grown-up gated), weather on events (agenda, grid, sheet), reminders (editor field, per-calendar defaults, on-display banner that talks to kids by name, chime, fired once per device), birthdays & holidays (read-only virtual calendars: profile birthdays with ages and kid countdowns, bundled US/CA/GB public holidays with observed days, family observances, country from the time zone, duplicates of real events hidden) · ✅ family Google calendar offer (FR-CAL-04: Settings → Calendars; the Hub makes, shares and defaults it, moving the Hub's own Family events in), Google reminders both ways (popups ↔ leads, "use default" follows the calendar's wall default, all-day 8 h shift, email reminders kept), "this event" edits pushed as Google instance exceptions · ⬜ Nager.Date holidays for other countries · ✅ M3: kid timeline (a picture day per kid in morning/afternoon/evening bands, the sun or moon at now, done ticks, events + routines + dinner, a Timeline view in the calendar and "My day" on the Kids screen, tap for a big picture card; routines start from it)
- ✅ 4.3 Weather screen (now, 36 h chart with rain/sun/UV bands, rain summary, 10 days, sun & moon, what to wear, alerts, sources)
- 🟡 4.4 Photos: ✅ curation grid (favorite/hide), screensaver (crossfade, portrait pairing, Hub pre-blur, precache, overlays with drift, long-press options, painted art-pack fallback), night clock · ⬜ verified against real Amazon/folder sources on the Hub
- 🟡 4.5 Settings: ✅ household (location search, units, week start, clock), people (colors, roles, stages, buddies, PINs), this display (theme, size, distance, idle, night, role, tier), calendars (enable, default, ICS subscribe, Google connect incl. paste-back), photo frame & night, Hub & devices (status, approvals, enrollment codes, disconnect), about · ⬜ weather/recipe/integration keys page, diagnostics

### Phase 5 — M2 features
- 🟡 5.1 Meals: ✅ aggregated recipe search (FR-RCP-13, owner request 2026-10-05): every search asks every free source at once (TheMealDB, Wikibooks Cookbook, Racion; RecipeAPI.io, Tasty and Spoonacular with free keys) and blends one list (one shape, the same dish merged with "also on", best fit first, sources taking turns), quotas spread over the month and kept across restarts, Settings → Recipes for switches and keys · ✅ week planner (grid on landscape, day list on portrait/phone; recipes or free text; per-entry servings; remove with undo), recipe sheet (servings scaling with friendly fractions, US/metric, add to plan, add ingredients to list, save to box, per-person face ratings), slot picker (search, "Pairs with your plan" with explanations, box, quick weeknights, Leftovers/Eat out/Takeout), Discover (search, pairs, quick, favorites, popular, Surprise me; Hub API or bundled catalog), recipe box (+ URL import on a Hub; family recipes written or edited in the app, FR-RCP-01, 2026-10-07), cook mode (one step at a time, detected timers, step ingredients, keeps the display awake), week → shopping list (consolidated, sources, staples skipped), Home dinner card opens tonight's recipe · ⬜ templates / copy last week (FR-MEAL-04), leftovers links (FR-MEAL-03), per-period shopping view with check state (FR-SHOP-02..05), allergen/diet filters, cuisine passport, seasonal & "haven't had in a while" feeds, drag to move
- 🟡 5.2 Lists ✅ (FR-LIST-01, aisle grouping for shopping, undo; FR-LIST-03 Google Tasks sync) · notes (display only) · ✅ kitchen timers (FR-TMR-01/02: named, presets + custom, synced so every display rings, floating pill on every screen, ring countdowns with pause / +1 min / cancel, a chime that grows louder, wakes the screensaver, cook-mode steps start them)

### Phase 6 — M3 features
- 🟡 6.1 Kids: ✅ Kids destination (a tab per kid + Grown-ups), stage-aware chart of big picture cards, "I did it!" with celebrations (confetti / stars / bubbles, buddy, praise; calm at night; reduced-motion variant), Undo for 30 s, grown-up approvals behind the PIN, grants on the append-only ledger with stable ids (idempotent, converge across devices; undo appends reversals), reward jar with a surprise reveal, star bank with a pinned goal and redemption requests, sticker book (pick and place on painted theme scenes, pages), routine run mode (stepping-stone path, visual timer, debounced steps, progress saved), grown-ups' household chores (claim Anyone chores), family team goal, Settings → Kids & chores (chore editor with who/schedule/time/rewards/approval/voice line, age-sorted chore library, routine editor from templates with steps/timers/reorder, reward editor from ideas, jar size, sticker theme and star goal per kid) · ⬜ voice prompts / TTS playback, First–Then and choice boards, kindness hearts, growing garden, potty chart, proud wall, feelings check-in, adult rotation / fairness, approval notifications
- 🟡 6.2 Toybox: ✅ core rules (catalog, adaptive difficulty FR-TOY-04, time budget and hours FR-TOY-05, launch-set rounds and results), game sounds, CC0 animal recordings, launcher (FR-TOY-01: picture tiles by age, "new!" sparkle, time left, grown-up corner), game host (levels, volume cap, two-minute warning, "the Toybox is sleeping"), parent controls (FR-TOY-05: time, hours, volume, per-kid game switches incl. opening a game early, level pins), the launch set (FR-TOY-02): Bubble Pop, Paint Studio (brush, crayon, marker, spray, rainbow; stamps and scenes at level 2, mirror at 3; undo, new sheet), Magic Coloring (16 code-drawn pictures, 4 → 26 parts), Animal Farm, Shape Sorter (rotated holes at the top), Xylophone & Drums, Jigsaw (family photos or the art pack, 2 → 24 tabbed pieces), Memory Match (2 → 12 pairs), Feed the Monster (color → shape/kind → two at once), Counting Garden (1–3 → 1–10 → flashes) · ✅ expansion set, first batch (FR-TOY-03): Patterns (AB → AAB → ABC → growing towers), Odd One Out (color → shape → kind → use), Shadow Match (2 → 6, look-alike families), Small to Big (3 → 6 sizes), Finger Mazes (3×2 → 7×5 perfect mazes), What Happens Next (3 → 5 cards), Picture Sudoku (1 → 6 blanks, unique answers), Spot the Difference (3 → 7, subtle later) · ✅ the voice games (FR-TOY-03): bundled Piper clips (`tool/sounds/voice.py`, lines from `toybox/voice.dart`; letter sounds as phonemes), Letter Sounds (hear → find the letter → first sound, Montessori colors), Rhyme Time (19 rhyme families, 2 → 4 choices), I Spy (colors → shapes → letters), Letter & Name Tracing (ball-and-stick glyphs for A–Z, a–z, 0–9 in stroke order; lines → curves → capitals → her name), Number Tracing (1–3 → 0–9, then counted out), Breathing Buddy (3 → 5 breaths, no cheering) · ✅ Build-a-Creature (FR-TOY-03: body and face → top and legs → arms and tail, 4 → 8 paints, every pick named aloud, 36 silly names it says while it dances; painted in code) · ✅ Dot-to-Dot (FR-TOY-03: 1→5 … 1→20, A→M, A→Z on 15 code-drawn outlines; tap or draw through the dots, each says its number or letter over a rising xylophone note, the line follows the true outline; a wrong dot says which to find, a golden ring after two slips or 9 s; the finished picture fills in and comes alive) · ✅ Big & Little Letters, Frog Hop · ✅ Word Builder (FR-TOY-03: a movable alphabet; the picture's word as slots, small-letter sound tiles to tap or drag into the glowing slot left to right; first letter missing → last → all three → four-letter words; the voice reads it back sound by sound, the letters close up and it says the word) · ✅ Hear the Sound (FR-TOY-03: a parrot says a sound alone; she taps the letter that makes it; easy sounds → more → look-alike pairs → sh, ch, th) · ✅ Sight Words (FR-TOY-03: street signs with Dolch words; the bus stops at the one she finds; 2 → 3 → 4 letters → two-word labels) · ✅ Banana Balance (FR-TOY-03: a see-saw tips toward the side with more; piles → pile vs. numeral → two numerals) · ✅ Who Has More? (FR-TOY-03: numbered double-decker buses; the one with more or fewer kids, then three lined up fewest first; the kids fill the windows ten to a deck as the answer) · ✅ Name Zoo (FR-TOY-03: the animal at the gate needs a name card; the voice spells her own name, then the family's; at the top she builds a short name from tiles) · ✅ Tallies (FR-TOY-03: a chalk mark per bunny, the fifth crossing the four; counting on from five; reading a tally) · ✅ Hundred Square (FR-TOY-03: find a number on 1 → 2 → 10 rows, the row lights; hidden numbers to place) · ✅ Freeze Dance (FR-TOY-03: dance to the app's own loop, freeze in ice when it stops; uneven pauses; animal dances) · ✅ Music Sequencer (FR-TOY-03: animal rows × steps, a looping playhead, 4×2 → 8×4) · ✅ Weather Dress-Up (FR-TOY-03: dress Buddy for the real forecast; top → top and shoes → whole outfit) · ✅ Who's That? (FR-TOY-03: the family's own faces, from photos picked in Settings → People; "Where's Grandma?"; 2 → 4 → 6 faces; shown once two people have faces) · ✅ Story Time (FR-TOY-03: nine picture books read aloud by Piper, 4 → 6 → 8 pages; painted scenes of tappable picture words; the sentence printed big) · ✅ second set (FR-TOY-03, 2026-10-08): Cookie Count (the purple monster asks for a number of cookies; jar → ten-frame plate → bell; spots → no spots → 5–10 → a plate that starts too full or too empty) · ⬜ Toddler Lock (§9.3), Memory Match family faces, save paintings to a gallery, skills report (FR-TOY-06)
- ⏸ 6.3 Music box: tiles, local files, YouTube, Spotify (via Hub). Deferred by the owner (2026-10-05).

### Phase 7 — Deployment tooling & CI
- 🟡 7.1 ✅ tool/build_all.sh, tool/web_assets.sh, tool/e2e.sh, tool/icons/make_icons.sh, tool/deploy_frame.sh (ADB over LAN: FreeKiosk pinned + Device Owner + HOME, External App mode locked to Dearth, magic corner + PIN, auto-rotate, adaptive brightness, Doze exemptions, JT215M preset, Dearth APK per ABI from a release / file / local build, `--check`, `--reboot` verification) · ⬜ Hub pairing and the FreeKiosk REST key handoff in deploy_frame.sh, tool/perf_gate.sh, a stable release signing key in CI
- ✅ 7.2 GitHub Actions (`.github/workflows/build.yml`): analyze + unit tests, Playwright E2E, Android APKs, web, Linux, Windows, macOS, iOS (unsigned), Hub binaries (4 targets), multi-arch Hub image on GHCR, GitHub release on every push to main

### Phase 8 — Verification
- ⬜ 8.1 All packages analyze clean + unit tests green + full Playwright suite green (all viewport projects); web, linux, APK (armeabi-v7a + arm64) build; Hub + web app end-to-end smoke
- ⬜ 8.2 README final pass

## Decisions & findings

- **2026-10-02** Admin password + device tokens: PBKDF2-HMAC-SHA256 / SHA-256 hashes (cryptography pkg). Profile PINs will use PBKDF2 on devices (spec said Argon2id; PBKDF2 is available everywhere incl. web — revisit if needed).
- **2026-10-02** Row-level scoping (private lists, per-calendar visible roles) is table-level only for v1: kid_room devices get `kidVisible` tables. Tracked as a follow-up.
- **2026-10-02** Postgres (`DEARTH_DB_URL`) not wired yet: SyncStore uses `?` placeholders; drift_postgres needs `$n`. Follow-up: dialect-aware SQL in SyncStore + PgDatabase executor.

- **2026-10-02** Append-only rows use **first-writer-wins (lowest HLC)**,
  not "ignore if present": the latter is arrival-order dependent and broke
  convergence. Field clocks are encoded canonically (sorted keys).

- **2026-10-02** Android `applicationId` = `app.dearth` (changeable before the
  first install on a frame; FreeKiosk targets it). Dart package names keep
  the `dearth_*` prefix.
- **2026-10-02** FreeKiosk v2.0.0-beta.4 exit options are: tap-anywhere,
  hidden corner button (2–20 taps within a timeout), Volume-Up ×5, and a
  numeric or alphanumeric PIN. Its `MainActivity` is exported and accepts
  `voluntaryReturn`/`navigateToPin` extras, so **Dearth owns the complex
  exit gesture** (hold clock 3 s → corner sequence → Dearth PIN → kiosk
  menu → FreeKiosk PIN). FreeKiosk's own trigger is hardened to an
  invisible 48 dp corner button needing 20 fast taps (fallback only).
- **2026-10-02** (owner request) Thorough unit tests + complete Playwright
  E2E on the web build are required (SPEC §16.1). Selectors use
  `flt-semantics-identifier` from `Semantics(identifier:)`; the app forces
  semantics on with `?e2e=1`. Native-only behavior keeps a small on-device
  smoke test.
- **2026-10-02** iOS/macOS/Windows cannot be built on this Linux host; their
  runners are generated and CI builds them on macOS/Windows runners.

- **2026-10-03** Flutter 3.47 decoupled Material into `package:material_ui`;
  go_router 18 only recognizes material_ui's `MaterialApp`, so the app and
  dearth_ui import `package:material_ui/material_ui.dart`, never
  `package:flutter/material.dart`.
- **2026-10-03** `DTheme` exposes the type scale as `text`, not `type`:
  `ThemeExtension.type` is the extension lookup key, and overriding it made
  `DTheme.of(context)` fail.
- **2026-10-03** Web database = drift_flutter (sqlite3.wasm + drift worker,
  OPFS or shared IndexedDB). Every statement is a round trip to the worker and
  queues behind busy frames (~450 ms/op seen while a spinner animated), so bulk
  writes go through `SyncStore.applyOpsBulk` (one read per table + one batched
  write; proven equal to sequential `applyOp` by a 200-seed test) and
  `replaceAll` is a single batch. Mutator, sync catch-up, bootstrap replays and
  wipes all use batches.
- **2026-10-03** Device token at rest: Keystore/Keychain on Android/iOS; the
  app-private database elsewhere (LAN web over http has no WebCrypto; Linux
  kiosks rarely run an unlocked keyring). SPEC §9.2 updated.
- **2026-10-03** Android allows cleartext HTTP (network security config): the
  Hub's LAN address is chosen at pairing time, so it can't be pinned in the
  manifest. SPEC §9.4 updated.
- **2026-10-03** Every build includes **demo mode** (a seeded local household,
  `?demo=1` on web): release artifacts are explorable without a Hub.
- **2026-10-03** E2E with Flutter web semantics: empty container nodes can
  overlap targets, so specs tap through `tap()` (force click at the centre;
  Flutter hit-tests), read text with `expectText()` (aria-label or text), and
  bring lazily built list items into the tree with `scrollTo()`.
- **2026-10-03** The screensaver's offline fallback "art pack" is painted in
  code (8 landscapes) instead of bundled images.
- **2026-10-03** App icon source: `tool/icons/dearth_icon.svg`, rendered for
  every platform by `tool/icons/make_icons.sh`.
- **2026-10-03** Git LFS tracks all binaries (`.gitattributes`); CI caches LFS
  objects to save bandwidth. Releases: every push to main is tagged
  `v<pubspec version>-build.<run>`.
- **2026-10-03** CI: Hub binaries build with the Dart SDK alone (Flutter has no
  linux-arm64 host build); the Hub image builds per arch on native runners
  (`ubuntu-24.04-arm`, no QEMU) and is merged by digest; the release job
  downloads artifacts by name (buildx `.dockerbuild` records break a blanket
  download-artifact). The repo is public, so arm64 runners are free.
- **2026-10-03** Follow-up: actions run on Node 20 majors (`checkout@v4`,
  `*-artifact@v4`, `cache@v4`, docker `@v3/@v6`…) that GitHub forces onto
  Node 24; upgrade majors (checkout v7, download-artifact v8, upload-artifact
  v7, cache v6, setup-java v6, setup-node v7, docker v4/v7, gh-release v3) in a
  dedicated change and watch one run.
- **2026-10-03** Meals: planning a provider recipe copies it into `recipes`
  under `stableId('recipe', [source, sourceId])` (the demo seed's ids), so a
  plan survives the provider and offline devices converge. Ratings are one
  row per person per recipe (`stableId('rating', …)`), scored 2/1/0/−2 so
  they add straight into plan scoring.
- **2026-10-03** Riverpod 3 pauses unlistened providers: reading a
  StreamProvider's `.future` from a handler hung "Add to list". Handlers
  read once from the DB instead (AGENTS.md → Style).
- **2026-10-03** Kids ledger: a grant's id is `grantLedgerId(ref, id,
  currency, n)` with `n` = earlier entries for that ref and currency, so two
  devices granting one completion offline write the same insert-only row,
  and a redo after an undo gets a fresh row. Undo appends reversals (rule 4).
  Stickers to place = earned − placed (placing never deducts: FR-KID-21).
- **2026-10-03** Text above the Navigator (toast host) or in raw overlay
  entries needs a `Material(type: transparency)` ancestor, or Flutter draws
  its yellow debug underline. A `GestureDetector` inside a `tid` forms its own
  semantics node and drops the id: use `excludeFromSemantics: true` when
  the gesture needs a pointer position anyway.
- **2026-10-03** The display layer (screensaver, night clock) renders in
  `AppFrame`, above the app's Navigator, while the app sits offstage under
  `TickerMode(enabled: false)`. Consequences: it needs its own
  `Material(type: transparency)` (the yellow underline on the screensaver
  clock), its own Navigator for sheets (the long-press photo options could
  never open), and it must *listen* to what it shows: Riverpod 3 pauses the
  subscriptions of consumers under a disabled TickerMode, so a `ref.read`
  of the photo pool could be empty or stale. `expectNoFallbackText()` in
  `test/support/app_harness.dart` catches fallback-styled text in widget
  tests.
- **2026-10-03** Sound: `lib/core/synth.dart` synthesizes every effect
  (bell and mallet partials → 16-bit WAV), so there are no audio assets.
  Native platforms play them through flutter_soloud (lazy engine start,
  1024-frame buffer ≈ 23 ms; Xiph codecs off via `hooks.user_defines` in
  the workspace pubspec); the web uses WebAudio directly, so pages load no
  extra WASM. S10 (latency on the frame) is still to measure.
- **2026-10-03** Reminders: `events.reminders` is an explicit list of
  minutes. Calendar defaults (`calendar.reminders` setting) prefill new
  events (editor and quick add) and apply at runtime only to read-only
  calendars, whose events can't carry their own. All-day events remind at
  8:00. Each device remembers fired keys (`eventId@startMs@lead`) in its kv
  store; a display that was off shows only the latest due lead.
- **2026-10-03** Weather on events uses the household forecast (hourly,
  else daily) for events within 7 days with a location or an outdoor
  keyword. Forecasts for far-away event locations need a Hub job
  (geocode + forecast): follow-up.
- **2026-10-03** Kitchen timers are synced `kitchen_timers` rows that hold
  `started_ms` + `duration_ms` (or `paused_remaining_ms`), never a ticking
  value. Every display derives the countdown and phase itself, so a timer
  started on a phone rings on the wall, and stopping it anywhere stops it
  everywhere. A timer rings for 2 min (chime every 6 s, louder each time),
  then stays "ended" for 30 min. The alarm arms one `Timer` for the next
  end instead of polling, and the pill sits in the shell body, not above
  the Navigator, so it never covers side-sheet buttons.
- **2026-10-03** Birthdays and holidays are *virtual* calendars computed on
  each device (`virtual:birthdays`, `virtual:holidays`), not synced rows.
  Feb 29 birthdays fall on Feb 28 in common years. Holiday rules are
  bundled for US/CA/GB (observed and substitute days, Easter by the
  computus), and the country defaults from the household time zone.
  Holiday ids use a slug of the name, not `hashCode`: the web and the VM
  hash strings differently. A virtual day is hidden when a real all-day
  event duplicates it (the demo's "Ava's birthday"). The Google sync sets
  no `eventTypes` filter, so Google birthday events are not filtered out.
  Other countries subscribe to an ICS holiday calendar; Nager.Date on the
  Hub is a follow-up.
- **2026-10-03** Kitchen frame setup (`tool/deploy_frame.sh`). Findings on
  the JT215M: FreeKiosk never had the SYSTEM_ALERT_WINDOW app-op (Device
  Owner doesn't grant it on this ROM), so its exit overlay never existed and
  no on-screen gesture could leave the kiosk. Tap-anywhere mode would count
  any 5 quick taps in Dearth (a servings stepper), so the way out is an
  invisible 48 dp button in the bottom-right corner, 5 taps in 2 s, then the
  PIN; Dearth keeps that corner clear (`kKioskCornerClearance`, the timer
  pill beside the rail). FreeKiosk's auto-brightness only sets its own
  window, which does nothing behind Dearth, and its brightness management
  forces manual mode: it's off, and Android's adaptive brightness (the ROM
  has a lux curve; the pt3r850 sensor works) dims the panel until Dearth's
  own curve (FR-DSP-02) lands.
- **2026-10-03** The photo frame couldn't be woken by a tap (owner report):
  `DisplayController.wake()` didn't count as activity, so the idle timer
  restarted from the last touch *before* the screensaver, long expired, and
  sent the frame straight back to its photos (the night clock too). Every
  app-level test runs the idle engine off (`e2e`), which hid it;
  `test/display_test.dart` now drives it on a fake clock (`idleClockProvider`).
- **2026-10-03** Kiosk frames: Dearth goes immersive on wall displays (the
  status bar was an empty strip under FreeKiosk's lock task) and asks for
  `fullSensor` orientation. The JT215M ROM restores Android's auto-rotate from
  `persist.sys.autorotation` at every boot (`deploy_frame.sh` sets it), but
  Dearth no longer depends on that switch. The frame has no RTC: it boots at
  1970-01-01 until NTP syncs, which Dearth should show as "setting the time"
  rather than dates and ops stamped in 1970 (follow-up).
- **2026-10-03** Every CI release so far was signed with that runner's
  throwaway debug key (no `ANDROID_KEYSTORE_*` secrets), so no release can
  update another in place: phones and frames must uninstall (data reset)
  between builds. Follow-up for the owner: a release keystore kept outside
  the repo plus the four secrets (README → Android signing); local builds
  pick it up from `apps/dearth_app/android/key.properties` (gitignored).
- **2026-10-03** Flutter web drops a node's `flt-semantics-identifier` when
  its role changes: a `DPressable` whose `onTap` went null for a moment (the
  music toy's echo button while the tune played) stopped being a button,
  and the rebuilt node had no id, so E2E lost it. Keep a `tid`'d control's
  handler non-null (do nothing instead). Same family as `screenTid` above.
- **2026-10-03** Toybox: games are shown by age (Appendix B starting points),
  and a grown-up can switch a game off or open it early per kid
  (`kids.toybox` → `off` / `early` keys `kidId.gameId`). Rounds are
  append-only `game_events`; the ladder (FR-TOY-04) is recomputed from them,
  so it converges across displays with no level table.
- **2026-10-04** Google Tasks list sync (FR-LIST-03, owner's choice):
  `planTaskSync` in dearth_integrations is a pure planner (per item, the
  side that changed last wins; links remember when both sides last
  matched, so the sync never hears its own writes as news; the first round
  links equal words instead of doubling). The Hub's `GoogleTasksJob` keeps
  links in its job state, polls every 3 min (Tasks has no push) and runs at
  once on device edits. The Tasks scope is added by incremental consent
  (`purpose=tasks`); `/api/admin/integrations` reports it per account.
  `sortKeyAfter`/`sortKeyBetween` moved to dearth_core for the Hub.
- **2026-10-04** Bundled recipes show TheMealDB photos of the closest dish
  (owner's choice over bundling photos): `catalogPhotoUrl` in the catalog,
  loaded when online (TheMealDB serves CORS headers, so the web demo shows
  them too; on a Hub they go through `/api/img`). Recipes saved before had
  no `image_url`; the tile finds a catalog recipe's photo by `source_id`.
  Tests stay offline: no remote photos when `AppEnv.e2e`.
- **2026-10-04** Volume on the kitchen frame (owner request). The JT215M's
  first press of a volume button only shows the volume panel; the level
  moves from the second press on. FreeKiosk's "Volume Up 5 times" shortcut
  counts *any* five volume changes within 2 s (`VolumeChangeReceiver`), so a
  few quick presses opened its PIN screen instead of changing the volume.
  `deploy_frame.sh` now turns it off (the magic corner stays). Dearth sets
  the media volume itself on Android (Settings → This display → Sound,
  `getVolume`/`setVolume` on `app.dearth/display`): a wall frame's buttons
  are on its back.
- **2026-10-04** Weather refresh (owner request): every 10 minutes by
  default (5 with a personal weather station), or the household's
  `weather.refresh` choice (5 min to 1 hour, Settings → Household). The
  Auto theme already follows sunrise and sunset at the household location,
  the same place the weather uses; with no location it falls back to
  7:00–19:00.
- **2026-10-04** Emoji on the kitchen frame: its Android 10 system font
  draws Emoji 12 at most (checked against the frame's
  `/system/fonts/NotoColorEmoji.ttf`), so anything newer is an empty box
  there. The Toybox uses Emoji 12 only (a core test guards its catalog;
  Bubble Pop's tile is painted, blueberries left the monster's foods). 23
  other source lines still use Emoji 13+ (chores like 🪥 brush teeth and
  🪴, 🛝 in event icons, 🫙 the reward jar): they need the Fluent Emoji
  assets of SPEC §11.3, or substitutes.
- **2026-10-04** Widget tests that open a Toybox game tapped its launcher
  tile without scrolling. On a phone-sized test screen the tile was below
  the fold, the tap missed (only a warning), and the "lays out at four
  sizes" checks quietly checked the launcher. `openToyboxGame` scrolls the
  tile into view and fails unless the game opened; every voice game did
  lay out once checked for real.
- **2026-10-04** Toybox art is drawn in code, so the app ships no image
  files for it: Magic Coloring's pictures are `Path` regions (each part's
  visible area is the part minus everything above it, computed once), the
  Jigsaw cuts a Hub photo at board size or a painted art-pack scene, and
  Paint Studio bakes finished strokes into one image so a frame only draws
  the stroke in progress. Pieces, cards and shapes each sit in their own
  `RepaintBoundary`, so moving one repaints nothing else.
- **2026-10-03** Follow-ups: bundle a Fluent Emoji subset (SPEC §11.3; web
  currently fetches Noto Color Emoji at runtime), slim the Hub image, Postgres
  backend, weather/recipe key settings UI.
- **2026-10-04** Toybox scroll perf on the kitchen frame (owner report):
  measured with `dumpsys SurfaceFlinger --latency` (HWUI `gfxinfo` sees
  nothing under Flutter) — **14 fps steady while scrolling the game grid**
  (median 71.7 ms, p90 89 ms, zero frames at the 56 Hz cadence; SPEC §12.1
  budget p95 ≤ 17.9 ms). Renderer confirmed **Impeller-GLES** from the
  engine's own log lines (`Using the Impeller rendering backend
  (OpenGLES)` after the denylisted PowerVR Vulkan driver) — present in the
  baseline build too; `gfxinfo`'s `Pipeline=Skia (OpenGL)` describes the
  Android window's HWUI pipeline, not Flutter, and is meaningless for a
  Flutter surface (arm32 armchair diagnosis trap). An `EnableImpeller`
  manifest A/B was moot (engine default already picks Impeller-GLES on the
  frame); flag reverted. The launcher's costs are code-side: one paint
  layer for the whole `SingleChildScrollView`+`Wrap` grid (no per-tile
  `RepaintBoundary`), a press `FadeTransition`/`ScaleTransition` firing at
  every scroll start, blur-8 shadows and gradients on every tile, and the
  tier machinery never engaging (`deviceRamMbProvider` is a stub, ROM
  `ro.config.low_ram=true` ignored → frame runs as T3 with 60 fps caps and
  blurs on). On Impeller (no raster cache), the scroll wins are: kill the
  press layers, blur-free T1 tiles, a lazy `GridView` — `RepaintBoundary`
  still pays on the CPU paint-record side and for isolated animations.
- **2026-10-04** Toybox perf, resolved: implemented all the code suggestions
  (lazy `GridView.builder` launcher with per-tile repaint boundaries,
  `DPressable.pressFeedback` off on tiles, tier-aware `DElevation` (flat
  offset shadows when `policy.blurAllowed` is false), the `getMemory`
  platform channel + `lowRamDevice` wired into `detectTier` (the frame now
  auto-detects t1: 1970 MB, `ro.config.low_ram=true`; a
  `debugPrint` in `perfTierProvider` reports it at startup), the celebration
  gate to `ambientFps` + RepaintBoundary'd center + a cached unit-star Path,
  the four infinite hint pulses driven by gated tickers, and jigsaw's
  shadow without a per-paint `path.shift`) — and the scroll barely moved:
  the raster cost was Impeller re-drawing the whole scene per frame on a
  fill-rate-starved GE8300. Per SPEC §12.2's ladder the frame now ships the
  **Skia opt-out** (`EnableImpeller=false`, application-scoped meta-data):
  grid scroll **14.0 → 56.8 fps** (median 71.7 → 17.6 ms, 85% of frames at
  the 56 Hz cadence). Findings along the way: the tier override lives in
  the `devices.tier_override` column (writing it into the settings JSON is
  silently ignored); `uiautomator` can't see the tier and `screencap` is
  blocked (FreeKiosk sets `disable-screen-capture`), so the SF `--latency`
  triples are the measurement (HWUI `gfxinfo`'s `Pipeline=` line describes
  the Android window, not Flutter); and the `(_frames++).isOdd` ambient
  gates halve the *animation* rate but not the render rate — an active
  `Ticker` keeps Flutter submitting (identical) frames at every vsync, so
  T1 ambient still pays full raster. Follow-up: on T1, drive ambient motion
  with a ~33 ms periodic one-shot instead of a hot ticker, and build
  `tool/perf_gate.sh` to keep both renderers measured (SPEC §12.2).
- **2026-10-05** Renderer decision, final (owner): keep **Impeller-GLES at
  1080p** on the frame and accept the ~14 fps Toybox scroll — the Skia
  opt-out (56.8 fps measured) was installed and then removed in favor of
  the non-deprecated renderer and full-resolution photos/text; the manifest
  carries no renderer flag. Evidence for the eventual revisit: beta
  **3.49.0-0.2.pre** (side SDK in /tmp, pubspec.lock restored) measured
  identical (14.0 fps); Impeller reaches 57.0 fps only at 540p (`wm size`,
  quarter pixels — rejected for photo crispness) and 32.6 at 720p; userScale
  1.6 at 1080p gives 19.1; the GPU has no clock headroom (504 MHz max under
  load, `simple_ondemand`). Also found: at 720p + userScale 1.6 the wall nav
  rail overflows and the Toybox button falls off the bottom — follow-up:
  the rail needs to adapt (or scroll) at large scales/short screens.
- **2026-10-04** Frame stuck on FreeKiosk's "waiting for application": a
  botched `--replace` (throwaway CI keys, 08:49) had uninstalled Dearth's
  files but left a dangling package entry, and the uninstall pruned
  `app.dearth` from the Device Owner lock-task list, so FreeKiosk couldn't
  launch Dearth at all (ActivityManager refuses with a lock-task mode
  violation; a manual `am start` returns "unknown error code 101"). Fixed by
  `pm uninstall app.dearth` + reinstall, then re-sending the FreeKiosk
  settings, which rebuilds the lock-task list. `deploy_frame.sh` now checks
  `/data/system/device_policies.xml` for the entry (root shell) and re-sends
  the settings when it's missing instead of a bare `am start` that lock task
  refuses. Note: the reinstall was the latest GitHub release, so the frame
  lost the morning's local build and its pairing (a known cost of the
  throwaway CI signing keys until the release keystore lands).

- **2026-10-05** Dot-to-Dot's outlines (written blind in the previous
  session) needed a rework once rendered: the "star" was a teardrop (one
  point on a round body), the umbrella's scallops were deep zigzags, the
  whale's tail a spike, and evenly spaced dots missed corners (the ice
  cream's tip) and crowded narrow spots (26 dots on the fish: 16-unit gaps,
  14 px dots on a phone). Now a dot sits on every corner and the others
  split the gaps evenly (`DotGeometry`, cached per picture and count); when
  corners bunch up (a whale's tail at five dots) even steps win. Every
  picture keeps ≥ 60 of 1000 units between dots at every level, so dots are
  ≥ 19 px on a phone and ≥ 46 px on the frame; dot size grows for small
  counts (a tenth of the board at five dots) and never reaches the gap. A
  test pumping 2 s in one frame shows dots that haven't popped away yet:
  implicit animations start in the frame that sees the change, so review
  renders pump in steps.

- **2026-10-05** Recipe sources (owner: free only, keys fine): the
  research (curl, since the web tools were failing) ruled out Edamam (no
  free plan any more; storing forbidden) and API Ninjas (free plan is
  evaluation-only, no storing) and found four that fit: the Wikibooks
  Cookbook (keyless; one MediaWiki request returns hits with their
  wikitext), Racion (keyless; summaries, so each hit is one more request:
  a search looks up four, and its rate-limit headers are obeyed before a
  search starts), RecipeAPI.io and Tasty (free keys, 500 a month each,
  spread over the month by `QuotaBudget`, kept in the Hub's job store).
  Searches go through `searchEverywhere` (dearth_integrations): fan-out
  with a 6 s budget, `tidyRecipe` into one shape, `mergeSameDishes`
  (order-free title words, or close titles plus shared ingredients; never
  within one source), `recipeScore`, `interleaveSources`. "Pairs with your
  plan" skips the metered sources (three ingredient searches would spend a
  tenth of Racion's hour). Attributions are now bare names and the sheet
  says "From X · also on Y" (`recipeCredit`), which also fixes the old
  "From Recipe from TheMealDB". RecipeAPI.io has no photos, so its cards
  rank below equal ones that do.
- **2026-10-06** First schema migration (version 2, `recipe_cache`). Migrations stay additive (SPEC §8.4.5): bump `schemaVersion`, add `if (from < N)` steps in `DearthDb.migration`, and test the upgrade from a file at the old version (`packages/dearth_core/test/schema_test.dart`). Hub-only tables are created on devices too, and stay empty there.
- **2026-10-06** Spoonacular's terms (spoonacular.com/food-api/terms): no storing beyond a recipe's id, title and image, caching an hour at most (with permission), and everything deleted if API use stops. The owner chose to keep its recipes in `recipe_cache` anyway (personal, non-commercial use; the risk is the key being revoked), 2026-10-06.

## Log

- 2026-10-08 — Family Google calendar (FR-CAL-04) and Google reminders (FR-CAL-20): Settings → Calendars offers a shared "Family" calendar once Google is connected (account, who to share with, move the Hub's Family events; an existing "Family" calendar is offered as is; "Not now" tucks it under Add calendars); `POST /api/admin/calendars/google/family` makes it at once or returns a consent URL (`calendar.app.created`, plus `calendar.acls` to share), finished in `_finishGoogle`. Reminders map both ways (`kCalendarReminders` sentinel for `useDefault`; only touched reminders go up, keeping email ones). Fixed on the way: "this event" edits of a Google series were never pushed (now instance patches/cancels), exceptions from Google lost their link to a series made on a display, a full resync could tombstone events not yet pushed, reconnecting Google (e.g. for Tasks) cleared the default calendar, and `Fetcher.postJson` form-encoded every all-string map, so Google push channels (`events.watch`, `channels/stop`) and making a Tasks list never sent JSON (the literals are now typed `<String, Object?>`). Tests: 2 core, 3 integrations, 2 Hub end to end against a fake Calendar API, 2 widget. No E2E journey: the E2E Hub has no Google account to offer it for.
- 2026-10-02 — Scaffolded workspace (step 1.1).
- 2026-10-02 — Core sync foundation: HLC, ops, field-LWW merge, protocol, 40-table drift schema, SyncStore, Mutator; 60-seed convergence property test green (steps 1.3–1.4).
- 2026-10-02 — Calendar/weather/solar domain (recurrence w/ DST + exceptions, layout, quick-add, icons, unified weather model); 112 core tests green (step 1.5).
- 2026-10-02 — Recipes (units, ingredient parser/KB, consolidation, plan-aware scoring, cook-mode timers) + kids (schedules, ledger, libraries); added `anchor_date` to chores/routines; 131 core tests green (step 1.6).
- 2026-10-02 — Integrations: Fetcher (retry/backoff), Open-Meteo/NWS/WU + merge policy + FakeWeather, TheMealDB/Spoonacular(budget)/URL import/24-recipe catalog, ICS parser, Google OAuth+Calendar, Amazon share/Immich/Google Picker, YouTube/Spotify; 32 fixture tests green, recorded real API fixtures (step 2.1).
- 2026-10-02 — Hub: kernel (validation/ACL/idempotent op log/fan-out/snapshots), auth (PBKDF2 admin pw, hashed device tokens, pairing + enrollment codes), WS sessions (catch-up w/ live buffer), blob store (libvips variants, pre-blur, image proxy), jobs (weather, ICS, Google two-way, photos, maintenance), routes (core/feature/admin/OAuth/webhooks), static web host; 8 in-process integration tests green (step 2.2).
- 2026-10-03 — Fixed a red tree (lint + a `ThemeExtension.type` shadowing bug); verified the Hub image (step 2.3).
- 2026-10-03 — dearth_ui component library + 16 widget/token tests incl. WCAG AA contrast checks (step 3.1).
- 2026-10-03 — App core: drift DB (native + web), sync client with bulk apply, pairing onboarding, demo mode, adaptive shell, grown-up PIN mode, kiosk gesture, display modes, error handling (step 3.2, partial).
- 2026-10-03 — Home, Calendar (5 views, editor with recurring scopes, quick add), Weather, Lists, Photos + screensaver, Settings; 10 FR-CAL-13 tests, 6 sync-client tests against an in-process Hub, app flow test (steps 4.x, 5.2).
- 2026-10-03 — `SyncStore.applyOpsBulk` + batched `replaceAll`; 200-seed equivalence test; 341 core tests green.
- 2026-10-03 — Playwright E2E suite (4 projects) against a test Hub; app icons; Android/iOS/desktop identity (`app.dearth`); CI/CD workflow with releases; Git LFS.
- 2026-10-04 — `skills/toybox-game/`: a checked-in playbook for adding a Toybox game (design for pre-readers, core rules, voice clips and their pronunciation traps, code-drawn art, speed on the frame, ids and labels, tests, docs, ship), with `check_game.py` (is a game wired in everywhere?), `phonemes.py` (how the voice will read a line) and a screenshot test template; AGENTS.md points to it. SPEC: four number and letter games (Dot-to-Dot, Big & Little Letters, Frog Hop, Word Builder; FR-TOY-03, Appendix B).
- 2026-10-04 — Build-a-Creature: 6 parts × 5–6 options drawn in code (part buttons zoom on their part; body outlines cached, so a dance frame unions nothing), 79 new Piper clips (names, parts, paints, hello). 4 core tests, 7 widget tests (incl. layout at four sizes), 1 E2E journey × 4 viewports. Test harness: `openToyboxGame` now scrolls to the tile and fails unless the game opened (small-screen layout checks used to look at the launcher).
- 2026-10-04 — Toybox voice games: 6 games and 513 voice clips (Piper, LJSpeech; `tool/sounds/voice.py` keeps an index so only changed lines are remade). 11 core tests (words, rounds, glyphs, tracer, voice lines); 15 widget tests incl. a layout check at four screen sizes and a clip-per-line guard; 6 E2E journeys × 4 viewports (tracing drags through on-screen waypoints). Host: `finishRound(calm: true)` skips the cheer; finished rounds always record.
- 2026-10-04 — Toybox expansion, first batch: 8 games without voice (rules in `toybox/expansion.dart`, 7 core tests; 10 widget tests; 8 E2E journeys × 4 viewports that play from the screen's labels). Fixed: halo shadows animated a blur when they appeared (lists now keep their shape).
- 2026-10-04 — Google Tasks sync for lists (Settings → Lists); 5 integrations tests, 1 Hub end-to-end test against a fake Tasks API, 1 widget test.
- 2026-10-04 — Recipe photos for the 24 bundled recipes (TheMealDB, matched by eye); 1 integrations test.
- 2026-10-04 — Owner suggestions: on-screen volume (This display → Sound) and FreeKiosk's volume shortcut off in `deploy_frame.sh`; weather every 10 min, configurable per household. Tests: 1 core, 2 widget.
- 2026-10-04 — Toybox launch set complete: Memory Match, Shape Sorter, Counting Garden, Feed the Monster, Magic Coloring (16 code-drawn pictures), Jigsaw (photos or art pack), Paint Studio; games can be opened early per kid; the Toybox keeps to Emoji 12 for the frame. Tests: 19 core toybox, 29 toybox widget, 11 E2E journeys × 4 viewports. Full E2E: 229 passed, 7 skipped; gate green (388 core, 104 app).
- 2026-10-03 — Toybox checkpoint: launcher, game host, Settings → Toybox, Bubble Pop, Animal Farm, Xylophone & Drums; 18 core tests, 7 widget tests, 4 E2E journeys × 4 viewports. Full E2E: 201 passed, 7 skipped.
- 2026-10-03 — Kid timeline (FR-CAL-10: core layout + 5 tests, Timeline view, "My day" on the Kids screen, 2 widget tests, 2 E2E journeys); fixed the photo frame that a tap couldn't wake (2 idle-engine tests); immersive bars and accelerometer orientation on wall displays (3 tests); routine run mode no longer changes providers mid-build.
- 2026-10-03 — `tool/deploy_frame.sh`: sets up, checks or updates an Android wall display over network ADB; the kitchen frame now has a working exit corner, auto-rotate, adaptive brightness and the current Dearth. README section for it.
- 2026-10-03 — Kitchen timers (synced, pill on every screen, escalating chime, cook mode) and birthdays & holidays (virtual calendars, US/CA/GB rules, kid countdowns). Tests: 12 new core, 3 new app; E2E journeys for timers, holidays on the calendar and holiday countdowns.
- 2026-10-03 — Calendar M2: People view, drag to move/resize, weather on events, reminders with banners and a synthesized chime (flutter_soloud native, WebAudio on web); toast timers cancel on dispose; event blocks fit their title lines; `tool/build_all.sh` executable again. Tests: 16 new core, 20 new app; E2E journeys for People, drag, forecast, reminders.
- 2026-10-03 — Fixed the screensaver: fallback text style (yellow underline) on the clock and overlays, photo options that could never open, and a photo pool read while paused; screensaver widget tests + shared app test harness. E2E: 149 passed, 7 skipped.
- 2026-10-03 — Kids & chores settings: chore/routine/reward editors, chore library by age, jar/sticker/goal settings; 8 setup unit tests; 4 Playwright journeys × 4 viewports.
- 2026-10-03 — Kids (step 6.1 core): chart, celebrations, approvals, jar, stars, sticker book, routines, grown-ups' chores; 9 kids-op unit tests; 6 Playwright journeys × 4 viewports.
- 2026-10-03 — Meals (step 5.1 core): planner, recipe sheet, slot picker, Discover, recipe box, cook mode, add to list; 8 meal-op unit tests; 9 Playwright journeys × 4 viewports (full suite: 109 passed, 7 skipped).
- 2026-10-03 — Pushed to GitHub; CI run #1 green except the release job (artifact download); fixed → run #2 published `v0.1.0-build.2`.
- 2026-10-04 — Toybox scroll perf (owner report: "kinda choppy"): measured 14 fps on the frame, implemented every suggestion (lazy launcher grid, no press layers on tiles, tier-wired DElevation + platform memory channel, gated celebrations and hint pulses, jigsaw shadow), then took SPEC §12.2's ladder to its end: the frame ships the Skia opt-out, 14.0 → 56.8 fps. Tests: 139 app widget tests green (harness scrolls the lazy grid with `dragUntilVisible`), 1 new tier token test, 104 Toybox E2E journeys × 4 viewports green.
- 2026-10-05 — Flutter beta 3.49.0-0.2.pre built with a side SDK and measured on the frame: Impeller-GLES scroll unchanged (14.0 vs 14.4 fps) — no help, and the Skia opt-out was then removed by owner decision (Impeller @1080p, jank accepted; SPEC §12.2 documents the full evidence matrix). pubspec.lock restored; no tree SDK change.
- 2026-10-05 — Removed the Toybox tile gradients (solid `hue` fill; contrast unchanged — the white title/dots already sat on the `hue` end): frame scroll **14.4 → 45.2 fps** (median 69.4 → 22.1 ms, 39% of frames at the 56 Hz cadence), the single biggest win of the perf work and it keeps Impeller at 1080p. Also measured on the frame for contrast: lists page scrolls at 56.6 fps (light content); weather/discover fit the wall layout without scrolling. 61 toybox tests + 139 app tests + 104 Toybox E2E journeys green.
- 2026-10-05 — Aggregated recipe search over free sources (FR-RCP-01, FR-RCP-13): Wikibooks Cookbook, Racion, RecipeAPI.io and Tasty providers, `QuotaBudget`, `searchEverywhere` (tidy, merge, rank, interleave), Hub switches/keys/quotas and search headers, Settings → Recipes, recipe credits with "also on". Tests: 13 integrations tests (four providers against fixtures, quotas, tidy/merge/rank/interleave, a slow and a failing source left out), 1 core (credits), 1 Hub (fan-out over a fake network, switches, keys never returned, quota counted), 1 widget (Settings → Recipes), 1 E2E journey; gate green (416 core, 52 integrations, 10 Hub, 17 UI, 151 app).
- 2026-10-05 — Dot-to-Dot (FR-TOY-03): the game, 15 reworked outlines with corner-first dots, finished pictures painted in code that come alive (twinkle, beat, smoke, swim, spout, flap, blink, rain, wheels, sprinkles), a painted launcher tile; no new clips (numbers, find-the-number/letter, picture names were made with the rules). Tests: 11 widget tests (geometry for 15 pictures × 6 levels × 4 board sizes; a play-through with clips and climbing notes; slips and the hint ring; drawing through the dots in one stroke; re-touching a joined dot; letters; the idle hint; layout at four sizes × 3 levels), 1 E2E journey × 4 viewports (all 108 Toybox journeys green); gate green (415 core, 39 integrations, 9 Hub, 17 UI, 150 app).
- 2026-10-05 — Smaller Toybox tiles (owner request: "maybe 6 across and keep them square"): square tiles about 190 dp × scale, six at most, so six across on the frame in landscape (~255 dp, was 5 at ~310), four in portrait, two on a phone, six on a landscape phone (two rows visible instead of one). Titles keep their size relative to the tile and shrink a little to fit rather than being cut off (portrait walls and phones used to show "Xylophone & …", "Letter & Name…"). SPEC FR-TOY-01 and the launcher wireframe updated.
- 2026-10-03 — E2E run 2: 69 passed, 4 failed (quick-add preview had no readable text node; fixed by labeling the summary node), 7 skipped by design. README written (screenshots in `docs/images`, LFS).
- 2026-10-04 — Kitchen frame stuck on FreeKiosk's "waiting for application": cleared a dangling `app.dearth` package entry (the APK dir was gone), reinstalled v0.1.0-build.6, rebuilt the pruned lock-task list via a FreeKiosk config push; `deploy_frame.sh` detects and repairs that state now. `--check` all green, Dearth in front.
- 2026-10-04 — Frame showed an empty status-bar strip on top of build.6 (immersive mode landed after build.6, and this ROM's status bar survives lock task). Fixed live via `settings global policy_control immersive.full=app.dearth` and the same line went into `deploy_frame.sh`, so any build goes full screen on the frame; `--check` green. Note: the good news from the repair — the dangling-entry uninstall left `/data/data/app.dearth` in place, so the reinstalled app kept its pairing.

- 2026-10-05 — CI red since the Amazon group-share commit (`_isContainer` never defined): fixed, with a group-share test. CI is now the test runner (AGENTS rule 1) and a new push cancels the running build.
- 2026-10-05 — Owner: the voice was too fast and unclear on the frame's speaker. All 639 clips remade slower (length 1.1 → 1.3), crisper (noise 0.667 → 0.5), shaped for a small speaker (high-pass 150 Hz, +5 dB at 3 kHz, light compression), 2 dB louder, 48 kbps (6.4 → 7.4 MB). `voice.py` now writes each clip's length to `voice_lengths.g.dart`; `afterVoice(clip)` lets a line finish before the next (letter tracing cut off long letter sounds, Breathing Buddy's welcome was clipped). Number Tracing counts each thing with its own number, 1.3 s apart.
- 2026-10-05 — Big & Little Letters (FR-TOY-03, Appendix B): capitals on cards, small letters on tokens; drag (or tap, then tap) each to its capital and the voice names the pair ("Big C, little c."). Ladder: 3 look-alike pairs → 5 that look different → b, d, p and q; all 26 letters across the levels. A wrong card wiggles and names the held letter; two slips or 12 s idle light the card. 28 new clips (`biglittle_*`); lowercase z now says "zee" too. 3 core tests, 4 widget tests, layout at 4 sizes, an E2E journey.
- 2026-10-06 — Frog Hop (FR-TOY-03, Appendix B): lily pads 0–5, then 0–10, as a number line (across a wide screen, up a tall one); the voice asks "Hop to six!", "One more than four!", "One less than seven!", "Three and two more!" and on the right pad the frog hops there a pad at a time (a rising C-major note per pad, dotted arcs over the water), then says where it landed. A wrong pad wiggles and says its number; two slips or 12 s idle light the pad. 55 new clips (`hop_*`). "one" now says the American "wun" (espeak gave "won"), which remade the 14 clips that say it. 3 core tests, 4 widget tests, layout at 4 sizes, an E2E journey.
- 2026-10-06 — Amazon Photos links from today's app (`…/photos/shared/{groupId}.{secret}`) didn't parse (owner report). They're group share links: reverse-engineered the anonymous read path from Amazon's web app (groups service for the name, `search/groups/{groupId}` with `groupShareToken` and `resourceVersion=V2` for photos, thumbnail service with `groupShareToken` for JPEGs, HEIC included) and verified it live against the owner's link. `/photos/groups/share/` links use it too (cbaa122 had sent them to the share endpoints). Fixture test from the real responses, anonymized. SPEC §13.5.1 updated.
- 2026-10-06 — Owner suggestions: (1) a birthday picks its year from a grid first (year → month → day; an unset one opens 30 years back; no future years; the month title steps out to years in every date picker) and the button shows the year ("March 14, 1985"; it showed only "Thursday, March 14"). (2) Only 150 Amazon photos showed: the Hub fetches 150 per source per run and waited an hour between runs; now it comes back after 20 s while an album has photos left ("adding photos · n of m"), skipping a photo that fails until the hourly run. (3) Photo sources can be removed (Settings → Photo frame → a source → Remove; the Hub tombstones it and its photos in one write), the same album can't be added twice (`photoSourceKey`: one share however its link was copied), duplicates added earlier fold into the copy with the most photos, and a photo in two sources shows once (same blob). Tests: integrations +1, Hub +1, app +2 (picker, dedupe).
- 2026-10-06 — Word Builder (FR-TOY-03, Appendix B): picture, letter slots and a tray of small-letter tiles (Montessori colors, shared baseline so a word reads as one). The voice says the word, then "Which sound is missing?" or "Let's build it, sound by sound!"; each tile says its sound (new `sound_<letter>` clips for 24 letters) and goes into the glowing slot by tap or drag, left to right. Slips: the tile wiggles back; two, or a 12 s pause, light the right tile and say its sound. Done: each letter hops as its sound is said, the letters slide together, the word is said and the picture jumps; extra tiles bow out. 22 three-letter and 12 four-letter words (16 new pictures in `kWords`); extra letters never sound like one in the word or spell another picture. 42 new Piper clips. Tests: core +4 (ladder over 200 seeds, extras, coverage, results), app +5 widget (play-through with clips in order, slips, four letters, drag, idle) + layout at four sizes, E2E +1 journey. The catalog's first game aimed past 4 (54 months).
- 2026-10-06 — Hear the Sound (FR-TOY-03, Appendix B): a parrot asks "Which letter says mmm?" (the sound alone) and repeats the sound when tapped; she taps the small letter that makes it. A wrong letter says its own sound and wiggles; two slips light the answer; a 12 s pause has the parrot ask again. The right one hops, shows its picture and says its letter clip ("M. Muh, muh, monkey."). Ladder: a, m, s, p, t (2 letters) → 12 letters (3, none alike) → a sound beside its look-alike (b/p, d/t, k/g, f/v, m/n) → sh, ch, th together on one tile with the lone first letter as the near miss. 25 new clips (`hear_*`, `sound_sh/ch/th`, `digraph_*`, thumb). Tests: core +3, app +4 widget + layout at four sizes, E2E +1.
- 2026-10-06 — Owner report: Amazon sync stopped after ~440 photos with HTTP 503 from the group search. The 20 s catch-up runs (earlier today) re-listed the whole album every time; now they download from the hour's listing, only the hourly run lists (400 ms between pages), and a busy reply (429/5xx) pauses that source 1 → 2 → … 60 min and stops its batch rather than marking photos failed. Also: the same image saved twice at once (one photo twice in an album) collided on its blob write; concurrent saves of one sha now share a write. Tests: Hub +1 (155-photo album: two batches, one listing; a 503 pauses the source and the next run leaves it alone).
- 2026-10-06 — Sight Words (FR-TOY-03, Appendix B): street signs on posts along a painted road, each word in the Toybox's ball-and-stick print (one letter size per round); the voice asks "Find the word go." and a tapped wrong sign reads itself out; the right one sends a bus along the road to stop under it, then the word is read. 14 two-letter, 16 three-letter, 16 four-letter words (Dolch pre-primer/primer) and 14 two-word labels; decoys tighten (different first letters → a look-alike start → labels sharing a word). Little words read alone are stressed with American vowels (`_sightStressed`: the, is, was…). 120 new clips. Tests: core +3, app +4 widget + layout at four sizes, E2E +1.
- 2026-10-06 — Owner request: cache every recipe pulled from the APIs indefinitely. New Hub-only table `recipe_cache` (schema version 2, the first migration: `createTable` on upgrade, tested from a version-1 file): every recipe from searches, feeds, recommendation lookups and URL imports is upserted (first/last seen kept, data refreshed); a search short of a page fills from remembered recipes that fit (`matchRecipes`, shared with the bundled catalog); recommendations rank everything remembered (the in-memory 2,000-recipe `_seen` map is gone). Spoonacular is left out: its terms allow storing only id, title and image and caching for an hour at most (its search answers now expire after an hour). Tests: core +1 (migration), Hub +1 (kept in the database, found again offline after a restart).
- 2026-10-06 — Owner request: every package and tool to its latest stable, Node to the latest LTS. Flutter 3.47.2 → **3.47.6** (Dart 3.13.2 → 3.13.5; CI, the setup action, the Hub image, the local SDK); pub at the newest this SDK resolves (`flutter_timezone` 5.1.1, `equatable` 3.0.0, `jni_flutter` 1.0.4+1, `test` ^1.31.1; analyzer, test_api, material_color_utilities, qr and package_config are held by the SDK and drift's builder); Node **24 LTS** in CI (`e2e/.nvmrc`, `engines`), TypeScript 7.0.2 (tsconfig to `nodenext`: TS 7 dropped `node10` resolution), `@types/node` 24.19; GitHub Actions to their latest majors (checkout v7, cache v6, upload-artifact v7, download-artifact v8, setup-java v6, setup-node v7, build-push v7, login v4, setup-buildx v4, action-gh-release v3: all moves to the Node 24 runtime); the Hub's runtime image Debian bookworm → **trixie** (13, stable). CI runners pinned to the latest Ubuntu LTS, **26.04** (`ubuntu-26.04`, `ubuntu-26.04-arm`) instead of `ubuntu-latest` (still 24.04 until 2026-10-19); the Linux build installs `g++` (headers for the default GCC) instead of `libstdc++-12-dev`. Not moved: Gradle 9.3.1, Kotlin 2.4.0 and AGP 9.1.0 are Flutter 3.47.6's own supported maxima (`gradle_utils.dart`), newer (9.8.0, 2.4.20, 9.4.1) is outside what the Flutter tool supports. Frame perf gate (SPEC §12.2): Toybox grid scroll 38.5 fps on 3.47.2 → **40.3 fps** on 3.47.6 (median 17.6 ms both; 3 runs each), so the upgrade shipped to the frame. The frame's screen can be read with `uiautomator dump` (Flutter's semantics show up as content-desc nodes with bounds), which is how the measurement reached the Toybox without screenshots.
- 2026-10-06 — Banana Balance (FR-TOY-03, Appendix B): a painted see-saw (stand, plank, plates; a monkey on the pivot) with a pile of bananas or a number card at each end; "Which side has more?" — the side she taps, if heavier, goes down with a springy tip, the monkey hops and the voice says "Five is more than three." (45 pairs); the lighter side wiggles and says its number, then the heavier plate glows. Piles are pyramids (4-3-2-1 wide, 3-3-2-1-1 tall) so ten reads at a glance. Ladder: 1–5 two apart → 1–10 → pile vs. numeral → two numerals. 46 new clips. Tests: core +3, app +4 widget + layout at four sizes, E2E +1.
- 2026-10-06 — Toybox tile colors (owner question: "most of them are blue now"): only the 10 launch-set games had entries in `kGameHues`, so the 22 games added since (expansion set, voice games, number and letter games) fell back to the theme accent (iris `#5B5BD6`) and all came out the same blue. The tiles are navigated by picture and color (FR-TOY-01), so every one of the 32 catalog games now has its own deliberate hue (frog green, banana yellow, sunflower gold, night-sky indigo for Dot-to-Dot's star…) and an app test fails when a catalog game lacks one or two games share. App tests green.
- 2026-10-07 — Who Has More? (FR-TOY-03, Appendix B; game id `compare`, not `more`: the shell's More menu already owns the `more.*` test ids, and a game id is forever, stored in every `game_events` row): painted double-decker buses pull in one after another with a toot, each with its route number on a roof sign in the Toybox's print, and the voice names each number as its bus stops (one clip per bus, then the question). "Which bus has more kids?" (later "fewer"): the windows stay empty until she answers; then the kids pop in, ten to a deck with a door between the fives, so the numeral she compared becomes a quantity she can see (13 is a full lower deck and three upstairs). The voice says the bus's number, then "That bus has more kids!"; the buses drive off and new ones pull in. A wrong bus wiggles and says its number, the kids show and the right bus glows; a pause of 12 s asks again and shows the kids. Ladder: two buses 0–9 at least two apart → 0–20 with a teen on board → more or fewer, mixed → three buses to line up in the bays, fewest first (left to right on a wide screen, top to bottom on a tall one). New `Sfx.honk` (a soft two-tone "beep-beep", synthesized). 6 new clips; numbers reuse `num_0`…`num_20`. Tests: core +3, app +4 widget + layout at four sizes, E2E +1.
- 2026-10-07 — Owner request: "add my own recipe with all of the features of a discovered recipe". The family recipe box (FR-RCP-01) gets an editor: "New recipe" in the box and Edit (pencil) on any recipe sheet. Fields: title, where it's from (own recipes only; a source's keeps its credit), photo from the family photo library or a link (owner's pick: no image-picker plugin), or an emoji picture (an emoji tag, which `RecipeVisual` already draws), servings, prep/cook minutes, course, cuisine, diets and kid-friendly in the search vocabulary (`kRecipeCourses`, `kRecipeDiets`, `kKidFriendlyTag` in core `recipe_text.dart`), ingredients one a line ("For the glaze:" starts a group; bullets dropped) read by the FR-RCP-12 parser with a live preview of amounts and aisles, steps one a line (typed numbers dropped; cook-mode timers counted), tags and notes (the `recipes.notes` column, now shown on the sheet). Saved as a whole row (`saveFamilyRecipeOps`), so it scales, converts, plans, shops, cooks, rates, and is found by search, which now matches the box's tags, diets and ingredients too, not just title, cuisine and course. Editing a source's recipe writes the family's version over the local copy; the recipe sheet now shows the local copy wherever one exists (`familyVersion`), and an unchanged ingredient line keeps the structure its source gave (`parseIngredientsText(before:)`). The sheet shows ingredient groups as headings. Found on the way: the Hub's "Pairs with your plan" never included the family box (FR-RCP-11); it now reads saved recipes from the synced table, the family's version replacing the source's. E2E `scrollTo` wheels over the target's own column when it's built (a wall's side sheet starts near the middle of the screen). Tests: core +3, app +2 unit, Hub +1, E2E +2.
- 2026-10-07 — Name Zoo (FR-TOY-03, Appendix B; game id `zoo`): animals queue at a painted zoo gate (posts, green arch, bunting); the front one holds up an empty name card in a speech bubble. "Find your name!" / "Find the name I spell.": the household's names can't be bundled clips, so the voice spells them with the existing letter-name clips, a letter a beat (`zooSpellClips`), which is the skill anyway. The right card fills the bubble in the Toybox's print (new shared `PrintedWord`), the animal hops, "Thank you!" and walks in through the gate; a wrong card fades and wiggles, the bubble shows the first letter and the name is spelled again; two slips light the card; a 12 s pause asks and spells again. Ladder: her own name among three cards whose names start with other letters → a family name (people and pets, a nickname when set; 20 short buddy names fill a small family) among four → a name of up to five letters built from tiles into slots that show it faintly, each tile saying its letter, a wrong tile saying the one it needs (+2 extra tiles, no b/d or p/q). `GameController.family` gives games the household's other names. A kid whose name can't print (one letter, over eight, no Latin letters) starts at family names. 6 new clips. Tests: core +4, app +4 widget + layout at four sizes, E2E +1.
- 2026-10-07 — Owner request: every Toybox game enabled by default. `gamesFor` now returns every game a grown-up hasn't switched off, the ones that suit the kid's age first (launcher order within each part), instead of hiding games for older kids until opened early; the "open early" setting is gone (old `early` entries in the stored setting are ignored) and Settings → Toybox's switches only turn games off. Test helpers no longer open games early; the E2E settings journey now switches Counting Garden off. Tests: core (rewritten launcher test), E2E +1.
- 2026-10-07 — Tallies (FR-TOY-03, Appendix B; game id `tally`): a painted chalkboard in a wooden frame on a meadow path; bunnies hop in from the right one at a time and wait. A tap on the board or the bunny draws a chalk line in (the fifth crosses the four), the voice says the count, the bunny hops and leaves left; a tap with no bunny makes no mark and shakes the board (a slip; a second tap within 450 ms of a mark is ignored, not a slip). After the last bunny the marks light yellow as the voice counts them back (one by one at level 1, by the bundle then on after) and says "n bunnies!"; a 9 s wait glows the board and says "Tap the board for the bunny.". Ladder: 1–5 bunnies → five already on the board, 1–5 more (6–10) → read a tally of 2–10 among three numerals one or two apart (a wrong one: the voice counts the marks with her). On tall screens the board and the bunny sit together above the middle. 14 new clips. Also: with every game on the launcher is long, so the widget-test harness scrolls the launcher's own grid. Tests: core +4, app +3 widget + layout at four sizes, E2E +1.
- 2026-10-07 — Hundred Square (FR-TOY-03, Appendix B; game id `hundred`): number squares in rows of ten in the Toybox's digits (`GlyphView`), a ladybug at the corner. "Find the number fifty-four.": the right square brings the ladybug flying over and lights its row as the number is said; a wrong one wiggles and says its own number (the reversed twin is the decoy the square teaches past); two slips glow the row, three the square; 12 s asks again. Ladder: 1–10 → 1–20 → 1–100 (80 % past twenty) → 13 blank squares, the asked one among them ("It's hiding! Where does it go?"; its neighbors in the row stay; a blank she tries shows what it hid). Number words now run to a hundred (`numberWord`; `numberClip` and `findNumberClip` 21–100: 161 new clips). Built and committed together with Tallies (they share the voice, catalog and test files). Tests: core +3, app +3 widget + layout at four sizes, E2E +1.
- 2026-10-07 — Freeze Dance (FR-TOY-03, Appendix B; game id `freeze`, free play): a random Build-a-Creature buddy (its `CreaturePainter` and dance notifier, the ticker capped at 30 fps on T1) dances to a loop the game plays itself from the synthesized sounds: `kFreezeTune`, 16 eighth notes of C major pentatonic on the xylophone (pitched by rate), kick and snare on the beats, hat on the off-beats, a step every 200 ms. The music stops dead, "Freeze!", and the buddy holds its pose inside a painted ice block (alpha in the paints, no opacity layer) until "Dance!". Songs: four 8–10 s dances with 3 s freezes → five 4–9 s dances with 1.5–5 s freezes → five dances each an animal's (the buddy becomes the emoji and moves its way; "Dance like a frog!", "Hop like a bunny!"…). "Great dancing!" records the song and a new buddy starts after 4 s. Tapping the buddy twirls it. 10 new clips. Tests: core +1, app +2 widget + layout at four sizes, E2E +1.
- 2026-10-07 — Music Sequencer (FR-TOY-03, Appendix B; game id `sequencer`, free play): a row per animal, a column per step, a playhead every 330 ms (`kSeqStepMs`) playing each lit square's call while the animal hops; a plain starter beat plays from the first pass (dog on the beat, cat between, frog and chicken answering); squares toggle (a lit one calls at once), animals play their call, the dice deals a pattern (each row a third to a half lit, never empty). Every fourth square is a shade darker, as a bar is counted. New `Sfx.dogBeat`, `catBeat`, `frogBeat`, `chickenBeat`: single calls (0.23–0.55 s) cut by `tool/sounds/animals.py beats` from the same CC0 recordings as the farm, so a step never piles calls up. Ladder: 4×2 → 8×2 → 8×3 → 8×4. 1 new clip. Tests: core +1, app +1 widget + layout at four sizes, E2E +1.
- 2026-10-07 — Weather Dress-Up (FR-TOY-03, Appendix B; game id `dressup`): `GameController.weather` reads the household's forecast through `wearInputs` (extracted from the weather screen's What to wear card, which now uses it too) and `dressWeatherFor` turns it into a kind of day (snow, rain, cold, cool, warm, hot: What to wear's thresholds); the game host keeps the forecast loaded while a game is open. The sky takes the day's colors; a painted paper-doll buddy wears each pick (emoji placed on it: tops over the body, legs, shoes at the feet, a hat on the head, glasses on the eyes, a scarf at the neck, mittens and an umbrella at a hand). One part at a time, one choice that suits (`kDressSuits`) and the rest from the opposite kind of day; tops are a tank top, a T-shirt or a warm coat (a sweater emoji looked too much like the T-shirt to choose between). Without a forecast it pretends a different day each round; a pretend first round becomes the real day if the forecast arrives within 450 ms. Ladder: top → top and shoes → top, legs, feet and one more. 29 new clips. Built and committed with Music Sequencer (shared files). Tests: core +3, app +1 widget + layout at four sizes, E2E +1.
- 2026-10-08 — Who's That? (FR-TOY-03, Appendix B; game id `whosthat`): faces come from the family photo library: Settings → People → "Use a photo" (`shared/face_picker.dart`: a grid of the library's photos, then drag and pinch the photo under a circle; needs a Hub) stores a `FaceCrop` (blob sha, aspect, square) as JSON in `profiles.avatar_blob`, and `ProfileAvatar` (`shared/face_photo.dart`) draws it through `DAvatar`'s new `photo` builder everywhere an avatar shows (Home, Kids, calendar, lists, recipes, reminders, Toybox), decoded at display size, the emoji as fallback. The voice asks by the family word a name or nickname is (`kWhoWords`: Mom, Mommy, Mama, Mum, Dad, Daddy, Dada, Papa, Grandma, Grandpa, Granny, Nana, Grandad, Gramps, Auntie, Uncle), "you" for the child, "the doggy"/"the kitty" for pets; the launcher shows the game once two people have faces and one is askable (`whoPlayable`). 21 clips. Two faces → four → six; slips by `expansionResult`. E2E: `?faces=1` (demo only) gives the demo family face crops with no photo behind them, so they draw as emoji. Also fixed the red run of Music Sequencer/Weather Dress-Up: the sequencer's step label was on a container (now a leaf), warm-day legs had nothing to choose (shorts only), and Tallies' `debugWaiting` counted the bunny just marked (flaky tests on rounds of 2+). Tests: core +4, app +3 widget + layout ×4 sizes, E2E +1.
- 2026-10-08 — Story Time (FR-TOY-03, Appendix B; game id `storytime`, free play; `stories` is What Happens Next): nine books in `kStoryBooks` (`toybox/storytime.dart`; `kStories` was taken), three per level (4, 6, 8 pages); the shelf (`storyShelf`) shows the newest unlocked set first, then the one below, in a fixed order. Every scene thing is a picture word, so a tap says its existing `word_*` clip; backdrops are painted per `StoryScene`, things placed by fractions (a core test keeps them inside a 4:3 picture). The voice says the title, then each page (`story_<id>_<n>`), "The end!", and the round is recorded `played` and `calm` (no confetti). Arrows are painted, not icons. 65 clips ("Bear eats a yellow banana": an article right before a `[[…]]` word is read as the letter A; "Everyone" avoided: its British "-one"). Also: the host's lasting `game.rounds` label made Odd One Out's flaky journey reliable. Tests: core +3, app +2 widget + page layout at four sizes, E2E +1.
- 2026-10-08 — Cookie Count (FR-TOY-03, Appendix B; game id `cookies`), first of the second set chosen from the frame's play counts (`game_events` on the frame, Oct 5–8: Number Tracing 34 rounds, Who Has More? 22, Feed the Monster 20, Sight Words 16, Tallies 15). Feed the Monster's painter is now `MonsterPainter` with a `MonsterSkin` (green, purple, orange). The jar adds a cookie and the voice says the new count (`numberClip`); a cookie tapped on the plate goes back; the bell (new synthesized `Sfx.ding`) serves: right → munched one by one with `cookies_yum_N`, wrong → `cookies_more_N`/`cookies_fewer_N`, the plate kept, spots after two slips (`countingResult`). 41 clips. Core: 4 tests (`toybox_more_test.dart`), widget: 4 + the layout loop at 4 sizes (`toybox_more_test.dart`), E2E: 1 journey × 4 projects (`toybox_more.spec.ts`). Found in the visual review: a cookie leaving the jar caught a quick second tap and flew straight back; flying cookies now ignore taps.
