import 'dart:math' as math;

import 'package:meta/meta.dart';

/// What the panel is showing, for the brightness curve (SPEC FR-DSP-02,
/// §10.12 display modes).
enum BrightnessScene {
  /// The full UI by day (or any time outside the night schedule).
  active,

  /// The photo frame.
  screensaver,

  /// The dim UI a touch brings up during the night, for a minute.
  nightAwake,

  /// The night clock.
  night,

  /// Off: black, whatever the room.
  off,
}

/// Window brightness (0…1) from ambient light: [min] in a dark room, [max]
/// in daylight, on a log scale between, as eyes see it.
@immutable
class BrightnessCurve {
  const BrightnessCurve(this.min, this.max, {this.darkLux = 2, this.brightLux = 800});
  final double min;
  final double max;

  /// At or below this the panel sits at [min].
  final double darkLux;

  /// At or above this the panel sits at [max].
  final double brightLux;

  /// Where [lux] falls between dark and bright, 0…1.
  double position(double lux) {
    final lo = math.log(darkLux + 1), hi = math.log(brightLux + 1);
    return ((math.log(math.max(0, lux) + 1) - lo) / (hi - lo)).clamp(0.0, 1.0);
  }

  /// The brightness for [lux], moved by the family's [bias]: −1 dimmer, +1
  /// brighter (a fifth of the way along the curve, and a lower or higher
  /// floor for a dark room).
  double at(double lux, {int bias = 0}) {
    final b = bias.clamp(-1, 1);
    final t = (position(lux) + 0.2 * b).clamp(0.0, 1.0);
    final floor = (min * (1 + 0.5 * b)).clamp(0.0, max);
    return (floor + (max - floor) * t).clamp(0.0, 1.0);
  }
}

/// The curve per scene. The night clock stays barely lit even with the
/// kitchen lights on; the photo frame is a little calmer than the UI.
const Map<BrightnessScene, BrightnessCurve> kBrightnessCurves = {
  BrightnessScene.active: BrightnessCurve(0.15, 1.0),
  BrightnessScene.screensaver: BrightnessCurve(0.10, 0.85),
  BrightnessScene.nightAwake: BrightnessCurve(0.04, 0.35),
  BrightnessScene.night: BrightnessCurve(0.01, 0.12),
};

/// The brightness for [scene] at [lux], or null to leave it to the system.
/// Without a light sensor ([lux] null) the system's brightness stands by
/// day, and the night scenes still dim.
double? targetBrightness(BrightnessScene scene, double? lux, {int bias = 0}) {
  if (scene == BrightnessScene.off) return 0;
  if (lux == null) {
    return switch (scene) {
      BrightnessScene.nightAwake => 0.2,
      BrightnessScene.night => 0.03,
      _ => null,
    };
  }
  return kBrightnessCurves[scene]!.at(lux, bias: bias);
}

/// Ambient light smoothed over a few seconds, so a hand or a shadow passing
/// the sensor doesn't move the screen. It follows a brighter room quickly
/// (lights on) and a darker one slowly (someone walking past). Smoothed on
/// a log scale, like the curve.
class AmbientLight {
  AmbientLight({this.brighten = const Duration(seconds: 2), this.darken = const Duration(seconds: 8)});
  final Duration brighten;
  final Duration darken;

  double? _log;
  int? _atMs;

  /// The smoothed light level in lux, or null before the first reading.
  double? get lux => _log == null ? null : math.exp(_log!) - 1;

  /// Feeds a reading taken at [atMs]. Call it on a steady tick with the
  /// latest reading too: the sensor reports changes only, so a room that
  /// stays dark sends nothing.
  double add(double lux, int atMs) {
    final v = math.log(math.max(0, lux) + 1);
    final last = _log, lastAt = _atMs;
    _atMs = atMs;
    if (last == null || lastAt == null) {
      _log = v;
    } else {
      final tau = (v > last ? brighten : darken).inMilliseconds;
      _log = last + (v - last) * (1 - math.exp(-math.max(0, atMs - lastAt) / tau));
    }
    return math.exp(_log!) - 1;
  }
}

/// Whether the room is dark enough for the night clock (SPEC §10.12: Night
/// on "ambient light below a threshold"). It takes [darkFor] below
/// [darkLux] to go dark and [lightFor] above [lightLux] to come back, so a
/// lamp switched off for a moment, or a light left on in the hall, doesn't
/// flip the display.
class DarkRoom {
  DarkRoom({this.darkLux = 3, this.lightLux = 12, this.darkFor = const Duration(minutes: 2), this.lightFor = const Duration(seconds: 20)});
  final double darkLux;
  final double lightLux;
  final Duration darkFor;
  final Duration lightFor;

  bool _dark = false;
  int? _crossedAtMs;

  bool get dark => _dark;

  /// Feeds the smoothed light level at [atMs]; returns whether the room is
  /// dark now.
  bool update(double lux, int atMs) {
    final crossing = _dark ? lux > lightLux : lux < darkLux;
    if (!crossing) {
      _crossedAtMs = null;
      return _dark;
    }
    final since = _crossedAtMs ??= atMs;
    if (atMs - since >= (_dark ? lightFor : darkFor).inMilliseconds) {
      _dark = !_dark;
      _crossedAtMs = null;
    }
    return _dark;
  }
}

/// Moves the applied brightness toward its target at a gentle pace and
/// ignores small changes, so the panel never flickers (SPEC FR-DSP-02
/// "hysteresis to prevent flicker").
class BrightnessRamp {
  BrightnessRamp({this.deadband = 0.04, this.perSecond = 0.5});

  /// Target changes smaller than this, from where the ramp is heading, are
  /// ignored.
  final double deadband;

  /// The most the brightness moves in a second.
  final double perSecond;

  double? _current;
  double? _target;

  /// The brightness applied now; null leaves it to the system.
  double? get current => _current;
  double? get target => _target;
  bool get settled => _current == _target;

  /// Aims at [target]. A [jump] (a new scene: the night clock, off, a
  /// wake) applies it at once; null hands brightness back to the system at
  /// once. Returns whether the applied value changed.
  bool retarget(double? target, {bool jump = false}) {
    if (target == null || jump || _current == null) {
      final changed = _current != target;
      _current = _target = target;
      return changed;
    }
    final aim = _target ?? _current!;
    if ((target - aim).abs() < deadband) return false;
    _target = target;
    return false;
  }

  /// Advances by [elapsed]; returns the new value when it moved.
  double? step(Duration elapsed) {
    final c = _current, t = _target;
    if (c == null || t == null || c == t) return null;
    final most = perSecond * elapsed.inMicroseconds / 1e6;
    final next = (t - c).abs() <= most ? t : c + most * (t > c ? 1 : -1);
    _current = next;
    return next;
  }
}
