import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

/// Spacing scale (4-pt base × uiScale; SPEC §11.3).
@immutable
class DSpace {
  const DSpace(this.scale);
  final double scale;

  double get xxs => 4 * scale;
  double get xs => 8 * scale;
  double get sm => 12 * scale;
  double get md => 16 * scale;
  double get lg => 24 * scale;
  double get xl => 32 * scale;
  double get xxl => 48 * scale;
  double get huge => 72 * scale;

  /// Minimum comfortable touch target on walls (SPEC §11.1: ≥ 64 dp).
  double get touch => 64 * scale;
  double get touchDense => 48 * scale;
}

/// Corner radii.
@immutable
class DRadius {
  const DRadius(this.scale);
  final double scale;
  double get s => 12 * scale;
  double get m => 20 * scale;
  double get l => 28 * scale;
  double get xl => 36 * scale;
  BorderRadius get card => BorderRadius.circular(m);
  BorderRadius get sheet => BorderRadius.circular(l);
  BorderRadius get pill => BorderRadius.circular(999);
}

/// Elevation: single analytic shadows only (SPEC §11.3, §12.3).
@immutable
class DElevation {
  const DElevation(this.shadow, this.scale);
  final Color shadow;
  final double scale;

  List<BoxShadow> get e1 => [BoxShadow(color: shadow.withValues(alpha: shadow.a * 0.55), offset: Offset(0, 2 * scale), blurRadius: 8 * scale)];
  List<BoxShadow> get e2 => [BoxShadow(color: shadow, offset: Offset(0, 8 * scale), blurRadius: 24 * scale)];
  List<BoxShadow> get none => const [];
}

/// Motion tokens (SPEC §11.4).
abstract final class DMotion {
  static const micro = Duration(milliseconds: 90);
  static const fast = Duration(milliseconds: 150);
  static const standard = Duration(milliseconds: 220);
  static const emphasized = Duration(milliseconds: 320);
  static const ambient = Duration(milliseconds: 1200);
  static const celebration = Duration(milliseconds: 1600);

  static const Curve standardCurve = Curves.easeOutCubic;
  static const Curve emphasizedCurve = Cubic(0.2, 0, 0, 1);
  static const Curve exitCurve = Curves.easeInCubic;
}
