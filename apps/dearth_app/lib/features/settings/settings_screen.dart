import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';

import 'sections/about_section.dart';
import 'sections/calendars_section.dart';
import 'sections/device_section.dart';
import 'sections/household_section.dart';
import 'sections/hub_section.dart';
import 'sections/kids_section.dart';
import 'sections/lists_section.dart';
import 'sections/people_section.dart';
import 'sections/photos_section.dart';
import 'sections/recipes_section.dart';
import 'sections/screensaver_section.dart';
import 'sections/toybox_section.dart';
import 'sections/weather_section.dart';

/// The headings Settings groups its sections under (SPEC FR-SET-03): the
/// family, this screen, the services the Hub talks to, and the system.
enum SettingsGroupKind {
  family('Family'),
  display('This display'),
  services('Connected services'),
  system('System');

  const SettingsGroupKind(this.label);
  final String label;
}

/// A settings section (SPEC FR-SET-03). [keywords] are the settings inside
/// it, for the search box.
class SettingsSection {
  const SettingsSection(this.id, this.group, this.title, this.subtitle, this.icon, this.builder, {this.keywords = const []});
  final String id;
  final SettingsGroupKind group;
  final String title;
  final String subtitle;
  final IconData icon;
  final WidgetBuilder builder;
  final List<String> keywords;

  /// The keywords [query] matched (every word must match something), or
  /// null when the section doesn't match. A title or subtitle match
  /// returns an empty list.
  List<String>? match(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return const [];
    final hits = <String>[];
    for (final w in words) {
      if (title.toLowerCase().contains(w) || subtitle.toLowerCase().contains(w)) continue;
      final k = keywords.where((k) => k.toLowerCase().contains(w)).toList();
      if (k.isEmpty) return null;
      for (final x in k) {
        if (!hits.contains(x)) hits.add(x);
      }
    }
    return hits;
  }
}

/// The sections a Toybox-only device shows (SPEC §7.2): there is nothing
/// else on it to set up.
const List<String> kToyboxOnlySettings = ['toybox', 'people', 'device', 'screensaver', 'hub', 'about'];

