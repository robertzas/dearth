import 'dart:async';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data/household.dart';
import '../core/env.dart';
import '../core/providers.dart';

// ───────────────────────────── Theme resolution ─────────────────────────────

/// Minutes-of-day window of the household night schedule, or null when off.
final nightWindowProvider = Provider<(int, int)?>((ref) {
  final v = ref.watch(settingMapProvider(SettingKeys.nightSchedule));
  if (v['enabled'] == false) return null;
  int? parse(Object? s) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch('${s ?? ''}');
    return m == null ? null : int.parse(m[1]!) * 60 + int.parse(m[2]!);
  }

  final start = parse(v['start']) ?? 21 * 60;
  final end = parse(v['end']) ?? 6 * 60 + 30;
  return (start, end);
});

bool inWindow(int minuteOfDay, (int, int) w) {
  final (s, e) = w;
  return s <= e ? minuteOfDay >= s && minuteOfDay < e : minuteOfDay >= s || minuteOfDay < e;
}

/// Whether the household night schedule is active right now.
final isNightTimeProvider = Provider<bool>((ref) {
  final w = ref.watch(nightWindowProvider);
  if (w == null) return false;
  ref.watch(minuteProvider);
  final time = ref.watch(householdTimeProvider);
  return inWindow(time.minuteOfDay(time.nowMs()), w);
});

/// Sun up at the household location (true when the location is unknown).
final isDaylightProvider = Provider<bool>((ref) {
  final loc = ref.watch(householdLocationProvider);
  ref.watch(minuteProvider);
  final time = ref.watch(householdTimeProvider);
  if (loc == null) {
    final m = time.minuteOfDay(time.nowMs());
    return m >= 7 * 60 && m < 19 * 60;
  }
  final today = time.today();
  return sunTimesFor(today, loc.$1, loc.$2, time).isDaylightAt(time.nowMs());
});

/// The theme to render (SPEC §11.6). `auto`: Night during the night schedule
/// on wall displays, Evening between sunset and sunrise, Light otherwise.
final themeModeProvider = Provider<DThemeMode>((ref) {
  final s = ref.watch(deviceSettingsProvider);
  switch (s.theme) {
    case 'light':
      return DThemeMode.light;
    case 'evening':
    case 'dark':
      return DThemeMode.evening;
    case 'night':
      return DThemeMode.night;
  }
  if (!s.isPersonal && s.nightMode && ref.watch(isNightTimeProvider)) return DThemeMode.night;
  return ref.watch(isDaylightProvider) ? DThemeMode.light : DThemeMode.evening;
});

/// Performance tier for this device (SPEC §6.2), with the device override.
final perfTierProvider = Provider<PerfTier>((ref) {
  final override = ref.watch(deviceSettingsProvider.select((s) => s.tierOverride));
  return detectTier(isWeb: kIsWeb, isDesktop: AppEnv.isDesktop, override: override, totalRamMb: ref.watch(deviceRamMbProvider));
});

/// Total RAM in MB when the platform reports it (Android), else null.
final deviceRamMbProvider = Provider<int?>((ref) => null);

// ─────────────────────────────── Display modes ──────────────────────────────

/// Display modes (SPEC §10.12), in priority order Off > Night > Privacy >
/// Screensaver > Active.
enum DisplayMode { active, screensaver, night, off }

@immutable
class DisplayState {
  const DisplayState({this.mode = DisplayMode.active, this.wokeAtMs = 0, this.keepAwakeUntilMs = 0});
  final DisplayMode mode;

  /// Last time a touch woke the display out of Night (dim UI for 60 s).
  final int wokeAtMs;

  /// "Keep awake 1 h" override (FR-DSP-01).
  final int keepAwakeUntilMs;

  DisplayState copyWith({DisplayMode? mode, int? wokeAtMs, int? keepAwakeUntilMs}) =>
      DisplayState(mode: mode ?? this.mode, wokeAtMs: wokeAtMs ?? this.wokeAtMs, keepAwakeUntilMs: keepAwakeUntilMs ?? this.keepAwakeUntilMs);
}

