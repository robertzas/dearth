import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dearth_hub/dearth_hub.dart';
import 'package:logging/logging.dart';

/// `dearth-hub [serve|healthcheck|enroll|approve|reset-admin]`
Future<void> main(List<String> argv) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false)
    ..addFlag('seed-demo', negatable: false, help: 'Seed a demo household on first start')
    ..addOption('name', defaultsTo: 'Display', help: 'enroll: device name')
    ..addOption('role', defaultsTo: 'kitchen', help: 'enroll/approve: kitchen | kid_room | entry | personal')
    ..addOption('orientation', help: 'enroll: auto | landscape | portrait')
    ..addFlag('admin', negatable: false, help: 'enroll/approve: grant admin');
  final args = parser.parse(argv);
  final command = args.rest.isEmpty ? 'serve' : args.rest.first;
  if (args['help'] as bool) {
    stdout.writeln('Dearth Hub\n\nCommands:\n'
        '  serve                 run the Hub (default)\n'
        '  healthcheck           exit 0 when the local Hub answers\n'
        '  enroll                print a one-time enrollment code (pre-approved pairing)\n'
        '  approve <CODE>        approve a pending pairing code\n'
        '  reset-admin           print a new admin password\n\n${parser.usage}');
    return;
  }

  final env = Platform.environment;
  final level = (env['DEARTH_LOG_LEVEL'] ?? 'info').toUpperCase();
  Logger.root.level = Level.LEVELS.firstWhere((l) => l.name == level, orElse: () => Level.INFO);
  Logger.root.onRecord.listen((r) {
    final line = jsonEncode({
      't': r.time.toUtc().toIso8601String(),
      'level': r.level.name.toLowerCase(),
      'logger': r.loggerName,
      'msg': r.message,
      if (r.error != null) 'error': '${r.error}',
    });
    (r.level >= Level.WARNING ? stderr : stdout).writeln(command == 'serve' ? line : r.message);
  });

  final config = HubConfig.fromEnvironment(env, warn: (m) => Logger('config').warning(m));

  switch (command) {
    case 'healthcheck':
      try {
        final client = HttpClient();
        final req = await client.getUrl(Uri.parse('http://127.0.0.1:${config.port}/api/health')).timeout(const Duration(seconds: 5));
        final res = await req.close().timeout(const Duration(seconds: 5));
        exit(res.statusCode == 200 ? 0 : 1);
      } on Object {
        exit(1);
      }
    case 'enroll':
    case 'approve':
    case 'reset-admin':
      final db = openHubDatabase(path: config.dbPath);
      final kernel = HubKernel(db);
      final auth = HubAuth(kernel, config, SecretVault(db, config.secretKey));
      if (command == 'enroll') {
        final code = await auth.enroll(name: args['name'] as String, role: args['role'] as String, admin: args['admin'] as bool, orientation: args['orientation'] as String?);
        stdout.writeln(code);
      } else if (command == 'approve') {
        if (args.rest.length < 2) {
          stderr.writeln('usage: dearth-hub approve <CODE>');
          exit(2);
        }
        final ok = await auth.approve(args.rest[1], role: args['role'] as String, admin: args['admin'] as bool);
        stdout.writeln(ok ? 'Approved.' : 'No pending pairing with that code.');
      } else {
        await SecretVault(db, config.secretKey).remove('admin:password');
        final pw = await auth.ensureAdminPassword();
        stdout.writeln(pw ?? 'DEARTH_ADMIN_PASSWORD is set; it wins.');
      }
      await db.close();
    default:
      final hub = await DearthHub.start(config, seedDemo: args['seed-demo'] as bool || env['DEARTH_SEED_DEMO'] == '1');
      final done = Completer<void>();
      for (final signal in [ProcessSignal.sigint, if (!Platform.isWindows) ProcessSignal.sigterm]) {
        signal.watch().listen((_) async {
          if (done.isCompleted) return;
          Logger('hub').info('Shutting down…');
          await hub.stop();
          done.complete();
        });
      }
      await done.future;
      exit(0);
  }
}
