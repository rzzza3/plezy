import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/connection/connection.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/exceptions/media_server_exceptions.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_filter.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/silo_api_cache.dart';
import 'package:plezy/services/silo_client.dart';
import 'package:plezy/silo/silo_catalog.dart';

import 'fake_silo.dart';

final _connection = SiloConnection(
  origin: 'https://silo.ruleone.xyz',
  serverId: 'server-1',
  serverName: 'Silo',
  username: 'alice',
  createdAt: DateTime.fromMillisecondsSinceEpoch(1_000_000),
);

Map<String, Object?> _card(String id, {String type = 'movie'}) => {'content_id': id, 'type': type, 'title': 'T-$id'};

http.Response _page(List<String> ids, {String? next, int total = 250}) => jsonResponse({
  'items': [for (final id in ids) _card(id)],
  'page': {'has_more': next != null, 'next_cursor': ?next},
  'total': total,
  'total_exact': true,
  'window_cursor': 'w',
}, 200);

List<String> _ids(int from, int count) => [for (var i = from; i < from + count; i++) 'm$i'];

Future<(SiloClient, FakeSilo)> _client(FakeHandler handler) async {
  final (session, _) = await signedInSession();
  final fake = FakeSilo(handler);
  return (SiloClient(connection: _connection, profileId: 'p-1', http: siloHttpFor(fake, session)), fake);
}

