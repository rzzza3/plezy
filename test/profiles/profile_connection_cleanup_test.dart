import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/connection/connection_registry.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/models/plex/plex_home_user.dart';
import 'package:plezy/profiles/profile.dart';
import 'package:plezy/profiles/profile_connection.dart';
import 'package:plezy/profiles/profile_connection_cleanup.dart';
import 'package:plezy/profiles/profile_connection_registry.dart';
import 'package:plezy/profiles/profile_registry.dart';
import 'package:plezy/services/plex_auth_service.dart';
import 'package:plezy/services/storage_service.dart';

import '../test_helpers/prefs.dart';

SiloConnection _silo({String serverId = 'silo-server'}) {
  return SiloConnection(
    origin: 'https://silo.example.test',
    serverId: serverId,
    serverName: 'Silo',
    username: 'alice',
    createdAt: DateTime.fromMillisecondsSinceEpoch(1_000_000),
    lastAuthenticatedAt: DateTime.fromMillisecondsSinceEpoch(1_000_000),
  );
}

PlexAccountConnection _plex({String id = 'plex-account', String serverMachineId = 'plex-machine'}) {
  return PlexAccountConnection(
    id: id,
    accountToken: 'account-token',
    clientIdentifier: 'client-1',
    accountLabel: 'Plex',
    servers: [
      PlexServer(
        name: 'Plex Server',
        clientIdentifier: serverMachineId,
        accessToken: 'server-token',
        connections: [
          PlexConnection(
            protocol: 'https',
            address: 'plex.example.test',
            port: 443,
            uri: 'https://plex.example.test',
            local: false,
            relay: false,
            ipv6: false,
          ),
        ],
        owned: true,
      ),
    ],
    createdAt: DateTime.fromMillisecondsSinceEpoch(1_000_000),
    lastAuthenticatedAt: DateTime.fromMillisecondsSinceEpoch(1_000_000),
  );
}

PlexHomeUser _homeUser(String uuid) {
  return PlexHomeUser(
    id: 1,
    uuid: uuid,
    title: 'User $uuid',
    thumb: '',
    hasPassword: false,
    restricted: false,
    updatedAt: null,
    admin: false,
    guest: false,
    protected: false,
  );
}

ProfileConnection _row(String profileId, Connection conn, {String userIdentifier = 'user'}) {
  return ProfileConnection(profileId: profileId, connectionId: conn.id, userToken: 't', userIdentifier: userIdentifier);
}

