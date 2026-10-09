import 'dart:async';

import '../sync/hub_api.dart';

/// Reports a move's progress: what is happening, and how far along (0–1)
/// when that is known.
typedef MoveProgress = void Function(String step, double? fraction);

/// Copies a household from one Hub to another (SPEC §7.2, §8.7): the
/// pictures its rows point at first, so nothing shows broken, then every
/// row. Both Hubs need admin access ([HubApi.adminPassword] or an admin
/// device token). The household that moves takes over where both Hubs have
/// the same row; the source keeps its copy.
Future<void> moveHousehold(HubApi from, HubApi to, {MoveProgress? onProgress}) async {
  onProgress?.call('Reading the family’s data…', null);
  final export = await from.exportHousehold();
  final blobs = [
    for (final b in export['blobs'] as List? ?? const [])
      if (b is Map<String, Object?> && b['sha'] is String) b,
  ];
  if (blobs.isNotEmpty) {
    final missing = (await to.missingBlobs([for (final b in blobs) b['sha']! as String])).toSet();
    final todo = [for (final b in blobs) if (missing.contains(b['sha'])) b];
    var done = 0;
    // A few at a time: photo albums run to hundreds of files.
    final queue = todo.iterator;
    Future<void> worker() async {
      while (queue.moveNext()) {
        final b = queue.current;
        final sha = b['sha']! as String;
        try {
          final bytes = await from.blobBytes(sha);
          await to.putBlob(sha, bytes, mime: b['mime'] as String? ?? 'application/octet-stream', origin: b['origin'] as String?);
        } on HubApiException catch (e) {
          // Gone from the source already: nothing to carry.
          if (e.code != 'blob_missing') rethrow;
        }
        done++;
        onProgress?.call('Copying photos and pictures…', done / todo.length);
      }
    }

    if (todo.isNotEmpty) {
      onProgress?.call('Copying photos and pictures…', 0);
      await Future.wait([for (var i = 0; i < 3; i++) worker()]);
    }
  }
  onProgress?.call('Copying the family’s data…', null);
  await to.importHousehold(export);
}
