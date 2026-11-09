import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/connection/connection.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/silo_client.dart';
import 'package:plezy/silo/silo_catalog.dart';
import 'package:plezy/silo/silo_models.dart';

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

http.Response _page(List<Map<String, Object?>> cards, {String? next, int? total}) => jsonResponse({
  'items': cards,
  'page': {'has_more': next != null, 'next_cursor': ?next},
  'total': total ?? cards.length,
  'total_exact': true,
  'window_cursor': 'w',
}, 200);

const _movie = MediaItem.silo(id: 'm1', kind: MediaKind.movie);

void main() {
  group('SiloClient.fetchPersonalList', () {
    test('reads the list as a catalog source in stored order, with no sort', () async {
      final (client, fake) = await _silo(
        (request) => request.url.queryParameters['cursor'] == null
            ? _page(
                [
                  {'content_id': 'm1', 'type': 'movie', 'title': 'Ponyo'},
                  {'content_id': 's1', 'type': 'series', 'title': 'The Traitors'},
                ],
                next: 'c2',
                total: 3,
              )
            : _page([
                {'content_id': 'm2', 'type': 'movie', 'title': 'The Meg'},
              ], total: 3),
      );

      final list = await client.fetchPersonalList(SiloPersonalList.favorites);

      expect(
        [for (final item in list.items) (item.id, item.kind)],
        [('m1', MediaKind.movie), ('s1', MediaKind.show), ('m2', MediaKind.movie)],
      );
      expect(list.total, 3);
      expect(fake.requests, hasLength(2));
      final first = fake.requests.first;
      expect(first.method, 'GET');
      expect(first.url.path, '/api/v2/catalog');
      expect(first.url.queryParameters, containsPair('source', 'favorites'));
      expect(first.url.queryParameters.containsKey('sort'), isFalse);
      expect(fake.requests.last.url.queryParameters, containsPair('cursor', 'c2'));
    });

    test('stops at maxItems and keeps the server total', () async {
      final (client, fake) = await _silo(
        (_) => _page(
          [
            for (var i = 0; i < 100; i++) {'content_id': 'm$i', 'type': 'movie', 'title': 'Movie $i'},
          ],
          next: 'more',
          total: 450,
        ),
      );

      final list = await client.fetchPersonalList(SiloPersonalList.watchlist, maxItems: 100);

      expect(list.items, hasLength(100));
      expect(list.total, 450);
      expect(fake.requests, hasLength(1));
      expect(fake.requests.single.url.queryParameters, containsPair('source', 'watchlist'));
    });

    test('a repeated cursor is a broken chain', () async {
      final (client, _) = await _silo(
        (_) => _page([
          {'content_id': 'm1', 'type': 'movie', 'title': 'Loop'},
        ], next: 'same'),
      );
      await expectLater(
        client.fetchPersonalList(SiloPersonalList.watchlist),
        throwsA(isA<SiloInvalidCursorException>()),
      );
    });
  });

  group('SiloClient.fetchMembership', () {
    test('reads both lists, and a 404 means not on the list', () async {
      final (client, fake) = await _silo(
        (request) => request.url.path.startsWith('/api/v2/favorites/')
            ? jsonResponse({'item_id': 'm1', 'added_at': '2026-10-01T00:00:00Z'}, 200)
            : jsonResponse({'code': 'not_found'}, 404),
      );

      final membership = await client.fetchMembership(_movie);

      expect(membership.favorite, isTrue);
      expect(membership.watchlisted, isFalse);
      expect(
        {for (final r in fake.requests) '${r.method} ${r.url.path}'},
        {'GET /api/v2/favorites/m1', 'GET /api/v2/watchlist/m1'},
      );
    });

    test('an answer for another item is refused', () async {
      final (client, _) = await _silo((_) => jsonResponse({'item_id': 'other'}, 200));
      await expectLater(client.fetchMembership(_movie), throwsA(isA<SiloDecodeException>()));
    });

    test('toggles write PUT to add and DELETE to remove', () async {
      final (client, fake) = await _silo((_) => http.Response('', 204));
      await client.setWatchlisted(_movie, true);
      await client.setFavorite(_movie, false);
      expect(
        [for (final r in fake.requests) '${r.method} ${r.url.path}'],
        ['PUT /api/v2/watchlist/m1', 'DELETE /api/v2/favorites/m1'],
      );
    });
  });
}
