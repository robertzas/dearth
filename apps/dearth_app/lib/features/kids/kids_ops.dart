import 'package:dearth_core/dearth_core.dart';

import '../../core/data/household_data.dart' show ChoreToday;
import '../calendar/event_ops.dart' show MakeOp;

/// Kids' chores, rewards and routines as ops (SPEC §10.7). The ledger is
/// append-only (AGENTS.md rule 4): grants are insert-only rows with stable
/// ids, and an undo appends compensating entries instead of deleting.

const String _choreRef = 'chore_instances';
const String _routineRef = 'routine_runs';

/// What one completion earns (SPEC FR-KID-01/13/14/15): the chore's stars,
/// jar tokens and a sticker for the kid who did it, and a drop in the family
/// jar for every completion, adults' included.
List<(String? profileId, String currency, int delta)> choreRewards(Chore chore, {required String? doer}) => [
      if (!chore.adult && doer != null) ...[
        if (chore.stars > 0) (doer, Currency.star, chore.stars),
        if (chore.jar > 0) (doer, Currency.jar, chore.jar),
        if (chore.sticker) (doer, Currency.sticker, 1),
      ],
      (null, Currency.family, 1),
    ];

Iterable<LedgerEntry> _refs(List<LedgerEntry> ledger, String refTable, String refId) =>
    ledger.where((e) => !e.deleted && e.refTable == refTable && e.refId == refId);

/// Grants for [refTable]/[refId] that aren't already on the ledger. Ids count
/// earlier entries per currency, so two devices granting the same completion
/// offline produce the same row (insert-only: first writer wins), and a
/// re-completion after an undo gets a fresh one.
List<Op> _grants(
  MakeOp op,
  List<(String?, String, int)> rewards, {
  required String refTable,
  required String refId,
  required List<LedgerEntry> ledger,
  required String reason,
  required String? by,
  required int nowMs,
  String? note,
}) {
  final mine = _refs(ledger, refTable, refId).toList();
  return [
    for (final (pid, currency, delta) in rewards)
      if (mine.where((e) => e.currency == currency).fold<int>(0, (a, e) => a + e.delta) <= 0)
        op(
          'ledger_entries',
          grantLedgerId(refTable, refId, currency, mine.where((e) => e.currency == currency).length),
          {
            'profile_id': pid,
            'currency': currency,
            'delta': delta,
            'reason': reason,
            'ref_table': refTable,
            'ref_id': refId,
            'at_ms': nowMs,
            'by_profile_id': by,
            'note': note,
          },
          kind: OpKind.insertOnly,
        ),
  ];
}

/// The person a completion counts for: the assignee, or whoever did an
/// Anyone-pool chore.
String? doerOf(ChoreToday c, String? actor) => c.due.profileId ?? actor;

/// "I did it!" (SPEC FR-KID-03). Rewards are granted now, or on approval
/// when the chore needs a grown-up's OK.
List<Op> completeChoreOps(MakeOp op, ChoreToday c, {required List<LedgerEntry> ledger, String? actor, required int nowMs}) {
  final d = c.due;
  final doer = doerOf(c, actor);
  return [
    op(_choreRef, d.instanceId, {
      'chore_id': d.chore.id,
      'date': d.date.iso,
      'profile_id': d.profileId,
      'status': ChoreStatus.done,
      'completed_ms': nowMs,
      'completed_by': doer,
      'approved_by': null,
      'deleted': false,
    }),
    if (!d.chore.needsApproval)
      ..._grants(op, choreRewards(d.chore, doer: doer), refTable: _choreRef, refId: d.instanceId, ledger: ledger, reason: 'chore', by: doer, nowMs: nowMs, note: d.chore.title),
  ];
}

/// A grown-up approves a waiting completion (SPEC FR-KID-03).
List<Op> approveChoreOps(MakeOp op, ChoreToday c, {required List<LedgerEntry> ledger, required String? approver, required int nowMs}) {
  final d = c.due;
  final doer = c.instance?.completedBy ?? d.profileId;
  return [
    op(_choreRef, d.instanceId, {'status': ChoreStatus.approved, 'approved_by': approver}),
    ..._grants(op, choreRewards(d.chore, doer: doer), refTable: _choreRef, refId: d.instanceId, ledger: ledger, reason: 'chore', by: approver, nowMs: nowMs, note: d.chore.title),
  ];
}

