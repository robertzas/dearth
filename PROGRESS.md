# PROGRESS — build log & crash-recovery guide

This file is the single source of truth for **where the build is**. Any
session (human or agent) that starts work MUST read it first and update it
when a step starts and finishes. If a turn dies mid-step, the next session
resumes from here.

## How to resume after an interruption

1. Read this file top to bottom, then `SPEC.md` sections named by the
   current step.
2. Restore a compiling tree **before** new feature work:
   ```bash
   tool/check.sh            # pub get + codegen + analyze + tests (all packages)
   ```
   If it fails, fix or revert the half-finished step listed under
   **In progress** below. Never stack new work on a red tree.
3. Continue with the first unchecked step. Update **In progress** first.
4. When a step completes: tick it, add a dated line to the **Log**, and note
   anything surprising under **Decisions & findings**.

Useful commands (details in `README.md`):

| Purpose | Command |
|---|---|
| Everything green? | `tool/check.sh` |
| Regenerate drift code | `tool/codegen.sh` |
| Run the Hub locally | `tool/dev_hub.sh` |
| Run the app (web / linux) | `cd apps/dearth_app && flutter run -d chrome` / `-d linux` |
| Build all host-buildable targets | `tool/build_all.sh` (CI builds iOS/macOS/Windows too) |
| Web E2E (Playwright, 4 viewports) | `tool/e2e.sh` (`SKIP_BUILD=1` reuses the web build) |
| Web DB runtime (sqlite3.wasm, drift worker) | `tool/web_assets.sh` |
| App icons from the SVG source | `tool/icons/make_icons.sh` |
| Deploy to the kitchen frame | `tool/deploy_frame.sh --help` (planned, step 7.1) |

## In progress

- Next: 4.2 calendar M2 (drag to move, People view, reminders, weather on events), then 6.3 music box / 6.2 toybox, 3.2 Android platform channel.
- Then: 4.2 calendar M2 items, 3.2 Android platform channel (FreeKiosk bridge, light sensor), 7.1 deploy/perf scripts, CI action major upgrades.

## Plan & status

Milestones refer to `SPEC.md` §17. ✅ done · 🟡 partial · ⬜ not started.

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
- 🟡 3.2 App core: ✅ device DB (native isolate / web wasm worker), sync client (bootstrap, bulk apply, outbox, repair, backoff, commands, telemetry), session + pairing onboarding, demo mode, router + adaptive shell (rail / bottom bar / phone bar, keep-alive budget), grown-up mode (PIN, relock, lockout), kiosk hold gesture → PIN → kiosk menu, idle engine + display modes (screensaver, night), toasts, global error handling, wake lock · ⬜ Android platform channel (FreeKiosk bridge, light sensor, brightness), corner-sequence step of the exit gesture, frame-stat telemetry

### Phase 4 — M1 features
_Every feature step below ships with unit tests **and** its Playwright journey specs._
- ✅ 4.1 Home dashboard (Wall-L 3 columns, tablet 2 columns, Wall-P stacked, phone Today) + widgets: header (date/clock/weather/alerts/sync/lock), agenda + now-line, up next + conflicts, week strip, notes & countdowns, dinner, kids' chores, shopping
- 🟡 4.2 Calendar: ✅ day / 3-day / week / month / agenda, person filters, event sheet, full editor with recurring scopes (this / following / all), quick add with preview, countdowns, auto + learned icons · ⬜ M2: drag to move, People view, reminders, weather on events
- ✅ 4.3 Weather screen (now, 36 h chart with rain/sun/UV bands, rain summary, 10 days, sun & moon, what to wear, alerts, sources)
- 🟡 4.4 Photos: ✅ curation grid (favorite/hide), screensaver (crossfade, portrait pairing, Hub pre-blur, precache, overlays with drift, long-press options, painted art-pack fallback), night clock · ⬜ verified against real Amazon/folder sources on the Hub
- 🟡 4.5 Settings: ✅ household (location search, units, week start, clock), people (colors, roles, stages, buddies, PINs), this display (theme, size, distance, idle, night, role, tier), calendars (enable, default, ICS subscribe, Google connect incl. paste-back), photo frame & night, Hub & devices (status, approvals, enrollment codes, disconnect), about · ⬜ weather/recipe/integration keys page, diagnostics

