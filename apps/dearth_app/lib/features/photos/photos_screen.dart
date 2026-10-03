import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/display_state.dart';
import '../../core/data/household.dart';
import '../../core/providers.dart';
import '../../core/sync/hub_api.dart';
import 'art_pack.dart';
import 'photos_data.dart';

enum _Filter { all, favorites, hidden }

/// Photos curation (SPEC FR-PHO-07): a grid per source with favorite and
/// hide marks that sync to every display.
class PhotosScreen extends ConsumerStatefulWidget {
  const PhotosScreen({super.key});

  @override
  ConsumerState<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends ConsumerState<PhotosScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final items = ref.watch(photoItemsProvider).value ?? const <PhotoItem>[];
    final api = ref.watch(hubApiProvider);
    final shown = [
      for (final p in items)
        if (switch (_filter) { _Filter.all => !p.hidden, _Filter.favorites => p.favorite && !p.hidden, _Filter.hidden => p.hidden }) p,
    ];
    final cols = t.isPhone ? 3 : (MediaQuery.sizeOf(context).width > 1400 ? 6 : 4);

    return tid(
      'screen.photos',
      CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(t.pageMargin, t.pageMargin, t.pageMargin, t.space.md),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DPageHeader(
                    title: 'Photos',
                    subtitle: items.isEmpty ? 'Built-in art until you add photos' : '${items.where((p) => !p.hidden).length} photos',
                    actions: [
                      DButton(
                        label: 'Start frame',
                        icon: Icons.slideshow_rounded,
                        id: 'photos.start',
                        onPressed: () => ref.read(displayProvider.notifier).startScreensaver(),
                      ),
                    ],
                  ),
                  if (items.isNotEmpty) ...[
                    SizedBox(height: t.space.md),
                    DSegmented<_Filter>(
                      idPrefix: 'photos.filter',
                      options: const [(_Filter.all, 'All'), (_Filter.favorites, 'Favorites'), (_Filter.hidden, 'Hidden')],
                      value: _filter,
                      onChanged: (v) => setState(() => _filter = v),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (items.isEmpty) ...[
            SliverToBoxAdapter(
              child: DEmptyState(
                emoji: '🖼️',
                title: 'Your photo frame',
                message: 'Add an Amazon Photos shared album or a NAS folder on the Hub. Until then the frame shows this art.',
                action: DButton(label: 'Add photos', tone: DButtonTone.tonal, id: 'photos.add', onPressed: () => context.go('/settings/screensaver')),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: t.pageMargin),
              sliver: SliverGrid.count(
                crossAxisCount: cols,
                mainAxisSpacing: t.space.sm,
                crossAxisSpacing: t.space.sm,
                childAspectRatio: 16 / 10,
                children: [
                  for (var i = 0; i < kArtCount; i++)
                    ClipRRect(
                      borderRadius: t.radius.card,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ArtScene(i),
                          const Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: 56,
                            child: DecoratedBox(
                              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0x66000000)])),
                            ),
                          ),
                          Positioned(
                            left: t.space.sm,
                            bottom: t.space.xs,
                            child: Text(kArtTitles[i], style: t.text.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w800, shadows: const [Shadow(blurRadius: 6)])),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ] else if (api != null)
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: t.pageMargin),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, mainAxisSpacing: t.space.xs, crossAxisSpacing: t.space.xs),
                itemCount: shown.length,
                itemBuilder: (context, i) => _Thumb(photo: shown[i], api: api),
              ),
            ),
          SliverToBoxAdapter(child: SizedBox(height: t.space.xxl)),
        ],
      ),
    );
  }
}

class _Thumb extends ConsumerWidget {
  const _Thumb({required this.photo, required this.api});
  final PhotoItem photo;
  final HubApi api;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final sha = blobSha(photo.thumbBlob) ?? blobSha(photo.blobRef);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return DPressable(
      id: 'photos.item.${photo.id}',
      onTap: () => _open(context, ref),
      borderRadius: BorderRadius.circular(10 * t.scale),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10 * t.scale),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: photo.color == null ? t.colors.surfaceSunken : Color(photo.color!)),
            if (sha != null)
              Image.network(api.blobUrl(sha, width: (240 * dpr).round(), height: (240 * dpr).round(), cover: true).toString(), fit: BoxFit.cover, cacheWidth: (240 * dpr).round()),
            if (photo.favorite) Positioned(right: 6, top: 6, child: DEmoji('⭐', size: 24 * t.scale)),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, WidgetRef ref) {
    final sha = blobSha(photo.blobRef);
    showDSheet<void>(
      context,
      title: photo.takenMs == null ? 'Photo' : DateFormat('MMMM d, y').format(ref.read(householdTimeProvider).wall(photo.takenMs!)),
      id: 'photos.viewer',
      builder: (sheet) {
        final t = DTheme.of(sheet);
        final w = ref.read(writerProvider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sha != null)
              ClipRRect(
                borderRadius: t.radius.card,
                child: Image.network(api.blobUrl(sha, width: 1280).toString(), fit: BoxFit.contain, height: 420 * t.scale),
              ),
            SizedBox(height: t.space.md),
            Row(
              children: [
                DButton(
                  label: photo.favorite ? 'Unfavorite' : 'Favorite',
                  emoji: '⭐',
                  tone: DButtonTone.tonal,
                  id: 'photos.viewer.favorite',
                  onPressed: () {
                    w.upsert('photo_items', photo.id, {'favorite': !photo.favorite});
                    Navigator.of(sheet).pop();
                  },
                ),
                SizedBox(width: t.space.sm),
                DButton(
                  label: photo.hidden ? 'Show again' : 'Hide',
                  emoji: '🙈',
                  tone: DButtonTone.neutral,
                  id: 'photos.viewer.hide',
                  onPressed: () {
                    w.upsert('photo_items', photo.id, {'hidden': !photo.hidden});
                    Navigator.of(sheet).pop();
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
