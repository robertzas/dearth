import 'dart:async';
import 'dart:io';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_integrations/dearth_integrations.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';

import 'api/admin_routes.dart';
import 'api/context.dart';
import 'api/core_routes.dart';
import 'api/feature_routes.dart';
import 'api/http_utils.dart';
import 'auth.dart';
import 'blobs.dart';
import 'config.dart';
import 'connections.dart';
import 'integrations.dart';
import 'jobs/basic_jobs.dart';
import 'jobs/google_job.dart';
import 'jobs/google_tasks_job.dart';
import 'jobs/photos_job.dart';
import 'jobs/scheduler.dart';
import 'kernel.dart';
import 'recipes_service.dart';
import 'storage.dart';

final _log = Logger('hub');

/// A running Dearth Hub (SPEC §14).
class DearthHub {
  DearthHub._(this.context, this.server, this.db);

  final HubContext context;
  final HttpServer? server;
  final DearthDb db;

  int get port => server?.port ?? 0;
  Uri get url => Uri.parse('http://127.0.0.1:$port');

  /// [timezone] names the household's zone on first start (the Hub built
  /// into the app passes the device's; a server reads `TZ`).
  static Future<DearthHub> start(HubConfig config, {bool inMemory = false, bool listen = true, Fetcher? fetcher, bool seedDemo = false, String? timezone}) async {
    final db = openHubDatabase(path: config.dbPath, inMemory: inMemory);
    final vault = SecretVault(db, config.secretKey);
    final kernel = HubKernel(db);
    final auth = HubAuth(kernel, config, vault);
    final f = fetcher ?? Fetcher(userAgent: 'Dearth Hub/$hubVersion (${config.contact})');

    await _bootstrap(kernel, seedDemo: seedDemo, timezone: timezone);
    final generated = await auth.ensureAdminPassword();
    if (generated != null) {
      _log.warning('══════════════════════════════════════════════════════════');
      _log.warning(' Admin password (shown once): $generated');
      _log.warning(' Set DEARTH_ADMIN_PASSWORD to choose your own.');
      _log.warning('══════════════════════════════════════════════════════════');
    }

    final jobs = JobStore(db);
    final scheduler = Scheduler(jobs);
    final blobs = BlobStore(db, config.blobDir, useVips: config.useVips);
    final integrations = Integrations(kernel: kernel, vault: vault, config: config, fetcher: f, jobs: jobs);
    final google = GoogleCalendarJob(integrations, jobs, onTrigger: () => scheduler.runNow('google-calendar', delay: const Duration(seconds: 2)));
    scheduler
      ..register(WeatherJob(integrations))
      ..register(IcsJob(integrations, jobs))
      ..register(google)
      ..register(GoogleTasksJob(integrations, jobs, onTrigger: () => scheduler.runNow('google-tasks', delay: const Duration(seconds: 2))))
      ..register(PhotosJob(integrations, blobs, jobs, config))
      ..register(MaintenanceJob(kernel, blobs, config));

    // Re-run integrations when the relevant data changes on any device.
    kernel.addListener((ops, origin) {
      for (final o in ops) {
        final t = o.op.table;
        if (t == 'households' && (o.op.fields.containsKey('lat') || o.op.fields.containsKey('timezone'))) scheduler.runNow('weather');
        if (t == 'calendar_sources' && origin.deviceId != DeviceIdentity.hub.deviceId) scheduler.runNow('ics');
        if (t == 'photo_sources' && origin.deviceId != DeviceIdentity.hub.deviceId) scheduler.runNow('photos');
      }
    });

    final connections = ConnectionHub(kernel, auth);
    final ctx = HubContext(
      config: config,
      kernel: kernel,
      auth: auth,
      connections: connections,
      blobs: blobs,
      integrations: integrations,
      recipes: RecipeService(integrations, f),
      scheduler: scheduler,
      jobs: jobs,
      google: google,
      fetcher: f,
      vault: vault,
    );

    final router = Router()..get('/api/sync', connections.handler);
    mountCoreRoutes(router, ctx);
    mountFeatureRoutes(router, ctx);
    mountAdminRoutes(router, ctx);
    router.all('/api/<rest|.*>', (Request req) => jsonError(404, 'not_found'));

    final web = _webHandler(config);
    final handler = const Pipeline()
        .addMiddleware(requestLog())
        .addMiddleware(securityHeaders())
        .addMiddleware(corsMiddleware({?config.publicUrl, ...config.lanUrls}))
        .addMiddleware(errorMiddleware())
        .addHandler(web == null ? router.call : Cascade().add(router.call).add(web).handler);

    HttpServer? server;
    if (listen) {
      server = await shelf_io.serve(handler, config.host, config.port);
      server.autoCompress = true;
      _log.info('Dearth Hub $hubVersion listening on http://${config.host}:${server.port}'
          '${config.fakeProviders ? ' (fake providers)' : ''}${config.publicUrl == null ? '' : ' — public ${config.publicUrl}'}');
    }
    if (config.jobsEnabled) scheduler.start();
    return DearthHub._(ctx, server, db);
  }

  /// First start: household skeleton (and optional demo data).
  static Future<void> _bootstrap(HubKernel kernel, {required bool seedDemo, String? timezone}) async {
    final existing = await kernel.db.select(kernel.db.households).get();
    if (existing.isEmpty) {
      final zone = timezone ?? Platform.environment['TZ'] ?? Platform.environment['DEARTH_TIMEZONE'] ?? 'UTC';
      await kernel.write(householdDefaultOps(kernel.mutator, timezone: locationOrUtc(zone).name));
      _log.info('Bootstrapped a new household (timezone ${locationOrUtc(zone).name})');
    }
    if (seedDemo && (await kernel.db.select(kernel.db.profiles).get()).isEmpty) {
      final tz = (await kernel.db.select(kernel.db.households).getSingle()).timezone;
      await kernel.write(await demoSeedOps(kernel.mutator, HouseholdTime.named(tz == 'UTC' ? 'America/Denver' : tz)));
      _log.info('Seeded demo household');
    }
  }

  static Handler? _webHandler(HubConfig config) {
    final dir = config.webDir;
    if (dir == null || !Directory(dir).existsSync()) return null;
    final files = createStaticHandler(dir, defaultDocument: 'index.html');
    final index = File(p.join(dir, 'index.html'));
    return (Request req) async {
      final res = await files(req);
      if (res.statusCode != 404 || req.url.path.startsWith('api/')) {
        final noCache = req.url.path.isEmpty || req.url.path.endsWith('index.html') || req.url.path.contains('service_worker') || req.url.path == 'version.json';
        return res.change(headers: {'cache-control': noCache ? 'no-cache' : 'public, max-age=3600'});
      }
      if (!index.existsSync()) return res;
      return Response.ok(index.openRead(), headers: {'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-cache'});
    };
  }

  Future<void> stop() async {
    context.scheduler.stop();
    await context.connections.closeAll();
    await server?.close(force: true);
    context.fetcher.close();
    await db.close();
  }
}
