import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../update/local_adb.dart';

final _log = Logger('KeyboardAllow');

/// Lets the chosen keyboard run on Allwinner frames (the JT215M).
///
/// Their ROM's background manager (AWBMS, `dumpsys background`) refuses to
/// start any service of an app outside its whitelist, silently: a keyboard
/// installed by deploy_frame.sh (HeliBoard) never connects, and tapping a
/// field brings up nothing. The vendor list names a few Chinese keyboards
/// and the user list (`setUserWhitelist`, transaction 4) lives in memory
/// only, so it's empty after every boot. Once per launch, through the
/// frame's own root adbd (as the updater installs), this puts the default
/// keyboard's package on that list; Android connects it at the next tap on
/// a field. Elsewhere there's no such service or no open adbd, and nothing
/// happens.
final keyboardAllowProvider = Provider<void>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  unawaited(() async {
    try {
      final out = await LocalAdb().shell(keyboardAllowCommand, timeout: const Duration(seconds: 10));
      if (out.trim().isNotEmpty) _log.info('keyboard whitelisted: ${out.trim()}');
    } on AdbException catch (e) {
      _log.fine('no local adbd: $e');
    }
  }());
});

/// The shell side: only where the service exists and a keyboard is set.
@visibleForTesting
const keyboardAllowCommand = r'''
case "$(service list)" in *'[android.aw.IBackgroundManager]'*) ;; *) exit 0 ;; esac
ime=$(settings get secure default_input_method); pkg=${ime%%/*}
case "$pkg" in ''|null) exit 0 ;; esac
service call background 4 i32 1 s16 "$pkg" >/dev/null && echo "$pkg"
''';
