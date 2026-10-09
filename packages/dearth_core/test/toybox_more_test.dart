import 'dart:math';

import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

/// The Toybox's second set of number and letter games (SPEC FR-TOY-03,
/// Appendix B), built on the games the family's kid plays most.
void main() {
  group('Cookie Count', () {
    test('FR-TOY-03: 1–5 with spots → 2–5 → 5–10 → a plate that starts one to three off', () {
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        for (var level = 1; level <= gameById('cookies')!.levels; level++) {
          final r = cookieRound(level, rng);
          final why = 'seed $seed, level $level: want ${r.want}, start ${r.start}';
          final (lo, hi) = switch (level) { 1 => (1, 5), 2 => (2, 5), 3 => (5, 10), _ => (3, 10) };
          expect(r.want, inInclusiveRange(lo, hi), reason: why);
          expect(r.spots, level == 1, reason: why);
          if (level < 4) {
            expect(r.start, 0, reason: why);
          } else {
            expect((r.start - r.want).abs(), inInclusiveRange(1, 3), reason: 'too few or too many, never right ($why)');
            expect(r.start, inInclusiveRange(1, kCookiePlate), reason: why);
          }
        }
      }
    });

    test('every number comes up, the top level both adds and takes away, and never the same number twice running', () {
      final seen = <int>{};
      var over = 0, under = 0;
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        CookieRound? last;
        for (var i = 0; i < 6; i++) {
          final r = cookieRound(4, rng, last: last);
          if (last != null) expect(r.want, isNot(last.want));
          last = r;
          seen.add(r.want);
          r.start > r.want ? over++ : under++;
        }
      }
      expect(seen, {for (var n = 3; n <= 10; n++) n});
      expect(over, greaterThan(300));
      expect(under, greaterThan(300));
    });

    test('slips: the right plate first time is a win, one wrong ring is helped, then a miss', () {
      expect([for (var s = 0; s <= 2; s++) cookieResult(s)], [GameResult.win, GameResult.helped, GameResult.miss]);
    });

    test('the monster can ask for, praise and correct every number on the plate', () {
      for (var n = 1; n <= kCookiePlate; n++) {
        for (final clip in [cookieAskClip(n), cookieYumClip(n), cookieMoreClip(n), cookieFewerClip(n)]) {
          expect(kVoiceLines, contains(clip));
        }
      }
      expect(kVoiceLines[cookieAskClip(1)], 'I want [[wˈʌn]] cookie!');
      expect(kVoiceLines[cookieAskClip(5)], 'I want five cookies!');
    });
  });
}
