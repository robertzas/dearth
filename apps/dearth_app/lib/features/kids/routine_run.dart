import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/display_state.dart';
import '../../core/providers.dart';
import 'celebration.dart';
import 'kids_data.dart';
import 'kids_ops.dart';

/// Routine run mode (SPEC FR-KID-06/07): full screen, the current step big
/// with its picture and words, an optional visual timer (a shrinking red
/// disc, Time-Timer style), and stepping stones the buddy hops along. Stray
/// taps can't break it: "Done" rests briefly after every step.
Future<void> openRoutine(BuildContext context, RoutineToday routine, Profile kid) {
  final t = DTheme.of(context);
  return Navigator.of(context, rootNavigator: true).push<void>(PageRouteBuilder<void>(
    transitionDuration: t.motion(DMotion.standard),
    reverseTransitionDuration: t.motion(DMotion.fast),
    pageBuilder: (_, _, _) => RoutineRunScreen(routine: routine, kid: kid),
    transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
  ));
}

String _goalEmoji(String kind) => switch (kind) {
      'bedtime' => '🛏️',
      'morning' => '☀️',
      'departure' => '🚗',
      'tidy' => '✨',
      _ => '🌟',
    };

class RoutineRunScreen extends ConsumerStatefulWidget {
  const RoutineRunScreen({super.key, required this.routine, required this.kid});
  final RoutineToday routine;
  final Profile kid;

  @override
  ConsumerState<RoutineRunScreen> createState() => _RoutineRunScreenState();
}

class _RoutineRunScreenState extends ConsumerState<RoutineRunScreen> {
  late final List<String> _done = [...widget.routine.doneSteps];
  late final DisplayController _display = ref.read(displayProvider.notifier);
  bool _resting = false;
  Timer? _ticker;
  int? _timerLeft;

  List<RoutineStep> get _steps => widget.routine.steps;
  int get _current => _steps.indexWhere((s) => !_done.contains(s.id));
  bool get _finished => _current < 0;
  bool get _calm => widget.routine.routine.kind == 'bedtime';

