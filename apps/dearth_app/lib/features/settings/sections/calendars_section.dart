import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/data/calendar.dart';
import '../../../core/data/household.dart';
import '../../../core/providers.dart';
import '../../../core/sync/hub_api.dart';
import '../settings_screen.dart';

/// Calendar sources (SPEC FR-CAL-01/02): toggle, default target, ICS
/// subscriptions and Google accounts (both run on the Hub).
class CalendarsSection extends ConsumerWidget {
  const CalendarsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final sources = ref.watch(calendarSourcesProvider).value ?? const <CalendarSource>[];
    final session = ref.watch(sessionProvider);
    final api = ref.watch(hubApiProvider);
    final w = ref.read(writerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsGroup(
          title: 'Calendars',
          footer: 'New events from this display go to the calendar marked “default”.',
          children: [
            for (final s in sources)
              DListRow(
                id: 'calendars.${s.id}',
                title: s.name,
                subtitle: [
                  switch (s.kind) { 'google' => 'Google${s.accountId == null ? '' : ' · ${s.accountId}'}', 'ics' => 'Subscribed (read-only)', _ => 'On this Hub' },
                  if (s.isDefault) 'default',
                  if (s.status != null && s.status != 'ok') s.status!,
                ].join(' · '),
                leading: Container(width: 20 * t.scale, height: 20 * t.scale, decoration: BoxDecoration(color: Color(s.color), shape: BoxShape.circle)),
                onTap: () => _calendarSheet(context, ref, s),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (s.writable && !s.isDefault && s.enabled)
                      DButton(
                        label: 'Make default',
                        tone: DButtonTone.ghost,
                        size: DButtonSize.sm,
                        onPressed: () => w.commit([
                          for (final o in sources)
                            if (o.isDefault) w.op('calendar_sources', o.id, {'is_default': false}),
                          w.op('calendar_sources', s.id, {'is_default': true}),
                        ]),
                      ),
                    Switch(value: s.enabled, onChanged: (v) => w.upsert('calendar_sources', s.id, {'enabled': v})),
                  ],
                ),
              ),
          ],
        ),
        const _BirthdaysAndHolidays(),
        SettingsGroup(
          title: 'Add calendars',
          footer: api == null
              ? 'Subscriptions and Google sync run on your Dearth Hub. Connect one in Hub & devices.'
              : (session.admin ? null : 'This device isn’t an admin device; add calendars from the Hub’s admin device.'),
          children: [
            DListRow(
              id: 'calendars.add.ics',
              title: 'Subscribe to a calendar link',
              subtitle: 'School, daycare, sports, holidays (ICS / webcal)',
              leading: const DEmoji('🔗', size: 30),
              chevron: true,
              onTap: api == null || !session.admin ? null : () => _addIcs(context, ref, api),
            ),
            DListRow(
              id: 'calendars.add.google',
              title: 'Connect Google Calendar',
              subtitle: 'Two-way sync; sign-in happens on the Hub',
              leading: const DEmoji('📆', size: 30),
              chevron: true,
              onTap: api == null || !session.admin ? null : () => _connectGoogle(context, ref, api),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _addIcs(BuildContext context, WidgetRef ref, HubApi api) async {
    final url = TextEditingController();
    final name = TextEditingController();
    final ok = await showDSheet<bool>(
      context,
      title: 'Subscribe to a calendar',
      id: 'calendars.ics.sheet',
      builder: (sheet) {
        final t = DTheme.of(sheet);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DTextField(id: 'ics.url', controller: url, label: 'Calendar link', hint: 'https://… or webcal://…', autofocus: true),
            SizedBox(height: t.space.md),
            DTextField(id: 'ics.name', controller: name, label: 'Name', hint: 'Daycare'),
            SizedBox(height: t.space.lg),
            DButton(label: 'Subscribe', id: 'ics.save', expand: true, onPressed: () => Navigator.of(sheet).pop(true)),
          ],
        );
      },
    );
    final u = url.text.trim(), n = name.text.trim();
    url.dispose();
    name.dispose();
    if (ok != true || u.isEmpty) return;
    try {
      await api.post('/api/admin/calendars/ics', {'url': u, 'name': n});
      ref.read(toastProvider).show('Subscribed — events appear in a moment', emoji: '🔗');
    } on HubApiException catch (e) {
      ref.read(toastProvider).show(e.friendly, emoji: '⚠️', tone: DBannerTone.warning);
    }
  }

  Future<void> _connectGoogle(BuildContext context, WidgetRef ref, HubApi api) async {
    try {
      final r = await api.get('/api/admin/oauth/google/start');
      final url = Uri.parse(r['url']! as String);
      if (r['mode'] == 'callback') {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        ref.read(toastProvider).show('Finish signing in in the browser', emoji: '🌐');
        return;
      }
      if (!context.mounted) return;
      await _pasteBack(context, ref, api, url);
    } on HubApiException catch (e) {
      ref.read(toastProvider).show(e.friendly, emoji: '⚠️', tone: DBannerTone.warning);
    }
  }

  /// Without an HTTPS domain the admin pastes the final redirect URL back
  /// (SPEC §13.2 paste-back flow).
  Future<void> _pasteBack(BuildContext context, WidgetRef ref, HubApi api, Uri url) async {
    final pasted = TextEditingController();
    final ok = await showDSheet<bool>(
      context,
      title: 'Connect Google',
      builder: (sheet) {
        final t = DTheme.of(sheet);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('1. Open the sign-in page on any browser and approve access.', style: t.text.body),
            SizedBox(height: t.space.sm),
            DButton(label: 'Open sign-in page', icon: Icons.open_in_new_rounded, tone: DButtonTone.tonal, onPressed: () => launchUrl(url, mode: LaunchMode.externalApplication)),
            SizedBox(height: t.space.md),
            Text('2. The browser ends on a page that fails to load. Copy its full address and paste it here.', style: t.text.body),
            SizedBox(height: t.space.sm),
            DTextField(controller: pasted, hint: 'http://localhost/dearth-oauth?code=…'),
            SizedBox(height: t.space.lg),
            DButton(label: 'Connect', expand: true, onPressed: () => Navigator.of(sheet).pop(true)),
          ],
        );
      },
    );
    final text = pasted.text.trim();
    pasted.dispose();
    if (ok != true || text.isEmpty) return;
    try {
      final r = await api.post('/api/admin/oauth/google/complete', {'url': text});
      ref.read(toastProvider).show('Connected ${r['email']}', emoji: '✅');
    } on HubApiException catch (e) {
      ref.read(toastProvider).show(e.friendly, emoji: '⚠️', tone: DBannerTone.warning);
    }
  }
}

