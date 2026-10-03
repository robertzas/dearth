import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';

import '../http/fetcher.dart';

/// A geocoded place.
class Place {
  const Place({required this.lat, required this.lon, required this.label, this.timezone, this.postalCode, this.countryCode});
  final double lat;
  final double lon;
  final String label;
  final String? timezone;
  final String? postalCode;
  final String? countryCode;
}

// ─────────────────────────────── Open-Meteo ────────────────────────────────

/// Open-Meteo: keyless current, hourly and 10-day forecast (SPEC §13.4).
class OpenMeteo {
  OpenMeteo(this.fetcher, {Uri? base}) : base = base ?? Uri.parse('https://api.open-meteo.com');
  final Fetcher fetcher;
  final Uri base;
  static const provider = 'open-meteo';

  Future<(WxCurrent, List<WxHour>, List<WxDay>)> forecast({
    required double lat,
    required double lon,
    required String timezone,
    int days = 10,
  }) async {
    final uri = base.replace(path: '/v1/forecast', queryParameters: {
      'latitude': lat.toStringAsFixed(4),
      'longitude': lon.toStringAsFixed(4),
      'timezone': timezone,
      'forecast_days': '$days',
      'timeformat': 'unixtime',
      'current': 'temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,wind_gusts_10m,'
          'wind_direction_10m,relative_humidity_2m,surface_pressure,precipitation',
      'hourly': 'temperature_2m,precipitation_probability,precipitation,cloud_cover,sunshine_duration,'
          'uv_index,weather_code,is_day,wind_speed_10m,wind_gusts_10m',
      'daily': 'temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,'
          'precipitation_hours,sunshine_duration,daylight_duration,uv_index_max,sunrise,sunset,weather_code,'
          'wind_speed_10m_max',
    });
    final j = asObject(await fetcher.getJson(provider, uri), provider);
    final offsetS = (j['utc_offset_seconds'] as num?)?.toInt() ?? 0;

    final c = j.obj('current');
    final current = WxCurrent(
      observedMs: ((c['time'] as num?)?.toInt() ?? 0) * 1000,
      source: provider,
      tempC: c.number('temperature_2m'),
      feelsLikeC: c.number('apparent_temperature'),
      condition: conditionFromWmo(c.integer('weather_code')),
      isDay: (c.integer('is_day') ?? 1) == 1,
      windKph: c.number('wind_speed_10m'),
      gustKph: c.number('wind_gusts_10m'),
      windDirDeg: c.number('wind_direction_10m'),
      humidity: c.number('relative_humidity_2m'),
      pressureHpa: c.number('surface_pressure'),
      precipRateMmH: c.number('precipitation'),
    );

    final h = j.obj('hourly');
    final times = h.arr('time');
    double? at(String key, int i) {
      final list = h.arr(key);
      return i < list.length && list[i] is num ? (list[i]! as num).toDouble() : null;
    }

    final hours = <WxHour>[
      for (var i = 0; i < times.length; i++)
        WxHour(
          timeMs: ((times[i] as num?)?.toInt() ?? 0) * 1000,
          tempC: at('temperature_2m', i),
          precipProb: at('precipitation_probability', i),
          precipMm: at('precipitation', i),
          cloudPct: at('cloud_cover', i),
          sunshineMin: at('sunshine_duration', i) == null ? null : at('sunshine_duration', i)! / 60,
          uvIndex: at('uv_index', i),
          condition: conditionFromWmo(at('weather_code', i)?.toInt()),
          isDay: (at('is_day', i) ?? 1) == 1,
          windKph: at('wind_speed_10m', i),
          gustKph: at('wind_gusts_10m', i),
        ),
    ];

    final d = j.obj('daily');
    final dTimes = d.arr('time');
    double? dat(String key, int i) {
      final list = d.arr(key);
      return i < list.length && list[i] is num ? (list[i]! as num).toDouble() : null;
    }

    final daysOut = <WxDay>[
      for (var i = 0; i < dTimes.length; i++)
        WxDay(
          // Daily unixtime marks local midnight; shift by the zone offset.
          date: LocalDate.fromDateTime(
            DateTime.fromMillisecondsSinceEpoch((((dTimes[i] as num?)?.toInt() ?? 0) + offsetS) * 1000, isUtc: true),
          ).iso,
          highC: dat('temperature_2m_max', i),
          lowC: dat('temperature_2m_min', i),
          condition: conditionFromWmo(dat('weather_code', i)?.toInt()),
          precipProb: dat('precipitation_probability_max', i),
          precipMm: dat('precipitation_sum', i),
          precipHours: dat('precipitation_hours', i),
          sunshineHours: dat('sunshine_duration', i) == null ? null : dat('sunshine_duration', i)! / 3600,
          daylightHours: dat('daylight_duration', i) == null ? null : dat('daylight_duration', i)! / 3600,
          uvMax: dat('uv_index_max', i),
          windMaxKph: dat('wind_speed_10m_max', i),
          sunriseMs: dat('sunrise', i) == null ? null : dat('sunrise', i)!.toInt() * 1000,
          sunsetMs: dat('sunset', i) == null ? null : dat('sunset', i)!.toInt() * 1000,
        ),
    ];
    return (current, hours, daysOut);
  }

