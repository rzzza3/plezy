import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/silo/silo_profiles.dart';
import 'package:plezy/silo/silo_server_probe.dart';
import 'package:plezy/silo/silo_session.dart';

import '../test_helpers/fake_silo_server.dart';

Future<(SiloProfiles, SiloSessionController, FakeSiloServer)> _signedIn(FakeSiloServer server) async {
  final (session, _) = await signedInSession();
  return (SiloProfiles(siloHttpForServer(server, session)), session, server);
}

void main() {
  group('profile picker, TvProfileSelectionViewModel.kt:125-393', () {
    test('load reads the account, then the profiles', () async {
      final (profiles, _, server) = await _signedIn(FakeSiloServer());

      final household = (await profiles.load())!;

      expect(household.account.username, 'alice');
      expect(household.account.isAdmin, true);
      expect(household.profiles.map((p) => (p.id, p.name, p.hasPin)), [('p-1', 'Alice', false), ('p-2', 'Kids', true)]);
      expect(server.requests.map((r) => r.url.path), ['/api/v2/account/me', '/api/v2/profiles']);
    });

    test('a 200 with valid: false does not enter the profile (ProfileModels.kt:124-125)', () async {
      final (profiles, session, _) = await _signedIn(FakeSiloServer());
      final kids = const SiloProfile(id: 'p-2', name: 'Kids', hasPin: true);

      final result = await profiles.enter(kids, pin: '0000');

      expect(result, isA<SiloPinRejected>());
      expect(session.session!.profileId, isNull);
      expect(session.generation, 1, reason: 'a wrong PIN changes no identity');
    });

    test('a valid response with a blank token does not enter the profile', () async {
      final (session, _) = await signedInSession();
      final blank = FakeSilo((_) => jsonResponse({'valid': true, 'profile_token': '  '}, 200));
      final profiles = SiloProfiles(siloHttpFor(blank, session));

      final result = await profiles.enter(
        const SiloProfile(id: 'p-2', name: 'Kids', hasPin: true),
        pin: '1234',
      );

      expect(result, isA<SiloPinRejected>());
      expect(session.session!.profileId, isNull);
    });

    test(
      'verify-pin goes without profile headers; later calls carry the new id and token (ProfileApi.kt:116-129)',
      () async {
        final (profiles, session, server) = await _signedIn(FakeSiloServer());
        await session.selectProfile('p-1', 'stale-token');

        final result = await profiles.enter(
          const SiloProfile(id: 'p-2', name: 'Kids', hasPin: true),
          pin: '1234',
        );
        await profiles.load();

        expect(result, isA<SiloProfileEntered>());
        final verify = server.to('/api/v2/profiles/p-2/verify-pin').single;
        expect(verify.header('authorization'), 'Bearer access-A');
        expect(verify.header('x-profile-id'), isNull);
        expect(verify.header('x-profile-token'), isNull);
        final list = server.to('/api/v2/profiles').single;
        expect(list.header('x-profile-id'), 'p-2');
        expect(list.header('x-profile-token'), 'profile-token-p-2');
      },
    );

    test('a profile without a PIN is entered without verify-pin', () async {
      final (profiles, session, server) = await _signedIn(FakeSiloServer());

      final result = await profiles.enter(const SiloProfile(id: 'p-1', name: 'Alice'));

      expect(result, isA<SiloProfileEntered>());
      expect(session.session!.profileId, 'p-1');
      expect(session.session!.profileToken, isNull);
      expect(server.requests, isEmpty);
    });
  });

  group('server address, TvServerSetupViewModel.kt:249-337', () {
    test('a bare host tries https, then http', () {
      expect(siloAddressCandidates(' silo.ruleone.xyz/ ').map((u) => '$u'), [
        'https://silo.ruleone.xyz',
        'http://silo.ruleone.xyz',
      ]);
      expect(siloAddressCandidates('http://10.0.2.2:8090').map((u) => '$u'), ['http://10.0.2.2:8090']);
      expect(siloAddressCandidates('not a host'), isEmpty);
    });

    test('a found server reports setup and signup from system/setup and auth/signup', () async {
      final server = FakeSiloServer();

      final result = await probeSiloServer('silo.ruleone.xyz', device: siloTestDevice, client: server.client);

      expect(result, isA<SiloServerFound>());
      final found = result as SiloServerFound;
      expect('${found.origin}', 'https://silo.ruleone.xyz');
      expect((found.needsSetup, found.signupEnabled), (false, true));
      expect(server.requests.map((r) => r.url.path), [
        '/api/v2/system/info',
        '/api/v2/system/setup',
        '/api/v2/auth/signup',
      ]);
    });

    test('an address where every candidate fails is unreachable', () async {
      final down = FakeSilo((_) => throw const _Offline());

      final result = await probeSiloServer('nowhere.invalid', device: siloTestDevice, client: down.client);

      expect(result, isA<SiloServerUnreachable>());
      expect(down.requests.map((r) => '${r.url.scheme} ${r.url.path}'), [
        'https /api/v2/system/info',
        'https /api/v2/system/setup',
        'http /api/v2/system/info',
        'http /api/v2/system/setup',
      ]);
    });

    test('the legacy 404 body means the server must be updated (ApiV2Probe.kt:139-147)', () async {
      final legacy = FakeSilo((_) => http.Response('404 page not found', 404));

      final result = await probeSiloServer('https://old.example', device: siloTestDevice, client: legacy.client);

      expect(result, isA<SiloServerNeedsUpdate>());
      expect(legacy.requests.single.url.path, '/api/v2/system/info');
    });
  });
}

class _Offline implements Exception {
  const _Offline();
}
