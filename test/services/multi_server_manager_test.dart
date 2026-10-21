import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:plezy/media/ids.dart';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/models/plex/plex_config.dart';
import 'package:plezy/services/plex_api_cache.dart';
import 'package:plezy/services/plex_auth_service.dart';
import 'package:plezy/services/plex_client.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/storage_service.dart';
import 'package:plezy/utils/active_client_scope.dart';
import 'package:plezy/utils/device_identity.dart';

import '../test_helpers/backend_client_fixtures.dart';
import '../test_helpers/http_fixtures.dart';
import '../test_helpers/prefs.dart';

void main() {
  setUp(resetSharedPreferencesForTest);

  group('initial state', () {
    test('a freshly constructed manager has no servers, clients, or status', () {
      final m = MultiServerManager();
      addTearDown(m.dispose);

      expect(m.serverIds, isEmpty);
      expect(m.onlineServerIds, isEmpty);
      expect(m.offlineServerIds, isEmpty);
      expect(m.onlineClients, isEmpty);
    });

    test('getClient returns null for unknown ids', () {
      final m = MultiServerManager();
      addTearDown(m.dispose);

      expect(m.getClient(ServerId('nope')), isNull);
      expect(m.isServerOnline(ServerId('nope')), isFalse);
    });
  });

  group('updateServerStatus + statusStream', () {
    test('emits a snapshot when status flips for a tracked server', () async {
      final m = MultiServerManager();
      addTearDown(m.dispose);

      final emitted = <Map<String, bool>>[];
      final sub = m.statusStream.listen(emitted.add);
      addTearDown(sub.cancel);

      // Pre-seed status (mirrors what addServer would do post-connect).
      m.updateServerStatus(ServerId('srv-1'), true);
      m.updateServerStatus(ServerId('srv-2'), false);
      m.updateServerStatus(ServerId('srv-1'), false); // change

      // Let the broadcast stream events drain.
      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(3));
      expect(emitted[0], {'srv-1': true});
      expect(emitted[1], {'srv-1': true, 'srv-2': false});
      expect(emitted[2], {'srv-1': false, 'srv-2': false});
    });

    test('repeated identical status is debounced (no extra emission)', () async {
      final m = MultiServerManager();
      addTearDown(m.dispose);

      final emitted = <Map<String, bool>>[];
      final sub = m.statusStream.listen(emitted.add);
      addTearDown(sub.cancel);

      m.updateServerStatus(ServerId('srv-1'), true);
      m.updateServerStatus(ServerId('srv-1'), true); // same value: no-op
      m.updateServerStatus(ServerId('srv-1'), true);

      await Future<void>.delayed(Duration.zero);
      expect(emitted, hasLength(1));
      expect(emitted.first, {'srv-1': true});
    });

    test('online/offline server-id getters reflect updateServerStatus', () {
      final m = MultiServerManager();
      addTearDown(m.dispose);

      m.updateServerStatus(ServerId('a'), true);
      m.updateServerStatus(ServerId('b'), false);
      m.updateServerStatus(ServerId('c'), true);

      expect(m.onlineServerIds.toSet(), {'a', 'c'});
      expect(m.offlineServerIds.toSet(), {'b'});
      expect(m.isServerOnline(ServerId('a')), isTrue);
      expect(m.isServerOnline(ServerId('b')), isFalse);
    });
  });

  group('endpoint exhaustion verification', () {
    setUp(() {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      PlexApiCache.initialize(db);
    });

    PlexClient plexClient(Future<http.Response> Function(http.Request request) handler) =>
        testPlexClient(serverId: ServerId('plex-server'), handler: handler);

    test('content-route exhaustion keeps an authenticated server online', () async {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);
      final client = plexClient((_) async => http.Response('{}', 200, headers: {'content-type': 'application/json'}));
      manager.debugRegisterClientForTesting(client);

      final emitted = <Map<String, bool>>[];
      final sub = manager.statusStream.listen(emitted.add);
      addTearDown(sub.cancel);

      await manager.debugVerifyServerEndpointsExhaustedForTesting(ServerId('plex-server'));
      await Future<void>.delayed(Duration.zero);

      expect(manager.isServerOnline(ServerId('plex-server')), isTrue);
      expect(manager.authErrorServerIds, isEmpty);
      expect(emitted, isEmpty, reason: 'a successful health probe must not publish a false offline transition');
    });

    test('auth rejection is published without attempting generic reconnection', () async {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);
      final client = plexClient((_) async => http.Response('', 401));
      manager.debugRegisterClientForTesting(client);

      final emitted = <Map<String, bool>>[];
      final sub = manager.statusStream.listen(emitted.add);
      addTearDown(sub.cancel);

      await manager.debugVerifyServerEndpointsExhaustedForTesting(ServerId('plex-server'));
      await Future<void>.delayed(Duration.zero);

      expect(manager.isServerOnline(ServerId('plex-server')), isFalse);
      expect(manager.authErrorServerIds, {'plex-server'});
      expect(emitted, [
        {'plex-server': false},
      ]);
    });

    test('an account refusal (403) is published as access denied, not as a sign-in prompt', () async {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);
      final client = plexClient((_) async => http.Response('', 403));
      manager.debugRegisterClientForTesting(client);

      final emitted = <Map<String, bool>>[];
      final sub = manager.statusStream.listen(emitted.add);
      addTearDown(sub.cancel);

      await manager.debugVerifyServerEndpointsExhaustedForTesting(ServerId('plex-server'));
      await Future<void>.delayed(Duration.zero);

      expect(manager.isServerOnline(ServerId('plex-server')), isFalse);
      expect(manager.accessDeniedServerIds, {'plex-server'});
      expect(manager.authErrorServerIds, isEmpty, reason: 'a new sign-in gets the same refusal');
      // The server answered, so no endpoint failover or reconnection follows.
      expect(emitted, [
        {'plex-server': false},
      ]);
    });
  });

  group('refreshTokensForProfile', () {
    test('successful in-place Plex token refresh clears auth-error state', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      PlexApiCache.initialize(db);
      addTearDown(db.close);

      final m = MultiServerManager();
      addTearDown(m.dispose);

      final client = PlexClient.forTesting(
        config: PlexConfig(
          baseUrl: 'https://plex.example',
          token: 'old-token',
          clientIdentifier: 'client-id',
          product: 'Plezy',
          version: '1.0.0',
        ),
        serverId: ServerId('server-1'),
        profileScopeId: buildPlexProfileScopeId(serverId: ServerId('server-1'), profileId: 'profile-1'),
        serverName: 'Plex',
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'MediaContainer': {'machineIdentifier': 'server-1'},
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      );
      m.debugRegisterClientForTesting(client, online: true);
      m.debugMarkAuthErrorForTesting(ServerId('server-1'));

      final bound = await m.refreshTokensForProfile(
        PlexAccountConnection(
          id: 'account-1',
          accountToken: 'account-token',
          clientIdentifier: 'client-id',
          accountLabel: 'Account',
          servers: [
            PlexServer(
              name: 'Plex',
              clientIdentifier: 'server-1',
              accessToken: 'new-token',
              connections: const [],
              owned: true,
            ),
          ],
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
        profileId: 'profile-1',
      );

      expect(bound, {'server-1'});
      expect(m.authErrorServerIds, isNot(contains('server-1')));
      expect(client.config.token, 'new-token');
    });

    test('unavailable optional Plex providers commits the token and clears old profile provider state', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      PlexApiCache.initialize(db);
      addTearDown(db.close);

      String? tokenFor(http.Request request) {
        for (final entry in request.headers.entries) {
          if (entry.key.toLowerCase() == 'x-plex-token') return entry.value;
        }
        return null;
      }

      final client = PlexClient.forTesting(
        config: PlexConfig(
          baseUrl: 'https://plex.example',
          token: 'old-token',
          clientIdentifier: 'client-id',
          product: 'Plezy',
          version: '1.0.0',
        ),
        serverId: ServerId('server-1'),
        profileScopeId: buildPlexProfileScopeId(serverId: ServerId('server-1'), profileId: 'old-profile'),
        serverName: 'Plex',
        httpClient: MockClient((request) async {
          switch (request.url.path) {
            case '/':
              return jsonResponse({
                'MediaContainer': {'machineIdentifier': 'server-1'},
              });
            case '/media/providers':
              if (tokenFor(request) == 'new-token') {
                return http.Response('provider unavailable', 503);
              }
              return jsonResponse({
                'MediaContainer': {
                  'MediaProvider': [
                    {
                      'identifier': 'com.plexapp.plugins.library',
                      'Feature': [
                        {
                          'type': 'content',
                          'Directory': [
                            {'id': '1', 'key': '/library/sections/1', 'type': 'movie', 'title': 'Old Profile Movies'},
                          ],
                        },
                      ],
                    },
                  ],
                },
              });
            case '/library/sections':
              return jsonResponse({
                'MediaContainer': {
                  'Directory': [
                    {'key': '9', 'type': 'movie', 'title': 'Fallback Movies'},
                  ],
                },
              });
            default:
              fail('Unexpected Plex request: ${request.url.path}');
          }
        }),
      );
      final oldScope = buildPlexProfileScopeId(serverId: ServerId('server-1'), profileId: 'old-profile');
      expect(await client.applyProfileUpdate(newToken: 'old-token', newProfileScopeId: oldScope), isTrue);
      expect((await client.fetchLibraries()).map((library) => library.title), ['Old Profile Movies']);

      final manager = MultiServerManager();
      addTearDown(manager.dispose);
      manager.debugRegisterClientForTesting(client, online: true);

      final bound = await manager.refreshTokensForProfile(
        _plexAccount('account-1', [
          PlexServer(
            name: 'Plex',
            clientIdentifier: 'server-1',
            accessToken: 'new-token',
            connections: const [],
            owned: true,
          ),
        ]),
        profileId: 'new-profile',
      );

      expect(bound, {'server-1'});
      expect(manager.isServerOnline(ServerId('server-1')), isTrue);
      expect(manager.authErrorServerIds, isNot(contains('server-1')));
      expect(client.config.token, 'new-token');
      expect(client.profileScopeId, buildPlexProfileScopeId(serverId: ServerId('server-1'), profileId: 'new-profile'));
      // Live TV favorites are keyed by the owning account, not the device.
      expect(client.plexAccountId, 'account-1');
      expect((await client.fetchLibraries()).map((library) => library.title), ['Fallback Movies']);
    });

    test('newest overlapping Plex profile refresh owns provider state', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      PlexApiCache.initialize(db);
      addTearDown(db.close);

      final responseGates = <String, Completer<http.Response>>{
        'token-a': Completer<http.Response>(),
        'token-b': Completer<http.Response>(),
      };
      final requestStarted = <String, Completer<void>>{'token-a': Completer<void>(), 'token-b': Completer<void>()};
      String? tokenFor(http.Request request) {
        for (final entry in request.headers.entries) {
          if (entry.key.toLowerCase() == 'x-plex-token') return entry.value;
        }
        return null;
      }

      http.Response providerResponse(String id, String title) => http.Response(
        jsonEncode({
          'MediaContainer': {
            'MediaProvider': [
              {
                'identifier': 'com.plexapp.plugins.library',
                'Feature': [
                  {
                    'type': 'content',
                    'Directory': [
                      {'id': id, 'key': '/library/sections/$id', 'type': 'movie', 'title': title},
                    ],
                  },
                ],
              },
            ],
          },
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );

      final client = PlexClient.forTesting(
        config: PlexConfig(
          baseUrl: 'https://plex.example',
          token: 'old-token',
          clientIdentifier: 'client-id',
          product: 'Plezy',
          version: '1.0.0',
        ),
        serverId: ServerId('server-1'),
        profileScopeId: buildPlexProfileScopeId(serverId: ServerId('server-1'), profileId: 'old-profile'),
        serverName: 'Plex',
        httpClient: MockClient((request) async {
          final token = tokenFor(request)!;
          if (request.url.path == '/') {
            return http.Response(
              jsonEncode({
                'MediaContainer': {'machineIdentifier': 'server-1'},
              }),
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          expect(request.url.path, '/media/providers');
          requestStarted[token]!.complete();
          return responseGates[token]!.future;
        }),
      );
      final manager = MultiServerManager();
      addTearDown(manager.dispose);
      manager.debugRegisterClientForTesting(client, online: true);

      PlexServer server(String token) => PlexServer(
        name: 'Plex',
        clientIdentifier: 'server-1',
        accessToken: token,
        connections: const [],
        owned: true,
      );

      final earlier = manager.refreshTokensForProfile(
        _plexAccount('account-1', [server('token-a')]),
        profileId: 'profile-a',
      );
      await requestStarted['token-a']!.future;
      final later = manager.refreshTokensForProfile(
        _plexAccount('account-1', [server('token-b')]),
        profileId: 'profile-b',
      );
      await requestStarted['token-b']!.future;

      responseGates['token-b']!.complete(providerResponse('2', 'Profile B Movies'));
      expect(await later, {'server-1'});
      responseGates['token-a']!.complete(providerResponse('1', 'Profile A Movies'));
      expect(await earlier, isEmpty);

      expect(client.config.token, 'token-b');
      expect(client.profileScopeId, buildPlexProfileScopeId(serverId: ServerId('server-1'), profileId: 'profile-b'));
      final libraries = await client.fetchLibraries();
      expect(libraries.map((library) => library.title), ['Profile B Movies']);
    });

    for (final (status, refusal) in [(401, 'auth-failed'), (403, 'access-denied')]) {
      test('refreshed Plex token rejected with $status remains offline and $refusal', () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        PlexApiCache.initialize(db);
        addTearDown(db.close);

        final client = PlexClient.forTesting(
          config: PlexConfig(
            baseUrl: 'https://plex.example',
            token: 'old-token',
            clientIdentifier: 'client-id',
            product: 'Plezy',
            version: '1.0.0',
          ),
          serverId: ServerId('server-1'),
          profileScopeId: buildPlexProfileScopeId(serverId: ServerId('server-1'), profileId: 'old-profile'),
          serverName: 'Plex',
          httpClient: MockClient((request) async {
            expect(request.url.path, '/');
            return http.Response('rejected', status);
          }),
        );
        final manager = MultiServerManager();
        addTearDown(manager.dispose);
        manager.debugRegisterClientForTesting(client, online: true);

        final bound = await manager.refreshTokensForProfile(
          _plexAccount('account-1', [
            PlexServer(
              name: 'Plex',
              clientIdentifier: 'server-1',
              accessToken: 'rejected-token',
              connections: const [],
              owned: true,
            ),
          ]),
          profileId: 'profile-b',
        );

        expect(bound, isEmpty);
        expect(manager.isServerOnline(ServerId('server-1')), isFalse);
        expect(status == 401 ? manager.authErrorServerIds : manager.accessDeniedServerIds, contains('server-1'));
        expect(status == 401 ? manager.accessDeniedServerIds : manager.authErrorServerIds, isEmpty);
        expect(client.config.token, 'old-token');
        expect(
          client.profileScopeId,
          buildPlexProfileScopeId(serverId: ServerId('server-1'), profileId: 'old-profile'),
        );
      });
    }

    test('required Plex probe rejects a different server identity without committing the candidate', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      PlexApiCache.initialize(db);
      addTearDown(db.close);

      final client = PlexClient.forTesting(
        config: PlexConfig(
          baseUrl: 'https://plex.example',
          token: 'old-token',
          clientIdentifier: 'client-id',
          product: 'Plezy',
          version: '1.0.0',
        ),
        serverId: ServerId('server-1'),
        profileScopeId: buildPlexProfileScopeId(serverId: ServerId('server-1'), profileId: 'old-profile'),
        serverName: 'Plex',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/');
          return http.Response(
            jsonEncode({
              'MediaContainer': {'machineIdentifier': 'different-server'},
            }),
            200,
            headers: const {'content-type': 'application/json'},
          );
        }),
      );
      final manager = MultiServerManager();
      addTearDown(manager.dispose);
      manager.debugRegisterClientForTesting(client, online: true);

      final bound = await manager.refreshTokensForProfile(
        _plexAccount('account-1', [
          PlexServer(
            name: 'Plex',
            clientIdentifier: 'server-1',
            accessToken: 'wrong-server-token',
            connections: const [],
            owned: true,
          ),
        ]),
        profileId: 'profile-b',
      );

      expect(bound, isEmpty);
      expect(manager.isServerOnline(ServerId('server-1')), isFalse);
      expect(client.config.token, 'old-token');
      expect(client.profileScopeId, buildPlexProfileScopeId(serverId: ServerId('server-1'), profileId: 'old-profile'));
    });

    test('concurrent Plex account refreshes do not invalidate each other', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      PlexApiCache.initialize(db);
      addTearDown(db.close);

      final manager = MultiServerManager();
      addTearDown(manager.dispose);

      PlexClient client(String serverId) => PlexClient.forTesting(
        config: PlexConfig(
          baseUrl: 'https://$serverId.example',
          token: 'old-$serverId',
          clientIdentifier: 'client-$serverId',
          product: 'Plezy',
          version: '1.0.0',
        ),
        serverId: ServerId(serverId),
        profileScopeId: buildPlexProfileScopeId(serverId: ServerId(serverId), profileId: 'profile-$serverId'),
        serverName: serverId,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'MediaContainer': {'machineIdentifier': serverId},
            }),
            200,
            headers: const {'content-type': 'application/json'},
          ),
        ),
      );

      final clientA = client('server-a');
      final clientB = client('server-b');
      manager.debugRegisterClientForTesting(clientA, online: true);
      manager.debugRegisterClientForTesting(clientB, online: true);

      PlexAccountConnection account(String accountId, String serverId) => PlexAccountConnection(
        id: accountId,
        accountToken: 'account-token',
        clientIdentifier: 'client-$serverId',
        accountLabel: accountId,
        servers: [
          PlexServer(
            name: serverId,
            clientIdentifier: serverId,
            accessToken: 'new-$serverId',
            connections: const [],
            owned: true,
          ),
        ],
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

      final results = await Future.wait([
        manager.refreshTokensForProfile(account('account-a', 'server-a'), profileId: 'profile-server-a'),
        manager.refreshTokensForProfile(account('account-b', 'server-b'), profileId: 'profile-server-b'),
      ]);

      expect(results, [
        {'server-a'},
        {'server-b'},
      ]);
      expect(clientA.config.token, 'new-server-a');
      expect(clientB.config.token, 'new-server-b');
    });

    test('fresh bind registers the scoped factory client and promotes a later endpoint', () async {
      final storage = await _prepareFreshPlexManagerTest();
      final first = _plexEndpoint('first');
      final promoted = _plexEndpoint('promoted');
      final discoveries = StreamController<PlexConnection>(sync: true);
      final server = _ControlledPlexServer(
        serverId: 'fresh-server',
        endpoints: [first, promoted],
        discoveryStreams: [() => discoveries.stream],
      );
      final factory = _RecordingPlexFactory();
      final manager = MultiServerManager(
        plexClientFactory: factory.create,
        connectivityChanges: () => const Stream.empty(),
      );
      addTearDown(manager.dispose);
      addTearDown(discoveries.close);
      final progress = <({String serverId, bool online})>[];
      final progressSub = manager.connectProgressStream.listen(progress.add);
      addTearDown(progressSub.cancel);

      final refresh = manager.refreshTokensForProfile(_plexAccount('fresh-account', [server]), profileId: 'profile-a');
      await pumpEventQueue();
      discoveries.add(first);
      final bound = await refresh;
      await pumpEventQueue();

      final expectedScope = buildPlexProfileScopeId(serverId: ServerId('fresh-server'), profileId: 'profile-a');
      final client = factory.clients['fresh-server']!;
      expect(bound, {'fresh-server'});
      expect(manager.getClient(ServerId('fresh-server')), same(client));
      expect(client.profileScopeId, expectedScope);
      expect(manager.isServerOnline(ServerId('fresh-server')), isTrue);
      expect(progress, contains((serverId: 'fresh-server', online: true)));
      expect(storage.getServerEndpoint(ServerId('fresh-server')), first.uri);

      final call = factory.calls.single;
      expect(call.serverId, ServerId('fresh-server'));
      expect(call.profileScopeId, expectedScope);
      expect(call.config.baseUrl, first.uri);
      expect(call.prioritizedEndpoints?.first, first.uri);
      expect(call.hasEndpointCallback, isTrue);
      expect(call.hasExhaustionCallback, isTrue);
      expect(call.seedTranscoderVideoSupport, isTrue);

      discoveries.add(promoted);
      await discoveries.close();
      await pumpEventQueue(times: 20);

      expect(client.config.baseUrl, promoted.uri);
      expect(storage.getServerEndpoint(ServerId('fresh-server')), promoted.uri);
    });

    test('fresh bind isolates a sibling factory failure and publishes both outcomes', () async {
      await _prepareFreshPlexManagerTest();
      final goodEndpoint = _plexEndpoint('good');
      final badEndpoint = _plexEndpoint('bad');
      final goodServer = _ControlledPlexServer(
        serverId: 'good-server',
        endpoints: [goodEndpoint],
        discoveryStreams: [() => Stream.value(goodEndpoint)],
      );
      final badServer = _ControlledPlexServer(
        serverId: 'bad-server',
        endpoints: [badEndpoint],
        discoveryStreams: [() => Stream.value(badEndpoint)],
      );
      final factory = _RecordingPlexFactory(failingServerIds: {'bad-server'});
      var connectivityFactoryCalls = 0;
      final manager = MultiServerManager(
        plexClientFactory: factory.create,
        connectivityChanges: () {
          connectivityFactoryCalls++;
          return const Stream.empty();
        },
      );
      addTearDown(manager.dispose);
      final progress = <({String serverId, bool online})>[];
      final statuses = <Map<String, bool>>[];
      final progressSub = manager.connectProgressStream.listen(progress.add);
      final statusSub = manager.statusStream.listen(statuses.add);
      addTearDown(progressSub.cancel);
      addTearDown(statusSub.cancel);

      final bound = await manager.refreshTokensForProfile(
        _plexAccount('mixed-account', [goodServer, badServer]),
        profileId: 'profile-a',
      );
      await pumpEventQueue();

      expect(bound, {'good-server'});
      expect(manager.getClient(ServerId('good-server')), same(factory.clients['good-server']));
      expect(manager.getClient(ServerId('bad-server')), isNull);
      expect(manager.isServerOnline(ServerId('good-server')), isTrue);
      expect(manager.isServerOnline(ServerId('bad-server')), isFalse);
      expect(progress, containsAll([(serverId: 'good-server', online: true), (serverId: 'bad-server', online: false)]));
      expect(statuses.last, {'good-server': true, 'bad-server': false});
      expect(connectivityFactoryCalls, 1);
    });

    test('late endpoint promotion cannot mutate persistence or a replacement after removal', () async {
      final storage = await _prepareFreshPlexManagerTest();
      final first = _plexEndpoint('stale-first');
      final late = _plexEndpoint('stale-late');
      final replacementEndpoint = _plexEndpoint('replacement');
      final discoveries = StreamController<PlexConnection>(sync: true);
      final server = _ControlledPlexServer(
        serverId: 'stale-server',
        endpoints: [first, late],
        discoveryStreams: [() => discoveries.stream],
      );
      final factory = _RecordingPlexFactory();
      final manager = MultiServerManager(
        plexClientFactory: factory.create,
        connectivityChanges: () => const Stream.empty(),
      );
      addTearDown(manager.dispose);
      addTearDown(discoveries.close);

      final refresh = manager.refreshTokensForProfile(_plexAccount('stale-account', [server]), profileId: 'profile-a');
      await pumpEventQueue();
      discoveries.add(first);
      expect(await refresh, {'stale-server'});
      expect(storage.getServerEndpoint(ServerId('stale-server')), first.uri);

      manager.removeServer(ServerId('stale-server'));
      final replacementScope = buildPlexProfileScopeId(serverId: ServerId('stale-server'), profileId: 'profile-b');
      final replacement = PlexClient.forTesting(
        config: PlexConfig(
          baseUrl: replacementEndpoint.uri,
          token: 'redacted',
          clientIdentifier: 'replacement-client',
          product: 'Plezy',
          version: '1.0.0',
        ),
        serverId: ServerId('stale-server'),
        profileScopeId: replacementScope,
        serverName: 'replacement',
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      manager.debugRegisterClientForTesting(replacement);

      discoveries.add(late);
      await discoveries.close();
      await pumpEventQueue(times: 20);

      expect(manager.getClient(ServerId('stale-server')), same(replacement));
      expect(replacement.config.baseUrl, replacementEndpoint.uri);
      expect(storage.getServerEndpoint(ServerId('stale-server')), first.uri);
    });

    test(
      'connectivity monitoring is lazy, singular, and coalesces every change, none included, for two seconds',
      () async {
        await _prepareFreshPlexManagerTest();
        final endpoint = _plexEndpoint('monitor');
        final connectivity = _DirectConnectivityStream();
        final server = _ControlledPlexServer(
          serverId: 'monitor-server',
          endpoints: [endpoint],
          discoveryStreams: [() => Stream.value(endpoint)],
        );
        final factory = _RecordingPlexFactory();
        final manager = MultiServerManager(plexClientFactory: factory.create, connectivityChanges: () => connectivity);
        addTearDown(manager.dispose);

        expect(connectivity.listenCount, 0);
        final bound = await manager.refreshTokensForProfile(
          _plexAccount('monitor-account', [server]),
          profileId: 'profile-a',
        );
        expect(bound, {'monitor-server'});
        expect(connectivity.listenCount, 1);
        expect(server.discoveryCalls, 1);

        final secondBound = await manager.refreshTokensForProfile(
          _plexAccount('monitor-account', [server]),
          profileId: 'profile-a',
        );
        expect(secondBound, {'monitor-server'});
        expect(connectivity.listenCount, 1);
        expect(factory.calls, hasLength(1));

        fakeAsync((async) {
          // Losing the network re-probes like any other change: it is how an
          // unreachable server gets marked offline (#2505). A burst of changes
          // still coalesces into one pass.
          connectivity.add([ConnectivityResult.none]);
          connectivity.add([ConnectivityResult.wifi]);
          connectivity.add([ConnectivityResult.mobile]);
          async.flushMicrotasks();
          async.elapse(const Duration(milliseconds: 1999));
          async.flushMicrotasks();
          expect(server.discoveryCalls, 1);
          expect(factory.requests['monitor-server']!.map((request) => request.url.path), ['/', '/media/providers']);
          async.elapse(const Duration(milliseconds: 1));
          async.flushMicrotasks();

          expect(server.discoveryCalls, 2);
          expect(factory.requests['monitor-server']!.map((request) => request.url.path), [
            '/',
            '/media/providers',
            '/',
          ]);

          connectivity.add([ConnectivityResult.none]);
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 2));
          async.flushMicrotasks();

          expect(server.discoveryCalls, 3);
          expect(factory.requests['monitor-server']!.map((request) => request.url.path), [
            '/',
            '/media/providers',
            '/',
            '/',
          ]);
          expect(connectivity.cancelCount, 0);
        });

        manager.dispose();
        expect(connectivity.cancelCount, 1);
      },
    );

    test('losing the network keeps a reachable server online and drops an unreachable one (#2505)', () async {
      var remoteReachable = true;
      PlexClient plexClient(String serverId, bool Function() reachable) => testPlexClient(
        serverId: ServerId(serverId),
        handler: (_) async {
          if (!reachable()) throw const SocketException('Connection refused');
          return http.Response('{}', 200, headers: {'content-type': 'application/json'});
        },
      );
      final loopback = plexClient('plex-loopback', () => true);
      final remote = plexClient('plex-remote', () => remoteReachable);
      addTearDown(loopback.close);
      addTearDown(remote.close);
      final connectivity = _DirectConnectivityStream();
      final manager = MultiServerManager(
        connectivityChanges: () => connectivity,
        connectivityDebounceDuration: Duration.zero,
      );
      addTearDown(manager.dispose);

      manager.debugRegisterClientForTesting(loopback, online: false);
      manager.debugRegisterClientForTesting(remote, online: false);
      await manager.checkServerHealth();
      expect(manager.isServerOnline(ServerId('plex-loopback')), isTrue);
      expect(manager.isServerOnline(ServerId('plex-remote')), isTrue);
      expect(connectivity.listenCount, 1);

      // The adapter goes down: the remote server loses its route, the
      // loopback one does not, and connectivity_plus reports `none`.
      remoteReachable = false;
      final remoteDropped = manager.statusStream.firstWhere((status) => status['plex-remote'] == false);
      connectivity.add(const [ConnectivityResult.none]);
      await remoteDropped.timeout(const Duration(seconds: 5));

      expect(manager.isServerOnline(ServerId('plex-remote')), isFalse);
      expect(manager.isServerOnline(ServerId('plex-loopback')), isTrue);
    });

    test('a server recovered by a health probe is re-probed when the network drops (#2505)', () async {
      var reachable = true;
      final client = testPlexClient(
        serverId: ServerId('plex-server'),
        handler: (_) async {
          if (!reachable) throw const SocketException('Connection refused');
          return http.Response('{}', 200, headers: {'content-type': 'application/json'});
        },
      );
      addTearDown(client.close);
      final connectivity = _DirectConnectivityStream();
      final manager = MultiServerManager(
        connectivityChanges: () => connectivity,
        connectivityDebounceDuration: Duration.zero,
      );
      addTearDown(manager.dispose);

      // The session started with the server unreachable, so no bind brought
      // it online; the Reconnect / resume health probe does.
      manager.debugRegisterClientForTesting(client, online: false);
      await manager.checkServerHealth();
      expect(manager.isServerOnline(ServerId('plex-server')), isTrue);

      reachable = false;
      final dropped = manager.statusStream.firstWhere((status) => status['plex-server'] == false);
      connectivity.add(const [ConnectivityResult.none]);
      await dropped.timeout(const Duration(seconds: 5));

      expect(manager.isServerOnline(ServerId('plex-server')), isFalse);
    });

    test('a Plex client that connects after the timeout is closed instead of leaked', () async {
      await _prepareFreshPlexManagerTest();
      final endpoint = _plexEndpoint('late');
      final server = _ControlledPlexServer(
        serverId: 'late-server',
        endpoints: [endpoint],
        discoveryStreams: [() => Stream.value(endpoint)],
      );
      final release = Completer<void>();
      final transport = _CloseRecordingHttpClient();
      PlexClient? lateClient;
      final manager = MultiServerManager(
        connectivityChanges: () => const Stream.empty(),
        plexClientFactory:
            (
              config, {
              required serverId,
              required profileScopeId,
              serverName,
              prioritizedEndpoints,
              onEndpointChanged,
              onAllEndpointsExhausted,
              seedTranscoderVideoSupport,
            }) async {
              await release.future;
              return lateClient = PlexClient.forTesting(
                config: config,
                serverId: serverId,
                profileScopeId: profileScopeId,
                httpClient: transport,
              );
            },
      );
      addTearDown(manager.dispose);

      final bound = await manager.refreshTokensForProfile(
        _plexAccount('late-account', [server]),
        profileId: 'profile-a',
        timeout: const Duration(milliseconds: 10),
      );
      expect(bound, isEmpty);
      expect(manager.isServerOnline(ServerId('late-server')), isFalse);

      release.complete();
      await pumpEventQueue(times: 20);

      expect(lateClient, isNotNull);
      expect(manager.getClient(ServerId('late-server')), isNull);
      expect(transport.closed, isTrue);
    });

    test('an offline client of another profile is dropped when this profile cannot connect', () async {
      await _prepareFreshPlexManagerTest();
      final server = _ControlledPlexServer(
        serverId: 'server-1',
        endpoints: [_plexEndpoint('down')],
        discoveryStreams: [],
      );
      final transport = _CloseRecordingHttpClient();
      final previous = testPlexClient(
        serverId: ServerId('server-1'),
        profileScopeId: buildPlexProfileScopeId(serverId: ServerId('server-1'), profileId: 'profile-a'),
        httpClient: transport,
      );
      final manager = MultiServerManager(connectivityChanges: () => const Stream.empty());
      addTearDown(manager.dispose);
      manager.debugRegisterClientForTesting(previous, online: false);

      final bound = await manager.refreshTokensForProfile(_plexAccount('account', [server]), profileId: 'profile-b');
      await pumpEventQueue();

      expect(bound, isEmpty);
      expect(manager.getClient(ServerId('server-1')), isNull);
      expect(transport.closed, isTrue);
      // Still registered — for profile B, so a reconnect retries it with B's token.
      expect(manager.registeredServerIds, ['server-1']);
      expect(manager.isRegisteredForOtherProfile(ServerId('server-1'), profileId: 'profile-b'), isFalse);
      expect(manager.isRegisteredForOtherProfile(ServerId('server-1'), profileId: 'profile-a'), isTrue);
    });

    test('dispose cancels a pending connectivity debounce with no later mutation', () async {
      final storage = await _prepareFreshPlexManagerTest();
      final endpoint = _plexEndpoint('pending');
      final connectivity = _DirectConnectivityStream();
      final server = _ControlledPlexServer(
        serverId: 'pending-server',
        endpoints: [endpoint],
        discoveryStreams: [() => Stream.value(endpoint)],
      );
      final factory = _RecordingPlexFactory();
      final manager = MultiServerManager(plexClientFactory: factory.create, connectivityChanges: () => connectivity);
      expect(await manager.refreshTokensForProfile(_plexAccount('pending-account', [server]), profileId: 'profile-a'), {
        'pending-server',
      });

      fakeAsync((async) {
        connectivity.add([ConnectivityResult.wifi]);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        manager.dispose();
        async.flushMicrotasks();
        final callsAfterDispose = server.discoveryCalls;
        final persistedAfterDispose = storage.getServerEndpoint(ServerId('pending-server'));
        final requestCountAfterDispose = factory.requests['pending-server']!.length;

        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();

        expect(connectivity.cancelCount, 1);
        expect(server.discoveryCalls, callsAfterDispose);
        expect(factory.requests['pending-server'], hasLength(requestCountAfterDispose));
        expect(storage.getServerEndpoint(ServerId('pending-server')), persistedAfterDispose);
        expect(manager.serverIds, isEmpty);
        expect(manager.onlineServerIds, isEmpty);
      });
    });
  });

  group('checkServerHealth', () {
    test('a probe result from a client replaced mid-probe is not applied', () async {
      final probeStarted = Completer<void>();
      final original = testPlexClient(
        serverId: ServerId('server-1'),
        handler: (_) async {
          if (!probeStarted.isCompleted) probeStarted.complete();
          await Completer<void>().future;
          throw StateError('unreachable');
        },
      );
      final replacement = testPlexClient(serverId: ServerId('server-1'));
      final manager = MultiServerManager();
      addTearDown(manager.dispose);
      manager.debugRegisterClientForTesting(original);

      final health = manager.checkServerHealth();
      await probeStarted.future;
      // A profile switch: the old client is removed (aborting its probe) and
      // the new profile's client is bound under the same server id.
      manager.removeServer(ServerId('server-1'));
      manager.debugRegisterClientForTesting(replacement);
      await health;

      expect(manager.getClient(ServerId('server-1')), same(replacement));
      expect(manager.isServerOnline(ServerId('server-1')), isTrue);
    });
  });

  group('relay endpoint handling', () {
    test('a relay phase-1 winner is never persisted; a later direct promotion is', () async {
      final storage = await _prepareFreshPlexManagerTest();
      final direct = _plexEndpoint('direct');
      final relay = _plexRelayEndpoint('relay');
      final discoveries = StreamController<PlexConnection>(sync: true);
      final server = _ControlledPlexServer(
        serverId: 'relay-server',
        endpoints: [direct, relay],
        discoveryStreams: [() => discoveries.stream],
      );
      final factory = _RecordingPlexFactory();
      final manager = MultiServerManager(
        plexClientFactory: factory.create,
        connectivityChanges: () => const Stream.empty(),
      );
      addTearDown(manager.dispose);
      addTearDown(discoveries.close);

      final refresh = manager.refreshTokensForProfile(_plexAccount('relay-account', [server]), profileId: 'profile-a');
      await pumpEventQueue();
      discoveries.add(relay);
      expect(await refresh, {'relay-server'});
      await pumpEventQueue();

      final client = factory.clients['relay-server']!;
      expect(client.config.baseUrl, relay.uri);
      expect(client.plexAccountId, 'relay-account');
      expect(storage.getServerEndpoint(ServerId('relay-server')), isNull);
      expect(manager.debugHasPendingRelayEscapeForTesting(ServerId('relay-server')), isTrue);

      discoveries.add(direct);
      await discoveries.close();
      await pumpEventQueue(times: 20);

      expect(client.config.baseUrl, direct.uri);
      expect(storage.getServerEndpoint(ServerId('relay-server')), direct.uri);
      expect(manager.debugHasPendingRelayEscapeForTesting(ServerId('relay-server')), isFalse);
    });

    test('failover onto a relay endpoint never overwrites the preferred endpoint', () async {
      final storage = await _prepareFreshPlexManagerTest();
      final direct = _plexEndpoint('failover-direct');
      final relay = _plexRelayEndpoint('failover-relay');
      final server = _ControlledPlexServer(
        serverId: 'failover-server',
        endpoints: [direct, relay],
        discoveryStreams: [() => Stream.value(direct)],
      );
      final factory = _RecordingPlexFactory();
      final manager = MultiServerManager(
        plexClientFactory: factory.create,
        connectivityChanges: () => const Stream.empty(),
      );
      addTearDown(manager.dispose);

      expect(
        await manager.refreshTokensForProfile(_plexAccount('failover-account', [server]), profileId: 'profile-a'),
        {'failover-server'},
      );
      await pumpEventQueue(times: 20);
      expect(storage.getServerEndpoint(ServerId('failover-server')), direct.uri);

      // Mid-session failover walks onto the relay candidate: the client may
      // use it, but it must not become the next bind's head-start endpoint.
      final onEndpointChanged = factory.calls.single.endpointChanged!;
      await onEndpointChanged(relay.uri);
      expect(storage.getServerEndpoint(ServerId('failover-server')), direct.uri);

      // Reverse rotation (PR #1974 review): a profile refresh rotates the
      // relay URI away, then the old relay URL reports a late failover
      // switch. The live server no longer lists it — the custom-hostname
      // fallback alone would classify it as remote — but the connect-time
      // capture still recognizes it as relay.
      final rotated = _ControlledPlexServer(
        serverId: 'failover-server',
        endpoints: [direct, _plexRelayEndpoint('rotated-relay')],
        discoveryStreams: [() => Stream.value(direct)],
      );
      expect(
        await manager.refreshTokensForProfile(_plexAccount('failover-account', [rotated]), profileId: 'profile-a'),
        {'failover-server'},
      );
      await onEndpointChanged(relay.uri);
      expect(storage.getServerEndpoint(ServerId('failover-server')), direct.uri);
    });

    test('a relay session re-probes on backoff and promotes a returning direct endpoint', () async {
      final storage = await _prepareFreshPlexManagerTest();
      final direct = _plexEndpoint('escape-direct');
      final relay = _plexRelayEndpoint('escape-relay');
      final server = _ControlledPlexServer(
        serverId: 'escape-server',
        endpoints: [direct, relay],
        discoveryStreams: [
          () => Stream.value(relay), // bind: only relay answers
          () => Stream.value(relay), // first escape probe: still relay-only
          () => Stream.value(direct), // second escape probe: direct is back
        ],
      );
      final factory = _RecordingPlexFactory();
      final manager = MultiServerManager(
        plexClientFactory: factory.create,
        connectivityChanges: () => const Stream.empty(),
      );
      addTearDown(manager.dispose);

      expect(await manager.refreshTokensForProfile(_plexAccount('escape-account', [server]), profileId: 'profile-a'), {
        'escape-server',
      });
      await pumpEventQueue(times: 20);
      final client = factory.clients['escape-server']!;
      expect(client.config.baseUrl, relay.uri);
      expect(server.discoveryCalls, 1);
      expect(manager.debugHasPendingRelayEscapeForTesting(ServerId('escape-server')), isTrue);

      fakeAsync((async) {
        // Fire the bind-scheduled probe (its real timer lives outside this zone).
        unawaited(manager.debugFireRelayEscapeForTesting(ServerId('escape-server')));
        async.flushMicrotasks();
        expect(server.discoveryCalls, 2);
        expect(client.config.baseUrl, relay.uri);

        // Still relay-only: rescheduled with a doubled backoff (30s -> 60s).
        async.elapse(const Duration(seconds: 60) - const Duration(milliseconds: 1));
        async.flushMicrotasks();
        expect(server.discoveryCalls, 2);
        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();

        expect(server.discoveryCalls, 3);
        expect(client.config.baseUrl, direct.uri);
        expect(storage.getServerEndpoint(ServerId('escape-server')), direct.uri);
        expect(manager.debugHasPendingRelayEscapeForTesting(ServerId('escape-server')), isFalse);

        // Off relay: the prober stays stopped.
        async.elapse(const Duration(minutes: 10));
        async.flushMicrotasks();
        expect(server.discoveryCalls, 3);
      });
    });

    test('removing a relay-connected server cancels its escape prober', () async {
      await _prepareFreshPlexManagerTest();
      final relay = _plexRelayEndpoint('removed-relay');
      final server = _ControlledPlexServer(
        serverId: 'removed-server',
        endpoints: [_plexEndpoint('removed-direct'), relay],
        discoveryStreams: [() => Stream.value(relay)],
      );
      final factory = _RecordingPlexFactory();
      final manager = MultiServerManager(
        plexClientFactory: factory.create,
        connectivityChanges: () => const Stream.empty(),
      );
      addTearDown(manager.dispose);

      expect(await manager.refreshTokensForProfile(_plexAccount('removed-account', [server]), profileId: 'profile-a'), {
        'removed-server',
      });
      await pumpEventQueue(times: 20);
      expect(manager.debugHasPendingRelayEscapeForTesting(ServerId('removed-server')), isTrue);

      manager.removeServer(ServerId('removed-server'));
      expect(manager.debugHasPendingRelayEscapeForTesting(ServerId('removed-server')), isFalse);
      expect(server.discoveryCalls, 1);
    });
  });

  group('reoptimizeDemotedServers', () {
    test('re-races a server sitting on remote while it publishes a local connection', () async {
      final storage = await _prepareFreshPlexManagerTest();
      final local = _plexEndpoint('demoted-local');
      final remote = _plexRemoteEndpoint('demoted-remote');
      final server = _ControlledPlexServer(
        serverId: 'demoted-server',
        endpoints: [local, remote],
        discoveryStreams: [
          () => Stream.value(remote), // bind: LAN was unreachable
          () => Stream.value(local), // resume: LAN is back
        ],
      );
      final factory = _RecordingPlexFactory();
      final manager = MultiServerManager(
        plexClientFactory: factory.create,
        connectivityChanges: () => const Stream.empty(),
      );
      addTearDown(manager.dispose);

      expect(await manager.refreshTokensForProfile(_plexAccount('demoted-account', [server]), profileId: 'profile-a'), {
        'demoted-server',
      });
      await pumpEventQueue(times: 20);
      final client = factory.clients['demoted-server']!;
      expect(client.config.baseUrl, remote.uri);
      expect(storage.getServerEndpoint(ServerId('demoted-server')), remote.uri);
      expect(server.discoveryCalls, 1);

      await manager.reoptimizeDemotedServers(reason: 'resume');
      await pumpEventQueue(times: 20);

      expect(server.discoveryCalls, 2);
      expect(client.config.baseUrl, local.uri);
      expect(storage.getServerEndpoint(ServerId('demoted-server')), local.uri);

      // Back on local: a second resume is a no-op.
      await manager.reoptimizeDemotedServers(reason: 'resume');
      expect(server.discoveryCalls, 2);
    });

    test('leaves alone a server on local and a remote-only server', () async {
      await _prepareFreshPlexManagerTest();
      final onLocal = _ControlledPlexServer(
        serverId: 'on-local',
        endpoints: [_plexEndpoint('on-local-lan'), _plexRemoteEndpoint('on-local-wan')],
        discoveryStreams: [() => Stream.value(_plexEndpoint('on-local-lan'))],
      );
      final remoteOnly = _ControlledPlexServer(
        serverId: 'remote-only',
        endpoints: [_plexRemoteEndpoint('remote-only-wan')],
        discoveryStreams: [() => Stream.value(_plexRemoteEndpoint('remote-only-wan'))],
      );
      final factory = _RecordingPlexFactory();
      final manager = MultiServerManager(
        plexClientFactory: factory.create,
        connectivityChanges: () => const Stream.empty(),
      );
      addTearDown(manager.dispose);

      expect(
        await manager.refreshTokensForProfile(_plexAccount('mixed-account', [onLocal, remoteOnly]), profileId: 'p'),
        {'on-local', 'remote-only'},
      );
      await pumpEventQueue(times: 20);

      await manager.reoptimizeDemotedServers(reason: 'resume');

      expect(onLocal.discoveryCalls, 1);
      expect(remoteOnly.discoveryCalls, 1);
    });

    test('skips offline servers — the reconnect path owns those', () async {
      await _prepareFreshPlexManagerTest();
      final local = _plexEndpoint('offline-lan');
      final remote = _plexRemoteEndpoint('offline-wan');
      final server = _ControlledPlexServer(
        serverId: 'offline-server',
        endpoints: [local, remote],
        discoveryStreams: [() => Stream.value(remote)],
      );
      final factory = _RecordingPlexFactory();
      final manager = MultiServerManager(
        plexClientFactory: factory.create,
        connectivityChanges: () => const Stream.empty(),
      );
      addTearDown(manager.dispose);

      expect(await manager.refreshTokensForProfile(_plexAccount('offline-account', [server]), profileId: 'p'), {
        'offline-server',
      });
      await pumpEventQueue(times: 20);
      manager.updateServerStatus(ServerId('offline-server'), false);

      await manager.reoptimizeDemotedServers(reason: 'resume');

      expect(server.discoveryCalls, 1);
    });
  });

  group('removeServer', () {
    test('removes a tracked server\'s status entry and emits a snapshot', () async {
      final m = MultiServerManager();
      addTearDown(m.dispose);

      m.updateServerStatus(ServerId('srv-1'), true);
      m.updateServerStatus(ServerId('srv-2'), true);

      final emitted = <Map<String, bool>>[];
      final sub = m.statusStream.listen(emitted.add);
      addTearDown(sub.cancel);

      m.removeServer(ServerId('srv-1'));
      await Future<void>.delayed(Duration.zero);

      expect(m.serverIds, isNot(contains('srv-1')));
      expect(emitted, isNotEmpty);
      expect(emitted.last, {'srv-2': true});
    });

    test('removing an unknown id still emits a snapshot (does not throw)', () async {
      final m = MultiServerManager();
      addTearDown(m.dispose);

      final emitted = <Map<String, bool>>[];
      final sub = m.statusStream.listen(emitted.add);
      addTearDown(sub.cancel);

      m.removeServer(ServerId('never-added'));
      await Future<void>.delayed(Duration.zero);

      // Doesn't throw; state stays empty; one snapshot fires.
      expect(m.serverIds, isEmpty);
      expect(emitted, hasLength(1));
      expect(emitted.first, isEmpty);
    });
  });

  group('disconnectAll', () {
    test('clears all status and emits an empty snapshot', () async {
      final m = MultiServerManager();
      addTearDown(m.dispose);

      m.updateServerStatus(ServerId('a'), true);
      m.updateServerStatus(ServerId('b'), false);

      final emitted = <Map<String, bool>>[];
      final sub = m.statusStream.listen(emitted.add);
      addTearDown(sub.cancel);

      m.disconnectAll();
      await Future<void>.delayed(Duration.zero);

      expect(m.serverIds, isEmpty);
      expect(m.onlineServerIds, isEmpty);
      expect(m.offlineServerIds, isEmpty);
      expect(emitted.last, isEmpty);
    });
  });

  group('shutdown', () {
    test('clears all state without emitting a snapshot and closes the stream', () async {
      final m = MultiServerManager();
      addTearDown(m.dispose);

      m.updateServerStatus(ServerId('a'), true);
      m.updateServerStatus(ServerId('b'), false);

      final emitted = <Map<String, bool>>[];
      var done = false;
      final sub = m.statusStream.listen(emitted.add, onDone: () => done = true);
      addTearDown(sub.cancel);

      await m.shutdown();
      await Future<void>.delayed(Duration.zero);

      // Exit teardown must stay invisible: an empty snapshot would flip the
      // still-mounted UI into offline mode while the app shuts down.
      expect(m.serverIds, isEmpty);
      expect(m.onlineServerIds, isEmpty);
      expect(m.offlineServerIds, isEmpty);
      expect(emitted, isEmpty);
      expect(done, isTrue);
    });

    test('a health result landing after shutdown is a silent no-op', () async {
      final m = MultiServerManager();
      addTearDown(m.dispose);

      m.updateServerStatus(ServerId('a'), true);
      await m.shutdown();

      // A probe that was in flight when the exit began must not throw into
      // the closed status controller.
      expect(() => m.updateServerStatus(ServerId('a'), false), returnsNormally);
    });
  });

  group('dispose', () {
    test('dispose closes the status stream (existing subscribers get onDone)', () async {
      final m = MultiServerManager();
      var done = false;
      final sub = m.statusStream.listen((_) {}, onDone: () => done = true);
      m.dispose();
      // Allow the close event to propagate.
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
      await sub.cancel();
    });
  });
}

