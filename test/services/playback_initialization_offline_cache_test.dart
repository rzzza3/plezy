import 'package:plezy/media/ids.dart';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/database/download_operations.dart';
import 'package:plezy/media/media_backend.dart';

import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/models/download_models.dart';
import 'package:plezy/services/download_storage_service.dart';
import 'package:plezy/services/playback_initialization_service.dart';
import 'package:plezy/services/silo_api_cache.dart';
import 'package:plezy/services/saf_storage_service.dart';
import 'package:plezy/services/settings_service.dart';

import '../test_helpers/io_fakes.dart';
import '../test_helpers/prefs.dart';
import '../test_helpers/media_items.dart';
import '../test_helpers/saf_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late Directory tmpRoot;
  late PathProviderPlatform previousPathProvider;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    DownloadStorageService.resetForTesting();
    // Downloaded rows below store SAF content:// URIs. Playback resolution
    // confirms such a copy is still reachable before preferring it over
    // streaming (issue #2101), so report them as present.
    SafStorageService.setOpsForTesting(FakeSafStorage());
    tmpRoot = await Directory.systemTemp.createTemp('playback_init_test_');
    previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProvider(tmpRoot);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SiloApiCache.initialize(db);
  });

  tearDown(() async {
    await db.close();
    DownloadStorageService.resetForTesting();
    SafStorageService.setOpsForTesting(null);
    SettingsService.resetForTesting();
    PathProviderPlatform.instance = previousPathProvider;
    if (await tmpRoot.exists()) {
      await tmpRoot.delete(recursive: true);
    }
  });

  test('downloaded track resolves to its local file through the offline path', () async {
    // Same globalKey shape queueDownload writes (`serverId:ratingKey`) —
    // the music resolver reaches this via preferOffline=true (original
    // audio preset), so a downloaded track must play from disk.
    await _insertDownloaded(
      db,
      serverId: ServerId('srv-1'),
      ratingKey: 'track-1',
      type: 'track',
      videoFilePath: 'content://offline/track-1',
    );
    final client = _FailingPlaybackClient(serverId: ServerId('srv-1'));

    final result = await PlaybackInitializationService(client: client, database: db).getPlaybackData(
      PlaybackInitializationOptions(
        metadata: testMediaItem(
          id: 'track-1',
          backend: MediaBackend.silo,
          kind: MediaKind.track,
          serverId: ServerId('srv-1'),
        ),
        selectedMediaIndex: 0,
      ),
      preferOffline: true,
    );

    expect(client.playbackInitializationCalls, 0);
    expect(result.isOffline, isTrue);
    expect(result.videoUrl, 'content://offline/track-1');
    expect(result.playMethod, 'DirectPlay');
  });

  test('preferOffline plays the local file without calling the live client', () async {
    await _insertDownloaded(
      db,
      serverId: ServerId('srv-1'),
      ratingKey: 'movie-1',
      videoFilePath: 'content://offline/movie-1',
    );
    final client = _FailingPlaybackClient(serverId: ServerId('srv-1'));

    final result = await PlaybackInitializationService(client: client, database: db).getPlaybackData(
      PlaybackInitializationOptions(
        metadata: testMediaItem(
          id: 'movie-1',
          backend: MediaBackend.silo,
          kind: MediaKind.movie,
          serverId: ServerId('srv-1'),
        ),
        selectedMediaIndex: 0,
      ),
      preferOffline: true,
    );

    expect(client.playbackInitializationCalls, 0);
    expect(result.isOffline, isTrue);
    expect(result.videoUrl, 'content://offline/movie-1');
    expect(result.availableVersions, isEmpty);
  });

  test('no-client playback falls back to the downloaded version on a default request', () async {
    // Issue #1440: only the non-default version (index 1) is downloaded, but
    // plain Play requests the default (index 0). With no client to stream
    // from, the downloaded copy must play.
    await _insertDownloaded(
      db,
      serverId: ServerId('srv-1'),
      ratingKey: 'movie-1',
      videoFilePath: 'content://offline/movie-1-v2',
      mediaIndex: 1,
      mediaSourceId: 'source-b',
    );

    final result = await PlaybackInitializationService(database: db).getPlaybackData(
      PlaybackInitializationOptions(
        metadata: testMediaItem(
          id: 'movie-1',
          backend: MediaBackend.silo,
          kind: MediaKind.movie,
          serverId: ServerId('srv-1'),
        ),
        selectedMediaIndex: 0,
      ),
    );

    expect(result.isOffline, isTrue);
    expect(result.videoUrl, 'content://offline/movie-1-v2');
    expect(result.selectedMediaIndex, 1);
    expect(result.selectedMediaSourceId, 'source-b');
  });

  test('no-client playback plays the local copy even on an explicit version mismatch', () async {
    await _insertDownloaded(
      db,
      serverId: ServerId('srv-1'),
      ratingKey: 'movie-1',
      videoFilePath: 'content://offline/movie-1-v2',
      mediaIndex: 1,
      mediaSourceId: 'source-b',
    );

    final result = await PlaybackInitializationService(database: db).getPlaybackData(
      PlaybackInitializationOptions(
        metadata: testMediaItem(
          id: 'movie-1',
          backend: MediaBackend.silo,
          kind: MediaKind.movie,
          serverId: ServerId('srv-1'),
        ),
        selectedMediaIndex: 0,
        selectedMediaSourceId: 'source-a',
      ),
    );

    expect(result.isOffline, isTrue);
    expect(result.videoUrl, 'content://offline/movie-1-v2');
    expect(result.selectedMediaIndex, 1);
  });

  test('online explicit version mismatch keeps streaming from the server', () async {
    // Online pinning guard: Play Version + Original on a NON-downloaded
    // version runs the offline check first (preferOffline), but the strict
    // mismatch must send it to the server, not the downloaded file.
    await _insertDownloaded(
      db,
      serverId: ServerId('srv-1'),
      ratingKey: 'movie-1',
      videoFilePath: 'content://offline/movie-1-v2',
      mediaIndex: 1,
      mediaSourceId: 'source-b',
    );
    final client = _StreamingPlaybackClient(serverId: ServerId('srv-1'));

    final result = await PlaybackInitializationService(client: client, database: db).getPlaybackData(
      PlaybackInitializationOptions(
        metadata: testMediaItem(
          id: 'movie-1',
          backend: MediaBackend.silo,
          kind: MediaKind.movie,
          serverId: ServerId('srv-1'),
        ),
        selectedMediaIndex: 0,
        selectedMediaSourceId: 'source-a',
      ),
      preferOffline: true,
    );

    expect(client.playbackInitializationCalls, 1);
    expect(result.isOffline, isFalse);
    expect(result.videoUrl, 'https://server/stream/0');
  });

  test('offline path falls back to media index when caller has no source id', () async {
    await _insertDownloaded(
      db,
      serverId: ServerId('srv-1'),
      ratingKey: 'movie-1',
      videoFilePath: 'content://offline/movie-1-v1',
      mediaIndex: 0,
      mediaSourceId: 'source-a',
    );

    final service = PlaybackInitializationService(database: db);

    expect(await service.getOfflineVideoPath(ServerId('srv-1'), 'movie-1', mediaIndex: 1), null);
    expect(
      await service.getOfflineVideoPath(ServerId('srv-1'), 'movie-1', mediaIndex: 0),
      'content://offline/movie-1-v1',
    );
  });

  test('SAF offline playback discovers app-managed sidecar subtitles', () async {
    await _insertDownloaded(
      db,
      serverId: ServerId('srv-1'),
      ratingKey: 'movie-1',
      videoFilePath: 'content://offline/movie-1',
    );
    final subtitlePath = await DownloadStorageService.instance.getSubtitlePath(ServerId('srv-1'), 'movie-1', 2, 'srt');
    final subtitleFile = File(subtitlePath);
    await subtitleFile.parent.create(recursive: true);
    await subtitleFile.writeAsString('1\n00:00:00,000 --> 00:00:01,000\nHello');

    final result = await PlaybackInitializationService(database: db).getPlaybackData(
      PlaybackInitializationOptions(
        metadata: testMediaItem(
          id: 'movie-1',
          backend: MediaBackend.silo,
          kind: MediaKind.movie,
          serverId: ServerId('srv-1'),
        ),
        selectedMediaIndex: 0,
      ),
      preferOffline: true,
    );

    expect(result.videoUrl, 'content://offline/movie-1');
    expect(result.externalSubtitles, hasLength(1));
    expect(result.externalSubtitles.single.uri, Uri.file(subtitlePath).toString());
    expect(
      result.subtitleSidecars.single.preload,
      isTrue,
      reason: 'local sidecars load with the media so they stay selectable as secondary subtitles (#1860)',
    );
  });
}

