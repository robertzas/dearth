import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_integrations/dearth_integrations.dart';
import 'package:drift/drift.dart';
import 'package:logging/logging.dart';

import '../blobs.dart';
import '../config.dart';
import '../integrations.dart';
import '../kernel.dart';
import '../storage.dart';
import 'scheduler.dart';

final _log = Logger('jobs');

/// Merged weather → `weather_reports/current` (SPEC §13.4).
class WeatherJob implements HubJob {
  WeatherJob(this.integrations);
  final Integrations integrations;
  bool _hasStation = false;

  @override
  String get id => 'weather';

  @override
  Duration nextDelay() => Duration(minutes: _hasStation ? 5 : 30);

  @override
  Future<void> run() async {
    final cfg = await integrations.weatherConfig();
    if (cfg == null) {
      await integrations.report('weather', ok: false, message: 'Set the household location to get weather');
      return;
    }
    _hasStation = cfg.hasStation;
    final db = integrations.db;
    final prevRow = await (db.select(db.weatherReports)..where((t) => t.id.equals(Ids.weather))).getSingleOrNull();
    final previous = WeatherReport.tryDecode(prevRow?.data);
    final source = integrations.weatherSource();
    final report = await source.fetch(cfg, previous: previous);
    await integrations.kernel.upsert('weather_reports', Ids.weather, {'data': report.encode(), 'fetched_ms': report.fetchedMs});
    final errors = source is WeatherService ? source.lastErrors : const <String, String>{};
    await integrations.report(
      'weather',
      ok: errors.isEmpty || report.current != null,
      message: errors.isEmpty ? 'Updated from ${report.sources.values.toSet().join(', ')}' : errors.entries.map((e) => '${e.key}: ${e.value}').join('; '),
      extra: {'sources': report.sources},
    );
  }
}

/// ICS subscriptions (SPEC §13.3): conditional fetch, deterministic upserts,
/// tombstones for events that disappeared from the feed.
class IcsJob implements HubJob {
  IcsJob(this.integrations, this.jobs);
  final Integrations integrations;
  final JobStore jobs;

  @override
  String get id => 'ics';

  @override
  Duration nextDelay() => const Duration(minutes: 30);

  @override
  Future<void> run() async {
    final db = integrations.db;
    final sources = await (db.select(db.calendarSources)..where((t) => t.kind.equals('ics') & t.enabled.equals(true) & t.deleted.equals(false))).get();
    final h = await integrations.household();
    final tz = h?.timezone ?? 'UTC';
    for (final s in sources) {
      if (s.url == null || s.url!.isEmpty) continue;
      final stateId = 'ics:${s.id}';
      final state = await jobs.data(stateId);
      final last = (state['fetchedMs'] as num?)?.toInt() ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - last < const Duration(hours: 6).inMilliseconds && state['force'] != true && s.lastSyncMs != null) continue;
      try {
        final url = s.url!.replaceFirst(RegExp('^webcal://', caseSensitive: false), 'https://');
        final res = await integrations.fetcher.send('ics', 'GET', Uri.parse(url), headers: {
          'Accept': 'text/calendar, */*',
          if (state['etag'] is String) 'If-None-Match': state['etag']! as String,
        });
        final drafts = parseIcs(res.body, defaultTz: tz);
        final n = await importDrafts(integrations.kernel, s.id, drafts);
        await jobs.write(stateId, data: {'etag': res.headers['etag'], 'fetchedMs': DateTime.now().millisecondsSinceEpoch});
        await integrations.kernel.upsert('calendar_sources', s.id, {'status': 'ok · $n events', 'last_sync_ms': DateTime.now().millisecondsSinceEpoch});
      } on ProviderException catch (e) {
        if (e.status == 304) {
          await jobs.write(stateId, data: {...state, 'fetchedMs': DateTime.now().millisecondsSinceEpoch});
          continue;
        }
        _log.warning('ICS ${s.name} failed: $e');
        await integrations.kernel.upsert('calendar_sources', s.id, {'status': 'error · ${e.message}'});
      }
    }
  }
}

