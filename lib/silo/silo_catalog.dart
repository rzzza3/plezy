import 'dart:async';
import 'dart:convert';

import '../exceptions/media_server_exceptions.dart';
import '../utils/media_server_http_client.dart' show AbortController;
import '../utils/serial_future_queue.dart';
import 'silo_http.dart';
import 'silo_models.dart';

/// One catalog rule, `S/network/apiv2/CatalogV2Models.kt:37-38`.
class SiloRule {
  final String field;
  final String op;
  final Object value;

  const SiloRule(this.field, this.op, this.value);

  Map<String, Object?> toJson() => {'field': field, 'op': op, 'value': value};
}

class SiloRuleGroup {
  final String match;
  final List<SiloRule> rules;

  const SiloRuleGroup(this.match, this.rules);

  Map<String, Object?> toJson() => {
    'match': match,
    'rules': [for (final rule in rules) rule.toJson()],
  };
}

/// `CatalogQueryV2`, `S/network/apiv2/CatalogV2Models.kt:11-31`. The same
/// query goes out on every page; only the cursor changes.
class SiloCatalogQuery {
  final String source;
  final String? libraryId;
  final String? personId;
  final String? type;
  final String? q;
  final String? namePrefix;
  final String? match;
  final List<SiloRuleGroup> groups;
  final String? sort;
  final bool descending;
  final int limit;

  const SiloCatalogQuery({
    this.source = 'query',
    this.libraryId,
    this.personId,
    this.type,
    this.q,
    this.namePrefix,
    this.match,
    this.groups = const [],
    this.sort,
    this.descending = false,
    this.limit = siloPageSize,
  }) : assert(limit >= 1 && limit <= siloPageSize);

  /// Any rule group forces `POST /catalog/query` (`S/network/apiv2/CatalogV2Api.kt:35`).
  bool get usesPost => groups.isNotEmpty;

  /// GET parameters in `S/network/apiv2/CatalogV2Api.kt:49-65` order.
  /// Descending goes out as `sort=-field`.
  Map<String, String> toQueryParameters({String? cursor}) => {
    'source': source,
    'library_id': ?libraryId,
    'person_id': ?personId,
    'type': ?type,
    'q': ?q,
    'name_prefix': ?namePrefix,
    'match': ?match,
    'skip_total': 'false',
    'limit': '$limit',
    if (sort != null) 'sort': descending ? '-$sort' : sort!,
    'cursor': ?cursor,
  };

  /// The POST body as SiloJson writes it: defaults encoded, nulls dropped.
  Map<String, Object?> toBody({String? cursor}) => {
    'source': source,
    'library_id': ?libraryId,
    'person_id': ?personId,
    'type': ?type,
    'q': ?q,
    'name_prefix': ?namePrefix,
    'match': ?match,
    'groups': [for (final group in groups) group.toJson()],
    'sort': ?sort,
    if (sort != null) 'order': descending ? 'desc' : 'asc',
    'skip_total': false,
    'limit': limit,
    'cursor': ?cursor,
  };

  String get requestKey => '${usesPost ? 'POST' : 'GET'}/catalog:${jsonEncode(toBody())}';
}

/// Silo caps a catalog page at 100 (`S/network/apiv2/CatalogV2Api.kt:34`), and
/// the TV browses libraries at that size.
const int siloPageSize = 100;

/// The cursor chain broke: a server `invalid_cursor`, or `has_more` with a
/// missing or already seen `next_cursor`. The query has to start over.
class SiloInvalidCursorException implements Exception {
  const SiloInvalidCursorException();

  @override
  String toString() => 'SiloInvalidCursorException';
}

/// The server, account or profile changed while a read was in flight, so its
/// result belongs to someone else. Reads as a cancellation, never as empty.
MediaServerHttpException siloIdentityMoved() =>
    MediaServerHttpException(type: MediaServerHttpErrorType.cancelled, message: 'Silo identity changed');

/// The catalog, library and user-state calls of `research/silo-catalog.md`.
/// Every read is fenced by the session generation
/// (`S/repository/CatalogRepository.kt:398-405`).
class SiloCatalog {
  final SiloHttp http;

  SiloCatalog(this.http);

  int get generation => http.session.generation;

  Future<Object?> _read(SiloRequest request) async {
    final generation = this.generation;
    final SiloResponse response;
    try {
      response = await http.send(request);
    } on MediaServerException {
      rethrow;
    } on Exception catch (error) {
      throw MediaServerHttpException.from(error, uri: http.origin.resolve(request.path));
    }
    if (this.generation != generation) throw siloIdentityMoved();
    if (!response.isSuccess) throw _failure(response);
    try {
      return response.json();
    } on FormatException {
      throw const SiloDecodeException('body');
    }
  }

