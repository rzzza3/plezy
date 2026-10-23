import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/exceptions/media_server_exceptions.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/services/catalog/catalog_library_matcher.dart';
import 'package:plezy/services/data_aggregation_service.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/utils/external_ids.dart';

import '../../test_helpers/library_lookup.dart';
import '../../test_helpers/media_items.dart';

class _LookupCall {
  final ExternalIds ids;
  final List<String> titles;
  final int? year;

  const _LookupCall({required this.ids, required this.titles, required this.year});
}

class _FakeDataAggregationService extends DataAggregationService {
  _FakeDataAggregationService(super.serverManager);

  final List<_LookupCall> calls = [];
  final List<LibraryLookupResult> responses = [];

  @override
  Future<LibraryLookupResult> findByExternalIdsAcrossServers(
    ExternalIds ids, {
    required MediaKind kind,
    required Set<String> serverIds,
    List<String> titles = const [],
    int? year,
    ExternalSeasonRef? season,
  }) async {
    calls.add(_LookupCall(ids: ids, titles: List.of(titles), year: year));
    return responses.removeAt(0);
  }
}

class _Harness {
  late final MultiServerManager manager;
  late final _FakeDataAggregationService aggregation;
  late final MultiServerProvider multiServer;
  late final CatalogLibraryMatcher matcher;

  _Harness({DateTime Function()? now}) {
    manager = MultiServerManager();
    aggregation = _FakeDataAggregationService(manager);
    multiServer = MultiServerProvider(manager, aggregation);
    matcher = now == null ? CatalogLibraryMatcher(multiServer) : CatalogLibraryMatcher.withClock(multiServer, now);
  }

  void dispose() {
    matcher.dispose();
    multiServer.dispose();
    manager.dispose();
  }
}

/// A server that answers the reverse lookup with [copies], or throws [error]
/// to model one that could not be reached.
class _LookupClient implements MediaServerClient {
  _LookupClient(String id, {this.copies = const [], this.error}) : serverId = ServerId(id);

  @override
  final ServerId serverId;
  List<MediaItem>? copies;
  Object? error;
  Completer<List<MediaItem>?>? pending;
  int calls = 0;

  @override
  Future<List<MediaItem>?> findByExternalIds(
    ExternalIds ids, {
    required MediaKind kind,
    List<String> titles = const [],
    int? year,
    ExternalSeasonRef? season,
  }) async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    return pending == null ? copies : await pending!.future;
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A matcher over the real [DataAggregationService] and [MultiServerManager].
/// Only they can tell a registered-but-offline server (never asked) from one
/// that left the account, so a canned-response harness cannot model it.
class _LiveHarness {
  final MultiServerManager manager = MultiServerManager();
  late final MultiServerProvider multiServer;
  late final CatalogLibraryMatcher matcher;

  _LiveHarness(DateTime Function() now) {
    multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    matcher = CatalogLibraryMatcher.withClock(multiServer, now);
  }

  void register(MediaServerClient client, {bool online = true}) =>
      manager.debugRegisterClientForTesting(client, online: online);

  void dispose() {
    matcher.dispose();
    multiServer.dispose();
    manager.dispose();
  }
}

void main() {
  test('cancelled and non-queryable retries retain copies until this server executes a miss', () async {
    var now = DateTime.utc(2026, 7, 28);
    final harness = _LiveHarness(() => now);
    addTearDown(harness.dispose);
    final copy = testMediaItem(id: 'retained', serverId: 'a');
    final a = _LookupClient('a', copies: [copy]);
    final b = _LookupClient('b', error: StateError('offline'));
    harness.register(a);
    harness.register(b);
    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Retained Movie',
      ids: CatalogItemIds(tmdb: 42),
    );
    expect((await harness.matcher.match(item)).items, [copy]);

    a.error = MediaServerHttpException(type: MediaServerHttpErrorType.cancelled);
    b.error = null;
    now = now.add(CatalogLibraryMatcher.negativeTtl);
    final cancelled = await harness.matcher.match(item);
    expect(cancelled.items, [copy]);
    expect(cancelled.cancelledServerIds, {'a'});
    expect(cancelled.failedServerIds, isEmpty);

    a
      ..error = null
      ..copies = null;
    now = now.add(CatalogLibraryMatcher.negativeTtl);
    final unqueried = await harness.matcher.match(item);
    expect(unqueried.items, [copy]);
    expect(unqueried.unqueriedServerIds, {'a'});
    expect(unqueried.succeededServerIds, {'b'});
    now = now.add(CatalogLibraryMatcher.negativeTtl - const Duration(seconds: 1));
    expect(await harness.matcher.match(item), same(unqueried));

    a.copies = const [];
    now = now.add(const Duration(seconds: 1));
    final removed = await harness.matcher.match(item);
    expect(removed.items, isEmpty);
    expect(removed.succeededServerIds, {'a', 'b'});
    expect(removed.unqueriedServerIds, isEmpty);
  });

