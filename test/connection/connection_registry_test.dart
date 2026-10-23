import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/connection/connection_registry.dart';
import 'package:plezy/database/app_database.dart';

import '../test_helpers/prefs.dart';

SiloConnection _silo({String serverId = 'srv-1', int createdAtMs = 1_000_000}) {
  return SiloConnection(
    origin: 'https://silo.local',
    serverId: serverId,
    serverName: 'Home',
    username: 'edde',
    createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
  );
}

void main() {
  late AppDatabase db;
  late ConnectionRegistry registry;

  setUp(() {
    resetSharedPreferencesForTest();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    registry = ConnectionRegistry(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('ConnectionRegistry', () {
    test('list() returns empty when no connections stored', () async {
      expect(await registry.list(), isEmpty);
    });

    test('upserted connection round-trips through list()', () async {
      await registry.upsert(_silo(serverId: 'a'));
      final list = await registry.list();
      expect(list.length, 1);
      expect(list.first.id, 'silo:a');
    });

    test('a Silo row stores origin and server id, and no credential', () async {
      await registry.upsert(
        SiloConnection(
          origin: 'https://silo.ruleone.xyz',
          serverId: 'server-1',
          serverName: 'Silo',
          username: 'alice',
          createdAt: DateTime.fromMillisecondsSinceEpoch(1_000_000),
        ),
      );

      final restored = await registry.get('silo:server-1') as SiloConnection;
      final row = await (db.select(db.connections)..where((table) => table.id.equals('silo:server-1'))).getSingle();

      expect(
        (restored.origin, restored.serverId, restored.serverName, restored.username),
        ('https://silo.ruleone.xyz', 'server-1', 'Silo', 'alice'),
      );
      expect(row.kind, 'silo');
      expect(jsonDecode(row.configJson), {
        'origin': 'https://silo.ruleone.xyz',
        'serverId': 'server-1',
        'serverName': 'Silo',
        'username': 'alice',
      });
    });

    test('a Silo row persists the account id only once it is known', () async {
      await registry.upsert(_silo(serverId: 'a'));
      final bare = await (db.select(db.connections)..where((table) => table.id.equals('silo:a'))).getSingle();
      expect(jsonDecode(bare.configJson), isNot(contains('accountId')));

      await registry.upsert(_silo(serverId: 'a').copyWith(accountId: 'acct-1'));
      final row = await (db.select(db.connections)..where((table) => table.id.equals('silo:a'))).getSingle();
      expect(jsonDecode(row.configJson)['accountId'], 'acct-1');
      expect((await registry.get('silo:a') as SiloConnection).accountId, 'acct-1');
    });

    test('a Silo row without a server id is dropped', () async {
      await db
          .into(db.connections)
          .insert(
            ConnectionsCompanion.insert(
              id: 'silo:broken',
              kind: 'silo',
              displayName: 'Silo',
              configJson: jsonEncode({'origin': 'https://silo.ruleone.xyz'}),
              createdAt: 1_000_000,
            ),
          );

      expect(await registry.list(), isEmpty);
    });

    test('stored rows of a kind Plezy no longer ships are dropped', () async {
      for (final kind in ['plex', 'jellyfin', 'emby']) {
        await db
            .into(db.connections)
            .insert(
              ConnectionsCompanion.insert(
                id: 'legacy-$kind',
                kind: kind,
                displayName: 'Legacy',
                configJson: jsonEncode({'baseUrl': 'https://legacy.local'}),
                createdAt: 1_000_000,
              ),
            );
      }
      await registry.upsert(_silo(serverId: 's'));

      expect((await registry.list()).map((c) => c.id).toList(), ['silo:s']);
      expect(await registry.get('legacy-plex'), isNull);
      expect(await registry.get('legacy-jellyfin'), isNull);
    });

    test('remove deletes a row', () async {
      await registry.upsert(_silo(serverId: 'a'));
      await registry.upsert(_silo(serverId: 'b'));
      await registry.remove('silo:a');
      expect((await registry.list()).map((c) => c.id).toList(), ['silo:b']);
      await registry.remove('silo:b');
      expect(await registry.list(), isEmpty);
    });

    test('re-upsert preserves the original creation order', () async {
      // Regression: creation order decides which connection lends a profile
      // its picture (issue #1667) and which row `remove` promotes to default.
      // Re-authenticating rebuilds the model with `DateTime.now()` under the
      // same stable id, so an unguarded writer restamped the originally-first
      // connection and shuffled it to last.
      await registry.upsert(_silo(serverId: 'first', createdAtMs: 1_000_000));
      await registry.upsert(_silo(serverId: 'second', createdAtMs: 2_000_000));

      await registry.upsert(_silo(serverId: 'first', createdAtMs: 9_000_000));

      final list = await registry.list();
      expect(list.map((c) => c.id).toList(), ['silo:first', 'silo:second']);
      expect(list.first.createdAt, DateTime.fromMillisecondsSinceEpoch(1_000_000));
    });

    test('a genuinely new connection keeps the creation time it was built with', () async {
      await registry.upsert(_silo(serverId: 'a', createdAtMs: 5_000_000));

      expect((await registry.list()).single.createdAt, DateTime.fromMillisecondsSinceEpoch(5_000_000));
    });
  });
}
