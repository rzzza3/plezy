import 'package:drift/native.dart';
import 'package:plezy/media/ids.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/media/episode_collection.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/server_capabilities.dart';
import 'package:plezy/models/download_models.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/sync_rule_executor.dart';

import '../test_helpers/prefs.dart';
import '../test_helpers/media_items.dart';

void main() {
  setUp(resetSharedPreferencesForTest);

  test('profile-scoped Silo sync rule executes through active client', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final manager = MultiServerManager();
    addTearDown(() async {
      manager.dispose();
      await db.close();
    });

    final userA = _ScopedSiloClient('user-a');
    final userB = _ScopedSiloClient('user-b');

    manager.debugRegisterClientForTesting(userB, online: false);
    manager.debugRegisterClientForTesting(userA);

    await db.insertSyncRule(
      profileId: 'profile-a',
      serverId: ServerId('silo-machine'),
      ratingKey: 'show-1',
      globalKey: 'profile-a|silo-machine:show-1',
      targetType: 'show',
      episodeCount: 1,
    );
    await db.insertWatchAction(
      serverId: ServerId('silo-machine'),
      clientScopeId: 'silo:silo-machine/user-b',
      ratingKey: 'ep-1',
      actionType: OfflineActionType.watched.id,
    );
    await db.insertWatchAction(
      profileId: 'profile-b',
      serverId: ServerId('silo-machine'),
      clientScopeId: 'silo:silo-machine/user-a',
      ratingKey: 'ep-1',
      actionType: OfflineActionType.watched.id,
    );

    final queued = <({MediaItem item, MediaServerClient client})>[];
    final executor = SyncRuleExecutor(database: db);
    final results = await executor.executeSyncRules(
      profileId: 'profile-a',
      serverManager: manager,
      downloads: const {},
      metadata: const {},
      associateDownload: (_, _) async {},
      queueSingleDownload: (item, client, {int mediaIndex = 0}) async {
        queued.add((item: item, client: client));
        return true;
      },
      isOffline: false,
      force: true,
    );

    expect(results.single.queuedCount, 1);
    expect(queued.single.client, same(userA));
    expect(userA.fetchPlayableDescendantsCalls, ['show-1']);
    expect(userB.calls, isEmpty);
  });

  test('profile-scoped sync rule excludes only the active profile local watched actions', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final manager = MultiServerManager();
    addTearDown(() async {
      manager.dispose();
      await db.close();
    });

    final userA = _ScopedSiloClient('user-a');
    manager.debugRegisterClientForTesting(userA);

    await db.insertSyncRule(
      profileId: 'profile-a',
      serverId: ServerId('silo-machine'),
      ratingKey: 'show-1',
      globalKey: 'profile-a|silo-machine:show-1',
      targetType: 'show',
      episodeCount: 1,
    );
    await db.insertWatchAction(
      profileId: 'profile-a',
      serverId: ServerId('silo-machine'),
      clientScopeId: 'silo:silo-machine/user-a',
      ratingKey: 'ep-1',
      actionType: OfflineActionType.watched.id,
    );

    final queued = <MediaItem>[];
    final executor = SyncRuleExecutor(database: db);
    final results = await executor.executeSyncRules(
      profileId: 'profile-a',
      serverManager: manager,
      downloads: const {},
      metadata: const {},
      associateDownload: (_, _) async {},
      queueSingleDownload: (item, client, {int mediaIndex = 0}) async {
        queued.add(item);
        return true;
      },
      isOffline: false,
      force: true,
    );

    expect(results, isEmpty);
    expect(queued, isEmpty);
    expect(userA.fetchPlayableDescendantsCalls, ['show-1']);
  });

  test('profile-scoped Silo sync rule does not execute for another profile', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final manager = MultiServerManager();
    addTearDown(() async {
      manager.dispose();
      await db.close();
    });

    final userB = _ScopedSiloClient('user-b');
    manager.debugRegisterClientForTesting(userB);

    await db.insertSyncRule(
      profileId: 'profile-a',
      serverId: ServerId('silo-machine'),
      ratingKey: 'show-1',
      globalKey: 'profile-a|silo-machine:show-1',
      targetType: 'show',
      episodeCount: 1,
    );

    final executor = SyncRuleExecutor(database: db);
    final results = await executor.executeSyncRules(
      profileId: 'profile-b',
      serverManager: manager,
      downloads: const {},
      metadata: const {},
      associateDownload: (_, _) async {},
      queueSingleDownload: (item, client, {int mediaIndex = 0}) async => true,
      isOffline: false,
      force: true,
    );

    expect(results, isEmpty);
    expect(userB.calls, isEmpty);
  });

  test('profile-scoped Silo sync rule counts shared public downloads as already present', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final manager = MultiServerManager();
    addTearDown(() async {
      manager.dispose();
      await db.close();
    });

    final userB = _ScopedSiloClient('user-b');
    manager.debugRegisterClientForTesting(userB);

    await db.insertSyncRule(
      profileId: 'profile-b',
      serverId: ServerId('silo-machine'),
      ratingKey: 'show-1',
      globalKey: 'profile-b|silo-machine:show-1',
      targetType: 'show',
      episodeCount: 1,
    );

    final queued = <MediaItem>[];
    final associated = <String>[];
    final executor = SyncRuleExecutor(database: db);
    final results = await executor.executeSyncRules(
      profileId: 'profile-b',
      serverManager: manager,
      downloads: const {
        'silo-machine:ep-1': DownloadProgress(globalKey: 'silo-machine:ep-1', status: DownloadStatus.completed),
      },
      metadata: const {},
      associateDownload: (_, globalKey) async => associated.add(globalKey),
      queueSingleDownload: (item, client, {int mediaIndex = 0}) async {
        queued.add(item);
        return true;
      },
      isOffline: false,
      force: true,
    );

    expect(results, isEmpty);
    expect(queued, isEmpty);
    expect(userB.fetchPlayableDescendantsCalls, ['show-1']);
    expect(associated, ['silo-machine:ep-1']);
    expect((await db.getSyncRule('profile-b|silo-machine:show-1'))!.downloadLinksInitialized, isTrue);
  });

  test('show sync rule respects includeSpecials=false when expanding episodes', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final manager = MultiServerManager();
    addTearDown(() async {
      manager.dispose();
      await db.close();
    });

    final client = _PlayableDescendantsClient([
      _episode('s1e1', parentIndex: 1, index: 1, originallyAvailableAt: '2022-10-05'),
      _episode('s0e1', parentIndex: 0, index: 1, originallyAvailableAt: '2022-10-27'),
      _episode('s1e2', parentIndex: 1, index: 2, originallyAvailableAt: '2022-11-02'),
    ]);
    manager.debugRegisterClientForTesting(client);

    const ruleKey = 'profile-a|plex-machine:show-1';
    final show = testMediaItem(id: 'show-1', backend: MediaBackend.silo, kind: MediaKind.show, title: 'Show');
    await db.insertSyncRule(
      profileId: 'profile-a',
      serverId: ServerId('plex-machine'),
      ratingKey: 'show-1',
      globalKey: ruleKey,
      targetType: 'show',
      episodeCount: 0,
      includeSpecials: false,
    );

    final queued = <MediaItem>[];
    final executor = SyncRuleExecutor(database: db);
    final results = await executor.executeSyncRules(
      profileId: 'profile-a',
      serverManager: manager,
      downloads: const {},
      metadata: {ruleKey: show},
      associateDownload: (_, _) async {},
      queueSingleDownload: (item, client, {int mediaIndex = 0}) async {
        queued.add(item);
        return true;
      },
      isOffline: false,
      force: true,
    );

    expect(results.single.queuedCount, 2);
    expect(queued.map((item) => item.id), ['s1e1', 's1e2']);
    expect(client.fetchPlayableDescendantsCalls, ['show-1']);
  });

  test('Silo playlist sync associates an already-downloaded member', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final manager = MultiServerManager();
    addTearDown(() async {
      manager.dispose();
      await db.close();
    });

    final client = _PlaylistPagingClient();
    manager.debugRegisterClientForTesting(client);
    const ruleKey = 'profile-a|silo-machine:playlist-1';
    await db.insertSyncRule(
      profileId: 'profile-a',
      serverId: ServerId('silo-machine'),
      ratingKey: 'playlist-1',
      globalKey: ruleKey,
      targetType: 'playlist',
      episodeCount: 0,
      downloadFilter: SyncRuleFilter.all,
    );
    final associated = <String>[];

    final results = await SyncRuleExecutor(database: db).executeSyncRules(
      profileId: 'profile-a',
      serverManager: manager,
      downloads: const {
        'silo-machine:episode-1': DownloadProgress(
          globalKey: 'silo-machine:episode-1',
          status: DownloadStatus.completed,
        ),
      },
      metadata: const {},
      associateDownload: (_, globalKey) async => associated.add(globalKey),
      queueSingleDownload: (_, _, {int mediaIndex = 0}) async {
        fail('an already-downloaded playlist member must not be queued');
      },
      isOffline: false,
      force: true,
    );

    expect(results, isEmpty);
    expect(associated, ['silo-machine:episode-1']);
    expect(client.playlistPageCalls, [(start: 0, size: 200)]);
    expect((await db.getSyncRule(ruleKey))!.downloadLinksInitialized, isTrue);
  });

  test('collection sync rule pages through collection API instead of metadata children', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final manager = MultiServerManager();
    addTearDown(() async {
      manager.dispose();
      await db.close();
    });

    final client = _CollectionPagingClient();
    manager.debugRegisterClientForTesting(client);

    const ruleKey = 'profile-a|plex-machine:collection-1';
    final collection = testMediaItem(
      id: 'collection-1',
      backend: MediaBackend.silo,
      kind: MediaKind.collection,
      title: 'Collection',
      serverId: 'plex-machine',
    );

    await db.insertSyncRule(
      profileId: 'profile-a',
      serverId: ServerId('plex-machine'),
      ratingKey: 'collection-1',
      globalKey: ruleKey,
      targetType: 'collection',
      episodeCount: 0,
      downloadFilter: SyncRuleFilter.all,
    );

    final queued = <MediaItem>[];
    final associated = <String>[];
    final executor = SyncRuleExecutor(database: db);
    final results = await executor.executeSyncRules(
      profileId: 'profile-a',
      serverManager: manager,
      downloads: const {},
      metadata: {ruleKey: collection},
      associateDownload: (_, globalKey) async => associated.add(globalKey),
      queueSingleDownload: (item, client, {int mediaIndex = 0}) async {
        queued.add(item);
        return true;
      },
      isOffline: false,
      force: true,
    );

    expect(results.single.queuedCount, 1);
    expect(queued.single.id, 'movie-1');
    expect(associated, ['plex-machine:movie-1']);
    expect((await db.getSyncRule(ruleKey))!.downloadLinksInitialized, isTrue);
    expect(client.collectionPageCalls, [(start: 0, size: 100)]);
    expect(client.fetchChildrenCalled, isFalse);
  });

  test('unwatched collection rule expands each member once and keeps watched members in membership', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final manager = MultiServerManager();
    addTearDown(() async {
      manager.dispose();
      await db.close();
    });

    final client = _ShowCollectionClient([
      _episode('ep-1', parentIndex: 1, index: 1),
      _episode('ep-2', parentIndex: 1, index: 2, played: true),
    ]);
    manager.debugRegisterClientForTesting(client);

    const ruleKey = 'profile-a|plex-machine:collection-1';
    final collection = testMediaItem(
      id: 'collection-1',
      backend: MediaBackend.silo,
      kind: MediaKind.collection,
      title: 'Collection',
      serverId: 'plex-machine',
    );
    await db.insertSyncRule(
      profileId: 'profile-a',
      serverId: ServerId('plex-machine'),
      ratingKey: 'collection-1',
      globalKey: ruleKey,
      targetType: 'collection',
      episodeCount: 0,
      downloadFilter: SyncRuleFilter.unwatched,
    );

    final queued = <MediaItem>[];
    final associated = <String>[];
    final results = await SyncRuleExecutor(database: db).executeSyncRules(
      profileId: 'profile-a',
      serverManager: manager,
      downloads: const {
        'plex-machine:ep-2': DownloadProgress(globalKey: 'plex-machine:ep-2', status: DownloadStatus.completed),
      },
      metadata: {ruleKey: collection},
      associateDownload: (_, globalKey) async => associated.add(globalKey),
      queueSingleDownload: (item, client, {int mediaIndex = 0}) async {
        queued.add(item);
        return true;
      },
      isOffline: false,
      force: true,
    );

    expect(client.fetchPlayableDescendantsCalls, ['show-1']);
    expect(queued.map((item) => item.id), ['ep-1']);
    // The watched member stays associated for cleanup provenance.
    expect(associated, ['plex-machine:ep-2', 'plex-machine:ep-1']);
    expect(results.single.queuedCount, 1);
  });

  test('legacy list backfill associates active members without queueing', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final manager = MultiServerManager();
    addTearDown(() async {
      manager.dispose();
      await db.close();
    });

    final client = _CollectionPagingClient();
    manager.debugRegisterClientForTesting(client);
    const ruleKey = 'profile-a|plex-machine:collection-1';
    final collection = testMediaItem(
      id: 'collection-1',
      backend: MediaBackend.silo,
      kind: MediaKind.collection,
      title: 'Collection',
      serverId: 'plex-machine',
    );
    await db.insertSyncRule(
      profileId: 'profile-a',
      serverId: ServerId('plex-machine'),
      ratingKey: 'collection-1',
      globalKey: ruleKey,
      targetType: 'collection',
      episodeCount: 0,
      downloadFilter: SyncRuleFilter.all,
    );
    final rule = (await db.getSyncRule(ruleKey))!;
    final associated = <String>[];

    final backfilled = await SyncRuleExecutor(database: db).backfillListRuleDownloadLinks(
      rule: rule,
      serverManager: manager,
      downloads: const {
        'plex-machine:movie-1': DownloadProgress(globalKey: 'plex-machine:movie-1', status: DownloadStatus.completed),
      },
      metadata: {ruleKey: collection},
      associateDownload: (_, globalKey) async => associated.add(globalKey),
    );

    expect(backfilled, isTrue);
    expect(associated, ['plex-machine:movie-1']);
    expect((await db.getSyncRule(ruleKey))!.downloadLinksInitialized, isTrue);
  });

  test('collectListLeaves accepts tracks and expands albums/artists', () async {
    final albumTracks = [_track('album-track-1'), _track('album-track-2', played: true)];
    final client = _PlayableDescendantsClient(albumTracks);

    final items = [
      _track('loose-track'),
      testMediaItem(id: 'album-1', backend: MediaBackend.silo, kind: MediaKind.album, title: 'Album'),
      testMediaItem(id: 'artist-1', backend: MediaBackend.silo, kind: MediaKind.artist, title: 'Artist'),
      // Still skipped: nested lists / unplayable kinds.
      testMediaItem(id: 'photo-1', backend: MediaBackend.silo, kind: MediaKind.photo, title: 'Photo'),
    ];

    final out = <MediaItem>[];
    await collectListLeaves(client, items, unwatchedOnly: false, out: out);

    expect(client.fetchPlayableDescendantsCalls, ['album-1', 'artist-1']);
    expect(out.map((i) => i.id), ['loose-track', 'album-track-1', 'album-track-2', 'album-track-1', 'album-track-2']);

    // unwatchedOnly applies the play-count filter to tracks too.
    final unwatched = <MediaItem>[];
    await collectListLeaves(
      client,
      [_track('played-track', played: true), items[1]],
      unwatchedOnly: true,
      out: unwatched,
    );
    expect(unwatched.map((i) => i.id), ['album-track-1']);
  });
}

