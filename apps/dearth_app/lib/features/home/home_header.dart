import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/grown_up.dart';
import '../../app/shell.dart' show syncLabel;
import '../../core/data/calendar.dart';
import '../../core/data/household.dart';
import '../../core/format.dart';
import '../../core/providers.dart';

/// Home header bar (SPEC FR-HOME-04): date, time, current weather with alert
/// badge, and a sync indicator only when degraded.
class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final today = ref.watch(todayProvider);
    final name = ref.watch(householdProvider.select((h) => h.value?.name));
    final hour = ref.watch(householdTimeProvider.select((ht) => ht.now().hour));
    final isDemo = ref.watch(sessionProvider.select((s) => s.isDemo));

    final dateBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        tid('home.date', Text(longDate(today), style: compact ? t.text.title : t.text.h2, maxLines: 1, overflow: TextOverflow.ellipsis)),
        SizedBox(height: t.space.xxs),
        Row(
          children: [
            Flexible(
              child: Text(
                '${greeting(hour)}${name == null || name.isEmpty ? '' : ', ${name.replaceFirst(RegExp(r'^The '), '')}'}',
                style: t.text.caption.copyWith(fontSize: (compact ? 15 : 18) * t.scale),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isDemo) ...[SizedBox(width: t.space.xs), const _DemoBadge()],
            const _SyncChip(),
            const _LockChip(),
          ],
        ),
      ],
    );

    if (compact) {
      return Row(
        children: [
          Expanded(child: dateBlock),
          SizedBox(width: t.space.sm),
          const HeaderWeather(compact: true),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: dateBlock),
        const HeaderClock(),
        const Expanded(child: Align(alignment: Alignment.centerRight, child: HeaderWeather())),
      ],
    );
  }
}

