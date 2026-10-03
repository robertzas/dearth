import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

int _utc(int y, int m, int d, [int h = 0, int min = 0]) => DateTime.utc(y, m, d, h, min).millisecondsSinceEpoch;

void main() {
  group('FR-WX-06 moon phase', () {
    test('known full moons read as full', () {
      // Full moons: 2024-09-18 02:34Z, 2025-10-07 03:47Z.
      for (final ms in [_utc(2024, 9, 18, 2, 34), _utc(2025, 10, 7, 3, 47)]) {
        final p = moonPhaseAt(ms);
        expect(p.name, 'Full moon');
        expect(p.illumination, greaterThan(0.97));
      }
    });

    test('known new moons read as new', () {
      // New moons: 2024-10-02 18:49Z, 2026-01-18 19:52Z.
      for (final ms in [_utc(2024, 10, 2, 18, 49), _utc(2026, 1, 18, 19, 52)]) {
        final p = moonPhaseAt(ms);
        expect(p.name, 'New moon');
        expect(p.illumination, lessThan(0.03));
        expect(p.emoji, '🌑');
      }
    });

    test('first quarter is waxing and half lit', () {
      // First quarter: 2024-10-10 18:55Z.
      final p = moonPhaseAt(_utc(2024, 10, 10, 18, 55));
      expect(p.name, 'First quarter');
      expect(p.illumination, closeTo(0.5, 0.08));
    });
  });
}
