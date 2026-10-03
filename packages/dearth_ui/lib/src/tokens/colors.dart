import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

/// Visual themes (SPEC §11.6).
enum DThemeMode { light, evening, night }

/// Color tokens for one theme (SPEC §11.3, "Warm Daylight").
@immutable
class DColors {
  const DColors({
    required this.mode,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.inkPrimary,
    required this.inkSecondary,
    required this.inkTertiary,
    required this.outline,
    required this.accent,
    required this.onAccent,
    required this.accentTint,
    required this.success,
    required this.warning,
    required this.danger,
    required this.shadow,
    required this.scrim,
    required this.vizRain,
    required this.vizSun,
    required this.vizWarm,
    required this.vizCool,
    required this.vizUv,
  });

  final DThemeMode mode;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceSunken;
  final Color inkPrimary;
  final Color inkSecondary;
  final Color inkTertiary;
  final Color outline;
  final Color accent;
  final Color onAccent;

  /// Selected/active backgrounds (chips, nav items).
  final Color accentTint;
  final Color success;
  final Color warning;
  final Color danger;
  final Color shadow;
  final Color scrim;

  /// Data-visualization colors (weather charts, progress).
  final Color vizRain;
  final Color vizSun;
  final Color vizWarm;
  final Color vizCool;
  final Color vizUv;

  bool get isDark => mode != DThemeMode.light;

  Color tintOf(Color c, [double amount = 0.14]) => Color.alphaBlend(c.withValues(alpha: isDark ? amount * 1.6 : amount), surfaceRaised);

  static const light = DColors(
    mode: DThemeMode.light,
    surface: Color(0xFFF7F4EE),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFEFEAE1),
    inkPrimary: Color(0xFF1E1C24),
    inkSecondary: Color(0xFF5E5A66),
    inkTertiary: Color(0xFF8C8794),
    outline: Color(0xFFE2DCD1),
    accent: Color(0xFF5B5BD6),
    onAccent: Color(0xFFFFFFFF),
    accentTint: Color(0xFFE9E8FA),
    success: Color(0xFF2E9E6A),
    warning: Color(0xFFE9A23B),
    danger: Color(0xFFD9534F),
    shadow: Color(0x261E1C24),
    scrim: Color(0x991E1C24),
    vizRain: Color(0xFF3D8FE0),
    vizSun: Color(0xFFF2B33D),
    vizWarm: Color(0xFFF2795D),
    vizCool: Color(0xFF3D9BE9),
    vizUv: Color(0xFF9B6CF0),
  );

  static const evening = DColors(
    mode: DThemeMode.evening,
    surface: Color(0xFF14161C),
    surfaceRaised: Color(0xFF1D2029),
    surfaceSunken: Color(0xFF0F1116),
    inkPrimary: Color(0xFFF2F0EC),
    inkSecondary: Color(0xFFA9A6B2),
    inkTertiary: Color(0xFF75727F),
    outline: Color(0xFF2C3040),
    accent: Color(0xFF8E8CF5),
    onAccent: Color(0xFF14161C),
    accentTint: Color(0xFF2A2B48),
    success: Color(0xFF4CC38A),
    warning: Color(0xFFF5B85A),
    danger: Color(0xFFF07470),
    shadow: Color(0x66000000),
    scrim: Color(0xB3000000),
    vizRain: Color(0xFF5FA8F0),
    vizSun: Color(0xFFF5C25A),
    vizWarm: Color(0xFFF59478),
    vizCool: Color(0xFF6BB3F2),
    vizUv: Color(0xFFB28EF5),
  );

  /// Near-black with dim amber ink for dark rooms (night clock, kid room).
  static const night = DColors(
    mode: DThemeMode.night,
    surface: Color(0xFF000000),
    surfaceRaised: Color(0xFF0B0B0B),
    surfaceSunken: Color(0xFF000000),
    inkPrimary: Color(0xFFB8753A),
    inkSecondary: Color(0xFF6E4A2A),
    inkTertiary: Color(0xFF4A321D),
    outline: Color(0xFF1A1209),
    accent: Color(0xFF8A5A2E),
    onAccent: Color(0xFF000000),
    accentTint: Color(0xFF1A1007),
    success: Color(0xFF3C6B4C),
    warning: Color(0xFF8A6A2E),
    danger: Color(0xFF8A3A36),
    shadow: Color(0x00000000),
    scrim: Color(0xCC000000),
    vizRain: Color(0xFF4A5A70),
    vizSun: Color(0xFF8A6A2E),
    vizWarm: Color(0xFF8A4A30),
    vizCool: Color(0xFF3A5A70),
    vizUv: Color(0xFF5A4A70),
  );

  static DColors of(DThemeMode mode) => switch (mode) {
        DThemeMode.light => light,
        DThemeMode.evening => evening,
        DThemeMode.night => night,
      };
}

/// The 12 profile colors (matches dearth_core `kProfilePalette`).
const List<Color> kProfileColors = [
  Color(0xFFF2795D), // Coral
  Color(0xFFF2B33D), // Amber
  Color(0xFF8CC152), // Lime
  Color(0xFF3CC59A), // Mint
  Color(0xFF26A9A0), // Teal
  Color(0xFF3D9BE9), // Sky
  Color(0xFF5B6CF2), // Indigo
  Color(0xFF9B6CF0), // Violet
  Color(0xFFEE6BA8), // Pink
  Color(0xFFE5484D), // Red
  Color(0xFFA8785A), // Brown
  Color(0xFF6B7A8F), // Slate
];

/// Derived colors for a person (SPEC §11.3: solid, tint, on-solid).
@immutable
class PersonColors {
  const PersonColors(this.solid, this.tint, this.onSolid, this.ink);

  factory PersonColors.of(int index, DColors theme) {
    final solid = kProfileColors[index % kProfileColors.length];
    if (theme.mode == DThemeMode.night) {
      // Night keeps hue but drops brightness so nothing glows in a dark room.
      final dim = HSLColor.fromColor(solid).withLightness(0.22).withSaturation(0.45).toColor();
      return PersonColors(dim, Color.alphaBlend(dim.withValues(alpha: 0.35), theme.surfaceRaised), theme.inkPrimary, theme.inkPrimary);
    }
    final tint = Color.alphaBlend(solid.withValues(alpha: theme.isDark ? 0.22 : 0.14), theme.surfaceRaised);
    final onSolid = solid.computeLuminance() > 0.45 ? const Color(0xFF1E1C24) : const Color(0xFFFFFFFF);
    // Text on a tint: darken in light mode, lighten in dark mode for contrast.
    final hsl = HSLColor.fromColor(solid);
    final ink = theme.isDark
        ? hsl.withLightness((hsl.lightness + 0.18).clamp(0, 0.85)).toColor()
        : hsl.withLightness((hsl.lightness - 0.22).clamp(0.15, 1)).toColor();
    return PersonColors(solid, tint, onSolid, ink);
  }

  final Color solid;
  final Color tint;
  final Color onSolid;
  final Color ink;
}

/// Sticky-note colors (index stored on notes.color).
const List<Color> kNoteColors = [
  Color(0xFFFFF4B8),
  Color(0xFFFFD9C7),
  Color(0xFFD7F2D0),
  Color(0xFFD3E7FF),
  Color(0xFFEADCFF),
  Color(0xFFFFDDEA),
];

/// Ink for text on a sticky note (notes stay light in every theme).
const Color kNoteInk = Color(0xFF2A2630);
