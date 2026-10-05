import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/dearth_theme.dart';
import '../tokens/metrics.dart';

/// Wraps [child] in its own semantics node carrying a stable test identifier
/// (SPEC §16.3). On web it renders as `flt-semantics-identifier`, which the
/// Playwright suite selects on. Identifiers are part of the test contract.
Widget tid(String id, Widget child) => Semantics(identifier: id, container: true, child: child);

/// A whole screen's test id. Its children always keep their own semantics
/// nodes: text merged into the screen's node would give it a role, and when
/// the screen's data arrived and that text moved into a child, Flutter web
/// rebuilt the node without its identifier (`screen.kids` went missing on
/// some loads).
Widget screenTid(String id, Widget child) => Semantics(identifier: id, container: true, explicitChildNodes: true, child: child);

/// The one tappable primitive (SPEC §11.1, §12.3): a layer-backed press scale
/// and highlight instead of Material ink sparkle, generous hit areas, an
/// optional deliberate long press (≥ 600 ms), and button semantics with an
/// optional test [id].
class DPressable extends StatefulWidget {
  const DPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.longPressDuration = const Duration(milliseconds: 600),
    this.id,
    this.semanticLabel,
    this.selected,
    this.borderRadius,
    this.pressedScale = 0.97,
    this.highlightColor,
    this.enabled = true,
    this.haptic = false,
    this.behavior = HitTestBehavior.opaque,
    this.excludeSemantics = false,
    this.pressFeedback = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Duration longPressDuration;
  final String? id;
  final String? semanticLabel;
  final bool? selected;
  final BorderRadius? borderRadius;
  final double pressedScale;
  final Color? highlightColor;
  final bool enabled;
  final bool haptic;
  final HitTestBehavior behavior;

  /// Leaf controls whose [semanticLabel] already says everything set this so
  /// screen readers don't read the label and the child text twice.
  final bool excludeSemantics;

  /// Off for items inside a scrolling grid: the press fade is an opacity
  /// layer and the scale a transform over the item, and every scroll begins
  /// with a pointer-down on some item (AGENTS rule 8). Taps still work.
  final bool pressFeedback;

  @override
  State<DPressable> createState() => _DPressableState();
}

class _DPressableState extends State<DPressable> with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(vsync: this, duration: DMotion.micro, reverseDuration: DMotion.fast);
  late final Animation<double> _scale = Tween<double>(begin: 1, end: widget.pressedScale)
      .animate(CurvedAnimation(parent: _press, curve: Curves.easeOut, reverseCurve: Curves.easeOutCubic));

  bool get _interactive => widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  @override
  void didUpdateWidget(DPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_interactive && _press.value > 0) _press.reverse();
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _down() {
    if (_interactive && widget.pressFeedback) _press.forward();
  }

  void _up() {
    if (!widget.pressFeedback) return;
    if (_press.isAnimating || _press.value > 0) _press.reverse();
  }

  void _tap() {
    if (!_interactive || widget.onTap == null) return;
    if (widget.haptic) HapticFeedback.selectionClick();
    widget.onTap!();
  }

  void _longPress() {
    if (!_interactive || widget.onLongPress == null) return;
    HapticFeedback.mediumImpact();
    _up();
    widget.onLongPress!();
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final radius = widget.borderRadius ?? t.radius.card;
    final highlight = widget.highlightColor ?? t.colors.inkPrimary.withValues(alpha: t.colors.isDark ? 0.10 : 0.06);

    Widget content = Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        if (widget.pressFeedback)
          Positioned.fill(
            child: IgnorePointer(
              child: FadeTransition(
                opacity: _press,
                child: DecoratedBox(decoration: BoxDecoration(color: highlight, borderRadius: radius)),
              ),
            ),
          ),
      ],
    );
    if (widget.pressFeedback && widget.pressedScale != 1) content = ScaleTransition(scale: _scale, child: content);

    final gestures = <Type, GestureRecognizerFactory>{
      TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
        TapGestureRecognizer.new,
        (r) => r
          ..onTapDown = (_) {
            _down();
          }
          ..onTapUp = (_) {
            _up();
          }
          ..onTapCancel = _up
          ..onTap = widget.onTap == null ? null : _tap,
      ),
      if (widget.onLongPress != null)
        LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
          () => LongPressGestureRecognizer(duration: widget.longPressDuration),
          (r) => r
            ..onLongPressStart = (_) {
              _down();
            }
            ..onLongPress = _longPress
            ..onLongPressEnd = (_) {
              _up();
            }
            ..onLongPressCancel = _up,
        ),
    };

    return Semantics(
      container: true,
      button: _interactive,
      enabled: widget.enabled,
      selected: widget.selected,
      identifier: widget.id,
      label: widget.semanticLabel,
      excludeSemantics: widget.excludeSemantics,
      onTap: widget.onTap == null || !widget.enabled ? null : _tap,
      onLongPress: widget.onLongPress == null || !widget.enabled ? null : _longPress,
      child: MouseRegion(
        cursor: _interactive ? SystemMouseCursors.click : MouseCursor.defer,
        child: RawGestureDetector(
          behavior: widget.behavior,
          gestures: _interactive ? gestures : const {},
          excludeFromSemantics: true,
          child: content,
        ),
      ),
    );
  }
}

/// Hold-to-activate with ring progress feedback (kiosk exit gesture, the
/// grown-up corner on kid surfaces; SPEC §9.3, §11.10). A tap does nothing.
class DHoldToActivate extends StatefulWidget {
  const DHoldToActivate({
    super.key,
    required this.child,
    required this.onActivated,
    this.duration = const Duration(seconds: 3),
    this.id,
    this.semanticLabel,
    this.ringColor,
  });

  final Widget child;
  final VoidCallback onActivated;
  final Duration duration;
  final String? id;
  final String? semanticLabel;
  final Color? ringColor;

  @override
  State<DHoldToActivate> createState() => _DHoldToActivateState();
}

class _DHoldToActivateState extends State<DHoldToActivate> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        HapticFeedback.heavyImpact();
        widget.onActivated();
        _c.value = 0;
      }
    });

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Semantics(
      container: true,
      identifier: widget.id,
      label: widget.semanticLabel,
      // Long-press semantic action lets assistive tech (and E2E) trigger it.
      onLongPress: widget.onActivated,
      child: Listener(
        onPointerDown: (_) => _c.forward(from: 0),
        onPointerUp: (_) => _c.reverse(),
        onPointerCancel: (_) => _c.reverse(),
        behavior: HitTestBehavior.opaque,
        child: Stack(
          alignment: Alignment.center,
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) => _c.value == 0
                        ? const SizedBox.shrink()
                        : CustomPaint(painter: _HoldRingPainter(_c.value, widget.ringColor ?? t.colors.accent, 4 * t.scale)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HoldRingPainter extends CustomPainter {
  _HoldRingPainter(this.progress, this.color, this.stroke);
  final double progress;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2 - stroke;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_HoldRingPainter old) => old.progress != progress || old.color != color;
}
