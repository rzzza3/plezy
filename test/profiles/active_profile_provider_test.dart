import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/profiles/active_profile_provider.dart';
import 'package:plezy/services/storage_service.dart';
import 'package:plezy/silo/silo_profiles.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import '../test_helpers/prefs.dart';
import '../test_helpers/profile_stack.dart';

final class _RecordingPreferencesPlatform extends SharedPreferencesAsyncPlatform {
  _RecordingPreferencesPlatform(this.delegate);

  final SharedPreferencesAsyncPlatform delegate;
  final List<String> writes = [];
  String? failIntKey;

  @override
  Future<void> setString(String key, String value, SharedPreferencesOptions options) async {
    writes.add('string:$key');
    await delegate.setString(key, value, options);
  }

  @override
  Future<void> setInt(String key, int value, SharedPreferencesOptions options) async {
    writes.add('int:$key');
    if (key == failIntKey) throw StateError('injected recency failure');
    await delegate.setInt(key, value, options);
  }

  @override
  Future<void> setBool(String key, bool value, SharedPreferencesOptions options) =>
      delegate.setBool(key, value, options);

  @override
  Future<void> setDouble(String key, double value, SharedPreferencesOptions options) =>
      delegate.setDouble(key, value, options);

  @override
  Future<void> setStringList(String key, List<String> value, SharedPreferencesOptions options) =>
      delegate.setStringList(key, value, options);

  @override
  Future<String?> getString(String key, SharedPreferencesOptions options) => delegate.getString(key, options);

  @override
  Future<bool?> getBool(String key, SharedPreferencesOptions options) => delegate.getBool(key, options);

  @override
  Future<double?> getDouble(String key, SharedPreferencesOptions options) => delegate.getDouble(key, options);

  @override
  Future<int?> getInt(String key, SharedPreferencesOptions options) => delegate.getInt(key, options);

  @override
  Future<List<String>?> getStringList(String key, SharedPreferencesOptions options) =>
      delegate.getStringList(key, options);

  @override
  Future<void> clear(ClearPreferencesParameters parameters, SharedPreferencesOptions options) =>
      delegate.clear(parameters, options);

  @override
  Future<Map<String, Object>> getPreferences(GetPreferencesParameters parameters, SharedPreferencesOptions options) =>
      delegate.getPreferences(parameters, options);

  @override
  Future<Set<String>> getKeys(GetPreferencesParameters parameters, SharedPreferencesOptions options) =>
      delegate.getKeys(parameters, options);
}

