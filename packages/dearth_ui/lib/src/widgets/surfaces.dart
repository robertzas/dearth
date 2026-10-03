import 'package:material_ui/material_ui.dart';

import '../theme/dearth_theme.dart';
import 'pressable.dart';

/// A raised content card (SPEC §11.3: radius M, single analytic shadow).
class DCard extends StatelessWidget {
  const DCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.onTap,
    this.onLongPress,
    this.id,
    this.semanticLabel,
    this.elevated = true,
    this.outlined = false,
    this.borderRadius,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? id;
  final String? semanticLabel;
  final bool elevated;
  final bool outlined;
  final BorderRadius? borderRadius;

  /// Clip children to the rounded shape (only for photos; costs a clip layer).
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final radius = borderRadius ?? t.radius.card;
    Widget body = Padding(padding: padding ?? EdgeInsets.all(t.space.lg), child: child);
    if (clip) body = ClipRRect(borderRadius: radius, child: body);
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? t.colors.surfaceRaised,
        borderRadius: radius,
        boxShadow: elevated && !t.colors.isDark ? t.elevation.e1 : null,
        border: outlined || (elevated && t.colors.isDark) ? Border.all(color: t.colors.outline) : null,
      ),
      child: body,
    );
    if (onTap == null && onLongPress == null) {
      return id == null ? box : tid(id!, box);
    }
    return DPressable(
      onTap: onTap,
      onLongPress: onLongPress,
      id: id,
      semanticLabel: semanticLabel,
      excludeSemantics: semanticLabel != null,
      borderRadius: radius,
      pressedScale: 0.985,
      child: box,
    );
  }
}

/// A titled region: overline label, optional trailing action, then content.
class DSection extends StatelessWidget {
  const DSection({super.key, required this.title, required this.child, this.trailing, this.gap, this.id, this.onTitleTap});

  final String title;
  final Widget child;
  final Widget? trailing;
  final double? gap;
  final String? id;
  final VoidCallback? onTitleTap;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    Widget header = Row(
      children: [
        Expanded(child: Text(title.toUpperCase(), style: t.text.overline, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ?trailing,
      ],
    );
    if (onTitleTap != null) header = DPressable(onTap: onTitleTap, pressedScale: 1, child: header);
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [header, SizedBox(height: gap ?? t.space.sm), child],
    );
    return id == null ? column : tid(id!, column);
  }
}

/// A screen title row: H1 title, optional subtitle and actions (SPEC §11.7).
class DPageHeader extends StatelessWidget {
  const DPageHeader({super.key, required this.title, this.subtitle, this.actions = const [], this.leading, this.compact = false});

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final titleStyle = compact || t.isPhone ? t.text.h2 : t.text.h1;
    return Row(
      children: [
        if (leading != null) ...[leading!, SizedBox(width: t.space.sm)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: titleStyle, maxLines: 1, overflow: TextOverflow.ellipsis, semanticsLabel: title),
              if (subtitle != null) ...[
                SizedBox(height: t.space.xxs),
                Text(subtitle!, style: t.text.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
        for (final (i, a) in actions.indexed) ...[if (i > 0) SizedBox(width: t.space.xs), a],
      ],
    );
  }
}

/// A thin divider in the outline color.
class DDivider extends StatelessWidget {
  const DDivider({super.key, this.indent = 0, this.vertical = false});
  final double indent;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final c = DTheme.of(context).colors.outline;
    return vertical
        ? Padding(padding: EdgeInsets.symmetric(vertical: indent), child: SizedBox(width: 1, child: ColoredBox(color: c)))
        : Padding(padding: EdgeInsets.only(left: indent), child: SizedBox(height: 1, width: double.infinity, child: ColoredBox(color: c)));
  }
}
