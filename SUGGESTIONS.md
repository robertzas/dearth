# SUGGESTIONS

What's still open from the full-tree review of 2026-10-11, cleaned up on
2026-10-14: everything fixed or found not accurate is gone (what was done,
and why the rest was dropped, is in the git log around 2026-10-11; the
durable findings live in `AGENTS.md`). 🔴 high · 🟡 medium · ⚪ low.

## Performance

1. 🟡 **Interval rules iterate from DTSTART on every expansion** —
   `packages/dearth_core/lib/src/calendar/recurrence.dart`. The rrule
   package's fast-forward only applies to `interval == 1 && count == null &&
   frequency ≤ daily`, so a biweekly event walks years of occurrences per
   expansion, on the UI isolate (the shared rule cache from 2026-10-11 saves
   parsing, not this). **Fix:** for interval rules, seed iteration near the
   window by stepping whole periods; memoize per (row version, window).

2. ⚪ **Countdowns expand recurrence over a 400-day horizon** —
   `apps/dearth_app/lib/core/data/calendar.dart` (`today.addDays(400)`), and
   keep only the first in-window occurrence; Home's notes card depends on it.
   Data-change-only cost. **Fix:** expand lazily per master until the first
   occurrence, or memoize per (event id, horizon).

3. 🟡 **Recipe cards fill with a corner-to-corner gradient each**
   (`apps/dearth_app/lib/shared/recipe_visual.dart`) — the slow
   kind of fill on the frame (AGENTS → Performance: ~73 ms/frame full
   screen), paid on every frame while Meals scrolls. Found 2026-10-14,
   not changed. **Fix:** flat fill, or paint once through `DStillPaint`.

## Hub

4. 🟡 **WebSocket fan-out has no backpressure** —
   `hub/dearth_hub/lib/src/connections.dart`: `DeviceSession.send` is
   fire-and-forget and a catching-up session's `_buffer` grows without bound.
   (Oversize pushes are refused now, and the 25 s ping closes dead sockets.)
   **Fix:** bound per-session buffered bytes and close on overflow; the
   device re-bootstraps.

## Structure (maintenance, your call)

5. ⚪ **`admin_routes.dart` (601 LOC) mixes pairing/devices, updates,
   backup, secrets, ICS and photo-source checks, both OAuth flows and
   webhooks.** Split into device/oauth/photo/update route files behind one
   `requireAdmin` wrapper.

6. ⚪ **`kids_section.dart` (853 LOC) holds four inline sheet editors.** Move
   them beside `kids_ops.dart`, as calendar's `event_ops.dart` does.

## UI

7. ⚪ **With the frame's keyboard up, the shell's rail is short enough
   that the Toys label touches the Timers icon.** Found 2026-10-15, not
   changed.

## CI

8. ⚪ **Old releases pile up** (a release per push is by design: it feeds
   the frame's updates). A retention step pruning releases older than N
   weeks would keep the page usable.

## Testing

9. 🟡 **TimeGrid, MonthView and AgendaView have no widget tests** — lane
   partitioning (`peopleColumns`), drag/resize math, day rollover on drop,
   and month/agenda windowing are the riskiest UI with no direct tests.

10. ⚪ **`dearth_ui` widget tests**: the toast queue, PIN-pad lockout,
    segmented and stepper controls.

11. 🟡 **E2E journeys for surfaces without one**: photo management
    (FR-PHO-01..09: favorite, hide, sources), notes, rewards and the reward
    jar, shopping list consolidation. All reachable in demo mode; one
    happy-path journey each to start. (Weather and the screensaver have
    theirs.)

## Decided against (so they aren't suggested again)

- Purging tombstones: devices keep theirs, and a long-offline outbox could
  bring a purged row back.
- Switching `DPressable` press feedback off inside scrollables: the press
  timeout already spares flings.
- CI `concurrency:` instead of the supersede job: the owner chose the job
  (2026-10-05).
