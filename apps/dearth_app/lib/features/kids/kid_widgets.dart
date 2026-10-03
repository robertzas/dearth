import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/display_state.dart';
import '../../app/grown_up.dart';
import '../../core/data/household_data.dart';
import '../../core/providers.dart';
import 'celebration.dart';
import 'kids_data.dart';
import 'kids_ops.dart';
import 'routine_run.dart';
import 'sticker_book.dart';

/// Whether a kid's stage shows numbers (SPEC §10.7.1: Little sees none).
bool showsNumbers(Profile kid) => kid.kidStage != KidStage.little;

// ───────────────────────────────── Chores ──────────────────────────────────

/// "I did it!" (SPEC FR-KID-03): records the completion, celebrates, and
/// offers Undo for 30 s.
Future<void> completeChore(BuildContext context, WidgetRef ref, ChoreToday c, Profile kid) async {
  final w = ref.read(writerProvider);
  final db = ref.read(dbProvider);
  final clock = ref.read(appClockProvider);
  final toast = ref.read(toastProvider);
  final calm = ref.read(isNightTimeProvider);
  await w.commit(completeChoreOps(w.op, c, ledger: await ledgerFor(db, 'chore_instances', c.due.instanceId), actor: kid.id, nowMs: clock.nowMs()));
  if (!context.mounted) return;
  final chore = c.due.chore;
  celebrate(
    context,
    emoji: chore.emoji ?? '⭐',
    buddy: buddyEmoji(kid.buddy),
    message: chore.needsApproval ? 'Yay! Let’s show a grown-up!' : randomPraise(),
    calm: calm,
  );
  toast.show(
    '${chore.title}: done!',
    emoji: '✅',
    actionLabel: 'Undo',
    duration: const Duration(seconds: 30),
    onAction: () async => w.commit(undoChoreOps(w.op, c, ledger: await ledgerFor(db, 'chore_instances', c.due.instanceId), nowMs: clock.nowMs())),
  );
}

/// A grown-up approves a waiting completion (behind the PIN).
Future<void> approveChore(BuildContext context, WidgetRef ref, ChoreToday c) async {
  if (!await ensureGrownUp(context, ref, reason: 'Approve “${c.due.chore.title}”')) return;
  final w = ref.read(writerProvider);
  final db = ref.read(dbProvider);
  await w.commit(approveChoreOps(
    w.op,
    c,
    ledger: await ledgerFor(db, 'chore_instances', c.due.instanceId),
    approver: actorProfileId(ref.read(grownUpActorProvider)),
    nowMs: ref.read(appClockProvider).nowMs(),
  ));
  ref.read(toastProvider).show('Approved “${c.due.chore.title}”', emoji: '👍');
}

/// A big picture card for one of a kid's chores (SPEC FR-KID-01/03).
class KidChoreCard extends ConsumerWidget {
  const KidChoreCard({super.key, required this.chore, required this.kid, required this.width});
  final ChoreToday chore;
  final Profile kid;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final c = chore.due.chore;
    final waiting = chore.waitingApproval;
    final done = chore.done && !waiting;
    final canApprove = waiting && (ref.watch(grownUpUnlockedProvider) ?? true);
    final person = PersonColors.of(kid.color, t.colors);
    final bg = done ? t.colors.tintOf(t.colors.success, 0.16) : (waiting ? t.colors.tintOf(t.colors.warning, 0.2) : person.tint);
    final state = done ? 'done' : (waiting ? 'waiting for a grown-up' : 'tap when you did it');
    return SizedBox(
      width: width,
      child: DCard(
        id: 'kids.chore.${c.id}',
        semanticLabel: canApprove ? null : '${c.title}, $state',
        color: bg,
        padding: EdgeInsets.all(t.space.md),
        onTap: done || waiting ? null : () => completeChore(context, ref, chore, kid),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Opacity(opacity: done ? 0.55 : 1, child: DEmoji(c.emoji ?? '⭐', size: width * 0.42)),
                if (done)
                  Positioned(
                    right: -width * 0.04,
                    bottom: -width * 0.02,
                    child: Icon(Icons.check_circle_rounded, size: width * 0.2, color: t.colors.success),
                  ),
              ],
            ),
            SizedBox(height: t.space.sm),
            Text(c.title, style: t.text.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
            SizedBox(height: t.space.sm),
            if (canApprove)
              DButton(label: 'Approve', icon: Icons.thumb_up_alt_rounded, size: DButtonSize.sm, id: 'kids.approve.${c.id}', onPressed: () => approveChore(context, ref, chore))
            else
              Container(
                padding: EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.xs),
                decoration: BoxDecoration(
                  color: done || waiting ? Colors.transparent : person.solid,
                  borderRadius: t.radius.pill,
                ),
                child: Text(
                  done ? 'Done! 🎉' : (waiting ? 'Waiting for grown-up 👀' : 'I did it!'),
                  style: t.text.label.copyWith(color: done || waiting ? t.colors.inkSecondary : person.onSolid, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────── Routines ─────────────────────────────────

class RoutineTile extends StatelessWidget {
  const RoutineTile({super.key, required this.routine, required this.kid});
  final RoutineToday routine;
  final Profile kid;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = routine.routine;
    final total = routine.steps.length;
    return DCard(
      id: 'kids.routine.${r.id}',
      semanticLabel: '${r.title}, ${routine.done ? 'done' : '${routine.progress} of $total steps'}',
      padding: EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
      onTap: () => openRoutine(context, routine, kid),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DEmoji(r.emoji ?? '🌟', size: 40 * t.scale),
          SizedBox(width: t.space.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(r.title, style: t.text.bodyStrong),
              Text(routine.done ? 'All done! 🌟' : (routine.progress == 0 ? '$total steps' : '${routine.progress} of $total steps'), style: t.text.caption),
            ],
          ),
          SizedBox(width: t.space.md),
          DProgressRing(progress: total == 0 ? 0 : routine.progress / total, size: 34 * t.scale, color: routine.done ? t.colors.success : null),
        ],
      ),
    );
  }
}

