import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

void main() {
  group('conditions', () {
    test('WMO and TWC codes map to conditions', () {
      expect(conditionFromWmo(0), WxCondition.clear);
      expect(conditionFromWmo(63), WxCondition.rain);
      expect(conditionFromWmo(75), WxCondition.heavySnow);
      expect(conditionFromWmo(99), WxCondition.hail);
      expect(conditionFromWmo(1234), WxCondition.unknown);
      expect(conditionFromTwcIcon(32), WxCondition.clear);
      expect(conditionFromTwcIcon(12), WxCondition.rain);
      expect(conditionFromTwcIcon(4), WxCondition.thunderstorm);
      expect(conditionEmoji(WxCondition.clear, isDay: false), '🌙');
    });
  });

  group('FR-WX-06: rain window', () {
    WxHour h(int i, {double pp = 0, double mm = 0}) => WxHour(timeMs: i * 3600000, precipProb: pp, precipMm: mm);
    test('finds the first likely window and totals it', () {
      final w = nextRainWindow([h(0), h(1, pp: 20), h(2, pp: 60, mm: 1.2), h(3, pp: 80, mm: 3), h(4, pp: 10), h(5, pp: 90, mm: 4)])!;
      expect(w.startMs, 2 * 3600000);
      expect(w.endMs, 4 * 3600000);
      expect(w.totalMm, closeTo(4.2, 1e-9));
      expect(w.maxProb, 80);
    });
    test('dry forecast', () => expect(nextRainWindow([h(0), h(1, pp: 10)]), isNull));
  });

  group('FR-WX-07: what to wear', () {
    test('cold, wet and sunny days', () {
      expect(whatToWear(feelsLikeC: -5), containsAll([WearItem.winterCoat, WearItem.mittens]));
      expect(whatToWear(feelsLikeC: 12, precipProb: 70), containsAll([WearItem.jacket, WearItem.raincoat, WearItem.boots]));
      expect(whatToWear(feelsLikeC: 28, uvMax: 8, sunny: true),
          containsAll([WearItem.shorts, WearItem.sunhat, WearItem.sunscreen, WearItem.sunglasses]));
      expect(whatToWear(feelsLikeC: 18, precipProb: 35), contains(WearItem.umbrella));
    });
  });

  test('WeatherReport JSON round-trip', () {
    const r = WeatherReport(
      fetchedMs: 1,
      current: WxCurrent(observedMs: 1, source: 'pws:KCOAURORA1', tempC: 17.5, condition: WxCondition.clear, precipTodayMm: 0),
      hourly: [WxHour(timeMs: 10, tempC: 18, precipProb: 5, sunshineMin: 60)],
      daily: [WxDay(date: '2026-10-02', highC: 22, lowC: 7, sunshineHours: 11.5, narrative: 'Sunny.', source: 'wu')],
      alerts: [WxAlert(id: 'a1', event: 'Red Flag Warning', severity: 'Severe')],
      locationLabel: 'Aurora, CO',
      lat: 39.71,
      lon: -104.7,
      sources: {'current': 'pws:KCOAURORA1', 'hourly': 'open-meteo'},
    );
    final back = WeatherReport.tryDecode(r.encode())!;
    expect(back.toJson(), r.toJson());
    expect(back.current!.isPersonalStation, isTrue);
    expect(back.dayFor('2026-10-02')!.narrative, 'Sunny.');
    expect(back.alerts.single.severityRank, 3);
    expect(WeatherReport.tryDecode('{}'), isNull);
  });

  group('solar', () {
    final denver = HouseholdTime.named('America/Denver');
    test('Denver equinox day is ~12 h and sunset lands on the same local day', () {
      const day = LocalDate(2026, 3, 20);
      final sun = sunTimesFor(day, 39.61, -104.67, denver);
      expect(sun.polarDay || sun.polarNight, isFalse);
      expect(denver.dateOfMs(sun.sunriseMs!), day);
      expect(denver.dateOfMs(sun.sunsetMs!), day);
      final hours = sun.daylightMs! / 3600000;
      expect(hours, inInclusiveRange(11.8, 12.4));
      expect(sun.isDaylightAt(denver.msAt(day, 12)), isTrue);
      expect(sun.isDaylightAt(denver.msAt(day, 23)), isFalse);
    });
    test('midnight sun and polar night', () {
      final tromso = HouseholdTime.named('Europe/Oslo');
      expect(sunTimesFor(const LocalDate(2026, 6, 21), 69.65, 18.96, tromso).polarDay, isTrue);
      expect(sunTimesFor(const LocalDate(2026, 12, 21), 69.65, 18.96, tromso).polarNight, isTrue);
    });
  });

  test('profile palette and kid stages', () {
    expect(kProfilePalette.length, 12);
    expect(profileColor(13), kProfilePalette[1].$2);
    expect(KidStage.forAge(2.5), KidStage.little);
    expect(KidStage.forAge(3.5), KidStage.preschool);
    expect(KidStage.forAge(4.2), KidStage.prek);
  });
}
