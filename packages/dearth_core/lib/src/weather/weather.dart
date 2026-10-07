import 'dart:convert';
import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../util/json.dart';

/// Unified weather model (SPEC §13.4, Appendix D). Values are metric
/// (°C, mm, km/h, hPa); conversion happens at display time.

enum WxCondition {
  clear,
  mostlyClear,
  partlyCloudy,
  cloudy,
  fog,
  drizzle,
  rain,
  heavyRain,
  freezingRain,
  sleet,
  snow,
  heavySnow,
  thunderstorm,
  hail,
  windy,
  unknown;

  bool get isWet => const {drizzle, rain, heavyRain, freezingRain, sleet, thunderstorm, hail}.contains(this);
  bool get isSnowy => this == snow || this == heavySnow || this == sleet;

  static WxCondition parse(String? s) => values.firstWhere((v) => v.name == s, orElse: () => unknown);
}

/// Kid-friendly emoji for a condition (day/night aware).
String conditionEmoji(WxCondition c, {bool isDay = true}) => switch (c) {
      WxCondition.clear => isDay ? '☀️' : '🌙',
      WxCondition.mostlyClear => isDay ? '🌤️' : '🌙',
      WxCondition.partlyCloudy => isDay ? '⛅' : '☁️',
      WxCondition.cloudy => '☁️',
      WxCondition.fog => '🌫️',
      WxCondition.drizzle => '🌦️',
      WxCondition.rain || WxCondition.heavyRain => '🌧️',
      WxCondition.freezingRain || WxCondition.sleet => '🌨️',
      WxCondition.snow || WxCondition.heavySnow => '❄️',
      WxCondition.thunderstorm || WxCondition.hail => '⛈️',
      WxCondition.windy => '🌬️',
      WxCondition.unknown => '🌡️',
    };

String conditionLabel(WxCondition c) => switch (c) {
      WxCondition.clear => 'Clear',
      WxCondition.mostlyClear => 'Mostly clear',
      WxCondition.partlyCloudy => 'Partly cloudy',
      WxCondition.cloudy => 'Cloudy',
      WxCondition.fog => 'Fog',
      WxCondition.drizzle => 'Drizzle',
      WxCondition.rain => 'Rain',
      WxCondition.heavyRain => 'Heavy rain',
      WxCondition.freezingRain => 'Freezing rain',
      WxCondition.sleet => 'Sleet',
      WxCondition.snow => 'Snow',
      WxCondition.heavySnow => 'Heavy snow',
      WxCondition.thunderstorm => 'Thunderstorms',
      WxCondition.hail => 'Hail',
      WxCondition.windy => 'Windy',
      WxCondition.unknown => '—',
    };

/// WMO weather interpretation codes (Open-Meteo).
WxCondition conditionFromWmo(int? code) => switch (code) {
      0 => WxCondition.clear,
      1 => WxCondition.mostlyClear,
      2 => WxCondition.partlyCloudy,
      3 => WxCondition.cloudy,
      45 || 48 => WxCondition.fog,
      51 || 53 || 55 => WxCondition.drizzle,
      56 || 57 || 66 || 67 => WxCondition.freezingRain,
      61 || 63 || 80 || 81 => WxCondition.rain,
      65 || 82 => WxCondition.heavyRain,
      71 || 73 || 77 || 85 => WxCondition.snow,
      75 || 86 => WxCondition.heavySnow,
      95 => WxCondition.thunderstorm,
      96 || 99 => WxCondition.hail,
      _ => WxCondition.unknown,
    };

/// The Weather Company icon codes used by the WU forecast (0–47).
WxCondition conditionFromTwcIcon(int? code) => switch (code) {
      0 || 1 || 2 || 3 || 4 || 37 || 38 || 47 => WxCondition.thunderstorm,
      5 || 6 || 7 || 18 => WxCondition.sleet,
      8 || 10 => WxCondition.freezingRain,
      9 => WxCondition.drizzle,
      11 || 12 || 39 || 45 => WxCondition.rain,
      40 => WxCondition.heavyRain,
      13 || 14 || 16 || 41 || 46 => WxCondition.snow,
      15 || 42 || 43 => WxCondition.heavySnow,
      17 || 35 => WxCondition.hail,
      19 || 20 || 21 || 22 => WxCondition.fog,
      23 || 24 => WxCondition.windy,
      25 || 31 || 32 || 36 => WxCondition.clear,
      33 || 34 => WxCondition.mostlyClear,
      29 || 30 => WxCondition.partlyCloudy,
      26 || 27 || 28 => WxCondition.cloudy,
      _ => WxCondition.unknown,
    };

