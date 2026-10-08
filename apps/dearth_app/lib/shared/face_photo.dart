import 'dart:convert';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/providers.dart';

/// A face cut from a photo in the family library (Settings → People): the
/// photo's blob, its shape, and a square around the face. Kept on the
/// profile as `avatar_blob` JSON, so every display shows the same face
/// without a second image (SPEC FR-TOY-03 Who's That?).
@immutable
class FaceCrop {
  const FaceCrop(this.sha, {required this.aspect, required this.x, required this.y, required this.w});

  /// The photo's blob.
  final String sha;

  /// The photo's width over its height.
  final double aspect;

  /// The square's left and top as fractions of the photo's width and
  /// height, and its side as a fraction of the width.
  final double x, y, w;

  /// The square's side as a fraction of the photo's height.
  double get h => w * aspect;

  static FaceCrop? parse(String? blob) {
    if (blob == null || blob.isEmpty) return null;
    try {
      final j = jsonDecode(blob);
      if (j is! Map<String, Object?>) return null;
      final sha = j['sha'];
      final crop = j['crop'];
      if (sha is! String || crop is! List || crop.length != 3) return null;
      return FaceCrop(sha, aspect: (j['aspect'] as num?)?.toDouble() ?? 1, x: (crop[0] as num).toDouble(), y: (crop[1] as num).toDouble(), w: (crop[2] as num).toDouble());
    } on Object {
      return null;
    }
  }

  String encode() => jsonEncode({'sha': sha, 'aspect': aspect, 'crop': [x, y, w]});
}

/// [crop] filling a circle [size] across: the whole photo laid out so the
/// square lands on the circle, decoded at the size it shows.
class FacePhoto extends ConsumerWidget {
  const FacePhoto(this.crop, {super.key, required this.size, this.fallback});
  final FaceCrop crop;
  final double size;
  final Widget? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(hubApiProvider);
    if (api == null) return fallback ?? const SizedBox.shrink();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final width = size / math.max(crop.w, 0.01);
    final height = width / crop.aspect;
    final px = (width * dpr).round().clamp(32, 2048);
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          children: [
            Positioned(
              left: -crop.x * width,
              top: -crop.y * height,
              width: width,
              height: height,
              child: Image.network(
                api.blobUrl(crop.sha, width: px).toString(),
                fit: BoxFit.fill,
                cacheWidth: px,
                errorBuilder: (_, _, _) => fallback ?? const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A person's avatar: their face photo when they have one (and a Hub to
/// show it from), else their emoji or initial on their color.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar(this.profile, {super.key, required this.size, this.progress, this.ring = true});
  final Profile profile;
  final double size;
  final double? progress;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final crop = FaceCrop.parse(profile.avatarBlob);
    return DAvatar(
      colorIndex: profile.color,
      emoji: profile.emoji,
      name: profile.name,
      size: size,
      progress: progress,
      ring: ring,
      photo: crop == null ? null : (double inner) => FacePhoto(crop, size: inner, fallback: DEmoji(profile.emoji ?? '🙂', size: inner * 0.58)),
    );
  }
}
