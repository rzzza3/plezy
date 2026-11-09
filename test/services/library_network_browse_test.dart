import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_filter.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_item_sort.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_sort.dart';
import 'package:plezy/services/library_network_browse.dart';

MediaItem _item(
  String id, {
  MediaKind kind = MediaKind.show,
  String? title,
  int? year,
  int? addedAt,
  List<String>? genres,
  String? contentRating,
  bool watched = false,
}) => MediaItem.silo(
  id: id,
  kind: kind,
  title: title ?? id,
  year: year,
  addedAt: addedAt,
  genres: genres,
  contentRating: contentRating,
  viewCount: watched ? 1 : 0,
  serverId: 'server-1',
);

/// Most popular first.
final _items = [
  _item('Crown', year: 2016, addedAt: 3, genres: ['Drama'], contentRating: 'TV-MA'),
  _item('Below', kind: MediaKind.movie, year: 2026, addedAt: 9, genres: ['Thriller'], watched: true),
  _item('Animals', kind: MediaKind.movie, year: 2026, addedAt: 5, genres: ['Drama', 'Sci-Fi/Fantasy']),
  _item('Bojack', year: 2014, genres: ['Comedy'], contentRating: 'TV-MA'),
];

List<String> _ids(List<MediaItem> items) => [for (final item in items) item.id];

List<String> _apply({List<LibraryFilter> filters = const [], MediaSort? sort, bool descending = false}) =>
    _ids(LibraryNetworkBrowse.apply(_items, filters: filters, sort: sort, descending: descending));

MediaSort _sort(String key) => LibraryNetworkBrowse.sortOptions().firstWhere((sort) => sort.key == key);

void main() {
  test('sorts A–Z by default, by popularity, or by date added with undated titles last', () {
    expect(_apply(), ['Animals', 'Below', 'Bojack', 'Crown']);
    expect(_apply(sort: _sort(LibraryNetworkBrowse.popularity)), ['Crown', 'Below', 'Animals', 'Bojack']);
    expect(_apply(sort: _sort(LibraryNetworkBrowse.popularity), descending: true), [
      'Bojack',
      'Animals',
      'Below',
      'Crown',
    ]);
    // Undated titles go last either way.
    expect(_apply(sort: _sort(mediaSortKeyDateAdded), descending: true), ['Below', 'Animals', 'Crown', 'Bojack']);
    expect(_apply(sort: _sort(mediaSortKeyDateAdded)), ['Crown', 'Animals', 'Below', 'Bojack']);
  });

  test('filters by type, genre, year, rating and unwatched; clauses AND together', () {
    LibraryFilter clause(String field, List<String> values, [LibraryFilterOperator op = LibraryFilterOperator.is_]) =>
        LibraryFilter(field: field, op: op, values: values);

    expect(
      _apply(
        filters: [
          clause(LibraryNetworkBrowse.type, [LibraryNetworkBrowse.movieType]),
        ],
      ),
      ['Animals', 'Below'],
    );
    expect(
      _apply(
        filters: [
          clause(MediaFilterField.genre, ['Drama', 'Comedy']),
        ],
      ),
      ['Animals', 'Bojack', 'Crown'],
    );
    expect(
      _apply(
        filters: [
          clause(MediaFilterField.genre, ['Drama'], LibraryFilterOperator.isNot),
        ],
      ),
      ['Below', 'Bojack'],
    );
    expect(
      _apply(
        filters: [
          clause(MediaFilterField.year, ['2015'], LibraryFilterOperator.atLeast),
          clause(MediaFilterField.year, ['2020'], LibraryFilterOperator.atMost),
        ],
      ),
      ['Crown'],
    );
    expect(
      _apply(
        filters: [
          clause(MediaFilterField.contentRating, ['TV-MA']),
        ],
      ),
      ['Bojack', 'Crown'],
    );
    expect(
      _apply(
        filters: [
          clause(MediaFilterField.unwatched, ['1']),
        ],
      ),
      ['Animals', 'Bojack', 'Crown'],
    );
    expect(
      _apply(
        filters: [
          clause(MediaFilterField.unwatched, ['1'], LibraryFilterOperator.isNot),
        ],
      ),
      ['Below'],
    );
    expect(
      _apply(
        filters: [
          clause(MediaFilterField.genre, ['Drama']),
          clause(LibraryNetworkBrowse.type, [LibraryNetworkBrowse.showType]),
        ],
      ),
      ['Crown'],
    );
  });

  test('offers only categories the titles can be narrowed by, with their values', () {
    final result = LibraryNetworkBrowse.filtersFor(_items);
    expect(
      [for (final filter in result.filters) filter.filter],
      [
        MediaFilterField.unwatched,
        LibraryNetworkBrowse.type,
        MediaFilterField.genre,
        MediaFilterField.year,
        MediaFilterField.contentRating,
      ],
    );
    final genres = result.cachedValues[MediaFilterField.genre]!;
    expect([for (final value in genres) value.title], ['Comedy', 'Drama', 'Sci-Fi/Fantasy', 'Thriller']);
    // The id the editor stores is the genre's name, slash and all.
    expect(libraryFilterValueId(genres[2].key, MediaFilterField.genre), 'Sci-Fi/Fantasy');

    final moviesOnly = LibraryNetworkBrowse.filtersFor([_items[1]]);
    expect(
      [for (final filter in moviesOnly.filters) filter.filter],
      [MediaFilterField.unwatched, MediaFilterField.genre, MediaFilterField.year],
    );
  });
}
