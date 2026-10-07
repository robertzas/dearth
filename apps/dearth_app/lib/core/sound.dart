import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sound_none.dart' if (dart.library.js_interop) 'sound_web.dart' if (dart.library.ffi) 'sound_native.dart' as platform;
import 'synth.dart';

/// Short sounds (SPEC §11.5): chimes for reminders and timers, kid taps and
/// successes, and the Toybox's effects, instruments and animals. The adult
/// UI is otherwise silent.
enum Sfx {
  reminder,
  timer,
  success,
  tap,
  // Toybox effects (FR-TOY-08).
  pop,
  sparkle,
  boing,
  snap,
  munch,
  nope,
  cheer,
  blip,
  honk,
  // The music toy: one xylophone bar (pitched by rate) and four drums.
  xylophone,
  kick,
  snare,
  hat,
  tom,
  // Animal Farm: CC0 recordings (tool/sounds/animals.py).
  cow,
  pig,
  sheep,
  rooster,
  chicken,
  horse,
  dog,
  cat,
  frog,
  owl,
  // Music Sequencer: one short call each, cut from the same recordings.
  dogBeat,
  catBeat,
  frogBeat,
  chickenBeat,
}

/// The farm's animals (recordings in assets/sounds/animals).
const Set<Sfx> kAnimalSounds = {Sfx.cow, Sfx.pig, Sfx.sheep, Sfx.rooster, Sfx.chicken, Sfx.horse, Sfx.dog, Sfx.cat, Sfx.frog, Sfx.owl, Sfx.dogBeat, Sfx.catBeat, Sfx.frogBeat, Sfx.chickenBeat};

/// The xylophone sample's pitch (C4); bars play it at `rate = 2^(semitones/12)`.
const int kXylophoneBaseMidi = 60;

/// Plays [Sfx]. Sound is never essential: implementations swallow errors
/// (no audio device, a browser that blocks autoplay).
abstract interface class SoundPlayer {
  /// [volume] 0…1 (timers chime louder as they keep ringing). [rate] speeds
  /// the sound up or down, and its pitch with it (xylophone bars, pops).
  Future<void> play(Sfx sfx, {double volume = 1, double rate = 1});

  /// Speaks a bundled voice clip (`assets/voice/<clip>.mp3`, made offline by
  /// tool/sounds/voice.py: the frame has no text-to-speech). A new line
  /// stops the one still speaking, so prompts never talk over each other.
  Future<void> say(String clip, {double volume = 1});
}

/// Plays nothing (tests, and platforms without an audio engine).
class SilentSound implements SoundPlayer {
  const SilentSound();

  @override
  Future<void> play(Sfx sfx, {double volume = 1, double rate = 1}) async {}

  @override
  Future<void> say(String clip, {double volume = 1}) async {}
}

/// A voice clip's encoded bytes.
Future<Uint8List> voiceBytes(String clip) async {
  final data = await rootBundle.load('assets/voice/$clip.mp3');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// The encoded sound of [sfx]: a synthesized WAV, or a bundled recording.
Future<Uint8List> soundBytes(Sfx sfx) async {
  if (kAnimalSounds.contains(sfx)) {
    final data = await rootBundle.load('assets/sounds/animals/${sfx.name}.mp3');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
  return wavBytes(samplesFor(sfx));
}

/// The synthesized samples of [sfx] (not the recordings).
Float32List samplesFor(Sfx sfx) => switch (sfx) {
      Sfx.reminder => reminderChime(),
      Sfx.timer => timerChime(),
      Sfx.success => successRun(),
      Sfx.tap => tapTock(),
      Sfx.pop => popSound(),
      Sfx.sparkle => sparkleSound(),
      Sfx.boing => boingSound(),
      Sfx.snap => snapSound(),
      Sfx.munch => munchSound(),
      Sfx.nope => nopeSound(),
      Sfx.cheer => cheerSound(),
      Sfx.blip => blipSound(),
      Sfx.honk => honkSound(),
      Sfx.xylophone => xylophoneNote(kXylophoneBaseMidi),
      Sfx.kick => kickDrum(),
      Sfx.snare => snareDrum(),
      Sfx.hat => hatDrum(),
      Sfx.tom => tomDrum(),
      _ => throw ArgumentError('${sfx.name} is a recording'),
    };

/// WebAudio on the web, flutter_soloud on native platforms.
final soundProvider = Provider<SoundPlayer>((ref) => platform.createSoundPlayer());
