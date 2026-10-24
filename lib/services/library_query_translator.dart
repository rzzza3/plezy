import '../media/library_query.dart';
import '../media/media_kind.dart';

/// Parse a sort string (`field`, `field:asc` or `field:desc`) into a
/// [LibrarySort]. Returns `null` when the input is empty or the field portion
/// is missing.
LibrarySort? parseLibrarySortParam(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  const descSuffix = ':desc';
  const ascSuffix = ':asc';
  final descending = raw.endsWith(descSuffix);
  final ascending = raw.endsWith(ascSuffix);
  final field = descending
      ? raw.substring(0, raw.length - descSuffix.length)
      : ascending
      ? raw.substring(0, raw.length - ascSuffix.length)
      : raw;
  if (field.isEmpty) return null;
  return LibrarySort(
    field: field,
    direction: descending ? LibrarySortDirection.descending : LibrarySortDirection.ascending,
  );
}

/// Assemble the neutral [LibraryQuery] the library browse surfaces run.
///
/// [clauses] is the user's filter selection; [kind] is the kind the active
/// grouping browses (or the library's own); [sortParam] is the `field:desc`
/// string the sort sheet produces.
LibraryQuery libraryQueryFromSelection({
  required List<LibraryFilter> clauses,
  MediaKind? kind,
  String? sortParam,
  String? alphaPrefix,
  String? search,
  int offset = 0,
  int limit = 50,
}) {
  String? nonEmpty(String? raw) => (raw == null || raw.isEmpty) ? null : raw;

  return LibraryQuery(
    kind: (kind == null || kind == MediaKind.unknown) ? null : kind,
    offset: offset,
    limit: limit,
    nameStartsWith: nonEmpty(alphaPrefix),
    search: nonEmpty(search),
    sort: parseLibrarySortParam(nonEmpty(sortParam)),
    filters: clauses,
  );
}
