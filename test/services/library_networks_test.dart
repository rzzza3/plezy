import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/library_networks.dart';
import 'package:plezy/services/silo_client.dart';
import 'package:plezy/services/tmdb/tmdb_client.dart';
import 'package:plezy/services/tmdb/tmdb_models.dart';
import 'package:plezy/services/tmdb/tmdb_networks.dart';
import 'package:plezy/silo/silo_catalog.dart';

import '../silo/fake_silo.dart';

final _connection = SiloConnection(
  origin: 'https://silo.ruleone.xyz',
  serverId: 'server-1',
  serverName: 'Silo',
  username: 'alice',
  createdAt: DateTime.fromMillisecondsSinceEpoch(1_000_000),
);

Future<(SiloClient, FakeSilo)> _silo(FakeHandler handler) async {
  final (session, _) = await signedInSession();
  final fake = FakeSilo(handler);
  return (SiloClient(connection: _connection, profileId: 'p-1', http: siloHttpFor(fake, session)), fake);
}

http.Response _catalogPage(List<Map<String, Object?>> cards, {String? next}) => jsonResponse({
  'items': cards,
  'page': {'has_more': next != null, 'next_cursor': ?next},
  'total': cards.length,
  'total_exact': true,
  'window_cursor': 'w',
}, 200);

MediaItem _item(String id, {MediaKind kind = MediaKind.show, String? title, int? year, int? addedAt}) => MediaItem.silo(
  id: id,
  kind: kind,
  title: title ?? id,
  year: year,
  addedAt: addedAt,
  serverId: 'server-1',
  serverName: 'Silo',
);

TmdbMedia _result(int id, String title, {int? year, double popularity = 0, TmdbMediaType type = TmdbMediaType.tv}) =>
    TmdbMedia(
      id: id,
      type: type,
      title: title,
      releaseDate: year == null ? null : DateTime(year),
      popularity: popularity,
    );

