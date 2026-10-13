import '../connection/connection.dart';
import '../exceptions/media_server_exceptions.dart';
import '../i18n/strings.g.dart';
import '../media/ids.dart';
import '../media/library_filter_result.dart';
import '../media/library_query.dart';
import '../media/media_backend.dart';
import '../media/media_filter.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_library.dart';
import '../media/media_person.dart';
import '../media/media_server_client.dart';
import '../media/media_sort.dart';
import '../media/server_capabilities.dart';
import '../silo/silo_app.dart';
import '../silo/silo_catalog.dart';
import '../silo/silo_http.dart';
import '../silo/silo_mappers.dart';
import '../silo/silo_models.dart';
import '../utils/app_logger.dart';
import '../utils/media_server_http_client.dart' show AbortController;

/// A Silo server bound to one profile. Carries the identity and catalog
/// members; playback and download members throw [UnsupportedError] until the
/// step that implements them lands (S5 onwards).
class SiloClient extends MediaServerClient implements ScopedMediaServerClient {
  final SiloConnection connection;
  final String profileId;
  final SiloHttp http;
  final SiloCatalog catalog;
  late final SiloCatalogPager _browsePager = SiloCatalogPager(catalog);
  late final SiloCatalogPager _personPager = SiloCatalogPager(catalog);

  int _sessionGeneration = -1;
  Object _sessionIdentity = Object();
  bool _offline = false;

  ({int generation, DateTime at, Future<List<SiloSection>> sections})? _home;

  /// Shows and seasons this client has mapped, so [fetchChildren] knows which
  /// Silo collection an id names without another detail read.
  final Map<String, _SiloParent> _parents = {};

  SiloClient({required this.connection, required this.profileId, required this.http}) : catalog = SiloCatalog(http);

  SiloOrigin get _origin => SiloOrigin(serverId, serverName);

  /// Binds the server's session slot to [profileId]. A profile other than
  /// the one the slot holds is selected without a token; a PIN profile then
  /// needs the picker again.
  static Future<SiloClient> create(SiloConnection connection, {required String profileId}) async {
    final silo = await SiloApp.http(origin: Uri.parse(connection.origin), serverId: connection.serverId);
    final session = silo.session.session;
    if (session != null && session.profileId != profileId) await silo.session.selectProfile(profileId, null);
    return SiloClient(connection: connection, profileId: profileId, http: silo);
  }

  @override
  ServerId get serverId => ServerId(connection.serverId);

  @override
  String? get serverName => connection.serverName;

  @override
  MediaBackend get backend => MediaBackend.silo;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.silo;

  @override
  String get scopedServerId => 'silo:${connection.serverId}/$profileId';

  @override
  Object get authenticationSessionId {
    final generation = http.session.generation;
    if (generation != _sessionGeneration) {
      _sessionGeneration = generation;
      _sessionIdentity = Object();
    }
    return _sessionIdentity;
  }

  @override
  bool get isOfflineMode => _offline;

  @override
  void setOfflineMode(bool offline) => _offline = offline;

  @override
  void close() => http.close();

  /// `GET /api/v2/account/me`, the lightest call that proves the bearer.
  @override
  Future<HealthStatus> checkHealth() async {
    try {
      final response = await http.send(const SiloRequest.get('/api/v2/account/me'));
      return switch (response.statusCode) {
        200 => HealthStatus.online,
        401 => HealthStatus.authError,
        403 => HealthStatus.accessDenied,
        _ => HealthStatus.offline,
      };
    } on SiloCredentialsRepudiatedException {
      return HealthStatus.authError;
    } on Exception {
      return HealthStatus.offline;
    }
  }

  @override
  Future<String?> getMachineIdentifier() async {
    try {
      final response = await http.send(const SiloRequest.get('/api/v2/system/identity', auth: SiloAuth.none));
      final json = response.statusCode == 200 ? response.json() : null;
      final id = json is Map ? json['server_id'] : null;
      return id is String && id.trim().isNotEmpty ? id.trim() : null;
    } on Exception {
      return null;
    }
  }

