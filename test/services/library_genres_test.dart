import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/services/library_genres.dart';
import 'package:plezy/services/silo_client.dart';
import 'package:plezy/services/tmdb/tmdb_client.dart';
import 'package:plezy/services/tmdb/tmdb_genres.dart';

import '../silo/fake_silo.dart';

LibraryGenre _genre(String id) => TmdbGenres.all.firstWhere((genre) => genre.id == id);

/// A Silo whose Horror films are m1 (TMDB 1) and m2, and whose Horror series
/// is s1; each query answers whatever its sort, as the server sorts.
Future<(SiloClient, FakeSilo)> _silo() async {
  final (session, _) = await signedInSession();
  final fake = FakeSilo((request) {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final series = body['type'] == 'series';
    Map<String, Object?> card(String id, int tmdbId, double rating) => {
      'content_id': id,
      'type': series ? 'series' : 'movie',
      'title': 'Title $id',
      'tmdb_id': tmdbId,
      'year': 2020,
      'genres': ['Horror'],
      'rating_imdb': rating,
    };
    return jsonResponse({
      'items': series ? [card('s1', 10, 7)] : [card('m1', 1, 6), card('m2', 2, 9)],
      'page': {'has_more': false},
      'total': series ? 1 : 2,
      'total_exact': true,
      'window_cursor': 'w',
    }, 200);
  });
  final client = SiloClient(
    connection: SiloConnection(
      origin: 'https://silo.ruleone.xyz',
      serverId: 'server-1',
      serverName: 'Silo',
      username: 'alice',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1_000_000),
    ),
    profileId: 'p-1',
    http: siloHttpFor(fake, session),
  );
  return (client, fake);
}

void main() {
  test('every default is in the catalogue and every id is distinct', () {
    final ids = [for (final genre in TmdbGenres.all) genre.id];
    expect(ids.toSet(), hasLength(ids.length));
    expect(ids, containsAll(TmdbGenres.defaultIds));
  });

  group('LibraryGenres.match', () {
    test('asks Silo per genre for the newest and the highest rated, never the whole library', () async {
      final (client, fake) = await _silo();

      await LibraryGenres(TmdbClient(token: '', apiKey: '')).match(_genre('science-fiction'), [client]);

      expect(fake.requests, hasLength(4));
      for (final request in fake.requests) {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v2/catalog/query');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['limit'], LibraryGenres.titlesPerQuery);
        expect(body['order'], 'desc');
        expect(body['groups'], [
          {
            'match': 'any',
            'rules': [
              for (final name in _genre('science-fiction').names) {'field': 'genre', 'op': 'contains', 'value': name},
            ],
          },
        ]);
      }
      expect(
        {for (final request in fake.requests) (jsonDecode(request.body) as Map)['sort']},
        {'added_at', 'rating_imdb'},
      );
    });

    test('most popular on TMDB first, then by rating', () async {
      final (client, _) = await _silo();
      final requests = <Uri>[];
      final tmdb = TmdbClient(
        token: 'token',
        httpClient: MockClient((request) async {
          requests.add(request.url);
          // Only m1 is popular on TMDB; Horror has no TV genre.
          return http.Response(
            jsonEncode({
              'page': 1,
              'total_pages': 1,
              'results': [
                {'id': 1, 'title': 'Title m1', 'popularity': 50},
                {'id': 404, 'title': 'Not Owned', 'popularity': 90},
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final items = await LibraryGenres(tmdb).match(_genre('horror'), [client]);

      expect([for (final item in items) item.id], ['m1', 'm2', 's1']);
      expect(requests.single.path, '/3/discover/movie');
      expect(requests.single.queryParameters, containsPair('with_genres', '27'));
    });

    test('without TMDB credentials, ranks by rating alone', () async {
      final (client, _) = await _silo();
      final items = await LibraryGenres(TmdbClient(token: '', apiKey: '')).match(_genre('horror'), [client]);
      expect([for (final item in items) item.id], ['m2', 's1', 'm1']);
    });
  });
}
