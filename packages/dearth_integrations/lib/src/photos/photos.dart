import 'package:dearth_core/dearth_core.dart';
import 'package:meta/meta.dart';

import '../http/fetcher.dart';

/// A photo discovered at a source; the Hub downloads [downloadUrl] (with
/// [headers]) into its blob store and renders derivatives (SPEC §13.5).
@immutable
class RemotePhoto {
  const RemotePhoto({
    required this.remoteId,
    required this.downloadUrl,
    this.headers = const {},
    this.takenMs,
    this.width,
    this.height,
    this.caption,
    this.location,
    this.favorite = false,
  });

  final String remoteId;
  final Uri downloadUrl;
  final Map<String, String> headers;
  final int? takenMs;
  final int? width;
  final int? height;
  final String? caption;
  final String? location;
  final bool favorite;
}

// ─────────────────────────── Amazon shared album ───────────────────────────

/// Parsed Amazon Photos share link. Both shared-album links
/// (`…/photos/share/{id}`) and group links (`…/photos/groups/share/{id}`)
/// resolve through the same share endpoints; [isGroup] tells them apart.
@immutable
class AmazonShareLink {
  const AmazonShareLink(this.tld, this.shareId, {this.isGroup = false});
  final String tld;
  final String shareId;
  final bool isGroup;

  static AmazonShareLink? parse(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    final m = RegExp(r'(?:^|\.)amazon\.([a-z.]+)$').firstMatch(host);
    if (m == null) return null;
    final segments = uri.pathSegments;
    final idx = segments.indexOf('share');
    if (idx < 0 || idx + 1 >= segments.length) return null;
    final id = segments[idx + 1];
    return RegExp(r'^[A-Za-z0-9_-]{10,}$').hasMatch(id) ? AmazonShareLink(m[1]!, id, isGroup: segments.contains('groups')) : null;
  }
}

/// Reads a public Amazon Photos shared album without credentials (SPEC
/// §13.5.1). Uses Amazon's undocumented share endpoints; validated in M0.
class AmazonSharedAlbum {
  AmazonSharedAlbum(this.fetcher);
  final Fetcher fetcher;
  static const provider = 'amazon-share';

  Uri _drive(AmazonShareLink link, String path, Map<String, String> q) =>
      Uri.https('www.amazon.${link.tld}', '/drive/v1/$path', {...q, 'shareId': link.shareId, 'resourceVersion': 'V2', 'ContentType': 'JSON'});

  /// Lists every photo under the shared node. A plain album share holds its
  /// photos directly; a group share points at a container of albums (SPEC
  /// §13.5.1), so the walk descends into every nested FOLDER/ALBUM node.
  /// [maxContainers] bounds the requests a pathological share can cause, and
  /// photo ids are deduped because a group can hold one file in two albums.
  Future<(String title, List<RemotePhoto>)> list(AmazonShareLink link, {int maxItems = 5000, int maxContainers = 100}) async {
    final share = asObject(await fetcher.getJson(provider, _drive(link, 'shares/${link.shareId}', {'asset': 'ALL'})), provider);
    final info = share.obj('nodeInfo');
    final root = info.str('id');
    final title = info.str('name') ?? share.str('name') ?? 'Amazon Photos';
    if (root == null) throw ProviderException(provider, 'Share has no node');

    final photos = <RemotePhoto>[];
    final seenPhotos = <String>{};
    final seenNodes = <String>{root};
    final pending = [root];
    while (pending.isNotEmpty && photos.length < maxItems && seenNodes.length <= maxContainers) {
      final nodeId = pending.removeLast();
      var offset = 0;
      while (photos.length < maxItems) {
        final (items, total) = await _page(link, nodeId, offset, 200);
        if (items.isEmpty) break;
        for (final n in items) {
          if (_isImage(n)) {
            final p = _photo(link, n);
            if (p != null && seenPhotos.add(p.remoteId)) photos.add(p);
          } else if (_isContainer(n)) {
            final id = n.str('id');
            if (id != null && seenNodes.add(id)) pending.add(id);
          }
        }
        offset += items.length;
        if (total != null && offset >= total) break;
      }
    }
    return (title, photos);
  }

