import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FrameTiming, PlatformDispatcher;

import 'package:dearth_core/dearth_core.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/household.dart';
import '../core/platform/freekiosk.dart';
import '../core/platform/system_ui.dart';
import 'display_state.dart';

// ───────────────────────────────── Brightness ───────────────────────────────

/// Where window brightness goes (0…1, null = the system's); tests record it.
final brightnessSinkProvider = Provider<Future<void> Function(double?)>((ref) => setWindowBrightness);

/// The brightness for what the display shows and how light the room is
/// (SPEC FR-DSP-02): a curve per scene, smoothed and ramped so it never
/// flickers. Wall displays only; phones and laptops keep their own. The
/// state is the brightness applied, null while the system's stands.
class BrightnessController extends Notifier<double?> {
  final _ramp = BrightnessRamp();
  BrightnessScene? _scene;
  Timer? _tick;
  static const _step = Duration(milliseconds: 250);

  @override
  double? build() {
    ref.onDispose(() => _tick?.cancel());
    ref.listen(displayProvider.select((d) => d.mode), (_, _) => _update());
    ref.listen(nightNowProvider, (_, _) => _update());
    ref.listen(roomProvider.select((r) => r.lux), (_, _) => _update());
    ref.listen(deviceSettingsProvider, (_, _) => _update());
    Future.microtask(_update);
    return null;
  }

  BrightnessScene _sceneNow(DeviceSettings s) => switch (ref.read(displayProvider).mode) {
        DisplayMode.off => BrightnessScene.off,
        DisplayMode.night => BrightnessScene.night,
        DisplayMode.screensaver => BrightnessScene.screensaver,
        DisplayMode.active => s.nightMode && ref.read(nightNowProvider) ? BrightnessScene.nightAwake : BrightnessScene.active,
      };

  void _update() {
    final s = ref.read(deviceSettingsProvider);
    final double? target;
    final BrightnessScene? scene;
    if (s.isPersonal) {
      scene = null;
      target = null;
    } else {
      scene = _sceneNow(s);
      // "Android's": the sensor isn't used, but the night scenes still dim.
      final lux = s.brightness == 'system' ? null : ref.read(roomProvider).lux;
      target = targetBrightness(scene, lux, bias: s.brightnessBias);
    }
    final jump = scene != _scene;
    _scene = scene;
    if (_ramp.retarget(target, jump: jump)) _apply(_ramp.current);
    if (!_ramp.settled) {
      _tick ??= Timer.periodic(_step, (_) {
        final v = _ramp.step(_step);
        if (v != null) _apply(v);
        if (_ramp.settled) {
          _tick?.cancel();
          _tick = null;
        }
      });
    }
  }

  void _apply(double? v) {
    state = v;
    unawaited(ref.read(brightnessSinkProvider)(v));
  }
}

final brightnessProvider = NotifierProvider<BrightnessController, double?>(BrightnessController.new);

// ──────────────────────────────── Screen power ──────────────────────────────

/// Turns the screen on (native wake lock); tests record it.
final screenWakerProvider = Provider<Future<void> Function()>((ref) => wakeScreen);

/// Off means off (SPEC FR-DSP-03, §13.9): entering it asks FreeKiosk to
/// turn the panel off (Device Owner `lockNow()`); without FreeKiosk the
/// display stays black at 0 % brightness. Leaving it (the schedule's end, a
/// timer, a reminder) turns the panel back on, through FreeKiosk and the
/// app's own wake lock both, so the morning never depends on one of them.
/// The state is whether the panel was asked to be off.
class ScreenPower extends Notifier<bool> {
  @override
  bool build() {
    ref.listen(displayProvider.select((d) => d.mode), (prev, mode) {
      if (mode == DisplayMode.off && prev != DisplayMode.off) unawaited(_off());
      if (prev == DisplayMode.off && mode != DisplayMode.off) unawaited(_on());
    });
    return false;
  }

  Future<void> _off() async {
    if (ref.read(deviceSettingsProvider).isPersonal) return;
    final kiosk = await ref.read(freeKioskProvider.future);
    // Something may have woken it while FreeKiosk was being found.
    if (kiosk == null || ref.read(displayProvider).mode != DisplayMode.off) return;
    try {
      await kiosk.screenOff();
      state = true;
    } on FreeKioskException {
      // Black at 0 % it is.
    }
  }

  Future<void> _on() async {
    state = false;
    final kiosk = await ref.read(freeKioskProvider.future);
    try {
      await kiosk?.screenOn();
    } on FreeKioskException {
      // The wake lock below.
    }
    await ref.read(screenWakerProvider)();
  }
}

final screenPowerProvider = NotifierProvider<ScreenPower, bool>(ScreenPower.new);

// ─────────────────────────────── Frame stats ────────────────────────────────

/// How smoothly frames have been drawn since the last report, for the Hub's
/// device list (SPEC §12, FR-ADM-01): frames, the ones over the display's
/// budget, the 95th percentile and the worst.
class FrameStats {
  FrameStats() {
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  static const _keep = 600;
  final _spansUs = <int>[];
  int _frames = 0;
  int _slow = 0;

  int get _budgetUs {
    final views = PlatformDispatcher.instance.views;
    final hz = views.isEmpty ? 60.0 : views.first.display.refreshRate;
    return (1e6 / (hz > 0 ? hz : 60)).round();
  }

  void _onTimings(List<FrameTiming> timings) {
    final budget = _budgetUs;
    for (final t in timings) {
      final us = t.totalSpan.inMicroseconds;
      _frames++;
      if (us > budget) _slow++;
      _spansUs.add(us);
    }
    if (_spansUs.length > _keep) _spansUs.removeRange(0, _spansUs.length - _keep);
  }

  /// The numbers since the last call, then starts counting afresh.
  Map<String, Object?> take() {
    final sorted = [..._spansUs]..sort();
    final out = {
      'frames': _frames,
      'slowFrames': _slow,
      if (sorted.isNotEmpty) 'p95Ms': (sorted[math.min(sorted.length - 1, (sorted.length * 0.95).floor())] / 1000).toStringAsFixed(1),
      if (sorted.isNotEmpty) 'worstMs': (sorted.last / 1000).toStringAsFixed(1),
    };
    _spansUs.clear();
    _frames = _slow = 0;
    return out;
  }

  void dispose() => SchedulerBinding.instance.removeTimingsCallback(_onTimings);
}

final frameStatsProvider = Provider<FrameStats>((ref) {
  final s = FrameStats();
  ref.onDispose(s.dispose);
  return s;
});
