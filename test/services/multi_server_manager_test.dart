import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/silo_client.dart';

import '../test_helpers/fake_silo_server.dart';
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

  group('health probe classification', () {
    Future<SiloClient> siloClient(FakeHandler handler) async {
      final (session, _) = await signedInSession();
      final client = SiloClient(
        connection: SiloConnection(
          origin: siloTestOrigin.toString(),
          serverId: 'silo-server',
          serverName: 'Silo',
          username: 'alice',
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
        profileId: 'p-1',
        http: siloHttpFor(FakeSilo(handler), session),
      );
      addTearDown(client.close);
      return client;
    }

    test('a successful probe keeps an authenticated server online', () async {
      final manager = MultiServerManager(connectivityChanges: () => const Stream.empty());
      addTearDown(manager.dispose);
      manager.debugRegisterClientForTesting(await siloClient((_) => jsonResponse({}, 200)));

      final emitted = <Map<String, bool>>[];
      final sub = manager.statusStream.listen(emitted.add);
      addTearDown(sub.cancel);

      await manager.checkServerHealth();
      await Future<void>.delayed(Duration.zero);

      expect(manager.isServerOnline(ServerId('silo-server')), isTrue);
      expect(manager.authErrorServerIds, isEmpty);
      expect(emitted, isEmpty, reason: 'a successful health probe must not publish a false offline transition');
    });

    test('auth rejection is published as an auth error', () async {
      final manager = MultiServerManager(connectivityChanges: () => const Stream.empty());
      addTearDown(manager.dispose);
      manager.debugRegisterClientForTesting(await siloClient((_) => jsonResponse({}, 401)));

      final emitted = <Map<String, bool>>[];
      final sub = manager.statusStream.listen(emitted.add);
      addTearDown(sub.cancel);

      await manager.checkServerHealth();
      await Future<void>.delayed(Duration.zero);

      expect(manager.isServerOnline(ServerId('silo-server')), isFalse);
      expect(manager.authErrorServerIds, {'silo-server'});
      expect(emitted, [
        {'silo-server': false},
      ]);
    });

    test('an account refusal (403) is published as access denied, not as a sign-in prompt', () async {
      final manager = MultiServerManager(connectivityChanges: () => const Stream.empty());
      addTearDown(manager.dispose);
      manager.debugRegisterClientForTesting(await siloClient((_) => jsonResponse({}, 403)));

      final emitted = <Map<String, bool>>[];
      final sub = manager.statusStream.listen(emitted.add);
      addTearDown(sub.cancel);

      await manager.checkServerHealth();
      await Future<void>.delayed(Duration.zero);

      expect(manager.isServerOnline(ServerId('silo-server')), isFalse);
      expect(manager.accessDeniedServerIds, {'silo-server'});
      expect(manager.authErrorServerIds, isEmpty, reason: 'a new sign-in gets the same refusal');
      expect(emitted, [
        {'silo-server': false},
      ]);
    });
  });

  group('connectivity monitoring', () {
    test(
      'connectivity monitoring is lazy, singular, and coalesces every change, none included, for two seconds',
      () async {
        final connectivity = _DirectConnectivityStream();
        final client = _ProbeClient('monitor-server');
        final manager = MultiServerManager(connectivityChanges: () => connectivity);
        addTearDown(manager.dispose);

        manager.debugRegisterClientForTesting(client, online: false);
        expect(connectivity.listenCount, 0);

        await manager.checkServerHealth();
        expect(manager.isServerOnline(ServerId('monitor-server')), isTrue);
        expect(connectivity.listenCount, 1);

        await manager.checkServerHealth();
        expect(connectivity.listenCount, 1);
        expect(client.probes, 2);

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
          expect(client.probes, 2);
          async.elapse(const Duration(milliseconds: 1));
          async.flushMicrotasks();
          expect(client.probes, 3);

          connectivity.add([ConnectivityResult.none]);
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 2));
          async.flushMicrotasks();

          expect(client.probes, 4);
          expect(connectivity.cancelCount, 0);
        });

        manager.dispose();
        expect(connectivity.cancelCount, 1);
      },
    );

    test('losing the network keeps a reachable server online and drops an unreachable one (#2505)', () async {
      var remoteReachable = true;
      final loopback = _ProbeClient('silo-loopback');
      final remote = _ProbeClient(
        'silo-remote',
        probe: () async => remoteReachable ? HealthStatus.online : HealthStatus.offline,
      );
      final connectivity = _DirectConnectivityStream();
      final manager = MultiServerManager(
        connectivityChanges: () => connectivity,
        connectivityDebounceDuration: Duration.zero,
      );
      addTearDown(manager.dispose);

      manager.debugRegisterClientForTesting(loopback, online: false);
      manager.debugRegisterClientForTesting(remote, online: false);
      await manager.checkServerHealth();
      expect(manager.isServerOnline(ServerId('silo-loopback')), isTrue);
      expect(manager.isServerOnline(ServerId('silo-remote')), isTrue);
      expect(connectivity.listenCount, 1);

      // The adapter goes down: the remote server loses its route, the
      // loopback one does not, and connectivity_plus reports `none`.
      remoteReachable = false;
      final remoteDropped = manager.statusStream.firstWhere((status) => status['silo-remote'] == false);
      connectivity.add(const [ConnectivityResult.none]);
      await remoteDropped.timeout(const Duration(seconds: 5));

      expect(manager.isServerOnline(ServerId('silo-remote')), isFalse);
      expect(manager.isServerOnline(ServerId('silo-loopback')), isTrue);
    });

    test('a server recovered by a health probe is re-probed when the network drops (#2505)', () async {
      var reachable = true;
      final client = _ProbeClient(
        'silo-server',
        probe: () async => reachable ? HealthStatus.online : HealthStatus.offline,
      );
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
      expect(manager.isServerOnline(ServerId('silo-server')), isTrue);

      reachable = false;
      final dropped = manager.statusStream.firstWhere((status) => status['silo-server'] == false);
      connectivity.add(const [ConnectivityResult.none]);
      await dropped.timeout(const Duration(seconds: 5));

      expect(manager.isServerOnline(ServerId('silo-server')), isFalse);
    });

    test('dispose cancels a pending connectivity debounce with no later mutation', () async {
      final connectivity = _DirectConnectivityStream();
      final client = _ProbeClient('pending-server');
      final manager = MultiServerManager(connectivityChanges: () => connectivity);
      manager.debugRegisterClientForTesting(client, online: false);
      await manager.checkServerHealth();
      expect(manager.isServerOnline(ServerId('pending-server')), isTrue);

      fakeAsync((async) {
        connectivity.add([ConnectivityResult.wifi]);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        manager.dispose();
        async.flushMicrotasks();
        final probesAfterDispose = client.probes;

        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();

        expect(connectivity.cancelCount, 1);
        expect(client.probes, probesAfterDispose);
        expect(manager.serverIds, isEmpty);
        expect(manager.onlineServerIds, isEmpty);
      });
    });
  });

  group('checkServerHealth', () {
    test('a probe result from a client replaced mid-probe is not applied', () async {
      final probeStarted = Completer<void>();
      final probeResult = Completer<HealthStatus>();
      final original = _ProbeClient(
        'server-1',
        probe: () {
          if (!probeStarted.isCompleted) probeStarted.complete();
          return probeResult.future;
        },
      );
      final replacement = _ProbeClient('server-1');
      final manager = MultiServerManager(connectivityChanges: () => const Stream.empty());
      addTearDown(manager.dispose);
      manager.debugRegisterClientForTesting(original);

      final health = manager.checkServerHealth();
      await probeStarted.future;
      // A profile switch: the old client is removed and the new profile's
      // client is bound under the same server id before the old probe lands.
      manager.removeServer(ServerId('server-1'));
      manager.debugRegisterClientForTesting(replacement);
      probeResult.complete(HealthStatus.offline);
      await health;

      expect(original.closed, isTrue);
      expect(manager.getClient(ServerId('server-1')), same(replacement));
      expect(manager.isServerOnline(ServerId('server-1')), isTrue);
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

/// A Silo-shaped client whose health probe the test scripts, counting probes.
class _ProbeClient implements MediaServerClient, ScopedMediaServerClient {
  _ProbeClient(String id, {Future<HealthStatus> Function()? probe})
    : serverId = ServerId(id),
      _probe = probe ?? (() async => HealthStatus.online);

  final Future<HealthStatus> Function() _probe;
  int probes = 0;
  bool closed = false;

  @override
  final ServerId serverId;

  @override
  String get scopedServerId => 'silo:$serverId/p-1';

  @override
  String? get serverName => '$serverId';

  @override
  MediaBackend get backend => MediaBackend.silo;

  @override
  Future<HealthStatus> checkHealth() {
    probes++;
    return _probe();
  }

  @override
  void close() => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