  /// Home and Continue Watching are two views of one `/home/sections` read,
  /// and the home asks for both within a moment, so one read serves both.
  Future<List<SiloSection>> _homeSections() {
    final generation = catalog.generation;
    final cached = _home;
    if (cached != null &&
        cached.generation == generation &&
        DateTime.now().difference(cached.at) < const Duration(seconds: 5)) {
      return cached.sections;
    }
    final sections = catalog.homeSections().then((sections) {
      final visible = [for (final section in sections) ?siloVisibleSection(section)];
      appLogger.i('Silo: home sections ${visible.length}');
      return visible;
    });
    _home = (generation: generation, at: DateTime.now(), sections: sections);
    sections.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_home?.sections, sections)) _home = null;
      },
    );
    return sections;
  }

  void _homeChanged() => _home = null;

  static String _homeHubId(String sectionId) => 'silo-home:$sectionId';

  static String _libraryHubId(String libraryId, String sectionId) => 'silo-library:$libraryId:$sectionId';

  Future<SiloSection> _hubSection(String hubId) {
    if (hubId.startsWith('silo-home:')) return catalog.homeSectionItems(hubId.substring('silo-home:'.length));
    if (hubId.startsWith('silo-library:')) {
      final rest = hubId.substring('silo-library:'.length);
      final split = rest.indexOf(':');
      if (split > 0) return catalog.librarySectionItems(rest.substring(0, split), rest.substring(split + 1));
    }
    return Future.error(ArgumentError.value(hubId, 'hubId', 'is not a Silo hub'));
  }

  @override
  Future<List<MediaHub>> fetchGlobalHubs({
    int limit = defaultHubPreviewLimit,
    bool includePlaybackHubs = true,
    HubFetchDiagnostics? diagnostics,
  }) async => [
    for (final section in await _homeSections())
      if (includePlaybackHubs || siloSectionRole(section.sectionType) == SiloRowRole.shelf)
        _preview(siloSectionToHub(section, _origin, hubId: _homeHubId(section.id)), limit),
  ];

  MediaHub _preview(MediaHub hub, int limit) =>
      hub.items.length <= limit ? hub : hub.copyWith(items: hub.items.sublist(0, limit));

  /// Resumable rows first, then next-up rows, each in server order.
  /// [excludedLibraryIds] cannot apply: Silo home cards carry no library id
  /// and the server has no parameter to scope them.
  @override
  Future<List<MediaItem>> fetchContinueWatching({int? count = 20, Set<String> excludedLibraryIds = const {}}) async {
    final sections = await _homeSections();
    final seen = <String>{};
    final items = [
      for (final role in const [SiloRowRole.continueWatching, SiloRowRole.nextUp])
        for (final section in sections)
          if (siloSectionRole(section.sectionType) == role)
            for (final card in section.items)
              if (seen.add(card.contentId)) siloCardToItem(card, _origin),
    ];
    return count == null || items.length <= count ? items : items.sublist(0, count);
  }

  /// Featured sections are left out of a library's Recommended tab
  /// (`T/ui/screens/library/TvLibraryDetailViewModel.kt:421-520`).
  @override
  Future<List<MediaHub>> fetchLibraryHubs(
    String libraryId, {
    required String libraryName,
    int limit = defaultHubPreviewLimit,
    bool includePlaybackHubs = true,
    MediaKind? libraryKind,
    HubFetchDiagnostics? diagnostics,
  }) async => [
    for (final section in await catalog.librarySections(libraryId))
      if (!section.featured && (includePlaybackHubs || siloSectionRole(section.sectionType) == SiloRowRole.shelf))
        if (siloVisibleSection(section) case final visible?)
          _preview(siloSectionToHub(visible, _origin, hubId: _libraryHubId(libraryId, section.id)), limit),
  ];

  @override
  Future<List<MediaItem>> fetchMoreHubItems(String hubId, {int? limit}) async {
    final page = await fetchMoreHubItemsPage(hubId, start: 0, size: limit);
    return page.items;
  }

  @override
  Future<LibraryPage<MediaItem>> fetchMoreHubItemsPage(
    String hubId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    final section = siloVisibleSection(await _hubSection(hubId));
    abort?.throwIfAborted();
    final items = [for (final card in section?.items ?? const <SiloCard>[]) siloCardToItem(card, _origin)];
    return _slice(items, start, size);
  }

  LibraryPage<MediaItem> _slice(List<MediaItem> items, int? start, int? size) {
    final from = (start ?? 0).clamp(0, items.length);
    final to = size == null ? items.length : (from + size).clamp(from, items.length);
    return LibraryPage(items: items.sublist(from, to), totalCount: items.length, offset: from);
  }

  @override
  Future<List<MediaLibrary>> fetchLibraries() async => [
    for (final library in await catalog.visibleLibraries(hiddenType: isSiloHiddenType))
      siloLibraryToMedia(library, _origin),
  ];

  @override
  Future<List<MediaSort>> fetchSortOptions(String libraryId, {String? libraryType}) async => [
    MediaSort(key: 'title', descKey: 'title:desc', title: t.libraries.sortLabels.title, defaultDirection: 'asc'),
    MediaSort(
      key: 'added_at',
      descKey: 'added_at:desc',
      title: t.libraries.sortLabels.dateAdded,
      defaultDirection: 'desc',
    ),
    MediaSort(
      key: 'release_date',
      descKey: 'release_date:desc',
      title: t.libraries.sortLabels.releaseDate,
      defaultDirection: 'desc',
    ),
    MediaSort(
      key: 'year',
      descKey: 'year:desc',
      title: t.libraries.sortLabels.productionYear,
      defaultDirection: 'desc',
    ),
    MediaSort(
      key: 'rating_imdb',
      descKey: 'rating_imdb:desc',
      title: t.libraries.sortLabels.rating,
      defaultDirection: 'desc',
    ),
    MediaSort(key: 'runtime', descKey: 'runtime:desc', title: t.libraries.sortLabels.runtime, defaultDirection: 'desc'),
  ];

  /// Genre and content rating, the two facets Plezy has labels for, with
  /// their values from `GET /catalog/filters`.
  @override
  Future<LibraryFilterResult> fetchLibraryFiltersWithValues(String libraryId, {MediaKind? libraryKind}) async {
    final facets = await catalog.filters(libraryId: libraryId);
    final filters = <MediaFilter>[];
    final values = <String, List<MediaFilterValue>>{};
    for (final (field, facet, title) in [
      (MediaFilterField.genre, 'genres', t.libraries.filterCategories.genre),
      (MediaFilterField.contentRating, 'content_ratings', t.libraries.filterCategories.contentRating),
    ]) {
      final entries = facets.values[facet] ?? const [];
      if (entries.isEmpty) continue;
      filters.add(
        MediaFilter(
          filter: field,
          filterType: MediaFilterType.tag,
          key: 'silo:$field',
          title: title,
          type: 'filter',
          operators: const [LibraryFilterOperator.is_],
        ),
      );
      values[field] = [for (final value in entries) MediaFilterValue(key: value, title: value)];
    }
    return LibraryFilterResult(filters: filters, cachedValues: values);
  }

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    final page = await _browsePager.read(
      siloLibraryQuery(libraryId, query, libraryKind: libraryKind),
      offset: query.offset,
      limit: query.limit,
      abort: abort,
    );
    return LibraryPage(
      items: [for (final card in page.items) siloCardToItem(card, _origin, libraryId: libraryId)],
      totalCount: page.total,
      offset: query.offset,
    );
  }

  @override
  Future<LibraryPage<MediaItem>> fetchPersonMediaPage(
    String personId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    final offset = start ?? 0;
    final page = await _personPager.read(
      SiloCatalogQuery(source: 'person', personId: personId, sort: 'year', descending: true),
      offset: offset,
      limit: size ?? siloPageSize,
      abort: abort,
    );
    return LibraryPage(
      items: [for (final card in page.items) siloCardToItem(card, _origin)],
      totalCount: page.total,
      offset: offset,
    );
  }

  @override
  Future<MediaItem?> fetchItem(String id) async {
    try {
      return _detailItem(await catalog.itemDetail(id));
    } on MediaServerHttpException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  MediaItem _detailItem(SiloItemDetail detail) {
    _remember(detail.contentId, switch (siloKind(detail.type)) {
      MediaKind.show => _SiloSeries(title: detail.title, posterUrl: detail.posterUrl),
      MediaKind.season when detail.seriesId != null && detail.seasonNumber != null => _SiloSeasonOf(
        seriesId: detail.seriesId!,
        number: detail.seasonNumber!,
        seriesTitle: detail.seriesTitle,
      ),
      _ => null,
    });
    return siloDetailToItem(detail, _origin);
  }

  /// A show opens on the season the Silo TV app picks, and its next-up
  /// episode is the one that season offers
  /// (`S/model/catalog/CatalogModels.kt:495-531`,
  /// `T/ui/screens/detail/TvItemDetailViewModel.kt:1835-1839`).
  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(
    String id, {
    void Function(MediaItem item)? onItemReady,
  }) async {
    final item = await fetchItem(id);
    if (item == null || item.kind != MediaKind.show) return (item: item, onDeckEpisode: null);
    onItemReady?.call(item);
    try {
      final seasons = siloSeasonsForDisplay(await catalog.seriesSeasons(id));
      final season = siloInitialSeason(seasons);
      if (season == null) return (item: item, onDeckEpisode: null);
      final series = _SiloSeries(title: item.title, posterUrl: item.thumbPath);
      final next = siloNextUpEpisode(await catalog.seasonEpisodes(id, season.seasonNumber));
      return (
        item: item,
        onDeckEpisode: next == null
            ? null
            : _episodeItem(next, seriesId: id, series: series, seasonId: season.contentId),
      );
    } on MediaServerHttpException catch (error) {
      if (error.isCancellation) rethrow;
      appLogger.w('Silo: next-up read failed (${error.statusCode ?? error.type.name})');
      return (item: item, onDeckEpisode: null);
    }
  }

  void _remember(String id, _SiloParent? parent) {
    if (parent == null) return;
    if (_parents.length >= 2000) _parents.clear();
    _parents[id] = parent;
  }

  Future<_SiloParent?> _parentOf(String id) async {
    final known = _parents[id];
    if (known != null) return known;
    final item = await fetchItem(id);
    return item == null ? null : _parents[id];
  }

  MediaItem _episodeItem(
    SiloEpisode episode, {
    required String seriesId,
    required _SiloSeries series,
    String? seasonId,
  }) => siloEpisodeToItem(
    episode,
    _origin,
    seriesId: seriesId,
    seriesTitle: series.title,
    seasonId: seasonId,
    seriesPosterUrl: series.posterUrl,
  );

  Future<List<MediaItem>> _seasons(String seriesId, _SiloSeries series) async {
    final items = <MediaItem>[];
    for (final season in siloSeasonsForDisplay(await catalog.seriesSeasons(seriesId))) {
      _remember(
        season.contentId,
        _SiloSeasonOf(
          seriesId: seriesId,
          number: season.seasonNumber,
          seriesTitle: series.title,
          posterUrl: series.posterUrl,
        ),
      );
      items.add(
        siloSeasonToItem(
          season,
          _origin,
          seriesId: seriesId,
          seriesTitle: series.title,
        ).copyWith(thumbPath: season.posterUrl ?? series.posterUrl),
      );
    }
    return items;
  }

  Future<List<MediaItem>> _episodes(String seasonId, _SiloSeasonOf season) async {
    final series = _SiloSeries(title: season.seriesTitle, posterUrl: season.posterUrl);
    return [
      for (final episode in await catalog.seasonEpisodes(season.seriesId, season.number))
        _episodeItem(episode, seriesId: season.seriesId, series: series, seasonId: seasonId),
    ];
  }

  @override
  Future<List<MediaItem>> fetchChildren(String parentId) async => switch (await _parentOf(parentId)) {
    final _SiloSeries series => _seasons(parentId, series),
    final _SiloSeasonOf season => _episodes(parentId, season),
    null => const <MediaItem>[],
  };

  @override
  Future<LibraryPage<MediaItem>> fetchChildrenPage(
    String parentId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async => _slice(await fetchChildren(parentId), start, size);

  @override
  Future<List<MediaItem>> fetchPlayableDescendants(String parentId) async {
    final parent = await _parentOf(parentId);
    if (parent is _SiloSeasonOf) return _episodes(parentId, parent);
    if (parent is! _SiloSeries) return const [];
    final episodes = <MediaItem>[];
    for (final season in await _seasons(parentId, parent)) {
      episodes.addAll(await _episodes(season.id, _parents[season.id]! as _SiloSeasonOf));
    }
    return episodes;
  }

  @override
  Future<LibraryPage<MediaItem>> fetchPlayableDescendantsPage(
    String parentId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async => _slice(await fetchPlayableDescendants(parentId), start, size);

  @override
  Future<List<MediaItem>?> fetchClientSideEpisodeQueue(String seriesId) => fetchPlayableDescendants(seriesId);

  /// One page of `source=query&q=…&limit=40`, as the TV search screen reads
  /// (`T/ui/screens/search/TvSearchViewModel.kt:240-300`). [excludedLibraryIds]
  /// cannot apply: Silo search cards carry no library id.
  @override
  Future<List<MediaItem>> searchItems(
    String query, {
    int limit = 100,
    AbortController? abort,
    Set<String> excludedLibraryIds = const {},
  }) async {
    final page = await catalog.browse(SiloCatalogQuery(q: query, limit: limit.clamp(1, 40)));
    abort?.throwIfAborted();
    return [
      for (final card in page.items)
        if (!isSiloHiddenType(card.type)) siloCardToItem(card, _origin),
    ];
  }

  /// A failed lookup yields no people, and a server that does not scope people
  /// search is never asked (`S/repository/SearchPeople.kt:9-36`).
  @override
  Future<List<MediaPerson>> searchPeople(
    String query, {
    int limit = defaultPeopleSearchLimit,
    AbortController? abort,
    Set<String> excludedLibraryIds = const {},
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    try {
      if (!await catalog.peopleSearchScoped()) return const [];
      abort?.throwIfAborted();
      return [for (final person in await catalog.people(trimmed, limit: limit)) siloPersonToMedia(person, _origin)];
    } on MediaServerHttpException catch (error) {
      if (error.isCancellation) rethrow;
      return const [];
    } on FormatException {
      return const [];
    }
  }

  /// "More like this" from `GET /recommendations/similar/{id}?limit=12`, with
  /// hidden types and the item itself dropped
  /// (`T/ui/screens/detail/TvItemDetailViewModel.kt:2513-2514`).
  @override
  Future<List<MediaHub>> fetchRelatedHubs(String id, {int count = 10}) async {
    final items = [
      for (final card in await catalog.similar(id))
        if (card.contentId != id && !isSiloHiddenType(card.type)) siloCardToItem(card, _origin),
    ];
    if (items.isEmpty) return const [];
    return [
      MediaHub(
        id: 'silo-similar:$id',
        identifier: 'item.$id.similar',
        title: t.discover.moreLikeThis,
        type: 'mixed',
        items: items,
        size: items.length,
        serverId: serverId.value,
        serverName: serverName,
      ),
    ];
  }

  @override
  Future<List<MediaItem>> fetchExtras(String id) async => const [];

  @override
  Future<void> markWatched(MediaItem item) async {
    await catalog.setWatched(item.id, true);
    _homeChanged();
  }

  @override
  Future<void> markUnwatched(MediaItem item) async {
    await catalog.setWatched(item.id, false);
    _homeChanged();
  }

  /// Plezy rates 0 to 10 and Silo 1 to 5 stars. A negative rating clears it.
  @override
  Future<void> rate(MediaItem item, double rating) =>
      catalog.setRating(item.id, rating < 0 ? null : (rating / 2).round().clamp(1, 5));

  @override
  Future<void> setFavorite(MediaItem item, bool isFavorite) async {
    await catalog.setFavorite(item.id, isFavorite);
    _homeChanged();
  }

  Future<void> setWatchlisted(MediaItem item, bool listed) async {
    await catalog.setWatchlisted(item.id, listed);
    _homeChanged();
  }

  /// Silo artwork URLs are absolute and presigned, and carry no credentials.
  @override
  String thumbnailUrl(String? path, {int? width, int? height, bool cover = true}) => path ?? '';

  @override
  String externalImageUrl(String url, {int? width, int? height, bool cover = true}) => url;

  @override
  Map<String, String> get streamHeaders => const {};

  @override
  Future<MediaItem> stampLibrary(MediaItem item) async => item;

  /// Members the later steps implement fail as a rejected future, so an
  /// awaiting caller sees an ordinary error instead of a synchronous throw.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final error = UnsupportedError('SiloClient does not implement ${invocation.memberName} yet');
    if (invocation.isMethod) return Future<Never>.error(error);
    throw error;
  }
}

/// `POST /api/v2/auth/logout`, bounded, then the slot is wiped.
Future<void> signOutSiloSession(SiloHttp silo) async {
  if (silo.session.session != null) {
    try {
      final response = await silo
          .send(const SiloRequest.post('/api/v2/auth/logout', timeout: Duration(seconds: 10)))
          .timeout(const Duration(seconds: 10));
      appLogger.i('Silo: logout status ${response.statusCode}');
    } on Object catch (error) {
      // The local wipe below is what signs this device out.
      appLogger.i('Silo: logout failed (${error.runtimeType})');
    }
  }
  await silo.session.signOut();
}

Future<void> signOutSiloConnection(SiloConnection connection) async {
  final silo = await SiloApp.http(origin: Uri.parse(connection.origin), serverId: connection.serverId);
  try {
    await signOutSiloSession(silo);
  } finally {
    silo.close();
  }
}

sealed class _SiloParent {}

class _SiloSeries extends _SiloParent {
  final String? title;
  final String? posterUrl;

  _SiloSeries({this.title, this.posterUrl});
}

class _SiloSeasonOf extends _SiloParent {
  final String seriesId;
  final int number;
  final String? seriesTitle;
  final String? posterUrl;

  _SiloSeasonOf({required this.seriesId, required this.number, this.seriesTitle, this.posterUrl});
}

/// Library browse as the TV Browse tab sends it: `source=query`, 100 a page,
/// Title A-Z by default, and each filter field as its own `any` rule group
/// (`T/ui/screens/library/TvLibraryBrowseFacets.kt:207-232`,
/// `S/network/api/CatalogApi.kt:25-41`).
SiloCatalogQuery siloLibraryQuery(String libraryId, LibraryQuery query, {MediaKind? libraryKind}) {
  final groups = [
    for (final filter in query.filters)
      if (_ruleFields[filter.field] case (final field, final op) when filter.values.isNotEmpty)
        SiloRuleGroup('any', [for (final value in filter.values) SiloRule(field, op, value)]),
  ];
  final sort = query.sort;
  return SiloCatalogQuery(
    libraryId: libraryId,
    type: siloCatalogTypeForKind(query.kind ?? libraryKind),
    q: query.search,
    namePrefix: query.nameStartsWith,
    match: groups.isEmpty ? null : 'all',
    groups: groups,
    sort: sort?.field ?? 'title',
    descending: sort?.direction == LibrarySortDirection.descending,
  );
}

const Map<String, (String, String)> _ruleFields = {
  MediaFilterField.genre: ('genre', 'contains'),
  MediaFilterField.contentRating: ('content_rating', 'is'),
};