  /// IANA time zone for a point (`timezone=auto`).
  Future<String?> timezoneFor(double lat, double lon) async {
    final uri = base.replace(path: '/v1/forecast', queryParameters: {
      'latitude': lat.toStringAsFixed(4),
      'longitude': lon.toStringAsFixed(4),
      'timezone': 'auto',
      'forecast_days': '1',
      'current': 'temperature_2m',
    });
    final j = asObject(await fetcher.getJson(provider, uri), provider);
    return j['timezone'] as String?;
  }

  /// City/place name search (Open-Meteo geocoding).
  Future<List<Place>> searchPlaces(String name, {int count = 5}) async {
    final uri = Uri.parse('https://geocoding-api.open-meteo.com/v1/search').replace(
      queryParameters: {'name': name, 'count': '$count', 'language': 'en', 'format': 'json'},
    );
    final j = asObject(await fetcher.getJson(provider, uri), provider);
    return [
      for (final r in j.arr('results'))
        if (r is Map<String, Object?>)
          Place(
            lat: r.number('latitude') ?? 0,
            lon: r.number('longitude') ?? 0,
            label: [r.str('name'), r.str('admin1'), r.str('country_code')].whereType<String>().join(', '),
            timezone: r.str('timezone'),
            countryCode: r.str('country_code'),
          ),
    ];
  }
}

/// US/CA postal code lookup (Open-Meteo's name geocoder misses ZIPs).
Future<Place?> lookupPostalCode(Fetcher fetcher, String code, {String country = 'us'}) async {
  final uri = Uri.parse('https://api.zippopotam.us/${country.toLowerCase()}/${Uri.encodeComponent(code.trim())}');
  try {
    final j = asObject(await fetcher.getJson('zippopotam', uri), 'zippopotam');
    final places = j.arr('places');
    if (places.isEmpty) return null;
    final p = places.first! as Map<String, Object?>;
    return Place(
      lat: p.number('latitude') ?? 0,
      lon: p.number('longitude') ?? 0,
      label: '${p.str('place name')}, ${p.str('state abbreviation') ?? p.str('state')}',
      postalCode: code.trim(),
      countryCode: country.toUpperCase(),
    );
  } on ProviderException catch (e) {
    if (e.isNotFound) return null;
    rethrow;
  }
}

// ─────────────────────────────────── NWS ───────────────────────────────────

/// US National Weather Service: alerts and official observations.
class NwsClient {
  NwsClient(this.fetcher, {this.contact = 'dearth-hub'});
  final Fetcher fetcher;
  final String contact;
  static const provider = 'nws';

  Map<String, String> get _headers => {'Accept': 'application/geo+json', 'User-Agent': 'Dearth weather ($contact)'};

