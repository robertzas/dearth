import 'dart:async';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/env.dart';
import '../../core/providers.dart';
import '../../core/sync/hub_api.dart';
import '../photos/art_pack.dart';

enum _Step { welcome, connect, pairing }

/// First run (SPEC FR-SET-01): connect to a Hub (pair) or explore the demo.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  _Step _step = _Step.welcome;
  final _hub = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  String _role = DeviceRole.kitchen;
  bool _busy = false;
  String? _error;
  bool _originIsHub = false;
  HubApi? _api;
  PairingTicket? _ticket;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    final env = ref.read(envProvider);
    _hub.text = env.hubUrl ?? AppEnv.webOrigin ?? '';
    _probeOrigin();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_name.text.isEmpty) {
      final phone = MediaQuery.sizeOf(context).shortestSide < 600;
      _name.text = phone ? 'My phone' : 'Kitchen display';
      _role = phone ? DeviceRole.personal : DeviceRole.kitchen;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _hub.dispose();
    _name.dispose();
    _password.dispose();
    _code.dispose();
    _api?.close();
    super.dispose();
  }

  /// On web, the page is usually served by the Hub itself.
  Future<void> _probeOrigin() async {
    final origin = AppEnv.webOrigin;
    if (origin == null) return;
    final api = HubApi(Uri.parse(origin));
    try {
      final h = await api.health();
      if (mounted && h['ok'] == true) setState(() => _originIsHub = true);
    } on Object {
      // Not a Hub (dev server, static hosting).
    } finally {
      api.close();
    }
  }

  Future<void> _demo() async {
    setState(() => _busy = true);
    await ref.read(sessionProvider.notifier).startDemo(role: MediaQuery.sizeOf(context).shortestSide < 600 ? DeviceRole.personal : null);
  }

  Future<void> _connect() async {
    final base = HubApi.parseBase(_hub.text);
    if (base == null) {
      setState(() => _error = 'Enter the Hub’s address, like 10.0.1.20:8080');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = HubApi(base);
    try {
      await api.health();
      final ticket = await api.startPairing(name: _name.text.trim().isEmpty ? 'Display' : _name.text.trim(), platform: AppEnv.platformName, role: _role);
      _api?.close();
      _api = api;
      setState(() {
        _ticket = ticket;
        _step = _Step.pairing;
      });
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
      unawaited(_check());
    } on HubApiException catch (e) {
      api.close();
      setState(() => _error = e.friendly);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    final api = _api, ticket = _ticket;
    if (api == null || ticket == null) return;
    try {
      final r = await api.pairingStatus(ticket);
      if (r.approved) {
        _poll?.cancel();
        await _finish(api.base, r);
      } else if (r.status == 'expired' || r.status == 'unknown') {
        _poll?.cancel();
        if (mounted) setState(() => _error = 'That code expired. Start again.');
      }
    } on HubApiException {
      // Keep polling through blips.
    }
  }

  Future<void> _approveWithPassword() async {
    final api = _api, ticket = _ticket;
    if (api == null || ticket == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await api.approveWithPassword(_password.text, ticket.code, role: _role, name: _name.text.trim());
      await _check();
    } on HubApiException catch (e) {
      setState(() => _error = e.friendly);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _claim() async {
    final base = HubApi.parseBase(_hub.text);
    if (base == null || _code.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = HubApi(base);
    try {
      final r = await api.claim(_code.text.trim(), platform: AppEnv.platformName, name: _name.text.trim());
      if (r.approved) await _finish(base, r);
    } on HubApiException catch (e) {
      setState(() => _error = e.friendly);
    } finally {
      api.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish(Uri base, PairResult r) async {
    await ref.read(sessionProvider.notifier).pairedWith(base, r, name: _name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final card = Container(
      constraints: BoxConstraints(maxWidth: 720 * t.scale),
      margin: EdgeInsets.all(t.space.lg),
      padding: EdgeInsets.all(t.isPhone ? t.space.lg : t.space.xxl),
      decoration: BoxDecoration(
        color: t.colors.surfaceRaised.withValues(alpha: 0.94),
        borderRadius: t.radius.sheet,
        boxShadow: t.elevation.e2,
      ),
      child: AnimatedSize(
        duration: t.motion(DMotion.standard),
        curve: DMotion.standardCurve,
        child: switch (_step) {
          _Step.welcome => _welcome(t),
          _Step.connect => _connectForm(t),
          _Step.pairing => _pairing(t),
        },
      ),
    );
    return screenTid(
      'screen.onboarding',
      Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            const ArtScene(0),
            SafeArea(child: Center(child: SingleChildScrollView(child: card))),
          ],
        ),
      ),
    );
  }

  Widget _welcome(DTheme t) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 64 * t.scale,
                height: 64 * t.scale,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: t.colors.accent, borderRadius: t.radius.card),
                child: Text('D', style: t.text.h1.copyWith(color: t.colors.onAccent)),
              ),
              SizedBox(width: t.space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Welcome to Dearth', style: t.text.h1),
                    Text('Your family’s calendar, meals, chores and photos — on your own hardware.', style: t.text.body.copyWith(color: t.colors.inkSecondary)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: t.space.xl),
          _OptionCard(
            id: 'onboarding.hub',
            emoji: '🏠',
            title: _originIsHub ? 'Connect to this Hub' : 'Connect to your Hub',
            subtitle: _originIsHub ? Uri.parse(_hub.text).authority : 'Sync with the Dearth Hub running at home',
            onTap: () => setState(() => _step = _Step.connect),
          ),
          SizedBox(height: t.space.md),
          _OptionCard(
            id: 'onboarding.demo',
            emoji: '🧪',
            title: 'Explore the demo',
            subtitle: 'A sample family, right on this device. Nothing leaves it.',
            busy: _busy,
            onTap: _busy ? null : _demo,
          ),
        ],
      );

  Widget _connectForm(DTheme t) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              DIconButton(icon: Icons.arrow_back_rounded, label: 'Back', tone: DButtonTone.ghost, onPressed: () => setState(() => _step = _Step.welcome)),
              SizedBox(width: t.space.sm),
              Text('Connect to your Hub', style: t.text.h2),
            ],
          ),
          SizedBox(height: t.space.lg),
          DTextField(id: 'onboarding.hub.url', controller: _hub, label: 'Hub address', hint: '10.0.1.20:8080 or https://dearth.example.com', keyboardType: TextInputType.url),
          SizedBox(height: t.space.md),
          DTextField(id: 'onboarding.name', controller: _name, label: 'Name this device'),
          SizedBox(height: t.space.md),
          Text('THIS SCREEN IS A…', style: t.text.overline),
          SizedBox(height: t.space.xs),
          Wrap(
            spacing: t.space.xs,
            runSpacing: t.space.xs,
            children: [
              DChip(id: 'onboarding.role.kitchen', label: 'Wall display', emoji: '🖼️', selected: _role == DeviceRole.kitchen, onTap: () => setState(() => _role = DeviceRole.kitchen)),
              DChip(id: 'onboarding.role.personal', label: 'Phone or laptop', emoji: '📱', selected: _role == DeviceRole.personal, onTap: () => setState(() => _role = DeviceRole.personal)),
            ],
          ),
          if (_error != null) ...[SizedBox(height: t.space.md), DBanner(title: _error!, tone: DBannerTone.danger, id: 'onboarding.error')],
          SizedBox(height: t.space.lg),
          DButton(label: 'Connect', id: 'onboarding.connect', size: DButtonSize.lg, expand: true, busy: _busy, onPressed: _connect),
          SizedBox(height: t.space.lg),
          Text('HAVE AN ENROLLMENT CODE?', style: t.text.overline),
          SizedBox(height: t.space.xs),
          Row(
            children: [
              Expanded(child: DTextField(id: 'onboarding.code', controller: _code, hint: 'ABCD2345')),
              SizedBox(width: t.space.sm),
              DButton(label: 'Use code', tone: DButtonTone.tonal, id: 'onboarding.code.use', onPressed: _busy ? null : _claim),
            ],
          ),
        ],
      );

  Widget _pairing(DTheme t) {
    final ticket = _ticket!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Approve this device', style: t.text.h2),
        SizedBox(height: t.space.xs),
        Text('On a grown-up’s phone or the Hub admin, approve this code. You can also scan the QR code.', style: t.text.body.copyWith(color: t.colors.inkSecondary)),
        SizedBox(height: t.space.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(t.space.sm),
              decoration: BoxDecoration(color: Colors.white, borderRadius: t.radius.card),
              child: QrImageView(data: ticket.approveUrl, size: 168 * t.scale, padding: EdgeInsets.zero),
            ),
            SizedBox(width: t.space.xl),
            Column(
              children: [
                tid('onboarding.pair.code', Text(ticket.code, style: t.text.display.copyWith(letterSpacing: 8 * t.scale))),
                SizedBox(height: t.space.sm),
                Row(
                  children: [
                    SizedBox.square(dimension: 18 * t.scale, child: CircularProgressIndicator(strokeWidth: 2.5 * t.scale)),
                    SizedBox(width: t.space.sm),
                    Text('Waiting for approval…', style: t.text.caption),
                  ],
                ),
              ],
            ),
          ],
        ),
        SizedBox(height: t.space.xl),
        Text('FIRST DEVICE? USE THE HUB’S ADMIN PASSWORD', style: t.text.overline),
        SizedBox(height: t.space.xs),
        Row(
          children: [
            Expanded(child: DTextField(id: 'onboarding.password', controller: _password, hint: 'Admin password', obscure: true, onSubmitted: (_) => _approveWithPassword())),
            SizedBox(width: t.space.sm),
            DButton(label: 'Approve', id: 'onboarding.password.approve', tone: DButtonTone.tonal, busy: _busy, onPressed: _approveWithPassword),
          ],
        ),
        if (_error != null) ...[SizedBox(height: t.space.md), DBanner(title: _error!, tone: DBannerTone.danger, id: 'onboarding.error')],
        SizedBox(height: t.space.md),
        DButton(
          label: 'Cancel',
          tone: DButtonTone.ghost,
          onPressed: () {
            _poll?.cancel();
            setState(() {
              _step = _Step.connect;
              _ticket = null;
            });
          },
        ),
      ],
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.id, required this.emoji, required this.title, required this.subtitle, required this.onTap, this.busy = false});
  final String id;
  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    return DPressable(
      id: id,
      onTap: onTap,
      semanticLabel: '$title. $subtitle',
      excludeSemantics: true,
      borderRadius: t.radius.card,
      child: Container(
        padding: EdgeInsets.all(t.space.lg),
        decoration: BoxDecoration(color: t.colors.surfaceSunken, borderRadius: t.radius.card),
        child: Row(
          children: [
            DEmoji(emoji, size: 52 * t.scale),
            SizedBox(width: t.space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.text.title),
                  Text(subtitle, style: t.text.caption),
                ],
              ),
            ),
            if (busy)
              SizedBox.square(dimension: 28 * t.scale, child: const CircularProgressIndicator())
            else
              Icon(Icons.arrow_forward_rounded, color: t.colors.accent, size: t.iconMd),
          ],
        ),
      ),
    );
  }
}
