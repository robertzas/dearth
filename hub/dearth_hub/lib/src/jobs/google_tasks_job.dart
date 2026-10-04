import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_integrations/dearth_integrations.dart';
import 'package:logging/logging.dart';

import '../integrations.dart';
import '../kernel.dart';
import '../storage.dart';
import 'scheduler.dart';

final _log = Logger('google-tasks');

/// Two-way list sync with Google Tasks (the owner's choice: Google Keep has
/// no API for personal accounts). Each chosen Dearth list mirrors the Google
/// task list of the same name, found or made on the first round. Tasks has
/// no push notifications, so remote changes are polled; an edit on any
/// display starts a round at once.
///
/// What the sync remembers per list lives in its job state: the task list,
/// when it last pulled, and each item's task with the time both last
/// matched (see [planTaskSync]).
class GoogleTasksJob implements HubJob {
  GoogleTasksJob(this.integrations, this.jobs, {this.onTrigger}) {
    integrations.kernel.addListener(_onOps);
  }

  final Integrations integrations;
  final JobStore jobs;

  /// Asks the scheduler to run this job soon.
  final void Function()? onTrigger;

  HubKernel get kernel => integrations.kernel;

  @override
  String get id => 'google-tasks';

  @override
  Duration nextDelay() => const Duration(minutes: 3);

  void _onOps(List<SeqOp> ops, DeviceIdentity origin) {
    if (origin.deviceId == DeviceIdentity.hub.deviceId) return;
    if (ops.any((o) => o.op.table == 'list_items' || (o.op.table == 'settings' && o.op.rowId.endsWith(SettingKeys.listsGoogleTasks)))) onTrigger?.call();
  }

  @override
  Future<void> run() async {
    final setting = await integrations.setting(SettingKeys.listsGoogleTasks);
    final listIds = [for (final l in setting['lists'] is List ? setting['lists']! as List : const []) '$l'];
    if (listIds.isEmpty) return;
    final account = await tasksAccount(setting['account'] as String?);
    if (account == null) {
      await integrations.report('google-tasks', ok: false, message: 'Allow Google Tasks: sign in to Google again from Settings → Lists');
      return;
    }
    final api = GoogleTasksApi(integrations.fetcher, () => integrations.googleAccessToken(account));
    var ok = true;
    String? problem;
    for (final listId in listIds) {
      try {
        await _syncList(api, listId);
      } on ProviderException catch (e) {
        ok = false;
        problem = e.isAuth ? 'Reconnect Google ($account)' : e.message;
        _log.warning('Google Tasks sync of $listId failed: $e');
      }
    }
    await integrations.report('google-tasks', ok: ok, message: problem ?? 'Synced ${listIds.length} ${listIds.length == 1 ? 'list' : 'lists'} with Google Tasks ($account)');
  }

  /// The Google account to sync with: the chosen one, else the first that
  /// allowed Google Tasks.
  Future<String?> tasksAccount(String? chosen) async {
    for (final id in await integrations.googleAccounts()) {
      if (chosen != null && chosen.isNotEmpty && id != chosen) continue;
      final stored = await integrations.vault.getJson('${SecretIds.googleAccountPrefix}$id');
      final tokens = stored?['tokens'];
      final scope = tokens is Map ? tokens['scope'] as String? ?? '' : '';
      if (scope.contains(GoogleTasksApi.scope)) return id;
    }
    return null;
  }

  static int _changedMs(String? clock) {
    final clocks = decodeClock(clock).values.map(Hlc.tryParse).whereType<Hlc>();
    return clocks.isEmpty ? 0 : clocks.map((h) => h.millis).reduce(math.max);
  }

