import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/grown_up.dart';
import '../../../core/data/household.dart';
import '../../../core/data/household_data.dart';
import '../../../core/format.dart';
import '../../../core/providers.dart';
import '../../../shared/pickers.dart';
import '../../calendar/event_editor.dart' show pickEmoji;
import '../../kids/kids_data.dart';
import '../../kids/kids_setup.dart';
import '../settings_screen.dart';

/// Pictures for chores, routine steps and rewards.
const List<String> kKidEmojiChoices = [
  '🧸', '👟', '🧺', '🐶', '🍽️', '📚', '🧽', '🪴', '🧻', '🧦', '👕', '🛏️', '🖍️', '💧', '🍴', '🧼', //
  '👗', '🎒', '🛒', '🪶', '🚽', '🪥', '🛁', '🩳', '📖', '🤗', '🥣', '🧥', '🥤', '🎵', '🙌', '🌞', //
  '🌙', '🧹', '🗑️', '🐱', '🐟', '🌱', '🍎', '🥕', '🚗', '🎨', '🧩', '⚽', '🎹', '🎁', '⭐', '🏆', //
  '🛝', '🥞', '🍿', '🍕', '🦁', '⛺', '💃', '🧁', '🎈', '🍦',
];

/// Kids & chores (SPEC FR-KID-01/04/06/11/13/14): chores with the age-sorted
/// library, routines from templates, rewards, and each kid's jar, sticker
/// theme and star goal. Every change needs a grown-up.
class KidsSection extends ConsumerWidget {
  const KidsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final chores = ref.watch(choresProvider).value ?? const <Chore>[];
    final routines = ref.watch(routinesProvider).value ?? const <Routine>[];
    final rewards = ref.watch(rewardsProvider).value ?? const <Reward>[];
    final people = ref.watch(profileMapProvider);
    final kids = ref.watch(kidsProvider);
    String who(List<String> ids) => ids.isEmpty ? 'Anyone' : ids.map((id) => people[id]?.name ?? '?').join(', ');
    final sorted = [...chores]..sort((a, b) {
        final c = (a.adult ? 1 : 0).compareTo(b.adult ? 1 : 0);
        return c != 0 ? c : who(decodeStringList(a.assignees)).compareTo(who(decodeStringList(b.assignees)));
      });
    Widget plus() => Container(
          width: 40 * t.scale,
          height: 40 * t.scale,
          decoration: BoxDecoration(color: t.colors.accentTint, shape: BoxShape.circle),
          child: Icon(Icons.add_rounded, color: t.colors.accent),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'Chores',
          footer: 'Kids’ chores show on their chart and on Home; grown-ups’ chores on the Grown-ups tab.',
          children: [
            for (final c in sorted)
              DListRow(
                id: 'chores.${c.id}',
                leading: DEmoji(c.emoji ?? '⭐', size: 32 * t.scale),
                title: c.title,
                subtitle: [who(decodeStringList(c.assignees)), describeSchedule(c.rrule), if (describeRewards(c).isNotEmpty) describeRewards(c)].join(' · '),
                chevron: true,
                onTap: () => editChore(context, ref, c),
              ),
            DListRow(id: 'chores.add', title: 'Add a chore', leading: plus(), onTap: () => editChore(context, ref, null)),
            if (kids.isNotEmpty)
              DListRow(
                id: 'chores.ideas',
                title: 'Chore ideas by age',
                subtitle: 'Picture chores little ones can really do',
                leading: SizedBox(width: 40 * t.scale, child: Center(child: DEmoji('💡', size: 28 * t.scale))),
                onTap: () => showChoreIdeas(context, ref),
              ),
          ],
        ),
        SettingsGroup(
          title: 'Routines',
          footer: 'Picture steps kids run themselves, with optional timers.',
          children: [
            for (final r in routines)
              DListRow(
                id: 'routines.${r.id}',
                leading: DEmoji(r.emoji ?? '🌟', size: 32 * t.scale),
                title: r.title,
                subtitle: [
                  '${decodeSteps(r.steps).length} steps',
                  who(decodeStringList(r.profileIds)),
                  describeSchedule(r.rrule),
                  if (r.startTime != null) r.startTime!,
                ].join(' · '),
                chevron: true,
                onTap: () => editRoutine(context, ref, r),
              ),
            DListRow(id: 'routines.add', title: 'Add a routine', leading: plus(), onTap: () => addRoutine(context, ref)),
          ],
        ),
        SettingsGroup(
          title: 'Rewards',
          footer: 'Star-store rewards cost stars; jar surprises are revealed when a jar fills; a family goal fills from everyone’s jobs.',
          children: [
            for (final r in rewards)
              DListRow(
                id: 'rewards.${r.id}',
                leading: DEmoji(r.emoji ?? '🎁', size: 32 * t.scale),
                title: r.title,
                subtitle: [RewardKind.parse(r.kind).label, if (r.kind != RewardKind.surprise.id) '${r.cost} ${r.kind == RewardKind.family.id ? 'jobs' : '⭐'}'].join(' · '),
                chevron: true,
                onTap: () => editReward(context, ref, r),
              ),
            DListRow(id: 'rewards.add', title: 'Add a reward', leading: plus(), onTap: () => addReward(context, ref)),
          ],
        ),
        SettingsGroup(
          title: 'Jar, stickers & goals',
          children: [
            DListRow(
              title: 'Reward jar size',
              subtitle: 'Pom-poms that fill a jar',
              trailing: DStepper(
                id: 'kids.jarsize',
                value: ref.watch(jarCapacityProvider),
                min: 3,
                max: 30,
                onChanged: (v) => _setSetting(context, ref, 'kids.jarSize', v),
              ),
            ),
            for (final kid in kids) ...[
              DListRow(
                id: 'kids.theme.${kid.id}',
                title: '${kid.name}’s sticker book',
                subtitle: kStickerThemes[ref.watch(stickerThemeProvider(kid.id))]!.$1,
                leading: DEmoji(kStickerThemes[ref.watch(stickerThemeProvider(kid.id))]!.$3.first, size: 32 * t.scale),
                chevron: true,
                onTap: () => _pickTheme(context, ref, kid),
              ),
              if (kid.kidStage != KidStage.little)
                DListRow(
                  id: 'kids.goal.${kid.id}',
                  title: '${kid.name}’s star goal',
                  subtitle: ref.watch(kidGoalProvider(kid.id))?.title ?? 'Add a star-store reward first',
                  leading: DEmoji(ref.watch(kidGoalProvider(kid.id))?.emoji ?? '⭐', size: 32 * t.scale),
                  chevron: true,
                  onTap: () => _pickGoal(context, ref, kid),
                ),
            ],
          ],
        ),
      ],
    );
  }

  static Future<void> _setSetting(BuildContext context, WidgetRef ref, String key, Object? value) async {
    if (!await ensureGrownUp(context, ref, reason: 'Kids’ settings need a grown-up')) return;
    final w = ref.read(writerProvider);
    await w.commit([settingOp(w, key, value)]);
  }

  static Future<void> _pickTheme(BuildContext context, WidgetRef ref, Profile kid) async {
    final id = await showDSheet<String>(
      context,
      id: 'kids.theme.sheet',
      title: '${kid.name}’s sticker book',
      builder: (sheet) {
        final t = DTheme.of(sheet);
        return Column(
          children: [
            for (final MapEntry(key: id, value: (name, _, stickers)) in kStickerThemes.entries)
              DListRow(
                id: 'kids.theme.pick.$id',
                title: name,
                trailing: Text(stickers.take(5).join(' '), style: t.text.title),
                onTap: () => Navigator.of(sheet).pop(id),
              ),
          ],
        );
      },
    );
    if (id != null && context.mounted) await _setSetting(context, ref, 'kids.stickerTheme.${kid.id}', id);
  }

  static Future<void> _pickGoal(BuildContext context, WidgetRef ref, Profile kid) async {
    final store = [for (final r in ref.read(rewardsProvider).value ?? const <Reward>[]) if (r.kind == RewardKind.store.id) r];
    if (store.isEmpty) {
      ref.read(toastProvider).show('Add a star-store reward first', emoji: '⭐');
      return;
    }
    final id = await showDSheet<String>(
      context,
      id: 'kids.goal.sheet',
      title: '${kid.name}’s star goal',
      builder: (sheet) => Column(
        children: [
          for (final r in store)
            DListRow(
              id: 'kids.goal.pick.${r.id}',
              leading: DEmoji(r.emoji ?? '🎁', size: 32 * DTheme.of(sheet).scale),
              title: r.title,
              subtitle: '${r.cost} ⭐',
              onTap: () => Navigator.of(sheet).pop(r.id),
            ),
        ],
      ),
    );
    if (id != null && context.mounted) await _setSetting(context, ref, 'kids.goal.${kid.id}', id);
  }
}

