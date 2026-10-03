import 'package:meta/meta.dart';

import '../time/local_date.dart';

/// A public holiday or a family observance on a date (SPEC FR-CAL-18).
@immutable
class Holiday {
  const Holiday(this.date, this.name, this.emoji, {this.public = false, this.kidFavorite = false});
  final LocalDate date;
  final String name;
  final String emoji;

  /// Offices and usually schools close (the observed day for weekend dates).
  final bool public;

  /// Worth a "sleeps until" countdown for kids.
  final bool kidFavorite;

  @override
  bool operator ==(Object other) => other is Holiday && other.date == date && other.name == name;
  @override
  int get hashCode => Object.hash(date, name);
  @override
  String toString() => 'Holiday(${date.iso} $name)';
}

/// Countries with bundled rules. Others can subscribe to an ICS holiday
/// calendar (or, later, the Hub's Nager.Date source).
const Map<String, String> kHolidayCountries = {'US': 'United States', 'CA': 'Canada', 'GB': 'United Kingdom'};

/// The bundled holiday country for an IANA time zone (the default until a
/// household picks one), or null.
String? holidayCountryForZone(String zone) {
  if (zone == 'Europe/London' || zone == 'Europe/Belfast') return 'GB';
  const canada = {
    'America/Toronto', 'America/Montreal', 'America/Vancouver', 'America/Edmonton', 'America/Winnipeg', 'America/Regina', //
    'America/Halifax', 'America/St_Johns', 'America/Moncton', 'America/Whitehorse', 'America/Yellowknife', 'America/Iqaluit',
  };
  if (canada.contains(zone)) return 'CA';
  const us = {
    'America/New_York', 'America/Chicago', 'America/Denver', 'America/Phoenix', 'America/Los_Angeles', 'America/Anchorage', //
    'America/Juneau', 'America/Detroit', 'America/Boise', 'America/Adak', 'America/Menominee', 'America/Nome', 'Pacific/Honolulu',
  };
  if (us.contains(zone) || zone.startsWith('America/Indiana/') || zone.startsWith('America/Kentucky/') || zone.startsWith('America/North_Dakota/')) return 'US';
  return null;
}

/// Holidays in [year] for [country] (ISO 3166-1 alpha-2), sorted by date:
/// public holidays (with weekend observed days) and, if [observances],
/// the family days kids look forward to.
List<Holiday> holidaysFor(int year, String country, {bool observances = true}) {
  final out = <Holiday>[
    ...switch (country) {
      'US' => _us(year),
      'CA' => _ca(year),
      'GB' => _gb(year),
      _ => const <Holiday>[],
    },
    if (observances && kHolidayCountries.containsKey(country)) ..._observances(year, country),
  ]..sort((a, b) => a.date.compareTo(b.date));
  return out;
}

/// The [n]th [weekday] (1 = Monday … 7 = Sunday) of [month]; n = -1 is the
/// last one.
LocalDate nthWeekday(int year, int month, int weekday, int n) {
  if (n < 0) {
    var d = LocalDate(year, month, 1).addMonths(1).addDays(-1);
    while (d.weekday != weekday) {
      d = d.addDays(-1);
    }
    return d;
  }
  var d = LocalDate(year, month, 1);
  while (d.weekday != weekday) {
    d = d.addDays(1);
  }
  return d.addDays(7 * (n - 1));
}

/// Western (Gregorian) Easter Sunday: the anonymous Gregorian computus.
LocalDate easterSunday(int year) {
  final a = year % 19, b = year ~/ 100, c = year % 100, d = b ~/ 4, e = b % 4;
  final f = (b + 8) ~/ 25, g = (b - f + 1) ~/ 3, h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7, m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31, day = (h + l - 7 * m + 114) % 31 + 1;
  return LocalDate(year, month, day);
}

/// A fixed-date public holiday, plus its weekday "observed" day when it
/// falls on a weekend (US rule: Saturday → Friday, Sunday → Monday).
List<Holiday> _fixedUs(LocalDate d, String name, String emoji, {bool kidFavorite = false}) => [
      Holiday(d, name, emoji, public: d.weekday < 6, kidFavorite: kidFavorite),
      if (d.weekday == 6) Holiday(d.addDays(-1), '$name (observed)', emoji, public: true),
      if (d.weekday == 7) Holiday(d.addDays(1), '$name (observed)', emoji, public: true),
    ];

