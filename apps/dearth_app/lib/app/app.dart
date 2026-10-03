import 'dart:async';
import 'dart:ui' as ui;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_ui/dearth_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/data/household.dart';
import '../core/env.dart';
import '../core/platform/platform.dart';
import '../core/providers.dart';
import '../core/sync/sync_client.dart';
import '../features/photos/screensaver.dart';
import '../features/timers/timers.dart';
import 'display_state.dart';
import 'grown_up.dart';
import 'reminders.dart';
import 'router.dart';

/// Root of the app: router + theme frame.
class DearthApp extends ConsumerWidget {
  const DearthApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // Keep the sync client alive for the whole session.
    ref.watch(syncClientProvider);
    return MaterialApp.router(
      title: 'Dearth',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: _fallbackTheme,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en', 'US'), Locale('en')],
      builder: (context, child) => AppFrame(child: child ?? const SizedBox.shrink()),
    );
  }
}

final ThemeData _fallbackTheme = buildThemeData(
  DTheme(colors: DColors.light, scale: 1, displayClass: DisplayClass.tablet, policy: TierPolicy.of(PerfTier.t2)),
);

/// Global key of the root repaint boundary (remote screenshots, FR-ADM-02).
final GlobalKey screenshotBoundaryKey = GlobalKey(debugLabel: 'screenshot');

