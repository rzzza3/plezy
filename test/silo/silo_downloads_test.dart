import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/connection/connection.dart';
import 'package:plezy/exceptions/media_server_exceptions.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/playback_report_metadata.dart';
import 'package:plezy/services/download_manager_service.dart';
import 'package:plezy/services/silo_client.dart';
import 'package:plezy/silo/silo_downloads.dart';
import 'package:plezy/silo/silo_http.dart';
import 'package:plezy/utils/active_client_scope.dart';

import 'fake_silo.dart';

final _connection = SiloConnection(
  origin: 'https://silo.ruleone.xyz',
  serverId: 'server-1',
  serverName: 'Silo',
  username: 'alice',
  createdAt: DateTime.fromMillisecondsSinceEpoch(1_000_000),
);

Map<String, Object?> _row({
  String id = 'dl-1',
  String contentId = 'movie-tmdb-1',
  String? episodeId,
  Object fileId = '41',
  String status = 'ready',
  String quality = 'original',
  int revision = 3,
  String? device,
  int bytesSent = 0,
}) => {
  'id': id,
  'content_id': contentId,
  'episode_id': ?episodeId,
  'device_id': device ?? siloTestDevice.id,
  'media_file_id': fileId,
  'file_size': 10,
  'bytes_sent': bytesSent,
  'kind': 'queued',
  'status': status,
  'quality': quality,
  'effective_quality': quality,
  'delivery_format': 'original',
  'target_bitrate_kbps': 0,
  'revision': revision,
  'created_at': '2026-10-20T10:00:00Z',
};

Map<String, Object?> _page(List<Map<String, Object?>> items, {String? next}) => {
  'items': items,
  'page': {'has_more': next != null, 'next_cursor': ?next},
};

Map<String, Object?> _receipt(Map<String, Object?> row) => {
  'items': [row],
  'skipped': <Object>[],
  'page': {'has_more': false},
};

Map<String, Object?> _capability({bool allowed = true, String state = 'available', String? revision = 'cap-1'}) => {
  'revision': ?revision,
  'state': state,
  'enabled': true,
  'download_allowed': allowed,
  'quality_presets': ['original'],
};

Map<String, Object?> _watch(String contentId) => {
  'content_id': contentId,
  'versions': [
    {'file_id': '41', 'resolution': '1080p', 'duration_seconds': 6780.5, 'container': 'mkv'},
  ],
};

Map<String, Object?> _manifest() => {
  'delivery_format': 'original',
  'selected_audio_track_index': 0,
  'audio_tracks': [
    {'index': 0, 'codec': 'eac3', 'language': 'eng'},
  ],
  'subtitles': [
    {'language': 'eng', 'title': 'English', 'format': 'subrip', 'fetch_url': '/api/v2/downloads/dl-1/subtitles/0'},
    {
      'language': 'fra',
      'format': 'hdmv_pgs_subtitle',
      'forced': true,
      'fetch_url': '/api/v2/downloads/dl-1/subtitles/1',
    },
    {'language': 'deu', 'format': 'mov_text', 'fetch_url': '/api/v2/downloads/dl-1/subtitles/2'},
    {'language': 'spa', 'format': 'srt', 'fetch_url': 'https://elsewhere.example/api/v2/downloads/dl-1/subtitles/3'},
    {'language': 'ita', 'format': 'vtt', 'fetch_url': '/api/v2/stream/s-1/subtitles/4.vtt'},
  ],
};

const _bytes = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

Future<SiloHttp> _http(FakeSilo fake, {String profile = 'p-1'}) async {
  final (session, _) = await signedInSession();
  await session.selectProfile(profile, null);
  return siloHttpFor(fake, session);
}

