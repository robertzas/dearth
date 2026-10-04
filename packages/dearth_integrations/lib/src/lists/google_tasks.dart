import 'package:dearth_core/dearth_core.dart';
import 'package:meta/meta.dart';

import '../http/fetcher.dart';

/// A task in Google Tasks (API v1).
@immutable
class GoogleTask {
  const GoogleTask({required this.id, required this.title, this.notes, this.completed = false, required this.updatedMs, this.deleted = false, this.hidden = false});

  factory GoogleTask.fromJson(Map<String, Object?> j) => GoogleTask(
        id: j.str('id') ?? '',
        title: j.str('title') ?? '',
        notes: j.str('notes'),
        completed: j.str('status') == 'completed',
        updatedMs: DateTime.tryParse(j.str('updated') ?? '')?.millisecondsSinceEpoch ?? 0,
        deleted: j.boolean('deleted') ?? false,
        hidden: j.boolean('hidden') ?? false,
      );

  final String id;
  final String title;
  final String? notes;
  final bool completed;
  final int updatedMs;
  final bool deleted;

  /// A completed task cleared away in Google Tasks ("Delete all completed").
  final bool hidden;

  /// Gone from the list, one way or another.
  bool get gone => deleted || hidden;

  @override
  String toString() => 'GoogleTask($id, $title${completed ? ', done' : ''}${gone ? ', gone' : ''})';
}

@immutable
class GoogleTaskList {
  const GoogleTaskList({required this.id, required this.title});
  final String id;
  final String title;
}

/// Google Tasks API v1 (owner's choice for list sync: Keep has no API for
/// personal accounts). [token] returns a fresh access token.
class GoogleTasksApi {
  GoogleTasksApi(this.fetcher, this.token, {Uri? base}) : base = base ?? Uri.parse('https://tasks.googleapis.com/tasks/v1');

  final Fetcher fetcher;
  final Future<String> Function() token;
  final Uri base;
  static const provider = 'google-tasks';
  static const scope = 'https://www.googleapis.com/auth/tasks';

  Future<Map<String, String>> _auth() async => {'Authorization': 'Bearer ${await token()}'};
  Uri _u(String path, [Map<String, String>? q]) => Uri.parse('$base$path').replace(queryParameters: q);
  String _e(String id) => Uri.encodeComponent(id);

  Future<List<GoogleTaskList>> taskLists() async {
    final out = <GoogleTaskList>[];
    String? page;
    do {
      final j = asObject(await fetcher.getJson(provider, _u('/users/@me/lists', {'maxResults': '100', 'pageToken': ?page}), headers: await _auth()), provider);
      for (final l in j.arr('items')) {
        if (l is Map<String, Object?>) out.add(GoogleTaskList(id: l.str('id') ?? '', title: l.str('title') ?? ''));
      }
      page = j.str('nextPageToken');
    } while (page != null);
    return out;
  }

  Future<GoogleTaskList> insertTaskList(String title) async {
    final j = asObject(await fetcher.postJson(provider, _u('/users/@me/lists'), headers: await _auth(), body: {'title': title}), provider);
    return GoogleTaskList(id: j.str('id') ?? '', title: j.str('title') ?? title);
  }

  /// Every task of [listId] (or only those changed since [updatedMinMs]),
  /// completed, deleted and cleared ones included, so changes of every kind
  /// arrive.
  Future<List<GoogleTask>> tasks(String listId, {int? updatedMinMs}) async {
    final out = <GoogleTask>[];
    String? page;
    do {
      final q = {
        'maxResults': '100',
        'showCompleted': 'true',
        'showDeleted': 'true',
        'showHidden': 'true',
        'pageToken': ?page,
        if (updatedMinMs != null) 'updatedMin': DateTime.fromMillisecondsSinceEpoch(updatedMinMs, isUtc: true).toIso8601String(),
      };
      final j = asObject(await fetcher.getJson(provider, _u('/lists/${_e(listId)}/tasks', q), headers: await _auth()), provider);
      for (final t in j.arr('items')) {
        if (t is Map<String, Object?>) out.add(GoogleTask.fromJson(t));
      }
      page = j.str('nextPageToken');
    } while (page != null);
    return out;
  }

  static Map<String, Object?> _body({required String title, String? notes, required bool completed}) => {
        'title': title,
        'notes': notes ?? '',
        'status': completed ? 'completed' : 'needsAction',
        // Reopening a task clears its completion time.
        if (!completed) 'completed': null,
      };

  Future<GoogleTask> insertTask(String listId, {required String title, String? notes, bool completed = false}) async => GoogleTask.fromJson(asObject(
        await fetcher.postJson(provider, _u('/lists/${_e(listId)}/tasks'), headers: await _auth(), body: _body(title: title, notes: notes, completed: completed)),
        provider,
      ));

  Future<GoogleTask> patchTask(String listId, String taskId, {required String title, String? notes, required bool completed}) async {
    final res = await fetcher.send(
      provider,
      'PATCH',
      _u('/lists/${_e(listId)}/tasks/${_e(taskId)}'),
      headers: await _auth(),
      body: _body(title: title, notes: notes, completed: completed),
      retry: false,
    );
    return GoogleTask.fromJson(asObject(fetcher.decodeResponse(provider, res), provider));
  }