PlexConnection _plexEndpoint(String label) => PlexConnection(
  protocol: 'https',
  address: '$label.invalid',
  port: 32400,
  uri: 'https://$label.invalid:32400',
  local: true,
  relay: false,
  ipv6: false,
);

/// Mirrors a plex.tv relay connection: remote, `relay: true`.
PlexConnection _plexRelayEndpoint(String label) => PlexConnection(
  protocol: 'https',
  address: '$label.invalid',
  port: 8443,
  uri: 'https://$label.invalid:8443',
  local: false,
  relay: true,
  ipv6: false,
);

/// A plex.tv-published WAN connection: `local: false`, direct (not relay).
PlexConnection _plexRemoteEndpoint(String label) => PlexConnection(
  protocol: 'https',
  address: '$label.invalid',
  port: 32400,
  uri: 'https://$label.invalid:32400',
  local: false,
  relay: false,
  ipv6: false,
);

class _ControlledPlexServer extends PlexServer {
  _ControlledPlexServer({
    required String serverId,
    required List<PlexConnection> endpoints,
    required this.discoveryStreams,
  }) : super(name: serverId, clientIdentifier: serverId, accessToken: 'redacted', connections: endpoints, owned: true);

  final List<Stream<PlexConnection> Function()> discoveryStreams;
  int discoveryCalls = 0;

