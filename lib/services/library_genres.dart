import 'package:collection/collection.dart';

import '../media/media_item.dart';
import '../media/media_item_sort.dart';
import '../media/media_kind.dart';
import 'library_networks.dart';
import 'silo_client.dart';
import 'tmdb/tmdb_client.dart';
import 'tmdb/tmdb_genres.dart';
import 'tmdb/tmdb_models.dart';

/// The Library tab's Genres row: the library's titles in each chosen genre,
/// by the genres Silo lists on them, so every card is a library item. TMDB
/// only ranks them.
///
/// Silo is asked per genre rather than the whole library read, which can
/// hold tens of thousands of titles: per kind and server, the
/// [titlesPerQuery] newest added (so the row's newest are right) and the
/// [titlesPerQuery] highest rated (so the page has the best).
class LibraryGenres {
  /// Titles each Silo query returns (one request each).
  static const int titlesPerQuery = 100;

  /// Null without TMDB credentials: titles then rank by rating alone.
  final TmdbClient? tmdb;

  LibraryGenres(this.tmdb);

  /// [genre]'s titles on [clients], movies and series merged most popular
  /// first: those TMDB ranks in the genre's first
  /// [LibraryNetworks.pagesPerList] discover pages, then the rest by rating.
  /// Throws when any Silo read fails, so a partial row is never cached.
  Future<List<MediaItem>> match(LibraryGenre genre, List<SiloClient> clients) async {
    Future<List<({MediaItem item, int? tmdbId})>> read(MediaKind kind) async {
      final reads = await Future.wait([
        for (final client in clients)
          for (final sort in const ['added_at', 'rating_imdb'])
            client.fetchTitlesInGenres(kind, genre.names, sort: sort, limit: titlesPerQuery),
      ]);
      final seen = <String>{};
      return [
        for (final title in reads.expand((titles) => titles))
          if (seen.add(title.item.globalKey)) title,
      ];
    }

    final [movies, shows] = await Future.wait([read(MediaKind.movie), read(MediaKind.show)]);
    final ranked = <({MediaItem item, double popularity})>[];
    final tmdb = this.tmdb;
    if (tmdb != null && tmdb.isConfigured) {
      final matcher = LibraryNetworks(tmdb);
      Map<String, String> query(String genres) => {'with_genres': genres};
      final lists = await Future.wait([
        if (genre.tmdbMovieGenres case final genres? when movies.isNotEmpty)
          matcher.discoverMatches(TmdbMediaType.movie, query(genres), LibraryTitleIndex(movies)),
        if (genre.tmdbTvGenres case final genres? when shows.isNotEmpty)
          matcher.discoverMatches(TmdbMediaType.tv, query(genres), LibraryTitleIndex(shows)),
      ]);
      ranked.addAll(lists.expand((list) => list));
      mergeSort(ranked, compare: (a, b) => b.popularity.compareTo(a.popularity));
    }
    final rest = [
      for (final title in [...movies, ...shows]) title.item,
    ]..sort(mediaItemSortComparator(mediaSortKeyRating, descending: true));
    final seen = <String>{};
    return [
      for (final item in [for (final match in ranked) match.item, ...rest])
        if (seen.add(item.globalKey)) item,
    ];
  }
}
