import 'package:material_ui/material_ui.dart';

import '../display/display.dart';
import '../tokens/colors.dart';
import '../tokens/metrics.dart';
import '../tokens/typography.dart';

/// All design tokens for the current device + theme (SPEC §11). Read with
/// `DTheme.of(context)`; never hard-code colors, sizes or durations.
///
/// Note: the type scale is exposed as [text], not `type` — `ThemeExtension`
/// already uses `type` as its lookup key.
@immutable
class DTheme extends ThemeExtension<DTheme> {
  DTheme({
    required this.colors,
    required this.scale,
    required this.displayClass,
    required this.policy,
    this.reducedMotion = false,
  })  : text = DType.scaled(scale, colors.inkPrimary, colors.inkSecondary),
        space = DSpace(scale),
        radius = DRadius(scale),
        elevation = DElevation(colors.shadow, scale, blur: policy.blurAllowed);

  final DColors colors;
  final double scale;
  final DisplayClass displayClass;
  final TierPolicy policy;
  final bool reducedMotion;
  final DType text;
  final DSpace space;
  final DRadius radius;
  final DElevation elevation;

  static DTheme of(BuildContext context) => Theme.of(context).extension<DTheme>()!;

  bool get isPhone => displayClass == DisplayClass.phone;
  bool get isWall => displayClass.isWall;

  /// Margin around page content for this display class (SPEC §11.2).
  double get pageMargin => switch (displayClass) {
        DisplayClass.wallL || DisplayClass.wallP => space.xl,
        DisplayClass.tablet => space.lg,
        DisplayClass.phone => space.md,
      };

  /// Gutter between grid columns.
  double get gutter => switch (displayClass) {
        DisplayClass.wallL || DisplayClass.wallP => space.lg,
        DisplayClass.tablet || DisplayClass.phone => space.md,
      };

  PersonColors person(int colorIndex) => PersonColors.of(colorIndex, colors);

  /// Duration honoring reduced motion (SPEC §11.4).
  Duration motion(Duration d) => reducedMotion ? (d > DMotion.fast ? DMotion.fast : d) : d;

  /// Icon size helpers.
  double get iconSm => 22 * scale;
  double get iconMd => 28 * scale;
  double get iconLg => 36 * scale;

  @override
  DTheme copyWith({DColors? colors, double? scale, DisplayClass? displayClass, TierPolicy? policy, bool? reducedMotion}) => DTheme(
        colors: colors ?? this.colors,
        scale: scale ?? this.scale,
        displayClass: displayClass ?? this.displayClass,
        policy: policy ?? this.policy,
        reducedMotion: reducedMotion ?? this.reducedMotion,
      );

  @override
  DTheme lerp(covariant DTheme? other, double t) => t < 0.5 ? this : (other ?? this);
}

/// Fast fade-through page transition (SPEC §11.4: no sliding pages on T1).
class FadeThroughPageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeThroughPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final curved = CurvedAnimation(parent: animation, curve: DMotion.standardCurve, reverseCurve: DMotion.exitCurve);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(scale: Tween<double>(begin: 0.985, end: 1).animate(curved), child: child),
    );
  }
}

