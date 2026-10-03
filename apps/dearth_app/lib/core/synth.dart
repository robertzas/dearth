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
