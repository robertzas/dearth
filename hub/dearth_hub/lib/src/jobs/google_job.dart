import 'dart:async';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_integrations/dearth_integrations.dart';
import 'package:drift/drift.dart';
import 'package:logging/logging.dart';

import '../integrations.dart';
import '../kernel.dart';
import '../storage.dart';
import 'basic_jobs.dart';
import 'scheduler.dart';

final _log = Logger('google');

/// Two-way Google Calendar sync (SPEC §13.2).
///
/// Order matters: device edits are pushed first, then remote changes are
/// pulled, and rows with pending local edits are never overwritten by stale
/// remote data in between.
class GoogleCalendarJob implements HubJob {
  GoogleCalendarJob(this.integrations, this.jobs, {this.onTrigger}) {
    integrations.kernel.addListener(_onOps);
  }

  final Integrations integrations;
  final JobStore jobs;

  /// Asks the scheduler to run this job soon.
  final void Function()? onTrigger;
  final Set<String> _dirty = {};
  final Map<String, int> _attempts = {};

  HubKernel get kernel => integrations.kernel;

  @override
  String get id => 'google-calendar';

  @override
  Duration nextDelay() => const Duration(minutes: 10);

  void _onOps(List<SeqOp> ops, DeviceIdentity origin) {
    if (origin.deviceId == DeviceIdentity.hub.deviceId) return;
    var touched = false;
    for (final o in ops) {
      if (o.op.table == 'events') {
        _dirty.add(o.op.rowId);
        touched = true;
      } else if (o.op.table == 'calendar_sources' && o.op.fields.containsKey('enabled')) {
        touched = true;
      }
    }
    if (touched) onTrigger?.call();
  }

  /// Push-notification webhook (verified by channel token).
  Future<bool> webhook({required String channelId, required String token}) async {
    final sources = await _googleSources();
    for (final s in sources) {
      final st = await jobs.data('gcal:${s.id}');
      if (st['channelId'] == channelId) {
        if (st['channelToken'] != token) return false;
        onTrigger?.call();
        return true;
      }
    }
    return false;
  }

  Future<List<CalendarSource>> _googleSources() {
    final db = kernel.db;
    return (db.select(db.calendarSources)..where((t) => t.kind.equals('google') & t.deleted.equals(false))).get();
  }

  @override
  Future<void> run() async {
    final accounts = await integrations.googleAccounts();
    if (accounts.isEmpty) return;
    final tz = (await integrations.household())?.timezone ?? 'UTC';
    await _push(tz);
    final sources = (await _googleSources()).where((s) => s.enabled).toList();
    var ok = true;
    String? message;
    for (final s in sources) {
      try {
        await _pull(s, tz);
        await _ensureChannel(s, tz);
      } on ProviderException catch (e) {
        ok = false;
        message = e.isAuth ? 'Reconnect Google (${s.accountId})' : e.message;
        await kernel.upsert('calendar_sources', s.id, {'status': 'error · ${e.isAuth ? 'reconnect needed' : e.message}'});
      }
    }
    await integrations.report('google', ok: ok, message: message ?? 'Synced ${sources.length} calendar(s)');
  }

  GoogleCalendarApi _api(String accountId, String tz) =>
      GoogleCalendarApi(integrations.fetcher, () => integrations.googleAccessToken(accountId), defaultTz: tz);

  // ─────────────────────────────── Inbound ─────────────────────────────────

