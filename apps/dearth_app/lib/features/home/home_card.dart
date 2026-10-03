import 'package:dearth_ui/dearth_ui.dart';
import 'package:material_ui/material_ui.dart';

/// A Home widget frame: overline title, optional trailing action, content.
/// Each widget is an independent repaint boundary (FR-HOME-07).
class HomeCard extends StatelessWidget {
  const HomeCard({
    super.key,
    required this.title,
    required this.child,
    this.id,
    this.trailing,
    this.onTap,
    this.onTitleTap,
    this.expand = false,
    this.color,
    this.padding,
  });

  final String title;
  final Widget child;
  final String? id;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onTitleTap;

  /// Fill the available height (child must then be flexible/scrollable).
  final bool expand;
  final Color? color;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    Widget header = Row(
      children: [
        Expanded(child: Text(title.toUpperCase(), style: t.text.overline, maxLines: 1)),
        ?trailing,
      ],
    );
    if (onTitleTap != null) {
      header = DPressable(onTap: onTitleTap, pressedScale: 1, semanticLabel: title, child: header);
    }
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        SizedBox(height: trailing == null ? 28 * t.scale : 44 * t.scale, child: Align(alignment: Alignment.centerLeft, child: header)),
        SizedBox(height: t.space.xs),
        if (expand) Expanded(child: child) else child,
      ],
    );
    return RepaintBoundary(
      child: DCard(
        id: id,
        color: color,
        onTap: onTap,
        padding: padding ?? EdgeInsets.fromLTRB(t.space.lg, t.space.md, t.space.lg, t.space.lg),
        child: body,
      ),
    );
  }
}
