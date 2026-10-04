import 'dart:convert';

import 'package:dearth_integrations/dearth_integrations.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'helpers.dart';

/// List sync with Google Tasks (owner's choice; Keep has no API for
/// personal accounts): the API client against recorded-shape fixtures, and
/// the two-way sync planner.
void main() {
  group('Google Tasks API', () {
    test('task lists and tasks parse, deleted and cleared ones included', () async {
      final log = <http.Request>[];
      final f = fakeFetcher({
        path('/tasks/v1/users/@me/lists'): (_) => json(jsonDecode(fixture('google_tasklists.json')) as Object),
        pathEnds('/tasks'): (_) => json(jsonDecode(fixture('google_tasks.json')) as Object),
      }, log: log);
      final api = GoogleTasksApi(f, () async => 'tok');
      final lists = await api.taskLists();
      expect(lists.map((l) => l.title), ['My Tasks', 'Shopping']);
      final tasks = await api.tasks('R0dkUnFfbUZjYUg3ZkpnRA', updatedMinMs: DateTime.utc(2026, 10, 3, 14).millisecondsSinceEpoch);
      expect(tasks.map((t) => (t.title, t.completed, t.gone)), [('Milk', false, false), ('Eggs', true, false), ('Batteries', true, true), ('Bread', false, true)]);
      expect(tasks[1].notes, '1 dozen');
      expect(tasks.first.updatedMs, DateTime.utc(2026, 10, 3, 15).millisecondsSinceEpoch);
      final q = log.last.url.queryParameters;
      expect((q['showDeleted'], q['showHidden'], q['showCompleted'], q['updatedMin']), ('true', 'true', 'true', '2026-10-03T14:00:00.000Z'));
      expect(log.last.headers['Authorization'], 'Bearer tok');
    });

    test('writes send the title, notes and status; reopening clears the completion; a gone task deletes quietly', () async {
      final log = <http.Request>[];
      Map<String, Object?> body(http.Request r) => jsonDecode(r.body) as Map<String, Object?>;
      final f = fakeFetcher({
        (r) => r.method == 'POST': (r) => json({...body(r), 'id': 'new1', 'updated': '2026-10-04T08:00:00.000Z'}),
        (r) => r.method == 'PATCH': (r) => json({...body(r), 'id': 'dGFzay1taWxr', 'updated': '2026-10-04T08:01:00.000Z'}),
        (r) => r.method == 'DELETE': (_) => http.Response('', 404),
      }, log: log);
      final api = GoogleTasksApi(f, () async => 'tok');
      final created = await api.insertTask('L', title: 'Apples', notes: '6', completed: true);
      expect((created.id, created.title, created.completed), ('new1', 'Apples', true));
      expect(body(log.last), {'title': 'Apples', 'notes': '6', 'status': 'completed'});
      await api.patchTask('L', 'dGFzay1taWxr', title: 'Milk', completed: false);
      expect(body(log.last), {'title': 'Milk', 'notes': '', 'status': 'needsAction', 'completed': null});
      await api.deleteTask('L', 'gone');
      expect(log.last.method, 'DELETE');
    });
  });

  group('two-way sync plan', () {
    const t0 = 1000000;
    TaskSyncItem item(String id, String text, {int at = t0, bool checked = false, bool deleted = false, String? note}) =>
        TaskSyncItem(id: id, text: text, note: note, checked: checked, deleted: deleted, changedMs: at);
    GoogleTask task(String id, String title, {int at = t0, bool done = false, bool deleted = false, bool hidden = false, String? notes}) =>
        GoogleTask(id: id, title: title, notes: notes, completed: done, updatedMs: at, deleted: deleted, hidden: hidden);
    String describe(TaskSyncAction a) => switch (a) {
          InsertTask(:final item) => '+task ${item.text}',
          PatchTask(:final item) => '~task ${item.text}',
          DeleteTask(:final itemId) => '-task $itemId',
          InsertItem(:final task) => '+item ${task.title}',
          UpdateItem(:final itemId, :final task) => '~item $itemId ← ${task.title}${task.completed ? ' ✓' : ''}',
          DeleteItem(:final itemId) => '-item $itemId',
          LinkPair(:final itemId, :final task, :final then) => 'link $itemId=${task.id}${then == null ? '' : ' then ${describe(then)}'}',
          Forget(:final itemId) => 'forget $itemId',
        };
    List<String> plan(List<TaskSyncItem> items, List<GoogleTask> remote, [Map<String, TaskLink> links = const {}]) =>
        planTaskSync(items: items, remote: remote, links: links).map(describe).toList();

    test('the first round copies what is new on each side and links what both have', () {
      expect(
        plan([item('i1', 'Milk'), item('i2', 'Apples'), item('i3', 'Old', deleted: true)], [task('a', 'milk '), task('b', 'Bread'), task('c', 'Gone', deleted: true)]),
        ['link i1=a', '+task Apples', '+item Bread'],
      );
      expect(plan([item('i1', 'Milk', checked: true, at: t0 + 5)], [task('a', 'Milk')]), ['link i1=a then ~task Milk'], reason: 'the newer side settles a difference');
      expect(plan([item('i1', 'Milk')], [task('a', 'Milk', at: t0 + 5, done: true)]), ['link i1=a then ~item i1 ← Milk ✓']);
    });

    test('after that, whichever side changed last wins, and the sync never hears its own echo', () {
      const link = {'i1': TaskLink('a', t0)};
      expect(plan([item('i1', 'Milk')], [task('a', 'Milk')], link), isEmpty, reason: 'nothing new on either side');
      expect(plan([item('i1', 'Oat milk', at: t0 + 10)], [], link), ['~task Oat milk']);
      expect(plan([item('i1', 'Milk')], [task('a', 'Milk', at: t0 + 10, done: true)], link), ['~item i1 ← Milk ✓']);
      expect(plan([item('i1', 'Oat milk', at: t0 + 20)], [task('a', 'Soy milk', at: t0 + 10)], link), ['~task Oat milk'], reason: 'both changed: the later one');
      expect(plan([item('i1', 'Oat milk', at: t0 + 10)], [task('a', 'Soy milk', at: t0 + 20)], link), ['~item i1 ← Soy milk']);
    });

    test('deletions travel both ways; a cleared completed task counts as deleted', () {
      const link = {'i1': TaskLink('a', t0)};
      expect(plan([item('i1', 'Milk', deleted: true, at: t0 + 10)], [], link), ['-task i1']);
      expect(plan([item('i1', 'Milk')], [task('a', 'Milk', at: t0 + 10, deleted: true)], link), ['-item i1']);
      expect(plan([item('i1', 'Milk', checked: true)], [task('a', 'Milk', at: t0 + 10, done: true, hidden: true)], link), ['-item i1']);
      expect(plan([item('i1', 'Milk', deleted: true)], [task('a', 'Milk', at: t0 + 10, deleted: true)], link), ['forget i1']);
      expect(plan([item('i1', 'Milk', deleted: true)], [task('a', 'Milk', at: t0 + 10)], link), ['~item i1 ← Milk'], reason: 'edited in Google after the delete: it comes back');
    });
  });
}
