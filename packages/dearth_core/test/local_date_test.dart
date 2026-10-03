import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

void main() {
  test('parse/format', () {
    expect(LocalDate.parse('2026-10-02').iso, '2026-10-02');
    expect(LocalDate.tryParse('2026-13-02'), isNull);
    expect(LocalDate.tryParse('garbage'), isNull);
  });

  test('day arithmetic crosses month, year and DST boundaries', () {
    expect(const LocalDate(2026, 1, 31).addDays(1), const LocalDate(2026, 2, 1));
    expect(const LocalDate(2026, 12, 31).addDays(1), const LocalDate(2027, 1, 1));
    // US DST ends 2026-11-01: a plain date add must not drift.
    expect(const LocalDate(2026, 10, 31).addDays(2), const LocalDate(2026, 11, 2));
    expect(const LocalDate(2026, 3, 1).daysUntil(const LocalDate(2026, 3, 31)), 30);
  });

  test('addMonths clamps to the last day', () {
    expect(const LocalDate(2026, 1, 31).addMonths(1), const LocalDate(2026, 2, 28));
    expect(const LocalDate(2028, 1, 31).addMonths(1), const LocalDate(2028, 2, 29));
  });

  test('startOfWeek for Sunday- and Monday-start weeks', () {
    const fri = LocalDate(2026, 10, 2); // a Friday
    expect(fri.weekday, 5);
    expect(fri.startOfWeek(7), const LocalDate(2026, 9, 27)); // Sunday
    expect(fri.startOfWeek(1), const LocalDate(2026, 9, 28)); // Monday
    expect(const LocalDate(2026, 9, 27).startOfWeek(7), const LocalDate(2026, 9, 27));
  });

  test('HouseholdTime maps instants to local dates in the family zone', () {
    final denver = HouseholdTime.named('America/Denver');
    // 2026-10-03T05:30Z is still Oct 2 in Denver (UTC-6).
    final ms = DateTime.utc(2026, 10, 3, 5, 30).millisecondsSinceEpoch;
    expect(denver.dateOfMs(ms), const LocalDate(2026, 10, 2));
    expect(denver.minuteOfDay(ms), 23 * 60 + 30);
    // Local midnight round trip, including the DST-change day.
    final nov1 = denver.startOfDayMs(const LocalDate(2026, 11, 1));
    expect(denver.dateOfMs(nov1), const LocalDate(2026, 11, 1));
    expect(denver.startOfDayMs(const LocalDate(2026, 11, 2)) - nov1, 25 * 3600 * 1000);
    expect(HouseholdTime.named('Not/AZone').zoneName, anyOf('UTC', 'Etc/UTC'));
  });
}