/// Upserts drafts for a source and tombstones rows that vanished. Returns the
/// number of live events. Device annotations (people, icon) survive because
/// drafts never carry those fields.
Future<int> importDrafts(HubKernel kernel, String sourceId, List<EventDraft> drafts, {bool tombstoneMissing = true}) async {
  final db = kernel.db;
  final existing = await (db.select(db.events)..where((t) => t.sourceId.equals(sourceId))).get();
  final byRemote = {for (final e in existing) if (e.remoteId != null) e.remoteId!: e};
  final ops = <Op>[];
  final seen = <String>{};
  for (final d in drafts) {
    final row = byRemote[d.remoteId];
    final id = row?.id ?? EventDraft.localId(sourceId, d.remoteId);
    seen.add(id);
    if (row != null && !row.deleted && row.updatedMs != null && row.updatedMs == d.updatedMs && row.etag == d.etag) continue;
    if (d.isCancelled && d.recurringRemoteId == null) {
      if (row != null && !row.deleted) ops.add(kernel.mutator.makeOp('events', id, const {}, kind: OpKind.delete));
      continue;
    }
    ops.add(kernel.mutator.makeOp('events', id, d.toFields(sourceId)));
  }
  if (tombstoneMissing) {
    for (final e in existing) {
      if (!e.deleted && !seen.contains(e.id)) ops.add(kernel.mutator.makeOp('events', e.id, const {}, kind: OpKind.delete));
    }
  }
  for (var i = 0; i < ops.length; i += 500) {
    await kernel.write(ops.sublist(i, i + 500 > ops.length ? ops.length : i + 500));
  }
  return drafts.where((d) => !d.isCancelled).length;
}

/// Nightly backup, op-log compaction and blob garbage collection.
class MaintenanceJob implements HubJob {
  MaintenanceJob(this.kernel, this.blobs, this.config);
  final HubKernel kernel;
  final BlobStore blobs;
  final HubConfig config;
  bool _first = true;

  @override
  String get id => 'maintenance';

  @override
  Duration nextDelay() => const Duration(hours: 24);

  @override
  Future<void> run() async {
    if (_first) {
      _first = false; // don't back up on every restart
      return;
    }
    await backupDatabase(kernel.db, config.backupDir);
    final dropped = await kernel.compact();
    final removed = await blobs.garbageCollect(await referencedBlobs(kernel.db));
    _log.info('Maintenance: backup done, compacted $dropped ops, removed $removed blobs');
  }
}

/// Every blob sha referenced by synced rows.
Future<Set<String>> referencedBlobs(DearthDb db) async {
  final refs = <String>{};
  Future<void> col(String table, String column) async {
    final rows = await db.customSelect('SELECT "$column" AS v FROM "$table" WHERE "$column" IS NOT NULL').get();
    for (final r in rows) {
      refs.add(r.read<String>('v'));
    }
  }

  await col('photo_items', 'blob_ref');
  await col('photo_items', 'thumb_blob');
  await col('profiles', 'avatar_blob');
  await col('recipes', 'image_blob');
  await col('chores', 'photo_blob');
  await col('chores', 'voice_blob');
  await col('notes', 'blob_ref');
  await col('artworks', 'blob_ref');
  await col('music_tiles', 'art_blob');
  await col('routines', 'cover_blob');
  final files = await db.customSelect("SELECT ref FROM music_tiles WHERE source = 'file'").get();
  refs.addAll(files.map((r) => r.read<String>('ref')));
  final routines = await db.select(db.routines).get();
  for (final r in routines) {
    for (final s in decodeSteps(r.steps)) {
      if (s.voiceBlob != null) refs.add(s.voiceBlob!);
    }
  }
  return refs;
}

