import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/providers.dart';
import '../../../core/sync/hub_api.dart';
import '../../photos/photos_data.dart';
import '../settings_screen.dart';

/// Where the photo frame's pictures come from (SPEC FR-PHO-01, FR-PHO-02):
/// shared albums and folders the Hub reads.
class PhotosSection extends ConsumerWidget {
  const PhotosSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final w = ref.read(writerProvider);
    final sources = ref.watch(photoSourcesProvider).value ?? const <PhotoSource>[];
    final api = ref.watch(hubApiProvider);
    final admin = ref.watch(sessionProvider.select((s) => s.admin));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