  // Providers can't change while widgets build or unmount: keep-awake waits
  // for the frame to finish, both ways.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _display.keepAwakeFor(const Duration(minutes: 20));
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    final display = _display;
    Future.microtask(() => display.keepAwakeFor(Duration.zero));
    super.dispose();
  }

  void _toggleTimer(RoutineStep step) {
    if (_ticker != null) {
      _ticker!.cancel();
      setState(() => _ticker = null);
      return;
    }
    setState(() => _timerLeft ??= step.timerSeconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = (_timerLeft ?? 0) - 1;
      setState(() => _timerLeft = left);
      if (left <= 0) {
        _ticker?.cancel();
        _ticker = null;
        celebrate(context, emoji: '⏰', buddy: buddyEmoji(widget.kid.buddy), message: 'Time’s up!', calm: _calm);
      }
    });
  }

  Future<void> _stepDone() async {
    if (_resting || _finished) return;
    final step = _steps[_current];
    _ticker?.cancel();
    setState(() {
      _ticker = null;
      _timerLeft = null;
      _done.add(step.id);
      _resting = true;
    });
    Future<void>.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _resting = false);
    });
    final r = widget.routine;
    final w = ref.read(writerProvider);
    final runId = routineRunId(r.routine.id, r.date, r.profileId);
    await w.commit(routineProgressOps(
      w.op,
      routine: r.routine,
      date: r.date,
      profileId: r.profileId,
      doneSteps: _done,
      totalSteps: _steps.length,
      existing: r.run,
      ledger: await ledgerFor(ref.read(dbProvider), 'routine_runs', runId),
      nowMs: ref.read(appClockProvider).nowMs(),
    ));
    if (!mounted) return;
    final buddy = buddyEmoji(widget.kid.buddy);
    if (_finished) {
      celebrate(context, emoji: r.routine.emoji ?? '🌟', buddy: buddy, message: _calm ? 'Sweet dreams!' : 'You did the whole thing!', big: true, calm: _calm);
    } else {
      celebrate(context, emoji: step.emoji ?? '⭐', buddy: buddy, message: randomPraise(), calm: _calm);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = widget.routine.routine;
    final n = _steps.length;
    final step = _finished ? null : _steps[_current];
    final big = (t.isPhone ? 140 : 210) * t.scale;
    return screenTid(
      'screen.routine',
      Material(
        color: t.colors.surface,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(t.pageMargin),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    DIconButton(icon: Icons.close_rounded, label: 'Close', id: 'routine.close', tone: DButtonTone.ghost, onPressed: () => Navigator.of(context).pop()),
                    SizedBox(width: t.space.sm),
                    DEmoji(r.emoji ?? '🌟', size: 32 * t.scale),
                    SizedBox(width: t.space.xs),
                    Expanded(child: Text(r.title, style: t.text.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    tid('routine.progress', Text(_finished ? 'All done!' : 'Step ${_current + 1} of $n', style: t.text.label.copyWith(color: t.colors.inkSecondary))),
                  ],
                ),
                SizedBox(height: t.space.md),
                _StonePath(steps: _steps, done: _done, current: _current, buddy: buddyEmoji(widget.kid.buddy), goal: _goalEmoji(r.kind)),
                Expanded(
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: t.motion(DMotion.emphasized),
                      child: step == null
                          ? Column(
                              key: const ValueKey('done'),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DEmoji(_goalEmoji(r.kind), size: big),
                                SizedBox(height: t.space.md),
                                Text(_calm ? 'Sweet dreams!' : 'All done!', style: t.text.kidDisplay),
                              ],
                            )
                          : Column(
                              key: ValueKey(step.id),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                DEmoji(step.emoji ?? '⭐', size: big),
                                SizedBox(height: t.space.md),
                                tid('routine.step', Text(step.title, style: t.text.kidDisplay, textAlign: TextAlign.center)),
                                if (step.voiceLine != null) ...[
                                  SizedBox(height: t.space.xs),
                                  Text(step.voiceLine!, style: t.text.kidBody.copyWith(color: t.colors.inkSecondary), textAlign: TextAlign.center),
                                ],
                                if (step.timerSeconds != null) ...[
                                  SizedBox(height: t.space.lg),
                                  _VisualTimer(
                                    total: step.timerSeconds!,
                                    left: _timerLeft ?? step.timerSeconds!,
                                    running: _ticker != null,
                                    onTap: () => _toggleTimer(step),
                                  ),
                                ],
                              ],
                            ),
                    ),
                  ),
                ),
                Center(
                  child: step == null
                      ? DButton(label: 'Yay!', emoji: '🎉', size: DButtonSize.lg, id: 'routine.finish', onPressed: () => Navigator.of(context).pop())
                      : DButton(label: 'Done!', emoji: '✅', size: DButtonSize.lg, id: 'routine.done', onPressed: _resting ? null : _stepDone),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Stepping stones to the goal, with the buddy on the current one.
class _StonePath extends StatelessWidget {
  const _StonePath({required this.steps, required this.done, required this.current, required this.buddy, required this.goal});
  final List<RoutineStep> steps;
  final List<String> done;
  final int current;
  final String buddy;
  final String goal;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final stone = 40 * t.scale;
    return SizedBox(
      height: stone * 2.2,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, s) in steps.indexed) ...[
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(height: stone, child: i == current ? DEmoji(buddy, size: stone) : null),
                  Container(
                    width: stone,
                    height: stone * 0.7,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: done.contains(s.id) ? t.colors.tintOf(t.colors.success, 0.35) : (i == current ? t.colors.accentTint : t.colors.surfaceSunken),
                      borderRadius: BorderRadius.all(Radius.elliptical(stone, stone * 0.7)),
                      border: i == current ? Border.all(color: t.colors.accent, width: 2) : null,
                    ),
                    child: done.contains(s.id) ? Icon(Icons.check_rounded, size: stone * 0.5, color: t.colors.success) : DEmoji(s.emoji ?? '⭐', size: stone * 0.45),
                  ),
                ],
              ),
            ),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (current < 0) DEmoji(buddy, size: stone),
                DEmoji(goal, size: stone * 1.1),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A red disc that shrinks as time passes (SPEC FR-KID-06).
class _VisualTimer extends StatelessWidget {
  const _VisualTimer({required this.total, required this.left, required this.running, required this.onTap});
  final int total;
  final int left;
  final bool running;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final size = 120 * t.scale;
    final mm = left ~/ 60, ss = (left % 60).toString().padLeft(2, '0');
    return DPressable(
      id: 'routine.timer',
      semanticLabel: running ? 'Timer running, $mm:$ss left. Tap to pause' : 'Start the timer, $mm:$ss',
      excludeSemantics: true,
      borderRadius: t.radius.pill,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: RepaintBoundary(child: CustomPaint(painter: _DiscPainter(fraction: total == 0 ? 0 : left / total, rim: t.colors.outline))),
          ),
          SizedBox(width: t.space.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$mm:$ss', style: t.text.h1.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              Text(running ? 'Tap to pause' : 'Tap to start', style: t.text.caption),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiscPainter extends CustomPainter {
  _DiscPainter({required this.fraction, required this.rim});
  final double fraction;
  final Color rim;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = Colors.white);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.92), -math.pi / 2, 2 * math.pi * fraction, true, Paint()..color = const Color(0xFFE5484D));
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.06
      ..color = rim);
  }

  @override
  bool shouldRepaint(_DiscPainter old) => old.fraction != fraction || old.rim != rim;
}