// ──────────────────────────────── Reward jar ───────────────────────────────

/// Pom-poms fill a jar; a full jar opens a surprise (SPEC FR-KID-13).
class JarCard extends ConsumerWidget {
  const JarCard({super.key, required this.kid});
  final Profile kid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final tokens = ref.watch(balancesProvider(kid.id))[Currency.jar] ?? 0;
    final cap = ref.watch(jarCapacityProvider);
    final full = tokens >= cap;
    final left = cap - tokens;
    final caption = full
        ? 'The jar is full!'
        : (showsNumbers(kid) ? '$left more to a surprise' : (tokens >= cap * 0.7 ? 'Almost full!' : 'Keep going!'));
    return DCard(
      id: 'kids.jar',
      padding: EdgeInsets.all(t.space.md),
      child: Column(
        children: [
          Text('Reward jar', style: t.text.title),
          SizedBox(height: t.space.sm),
          SizedBox(
            height: 170 * t.scale,
            width: 140 * t.scale,
            child: RepaintBoundary(child: CustomPaint(painter: JarPainter(tokens: math.min(tokens, cap), capacity: cap, glass: t.colors.outline, lid: t.colors.inkTertiary))),
          ),
          SizedBox(height: t.space.sm),
          tid('kids.jar.status', Text(caption, style: t.text.body)),
          if (full) ...[
            SizedBox(height: t.space.sm),
            DButton(label: 'Open the surprise!', emoji: '🎁', id: 'kids.jar.open', onPressed: () => _open(context, ref, cap)),
          ],
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref, int cap) async {
    final surprises = [for (final r in ref.read(rewardsProvider).value ?? const <Reward>[]) if (r.kind == 'surprise') r];
    if (surprises.isEmpty) {
      ref.read(toastProvider).show('Add surprise rewards in Settings first', emoji: '🎁');
      return;
    }
    final reward = surprises[math.Random().nextInt(surprises.length)];
    final w = ref.read(writerProvider);
    await w.commit(openJarOps(w.op, profileId: kid.id, capacity: cap, reward: reward, nowMs: ref.read(appClockProvider).nowMs()));
    if (!context.mounted) return;
    await showSurprise(context, reward: reward, buddy: buddyEmoji(kid.buddy));
  }
}

/// The gift-box reveal (SPEC FR-KID-13): the box wobbles, then opens to the
/// reward with a big celebration.
Future<void> showSurprise(BuildContext context, {required Reward reward, required String buddy}) => showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, _, _) => _Surprise(reward: reward, buddy: buddy),
    );

class _Surprise extends StatefulWidget {
  const _Surprise({required this.reward, required this.buddy});
  final Reward reward;
  final String buddy;