List<Holiday> _us(int y) => [
      ..._fixedUs(LocalDate(y, 1, 1), 'New Year’s Day', '🎆'),
      Holiday(nthWeekday(y, 1, 1, 3), 'Martin Luther King Jr. Day', '✊', public: true),
      Holiday(nthWeekday(y, 2, 1, 3), 'Presidents’ Day', '🇺🇸', public: true),
      Holiday(nthWeekday(y, 5, 1, -1), 'Memorial Day', '🇺🇸', public: true),
      ..._fixedUs(LocalDate(y, 6, 19), 'Juneteenth', '✊🏿'),
      ..._fixedUs(LocalDate(y, 7, 4), 'Independence Day', '🎆'),
      Holiday(nthWeekday(y, 9, 1, 1), 'Labor Day', '🛠️', public: true),
      Holiday(nthWeekday(y, 10, 1, 2), 'Indigenous Peoples’ Day', '🪶', public: true),
      ..._fixedUs(LocalDate(y, 11, 11), 'Veterans Day', '🎖️'),
      Holiday(nthWeekday(y, 11, 4, 4), 'Thanksgiving', '🦃', public: true, kidFavorite: true),
      ..._fixedUs(LocalDate(y, 12, 25), 'Christmas Day', '🎄', kidFavorite: true),
    ];

List<Holiday> _ca(int y) {
  final easter = easterSunday(y);
  var victoria = LocalDate(y, 5, 24);
  while (victoria.weekday != 1) {
    victoria = victoria.addDays(-1);
  }
  return [
    Holiday(LocalDate(y, 1, 1), 'New Year’s Day', '🎆', public: true),
    Holiday(easter.addDays(-2), 'Good Friday', '✝️', public: true),
    Holiday(victoria, 'Victoria Day', '👑', public: true),
    Holiday(LocalDate(y, 7, 1), 'Canada Day', '🇨🇦', public: true),
    Holiday(nthWeekday(y, 9, 1, 1), 'Labour Day', '🛠️', public: true),
    Holiday(LocalDate(y, 9, 30), 'National Day for Truth and Reconciliation', '🧡', public: true),
    Holiday(nthWeekday(y, 10, 1, 2), 'Thanksgiving', '🦃', public: true, kidFavorite: true),
    Holiday(LocalDate(y, 11, 11), 'Remembrance Day', '🌺', public: true),
    Holiday(LocalDate(y, 12, 25), 'Christmas Day', '🎄', public: true, kidFavorite: true),
    Holiday(LocalDate(y, 12, 26), 'Boxing Day', '🎁', public: true),
  ];
}

/// England and Wales bank holidays, with substitute days.
List<Holiday> _gb(int y) {
  final easter = easterSunday(y);
  LocalDate weekdayOnOrAfter(LocalDate d) => d.weekday == 6 ? d.addDays(2) : (d.weekday == 7 ? d.addDays(1) : d);
  final newYear = weekdayOnOrAfter(LocalDate(y, 1, 1));
  final christmas = weekdayOnOrAfter(LocalDate(y, 12, 25));
  var boxing = weekdayOnOrAfter(LocalDate(y, 12, 26));
  if (boxing == christmas) boxing = boxing.addDays(1);
  return [
    Holiday(newYear, newYear.day == 1 ? 'New Year’s Day' : 'New Year’s Day (substitute)', '🎆', public: true),
    Holiday(easter.addDays(-2), 'Good Friday', '✝️', public: true),
    Holiday(easter.addDays(1), 'Easter Monday', '🐣', public: true),
    Holiday(nthWeekday(y, 5, 1, 1), 'Early May bank holiday', '🌸', public: true),
    Holiday(nthWeekday(y, 5, 1, -1), 'Spring bank holiday', '🌷', public: true),
    Holiday(nthWeekday(y, 8, 1, -1), 'Summer bank holiday', '☀️', public: true),
    if (christmas.day != 25) Holiday(LocalDate(y, 12, 25), 'Christmas Day', '🎄', kidFavorite: true),
    Holiday(christmas, christmas.day == 25 ? 'Christmas Day' : 'Christmas Day (substitute)', '🎄', public: true, kidFavorite: christmas.day == 25),
    if (boxing.day != 26) Holiday(LocalDate(y, 12, 26), 'Boxing Day', '🎁'),
    Holiday(boxing, boxing.day == 26 ? 'Boxing Day' : 'Boxing Day (substitute)', '🎁', public: true),
  ];
}

List<Holiday> _observances(int y, String country) {
  final easter = easterSunday(y);
  return [
    Holiday(LocalDate(y, 2, 14), 'Valentine’s Day', '❤️'),
    if (country != 'GB') Holiday(LocalDate(y, 3, 17), 'St. Patrick’s Day', '☘️'),
    // GB's Mothering Sunday is three weeks before Easter.
    if (country == 'GB') Holiday(easter.addDays(-21), 'Mother’s Day', '💐') else Holiday(nthWeekday(y, 5, 7, 2), 'Mother’s Day', '💐'),
    Holiday(easter, 'Easter Sunday', '🐣', kidFavorite: true),
    Holiday(nthWeekday(y, 6, 7, 3), 'Father’s Day', '👔'),
    Holiday(LocalDate(y, 10, 31), 'Halloween', '🎃', kidFavorite: true),
    Holiday(LocalDate(y, 12, 24), 'Christmas Eve', '🎄'),
    Holiday(LocalDate(y, 12, 31), 'New Year’s Eve', '🥳'),
  ];
}
