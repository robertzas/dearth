import 'dart:math' as math;

import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

/// A shake each time [count] grows: "not that one".
class Wiggle extends StatelessWidget {
  const Wiggle({super.key, required this.count, required this.child});
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        key: ValueKey(count),
        tween: Tween(begin: count == 0 ? 0 : 1, end: 0),
        duration: const Duration(milliseconds: 550),
        builder: (context, k, child) => Transform.translate(offset: Offset(math.sin(k * math.pi * 5) * 12 * k, 0), child: child),
        child: child,
      );
}

/// A hop each time [count] grows: "yes, that one".
class Hop extends StatelessWidget {
  const Hop({super.key, required this.count, required this.child});
  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        key: ValueKey(count),
        tween: Tween(begin: count == 0 ? 0 : 1, end: 0),
        duration: const Duration(milliseconds: 600),
        builder: (context, k, child) => Transform.translate(offset: Offset(0, -math.sin(k * math.pi) * 24), child: child),
        child: child,
      );
}

/// A big picture to choose: a white rounded tile that fades back once
/// tried, glows as a hint, and keeps its tap handler (and so its test id on
/// the web) in every state.
class PictureTile extends StatelessWidget {
  const PictureTile({
    super.key,
    required this.id,
    required this.label,
    required this.child,
    required this.size,
    required this.onTap,
    this.tried = false,
    this.hint = false,
    this.wiggles = 0,
    this.hops = 0,
    this.width,
  });

  final String id;
  final String label;
  final Widget child;
  final double size;

  /// Wider than tall, for towers and rows.
  final double? width;
  final VoidCallback onTap;
  final bool tried, hint;
  final int wiggles, hops;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final r = BorderRadius.circular(size * 0.22);
    return DPressable(
      id: id,
      semanticLabel: label,
      excludeSemantics: true,
      onTap: onTap,
      pressedScale: 0.94,
      borderRadius: r,
      child: Hop(
        count: hops,
        child: Wiggle(
          count: wiggles,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: width ?? size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tried ? const Color(0xFFECE6DA) : Colors.white,
              borderRadius: r,
              border: Border.all(color: hint ? const Color(0xFFFFC93C) : const Color(0xFFE3DCF5), width: hint ? 7 : 3),
              // A solid halo, not a blur, always first in the list so a
              // change animates only the halo: blurs are too slow to animate
              // on a frame.
              boxShadow: [BoxShadow(color: hint ? const Color(0x88FFD54F) : const Color(0x00FFD54F), spreadRadius: hint ? 10 : 0), ...t.elevation.e1],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A soft two-color backdrop.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.top, required this.bottom, required this.child});
  final Color top, bottom;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom])),
        child: child,
      );
}

/// The playfield under the home button: padded, safe.
class PlayArea extends StatelessWidget {
  const PlayArea({super.key, required this.child, this.top = 96});
  final Widget child;
  final double top;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return SafeArea(child: Padding(padding: EdgeInsets.fromLTRB(t.space.lg, top * t.scale, t.space.lg, t.space.lg), child: child));
  }
}
