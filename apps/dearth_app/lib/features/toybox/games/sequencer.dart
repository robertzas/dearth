import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';

/// Music Sequencer (SPEC FR-TOY-03, Appendix B: patterns, music). A row per
/// animal, a column per step. A playhead loops across, every lit square on
/// it makes its animal's short call, and the animal hops. She taps squares
/// on (it calls at once) and off, and hears the beat change on the next
/// pass; tapping an animal plays its call; the dice deals a new pattern. It
/// starts with a plain beat already playing. Free play: four steps and two
/// animals → eight steps → three animals → four.
class SequencerGame extends StatefulWidget {
  const SequencerGame(this.c, {super.key});
  final GameController c;

  @override
  State<SequencerGame> createState() => SequencerGameState();
}

const Map<SeqTrack, Color> _kTrackColors = {
  SeqTrack.dog: Color(0xFFF4A259),
  SeqTrack.cat: Color(0xFFA78BFA),
  SeqTrack.frog: Color(0xFF6CC070),
  SeqTrack.chicken: Color(0xFFF2C14E),
};

@visibleForTesting
class SequencerGameState extends State<SequencerGame> {
  late final SeqSize _size = sequencerSize(widget.c.level);
  late List<List<bool>> _grid = sequencerPattern(_size);
  int _step = -1;
  final _hops = <SeqTrack, int>{};
  final _timers = <Timer>[];
  Timer? _beat;

  @visibleForTesting
  SeqSize get debugSize => _size;

  @visibleForTesting
  List<List<bool>> get debugGrid => _grid;

  /// The step the playhead is on (-1 before it starts).
  @visibleForTesting
  int get debugStep => _step;

  @override
  void initState() {
    super.initState();
    _timers.add(Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      widget.c.say(VoiceLine.seqStart);
      // The beat starts under the voice's last words.
      _timers.add(Timer(afterVoice(VoiceLine.seqStart) - const Duration(milliseconds: 600), _start));
    }));
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _beat?.cancel();
    super.dispose();
  }

  void _start() {
    if (!mounted) return;
    _beat = Timer.periodic(const Duration(milliseconds: kSeqStepMs), (_) => _advance());
    _advance();
  }

  void _advance() {
    if (!mounted) return;
    final step = (_step + 1) % _size.steps;
    final calls = <SeqTrack>[];
    for (final (r, track) in _size.tracks.indexed) {
      if (_grid[r][step]) calls.add(track);
    }
    for (final track in calls) {
      _call(track, volume: 0.75);
    }
    setState(() {
      _step = step;
      for (final t in calls) {
        _hops[t] = (_hops[t] ?? 0) + 1;
      }
    });
  }

  void _call(SeqTrack track, {double volume = 0.8}) => widget.c.sound(Sfx.values.byName(track.sound), volume: volume);

  void _toggle(int r, int i) {
    final on = !_grid[r][i];
    if (on) {
      _call(_size.tracks[r]);
    } else {
      widget.c.sound(Sfx.tap, volume: 0.4);
    }
    setState(() {
      _grid = [for (final (k, row) in _grid.indexed) k == r ? [for (final (j, v) in row.indexed) j == i ? on : v] : row];
    });
  }

  void _tapTrack(SeqTrack track) {
    _call(track);
    setState(() => _hops[track] = (_hops[track] ?? 0) + 1);
  }

  void _dice() {
    widget.c.sound(Sfx.sparkle, volume: 0.4);
    setState(() => _grid = sequencerPattern(_size, random: widget.c.random));
  }

  String _name(SeqTrack t) => t.name[0].toUpperCase() + t.name.substring(1);

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Backdrop(
      top: const Color(0xFFFFF1E6),
      bottom: const Color(0xFFEDE7FF),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final n = _size.steps, rows = _size.tracks.length;
              final gap = math.max(6.0, box.maxWidth * 0.008);
              // The animals' column and a step per column; the dice under them.
              final cell = math.min(math.min((box.maxWidth - gap * n) / (n + 1), (box.maxHeight - gap * rows) / (rows + 0.9)), 240.0 * t.scale);
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The playhead's place is a leaf behind the squares: a container's
                    // label isn't text a test (or a screen reader) can read past its children.
                    Stack(
                      children: [
                        Positioned.fill(
                          child: tid('seq.board', Semantics(label: _step < 0 ? 'Ready' : 'Step ${_step + 1} of $n', excludeSemantics: true, child: const SizedBox.expand())),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final (r, track) in _size.tracks.indexed)
                              Padding(
                                padding: EdgeInsets.only(bottom: gap),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    DPressable(
                                      id: 'seq.track.${track.name}',
                                      semanticLabel: _name(track),
                                      excludeSemantics: true,
                                      onTap: () => _tapTrack(track),
                                      borderRadius: BorderRadius.circular(cell / 2),
                                      child: SizedBox.square(dimension: cell, child: Center(child: Hop(count: _hops[track] ?? 0, child: DEmoji(track.emoji, size: cell * 0.72)))),
                                    ),
                                    for (var i = 0; i < n; i++) ...[
                                      SizedBox(width: gap),
                                      _Square(
                                        id: 'seq.cell.${track.name}.$i',
                                        label: '${_name(track)} ${i + 1}: ${_grid[r][i] ? 'on' : 'off'}',
                                        on: _grid[r][i],
                                        here: i == _step,
                                        color: _kTrackColors[track]!,
                                        emoji: track.emoji,
                                        size: cell,
                                        // A beat in four: every fourth square a shade darker, as music is counted.
                                        downbeat: i % 4 == 0,
                                        onTap: () => _toggle(r, i),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    DPressable(
                      id: 'seq.dice',
                      semanticLabel: 'New pattern',
                      excludeSemantics: true,
                      onTap: _dice,
                      borderRadius: t.radius.pill,
                      child: Container(
                        height: cell * 0.8,
                        padding: EdgeInsets.symmetric(horizontal: cell * 0.3),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: t.radius.pill, boxShadow: t.elevation.e1),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [DEmoji('🎲', size: cell * 0.5), SizedBox(width: cell * 0.12), DEmoji('🎶', size: cell * 0.42)]),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// One step of one animal: lit in the animal's color with its face, plain
/// when off; the playhead's column glows.
class _Square extends StatelessWidget {
  const _Square({
    required this.id,
    required this.label,
    required this.on,
    required this.here,
    required this.color,
    required this.emoji,
    required this.size,
    required this.downbeat,
    required this.onTap,
  });
  final String id, label, emoji;
  final bool on, here, downbeat;
  final Color color;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.18);
    return DPressable(
      id: id,
      semanticLabel: label,
      excludeSemantics: true,
      onTap: onTap,
      borderRadius: radius,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? (here ? Color.lerp(color, Colors.white, 0.25) : color) : (here ? const Color(0xFFFFF6D6) : (downbeat ? const Color(0xFFF3F0F8) : Colors.white)),
          borderRadius: radius,
          border: Border.all(color: here ? const Color(0xFFFFC93C) : (on ? Color.lerp(color, const Color(0xFF2B2440), 0.3)! : const Color(0xFFD9D2E9)), width: here ? size * 0.07 : size * 0.035),
        ),
        child: on ? DEmoji(emoji, size: size * (here ? 0.62 : 0.5)) : null,
      ),
    );
  }
}
