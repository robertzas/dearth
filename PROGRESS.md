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
| Build all host-buildable targets | `tool/build_all.sh` |
| Deploy to the kitchen frame | `tool/deploy_frame.sh --help` |

## In progress

- 2.3 Docker image + compose files

## Plan & status

Milestones refer to `SPEC.md` §17. ✅ done · 🟡 partial · ⬜ not started.

### Phase 1 — Foundations
- ✅ 1.1 Workspace scaffold: pub workspace, app (android/ios/web/linux/macos/windows), hub, core, integrations, ui; git init; LICENSE; lint config
- 🟡 1.2 PROGRESS.md ✅, AGENTS.md ✅, tool/check.sh ✅, tool/codegen.sh ✅, README.md ⬜ (written at the end, step 8.2)
- ✅ 1.3 dearth_core: ids, LocalDate/time, HLC, ops, merge, wire protocol + tests
- ✅ 1.4 dearth_core: drift schema (all tables), SyncStore, Mutator + tests
- ✅ 1.5 dearth_core: calendar domain (recurrence, layout, quick-add, icons), solar, weather model, palette + tests
- ✅ 1.6 dearth_core: recipes (parser, units, KB, scaling, consolidation, scoring), kids (schedules, ledger) + tests

### Phase 2 — Integrations & Hub
- ✅ 2.1 dearth_integrations: http abstraction, weather (Open-Meteo, NWS, WU, merge), recipes (TheMealDB, Spoonacular, URL import), ICS, Google OAuth + Calendar, photos (Amazon share, Immich, Google Picker), music (YouTube oEmbed, Spotify) + fixture tests
- ✅ 2.2 dearth_hub: config, storage, auth & pairing, sync WebSocket, snapshot, blobs + variants, admin API, OAuth endpoints, jobs, static web + tests
- ⬜ 2.3 Docker image + compose files

### Phase 3 — App foundations
- ⬜ 3.1 dearth_ui: tokens, themes (Light/Evening/Night), display classes, uiScale, tiers, components, motion
- ⬜ 3.3 **Playwright E2E harness** (`e2e/`): Hub fake-provider mode, test Hub launcher, viewport projects (Wall-L/Wall-P/Tablet/Phone), `tid()` semantics ids, `?e2e=1` semantics enablement, first smoke specs
- ⬜ 3.2 App core: platform channel (Kotlin), device profile/tier, DB open (native/web), sync client, repositories, demo seed, onboarding/pairing, router + shell, grown-up mode, kiosk gesture + FreeKiosk handoff, idle engine/display modes, toasts

### Phase 4 — M1 features
_Every feature step below ships with unit tests **and** its Playwright journey specs._
- ⬜ 4.1 Home dashboard + widgets
- ⬜ 4.2 Calendar (views, event sheet, editor, quick add, countdowns)
- ⬜ 4.3 Weather screen
- ⬜ 4.4 Photos curation + screensaver
- ⬜ 4.5 Settings (household, people, devices, calendars, weather, photos, integrations, display)

### Phase 5 — M2 features
- ⬜ 5.1 Meals: discover, recipe detail + scaling, planner, shopping list, recommendations, cook mode
- ⬜ 5.2 Lists, notes, timers

### Phase 6 — M3 features
- ⬜ 6.1 Kids: chart by stage, chores, routines, rewards (stickers, jar, stars), celebrations, approvals
- ⬜ 6.2 Toybox: launcher + launch-set games
- ⬜ 6.3 Music box: tiles, local files, YouTube, Spotify (via Hub)

### Phase 7 — Deployment tooling & CI
- ⬜ 7.1 tool/build_all.sh, tool/deploy_frame.sh (ADB over LAN: APK, FreeKiosk External App mode, hardened exit gesture, REST key, enrollment), tool/perf_gate.sh
- ⬜ 7.2 GitHub Actions: analyze/test + builds for android, web, linux, windows, macos, ios + hub image

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

## Log

- 2026-10-02 — Scaffolded workspace (step 1.1).
- 2026-10-02 — Core sync foundation: HLC, ops, field-LWW merge, protocol, 40-table drift schema, SyncStore, Mutator; 60-seed convergence property test green (steps 1.3–1.4).
- 2026-10-02 — Calendar/weather/solar domain (recurrence w/ DST + exceptions, layout, quick-add, icons, unified weather model); 112 core tests green (step 1.5).
- 2026-10-02 — Recipes (units, ingredient parser/KB, consolidation, plan-aware scoring, cook-mode timers) + kids (schedules, ledger, libraries); added `anchor_date` to chores/routines; 131 core tests green (step 1.6).
- 2026-10-02 — Integrations: Fetcher (retry/backoff), Open-Meteo/NWS/WU + merge policy + FakeWeather, TheMealDB/Spoonacular(budget)/URL import/24-recipe catalog, ICS parser, Google OAuth+Calendar, Amazon share/Immich/Google Picker, YouTube/Spotify; 32 fixture tests green, recorded real API fixtures (step 2.1).
- 2026-10-02 — Hub: kernel (validation/ACL/idempotent op log/fan-out/snapshots), auth (PBKDF2 admin pw, hashed device tokens, pairing + enrollment codes), WS sessions (catch-up w/ live buffer), blob store (libvips variants, pre-blur, image proxy), jobs (weather, ICS, Google two-way, photos, maintenance), routes (core/feature/admin/OAuth/webhooks), static web host; 8 in-process integration tests green (step 2.2).