/// Undo (SPEC FR-KID-03, within 30 s): back to pending, and whatever the
/// completion granted is balanced by compensating entries.
List<Op> undoChoreOps(MakeOp op, ChoreToday c, {required List<LedgerEntry> ledger, required int nowMs}) {
  final id = c.due.instanceId;
  final mine = _refs(ledger, _choreRef, id).toList();
  final net = <(String?, String), int>{};
  for (final e in mine) {
    net[(e.profileId, e.currency)] = (net[(e.profileId, e.currency)] ?? 0) + e.delta;
  }
  final count = <String, int>{};
  for (final e in mine) {
    count[e.currency] = (count[e.currency] ?? 0) + 1;
  }
  return [
    op(_choreRef, id, {'status': ChoreStatus.pending, 'completed_ms': null, 'completed_by': null, 'approved_by': null}),
    for (final MapEntry(key: (pid, currency), value: delta) in net.entries)
      if (delta > 0)
        op(
          'ledger_entries',
          grantLedgerId(_choreRef, id, currency, count[currency]!),
          {'profile_id': pid, 'currency': currency, 'delta': -delta, 'reason': 'undo', 'ref_table': _choreRef, 'ref_id': id, 'at_ms': nowMs},
          kind: OpKind.insertOnly,
        ),
  ];
}

/// Stickers still to place: earned minus placed. Placing never takes
/// anything away (SPEC FR-KID-21: no loss mechanics).
int stickersToPlace(Map<String, int> balance, int placed) => ((balance[Currency.sticker] ?? 0) - placed).clamp(0, 1 << 30);

/// Puts a chosen sticker on the book's scene (SPEC FR-KID-12). Positions are
/// fractions of the scene so every screen size shows the same page.
List<Op> placeStickerOps(MakeOp op, {required String profileId, required String sticker, required double x, required double y, int page = 0, double scale = 1, double rotation = 0, required int nowMs, String? id}) => [
      op('sticker_placements', id ?? newId(), {
        'profile_id': profileId,
        'page': page,
        'sticker': sticker,
        'x': x.clamp(0.0, 1.0),
        'y': y.clamp(0.0, 1.0),
        'scale': scale,
        'rotation': rotation,
        'at_ms': nowMs,
      }),
    ];

/// Opens a full reward jar (SPEC FR-KID-13): the tokens become the revealed
/// surprise, recorded on the ledger with what it was.
List<Op> openJarOps(MakeOp op, {required String profileId, required int capacity, required Reward reward, required int nowMs, String? id}) => [
      op(
        'ledger_entries',
        id ?? newId(),
        {'profile_id': profileId, 'currency': Currency.jar, 'delta': -capacity, 'reason': 'jar_reveal', 'ref_table': 'rewards', 'ref_id': reward.id, 'at_ms': nowMs, 'note': reward.title},
        kind: OpKind.insertOnly,
      ),
    ];

/// A kid asks for a store reward (SPEC FR-KID-14); a grown-up decides.
List<Op> requestRewardOps(MakeOp op, {required Reward reward, required String profileId, required int nowMs, String? id}) => [
      op('redemptions', id ?? newId(), {'reward_id': reward.id, 'profile_id': profileId, 'cost': reward.cost, 'status': 'pending', 'requested_ms': nowMs}),
    ];

/// Approving spends the stars; declining spends nothing.
List<Op> decideRedemptionOps(MakeOp op, Redemption r, {required bool approve, required String? by, required String currency, required int nowMs}) => [
      op('redemptions', r.id, {'status': approve ? 'approved' : 'declined', 'decided_by': by, 'decided_ms': nowMs}),
      if (approve && r.cost > 0)
        op(
          'ledger_entries',
          stableId('redeem', [r.id]),
          {'profile_id': r.profileId, 'currency': currency, 'delta': -r.cost, 'reason': 'redeem', 'ref_table': 'redemptions', 'ref_id': r.id, 'at_ms': nowMs, 'by_profile_id': by},
          kind: OpKind.insertOnly,
        ),
    ];

/// Records routine progress (SPEC FR-KID-07). Finishing earns a star and a
/// family drop, once per run.
List<Op> routineProgressOps(
  MakeOp op, {
  required Routine routine,
  required LocalDate date,
  required String? profileId,
  required List<String> doneSteps,
  required int totalSteps,
  RoutineRun? existing,
  required List<LedgerEntry> ledger,
  required int nowMs,
}) {
  final id = routineRunId(routine.id, date, profileId);
  final complete = totalSteps > 0 && doneSteps.length >= totalSteps;
  return [
    op(_routineRef, id, {
      'routine_id': routine.id,
      'date': date.iso,
      'profile_id': profileId,
      'done_steps': doneSteps,
      'status': complete ? 'done' : 'running',
      'started_ms': existing?.startedMs ?? nowMs,
      'completed_ms': complete ? nowMs : null,
      'deleted': false,
    }),
    if (complete)
      ..._grants(
        op,
        [if (profileId != null) (profileId, Currency.star, 1), (null, Currency.family, 1)],
        refTable: _routineRef,
        refId: id,
        ledger: ledger,
        reason: 'routine',
        by: profileId,
        nowMs: nowMs,
        note: routine.title,
      ),
  ];
}
