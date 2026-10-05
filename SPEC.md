# Dearth — Product & Engineering Specification

> **Dearth** is a family command center for wall-mounted touchscreens: shared
> calendar, meals and recipes, chores and rewards, a toddler toybox, music,
> photos, and weather. It runs fast on a cheap Android frame, looks good
> enough to leave on the wall, and keeps the family's data on its own
> hardware.

| | |
|---|---|
| **Status** | Draft 0.1 for review |
| **Date** | 2026-10-02 |
| **Owner** | Robert Z |
| **Edition** | Native Flutter app + optional self-hosted Hub |
| **Supersedes** | `../dearth_webapp/SPEC.md` (web edition) and `../dearth_flutter` (standalone edition) as the product contract. Both remain reference implementations; see §4 for what we keep from each. |

**How to read this document.** Requirements carry stable IDs (`FR-CAL-07`)
for use in code comments, tests, issues and PRs. Every requirement carries a
milestone tag (`[M1]` … `[M5]`, defined in §17). **MUST / SHOULD / MAY**
follow RFC 2119. ★ marks a suggestion that goes beyond the original brief
and is open for debate. Measured facts about the target hardware are dated;
re-measure before relying on them for new decisions.

---

## Table of contents

1. [Vision & product pillars](#1-vision--product-pillars)
2. [Reference household & devices](#2-reference-household--devices)
3. [Goals, non-goals & success metrics](#3-goals-non-goals--success-metrics)
4. [Lessons from previous attempts](#4-lessons-from-previous-attempts)
5. [Competitive parity (Skylight, Hearth)](#5-competitive-parity-skylight-hearth)
6. [Target hardware & performance envelope](#6-target-hardware--performance-envelope)
7. [System architecture](#7-system-architecture)
8. [Data model & sync](#8-data-model--sync)
9. [Identity, roles, security & privacy](#9-identity-roles-security--privacy)
10. [Feature specifications](#10-feature-specifications)
11. [UX & design system](#11-ux--design-system)
12. [Performance engineering](#12-performance-engineering)
13. [Integrations](#13-integrations)
14. [The Hub server](#14-the-hub-server)
15. [Kiosk deployment & device management](#15-kiosk-deployment--device-management)
16. [Quality & engineering practices](#16-quality--engineering-practices)
17. [Roadmap & milestones](#17-roadmap--milestones)
18. [Risks & mitigations](#18-risks--mitigations)
19. [Open questions](#19-open-questions)
20. [Appendices](#20-appendices)

---

## 1. Vision & product pillars

Dearth gives a family two things:

- **The five-second glance.** Anyone, from across the kitchen, knows what's
  happening today, what's for dinner, and whether to grab an umbrella.
- **The five-minute delight.** A two-and-a-half-year-old can spend five happy
  minutes in the Toybox, run her bedtime routine by herself, or put a
  sticker in her book, and nothing she taps can break the family's data.

It does this without a subscription, without sending the family's life to a
vendor cloud, and on hardware that costs a fraction of a Skylight or Hearth.

### Product pillars

| # | Pillar | What it means in practice |
|---|---|---|
| P1 | **Glanceable** | Today, the next event, weather and dinner are readable at 3 m. One screen answers "what's happening today?" |
| P2 | **Delightful & professional** | One coherent design system, purposeful motion, celebration moments, no rough edges, empty states that invite action. |
| P3 | **Fast on weak hardware** | Smooth at the target's 56 Hz on a 4× Cortex-A53, 2 GB, PowerVR GE8300 frame. Performance budgets are enforced, not hoped for (§12). |
| P4 | **Local-first & private** | Every screen renders from on-device data and keeps working offline. Credentials live on the Hub only. No telemetry. |
| P5 | **Toddler-proof, toddler-joyful** | Nothing destructive is reachable by small hands. Games and charts grow with her from 2 to 5. |
| P6 | **Open & portable** | One codebase for Android, iOS, web and desktop. The Hub runs anywhere Docker does: SQLite by default, Postgres optional. Every integration is pluggable, so other families can run Dearth with a different setup. |

---

## 2. Reference household & devices

We design for this household first and generalize second. Everything below
is optional or pluggable for other families.

| Aspect | Reference household |
|---|---|
| People | 2 adults (one Android phone, one iPhone); daughter aged 2.5. Design for ages 2–5. Profiles also cover caregivers, grandparents, guests and pets. |
| Home infrastructure | Home server running Docker with Postgres available; **Home Assistant**; an **HTTPS domain** reaching the server (reverse proxy). |
| Displays | **Kitchen hub:** 27" 1080p Android frame (Joyhong JT215M-class, portrait or landscape). **Toddler's room** and **entryway/office** tablets (future). **Phones and laptops** as companions. |
| Calendars | Google Calendar (two-way). |
| Photos | **Amazon Photos** (primary library), Google Photos, Immich, and a NAS folder. |
| Weather | Owns a **Weather Underground PWS with an API key**. Dearth must also work fully without a key. |
| Music | YouTube / YouTube Music, Spotify, Amazon Music, own song files. |
| AI | Not in v1. Specified as a pluggable provider, decision deferred (§10.16). |

**Generalization test.** A family with one Android tablet, a Google account
and no server MUST be able to install Dearth and get calendar, weather,
photos (local or shared-link), recipes, chores and the toybox (§7.2).

---

## 3. Goals, non-goals & success metrics

### 3.1 Goals

- **G1:** Match or beat Skylight and Hearth on the core family experience (§5).
- **G2:** Two-way Google Calendar sync with near-real-time updates.
- **G3:** Recipe discovery with serving scaling, a meal plan, and a
  consolidated shopping list. Plan-aware recipe recommendations reuse
  ingredients already being bought.
- **G4:** A toddler-first chores, routines and rewards system that scales to
  age 5 and to adult household chores.
- **G5:** A Toybox of creative and thinking games for ages 2–5, plus a
  curated music page.
- **G6:** A photo screensaver fed by Amazon shared albums, Google Photos,
  Immich and NAS folders, with in-app browse-and-select.
- **G7:** A weather dashboard built on the family's own WU station when
  available. It covers a week or more of daily forecast, the next 24 h
  hourly, rain chance and amount, and sunshine through the day.
- **G8:** Multiple displays and phones share one family state that stays in
  sync, with per-device roles.
- **G9:** Performance and polish that feel professional on the weakest
  target device.
- **G10:** Distributable: no hard dependency on this household's setup.

### 3.2 Non-goals (v1)

- Multi-household SaaS or any Dearth-operated cloud.
- General photo management (editing, uploading to Amazon or Google).
- Video calling and voice assistants. Voice is considered post-v1 via Home
  Assistant Assist.
- Replacing Home Assistant. Dearth integrates; it doesn't duplicate HA.
- Ads, paywalls, or engagement-maximizing dark patterns (especially in kid
  areas).
- Running on Android below 10 (API 29) on display devices. The phone
  companion follows Flutter's minimum.

### 3.3 Success metrics (measured on the JT215M unless noted)

| Metric | Target |
|---|---|
| Frame time, standard interactions (scroll, navigate, open sheets) | p95 ≤ 17.9 ms (56 Hz budget), no frame > 50 ms during navigation |
| Screensaver crossfade between 1080p photos | 0 dropped frames, p99 ≤ 17.9 ms |
| Cold start → interactive Home | ≤ 3.5 s |
| Resume from background | ≤ 300 ms |
| Memory (PSS), kitchen role, 24 h uptime | ≤ 220 MB steady state; < 10 % growth over 7 days |
| CPU, idle Home (no animation) / screensaver | ≤ 3 % / ≤ 12 % of total CPU |
| Change on phone → visible on LAN displays | p95 ≤ 1 s |
| Google Calendar change → visible on display | ≤ 15 s with push channels; ≤ 10 min fallback |
| Unattended kiosk uptime without app restart | ≥ 30 days |
| Toddler safety | 0 destructive actions reachable in a 30-minute random-tap fuzz of kid surfaces (§16.1) |

---

## 4. Lessons from previous attempts

Two earlier editions exist: `../dearth_webapp` (Bun + Svelte web app in
FreeKiosk's WebView) and `../dearth_flutter` (standalone Flutter, Hive
storage, no server). What we learned from each:

| # | What happened | Evidence | Decision for this edition |
|---|---|---|---|
| L1 | The web UI was slow or broken on the frame. | Stock WebView (Chromium 74) showed a blank page; Chromium 101 broke Tailwind 4 colors; even Chromium 124's V8 is slow on Cortex-A53. FreeKiosk + WebView used **318 MB PSS** (measured 2026-10-02). | **Native Flutter AOT app.** WebView is used only to embed the YouTube player. |
| L2 | Amazon Photos sign-in automation kept breaking. | Cookie paste, HTML form scraping and headless Chromium each failed against Amazon's anti-bot, passkey and 2FA flows. | **Never store Amazon credentials.** Use an anonymous **shared-album link** (§13.5.1); Immich, Google Photos Picker and folders are the official paths. |
| L3 | The standalone Flutter edition had no multi-device story. | Each device synced Google on its own. Hive is a key-value store with no relational queries. | **Hub + local-first relational replicas** (drift/SQLite on every device), with **one integration engine on the Hub**. |
| L4 | Google sign-in can't work on the frame. | `google_sign_in` needs Google Play Services, which the frame lacks. Google's device-code flow does not allow Calendar scopes. | **OAuth runs on the Hub** through the family's HTTPS domain. Displays never hold Google tokens. |
| L5 | Google Keep sync was unreliable to set up. | The Keep API is gated to Workspace accounts. | No Keep dependency. Local lists, with optional Home Assistant to-do and Google Tasks mirrors. |
| L6 | Keeping every tab alive cost too much memory. | `IndexedStack` held all 10 screens and their tickers alive. | Explicit keep-alive budget (§12.6); `TickerMode` off for offstage routes. |
| L7 | Spec-first development with FR IDs and tests worked well. | Two editions built quickly from one spec. | Keep it. FR IDs are referenced from tests. |

**Reusable assets** to port rather than reinvent:

- Google Calendar sync semantics: syncTokens, etag conflict policy, outbox (old SPEC §11.2).
- The recipe normalization, consolidation and reuse-scoring algorithms
  (`../dearth_webapp/MEALS.md`).
- The quick-add parser and NOAA solar math, with their test vectors.
- The FreeKiosk provisioning script and device quirks
  (`../dearth_webapp/skills/freekiosk/SKILL.md`, to be ported into this repo).
- The Toybox concepts and synthesized-sound approach.

---

## 5. Competitive parity (Skylight, Hearth)

Vendor features were captured from vendor sites and reviews (Sept/Oct 2026).
Skylight gates several features behind *Calendar Plus* (about $79/yr) and
Hearth behind its *Family Membership*. Dearth has no subscription.

| Capability | Skylight | Hearth | Dearth (milestone) |
|---|---|---|---|
| Calendar sync | Google, Apple, Outlook, Yahoo, Cozi, Readdle | Google, iCal, Outlook | Google two-way **[M1]**; ICS subscribe **[M1]**; CalDAV/iCloud and Microsoft 365 **[M5]** |
| Views | Day, week, month | Daily (24 h), weekly, monthly | Day, 3-day, week, month, agenda, **per-person columns**, kid picture-timeline **[M1–M3]** |
| Color-coded profiles | ✓ | ✓ (incl. pets, caregivers) | ✓ incl. pets, caregivers, guests **[M1]** |
| Countdowns | ✓ | — | ✓ incl. kid "sleeps until" **[M1]** |
| Weather at event time/location | ✓ | Weather widget | ✓ **[M2]** plus full weather dashboard **[M1]** |
| Lists / grocery | ✓ | ✓ (board and checklist) | ✓ plus meal-plan-generated shopping list **[M2]** |
| To-dos / chores | ✓ | ✓ (Anyone pool, celebrations) | ✓ incl. toddler picture-and-voice chart **[M3]** |
| Stars & rewards | Plus | Membership | ✓ stars, stickers, reward jar, family goals **[M3]** |
| Routines & streaks | Task lists | ✓ | ✓ visual routines, timers, First–Then **[M3]** |
| Meal planning & recipes | Plus (AI suggestions) | Membership (recipes on display) | ✓ multi-source recipe finder, scaling, plan-aware suggestions, cook mode **[M2]** |
| AI import (email, photo, PDF → events) | Plus ("Magic Import") | Membership ("Hearth Helper") | Pluggable, deferred **[M5]** |
| Photo screensaver | Plus | Privacy-mode photos | ✓ Amazon shared album, Google Photos, Immich, NAS **[M1–M3]** |
| Feelings check-in | — | ✓ | ✓ (ages 3+) **[M3]** |
| Character animations | Plus (Disney) | Celebrations | Original "buddy" characters, celebration catalog **[M3]** |
| Multi-device sync | ✓ | — | ✓ with per-device roles **[M1]** |
| Companion app | ✓ | ✓ | Android app + iPhone PWA **[M1–M2]** |
| Parental lock | ✓ | ✓ | Grown-up mode, toddler lock **[M1]** |
| **Toddler Toybox** | — | — | ✓ creative and thinking games for ages 2–5 **[M3]** |
| **Music for kids** | — | — | ✓ curated tiles: files, YouTube, Spotify, Amazon via HA **[M3–M4]** |
| **Smart home** | — | — | ✓ Home Assistant panel, doorbell pop-up, presence wake **[M4]** |
| **Multi-room roles** | — | — | ✓ kitchen, kid room (OK-to-wake), entry **[M4]** |
| **Privacy / ownership** | Vendor cloud | Vendor cloud | Self-hosted, offline-capable, exportable **[M1]** |

---

## 6. Target hardware & performance envelope

### 6.1 Measured device profile: kitchen frame (ADB, 2026-10-02)

| Property | Value | Consequence |
|---|---|---|
| Model | Joyhong JT215M-H01, Allwinner `sun50iw10p1` (A133-class), board `ceres` | Vendor quirks documented in `../dearth_webapp/skills/freekiosk/SKILL.md` |
| CPU | 4× Cortex-A53 @ 1.51 GHz, `schedutil` | Little cores only. Keep UI-isolate work small; push parsing to isolates. |
| ABI | **32-bit only:** `armeabi-v7a`, `zygote32`, no 64-bit ABI list | Build `android-arm`. Every native dependency MUST ship armeabi-v7a. |
| RAM | 2 GB total, ~1.0 GB free; **`ro.config.low_ram=true`**; Java heap limit 128 MB | Aggressive low-memory killer. Strict image-cache and keep-alive budgets. |
| GPU | **PowerVR Rogue GE8300**, GLES 3.2 (driver build 1.11, 2019); Vulkan 1.0.3 | Flutter 3.47's Impeller rejects this Vulkan driver ("Known bad Vulkan driver… falling back to OpenGLES") → **Impeller OpenGL ES backend**. The Skia opt-out exists but is deprecated (§12.2). |
| Display | 1080×1920 native portrait panel; app currently landscape 1920×1080; **56 Hz** (17.9 ms frame budget) | Both orientations are first-class. Budget frames for 56 Hz, not 60. |
| Density | Physical 230 dpi, **override 173 dpi** → devicePixelRatio ≈ 1.08 | Logical canvas ≈ **1777 × 1000 dp** in landscape. The reported physical dpi is bogus (187×57), so physical size must be configured (§11.2). |
| Android | 10 (API 29), patch 2020-11, `test-keys`, `ro.secure=0`, rooted adb | `minSdk` 29 for displays is fine; Flutter's default minimum is 24. |
| Google Play Services | **None** | No `google_sign_in` or FCM on the frame. OAuth happens on the Hub. |
| System WebView | `com.android.webview` 124.0.6367.219 (already upgraded) | Fine for embedding the YouTube player only. |
| Sensors | Accelerometer (Mi3da), **ambient light** (pt3r850). **No proximity sensor, no camera** (despite feature flags). | Light sensor → auto brightness and night mode. Wake on presence must come from Home Assistant motion sensors. |
| Audio | Speaker; no TTS engine installed | Use parent-recorded clips and Home Assistant TTS (§13.8) for voice; the Toybox bundles pre-generated clips (FR-TOY-07). |
| Storage | 26 GB, 24 GB free | Plenty for photo and music caches (default caps in §12.5). |
| Kiosk | FreeKiosk v2.0.0-beta.4 is Device Owner and HOME launcher | Phase 1 runs Dearth under FreeKiosk **External App mode** (§15). |

### 6.2 Device classes & performance tiers

Every device classifies itself at startup. Users can override the result in
Settings → Device → Advanced.

| Tier | Typical device | Detection heuristic | Effects policy |
|---|---|---|---|
| **T1 (low)** | JT215M frame, cheap 2 GB tablets | RAM ≤ 3 GB, or Impeller-GLES on PowerVR, Mali-4xx or Adreno 3xx | No runtime blurs. Ambient animations capped at 30 fps. Celebrations ≤ 120 particles. Ken Burns off by default. Image cache 48 MB. Keep-alive: Home + current screen. |
| **T2 (mid)** | 4 GB tablets with Vulkan | RAM 3–6 GB, Impeller-Vulkan | Light blurs allowed on small regions. Ken Burns on. Celebrations ≤ 300 particles. Image cache 96 MB. |
| **T3 (high)** | Modern phones, desktops, web on laptops | RAM > 6 GB or desktop | Full effects. Image cache 160 MB. |

| Display class | Rule (logical size) | Layout |
|---|---|---|
| **Wall-L** | width ≥ 1280 dp and landscape | Left navigation rail, 12-column grid, 3-column Home |
| **Wall-P** | height ≥ 1280 dp and portrait | Bottom navigation bar, 6-column grid, stacked Home |
| **Tablet** | shortest side 600–1279 dp | Rail or bottom bar by orientation, 8-column grid |
| **Phone** | shortest side < 600 dp | Bottom bar, single column, companion-first IA |

---

## 7. System architecture

### 7.1 Overview

```
 ┌──────────────────────────────── Home LAN ─────────────────────────────────┐
 │                                                                           │
 │  Kitchen frame (T1)        Kid-room tablet        Entry tablet            │
 │  FreeKiosk → External App  Dearth app             Dearth app              │
 │  ┌──────────────────────┐                                                 │
 │  │ Dearth app (Flutter) │  Phones: Android app (Flutter) · iPhone PWA     │
 │  │ ├ UI + design system │  Laptops: web app (Flutter web) for admin       │
 │  │ ├ Local replica      │                                                 │
 │  │ │  (drift/SQLite)    │                                                 │
 │  │ └ Sync client ───────┼──── WebSocket + HTTP ─────┐                     │
 │  └──────────────────────┘                           ▼                     │
 │                         ┌─────────────────────────────────────────────┐   │
 │                         │ Dearth Hub  (Docker · Dart AOT binary)      │   │
 │                         │ ├ Sync service: op log, LWW merge, fan-out  │   │
 │                         │ ├ Store: SQLite (default) | Postgres        │   │
 │                         │ ├ Blob store + media pipeline (libvips)     │   │
 │                         │ ├ Scheduler & jobs                          │   │
 │                         │ ├ Integration workers ──────────────────────┼───┼──▶ Google Calendar / Photos Picker
 │                         │ │  calendar · weather · photos · recipes    │   │    Weather Underground · Open-Meteo · NWS
 │                         │ │  music · Home Assistant                   │   │    Amazon shared albums · Immich
 │                         │ └ Web: companion PWA, admin, OAuth          │   │    TheMealDB · Spoonacular · recipe URLs
 │                         │        callbacks, webhooks (HTTPS domain)   │   │    Spotify · YouTube oEmbed
 │                         └───────────────┬─────────────────────────────┘   │
 │                                         └── LAN ──▶ Home Assistant         │
 └───────────────────────────────────────────────────────────────────────────┘
```

**Principles**

1. **Local-first UI.** Widgets read only the local database through reactive
   queries. The network is never on the interaction path. Every screen
   works offline using last-known data.
2. **One integration engine.** The Hub owns all provider credentials,
   polling, webhooks and quotas. Displays never talk to Google, Amazon or
   other vendors directly. One weather fetch serves every device.
3. **Push, don't poll.** Devices hold one WebSocket to the Hub and receive
   changes as they happen. There are no per-device polling loops.
4. **One language.** Dart everywhere (app, Hub, shared core), so models,
   validation, sync logic, recurrence and the recipe algorithms are written
   once and tested once.
5. **Everything observable.** Every device reports health, versions, tier,
   renderer and performance counters to the Hub's admin view.

### 7.2 Deployment modes

| Mode | Who it's for | How it works | Limits |
|---|---|---|---|
| **Hub mode** (recommended) | This household; homelabbers | Hub in Docker (`docker compose up`); any number of devices pair with it; remote access via HTTPS domain | Needs an always-on host |
| **Solo mode** `[M5]` | One device, no server | The app runs integration workers in a background isolate against its own database | One device only. Google OAuth only on devices with a browser or Play Services (not the frame). Migrate to a Hub later via export/import. |
| **Hub-on-device** `[M5]` ★ | Families without a server | The same Hub runtime (pure Dart) runs inside an always-on tablet; other devices pair to it | Weak devices pay the CPU cost; Google OAuth needs a phone-assisted flow |
| **Web dev mode** | Development | Flutter web build against a local Hub (`docker compose -f compose.dev.yml`) or a seeded in-memory Hub | Not for production displays |

### 7.3 Repository layout (Dart pub workspace)

```
dearth/
├── SPEC.md                    ← this document
├── AGENTS.md                  ← conventions for humans and coding agents (M0)
├── apps/
│   └── dearth_app/            ← Flutter app: android, ios, web, linux, macos, windows
├── hub/
│   └── dearth_hub/            ← Dart server (shelf), Dockerfile, compose files
├── packages/
│   ├── dearth_core/           ← pure Dart: domain model, drift schema, sync protocol,
│   │                            HLC, recurrence, schedules, units, ingredient parsing,
│   │                            recipe scoring, quick-add parser, solar math
│   ├── dearth_integrations/   ← pure Dart provider adapters (used by Hub and Solo mode)
│   └── dearth_ui/             ← design system: tokens, components, icons, motion,
│                                widget gallery app for visual review
├── tool/                      ← deploy_frame.sh, perf_gate.sh, release.sh
└── docs/                      ← setup guides (Google, WU, Amazon link, HA, FreeKiosk)
```

### 7.4 Technology stack

Versions are as of 2026-10-02; pin exact versions in lockfiles.

| Concern | Choice | Rationale / rejected alternatives |
|---|---|---|
| Client | **Flutter 3.47.x (stable), Dart 3.13** | Native AOT on armv7, one codebase for Android, iOS, web and desktop. Requested by the owner. |
| State | **Riverpod 3.4** (`select`-based fine-grained rebuilds) | Mature and testable. The previous edition already used it. Signals is a viable alternative but less proven for this team. |
| Routing | **go_router 18** with `StatefulShellRoute` | Deep links (web URLs), per-tab stacks, explicit keep-alive control |
| Local DB | **drift 2.35** + **sqlite3 3.x** (FFI on native; WASM + OPFS on web) | Relational, reactive `watch()` streams, migrations, background isolate. Rejected: Hive (no queries), Isar (maintenance risk), ObjectBox (licensing and armv7). |
| Hub DB | drift on SQLite (default) or **Postgres** (via `drift_postgres`, verify in M0; fallback: `postgres` 3.5 behind a storage adapter) | Same schema definitions on client and Hub. Owner's Postgres is optional, never required. |
| Sync | **Custom field-level LWW with Hybrid Logical Clocks** (§8.4) | Rejected: PowerSync (needs Postgres logical replication plus extra services), ElectricSQL (read-path only), Firebase/Supabase (cloud or heavy), Dart CRDT libraries (`crdt_sync` unmaintained since 2024). Data volume is small; the protocol stays small. |
| Hub HTTP | **shelf 1.4** + shelf_router + web_socket_channel | Stable and minimal. Rejected: Serverpod (Postgres-first, its own codegen and protocol), dart_frog (adds little here). |
| Serialization | drift-generated row classes + `json_serializable` for API DTOs | Keep codegen to drift_dev + json_serializable (+ optional riverpod_generator) |
| Images | Hub-rendered derivatives (**libvips** in the Hub image) + device blob cache + `ResizeImage` | Decoding originals on a Cortex-A53 is the main jank and memory risk. Rejected: `cached_network_image` (no control over sizing or offline guarantees). |
| Audio | **just_audio** (music, ExoPlayer) + **flutter_soloud** (low-latency game sound effects; verify armv7 in M0) | Toddler instruments need low latency; music needs streaming and gapless playback |
| Embedded web | `webview_flutter` 4.14 + `youtube_player_iframe` 6 | YouTube only (§13.7) |
| Animation | Implicit/explicit animations + `CustomPainter` + sprite sheets. Rive only if it passes the T1 benchmark. **No Lottie on T1.** | Predictable cost on Impeller-GLES |
| Charts | Custom painters (weather, progress) | Exact design control, cached pictures, no heavy chart library |
| Calendar views | **Custom** time-grid, month and agenda renderers | Performance and design control. Rejected: Syncfusion (license, weight), kalender/table_calendar (styling limits). |
| Icons & illustration | Material Symbols Rounded (variable font) + **Microsoft Fluent Emoji** (MIT) pre-rasterized + `vector_graphics` precompiled SVG | Rich, friendly, cheap to draw |
| Testing | flutter_test, `alchemist` goldens, integration_test, **patrol** (on-device), `package:test` on the Hub | §16 |
| Hub packaging | `dart compile exe` → slim Debian image with libvips; multi-arch (amd64, arm64); Compose with optional Postgres profile | Small, fast-starting, ARM-friendly (Raspberry Pi) |

### 7.5 Architecture decisions (ADR summary)

- **ADR-01 Native Flutter, not a WebView app.** L1 showed WebView apps are
  slow on this hardware. Flutter AOT with Impeller-GLES is the best
  available renderer here. Re-evaluate only if the M0 benchmark fails.
- **ADR-02 Hub + local-first replicas.** Gives multi-device sync, offline
  operation, and a single place for credentials and quotas. Displays stay
  fast because reads are local.
- **ADR-03 Custom HLC field-level LWW sync.** Off-the-shelf options are
  heavier than the problem or tied to Postgres or a cloud. Our data is small
  and mostly human-paced. Append-only ledgers and deterministic IDs remove
  the hard conflict cases (§8.4).
- **ADR-04 SQLite by default, Postgres optional.** Zero-admin for other
  families; the owner can point the Hub at existing Postgres
  (`DEARTH_DB_URL`).
- **ADR-05 Integrations run only on the Hub** (Solo mode excepted). Tokens
  never land on wall devices. Quotas are shared. Webhooks need a
  server-reachable URL anyway.
- **ADR-06 No Amazon credentials, ever.** Shared-album links only (L2).
- **ADR-07 Design for Impeller-GLES on PowerVR.** Don't rely on the
  deprecated Skia fallback. Enforce design rules (§12.3) instead.
- **ADR-08 Custom calendar rendering.** The calendar is the product's
  centerpiece; it must hit frame budgets and match the design system exactly.
- **ADR-09 FreeKiosk External App mode first.** Device-owner launcher mode
  and silent OTA updates come later (§15).

---

## 8. Data model & sync

### 8.1 Storage

| Where | Engine | Notes |
|---|---|---|
| Device (native) | drift + sqlite3 (FFI), WAL, `NativeDatabase.createInBackground` | All database I/O runs on a background isolate. The UI isolate only receives query results. |
| Device (web) | drift + sqlite3.wasm on OPFS (IndexedDB fallback) | Same schema and queries |
| Hub | drift on SQLite file `/data/dearth.db` **or** Postgres via `DEARTH_DB_URL` | Snapshot backups nightly (§8.7) |
| Blobs (photos, audio, drawings, avatars) | Content-addressed files `/data/blobs/<sha256[0:2]>/<sha256>` on the Hub. Device-side LRU cache under app storage. | Derivative variants keyed `sha256 + variant` (§14.5) |

The device database is a **replica**, not the source of truth. A wiped
device re-bootstraps from the Hub in seconds (§8.4.6). In Solo mode the
device database *is* the source of truth and is backed up locally.

### 8.2 Entity overview

Grouped by domain. Every synced table includes the sync columns from §8.3.

| Domain | Tables (key columns) |
|---|---|
| Household & people | `household` (name, timezone, locale, units, week_start, location) · `profile` (name, nickname, role: adult/child/caregiver/guest/pet, color, avatar_blob, birthday, kid_stage, buddy, pin_hash) · `device` (name, role, tier, orientation, scale, scopes, schedules) · `setting` (scope: household/device/profile, key, value JSON) |
| Calendar | `calendar_source` (kind: local/google/ics/caldav, account_id, remote_id, color, default_profile_id, writable, visible_on_roles) · `event` (source_id, remote_id, etag, title, icon, start, end, all_day, tz, rrule, exdates, recurring_parent_id, original_start, location, notes, countdown, reminder_minutes[]) · `event_profile` (event_id, profile_id) · `countdown` |
| Lists & notes | `list` (kind: shopping/todo/packing/custom, visibility, provider) · `list_item` (text, qty, unit, category, checked, sort_key, assignee, source_refs) · `note` (kind: sticky/announcement/doodle, body, blob, color, expires_at, targets) |
| Meals | `recipe` (source, source_id, url, title, image_blob, servings, times, cuisine, tags, diets, rating_avg) · `recipe_ingredient` (raw, qty, unit, name_norm, prep, optional, group) · `recipe_step` · `meal_slot` (breakfast/lunch/dinner/snack…) · `meal_plan_entry` (date, slot, recipe_id or title, servings, leftovers_of, notes, profiles) · `shopping_item` (derived + manual; see §10.5) · `pantry_staple` · `recipe_rating` (recipe_id, profile_id, score, at) |
| Kids & chores | `chore` (title, icon/photo blob, voice_blob, rrule, assignees or anyone, reward spec, needs_approval, window, stage) · `chore_instance` (deterministic id; date, profile, status, completed_at, approved_by) · `routine` / `routine_step` (icon, photo, voice, timer_s, song) · `routine_run` · `reward` (kind: item/surprise/family goal, cost, image) · `redemption` · **`ledger_entry`** (append-only: profile, currency: star/sticker/heart/jar, delta, reason, ref) · `sticker_placement` (page, sticker, x, y, scale, rot) · `feeling_entry` |
| Toybox & music | `game_progress` (append-only: game, level, result, duration) · `game_settings` · `artwork` (blob, game, profile) · `music_tile` (source: file/youtube/spotify/ha, ref, art_blob, title, order, profile) · `story_recording` |
| Photos | `photo_source` (kind: amazon_share/google_picker/immich/folder, config) · `photo_item` (source_id, remote_id, taken_at, w, h, orientation, location, people[], blob_refs) · `photo_collection` (name, rules JSON, schedule) · `photo_state` (hidden, favorite) |
| Weather | `weather_snapshot` (Hub-written; current, hourly, daily, alerts JSON, sources, fetched_at). Read-only on devices. |
| Home & devices | `home_layout` (role, orientation, widgets JSON) · `timer` (label, duration, started_at, paused_at, device_scope) · `ha_tile` (entity_id, kind, room, kid_safe) |
| System | `integration_account` (**Hub-only, never synced**: provider, encrypted secrets, health) · `op_log` (Hub) · `sync_state` (device cursor) · `audit_log` (append-only) |

### 8.3 Conventions

- **IDs:** UUIDv7 (time-sortable) for user-created rows. **Deterministic
  UUIDv5** for rows with a natural key, so two devices creating "the same"
  row converge on one ID. Examples: `chore_instance` = v5(chore_id, date,
  profile_id); `shopping_item` derived from the plan = v5(name_norm, unit
  dimension, period).
- **Time:** instants are stored UTC (ISO-8601). Local dates are
  `YYYY-MM-DD` in the household timezone. Recurrence uses RFC 5545 RRULE
  with an explicit TZID. All-day events never shift across zones.
- **Sync columns on every synced table:** `id`, `_hlc` (JSON map field →
  HLC of last write), `_row_hlc` (max HLC), `_seq` (Hub sequence of last
  applied op), `deleted` (tombstone flag, itself an LWW field).
- **Ordering:** fractional-index `sort_key` strings, so concurrent reorders
  converge and moving one item writes one row.
- **Money and counts:** never stored as mutable counters. Balances are sums
  over append-only ledgers.

### 8.4 Sync protocol (v1)

#### 8.4.1 Clocks
Each node (device or Hub) keeps a **Hybrid Logical Clock**: 48-bit physical
ms + 16-bit counter, tie-broken by `node_id`. The encoding is a fixed-width,
lexically sortable string `"{ms:012x}{ctr:04x}-{node}"`. On receiving
remote ops a node advances its clock (standard HLC receive rule). The Hub
rejects ops more than 10 minutes in the future and flags that device's clock
in diagnostics.

#### 8.4.2 Operations
```json
{
  "op": "0192f4c4-…",                // UUIDv7, idempotency key
  "t": "event",                      // table
  "id": "0192f4c1-…",                // row id
  "k": "upsert",                     // upsert | insert_only | delete
  "f": { "title": "Swim lesson", "start": "2026-10-03T23:30:00Z" },
  "h": "019a3b7c2f10-0003-dev7",     // HLC
  "a": "profile:mom",                // actor (optional; required for gated ops)
  "v": 3                             // schema major version
}
```
**Merge rule (field-level LWW):** for each field `f`, apply the incoming
value iff `op.h > row._hlc[f]`. Deletes set `deleted=true` with an HLC like
any field. Because ties are impossible (the node id breaks them), every
node converges to the same state regardless of arrival order.

#### 8.4.3 Exchange
- **Push:** the device sends batches of unacknowledged ops (≤ 500 per batch)
  over the WebSocket. The Hub authenticates, validates (schema, ACL, gated
  actions, value constraints), assigns a monotonic `seq`, appends to
  `op_log`, merges into its materialized tables, and acks. **Rejected ops
  return a reason**; the device rolls back the optimistic local change and
  shows a non-blocking toast.
- **Fan-out:** accepted ops are broadcast to every connected device whose
  scopes match (§8.5), typically within 100 ms on the LAN.
- **Pull:** on (re)connect, the device sends `since=<last seq>` and receives
  missed ops page by page, then switches to live mode.
- **Offline:** devices queue ops durably (an outbox table) and work fully
  offline. Nothing user-entered is ever dropped silently.

#### 8.4.4 Special cases
| Case | Rule |
|---|---|
| Append-only tables (`ledger_entry`, `game_progress`, `audit_log`, `feeling_entry`) | `insert_only` ops. The Hub rejects updates to these tables. No conflicts possible. |
| Natural-key rows (chore instances, derived shopping items) | Deterministic v5 IDs; concurrent creation merges field-wise |
| Approvals and grants (approve chore, redeem reward, adjust stars) | Gated ops: must carry an actor with an adult role and come from a device whose role allows it. The Hub verifies, and the ledger entry is written **by the Hub** as a consequence, so balances can't be forged by a kid-room device. |
| Integration-owned fields (Google `etag`, `remote_id`, sync metadata) | Written only by the Hub node. The Hub rejects device writes to them. |
| Edits to Google-backed events | A device edit syncs to the Hub; the Hub's Google worker pushes it upstream (outbox) and writes back etag/ids (§13.2). |
| Clock skew | HLC tolerates skew; displays rely on Android network time. Diagnostics flag > 2 min drift. |

#### 8.4.5 Schema evolution
Ops carry a schema **major** version. The Hub refuses sync from older majors
with `426 Upgrade Required`; the device then shows an "Update needed" card
(§10.17). Minor versions only add nullable fields and tables, which older
clients ignore.

#### 8.4.6 Bootstrap & compaction
A new or wiped device downloads a **scoped snapshot**: a SQLite file
generated by the Hub at seq *S* for the device's scopes. It then pulls from
*S*. The Hub keeps `op_log` for 30 days (configurable). A device offline
longer than that re-bootstraps automatically.

#### 8.4.7 Blobs
Rows reference blobs as `{sha256, mime, w, h, bytes}`. Devices fetch
`GET /api/blobs/{sha}?v=<variant>` on demand and cache them LRU. Kiosk
displays **prefetch** what the next hours will need: upcoming screensaver
photos, today's recipe images, kid-chart photos and voice clips. Uploads
(phone photo, voice recording, drawing) go to `POST /api/blobs`, then the
referencing row syncs as an op.

#### 8.4.8 Verification
Property-based tests in `dearth_core` generate random op streams across
three simulated nodes with random delivery order, duplication, offline gaps
and clock skew. They assert identical materialized state, no lost
`insert_only` rows, and no resurrected deletes (§16.1).

### 8.5 Scopes (what each device receives)

| Scope | Contents | Devices receiving it |
|---|---|---|
| `household` | Calendar, meals, lists marked family, chores, photos metadata, weather, layouts | All paired devices |
| `adult` | Adult-only lists, approval queues, feelings reports, audit log, integration health | Adult-role personal devices; shared displays (content hidden until grown-up mode, §9.3) |
| `profile:<id>` | Private lists and notes of one profile | That profile's personal devices only |
| `kid_safe` | Subset for kid-room devices: kid profiles, routines, music tiles, toybox, kid-visible events | Kid-room role (never receives `adult` or other profiles' private scopes) |

### 8.6 Ephemeral (non-op-log) channels
Some data streams through the WebSocket without entering `op_log`: Home
Assistant entity states, live timer ticks (devices compute these locally
from `started_at`), device presence and performance heartbeats, remote
commands (wake, sleep, screenshot, reload, play chime), and recipe search
results. Recipe results are fetched on demand and persisted only when saved.

### 8.7 Backups & export
- Nightly Hub snapshot: SQLite online backup API, or a `pg_dump` hook for
  Postgres. Keep 14 dailies + 8 weeklies under `/data/backups`. A
  pre-migration snapshot is taken on every schema upgrade.
- One-click **export** (admin): household JSON (all tables) + blobs zip.
  **Import** restores into a fresh Hub, or promotes a Solo device to a Hub.
- Restore drill documented in `docs/backup.md` and tested in CI.

---

## 9. Identity, roles, security & privacy

### 9.1 Household, profiles & roles
- One household per Hub (v1).
- Profiles: `adult`, `child`, `caregiver`, `guest`, `pet`. Pets can have care
  tasks but no stars.
- Adults have a **PIN** (4–6 digits). The Hub stores an Argon2id hash, with parameters tuned
  so one verification takes ≤ 300 ms on T1. The hash syncs to shared displays
  so they can verify offline, with rate-limited attempts (30 s lockout after
  5 failures).
- Kids have a **stage** (`little` 2–3, `preschool` 3–4, `prek` 4–5) that
  tunes their UI and reward mechanics (§10.7). Dearth suggests a stage
  change around birthdays.

### 9.2 Devices & pairing
- **Pairing:** the new device shows a QR code (Hub URL + one-time code) and a
  6-character code. An adult approves it in the companion or web admin,
  picking name, role, orientation and screen size. The device receives a
  revocable bearer token.
- **Roles:** `kitchen` (full experience), `kid_room`, `entry`, `personal`
  (phone or desktop), or `custom`. A role sets navigation, home layout,
  scopes, screensaver defaults, schedules and lock defaults (§10.12).
- Tokens are stored in Android Keystore / iOS Keychain-backed storage on
  phones and tablets, and in the app-private database on web, desktop and
  kiosk Linux (no WebCrypto on LAN http; kiosks rarely run a keyring).
  Revoking a token in the admin immediately disconnects the device.

### 9.3 Grown-up mode & toddler safety
- Shared displays default to **family mode**. Adult actions (settings,
  delete, approvals, editing other people's items, private or adult content,
  integrations) require **grown-up mode**: PIN entry, auto-relock after
  2 minutes idle, and a visible lock indicator.
- **Kid surfaces** (Toybox, Music, routines, kid chart, kid-room role)
  contain no destructive actions at all. Their settings live behind a
  "grown-up corner": a 3-second hold on a small corner glyph, then PIN.
- **Toddler lock** pins the display to one kid surface (Toybox, Music, a
  routine). It suppresses navigation, edge swipes and notifications, and
  exits only via the grown-up corner.
- **No open web from kid areas.** The YouTube player is curated-IDs only,
  with related-video navigation blocked and logo/title links covered by a
  touch-absorbing layer (§13.7).
- FreeKiosk's way out (a magic corner tapped 5 times, then a PIN) can't be
  passed by toddler taps, so they can't escape the app (§15.1).

### 9.4 Remote access & web security
- The Hub serves LAN clients and, through the owner's HTTPS domain, remote
  phones. Every API call needs a device token or an admin session.
- Admin web login: password + TOTP, **or** trusted reverse-proxy SSO headers
  (Authelia, Authentik). Passkeys are planned for `[M5]`.
- Rate limiting on auth, pairing and PIN endpoints. CSRF protection for
  cookie sessions. Same-origin CORS. Strict CSP on the web app. Security
  headers.
- LAN devices may use the HTTPS domain via split-horizon DNS (recommended)
  or `http://<lan-ip>`. Android's network security config permits cleartext,
  because the Hub's LAN address is chosen at pairing time (and FreeKiosk's
  bridge is on `127.0.0.1`); remote access uses the HTTPS domain.

### 9.5 Secrets
Integration credentials (Google refresh tokens, WU key, Spotify tokens,
Immich key, HA token, Spoonacular key) live **only on the Hub**. They are
encrypted at rest with AES-256-GCM under a master key from `DEARTH_SECRET_KEY`
or a secret file, are never synced to devices, and are redacted from logs and
exports. Export includes them only when the admin explicitly opts in, and
then encrypted.

### 9.6 Privacy posture
- No telemetry, analytics or third-party crash reporting. Crash and
  performance reports go to the family's own Hub only.
- Outbound network calls go only to providers the family configured.
- **Amazon shared-album links are unlisted but public:** anyone with the URL
  can view that album. The setup flow says so plainly and recommends a
  dedicated "Dearth Frame" album (§13.5.1).
- Kids' data (feelings, game progress, artwork) never leaves the Hub unless
  an adult explicitly shares or exports it.

---

## 10. Feature specifications

### 10.1 Home & dashboard (`FR-HOME`)

**Purpose.** The first screen every display shows: today at a glance,
tailored to the device's role and orientation.

- **FR-HOME-01 [M1]** Home is a **widget grid** defined per device role and
  orientation (`home_layout`). Shipped templates: Kitchen-L, Kitchen-P,
  Kid-room, Entry, Phone.
- **FR-HOME-02 [M1]** Widget catalog (v1): Clock & date · Weather (compact
  and expanded) · Today agenda · Up next (with countdown) · Week strip ·
  Tonight's dinner / today's meals · Chores progress (avatar rings) · Kid
  chart (stage-aware) · Shopping list preview · Notes & announcements ·
  Countdowns · Photo tile · Timers. Later: HA tiles **[M4]**, Who's home
  **[M4]**, Birthdays **[M2]**, Bin day **[M2]**, Air quality **[M4]**,
  Wi-Fi QR ★ **[M2]**.
- **FR-HOME-03 [M2]** **Edit Home** (grown-up mode): drag, resize on grid
  snap, add and remove widgets, per orientation. Saved layouts sync to
  every device with that role.
- **FR-HOME-04 [M1]** Header bar: date, time, current weather and alert
  badge, sync/offline indicator (subtle; only shown when degraded), grown-up
  lock state.
- **FR-HOME-05 [M1]** Every widget opens its full screen in one tap and has
  a designed empty state that invites setup ("Connect a calendar").
- **FR-HOME-06 [M2]** ★ **Morning briefing:** during a configurable morning
  window, the first wake shows a full-screen card: greeting, weather +
  "what to wear", today's events, dinner, kid's first routine. Dismiss with
  a tap.
- **FR-HOME-07 [M1]** Rendering: widgets are independent repaint
  boundaries. The clock ticks on minute boundaries, or seconds only when the
  seconds style is enabled. Nothing else repaints when idle (§12).

### 10.2 Calendar (`FR-CAL`)

**Purpose.** Everyone's schedule in one color-coded place. Editable from the
wall, synced two-way with Google, and legible for a pre-reader.

**Sources & sync**
- **FR-CAL-01 [M1]** Sources: **Google** (two-way; multiple accounts, e.g.
  both parents), **ICS URL** (read-only: school, daycare, sports, holidays),
  **Local** (Dearth-only). **[M5]** CalDAV (iCloud, Fastmail, Nextcloud) and
  Microsoft 365.
- **FR-CAL-02 [M1]** Per calendar: on/off, color, default profile(s), which
  device roles show it (e.g. kid room shows only the family and Ava
  calendars), and whether it is the default target for new events.
- **FR-CAL-03 [M1]** Google changes appear within 15 s via push channels,
  with polling as a fallback. Edits from Dearth reach Google within 5 s when
  online and are queued otherwise (§13.2).
- **FR-CAL-04 [M2]** ★ Offer to create a shared **"Family" Google calendar**
  during setup so events created on the wall land somewhere both parents
  see them.

**Views** (all available in both orientations; landscape defaults to Week,
portrait to Agenda)
- **FR-CAL-05 [M1]** **Day:** hour grid with an all-day lane and a now-line.
  Overlapping events are laid out side by side.
- **FR-CAL-06 [M1]** **3-day** and **Week:** time grid with weather on each
  day header (icon, high/low) and swipe paging.
- **FR-CAL-07 [M1]** **Month:** event chips per day ("+3" overflow); tap a
  day to open a day sheet.
- **FR-CAL-08 [M1]** **Agenda:** continuous list grouped by day, sticky day
  headers, infinite scroll in both directions.
- **FR-CAL-09 [M2]** **People:** one column per profile for the selected day
  or 3 days. This is the family "who's where" view.
- **FR-CAL-10 [M3]** **Kid timeline:** a picture timeline for pre-readers.
  Big icons in time-of-day bands (morning, afternoon, evening), a moving
  "now" marker, and a sun or moon cue.
- **FR-CAL-11 [M1]** Profile filter chips (multi-select) persist per device.
  Multi-person events show stacked avatars and a striped color edge.

**Create & edit**
- **FR-CAL-12 [M1]** **Quick add** in natural language ("Swim Saturday 9am
  Ava", "Dentist tue 3:30 mom 1h"), parsed deterministically with a live
  preview chip before saving.
- **FR-CAL-13 [M1]** Full editor: title, icon or emoji (auto-suggested),
  date and time or all-day, duration, recurrence (presets + custom RRULE
  builder), people, calendar, location, notes, reminders, countdown toggle.
  Recurring edits offer *this event / this and following / all events*.
- **FR-CAL-14 [M2]** Long-press and drag to move an event, drag the bottom
  edge to resize (grown-up mode), with 15-minute snapping and haptic and
  visual feedback.
- **FR-CAL-15 [M1]** **Auto-icons:** a keyword map (Appendix F) gives events
  an emoji or icon ("swim" → 🏊, "dentist" → 🦷, "birthday" → 🎂). Users can
  override per event, and a learned override applies to future events with
  the same title.

**Smart extras**
- **FR-CAL-16 [M1]** **Up next** card with a live countdown ("Swim in
  45 min") and conflict warnings (the same person double-booked).
- **FR-CAL-17 [M1]** **Countdowns:** any event can be flagged. The
  kid-friendly form counts sleeps ("3 sleeps until Grandma!") with moon
  icons.
- **FR-CAL-18 [M2]** **Birthdays & holidays:** profile birthdays, Google
  birthday events, and a regional public-holiday calendar (bundled or
  Nager.Date).
- **FR-CAL-19 [M2]** **Weather on events:** events within 7 days that have a
  location or outdoor keyword show forecast icon and temperature for their
  time and place (Skylight parity).
- **FR-CAL-20 [M2]** **On-display reminders:** chime + banner N minutes
  before (per event or per calendar). Kid-addressed reminders use the
  child's name and icon ("Ava, time for shoes, swim soon!"), voiced when a
  clip or TTS is available (§13.8).
- **FR-CAL-21 [M4]** ★ **Leave-by:** for events with an address, compute
  travel time (HA Waze integration or OpenRouteService) and show "Leave by
  5:05".
- **FR-CAL-22 [M5]** ★ Read-only **share link** for grandparents or a
  babysitter: a scoped week view served by the Hub, revocable.
- **FR-CAL-23 [M1]** Performance: recurrences are expanded into a local
  instance cache (window −60 d … +400 d) on the database isolate. Week and
  day layouts are precomputed per visible range. Scrolling only translates
  cached layers (§12.3).

### 10.3 Weather (`FR-WX`)

**Purpose.** "What's it like outside, and what do I need?" Hyperlocal from
the family's own station when available; complete without a key.

**Data sources & merging** (details in §13.4)
- **FR-WX-01 [M1]** **Station mode (WU key + station ID):** current
  conditions from the family's PWS (temperature, feels-like, wind and gust,
  humidity, pressure, rain rate, **rain so far today**, UV, solar
  radiation). Optionally the WU 5-day forecast for days 1–5.
- **FR-WX-02 [M1]** **Keyless mode (default fallback):** Open-Meteo for
  current, **hourly (48 h)** and **daily (10 days)**; NWS for US alerts and
  nearest official observations. Location by ZIP/postcode, city, or map pin.
- **FR-WX-03 [M1]** Merge policy:
  - Current = PWS if fresh (≤ 15 min), else NWS observation, else Open-Meteo.
  - Days 1–5 = WU when "Use WU forecast" is on, else Open-Meteo.
  - Days 6–10 and all hourly data = Open-Meteo.
  - Alerts = NWS (US).
  - Each tile shows its data age; the detail view names its source.
- **FR-WX-04 [M1]** Station selection: by **station ID**, or **pick from a
  map or list of nearby stations** (WU location API, requires key). A ZIP
  sets the forecast location even when a station is used for current
  conditions.

**Presentation**
- **FR-WX-05 [M1]** Home widget: big current temperature, condition icon,
  feels-like, high/low, today's rain chance, a 12-hour strip, and an alert
  badge.
- **FR-WX-06 [M1]** **Weather screen:**
  - **Now:** "In our backyard" card from the PWS, with rain today and wind
    gusts.
  - **Next 24–48 h:** a combined chart with a temperature line and icons,
    rain-probability bars labelled with amounts, a **sunshine band** (minutes
    of sun per hour), a UV band and wind arrows.
  - **Rain summary** sentence ("Rain likely 3–7 PM, about 0.3 in").
  - **10 days:** high/low range bars, icon, rain % and amount, **sunshine
    hours**, max UV and wind. Tap a day for its hours plus the WU narrative.
  - **Sun & moon:** sunrise/sunset arc, daylight length, moon phase.
  - **Alerts:** severity-colored banner with full text.
- **FR-WX-07 [M3]** ★ **What to wear:** a dress-up character (the child's
  buddy) wears today's outfit, chosen by rules over feels-like temperature,
  rain, wind and UV: coat, hat, mittens, raincoat and boots, sunglasses, sun
  hat, sunscreen reminder. It appears on the morning briefing, the kid room
  and the Entry role.
- **FR-WX-08 [M1]** Units (°F/°C, in/mm, mph/km/h), 12/24 h, and an icon set
  that works for kids and adults (one family of icons, day and night
  variants).
- **FR-WX-09 [M1]** Resilience: the Hub caches the last good data per
  source. Devices show stale data with "as of 7:42" rather than empty
  states, and severe alerts stay visible until they expire.
- **FR-WX-10 [M4]** Air quality (US AQI) and pollen where available.

### 10.4 Photos & screensaver (`FR-PHO`, `FR-SSV`)

**Purpose.** Turn idle time into a family photo frame using photos from
wherever they already live, with curation that's easy from a phone or the
wall.

**Sources** (details in §13.5)
- **FR-PHO-01 [M1]** **Amazon Photos shared album:** paste a share link. No
  Amazon credentials are ever requested. New photos added to the album
  appear within an hour.
- **FR-PHO-02 [M1]** **Folder / NAS:** one or more paths mounted into the
  Hub container (SMB/NFS mounts are handled by the host), rescanned
  periodically.
- **FR-PHO-03 [M3]** **Immich:** server URL + API key. Supports albums,
  favorites, people and **memories** (on this day), and random sampling
  without enumerating the library.
- **FR-PHO-04 [M3]** **Google Photos (Picker):** "Pick photos" creates a
  picker session. The display shows a QR code; an adult picks up to 2,000
  photos on a phone; the Hub imports them. Google no longer allows
  auto-updating albums for third-party apps (§13.5.2).
- **FR-PHO-05 [M2]** **From phones** ★: the companion's share target ("Send
  to Dearth") uploads photos straight into a "From phones" collection.
- **FR-PHO-06 [M3]** **Kid art:** saved Toybox paintings form an "Ava's art"
  collection that can join the screensaver ★.

**Curation**
- **FR-PHO-07 [M1]** Photos screen: a browsable grid per source (albums,
  people, folders), multi-select, and include/exclude toggles. **Hidden**
  and **favorite** marks sync across devices.
- **FR-PHO-08 [M2]** **Collections:** named sets built from manual picks
  plus rules (source/album, date range, favorites, people, orientation, "on
  this day"). Collections can be scheduled ("Halloween" in October; "Family
  favorites" by default) and assigned per device role.
- **FR-PHO-09 [M1]** Long-press a photo on the screensaver (grown-up mode) to
  hide it everywhere, favorite it, or show its source and date.

**Screensaver**
- **FR-SSV-01 [M1]** Starts after a **configurable idle timeout** (per
  device; default 5 min; separate night value), or manually from the nav
  rail. Any touch wakes to the previous screen. A first touch never
  triggers the control underneath it.
- **FR-SSV-02 [M1]** Shows each photo for a configurable time (10–120 s,
  default 30 s). Shuffle without repeats until the pool is exhausted, with
  recent-history suppression.
- **FR-SSV-03 [M1]** Transitions: **crossfade** (default on every tier),
  plus **slow Ken Burns** pan/zoom on T2+, or on T1 only if the M0 benchmark
  passes.
- **FR-SSV-04 [M1]** **Orientation-aware layout:** in landscape, two
  portrait photos taken near each other are **paired** side by side. Single
  mismatched photos get a **pre-blurred background** generated by the Hub,
  so no runtime blur is needed. Photos are never stretched or awkwardly
  cropped (focus point from EXIF or face data where available).
- **FR-SSV-05 [M1]** Overlays (each toggleable): clock and date, current
  weather, next event, and a photo caption ("July 2024 · Lake Dillon" /
  "3 years ago today"). Overlays sit on a gradient scrim and slowly drift a
  few pixels to avoid uneven panel aging.
- **FR-SSV-06 [M1]** Offline guarantee: each display keeps at least the next
  200 photos (configurable) cached as display-sized derivatives. The
  screensaver never shows a blank screen. Fallback order: cached pool →
  bundled art pack → clock face.
- **FR-SSV-07 [M2]** Ambient alternatives: **clock face** styles (big
  digital, analog for learning time, word clock), "calendar glance"
  (photo + agenda strip), and **night clock** (dim, warm).

### 10.5 Meals, recipes & shopping (`FR-RCP`, `FR-MEAL`, `FR-SHOP`)

**Purpose.** Answer "what's for dinner?" from discovery through plan,
shopping and cooking, and make each next choice easier by reusing what's
already on the list.

**Recipe sources** (details in §13.6)
- **FR-RCP-01 [M2]** Providers behind one `RecipeProvider` interface:
  - **TheMealDB** (free baseline; optional supporter key for V2
    multi-ingredient filters and random sets).
  - **Spoonacular** (optional key; popularity sort, by-ingredients, similar
    recipes, diets; the free tier is ~50 points/day, so cache aggressively).
  - **Import from any URL** (schema.org `Recipe` JSON-LD or microdata,
    parsed on the Hub; works with most major recipe sites; also the
    companion's "Share to Dearth").
  - **Family recipe box** (hand-entered or edited).
  - **[M5]** Mealie/Tandoor connectors and AI suggestions.
- **FR-RCP-02 [M2]** Every result is normalized into one recipe model:
  structured ingredients (quantity, unit, normalized name, preparation,
  confidence), steps, times, servings, image, tags, diets and source
  attribution (§13.6). A recipe is copied into the family box when saved or
  planned, so the plan never breaks if a provider disappears.

**Discovery**
- **FR-RCP-03 [M2]** **Search:** text with typo tolerance; filters for
  cuisine, meal type, diet, **allergens (hard exclusions)**, max total
  time, equipment (air fryer, slow cooker, Instant Pot), and include/exclude
  ingredients.
- **FR-RCP-04 [M2]** **Discover feeds:**

  | Feed | Source |
  |---|---|
  | **Popular this week** | Spoonacular popularity; TheMealDB latest |
  | **Surprise me** | Random, with a playful card-shuffle reveal |
  | **Quick weeknights** (≤ 30 min) | Provider filters |
  | **Toddler-approved** | Family ratings + kid-friendly tags and heuristics |
  | **In season now** | Bundled produce calendar for the household's region |
  | **Cuisine passport** ★ | Pick a country on a map |
  | **Family favorites** | Most cooked, highest rated |
  | **Haven't had in a while** | Plan history |
  | **Use it up** | Choose ingredients you have |
  | **Pairs with your plan** | Ingredient overlap (FR-RCP-09) |

- **FR-RCP-05 [M2]** **Recipe card:** image, title, total time, servings,
  diet icons, family rating, and **plan badges** ("uses 4 of your
  ingredients · +3 new").
- **FR-RCP-06 [M2]** **Recipe detail:**
  - **Servings stepper** rescales every ingredient live, with friendly
    fractions (⅓, ¾), smart rounding (1.33 cups → 1⅓ cups; eggs round up
    with a note) and US/metric toggle.
  - Actions: *Add to plan* (date, slot, servings), *Add ingredients to
    list* (without planning), *Save*, *Rate* (each family member gives an
    emoji 😋🙂😐🙅, kids included), and notes ("used less salt").
- **FR-RCP-07 [M2]** **Cook mode:** large type, step by step, screen kept
  awake, and **timers auto-detected** from step text ("bake 25 minutes" →
  tap-to-start chip). Ingredients needed for the current step are
  highlighted, and the screensaver is suppressed.

**Planning**
- **FR-MEAL-01 [M2]** Planner grid: days × slots (breakfast, lunch, dinner,
  snack; configurable). Drag recipes from search, the recipe box or
  favorites into slots. Entries can also be free text ("Eat out",
  "Leftovers").
- **FR-MEAL-02 [M2]** **Planning period:** any date range (e.g. "next 5
  dinners" or Sun–Sat), shown as a summary bar: recipes, new ingredients,
  overlap score.
- **FR-MEAL-03 [M2]** Per-entry servings (default household size, with
  optional per-member opt-outs) and **leftovers** ★ ("cook once, eat twice"
  marks a later slot as leftovers of an entry; leftovers add no shopping
  items).
- **FR-MEAL-04 [M2]** Copy last week, save and apply **templates** ("school
  week"), and repeat favorite entries.
- **FR-MEAL-05 [M2]** Home shows tonight's dinner (photo), with tomorrow's
  dinner peeking.

**Shopping list**
- **FR-SHOP-01 [M2]** **Consolidated list** generated for the planning
  period. Ingredients merge only when normalized names match with high
  confidence **and** units are convertible within one dimension (volume,
  weight, count). Totals display in the friendliest unit.
- **FR-SHOP-02 [M2]** Each item shows its **sources** ("for Tacos (Tue),
  Chili (Thu)"). Excluding a recipe from the period removes its
  contribution.
- **FR-SHOP-03 [M2]** **Pantry staples** (salt, oil, flour…) are excluded or
  shown as "check you have". A one-tap "Have it" hides an item for this
  period.
- **FR-SHOP-04 [M2]** Manual items, quantities and notes. Items are grouped
  by **aisle category** in a customizable store order. Checked state
  survives regeneration when the quantity didn't change.
- **FR-SHOP-05 [M2]** Phone UI for in-store use: offline-safe, big
  checkboxes, a sort-by-aisle toggle, and checks syncing live to the wall.
- **FR-SHOP-06 [M4]** Optional mirror to a **Home Assistant to-do list**
  (so "add milk" through HA Assist works) and Google Tasks.

**Plan-aware recommendations** ("find recipes with similar ingredients")
- **FR-RCP-09 [M2]** Once at least one recipe is planned, Discover shows a
  **"Pairs with your plan"** row and a "Complete my plan" action. Candidates
  are scored locally (algorithm ported from `../dearth_webapp/MEALS.md` §13–§15):
  - `+` **overlap with perishable ingredients** already being bought (weighted
    by perishability and leftover package fraction, e.g. "uses the other
    half bunch of cilantro").
  - `+` overlap with pantry-type ingredients (low weight).
  - `−` **penalty per new ingredient**.
  - `+` family preference (ratings, cuisines liked).
  - variety constraints (protein and cuisine diversity across the period).
  - hard filters: allergens and diets.
- **FR-RCP-10 [M2]** Every recommendation explains itself in one line ("Uses
  your cilantro, limes and black beans · adds 2 items"). Tapping the
  explanation highlights those ingredients.
- **FR-RCP-11 [M2]** The candidate pool combines cached recipes, the family
  box, and provider by-ingredient queries for the plan's top 3 perishables
  (budgeted per day for Spoonacular).

**Ingredient knowledge base**
- **FR-RCP-12 [M2]** A bundled, versioned dataset (~1,500 ingredients):
  canonical names, synonyms and plurals, aisle category, perishability
  (days), typical package sizes, and densities for common volume↔weight
  conversions. The parser handles "2 ½ cups all-purpose flour, sifted",
  ranges ("2–3 cloves"), and "to taste". Unparsed lines are kept verbatim
  and never merged.

### 10.6 Lists, notes & household helpers (`FR-LIST`, `FR-NOTE`, `FR-HH`)

- **FR-LIST-01 [M1]** Lists of kind shopping, to-do, packing and custom.
  Checklist and **board** views (columns per assignee or category).
  Drag to reorder. Assign items to a profile. Lists can be family, adult or
  private (§8.5).
- **FR-LIST-02 [M2]** **Templates** ★: daycare bag, swim bag, beach day,
  vacation packing. Instantiate as a fresh checklist.
- **FR-LIST-03 [M2]** **Google Tasks sync** (owner's choice; Google Keep has
  no API for personal accounts): any list mirrors the Google task list of
  the same name, two ways, through the Hub. Additions, ticks, edits and
  deletions travel both ways; per item the side that changed last wins,
  and on the first sync items with the same words are linked, not
  doubled. Tasks has no push, so the Hub polls every 3 minutes; an edit on
  a display syncs at once.
- **FR-NOTE-01 [M1]** **Sticky notes & announcements:** color, optional
  target profiles or devices, start and expiry. Announcements appear as a
  Home banner and can chime once.
- **FR-NOTE-02 [M2]** ★ **Doodle notes:** draw a quick note on the wall
  ("Love you! ❤"). Strokes are stored as vectors, rendered once to a blob,
  and pinned to the board.
- **FR-NOTE-03 [M3]** ★ **Voice notes:** record on a phone, play on the wall
  ("Message from Daddy" with avatar).
- **FR-HH-01 [M2]** ★ **Bin day & recurring reminders:** icon reminders
  ("🗑️ Trash out tonight") on Home the evening before, dismissible by
  anyone.
- **FR-HH-02 [M4]** ★ **Pet care log:** one-tap logging ("Fed Biscuit 7:32
  AM · Dad") with the last-done time shown prominently, preventing
  double-feeding. Includes medication schedules.
- **FR-HH-03 [M4]** ★ **Guest & babysitter mode:** a curated screen with
  emergency contacts, allergies and medical notes per child, bedtime
  routine steps, house Wi-Fi QR code, "where things are" notes, and parents'
  ETA. Private data is hidden while it's on. Turned on from the companion
  or in grown-up mode.

### 10.7 Chores, routines & rewards (`FR-KID`)

**Purpose.** A chore chart that a 2.5-year-old can run, that grows into a
real responsibility and reward system by age 5, and that also handles the
adults' household chores.

#### 10.7.1 Kid stages

| Stage | Ages | Chart UI | Reward mechanics | Text vs. voice |
|---|---|---|---|---|
| **Little** | 2–3 | 3–4 huge photo cards, one tap "I did it!", celebration every time | Stickers (pick and place), reward jar; no numbers | Voice and picture only |
| **Preschool** | 3–4 | Up to 6 cards, visual routines she runs herself, timers | Stickers + jar + first stars; surprise rewards | Voice first, single words |
| **Pre-K** | 4–5 | Full chart, routines, simple streaks (with grace days) | Star economy with a **pinned goal** and reward store | Words + voice |

Adults and older kids use the standard chore list: points optional, rotation
fairness, reminders.

#### 10.7.2 Chores
- **FR-KID-01 [M3]** Chore: title, **photo or illustration**, **parent-recorded
  voice prompt** (or TTS, §13.8), schedule (RRULE: daily, weekdays, specific
  days, every N days), time window (morning or evening), assignees or
  **Anyone pool**, reward spec (stars, sticker, jar token), approval
  required (yes/no), stage visibility.
- **FR-KID-02 [M3]** Materialization: chore instances for today + 6 days.
  IDs are deterministic, so any device can materialize them offline and
  still converge (§8.3).
- **FR-KID-03 [M3]** Completion: a big "I did it!" tap triggers a
  **celebration** (buddy dance, sound, sticker or star flying to the
  jar/bank). Undo is available for 30 s. If approval is required, the card
  shows "Waiting for grown-up 👀" and approval happens in grown-up mode on
  any device, or by actionable phone notification (§10.14).
- **FR-KID-04 [M3]** Ships with an age-sorted **chore library** (Appendix C):
  "Put toys in the bin", "Shoes in the basket", "Feed Biscuit (with
  grown-up)", "Wipe the table", "Water the plants"… Each comes with a
  bundled illustration and a suggested voice line.
- **FR-KID-05 [M3]** Adult household chores: rotation (round-robin or
  least-recently-done), "Anyone" with claim, due reminders, a weekly
  fairness view.

#### 10.7.3 Visual routines
- **FR-KID-06 [M3]** Routines (morning, bedtime, clean-up, daycare
  departure) are ordered picture steps with an optional **visual timer**
  (red-disc countdown, Time-Timer style) and an optional **song** per step.
- **FR-KID-07 [M3]** Run mode: full screen, the current step large and
  centered with its voice prompt, and a **progress path** (the buddy hops
  along stepping stones toward the bed or sun). Completing a step gives a
  small celebration; the whole routine gives a big one. Stray taps can't
  break state.
- **FR-KID-08 [M3]** ★ **Clean-up song challenge:** the tidy step plays a
  song; "Can you finish before the song ends?"
- **FR-KID-09 [M3]** ★ **First–Then board:** two big cards ("First: brush
  teeth → Then: story"), one tap to switch, used ad hoc by parents. A
  classic early-childhood tool.
- **FR-KID-10 [M3]** ★ **Choice boards:** parents offer 2–3 picture choices
  ("Which pajamas?", "Which book?"). Building autonomy defuses toddler
  power struggles.
- **FR-KID-11 [M3]** Templates: morning, bedtime, potty, daycare
  drop-off, bath, tidy-up, with bundled art.

#### 10.7.4 Rewards that work for toddlers
- **FR-KID-12 [M3]** **Sticker book:** each completion earns a sticker she
  **chooses** and **places** anywhere on a themed scene (farm, ocean,
  space, dinosaurs). This combines choice, fine-motor practice and a
  visible collection. Finished pages are kept in a book she can flip
  through.
- **FR-KID-13 [M3]** **Reward jar:** pom-poms or marbles fill a jar. A full
  jar triggers a **surprise reveal** (a gift box opens) showing one reward
  from a parent-curated list (park trip, pancake breakfast, new book).
- **FR-KID-14 [M3]** **Star economy** (pre-K): append-only ledger, reward
  store with costs, **pinned goal** with a progress ring around her avatar,
  and redemption requests approved by an adult with a full-screen
  celebration.
- **FR-KID-15 [M3]** ★ **Family team goal:** every family member's
  completions fill a shared jar toward a family reward (zoo trip). This is
  cooperative rather than competitive, and works well when siblings arrive.
- **FR-KID-16 [M3]** ★ **Kindness hearts:** adults award hearts for kind
  acts (sharing, helping), not just chores. They show as a separate,
  celebrated counter.
- **FR-KID-17 [M3]** ★ **Growing garden:** each completion waters a plant
  that grows through the week and blooms on the weekend. This gives
  long-horizon progress without numbers.
- **FR-KID-18 [M3]** **Potty chart template** (likely relevant at 2.5):
  one-tap sticker + extra-big fanfare, with optional parent approval.
- **FR-KID-19 [M3]** ★ **Proud wall:** a gallery of her artwork, sticker
  pages and parent photos of finished tasks (taken on the phone). It can
  feed the screensaver.
- **FR-KID-20 [M3]** Celebrations come from a **catalog** (confetti, buddy
  dance, fireworks, star shower, bubbles), randomized so they never repeat
  twice in a row. The bedtime variant is calm (soft sparkles, quiet chime).
  All respect mute and reduced-motion settings.
- **FR-KID-21 [M3]** Design guardrails: praise effort ("You did it
  yourself!") over totals, use surprise rewards sparingly, **no streak
  pressure for Little/Preschool**, and **no loss mechanics** (nothing is
  ever taken away from a toddler's collection).

#### 10.7.5 Feelings & buddy
- **FR-KID-22 [M3]** **Buddy:** each child picks a buddy character (bunny,
  dino, unicorn, puppy, robot). It appears in celebrations, the progress
  path, What-to-wear and the morning greeting.
- **FR-KID-23 [M3]** **Feelings check-in** (Preschool+): a face grid with
  voiced labels, embeddable as a routine step. A parent-only report shows
  patterns over time (Hearth parity). Never shown on shared Home screens.

### 10.8 Toybox (`FR-TOY`)

**Purpose.** A safe, ad-free, offline play space with games that *stretch
her thinking* from age 2 to 5, adapt to her level, and respect family limits.

- **FR-TOY-01 [M3]** **Launcher:** big illustrated square tiles (six across
  on a landscape wall, four on a portrait one, two on a phone), no reading
  required, filtered to the child's stage, with a "new!" sparkle on recently
  unlocked games. A grown-up corner leads to settings.
- **FR-TOY-02 [M3]** **Launch set (M3).** The full catalog with age bands,
  skills and difficulty ladders is in Appendix B.

  | Game | Ages | What it does |
  |---|---|---|
  | **Paint Studio** | 2+ | Brushes, crayon, marker, spray, rainbow; stamps; backgrounds; undo; save to the art gallery |
  | **Magic Coloring** | 2+ | Tap-to-fill line art; themed packs |
  | **Bubble Pop & Fireworks** | 2+ | Cause and effect, finger trails |
  | **Animal Sounds Farm** | 2+ | Tap animals; hear the name and the sound |
  | **Shape Sorter** | 2+ | Drag shapes into matching holes |
  | **Jigsaw** | 2+ | 2 → 24 pieces, using **family photos** |
  | **Memory Match** | 2.5+ | 2 → 12 pairs; family-faces option |
  | **Feed the Monster** | 2.5+ | Sort by color, shape or category ("only red food!") |
  | **Counting Garden** | 3+ | Tap to count 1–10, then "how many?" |
  | **Xylophone & Drums** | 2+ | Low-latency pentatonic instruments |

- **FR-TOY-03 [M4]** **Expansion set:**
  - Patterns, Odd-one-out, Shadow Match, Size Order
  - Finger Mazes, Sequencing Stories
  - Letter & number tracing, including **tracing her own name**
  - Letter sounds, Rhyme Time, Picture Sudoku 4×4, Spot the Difference
  - I-Spy, Who's That? (family faces)
  - Build-a-Creature, Music Sequencer
  - Weather Dress-Up, Freeze Dance, Breathing Buddy
  - Story Time with family voice recordings
  - Numbers and letters (added 2026-10-04): Dot-to-Dot, Big & Little
    Letters, Frog Hop, Word Builder, Hear the Sound, Sight Words, Banana
    Balance, Who Has More?, Name Zoo, Tallies, Hundred Square — number
    order, comparing and adding; capitals and small letters, alphabet
    order, word building, listening, sight words, first names, tallying and
    counting past twenty
- **FR-TOY-04 [M3]** **Adaptive difficulty:** each game tracks success rate,
  time and hints. It levels up after consistent success, eases off after
  repeated misses, and **never shows failure screens** (gentle retry cues
  instead). Parents can pin a level.
- **FR-TOY-05 [M3]** **Parent controls:** games on/off, daily time budget
  with a friendly "Toybox is sleeping" ending (with a countdown warning),
  Toybox hours (closes at bedtime), volume cap, and Toddler Lock (§9.3).
- **FR-TOY-06 [M4]** **Skills progress** (parent view): which skills she's
  practicing and mastering (counts to 7, recognizes 12 letters) from
  `game_progress`.
- **FR-TOY-07 [M3]** Content and assets: original or permissive art
  (**Kenney CC0** game assets, **Fluent Emoji** MIT, commissioned or
  generated illustrations reviewed for style consistency), CC0 sound
  effects, and parent or grandparent voice recordings. **No ads, no links,
  no purchases, no network needed** (family photos are pre-cached). The
  games' own voice (letters and their sounds, words, rhymes, I Spy clues,
  numbers, breathing prompts) is pre-generated offline with Piper's
  public-domain LJSpeech voice and bundled, since the frame has no TTS
  engine; letter sounds are written as phonemes so they come out as sounds
  ("buh", a short "a"), not names.
- **FR-TOY-08 [M3]** Engineering: each game is a self-contained module built
  on `CustomPainter`/sprites (no physics engine) with a T1 frame budget
  test. Sound effects use flutter_soloud for under 30 ms latency (verify in
  M0).

### 10.9 Music box (`FR-MUS`)

**Purpose.** A parent-curated wall of big album-art tiles that a toddler can
tap to play, whatever service the song lives on.

**Status: deferred** (owner, 2026-10-05). The requirements below stand,
but the music box isn't being built now; we'll come back to it later.

- **FR-MUS-01 [M3]** Tiles: cover art, title (optionally hidden for
  toddlers), and per-profile boards ("Ava's songs", "Dinner music",
  "Lullabies"). Parents curate tiles from the companion or web admin by
  pasting a link or searching.
- **FR-MUS-02** Sources:

  | Source | Plays on | Milestone | Notes |
  |---|---|---|---|
  | **Own files** (upload, or a NAS folder via the Hub) | This display, offline, ad-free | **[M3]** | Cached on the device. The best toddler experience. |
  | **YouTube / YouTube Music** | This display (embedded player) | **[M3]** | Curated video IDs only. Ads possible. Some videos block embedding (detected and flagged). |
  | **Spotify** | Any Spotify Connect device (Echo, Sonos, phone; the frame only if the Spotify app runs on it) | **[M3]** | Official Web API; Premium required (§13.7) |
  | **Amazon Music** | An Echo, via Home Assistant (Alexa Media Player) | **[M4]** | Unofficial on the HA side; a tile can also run any HA script |

- **FR-MUS-03 [M3]** Playback UI: huge play/pause and next, an animated
  "now playing" tile (equalizer bars at 15 fps on T1), and a **volume
  limiter**. A **sleep timer** fades out at the end.
- **FR-MUS-04 [M3]** Output target per board: "this display", a Spotify
  Connect device, or a Home Assistant media player (kitchen speaker). The
  tile shows where it will play.
- **FR-MUS-05 [M4]** ★ **Dance party:** an optional HA scene (colored lights)
  while a "party" board plays. **Freeze Dance** (Toybox) uses the same
  player.
- **FR-MUS-06 [M4]** Kid room role: lullaby board, white noise and nature
  loops (bundled), and a fade-out timer.

### 10.10 Timers, alarms & announcements (`FR-TMR`)

- **FR-TMR-01 [M2]** Multiple named kitchen timers with preset chips (1, 3,
  5, 10, 15, 30 min, custom) and a big ring countdown. They stay visible
  as a floating pill on every screen. When finished: chime, pulsing pill
  and a wake from screensaver.
- **FR-TMR-02 [M2]** Timers sync: start on a phone and it rings on the wall
  (or both). Recipe cook-mode timers are named after the step.
- **FR-TMR-03 [M3]** **Visual kid timers** (red disc) for routines, plus
  "5 more minutes" transitions with a gentle sound.
- **FR-TMR-04 [M4]** Scheduled **announcements** ("Bath time in 10 minutes")
  with chime, optional voice (§13.8), and target devices. Quiet hours are
  respected.

### 10.11 Smart home: Home Assistant (`FR-HA`)

- **FR-HA-01 [M4]** Connect HA (URL + long-lived token on the Hub). Choose
  exposed entities by room. Tile kinds: light (with brightness), switch,
  scene, script, climate, cover/garage, lock, media player, sensor.
- **FR-HA-02 [M4]** Safety: **locks, alarm and garage need grown-up mode.**
  Kid surfaces only show tiles explicitly marked kid-safe ("Ava's lamp").
- **FR-HA-03 [M4]** **Doorbell pop-up:** an HA doorbell event wakes
  displays and shows the camera view (snapshot refresh 2 fps on T1, MJPEG on
  T2+) with "Dismiss" and quick actions (unlock needs grown-up mode).
- **FR-HA-04 [M4]** **Presence wake:** HA motion or occupancy sensors near
  a display wake it from screensaver or night-off. This compensates for the
  frame having no camera or proximity sensor.
- **FR-HA-05 [M4]** **Who's home** widget from HA person entities.
- **FR-HA-06 [M4]** HA → Dearth: HA automations fire `dearth_*` events
  (announcement, chime, wake, show tile), e.g. "Washer done" → announcement.
  Dearth → HA: events such as `routine_started` and `display_mode_changed`
  for automations like dimming lights at bedtime.
- **FR-HA-07 [M4]** TTS and notifications are provided via HA (§13.8,
  §10.14).

### 10.12 Device roles & display modes (`FR-DEV`, `FR-DSP`)

**Roles**
- **FR-DEV-01 [M1]** **Kitchen:** full navigation, Kitchen home template,
  family + adult scopes (adult content gated), photo screensaver.
- **FR-DEV-02 [M4]** **Kid room:**
  - **OK-to-wake clock**: moon and dim red/orange means stay in bed; sun and
    green means OK to get up, with per-day times.
  - **Night light**: chosen color at minimum brightness with a fade-off
    timer.
  - Sleep sounds, bedtime routine, music board, "sleeps until" countdown,
    and a morning greeting with weather dress-up.
  - `kid_safe` scope only.
- **FR-DEV-03 [M4]** **Entry:** today's key events, weather with umbrella
  and jacket hints, leave-by (later), a departure checklist ("backpack,
  water bottle, library book"), pickup assignments, and door/garage status
  (HA).
- **FR-DEV-04 [M1]** **Personal (phone/desktop):** companion IA (§10.13).
- **FR-DEV-05 [M1]** Per-device settings: name, role, orientation (auto via
  accelerometer, landscape, portrait, reversed), screen diagonal and
  viewing distance (drives UI scale, §11.2), performance tier override,
  schedules, and screensaver collection.

**Display modes** (state machine, evaluated on device and overridable from
the Hub)

| Mode | Enters on | Shows | Exits on |
|---|---|---|---|
| **Active** | Touch, wake trigger | Full UI | Idle timeout |
| **Screensaver** | Idle ≥ timeout (default 5 min) | Photo frame + overlays | Touch, wake trigger, timer or alarm |
| **Night** | Schedule (e.g. 21:00–06:30) or ambient light below a threshold | Dim warm clock, or very dim photos (optional) | Schedule end; touch shows a dim UI for 60 s |
| **Off** | Schedule (optional) | Screen physically off (FreeKiosk `screen/off`) or black at 0 % brightness | Schedule end, HA presence, timer or alarm (FreeKiosk `screen/on`) |
| **Privacy** | Manual or guest mode | Photos + clock only | Grown-up PIN |

- **FR-DSP-01 [M1]** Mode priority: Off > Night > Privacy > Screensaver >
  Active. Manual "keep awake 1 h" override.
- **FR-DSP-02 [M1]** **Auto-brightness from the light sensor** using a
  configurable lux → brightness curve (separate curves per mode, min/max
  clamps, hysteresis to prevent flicker). Brightness is applied at the
  window level by the app, or through FreeKiosk when present.
- **FR-DSP-03 [M1]** Touch in Off mode can't wake an Android screen, so
  **Off is only allowed with a scheduled end** (and optional HA presence
  wake). Night (dim) is the recommended default.
- **FR-DSP-04 [M1]** Burn-in and wear: overlays drift and the clock position
  rotates slowly in Night mode.

### 10.13 Companion app & web admin (`FR-CMP`)

- **FR-CMP-01 [M1]** One codebase, **Personal** role. Android phones: the
  Flutter Android app. **iPhones: the PWA** served by the Hub over HTTPS
  (installable, offline shell, Web Push on iOS 16.4+). Native iOS is a
  later option (needs a Mac and an Apple developer account).
- **FR-CMP-02 [M1]** Phone IA: **Today** (personal agenda + family), **Add**
  (quick-add event, list item, note), **Lists** (store mode), **Approvals**,
  **More** (meals, photos, kids, settings).
- **FR-CMP-03 [M2]** Share targets: "Send to Dearth" for photos (to the
  screensaver), recipe URLs (to recipe import), and YouTube/Spotify links
  (to music tiles).
- **FR-CMP-04 [M2]** **Web admin** on laptop-sized screens for content-heavy
  work: meal planning, photo curation, chore and reward setup, music
  boards, device management, integrations, backups.
- **FR-CMP-05 [M3]** Remote device control: wake or sleep, show
  announcement, play chime, start timer, screenshot, reload.

### 10.14 Notifications (`FR-NTF`)

| Channel | Use | Milestone |
|---|---|---|
| On-display banners and chimes | Reminders, timers, announcements, approvals waiting | **[M1]** |
| **HA mobile app notify** (recommended for this household) | Phone pushes, including **actionable approvals** ("Approve Ava's chore" → HA event → Hub) | **[M4]** |
| Web Push (VAPID) | PWA users (iPhone) | **[M2]** |
| ntfy (self-hosted) | Families without HA | **[M5]** |

- **FR-NTF-01 [M2]** Triggers (each toggleable per person): event
  reminders, approvals pending, reward requests, timers done, severe
  weather alerts, integration failures (admins only). Quiet hours apply.

### 10.15 Onboarding & settings (`FR-SET`)

- **FR-SET-01 [M1]** Device first run: welcome, then **"Connect to your
  Hub"** (scan QR or enter URL, then pair, §9.2) or **"Try it solo"** (M5).
  Then role, orientation, screen size and viewing distance (with a live
  scale preview), then done.
- **FR-SET-02 [M1]** Household setup wizard (web admin or companion):
  household name, timezone, location (ZIP or map), units and week start;
  family profiles (name, color, photo, role, birthday, kid stage, buddy);
  connect Google and map calendars to people; weather (WU key + station, or
  keyless); photos (Amazon link, folder); done. Dearth then offers sample
  chores, routines and meal ideas.
- **FR-SET-03 [M1]** Settings IA: Household · People · Devices · Calendar ·
  Weather · Photos & Screensaver · Meals · Kids · Toybox · Music · Smart
  Home · Notifications · Integrations & Accounts · Backups · Updates ·
  Diagnostics · About & Licenses. Settings are searchable and every one has
  inline help.
- **FR-SET-04 [M1]** Accessibility settings: text size, high contrast,
  reduced motion, color-blind-safe palette, sounds and haptics.

### 10.16 AI assistant: pluggable, deferred (`FR-AI`)

Decision deferred by the owner. v1 ships the **interface and UX hooks
only**.

- **FR-AI-01 [M5]** `AiProvider` interface on the Hub with these
  operations:
  - `extractEvents(text | image | pdf) → EventDraft[]`
  - `extractMealPlan(...) → PlanDraft`
  - `normalizeRecipe(raw) → Recipe`
  - `suggestRecipes(planContext, constraints) → RecipeIdea[]`
- **FR-AI-02 [M5]** **Nothing publishes without approval.** Drafts land in
  an adult-only review queue with field-level diffs. AI is off by default.
  Each feature is toggled separately, and there's a monthly cost meter.
- **FR-AI-03 [M5]** Inputs: a forwarded email (IMAP folder poll), a photo
  from the companion, PDF upload, pasted text. Parity with Skylight's Magic
  Import and Hearth Helper.
- **FR-AI-04 [M5]** Reference implementation when enabled: Anthropic
  Messages API over HTTPS from the Hub (there is no official Dart SDK, so
  use raw HTTP). Default model `claude-opus-5-5`, configurable. Use
  structured outputs (`output_config.format` with a JSON schema; every
  object `additionalProperties: false`), images and PDFs as content blocks,
  and check `stop_reason` (including `refusal`) before reading content.
  Opt into server-side refusal fallbacks. Re-verify current API details when
  this feature is picked up, since the API evolves quickly.

### 10.17 Administration, updates & diagnostics (`FR-ADM`)

- **FR-ADM-01 [M1]** **Devices view:** online state, app version, role,
  tier, renderer backend, memory and CPU, frame stats (p50/p95), uptime,
  last error, data cache sizes.
- **FR-ADM-02 [M1]** **Remote screenshot:** the device renders its own
  Flutter layer to PNG and uploads it. `adb screencap` returns 0 bytes on
  this ROM, so this matters.
- **FR-ADM-03 [M1]** Remote log tail and crash reports, stored on the Hub
  only.
- **FR-ADM-04 [M2]** **App updates:** the Hub hosts signed APKs (per ABI)
  with release notes. Devices check daily and show "Update available".
  Install mechanics depend on kiosk mode (§15.3).
- **FR-ADM-05 [M1]** Integration health page: status, last success, next
  run, quota use (WU calls per day, Spoonacular points), and a "Reconnect"
  button.

---

## 11. UX & design system

The bar: it should feel like a premium appliance, not a hobby app. That
comes from consistency (tokens, components, motion rules), restraint (calm
by default) and craft (typography, spacing, photography). It must stay
within the T1 performance budget.

### 11.1 Design principles

1. **Glance first.** The most important answer on each screen is the
   biggest thing on it. Secondary information is quieter, not smaller-than-
   readable.
2. **People are the color.** Profile colors are the primary color system:
   events, chores, avatars and lists. The brand accent is used sparingly.
3. **Calm by default, delight on demand.** Ambient screens are still.
   Motion and sound mark moments that matter: completions, celebrations,
   timers.
4. **Big, forgiving touch.** Wall targets ≥ 64 dp (≥ 48 dp for dense
   secondary controls). No double-taps, hovers, right-clicks or tiny close
   buttons. Generous hit-slop.
5. **Keep context.** Details open in side sheets (landscape) or bottom
   sheets (portrait) over the current view. State survives rotation and
   screensaver.
6. **Kid surfaces are their own world.** No reading required, no
   destructive actions, voice and picture first, bigger everything.
7. **Performance is a design constraint.** Effects are designed per tier;
   every component lists its T1 behavior.
8. **Tokens, not one-offs.** Every color, size, radius, duration and curve
   comes from `dearth_ui` tokens. Lint rules flag raw values in feature
   code.

### 11.2 Scale, grid & navigation

**UI scale.** The panel reports a bogus physical DPI, and Android's density
override (173) is an arbitrary vendor choice. So Dearth computes its own
**`uiScale`** from the configured screen diagonal, resolution and **viewing
distance** (near ≈ 0.5 m, room ≈ 1.5 m, across-kitchen ≈ 3 m). The user can
adjust it from 80 % to 140 % with a live preview. All typography and spacing
tokens multiply by `uiScale`; layout breakpoints use logical size. Reference:
on the 27" frame at "room" distance, `uiScale = 1.0` and Body text = 22 dp
(≈ 7 mm line height).

| Display class | Columns / gutter / margin | Navigation |
|---|---|---|
| Wall-L (1777×1000 dp) | 12 / 24 / 32 dp | **Left rail**, 96 dp wide, icons with always-visible labels |
| Wall-P (1000×1777 dp) | 6 / 24 / 32 dp | **Bottom bar**, 5 destinations + More |
| Tablet | 8 / 16 / 24 dp | Rail (landscape) or bottom bar (portrait) |
| Phone | 4 / 16 / 16 dp | Bottom bar: Today · Add · Lists · Approvals · More |

Primary destinations on Kitchen: **Home, Calendar, Meals, Lists, Kids,
Toybox, Music, Photos, Home Control (M4), Settings**. Roles can hide any of
them.

### 11.3 Visual language

**Direction: "Warm Daylight."** Warm paper neutrals, deep ink text, soft
depth, rounded geometry, photography-forward, people-colored accents.
**Evening** (dark) uses deep blue-charcoal; **Night** uses near-black with
dim amber text that is easy on eyes in a dark room.

| Token | Light | Evening (dark) | Night |
|---|---|---|---|
| `surface` | `#F7F4EE` | `#14161C` | `#000000` |
| `surface-raised` (cards) | `#FFFFFF` | `#1D2029` | `#0B0B0B` |
| `surface-sunken` | `#EFEAE1` | `#0F1116` | `#000000` |
| `ink-primary` | `#1E1C24` | `#F2F0EC` | `#B8753A` |
| `ink-secondary` | `#5E5A66` | `#A9A6B2` | `#6E4A2A` |
| `outline` | `#E2DCD1` | `#2C3040` | `#1A1209` |
| `accent` (brand) | `#5B5BD6` | `#8E8CF5` | `#8A5A2E` |
| `success` / `warning` / `danger` | `#2E9E6A` / `#E9A23B` / `#D9534F` | `#4CC38A` / `#F5B85A` / `#F07470` | dimmed variants |

*(Proposed values; final values come from the M0 design pass with contrast
checks for every pairing.)*

**Profile palette** (12 colors, each with `solid`, `tint` and `on-solid`,
tuned for both themes and checked for color-blind distinguishability; color
is never the only signal):
Coral `#F2795D` · Amber `#F2B33D` · Lime `#8CC152` · Mint `#3CC59A` ·
Teal `#26A9A0` · Sky `#3D9BE9` · Indigo `#5B6CF2` · Violet `#9B6CF0` ·
Pink `#EE6BA8` · Red `#E5484D` · Brown `#A8785A` · Slate `#6B7A8F`.

**Typography** (bundled, subset to Latin, no runtime fetch; both OFL):
- **Plus Jakarta Sans** (variable) for UI. Use **tabular figures** for
  clocks, times and quantities.
- **Fredoka** (variable, rounded) for kid surfaces and playful display
  numerals.
- Alternatives to evaluate in M0: Nunito, Figtree, Inter.

| Style | Wall size (dp @ uiScale 1.0) | Use |
|---|---|---|
| Clock XL | 120 / weight 300 | Screensaver, night clock |
| Display | 72 / 600 | Home clock, big temperature |
| H1 | 44 / 700 | Screen titles |
| H2 | 32 / 650 | Section titles, Up next |
| Title | 26 / 600 | Card titles, event titles |
| Body | 22 / 450 | Default text |
| Label | 18 / 600 | Chips, buttons, metadata |
| Caption | 16 / 500 | Timestamps, sources (minimum on wall) |

The phone class uses a 0.72× type ramp.

**Icons & illustration**
- **Material Symbols Rounded** (variable font; outlined by default, filled
  for the active state) for UI.
- **Fluent Emoji** (MIT; 3D style) for content: event icons, chores, meals,
  weather "for kids", rewards. Pre-rasterized at 96/192/384 px and selected
  per size.
- Empty-state illustrations and kid scenes in one consistent style,
  precompiled with `vector_graphics`.

**Shape & depth**
- Radius tokens: S 12 · M 20 · L 28 · XL 36 · pill.
- Elevation: e0 flat · e1 card (y 2, blur 8, 8 % ink) · e2 raised (y 8,
  blur 24, 12 %) · e3 sheet.
- Single analytic shadows only. **No glassmorphism blur on T1**; "frosted"
  surfaces use semi-opaque fills instead.

### 11.4 Motion

| Token | Duration | Curve | Use |
|---|---|---|---|
| `micro` | 90 ms | easeOut | Press states, toggles |
| `fast` | 150 ms | easeOutCubic | Chips, small reveals |
| `standard` | 220 ms | easeOutCubic | Sheets, fade-through between destinations |
| `emphasized` | 320 ms | cubic(0.2, 0, 0, 1) | Card → detail, celebrations' entrance |
| `ambient` | 1,200 ms | easeInOut | Screensaver crossfade |
| `celebration` | ≤ 1,600 ms | custom | Confetti, buddy dance, star flight |

Rules:
- Animate **transform and opacity of leaf layers**; never animate the
  layout of large subtrees.
- No animated blur or shadow radius.
- Stagger at most 6 items at 30 ms.
- Top-level navigation uses **fade-through** (no sliding pages on T1).
- Card → detail uses a hero/container transform on T2+ and fade + scale
  on T1.
- Reduced motion turns everything into ≤ 150 ms crossfades and calm
  celebrations.

### 11.5 Sound

- Adult UI is silent by default.
- Kid surfaces have tap and success sounds.
- Chimes: timer (escalating), reminder, announcement, doorbell.
- Volume per category, quiet hours, and a global mute on the Home header
  long-press.
- All sounds are short CC0 or self-produced assets, loudness-normalized.

### 11.6 Themes

- Light, Evening, Night. **Auto** switches at local sunset and sunrise (NOAA
  solar math at the household location) or when ambient light crosses a
  threshold; the user picks the source.
- ★ **Seasonal accents** (opt-in, subtle): leaves in fall, snow in December,
  hearts in February. On T1 these are static or use ≤ 20 particles at
  20 fps.

### 11.7 Screen blueprints

These are wireframes for structure and hierarchy, not visual design. Hi-fi
mockups for each are an M0 deliverable.

**Kitchen Home — landscape (Wall-L)**
```
┌────┬──────────────────────────────────────────────────────────────────────────────┐
│ ⌂  │ Friday, October 2                    7:42                ☀ 63°  H71 L45  ☂ 10% │
│Home│                                       PM                  ⚠ none   ● synced   │
│ 📅 ├──────────────────────────┬─────────────────────────────┬───────────────────────┤
│Cal │ TODAY                     │ UP NEXT                      │ TONIGHT               │
│ 🍽 │ 8:00  🏫 Daycare   ●Ava   │ 🏊 Swim lesson    in 45 min  │ ┌───────────────────┐ │
│Meal│ 9:30  🦷 Dentist   ●Mom   │ 5:30–6:15 · ●Ava ●Mom        │ │   [taco photo]    │ │
│ ✓  │ 5:30  🏊 Swim      ●Ava●M │──────────────────────────────│ └───────────────────┘ │
│List│ ─────── now ───────────── │ THIS WEEK                     │ Chicken tacos · 30 m │
│ ⭐ │ 7:30  🛁 Bath & story ●Ava│  Fri  Sat  Sun  Mon  Tue  Wed │ Tomorrow: pasta night │
│Kids│                           │  ☀71  ⛅68 🌧55 ☀60 ☀64 ⛅61 ├───────────────────────┤
│ 🧸 │ TOMORROW                  │  ●●   ●    ●●●  ●    ●●   ●  │ AVA          🌼 garden │
│Toys│ 10:00 🥕 Farmers market   │──────────────────────────────│ [🦷✓][👕✓][🧸 ][🥣 ]   │
│ 🎵 │ 2:00  🎂 Leo's party      │ NOTES                         │ Sticker jar ●●●●○○    │
│Musc│                           │ 📝 "Grandma visits Sat!"      ├───────────────────────┤
│ 🖼 │                           │ ⏳ 🎃 Halloween in 29 days    │ 🛒 Shopping · 12 items │
│ ⚙  │                           │                               │ [family photo tile]   │
└────┴──────────────────────────┴─────────────────────────────┴───────────────────────┘
```

**Kitchen Home — portrait (Wall-P)**
```
┌────────────────────────────────────────────┐
│ Friday, October 2            ☀ 63°  H71 L45 │
│                  7:42 PM                    │
├────────────────────────────────────────────┤
│ UP NEXT  🏊 Swim lesson · in 45 min  ●A ●M │
├────────────────────────────────────────────┤
│ TODAY                         TOMORROW      │
│ 8:00  🏫 Daycare  ●Ava        10:00 🥕 Mkt  │
│ 9:30  🦷 Dentist  ●Mom        2:00  🎂 Leo  │
│ 5:30  🏊 Swim     ●Ava ●Mom                 │
├──────────────────────┬─────────────────────┤
│ TONIGHT [taco photo] │ AVA  [🦷✓][👕✓][🧸] │
│ Chicken tacos · 30 m │ Sticker jar ●●●●○○  │
├──────────────────────┴─────────────────────┤
│ THIS WEEK  ☀71 ⛅68 🌧55 ☀60 ☀64 ⛅61 ☀66  │
├────────────────────────────────────────────┤
│ 📝 Grandma visits Sat!   ⏳ Halloween 29d   │
│ [ family photo tile ................... ]   │
├────────────────────────────────────────────┤
│  ⌂ Home   📅 Cal   🍽 Meals   ⭐ Kids   ⋯   │
└────────────────────────────────────────────┘
```

**Calendar — week (Wall-L)**
```
┌────┬─────────────────────────────────────────────────────────────────────────┐
│nav │ ◀  Sep 28 – Oct 4, 2026  ▶   Day 3-Day [Week] Month Agenda People   ＋  │
│    │ (All) (●Mom) (●Dad) (●Ava)                         quick add: "…"      │
│    │        Sun 28    Mon 29    Tue 30    Wed 1     Thu 2     Fri 3   Sat 4 │
│    │        ☀70/44   ⛅66/41   🌧55/40   ☀60/38   ☀64/40   ☀71/45  ⛅68/43 │
│    │ all-day [🎂 Grandpa's birthday ──────]                                  │
│    │  8 AM  [🏫 Daycare●A]  [🏫 Daycare●A] [🏫 Daycare●A] ...                │
│    │  9 AM            [🦷 Dentist ●M]                                        │
│    │ ...                                                                     │
│    │  5 PM                                        [🏊 Swim ●A●M]             │
│    │ ──────────────────────────────── now 7:42 ─────────────────             │
└────┴─────────────────────────────────────────────────────────────────────────┘
```

**Recipe detail + plan-aware suggestions (Wall-L, side sheet over Discover)**
```
┌─────────────── Discover ───────────────┬──────────── Chicken Tacos ─────────────┐
│ [Search…]  Popular · Surprise · Quick… │ [hero photo]                  ★ 😋😋🙂 │
│ PAIRS WITH YOUR PLAN                   │ 30 min · Mexican · TheMealDB           │
│ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐   │ Servings  [ − ]  6  [ + ]   US | metric │
│ │photo │ │photo │ │photo │ │photo │   │ ☐ 1½ lb chicken thighs                 │
│ │Black │ │Burrito│ │Lime  │ │ …    │   │ ☐ 1 bunch cilantro ← also in Burrito  │
│ │bean  │ │bowls │ │rice  │ │      │   │ ☐ 3 limes          ← also in Lime rice │
│ │soup  │ │      │ │      │ │      │   │ …                                      │
│ │uses 4│ │uses 5│ │uses 3│ │      │   │ [ Add to plan ▾ ] [ Add to list ] [♥]  │
│ │+2 new│ │+1 new│ │+2 new│ │      │   │ [ Cook mode ▶ ]                        │
│ └──────┘ └──────┘ └──────┘ └──────┘   │                                        │
└────────────────────────────────────────┴────────────────────────────────────────┘
```

**Kid chart — Little stage (Wall-L)**
```
┌───────────────────────────────────────────────────────────────────────────┐
│  ☀ Good morning, Ava!                🐰 (buddy)           🫙 ●●●●○○        │
│                                                                           │
│   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐                  │
│   │   [photo of  │   │   [photo of  │   │   [photo of  │                  │
│   │  toothbrush] │   │   clothes]   │   │   cereal]    │                  │
│   │      🦷      │   │      👕      │   │      🥣      │                  │
│   │   ✓ Done!    │   │   🔊 tap     │   │   🔊 tap     │                  │
│   └──────────────┘   └──────────────┘   └──────────────┘                  │
│                                                                           │
│   🐰 ●━━━━━━●━━━━━━○━━━━━━○  🌞   (bunny hops along the path)              │
│                                                          ◔ grown-ups      │
└───────────────────────────────────────────────────────────────────────────┘
```

**Toybox launcher**
```
┌───────────────────────────────────────────────────────────────────────────┐
│  🧸 Ava's Toybox                                    ⏳ 12 min left  ◔      │
│  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐   │
│  │  🎨    │  │  🖍️    │  │  🫧    │  │  🐮    │  │  🔺🟦  │  │  🎵    │   │
│  │ Paint  │  │ Color  │  │ Bubbles│  │ Farm   │  │ Shapes │  │ Music  │   │
│  └────────┘  └────────┘  └────────┘  └────────┘  └────────┘  └────────┘   │
│  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐   │
│  │  🧩 ✨ │  │  🃏    │  │  👾    │  │ 🌻 123 │  │  ⭐    │  │  🔤    │   │
│  │ Puzzle │  │ Match  │  │ Monster│  │ Count  │  │ Dots   │  │ Letters│   │
│  └────────┘  └────────┘  └────────┘  └────────┘  └────────┘  └────────┘   │
└───────────────────────────────────────────────────────────────────────────┘
```
(Labels are for parents; tiles are recognizable without reading.)

**Screensaver**
```
┌───────────────────────────────────────────────────────────────────────────┐
│                                                                           │
│                       [ full-bleed photo, or two paired portraits ]        │
│                                                                           │
│ ░░ gradient scrim ░░                                                      │
│ 7:42                                                🏊 Swim in 45 min     │
│ Friday, Oct 2 · ☀ 63°                               📷 July 2024 · Dillon  │
└───────────────────────────────────────────────────────────────────────────┘
```

**Weather (Wall-L)**
```
┌────┬──────────────────────────────────────────────────────────────────────────┐
│nav │ IN OUR BACKYARD (PWS KCOAUROR123 · 2 min ago)        ⚠ No alerts          │
│    │ 63.6°  feels 61°  💨 5 mph (gust 12)  💧 30%  🌧 today 0.00 in  UV 3       │
│    ├──────────────────────────────────────────────────────────────────────────┤
│    │ NEXT 24 HOURS    "Dry tonight; rain likely 3–7 PM tomorrow, ~0.3 in"     │
│    │ temp  ╭─╮__╭──╮___                                                       │
│    │ rain  ▁ ▁ ▁ ▂ ▅ ▇ ▆ ▃   % + amount                                       │
│    │ sun   ████████░░░░▒▒██  minutes of sun per hour                          │
│    │ UV    ▂▃▅▆▅▃▂                                                            │
│    ├──────────────────────────────────────────────────────────────────────────┤
│    │ 10 DAYS  Fri ☀ 45 ━━━━━━ 71  10%  ☀ 11.5 h                              │
│    │          Sat ⛅ 43 ━━━━━ 68   20%  ☀ 8.0 h                               │
│    │          Sun 🌧 40 ━━━ 55     80% 0.4 in  ☀ 2.1 h  ...                    │
│    ├──────────────────────────────────────────────────────────────────────────┤
│    │ ☀ sunrise 7:01 ── arc ── sunset 6:43 · daylight 11 h 42 m · 🌔 waxing   │
└────┴──────────────────────────────────────────────────────────────────────────┘
```

**Kid room — night (OK-to-wake)**
```
┌──────────────────────────────┐
│                              │
│            🌙                │   dim, warm, near-black
│          7:12                │   moon + red/orange tint = stay in bed
│                              │   at wake time: 🌞 + soft green, gentle chime
│   2 sleeps until Grandma 🏡  │
└──────────────────────────────┘
```

### 11.8 Component library (`dearth_ui`)

Foundation: `DTokens` (color, type, space, radius, motion, elevation per
theme × tier × uiScale), `DIcon`, `DEmoji` (sized bitmap selection),
`DText` styles.

Components:
- **Containers:** `DCard`, `DTile`, `DSection`, `DSideSheet`, `DBottomSheet`,
  `DDialog` (no nested dialogs)
- **Feedback:** `DToast`, `DBanner`
- **People:** `DAvatar` (with progress ring), `DProfileChip`
- **Calendar:** `DEventPill`, `DTimeGrid`, `DMonthGrid`, `DAgendaList`
- **Controls:** `DBigButton`, `DSegmented`, `DStepper`, `DPinPad`
- **Progress & time:** `DCountdownRing`, `DVisualTimer`, `DProgressPath`
  (kid routine path)
- **Charts:** `DRangeBar` (weather high/low), `DSparkline`, `DBarStrip`
- **Media:** `DPhoto` (blob-backed, sized decode, placeholder color)
- **States:** `DSkeleton`, `DEmptyState`
- **Moments:** `DCelebration` (catalog player), `DStickerCanvas`

Each component documents its T1 behavior, has golden tests for 4 display
classes × 3 themes, and appears in the **widget gallery** app for design
review.

### 11.9 Accessibility & i18n

- WCAG 2.2 AA contrast for all text and icons in Light and Evening themes
  (Night is exempt by design, but readable).
- Screen-reader labels on every interactive element. Color plus icon or
  text for every status. A color-blind-safe palette option.
- Text size setting (independent of `uiScale`), high-contrast mode,
  reduced motion.
- All strings externalized (ARB, `flutter_localizations`). English first.
  Dates, times and numbers follow locale + household timezone; week start
  is configurable.

### 11.10 Toddler-proof interaction rules

1. Kid surfaces have **no destructive or irreversible actions**.
2. The **first touch on a sleeping display only wakes it**; it never
   activates the control underneath.
3. A **multi-tap storm** (≥ 6 taps/s) on non-kid screens triggers a gentle
   "Little hands detected 🐣" overlay offering Toybox or Music. Nothing
   underneath is triggered. ★
4. Long-press actions need ≥ 600 ms and show progress feedback. Drag
   actions need a deliberate threshold.
5. Dialogs never stack. A tap on the backdrop never confirms.
6. Exits from kid surfaces go through the grown-up corner (3 s hold + PIN).

---

## 12. Performance engineering

Performance is a feature with budgets, tooling and release gates. All
numbers refer to the JT215M (T1) in **profile** builds unless noted.

### 12.1 Budgets

| Budget | Target |
|---|---|
| Frame (56 Hz) | 17.9 ms total. UI thread (build + layout + paint record) p90 ≤ 7 ms; raster p90 ≤ 10 ms |
| Jank | < 1 % janky frames per scenario; no frame > 50 ms outside cold start |
| Cold start → Home interactive | ≤ 3.5 s (splash shows the clock within 1 s) |
| Memory (PSS) | ≤ 220 MB steady; ≤ 300 MB peak (photo transitions + cook mode) |
| Dart heap | ≤ 60 MB steady |
| Image cache | T1 48 MB / T2 96 MB / T3 160 MB (`PaintingBinding.imageCache`) |
| CPU | Idle Home ≤ 3 %; screensaver ≤ 12 %; Toybox games ≤ 45 % |
| APK size | armeabi-v7a APK ≤ 35 MB (fonts subset, assets compressed, icons tree-shaken) |
| Device disk caches | Photos 1.5 GB · music 2 GB · recipe images 200 MB · other blobs 300 MB (LRU, configurable) |
| Device network | No polling. One WebSocket; blob fetches are prefetch-scheduled |

### 12.2 Renderer strategy

- On the frame, Flutter 3.47's engine picks **Impeller's OpenGL ES backend**
  (the PowerVR Rogue Vulkan 1.0 driver is denylisted, as confirmed by engine
  strings). Measured there (2026-10-04, `dumpsys SurfaceFlinger --latency` —
  HWUI `gfxinfo` sees nothing under a Flutter surface), the Toybox grid
  scroll is **GPU-bound at ~14 fps (median 71.7 ms/frame)**, steady across
  content tier, shadow blur, press effects and lazy-grid changes: Impeller
  re-rasterizes the whole scene every frame, and the GE8300's fill rate
  can't do ~10 M shaded pixels twice inside a 17.9 ms budget. The GPU has
  no clock headroom (504 MHz max, already reached under load).
- **Shipped (owner decision 2026-10-05): Impeller at native resolution.**
  The time-boxed Skia opt-out was measured at 56.8 fps (raster cache caches
  the tile layers), and Impeller reaches 57.0 fps at 540p / 32.6 at 720p via
  `wm size` — but the frame is partly a photo frame, and the owner chose
  renderer longevity and photo/text crispness over scroll smoothness. No
  renderer flag ships in the manifest; the opt-out stays documented here as
  the measured fallback. App-side cost work continues to close the gap:
  removing the tile gradients (the launcher's dominant fill — one flat quad
  per tile now) took the same scroll from ~14 to **45.2 fps** (median
  22.1 ms, 2026-10-05); the remaining stride is the big-emoji and text
  fill.
- **Revisit on every Flutter upgrade** via the frame perf gate (§12.9):
  watch for PowerVR-Rogue GLES work (3.47.3's flutter/181315 fixed
  B-series PowerVR artifacts/perf, not Rogue fill rate), any Impeller
  scene/caching work for the GLES backend, and the announced removal of
  the opt-out (which retires the 56.8 fps fallback). Probe data:
  beta 3.49.0-0.2.pre measured identical to pinned 3.47.2 (14.0 vs 14.4
  fps) — record every probe's numbers here.
- Escalation ladder for display perf: 1. tighten tier rules and component
  T1 variants; 2. fix the specific hot path; 3. file upstream issues with
  reproductions; 4. time-boxed Skia opt-out with an exit plan (measured
  2026-10-04; not shipped by owner decision).

### 12.3 Rendering rules

**Do**
- Wrap independently changing regions in `RepaintBoundary`: clock, timers,
  now-line, each Home widget, celebrations, screensaver layers.
- Use `const` widgets aggressively, and `AnimatedBuilder`/`ListenableBuilder`
  with a `child:` for static subtrees.
- Use `ListView.builder` / `SliverList` with `itemExtent` or `prototypeItem`
  for long lists. Virtualize calendar grids by visible range.
- Draw charts, rings, paths and game scenes in **one `CustomPainter`** each,
  caching a `Picture` when the inputs haven't changed.
- Pre-render expensive looks into bitmaps on the Hub: blurred backgrounds,
  drop-shadowed stickers, gradients over photos where possible.
- Throttle ambient animations (equalizer bars, weather icons, buddy idle
  animation) to **≤ 30 fps on T1** with a frame-skipping ticker.
- Use `FadeTransition`/`ScaleTransition` (layer-backed) instead of
  rebuilding with new opacity values.

**Don't** (flagged by custom lint rules in feature code)
- Don't use `BackdropFilter`, `ImageFilter.blur` or `ShaderMask` on T1
  paths.
- Don't put an `Opacity` widget over large subtrees (it forces offscreen
  layers). Use per-leaf alpha.
- Don't stack `ClipRRect`/`ClipPath` over scrolling content. Prefer
  rounded `DecoratedBox` + `Clip.hardEdge` on images.
- Don't animate font size (it churns the glyph atlas). Scale with
  transforms instead.
- Don't nest multiple `BoxShadow`s on cards in lists.
- Don't use Material 3's `InkSparkle` (shader). Use `InkRipple` or custom
  press states.
- Don't use `IntrinsicHeight/Width` in lists, or `shrinkWrap` lists inside
  scroll views.
- Don't run any `Timer.periodic` faster than 1 Hz outside active
  animations.

### 12.4 State & rebuilds

- Riverpod providers expose **narrow** slices. Widgets use `select` so that,
  for example, a ledger change repaints only the ring that depends on it.
- drift `watch()` queries are **scoped to visible ranges** (the visible week,
  today's chores) and debounced (16–50 ms) when bursts of ops arrive.
- Clock and countdown widgets own their tickers and align to minute
  boundaries. Nothing else listens to time.

### 12.5 Images & media

- Devices **never decode originals**. The Hub produces derivatives sized for
  each device class (e.g. 1920×1080 cover, 960 px cards, 384 px thumbnails)
  as **baseline JPEG q≈82** (fastest decode on ARM; WebP only where alpha
  is needed).
- Decode at display size (`ResizeImage` / `cacheWidth`). `precacheImage` the
  **next** screensaver photo at least 5 s before its transition, and keep at
  most 3 decoded full-screen images.
- Placeholders: each photo row carries a dominant color and a 16-px blur-hash
  so the first frame is never blank.
- Video is out of scope on T1 except the YouTube player (§13.7).

### 12.6 Memory & lifecycle

- Keep-alive budget per tier: T1 keeps **Home + current** destination;
  T2 also keeps one recent destination. Offstage routes run with
  `TickerMode(enabled: false)`.
- When Android signals memory pressure (`didHaveMemoryPressure`): clear the
  image cache, drop keep-alives, release game assets.
- Dispose controllers, streams and subscriptions deterministically (lint
  rule). A leak test runs a 1-hour scripted navigation loop in the perf
  gate and asserts no PSS growth beyond 5 %.

### 12.7 Data & isolates

- The database runs on a background isolate. Batches of incoming ops apply
  in single transactions.
- JSON decoding of large payloads (snapshots, recipe searches),
  recurrence expansion, layout precomputation for dense weeks, and recipe
  scoring run in `Isolate.run` or a long-lived worker isolate.
- Nothing on the UI isolate takes more than 4 ms; violations are logged
  with stack traces in debug and profile builds.

### 12.8 Startup

- Show a native splash, then the Flutter frame with clock and cached
  weather within 1 s.
- Open the database and render Home from local data **before** connecting
  to the Hub.
- Defer the initialization of non-visible features (games, music engine,
  HA) until first use or idle time.

### 12.9 Measurement & gates

- **Perf HUD** (hidden developer menu): frame chart (build and raster), PSS,
  CPU, renderer backend, image-cache size, isolate queue depth.
- **Telemetry to the Hub** (local only): per-device p50/p95/p99 frame times
  per screen, jank counts, memory, uptime, shown in Admin → Devices.
- **`tool/perf_gate.sh <device>`**: builds a profile APK, installs it over
  ADB, and runs `integration_test` scenarios with `traceAction` →
  `TimelineSummary`. It fails on budget regressions. **Release builds for
  displays require a green perf gate on the frame.**

  | Scenario | Measures |
  |---|---|
  | Home idle 60 s | Idle CPU, repaint count |
  | Navigate all destinations ×3 | Transitions |
  | Agenda fling (300 events) | Scroll jank |
  | Week view page ×10 (60 events/week) | Grid layout + paint |
  | Month view open | Chip layout |
  | Recipe search results scroll (40 cards with images) | Image decode + scroll |
  | Cook mode with 2 timers | Ticker cost |
  | Screensaver 10 transitions | Crossfade + optional Ken Burns |
  | Celebration ×5 | Particles |
  | Paint Studio 30 s of strokes | Stroke rendering |
  | Jigsaw 12 pieces drag | Drag + hit testing |
  | 1-hour soak | Memory growth |

### 12.10 Web build

The web build serves development and the iPhone PWA. Use **skwasm**
(WebAssembly) where the browser supports it, falling back to CanvasKit.
Serve with `Cross-Origin-Opener-Policy`/`Cross-Origin-Embedder-Policy`
headers from the Hub for multi-threaded skwasm. The web app is not used on
the frame.

---

## 13. Integrations

### 13.1 Adapter framework (`dearth_integrations`)

Every provider implements a small interface:
`CalendarProvider`, `WeatherProvider`, `PhotoProvider`, `RecipeProvider`,
`MusicProvider`, `SmartHomeProvider`.

Shared base behavior:
- Typed config and secrets.
- `probe()` health check.
- Token-bucket rate limiting and **quota accounting** (per-day counters).
- Exponential backoff with jitter; honor `Retry-After`.
- Circuit breaker (open → half-open).
- Response caching with TTL.
- Structured health status shown in Admin.
- **Recorded fixtures** so CI runs offline.

No adapter is ever called from device UI code (Solo mode runs adapters in a
background isolate).

### 13.2 Google (Calendar; later Photos Picker, Tasks)

**OAuth (on the Hub)**
- Each family creates its own Google Cloud project with an OAuth **Web
  application** client. The redirect URI is
  `https://<hub-domain>/api/oauth/google/callback`. Use
  `access_type=offline`, `prompt=consent`, and PKCE.
- **Publishing status must be "In production"**, not "Testing": External
  apps in Testing get refresh tokens that **expire after 7 days**. An
  unverified production app shows Google's "unverified app" warning, which
  the family accepts once. That's fine for personal use (up to 100 users).
  `docs/google.md` walks through it with screenshots.
- Scopes, least privilege:
  - M1: `openid email profile`,
    `…/auth/calendar.calendarlist.readonly`, `…/auth/calendar.events`.
  - M2 (optional, to create a "Family" calendar): `…/auth/calendar.app.created`.
  - M3 (Photos Picker): `…/auth/photospicker.mediaitems.readonly`.
  - M4 (optional): `…/auth/tasks`.
- Several Google accounts per household are supported.
- Without an HTTPS domain (other families): use the Hub's **paste-back
  flow**. The admin opens the consent URL on any browser, then pastes the
  final redirected URL back into the admin UI. **Device-code flow is not
  usable**: Google doesn't allow Calendar scopes there.

**Inbound sync**
- Initial sync per calendar: `events.list` with `singleEvents=false` (keep
  masters + exceptions; we expand locally) over a −1 y … +2 y window, then
  store `nextSyncToken`.
- Incremental: `events.list(syncToken)`. On `410 Gone`, do a full resync
  for that calendar.
- **Push:** `events.watch` channels to
  `https://<hub-domain>/api/webhooks/google/calendar`. A notification
  triggers an immediate incremental sync. Channels renew before their
  `expiration`. A fallback poll runs every 10 min, or every 2 min while a
  device is in the Calendar view.
- Cancelled events (`status=cancelled`) → tombstones. Exceptions map to
  `recurring_parent_id` + `original_start`.

**Outbound**
- Device edits arrive as ops. The Hub outbox sends `insert`/`patch`/`delete`
  with `If-Match: <etag>`. On `412`, refetch and resolve per calendar policy
  (default: **last-writer-wins on field level**, using Google's `updated`
  vs the op HLC time). The user sees a toast if their edit lost.
- Recurring edits:
  - "This event" patches the instance.
  - "This and following" truncates the master's `UNTIL` and creates a new
    series.
  - "All" patches the master.
- Loop prevention: the Hub records `(remote_id, etag)` for every applied
  inbound change and never echoes its own writes.

**Quota & health:** incremental sync with push keeps usage tiny. Per-account
health is shown with a "Reconnect" action when a refresh token is revoked.

### 13.3 ICS & CalDAV

- **ICS [M1]:** poll each URL (default 6 h, minimum 15 min) with
  `ETag`/`If-Modified-Since`. Parse defensively (folded lines, TZID,
  EXDATE, RECURRENCE-ID). Replace that source's events in one transaction.
  Local annotations (profile mapping, icon) survive via the `UID` key.
- **CalDAV [M5]:** two-way via `sync-collection` REPORT. iCloud uses
  app-specific passwords.

### 13.4 Weather

**Weather Underground (PWS key)**
- Current: `GET https://api.weather.com/v2/pws/observations/current?stationId={ID}&format=json&units=e&numericPrecision=decimal&apiKey={KEY}`
- Forecast: `GET https://api.weather.com/v3/wx/forecast/daily/5day?geocode={lat},{lon}&format=json&units=e&language=en-US&apiKey={KEY}`.
  Includes day/night parts with `precipChance`, `qpf`, `cloudCover`,
  `uvIndex`, narratives, sunrise/sunset and moon phase. Note that today's
  `temperatureMax` becomes null in the afternoon.
- Nearby stations: `GET https://api.weather.com/v3/location/near?geocode={lat},{lon}&product=pws&format=json&apiKey={KEY}`.
  Postal lookup: `v3/location/point?postalKey={zip}:US`.
- Key limits: **1,500 calls/day, 30/minute**. Hub cadence: current every
  5 min (288/day) + forecast every 30 min (48/day), so about 340/day.
- WU provides **no hourly forecast and no days 6–7** for PWS keys. That's
  why the keyless sources are always on.

**Open-Meteo (keyless; always on)** — verified for Aurora, CO on 2026-10-02
- `GET https://api.open-meteo.com/v1/forecast?latitude=…&longitude=…&timezone=…&forecast_days=10`
- Current: `temperature_2m, apparent_temperature, weather_code, is_day`
- Hourly: `temperature_2m, precipitation_probability, precipitation,
  cloud_cover, sunshine_duration, uv_index, weather_code, wind_speed_10m,
  wind_gusts_10m`
- Daily: `temperature_2m_max/min, precipitation_sum,
  precipitation_probability_max, precipitation_hours, sunshine_duration,
  daylight_duration, uv_index_max, sunrise, sunset, weather_code`
- Cadence: every 10 min by default (5 with a personal weather station), set
  per household in Settings → Household (5 min to 1 hour). Attribution:
  "Weather data by Open-Meteo.com" (CC BY 4.0).
  Free for non-commercial use.
- **[M4]** Air quality via `air-quality-api.open-meteo.com` (US AQI; pollen
  where available).

**NWS (US; keyless)**
- Alerts: `GET https://api.weather.gov/alerts/active?point={lat},{lon}`
  every 5 min.
- Observations: `/points/{lat},{lon}` → `observationStations` →
  `/stations/{id}/observations/latest`.
- A descriptive `User-Agent` header with contact info is required.

**Geocoding:** ZIP → zippopotam.us (US/CA). City → Open-Meteo geocoding.
With a WU key → WU location point. The result is stored once in `household`.

**Unified model** (Appendix D): `Current`, `Hourly[48]`, `Daily[10]`,
`Alerts[]`, `Astro`, each field tagged with source and timestamp. WMO
weather codes and TWC icon codes map to Dearth's icon set.

### 13.5 Photos

#### 13.5.1 Amazon Photos: shared-album link (unofficial, anonymous)

- **Setup:** in the Amazon Photos app, create an album (e.g. "Dearth
  Frame"), Share → **Get link**, and paste the link into Dearth. Supports
  `amazon.com/photos/share/{shareId}` and regional domains (`.ca`, `.co.uk`,
  `.de`…).
- **Read path** (no cookies or credentials; confirmed by public scripts,
  to be **re-validated in M0** against a real link):
  1. `GET https://www.amazon.{tld}/drive/v1/shares/{shareId}?shareId={shareId}&resourceVersion=V2&ContentType=JSON&asset=ALL`
     returns the album's `nodeInfo.id`.
  2. `GET https://www.amazon.{tld}/drive/v1/nodes/{nodeId}/children?asset=ALL&limit=200&offset={n}&searchOnFamily=false&shareId={shareId}&resourceVersion=V2&ContentType=JSON`
     is paginated. Items carry `id`, `ownerId`, `name` and image metadata.
  3. Derivatives: candidates, in order (validate in M0):
     - `https://thumbnails-photos.amazon.{tld}/v1/thumbnail/{nodeId}?ownerId={ownerId}&viewBox=1920&shareId={shareId}`
     - `…/drive/v1/nodes/{id}/contentRedirection?querySuffix=%3FviewBox%3D1920&shareId={shareId}`
     - `POST …/drive/v1/batchLink?shareId=…` (zip of originals; last resort).
- **Cadence:** refresh the listing every 60 min. Fetch derivatives
  incrementally into the Hub blob store and keep serving from cache
  forever if Amazon changes anything.
- **Failure posture:** health badge + docs. The screensaver never goes blank
  (FR-SSV-06). Because no credentials are involved, breakage can't lock
  accounts or trigger 2FA prompts.
- **Privacy:** an unlisted public link (§9.6). Revoke by deleting the share
  in Amazon Photos.

#### 13.5.2 Google Photos: Picker API (official) `[M3]`

- Since March 31, 2025, third-party apps can't browse libraries or albums;
  only user-picked items are accessible.
- Flow:
  1. Hub `POST https://photospicker.googleapis.com/v1/sessions` returns
     `pickerUri`.
  2. The display or admin shows a **QR code**; an adult picks on a phone
     (≤ 2,000 items).
  3. The Hub polls `sessions.get` until `mediaItemsSet`.
  4. The Hub lists `mediaItems` and downloads `baseUrl=w2048-h2048` with
     the bearer token **within 60 min** (baseUrls expire).
  5. The Hub stores derivatives and deletes the session.
- Re-pick any time to add more. There's no auto-sync; the UI says so.

#### 13.5.3 Immich (official REST API) `[M3]`

- URL + API key (`x-api-key`). The probe checks server version and key
  scope.
- Uses: album list and assets, `search/random` (sampled pools without
  enumerating), metadata search (date, favorites, people), **memories (on
  this day)**, and `thumbnail?size=preview`.
- Endpoints follow the server's OpenAPI for the detected version; the
  adapter is version-gated.

#### 13.5.4 Folder / NAS `[M1]`

- Paths mounted into the Hub container (`/photos/...`). Rescan via
  inotify where available, otherwise every 15 min.
- EXIF date, orientation and GPS are read; HEIC, JPEG, PNG and WebP are
  supported via libvips.

**Common pipeline:** each source yields `photo_item` rows (dedup by
perceptual hash across sources). Derivatives are produced per device class.
Pre-blurred backgrounds, dominant color and blur-hash are computed once
(§14.4).

### 13.6 Recipes

- **TheMealDB:** `www.themealdb.com/api/json/v1/{key}/…` (search, lookup,
  filter by single ingredient, category or area, random). The test key `1`
  works for development. A supporter key unlocks V2 (multi-ingredient
  filter, random selection, latest). Catalog is small (~600–700 meals), so
  it's a baseline source, not the whole story.
- **Spoonacular** (optional key): `complexSearch` (sort=popularity, diets,
  intolerances, maxReadyTime), `findByIngredients`, `{id}/information`,
  `{id}/similar`, random. **Free tier ≈ 50 points/day**: the Hub enforces a
  daily point budget, caches responses for 7 days, and degrades gracefully
  when the budget runs out.
- **URL import:** the Hub fetches the page (desktop UA, size and time
  limits), extracts **schema.org `Recipe`** from JSON-LD (incl. `@graph`)
  or microdata, sanitizes HTML, downloads the image, and runs the
  ingredient parser. Pages without structured data trigger "Couldn't read
  this recipe automatically; paste the ingredients?" (with optional AI
  cleanup in M5).
- **Attribution:** every recipe shows source name and link, and provider
  terms are respected (§18).

### 13.7 Music

- **Own files:** upload via the companion or web admin, or point at a Hub
  folder. Tags are read for title, artist and cover art. Files are
  transcoded only if the codec is unsupported (AAC/MP3 pass through).
  Devices cache boards for offline play.
- **YouTube / YouTube Music:**
  - Parents paste links; the Hub resolves title and thumbnail via
    **oEmbed** (no API key).
  - Playback uses the official IFrame player in `webview_flutter`
    (`youtube_player_iframe`) with related videos limited (`rel=0`), no
    keyboard, inline playback, and an overlay that absorbs taps on the
    YouTube logo and title links.
  - Embed-blocked videos (errors 101/150) are flagged on the tile.
  - **M0 spike:** compare an in-tree platform view against a dedicated
    native activity for smoothness and memory on T1.
  - Ads may appear: Premium can't be signed in to inside an embedded player
    on this device.
- **Spotify:**
  - Authorization Code + PKCE on the Hub with redirect to the HTTPS domain.
    Scopes: `user-read-playback-state user-modify-playback-state
    playlist-read-private user-library-read`.
  - Play via `PUT /v1/me/player/play?device_id=…` with `uris` or
    `context_uri`. Devices come from `GET /v1/me/player/devices`.
  - **Premium required.** Spotify apps in development mode are limited to
    an allowlist of users, which is fine for one family.
  - Whether the Spotify Android app runs on the 32-bit frame (making it a
    Connect target with local audio) is an **M0 check**. Otherwise it plays
    on Echo, Sonos or phones.
- **Amazon Music (via Home Assistant) [M4]:** requires the community
  **Alexa Media Player** integration in HA. The Hub calls
  `media_player.play_media` on an Echo entity with
  `media_content_type: AMAZON_MUSIC` and a search phrase. It's fragile by
  nature (unofficial on HA's side) and isolated to that tile type. A
  generic **"HA script" tile** is also offered.

### 13.8 Home Assistant `[M4]`

- **Transport:** the Hub keeps one WebSocket to `wss://<ha>/api/websocket`,
  authenticated with a long-lived access token. It uses `subscribe_entities`
  for exposed entities, `call_service` for actions, and `subscribe_events`
  for `dearth_*` events and doorbell or motion triggers.
- **Camera:** `GET /api/camera_proxy/{entity}` snapshots, resized by the Hub
  and streamed to displays as an ephemeral channel.
- **TTS for displays without an engine:** `POST /api/tts_get_url`
  `{engine_id, message, language}` returns an audio URL. The Hub fetches and
  caches the clip as a blob; the display plays it with just_audio. Chore,
  routine and reminder prompts can be pre-generated this way when no parent
  recording exists.
- **Notifications:** `notify.mobile_app_<phone>` with actionable buttons for
  approvals. HA returns `mobile_app_notification_action` events, which the
  Hub handles.
- **To-do mirror:** `todo.get_items`, `todo.add_item` and `todo.update_item`
  against a chosen HA to-do entity (FR-SHOP-06).

### 13.9 FreeKiosk bridge (frames running FreeKiosk)

- Local REST at `http://127.0.0.1:<port>` with `X-API-Key`. The key is
  stored in device secure storage and set during provisioning.
- Used for:
  - `POST /api/screen/off` and `/api/screen/on` (true screen off via
    Device-Owner `lockNow()` and wake).
  - `POST /api/brightness`, `/api/autoBrightness/disable`.
  - `GET /api/status`, `/api/health`.
  - `POST /api/reboot` (admin-initiated only).
- **FreeKiosk's own screensaver is disabled** (`/api/screensaver/off`) so it
  never fights Dearth's.
- **Fallback when FreeKiosk is absent:** window-level brightness and a black
  overlay. "Off" mode is then 0 % brightness, not a physically off screen.

### 13.10 Holidays

Public holidays come from a bundled dataset, with optional refresh from
Nager.Date (keyless). The family picks a region; school calendars arrive via
ICS.

---

## 14. The Hub server

### 14.1 Responsibilities

The Hub:
- is the **sync authority**: validates ops, keeps the op log, fans changes
  out, and serves snapshots;
- runs **integration workers** and the **job scheduler**;
- runs the **media pipeline** and **blob store**;
- serves the **web app** (iPhone PWA + admin) and the OAuth, webhook and
  pairing endpoints;
- handles **device management**: pairing, roles, commands, APK hosting,
  diagnostics.

### 14.2 API surface (v1)

All endpoints live under `/api`, require a device token or admin session
except where noted, and return JSON. A versioned OpenAPI document is
generated from the shelf routes and committed.

| Area | Endpoints |
|---|---|
| Health | `GET /health` (no auth) · `GET /version` |
| Pairing | `POST /pair/start` (device, no auth) → code + QR payload · `POST /pair/approve` (admin) · `POST /pair/claim` (device) → token · `DELETE /devices/{id}` |
| Sync | `WS /sync` (push/ack, live ops, ephemeral channels, commands) · `GET /sync/snapshot?scopes=` · `GET /sync/ops?since=&limit=` (fallback) |
| Blobs | `GET /blobs/{sha}?v={variant}` · `POST /blobs` (multipart, ≤ 50 MB, type-checked) |
| OAuth & webhooks | `GET /oauth/{provider}/start` · `GET /oauth/{provider}/callback` (public) · `POST /webhooks/google/calendar` (public, channel-token verified) · `POST /webhooks/ha/{secret}` (public, secret-verified) |
| Recipes | `GET /recipes/search` · `GET /recipes/discover/{feed}` · `POST /recipes/import {url}` · `POST /recipes/recommend {period}` |
| Music | `POST /music/resolve {url}` · `GET /music/spotify/devices` · `POST /music/play {tile, target}` · `POST /music/control` |
| Photos | `POST /photos/sources/{id}/refresh` · `POST /photos/google/picker` (new session) · `GET /photos/google/picker/{id}` |
| Smart home | `POST /ha/call` (ACL-checked) · `GET /ha/camera/{entity}` (snapshot) |
| Devices | `POST /devices/{id}/command` (wake, sleep, reload, screenshot, chime, announce, timer) · `GET /devices/{id}/screenshot/latest` · `GET /devices/{id}/logs` |
| Updates | `GET /app/latest?abi=&channel=` · `GET /app/apk/{version}/{abi}` |
| Admin | `GET/PUT /admin/settings` · `/admin/integrations/*` · `POST /admin/backup` · `POST /admin/export` · `POST /admin/import` |
| Web | `/` (Flutter web app, PWA manifest, service worker, COOP/COEP headers) |

### 14.3 Jobs & schedules

| Job | Cadence |
|---|---|
| Weather (WU current and forecast, Open-Meteo, NWS alerts, one run) | Every 10 min by default, 5 with a personal weather station; per household, 5 min to 1 hour |
| Google Calendar | Push-triggered + fallback 10 min; channel renewal daily |
| ICS feeds | Per source (default 6 h) |
| Photos: Amazon share / folders / Immich pool top-up | 60 min / inotify or 15 min / 6 h |
| Chore & routine materialization | Hourly + at local midnight (household TZ) |
| Recipe cache cleanup, Spoonacular budget reset | Daily |
| Backups | Nightly 03:30 local |
| APK update check (GitHub releases, optional) | Daily |
| HA connection | Persistent with reconnect backoff |
| Blob store GC (unreferenced, older than 7 d) | Weekly |

### 14.4 Media pipeline

- **libvips** (`vips` CLI or FFI) in the Hub image: fast, streaming and
  low-memory. Handles JPEG, PNG, WebP, HEIC (libheif) and AVIF.
- Per photo:
  - EXIF auto-rotate.
  - Variants: `cover-1920x1080`, `cover-1080x1920`, `card-960`,
    `thumb-384`.
  - Smart crop focus from faces or saliency (`vips smartcrop attention`).
  - Pre-blurred background (`bg-blur-640`).
  - Dominant color + blur-hash.
  - Perceptual hash for dedup.
- Per audio file: tag extraction and cover art (`ffprobe`), loudness
  analysis (EBU R128) for volume normalization.
- Variants are generated lazily on first request and cached. Per-device-class
  variants are prewarmed for screensaver pools.

### 14.5 Configuration (environment)

| Variable | Default | Purpose |
|---|---|---|
| `DEARTH_DATA_DIR` | `/data` | Database (SQLite), blobs, backups, logs |
| `DEARTH_DB_URL` | *(unset → SQLite)* | `postgres://user:pass@host:5432/dearth` to use Postgres |
| `DEARTH_PUBLIC_URL` | — | `https://dearth.example.com`. Needed for OAuth redirects, webhooks and the PWA. |
| `DEARTH_LAN_URLS` | — | Extra origins for LAN access, e.g. `http://10.0.1.20:8080` |
| `DEARTH_SECRET_KEY` / `_FILE` | — (required) | Master key for secrets at rest |
| `DEARTH_PORT` | `8080` | HTTP port (TLS terminates at the reverse proxy) |
| `DEARTH_TRUSTED_PROXY_HEADERS` | `false` | Accept SSO identity headers from the reverse proxy |
| `DEARTH_PHOTO_DIRS` | — | Colon-separated mounted photo folders |
| `DEARTH_MUSIC_DIRS` | — | Colon-separated mounted music folders |
| `DEARTH_LOG_LEVEL` | `info` | Structured JSON logs |

### 14.6 Deployment

```yaml
# compose.yml (excerpt)
services:
  dearth:
    image: ghcr.io/robertzas/dearth-hub:latest     # multi-arch: amd64, arm64
    restart: unless-stopped
    environment:
      DEARTH_PUBLIC_URL: https://dearth.example.com
      DEARTH_SECRET_KEY_FILE: /run/secrets/dearth_key
      # DEARTH_DB_URL: postgres://dearth:***@postgres:5432/dearth   # optional
    volumes:
      - dearth-data:/data
      - /mnt/nas/photos/frame:/photos/nas:ro
      - /mnt/nas/music/kids:/music/kids:ro
    ports: ["8080:8080"]
    secrets: [dearth_key]
    healthcheck: { test: ["CMD", "/app/dearth-hub", "healthcheck"], interval: 30s }
volumes: { dearth-data: {} }
secrets: { dearth_key: { file: ./dearth_key } }
```

The image is built from a multi-stage Dockerfile (`dart compile exe`,
then `debian:stable-slim` + libvips + ffmpeg for `ffprobe`) and runs as a non-root
user. A reverse proxy (Caddy, Traefik, NGINX) terminates TLS for the HTTPS
domain and must allow WebSocket upgrades on `/api/sync`.

### 14.7 Observability & resource budget

- Structured JSON logs. `GET /api/metrics` exposes Prometheus metrics: sync
  lag, ops/s, connected devices, job durations, provider errors and quota
  use.
- Budget on a Raspberry Pi 4-class host: **RSS ≤ 256 MB steady**, idle CPU
  < 2 %, cold start < 2 s.

---

## 15. Kiosk deployment & device management

### 15.1 Phase 1: the kitchen frame under FreeKiosk "External App" mode

The frame state (2026-10-03): FreeKiosk v2.0.0-beta.4 is **Device Owner**
and the HOME launcher, in External App mode locked to Dearth. The owner
switched it from the old webapp while v1 is still in progress, so the frame
is a working test bed. `tool/deploy_frame.sh` (§15.2) sets all of the below
up, including after a factory reset.

1. Build `apps/dearth_app` release APK for **armeabi-v7a**, signed with the
   Dearth release key.
2. `adb install` it, then pair the device with the Hub (QR flow).
3. Reconfigure FreeKiosk to **External App mode** targeting Dearth's
   package id. Keep auto-relaunch on exit or crash, the PIN-protected magic-corner
   settings gesture, and boot autostart.
4. Disable FreeKiosk's screensaver; keep its REST API on, bound to
   localhost, with the key handed to Dearth during provisioning.
5. Dearth hides the system bars on wall displays (immersive) and follows
   the accelerometer (`fullSensor`), whatever Android's auto-rotate switch
   says.
6. Optionally `pm disable-user com.fujia.calendar`. **Never disable
   `com.waophoto.fota`**: it crash-loops this ROM (see the FreeKiosk skill notes).
7. Verify with Dearth's own remote screenshot (FR-ADM-02) and the Admin →
   Devices health view.

**Toddler consideration:** the magic corner is an invisible 48 dp button
8 dp from the bottom-right corner; 5 taps on it within 2 s open a PIN
prompt. Repeated toddler taps can surface that prompt but never get past
it. Dearth keeps the bottom-right corner free of controls
(`kKioskCornerClearance`); FreeKiosk's tap-anywhere mode is not used,
because any 5 quick taps in Dearth would trigger it. FreeKiosk needs the
"display over other apps" app-op for the corner to exist at all: Device
Owner does not grant it on the JT215M ROM.

### 15.2 Provisioning script

`tool/deploy_frame.sh <ip> [--check] [--build | --apk FILE] [--reboot]`
reuses the logic and quirk handling of the old `setup-freekiosk.sh`. It
installs or upgrades FreeKiosk (pinned, SHA-256 checked) and the Dearth APK
for the device's ABI, makes FreeKiosk Device Owner and HOME, writes the
External App config (a second time when the beta.4 config-ordering quirk
leaves the old overlay running), turns on auto-rotate and adaptive
brightness, and verifies by reboot. Every step reads the device first and
changes only what differs; `--check` reports without changing anything.
Still to come: pairing with a Hub (`--hub <url>`) and the FreeKiosk REST
key handoff (§13.9).

### 15.3 App updates

| Mode | How updates install |
|---|---|
| Under FreeKiosk (Phase 1) | `tool/deploy_frame.sh` pushes the new APK over LAN ADB, one frame per run (developer path). In-app "Update available" for others, **if** the system installer UI can appear under FreeKiosk's lock task (M0 check). |
| Dearth as Device Owner/launcher (M5, optional) | **Silent** `PackageInstaller` sessions from the Hub's APK feed, with staged rollout (one frame first) and automatic rollback if the new version fails to report healthy within 10 min. |
| Phones | Android: APK channel from the Hub (or a store later). iPhone: the PWA updates on reload. |

### 15.4 Watchdog & recovery

- FreeKiosk relaunches Dearth on crash. Dearth restores the last screen and
  mode within 3 s.
- Uncaught errors in a feature show a friendly "This part hiccuped" card
  with retry, never a red error screen. Errors are reported to the Hub.
- An optional nightly maintenance window (03:45) restarts the app
  (FreeKiosk `restart-ui`, or app self-restart) for long-uptime hygiene.
- Recovery playbook (factory-reset-safe) in `docs/frame-recovery.md`,
  including the FreeKiosk device-owner removal steps.

### 15.5 Other devices

| Device | Kiosk approach |
|---|---|
| Kid-room and entry tablets | FreeKiosk External App mode (same script), or Android screen pinning on tablets with Play Services |
| Phones | Normal app (Android) or PWA (iPhone). No kiosk. |

The provisioning script detects ABI and installs the matching APK
(`armeabi-v7a` or `arm64-v8a`).

### 15.6 Future: Dearth as its own launcher ★ `[M5]`

Dearth can become the HOME app and Device Owner itself, replacing FreeKiosk.
This would add:
- silent OTA updates;
- `lockNow()` screen-off and wake scheduling;
- scheduled reboots;
- the lock-task allowlist (e.g. Spotify);
- no dependency on FreeKiosk's beta releases.

Revisit after v1 based on how well FreeKiosk works in practice.

---

## 16. Quality & engineering practices

### 16.1 Testing strategy

| Layer | What | Tooling | Bar |
|---|---|---|---|
| Core logic (unit) | HLC/LWW merge, recurrence (incl. DST and exceptions), quick-add, schedule materialization, ingredient parsing, unit conversion, consolidation, reuse scoring, solar math, weather merge, ledger balances | `package:test` | ≥ 90 % line coverage on `dearth_core`; ported test vectors from the old editions |
| App logic (unit) | Riverpod providers, repositories, display-mode state machine, idle engine, grown-up/kiosk gesture recognizers, sync client (against an in-process Hub) | `flutter_test` | ≥ 80 % line coverage on non-widget app code |
| Sync convergence | Random op streams × 3 nodes × reordering, duplicates, offline gaps, clock skew | Property-based tests (custom generators) | 10k cases per CI run; invariants in §8.4.8 |
| Provider adapters | Every adapter against **recorded fixtures**, including error, quota and 410/412 cases | Fake HTTP client | Runs offline in CI |
| Hub | Route handlers, ACLs, pairing, snapshot, backups/restore drill | `package:test` + in-memory SQLite + Postgres service container | Both DB backends in CI |
| Widgets | Every `dearth_ui` component and key screen | `alchemist` goldens: 4 display classes × Light/Evening/Night × T1/T3 variants | Golden diffs reviewed in PRs |
| **Web E2E (primary end-to-end suite)** | **Every user journey** in §10 on the Flutter **web build**, served by a real Hub started with a fresh data dir and **fake providers** (deterministic weather, recipes, calendars, photos). Viewport projects: Wall-L 1920×1080, Wall-P 1080×1920, Tablet 1280×800, Phone 390×844. Includes **multi-device sync** tests (two browser contexts paired to one Hub), offline/reconnect, grown-up PIN, kiosk gesture, toddler lock, screensaver timing, and visual snapshots of key screens. | **Playwright** (`e2e/`), selectors are semantics identifiers (§16.3) | Required on every PR; release blocker |
| Native smoke | What web E2E cannot reach: Android platform channels (FreeKiosk bridge, light sensor, brightness, wake lock), native SQLite on armv7, audio, YouTube platform view, FreeKiosk External App behavior | `integration_test`/`patrol` on the frame via `tool/perf_gate.sh --smoke` | Required for display releases |
| Performance | §12.9 scenarios on the frame | `tool/perf_gate.sh` | Release blocker |
| Toddler monkey | 30-minute random-tap/drag fuzz on kid surfaces and Home with toddler lock on/off | `patrol` custom driver | 0 destructive actions, 0 exits from locked surfaces, 0 crashes |
| Accessibility | Contrast, labels, tap targets | `flutter_test` accessibility guidelines + manual audit | AA for Light/Evening |

### 16.2 CI/CD (GitHub Actions)

- On every PR:
  - Format and analyze (strict lints plus custom rules from §12.3).
  - Unit, property, Hub and golden tests.
  - **Playwright web E2E** against the web build + a test Hub (all viewport
    projects; traces, screenshots and videos kept on failure).
  - Build: armeabi-v7a and arm64 APKs, web, Linux, Windows, macOS, iOS
    (no-codesign), Hub Docker image.
- On `main`: publish the Hub image (`ghcr.io`, multi-arch) and attach APKs
  to a rolling pre-release.
- On tags: full release with notes, APKs uploaded to the Hub's update
  channel, and the perf-gate report attached (run on the LAN frame by a
  self-hosted runner or manually).

### 16.3 Conventions (to be codified in `AGENTS.md` at M0)

- Dart 3.13, `strict-casts`, `strict-raw-types`, `strict-inference`. No
  `dynamic` in feature code. No `print` (structured logger).
- Feature-first folders (`lib/features/calendar/{data,domain,ui}`).
  Widgets never call HTTP or providers directly.
- FR IDs appear in test names (`FR-CAL-12: quick add parses "…"`), in
  both Dart tests and Playwright specs.
- **Test identifiers:** every interactive or asserted widget on a user
  journey carries a stable `Semantics(identifier: 'area.thing')` (helper
  `tid()`). On web this renders as the `flt-semantics-identifier` DOM
  attribute that Playwright selects on. The app force-enables the semantics
  tree when started with `?e2e=1` (or `--dart-define=DEARTH_E2E=true`).
  Identifiers are part of the test contract: renaming one is a breaking
  change for `e2e/`.
- **Why web E2E is the primary suite:** Flutter renders the same widgets and
  runs the same Dart on web and native, so journeys verified in Chromium hold
  on Android/iOS/desktop. Web can't verify platform channels, armv7 native
  libraries, or Impeller-GLES performance; those stay covered by the native
  smoke test and the perf gate.
- Changing specified behavior means updating this SPEC in the same PR.
- Dependencies: each new package needs a justification line in the PR,
  armv7 verification if it's native, and license compatibility. Prefer
  first-party (Dart/Flutter team) packages.

### 16.4 Definition of done (per feature)

- FRs implemented and tested; goldens recorded for all display classes.
- T1 perf scenario added or updated and green on the frame.
- Works offline (or degrades as specified); sync conflicts considered.
- Kid-surface safety reviewed if any child can reach it.
- Empty, loading and error states designed. Accessibility labels in place.
- Docs updated (user guide + SPEC).

### 16.5 License

**AGPL-3.0** (consistent with previous editions) unless the owner prefers
MIT/Apache for wider reuse (see §19). Third-party assets: OFL fonts, MIT
Fluent Emoji, CC0 Kenney assets and sounds. A licenses screen is generated.

---

## 17. Roadmap & milestones

Each milestone ends in a usable product on the real frame. **v1.0 (the
"switch the frame" release) = M1 + M2 + M3.**

### M0: Foundations & de-risking spikes
Each spike has a written result in `docs/spikes/` and a go/no-go.

| # | Spike | Exit criteria |
|---|---|---|
| S1 | **Renderer benchmark** on the JT215M (armv7 profile APK, Impeller-GLES) for the §12.9 scenarios + blur/shadow/clip micro-benchmarks | Budgets met, or design rules adjusted with evidence |
| S2 | drift + sqlite3 (native assets) build and run on **armeabi-v7a**; background isolate; 50k-row query timings | Works; p95 query < 10 ms for Home queries |
| S3 | Sync prototype: Hub + frame + web client; offline edits; reconnection; fan-out latency | Converges; p95 LAN fan-out ≤ 1 s |
| S4 | **Amazon shared album** with the owner's real link: listing, pagination, derivative endpoint, a 7-day stability watch | ≥ 1 working derivative path |
| S5 | Google OAuth on the Hub via the HTTPS domain ("In production" status); calendar list; `events.watch` webhook round trip | Push-triggered sync < 15 s |
| S6 | WU key: current + 5-day + nearby stations; merge with Open-Meteo/NWS | Unified model populated |
| S7 | YouTube IFrame on the frame: platform view vs dedicated activity; memory; embed-blocked detection | Smooth playback, PSS within budget |
| S8 | Spotify Connect: device list and playback on an Echo/phone; can the Spotify app run on the frame? | Playback works on at least one target |
| S9 | FreeKiosk External App mode with a test APK: auto-relaunch, localhost REST (screen off/on, brightness), 5-tap overlap, installer UI under lock task | All behaviors documented |
| S10 | Audio: flutter_soloud latency on armv7 (< 30 ms); just_audio streaming; mixing | Pass, or choose an alternative |
| S11 | Light sensor → brightness curve; accelerometer auto-rotation | Comfortable curve by day and night |
| S12 | **Design direction:** hi-fi mockups of Home (L/P), Calendar week, Recipe detail, Kid chart, Toybox, Screensaver, Weather. Font choice validated on the panel at distance. | Owner sign-off |
| S13 | Image decode: 1080p JPEG vs WebP decode time and memory on the frame | Variant formats confirmed |

Also in M0: repo scaffold (pub workspace), CI, `AGENTS.md`, `dearth_ui`
token foundation, widget gallery, **Playwright E2E harness** (test Hub with
fake providers, viewport projects, semantics-identifier selectors).

### M1: Wall-ready core
Hub (pairing, sync, blobs, jobs, admin basics, backups) · app shell, design
system, navigation for all display classes · Home (core widgets) ·
**Calendar** (Google two-way + ICS + local; all views except People and
Kid timeline; quick add; editor; countdowns; up next) · **Weather** (WU +
Open-Meteo + NWS; widget + screen) · **Photos & screensaver** (Amazon
shared album + NAS folder; curation grid; pairing and pre-blur) · display
modes + auto-brightness + FreeKiosk bridge · grown-up mode · Android
companion basics + PWA shell · Admin → Devices, screenshots, logs.

### M2: Meals & household
Recipe providers (TheMealDB, Spoonacular, URL import, family box) ·
discovery feeds · recipe detail + scaling · cook mode + timers · planner ·
consolidated shopping list + phone store mode · plan-aware recommendations
· ingredient KB · kitchen timers · lists/templates · doodle notes · bin day
· morning briefing · Edit Home · People calendar view · weather on events ·
birthdays and holidays · Web Push · web admin for content · drag-to-move
events · on-display reminders · optional shared "Family" Google calendar ·
photo collections · photos sent from phones · share targets · clock faces ·
Wi-Fi QR widget · APK update channel.

### M3: Kids & play
Kid stages · chores + library · routines + run mode + visual timers ·
First–Then and choice boards · sticker book, reward jar, star economy,
family goal, kindness hearts, garden · potty chart · celebrations catalog
· buddy · feelings check-in · **Toybox launch set** (10 games) with
adaptive difficulty and parent controls · **Music box** (files, YouTube,
Spotify) · kid timeline view · What to wear · **Immich** and **Google
Photos Picker** · kid art in the screensaver · voice notes · remote device control from the
companion · perf and polish pass →
**v1.0 release; switch the frame from the old webapp.**

### M4: Smart home & multi-room (v1.1)
Home Assistant (tiles, doorbell pop-up, presence wake, who's home, events
both ways, TTS, actionable notifications, to-do mirror) · Amazon Music via
HA · **Kid room** role (OK-to-wake, night light, sleep sounds) · **Entry**
role · announcements · Toybox expansion set · skills progress · air quality
· guest/babysitter mode · pet care log · leave-by times · dance-party scene ·
kid-room music (lullabies, sleep sounds).

### M5: Extensions (v1.2+)
AI provider (if approved) · CalDAV/iCloud + Microsoft 365 · share links ·
Solo mode + Hub-on-device · Dearth as Device Owner launcher + silent OTA ·
passkeys · i18n · ntfy · Mealie/Tandoor · voice via HA Assist.

---

## 18. Risks & mitigations

| Risk | Likelihood / impact | Mitigation |
|---|---|---|
| Impeller-GLES on PowerVR GE8300 underperforms or renders incorrectly | Med / High | S1 benchmark first; tiered effects; pinned Flutter for display builds; upstream reports; time-boxed Skia fallback |
| Flutter/Dart drops 32-bit ARM, or Skia opt-out removal lands before we're ready | Low–Med / High | Pin display builds; monitor release notes; frames keep working on the pinned version; future hardware is arm64 |
| Amazon changes the anonymous share endpoints | Med / Med | Cache-forever pipeline; multiple derivative paths; health badge; Immich/folder alternatives; no credentials means no account lockouts |
| Google OAuth "Testing" status expires tokens after 7 days | High if missed / Med | Setup docs + Hub health check warn on Testing status; reconnect flow |
| WU API key limits or policy changes | Low / Low | Keyless sources always on; ~340 calls/day vs a 1,500 limit |
| YouTube embeds: ads, embed-blocked videos, player changes | High / Low–Med | Own files as the primary toddler source; embed checks on tile creation; overlay to block link-outs |
| Spotify dev-mode limits or Premium requirement | Med / Low | Family allowlist; tiles show the requirement; other sources unaffected |
| Alexa Media Player (unofficial) breaks | Med / Low | Isolated to Amazon Music tiles; generic HA script tiles as a workaround |
| Low-memory killer on a 2 GB `low_ram` device | Med / High | Memory budgets, keep-alive limits, pressure handling, soak tests, FreeKiosk auto-relaunch + state restore |
| FreeKiosk beta regressions | Med / Med | Pin a known-good version; provisioning script; M5 own-launcher option |
| Sync bugs (lost or duplicated data) | Low–Med / High | Property-based convergence tests, append-only ledgers, deterministic IDs, op log retention, nightly backups |
| Hub exposed on the internet | Med / High | Token auth everywhere, admin 2FA or SSO, rate limits, minimal public endpoints (OAuth callback, webhooks with secrets), security headers |
| Recipe provider ToS (caching, attribution) | Low / Med | Respect per-provider caching rules; attribution on every recipe; family box copies only what's needed for planning; URL import is for personal use |
| Scope creep vs quality bar | High / High | Milestone discipline; v1 = M1–M3; DoD includes perf and goldens; ★ items are optional |

---

## 19. Open questions

1. **Screen size:** the frame reports model JT215M (usually a 21.5" panel),
   but it's described as 27". Which is it? This drives the default
   `uiScale`.
2. **Kitchen mounting orientation** (landscape or portrait)? Both are
   supported; this sets which layout gets the most polish first.
3. **Android package id and app name:** keep "Dearth"? The package id must
   be fixed before the first install (FreeKiosk targets it).
4. **License:** AGPL-3.0 as before, or MIT/Apache?
5. **Calendars:** which Google accounts and calendars? Create a shared
   "Family" calendar (FR-CAL-04)? Week start (Sun/Mon) and 12/24 h?
6. **Family details for personalization:** names, colors, the daughter's
   favorite themes (animals? dinosaurs? space?) for stickers, buddy and
   coloring packs; dietary restrictions or allergies.
7. **Amazon shared link comfort:** OK with an unlisted public album for the
   frame? A dedicated "Dearth Frame" album is recommended.
8. **Spotify Premium?** (Required for playback control.) Is **Alexa Media
   Player** already installed in HA?
9. **Recipe keys:** OK to register a free Spoonacular key? Interested in
   TheMealDB's supporter tier (multi-ingredient search, random sets)?
10. **Hub domain & LAN:** do LAN devices resolve the HTTPS domain to the
    LAN IP (split-horizon DNS), or should displays use the LAN IP directly?
11. **Toddler-room and entry hardware:** which tablets? Their tier and ABI
    affect testing.
12. **Grandparents:** should they get anything (read-only calendar link,
    sending photos to the frame, cheering on chores)?

---

## 20. Appendices

### Appendix A: JT215M raw facts (2026-10-02)

```
model JT215M-H01 · brand Allwinner/joyhong · hardware sun50iw10p1 · platform ceres
Android 10 (SDK 29) · patch 2020-11-05 · test-keys · ro.secure=0 · debuggable
ABI armeabi-v7a, armeabi (32-bit only; zygote32) · kernel 4.9.170 armv8l
CPU 4× Cortex-A53 (0xd03) max 1.512 GHz schedutil
RAM 2,017,644 kB; ~1.03 GB free with FreeKiosk running · ro.config.low_ram=true
dalvik heapgrowthlimit 128m / heapsize 256m
GPU PowerVR Rogue GE8300, OpenGL ES 3.2 build 1.11@5516664; Vulkan 1.0.3 (vulkan.ceres.so)
Display 1080×1920 (native portrait) @ 56.0 Hz · density 230, override 173
Sensors: accelerometer (Mi3da), light (pt3r850) · cameras: 0 · TTS engines: none
WebView com.android.webview 124.0.6367.219 · Google Play Services: absent
Storage /data 26 GB (24 GB free)
FreeKiosk 2.0.0-beta.4 (Device Owner, HOME) · com.freekiosk PSS ≈ 318 MB (WebView mode)
Flutter 3.47.2 engine: Impeller detects PowerVR Rogue → "Known bad Vulkan driver… falling back to OpenGLES"
```

### Appendix B: Toybox game catalog (ages 2–5)

Difficulty ladders advance automatically (FR-TOY-04). Ages are starting
points, not limits.

| Game | Ages | Skills | How it plays | Difficulty ladder | Milestone |
|---|---|---|---|---|---|
| Paint Studio | 2+ | Creativity, fine motor | Brushes, crayon, spray, rainbow, stamps, backgrounds, undo; saves to art gallery | Tools unlock: stamps → layers → symmetry mode | M3 |
| Magic Coloring | 2+ | Colors, fine motor | Tap-to-fill line art | 4 big regions → 30 small regions | M3 |
| Bubble Pop & Fireworks | 2+ | Cause and effect | Pop bubbles, finger-trail fireworks | Bubbles slow → faster; color-call "pop the blue ones!" | M3 |
| Animal Sounds Farm | 2+ | Vocabulary, listening | Tap animal → name + sound | "Where's the cow?" find-it mode | M3 |
| Shape Sorter | 2+ | Shapes, spatial | Drag shapes into holes | 2 shapes → 8, rotated holes | M3 |
| Jigsaw (family photos) | 2+ | Spatial reasoning | Drag pieces, snaps when close | 2 → 4 → 6 → 9 → 12 → 16 → 24 pieces | M3 |
| Memory Match | 2.5+ | Working memory | Flip pairs (emoji or family faces) | 2 → 12 pairs | M3 |
| Feed the Monster | 2.5+ | Classification | Monster eats only one color/shape/category | 1 attribute → 2 attributes ("red AND round") | M3 |
| Counting Garden | 3+ | Number sense | Tap to count flowers; "how many?" | 1–3 → 1–10 → subitizing flashes | M3 |
| Xylophone & Drums | 2+ | Music, rhythm | Low-latency pentatonic bars, drums | Free play → echo my rhythm | M3 |
| Patterns | 3+ | Logic | What comes next? | AB → AAB → ABC → growing patterns | M4 |
| Odd One Out | 3+ | Categorization | Tap the one that doesn't belong | Color → shape → category → function | M4 |
| Shadow Match | 2.5+ | Visual discrimination | Drag object to its silhouette | 2 → 6 options, similar shapes | M4 |
| Size Order | 2.5+ | Seriation | Line up small → big | 3 → 6 items | M4 |
| Finger Mazes | 3+ | Planning, motor | Guide buddy home with a finger | Wide paths → branches → dead ends | M4 |
| Sequencing Stories | 3.5+ | Narrative, cause/effect | Put 3–4 pictures in order (seed → sprout → flower) | 3 → 5 cards | M4 |
| Letter & Name Tracing | 3.5+ | Pre-writing | Trace with arrows; **trace her own name** | Lines → curves → letters → name | M4 |
| Number Tracing | 3.5+ | Numerals | Trace 0–9 with voice | 1–3 → 0–9 | M4 |
| Letter Sounds | 3+ | Phonics | Tap letter → sound + picture word | Hear → find the letter → first-sound game | M4 |
| Rhyme Time | 4+ | Phonological awareness | Which one rhymes with "cat"? | 2 → 4 choices | M4 |
| Picture Sudoku | 4+ | Logic | 4×4 grid with fruit pictures | 1 blank → 6 blanks | M4 |
| Spot the Difference | 4+ | Attention | Find 3–7 differences | Big → subtle | M4 |
| I Spy | 3+ | Vocabulary, attention | "I spy something yellow" in a scene | Colors → shapes → letters | M4 |
| Who's That? | 2+ | Family recognition | Tap Grandma among family faces | 2 → 6 faces | M4 |
| Build-a-Creature | 2.5+ | Creativity, language | Mix body parts; it dances and says its silly name | More parts and colors | M4 |
| Music Sequencer | 4+ | Patterns, music | 8-step grid of animal sounds loops | 4 → 8 steps, 2 → 4 tracks | M4 |
| Weather Dress-Up | 2.5+ | Reasoning, self-care | Dress buddy for **today's real forecast** | Pick one item → full outfit | M4 |
| Freeze Dance | 2+ | Movement, self-regulation | Dance until the music stops | Longer and shorter pauses, "dance like a frog!" | M4 |
| Breathing Buddy | 3+ | Calm-down | Balloon inflates and deflates; "smell the flower, blow the candle" | 3 → 5 breaths | M4 |
| Story Time | 2+ | Language, connection | Picture stories read in **family voices** (grandparents record from phones) | — | M4 |
| Dot-to-Dot | 3+ | Number order, numerals, alphabet order | Join the dots in order to reveal a picture that comes alive; the voice says each number or letter, and which one to find after a wrong dot | 1→5 → 1→10 → 1→15 → 1→20 → A→M → A→Z | M4 |
| Big & Little Letters | 3.5+ | Letter recognition: capitals and small letters | Little letters find their big letters; the voice names each pair | 3 look-alike pairs (c C, o O, s S) → 5 pairs that look different (a A, g G) → b, d, p and q | M4 |
| Frog Hop | 3.5+ | Number line, one more and one less, first adding | A frog hops along numbered lily pads: "Hop to 6!", "One more than 4!", "3 and 2 more!" as hops | 0–5 → 0–10 → one more / one less → adding as hops | M4 |
| Word Builder | 4.5+ | Phonics: blending and spelling | Build the picture's word (cat, sun, bed) from letter tiles; each tile says its sound and the voice blends the word at the end | Missing first letter → missing last → all three → four-letter words | M4 |
| Hear the Sound | 3+ | Phonics, listening | "Which letter says sss?" — the sound alone, no word; she taps the letter that says it | easy sounds (a, m, s, p, t) → similar pairs (b/p, d/t, k/g) → digraph sounds (sh, ch, th) with their letters together | M4 |
| Sight Words | 4+ | Early reading, whole words | Words on signs and labels; the voice says the word, she taps it | 2-letter (a, I, go, no) → common 3-letter (the, and, can, stop) → 4-letter (here, with, look) → two-word labels (the bus) | M4 |
| Banana Balance | 3+ | Comparing quantities | A see-saw with two plates of bananas; "Which side has more?" — it tips when she chooses | pictured piles → pictured vs. the numeral → two numerals | M4 |
| Who Has More? | 3.5+ | Comparing numerals | Two cars, buses or kids with numbers; "Which one is more, 3 or 7?" then "which is fewer?" | 0–9 → 0–20 → more-versus-fewer mixed → order three | M4 |
| Name Zoo | 3.5+ | Reading first names | Animal queue at the zoo gate, each wanting a name card; she taps the card for the name the voice spells | her own name → her family's and buddies' names → short names built letter by letter | M4 |
| Tallies | 3.5+ | Keeping count | Each rabbit that hops past makes a tally mark, made by the kid's taps; the fifth crosses the four | 1–5 one by one → counting on past five (6–10) → match a tally count to its numeral | M4 |
| Hundred Square | 5+ | Counting past 20 | A 100 square with decoys; the voice asks for a number and the grid lights the row when she's right | the first row (1–10) → the first two rows (1–20) → anywhere up to 100 | M4 |

### Appendix C: Chores & rewards by age

**Chore library (bundled, editable)**

| Ages | Chores |
|---|---|
| 2–3 | Put toys in the bin · shoes in the basket · clothes in the hamper · help feed the pet · bring your plate to the counter · wipe spills with a cloth · water a plant (with help) · put books on the shelf |
| 3–4 | Above, plus: set napkins and spoons · match socks · sort laundry by color · make bed (pull up blanket) · tidy art supplies · help unload utensils · fill the pet's water |
| 4–5 | Above, plus: set the table · clear the table · feed the pet independently · dust low surfaces · help put groceries away · get dressed alone · pack daycare bag |
| Routines (any age) | Brush teeth · potty · wash hands · pajamas · story · lights out · morning: dress, breakfast, shoes |

**Reward ideas** (parents curate; the surprise jar draws from these)

| Small | Medium | Big (family goal) |
|---|---|---|
| Extra bedtime story · pick dinner side · special cup · dance party · bubble bath · stamp on hand | Park trip · pancake breakfast · choose a movie · baking together · new book · playdate | Zoo trip · aquarium · camping in the living room · special outing with Grandma |

**Engagement mechanics by stage:** see §10.7.1. Guardrails: FR-KID-21.

### Appendix D: Weather field mapping

| Unified field | WU PWS current | WU 5-day | Open-Meteo | NWS |
|---|---|---|---|---|
| Temperature | `imperial.temp` | — | `temperature_2m` | obs `temperature` |
| Feels like | `heatIndex` / `windChill` | — | `apparent_temperature` | obs `heatIndex`/`windChill` |
| Wind / gust | `windSpeed` / `windGust`, `winddir` | `windSpeed` (daypart) | `wind_speed_10m` / `wind_gusts_10m` | obs |
| Humidity / dewpoint | `humidity` / `dewpt` | — | (optional) | obs |
| Rain so far today | `precipTotal` | — | — | — |
| Rain rate | `precipRate` | — | `precipitation` (hourly) | — |
| Rain chance | — | `precipChance` (daypart) | `precipitation_probability` (hourly), `_max` (daily) | — |
| Rain amount | — | `qpf` (daily/daypart) | `precipitation_sum` (daily) | — |
| Cloud / sun | `solarRadiation`, `uv` (now) | `cloudCover` (daypart), `uvIndex` | `cloud_cover`, **`sunshine_duration`** (hourly/daily), `uv_index` | — |
| High / low | — | `temperatureMax`/`Min` (days 1–5) | `temperature_2m_max`/`min` (days 1–10) | — |
| Narrative | — | `narrative`, daypart narratives | — | alert text |
| Sunrise / sunset | — | `sunriseTimeLocal`/`sunsetTimeLocal` | `sunrise`/`sunset`, `daylight_duration` | — |
| Moon | — | `moonPhase` | — (computed locally) | — |
| Alerts | — | — | — | `alerts/active` |

### Appendix E: Sync wire messages (WebSocket, JSON)

```jsonc
// device → hub
{"type":"hello","device":"dev7","token":"…","schema":3,"since":18234,"scopes":["household","kid_safe"]}
{"type":"push","batch":"b-91","ops":[ /* op objects, §8.4.2 */ ]}

// hub → device
{"type":"welcome","hubTime":"…","seq":18240,"snapshotRequired":false}
{"type":"ack","batch":"b-91","accepted":["op-1","op-2"],"rejected":[{"op":"op-3","reason":"acl:approval_requires_adult"}]}
{"type":"ops","from":18235,"to":18240,"ops":[ /* … */ ]}
{"type":"ephemeral","channel":"ha.state","data":{ /* entity deltas */ }}
{"type":"command","id":"c-12","cmd":"wake"}            // also: sleep, reload, screenshot, chime, announce, timer
{"type":"error","code":"upgrade_required","minSchema":4}
```

### Appendix F: Event auto-icon keywords (sample)

| Keywords | Icon | Keywords | Icon |
|---|---|---|---|
| swim, pool | 🏊 | dentist, teeth | 🦷 |
| soccer | ⚽ | doctor, checkup, pediatrician | 🩺 |
| birthday, bday, party | 🎂 | daycare, school, preschool | 🏫 |
| dance, ballet | 🩰 | library, story time | 📚 |
| park, playground | 🛝 | zoo | 🦁 |
| grandma, grandpa, nana, papa | 👵 | flight, airport, trip | ✈️ |
| haircut | 💇 | vet | 🐾 |
| dinner, lunch, brunch | 🍽️ | church, temple | ⛪ |
| music, piano, lesson | 🎹 | bath | 🛁 |

The bundled map holds ~300 keywords (English first). User overrides are
learned per title (FR-CAL-15).

### Appendix G: Glossary

| Term | Meaning |
|---|---|
| **Hub** | The Dearth server (Docker) that syncs devices and runs integrations |
| **Device role** | A per-device profile (kitchen, kid room, entry, personal) defining nav, home and scopes |
| **Tier (T1–T3)** | Performance class that sets the effects budget |
| **Display class** | Layout class by logical size (Wall-L, Wall-P, Tablet, Phone) |
| **Op / HLC / LWW** | Sync operation / Hybrid Logical Clock / last-writer-wins (field level) |
| **Scope** | A slice of household data a device is allowed to receive |
| **Grown-up mode** | PIN-unlocked adult mode on shared displays |
| **Toddler lock** | Pins a display to one kid surface |
| **Kid stage** | Little (2–3), Preschool (3–4), Pre-K (4–5): tunes kid UI and rewards |
| **Buddy** | A child's chosen character, used in celebrations and guidance |
| **Planning period** | Date range of meals whose ingredients form one shopping list |
| **Perf gate** | On-device automated performance test that blocks releases |
