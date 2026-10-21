import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/services/plex_api_cache.dart';

/// Pins Plex's `applyWatchState` cache mutations, so the flip defaults and the
/// epoch-seconds fields fail here instead of drifting silently.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('PlexApiCache.applyWatchState', () {
    final serverId = ServerId('plex-srv');
    const endpoint = '/library/metadata/movie-1';

    Map<String, dynamic> container({int viewCount = 0, int viewOffset = 5000}) => {
      'MediaContainer': {
        'Metadata': [
          {'ratingKey': 'movie-1', 'type': 'movie', 'title': 'Movie', 'viewCount': viewCount, 'viewOffset': viewOffset},
        ],
      },
    };

    Future<Map<String, dynamic>> readBack() async {
      final cached = await PlexApiCache.instance.get(serverId, endpoint);
      return (cached!['MediaContainer']['Metadata'] as List).first as Map<String, dynamic>;
    }

    test('watched flip sets viewCount, zeroes viewOffset, stamps lastViewedAt', () async {
      await PlexApiCache.instance.put(serverId, endpoint, container());

      await PlexApiCache.instance.applyWatchState(serverId: serverId, itemId: 'movie-1', isWatched: true);

      final json = await readBack();
      expect(json['viewCount'], 1);
      expect(json['viewOffset'], 0);
      expect(json['lastViewedAt'], isA<int>());
      expect(json['lastViewedAt'] as int, greaterThan(0));
    });

    test('watched flip preserves an existing viewCount', () async {
      await PlexApiCache.instance.put(serverId, endpoint, container(viewCount: 3));

      await PlexApiCache.instance.applyWatchState(serverId: serverId, itemId: 'movie-1', isWatched: true);

      expect((await readBack())['viewCount'], 3);
    });

    test('unwatched flip zeroes viewCount/viewOffset and leaves lastViewedAt alone', () async {
      await PlexApiCache.instance.put(serverId, endpoint, container(viewCount: 2));

      await PlexApiCache.instance.applyWatchState(serverId: serverId, itemId: 'movie-1', isWatched: false);

      final json = await readBack();
      expect(json['viewCount'], 0);
      expect(json['viewOffset'], 0);
      expect(json.containsKey('lastViewedAt'), isFalse);
    });

    test('richer snapshot fields overwrite the flip defaults', () async {
      await PlexApiCache.instance.put(serverId, endpoint, container());

      await PlexApiCache.instance.applyWatchState(
        serverId: serverId,
        itemId: 'movie-1',
        isWatched: true,
        viewOffsetMs: 123456,
        lastViewedAt: 1700000000,
        viewedLeafCount: 7,
      );

      final json = await readBack();
      // Plex stores epoch-seconds and flat fields; viewedLeafCount is stored
      // directly.
      expect(json['viewOffset'], 123456);
      expect(json['lastViewedAt'], 1700000000);
      expect(json['viewedLeafCount'], 7);
    });

    test('no cached row means nothing is written', () async {
      await PlexApiCache.instance.applyWatchState(serverId: serverId, itemId: 'missing', isWatched: true);

      expect(await PlexApiCache.instance.get(serverId, '/library/metadata/missing'), isNull);
      expect(await db.select(db.apiCache).get(), isEmpty);
    });
  });
}
