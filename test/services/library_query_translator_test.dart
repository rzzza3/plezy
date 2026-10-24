import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/library_query_translator.dart';

void main() {
  group('parseLibrarySortParam', () {
    test('returns null for null/empty input', () {
      expect(parseLibrarySortParam(null), isNull);
      expect(parseLibrarySortParam(''), isNull);
    });

    test('parses bare field as ascending', () {
      final sort = parseLibrarySortParam('addedAt');
      expect(sort, isNotNull);
      expect(sort!.field, 'addedAt');
      expect(sort.direction, LibrarySortDirection.ascending);
    });

    test('strips explicit ascending suffix', () {
      final sort = parseLibrarySortParam('titleSort:asc');
      expect(sort?.field, 'titleSort');
      expect(sort?.direction, LibrarySortDirection.ascending);
    });

    test('parses field:desc as descending', () {
      final sort = parseLibrarySortParam('rating:desc');
      expect(sort, isNotNull);
      expect(sort!.field, 'rating');
      expect(sort.direction, LibrarySortDirection.descending);
    });

    test('handles dotted sort keys without losing the field', () {
      final sort = parseLibrarySortParam('episode.originallyAvailableAt:desc');
      expect(sort!.field, 'episode.originallyAvailableAt');
      expect(sort.direction, LibrarySortDirection.descending);
    });

    test('returns null when only the suffix is present', () {
      expect(parseLibrarySortParam(':desc'), isNull);
    });
  });

  // The browse tab holds the user's selection as clauses and assembles the
  // neutral query at the fetch boundary, so the assembly is pinned here.
  group('libraryQueryFromSelection', () {
    test('clauses, sort and alpha prefix reach the query together', () {
      const clauses = [
        LibraryFilter(field: 'genre', values: ['Comedy']),
        LibraryFilter(field: 'unwatched', values: ['1']),
      ];
      final query = libraryQueryFromSelection(clauses: clauses, sortParam: 'addedAt:desc', alphaPrefix: 'B');
      expect(query.filters, clauses);
      expect(query.sort?.field, 'addedAt');
      expect(query.sort?.direction, LibrarySortDirection.descending);
      expect(query.nameStartsWith, 'B');
    });

    test('kind is carried through, unknown kind is dropped', () {
      expect(libraryQueryFromSelection(clauses: const [], kind: MediaKind.show).kind, MediaKind.show);
      expect(libraryQueryFromSelection(clauses: const [], kind: MediaKind.unknown).kind, isNull);
    });

    test('search, offset and limit pass through', () {
      final query = libraryQueryFromSelection(clauses: const [], search: 'star wars', offset: 100, limit: 25);
      expect(query.search, 'star wars');
      expect(query.offset, 100);
      expect(query.limit, 25);
    });

    test('an empty selection produces an empty query', () {
      final query = libraryQueryFromSelection(clauses: const [], sortParam: '', alphaPrefix: '', search: '');
      expect(query, const LibraryQuery());
    });
  });
}
