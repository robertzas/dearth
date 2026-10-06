import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/household.dart';
import '../../../core/providers.dart';
import '../../../core/sync/hub_api.dart';
import '../../photos/photos_data.dart';
import '../settings_screen.dart';

/// Photo frame and night settings (SPEC FR-SSV-01…05, FR-DSP-01).
class ScreensaverSection extends ConsumerWidget {
  const ScreensaverSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final ss = ref.watch(settingMapProvider(SettingKeys.screensaver));
    final night = ref.watch(settingMapProvider(SettingKeys.nightSchedule));
    final w = ref.read(writerProvider);
    final sources = ref.watch(photoSourcesProvider).value ?? const <PhotoSource>[];
    final api = ref.watch(hubApiProvider);
    final admin = ref.watch(sessionProvider.select((s) => s.admin));
    Future<void> setSs(Map<String, Object?> patch) => w.commit([settingOp(w, SettingKeys.screensaver, {...ss, ...patch})]);
    Future<void> setNight(Map<String, Object?> patch) => w.commit([settingOp(w, SettingKeys.nightSchedule, {...night, ...patch})]);
    bool flag(String k) => ss[k] as bool? ?? true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'Photo frame',
          children: [
            ChoiceRow<int>(
              title: 'Start after',
              idPrefix: 'ss.idle',
              options: const [(2, '2 min'), (5, '5 min'), (10, '10 min'), (30, '30 min')],
              value: (ss['idleMinutes'] as num?)?.toInt() ?? 5,
              onChanged: (v) => setSs({'idleMinutes': v}),
            ),
            ChoiceRow<int>(
              title: 'Each photo',
              idPrefix: 'ss.seconds',
              options: const [(10, '10 s'), (30, '30 s'), (60, '1 min'), (120, '2 min')],
              value: (ss['photoSeconds'] as num?)?.toInt() ?? 30,
              onChanged: (v) => setSs({'photoSeconds': v}),
            ),
            DSwitchRow(id: 'ss.clock', title: 'Clock and date', value: flag('clock'), onChanged: (v) => setSs({'clock': v})),
            DSwitchRow(id: 'ss.weather', title: 'Current weather', value: flag('weather'), onChanged: (v) => setSs({'weather': v})),
            DSwitchRow(id: 'ss.next', title: 'Next event', value: flag('nextEvent'), onChanged: (v) => setSs({'nextEvent': v})),
            DSwitchRow(id: 'ss.caption', title: 'Photo captions', value: flag('caption'), onChanged: (v) => setSs({'caption': v})),
            DSwitchRow(
              id: 'ss.kenburns',
              title: 'Slow pan and zoom',
              subtitle: 'Off by default on low-power displays',
              value: ss['kenBurns'] as bool? ?? false,
              onChanged: (v) => setSs({'kenBurns': v}),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Photo sources',
          footer: api == null ? 'Photo sources run on your Hub. Demo mode shows the built-in art pack.' : null,
          children: [
            for (final s in sources)
              DListRow(
                id: 'photos.source.${s.id}',
                title: s.name,
                subtitle: '${s.itemCount} photos${s.status == null ? '' : ' · ${s.status}'}',
                leading: DEmoji(_emoji(s.kind), size: 30 * t.scale),
                trailing: Switch(value: s.enabled, onChanged: (v) => w.upsert('photo_sources', s.id, {'enabled': v})),
                onTap: api == null || !admin ? null : () => _sourceSheet(context, ref, api, s),
              ),
            DListRow(
              id: 'photos.add.amazon',
              title: 'Add an Amazon Photos shared album',
              subtitle: 'Paste a share link — no Amazon password needed',
              leading: const DEmoji('📦', size: 30),
              chevron: true,
              onTap: api == null || !admin ? null : () => _addSource(context, ref, api, 'amazon'),
            ),
            DListRow(
              id: 'photos.add.folder',
              title: 'Add a folder on the Hub',
              subtitle: 'A NAS or local folder mounted into the Hub',
              leading: const DEmoji('🗂️', size: 30),
              chevron: true,
              onTap: api == null || !admin ? null : () => _addSource(context, ref, api, 'folder'),
            ),
          ],
        ),
        SettingsGroup(
          title: 'Night',
          footer: 'During the night schedule, wall displays show a dim, warm clock.',
          children: [
            DSwitchRow(id: 'night.enabled', title: 'Night schedule', value: night['enabled'] as bool? ?? true, onChanged: (v) => setNight({'enabled': v})),
            ChoiceRow<String>(
              title: 'Starts',
              idPrefix: 'night.start',
              options: const [('20:00', '8 PM'), ('21:00', '9 PM'), ('22:00', '10 PM'), ('23:00', '11 PM')],
              value: night['start'] as String? ?? '21:00',
              onChanged: (v) => setNight({'start': v}),
            ),
            ChoiceRow<String>(
              title: 'Ends',
              idPrefix: 'night.end',
              options: const [('05:30', '5:30'), ('06:30', '6:30'), ('07:00', '7:00'), ('07:30', '7:30')],
              value: night['end'] as String? ?? '06:30',
              onChanged: (v) => setNight({'end': v}),
            ),
          ],
        ),
      ],
    );
  }

  static String _emoji(String kind) => kind == 'amazon' ? '📦' : (kind == 'folder' ? '🗂️' : '🖼️');

  /// A source's details: where its photos come from, a sync now, and
  /// removing it (with its photos) for good.
  Future<void> _sourceSheet(BuildContext context, WidgetRef ref, HubApi api, PhotoSource s) async {
    final cfg = decodeJsonMap(s.config);
    final where = (cfg['shareUrl'] ?? cfg['path'] ?? cfg['url']) as String?;
    final action = await showDSheet<String>(
      context,
      title: s.name,
      id: 'photos.source.sheet',
      builder: (sheet) {
        final t = DTheme.of(sheet);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${s.itemCount} photos${s.status == null ? '' : ' · ${s.status}'}', style: t.text.body),
            if (where != null) ...[SizedBox(height: t.space.xs), Text(where, style: t.text.caption.copyWith(color: t.colors.inkSecondary))],
            SizedBox(height: t.space.lg),
            DButton(label: 'Check for new photos now', tone: DButtonTone.tonal, expand: true, id: 'photos.source.refresh', onPressed: () => Navigator.of(sheet).pop('refresh')),
            SizedBox(height: t.space.sm),
            DButton(label: 'Remove this source', tone: DButtonTone.danger, expand: true, id: 'photos.source.remove', onPressed: () => Navigator.of(sheet).pop('remove')),
          ],
        );
      },
    );
    if (!context.mounted || action == null) return;
    try {
      if (action == 'refresh') {
        await api.post('/api/admin/photos/refresh', const {});
        ref.read(toastProvider).show('Checking for new photos', emoji: '🖼️');
        return;
      }
      final ok = await confirmDialog(
        context,
        title: 'Remove ${s.name}?',
        message: 'Its ${s.itemCount} photos leave the photo frame on every display. The album itself isn’t touched.',
        confirmLabel: 'Remove',
        danger: true,
      );
      if (!ok) return;
      await api.delete('/api/admin/photos/sources/${s.id}');
      ref.read(toastProvider).show('Removed ${s.name}', emoji: '🗑️');
    } on HubApiException catch (e) {
      ref.read(toastProvider).show(e.friendly, emoji: '⚠️', tone: DBannerTone.warning);
    }
  }

  Future<void> _addSource(BuildContext context, WidgetRef ref, HubApi api, String kind) async {
    final input = TextEditingController();
    final ok = await showDSheet<bool>(
      context,
      title: kind == 'amazon' ? 'Amazon Photos album' : 'Photo folder',
      builder: (sheet) {
        final t = DTheme.of(sheet);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (kind == 'amazon')
              Text(
                'In Amazon Photos, create an album (for example “Dearth Frame”), choose Share → Get link, and paste it below. '
                'Anyone with the link can view that album, so keep it to photos you’re happy to share.',
                style: t.text.body,
              ),
            SizedBox(height: t.space.md),
            DTextField(id: 'photos.source.input', controller: input, hint: kind == 'amazon' ? 'https://www.amazon.com/photos/share/…' : '/photos/family', autofocus: true),
            SizedBox(height: t.space.lg),
            DButton(label: 'Add', expand: true, id: 'photos.source.save', onPressed: () => Navigator.of(sheet).pop(true)),
          ],
        );
      },
    );
    final value = input.text.trim();
    input.dispose();
    if (ok != true || value.isEmpty) return;
    try {
      await api.post('/api/admin/photos/sources', {
        'kind': kind,
        'config': kind == 'amazon' ? {'shareUrl': value} : {'path': value},
      });
      ref.read(toastProvider).show('Added — photos arrive over the next few minutes', emoji: '🖼️');
    } on HubApiException catch (e) {
      ref.read(toastProvider).show(e.friendly, emoji: '⚠️', tone: DBannerTone.warning);
    }
  }
}