/// Section label inside an editor.
class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: t.space.md, bottom: t.space.xs),
      child: Text(text.toUpperCase(), style: t.text.overline.copyWith(color: t.colors.inkSecondary)),
    );
  }
}

/// The emoji button at the start of an editor's title row.
class _EmojiButton extends StatelessWidget {
  const _EmojiButton({required this.emoji, required this.id, required this.onPick});
  final String emoji;
  final String id;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return DPressable(
      id: id,
      semanticLabel: 'Picture $emoji',
      excludeSemantics: true,
      borderRadius: t.radius.card,
      onTap: () async {
        final e = await pickEmoji(context, choices: kKidEmojiChoices, title: 'Pick a picture');
        if (e != null) onPick(e);
      },
      child: Container(
        width: 64 * t.scale,
        height: 64 * t.scale,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: t.colors.surfaceSunken, borderRadius: t.radius.card),
        child: DEmoji(emoji, size: 40 * t.scale),
      ),
    );
  }
}

/// Schedule picker shared by chores and routines.
class _SchedulePicker extends StatelessWidget {
  const _SchedulePicker({required this.kind, required this.days, required this.idPrefix, required this.onChanged});
  final ScheduleKind kind;
  final Set<int> days;
  final String idPrefix;
  final void Function(ScheduleKind kind, Set<int> days) onChanged;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DSegmented<ScheduleKind>(
            options: [for (final k in ScheduleKind.values) if (k != ScheduleKind.custom || kind == ScheduleKind.custom) (k, k.label)],
            value: kind,
            dense: true,
            idPrefix: idPrefix,
            onChanged: (k) => onChanged(k, k == ScheduleKind.days && days.isEmpty ? {DateTime.monday} : days),
          ),
        ),
        if (kind == ScheduleKind.days) ...[
          SizedBox(height: t.space.xs),
          Wrap(
            spacing: t.space.xxs,
            runSpacing: t.space.xxs,
            children: [
              for (var d = 1; d <= 7; d++)
                DChip(
                  label: kWeekdayShort[d - 1],
                  selected: days.contains(d),
                  dense: true,
                  id: '$idPrefix.day.$d',
                  onTap: () => onChanged(kind, days.contains(d) ? ({...days}..remove(d)) : {...days, d}),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// ──────────────────────────────── Chores ───────────────────────────────────

Future<void> editChore(BuildContext context, WidgetRef ref, Chore? chore) async {
  if (!await ensureGrownUp(context, ref, reason: 'Changing chores needs a grown-up')) return;
  if (!context.mounted) return;
  await showDSheet<void>(context, id: 'chore.editor', title: chore == null ? 'New chore' : chore.title, builder: (_) => _ChoreEditor(chore: chore));
}

class _ChoreEditor extends ConsumerStatefulWidget {
  const _ChoreEditor({this.chore});
  final Chore? chore;

  @override
  ConsumerState<_ChoreEditor> createState() => _ChoreEditorState();
}

class _ChoreEditorState extends ConsumerState<_ChoreEditor> {
  late final _title = TextEditingController(text: widget.chore?.title ?? '');
  late final _voice = TextEditingController(text: widget.chore?.voiceLine ?? '');
  late String _emoji = widget.chore?.emoji ?? '⭐';
  late Set<String> _who = {...decodeStringList(widget.chore?.assignees)};
  late ScheduleKind _kind = scheduleOf(widget.chore?.rrule ?? 'FREQ=DAILY').$1;
  late Set<int> _days = scheduleOf(widget.chore?.rrule ?? 'FREQ=DAILY').$2;
  late String _window = widget.chore?.timeWindow ?? 'any';
  late int _stars = widget.chore?.stars ?? 1;
  late bool _jar = (widget.chore?.jar ?? 1) > 0;
  late bool _sticker = widget.chore?.sticker ?? true;
  late bool _approval = widget.chore?.needsApproval ?? false;
  late bool _anyoneAdult = widget.chore?.adult ?? false;

  @override
  void dispose() {
    _title.dispose();
    _voice.dispose();
    super.dispose();
  }

  bool _isAdultChore(Map<String, Profile> people) {
    if (_who.isEmpty) return _anyoneAdult;
    return _who.every((id) => people[id]?.role != ProfileRole.child);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ref.read(toastProvider).show('Give the chore a name', emoji: '✏️');
      return;
    }
    final people = ref.read(profileMapProvider);
    final w = ref.read(writerProvider);
    final c = widget.chore;
    await w.commit([
      w.op('chores', c?.id ?? newId(), choreFields(
        title: _title.text,
        emoji: _emoji,
        assignees: _who.toList(),
        rrule: scheduleRule(_kind, days: _days, custom: c?.rrule),
        window: _window,
        stars: _stars,
        jar: _jar,
        sticker: _sticker,
        needsApproval: _approval,
        adult: _isAdultChore(people),
        voiceLine: _voice.text,
        anchorDate: c?.anchorDate ?? ref.read(todayProvider).iso,
      )),
    ]);
    if (mounted) Navigator.of(context).maybePop();
    ref.read(toastProvider).show('Saved “${_title.text.trim()}”', emoji: _emoji);
  }

  Future<void> _delete() async {
    final c = widget.chore!;
    if (!await confirmDialog(context, title: 'Delete “${c.title}”?', message: 'Past stars and stickers stay.', confirmLabel: 'Delete', danger: true)) return;
    final w = ref.read(writerProvider);
    await w.delete('chores', c.id);
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final family = [for (final p in ref.watch(familyProvider)) if (p.role != ProfileRole.pet) p];
    final people = ref.watch(profileMapProvider);
    final adult = _isAdultChore(people);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _EmojiButton(emoji: _emoji, id: 'chore.emoji', onPick: (e) => setState(() => _emoji = e)),
            SizedBox(width: t.space.sm),
            Expanded(child: DTextField(id: 'chore.title', controller: _title, label: 'Chore', hint: 'Shoes in the basket')),
          ],
        ),
        const _Label('Who'),
        Wrap(
          spacing: t.space.xs,
          runSpacing: t.space.xs,
          children: [
            DChip(label: 'Anyone', emoji: '🙋', selected: _who.isEmpty, id: 'chore.who.anyone', onTap: () => setState(() => _who = {})),
            for (final p in family)
              DChip(
                label: p.name,
                emoji: p.emoji,
                personColor: PersonColors.of(p.color, t.colors),
                selected: _who.contains(p.id),
                id: 'chore.who.${p.id}',
                onTap: () => setState(() => _who.contains(p.id) ? _who.remove(p.id) : _who.add(p.id)),
              ),
          ],
        ),
        if (_who.isEmpty) DSwitchRow(id: 'chore.adult', title: 'A grown-ups’ chore', subtitle: 'Shows on the Grown-ups tab instead of kids’ charts', value: _anyoneAdult, onChanged: (v) => setState(() => _anyoneAdult = v)),
        const _Label('When'),
        _SchedulePicker(kind: _kind, days: _days, idPrefix: 'chore.schedule', onChanged: (k, d) => setState(() {
              _kind = k;
              _days = d;
            })),
        SizedBox(height: t.space.sm),
        DSegmented<String>(options: kTimeWindows, value: _window, dense: true, idPrefix: 'chore.window', onChanged: (v) => setState(() => _window = v)),
        if (!adult) ...[
          const _Label('Rewards'),
          DListRow(title: 'Stars', subtitle: 'For Preschool and up', trailing: DStepper(id: 'chore.stars', value: _stars, min: 0, max: 5, onChanged: (v) => setState(() => _stars = v))),
          DSwitchRow(id: 'chore.jar', title: 'A pom-pom for the jar', value: _jar, onChanged: (v) => setState(() => _jar = v)),
          DSwitchRow(id: 'chore.sticker', title: 'A sticker to place', value: _sticker, onChanged: (v) => setState(() => _sticker = v)),
          DSwitchRow(id: 'chore.approval', title: 'Needs a grown-up’s OK', subtitle: 'Rewards come after approval', value: _approval, onChanged: (v) => setState(() => _approval = v)),
          const _Label('Voice prompt'),
          DTextField(id: 'chore.voice', controller: _voice, hint: 'What to say, like “Shoes go in the basket!”'),
        ],
        SizedBox(height: t.space.lg),
        Row(
          children: [
            if (widget.chore != null) DButton(label: 'Delete', icon: Icons.delete_outline_rounded, tone: DButtonTone.ghost, id: 'chore.delete', onPressed: _delete),
            const Spacer(),
            DButton(label: 'Save', icon: Icons.check_rounded, id: 'chore.save', onPressed: _save),
          ],
        ),
      ],
    );
  }
}

