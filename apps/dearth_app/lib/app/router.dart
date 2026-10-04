import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/providers.dart';
import '../core/sync/hub_api.dart';
import '../features/calendar/calendar_screen.dart';
import '../features/home/home_screen.dart';
import '../features/kids/kids_screen.dart';
import '../features/lists/lists_screen.dart';
import '../features/meals/meals_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/photos/photos_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/toybox/toybox_screen.dart';
import '../features/weather/weather_screen.dart';
import 'shell.dart';

/// Routes (hash URLs on web, so any static host works). Unpaired devices
/// land on onboarding; everything else lives in the navigation shell.
final routerProvider = Provider<GoRouter>((ref) {
  final ready = ValueNotifier<bool>(ref.read(sessionProvider).isReady);
  ref.listen(sessionProvider.select((s) => s.isReady), (_, v) => ready.value = v);

  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: ready,
    redirect: (context, state) {
      final onWelcome = state.matchedLocation == '/welcome';
      if (!ready.value) return onWelcome ? null : '/welcome';
      if (onWelcome) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/welcome', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/pair/:code', builder: (_, state) => PairApprovalScreen(code: state.pathParameters['code']!)),
      StatefulShellRoute(
        builder: (context, state, shell) => shell,
        navigatorContainerBuilder: (context, shell, children) => AppShell(shell: shell, children: children),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/calendar', builder: (_, _) => const CalendarScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/meals', builder: (_, _) => const MealsScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/lists',
              builder: (_, _) => const ListsScreen(),
              routes: [GoRoute(path: ':id', builder: (_, state) => ListsScreen(listId: state.pathParameters['id']))],
            ),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: '/kids', builder: (_, _) => const KidsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/toybox', builder: (_, _) => const ToyboxScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/weather', builder: (_, _) => const WeatherScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/photos', builder: (_, _) => const PhotosScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/settings',
              builder: (_, _) => const SettingsScreen(),
              routes: [GoRoute(path: ':section', builder: (_, state) => SettingsScreen(section: state.pathParameters['section']))],
            ),
          ]),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    ready.dispose();
  });
  return router;
});

/// Opened from the Hub's pairing QR code on an admin phone (SPEC §9.2).
class PairApprovalScreen extends ConsumerStatefulWidget {
  const PairApprovalScreen({super.key, required this.code});
  final String code;

  @override
  ConsumerState<PairApprovalScreen> createState() => _PairApprovalScreenState();
}

class _PairApprovalScreenState extends ConsumerState<PairApprovalScreen> {
  bool _busy = false;
  String? _result;

  Future<void> _approve() async {
    final api = ref.read(hubApiProvider);
    if (api == null) return;
    setState(() => _busy = true);
    try {
      await api.post('/api/admin/pair/approve', {'code': widget.code});
      setState(() => _result = 'Approved! The new display connects in a moment.');
    } on HubApiException catch (e) {
      setState(() => _result = e.friendly);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = DTheme.of(context);
    final admin = ref.watch(sessionProvider.select((s) => s.admin && s.isHub));
    return Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(t.space.xl),
          child: DEmptyState(
            id: 'pair.approve',
            emoji: _result == null ? '📲' : '✅',
            title: _result ?? 'Approve display ${widget.code}?',
            message: admin ? null : 'Only an admin device can approve new displays.',
            action: _result != null
                ? DButton(label: 'Done', onPressed: () => context.go('/'))
                : DButton(label: 'Approve', id: 'pair.approve.ok', busy: _busy, onPressed: admin ? _approve : null),
          ),
        ),
      ),
    );
  }
}
