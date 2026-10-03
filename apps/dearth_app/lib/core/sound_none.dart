import 'sound.dart';

/// Platforms with neither WebAudio nor FFI: silence.
SoundPlayer createSoundPlayer() => const SilentSound();
