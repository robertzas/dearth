import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

/// Kitchen timers on synced rows (SPEC FR-TMR-01/02).
void main() {
  const min = 60000;

  KitchenTimer row(Map<String, Object?> f, {KitchenTimer? from}) => KitchenTimer(
        id: 't',
        syncClock: '{}',
        syncHlc: '',
        syncSeq: 0,
        deleted: false,
        label: (f['label'] ?? from?.label ?? 'Timer') as String,
        durationMs: (f['duration_ms'] ?? from?.durationMs ?? 0) as int,
        startedMs: f.containsKey('started_ms') ? f['started_ms'] as int? : from?.startedMs,
        pausedRemainingMs: f.containsKey('paused_remaining_ms') ? f['paused_remaining_ms'] as int? : from?.pausedRemainingMs,
        status: (f['status'] ?? from?.status ?? TimerStatus.running) as String,
        kind: 'kitchen',
      );

  test('a running timer counts down, rings, then sits done, then goes', () {
    final t = row(startTimerFields('Pasta', const Duration(minutes: 10), 0));
    expect((t.remainingMs(4 * min), t.phase(4 * min), t.progress(5 * min)), (6 * min, TimerPhase.running, 0.5));
    expect(t.phase(10 * min), TimerPhase.ringing);
    expect(t.phase(11 * min), TimerPhase.ringing);
    expect(t.phase(12 * min), TimerPhase.ended);
    expect(t.phase(40 * min), TimerPhase.gone);
    expect(t.remainingMs(15 * min), 0);
  });

  test('pause keeps the time left; resume restarts the clock from it', () {
    final t = row(startTimerFields('Eggs', const Duration(minutes: 6), 0));
    final paused = row(pauseTimerFields(t, 2 * min), from: t);
    expect((paused.phase(50 * min), paused.remainingMs(50 * min)), (TimerPhase.paused, 4 * min), reason: 'a paused timer never runs out');
    final resumed = row(resumeTimerFields(paused, 50 * min), from: paused);
    expect((resumed.remainingMs(51 * min), resumed.endsAtMs), (3 * min, 54 * min));
  });

  test('one more minute: added while running, or a fresh minute once done', () {
    final t = row(startTimerFields('Rice', const Duration(minutes: 5), 0));
    final more = row(addTimerFields(t, const Duration(minutes: 1), 2 * min), from: t);
    expect((more.remainingMs(2 * min), more.durationMs), (4 * min, 6 * min));
    final rang = row(addTimerFields(t, const Duration(minutes: 1), 7 * min), from: t);
    expect((rang.phase(7 * min), rang.remainingMs(7 * min), rang.durationMs), (TimerPhase.running, min, min));
    final paused = row(pauseTimerFields(t, min), from: t);
    expect(row(addTimerFields(paused, const Duration(minutes: 1), 9 * min), from: paused).remainingMs(9 * min), 5 * min);
  });

  test('dismissed timers are gone everywhere', () {
    final t = row(startTimerFields('Tea', const Duration(minutes: 3), 0));
    expect(row(kDismissTimerFields, from: t).phase(min), TimerPhase.gone);
  });

  test('countdowns read like a clock', () {
    expect(formatCountdown(245000), '4:05');
    expect(formatCountdown(3750000), '1:02:30');
    expect(formatCountdown(8100), '0:09', reason: 'rounds up: never shows 0:00 while running');
  });
}
