import 'dart:async';

import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/grown_up.dart';
import '../../../app/shell.dart' show syncLabel;
import '../../../core/providers.dart';
import '../../../core/solo/built_in_hub.dart';
import '../../../core/sync/hub_api.dart';
import '../settings_screen.dart';
import 'hub_move.dart';

/// Hub connection, pairing approvals and devices (SPEC §9.2, FR-ADM-01).
class HubSection extends ConsumerStatefulWidget {
  const HubSection({super.key});

  @override
  ConsumerState<HubSection> createState() => _HubSectionState();
}

class _HubSectionState extends ConsumerState<HubSection> {
  Map<String, Object?>? _status;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(hubApiProvider);
    if (api == null || !ref.read(sessionProvider).admin) return;
    try {
      final s = await api.get('/api/admin/status');
      if (mounted) setState(() => _status = s);
    } on HubApiException catch (e) {
      if (mounted) setState(() => _error = e.friendly);
    }
  }

  Future<void> _approve(HubApi api, String code) async {
    try {
      await api.post('/api/admin/pair/approve', {'code': code});
      ref.read(toastProvider).show('Approved', emoji: '✅');
      await _load();
    } on HubApiException catch (e) {
      ref.read(toastProvider).show(e.friendly, emoji: '⚠️');
    }
  }

  Future<void> _enroll(HubApi api) async {
    try {
      final r = await api.post('/api/admin/enroll', {'name': 'New display', 'role': 'kitchen'});
      if (!mounted) return;
      await showDSheet<void>(
        context,
        title: 'Enrollment code',
        builder: (sheet) {
          final t = DTheme.of(sheet);
          return Column(
            children: [
              Text('Enter this code on the new display (valid for 30 minutes):', style: t.text.body),
              SizedBox(height: t.space.lg),
              tid('hub.enroll.code', Text('${r['code']}', style: t.text.display.copyWith(letterSpacing: 6 * t.scale))),
              SizedBox(height: t.space.lg),
            ],
          );
        },
      );
    } on HubApiException catch (e) {
      ref.read(toastProvider).show(e.friendly, emoji: '⚠️');
    }
  }

  Future<void> _leave() async {
    if (!await ensureGrownUp(context, ref, reason: 'Disconnecting needs a grown-up')) return;
    if (!mounted) return;
    final session = ref.read(sessionProvider);
    final demo = session.isDemo;
    final (title, message, label) = session.isToybox
        ? ('Leave Toybox mode?', 'The Toybox’s levels and played games are removed from this device. You can then connect a Hub or start again.', 'Leave Toybox mode')
        : session.isSolo
            ? (
                'Delete this household?',
                'This device holds the family’s only copy: people, calendars, lists, chores, stars and photos are deleted for good. To keep them, move to a Hub instead.',
                'Delete everything',
              )
            : demo
            ? ('Leave the demo?', 'The demo family is removed from this device.', 'Leave demo')
            : ('Disconnect this display?', 'This device forgets the Hub and its local copy. The family’s data stays on the Hub.', 'Disconnect');
    final ok = await confirmDialog(context, title: title, message: message, confirmLabel: label, danger: !demo);
    if (ok) await ref.read(sessionProvider.notifier).reset();
  }

  Future<void> _switch(Future<void> Function(BuildContext) sheet) async {
    if (!await ensureGrownUp(context, ref, reason: 'Moving the household needs a grown-up')) return;
    if (mounted) await sheet(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final session = ref.watch(sessionProvider);
    final sync = ref.watch(syncStateProvider).value;
    final pending = ref.watch(outboxCountProvider).value ?? 0;
    final api = ref.watch(hubApiProvider);
    final hub = _status?['hub'] as Map<String, Object?>?;
    final devices = [for (final d in (_status?['devices'] as List? ?? const [])) if (d is Map<String, Object?>) d];
    final pairings = [for (final p in (_status?['pendingPairings'] as List? ?? const [])) if (p is Map<String, Object?>) p];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'Connection',
          children: [
            if (session.isDemo)
              const DListRow(title: 'Demo mode', subtitle: 'A sample family that lives only on this device', leading: DEmoji('🧪', size: 30))
            else if (session.isToybox)
              const DListRow(id: 'hub.toybox', title: 'Toybox only', subtitle: 'Just the games, for one child, on this device. Nothing leaves it.', leading: DEmoji('🧸', size: 30))
            else if (session.isSolo) ...[
              DListRow(
                id: 'hub.solo',
                title: 'On its own',
                subtitle: 'Its own Hub, inside the app: the family’s data lives on this device${sync == null || sync.isHealthy ? '' : ' · ${syncLabel(sync, t.colors).$1}'}',
                leading: const DEmoji('📟', size: 30),
              ),
              if (hub != null) DListRow(title: 'Built-in Hub', subtitle: '${hub['version']} · ${hub['seq']} changes · ${_size(hub['dbBytes'])}'),
              DListRow(
                id: 'hub.move',
                title: 'Move to a Hub',
                subtitle: 'Set up a Hub at home, then bring everything here over to it',
                leading: Icon(Icons.drive_file_move_rounded, color: t.colors.accent),
                onTap: () => _switch(showMoveToHubSheet),
              ),
            ] else ...[
              DListRow(
                id: 'hub.status',
                title: session.hubUrl ?? 'Hub',
                subtitle: sync == null ? '' : '${syncLabel(sync, t.colors).$1}${pending > 0 ? ' · $pending changes waiting' : ''}${sync.error == null ? '' : ' · ${sync.error}'}',
                leading: Icon(Icons.hub_rounded, color: sync?.isHealthy ?? false ? t.colors.success : t.colors.warning),
              ),
              DListRow(title: 'This device', subtitle: '${session.deviceName ?? 'Display'} · ${session.role}${session.admin ? ' · admin' : ''}'),
              if (hub != null) DListRow(title: 'Hub version', subtitle: '${hub['version']} · ${hub['seq']} changes · ${hub['fakeProviders'] == true ? 'demo providers' : 'live providers'}'),
              if (BuiltInHub.supported)
                DListRow(
                  id: 'hub.solo.start',
                  title: 'Run this device on its own',
                  subtitle: 'Take a copy of the family’s data and stop syncing with this Hub',
                  leading: Icon(Icons.offline_bolt_rounded, color: t.colors.accent),
                  onTap: () => _switch(showRunOnItsOwnSheet),
                ),
            ],
            DListRow(
              id: 'hub.leave',
              title: session.isToybox
                  ? 'Leave Toybox mode'
                  : session.isDemo
                      ? 'Leave demo and connect a Hub'
                      : session.isSolo
                          ? 'Delete this household'
                          : 'Disconnect this display',
              leading: Icon(Icons.logout_rounded, color: t.colors.danger),
              onTap: _leave,
            ),
          ],
        ),
        // Nothing else can join the built-in Hub: it listens on this device only.
        if (api != null && session.admin && !session.isSolo) ...[
          if (pairings.isNotEmpty)
            SettingsGroup(
              title: 'Waiting to join',
              children: [
                for (final p in pairings)
                  DListRow(
                    id: 'hub.pairing.${p['code']}',
                    title: '${p['name']}',
                    subtitle: 'Code ${p['code']} · ${p['platform'] ?? 'device'}',
                    leading: const DEmoji('📲', size: 30),
                    trailing: DButton(label: 'Approve', size: DButtonSize.sm, id: 'hub.approve.${p['code']}', onPressed: () => _approve(api, '${p['code']}')),
                  ),
              ],
            ),
          SettingsGroup(
            title: 'Devices',
            footer: _error,
            children: [
              for (final d in devices)
                DListRow(
                  title: '${d['name']}',
                  subtitle: '${d['role']}${d['admin'] == true ? ' · admin' : ''} · ${d['online'] == true ? 'online' : 'offline'}',
                  leading: Icon(Icons.circle, size: 14 * t.scale, color: d['online'] == true ? t.colors.success : t.colors.inkTertiary),
                ),
              DListRow(
                id: 'hub.enroll',
                title: 'Add a display with a code',
                subtitle: 'Creates a one-time enrollment code',
                leading: Icon(Icons.add_to_queue_rounded, color: t.colors.accent),
                onTap: () => _enroll(api),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

String _size(Object? bytes) {
  final b = bytes is num ? bytes.toDouble() : 0.0;
  return b >= 1 << 20 ? '${(b / (1 << 20)).toStringAsFixed(1)} MB' : '${(b / 1024).ceil()} KB';
}
