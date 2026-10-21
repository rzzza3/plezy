import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/database/download_operations.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/models/download_models.dart';

import '../test_helpers/download_fixtures.dart';

const _tables = [
  'connections',
  'profiles',
  'profile_connections',
  'downloaded_media',
  'download_owners',
  'download_queue',
  'sync_rules',
  'sync_rule_downloads',
  'download_collections',
  'download_collection_syncs',
  'offline_watch_progress',
  'api_cache',
  'music_sessions',
];

/// One backend's worth of stored rows, as a schema 25 install holds them.
class _Seed {
  const _Seed({
    required this.backend,
    required this.connectionId,
    required this.serverId,
    required this.scope,
    required this.cacheKey,
    required this.profileId,
  });

  final String backend;
  final String? connectionId;
  final String serverId;
  final String? scope;
  final String cacheKey;
  final String profileId;

  String get globalKey => '$serverId:item-$backend';
}

const _plex = _Seed(
  backend: 'plex',
  connectionId: 'plex-account',
  serverId: 'plex-machine',
  scope: 'plex-machine/~plex-profile/local-a',
  cacheKey: 'plex-machine/~plex-profile/local-a:/library/metadata/item-plex',
  profileId: 'local-a',
);
const _jellyfin = _Seed(
  backend: 'jellyfin',
  connectionId: 'jf-machine/user-1',
  serverId: 'jf-machine',
  scope: 'jf-machine/user-1',
  cacheKey: 'jf-machine/user-1:/Users/user-1/Items/item-jellyfin',
  profileId: 'local-b',
);
const _emby = _Seed(
  backend: 'emby',
  connectionId: 'emby-machine/user-2',
  serverId: 'emby-machine',
  scope: null,
  cacheKey: 'emby-machine:/Users/user-2/Items/item-emby',
  profileId: 'local-c',
);
const _silo = _Seed(
  backend: 'silo',
  connectionId: 'silo:silo-srv',
  serverId: 'silo-srv',
  scope: 'silo:silo-srv/admin',
  cacheKey: 'silo:silo-srv/admin:/silo/items/item-silo',
  profileId: 'local-a',
);

/// A Silo server the user signed out of. Its scoped download stays.
const _siloSignedOut = _Seed(
  backend: 'silo',
  connectionId: null,
  serverId: 'silo-gone',
  scope: 'silo:silo-gone/kid',
  cacheKey: 'silo:silo-gone/kid:/silo/items/item-silo',
  profileId: 'local-b',
);

Future<void> _seedBackend(AppDatabase db, _Seed seed) async {
  if (seed.connectionId case final connectionId?) {
    await db
        .into(db.connections)
        .insert(
          ConnectionsCompanion.insert(
            id: connectionId,
            kind: seed.backend,
            displayName: seed.backend,
            configJson: '{}',
            createdAt: 0,
          ),
        );
    await db
        .into(db.profileConnections)
        .insert(
          ProfileConnectionsCompanion.insert(
            profileId: seed.profileId,
            connectionId: connectionId,
            userIdentifier: 'user-${seed.backend}',
          ),
        );
  }
  await db.insertDownload(
    serverId: ServerId(seed.serverId),
    clientScopeId: seed.scope,
    ratingKey: 'item-${seed.backend}',
    globalKey: seed.globalKey,
    type: 'movie',
    status: DownloadStatus.completed.index,
  );
  await db.updateVideoFilePath(seed.globalKey, 'downloads/Movies/${seed.backend}/${seed.backend}.mkv');
  await db.addDownloadOwner(
    profileId: seed.profileId,
    globalKey: seed.globalKey,
    backendId: seed.backend,
    clientScopeId: seed.scope,
  );
  await db.addToQueue(mediaGlobalKey: seed.globalKey);
  final ruleId = await db
      .into(db.syncRules)
      .insert(
        SyncRulesCompanion.insert(
          profileId: Value(seed.profileId),
          serverId: seed.serverId,
          ratingKey: 'show-${seed.backend}',
          globalKey: '${seed.serverId}:show-${seed.backend}',
          targetType: 'show',
          episodeCount: 3,
          createdAt: 0,
        ),
      );
  await db
      .into(db.syncRuleDownloads)
      .insert(
        SyncRuleDownloadsCompanion.insert(
          syncRuleId: ruleId,
          profileId: seed.profileId,
          downloadGlobalKey: seed.globalKey,
        ),
      );
  await db
      .into(db.downloadCollections)
      .insert(
        DownloadCollectionsCompanion.insert(
          profileId: seed.profileId,
          serverId: seed.serverId,
          collectionId: 'collection-${seed.backend}',
          memberIds: '["item-${seed.backend}"]',
        ),
      );
  await db
      .into(db.downloadCollectionSyncs)
      .insert(
        DownloadCollectionSyncsCompanion.insert(
          profileId: seed.profileId,
          serverId: seed.serverId,
          syncedAt: 0,
          checkedIds: '[]',
        ),
      );
  await db
      .into(db.offlineWatchProgress)
      .insert(
        OfflineWatchProgressCompanion.insert(
          profileId: Value(seed.profileId),
          serverId: seed.serverId,
          clientScopeId: Value(seed.scope),
          ratingKey: 'item-${seed.backend}',
          globalKey: seed.globalKey,
          actionType: 'progress',
          viewOffset: const Value(640430),
          createdAt: 0,
          updatedAt: 0,
        ),
      );
  await db
      .into(db.apiCache)
      .insert(ApiCacheCompanion.insert(cacheKey: seed.cacheKey, data: '{}', pinned: const Value(true)));
}

