import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:meta/meta.dart';

import '../http/fetcher.dart';
import 'weather_providers.dart';

/// Where and how to fetch weather (household + secrets, assembled by the Hub).
@immutable
class WeatherConfig {
  const WeatherConfig({
    required this.lat,
    required this.lon,
    required this.timezone,
    this.label,
    this.countryCode = 'US',
    this.wuApiKey,
    this.stationId,
    this.useWuForecast = true,
  });

  final double lat;
  final double lon;
  final String timezone;
  final String? label;
  final String countryCode;
  final String? wuApiKey;
  final String? stationId;
  final bool useWuForecast;

  bool get hasStation => (wuApiKey?.isNotEmpty ?? false) && (stationId?.isNotEmpty ?? false);
  bool get isUs => countryCode.toUpperCase() == 'US';
}

/// Anything that can produce a merged report (real or fake).
abstract interface class WeatherSource {
  Future<WeatherReport> fetch(WeatherConfig config, {WeatherReport? previous});
}

/// Merges Weather Underground, Open-Meteo and NWS per SPEC FR-WX-03. Each
/// source fails independently; a failed section keeps the previous report's
/// data so displays never go blank (FR-WX-09).
class WeatherService implements WeatherSource {
  WeatherService(this.fetcher, {this.contact = 'dearth-hub', DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final Fetcher fetcher;
  final String contact;
  final DateTime Function() _clock;

  /// Errors from the last fetch, by source (for the integration health page).
  final Map<String, String> lastErrors = {};

  @override
  Future<WeatherReport> fetch(WeatherConfig config, {WeatherReport? previous}) async {
    lastErrors.clear();
    final nowMs = _clock().millisecondsSinceEpoch;
    final time = HouseholdTime.named(config.timezone);
    Future<T?> guard<T>(String name, Future<T> Function() run) async {
      try {
        return await run();
      } on Object catch (e) {
        lastErrors[name] = '$e';
        return null;
      }
    }

    final wu = config.hasStation ? WundergroundClient(fetcher, config.wuApiKey!) : null;
    final nws = config.isUs ? NwsClient(fetcher, contact: contact) : null;
    final results = await (
      guard('open-meteo', () => OpenMeteo(fetcher).forecast(lat: config.lat, lon: config.lon, timezone: config.timezone)),
      wu == null ? Future<(WxCurrent, double, double)?>.value() : guard('wunderground', () => wu.current(config.stationId!)),
      wu == null || !config.useWuForecast ? Future<List<WxDay>?>.value() : guard('wunderground-forecast', () => wu.forecast5(config.lat, config.lon, time)),
      nws == null ? Future<List<WxAlert>?>.value() : guard('nws-alerts', () => nws.alerts(config.lat, config.lon)),
    ).wait;
    final (om, pws, wuDays, alerts) = results;

    WxCurrent? nwsObs;
    final pwsFresh = pws != null && nowMs - pws.$1.observedMs <= 15 * 60 * 1000;
    if (!pwsFresh && nws != null) {
      nwsObs = await guard<WxCurrent?>('nws-observation', () => nws.latestObservation(config.lat, config.lon));
      if (nwsObs != null && nowMs - nwsObs.observedMs > 90 * 60 * 1000) nwsObs = null;
    }

    final sources = <String, String>{};
    WxCurrent? current;
    final omCurrent = om?.$1;
    if (pwsFresh) {
      current = omCurrent == null ? pws.$1 : pws.$1.fillFrom(omCurrent);
    } else if (nwsObs != null) {
      current = omCurrent == null ? nwsObs : nwsObs.fillFrom(omCurrent);
    } else {
      current = omCurrent ?? previous?.current;
    }
    if (current != null) sources['current'] = current.source;

    final hourly = om?.$2 ?? previous?.hourly ?? const [];
    if (om != null) sources['hourly'] = OpenMeteo.provider;

    var daily = om?.$3 ?? previous?.daily ?? const <WxDay>[];
    if (wuDays != null && wuDays.isNotEmpty) {
      final byDate = {for (final d in daily) d.date: d};
      final merged = <WxDay>[];
      for (final w in wuDays) {
        final o = byDate.remove(w.date);
        merged.add(WxDay(
          date: w.date,
          highC: w.highC ?? o?.highC,
          lowC: w.lowC ?? o?.lowC,
          condition: w.condition == WxCondition.unknown ? (o?.condition ?? WxCondition.unknown) : w.condition,
          precipProb: w.precipProb ?? o?.precipProb,
          precipMm: w.precipMm ?? o?.precipMm,
          precipHours: o?.precipHours,
          sunshineHours: o?.sunshineHours,
          daylightHours: o?.daylightHours,
          uvMax: w.uvMax ?? o?.uvMax,
          windMaxKph: math.max(w.windMaxKph ?? 0, o?.windMaxKph ?? 0),
          sunriseMs: w.sunriseMs ?? o?.sunriseMs,
          sunsetMs: w.sunsetMs ?? o?.sunsetMs,
          narrative: w.narrative,
          source: WundergroundClient.provider,
        ));
      }
      daily = [...merged, ...byDate.values]..sort((a, b) => a.date.compareTo(b.date));
      sources['daily'] = 'wunderground+open-meteo';
    } else if (om != null) {
      sources['daily'] = OpenMeteo.provider;
    }

    final activeAlerts = (alerts ?? previous?.alerts ?? const <WxAlert>[])
        .where((a) => a.endsMs == null || a.endsMs! > nowMs)
        .toList();
    if (alerts != null) sources['alerts'] = NwsClient.provider;

    if (om == null && pws == null && previous == null) {
      throw ProviderException('weather', 'All weather sources failed: ${lastErrors.values.join('; ')}');
    }
    return WeatherReport(
      fetchedMs: nowMs,
      current: current,
      hourly: hourly,
      daily: daily,
      alerts: activeAlerts,
      locationLabel: config.label ?? previous?.locationLabel,
      lat: config.lat,
      lon: config.lon,
      sources: sources,
    );
  }
}

/// Deterministic weather for demos and E2E tests (`DEARTH_FAKE_PROVIDERS`).
/// Today is sunny; tomorrow afternoon brings rain; the weekend is cool.
class FakeWeather implements WeatherSource {
  FakeWeather({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;

  @override
  Future<WeatherReport> fetch(WeatherConfig config, {WeatherReport? previous}) async {
    final time = HouseholdTime.named(config.timezone, clock: _clock);
    final now = time.nowMs();
    final today = time.today();
    final hourStart = now - now % 3600000;
    final hours = <WxHour>[];
    for (var i = 0; i < 48; i++) {
      final t = hourStart + i * 3600000;
      final local = time.fromMs(t);
      final day = time.dateOfMs(t);
      final isDay = local.hour >= 7 && local.hour < 19;
      final rainy = day == today.addDays(1) && local.hour >= 15 && local.hour < 19;
      final temp = 12 + 9 * math.sin((local.hour - 9) / 24 * 2 * math.pi) - (day == today ? 0 : 2);
      hours.add(WxHour(
        timeMs: t,
        tempC: double.parse(temp.toStringAsFixed(1)),
        precipProb: rainy ? 80 : 5,
        precipMm: rainy ? 2.5 : 0,
        cloudPct: rainy ? 95 : (isDay ? 15 : 10),
        sunshineMin: rainy || !isDay ? 0 : 55,
        uvIndex: isDay ? (local.hour >= 11 && local.hour <= 15 ? 5 : 2) : 0,
        condition: rainy ? WxCondition.rain : (isDay ? WxCondition.clear : WxCondition.mostlyClear),
        isDay: isDay,
        windKph: rainy ? 22 : 9,
        gustKph: rainy ? 40 : 15,
      ));
    }
    final days = <WxDay>[
      for (var i = 0; i < 10; i++)
        () {
          final d = today.addDays(i);
          final rainy = i == 1;
          final cool = i >= 2 && i <= 3;
          final sun = sunTimesFor(d, config.lat, config.lon, time);
          return WxDay(
            date: d.iso,
            highC: rainy ? 14 : (cool ? 11 : 21),
            lowC: rainy ? 6 : (cool ? 2 : 7),
            condition: rainy ? WxCondition.rain : (cool ? WxCondition.partlyCloudy : WxCondition.clear),
            precipProb: rainy ? 80 : (cool ? 20 : 5),
            precipMm: rainy ? 8 : 0,
            precipHours: rainy ? 4 : 0,
            sunshineHours: rainy ? 2.5 : (cool ? 7 : 10.5),
            daylightHours: sun.daylightMs == null ? 11.5 : sun.daylightMs! / 3600000,
            uvMax: rainy ? 2 : 5,
            windMaxKph: rainy ? 35 : 15,
            sunriseMs: sun.sunriseMs,
            sunsetMs: sun.sunsetMs,
            narrative: rainy ? 'Rain likely in the afternoon. High 14°C.' : 'Sunshine. High ${cool ? 11 : 21}°C.',
            source: 'fake',
          );
        }(),
    ];
    return WeatherReport(
      fetchedMs: now,
      current: WxCurrent(
        observedMs: now,
        source: 'pws:KFAKE123',
        tempC: hours.first.tempC,
        feelsLikeC: (hours.first.tempC ?? 15) - 1,
        condition: hours.first.condition,
        isDay: hours.first.isDay,
        windKph: 9,
        gustKph: 15,
        humidity: 35,
        precipTodayMm: 0,
        uvIndex: hours.first.uvIndex,
        solarWm2: hours.first.isDay ? 520 : 0,
        stationName: 'Backyard (demo)',
      ),
      hourly: hours,
      daily: days,
      locationLabel: config.label ?? 'Demo City',
      lat: config.lat,
      lon: config.lon,
      sources: const {'current': 'pws:KFAKE123', 'hourly': 'fake', 'daily': 'fake'},
    );
  }
}
