import 'dart:math';

import 'package:dearth_core/dearth_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

DearthDb memoryDb() => DearthDb(NativeDatabase.memory());

Future<List<Map<String, Object?>>> rows(DearthDb db, String table) async {
  final all = await SyncStore(db).readAll(table);
  final out = [
    for (final r in all) {...r}..remove('sync_seq'),
  ]..sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
  return out;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late DearthDb db;
  late SyncStore store;
  setUp(() {
    db = memoryDb();
    store = SyncStore(db);
  });
  tearDown(() => db.close());

  Op op(String table, String id, Map<String, Object?> f, String hlc, {OpKind kind = OpKind.upsert}) =>
      Op(id: newId(), table: table, rowId: id, kind: kind, fields: f, hlc: hlc);
  String h(int ms, [String node = 'n']) => Hlc(ms, 0, node).pack();

  test('upsert creates a row; defaults fill unspecified columns', () async {
    await store.applyOp(op('events', 'e1', {'title': 'Swim', 'start_ms': 100}, h(1)));
    final ev = await (db.select(db.events)..where((t) => t.id.equals('e1'))).getSingle();
    expect(ev.title, 'Swim');
    expect(ev.startMs, 100);
    expect(ev.allDay, isFalse);
    expect(ev.profileIds, '[]');
    expect(ev.syncHlc, h(1));
  });

  test('field-level LWW: concurrent edits to different fields both survive', () async {
    await store.applyOp(op('events', 'e1', {'title': 'Swim', 'notes': 'pool A'}, h(1)));
    await store.applyOp(op('events', 'e1', {'notes': 'pool B'}, h(3, 'b')));
    await store.applyOp(op('events', 'e1', {'title': 'Swim lesson'}, h(2, 'a')));
    final ev = await (db.select(db.events)..where((t) => t.id.equals('e1'))).getSingle();
    expect(ev.title, 'Swim lesson');
    expect(ev.notes, 'pool B');
  });

  test('stale write loses; booleans and doubles round-trip', () async {
    await store.applyOp(op('list_items', 'i1', {'text': 'Milk', 'checked': true, 'qty': 1.5}, h(5)));
    final changed = await store.applyOp(op('list_items', 'i1', {'checked': false}, h(4)));
    expect(changed, isFalse);
    final item = await (db.select(db.listItems)..where((t) => t.id.equals('i1'))).getSingle();
    expect(item.checked, isTrue);
    expect(item.qty, 1.5);
    expect(item.itemText, 'Milk');
  });

  test('delete is a tombstone that a newer upsert can revive', () async {
    await store.applyOp(op('notes', 'n1', {'body': 'hi'}, h(1)));
    await store.applyOp(op('notes', 'n1', const {}, h(2), kind: OpKind.delete));
    var note = await (db.select(db.notes)..where((t) => t.id.equals('n1'))).getSingle();
    expect(note.deleted, isTrue);
    await store.applyOp(op('notes', 'n1', {'deleted': false}, h(3)));
    note = await (db.select(db.notes)..where((t) => t.id.equals('n1'))).getSingle();
    expect(note.deleted, isFalse);
  });

  test('insert-only rows: first writer (lowest HLC) wins in any order', () async {
    final early = op('ledger_entries', 'l1', {'delta': 1, 'reason': 'chore'}, h(10, 'a'), kind: OpKind.insertOnly);
    final late = op('ledger_entries', 'l1', {'delta': 99, 'reason': 'forged'}, h(20, 'b'), kind: OpKind.insertOnly);
    final db2 = memoryDb();
    addTearDown(db2.close);
    await store.applyOps([late, early]);
    await SyncStore(db2).applyOps([early, late]);
    expect(await rows(db, 'ledger_entries'), await rows(db2, 'ledger_entries'));
    final entry = await db.select(db.ledgerEntries).getSingle();
    expect(entry.delta, 1);
  });

  test('unknown columns and system columns in ops are ignored', () async {
    await store.applyOp(op('events', 'e1', {'title': 'x', 'from_the_future': 1, 'sync_seq': 999}, h(1)));
    final ev = await db.select(db.events).getSingle();
    expect(ev.title, 'x');
    expect(ev.syncSeq, 0);
  });

  test('unknown table throws', () {
    expect(() => store.applyOp(op('nope', 'x', const {}, h(1))), throwsA(isA<UnknownTableException>()));
  });

  test('sequence numbers only move forward', () async {
    await store.applyOp(op('events', 'e1', {'title': 'a'}, h(2)), seq: 5);
    await store.applyOp(op('events', 'e1', {'title': 'old'}, h(1)), seq: 7);
    final ev = await db.select(db.events).getSingle();
    expect(ev.title, 'a');
    expect(ev.syncSeq, 7);
  });

  test('Mutator applies locally, stamps HLC and hands ops to the sink atomically', () async {
    final sent = <Op>[];
    final m = Mutator(store: store, clock: HlcClock('dev1'), sink: (ops) async => sent.addAll(ops));
    final id = await m.create('events', {'title': 'Dentist', 'profile_ids': ['mom'], 'start_ms': DateTime.utc(2026)});
    final ev = await db.select(db.events).getSingle();
    expect(ev.id, id);
    expect(ev.profileIds, '["mom"]');
    expect(ev.startMs, DateTime.utc(2026).millisecondsSinceEpoch);
    expect(sent.single.fields['profile_ids'], '["mom"]');
    expect(() => m.makeOp('events', id, {'bogus': 1}), throwsArgumentError);
  });

  test('a failing sink rolls back the local write', () async {
    final m = Mutator(store: store, clock: HlcClock('dev1'), sink: (_) async => throw StateError('disk full'));
    await expectLater(m.upsert('notes', 'n1', {'body': 'x'}), throwsStateError);
    expect(await db.select(db.notes).get(), isEmpty);
  });

  test('replaceAll swaps in a snapshot and clears other tables', () async {
    await store.applyOp(op('notes', 'n1', {'body': 'old'}, h(1)));
    final other = memoryDb();
    addTearDown(other.close);
    final otherStore = SyncStore(other);
    await otherStore.applyOp(op('events', 'e9', {'title': 'Snap'}, h(5)));
    final snapshot = {for (final t in otherStore.syncedTables) t: await otherStore.readAll(t)};
    await store.replaceAll(snapshot);
    expect(await db.select(db.notes).get(), isEmpty);
    expect((await db.select(db.events).getSingle()).title, 'Snap');
  });

  group('convergence (property-based, SPEC §8.4.8)', () {
    const tables = ['events', 'list_items', 'ledger_entries'];
    Map<String, Object?> randomFields(Random r, String table) => switch (table) {
          'events' => {
              if (r.nextBool()) 'title': ['Swim', 'Dentist', 'Park', 'Nap'][r.nextInt(4)],
              if (r.nextBool()) 'start_ms': r.nextInt(1 << 30),
              if (r.nextBool()) 'all_day': r.nextBool(),
              if (r.nextInt(5) == 0) 'deleted': r.nextBool(),
            },
          'list_items' => {
              if (r.nextBool()) 'text': ['Milk', 'Eggs', 'Bread'][r.nextInt(3)],
              if (r.nextBool()) 'checked': r.nextBool(),
              if (r.nextBool()) 'qty': r.nextInt(10) / 2,
            },
          _ => {'delta': r.nextInt(5) + 1, 'reason': 'chore'},
        };

    for (var seed = 0; seed < 60; seed++) {
      test('seed $seed: 3 replicas converge under reordering, duplication and skew', () async {
        final r = Random(seed);
        final clocks = [
          for (var n = 0; n < 3; n++) HlcClock('node$n', wallClock: () => 1000000 + r.nextInt(5000) - n * 700),
        ];
        final ops = <Op>[];
        for (var i = 0; i < 40; i++) {
          final node = r.nextInt(3);
          final table = tables[r.nextInt(tables.length)];
          final rowId = '$table-${r.nextInt(5)}';
          final fields = randomFields(r, table);
          if (fields.isEmpty) continue;
          // Nodes occasionally observe each other's latest stamp.
          if (ops.isNotEmpty && r.nextBool()) clocks[node].observe(Hlc.parse(ops[r.nextInt(ops.length)].hlc));
          ops.add(Op(
            id: 'op$i',
            table: table,
            rowId: rowId,
            kind: table == 'ledger_entries' ? OpKind.insertOnly : OpKind.upsert,
            fields: fields,
            hlc: clocks[node].tick().pack(),
          ));
        }
        final replicas = [memoryDb(), memoryDb(), memoryDb()];
        try {
          for (final replica in replicas) {
            final delivery = [...ops, ...ops.where((_) => r.nextInt(4) == 0)]..shuffle(r);
            await SyncStore(replica).applyOps(delivery);
          }
          for (final table in tables) {
            final a = await rows(replicas[0], table);
            expect(await rows(replicas[1], table), a, reason: '$table replica 1');
            expect(await rows(replicas[2], table), a, reason: '$table replica 2');
          }
        } finally {
          for (final replica in replicas) {
            await replica.close();
          }
        }
      });
    }
  });
}
