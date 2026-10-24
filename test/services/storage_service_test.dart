import 'dart:async';
import 'dart:convert';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/library_query.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/base_shared_preferences_service.dart';
import 'package:plezy/services/storage_service.dart';

import '../test_helpers/prefs.dart';

class _GatedPreferencesService extends BaseSharedPreferencesService {
  _GatedPreferencesService(this.started, this.release);

  final Completer<void> started;
  final Future<void> release;

  @override
  Future<void> onInit() async {
    started.complete();
    await release;
  }
}

void main() {
  setUp(resetSharedPreferencesForTest);

  group('StorageService.getInstance', () {
    test('returns same singleton instance', () async {
      final a = await StorageService.getInstance();
      final b = await StorageService.getInstance();
      expect(identical(a, b), isTrue);
    });

    test('coalesces callers until asynchronous initialization completes', () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var constructorCalls = 0;

      Future<_GatedPreferencesService> acquire() => BaseSharedPreferencesService.initializeInstance(() {
        constructorCalls++;
        return _GatedPreferencesService(started, release.future);
      });

      final first = acquire();
      await started.future;
      var secondCompleted = false;
      final second = acquire().then((instance) {
        secondCompleted = true;
        return instance;
      });
      await Future<void>.delayed(Duration.zero);

      expect(secondCompleted, isFalse);
      expect(constructorCalls, 1);

      release.complete();
      final instances = await Future.wait([first, second]);
      expect(identical(instances.first, instances.last), isTrue);
    });

    test('reset rebuilds against current SharedPreferences', () async {
      final first = await StorageService.getInstance();
      await first.prefs.setString('plex_token', 'token-1');
      BaseSharedPreferencesService.resetForTesting();

      final second = await StorageService.getInstance();
      expect(identical(first, second), isFalse);
      // Reset only the cached singleton, not the underlying prefs — values survive.
      expect(second.prefs.getString('plex_token'), 'token-1');
    });
  });

  group('ServerEndpoint', () {
    test('round-trip per server id', () async {
      final s = await StorageService.getInstance();
      await s.saveServerEndpoint(ServerId('srv-1'), 'http://192.0.2.1:32400');
      await s.saveServerEndpoint(ServerId('srv-2'), 'http://198.51.100.5:32400');

      expect(s.getServerEndpoint(ServerId('srv-1')), 'http://192.0.2.1:32400');
      expect(s.getServerEndpoint(ServerId('srv-2')), 'http://198.51.100.5:32400');
      expect(s.getServerEndpoint(ServerId('missing')), isNull);
    });

    test('clearServerEndpoint removes only the targeted id', () async {
      final s = await StorageService.getInstance();
      await s.saveServerEndpoint(ServerId('srv-1'), 'http://example.test');
      await s.saveServerEndpoint(ServerId('srv-2'), 'http://other.test');
      await s.clearServerEndpoint(ServerId('srv-1'));
      expect(s.getServerEndpoint(ServerId('srv-1')), isNull);
      expect(s.getServerEndpoint(ServerId('srv-2')), 'http://other.test');
    });
  });

  group('Servers list (legacy migration slot)', () {
    test('clearMultiServerData clears legacy list + order + endpoint prefixes', () async {
      final s = await StorageService.getInstance();
      // Write legacy values directly — the setters are gone.
      await s.prefs.setString('servers_list', '[{"x":1}]');
      await s.prefs.setString('server_order', json.encode(['a', 'b']));
      await s.saveServerEndpoint(ServerId('a'), 'http://foo.test');
      await s.saveServerEndpoint(ServerId('b'), 'http://bar.test');

      await s.clearMultiServerData();

      expect(s.prefs.getString('servers_list'), isNull);
      expect(s.prefs.getString('server_order'), isNull);
      expect(s.getServerEndpoint(ServerId('a')), isNull);
      expect(s.getServerEndpoint(ServerId('b')), isNull);
    });
  });

  group('Hidden libraries', () {
    test('default is empty set', () async {
      final s = await StorageService.getInstance();
      expect(s.getHiddenLibraries(), isEmpty);
    });

    test('save + read round-trip', () async {
      final s = await StorageService.getInstance();
      await s.saveHiddenLibraries({'lib-a', 'lib-b'});
      expect(s.getHiddenLibraries(), equals({'lib-a', 'lib-b'}));
    });

    test('explicit profile helpers isolate hidden libraries from active profile changes', () async {
      final s = await StorageService.getInstance();

      await s.setActiveProfileId('owner');
      await s.saveHiddenLibrariesForProfile('owner', {'srv:movies'});
      await s.setActiveProfileId('kids');
      await s.saveHiddenLibrariesForProfile('kids', {'srv:kids'});

      expect(s.getHiddenLibrariesForProfile('owner'), {'srv:movies'});
      expect(s.getHiddenLibrariesForProfile('kids'), {'srv:kids'});
      expect(s.getHiddenLibraries(), {'srv:kids'});
    });

    test('overwrite replaces previous set', () async {
      final s = await StorageService.getInstance();
      await s.saveHiddenLibraries({'lib-a', 'lib-b'});
      await s.saveHiddenLibraries({'lib-c'});
      expect(s.getHiddenLibraries(), equals({'lib-c'}));
    });

    test('saving empty set persists empty set (not null)', () async {
      final s = await StorageService.getInstance();
      await s.saveHiddenLibraries({'x'});
      await s.saveHiddenLibraries({});
      expect(s.getHiddenLibraries(), isEmpty);
    });

    test('survives garbage JSON by returning empty set', () async {
      final s = await StorageService.getInstance();
      // Write garbage directly under the key getHiddenLibraries() will read.
      await s.prefs.setString('hidden_libraries', 'not-json');
      expect(s.getHiddenLibraries(), isEmpty);
    });
  });

  group('Library order', () {
    test('default is null', () async {
      final s = await StorageService.getInstance();
      expect(s.getLibraryOrder(), isNull);
    });

    test('round-trip preserves order', () async {
      final s = await StorageService.getInstance();
      await s.saveLibraryOrder(['c', 'a', 'b']);
      expect(s.getLibraryOrder(), ['c', 'a', 'b']);
    });

    test('legacy unscoped value migrates into scoped key when an active profile is set', () async {
      final s = await StorageService.getInstance();

      // Write a legacy (unscoped) library order, mimicking pre-multi-user data.
      await s.prefs.setString('library_order', json.encode(['x', 'y']));

      // Set an active profile so reads/writes become scoped.
      await s.setActiveProfileId('local-user-1');

      final read = s.getLibraryOrder();
      expect(read, ['x', 'y']);

      // Migration should have copied the legacy value under the scoped key.
      final scopedRaw = s.prefs.getString('user_local-user-1_library_order');
      expect(scopedRaw, json.encode(['x', 'y']));
      expect(s.prefs.getString('library_order'), isNull);
    });

    test('migrated legacy order is not inherited by another profile', () async {
      final s = await StorageService.getInstance();
      await s.prefs.setString('library_order', json.encode(['legacy']));

      await s.setActiveProfileId('local-user-1');
      expect(s.getLibraryOrder(), ['legacy']);

      await s.setActiveProfileId('local-user-2');
      expect(s.getLibraryOrder(), isNull);
    });

    test('per-user scoping isolates orders', () async {
      final s = await StorageService.getInstance();

      await s.setActiveProfileId('local-user-1');
      await s.saveLibraryOrder(['u1-a', 'u1-b']);

      await s.setActiveProfileId('local-user-2');
      expect(s.getLibraryOrder(), isNull);
      await s.saveLibraryOrder(['u2-a']);

      // Switch back — user-1 sees their own list.
      await s.setActiveProfileId('local-user-1');
      expect(s.getLibraryOrder(), ['u1-a', 'u1-b']);

      await s.setActiveProfileId('local-user-2');
      expect(s.getLibraryOrder(), ['u2-a']);
    });

  });

  group('Library filters / sort / grouping / tab', () {
    test('global filters round-trip, operators included', () async {
      final s = await StorageService.getInstance();
      expect(s.getLibraryFilters(), isEmpty);
      const selection = [
        LibraryFilter(field: 'genre', values: ['sci-fi', 'horror']),
        LibraryFilter(field: 'year', op: LibraryFilterOperator.atLeast, values: ['2024']),
        LibraryFilter(field: 'contentRating', op: LibraryFilterOperator.isNot, values: ['R']),
      ];
      await s.saveLibraryFilters(selection);
      expect(s.getLibraryFilters(), selection);
    });

    test('per-section filters fall back to global when missing', () async {
      final s = await StorageService.getInstance();
      const global = [
        LibraryFilter(field: 'unwatched', values: ['1']),
      ];
      const section = [
        LibraryFilter(field: 'genre', values: ['horror']),
      ];
      await s.saveLibraryFilters(global);
      expect(s.getLibraryFilters(sectionId: 'sec-1'), global);

      await s.saveLibraryFilters(section, sectionId: 'sec-1');
      expect(s.getLibraryFilters(sectionId: 'sec-1'), section);
      expect(s.getLibraryFilters(), global);
    });

    test('legacy per-section filters migrate once into scoped key', () async {
      final s = await StorageService.getInstance();
      await s.prefs.setString(
        'library_filters_sec-1',
        json.encode([
          {
            'field': 'genre',
            'values': ['drama'],
          },
        ]),
      );

      await s.setActiveProfileId('local-user-1');
      expect(s.getLibraryFilters(sectionId: 'sec-1'), const [
        LibraryFilter(field: 'genre', values: ['drama']),
      ]);
      expect(s.prefs.getString('user_local-user-1_library_filters_sec-1'), isNotNull);
      expect(s.prefs.getString('library_filters_sec-1'), isNull);

      await s.setActiveProfileId('local-user-2');
      expect(s.getLibraryFilters(sectionId: 'sec-1'), isEmpty);
    });

    test('a selection saved by a pre-clause build restores as equality clauses', () async {
      // Older builds wrote `{"genre": "42", "unwatched": "1"}`; those saved
      // filters must survive the upgrade rather than silently vanish.
      final s = await StorageService.getInstance();
      await s.prefs.setString('library_filters_sec-legacy', json.encode({'genre': '42,43', 'unwatched': '1'}));
      expect(s.getLibraryFilters(sectionId: 'sec-legacy'), const [
        LibraryFilter(field: 'genre', values: ['42', '43']),
        LibraryFilter(field: 'unwatched', values: ['1']),
      ]);
    });

    test('a clause with an unrecognised operator is dropped, not downgraded to include', () async {
      // A newer build may persist an operator this one does not know. Reading
      // it as plain equality would show exactly the items the user excluded.
      final s = await StorageService.getInstance();
      await s.prefs.setString(
        'library_filters_sec-future',
        json.encode([
          {
            'field': 'genre',
            'op': 'isNot',
            'values': ['42'],
          },
          {
            'field': 'genre',
            'op': 'matchesFuzzily',
            'values': ['43'],
          },
        ]),
      );
      expect(s.getLibraryFilters(sectionId: 'sec-future'), const [
        LibraryFilter(field: 'genre', op: LibraryFilterOperator.isNot, values: ['42']),
      ]);
    });

    test('library sort round-trips with descending flag', () async {
      final s = await StorageService.getInstance();
      await s.saveLibrarySort('sec-1', 'titleSort', descending: true);
      expect(s.getLibrarySort('sec-1'), {'key': 'titleSort', 'descending': true});

      await s.saveLibrarySort('sec-1', 'addedAt');
      expect(s.getLibrarySort('sec-1'), {'key': 'addedAt', 'descending': false});
    });

    test('library sort: legacy plain-string value migrates to map shape', () async {
      final s = await StorageService.getInstance();
      // Pre-existing legacy plain string under the unscoped key.
      await s.prefs.setString('library_sort_sec-1', 'titleSort');
      // _readJsonMap with legacyStringOk=true should normalize to the map shape.
      final result = s.getLibrarySort('sec-1');
      expect(result, {'key': 'titleSort', 'descending': false});
    });

    test('library grouping round-trips', () async {
      final s = await StorageService.getInstance();
      expect(s.getLibraryGrouping('sec-1'), isNull);
      await s.saveLibraryGrouping('sec-1', 'shows');
      expect(s.getLibraryGrouping('sec-1'), 'shows');
    });

    test('library tab round-trips', () async {
      final s = await StorageService.getInstance();
      expect(s.getLibraryTab('sec-1'), isNull);
      await s.saveLibraryTab('sec-1', 'recommended');
      expect(s.getLibraryTab('sec-1'), 'recommended');
    });

    test('saveSelectedLibraryKey + getSelectedLibraryKey round-trip', () async {
      final s = await StorageService.getInstance();
      expect(s.getSelectedLibraryKey(), isNull);
      await s.saveSelectedLibraryKey('lib-key-42');
      expect(s.getSelectedLibraryKey(), 'lib-key-42');
    });
  });

  group('clearLegacyBackendPrefsOnce', () {
    const legacy = {
      'plex_token': 'legacy-token',
      'current_user_uuid': 'uuid-1',
      'servers_list': '[]',
      'server_order': '[]',
      'selected_library_key': 'plex-machine:1',
      'library_filters': '{}',
      'library_order': '["plex-machine:1"]',
      'hidden_libraries': '[]',
      'home_users_cache': '[]',
      'home_users_cache_expiry': '0',
      'server_endpoint_plex-machine': 'https://plex.example',
      'plex_home_users_plex-account': '[]',
      'library_filters_plex-machine:1': '{}',
      'library_sort_plex-machine:1': '{}',
      'library_grouping_plex-machine:1': 'all',
      'library_tab_plex-machine:1': 'browse',
    };
    const kept = {
      'active_app_profile_id': 'local-1',
      'client_identifier': 'device-1',
      'silo_device_id': 'silo-device-1',
      'silo_session_v1.origin': 'https://silo.example',
      'user_local-1_selected_library_key': 'silo-srv:movies',
      'user_local-1_library_sort_silo-srv:movies': '{}',
      'user_local-1_library_order': '["silo-srv:movies"]',
    };

    Future<StorageService> seeded() async {
      final s = await StorageService.getInstance();
      for (final entry in {...legacy, ...kept}.entries) {
        await s.prefs.setString(entry.key, entry.value);
      }
      await s.prefs.setInt('profile_last_used_local-1', 42);
      return s;
    }

    test('removes the legacy Plex keys and Plex-era library prefixes', () async {
      final s = await seeded();

      await s.clearLegacyBackendPrefsOnce();

      expect(s.prefs.keys.where(legacy.containsKey), isEmpty);
    });

    test('keeps profile-scoped prefs, the active profile, recency and device ids', () async {
      final s = await seeded();

      await s.clearLegacyBackendPrefsOnce();

      for (final entry in kept.entries) {
        expect(s.prefs.getString(entry.key), entry.value, reason: entry.key);
      }
      expect(s.prefs.getInt('profile_last_used_local-1'), 42);
    });

    test('runs once, so keys written afterwards stay', () async {
      var s = await seeded();
      await s.clearLegacyBackendPrefsOnce();

      await s.prefs.setString('library_sort_silo-srv:movies', '{}');
      await s.clearLegacyBackendPrefsOnce();
      BaseSharedPreferencesService.resetForTesting();
      s = await StorageService.getInstance();
      await s.clearLegacyBackendPrefsOnce();

      expect(s.prefs.getString('library_sort_silo-srv:movies'), '{}');
    });
  });

  group('clearCredentials', () {
    test('removes credential keys, plex token, and multi-server data', () async {
      final s = await StorageService.getInstance();

      // Seed every legacy slot directly — the runtime setters were removed
      // when we collapsed the legacy/new dual-write.
      await s.prefs.setString('plex_token', 'tok-x');
      await s.prefs.setString('client_identifier', 'client-x');
      await s.prefs.setString('servers_list', '[{"x":1}]');
      await s.prefs.setString('server_order', json.encode(['a']));
      await s.saveServerEndpoint(ServerId('a'), 'http://foo.test');

      // Library prefs: write WITHOUT an active profile id
      // so they land on the legacy unscoped key.
      await s.saveLibraryOrder(['lib-1']);

      // Now seed current_user_uuid — clearCredentials should remove this.
      await s.prefs.setString('current_user_uuid', 'u-x');

      await s.clearCredentials();

      // Credential-bucket keys all gone.
      expect(s.prefs.getString('plex_token'), isNull);
      expect(s.prefs.getString('client_identifier'), isNull);
      expect(s.prefs.getString('current_user_uuid'), isNull);

      // Multi-server data wiped.
      expect(s.prefs.getString('servers_list'), isNull);
      expect(s.prefs.getString('server_order'), isNull);
      expect(s.getServerEndpoint(ServerId('a')), isNull);

      // Library prefs and unrelated state untouched (no scope active, so
      // the scoped read falls through to the same legacy key it was written to).
      expect(s.getLibraryOrder(), ['lib-1']);
    });

    test('removes every Silo session slot and keeps the Silo device id', () async {
      final s = await StorageService.getInstance();
      await s.prefs.setString('silo_session_v1.server-1', 'enc:v1:a');
      await s.prefs.setString('silo_session_v1.server-2', 'enc:v1:b');
      await s.prefs.setString('silo_device_id', 'device-1');

      await s.clearCredentials();

      expect(s.prefs.getString('silo_session_v1.server-1'), isNull);
      expect(s.prefs.getString('silo_session_v1.server-2'), isNull);
      expect(s.prefs.getString('silo_device_id'), 'device-1');
    });
  });

  group('clearLibraryPreferences', () {
    test('clears scoped library keys for current user only', () async {
      final s = await StorageService.getInstance();

      // user-1's library prefs
      await s.setActiveProfileId('local-user-1');
      await s.saveLibraryOrder(['u1-a', 'u1-b']);
      await s.saveSelectedLibraryKey('u1-key');
      await s.saveLibraryFilters(const [
        LibraryFilter(field: 'genre', values: ['horror']),
      ], sectionId: 'sec-1');
      await s.saveLibrarySort('sec-1', 'titleSort', descending: true);
      await s.saveLibraryGrouping('sec-1', 'shows');
      await s.saveLibraryTab('sec-1', 'tabA');
      await s.saveHiddenLibraries({'h-1'});

      // user-2's library prefs (must not be touched by clearing user-1)
      await s.setActiveProfileId('local-user-2');
      await s.saveLibraryOrder(['u2-a']);
      await s.saveSelectedLibraryKey('u2-key');

      // Clear user-2 first to ensure user-2 keys are gone, then verify user-1's intact.
      await s.clearLibraryPreferences();
      expect(s.getLibraryOrder(), isNull);
      expect(s.getSelectedLibraryKey(), isNull);

      await s.setActiveProfileId('local-user-1');
      expect(s.getLibraryOrder(), ['u1-a', 'u1-b']);
      expect(s.getSelectedLibraryKey(), 'u1-key');
      expect(s.getLibraryFilters(sectionId: 'sec-1'), const [
        LibraryFilter(field: 'genre', values: ['horror']),
      ]);
      expect(s.getLibrarySort('sec-1'), {'key': 'titleSort', 'descending': true});
      expect(s.getLibraryGrouping('sec-1'), 'shows');
      expect(s.getLibraryTab('sec-1'), 'tabA');
      expect(s.getHiddenLibraries(), {'h-1'});

      // Now clear user-1 and confirm everything for that user goes away.
      await s.clearLibraryPreferences();
      expect(s.getLibraryOrder(), isNull);
      expect(s.getSelectedLibraryKey(), isNull);
      expect(s.getLibraryFilters(sectionId: 'sec-1'), isEmpty);
      expect(s.getLibrarySort('sec-1'), isNull);
      expect(s.getLibraryGrouping('sec-1'), isNull);
      expect(s.getLibraryTab('sec-1'), isNull);
      expect(s.getHiddenLibraries(), isEmpty);
    });

    test('clearing scoped prefs also consumes pending legacy values', () async {
      final s = await StorageService.getInstance();
      await s.prefs.setString('library_order', json.encode(['legacy']));
      await s.prefs.setString(
        'library_filters_sec-1',
        json.encode(const [
          {
            'field': 'genre',
            'values': ['drama'],
          },
        ]),
      );

      await s.setActiveProfileId('local-user-1');
      await s.clearLibraryPreferences();

      expect(s.getLibraryOrder(), isNull);
      expect(s.getLibraryFilters(sectionId: 'sec-1'), isEmpty);
      expect(s.prefs.getString('library_order'), isNull);
      expect(s.prefs.getString('library_filters_sec-1'), isNull);
    });

    test('clearLibraryPreferencesForServer clears only the target profile server keys', () async {
      final s = await StorageService.getInstance();
      final serverA = ServerId('srv-a');
      final serverB = ServerId('srv-b');

      await s.setActiveProfileId('local-user-1');
      await s.saveLibraryOrder(['srv-a:movies', 'srv-b:shows']);
      await s.saveSelectedLibraryKey('srv-a:movies');
      await s.saveHiddenLibraries({'srv-a:movies', 'srv-b:shows'});
      await s.saveLibraryFilters(const [
        LibraryFilter(field: 'genre', values: ['sci-fi']),
      ], sectionId: 'srv-a:movies');
      await s.saveLibraryFilters(const [
        LibraryFilter(field: 'genre', values: ['drama']),
      ], sectionId: 'srv-b:shows');
      await s.saveLibrarySort('srv-a:movies', 'titleSort');
      await s.saveLibraryGrouping('srv-a:movies', 'movies');
      await s.saveLibraryTab('srv-a:movies', 'recommended');

      await s.setActiveProfileId('local-user-2');
      await s.saveLibraryOrder(['srv-a:movies']);
      await s.saveHiddenLibraries({'srv-a:movies'});

      await s.clearLibraryPreferencesForServer(serverA, profileId: 'local-user-1');

      await s.setActiveProfileId('local-user-1');
      expect(s.getLibraryOrder(), ['srv-b:shows']);
      expect(s.getSelectedLibraryKey(), isNull);
      expect(s.getHiddenLibraries(), {'srv-b:shows'});
      expect(s.getLibraryFilters(sectionId: 'srv-a:movies'), isEmpty);
      expect(s.getLibraryFilters(sectionId: 'srv-b:shows'), const [
        LibraryFilter(field: 'genre', values: ['drama']),
      ]);
      expect(s.getLibrarySort('srv-a:movies'), isNull);
      expect(s.getLibraryGrouping('srv-a:movies'), isNull);
      expect(s.getLibraryTab('srv-a:movies'), isNull);

      await s.setActiveProfileId('local-user-2');
      expect(s.getLibraryOrder(), ['srv-a:movies']);
      expect(s.getHiddenLibraries(), {'srv-a:movies'});

      await s.clearLibraryPreferencesForServer(serverB, profileId: 'local-user-1');
      await s.setActiveProfileId('local-user-1');
      expect(s.getLibraryOrder(), isNull);
      expect(s.getHiddenLibraries(), isEmpty);
    });

    test('clearLibraryPreferencesForServerEverywhere clears server keys from all scopes', () async {
      final s = await StorageService.getInstance();
      final serverA = ServerId('srv-a');

      await s.prefs.setString('library_order', json.encode(['srv-a:legacy', 'srv-b:legacy']));
      await s.prefs.setString('hidden_libraries', json.encode(['srv-a:legacy', 'srv-b:legacy']));
      await s.prefs.setString('selected_library_key', 'srv-a:legacy');
      await s.prefs.setString('library_sort_srv-a:legacy', json.encode({'key': 'titleSort', 'descending': false}));
      await s.prefs.setString('library_grouping_srv-a:legacy', 'movies');

      await s.setActiveProfileId('local-user-1');
      await s.saveLibraryOrder(['srv-a:movies', 'srv-b:shows']);
      await s.saveHiddenLibraries({'srv-a:movies', 'srv-b:shows'});
      await s.saveLibrarySort('srv-a:movies', 'titleSort');

      await s.setActiveProfileId('local-user-2');
      await s.saveLibraryOrder(['srv-a:movies']);
      await s.saveHiddenLibraries({'srv-a:movies'});

      await s.clearLibraryPreferencesForServerEverywhere(serverA);

      expect(s.prefs.getString('library_order'), json.encode(['srv-b:legacy']));
      expect(s.prefs.getString('hidden_libraries'), json.encode(['srv-b:legacy']));
      expect(s.prefs.getString('selected_library_key'), isNull);
      expect(s.prefs.getString('library_sort_srv-a:legacy'), isNull);
      expect(s.prefs.getString('library_grouping_srv-a:legacy'), isNull);

      await s.setActiveProfileId('local-user-1');
      expect(s.getLibraryOrder(), ['srv-b:shows']);
      expect(s.getHiddenLibraries(), {'srv-b:shows'});
      expect(s.getLibrarySort('srv-a:movies'), isNull);

      await s.setActiveProfileId('local-user-2');
      expect(s.getLibraryOrder(), ['srv-b:legacy']);
      expect(s.getHiddenLibraries(), {'srv-b:legacy'});
    });
  });

  group('clearUserData', () {
    test('combines credentials and library-preferences clear', () async {
      final s = await StorageService.getInstance();

      await s.prefs.setString('plex_token', 'tok');
      await s.setActiveProfileId('local-user-1');
      await s.saveLibraryOrder(['lib-a']);
      await s.saveHiddenLibraries({'h-1'});

      await s.clearUserData();

      expect(s.prefs.getString('plex_token'), isNull);
      // setActiveProfileId is unaffected by clearCredentials, so the prefix
      // is still active — clearLibraryPreferences cleared the scoped values.
      expect(s.getLibraryOrder(), isNull);
      expect(s.getHiddenLibraries(), isEmpty);
    });
  });

  group('clearPlezyProfilePrefsOnce', () {
    test('drops prefs keyed by a Plezy profile and keeps Silo scopes and global slots', () async {
      final s = await StorageService.getInstance();
      await s.prefs.setString('user_local-1_seerr_session', '{}');
      await s.prefs.setString('user_local-1_trakt_session', '{}');
      await s.prefs.setString('user_local-1_library_order', '[]');
      await s.prefs.setInt('profile_last_used_local-1', 42);
      await s.prefs.setString('user_silo:srv/p-1_seerr_session', '{}');
      await s.prefs.setInt('profile_last_used_silo:srv/p-1', 7);
      await s.prefs.setString('trakt_session', '{}');
      await s.setActiveProfileId('silo:srv/p-1');

      await s.clearPlezyProfilePrefsOnce();

      expect(s.prefs.keys.where((k) => k.contains('local-1')), isEmpty);
      expect(s.prefs.getString('user_silo:srv/p-1_seerr_session'), '{}');
      expect(s.prefs.getInt('profile_last_used_silo:srv/p-1'), 7);
      expect(s.prefs.getString('trakt_session'), '{}');
      expect(s.getActiveProfileId(), 'silo:srv/p-1');
    });

    test('runs once, so keys written afterwards stay', () async {
      final s = await StorageService.getInstance();
      await s.clearPlezyProfilePrefsOnce();
      await s.prefs.setString('user_local-2_library_order', '[]');

      await s.clearPlezyProfilePrefsOnce();

      expect(s.prefs.getString('user_local-2_library_order'), '[]');
    });
  });
}
