import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/sync/hub_api.dart';

/// The Hub's Google setup: whether it holds the family's OAuth client
/// (`hasClient`), the redirect URI that client needs, and the accounts.
/// Null without a Hub, or on a display that isn't an admin.
final googleSetupProvider = FutureProvider.autoDispose<Map<String, Object?>?>((ref) async {
  final api = ref.watch(hubApiProvider);
  if (api == null || !ref.watch(sessionProvider.select((s) => s.admin))) return null;
  final r = await api.get('/api/admin/integrations');
  return r['google'] as Map<String, Object?>? ?? const {};
});

/// Starts Google sign-in on the Hub (SPEC §13.2): in the browser when the
/// Hub has an HTTPS callback, else the paste-back flow. [purpose] asks for
/// one more permission than the calendars ("tasks" for list sync, "photos").
/// A Hub without the family's OAuth client asks for it first.
Future<void> connectGoogle(BuildContext context, WidgetRef ref, HubApi api, {String? purpose, bool askedForClient = false}) async {
  try {
    final r = await api.get('/api/admin/oauth/google/start', {'purpose': ?purpose});
    if (!context.mounted) return;
    await continueGoogleSignIn(context, ref, api, r);
  } on HubApiException catch (e) {
    if (e.code == 'google_client_required' && !askedForClient && context.mounted) {
      if (await setUpGoogleClient(context, ref, api) && context.mounted) await connectGoogle(context, ref, api, purpose: purpose, askedForClient: true);
      return;
    }
    ref.read(toastProvider).show(e.friendly, emoji: '⚠️', tone: DBannerTone.warning);
  }
}

/// Asks for the family's own Google OAuth client (SPEC §13.2: each family
/// makes one in its own Google Cloud project) and saves it on the Hub, which
/// keeps the secret. True once saved.
Future<bool> setUpGoogleClient(BuildContext context, WidgetRef ref, HubApi api) async {
  final Map<String, Object?> setup;
  try {
    setup = (await api.get('/api/admin/integrations'))['google'] as Map<String, Object?>? ?? const {};
  } on HubApiException catch (e) {
    ref.read(toastProvider).show(e.friendly, emoji: '⚠️', tone: DBannerTone.warning);
    return false;
  }
  if (!context.mounted) return false;
  final client = await showDSheet<(String, String)>(
    context,
    title: 'Google sign-in',
    id: 'google.client.sheet',
    builder: (sheet) => GoogleClientSheet(redirectUri: setup['redirectUri'] as String? ?? '', replacing: setup['hasClient'] == true),
  );
  if (client == null) return false;
  try {
    await api.put('/api/admin/integrations/google', {'clientId': client.$1, 'clientSecret': client.$2});
  } on HubApiException catch (e) {
    ref.read(toastProvider).show(e.friendly, emoji: '⚠️', tone: DBannerTone.warning);
    return false;
  }
  ref.invalidate(googleSetupProvider);
  ref.read(toastProvider).show('Saved on the Hub', emoji: '🔑');
  return true;
}

/// How to make a Google OAuth client, the redirect URI to give it, and
/// fields for its ID and secret. Pops (clientId, clientSecret). The README's
/// "Google Calendar" section has the long version.
class GoogleClientSheet extends StatefulWidget {
  const GoogleClientSheet({super.key, required this.redirectUri, required this.replacing});
  final String redirectUri;

  /// The Hub has a client already: accounts connected through it stop syncing.
  final bool replacing;

  @override
  State<GoogleClientSheet> createState() => _GoogleClientSheetState();
}

class _GoogleClientSheetState extends State<GoogleClientSheet> {
  final _id = TextEditingController();
  final _secret = TextEditingController();
  String? _idError, _secretError;
  bool _copied = false;

  @override
  void dispose() {
    _id.dispose();
    _secret.dispose();
    super.dispose();
  }

  void _save() {
    final id = _id.text.trim(), secret = _secret.text.trim();
    setState(() {
      _idError = id.endsWith('.apps.googleusercontent.com') ? null : 'A client ID ends in .apps.googleusercontent.com';
      _secretError = secret.isEmpty ? 'Paste the client secret too' : null;
    });
    if (_idError == null && _secretError == null) Navigator.of(context).pop((id, secret));
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    Widget step(String text) => Padding(padding: EdgeInsets.only(bottom: t.space.sm), child: Text(text, style: t.text.body));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Google lets Dearth in through a sign-in app of your own, made once in Google Cloud. It’s free, and the secret stays on the Hub.',
            style: t.text.body.copyWith(color: t.colors.inkSecondary)),
        SizedBox(height: t.space.md),
        step('1. At console.cloud.google.com, make a project and enable the Google Calendar API (and the Google Tasks API to sync lists).'),
        step('2. Under Google Auth Platform, set the audience to External and publish the app (In production). In Testing, Google signs Dearth out every 7 days.'),
        step('3. Under Clients, create a Web application client with this authorized redirect URI:'),
        Container(
          padding: EdgeInsets.symmetric(horizontal: t.space.sm, vertical: t.space.xs),
          decoration: BoxDecoration(color: t.colors.surfaceSunken, borderRadius: BorderRadius.circular(t.radius.s)),
          child: Row(
            children: [
              Expanded(child: tid('google.client.redirect', Text(widget.redirectUri, style: t.text.bodyStrong))),
              DButton(
                label: _copied ? 'Copied' : 'Copy',
                id: 'google.client.copy',
                tone: DButtonTone.ghost,
                size: DButtonSize.sm,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: widget.redirectUri));
                  if (mounted) setState(() => _copied = true);
                },
              ),
            ],
          ),
        ),
        SizedBox(height: t.space.md),
        step('4. Paste the client’s ID and secret here.'),
        DTextField(id: 'google.client.id', controller: _id, label: 'Client ID', hint: '…apps.googleusercontent.com', errorText: _idError),
        SizedBox(height: t.space.sm),
        DTextField(id: 'google.client.secret', controller: _secret, label: 'Client secret', hint: 'GOCSPX-…', obscure: true, errorText: _secretError, onSubmitted: (_) => _save()),
        if (widget.replacing) ...[
          SizedBox(height: t.space.sm),
          Text('Accounts connected through the old client stop syncing: connect them again afterwards.', style: t.text.caption),
        ],
        SizedBox(height: t.space.lg),
        DButton(label: 'Save', id: 'google.client.save', expand: true, onPressed: _save),
      ],
    );
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