/// The age-sorted chore library (SPEC FR-KID-04).
Future<void> showChoreIdeas(BuildContext context, WidgetRef ref) async {
  if (!await ensureGrownUp(context, ref, reason: 'Adding chores needs a grown-up')) return;
  if (!context.mounted) return;
  await showDSheet<void>(context, id: 'chores.ideas.sheet', title: 'Chore ideas', builder: (_) => const _ChoreIdeas());
}

class _ChoreIdeas extends ConsumerStatefulWidget {
  const _ChoreIdeas();

  @override
  ConsumerState<_ChoreIdeas> createState() => _ChoreIdeasState();
}

class _ChoreIdeasState extends ConsumerState<_ChoreIdeas> {
  String? _kidId;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final kids = ref.watch(kidsProvider);
    if (kids.isEmpty) return Text('Add a kid in People first.', style: t.text.body);
    final kid = kids.firstWhere((k) => k.id == _kidId, orElse: () => kids.first);
    final mine = [
      for (final c in ref.watch(choresProvider).value ?? const <Chore>[])
        if (decodeStringList(c.assignees).contains(kid.id)) c.title,
    ];
    final ideas = choreIdeasFor(ageOn(kid.birthday, ref.watch(todayProvider)), existingTitles: mine);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (kids.length > 1) ...[
          DSegmented<String>(options: [for (final k in kids) (k.id, k.name)], value: kid.id, idPrefix: 'chores.ideas.kid', onChanged: (v) => setState(() => _kidId = v)),
          SizedBox(height: t.space.sm),
        ],
        if (ideas.isEmpty) Text('${kid.name} has every chore for their age. 🌟', style: t.text.body),
        for (final (i, idea) in ideas.indexed)
          DListRow(
            id: 'chores.idea.$i',
            leading: DEmoji(idea.emoji, size: 32 * t.scale),
            title: idea.title,
            subtitle: 'Age ${idea.minAge % 1 == 0 ? idea.minAge.toInt() : idea.minAge}+ · ${describeSchedule(idea.rrule)}',
            trailing: Icon(Icons.add_circle_outline_rounded, color: t.colors.accent),
            onTap: () async {
              final w = ref.read(writerProvider);
              await w.commit([w.op('chores', newId(), choreFromTemplate(idea, kidId: kid.id, anchorDate: ref.read(todayProvider).iso))]);
              ref.read(toastProvider).show('Added “${idea.title}” for ${kid.name}', emoji: idea.emoji);
            },
          ),
      ],
    );
  }
}

