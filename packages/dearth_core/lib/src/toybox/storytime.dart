import 'package:meta/meta.dart';

import 'words.dart';

// Story Time (SPEC FR-TOY-03, Appendix B: language, listening, print
// awareness). A shelf of picture books; she picks one by its cover and the
// voice reads it a page at a time (Piper narration, owner's decision
// 2026-10-07: no recordings). Every page is a painted scene of things she
// can tap to hear their names, with the sentence printed big underneath.
// Arrows turn the pages; the last one ends "The end!". Nothing to win:
// visits unlock longer books (four pages → six → eight). Drawing lives in
// the app.

/// The backdrop a page is painted on.
enum StoryScene { day, sunset, night, rain, beach, sea, space, snow, party }

/// A thing in a scene: a picture word (it says its name when tapped), its
/// centre as fractions of the scene's width and height, and its size as a
/// fraction of the scene's height.
@immutable
class StoryThing {
  const StoryThing(this.word, this.x, this.y, this.size);
  final String word;
  final double x, y, size;

  PictureWord get picture => kWords.firstWhere((w) => w.word == word);
}

@immutable
class StoryPage {
  const StoryPage(this.text, this.scene, this.things);

  /// What the voice reads, printed under the picture.
  final String text;
  final StoryScene scene;
  final List<StoryThing> things;
}

@immutable
class StoryBook {
  const StoryBook(this.id, this.title, this.cover, this.level, this.pages);
  final String id, title;

  /// The picture word on its cover.
  final String cover;

  /// The shelf it joins: 1 (four pages), 2 (six), 3 (eight).
  final int level;
  final List<StoryPage> pages;

  PictureWord get coverPicture => kWords.firstWhere((w) => w.word == cover);

  /// The clip that says the title.
  String get titleClip => 'story_${id}_title';

  /// The clip that reads page [i] (from 0).
  String pageClip(int i) => 'story_${id}_${i + 1}';
}

const _day = StoryScene.day, _sunset = StoryScene.sunset, _night = StoryScene.night, _rain = StoryScene.rain, _beach = StoryScene.beach;
const _sea = StoryScene.sea, _space = StoryScene.space, _snow = StoryScene.snow, _party = StoryScene.party;

