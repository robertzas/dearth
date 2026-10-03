import 'dart:math';

import 'package:meta/meta.dart';

import '../time/household_time.dart';
import '../time/local_date.dart';

/// Sunrise/sunset for one local day as instants (epoch ms).
@immutable
class SunTimes {
  const SunTimes({this.sunriseMs, this.sunsetMs, this.polarDay = false, this.polarNight = false});
  final int? sunriseMs;
  final int? sunsetMs;
  final bool polarDay;
  final bool polarNight;

  bool isDaylightAt(int ms) {
    if (polarDay) return true;
    if (polarNight || sunriseMs == null || sunsetMs == null) return false;
    return ms >= sunriseMs! && ms < sunsetMs!;
  }

  int? get daylightMs => sunriseMs != null && sunsetMs != null ? sunsetMs! - sunriseMs! : null;
}

double _rad(double d) => d * pi / 180;
double _deg(double r) => r * 180 / pi;
double _norm360(double d) => (d % 360 + 360) % 360;
double _norm24(double h) => (h % 24 + 24) % 24;

/// NOAA approximation (ported with test vectors from the previous editions):
/// returns UTC minutes-of-day for sunrise and sunset, or null in polar cases.
(double?, double?, bool polarDay, bool polarNight) sunMinutesUtc(LocalDate date, double lat, double lon) {
  final n = date.utcMidnight.difference(DateTime.utc(date.year)).inDays + 1;
  final lngHour = lon / 15;

  double? calc(bool sunrise) {
    final t = n + ((sunrise ? 6 : 18) - lngHour) / 24;
    final m = 0.9856 * t - 3.289;
    final l = _norm360(m + 1.916 * sin(_rad(m)) + 0.02 * sin(_rad(2 * m)) + 282.634);
    var ra = _deg(atan(0.91764 * tan(_rad(l))));
    ra += ((l / 90).floor() - (ra / 90).floor()) * 90; // floor(), not ~/ (negative RA)
    ra /= 15;
    final sinDec = 0.39782 * sin(_rad(l));
    final cosDec = cos(asin(sinDec));
    final cosH = (cos(_rad(90.833)) - sinDec * sin(_rad(lat))) / (cosDec * cos(_rad(lat)));
    if (cosH > 1 || cosH < -1) return null;
    var h = sunrise ? 360 - _deg(acos(cosH)) : _deg(acos(cosH));
    h /= 15;
    final tt = h + ra - 0.06571 * t - 6.622;
    return _norm24(tt - lngHour) * 60;
  }

  final rise = calc(true);
  final set = calc(false);
  if (rise == null || set == null) {
    final dec = 23.44 * sin(_rad((360 / 365) * (n - 81)));
    final polarDay = lat * dec > 0;
    return (null, null, polarDay, !polarDay);
  }
  return (rise, set, false, false);
}

/// Sunrise and sunset of [date] at (lat, lon) as instants, placed on the
/// correct local day (west of Greenwich the UTC sunset is "tomorrow").
SunTimes sunTimesFor(LocalDate date, double lat, double lon, HouseholdTime time) {
  final (rise, set, polarDay, polarNight) = sunMinutesUtc(date, lat, lon);
  if (rise == null || set == null) return SunTimes(polarDay: polarDay, polarNight: polarNight);
  final noonMs = time.msAt(date, 12);
  final offsetMin = time.fromMs(noonMs).timeZoneOffset.inMinutes;
  int toLocalMs(double utcMinutes) {
    final local = ((utcMinutes + offsetMin) % 1440 + 1440) % 1440;
    return time.msAt(date, local ~/ 60, (local % 60).round().clamp(0, 59));
  }

  return SunTimes(sunriseMs: toLocalMs(rise), sunsetMs: toLocalMs(set));
}
