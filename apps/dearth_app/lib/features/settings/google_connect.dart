import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/sync/hub_api.dart';

/// Starts Google sign-in on the Hub (SPEC §13.2): in the browser when the
/// Hub has an HTTPS callback, else the paste-back flow. [purpose] asks for
/// one more permission than the calendars ("tasks" for list sync, "photos").
Future<void> connectGoogle(BuildContext context, WidgetRef ref, HubApi api, {String? purpose}) async {
  try {
    final r = await api.get('/api/admin/oauth/google/start', {'purpose': ?purpose});
    if (!context.mounted) return;
    await continueGoogleSignIn(context, ref, api, r);
  } on HubApiException catch (e) {
    ref.read(toastProvider).show(e.friendly, emoji: '⚠️', tone: DBannerTone.warning);
  }
}

/// Finishes a Google consent the Hub started ([start] holds its `url` and
/// `mode`). [onDone] gets the Hub's reply when it comes back here (the
/// paste-back flow); a browser callback ends on the Hub's own page.
Future<void> continueGoogleSignIn(BuildContext context, WidgetRef ref, HubApi api, Map<String, Object?> start, {void Function(Map<String, Object?> reply)? onDone}) async {
  final url = Uri.parse(start['url']! as String);
  if (start['mode'] == 'callback') {
    await launchUrl(url, mode: LaunchMode.externalApplication);
    ref.read(toastProvider).show('Finish signing in in the browser', emoji: '🌐');
    return;
  }
  await _pasteBack(context, ref, api, url, onDone: onDone);
}

/// Without an HTTPS domain the admin pastes the final redirect URL back
/// (SPEC §13.2 paste-back flow).
Future<void> _pasteBack(BuildContext context, WidgetRef ref, HubApi api, Uri url, {void Function(Map<String, Object?> reply)? onDone}) async {
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
    onDone == null ? ref.read(toastProvider).show('Connected ${r['email']}', emoji: '✅') : onDone(r);
  } on HubApiException catch (e) {
    ref.read(toastProvider).show(e.friendly, emoji: '⚠️', tone: DBannerTone.warning);
  }
}
