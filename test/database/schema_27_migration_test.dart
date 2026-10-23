import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/database/download_operations.dart';
import 'package:plezy/media/ids.dart';
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

const _connectionId = 'silo:silo-srv';
const _serverId = 'silo-srv';

/// One local Plezy profile bound to the Silo connection, entering the Silo
/// profile [siloProfileId].
class _Local {
  const _Local(this.id, this.siloProfileId);

  final String id;
  final String siloProfileId;

  String get scope => 'silo:$_serverId/$siloProfileId';
  String get globalKey => '$_serverId:item-$siloProfileId';
}

const _admin = _Local('local-a', 'admin');
const _kid = _Local('local-b', 'kid');

Future<int> _userVersion(AppDatabase db) async =>
    (await db.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version');

Future<void> _seedConnection(AppDatabase db, {required String id, required String kind}) => db
    .into(db.connections)
    .insert(ConnectionsCompanion.insert(id: id, kind: kind, displayName: kind, configJson: '{}', createdAt: 0));

Future<void> _seedProfile(AppDatabase db, String id, String kind) => db
    .into(db.profiles)
    .insert(ProfilesCompanion.insert(id: id, kind: kind, displayName: id, configJson: '{}', createdAt: 0));

/// The rows a local profile owned on an S8 install, all under its Silo
/// scope.
Future<void> _seedLocal(AppDatabase db, _Local local) async {
  await _seedProfile(db, local.id, 'local');
  await db
      .into(db.profileConnections)
      .insert(
        ProfileConnectionsCompanion.insert(
          profileId: local.id,
          connectionId: _connectionId,
          userIdentifier: local.siloProfileId,
        ),
      );
  await db.insertDownload(
    serverId: ServerId(_serverId),
    clientScopeId: local.scope,
    ratingKey: 'item-${local.siloProfileId}',
    globalKey: local.globalKey,
    type: 'movie',
    status: DownloadStatus.completed.index,
  );
  await db.updateVideoFilePath(local.globalKey, 'downloads/Movies/${local.siloProfileId}.mkv');
  await db.addDownloadOwner(
    profileId: local.id,
    globalKey: local.globalKey,
    backendId: 'silo',
    clientScopeId: local.scope,
  );
  await db.addToQueue(mediaGlobalKey: local.globalKey);
  final ruleId = await db
      .into(db.syncRules)
      .insert(
        SyncRulesCompanion.insert(
          profileId: Value(local.id),
          serverId: _serverId,
          ratingKey: 'show-${local.siloProfileId}',
          globalKey: '$_serverId:show-${local.siloProfileId}',
          targetType: 'show',
          episodeCount: 3,
          createdAt: 0,
        ),
      );
  await db
      .into(db.syncRuleDownloads)
      .insert(
        SyncRuleDownloadsCompanion.insert(syncRuleId: ruleId, profileId: local.id, downloadGlobalKey: local.globalKey),
      );
  await db
      .into(db.downloadCollections)
      .insert(
        DownloadCollectionsCompanion.insert(
          profileId: local.id,
          serverId: _serverId,
          collectionId: 'collection-${local.siloProfileId}',
          memberIds: '["item-${local.siloProfileId}"]',
        ),
      );
  await db
      .into(db.downloadCollectionSyncs)
      .insert(
        DownloadCollectionSyncsCompanion.insert(
          profileId: local.id,
          serverId: _serverId,
          syncedAt: 0,
          checkedIds: '[]',
        ),
      );
  await db
      .into(db.offlineWatchProgress)
      .insert(
        OfflineWatchProgressCompanion.insert(
          profileId: Value(local.id),
          serverId: _serverId,
          clientScopeId: Value(local.scope),
          ratingKey: 'item-${local.siloProfileId}',
          globalKey: local.globalKey,
          actionType: 'progress',
          viewOffset: const Value(640430),
          createdAt: 0,
          updatedAt: 0,
        ),
      );
  await db
      .into(db.musicSessions)
      .insert(
        MusicSessionsCompanion.insert(
          profileId: local.id,
          queueJson: jsonEncode([
            {'backend': 'silo', 'id': 'track-1', 'kind': 'track', 'serverId': _serverId},
          ]),
          orderJson: '[0]',
          cursor: 0,
          updatedAt: 0,
        ),
      );
  await db
      .into(db.apiCache)
      .insert(
        ApiCacheCompanion.insert(
          cacheKey: '${local.scope}:/silo/items/item-${local.siloProfileId}',
          data: '{}',
          pinned: const Value(true),
        ),
      );
}

/// Two local profiles bound to one Silo connection, written by [version]
/// of the schema.
Future<void> _seedTwoLocals(File file, {required int version, Future<void> Function(AppDatabase db)? extra}) async {
  final db = AppDatabase.forTesting(NativeDatabase(file), schemaVersion: version);
  try {
    await _seedConnection(db, id: _connectionId, kind: 'silo');
    await _seedLocal(db, _admin);
    await _seedLocal(db, _kid);
    // A watch action queued before profile ownership, with no scope.
    await db
        .into(db.offlineWatchProgress)
        .insert(
          OfflineWatchProgressCompanion.insert(
            serverId: _serverId,
            ratingKey: 'unscoped',
            globalKey: '$_serverId:unscoped',
            actionType: 'watched',
            createdAt: 0,
            updatedAt: 0,
          ),
        );
    await extra?.call(db);
    expect(await _userVersion(db), version, reason: 'the seed must be a schema $version database');
  } finally {
    await db.close();
  }
}

/// What a trunk (schema 25) install adds next to the Silo rows: a Plex
/// account with a Plex Home profile and a Plex download.
Future<void> _seedTrunkPlex(AppDatabase db) async {
  await _seedConnection(db, id: 'plex-account', kind: 'plex');
  await _seedProfile(db, 'plex-home-acct-uuid', 'plex_home');
  await db
      .into(db.profileConnections)
      .insert(
        ProfileConnectionsCompanion.insert(
          profileId: 'plex-home-acct-uuid',
          connectionId: 'plex-account',
          userIdentifier: 'uuid',
        ),
      );
  await db.insertDownload(
    serverId: ServerId('plex-machine'),
    clientScopeId: 'plex-machine/~plex-profile/local-a',
    ratingKey: 'item-plex',
    globalKey: 'plex-machine:item-plex',
    type: 'movie',
    status: DownloadStatus.completed.index,
  );
  await db.addDownloadOwner(
    profileId: _admin.id,
    globalKey: 'plex-machine:item-plex',
    backendId: 'plex',
    clientScopeId: 'plex-machine/~plex-profile/local-a',
  );
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

/// The expectations both upgrade paths share: Plezy's profiles and what they
/// owned are gone; the Silo connection, downloads and scopes stay.
Future<void> _expectPlezyProfilesRemoved(AppDatabase db) async {
  expect(await _userVersion(db), 27);
  expect(await db.select(db.profiles).get(), isEmpty);
  expect(await db.select(db.profileConnections).get(), isEmpty);

  final connections = await db.select(db.connections).get();
  expect(connections.map((row) => (row.id, row.kind)), [(_connectionId, 'silo')]);

  for (final local in [_admin, _kid]) {
    final download = await db.getDownloadedMedia(local.globalKey);
    expect(download?.clientScopeId, local.scope);
    expect(download?.status, DownloadStatus.completed.index);
    expect(download?.videoFilePath, 'downloads/Movies/${local.siloProfileId}.mkv');
  }
  expect(await _column(db, 'download_queue', 'media_global_key'), [_admin.globalKey, _kid.globalKey]);
  expect(await db.select(db.downloadOwners).get(), isEmpty);
  expect(await db.select(db.syncRules).get(), isEmpty);
  expect(await db.select(db.syncRuleDownloads).get(), isEmpty);
  expect(await db.select(db.downloadCollections).get(), isEmpty);
  expect(await db.select(db.downloadCollectionSyncs).get(), isEmpty);
  expect(await db.select(db.musicSessions).get(), isEmpty);
  expect(await _column(db, 'api_cache', 'cache_key'), [
    '${_admin.scope}:/silo/items/item-admin',
    '${_kid.scope}:/silo/items/item-kid',
  ]);

  final progress = await (db.select(db.offlineWatchProgress)..orderBy([(t) => OrderingTerm.asc(t.ratingKey)])).get();
  expect(progress.map((row) => (row.ratingKey, row.profileId, row.clientScopeId)), [
    ('item-admin', _admin.scope, _admin.scope),
    ('item-kid', _kid.scope, _kid.scope),
    ('unscoped', null, null),
  ]);
}

void main() {
  late Directory tempDir;
  late File file;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('plezy_db_v27_migration_test_');
    file = File('${tempDir.path}/plezy_downloads.db');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('schema 27 migration', () {
    test('from S8 data: removes the local profiles and keeps the Silo connection', () async {
      await _seedTwoLocals(file, version: 26);

      final db = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(db.close);
      await _expectPlezyProfilesRemoved(db);
    });

    test('from trunk data: runs through the v26 purge, then removes the local profiles', () async {
      await _seedTwoLocals(file, version: 25, extra: _seedTrunkPlex);

      final db = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(db.close);
      await _expectPlezyProfilesRemoved(db);
      expect(await db.getDownloadedMedia('plex-machine:item-plex'), isNull);
    });

    test('a Silo profile reclaims only the downloads of its own scope', () async {
      await _seedTwoLocals(file, version: 26);

      final db = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(db.close);
      await db.adoptLegacyDownloadsForProfile(_admin.scope);

      final owners = await db.select(db.downloadOwners).get();
      expect(owners.map((row) => (row.profileId, row.globalKey, row.backend, row.clientScopeId)), [
        (_admin.scope, _admin.globalKey, 'silo', _admin.scope),
      ]);
    });

    test('is idempotent when run again or reopened', () async {
      await _seedTwoLocals(file, version: 26);

      final db = AppDatabase.forTesting(NativeDatabase(file));
      final migrated = await _snapshot(db);
      await db.purgePlezyProfileData();
      expect(await _snapshot(db), migrated);
      await db.close();

      final reopened = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(reopened.close);
      expect(await _snapshot(reopened), migrated);
    });
  });
}