/// The idle engine: tracks touches, enters the screensaver after the idle
/// timeout and Night during the night schedule; any touch wakes.
class DisplayController extends Notifier<DisplayState> {
  Timer? _idle;
  int _lastActivityMs = 0;

  @override
  DisplayState build() {
    ref.onDispose(() => _idle?.cancel());
    // Re-evaluate when the night schedule or settings change.
    ref.listen(isNightTimeProvider, (_, night) => _evaluate(night: night));
    ref.listen(deviceSettingsProvider, (_, _) => _restartIdle());
    ref.listen(_idleMinutesProvider, (_, _) => _restartIdle());
    Future.microtask(_restartIdle);
    return const DisplayState();
  }

  bool get _enabled {
    final s = ref.read(deviceSettingsProvider);
    return !s.isPersonal && !ref.read(envProvider).e2e;
  }

  int get _now => DateTime.now().millisecondsSinceEpoch;

  /// Any touch on the app.
  void activity() {
    _lastActivityMs = _now;
    if (state.mode != DisplayMode.active) {
      wake();
      return;
    }
    _restartIdle();
  }

  void wake() {
    state = state.copyWith(mode: DisplayMode.active, wokeAtMs: _now);
    _restartIdle();
  }

  /// Starts the photo frame now (nav rail button, remote "sleep").
  void startScreensaver() {
    _idle?.cancel();
    state = state.copyWith(mode: DisplayMode.screensaver);
  }

  void keepAwakeFor(Duration d) {
    state = state.copyWith(keepAwakeUntilMs: _now + d.inMilliseconds, mode: DisplayMode.active);
    _restartIdle();
  }

  void _restartIdle() {
    _idle?.cancel();
    if (!_enabled) return;
    final night = ref.read(isNightTimeProvider) && ref.read(deviceSettingsProvider).nightMode;
    final s = ref.read(deviceSettingsProvider);
    final int minutes = s.idleMinutes ?? ref.read<int>(_idleMinutesProvider);
    // In Night, a touch shows a dim UI for 60 s, then Night resumes.
    final timeout = night ? const Duration(seconds: 60) : Duration(minutes: minutes.clamp(1, 240));
    final since = _now - _lastActivityMs;
    final remaining = _lastActivityMs == 0 ? timeout : timeout - Duration(milliseconds: since);
    _idle = Timer(remaining.isNegative ? Duration.zero : remaining, _onIdle);
  }

  void _onIdle() {
    if (!_enabled) return;
    if (state.keepAwakeUntilMs > _now) {
      _idle = Timer(Duration(milliseconds: state.keepAwakeUntilMs - _now), _onIdle);
      return;
    }
    final s = ref.read(deviceSettingsProvider);
    if (ref.read(isNightTimeProvider) && s.nightMode) {
      state = state.copyWith(mode: DisplayMode.night);
    } else if (s.screensaver) {
      state = state.copyWith(mode: DisplayMode.screensaver);
    }
  }

  void _evaluate({required bool night}) {
    if (!_enabled) return;
    final s = ref.read(deviceSettingsProvider);
    if (night && s.nightMode && state.mode == DisplayMode.screensaver) {
      state = state.copyWith(mode: DisplayMode.night);
    } else if (!night && state.mode == DisplayMode.night) {
      // Morning: back to the photo frame until someone touches the screen.
      state = state.copyWith(mode: s.screensaver ? DisplayMode.screensaver : DisplayMode.active);
    }
    _restartIdle();
  }
}

final _idleMinutesProvider = Provider<int>((ref) {
  final v = ref.watch(settingMapProvider(SettingKeys.screensaver));
  return (v['idleMinutes'] as num?)?.toInt() ?? 5;
});

final displayProvider = NotifierProvider<DisplayController, DisplayState>(DisplayController.new);
