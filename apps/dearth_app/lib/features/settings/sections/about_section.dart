import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/env.dart';
import '../../../core/providers.dart';
import '../settings_screen.dart';

class AboutSection extends ConsumerWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = DTheme.of(context);
    final env = ref.watch(envProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 72 * t.scale,
              height: 72 * t.scale,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: t.colors.accent, borderRadius: t.radius.card),
              child: Text('D', style: t.text.h1.copyWith(color: t.colors.onAccent)),
            ),
            SizedBox(width: t.space.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dearth', style: t.text.h2),
                tid('about.version', Text('Version ${env.appVersion} · ${AppEnv.platformName}', style: t.text.caption)),
              ],
            ),
          ],
        ),
        SizedBox(height: t.space.lg),
        Text(
          'A family command center for wall displays: shared calendar, meals, chores, a toddler toybox, music, photos and weather. '
          'No subscription, no vendor cloud — your data stays on your own Hub.',
          style: t.text.body,
        ),
        SizedBox(height: t.space.lg),
        SettingsGroup(
          title: 'Open source',
          footer: 'Licensed under AGPL-3.0. Fonts: Plus Jakarta Sans and Fredoka (SIL OFL). Weather data by Open-Meteo.com (CC BY 4.0).',
          children: [
            DListRow(
              title: 'Source code',
              subtitle: 'github.com/robertzas/dearth',
              chevron: true,
              onTap: () => launchUrl(Uri.parse('https://github.com/robertzas/dearth'), mode: LaunchMode.externalApplication),
            ),
            DListRow(
              id: 'about.licenses',
              title: 'Open-source licenses',
              chevron: true,
              onTap: () => showLicensePage(context: context, applicationName: 'Dearth', applicationVersion: env.appVersion),
            ),
          ],
        ),
      ],
    );
  }
}