// ──────────────────────────────── Routines ─────────────────────────────────

const List<int?> _timerChoices = [null, 20, 60, 120, 300];

/// Picker result for "start from scratch" (null means the sheet was dismissed).
const Object _blank = 'blank';

String _timerLabel(int? s) => s == null ? 'No timer' : (s < 60 ? '$s s' : '${s ~/ 60} min');

Future<void> addRoutine(BuildContext context, WidgetRef ref) async {
  if (!await ensureGrownUp(context, ref, reason: 'Adding routines needs a grown-up')) return;
  if (!context.mounted) return;
  // A sentinel for "from scratch": dismissing the sheet also returns null.
  final choice = await showDSheet<Object>(
    context,
    id: 'routines.templates',
    title: 'Add a routine',
    builder: (sheet) {
      final t = DTheme.of(sheet);
      return Column(
        children: [
          for (final (i, tpl) in kRoutineTemplates.indexed)
            DListRow(
              id: 'routines.template.$i',
              leading: DEmoji(tpl.emoji, size: 32 * t.scale),
              title: tpl.title,
              subtitle: tpl.steps.map((s) => s.$2).join(' '),
              onTap: () => Navigator.of(sheet).pop(tpl),
            ),
          DListRow(id: 'routines.template.blank', leading: DEmoji('✨', size: 32 * t.scale), title: 'Start from scratch', onTap: () => Navigator.of(sheet).pop(_blank)),
        ],
      );
    },
  );
  if (choice == null || !context.mounted) return;
  final template = choice is RoutineTemplate ? choice : null;
  await showDSheet<void>(context, id: 'routine.editor', title: template?.title ?? 'New routine', builder: (_) => _RoutineEditor(template: template));
}

