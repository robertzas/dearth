import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:drift/drift.dart' show BooleanExpressionOperators, OrderingTerm;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/display_state.dart';
import '../../app/router.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/sound.dart';

/// Kitchen timers that haven't been dismissed, in start order (FR-TMR-01).
final kitchenTimersProvider = StreamProvider<List<KitchenTimer>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.kitchenTimers)
        ..where((t) => t.deleted.equals(false) & t.status.isIn(const [TimerStatus.running, TimerStatus.paused]))
        ..orderBy([(t) => OrderingTerm.asc(t.startedMs)]))
      .watch();
});

/// The app clock, twice a second while a countdown is on screen.
final countdownClockProvider = StreamProvider.autoDispose<int>((ref) {
  final clock = ref.watch(appClockProvider);
  final out = StreamController<int>();
  out.add(clock.nowMs());
  final tick = Timer.periodic(const Duration(milliseconds: 500), (_) => out.add(clock.nowMs()));
  ref.onDispose(() {
    tick.cancel();
    out.close();
  });
  return out.stream;
});

/// Timers worth showing at [nowMs] (running, paused, or recently ended).
List<KitchenTimer> visibleTimers(List<KitchenTimer> all, int nowMs) => [for (final t in all) if (t.phase(nowMs) != TimerPhase.gone) t];

// ─────────────────────────────── Actions ────────────────────────────────────

/// Starts a synced kitchen timer: it rings on every display (FR-TMR-02).
Future<void> startKitchenTimer(WidgetRef ref, Duration length, {String? label, String kind = 'kitchen'}) {
  final name = (label?.trim().isNotEmpty ?? false) ? label!.trim() : '${formatTimerLength(length)} timer';
  return ref.read(writerProvider).create('kitchen_timers', startTimerFields(name, length, ref.read(appClockProvider).nowMs(), kind: kind));
}

Future<void> updateKitchenTimer(WidgetRef ref, KitchenTimer t, Map<String, Object?> Function(KitchenTimer t, int nowMs) change) =>
    ref.read(writerProvider).upsert('kitchen_timers', t.id, change(t, ref.read(appClockProvider).nowMs()));

/// Stops every timer that is ringing or sits finished.
Future<void> stopFinishedTimers(WidgetRef ref) {
  final w = ref.read(writerProvider);
  final now = ref.read(appClockProvider).nowMs();
  final done = [for (final t in ref.read(kitchenTimersProvider).value ?? const <KitchenTimer>[]) if (const {TimerPhase.ringing, TimerPhase.ended}.contains(t.phase(now))) t];
  return w.commit([for (final t in done) w.op('kitchen_timers', t.id, kDismissTimerFields)]);
}

int stepUpMinutes(int m) => m < 10 ? m + 1 : (m ~/ 5 + 1) * 5;
int stepDownMinutes(int m) => m <= 10 ? m - 1 : (m - 1) ~/ 5 * 5;

/// "5 min", "1 h 30 min"; seconds only for sub-minute timers.
String formatTimerLength(Duration d) => d.inSeconds < 60 ? '${d.inSeconds} s' : formatDuration(d.inMinutes);

// ─────────────────────────────── Alarm ──────────────────────────────────────

/// Rings finished timers on this display (FR-TMR-01): the chime right away
/// and then every 6 s, louder each time, for [kRingFor]; wakes the display
/// from the photo frame or night. Sleeps until the next timer ends rather
/// than polling. State: ids of the timers ringing now.
class TimerAlarm extends Notifier<Set<String>> {
  Timer? _next;
  Timer? _ring;
  int _rings = 0;

  @override
  Set<String> build() {
    ref.listen(kitchenTimersProvider, (_, _) => _evaluate());
    ref.onDispose(() {
      _next?.cancel();
      _ring?.cancel();
    });
    Future.microtask(_evaluate);
    return const {};
  }

  void _evaluate() {
    final timers = ref.read(kitchenTimersProvider).value;
    if (timers == null) return;
    final now = ref.read(appClockProvider).nowMs();
    final ringing = {for (final t in timers) if (t.phase(now) == TimerPhase.ringing) t.id};
    // Wake up at the next change: a timer ending, or one's ringing ending.
    final upcoming = [
      for (final t in timers)
        if (t.phase(now) == TimerPhase.running) t.endsAtMs! else if (t.phase(now) == TimerPhase.ringing) t.endsAtMs! + kRingFor.inMilliseconds,
    ];
    _next?.cancel();
    if (upcoming.isNotEmpty) _next = Timer(Duration(milliseconds: upcoming.reduce(math.min) - now + 20), _evaluate);

    if (ringing.difference(state).isNotEmpty) {
      // Something new finished: wake the display and (re)start the chimes.
      ref.read(displayProvider.notifier).wake();
      _rings = 0;
      _ring?.cancel();
      _chime();
      _ring = Timer.periodic(const Duration(seconds: 6), (_) => _chime());
    } else if (ringing.isEmpty) {
      _ring?.cancel();
      _ring = null;
    }
    if (!setEquals(ringing, state)) state = ringing;
  }

