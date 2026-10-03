import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sound_none.dart' if (dart.library.js_interop) 'sound_web.dart' if (dart.library.ffi) 'sound_native.dart' as platform;
import 'synth.dart';

/// Short sounds (SPEC §11.5): chimes for reminders and timers, and the kid
/// surfaces' taps and successes. The adult UI is otherwise silent.
enum Sfx { reminder, timer, success, tap }

/// Plays [Sfx]. Sound is never essential: implementations swallow errors
/// (no audio device, a browser that blocks autoplay).
abstract interface class SoundPlayer {
  /// [volume] 0…1 (timers chime louder as they keep ringing).
  Future<void> play(Sfx sfx, {double volume = 1});
}

/// Plays nothing (tests, and platforms without an audio engine).
class SilentSound implements SoundPlayer {
  const SilentSound();

  @override
  Future<void> play(Sfx sfx, {double volume = 1}) async {}
}

/// The synthesized samples of [sfx].
Float32List samplesFor(Sfx sfx) => switch (sfx) {
      Sfx.reminder => reminderChime(),
      Sfx.timer => timerChime(),
      Sfx.success => successRun(),
      Sfx.tap => tapTock(),
    };

/// WebAudio on the web, flutter_soloud on native platforms.
final soundProvider = Provider<SoundPlayer>((ref) => platform.createSoundPlayer());
