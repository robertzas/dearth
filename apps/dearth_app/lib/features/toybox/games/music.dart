import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';

/// The eight bars' colors: a rainbow, low to high.
const List<Color> kBarColors = [
  Color(0xFFE94B4B), Color(0xFFF28C38), Color(0xFFF5C334), Color(0xFF6CC04A), //
  Color(0xFF2EB8A6), Color(0xFF3D8FE0), Color(0xFF6A5ACD), Color(0xFFB25FD6),
];

const List<String> _noteNames = ['C', 'D', 'E', 'G', 'A', 'high C', 'high D', 'high E'];

/// Xylophone & Drums (SPEC FR-TOY-02, Appendix B: music and rhythm). Eight
/// pentatonic bars (anything sounds good) and four drums, sounding on the
/// finger going down, not up: instruments can't wait. The parrot starts
/// "echo me": the toy plays a little tune, then it's her turn.
class MusicGame extends StatefulWidget {
  const MusicGame(this.c, {super.key});
  final GameController c;

  @override
  State<MusicGame> createState() => MusicGameState();
}

enum _Echo { off, listening, yourTurn }

@visibleForTesting
class MusicGameState extends State<MusicGame> {
  final _lit = List<int>.filled(kXylophoneMidi.length, 0);
  _Echo _echo = _Echo.off;
  List<int> _tune = const [];
  int _played = 0, _slips = 0;
  Timer? _player;

  /// The tune to echo, for tests.
  @visibleForTesting
  List<int> get debugTune => _tune;

  @override
  void dispose() {
    _player?.cancel();
    super.dispose();
  }

  void _ring(int bar) {
    widget.c.sound(Sfx.xylophone, rate: math.pow(2, (kXylophoneMidi[bar] - kXylophoneBaseMidi) / 12).toDouble());
    setState(() => _lit[bar]++);
  }

  void _hit(int bar) {
    if (_echo == _Echo.listening) return;
    _ring(bar);
    if (_echo != _Echo.yourTurn) return;
    if (bar == _tune[_played]) {
      if (++_played == _tune.length) {
        final level = math.max(2, widget.c.level);
        setState(() => _echo = _Echo.off);
        unawaited(widget.c.finishRound(resultFor(_slips, allowed: 1), emoji: '🦜', level: level));
      }
    } else {
      // Not that one: a gentle "uh-uh", then the tune again.
      _slips++;
      widget.c.cue();
      _play(after: const Duration(milliseconds: 900));
    }
  }

  void _startEcho() {
    final level = math.max(2, widget.c.level);
    _tune = echoPattern(level, widget.c.random);
    _slips = 0;
    _play();
  }

  /// Plays the tune, lighting each bar, then hands over.
  void _play({Duration after = const Duration(milliseconds: 400)}) {
    _player?.cancel();
    _played = 0;
    setState(() => _echo = _Echo.listening);
    var i = -1;
    _player = Timer(after, () {
      void next() {
        i++;
        if (!mounted) return;
        if (i < _tune.length) {
          _ring(_tune[i]);
          _player = Timer(const Duration(milliseconds: 520), next);
        } else {
          setState(() => _echo = _Echo.yourTurn);
        }
      }

      next();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF4DE), Color(0xFFFFE2B8)])),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(t.space.lg, 96 * t.scale, t.space.lg, t.space.lg),
          child: LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth > box.maxHeight * 0.9;
            final bars = _Xylophone(lit: _lit, onHit: _hit, sideways: !wide);
            final drums = _Drums(onHit: (sfx) => widget.c.sound(sfx));
            return Column(
              children: [
                // Always tappable (a tap while the parrot plays does nothing):
                // a button that loses its handler changes semantics role, and
                // Flutter web rebuilds the node without its test id.
                _EchoButton(state: _echo, onTap: switch (_echo) { _Echo.off => _startEcho, _Echo.yourTurn => _play, _Echo.listening => () {} }),
                SizedBox(height: t.space.md),
                Expanded(flex: 6, child: bars),
                SizedBox(height: t.space.lg),
                Expanded(flex: 3, child: drums),
              ],
            );
          }),
        ),
      ),
    );
  }
}

/// The parrot: "echo me" (the toy plays, she plays it back).
class _EchoButton extends StatelessWidget {
  const _EchoButton({required this.state, required this.onTap});
  final _Echo state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final (emoji, label) = switch (state) {
      _Echo.off => ('🦜', 'Echo me'),
      _Echo.listening => ('👂', 'Listen…'),
      _Echo.yourTurn => ('👉', 'Your turn! (tap to hear it again)'),
    };
    return DPressable(
      id: 'music.echo',
      semanticLabel: label,
      excludeSemantics: true,
      onTap: onTap,
      borderRadius: t.radius.pill,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: t.space.lg, vertical: t.space.sm),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), borderRadius: t.radius.pill, boxShadow: t.elevation.e1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DEmoji(emoji, size: 40 * t.scale),
            if (state != _Echo.off) ...[
              SizedBox(width: t.space.sm),
              for (var i = 0; i < 3; i++) DEmoji(state == _Echo.listening ? '🎵' : '✨', size: 24 * t.scale),
            ],
          ],
        ),
      ),
    );
  }
}