double? _d(Object? v) => v is num ? v.toDouble() : null;
int? _i(Object? v) => v is num ? v.round() : null;

@immutable
class WxCurrent {
  const WxCurrent({
    required this.observedMs,
    required this.source,
    this.tempC,
    this.feelsLikeC,
    this.condition = WxCondition.unknown,
    this.isDay = true,
    this.windKph,
    this.gustKph,
    this.windDirDeg,
    this.humidity,
    this.dewpointC,
    this.pressureHpa,
    this.precipTodayMm,
    this.precipRateMmH,
    this.uvIndex,
    this.solarWm2,
    this.stationName,
  });

  factory WxCurrent.fromJson(Map<String, Object?> j) => WxCurrent(
        observedMs: _i(j['observedMs']) ?? 0,
        source: j['source'] as String? ?? '',
        tempC: _d(j['tempC']),
        feelsLikeC: _d(j['feelsLikeC']),
        condition: WxCondition.parse(j['condition'] as String?),
        isDay: j['isDay'] as bool? ?? true,
        windKph: _d(j['windKph']),
        gustKph: _d(j['gustKph']),
        windDirDeg: _d(j['windDirDeg']),
        humidity: _d(j['humidity']),
        dewpointC: _d(j['dewpointC']),
        pressureHpa: _d(j['pressureHpa']),
        precipTodayMm: _d(j['precipTodayMm']),
        precipRateMmH: _d(j['precipRateMmH']),
        uvIndex: _d(j['uvIndex']),
        solarWm2: _d(j['solarWm2']),
        stationName: j['stationName'] as String?,
      );

  final int observedMs;

  /// `pws:<station>`, `nws:<station>` or `open-meteo`.
  final String source;
  final double? tempC;
  final double? feelsLikeC;
  final WxCondition condition;
  final bool isDay;
  final double? windKph;
  final double? gustKph;
  final double? windDirDeg;
  final double? humidity;
  final double? dewpointC;
  final double? pressureHpa;
  final double? precipTodayMm;
  final double? precipRateMmH;
  final double? uvIndex;
  final double? solarWm2;
  final String? stationName;

  bool get isPersonalStation => source.startsWith('pws:');

  WxCurrent fillFrom(WxCurrent other) => WxCurrent(
        observedMs: observedMs,
        source: source,
        tempC: tempC ?? other.tempC,
        feelsLikeC: feelsLikeC ?? other.feelsLikeC,
        condition: condition == WxCondition.unknown ? other.condition : condition,
        isDay: isDay,
        windKph: windKph ?? other.windKph,
        gustKph: gustKph ?? other.gustKph,
        windDirDeg: windDirDeg ?? other.windDirDeg,
        humidity: humidity ?? other.humidity,
        dewpointC: dewpointC ?? other.dewpointC,
        pressureHpa: pressureHpa ?? other.pressureHpa,
        precipTodayMm: precipTodayMm ?? other.precipTodayMm,
        precipRateMmH: precipRateMmH ?? other.precipRateMmH,
        uvIndex: uvIndex ?? other.uvIndex,
        solarWm2: solarWm2 ?? other.solarWm2,
        stationName: stationName ?? other.stationName,
      );

  Map<String, Object?> toJson() => {
        'observedMs': observedMs,
        'source': source,
        'tempC': tempC,
        'feelsLikeC': feelsLikeC,
        'condition': condition.name,
        'isDay': isDay,
        'windKph': windKph,
        'gustKph': gustKph,
        'windDirDeg': windDirDeg,
        'humidity': humidity,
        'dewpointC': dewpointC,
        'pressureHpa': pressureHpa,
        'precipTodayMm': precipTodayMm,
        'precipRateMmH': precipRateMmH,
        'uvIndex': uvIndex,
        'solarWm2': solarWm2,
        'stationName': stationName,
      };
}

@immutable
class WxHour {
  const WxHour({
    required this.timeMs,
    this.tempC,
    this.precipProb,
    this.precipMm,
    this.cloudPct,
    this.sunshineMin,
    this.uvIndex,
    this.condition = WxCondition.unknown,
    this.isDay = true,
    this.windKph,
    this.gustKph,
  });

  factory WxHour.fromJson(Map<String, Object?> j) => WxHour(
        timeMs: _i(j['t']) ?? 0,
        tempC: _d(j['temp']),
        precipProb: _d(j['pp']),
        precipMm: _d(j['mm']),
        cloudPct: _d(j['cloud']),
        sunshineMin: _d(j['sun']),
        uvIndex: _d(j['uv']),
        condition: WxCondition.parse(j['c'] as String?),
        isDay: j['day'] as bool? ?? true,
        windKph: _d(j['wind']),
        gustKph: _d(j['gust']),
      );

