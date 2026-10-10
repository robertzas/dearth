import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// The developer's tools over ADB (tool/perf_gate.sh, deploy_frame.sh
/// --join): commands come through the `app.dearth/tool` channel and the
/// answers go back to logcat as `DEARTH_TOOL <what> {json}`.
void main() {
  testWidgets('the display says what it is, and never lets a code replace a household that is set up', (tester) async {
    const channel = MethodChannel('app.dearth/tool');
    Map<String, Object?> pending = const {};
    final reports = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'takeTool':
          final taken = pending;
          pending = const {};
          return taken;
        case 'report':
          reports.add(call.arguments as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    Future<void> nudge(Map<String, Object?> command) async {
      pending = command;
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(channel.name, const StandardMethodCodec().encodeMethodCall(const MethodCall('nudge')), (_) {});
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    Map<String, Object?> last(String what) {
      final line = reports.lastWhere((r) => r.startsWith('DEARTH_TOOL $what '));
      return jsonDecode(line.substring('DEARTH_TOOL $what '.length)) as Map<String, Object?>;
    }

    final h = await AppHarness.demo(tester);
    await nudge({'command': 'session'});
    expect(last('session'), {'mode': 'demo', 'name': 'This display', 'sync': 'idle'}, reason: 'no token, and no Hub for a demo');

    await nudge({'command': 'rejoin:45'});
    expect(last('rejoin')['error'], contains('not joined to a Hub'));

    await nudge({'hub': 'http://hub.invalid:8090', 'code': 'ABCD2345'});
    expect(last('enroll')['error'], 'already set up (demo)', reason: 'a code only sets up a display that is not set up');

    await nudge({'command': 'dance'});
    expect(last('error'), {'unknown': 'dance'});
    await h.shutdown();
  });
}
