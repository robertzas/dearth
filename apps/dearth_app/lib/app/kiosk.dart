import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/data/household.dart';
import '../core/format.dart';
import '../core/platform/platform.dart';
import '../core/providers.dart';
import 'display_state.dart';
import 'grown_up.dart';

/// How far controls keep from the bottom-right corner of the screen. Kiosk
/// frames reach FreeKiosk's settings through a "magic corner" there
/// (`tool/deploy_frame.sh`): an invisible 48 dp button, 8 dp from the edges,
/// that takes every tap on it. Bottom-right is the corner Dearth leaves free:
/// the others hold this clock, navigation and header actions.
const double kKioskCornerClearance = 64;

/// The rail clock. Holding it for 3 s starts the kiosk exit path (SPEC §9.3,
/// PROGRESS decision 2026-10-02): hold → grown-up PIN → kiosk menu. A tap
/// does nothing, so small hands can't open it.
class KioskClockTarget extends ConsumerWidget {
  const KioskClockTarget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final h24 = ref.watch(clock24Provider);
    final time = ref.watch(householdTimeProvider);
    ref.watch(minuteProvider);
    final wall = time.wall(time.nowMs());
    return DHoldToActivate(
      id: 'kiosk.clock',
      semanticLabel: 'Clock. Hold for the kiosk menu',
      onActivated: () => openKioskMenu(context, ref),
      child: RepaintBoundary(
        child: Padding(
          padding: EdgeInsets.all(t.space.xs),
          child: Column(
            children: [
              Text(formatClock(wall, h24: h24), style: t.text.title.copyWith(fontWeight: FontWeight.w800, fontSize: 24 * t.scale)),
              if (!h24) Text(formatMeridiem(wall), style: t.text.caption.copyWith(fontSize: 12 * t.scale, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> openKioskMenu(BuildContext context, WidgetRef ref) async {
  if (!await ensureGrownUp(context, ref, reason: 'Kiosk menu')) return;
  if (!context.mounted) return;
  await showDSheet<void>(
    context,
    title: 'Kiosk',
    id: 'kiosk.sheet',
    builder: (sheet) {
      final t = DTheme.of(sheet);
      void close() => Navigator.of(sheet).pop();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DListRow(
            id: 'kiosk.awake',
            title: 'Keep awake for an hour',
            subtitle: 'No photo frame or night mode until then',
            leading: Icon(Icons.light_mode_rounded, color: t.colors.accent),
            onTap: () {
              ref.read(displayProvider.notifier).keepAwakeFor(const Duration(hours: 1));
              close();
            },
          ),
          DListRow(
            id: 'kiosk.frame',
            title: 'Start the photo frame',
            leading: Icon(Icons.photo_rounded, color: t.colors.accent),
            onTap: () {
              close();
              ref.read(displayProvider.notifier).startScreensaver();
            },
          ),
          DListRow(
            id: 'kiosk.reload',
            title: 'Reload',
            subtitle: 'Reconnect and return to Home',
            leading: Icon(Icons.refresh_rounded, color: t.colors.accent),
            onTap: () {
              close();
              ref.read(syncClientProvider)?.nudge();
              context.go('/');
              reloadApp();
            },
          ),
          DListRow(
            id: 'kiosk.settings',
            title: 'Device settings',
            leading: Icon(Icons.tune_rounded, color: t.colors.accent),
            chevron: true,
            onTap: () {
              close();
              context.go('/settings/device');
            },
          ),
          DListRow(
            id: 'kiosk.lock',
            title: 'Lock grown-up mode',
            leading: Icon(Icons.lock_rounded, color: t.colors.accent),
            onTap: () {
              ref.read(grownUpProvider.notifier).lock();
              close();
            },
          ),
        ],
      );
    },
  );
}
