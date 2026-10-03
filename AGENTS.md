# AGENTS.md — working on Dearth

Read these first, in order:

1. **`PROGRESS.md`**: where the build is, what's in progress, and how to
   recover from an interrupted session. Update it when you start and finish
   a step.
2. **`SPEC.md`**: the product contract. Requirement IDs (`FR-CAL-12`) are
   referenced from code comments and test names.
3. This file: the rules that keep the codebase coherent.

## Layout

| Path | What lives there |
|---|---|
| `packages/dearth_core` | Pure Dart. Drift schema (`lib/src/db/tables.dart`), sync (HLC, ops, merge, protocol, `SyncStore`, `Mutator`), and domain logic (calendar, recipes, kids, weather models, solar). **No Flutter imports.** |
| `packages/dearth_integrations` | Pure Dart provider adapters (weather, Google, ICS, photos, recipes, music) behind small interfaces, with fixture-based tests. |
| `packages/dearth_ui` | Flutter design system: tokens, themes, display classes, `uiScale`, tiers, motion, components. No app state. |
| `hub/dearth_hub` | Dart server: sync authority, pairing, blobs, jobs, integrations, admin API, web hosting. |
| `apps/dearth_app` | The Flutter app for every platform. Feature-first folders under `lib/features/<feature>/`. |
| `e2e/` | Playwright end-to-end suite against the web build and a test Hub. |
| `tool/` | `check.sh`, `codegen.sh`, `build_all.sh`, `e2e.sh`, `dev_hub.sh`, `web_assets.sh`, `icons/` (the SVG source of every app icon and `make_icons.sh`). Planned: `deploy_frame.sh`, `perf_gate.sh`. |
| `.github/` | `workflows/build.yml`: every push to `main` runs the gate and the E2E suite, builds every platform plus the Hub image, and publishes a GitHub release `v<version>-build.<run>`. `actions/setup`: shared Flutter, pub and LFS setup. |

## Golden rules

1. **Never leave the tree red.** `tool/check.sh` must pass at the end of
   every step. If a session is interrupted, the next one fixes or reverts
   first (see `PROGRESS.md`).
2. **All synced writes go through `Mutator`** (devices) or the Hub's op
   pipeline. Never `INSERT`/`UPDATE` a synced table directly: it bypasses
   HLC stamping, replication and the outbox.
3. **Synced columns are nullable or defaulted.** Op field keys are SQL
   column names (`start_ms`, `profile_ids`). JSON columns hold encoded text;
   `Mutator` encodes `Map`/`List` values for you.
4. **Append-only tables** (`ledger_entries`, `feeling_entries`,
   `game_events`) use `Mutator.insertOnly` and are never updated. Balances
   are sums.
5. **Natural-key rows use `stableId(kind, parts)`** (chore instances, routine
   runs, shopping states) so devices converge offline.
6. **Instants are epoch ms (UTC); local dates are `LocalDate`/`YYYY-MM-DD`.**
   Every "today" decision goes through `HouseholdTime`. No ad-hoc
   `DateTime.now()` in feature code.
7. **Integrations run on the Hub** (or in Solo mode inside the app's
   integration runner). Widgets never call providers or HTTP.
8. **Performance is a requirement** (SPEC §12). Don't use `BackdropFilter`,
   `ShaderMask`, `Opacity` over large subtrees, or animated blur in feature
   code. Give independently animating regions a `RepaintBoundary`. Decode
   images at display size. Ambient animations are capped at 30 fps on T1.
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
    extensions (images, fonts, wasm, archives, media). Check
    `git lfs ls-files` before committing a new kind of binary. Generated
    text (`database.g.dart`, `web/drift_worker.js`) stays in plain git.

## Testing

- `dearth_core`, `dearth_integrations`, `dearth_hub`: `dart test`. Provider
  adapters are tested against recorded fixtures; no network in tests.
- `dearth_ui`, `dearth_app`: `flutter test` (unit + widget).
- End to end: `tool/e2e.sh` builds the web app, starts a Hub with
  `DEARTH_FAKE_PROVIDERS=1` on a temp data dir, and runs Playwright across
  the Wall-L, Wall-P, Tablet and Phone projects. `SKIP_BUILD=1` reuses the
  last web build. `CHROME_PATH=/usr/bin/google-chrome-stable` uses a system
  Chrome instead of downloading one. Extra arguments go to
  `playwright test`, e.g. `tool/e2e.sh tests/calendar.spec.ts`.
- E2E specs drive the app through `e2e/tests/helpers.ts`:
  - `openDemo(page, route)` starts a seeded local household at a fixed
    clock (`?demo=1&e2e=1&now=…`).
  - `tap()` clicks the centre of the node, as a finger would. Empty
    semantics containers can overlap it in the DOM, and Flutter hit-tests
    the pointer position itself.
  - `expectText()` polls the aria-label and the text content.
  - `scrollTo()` wheels lazy lists until a `tid` is built.
  - `goTo()` uses whichever navigation chrome the layout shows.
- Name tests after requirements where possible: `FR-CAL-12: quick add …`.

## Code generation

Drift code lives next to the schema (`database.g.dart`) and is committed.
After editing `tables.dart`, run `tool/codegen.sh`. Builders take ~90 s the
first time.

## Style

- Strict analysis (`analysis_options.yaml` at the root). No `dynamic`, no
  `print` (use `package:logging` / the app logger).
- Prefer small, composable widgets with `const` constructors.
- Riverpod: narrow providers, `select` in widgets, no business logic in
  `build`. Riverpod 3 pauses providers that nothing listens to, so in an
  event handler `ref.read(p).value` is null and `ref.read(p.future)` can
  wait forever unless a visible widget watches `p`. For one-off reads,
  query the database directly (e.g. `shoppingListOnce(db)`).
- Comments explain *why*. Reference spec sections (`SPEC §8.4`) when a rule
  comes from there.