/// The big clock; repaints once a minute in its own layer.
class HeaderClock extends ConsumerWidget {
  const HeaderClock({super.key, this.style});
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    ref.watch(minuteProvider);
    final time = ref.watch(householdTimeProvider);
    final h24 = ref.watch(clock24Provider);
    final wall = time.wall(time.nowMs());
    final s = style ?? t.text.display;
    return RepaintBoundary(
      child: tid(
        'home.clock',
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(formatClock(wall, h24: h24), style: s),
            if (!h24) ...[
              SizedBox(width: t.space.xs),
              Text(formatMeridiem(wall), style: t.text.title.copyWith(color: t.colors.inkSecondary, fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Current conditions summary; taps through to the Weather screen.
class HeaderWeather extends ConsumerWidget {
  const HeaderWeather({super.key, this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final report = ref.watch(weatherProvider).value;
    final imperial = ref.watch(imperialProvider);
    final today = ref.watch(todayProvider);
    if (report == null || report.current == null) {
      return DPressable(
        id: 'home.weather',
        onTap: () => context.go('/weather'),
        child: Text('Weather appears here', style: t.text.caption),
      );
    }
    final now = report.current!;
    final day = report.dayFor(today.iso);
    final alerts = report.alerts.where((a) => a.endsMs == null || a.endsMs! > ref.read(appClockProvider).nowMs()).toList();
    final emojiSize = (compact ? 40 : 60) * t.scale;
    return DPressable(
      id: 'home.weather',
      semanticLabel: 'Weather',
      onTap: () => context.go('/weather'),
      borderRadius: t.radius.card,
      child: Padding(
        padding: EdgeInsets.all(t.space.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                DEmoji(conditionEmoji(now.condition, isDay: now.isDay), size: emojiSize),
                if (alerts.isNotEmpty)
                  Positioned(
                    right: -4 * t.scale,
                    top: -4 * t.scale,
                    child: tid(
                      'home.weather.alert',
                      Container(
                        padding: EdgeInsets.all(3 * t.scale),
                        decoration: BoxDecoration(color: t.colors.danger, shape: BoxShape.circle, border: Border.all(color: t.colors.surface, width: 2)),
                        child: Icon(Icons.priority_high_rounded, size: 14 * t.scale, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(width: t.space.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                tid('home.weather.temp', Text(formatTemp(now.tempC, imperial: imperial), style: compact ? t.text.h2 : t.text.h1.copyWith(fontWeight: FontWeight.w600))),
                if (day != null)
                  Text(
                    [
                      'H ${formatTemp(day.highC, imperial: imperial)}  L ${formatTemp(day.lowC, imperial: imperial)}',
                      if (!compact && (day.precipProb ?? 0) >= 10) '☂ ${day.precipProb!.round()}%',
                    ].join('  ·  '),
                    style: t.text.caption.copyWith(fontWeight: FontWeight.w700),
                  ),
                if (!compact)
                  Text(
                    alerts.isNotEmpty ? alerts.first.event : conditionLabel(now.condition),
                    style: t.text.caption.copyWith(color: alerts.isNotEmpty ? t.colors.danger : null, fontWeight: alerts.isNotEmpty ? FontWeight.w800 : null),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DemoBadge extends StatelessWidget {
  const _DemoBadge();

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return tid(
      'home.demo',
      Container(
        padding: EdgeInsets.symmetric(horizontal: t.space.xs, vertical: 2 * t.scale),
        decoration: BoxDecoration(color: t.colors.accentTint, borderRadius: t.radius.pill),
        child: Text('Demo', style: t.text.caption.copyWith(fontSize: 13 * t.scale, color: t.colors.isDark ? t.colors.inkPrimary : t.colors.accent, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _SyncChip extends ConsumerWidget {
  const _SyncChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(syncStateProvider).value;
    if (state == null || state.isHealthy) return const SizedBox.shrink();
    final t = DTheme.of(context);
    final pending = ref.watch(outboxCountProvider).value ?? 0;
    final (label, color) = syncLabel(state, t.colors);
    return Padding(
      padding: EdgeInsets.only(left: t.space.xs),
      child: tid(
        'home.sync',
        Container(
          padding: EdgeInsets.symmetric(horizontal: t.space.xs, vertical: 2 * t.scale),
          decoration: BoxDecoration(color: t.colors.tintOf(color), borderRadius: t.radius.pill),
          child: Text(
            pending > 0 ? '$label · $pending waiting' : label,
            style: t.text.caption.copyWith(fontSize: 13 * t.scale, color: color, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

/// Grown-up lock state (FR-HOME-04); hidden when no PIN is set or on
/// personal devices. Tap to lock or unlock.
class _LockChip extends ConsumerWidget {
  const _LockChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlocked = ref.watch(grownUpUnlockedProvider);
    if (unlocked == null || ref.watch(deviceSettingsProvider.select((s) => s.isPersonal))) return const SizedBox.shrink();
    final t = DTheme.of(context);
    final color = unlocked ? t.colors.warning : t.colors.inkSecondary;
    return Padding(
      padding: EdgeInsets.only(left: t.space.xs),
      child: DPressable(
        id: 'home.lock',
        semanticLabel: unlocked ? 'Grown-up mode unlocked. Tap to lock' : 'Locked. Tap for grown-up mode',
        excludeSemantics: true,
        onTap: () => unlocked ? ref.read(grownUpProvider.notifier).lock() : ensureGrownUp(context, ref),
        borderRadius: t.radius.pill,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: t.space.xs, vertical: 2 * t.scale),
          decoration: BoxDecoration(color: t.colors.tintOf(color), borderRadius: t.radius.pill),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(unlocked ? Icons.lock_open_rounded : Icons.lock_rounded, size: 14 * t.scale, color: color),
              SizedBox(width: 4 * t.scale),
              Text(unlocked ? 'Grown-up' : 'Locked', style: t.text.caption.copyWith(fontSize: 13 * t.scale, color: color, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

/// How many events today (for greetings and briefings).
final todayEventCountProvider = Provider<int>((ref) {
  final today = ref.watch(todayProvider);
  return ref.watch(occurrencesProvider(DayRange.single(today))).value?.length ?? 0;
});
