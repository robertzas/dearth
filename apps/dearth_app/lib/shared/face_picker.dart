import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/providers.dart';
import '../core/sync/hub_api.dart';
import '../features/photos/photos_data.dart';
import 'face_photo.dart';

/// Picks a face for a person (Settings → People): a photo from the family
/// library, then the face fitted into a circle by dragging and pinching.
/// Null when cancelled, or without a Hub (the library lives there).
Future<FaceCrop?> pickFace(BuildContext context, WidgetRef ref) async {
  final api = ref.read(hubApiProvider);
  if (api == null) return null;
  final photos = (await photoItemsOnce(ref.read(dbProvider))).where((p) => blobSha(p.blobRef) != null).take(60).toList();
  if (!context.mounted) return null;
  final photo = await showDSheet<PhotoItem>(
    context,
    id: 'face.photos',
    title: 'Choose a photo',
    builder: (sheet) {
      final t = DTheme.of(sheet);
      final dpr = MediaQuery.devicePixelRatioOf(sheet);
      final side = 104 * t.scale;
      if (photos.isEmpty) {
        return const DEmptyState(id: 'face.none', emoji: '🖼️', title: 'No photos yet', message: 'Add a photo album in Settings → Photos, then come back for a face.');
      }
      return Wrap(
        spacing: t.space.xs,
        runSpacing: t.space.xs,
        children: [
          for (final p in photos)
            DPressable(
              id: 'face.photo.${p.id}',
              semanticLabel: p.caption ?? 'Photo',
              borderRadius: BorderRadius.circular(10 * t.scale),
              onTap: () => Navigator.of(sheet).pop(p),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10 * t.scale),
                child: SizedBox.square(
                  dimension: side,
                  child: Image.network(
                    api.blobUrl(blobSha(p.thumbBlob) ?? blobSha(p.blobRef)!, width: (side * dpr).round(), height: (side * dpr).round(), cover: true).toString(),
                    fit: BoxFit.cover,
                    cacheWidth: (side * dpr).round(),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
  if (photo == null || !context.mounted) return null;
  return _fit(context, api, photo);
}

/// The photo under a circle: drag and pinch until the face fills it.
Future<FaceCrop?> _fit(BuildContext context, HubApi api, PhotoItem photo) {
  final sha = blobSha(photo.blobRef)!;
  final aspect = (photo.width ?? 1) / math.max(1, photo.height ?? 1);
  final controller = TransformationController();
  return showDSheet<FaceCrop>(
    context,
    id: 'face.fit',
    title: 'Fit the face in the circle',
    builder: (sheet) {
      final t = DTheme.of(sheet);
      final dpr = MediaQuery.devicePixelRatioOf(sheet);
      final v = math.min(MediaQuery.sizeOf(sheet).width - 64, 440 * t.scale);
      // The whole photo fits the square at first; she zooms to the face.
      final (cw, ch) = aspect >= 1 ? (v, v / aspect) : (v * aspect, v);
      final ox = (v - cw) / 2, oy = (v - ch) / 2;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: SizedBox.square(
              dimension: v,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: t.radius.card,
                    child: ColoredBox(
                      color: t.colors.surfaceSunken,
                      child: InteractiveViewer(
                        transformationController: controller,
                        minScale: 1,
                        maxScale: 8,
                        child: SizedBox.square(
                          dimension: v,
                          child: Center(
                            child: SizedBox(
                              width: cw,
                              height: ch,
                              child: Image.network(api.blobUrl(sha, width: (v * dpr * 2).round()).toString(), fit: BoxFit.fill),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(child: CustomPaint(size: Size.square(v), painter: const _CircleMask())),
                ],
              ),
            ),
          ),
          SizedBox(height: t.space.sm),
          Text('Drag and pinch the photo until the face fills the circle.', style: t.text.caption.copyWith(color: t.colors.inkSecondary), textAlign: TextAlign.center),
          SizedBox(height: t.space.md),
          DButton(
            label: 'Use this face',
            icon: Icons.check_rounded,
            id: 'face.use',
            onPressed: () {
              final tl = controller.toScene(Offset.zero), br = controller.toScene(Offset(v, v));
              Navigator.of(sheet).pop(FaceCrop(sha, aspect: aspect, x: (tl.dx - ox) / cw, y: (tl.dy - oy) / ch, w: (br.dx - tl.dx) / cw));
            },
          ),
        ],
      );
    },
  );
}

/// Dims everything outside the circle and rings it.
class _CircleMask extends CustomPainter {
  const _CircleMask();

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2 * 0.92;
    final c = size.center(Offset.zero);
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: c, radius: r));
    canvas
      ..drawPath(outside, Paint()..color = const Color(0x88000000))
      ..drawCircle(
        c,
        r,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
  }

  @override
  bool shouldRepaint(_CircleMask old) => false;
}