  Future<(List<Map<String, Object?>>, int?)> _page(AmazonShareLink link, String nodeId, int offset, int limit) async {
    final j = asObject(
      await fetcher.getJson(provider, _drive(link, 'nodes/$nodeId/children', {
        'asset': 'ALL',
        'limit': '$limit',
        'offset': '$offset',
        'searchOnFamily': 'false',
        'tempLink': 'false',
      })),
      provider,
    );
    return ([for (final d in j.arr('data')) if (d is Map<String, Object?>) d], j.integer('count'));
  }

  bool _isImage(Map<String, Object?> n) {
    final cp = n.obj('contentProperties');
    final type = cp.str('contentType') ?? '';
    return cp.obj('image').isNotEmpty || type.startsWith('image/');
  }

  RemotePhoto? _photo(AmazonShareLink link, Map<String, Object?> n) {
    final id = n.str('id');
    final owner = n.str('ownerId');
    if (id == null) return null;
    final image = n.obj('contentProperties').obj('image');
    final taken = image.str('dateTimeOriginal') ?? n.obj('contentProperties').str('contentDate') ?? n.str('createdDate');
    return RemotePhoto(
      remoteId: id,
      downloadUrl: Uri.https('thumbnails-photos.amazon.${link.tld}', '/v1/thumbnail/$id', {
        'ownerId': ?owner,
        'viewBox': '2048',
        'shareId': link.shareId,
      }),
      takenMs: taken == null ? null : DateTime.tryParse(taken)?.millisecondsSinceEpoch,
      width: image.integer('width'),
      height: image.integer('height'),
      caption: n.str('description'),
    );
  }

  /// Fallback derivative URL when the thumbnail host refuses (M0 validation).
  Uri contentRedirection(AmazonShareLink link, String nodeId) =>
      _drive(link, 'nodes/$nodeId/contentRedirection', {'querySuffix': '?viewBox=2048'});
}

// ───────────────────────────────── Immich ──────────────────────────────────

/// Immich official REST API (SPEC §13.5.3).
class ImmichClient {
  ImmichClient(this.fetcher, String baseUrl, this.apiKey) : base = Uri.parse(baseUrl.replaceFirst(RegExp(r'/+$'), ''));
  final Fetcher fetcher;
  final Uri base;
  final String apiKey;
  static const provider = 'immich';

  Map<String, String> get _h => {'x-api-key': apiKey};
  Uri _u(String path, [Map<String, String>? q]) => Uri.parse('$base/api$path').replace(queryParameters: q);

  Future<String> version() async {
    final j = asObject(await fetcher.getJson(provider, _u('/server/version'), headers: _h), provider);
    return '${j['major']}.${j['minor']}.${j['patch']}';
  }

  Future<List<(String id, String name, int count)>> albums() async {
    final j = await fetcher.getJson(provider, _u('/albums'), headers: _h);
    return [
      for (final a in asArray(j))
        if (a is Map<String, Object?>) (a.str('id') ?? '', a.str('albumName') ?? 'Album', a.integer('assetCount') ?? 0),
    ];
  }

  /// A random sample (no library enumeration).
  Future<List<RemotePhoto>> random(int size, {List<String>? albumIds, bool? favorites}) async {
    final j = await fetcher.postJson(provider, _u('/search/random'), headers: _h, body: {
      'size': size,
      'type': 'IMAGE',
      'withExif': true,
      'albumIds': ?albumIds,
      'isFavorite': ?favorites,
    });
    return [for (final a in asArray(j)) if (a is Map<String, Object?>) _asset(a)];
  }

  Future<List<RemotePhoto>> album(String albumId) async {
    final j = asObject(await fetcher.getJson(provider, _u('/albums/$albumId'), headers: _h), provider);
    return [for (final a in j.arr('assets')) if (a is Map<String, Object?> && a.str('type') == 'IMAGE') _asset(a)];
  }

  /// "On this day" memories for [day].
  Future<List<RemotePhoto>> memories(LocalDate day) async {
    final j = await fetcher.getJson(provider, _u('/memories', {'for': '${day.iso}T00:00:00.000Z'}), headers: _h);
    return [
      for (final m in asArray(j))
        if (m is Map<String, Object?>)
          for (final a in m.arr('assets'))
            if (a is Map<String, Object?> && a.str('type') == 'IMAGE') _asset(a),
    ];
  }

