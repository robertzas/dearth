import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/data/calendar.dart';
import '../../../core/data/household.dart';
import '../../../core/providers.dart';
import '../../../core/sync/hub_api.dart';
import '../google_connect.dart';
import '../settings_screen.dart';

/// The Google accounts the Hub syncs calendars for.
List<String> googleCalendarAccounts(List<CalendarSource> sources) =>
    {for (final s in sources) if (s.kind == 'google' && s.accountId != null && s.status != 'disconnected') s.accountId!}.toList()..sort();

/// FR-CAL-04: once Google is connected, offer a shared "Family" calendar so
/// events added on the wall land somewhere both parents see on their
/// phones. A writable Google calendar already called "Family" is offered
/// instead of making another.
class FamilyCalendarOffer extends ConsumerWidget {
  const FamilyCalendarOffer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final sources = ref.watch(calendarSourcesProvider).value ?? const <CalendarSource>[];
    final setting = ref.watch(settingMapProvider(SettingKeys.calendarGoogleFamily));
    final accounts = googleCalendarAccounts(sources);
    if (accounts.isEmpty) return const SizedBox.shrink();

    final made = sources.where((s) => s.id == setting['source'] && !s.deleted).firstOrNull;
    if (made != null) {
      final shared = [for (final e in setting['shared'] is List ? setting['shared']! as List : const []) '$e'];
      return SettingsGroup(
        title: 'Family calendar',
        children: [
          DListRow(
            id: 'calendars.family.made',
            title: '${made.name} · Google',
            subtitle: [
              'In ${made.accountId}’s Google Calendar',
              if (shared.isNotEmpty) 'shared with ${shared.join(', ')}',
              if (made.isDefault) 'new events go here',
            ].join(' · '),
            leading: DEmoji('👪', size: 30 * t.scale),
          ),
        ],
      );
    }
    if (setting['dismissed'] == true) return const SizedBox.shrink();

    final api = ref.watch(hubApiProvider);
    final admin = ref.watch(sessionProvider.select((s) => s.admin));
    final existing = sources.where((s) => s.kind == 'google' && s.writable && s.name.trim().toLowerCase() == 'family').firstOrNull;
    final w = ref.read(writerProvider);
    return SettingsGroup(
      title: 'Family calendar',
      footer: 'Events added on the wall land in a Google calendar both parents see on their phones.',
      children: [
        if (existing != null)
          DListRow(
            id: 'calendars.family.use',
            title: 'Use “${existing.name}” from Google',
            subtitle: 'In ${existing.accountId}’s Google Calendar. New events from the wall go there.',
            leading: DEmoji('👪', size: 30 * t.scale),
            chevron: true,
            onTap: () => w.commit([
              for (final o in sources)
                if (o.isDefault && o.id != existing.id) w.op('calendar_sources', o.id, {'is_default': false}),
              w.op('calendar_sources', existing.id, {'is_default': true, 'enabled': true}),
              settingOp(w, SettingKeys.calendarGoogleFamily, {'source': existing.id, 'account': existing.accountId, 'shared': const <String>[]}),
            ]),
          )
        else
          DListRow(
            id: 'calendars.family.create',
            title: 'Make a shared Family calendar',
            subtitle: admin ? 'In Google Calendar, shared with the other grown-up' : 'From the Hub’s admin display',
            leading: DEmoji('👪', size: 30 * t.scale),
            chevron: true,
            onTap: api == null || !admin ? null : () => makeFamilyCalendar(context, ref, api, accounts),
          ),
        DListRow(
          id: 'calendars.family.dismiss',
          title: 'Not now',
          subtitle: 'Keep new events on the Hub’s own Family calendar',
          leading: DEmoji('🏠', size: 30 * t.scale),
          onTap: () => w.commit([settingOp(w, SettingKeys.calendarGoogleFamily, {'dismissed': true})]),
        ),
      ],
    );
  }
}

