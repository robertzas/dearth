import 'dart:async';
import 'dart:convert';

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

  /// Events whose reminders a device changed: only these send reminders to
  /// Google, so a title edit on the wall leaves a parent's own phone
  /// reminders (and "use default") alone.
  final Set<String> _remindersTouched = {};
  final Map<String, int> _attempts = {};

  /// Bumped when inbound mapping gains a field, so every calendar does one
  /// full resync and existing rows pick it up (2: reminders).
  static const _mappingVersion = 2;

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
        if (o.op.fields.containsKey('reminders')) _remindersTouched.add(o.op.rowId);
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
    var syncToken = state['mapping'] == _mappingVersion ? state['syncToken'] as String? : null;
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
    final db = kernel.db;
    final rows = {
      for (final e in await (db.select(db.events)..where((t) => t.sourceId.equals(s.id) & t.remoteId.isNotNull())).get()) e.remoteId!: e,
    };
    final apply = [
      for (final d in drafts)
        if (!pending.contains(rows[d.remoteId]?.id ?? EventDraft.localId(s.id, d.remoteId))) _keepWallOnly(d, rows[d.remoteId]),
    ];
    final n = await importDrafts(kernel, s.id, apply, tombstoneMissing: full);
    await jobs.write(stateId, data: {...state, 'syncToken': next ?? syncToken, 'mapping': _mappingVersion});
    await kernel.upsert('calendar_sources', s.id, {
      'status': full ? 'ok · $n events' : 'ok',
      'last_sync_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// All-day "Morning of" has no Google form, so it never went up; keep it
  /// on the row when Google's copy comes back.
  EventDraft _keepWallOnly(EventDraft d, Event? row) {
    if (row == null || !d.allDay || d.reminders == null || followsCalendarReminders(d.reminders)) return d;
    final local = wallOnlyReminders(row.reminders, allDay: true);
    if (local.isEmpty) return d;
    return d.withReminders(jsonEncode(({...decodeReminders(d.reminders), ...local}.toList()..sort())));
  }

  // ─────────────────────────────── Outbound ────────────────────────────────

  Future<void> _push(String tz) async {
    if (_dirty.isEmpty) return;
    final db = kernel.db;
    final ids = _dirty.toList();
    _dirty.clear();
    final sources = {for (final s in await _googleSources()) s.id: s};
    final rows = await (db.select(db.events)..where((t) => t.id.isIn(ids))).get();
    // Series before their exceptions: an instance needs its master's id.
    rows.sort((a, b) => (a.recurringParentId == null ? 0 : 1) - (b.recurringParentId == null ? 0 : 1));
    for (final row in rows) {
      final id = row.id;
      final s = sources[row.sourceId];
      if (s == null || !s.writable || s.remoteId == null || s.accountId == null) continue;
      final api = _api(s.accountId!, tz);
      final reminders = _remindersTouched.remove(id);
      try {
        if (row.deleted) {
          // (An instance edit that never went up has nothing to undo.)
          if (row.remoteId != null) await api.delete(s.remoteId!, row.remoteId!, etag: row.etag);
        } else if (row.recurringParentId != null && (row.remoteId == null || row.status == 'cancelled')) {
          if (!await _pushInstance(api, s, row, tz)) _dirty.add(id); // its series isn't on Google yet
        } else if (row.remoteId == null) {
          final created = await api.insert(s.remoteId!, googleBodyFromEvent(row, householdTz: tz, withReminders: true));
          await kernel.upsert('events', row.id, {'remote_id': created.remoteId, 'etag': created.etag, 'updated_ms': created.updatedMs});
        } else {
          // Email reminders aren't on the wall: fetch them to send them back.
          final kept = reminders ? (await api.get(s.remoteId!, row.remoteId!))?.keptReminders ?? const <Map<String, Object?>>[] : const <Map<String, Object?>>[];
          final body = {
            ...googleBodyFromEvent(row, householdTz: tz, withReminders: reminders, kept: kept),
            if (row.recurringParentId != null) 'status': 'confirmed', // an instance brought back
          };
          try {
            final updated = await api.patch(s.remoteId!, row.remoteId!, body, etag: row.etag);
            await kernel.upsert('events', row.id, {'etag': updated.etag, 'updated_ms': updated.updatedMs});
          } on EtagConflict {
            await _resolveConflict(api, s, row, body);
          }
        }
        _attempts.remove(id);
      } on ProviderException catch (e) {
        final n = (_attempts[id] ?? 0) + 1;
        _attempts[id] = n;
        if (n < 5 && e.isRetryable) {
          _dirty.add(id);
          if (reminders) _remindersTouched.add(id);
        } else {
          _log.warning('Giving up pushing ${row.title}: $e');
        }
      }
    }
  }

  /// "This event" of a series (SPEC §13.2): Google keeps one instance per
  /// original start under a derived id, so a wall edit patches that
  /// instance and a wall delete cancels it. False while the series itself
  /// hasn't reached Google.
  Future<bool> _pushInstance(GoogleCalendarApi api, CalendarSource s, Event row, String tz) async {
    final db = kernel.db;
    final master = await (db.select(db.events)..where((t) => t.id.equals(row.recurringParentId!))).getSingleOrNull();
    if (master == null || master.deleted) return true;
    if (master.remoteId == null) return false;
    final original = row.originalStartMs ?? row.startMs;
    final instanceId = row.remoteId ??
        googleInstanceId(master.remoteId!, originalStartMs: original, allDayDate: master.allDay ? HouseholdTime.named(master.tz ?? tz).dateOfMs(original).iso : null);
    if (row.status == 'cancelled') {
      await api.delete(s.remoteId!, instanceId);
      await kernel.upsert('events', row.id, {'remote_id': instanceId});
      return true;
    }
    final updated = await api.patch(s.remoteId!, instanceId, {...googleBodyFromEvent(row, householdTz: tz, withReminders: true), 'status': 'confirmed'});
    await kernel.upsert('events', row.id, {'remote_id': instanceId, 'etag': updated.etag, 'updated_ms': updated.updatedMs});
    return true;
  }

  /// Field-level LWW against the remote copy: whichever side changed last
  /// wins (SPEC §13.2). The device edit time is the newest field HLC.
  Future<void> _resolveConflict(GoogleCalendarApi api, CalendarSource s, Event row, Map<String, Object?> body) async {
    final remote = await api.get(s.remoteId!, row.remoteId!);
    if (remote == null) return;
    final clocks = decodeClock(row.syncClock).values.map(Hlc.tryParse).whereType<Hlc>();
    final localMs = clocks.isEmpty ? 0 : clocks.map((h) => h.millis).reduce((a, b) => a > b ? a : b);
    if ((remote.updatedMs ?? 0) > localMs) {
      await kernel.upsert('events', row.id, {...remote.toFields(s.id), 'recurring_parent_id': row.recurringParentId});
    } else {
      final forced = await api.patch(s.remoteId!, row.remoteId!, body);
      await kernel.upsert('events', row.id, {'etag': forced.etag, 'updated_ms': forced.updatedMs});
    }
  }

  // ─────────────────────────── Family calendar ─────────────────────────────

  /// FR-CAL-04: a shared "Family" calendar in [account]'s Google, shared
  /// with [share] (they get Google's email to add it), made the default for
  /// new events. With [move], the Hub's own Family calendar hands its events
  /// over (they go up on the next push) and steps aside. Asking again
  /// returns the calendar already made.
  Future<Map<String, Object?>> createFamilyCalendar({required String account, List<String> share = const [], bool move = false}) async {
    final db = kernel.db;
    final setting = await integrations.setting(SettingKeys.calendarGoogleFamily);
    if (setting['source'] is String) {
      final existing = await (db.select(db.calendarSources)..where((t) => t.id.equals(setting['source']! as String))).getSingleOrNull();
      if (existing != null && !existing.deleted) return {'source': existing.id, 'account': existing.accountId, 'shared': setting['shared'] ?? const <String>[], 'failed': const <String>[], 'moved': 0};
    }
    final tz = (await integrations.household())?.timezone ?? 'UTC';
    final api = _api(account, tz);
    final remoteId = await api.createCalendar('Family', timeZone: tz, description: 'The family calendar on Dearth: events added on the wall land here.');
    final shared = <String>[], failed = <String>[];
    for (final raw in share) {
      final email = raw.trim().toLowerCase();
      if (email.isEmpty || email == account.toLowerCase() || shared.contains(email)) continue;
      try {
        await api.share(remoteId, email);
        shared.add(email);
      } on ProviderException catch (e) {
        _log.warning('Sharing the Family calendar with $email failed: $e');
        failed.add(email);
      }
    }

    final id = stableId('gcal', [account, remoteId]);
    final local = await (db.select(db.calendarSources)..where((t) => t.id.equals(Ids.familyCalendar))).getSingleOrNull();
    final others = await (db.select(db.calendarSources)..where((t) => t.isDefault.equals(true) & t.id.equals(id).not())).get();
    final moving = move ? await (db.select(db.events)..where((t) => t.sourceId.equals(Ids.familyCalendar) & t.deleted.equals(false))).get() : const <Event>[];
    final reminders = await integrations.setting(SettingKeys.calendarReminders);
    final m = kernel.mutator;
    Op put(String key, Object? value) => m.makeOp('settings', Ids.setting('household', key), {'scope': 'household', 'key': key, 'value': value});
    await kernel.write([
      m.makeOp('calendar_sources', id, {
        'kind': 'google',
        'account_id': account,
        'remote_id': remoteId,
        'name': 'Family',
        'color': local?.color ?? 0xFF5B5BD6,
        'default_profile_ids': local?.defaultProfileIds ?? '[]',
        'writable': true,
        'enabled': true,
        'is_default': true,
        'deleted': false,
      }),
      for (final o in others) m.makeOp('calendar_sources', o.id, {'is_default': false}),
      if (move && local != null) m.makeOp('calendar_sources', local.id, {'enabled': false, 'is_default': false}),
      for (final e in moving) m.makeOp('events', e.id, {'source_id': id}),
      put(SettingKeys.calendarGoogleFamily, {'source': id, 'account': account, 'shared': shared}),
      // New events in it start with the reminders the Hub's Family had.
      if (reminders[Ids.familyCalendar] case final List<Object?> leads) put(SettingKeys.calendarReminders, {...reminders, id: leads}),
    ]);
    // Moved events carry their reminders up with them.
    for (final e in moving) {
      _dirty.add(e.id);
      _remindersTouched.add(e.id);
    }
    onTrigger?.call();
    return {'source': id, 'account': account, 'shared': shared, 'failed': failed, 'moved': moving.length};
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
