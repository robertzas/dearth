import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/household.dart';
import '../../../core/data/household_data.dart';
import '../../../core/providers.dart';
import '../google_connect.dart';
import '../settings_screen.dart';

/// Lists (SPEC FR-LIST): which ones mirror to Google Tasks. The owner chose
/// Tasks for list sync because Google Keep has no API for personal
/// accounts. The sync runs on the Hub; switching a list on needs no Google
/// sign-in on this display, allowing Tasks does (admin displays only).
class ListsSection extends ConsumerWidget {
  const ListsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final lists = [for (final l in ref.watch(listsProvider).value ?? const <DList>[]) if (!l.isTemplate) l];
    final api = ref.watch(hubApiProvider);
    final admin = ref.watch(sessionProvider).admin;
    final setting = ref.watch(settingMapProvider(SettingKeys.listsGoogleTasks));
    final synced = {for (final id in setting['lists'] is List ? setting['lists']! as List : const []) '$id'};
    final status = ref.watch(settingMapProvider('integrations.status'))['google-tasks'];
    Future<void> toggle(DList l, bool on) {
      final w = ref.read(writerProvider);
      final next = {...synced}..remove(l.id);
      if (on) next.add(l.id);
      return w.commit([settingOp(w, SettingKeys.listsGoogleTasks, {...setting, 'lists': next.toList()..sort()})]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'Google Tasks',
          footer: api == null
              ? 'List sync runs on your Dearth Hub. Connect one in Hub & devices.'
              : 'Items added, ticked off or deleted on either side show up on the other within a few minutes, in the Google Tasks app, Gmail and Google Calendar. (Google Keep has no way in for apps.)',
          children: [
            for (final l in lists)
              DSwitchRow(
                id: 'lists.gtasks.${l.id}',
                leading: DEmoji(l.icon ?? '📝', size: 28 * t.scale),
                title: l.title,
                subtitle: synced.contains(l.id) ? 'Synced with “${l.title}” in Google Tasks' : 'Only on Dearth',
                value: synced.contains(l.id),
                onChanged: api == null ? null : (v) => toggle(l, v),
              ),
            if (status is Map && synced.isNotEmpty)
              DListRow(
                id: 'lists.gtasks.status',
                title: status['ok'] == true ? 'Synced' : 'Needs attention',
                subtitle: status['message'] as String?,
                leading: DEmoji(status['ok'] == true ? '✅' : '⚠️', size: 28 * t.scale),
              ),
            DListRow(
              id: 'lists.gtasks.allow',
              title: 'Allow Google Tasks',
              subtitle: admin ? 'Sign in to Google again and allow Tasks' : 'From the Hub’s admin display',
              leading: DEmoji('🔑', size: 28 * t.scale),
              chevron: true,
              onTap: api == null || !admin ? null : () => connectGoogle(context, ref, api, purpose: 'tasks'),
            ),
          ],
        ),
      ],
    );
  }
}
