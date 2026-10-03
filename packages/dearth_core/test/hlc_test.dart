import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

void main() {
  group('Hlc', () {
    test('pack/parse round-trips and orders lexicographically', () {
      const a = Hlc(1700000000000, 3, 'devA');
      final packed = a.pack();
      expect(packed, '018bcfe568000003-devA');
      expect(Hlc.parse(packed), a);
      final stamps = [
        const Hlc(1, 0, 'b'),
        const Hlc(1, 0, 'a'),
        const Hlc(0, 9, 'z'),
        const Hlc(1, 1, 'a'),
      ];
      final byObject = [...stamps]..sort();
      final byString = [...stamps]..sort((x, y) => x.pack().compareTo(y.pack()));
      expect(byString, byObject);
    });

    test('node ids may contain dashes (UUIDs)', () {
      const h = Hlc(5, 1, '0192f4c1-aaaa-bbbb');
      expect(Hlc.parse(h.pack()).node, '0192f4c1-aaaa-bbbb');
    });

    test('tick is strictly monotonic when the wall clock stalls or jumps back', () {
      var wall = 1000;
      final clock = HlcClock('n1', wallClock: () => wall);
      final seen = <Hlc>[clock.tick(), clock.tick()];
      wall = 900; // clock moved backwards
      seen.add(clock.tick());
      wall = 2000;
      seen.add(clock.tick());
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i].compareTo(seen[i - 1]), greaterThan(0), reason: 'stamp $i');
      }
      expect(seen.last.millis, 2000);
      expect(seen.last.counter, 0);
    });

    test('observe advances past a remote stamp', () {
      var wall = 1000;
      final clock = HlcClock('n1', wallClock: () => wall);
      clock.observe(const Hlc(1500, 7, 'n2'));
      final next = clock.tick();
      expect(next.compareTo(const Hlc(1500, 7, 'n2')), greaterThan(0));
      wall = 3000;
      expect(clock.tick().millis, 3000);
    });

    test('rejects remote stamps far in the future', () {
      final clock = HlcClock('n1', wallClock: () => 0, maxDriftMs: 1000);
      expect(() => clock.observe(const Hlc(5000, 0, 'n2')), throwsA(isA<ClockDriftException>()));
    });

    test('counter overflow rolls into the next millisecond', () {
      final clock = HlcClock('n1', wallClock: () => 10);
      clock.observe(const Hlc(10, Hlc.maxCounter, 'n2'));
      final h = clock.tick();
      expect(h.millis, greaterThanOrEqualTo(11));
    });
  });
}
