import 'dart:math';

import 'package:meta/meta.dart';

import 'words.dart';

// Build-a-Creature (SPEC FR-TOY-03, Appendix B: creativity and language).
// She mixes body parts and colors, and hears each one named as she picks it
// ("Bunny ears!", "Purple!"); the creature dances and says its silly name,
// which comes from its body and its face ("I'm a Wobblesaurus!"). Drawing
// lives in the app.

/// What a creature is made of, in the order the parts unlock.
enum CreaturePart { body, face, top, legs, arms, tail }

/// How many kinds of each part there are. Option 0 of the optional parts
/// (top, legs, arms, tail) is "none".
const Map<CreaturePart, int> kCreatureOptions = {
  CreaturePart.body: 6,
  CreaturePart.face: 6,
  CreaturePart.top: 6,
  CreaturePart.legs: 6,
  CreaturePart.arms: 5,
  CreaturePart.tail: 5,
};

/// What each option is called, by part: the voice says it when she picks
/// it, and the screen reader reads the creature with it.
const Map<CreaturePart, List<String>> kCreaturePartWords = {
  CreaturePart.body: ['a round body', 'an egg body', 'a pear body', 'a square body', 'a spiky body', 'a fluffy body'],
  CreaturePart.face: ['googly eyes', 'one big eye', 'three eyes', 'sleepy eyes', 'happy eyes', 'long eyelashes'],
  CreaturePart.top: ['nothing on top', 'horns', 'bunny ears', 'antennae', 'a tuft of hair', 'a party hat'],
  CreaturePart.legs: ['no legs', 'two legs', 'four legs', 'wiggly tentacles', 'bird legs', 'wheels'],
  CreaturePart.arms: ['no arms', 'little arms', 'wings', 'fins', 'noodle arms'],
  CreaturePart.tail: ['no tail', 'a curly tail', 'a fluffy tail', 'a spiky tail', 'a long tail'],
};

/// The paints' names, in the app's paint order.
const List<String> kCreaturePaints = ['pink', 'blue', 'green', 'purple', 'orange', 'yellow', 'teal', 'red'];

/// The first half of its name, by body.
const List<String> kCreaturePrefixes = ['Wobble', 'Zippy', 'Fluffle', 'Boingo', 'Snuggle', 'Giggle'];

/// The second half, by face.
const List<String> kCreatureSuffixes = ['bug', 'saurus', 'moo', 'pop', 'wump', 'zoo'];

/// The parts she can change at a level (Appendix B: more parts and
/// colors): body and face, then top and legs, then arms and tail.
List<CreaturePart> creatureParts(int level) => switch (level) {
      <= 1 => const [CreaturePart.body, CreaturePart.face],
      2 => const [CreaturePart.body, CreaturePart.face, CreaturePart.top, CreaturePart.legs],
      _ => CreaturePart.values,
    };

/// How many paint colors a level offers: 4 → 8.
int creatureColors(int level) => switch (level) { <= 1 => 4, 2 => 6, _ => 8 };

@immutable
class Creature {
  const Creature(this.parts, this.color);

  /// The option of each part; missing parts are none (0).
  final Map<CreaturePart, int> parts;

  /// An index into the app's paint colors.
  final int color;

  int operator [](CreaturePart p) => parts[p] ?? 0;

  /// The next option of [part], round and round (the "none" of optional
  /// parts included).
  Creature next(CreaturePart part) => Creature({...parts, part: (this[part] + 1) % kCreatureOptions[part]!}, color);

  Creature withColor(int c) => Creature(parts, c);

  String get name => '${kCreaturePrefixes[this[CreaturePart.body]]}${kCreatureSuffixes[this[CreaturePart.face]]}';

  @override
  bool operator ==(Object other) => other is Creature && other.color == color && CreaturePart.values.every((p) => other[p] == this[p]);

  @override
  int get hashCode => Object.hash(color, Object.hashAll([for (final p in CreaturePart.values) this[p]]));
}

/// A surprise creature with every part of [level] (optional ones present).
Creature randomCreature(int level, Random rng) {
  final parts = <CreaturePart, int>{
    for (final p in creatureParts(level)) p: p == CreaturePart.body || p == CreaturePart.face ? rng.nextInt(kCreatureOptions[p]!) : 1 + rng.nextInt(kCreatureOptions[p]! - 1),
  };
  return Creature(parts, rng.nextInt(creatureColors(level)));
}

/// "I'm a Wobblesaurus!"
String creatureClip(Creature c) => creatureNameClip(c.name);

String creatureNameClip(String name) => 'creature_${voiceSlug(name)}';

/// "Bunny ears!"
String creaturePartClip(CreaturePart part, int option) => 'creature_${part.name}_$option';

/// Every name a creature can have.
List<String> get kCreatureNames => [
      for (final p in kCreaturePrefixes)
        for (final s in kCreatureSuffixes) '$p$s',
    ];
