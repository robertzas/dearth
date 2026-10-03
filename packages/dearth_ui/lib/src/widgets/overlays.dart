import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../display/display.dart';
import '../theme/dearth_theme.dart';
import '../tokens/metrics.dart';
import 'controls.dart';
import 'pressable.dart';

// ─────────────────────────────── Sheets ────────────────────────────────────

/// Opens a sheet over the current view (SPEC §11.1 "keep context"): a side
/// sheet on landscape walls and tablets, a bottom sheet elsewhere. Tapping
/// the scrim dismisses; it never confirms (SPEC §11.10).
Future<T?> showDSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  String? id,
  double? width,
  bool scrollable = true,
  List<Widget> actions = const [],
}) {
  final t = DTheme.of(context);
  final size = MediaQuery.sizeOf(context);
  final side = (t.displayClass == DisplayClass.wallL || t.displayClass == DisplayClass.tablet) && size.width > size.height;
  return Navigator.of(context).push<T>(_DSheetRoute<T>(
    side: side,
    width: width ?? (t.isWall ? 640 * t.scale : 520 * t.scale),
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    scrim: t.colors.scrim.withValues(alpha: 0.42),
    duration: t.motion(DMotion.standard),
    builder: (context) => _DSheetFrame(title: title, id: id, side: side, scrollable: scrollable, actions: actions, child: builder(context)),
  ));
}

class _DSheetRoute<T> extends PopupRoute<T> {
  _DSheetRoute({required this.side, required this.width, required this.builder, required this.barrierLabel, required this.scrim, required this.duration});

  final bool side;
  final double width;
  final WidgetBuilder builder;
  final Color scrim;
  final Duration duration;

  @override
  final String barrierLabel;

  @override
  Color get barrierColor => scrim;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => duration;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final mq = MediaQuery.of(context);
    final t = DTheme.of(context);
    final sheet = Material(
      type: MaterialType.transparency,
      child: Container(
        width: side ? width.clamp(320, mq.size.width * 0.9) : double.infinity,
        constraints: BoxConstraints(maxHeight: side ? double.infinity : mq.size.height * 0.92),
        decoration: BoxDecoration(
          color: t.colors.surfaceRaised,
          borderRadius: side
              ? BorderRadius.horizontal(left: Radius.circular(t.radius.l))
              : BorderRadius.vertical(top: Radius.circular(t.radius.l)),
          boxShadow: t.elevation.e2,
        ),
        child: builder(context),
      ),
    );
    return Align(
      alignment: side ? Alignment.centerRight : Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(bottom: side ? 0 : mq.viewInsets.bottom),
        child: side ? SizedBox(height: mq.size.height, child: sheet) : sheet,
      ),
    );
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final curved = CurvedAnimation(parent: animation, curve: DMotion.emphasizedCurve, reverseCurve: DMotion.exitCurve);
    return SlideTransition(
      position: Tween<Offset>(begin: side ? const Offset(0.12, 0) : const Offset(0, 0.12), end: Offset.zero).animate(curved),
      child: FadeTransition(opacity: curved, child: child),
    );
  }
}

