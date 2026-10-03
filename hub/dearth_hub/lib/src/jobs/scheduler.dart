import 'dart:async';
import 'dart:math' as math;

import 'package:logging/logging.dart';

import '../storage.dart';

final _log = Logger('jobs');

/// A periodic Hub job (SPEC §14.3).
abstract class HubJob {
  String get id;

  /// Delay until the next run (jobs may adapt their cadence).
  Duration nextDelay();

  Future<void> run();
}

/// Runs jobs on their cadence, never overlapping the same job, recording
/// health in `job_states`. `runNow` coalesces bursts of triggers.
class Scheduler {
  Scheduler(this.store);

  final JobStore store;
  final Map<String, HubJob> _jobs = {};
  final Map<String, Timer> _timers = {};
  final Set<String> _running = {};
  final Set<String> _rerun = {};
  final _random = math.Random();
  bool _stopped = false;

  void register(HubJob job) => _jobs[job.id] = job;
  Iterable<HubJob> get jobs => _jobs.values;

  void start() {
    var stagger = 2;
    for (final job in _jobs.values) {
      _schedule(job.id, Duration(seconds: stagger));
      stagger += 3;
    }
  }

  /// Runs [id] soon (debounced by [delay]); if running, runs again after.
  void runNow(String id, {Duration delay = const Duration(milliseconds: 300)}) {
    if (!_jobs.containsKey(id) || _stopped) return;
    if (_running.contains(id)) {
      _rerun.add(id);
      return;
    }
    _schedule(id, delay);
  }

  Future<void> runAndWait(String id) async {
    final job = _jobs[id];
    if (job == null) return;
    _timers.remove(id)?.cancel();
    await _execute(job);
  }

  void _schedule(String id, Duration delay) {
    _timers.remove(id)?.cancel();
    if (_stopped) return;
    _timers[id] = Timer(delay, () => unawaited(_execute(_jobs[id]!)));
  }

  Future<void> _execute(HubJob job) async {
    if (_running.contains(job.id)) {
      _rerun.add(job.id);
      return;
    }
    _running.add(job.id);
    final started = DateTime.now().millisecondsSinceEpoch;
    try {
      await job.run();
      await store.write(job.id, lastRunMs: started, lastOkMs: DateTime.now().millisecondsSinceEpoch, clearError: true);
    } on Object catch (e, st) {
      _log.warning('Job ${job.id} failed: $e', e, st);
      await store.write(job.id, lastRunMs: started, lastError: '$e');
    } finally {
      _running.remove(job.id);
      if (_rerun.remove(job.id)) {
        _schedule(job.id, const Duration(milliseconds: 200));
      } else {
        final base = job.nextDelay();
        final jitter = Duration(milliseconds: _random.nextInt(math.max(1, base.inMilliseconds ~/ 20)));
        _schedule(job.id, base + jitter);
      }
    }
  }

  void stop() {
    _stopped = true;
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
  }
}
