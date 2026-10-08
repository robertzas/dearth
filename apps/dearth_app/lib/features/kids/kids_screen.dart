import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/data/household.dart';
import '../../shared/face_photo.dart';
import '../calendar/views/kid_timeline.dart';
import 'grown_ups.dart';
import 'kid_widgets.dart';
import 'kids_data.dart';

/// Kids (SPEC §10.7): each kid's chart for today with rewards that fit their
/// stage, their routines, and the grown-ups' side.
class KidsScreen extends ConsumerWidget {
  const KidsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final tab = ref.watch(kidsTabProvider);
    final kids = ref.watch(kidsProvider);
    final kid = kids.where((k) => k.id == tab).firstOrNull;
    final tabs = DSegmented<String>(
      options: [for (final k in kids) (k.id, k.name), (kGrownUpsTab, 'Grown-ups')],
      value: tab,
      idPrefix: 'kids.tab',
      onChanged: (v) => showKidsTab(ref, v),
    );
    final header = DPageHeader(
      title: kid == null ? 'Grown-ups' : '${kid.name}’s day',
      subtitle: kid == null ? 'Approvals, rewards and household chores' : '${KidStage.label(kid.kidStage)} · ${buddyEmoji(kid.buddy)} ${_buddyName(kid.buddy)}',
      leading: kid == null ? null : ProfileAvatar(kid, size: 56 * t.scale),
      actions: t.isPhone ? const [] : [tabs],
    );
    return screenTid(
      'screen.kids',
      Padding(
        padding: EdgeInsets.fromLTRB(t.pageMargin, t.pageMargin, t.pageMargin, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            if (t.isPhone) ...[SizedBox(height: t.space.sm), Align(alignment: Alignment.centerLeft, child: tabs)],
            SizedBox(height: t.gutter),
            Expanded(child: kid == null ? const GrownUpsView() : _KidView(kid: kid)),
          ],
        ),
      ),
    );
  }

  static String _buddyName(String? id) => kBuddies.firstWhere((b) => b.$1 == id, orElse: () => kBuddies.first).$3;
}

class _KidView extends ConsumerWidget {
  const _KidView({required this.kid});
  final Profile kid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final routines = ref.watch(kidRoutinesTodayProvider(kid.id));
    final today = ref.watch(todayProvider);
    final size = MediaQuery.sizeOf(context);
    final wide = !t.isPhone && size.width > size.height && size.width > 1100 * t.scale;
    final gap = SizedBox(height: t.gutter);
    final routinesRow = routines.isEmpty
        ? null
        : Wrap(spacing: t.space.sm, runSpacing: t.space.sm, children: [for (final r in routines) RoutineTile(routine: r, kid: kid)]);
    // Their day in pictures (FR-CAL-10): what's next, without reading.
    final myDay = DCard(
      id: 'kids.myday',
      padding: EdgeInsets.all(t.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('My day', style: t.text.h2),
          SizedBox(height: t.space.sm),
          KidTimeline(kid: kid, date: today, compact: true),
        ],
      ),
    );
    final rewards = <Widget>[
      JarCard(kid: kid),
      gap,
      if (kid.kidStage != KidStage.little) ...[StarsCard(kid: kid), gap],
      StickersCard(kid: kid),
      gap,
      const FamilyJarCard(),
      gap,
    ];
    if (!wide) {
      return ListView(
        children: [
          myDay,
          gap,
          if (routinesRow != null) ...[routinesRow, gap],
          _Chart(kid: kid),
          gap,
          ...rewards,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            children: [
              myDay,
              gap,
              if (routinesRow != null) ...[routinesRow, gap],
              _Chart(kid: kid),
              gap,
            ],
          ),
        ),
        SizedBox(width: t.gutter),
        SizedBox(width: 380 * t.scale, child: ListView(children: rewards)),
      ],
    );
  }
}

/// Today's jobs as big picture cards: few and huge for Little, more for
/// older kids (SPEC §10.7.1).
class _Chart extends ConsumerWidget {
  const _Chart({required this.kid});
  final Profile kid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final chores = ref.watch(kidChoresTodayProvider(kid.id));
    if (chores.isEmpty) {
      return const DEmptyState(id: 'kids.chart.empty', emoji: '🌈', title: 'No jobs today', message: 'Time to play!');
    }
    final done = chores.where((c) => c.done && !c.waitingApproval).length;
    final maxCols = kid.kidStage == KidStage.little ? 4 : 6;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Today’s jobs', style: t.text.h2)),
            tid(
              'kids.chart.progress',
              Text(
                showsNumbers(kid) ? '$done of ${chores.length} done' : '${'⭐' * done}${'☆' * (chores.length - done)}',
                style: t.text.title.copyWith(color: t.colors.inkSecondary),
              ),
            ),
          ],
        ),
        SizedBox(height: t.space.md),
        LayoutBuilder(builder: (context, box) {
          final gap = t.space.md;
          final cols = math.max(1, math.min(maxCols, math.min(chores.length, (box.maxWidth / (200 * t.scale)).floor())));
          final w = ((box.maxWidth - gap * (cols - 1)) / cols).clamp(150 * t.scale, 340 * t.scale);
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [for (final c in chores) KidChoreCard(chore: c, kid: kid, width: w)],
          );
        }),
      ],
    );
  }
}
