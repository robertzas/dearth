import 'dart:math' as math;
import 'dart:typed_data';

/// Sound synthesis for the app's short sounds and the toy instruments
/// (SPEC §11.5): mono 16-bit PCM WAV generated in Dart. There are no audio
/// assets to license or ship, and every sound is peak-normalized to its
/// category's level.
const int kSynthRate = 44100;

/// One partial of a struck tone: frequency [ratio] to the fundamental,
/// relative [amp]litude, and [decay] time constant in seconds.
typedef Partial = (double ratio, double amp, double decay);

/// A small bell or glockenspiel: inharmonic upper partials that die fast.
const List<Partial> kBellPartials = [(1, 1, 0.9), (2.76, 0.42, 0.35), (5.40, 0.2, 0.16), (8.93, 0.08, 0.08)];

/// A marimba or xylophone bar: a strong fundamental, a quick 4th partial.
const List<Partial> kMalletPartials = [(1, 1, 0.45), (3.93, 0.22, 0.07), (9.0, 0.05, 0.03)];

double midiToHz(num midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();

/// A struck tone at [hz]: the [partials] with exponential decay and a few
/// milliseconds of attack (no click).
Float32List strike(double hz, {double seconds = 1.2, List<Partial> partials = kBellPartials, double attack = 0.004, int rate = kSynthRate}) {
  final n = (seconds * rate).round();
  final out = Float32List(n);
  final attackN = math.max(1, (attack * rate).round());
  // The last 30 ms fade to zero so a cut tail never clicks.
  final fadeN = math.min(n, (0.03 * rate).round());
  for (final (ratio, amp, decay) in partials) {
    final f = hz * ratio;
    if (f >= rate / 2) continue; // above Nyquist: would alias
    final w = 2 * math.pi * f / rate;
    final k = 1 / (decay * rate);
    for (var i = 0; i < n; i++) {
      out[i] += amp * math.sin(w * i) * math.exp(-k * i);
    }
  }
  for (var i = 0; i < attackN && i < n; i++) {
    out[i] *= i / attackN;
  }
  for (var i = 0; i < fadeN; i++) {
    out[n - 1 - i] *= i / fadeN;
  }
  return out;
}

/// Mixes [voices] (start offset in seconds, samples) into one buffer and
/// scales it to [peak].
Float32List mix(List<(double at, Float32List voice)> voices, {double peak = 0.8, int rate = kSynthRate}) {
  var n = 0;
  for (final (at, v) in voices) {
    n = math.max(n, (at * rate).round() + v.length);
  }
  final out = Float32List(n);
  for (final (at, v) in voices) {
    final o = (at * rate).round();
    for (var i = 0; i < v.length; i++) {
      out[o + i] += v[i];
    }
  }
  return normalize(out, peak: peak);
}

/// Scales [s] in place so its loudest sample is [peak].
Float32List normalize(Float32List s, {double peak = 0.8}) {
  var max = 0.0;
  for (final x in s) {
    if (x.abs() > max) max = x.abs();
  }
  if (max == 0) return s;
  final g = peak / max;
  for (var i = 0; i < s.length; i++) {
    s[i] *= g;
  }
  return s;
}

/// A mono 16-bit PCM WAV file of [samples] (−1…1).
Uint8List wavBytes(Float32List samples, {int rate = kSynthRate}) {
  final data = samples.length * 2;
  final b = ByteData(44 + data);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  b.setUint32(4, 36 + data, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  b.setUint32(16, 16, Endian.little); // PCM chunk size
  b.setUint16(20, 1, Endian.little); // PCM
  b.setUint16(22, 1, Endian.little); // mono
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * 2, Endian.little); // byte rate
  b.setUint16(32, 2, Endian.little); // block align
  b.setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  b.setUint32(40, data, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    b.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return b.buffer.asUint8List();
}

// ───────────────────────────────── Sounds ──────────────────────────────────

/// Reminder: a soft two-note "ding-dong" (E6 → C6).
Float32List reminderChime() => mix([
      (0, strike(midiToHz(88), seconds: 1.4)),
      (0.32, strike(midiToHz(84), seconds: 1.6)),
    ], peak: 0.7);

/// Timer done: a bright rising arpeggio (C6 E6 G6 C7) a family hears from
/// the next room; the timer repeats it, growing louder (FR-TMR-01).
Float32List timerChime() => mix([
      for (final (i, m) in const [84, 88, 91, 96].indexed) (i * 0.14, strike(midiToHz(m))),
    ], peak: 0.85);

/// A kid's success: a quick marimba run up (C5 E5 G5 C6).
Float32List successRun() => mix([
      for (final (i, m) in const [72, 76, 79, 84].indexed) (i * 0.09, strike(midiToHz(m), seconds: 0.8, partials: kMalletPartials)),
    ], peak: 0.6);

/// A soft wooden tap for kid buttons.
Float32List tapTock() => normalize(strike(midiToHz(79), seconds: 0.12, partials: kMalletPartials, attack: 0.002), peak: 0.35);

/// One xylophone bar (toybox instrument), [midi] note.
Float32List xylophoneNote(int midi) => normalize(strike(midiToHz(midi), seconds: 1.1, partials: kMalletPartials), peak: 0.7);

// ──────────────────────────────── Toybox ───────────────────────────────────
// Game effects (SPEC FR-TOY-08): short, round and never harsh. Noise comes
// from a seeded generator, so every build sounds the same.

Float32List _render(double seconds, double Function(double t, int i) sample, {int rate = kSynthRate}) {
  final out = Float32List((seconds * rate).round());
  for (var i = 0; i < out.length; i++) {
    out[i] = sample(i / rate, i);
  }
  return out;
}

/// −1…1 white noise, repeatable.
Float32List _noise(double seconds, {int seed = 7, int rate = kSynthRate}) {
  final rng = math.Random(seed);
  return _render(seconds, (_, _) => rng.nextDouble() * 2 - 1, rate: rate);
}

/// A sine whose pitch slides from [from] to [to] Hz (exponentially), with
/// an exponential [decay] (seconds to fall to ~37 %).
Float32List _sweep(double from, double to, double seconds, {double decay = 0.1, double attack = 0.003, int rate = kSynthRate}) {
  var phase = 0.0;
  return _render(seconds, (t, _) {
    final hz = from * math.pow(to / from, t / seconds);
    phase += 2 * math.pi * hz / rate;
    final env = math.min(1.0, t / attack) * math.exp(-t / decay);
    return math.sin(phase) * env;
  }, rate: rate);
}

/// [noise] through a one-pole high-pass ([cutoff] Hz), shaped by [decay].
Float32List _hiss(double seconds, {double cutoff = 4000, double decay = 0.05, int seed = 7, int rate = kSynthRate}) {
  final n = _noise(seconds, seed: seed, rate: rate);
  final rc = 1 / (2 * math.pi * cutoff), a = rc / (rc + 1 / rate);
  var prevIn = 0.0, prevOut = 0.0;
  for (var i = 0; i < n.length; i++) {
    final y = a * (prevOut + n[i] - prevIn);
    prevIn = n[i];
    prevOut = y;
    n[i] = y * math.exp(-(i / rate) / decay);
  }
  return n;
}

/// [noise] through a one-pole low-pass ([cutoff] Hz): rumbles and crunches.
Float32List _rumble(Float32List s, {double cutoff = 900, int rate = kSynthRate}) {
  final dt = 1 / rate, rc = 1 / (2 * math.pi * cutoff), a = dt / (rc + dt);
  var y = 0.0;
  for (var i = 0; i < s.length; i++) {
    y += a * (s[i] - y);
    s[i] = y;
  }
  return s;
}

/// A bubble popping: a quick upward blip with a click.
Float32List popSound() => mix([(0, _sweep(380, 1100, 0.09, decay: 0.03)), (0, _hiss(0.012, cutoff: 2500, decay: 0.003))], peak: 0.6);

/// Fireworks and fairy dust: high bells sprinkled over a third of a second.
Float32List sparkleSound() {
  final rng = math.Random(3);
  return mix([
    for (var i = 0; i < 7; i++) (i * 0.045 + rng.nextDouble() * 0.02, strike(1800 + rng.nextDouble() * 2400, seconds: 0.35, partials: const [(1, 1, 0.12), (2.76, 0.3, 0.05)])),
  ], peak: 0.45);
}

/// A springy "boing": a low note that wobbles and settles.
Float32List boingSound() {
  var phase = 0.0;
  return normalize(_render(0.45, (t, _) {
    final hz = 180 * (1 + 0.35 * math.exp(-t / 0.12) * math.sin(2 * math.pi * 14 * t));
    phase += 2 * math.pi * hz / kSynthRate;
    return math.sin(phase) * math.min(1.0, t / 0.004) * math.exp(-t / 0.16);
  }), peak: 0.55);
}

/// A piece clicking into place.
Float32List snapSound() => mix([(0, _hiss(0.03, cutoff: 1800, decay: 0.006)), (0.004, strike(1400, seconds: 0.08, partials: kMalletPartials))], peak: 0.55);

/// The monster munching: three crunchy bites.
Float32List munchSound() => mix([
      for (var i = 0; i < 3; i++) (i * 0.13, normalize(_rumble(_hiss(0.09, cutoff: 300, decay: 0.03, seed: 11 + i), cutoff: 1600), peak: 1)),
    ], peak: 0.6);

/// A gentle "uh-uh": two soft notes down. Never a buzzer (FR-TOY-04).
Float32List nopeSound() => mix([
      (0, strike(midiToHz(64), seconds: 0.35, partials: kMalletPartials)),
      (0.16, strike(midiToHz(60), seconds: 0.45, partials: kMalletPartials)),
    ], peak: 0.4);

/// A round won: a marimba run up with sparkles on top.
Float32List cheerSound() => mix([
      for (final (i, m) in const [72, 76, 79, 84, 88].indexed) (i * 0.08, strike(midiToHz(m), seconds: 0.9, partials: kMalletPartials)),
      (0.36, sparkleSound()),
    ], peak: 0.65);

/// One counted flower: a short mallet note (the game raises its pitch).
Float32List blipSound() => normalize(strike(midiToHz(72), seconds: 0.3, partials: kMalletPartials, attack: 0.002), peak: 0.55);

/// A bus horn, friendly: "beep-beep", two notes a third apart sounding
/// together (a car horn's chord), mellow harmonics, soft edges.
Float32List honkSound() {
  Float32List beep(double seconds) => _render(seconds, (t, _) {
        var x = 0.0;
        for (final hz in const [392.0, 494.0]) {
          for (var k = 1; k <= 5; k++) {
            x += math.sin(2 * math.pi * hz * k * t) / (k * k);
          }
        }
        // 8 ms in and out: a toot, not a click.
        return x * math.min(1.0, math.min(t, seconds - t) / 0.008);
      });
  return mix([(0, beep(0.12)), (0.18, beep(0.2))], peak: 0.5);
}

/// Drums for the music toy: kick, snare, hi-hat, tom.
Float32List kickDrum() => normalize(_sweep(150, 42, 0.32, decay: 0.12, attack: 0.002), peak: 0.85);
Float32List snareDrum() => mix([(0, _hiss(0.2, cutoff: 1200, decay: 0.07, seed: 5)), (0, _sweep(210, 170, 0.12, decay: 0.05))], peak: 0.7);
Float32List hatDrum() => normalize(_hiss(0.08, cutoff: 6000, decay: 0.02, seed: 9), peak: 0.45);
Float32List tomDrum() => normalize(_sweep(130, 90, 0.4, decay: 0.15), peak: 0.75);
