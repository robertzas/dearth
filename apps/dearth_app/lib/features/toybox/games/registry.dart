import '../game_host.dart';
import 'bubbles.dart';
import 'coloring.dart';
import 'counting.dart';
import 'farm.dart';
import 'jigsaw.dart';
import 'memory.dart';
import 'monster.dart';
import 'music.dart';
import 'paint.dart';
import 'shapes.dart';

/// Every launch-set game's playfield, by game id (SPEC FR-TOY-02).
final Map<String, GameBuilder> kGameBuilders = {
  'bubbles': BubbleGame.new,
  'music': MusicGame.new,
  'farm': FarmGame.new,
  'memory': MemoryGame.new,
  'shapes': ShapeGame.new,
  'counting': CountingGame.new,
  'monster': MonsterGame.new,
  'coloring': ColoringGame.new,
  'jigsaw': JigsawGame.new,
  'paint': PaintGame.new,
};