  Future<List<WxAlert>> alerts(double lat, double lon) async {
    final uri = Uri.parse('https://api.weather.gov/alerts/active').replace(queryParameters: {'point': '${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}'});
    final j = asObject(await fetcher.getJson(provider, uri, headers: _headers), provider);
    int? ms(String? iso) => iso == null ? null : DateTime.tryParse(iso)?.millisecondsSinceEpoch;
    return [
      for (final f in j.arr('features'))
        if (f is Map<String, Object?>)
          () {
            final p = f.obj('properties');
            return WxAlert(
              id: p.str('id') ?? f.str('id') ?? '',
              event: p.str('event') ?? 'Weather alert',
              severity: p.str('severity') ?? 'Unknown',
              headline: p.str('headline'),
              description: p.str('description'),
              instruction: p.str('instruction'),
              startsMs: ms(p.str('onset') ?? p.str('effective')),
              endsMs: ms(p.str('ends') ?? p.str('expires')),
              sender: p.str('senderName'),
            );
          }(),
    ]..sort((a, b) => b.severityRank.compareTo(a.severityRank));
  }

  /// Latest observation from the nearest official station.
  Future<WxCurrent?> latestObservation(double lat, double lon) async {
    final point = asObject(
      await fetcher.getJson(provider, Uri.parse('https://api.weather.gov/points/${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}'), headers: _headers),
      provider,
    );
    final stationsUrl = point.obj('properties').str('observationStations');
    if (stationsUrl == null) return null;
    final stations = asObject(await fetcher.getJson(provider, Uri.parse(stationsUrl), headers: _headers), provider);
    final features = stations.arr('features');
    if (features.isEmpty) return null;
    final stationId = (features.first! as Map<String, Object?>).obj('properties').str('stationIdentifier');
    if (stationId == null) return null;
    final obs = asObject(
      await fetcher.getJson(provider, Uri.parse('https://api.weather.gov/stations/$stationId/observations/latest'), headers: _headers),
      provider,
    ).obj('properties');
    double? v(String key) => obs.obj(key).number('value');
    final pressurePa = v('barometricPressure');
    return WxCurrent(
      observedMs: DateTime.tryParse(obs.str('timestamp') ?? '')?.millisecondsSinceEpoch ?? 0,
      source: 'nws:$stationId',
      tempC: v('temperature'),
      feelsLikeC: v('heatIndex') ?? v('windChill'),
      windKph: v('windSpeed'),
      gustKph: v('windGust'),
      windDirDeg: v('windDirection'),
      humidity: v('relativeHumidity'),
      dewpointC: v('dewpoint'),
      pressureHpa: pressurePa == null ? null : pressurePa / 100,
      stationName: stationId,
    );
  }
}

// ──────────────────────────── Weather Underground ──────────────────────────

/// Weather Underground PWS API (key holders only; SPEC §13.4).
class WundergroundClient {
  WundergroundClient(this.fetcher, this.apiKey, {Uri? base}) : base = base ?? Uri.parse('https://api.weather.com');
  final Fetcher fetcher;
  final String apiKey;
  final Uri base;
  static const provider = 'wunderground';

  /// Current conditions from a personal weather station (metric units).
  Future<(WxCurrent, double lat, double lon)> current(String stationId) async {
    final uri = base.replace(path: '/v2/pws/observations/current', queryParameters: {
      'stationId': stationId,
      'format': 'json',
      'units': 'm',
      'numericPrecision': 'decimal',
      'apiKey': apiKey,
    });
    final j = asObject(await fetcher.getJson(provider, uri), provider);
    final obsList = j.arr('observations');
    if (obsList.isEmpty) throw ProviderException(provider, 'Station $stationId returned no observations');
    final o = obsList.first! as Map<String, Object?>;
    final m = o.obj('metric');
    final temp = m.number('temp');
    final heat = m.number('heatIndex');
    final chill = m.number('windChill');
    final feels = temp == null ? null : (heat != null && heat > temp ? heat : (chill != null && chill < temp ? chill : temp));
    return (
      WxCurrent(
        observedMs: ((o.integer('epoch') ?? 0) * 1000),
        source: 'pws:$stationId',
        tempC: temp,
        feelsLikeC: feels,
        windKph: m.number('windSpeed'),
        gustKph: m.number('windGust'),
        windDirDeg: o.number('winddir'),
        humidity: o.number('humidity'),
        dewpointC: m.number('dewpt'),
        pressureHpa: m.number('pressure'),
        precipTodayMm: m.number('precipTotal'),
        precipRateMmH: m.number('precipRate'),
        uvIndex: o.number('uv'),
        solarWm2: o.number('solarRadiation'),
        stationName: o.str('neighborhood') ?? stationId,
      ),
      o.number('lat') ?? 0,
      o.number('lon') ?? 0,
    );
  }

