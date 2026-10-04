import 'dart:math';

import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

/// The picture timeline for pre-readers (SPEC FR-CAL-10).
void main() {
  int h(int hour, [int minute = 0]) => hour * 60 + minute;

  test('the day splits at noon and 5 pm', () {
    expect([for (final m in [h(7), h(11, 59), h(12), h(16, 59), h(17), h(23)]) DayPart.of(m)],
        [DayPart.morning, DayPart.morning, DayPart.afternoon, DayPart.afternoon, DayPart.evening, DayPart.evening]);
  });

  test('stops are evenly spaced in their part, and a part is as long as it has stops', () {
    final l = layoutKidTimeline([TimelineSpan(h(8), h(9)), TimelineSpan(h(10)), TimelineSpan(h(15)), TimelineSpan(h(18, 30))]);
    expect([for (final b in l.bands) (b.part, b.from, b.to, b.count)], [
      (DayPart.morning, 0.0, 0.5, 2),
      (DayPart.afternoon, 0.5, 0.75, 1),
      (DayPart.evening, 0.75, 1.0, 1),
    ]);
    expect(l.centers, [0.125, 0.375, 0.625, 0.875]);
  });

  test('an empty part keeps a little room, and stops come back in the order given', () {
    final l = layoutKidTimeline([TimelineSpan(h(18)), TimelineSpan(h(9))]);
    expect(l.bands[1].count, 0);
    expect(l.bands[1].to - l.bands[1].from, closeTo(0.6 / 2.6, 1e-9));
    expect(l.centers[0], greaterThan(l.centers[1]), reason: 'the evening stop was given first');
  });

  test('"now" crosses a stop while it runs, then moves along the gap to the next', () {
    // Daycare 8–9, snack at 10. Morning gets 2 of 3.2 weights, so 0…0.625,
    // with two slots of 0.3125: daycare centred at 0.15625, snack at 0.46875.
    final l = layoutKidTimeline([TimelineSpan(h(8), h(9)), TimelineSpan(h(10))]);
    expect(l.at(h(6)), 0, reason: 'before the day starts, it waits at the beginning');
    expect(l.at(h(7, 30)), closeTo(0.0390625, 1e-9));
    expect(l.at(h(8, 30)), closeTo(0.15625, 1e-9), reason: 'half way through daycare is its middle');
    expect(l.at(h(10)), closeTo(0.46875, 1e-9));
    expect(l.at(h(11)), closeTo(0.546875, 1e-9));
    expect(l.at(h(14, 30)), closeTo(0.71875, 1e-9), reason: 'an empty afternoon passes evenly');
    expect(l.at(h(22)), 1, reason: 'after bedtime, it rests at the end');
  });

  test('"now" never moves backwards, whatever the stops', () {
    final rng = Random(7);
    for (var seed = 0; seed < 200; seed++) {
      final stops = [
        for (var i = rng.nextInt(9); i > 0; i--)
          () {
            final start = rng.nextInt(24 * 60);
            return TimelineSpan(start, rng.nextBool() ? start + rng.nextInt(240) : null);
          }(),
      ];
      final l = layoutKidTimeline(stops);
      var last = -1.0;
      for (var m = 0; m <= 24 * 60; m += 5) {
        final at = l.at(m);
        expect(at, inInclusiveRange(0, 1));
        expect(at, greaterThanOrEqualTo(last), reason: 'seed $seed at minute $m: $stops');
        last = at;
      }
      expect(l.bands.last.to, closeTo(1, 1e-9));
    }
  });
}
