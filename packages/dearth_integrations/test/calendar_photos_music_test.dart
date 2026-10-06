import 'package:dearth_core/dearth_core.dart';
import 'package:dearth_integrations/dearth_integrations.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'helpers.dart';

const _ics = '''
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Test//EN
BEGIN:VEVENT
UID:swim-1@school.test
DTSTAMP:20260901T120000Z
DTSTART;TZID=America/Denver:20261006T170000
DTEND;TZID=America/Denver:20261006T180000
RRULE:FREQ=WEEKLY;BYDAY=TU;COUNT=6
EXDATE;TZID=America/Denver:20261013T170000
SUMMARY:Swim lesson\\, level 2
LOCATION:Rec Center\\; Pool B
DESCRIPTION:Bring goggles.\\nAnd a towel.
BEGIN:VALARM
TRIGGER:-PT30M
ACTION:DISPLAY
DESCRIPTION:Reminder
END:VALARM
END:VEVENT
BEGIN:VEVENT
UID:swim-1@school.test
RECURRENCE-ID;TZID=America/Denver:20261020T170000
DTSTART;TZID=America/Denver:20261020T180000
DTEND;TZID=America/Denver:20261020T190000
SUMMARY:Swim lesson (moved)
END:VEVENT
BEGIN:VEVENT
UID:no-school@district.test
DTSTART;VALUE=DATE:20261009
DTEND;VALUE=DATE:20261010
SUMMARY:No school – teacher work day
END:VEVENT
BEGIN:VEVENT
UID:long-title@district.test
DTSTART:20261015T150000Z
DURATION:PT1H30M
SUMMARY:Parent-teacher conferences for the whole elementary school and the pre
 school wing
STATUS:CANCELLED
END:VEVENT
END:VCALENDAR
''';

