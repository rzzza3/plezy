import '../media/library_query.dart';
import '../media/media_kind.dart';
import 'plex_constants.dart';

/// Translates a backend-neutral [LibraryQuery] into the per-backend
/// query-parameter map that the corresponding `/library/sections/{id}/all`
/// (Plex) endpoint expects.
///
/// Pulled out of the clients so the translation can be unit-tested without
/// spinning up an HTTP layer, and so the per-backend filter/sort name
/// mappings live in one place.
abstract class LibraryQueryTranslator {
  Map<String, dynamic> toQueryParameters(LibraryQuery query);

  /// Parse a Plex-style sort string (`field` or `field:desc`) into the
  /// backend-neutral [LibrarySort] consumed by the translators. Returns
  /// `null` when the input is empty or the field portion is missing.
  static LibrarySort? parseSortParam(String? raw) {
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
}

/// Plex's `/library/sections/{id}/all` accepts a flat `key=value` query.
/// Numeric `type=` selects the result class (1=movie, 2=show, …);
/// `sort=titleSort:asc` chains field+direction; filter clauses are lowered by
/// [plexFilterQueryParameters].
class PlexLibraryQueryTranslator implements LibraryQueryTranslator {
  const PlexLibraryQueryTranslator();

  @override
  Map<String, dynamic> toQueryParameters(LibraryQuery query) {
    final params = <String, dynamic>{};
    if (query.includeKinds.isNotEmpty) {
      final kindNumbers = query.includeKinds.map(PlexMetadataType.forKind).whereType<int>().join(',');
      if (kindNumbers.isNotEmpty) {
        params['type'] = kindNumbers;
      }
    } else {
      final kindNumber = PlexMetadataType.forKind(query.kind);
      if (kindNumber != null) {
        params['type'] = kindNumber.toString();
      }
    }
    final sort = query.sort;
    if (sort != null) {
      final dir = sort.direction == LibrarySortDirection.descending ? ':desc' : ':asc';
      params['sort'] = '${sort.field}$dir';
    }
    if (query.search != null && query.search!.isNotEmpty) {
      params['title'] = query.search!;
    }
    if (query.nameStartsWith != null && query.nameStartsWith!.isNotEmpty) {
      params['alphaPrefix'] = query.nameStartsWith!;
    }
    for (final entry in plexFilterQueryParameters(query.filters).entries) {
      final existing = params[entry.key];
      if (existing == null) {
        params[entry.key] = entry.value;
        continue;
      }
      // `title` can arrive from both the search box and a clause; Plex ANDs
      // repeated keys, so keep both instead of letting one win.
      params[entry.key] = <String>[
        ...existing is List<String> ? existing : <String>[existing as String],
        ...entry.value is List<String> ? entry.value as List<String> : <String>[entry.value as String],
      ];
    }
    return params;
  }
}

/// Lower filter clauses onto Plex's query vocabulary.
///
/// The operator lives in the query *key* (`year>>=2015` is key `year>>`,
/// value `2015`), values inside one clause are comma-joined and OR, and two
/// clauses that produce the same key repeat it, which Plex ANDs. Repeated
/// keys survive to the wire because `encodeQueryParameters` expands iterable
/// values into repeated pairs.
Map<String, dynamic> plexFilterQueryParameters(Iterable<LibraryFilter> clauses) {
  final params = <String, dynamic>{};
  for (final clause in clauses) {
    final values = clause.values.where((value) => value.isNotEmpty).toList();
    if (clause.field.isEmpty || values.isEmpty) continue;
    final key = '${clause.field}${clause.op.wireSuffix}';
    final value = values.join(',');
    final existing = params[key];
    if (existing == null) {
      params[key] = value;
    } else if (existing is List<String>) {
      existing.add(value);
    } else {
      params[key] = <String>[existing as String, value];
    }
  }
  return params;
}

/// Assemble the neutral [LibraryQuery] the library browse surfaces run.
///
/// [clauses] is the user's filter selection; [typeParam] is the grouping's
/// Plex metadata type (a single number folds into [LibraryQuery.kind], a CSV
/// stays a `type` clause so Plex still receives it verbatim); [sortParam] is
/// the Plex-style `field:desc` string the sort sheet produces.
///
/// `libraryKind` overrides any [typeParam] — both can be sources of truth in
/// the browse tab and the explicit argument wins.
LibraryQuery libraryQueryFromSelection({
  required List<LibraryFilter> clauses,
  MediaKind? libraryKind,
  String? typeParam,
  String? sortParam,
  String? alphaPrefix,
  String? search,
  int offset = 0,
  int limit = 50,
}) {
  String? nonEmpty(String? raw) => (raw == null || raw.isEmpty) ? null : raw;

  final typeRaw = nonEmpty(typeParam);
  final kindFromType = (typeRaw != null && !typeRaw.contains(','))
      ? PlexMetadataType.kindFor(int.tryParse(typeRaw))
      : null;
  final kind = libraryKind ?? kindFromType;

  final filters = <LibraryFilter>[
    ...clauses,
    // Multi-value `type` can't fold into `kind`; keep it as a clause.
    if (typeRaw != null && typeRaw.contains(',')) LibraryFilter(field: 'type', values: typeRaw.split(',')),
  ];

  return LibraryQuery(
    kind: (kind == null || kind == MediaKind.unknown) ? null : kind,
    offset: offset,
    limit: limit,
    nameStartsWith: nonEmpty(alphaPrefix),
    search: nonEmpty(search),
    sort: LibraryQueryTranslator.parseSortParam(nonEmpty(sortParam)),
    filters: filters,
  );
}