MediaItem _track(String id, {bool played = false}) {
  return testMediaItem(id: id, backend: MediaBackend.silo, kind: MediaKind.track, title: id, viewCount: played ? 1 : 0);
}

MediaItem _episode(
  String id, {
  required int parentIndex,
  required int index,
  String? originallyAvailableAt,
  bool played = false,
}) {
  return testMediaItem(
    id: id,
    backend: MediaBackend.silo,
    kind: MediaKind.episode,
    title: id,
    parentIndex: parentIndex,
    index: index,
    originallyAvailableAt: originallyAvailableAt,
    viewCount: played ? 1 : 0,
  );
}

class _ShowCollectionClient implements MediaServerClient {
  _ShowCollectionClient(this.episodes);

  final List<MediaItem> episodes;
  final fetchPlayableDescendantsCalls = <String>[];

  @override
  ServerId get serverId => ServerId('plex-machine');

  @override
  String? get serverName => 'Plex';

  @override
  MediaBackend get backend => MediaBackend.silo;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  bool get isOfflineMode => false;

  @override
  void close() {}

  @override
  Future<MediaItem?> fetchItem(String id) async => null;

  @override
  Future<List<MediaItem>> fetchPlayableDescendants(String parentId) async {
    fetchPlayableDescendantsCalls.add(parentId);
    return episodes;
  }

