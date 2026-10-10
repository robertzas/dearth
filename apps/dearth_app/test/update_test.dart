import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dearth_app/app/router.dart';
import 'package:dearth_app/core/data/household.dart';
import 'package:dearth_app/core/update/local_adb.dart';
import 'package:dearth_app/core/update/updater.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_harness.dart';

/// App updates from GitHub releases (SPEC FR-ADM-04, §15.3).
void main() {
  // The shape of GitHub's `releases/latest` (trimmed to what the app reads).
  Map<String, Object?> release(String tag, {List<String> abis = const ['arm64-v8a', 'armeabi-v7a', 'x86_64']}) => {
        'tag_name': tag,
        'draft': false,
        'prerelease': false,
        'published_at': '2026-10-10T16:09:34Z',
        'assets': [
          {'name': 'dearth-${tag.substring(1)}-web.zip', 'size': 1, 'browser_download_url': 'https://example.test/web.zip'},
          for (final abi in abis)
            {
              'name': 'dearth-${tag.substring(1)}-android-$abi.apk',
              'size': 47129906,
              'digest': 'sha256:28DF25b3fca6ffaa1cbb26efb4f8b873d45615409c41a02f6b54a9d3091e3be9',
              'browser_download_url': 'https://github.com/robertzas/dearth/releases/download/$tag/dearth-${tag.substring(1)}-android-$abi.apk',
            },
        ],
      };

  group('FR-ADM-04: releases', () {
    test('releases are semantic versions; a build made anywhere else has none and never updates by itself', () {
      expect(AppVersion.tryParse('0.1.97'), const AppVersion(0, 1, 97));
      expect(AppVersion.tryParse('v1.2.3'), const AppVersion(1, 2, 3));
      expect(AppVersion.tryParse('0.1.0-dev'), isNull);
      expect(AppVersion.tryParse('0.1.0-local.edc123b-dirty'), isNull);
      expect(AppVersion.tryParse('0.1'), isNull);
      // Releases from before semantic versions: the frame ran 0.1.0-build.95.
      expect(AppVersion.tryParse('0.1.0-build.95'), const AppVersion(0, 1, 95));
      expect(const AppVersion(0, 1, 97) > AppVersion.tryParse('0.1.0-build.95')!, isTrue);
      expect(const AppVersion(0, 2, 1) > const AppVersion(0, 1, 120), isTrue);
      expect(const AppVersion(1, 0, 0) > const AppVersion(0, 9, 999), isTrue);
      expect(const AppVersion(0, 1, 97) > const AppVersion(0, 1, 97), isFalse);
    });

    test('the release picks the APK built for this device’s ABI, with its checksum', () {
      final r = AppRelease.fromGitHub(release('v0.1.97'), 'armeabi-v7a')!;
      expect(r.version, const AppVersion(0, 1, 97));
      expect('${r.version}', '0.1.97');
      expect(r.apkUrl.path, endsWith('dearth-0.1.97-android-armeabi-v7a.apk'));
      expect(r.size, 47129906);
      expect(r.sha256, '28df25b3fca6ffaa1cbb26efb4f8b873d45615409c41a02f6b54a9d3091e3be9');
      expect(AppRelease.fromGitHub(release('v0.1.97', abis: ['arm64-v8a']), 'armeabi-v7a'), isNull, reason: 'no APK for this ABI');
      expect(AppRelease.fromGitHub(release('vnext'), 'armeabi-v7a'), isNull, reason: 'not a release version');
      expect(AppRelease.fromGitHub({...release('v0.1.98'), 'draft': true}, 'armeabi-v7a'), isNull);
    });
  });

  group('§15.3: installing by itself', () {
    bool may(String mode, {bool idle = true, bool timer = false, bool? night, int minute = 12 * 60}) =>
        mayAutoInstall(mode: mode, idle: idle, timerRunning: timer, nightTime: night, minuteOfDay: minute);

    test('only when nobody is using the screen and no kitchen timer is counting down', () {
      expect(may(UpdateMode.idle), isTrue);
      expect(may(UpdateMode.idle, idle: false), isFalse);
      expect(may(UpdateMode.idle, timer: true), isFalse);
      expect(may(UpdateMode.manual), isFalse, reason: 'manual waits for a grown-up');
    });

    test('nightly waits for the night hours, or 2–5 am without a night schedule', () {
      expect(may(UpdateMode.nightly, night: false), isFalse);
      expect(may(UpdateMode.nightly, night: true), isTrue);
      expect(may(UpdateMode.nightly, night: true, idle: false), isFalse, reason: 'someone woke the night clock');
      expect(may(UpdateMode.nightly, minute: 3 * 60), isTrue);
      expect(may(UpdateMode.nightly, minute: 23 * 60), isFalse);
      expect(may(UpdateMode.nightly, minute: 5 * 60), isFalse);
    });

    test('the download’s progress takes any number (a whole 0 broke the first download on the frame)', () {
      const s = UpdateState(phase: UpdatePhase.available);
      expect(s.copyWith(phase: UpdatePhase.downloading, progress: 0).progress, 0.0);
      expect(s.copyWith(progress: 0.5).progress, 0.5);
      expect(s.copyWith(progress: 0.5).copyWith(phase: UpdatePhase.ready, progress: null).progress, isNull);
    });

    test('the silent install runs on after adbd returns and starts the new app', () {
      final cmd = AppUpdater.silentInstallCommand('/data/user/0/app.dearth/cache/updates/dearth-0.1.97.apk', 47129906);
      expect(cmd, startsWith('nohup sh -c '));
      expect(cmd, contains('cat /data/user/0/app.dearth/cache/updates/dearth-0.1.97.apk | pm install -r -S 47129906'));
      expect(cmd, contains('am start -n app.dearth/.MainActivity'));
      expect(cmd, endsWith('&'));
    });
  });

  group('§15.3: the device’s own ADB', () {
    test('runs a shell command on an adbd that lets it in', () async {
      final adbd = await _FakeAdbd.start((command) => command == 'id -u' ? '0\n' : 'unknown');
      addTearDown(adbd.close);
      expect(await LocalAdb(port: adbd.port).shell('id -u'), '0\n');
      expect(adbd.commands, ['id -u']);
    });

    test('gives up on an adbd that asks for authorization, and on a port with nothing on it', () async {
      final adbd = await _FakeAdbd.start((_) => '', auth: true);
      addTearDown(adbd.close);
      await expectLater(LocalAdb(port: adbd.port).shell('id -u'), throwsA(isA<AdbException>().having((e) => e.message, 'message', contains('authorization'))));
      final free = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = free.port;
      await free.close();
      await expectLater(LocalAdb(port: port).shell('id -u'), throwsA(isA<AdbException>()));
    });
  });

  testWidgets('FR-ADM-04: Settings → Updates shows a newer version, a grown-up installs it, and a frame can update nightly', (tester) async {
    final handle = tester.ensureSemantics();
    final fake = _FakeUpdater(
      UpdateState(
        phase: UpdatePhase.available,
        current: AppVersion.tryParse('0.1.0-build.95'),
        latest: AppRelease.fromGitHub(release('v0.1.97'), 'armeabi-v7a'),
        checkedAtMs: DateTime.utc(2026, 10, 10, 16).millisecondsSinceEpoch,
        silent: true,
      ),
    );
    final h = await AppHarness.demo(tester, overrides: [appUpdaterProvider.overrideWith(() => fake)]);
    h.container.read(routerProvider).go('/settings/updates');
    await h.settle();
    expect(find.textContaining('Dearth 0.1.97 is available'), findsOneWidget);
    expect(byId('updates.mode.when-i-tap'), findsOneWidget);

    await tester.tap(byId('updates.install'));
    await h.settle();
    await tester.tap(find.text('Install'));
    await h.settle();
    expect(fake.installs, 1);

    await tester.tap(byId('updates.mode.nightly'));
    await h.settle();
    expect(h.container.read(deviceSettingsProvider).updates, UpdateMode.nightly);
    expectNoFallbackText();
    await h.shutdown();
    handle.dispose();
  });
}

