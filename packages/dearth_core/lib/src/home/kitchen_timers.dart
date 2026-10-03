import 'dart:math' as math;

import '../db/database.dart';

/// Kitchen timers (SPEC FR-TMR-01/02) as synced `kitchen_timers` rows, so a
/// timer started on a phone rings on the wall. A running timer ends at
/// `started_ms + (paused_remaining_ms ?? duration_ms)`; pausing stores the
/// time left, and resuming restarts the clock from it.
abstract final class TimerStatus {
  static const running = 'running';
  static const paused = 'paused';

  /// Dismissed or cancelled: no longer shown anywhere.
  static const done = 'done';
}

/// What a timer is doing at a given instant.
enum TimerPhase {
  running,
  paused,

  /// Just ended: chime and pulse (for [kRingFor]).
  ringing,

  /// Ended a while ago and nobody dismissed it: shown as done, quietly.
  ended,

  /// Dismissed, cancelled, or ended longer than [kKeepEnded] ago.
  gone,
}

/// How long a finished timer chimes (louder each time).
const Duration kRingFor = Duration(minutes: 2);

/// How long an undismissed finished timer stays on screen.
const Duration kKeepEnded = Duration(minutes: 30);

/// Preset lengths offered as chips (FR-TMR-01).
const List<Duration> kTimerPresets = [
  Duration(minutes: 1),
  Duration(minutes: 3),
  Duration(minutes: 5),
  Duration(minutes: 10),
  Duration(minutes: 15),
  Duration(minutes: 30),
];

extension KitchenTimerState on KitchenTimer {
  int get _left => pausedRemainingMs ?? durationMs;

  /// When a running timer ends; null otherwise.
  int? get endsAtMs => status == TimerStatus.running ? (startedMs ?? 0) + _left : null;

  int remainingMs(int nowMs) => switch (status) {
        TimerStatus.running => math.max(0, endsAtMs! - nowMs),
        TimerStatus.paused => _left,
        _ => 0,
      };

  TimerPhase phase(int nowMs) {
    if (status == TimerStatus.paused) return TimerPhase.paused;
    if (status != TimerStatus.running) return TimerPhase.gone;
    final over = nowMs - endsAtMs!;
    if (over < 0) return TimerPhase.running;
    if (over < kRingFor.inMilliseconds) return TimerPhase.ringing;
    if (over < kKeepEnded.inMilliseconds) return TimerPhase.ended;
    return TimerPhase.gone;
  }

  /// Fraction elapsed, 0…1 (for the ring).
  double progress(int nowMs) => durationMs <= 0 ? 1 : (1 - remainingMs(nowMs) / durationMs).clamp(0, 1).toDouble();
}

/// Row fields for a new timer.
Map<String, Object?> startTimerFields(String label, Duration length, int nowMs, {String? createdBy, String kind = 'kitchen'}) => {
      'label': label,
      'duration_ms': length.inMilliseconds,
      'started_ms': nowMs,
      'paused_remaining_ms': null,
      'status': TimerStatus.running,
      'created_by': createdBy,
      'kind': kind,
    };

Map<String, Object?> pauseTimerFields(KitchenTimer t, int nowMs) => {'status': TimerStatus.paused, 'paused_remaining_ms': t.remainingMs(nowMs)};

Map<String, Object?> resumeTimerFields(KitchenTimer t, int nowMs) =>
    {'status': TimerStatus.running, 'started_ms': nowMs, 'paused_remaining_ms': t.remainingMs(nowMs)};

/// Adds [extra]; a finished timer starts again with just [extra] (the
/// "1 more minute" of a pot that isn't quite done). The total grows too,
/// so the ring keeps its meaning.
Map<String, Object?> addTimerFields(KitchenTimer t, Duration extra, int nowMs) {
  final phase = t.phase(nowMs);
  if (phase == TimerPhase.paused) {
    return {'paused_remaining_ms': t.remainingMs(nowMs) + extra.inMilliseconds, 'duration_ms': t.durationMs + extra.inMilliseconds};
  }
  if (phase == TimerPhase.running) {
    return {'started_ms': nowMs, 'paused_remaining_ms': t.remainingMs(nowMs) + extra.inMilliseconds, 'duration_ms': t.durationMs + extra.inMilliseconds};
  }
  return {'status': TimerStatus.running, 'started_ms': nowMs, 'paused_remaining_ms': extra.inMilliseconds, 'duration_ms': extra.inMilliseconds};
}

const Map<String, Object?> kDismissTimerFields = {'status': TimerStatus.done};

/// "4:05", "1:02:30", "0:09".
String formatCountdown(int ms) {
  final s = (ms / 1000).ceil();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
}
