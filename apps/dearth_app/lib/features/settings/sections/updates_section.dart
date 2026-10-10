import 'dart:async';

import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/grown_up.dart';
import '../../../core/data/household.dart';
import '../../../core/format.dart';
import '../../../core/providers.dart';
import '../../../core/update/updater.dart';
import '../settings_screen.dart';

/// App updates from GitHub releases (SPEC FR-ADM-04, §15.3): what's
/// installed, what's newer, Install (a grown-up), and on a display that can
/// install silently, whether it updates by itself.
class UpdatesSection extends ConsumerStatefulWidget {
  const UpdatesSection({super.key});

  @override
  ConsumerState<UpdatesSection> createState() => _UpdatesSectionState();
}

class _UpdatesSectionState extends ConsumerState<UpdatesSection> {
  @override
  void initState() {
    super.initState();
    // Opening the page looks again, unless it looked a moment ago.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = ref.read(appUpdaterProvider);
      final now = ref.read(appClockProvider).nowMs();
      if (s.phase != UpdatePhase.unsupported && (s.checkedAtMs == null || now - s.checkedAtMs! > 10 * 60 * 1000)) unawaited(ref.read(appUpdaterProvider.notifier).check());
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final u = ref.watch(appUpdaterProvider);
    final env = ref.watch(envProvider);
    final device = ref.watch(deviceSettingsProvider);
    final time = ref.watch(householdTimeProvider);
    final h24 = ref.watch(clock24Provider);
    final latest = u.latest;
    final checked = u.checkedAtMs == null ? null : 'checked at ${formatTime(time.wall(u.checkedAtMs!), h24: h24)}';

    final status = switch (u.phase) {
      UpdatePhase.unsupported => 'This device gets new versions where it was installed from',
      UpdatePhase.idle => 'Not checked yet',
      UpdatePhase.checking => 'Checking…',
      UpdatePhase.upToDate => 'Up to date${checked == null ? '' : ' · $checked'}',
      UpdatePhase.available => 'Dearth ${latest?.version} is available${checked == null ? '' : ' · $checked'}',
      UpdatePhase.downloading => 'Downloading ${latest?.version}… ${((u.progress ?? 0) * 100).round()} %',
      UpdatePhase.ready => '${latest?.version} is downloaded and ready',
      UpdatePhase.installing => 'Installing ${latest?.version}. Dearth restarts by itself in a minute.',
    };

    Future<void> install() async {
      if (!await ensureGrownUp(context, ref, reason: 'Installing an update needs a grown-up')) return;
      if (!context.mounted) return;
      if (u.silent) {
        final ok = await confirmDialog(
          context,
          title: 'Install Dearth ${latest?.version}?',
          message: 'Dearth closes for about a minute while it updates, then comes back on its own.',
          confirmLabel: 'Install',
        );
        if (!ok) return;
      }
      await ref.read(appUpdaterProvider.notifier).install();
    }

    Future<void> setMode(String mode) async {
      if (!await ensureGrownUp(context, ref, reason: 'Changing how updates install needs a grown-up')) return;
      await updateDeviceSettings(ref.read(writerProvider), deviceId: ref.read(sessionProvider).effectiveDeviceId, current: device, patch: {'updates': mode});
    }

    final busy = u.phase == UpdatePhase.checking || u.phase == UpdatePhase.downloading || u.phase == UpdatePhase.installing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'This app',
          footer: u.current == null && u.phase != UpdatePhase.unsupported
              ? 'This is a development build, so it never updates by itself. Installing a release replaces it.'
              : 'New versions come from github.com/robertzas/dearth.',
          children: [
            DListRow(
              id: 'updates.status',
              title: 'Version ${env.appVersion}',
              subtitle: status,
              leading: Icon(
                latest == null ? Icons.check_circle_rounded : Icons.system_update_rounded,
                color: latest == null ? t.colors.success : t.colors.accent,
              ),
            ),
            if (u.error != null)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.xs),
                child: tid('updates.error', Text(u.error!, style: t.text.caption.copyWith(color: t.colors.warning))),
              ),
            if (u.phase != UpdatePhase.unsupported)
              Padding(
                padding: EdgeInsets.all(t.space.md),
                child: Wrap(
                  spacing: t.space.sm,
                  runSpacing: t.space.sm,
                  children: [
                    if (latest != null) DButton(id: 'updates.install', label: 'Install ${latest.version}', icon: Icons.download_rounded, busy: busy, onPressed: install),
                    DButton(
                      id: 'updates.check',
                      label: 'Check now',
                      tone: latest == null ? DButtonTone.primary : DButtonTone.tonal,
                      onPressed: busy ? null : () => unawaited(ref.read(appUpdaterProvider.notifier).check()),
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (u.silent)
          SettingsGroup(
            title: 'Install by itself',
            footer: 'Never while someone is using the screen or a kitchen timer is counting down. '
                'Nightly waits for the night hours; when idle, for the photo frame or the night clock.',
            children: [
              ChoiceRow<String>(
                title: 'Install updates',
                idPrefix: 'updates.mode',
                options: const [(UpdateMode.manual, 'When I tap'), (UpdateMode.nightly, 'Nightly'), (UpdateMode.idle, 'When idle')],
                value: const {UpdateMode.nightly, UpdateMode.idle}.contains(device.updates) ? device.updates : UpdateMode.manual,
                onChanged: (v) => unawaited(setMode(v)),
              ),
            ],
          ),
      ],
    );
  }
}
