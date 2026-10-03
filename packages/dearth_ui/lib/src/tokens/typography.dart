import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

/// Font families bundled with dearth_ui (OFL; no runtime fetch).
abstract final class DFonts {
  static const package = 'dearth_ui';
  static const ui = 'PlusJakartaSans';
  static const kid = 'Fredoka';
}

/// The type scale (SPEC §11.3). Sizes are logical px at uiScale 1.0 on a
/// wall display; [DType.scaled] multiplies them for each device.
@immutable
class DType {
  const DType({
    required this.clockXL,
    required this.display,
    required this.h1,
    required this.h2,
    required this.title,
    required this.body,
    required this.bodyStrong,
    required this.label,
    required this.caption,
    required this.overline,
    required this.numeral,
    required this.kidDisplay,
    required this.kidTitle,
    required this.kidBody,
  });

  factory DType.scaled(double scale, Color ink, Color inkSecondary) {
    TextStyle s(
      double size,
      FontWeight w, {
      double height = 1.25,
      Color? color,
      String family = DFonts.ui,
      double spacing = 0,
      bool tabular = false,
    }) =>
        TextStyle(
          fontFamily: family,
          package: DFonts.package,
          fontSize: (size * scale).roundToDouble(),
          fontWeight: w,
          height: height,
          color: color ?? ink,
          letterSpacing: spacing * scale,
          fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
          fontVariations: [FontVariation('wght', w.value.toDouble())],
          leadingDistribution: TextLeadingDistribution.even,
        );
    return DType(
      clockXL: s(120, FontWeight.w300, height: 1, spacing: -3, tabular: true),
      display: s(72, FontWeight.w600, height: 1.05, spacing: -2, tabular: true),
      h1: s(44, FontWeight.w700, height: 1.1, spacing: -0.8),
      h2: s(32, FontWeight.w700, height: 1.15, spacing: -0.4),
      title: s(26, FontWeight.w600, height: 1.2, spacing: -0.2),
      body: s(22, FontWeight.w500, height: 1.35),
      bodyStrong: s(22, FontWeight.w700, height: 1.35),
      label: s(18, FontWeight.w600, tabular: true),
      caption: s(16, FontWeight.w500, height: 1.3, color: inkSecondary),
      overline: s(15, FontWeight.w800, height: 1.2, color: inkSecondary, spacing: 1.4),
      numeral: s(22, FontWeight.w700, height: 1.1, tabular: true),
      kidDisplay: s(64, FontWeight.w600, height: 1.05, family: DFonts.kid),
      kidTitle: s(34, FontWeight.w600, height: 1.15, family: DFonts.kid),
      kidBody: s(26, FontWeight.w500, family: DFonts.kid),
    );
  }

  /// Screensaver and night clock.
  final TextStyle clockXL;

  /// Home clock, big temperature.
  final TextStyle display;
  final TextStyle h1;
  final TextStyle h2;
  final TextStyle title;
  final TextStyle body;
  final TextStyle bodyStrong;

  /// Chips, buttons, metadata (tabular figures for times).
  final TextStyle label;
  final TextStyle caption;

  /// Uppercase section labels ("TODAY", "UP NEXT").
  final TextStyle overline;

  /// Times and quantities in lists.
  final TextStyle numeral;
  final TextStyle kidDisplay;
  final TextStyle kidTitle;
  final TextStyle kidBody;
}