  @override
  Stream<PlexConnection> findBestWorkingConnection({
    String? preferredUri,
    String? clientIdentifier,
    void Function(bool)? onTranscoderCapability,
  }) {
    onTranscoderCapability?.call(true);
    final index = discoveryCalls++;
    if (discoveryStreams.isEmpty) return const Stream.empty();
    return discoveryStreams[index.clamp(0, discoveryStreams.length - 1)]();
  }
}

class _PlexFactoryCall {
  const _PlexFactoryCall({
    required this.config,
    required this.serverId,
    required this.profileScopeId,
    required this.prioritizedEndpoints,
    required this.endpointChanged,
    required this.hasExhaustionCallback,
    required this.seedTranscoderVideoSupport,
  });

  final PlexConfig config;
  final ServerId serverId;
  final PlexProfileScopeId profileScopeId;
  final List<String>? prioritizedEndpoints;
  final Future<void> Function(String newBaseUrl)? endpointChanged;
  final bool hasExhaustionCallback;
  final bool? seedTranscoderVideoSupport;

  bool get hasEndpointCallback => endpointChanged != null;
}

class _RecordingPlexFactory {
  _RecordingPlexFactory({this.failingServerIds = const {}});

  final Set<String> failingServerIds;
  final calls = <_PlexFactoryCall>[];
  final clients = <String, PlexClient>{};
  final requests = <String, List<http.Request>>{};