  Future<void> _write(String method, String path, {Object? body}) async {
    final generation = this.generation;
    final SiloResponse response;
    try {
      response = await http.send(SiloRequest(method, path, body: body, single: true));
    } on Exception catch (error) {
      throw MediaServerHttpException.from(error, uri: http.origin.resolve(path));
    }
    if (this.generation != generation) throw siloIdentityMoved();
    if (response.statusCode != 204) throw _failure(response);
  }

  MediaServerHttpException _failure(SiloResponse response) {
    final code = response.problem?.code;
    return MediaServerHttpException(
      type: MediaServerHttpErrorType.unknown,
      statusCode: response.statusCode,
      message: code ?? 'HTTP ${response.statusCode}',
      responseData: code,
      requestUri: response.url.replace(query: ''),
    );
  }

  /// `GET /home/sections`, hydrated (`S/network/apiv2/HomeSectionsV2Api.kt:13-23`).
  Future<List<SiloSection>> homeSections() async {
    final sections = SiloSection.listFromJson(await _read(const SiloRequest.get('/api/v2/home/sections')));
    return hydrateSiloSections(sections, homeSectionItems);
  }

  /// `GET /home/sections/{id}/items`. The section that comes back must be the
  /// one asked for (`S/network/apiv2/HomeSectionsV2Api.kt:46-55`).
  Future<SiloSection> homeSectionItems(String id) async =>
      _sameSection(id, await _read(SiloRequest.get('/api/v2/home/sections/${Uri.encodeComponent(id)}/items')));

  /// `GET /library/{id}/sections`, hydrated through
  /// `/library/{id}/sections/{sectionId}/items`
  /// (`S/network/apiv2/LibrarySectionItemsV2Api.kt:13-30`).
  Future<List<SiloSection>> librarySections(String libraryId) async {
    final library = Uri.encodeComponent(libraryId);
    final sections = SiloSection.listFromJson(await _read(SiloRequest.get('/api/v2/library/$library/sections')));
    return hydrateSiloSections(sections, (id) => librarySectionItems(libraryId, id));
  }

  Future<SiloSection> librarySectionItems(String libraryId, String sectionId) async => _sameSection(
    sectionId,
    await _read(
      SiloRequest.get(
        '/api/v2/library/${Uri.encodeComponent(libraryId)}/sections/${Uri.encodeComponent(sectionId)}/items',
      ),
    ),
  );

  SiloSection _sameSection(String id, Object? json) {
    final section = SiloSection.fromJson(siloObject(json, 'section'));
    if (section.id != id) throw const SiloDecodeException('id');
    return section;
  }

  /// `/user/libraries` and the hidden-library setting in parallel, then the
  /// hidden ids and the types the TV cannot open are dropped
  /// (`T/ui/screens/libraries/TvLibrariesViewModel.kt:73,104-106`).
  Future<List<SiloLibrary>> visibleLibraries({bool Function(String type)? hiddenType}) async {
    final results = await Future.wait([userLibraries(), hiddenLibraryIds()]);
    final libraries = results[0] as List<SiloLibrary>;
    final hidden = results[1] as Set<String>;
    return [
      for (final library in libraries)
        if (!hidden.contains(library.id) && !(hiddenType?.call(library.type) ?? false)) library,
    ];
  }

  /// `GET /user/libraries`. Duplicate ids and a continuation are refused
  /// (`S/network/apiv2/UserLibrariesV2.kt:7-24`).
  Future<List<SiloLibrary>> userLibraries() async {
    final libraries = [
      for (final json in siloCompleteItems(await _read(const SiloRequest.get('/api/v2/user/libraries'))))
        SiloLibrary.fromJson(json),
    ];
    if ({for (final library in libraries) library.id}.length != libraries.length) {
      throw const SiloDecodeException('id');
    }
    return libraries;
  }

  /// `ui.disabled_library_ids` from `GET /settings/values/effective`
  /// (`S/network/apiv2/SettingsV2Api.kt:50-67`).
  Future<Set<String>> hiddenLibraryIds() async {
    final json = siloObject(
      await _read(
        const SiloRequest.get('/api/v2/settings/values/effective', query: {'keys': 'ui.disabled_library_ids'}),
      ),
      'settings',
    );
    final items = json['items'];
    if (items is! List) return const {};
    for (final item in items) {
      if (item is Map && item['key'] == 'ui.disabled_library_ids') return parseSiloLibraryIds(item['value']);
    }
    return const {};
  }

