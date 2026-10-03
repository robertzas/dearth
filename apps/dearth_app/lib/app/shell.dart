import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/data/household.dart';
import '../core/providers.dart';
import '../core/sync/sync_client.dart';
import '../features/calendar/quick_add.dart';
import 'destinations.dart';
import 'display_state.dart';
import 'grown_up.dart';
import 'kiosk.dart';

/// The navigation chrome around every destination (SPEC §11.2): a left rail
/// on landscape walls and tablets, a bottom bar on portrait walls, and the
/// companion bar (Today · Calendar · Add · Lists · More) on phones.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell, required this.children});

  final StatefulNavigationShell shell;
  final List<Widget> children;

  void _go(int index) => shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final size = MediaQuery.sizeOf(context);
    final keepRecent = ref.watch(perfTierProvider) != PerfTier.t1;
    final body = _BranchStack(current: shell.currentIndex, keepRecent: keepRecent, children: children);
    final landscape = size.width > size.height;

    if (t.displayClass == DisplayClass.phone) {
      return Scaffold(
        body: SafeArea(bottom: false, child: body),
        bottomNavigationBar: _PhoneBar(current: shell.currentIndex, onSelect: _go),
      );
    }
    if (t.displayClass == DisplayClass.wallL || (t.displayClass == DisplayClass.tablet && landscape)) {
      return Scaffold(
        body: Row(
          children: [
            _NavRail(current: shell.currentIndex, onSelect: _go),
            Expanded(child: SafeArea(left: false, child: body)),
          ],
        ),
      );
    }
    return Scaffold(
      body: SafeArea(bottom: false, child: body),
      bottomNavigationBar: _BottomBar(current: shell.currentIndex, onSelect: _go),
    );
  }
}

/// Branch container with an explicit keep-alive budget: Home and the current
/// destination always (plus the previous one on T2+); everything else is
/// disposed. Offstage branches run with tickers off.
class _BranchStack extends StatefulWidget {
  const _BranchStack({required this.current, required this.children, required this.keepRecent});
  final int current;
  final List<Widget> children;
  final bool keepRecent;

  @override
  State<_BranchStack> createState() => _BranchStackState();
}

class _BranchStackState extends State<_BranchStack> with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(vsync: this, duration: DMotion.standard, value: 1);
  int? _previous;
  static const _still = AlwaysStoppedAnimation<double>(1);

  @override
  void didUpdateWidget(_BranchStack old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) {
      _previous = old.current;
      _fade.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keep = {0, widget.current, if (widget.keepRecent && _previous != null) _previous!};
    final curved = CurvedAnimation(parent: _fade, curve: DMotion.standardCurve);
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          if (keep.contains(i))
            Offstage(
              key: ValueKey('branch-$i'),
              offstage: i != widget.current,
              child: TickerMode(
                enabled: i == widget.current,
                child: FadeTransition(opacity: i == widget.current ? curved : _still, child: widget.children[i]),
              ),
            ),
      ],
    );
  }
}

// ──────────────────────────────── Rail ──────────────────────────────────────

