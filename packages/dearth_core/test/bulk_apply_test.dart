import 'dart:math';

import 'package:dearth_core/dearth_core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:test/test.dart';

/// [SyncStore.applyOpsBulk] must be indistinguishable from applying each op
/// with [SyncStore.applyOp] (SPEC §8.4.8): same values, field clocks, row
/// HLCs and sequence numbers, for any mix of upserts, deletes, insert-only
/// rows, duplicates, stale writes and unknown columns.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  const tables = ['events', 'list_items', 'ledger_entries', 'notes'];

  Future<Map<String, List<Map<String, Object?>>>> dump(DearthDb db) async {
    final store = SyncStore(db);
    return {
      for (final t in tables)
        t: (await store.readAll(t))..sort((a, b) => '${a['id']}'.compareTo('${b['id']}')),
    };
  }

  List<(Op, int)> randomOps(Random r) {
    final ids = ['a', 'b', 'c', 'd'];
    final nodes = ['n1', 'n2', 'n3'];
    final out = <(Op, int)>[];
    var seq = 0;
    for (var i = 0; i < 60; i++) {
      final table = tables[r.nextInt(tables.length)];
      final hlc = Hlc(1000 + r.nextInt(12), r.nextInt(2), nodes[r.nextInt(nodes.length)]).pack();
      final Map<String, Object?> fields = switch (table) {
        'events' => {
            if (r.nextBool()) 'title': 'T${r.nextInt(5)}',
            if (r.nextBool()) 'start_ms': r.nextInt(1 << 30) * 1000 + r.nextInt(1000),
            if (r.nextInt(4) == 0) 'all_day': r.nextBool(),
            if (r.nextInt(6) == 0) 'not_a_column': 1,
          },
        'list_items' => {
            if (r.nextBool()) 'text': 'I${r.nextInt(5)}',
            if (r.nextBool()) 'checked': r.nextBool(),
            if (r.nextBool()) 'qty': r.nextDouble() * 4,
          },
        'ledger_entries' => {'delta': r.nextInt(5) - 2, 'reason': 'r${r.nextInt(3)}'},
        _ => {if (r.nextBool()) 'body': 'B${r.nextInt(5)}', if (r.nextBool()) 'pinned': r.nextBool()},
      };
      final kind = table == 'ledger_entries' ? OpKind.insertOnly : (r.nextInt(7) == 0 ? OpKind.delete : OpKind.upsert);
      final op = Op(id: 'op$i', table: table, rowId: ids[r.nextInt(ids.length)], kind: kind, fields: kind == OpKind.delete ? const {} : fields, hlc: hlc);
      seq += r.nextInt(3);
      out.add((op, seq));
      if (r.nextInt(8) == 0) out.add((op, seq + 1)); // duplicate delivery
    }
    return out;
  }

  for (var seed = 0; seed < 200; seed++) {
    test('bulk apply equals sequential apply (seed $seed)', () async {
      final r = Random(seed);
      final ops = randomOps(r);
      final a = DearthDb(NativeDatabase.memory());
      final b = DearthDb(NativeDatabase.memory());
      addTearDown(a.close);
      addTearDown(b.close);
      final sa = SyncStore(a), sb = SyncStore(b);

      var changedA = 0;
      for (final (op, seq) in ops) {
        if (await sa.applyOp(op, seq: seq)) changedA++;
      }
      // Bulk in 1–3 chunks, so rows also persist between bulk calls.
      var changedB = 0;
      var i = 0;
      while (i < ops.length) {
        final n = 1 + r.nextInt(ops.length - i);
        final chunk = ops.sublist(i, i + n);
        final seqs = {for (final (op, seq) in chunk) op: seq};
        changedB += await sb.applyOpsBulk([for (final (op, _) in chunk) op], seqOf: (op) => seqs[op]!);
        i += n;
      }
      expect(await dump(b), await dump(a));
      expect(changedB, changedA);
    });
  }

  test('replaceAll restores a snapshot in one batch, clearing other tables', () async {
    final db = DearthDb(NativeDatabase.memory());
    addTearDown(db.close);
    final store = SyncStore(db);
    await store.applyOp(Op(id: 'x', table: 'notes', rowId: 'n1', kind: OpKind.upsert, fields: const {'body': 'old'}, hlc: const Hlc(1, 0, 'a').pack()));
    await store.replaceAll({
      'events': [
        {'id': 'e1', 'title': 'Swim', 'all_day': 1, 'start_ms': 5, 'sync_clock': '{}', 'sync_hlc': 'h', 'sync_seq': 3, 'deleted': 0},
      ],
    });
    expect(await store.readAll('notes'), isEmpty);
    final ev = await db.select(db.events).getSingle();
    expect((ev.title, ev.allDay, ev.syncSeq), ('Swim', true, 3));
  });
}