Map<String, Object?> _body(RecordedRequest request) => jsonDecode(request.body) as Map<String, Object?>;

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('silo_downloads_test_'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('capability gate (DownloadRegistryV2Api.kt:91-95, DownloadModels.kt:227)', () {
    test('usable only when enabled, allowed and available (DownloadModels.kt:227)', () {
      expect(SiloDownloadCapability.fromJson(_capability()).isUsable, isTrue);
      expect(SiloDownloadCapability.fromJson(_capability(allowed: false)).isUsable, isFalse);
      expect(SiloDownloadCapability.fromJson(_capability(state: 'maintenance')).isUsable, isFalse);
    });

    test('a capability without revision or state is invalid (DownloadRegistryV2Api.kt:94)', () async {
      final fake = FakeSilo((_) => jsonResponse(_capability(revision: null), 200));
      final downloads = SiloDownloads(await _http(fake), profileId: 'p-1');

      await expectLater(
        downloads.capability(),
        throwsA(isA<SiloDownloadException>().having((e) => e.code, 'code', 'invalid_download_registry')),
      );
      expect(fake.requests.single.url.path, '/api/v2/capabilities/downloads');
    });

    test('resolveDownload stops at a refused capability and never creates (DownloadsApi.kt:53-61)', () async {
      final fake = FakeSilo((_) => jsonResponse(_capability(allowed: false), 200));
      final client = SiloClient(connection: _connection, profileId: 'p-1', http: await _http(fake));
      final item = MediaItem.silo(id: 'movie-tmdb-1', kind: MediaKind.movie, serverId: 'server-1');

      await expectLater(
        client.resolveDownload(item),
        throwsA(isA<MediaServerHttpException>().having((e) => e.statusCode, 'statusCode', 403)),
      );
      expect(fake.requests.map((r) => r.url.path), ['/api/v2/capabilities/downloads']);
    });
  });

  group('registry list (DownloadRegistryV2Api.kt:61-90)', () {
    test('follows cursors 100 at a time until has_more is false (DownloadRegistryV2Api.kt:66-84)', () async {
      final fake = FakeSilo((request) {
        final cursor = request.url.queryParameters['cursor'];
        return cursor == null
            ? jsonResponse(_page([_row()], next: 'c-2'), 200)
            : jsonResponse(_page([_row(id: 'dl-2', fileId: '42')]), 200);
      });
      final rows = await SiloDownloads(await _http(fake), profileId: 'p-1').list();

      expect(rows.map((r) => r.id), ['dl-1', 'dl-2']);
      expect(fake.requests.map((r) => r.url.queryParameters), [
        {'limit': '100'},
        {'limit': '100', 'cursor': 'c-2'},
      ]);
    });

    test('a row owned by another installation voids the whole list (DownloadRegistryV2Api.kt:32-37,74)', () async {
      final fake = FakeSilo((_) => jsonResponse(_page([_row(device: 'other-device')]), 200));

      await expectLater(
        SiloDownloads(await _http(fake), profileId: 'p-1').list(),
        throwsA(isA<SiloDownloadException>().having((e) => e.code, 'code', 'invalid_download_registry')),
      );
    });

    test('media_file_id is read from a string or a number (DownloadRegistryV2Api.kt:20)', () {
      expect(SiloDownloadRecord.fromJson(_row(fileId: 41), expectedDevice: siloTestDevice.id).mediaFileId, 41);
      expect(SiloDownloadRecord.fromJson(_row(fileId: '41'), expectedDevice: siloTestDevice.id).mediaFileId, 41);
      expect(
        () => SiloDownloadRecord.fromJson(_row(fileId: '0'), expectedDevice: siloTestDevice.id),
        throwsFormatException,
      );
    });
  });

  group('create once (DownloadCreationV2Api.kt:181-223)', () {
    test(
      'a usable entry for the same file and quality is reused with no POST (DownloadCreationV2Api.kt:198-208)',
      () async {
        final fake = FakeSilo((_) => jsonResponse(_page([_row(status: 'downloading', bytesSent: 4)]), 200));
        final row = await SiloDownloads(
          await _http(fake),
          profileId: 'p-1',
        ).create(const SiloDownloadRequest(contentId: 'movie-tmdb-1', fileId: 41));

        expect(row.id, 'dl-1');
        expect(fake.requests.map((r) => r.method), ['GET']);
      },
    );

    test(
      'a new file is posted once with a string file id and a zero guard (DownloadCreationV2Api.kt:157-176,210)',
      () async {
        final fake = FakeSilo((request) {
          if (request.method == 'GET') return jsonResponse(_page([]), 200);
          return jsonResponse(_receipt(_row()), 202);
        });
        final row = await SiloDownloads(
          await _http(fake),
          profileId: 'p-1',
        ).create(const SiloDownloadRequest(contentId: 'movie-tmdb-1', fileId: 41));

        final post = fake.requests.singleWhere((r) => r.method == 'POST');
        expect(row.revision, 3);
        expect(post.url.path, '/api/v2/downloads');
        expect(post.url.queryParameters, {'limit': '100'});
        expect(_body(post), {
          'content_id': 'movie-tmdb-1',
          'media_file_id': '41',
          'quality': 'original',
          'expected_revision': 0,
        });
        expect(post.header('x-silo-device-id'), siloTestDevice.id, reason: 'DownloadCreationV2Api.kt:170-173');
        expect(post.header('x-profile-id'), 'p-1');
      },
    );

    test('a failed entry is replaced under its revision guard (DownloadCreationV2Api.kt:205-211)', () async {
      final fake = FakeSilo((request) {
        if (request.method == 'GET') return jsonResponse(_page([_row(status: 'failed', revision: 5)]), 200);
        return jsonResponse(_receipt(_row(revision: 6)), 202);
      });
      await SiloDownloads(
        await _http(fake),
        profileId: 'p-1',
      ).create(const SiloDownloadRequest(contentId: 'movie-tmdb-1', fileId: 41));

      final body = _body(fake.requests.singleWhere((r) => r.method == 'POST'));
      expect(body['expected_revision'], 5);
      expect(body['expected_download_id'], 'dl-1');
    });

    test('the POST is never replayed, not even after a 401 (DownloadCreationV2Api.kt:169)', () async {
      final fake = FakeSilo((request) {
        if (request.url.path == '/api/v2/auth/refresh') return tokenPair('access-B', 'refresh-B');
        if (request.method == 'GET') return jsonResponse(_page([]), 200);
        return jsonResponse({}, 401);
      });

      await expectLater(
        SiloDownloads(
          await _http(fake),
          profileId: 'p-1',
        ).create(const SiloDownloadRequest(contentId: 'movie-tmdb-1', fileId: 41)),
        throwsA(isA<SiloDownloadException>().having((e) => e.status, 'status', 401)),
      );
      expect(fake.requests.where((r) => r.method == 'POST'), hasLength(1));
      expect(fake.to('/api/v2/auth/refresh'), isEmpty);
    });

    test('a receipt for another file is refused (DownloadCreationV2Api.kt:215-217)', () async {
      final fake = FakeSilo((request) {
        if (request.method == 'GET') return jsonResponse(_page([]), 200);
        return jsonResponse(_receipt(_row(fileId: '99')), 202);
      });

      await expectLater(
        SiloDownloads(
          await _http(fake),
          profileId: 'p-1',
        ).create(const SiloDownloadRequest(contentId: 'movie-tmdb-1', fileId: 41)),
        throwsA(isA<SiloDownloadException>().having((e) => e.code, 'code', 'invalid_download_creation')),
      );
    });

    test('an episode is registered under its series with episode_id (DownloadEnqueuer.kt:120-127)', () async {
      final fake = FakeSilo((request) {
        return switch (request.url.path) {
          '/api/v2/capabilities/downloads' => jsonResponse(_capability(), 200),
          '/api/v2/watch/ep-1' => jsonResponse(_watch('ep-1'), 200),
          '/api/v2/downloads' when request.method == 'GET' => jsonResponse(_page([]), 200),
          _ => jsonResponse(_receipt(_row(contentId: 'series-1', episodeId: 'ep-1')), 202),
        };
      });
      final client = SiloClient(connection: _connection, profileId: 'p-1', http: await _http(fake));
      final episode = MediaItem.silo(
        id: 'ep-1',
        kind: MediaKind.episode,
        grandparentId: 'series-1',
        serverId: 'server-1',
      );

      final resolution = await client.resolveDownload(episode);

      final body = _body(fake.requests.singleWhere((r) => r.method == 'POST'));
      expect(body['content_id'], 'series-1');
      expect(body['episode_id'], 'ep-1');
      expect(body['media_file_id'], '41');
      expect(resolution.videoUrl, 'https://silo.ruleone.xyz/api/v2/downloads/dl-1/file');
      expect(resolution.mediaSourceId, '41');
      expect(resolution.externalSubtitlesResolved, isFalse, reason: 'manifest waits for completion');
      expect(fake.requests.where((r) => r.url.path.endsWith('/manifest')), isEmpty);
      expect(client.downloadExtension(resolution.videoUrl!), 'mkv');
    });
  });

  group('file transfer (DownloadWorker.kt:205-341)', () {
    final record = SiloDownloadRecord.fromJson(_row(), expectedDevice: siloTestDevice.id);

    FakeSilo fileServer(http.Response Function(RecordedRequest request) file) => FakeSilo((request) {
      if (request.method == 'PATCH') {
        return jsonResponse({..._row(), 'status': _body(request)['status']}, 200);
      }
      return file(request);
    });

    Future<void> run(FakeSilo fake, File target, {SiloTransferCancel? cancel}) async {
      var tick = DateTime.utc(2026, 10, 20, 12);
      final downloads = SiloDownloads(await _http(fake), profileId: 'p-1');
      await SiloDownloadTransfer(
        downloads,
        now: () => tick = tick.add(const Duration(seconds: 1)),
      ).run(record: record, target: target, cancel: cancel);
    }

    test(
      'a fresh transfer asks for identity bytes with no Range and saves the ETag (DownloadWorker.kt:228-236,274-287)',
      () async {
        final target = File('${dir.path}/movie.mkv');
        final fake = fileServer(
          (_) => http.Response.bytes(_bytes, 200, headers: {'etag': '"v1"', 'content-length': '10'}),
        );

        await run(fake, target);

        final get = fake.to('/api/v2/downloads/dl-1/file').single;
        expect(get.header('accept-encoding'), 'identity');
        expect(get.header('range'), isNull);
        expect(get.header('if-range'), isNull);
        expect(get.header('authorization'), 'Bearer access-A');
        expect(get.header('x-profile-id'), 'p-1');
        expect(target.readAsBytesSync(), _bytes);
        expect(SiloDownloadTransfer.partialFor(target).existsSync(), isFalse);
        expect(SiloDownloadTransfer.resumeStateFor(target).existsSync(), isFalse);
      },
    );

    test('a resume sends Range: bytes=N- and If-Range with the saved validator (DownloadWorker.kt:212-236)', () async {
      final target = File('${dir.path}/movie.mkv');
      SiloDownloadTransfer.partialFor(target).writeAsBytesSync(_bytes.sublist(0, 4));
      await const SiloResumeState(
        downloadId: 'dl-1',
        revision: 3,
        validator: '"v1"',
      ).write(SiloDownloadTransfer.resumeStateFor(target));
      final fake = fileServer(
        (_) => http.Response.bytes(_bytes.sublist(4), 206, headers: {'content-range': 'bytes 4-9/10', 'etag': '"v1"'}),
      );

      await run(fake, target);

      final get = fake.to('/api/v2/downloads/dl-1/file').single;
      expect(get.header('range'), 'bytes=4-', reason: 'DownloadWorker.kt:232');
      expect(get.header('if-range'), '"v1"', reason: 'DownloadWorker.kt:235');
      expect(get.header('accept-encoding'), 'identity');
      expect(target.readAsBytesSync(), _bytes, reason: 'a matching 206 appends (DownloadWorker.kt:256-273)');
    });

    test('a 416 drops the partial and restarts from zero (DownloadWorker.kt:239-245)', () async {
      final target = File('${dir.path}/movie.mkv');
      SiloDownloadTransfer.partialFor(target).writeAsBytesSync([9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9]);
      await const SiloResumeState(
        downloadId: 'dl-1',
        revision: 3,
        validator: '"v1"',
      ).write(SiloDownloadTransfer.resumeStateFor(target));
      final fake = fileServer((request) {
        if (request.header('range') != null) return http.Response('', 416);
        return http.Response.bytes(_bytes, 200, headers: {'etag': '"v2"'});
      });

      await run(fake, target);

      final gets = fake.to('/api/v2/downloads/dl-1/file');
      expect(gets, hasLength(2));
      expect(gets.first.header('range'), 'bytes=12-');
      expect(gets.last.header('range'), isNull, reason: 'the restart is a fresh GET');
      expect(gets.last.header('if-range'), isNull);
      expect(target.readAsBytesSync(), _bytes);
    });

    test('a 200 to a ranged request starts over instead of appending (DownloadWorker.kt:233-234,274-287)', () async {
      final target = File('${dir.path}/movie.mkv');
      SiloDownloadTransfer.partialFor(target).writeAsBytesSync([7, 7, 7]);
      await const SiloResumeState(
        downloadId: 'dl-1',
        revision: 3,
        validator: '"v1"',
      ).write(SiloDownloadTransfer.resumeStateFor(target));
      final fake = fileServer((_) => http.Response.bytes(_bytes, 200, headers: {'etag': '"v2"'}));

      await run(fake, target);

      expect(fake.to('/api/v2/downloads/dl-1/file').single.header('range'), 'bytes=3-');
      expect(target.readAsBytesSync(), _bytes);
    });

    test('no saved validator, or another revision, never resumes (DownloadWorker.kt:212-216)', () async {
      final target = File('${dir.path}/movie.mkv');
      SiloDownloadTransfer.partialFor(target).writeAsBytesSync([7, 7, 7]);
      await const SiloResumeState(
        downloadId: 'dl-1',
        revision: 2,
        validator: '"v1"',
      ).write(SiloDownloadTransfer.resumeStateFor(target));
      final fake = fileServer((_) => http.Response.bytes(_bytes, 200));

      await run(fake, target);

      expect(fake.to('/api/v2/downloads/dl-1/file').single.header('range'), isNull);
      expect(target.readAsBytesSync(), _bytes);
    });

    test('a weak ETag is skipped for Last-Modified (DownloadWorker.kt:857-863)', () {
      expect(
        siloResumeValidator({'etag': 'W/"v1"', 'last-modified': 'Tue, 20 Oct 2026 10:00:00 GMT'}),
        'Tue, 20 Oct 2026 10:00:00 GMT',
      );
      expect(siloResumeValidator({'etag': '"v1"'}), '"v1"');
      expect(siloResumeValidator({'etag': 'W/"v1"'}), isNull);
    });

    test('Content-Range is parsed and checked (DownloadWorker.kt:840-855)', () {
      expect(parseSiloContentRange('bytes 4-9/10'), (start: 4, end: 9, total: 10));
      expect(parseSiloContentRange('bytes 4-9/*'), (start: 4, end: 9, total: null));
      expect(parseSiloContentRange('bytes 9-4/10'), isNull);
      expect(parseSiloContentRange('bytes 4-9/9'), isNull);
    });

    test('a short body keeps its partial and fails retriably (DownloadWorker.kt:333-340)', () async {
      final target = File('${dir.path}/movie.mkv');
      final fake = fileServer(
        (_) => http.Response.bytes(_bytes.sublist(0, 6), 200, headers: {'etag': '"v1"', 'content-length': '10'}),
      );

      await expectLater(
        run(fake, target),
        throwsA(isA<SiloDownloadException>().having((e) => e.retriable, 'retriable', isTrue)),
      );
      expect(SiloDownloadTransfer.partialFor(target).lengthSync(), 6);
      expect((await SiloResumeState.read(SiloDownloadTransfer.resumeStateFor(target)))?.validator, '"v1"');
      expect(target.existsSync(), isFalse);
    });

    test('a 409 means not ready yet and keeps the partial (DownloadWorker.kt:246-253)', () async {
      final target = File('${dir.path}/movie.mkv');
      final fake = fileServer((_) => jsonResponse({}, 409));

      await expectLater(
        run(fake, target),
        throwsA(isA<SiloDownloadException>().having((e) => e.code, 'code', 'download_preparing')),
      );
      expect(fake.requests.where((r) => r.method == 'PATCH'), isEmpty);
    });

    test(
      'reports downloading, then completed later, at the record revision (DownloadWorker.kt:289-290,367-384)',
      () async {
        final target = File('${dir.path}/movie.mkv');
        final fake = fileServer((_) => http.Response.bytes(_bytes, 200, headers: {'etag': '"v1"'}));

        await run(fake, target);

        final patches = fake.requests.where((r) => r.method == 'PATCH').toList();
        expect(patches.map((r) => r.url.path), ['/api/v2/downloads/dl-1', '/api/v2/downloads/dl-1']);
        expect(patches.map((r) => _body(r)['status']), ['downloading', 'completed']);
        expect(patches.map((r) => _body(r)['revision']), [3, 3]);
        final first = DateTime.parse(_body(patches.first)['updated_at']! as String);
        final last = DateTime.parse(_body(patches.last)['updated_at']! as String);
        expect(last.isAfter(first), isTrue, reason: 'the server ignores an event not newer than the one it holds');
      },
    );

    test('a cancel keeps the partial for a resume (DownloadWorker.kt:206-211)', () async {
      final target = File('${dir.path}/movie.mkv');
      final cancel = SiloTransferCancel()..cancel();
      final fake = fileServer((_) => http.Response.bytes(_bytes, 200));

      await expectLater(run(fake, target, cancel: cancel), throwsA(isA<SiloTransferCancelledException>()));
      expect(fake.to('/api/v2/downloads/dl-1/file'), isEmpty);
    });

    test('a profile switch stops the transfer before any byte (DownloadByteRequest.kt:8-12)', () async {
      final target = File('${dir.path}/movie.mkv');
      final fake = fileServer((_) => http.Response.bytes(_bytes, 200));
      final downloads = SiloDownloads(await _http(fake, profile: 'p-2'), profileId: 'p-1');

      await expectLater(
        SiloDownloadTransfer(downloads).run(record: record, target: target),
        throwsA(isA<SiloDownloadException>().having((e) => e.code, 'code', 'identity_changed')),
      );
      expect(fake.requests, isEmpty);
    });
  });

  group('manifest and tracks (OfflineTrackAssetFetcher.kt:64-117,211-244, OfflineTracks.kt:18-42,153-182)', () {
    test('keeps mountable same-download sidecars at their manifest ordinal (OfflineTracks.kt:153-182)', () {
      final manifest = SiloOfflineManifest.tryParse(jsonEncode(_manifest()))!;

      expect(manifest.subtitles.map((s) => (s.ordinal, s.format, s.language)), [(0, 'srt', 'eng'), (1, 'pgs', 'fra')]);
      expect(manifest.subtitles[1].forced, isTrue);
      expect(manifest.selectedAudioTrackIndex, 0);
      expect(manifest.audioTracks, hasLength(1));
      expect(SiloOfflineManifest.tryParse('not json'), isNull);
    });

    test('retries a 503, then reads the manifest (OfflineTrackAssetFetcher.kt:95-117)', () async {
      var calls = 0;
      final fake = FakeSilo((_) => calls++ == 0 ? jsonResponse({}, 503) : jsonResponse(_manifest(), 200));
      final downloads = SiloDownloads(await _http(fake), profileId: 'p-1', manifestRetryDelay: Duration.zero);

      final manifest = await downloads.manifest('dl-1');

      expect(manifest?.subtitles, hasLength(2));
      expect(fake.requests.map((r) => r.url.path), [
        '/api/v2/downloads/dl-1/manifest',
        '/api/v2/downloads/dl-1/manifest',
      ]);
    });

    test('a 404 is no manifest, asked once (OfflineTrackAssetFetcher.kt:109)', () async {
      final fake = FakeSilo((_) => jsonResponse({}, 404));
      final downloads = SiloDownloads(await _http(fake), profileId: 'p-1', manifestRetryDelay: Duration.zero);

      expect(await downloads.manifest('dl-1'), isNull);
      expect(fake.requests, hasLength(1));
    });

    test('a completed download lists the manifest sidecars as subtitles (OfflineTrackAssetFetcher.kt:72-87)', () async {
      final fake = FakeSilo((request) {
        return switch (request.url.path) {
          '/api/v2/capabilities/downloads' => jsonResponse(_capability(), 200),
          '/api/v2/watch/movie-tmdb-1' => jsonResponse(_watch('movie-tmdb-1'), 200),
          '/api/v2/downloads' => jsonResponse(_page([_row(status: 'completed')]), 200),
          '/api/v2/downloads/dl-1/manifest' => jsonResponse(_manifest(), 200),
          _ => jsonResponse({}, 500),
        };
      });
      final client = SiloClient(connection: _connection, profileId: 'p-1', http: await _http(fake));
      final item = MediaItem.silo(id: 'movie-tmdb-1', kind: MediaKind.movie, serverId: 'server-1');

      final resolution = await client.resolveDownload(item);

      expect(resolution.externalSubtitlesResolved, isTrue);
      expect(resolution.externalSubtitles.map((s) => (s.id, s.codec, s.url)), [
        (0, 'srt', 'https://silo.ruleone.xyz/api/v2/downloads/dl-1/subtitles/0'),
        (1, 'pgs', 'https://silo.ruleone.xyz/api/v2/downloads/dl-1/subtitles/1'),
      ]);
      expect(fake.requests.where((r) => r.method == 'POST'), isEmpty);
    });

    test('a sidecar is fetched with the session and lands whole (OfflineTrackAssetFetcher.kt:211-244)', () async {
      final fake = FakeSilo((_) => http.Response('1\n00:00:01,000 --> 00:00:02,000\nHi\n', 200));
      final client = SiloClient(connection: _connection, profileId: 'p-1', http: await _http(fake));
      final target = File('${dir.path}/0.srt');

      await client.downloadSubtitle('https://silo.ruleone.xyz/api/v2/downloads/dl-1/subtitles/0', target);

      expect(fake.requests.single.header('authorization'), 'Bearer access-A');
      expect(fake.requests.single.header('x-profile-id'), 'p-1');
      expect(target.readAsStringSync(), contains('Hi'));
      expect(File('${target.path}.part').existsSync(), isFalse);
    });

    test('a sidecar on another origin is never fetched (OfflineTracks.kt:170-180)', () async {
      final fake = FakeSilo((_) => http.Response('x', 200));
      final client = SiloClient(connection: _connection, profileId: 'p-1', http: await _http(fake));

      await expectLater(
        client.downloadSubtitle('https://elsewhere.example/api/v2/downloads/dl-1/subtitles/0', File('${dir.path}/x')),
        throwsA(isA<SiloDownloadException>()),
      );
      expect(fake.requests, isEmpty);
    });
  });

  group('status and delete (DownloadRegistryV2Api.kt:96-124)', () {
    test('PATCH sends status, updated_at and revision (DownloadRegistryV2Api.kt:106-115)', () async {
      final fake = FakeSilo((_) => jsonResponse(_row(status: 'downloading'), 200));
      final row = await SiloDownloads(
        await _http(fake),
        profileId: 'p-1',
      ).reportStatus('dl-1', status: 'downloading', updatedAt: DateTime.utc(2026, 10, 20, 12), revision: 3);

      final patch = fake.requests.single;
      expect(patch.method, 'PATCH');
      expect(patch.url.path, '/api/v2/downloads/dl-1');
      expect(_body(patch), {'status': 'downloading', 'updated_at': '2026-10-20T12:00:00.000Z', 'revision': 3});
      expect(row.status, 'downloading');
    });

    test('a moved revision answers 409 (DownloadRegistryV2Api.kt:101-104)', () async {
      final fake = FakeSilo((_) => jsonResponse({}, 409));

      await expectLater(
        SiloDownloads(
          await _http(fake),
          profileId: 'p-1',
        ).reportStatus('dl-1', status: 'completed', updatedAt: DateTime.utc(2026), revision: 3),
        throwsA(isA<SiloDownloadException>().having((e) => e.code, 'code', 'revision_moved')),
      );
    });

    test('only downloading or completed at a positive revision is sent (DownloadRegistryV2Api.kt:108-109)', () async {
      final fake = FakeSilo((_) => jsonResponse(_row(), 200));
      final downloads = SiloDownloads(await _http(fake), profileId: 'p-1');

      await expectLater(
        downloads.reportStatus('dl-1', status: 'failed', updatedAt: DateTime.utc(2026), revision: 3),
        throwsA(isA<SiloDownloadException>()),
      );
      await expectLater(
        downloads.reportStatus('dl-1', status: 'completed', updatedAt: DateTime.utc(2026), revision: 0),
        throwsA(isA<SiloDownloadException>()),
      );
      expect(fake.requests, isEmpty);
    });

    test('DELETE expects 204 and is sent once (DownloadRegistryV2Api.kt:47,55,96-98)', () async {
      final fake = FakeSilo((request) {
        if (request.url.path == '/api/v2/auth/refresh') return tokenPair('access-B', 'refresh-B');
        return jsonResponse({}, 401);
      });

      await expectLater(
        SiloDownloads(await _http(fake), profileId: 'p-1').delete('dl-1'),
        throwsA(isA<SiloDownloadException>()),
      );
      expect(fake.requests.map((r) => '${r.method} ${r.url.path}'), ['DELETE /api/v2/downloads/dl-1']);
    });
  });

  group('offline progress (PlaybackSessionLifecycle.kt:870-908)', () {
    test(
      'a sessionless stop syncs through the personal-data progress path (PlaybackSessionLifecycle.kt:877-886)',
      () async {
        final fake = FakeSilo(
          (_) => jsonResponse({
            'results': [
              {'media_item_id': 'movie-tmdb-1', 'status': 'ok'},
            ],
          }, 200),
        );
        final client = SiloClient(connection: _connection, profileId: 'p-1', http: await _http(fake));

        await client.reportPlaybackStopped(
          itemId: 'movie-tmdb-1',
          position: const Duration(seconds: 754, milliseconds: 500),
          duration: const Duration(seconds: 6780),
          report: PlaybackReportMetadata.offlineReplay(recordedAt: DateTime.utc(2026, 10, 20, 9)),
        );

        final sync = fake.requests.single;
        expect(sync.method, 'POST');
        expect(sync.url.path, '/api/v1/sync/progress');
        expect(_body(sync), {
          'items': [
            {
              'media_item_id': 'movie-tmdb-1',
              'position': 754.5,
              'duration': 6780.0,
              'force_overwrite': true,
              'updated_at': '2026-10-20T09:00:00.000Z',
            },
          ],
        });
        expect(fake.requests.where((r) => r.url.path.startsWith('/api/v2/playback')), isEmpty);
      },
    );

    test('a failed sync throws so the offline queue keeps the position', () async {
      final fake = FakeSilo((_) => jsonResponse({}, 503));
      final client = SiloClient(connection: _connection, profileId: 'p-1', http: await _http(fake));

      await expectLater(
        client.reportPlaybackStopped(itemId: 'movie-tmdb-1', position: const Duration(seconds: 10)),
        throwsA(isA<SiloDownloadException>()),
      );
    });

    test('a rejected item in the results throws too', () async {
      final fake = FakeSilo(
        (_) => jsonResponse({
          'results': [
            {'media_item_id': 'movie-tmdb-1', 'status': 'error', 'error': 'not_found'},
          ],
        }, 200),
      );

      await expectLater(
        siloSyncProgress(await _http(fake), contentId: 'movie-tmdb-1', position: 10, duration: 20),
        throwsA(isA<SiloDownloadException>()),
      );
    });
  });

  group('profile scope', () {
    test('download rows use silo:<server_id>/<profile_id>, invisible to another profile', () {
      final scope = SiloProfileScopeId.tryParse('silo:server-1/p-1')!;

      expect(scope.publicServerId, ServerId('server-1'));
      expect(scope.profileId, 'p-1');
      expect(
        resolveActiveClientScopeId(serverId: ServerId('server-1'), cacheServerId: 'silo:server-1/p-1'),
        'silo:server-1/p-1',
      );
      expect(resolveActiveClientScopeId(serverId: ServerId('server-2'), cacheServerId: 'silo:server-1/p-1'), isNull);
      expect(SiloProfileScopeId.tryParse('silo:server-1'), isNull);
      expect(SiloProfileScopeId.tryParse('silo:server-1/p-1/x'), isNull);
      expect(SiloProfileScopeId.tryParse('server-1/p-1'), isNull);
    });
  });

  group('download manager events', () {
    final task = DownloadTask(url: 'https://silo.ruleone.xyz/api/v2/downloads/dl-1/file', filename: 'movie.mkv');

    test('a vanished entry is not found, a refusal keeps its status', () {
      expect(
        siloTransferFailure(task, const SiloDownloadException('file_failed', status: 404)).status,
        TaskStatus.notFound,
      );
      final refused = siloTransferFailure(task, const SiloDownloadException('file_failed', status: 403));
      expect(refused.exception, isA<TaskHttpException>().having((e) => e.httpResponseCode, 'code', 403));
    });

    test('an interrupted transfer reads as a retriable connection failure with a fixed description', () {
      final interrupted = siloTransferFailure(task, const SocketException('Network is unreachable'));
      expect(interrupted.status, TaskStatus.failed);
      expect(interrupted.exception, isA<TaskConnectionException>());
      expect(interrupted.exception!.description, 'Silo transfer interrupted');
    });
  });
}