class _NavRail extends ConsumerWidget {
  const _NavRail({required this.current, required this.onSelect});
  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final c = t.colors;
    return Container(
      width: 104 * t.scale,
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        border: Border(right: BorderSide(color: c.outline)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            SizedBox(height: t.space.md),
            const KioskClockTarget(),
            SizedBox(height: t.space.md),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final (i, d) in kDestinations.indexed)
                      _RailItem(destination: d, selected: i == current, onTap: () => onSelect(i)),
                  ],
                ),
              ),
            ),
            const _SyncDot(),
            const _LockButton(),
            _RailAction(
              icon: Icons.photo_rounded,
              label: 'Frame',
              id: 'nav.screensaver',
              onTap: () => ref.read(displayProvider.notifier).startScreensaver(),
            ),
            SizedBox(height: t.space.md),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({required this.destination, required this.selected, required this.onTap});
  final Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final c = t.colors;
    return DPressable(
      id: 'nav.${destination.id}',
      onTap: onTap,
      selected: selected,
      semanticLabel: destination.label,
      excludeSemantics: true,
      borderRadius: t.radius.card,
      pressedScale: 0.94,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: t.space.xs),
        child: Column(
          children: [
            AnimatedContainer(
              duration: t.motion(DMotion.fast),
              curve: DMotion.standardCurve,
              width: 64 * t.scale,
              height: 40 * t.scale,
              decoration: BoxDecoration(color: selected ? c.accentTint : Colors.transparent, borderRadius: t.radius.pill),
              child: Icon(selected ? destination.activeIcon : destination.icon, size: t.iconMd, color: selected ? c.accent : c.inkSecondary),
            ),
            SizedBox(height: t.space.xxs),
            Text(
              destination.label,
              style: t.text.caption.copyWith(
                fontSize: 14 * t.scale,
                color: selected ? c.inkPrimary : c.inkSecondary,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailAction extends StatelessWidget {
  const _RailAction({required this.icon, required this.label, required this.onTap, this.id, this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? id;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return DPressable(
      id: id,
      onTap: onTap,
      semanticLabel: label,
      excludeSemantics: true,
      borderRadius: t.radius.card,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: t.space.xs, horizontal: t.space.xs),
        child: Column(
          children: [
            Icon(icon, size: t.iconSm, color: color ?? t.colors.inkSecondary),
            SizedBox(height: 2 * t.scale),
            Text(label, style: t.text.caption.copyWith(fontSize: 13 * t.scale, color: color ?? t.colors.inkSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Grown-up lock state (SPEC FR-HOME-04): hidden when no PINs are set.
class _LockButton extends ConsumerWidget {
  const _LockButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlocked = ref.watch(grownUpUnlockedProvider);
    if (unlocked == null || ref.watch(deviceSettingsProvider.select((s) => s.isPersonal))) return const SizedBox.shrink();
    final t = DTheme.of(context);
    return _RailAction(
      id: 'nav.lock',
      icon: unlocked ? Icons.lock_open_rounded : Icons.lock_rounded,
      label: unlocked ? 'Unlocked' : 'Locked',
      color: unlocked ? t.colors.warning : null,
      onTap: () => unlocked ? ref.read(grownUpProvider.notifier).lock() : ensureGrownUp(context, ref),
    );
  }
}

/// Shown only when sync is degraded (SPEC FR-HOME-04: subtle).
class _SyncDot extends ConsumerWidget {
  const _SyncDot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(syncStateProvider).value;
    if (state == null || state.isHealthy) return const SizedBox.shrink();
    final t = DTheme.of(context);
    final (label, color) = syncLabel(state, t.colors);
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.xs),
      child: tid(
        'nav.sync',
        Tooltip(
          message: label,
          child: Column(
            children: [
              Icon(Icons.cloud_off_rounded, size: t.iconSm, color: color),
              Text(label.split(' ').first, style: t.text.caption.copyWith(fontSize: 12 * t.scale, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

(String, Color) syncLabel(SyncState s, DColors c) => switch (s.phase) {
      SyncPhase.connecting => ('Connecting…', c.inkSecondary),
      SyncPhase.bootstrapping => ('Downloading…', c.inkSecondary),
      SyncPhase.catchingUp => ('Syncing…', c.inkSecondary),
      SyncPhase.offline => ('Offline', c.warning),
      SyncPhase.unauthorized => ('Unpaired', c.danger),
      SyncPhase.upgradeRequired => ('Update needed', c.danger),
      SyncPhase.live || SyncPhase.idle => ('Synced', c.success),
    };

// ──────────────────────────── Bottom bars ───────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.current, required this.onSelect});
  final int current;
  final ValueChanged<int> onSelect;

  static const _primary = ['home', 'calendar', 'meals', 'lists'];

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final items = [for (final id in _primary) destinationIndex(id)];
    final inMore = !items.contains(current);
    return _BarFrame(
      children: [
        for (final i in items)
          _BarItem(destination: kDestinations[i], selected: i == current, onTap: () => onSelect(i)),
        _BarButton(
          id: 'nav.more',
          icon: Icons.more_horiz_rounded,
          label: 'More',
          selected: inMore,
          onTap: () => _showMore(context, onSelect, exclude: items.toSet()),
        ),
        SizedBox(width: t.space.xs),
      ],
    );
  }
}

class _PhoneBar extends ConsumerWidget {
  const _PhoneBar({required this.current, required this.onSelect});
  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final home = destinationIndex('home'), cal = destinationIndex('calendar'), lists = destinationIndex('lists');
    final inMore = !{home, cal, lists}.contains(current);
    return _BarFrame(
      children: [
        _BarItem(destination: kDestinations[home], selected: current == home, onTap: () => onSelect(home), phone: true),
        _BarItem(destination: kDestinations[cal], selected: current == cal, onTap: () => onSelect(cal), phone: true),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space.xs),
          child: DIconButton(
            icon: Icons.add_rounded,
            label: 'Add',
            id: 'nav.add',
            tone: DButtonTone.primary,
            size: 56 * t.scale,
            onPressed: () => showQuickAdd(context),
          ),
        ),
        _BarItem(destination: kDestinations[lists], selected: current == lists, onTap: () => onSelect(lists), phone: true),
        _BarButton(
          id: 'nav.more',
          icon: Icons.menu_rounded,
          label: 'More',
          selected: inMore,
          onTap: () => _showMore(context, onSelect, exclude: {home, cal, lists}),
        ),
      ],
    );
  }
}

class _BarFrame extends StatelessWidget {
  const _BarFrame({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: t.colors.surfaceRaised, border: Border(top: BorderSide(color: t.colors.outline))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: (t.isPhone ? 72 : 88) * t.scale,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: children),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({required this.destination, required this.selected, required this.onTap, this.phone = false});
  final Destination destination;
  final bool selected;
  final VoidCallback onTap;
  final bool phone;

  @override
  Widget build(BuildContext context) => _BarButton(
        id: 'nav.${destination.id}',
        icon: selected ? destination.activeIcon : destination.icon,
        label: phone ? (destination.phoneLabel ?? destination.label) : destination.label,
        selected: selected,
        onTap: onTap,
      );
}

class _BarButton extends StatelessWidget {
  const _BarButton({required this.icon, required this.label, required this.selected, required this.onTap, this.id});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? id;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final c = t.colors;
    return Expanded(
      child: DPressable(
        id: id,
        onTap: onTap,
        selected: selected,
        semanticLabel: label,
        excludeSemantics: true,
        pressedScale: 0.94,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: t.motion(DMotion.fast),
              width: 56 * t.scale,
              height: 32 * t.scale,
              decoration: BoxDecoration(color: selected ? c.accentTint : Colors.transparent, borderRadius: t.radius.pill),
              child: Icon(icon, size: t.iconSm * 1.1, color: selected ? c.accent : c.inkSecondary),
            ),
            SizedBox(height: 2 * t.scale),
            Text(label, style: t.text.caption.copyWith(fontSize: 13 * t.scale, color: selected ? c.inkPrimary : c.inkSecondary, fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

void _showMore(BuildContext context, ValueChanged<int> onSelect, {required Set<int> exclude}) {
  showDSheet<void>(
    context,
    title: 'More',
    id: 'nav.more.sheet',
    builder: (sheetContext) {
      final t = DTheme.of(sheetContext);
      return Column(
        children: [
          for (final (i, d) in kDestinations.indexed)
            if (!exclude.contains(i))
              DListRow(
                id: 'more.${d.id}',
                title: d.label,
                leading: Icon(d.activeIcon, color: t.colors.accent, size: t.iconMd),
                chevron: true,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onSelect(i);
                },
              ),
        ],
      );
    },
  );
}
