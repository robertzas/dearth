import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart' show immutable;

/// Layout classes by logical size (SPEC §6.2).
enum DisplayClass {
  wallL,
  wallP,
  tablet,
  phone;

  bool get isWall => this == wallL || this == wallP;
  bool get isLandscapeWall => this == wallL;
  bool get usesRail => this == wallL || this == tablet;
}

DisplayClass resolveDisplayClass(Size size) {
  final shortest = math.min(size.width, size.height);
  if (shortest < 600) return DisplayClass.phone;
  if (size.width >= 1280 && size.width > size.height) return DisplayClass.wallL;
  if (size.height >= 1280 && size.height >= size.width) return DisplayClass.wallP;
  return DisplayClass.tablet;
}

/// Viewing distance presets (SPEC §11.2).
enum ViewingDistance {
  near(0.82),
  room(1.0),
  far(1.22);

  const ViewingDistance(this.factor);
  final double factor;

  static ViewingDistance parse(String? s) => values.firstWhere((v) => v.name == s, orElse: () => room);
}

/// Computes the per-device `uiScale` (SPEC §11.2). With a known diagonal the
/// scale keeps text at the same *physical* size as the reference 27" 1080p
/// frame at room distance; otherwise class defaults apply.
double computeUiScale({
  required Size logicalSize,
  required double devicePixelRatio,
  required DisplayClass displayClass,
  double? diagonalInches,
  ViewingDistance distance = ViewingDistance.room,
  double userScale = 1.0,
}) {
  double base;
  if (diagonalInches != null && diagonalInches > 3) {
    final pw = logicalSize.width * devicePixelRatio;
    final ph = logicalSize.height * devicePixelRatio;
    final ppi = math.sqrt(pw * pw + ph * ph) / diagonalInches;
    final mmPerLogicalPx = 25.4 / (ppi / devicePixelRatio);
    const referenceMm = 0.336; // 27" 1080p at dpr 1.08 (the kitchen frame)
    base = referenceMm / mmPerLogicalPx;
    base = switch (displayClass) {
      DisplayClass.wallL || DisplayClass.wallP => base.clamp(0.85, 1.2),
      DisplayClass.tablet => base.clamp(0.7, 1.05),
      DisplayClass.phone => base.clamp(0.62, 0.85),
    };
  } else {
    base = switch (displayClass) {
      DisplayClass.wallL || DisplayClass.wallP => 1.0,
      DisplayClass.tablet => 0.84,
      DisplayClass.phone => 0.72,
    };
  }
  return (base * distance.factor * userScale).clamp(0.55, 1.6);
}

/// Performance tiers (SPEC §6.2).
enum PerfTier { t1, t2, t3 }

PerfTier detectTier({int? totalRamMb, bool lowRamDevice = false, bool isWeb = false, bool isDesktop = false, String? override}) {
  if (override != null) {
    for (final t in PerfTier.values) {
      if (t.name == override) return t;
    }
  }
  if (isDesktop) return PerfTier.t3;
  if (lowRamDevice || (totalRamMb != null && totalRamMb <= 3072)) return PerfTier.t1;
  if (isWeb) return PerfTier.t2;
  if (totalRamMb != null && totalRamMb <= 6144) return PerfTier.t2;
  return PerfTier.t3;
}

/// What each tier may afford (SPEC §6.2, §12.3).
@immutable
class TierPolicy {
  const TierPolicy({
    required this.tier,
    required this.blurAllowed,
    required this.ambientFps,
    required this.maxParticles,
    required this.imageCacheMb,
    required this.kenBurns,
    required this.heroTransitions,
  });

  factory TierPolicy.of(PerfTier tier) => switch (tier) {
        PerfTier.t1 => const TierPolicy(tier: PerfTier.t1, blurAllowed: false, ambientFps: 30, maxParticles: 120, imageCacheMb: 48, kenBurns: false, heroTransitions: false),
        PerfTier.t2 => const TierPolicy(tier: PerfTier.t2, blurAllowed: true, ambientFps: 60, maxParticles: 300, imageCacheMb: 96, kenBurns: true, heroTransitions: true),
        PerfTier.t3 => const TierPolicy(tier: PerfTier.t3, blurAllowed: true, ambientFps: 60, maxParticles: 600, imageCacheMb: 160, kenBurns: true, heroTransitions: true),
      };

  final PerfTier tier;
  final bool blurAllowed;
  final int ambientFps;
  final int maxParticles;
  final int imageCacheMb;
  final bool kenBurns;
  final bool heroTransitions;
}