/// A finger down on any of [child] plays at once (and keeps playing with
/// several fingers); semantics taps play too.
class _Instant extends StatelessWidget {
  const _Instant({required this.id, required this.label, required this.onHit, required this.child});
  final String id;
  final String label;
  final VoidCallback onHit;
  final Widget child;

  @override
  Widget build(BuildContext context) => tid(
        id,
        Semantics(
          button: true,
          label: label,
          onTap: onHit,
          excludeSemantics: true,
          child: Listener(behavior: HitTestBehavior.opaque, onPointerDown: (_) => onHit(), child: child),
        ),
      );
}

class _Xylophone extends StatelessWidget {
  const _Xylophone({required this.lit, required this.onHit, required this.sideways});
  final List<int> lit;
  final ValueChanged<int> onHit;

  /// Bars stacked top to bottom on a narrow screen.
  final bool sideways;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final n = kXylophoneMidi.length;
    return LayoutBuilder(builder: (context, box) {
      final gap = (sideways ? box.maxHeight : box.maxWidth) * 0.018;
      final thick = ((sideways ? box.maxHeight : box.maxWidth) - gap * (n - 1)) / n;
      final long = sideways ? box.maxWidth : box.maxHeight;
      final children = [
        for (var i = 0; i < n; i++)
          _Instant(
            id: 'music.bar.$i',
            label: _noteNames[i],
            onHit: () => onHit(i),
            child: _Bar(color: kBarColors[i], length: long * (1 - i * 0.055), thick: thick, sideways: sideways, hits: lit[i], radius: t.radius.s),
          ),
      ];
      return sideways
          ? Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: children)
          : Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: children);
    });
  }
}

/// One bar: dips and glows when it rings ([hits] counts rings).
class _Bar extends StatelessWidget {
  const _Bar({required this.color, required this.length, required this.thick, required this.sideways, required this.hits, required this.radius});
  final Color color;
  final double length, thick, radius;
  final bool sideways;
  final int hits;

  @override
  Widget build(BuildContext context) {
    final w = sideways ? length : thick, h = sideways ? thick : length;
    return TweenAnimationBuilder<double>(
      key: ValueKey(hits),
      tween: Tween(begin: hits == 0 ? 0 : 1, end: 0),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      builder: (context, glow, child) => Transform.translate(
        offset: sideways ? Offset(glow * 6, 0) : Offset(0, glow * 6),
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: Color.lerp(color, Colors.white, glow * 0.45),
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 4 + glow * 14, offset: const Offset(0, 3))],
          ),
          child: child,
        ),
      ),
      // The two pins that hold a bar to the frame.
      child: Flex(
        direction: sideways ? Axis.horizontal : Axis.vertical,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < 2; i++)
            Padding(
              padding: EdgeInsets.all(math.min(w, h) * 0.28),
              child: Container(width: math.min(w, h) * 0.16, height: math.min(w, h) * 0.16, decoration: const BoxDecoration(color: Color(0xCCFFFFFF), shape: BoxShape.circle)),
            ),
        ],
      ),
    );
  }
}

class _Drums extends StatelessWidget {
  const _Drums({required this.onHit});
  final ValueChanged<Sfx> onHit;

  static const _kit = [
    (Sfx.kick, 'Big drum', '🥁', Color(0xFFD9534F)),
    (Sfx.snare, 'Snare', '👏', Color(0xFF5B5BD6)),
    (Sfx.tom, 'Tom', '🛢️', Color(0xFF2EB8A6)),
    (Sfx.hat, 'Cymbal', '🔔', Color(0xFFE5B53D)),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final d = math.min(box.maxHeight, box.maxWidth / _kit.length * 0.86);
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final (sfx, name, emoji, color) in _kit)
            _Instant(
              id: 'music.drum.${sfx.name}',
              label: name,
              onHit: () => onHit(sfx),
              child: _Pad(diameter: sfx == Sfx.kick ? d : d * 0.86, emoji: emoji, color: color),
            ),
        ],
      );
    });
  }
}

/// A drum skin: a ring that flashes on a hit.
class _Pad extends StatefulWidget {
  const _Pad({required this.diameter, required this.emoji, required this.color});
  final double diameter;
  final String emoji;
  final Color color;

  @override
  State<_Pad> createState() => _PadState();
}

class _PadState extends State<_Pad> with SingleTickerProviderStateMixin {
  late final AnimationController _hit = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));

  @override
  void dispose() {
    _hit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _hit.forward(from: 0),
      child: AnimatedBuilder(
        animation: _hit,
        builder: (context, child) {
          final k = 1 - Curves.easeOut.transform(_hit.value);
          return Transform.scale(
            scale: 1 - 0.06 * (_hit.isAnimating ? k : 0),
            child: Container(
              width: widget.diameter,
              height: widget.diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Colors.white, Color.lerp(Colors.white, widget.color, 0.25)!]),
                border: Border.all(color: widget.color, width: widget.diameter * (0.07 + 0.05 * (_hit.isAnimating ? k : 0))),
              ),
              alignment: Alignment.center,
              child: child,
            ),
          );
        },
        child: DEmoji(widget.emoji, size: widget.diameter * 0.42),
      ),
    );
  }
}
