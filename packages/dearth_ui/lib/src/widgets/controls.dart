import 'package:material_ui/material_ui.dart';

import '../theme/dearth_theme.dart';
import '../tokens/colors.dart';
import '../tokens/metrics.dart';
import 'pressable.dart';

/// Button tones.
enum DButtonTone { primary, tonal, neutral, outline, ghost, danger }

/// Button sizes: 48 / 56 / 64 dp at uiScale 1 (SPEC §11.1 touch targets).
enum DButtonSize { sm, md, lg }

/// The standard button. Pill-shaped, token-colored, no ink sparkle.
class DButton extends StatelessWidget {
  const DButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.emoji,
    this.tone = DButtonTone.primary,
    this.size = DButtonSize.md,
    this.id,
    this.expand = false,
    this.busy = false,
    this.trailingIcon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final String? emoji;
  final DButtonTone tone;
  final DButtonSize size;
  final String? id;
  final bool expand;
  final bool busy;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final c = t.colors;
    final enabled = onPressed != null && !busy;
    final (bg, fg, border) = switch (tone) {
      DButtonTone.primary => (c.accent, c.onAccent, null),
      DButtonTone.tonal => (c.accentTint, c.isDark ? c.inkPrimary : c.accent, null),
      DButtonTone.neutral => (c.surfaceSunken, c.inkPrimary, null),
      DButtonTone.outline => (Colors.transparent, c.inkPrimary, c.outline),
      DButtonTone.ghost => (Colors.transparent, c.accent, null),
      DButtonTone.danger => (c.danger, Colors.white, null),
    };
    final height = switch (size) {
      DButtonSize.sm => t.space.touchDense,
      DButtonSize.md => 56 * t.scale,
      DButtonSize.lg => t.space.touch,
    };
    final textStyle = (size == DButtonSize.lg ? t.text.bodyStrong : t.text.label).copyWith(color: fg);
    final iconSize = size == DButtonSize.sm ? t.iconSm : t.iconMd * 0.9;
    final radius = t.radius.pill;
    final child = DDimmed(
      visible: enabled || busy,
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: size == DButtonSize.sm ? t.space.md : t.space.lg),
        decoration: BoxDecoration(color: bg, borderRadius: radius, border: border == null ? null : Border.all(color: border, width: 1.5)),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              SizedBox.square(dimension: iconSize * 0.8, child: CircularProgressIndicator(strokeWidth: 2.5 * t.scale, color: fg))
            else if (icon != null)
              Icon(icon, size: iconSize, color: fg)
            else if (emoji != null)
              DEmoji(emoji!, size: iconSize),
            if (busy || icon != null || emoji != null) SizedBox(width: t.space.xs),
            Flexible(child: Text(label, style: textStyle, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (trailingIcon != null) ...[SizedBox(width: t.space.xxs), Icon(trailingIcon, size: iconSize, color: fg)],
          ],
        ),
      ),
    );
    return DPressable(
      onTap: enabled ? onPressed : null,
      enabled: enabled,
      id: id,
      semanticLabel: label,
      excludeSemantics: true,
      borderRadius: radius,
      child: child,
    );
  }
}

/// Dims a disabled control. Controls are small leaves, so the `Opacity`
/// layer stays cheap (never wrap large subtrees; SPEC §12.3).
class DDimmed extends StatelessWidget {
  const DDimmed({super.key, required this.visible, required this.child});
  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => visible ? child : Opacity(opacity: 0.45, child: child);
}