  /// `GET /catalog` or, with rule groups, `POST /catalog/query`
  /// (`S/network/apiv2/CatalogV2Api.kt:29-82`).
  Future<SiloCatalogPage> browse(SiloCatalogQuery query, {String? cursor}) async {
    final request = query.usesPost
        ? SiloRequest('POST', '/api/v2/catalog/query', body: query.toBody(cursor: cursor))
        : SiloRequest.get('/api/v2/catalog', query: query.toQueryParameters(cursor: cursor));
    try {
      return SiloCatalogPage.fromJson(await _read(request));
    } on MediaServerHttpException catch (error) {
      if (error.responseData == 'invalid_cursor') throw const SiloInvalidCursorException();
      rethrow;
    }
  }

  /// `GET /catalog/filters` for one library, technical facets included as the
  /// TV Browse tab asks (`T/ui/screens/library/TvLibraryDetailViewModel.kt:529-600`).
  Future<SiloFilterFacets> filters({String? libraryId}) async => SiloFilterFacets.fromJson(
    await _read(
      SiloRequest.get('/api/v2/catalog/filters', query: {'library_id': ?libraryId, 'skip_technical': 'false'}),
    ),
  );

  Future<SiloItemDetail> itemDetail(String id) async =>
      SiloItemDetail.fromJson(await _read(SiloRequest.get('/api/v2/catalog/items/${Uri.encodeComponent(id)}')));

  Future<List<SiloSeason>> seriesSeasons(String seriesId) async => [
    for (final json in siloCompleteItems(
      await _read(SiloRequest.get('/api/v2/catalog/series/${Uri.encodeComponent(seriesId)}/seasons')),
    ))
      SiloSeason.fromJson(json),
  ];

  Future<List<SiloEpisode>> seasonEpisodes(String seriesId, int seasonNumber) async => [
    for (final json in siloCompleteItems(
      await _read(
        SiloRequest.get('/api/v2/catalog/series/${Uri.encodeComponent(seriesId)}/seasons/$seasonNumber/episodes'),
      ),
    ))
      SiloEpisode.fromJson(json),
  ];

  /// `GET /catalog/search/capabilities`; people search runs only when the
  /// server scopes it (`S/repository/SearchPeople.kt:23-36`).
  Future<bool> peopleSearchScoped() async {
    final json = siloObject(await _read(const SiloRequest.get('/api/v2/catalog/search/capabilities')), 'capabilities');
    return json['people_media_scope'] == true;
  }

  /// People in [mediaScope] only. The TV's All search asks `video`, so ebook
  /// and audiobook authors stay out (`T/ui/screens/search/TvSearchViewModel.kt:42-47`).
  Future<List<SiloPerson>> people(String q, {String mediaScope = 'video', int limit = 20}) async => [
    for (final json in siloCompleteItems(
      await _read(
        SiloRequest.get(
          '/api/v2/catalog/people',
          query: {'q': q, 'limit': '${limit.clamp(1, 100)}', 'media_scope': mediaScope},
        ),
      ),
    ))
      SiloPerson.fromJson(json),
  ];

  /// `GET /recommendations/similar/{id}`, at most [limit] unique cards
  /// (`S/network/apiv2/SimilarCardsV2Api.kt:15-28`).
  Future<List<SiloCard>> similar(String id, {int limit = 12}) async {
    final cards = [
      for (final json in siloCompleteItems(
        await _read(
          SiloRequest.get('/api/v2/recommendations/similar/${Uri.encodeComponent(id)}', query: {'limit': '$limit'}),
        ),
      ))
        SiloCard.fromJson(json),
    ];
    if (cards.length > limit || {for (final card in cards) card.contentId}.length != cards.length) {
      throw const SiloDecodeException('items');
    }
    return cards;
  }

  /// `POST`/`DELETE /watched/{id}`, single attempt, 204
  /// (`S/repository/port/PersonalWrite.kt:17-21`).
  Future<void> setWatched(String id, bool watched) =>
      _write(watched ? 'POST' : 'DELETE', '/api/v2/watched/${Uri.encodeComponent(id)}');

  /// `PUT /ratings/{id}` with 1..5, or `DELETE` for null
  /// (`S/repository/port/PersonalWrite.kt:23-30`).
  Future<void> setRating(String id, int? stars) {
    assert(stars == null || (stars >= 1 && stars <= 5));
    final path = '/api/v2/ratings/${Uri.encodeComponent(id)}';
    return stars == null ? _write('DELETE', path) : _write('PUT', path, body: {'rating': stars});
  }

  /// `PUT`/`DELETE /favorites/{id}` (`S/network/apiv2/MembershipV2Api.kt:41-54`).
  Future<void> setFavorite(String id, bool favorite) =>
      _write(favorite ? 'PUT' : 'DELETE', '/api/v2/favorites/${Uri.encodeComponent(id)}');

  /// `PUT`/`DELETE /watchlist/{id}` (`S/network/apiv2/MembershipV2Api.kt:27-28,41-54`).
  Future<void> setWatchlisted(String id, bool listed) =>
      _write(listed ? 'PUT' : 'DELETE', '/api/v2/watchlist/${Uri.encodeComponent(id)}');

