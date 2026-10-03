import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/grown_up.dart';
import '../../core/data/household.dart';
import '../../core/data/household_data.dart';
import '../../core/providers.dart';
import 'kid_widgets.dart';
import 'kids_data.dart';
import 'kids_ops.dart';

/// The grown-ups' side (SPEC FR-KID-03/05/14): completions and reward
/// requests waiting for a decision, then today's household chores with
/// "Anyone" chores claimable.
class GrownUpsView extends ConsumerWidget {
  const GrownUpsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final waiting = ref.watch(waitingApprovalProvider);
    final rewards = {for (final r in ref.watch(rewardsProvider).value ?? const <Reward>[]) r.id: r};
    final requests = [
      for (final r in ref.watch(redemptionsProvider).value ?? const <Redemption>[])
        if (r.status == 'pending') r,
    ];
    final people = ref.watch(profileMapProvider);
    final chores = ref.watch(adultChoresTodayProvider);
    final gap = SizedBox(height: t.gutter);
    return ListView(
      children: [
        if (waiting.isNotEmpty || requests.isNotEmpty) ...[
          DSection(
            id: 'grownups.waiting',
            title: 'Waiting for you',
            child: Column(
              children: [
                for (final c in waiting)
                  DListRow(
                    id: 'grownups.approve.${c.due.chore.id}',
                    leading: DEmoji(c.due.chore.emoji ?? '⭐', size: 36 * t.scale),
                    title: c.due.chore.title,
                    subtitle: '${people[c.instance?.completedBy ?? c.due.profileId]?.name ?? 'Someone'} says it’s done',
                    trailing: DButton(label: 'Approve', size: DButtonSize.sm, onPressed: () => approveChore(context, ref, c)),
                  ),
                for (final r in requests)
                  DListRow(
                    id: 'grownups.request.${r.id}',
                    leading: DEmoji(rewards[r.rewardId]?.emoji ?? '🎁', size: 36 * t.scale),
                    title: rewards[r.rewardId]?.title ?? 'A reward',
                    subtitle: '${people[r.profileId]?.name ?? 'Someone'} asks · ${r.cost} ⭐',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DButton(label: 'Not now', tone: DButtonTone.ghost, size: DButtonSize.sm, onPressed: () => _decide(context, ref, r, approve: false)),
                        SizedBox(width: t.space.xs),
                        DButton(label: 'Yes!', size: DButtonSize.sm, onPressed: () => _decide(context, ref, r, approve: true)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          gap,
        ],
        DSection(
          id: 'grownups.chores',
          title: 'Household chores today',
          child: chores.isEmpty
              ? Text('Nothing due today.', style: t.text.body.copyWith(color: t.colors.inkSecondary))
              : Column(children: [for (final c in chores) _AdultChoreRow(chore: c)]),
        ),
        gap,
        const FamilyJarCard(),
        gap,
      ],
    );
  }

  Future<void> _decide(BuildContext context, WidgetRef ref, Redemption r, {required bool approve}) async {
    if (!await ensureGrownUp(context, ref, reason: approve ? 'Say yes to a reward' : 'Decline a reward')) return;
    final w = ref.read(writerProvider);
    final reward = (ref.read(rewardsProvider).value ?? const <Reward>[]).where((x) => x.id == r.rewardId).firstOrNull;
    await w.commit(decideRedemptionOps(
      w.op,
      r,
      approve: approve,
      by: actorProfileId(ref.read(grownUpActorProvider)),
      currency: reward?.currency ?? Currency.star,
      nowMs: ref.read(appClockProvider).nowMs(),
    ));
    ref.read(toastProvider).show(approve ? 'Enjoy ${reward?.title ?? 'the reward'}!' : 'Maybe next time', emoji: approve ? '🎉' : '👌');
  }
}

class _AdultChoreRow extends ConsumerWidget {
  const _AdultChoreRow({required this.chore});
  final ChoreToday chore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final c = chore.due.chore;
    final people = ref.watch(profileMapProvider);
    final who = chore.due.profileId == null ? null : people[chore.due.profileId];
    final doneBy = people[chore.instance?.completedBy];
    return DListRow(
      id: 'grownups.chore.${c.id}',
      leading: DEmoji(c.emoji ?? '🧹', size: 36 * t.scale),
      title: c.title,
      subtitle: chore.done ? 'Done${doneBy == null ? '' : ' by ${doneBy.name}'}' : (who == null ? 'Anyone · claim it' : who.name),
      trailing: Icon(
        chore.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
        color: chore.done ? t.colors.success : t.colors.inkTertiary,
        size: t.iconLg,
      ),
      onTap: () => _toggle(context, ref),
    );
  }

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final w = ref.read(writerProvider);
    final db = ref.read(dbProvider);
    final now = ref.read(appClockProvider).nowMs();
    final ledger = await ledgerFor(db, 'chore_instances', chore.due.instanceId);
    if (chore.done) {
      await w.commit(undoChoreOps(w.op, chore, ledger: ledger, nowMs: now));
      return;
    }
    // Anyone-pool chores are claimed by whoever is signed in as a grown-up.
    final actor = actorProfileId(ref.read(grownUpActorProvider));
    await w.commit(completeChoreOps(w.op, chore, ledger: ledger, actor: actor, nowMs: now));
    ref.read(toastProvider).show('${chore.due.chore.title}: done', emoji: '✅');
  }
}