class _DSheetFrame extends StatelessWidget {
  const _DSheetFrame({required this.child, required this.side, required this.scrollable, this.title, this.id, this.actions = const []});
  final Widget child;
  final String? title;
  final String? id;
  final bool side;
  final bool scrollable;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final pad = t.isPhone ? t.space.md : t.space.lg;
    final body = Padding(padding: EdgeInsets.fromLTRB(pad, 0, pad, pad), child: child);
    final column = Column(
      mainAxisSize: side ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!side)
          Center(
            child: Container(
              margin: EdgeInsets.only(top: t.space.sm),
              width: 44 * t.scale,
              height: 5 * t.scale,
              decoration: BoxDecoration(color: t.colors.outline, borderRadius: t.radius.pill),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(pad, side ? pad : t.space.sm, t.space.sm, t.space.sm),
          child: Row(
            children: [
              Expanded(child: Text(title ?? '', style: t.text.h2, maxLines: 2, overflow: TextOverflow.ellipsis)),
              ...actions,
              DIconButton(
                icon: Icons.close_rounded,
                label: 'Close',
                tone: DButtonTone.ghost,
                id: 'sheet.close',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
        if (scrollable)
          Flexible(child: SingleChildScrollView(child: body))
        else
          Flexible(child: body),
      ],
    );
    return SafeArea(
      left: false,
      top: side,
      child: id == null ? column : tid(id!, column),
    );
  }
}

/// A centered confirmation dialog (never stacks; SPEC §11.10). Returns true
/// only when the confirm button is pressed.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'OK',
  String cancelLabel = 'Cancel',
  bool danger = false,
  String? emoji,
}) async {
  final t = DTheme.of(context);
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: t.colors.scrim.withValues(alpha: 0.42),
    transitionDuration: t.motion(DMotion.standard),
    pageBuilder: (context, _, _) => Center(
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: 520 * t.scale,
          margin: EdgeInsets.all(t.space.lg),
          padding: EdgeInsets.all(t.space.xl),
          decoration: BoxDecoration(color: t.colors.surfaceRaised, borderRadius: t.radius.sheet, boxShadow: t.elevation.e2),
          child: tid(
            'dialog.confirm',
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (emoji != null) ...[DEmoji(emoji, size: 56 * t.scale), SizedBox(height: t.space.md)],
                Text(title, style: t.text.h2, textAlign: emoji != null ? TextAlign.center : TextAlign.start),
                if (message != null) ...[
                  SizedBox(height: t.space.sm),
                  Text(message, style: t.text.body.copyWith(color: t.colors.inkSecondary), textAlign: emoji != null ? TextAlign.center : TextAlign.start),
                ],
                SizedBox(height: t.space.xl),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    DButton(label: cancelLabel, tone: DButtonTone.neutral, id: 'dialog.cancel', onPressed: () => Navigator.of(context).pop(false)),
                    SizedBox(width: t.space.sm),
                    DButton(
                      label: confirmLabel,
                      tone: danger ? DButtonTone.danger : DButtonTone.primary,
                      id: 'dialog.confirm.ok',
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: DMotion.emphasizedCurve);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween<double>(begin: 0.96, end: 1).animate(curved), child: child),
      );
    },
  );
  return result ?? false;
}

// ─────────────────────────────── Toasts ────────────────────────────────────

/// A queued, non-blocking message (SPEC §11.8 `DToast`).
class DToastData {
  DToastData(this.message, {this.emoji, this.actionLabel, this.onAction, this.duration = const Duration(seconds: 4), this.tone = DBannerTone.info});
  final String message;
  final String? emoji;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
  final DBannerTone tone;
  final int id = _nextId++;
  static int _nextId = 0;
}

/// Shows toasts from anywhere (providers, sync client) without a context.
class DToastController extends ChangeNotifier {
  final List<DToastData> _items = [];
  List<DToastData> get items => List.unmodifiable(_items);

  void show(String message, {String? emoji, String? actionLabel, VoidCallback? onAction, Duration? duration, DBannerTone tone = DBannerTone.info}) {
    final d = DToastData(message, emoji: emoji, actionLabel: actionLabel, onAction: onAction, tone: tone, duration: duration ?? const Duration(seconds: 4));
    _items.add(d);
    if (_items.length > 3) _items.removeAt(0);
    notifyListeners();
    Timer(d.duration, () => dismiss(d));
  }

  void dismiss(DToastData d) {
    if (_items.remove(d)) notifyListeners();
  }
}

