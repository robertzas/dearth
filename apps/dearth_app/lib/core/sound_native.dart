import 'dart:async';

import 'package:flutter_soloud/flutter_soloud.dart';

import 'sound.dart';

SoundPlayer createSoundPlayer() => SoLoudSound();

/// Native playback through flutter_soloud (SPEC §7.4): low latency for kid
/// taps and toy instruments. Each sound is synthesized (or read from the
/// bundle) once, on first use, and kept in memory. Starts the engine lazily, so a display that never
/// plays a sound never opens the audio device.
class SoLoudSound implements SoundPlayer {
  Future<bool>? _ready;
  final Map<Sfx, Future<AudioSource>> _sources = {};

  /// Voice clips decoded lately, oldest first: a few dozen at most, so a
  /// long session of words doesn't fill a 2 GB frame's memory.
  final Map<String, Future<AudioSource>> _voices = {};
  SoundHandle? _speaking;
  static const _keepVoices = 32;

  Future<bool> _init() async {
    try {
      // 1024 frames ≈ 23 ms at 44.1 kHz: under the 30 ms the toy
      // instruments need (S10), with headroom for the frame's Cortex-A53.
      if (!SoLoud.instance.isInitialized) await SoLoud.instance.init(bufferSize: 1024);
      return true;
    } on Object {
      return false; // no audio device: stay silent for this session
    }
  }

  @override
  Future<void> play(Sfx sfx, {double volume = 1, double rate = 1}) async {
    try {
      if (!await (_ready ??= _init())) return;
      final source = await (_sources[sfx] ??= soundBytes(sfx).then((b) => SoLoud.instance.loadMem('dearth-${sfx.name}', b)));
      if (rate == 1) {
        SoLoud.instance.play(source, volume: volume);
      } else {
        // Paused first, so the pitch is set before the first sample plays.
        final handle = SoLoud.instance.play(source, volume: volume, paused: true);
        SoLoud.instance.setRelativePlaySpeed(handle, rate);
        SoLoud.instance.setPause(handle, false);
      }
    } on Object {
      _sources.remove(sfx)?.ignore(); // retry the load next time
    }
  }

  @override
  Future<void> say(String clip, {double volume = 1}) async {
    try {
      if (!await (_ready ??= _init())) return;
      final pending = _voices.remove(clip) ?? voiceBytes(clip).then((b) => SoLoud.instance.loadMem('voice-$clip', b));
      _voices[clip] = pending; // newest last
      if (_voices.length > _keepVoices) {
        final oldest = _voices.keys.first;
        unawaited(_voices.remove(oldest)!.then(SoLoud.instance.disposeSource, onError: (Object _) {}));
      }
      final source = await pending;
      final last = _speaking;
      if (last != null) unawaited(SoLoud.instance.stop(last).catchError((Object _) {}));
      _speaking = SoLoud.instance.play(source, volume: volume);
    } on Object {
      _voices.remove(clip)?.ignore();
    }
  }
}
