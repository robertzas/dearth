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