Future<void> editRoutine(BuildContext context, WidgetRef ref, Routine routine) async {
  if (!await ensureGrownUp(context, ref, reason: 'Changing routines needs a grown-up')) return;
  if (!context.mounted) return;
  await showDSheet<void>(context, id: 'routine.editor', title: routine.title, builder: (_) => _RoutineEditor(routine: routine));
}

class _RoutineEditor extends ConsumerStatefulWidget {
  const _RoutineEditor({this.routine, this.template});
  final Routine? routine;
  final RoutineTemplate? template;

  @override
  ConsumerState<_RoutineEditor> createState() => _RoutineEditorState();
}

class _RoutineEditorState extends ConsumerState<_RoutineEditor> {
  late final _title = TextEditingController(text: widget.routine?.title ?? widget.template?.title ?? '');
  late String _emoji = widget.routine?.emoji ?? widget.template?.emoji ?? '🌟';
  late final String _kind = widget.routine?.kind ?? widget.template?.kind ?? 'custom';
  late Set<String> _who = {...decodeStringList(widget.routine?.profileIds)};
  late ScheduleKind _schedule = scheduleOf(widget.routine?.rrule ?? 'FREQ=DAILY').$1;
  late Set<int> _days = scheduleOf(widget.routine?.rrule ?? 'FREQ=DAILY').$2;
  late String? _start = widget.routine?.startTime ?? widget.template?.startTime;
  late final List<RoutineStep> _steps = widget.routine != null ? decodeSteps(widget.routine!.steps) : (widget.template?.buildSteps() ?? []);
  late final List<TextEditingController> _stepText = [for (final s in _steps) TextEditingController(text: s.title)];