  final int timeMs;
  final double? tempC;
  final double? precipProb;
  final double? precipMm;
  final double? cloudPct;

  /// Minutes of sunshine during this hour (0–60).
  final double? sunshineMin;
  final double? uvIndex;
  final WxCondition condition;
  final bool isDay;
  final double? windKph;
  final double? gustKph;

  Map<String, Object?> toJson() => {
        't': timeMs,
        'temp': tempC,
        'pp': precipProb,
        'mm': precipMm,
        'cloud': cloudPct,
        'sun': sunshineMin,
        'uv': uvIndex,
        'c': condition.name,
        'day': isDay,
        'wind': windKph,
        'gust': gustKph,
      };
}

@immutable
class WxDay {
  const WxDay({
    required this.date,
    this.highC,
    this.lowC,
    this.condition = WxCondition.unknown,
    this.precipProb,
    this.precipMm,
    this.precipHours,
    this.sunshineHours,
    this.daylightHours,
    this.uvMax,
    this.windMaxKph,
    this.sunriseMs,
    this.sunsetMs,
    this.narrative,
    this.source = 'open-meteo',
  });

  factory WxDay.fromJson(Map<String, Object?> j) => WxDay(
        date: j['date'] as String? ?? '',
        highC: _d(j['hi']),
        lowC: _d(j['lo']),
        condition: WxCondition.parse(j['c'] as String?),
        precipProb: _d(j['pp']),
        precipMm: _d(j['mm']),
        precipHours: _d(j['ph']),
        sunshineHours: _d(j['sun']),
        daylightHours: _d(j['daylight']),
        uvMax: _d(j['uv']),
        windMaxKph: _d(j['wind']),
        sunriseMs: _i(j['rise']),
        sunsetMs: _i(j['set']),
        narrative: j['text'] as String?,
        source: j['src'] as String? ?? 'open-meteo',
      );

  /// `YYYY-MM-DD` (household-local).
  final String date;
  final double? highC;
  final double? lowC;
  final WxCondition condition;
  final double? precipProb;
  final double? precipMm;
  final double? precipHours;
  final double? sunshineHours;
  final double? daylightHours;
  final double? uvMax;
  final double? windMaxKph;
  final int? sunriseMs;
  final int? sunsetMs;
  final String? narrative;
  final String source;

  Map<String, Object?> toJson() => {
        'date': date,
        'hi': highC,
        'lo': lowC,
        'c': condition.name,
        'pp': precipProb,
        'mm': precipMm,
        'ph': precipHours,
        'sun': sunshineHours,
        'daylight': daylightHours,
        'uv': uvMax,
        'wind': windMaxKph,
        'rise': sunriseMs,
        'set': sunsetMs,
        'text': narrative,
        'src': source,
      };
}

@immutable
class WxAlert {
  const WxAlert({
    required this.id,
    required this.event,
    required this.severity,
    this.headline,
    this.description,
    this.instruction,
    this.startsMs,
    this.endsMs,
    this.sender,
  });

  factory WxAlert.fromJson(Map<String, Object?> j) => WxAlert(
        id: j['id'] as String? ?? '',
        event: j['event'] as String? ?? 'Alert',
        severity: j['severity'] as String? ?? 'Unknown',
        headline: j['headline'] as String?,
        description: j['description'] as String?,
        instruction: j['instruction'] as String?,
        startsMs: _i(j['starts']),
        endsMs: _i(j['ends']),
        sender: j['sender'] as String?,
      );

  final String id;
  final String event;

  /// Extreme | Severe | Moderate | Minor | Unknown (CAP).
  final String severity;
  final String? headline;
  final String? description;
  final String? instruction;
  final int? startsMs;
  final int? endsMs;
  final String? sender;

  int get severityRank => const {'Extreme': 4, 'Severe': 3, 'Moderate': 2, 'Minor': 1}[severity] ?? 0;

  Map<String, Object?> toJson() => {
        'id': id,
        'event': event,
        'severity': severity,
        'headline': headline,
        'description': description,
        'instruction': instruction,
        'starts': startsMs,
        'ends': endsMs,
        'sender': sender,
      };
}

/// The complete merged report stored in `weather_reports` (row `current`).
@immutable
class WeatherReport {
  const WeatherReport({
    required this.fetchedMs,
    this.current,
    this.hourly = const [],
    this.daily = const [],
    this.alerts = const [],
    this.locationLabel,
    this.lat,
    this.lon,
    this.sources = const {},
  });

