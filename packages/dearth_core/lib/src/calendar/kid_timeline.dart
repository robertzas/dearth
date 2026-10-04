import 'package:meta/meta.dart';

/// The three parts of a kid's day on the picture timeline (SPEC FR-CAL-10).
enum DayPart {
  morning('Morning', '🌅', 0),
  afternoon('Afternoon', '☀️', 12 * 60),
  evening('Evening', '🌙', 17 * 60);

  const DayPart(this.label, this.emoji, this.startMinute);
  final String label;
  final String emoji;

  /// Minutes after midnight the part begins (morning: whenever the day does).
  final int startMinute;

  static DayPart of(int minuteOfDay) => minuteOfDay < afternoon.startMinute ? morning : (minuteOfDay < evening.startMinute ? afternoon : evening);
}

/// Something on the timeline, in minutes after midnight. [end] is null for
/// moments (dinner, a routine's start).
@immutable
class TimelineSpan {
  const TimelineSpan(this.start, [this.end]);
  final int start;
  final int? end;

  DayPart get part => DayPart.of(start);
}

/// One part's stretch of the timeline.
@immutable
class TimelineBand {
  const TimelineBand(this.part, this.from, this.to, this.count);
  final DayPart part;

  /// Fractions of the timeline's length, 0…1.
  final double from;
  final double to;

  /// How many stops sit in it.
  final int count;
}

/// Where everything sits along a kid's timeline, as fractions 0…1 of its
/// length. Pre-readers need order, not proportion: stops are evenly spaced
/// within their part, and each part is as long as it has stops (an empty one
/// keeps a little room). "Now" moves between the stops by the clock: across
/// a stop while it runs, along the gap between stops otherwise.
@immutable
class KidTimelineLayout {
  const KidTimelineLayout._(this.bands, this.centers, this._anchors);

  /// Morning, afternoon and evening, always all three, in order.
  final List<TimelineBand> bands;

  /// The center of each stop, in the order the stops were given.
  final List<double> centers;

  final List<({int minute, double at})> _anchors;

  /// Where "now" sits at [minute] after midnight. Before the day starts it
  /// waits at the beginning; after it ends, at the end.
  double at(int minute) {
    if (minute <= _anchors.first.minute) return _anchors.first.at;
    if (minute >= _anchors.last.minute) return _anchors.last.at;
    for (var i = 0; i < _anchors.length - 1; i++) {
      final a = _anchors[i], b = _anchors[i + 1];
      if (minute >= a.minute && minute < b.minute) {
        return a.at + (b.at - a.at) * (minute - a.minute) / (b.minute - a.minute);
      }
    }
    return _anchors.last.at;
  }
}

/// Lays out [stops] (any order) for a day that starts around [wake] and ends
/// around [bedtime], minutes after midnight.
KidTimelineLayout layoutKidTimeline(List<TimelineSpan> stops, {int wake = 7 * 60, int bedtime = 20 * 60, double emptyRoom = 0.6}) {
  final order = List<int>.generate(stops.length, (i) => i)..sort((a, b) => stops[a].start.compareTo(stops[b].start));
  final byPart = {for (final p in DayPart.values) p: <int>[for (final i in order) if (stops[i].part == p) i]};
  final weights = {for (final p in DayPart.values) p: byPart[p]!.isEmpty ? emptyRoom : byPart[p]!.length.toDouble()};
  final total = weights.values.fold<double>(0, (a, b) => a + b);

  final first = order.isEmpty ? wake : stops[order.first].start;
  var last = bedtime;
  for (final s in stops) {
    final end = s.end ?? s.start + 30;
    if (end > last) last = end;
  }
  final partStart = {DayPart.morning: first < wake ? first : wake, DayPart.afternoon: DayPart.afternoon.startMinute, DayPart.evening: DayPart.evening.startMinute};
  final partEnd = {DayPart.morning: DayPart.afternoon.startMinute, DayPart.afternoon: DayPart.evening.startMinute, DayPart.evening: last};

  final bands = <TimelineBand>[];
  final centers = List<double>.filled(stops.length, 0);
  final anchors = <({int minute, double at})>[];
  var x = 0.0;
  for (final p in DayPart.values) {
    // The last part ends exactly at 1: summed fractions drift past it.
    final from = x, to = p == DayPart.values.last ? 1.0 : x + weights[p]! / total;
    final idx = byPart[p]!;
    bands.add(TimelineBand(p, from, to, idx.length));
    anchors.add((minute: partStart[p]!, at: from));
    final slot = idx.isEmpty ? 0.0 : (to - from) / idx.length;
    for (var k = 0; k < idx.length; k++) {
      final s = stops[idx[k]];
      final c = from + slot * (k + 0.5);
      centers[idx[k]] = c;
      final next = k + 1 < idx.length ? stops[idx[k + 1]].start : partEnd[p]!;
      final end = s.end;
      if (end != null && end > s.start && end <= next) {
        // A stop that runs: "now" crosses its picture while it's on.
        anchors
          ..add((minute: s.start, at: c - slot / 4))
          ..add((minute: end, at: c + slot / 4));
      } else {
        anchors.add((minute: s.start, at: c));
      }
    }
    anchors.add((minute: partEnd[p]!, at: to));
    x = to;
  }
  // Overlaps and stops that run past their part can put a later anchor at an
  // earlier time; time never runs backwards along the line.
  for (var i = 1; i < anchors.length; i++) {
    if (anchors[i].minute < anchors[i - 1].minute) anchors[i] = (minute: anchors[i - 1].minute, at: anchors[i].at);
  }
  return KidTimelineLayout._(bands, centers, anchors);
}
