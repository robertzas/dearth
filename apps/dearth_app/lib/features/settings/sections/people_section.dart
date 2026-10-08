import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../app/grown_up.dart';
import '../../../core/data/household.dart';
import '../../../core/format.dart';
import '../../../core/providers.dart';
import '../../../shared/face_photo.dart';
import '../../../shared/face_picker.dart';
import '../../../shared/pickers.dart';
import '../settings_screen.dart';

/// Family members (SPEC §9.1, FR-SET-02): colors, roles, kid stages, PINs.
class PeopleSection extends ConsumerWidget {
  const PeopleSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final people = ref.watch(profilesProvider).value ?? const <Profile>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'Family',
          footer: 'Grown-ups with a PIN can unlock settings and deletes on shared displays.',
          children: [
            for (final p in people)
              DListRow(
                id: 'people.${p.id}',
                title: p.name,
                subtitle: [
                  _roleLabel(p.role),
                  if (p.role == ProfileRole.child) KidStage.label(p.kidStage),
                  if (_isAdult(p)) p.pinHash == null ? 'no PIN' : 'PIN set',
                ].join(' · '),
                leading: ProfileAvatar(p, size: 48 * t.scale),
                chevron: true,
                onTap: () => editProfile(context, ref, p),
              ),
            DListRow(
              id: 'people.add',
              title: 'Add someone',
              leading: Container(
                width: 48 * t.scale,
                height: 48 * t.scale,
                decoration: BoxDecoration(color: t.colors.accentTint, shape: BoxShape.circle),
                child: Icon(Icons.add_rounded, color: t.colors.accent),
              ),
              onTap: () => editProfile(context, ref, null),
            ),
          ],
        ),
      ],
    );
  }
}

bool _isAdult(Profile p) => p.role == ProfileRole.adult || p.role == ProfileRole.caregiver;

String _roleLabel(String role) => switch (role) {
      ProfileRole.adult => 'Grown-up',
      ProfileRole.child => 'Kid',
      ProfileRole.caregiver => 'Caregiver',
      ProfileRole.guest => 'Guest',
      ProfileRole.pet => 'Pet',
      _ => role,
    };

const _emojiChoices = ['👩', '👨', '🧑', '👧', '👦', '🧒', '👶', '👵', '👴', '🧓', '🐶', '🐱', '🐰', '🦊', '🐻', '🐼', '🦄', '🦖', '🌟', '🌈'];

Future<void> editProfile(BuildContext context, WidgetRef ref, Profile? p) async {
  if (!await ensureGrownUp(context, ref, reason: 'Changing people needs a grown-up')) return;
  if (!context.mounted) return;
  await showDSheet<void>(
    context,
    title: p == null ? 'Add someone' : p.name,
    id: 'profile.editor',
    builder: (_) => _ProfileEditor(profile: p),
  );
}

class _ProfileEditor extends ConsumerStatefulWidget {
  const _ProfileEditor({this.profile});
  final Profile? profile;

