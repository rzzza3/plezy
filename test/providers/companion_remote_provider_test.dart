import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/models/companion_remote/remote_command.dart';
import 'package:plezy/models/companion_remote/remote_session.dart';
import 'package:plezy/providers/companion_remote_provider.dart';
import 'package:plezy/services/companion_remote/companion_remote_peer_service.dart';
import 'package:plezy/services/companion_remote/lan_discovery_service.dart';
import 'package:plezy/services/companion_remote/remote_auth_context.dart';
import 'package:plezy/services/companion_remote/remote_auth_service.dart';

import '../test_helpers/prefs.dart';
import '../test_helpers/profile_stack.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetSharedPreferencesForTest);

  group('CompanionRemoteProvider — initial state', () {
    test('discoverHosts returns null when crypto is not ready', () {
      final p = CompanionRemoteProvider();
      expect(p.discoverHosts(), isNull);
      p.dispose();
    });

    test('sendCommand is a no-op when not connected (no throw)', () {
      final p = CompanionRemoteProvider();
      // Not connected → cannot send. Must log a warning but not throw.
      expect(() => p.sendCommand(RemoteCommandType.ping), returnsNormally);
      p.dispose();
    });

    test('startHostServer no-ops when crypto is not ready', () async {
      final p = CompanionRemoteProvider();
      // Without crypto context, this method must early-return without
      // creating a peer service or session.
      await p.startHostServer();
      expect(p.session, isNull);
      expect(p.isHostServerRunning, isFalse);
      p.dispose();
    });

    test('host listen addresses are exposed while running and cleared on stop', () async {
      final host = _FakeCompanionRemotePeerService();
      final harness = await _RemoteHarness.create(
        _FakePeerFactory([host]).call,
        discoveryServiceFactory: _FakeLanDiscoveryService.new,
      );
      addTearDown(harness.close);

      expect(harness.provider.hostServerAddresses, isEmpty);
      await harness.provider.startHostServer();
      expect(harness.provider.hostServerAddresses, ['127.0.0.1:48634']);

      await harness.provider.stopHostServer();
      expect(harness.provider.hostServerAddresses, isEmpty);
    });
  });

  group('CompanionRemoteProvider — live host identity refresh', () {
    test('a refresh still rebuilding when the provider is disposed does not restart the host', () async {
      final stack = await ProfileStack.create();
      addTearDown(stack.dispose);
      await stack.addServer('srv-a', testHousehold([('profile-a', 'A')], accountId: 'acct-a'));
      await stack.addServer('srv-b', testHousehold([('profile-b', 'B')], accountId: 'acct-b'));
      await stack.storage.setActiveProfileId('silo:srv-a/profile-a');
      await stack.active.reloadFromStorage();
      final second = stack.profile('srv-b', 'profile-b');

      final disconnectGate = Completer<void>();
      final host = _FakeCompanionRemotePeerService(disconnectGate: disconnectGate);
      final peers = _FakePeerFactory([host, _FakeCompanionRemotePeerService()]);
      final provider = CompanionRemoteProvider.forTesting(
        peerServiceFactory: peers.call,
        discoveryServiceFactory: _FakeLanDiscoveryService.new,
      );
      addTearDown(() {
        if (!disconnectGate.isCompleted) disconnectGate.complete();
        if (!provider.isDisposed) provider.dispose();
      });
      expect(await provider.ensureCryptoReady(connections: stack.connections, activeProfile: stack.active), isTrue);
      await provider.startHostServer();
      provider.bindProfileServices(
        connections: stack.connections,
        activeProfile: stack.active,
        households: stack.households,
      );
      // Let the watchers' initial emissions refresh an unchanged identity.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(provider.isHostServerRunning, isTrue);

      // A profile switch changes the identity: the refresh tears the host
      // down to rebuild, and the provider is disposed while it does.
      expect(await stack.active.activate(second), isTrue);
      await host.disconnectStarted.future;
      provider.dispose();
      disconnectGate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(peers.created, 1);
      expect(provider.isHostServerRunning, isFalse);
    });
  });

  group('CompanionRemoteProvider — host player state', () {
    test('a remote that pairs while the player is up is told it is active', () async {
      final host = _FakeCompanionRemotePeerService();
      final harness = await _RemoteHarness.create(
        _FakePeerFactory([host]).call,
        discoveryServiceFactory: _FakeLanDiscoveryService.new,
      );
      addTearDown(harness.close);
      await harness.provider.startHostServer();
      harness.provider.setHostPlayerActive(true);
      host.sentCommands.clear();

      host.emitDeviceConnected(RemoteDevice(id: 'phone', name: 'Phone', platform: 'ios', connectedAt: DateTime(2026)));

      expect(host.sentCommands.single.type, RemoteCommandType.syncState);
      expect(host.sentCommands.single.data, {'playerActive': true});

      harness.provider.setHostPlayerActive(false);
      host.sentCommands.clear();
      host.emitDeviceConnected(RemoteDevice(id: 'phone', name: 'Phone', platform: 'ios', connectedAt: DateTime(2026)));
      expect(host.sentCommands.single.data, {'playerActive': false});
    });
  });

  group('CompanionRemoteProvider — dispose hygiene', () {
    test('cancelReconnect on a fresh provider does not throw', () {
      final p = CompanionRemoteProvider();
      // No timer, no session — copyWith on null _session is a no-op so
      // status remains disconnected.
      expect(p.cancelReconnect, returnsNormally);
      expect(p.status, RemoteSessionStatus.disconnected);
      p.dispose();
    });

    test('leaveSession on a fresh provider does not throw', () async {
      final p = CompanionRemoteProvider();
      await p.leaveSession();
      expect(p.session, isNull);
      p.dispose();
    });

    test('safeNotifyListeners no-ops after dispose (deviceInfo race)', () async {
      // The constructor kicks off an async _initializeDeviceInfo() that calls
      // safeNotifyListeners() on completion. Disposing before that microtask
      // resolves must not throw — the disposable mixin should swallow it.
      final p = CompanionRemoteProvider();
      p.dispose();
      // Yield so any pending device-info callbacks complete.
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('CompanionRemoteProvider — reconnect ownership', () {
    test('newest overlapping connect owns the session and disposes the stale candidate once', () async {
      final firstJoinGate = Completer<void>();
      final firstDisposalGate = Completer<void>();
      final first = _FakeCompanionRemotePeerService(joinGate: firstJoinGate, disconnectGate: firstDisposalGate);
      final second = _FakeCompanionRemotePeerService();
      final factory = _FakePeerFactory([first, second]);
      final harness = await _RemoteHarness.create(factory.call);
      addTearDown(harness.close);

      final olderConnect = harness.provider.connectToManualHost('192.0.2.20:48634');
      await first.joinStarted.future;
      final newerConnect = harness.provider.connectToManualHost('192.0.2.21:48634');
      await first.disconnectStarted.future;
      firstJoinGate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(first.disposeCalls, 1);

      firstDisposalGate.complete();
      await second.joinStarted.future;
      await newerConnect;

      harness.provider.sendCommand(RemoteCommandType.playPause);
      expect(harness.provider.status, RemoteSessionStatus.connected);
      expect(second.sentCommands.single.type, RemoteCommandType.playPause);

      await olderConnect;

      expect(harness.provider.status, RemoteSessionStatus.connected);
      expect(first.disposeCalls, 1);
      expect(first.disconnectCalls, 1);
      expect(first.hasListeners, isFalse);
      expect(second.disposeCalls, 0);
      expect(factory.created, 2);
    });

    test('replacement disconnect reconnects while intentional predecessor teardown is blocked', () async {
      final predecessorDisposalGate = Completer<void>();
      final predecessor = _FakeCompanionRemotePeerService(disconnectGate: predecessorDisposalGate);
      final replacement = _FakeCompanionRemotePeerService();
      final factory = _FakePeerFactory([predecessor, replacement]);
      final harness = await _RemoteHarness.create(factory.call);
      addTearDown(harness.close);

      Future<void>? predecessorTeardown;
      addTearDown(() async {
        if (!predecessorDisposalGate.isCompleted) {
          predecessorDisposalGate.complete();
        }
        final teardown = predecessorTeardown;
        if (teardown != null) await teardown;
      });

      await harness.provider.connectToManualHost('192.0.2.22:48634');

      var teardownCompleted = false;
      predecessorTeardown = harness.provider.leaveSession().whenComplete(() {
        teardownCompleted = true;
      });
      await predecessor.disconnectStarted.future;
      expect(teardownCompleted, isFalse);

      await harness.provider.connectToManualHost('192.0.2.23:48634');
      expect(harness.provider.status, RemoteSessionStatus.connected);
      expect(replacement.hasListeners, isTrue);

      final publishedStatuses = <RemoteSessionStatus>[];
      void captureStatus() => publishedStatuses.add(harness.provider.status);
      harness.provider.addListener(captureStatus);

      predecessor.emitError(
        RemotePeerError(type: RemotePeerErrorType.connectionFailed, message: 'stale predecessor error'),
      );
      predecessor.emitDeviceDisconnected();

      expect(publishedStatuses, isEmpty);
      expect(harness.provider.status, RemoteSessionStatus.connected);
      expect(harness.provider.session?.errorMessage, isNull);
      expect(harness.provider.reconnectAttempts, 0);

      replacement.emitDeviceDisconnected();

      expect(publishedStatuses, [RemoteSessionStatus.reconnecting]);
      expect(harness.provider.status, RemoteSessionStatus.reconnecting);
      expect(harness.provider.reconnectAttempts, 1);
      expect(teardownCompleted, isFalse);

      predecessorDisposalGate.complete();
      await predecessorTeardown;

      expect(publishedStatuses, [RemoteSessionStatus.reconnecting]);
      expect(harness.provider.status, RemoteSessionStatus.reconnecting);
      expect(harness.provider.reconnectAttempts, 1);

      harness.provider.removeListener(captureStatus);
      await harness.provider.cancelReconnect();
    });

    test('cancelReconnect fully tears down a running host and discovery', () async {
      final hostDisposalGate = Completer<void>();
      final host = _FakeCompanionRemotePeerService(disconnectGate: hostDisposalGate);
      final discovery = _FakeLanDiscoveryService();
      final factory = _FakePeerFactory([host]);
      final harness = await _RemoteHarness.create(factory.call, discoveryServiceFactory: () => discovery);
      addTearDown(harness.close);

      await harness.provider.startHostServer();
      expect(harness.provider.isHostServerRunning, isTrue);
      expect(harness.provider.debugIsDiscoveryBroadcasting, isTrue);
      expect(host.hasListeners, isTrue);

      final cancellation = harness.provider.cancelReconnect();
      await host.disconnectStarted.future;
      expect(harness.provider.debugIsDiscoveryBroadcasting, isFalse);
      expect(host.hasListeners, isFalse);
      hostDisposalGate.complete();
      await cancellation;

      expect(harness.provider.session, isNull);
      expect(harness.provider.isHostServerRunning, isFalse);
      expect(harness.provider.debugIsDiscoveryBroadcasting, isFalse);
      expect(harness.provider.debugIsDiscoveryListening, isFalse);
      expect(discovery.stopBroadcastingCalls, 1);
      expect(discovery.stopListeningCalls, 1);
      expect(host.disposeCalls, 1);
      expect(host.disconnectCalls, 1);
      expect(host.hasListeners, isFalse);
    });

    test('cancel during join keeps disconnected state and disposes the candidate once', () async {
      final initial = _FakeCompanionRemotePeerService();
      final joinGate = Completer<void>();
      final candidate = _FakeCompanionRemotePeerService(joinGate: joinGate);
      final factory = _FakePeerFactory([initial, candidate]);
      final harness = await _RemoteHarness.create(factory.call);
      addTearDown(harness.close);
      await harness.provider.connectToManualHost('192.0.2.10:48634');

      final statuses = <RemoteSessionStatus>[];
      harness.provider.addListener(() => statuses.add(harness.provider.status));
      initial.emitDeviceDisconnected();
      expect(harness.provider.status, RemoteSessionStatus.reconnecting);

      final retry = harness.provider.retryReconnectNow();
      await candidate.joinStarted.future;
      expect(candidate.hasListeners, isTrue);

      final cancellation = harness.provider.cancelReconnect();
      expect(harness.provider.status, RemoteSessionStatus.disconnected);
      await cancellation;
      final statusCountAfterCancel = statuses.length;

      joinGate.complete();
      await retry;
      await Future<void>.delayed(Duration.zero);

      expect(harness.provider.status, RemoteSessionStatus.disconnected);
      expect(statuses.skip(statusCountAfterCancel), isNot(contains(RemoteSessionStatus.connected)));
      expect(candidate.disposeCalls, 1);
      expect(candidate.disconnectCalls, 1);
      expect(candidate.hasListeners, isFalse);
      expect(factory.created, 2);
      expect(harness.provider.reconnectAttempts, 0);
    });

    test('leave during join clears the session and rejects late commands', () async {
      final initial = _FakeCompanionRemotePeerService();
      final joinGate = Completer<void>();
      final candidate = _FakeCompanionRemotePeerService(joinGate: joinGate);
      final factory = _FakePeerFactory([initial, candidate]);
      final harness = await _RemoteHarness.create(factory.call);
      addTearDown(harness.close);
      await harness.provider.connectToManualHost('192.0.2.11:48634');

      var deliveredCommands = 0;
      harness.provider.onCommandReceived = (_) => deliveredCommands++;
      initial.emitDeviceDisconnected();
      final retry = harness.provider.retryReconnectNow();
      await candidate.joinStarted.future;

      await harness.provider.leaveSession();
      expect(harness.provider.session, isNull);
      expect(candidate.hasListeners, isFalse);
      candidate.emitCommand(const RemoteCommand(type: RemoteCommandType.playPause));
      joinGate.complete();
      await retry;

      expect(harness.provider.session, isNull);
      expect(deliveredCommands, 0);
      expect(candidate.disposeCalls, 1);
      expect(factory.created, 2);
      expect(harness.provider.reconnectAttempts, 0);
    });

    for (final action in ['cancel', 'leave']) {
      test('$action before candidate creation prevents replacement allocation', () async {
        final disconnectGate = Completer<void>();
        final initial = _FakeCompanionRemotePeerService(disconnectGate: disconnectGate);
        final replacement = _FakeCompanionRemotePeerService();
        final factory = _FakePeerFactory([initial, replacement]);
        final harness = await _RemoteHarness.create(factory.call);
        addTearDown(harness.close);
        await harness.provider.connectToManualHost('192.0.2.12:48634');

        initial.emitDeviceDisconnected();
        final retry = harness.provider.retryReconnectNow();
        await initial.disconnectStarted.future;

        if (action == 'cancel') {
          await harness.provider.cancelReconnect();
        } else {
          await harness.provider.leaveSession();
        }
        disconnectGate.complete();
        await retry;

        expect(factory.created, 1);
        expect(replacement.joinStarted.isCompleted, isFalse);
        expect(initial.disposeCalls, 1);
      });
    }

    test('dispose during join detaches listeners and prevents a late commit', () async {
      final initial = _FakeCompanionRemotePeerService();
      final joinGate = Completer<void>();
      final candidate = _FakeCompanionRemotePeerService(joinGate: joinGate);
      final factory = _FakePeerFactory([initial, candidate]);
      final harness = await _RemoteHarness.create(factory.call);
      addTearDown(harness.close);
      await harness.provider.connectToManualHost('192.0.2.13:48634');

      var deliveredCommands = 0;
      harness.provider.onCommandReceived = (_) => deliveredCommands++;
      initial.emitDeviceDisconnected();
      final retry = harness.provider.retryReconnectNow();
      await candidate.joinStarted.future;

      harness.provider.dispose();
      expect(harness.provider.isDisposed, isTrue);
      expect(candidate.hasListeners, isFalse);
      candidate.emitCommand(const RemoteCommand(type: RemoteCommandType.playPause));
      joinGate.complete();
      await retry;
      await Future<void>.delayed(Duration.zero);

      expect(harness.provider.status, isNot(RemoteSessionStatus.connected));
      expect(deliveredCommands, 0);
      expect(candidate.disposeCalls, 1);
      expect(factory.created, 2);
    });

    test('logout invalidates a held reconnect before clearing identity', () async {
      final initial = _FakeCompanionRemotePeerService();
      final joinGate = Completer<void>();
      final candidate = _FakeCompanionRemotePeerService(joinGate: joinGate);
      final factory = _FakePeerFactory([initial, candidate]);
      final harness = await _RemoteHarness.create(factory.call);
      addTearDown(harness.close);
      await harness.provider.connectToManualHost('192.0.2.14:48634');

      initial.emitDeviceDisconnected();
      final retry = harness.provider.retryReconnectNow();
      await candidate.joinStarted.future;

      await harness.provider.resetForLogout();
      expect(harness.provider.session, isNull);
      expect(harness.provider.isCryptoReady, isFalse);
      expect(harness.provider.debugCryptoConnectionId, isNull);
      expect(candidate.hasListeners, isFalse);

      joinGate.complete();
      await retry;

      expect(harness.provider.session, isNull);
      expect(harness.provider.isCryptoReady, isFalse);
      expect(candidate.disposeCalls, 1);
      expect(factory.created, 2);
      expect(harness.provider.reconnectAttempts, 0);
    });

    test('current reconnect failure is contained and schedules one retry', () async {
      final initial = _FakeCompanionRemotePeerService();
      final candidate = _FakeCompanionRemotePeerService(joinError: StateError('synthetic reconnect failure'));
      final factory = _FakePeerFactory([initial, candidate]);
      final harness = await _RemoteHarness.create(factory.call);
      addTearDown(harness.close);
      await harness.provider.connectToManualHost('192.0.2.15:48634');

      initial.emitDeviceDisconnected();
      await harness.provider.retryReconnectNow();

      expect(harness.provider.status, RemoteSessionStatus.reconnecting);
      expect(harness.provider.reconnectAttempts, 1);
      expect(candidate.disposeCalls, 1);
      expect(candidate.hasListeners, isFalse);

      await harness.provider.cancelReconnect();
    });

    test('successful current reconnect preserves connected behavior', () async {
      final initial = _FakeCompanionRemotePeerService();
      final candidate = _FakeCompanionRemotePeerService();
      final factory = _FakePeerFactory([initial, candidate]);
      final harness = await _RemoteHarness.create(factory.call);
      addTearDown(harness.close);
      await harness.provider.connectToManualHost('192.0.2.16:48634');

      initial.emitDeviceDisconnected();
      await harness.provider.retryReconnectNow();
      harness.provider.sendCommand(RemoteCommandType.playPause);

      expect(harness.provider.status, RemoteSessionStatus.connected);
      expect(harness.provider.reconnectAttempts, 0);
      expect(candidate.sentCommands.single.type, RemoteCommandType.playPause);
      expect(initial.disposeCalls, 1);
      expect(candidate.disposeCalls, 0);
    });
  });

  group('CompanionRemoteProvider — lifecycle and reconnect resilience', () {
    test('trailing peer status and error events do not end the reconnect cycle', () async {
      final initial = _FakeCompanionRemotePeerService();
      final factory = _FakePeerFactory([initial]);
      final harness = await _RemoteHarness.create(factory.call);
      addTearDown(harness.close);
      await harness.provider.connectToManualHost('192.0.2.30:48634');

      // The real peer emits deviceDisconnected followed by a disconnected
      // status, and a dying socket can surface a stale error; none of these
      // may knock the session out of reconnecting.
      initial.emitDeviceDisconnected();
      initial.emitStatus(RemoteSessionStatus.disconnected);
      initial.emitError(RemotePeerError(type: RemotePeerErrorType.connectionFailed, message: 'socket error'));

      expect(harness.provider.status, RemoteSessionStatus.reconnecting);
      expect(harness.provider.session?.errorMessage, isNull);
      expect(harness.provider.reconnectAttempts, 1);

      await harness.provider.cancelReconnect();
    });

    test('candidate status and error emissions during a failed reconnect attempt still reschedule', () async {
      final initial = _FakeCompanionRemotePeerService();
      final joinGate = Completer<void>();
      final candidate = _FakeCompanionRemotePeerService(
        joinGate: joinGate,
        joinError: StateError('synthetic reconnect failure'),
      );
      final factory = _FakePeerFactory([initial, candidate]);
      final harness = await _RemoteHarness.create(factory.call);
      addTearDown(harness.close);
      await harness.provider.connectToManualHost('192.0.2.35:48634');

      initial.emitDeviceDisconnected();
      final retry = harness.provider.retryReconnectNow();
      await candidate.joinStarted.future;

      // A joining candidate mirrors its own lifecycle into the session: a
      // transient connected knocks it out of `reconnecting`, and the dying
      // socket's error then stamps `error`.
      candidate.emitStatus(RemoteSessionStatus.connected);
      candidate.emitError(RemotePeerError(type: RemotePeerErrorType.connectionFailed, message: 'handshake died'));
      expect(harness.provider.status, isNot(RemoteSessionStatus.reconnecting));

      joinGate.complete();
      await retry;

      // Regression: rescheduling used to read the peer-overwritten session
      // status and ended the cycle after this single failed attempt. The
      // attempt's own captured intent must drive the reschedule.
      expect(harness.provider.reconnectAttempts, 1);

      await harness.provider.cancelReconnect();
    });

    test('a failed user-initiated connect does not schedule a reconnect', () async {
      final candidate = _FakeCompanionRemotePeerService(joinError: StateError('synthetic connect failure'));
      final factory = _FakePeerFactory([candidate]);
      final harness = await _RemoteHarness.create(factory.call);
      addTearDown(harness.close);

      await expectLater(harness.provider.connectToManualHost('192.0.2.36:48634'), throwsA(isA<StateError>()));

      // _scheduleReconnect arms synchronously, so a zero attempt count proves
      // the user-initiated failure surfaced as an error without a retry cycle.
      expect(harness.provider.status, RemoteSessionStatus.error);
      expect(harness.provider.reconnectAttempts, 0);
      expect(factory.created, 1);
    });

    test('disconnect while backgrounded defers retries until resume, then reconnects', () async {
      final initial = _FakeCompanionRemotePeerService();
      final candidate = _FakeCompanionRemotePeerService();
      final factory = _FakePeerFactory([initial, candidate]);
      final harness = await _RemoteHarness.create(factory.call);
      addTearDown(harness.close);
      await harness.provider.connectToManualHost('192.0.2.31:48634');

      harness.provider.didChangeAppLifecycleState(AppLifecycleState.paused);
      initial.emitDeviceDisconnected();

      // Backgrounded: the cycle is held open without burning the retry budget
      // or allocating a candidate that would fail against restricted network.
      expect(harness.provider.status, RemoteSessionStatus.reconnecting);
      expect(harness.provider.reconnectAttempts, 0);
      expect(factory.created, 1);

      harness.provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await candidate.joinStarted.future;
      await Future<void>.delayed(Duration.zero);

      expect(harness.provider.status, RemoteSessionStatus.connected);
      expect(harness.provider.reconnectAttempts, 0);
    });

    test('backgrounding pauses an armed backoff timer and resume retries with a fresh budget', () async {
      final initial = _FakeCompanionRemotePeerService();
      final candidate = _FakeCompanionRemotePeerService();
      final factory = _FakePeerFactory([initial, candidate]);
      final harness = await _RemoteHarness.create(factory.call);
      addTearDown(harness.close);
      await harness.provider.connectToManualHost('192.0.2.32:48634');

      initial.emitDeviceDisconnected();
      expect(harness.provider.reconnectAttempts, 1);

      harness.provider.didChangeAppLifecycleState(AppLifecycleState.paused);
      harness.provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await candidate.joinStarted.future;
      await Future<void>.delayed(Duration.zero);

      expect(harness.provider.status, RemoteSessionStatus.connected);
      expect(harness.provider.reconnectAttempts, 0);
    });

    test('resume pings a connected remote session to surface a dead socket', () async {
      final initial = _FakeCompanionRemotePeerService();
      final factory = _FakePeerFactory([initial]);
      final harness = await _RemoteHarness.create(factory.call);
      addTearDown(harness.close);
      await harness.provider.connectToManualHost('192.0.2.33:48634');

      harness.provider.didChangeAppLifecycleState(AppLifecycleState.paused);
      harness.provider.didChangeAppLifecycleState(AppLifecycleState.resumed);

      expect(initial.pingsSent, 1);
    });

    test('leave while a resume retry is pending prevents the retry', () async {
      final initial = _FakeCompanionRemotePeerService();
      final factory = _FakePeerFactory([initial]);
      final harness = await _RemoteHarness.create(factory.call);
      addTearDown(harness.close);
      await harness.provider.connectToManualHost('192.0.2.34:48634');

      harness.provider.didChangeAppLifecycleState(AppLifecycleState.paused);
      initial.emitDeviceDisconnected();
      await harness.provider.leaveSession();
      harness.provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);

      expect(harness.provider.session, isNull);
      // _FakePeerFactory throws on an unexpected allocation, so reaching here
      // proves no reconnect candidate was created.
      expect(factory.created, 1);
    });
  });

  group('CompanionRemoteProvider — public API safety', () {
    test('connectToDiscoveredHost reports localized auth failure when crypto is not ready', () async {
      final p = CompanionRemoteProvider();
      await expectLater(
        () => p.connectToManualHost('192.0.2.1:9999'),
        throwsA(
          isA<PeerError>().having((error) => error.message, 'message', t.companionRemote.pairing.cryptoInitFailed),
        ),
      );
      p.dispose();
    });
  });

  group('CompanionRemoteProvider — crypto identity', () {
    Future<ProfileStack> twoServers() async {
      final stack = await ProfileStack.create();
      addTearDown(stack.dispose);
      await stack.addServer('srv-a', testHousehold([('p-1', 'Owner'), ('p-2', 'Kids')], accountId: 'acct-a'));
      await stack.addServer('srv-b', testHousehold([('p-3', 'Den')], accountId: 'acct-b'));
      return stack;
    }

    test("the context is the active profile's server, account and profile", () async {
      final stack = await twoServers();
      await stack.storage.setActiveProfileId('silo:srv-a/p-2');
      await stack.active.reloadFromStorage();

      final provider = CompanionRemoteProvider();
      addTearDown(provider.dispose);
      expect(await provider.ensureCryptoReady(connections: stack.connections, activeProfile: stack.active), isTrue);

      expect(provider.debugCryptoConnectionId, 'silo:srv-a');
      expect(provider.debugCryptoConnectionIds, ['silo:srv-a']);
      expect(provider.debugCryptoProfileId, 'silo:srv-a/p-2');
      expect(provider.debugCryptoUserUuid, 'p-2');
    });

    test('ensureCryptoReady rebuilds when the active profile changes server', () async {
      final stack = await twoServers();
      await stack.storage.setActiveProfileId('silo:srv-a/p-1');
      await stack.active.reloadFromStorage();

      final provider = CompanionRemoteProvider();
      addTearDown(provider.dispose);
      expect(await provider.ensureCryptoReady(connections: stack.connections, activeProfile: stack.active), isTrue);
      expect(provider.debugCryptoConnectionId, 'silo:srv-a');

      expect(await stack.active.activate(stack.profile('srv-b', 'p-3')), isTrue);
      expect(await provider.ensureCryptoReady(connections: stack.connections, activeProfile: stack.active), isTrue);

      expect(provider.debugCryptoConnectionId, 'silo:srv-b');
      expect(provider.debugCryptoProfileId, 'silo:srv-b/p-3');
    });

    test('ensureCryptoReady is not ready without an active profile', () async {
      final stack = await twoServers();

      final provider = CompanionRemoteProvider();
      addTearDown(provider.dispose);

      expect(await provider.ensureCryptoReady(connections: stack.connections, activeProfile: stack.active), isFalse);
      expect(provider.isCryptoReady, isFalse);
    });

    test('ensureCryptoReady is not ready until the account id is known', () async {
      final stack = await ProfileStack.create();
      addTearDown(stack.dispose);
      final legacy = testSiloConnection('srv-a', accountId: '');
      await stack.connections.upsert(legacy);
      await stack.storage.setActiveProfileId('silo:srv-a/p-1');
      await stack.active.reloadFromStorage();

      final provider = CompanionRemoteProvider();
      addTearDown(provider.dispose);

      expect(await provider.ensureCryptoReady(connections: stack.connections, activeProfile: stack.active), isFalse);
    });

    test('the shared secret follows the Silo server and account, not the device', () async {
      final auth = RemoteAuthService.instance;
      final a = await auth.deriveSiloHomeSecret(serverId: 'srv-a', accountId: 'acct-a');
      final again = await auth.deriveSiloHomeSecret(serverId: 'srv-a', accountId: 'acct-a');
      final otherAccount = await auth.deriveSiloHomeSecret(serverId: 'srv-a', accountId: 'acct-b');
      final otherServer = await auth.deriveSiloHomeSecret(serverId: 'srv-b', accountId: 'acct-a');

      expect(auth.computeAuthContextId(again), auth.computeAuthContextId(a));
      expect(auth.computeAuthContextId(otherAccount), isNot(auth.computeAuthContextId(a)));
      expect(auth.computeAuthContextId(otherServer), isNot(auth.computeAuthContextId(a)));
    });

    test('resetForLogout clears crypto context', () async {
      final stack = await twoServers();
      await stack.storage.setActiveProfileId('silo:srv-a/p-1');
      await stack.active.reloadFromStorage();

      final provider = CompanionRemoteProvider();
      addTearDown(provider.dispose);
      await provider.ensureCryptoReady(connections: stack.connections, activeProfile: stack.active);
      expect(provider.isCryptoReady, isTrue);

      await provider.resetForLogout();

      expect(provider.isCryptoReady, isFalse);
      expect(provider.debugCryptoConnectionId, isNull);
      expect(provider.debugCryptoProfileId, isNull);
    });
  });
}

class _FakePeerFactory {
  _FakePeerFactory(this.peers);

  final List<_FakeCompanionRemotePeerService> peers;
  int created = 0;

  CompanionRemotePeerService call() {
    if (created >= peers.length) {
      throw StateError('Unexpected peer allocation');
    }
    return peers[created++];
  }
}

class _FakeCompanionRemotePeerService extends CompanionRemotePeerService {
  _FakeCompanionRemotePeerService({this.joinGate, this.disconnectGate, this.joinError});

  final Completer<void>? joinGate;
  final Completer<void>? disconnectGate;
  final Object? joinError;
  final Completer<void> joinStarted = Completer<void>();
  final Completer<void> disconnectStarted = Completer<void>();
  final List<RemoteCommand> sentCommands = [];

  final StreamController<RemoteCommand> _commands = StreamController<RemoteCommand>.broadcast(sync: true);
  final StreamController<RemoteDevice> _connected = StreamController<RemoteDevice>.broadcast(sync: true);
  final StreamController<void> _disconnected = StreamController<void>.broadcast(sync: true);
  final StreamController<RemotePeerError> _errors = StreamController<RemotePeerError>.broadcast(sync: true);
  final StreamController<RemoteSessionStatus> _statuses = StreamController<RemoteSessionStatus>.broadcast(sync: true);

  int disconnectCalls = 0;
  int disposeCalls = 0;
  bool _streamsClosed = false;
  bool _serverRunning = false;

  @override
  bool get isServerRunning => _serverRunning;

  bool get hasListeners =>
      _commands.hasListener ||
      _connected.hasListener ||
      _disconnected.hasListener ||
      _errors.hasListener ||
      _statuses.hasListener;

  @override
  Stream<RemoteCommand> get onCommandReceived => _commands.stream;

  @override
  Stream<RemoteDevice> get onDeviceConnected => _connected.stream;

  @override
  Stream<void> get onDeviceDisconnected => _disconnected.stream;

  @override
  Stream<RemotePeerError> get onError => _errors.stream;

  @override
  Stream<RemoteSessionStatus> get onConnectionStateChanged => _statuses.stream;

  @override
  String? get selectedAuthContextId => 'auth-context';

  @override
  String? get selectedHostClientId => 'host-client';

  @override
  Future<({List<String> addresses, int port})> createSessionForContexts(
    String deviceName,
    String platform,
    List<RemoteAuthContext> authContexts,
  ) async {
    _serverRunning = true;
    return (addresses: const ['127.0.0.1:48634'], port: 48634);
  }

  @override
  Future<void> joinSessionWithContexts(
    String deviceName,
    String platform,
    String hostAddress,
    List<RemoteAuthContext> authContexts, {
    String? authContextId,
    String expectedHostClientId = '',
  }) async {
    if (!joinStarted.isCompleted) joinStarted.complete();
    final gate = joinGate;
    if (gate != null) await gate.future;
    final error = joinError;
    if (error != null) throw error;
  }

  @override
  Future<String> joinSessionRacingWithContexts(
    String deviceName,
    String platform,
    List<String> hostAddresses,
    List<RemoteAuthContext> authContexts, {
    String? authContextId,
    String expectedHostClientId = '',
  }) async {
    await joinSessionWithContexts(
      deviceName,
      platform,
      hostAddresses.first,
      authContexts,
      authContextId: authContextId,
      expectedHostClientId: expectedHostClientId,
    );
    return hostAddresses.first;
  }

  @override
  void sendCommand(RemoteCommand command) {
    sentCommands.add(command);
  }

  int pingsSent = 0;

  @override
  void sendPing() {
    pingsSent++;
  }

  void emitDeviceConnected(RemoteDevice device) {
    if (!_streamsClosed) _connected.add(device);
  }

  void emitDeviceDisconnected() {
    if (!_streamsClosed) _disconnected.add(null);
  }

  void emitStatus(RemoteSessionStatus status) {
    if (!_streamsClosed) _statuses.add(status);
  }

  void emitCommand(RemoteCommand command) {
    if (!_streamsClosed) _commands.add(command);
  }

  void emitError(RemotePeerError error) {
    if (!_streamsClosed) _errors.add(error);
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    _serverRunning = false;
    if (!disconnectStarted.isCompleted) disconnectStarted.complete();
    final gate = disconnectGate;
    if (gate != null) await gate.future;
  }

  Future<void>? _disposeInFlight;

  /// Mirrors the real service's idempotent dispose (`_disposed` /
  /// `FutureCoalescer` dedup): only the first call tears down, concurrent
  /// and repeat calls join it. The provider relies on that contract instead of
  /// memoizing disposals itself, so [disposeCalls] counts effective disposals.
  @override
  Future<void> dispose() => _disposeInFlight ??= _disposeOnce();

  Future<void> _disposeOnce() async {
    disposeCalls++;
    await disconnect();
    if (_streamsClosed) return;
    _streamsClosed = true;
    await Future.wait([
      _commands.close(),
      _connected.close(),
      _disconnected.close(),
      _errors.close(),
      _statuses.close(),
    ]);
  }
}

class _FakeLanDiscoveryService extends LanDiscoveryService {
  bool _broadcasting = false;
  bool _listening = false;
  int stopBroadcastingCalls = 0;
  int stopListeningCalls = 0;

  @override
  bool get isBroadcasting => _broadcasting;

  @override
  bool get isListening => _listening;

  @override
  Future<void> startBroadcastingForContexts({
    required List<RemoteAuthContext> contexts,
    required String deviceName,
    required String platform,
    required int wsPort,
    required List<String> ips,
  }) async {
    _broadcasting = true;
  }

  @override
  Future<void> stopBroadcasting() async {
    stopBroadcastingCalls++;
    _broadcasting = false;
  }

  @override
  void stopListening() {
    stopListeningCalls++;
    _listening = false;
  }
}

class _RemoteHarness {
  _RemoteHarness({required this.provider, required this.stack});

  final CompanionRemoteProvider provider;
  final ProfileStack stack;
  bool _closed = false;

  static Future<_RemoteHarness> create(
    CompanionRemotePeerServiceFactory peerServiceFactory, {
    LanDiscoveryServiceFactory discoveryServiceFactory = LanDiscoveryService.new,
  }) async {
    final stack = await ProfileStack.create();

    await stack.addServer('remote-srv', testHousehold([('remote-profile', 'Remote')]));
    await stack.storage.setActiveProfileId('silo:remote-srv/remote-profile');
    await stack.active.reloadFromStorage();

    final provider = CompanionRemoteProvider.forTesting(
      peerServiceFactory: peerServiceFactory,
      discoveryServiceFactory: discoveryServiceFactory,
    );
    final ready = await provider.ensureCryptoReady(connections: stack.connections, activeProfile: stack.active);
    if (!ready) {
      throw StateError('Remote test harness failed to initialize crypto');
    }

    return _RemoteHarness(provider: provider, stack: stack);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (!provider.isDisposed) provider.dispose();
    await stack.dispose();
  }
}
