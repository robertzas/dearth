import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'sections/about_section.dart';
import 'sections/calendars_section.dart';
import 'sections/device_section.dart';
import 'sections/household_section.dart';
import 'sections/hub_section.dart';
import 'sections/kids_section.dart';
import 'sections/people_section.dart';
import 'sections/screensaver_section.dart';
import 'sections/toybox_section.dart';

/// A settings section (SPEC FR-SET-03).
class SettingsSection {
  const SettingsSection(this.id, this.title, this.subtitle, this.icon, this.builder);
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final WidgetBuilder builder;
}

final List<SettingsSection> kSettingsSections = [
  SettingsSection('household', 'Household', 'Name, location, units, time', Icons.home_rounded, (_) => const HouseholdSection()),
  SettingsSection('people', 'People', 'Family members, colors, PINs', Icons.people_alt_rounded, (_) => const PeopleSection()),
  SettingsSection('kids', 'Kids & chores', 'Chores, routines, rewards', Icons.child_care_rounded, (_) => const KidsSection()),
  SettingsSection('toybox', 'Toybox', 'Games, time and levels', Icons.toys_rounded, (_) => const ToyboxSection()),
  SettingsSection('device', 'This display', 'Theme, size, idle, night', Icons.tablet_mac_rounded, (_) => const DeviceSection()),
  SettingsSection('calendars', 'Calendars', 'Sources, colors, subscriptions', Icons.calendar_month_rounded, (_) => const CalendarsSection()),
  SettingsSection('screensaver', 'Photo frame & night', 'Screensaver and quiet hours', Icons.photo_rounded, (_) => const ScreensaverSection()),
  SettingsSection('hub', 'Hub & devices', 'Sync, pairing, devices', Icons.hub_rounded, (_) => const HubSection()),
  SettingsSection('about', 'About', 'Version and licenses', Icons.info_outline_rounded, (_) => const AboutSection()),
];

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.section});
  final String? section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final wide = !t.isPhone && MediaQuery.sizeOf(context).width >= 1000 * t.scale;
    final current = kSettingsSections.where((s) => s.id == section).firstOrNull ?? (wide ? kSettingsSections.first : null);

    final list = ListView(
      padding: EdgeInsets.zero,
      children: [
        const DPageHeader(title: 'Settings'),
        SizedBox(height: t.space.md),
        for (final s in kSettingsSections)
          Padding(
            padding: EdgeInsets.only(bottom: t.space.xxs),
            child: DPressable(
              id: 'settings.nav.${s.id}',
              selected: s == current,
              onTap: () => context.go('/settings/${s.id}'),
              semanticLabel: s.title,
              excludeSemantics: true,
              borderRadius: t.radius.card,
              child: AnimatedContainer(
                duration: DMotion.fast,
                padding: EdgeInsets.symmetric(horizontal: t.space.md, vertical: t.space.sm),
                decoration: BoxDecoration(color: wide && s == current ? t.colors.accentTint : null, borderRadius: t.radius.card),
                child: Row(
                  children: [
                    Icon(s.icon, color: wide && s == current ? t.colors.accent : t.colors.inkSecondary, size: t.iconMd),
                    SizedBox(width: t.space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.title, style: t.text.bodyStrong),
                          Text(s.subtitle, style: t.text.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    if (!wide) Icon(Icons.chevron_right_rounded, color: t.colors.inkTertiary),
                  ],
                ),
              ),
            ),
          ),
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