  @override
  void dispose() {
    _title.dispose();
    for (final c in _stepText) {
      c.dispose();
    }
    super.dispose();
  }

  RoutineStep _with(RoutineStep s, {String? emoji, int? timer, bool clearTimer = false}) => RoutineStep(
        id: s.id,
        title: s.title,
        emoji: emoji ?? s.emoji,
        timerSeconds: clearTimer ? null : (timer ?? s.timerSeconds),
        voiceLine: s.voiceLine,
        voiceBlob: s.voiceBlob,
        song: s.song,
      );

  void _move(int i, int by) => setState(() {
        final j = i + by;
        if (j < 0 || j >= _steps.length) return;
        _steps.insert(j, _steps.removeAt(i));
        _stepText.insert(j, _stepText.removeAt(i));
      });

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ref.read(toastProvider).show('Give the routine a name', emoji: '✏️');
      return;
    }
    final steps = [
      for (final (i, s) in _steps.indexed)
        if (_stepText[i].text.trim().isNotEmpty)
          RoutineStep(id: s.id, title: _stepText[i].text.trim(), emoji: s.emoji, timerSeconds: s.timerSeconds, voiceLine: s.voiceLine, voiceBlob: s.voiceBlob, song: s.song),
    ];
    if (steps.isEmpty) {
      ref.read(toastProvider).show('Add at least one step', emoji: '✏️');
      return;
    }
    final w = ref.read(writerProvider);
    final r = widget.routine;
    await w.commit([
      w.op('routines', r?.id ?? newId(), routineFields(
        title: title,
        emoji: _emoji,
        kind: _kind,
        profileIds: _who.toList(),
        steps: steps,
        rrule: scheduleRule(_schedule, days: _days, custom: r?.rrule),
        startTime: _start,
        anchorDate: r?.anchorDate ?? ref.read(todayProvider).iso,
      )),
    ]);
    if (mounted) Navigator.of(context).maybePop();
    ref.read(toastProvider).show('Saved “$title”', emoji: _emoji);
  }

  Future<void> _delete() async {
    final r = widget.routine!;
    if (!await confirmDialog(context, title: 'Delete “${r.title}”?', confirmLabel: 'Delete', danger: true)) return;
    await ref.read(writerProvider).delete('routines', r.id);
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final kids = ref.watch(kidsProvider);
    final h24 = ref.watch(clock24Provider);
    String? startLabel() {
      final s = _start;
      if (s == null) return null;
      final parts = s.split(':');
      return formatTime(DateTime(2000, 1, 1, int.tryParse(parts.first) ?? 0, int.tryParse(parts.last) ?? 0), h24: h24);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _EmojiButton(emoji: _emoji, id: 'routine.emoji', onPick: (e) => setState(() => _emoji = e)),
            SizedBox(width: t.space.sm),
            Expanded(child: DTextField(id: 'routine.title', controller: _title, label: 'Routine', hint: 'Good morning')),
          ],
        ),
        const _Label('For'),
        Wrap(
          spacing: t.space.xs,
          runSpacing: t.space.xs,
          children: [
            DChip(label: 'All kids', selected: _who.isEmpty, id: 'routine.who.all', onTap: () => setState(() => _who = {})),
            for (final k in kids)
              DChip(
                label: k.name,
                emoji: k.emoji,
                personColor: PersonColors.of(k.color, t.colors),
                selected: _who.contains(k.id),
                id: 'routine.who.${k.id}',
                onTap: () => setState(() => _who.contains(k.id) ? _who.remove(k.id) : _who.add(k.id)),
              ),
          ],
        ),
        const _Label('When'),
        _SchedulePicker(kind: _schedule, days: _days, idPrefix: 'routine.schedule', onChanged: (k, d) => setState(() {
              _schedule = k;
              _days = d;
            })),
        DListRow(
          id: 'routine.start',
          title: 'Starts at',
          subtitle: startLabel() ?? 'Any time',
          trailing: _start == null ? null : DIconButton(icon: Icons.close_rounded, label: 'No start time', tone: DButtonTone.ghost, onPressed: () => setState(() => _start = null)),
          onTap: () async {
            final parts = (_start ?? '07:00').split(':');
            final m = await pickTime(context, initial: (int.tryParse(parts.first) ?? 7) * 60 + (int.tryParse(parts.last) ?? 0), title: 'Starts at');
            if (m != null) setState(() => _start = '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}');
          },
        ),
        const _Label('Steps'),
        for (final (i, s) in _steps.indexed)
          Padding(
            padding: EdgeInsets.only(bottom: t.space.xs),
            child: Row(
              children: [
                _EmojiButton(emoji: s.emoji ?? '⭐', id: 'routine.step.$i.emoji', onPick: (e) => setState(() => _steps[i] = _with(s, emoji: e))),
                SizedBox(width: t.space.xs),
                Expanded(child: DTextField(id: 'routine.step.$i', controller: _stepText[i], hint: 'Step ${i + 1}')),
                SizedBox(width: t.space.xs),
                DChip(
                  label: _timerLabel(s.timerSeconds),
                  emoji: '⏱️',
                  dense: true,
                  selected: s.timerSeconds != null,
                  id: 'routine.step.$i.timer',
                  onTap: () => setState(() {
                    final next = _timerChoices[(_timerChoices.indexOf(s.timerSeconds) + 1) % _timerChoices.length];
                    _steps[i] = _with(s, timer: next, clearTimer: next == null);
                  }),
                ),
                DIconButton(icon: Icons.arrow_upward_rounded, label: 'Move up', tone: DButtonTone.ghost, onPressed: i == 0 ? null : () => _move(i, -1)),
                DIconButton(icon: Icons.arrow_downward_rounded, label: 'Move down', tone: DButtonTone.ghost, onPressed: i == _steps.length - 1 ? null : () => _move(i, 1)),
                DIconButton(
                  icon: Icons.delete_outline_rounded,
                  label: 'Remove step',
                  tone: DButtonTone.ghost,
                  id: 'routine.step.$i.remove',
                  onPressed: () => setState(() {
                    _steps.removeAt(i);
                    _stepText.removeAt(i).dispose();
                  }),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: DButton(
            label: 'Add a step',
            icon: Icons.add_rounded,
            tone: DButtonTone.tonal,
            size: DButtonSize.sm,
            id: 'routine.step.add',
            onPressed: () => setState(() {
              _steps.add(RoutineStep(id: newId(), title: '', emoji: '⭐'));
              _stepText.add(TextEditingController());
            }),
          ),
        ),
        SizedBox(height: t.space.lg),
        Row(
          children: [
            if (widget.routine != null) DButton(label: 'Delete', icon: Icons.delete_outline_rounded, tone: DButtonTone.ghost, id: 'routine.delete', onPressed: _delete),
            const Spacer(),
            DButton(label: 'Save', icon: Icons.check_rounded, id: 'routine.save', onPressed: _save),
          ],
        ),
      ],
    );
  }
}

