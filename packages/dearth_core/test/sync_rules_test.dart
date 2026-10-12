import 'dart:math';

import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

/// The replication rules devices and the Hub share (SPEC §8.4–8.5): which
/// fields a device may write and which tables a kid-room display receives,
/// the privacy boundary of the sync protocol.
void main() {
  group('who may write what', () {
    test('devices never write hub-only tables, hub fields or system columns', () {
      for (final spec in kSyncTables.values) {
        for (final f in kSyncSystemColumns) {
          expect(deviceMayWriteField(spec, f), isFalse, reason: '${spec.name}.$f');
        }
        for (final f in spec.hubFields) {
          expect(deviceMayWriteField(spec, f), isFalse, reason: '${spec.name}.$f is the Hub\'s');
        }
        if (spec.hubOnly) expect(deviceMayWriteField(spec, 'deleted'), isFalse, reason: '${spec.name} is hub-only');
      }
      expect(deviceMayWriteField(kSyncTables['weather_reports']!, 'data'), isFalse);
      expect(deviceMayWriteField(kSyncTables['events']!, 'etag'), isFalse);
      expect(deviceMayWriteField(kSyncTables['events']!, 'title'), isTrue);
      expect(deviceMayWriteField(kSyncTables['events']!, 'deleted'), isTrue, reason: 'a tombstone is a device write');
      expect(deviceMayWriteField(kSyncTables['photo_items']!, 'favorite'), isTrue);
      expect(deviceMayWriteField(kSyncTables['photo_items']!, 'blob_ref'), isFalse);
    });

    test('a kid-room display receives only kid-visible tables; every other role receives all', () {
      const private = ['lists', 'list_items', 'recipes', 'shopping_states', 'feeling_entries', 'photo_sources'];
      for (final t in private) {
        expect(roleReceivesTable(DeviceRole.kidRoom, t), isFalse, reason: t);
      }
      for (final t in ['events', 'chores', 'ledger_entries', 'game_events', 'weather_reports']) {
        expect(roleReceivesTable(DeviceRole.kidRoom, t), isTrue, reason: t);
      }
      for (final role in DeviceRole.all.where((r) => r != DeviceRole.kidRoom)) {
        for (final t in kSyncTables.keys) {
          expect(roleReceivesTable(role, t), isTrue, reason: '$role $t');
        }
      }
      expect(roleReceivesTable(DeviceRole.kitchen, 'not_a_table'), isFalse);
    });

    test('whatever a kid-room display may write, it also receives', () {
      for (final spec in kSyncTables.values.where((s) => s.kidWritable)) {
        expect(spec.kidVisible || spec.name == 'feeling_entries', isTrue, reason: spec.name);
      }
    });
  });

  group('sort keys', () {
    test('a key between two neighbours sorts strictly between them, however many times', () {
      final r = Random(7);
      final keys = <String>[sortKeyAfter(null)];
      for (var n = 0; n < 3000; n++) {
        final i = r.nextInt(keys.length + 1);
        final before = i == 0 ? null : keys[i - 1];
        final after = i == keys.length ? null : keys[i];
        final k = sortKeyBetween(before, after);
        if (before != null) expect(k.compareTo(before), greaterThan(0), reason: '$before < $k');
        if (after != null) expect(k.compareTo(after), lessThan(0), reason: '$k < $after');
        keys.insert(i, k);
      }
      expect(keys.toSet().length, keys.length);
    });

    test('appending always sorts last, past z', () {
      var k = sortKeyAfter(null);
      for (var n = 0; n < 100; n++) {
        final next = sortKeyAfter(k);
        expect(next.compareTo(k), greaterThan(0), reason: '$k < $next');
        k = next;
      }
    });
  });
}
