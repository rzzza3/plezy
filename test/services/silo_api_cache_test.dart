import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/api_cache.dart';
import 'package:plezy/services/plex_api_cache.dart';
import 'package:plezy/services/silo_api_cache.dart';
import 'package:plezy/utils/active_client_scope.dart';

void main() {
  late AppDatabase db;
  late SiloApiCache cache;

  final scopeA = ServerId(SiloProfileScopeId(serverId: ServerId('srv'), profileId: 'admin'));
  final scopeB = ServerId(SiloProfileScopeId(serverId: ServerId('srv'), profileId: 'kid'));

  MediaItem episode({String id = 'episode-tvdb-344961-1-1', int? viewCount, int? viewOffsetMs}) => MediaItem.silo(
    id: id,
    kind: MediaKind.episode,
    title: 'Physics',
    parentId: 'season-tvdb-344961-1',
    grandparentId: 'series-tvdb-344961',
    grandparentTitle: 'Taskmaster (US)',
    index: 1,
    parentIndex: 1,
    thumbPath: 'https://silo.example/art/1.jpg',
    durationMs: 1500000,
    viewCount: viewCount,
    viewOffsetMs: viewOffsetMs,
    serverId: 'srv',
    serverName: 'Silo',
  );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    SiloApiCache.initialize(db);
    cache = SiloApiCache.instance;
  });

  tearDown(() async {
    await db.close();
  });

  test('the Silo backend dispatches to the Silo cache, not the Plex fallback', () {
    expect(ApiCache.forBackend(MediaBackend.silo), same(cache));
  });

  test('an item written for a profile scope reads back as the same Silo item', () async {
    await cache.putItem(scopeA, episode());

    final read = await cache.getMetadata(scopeA, 'episode-tvdb-344961-1-1');

    expect(read, isA<SiloMediaItem>());
    expect(read!.title, 'Physics');
    expect(read.grandparentId, 'series-tvdb-344961');
    expect(read.globalKey, 'srv:episode-tvdb-344961-1-1');
    expect(await cache.getMetadata(scopeB, 'episode-tvdb-344961-1-1'), isNull);
  });

  test('pinned items load in bulk for the asked scopes only, keyed by the public server', () async {
    await cache.putItem(scopeA, episode());
    await cache.putItem(scopeA, episode(id: 'series-tvdb-344961'));
    await cache.putItem(scopeA, episode(id: 'unpinned'));
    await cache.putItem(scopeB, episode(id: 'other-profile'));
    await cache.pinForOffline(scopeA, 'episode-tvdb-344961-1-1');
    await cache.pinForOffline(scopeA, 'series-tvdb-344961');
    await cache.pinForOffline(scopeB, 'other-profile');

    final pinned = await cache.getAllPinnedMetadata(cacheServerIds: {scopeA});

    expect(pinned.keys, unorderedEquals(['srv:episode-tvdb-344961-1-1', 'srv:series-tvdb-344961']));
    expect(await cache.getAllPinnedMetadata(cacheServerIds: const {}), isEmpty);
    expect((await cache.getAllPinnedMetadata()).keys, hasLength(3));
  });

  test('a later write keeps the pin', () async {
    await cache.putItem(scopeA, episode());
    await cache.pinForOffline(scopeA, 'episode-tvdb-344961-1-1');

    await cache.putItem(scopeA, episode(viewOffsetMs: 60000));

    final pinned = await cache.getAllPinnedMetadata(cacheServerIds: {scopeA});
    expect(pinned['srv:episode-tvdb-344961-1-1']?.viewOffsetMs, 60000);
  });

  test('a Plex row under the same key prefix never decodes as a Silo item', () async {
    await PlexApiCache.instance.put(scopeA, SiloApiCache.itemEndpoint('x'), {
      'backend': 'plex',
      'id': 'x',
      'kind': 'movie',
    });
    await cache.pinForOffline(scopeA, 'x');

    expect(await cache.getMetadata(scopeA, 'x'), isNull);
    expect(await cache.getAllPinnedMetadata(cacheServerIds: {scopeA}), isEmpty);
  });

  test('watch state flips are written into the cached item', () async {
    await cache.putItem(scopeA, episode(viewOffsetMs: 60000));

    await cache.applyWatchState(serverId: scopeA, itemId: 'episode-tvdb-344961-1-1', isWatched: true);
    final watched = await cache.getMetadata(scopeA, 'episode-tvdb-344961-1-1');
    expect(watched!.viewCount, 1);
    expect(watched.viewOffsetMs, 0);
    expect(watched.lastViewedAt, isNotNull);

    await cache.applyWatchState(
      serverId: scopeA,
      itemId: 'episode-tvdb-344961-1-1',
      isWatched: false,
      viewOffsetMs: 120000,
    );
    final unwatched = await cache.getMetadata(scopeA, 'episode-tvdb-344961-1-1');
    expect(unwatched!.viewCount, 0);
    expect(unwatched.viewOffsetMs, 120000);
  });

  test('deleting an item removes only that scope row', () async {
    await cache.putItem(scopeA, episode());
    await cache.putItem(scopeB, episode());

    await cache.deleteForItem(scopeA, 'episode-tvdb-344961-1-1');

    expect(await cache.getMetadata(scopeA, 'episode-tvdb-344961-1-1'), isNull);
    expect(await cache.getMetadata(scopeB, 'episode-tvdb-344961-1-1'), isNotNull);
  });
}