/// Hosts toasts above [child] (bottom center).
class DToastHost extends StatelessWidget {
  const DToastHost({super.key, required this.controller, required this.child});
  final DToastController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          // The host sits above the Navigator, outside any route's Material:
          // give text a real default style (no debug underline).
          child: Material(
            type: MaterialType.transparency,
            child: SafeArea(
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final t = DTheme.of(context);
                  return Padding(
                    padding: EdgeInsets.all(t.space.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final d in controller.items)
                          _ToastView(key: ValueKey(d.id), data: d, onDismiss: () => controller.dismiss(d)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ToastView extends StatefulWidget {
  const _ToastView({super.key, required this.data, required this.onDismiss});
  final DToastData data;
  final VoidCallback onDismiss;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: DMotion.standard)..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final d = widget.data;
    final curved = CurvedAnimation(parent: _c, curve: DMotion.emphasizedCurve);
    final bg = t.colors.isDark ? t.colors.surfaceRaised : t.colors.inkPrimary;
    final fg = t.colors.isDark ? t.colors.inkPrimary : t.colors.surface;
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(curved),
        child: Padding(
          padding: EdgeInsets.only(top: t.space.xs),
          child: tid(
            'toast',
            Container(
              constraints: BoxConstraints(maxWidth: 720 * t.scale, minHeight: t.space.touchDense),
              padding: EdgeInsets.symmetric(horizontal: t.space.lg, vertical: t.space.sm),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: t.radius.pill,
                boxShadow: t.elevation.e2,
                border: t.colors.isDark ? Border.all(color: t.colors.outline) : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (d.emoji != null) ...[DEmoji(d.emoji!, size: 28 * t.scale), SizedBox(width: t.space.sm)],
                  Flexible(child: Text(d.message, style: t.text.label.copyWith(color: fg), maxLines: 2, overflow: TextOverflow.ellipsis)),
                  if (d.actionLabel != null) ...[
                    SizedBox(width: t.space.md),
                    DPressable(
                      id: 'toast.action',
                      onTap: () {
                        d.onAction?.call();
                        widget.onDismiss();
                      },
                      borderRadius: t.radius.pill,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: t.space.sm, vertical: t.space.xs),
                        child: Text(d.actionLabel!, style: t.text.label.copyWith(color: t.colors.isDark ? t.colors.accent : t.colors.accentTint, fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────── Banners ───────────────────────────────────

enum DBannerTone { info, success, warning, danger }

/// An inline status banner (weather alerts, sync problems, setup hints).
class DBanner extends StatelessWidget {
  const DBanner({super.key, required this.title, this.message, this.tone = DBannerTone.info, this.emoji, this.icon, this.action, this.onTap, this.id});
  final String title;
  final String? message;
  final DBannerTone tone;
  final String? emoji;
  final IconData? icon;
  final Widget? action;
  final VoidCallback? onTap;
  final String? id;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final c = t.colors;
    final accent = switch (tone) {
      DBannerTone.info => c.accent,
      DBannerTone.success => c.success,
      DBannerTone.warning => c.warning,
      DBannerTone.danger => c.danger,
    };
    final content = Container(
      padding: EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
      decoration: BoxDecoration(color: c.tintOf(accent, 0.12), borderRadius: t.radius.card, border: Border(left: BorderSide(color: accent, width: 4 * t.scale))),
      child: Row(
        children: [
          if (emoji != null) ...[DEmoji(emoji!, size: 32 * t.scale), SizedBox(width: t.space.sm)] else if (icon != null) ...[
            Icon(icon, color: accent, size: t.iconMd),
            SizedBox(width: t.space.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: t.text.label.copyWith(fontWeight: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (message != null) Text(message!, style: t.text.caption, maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (action != null) ...[SizedBox(width: t.space.sm), action!],
        ],
      ),
    );
    if (onTap != null) return DPressable(onTap: onTap, id: id, semanticLabel: title, pressedScale: 0.99, child: content);
    return id == null ? content : tid(id!, content);
  }
}

// ──────────────────────────── Empty & loading ──────────────────────────────

/// Designed empty state that invites action (SPEC FR-HOME-05, §16.4).
class DEmptyState extends StatelessWidget {
  const DEmptyState({super.key, required this.emoji, required this.title, this.message, this.action, this.compact = false, this.id});
  final String emoji;
  final String title;
  final String? message;
  final Widget? action;
  final bool compact;
  final String? id;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final bubble = (compact ? 64 : 112) * t.scale;
    final content = Padding(
      padding: EdgeInsets.all(compact ? t.space.md : t.space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: bubble,
            height: bubble,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: t.colors.surfaceSunken, shape: BoxShape.circle),
            child: DEmoji(emoji, size: bubble * 0.52),
          ),
          SizedBox(height: t.space.md),
          Text(title, style: compact ? t.text.label : t.text.title, textAlign: TextAlign.center),
          if (message != null) ...[
            SizedBox(height: t.space.xs),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 480 * t.scale),
              child: Text(message!, style: t.text.caption, textAlign: TextAlign.center),
            ),
          ],
          if (action != null) ...[SizedBox(height: t.space.lg), action!],
        ],
      ),
    );
    return id == null ? content : tid(id!, content);
  }
}

/// A static placeholder block (no shimmer: ambient motion is costly on T1).
class DSkeleton extends StatelessWidget {
  const DSkeleton({super.key, this.width, this.height, this.radius});
  final double? width;
  final double? height;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Container(
      width: width,
      height: height ?? 20 * t.scale,
      decoration: BoxDecoration(color: t.colors.surfaceSunken, borderRadius: BorderRadius.circular(radius ?? t.radius.s)),
    );
  }
}

// ─────────────────────────────── PIN pad ───────────────────────────────────

/// Numeric PIN entry for grown-up mode (SPEC §9.3). [onSubmit] returns
/// whether the PIN was accepted; wrong PINs shake and clear.
class DPinPad extends StatefulWidget {
  const DPinPad({super.key, required this.onSubmit, this.length = 4, this.title, this.subtitle, this.lockedUntil});
  final Future<bool> Function(String pin) onSubmit;
  final int length;
  final String? title;
  final String? subtitle;
  final DateTime? lockedUntil;

  @override
  State<DPinPad> createState() => _DPinPadState();
}

class _DPinPadState extends State<DPinPad> with SingleTickerProviderStateMixin {
  String _pin = '';
  bool _busy = false;
  bool _error = false;
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  Future<void> _press(String key) async {
    if (_busy) return;
    if (widget.lockedUntil != null && widget.lockedUntil!.isAfter(DateTime.now())) return;
    setState(() {
      _error = false;
      if (key == '⌫') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < widget.length) {
        _pin += key;
      }
    });
    if (_pin.length == widget.length) {
      setState(() => _busy = true);
      final ok = await widget.onSubmit(_pin);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _pin = '';
        _error = !ok;
      });
      if (!ok) await _shake.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final c = t.colors;
    final key = 76 * t.scale;
    final locked = widget.lockedUntil != null && widget.lockedUntil!.isAfter(DateTime.now());
    Widget digit(String d) => Padding(
          padding: EdgeInsets.all(t.space.xs),
          child: DPressable(
            id: 'pin.key.${d == '⌫' ? 'back' : d}',
            onTap: () => _press(d),
            semanticLabel: d == '⌫' ? 'Delete' : d,
            borderRadius: BorderRadius.circular(key),
            pressedScale: 0.9,
            child: Container(
              width: key,
              height: key,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: d == '⌫' ? Colors.transparent : c.surfaceSunken, shape: BoxShape.circle),
              child: d == '⌫'
                  ? Icon(Icons.backspace_outlined, size: t.iconMd, color: c.inkSecondary)
                  : Text(d, style: t.text.h2.copyWith(fontWeight: FontWeight.w600)),
            ),
          ),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.title != null) Text(widget.title!, style: t.text.h2, textAlign: TextAlign.center),
        if (widget.subtitle != null) ...[SizedBox(height: t.space.xs), Text(widget.subtitle!, style: t.text.caption, textAlign: TextAlign.center)],
        SizedBox(height: t.space.lg),
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) {
            final v = _shake.value;
            final dx = v == 0 ? 0.0 : 14 * t.scale * (1 - v) * ((v * 12).floor().isEven ? 1 : -1);
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: tid(
            'pin.dots',
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < widget.length; i++)
                  AnimatedContainer(
                    duration: DMotion.fast,
                    margin: EdgeInsets.symmetric(horizontal: t.space.xs),
                    width: 20 * t.scale,
                    height: 20 * t.scale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _error ? c.danger : (i < _pin.length ? c.accent : Colors.transparent),
                      border: Border.all(color: _error ? c.danger : (i < _pin.length ? c.accent : c.outline), width: 2.5 * t.scale),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(height: t.space.sm),
        SizedBox(
          height: 24 * t.scale,
          child: Text(
            locked ? 'Too many tries — wait a moment' : (_error ? 'That PIN didn’t match' : ''),
            style: t.text.caption.copyWith(color: c.danger),
          ),
        ),
        SizedBox(height: t.space.sm),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['', '0', '⌫'],
        ])
          Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) d.isEmpty ? SizedBox(width: key + t.space.md) : digit(d)]),
      ],
    );
  }
}

// ─────────────────────────────── Text field ────────────────────────────────

/// A labeled text field using the token input styles.
class DTextField extends StatelessWidget {
  const DTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.id,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.keyboardType,
    this.obscure = false,
    this.maxLines = 1,
    this.prefix,
    this.suffix,
    this.textInputAction,
    this.focusNode,
    this.errorText,
    this.big = false,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? id;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final TextInputType? keyboardType;
  final bool obscure;
  final int maxLines;
  final Widget? prefix;
  final Widget? suffix;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final String? errorText;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      keyboardType: keyboardType,
      obscureText: obscure,
      maxLines: obscure ? 1 : maxLines,
      minLines: 1,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: textInputAction,
      style: big ? t.text.title : t.text.body,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: prefix,
        suffixIcon: suffix,
        errorText: errorText,
        isDense: !big,
      ),
    );
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[Text(label!, style: t.text.label.copyWith(color: t.colors.inkSecondary)), SizedBox(height: t.space.xs)],
        field,
      ],
    );
    return id == null ? column : Semantics(identifier: id, container: true, child: column);
  }
}
