import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/providers/offline_mode_provider.dart';
import 'package:plezy/services/multi_server_manager.dart';

import '../test_helpers/multi_server_fixtures.dart';
import '../test_helpers/prefs.dart';

void main() {
  // OfflineModeProvider depends on a MultiServerManager. We instantiate one with
  // no connected servers — this exercises only the in-memory bookkeeping (id
  // maps + status stream) and never opens an HTTP socket. `initialize()` is
  // not driven here: its connectivity path is ConnectivityProbe, which has its
  // own coverage in test/services/connectivity_probe_test.dart, and the
  // snapshot-to-flags mapping is exercised through `applyConnectivityResults`.
  setUp(resetSharedPreferencesForTest);

  group('OfflineModeProvider', () {
    test('with empty manager: hasServerConnection=false but isOffline stays false during warmup', () {
      final manager = MultiServerManager();
      final p = OfflineModeProvider(manager);

      // Until [MultiServerManager] emits its first status snapshot, we don't
      // actually know whether the binder will connect anything — treating an
      // empty manager as offline causes the cold-start UI to flash the
      // offline state for the few hundred ms it takes to come up. Stay
      // optimistic.
      expect(p.hasNetworkConnection, isTrue);
      expect(p.hasServerConnection, isFalse);
      expect(p.isOffline, isFalse);

      p.dispose();
      manager.dispose();
    });

    test('reads online server IDs from the manager at construction', () {
      final manager = MultiServerManager();
      manager.updateServerStatus(ServerId('srv-1'), true);
      final p = OfflineModeProvider(manager);

      expect(p.hasServerConnection, isTrue);
      // Network is assumed up by default; both up → not offline.
      expect(p.isOffline, isFalse);

      p.dispose();
      manager.dispose();
    });

    test('all servers offline at construction → still warmup-optimistic until status emits', () {
      // updateServerStatus pushes to a broadcast controller — the provider
      // hasn't subscribed yet, so it never sees these events. After
      // construction `onlineServerIds` is empty (the same shape as a
      // fresh-cold-start manager), so we stay optimistic until the
      // provider's own listener catches an emission.
      final manager = MultiServerManager();
      manager.updateServerStatus(ServerId('srv-1'), false);
      manager.updateServerStatus(ServerId('srv-2'), false);
      final p = OfflineModeProvider(manager);

      expect(p.hasServerConnection, isFalse);
      expect(p.isOffline, isFalse);

      p.dispose();
      manager.dispose();
    });

    test('dispose marks provider as disposed; later notifies are no-ops', () {
      final manager = MultiServerManager();
      final p = OfflineModeProvider(manager);

      p.dispose();
      // After dispose, the disposable mixin guards against post-dispose notify.
      // We can't call private safeNotifyListeners, but `isDisposed` reflects state.
      expect(p.isDisposed, isTrue);

      manager.dispose();
    });

    test('warmup skipped when manager already has an online server at construction', () {
      // If the manager already has an online server when the provider is
      // built, we have ground truth — no need for the warmup window.
      // hasServerConnection reflects the manager's state and isOffline
      // is correctly false (network up + server up).
      final manager = MultiServerManager();
      manager.updateServerStatus(ServerId('srv'), true);
      final p = OfflineModeProvider(manager);

      expect(p.hasServerConnection, isTrue);
      expect(p.isOffline, isFalse);

      p.dispose();
      manager.dispose();
    });

    for (final (label, mark) in <(String, void Function(MultiServerManager, ServerId))>[
      ('auth-error', (m, id) => m.debugMarkAuthErrorForTesting(id)),
      ('access-denied', (m, id) => m.debugMarkAccessDeniedForTesting(id)),
    ]) {
      test('$label-only visible servers do not collapse to generic offline', () async {
        final manager = MultiServerManager();
        final client = _FakeClient(ServerId('refused-server'));
        manager.debugRegisterClientForTesting(client, online: false);
        final multi = testMultiServerProvider(manager);
        final p = OfflineModeProvider(manager, multiServerProvider: multi);
        await p.initialize();

        mark(manager, ServerId('refused-server'));
        await Future<void>.delayed(Duration.zero);

        expect(multi.refusedServerIds, contains('refused-server'));
        expect(p.isOffline, isFalse);

        p.dispose();
        multi.dispose();
        manager.dispose();
      });
    }

    test('expected but unreachable visible servers enter offline without live clients', () async {
      final manager = MultiServerManager();
      final multi = testMultiServerProvider(manager);
      final p = OfflineModeProvider(manager, multiServerProvider: multi);
      await p.initialize();
      manager.updateServerStatus(ServerId('silo-server'), false);
      await Future<void>.delayed(Duration.zero);
      expect(p.isOffline, isFalse);

      var notifications = 0;
      p.addListener(() => notifications++);

      multi.setExpectedVisibleServerIds({'silo-server'});
      multi.setVisibleServerIds(<String>{});
      await Future<void>.delayed(Duration.zero);

      expect(p.isOffline, isTrue);
      expect(notifications, 1);

      p.dispose();
      multi.dispose();
      manager.dispose();
    });

    test('expected but unreachable profile servers enter offline once visibility settles', () async {
      final manager = MultiServerManager();
      final multi = testMultiServerProvider(manager);
      final p = OfflineModeProvider(manager, multiServerProvider: multi);

      expect(p.isOffline, isFalse);

      var notifications = 0;
      p.addListener(() => notifications++);

      multi.setExpectedVisibleServerIds({'expected-server'});
      await Future<void>.delayed(Duration.zero);

      expect(p.isOffline, isFalse);
      expect(notifications, 0);

      multi.setVisibleServerIds(<String>{});
      await Future<void>.delayed(Duration.zero);

      expect(p.isOffline, isTrue);
      expect(notifications, 1);

      p.dispose();
      multi.dispose();
      manager.dispose();
    });

    group('connectivity transitions', () {
      test('regaining any network notifies even while servers stay unreachable', () async {
        final manager = MultiServerManager();
        final multi = testMultiServerProvider(manager);
        final p = OfflineModeProvider(manager, multiServerProvider: multi);
        // Settle visibility with nothing reachable, so offline is owned by
        // `noServerConnection` rather than the network flag or startup warmup.
        multi.setExpectedVisibleServerIds({'silo-server'});
        multi.setVisibleServerIds({'silo-server'});
        await Future<void>.delayed(Duration.zero);
        p.applyConnectivityResults(const [ConnectivityResult.none]);
        expect(p.hasNetworkConnection, isFalse);
        expect(p.isOffline, isTrue);

        var notifications = 0;
        p.addListener(() => notifications++);

        // Cellular comes back but no server is reachable, so neither the composite
        // offline state nor the WiFi/Ethernet flag moves. Consumers that only need
        // the internet — queued tracker history writes — still have to hear it.
        p.applyConnectivityResults(const [ConnectivityResult.mobile]);

        expect(p.hasNetworkConnection, isTrue);
        expect(p.hasWifiOrEthernet, isFalse);
        expect(p.isOffline, isTrue, reason: 'servers are still unreachable');
        expect(notifications, 1);

        p.dispose();
        multi.dispose();
        manager.dispose();
      });

      test('a reachable server keeps the app online while the OS reports no network (#2505)', () async {
        final manager = MultiServerManager();
        final multi = testMultiServerProvider(manager);
        final p = OfflineModeProvider(manager, multiServerProvider: multi);
        await p.initialize();
        multi.setExpectedVisibleServerIds({'loopback-server'});
        multi.setVisibleServerIds({'loopback-server'});
        manager.updateServerStatus(ServerId('loopback-server'), true);
        await Future<void>.delayed(Duration.zero);
        expect(p.isOffline, isFalse);

        var notifications = 0;
        p.addListener(() => notifications++);

        // A server on 127.0.0.1 (or a LAN without internet on Windows) stays
        // reachable when connectivity_plus reports `none`.
        p.applyConnectivityResults(const [ConnectivityResult.none]);
        expect(p.hasNetworkConnection, isFalse);
        expect(p.isOffline, isFalse);
        expect(notifications, 1, reason: 'internet-only consumers still hear the network loss');

        // Only the server actually becoming unreachable takes the app offline.
        manager.updateServerStatus(ServerId('loopback-server'), false);
        await Future<void>.delayed(Duration.zero);
        expect(p.isOffline, isTrue);

        p.dispose();
        multi.dispose();
        manager.dispose();
      });

      test('an unchanged connectivity snapshot notifies nobody', () async {
        final manager = MultiServerManager();
        final p = OfflineModeProvider(manager);
        p.applyConnectivityResults(const [ConnectivityResult.wifi]);

        var notifications = 0;
        p.addListener(() => notifications++);
        p.applyConnectivityResults(const [ConnectivityResult.wifi]);

        expect(notifications, isZero);

        p.dispose();
        manager.dispose();
      });

      test('isCellularOnly is true only for cellular with no WiFi/Ethernet fallback', () {
        final manager = MultiServerManager();
        final p = OfflineModeProvider(manager);

        // Not-yet-emitted results must read as not-cellular so playback falls
        // back to the general default quality.
        expect(p.isCellularOnly, isFalse);

        p.applyConnectivityResults(const [ConnectivityResult.mobile]);
        expect(p.isCellularOnly, isTrue);

        // A simultaneous WiFi (or Ethernet) link wins over cellular.
        p.applyConnectivityResults(const [ConnectivityResult.mobile, ConnectivityResult.wifi]);
        expect(p.isCellularOnly, isFalse);

        p.applyConnectivityResults(const [ConnectivityResult.mobile, ConnectivityResult.ethernet]);
        expect(p.isCellularOnly, isFalse);

        p.applyConnectivityResults(const [ConnectivityResult.wifi]);
        expect(p.isCellularOnly, isFalse);

        p.applyConnectivityResults(const [ConnectivityResult.none]);
        expect(p.isCellularOnly, isFalse);

        p.dispose();
        manager.dispose();
      });
    });
  });
}

class _FakeClient implements MediaServerClient {
  _FakeClient(this.serverId);

  @override
  final ServerId serverId;

  @override
  String? get serverName => 'Silo';

  @override
  MediaBackend get backend => MediaBackend.silo;

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