void main() {
  late _RecordingPreferencesPlatform preferencesPlatform;
  late ProfileStack stack;
  late ActiveProfileProvider provider;
  late StorageService storage;

  final household = testHousehold([('p1', 'Owner'), ('p2', 'Kids')]);

  setUp(() async {
    resetSharedPreferencesForTest();
    preferencesPlatform = _RecordingPreferencesPlatform(SharedPreferencesAsyncPlatform.instance!);
    SharedPreferencesAsyncPlatform.instance = preferencesPlatform;
    stack = await ProfileStack.create();
    provider = stack.active;
    storage = stack.storage;
  });

  tearDown(() => stack.dispose());

  group('ActiveProfileProvider', () {
    test('initialize with no servers leaves active null', () async {
      await provider.initialize();
      expect(provider.profiles, isEmpty);
      expect(provider.active, isNull);
    });

    test('concurrent initialize calls await the same in-flight load', () async {
      final first = provider.initialize();
      final second = provider.initialize();
      expect(identical(first, second), isTrue);
      await Future.wait([first, second]);
      expect(provider.isInitialized, isTrue);
    });

    test("lists each signed-in server's household as Silo profiles", () async {
      await provider.initialize();
      await stack.addServer('srv-a', household);
      await stack.addServer('srv-b', testHousehold([('k1', 'Den')]));

      expect(provider.profiles.map((p) => p.id), unorderedEquals(['silo:srv-a/p1', 'silo:srv-a/p2', 'silo:srv-b/k1']));
      final owner = stack.profile('srv-a', 'p1');
      expect((owner.displayName, owner.isPrimary, owner.connectionId), ('Owner', true, 'silo:srv-a'));
      expect(provider.connectionFor(owner)?.serverId, 'srv-a');
    });

    test('initialize leaves active null when no active id is stored', () async {
      await stack.addServer('srv-a', household);
      expect(provider.active, isNull);
    });

    test('initialize resolves the stored active profile id', () async {
      await storage.setActiveProfileId('silo:srv-a/p2');
      await stack.addServer('srv-a', household);
      expect(provider.activeId, 'silo:srv-a/p2');
      expect(provider.active?.displayName, 'Kids');
    });

    test("an upgrade adopts the server session's profile when the stored id predates Silo profiles", () async {
      await storage.setActiveProfileId('local-a');
      final connection = testSiloConnection('srv-a');
      await stack.connections.upsert(connection);
      await stack.households.put(connection, household);
      stack.sessionProfiles[connection.id] = 'p2';

      await provider.initialize();

      expect(provider.activeId, 'silo:srv-a/p2');
      expect(storage.getActiveProfileId(), 'silo:srv-a/p2');
    });

    test('a stored id no session names is cleared so the picker opens', () async {
      await storage.setActiveProfileId('local-a');
      await stack.addServer('srv-a', household);

      expect(provider.active, isNull);
      expect(storage.getActiveProfileId(), isNull);
    });

    test('a stored profile the loaded household no longer lists clears the selection', () async {
      await storage.setActiveProfileId('silo:srv-a/gone');
      await stack.addServer('srv-a', household);
      await pumpEventQueue();

      expect(provider.active, isNull);
      expect(storage.getActiveProfileId(), isNull);
    });

    test('an uncached household binds the stored profile provisionally until its read lands', () async {
      await storage.setActiveProfileId('silo:srv-a/p2');
      await stack.connections.upsert(testSiloConnection('srv-a', serverName: 'Den'));
      await provider.initialize();

      expect(provider.activeId, 'silo:srv-a/p2');
      expect(provider.active?.displayName, 'alice', reason: 'the account name stands in for the profile');

      await stack.households.put(testSiloConnection('srv-a'), household);
      await pumpEventQueue();
      expect(provider.active?.displayName, 'Kids');
    });

    test('keeps a stored id for a server whose connection has not loaded yet', () async {
      await storage.setActiveProfileId('silo:srv-a/p2');
      await provider.initialize();

      expect(provider.active, isNull);
      expect(storage.getActiveProfileId(), 'silo:srv-a/p2');
    });

    test('a household read backfills the connection account id', () async {
      final legacy = testSiloConnection('srv-a', accountId: '');
      await stack.connections.upsert(legacy);
      stack.serverHouseholds[legacy.id] = testHousehold([('p1', 'Owner')], accountId: 'acct-9');

      await stack.households.refresh(legacy);

      final stored = await stack.connections.get(legacy.id);
      expect(stored, isA<SiloConnection>().having((c) => c.accountId, 'accountId', 'acct-9'));
    });

    test('re-upserting an identical connection does not notify listeners', () async {
      final connection = await stack.addServer('srv-a', household);
      var notifications = 0;
      void listener() => notifications++;
      provider.addListener(listener);
      addTearDown(() => provider.removeListener(listener));

      await stack.connections.upsert(connection);
      await pumpEventQueue();

      expect(notifications, 0);
    });

    test('avatarUrlFor resolves a relative avatar against the server origin', () async {
      await stack.addServer(
        'srv-a',
        const SiloHousehold(SiloAccount(id: 'acct-1', username: 'alice', role: 'admin'), [
          SiloProfile(id: 'p1', name: 'Owner', avatarUrl: '/api/v2/profiles/p1/avatar'),
          SiloProfile(id: 'p2', name: 'Kids'),
        ]),
      );

      expect(provider.avatarUrlFor('silo:srv-a/p1'), 'https://srv-a.example/api/v2/profiles/p1/avatar');
      expect(provider.avatarUrlFor('silo:srv-a/p2'), isNull);
      expect(provider.avatarUrlFor('silo:srv-a/unknown'), isNull);
    });

    test('activate switches profiles', () async {
      await stack.addServer('srv-a', household);
      final ok = await provider.activate(stack.profile('srv-a', 'p2'));
      expect(ok, isTrue);
      expect(provider.activeId, 'silo:srv-a/p2');
      expect(storage.getActiveProfileId(), 'silo:srv-a/p2');
    });

    test('recency failure leaves stored and in-memory active identity unchanged', () async {
      await storage.setActiveProfileId('silo:srv-a/p1');
      await stack.addServer('srv-a', household);
      preferencesPlatform.writes.clear();
      preferencesPlatform.failIntKey = 'profile_last_used_silo:srv-a/p2';

      await expectLater(provider.activate(stack.profile('srv-a', 'p2')), throwsA(isA<StateError>()));
      await storage.prefs.reloadCache();

      expect(preferencesPlatform.writes, ['int:profile_last_used_silo:srv-a/p2']);
      expect(storage.getProfileLastUsed('silo:srv-a/p2'), isNull);
      expect(storage.getActiveProfileId(), 'silo:srv-a/p1');
      expect(provider.activeId, 'silo:srv-a/p1');
    });

    test('activation persists recency then marker before notifying listeners', () async {
      await storage.setActiveProfileId('silo:srv-a/p1');
      await stack.addServer('srv-a', household);
      preferencesPlatform.writes.clear();
      var notifiedAfterCommit = false;
      void listener() {
        if (provider.activeId != 'silo:srv-a/p2') return;
        notifiedAfterCommit =
            storage.getProfileLastUsed('silo:srv-a/p2') != null &&
            storage.getActiveProfileId() == 'silo:srv-a/p2' &&
            preferencesPlatform.writes.length >= 2 &&
            preferencesPlatform.writes[0] == 'int:profile_last_used_silo:srv-a/p2' &&
            preferencesPlatform.writes[1] == 'string:active_app_profile_id';
      }

      provider.addListener(listener);
      addTearDown(() => provider.removeListener(listener));

      expect(await provider.activate(stack.profile('srv-a', 'p2')), isTrue);

      expect(preferencesPlatform.writes.take(2), [
        'int:profile_last_used_silo:srv-a/p2',
        'string:active_app_profile_id',
      ]);
      expect(notifiedAfterCommit, isTrue);
    });

    test('activate moves the selected profile to the front by recent usage', () async {
      await stack.addServer('srv-a', household);
      expect(provider.profiles.map((p) => p.siloProfileId).toList(), ['p1', 'p2']);

      expect(await provider.activate(stack.profile('srv-a', 'p2')), isTrue);

      expect(provider.profiles.map((p) => p.siloProfileId).toList(), ['p2', 'p1']);
      expect(storage.getProfileLastUsed('silo:srv-a/p2'), isNotNull);
    });

    test('clearActiveProfile clears storage and in-memory active profile', () async {
      await stack.addServer('srv-a', household);
      await provider.activate(stack.profile('srv-a', 'p1'));

      await provider.clearActiveProfile();

      expect(storage.getActiveProfileId(), isNull);
      expect(provider.active, isNull);
    });

    test('hasMultipleProfiles reflects the household size', () async {
      await stack.addServer('srv-a', testHousehold([('p1', 'Owner')]));
      expect(provider.hasMultipleProfiles, isFalse);

      await stack.households.put(testSiloConnection('srv-a'), household);
      await pumpEventQueue();
      expect(provider.hasMultipleProfiles, isTrue);
    });

    test('signing out of a server drops its profiles', () async {
      final connection = await stack.addServer('srv-a', household);
      await stack.addServer('srv-b', testHousehold([('k1', 'Den')]));

      await stack.connections.remove(connection.id);
      await pumpEventQueue();

      expect(provider.profiles.map((p) => p.id), ['silo:srv-b/k1']);
    });
  });
}