class _StreamingPlaybackClient implements MediaServerClient {
  _StreamingPlaybackClient({required this.serverId});

  @override
  final ServerId serverId;

  int playbackInitializationCalls = 0;

  @override
  Future<PlaybackInitializationResult> getPlaybackInitialization(PlaybackInitializationOptions options) async {
    playbackInitializationCalls++;
    return PlaybackInitializationResult(
      availableVersions: const [],
      videoUrl: 'https://server/stream/${options.selectedMediaIndex}',
      selectedMediaIndex: options.selectedMediaIndex,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingPlaybackClient implements MediaServerClient {
  _FailingPlaybackClient({required this.serverId});

  @override
  final ServerId serverId;

  int playbackInitializationCalls = 0;

  @override
  Future<PlaybackInitializationResult> getPlaybackInitialization(PlaybackInitializationOptions options) async {
    playbackInitializationCalls++;
    throw StateError('live playback initialization should not be called for downloaded playback');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _insertDownloaded(
  AppDatabase db, {
  required ServerId serverId,
  String? clientScopeId,
  required String ratingKey,
  required String videoFilePath,
  List<String>? additionalPartPaths,
  String type = 'movie',
  int mediaIndex = 0,
  String? mediaSourceId,
}) async {
  await db
      .into(db.downloadedMedia)
      .insert(
        DownloadedMediaCompanion.insert(
          serverId: serverId,
          clientScopeId: Value(clientScopeId),
          ratingKey: ratingKey,
          globalKey: '$serverId:$ratingKey',
          type: type,
          status: DownloadStatus.completed.index,
          videoFilePath: Value(videoFilePath),
          additionalPartPaths: Value(encodeAdditionalPartPaths(additionalPartPaths)),
          mediaIndex: Value(mediaIndex),
          mediaSourceId: Value(mediaSourceId),
        ),
      );
}