  @override
  State<_Surprise> createState() => _SurpriseState();
}

class _SurpriseState extends State<_Surprise> with SingleTickerProviderStateMixin {
  late final AnimationController _wobble = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..forward().whenComplete(_reveal);
  bool _open = false;

  void _reveal() {
    if (!mounted) return;
    setState(() => _open = true);
    celebrate(context, emoji: widget.reward.emoji ?? '🎉', buddy: widget.buddy, message: widget.reward.title, big: true);
  }

  @override
  void dispose() {
    _wobble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Center(
      child: tid(
        'kids.surprise',
        Material(
          color: t.colors.surfaceRaised,
          borderRadius: BorderRadius.circular(t.radius.xl),
          child: Padding(
            padding: EdgeInsets.all(t.space.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: t.motion(DMotion.emphasized),
                  child: _open
                      ? DEmoji(widget.reward.emoji ?? '🎉', size: 150 * t.scale, key: const ValueKey('open'))
                      : AnimatedBuilder(
                          key: const ValueKey('box'),
                          animation: _wobble,
                          builder: (context, child) => Transform.rotate(angle: math.sin(_wobble.value * math.pi * 10) * 0.15 * (_wobble.value), child: child),
                          child: DEmoji('🎁', size: 150 * t.scale),
                        ),
                ),
                SizedBox(height: t.space.md),
                Text(_open ? widget.reward.title : 'What’s inside?', style: t.text.kidTitle, textAlign: TextAlign.center),
                SizedBox(height: t.space.lg),
                DButton(label: _open ? 'Yay!' : 'Opening…', id: 'kids.surprise.close', onPressed: _open ? () => Navigator.of(context).pop() : null),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A glass jar with [tokens] colorful pom-poms out of [capacity].
class JarPainter extends CustomPainter {
  JarPainter({required this.tokens, required this.capacity, required this.glass, required this.lid});
  final int tokens;
  final int capacity;
  final Color glass;
  final Color lid;

  static const _pom = [Color(0xFFFF6B6B), Color(0xFFFFC145), Color(0xFF4ECDC4), Color(0xFF5B5BD6), Color(0xFFFF8FD8), Color(0xFF7ED957)];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.08, h * 0.16, w * 0.84, h * 0.82), Radius.circular(w * 0.16));
    final neck = RRect.fromRectAndRadius(Rect.fromLTWH(w * 0.22, h * 0.02, w * 0.56, h * 0.14), Radius.circular(w * 0.05));
    canvas.drawRRect(body, Paint()..color = glass.withValues(alpha: 0.25));
    // Pom-poms settle from the bottom up in a loose grid.
    const cols = 4;
    final rows = (capacity / cols).ceil();
    final r = math.min(body.width / cols, body.height / rows) * 0.42;
    for (var i = 0; i < tokens; i++) {
      final row = i ~/ cols, col = i % cols;
      final jitter = (row.isOdd ? 0.5 : 0.0);
      final cx = body.left + (col + 0.5 + jitter * (col == cols - 1 ? -1 : 1) * 0.3) * body.width / cols;
      final cy = body.bottom - (row + 0.5) * (body.height / rows);
      canvas.drawCircle(Offset(cx, cy), r, Paint()..color = _pom[i % _pom.length]);
      canvas.drawCircle(Offset(cx - r * 0.3, cy - r * 0.3), r * 0.25, Paint()..color = Colors.white.withValues(alpha: 0.35));
    }
    canvas.drawRRect(body, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, w * 0.025)
      ..color = glass);
    canvas.drawRRect(neck, Paint()..color = lid);
  }

  @override
  bool shouldRepaint(JarPainter old) => old.tokens != tokens || old.capacity != capacity || old.glass != glass || old.lid != lid;
}

// ──────────────────────────────── Stars & goal ─────────────────────────────

/// The star bank with a pinned goal (SPEC FR-KID-14), for Preschool and up.
class StarsCard extends ConsumerWidget {
  const StarsCard({super.key, required this.kid});
  final Profile kid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final stars = ref.watch(balancesProvider(kid.id))[Currency.star] ?? 0;
    final goal = ref.watch(kidGoalProvider(kid.id));
    final pending = (ref.watch(redemptionsProvider).value ?? const <Redemption>[]).where((r) => r.profileId == kid.id && r.status == 'pending').toList();
    final progress = goal == null || goal.cost <= 0 ? 0.0 : (stars / goal.cost).clamp(0.0, 1.0);
    return DCard(
      id: 'kids.stars',
      padding: EdgeInsets.all(t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DAvatar(colorIndex: kid.color, emoji: kid.emoji, name: kid.name, size: 64 * t.scale, progress: progress),
              SizedBox(width: t.space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    tid('kids.stars.count', Text('⭐ $stars star${stars == 1 ? '' : 's'}', style: t.text.title)),
                    if (goal != null) Text('Goal: ${goal.emoji ?? ''} ${goal.title} (${goal.cost})', style: t.text.caption),
                  ],
                ),
              ),
            ],
          ),
          if (goal != null) ...[
            SizedBox(height: t.space.sm),
            if (pending.any((p) => p.rewardId == goal.id))
              Text('Asked a grown-up for ${goal.title} 👀', style: t.text.body)
            else if (stars >= goal.cost)
              DButton(
                label: 'Ask for ${goal.title}',
                emoji: goal.emoji,
                id: 'kids.stars.redeem',
                onPressed: () {
                  final w = ref.read(writerProvider);
                  w.commit(requestRewardOps(w.op, reward: goal, profileId: kid.id, nowMs: ref.read(appClockProvider).nowMs()));
                  celebrate(context, emoji: goal.emoji ?? '🎉', buddy: buddyEmoji(kid.buddy), message: 'Let’s ask a grown-up!');
                },
              )
            else
              Text('${goal.cost - stars} more star${goal.cost - stars == 1 ? '' : 's'} to go', style: t.text.body),
          ],
        ],
      ),
    );
  }
}