/// Asks where to make the Family calendar and who to share it with, then
/// has the Hub make it (after one more Google consent when the account
/// hasn't allowed making calendars yet).
Future<void> makeFamilyCalendar(BuildContext context, WidgetRef ref, HubApi api, List<String> accounts) async {
  final db = ref.read(dbProvider);
  final onHub = (await (db.select(db.events)..where((e) => e.sourceId.equals(Ids.familyCalendar) & e.deleted.equals(false))).get()).length;
  if (!context.mounted) return;
  final choice = await showDSheet<({String account, List<String> share, bool move})>(
    context,
    title: 'Shared Family calendar',
    id: 'calendars.family.sheet',
    builder: (sheet) => _FamilySheet(accounts: accounts, onHub: onHub),
  );
  if (choice == null || !context.mounted) return;

  void done(Map<String, Object?> family) {
    final shared = [for (final e in family['shared'] is List ? family['shared']! as List : const []) '$e'];
    final failed = [for (final e in family['failed'] is List ? family['failed']! as List : const []) '$e'];
    final toast = ref.read(toastProvider);
    toast.show(shared.isEmpty ? 'Made “Family” in Google Calendar' : 'Made “Family” and shared it with ${shared.join(' and ')}', emoji: '👪');
    if (failed.isNotEmpty) toast.show('Couldn’t share it with ${failed.join(' and ')}. Share it in Google Calendar instead.', emoji: '⚠️', tone: DBannerTone.warning);
  }

  try {
    final r = await api.post('/api/admin/calendars/google/family', {'account': choice.account, 'share': choice.share, 'move': choice.move});
    if (r['created'] == true) return done(r);
    if (!context.mounted) return;
    await continueGoogleSignIn(context, ref, api, r, onDone: (reply) {
      if (reply['family'] case final Map<String, Object?> family) done(family);
    });
  } on HubApiException catch (e) {
    ref.read(toastProvider).show(e.friendly, emoji: '⚠️', tone: DBannerTone.warning);
  }
}

class _FamilySheet extends StatefulWidget {
  const _FamilySheet({required this.accounts, required this.onHub});
  final List<String> accounts;

  /// Events on the Hub's own Family calendar, offered to move over.
  final int onHub;

  @override
  State<_FamilySheet> createState() => _FamilySheetState();
}

class _FamilySheetState extends State<_FamilySheet> {
  late String _account = widget.accounts.first;

  /// Other connected accounts are the other grown-ups: shared by default.
  late final Set<String> _share = {...widget.accounts.skip(1)};
  late bool _move = widget.onHub > 0;
  final _email = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _create() {
    final typed = _email.text.trim().toLowerCase();
    if (typed.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(typed)) {
      setState(() => _error = 'That doesn’t look like an email address');
      return;
    }
    Navigator.of(context).pop((
      account: _account,
      share: {..._share.where((e) => e != _account), if (typed.isNotEmpty) typed}.toList(),
      move: _move,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    Widget label(String s) => Padding(padding: EdgeInsets.only(top: t.space.md, bottom: t.space.xs), child: Text(s, style: t.text.overline));
    final others = widget.accounts.where((a) => a != _account).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Dearth makes a calendar called “Family” in Google Calendar and adds new events from the wall to it, so they show up on both parents’ phones.',
          style: t.text.body.copyWith(color: t.colors.inkSecondary),
        ),
        if (widget.accounts.length > 1) ...[
          label('MAKE IT IN'),
          Wrap(
            spacing: t.space.xs,
            runSpacing: t.space.xs,
            children: [
              for (final a in widget.accounts)
                DChip(id: 'family.account.$a', label: a, dense: true, selected: a == _account, onTap: () => setState(() => _account = a)),
            ],
          ),
        ],
        label('SHARE IT WITH'),
        if (others.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: t.space.sm),
            child: Wrap(
              spacing: t.space.xs,
              runSpacing: t.space.xs,
              children: [
                for (final a in others)
                  DChip(
                    id: 'family.share.$a',
                    label: a,
                    dense: true,
                    selected: _share.contains(a),
                    onTap: () => setState(() => _share.contains(a) ? _share.remove(a) : _share.add(a)),
                  ),
              ],
            ),
          ),
        DTextField(
          id: 'family.share.email',
          controller: _email,
          hint: others.isEmpty ? 'The other grown-up’s Google email' : 'Someone else’s Google email',
          keyboardType: TextInputType.emailAddress,
          errorText: _error,
          onChanged: (_) => setState(() => _error = null),
        ),
        SizedBox(height: t.space.xs),
        Text('Google emails them a link to add it.', style: t.text.caption),
        if (widget.onHub > 0) ...[
          SizedBox(height: t.space.sm),
          DSwitchRow(
            id: 'family.move',
            title: 'Move the ${widget.onHub} ${widget.onHub == 1 ? 'event' : 'events'} already here',
            subtitle: 'From the Hub’s own Family calendar into the new one',
            value: _move,
            onChanged: (v) => setState(() => _move = v),
          ),
        ],
        SizedBox(height: t.space.lg),
        DButton(label: 'Make the Family calendar', id: 'family.create', expand: true, onPressed: _create),
      ],
    );
  }
}
