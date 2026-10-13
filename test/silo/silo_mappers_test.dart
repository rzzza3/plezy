import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/silo/silo_artwork.dart';
import 'package:plezy/silo/silo_mappers.dart';
import 'package:plezy/silo/silo_models.dart';

final _origin = SiloOrigin(ServerId('server-1'), 'Silo');

List<SiloSection> _fixture() => SiloSection.listFromJson(
  resolveSiloArtworkUrls(
    jsonDecode(File('test/silo/fixtures/home_sections.json').readAsStringSync()),
    Uri.parse('https://silo.ruleone.xyz/api/v2/home/sections'),
  ),
);

SiloSection _section(String id) => _fixture().singleWhere((s) => s.id == id);

void main() {
  test('a recorded section shape maps to a MediaHub with its title, type and item count', () {
    final hub = siloSectionToHub(_section('sec-added'), _origin, hubId: 'silo-home:sec-added');

    expect(hub.id, 'silo-home:sec-added');
    expect(hub.identifier, 'recently_added');
    expect(hub.title, 'Recently Added');
    expect(hub.type, 'movie');
    expect(hub.items, hasLength(4));
    expect(hub.size, 30);
    expect(hub.more, isTrue);
    expect(hub.serverId, 'server-1');
    expect(hub.items.first.thumbPath, 'https://silo.ruleone.xyz/img/movie-2/poster.jpg');
  });

  test('every section_type in research/samples/home-sections.json has a role', () {
    final samples =
        (jsonDecode(File('docs/silo-migration/research/samples/home-sections.json').readAsStringSync())
                as Map)['section_type_values']
            as List;

    expect(
      {for (final type in samples) type: siloSectionRole(type as String)},
      {
        'collection': SiloRowRole.shelf,
        'continue_watching': SiloRowRole.continueWatching,
        'custom_filter': SiloRowRole.shelf,
        'favorites': SiloRowRole.shelf,
        'recently_added': SiloRowRole.shelf,
        'recently_released': SiloRowRole.shelf,
        'recommended_for_you': SiloRowRole.shelf,
        'taste_match': SiloRowRole.shelf,
        'trending_on_server': SiloRowRole.shelf,
        'watchlist': SiloRowRole.shelf,
      },
    );
  });

  test('an unknown section_type falls back to the TvSkylineSectionFeed.kt:1022-1034 substrings, else a shelf', () {
    expect(siloSectionRole('mystery_recipe_v9'), SiloRowRole.shelf);
    expect(siloSectionRole('Continue_Listening'), SiloRowRole.continueWatching);
    expect(siloSectionRole('series_up_next'), SiloRowRole.nextUp);
    expect(siloSectionRole(''), SiloRowRole.shelf);
  });

  test('ebook-like cards are dropped and an emptied row goes (TvMediaTypeFilters.kt:32-36)', () {
    expect(siloVisibleSection(_section('sec-books')), isNull);
    expect(siloVisibleSection(_section('sec-added'))?.items, hasLength(4));
  });

  test('a Continue Watching episode card keeps its series, position and artwork', () {
    final item = siloCardToItem(_section('sec-cw').items.first, _origin);

    expect(item, isA<SiloMediaItem>());
    expect(item.backend, MediaBackend.silo);
    expect(item.kind, MediaKind.episode);
    expect(item.grandparentId, 'show-1');
    expect(item.grandparentTitle, 'Show A');
    expect((item.parentIndex, item.index), (2, 3));
    expect(item.viewOffsetMs, 600000);
    expect(item.durationMs, 2520000);
    expect(item.hasActiveProgress, isTrue);
    expect(item.lastViewedAt, DateTime.utc(2026, 10, 12, 20).millisecondsSinceEpoch ~/ 1000);
    expect(item.thumbPath, 'https://silo.ruleone.xyz/img/ep-1/backdrop.jpg');
    expect(item.grandparentThumbPath, 'https://silo.ruleone.xyz/img/ep-1/poster.jpg');
    expect(item.clearLogoPath, 'https://silo.ruleone.xyz/img/show-1/logo.png');
    expect(item.globalKey, 'server-1:ep-1');
  });

  test('a signed absolute artwork URL is left untouched', () {
    final movie = siloCardToItem(_section('sec-cw').items[1], _origin);

    expect(movie.artPath, 'https://cdn.example/b.jpg?exp=1&sig=x');
  });

  test('user state maps to watched and favorite', () {
    final item = siloCardToItem(_section('sec-fav').items.single, _origin);

    expect(item.isWatched, isTrue);
    expect(item.isFavorite, isTrue);
    expect(item.ratings?.single.source, 'tmdb');
  });

  test('a Silo item survives the MediaItem JSON round trip', () {
    final item = siloCardToItem(_section('sec-cw').items.first, _origin);

    final restored = MediaItem.fromJson(jsonDecode(jsonEncode(item.toJson())) as Map<String, dynamic>);

    expect(restored, isA<SiloMediaItem>());
    expect((restored.id, restored.kind, restored.viewOffsetMs), ('ep-1', MediaKind.episode, 600000));
  });

  test('detail maps cast, crew and the 1-5 user rating', () {
    final item = siloDetailToItem(
      SiloItemDetail.fromJson({
        'content_id': 'movie-1',
        'type': 'movie',
        'title': 'Movie A',
        'year': 2020,
        'runtime': 110,
        'overview': 'Synthetic.',
        'user_rating': 4,
        'cast': [
          {'name': 'Actor A', 'character': 'Role A', 'person_id': '12', 'photo_url': 'https://x/p.jpg'},
        ],
        'crew': [
          {'name': 'Director A', 'job': 'Director'},
          {'name': 'Writer A', 'job': 'Screenplay'},
        ],
        'versions': [],
        'subtitles': [],
        'user_data': {'played': true},
      }),
      _origin,
    );

    expect((item.title, item.year, item.durationMs, item.summary), ('Movie A', 2020, 6600000, 'Synthetic.'));
    expect(item.roles?.single.tag, 'Actor A');
    expect(item.roles?.single.role, 'Role A');
    expect(item.roles?.single.id, '12');
    expect(item.directors, ['Director A']);
    expect(item.writers, ['Writer A']);
    expect(item.userRating, 8.0);
    expect(item.isWatched, isTrue);
  });

  test('a detail without its required arrays is refused (CatalogDetailReadV2Models.kt:17-81)', () {
    expect(
      () => SiloItemDetail.fromJson({'content_id': 'x', 'type': 'movie', 'title': 'X'}),
      throwsA(isA<SiloDecodeException>()),
    );
  });

  test('a home row without items rejects the response (HomeSectionsV2Api.kt:41-44)', () {
    expect(
      () => SiloSection.listFromJson({
        'sections': [
          {'id': 'a', 'section_type': 'x', 'title': 'A'},
        ],
      }),
      throwsA(isA<SiloDecodeException>()),
    );
  });

  group('seasons', () {
    SiloSeason season(String id, int n, {bool specials = false, int count = 10, int watched = 0, int inProgress = 0}) =>
        SiloSeason(
          contentId: id,
          seasonNumber: n,
          isSpecials: specials,
          episodeCount: count,
          played: watched == count,
          watchedCount: watched,
          inProgressCount: inProgress,
        );

    test('numbered seasons come first and specials last (CatalogModels.kt:483-493)', () {
      final ordered = siloSeasonsForDisplay([
        season('s0', 0),
        season('s2', 2),
        season('x', 5, specials: true),
        season('s1', 1),
      ]);

      expect(ordered.map((s) => s.contentId), ['s1', 's2', 's0', 'x']);
    });

    test('the initial season follows CatalogModels.kt:495-509', () {
      final watched = season('s1', 1, watched: 10);
      final partly = season('s2', 2, watched: 3);
      final resuming = season('s3', 3, inProgress: 1);
      final fresh = season('s4', 4);

      expect(siloInitialSeason([watched, partly, resuming, fresh])?.contentId, 's3');
      expect(siloInitialSeason([watched, partly, fresh])?.contentId, 's2');
      expect(siloInitialSeason([watched, fresh])?.contentId, 's4');
      expect(siloInitialSeason([watched])?.contentId, 's1');
      expect(siloInitialSeason([watched, fresh], preferredSeasonNumber: 1)?.contentId, 's1');
      expect(siloInitialSeason(const []), isNull);
    });

    test('the next-up episode follows TvItemDetailViewModel.kt:1835-1839', () {
      SiloEpisode episode(String id, {bool played = false, bool inProgress = false}) => SiloEpisode(
        contentId: id,
        seasonNumber: 1,
        episodeNumber: 1,
        userData: SiloLeafUserData(played: played, isInProgress: inProgress),
      );

      expect(
        siloNextUpEpisode([episode('a', played: true), episode('b'), episode('c', inProgress: true)])?.contentId,
        'c',
      );
      expect(siloNextUpEpisode([episode('a', played: true), episode('b')])?.contentId, 'b');
      expect(siloNextUpEpisode([episode('a', played: true)])?.contentId, 'a');
    });
  });
}