// ──────────────────────────────── Rewards ──────────────────────────────────

Future<void> addReward(BuildContext context, WidgetRef ref) async {
  if (!await ensureGrownUp(context, ref, reason: 'Adding rewards needs a grown-up')) return;
  if (!context.mounted) return;
  final picked = await showDSheet<Object>(
    context,
    id: 'rewards.ideas',
    title: 'Add a reward',
    builder: (sheet) {
      final t = DTheme.of(sheet);
      return Column(
        children: [
          DListRow(id: 'rewards.idea.custom', leading: DEmoji('✨', size: 32 * t.scale), title: 'Something else', onTap: () => Navigator.of(sheet).pop(_blank)),
          for (final (i, idea) in kRewardIdeas.indexed)
            DListRow(
              id: 'rewards.idea.$i',
              leading: DEmoji(idea.$2, size: 32 * t.scale),
              title: idea.$1,
              subtitle: RewardKind.parse(idea.$3).label,
              onTap: () => Navigator.of(sheet).pop(idea),
            ),
        ],
      );
    },
  );
  if (picked == null || !context.mounted) return;
  final idea = picked is (String, String, String, int) ? picked : null;
  await showDSheet<void>(context, id: 'reward.editor', title: idea?.$1 ?? 'New reward', builder: (_) => _RewardEditor(idea: idea));
}

