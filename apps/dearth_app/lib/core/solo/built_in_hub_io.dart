import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_hub/dearth_hub.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'built_in_hub.dart';

const bool supported = true;

_IoHub? _current;
BuiltInHub? get current => _current;

/// The last stop, until its isolate has ended: nothing touches the data
/// folder before then.
Future<void> _stopped = Future.value();

Future<String> _dataDir() async => builtInHubDirOverride ?? p.join((await getApplicationSupportDirectory()).path, 'hub');

Future<BuiltInHub> start({int port = 0, String? timezone, List<SetupRow> setup = const [], ({String name, String role})? enroll}) async {
  await _current?.stop();
  await _stopped;
  final dir = await _dataDir();
  final inbox = ReceivePort();
  final exit = ReceivePort();
  final ready = Completer<(int, String?, SendPort)>();
  final exited = Completer<void>();
  inbox.listen((Object? m) {
    switch (m) {
      case ('ready', final int port, final String? code, final SendPort control):
        ready.complete((port, code, control));
      case ('log', final int level, final String logger, final String message):
        // The Hub's warnings join the app's trail (release builds print
        // nothing else); its per-request info lines stay quiet.
        if (level >= Level.WARNING.value) debugPrint('Dearth hub [$logger] $message');
      case ('error', final String error, final String stack):
        if (!ready.isCompleted) ready.completeError(StateError(error), StackTrace.fromString(stack));
        debugPrint('Dearth hub failed: $error\n$stack');
    }
  });
  exit.listen((_) {
    if (!ready.isCompleted) ready.completeError(StateError('The built-in Hub stopped while starting'));
    if (!exited.isCompleted) exited.complete();
    inbox.close();
    exit.close();
  });
  final isolate = await Isolate.spawn(_main, (inbox.sendPort, dir, port, timezone, setup, enroll), debugName: 'dearth-hub', onExit: exit.sendPort);
  final (bound, code, control) = await ready.future;
  return _current = _IoHub(isolate, control, Uri.parse('http://127.0.0.1:$bound'), code, exited.future);
}

Future<void> erase() async {
  await _current?.stop();
  await _stopped;
  final dir = Directory(await _dataDir());
  if (dir.existsSync()) await dir.delete(recursive: true);
}

class _IoHub implements BuiltInHub {
  _IoHub(this._isolate, this._control, this.url, this.enrollCode, this.exited);
  final Isolate _isolate;
  final SendPort _control;
  @override
  final Uri url;
  @override
  final String? enrollCode;
  @override
  final Future<void> exited;
  Future<void>? _stopping;

  @override
  Future<void> stop() => _stopping ??= _stopped = () async {
        if (_current == this) _current = null;
        _control.send('stop');
        // The Hub closes its sockets and database; a stuck one is killed.
        await exited.timeout(const Duration(seconds: 10), onTimeout: () => _isolate.kill(priority: Isolate.immediate));
      }();
}

/// The Hub isolate: start, report the port, serve until asked to stop.
Future<void> _main((SendPort, String, int, String?, List<SetupRow>, ({String name, String role})?) args) async {
  final (reply, dir, preferredPort, timezone, setup, enroll) = args;
  Logger.root.level = Level.INFO;
  final logs = Logger.root.onRecord.listen((r) => reply.send(('log', r.level.value, r.loggerName, r.message)));
  final control = ReceivePort();
  try {
    ensureTimeZones();
    Directory(dir).createSync(recursive: true);
    final secretFile = File(p.join(dir, 'secret.key'));
    if (!secretFile.existsSync()) secretFile.writeAsStringSync(randomToken());
    final hub = await DearthHub.start(
      HubConfig(
        dataDir: dir,
        secretKey: secretFile.readAsStringSync().trim(),
        host: '127.0.0.1',
        port: await _freePort(preferredPort),
        contact: 'dearth-app',
        useVips: false,
      ),
      timezone: timezone,
    );
    if (setup.isNotEmpty) {
      final k = hub.context.kernel;
      await k.write([for (final (table, id, fields) in setup) k.mutator.makeOp(table, id, fields)]);
    }
    final code = enroll == null ? null : await hub.context.auth.enroll(name: enroll.name, role: enroll.role, admin: true);
    reply.send(('ready', hub.port, code, control.sendPort));
    await control.firstWhere((m) => m == 'stop');
    await hub.stop();
  } on Object catch (e, st) {
    reply.send(('error', '$e', '$st'));
  }
  control.close();
  await logs.cancel();
  // Whatever the Hub left open (a timer, a socket) ends with the isolate.
  Isolate.exit();
}

/// [preferred] when it is free (the device keeps its address across
/// restarts), else 0: any free port.
Future<int> _freePort(int preferred) async {
  if (preferred <= 0) return 0;
  try {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, preferred);
    await socket.close();
    return preferred;
  } on SocketException {
    return 0;
  }
}
