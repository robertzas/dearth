import 'dart:convert';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_integrations/dearth_integrations.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'helpers.dart';

Map<String, Object?> wuCurrent({required int epoch}) => {
      'observations': [
        {
          'stationID': 'KCOAURORA123',
          'neighborhood': 'Backyard',
          'epoch': epoch,
          'lat': 39.71,
          'lon': -104.7,
          'solarRadiation': 512.3,
          'uv': 4.0,
          'winddir': 180,
          'humidity': 31,
          'metric': {
            'temp': 18.4, 'heatIndex': 18.4, 'dewpt': 1.2, 'windChill': 18.4, 'windSpeed': 9.7, //
            'windGust': 16.1, 'pressure': 1013.2, 'precipRate': 0.0, 'precipTotal': 1.8,
          },
        },
      ],
    };

Map<String, Object?> wuForecast(LocalDate today) => {
      'validTimeLocal': [for (var i = 0; i < 5; i++) '${today.addDays(i).iso}T07:00:00-0600'],
      'calendarDayTemperatureMax': [22, 15, 12, 18, 20],
      'calendarDayTemperatureMin': [7, 6, 3, 5, 8],
      'qpf': [0, 6.4, 0.5, 0, 0],
      'narrative': ['Sunny.', 'Rain in the afternoon.', 'Cool.', 'Partly cloudy.', 'Sunny.'],
      'sunriseTimeLocal': [for (var i = 0; i < 5; i++) '${today.addDays(i).iso}T07:01:00-0600'],
      'sunsetTimeLocal': [for (var i = 0; i < 5; i++) '${today.addDays(i).iso}T18:43:00-0600'],
      'daypart': [
        {
          'iconCode': [32, 31, 12, 11, 30, 29, 30, 29, 32, 31],
          'precipChance': [null, 5, 80, 60, 20, 10, 10, 10, 0, 0],
          'uvIndex': [5, 0, 2, 0, 4, 0, 5, 0, 6, 0],
          'windSpeed': [10, 6, 25, 15, 12, 8, 10, 6, 9, 5],
        },
      ],
    };