  void _chime() => unawaited(ref.read(soundProvider).play(Sfx.timer, volume: math.min(1, 0.45 + 0.11 * _rings++)));
}

final timerAlarmProvider = NotifierProvider<TimerAlarm, Set<String>>(TimerAlarm.new);

// ──────────────────────────────── Pill ──────────────────────────────────────

/// Opens the timers sheet on the app's Navigator (callers above it, like
/// the pill, have none of their own).
Future<void> showTimers(WidgetRef ref, [BuildContext? context]) async {
  ref.read(displayProvider.notifier).wake();
  final nav = context ?? ref.read(routerProvider).routerDelegate.navigatorKey.currentContext;
  if (nav == null) return;
  await showDSheet<void>(nav, title: 'Timers', id: 'timers.sheet', builder: (_) => const TimersPanel());
}

/// The floating pill (FR-TMR-01): the next timer to finish, on every
/// screen. It pulses while a timer rings, and then a tap stops it (wet
/// hands in a kitchen); otherwise a tap opens the timers. Lives in the shell
/// body, so sheets and dialogs cover it and it stays clear of the bars.
class TimerPill extends ConsumerWidget {
  const TimerPill({super.key, this.cornerClearance = 0});

  /// Extra lift off the bottom edge, where the body reaches the screen's
  /// bottom-right corner (a kiosk frame's magic corner).
  final double cornerClearance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(kitchenTimersProvider).value ?? const <KitchenTimer>[];
    if (all.isEmpty) return const SizedBox.shrink();
    return _Pill(cornerClearance: cornerClearance);
  }
}

class _Pill extends ConsumerStatefulWidget {
  const _Pill({required this.cornerClearance});
  final double cornerClearance;

  @override
  ConsumerState<_Pill> createState() => _PillState();
}

class _PillState extends ConsumerState<_Pill> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final c = t.colors;
    final now = ref.watch(countdownClockProvider).value ?? ref.read(appClockProvider).nowMs();
    final timers = visibleTimers(ref.watch(kitchenTimersProvider).value ?? const [], now);
    final finished = [for (final x in timers) if (const {TimerPhase.ringing, TimerPhase.ended}.contains(x.phase(now))) x];
    if (timers.isEmpty) return const SizedBox.shrink();
    final ringing = finished.isNotEmpty;
    if (ringing && !t.reducedMotion && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!ringing && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
    final next = ringing ? finished.first : (List.of(timers)..sort((a, b) => a.remainingMs(now).compareTo(b.remainingMs(now)))).first;
    final more = timers.length - 1;
    final color = ringing ? c.warning : c.accent;
    final label = ringing ? '${next.label} · done!' : '${next.label} · ${formatCountdown(next.remainingMs(now))}${next.phase(now) == TimerPhase.paused ? ' (paused)' : ''}';

    final pill = Container(
      padding: EdgeInsets.fromLTRB(t.space.xs, t.space.xs, t.space.md, t.space.xs),
      decoration: BoxDecoration(
        color: ringing ? c.warning : c.surfaceRaised,
        borderRadius: t.radius.pill,
        border: Border.all(color: color, width: 2 * t.scale),
        boxShadow: t.elevation.e2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DProgressRing(
            progress: next.progress(now),
            size: 40 * t.scale,
            color: ringing ? c.onAccent : color,
            child: Icon(ringing ? Icons.alarm_rounded : Icons.timer_rounded, size: 20 * t.scale, color: ringing ? c.onAccent : color),
          ),
          SizedBox(width: t.space.xs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.text.label.copyWith(fontWeight: FontWeight.w800, color: ringing ? c.onAccent : c.inkPrimary, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          if (more > 0) ...[
            SizedBox(width: t.space.xs),
            Text('+$more', style: t.text.caption.copyWith(fontWeight: FontWeight.w800, color: ringing ? c.onAccent : c.inkSecondary)),
          ],
          if (ringing) ...[SizedBox(width: t.space.xs), Text('Stop', style: t.text.label.copyWith(color: c.onAccent, fontWeight: FontWeight.w900))],
        ],
      ),
    );
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: EdgeInsets.fromLTRB(t.space.lg, t.space.lg, t.space.lg, t.space.lg + widget.cornerClearance),
        child: DPressable(
          id: 'timers.pill',
          onTap: ringing ? () => stopFinishedTimers(ref) : () => showTimers(ref, context),
          onLongPress: () => showTimers(ref, context),
          semanticLabel: ringing ? '${next.label} is done. Stop' : 'Timers: $label',
          excludeSemantics: true,
          borderRadius: t.radius.pill,
          child: RepaintBoundary(child: ScaleTransition(scale: Tween<double>(begin: 1, end: 1.07).animate(_pulse), child: pill)),
        ),
      ),
    );
  }
}

// ─────────────────────────────── Sheet ──────────────────────────────────────

/// Start timers from presets or a custom length, and run the ones going
/// (FR-TMR-01): a big ring each, pause/resume, one more minute, cancel.
class TimersPanel extends ConsumerStatefulWidget {
  const TimersPanel({super.key});

  @override
  ConsumerState<TimersPanel> createState() => _TimersPanelState();
}