### Phase 5 — M2 features
- 🟡 5.1 Meals: ✅ week planner (grid on landscape, day list on portrait/phone; recipes or free text; per-entry servings; remove with undo), recipe sheet (servings scaling with friendly fractions, US/metric, add to plan, add ingredients to list, save to box, per-person face ratings), slot picker (search, "Pairs with your plan" with explanations, box, quick weeknights, Leftovers/Eat out/Takeout), Discover (search, pairs, quick, favorites, popular, Surprise me; Hub API or bundled catalog), recipe box (+ URL import on a Hub), cook mode (one step at a time, detected timers, step ingredients, keeps the display awake), week → shopping list (consolidated, sources, staples skipped), Home dinner card opens tonight's recipe · ⬜ templates / copy last week (FR-MEAL-04), leftovers links (FR-MEAL-03), per-period shopping view with check state (FR-SHOP-02..05), allergen/diet filters, cuisine passport, seasonal & "haven't had in a while" feeds, drag to move
- 🟡 5.2 Lists ✅ (FR-LIST-01, aisle grouping for shopping, undo) · notes (display only) · ⬜ timers

### Phase 6 — M3 features
- 🟡 6.1 Kids: ✅ Kids destination (a tab per kid + Grown-ups), stage-aware chart of big picture cards, "I did it!" with celebrations (confetti / stars / bubbles, buddy, praise; calm at night; reduced-motion variant), Undo for 30 s, grown-up approvals behind the PIN, grants on the append-only ledger with stable ids (idempotent, converge across devices; undo appends reversals), reward jar with a surprise reveal, star bank with a pinned goal and redemption requests, sticker book (pick and place on painted theme scenes, pages), routine run mode (stepping-stone path, visual timer, debounced steps, progress saved), grown-ups' household chores (claim Anyone chores), family team goal, Settings → Kids & chores (chore editor with who/schedule/time/rewards/approval/voice line, age-sorted chore library, routine editor from templates with steps/timers/reorder, reward editor from ideas, jar size, sticker theme and star goal per kid) · ⬜ voice prompts / TTS playback, First–Then and choice boards, kindness hearts, growing garden, potty chart, proud wall, feelings check-in, adult rotation / fairness, approval notifications
- ⬜ 6.2 Toybox: launcher + launch-set games
- ⬜ 6.3 Music box: tiles, local files, YouTube, Spotify (via Hub)

### Phase 7 — Deployment tooling & CI
- 🟡 7.1 ✅ tool/build_all.sh, tool/web_assets.sh, tool/e2e.sh, tool/icons/make_icons.sh · ⬜ tool/deploy_frame.sh (ADB over LAN, FreeKiosk External App mode, REST key, enrollment), tool/perf_gate.sh
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
- **2026-10-03** Follow-ups: bundle a Fluent Emoji subset (SPEC §11.3; web
  currently fetches Noto Color Emoji at runtime), slim the Hub image, Postgres
  backend, weather/recipe key settings UI.

## Log

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
- 2026-10-03 — Fixed the screensaver: fallback text style (yellow underline) on the clock and overlays, photo options that could never open, and a photo pool read while paused; screensaver widget tests + shared app test harness. E2E: 149 passed, 7 skipped.
- 2026-10-03 — Kids & chores settings: chore/routine/reward editors, chore library by age, jar/sticker/goal settings; 8 setup unit tests; 4 Playwright journeys × 4 viewports.
- 2026-10-03 — Kids (step 6.1 core): chart, celebrations, approvals, jar, stars, sticker book, routines, grown-ups' chores; 9 kids-op unit tests; 6 Playwright journeys × 4 viewports.
- 2026-10-03 — Meals (step 5.1 core): planner, recipe sheet, slot picker, Discover, recipe box, cook mode, add to list; 8 meal-op unit tests; 9 Playwright journeys × 4 viewports (full suite: 109 passed, 7 skipped).
- 2026-10-03 — Pushed to GitHub; CI run #1 green except the release job (artifact download); fixed → run #2 published `v0.1.0-build.2`.
- 2026-10-03 — E2E run 2: 69 passed, 4 failed (quick-add preview had no readable text node; fixed by labeling the summary node), 7 skipped by design. README written (screenshots in `docs/images`, LFS).

