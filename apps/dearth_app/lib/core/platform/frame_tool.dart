import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../env.dart';
import '../providers.dart';
import '../session.dart';
import '../sync/hub_api.dart';

final _log = Logger('FrameTool');
const MethodChannel _tool = MethodChannel('app.dearth/tool');

/// Answers the developer's tools on an Android display (tool/perf_gate.sh),
/// which send commands as launch-intent extras over ADB and read the
/// answers on logcat as `DEARTH_TOOL <what> <json>` lines (tag DearthTool):
///
/// - `--es dearth_tool session`: the mode, Hub, device id and sync phase
///   (never the token).
/// - `--es dearth_tool rejoin:<minutes>`: on a display joined to a Hub, a
///   single-use code from the Hub that brings this same device back after
///   its data is wiped.
/// - `--es dearth_hub <url> --es dearth_enroll <code>`: an unpaired display
///   claims the code by itself (only from onboarding: it never replaces a
///   household that's set up).
///
/// Kept alive by the app root, so it answers on onboarding too.
final frameToolProvider = Provider<void>((ref) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  var alive = true;
  ref.onDispose(() {
    alive = false;
    _tool.setMethodCallHandler(null);
  });

  Future<void> report(String what, Map<String, Object?> data) async {
    try {
      await _tool.invokeMethod<void>('report', 'DEARTH_TOOL $what ${jsonEncode(data)}');
    } on Object {
      // No activity to log through: nobody is listening either.
    }
  }

  Future<void> session() async {
    final s = ref.read(sessionProvider);
    await report('session', {
      'mode': s.mode.name,
      if (s.mode == SessionMode.hub) 'hub': s.hubUrl,
      'device': ?s.deviceId,
      'name': ?s.deviceName,
      'sync': ref.read(syncClientProvider)?.state.phase.name ?? 'idle',
    });
  }

  Future<void> rejoin(int minutes) async {
    final s = ref.read(sessionProvider);
    final api = ref.read(hubApiProvider);
    if (s.mode != SessionMode.hub || api == null) {
      await report('rejoin', {'error': 'not joined to a Hub (${s.mode.name})'});
      return;
    }
    try {
      final r = await api.post('/api/devices/self/rejoin', {'minutes': minutes});
      await report('rejoin', {'hub': s.hubUrl, 'device': r['deviceId'], 'code': r['code'], 'expiresInS': r['expiresInS']});
    } on HubApiException catch (e) {
      await report('rejoin', {'error': e.friendly});
    }
  }

  Future<void> enroll(String hub, String code) async {
    final base = HubApi.parseBase(hub);
    if (base == null) return report('enroll', {'error': 'not a Hub address: $hub'});
    if (ref.read(sessionProvider).isReady) return report('enroll', {'error': 'already set up (${ref.read(sessionProvider).mode.name})'});
    final api = HubApi(base);
    try {
      // No name: a returning display keeps the one it had on the Hub.
      final r = await api.claim(code, platform: AppEnv.platformName);
      if (!r.approved) {
        await report('enroll', {'error': 'the Hub said ${r.status}'});
        return;
      }
      await ref.read(sessionProvider.notifier).pairedWith(base, r, name: r.name);
      await report('enroll', {'hub': base.toString(), 'device': r.deviceId});
    } on HubApiException catch (e) {
      await report('enroll', {'error': e.friendly});
    } finally {
      api.close();
    }
  }

  Future<void> take() async {
    final Map<String, Object?>? t;
    try {
      t = await _tool.invokeMapMethod<String, Object?>('takeTool');
    } on MissingPluginException {
      return; // Widget tests, and embedders without Dearth's activity.
    } on PlatformException catch (e) {
      _log.warning('takeTool: $e');
      return;
    }
    if (!alive || t == null) return;
    // The claim first: a tool that enrolls and then asks for the session
    // hears the new one.
    if (t['hub'] case final String hub) {
      if (t['code'] case final String code) await enroll(hub, code);
    }
    switch ((t['command'] as String?)?.split(':')) {
      case ['session']:
        await session();
      case ['rejoin', ...final rest]:
        await rejoin(int.tryParse(rest.firstOrNull ?? '') ?? 60);
      case [final other, ...]:
        await report('error', {'unknown': other});
      case null || []:
        break;
    }
  }

  _tool.setMethodCallHandler((call) async {
    if (call.method == 'nudge') await take();
  });
  unawaited(take());
});