/// Computes tokens for this device (display class, uiScale, tier, theme) and
/// hosts app-wide layers: toasts, idle tracking, screensaver/night.
class AppFrame extends ConsumerStatefulWidget {
  const AppFrame({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppFrame> createState() => _AppFrameState();
}

class _AppFrameState extends ConsumerState<AppFrame> with WidgetsBindingObserver {
  Object? _themeKey;
  ThemeData? _theme;
  DTheme? _dt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.read(syncClientProvider)?.nudge();
  }

  @override
  void didHaveMemoryPressure() {
    // SPEC §12.6: drop decoded images under memory pressure.
    PaintingBinding.instance.imageCache.clear();
  }

  DTheme _resolveTheme(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final dc = resolveDisplayClass(size);
    final s = ref.watch(deviceSettingsProvider);
    final mode = ref.watch(themeModeProvider);
    final tier = ref.watch(perfTierProvider);
    final reduced = s.reducedMotion || MediaQuery.disableAnimationsOf(context) || ref.watch(envProvider).e2e;
    final scale = computeUiScale(
      logicalSize: size,
      devicePixelRatio: dpr,
      displayClass: dc,
      diagonalInches: s.diagonalIn,
      distance: ViewingDistance.parse(s.viewingDistance),
      userScale: s.userScale,
    );
    final key = (mode, (scale * 100).round(), dc, tier, reduced);
    if (key != _themeKey || _dt == null) {
      _themeKey = key;
      _dt = DTheme(colors: DColors.of(mode), scale: (scale * 100).round() / 100, displayClass: dc, policy: TierPolicy.of(tier), reducedMotion: reduced);
      _theme = buildThemeData(_dt!);
      PaintingBinding.instance.imageCache.maximumSizeBytes = TierPolicy.of(tier).imageCacheMb << 20;
    }
    return _dt!;
  }

  @override
  Widget build(BuildContext context) {
    _resolveTheme(context);
    final display = ref.watch(displayProvider.select((d) => d.mode));
    final active = display == DisplayMode.active;
    // Finished timers ring on every display, whatever it shows (FR-TMR-01).
    ref.listen(timerAlarmProvider, (_, _) {});
    return Theme(
      data: _theme!,
      child: _Effects(
        child: RepaintBoundary(
          key: screenshotBoundaryKey,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) {
              if (ref.read(displayProvider).mode == DisplayMode.active) ref.read(displayProvider.notifier).activity();
              ref.read(grownUpProvider.notifier).touch();
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                Offstage(
                  offstage: !active,
                  child: TickerMode(
                    enabled: active,
                    child: DToastHost(controller: ref.watch(toastProvider), child: widget.child),
                  ),
                ),
                const _DisplayLayer(),
                const ReminderLayer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Screensaver, night clock or off, above the app (SPEC §10.12).
class _DisplayLayer extends ConsumerWidget {
  const _DisplayLayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(displayProvider.select((d) => d.mode));
    final t = DTheme.of(context);
    final child = switch (mode) {
      DisplayMode.active => const SizedBox.shrink(key: ValueKey('active')),
      DisplayMode.screensaver => const Screensaver(key: ValueKey('ss')),
      DisplayMode.night => const NightClock(key: ValueKey('night')),
      DisplayMode.off => GestureDetector(
          key: const ValueKey('off'),
          behavior: HitTestBehavior.opaque,
          onTap: () => ref.read(displayProvider.notifier).wake(),
          child: const ColoredBox(color: Colors.black),
        ),
    };
    // This layer sits above the Navigator, outside every Scaffold: without a
    // Material its text inherits MaterialApp's fallback style (yellow double
    // underline).
    return Material(
      type: MaterialType.transparency,
      child: AnimatedSwitcher(
        duration: t.motion(mode == DisplayMode.active ? DMotion.standard : const Duration(milliseconds: 600)),
        child: child,
      ),
    );
  }
}

/// Side effects tied to settings: wake lock, telemetry source.
class _Effects extends ConsumerStatefulWidget {
  const _Effects({required this.child});
  final Widget child;

  @override
  ConsumerState<_Effects> createState() => _EffectsState();
}

class _EffectsState extends ConsumerState<_Effects> {
  @override
  void initState() {
    super.initState();
    _applyWakeLock(ref.read(deviceSettingsProvider));
  }

  void _applyWakeLock(DeviceSettings s) {
    final on = s.keepAwake && !s.isPersonal;
    unawaited(() async {
      try {
        await WakelockPlus.toggle(enable: on);
      } on Object {
        // Unsupported platform or insecure web origin: the OS default applies.
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(deviceSettingsProvider, (_, s) => _applyWakeLock(s));
    return widget.child;
  }
}

// ──────────────────────────── Remote commands ───────────────────────────────

/// Handles Hub → device commands (SPEC FR-CMP-05, FR-ADM-02).
CommandHandler appCommandHandler(Ref ref) => (command, args) async {
      switch (command) {
        case 'wake':
          ref.read(displayProvider.notifier).wake();
          return {'mode': 'active'};
        case 'sleep':
          ref.read(displayProvider.notifier).startScreensaver();
          return {'mode': 'screensaver'};
        case 'chime':
        case 'announce':
          ref.read(toastProvider).show('${args['message'] ?? 'Hello from the Hub'}', emoji: '📣', duration: const Duration(seconds: 12));
          ref.read(displayProvider.notifier).wake();
          return {'shown': true};
        case 'reload':
          ref.read(syncClientProvider)?.nudge();
          reloadApp();
          return {'reloaded': true};
        case 'screenshot':
          return captureScreenshot(ref);
        default:
          throw UnsupportedError('Unknown command $command');
      }
    };

/// Renders the app's own layer to PNG and uploads it (adb screencap returns
/// 0 bytes on the frame; SPEC FR-ADM-02).
Future<Map<String, Object?>> captureScreenshot(Ref ref) async {
  final boundary = screenshotBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  final api = ref.read(hubApiProvider);
  if (boundary == null || api == null) throw StateError('No screen to capture');
  final image = await boundary.toImage(pixelRatio: 0.75);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (bytes == null) throw StateError('Encoding failed');
  final blob = await api.uploadBlob(bytes.buffer.asUint8List(), 'image/png');
  return {'sha': blob['sha'], 'width': blob['width'], 'height': blob['height']};
}

/// Telemetry fields the device reports to the Hub (SPEC FR-ADM-01).
Map<String, Object?> Function() appTelemetry(Ref ref) {
  final started = DateTime.now();
  return () => {
        'role': ref.read(deviceSettingsProvider).role,
        'tier': ref.read(perfTierProvider).name,
        'theme': ref.read(themeModeProvider).name,
        'mode': ref.read(displayProvider).mode.name,
        'uptimeS': DateTime.now().difference(started).inSeconds,
        'web': kIsWeb,
        'desktop': AppEnv.isDesktop,
        'today': ref.read(householdTimeProvider).today().iso,
        'schema': kSchemaMajor,
      };
}
