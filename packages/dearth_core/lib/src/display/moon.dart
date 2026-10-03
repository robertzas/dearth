import 'dart:math' as math;

import 'package:meta/meta.dart';

/// Moon phase computed locally (SPEC Appendix D: "computed locally").
@immutable
class MoonPhase {
  const MoonPhase(this.age, this.fraction);

  /// Days since the last new moon (0 … 29.53).
  final double age;

  /// 0 = new, 0.5 = full, → 1 = new again.
  final double fraction;

  static const synodicMonth = 29.530588853;

  /// Illuminated fraction of the disc (0 … 1).
  double get illumination => (1 - math.cos(fraction * 2 * math.pi)) / 2;

  String get name => switch ((fraction * 8 + 0.5).floor() % 8) {
        0 => 'New moon',
        1 => 'Waxing crescent',
        2 => 'First quarter',
        3 => 'Waxing gibbous',
        4 => 'Full moon',
        5 => 'Waning gibbous',
        6 => 'Last quarter',
        _ => 'Waning crescent',
      };

  String get emoji => const ['🌑', '🌒', '🌓', '🌔', '🌕', '🌖', '🌗', '🌘'][(fraction * 8 + 0.5).floor() % 8];
}

/// Phase at an instant, from the reference new moon of 2000-01-06 18:14 UTC.
MoonPhase moonPhaseAt(int epochMs) {
  const refNewMoonMs = 947182440000; // 2000-01-06T18:14:00Z
  final days = (epochMs - refNewMoonMs) / 86400000.0;
  var age = days % MoonPhase.synodicMonth;
  if (age < 0) age += MoonPhase.synodicMonth;
  return MoonPhase(age, age / MoonPhase.synodicMonth);
}
