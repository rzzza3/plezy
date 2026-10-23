import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/silo_api_cache.dart';

void main() {
  group('MediaBackend.fromString', () {
    test('reads every known id', () {
      for (final backend in MediaBackend.values) {
        expect(MediaBackend.fromString(backend.id), backend);
      }
    });

    test('an unknown or removed id is null instead of Silo', () {
      expect(MediaBackend.fromString('kodi'), isNull);
      expect(MediaBackend.fromString(''), isNull);
      for (final removed in MediaBackend.removedIds) {
        expect(MediaBackend.fromString(removed), isNull, reason: removed);
      }
    });

    test('a missing id, the oldest stored shape, is dropped too', () {
      expect(MediaBackend.fromString(null), isNull);
    });
  });

  group('MediaItem with an unknown backend', () {
    final json = {'backend': 'kodi', 'id': 'movie-1', 'kind': 'movie', 'title': 'Stray'};

    test('tryFromJson drops it', () {
      expect(MediaItem.tryFromJson(json), isNull);
    });

    test('a stored row of a removed backend is dropped', () {
      expect(MediaItem.tryFromJson({...json, 'backend': 'plex'}), isNull);
      expect(MediaItem.tryFromJson({'id': 'movie-1', 'kind': 'movie'}), isNull);
    });

    test('fromJson throws instead of decoding it as Silo', () {
      expect(() => MediaItem.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('a Silo cache row naming it reads as missing', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      SiloApiCache.initialize(db);
      final scope = ServerId('silo:server-1/p-1');
      await db
          .into(db.apiCache)
          .insert(
            ApiCacheCompanion.insert(
              cacheKey: '$scope:${SiloApiCache.itemEndpoint('movie-1')}',
              data: jsonEncode(json),
              pinned: const Value(true),
            ),
          );
      await SiloApiCache.instance.putItem(
        scope,
        const MediaItem.silo(id: 'movie-2', kind: MediaKind.movie, title: 'Kept', serverId: 'server-1'),
      );
      await SiloApiCache.instance.pinForOffline(scope, 'movie-2');

      expect(await SiloApiCache.instance.getMetadata(scope, 'movie-1'), isNull);
      final pinned = await SiloApiCache.instance.getAllPinnedMetadata();
      expect(pinned.values.map((item) => item.title), ['Kept']);
    });
  });
}
