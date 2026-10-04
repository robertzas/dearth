import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'sound.dart';

SoundPlayer createSoundPlayer() => WebSound();

/// WebAudio playback: each sound (a synthesized WAV or a bundled MP3) is
/// decoded once into an AudioBuffer. No extra script or WASM on the page. Browsers keep the
/// context suspended until the first touch, so a reminder before anyone
/// has touched the screen may stay silent; the banner still shows.
class WebSound implements SoundPlayer {
  web.AudioContext? _ctx;
  final Map<Sfx, Future<web.AudioBuffer>> _buffers = {};

  @override
  Future<void> play(Sfx sfx, {double volume = 1, double rate = 1}) async {
    try {
      final ctx = _ctx ??= web.AudioContext();
      // Don't await: without a user gesture the promise may never settle.
      if (ctx.state == 'suspended') unawaited(ctx.resume().toDart.then((_) {}, onError: (Object _) {}));
      final buffer = await (_buffers[sfx] ??= soundBytes(sfx).then((b) => ctx.decodeAudioData(b.buffer.toJS).toDart));
      final source = ctx.createBufferSource()..buffer = buffer;
      if (rate != 1) source.playbackRate.value = rate;
      final gain = ctx.createGain()..gain.value = volume;
      source.connect(gain);
      gain.connect(ctx.destination);
      source.start();
    } on Object {
      // No audio device or a blocked context: sound is never essential.
    }
  }
}
