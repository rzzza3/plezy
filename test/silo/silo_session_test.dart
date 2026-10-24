import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/silo/silo_http.dart';
import 'package:plezy/services/base_shared_preferences_service.dart';
import 'package:plezy/services/credential_vault.dart';
import 'package:plezy/services/sensitive_prefs.dart';
import 'package:plezy/silo/silo_headers.dart';
import 'package:plezy/silo/silo_session.dart';
import 'package:plezy/silo/silo_vault_store.dart';

import '../test_helpers/prefs.dart';

import 'fake_silo.dart';

const _home = '/api/v2/home/sections';
const _refresh = '/api/v2/auth/refresh';

void main() {
  group('401 refresh, AuthInterceptorImpl.kt:748-832', () {
    test('two concurrent 401s cause exactly one /auth/refresh call (AuthInterceptorImpl.kt:155-166)', () async {
      final (session, _) = await signedInSession();
      final refreshGate = Completer<void>();
      final fake = FakeSilo((request) async {
        if (request.url.path == _refresh) {
          await refreshGate.future;
          return tokenPair('access-B', 'refresh-B');
        }
        return request.header('authorization') == 'Bearer access-B'
            ? jsonResponse({'sections': []}, 200)
            : jsonResponse({}, 401);
      });
      final silo = siloHttpFor(fake, session);

      final first = silo.send(const SiloRequest.get(_home));
      final second = silo.send(const SiloRequest.get(_home));
      await pumpEventQueue();
      expect(fake.to(_home).length, 2, reason: 'both requests went out with the old token before any refresh');
      refreshGate.complete();
      final responses = await Future.wait([first, second]);

      expect(fake.to(_refresh).length, 1, reason: 'AuthInterceptorImpl.kt:162-166 reuses the rotated token');
      expect(responses.map((r) => r.statusCode), [200, 200]);
      expect(fake.to(_home).map((r) => r.header('authorization')), [
        'Bearer access-A',
        'Bearer access-A',
        'Bearer access-B',
        'Bearer access-B',
      ]);
      expect(session.session!.tokens.refreshToken, 'refresh-B');
    });

    test('a 401 is retried at most once (AuthInterceptorImpl.kt:805-832)', () async {
      final (session, _) = await signedInSession();
      final fake = FakeSilo(
        (request) => request.url.path == _refresh ? tokenPair('access-B', 'refresh-B') : jsonResponse({}, 401),
      );

      final response = await siloHttpFor(fake, session).send(const SiloRequest.get(_home));

      expect(response.statusCode, 401);
      expect(fake.to(_home).length, 2);
      expect(fake.to(_refresh).length, 1);
    });

    test('a single request is never refreshed or retried (AuthInterceptorImpl.kt:551-552)', () async {
      final (session, _) = await signedInSession();
      final fake = FakeSilo((request) => jsonResponse({}, 401));

      final response = await siloHttpFor(
        fake,
        session,
      ).send(const SiloRequest.post('/api/v2/profiles', body: {'name': 'x'}, single: true));

      expect(response.statusCode, 401);
      expect(fake.requests.map((r) => r.url.path), ['/api/v2/profiles']);
    });

    test(
      'the refresh call carries no Authorization, profile or X-Silo-* header (AuthInterceptorImpl.kt:476-478)',
      () async {
        final (session, _) = await signedInSession();
        await session.selectProfile('7', 'pin-token');
        final fake = FakeSilo(
          (request) => request.url.path == _refresh ? tokenPair('access-B', 'refresh-B') : jsonResponse({}, 401),
        );

        await siloHttpFor(fake, session).send(const SiloRequest.get(_home));

        final refresh = fake.to(_refresh).single;
        expect(refresh.method, 'POST');
        expect(refresh.body, '{"refresh_token":"refresh-A"}');
        expect(refresh.headers.keys.where((k) => k == 'authorization' || k.startsWith('x-')), isEmpty);
      },
    );
  });

  group('refresh outcomes, AuthInterceptorImpl.kt:228-292', () {
    Future<(SiloRefreshOutcome, SiloSessionController, MemorySiloSessionStore, int)> refreshAnswering(
      int status, {
      String body = '{}',
    }) async {
      final (session, store) = await signedInSession();
      var expiredEvents = 0;
      session.sessionExpired.listen((_) => expiredEvents++);
      final fake = FakeSilo((_) => http.Response(body, status));
      final outcome = await siloHttpFor(
        fake,
        session,
      ).refresh(sentAccessToken: 'access-A', generation: session.generation);
      return (outcome, session, store, expiredEvents);
    }

    test('a 503 from refresh keeps the tokens (AuthInterceptorImpl.kt:248-257)', () async {
      final (outcome, session, store, expiredEvents) = await refreshAnswering(503);

      expect(outcome, isA<SiloRefreshTransient>().having((o) => o.status, 'status', 503));
      expect(session.session!.tokens.accessToken, 'access-A');
      expect(session.session!.tokens.refreshToken, 'refresh-A');
      expect(store.state.session!.tokens.refreshToken, 'refresh-A');
      expect(expiredEvents, 0);
    });

    test('a 503 provider_unavailable problem is reported apart (AuthInterceptorImpl.kt:251-255)', () async {
      final (outcome, session, _, _) = await refreshAnswering(
        503,
        body: '{"type":"https://silo/problems/provider_unavailable","title":"t","status":503}',
      );

      expect(outcome, isA<SiloRefreshTransient>().having((o) => o.providerUnavailable, 'providerUnavailable', true));
      expect(session.session!.tokens.accessToken, 'access-A');
    });

    test('a 401 from refresh clears the session (AuthInterceptorImpl.kt:285-288, :890-893)', () async {
      final (outcome, session, store, expiredEvents) = await refreshAnswering(401);

      expect(outcome, isA<SiloRefreshRejected>().having((o) => o.status, 'status', 401));
      expect(session.session, isNull);
      expect(store.state.session, isNull);
      expect(store.state.generation, 2);
      expect(expiredEvents, 1);
    });

    for (final status in [400, 403]) {
      test('a $status from refresh also clears the session (AuthInterceptorImpl.kt:890-893)', () async {
        final (outcome, session, _, _) = await refreshAnswering(status);

        expect(outcome, isA<SiloRefreshRejected>().having((o) => o.status, 'status', status));
        expect(session.session, isNull);
      });
    }

    for (final status in [500, 502, 429, 404]) {
      test('a $status from refresh keeps the session (AuthInterceptorImpl.kt:245-257)', () async {
        final (outcome, session, _, _) = await refreshAnswering(status);

        expect(outcome, isA<SiloRefreshTransient>());
        expect(session.session!.tokens.accessToken, 'access-A');
      });
    }

    test('a network error from refresh keeps the session (AuthInterceptorImpl.kt:293-296)', () async {
      final (session, _) = await signedInSession();
      final fake = FakeSilo((_) => throw http.ClientException('offline'));

      final outcome = await siloHttpFor(
        fake,
        session,
      ).refresh(sentAccessToken: 'access-A', generation: session.generation);

      expect(outcome, isA<SiloRefreshTransient>().having((o) => o.status, 'status', isNull));
      expect(session.session!.tokens.refreshToken, 'refresh-A');
    });

    test('a sign-out during the refresh round trip drops the new tokens (AuthInterceptorImpl.kt:218-226)', () async {
      final (session, _) = await signedInSession();
      final answer = Completer<http.Response>();
      final fake = FakeSilo((_) => answer.future);
      final pending = siloHttpFor(fake, session).refresh(sentAccessToken: 'access-A', generation: session.generation);
      await pumpEventQueue();

      await session.signOut();
      answer.complete(tokenPair('access-B', 'refresh-B'));

      expect(await pending, isA<SiloRefreshNotAttempted>());
      expect(session.session, isNull);
    });

    test('a 200 rotation keeps the generation, because it is not an identity change', () async {
      final (session, _) = await signedInSession();
      final generation = session.generation;
      final fake = FakeSilo((_) => tokenPair('access-B', 'refresh-B', expiresIn: 900));

      final outcome = await siloHttpFor(fake, session).refresh(sentAccessToken: 'access-A', generation: generation);

      expect(outcome, isA<SiloRefreshed>().having((o) => o.usedNetwork, 'usedNetwork', true));
      expect(session.generation, generation);
      expect(session.session!.tokens.lifetime, const Duration(seconds: 900));
    });
  });

  group('proactive refresh, ProactiveRefreshPolicy.kt:28-38', () {
    test('the margin is clamped to half the lifetime (ProactiveRefreshPolicy.kt:37)', () {
      const margin = Duration(seconds: 60);
      const lifetime = Duration(seconds: 60);
      expect(
        shouldRefreshProactively(remaining: const Duration(seconds: 31), lifetime: lifetime, margin: margin),
        false,
      );
      expect(
        shouldRefreshProactively(remaining: const Duration(seconds: 30), lifetime: lifetime, margin: margin),
        true,
      );
      expect(
        shouldRefreshProactively(
          remaining: const Duration(seconds: 60),
          lifetime: const Duration(hours: 1),
          margin: margin,
        ),
        true,
      );
      expect(
        shouldRefreshProactively(
          remaining: const Duration(seconds: 61),
          lifetime: const Duration(hours: 1),
          margin: margin,
        ),
        false,
      );
    });

    test('an unknown or zero lifetime never refreshes early (ProactiveRefreshPolicy.kt:34-35)', () {
      const margin = Duration(seconds: 60);
      expect(shouldRefreshProactively(remaining: const Duration(seconds: 1), lifetime: null, margin: margin), false);
      expect(
        shouldRefreshProactively(remaining: const Duration(seconds: 1), lifetime: Duration.zero, margin: margin),
        false,
      );
    });

    test('an expired token is always refreshed first (ProactiveRefreshPolicy.kt:33)', () {
      expect(shouldRefreshProactively(remaining: Duration.zero, lifetime: null, margin: Duration.zero), true);
    });

    test(
      'a token inside the margin is refreshed before the request goes out (AuthInterceptorImpl.kt:663-679)',
      () async {
        var clock = DateTime.utc(2026, 10, 11, 12);
        final (session, _) = await signedInSession(now: () => clock);
        clock = clock.add(const Duration(minutes: 59, seconds: 30));
        final fake = FakeSilo(
          (request) => request.url.path == _refresh ? tokenPair('access-B', 'refresh-B') : jsonResponse({}, 200),
        );

        final response = await siloHttpFor(fake, session).send(const SiloRequest.get(_home));

        expect(response.statusCode, 200);
        expect(fake.requests.map((r) => r.url.path), [_refresh, _home]);
        expect(fake.to(_home).single.header('authorization'), 'Bearer access-B');
      },
    );

    test('a rejected proactive refresh fails the request unsent (AuthInterceptorImpl.kt:693-698)', () async {
      var clock = DateTime.utc(2026, 10, 11, 12);
      final (session, _) = await signedInSession(now: () => clock);
      clock = clock.add(const Duration(hours: 2));
      final fake = FakeSilo((_) => jsonResponse({}, 401));

      await expectLater(
        siloHttpFor(fake, session).send(const SiloRequest.get(_home)),
        throwsA(isA<SiloCredentialsRepudiatedException>()),
      );
      expect(fake.requests.map((r) => r.url.path), [_refresh]);
      expect(session.session, isNull);
    });

    test(
      'after a transient proactive failure the 401 path does not refresh again (AuthInterceptorImpl.kt:799-802)',
      () async {
        var clock = DateTime.utc(2026, 10, 11, 12);
        final (session, _) = await signedInSession(now: () => clock);
        clock = clock.add(const Duration(hours: 2));
        final fake = FakeSilo(
          (request) => request.url.path == _refresh ? http.Response('', 502) : jsonResponse({}, 401),
        );

        final response = await siloHttpFor(fake, session).send(const SiloRequest.get(_home));

        expect(response.statusCode, 401);
        expect(fake.requests.map((r) => r.url.path), [_refresh, _home]);
        expect(session.session!.tokens.accessToken, 'access-A');
      },
    );
  });

  group('session value and generation, EncryptedTokenManagerImpl.kt:174-243', () {
    test(
      'a sign-in, profile switch and sign-out each bump the generation (IdentityTransitionBarrier.kt:99-133)',
      () async {
        final store = MemorySiloSessionStore();
        final session = await SiloSessionController.load(store);
        expect(session.generation, 0);

        await session.replaceAccountSession(
          origin: 'https://silo.ruleone.xyz',
          accessToken: 'a',
          refreshToken: 'r',
          expiresInSeconds: 60,
        );
        expect(session.generation, 1);
        await session.selectProfile('3', null);
        expect(session.generation, 2);
        await session.signOut();
        expect(session.generation, 3);
        expect(store.state.generation, 3);
        expect(store.state.session, isNull);
      },
    );

    test('a sign-in commit is refused when the generation moved (AuthRepository.kt:60-89)', () async {
      final (session, _) = await signedInSession();
      final captured = session.generation;
      await session.selectProfile('3', null);

      await expectLater(
        session.replaceAccountSession(
          origin: 'https://silo.ruleone.xyz',
          accessToken: 'a',
          refreshToken: 'r',
          expiresInSeconds: 60,
          expectedGeneration: captured,
        ),
        throwsA(isA<SiloIdentityChangedException>()),
      );
      expect(session.session!.tokens.accessToken, 'access-A');
    });

    test('changing the profile id drops a stale profile token (TokenManager.kt:141-180)', () async {
      final (session, _) = await signedInSession();
      await session.selectProfile('3', 'pin-token');
      expect(session.session!.profileToken, 'pin-token');
      await session.selectProfile(null, 'pin-token');
      expect(session.session!.profileToken, isNull);
    });

    test('the persisted value round-trips every field in one blob', () async {
      final (session, store) = await signedInSession(expiresIn: 900);
      await session.selectProfile('3', 'pin-token');

      final decoded = SiloSessionState.decode(store.state.encode());

      expect(decoded.generation, 2);
      expect(decoded.session!.origin, 'https://silo.ruleone.xyz');
      expect(decoded.session!.tokens.accessToken, 'access-A');
      expect(decoded.session!.tokens.refreshToken, 'refresh-A');
      expect(decoded.session!.tokens.lifetime, const Duration(seconds: 900));
      expect(decoded.session!.tokens.expiresAt, session.session!.tokens.expiresAt);
      expect(decoded.session!.profileId, '3');
      expect(decoded.session!.profileToken, 'pin-token');
    });
  });

  group('vault storage, EncryptedTokenManagerImpl.kt:174-243 and AndroidDeviceMetadataProvider.kt:31-33', () {
    setUp(() {
      resetSharedPreferencesForTest();
      CredentialVault.resetKeyForTesting();
    });

    test('the whole session is one encrypted preference value', () async {
      final session = await SiloSessionController.load(const VaultSiloSessionStore('server-1'));
      await session.replaceAccountSession(
        origin: 'https://silo.ruleone.xyz',
        accessToken: 'access-A',
        refreshToken: 'refresh-A',
        expiresInSeconds: 900,
      );
      await session.selectProfile('3', 'pin-token');
      await session.saveRefreshedTokens(accessToken: 'access-B', refreshToken: 'refresh-B', expiresInSeconds: 900);

      final prefs = await BaseSharedPreferencesService.sharedCache();
      final raw = prefs.getString(siloSessionPrefFor('server-1'))!;
      expect(CredentialVault.isProtected(raw), true);
      for (final secret in ['access-B', 'refresh-B', 'pin-token']) {
        expect(raw, isNot(contains(secret)));
      }
      expect(prefs.keys.where((k) => k.startsWith('silo_')).toSet(), {siloSessionPrefFor('server-1')});

      final other = await const VaultSiloSessionStore('server-2').read();
      expect(other.session, isNull, reason: 'each server has its own slot, EncryptedTokenManagerImpl.kt:823-834');

      final reloaded = await SiloSessionController.load(const VaultSiloSessionStore('server-1'));
      expect(reloaded.generation, 2);
      expect(reloaded.session!.tokens.accessToken, 'access-B');
      expect(reloaded.session!.tokens.refreshToken, 'refresh-B');
      expect(reloaded.session!.profileId, '3');
      expect(reloaded.session!.profileToken, 'pin-token');
    });

    test('the device id lives outside the session and survives sign-out', () async {
      final headers = await SiloHeaders.load(
        store: const PrefsSiloDeviceIdStore(),
        isTv: true,
        manufacturer: 'a',
        model: 'b',
      );
      final session = await SiloSessionController.load(const VaultSiloSessionStore('server-1'));
      await session.replaceAccountSession(
        origin: 'https://silo.ruleone.xyz',
        accessToken: 'a',
        refreshToken: 'r',
        expiresInSeconds: 60,
      );
      await session.signOut();

      final prefs = await BaseSharedPreferencesService.sharedCache();
      expect(prefs.getString(PrefsSiloDeviceIdStore.key), headers.id);
      expect((await const VaultSiloSessionStore('server-1').read()).session, isNull);
      final again = await SiloHeaders.load(
        store: const PrefsSiloDeviceIdStore(),
        isTv: true,
        manufacturer: 'a',
        model: 'b',
      );
      expect(again.id, headers.id);
    });

    test('the session key is a credential slot that prefs repair must keep', () {
      expect(isSensitivePrefKey(siloSessionPrefFor('server-1')), true);
      expect(isSensitivePrefKey(PrefsSiloDeviceIdStore.key), false);
    });
  });
}