/// One calendar's options: its default reminders (FR-CAL-20). Writable
/// calendars prefill them on new events; read-only ones (ICS) remind about
/// every event with them.
Future<void> _calendarSheet(BuildContext context, WidgetRef ref, CalendarSource s) => showDSheet<void>(
      context,
      title: s.name,
      id: 'calendars.sheet',
      builder: (sheet) => Consumer(builder: (context, ref, _) {
        final t = DTheme.of(context);
        final all = ref.watch(calendarRemindersProvider);
        final mine = all[s.id] ?? const <int>[];
        void save(List<int> leads) {
          final w = ref.read(writerProvider);
          w.commit([settingOp(w, SettingKeys.calendarReminders, {...all, s.id: leads})]);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('REMINDERS', style: t.text.overline),
            SizedBox(height: t.space.xs),
            Text(
              s.writable ? 'New events in ${s.name} start with these reminders.' : 'Remind about every event in ${s.name}.',
              style: t.text.body.copyWith(color: t.colors.inkSecondary),
            ),
            SizedBox(height: t.space.sm),
            Wrap(
              spacing: t.space.xs,
              runSpacing: t.space.xs,
              children: [
                DChip(id: 'calendars.remind.none', label: 'None', dense: true, selected: mine.isEmpty, onTap: () => save(const [])),
                for (final m in kTimedReminderChoices)
                  DChip(
                    id: 'calendars.remind.$m',
                    label: describeReminder(m, allDay: false),
                    dense: true,
                    selected: mine.contains(m),
                    onTap: () => save(mine.contains(m) ? [...mine.where((x) => x != m)] : ([...mine, m]..sort())),
                  ),
              ],
            ),
            SizedBox(height: t.space.sm),
            Text('All-day events remind at 8:00 that morning, or the day before.', style: t.text.caption),
          ],
        );
      }),
    );

/// Birthdays from People, and bundled holidays (FR-CAL-18). Tap a row for
/// its reminders.
class _BirthdaysAndHolidays extends ConsumerWidget {
  const _BirthdaysAndHolidays();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final s = ref.watch(virtualCalendarSettingsProvider);
    final sources = {for (final c in ref.watch(virtualCalendarsProvider)) c.id: c};
    final all = ref.watch(settingMapProvider(SettingKeys.calendarVirtual));
    void save(Map<String, Object?> patch) {
      final w = ref.read(writerProvider);
      w.commit([settingOp(w, SettingKeys.calendarVirtual, {...all, ...patch})]);
    }

    return SettingsGroup(
      title: 'Birthdays & holidays',
      footer: 'Birthdays come from People. Holidays include school and office closures, and family days like Halloween.',
      children: [
        DListRow(
          id: 'calendars.birthdays',
          title: 'Birthdays',
          subtitle: 'Kids’ birthdays count down on Home',
          leading: const DEmoji('🎂', size: 30),
          onTap: () => _calendarSheet(context, ref, sources[VirtualCalendars.birthdays]!),
          trailing: Switch(value: s.birthdays, onChanged: (v) => save({'birthdays': v})),
        ),
        DListRow(
          id: 'calendars.holidays',
          title: 'Holidays',
          subtitle: s.country == null ? 'Pick a country' : kHolidayCountries[s.country],
          leading: const DEmoji('🎆', size: 30),
          onTap: s.country == null ? null : () => _calendarSheet(context, ref, sources[VirtualCalendars.holidays]!),
          trailing: Switch(value: s.holidays && s.country != null, onChanged: s.country == null ? null : (v) => save({'holidays': v})),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: t.space.sm),
          child: Wrap(
            spacing: t.space.xs,
            runSpacing: t.space.xs,
            children: [
              for (final e in kHolidayCountries.entries)
                DChip(id: 'calendars.country.${e.key}', label: e.value, dense: true, selected: s.country == e.key, onTap: () => save({'country': e.key, 'holidays': true})),
            ],
          ),
        ),
        DSwitchRow(
          id: 'calendars.observances',
          title: 'Family days',
          subtitle: 'Valentine’s, Easter, Mother’s and Father’s Day, Halloween…',
          value: s.observances,
          onChanged: s.country == null ? null : (v) => save({'observances': v}),
        ),
      ],
    );
  }
}