  /// The 5-day daily forecast (days 1–5 only; no hourly for PWS keys).
  Future<List<WxDay>> forecast5(double lat, double lon, HouseholdTime time) async {
    final uri = base.replace(path: '/v3/wx/forecast/daily/5day', queryParameters: {
      'geocode': '${lat.toStringAsFixed(3)},${lon.toStringAsFixed(3)}',
      'format': 'json',
      'units': 'm',
      'language': 'en-US',
      'apiKey': apiKey,
    });
    final j = asObject(await fetcher.getJson(provider, uri), provider);
    final valid = j.arr('validTimeLocal');
    final parts = j.arr('daypart');
    final dp = parts.isNotEmpty && parts.first is Map<String, Object?> ? parts.first! as Map<String, Object?> : const <String, Object?>{};
    Object? pick(String key, int i) {
      final list = j.arr(key);
      return i < list.length ? list[i] : null;
    }

    // Day part arrays interleave [day0, night0, day1, night1, …]; the first
    // day part is null after ~3 pm local.
    Object? part(String key, int i, {bool night = false}) {
      final list = dp.arr(key);
      final idx = i * 2 + (night ? 1 : 0);
      return idx < list.length ? list[idx] : null;
    }

    double? num0(Object? v) => v is num ? v.toDouble() : null;
    final out = <WxDay>[];
    for (var i = 0; i < valid.length; i++) {
      final date = LocalDate.tryParse('${valid[i]}');
      if (date == null) continue;
      final dayIcon = part('iconCode', i) ?? part('iconCode', i, night: true);
      final pDay = num0(part('precipChance', i));
      final pNight = num0(part('precipChance', i, night: true));
      final qpf = num0(pick('qpf', i));
      out.add(WxDay(
        date: date.iso,
        highC: num0(pick('calendarDayTemperatureMax', i)) ?? num0(pick('temperatureMax', i)),
        lowC: num0(pick('calendarDayTemperatureMin', i)) ?? num0(pick('temperatureMin', i)),
        condition: conditionFromTwcIcon((dayIcon as num?)?.toInt()),
        precipProb: [pDay, pNight].whereType<double>().fold<double?>(null, (a, b) => a == null ? b : math.max(a, b)),
        precipMm: qpf,
        uvMax: num0(part('uvIndex', i)),
        windMaxKph: num0(part('windSpeed', i)),
        sunriseMs: DateTime.tryParse('${pick('sunriseTimeLocal', i)}')?.millisecondsSinceEpoch,
        sunsetMs: DateTime.tryParse('${pick('sunsetTimeLocal', i)}')?.millisecondsSinceEpoch,
        narrative: pick('narrative', i) as String?,
        source: provider,
      ));
    }
    return out;
  }

  /// Personal weather stations near a point (for the station picker).
  Future<List<(String id, String name, double distanceKm)>> nearbyStations(double lat, double lon) async {
    final uri = base.replace(path: '/v3/location/near', queryParameters: {
      'geocode': '${lat.toStringAsFixed(3)},${lon.toStringAsFixed(3)}',
      'product': 'pws',
      'format': 'json',
      'apiKey': apiKey,
    });
    final loc = asObject(await fetcher.getJson(provider, uri), provider).obj('location');
    final ids = loc.arr('stationId');
    final names = loc.arr('stationName');
    final dist = loc.arr('distanceKm');
    return [
      for (var i = 0; i < ids.length; i++)
        ('${ids[i]}', i < names.length ? '${names[i]}' : '${ids[i]}', i < dist.length && dist[i] is num ? (dist[i]! as num).toDouble() : 0.0),
    ];
  }
}
