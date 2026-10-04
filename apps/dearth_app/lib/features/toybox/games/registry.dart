import '../game_host.dart';
import 'bubbles.dart';
import 'farm.dart';
import 'music.dart';

/// Every launch-set game's playfield, by game id (SPEC FR-TOY-02).
final Map<String, GameBuilder> kGameBuilders = {
  'bubbles': BubbleGame.new,
  'music': MusicGame.new,
  'farm': FarmGame.new,
};
