import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/grown_up.dart';
import '../../core/data/household.dart';
import '../../core/data/household_data.dart';
import '../../core/providers.dart';

/// Lists (SPEC FR-LIST-01): master–detail on wide screens, list → detail on
/// phones. Shopping lists group by aisle (FR-SHOP-04).
class ListsScreen extends ConsumerWidget {
  const ListsScreen({super.key, this.listId});
  final String? listId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final lists = ref.watch(listsProvider).value ?? const <DList>[];
    final wide = !t.isPhone && MediaQuery.sizeOf(context).width >= 1000 * t.scale;
    final selected = listId ?? (wide ? lists.firstOrNull?.id : null);

    if (!wide && selected != null) {
      return screenTid('screen.list', Padding(padding: EdgeInsets.all(t.pageMargin), child: ListDetail(listId: selected, showBack: true)));
    }
    final overview = _ListOverview(lists: lists, selected: wide ? selected : null);
    if (!wide) return screenTid('screen.lists', Padding(padding: EdgeInsets.all(t.pageMargin), child: overview));
    return screenTid(
      'screen.lists',
      Padding(
        padding: EdgeInsets.all(t.pageMargin),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 380 * t.scale, child: overview),
            SizedBox(width: t.gutter),
            Expanded(
              child: selected == null
                  ? const DEmptyState(emoji: '📋', title: 'No lists yet', message: 'Create one to get started.')
                  : DCard(padding: EdgeInsets.all(t.space.lg), child: ListDetail(listId: selected, key: ValueKey(selected))),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListOverview extends ConsumerWidget {
  const _ListOverview({required this.lists, this.selected});
  final List<DList> lists;
  final String? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final counts = ref.watch(openItemCountsProvider).value ?? const <String, int>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DPageHeader(
          title: 'Lists',
          actions: [
            DIconButton(icon: Icons.add_rounded, label: 'New list', id: 'lists.new', tone: DButtonTone.tonal, onPressed: () => _newList(context, ref)),
          ],
        ),
        SizedBox(height: t.space.md),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (final l in lists)
                Padding(
                  padding: EdgeInsets.only(bottom: t.space.xs),
                  child: DPressable(
                    id: 'lists.item.${l.id}',
                    selected: l.id == selected,
                    semanticLabel: '${l.title}${(counts[l.id] ?? 0) > 0 ? ', ${counts[l.id]} open' : ''}',
                    excludeSemantics: true,
                    onTap: () => context.go('/lists/${l.id}'),
                    borderRadius: t.radius.card,
                    child: AnimatedContainer(
                      duration: DMotion.fast,
                      padding: EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
                      decoration: BoxDecoration(
                        color: l.id == selected ? t.colors.accentTint : t.colors.surfaceRaised,
                        borderRadius: t.radius.card,
                        border: Border.all(color: l.id == selected ? t.colors.accent.withValues(alpha: 0.4) : t.colors.outline),
                      ),
                      child: Row(
                        children: [
                          DEmoji(l.icon ?? '📋', size: 36 * t.scale),
                          SizedBox(width: t.space.sm),
                          Expanded(child: Text(l.title, style: t.text.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis)),
                          if ((counts[l.id] ?? 0) > 0)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: t.space.xs, vertical: 2 * t.scale),
                              decoration: BoxDecoration(color: t.colors.surfaceSunken, borderRadius: t.radius.pill),
                              child: Text('${counts[l.id]}', style: t.text.label.copyWith(fontWeight: FontWeight.w800)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _newList(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    var emoji = '📋';
    final created = await showDSheet<bool>(
      context,
      title: 'New list',
      id: 'lists.new.sheet',
      builder: (sheet) => StatefulBuilder(builder: (context, setState) {
        final t = DTheme.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DTextField(id: 'lists.new.name', controller: name, hint: 'Packing for the beach', autofocus: true, big: true, onSubmitted: (_) => Navigator.of(sheet).pop(true)),
            SizedBox(height: t.space.md),
            Wrap(
              spacing: t.space.xs,
              runSpacing: t.space.xs,
              children: [
                for (final e in const ['📋', '🛒', '✅', '🎒', '🧳', '🏖️', '🎁', '🧹', '🔧', '📚', '🎄', '💊'])
                  DChip(label: '', emoji: e, selected: emoji == e, onTap: () => setState(() => emoji = e)),
              ],
            ),
            SizedBox(height: t.space.lg),
            DButton(label: 'Create list', id: 'lists.new.create', expand: true, onPressed: () => Navigator.of(sheet).pop(true)),
          ],
        );
      }),
    );
    final title = name.text.trim();
    name.dispose();
    if (created != true || title.isEmpty) return;
    final lists = ref.read(listsProvider).value ?? const <DList>[];
    final id = await ref.read(writerProvider).create('lists', {
      'title': title,
      'icon': emoji,
      'kind': 'custom',
      'sort_key': sortKeyAfter(lists.lastOrNull?.sortKey),
    });
    if (context.mounted) context.go('/lists/$id');
  }
}

/// One list: add field, open items (grouped by aisle for shopping), done items.
class ListDetail extends ConsumerStatefulWidget {
  const ListDetail({super.key, required this.listId, this.showBack = false});
  final String listId;
  final bool showBack;

  @override
  ConsumerState<ListDetail> createState() => _ListDetailState();
}

class _ListDetailState extends ConsumerState<ListDetail> {
  final _add = TextEditingController();
  final _focus = FocusNode();
  bool _showDone = false;

  @override
  void dispose() {
    _add.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _addItem(DList list, List<ListItem> items) async {
    final text = _add.text.trim();
    if (text.isEmpty) return;
    final aisle = list.kind == 'shopping' ? parseIngredientLine(text).aisle : null;
    final last = items.where((i) => !i.checked).map((i) => i.sortKey).fold<String?>(null, (a, b) => a == null || b.compareTo(a) > 0 ? b : a);
    await ref.read(writerProvider).create('list_items', {
      'list_id': list.id,
      'text': text,
      'category': aisle?.name,
      'sort_key': sortKeyAfter(last),
    });
    _add.clear();
    _focus.requestFocus();
  }

  Future<void> _toggle(ListItem i) async {
    final now = ref.read(appClockProvider).nowMs();
    await ref.read(writerProvider).upsert('list_items', i.id, {'checked': !i.checked, 'checked_ms': i.checked ? null : now});
  }

  Future<void> _delete(ListItem i) async {
    final w = ref.read(writerProvider);
    await w.delete('list_items', i.id);
    ref.read(toastProvider).show('Removed “${i.itemText}”', emoji: '🗑️', actionLabel: 'Undo', onAction: () => w.upsert('list_items', i.id, {'deleted': false}));
  }

  Future<void> _clearDone(List<ListItem> done) async {
    final ok = await confirmDialog(context, title: 'Clear ${done.length} checked ${done.length == 1 ? 'item' : 'items'}?', confirmLabel: 'Clear', emoji: '🧹');
    if (!ok) return;
    final w = ref.read(writerProvider);
    await w.commit([for (final i in done) w.op('list_items', i.id, const {}, kind: OpKind.delete)]);
  }

  Future<void> _deleteList(DList list) async {
    if (!await ensureGrownUp(context, ref, reason: 'Deleting a list needs a grown-up')) return;
    if (!mounted) return;
    final ok = await confirmDialog(context, title: 'Delete “${list.title}”?', message: 'Everything on it goes too.', confirmLabel: 'Delete', danger: true);
    if (!ok || !mounted) return;
    await ref.read(writerProvider).delete('lists', list.id);
    if (mounted) context.go('/lists');
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final c = t.colors;
    final list = (ref.watch(listsProvider).value ?? const <DList>[]).where((l) => l.id == widget.listId).firstOrNull;
    final items = ref.watch(listItemsProvider(widget.listId)).value ?? const <ListItem>[];
    if (list == null) return const Center(child: DEmptyState(emoji: '🔎', title: 'List not found'));
    final open = [for (final i in items) if (!i.checked) i];
    final done = [for (final i in items) if (i.checked) i];
    final people = ref.watch(profileMapProvider);
    final shopping = list.kind == 'shopping';

    final rows = <Widget>[];
    if (shopping) {
      final groups = <Aisle, List<ListItem>>{};
      for (final i in open) {
        groups.putIfAbsent(Aisle.parse(i.category), () => []).add(i);
      }
      final aisles = groups.keys.toList()..sort((a, b) => a.index.compareTo(b.index));
      for (final a in aisles) {
        rows.add(Padding(
          padding: EdgeInsets.only(top: t.space.sm, bottom: t.space.xxs),
          child: Row(children: [DEmoji(a.emoji, size: 22 * t.scale), SizedBox(width: t.space.xs), Text(a.label.toUpperCase(), style: t.text.overline)]),
        ));
        rows.addAll([for (final i in groups[a]!) _ItemRow(item: i, people: people, onToggle: () => _toggle(i), onDelete: () => _delete(i))]);
      }
    } else {
      rows.addAll([for (final i in open) _ItemRow(item: i, people: people, onToggle: () => _toggle(i), onDelete: () => _delete(i))]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (widget.showBack) ...[
              DIconButton(icon: Icons.arrow_back_rounded, label: 'All lists', id: 'list.back', tone: DButtonTone.ghost, onPressed: () => context.go('/lists')),
              SizedBox(width: t.space.xs),
            ],
            DEmoji(list.icon ?? '📋', size: 44 * t.scale),
            SizedBox(width: t.space.sm),
            Expanded(child: tid('list.title', Text(list.title, style: t.text.h2, maxLines: 1, overflow: TextOverflow.ellipsis))),
            Text(open.isEmpty ? 'All done' : '${open.length} to go', style: t.text.caption),
            if (list.id != Ids.shoppingList && list.id != Ids.todoList) ...[
              SizedBox(width: t.space.xs),
              DIconButton(icon: Icons.delete_outline_rounded, label: 'Delete list', id: 'list.delete', tone: DButtonTone.ghost, onPressed: () => _deleteList(list)),
            ],
          ],
        ),
        SizedBox(height: t.space.md),
        DTextField(
          id: 'list.add',
          controller: _add,
          focusNode: _focus,
          hint: shopping ? 'Add milk, 2 lb chicken…' : 'Add an item',
          prefix: Icon(Icons.add_rounded, color: c.accent),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _addItem(list, items),
          suffix: Padding(
            padding: EdgeInsets.all(t.space.xxs),
            child: DButton(label: 'Add', size: DButtonSize.sm, id: 'list.add.button', onPressed: () => _addItem(list, items)),
          ),
        ),
        SizedBox(height: t.space.sm),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              if (open.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: t.space.lg),
                  child: DEmptyState(emoji: shopping ? '🛒' : '✨', title: shopping ? 'Nothing to buy' : 'All clear', compact: true),
                ),
              ...rows,
              if (done.isNotEmpty) ...[
                SizedBox(height: t.space.md),
                Row(
                  children: [
                    DPressable(
                      id: 'list.done.toggle',
                      onTap: () => setState(() => _showDone = !_showDone),
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: t.space.xs),
                        child: Row(
                          children: [
                            Icon(_showDone ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: c.inkSecondary),
                            Text('Checked (${done.length})', style: t.text.label.copyWith(color: c.inkSecondary)),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    DButton(label: 'Clear', tone: DButtonTone.ghost, size: DButtonSize.sm, id: 'list.clear', onPressed: () => _clearDone(done)),
                  ],
                ),
                if (_showDone)
                  for (final i in done) _ItemRow(item: i, people: people, onToggle: () => _toggle(i), onDelete: () => _delete(i)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.people, required this.onToggle, required this.onDelete});
  final ListItem item;
  final Map<String, Profile> people;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final c = t.colors;
    final who = item.assigneeProfileId == null ? null : people[item.assigneeProfileId];
    return DPressable(
      id: 'list.item.${item.id}',
      semanticLabel: '${item.itemText}${item.checked ? ', done' : ''}',
      selected: item.checked,
      excludeSemantics: true,
      onTap: onToggle,
      onLongPress: onDelete,
      borderRadius: t.radius.card,
      pressedScale: 0.99,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: t.space.touch),
        child: Row(
          children: [
            AnimatedContainer(
              duration: DMotion.fast,
              width: 32 * t.scale,
              height: 32 * t.scale,
              margin: EdgeInsets.symmetric(horizontal: t.space.xs),
              decoration: BoxDecoration(
                color: item.checked ? c.success : Colors.transparent,
                borderRadius: BorderRadius.circular(10 * t.scale),
                border: Border.all(color: item.checked ? c.success : c.inkTertiary, width: 2.5 * t.scale),
              ),
              child: item.checked ? Icon(Icons.check_rounded, size: 22 * t.scale, color: Colors.white) : null,
            ),
            SizedBox(width: t.space.sm),
            Expanded(
              child: Text(
                item.itemText,
                style: t.text.body.copyWith(
                  color: item.checked ? c.inkTertiary : c.inkPrimary,
                  decoration: item.checked ? TextDecoration.lineThrough : null,
                  decorationColor: c.inkTertiary,
                ),
              ),
            ),
            if (item.note != null) Padding(padding: EdgeInsets.only(left: t.space.xs), child: Text(item.note!, style: t.text.caption)),
            if (who != null) ...[SizedBox(width: t.space.xs), DAvatar(colorIndex: who.color, emoji: who.emoji, name: who.name, size: 32 * t.scale)],
            SizedBox(width: t.space.xs),
          ],
        ),
      ),
    );
  }
}