final List<SettingsSection> kSettingsSections = [
  SettingsSection('household', SettingsGroupKind.family, 'Household', 'Name, location, time zone, formats', Icons.home_rounded, (_) => const HouseholdSection(),
      keywords: const ['Name', 'Location', 'Address', 'ZIP code', 'Time zone', 'Units', 'Celsius', 'Fahrenheit', 'Metric', 'Week starts on', 'Clock', '24-hour clock']),
  SettingsSection('people', SettingsGroupKind.family, 'People', 'Family members, colors, PINs', Icons.people_alt_rounded, (_) => const PeopleSection(),
      keywords: const ['Family', 'Kids', 'Grown-ups', 'Colors', 'Faces', 'Photos', 'Birthdays', 'Grown-up PIN', 'Buddy', 'Stage', 'Nickname']),
  SettingsSection('kids', SettingsGroupKind.family, 'Kids & chores', 'Chores, routines, rewards', Icons.child_care_rounded, (_) => const KidsSection(),
      keywords: const ['Chores', 'Routines', 'Rewards', 'Stars', 'Stickers', 'Reward jar', 'Star goal', 'Approval']),
  SettingsSection('toybox', SettingsGroupKind.family, 'Toybox', 'Games, time and levels', Icons.toys_rounded, (_) => const ToyboxSection(),
      keywords: const ['Games', 'Time limit', 'Opening hours', 'Bedtime', 'Game volume', 'Levels']),
  SettingsSection('device', SettingsGroupKind.display, 'Screen & sound', 'Theme, size, volume, role', Icons.tablet_mac_rounded, (_) => const DeviceSection(),
      keywords: const ['Theme', 'Dark', 'Evening', 'Size', 'Text size', 'Viewing distance', 'Reduce motion', 'Animations', 'Brightness', 'Light sensor', 'Dimmer', 'Brighter', 'Volume',
        'Sound', 'Role', 'Orientation', 'Rotate', 'Effects', 'Performance', 'FreeKiosk', 'Kiosk', 'Restart this frame']),
  SettingsSection('screensaver', SettingsGroupKind.display, 'Photo frame & night', 'When it starts, what it shows, night hours', Icons.nightlight_round, (_) => const ScreensaverSection(),
      keywords: const ['Screensaver', 'Idle', 'Start after', 'Each photo', 'Clock and date', 'Current weather', 'Next event', 'Captions', 'Pan and zoom', 'At night', 'Night clock', 'Night schedule', 'Screen off', 'Room goes dark', 'Keep the screen on', 'Dim']),
  SettingsSection('calendars', SettingsGroupKind.services, 'Calendars', 'Google, subscriptions, birthdays', Icons.calendar_month_rounded, (_) => const CalendarsSection(),
      keywords: const ['Google Calendar', 'Subscribe', 'ICS', 'webcal', 'School calendar', 'Family calendar', 'Birthdays', 'Holidays', 'Family days', 'Colors']),
  SettingsSection('photos', SettingsGroupKind.services, 'Photos', 'Shared albums and folders', Icons.photo_library_rounded, (_) => const PhotosSection(),
      keywords: const ['Amazon Photos', 'Shared album', 'Folder', 'NAS', 'Photo sources']),
  SettingsSection('lists', SettingsGroupKind.services, 'Lists', 'Sync with Google Tasks', Icons.checklist_rounded, (_) => const ListsSection(),
      keywords: const ['Google Tasks', 'Shopping list', 'To-do']),
  SettingsSection('recipes', SettingsGroupKind.services, 'Recipes', 'Where searches look', Icons.restaurant_menu_rounded, (_) => const RecipesSection(),
      keywords: const ['Recipe sources', 'Spoonacular', 'TheMealDB', 'Tasty', 'RecipeAPI', 'API keys']),
  SettingsSection('weather', SettingsGroupKind.services, 'Weather', 'Forecast updates, your own station', Icons.wb_sunny_rounded, (_) => const WeatherSection(),
      keywords: const ['Forecast', 'Weather updates', 'Weather Underground', 'Weather station', 'API key']),
  SettingsSection('hub', SettingsGroupKind.system, 'Hub & devices', 'How this device runs, other screens', Icons.hub_rounded, (_) => const HubSection(),
      keywords: const ['Sync', 'Pairing', 'Devices', 'Enrollment code', 'On its own', 'Move to a Hub', 'Demo', 'Toybox mode', 'Disconnect']),
  SettingsSection('about', SettingsGroupKind.system, 'About', 'Version and licenses', Icons.info_outline_rounded, (_) => const AboutSection(),
      keywords: const ['Version', 'Licenses', 'Source code']),
];

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.section});
  final String? section;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final wide = !t.isPhone && MediaQuery.sizeOf(context).width >= 1000 * t.scale;
    final toyboxOnly = ref.watch(sessionProvider.select((s) => s.isToybox));
    final sections = [for (final s in kSettingsSections) if (!toyboxOnly || kToyboxOnlySettings.contains(s.id)) s];
    final current = sections.where((s) => s.id == widget.section).firstOrNull ?? (wide ? sections.first : null);
    final query = _query.text.trim();
    // While searching, the sections that match, each with the settings it matched.
    final shown = [
      for (final s in sections)
        if (s.match(query) case final hits?) (s, hits),
    ];

    final list = ListView(
      padding: EdgeInsets.zero,
      children: [
        DPageHeader(
          title: 'Settings',
          // No navigation bar on a Toybox-only device: the way back to the games.
          leading: toyboxOnly ? DIconButton(icon: Icons.arrow_back_rounded, label: 'Back to the Toybox', id: 'settings.toybox', tone: DButtonTone.ghost, onPressed: () => context.go('/toybox')) : null,
        ),
        SizedBox(height: t.space.md),
        DTextField(
          id: 'settings.search',
          controller: _query,
          hint: 'Search settings',
          prefix: Icon(Icons.search_rounded, color: t.colors.inkTertiary, size: t.iconMd),
          suffix: query.isEmpty
              ? null
              : DIconButton(
                  icon: Icons.close_rounded,
                  label: 'Clear the search',
                  id: 'settings.search.clear',
                  tone: DButtonTone.ghost,
                  onPressed: () => setState(_query.clear),
                ),
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
        ),
        SizedBox(height: t.space.sm),
        if (shown.isEmpty)
          Padding(
            padding: EdgeInsets.all(t.space.md),
            child: tid('settings.search.none', Text('Nothing in Settings matches “$query”', style: t.text.body.copyWith(color: t.colors.inkSecondary))),
          ),
        for (final (i, (s, hits)) in shown.indexed) ...[
          // Headings only for the full list: search results are few.
          if (query.isEmpty && (i == 0 || shown[i - 1].$1.group != s.group))
            Padding(
              padding: EdgeInsets.fromLTRB(t.space.md, i == 0 ? t.space.sm : t.space.lg, t.space.md, t.space.xs),
              child: tid('settings.group.${s.group.name}', Text(s.group.label.toUpperCase(), style: t.text.overline)),
            ),
          Padding(
            padding: EdgeInsets.only(bottom: t.space.xxs),
            child: _NavRow(section: s, hits: hits, selected: s == current, wide: wide, onTap: () => context.go('/settings/${s.id}')),
          ),
        ],
      ],
    );

    if (!wide) {
      if (current == null) return screenTid('screen.settings', Padding(padding: EdgeInsets.all(t.pageMargin), child: list));
      return screenTid(
        'screen.settings.${current.id}',
        ListView(
          padding: EdgeInsets.all(t.pageMargin),
          children: [
            DPageHeader(
              title: current.title,
              leading: DIconButton(icon: Icons.arrow_back_rounded, label: 'Settings', id: 'settings.back', tone: DButtonTone.ghost, onPressed: () => context.go('/settings')),
            ),
            SizedBox(height: t.space.lg),
            current.builder(context),
          ],
        ),
      );
    }
    return screenTid(
      'screen.settings',
      Padding(
        padding: EdgeInsets.all(t.pageMargin),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 380 * t.scale, child: list),
            SizedBox(width: t.gutter),
            Expanded(
              child: DCard(
                padding: EdgeInsets.zero,
                child: ListView(
                  key: ValueKey(current!.id),
                  padding: EdgeInsets.all(t.space.xl),
                  children: [
                    tid('settings.section.${current.id}', Text(current.title, style: t.text.h2)),
                    SizedBox(height: t.space.lg),
                    current.builder(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A section in the list: its icon, title, and what it holds (or, while
/// searching, the settings in it that matched).
class _NavRow extends StatelessWidget {
  const _NavRow({required this.section, required this.hits, required this.selected, required this.wide, required this.onTap});
  final SettingsSection section;
  final List<String> hits;
  final bool selected;
  final bool wide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final s = section;
    final lit = wide && selected;
    return DPressable(
      id: 'settings.nav.${s.id}',
      selected: selected,
      onTap: onTap,
      semanticLabel: hits.isEmpty ? s.title : '${s.title}: ${hits.join(', ')}',
      excludeSemantics: true,
      borderRadius: t.radius.card,
      child: AnimatedContainer(
        duration: DMotion.fast,
        padding: EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
        decoration: BoxDecoration(color: lit ? t.colors.accentTint : null, borderRadius: t.radius.card),
        child: Row(
          children: [
            Icon(s.icon, color: lit ? t.colors.accent : t.colors.inkSecondary, size: t.iconMd),
            SizedBox(width: t.space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.title, style: t.text.bodyStrong),
                  Text(hits.isEmpty ? s.subtitle : hits.join(' · '), style: t.text.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (!wide) Icon(Icons.chevron_right_rounded, color: t.colors.inkTertiary),
          ],
        ),
      ),
    );
  }
}

/// A labeled group inside a section.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.title, required this.children, this.footer});
  final String title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: t.space.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title.toUpperCase(), style: t.text.overline),
          SizedBox(height: t.space.sm),
          DecoratedBox(
            decoration: BoxDecoration(color: t.colors.surfaceSunken.withValues(alpha: 0.6), borderRadius: t.radius.card),
            child: Padding(padding: EdgeInsets.symmetric(vertical: t.space.xs), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
          ),
          if (footer != null) ...[SizedBox(height: t.space.xs), Text(footer!, style: t.text.caption)],
        ],
      ),
    );
  }
}

/// A row with a trailing segmented choice.
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({super.key, required this.title, required this.options, required this.value, required this.onChanged, this.subtitle, this.idPrefix});
  final String title;
  final String? subtitle;
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String? idPrefix;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final seg = DSegmented<T>(options: options, value: value, onChanged: onChanged, dense: true, idPrefix: idPrefix);
    if (t.isPhone) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: t.text.body.copyWith(fontWeight: FontWeight.w600)),
            if (subtitle != null) Text(subtitle!, style: t.text.caption),
            SizedBox(height: t.space.xs),
            SingleChildScrollView(scrollDirection: Axis.horizontal, child: seg),
          ],
        ),
      );
    }
    return DListRow(title: title, subtitle: subtitle, trailing: seg);
  }
}

/// Where an API key comes from, a field to paste it, and Save (or Remove):
/// pops ('save', key) or ('remove', ''). It owns its text controller, which
/// outlives the sheet's closing animation.
class KeySheet extends StatefulWidget {
  const KeySheet({super.key, required this.idPrefix, required this.help, required this.canRemove});
  final String idPrefix;
  final String help;
  final bool canRemove;

  @override
  State<KeySheet> createState() => _KeySheetState();
}

class _KeySheetState extends State<KeySheet> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.help, style: t.text.body),
        SizedBox(height: t.space.md),
        DTextField(id: '${widget.idPrefix}.input', controller: _input, hint: 'Paste the key', autofocus: true),
        SizedBox(height: t.space.lg),
        DButton(label: 'Save', expand: true, id: '${widget.idPrefix}.save', onPressed: () => Navigator.of(context).pop(('save', _input.text.trim()))),
        if (widget.canRemove) ...[
          SizedBox(height: t.space.sm),
          DButton(label: 'Remove the key', expand: true, tone: DButtonTone.outline, id: '${widget.idPrefix}.remove', onPressed: () => Navigator.of(context).pop(('remove', ''))),
        ],
      ],
    );
  }
}
