import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

/// Bundled holiday rules (SPEC FR-CAL-18).
void main() {
  Map<String, String> byName(List<Holiday> hs) => {for (final h in hs) h.name: h.date.iso};

  test('Easter follows the Gregorian computus', () {
    expect([for (final y in [2024, 2025, 2026, 2027, 2038]) easterSunday(y).iso], ['2024-03-31', '2025-04-20', '2026-04-05', '2027-03-28', '2038-04-25']);
  });

  test('nth and last weekdays of a month', () {
    expect(nthWeekday(2026, 11, 4, 4).iso, '2026-11-26', reason: 'Thanksgiving: 4th Thursday');
    expect(nthWeekday(2026, 5, 1, -1).iso, '2026-05-25', reason: 'Memorial Day: last Monday');
    expect(nthWeekday(2026, 9, 1, 1).iso, '2026-09-07', reason: 'Labor Day: 1st Monday');
  });

  test('US 2026: federal holidays, with weekend observed days', () {
    final us = byName(holidaysFor(2026, 'US', observances: false));
    expect(us['Martin Luther King Jr. Day'], '2026-01-19');
    expect(us['Thanksgiving'], '2026-11-26');
    // July 4, 2026 is a Saturday: offices close Friday the 3rd.
    expect((us['Independence Day'], us['Independence Day (observed)']), ('2026-07-04', '2026-07-03'));
    expect(holidaysFor(2026, 'US', observances: false).firstWhere((h) => h.name == 'Independence Day').public, isFalse);
    expect(us.containsKey('Halloween'), isFalse);
  });

  test('family observances: Mother’s and Father’s Day, Easter, Halloween', () {
    final us = byName(holidaysFor(2026, 'US'));
    expect((us['Mother’s Day'], us['Father’s Day'], us['Easter Sunday'], us['Halloween']), ('2026-05-10', '2026-06-21', '2026-04-05', '2026-10-31'));
    expect(holidaysFor(2026, 'US').where((h) => h.kidFavorite).map((h) => h.name), containsAll(['Halloween', 'Christmas Day', 'Easter Sunday']));
    // Mothering Sunday in the UK is three weeks before Easter.
    expect(byName(holidaysFor(2026, 'GB'))['Mother’s Day'], '2026-03-15');
  });

  test('UK substitutes and Canada’s Victoria Day', () {
    // Christmas 2027 is a Saturday: substitutes on Monday 27th and Tuesday 28th.
    final gb = byName(holidaysFor(2027, 'GB', observances: false));
    expect((gb['Christmas Day (substitute)'], gb['Boxing Day (substitute)']), ('2027-12-27', '2027-12-28'));
    expect(byName(holidaysFor(2026, 'CA'))['Victoria Day'], '2026-05-18', reason: 'the Monday before May 25');
  });

  test('unknown countries have no bundled holidays; lists are sorted', () {
    expect(holidaysFor(2026, 'FR'), isEmpty);
    final us = holidaysFor(2026, 'US');
    expect([for (var i = 1; i < us.length; i++) !us[i].date.isBefore(us[i - 1].date)].every((x) => x), isTrue);
  });

  test('time zones pick a default country', () {
    expect([for (final z in ['America/Denver', 'America/Indiana/Knox', 'America/Toronto', 'Europe/London', 'Europe/Paris']) holidayCountryForZone(z)], ['US', 'US', 'CA', 'GB', null]);
  });
}
