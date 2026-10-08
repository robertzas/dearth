import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../../../shared/face_photo.dart';
import '../game_host.dart';
import '../toybox_data.dart';
import 'game_widgets.dart';
import 'voice_widgets.dart';

/// Who's That? (SPEC FR-TOY-03, Appendix B: family recognition). The
/// family's faces (photos chosen in Settings → People) in big circles; the
/// voice asks "Where's Grandma?" or "Where are you?". The right face hops
/// and the voice cheers ("That's you!"); a wrong one wiggles and fades;
/// two slips light the right one. Two faces → four → six. The Toybox shows
/// the game once two people have faces and one can be asked for.
class WhoGame extends StatefulWidget {
  const WhoGame(this.c, {super.key});
  final GameController c;

  @override
  State<WhoGame> createState() => WhoGameState();
}

@visibleForTesting
class WhoGameState extends State<WhoGame> {
  late final Map<String, Profile> _people = {for (final p in widget.c.people) p.id: p};
  // The Toybox only offers the game with faces; opened without them, the
  // family's avatars stand in rather than leaving an empty board.
  late final List<WhoFace> _faces = whoPlayable(whoFaces(widget.c.people, widget.c.kid.id))
      ? whoFaces(widget.c.people, widget.c.kid.id)
      : whoFaces(widget.c.people, widget.c.kid.id, photosOnly: false);
  WhoRound? _round;
  int _deal = 0, _slips = 0;
  bool _solved = false;
  final _tried = <String>{};
  final _wiggles = <String, int>{};
  final _hops = <String, int>{};
  final _timers = <Timer>[];

  @visibleForTesting
  WhoRound get debugRound => _round!;

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  void _after(Duration d, VoidCallback f) => _timers.add(Timer(d, () {
        if (mounted) f();
      }));

  void _newRound() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    _round = whoRound(widget.c.level, widget.c.random, faces: _faces, last: _round?.target.id);
    _deal++;
    _slips = 0;
    _solved = false;
    _tried.clear();
    _wiggles.clear();
    _hops.clear();
    _after(const Duration(milliseconds: 600), _ask);
    if (mounted) setState(() {});
  }

  void _ask() {
    widget.c.say(_round!.target.ask!);
    // A long pause asks again (not a slip).
    _after(const Duration(seconds: 12), () {
      if (!_solved) _ask();
    });
  }

  void _tap(WhoFace face) {
    final r = _round!;
    if (_solved) return;
    if (face.id != r.target.id) {
      if (!_tried.add(face.id)) return;
      _slips++;
      widget.c.cue();
      setState(() => _wiggles[face.id] = (_wiggles[face.id] ?? 0) + 1);
      return;
    }
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    widget.c.sound(Sfx.sparkle, volume: 0.5);
    final you = face.id == widget.c.kid.id;
    final clip = you ? VoiceLine.whoYesYou : VoiceLine.whoYes;
    widget.c.say(clip);
    setState(() {
      _solved = true;
      _hops[face.id] = (_hops[face.id] ?? 0) + 1;
    });
    unawaited(widget.c.finishRound(whoResult(r, _slips), emoji: '👪'));
    _after(afterVoice(clip, atLeast: const Duration(milliseconds: 3000)), _newRound);
  }

  String _name(String id) {
    final p = _people[id];
    return p == null ? '?' : (p.nickname ?? p.name);
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = _round!;
    final target = _name(r.target.id);
    return Backdrop(
      top: const Color(0xFFFFEFE6),
      bottom: const Color(0xFFFFF8EC),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PlayArea(
            top: 140,
            child: LayoutBuilder(builder: (context, box) {
              final n = r.faces.length;
              final gap = t.space.lg;
              // Rows of faces as large as fit: two a row on a tall screen.
              final per = box.maxWidth > box.maxHeight ? math.min(n, n <= 4 ? n : 3) : math.min(n, 2);
              final rows = (n / per).ceil();
              // Faces as big as the room allows (a fixed cap left two faces tiny on a wall).
              final side = math.min(math.min(box.maxWidth / per, box.maxHeight / rows) - gap, box.biggest.shortestSide * 0.62);
              return Center(
                key: ValueKey(_deal),
                child: TileRows(
                  per: per,
                  children: [
                    for (final f in r.faces)
                      Padding(
                        padding: EdgeInsets.all(gap / 2),
                        child: _Face(
                          face: f,
                          person: _people[f.id],
                          label: '${_name(f.id)}${_tried.contains(f.id) ? ', tried' : ''}${_solved && f.id == r.target.id ? ', found' : ''}',
                          size: side,
                          tried: _tried.contains(f.id),
                          glow: !_solved && _slips >= 2 && f.id == r.target.id,
                          wiggles: _wiggles[f.id] ?? 0,
                          hops: _hops[f.id] ?? 0,
                          onTap: () => _tap(f),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ),
          TopPrompt(
            child: PromptPill(
              id: 'who.ask',
              label: switch ((_solved, r.target.id == widget.c.kid.id)) {
                (true, true) => "That's you!",
                (true, false) => 'You found $target',
                (false, true) => 'Where are you?',
                (false, false) => 'Where is $target?',
              },
              onSayAgain: _ask,
              children: [DEmoji('👀', size: 40 * t.scale), SizedBox(width: t.space.xs), DEmoji('👪', size: 40 * t.scale)],
            ),
          ),
        ],
      ),
    );
  }
}

/// A family member's face in a big circle, ringed in their color.
class _Face extends StatelessWidget {
  const _Face({
    required this.face,
    required this.person,
    required this.label,
    required this.size,
    required this.tried,
    required this.glow,
    required this.wiggles,
    required this.hops,
    required this.onTap,
  });
  final WhoFace face;
  final Profile? person;
  final String label;
  final double size;
  final bool tried, glow;
  final int wiggles, hops;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = person;
    return DPressable(
      id: 'who.face.${face.id}',
      semanticLabel: label,
      excludeSemantics: true,
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      child: Hop(
        count: hops,
        child: Wiggle(
          count: wiggles,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: EdgeInsets.all(size * 0.03),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              // A solid halo, not a blur: blurs are too slow to animate on a frame.
              boxShadow: [BoxShadow(color: glow ? const Color(0xAAFFD54F) : const Color(0x00FFD54F), spreadRadius: glow ? 14 : 0)],
            ),
            // A face she tried sits back: smaller, no fade layer.
            child: AnimatedScale(
              scale: tried ? 0.86 : 1,
              duration: const Duration(milliseconds: 250),
              child: p == null ? SizedBox.square(dimension: size * 0.94) : ProfileAvatar(p, size: size * 0.94),
            ),
          ),
        ),
      ),
    );
  }
}