http.Response _tmdbJson(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

Map<String, Object?> _discoverBody(List<Map<String, Object?>> results, {int page = 1, int totalPages = 1}) => {
  'page': page,
  'total_pages': totalPages,
  'results': results,
};

void main() {
  group('SiloClient.fetchTitles', () {
    test('pages through one year range Title A-Z and reads each tmdb_id', () async {
      final (client, fake) = await _silo(
        (request) => jsonDecode(request.body)['cursor'] == null
            ? _catalogPage([
                {'content_id': 's1', 'type': 'series', 'title': 'Stranger Things', 'tmdb_id': 66732},
                {'content_id': 's2', 'type': 'series', 'title': 'Dark', 'tmdb_id': '70523'},
              ], next: 'c2')
            : _catalogPage([
                {'content_id': 's3', 'type': 'series', 'title': 'Unmatched', 'tmdb_id': 'n/a'},
              ]),
      );

      final titles = await client.fetchTitles(MediaKind.show, years: (2010, 2019));

      expect([for (final title in titles) (title.item.id, title.tmdbId)], [('s1', 66732), ('s2', 70523), ('s3', null)]);
      expect(fake.requests, hasLength(2));
      expect(fake.requests.first.method, 'POST');
      expect(fake.requests.first.url.path, '/api/v2/catalog/query');
      final body = jsonDecode(fake.requests.first.body) as Map<String, dynamic>;
      expect(body, containsPair('type', 'series'));
      expect(body, containsPair('sort', 'title'));
      expect(body, containsPair('limit', 100));
      expect(body['groups'], [
        {
          'match': 'all',
          'rules': [
            {
              'field': 'year',
              'op': 'between',
              'value': [2010, 2019],
            },
          ],
        },
      ]);
      expect(jsonDecode(fake.requests.last.body), containsPair('cursor', 'c2'));
    });

    test('a repeated cursor is a broken chain', () async {
      final (client, _) = await _silo(
        (_) => _catalogPage([
          {'content_id': 'm1', 'type': 'movie', 'title': 'Loop'},
        ], next: 'same'),
      );
      await expectLater(
        client.fetchTitles(MediaKind.movie, years: (2000, 2000)),
        throwsA(isA<SiloInvalidCursorException>()),
      );
    });
  });

  group('LibraryNetworks.readLibrary', () {
    test('the year ranges cover every year exactly once', () {
      final ranges = LibraryNetworks.libraryYearRanges(2026);
      expect(ranges.first.$1, lessThanOrEqualTo(0));
      expect(ranges.last.$2, greaterThan(9999));
      for (var i = 1; i < ranges.length; i++) {
        expect(ranges[i].$1, ranges[i - 1].$2 + 1, reason: 'gap or overlap before ${ranges[i]}');
      }
      expect(ranges, contains((2027, 2027)));
    });

    test('reads every year range of both kinds and indexes the results', () async {
      final (client, fake) = await _silo((request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final years = body['groups'][0]['rules'][0]['value'] as List;
        if (body['type'] == 'movie' && years.first == 2010) {
          return _catalogPage([
            {'content_id': 'm1', 'type': 'movie', 'title': 'Inception', 'tmdb_id': 27205, 'year': 2010},
          ]);
        }
        if (body['type'] == 'series' && years.first == 2016) {
          return _catalogPage([
            {'content_id': 's1', 'type': 'series', 'title': 'Stranger Things', 'tmdb_id': 66732, 'year': 2016},
          ]);
        }
        return _catalogPage([]);
      });

      final library = await LibraryNetworks.readLibrary([client]);

      final ranges = LibraryNetworks.libraryYearRanges(DateTime.now().year);
      expect(fake.to('/api/v2/catalog/query'), hasLength(ranges.length * 2));
      expect(library.movies.lookup(_result(27205, 'Inception', type: TmdbMediaType.movie))?.id, 'm1');
      expect(library.shows.lookup(_result(66732, 'Stranger Things'))?.id, 's1');
      expect(library.movies.lookup(_result(66732, 'Stranger Things')), isNull);
    });

    test('a failed range fails the whole read', () async {
      final (client, _) = await _silo((request) {
        final years = jsonDecode(request.body)['groups'][0]['rules'][0]['value'] as List;
        return years.first == 1990 ? jsonResponse({'error': 'boom'}, 500) : _catalogPage([]);
      });
      await expectLater(LibraryNetworks.readLibrary([client]), throwsA(anything));
    });
  });

  group('LibraryTitleIndex', () {
    test('matches by TMDB id, else by letters-and-digits title and year', () {
      final byId = _item('a', title: 'Something Else', year: 2000);
      final byTitle = _item('b', title: "Grey's Anatomy", year: 2005);
      final index = LibraryTitleIndex([(item: byId, tmdbId: 42), (item: byTitle, tmdbId: null)]);

      expect(index.lookup(_result(42, 'Renamed', year: 1990)), byId);
      expect(index.lookup(_result(7, 'Greys Anatomy', year: 2005)), byTitle);
      expect(index.lookup(_result(7, 'Greys Anatomy', year: 2006)), isNull);
      expect(index.lookup(_result(7, 'Greys Anatomy')), isNull);
    });
  });

  group('LibraryNetworks.match', () {
    test('merges series and films most popular first, keeping library titles only', () async {
      final requests = <Uri>[];
      final tmdb = TmdbClient(
        token: 'token',
        httpClient: MockClient((request) async {
          requests.add(request.url);
          return _tmdbJson(switch (request.url.pathSegments.last) {
            'tv' => _discoverBody([
              {'id': 1, 'name': 'Show One', 'popularity': 90},
              {'id': 404, 'name': 'Not Owned', 'popularity': 80},
              {'id': 2, 'name': 'Show Two', 'popularity': 10},
            ]),
            _ => _discoverBody([
              {'id': 11, 'title': 'Film', 'popularity': 50},
            ]),
          });
        }),
      );
      final shows = LibraryTitleIndex([
        (item: _item('s1', addedAt: 100), tmdbId: 1),
        (item: _item('s2', addedAt: 300), tmdbId: 2),
      ]);
      final movies = LibraryTitleIndex([(item: _item('m11', kind: MediaKind.movie, addedAt: 200), tmdbId: 11)]);

      final items = await LibraryNetworks(tmdb).match(
        const TmdbNetworkBrand(213, 'Netflix', watchProviders: '8'),
        movies: movies,
        shows: shows,
      );

      expect([for (final item in items) item.id], ['s1', 'm11', 's2']);
      expect([for (final item in LibraryNetworks.newestFirst(items)) item.id], ['s2', 'm11', 's1']);
      final tv = requests.singleWhere((url) => url.path == '/3/discover/tv');
      expect(tv.queryParameters, containsPair('with_networks', '213'));
      expect(tv.queryParameters, containsPair('sort_by', 'popularity.desc'));
      final movie = requests.singleWhere((url) => url.path == '/3/discover/movie');
      expect(movie.queryParameters, containsPair('with_watch_providers', '8'));
      expect(movie.queryParameters, containsPair('watch_region', 'US'));
      expect(movie.queryParameters, containsPair('with_watch_monetization_types', 'flatrate'));
    });

    test('a channel without providers reads series only, at most ten pages', () async {
      final pages = <String>[];
      final tmdb = TmdbClient(
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/3/discover/tv');
          final page = int.parse(request.url.queryParameters['page']!);
          pages.add('$page');
          return _tmdbJson(
            _discoverBody(
              [
                {'id': page, 'name': 'Show $page', 'popularity': 100 - page},
                // The same title on two pages counts once.
                {'id': 1, 'name': 'Show 1', 'popularity': 100},
              ],
              page: page,
              totalPages: 40,
            ),
          );
        }),
      );
      final shows = LibraryTitleIndex([for (var id = 1; id <= 12; id++) (item: _item('s$id'), tmdbId: id)]);

      final items = await LibraryNetworks(
        tmdb,
      ).match(const TmdbNetworkBrand(2, 'ABC'), movies: LibraryTitleIndex(const []), shows: shows);

      expect(pages..sort((a, b) => int.parse(a).compareTo(int.parse(b))), [
        for (var page = 1; page <= 10; page++) '$page',
      ]);
      expect([for (final item in items) item.id], [for (var id = 1; id <= 10; id++) 's$id']);
    });
  });

  group('LibraryNetworks.trending', () {
    tearDown(LibraryNetworks.resetTrending);

    test('keeps the titles trending this week, in trending order, read once for every network', () async {
      final pages = <int>[];
      final tmdb = TmdbClient(
        token: 'token',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/3/trending/all/week');
          final page = int.parse(request.url.queryParameters['page']!);
          pages.add(page);
          return _tmdbJson(
            _discoverBody(
              switch (page) {
                1 => [
                  {'id': 1, 'media_type': 'movie', 'title': 'Below', 'release_date': '2026-03-01'},
                  {'id': 2, 'media_type': 'person', 'name': 'Crown'},
                  // A series sharing a movie's title and year matches the series only.
                  {'id': 3, 'media_type': 'tv', 'name': 'The Crown', 'first_air_date': '2016-11-04'},
                ],
                2 => [
                  {'id': 4, 'media_type': 'tv', 'name': 'Bojack Horseman', 'first_air_date': '2014-08-22'},
                  {'id': 5, 'media_type': 'tv', 'name': 'Not In Library', 'first_air_date': '2020-01-01'},
                  // Two years off: a different title.
                  {'id': 6, 'media_type': 'movie', 'title': 'Animals', 'release_date': '2024-01-01'},
                  // A year off: TMDB and the server often disagree on a series' first year.
                  {'id': 7, 'media_type': 'tv', 'name': 'Dark', 'first_air_date': '2017-12-01'},
                ],
                _ => const [],
              },
              page: page,
              totalPages: 500,
            ),
          );
        }),
      );
      final items = [
        _item('crown-movie', kind: MediaKind.movie, title: 'The Crown', year: 2016),
        _item('animals', kind: MediaKind.movie, title: 'Animals', year: 2026),
        _item('bojack', title: 'BoJack Horseman', year: 2014),
        _item('below', kind: MediaKind.movie, title: 'Below', year: 2026),
        _item('crown', title: 'The Crown', year: 2016),
        _item('dark', title: 'Dark', year: 2018),
      ];

      final trending = await LibraryNetworks(tmdb).trending(items);
      expect([for (final item in trending) item.id], ['below', 'crown', 'bojack', 'dark']);
      expect(pages..sort(), [for (var page = 1; page <= LibraryNetworks.trendingPages; page++) page]);

      // Another network's page reuses the week's list.
      expect(await LibraryNetworks(tmdb).trending([items[2]]), [items[2]]);
      expect(pages, hasLength(LibraryNetworks.trendingPages));
    });

    test('a failed read is asked again next time', () async {
      var fail = true;
      final tmdb = TmdbClient(
        token: 'token',
        httpClient: MockClient((request) async {
          if (fail) return http.Response('{}', 500);
          return _tmdbJson(
            _discoverBody([
              {'id': 1, 'media_type': 'tv', 'name': 'Dark', 'first_air_date': '2017-12-01'},
            ]),
          );
        }),
      );
      final items = [_item('dark', title: 'Dark', year: 2017)];

      await expectLater(LibraryNetworks(tmdb).trending(items), throwsA(isA<TmdbApiException>()));
      fail = false;
      expect(await LibraryNetworks(tmdb).trending(items), items);
    });
  });
}
