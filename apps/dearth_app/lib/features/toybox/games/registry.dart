import '../game_host.dart';
import 'bubbles.dart';
import 'coloring.dart';
import 'counting.dart';
import 'differences.dart';
import 'farm.dart';
import 'jigsaw.dart';
import 'mazes.dart';
import 'memory.dart';
import 'monster.dart';
import 'music.dart';
import 'oddone.dart';
import 'paint.dart';
import 'patterns.dart';
import 'shadows.dart';
import 'shapes.dart';
import 'sizes.dart';
import 'stories.dart';
import 'sudoku.dart';

/// Every game's playfield, by game id (SPEC FR-TOY-02/03). The launcher
/// shows only games that have one.
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
  'patterns': PatternsGame.new,
  'oddone': OddOneGame.new,
  'shadows': ShadowsGame.new,
  'sizes': SizesGame.new,
  'mazes': MazesGame.new,
  'stories': StoriesGame.new,
  'sudoku': SudokuGame.new,
  'differences': DifferencesGame.new,
};
