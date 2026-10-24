import 'dart:async';
import 'package:plezy/media/ids.dart';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/exceptions/media_server_exceptions.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/server_capabilities.dart';
import 'package:plezy/media/media_person.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/search_hit.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/services/catalog/catalog_library_matcher.dart';
import 'package:plezy/services/data_aggregation_service.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/silo_api_cache.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/external_ids.dart';
import 'package:plezy/utils/media_server_http_client.dart';
import 'package:plezy/utils/media_server_timeouts.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

/// Minimal client with independently configurable library and search outcomes.
/// A `hang*` leg never answers until its abort fires, like a server that
/// accepted the connection and stopped responding.
class _LibrariesClient implements MediaServerClient {
  _LibrariesClient(
    this.serverId, {
    this.error,
    this.libraries = const [],
    this.searchError,
    this.searchResults = const [],
    this.peopleError,
    this.peopleResults = const [],
    this.hangLibraries = false,
    this.hangSearch = false,
    this.hangPeople = false,
  });

  @override
  final ServerId serverId;

  @override
  final String serverName = 'Server';

  final Object? error;
  final List<MediaLibrary> libraries;
  final Object? searchError;
  final List<MediaItem> searchResults;
  final Object? peopleError;
  final List<MediaPerson> peopleResults;
  final bool hangLibraries;
  final bool hangSearch;
  final bool hangPeople;
  int? lastSearchLimit;
  Set<String>? lastExcludedLibraryIds;
  Set<String>? lastPeopleExcludedLibraryIds;
  AbortController? lastSearchAbort;
  AbortController? lastPeopleAbort;

  static Future<void> _hangUntilAborted(AbortController? abort) async {
    await (abort?.trigger ?? Completer<void>().future);
    abort!.throwIfAborted();
  }

  @override
  Future<List<MediaLibrary>> fetchLibraries() async {
    if (hangLibraries) await Completer<void>().future;
    if (error != null) throw error!;
    return libraries;
  }

  @override
  Future<List<MediaItem>> searchItems(
    String query, {
    int limit = 100,
    AbortController? abort,
    Set<String> excludedLibraryIds = const {},
  }) async {
    lastSearchLimit = limit;
    lastExcludedLibraryIds = excludedLibraryIds;
    lastSearchAbort = abort;
    if (hangSearch) await _hangUntilAborted(abort);
    abort?.throwIfAborted();
    if (searchError != null) throw searchError!;
    return searchResults;
  }

