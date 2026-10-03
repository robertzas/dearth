import 'package:meta/meta.dart';

import '../time/household_time.dart';
import '../weather/weather.dart';
import 'recurrence.dart';

/// Words that put an event outdoors (FR-CAL-19). Matched like the icon
/// keywords: whole words, case-insensitive, plural "s" allowed.
const List<String> kOutdoorKeywords = [
  'outdoor', 'outdoors', 'outside', 'park', 'playground', 'splash pad', 'picnic', 'hike', 'hiking', 'trail', 'walk',
  'beach', 'lake', 'river', 'camping', 'campout', 'zoo', 'farm', 'farmers market', 'market', 'pumpkin patch',
  'apple picking', 'garden', 'gardening', 'yard', 'soccer', 'baseball', 'softball', 't-ball', 'tball', 'football',
  'tennis', 'golf', 'bike', 'biking', 'cycling', 'run', 'running', '5k', 'marathon', 'race', 'ski', 'skiing',
  'snowboard', 'sledding', 'fishing', 'parade', 'fair', 'festival', 'fireworks', 'bbq', 'barbecue', 'cookout',
  'pool party', 'trick or treat', 'trick-or-treat', 'car wash',
];

/// Whether [title] sounds like it happens outdoors.
bool isOutdoorTitle(String title) {
  final words = ' ${title.toLowerCase().replaceAll(RegExp(r"[^a-z0-9'\- ]"), ' ')} ';
  return kOutdoorKeywords.any((k) => words.contains(' $k ') || words.contains(' ${k}s '));
}

/// The forecast shown on an event (FR-CAL-19).
@immutable
class EventForecast {
  const EventForecast({required this.condition, required this.isDay, this.tempC, this.highC, this.lowC, this.precipProb});
  final WxCondition condition;
  final bool isDay;

  /// The hour's temperature, for timed events within the hourly forecast.
  final double? tempC;

  /// The day's range, for all-day events and days past the hourly forecast.
  final double? highC;
  final double? lowC;
  final double? precipProb;

  String get emoji => conditionEmoji(condition, isDay: isDay);

  /// Rain (or snow) is likely enough to plan around.
  bool get wet => (precipProb ?? 0) >= 50 || condition.isWet || condition.isSnowy;
}

/// How far ahead events show weather (Skylight parity).
const Duration kEventForecastHorizon = Duration(days: 7);

/// The forecast for [o] from the household's [report]: events within the
/// next 7 days (or under way) that have a location or an outdoor keyword.
/// Timed events use the hour they start (or the hour under way); otherwise
/// the day's forecast.
///
/// The forecast is the household location's: places far from home would need
/// their own (a Hub follow-up), but most family events are local.
EventForecast? eventForecast(WeatherReport? report, Occurrence o, HouseholdTime time, {required int nowMs}) {
  if (report == null) return null;
  final e = o.event;
  final hasPlace = e.location != null && e.location!.trim().isNotEmpty;
  if (!hasPlace && !isOutdoorTitle(e.title)) return null;
  if (o.endMs <= nowMs || o.startMs > nowMs + kEventForecastHorizon.inMilliseconds) return null;
  if (!o.allDay) {
    final at = o.startMs < nowMs ? nowMs : o.startMs;
    final hour = report.hourly.where((h) => h.timeMs <= at && at < h.timeMs + 3600000).firstOrNull;
    if (hour != null) {
      return EventForecast(condition: hour.condition, isDay: hour.isDay, tempC: hour.tempC, precipProb: hour.precipProb);
    }
  }
  final date = o.allDay && o.startDate != null ? (o.startDate!.isBefore(time.dateOfMs(nowMs)) ? time.dateOfMs(nowMs) : o.startDate!) : time.dateOfMs(o.startMs);
  final day = report.dayFor(date.iso);
  if (day == null) return null;
  return EventForecast(condition: day.condition, isDay: true, highC: day.highC, lowC: day.lowC, precipProb: day.precipProb);
}
