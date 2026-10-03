<p align="center"><img src="tool/icons/dearth_icon.svg" width="96" height="96" alt=""></p>

<h1 align="center">Dearth</h1>

<p align="center">
A family command center for wall-mounted touchscreens.<br>
Self-hosted, private, and fast on inexpensive hardware.
</p>

<p align="center">
<a href="https://github.com/robertzas/dearth/actions/workflows/build.yml"><img src="https://github.com/robertzas/dearth/actions/workflows/build.yml/badge.svg?branch=main" alt="Build &amp; release"></a>
<a href="https://github.com/robertzas/dearth/releases/latest"><img src="https://img.shields.io/github/v/release/robertzas/dearth?label=release" alt="Latest release"></a>
<a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-blue" alt="AGPL-3.0"></a>
</p>

![Home on a 27-inch landscape wall display](docs/images/home-wall-l.png)

Dearth puts the household calendar, the weather, lists, dinner, chores and a
photo frame on one screen in the kitchen. Every other screen in the house
stays in sync with it: portrait hallway displays, tablets, phones, desktops
and the browser.

Everything runs on your own network. A small server, the **Hub**, keeps the
data, syncs the devices and talks to outside services. The displays keep
working when the Hub or the internet is down, and catch up when they come
back.

## What it does today

- **Home.** Clock, date, weather and alerts, today's agenda with a live
  "now" line, what's next (with conflicts), the week ahead, notes and
  countdowns, dinner, kids' chores and the shopping list. It lays itself
  out for each display.
- **Calendar.** Day, 3-day, week, month and agenda views, with filters for
  each person. A full editor handles recurring events ("this one",
  "this and following" or "all"). Quick add understands plain language:
  *"Swim Saturday 9am Ava"*. It adds automatic event emoji and learns from
  your edits. It subscribes to ICS calendars and connects to Google
  Calendar.
- **Meals.** A week planner of days and meal slots, holding recipes or a
  free-text entry like "Leftovers". Recipes scale with the servings
  stepper, using friendly fractions, and switch between US and metric
  units. Discover suggests recipes that pair with the week's plan and says
  why ("Uses your cilantro and limes · adds 2 items"). Each person rates a
  recipe with a face, kids included. A tap adds a recipe's ingredients, or
  the whole week's, to the shopping list, with staples skipped and amounts
  merged. Cook mode shows one step at a time with tap-to-start timers.
- **Weather.** The current conditions and a 36-hour chart with rain, sun
  and UV bands. It also shows a rain summary, a 10-day forecast, sunrise,
  sunset and the moon, what to wear, and alerts. Sources are Open-Meteo,
  NWS and Weather Underground, merged.
- **Lists.** Shared shopping and to-do lists, grouped by aisle, with undo.
- **Photo frame.** A screensaver with crossfades, paired portrait photos
  and a built-in painted art pack, plus a night clock. Photos come from
  folders on the Hub or Amazon Photos shared albums.
- **Grown-up mode.** Kid-safe by default. A PIN unlocks anything
  destructive and locks again on its own. On kiosk displays, holding the
  clock opens the kiosk menu.
- **Every screen size.** A 27″ wall display (landscape or portrait),
  tablets, phones, Linux, Windows and macOS desktops, and the web.

<table>
<tr>
<td width="50%"><img src="docs/images/calendar-wall-l.png" alt="Week view"></td>
<td width="50%"><img src="docs/images/weather-wall-l.png" alt="Weather"></td>
</tr>
<tr>
<td><img src="docs/images/meals-wall-l.png" alt="Meal planner"></td>
<td><img src="docs/images/discover-wall-l.png" alt="Recipe discovery"></td>
</tr>
<tr>
<td><img src="docs/images/home-tablet.png" alt="Home on a tablet"></td>
<td><img src="docs/images/photos-wall-l.png" alt="Photo frame curation"></td>
</tr>
</table>

<p align="center">
<img src="docs/images/home-wall-p.png" height="420" alt="Portrait wall display">
&nbsp;
<img src="docs/images/home-phone.png" height="420" alt="Phone: Today">
&nbsp;
<img src="docs/images/calendar-phone.png" height="420" alt="Phone: calendar">
</p>

Still to come: the kids' chart, chores and rewards, a music box,
reminders, and meal-plan templates. Integration with the FreeKiosk
Android frame is coming too. [`PROGRESS.md`](PROGRESS.md) tracks the
build, and [`SPEC.md`](SPEC.md) is the full product specification.

## Try it

### The demo (no server needed)