  RemotePhoto _asset(Map<String, Object?> a) {
    final exif = a.obj('exifInfo');
    final id = a.str('id') ?? '';
    final place = [exif.str('city'), exif.str('state') ?? exif.str('country')].whereType<String>().join(', ');
    return RemotePhoto(
      remoteId: id,
      downloadUrl: _u('/assets/$id/thumbnail', {'size': 'preview'}),
      headers: _h,
      takenMs: DateTime.tryParse(exif.str('dateTimeOriginal') ?? a.str('localDateTime') ?? a.str('fileCreatedAt') ?? '')?.millisecondsSinceEpoch,
      width: exif.integer('exifImageWidth'),
      height: exif.integer('exifImageHeight'),
      caption: exif.str('description'),
      location: place.isEmpty ? null : place,
      favorite: a.boolean('isFavorite') ?? false,
    );
  }
}

// ───────────────────────── Google Photos (Picker API) ──────────────────────

@immutable
class PickerSession {
  const PickerSession({required this.id, required this.pickerUri, required this.itemsSet, this.pollInterval = const Duration(seconds: 5), this.expireMs});
  final String id;
  final Uri pickerUri;
  final bool itemsSet;
  final Duration pollInterval;
  final int? expireMs;
}

/// Google Photos Picker (SPEC §13.5.2): the family picks on a phone; the Hub
/// downloads the picked items within an hour (base URLs expire).
class GooglePhotosPicker {
  GooglePhotosPicker(this.fetcher, this.token);
  final Fetcher fetcher;
  final Future<String> Function() token;
  static const provider = 'google-photos';
  static final _base = Uri.parse('https://photospicker.googleapis.com/v1');

  Future<Map<String, String>> _h() async => {'Authorization': 'Bearer ${await token()}'};

  PickerSession _session(Map<String, Object?> j) {
    final poll = j.obj('pollingConfig').str('pollInterval') ?? '5s';
    return PickerSession(
      id: j.str('id') ?? '',
      pickerUri: Uri.parse(j.str('pickerUri') ?? 'https://photos.google.com'),
      itemsSet: j.boolean('mediaItemsSet') ?? false,
      pollInterval: Duration(milliseconds: ((double.tryParse(poll.replaceAll('s', '')) ?? 5) * 1000).round()),
      expireMs: DateTime.tryParse(j.str('expireTime') ?? '')?.millisecondsSinceEpoch,
    );
  }

  Future<PickerSession> createSession() async =>
      _session(asObject(await fetcher.postJson(provider, Uri.parse('$_base/sessions'), headers: await _h(), body: const <String, Object?>{}), provider));

  Future<PickerSession> getSession(String id) async =>
      _session(asObject(await fetcher.getJson(provider, Uri.parse('$_base/sessions/$id'), headers: await _h()), provider));

  Future<List<RemotePhoto>> listItems(String sessionId) async {
    final out = <RemotePhoto>[];
    String? page;
    final headers = await _h();
    do {
      final j = asObject(
        await fetcher.getJson(provider, Uri.parse('$_base/mediaItems').replace(queryParameters: {'sessionId': sessionId, 'pageSize': '100', 'pageToken': ?page}), headers: headers),
        provider,
      );
      for (final m in j.arr('mediaItems')) {
        if (m is! Map<String, Object?> || m.str('type') == 'VIDEO') continue;
        final file = m.obj('mediaFile');
        final meta = file.obj('mediaFileMetadata');
        final baseUrl = file.str('baseUrl');
        if (baseUrl == null) continue;
        out.add(RemotePhoto(
          remoteId: m.str('id') ?? baseUrl,
          downloadUrl: Uri.parse('$baseUrl=w2048-h2048'),
          headers: headers,
          takenMs: DateTime.tryParse(m.str('createTime') ?? '')?.millisecondsSinceEpoch,
          width: meta.integer('width'),
          height: meta.integer('height'),
        ));
      }
      page = j.str('nextPageToken');
    } while (page != null);
    return out;
  }

  Future<void> deleteSession(String id) async {
    await fetcher.send(provider, 'DELETE', Uri.parse('$_base/sessions/$id'), headers: await _h(), retry: false);
  }
}
