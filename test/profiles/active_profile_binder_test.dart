import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/profiles/active_profile_binder.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/services/multi_server_manager.dart';

import '../test_helpers/multi_server_fixtures.dart';
import '../test_helpers/prefs.dart';
import '../test_helpers/profile_stack.dart';

/// Records Silo binds instead of reaching a server.
class _Manager extends MultiServerManager {
  final List<(String, String)> binds = [];
  final Map<String, bool> reachable = {};
  final Set<String> refused = {};
  final Set<String> registered = {};
  final List<String> removed = [];
  Completer<void>? gate;

  @override
  Future<bool> addSiloConnection(SiloConnection connection, {required String profileId}) async {
    binds.add((connection.serverId, profileId));
    await gate?.future;
    registered.add(connection.serverId);
    return reachable[connection.serverId] ?? true;
  }

  @override
  Set<String> get refusedServerIds => refused;

  @override
  List<String> get registeredServerIds => registered.toList();

  @override
  bool isRegisteredForOtherProfile(ServerId serverId, {required String profileId}) => false;

  @override
  void removeServer(ServerId serverId) {
    registered.remove(serverId);
    removed.add(serverId);
  }
}

void main() {
  late ProfileStack stack;
  late _Manager manager;
  late MultiServerProvider multi;
  late ActiveProfileBinder binder;

  ActiveProfileBinder createBinder({ShouldDeferInitialBind? defer}) => ActiveProfileBinder(
    activeProfile: stack.active,
    connections: stack.connections,
    serverManager: manager,
    multiServerProvider: multi,
    shouldDeferInitialBind: defer,
  );

  setUp(() async {
    resetSharedPreferencesForTest();
    stack = await ProfileStack.create();
    manager = _Manager();
    multi = testMultiServerProvider(manager);
    await stack.addServer('srv-a', testHousehold([('p-1', 'Owner'), ('p-2', 'Kids')]));
    await stack.addServer('srv-b', testHousehold([('p-3', 'Den')]));
    binder = createBinder();
  });

  tearDown(() async {
    binder.dispose();
    multi.dispose();
    manager.dispose();
    await stack.dispose();
  });

  Future<void> activate(String serverId, String profileId) async {
    expect(await stack.active.activate(stack.profile(serverId, profileId)), isTrue);
  }

  test('no active profile binds nothing and settles successfully', () async {
    binder.start();
    expect(await stack.active.awaitBindingSettle(), isTrue);
    expect(manager.binds, isEmpty);
    expect(multi.serverIds, isEmpty);
  });

  test('start() marks binding synchronously so first-frame readers see it', () async {
    binder.start();
    expect(stack.active.isBinding, isTrue);
    await stack.active.awaitBindingSettle();
    expect(stack.active.isBinding, isFalse);
  });

  test('disposing before the initial rebind microtask clears the binding flag', () async {
    binder.start();
    binder.dispose();
    await pumpEventQueue();
    expect(stack.active.isBinding, isFalse);
  });

  test('binds only the active profile on its own server, with its profile id', () async {
    await activate('srv-a', 'p-2');
    binder.start();
    expect(await stack.active.awaitBindingSettle(), isTrue);

    expect(manager.binds, [('srv-a', 'p-2')]);
    expect(multi.expectedServerIds, ['srv-a']);
  });

  test('switching to a profile on another server drops the previous server', () async {
    await activate('srv-a', 'p-1');
    binder.start();
    await stack.active.awaitBindingSettle();

    await activate('srv-b', 'p-3');
    expect(await stack.active.awaitBindingSettle(), isTrue);

    expect(manager.binds, [('srv-a', 'p-1'), ('srv-b', 'p-3')]);
    expect(manager.removed, contains('srv-a'));
    expect(manager.registered, {'srv-b'});
    expect(multi.expectedServerIds, ['srv-b']);
  });

  test('an unreachable server fails the bind as connectivity-only', () async {
    manager.reachable['srv-a'] = false;
    await activate('srv-a', 'p-1');
    binder.start();

    expect(await stack.active.awaitBindingSettle(), isFalse);
    expect(binder.lastBindFailureConnectivityOnly, isTrue);
    expect(multi.expectedServerIds, ['srv-a'], reason: 'the profile still expects its server');
  });

  test('a refusing server still counts as bound so the refusal is what shows', () async {
    manager.reachable['srv-a'] = false;
    manager.refused.add('srv-a');
    await activate('srv-a', 'p-1');
    binder.start();

    expect(await stack.active.awaitBindingSettle(), isTrue);
    expect(binder.lastBindFailureConnectivityOnly, isFalse);
  });

  test('a later successful cycle resets the classification', () async {
    manager.reachable['srv-a'] = false;
    await activate('srv-a', 'p-1');
    binder.start();
    await stack.active.awaitBindingSettle();
    expect(binder.lastBindFailureConnectivityOnly, isTrue);

    manager.reachable['srv-a'] = true;
    await binder.rebindActive();

    expect(stack.active.lastBindingSucceeded, isTrue);
    expect(binder.lastBindFailureConnectivityOnly, isFalse);
  });

  test('passive notifications do not retry a failed profile; explicit rebind does', () async {
    manager.reachable['srv-a'] = false;
    await activate('srv-a', 'p-1');
    binder.start();
    await stack.active.awaitBindingSettle();
    expect(manager.binds, hasLength(1));

    await stack.households.put(testSiloConnection('srv-a'), testHousehold([('p-1', 'Owner'), ('p-2', 'Kids')]));
    await pumpEventQueue();
    expect(manager.binds, hasLength(1));

    await binder.rebindActive();
    expect(manager.binds, hasLength(2));
  });

  test('a profile whose server was signed out fails without binding', () async {
    await activate('srv-a', 'p-1');
    await stack.connections.remove('silo:srv-a');
    await stack.storage.setActiveProfileId('silo:srv-a/p-1');
    binder.start();

    expect(await stack.active.awaitBindingSettle(), isFalse);
    expect(manager.binds, isEmpty);
  });

  test('initial bind can be deferred until profile selection', () async {
    await activate('srv-a', 'p-1');
    binder.dispose();
    binder = createBinder(defer: (_) => true);
    binder.start();

    expect(await stack.active.awaitBindingSettle(), isTrue);
    expect(manager.binds, isEmpty);
  });

  test('user initiated activation bypasses initial bind defer', () async {
    binder.dispose();
    binder = createBinder(defer: (_) => true);
    binder.markUserInitiatedActivation('silo:srv-a/p-1');
    await activate('srv-a', 'p-1');
    binder.start();

    await stack.active.awaitBindingSettle();
    expect(manager.binds, [('srv-a', 'p-1')]);
  });

  test('A to B to A during one pass forces a complete final A bind', () async {
    await activate('srv-a', 'p-1');
    manager.gate = Completer<void>();
    binder.start();
    await pumpEventQueue();
    expect(manager.binds, [('srv-a', 'p-1')]);

    await activate('srv-b', 'p-3');
    await activate('srv-a', 'p-1');
    manager.gate!.complete();
    manager.gate = null;
    expect(await stack.active.awaitBindingSettle(), isTrue);

    expect(manager.binds.last, ('srv-a', 'p-1'));
    expect(manager.binds, hasLength(2), reason: 'the same-id rebind must run once more, not loop');
    expect(binder.debugLastBoundProfileId, 'silo:srv-a/p-1');
  });
}
