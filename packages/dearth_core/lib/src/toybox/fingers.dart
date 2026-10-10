import 'dart:math';

import 'package:meta/meta.dart';

import 'rounds.dart';

// Finger Count (SPEC FR-TOY-03, Appendix B: fingers as numbers). Number
// Tracing's numerals and number words, tied to the counting tool she
// always has with her. "Show me three fingers!": raise them in order,
// then any finger, then two hands for 6–10 — a whole hand and some more —
// with a palm tap that raises five at once. A high five checks. The top
// level turns it around: the hand shows fingers and she picks the number.

enum FingerMode { inOrder, any, twoHands, read }

@immutable
class FingerRound {
  const FingerRound(this.mode, this.want, {this.choices = const []});

  /// The round's way of playing (the ladder above).
  final FingerMode mode;

  /// How many fingers to show — or, in read mode, how many are shown.
  final int want;

  /// Read mode: three distinct numbers, [want] among them, all in 1–10.
  final List<int> choices;

  int get hands => want > 5 ? 2 : 1;
}

/// A round at [level]; the want never repeats [last]'s.
FingerRound fingerRound(int level, Random rng, {FingerRound? last}) {
  for (var i = 0;; i++) {
    final r = _round(level, rng);
    if (last == null || r.want != last.want || i >= 20) return r;
  }
}

FingerRound _round(int level, Random rng) {
  switch (level) {
    case <= 1:
      return FingerRound(FingerMode.inOrder, 1 + rng.nextInt(5));
    case 2:
      return FingerRound(FingerMode.any, 1 + rng.nextInt(5));
    case 3:
      return FingerRound(FingerMode.twoHands, 6 + rng.nextInt(5));
    default:
      final want = 1 + rng.nextInt(10);
      return FingerRound(FingerMode.read, want, choices: _choices(want, rng));
  }
}

/// Three distinct numbers in 1–10 with [want] among them: its neighbors
/// ±1, or for 6–10 the number five apart (the whole hand beside the
/// some-more), the rest of the range as a fallback.
List<int> _choices(int want, Random rng) {
  final near = [for (final d in [-1, 1, -5, 5]) if (want + d >= 1 && want + d <= 10) want + d]..shuffle(rng);
  final far = [for (var n = 1; n <= 10; n++) if (n != want) n]..shuffle(rng);
  final out = <int>[];
  for (var guard = 0; out.length < 2 && guard < 100; guard++) {
    final n = near.isNotEmpty ? near.removeLast() : far.removeLast();
    if (n != want && !out.contains(n)) out.add(n);
  }
  return ([want, ...out]..shuffle(rng));
}

/// A wrong high five is a slip: the first is "helped", more a miss.
String fingerResult(int slips) => countingResult(slips);

/// Fingers in counting order: thumb, index, middle, ring, pinky.
const List<String> kFingerNames = ['Thumb', 'Index finger', 'Middle finger', 'Ring finger', 'Pinky'];