/// A round icon button.
class DIconButton extends StatelessWidget {
  const DIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.label,
    this.tone = DButtonTone.neutral,
    this.size,
    this.id,
    this.badge = false,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  /// Accessibility label (also the tooltip on desktop).
  final String label;
  final DButtonTone tone;
  final double? size;
  final String? id;
  final bool badge;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final c = t.colors;
    final dim = size ?? t.space.touchDense;
    final (bg, fg) = switch (tone) {
      DButtonTone.primary => (c.accent, c.onAccent),
      DButtonTone.tonal => (c.accentTint, c.isDark ? c.inkPrimary : c.accent),
      DButtonTone.neutral => (c.surfaceSunken, c.inkPrimary),
      DButtonTone.outline => (Colors.transparent, c.inkPrimary),
      DButtonTone.ghost => (Colors.transparent, c.inkSecondary),
      DButtonTone.danger => (c.danger, Colors.white),
    };
    return DPressable(
      onTap: onPressed,
      enabled: onPressed != null,
      id: id,
      semanticLabel: label,
      excludeSemantics: true,
      borderRadius: BorderRadius.circular(dim),
      pressedScale: 0.92,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        waitDuration: const Duration(milliseconds: 600),
        child: SizedBox.square(
          dimension: dim,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: tone == DButtonTone.outline ? Border.all(color: c.outline, width: 1.5) : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, size: dim * 0.5, color: color ?? fg),
                if (badge)
                  Positioned(
                    top: dim * 0.18,
                    right: dim * 0.18,
                    child: Container(
                      width: dim * 0.2,
                      height: dim * 0.2,
                      decoration: BoxDecoration(color: c.danger, shape: BoxShape.circle, border: Border.all(color: c.surfaceRaised, width: 2)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A selectable chip (filters, choices). Person chips pass [personColor].
class DChip extends StatelessWidget {
  const DChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.leading,
    this.emoji,
    this.personColor,
    this.id,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? leading;
  final String? emoji;
  final PersonColors? personColor;
  final String? id;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final c = t.colors;
    final pc = personColor;
    final bg = selected ? (pc?.solid ?? c.accent) : (pc?.tint ?? c.surfaceSunken);
    final fg = selected ? (pc?.onSolid ?? c.onAccent) : (pc?.ink ?? c.inkPrimary);
    final h = dense ? 40 * t.scale : t.space.touchDense;
    return DPressable(
      onTap: onTap,
      id: id,
      selected: selected,
      semanticLabel: label,
      excludeSemantics: true,
      borderRadius: t.radius.pill,
      child: AnimatedContainer(
        duration: t.motion(DMotion.fast),
        curve: DMotion.standardCurve,
        height: h,
        padding: EdgeInsets.symmetric(horizontal: dense ? t.space.sm : t.space.md),
        decoration: BoxDecoration(color: bg, borderRadius: t.radius.pill),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, SizedBox(width: t.space.xs)],
            if (emoji != null) ...[DEmoji(emoji!, size: h * 0.48), SizedBox(width: t.space.xs)],
            Text(label, style: (dense ? t.text.caption : t.text.label).copyWith(color: fg, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// Renders an emoji glyph at a stable box size. Content icons (events,
/// chores, meals, weather for kids) all go through this widget so a
/// pre-rasterized emoji set can replace the font later without touching
/// call sites (SPEC §11.3).
class DEmoji extends StatelessWidget {
  const DEmoji(this.emoji, {super.key, required this.size, this.semanticLabel});
  final String emoji;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final glyph = Text(
      emoji,
      textAlign: TextAlign.center,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      textScaler: TextScaler.noScaling,
      style: TextStyle(fontSize: size * 0.86, height: 1.12, inherit: false, fontFamilyFallback: const ['Noto Color Emoji', 'Apple Color Emoji', 'Segoe UI Emoji']),
    );
    final box = SizedBox.square(dimension: size, child: Center(child: glyph));
    return semanticLabel == null ? ExcludeSemantics(child: box) : Semantics(label: semanticLabel, child: ExcludeSemantics(child: box));
  }
}

/// A circular person avatar: emoji (or initial) on the person's tint, with
/// an optional progress ring (chores done; SPEC §11.8 `DAvatar`).
class DAvatar extends StatelessWidget {
  const DAvatar({super.key, required this.colorIndex, this.emoji, this.name, required this.size, this.progress, this.ring = true, this.semanticLabel});

  final int colorIndex;
  final String? emoji;
  final String? name;
  final double size;

  /// 0…1; null hides the ring progress.
  final double? progress;
  final bool ring;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final pc = t.person(colorIndex);
    final stroke = (size * 0.07).clamp(2.0, 6.0);
    final inner = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: pc.tint,
        shape: BoxShape.circle,
        border: ring && progress == null ? Border.all(color: pc.solid, width: stroke) : null,
      ),
      child: emoji != null && emoji!.isNotEmpty
          ? DEmoji(emoji!, size: size * 0.58)
          : Text(
              (name ?? '?').characters.firstOrNull?.toUpperCase() ?? '?',
              style: t.text.title.copyWith(fontSize: size * 0.42, color: pc.ink, fontWeight: FontWeight.w800, height: 1),
            ),
    );
    final widget = progress == null
        ? inner
        : CustomPaint(
            foregroundPainter: RingPainter(progress: progress!.clamp(0, 1), color: pc.solid, track: pc.solid.withValues(alpha: 0.22), stroke: stroke),
            child: inner,
          );
    return Semantics(label: semanticLabel ?? name, image: true, child: ExcludeSemantics(child: widget));
  }
}

/// A ring arc from 12 o'clock, used by avatars and progress rings.
class RingPainter extends CustomPainter {
  const RingPainter({required this.progress, required this.color, required this.track, required this.stroke});
  final double progress;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 6.283185307, false, paint..color = track);
    if (progress > 0) canvas.drawArc(rect, -1.5707963, 6.283185307 * progress, false, paint..color = color);
  }

  @override
  bool shouldRepaint(RingPainter old) => old.progress != progress || old.color != color || old.track != track || old.stroke != stroke;
}

/// A progress ring with centered content (countdowns, goals).
class DProgressRing extends StatelessWidget {
  const DProgressRing({super.key, required this.progress, required this.size, this.color, this.stroke, this.child});
  final double progress;
  final double size;
  final Color? color;
  final double? stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final col = color ?? t.colors.accent;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: RingPainter(progress: progress.clamp(0, 1), color: col, track: col.withValues(alpha: 0.16), stroke: stroke ?? size * 0.09),
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// A pill segmented control (view switchers).
class DSegmented<T> extends StatelessWidget {
  const DSegmented({super.key, required this.options, required this.value, required this.onChanged, this.idPrefix, this.dense = false});

  final List<(T value, String label)> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// Test ids become `$idPrefix.$label` (lower-case, no spaces).
  final String? idPrefix;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final c = t.colors;
    final h = dense ? 40 * t.scale : t.space.touchDense;
    return Container(
      height: h + 8 * t.scale,
      padding: EdgeInsets.all(4 * t.scale),
      decoration: BoxDecoration(color: c.surfaceSunken, borderRadius: t.radius.pill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (v, label) in options)
            DPressable(
              onTap: () => onChanged(v),
              id: idPrefix == null ? null : '$idPrefix.${label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}',
              selected: v == value,
              semanticLabel: label,
              excludeSemantics: true,
              borderRadius: t.radius.pill,
              pressedScale: 0.96,
              child: AnimatedContainer(
                duration: t.motion(DMotion.fast),
                curve: DMotion.standardCurve,
                height: h,
                padding: EdgeInsets.symmetric(horizontal: dense ? t.space.sm : t.space.md),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: v == value ? c.surfaceRaised : Colors.transparent,
                  borderRadius: t.radius.pill,
                  boxShadow: v == value && !c.isDark ? t.elevation.e1 : null,
                ),
                child: Text(
                  label,
                  style: (dense ? t.text.caption : t.text.label).copyWith(
                    color: v == value ? c.inkPrimary : c.inkSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// − value + (servings, durations).
class DStepper extends StatelessWidget {
  const DStepper({super.key, required this.value, required this.onChanged, this.min = 1, this.max = 99, this.step = 1, this.format, this.id});
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final int step;
  final String Function(int)? format;
  final String? id;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DIconButton(icon: Icons.remove_rounded, label: 'Less', id: id == null ? null : '$id.minus', onPressed: value - step >= min ? () => onChanged(value - step) : null),
        ConstrainedBox(
          constraints: BoxConstraints(minWidth: 64 * t.scale),
          child: Text(format?.call(value) ?? '$value', textAlign: TextAlign.center, style: t.text.title.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ),
        DIconButton(icon: Icons.add_rounded, label: 'More', id: id == null ? null : '$id.plus', onPressed: value + step <= max ? () => onChanged(value + step) : null),
      ],
    );
  }
}

/// A settings-style row: leading, title + subtitle, trailing; tappable.
class DListRow extends StatelessWidget {
  const DListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.id,
    this.dense = false,
    this.chevron = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? id;
  final bool dense;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: dense ? t.space.touchDense : t.space.touch),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.xs),
        child: Row(
          children: [
            if (leading != null) ...[leading!, SizedBox(width: t.space.md)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: dense ? t.text.label : t.text.body.copyWith(fontWeight: FontWeight.w600)),
                  if (subtitle != null) ...[SizedBox(height: 2 * t.scale), Text(subtitle!, style: t.text.caption)],
                ],
              ),
            ),
            if (trailing != null) ...[SizedBox(width: t.space.sm), trailing!],
            if (chevron) ...[SizedBox(width: t.space.xs), Icon(Icons.chevron_right_rounded, color: t.colors.inkTertiary, size: t.iconMd)],
          ],
        ),
      ),
    );
    if (onTap == null) return id == null ? row : tid(id!, row);
    return DPressable(
      onTap: onTap,
      id: id,
      semanticLabel: subtitle == null ? title : '$title, $subtitle',
      excludeSemantics: trailing == null,
      pressedScale: 0.99,
      borderRadius: t.radius.card,
      child: row,
    );
  }
}

/// A row with a switch.
class DSwitchRow extends StatelessWidget {
  const DSwitchRow({super.key, required this.title, required this.value, required this.onChanged, this.subtitle, this.leading, this.id});
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? leading;
  final String? id;

  @override
  Widget build(BuildContext context) {
    return DListRow(
      title: title,
      subtitle: subtitle,
      leading: leading,
      id: id,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      trailing: ExcludeSemantics(child: Switch(value: value, onChanged: onChanged)),
    );
  }
}