  Future<PlexClient> create(
    PlexConfig config, {
    required ServerId serverId,
    required PlexProfileScopeId profileScopeId,
    String? serverName,
    List<String>? prioritizedEndpoints,
    Future<void> Function(String newBaseUrl)? onEndpointChanged,
    void Function()? onAllEndpointsExhausted,
    bool? seedTranscoderVideoSupport,
  }) async {
    calls.add(
      _PlexFactoryCall(
        config: config,
        serverId: serverId,
        profileScopeId: profileScopeId,
        prioritizedEndpoints: prioritizedEndpoints,
        endpointChanged: onEndpointChanged,
        hasExhaustionCallback: onAllEndpointsExhausted != null,
        seedTranscoderVideoSupport: seedTranscoderVideoSupport,
      ),
    );
    if (failingServerIds.contains(serverId)) {
      throw StateError('injected client creation failure');
    }
    final serverRequests = requests.putIfAbsent(serverId, () => []);
    final client = PlexClient.forTesting(
      config: config,
      serverId: serverId,
      profileScopeId: profileScopeId,
      serverName: serverName,
      prioritizedEndpoints: prioritizedEndpoints,
      httpClient: MockClient((request) async {
        serverRequests.add(request);
        final body = request.url.path == '/'
            ? {
                'MediaContainer': {'machineIdentifier': serverId},
              }
            : <String, dynamic>{};
        return http.Response(jsonEncode(body), 200, headers: const {'content-type': 'application/json'});
      }),
    );
    clients[serverId] = client;
    return client;
  }
}