  Future<void> _pull(CalendarSource s, String tz) async {
    final api = _api(s.accountId!, tz);
    final stateId = 'gcal:${s.id}';
    final state = await jobs.data(stateId);
    var syncToken = state['syncToken'] as String?;
    final drafts = <EventDraft>[];
    String? next;
    var full = syncToken == null;
    while (true) {
      try {
        String? page;
        do {
          final res = await api.listEvents(
            s.remoteId!,
            syncToken: full ? null : syncToken,
            pageToken: page,
            timeMinMs: full ? DateTime.now().subtract(const Duration(days: 365)).millisecondsSinceEpoch : null,
          );
          drafts.addAll(res.events);
          page = res.nextPageToken;
          next = res.nextSyncToken ?? next;
        } while (page != null);
        break;
      } on SyncTokenExpired {
        _log.info('Sync token expired for ${s.name}; full resync');
        full = true;
        syncToken = null;
        drafts.clear();
      }
    }
    final pending = Set.of(_dirty);
    final apply = drafts.where((d) {
      final localId = EventDraft.localId(s.id, d.remoteId);
      return !pending.contains(localId);
    }).toList();
    final n = await importDrafts(kernel, s.id, apply, tombstoneMissing: full);
    await jobs.write(stateId, data: {...state, 'syncToken': next ?? syncToken});
    await kernel.upsert('calendar_sources', s.id, {
      'status': full ? 'ok · $n events' : 'ok',
      'last_sync_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ─────────────────────────────── Outbound ────────────────────────────────

  Future<void> _push(String tz) async {
    if (_dirty.isEmpty) return;
    final db = kernel.db;
    final ids = _dirty.toList();
    _dirty.clear();
    final sources = {for (final s in await _googleSources()) s.id: s};
    for (final id in ids) {
      final row = await (db.select(db.events)..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) continue;
      final s = sources[row.sourceId];
      if (s == null || !s.writable || s.remoteId == null || s.accountId == null) continue;
      final api = _api(s.accountId!, tz);
      try {
        if (row.deleted) {
          if (row.remoteId != null) await api.delete(s.remoteId!, row.remoteId!, etag: row.etag);
        } else if (row.recurringParentId != null && row.remoteId == null) {
          _log.info('Skipping locally created recurring exception ${row.id} (edit the series in Google)');
        } else if (row.remoteId == null) {
          final created = await api.insert(s.remoteId!, googleBodyFromEvent(row, householdTz: tz));
          await kernel.upsert('events', row.id, {'remote_id': created.remoteId, 'etag': created.etag, 'updated_ms': created.updatedMs});
        } else {
          try {
            final updated = await api.patch(s.remoteId!, row.remoteId!, googleBodyFromEvent(row, householdTz: tz), etag: row.etag);
            await kernel.upsert('events', row.id, {'etag': updated.etag, 'updated_ms': updated.updatedMs});
          } on EtagConflict {
            await _resolveConflict(api, s, row, tz);
          }
        }
        _attempts.remove(id);
      } on ProviderException catch (e) {
        final n = (_attempts[id] ?? 0) + 1;
        _attempts[id] = n;
        if (n < 5 && e.isRetryable) {
          _dirty.add(id);
        } else {
          _log.warning('Giving up pushing ${row.title}: $e');
        }
      }
    }
  }

  /// Field-level LWW against the remote copy: whichever side changed last
  /// wins (SPEC §13.2). The device edit time is the newest field HLC.
  Future<void> _resolveConflict(GoogleCalendarApi api, CalendarSource s, Event row, String tz) async {
    final remote = await api.get(s.remoteId!, row.remoteId!);
    if (remote == null) return;
    final clocks = decodeClock(row.syncClock).values.map(Hlc.tryParse).whereType<Hlc>();
    final localMs = clocks.isEmpty ? 0 : clocks.map((h) => h.millis).reduce((a, b) => a > b ? a : b);
    if ((remote.updatedMs ?? 0) > localMs) {
      await kernel.upsert('events', row.id, remote.toFields(s.id));
    } else {
      final forced = await api.patch(s.remoteId!, row.remoteId!, googleBodyFromEvent(row, householdTz: tz));
      await kernel.upsert('events', row.id, {'etag': forced.etag, 'updated_ms': forced.updatedMs});
    }
  }

  // ───────────────────────────── Push channels ─────────────────────────────

  Future<void> _ensureChannel(CalendarSource s, String tz) async {
    final origin = integrations.publicOrigin;
    if (origin == null || !origin.startsWith('https://')) return;
    final stateId = 'gcal:${s.id}';
    final state = await jobs.data(stateId);
    final exp = (state['channelExpiration'] as num?)?.toInt() ?? 0;
    if (exp - DateTime.now().millisecondsSinceEpoch > const Duration(hours: 24).inMilliseconds) return;
    final api = _api(s.accountId!, tz);
    if (state['channelId'] is String && state['resourceId'] is String) {
      unawaited(api.stopChannel(state['channelId']! as String, state['resourceId']! as String).catchError((Object _) {}));
    }
    final channelId = newId();
    final token = randomToken(bytes: 16);
    try {
      final ch = await api.watch(s.remoteId!, address: '$origin/api/webhooks/google/calendar', channelId: channelId, channelToken: token);
      await jobs.write(stateId, data: {...state, 'channelId': ch.id, 'resourceId': ch.resourceId, 'channelToken': token, 'channelExpiration': ch.expirationMs});
    } on ProviderException catch (e) {
      _log.info('Push channel not available for ${s.name} (${e.message}); polling instead');
    }
  }
}
