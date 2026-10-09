import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/providers.dart';
import '../../../core/sync/hub_api.dart';

/// Moves a household running on its own to a Hub (SPEC §7.2): the Hub's
/// address and admin password, then the copy, with its progress.
Future<void> showMoveToHubSheet(BuildContext context) => showDSheet<void>(context, title: 'Move to a Hub', id: 'hub.move.sheet', builder: (_) => const _MoveSheet(toHub: true));

/// Moves this device off its Hub to run on its own, bringing a copy of the
/// family's data (SPEC §7.2).
Future<void> showRunOnItsOwnSheet(BuildContext context) =>
    showDSheet<void>(context, title: 'Run this device on its own', id: 'hub.solo.sheet', builder: (_) => const _MoveSheet(toHub: false));

class _MoveSheet extends ConsumerStatefulWidget {
  const _MoveSheet({required this.toHub});
  final bool toHub;

  @override
  ConsumerState<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends ConsumerState<_MoveSheet> {
  final _url = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _step;
  double? _fraction;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final session = ref.read(sessionProvider);
    final target = widget.toHub ? HubApi.parseBase(_url.text) : null;
    final needsPassword = widget.toHub || !session.admin;
    final problem = widget.toHub && target == null
        ? 'Enter the Hub’s address, like 10.0.1.20:8080'
        : needsPassword && _password.text.isEmpty
            ? 'Enter the Hub’s admin password: copying a household in or out needs it.'
            : null;
    setState(() => _error = problem);
    if (problem != null) return;
    setState(() => _busy = true);
    void progress(String step, double? fraction) {
      if (mounted) {
        setState(() {
          _step = step;
          _fraction = fraction;
        });
      }
    }

    final controller = ref.read(sessionProvider.notifier);
    try {
      if (widget.toHub) {
        await controller.moveToHub(target!, _password.text, onProgress: progress);
      } else {
        await controller.runOnThisDevice(password: needsPassword ? _password.text : null, onProgress: progress);
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = null;
        _error = switch (e) {
          HubApiException(status: 403) => 'That admin password isn’t right.',
          HubApiException(code: 'network') => widget.toHub ? 'Couldn’t reach a Hub at that address.' : 'Couldn’t reach the Hub.',
          HubApiException(:final friendly) => friendly,
          _ => 'Something went wrong: $e',
        };
      });
      return;
    }
    ref.read(toastProvider).show(widget.toHub ? 'Moved to the Hub' : 'Running on its own', emoji: '✅');
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final session = ref.watch(sessionProvider);
    final needsPassword = widget.toHub || !session.admin;
    final explain = widget.toHub
        ? 'Everything on this device goes to the Hub: people, calendars, lists, meals, chores, stars, photos and pictures. '
            'Where the Hub already has the same settings, this household’s win. This device then syncs with the Hub, and other screens can join it.'
        : 'This device starts its own Hub and copies the family’s data from ${Uri.tryParse(session.hubUrl ?? '')?.authority ?? 'the Hub'}: people, calendars, lists, meals, chores, stars, photos and pictures. '
            'The Hub keeps its copy and the other screens stay with it; from then on, changes here stay here.';
    return PopScope(
      canPop: !_busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(explain, style: t.text.body.copyWith(color: t.colors.inkSecondary)),
          SizedBox(height: t.space.lg),
          if (widget.toHub) ...[
            DTextField(id: 'hub.move.url', controller: _url, label: 'Hub address', hint: '10.0.1.20:8080 or https://dearth.example.com', keyboardType: TextInputType.url),
            SizedBox(height: t.space.md),
          ],
          if (needsPassword) ...[
            DTextField(id: 'hub.move.password', controller: _password, label: 'The Hub’s admin password', obscure: true, onSubmitted: (_) => _busy ? null : _go()),
            SizedBox(height: t.space.md),
          ],
          Padding(
            padding: EdgeInsets.only(bottom: t.space.md),
            child: Text('Integration keys and Google sign-ins don’t move: connect them again in Settings afterwards.', style: t.text.caption),
          ),
          if (_step != null) ...[
            tid('hub.move.step', Text(_step!, style: t.text.bodyStrong)),
            SizedBox(height: t.space.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(4 * t.scale),
              child: LinearProgressIndicator(value: _fraction, minHeight: 6 * t.scale, color: t.colors.accent, backgroundColor: t.colors.surfaceSunken),
            ),
            SizedBox(height: t.space.md),
          ],
          if (_error != null) ...[DBanner(title: _error!, tone: DBannerTone.danger, id: 'hub.move.error'), SizedBox(height: t.space.md)],
          DButton(
            label: widget.toHub ? 'Move to the Hub' : 'Run on its own',
            id: 'hub.move.go',
            size: DButtonSize.lg,
            expand: true,
            busy: _busy,
            onPressed: _busy ? null : _go,
          ),
        ],
      ),
    );
  }
}
