import 'dart:typed_data';

import 'package:dearth_app/core/sound.dart';
import 'package:dearth_app/core/synth.dart';
import 'package:flutter_test/flutter_test.dart';

/// The synthesized sounds (SPEC §11.5): valid WAV, no clicks, normalized.
void main() {
  double peak(Float32List s) => s.fold(0, (m, x) => x.abs() > m ? x.abs() : m);

  test('WAV files are mono 16-bit PCM with correct sizes', () {
    final s = Float32List.fromList([0, 0.5, -0.5, 1, -1]);
    final b = ByteData.sublistView(wavBytes(s));
    String ascii(int at) => String.fromCharCodes(b.buffer.asUint8List(b.offsetInBytes + at, 4));
    expect((ascii(0), ascii(8), ascii(12), ascii(36)), ('RIFF', 'WAVE', 'fmt ', 'data'));
    expect(b.getUint32(4, Endian.little), 36 + 10);
    expect((b.getUint16(20, Endian.little), b.getUint16(22, Endian.little), b.getUint32(24, Endian.little), b.getUint16(34, Endian.little)), (1, 1, kSynthRate, 16));
    expect(b.getUint32(40, Endian.little), 10);
    expect([for (var i = 0; i < 5; i++) b.getInt16(44 + i * 2, Endian.little)], [0, 16384, -16384, 32767, -32767]);
  });

  test('a struck tone starts and ends at silence (no clicks)', () {
    final s = strike(midiToHz(69), seconds: 0.5);
    expect(s.length, (0.5 * kSynthRate).round());
    expect(s.first, 0);
    expect(s.last.abs(), lessThan(1e-3));
    expect(s.every((x) => x.isFinite), isTrue);
  });

  test('partials above Nyquist are skipped rather than aliased', () {
    // 8.93 × 4 kHz is far above 22.05 kHz; only the lower partials remain.
    expect(strike(4000, seconds: 0.1).every((x) => x.isFinite), isTrue);
  });

  test('every sound is normalized to its level', () {
    expect(peak(reminderChime()), closeTo(0.7, 1e-6));
    expect(peak(timerChime()), closeTo(0.85, 1e-6));
    expect(peak(successRun()), closeTo(0.6, 1e-6));
    expect(peak(tapTock()), closeTo(0.35, 1e-6));
    expect(peak(xylophoneNote(72)), closeTo(0.7, 1e-6));
  });

  test('toybox sounds (FR-TOY-08): audible, never clipped, short and soft-edged', () {
    for (final sfx in Sfx.values.where((s) => !kAnimalSounds.contains(s))) {
      final s = samplesFor(sfx);
      expect(peak(s), inInclusiveRange(0.3, 0.9), reason: sfx.name);
      expect(s.length / kSynthRate, lessThan(sfx == Sfx.reminder || sfx == Sfx.timer ? 3 : 1.5), reason: sfx.name);
      // The last 5 ms fade out: no click when a sound ends.
      final tail = s.sublist(s.length - kSynthRate ~/ 200);
      expect(peak(tail), lessThan(0.08), reason: '${sfx.name} ends with a click');
    }
    expect(samplesFor(Sfx.cheer), isNot(samplesFor(Sfx.success)));
  });

  test('every farm animal is a bundled recording', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final sfx in kAnimalSounds) {
      final bytes = await soundBytes(sfx);
      // An MP3: an ID3 tag or a frame sync.
      final mp3 = (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) || (bytes[0] == 0xFF && bytes[1] & 0xE0 == 0xE0);
      expect((mp3, bytes.length > 2000), (true, true), reason: sfx.name);
    }
    expect(() => samplesFor(Sfx.cow), throwsArgumentError);
  });

  test('pitches follow equal temperament (A4 = 440 Hz)', () {
    expect(midiToHz(69), 440);
    expect(midiToHz(81), closeTo(880, 1e-9));
    expect(midiToHz(60), closeTo(261.6256, 1e-4));
  });
}
