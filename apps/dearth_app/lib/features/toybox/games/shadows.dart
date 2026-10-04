import 'dart:async';
import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/sound.dart';
import '../game_host.dart';
import 'game_widgets.dart';

const Color _shade = Color(0xFF3A3452);

/// Shadow Match (SPEC FR-TOY-03, Appendix B: visual discrimination).
/// Pictures wait in a tray under a row of shadows; she drags each onto its
/// own shadow (or taps it, then the shadow), and it fills in with color. A
/// wrong shadow sends it back with a wiggle. Two shadows at first, then six
/// from one family, so they look alike.
class ShadowsGame extends StatefulWidget {
  const ShadowsGame(this.c, {super.key});
  final GameController c;

  @override
  State<ShadowsGame> createState() => ShadowsGameState();
}

@visibleForTesting
class ShadowsGameState extends State<ShadowsGame> {
  final _area = GlobalKey();
  late ShadowRound _round;
  final _placed = <String>{};
  final _wiggles = <String, int>{};
  int _slips = 0, _deal = 0;
  String? _dragging, _selected;
  Offset _dragAt = Offset.zero, _grip = Offset.zero;
  Timer? _next;
  _Layout? _layout;

  @visibleForTesting
  ShadowRound get debugRound => _round;

  @override
  void initState() {
    super.initState();
    _newRound();
  }

  @override
  void dispose() {
    _next?.cancel();
    super.dispose();
  }

  void _newRound() {
    _round = shadowRound(widget.c.level, widget.c.random);
    _placed.clear();
    _slips = 0;
    _dragging = _selected = null;
    _deal++;
    if (mounted) setState(() {});
  }

  /// Tries [picture] on the shadow of [shadow].
  void _fit(String picture, String shadow) {
    if (picture != shadow) {
      _slips++;
      widget.c.sound(Sfx.boing, volume: 0.7);
      setState(() {
        _wiggles[picture] = (_wiggles[picture] ?? 0) + 1;
        _selected = null;
      });
      return;
    }
    widget.c.sound(Sfx.snap);
    setState(() {
      _placed.add(picture);
      _selected = null;
    });
    if (_placed.length == _round.pictures.length) {
      unawaited(widget.c.finishRound(expansionResult(_slips, size: _round.pictures.length), emoji: picture));
      _next = Timer(const Duration(milliseconds: 2600), _newRound);
    }
  }

  void _tapPicture(String p) {
    if (_placed.contains(p)) return;
    widget.c.sound(Sfx.tap, volume: 0.6);
    setState(() => _selected = _selected == p ? null : p);
  }

  void _tapShadow(String s) {
    final p = _selected;
    if (p == null || _placed.contains(s)) return;
    _fit(p, s);
  }

  Offset _local(Offset global) => (_area.currentContext!.findRenderObject()! as RenderBox).globalToLocal(global);

  void _dragEnd() {
    final p = _dragging, l = _layout;
    if (p == null || l == null) return;
    _dragging = null;
    String? near;
    var best = double.infinity;
    for (final (i, s) in _round.shadows.indexed) {
      if (_placed.contains(s)) continue;
      final d = (l.shadows[i] - _dragAt).distance;
      if (d < best) (best, near) = (d, s);
    }
    if (near != null && best < l.size * 0.6) {
      _fit(p, near);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Backdrop(
      top: const Color(0xFFFFF6D9),
      bottom: const Color(0xFFE9F7E4),
      child: PlayArea(
        child: LayoutBuilder(
          key: _area,
          builder: (context, box) {
            final l = _layout = _Layout.of(box.biggest, _round.pictures.length);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                for (final (i, s) in _round.shadows.indexed)
                  Positioned(
                    left: l.shadows[i].dx - l.size / 2,
                    top: l.shadows[i].dy - l.size / 2,
                    child: tid(
                      'shadows.shadow.$i',
                      Semantics(
                        button: true,
                        label: _placed.contains(s) ? s : 'Shadow ${i + 1}',
                        onTap: () => _tapShadow(s),
                        excludeSemantics: true,
                        child: GestureDetector(
                          excludeFromSemantics: true,
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _tapShadow(s),
                          child: _Shadow(emoji: s, size: l.size, glow: _slips >= 2 && (_dragging ?? _selected) == s),
                        ),
                      ),
                    ),
                  ),
                for (final (i, p) in _round.pictures.indexed) _picture(p, i, l),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _picture(String p, int i, _Layout l) {
    final placed = _placed.contains(p), dragging = _dragging == p;
    final home = l.tray[i];
    final center = placed ? l.shadows[_round.shadows.indexOf(p)] : (dragging ? _dragAt : home);
    return AnimatedPositioned(
      key: ValueKey('$_deal.$i'),
      duration: dragging ? Duration.zero : const Duration(milliseconds: 360),
      curve: Curves.easeOutBack,
      left: center.dx - l.size / 2,
      top: center.dy - l.size / 2,
      child: IgnorePointer(
        ignoring: placed,
        child: tid(
          'shadows.picture.$i',
          Semantics(
            button: true,
            label: p,
            onTap: () => _tapPicture(p),
            excludeSemantics: true,
            child: GestureDetector(
              excludeFromSemantics: true,
              dragStartBehavior: DragStartBehavior.down,
              onTap: () => _tapPicture(p),
              onPanStart: (d) => setState(() {
                _dragging = p;
                _selected = null;
                _grip = center - _local(d.globalPosition);
                _dragAt = center;
              }),
              onPanUpdate: (d) => setState(() => _dragAt = _local(d.globalPosition) + _grip),
              onPanEnd: (_) => _dragEnd(),
              onPanCancel: _dragEnd,
              child: AnimatedScale(
                scale: dragging || _selected == p ? 1.12 : 1,
                duration: const Duration(milliseconds: 160),
                child: Wiggle(count: _wiggles[p] ?? 0, child: SizedBox.square(dimension: l.size, child: Center(child: DEmoji(p, size: l.size * 0.86)))),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A picture's shadow: the same emoji, tinted dark, painted once.
class _Shadow extends StatelessWidget {
  const _Shadow({required this.emoji, required this.size, required this.glow});
  final String emoji;
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: size,
              height: size,
              decoration: BoxDecoration(shape: BoxShape.circle, color: glow ? const Color(0x55FFD54F) : const Color(0x14000000)),
            ),
            // A small layer, filtered once and then kept: cheap on a frame.
            RepaintBoundary(child: ColorFiltered(colorFilter: const ColorFilter.mode(_shade, BlendMode.srcIn), child: DEmoji(emoji, size: size * 0.86))),
          ],
        ),
      );
}

/// Shadows on top, the tray below: one row, or two for many.
class _Layout {
  _Layout(this.shadows, this.tray, this.size);

  factory _Layout.of(Size area, int n) {
    final rows = n > 4 ? 2 : 1;
    final cols = (n / rows).ceil();
    final size = math.min(math.min(area.width / cols * 0.7, area.height * 0.42 / rows * 0.86), 230.0);
    List<Offset> grid(double top, double height, {bool stagger = false}) => [
          for (var i = 0; i < n; i++)
            Offset(
              area.width * ((i % cols) + 0.5 + (stagger && (i ~/ cols).isOdd ? 0.25 : 0)) / (cols + (stagger ? 0.25 : 0)),
              top + height * ((i ~/ cols) + 0.5) / rows,
            ),
        ];
    return _Layout(grid(0, area.height * 0.46), grid(area.height * 0.54, area.height * 0.46, stagger: true), size);
  }

  final List<Offset> shadows, tray;
  final double size;
}
