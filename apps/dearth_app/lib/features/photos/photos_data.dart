import 'dart:math' as math;

import 'package:dearth_core/dearth_core.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

final photoSourcesProvider = StreamProvider<List<PhotoSource>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.photoSources)..where((s) => s.deleted.equals(false))).watch();
});

/// Every photo item of every source, newest first.
final _allPhotoItemsProvider = StreamProvider<List<PhotoItem>>((ref) {
  final db = ref.watch(dbProvider);
  return (db.select(db.photoItems)
        ..where((p) => p.deleted.equals(false) & p.blobRef.isNotNull())
        ..orderBy([(p) => OrderingTerm.desc(p.takenMs), (p) => OrderingTerm.desc(p.addedMs)]))
      .watch();
});

/// Every photo, newest first (curation grid). A photo in two sources (one
/// album shared twice, or in two albums of a group) is the same image, so
/// the same blob: it shows once.
final photoItemsProvider = Provider<AsyncValue<List<PhotoItem>>>((ref) => ref.watch(_allPhotoItemsProvider).whenData(uniquePhotos));

/// [items] without repeats of one image, the first of each kept.
List<PhotoItem> uniquePhotos(List<PhotoItem> items) {
  final seen = <String>{};
  return [for (final p in items) if (seen.add(p.blobRef ?? p.id)) p];
}

/// Photos eligible for the screensaver: enabled sources, not hidden. Null
/// until both queries have loaded, so the frame can tell "still loading"
/// from "no photos" (which falls back to the art pack).
final screensaverPoolProvider = Provider<List<PhotoItem>?>((ref) {
  final sources = ref.watch(photoSourcesProvider).value;
  final items = ref.watch(_allPhotoItemsProvider).value;
  if (sources == null || items == null) return null;
  final enabled = {for (final s in sources) if (s.enabled) s.id};
  // Hiding a photo hides the image, whichever copy the grid showed.
  final hidden = {for (final p in items) if (p.hidden) p.blobRef};
  return uniquePhotos([for (final p in items) if (!hidden.contains(p.blobRef) && enabled.contains(p.sourceId)) p]);
});

bool isPortrait(PhotoItem p) => (p.height ?? 0) > (p.width ?? 1) * 1.05;

/// One screen of the frame: a photo, a pair of portraits, or bundled art.
class Slide {
  const Slide.photos(this.photos) : art = null;
  const Slide.art(int this.art) : photos = const [];
  final List<PhotoItem> photos;
  final int? art;

  String get key => art != null ? 'art$art' : photos.map((p) => p.id).join('+');
}

/// Shuffle without repeats until the pool is exhausted, with recent-history
/// suppression across reshuffles (FR-SSV-02), pairing portraits taken near
/// each other on landscape screens (FR-SSV-04).
class SlideDeck {
  SlideDeck({math.Random? random}) : _random = random ?? math.Random();
  final math.Random _random;
  final List<PhotoItem> _queue = [];
  final List<String> _recent = [];
  int _artIndex = 0;

  Slide next(List<PhotoItem> pool, {required bool landscape, required int artCount}) {
    if (pool.isEmpty) return Slide.art(_artIndex++ % artCount);
    if (_queue.isEmpty) {
      final recent = _recent.toSet();
      final fresh = pool.where((p) => !recent.contains(p.id)).toList()..shuffle(_random);
      final rest = pool.where((p) => recent.contains(p.id)).toList()..shuffle(_random);
      _queue.addAll([...fresh, ...rest]);
    }
    final first = _queue.removeAt(0);
    _remember(first.id, pool.length);
    if (landscape && isPortrait(first)) {
      final i = _queue.indexWhere((p) => isPortrait(p) && _near(p, first));
      if (i >= 0) {
        final second = _queue.removeAt(i);
        _remember(second.id, pool.length);
        return Slide.photos([first, second]);
      }
    }
    return Slide.photos([first]);
  }

  bool _near(PhotoItem a, PhotoItem b) {
    if (a.takenMs == null || b.takenMs == null) return a.sourceId == b.sourceId;
    return (a.takenMs! - b.takenMs!).abs() < 3 * 86400000;
  }

  void _remember(String id, int poolSize) {
    _recent.add(id);
    final keep = math.max(1, poolSize ~/ 2);
    while (_recent.length > keep) {
      _recent.removeAt(0);
    }
  }
}
