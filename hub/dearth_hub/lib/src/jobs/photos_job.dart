import 'dart:async';
import 'dart:io';

import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_integrations/dearth_integrations.dart';
import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../blobs.dart';
import '../config.dart';
import '../integrations.dart';
import '../storage.dart';
import 'scheduler.dart';

final _log = Logger('photos');

/// Photo sources → normalized blobs + `photo_items` (SPEC §13.5). Sources are
/// listed, new items downloaded with bounded concurrency into display-ready
/// 2048-px derivatives, and items that left the source are tombstoned.
class PhotosJob implements HubJob {
  PhotosJob(this.integrations, this.blobs, this.jobs, this.config);
  final Integrations integrations;
  final BlobStore blobs;
  final JobStore jobs;
  final HubConfig config;

  static const _maxNewPerRun = 150;

  @override
  String get id => 'photos';

  @override
  Duration nextDelay() => const Duration(minutes: 60);

  DearthDb get db => integrations.db;

  @override
  Future<void> run() async {
    final sources = await (db.select(db.photoSources)..where((t) => t.enabled.equals(true) & t.deleted.equals(false))).get();
    for (final s in sources) {
      try {
        final cfg = decodeJsonMap(s.config);
        final (title, listing, prune) = await _list(s, cfg);
        final added = await _sync(s, listing, prune: prune);
        final count = await (db.select(db.photoItems)..where((t) => t.sourceId.equals(s.id) & t.deleted.equals(false))).get();
        await integrations.kernel.upsert('photo_sources', s.id, {
          'status': added == 0 ? 'ok' : 'ok · $added new',
          'item_count': count.length,
          'last_sync_ms': DateTime.now().millisecondsSinceEpoch,
          if (title != null && s.name == 'Photos') 'name': title,
        });
      } on Object catch (e) {
        _log.warning('Photo source ${s.name} failed: $e');
        await integrations.kernel.upsert('photo_sources', s.id, {'status': 'error · $e'});
      }
    }
  }

  /// (album title, photos, prune missing?)
  Future<(String?, List<_Item>, bool)> _list(PhotoSource s, Map<String, Object?> cfg) async {
    final fetcher = integrations.fetcher;
    switch (s.kind) {
      case 'folder':
        final path = cfg['path'] as String? ?? '';
        if (!_allowedFolder(path)) throw StateError('Folder $path is not under DEARTH_PHOTO_DIRS');
        return (null, _scanFolder(path), true);
      case 'amazon':
        final link = AmazonShareLink.parse(cfg['shareUrl'] as String? ?? '');
        if (link == null) throw StateError('Invalid Amazon share link');
        final (title, photos) = await AmazonSharedAlbum(fetcher).list(link);
        return (title, photos.map(_Item.remote).toList(), true);
      case 'immich':
        final key = await integrations.secretField('${SecretIds.immichPrefix}${s.id}', 'apiKey');
        if (key == null) throw StateError('Immich API key missing');
        final client = ImmichClient(fetcher, cfg['url'] as String? ?? '', key);
        final albums = [for (final a in (cfg['albumIds'] as List? ?? const [])) '$a'];
        final photos = <RemotePhoto>[];
        if (albums.isNotEmpty) {
          for (final a in albums) {
            photos.addAll(await client.album(a));
          }
        } else {
          photos.addAll(await client.random((cfg['poolSize'] as num?)?.toInt() ?? 300, favorites: cfg['favorites'] as bool?));
        }
        if (cfg['memories'] == true) {
          final tz = (await integrations.household())?.timezone;
          photos.addAll(await client.memories(HouseholdTime.named(tz).today()));
        }
        return (null, photos.map(_Item.remote).toList(), albums.isNotEmpty);
      case 'google':
        return (null, await _pickerItems(s), false);
      default:
        return (null, const <_Item>[], false);
    }
  }

  bool _allowedFolder(String path) {
    if (path.isEmpty || config.photoDirs.isEmpty) return false;
    final real = p.canonicalize(path);
    return config.photoDirs.any((d) => p.isWithin(p.canonicalize(d), real) || p.canonicalize(d) == real);
  }

  List<_Item> _scanFolder(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) throw StateError('Folder not found: $path');
    final out = <_Item>[];
    for (final f in dir.listSync(recursive: true, followLinks: false).whereType<File>()) {
      final ext = p.extension(f.path).toLowerCase();
      if (!const {'.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif'}.contains(ext)) continue;
      if (p.split(f.path).any((seg) => seg.startsWith('.'))) continue;
      out.add(_Item(remoteId: p.relative(f.path, from: path), file: f, takenMs: f.statSync().modified.millisecondsSinceEpoch));
      if (out.length >= 10000) break;
    }
    return out;
  }

  Future<List<_Item>> _pickerItems(PhotoSource s) async {
    final stateId = 'gpicker:${s.id}';
    final state = await jobs.data(stateId);
    final sessionId = state['sessionId'] as String?;
    if (sessionId == null) return const [];
    final account = (await integrations.googleAccounts()).firstOrNull;
    if (account == null) return const [];
    final picker = GooglePhotosPicker(integrations.fetcher, () => integrations.googleAccessToken(account));
    final session = await picker.getSession(sessionId);
    if (!session.itemsSet) return const [];
    final items = await picker.listItems(sessionId);
    await jobs.write(stateId, data: {'sessionId': null, 'lastPicked': items.length});
    unawaited(picker.deleteSession(sessionId).catchError((Object _) {}));
    return items.map(_Item.remote).toList();
  }

  Future<int> _sync(PhotoSource s, List<_Item> listing, {required bool prune}) async {
    final existing = await (db.select(db.photoItems)..where((t) => t.sourceId.equals(s.id))).get();
    final byRemote = {for (final e in existing) e.remoteId: e};
    final fresh = listing.where((i) => byRemote[i.remoteId] == null || byRemote[i.remoteId]!.deleted).take(_maxNewPerRun).toList();
    var added = 0;
    final queue = [...fresh];
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final item = queue.removeLast();
        try {
          final blob = item.file != null
              ? await blobs.putImage(await item.file!.readAsBytes())
              : await blobs.fetchRemoteImage(integrations.fetcher, item.remote!.downloadUrl, headers: item.remote!.headers);
          if (blob == null) continue;
          await integrations.kernel.upsert('photo_items', stableId('photo', [s.id, item.remoteId]), {
            'source_id': s.id,
            'remote_id': item.remoteId,
            'taken_ms': item.takenMs ?? item.remote?.takenMs,
            'width': blob.width ?? item.remote?.width,
            'height': blob.height ?? item.remote?.height,
            'caption': item.remote?.caption,
            'location': item.remote?.location,
            'blob_ref': blob.sha,
            'favorite': item.remote?.favorite ?? false,
            'added_ms': DateTime.now().millisecondsSinceEpoch,
            'deleted': false,
          });
          added++;
        } on Object catch (e) {
          _log.fine('Skipping ${item.remoteId}: $e');
        }
      }
    }

    await Future.wait(List.generate(3, (_) => worker()));
    if (prune) {
      final present = {for (final i in listing) i.remoteId};
      final gone = existing.where((e) => !e.deleted && !present.contains(e.remoteId)).toList();
      for (final e in gone) {
        await integrations.kernel.delete('photo_items', e.id);
      }
    }
    return added;
  }
}

class _Item {
  _Item({required this.remoteId, this.file, this.remote, this.takenMs});
  factory _Item.remote(RemotePhoto r) => _Item(remoteId: r.remoteId, remote: r, takenMs: r.takenMs);
  final String remoteId;
  final File? file;
  final RemotePhoto? remote;
  final int? takenMs;
}