void main() {
  group('ICS (FR-CAL-01)', () {
    final drafts = parseIcs(_ics, defaultTz: 'America/Denver');
    final denver = HouseholdTime.named('America/Denver');

    test('parses timed recurring masters with TZID, EXDATE and escapes; skips alarms', () {
      final swim = drafts.firstWhere((d) => d.remoteId == 'swim-1@school.test');
      expect(swim.title, 'Swim lesson, level 2');
      expect(swim.location, 'Rec Center; Pool B');
      expect(swim.notes, 'Bring goggles.\nAnd a towel.');
      expect(swim.rrule, 'FREQ=WEEKLY;BYDAY=TU;COUNT=6');
      expect(denver.minuteOfDay(swim.startMs), 17 * 60);
      expect(swim.endMs - swim.startMs, 3600000);
      expect(swim.exdates.single, denver.msAt(const LocalDate(2026, 10, 13), 17));
      expect(swim.tz, 'America/Denver');
    });

    test('RECURRENCE-ID overrides map to the master', () {
      final moved = drafts.firstWhere((d) => d.remoteId.startsWith('swim-1@school.test#'));
      expect(moved.recurringRemoteId, 'swim-1@school.test');
      expect(moved.originalStartMs, denver.msAt(const LocalDate(2026, 10, 20), 17));
      final fields = moved.toFields('src1');
      expect(fields['recurring_parent_id'], EventDraft.localId('src1', 'swim-1@school.test'));
    });

    test('all-day DATE values, folded lines, DURATION and cancellations', () {
      final day = drafts.firstWhere((d) => d.remoteId == 'no-school@district.test');
      expect(day.allDay, isTrue);
      expect(day.startDate, '2026-10-09');
      expect(day.endDate, '2026-10-10');
      final conf = drafts.firstWhere((d) => d.remoteId == 'long-title@district.test');
      expect(conf.title, endsWith('preschool wing'));
      expect(conf.endMs - conf.startMs, 90 * 60000);
      expect(conf.isCancelled, isTrue);
    });

    test('expanding imported events honors EXDATE and the moved instance', () {
      Event row(EventDraft d) {
        final f = d.toFields('src1');
        return Event(
          id: EventDraft.localId('src1', d.remoteId),
          syncClock: '{}', syncHlc: '', syncSeq: 0, deleted: false, //
          sourceId: 'src1', title: d.title, startMs: d.startMs, endMs: d.endMs, allDay: d.allDay,
          startDate: d.startDate, endDate: d.endDate, tz: d.tz, rrule: d.rrule,
          exdates: encodeJson(d.exdates), recurringParentId: f['recurring_parent_id'] as String?,
          originalStartMs: d.originalStartMs, countdown: false, reminders: '[]', profileIds: '[]', status: d.status,
        );
      }

      final occ = RecurrenceExpander(denver).expand(
        drafts.map(row),
        fromMs: denver.msAt(const LocalDate(2026, 10, 1), 0),
        toMs: denver.msAt(const LocalDate(2026, 11, 30), 0),
      );
      final swims = occ.where((o) => o.event.title.startsWith('Swim')).map((o) => '${denver.dateOfMs(o.startMs).day}@${denver.minuteOfDay(o.startMs) ~/ 60}').toList();
      expect(swims, ['6@17', '20@18', '27@17', '3@17', '10@17']);
    });
  });

  group('Google Calendar', () {
    test('maps timed, all-day, recurring and exception events', () {
      final timed = eventFromGoogle({
        'id': 'abc',
        'etag': '"3"',
        'status': 'confirmed',
        'summary': 'Dentist',
        'start': {'dateTime': '2026-10-06T15:30:00-06:00', 'timeZone': 'America/Denver'},
        'end': {'dateTime': '2026-10-06T16:30:00-06:00', 'timeZone': 'America/Denver'},
        'updated': '2026-10-01T10:00:00.000Z',
      }, defaultTz: 'UTC');
      expect(timed.startMs, DateTime.parse('2026-10-06T21:30:00Z').millisecondsSinceEpoch);
      expect(timed.etag, '"3"');
      expect(timed.tz, 'America/Denver');

      final allDay = eventFromGoogle({
        'id': 'b',
        'summary': 'Trip',
        'start': {'date': '2026-10-10'},
        'end': {'date': '2026-10-13'},
      }, defaultTz: 'America/Denver');
      expect(allDay.allDay, isTrue);
      expect(allDay.endDate, '2026-10-13');

      final master = eventFromGoogle({
        'id': 'm',
        'summary': 'Soccer',
        'start': {'dateTime': '2026-10-03T09:00:00-06:00', 'timeZone': 'America/Denver'},
        'end': {'dateTime': '2026-10-03T10:00:00-06:00', 'timeZone': 'America/Denver'},
        'recurrence': ['RRULE:FREQ=WEEKLY;BYDAY=SA', 'EXDATE;TZID=America/Denver:20261010T090000'],
      }, defaultTz: 'UTC');
      expect(master.rrule, 'FREQ=WEEKLY;BYDAY=SA');
      expect(master.exdates.single, DateTime.parse('2026-10-10T15:00:00Z').millisecondsSinceEpoch);

      final cancelled = eventFromGoogle({
        'id': 'm_20261017T150000Z',
        'status': 'cancelled',
        'recurringEventId': 'm',
        'originalStartTime': {'dateTime': '2026-10-17T09:00:00-06:00'},
      }, defaultTz: 'UTC');
      expect(cancelled.isCancelled, isTrue);
      expect(cancelled.recurringRemoteId, 'm');
    });

    test('incremental sync pages, 410 → SyncTokenExpired, 412 → EtagConflict', () async {
      final f = fakeFetcher({
        (r) => r.url.path.endsWith('/events') && r.url.queryParameters['syncToken'] == 'stale': (_) => http.Response('gone', 410),
        (r) => r.url.path.endsWith('/events') && r.url.queryParameters['pageToken'] == null && r.method == 'GET': (_) => json({
              'items': [
                {'id': 'e1', 'summary': 'A', 'start': {'date': '2026-10-02'}, 'end': {'date': '2026-10-03'}},
              ],
              'nextPageToken': 'p2',
            }),
        (r) => r.url.queryParameters['pageToken'] == 'p2': (_) => json({'items': <Object>[], 'nextSyncToken': 'sync-1'}),
        (r) => r.method == 'PATCH': (_) => http.Response('precondition', 412),
      });
      final api = GoogleCalendarApi(f, () async => 'tok', defaultTz: 'America/Denver');
      final p1 = await api.listEvents('primary', timeMinMs: 0);
      expect(p1.events.single.remoteId, 'e1');
      expect(p1.nextPageToken, 'p2');
      final p2 = await api.listEvents('primary', pageToken: 'p2');
      expect(p2.nextSyncToken, 'sync-1');
      expect(() => api.listEvents('primary', syncToken: 'stale'), throwsA(isA<SyncTokenExpired>()));
      expect(() => api.patch('primary', 'e1', {'summary': 'B'}, etag: '"1"'), throwsA(isA<EtagConflict>()));
    });

    test('OAuth URL, PKCE and token exchange', () async {
      final f = fakeFetcher({
        path('/token'): (r) {
          expect(r.bodyFields['grant_type'], 'authorization_code');
          expect(r.bodyFields['code_verifier'], 'v' * 64);
          return json({'access_token': 'a', 'refresh_token': 'r', 'expires_in': 3600, 'scope': 's'});
        },
      });
      final oauth = GoogleOAuth(f, clientId: 'cid', clientSecret: 'sec');
      final url = oauth.authorizationUrl(redirectUri: 'https://hub.test/cb', state: 'st', scopes: GoogleOAuth.calendarScopes, codeChallenge: pkceChallenge('v' * 64));
      expect(url.queryParameters['access_type'], 'offline');
      expect(url.queryParameters['code_challenge_method'], 'S256');
      final tokens = await oauth.exchangeCode('code', redirectUri: 'https://hub.test/cb', codeVerifier: 'v' * 64);
      expect(tokens.refreshToken, 'r');
      expect(OAuthTokens.fromJson(tokens.toJson()).accessToken, 'a');
      // RFC 7636 appendix B vector.
      expect(pkceChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'), 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
    });

    test('outbound body round-trips through the importer', () {
      final ev = Event(
        id: 'x', syncClock: '{}', syncHlc: '', syncSeq: 0, deleted: false, sourceId: 'g', title: 'Park', //
        startMs: DateTime.utc(2026, 10, 3, 16).millisecondsSinceEpoch, endMs: DateTime.utc(2026, 10, 3, 17).millisecondsSinceEpoch,
        allDay: false, exdates: '[]', countdown: false, reminders: '[]', profileIds: '[]', status: 'confirmed', rrule: 'FREQ=WEEKLY',
      );
      final body = googleBodyFromEvent(ev, householdTz: 'America/Denver');
      expect((body['start']! as Map)['timeZone'], 'America/Denver');
      expect((body['recurrence']! as List).first, 'RRULE:FREQ=WEEKLY');
      final back = eventFromGoogle({'id': 'x', ...body}, defaultTz: 'UTC');
      expect(back.startMs, ev.startMs);
    });
  });

  group('photos', () {
    test('Amazon share links parse across marketplaces', () {
      expect(AmazonShareLink.parse('https://www.amazon.com/photos/share/AbCdEfGhIjKlMnOp1234')!.shareId, 'AbCdEfGhIjKlMnOp1234');
      expect(AmazonShareLink.parse('https://www.amazon.co.uk/photos/share/AbCdEfGhIjKlMnOp1234')!.tld, 'co.uk');
      expect(AmazonShareLink.parse('https://amazon.com/clouddrive/share/AbCdEfGhIjKlMnOp1234'), isNotNull);
      expect(AmazonShareLink.parse('https://evil.test/photos/share/AbCdEfGhIjKlMnOp1234'), isNull);
      // The links the Photos app makes today: a group share token, dot and all.
      final shared = AmazonShareLink.parse('https://www.amazon.com/photos/shared/GrOuPiD1234567890ab.SeCrEtToKeN987')!;
      expect((shared.isGroup, shared.shareId, shared.groupId), (true, 'GrOuPiD1234567890ab.SeCrEtToKeN987', 'GrOuPiD1234567890ab'));
      expect(AmazonShareLink.parse('https://www.amazon.com/photos/groups/share/GrOuPiD1234567890ab.SeCrEtToKeN987')!.isGroup, isTrue);
      expect(AmazonShareLink.parse('https://www.amazon.com/photos/share/AbCdEfGhIjKlMnOp1234')!.isGroup, isFalse);
      // Collaborative albums need a signed-in viewer.
      expect(AmazonShareLink.parse('https://www.amazon.com/photos/shared/album/AbCdEfGhIjKlMnOp1234'), isNull);
      expect(AmazonShareLink.parse('https://www.amazon.com/photos/share/AbCd.EfGhIjKlMnOp1234'), isNull, reason: 'share ids have no dot');
    });

    test('one album pasted twice, however the link was copied, is one source', () {
      String? amazon(String url) => photoSourceKey('amazon', {'shareUrl': url});
      const link = 'https://www.amazon.com/photos/shared/GrOuPiD1234567890ab.SeCrEtToKeN987';
      expect(amazon('$link?_encoding=UTF8&ref=share'), amazon(link));
      expect(amazon(' $link/ '), amazon(link));
      expect(amazon('https://amazon.com/photos/groups/share/GrOuPiD1234567890ab.SeCrEtToKeN987'), amazon(link));
      expect(amazon('https://www.amazon.com/photos/share/AbCdEfGhIjKlMnOp1234'), isNot(amazon(link)));
      expect(amazon('https://www.amazon.co.uk/photos/share/AbCdEfGhIjKlMnOp1234'), isNot(amazon('https://www.amazon.com/photos/share/AbCdEfGhIjKlMnOp1234')));
      expect(amazon('not a link'), isNull);
      expect(photoSourceKey('folder', {'path': '/photos/family/'}), photoSourceKey('folder', {'path': '/photos/family'}));
      expect(photoSourceKey('immich', {'url': 'http://nas:2283/', 'albumIds': ['b', 'a']}), photoSourceKey('immich', {'url': 'http://NAS:2283', 'albumIds': ['a', 'b']}));
      expect(photoSourceKey('google', const {}), isNull, reason: 'every Google pick is its own');
    });

    test('Amazon shared album listing descends into the album node and pages', () async {
      final f = fakeFetcher({
        pathEnds('/shares/AbCdEfGhIjKlMnOp1234'): (_) => json({'nodeInfo': {'id': 'root', 'name': 'Dearth Frame'}}),
        (r) => r.url.path.endsWith('/nodes/root/children'): (_) => json({'count': 1, 'data': [
              {'id': 'album1', 'kind': 'FOLDER'},
            ]}),
        (r) => r.url.path.endsWith('/nodes/album1/children') && r.url.queryParameters['limit'] == '1': (_) => json({'data': [
              {'id': 'p1', 'kind': 'FILE', 'contentProperties': {'contentType': 'image/jpeg', 'image': {'width': 4032, 'height': 3024}}},
            ]}),
        (r) => r.url.path.endsWith('/nodes/album1/children') && r.url.queryParameters['offset'] == '0': (_) => json({'count': 2, 'data': [
              {'id': 'p1', 'ownerId': 'O1', 'kind': 'FILE', 'contentProperties': {'contentType': 'image/jpeg', 'image': {'width': 4032, 'height': 3024, 'dateTimeOriginal': '2024-07-04T12:00:00.000Z'}}},
              {'id': 'v1', 'kind': 'FILE', 'contentProperties': {'contentType': 'video/mp4'}},
            ]}),
        (r) => r.url.path.endsWith('/nodes/album1/children') && r.url.queryParameters['offset'] == '2': (_) => json({'count': 2, 'data': <Object>[]}),
      });
      final link = AmazonShareLink.parse('https://www.amazon.com/photos/share/AbCdEfGhIjKlMnOp1234')!;
      final (title, photos) = await AmazonSharedAlbum(f).list(link);
      expect(title, 'Dearth Frame');
      expect(photos.single.remoteId, 'p1');
      expect(photos.single.downloadUrl.host, 'thumbnails-photos.amazon.com');
      expect(photos.single.downloadUrl.queryParameters['ownerId'], 'O1');
      expect(photos.single.takenMs, DateTime.utc(2024, 7, 4, 12).millisecondsSinceEpoch);
    });

    test('Amazon share walks every nested album and dedupes shared photos', () async {
      Map<String, Object?> photo(String id) => {'id': id, 'kind': 'FILE', 'contentProperties': {'contentType': 'image/jpeg', 'image': <String, Object?>{}}};
      final f = fakeFetcher({
        pathEnds('/shares/GrOuPsHaRe12345'): (_) => json({'nodeInfo': {'id': 'group', 'name': 'Family'}}),
        pathEnds('/nodes/group/children'): (_) => json({'count': 3, 'data': [
              {'id': 'a1', 'kind': 'ALBUM'},
              {'id': 'a2', 'kind': 'ALBUM'},
              photo('loose'),
            ]}),
        pathEnds('/nodes/a1/children'): (_) => json({'count': 2, 'data': [photo('p1'), photo('both')]}),
        pathEnds('/nodes/a2/children'): (_) => json({'count': 2, 'data': [photo('both'), {'id': 'sub', 'kind': 'FOLDER'}]}),
        pathEnds('/nodes/sub/children'): (_) => json({'count': 1, 'data': [photo('p2')]}),
      });
      final link = AmazonShareLink.parse('https://www.amazon.com/photos/share/GrOuPsHaRe12345')!;
      final (title, photos) = await AmazonSharedAlbum(f).list(link);
      expect(title, 'Family');
      expect(photos.map((p) => p.remoteId), unorderedEquals(['loose', 'p1', 'both', 'p2']));
    });

    test('Amazon group share link (…/photos/shared/{token}): named by the groups service, photos from the group search', () async {
      final log = <http.Request>[];
      final f = fakeFetcher({
        path('/cdrs/drive/v2/photosGroups/shares/GrOuPiD1234567890ab.SeCrEtToKeN987'): (_) => http.Response(fixture('amazon_group_share.json'), 200),
        path('/drive/v1/search/groups/GrOuPiD1234567890ab'): (r) {
          expect(r.url.queryParameters, containsPair('groupShareToken', 'GrOuPiD1234567890ab.SeCrEtToKeN987'));
          expect(r.url.queryParameters, containsPair('searchContext', 'groups'));
          expect(r.url.queryParameters, containsPair('resourceVersion', 'V2'), reason: 'V1 nodes have no ownerId');
          return http.Response(fixture('amazon_group_search.json'), 200);
        },
      }, log: log);
      final link = AmazonShareLink.parse('https://www.amazon.com/photos/shared/GrOuPiD1234567890ab.SeCrEtToKeN987')!;
      final (title, photos) = await AmazonSharedAlbum(f).list(link);
      expect(title, 'October 6, 2026');
      // The album node in the group is skipped; its photo is listed itself.
      final p = photos.single;
      expect(p.remoteId, 'PhOtOnOdE0001');
      expect((p.width, p.height), (4032, 3024));
      expect(p.takenMs, DateTime.utc(2026, 10, 5, 19, 40, 13).millisecondsSinceEpoch);
      // A HEIC original comes back from the thumbnail service as a JPEG.
      expect(p.downloadUrl.host, 'thumbnails-photos.amazon.com');
      expect(p.downloadUrl.queryParameters, {'ownerId': 'A1OWNEREXAMPLE', 'viewBox': '2048', 'groupShareToken': 'GrOuPiD1234567890ab.SeCrEtToKeN987'});
      expect(log.where((r) => r.url.path.contains('/nodes/')), isEmpty, reason: 'group links never use the share endpoints');
    });

    test('Immich random sample with exif', () async {
      final f = fakeFetcher({
        path('/api/search/random'): (r) {
          expect(r.headers['x-api-key'], 'key');
          return json([
            {'id': 'a1', 'type': 'IMAGE', 'isFavorite': true, 'exifInfo': {'exifImageWidth': 4000, 'exifImageHeight': 3000, 'city': 'Lake Dillon', 'state': 'Colorado', 'dateTimeOriginal': '2024-07-04T12:00:00.000Z'}},
          ]);
        },
      });
      final photos = await ImmichClient(f, 'https://immich.test/', 'key').random(10);
      expect(photos.single.location, 'Lake Dillon, Colorado');
      expect(photos.single.downloadUrl.toString(), 'https://immich.test/api/assets/a1/thumbnail?size=preview');
      expect(photos.single.favorite, isTrue);
    });
  });

  group('music', () {
    test('YouTube ids from every URL shape', () {
      for (final u in [
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=5',
        'https://youtu.be/dQw4w9WgXcQ',
        'https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=x',
        'https://www.youtube.com/shorts/dQw4w9WgXcQ',
        'https://www.youtube.com/embed/dQw4w9WgXcQ',
        'dQw4w9WgXcQ',
      ]) {
        expect(parseYouTubeId(u), 'dQw4w9WgXcQ', reason: u);
      }
      expect(parseYouTubeId('https://vimeo.com/123'), isNull);
    });

    test('Spotify URIs from share links', () {
      expect(parseSpotifyUri('https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC?si=x'), 'spotify:track:4uLU6hMCjMI75M1A2tKUQC');
      expect(parseSpotifyUri('https://open.spotify.com/intl-de/playlist/37i9dQZF1DX0XUsuxWHRQd'), 'spotify:playlist:37i9dQZF1DX0XUsuxWHRQd');
      expect(parseSpotifyUri('spotify:album:1DFixLWuPkv3KT3TnV35m3'), 'spotify:album:1DFixLWuPkv3KT3TnV35m3');
      expect(parseSpotifyUri('https://example.com/track/x'), isNull);
    });

    test('Spotify play uses context_uri for playlists and uris for tracks', () async {
      final bodies = <String>[];
      final f = fakeFetcher({
        path('/v1/me/player/play'): (r) {
          bodies.add(r.body);
          return http.Response('', 204);
        },
      });
      final api = SpotifyApi(f, () async => 'tok');
      await api.play('spotify:playlist:abc', deviceId: 'echo');
      await api.play('spotify:track:def');
      expect(bodies[0], contains('context_uri'));
      expect(bodies[1], contains('"uris"'));
    });

    test('YouTube oEmbed resolves titles; embed-blocked videos error', () async {
      final f = fakeFetcher({
        (r) => r.url.path == '/oembed' && r.url.queryParameters['url']!.contains('dQw4w9WgXcQ'): (_) => json({'title': 'Baby Shark', 'author_name': 'Pinkfong'}),
        (r) => r.url.path == '/oembed': (_) => http.Response('Unauthorized', 401),
      });
      final info = await YouTubeOEmbed(f).resolve('dQw4w9WgXcQ');
      expect(info.title, 'Baby Shark');
      expect(info.artUrl, contains('dQw4w9WgXcQ'));
      expect(() => YouTubeOEmbed(f).resolve('AAAAAAAAAAA'), throwsA(isA<ProviderException>()));
    });
  });
}