  factory WeatherReport.fromJson(Map<String, Object?> j) => WeatherReport(
        fetchedMs: _i(j['fetchedMs']) ?? 0,
        current: j['current'] is Map<String, Object?> ? WxCurrent.fromJson(j['current']! as Map<String, Object?>) : null,
        hourly: [for (final h in j.arr('hourly')) if (h is Map<String, Object?>) WxHour.fromJson(h)],
        daily: [for (final d in j.arr('daily')) if (d is Map<String, Object?>) WxDay.fromJson(d)],
        alerts: [for (final a in j.arr('alerts')) if (a is Map<String, Object?>) WxAlert.fromJson(a)],
        locationLabel: j['location'] as String?,
        lat: _d(j['lat']),
        lon: _d(j['lon']),
        sources: {for (final e in j.obj('sources').entries) e.key: '${e.value}'},
      );

  static WeatherReport? tryDecode(String? source) {
    if (source == null || source.isEmpty || source == '{}') return null;
    try {
      final v = jsonDecode(source);
      return v is Map<String, Object?> ? WeatherReport.fromJson(v) : null;
    } on FormatException {
      return null;
    }
  }

  final int fetchedMs;
  final WxCurrent? current;
  final List<WxHour> hourly;
  final List<WxDay> daily;
  final List<WxAlert> alerts;
  final String? locationLabel;
  final double? lat;
  final double? lon;

  /// Which provider supplied which section: `{current: pws:K…, hourly: open-meteo, …}`.
  final Map<String, String> sources;

  WxDay? dayFor(String isoDate) => daily.where((d) => d.date == isoDate).firstOrNull;

  /// Hours from [fromMs] (inclusive) for [count] hours.
  List<WxHour> hoursFrom(int fromMs, int count) {
    final startIdx = hourly.indexWhere((h) => h.timeMs + 3600 * 1000 > fromMs);
    if (startIdx < 0) return const [];
    return hourly.sublist(startIdx, math.min(hourly.length, startIdx + count));
  }

  Map<String, Object?> toJson() => {
        'fetchedMs': fetchedMs,
        'current': current?.toJson(),
        'hourly': [for (final h in hourly) h.toJson()],
        'daily': [for (final d in daily) d.toJson()],
        'alerts': [for (final a in alerts) a.toJson()],
        'location': locationLabel,
        'lat': lat,
        'lon': lon,
        'sources': sources,
      };

  String encode() => jsonEncode(toJson());
}

// ─────────────────────────────── Summaries ─────────────────────────────────

/// A contiguous window of likely precipitation.
@immutable
class RainWindow {
  const RainWindow({required this.startMs, required this.endMs, required this.totalMm, required this.maxProb, required this.snow});
  final int startMs;
  final int endMs;
  final double totalMm;
  final double maxProb;
  final bool snow;
}

/// Finds the first window in [hours] where precipitation is likely
/// (probability ≥ [threshold] % or measurable amount).
RainWindow? nextRainWindow(List<WxHour> hours, {double threshold = 40}) {
  int? start;
  int? end;
  var total = 0.0;
  var maxProb = 0.0;
  var snow = false;
  for (final h in hours) {
    final likely = (h.precipProb ?? 0) >= threshold || (h.precipMm ?? 0) >= 0.3;
    if (likely) {
      start ??= h.timeMs;
      end = h.timeMs + 3600 * 1000;
      total += h.precipMm ?? 0;
      maxProb = math.max(maxProb, h.precipProb ?? 0);
      snow = snow || h.condition.isSnowy;
    } else if (start != null) {
      break;
    }
  }
  if (start == null) return null;
  return RainWindow(startMs: start, endMs: end!, totalMm: total, maxProb: maxProb, snow: snow);
}

/// Things to wear or bring (FR-WX-07).
enum WearItem { winterCoat, jacket, sweater, tshirt, shorts, warmHat, mittens, raincoat, umbrella, boots, sunglasses, sunhat, sunscreen }

String wearEmoji(WearItem item) => switch (item) {
      WearItem.winterCoat => '🧥',
      WearItem.jacket => '🧥',
      WearItem.sweater => '👚',
      WearItem.tshirt => '👕',
      WearItem.shorts => '🩳',
      WearItem.warmHat => '🧢',
      WearItem.mittens => '🧤',
      WearItem.raincoat => '🧥',
      WearItem.umbrella => '☂️',
      WearItem.boots => '🥾',
      WearItem.sunglasses => '🕶️',
      WearItem.sunhat => '👒',
      WearItem.sunscreen => '🧴',
    };