Every build has **Explore the demo** on its welcome screen. It sets up a
sample household on that device alone. Download a build from the
[latest release](https://github.com/robertzas/dearth/releases/latest):

| Platform | File |
|---|---|
| Android tablets and phones | `dearth-…-android-arm64-v8a.apk` |
| 32-bit Android frames | `dearth-…-android-armeabi-v7a.apk` |
| Linux | `dearth-…-linux-x64.tar.gz` (run `./dearth`) |
| Windows | `dearth-…-windows-x64.zip` (run `dearth.exe`) |
| macOS | `dearth-…-macos.zip` (unsigned: right-click → **Open** the first time) |
| Web | `dearth-…-web.zip`. Serve the folder with any static server, e.g. `python3 -m http.server`, and open `/?demo=1`. |

### The Hub (Docker)

```bash
mkdir dearth && cd dearth
curl -fsSLO https://raw.githubusercontent.com/robertzas/dearth/main/compose.yml
curl -fsSL -o .env https://raw.githubusercontent.com/robertzas/dearth/main/.env.example
$EDITOR .env                          # public URL, admin password, time zone, folders
openssl rand -hex 32 > dearth_key     # encrypts stored integration secrets: back it up
docker compose up -d
```

Open `http://<hub>:8080`. The Hub serves the web app itself, and phones
can add it to their home screen. Each display pairs once:

1. Choose **Connect to a Hub** and enter the Hub's address.
2. Name the display and pick its role: kitchen, kid's room, entry or
   personal.
3. Approve the code it shows. Use another paired device (**Settings → Hub
   & devices**), the admin password, or `docker compose exec dearth
   /app/bin/dearth_hub approve <CODE>`.

To skip step 3, create a one-time enrollment code in **Settings → Hub &
devices → Add a display with a code**, or run `/app/bin/dearth_hub enroll`
in the container.

<details>
<summary>Hub without Docker</summary>

The `dearth-hub-…-<os>-<arch>` archives in each release contain the Hub
binary and the web app:

```bash
tar -xzf dearth-hub-…-linux-x64.tar.gz -C /opt/dearth
DEARTH_DATA_DIR=/var/lib/dearth DEARTH_ADMIN_PASSWORD=… /opt/dearth/bin/dearth_hub serve
```

</details>

### Hub configuration

| Variable | Default | Purpose |
|---|---|---|
| `DEARTH_PUBLIC_URL` | (none) | The Hub's public HTTPS origin behind a reverse proxy or tunnel. Needed for Google sign-in callbacks and calendar push updates. |
| `DEARTH_LAN_URLS` | (none) | Extra origins allowed to call the API, e.g. `http://10.0.1.20:8080`. |
| `DEARTH_ADMIN_PASSWORD` | generated | If unset, a password is generated and printed once in the log. `dearth_hub reset-admin` prints a new one. |
| `TZ` | `UTC` | The household time zone on first start. You can change it later in the app. |
| `DEARTH_PHOTO_DIRS`, `DEARTH_MUSIC_DIRS` | (none) | Folders the Hub may read. Compose mounts `DEARTH_PHOTO_FOLDER` and `DEARTH_MUSIC_FOLDER` there read-only. |
| `DEARTH_SECRET_KEY_FILE` | `<data>/secret.key` | The key that encrypts integration secrets. |
| `DEARTH_DATA_DIR` | `./data` (`/data` in Docker) | The database and blobs. |
| `DEARTH_PORT`, `DEARTH_HOST` | `8080`, `0.0.0.0` | Where the Hub listens. |
| `DEARTH_CONTACT` | `dearth-hub` | The contact sent in the NWS User-Agent (their API asks for one). |
| `DEARTH_LOG_LEVEL` | `info` | `fine`, `info`, `warning` or `severe`. |

## Development

You need **Flutter 3.47.2** (Dart 3.13), **Git LFS**, and Node.js 20+ with
Chrome for the end-to-end suite. Docker and the Android SDK are optional.

```bash
git lfs install && git clone https://github.com/robertzas/dearth && cd dearth
tool/check.sh                                  # pub get, codegen, analyze, every unit test
tool/dev_hub.sh                                # a local Hub with demo data
cd apps/dearth_app && flutter run -d chrome    # or -d linux, or an Android device
```

| Task | Command |
|---|---|
| Quality gate (must stay green) | `tool/check.sh` (`--fast` skips codegen) |
| Regenerate drift code after editing `tables.dart` | `tool/codegen.sh` |
| Web E2E: Playwright at 4 viewports against a test Hub | `tool/e2e.sh` (`SKIP_BUILD=1` reuses the web build) |
| Build every target this machine can | `tool/build_all.sh` (`--hub-image` also builds the Docker image) |
| Web database runtime (sqlite3.wasm, drift worker) | `tool/web_assets.sh` |
| App icons from the SVG source | `tool/icons/make_icons.sh` |

Every push to `main` runs the gate and the E2E suite and builds every
platform: Android, web, Linux, Windows, macOS, iOS, Hub binaries and a
multi-arch Hub image on GHCR. It then publishes a release
`v<version>-build.<n>` ([workflow](.github/workflows/build.yml)).

Read [`AGENTS.md`](AGENTS.md) before changing code. It covers the layout
and the rules that keep the codebase coherent.

### Architecture

```
            ┌──────────── Hub (Dart, Docker) ────────────┐
            │ sync authority · pairing · blobs · jobs    │
 Google ────┤ integrations: weather, calendars, photos   │
 Open-Meteo─┤ admin API · serves the web app             │
            └───────▲───────────────▲───────────────▲────┘
       WebSocket ops│               │               │
            ┌───────┴──────┐ ┌──────┴─────┐ ┌───────┴──────┐
            │ wall display │ │   tablet   │ │ phone / web  │
            │  (Android)   │ │            │ │              │
            │ SQLite + ops │ │SQLite + ops│ │ SQLite (wasm)│
            └──────────────┘ └────────────┘ └──────────────┘
```

Each device keeps the whole household in a local SQLite database, so
screens render from local data and keep working offline. Writes become
field-level operations stamped with a hybrid logical clock. The Hub orders
and relays them, and conflicts resolve as last-writer-wins per field
(SPEC §8).

| Package | Role |
|---|---|
| `packages/dearth_core` | Pure Dart: schema, sync engine, calendar, recipes, kids, weather and solar logic |
| `packages/dearth_integrations` | Provider adapters (weather, Google, ICS, photos, recipes, music) tested against fixtures |
| `packages/dearth_ui` | The design system: tokens, themes, display classes, scaling, components and charts |
| `hub/dearth_hub` | The Hub server |
| `apps/dearth_app` | The Flutter app for every platform |
| `e2e/` | The Playwright suite |

## License

[GNU AGPL-3.0](LICENSE). If you run a modified Hub for others, share the
changes.