  @override
  Future<LibraryPage<MediaItem>> fetchCollectionPage(
    String collectionId, {
    int? start,
    int? size,
    abort,
    String? libraryId,
    String? libraryTitle,
  }) async => LibraryPage(
    items: [testMediaItem(id: 'show-1', backend: MediaBackend.silo, kind: MediaKind.show, title: 'Show')],
    totalCount: 1,
    offset: start ?? 0,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PlayableDescendantsClient implements MediaServerClient {
  _PlayableDescendantsClient(this.leaves);

  final List<MediaItem> leaves;
  final fetchPlayableDescendantsCalls = <String>[];

  @override
  ServerId get serverId => ServerId('plex-machine');

  @override
  String? get serverName => 'Plex';

  @override
  MediaBackend get backend => MediaBackend.silo;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  bool get isOfflineMode => false;

  @override
  void close() {}

  @override
  Future<MediaItem?> fetchItem(String id) async => null;

  @override
  Future<List<MediaItem>> fetchPlayableDescendants(String parentId) async {
    fetchPlayableDescendantsCalls.add(parentId);
    return leaves;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PlaylistPagingClient implements MediaServerClient {
  final playlistPageCalls = <({int? start, int? size})>[];

  @override
  ServerId get serverId => ServerId('silo-machine');

  @override
  String? get serverName => 'Silo';

  @override
  MediaBackend get backend => MediaBackend.silo;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.silo;

  @override
  bool get isOfflineMode => false;

  @override
  void close() {}

  @override
  Future<MediaItem?> fetchItem(String id) async => null;

  @override
  Future<LibraryPage<MediaItem>> fetchPlaylistPage(String id, {int? start, int? size, abort}) async {
    playlistPageCalls.add((start: start, size: size));
    expect(id, 'playlist-1');
    return LibraryPage(
      items: [testMediaItem(id: 'episode-1', backend: MediaBackend.silo, kind: MediaKind.episode, title: 'Episode')],
      totalCount: 1,
      offset: start ?? 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CollectionPagingClient implements MediaServerClient {
  bool fetchChildrenCalled = false;
  final collectionPageCalls = <({int? start, int? size})>[];

  @override
  ServerId get serverId => ServerId('plex-machine');

  @override
  String? get serverName => 'Plex';

  @override
  MediaBackend get backend => MediaBackend.silo;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  bool get isOfflineMode => false;

  @override
  void close() {}

  @override
  Future<MediaItem?> fetchItem(String id) async => null;

  @override
  Future<List<MediaItem>> fetchChildren(String parentId) async {
    fetchChildrenCalled = true;
    throw StateError('collection rules must not use fetchChildren');
  }

  @override
  Future<LibraryPage<MediaItem>> fetchCollectionPage(
    String collectionId, {
    int? start,
    int? size,
    abort,
    String? libraryId,
    String? libraryTitle,
  }) async {
    collectionPageCalls.add((start: start, size: size));
    expect(collectionId, 'collection-1');
    return LibraryPage(
      items: [testMediaItem(id: 'movie-1', backend: MediaBackend.silo, kind: MediaKind.movie, title: 'Movie')],
      totalCount: 1,
      offset: start ?? 0,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A Silo client scoped to one Silo profile, serving show-1 with one unwatched
/// episode.
class _ScopedSiloClient implements MediaServerClient, ScopedMediaServerClient {
  _ScopedSiloClient(this.profileId);

  final String profileId;
  final calls = <String>[];
  final fetchPlayableDescendantsCalls = <String>[];

  @override
  ServerId get serverId => ServerId('silo-machine');

  @override
  String get scopedServerId => 'silo:silo-machine/$profileId';

  @override
  String? get serverName => 'Shared Silo';

  @override
  MediaBackend get backend => MediaBackend.silo;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.silo;

  @override
  bool get isOfflineMode => false;

  @override
  void close() {}

  @override
  Future<MediaItem?> fetchItem(String id) async {
    calls.add('fetchItem $id');
    return testMediaItem(id: id, backend: MediaBackend.silo, kind: MediaKind.show, title: 'Show $profileId');
  }

  @override
  Future<List<MediaItem>> fetchPlayableDescendants(String parentId) async {
    calls.add('fetchPlayableDescendants $parentId');
    fetchPlayableDescendantsCalls.add(parentId);
    return [
      testMediaItem(
        id: 'ep-1',
        backend: MediaBackend.silo,
        kind: MediaKind.episode,
        title: 'Episode $profileId',
        grandparentId: parentId,
        parentIndex: 1,
        index: 1,
        viewCount: 0,
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