  test('membership additions retry positive caches while retaining offline copies still in scope', () async {
    final harness = _LiveHarness(() => DateTime.utc(2026, 7, 28));
    addTearDown(harness.dispose);
    final aCopy = testMediaItem(id: 'a-copy', serverId: 'a');
    final bCopy = testMediaItem(id: 'b-copy', serverId: 'b');
    final a = _LookupClient('a', copies: [aCopy]);
    final b = _LookupClient('b', copies: [bCopy]);
    harness.register(a);
    harness.register(b);
    harness.multiServer.setExpectedVisibleServerIds({'a'});
    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Membership Movie',
      ids: CatalogItemIds(tmdb: 42),
    );
    expect((await harness.matcher.match(item)).items, [aCopy]);
    expect(b.calls, 0);

    harness.register(a, online: false);
    harness.multiServer.setExpectedVisibleServerIds({'a', 'b'});
    final added = await harness.matcher.match(item);
    expect(added.items, [aCopy, bCopy]);
    expect(added.unqueriedServerIds, {'a'});
    expect(added.succeededServerIds, {'b'});

    // Remove and re-add between taps: membership notifications must prune A's
    // old copy even though the next lookup sees the same final set.
    harness.multiServer.setExpectedVisibleServerIds({'b'});
    harness.multiServer.setExpectedVisibleServerIds({'a', 'b'});
    final readded = await harness.matcher.match(item);
    expect(readded.items, [bCopy]);
    expect(readded.unqueriedServerIds, {'a'});
    expect(b.calls, 2);

    harness.multiServer.setExpectedVisibleServerIds({'b'});
    final removed = await harness.matcher.match(item);
    expect(removed.items, [bCopy]);
    expect(removed.unqueriedServerIds, isEmpty);
    expect(removed.succeededServerIds, {'b'});
  });

  test('a membership change during lookup cannot publish or cache the departed server response', () async {
    final harness = _LiveHarness(() => DateTime.utc(2026, 7, 28));
    addTearDown(harness.dispose);
    final aCopy = testMediaItem(id: 'a-copy', serverId: 'a');
    final bCopy = testMediaItem(id: 'b-copy', serverId: 'b');
    final a = _LookupClient('a')..pending = Completer<List<MediaItem>?>();
    final b = _LookupClient('b', copies: [bCopy]);
    harness.register(a);
    harness.register(b);
    harness.multiServer.setExpectedVisibleServerIds({'a'});
    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'In-flight Movie',
      ids: CatalogItemIds(tmdb: 42),
    );

    final pending = harness.matcher.match(item);
    harness.multiServer.setExpectedVisibleServerIds({'b'});
    a.pending!.complete([aCopy]);
    final result = await pending;
    expect(result.items, [bCopy]);
    expect(result.succeededServerIds, {'b'});
    expect(result.unqueriedServerIds, isEmpty);
    expect((await harness.matcher.match(item)).items, [bCopy]);
  });

  test('a weaker cached hit cannot suppress failed richer-query retries or recovery', () async {
    var now = DateTime.utc(2026, 7, 28);
    final harness = _Harness(now: () => now);
    addTearDown(harness.dispose);
    final bareCopy = testMediaItem(id: 'bare-copy', serverId: 'a');
    final nativeCopy = testMediaItem(id: 'native-copy', serverId: 'a');
    harness.aggregation.responses.addAll([
      libraryLookupResult([bareCopy], succeeded: {'a'}),
      libraryLookupResult(const [], failed: {'a'}),
      libraryLookupResult([bareCopy, nativeCopy], succeeded: {'a'}),
    ]);
    const bare = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Night on the Galactic Railroad',
      ids: CatalogItemIds(slug: '5d776b59ad5437001f79c6f8'),
    );
    const enriched = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Night on the Galactic Railroad',
      originalTitle: '銀河鉄道の夜',
      ids: CatalogItemIds(slug: '5d776b59ad5437001f79c6f8', tmdb: 34523),
    );

    expect((await harness.matcher.match(bare)).items, [bareCopy]);
    final failed = await harness.matcher.match(enriched);
    expect(failed.failedServerIds, {'a'});
    expect(failed.succeededServerIds, isEmpty);
    expect((await harness.matcher.match(bare)).items, [bareCopy]);
    now = now.add(CatalogLibraryMatcher.negativeTtl - const Duration(seconds: 1));
    expect(await harness.matcher.match(enriched), same(failed));
    now = now.add(const Duration(seconds: 1));
    final recovered = await harness.matcher.match(enriched);
    expect(recovered.items, [bareCopy, nativeCopy]);
    expect(recovered.succeededServerIds, {'a'});
    expect(recovered.failedServerIds, isEmpty);
  });

  test('season entries sharing canonical ids keep independent cached matches', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final firstHit = testMediaItem(id: 'server-season-1', kind: MediaKind.show);
    final secondHit = testMediaItem(id: 'server-season-2', kind: MediaKind.show);
    harness.aggregation.responses.addAll([
      libraryLookupResult([firstHit]),
      libraryLookupResult([secondHit]),
    ]);
    const first = CatalogItem(
      source: CatalogSourceId.mal,
      kind: MediaKind.show,
      title: 'Mushoku Tensei',
      ids: CatalogItemIds(mal: 39535, imdb: 'tt13293588'),
    );
    const second = CatalogItem(
      source: CatalogSourceId.mal,
      kind: MediaKind.show,
      title: 'Mushoku Tensei II',
      ids: CatalogItemIds(mal: 51179, imdb: 'tt13293588'),
    );

    expect(first.identityKey, second.identityKey);
    expect(first.entryIdentityKey, isNot(second.entryIdentityKey));
    expect((await harness.matcher.match(first)).items.single, same(firstHit));
    expect((await harness.matcher.match(second)).items.single, same(secondHit));
    expect((await harness.matcher.match(first)).items.single, same(firstHit));
    expect(harness.aggregation.calls, hasLength(2));
  });

  test('negative cache entries are isolated by catalog source', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final anilistHit = testMediaItem(id: 'japanese-title-match', kind: MediaKind.show);
    harness.aggregation.responses.addAll([
      libraryLookupResult(const []),
      libraryLookupResult([anilistHit]),
    ]);
    const malItem = CatalogItem(
      source: CatalogSourceId.mal,
      kind: MediaKind.show,
      title: 'English Title',
      ids: CatalogItemIds(mal: 100, tmdb: 200),
    );
    const anilistItem = CatalogItem(
      source: CatalogSourceId.anilist,
      kind: MediaKind.show,
      title: 'English Title',
      originalTitle: '日本語タイトル',
      ids: CatalogItemIds(mal: 100, anilist: 300, tmdb: 200),
    );

    expect(malItem.entryIdentityKey, anilistItem.entryIdentityKey);
    expect((await harness.matcher.match(malItem)).items, isEmpty);
    expect((await harness.matcher.match(anilistItem)).items.single, same(anilistHit));
    expect(harness.aggregation.calls, hasLength(2));
    expect(harness.aggregation.calls.last.titles, contains('日本語タイトル'));
  });

  test('negative matches expire after negativeTtl while positive matches persist', () async {
    var now = DateTime.utc(2026, 7, 28, 12);
    final harness = _Harness(now: () => now);
    addTearDown(harness.dispose);
    final hit = testMediaItem(id: 'new-library-item', kind: MediaKind.show);
    harness.aggregation.responses.addAll([
      libraryLookupResult(const []),
      libraryLookupResult([hit]),
    ]);
    const item = CatalogItem(
      source: CatalogSourceId.anilist,
      kind: MediaKind.show,
      title: 'New Show',
      ids: CatalogItemIds(anilist: 1, tmdb: 42),
    );

    expect((await harness.matcher.match(item)).items, isEmpty);
    now = now.add(CatalogLibraryMatcher.negativeTtl - const Duration(seconds: 1));
    expect((await harness.matcher.match(item)).items, isEmpty);
    expect(harness.aggregation.calls, hasLength(1));

    now = now.add(const Duration(seconds: 1));
    expect((await harness.matcher.match(item)).items.single, same(hit));
    expect(harness.aggregation.calls, hasLength(2));

    now = now.add(const Duration(days: 30));
    expect((await harness.matcher.match(item)).items.single, same(hit));
    expect(harness.aggregation.calls, hasLength(2));
  });

  test('a wave a server sat out is retried after negativeTtl even when it found copies', () async {
    // #2098: a slow server timing out is not evidence the title is absent
    // there. The degraded answer is shown, with the failed server named, but
    // it must not be memoized for the session like an authoritative hit.
    var now = DateTime.utc(2026, 7, 28, 12);
    final harness = _Harness(now: () => now);
    addTearDown(harness.dispose);
    final fastCopy = testMediaItem(id: 'fast-copy', serverId: 'fast');
    final slowCopy = testMediaItem(id: 'slow-copy', serverId: 'slow');
    harness.aggregation.responses.addAll([
      libraryLookupResult([fastCopy], succeeded: {'fast'}, failed: {'slow'}),
      libraryLookupResult([fastCopy, slowCopy], succeeded: {'fast', 'slow'}),
    ]);
    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Slow Server Movie',
      ids: CatalogItemIds(trakt: 9, tmdb: 77),
    );

    final degraded = await harness.matcher.match(item);
    expect(degraded.items, [fastCopy]);
    expect(degraded.failedServerIds, {'slow'});
    now = now.add(CatalogLibraryMatcher.negativeTtl - const Duration(seconds: 1));
    expect(await harness.matcher.match(item), same(degraded));
    expect(harness.aggregation.calls, hasLength(1));

    now = now.add(const Duration(seconds: 1));
    expect((await harness.matcher.match(item)).items, [fastCopy, slowCopy]);
    expect(harness.aggregation.calls, hasLength(2));
    now = now.add(const Duration(days: 30));
    expect((await harness.matcher.match(item)).items, [fastCopy, slowCopy]);
    expect(harness.aggregation.calls, hasLength(2), reason: 'every server answered, so the hit is kept');
  });

  test('a server that sits out the retry keeps its last-known copies until it answers itself', () async {
    // Wave 1: A holds a copy, B is unreachable. After negativeTtl, wave 2:
    // A is unreachable, B answers empty. A's copy is verified and nothing
    // says A removed it, so it stays; only A's own answer may replace it.
    var now = DateTime.utc(2026, 7, 28, 12);
    final harness = _Harness(now: () => now);
    addTearDown(harness.dispose);
    final aCopy = testMediaItem(id: 'a-copy', serverId: 'a');
    harness.aggregation.responses.addAll([
      libraryLookupResult([aCopy], succeeded: {'a'}, failed: {'b'}),
      libraryLookupResult(const [], succeeded: {'b'}, failed: {'a'}),
      libraryLookupResult(const [], succeeded: {'a', 'b'}),
    ]);
    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Flaky Servers Movie',
      ids: CatalogItemIds(trakt: 10, tmdb: 78),
    );

    expect((await harness.matcher.match(item)).items, [aCopy]);
    now = now.add(CatalogLibraryMatcher.negativeTtl);
    final retained = await harness.matcher.match(item);
    expect(retained.items, [aCopy]);
    expect(retained.failedServerIds, {'a'});
    expect(retained.succeededServerIds, {'b'});
    expect(harness.aggregation.calls, hasLength(2));

    // A answering empty for itself is the evidence that the copy is gone.
    now = now.add(CatalogLibraryMatcher.negativeTtl);
    expect((await harness.matcher.match(item)).items, isEmpty);
    expect(harness.aggregation.calls, hasLength(3));
  });

  test('a registered server that is offline for the retry keeps its copies and stays retryable', () async {
    // An offline server is not in the fan-out at all, so it answers in no
    // set — indistinguishable, to the fold, from one that left the account.
    // It never said the title was gone, and the surviving wave must not be
    // memoized as a complete answer for the session either.
    var now = DateTime.utc(2026, 7, 28, 12);
    final harness = _LiveHarness(() => now);
    addTearDown(harness.dispose);
    final aCopy = testMediaItem(id: 'a-copy', serverId: 'a');
    final bCopy = testMediaItem(id: 'b-copy', serverId: 'b');
    final a = _LookupClient('a', copies: [aCopy]);
    final b = _LookupClient('b', error: StateError('unreachable'));
    harness.register(a);
    harness.register(b);
    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Offline Server Movie',
      ids: CatalogItemIds(trakt: 11, tmdb: 79),
    );

    expect((await harness.matcher.match(item)).items, [aCopy]);

    // A drops offline, B recovers and answers for itself.
    harness.register(a, online: false);
    b
      ..error = null
      ..copies = [bCopy];
    now = now.add(CatalogLibraryMatcher.negativeTtl);

    final retained = await harness.matcher.match(item);
    expect(retained.items, [aCopy, bCopy], reason: 'A was never asked, so its verified copy stands');
    expect(a.calls, 1);

    // Only A's own answer may drop A's copy, so the wave stays retryable.
    harness.register(a);
    a.copies = const [];
    now = now.add(CatalogLibraryMatcher.negativeTtl);
    expect((await harness.matcher.match(item)).items, [bCopy]);
    expect(a.calls, 2);
  });

  test('a wave with no online server keeps known copies and is not an authoritative absence', () async {
    var now = DateTime.utc(2026, 7, 28, 12);
    final harness = _LiveHarness(() => now);
    addTearDown(harness.dispose);
    final aCopy = testMediaItem(id: 'a-copy', serverId: 'a');
    final a = _LookupClient('a', copies: [aCopy]);
    final b = _LookupClient('b', error: StateError('unreachable'));
    harness.register(a);
    harness.register(b);
    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'All Servers Offline Movie',
      ids: CatalogItemIds(trakt: 12, tmdb: 80),
    );

    expect((await harness.matcher.match(item)).items, [aCopy]);

    harness.register(a, online: false);
    harness.register(b, online: false);
    now = now.add(CatalogLibraryMatcher.negativeTtl);

    final blind = await harness.matcher.match(item);
    expect(blind.items, [aCopy], reason: 'a wave nobody answered erases nothing');
    expect(blind.succeededServerIds, isEmpty);

    harness.register(a);
    now = now.add(CatalogLibraryMatcher.negativeTtl);
    expect((await harness.matcher.match(item)).items, [aCopy]);
    expect(a.calls, 2, reason: 'the blind wave is no hit, so the next tap asks again');
  });

  test('a server that left the account loses its copies', () async {
    // The one wave shape that means removal: the server is in no set at all
    // — it neither answered nor sat the wave out, so it is off the account.
    var now = DateTime.utc(2026, 7, 28, 12);
    final harness = _Harness(now: () => now);
    addTearDown(harness.dispose);
    final aCopy = testMediaItem(id: 'a-copy', serverId: 'a');
    final bCopy = testMediaItem(id: 'b-copy', serverId: 'b');
    harness.aggregation.responses.addAll([
      libraryLookupResult([aCopy], succeeded: {'a'}, failed: {'b'}),
      libraryLookupResult([bCopy], succeeded: {'b'}),
    ]);
    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Removed Server Movie',
      ids: CatalogItemIds(trakt: 13, tmdb: 81),
    );

    expect((await harness.matcher.match(item)).items, [aCopy]);
    now = now.add(CatalogLibraryMatcher.negativeTtl);
    expect((await harness.matcher.match(item)).items, [bCopy]);
  });

  test('a retry that lost the library stamp keeps the label from the previous wave', () async {
    // The library stamp is a best-effort extra call. Wave 1 labels the
    // copy; wave 2 — the first every server took part in, so it is memoized
    // for the session — returns the same copy unstamped. J still holds it,
    // and nothing says it moved, so the label survives the replacement.
    var now = DateTime.utc(2026, 7, 28, 12);
    final harness = _Harness(now: () => now);
    addTearDown(harness.dispose);
    final stamped = testMediaItem(id: 'j-copy', serverId: 'j', libraryId: 'lib-1', libraryTitle: 'Movies');
    final unstamped = testMediaItem(id: 'j-copy', serverId: 'j');
    harness.aggregation.responses.addAll([
      libraryLookupResult([stamped], succeeded: {'j'}, failed: {'k'}),
      libraryLookupResult([unstamped], succeeded: {'j', 'k'}),
    ]);
    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Unstamped Retry Movie',
      ids: CatalogItemIds(trakt: 14, tmdb: 82),
    );

    expect((await harness.matcher.match(item)).items, [stamped]);
    now = now.add(CatalogLibraryMatcher.negativeTtl);
    final retried = await harness.matcher.match(item);
    expect(retried.items.single.libraryId, 'lib-1');
    expect(retried.items.single.libraryTitle, 'Movies');
    now = now.add(const Duration(days: 30));
    expect((await harness.matcher.match(item)).items.single.libraryTitle, 'Movies');
    expect(harness.aggregation.calls, hasLength(2), reason: 'the enriched wave is the memoized hit');
  });

  test('a retry that names another library takes its id without the old label', () async {
    var now = DateTime.utc(2026, 7, 28, 12);
    final harness = _Harness(now: () => now);
    addTearDown(harness.dispose);
    final stamped = testMediaItem(id: 'j-copy', serverId: 'j', libraryId: 'lib-1', libraryTitle: 'Movies');
    final moved = testMediaItem(id: 'j-copy', serverId: 'j', libraryId: 'lib-2');
    harness.aggregation.responses.addAll([
      libraryLookupResult([stamped], succeeded: {'j'}, failed: {'k'}),
      libraryLookupResult([moved], succeeded: {'j', 'k'}),
    ]);
    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Moved Library Movie',
      ids: CatalogItemIds(trakt: 15, tmdb: 83),
    );

    expect((await harness.matcher.match(item)).items, [stamped]);
    now = now.add(CatalogLibraryMatcher.negativeTtl);
    final retried = await harness.matcher.match(item);
    expect(retried.items.single.libraryId, 'lib-2');
    expect(retried.items.single.libraryTitle, isNull);
  });

  test('a retry that no longer returns a copy still drops it', () async {
    // Enrichment is per copy; which copies a server holds stays that
    // server's answer alone.
    var now = DateTime.utc(2026, 7, 28, 12);
    final harness = _Harness(now: () => now);
    addTearDown(harness.dispose);
    final stamped = testMediaItem(id: 'j-copy', serverId: 'j', libraryId: 'lib-1', libraryTitle: 'Movies');
    final other = testMediaItem(id: 'j-other', serverId: 'j');
    harness.aggregation.responses.addAll([
      libraryLookupResult([stamped], succeeded: {'j'}, failed: {'k'}),
      libraryLookupResult([other], succeeded: {'j', 'k'}),
    ]);
    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Dropped Copy Movie',
      ids: CatalogItemIds(trakt: 16, tmdb: 84),
    );

    expect((await harness.matcher.match(item)).items, [stamped]);
    now = now.add(CatalogLibraryMatcher.negativeTtl);
    expect((await harness.matcher.match(item)).items, [other]);
  });

  test('keeps the year for an entry that is not a sequel', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.aggregation.responses.add(libraryLookupResult(const []));
    const item = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.show,
      title: 'Severance',
      year: 2022,
      ids: CatalogItemIds(trakt: 1, tvdb: 371980),
    );

    await harness.matcher.match(item);

    final call = harness.aggregation.calls.single;
    expect(call.year, 2022);
    expect(call.titles, ['Severance'], reason: 'nothing to strip, so one candidate and one request');
  });

  test('a failed lookup retains prior verified copies until the server answers a complete miss', () async {
    var now = DateTime.utc(2026, 9, 6);
    final harness = _LiveHarness(() => now);
    addTearDown(harness.dispose);
    final client = _LookupClient(
      'silo',
      copies: [testMediaItem(id: 'owned', backend: MediaBackend.silo, kind: MediaKind.movie, serverId: 'silo')],
    );
    final other = _LookupClient('offline', error: StateError('unavailable'));
    harness.register(client);
    harness.register(other);
    const item = CatalogItem(
      source: CatalogSourceId.mal,
      kind: MediaKind.movie,
      title: 'Kimi no Na wa.',
      altTitles: ['君の名は。'],
      ids: CatalogItemIds(mal: 32281, tmdb: 372058),
    );

    expect((await harness.matcher.match(item)).items.map((copy) => copy.id), ['owned']);
    other.error = null;
    client.error = MediaServerHttpException(type: MediaServerHttpErrorType.unknown, statusCode: 403);
    now = now.add(CatalogLibraryMatcher.negativeTtl);
    final partial = await harness.matcher.match(item);
    expect(partial.items.map((copy) => copy.id), ['owned']);
    expect(partial.failedServerIds, {client.serverId.value});
    expect(partial.succeededServerIds, {'offline'});

    client.error = null;
    client.copies = const [];
    now = now.add(CatalogLibraryMatcher.negativeTtl);
    final absent = await harness.matcher.match(item);
    expect(absent.items, isEmpty);
    expect(absent.failedServerIds, isEmpty);
    expect(absent.succeededServerIds, {client.serverId.value, 'offline'});
  });

  test('a detail load that adds the native title is not served the bare form\'s cached negative', () async {
    // A Plex Discover row carries no originalTitle; the detail body does,
    // and only that title reaches a romaji-filed library.
    final harness = _Harness();
    addTearDown(harness.dispose);
    final romajiCopy = testMediaItem(id: 'romaji-copy', kind: MediaKind.show);
    harness.aggregation.responses.addAll([
      libraryLookupResult(const []),
      libraryLookupResult([romajiCopy]),
    ]);
    const bare = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.show,
      title: "Frieren: Beyond Journey's End",
      ids: CatalogItemIds(slug: '631cc', tvdb: 424536),
    );
    const enriched = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.show,
      title: "Frieren: Beyond Journey's End",
      originalTitle: '葬送のフリーレン',
      ids: CatalogItemIds(slug: '631cc', tvdb: 424536),
    );

    expect((await harness.matcher.match(bare)).items, isEmpty);
    expect((await harness.matcher.match(enriched)).items.single, same(romajiCopy));
    expect(harness.aggregation.calls, hasLength(2));
    expect(harness.aggregation.calls.last.titles.first, '葬送のフリーレン');
  });

  test('drops the year from a sequel title even when Fribb mapped no season', () async {
    // RC3 entries carry no season, but a strippable suffix says sequel just as
    // reliably, and the year window around it would exclude the parent show.
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.aggregation.responses.add(libraryLookupResult(const []));
    const item = CatalogItem(
      source: CatalogSourceId.anilist,
      kind: MediaKind.show,
      title: 'Some Show 2nd Season',
      year: 2026,
      ids: CatalogItemIds(anilist: 5, tvdb: 1),
    );

    await harness.matcher.match(item);

    expect(harness.aggregation.calls.single.year, isNull);
  });

  test('an id-poor negative does not suppress the detail-enriched retry', () async {
    // #1715: a Plex Discover row item carries only its rating key, and the
    // exact-guid lookup can miss even for owned titles (Discover dupes).
    // The detail body brings the external ids moments later; that richer
    // lookup must reach the servers instead of the bare form's cached
    // negative.
    final harness = _Harness();
    addTearDown(harness.dispose);
    final hit = testMediaItem(id: 'server-movie', kind: MediaKind.movie);
    harness.aggregation.responses.addAll([
      libraryLookupResult(const []),
      libraryLookupResult([hit]),
    ]);
    const bare = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Night on the Galactic Railroad',
      ids: CatalogItemIds(slug: '5d776b59ad5437001f79c6f8'),
    );
    const enriched = CatalogItem(
      source: CatalogSourceId.trakt,
      kind: MediaKind.movie,
      title: 'Night on the Galactic Railroad',
      ids: CatalogItemIds(slug: '5d776b59ad5437001f79c6f8', imdb: 'tt0089445', tmdb: 34523),
    );

    expect(bare.entryIdentityKey, enriched.entryIdentityKey);
    expect((await harness.matcher.match(bare)).items, isEmpty);
    expect((await harness.matcher.match(enriched)).items.single, same(hit));
    expect(harness.aggregation.calls, hasLength(2));
    expect(harness.aggregation.calls.last.ids.imdb, 'tt0089445');

    // Both forms stay memoized independently.
    expect((await harness.matcher.match(enriched)).items.single, same(hit));
    expect(harness.aggregation.calls, hasLength(2));
  });
}