String wearLabel(WearItem item) => switch (item) {
      WearItem.winterCoat => 'Winter coat',
      WearItem.jacket => 'Jacket',
      WearItem.sweater => 'Sweater',
      WearItem.tshirt => 'T-shirt',
      WearItem.shorts => 'Shorts',
      WearItem.warmHat => 'Warm hat',
      WearItem.mittens => 'Mittens',
      WearItem.raincoat => 'Raincoat',
      WearItem.umbrella => 'Umbrella',
      WearItem.boots => 'Boots',
      WearItem.sunglasses => 'Sunglasses',
      WearItem.sunhat => 'Sun hat',
      WearItem.sunscreen => 'Sunscreen',
    };

/// What "what to wear" decides from (FR-WX-07): the coldest daytime
/// temperature in the next 12 hours (else the feel right now, else the
/// day's low), and today's rain, snow, wind, UV and sky.
({double feelsLikeC, double precipProb, double precipMm, bool snow, double windKph, double uvMax, bool sunny}) wearInputs(WeatherReport report, {required String todayIso, required int nowMs}) {
  final d = report.dayFor(todayIso);
  final dayFeels = [for (final h in report.hoursFrom(nowMs, 12)) if (h.isDay && h.tempC != null) h.tempC!];
  return (
    feelsLikeC: dayFeels.isEmpty ? (report.current?.feelsLikeC ?? report.current?.tempC ?? d?.lowC ?? 15) : dayFeels.reduce(math.min),
    precipProb: d?.precipProb ?? 0,
    precipMm: d?.precipMm ?? 0,
    snow: d?.condition.isSnowy ?? false,
    windKph: d?.windMaxKph ?? 0,
    uvMax: d?.uvMax ?? 0,
    sunny: d?.condition == WxCondition.clear || d?.condition == WxCondition.mostlyClear,
  );
}

/// Rule-based outfit for the day: dressing for the coldest daytime feel,
/// protecting against rain/snow, wind and UV.
List<WearItem> whatToWear({
  required double feelsLikeC,
  double precipProb = 0,
  double precipMm = 0,
  bool snow = false,
  double windKph = 0,
  double uvMax = 0,
  bool sunny = false,
}) {
  final items = <WearItem>[];
  final feel = feelsLikeC - (windKph > 30 ? 3 : 0);
  if (feel < 0) {
    items.addAll([WearItem.winterCoat, WearItem.warmHat, WearItem.mittens]);
  } else if (feel < 8) {
    items.addAll([WearItem.winterCoat, WearItem.warmHat]);
  } else if (feel < 15) {
    items.add(WearItem.jacket);
  } else if (feel < 20) {
    items.add(WearItem.sweater);
  } else if (feel < 26) {
    items.add(WearItem.tshirt);
  } else {
    items.addAll([WearItem.tshirt, WearItem.shorts]);
  }
  final wet = precipProb >= 50 || precipMm >= 1;
  if (snow && wet) {
    items.add(WearItem.boots);
    if (!items.contains(WearItem.mittens)) items.add(WearItem.mittens);
  } else if (wet) {
    items.addAll([WearItem.raincoat, WearItem.boots]);
  } else if (precipProb >= 30) {
    items.add(WearItem.umbrella);
  }
  if (uvMax >= 6) {
    items.addAll([WearItem.sunhat, WearItem.sunscreen]);
  } else if (uvMax >= 3) {
    items.add(WearItem.sunscreen);
  }
  if (sunny && uvMax >= 3) items.add(WearItem.sunglasses);
  return items;
}

/// The choices for how often the weather updates, in minutes.
const List<int> kWeatherRefreshChoices = [5, 10, 15, 30, 60];

/// How often the Hub fetches the weather (SPEC §14.3): the household's
/// choice (`weather.refresh`), else every 10 minutes, or 5 with a personal
/// weather station, whose readings change that fast. Open-Meteo's free tier
/// allows far more than either.
Duration weatherRefresh(Map<String, Object?> setting, {required bool hasStation}) {
  final minutes = (setting['minutes'] as num?)?.toInt();
  if (minutes == null) return Duration(minutes: hasStation ? 5 : 10);
  return Duration(minutes: minutes.clamp(5, 60));
}

/// °C → display value in the household's units.
double displayTemp(double c, {required bool imperial}) => imperial ? c * 9 / 5 + 32 : c;
double displayPrecip(double mm, {required bool imperial}) => imperial ? mm / 25.4 : mm;
double displayWind(double kph, {required bool imperial}) => imperial ? kph / 1.609344 : kph;
