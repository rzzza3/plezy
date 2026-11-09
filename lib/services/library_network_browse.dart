import 'package:collection/collection.dart';

import '../i18n/strings.g.dart';
import '../media/library_filter_result.dart';
import '../media/library_query.dart';
import '../media/media_filter.dart';
import '../media/media_item.dart';
import '../media/media_item_sort.dart';
import '../media/media_kind.dart';
import '../media/media_sort.dart';

/// Sort and filters for a network page's All Content grid. Applied on the
/// device to the network's library titles, which already carry every field
/// offered, so nothing is fetched.
abstract final class LibraryNetworkBrowse {
  /// The network's own order, most popular first.
  static const popularity = 'popularity';

  /// Movies or TV.
  static const type = 'type';
  static const movieType = 'movie';
  static const showType = 'show';

  static List<MediaSort> sortOptions() => [
    MediaSort(key: mediaSortKeyTitle, title: t.libraries.sortLabels.title, defaultDirection: 'asc'),
    MediaSort(key: popularity, title: t.libraryHome.networkPopularity, defaultDirection: 'asc'),
    MediaSort(key: mediaSortKeyDateAdded, title: t.libraries.sortLabels.dateAdded, defaultDirection: 'desc'),
    MediaSort(key: mediaSortKeyReleaseDate, title: t.libraries.sortLabels.releaseDate, defaultDirection: 'desc'),
    MediaSort(key: mediaSortKeyRating, title: t.libraries.sortLabels.rating, defaultDirection: 'desc'),
  ];

  /// The filter categories [items] can be narrowed by, with every value
  /// they hold. Categories with nothing to choose between are left out.
  static LibraryFilterResult filtersFor(List<MediaItem> items) {
    final hasMovies = items.any((item) => item.kind == MediaKind.movie);
    final hasShows = items.any((item) => item.kind != MediaKind.movie);
    final genres = _distinct([for (final item in items) ...?item.genres]);
    final ratings = _distinct([for (final item in items) ?item.contentRating]);
    final hasYears = items.any((item) => item.year != null);
    MediaFilter category(String field, String filterType, String title, {bool listed = false}) => MediaFilter(
      filter: field,
      filterType: filterType,
      key: listed ? field : '',
      title: title,
      type: 'filter',
      operators: switch (filterType) {
        MediaFilterType.integer => const [LibraryFilterOperator.atLeast, LibraryFilterOperator.atMost],
        _ when field == type => const [LibraryFilterOperator.is_],
        _ => null,
      },
    );
    return LibraryFilterResult(
      filters: [
        category(MediaFilterField.unwatched, MediaFilterType.boolean, t.libraries.filterCategories.unwatched),
        if (hasMovies && hasShows) category(type, MediaFilterType.string, t.libraryHome.networkType, listed: true),
        if (genres.isNotEmpty)
          category(MediaFilterField.genre, MediaFilterType.tag, t.libraries.filterCategories.genre, listed: true),
        if (hasYears) category(MediaFilterField.year, MediaFilterType.integer, t.libraries.filterCategories.year),
        if (ratings.isNotEmpty)
          category(
            MediaFilterField.contentRating,
            MediaFilterType.string,
            t.libraries.filterCategories.contentRating,
            listed: true,
          ),
      ],
      cachedValues: {
        type: [
          MediaFilterValue(key: movieType, title: t.libraries.groupings.movies),
          MediaFilterValue(key: showType, title: t.libraries.groupings.shows),
        ],
        MediaFilterField.genre: _values(genres),
        MediaFilterField.contentRating: _values(ratings),
      },
    );
  }

  /// [items] (most popular first) kept to those matching every clause of
  /// [filters], in [sort]'s order; A–Z without one.
  static List<MediaItem> apply(
    List<MediaItem> items, {
    required List<LibraryFilter> filters,
    required MediaSort? sort,
    required bool descending,
  }) {
    final shown = [
      for (final item in items)
        if (filters.every((clause) => _matches(item, clause))) item,
    ];
    final key = sort?.key ?? mediaSortKeyTitle;
    if (key == popularity) return descending ? shown.reversed.toList() : shown;
    // Titles without the sorted field go last either way.
    return shown..sort(mediaItemSortComparator(key, descending: descending));
  }

  static bool _matches(MediaItem item, LibraryFilter clause) {
    if (clause.field == MediaFilterField.year) {
      final year = item.year;
      final bound = int.tryParse(clause.values.firstOrNull ?? '');
      if (year == null || bound == null) return false;
      return switch (clause.op) {
        LibraryFilterOperator.atLeast => year >= bound,
        LibraryFilterOperator.atMost => year <= bound,
        _ => year == bound,
      };
    }
    final hit = switch (clause.field) {
      MediaFilterField.unwatched => !item.isWatched,
      type => clause.values.contains(item.kind == MediaKind.movie ? movieType : showType),
      MediaFilterField.genre => item.genres?.any(clause.values.contains) ?? false,
      MediaFilterField.contentRating => clause.values.contains(item.contentRating),
      _ => true,
    };
    return clause.op.isNegated ? !hit : hit;
  }

  static List<String> _distinct(List<String> values) =>
      values.where((value) => value.isNotEmpty).toSet().toList()..sort(compareAsciiLowerCase);

  // Encoded, as the editor reads a value's id through
  // `libraryFilterValueId`, which would split a name holding a `/`.
  static List<MediaFilterValue> _values(List<String> names) => [
    for (final name in names) MediaFilterValue(key: Uri.encodeComponent(name), title: name),
  ];
}
