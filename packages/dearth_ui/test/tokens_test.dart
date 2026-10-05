import 'dart:math' as math;

import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('SPEC §6.2 display classes', () {
    test('the four reference viewports classify as specified', () {
      expect(resolveDisplayClass(const Size(1777, 1000)), DisplayClass.wallL);
      expect(resolveDisplayClass(const Size(1000, 1777)), DisplayClass.wallP);
      expect(resolveDisplayClass(const Size(1280, 800)), DisplayClass.wallL);
      expect(resolveDisplayClass(const Size(1180, 820)), DisplayClass.tablet);
      expect(resolveDisplayClass(const Size(390, 844)), DisplayClass.phone);
    });

    test('§11.2 the 27" kitchen frame at room distance has uiScale ≈ 1', () {
      final s = computeUiScale(logicalSize: const Size(1777, 1000), devicePixelRatio: 1.08, displayClass: DisplayClass.wallL, diagonalInches: 27);
      expect(s, closeTo(1.0, 0.03));
    });

    test('§11.2 viewing distance and the user slider scale text', () {
      double scale(ViewingDistance d, [double user = 1]) =>
          computeUiScale(logicalSize: const Size(1777, 1000), devicePixelRatio: 1.08, displayClass: DisplayClass.wallL, distance: d, userScale: user);
      expect(scale(ViewingDistance.far), greaterThan(scale(ViewingDistance.room)));
      expect(scale(ViewingDistance.near), lessThan(scale(ViewingDistance.room)));
      expect(scale(ViewingDistance.room, 1.2), closeTo(1.2, 0.001));
    });

    test('§6.2 tier detection', () {
      expect(detectTier(totalRamMb: 2048), PerfTier.t1);
      expect(detectTier(lowRamDevice: true), PerfTier.t1);
      expect(detectTier(totalRamMb: 4096), PerfTier.t2);
      expect(detectTier(isDesktop: true), PerfTier.t3);
      expect(detectTier(totalRamMb: 2048, override: 't3'), PerfTier.t3);
      expect(TierPolicy.of(PerfTier.t1).blurAllowed, isFalse);
      expect(TierPolicy.of(PerfTier.t1).ambientFps, 30);
    });

    test('§12.3 T1 shadows are flat offsets (no blur pass)', () {
      const shadow = Color(0xFF000000);
      final blurred = const DElevation(shadow, 1.5).e1.first;
      final flat = const DElevation(shadow, 1.5, blur: false).e1.first;
      expect(blurred.blurRadius, 8 * 1.5);
      expect(flat.blurRadius, 0);
      expect(flat.offset, blurred.offset);
      expect(const DElevation(shadow, 1.5, blur: false).e2.first.blurRadius, 0);
    });
  });

  group('SPEC §11.9 contrast (WCAG 2.2 AA)', () {
    for (final c in [DColors.light, DColors.evening]) {
      test('${c.mode.name}: body ink on every surface ≥ 4.5:1', () {
        for (final bg in [c.surface, c.surfaceRaised, c.surfaceSunken]) {
          expect(contrast(c.inkPrimary, bg), greaterThanOrEqualTo(4.5));
          expect(contrast(c.inkSecondary, bg), greaterThanOrEqualTo(4.5));
        }
      });

      test('${c.mode.name}: accent buttons are legible', () {
        expect(contrast(c.onAccent, c.accent), greaterThanOrEqualTo(4.5));
      });

      test('${c.mode.name}: person ink on person tints ≥ 3:1 (bold labels)', () {
        for (var i = 0; i < kProfileColors.length; i++) {
          final p = PersonColors.of(i, c);
          expect(contrast(p.ink, p.tint), greaterThanOrEqualTo(3), reason: 'color $i');
        }
      });
    }
  });
}
