import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/services/silo_client.dart';

import '../test_helpers/fake_silo_server.dart';

final _connection = SiloConnection(
  origin: 'https://silo.ruleone.xyz',
  serverId: 'server-1',
  serverName: 'Silo',
  username: 'alice',
  createdAt: DateTime.fromMillisecondsSinceEpoch(1_000_000),
);

void main() {
  test('the cache scope is silo:<server_id>/<profile_id>', () async {
    final (session, _) = await signedInSession();
    final client = SiloClient(
      connection: _connection,
      profileId: 'p-2',
      http: siloHttpForServer(FakeSiloServer(), session),
    );

    expect(client.cacheServerId, 'silo:server-1/p-2');
    expect('${client.serverId}', 'server-1');
  });

  test('health reads account/me with the bearer', () async {
    final (session, _) = await signedInSession();
    final server = FakeSiloServer();
    final client = SiloClient(connection: _connection, profileId: 'p-1', http: siloHttpForServer(server, session));

    expect(await client.checkHealth(), HealthStatus.online);
    expect(server.to('/api/v2/account/me').single.header('authorization'), 'Bearer access-A');
  });

  test('sign-out wipes the slot even when logout fails (AuthRepository.kt:266-272)', () async {
    final (session, _) = await signedInSession();
    final down = FakeSilo((_) => jsonResponse({}, 503));

    await signOutSiloSession(siloHttpFor(down, session));

    expect(down.requests.single.url.path, '/api/v2/auth/logout');
    expect(down.requests.single.header('authorization'), 'Bearer access-A');
    expect(session.session, isNull);
  });
}
