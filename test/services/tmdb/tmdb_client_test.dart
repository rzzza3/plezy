import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/tmdb/tmdb_client.dart';
import 'package:plezy/services/tmdb/tmdb_models.dart';

TmdbClient _client(Future<http.Response> Function(http.Request) handler, {String? language}) =>
    TmdbClient(token: 'token', language: language, httpClient: MockClient(handler));

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  test('unconfigured client throws without sending', () async {
    var sent = false;
    final client = TmdbClient(
      token: '',
      httpClient: MockClient((_) async {
        sent = true;
        return _json({});
      }),
    );
    expect(client.isConfigured, isFalse);
    await expectLater(client.trending(), throwsA(isA<TmdbNotConfiguredException>()));
    expect(sent, isFalse);
  });

  test('getList reads a v4 list with mixed items and pagination', () async {
    late http.Request seen;
    final client = _client((req) async {
      seen = req;
      return _json({
        'id': 8136,
        'name': 'Favourites',
        'description': 'Mine',
        'page': 1,
        'total_pages': 2,
        'total_results': 30,
        'results': [
          {
            'id': 603,
            'media_type': 'movie',
            'title': 'The Matrix',
            'release_date': '1999-03-30',
            'poster_path': '/m.jpg',
          },
          {'id': 1396, 'media_type': 'tv', 'name': 'Breaking Bad', 'first_air_date': '2008-01-20'},
          {'id': 1, 'media_type': 'movie'},
        ],
      });
    }, language: 'de-DE');

    final list = await client.getList(8136, sortBy: 'vote_average.desc');

    expect(seen.url.path, '/4/list/8136');
    expect(seen.url.queryParameters, {'language': 'de-DE', 'page': '1', 'sort_by': 'vote_average.desc'});
    expect(seen.headers['Authorization'], 'Bearer token');
    expect(list.name, 'Favourites');
    expect(list.items.hasMore, isTrue);
    expect(list.items.results.map((m) => (m.title, m.kind, m.year)), [
      ('The Matrix', MediaKind.movie, 1999),
      ('Breaking Bad', MediaKind.show, 2008),
    ]);
    expect(list.items.results.first.posterUrl('w342'), 'https://image.tmdb.org/t/p/w342/m.jpg');
  });

  test('popular falls back to the requested type when entries omit media_type', () async {
    final client = _client((req) async {
      expect(req.url.path, '/3/tv/popular');
      return _json({
        'page': 1,
        'total_pages': 1,
        'results': [
          {'id': 1396, 'name': 'Breaking Bad'},
        ],
      });
    });
    final page = await client.popular(TmdbMediaType.tv);
    expect(page.results.single.type, TmdbMediaType.tv);
    expect(page.hasMore, isFalse);
  });

  test('details exposes appended external ids', () async {
    final client = _client((req) async {
      expect(req.url.queryParameters['append_to_response'], 'external_ids');
      return _json({
        'id': 1396,
        'name': 'Breaking Bad',
        'genres': [
          {'id': 18, 'name': 'Drama'},
        ],
        'external_ids': {'imdb_id': 'tt0903747', 'tvdb_id': 81189},
      });
    });
    final show = await client.details(TmdbMediaType.tv, 1396);
    expect((show.imdbId, show.tvdbId), ('tt0903747', 81189));
    expect(show.genreIds, [18]);
  });

  test('network reads a name and logo', () async {
    late http.Request seen;
    final client = _client((req) async {
      seen = req;
      return _json({'id': 213, 'name': 'Netflix', 'logo_path': '/n.png', 'origin_country': ''});
    });

    final network = await client.network(213);

    expect(seen.url.path, '/3/network/213');
    expect(network.id, 213);
    expect(network.name, 'Netflix');
    expect(network.originCountry, isNull);
    expect(network.logoUrl(), 'https://image.tmdb.org/t/p/w300/n.png');
  });

  test('network without a name is malformed', () async {
    final client = _client((_) async => _json({'id': 213}));
    await expectLater(client.network(213), throwsA(isA<TmdbApiException>()));
  });

  test('error body surfaces as TmdbApiException', () async {
    final client = _client(
      (_) async => http.Response(
        jsonEncode({'status_code': 25, 'status_message': 'Rate limited'}),
        429,
        headers: {'retry-after': '3'},
      ),
    );
    await expectLater(
      client.trending(),
      throwsA(
        isA<TmdbApiException>()
            .having((e) => e.isRateLimited, 'isRateLimited', isTrue)
            .having((e) => e.tmdbCode, 'tmdbCode', 25)
            .having((e) => e.retryAfterSeconds, 'retryAfterSeconds', 3),
      ),
    );
  });

  test('a v3 key goes in the query and lists fall back to /3/list', () async {
    late http.Request seen;
    final client = TmdbClient(
      token: '',
      apiKey: 'key',
      httpClient: MockClient((req) async {
        seen = req;
        return _json({
          'id': 8136,
          'name': 'Favourites',
          'item_count': 1,
          'items': [
            {'id': 603, 'media_type': 'movie', 'title': 'The Matrix'},
          ],
        });
      }),
    );

    final list = await client.getList(8136, page: 2);

    expect(client.supportsV4, isFalse);
    expect(seen.url.path, '/3/list/8136');
    expect(seen.url.queryParameters, {'api_key': 'key'});
    expect(seen.headers.containsKey('Authorization'), isFalse);
    expect(list.items.results.single.title, 'The Matrix');
    expect((list.items.totalResults, list.items.hasMore), (1, false));
  });
}