void main() {
  group('library browse', () {
    test('no filter reads GET /catalog with the TV Browse query (CatalogV2Api.kt:49-65)', () async {
      final (client, fake) = await _client((_) => _page(_ids(0, 3)));

      final page = await client.fetchLibraryPagedContent(
        '5',
        query: const LibraryQuery(limit: 50),
        libraryKind: MediaKind.movie,
      );

      final request = fake.requests.single;
      expect(request.method, 'GET');
      expect(request.url.path, '/api/v2/catalog');
      expect(request.url.queryParameters, {
        'source': 'query',
        'library_id': '5',
        'type': 'movie',
        'skip_total': 'false',
        'limit': '100',
        'sort': 'title',
      });
      expect(page.items.map((i) => i.id), ['m0', 'm1', 'm2']);
      expect(page.items.first.libraryId, '5');
    });

    test('a genre filter switches to POST /catalog/query (CatalogApi.kt:25-41, CatalogV2Api.kt:35)', () async {
      final (client, fake) = await _client((_) => _page(_ids(0, 2)));

      await client.fetchLibraryPagedContent(
        '5',
        query: const LibraryQuery(
          limit: 50,
          sort: LibrarySort(field: 'added_at'),
          filters: [
            LibraryFilter(field: MediaFilterField.genre, values: ['Drama']),
          ],
        ),
        libraryKind: MediaKind.show,
      );

      final request = fake.requests.single;
      expect(request.method, 'POST');
      expect(request.url.path, '/api/v2/catalog/query');
      expect(request.url.query, isEmpty);
      expect(jsonDecode(request.body), {
        'source': 'query',
        'library_id': '5',
        'type': 'series',
        'match': 'all',
        'groups': [
          {
            'match': 'any',
            'rules': [
              {'field': 'genre', 'op': 'contains', 'value': 'Drama'},
            ],
          },
        ],
        'sort': 'added_at',
        'order': 'desc',
        'skip_total': false,
        'limit': 100,
      });
    });

    test('a second page sends the same query plus cursor (CatalogV2Api.kt:36-38)', () async {
      final (client, fake) = await _client(
        (r) => r.url.queryParameters['cursor'] == null ? _page(_ids(0, 100), next: 'c1') : _page(_ids(100, 100)),
      );

      final first = await client.fetchLibraryPagedContent('5', query: const LibraryQuery(limit: 100));
      final second = await client.fetchLibraryPagedContent('5', query: const LibraryQuery(offset: 100, limit: 100));

      expect(fake.requests, hasLength(2));
      expect(fake.requests[1].url.queryParameters, {...fake.requests[0].url.queryParameters, 'cursor': 'c1'});
      expect(first.items.last.id, 'm99');
      expect(second.items.map((i) => i.id), _ids(100, 100));
      expect(second.offset, 100);
    });

    test('a POST second page sends the same body plus cursor', () async {
      final (client, fake) = await _client(
        (r) => (jsonDecode(r.body) as Map)['cursor'] == null ? _page(_ids(0, 100), next: 'c1') : _page(_ids(100, 5)),
      );
      const genre = [
        LibraryFilter(field: MediaFilterField.genre, values: ['Drama']),
      ];

      await client.fetchLibraryPagedContent('5', query: const LibraryQuery(limit: 100, filters: genre));
      await client.fetchLibraryPagedContent('5', query: const LibraryQuery(offset: 100, limit: 100, filters: genre));

      expect(jsonDecode(fake.requests[1].body), {...jsonDecode(fake.requests[0].body) as Map, 'cursor': 'c1'});
    });

    test('a request above 100 reads 100-item pages (CatalogV2Api.kt:34)', () async {
      final (client, fake) = await _client((r) {
        final cursor = r.url.queryParameters['cursor'];
        final start = cursor == null ? 0 : int.parse(cursor);
        return _page(_ids(start, 100), next: '${start + 100}');
      });

      final page = await client.fetchLibraryPagedContent('5', query: const LibraryQuery(limit: 250));

      expect(fake.requests.map((r) => r.url.queryParameters['cursor']), [null, '100', '200']);
      expect(fake.requests.map((r) => r.url.queryParameters['limit']).toSet(), {'100'});
      expect(page.items, hasLength(250));
      expect(page.items.last.id, 'm249');
    });

    test('a repeated next_cursor restarts from page one (CatalogV2Api.kt:208-213)', () async {
      var repeated = false;
      final (client, fake) = await _client((r) {
        final cursor = r.url.queryParameters['cursor'];
        if (cursor == null) return _page(_ids(0, 100), next: 'c1');
        if (!repeated) {
          repeated = true;
          return _page(_ids(100, 100), next: 'c1');
        }
        return _page(_ids(100, 100));
      });

      final page = await client.fetchLibraryPagedContent('5', query: const LibraryQuery(limit: 200));

      expect(fake.requests.map((r) => r.url.queryParameters['cursor']), [null, 'c1', null, 'c1']);
      expect(page.items.map((i) => i.id), _ids(0, 200), reason: 'no duplicates after the restart');
    });

    test('an invalid_cursor problem restarts from page one (CatalogV2Api.kt:216-217)', () async {
      var refused = false;
      final (client, fake) = await _client((r) {
        final cursor = r.url.queryParameters['cursor'];
        if (cursor == null) return _page(_ids(0, 100), next: 'c1');
        if (!refused) {
          refused = true;
          return jsonResponse(
            {'type': 'https://silo.dev/problems/invalid_cursor', 'title': 'x', 'status': 400},
            400,
            headers: {'content-type': 'application/problem+json'},
          );
        }
        return _page(_ids(100, 100));
      });

      await client.fetchLibraryPagedContent('5', query: const LibraryQuery(limit: 100));
      final second = await client.fetchLibraryPagedContent('5', query: const LibraryQuery(offset: 100, limit: 100));

      expect(fake.requests.map((r) => r.url.queryParameters['cursor']), [null, 'c1', null, 'c1']);
      expect(second.items.first.id, 'm100');
    });

    test('a changed query starts again without a cursor', () async {
      final (client, fake) = await _client((_) => _page(_ids(0, 100), next: 'c1'));

      await client.fetchLibraryPagedContent('5', query: const LibraryQuery(limit: 100));
      await client.fetchLibraryPagedContent('5', query: const LibraryQuery(limit: 100, nameStartsWith: 'B'));

      expect(fake.requests[1].url.queryParameters['cursor'], isNull);
      expect(fake.requests[1].url.queryParameters['name_prefix'], 'B');
    });
  });

  group('home', () {
    Future<(SiloClient, FakeSilo)> home() =>
        _client((r) => http.Response(File('test/silo/fixtures/home_sections.json').readAsStringSync(), 200));

    test('hubs keep server order and leave progress rows to Continue Watching', () async {
      final (client, fake) = await _client((r) {
        if (r.url.path == '/api/v2/home/sections') {
          return http.Response(File('test/silo/fixtures/home_sections.json').readAsStringSync(), 200);
        }
        return jsonResponse({
          'id': 'sec-watch',
          'section_type': 'watchlist',
          'title': 'Watchlist',
          'items': [_card('movie-20')],
        }, 200);
      });

      final hubs = await client.fetchGlobalHubs(includePlaybackHubs: false);
      final continueWatching = await client.fetchContinueWatching();

      expect(hubs.map((h) => h.identifier), [
        'recently_added',
        'recently_released',
        'trending_on_server',
        'recommended_for_you',
        'taste_match',
        'favorites',
        'watchlist',
        'collection',
        'mystery_recipe_v9',
      ]);
      expect(continueWatching.map((i) => i.id), ['ep-1', 'movie-1']);
      expect(fake.to('/api/v2/home/sections'), hasLength(1), reason: 'one home read serves both');
      expect(fake.to('/api/v2/home/sections/sec-watch/items'), hasLength(1));
      expect(fake.to('/api/v2/home/sections/sec-custom/items'), isEmpty, reason: 'total_count 0 is not hydrated');
    });

    test('playback hubs are included when asked', () async {
      final (client, _) = await home();

      final hubs = await client.fetchGlobalHubs(limit: 1);

      expect(hubs.first.identifier, 'continue_watching');
      expect(hubs.first.isContinueWatchingHub, isTrue);
      expect(hubs.first.items, hasLength(1));
    });

    test('hydration reads at most four sections at once (HomeSectionHydrator.kt:22-55)', () async {
      var inFlight = 0;
      var peak = 0;
      final (client, fake) = await _client((r) async {
        if (r.url.path == '/api/v2/home/sections') {
          return jsonResponse({
            'sections': [
              for (var i = 0; i < 7; i++)
                {'id': 's$i', 'section_type': 'recently_added', 'title': 'S$i', 'total_count': 5, 'items': []},
            ],
          }, 200);
        }
        inFlight++;
        peak = peak < inFlight ? inFlight : peak;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inFlight--;
        final id = r.url.pathSegments[4];
        if (id == 's3') return jsonResponse({}, 500);
        return jsonResponse({
          'id': id,
          'section_type': 'recently_added',
          'title': id.toUpperCase(),
          'items': [_card('m-$id')],
        }, 200);
      });

      final hubs = await client.fetchGlobalHubs();

      expect(peak, 4);
      expect(fake.requests, hasLength(8));
      expect(hubs.map((h) => h.title), [
        'S0',
        'S1',
        'S2',
        'S4',
        'S5',
        'S6',
      ], reason: 'the hydrated section replaces the row and a failed read drops it (HomeSectionHydrator.kt:56-69)');
    });

    test('a read that straddles a profile switch is dropped (CatalogRepository.kt:398-405)', () async {
      final (session, _) = await signedInSession();
      final gate = Completer<void>();
      final fake = FakeSilo((_) async {
        await gate.future;
        return http.Response(File('test/silo/fixtures/home_sections.json').readAsStringSync(), 200);
      });
      final client = SiloClient(connection: _connection, profileId: 'p-1', http: siloHttpFor(fake, session));

      final hubs = client.fetchGlobalHubs();
      await Future<void>.delayed(Duration.zero);
      await session.selectProfile('p-2', null);
      gate.complete();

      await expectLater(
        hubs,
        throwsA(isA<MediaServerHttpException>().having((e) => e.isCancellation, 'isCancellation', isTrue)),
      );
    });
  });

  group('libraries', () {
    test('hidden ids and ebook types are dropped (TvLibrariesViewModel.kt:73,104-106)', () async {
      final (client, fake) = await _client((r) {
        if (r.url.path == '/api/v2/settings/values/effective') {
          return jsonResponse({
            'items': [
              {'key': 'ui.disabled_library_ids', 'value': '[2, "3", 4.5]'},
            ],
            'revision': 1,
          }, 200);
        }
        return jsonResponse({
          'items': [
            {'id': '1', 'name': 'Movies', 'type': 'movies', 'sort_order': 0},
            {'id': '2', 'name': 'Hidden', 'type': 'movies', 'sort_order': 1},
            {'id': '3', 'name': 'Shows', 'type': 'series', 'sort_order': 2},
            {'id': '4', 'name': 'Books', 'type': 'ebooks', 'sort_order': 3},
          ],
        }, 200);
      });

      final libraries = await client.fetchLibraries();

      expect(libraries.map((l) => (l.id, l.kind)), [('1', MediaKind.movie), ('3', MediaKind.show)]);
      expect(fake.to('/api/v2/settings/values/effective').single.url.queryParameters, {
        'keys': 'ui.disabled_library_ids',
      });
    });

    test('hidden-library ids parse like HiddenLibrariesStore.kt:94-111', () {
      expect(parseSiloLibraryIds([1, 2.0, 0, -3, 2.5, '7']), {'1', '2'});
      expect(parseSiloLibraryIds('[9, 10]'), {'9', '10'});
      expect(parseSiloLibraryIds('not json'), isEmpty);
      expect(parseSiloLibraryIds(null), isEmpty);
    });
  });

  group('writes', () {
    test('watched is one POST that expects 204 (PersonalWrite.kt:17-21, PersonalDataApi.kt:43-45)', () async {
      final (client, fake) = await _client((_) => jsonResponse({}, 204));
      final item = _movie();

      await client.markWatched(item);
      await client.markUnwatched(item);

      expect(fake.requests.map((r) => '${r.method} ${r.url.path}'), [
        'POST /api/v2/watched/movie-1',
        'DELETE /api/v2/watched/movie-1',
      ]);
    });

    test('a refused write is not retried and throws', () async {
      final (client, fake) = await _client((_) => jsonResponse({}, 401));

      await expectLater(
        client.markWatched(_movie()),
        throwsA(isA<MediaServerHttpException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
      expect(fake.requests, hasLength(1));
    });

    test('ratings map 0-10 to 1-5 stars and clear on negative (PersonalWrite.kt:23-30)', () async {
      final (client, fake) = await _client((_) => jsonResponse({}, 204));
      final item = _movie();

      await client.rate(item, 8);
      await client.rate(item, 1);
      await client.rate(item, -1);

      expect(fake.requests.map((r) => '${r.method} ${r.body}'), ['PUT {"rating":4}', 'PUT {"rating":1}', 'DELETE ']);
    });

    test('favorite and watchlist use PUT and DELETE (MembershipV2Api.kt:41-54)', () async {
      final (client, fake) = await _client((_) => jsonResponse({}, 204));
      final item = _movie();

      await client.setFavorite(item, true);
      await client.setWatchlisted(item, false);

      expect(fake.requests.map((r) => '${r.method} ${r.url.path}'), [
        'PUT /api/v2/favorites/movie-1',
        'DELETE /api/v2/watchlist/movie-1',
      ]);
    });
  });

  group('detail', () {
    Map<String, Object?> season(String id, int n, {int count = 10, int watched = 0, int inProgress = 0}) => {
      'content_id': id,
      'season_number': n,
      'episode_count': count,
      'user_data': {'played': watched == count, 'watched_count': watched, 'in_progress_count': inProgress},
    };

    test('a show opens on the season and episode the Silo TV app picks (CatalogModels.kt:495-509)', () async {
      final (client, fake) = await _client((r) {
        return switch (r.url.path) {
          '/api/v2/catalog/items/show-1' => jsonResponse({
            'content_id': 'show-1',
            'type': 'series',
            'title': 'Show A',
            'cast': [],
            'crew': [],
            'versions': [],
            'subtitles': [],
          }, 200),
          '/api/v2/catalog/series/show-1/seasons' => jsonResponse({
            'items': [
              season('s0', 0, count: 2),
              season('s1', 1, watched: 10),
              season('s2', 2, watched: 4),
              season('s3', 3, inProgress: 1),
            ],
          }, 200),
          _ => jsonResponse({
            'items': [
              {
                'content_id': 'e1',
                'season_number': 3,
                'episode_number': 1,
                'user_data': {'played': true},
              },
              {
                'content_id': 'e2',
                'season_number': 3,
                'episode_number': 2,
                'user_data': {'is_in_progress': true},
              },
            ],
          }, 200),
        };
      });

      final result = await client.fetchItemWithOnDeck('show-1');
      final seasons = await client.fetchChildren('show-1');
      final episodes = await client.fetchChildren('s3');

      expect(result.item?.kind, MediaKind.show);
      expect(result.onDeckEpisode?.id, 'e2');
      expect(result.onDeckEpisode?.parentId, 's3');
      expect(fake.requests.last.url.path, '/api/v2/catalog/series/show-1/seasons/3/episodes');
      expect(seasons.map((s) => s.id), ['s1', 's2', 's3', 's0'], reason: 'specials last (CatalogModels.kt:483-493)');
      expect(episodes.map((e) => (e.id, e.grandparentId, e.parentIndex, e.index)), [
        ('e1', 'show-1', 3, 1),
        ('e2', 'show-1', 3, 2),
      ]);
    });

    test('an item read is kept in the Silo cache under the profile scope, for offline use', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      SiloApiCache.initialize(db);
      final (client, _) = await _client(
        (_) => jsonResponse({
          'content_id': 'episode-1',
          'type': 'episode',
          'title': 'Physics',
          'cast': [],
          'crew': [],
          'versions': [],
          'subtitles': [],
        }, 200),
      );

      final item = await client.fetchItem('episode-1');
      final cached = await SiloApiCache.instance.getMetadata(ServerId('silo:server-1/p-1'), 'episode-1');

      expect(client.cache, same(SiloApiCache.instance));
      expect(cached?.globalKey, item?.globalKey);
      expect(cached?.title, 'Physics');
      expect(await SiloApiCache.instance.getMetadata(ServerId('server-1'), 'episode-1'), isNull);
    });

    test('a missing item reads as null', () async {
      final (client, _) = await _client((_) => jsonResponse({}, 404));

      expect(await client.fetchItem('gone'), isNull);
    });

    test('search reads one 40-item page (TvSearchViewModel.kt:240-300)', () async {
      final (client, fake) = await _client(
        (_) => jsonResponse({
          'items': [_card('m1'), _card('b1', type: 'ebook')],
          'page': {'has_more': false},
          'total': 2,
          'total_exact': true,
          'window_cursor': 'w',
        }, 200),
      );

      final items = await client.searchItems('alpha');

      expect(fake.requests.single.url.queryParameters, {
        'source': 'query',
        'q': 'alpha',
        'skip_total': 'false',
        'limit': '40',
      });
      expect(items.map((i) => i.id), ['m1']);
    });

    test('people search runs only on a server that scopes it (SearchPeople.kt:23-36)', () async {
      final (client, fake) = await _client(
        (r) => r.url.path.endsWith('/capabilities')
            ? jsonResponse({'people_media_scope': false}, 200)
            : jsonResponse({'items': []}, 200),
      );

      expect(await client.searchPeople('alpha'), isEmpty);
      expect(fake.requests.map((r) => r.url.path), ['/api/v2/catalog/search/capabilities']);
    });

    test('people search asks the video scope, as the TV All filter does (TvSearchViewModel.kt:42-47)', () async {
      final (client, fake) = await _client(
        (r) => r.url.path.endsWith('/capabilities')
            ? jsonResponse({'people_media_scope': true}, 200)
            : jsonResponse({
                'items': [
                  {'id': '41', 'name': 'Alpha Person'},
                ],
              }, 200),
      );

      final people = await client.searchPeople(' alpha ');

      expect(people.map((p) => p.id), ['41']);
      expect(fake.to('/api/v2/catalog/people').single.url.queryParameters, {
        'q': 'alpha',
        'limit': '20',
        'media_scope': 'video',
      });
    });
  });

  test('the silo preset offers hubs, ratings and favorites and none of the features Silo has no wire for', () async {
    final (client, _) = await _client((_) => jsonResponse({}, 500));
    final caps = client.capabilities;

    expect(
      {
        'liveTv': caps.liveTv,
        'liveTvDvr': caps.liveTvDvr,
        'folderGrouping': caps.folderGrouping,
        'externalSubtitleSearch': caps.externalSubtitleSearch,
        'instantMix': caps.instantMix,
        'richMetadataEdit': caps.richMetadataEdit,
        'richHubs': caps.richHubs,
        'numericUserRating': caps.numericUserRating,
        'wholeStarRating': caps.wholeStarRating,
        'userFavorites': caps.userFavorites,
      },
      {
        'liveTv': false,
        'liveTvDvr': false,
        'folderGrouping': false,
        'externalSubtitleSearch': false,
        'instantMix': false,
        'richMetadataEdit': false,
        'richHubs': true,
        'numericUserRating': true,
        'wholeStarRating': true,
        'userFavorites': true,
      },
    );
  });

  group('home dismissal (HomeSectionsV2Api.kt:28-39, HomeViewModel.kt:412-446)', () {
    Map<String, Object?> home(String progressUpdatedAt) => {
      'sections': [
        {
          'id': 's-cw',
          'section_type': 'continue_watching',
          'title': 'Continue Watching',
          'total_count': 1,
          'items': [
            {'content_id': 'movie-1', 'type': 'movie', 'title': 'M', 'progress_updated_at': progressUpdatedAt},
          ],
        },
        {
          'id': 's-nu',
          'section_type': 'next_up',
          'title': 'Next Up',
          'total_count': 1,
          'items': [
            {
              'content_id': 'ep-2',
              'type': 'episode',
              'title': 'E',
              'series_id': 'show-1',
              'season_number': 1,
              'episode_number': 2,
            },
          ],
        },
      ],
    };

    Future<(SiloClient, FakeSilo, List<MediaItem>)> visibleHome() async {
      var anchor = '2026-10-14T10:00:00Z';
      final (client, fake) = await _client((r) {
        if (r.url.path == '/api/v2/home/sections') {
          final body = home(anchor);
          anchor = '2026-10-14T10:05:00Z';
          return jsonResponse(body, 200);
        }
        return http.Response('', 204);
      });
      return (client, fake, await client.fetchContinueWatching());
    }

    test('a continue watching card sends its progress_updated_at anchor', () async {
      final (client, fake, cards) = await visibleHome();

      await client.removeFromContinueWatching(cards.firstWhere((c) => c.id == 'movie-1'));

      final put = fake.requests.last;
      expect(put.method, 'PUT');
      expect(put.url.path, '/api/v2/home/dismissals/continue_watching/movie-1');
      expect(jsonDecode(put.body), {'progress_updated_at': '2026-10-14T10:00:00Z'});
    });

    test('a next up card sends its series_id anchor', () async {
      final (client, fake, cards) = await visibleHome();

      await client.removeFromContinueWatching(cards.firstWhere((c) => c.id == 'ep-2'));

      final put = fake.requests.last;
      expect(put.url.path, '/api/v2/home/dismissals/next_up/ep-2');
      expect(jsonDecode(put.body), {'series_id': 'show-1'});
    });

    test('a card whose anchor moved since the last home read is not dismissed', () async {
      final (client, fake, cards) = await visibleHome();
      final stale = cards.firstWhere((c) => c.id == 'movie-1');
      await client.markWatched(cards.firstWhere((c) => c.id == 'ep-2'));
      final reread = await client.fetchContinueWatching();
      expect(reread.firstWhere((c) => c.id == 'movie-1').lastViewedAt, isNot(stale.lastViewedAt));

      await expectLater(client.removeFromContinueWatching(stale), throwsA(isA<MediaServerHttpException>()));
      expect(fake.requests.where((r) => r.method == 'PUT'), isEmpty);
    });

    test('a card the home never showed is not dismissed', () async {
      final (client, fake, _) = await visibleHome();

      await expectLater(
        client.removeFromContinueWatching(MediaItem.silo(id: 'movie-9', kind: MediaKind.movie)),
        throwsA(isA<MediaServerHttpException>()),
      );
      expect(fake.requests.where((r) => r.method == 'PUT'), isEmpty);
    });
  });
}

MediaItem _movie() => MediaItem.silo(id: 'movie-1', kind: MediaKind.movie);
