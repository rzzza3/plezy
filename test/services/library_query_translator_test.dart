import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/library_query_translator.dart';
import 'package:plezy/utils/url_utils.dart';

void main() {
  group('PlexLibraryQueryTranslator', () {
    const translator = PlexLibraryQueryTranslator();

    test('empty query produces empty filter map', () {
      expect(translator.toQueryParameters(const LibraryQuery()), isEmpty);
    });

    test('movie kind maps to type=1', () {
      final params = translator.toQueryParameters(const LibraryQuery(kind: MediaKind.movie));
      expect(params['type'], '1');
    });

    test('show kind maps to type=2', () {
      final params = translator.toQueryParameters(const LibraryQuery(kind: MediaKind.show));
      expect(params['type'], '2');
    });

    test('multiple kinds map to a comma-delimited type filter', () {
      final params = translator.toQueryParameters(const LibraryQuery(includeKinds: [MediaKind.movie, MediaKind.show]));
      expect(params['type'], '1,2');
    });

    test('collection kind has no Plex type number (filtered separately)', () {
      final params = translator.toQueryParameters(const LibraryQuery(kind: MediaKind.collection));
      expect(params, isNot(contains('type')));
    });

    test('ascending sort appends :asc suffix', () {
      final params = translator.toQueryParameters(
        const LibraryQuery(
          sort: LibrarySort(field: 'titleSort', direction: LibrarySortDirection.ascending),
        ),
      );
      expect(params['sort'], 'titleSort:asc');
    });

    test('parseSortParam strips explicit ascending suffix', () {
      final sort = LibraryQueryTranslator.parseSortParam('titleSort:asc');
      expect(sort?.field, 'titleSort');
      expect(sort?.direction, LibrarySortDirection.ascending);
      expect(translator.toQueryParameters(LibraryQuery(sort: sort))['sort'], 'titleSort:asc');
    });

    test('descending sort appends :desc suffix (default direction)', () {
      final params = translator.toQueryParameters(const LibraryQuery(sort: LibrarySort(field: 'addedAt')));
      expect(params['sort'], 'addedAt:desc');
    });

    test('search puts text in title field', () {
      final params = translator.toQueryParameters(const LibraryQuery(search: 'star wars'));
      expect(params['title'], 'star wars');
    });

    test('arbitrary filter clauses pass through verbatim', () {
      final params = translator.toQueryParameters(
        const LibraryQuery(
          filters: [
            LibraryFilter(field: 'genre', values: ['Action', 'Drama']),
          ],
        ),
      );
      expect(params['genre'], 'Action,Drama');
    });

    test('a title clause and a search term both reach the wire instead of one winning', () {
      final params = translator.toQueryParameters(
        const LibraryQuery(
          search: 'wick',
          filters: [
            LibraryFilter(field: 'title', op: LibraryFilterOperator.beginsWith, values: ['The']),
          ],
        ),
      );
      expect(params['title'], 'wick');
      expect(params['title<'], 'The');
    });

    test('the operator rides in the query key, keeping its trailing = as the separator', () {
      final params = translator.toQueryParameters(
        const LibraryQuery(
          filters: [
            LibraryFilter(field: 'genre', op: LibraryFilterOperator.isNot, values: ['Comedy']),
            LibraryFilter(field: 'year', op: LibraryFilterOperator.atLeast, values: ['2015']),
            LibraryFilter(field: 'year', op: LibraryFilterOperator.atMost, values: ['2018']),
            LibraryFilter(field: 'title', op: LibraryFilterOperator.matches, values: ['Wicked']),
            LibraryFilter(field: 'title', op: LibraryFilterOperator.beginsWith, values: ['Wick']),
          ],
        ),
      );
      expect(params['genre!'], 'Comedy');
      expect(params['year>>'], '2015');
      expect(params['year<<'], '2018');
      expect(params['title='], 'Wicked');
      expect(params['title<'], 'Wick');
    });

    test('two clauses on one field with the same operator repeat the key so Plex ANDs them', () {
      final params = translator.toQueryParameters(
        const LibraryQuery(
          filters: [
            LibraryFilter(field: 'genre', values: ['Comedy']),
            LibraryFilter(field: 'genre', values: ['Drama']),
          ],
        ),
      );
      expect(params['genre'], ['Comedy', 'Drama']);
      expect(encodeQueryParameters(params), 'genre=Comedy&genre=Drama');
    });

    // Percent-encoding the operator and the value separator is safe: PMS
    // decodes query keys, so `genre!=a%2Cb` and `genre!=a,b` select the same
    // rows. What it must never see is an encoded separator (`genre%21%3D=a`),
    // which is why the operator's trailing `=` is not part of the key.
    test('a negated clause encodes to a query Plex parses as one clause', () {
      final params = translator.toQueryParameters(
        const LibraryQuery(
          filters: [
            LibraryFilter(field: 'genre', op: LibraryFilterOperator.isNot, values: ['Comedy', 'Horror']),
          ],
        ),
      );
      expect(encodeQueryParameters(params), 'genre!=Comedy%2CHorror');
    });

    test('empty clauses and values are dropped rather than sent as bare keys', () {
      final params = translator.toQueryParameters(
        const LibraryQuery(
          filters: [
            LibraryFilter(field: 'genre', values: ['']),
            LibraryFilter(field: '', values: ['x']),
            LibraryFilter(field: 'tag', values: []),
          ],
        ),
      );
      expect(params, isEmpty);
    });
  });

  group('LibraryQueryTranslator.parseSortParam', () {
    test('returns null for null/empty input', () {
      expect(LibraryQueryTranslator.parseSortParam(null), isNull);
      expect(LibraryQueryTranslator.parseSortParam(''), isNull);
    });

    test('parses bare field as ascending', () {
      final sort = LibraryQueryTranslator.parseSortParam('addedAt');
      expect(sort, isNotNull);
      expect(sort!.field, 'addedAt');
      expect(sort.direction, LibrarySortDirection.ascending);
    });

    test('parses field:desc as descending', () {
      final sort = LibraryQueryTranslator.parseSortParam('rating:desc');
      expect(sort, isNotNull);
      expect(sort!.field, 'rating');
      expect(sort.direction, LibrarySortDirection.descending);
    });

    test('handles dotted Plex sort keys without losing the field', () {
      final sort = LibraryQueryTranslator.parseSortParam('episode.originallyAvailableAt:desc');
      expect(sort!.field, 'episode.originallyAvailableAt');
      expect(sort.direction, LibrarySortDirection.descending);
    });

    test('returns null when only the suffix is present', () {
      expect(LibraryQueryTranslator.parseSortParam(':desc'), isNull);
    });
  });

  // The browse tab holds the user's selection as clauses and assembles the
  // neutral query at the fetch boundary; the Plex client lowers it back to
  // wire params. Selections saved by prior versions (and by the sheet) must
  // survive that trip, so the assembly is pinned here.
  group('libraryQueryFromSelection', () {
    const translator = PlexLibraryQueryTranslator();

    Map<String, dynamic> wire({
      List<LibraryFilter> clauses = const [],
      MediaKind? libraryKind,
      String? typeParam,
      String? sortParam,
      String? alphaPrefix,
    }) => translator.toQueryParameters(
      libraryQueryFromSelection(
        clauses: clauses,
        libraryKind: libraryKind,
        typeParam: typeParam,
        sortParam: sortParam,
        alphaPrefix: alphaPrefix,
      ),
    );

    test('clauses, sort and alpha prefix reach the wire together', () {
      expect(
        wire(
          clauses: const [
            LibraryFilter(field: 'genre', values: ['Comedy']),
            LibraryFilter(field: 'unwatched', values: ['1']),
          ],
          sortParam: 'addedAt:desc',
          alphaPrefix: 'B',
        ),
        {'genre': 'Comedy', 'unwatched': '1', 'sort': 'addedAt:desc', 'alphaPrefix': 'B'},
      );
    });

    test('libraryKind overrides any grouping type parameter', () {
      final query = libraryQueryFromSelection(clauses: const [], typeParam: '1', libraryKind: MediaKind.show);
      expect(query.kind, MediaKind.show);
    });

    test('numeric grouping type maps to a kind when no libraryKind is given', () {
      final query = libraryQueryFromSelection(clauses: const [], typeParam: '1');
      expect(query.kind, MediaKind.movie);
    });

    test('multi-value type stays a clause so Plex still receives it verbatim', () {
      // Plex shared libraries use `type=1,4` for movies+episodes — no single
      // MediaKind covers that.
      expect(wire(typeParam: '1,4')['type'], '1,4');
    });

    test('an empty selection produces an empty query', () {
      expect(wire(), isEmpty);
    });
  });
}
