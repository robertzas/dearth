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
}