void main() {
  test('Open-Meteo forecast parses the recorded response', () async {
    final f = fakeFetcher({path('/v1/forecast'): (_) => text(fixture('open_meteo.json'))});
    final (current, hours, days) = await OpenMeteo(f).forecast(lat: 39.71, lon: -104.7, timezone: 'America/Denver');
    expect(current.tempC, isNotNull);
    expect(current.source, 'open-meteo');
    expect(hours.length, 240);
    expect(hours.every((h) => h.sunshineMin == null || (h.sunshineMin! >= 0 && h.sunshineMin! <= 60)), isTrue);
    expect(days.length, 10);
    expect(LocalDate.tryParse(days.first.date), isNotNull);
    expect(days.first.sunshineHours, isNotNull);
    expect(days.first.sunriseMs, lessThan(days.first.sunsetMs!));
  });

  test('NWS alerts parse and sort by severity', () async {
    final f = fakeFetcher({path('/alerts/active'): (_) => text(fixture('nws_alerts.json'))});
    final alerts = await NwsClient(f).alerts(39.71, -104.7);
    final raw = jsonDecode(fixture('nws_alerts.json')) as Map<String, Object?>;
    expect(alerts.length, (raw['features']! as List).length);
    if (alerts.isNotEmpty) expect(alerts.first.event, isNotEmpty);
  });

  test('Weather Underground current conditions (metric) and 5-day forecast', () async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final today = HouseholdTime.named('America/Denver').today();
    final f = fakeFetcher({
      path('/v2/pws/observations/current'): (r) {
        expect(r.url.queryParameters['units'], 'm');
        expect(r.url.queryParameters['stationId'], 'KCOAURORA123');
        return json(wuCurrent(epoch: now));
      },
      path('/v3/wx/forecast/daily/5day'): (_) => json(wuForecast(today)),
    });
    final wu = WundergroundClient(f, 'key');
    final (cur, lat, lon) = await wu.current('KCOAURORA123');
    expect(cur.source, 'pws:KCOAURORA123');
    expect(cur.precipTodayMm, 1.8);
    expect(cur.solarWm2, 512.3);
    expect(lat, 39.71);
    expect(lon, -104.7);
    final days = await wu.forecast5(39.71, -104.7, HouseholdTime.named('America/Denver'));
    expect(days.length, 5);
    expect(days[1].condition, WxCondition.rain);
    expect(days[1].precipProb, 80);
    expect(days[1].narrative, 'Rain in the afternoon.');
    expect(days[0].condition, WxCondition.clear);
  });

  group('FR-WX-03: merge policy', () {
    test('fresh PWS wins current; WU days 1–5 merge with Open-Meteo extras; alerts from NWS', () async {
      final now = DateTime.now();
      final today = HouseholdTime.named('America/Denver').today();
      final f = fakeFetcher({
        path('/v1/forecast'): (_) => text(fixture('open_meteo.json')),
        path('/v2/pws/observations/current'): (_) => json(wuCurrent(epoch: now.millisecondsSinceEpoch ~/ 1000)),
        path('/v3/wx/forecast/daily/5day'): (_) => json(wuForecast(today)),
        path('/alerts/active'): (_) => json({'features': <Object>[]}),
      });
      final svc = WeatherService(f);
      final report = await svc.fetch(const WeatherConfig(lat: 39.71, lon: -104.7, timezone: 'America/Denver', wuApiKey: 'k', stationId: 'KCOAURORA123'));
      expect(report.current!.source, 'pws:KCOAURORA123');
      expect(report.current!.condition, isNot(WxCondition.unknown), reason: 'condition filled from Open-Meteo');
      expect(report.sources['current'], 'pws:KCOAURORA123');
      expect(report.sources['hourly'], 'open-meteo');
      expect(report.hourly, isNotEmpty);
      final wuDay = report.daily.firstWhere((d) => d.date == today.addDays(1).iso, orElse: () => report.daily.first);
      if (wuDay.date == today.addDays(1).iso) {
        expect(wuDay.narrative, 'Rain in the afternoon.');
        expect(wuDay.source, 'wunderground');
      }
      expect(report.daily.length, greaterThanOrEqualTo(5));
      expect(svc.lastErrors, isEmpty);
    });

    test('keyless mode and per-source failure keep previous data', () async {
      final f = fakeFetcher({
        path('/v1/forecast'): (_) => http.Response('boom', 500),
        path('/alerts/active'): (_) => json({'features': <Object>[]}),
        (r) => r.url.path.startsWith('/points/'): (_) => http.Response('nope', 500),
      });
      final previous = await FakeWeather().fetch(const WeatherConfig(lat: 39.71, lon: -104.7, timezone: 'America/Denver'));
      final svc = WeatherService(f);
      final report = await svc.fetch(const WeatherConfig(lat: 39.71, lon: -104.7, timezone: 'America/Denver'), previous: previous);
      expect(report.hourly, previous.hourly);
      expect(report.daily, previous.daily);
      expect(svc.lastErrors.keys, contains('open-meteo'));
    });

    test('everything failing with no previous data is an error', () async {
      final f = fakeFetcher({});
      expect(
        () => WeatherService(f).fetch(const WeatherConfig(lat: 1, lon: 1, timezone: 'UTC', countryCode: 'GB')),
        throwsA(isA<ProviderException>()),
      );
    });
  });

  test('FakeWeather is deterministic and complete', () async {
    final clock = DateTime.utc(2026, 10, 2, 18);
    final a = await FakeWeather(clock: () => clock).fetch(const WeatherConfig(lat: 39.7, lon: -104.7, timezone: 'America/Denver'));
    final b = await FakeWeather(clock: () => clock).fetch(const WeatherConfig(lat: 39.7, lon: -104.7, timezone: 'America/Denver'));
    expect(a.encode(), b.encode());
    expect(a.hourly.length, 48);
    expect(a.daily.length, 10);
    expect(a.daily[1].condition, WxCondition.rain);
    expect(nextRainWindow(a.hourly), isNotNull);
  });

  test('postal code lookup', () async {
    final f = fakeFetcher({
      path('/us/80018'): (_) => json({
            'post code': '80018',
            'places': [
              {'place name': 'Aurora', 'longitude': '-104.7', 'state': 'Colorado', 'state abbreviation': 'CO', 'latitude': '39.7'},
            ],
          }),
      path('/us/00000'): (_) => json(<String, Object?>{}, status: 404),
    });
    final p = await lookupPostalCode(f, '80018');
    expect(p!.label, 'Aurora, CO');
    expect(p.lat, 39.7);
    expect(await lookupPostalCode(f, '00000'), isNull);
  });

  test('Fetcher retries 5xx with Retry-After and gives up with a classified error', () async {
    var calls = 0;
    final f = fakeFetcher({
      path('/flaky'): (_) => ++calls < 2 ? http.Response('busy', 503, headers: {'retry-after': '1'}) : json({'ok': true}),
      path('/auth'): (_) => http.Response('no', 401),
    });
    expect(await f.getJson('t', Uri.parse('https://x.test/flaky')), {'ok': true});
    expect(calls, 2);
    try {
      await f.getJson('t', Uri.parse('https://x.test/auth'));
      fail('expected error');
    } on ProviderException catch (e) {
      expect(e.isAuth, isTrue);
      expect(e.isRetryable, isFalse);
    }
  });
}
