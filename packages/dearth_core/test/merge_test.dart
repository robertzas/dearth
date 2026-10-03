import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

void main() {
  String h(int ms, [String node = 'a']) => Hlc(ms, 0, node).pack();

  group('mergeFields (field-level LWW)', () {
    test('applies every field to an empty clock', () {
      final r = mergeFields(clock: const {}, fields: const {'title': 'Swim', 'all_day': false}, hlc: h(1));
      expect(r.changes, {'title': 'Swim', 'all_day': false});
      expect(r.clock, {'title': h(1), 'all_day': h(1)});
    });

    test('newer field wins, older field loses, per field', () {
      final clock = {'title': h(5), 'notes': h(1)};
      final r = mergeFields(clock: clock, fields: const {'title': 'Old', 'notes': 'New'}, hlc: h(3));
      expect(r.changes, {'notes': 'New'});
      expect(r.clock['title'], h(5));
      expect(r.clock['notes'], h(3));
    });

    test('equal HLC is not re-applied (idempotent)', () {
      final r = mergeFields(clock: {'title': h(5)}, fields: const {'title': 'Same'}, hlc: h(5));
      expect(r.changed, isFalse);
    });

    test('node id breaks ties deterministically', () {
      final r = mergeFields(clock: {'title': h(5)}, fields: const {'title': 'B'}, hlc: h(5, 'b'));
      expect(r.changes, {'title': 'B'});
    });

    test('unknown fields are skipped', () {
      final r = mergeFields(
        clock: const {},
        fields: const {'title': 'x', 'future_column': 1},
        hlc: h(1),
        isKnown: (f) => f == 'title',
      );
      expect(r.changes.keys, ['title']);
    });

    test('clock codec tolerates garbage', () {
      expect(decodeClock('not json'), isEmpty);
      expect(decodeClock(encodeClock({'a': h(1)})), {'a': h(1)});
    });
  });
}
