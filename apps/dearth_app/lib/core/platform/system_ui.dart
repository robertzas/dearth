import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const MethodChannel _display = MethodChannel('app.dearth/display');

/// Asks the Android activity for an orientation mode: "sensor", "user",
/// "landscape" or "portrait" (SPEC FR-DEV-05). The activity also keeps it
/// for its next start. Other platforms keep the system's behavior.
Future<void> applyOrientation(String mode) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _display.invokeMethod<void>('setOrientation', mode);
  } on MissingPluginException {
    // Widget tests, and embedders without Dearth's activity.
  } on PlatformException {
    // Never fatal: the system's own rotation still applies.
  }
}

/// The media volume Dearth plays at, as (level, max), where the app can set
/// it: Android only (a wall frame's buttons are on its back). Null elsewhere.
Future<(int, int)?> mediaVolume() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    final v = await _display.invokeListMethod<int>('getVolume');
    return v == null || v.length < 2 ? null : (v[0], v[1]);
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

/// Sets the media volume to [level] (0…max from [mediaVolume]).
Future<void> setMediaVolume(int level) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _display.invokeMethod<void>('setVolume', level);
  } on MissingPluginException {
    // Widget tests, and embedders without Dearth's activity.
  } on PlatformException {
    // Do Not Disturb: the buttons on the device still work.
  }
}

/// Total RAM in MB and whether Android calls this a low-RAM device — the
/// inputs of the perf tier (SPEC §6.2). Android only; null elsewhere.
Future<({int ramMb, bool lowRam})?> deviceMemory() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    final v = await _display.invokeListMethod<int>('getMemory');
    return v == null || v.length < 2 ? null : (ramMb: v[0], lowRam: v[1] != 0);
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

/// Hides the phone-style system bars (status, navigation) or shows them
/// again. Hidden, a swipe from the edge brings them back for a moment.
Future<void> applySystemBars({required bool hidden}) async {
  if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) return;
  try {
    await (hidden
        ? SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)
        : SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values));
  } on Object {
    // Never fatal: the bars just stay as they are.
  }
}

// ──────────────────────── Light, brightness, screen ─────────────────────────

const EventChannel _light = EventChannel('app.dearth/light');

bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Whether this device has an ambient light sensor (SPEC FR-DSP-02).
Future<bool> hasLightSensor() async {
  if (!_android) return false;
  try {
    return await _display.invokeMethod<bool>('hasLightSensor') ?? false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}

/// Ambient light readings in lux, as the sensor reports changes. Empty
/// where there is no sensor. It asks first: an event channel with nothing
/// behind it (widget tests, which run as Android) reports the missing
/// plugin as an error of its own instead of through the stream.
Stream<double> lightReadings() async* {
  if (!await hasLightSensor()) return;
  yield* _light.receiveBroadcastStream().map((v) => (v! as num).toDouble()).handleError((Object _) {}, test: (e) => e is PlatformException);
}

/// Sets this window's brightness (0…1), or hands it back to the system
/// (null). Android only; it holds while Dearth is in front.
Future<void> setWindowBrightness(double? level) async {
  if (!_android) return;
  try {
    await _display.invokeMethod<void>('setBrightness', level);
  } on MissingPluginException {
    // Widget tests, and embedders without Dearth's activity.
  } on PlatformException {
    // Never fatal: the system's brightness stands.
  }
}

/// Turns the screen on if it is asleep (SPEC FR-DSP-03).
Future<void> wakeScreen() async {
  if (!_android) return;
  try {
    await _display.invokeMethod<bool>('wakeScreen');
  } on MissingPluginException {
    // Widget tests, and embedders without Dearth's activity.
  } on PlatformException {
    // FreeKiosk's screen/on is the other way back.
  }
}

/// Whether the screen is physically on; null where unknown.
Future<bool?> isScreenOn() async {
  if (!_android) return null;
  try {
    return await _display.invokeMethod<bool>('isScreenOn');
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

/// FreeKiosk's REST port and key, as `deploy_frame.sh` handed them over
/// (SPEC §13.9); null on devices without it.
Future<({int port, String key})?> freeKioskConfig() async {
  if (!_android) return null;
  try {
    final m = await _display.invokeMapMethod<String, Object?>('getFreeKiosk');
    final key = m?['key'] as String?;
    return key == null || key.isEmpty ? null : (port: (m!['port'] as num?)?.toInt() ?? 8080, key: key);
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}