Future<void> _seedMusicSession(AppDatabase db, String profileId, Map<String, dynamic> itemJson) async {
  await db
      .into(db.musicSessions)
      .insert(
        MusicSessionsCompanion.insert(
          profileId: profileId,
          queueJson: jsonEncode([itemJson]),
          orderJson: '[0]',
          cursor: 0,
          updatedAt: 0,
        ),
      );
}

Future<void> _seedProfile(AppDatabase db, String id, String kind) => db
    .into(db.profiles)
    .insert(ProfilesCompanion.insert(id: id, kind: kind, displayName: id, configJson: '{}', createdAt: 0));

/// Builds a schema 25 database holding rows for every backend.
Future<void> _seedSchema25(File file) async {
  final db = AppDatabase.forTesting(NativeDatabase(file), schemaVersion: 25);
  try {
    for (final seed in [_plex, _jellyfin, _emby, _silo, _siloSignedOut]) {
      await _seedBackend(db, seed);
    }
    // Plex's other cache shapes: an unscoped row and a pre-v17 transfer row.
    for (final key in ['plex-machine:/library/sections', 'plex-machine/~plex-transfer:/library/metadata/9']) {
      await db.into(db.apiCache).insert(ApiCacheCompanion.insert(cacheKey: key, data: '{}'));
    }
    // An ownerless Plex download and an orphan Plex owner.
    await db.insertDownload(
      serverId: ServerId('plex-machine'),
      ratingKey: 'ownerless',
      globalKey: 'plex-machine:ownerless',
      type: 'episode',
      status: DownloadStatus.queued.index,
    );
    await db.addDownloadOwner(profileId: 'local-b', globalKey: 'plex-machine:gone');
    // A Silo owner written without backend or scope, as before S6's fix.
    await db.addDownloadOwner(profileId: 'local-b', globalKey: _silo.globalKey);

    await _seedProfile(db, 'local-a', 'local');
    await _seedProfile(db, 'local-b', 'local');
    await _seedProfile(db, 'plex-home-acct-uuid', 'plex_home');

    await _seedMusicSession(
      db,
      'local-a',
      const MediaItem.silo(id: 'track-1', kind: MediaKind.track, serverId: 'silo-srv').toJson(),
    );
    await _seedMusicSession(
      db,
      'local-b',
      const MediaItem.plex(id: 'track-2', kind: MediaKind.track, serverId: 'plex-machine').toJson(),
    );
    await _seedMusicSession(
      db,
      'local-c',
      // A legacy Jellyfin queue entry, as schema 25 stored it.
      {'backend': 'jellyfin', 'id': 'track-3', 'kind': 'track', 'serverId': 'jf-machine'},
    );
    expect(
      (await db.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version'),
      25,
      reason: 'the seed must be a schema 25 database',
    );
  } finally {
    await db.close();
  }
}

Future<Map<String, List<Map<String, Object?>>>> _snapshot(AppDatabase db) async {
  return {
    for (final table in _tables)
      table: [for (final row in await db.customSelect('SELECT * FROM $table ORDER BY rowid').get()) row.data],
  };
}

Future<List<String>> _column(AppDatabase db, String table, String column) async {
  final rows = await db.customSelect('SELECT $column FROM $table ORDER BY $column').get();
  return [for (final row in rows) '${row.data[column]}'];
}

void main() {
  late Directory tempDir;
  late File file;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('plezy_db_v26_migration_test_');
    file = File('${tempDir.path}/plezy_downloads.db');
    await _seedSchema25(file);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('schema 26 migration', () {
    test('removes every Plex, Jellyfin and Emby row', () async {
      final db = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(db.close);

      expect((await db.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version'), 26);
      expect(await _column(db, 'connections', 'kind'), ['silo']);
      expect(await _column(db, 'profile_connections', 'connection_id'), ['silo:silo-srv']);
      expect(await _column(db, 'downloaded_media', 'server_id'), ['silo-gone', 'silo-srv']);
      expect(await _column(db, 'download_owners', 'global_key'), [
        _siloSignedOut.globalKey,
        _silo.globalKey,
        _silo.globalKey,
      ]);
      expect(await _column(db, 'download_queue', 'media_global_key'), [_siloSignedOut.globalKey, _silo.globalKey]);
      expect(await _column(db, 'sync_rules', 'server_id'), ['silo-gone', 'silo-srv']);
      expect(await _column(db, 'sync_rule_downloads', 'download_global_key'), [
        _siloSignedOut.globalKey,
        _silo.globalKey,
      ]);
      expect(await _column(db, 'download_collections', 'server_id'), ['silo-gone', 'silo-srv']);
      expect(await _column(db, 'download_collection_syncs', 'server_id'), ['silo-gone', 'silo-srv']);
      expect(await _column(db, 'offline_watch_progress', 'server_id'), ['silo-gone', 'silo-srv']);
      expect(await _column(db, 'api_cache', 'cache_key'), [_siloSignedOut.cacheKey, _silo.cacheKey]);
      expect(await _column(db, 'music_sessions', 'profile_id'), ['local-a']);

      for (final seed in [_plex, _jellyfin, _emby]) {
        for (final table in _tables) {
          final rows = await db.customSelect('SELECT * FROM $table').get();
          for (final row in rows) {
            final values = row.data.values.whereType<String>();
            expect(
              values.where((value) => value.contains(seed.serverId) || value.contains('"backend":"${seed.backend}"')),
              isEmpty,
              reason: '$table keeps a ${seed.backend} row: ${row.data}',
            );
          }
        }
      }
    });

    test('keeps Silo rows unchanged, with their scopes and progress', () async {
      final db = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(db.close);

      final download = await db.getDownloadedMedia(_silo.globalKey);
      expect(download?.clientScopeId, 'silo:silo-srv/admin');
      expect(download?.status, DownloadStatus.completed.index);
      expect(download?.videoFilePath, 'downloads/Movies/silo/silo.mkv');
      final signedOut = await db.getDownloadedMedia(_siloSignedOut.globalKey);
      expect(signedOut?.clientScopeId, 'silo:silo-gone/kid');

      final owners = await db.select(db.downloadOwners).get();
      expect(
        owners.where((owner) => owner.globalKey == _silo.globalKey).map((owner) => (owner.profileId, owner.backend)),
        unorderedEquals([('local-a', 'silo'), ('local-b', null)]),
      );

      final progress = await db.getPendingWatchActions(profileId: 'local-a');
      expect(progress.single.clientScopeId, 'silo:silo-srv/admin');
      expect(progress.single.viewOffset, 640430);

      final cache = await (db.select(db.apiCache)..where((t) => t.cacheKey.equals(_silo.cacheKey))).getSingle();
      expect(cache.pinned, isTrue);

      final binding = await db.select(db.profileConnections).getSingle();
      expect((binding.profileId, binding.userIdentifier), ('local-a', 'user-silo'));
    });

    test('keeps local profiles and drops Plex Home rows', () async {
      final db = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(db.close);

      final profiles = await db.select(db.profiles).get();
      expect(profiles.map((profile) => (profile.id, profile.kind)), [('local-a', 'local'), ('local-b', 'local')]);
    });

    test('is idempotent when run again or reopened', () async {
      final db = AppDatabase.forTesting(NativeDatabase(file));
      final migrated = await _snapshot(db);
      await db.purgeNonSiloBackendData();
      expect(await _snapshot(db), migrated);
      await db.close();

      final reopened = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(reopened.close);
      expect(await _snapshot(reopened), migrated);
    });

    test('the upgrade gives the purged cache space back to the file system', () async {
      final seeded = AppDatabase.forTesting(NativeDatabase(file), schemaVersion: 25);
      final payload = 'x' * 4096;
      await seeded.batch((batch) {
        for (var i = 0; i < 500; i++) {
          batch.insert(
            seeded.apiCache,
            ApiCacheCompanion.insert(cacheKey: 'plex-machine:/library/metadata/$i', data: payload),
          );
        }
      });
      await seeded.close();
      final before = await file.length();

      final db = AppDatabase.forTesting(NativeDatabase(file));
      await db.customSelect('SELECT 1').get();
      await db.close();

      expect(before, greaterThan(2000000));
      expect(await file.length(), lessThan(before - 2000000));
    });

    test('a fresh schema 26 database keeps Silo rows written after creation', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await _seedBackend(db, _silo);

      final before = await _snapshot(db);
      await db.purgeNonSiloBackendData();
      expect(await _snapshot(db), before);
    });
  });
}
