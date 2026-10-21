import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:plezy/database/app_database.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/plex_api_cache.dart';
import 'package:plezy/services/plex_client.dart';

import '../test_helpers/backend_client_fixtures.dart';
import '../test_helpers/http_fixtures.dart';
import '../test_helpers/multi_server_fixtures.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
  });

  tearDown(() => db.close());

  PlexClient plexClient(http.Client httpClient) => testPlexClient(
    config: testPlexConfig(token: 'plex-token', clientIdentifier: 'plex-device', machineIdentifier: 'plex-machine'),
    serverId: ServerId('plex-machine'),
    httpClient: httpClient,
  );

  test('Plex exposes one centralized Live TV DVR adapter', () async {
    final requests = <Uri>[];
    final client = plexClient(
      MockClient((request) async {
        requests.add(request.url);
        return jsonResponse({
          'MediaContainer': {
            'Dvr': [
              {'key': 'dvr-1', 'uuid': 'dvr-1'},
            ],
          },
        });
      }),
    );
    addTearDown(client.close);

    expect(client.capabilities.liveTvDvr, isTrue);
    expect(client.liveTv.dvr, same(client));
    expect(client.liveTvDvr, same(client));
    expect((await client.liveTvDvr!.fetchDvrs()).single.key, 'dvr-1');
    expect(requests.single.path, '/livetv/dvrs');
  });

  test('availability call site lists the Plex DVR', () async {
    final plexRequests = <Uri>[];
    final plex = plexClient(
      MockClient((request) async {
        plexRequests.add(request.url);
        if (request.url.path != '/livetv/dvrs') fail('Unexpected Plex request: ${request.url}');
        return jsonResponse({
          'MediaContainer': {
            'Dvr': [
              {'key': 'dvr-1', 'uuid': 'dvr-1'},
            ],
          },
        });
      }),
    );
    final manager = MultiServerManager();
    manager.debugRegisterClientForTesting(plex);
    final provider = testMultiServerProvider(manager);
    addTearDown(() {
      provider.dispose();
      manager.dispose();
    });

    await provider.checkLiveTvAvailability();

    expect(plexRequests.map((uri) => uri.path), ['/livetv/dvrs']);
    expect(
      provider.liveTvServers.map((server) => (server.serverId, server.dvrKey)),
      contains(('plex-machine', 'dvr-1')),
    );
  });
}
