import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/connection/connection_registry.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/profiles/active_profile_binder.dart';
import 'package:plezy/profiles/active_profile_provider.dart';
import 'package:plezy/profiles/profile.dart';
import 'package:plezy/profiles/silo_household_service.dart';
import 'package:plezy/screens/settings/connection_persistence.dart';
import 'package:plezy/services/storage_service.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';
import '../../test_helpers/profile_stack.dart';

enum _Activation { succeed, reject, fail }

class _ScriptedActiveProfileProvider extends ActiveProfileProvider {
  _ScriptedActiveProfileProvider({required super.households, required super.connections, required super.storage});

  _Activation activation = _Activation.succeed;

  @override
  Future<bool> activate(Profile profile) async {
    switch (activation) {
      case _Activation.succeed:
        return super.activate(profile);
      case _Activation.reject:
        return false;
      case _Activation.fail:
        throw StateError('synthetic activation failure');
    }
  }
}

class _Binder implements ActiveProfileBinder {
  final List<String> events = [];

  @override
  void markUserInitiatedActivation(String profileId) => events.add('mark:$profileId');

  @override
  Future<void> rebindIfActive(String profileId) async => events.add('rebind:$profileId');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  _Harness(this.db, this.connections, this.households, this.active, this.storage, this.binder);

  final AppDatabase db;
  final ConnectionRegistry connections;
  final SiloHouseholdService households;
  final _ScriptedActiveProfileProvider active;
  final StorageService storage;
  final _Binder binder;
  late BuildContext context;

  static Future<_Harness> create() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final connections = ConnectionRegistry(db);
    final households = SiloHouseholdService(connections: connections, loader: (_) async => null);
    final storage = await StorageService.getInstance();
    final active = _ScriptedActiveProfileProvider(households: households, connections: connections, storage: storage);
    await active.initialize();
    return _Harness(db, connections, households, active, storage, _Binder());
  }

  Widget app({Widget? child}) => MultiProvider(
    providers: [
      Provider<ConnectionRegistry>.value(value: connections),
      Provider<SiloHouseholdService>.value(value: households),
      ChangeNotifierProvider<ActiveProfileProvider>.value(value: active),
      Provider<ActiveProfileBinder>.value(value: binder),
      Provider<StorageService>.value(value: storage),
    ],
    child: MaterialApp(
      home:
          child ??
          Builder(
            builder: (context) {
              this.context = context;
              return const SizedBox.shrink();
            },
          ),
    ),
  );

  Future<void> dispose() async {
    await active.resetForTesting();
    active.dispose();
    households.dispose();
    await db.close();
  }
}

final _household = testHousehold([('p-1', 'Owner'), ('p-2', 'Kids')], accountId: 'acct-7');

void main() {
  setUp(resetSharedPreferencesForTest);

  Future<_Harness> pump(WidgetTester tester) async {
    final harness = (await tester.runAsync(_Harness.create))!;
    addTearDown(() => tester.runAsync(harness.dispose));
    await tester.pumpWidget(harness.app());
    return harness;
  }

  testWidgets('a first sign-in stores the connection, caches the household and enters the profile', (tester) async {
    final harness = await pump(tester);
    final connection = testSiloConnection('srv', accountId: 'acct-7');

    await tester.runAsync(
      () => persistSiloSignIn(
        context: harness.context,
        connection: connection,
        household: _household,
        entered: _household.profiles[1],
      ),
    );

    final stored = await tester.runAsync(() => harness.connections.get(connection.id));
    expect(stored, isA<SiloConnection>().having((c) => c.accountId, 'accountId', 'acct-7'));
    expect(harness.households.current[connection.id]?.profiles.map((p) => p.id), ['p-1', 'p-2']);
    expect(harness.active.activeId, 'silo:srv/p-2');
    expect(harness.storage.getActiveProfileId(), 'silo:srv/p-2');
    expect(harness.binder.events, ['mark:silo:srv/p-2'], reason: 'a first sign-in has no stale binding to redo');
  });

  testWidgets('signing in again to a stored server rebinds the active profile', (tester) async {
    final harness = await pump(tester);
    final connection = testSiloConnection('srv', accountId: 'acct-7');
    await tester.runAsync(() => harness.connections.upsert(connection));

    await tester.runAsync(
      () => persistSiloSignIn(
        context: harness.context,
        connection: connection,
        household: _household,
        entered: _household.profiles.first,
      ),
    );

    expect(harness.binder.events, ['mark:silo:srv/p-1', 'rebind:silo:srv/p-1']);
  });

  testWidgets('a rejected activation removes the new connection and restores the active marker', (tester) async {
    final harness = await pump(tester);
    await tester.runAsync(() => harness.storage.setActiveProfileId('silo:other/p-9'));
    harness.active.activation = _Activation.reject;
    final connection = testSiloConnection('srv');

    final error = await tester.runAsync(() async {
      try {
        await persistSiloSignIn(
          context: harness.context,
          connection: connection,
          household: _household,
          entered: _household.profiles.first,
        );
        return null;
      } on StateError catch (error) {
        return error;
      }
    });

    expect(error, isNotNull);
    expect(await tester.runAsync(() => harness.connections.get(connection.id)), isNull);
    expect(harness.storage.getActiveProfileId(), 'silo:other/p-9');
  });

  testWidgets('a failed activation restores the prior same-id connection', (tester) async {
    final harness = await pump(tester);
    final prior = testSiloConnection('srv', accountId: 'acct-old');
    await tester.runAsync(() => harness.connections.upsert(prior));
    harness.active.activation = _Activation.fail;

    final error = await tester.runAsync(() async {
      try {
        await persistSiloSignIn(
          context: harness.context,
          connection: testSiloConnection('srv', accountId: 'acct-7'),
          household: _household,
          entered: _household.profiles.first,
        );
        return null;
      } on StateError catch (error) {
        return error;
      }
    });

    expect(error, isNotNull);
    final stored = await tester.runAsync(() => harness.connections.get(prior.id));
    expect(stored, isA<SiloConnection>().having((c) => c.accountId, 'accountId', 'acct-old'));
    expect(harness.storage.getActiveProfileId(), isNull);
  });

  testWidgets('the command completes after its route unmounts', (tester) async {
    final harness = await pump(tester);
    final connection = testSiloConnection('srv');

    // Started in the real zone (drift work never completes in fake async),
    // wrapped so runAsync hands the future back unawaited.
    final pending = (await tester.runAsync(
      () async => (
        persistSiloSignIn(
          context: harness.context,
          connection: connection,
          household: _household,
          entered: _household.profiles.first,
        ),
      ),
    ))!.$1;
    await tester.pumpWidget(harness.app(child: const SizedBox.shrink()));
    await tester.runAsync(() => pending);

    expect(harness.active.activeId, 'silo:srv/p-1');
    expect(await tester.runAsync(() => harness.connections.get(connection.id)), isNotNull);
  });
}
