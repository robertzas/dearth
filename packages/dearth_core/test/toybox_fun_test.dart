import 'dart:math';

import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

/// The fourth set (SPEC FR-TOY-03, 2026-10-13): four number games for fun.
void main() {
  int levels(String id) => gameById(id)!.levels;

  test('FR-TOY-03 Dice Dash: a 1–3 die on 12 squares → 1–6 with ladders and slides → saying where she lands → two dice', () {
    for (var seed = 0; seed < 200; seed++) {
      for (var level = 1; level <= levels('dice'); level++) {
        final b = diceBoard(level, Random(seed));
        expect(b.squares, const [12, 18, 18, 20][level - 1]);
        expect(b.mode, level == 3 ? DiceMode.landOn : DiceMode.hop);
        expect((b.dice, b.faces), level == 4 ? (2, 3) : (1, level == 1 ? 3 : 6));
        expect(b.jumps.length, const [0, 3, 3, 4][level - 1], reason: 'seed $seed, level $level');
        for (final MapEntry(key: from, value: to) in b.jumps.entries) {
          expect(from, inExclusiveRange(0, b.cake));
          expect(to, inExclusiveRange(0, b.cake));
          expect(b.jumps.containsKey(to), isFalse, reason: 'no chains');
          // Straight up or down one row of the track.
          expect((from ~/ kDiceRow - to ~/ kDiceRow).abs(), 1);
          expect(to, anyOf(diceAbove(from), diceBelow(from)));
        }
        expect(b.jumps.entries.where((e) => e.value > e.key).length, const [0, 2, 2, 2][level - 1], reason: 'ladders');
        final roll = diceRoll(b, Random(seed));
        expect(roll.length, b.dice);
        expect(roll.every((d) => d >= 1 && d <= b.faces), isTrue);
      }
    }
    final b = diceBoard(1, Random(1));
    expect(b.landing(10, 3), b.cake, reason: 'the cake stops her: no exact roll needed');
    expect(b.afterJump(5), 5);
    expect(diceAbove(0), 11, reason: 'rows wind: the square above the first is the last of row two');
    expect(diceBelow(11), 0);
    expect(kVoiceLines[diceTwoClip(3, 2)], 'Three and two make five! Hop five times!');
    expect(kVoiceLines[diceHopClip(1)], '[[wˈʌn]]! Hop [[wˈʌn]] time!');
  });

  test('FR-TOY-03 Block Tower: build to 1–5 with an outline → 3–10 → as tall as the red one → one taller or shorter', () {
    for (var seed = 0; seed < 200; seed++) {
      TowerRound? last;
      for (var level = 1; level <= levels('tower'); level++) {
        final r = towerRound(level, Random(seed), last: last);
        expect(r.target, inInclusiveRange(1, kTowerMax), reason: 'seed $seed, level $level');
        switch (level) {
          case 1:
            expect((r.ask, r.outline, r.other), (TowerAsk.build, true, 0));
            expect(r.target, lessThanOrEqualTo(5));
          case 2:
            expect((r.ask, r.outline, r.other), (TowerAsk.build, false, 0));
            expect(r.target, greaterThanOrEqualTo(3));
          case 3:
            expect(r.ask, TowerAsk.match);
            expect(r.target, r.other);
          default:
            expect(r.ask, anyOf(TowerAsk.oneMore, TowerAsk.oneLess));
            expect(r.target, r.ask == TowerAsk.oneMore ? r.other + 1 : r.other - 1);
            expect(r.target, greaterThanOrEqualTo(1));
        }
        last = r;
      }
    }
    // Never the same height twice in a row.
    final rng = Random(3);
    var last = towerRound(2, rng);
    for (var i = 0; i < 100; i++) {
      final r = towerRound(2, rng, last: last);
      expect(r.target, isNot(last.target));
      last = r;
    }
    for (var n = 1; n <= kTowerMax; n++) {
      expect(kVoiceLines, containsPair(towerBuildClip(n), contains('tall')));
    }
    expect(towerResult(0), GameResult.win);
    expect(towerResult(1), GameResult.helped);
  });

  test('FR-TOY-03 Drum Count: 1–3 counted along → 1–5 watched → 1–5 played → 2–6 heard behind a curtain; near choices', () {
    for (var seed = 0; seed < 200; seed++) {
      for (var level = 1; level <= levels('drums'); level++) {
        final r = drumRound(level, Random(seed));
        expect(r.mode, DrumMode.values[level - 1]);
        final (lo, hi) = const [(1, 3), (1, 5), (1, 5), (2, 6)][level - 1];
        expect(r.beats, inInclusiveRange(lo, hi), reason: 'seed $seed, level $level');
        if (r.mode == DrumMode.play) {
          expect(r.choices, isEmpty);
          expect(kVoiceLines, contains(drumPlayClip(r.beats)));
        } else {
          expect(r.choices, contains(r.beats));
          expect(r.choices.length, level == 1 ? 2 : 3);
          expect(r.choices.toSet().length, r.choices.length);
          expect(r.choices, orderedEquals([...r.choices]..sort()));
          expect(r.choices.every((c) => c >= 1 && (c - r.beats).abs() <= 2), isTrue, reason: '${r.choices} for ${r.beats}');
        }
        expect(kVoiceLines, contains(drumYesClip(r.beats)));
      }
    }
    for (var n = 1; n <= 9; n++) {
      expect(kVoiceLines, contains(drumWasClip(n)), reason: 'what she played, up to nine beats');
    }
  });

  test('FR-TOY-03 Peekaboo Pals: 2–3 friends → 4–5 → 6–10 → a total on a sign; some always hide; the answer is a choice', () {
    var allHid = 0;
    for (var seed = 0; seed < 300; seed++) {
      for (var level = 1; level <= levels('peekaboo'); level++) {
        final r = peekabooRound(level, Random(seed));
        final (lo, hi) = const [(2, 3), (4, 5), (6, 10), (3, 8)][level - 1];
        expect(r.total, inInclusiveRange(lo, hi), reason: 'seed $seed, level $level');
        expect(r.hiding, inInclusiveRange(1, r.total));
        expect(r.sign, level == 4);
        if (r.sign) expect(r.showing, greaterThan(0), reason: 'a sign round shows some');
        if (r.hiding == r.total) allHid++;
        expect(r.choices, contains(r.hiding));
        expect(r.choices.toSet().length, r.choices.length);
        expect(r.choices.every((c) => c >= 1 && c <= r.total), isTrue, reason: 'one always hides: no 0');
        expect(r.choices.length, min(3, r.total));
        expect(kPeekabooFriends, contains(r.friend));
        expect(kVoiceLines, contains(peekYesClip(r.hiding)));
        if (r.sign) {
          expect(kVoiceLines, contains(peekSignClip(r.total)));
        } else {
          expect(kVoiceLines, contains(peekPlayClip(r.total)));
        }
      }
    }
    expect(allHid, greaterThan(0), reason: 'now and then they all hide');
    expect(kVoiceLines[peekYesClip(1)], '[[wˈʌn]] was hiding!');
  });
}
