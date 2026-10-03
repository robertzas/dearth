import 'package:dearth_app/core/data/household_data.dart' show ChoreToday;
import 'package:dearth_app/features/calendar/event_ops.dart' show MakeOp;
import 'package:dearth_app/features/kids/kids_ops.dart';
import 'package:dearth_core/dearth_core.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Chores, rewards and routines (SPEC §10.7) through a real device database:
/// grants are append-only, idempotent and converge across devices.
void main() {
  late DearthDb db;
  late Mutator m;
  const today = LocalDate(2026, 10, 3);
  const ava = 'p-ava';

  MakeOp op() => (table, id, fields, {kind = OpKind.upsert}) => m.makeOp(table, id, fields, kind: kind);
  Future<List<LedgerEntry>> ledger() => db.select(db.ledgerEntries).get();
  Future<Map<String, int>> balance(String? who) async => balances(await ledger(), who);

  Future<Chore> chore(String id, {List<String> who = const [ava], bool approval = false, bool adult = false}) async {
    await m.commit([
      op()('chores', id, {'title': id, 'emoji': '🧸', 'assignees': who, 'rrule': 'FREQ=DAILY', 'anchor_date': '2026-09-01', 'needs_approval': approval, 'adult': adult, 'stars': adult ? 0 : 1}),
    ]);
    return (db.select(db.chores)..where((c) => c.id.equals(id))).getSingle();
  }

  /// Today's due item for [c] with its current instance row.
  Future<ChoreToday> today_(Chore c, {String? profileId = ava}) async {
    final due = DueChore(c, today, profileId);
    final inst = await (db.select(db.choreInstances)..where((i) => i.id.equals(due.instanceId))).getSingleOrNull();
    return ChoreToday(due, inst);
  }

  setUp(() {
    db = DearthDb(NativeDatabase.memory());
    m = Mutator(store: SyncStore(db), clock: HlcClock('test'), sink: (_) async {});
  });

  tearDown(() => db.close());

  group('FR-KID-03: completing chores', () {
    test('“I did it!” marks it done and grants star, jar, sticker and a family drop', () async {
      final c = await chore('toys');
      await m.commit(completeChoreOps(op(), await today_(c), ledger: await ledger(), actor: ava, nowMs: 1));
      final t = await today_(c);
      expect((t.status, t.done, t.waitingApproval), (ChoreStatus.done, true, false));
      expect(await balance(ava), {Currency.star: 1, Currency.jar: 1, Currency.sticker: 1});
      expect(await balance(null), {Currency.family: 1});
    });

    test('a double tap (or a second device) never grants twice', () async {
      final c = await chore('toys');
      final first = completeChoreOps(op(), await today_(c), ledger: const [], actor: ava, nowMs: 1);
      // Another device completes offline from the same (empty) ledger.
      final second = completeChoreOps(op(), await today_(c), ledger: const [], actor: ava, nowMs: 2);
      await m.commit(first);
      await m.commit(second);
      await m.commit(completeChoreOps(op(), await today_(c), ledger: await ledger(), actor: ava, nowMs: 3));
      expect((await balance(ava))[Currency.star], 1);
      expect((await balance(null))[Currency.family], 1);
    });

    test('undo balances the grants; doing it again grants afresh', () async {
      final c = await chore('toys');
      await m.commit(completeChoreOps(op(), await today_(c), ledger: await ledger(), actor: ava, nowMs: 1));
      await m.commit(undoChoreOps(op(), await today_(c), ledger: await ledger(), nowMs: 2));
      expect((await today_(c)).status, ChoreStatus.pending);
      expect((await balance(ava)).values.every((v) => v == 0), isTrue);
      expect((await balance(null))[Currency.family], 0);
      expect((await ledger()).length, 8, reason: 'append-only: 4 grants + 4 reversals');
      await m.commit(completeChoreOps(op(), await today_(c), ledger: await ledger(), actor: ava, nowMs: 3));
      expect(await balance(ava), {Currency.star: 1, Currency.jar: 1, Currency.sticker: 1});
    });

    test('approval-required chores wait, then grant on approval', () async {
      final c = await chore('potty', approval: true);
      await m.commit(completeChoreOps(op(), await today_(c), ledger: await ledger(), actor: ava, nowMs: 1));
      final waiting = await today_(c);
      expect(waiting.waitingApproval, isTrue);
      expect(await ledger(), isEmpty);
      await m.commit(approveChoreOps(op(), waiting, ledger: await ledger(), approver: 'p-mom', nowMs: 2));
      final approved = await today_(c);
      expect((approved.status, approved.instance?.approvedBy, approved.waitingApproval), (ChoreStatus.approved, 'p-mom', false));
      expect((await balance(ava))[Currency.star], 1);
    });

    test('Anyone-pool chores reward whoever did them; adults fill only the family jar', () async {
      final pool = await chore('napkins', who: const []);
      await m.commit(completeChoreOps(op(), await today_(pool, profileId: null), ledger: await ledger(), actor: ava, nowMs: 1));
      expect((await today_(pool, profileId: null)).instance?.completedBy, ava);
      expect((await balance(ava))[Currency.star], 1);

      final trash = await chore('trash', who: const ['p-dad'], adult: true);
      await m.commit(completeChoreOps(op(), await today_(trash, profileId: 'p-dad'), ledger: await ledger(), actor: 'p-dad', nowMs: 2));
      expect(await balance('p-dad'), isEmpty);
      expect((await balance(null))[Currency.family], 2);
    });
  });

  group('FR-KID-12..15: rewards', () {
    test('stickers to place are earned minus placed; placing takes nothing away', () async {
      expect(stickersToPlace({Currency.sticker: 6}, 5), 1);
      expect(stickersToPlace({Currency.sticker: 2}, 5), 0);
      await m.commit(placeStickerOps(op(), profileId: ava, sticker: '🐮', x: 1.4, y: -0.2, nowMs: 1, id: 's1'));
      final s = await (db.select(db.stickerPlacements)).getSingle();
      expect((s.sticker, s.x, s.y), ('🐮', 1.0, 0.0), reason: 'positions are clamped to the scene');
      expect(await ledger(), isEmpty);
    });

    test('opening the jar spends its tokens on the revealed surprise', () async {
      await m.commit([op()('ledger_entries', 'g', {'profile_id': ava, 'currency': Currency.jar, 'delta': 10}, kind: OpKind.insertOnly)]);
      await m.commit([op()('rewards', 'rw-park', {'title': 'Park trip', 'kind': 'surprise', 'currency': 'jar', 'cost': 0})]);
      final park = await (db.select(db.rewards)).getSingle();
      await m.commit(openJarOps(op(), profileId: ava, capacity: 10, reward: park, nowMs: 1, id: 'open1'));
      expect((await balance(ava))[Currency.jar], 0);
      expect((await ledger()).firstWhere((e) => e.id == 'open1').note, 'Park trip');
    });

    test('a redemption spends stars only when a grown-up says yes', () async {
      await m.commit([
        op()('ledger_entries', 'g', {'profile_id': ava, 'currency': Currency.star, 'delta': 6}, kind: OpKind.insertOnly),
        op()('rewards', 'rw-story', {'title': 'Extra story', 'kind': 'store', 'currency': 'star', 'cost': 5}),
      ]);
      final story = await (db.select(db.rewards)).getSingle();
      await m.commit(requestRewardOps(op(), reward: story, profileId: ava, nowMs: 1, id: 'r1'));
      await m.commit(requestRewardOps(op(), reward: story, profileId: ava, nowMs: 2, id: 'r2'));
      final reqs = await (db.select(db.redemptions)..orderBy([(r) => OrderingTerm.asc(r.id)])).get();
      await m.commit(decideRedemptionOps(op(), reqs[0], approve: false, by: 'p-mom', currency: Currency.star, nowMs: 3));
      expect((await balance(ava))[Currency.star], 6);
      await m.commit(decideRedemptionOps(op(), reqs[1], approve: true, by: 'p-mom', currency: Currency.star, nowMs: 4));
      expect((await balance(ava))[Currency.star], 1);
      final decided = await (db.select(db.redemptions)..orderBy([(r) => OrderingTerm.asc(r.id)])).get();
      expect(decided.map((r) => r.status), ['declined', 'approved']);
    });
  });

  group('FR-KID-07: routines', () {
    test('progress is saved per step; finishing grants once', () async {
      await m.commit([op()('routines', 'rt', {'title': 'Bedtime', 'kind': 'bedtime', 'steps': const []})]);
      final r = await (db.select(db.routines)).getSingle();
      Future<RoutineRun?> run() => (db.select(db.routineRuns)).getSingleOrNull();
      await m.commit(routineProgressOps(op(), routine: r, date: today, profileId: ava, doneSteps: const ['a'], totalSteps: 2, ledger: await ledger(), nowMs: 1));
      expect((await run())?.status, 'running');
      expect(await ledger(), isEmpty);
      for (var i = 0; i < 2; i++) {
        await m.commit(routineProgressOps(op(), routine: r, date: today, profileId: ava, doneSteps: const ['a', 'b'], totalSteps: 2, existing: await run(), ledger: await ledger(), nowMs: 2));
      }
      final done = await run();
      expect((done?.status, done?.startedMs, done?.id), ('done', 1, routineRunId('rt', today, ava)));
      expect((await balance(ava))[Currency.star], 1);
      expect((await balance(null))[Currency.family], 1);
    });
  });
}
