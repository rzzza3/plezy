import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/silo/silo_device_sign_in.dart';
import 'package:plezy/silo/silo_session.dart';
import 'package:plezy/silo/silo_sign_in.dart';

import '../test_helpers/fake_silo_server.dart';

const _poll = '/api/v2/auth/device/poll';
const _start = '/api/v2/auth/device/start';
const _cancel = '/api/v2/auth/device/cancel';

Future<(SiloDeviceSignIn, FakeSiloClock)> _machine(FakeSiloServer server) async {
  final clock = FakeSiloClock();
  final machine = SiloDeviceSignIn(
    http: siloHttpForServer(server, await emptySiloSession()),
    deviceName: 'Plezy Test',
    wait: clock.wait,
    now: () => clock.now,
  );
  return (machine, clock);
}

void main() {
  group('device code timing, DeviceLoginRepository.kt:68-189', () {
    test('waits follow interval, then poll_after, with a 1 s floor and doubling backoff to 30 s', () async {
      final replies = <http.Response Function()>[
        FakeSiloServer.pending,
        () => FakeSiloServer.pending(pollAfter: 0),
        () => FakeSiloServer.pending(pollAfter: 3),
        for (var i = 0; i < 5; i++) () => jsonResponse({}, 503),
        () => FakeSiloServer.pending(pollAfter: 2),
        FakeSiloServer.approved,
      ];
      final server = FakeSiloServer(codeInterval: 5, pollReply: (_, n) => replies[n - 1]());
      final (machine, clock) = await _machine(server);

      await machine.run();

      expect(
        clock.waits.map((d) => d.inSeconds),
        [5, 1, 3, 3, 6, 12, 24, 30, 2],
        reason:
            'interval 5 (start reply), poll_after 0 floors to 1 s (:141), poll_after 3, '
            'then 5xx backoff doubles from the interval to the 30 s cap (:72-74), then poll_after 2',
      );
      expect(server.to(_poll).length, 10, reason: 'the first poll goes out right after start, with no wait');
      final state = machine.state.value;
      expect(state, isA<SiloDeviceApproved>());
      expect((state as SiloDeviceApproved).tokens.accessToken, 'access-D');
    });

    test('an expired code is cancelled before a new start (DeviceSignInMachine.kt:352-379)', () async {
      final server = FakeSiloServer(
        codeLifetimeSeconds: 8,
        codeInterval: 5,
        pollReply: (code, _) => code == 'device-code-2' ? FakeSiloServer.approved() : FakeSiloServer.pending(),
      );
      final (machine, clock) = await _machine(server);

      await machine.run();

      expect(clock.waits.map((d) => d.inSeconds), [5, 3], reason: 'the last wait is clamped to the deadline (:187)');
      final calls = [
        for (final r in server.requests)
          if (r.url.path.startsWith('/api/v2/auth/device/') && !r.url.path.endsWith('capability'))
            '${r.url.path.split('/').last} ${r.body.contains('device_code') ? r.body.split('"')[3] : ''}'.trim(),
      ];
      expect(calls, [
        'start',
        'poll device-code-1',
        'poll device-code-1',
        'poll device-code-1',
        'cancel device-code-1',
        'start',
        'poll device-code-2',
      ]);
      expect(server.cancelledCodes, ['device-code-1']);
      expect(machine.state.value, isA<SiloDeviceApproved>());
    });

    test('a code the server reports expired is replaced without a cancel', () async {
      final server = FakeSiloServer(
        pollReply: (code, _) => code == 'device-code-1' ? FakeSiloServer.status('expired') : FakeSiloServer.approved(),
      );
      final (machine, _) = await _machine(server);

      await machine.run();

      expect(server.to(_start).length, 2);
      expect(server.cancelledCodes, isEmpty, reason: 'the server already dropped it');
      expect(machine.state.value, isA<SiloDeviceApproved>());
    });

    test('abandon withdraws the live code (TvLoginViewModel.kt:893-899)', () async {
      final server = FakeSiloServer();
      final parked = SiloDeviceSignIn(
        http: siloHttpForServer(server, await emptySiloSession()),
        deviceName: 'Plezy Test',
        wait: (_) => Future<void>.delayed(const Duration(days: 1)),
      );

      final running = parked.run();
      await pumpEventQueue();
      expect(parked.state.value, isA<SiloDeviceShowingCode>());
      await parked.abandon();
      await running;

      expect(server.cancelledCodes, ['device-code-1']);
      expect(server.to(_cancel).single.header('authorization'), isNull);
    });
  });

  group('password and device code race, TvLoginViewModel.kt:313, :664-668, :754-764', () {
    late FakeSiloServer server;
    late SiloSessionController session;
    late SiloLoginController login;

    setUp(() async {
      server = FakeSiloServer();
      session = await emptySiloSession();
      login = SiloLoginController(
        origin: siloTestOrigin,
        device: siloTestDevice,
        sessionFor: (_) async => session,
        deviceName: 'Plezy Test',
        client: server.client,
        wait: (_) => Future<void>.delayed(const Duration(days: 1)),
      );
    });

    tearDown(() => login.dispose());

    test('a password win cancels the device code', () async {
      await login.open();
      await pumpEventQueue();
      expect(login.phase, isA<SiloLoginRacing>());

      await login.submitPassword('alice', 'secret');

      expect((login.phase as SiloLoginSignedIn).username, 'alice');
      expect(server.cancelledCodes, ['device-code-1']);
      expect(session.session!.tokens.accessToken, 'access-P');
      expect(session.generation, 1, reason: 'one commit, fenced by the generation (AuthRepository.kt:60-89)');
    });

    test('a wrong password shows invalid credentials and keeps the code running', () async {
      await login.open();
      await pumpEventQueue();

      await login.submitPassword('alice', 'wrong');

      final phase = login.phase as SiloLoginRacing;
      expect((phase.password as SiloPasswordFailed).error.kind, SiloSignInErrorKind.invalidCredentials);
      expect(phase.device, isA<SiloDeviceShowingCode>());
      expect(server.cancelledCodes, isEmpty);
      expect(session.session, isNull);
    });

    test('a device approval that lands while the password call is in flight wins', () async {
      server.loginGate = Completer<void>();
      server.pollReply = (_, n) => n == 1 ? FakeSiloServer.pending() : FakeSiloServer.approved();
      final fastLogin = SiloLoginController(
        origin: siloTestOrigin,
        device: siloTestDevice,
        sessionFor: (_) async => session,
        deviceName: 'Plezy Test',
        client: server.client,
        wait: (_) async {},
      );
      addTearDown(fastLogin.dispose);

      await fastLogin.open();
      final password = fastLogin.submitPassword('alice', 'wrong');
      await pumpEventQueue();
      server.loginGate!.complete();
      await password;
      await pumpEventQueue();

      expect(fastLogin.phase, isA<SiloLoginSignedIn>());
      expect(session.session!.tokens.accessToken, 'access-D');
    });

    test('a device approval with no password signs in under the account name', () async {
      server.pollReply = (_, n) => n == 1 ? FakeSiloServer.pending() : FakeSiloServer.approved();
      final approving = SiloLoginController(
        origin: siloTestOrigin,
        device: siloTestDevice,
        sessionFor: (_) async => session,
        deviceName: 'Plezy Test',
        client: server.client,
        wait: (_) async {},
      );
      addTearDown(approving.dispose);

      await approving.open();
      await pumpEventQueue();

      expect((approving.phase as SiloLoginSignedIn).username, 'alice');
      expect(session.session!.tokens.accessToken, 'access-D');
      expect(session.generation, 1);
      expect(server.cancelledCodes, isEmpty, reason: 'an approved code is spent, not withdrawn');
    });

    test('an approval after the identity moved is refused (port note 9)', () async {
      server.pollReply = (code, n) =>
          code == 'device-code-1' && n > 1 ? FakeSiloServer.approved() : FakeSiloServer.pending();
      final gate = Completer<void>();
      var waits = 0;
      final fenced = SiloLoginController(
        origin: siloTestOrigin,
        device: siloTestDevice,
        sessionFor: (_) async => session,
        deviceName: 'Plezy Test',
        client: server.client,
        wait: (_) => waits++ == 0 ? gate.future : Completer<void>().future,
      );
      addTearDown(fenced.dispose);

      await fenced.open();
      await pumpEventQueue();
      await session.signOut();
      gate.complete();
      await pumpEventQueue();

      expect(session.session, isNull, reason: 'the approval was captured under generation 0 and must not commit');
      expect(server.issuedCodes, ['device-code-1', 'device-code-2'], reason: 'a fresh code, fenced anew');
      final phase = fenced.phase as SiloLoginRacing;
      expect((phase.password as SiloPasswordFailed).error.kind, SiloSignInErrorKind.identityChanged);
    });

    test('leaving the screen withdraws the code', () async {
      await login.open();
      await pumpEventQueue();

      await login.leave();

      expect(server.cancelledCodes, ['device-code-1']);
    });
  });
}