class _TimersPanelState extends ConsumerState<TimersPanel> {
  final _label = TextEditingController();
  bool _custom = false;
  int _customMinutes = 20;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _start(Duration d) async {
    await startKitchenTimer(ref, d, label: _label.text);
    _label.clear();
    if (mounted) setState(() => _custom = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final now = ref.watch(countdownClockProvider).value ?? ref.read(appClockProvider).nowMs();
    final timers = visibleTimers(ref.watch(kitchenTimersProvider).value ?? const [], now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final x in timers) TimerRow(timer: x, nowMs: now),
        if (timers.isNotEmpty) SizedBox(height: t.space.md),
        Text('NEW TIMER', style: t.text.overline),
        SizedBox(height: t.space.xs),
        DTextField(id: 'timers.label', controller: _label, hint: 'What’s it for? (optional)', prefix: Icon(Icons.label_outline_rounded, color: t.colors.inkTertiary)),
        SizedBox(height: t.space.sm),
        Wrap(
          spacing: t.space.xs,
          runSpacing: t.space.xs,
          children: [
            for (final d in kTimerPresets) DChip(id: 'timers.preset.${d.inMinutes}', label: formatTimerLength(d), onTap: () => _start(d)),
            DChip(id: 'timers.custom', label: 'Custom…', selected: _custom, onTap: () => setState(() => _custom = !_custom)),
          ],
        ),
        if (_custom) ...[
          SizedBox(height: t.space.sm),
          Row(
            children: [
              DStepper(
                id: 'timers.custom.minutes',
                value: _customMinutes,
                max: 600,
                // One minute at a time up to 10, then fives.
                onChanged: (v) => setState(() => _customMinutes = v > _customMinutes ? stepUpMinutes(_customMinutes) : stepDownMinutes(_customMinutes)),
                format: (v) => formatTimerLength(Duration(minutes: v)),
              ),
              SizedBox(width: t.space.sm),
              DButton(label: 'Start', icon: Icons.play_arrow_rounded, id: 'timers.custom.start', onPressed: () => _start(Duration(minutes: _customMinutes))),
            ],
          ),
        ],
      ],
    );
  }
}

/// One running timer: a big ring with the time left, pause/resume, one more
/// minute, and cancel (or Stop once it rings).
class TimerRow extends ConsumerWidget {
  const TimerRow({super.key, required this.timer, required this.nowMs});
  final KitchenTimer timer;
  final int nowMs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final c = t.colors;
    final x = timer;
    final phase = x.phase(nowMs);
    final finished = phase == TimerPhase.ringing || phase == TimerPhase.ended;
    final color = finished ? c.warning : (phase == TimerPhase.paused ? c.inkTertiary : c.accent);
    final big = 92 * t.scale;
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.sm),
      child: tid(
        'timer.${x.id}',
        Row(
          children: [
            tid(
              'timer.${x.id}.left',
              Semantics(
                label: '${x.label}: ${finished ? 'done' : '${formatCountdown(x.remainingMs(nowMs))} left'}',
                excludeSemantics: true,
                child: DProgressRing(
                progress: x.progress(nowMs),
                size: big,
                color: color,
                  child: Text(
                    finished ? 'Done' : formatCountdown(x.remainingMs(nowMs)),
                    style: t.text.title.copyWith(fontWeight: FontWeight.w800, fontSize: (finished ? 22 : 24) * t.scale, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
              ),
            ),
            SizedBox(width: t.space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(x.label, style: t.text.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    finished ? 'Done' : (phase == TimerPhase.paused ? 'Paused' : '${formatTimerLength(Duration(milliseconds: x.durationMs))} timer'),
                    style: t.text.caption,
                  ),
                ],
              ),
            ),
            if (finished)
              DButton(label: 'Stop', icon: Icons.alarm_off_rounded, id: 'timer.${x.id}.stop', onPressed: () => updateKitchenTimer(ref, x, (_, _) => kDismissTimerFields))
            else
              DIconButton(
                icon: phase == TimerPhase.paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                label: phase == TimerPhase.paused ? 'Resume' : 'Pause',
                id: 'timer.${x.id}.${phase == TimerPhase.paused ? 'resume' : 'pause'}',
                tone: DButtonTone.tonal,
                onPressed: () => updateKitchenTimer(ref, x, phase == TimerPhase.paused ? resumeTimerFields : pauseTimerFields),
              ),
            SizedBox(width: t.space.xs),
            DButton(
              label: '+1 min',
              tone: DButtonTone.neutral,
              size: DButtonSize.sm,
              id: 'timer.${x.id}.add',
              onPressed: () => updateKitchenTimer(ref, x, (t, now) => addTimerFields(t, const Duration(minutes: 1), now)),
            ),
            if (!finished) ...[
              SizedBox(width: t.space.xs),
              DIconButton(
                icon: Icons.close_rounded,
                label: 'Cancel timer',
                id: 'timer.${x.id}.cancel',
                tone: DButtonTone.ghost,
                onPressed: () => updateKitchenTimer(ref, x, (_, _) => kDismissTimerFields),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