  /// `PUT /home/dismissals/{surface}/{itemId}` with the card's anchor, single
  /// attempt, 204 (`S/network/apiv2/HomeSectionsV2Api.kt:28-39`).
  Future<void> dismissHomeItem(String surface, String itemId, String anchor) => _write(
    'PUT',
    '/api/v2/home/dismissals/$surface/${Uri.encodeComponent(itemId)}',
    body: {surface == 'continue_watching' ? 'progress_updated_at' : 'series_id': anchor},
  );
}

/// Sections with empty `items` and `total_count > 0` read their `/items`, at
/// most four at once. Rows still empty, or whose read failed, are dropped
/// (`S/viewmodel/HomeSectionHydrator.kt:22-55`).
Future<List<SiloSection>> hydrateSiloSections(
  List<SiloSection> sections,
  Future<SiloSection> Function(String id) fetchItems, {
  int maxConcurrency = 4,
}) async {
  final unresolved = [
    for (final section in sections)
      if (section.items.isEmpty && section.totalCount > 0) section,
  ];
  final fetched = <String, SiloSection?>{};
  var next = 0;
  Future<void> worker() async {
    while (next < unresolved.length) {
      final section = unresolved[next++];
      try {
        fetched[section.id] = await fetchItems(section.id);
      } on MediaServerHttpException catch (error) {
        if (error.isCancellation) rethrow;
        fetched[section.id] = null;
      } on FormatException {
        fetched[section.id] = null;
      }
    }
  }

  await Future.wait([for (var i = 0; i < maxConcurrency && i < unresolved.length; i++) worker()]);
  return [
    for (final section in sections)
      if (section.items.isNotEmpty)
        section
      else if (fetched[section.id]?.items.isNotEmpty ?? false)
        fetched[section.id]!,
  ];
}

/// `ui.disabled_library_ids` is a JSON array of positive whole numbers, or a
/// JSON string holding one. Anything else is dropped
/// (`S/repository/HiddenLibrariesStore.kt:94-111`).
Set<String> parseSiloLibraryIds(Object? value) {
  Object? array = value;
  if (value is String && value.trim().isNotEmpty) {
    try {
      array = jsonDecode(value);
    } on FormatException {
      return const {};
    }
  }
  if (array is! List) return const {};
  return {
    for (final entry in array)
      if (entry is num && entry >= 1 && entry <= 0x7fffffff && entry == entry.roundToDouble()) '${entry.toInt()}',
  };
}

/// Plezy pages by offset; Silo pages by cursor and has no offset. The pager
/// keeps the pages of the last query it ran, so a later offset is served from
/// them or from the cursor after them, without re-reading earlier pages.
class SiloCatalogPager {
  final SiloCatalog catalog;
  final SerialFutureQueue _queue = SerialFutureQueue();

  String? _key;
  final List<SiloCard> _loaded = [];
  final Set<String> _seenCursors = {};
  String? _nextCursor;
  bool _hasMore = true;
  int _total = 0;

  SiloCatalogPager(this.catalog);

  Future<({List<SiloCard> items, int total})> read(
    SiloCatalogQuery query, {
    required int offset,
    required int limit,
    AbortController? abort,
  }) => _queue.run(() async {
    final key = '${catalog.generation}|${query.requestKey}';
    if (key != _key) _reset(key);
    try {
      await _fill(query, offset + limit, abort);
    } on SiloInvalidCursorException {
      _reset(key);
      await _fill(query, offset + limit, abort);
    }
    final end = (offset + limit).clamp(0, _loaded.length);
    final start = offset.clamp(0, end);
    return (items: _loaded.sublist(start, end), total: _hasMore ? _total : _loaded.length);
  });

  void _reset(String key) {
    _key = key;
    _loaded.clear();
    _seenCursors.clear();
    _nextCursor = null;
    _hasMore = true;
    _total = 0;
  }

  /// `S/network/apiv2/CatalogV2Api.kt:208-213`: `has_more` with a missing or
  /// repeated `next_cursor` is a broken chain.
  Future<void> _fill(SiloCatalogQuery query, int wanted, AbortController? abort) async {
    while (_loaded.length < wanted && _hasMore) {
      abort?.throwIfAborted();
      final page = await catalog.browse(query, cursor: _nextCursor);
      abort?.throwIfAborted();
      final cursor = page.nextCursor;
      if (page.hasMore && (cursor == null || !_seenCursors.add(cursor))) throw const SiloInvalidCursorException();
      _loaded.addAll(page.items);
      _total = page.total;
      _hasMore = page.hasMore;
      _nextCursor = cursor;
    }
  }
}