/// Builds Material [ThemeData] from Dearth tokens. Ink sparkle (a fragment
/// shader) is replaced by plain ripples for weak GPUs (SPEC §12.3).
ThemeData buildThemeData(DTheme t) {
  final c = t.colors;
  final ty = t.text;
  final scheme = ColorScheme(
    brightness: c.isDark ? Brightness.dark : Brightness.light,
    primary: c.accent,
    onPrimary: c.onAccent,
    primaryContainer: c.accentTint,
    onPrimaryContainer: c.inkPrimary,
    secondary: c.accent,
    onSecondary: c.onAccent,
    secondaryContainer: c.accentTint,
    onSecondaryContainer: c.inkPrimary,
    error: c.danger,
    onError: Colors.white,
    surface: c.surface,
    onSurface: c.inkPrimary,
    surfaceContainerLowest: c.surfaceRaised,
    surfaceContainerLow: c.surfaceRaised,
    surfaceContainer: c.surfaceRaised,
    surfaceContainerHigh: c.surfaceSunken,
    surfaceContainerHighest: c.surfaceSunken,
    onSurfaceVariant: c.inkSecondary,
    outline: c.outline,
    outlineVariant: c.outline,
    shadow: c.shadow,
    scrim: c.scrim,
  );
  final shape = RoundedRectangleBorder(borderRadius: t.radius.card);
  final buttonShape = RoundedRectangleBorder(borderRadius: t.radius.pill);
  final minButton = Size(t.space.touchDense * 1.6, t.space.touchDense);
  const transitions = PageTransitionsTheme(builders: {
    TargetPlatform.android: FadeThroughPageTransitionsBuilder(),
    TargetPlatform.iOS: FadeThroughPageTransitionsBuilder(),
    TargetPlatform.linux: FadeThroughPageTransitionsBuilder(),
    TargetPlatform.macOS: FadeThroughPageTransitionsBuilder(),
    TargetPlatform.windows: FadeThroughPageTransitionsBuilder(),
    TargetPlatform.fuchsia: FadeThroughPageTransitionsBuilder(),
  });

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: scheme.brightness,
    scaffoldBackgroundColor: c.surface,
    canvasColor: c.surface,
    fontFamily: DFonts.ui,
    package: DFonts.package,
    splashFactory: InkRipple.splashFactory,
    highlightColor: c.inkPrimary.withValues(alpha: 0.04),
    splashColor: c.accent.withValues(alpha: 0.08),
    hoverColor: c.inkPrimary.withValues(alpha: 0.04),
    focusColor: c.accent.withValues(alpha: 0.18),
    materialTapTargetSize: MaterialTapTargetSize.padded,
    pageTransitionsTheme: transitions,
    textTheme: TextTheme(
      displayLarge: ty.display,
      displayMedium: ty.h1,
      displaySmall: ty.h2,
      headlineLarge: ty.h1,
      headlineMedium: ty.h2,
      headlineSmall: ty.title,
      titleLarge: ty.title,
      titleMedium: ty.bodyStrong,
      titleSmall: ty.label,
      bodyLarge: ty.body,
      bodyMedium: ty.body,
      bodySmall: ty.caption,
      labelLarge: ty.label,
      labelMedium: ty.label,
      labelSmall: ty.caption,
    ),
    iconTheme: IconThemeData(color: c.inkPrimary, size: t.iconMd),
    dividerTheme: DividerThemeData(color: c.outline, thickness: 1, space: t.space.md),
    cardTheme: CardThemeData(color: c.surfaceRaised, elevation: 0, margin: EdgeInsets.zero, shape: shape),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(borderRadius: t.radius.sheet),
      titleTextStyle: ty.h2,
      contentTextStyle: ty.body,
      elevation: 0,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surfaceRaised,
      modalBackgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(t.radius.l))),
      showDragHandle: true,
      elevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        minimumSize: minButton,
        padding: EdgeInsets.symmetric(horizontal: t.space.lg, vertical: t.space.sm),
        shape: buttonShape,
        textStyle: ty.label,
        splashFactory: InkRipple.splashFactory,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.inkPrimary,
        minimumSize: minButton,
        padding: EdgeInsets.symmetric(horizontal: t.space.lg, vertical: t.space.sm),
        side: BorderSide(color: c.outline, width: 1.5),
        shape: buttonShape,
        textStyle: ty.label,
        splashFactory: InkRipple.splashFactory,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        minimumSize: Size(t.space.touchDense, t.space.touchDense),
        shape: buttonShape,
        textStyle: ty.label,
        splashFactory: InkRipple.splashFactory,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: Size.square(t.space.touchDense), iconSize: t.iconMd, splashFactory: InkRipple.splashFactory),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surfaceSunken,
      selectedColor: c.accentTint,
      labelStyle: ty.label,
      side: BorderSide.none,
      shape: buttonShape,
      padding: EdgeInsets.symmetric(horizontal: t.space.sm, vertical: t.space.xs),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: c.surfaceSunken,
      contentPadding: EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.md),
      hintStyle: ty.body.copyWith(color: c.inkTertiary),
      labelStyle: ty.label.copyWith(color: c.inkSecondary),
      floatingLabelStyle: ty.label.copyWith(color: c.accent),
      border: OutlineInputBorder(borderRadius: t.radius.card, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: t.radius.card, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: t.radius.card, borderSide: BorderSide(color: c.accent, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: t.radius.card, borderSide: BorderSide(color: c.danger, width: 2)),
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: c.accent, selectionColor: c.accent.withValues(alpha: 0.28), selectionHandleColor: c.accent),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStatePropertyAll(c.surfaceRaised),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : c.outline),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    sliderTheme: SliderThemeData(activeTrackColor: c.accent, inactiveTrackColor: c.outline, thumbColor: c.accent, trackHeight: 6 * t.scale),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent, linearTrackColor: c.outline, circularTrackColor: c.outline),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.inkPrimary,
      contentTextStyle: ty.body.copyWith(color: c.surface),
      shape: RoundedRectangleBorder(borderRadius: t.radius.card),
      behavior: SnackBarBehavior.floating,
    ),
    tooltipTheme: TooltipThemeData(textStyle: ty.caption.copyWith(color: c.surface), decoration: BoxDecoration(color: c.inkPrimary, borderRadius: t.radius.card)),
    scrollbarTheme: ScrollbarThemeData(thumbColor: WidgetStatePropertyAll(c.inkTertiary.withValues(alpha: 0.4)), radius: Radius.circular(t.radius.s)),
    extensions: [t],
  );
}

/// Shorthand: `context.dt` for the current [DTheme].
extension DThemeContext on BuildContext {
  DTheme get dt => DTheme.of(this);
}