class _FakeUpdater extends AppUpdater {
  _FakeUpdater(this.initial);
  final UpdateState initial;
  int installs = 0;

  @override
  UpdateState build() => initial;

  @override
  Future<void> check() async {}

  @override
  Future<void> install({bool auto = false}) async => installs++;
}

/// An adbd on a loopback port that answers one shell command per connection.
class _FakeAdbd {
  _FakeAdbd._(this._server, this._answer, this._auth) {
    _server.listen(_serve);
  }

  static Future<_FakeAdbd> start(String Function(String command) answer, {bool auth = false}) async =>
      _FakeAdbd._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0), answer, auth);

  final ServerSocket _server;
  final String Function(String) _answer;
  final bool _auth;
  final commands = <String>[];

  int get port => _server.port;

  static const _cnxn = 0x4e584e43, _authCmd = 0x48545541, _open = 0x4e45504f, _okay = 0x59414b4f, _clse = 0x45534c43, _wrte = 0x45545257;

  void _serve(Socket s) {
    var buf = <int>[];
    s.listen((chunk) {
      buf = [...buf, ...chunk];
      while (buf.length >= 24) {
        final h = ByteData.sublistView(Uint8List.fromList(buf.sublist(0, 24)));
        final cmd = h.getUint32(0, Endian.little), arg0 = h.getUint32(4, Endian.little), len = h.getUint32(12, Endian.little);
        expect(h.getUint32(20, Endian.little), cmd ^ 0xffffffff);
        if (buf.length < 24 + len) return;
        final data = buf.sublist(24, 24 + len);
        expect(h.getUint32(16, Endian.little), data.fold<int>(0, (a, b) => a + b), reason: 'data checksum');
        buf = buf.sublist(24 + len);
        switch (cmd) {
          case _cnxn:
            s.add(_auth ? LocalAdb.packet(_authCmd, 1, 0, List.filled(20, 7)) : LocalAdb.packet(_cnxn, 0x01000000, 4096, utf8.encode('device::\x00')));
          case _open:
            final service = utf8.decode(data).replaceAll('\x00', '');
            final command = service.substring('shell:'.length);
            commands.add(command);
            s
              ..add(LocalAdb.packet(_okay, 7, arg0, const []))
              ..add(LocalAdb.packet(_wrte, 7, arg0, utf8.encode(_answer(command))))
              ..add(LocalAdb.packet(_clse, 7, arg0, const []));
        }
      }
    }, onError: (Object _) {});
  }

  Future<void> close() => _server.close();
}
