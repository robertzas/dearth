import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'local_date.dart';

bool _tzReady = false;

/// Loads the IANA time-zone database (10-year window) once per isolate.
void ensureTimeZones() {
  if (_tzReady) return;
  tzdata.initializeTimeZones();
  _tzReady = true;
}

/// Resolves an IANA zone name, falling back to UTC for unknown names.
tz.Location locationOrUtc(String? name) {
  ensureTimeZones();
  if (name == null || name.isEmpty) return tz.UTC;
  try {
    return tz.getLocation(name);
  } on tz.LocationNotFoundException {
    return tz.UTC;
  }
}

/// Converts between UTC instants (epoch ms) and the household's wall clock.
///
/// Every rendering decision ("is this event today?") goes through this class
/// so the whole app agrees on one family time zone (SPEC §8.3).
class HouseholdTime {
  HouseholdTime(this.location, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  factory HouseholdTime.named(String? zone, {DateTime Function()? clock}) =>
      HouseholdTime(locationOrUtc(zone), clock: clock);

  final tz.Location location;
  final DateTime Function() _clock;

  String get zoneName => location.name;

  tz.TZDateTime now() => tz.TZDateTime.from(_clock(), location);
  int nowMs() => _clock().millisecondsSinceEpoch;
  LocalDate today() => LocalDate.fromDateTime(now());

  tz.TZDateTime fromMs(int ms) => tz.TZDateTime.fromMillisecondsSinceEpoch(location, ms);
  LocalDate dateOfMs(int ms) => LocalDate.fromDateTime(fromMs(ms));

  /// Epoch ms of local midnight starting [date].
  int startOfDayMs(LocalDate date) =>
      tz.TZDateTime(location, date.year, date.month, date.day).millisecondsSinceEpoch;

  /// Epoch ms of a local wall-clock time on [date].
  int msAt(LocalDate date, int hour, [int minute = 0]) =>
      tz.TZDateTime(location, date.year, date.month, date.day, hour, minute).millisecondsSinceEpoch;

  /// Minutes since local midnight for an instant.
  int minuteOfDay(int ms) {
    final t = fromMs(ms);
    return t.hour * 60 + t.minute;
  }

  /// A wall-clock DateTime (no zone) for an instant, for formatting.
  DateTime wall(int ms) {
    final t = fromMs(ms);
    return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
  }
}
