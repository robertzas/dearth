import 'package:dearth_core/dearth_core.dart';
import 'package:intl/intl.dart';

/// Shared display formatting. Everything takes household wall-clock values
/// (from [HouseholdTime.wall]) so the whole app agrees on one family zone.

/// "7:42" (12 h, meridiem shown separately) or "19:42".
String formatClock(DateTime wall, {required bool h24}) => DateFormat(h24 ? 'H:mm' : 'h:mm').format(wall);

/// "AM" / "PM".
String formatMeridiem(DateTime wall) => DateFormat('a').format(wall);

/// "9:30 AM" / "17:30"; compact: "9:30a", "5p".
String formatTime(DateTime wall, {required bool h24, bool compact = false}) {
  if (h24) return DateFormat('H:mm').format(wall);
  if (compact) {
    final s = wall.minute == 0 ? DateFormat('h').format(wall) : DateFormat('h:mm').format(wall);
    return '$s${wall.hour < 12 ? 'a' : 'p'}';
  }
  return DateFormat('h:mm a').format(wall);
}

/// "9:00–9:45 AM", "11:30 AM–1 PM", "17:00–18:15".
String formatTimeRange(DateTime start, DateTime end, {required bool h24}) {
  if (h24) return '${DateFormat('H:mm').format(start)}–${DateFormat('H:mm').format(end)}';
  String hm(DateTime d) => d.minute == 0 ? DateFormat('h').format(d) : DateFormat('h:mm').format(d);
  final sameHalf = (start.hour < 12) == (end.hour < 12) && end.difference(start).inHours < 12;
  return sameHalf ? '${hm(start)}–${hm(end)} ${DateFormat('a').format(end)}' : '${hm(start)} ${DateFormat('a').format(start)}–${hm(end)} ${DateFormat('a').format(end)}';
}

/// Countdown text: "now", "in 5 min", "in 1 h 20 min", "in 3 h".
String formatIn(int fromMs, int toMs) {
  final minutes = ((toMs - fromMs) / 60000).ceil();
  if (minutes <= 0) return 'now';
  if (minutes < 60) return 'in $minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  if (h >= 6 || m == 0) return 'in $h h';
  return 'in $h h $m min';
}

/// Duration: "45 min", "1 h 30 min", "2 h".
String formatDuration(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// "Today", "Tomorrow", "Yesterday", else "Saturday".
String relativeDayName(LocalDate day, LocalDate today) {
  final d = today.daysUntil(day);
  if (d == 0) return 'Today';
  if (d == 1) return 'Tomorrow';
  if (d == -1) return 'Yesterday';
  return DateFormat('EEEE').format(day.utcMidnight);
}

String weekdayShort(LocalDate d) => DateFormat('EEE').format(d.utcMidnight);
String weekdayLong(LocalDate d) => DateFormat('EEEE').format(d.utcMidnight);
String monthDay(LocalDate d) => DateFormat('MMM d').format(d.utcMidnight);
String longDate(LocalDate d) => DateFormat('EEEE, MMMM d').format(d.utcMidnight);
String monthYear(LocalDate d) => DateFormat('MMMM y').format(d.utcMidnight);

/// "Sep 28 – Oct 4, 2026" or "Oct 5 – 11, 2026".
String formatDateSpan(LocalDate start, LocalDate endInclusive) {
  if (start == endInclusive) return DateFormat('EEEE, MMM d, y').format(start.utcMidnight);
  if (start.year != endInclusive.year) {
    return '${DateFormat('MMM d, y').format(start.utcMidnight)} – ${DateFormat('MMM d, y').format(endInclusive.utcMidnight)}';
  }
  if (start.month == endInclusive.month) return '${DateFormat('MMM d').format(start.utcMidnight)} – ${endInclusive.day}, ${start.year}';
  return '${DateFormat('MMM d').format(start.utcMidnight)} – ${DateFormat('MMM d').format(endInclusive.utcMidnight)}, ${start.year}';
}

/// "63°" in household units (no unit letter, the household knows).
String formatTemp(double? celsius, {required bool imperial}) =>
    celsius == null ? '–°' : '${displayTemp(celsius, imperial: imperial).round()}°';

/// Rain amount: "0.3 in", "<0.1 in", "4 mm".
String formatPrecip(double? mm, {required bool imperial}) {
  if (mm == null) return '–';
  if (imperial) {
    final inches = mm / 25.4;
    if (inches > 0 && inches < 0.05) return '<0.1 in';
    return '${inches.toStringAsFixed(inches < 1 ? 2 : 1).replaceFirst(RegExp(r'0$'), '')} in';
  }
  if (mm > 0 && mm < 0.5) return '<1 mm';
  return '${mm.round()} mm';
}

String formatWind(double? kph, {required bool imperial}) =>
    kph == null ? '–' : '${displayWind(kph, imperial: imperial).round()} ${imperial ? 'mph' : 'km/h'}';

/// "as of 7:42" for stale data (FR-WX-09).
String formatAsOf(DateTime wall, {required bool h24}) => 'as of ${formatTime(wall, h24: h24)}';

/// Friendly greeting by hour.
String greeting(int hour) => switch (hour) {
      < 5 => 'Good night',
      < 12 => 'Good morning',
      < 17 => 'Good afternoon',
      < 21 => 'Good evening',
      _ => 'Good night',
    };
