import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/silo/silo_contract_gate.dart';
import 'package:plezy/silo/silo_headers.dart';
import 'package:plezy/silo/silo_http.dart';
import 'package:plezy/silo/silo_problem.dart';
import 'package:plezy/silo/silo_session.dart';

import 'fake_silo.dart';

bool _isCredential(String name) =>
    name == 'authorization' || name.startsWith('x-silo-') || name.startsWith('x-profile-');

void main() {
  group('credentials stay on the trusted origin, AuthInterceptorImpl.kt:409-426', () {
    test(
      'a redirect to another origin carries no Authorization and no X-Silo-* header (AuthInterceptorImpl.kt:927-934)',
      () async {
        final (session, _) = await signedInSession();
        await session.selectProfile('3', 'pin-token');
        final fake = FakeSilo(
          (request) => request.url.host == 'silo.ruleone.xyz'
              ? http.Response('', 302, headers: {'location': 'https://cdn.example/x.json'})
              : jsonResponse({'ok': true}, 200),
        );

        final response = await siloHttpFor(fake, session).send(const SiloRequest.get('/api/v2/home/sections'));

        expect(response.statusCode, 200);
        expect(response.url.toString(), 'https://cdn.example/x.json');
        final [first, second] = fake.requests;
        expect(first.header('authorization'), 'Bearer access-A');
        expect(first.header('x-profile-id'), '3');
        expect(first.header('x-silo-device-id'), siloTestDevice.id);
        expect(second.url.toString(), 'https://cdn.example/x.json');
        expect(second.headers.keys.where(_isCredential), isEmpty);
        expect(second.header('content-type'), 'application/json');
      },
    );

    test('a hop back to the trusted origin after leaving it stays stripped', () async {
      final (session, _) = await signedInSession();
      final fake = FakeSilo(
        (request) => switch (request.url.host) {
          'silo.ruleone.xyz' when request.url.path == '/api/v2/a' => http.Response(
            '',
            307,
            headers: {'location': 'http://silo.ruleone.xyz/api/v2/b'},
          ),
          'silo.ruleone.xyz' when request.url.scheme == 'http' => http.Response(
            '',
            307,
            headers: {'location': 'https://silo.ruleone.xyz/api/v2/c'},
          ),
          _ => jsonResponse({}, 200),
        },
      );

      await siloHttpFor(fake, session).send(const SiloRequest.get('/api/v2/a'));

      expect(fake.requests.map((r) => r.url.toString()), [
        'https://silo.ruleone.xyz/api/v2/a',
        'http://silo.ruleone.xyz/api/v2/b',
        'https://silo.ruleone.xyz/api/v2/c',
      ]);
      expect(fake.requests[0].header('authorization'), 'Bearer access-A');
      expect(
        fake.requests[1].headers.keys.where(_isCredential),
        isEmpty,
        reason: 'scheme differs (HttpOriginPolicy.kt:37-41)',
      );
      expect(fake.requests[2].headers.keys.where(_isCredential), isEmpty);
    });

    test('a same-origin redirect keeps the credentials', () async {
      final (session, _) = await signedInSession();
      final fake = FakeSilo(
        (request) => request.url.path == '/api/v2/a'
            ? http.Response('', 308, headers: {'location': '/api/v2/b'})
            : jsonResponse({}, 200),
      );

      await siloHttpFor(fake, session).send(const SiloRequest.get('/api/v2/a'));

      expect(fake.requests.map((r) => r.header('authorization')), ['Bearer access-A', 'Bearer access-A']);
    });

    test(
      'a 401 from a foreign origin after a redirect never triggers a refresh (AuthInterceptorImpl.kt:754-756)',
      () async {
        final (session, _) = await signedInSession();
        final fake = FakeSilo(
          (request) => request.url.host == 'silo.ruleone.xyz'
              ? http.Response('', 302, headers: {'location': 'https://cdn.example/x'})
              : jsonResponse({}, 401),
        );

        final response = await siloHttpFor(fake, session).send(const SiloRequest.get('/api/v2/a'));

        expect(response.statusCode, 401);
        expect(fake.to('/api/v2/auth/refresh'), isEmpty);
      },
    );

    test('a public probe sends device headers but no Authorization (AuthInterceptorImpl.kt:410-416)', () async {
      final (session, _) = await signedInSession();
      await session.selectProfile('3', 'pin-token');
      final fake = FakeSilo((_) => jsonResponse({'server_id': 'x'}, 200));

      await siloHttpFor(fake, session).send(const SiloRequest.get('/api/v2/system/identity', auth: SiloAuth.none));

      final sent = fake.requests.single.headers;
      expect(sent.containsKey('authorization'), false);
      expect(sent.containsKey('x-profile-id'), false);
      expect(sent['x-silo-device-id'], siloTestDevice.id);
      expect(sent['x-silo-device-platform'], 'android-tv');
    });

    test('origin equality compares scheme, host and port (HttpOriginPolicy.kt:37-41)', () {
      bool same(String a, String b) => isSameSiloOrigin(Uri.parse(a), Uri.parse(b));
      expect(same('https://Silo.RuleOne.xyz/a', 'https://silo.ruleone.xyz:443/b'), true);
      expect(same('https://silo.ruleone.xyz', 'http://silo.ruleone.xyz'), false);
      expect(same('https://silo.ruleone.xyz', 'https://silo.ruleone.xyz:8443'), false);
      expect(same('https://silo.ruleone.xyz', 'https://evil.example'), false);
      expect(same('https://silo.ruleone.xyz', 'https://user@silo.ruleone.xyz'), false);
      expect(same('https://silo.ruleone.xyz', 'wss://silo.ruleone.xyz'), false);
    });
  });

  group('wire defaults, SiloHttpClientImpl.kt:17-23 and :84-98', () {
    test('timeouts are 10 s connect and 60 s request (SiloHttpClientImpl.kt:91-92)', () {
      expect(siloConnectTimeout, const Duration(seconds: 10));
      expect(siloRequestTimeout, const Duration(seconds: 60));
      expect(const SiloRequest.get('/x').timeout, const Duration(seconds: 60));
    });

    test('a request past its timeout fails instead of hanging', () async {
      final (session, _) = await signedInSession();
      final fake = FakeSilo((_) => Completer<http.Response>().future);

      await expectLater(
        siloHttpFor(fake, session).send(const SiloRequest('GET', '/api/v2/x', timeout: Duration(milliseconds: 20))),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('every request is JSON and null members are omitted (SiloHttpClientImpl.kt:21-22, :96-98)', () async {
      final (session, _) = await signedInSession();
      final fake = FakeSilo((_) => jsonResponse({}, 201));

      await siloHttpFor(fake, session).send(
        const SiloRequest.post(
          '/api/v2/auth/device/start',
          body: {
            'device_name': 'TV',
            'provider': null,
            'nested': {'a': null, 'b': 1},
          },
          auth: SiloAuth.none,
          single: true,
        ),
      );

      expect(fake.requests.single.header('content-type'), startsWith('application/json'));
      expect(fake.requests.single.body, '{"device_name":"TV","nested":{"b":1}}');
    });

    test('response JSON resolves artwork against the answering origin (ApiV2Call.kt:36-38)', () async {
      final (session, _) = await signedInSession();
      final fake = FakeSilo((_) => jsonResponse({'poster_url': '/p.jpg'}, 200));

      final response = await siloHttpFor(fake, session).send(const SiloRequest.get('/api/v2/x'));

      expect(response.json(), {'poster_url': 'https://silo.ruleone.xyz/p.jpg'});
    });
  });

  group('device headers, silo-auth.md 4.4 and AndroidDeviceMetadataProvider.kt:30-90', () {
    test('the header set carries every non-blank value and drops build 0 (ClientBuildIdentity.kt:54-63)', () async {
      final headers = await SiloHeaders.load(
        store: MemorySiloDeviceIdStore('device-1'),
        isTv: true,
        manufacturer: ' NVIDIA ',
        model: 'SHIELD Android TV',
        clientName: 'Plezy',
        version: '2.22.0',
        build: '0',
        channel: ' ',
      );

      expect(headers.toMap(), {
        'X-Silo-Device-Id': 'device-1',
        'X-Silo-Device-Name': 'NVIDIA SHIELD Android TV',
        'X-Silo-Device-Platform': 'android-tv',
        'X-Silo-Client': 'Plezy',
        'X-Silo-Client-Version': '2.22.0',
        'X-Silo-Client-Family': 'tv',
      });
    });

    test(
      'a phone is android, and a blank or duplicate model falls back (AndroidDeviceMetadataProvider.kt:34-38)',
      () async {
        final store = MemorySiloDeviceIdStore('device-1');
        final phone = await SiloHeaders.load(store: store, isTv: false, manufacturer: 'Pixel', model: 'Pixel');
        final blank = await SiloHeaders.load(store: store, isTv: false, manufacturer: ' ', model: null);

        expect(phone.platform, 'android');
        expect(phone.family, 'mobile');
        expect(phone.name, 'Pixel');
        expect(blank.name, 'Android Device');
      },
    );

    test('the device id is generated once and survives sign-out (AndroidDeviceMetadataProvider.kt:31-33)', () async {
      final store = MemorySiloDeviceIdStore();
      final first = await SiloHeaders.load(store: store, isTv: true, manufacturer: 'a', model: 'b');
      final (session, _) = await signedInSession();
      await session.signOut();
      final second = await SiloHeaders.load(store: store, isTv: true, manufacturer: 'a', model: 'b');

      expect(first.id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(second.id, first.id);
      expect(await store.read(), first.id);
    });
  });

  group('problem bodies, ApiV2Models.kt:34-53', () {
    test('the code is the last segment of type, trailing slashes trimmed (ApiV2Models.kt:45)', () {
      final problem = SiloProblem.tryParse(
        '{"type":"https://silo.dev/problems/validation_failed/","title":"Bad","status":422,"detail":"d",'
        '"errors":[{"location":"body.password","code":"too_short"}]}',
      );

      expect(problem!.code, 'validation_failed');
      expect(problem.status, 422);
      expect(problem.detail, 'd');
      expect(problem.errors.single.location, 'body.password');
      expect(problem.errors.single.code, 'too_short');
    });

    test('a bare type is its own code, and a non-problem body is null (ApiV2Call.kt:50-61)', () {
      expect(SiloProblem.tryParse('{"type":"rate_limited","title":"t","status":429}')!.code, 'rate_limited');
      expect(SiloProblem.tryParse('<html>'), isNull);
      expect(SiloProblem.tryParse('{"title":"t","status":429}'), isNull);
    });
  });

  group('contract gate, ApiV2Probe.kt:106-147 and ApiV2Gate.kt:23-38', () {
    test('only the exact legacy 404 body records UPDATE_REQUIRED (ApiV2Probe.kt:146-147)', () {
      final gate = SiloContractGate();
      gate.recordProbe(status: 404, body: '404 page not found\n\n');
      expect(gate.contract, SiloContract.unknown);
      gate.recordProbe(status: 404, body: ' 404 page not found');
      expect(gate.contract, SiloContract.unknown);
      gate.recordProbe(status: 200, body: '{}', apiMajor: 2);
      expect(gate.contract, SiloContract.v2);
      gate.recordProbe(status: 503, body: '404 page not found');
      expect(gate.contract, SiloContract.v2, reason: 'a failed probe keeps the verdict (ServerContract.kt:12-13)');
      gate.recordProbe(status: 404, body: '404 page not found\n');
      expect(gate.contract, SiloContract.updateRequired);
    });

    test('while UPDATE_REQUIRED is set, v2 calls are blocked before sending (ApiV2Gate.kt:29-34)', () async {
      final session = await SiloSessionController.load(MemorySiloSessionStore());
      final fake = FakeSilo((_) => jsonResponse({}, 200));
      final gate = SiloContractGate()..recordProbe(status: 404, body: '404 page not found');
      final silo = SiloHttp(
        origin: siloTestOrigin,
        session: session,
        device: siloTestDevice,
        gate: gate,
        client: fake.client,
      );

      await expectLater(
        silo.send(const SiloRequest.get('/api/v2/system/setup', auth: SiloAuth.none)),
        throwsA(isA<SiloUpdateRequiredException>()),
      );
      expect(fake.requests, isEmpty);
      await silo.send(const SiloRequest.get('/api/v2/system/info', auth: SiloAuth.none, gated: false));
      expect(fake.requests.single.url.path, '/api/v2/system/info');
    });
  });
}
