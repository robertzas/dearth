# PROGRESS — where the build is & how to resume

`AGENTS.md` is the working manual (rules, commands, environment,
conventions, gotchas) — read it first; this file is **state**: what's
built, what's open, and how to pick up after an interrupted session.
Any session that starts work updates this file when a step starts and
finishes. Build history lives in `git log` and the CI runs; durable
findings belong in `AGENTS.md`/`SPEC.md`, not here.

## Resume after an interruption

1. Check the latest `build.yml` run on `main` (CI is the test runner;
   AGENTS golden rule 1). If it failed, fix or revert the failing change
   and wait for green before any new work. Never stack work on a red tree.
2. Read **In progress** below: if a line describes unfinished work, that
   is where the last session died — resume it (or revert it) first.
3. Otherwise pick from **Open items** (or the owner's next request),
   add a line under **In progress**, and remove it when done, folding
   anything durable into `AGENTS.md`/`SPEC.md`/`SUGGESTIONS.md`.

## In progress

- (nothing)

## State (2026-10-15)

- CI green; the frame is on **v0.1.126** (it installs GitHub releases
  itself; the owner triggers updates in Settings → Updates).
- **M1–M3 built and shipping** — Home, Calendar (Google two-way + ICS +
  People + kid timeline + reminders + the Family calendar offer),
  Weather, Photos & screensaver, Settings (grouped, searchable), Meals
  (aggregated search, planner, cook mode, family box, synced kitchen
  timers), Lists (Google Tasks sync), Kids (chart, celebrations,
  approvals — approve or send back "Not yet" — routines, reward jar,
  star bank, stickers), Solo and Toybox-only modes, the Android platform
  channel (brightness, night, screen off, clock check), FreeKiosk bridge,
  device removal, GitHub self-updates for app and Hub, HeliBoard + emoji
  working on the frame.
- **59 Toybox games**, all voiced (Maya-1) and audited for frame speed
  (2026-10-13/14); every game is on by default.
- **Deferred**: the Music box (owner, 2026-10-05) — its requirements
  stand in SPEC §10.9/§13.7 for when it comes back.

## Open items

**Features not yet built** (milestone tags in SPEC §10):

- Meals: planner templates / copy last week (FR-MEAL-04), leftovers
  links (FR-MEAL-03), per-period shopping view with sources and checked
  state (FR-SHOP-02..05), allergen/diet hard filters (FR-RCP-03),
  cuisine passport / seasonal / "haven't had in a while" feeds
  (FR-RCP-04), drag-to-move in the planner.
- Kids: voice prompts / TTS playback, First–Then and choice boards
  (FR-KID-09/10), kindness hearts (FR-KID-16), growing garden
  (FR-KID-17), potty chart (FR-KID-18), proud wall (FR-KID-19), feelings
  check-in (FR-KID-23), adult rotation / fairness (FR-KID-05), approval
  notifications (§10.14).
- Photos: verify against real Amazon / folder sources on a live Hub.
- Settings: diagnostics page. Web Push / share targets / collections
  (FR-PHO-08, FR-CMP-03) where still tagged [M2]+.
- README final pass (old phase 8.2).

**Engineering follow-ups**:

- Postgres backend (`DEARTH_DB_URL`): `SyncStore` needs dialect-aware
  SQL (`?` vs `$n` placeholders) first (SPEC §7.4).
- Slim the Hub image (411 MB).
- Weather on events for far-away locations needs a Hub job (geocode +
  forecast; FR-CAL-19 note).
- Fluent Emoji pre-rasterized set / `vector_graphics` (SPEC §11.3): the
  web still fetches Noto Color Emoji at runtime.
- Nav rail overflows at 720p + userScale 1.6 — the rail needs to adapt
  (or scroll) at large scales / short screens.
- Everything in `SUGGESTIONS.md` (perf, Hub backpressure, structure
  splits, CI release retention, missing widget/E2E tests).

**Standing perf misses on the frame** (known, not regressions; the gate
re-measures each release): week paging build p90 ~216 ms, month open
~370 ms, navigate build p90 swings ~95–160 ms with the same build
(cause not found), raster p90 over 10 ms in several scenarios, photo
crossfade raster p90 ~50 ms, PSS ~268 MB at the end of a run (no fixed
budget — growth and the baseline are what's watched).

## Waiting on the owner

- **Audition the Maya-1 voice on the frame**, especially the respelled
  letter-sound clips (`letter_*`, `sound_*`); `python3
  tool/sounds/voice.py <id>` remakes any single clip after a `RESPELL`
  tweak.
- **Pick the frame's update policy**: Settings → Updates is still "When
  I tap"; choose Nightly or When idle.
- **Bring the Hub's compose up to date** (README → Updating the Hub:
  the new `compose.yml` + `dearth_update_token` once) — until then the
  Hub only reports new releases.
- **Check the Hub's `.env`** for the old placeholder `DEARTH_PUBLIC_URL`
  (it switched the Hub off the paste-back flow).
- **Create the Google Cloud OAuth client and connect** (README → Google
  Calendar); the consent screen needs `calendar.app.created` and
  `calendar.acls` before accepting the Family calendar offer.
- **Add the RecipeAPI.io and RapidAPI (Tasty) keys** in Settings →
  Recipes, then re-record those two fixtures from real responses
  (`packages/dearth_integrations/test/fixtures/recipeapi_search.json`,
  `tasty_list.json` follow the documented shapes).