  Future<void> _syncList(GoogleTasksApi api, String listId) async {
    final db = kernel.db;
    final list = await (db.select(db.lists)..where((t) => t.id.equals(listId))).getSingleOrNull();
    if (list == null || list.deleted) return;
    final stateId = 'gtasks:$listId';
    final state = await jobs.data(stateId);
    var taskList = state['taskList'] as String?;
    if (taskList == null) {
      final name = list.title.trim().toLowerCase();
      final existing = (await api.taskLists()).where((l) => l.title.trim().toLowerCase() == name).firstOrNull;
      taskList = (existing ?? await api.insertTaskList(list.title)).id;
    }
    final links = <String, TaskLink>{
      if (state['links'] is Map)
        for (final e in (state['links']! as Map).entries)
          if (e.value is List && (e.value as List).length == 2) '${e.key}': TaskLink('${(e.value as List)[0]}', ((e.value as List)[1] as num).toInt()),
    };
    final roundStart = DateTime.now().millisecondsSinceEpoch;
    final pulled = (state['pulledMs'] as num?)?.toInt();
    // A minute of overlap: a task updated during the last round isn't missed.
    final remote = await api.tasks(taskList, updatedMinMs: pulled == null ? null : pulled - 60000);
    final rows = await (db.select(db.listItems)..where((t) => t.listId.equals(listId))).get();
    final items = [
      for (final r in rows) TaskSyncItem(id: r.id, text: r.itemText, note: r.note, checked: r.checked, deleted: r.deleted, changedMs: _changedMs(r.syncClock)),
    ];
    var lastKey = rows.where((r) => !r.deleted).map((r) => r.sortKey).fold<String?>(null, (a, b) => a == null || b.compareTo(a) > 0 ? b : a);
    final touched = <String>{};
    for (final action in planTaskSync(items: items, remote: remote, links: links)) {
      lastKey = await _apply(action, api, taskList, list, links, touched, lastKey);
    }
    if (touched.isNotEmpty) {
      // The sync's own writes aren't news next round: each link remembers the
      // clock its write left on the item.
      final fresh = await (db.select(db.listItems)..where((t) => t.id.isIn(touched))).get();
      for (final r in fresh) {
        final l = links[r.id];
        if (l != null) links[r.id] = TaskLink(l.taskId, math.max(l.syncedMs, _changedMs(r.syncClock)));
      }
    }
    await jobs.write(stateId, data: {
      'taskList': taskList,
      'pulledMs': roundStart,
      'links': {for (final e in links.entries) e.key: [e.value.taskId, e.value.syncedMs]},
    });
  }

  /// Applies one planned write; returns the list's last sort key.
  Future<String?> _apply(TaskSyncAction a, GoogleTasksApi api, String taskList, DList list, Map<String, TaskLink> links, Set<String> touched, String? lastKey) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    Map<String, Object?> fieldsOf(GoogleTask t) => {
          'text': t.title,
          'note': (t.notes ?? '').isEmpty ? null : t.notes,
          'checked': t.completed,
          'checked_ms': t.completed ? (t.updatedMs == 0 ? now : t.updatedMs) : null,
          'deleted': false,
        };
    switch (a) {
      case InsertTask(:final item):
        final t = await api.insertTask(taskList, title: item.text, notes: item.note, completed: item.checked);
        links[item.id] = TaskLink(t.id, [t.updatedMs, now, item.changedMs].reduce(math.max));
      case PatchTask(:final item, :final taskId):
        final t = await api.patchTask(taskList, taskId, title: item.text, notes: item.note, completed: item.checked);
        links[item.id] = TaskLink(taskId, [t.updatedMs, now, item.changedMs].reduce(math.max));
      case DeleteTask(:final itemId, :final taskId):
        await api.deleteTask(taskList, taskId);
        links.remove(itemId);
      case InsertItem(:final task):
        final itemId = stableId('gtask', [list.id, task.id]);
        lastKey = sortKeyAfter(lastKey);
        await kernel.upsert('list_items', itemId, {
          'list_id': list.id,
          ...fieldsOf(task),
          // Shopping lists group by aisle, as if typed on a display.
          'category': list.kind == 'shopping' ? parseIngredientLine(task.title).aisle.name : null,
          'sort_key': lastKey,
        });
        links[itemId] = TaskLink(task.id, math.max(now, task.updatedMs));
        touched.add(itemId);
      case UpdateItem(:final itemId, :final task):
        await kernel.upsert('list_items', itemId, fieldsOf(task));
        links[itemId] = TaskLink(task.id, math.max(now, task.updatedMs));
        touched.add(itemId);
      case DeleteItem(:final itemId):
        await kernel.delete('list_items', itemId);
        links.remove(itemId);
      case LinkPair(:final itemId, :final task, :final then):
        links[itemId] = TaskLink(task.id, math.max(now, task.updatedMs));
        if (then != null) lastKey = await _apply(then, api, taskList, list, links, touched, lastKey);
      case Forget(:final itemId):
        links.remove(itemId);
    }
    return lastKey;
  }
}
