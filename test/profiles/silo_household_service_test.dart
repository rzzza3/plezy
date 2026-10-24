import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/connection/connection_registry.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/profiles/silo_household_service.dart';
import 'package:plezy/silo/silo_profiles.dart';

import '../test_helpers/prefs.dart';
import '../test_helpers/profile_stack.dart';

void main() {
  late AppDatabase db;
  late ConnectionRegistry connections;
  late SiloHousehold household;
  late int loads;
  late Completer<void>? gate;
  late SiloHouseholdService service;

  SiloHouseholdService create() => SiloHouseholdService(
    connections: connections,
    loader: (_) async {
      loads++;
      await gate?.future;
      return household;
    },
  );

  setUp(() {
    resetSharedPreferencesForTest();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    connections = ConnectionRegistry(db);
    household = testHousehold([('p1', 'Owner'), ('p2', 'Kids')], accountId: 'acct-9');
    loads = 0;
    gate = null;
    service = create();
  });

  tearDown(() async {
    service.dispose();
    await db.close();
  });

  test('refresh completes, caches the household and backfills the account id', () async {
    final connection = testSiloConnection('srv-a', accountId: '');
    await connections.upsert(connection);

    final read = await service.refresh(connection).timeout(const Duration(seconds: 5));

    expect(read?.profiles.map((p) => p.id), ['p1', 'p2']);
    expect(service.current[connection.id]?.account.id, 'acct-9');
    expect(await connections.get(connection.id), isA<SiloConnection>().having((c) => c.accountId, 'id', 'acct-9'));
  });

  test('concurrent refreshes of one server share a read', () async {
    final connection = testSiloConnection('srv-a');
    await connections.upsert(connection);
    gate = Completer<void>();

    final first = service.refresh(connection);
    final second = service.refresh(connection);
    gate!.complete();
    await Future.wait([first, second]);

    expect(loads, 1);
    await service.refresh(connection);
    expect(loads, 2, reason: 'a settled read is not reused');
  });

  test('a cold start hydrates the cached household without reading the server', () async {
    final connection = testSiloConnection('srv-a');
    await connections.upsert(connection);
    await service.put(connection, household);
    service.dispose();

    service = create();
    await service.hydrate();

    expect(service.current[connection.id]?.profiles.map((p) => p.name), ['Owner', 'Kids']);
    expect(loads, 0);
  });

  test('clearAll drops a read that was in flight', () async {
    final connection = testSiloConnection('srv-a');
    await connections.upsert(connection);
    gate = Completer<void>();

    final read = service.refresh(connection);
    await service.clearAll();
    gate!.complete();

    expect(await read, isNull);
    expect(service.current, isEmpty);
  });

  test('a signed-out server leaves the cache once the service follows connections', () async {
    final connection = testSiloConnection('srv-a');
    await connections.upsert(connection);
    await service.put(connection, household);
    await service.start();

    await connections.remove(connection.id);
    await pumpEventQueue();

    expect(service.current, isEmpty);
  });
}
