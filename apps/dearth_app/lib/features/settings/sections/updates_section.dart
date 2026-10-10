import 'dart:async';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/grown_up.dart';
import '../../../core/data/household.dart';
import '../../../core/format.dart';
import '../../../core/providers.dart';
import '../../../core/session.dart';
import '../../../core/sync/hub_api.dart';
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
    final hub = ref.watch(sessionProvider.select(showsHubUpdates));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hub) const _HubUpdatesGroup(),
        if (u.phase != UpdatePhase.unsupported)
          SettingsGroup(
            title: 'This app',
            footer: u.current == null
                ? 'This is a development build, so it never updates by itself. Installing a release replaces it.'
                : 'New versions come from github.com/robertzas/dearth.',
            children: [
              DListRow(
                id: 'updates.status',
                title: 'Version ${env.appVersion}',
                subtitle: status,
                onTap: busy ? null : () => unawaited(ref.read(appUpdaterProvider.notifier).check()),
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

/// Whether Settings → Updates shows the Hub's updates: on a device joined
/// to a separate Hub as an admin (the Hub built into the app updates with
/// the app).
bool showsHubUpdates(Session s) => s.isHub && !s.isSolo && s.admin;

/// The Hub's version and its updates (FR-ADM-04, SPEC §15.3): what's
/// newer, Install (a grown-up), and when it installs by itself. It asks the
/// Hub every 10 s while it's on screen, so an install shows through to the
/// Hub coming back on the new version.
class _HubUpdatesGroup extends ConsumerStatefulWidget {
  const _HubUpdatesGroup();

  @override
  ConsumerState<_HubUpdatesGroup> createState() => _HubUpdatesGroupState();
}

class _HubUpdatesGroupState extends ConsumerState<_HubUpdatesGroup> {
  Map<String, Object?>? _status;
  String? _error;
  bool _busy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    unawaited(_call('/api/admin/update/check'));
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => unawaited(_call('/api/admin/update')));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _call(String path, {bool post = false}) async {
    final api = ref.read(hubApiProvider);
    if (api == null) return;
    try {
      final s = path.endsWith('/update') && !post ? await api.get(path) : await api.post(path, const {});
      if (mounted) {
        setState(() {
          _status = s;
          _error = null;
        });
      }
    } on HubApiException catch (e) {
      // While it installs, the Hub is away for a moment: keep what it said.
      if (mounted && _status?['installing'] != true) setState(() => _error = e.friendly);
    }
  }

  Future<void> _install(String latest) async {
    if (!await ensureGrownUp(context, ref, reason: 'Updating the Hub needs a grown-up')) return;
    if (!mounted) return;
    final ok = await confirmDialog(
      context,
      title: 'Update the Hub to $latest?',
      message: 'The Hub restarts on the new version. Displays reconnect by themselves within a minute.',
      confirmLabel: 'Update',
    );
    if (!ok) return;
    setState(() => _busy = true);
    await _call('/api/admin/update/install', post: true);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _setMode(String mode) async {
    if (!await ensureGrownUp(context, ref, reason: 'Changing how the Hub updates needs a grown-up')) return;
    final writer = ref.read(writerProvider);
    await writer.commit([settingOp(writer, SettingKeys.hubUpdates, {'mode': mode})]);
    await _call('/api/admin/update');
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final s = _status;
    final time = ref.watch(householdTimeProvider);
    final h24 = ref.watch(clock24Provider);
    final version = s?['version'] as String?;
    final latest = s?['latest'] as String?;
    final available = s?['available'] == true;
    final installing = s?['installing'] == true;
    final canInstall = s?['canInstall'] == true;
    final checkedMs = (s?['checkedAtMs'] as num?)?.toInt();
    final checked = checkedMs == null ? null : 'checked at ${formatTime(time.wall(checkedMs), h24: h24)}';
    final mode = ref.watch(settingMapProvider(SettingKeys.hubUpdates))['mode'] as String? ?? HubUpdateMode.manual;
    final status = switch (s) {
      null => _error ?? 'Asking the Hub…',
      _ when installing => 'Updating to $latest. The Hub is back in a minute.',
      _ when available => 'Dearth Hub $latest is available${checked == null ? '' : ' · $checked'}',
      _ when latest == null => checked == null ? 'Not checked yet' : 'Couldn’t tell what’s newest',
      _ => 'Up to date${checked == null ? '' : ' · $checked'}',
    };
    final error = s?['error'] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'The Hub',
          footer: s == null || canInstall
              ? 'The Hub looks for new versions every hour.'
              : 'This Hub can’t update itself: it needs the updater from the latest compose.yml (README → Updating the Hub).',
          children: [
            DListRow(
              id: 'updates.hub.status',
              title: version == null ? 'Dearth Hub' : 'Dearth Hub $version',
              subtitle: status,
              onTap: installing ? null : () => unawaited(_call('/api/admin/update/check')),
              leading: Icon(available ? Icons.system_update_rounded : Icons.dns_rounded, color: available ? t.colors.accent : t.colors.inkSecondary),
            ),
            if (error != null)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.xs),
                child: tid('updates.hub.error', Text(error, style: t.text.caption.copyWith(color: t.colors.warning))),
              ),
            if (s != null)
              Padding(
                padding: EdgeInsets.all(t.space.md),
                child: Wrap(
                  spacing: t.space.sm,
                  runSpacing: t.space.sm,
                  children: [
                    if (available && canInstall && latest != null)
                      DButton(id: 'updates.hub.install', label: 'Update the Hub to $latest', icon: Icons.download_rounded, busy: _busy || installing, onPressed: () => unawaited(_install(latest))),
                    DButton(
                      id: 'updates.hub.check',
                      label: 'Check now',
                      tone: available ? DButtonTone.tonal : DButtonTone.primary,
                      onPressed: installing ? null : () => unawaited(_call('/api/admin/update/check')),
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (canInstall)
          SettingsGroup(
            title: 'The Hub installs updates',
            footer: 'Nightly updates between 3 and 5 am. A display shows "Reconnecting" for a moment while the Hub restarts.',
            children: [
              ChoiceRow<String>(
                title: 'Install Hub updates',
                idPrefix: 'updates.hub.mode',
                options: const [(HubUpdateMode.manual, 'When I tap'), (HubUpdateMode.nightly, 'Nightly'), (HubUpdateMode.auto, 'Right away')],
                value: mode,
                onChanged: (v) => unawaited(_setMode(v)),
              ),
            ],
          ),
      ],
    );
  }
}
