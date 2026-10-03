import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

/// Weather on events (SPEC FR-CAL-19).
void main() {
  final denver = HouseholdTime.named('America/Denver');
  const today = LocalDate(2026, 10, 3);
  final now = denver.msAt(today, 8, 30);
  int at(LocalDate d, int h, [int m = 0]) => denver.msAt(d, h, m);

  Occurrence occ(String title, {String? location, LocalDate date = today, int hour = 10, bool allDay = false, int minutes = 60}) {
    final start = allDay ? denver.startOfDayMs(date) : at(date, hour);
    final end = allDay ? denver.startOfDayMs(date.addDays(1)) : start + minutes * 60000;
    final e = Event(
      id: title,
      syncClock: '{}',
      syncHlc: '',
      syncSeq: 0,
      deleted: false,
      sourceId: 'local',
      title: title,
      startMs: start,
      endMs: end,
      allDay: allDay,
      startDate: allDay ? date.iso : null,
      endDate: allDay ? date.addDays(1).iso : null,
      exdates: '[]',
      location: location,
      countdown: false,
      reminders: '[]',
      profileIds: '[]',
      status: 'confirmed',
    );
    return Occurrence(event: e, startMs: start, endMs: end, allDay: allDay, startDate: allDay ? date : null, endDate: allDay ? date.addDays(1) : null);
  }

  final report = WeatherReport(
    fetchedMs: now,
    hourly: [
      for (var h = 8; h < 8 + 48; h++)
        WxHour(timeMs: at(today, 0) + h * 3600000, tempC: h.toDouble(), condition: h < 12 ? WxCondition.clear : WxCondition.rain, precipProb: h < 12 ? 0 : 80),
    ],
    daily: [
      for (var d = 0; d < 10; d++) WxDay(date: today.addDays(d).iso, highC: 20.0 + d, lowC: 5.0 + d, condition: WxCondition.partlyCloudy, precipProb: 10),
    ],
  );

  test('outdoor keywords match whole words and plurals, not substrings', () {
    expect(isOutdoorTitle('Soccer practice'), isTrue);
    expect(isOutdoorTitle('Picnic at the PARK'), isTrue);
    expect(isOutdoorTitle('Farmers market'), isTrue);
    expect(isOutdoorTitle('Trick-or-treat'), isTrue);
    expect(isOutdoorTitle('Hikes with Grandpa'), isTrue);
    expect(isOutdoorTitle('Parking ticket'), isFalse);
    expect(isOutdoorTitle('Dentist'), isFalse);
  });

  test('only events with a place or an outdoor keyword get weather', () {
    expect(eventForecast(report, occ('Dentist'), denver, nowMs: now), isNull);
    expect(eventForecast(report, occ('Dentist', location: 'Smile Dental'), denver, nowMs: now), isNotNull);
    expect(eventForecast(report, occ('Soccer'), denver, nowMs: now), isNotNull);
    expect(eventForecast(report, occ('Soccer', location: '  '), denver, nowMs: now), isNotNull, reason: 'the keyword still counts');
  });

  test('timed events use the hour they start; past the hourly range, the day', () {
    final f = eventForecast(report, occ('Soccer'), denver, nowMs: now)!;
    expect((f.emoji, f.tempC, f.highC, f.wet), ('☀️', 10.0, null, false));
    final rainy = eventForecast(report, occ('Soccer', hour: 15), denver, nowMs: now)!;
    expect((rainy.emoji, rainy.tempC, rainy.wet), ('🌧️', 15.0, true));
    final later = eventForecast(report, occ('Soccer', date: today.addDays(4)), denver, nowMs: now)!;
    expect((later.tempC, later.highC, later.lowC), (null, 24.0, 9.0));
  });

  test('an event under way uses the current hour', () {
    final f = eventForecast(report, occ('Hike', hour: 7, minutes: 180), denver, nowMs: now)!;
    expect(f.tempC, 8.0);
  });

  test('all-day events use the day; nothing past 7 days or already over', () {
    final f = eventForecast(report, occ('Beach day', allDay: true, date: today.addDays(2)), denver, nowMs: now)!;
    expect((f.highC, f.lowC, f.tempC), (22.0, 7.0, null));
    expect(eventForecast(report, occ('Beach day', date: today.addDays(8)), denver, nowMs: now), isNull);
    expect(eventForecast(report, occ('Soccer', hour: 6), denver, nowMs: now), isNull, reason: 'ended at 7:00');
    expect(eventForecast(null, occ('Soccer'), denver, nowMs: now), isNull);
  });
}