  @override
  Future<List<MediaPerson>> searchPeople(
    String query, {
    int limit = defaultPeopleSearchLimit,
    AbortController? abort,
    Set<String> excludedLibraryIds = const {},
  }) async {
    lastPeopleExcludedLibraryIds = excludedLibraryIds;
    lastPeopleAbort = abort;
    if (hangPeople) await _hangUntilAborted(abort);
    abort?.throwIfAborted();
    if (peopleError != null) throw peopleError!;
    return peopleResults;
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaPerson _person(String id, String name, {required String serverId}) =>
    MediaPerson(id: id, name: name, backend: MediaBackend.silo, serverId: ServerId(serverId));

/// Hit identities in rank order: a title's id, or `person:<id>`.
List<String> _hitIds(SearchAggregationResult result) => [
  for (final hit in result.hits)
    switch (hit) {
      MediaSearchHit(:final item) => item.id,
      PersonSearchHit(:final person) => 'person:${person.id}',
    },
];

/// Per-library hub client whose fetches are held open individually, so a test
/// can observe exactly when the fan-out starts each library.
class _GatedHubsClient implements MediaServerClient {
  _GatedHubsClient(this.libraries);

  final List<MediaLibrary> libraries;
  final started = <String>[];
  final _gates = <String, Completer<List<MediaHub>>>{};

  void complete(String libraryId) {
    _gates[libraryId]!.complete([
      MediaHub(
        id: '$libraryId.recent',
        title: libraryId,
        type: 'mixed',
        items: const [],
        size: 0,
        libraryId: libraryId,
      ),
    ]);
  }

  @override
  ServerId get serverId => ServerId('server-1');

  @override
  String get serverName => 'Server';

  @override
  ServerCapabilities get capabilities => ServerCapabilities.silo;

  @override
  Future<List<MediaLibrary>> fetchLibraries() async => libraries;

  @override
  Future<List<MediaHub>> fetchLibraryHubs(
    String libraryId, {
    String? libraryName,
    int limit = defaultHubPreviewLimit,
    bool includePlaybackHubs = true,
    MediaKind? libraryKind,
    HubFetchDiagnostics? diagnostics,
  }) {
    started.add(libraryId);
    return (_gates[libraryId] = Completer<List<MediaHub>>()).future;
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaLibrary _library(String id, MediaKind kind) =>
    MediaLibrary(id: id, backend: MediaBackend.silo, title: id, kind: kind, serverId: ServerId('server-1'));

/// Per-library hub client for a server without rich (global) hubs: every row
/// comes from its libraries, and the global endpoint must never be asked.
class _PerLibraryHubsClient implements MediaServerClient {
  _PerLibraryHubsClient(this.libraries);

  final List<MediaLibrary> libraries;
  var fetchLibrariesCalls = 0;
  final hubCalls = <({String libraryId, int limit, bool includePlaybackHubs})>[];

  @override
  ServerId get serverId => ServerId('server-1');

  @override
  String get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.silo;

  @override
  ServerCapabilities get capabilities => const ServerCapabilities(richHubs: false);

  @override
  Future<List<MediaLibrary>> fetchLibraries() async {
    fetchLibrariesCalls++;
    return libraries;
  }

  @override
  Future<List<MediaHub>> fetchGlobalHubs({
    int limit = defaultHubPreviewLimit,
    bool includePlaybackHubs = true,
    HubFetchDiagnostics? diagnostics,
  }) => fail('a server without rich hubs must not be asked for global hubs');

  @override
  Future<List<MediaHub>> fetchLibraryHubs(
    String libraryId, {
    String? libraryName,
    int limit = defaultHubPreviewLimit,
    bool includePlaybackHubs = true,
    MediaKind? libraryKind,
    HubFetchDiagnostics? diagnostics,
  }) async {
    hubCalls.add((libraryId: libraryId, limit: limit, includePlaybackHubs: includePlaybackHubs));
    return [
      MediaHub(
        id: '$libraryId.recent',
        identifier: 'library.$libraryId.recent',
        title: libraryName ?? libraryId,
        type: 'mixed',
        items: [
          testMediaItem(id: 'item-$libraryId', backend: MediaBackend.silo, serverId: 'server-1', libraryId: libraryId),
        ],
        size: 1,
        libraryId: libraryId,
      ),
    ];
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Silo-backed client whose Continue Watching rows, external ids and
/// external-id lookups are scripted per test, recording what it was asked.
class _ScriptedClient implements MediaServerClient {
  _ScriptedClient(this.serverId, {this.continueWatching = const [], this.externalIds = const {}, this.lookup});

  @override
  final ServerId serverId;

  @override
  final String serverName = 'Server';

  @override
  MediaBackend get backend => MediaBackend.silo;

  final List<MediaItem> continueWatching;
  final Map<String, ExternalIds> externalIds;
  final Future<List<MediaItem>?> Function(MediaKind kind)? lookup;
  final continueWatchingCounts = <int?>[];
  var lookups = 0;

  @override
  Future<List<MediaItem>> fetchContinueWatching({int? count = 20, Set<String> excludedLibraryIds = const {}}) async {
    continueWatchingCounts.add(count);
    return continueWatching;
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => externalIds[itemId] ?? const ExternalIds();

  @override
  Future<List<MediaItem>?> findByExternalIds(
    ExternalIds ids, {
    required MediaKind kind,
    List<String> titles = const [],
    int? year,
    ExternalSeasonRef? season,
  }) async {
    lookups++;
    final handler = lookup;
    if (handler == null) return fail('Unexpected lookup for $kind');
    return handler(kind);
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A Continue Watching row on server `silo-1`.
MediaItem _row(
  String id, {
  MediaKind kind = MediaKind.movie,
  required String title,
  int? lastViewedAt,
  String? libraryId,
  String? grandparentId,
  String? grandparentTitle,
}) => testMediaItem(
  id: id,
  backend: MediaBackend.silo,
  kind: kind,
  title: title,
  serverId: 'silo-1',
  lastViewedAt: lastViewedAt,
  libraryId: libraryId,
  grandparentId: grandparentId,
  grandparentTitle: grandparentTitle,
);

/// Covers the remaining cross-server [DataAggregationService] fan-out surface;
/// single-server calls now go through the per-server client context.
void main() {
  late AppDatabase db;
  late MultiServerManager manager;
  late DataAggregationService service;

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SiloApiCache.initialize(db);
    manager = MultiServerManager();
    service = DataAggregationService(manager);
  });

  tearDown(() async {
    manager.dispose();
    await db.close();
  });

  /// Registers server `silo-1` whose Continue Watching answers [rows];
  /// [externalIds] answers identity lookups for the ids it names.
  _ScriptedClient registerContinueWatching(List<MediaItem> rows, {Map<String, ExternalIds> externalIds = const {}}) {
    final client = _ScriptedClient(ServerId('silo-1'), continueWatching: rows, externalIds: externalIds);
    manager.debugRegisterClientForTesting(client);
    return client;
  }

  test('offline expected-server misses expire and reveal copies after recovery', () async {
    const serverId = 'silo-1';
    final client = _ScriptedClient(
      ServerId(serverId),
      lookup: (_) async => [
        testMediaItem(
          id: 'recovered',
          backend: MediaBackend.silo,
          kind: MediaKind.movie,
          title: 'Recovered Movie',
          serverId: serverId,
        ),
      ],
    );
    manager.debugRegisterClientForTesting(client, online: false);
    final multiServer = MultiServerProvider(manager, service)
      ..setExpectedVisibleServerIds({serverId})
      ..setVisibleServerIds({});
    var now = DateTime.utc(2026, 7, 28);
    final matcher = CatalogLibraryMatcher.withClock(multiServer, () => now);
    addTearDown(() {
      matcher.dispose();
      multiServer.dispose();
    });
    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Recovered Movie',
      ids: CatalogItemIds(tmdb: 42),
    );

    final offline = await matcher.match(item);
    expect(offline.items, isEmpty);
    expect(offline.succeededServerIds, isEmpty);
    expect(offline.unqueriedServerIds, {serverId});
    manager.debugRegisterClientForTesting(client);
    now = now.add(CatalogLibraryMatcher.negativeTtl - const Duration(seconds: 1));
    expect((await matcher.match(item)).unqueriedServerIds, {serverId});
    expect(client.lookups, 0);

    now = now.add(const Duration(seconds: 1));
    final recovered = await matcher.match(item);
    expect(recovered.items.single.id, 'recovered');
    expect(recovered.items.single.serverId, serverId);
    expect(recovered.succeededServerIds, {serverId});
    expect(recovered.unqueriedServerIds, isEmpty);
  });

  group('external-id query coverage', () {
    test('unsupported media kinds are unqueried, not successful empty answers', () async {
      // A backend that cannot look this kind up answers null.
      final client = _ScriptedClient(ServerId('srv'), lookup: (_) async => null);
      manager.debugRegisterClientForTesting(client);
      final result = await service.findByExternalIdsAcrossServers(
        const ExternalIds(tmdb: 42),
        kind: MediaKind.episode,
        titles: const ['Pilot'],
        serverIds: {'srv'},
      );
      expect(result.items, isEmpty);
      expect(result.succeededServerIds, isEmpty);
      expect(result.unqueriedServerIds, {'srv'});
      expect(result.failedServerIds, isEmpty);
      expect(result.cancelledServerIds, isEmpty);
      expect(client.lookups, 1);
    });

    test('cancellation, HTTP failure and unavailable clients remain distinct from successful misses', () async {
      manager.debugRegisterClientForTesting(
        _ScriptedClient(
          ServerId('cancelled'),
          lookup: (_) async =>
              throw MediaServerHttpException(type: MediaServerHttpErrorType.cancelled, message: 'aborted'),
        ),
      );
      manager.debugRegisterClientForTesting(
        _ScriptedClient(
          ServerId('failed'),
          lookup: (_) async => throw MediaServerHttpException(
            type: MediaServerHttpErrorType.unknown,
            statusCode: 401,
            message: 'Unauthorized',
          ),
        ),
      );
      manager.debugRegisterClientForTesting(_ScriptedClient(ServerId('miss'), lookup: (_) async => []));

      final result = await service.findByExternalIdsAcrossServers(
        const ExternalIds(tmdb: 34523),
        kind: MediaKind.movie,
        titles: const ['Night on the Galactic Railroad'],
        serverIds: {'cancelled', 'failed', 'miss', 'clientless'},
      );

      expect(result.items, isEmpty);
      expect(result.succeededServerIds, {'miss'});
      expect(result.failedServerIds, {'failed'});
      expect(result.cancelledServerIds, {'cancelled'});
      expect(result.unqueriedServerIds, {'clientless'});
    });
  });

  group('DataAggregationService cross-server aggregation', () {
    test('getMediaLibrariesFromAllServers returns empty when no clients connected', () async {
      final result = await service.getMediaLibrariesFromAllServers();
      expect(result.libraries, isEmpty);
      expect(result.succeededServerIds, isEmpty);
    });
    test('per-library hub fan-out refills a free slot instead of waiting for the batch', () async {
      // Old shape: batches of three separated by `Future.wait`, so the 4th
      // library could not start until ALL of the first three had answered and
      // one slow row stalled every row queued behind it (#1784). A sliding
      // window keeps the same peak concurrency with no head-of-line blocking.
      final client = _GatedHubsClient([
        for (var i = 1; i <= 4; i++)
          MediaLibrary(
            id: 'lib-$i',
            backend: MediaBackend.silo,
            title: 'Library $i',
            kind: MediaKind.movie,
            serverId: ServerId('server-1'),
          ),
      ]);
      manager.debugRegisterClientForTesting(client);

      final pending = service.getHubsFromAllServers(useGlobalHubs: false, includePlaybackHubs: false);
      await pumpEventQueue();

      expect(client.started, ['lib-1', 'lib-2', 'lib-3'], reason: 'concurrency stays at 3');

      // Free exactly one slot. The 4th library must take it immediately, while
      // its two batch-mates are still in flight.
      client.complete('lib-1');
      await pumpEventQueue();

      expect(client.started, ['lib-1', 'lib-2', 'lib-3', 'lib-4']);

      // Finish out of order — hub order must still follow library order.
      client.complete('lib-4');
      client.complete('lib-3');
      client.complete('lib-2');

      final result = await pending;
      expect(result.hubs.map((hub) => hub.libraryId), ['lib-1', 'lib-2', 'lib-3', 'lib-4']);
    });

    test('searchAcrossServers and getOnDeckFromAllServers return empty when no clients', () async {
      final search = await service.searchAcrossServers('hello');
      expect(search.hits, isEmpty);
      expect(search.candidates, isEmpty);
      expect(search.people, isEmpty);
      expect(search.succeededServerIds, isEmpty);
      expect(search.cancelledServerIds, isEmpty);
      expect(search.failedServerIds, isEmpty);
      final onDeck = await service.getOnDeckFromAllServers();
      expect(onDeck.items, isEmpty);
      expect(onDeck.succeededServerIds, isEmpty);
    });

    test('classifies cancelled per-server failures apart from settled ones', () async {
      // A cancelled fetch (our own client torn down mid-request) says nothing
      // about the server's content; consumers use cancelledServerIds to keep
      // a disrupted pass from being committed as authoritative. A settled
      // failure (server down) lands in neither set.
      manager.debugRegisterClientForTesting(
        _LibrariesClient(
          ServerId('ok'),
          libraries: [MediaLibrary(id: '1', backend: MediaBackend.silo, title: 'Movies', serverId: ServerId('ok'))],
        ),
      );
      manager.debugRegisterClientForTesting(
        _LibrariesClient(
          ServerId('torn-down'),
          error: MediaServerHttpException(type: MediaServerHttpErrorType.cancelled, message: 'HTTP client is closing'),
        ),
      );
      manager.debugRegisterClientForTesting(
        _LibrariesClient(
          ServerId('down'),
          error: MediaServerHttpException(type: MediaServerHttpErrorType.connectionError, message: 'refused'),
        ),
      );

      final result = await service.getMediaLibrariesFromAllServers();

      expect(result.libraries.map((l) => l.title), ['Movies']);
      expect(result.succeededServerIds, {'ok'});
      expect(result.cancelledServerIds, {'torn-down'});
    });

    test('search classifies successful, cancelled, and failed servers independently', () async {
      final item = testMediaItem(
        id: 'show-1',
        backend: MediaBackend.silo,
        kind: MediaKind.show,
        title: 'Target',
        serverId: 'ok',
      );
      manager.debugRegisterClientForTesting(_LibrariesClient(ServerId('ok'), searchResults: [item]));
      manager.debugRegisterClientForTesting(
        _LibrariesClient(
          ServerId('cancelled'),
          searchError: MediaServerHttpException(type: MediaServerHttpErrorType.cancelled, message: 'superseded search'),
        ),
      );
      manager.debugRegisterClientForTesting(
        _LibrariesClient(
          ServerId('failed'),
          searchError: MediaServerHttpException(type: MediaServerHttpErrorType.connectionError, message: 'refused'),
        ),
      );

      final result = await service.searchAcrossServers('Target');

      expect(_hitIds(result), ['show-1']);
      expect(result.succeededServerIds, {'ok'});
      expect(result.cancelledServerIds, {'cancelled'});
      expect(result.failedServerIds, {'failed'});
    });

    test('a server that stops answering fails search on its own at the per-server deadline', () {
      fakeAsync((async) {
        final item = testMediaItem(
          id: 'show-1',
          backend: MediaBackend.silo,
          kind: MediaKind.show,
          title: 'Target',
          serverId: 'ok',
        );
        manager.debugRegisterClientForTesting(_LibrariesClient(ServerId('ok'), searchResults: [item]));
        final hung = _LibrariesClient(ServerId('hung'), hangSearch: true, hangPeople: true);
        manager.debugRegisterClientForTesting(hung);

        SearchAggregationResult? result;
        service.searchAcrossServers('Target').then((r) => result = r);
        async.elapse(MediaServerTimeouts.searchServerDeadline - const Duration(seconds: 1));
        expect(result, isNull, reason: 'a slow server is still waited for inside its deadline');

        async.elapse(const Duration(seconds: 1));
        expect(_hitIds(result!), ['show-1']);
        expect(result!.succeededServerIds, {'ok'});
        expect(result!.failedServerIds, {'hung'}, reason: 'a missed deadline is a failure, not a cancellation');
        expect(result!.cancelledServerIds, isEmpty);
        expect(hung.lastSearchAbort?.isAborted, isTrue, reason: 'the abandoned request is torn down');
        expect(hung.lastPeopleAbort?.isAborted, isTrue);
      });
    });

    test('a stalled people search costs the server its people, never its titles', () {
      fakeAsync((async) {
        final item = testMediaItem(
          id: 'movie-1',
          backend: MediaBackend.silo,
          kind: MediaKind.movie,
          title: 'Target',
          serverId: 'srv',
        );
        manager.debugRegisterClientForTesting(
          _LibrariesClient(ServerId('srv'), searchResults: [item], hangPeople: true),
        );

        SearchAggregationResult? result;
        service.searchAcrossServers('Target').then((r) => result = r);
        async.elapse(MediaServerTimeouts.searchServerDeadline);

        expect(_hitIds(result!), ['movie-1']);
        expect(result!.people, isEmpty);
        expect(result!.succeededServerIds, {'srv'});
      });
    });

    test('a superseded search still cancels a server inside its deadline', () {
      fakeAsync((async) {
        final hung = _LibrariesClient(ServerId('hung'), hangSearch: true);
        manager.debugRegisterClientForTesting(hung);
        final abort = AbortController();

        Object? error;
        SearchAggregationResult? result;
        service
            .searchAcrossServers('Target', abort: abort)
            .then<void>(
              (r) => result = r,
              onError: (Object e) {
                error = e;
              },
            );
        async.flushMicrotasks();
        abort.abort();
        async.flushMicrotasks();

        expect(hung.lastSearchAbort?.isAborted, isTrue);
        expect(result, isNull);
        expect(error, isA<MediaServerHttpException>().having((e) => e.isCancellation, 'isCancellation', isTrue));
      });
    });

    test('a server that stops answering its library list fails on its own at the per-server deadline', () {
      fakeAsync((async) {
        manager.debugRegisterClientForTesting(
          _LibrariesClient(
            ServerId('ok'),
            libraries: [MediaLibrary(id: '1', backend: MediaBackend.silo, title: 'Movies', serverId: ServerId('ok'))],
          ),
        );
        manager.debugRegisterClientForTesting(_LibrariesClient(ServerId('hung'), hangLibraries: true));

        LibraryAggregationResult? result;
        service.getMediaLibrariesFromAllServers().then((r) => result = r);
        async.elapse(MediaServerTimeouts.libraryListServerDeadline - const Duration(seconds: 1));
        expect(result, isNull);

        async.elapse(const Duration(seconds: 1));
        expect(result!.libraries.map((l) => l.title), ['Movies']);
        expect(result!.succeededServerIds, {'ok'});
        expect(result!.failedServerIds, {'hung'});
      });
    });

    test('searchAcrossServers drops hidden-library results and keeps unattributed ones', () async {
      final visible = testMediaItem(
        id: 'visible-1',
        backend: MediaBackend.silo,
        kind: MediaKind.movie,
        title: 'Target',
        serverId: 'srv',
        libraryId: '1',
      );
      final hidden = testMediaItem(
        id: 'hidden-1',
        backend: MediaBackend.silo,
        kind: MediaKind.movie,
        title: 'Target',
        serverId: 'srv',
        libraryId: '2',
      );
      // Search can return shared rows that carry no local library. The user cannot have hidden a library that isn't theirs, so
      // an unattributed row must survive the filter.
      final unattributed = testMediaItem(
        id: 'shared-1',
        backend: MediaBackend.silo,
        kind: MediaKind.movie,
        title: 'Target',
        serverId: 'srv',
      );
      manager.debugRegisterClientForTesting(
        _LibrariesClient(ServerId('srv'), searchResults: [visible, hidden, unattributed]),
      );

      final result = await service.searchAcrossServers('Target', hiddenLibraryKeys: {'srv:2'});

      expect(_hitIds(result), unorderedEquals(['visible-1', 'shared-1']));
      expect(result.succeededServerIds, {'srv'});
    });

    test('hidden-library results are dropped before the ranking limit is spent', () async {
      // The hidden row is the exact-title match, so it outranks the visible
      // one. Filtering after ranking would let it consume the single slot and
      // return nothing at all.
      final hidden = testMediaItem(
        id: 'hidden-1',
        backend: MediaBackend.silo,
        kind: MediaKind.movie,
        title: 'Target',
        serverId: 'srv',
        libraryId: '2',
      );
      final visible = testMediaItem(
        id: 'visible-1',
        backend: MediaBackend.silo,
        kind: MediaKind.movie,
        title: 'Target Sequel',
        serverId: 'srv',
        libraryId: '1',
      );
      manager.debugRegisterClientForTesting(_LibrariesClient(ServerId('srv'), searchResults: [hidden, visible]));

      final result = await service.searchAcrossServers('Target', limit: 1, hiddenLibraryKeys: {'srv:2'});

      expect(_hitIds(result), ['visible-1']);
    });

    test('candidates keeps rows the ranked limit dropped, minus hidden ones', () async {
      // The search screen's kind filter re-ranks `candidates`, so a kind
      // crowded out of the trimmed `items` must still be present there — but
      // a hidden library's rows must not be.
      final movie = testMediaItem(
        id: 'movie-1',
        backend: MediaBackend.silo,
        kind: MediaKind.movie,
        title: 'Target',
        serverId: 'srv',
        libraryId: '1',
      );
      final episode = testMediaItem(
        id: 'episode-1',
        backend: MediaBackend.silo,
        kind: MediaKind.episode,
        title: 'Target Sequel',
        serverId: 'srv',
        libraryId: '1',
      );
      final hidden = testMediaItem(
        id: 'hidden-1',
        backend: MediaBackend.silo,
        kind: MediaKind.track,
        title: 'Target',
        serverId: 'srv',
        libraryId: '2',
      );
      manager.debugRegisterClientForTesting(_LibrariesClient(ServerId('srv'), searchResults: [movie, episode, hidden]));

      final result = await service.searchAcrossServers('Target', limit: 1, hiddenLibraryKeys: {'srv:2'});

      expect(_hitIds(result), ['movie-1']);
      expect(result.candidates.map((item) => item.id), unorderedEquals(['movie-1', 'episode-1']));
    });

    test('each server is told only about its own hidden libraries', () async {
      // Global keys are cross-server; a backend that scopes its search needs
      // the bare library ids it actually owns, and none of its neighbour's.
      final alpha = _LibrariesClient(ServerId('alpha'));
      final beta = _LibrariesClient(ServerId('beta'));
      manager.debugRegisterClientForTesting(alpha);
      manager.debugRegisterClientForTesting(beta);

      await service.searchAcrossServers('Target', hiddenLibraryKeys: {'alpha:1', 'alpha:9', 'beta:1'});

      expect(alpha.lastExcludedLibraryIds, {'1', '9'});
      expect(beta.lastExcludedLibraryIds, {'1'});
      // People span libraries, so each backend drops hidden-only people itself
      // and needs the same scoping.
      expect(alpha.lastPeopleExcludedLibraryIds, {'1', '9'});
      expect(beta.lastPeopleExcludedLibraryIds, {'1'});
    });

    test('a failed or cancelled people search keeps that server\'s titles and success', () async {
      final failingPeople = testMediaItem(
        id: 'movie-a',
        backend: MediaBackend.silo,
        kind: MediaKind.movie,
        title: 'Target',
        serverId: 'a',
      );
      final cancelledPeople = testMediaItem(
        id: 'movie-b',
        backend: MediaBackend.silo,
        kind: MediaKind.movie,
        title: 'Target',
        serverId: 'b',
      );
      manager.debugRegisterClientForTesting(
        _LibrariesClient(
          ServerId('a'),
          searchResults: [failingPeople],
          peopleError: MediaServerHttpException(type: MediaServerHttpErrorType.connectionError, message: 'refused'),
        ),
      );
      manager.debugRegisterClientForTesting(
        _LibrariesClient(
          ServerId('b'),
          searchResults: [cancelledPeople],
          peopleError: MediaServerHttpException(type: MediaServerHttpErrorType.cancelled, message: 'closing'),
        ),
      );

      final result = await service.searchAcrossServers('Target');

      expect(_hitIds(result), unorderedEquals(['movie-a', 'movie-b']));
      expect(result.people, isEmpty);
      expect(result.succeededServerIds, {'a', 'b'});
      expect(result.failedServerIds, isEmpty);
      expect(result.cancelledServerIds, isEmpty);
    });

    test('titles and people rank on one scale', () async {
      // An exact title outranks a person whose name merely contains the
      // query; a person whose name is the query outranks a loose title.
      manager.debugRegisterClientForTesting(
        _LibrariesClient(
          ServerId('srv'),
          searchResults: [
            testMediaItem(
              id: 'oppenheimer',
              backend: MediaBackend.silo,
              kind: MediaKind.movie,
              title: 'Oppenheimer',
              serverId: 'srv',
            ),
            testMediaItem(
              id: 'waltz-with-bashir',
              backend: MediaBackend.silo,
              kind: MediaKind.movie,
              title: 'Waltz with Bashir',
              serverId: 'srv',
            ),
          ],
          peopleResults: [
            _person('38906', 'Brianna Oppenheimer', serverId: 'srv'),
            _person('38797', 'Christoph Waltz', serverId: 'srv'),
          ],
        ),
      );

      final byTitle = await service.searchAcrossServers('Oppenheimer');
      final byPerson = await service.searchAcrossServers('Christoph Waltz');

      expect(_hitIds(byTitle).take(2), ['oppenheimer', 'person:38906']);
      expect(_hitIds(byPerson).first, 'person:38797');
      expect(byPerson.people.map((person) => person.id), unorderedEquals(['38906', '38797']));
    });

    test('a query only people match still returns hits', () async {
      manager.debugRegisterClientForTesting(
        _LibrariesClient(ServerId('srv'), peopleResults: [_person('38797', 'Christoph Waltz', serverId: 'srv')]),
      );

      final result = await service.searchAcrossServers('Christoph Waltz');

      expect(_hitIds(result), ['person:38797']);
      expect(result.candidates, isEmpty);
      expect(result.succeededServerIds, {'srv'});
    });

    test('no hidden libraries passes an empty exclusion set', () async {
      final client = _LibrariesClient(ServerId('alpha'));
      manager.debugRegisterClientForTesting(client);

      await service.searchAcrossServers('Target');

      expect(client.lastExcludedLibraryIds, isEmpty);
    });

    test('searchAcrossServers overfetches and ranks before trimming across servers', () async {
      final other = _LibrariesClient(
        ServerId('silo-2'),
        searchResults: [
          testMediaItem(
            id: 'other-movie',
            backend: MediaBackend.silo,
            kind: MediaKind.movie,
            title: 'Spider Man Returns',
            serverId: 'silo-2',
          ),
        ],
      );
      manager.debugRegisterClientForTesting(other);

      final silo = _LibrariesClient(
        ServerId('silo-1'),
        searchResults: [
          testMediaItem(
            id: 'silo-show',
            backend: MediaBackend.silo,
            kind: MediaKind.show,
            title: 'Spider‑Man',
            serverId: 'silo-1',
          ),
        ],
      );
      manager.debugRegisterClientForTesting(silo);

      final results = await service.searchAcrossServers('Spider Man', limit: 1);

      expect(_hitIds(results), ['silo-show']);
      // Every server gets the full candidate budget, not the trimmed limit.
      expect(other.lastSearchLimit, 100);
      expect(silo.lastSearchLimit, 100);
    });

    test('getOnDeckFromAllServers forwards preview limit to clients', () async {
      final client = registerContinueWatching([_row('movie-1', title: 'Movie 1')]);

      final result = await service.getOnDeckFromAllServers(limit: 21);

      expect(result.items.map((item) => item.id), ['movie-1']);
      expect(result.succeededServerIds, {'silo-1'});
      expect(client.continueWatchingCounts, [21]);
    });

    test('getOnDeckFromAllServers filters hidden continue-watching libraries', () async {
      registerContinueWatching([
        _row('movie-visible', title: 'Visible Movie', lastViewedAt: 100, libraryId: '1'),
        _row('movie-hidden', title: 'Hidden Movie', lastViewedAt: 200, libraryId: '2'),
      ]);

      final result = await service.getOnDeckFromAllServers(limit: 10, hiddenLibraryKeys: {'silo-1:2'});

      expect(result.items.map((item) => item.id), ['movie-visible']);
      expect(result.succeededServerIds, {'silo-1'});
    });

    test('getOnDeckFromAllServers hides duplicate show entries by stable show ids', () async {
      registerContinueWatching(
        [
          _row(
            'old-episode',
            kind: MediaKind.episode,
            title: 'Episode 1',
            grandparentId: 'old-show',
            grandparentTitle: 'Shared Show',
            lastViewedAt: 100,
            libraryId: '1',
          ),
          _row(
            'new-episode',
            kind: MediaKind.episode,
            title: 'Episode 2',
            grandparentId: 'new-show',
            grandparentTitle: 'Shared Show',
            lastViewedAt: 200,
            libraryId: '2',
          ),
        ],
        externalIds: const {'old-show': ExternalIds(tvdb: 12345), 'new-show': ExternalIds(tvdb: 12345)},
      );

      final result = await service.getOnDeckFromAllServers(limit: 10);

      expect(result.items.map((item) => item.id), ['new-episode']);
      expect(result.succeededServerIds, {'silo-1'});
    });

    test('getOnDeckFromAllServers prefers the locally last-played duplicate sibling', () async {
      // Two libraries carry the same show (1080p + 4K, matched by tvdb id);
      // the server syncs watch state so lastViewedAt favours neither
      // reliably. The locally recorded play must decide the surviving card —
      // and it must keep the winner in the group's original shelf slot,
      // ahead of the unrelated movie sorted between the two episodes (#1492).
      registerContinueWatching(
        [
          _row(
            'hd-episode',
            kind: MediaKind.episode,
            title: 'Episode 1',
            grandparentId: 'hd-show',
            grandparentTitle: 'Shared Show',
            lastViewedAt: 200,
            libraryId: '1',
          ),
          _row('movie-between', title: 'Unrelated Movie', lastViewedAt: 150),
          _row(
            'uhd-episode',
            kind: MediaKind.episode,
            title: 'Episode 1',
            grandparentId: 'uhd-show',
            grandparentTitle: 'Shared Show',
            lastViewedAt: 100,
            libraryId: '2',
          ),
        ],
        externalIds: const {'hd-show': ExternalIds(tvdb: 12345), 'uhd-show': ExternalIds(tvdb: 12345)},
      );

      // The user last played something in the 4K library's show tree.
      final settings = await SettingsService.getInstance();
      await settings.write(SettingsService.localLastPlayedAt, {'silo-1:uhd-show': 999999});

      final result = await service.getOnDeckFromAllServers(limit: 10);

      // uhd-episode wins the duplicate group and takes the group's slot
      // (before the movie); without local history hd-episode (newest
      // lastViewedAt) would have survived.
      expect(result.items.map((item) => item.id), ['uhd-episode', 'movie-between']);
    });

    test('getOnDeckFromAllServers prefers a duplicate recorded by item key', () async {
      registerContinueWatching(
        [
          _row('movie-hd', title: 'Shared Movie', lastViewedAt: 200, libraryId: '1'),
          _row('movie-uhd', title: 'Shared Movie', lastViewedAt: 100, libraryId: '2'),
        ],
        externalIds: const {'movie-hd': ExternalIds(tmdb: 777), 'movie-uhd': ExternalIds(tmdb: 777)},
      );

      final settings = await SettingsService.getInstance();
      await settings.write(SettingsService.localLastPlayedAt, {'silo-1:movie-uhd': 999999});

      final result = await service.getOnDeckFromAllServers(limit: 10);

      expect(result.items.map((item) => item.id), ['movie-uhd']);
    });

    test('getOnDeckFromAllServers keeps duplicate titles without stable ids', () async {
      registerContinueWatching([
        _row(
          'old-unmatched',
          kind: MediaKind.episode,
          title: 'Episode 1',
          grandparentId: 'old-unmatched-show',
          grandparentTitle: 'Shared Show',
          lastViewedAt: 100,
        ),
        _row(
          'new-unmatched',
          kind: MediaKind.episode,
          title: 'Episode 2',
          grandparentId: 'new-unmatched-show',
          grandparentTitle: 'Shared Show',
          lastViewedAt: 200,
        ),
      ]);

      final result = await service.getOnDeckFromAllServers(limit: 10);

      expect(result.items.map((item) => item.id), ['new-unmatched', 'old-unmatched']);
      expect(result.succeededServerIds, {'silo-1'});
    });

    test('global home layout falls back to per-library hubs without rich hubs', () async {
      final client = _PerLibraryHubsClient([_library('movies', MediaKind.movie), _library('shows', MediaKind.show)]);
      manager.debugRegisterClientForTesting(client);

      final result = await service.getHubsFromAllServers(useGlobalHubs: true, includePlaybackHubs: false);

      expect(result.succeededServerIds, {'server-1'});
      expect(result.hubs.map((h) => h.identifier), ['library.movies.recent', 'library.shows.recent']);
      expect(result.hubs.map((h) => h.items.single.id), ['item-movies', 'item-shows']);
      expect(client.fetchLibrariesCalls, 1);
      expect(client.hubCalls.map((call) => call.libraryId), ['movies', 'shows']);
      expect(client.hubCalls.map((call) => call.limit), everyElement(defaultHubPreviewLimit));
    });

    test('per-library home rows include clip and music libraries and skip photo (#1476)', () async {
      final client = _PerLibraryHubsClient([
        _library('movies', MediaKind.movie),
        _library('mv', MediaKind.clip),
        _library('home-vids', MediaKind.clip),
        _library('music', MediaKind.artist),
        _library('photos', MediaKind.photo),
      ]);
      manager.debugRegisterClientForTesting(client);

      final result = await service.getHubsFromAllServers(useGlobalHubs: true, includePlaybackHubs: false);

      expect(result.succeededServerIds, {'server-1'});
      expect(result.hubs.map((h) => h.identifier), [
        'library.movies.recent',
        'library.mv.recent',
        'library.home-vids.recent',
        'library.music.recent',
      ]);
      expect(client.hubCalls.map((call) => call.libraryId), ['movies', 'mv', 'home-vids', 'music']);
      expect(
        client.hubCalls.map((call) => call.includePlaybackHubs),
        everyElement(isFalse),
        reason: 'the home screen excludes playback-derived rows',
      );
    });
  });
}