// ──────────────────────────────── Stickers ─────────────────────────────────

class StickersCard extends ConsumerWidget {
  const StickersCard({super.key, required this.kid});
  final Profile kid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final placed = ref.watch(stickerPlacementsProvider(kid.id)).value ?? const <StickerPlacement>[];
    final toPlace = stickersToPlace(ref.watch(balancesProvider(kid.id)), placed.length);
    final theme = kStickerThemes[ref.watch(stickerThemeProvider(kid.id))]!;
    return DCard(
      id: 'kids.stickers',
      semanticLabel: toPlace > 0 ? 'Sticker book, $toPlace to place' : 'Sticker book',
      padding: EdgeInsets.all(t.space.md),
      onTap: () => openStickerBook(context, kid),
      child: Row(
        children: [
          DEmoji(theme.$3.first, size: 48 * t.scale),
          SizedBox(width: t.space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sticker book', style: t.text.title),
                Text(toPlace > 0 ? 'A new sticker to place! ✨' : '${theme.$1} · ${placed.length} placed', style: t.text.caption),
              ],
            ),
          ),
          if (toPlace > 0)
            Container(
              padding: EdgeInsets.all(t.space.xs),
              decoration: BoxDecoration(color: t.colors.accent, shape: BoxShape.circle),
              child: Text('$toPlace', style: t.text.label.copyWith(color: t.colors.onAccent, fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }
}

// ──────────────────────────────── Family jar ───────────────────────────────

/// Everyone's completions fill one jar toward a family reward
/// (SPEC FR-KID-15).
class FamilyJarCard extends ConsumerWidget {
  const FamilyJarCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final goal = ref.watch(familyGoalProvider);
    if (goal == null) return const SizedBox.shrink();
    final drops = ref.watch(balancesProvider(null))[Currency.family] ?? 0;
    final progress = goal.cost <= 0 ? 1.0 : (drops / goal.cost).clamp(0.0, 1.0);
    return DCard(
      id: 'kids.family',
      semanticLabel: 'Family goal: ${goal.title}, $drops of ${goal.cost}',
      padding: EdgeInsets.all(t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DEmoji(goal.emoji ?? '🏆', size: 40 * t.scale),
              SizedBox(width: t.space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Family goal', style: t.text.overline.copyWith(color: t.colors.inkSecondary)),
                    Text(goal.title, style: t.text.title),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: t.space.sm),
          ClipRRect(
            borderRadius: t.radius.pill,
            child: SizedBox(
              height: 14 * t.scale,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: t.colors.surfaceSunken),
                  FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: progress, child: ColoredBox(color: t.colors.success)),
                ],
              ),
            ),
          ),
          SizedBox(height: t.space.xs),
          Text('$drops of ${goal.cost} · every job anyone does counts', style: t.text.caption),
        ],
      ),
    );
  }
}
