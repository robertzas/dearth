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