  @override
  ConsumerState<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends ConsumerState<_ProfileEditor> {
  late final _name = TextEditingController(text: widget.profile?.name ?? '');
  late String _role = widget.profile?.role ?? ProfileRole.adult;
  late int _color = widget.profile?.color ?? 0;
  late String? _emoji = widget.profile?.emoji;
  late LocalDate? _birthday = LocalDate.tryParse(widget.profile?.birthday);
  late String? _stage = widget.profile?.kidStage;
  late String? _buddy = widget.profile?.buddy;
  late String? _photo = widget.profile?.avatarBlob;
  String? _newPinHash;
  bool _clearPin = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _setPin() async {
    String? first;
    final hash = await showDSheet<String>(
      context,
      title: 'Grown-up PIN',
      id: 'profile.pin',
      builder: (sheet) => StatefulBuilder(builder: (context, setState) {
        return DPinPad(
          subtitle: first == null ? 'Choose a 4-digit PIN' : 'Enter it again',
          onSubmit: (pin) async {
            if (first == null) {
              setState(() => first = pin);
              return true;
            }
            if (pin != first) {
              setState(() => first = null);
              return false;
            }
            final h = await compute(hashPin, pin);
            if (sheet.mounted) Navigator.of(sheet).pop(h);
            return true;
          },
        );
      }),
    );
    if (hash != null) {
      setState(() {
        _newPinHash = hash;
        _clearPin = false;
      });
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final people = ref.read(profilesProvider).value ?? const <Profile>[];
    final fields = <String, Object?>{
      'name': name,
      'role': _role,
      'color': _color,
      'emoji': _emoji,
      'avatar_blob': _photo,
      'birthday': _birthday?.iso,
      'kid_stage': _role == ProfileRole.child ? (_stage ?? KidStage.little) : null,
      'buddy': _role == ProfileRole.child ? (_buddy ?? 'bunny') : null,
      if (_newPinHash != null) 'pin_hash': _newPinHash,
      if (_clearPin) 'pin_hash': null,
    };
    final w = ref.read(writerProvider);
    if (widget.profile == null) {
      await w.create('profiles', {...fields, 'sort_key': sortKeyAfter(people.lastOrNull?.sortKey)});
    } else {
      await w.upsert('profiles', widget.profile!.id, fields);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    final p = widget.profile!;
    final ok = await confirmDialog(context, title: 'Remove ${p.name}?', message: 'Their events and chores stay; they just won’t show up as a person.', confirmLabel: 'Remove', danger: true);
    if (!ok) return;
    await ref.read(writerProvider).upsert('profiles', p.id, {'archived': true});
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final adult = _role == ProfileRole.adult || _role == ProfileRole.caregiver;
    final hasPin = !_clearPin && (_newPinHash != null || widget.profile?.pinHash != null);
    Widget label(String s) => Padding(padding: EdgeInsets.only(top: t.space.lg, bottom: t.space.xs), child: Text(s.toUpperCase(), style: t.text.overline));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            DAvatar(
              colorIndex: _color,
              emoji: _emoji,
              name: _name.text,
              size: 72 * t.scale,
              photo: FaceCrop.parse(_photo) == null ? null : (double s) => FacePhoto(FaceCrop.parse(_photo)!, size: s, fallback: DEmoji(_emoji ?? '🙂', size: s * 0.58)),
            ),
            SizedBox(width: t.space.md),
            Expanded(child: DTextField(id: 'profile.name', controller: _name, hint: 'Name', big: true, autofocus: widget.profile == null, onChanged: (_) => setState(() {}))),
          ],
        ),
        label('Who'),
        Wrap(
          spacing: t.space.xs,
          runSpacing: t.space.xs,
          children: [
            for (final r in ProfileRole.all)
              DChip(id: 'profile.role.$r', label: _roleLabel(r), selected: _role == r, dense: true, onTap: () => setState(() => _role = r)),
          ],
        ),
        label('Color'),
        Wrap(
          spacing: t.space.xs,
          runSpacing: t.space.xs,
          children: [
            for (var i = 0; i < kProfileColors.length; i++)
              DPressable(
                id: 'profile.color.$i',
                onTap: () => setState(() => _color = i),
                semanticLabel: kProfilePalette[i].$1,
                selected: _color == i,
                borderRadius: BorderRadius.circular(40),
                child: Container(
                  width: 48 * t.scale,
                  height: 48 * t.scale,
                  decoration: BoxDecoration(
                    color: kProfileColors[i],
                    shape: BoxShape.circle,
                    border: Border.all(color: _color == i ? t.colors.inkPrimary : Colors.transparent, width: 3 * t.scale),
                  ),
                  child: _color == i ? Icon(Icons.check_rounded, color: t.person(i).onSolid) : null,
                ),
              ),
          ],
        ),
        label('Picture'),
        // A face photo from the family library (it shows as their avatar,
        // and lets the Toybox's Who's That? use their face).
        Wrap(
          spacing: t.space.sm,
          runSpacing: t.space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DButton(
              id: 'profile.photo',
              label: _photo == null ? 'Use a photo' : 'Change the photo',
              icon: Icons.face_retouching_natural_rounded,
              tone: DButtonTone.tonal,
              onPressed: ref.watch(hubApiProvider) == null
                  ? null
                  : () async {
                      final face = await pickFace(context, ref);
                      if (face != null) setState(() => _photo = face.encode());
                    },
            ),
            if (_photo != null) DButton(id: 'profile.nophoto', label: 'No photo', tone: DButtonTone.ghost, onPressed: () => setState(() => _photo = null)),
            if (ref.watch(hubApiProvider) == null) Text('Photos come from the family photo library on a Hub.', style: t.text.caption.copyWith(color: t.colors.inkTertiary)),
          ],
        ),
        SizedBox(height: t.space.sm),
        Wrap(
          spacing: t.space.xs,
          runSpacing: t.space.xs,
          children: [
            for (final e in _emojiChoices)
              DPressable(
                onTap: () => setState(() => _emoji = e),
                semanticLabel: e,
                selected: _emoji == e,
                borderRadius: t.radius.card,
                child: Container(
                  width: 52 * t.scale,
                  height: 52 * t.scale,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _emoji == e ? t.colors.accentTint : t.colors.surfaceSunken, borderRadius: t.radius.card),
                  child: DEmoji(e, size: 34 * t.scale),
                ),
              ),
          ],
        ),
        label('Birthday'),
        Row(
          children: [
            DButton(
              id: 'profile.birthday',
              label: _birthday == null ? 'Add birthday' : dateWithYear(_birthday!),
              icon: Icons.cake_rounded,
              tone: DButtonTone.neutral,
              onPressed: () async {
                final d = await pickDate(context, initial: _birthday ?? ref.read(todayProvider), title: 'Birthday', birthday: true, unset: _birthday == null);
                if (d != null) setState(() => _birthday = d);
              },
            ),
          ],
        ),
        if (_role == ProfileRole.child) ...[
          label('Stage'),
          Wrap(
            spacing: t.space.xs,
            runSpacing: t.space.xs,
            children: [
              for (final s in KidStage.all)
                DChip(id: 'profile.stage.$s', label: KidStage.label(s), selected: (_stage ?? KidStage.little) == s, dense: true, onTap: () => setState(() => _stage = s)),
            ],
          ),
          label('Buddy'),
          Wrap(
            spacing: t.space.xs,
            runSpacing: t.space.xs,
            children: [
              for (final (id, emoji, name) in kBuddies)
                DChip(label: name, emoji: emoji, selected: (_buddy ?? 'bunny') == id, dense: true, onTap: () => setState(() => _buddy = id)),
            ],
          ),
        ],
        if (adult) ...[
          label('Grown-up PIN'),
          Row(
            children: [
              DButton(id: 'profile.pin.set', label: hasPin ? 'Change PIN' : 'Set a PIN', icon: Icons.pin_rounded, tone: DButtonTone.tonal, onPressed: _setPin),
              if (hasPin) ...[
                SizedBox(width: t.space.sm),
                DButton(label: 'Remove PIN', tone: DButtonTone.ghost, onPressed: () => setState(() {
                  _clearPin = true;
                  _newPinHash = null;
                })),
              ],
            ],
          ),
        ],
        SizedBox(height: t.space.xl),
        Row(
          children: [
            if (widget.profile != null) ...[
              DButton(label: 'Remove', tone: DButtonTone.ghost, id: 'profile.remove', onPressed: _remove),
              const Spacer(),
            ] else
              const Spacer(),
            DButton(label: 'Save', icon: Icons.check_rounded, id: 'profile.save', onPressed: _save),
          ],
        ),
      ],
    );
  }
}