  Future<void> deleteTask(String listId, String taskId) async {
    try {
      await fetcher.send(provider, 'DELETE', _u('/lists/${_e(listId)}/tasks/${_e(taskId)}'), headers: await _auth(), retry: false);
    } on ProviderException catch (e) {
      if (e.status == 404 || e.status == 410) return; // already gone
      rethrow;
    }
  }
}

// ─────────────────────────────── Sync planning ──────────────────────────────

/// A Dearth list item as the sync sees it.
@immutable
class TaskSyncItem {
  const TaskSyncItem({required this.id, required this.text, this.note, this.checked = false, this.deleted = false, required this.changedMs});
  final String id;
  final String text;

  /// Shopping amounts live here ("1 lb"), as a task's notes do.
  final String? note;
  final bool checked;
  final bool deleted;

  /// When it last changed on any device: its newest field clock.
  final int changedMs;
}

/// A linked pair as the sync remembers it: the task, and when both sides
/// last matched. A change on either side after that is news.
@immutable
class TaskLink {
  const TaskLink(this.taskId, this.syncedMs);
  final String taskId;
  final int syncedMs;
}

/// One write a sync round makes.
sealed class TaskSyncAction {
  const TaskSyncAction();
}

/// A new Dearth item becomes a task.
class InsertTask extends TaskSyncAction {
  const InsertTask(this.item);
  final TaskSyncItem item;
}

/// A Dearth item changed: its task follows.
class PatchTask extends TaskSyncAction {
  const PatchTask(this.item, this.taskId);
  final TaskSyncItem item;
  final String taskId;
}

/// A Dearth item was deleted: so is its task.
class DeleteTask extends TaskSyncAction {
  const DeleteTask(this.itemId, this.taskId);
  final String itemId;
  final String taskId;
}

/// A new task becomes a Dearth item.
class InsertItem extends TaskSyncAction {
  const InsertItem(this.task);
  final GoogleTask task;
}

/// A task changed (or matched an unlinked item by its words): the item
/// follows, coming back if it had been deleted.
class UpdateItem extends TaskSyncAction {
  const UpdateItem(this.itemId, this.task);
  final String itemId;
  final GoogleTask task;
}

/// A task was deleted or cleared: so is its item.
class DeleteItem extends TaskSyncAction {
  const DeleteItem(this.itemId);
  final String itemId;
}

/// An unlinked item and task with the same words: linked, and [then]
/// brings the older side up to date.
class LinkPair extends TaskSyncAction {
  const LinkPair(this.itemId, this.task, this.then);
  final String itemId;
  final GoogleTask task;
  final TaskSyncAction? then;
}

/// Both sides are gone: forget the link.
class Forget extends TaskSyncAction {
  const Forget(this.itemId);
  final String itemId;
}

String _words(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Plans one round of two-way sync between a Dearth list and a Google task
/// list. [items]: every item of the list, tombstones included. [remote]: the
/// tasks that changed since the last round (all of them on the first).
/// [links]: item id → task. Per item, the side that changed last wins; a
/// write the sync made itself is never news (the links remember when both
/// sides matched). On the first round, items and tasks with the same words
/// are linked instead of copied, so a list that already exists on both
/// sides doesn't double.
List<TaskSyncAction> planTaskSync({required List<TaskSyncItem> items, required List<GoogleTask> remote, required Map<String, TaskLink> links}) {
  final out = <TaskSyncAction>[];
  final itemsById = {for (final i in items) i.id: i};
  final remoteById = {for (final t in remote) t.id: t};
  final linkedTasks = {for (final l in links.values) l.taskId};

  for (final MapEntry(key: itemId, value: link) in links.entries) {
    final item = itemsById[itemId];
    final task = remoteById[link.taskId];
    final localNews = item != null && item.changedMs > link.syncedMs;
    final remoteNews = task != null && task.updatedMs > link.syncedMs;
    if (localNews && (!remoteNews || item.changedMs >= task.updatedMs)) {
      out.add(item.deleted ? DeleteTask(itemId, link.taskId) : PatchTask(item, link.taskId));
    } else if (remoteNews) {
      if (!task.gone) {
        out.add(UpdateItem(itemId, task));
      } else if (item != null && !item.deleted) {
        out.add(DeleteItem(itemId));
      } else {
        out.add(Forget(itemId));
      }
    }
  }

  // New on each side: pair up equal words first.
  final freshItems = [for (final i in items) if (!links.containsKey(i.id) && !i.deleted) i];
  final freshTasks = [for (final t in remote) if (!linkedTasks.contains(t.id) && !t.gone) t];
  final byWords = <String, List<GoogleTask>>{};
  for (final t in freshTasks) {
    (byWords[_words(t.title)] ??= []).add(t);
  }
  final paired = <String>{};
  for (final i in freshItems) {
    final match = byWords[_words(i.text)];
    if (match != null && match.isNotEmpty) {
      final t = match.removeAt(0);
      paired.add(t.id);
      final same = i.checked == t.completed && (i.note ?? '') == (t.notes ?? '');
      out.add(LinkPair(i.id, t, same ? null : (i.changedMs >= t.updatedMs ? PatchTask(i, t.id) : UpdateItem(i.id, t))));
    } else {
      out.add(InsertTask(i));
    }
  }
  for (final t in freshTasks) {
    if (!paired.contains(t.id)) out.add(InsertItem(t));
  }
  return out;
}
