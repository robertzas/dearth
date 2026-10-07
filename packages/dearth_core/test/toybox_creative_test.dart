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
}