/// The bookshelf. Things stand on the ground at y ≈ 0.7–0.8 (the ground
/// starts at about 0.62) and float in the sky above 0.4.
const List<StoryBook> kStoryBooks = [
  // ── Level 1: board books, four pages, one thing happening ──
  StoryBook('rabbit', 'Goodnight, Little Rabbit', 'rabbit', 1, [
    StoryPage('The sun goes down, down, down.', _sunset, [StoryThing('sun', 0.5, 0.56, 0.3), StoryThing('house', 0.18, 0.68, 0.3), StoryThing('tree', 0.82, 0.6, 0.42)]),
    StoryPage('Little Rabbit drinks her milk.', _night, [StoryThing('rabbit', 0.4, 0.68, 0.4), StoryThing('milk', 0.64, 0.74, 0.2), StoryThing('moon', 0.84, 0.2, 0.18)]),
    StoryPage('She says goodnight to the moon and the stars.', _night, [StoryThing('rabbit', 0.3, 0.7, 0.34), StoryThing('moon', 0.7, 0.24, 0.26), StoryThing('star', 0.46, 0.14, 0.1), StoryThing('star', 0.9, 0.4, 0.09)]),
    StoryPage('Then she hops into bed. Goodnight, Little Rabbit!', _night, [StoryThing('bed', 0.5, 0.72, 0.42), StoryThing('rabbit', 0.46, 0.56, 0.22), StoryThing('moon', 0.85, 0.18, 0.18)]),
  ]),
  StoryBook('duck', "Duck's Walk", 'duck', 1, [
    StoryPage('Duck goes for a walk.', _day, [StoryThing('duck', 0.3, 0.72, 0.3), StoryThing('tree', 0.76, 0.58, 0.46), StoryThing('flower', 0.55, 0.82, 0.12), StoryThing('flower', 0.92, 0.84, 0.1)]),
    StoryPage('She sees a frog. Ribbit, ribbit!', _day, [StoryThing('duck', 0.26, 0.72, 0.28), StoryThing('frog', 0.66, 0.76, 0.24)]),
    StoryPage('She sees a snail. Slow, slow snail.', _day, [StoryThing('duck', 0.26, 0.72, 0.28), StoryThing('snail', 0.64, 0.8, 0.18), StoryThing('leaf', 0.8, 0.8, 0.12)]),
    StoryPage('And she finds her chicks! Quack, quack!', _day, [StoryThing('duck', 0.28, 0.7, 0.32), StoryThing('chick', 0.55, 0.8, 0.15), StoryThing('chick', 0.69, 0.8, 0.15), StoryThing('chick', 0.83, 0.8, 0.15)]),
  ]),
  StoryBook('bear', 'Hungry Bear', 'bear', 1, [
    StoryPage('Bear wakes up. His tummy rumbles.', _day, [StoryThing('bear', 0.48, 0.68, 0.44), StoryThing('sun', 0.84, 0.2, 0.2)]),
    StoryPage('Bear eats an apple. Crunch, crunch!', _day, [StoryThing('bear', 0.36, 0.68, 0.42), StoryThing('apple', 0.72, 0.74, 0.2)]),
    StoryPage('Bear eats a yellow banana. Yum, yum!', _day, [StoryThing('bear', 0.36, 0.68, 0.42), StoryThing('banana', 0.72, 0.74, 0.2)]),
    StoryPage('Now Bear is full. Time for a nap under the tree.', _day, [StoryThing('tree', 0.72, 0.56, 0.54), StoryThing('bear', 0.36, 0.72, 0.36)]),
  ]),
  // ── Level 2: six pages, a little plot ──
  StoryBook('balloon', "Monkey's Balloon", 'balloon', 2, [
    StoryPage('Monkey has a red balloon.', _day, [StoryThing('monkey', 0.4, 0.7, 0.4), StoryThing('balloon', 0.64, 0.34, 0.26)]),
    StoryPage('Whoosh! The wind blows it away.', _day, [StoryThing('monkey', 0.24, 0.72, 0.3), StoryThing('cloud', 0.36, 0.2, 0.24), StoryThing('balloon', 0.7, 0.26, 0.22), StoryThing('tree', 0.84, 0.62, 0.4)]),
    StoryPage('Up, up it goes, past a plane.', _day, [StoryThing('balloon', 0.34, 0.36, 0.2), StoryThing('plane', 0.72, 0.2, 0.22), StoryThing('cloud', 0.16, 0.14, 0.2)]),
    StoryPage('It floats over a rainbow.', _day, [StoryThing('rainbow', 0.5, 0.46, 0.5), StoryThing('balloon', 0.52, 0.14, 0.18)]),
    StoryPage('Elephant reaches up with her long trunk. Got it!', _day, [StoryThing('elephant', 0.48, 0.68, 0.46), StoryThing('balloon', 0.66, 0.24, 0.18)]),
    StoryPage('Here you go, Monkey! Monkey gives Elephant a big hug.', _day, [StoryThing('monkey', 0.32, 0.72, 0.3), StoryThing('elephant', 0.64, 0.68, 0.42), StoryThing('balloon', 0.46, 0.28, 0.18), StoryThing('heart', 0.48, 0.52, 0.1)]),
  ]),
  StoryBook('rain', 'Rainy Day', 'umbrella', 2, [
    StoryPage("Drip, drop. It's raining.", _rain, [StoryThing('rain', 0.28, 0.2, 0.24), StoryThing('rain', 0.72, 0.18, 0.24), StoryThing('house', 0.5, 0.68, 0.34)]),
    StoryPage('Frog loves the rain. Splash!', _rain, [StoryThing('rain', 0.5, 0.18, 0.24), StoryThing('frog', 0.5, 0.74, 0.3)]),
    StoryPage('Duck loves the rain too. Quack!', _rain, [StoryThing('umbrella', 0.5, 0.42, 0.26), StoryThing('duck', 0.5, 0.74, 0.28)]),
    StoryPage('But Cat stays inside, warm and dry.', _rain, [StoryThing('house', 0.42, 0.62, 0.5), StoryThing('cat', 0.76, 0.78, 0.2), StoryThing('rain', 0.82, 0.18, 0.2)]),
    StoryPage('Then the sun comes out.', _day, [StoryThing('sun', 0.52, 0.3, 0.3), StoryThing('cloud', 0.24, 0.22, 0.2), StoryThing('house', 0.8, 0.68, 0.26)]),
    StoryPage('Look, a rainbow! Now they can all go out and play.', _day, [StoryThing('rainbow', 0.5, 0.34, 0.48), StoryThing('frog', 0.24, 0.8, 0.18), StoryThing('duck', 0.5, 0.8, 0.18), StoryThing('cat', 0.76, 0.8, 0.18)]),
  ]),
  StoryBook('panda', "Panda's Birthday", 'cake', 2, [
    StoryPage("Today is Panda's birthday!", _party, [StoryThing('panda', 0.5, 0.68, 0.42), StoryThing('balloon', 0.18, 0.3, 0.2), StoryThing('balloon', 0.82, 0.28, 0.2)]),
    StoryPage('Tiger brings a gift.', _party, [StoryThing('tiger', 0.36, 0.7, 0.38), StoryThing('gift', 0.7, 0.76, 0.2)]),
    StoryPage('Koala brings balloons.', _party, [StoryThing('koala', 0.38, 0.7, 0.36), StoryThing('balloon', 0.64, 0.3, 0.18), StoryThing('balloon', 0.78, 0.38, 0.18)]),
    StoryPage('Monkey brings a cake.', _party, [StoryThing('monkey', 0.36, 0.7, 0.36), StoryThing('cake', 0.7, 0.76, 0.22)]),
    StoryPage("Panda opens the gift. It's a kite!", _party, [StoryThing('panda', 0.34, 0.7, 0.38), StoryThing('kite', 0.7, 0.3, 0.26), StoryThing('gift', 0.66, 0.8, 0.14)]),
    StoryPage('Happy birthday, Panda!', _party, [
      StoryThing('panda', 0.5, 0.62, 0.32), StoryThing('tiger', 0.2, 0.74, 0.22), StoryThing('koala', 0.8, 0.74, 0.22), //
      StoryThing('cake', 0.5, 0.86, 0.14), StoryThing('balloon', 0.14, 0.24, 0.16), StoryThing('balloon', 0.86, 0.24, 0.16),
    ]),
  ]),
  // ── Level 3: eight pages, a journey ──
  StoryBook('rocket', "Robot's Rocket", 'rocket', 3, [
    StoryPage('Robot builds a little rocket.', _day, [StoryThing('robot', 0.34, 0.7, 0.38), StoryThing('rocket', 0.7, 0.58, 0.46)]),
    StoryPage('Three, two, one, blast off!', _day, [StoryThing('rocket', 0.5, 0.42, 0.4), StoryThing('fire', 0.5, 0.78, 0.2)]),
    StoryPage('The rocket zooms up through the clouds.', _day, [StoryThing('rocket', 0.56, 0.36, 0.3), StoryThing('cloud', 0.24, 0.56, 0.24), StoryThing('cloud', 0.82, 0.7, 0.24)]),
    StoryPage('It flies past the moon.', _space, [StoryThing('rocket', 0.34, 0.52, 0.28), StoryThing('moon', 0.7, 0.34, 0.34), StoryThing('star', 0.14, 0.2, 0.08), StoryThing('star', 0.9, 0.78, 0.08)]),
    StoryPage('It lands on a big, shiny star. Hello, star!', _space, [StoryThing('star', 0.5, 0.7, 0.44), StoryThing('rocket', 0.5, 0.34, 0.26)]),
    StoryPage('Robot looks out. Home is far, far away.', _space, [StoryThing('robot', 0.3, 0.6, 0.34), StoryThing('house', 0.8, 0.26, 0.08), StoryThing('star', 0.6, 0.14, 0.06)]),
    StoryPage('Robot misses home. Time to fly back!', _space, [StoryThing('rocket', 0.5, 0.48, 0.32), StoryThing('heart', 0.76, 0.24, 0.12), StoryThing('star', 0.2, 0.2, 0.1)]),
    StoryPage('Home again! Robot tells Dog and Cat all about it.', _day, [StoryThing('house', 0.84, 0.56, 0.26), StoryThing('robot', 0.24, 0.7, 0.34), StoryThing('dog', 0.52, 0.76, 0.22), StoryThing('cat', 0.72, 0.78, 0.2)]),
  ]),
  StoryBook('turtle', 'Little Turtle and the Sea', 'turtle', 3, [
    StoryPage('Little Turtle lives on the beach.', _beach, [StoryThing('turtle', 0.4, 0.76, 0.28), StoryThing('shell', 0.72, 0.82, 0.12)]),
    StoryPage('One day, she walks down to the sea.', _beach, [StoryThing('turtle', 0.62, 0.78, 0.24), StoryThing('sun', 0.18, 0.18, 0.18)]),
    StoryPage('Splash! The water is cool and blue.', _sea, [StoryThing('turtle', 0.5, 0.48, 0.34)]),
    StoryPage('She swims with a little fish.', _sea, [StoryThing('turtle', 0.34, 0.5, 0.32), StoryThing('fish', 0.72, 0.38, 0.16)]),
    StoryPage('She waves hello to an octopus.', _sea, [StoryThing('turtle', 0.3, 0.42, 0.3), StoryThing('octopus', 0.7, 0.7, 0.3)]),
    StoryPage('A great big whale swims by. Whoosh!', _sea, [StoryThing('whale', 0.6, 0.4, 0.5), StoryThing('turtle', 0.18, 0.76, 0.16)]),
    StoryPage('Two dolphins jump and play.', _sea, [StoryThing('dolphin', 0.34, 0.34, 0.3), StoryThing('dolphin', 0.7, 0.52, 0.3), StoryThing('turtle', 0.5, 0.82, 0.14)]),
    StoryPage('When the moon comes up, Turtle swims home to sleep.', _night, [StoryThing('moon', 0.8, 0.2, 0.2), StoryThing('turtle', 0.4, 0.76, 0.26), StoryThing('shell', 0.66, 0.82, 0.1)]),
  ]),
  StoryBook('snowman', "The Snowman's Hat", 'snowman', 3, [
    StoryPage('Snow fell all night long.', _snow, [StoryThing('cloud', 0.3, 0.2, 0.24), StoryThing('cloud', 0.7, 0.14, 0.2), StoryThing('house', 0.24, 0.64, 0.3), StoryThing('tree', 0.8, 0.6, 0.4)]),
    StoryPage('Penguin and Bear build a snowman.', _snow, [StoryThing('penguin', 0.2, 0.74, 0.24), StoryThing('snowman', 0.5, 0.64, 0.4), StoryThing('bear', 0.8, 0.72, 0.3)]),
    StoryPage('Penguin gives him a carrot nose.', _snow, [StoryThing('penguin', 0.24, 0.74, 0.26), StoryThing('snowman', 0.6, 0.64, 0.42), StoryThing('carrot', 0.42, 0.42, 0.12)]),
    StoryPage('Bear gives him a warm hat.', _snow, [StoryThing('bear', 0.24, 0.72, 0.3), StoryThing('snowman', 0.62, 0.66, 0.42), StoryThing('hat', 0.62, 0.34, 0.15)]),
    StoryPage('Whoosh! The wind blows the hat away.', _snow, [StoryThing('snowman', 0.34, 0.66, 0.42), StoryThing('cloud', 0.5, 0.18, 0.2), StoryThing('hat', 0.78, 0.26, 0.15)]),
    StoryPage('Fox finds the hat in a tree.', _snow, [StoryThing('tree', 0.62, 0.54, 0.56), StoryThing('hat', 0.64, 0.38, 0.12), StoryThing('fox', 0.28, 0.75, 0.26)]),
    StoryPage('Fox brings it back. Thank you, Fox!', _snow, [StoryThing('fox', 0.28, 0.74, 0.26), StoryThing('snowman', 0.64, 0.64, 0.42), StoryThing('hat', 0.64, 0.32, 0.14)]),
    StoryPage('Now the snowman is ready for the party!', _snow, [
      StoryThing('snowman', 0.5, 0.62, 0.4), StoryThing('penguin', 0.18, 0.76, 0.22), StoryThing('bear', 0.82, 0.74, 0.24), //
      StoryThing('star', 0.16, 0.2, 0.1), StoryThing('star', 0.84, 0.18, 0.1),
    ]),
  ]),
];

/// The books on the shelf at [level]: that level's first (the newest she
/// has unlocked), then the level below; at most six, in a fixed order so a
/// favorite stays where she left it.
List<StoryBook> storyShelf(int level) {
  final top = level.clamp(1, 3);
  return [for (final l in [top, top - 1]) ...kStoryBooks.where((s) => s.level == l)].take(6).toList();
}

StoryBook? storyBookById(String id) => kStoryBooks.where((s) => s.id == id).firstOrNull;
