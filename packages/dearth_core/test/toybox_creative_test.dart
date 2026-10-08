import 'dart:math';

import 'package:dearth_core/dearth_core.dart';
import 'package:test/test.dart';

/// The Toybox's make-and-move games (SPEC FR-TOY-03, Appendix B).
void main() {
  group('Build-a-Creature', () {
    test('FR-TOY-03: body and face, then top and legs, then arms and tail; 4 → 6 → 8 paints', () {
      expect(creatureParts(1), [CreaturePart.body, CreaturePart.face]);
      expect(creatureParts(2), [CreaturePart.body, CreaturePart.face, CreaturePart.top, CreaturePart.legs]);
      expect(creatureParts(3), CreaturePart.values);
      expect([for (var l = 1; l <= 3; l++) creatureColors(l)], [4, 6, 8]);
      expect(gameById('creature')!.levels, 3);
    });

    test('a part goes round its options, "none" included, and the name comes from body and face', () {
      var c = const Creature({}, 0);
      for (var i = 1; i <= kCreatureOptions[CreaturePart.top]!; i++) {
        c = c.next(CreaturePart.top);
        expect(c[CreaturePart.top], i % kCreatureOptions[CreaturePart.top]!);
      }
      expect(c[CreaturePart.top], 0, reason: 'back to none');
      expect(const Creature({CreaturePart.face: 1}, 0).name, 'Wobblesaurus');
      expect(const Creature({CreaturePart.body: 3, CreaturePart.face: 3}, 0).name, 'Boingopop');
      expect(kCreatureNames.toSet(), hasLength(kCreaturePrefixes.length * kCreatureSuffixes.length), reason: 'every name is different');
      // A part left out is none: equal, and hashed alike.
      const a = Creature({CreaturePart.body: 2}, 1), b = Creature({CreaturePart.body: 2, CreaturePart.tail: 0}, 1);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.withColor(2), isNot(a));
    });

    test('a surprise has every part its level shows, never "none", and a paint it offers', () {
      for (var seed = 0; seed < 200; seed++) {
        for (var level = 1; level <= 3; level++) {
          final c = randomCreature(level, Random(seed));
          final shown = creatureParts(level);
          for (final p in CreaturePart.values) {
            final optional = p != CreaturePart.body && p != CreaturePart.face;
            if (!shown.contains(p)) {
              expect(c[p], 0, reason: '$p is hidden at $level');
            } else {
              expect(c[p], inInclusiveRange(optional ? 1 : 0, kCreatureOptions[p]! - 1), reason: '$p at $level, seed $seed');
            }
          }
          expect(c.color, inInclusiveRange(0, creatureColors(level) - 1));
        }
      }
    });

    test('every creature says its own name, and every part and paint has a word', () {
      for (final name in kCreatureNames) {
        expect(kVoiceLines[creatureNameClip(name)], "I'm a $name!");
      }
      for (final p in CreaturePart.values) {
        expect(kCreaturePartWords[p], hasLength(kCreatureOptions[p]), reason: '$p');
      }
      expect(kVoiceLines[creaturePartClip(CreaturePart.top, 2)], 'Bunny ears!');
      expect(kVoiceLines[colorClip(kCreaturePaints[3])], 'Purple!');
      const c = Creature({CreaturePart.body: 5, CreaturePart.face: 5}, 0);
      expect(creatureClip(c), 'creature_gigglezoo');
    });
  });

  group('Freeze Dance', () {
    test('FR-TOY-03: long dances and steady freezes → uneven ones → a different animal each dance', () {
      expect(gameById('freeze')!.freePlay, isTrue, reason: 'the screen can\'t see her freeze: nothing to score');
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        final one = freezeSong(1, rng), two = freezeSong(2, rng), three = freezeSong(3, rng);
        expect(one, hasLength(4));
        expect(one.every((t) => t.danceMs >= 8000 && t.danceMs <= 10000 && t.freezeMs == 3000 && t.animal == null), isTrue);
        expect(two, hasLength(5));
        expect(two.every((t) => t.danceMs >= 4000 && t.danceMs <= 9000 && t.freezeMs >= 1500 && t.freezeMs <= 5000), isTrue);
        expect(three.map((t) => t.animal).toSet(), hasLength(5), reason: 'a different animal each dance');
        expect(three.every((t) => t.animal != null), isTrue);
      }
      expect(kFreezeTune, hasLength(16));
      expect(kFreezeTune.nonNulls.every((m) => const {0, 2, 4, 7, 9}.contains(m % 12)), isTrue, reason: 'C major pentatonic: nothing sounds wrong');
    });
  });

  group('Music Sequencer', () {
    test('FR-TOY-03: 4 steps × 2 animals → 8 × 2 → 8 × 3 → 8 × 4; a beat to start, the dice never leaves a row empty', () {
      expect(gameById('sequencer')!.freePlay, isTrue);
      expect([for (var l = 1; l <= 4; l++) (sequencerSize(l).steps, sequencerSize(l).tracks.length)], [(4, 2), (8, 2), (8, 3), (8, 4)]);
      final starter = sequencerPattern(sequencerSize(4));
      expect(starter.map((row) => row.where((on) => on).length), [2, 2, 1, 1], reason: 'dog on the beat, cat between, frog and chicken answering');
      expect(starter.first, [true, false, false, false, true, false, false, false]);
      for (var seed = 0; seed < 200; seed++) {
        for (var l = 1; l <= 4; l++) {
          final size = sequencerSize(l);
          final p = sequencerPattern(size, random: Random(seed));
          expect(p, hasLength(size.tracks.length));
          for (final row in p) {
            expect(row, hasLength(size.steps));
            final lit = row.where((on) => on).length;
            expect(lit, inInclusiveRange(1, size.steps ~/ 2), reason: 'seed $seed level $l');
          }
        }
      }
      expect({for (final t in SeqTrack.values) t.sound}, {'dogBeat', 'catBeat', 'frogBeat', 'chickenBeat'});
    });
  });

  group('Weather Dress-Up', () {
    test('FR-TOY-03: the kind of day follows What to wear\'s rules: wet first, then how warm it feels', () {
      expect(dressWeatherFor(feelsLikeC: 2, precipProb: 80, snow: true), DressWeather.snow);
      expect(dressWeatherFor(feelsLikeC: 12, precipMm: 3), DressWeather.rain);
      expect(dressWeatherFor(feelsLikeC: 3), DressWeather.cold);
      expect(dressWeatherFor(feelsLikeC: 14), DressWeather.cool);
      expect(dressWeatherFor(feelsLikeC: 22), DressWeather.warm);
      expect(dressWeatherFor(feelsLikeC: 29), DressWeather.hot);
      expect(dressWeatherFor(feelsLikeC: 9, windKph: 40), DressWeather.cold, reason: 'wind makes it feel colder');
    });

    test('the top → the top and shoes → the whole outfit; one choice suits, the others are the wrong weather\'s', () {
      for (var seed = 0; seed < 200; seed++) {
        for (final w in DressWeather.values) {
          for (var level = 1; level <= 3; level++) {
            final r = dressRound(level, Random(seed), weather: w);
            expect(r.weather, w);
            expect(r.pretend, isFalse);
            expect(r.picks.map((p) => p.slot), switch (level) { 1 => [DressSlot.top], 2 => [DressSlot.top, DressSlot.feet], _ => DressSlot.values });
            for (final p in r.picks) {
              expect(p.choices.where(p.suits.contains), hasLength(1), reason: 'one that suits: $w ${p.slot} ${p.choices}');
              expect(p.choices.length, inInclusiveRange(2, 3));
              expect(p.choices.every((i) => i.slot == p.slot), isTrue);
            }
          }
        }
      }
      // Every kind of day dresses every part, and nothing suits both a snowy and a hot day.
      for (final w in DressWeather.values) {
        expect(kDressSuits[w]!.keys.toSet(), DressSlot.values.toSet());
      }
      for (final slot in DressSlot.values) {
        expect(kDressSuits[DressWeather.hot]![slot]!.intersection(kDressSuits[DressWeather.snow]![slot]!), isEmpty, reason: '$slot');
      }
    });

    test('without a forecast it pretends, a different day each time', () {
      final rng = Random(4);
      DressRound? last;
      for (var i = 0; i < 30; i++) {
        final r = dressRound(2, rng, last: last);
        expect(r.pretend, isTrue);
        if (last != null) expect(r.weather, isNot(last.weather));
        last = r;
      }
    });
  });

  group("Who's That?", () {
    test("FR-TOY-03 Who's That?: a person is asked for by the family word they go by; the child is \"you\", a dog \"the doggy\"", () {
      expect(whoAskFor(name: 'Mom'), 'who_mom');
      expect(whoAskFor(name: 'Sarah', nickname: 'Mommy'), 'who_mommy', reason: 'the nickname the family uses');
      expect(whoAskFor(name: 'Grandma', nickname: 'Gigi'), 'who_grandma', reason: 'an unknown nickname falls back to the name');
      expect(whoAskFor(name: 'GRAND-PA'), 'who_grandpa');
      expect(whoAskFor(name: 'Ava', you: true), 'who_you');
      expect(whoAskFor(name: 'Biscuit', emoji: '🐶', pet: true), 'who_doggy');
      expect(whoAskFor(name: 'Tom', emoji: '🐈', pet: true), 'who_kitty');
      expect(whoAskFor(name: 'Goldie', emoji: '🐠', pet: true), isNull, reason: 'no clip for a fish');
      expect(whoAskFor(name: 'Sarah'), isNull);
      for (final key in kWhoWords.keys) {
        expect(key, matches(RegExp(r'^[a-z]+$')), reason: 'keys are what a name folds to');
      }
    });

    test('playable with two faces, one the voice can ask for', () {
      expect(whoPlayable(const [WhoFace('a', 'who_mom')]), isFalse);
      expect(whoPlayable(const [WhoFace('a', null), WhoFace('b', null)]), isFalse);
      expect(whoPlayable(const [WhoFace('a', 'who_you'), WhoFace('b', null)]), isTrue);
    });

    test('two faces → four → six (as many as there are); the one asked for is on the board, askable, and not the last', () {
      final family = [
        for (final (i, ask) in ['who_you', 'who_mom', 'who_dad', null, 'who_doggy', null, 'who_nana', 'who_papa'].indexed) WhoFace('p$i', ask),
      ];
      for (var seed = 0; seed < 200; seed++) {
        final rng = Random(seed);
        String? last;
        for (var level = 1; level <= 3; level++) {
          final r = whoRound(level, rng, faces: family, last: last);
          expect(r.faces, hasLength([2, 4, 6][level - 1]));
          expect(r.faces.map((f) => f.id).toSet(), hasLength(r.faces.length), reason: 'each face once');
          expect(r.faces, contains(r.target));
          expect(r.target.ask, isNotNull);
          expect(r.target.id, isNot(last), reason: 'seed $seed');
          last = r.target.id;
        }
        expect(whoRound(3, rng, faces: family.take(3).toList()).faces, hasLength(3), reason: 'a small family shows everyone');
      }
      // Only one face can be asked for: it is asked again rather than never.
      final one = whoRound(1, Random(1), faces: const [WhoFace('kid', 'who_you'), WhoFace('x', null)], last: 'kid');
      expect(one.target.id, 'kid');
    });

    test('slips: two faces allow none; four or six allow one, then helped', () {
      final two = whoRound(1, Random(0), faces: const [WhoFace('a', 'who_mom'), WhoFace('b', 'who_dad')]);
      expect([for (final s in [0, 1, 2]) whoResult(two, s)], [GameResult.win, GameResult.helped, GameResult.miss]);
      final four = whoRound(2, Random(0), faces: [for (var i = 0; i < 4; i++) WhoFace('p$i', 'who_mom')]);
      expect([for (final s in [0, 1, 2, 3, 4]) whoResult(four, s)], [GameResult.win, GameResult.win, GameResult.helped, GameResult.helped, GameResult.miss]);
    });
  });
}
