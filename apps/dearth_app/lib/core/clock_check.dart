import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Nothing Dearth shows happens before this: a clock earlier than it is
/// one that hasn't been set.
final DateTime kClockFloor = DateTime.utc(2026);

/// Whether the device's clock can be believed. Frames have no clock battery:
/// after a power cut they start at 1970 until the network sets the time,
/// and until then "today", the calendar and every change stamped would be
/// decades off. The clock counts as set once it is past [kClockFloor] and
/// no more than a day behind the last time this device saw it set.
class ClockCheck extends Notifier<bool> {
  static const _kvKey = 'clock.lastSeenMs';
  Timer? _poll;
  int _lastSeenMs = 0;

  @override
  bool build() {
    ref.onDispose(() => _poll?.cancel());
    final ok = _plausible();
    if (ok) {
      unawaited(_checkLastSeen());
    } else {
      _waitForIt();
    }
    return ok;
  }

  int get _now => ref.read(appClockProvider).nowMs();

  // A clock the tests and E2E shift (`?now=`) is not this device's own.
  bool get _shifted => ref.read(appClockProvider).isShifted;

  bool _plausible() => _now >= kClockFloor.millisecondsSinceEpoch && _now >= _lastSeenMs - const Duration(days: 1).inMilliseconds;

  void _waitForIt() {
    _poll ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_plausible()) return;
      _poll?.cancel();
      _poll = null;
      state = true;
      unawaited(_remember());
    });
  }

  Future<void> _checkLastSeen() async {
    if (_shifted) return;
    final db = ref.read(dbProvider);
    _lastSeenMs = int.tryParse(await db.kvGet(_kvKey) ?? '') ?? 0;
    if (!ref.mounted) return;
    if (!_plausible()) {
      state = false;
      _waitForIt();
      return;
    }
    await _remember();
  }

  /// Past [kClockFloor] but behind the last time seen: someone may have
  /// set it back on purpose, so a grown-up can say it's right.
  bool get canAccept => _now >= kClockFloor.millisecondsSinceEpoch;

  /// "The time is right": believe the clock as it is.
  void accept() {
    if (!canAccept) return;
    _poll?.cancel();
    _poll = null;
    _lastSeenMs = 0;
    state = true;
    unawaited(_remember());
  }

  Future<void> _remember() async {
    if (_shifted) return;
    await ref.read(dbProvider).kvSet(_kvKey, '$_now');
  }
}

final clockSetProvider = NotifierProvider<ClockCheck, bool>(ClockCheck.new);