void main() {
  late AppDatabase db;
  late ConnectionRegistry connections;
  late ProfileConnectionRegistry profileConnections;
  late StorageService storage;
  late ProfileConnectionCleanup cleanup;
  late List<String> signedOut;

  setUp(() async {
    signedOut = [];
    resetSharedPreferencesForTest();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    connections = ConnectionRegistry(db);
    profileConnections = ProfileConnectionRegistry(db);
    storage = await StorageService.getInstance();
    cleanup = ProfileConnectionCleanup(
      profileConnections: profileConnections,
      connections: connections,
      storage: storage,
      signOutSilo: (connection) async => signedOut.add(connection.id),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('profile connection cleanup', () {
    test('removing the last Silo profile link deletes the connection and profile prefs', () async {
      final conn = _silo();
      await connections.upsert(conn);
      await profileConnections.upsert(
        ProfileConnection(profileId: 'p1', connectionId: conn.id, userIdentifier: 'sp-1'),
      );
      await storage.setActiveProfileId('p1');
      await storage.saveHiddenLibraries({'silo-server:movies'});
      await storage.saveLibraryOrder(['silo-server:movies']);

      await cleanup.removeProfileConnection(profileId: 'p1', connection: conn);

      expect(await profileConnections.listForConnection(conn.id), isEmpty);
      expect(await connections.get(conn.id), isNull);
      expect(storage.getHiddenLibraries(), isEmpty);
      expect(storage.getLibraryOrder(), isNull);
    });

    test('removing one profile link keeps a shared Silo connection and other profile prefs', () async {
      final conn = _silo();
      await connections.upsert(conn);
      await profileConnections.upsert(
        ProfileConnection(profileId: 'p1', connectionId: conn.id, userIdentifier: 'sp-1'),
      );
      await profileConnections.upsert(
        ProfileConnection(profileId: 'p2', connectionId: conn.id, userIdentifier: 'sp-2'),
      );

      await storage.setActiveProfileId('p1');
      await storage.saveHiddenLibraries({'silo-server:movies'});
      await storage.setActiveProfileId('p2');
      await storage.saveHiddenLibraries({'silo-server:movies'});

      await cleanup.removeProfileConnection(profileId: 'p1', connection: conn);

      expect(await connections.get(conn.id), isNotNull);
      final remaining = await profileConnections.listForConnection(conn.id);
      expect(remaining, hasLength(1));
      expect(remaining.single.profileId, 'p2');

      await storage.setActiveProfileId('p1');
      expect(storage.getHiddenLibraries(), isEmpty);
      await storage.setActiveProfileId('p2');
      expect(storage.getHiddenLibraries(), {'silo-server:movies'});
    });

    group('Silo, TvSettingsViewModel.kt:748-762', () {
      final silo = SiloConnection(
        origin: 'https://silo.ruleone.xyz',
        serverId: 'server-1',
        serverName: 'Silo',
        username: 'alice',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1_000_000),
      );
      test('removing the last link signs this device out of the server and deletes the connection', () async {
        await connections.upsert(silo);
        await profileConnections.upsert(
          ProfileConnection(profileId: 'p1', connectionId: silo.id, userIdentifier: 'sp-1'),
        );

        await cleanup.removeProfileConnection(profileId: 'p1', connection: silo);

        expect(signedOut, ['silo:server-1']);
        expect(await connections.get(silo.id), isNull);
      });

      test('full logout signs out every Silo connection and leaves other kinds alone', () async {
        final other = SiloConnection(
          origin: 'https://other.silo.test',
          serverId: 'server-2',
          serverName: 'Other',
          username: 'bob',
          createdAt: DateTime.fromMillisecondsSinceEpoch(1_000_000),
        );
        await connections.upsert(silo);
        await connections.upsert(other);
        await connections.upsert(_plex());

        await cleanup.signOutAllSiloConnections();

        expect(signedOut..sort(), ['silo:server-1', 'silo:server-2']);
        expect((await connections.list()).length, 3, reason: 'logout clears the rows itself, after this');
      });

      test('a link another profile still holds keeps the session', () async {
        await connections.upsert(silo);
        await profileConnections.upsert(
          ProfileConnection(profileId: 'p1', connectionId: silo.id, userIdentifier: 'sp-1'),
        );
        await profileConnections.upsert(
          ProfileConnection(profileId: 'p2', connectionId: silo.id, userIdentifier: 'sp-2'),
        );

        await cleanup.removeProfileConnection(profileId: 'p1', connection: silo);

        expect(signedOut, isEmpty);
        expect(await connections.get(silo.id), isNotNull);
      });

      test('startup prune signs out an orphaned Silo connection', () async {
        await connections.upsert(silo);

        expect(await cleanup.pruneUnreferencedConnections(), 1);
        expect(signedOut, ['silo:server-1']);
      });
    });

    test('startup prune removes unreferenced Silo rows and stale prefs', () async {
      final conn = _silo();
      await connections.upsert(conn);
      await storage.setActiveProfileId('p1');
      await storage.saveHiddenLibraries({'silo-server:movies'});
      await storage.saveLibrarySort('silo-server:movies', 'titleSort');

      final removed = await cleanup.pruneUnreferencedConnections();

      expect(removed, 1);
      expect(await connections.get(conn.id), isNull);
      expect(storage.getHiddenLibraries(), isEmpty);
      expect(storage.getLibrarySort('silo-server:movies'), isNull);
    });

    test('sign-out removes the account, its virtual profiles, and their borrowed Silo connection (#1423)', () async {
      const uuid = 'aaaaaaaaaaaaaaaa';
      final acct = _plex();
      final silo = _silo();
      final vProfile = plexHomeProfileId(accountConnectionId: acct.id, homeUserUuid: uuid);
      await connections.upsert(acct);
      await connections.upsert(silo);
      await profileConnections.upsert(_row(vProfile, acct, userIdentifier: uuid));
      await profileConnections.upsert(_row(vProfile, silo));
      await storage.savePlexHomeUsersCache(acct.id, [_homeUser(uuid).toJson()]);
      await storage.markProfileUsed(vProfile, DateTime.fromMillisecondsSinceEpoch(2_000_000));
      await storage.setActiveProfileId(vProfile);
      await storage.saveHiddenLibraries({'silo-server:movies'});

      final plannedRemoval = await planPlexAccountConnectionRemoval(
        account: acct,
        profileConnections: profileConnections,
      );
      expect(plannedRemoval.removedVirtualProfileIds, {vProfile});
      expect(await connections.get(acct.id), isNotNull);
      expect(await profileConnections.listAll(), hasLength(2));

      final removal = await cleanup.removePlexAccountConnection(acct, plannedRemoval: plannedRemoval);

      expect(removal.removedVirtualProfileIds, {vProfile});
      expect(removal.borrowerProfileIds, isEmpty);
      expect(await connections.list(), isEmpty);
      expect(await profileConnections.listAll(), isEmpty);
      expect(storage.getPlexHomeUsersCacheJson(acct.id), isNull);
      expect(storage.getProfileLastUsed(vProfile), isNull);
      expect(storage.getHiddenLibraries(), isEmpty);
    });

    test('sign-out keeps a borrowed Silo connection another profile still references', () async {
      const uuid = 'aaaaaaaaaaaaaaaa';
      final acct = _plex();
      final silo = _silo();
      final vProfile = plexHomeProfileId(accountConnectionId: acct.id, homeUserUuid: uuid);
      await connections.upsert(acct);
      await connections.upsert(silo);
      await profileConnections.upsert(_row(vProfile, acct, userIdentifier: uuid));
      await profileConnections.upsert(_row(vProfile, silo));
      await profileConnections.upsert(_row('local-1', silo));

      await cleanup.removePlexAccountConnection(acct);

      expect(await connections.get(silo.id), isNotNull);
      final remaining = await profileConnections.listAll();
      expect(remaining, hasLength(1));
      expect(remaining.single.profileId, 'local-1');
    });

    test('sign-out from a local borrower keeps the local profile and its Silo connection (repro 2 shape)', () async {
      final acct = _plex();
      final silo = _silo();
      await connections.upsert(acct);
      await connections.upsert(silo);
      await profileConnections.upsert(_row('local-1', acct));
      await profileConnections.upsert(_row('local-1', silo));

      final removal = await cleanup.removePlexAccountConnection(acct);

      expect(removal.removedVirtualProfileIds, isEmpty);
      expect(removal.borrowerProfileIds, {'local-1'});
      expect(await connections.get(acct.id), isNull);
      expect(await connections.get(silo.id), isNotNull);
      final remaining = await profileConnections.listAll();
      expect(remaining, hasLength(1));
      expect(remaining.single.connectionId, silo.id);
    });

    test('sign-out leaves another account and its virtual profiles untouched (hyphen-bearing ids)', () async {
      const uuid1 = 'aaaaaaaaaaaaaaaa';
      const uuid2 = 'bbbbbbbbbbbbbbbb';
      final acct1 = _plex();
      final acct2 = _plex(id: 'plex-account-2', serverMachineId: 'plex-machine-2');
      final v1 = plexHomeProfileId(accountConnectionId: acct1.id, homeUserUuid: uuid1);
      final v2 = plexHomeProfileId(accountConnectionId: acct2.id, homeUserUuid: uuid2);
      await connections.upsert(acct1);
      await connections.upsert(acct2);
      await profileConnections.upsert(_row(v1, acct1, userIdentifier: uuid1));
      await profileConnections.upsert(_row(v2, acct2, userIdentifier: uuid2));
      await storage.savePlexHomeUsersCache(acct2.id, [_homeUser(uuid2).toJson()]);

      final removal = await cleanup.removePlexAccountConnection(acct1);

      expect(removal.removedVirtualProfileIds, {v1});
      expect(await connections.get(acct2.id), isNotNull);
      final remaining = await profileConnections.listAll();
      expect(remaining, hasLength(1));
      expect(remaining.single.profileId, v2);
      expect(storage.getPlexHomeUsersCacheJson(acct2.id), isNotNull);
    });

    test('sign-out is idempotent', () async {
      const uuid = 'aaaaaaaaaaaaaaaa';
      final acct = _plex();
      final silo = _silo();
      final vProfile = plexHomeProfileId(accountConnectionId: acct.id, homeUserUuid: uuid);
      await connections.upsert(acct);
      await connections.upsert(silo);
      await profileConnections.upsert(_row(vProfile, acct, userIdentifier: uuid));
      await profileConnections.upsert(_row(vProfile, silo));

      Future<PlexAccountRemoval> run() => cleanup.removePlexAccountConnection(acct);

      await run();
      final second = await run();

      expect(second.removedVirtualProfileIds, isEmpty);
      expect(await connections.list(), isEmpty);
      expect(await profileConnections.listAll(), isEmpty);
    });

    test('Plex profile unlink clears only that profile because Plex Home access can be implicit', () async {
      final conn = _plex();
      await connections.upsert(conn);
      await profileConnections.upsert(
        ProfileConnection(profileId: 'p1', connectionId: conn.id, userToken: 'user-token', userIdentifier: 'home-user'),
      );

      await storage.setActiveProfileId('p1');
      await storage.saveHiddenLibraries({'plex-machine:movies'});
      await storage.setActiveProfileId('p2');
      await storage.saveHiddenLibraries({'plex-machine:movies'});

      await cleanup.removeProfileConnection(profileId: 'p1', connection: conn);

      expect(await connections.get(conn.id), isNotNull);
      expect(await profileConnections.listForConnection(conn.id), isEmpty);
      await storage.setActiveProfileId('p1');
      expect(storage.getHiddenLibraries(), isEmpty);
      await storage.setActiveProfileId('p2');
      expect(storage.getHiddenLibraries(), {'plex-machine:movies'});
    });
  });

  group('resolvePostRemovalState', () {
    late ProfileRegistry profileRegistry;

    setUp(() {
      profileRegistry = ProfileRegistry(db);
    });

    Future<({PostRemovalRoute route, List<Profile> profiles})> resolve({
      Map<String, List<PlexHomeUser>> plexHomeUsers = const {},
    }) {
      return cleanup.resolvePostRemovalState(profileRegistry: profileRegistry, plexHomeUsers: plexHomeUsers);
    }

    Profile local(String id) =>
        Profile.local(id: id, displayName: id, createdAt: DateTime.fromMillisecondsSinceEpoch(1_000_000));

    test('no connections → signed out', () async {
      final result = await resolve();
      expect(result.route, PostRemovalRoute.signedOut);
      expect(result.profiles, isEmpty);
    });

    test('only an orphaned Silo connection → pruned, signed out (the #1423 wedge)', () async {
      final silo = _silo();
      await connections.upsert(silo);

      final result = await resolve();

      expect(result.route, PostRemovalRoute.signedOut);
      expect(await connections.list(), isEmpty);
    });

    test('account with cached home users → stay signed in with the virtual profiles', () async {
      final acct = _plex();
      await connections.upsert(acct);

      final result = await resolve(
        plexHomeUsers: {
          acct.id: [_homeUser('aaaaaaaaaaaaaaaa')],
        },
      );

      expect(result.route, PostRemovalRoute.staySignedIn);
      expect(result.profiles.single.isPlexHome, isTrue);
    });

    test('account but no resolvable home users and no locals → signed out (boot-guard mirror)', () async {
      final acct = _plex();
      await connections.upsert(acct);
      // Referenced so the prune keeps nothing to do; still unresolvable.
      await profileConnections.upsert(_row('plex-home-${acct.id}-aaaaaaaaaaaaaaaa', acct));

      final result = await resolve();

      expect(result.route, PostRemovalRoute.signedOut);
    });

    test('local profile survives alongside an orphaned Silo connection → stay signed in, orphan pruned', () async {
      final orphan = _silo(serverId: 'silo-orphan');
      final referenced = _silo(serverId: 'silo-referenced');
      await connections.upsert(orphan);
      await connections.upsert(referenced);
      await profileRegistry.upsert(local('local-1'));
      await profileConnections.upsert(_row('local-1', referenced));

      final result = await resolve();

      expect(result.route, PostRemovalRoute.staySignedIn);
      expect(result.profiles.single.id, 'local-1');
      expect(await connections.get(orphan.id), isNull);
      expect(await connections.get(referenced.id), isNotNull);
    });
  });
}