PlexAccountConnection _plexAccount(String accountId, List<PlexServer> servers) => PlexAccountConnection(
  id: accountId,
  accountToken: 'redacted',
  clientIdentifier: 'test-client',
  accountLabel: accountId,
  servers: servers,
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
);

Future<StorageService> _prepareFreshPlexManagerTest() async {
  PackageInfo.setMockInitialValues(
    appName: 'Plezy',
    packageName: 'com.example.plezy',
    version: '1.0.0',
    buildNumber: '1',
    buildSignature: '',
  );
  DeviceIdentityService.debugOverride(const DeviceIdentity(platform: 'Test'));
  addTearDown(() => DeviceIdentityService.debugOverride(null));
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  PlexApiCache.initialize(db);
  addTearDown(db.close);
  return StorageService.getInstance();
}

class _DirectConnectivityStream extends Stream<List<ConnectivityResult>> {
  void Function(List<ConnectivityResult>)? _onData;
  int listenCount = 0;
  int cancelCount = 0;

  void add(List<ConnectivityResult> value) => _onData?.call(value);

  @override
  StreamSubscription<List<ConnectivityResult>> listen(
    void Function(List<ConnectivityResult> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    listenCount++;
    _onData = onData;
    return _TrackedStreamSubscription<List<ConnectivityResult>>(
      const Stream<List<ConnectivityResult>>.empty().listen(null),
      () {
        cancelCount++;
        _onData = null;
      },
    );
  }
}

class _TrackedStreamSubscription<T> implements StreamSubscription<T> {
  _TrackedStreamSubscription(this._delegate, this._onCancel);

  final StreamSubscription<T> _delegate;
  final void Function() _onCancel;
  bool _cancelled = false;

  @override
  Future<void> cancel() {
    if (!_cancelled) {
      _cancelled = true;
      _onCancel();
    }
    return _delegate.cancel();
  }

  @override
  void onData(void Function(T data)? handleData) => _delegate.onData(handleData);

  @override
  void onError(Function? handleError) => _delegate.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => _delegate.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => _delegate.pause(resumeSignal);

  @override
  void resume() => _delegate.resume();

  @override
  bool get isPaused => _delegate.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => _delegate.asFuture(futureValue);
}

class _CloseRecordingHttpClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);

  @override
  void close() => closed = true;
}
