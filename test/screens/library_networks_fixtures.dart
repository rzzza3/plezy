import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/screens/library_home_screen.dart';
import 'package:plezy/screens/library_networks_section.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/silo_client.dart';
import 'package:plezy/services/tmdb/tmdb_client.dart';
import 'package:plezy/services/tmdb/tmdb_networks.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:provider/provider.dart';

import '../silo/fake_silo.dart';
import '../test_helpers/multi_server_fixtures.dart';

/// Fakes for the Library tab's Networks row: a TMDB that lists a few
/// networks' titles and a Silo library that holds them.

final _names = {for (final network in TmdbNetworks.all) network.id: network.name};

/// TMDB ids of each network's series and films, all of them in the library.
/// Prime Video and Paramount+ have too few to show.
const _seriesOn = {
  213: [2130, 2131, 2132, 2133, 2134, 2135, 2136],
  49: [490, 491, 492, 493, 494, 495],
  1024: [10240, 10241, 10242],
};
const _filmsFrom = {
  '8': [80, 81],
};

/// Answers `/3/network/{id}` with a logo-less network (so no image loads)
/// and `/3/discover/{tv,movie}` with the ids above plus one title the library
/// doesn't have. This week's trending: a Netflix film, an HBO series and a
/// Netflix series, by title and year. Discover answers once [discovered]
/// completes, when given.
TmdbClient networksTmdb({Future<void>? discovered}) => TmdbClient(
  token: 'token',
  httpClient: MockClient((req) async {
    final query = req.url.queryParameters;
    if (req.url.pathSegments case ['3', 'discover', _]) await discovered;
    final body = switch (req.url.pathSegments) {
      ['3', 'network', final id] => {'id': int.parse(id), 'name': _names[int.parse(id)]},
      ['3', 'discover', 'tv'] => _discover(_seriesOn[int.parse(query['with_networks']!)] ?? const [], 'name'),
      ['3', 'discover', 'movie'] => _discover(_filmsFrom[query['with_watch_providers']] ?? const [], 'title'),
      ['3', 'trending', 'all', 'week'] => {
        'page': 1,
        'total_pages': 1,
        'results': [
          {'id': 81, 'media_type': 'movie', 'title': 'Title 81', 'release_date': '2020-05-01'},
          {'id': 491, 'media_type': 'tv', 'name': 'Title 491', 'first_air_date': '2020-05-01'},
          {'id': 2133, 'media_type': 'tv', 'name': 'Title 2133', 'first_air_date': '2020-05-01'},
        ],
      },
      _ => const <String, Object?>{},
    };
    return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
  }),
);

Map<String, Object?> _discover(List<int> ids, String titleKey) => {
  'page': 1,
  'total_pages': 1,
  'results': [
    for (final (index, id) in [...ids, 999999].indexed) {'id': id, titleKey: 'TMDB $id', 'popularity': 1000 - index},
  ],
};

/// Home's Continue Watching: an episode of a Netflix series (`Title 2130`),
/// one of an HBO series and a Netflix film (`Title 80`).
const _home = {
  'sections': [
    {
      'id': 'sec-cw',
      'section_type': 'continue_watching',
      'title': 'Continue Watching',
      'total_count': 3,
      'items': [
        {
          'content_id': 'ep-2130',
          'type': 'episode',
          'title': 'Netflix Episode',
          'series_id': 'c2130',
          'series_title': 'Title 2130',
          'season_number': 1,
          'episode_number': 2,
        },
        {
          'content_id': 'ep-490',
          'type': 'episode',
          'title': 'HBO Episode',
          'series_id': 'c490',
          'series_title': 'Title 490',
          'season_number': 1,
          'episode_number': 1,
        },
        {'content_id': 'c80', 'type': 'movie', 'title': 'Title 80'},
      ],
    },
  ],
};

/// One Silo server whose library holds every title above, named
/// `Title {tmdb id}`; every catalog read fails when [libraryFails].
Future<(SiloClient, FakeSilo)> networksSilo({bool libraryFails = false}) async {
  final (session, _) = await signedInSession();
  final fake = FakeSilo((request) {
    if (request.url.path == '/api/v2/home/sections') return jsonResponse(_home, 200);
    if (libraryFails) return jsonResponse({}, 500);
    // A genre or year query (`POST /catalog/query`) carries its type and
    // rules in the body. Every title is from 2020.
    final body = request.method == 'POST' ? jsonDecode(request.body) as Map<String, dynamic> : const {};
    final series = (request.url.queryParameters['type'] ?? body['type']) == 'series';
    final genre = series ? 'Drama' : 'Comedy';
    final rules = [
      for (final group in (body['groups'] as List?) ?? const [])
        for (final rule in (group as Map)['rules'] as List) rule as Map,
    ];
    final genres = [
      for (final rule in rules)
        if (rule['field'] == 'genre') rule['value'],
    ];
    final outsideYears = rules.any((rule) {
      if (rule['field'] != 'year') return false;
      final [from as int, to as int] = rule['value'] as List;
      return 2020 < from || 2020 > to;
    });
    final ids = outsideYears || (genres.isNotEmpty && !genres.contains(genre))
        ? const <int>[]
        : series
        ? _seriesOn.values.expand((ids) => ids)
        : _filmsFrom.values.expand((ids) => ids);
    return jsonResponse({
      'items': [
        for (final id in ids)
          {
            'content_id': 'c$id',
            'type': series ? 'series' : 'movie',
            'title': 'Title $id',
            'tmdb_id': id,
            'year': 2020,
            // Every series is a drama; the films too few comedies to show.
            'genres': [genre],
            // Films were added last, so they lead their networks' rows.
            'added_at': series ? '2026-01-01T00:00:00Z' : '2026-06-01T00:00:00Z',
          },
      ],
      'page': {'has_more': false},
      'total': ids.length,
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

/// Pumps the section (Networks unless [section] builds another) alone over
/// [silo] (a fresh [networksSilo] by default), unreachable when [offline];
/// left to settle unless [settle] is false.
Future<({MultiServerManager manager, SiloClient client})> pumpNetworksSection(
  WidgetTester tester, {
  TmdbClient? tmdb,
  SiloClient? silo,
  bool offline = false,
  bool settle = true,
  LibraryHomeFilter filter = LibraryHomeFilter.moviesAndShows,
  Widget Function(LibraryHomeFilter filter)? section,
}) async {
  final client = silo ?? (await tester.runAsync(networksSilo))!.$1;
  final servers = testMultiServer(clients: [client], offline: [if (offline) client]);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<TmdbClient>.value(value: tmdb ?? networksTmdb()),
        ChangeNotifierProvider<MultiServerProvider>.value(value: servers.provider),
      ],
      child: MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child:
                section?.call(filter) ??
                LibraryNetworksSection(filter: filter, onNavigateUp: () {}, onNavigateToSidebar: () {}),
          ),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return (manager: servers.manager, client: client);
}
