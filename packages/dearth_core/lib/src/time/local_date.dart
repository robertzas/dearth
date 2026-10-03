import 'package:meta/meta.dart';

/// A calendar date without a time zone (household-local), e.g. 2026-10-02.
///
/// Stored as `YYYY-MM-DD` text. Arithmetic goes through UTC midnight so it is
/// immune to DST transitions.
@immutable
class LocalDate implements Comparable<LocalDate> {
  const LocalDate(this.year, this.month, this.day);

  factory LocalDate.fromDateTime(DateTime dt) => LocalDate(dt.year, dt.month, dt.day);

  /// Parses `YYYY-MM-DD` (extra characters after the date are ignored).
  factory LocalDate.parse(String s) {
    final v = tryParse(s);
    if (v == null) throw FormatException('Invalid date', s);
    return v;
  }

  static LocalDate? tryParse(String? s) {
    if (s == null || s.length < 10) return null;
    final y = int.tryParse(s.substring(0, 4));
    final m = int.tryParse(s.substring(5, 7));
    final d = int.tryParse(s.substring(8, 10));
    if (y == null || m == null || d == null || s[4] != '-' || s[7] != '-') return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return LocalDate(y, m, d);
  }

  final int year;
  final int month;
  final int day;

  DateTime get utcMidnight => DateTime.utc(year, month, day);

  /// ISO weekday: 1 = Monday … 7 = Sunday.
  int get weekday => utcMidnight.weekday;

  LocalDate addDays(int days) => LocalDate.fromDateTime(DateTime.utc(year, month, day + days));

  LocalDate addMonths(int months) {
    final target = DateTime.utc(year, month + months);
    final lastDay = DateTime.utc(target.year, target.month + 1, 0).day;
    return LocalDate(target.year, target.month, day > lastDay ? lastDay : day);
  }

  int daysUntil(LocalDate other) => other.utcMidnight.difference(utcMidnight).inDays;

  bool isBefore(LocalDate other) => compareTo(other) < 0;
  bool isAfter(LocalDate other) => compareTo(other) > 0;

  /// First day of the week containing this date. [weekStart] uses ISO
  /// numbering (1 = Monday, 7 = Sunday).
  LocalDate startOfWeek(int weekStart) {
    final delta = (weekday - weekStart) % 7;
    return addDays(-delta);
  }

  LocalDate get startOfMonth => LocalDate(year, month, 1);
  int get daysInMonth => DateTime.utc(year, month + 1, 0).day;

  String get iso =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  String toString() => iso;

  @override
  int compareTo(LocalDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is LocalDate && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);
}

/// Iterates dates from [start] (inclusive) to [endExclusive].
Iterable<LocalDate> dateRange(LocalDate start, LocalDate endExclusive) sync* {
  for (var d = start; d.isBefore(endExclusive); d = d.addDays(1)) {
    yield d;
  }
}