Future<void> editReward(BuildContext context, WidgetRef ref, Reward reward) async {
  if (!await ensureGrownUp(context, ref, reason: 'Changing rewards needs a grown-up')) return;
  if (!context.mounted) return;
  await showDSheet<void>(context, id: 'reward.editor', title: reward.title, builder: (_) => _RewardEditor(reward: reward));
}

class _RewardEditor extends ConsumerStatefulWidget {
  const _RewardEditor({this.reward, this.idea});
  final Reward? reward;
  final (String, String, String, int)? idea;

  @override
  ConsumerState<_RewardEditor> createState() => _RewardEditorState();
}

class _RewardEditorState extends ConsumerState<_RewardEditor> {
  late final _title = TextEditingController(text: widget.reward?.title ?? widget.idea?.$1 ?? '');
  late String _emoji = widget.reward?.emoji ?? widget.idea?.$2 ?? '🎁';
  late RewardKind _kind = RewardKind.parse(widget.reward?.kind ?? widget.idea?.$3);
  late int _cost = (widget.reward?.cost ?? widget.idea?.$4 ?? 10).clamp(1, 999);

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ref.read(toastProvider).show('Give the reward a name', emoji: '✏️');
      return;
    }
    final w = ref.read(writerProvider);
    await w.commit([w.op('rewards', widget.reward?.id ?? newId(), rewardFields(title: _title.text, emoji: _emoji, kind: _kind, cost: _cost))]);
    if (mounted) Navigator.of(context).maybePop();
    ref.read(toastProvider).show('Saved “${_title.text.trim()}”', emoji: _emoji);
  }

  Future<void> _delete() async {
    final r = widget.reward!;
    if (!await confirmDialog(context, title: 'Delete “${r.title}”?', confirmLabel: 'Delete', danger: true)) return;
    await ref.read(writerProvider).delete('rewards', r.id);
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _EmojiButton(emoji: _emoji, id: 'reward.emoji', onPick: (e) => setState(() => _emoji = e)),
            SizedBox(width: t.space.sm),
            Expanded(child: DTextField(id: 'reward.title', controller: _title, label: 'Reward', hint: 'Extra bedtime story')),
          ],
        ),
        const _Label('Kind'),
        DSegmented<RewardKind>(options: [for (final k in RewardKind.values) (k, k.label)], value: _kind, dense: true, idPrefix: 'reward.kind', onChanged: (k) => setState(() => _kind = k)),
        if (_kind != RewardKind.surprise)
          DListRow(
            title: _kind == RewardKind.family ? 'Jobs to reach it' : 'Stars it costs',
            trailing: DStepper(id: 'reward.cost', value: _cost, max: 999, onChanged: (v) => setState(() => _cost = v)),
          )
        else
          Padding(padding: EdgeInsets.only(top: t.space.sm), child: Text('Revealed when a reward jar fills up.', style: t.text.caption)),
        SizedBox(height: t.space.lg),
        Row(
          children: [
            if (widget.reward != null) DButton(label: 'Delete', icon: Icons.delete_outline_rounded, tone: DButtonTone.ghost, id: 'reward.delete', onPressed: _delete),
            const Spacer(),
            DButton(label: 'Save', icon: Icons.check_rounded, id: 'reward.save', onPressed: _save),
          ],
        ),
      ],
    );
  }
}
