import 'package:http/http.dart' as http;

import '../../utils/json_utils.dart';
import '../trackers/tracker_http_client.dart';
import 'tmdb_constants.dart';
import 'tmdb_models.dart';

/// Thrown by every [TmdbClient] call when the build carries no TMDB token.
class TmdbNotConfiguredException implements Exception {
  const TmdbNotConfiguredException();

  @override
  String toString() => 'TmdbNotConfiguredException: build has no TMDB_READ_ACCESS_TOKEN or TMDB_API_KEY';
}

/// A non-2xx TMDB response. [statusCode] is the HTTP status; [tmdbCode] and
/// [message] come from TMDB's `{status_code, status_message}` error body.
class TmdbApiException implements Exception {
  final int statusCode;
  final int? tmdbCode;
  final String? message;

  /// Seconds TMDB asked us to wait, on a 429.
  final int? retryAfterSeconds;

  const TmdbApiException({required this.statusCode, this.tmdbCode, this.message, this.retryAfterSeconds});

  bool get isRateLimited => statusCode == 429;

  bool get isNotFound => statusCode == 404;

  @override
  String toString() => 'TmdbApiException($statusCode${tmdbCode == null ? '' : '/$tmdbCode'}): ${message ?? ''}';
}

/// `/trending` window.
enum TmdbTimeWindow { day, week }

/// `external_source` values accepted by `/find`.
enum TmdbExternalSource {
  imdb('imdb_id'),
  tvdb('tvdb_id');

  const TmdbExternalSource(this.id);

  final String id;
}

/// Read-only TMDB API client, shared app-wide (see the root `MultiProvider`
/// in `main.dart`): `context.read<TmdbClient>()`.
///
/// Authenticates with the app's build-time token, not a user account, so it
/// carries no session and needs no refresh. Typed helpers cover the common
/// browse endpoints; [get] reaches anything else under `/3` or `/4`.
class TmdbClient {
  final String _token;
  final String _apiKey;
  final TrackerHttpClient _http;

  /// TMDB `language` (e.g. `en-US`, `de-DE`) sent with every call. Null lets
  /// TMDB default to `en-US`.
  String? language;

  /// [token] and [apiKey] override the build-time credentials (tests). The
  /// token wins when both are set.
  TmdbClient({String? token, String? apiKey, this.language, http.Client? httpClient})
    : _token = token ?? TmdbConstants.readAccessToken,
      _apiKey = apiKey ?? TmdbConstants.apiKey,
      _http = TrackerHttpClient(logLabel: 'TMDB', httpClient: httpClient);

  bool get isConfigured => _token.isNotEmpty || _apiKey.isNotEmpty;

  /// Whether `/4` endpoints are reachable; a v3 key only authenticates `/3`.
  bool get supportsV4 => _token.isNotEmpty;

  void dispose() => _http.dispose();

  /// A TMDB list by id (`themoviedb.org/list/{id}`), one page of items at a
  /// time. [sortBy] is e.g. `original_order.asc`, `vote_average.desc`.
  ///
  /// With only a v3 key this reads `/3/list/{id}`, which returns every item
  /// on one page and ignores [page] and [sortBy].
  Future<TmdbList> getList(int listId, {int page = 1, String? sortBy}) async {
    final body = supportsV4
        ? await get('/4/list/$listId', query: {'page': '$page', 'sort_by': ?sortBy})
        : await get('/3/list/$listId');
    final list = TmdbList.tryParse(body);
    if (list == null) throw TmdbApiException(statusCode: 200, message: 'Malformed list $listId');
    return list;
  }

  /// [type] [TmdbMediaType.person] is valid here; null means all types.
  Future<TmdbPage<TmdbMedia>> trending({
    TmdbMediaType? type,
    TmdbTimeWindow window = TmdbTimeWindow.week,
    int page = 1,
  }) async {
    final body = await get('/3/trending/${type?.id ?? 'all'}/${window.name}', query: {'page': '$page'});
    return TmdbPage.parseMedia(body, fallbackType: type);
  }

  Future<TmdbPage<TmdbMedia>> popular(TmdbMediaType type, {int page = 1}) => _mediaList(type, 'popular', page);

  Future<TmdbPage<TmdbMedia>> topRated(TmdbMediaType type, {int page = 1}) => _mediaList(type, 'top_rated', page);

  /// Movies in theatres now.
  Future<TmdbPage<TmdbMedia>> nowPlayingMovies({int page = 1}) => _mediaList(TmdbMediaType.movie, 'now_playing', page);

  Future<TmdbPage<TmdbMedia>> upcomingMovies({int page = 1}) => _mediaList(TmdbMediaType.movie, 'upcoming', page);

  /// Shows with an episode airing in the next seven days.
  Future<TmdbPage<TmdbMedia>> onTheAirShows({int page = 1}) => _mediaList(TmdbMediaType.tv, 'on_the_air', page);

  /// `/discover/{movie|tv}` with TMDB's filter params passed through
  /// verbatim, e.g. `{'with_genres': '16', 'sort_by': 'popularity.desc'}`.
  Future<TmdbPage<TmdbMedia>> discover(
    TmdbMediaType type, {
    Map<String, String> filters = const {},
    int page = 1,
  }) async {
    final body = await get('/3/discover/${type.id}', query: {...filters, 'page': '$page'});
    return TmdbPage.parseMedia(body, fallbackType: type);
  }

  /// Multi search across movies, shows and people.
  Future<TmdbPage<TmdbMedia>> search(String query, {int page = 1, bool includeAdult = false}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const TmdbPage(results: []);
    final body = await get(
      '/3/search/multi',
      query: {'query': trimmed, 'page': '$page', 'include_adult': '$includeAdult'},
    );
    return TmdbPage.parseMedia(body);
  }

  /// Movie or show details. [append] adds sub-resources to the same request
  /// (`credits`, `videos`, `external_ids`, `recommendations`, ...); their
  /// bodies land in [TmdbMedia.raw] under the same keys.
  Future<TmdbMedia> details(TmdbMediaType type, int id, {List<String> append = const ['external_ids']}) async {
    if (type == TmdbMediaType.person) throw ArgumentError('Use get(\'/3/person/$id\') for people');
    final body = await get('/3/${type.id}/$id', query: {if (append.isNotEmpty) 'append_to_response': append.join(',')});
    final media = body is Map ? TmdbMedia.tryParse(body.cast<String, dynamic>(), fallbackType: type) : null;
    if (media == null) throw TmdbApiException(statusCode: 200, message: 'Malformed ${type.id} $id');
    return media;
  }

  Future<TmdbPage<TmdbMedia>> recommendations(TmdbMediaType type, int id, {int page = 1}) async {
    final body = await get('/3/${type.id}/$id/recommendations', query: {'page': '$page'});
    return TmdbPage.parseMedia(body, fallbackType: type);
  }

  /// A network's name and logo. Shows on it are
  /// `discover(TmdbMediaType.tv, filters: {'with_networks': '$id'})`.
  Future<TmdbNetwork> network(int id) async {
    final network = TmdbNetwork.tryParse(await get('/3/network/$id'));
    if (network == null) throw TmdbApiException(statusCode: 200, message: 'Malformed network $id');
    return network;
  }

  /// Movies and shows matching an IMDb or TVDB id — the bridge from a
  /// library item's external ids to TMDB.
  Future<List<TmdbMedia>> findByExternalId(String externalId, TmdbExternalSource source) async {
    final body = await get('/3/find/$externalId', query: {'external_source': source.id});
    final map = body is Map ? body : const {};
    return [
      for (final entry in flexibleMapList(map['movie_results']))
        ?TmdbMedia.tryParse(entry, fallbackType: TmdbMediaType.movie),
      for (final entry in flexibleMapList(map['tv_results']))
        ?TmdbMedia.tryParse(entry, fallbackType: TmdbMediaType.tv),
    ];
  }

  /// Raw GET against any TMDB path, version prefix included (`/3/...`,
  /// `/4/...`). Returns the decoded JSON body. [language] is added unless
  /// [query] sets its own.
  Future<dynamic> get(String path, {Map<String, String> query = const {}}) async {
    if (!isConfigured) throw const TmdbNotConfiguredException();
    final uri = Uri.parse(
      '${TmdbConstants.apiBase}$path',
    ).replace(queryParameters: {'language': ?language, ...query, if (!supportsV4) 'api_key': _apiKey});
    final res = await _http.send(
      'GET',
      uri,
      headers: TmdbConstants.headers(token: supportsV4 ? _token : null),
      allowedMethods: const {'GET'},
    );
    final body = TrackerHttpClient.decodeJson(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    final error = body is Map ? body : const {};
    throw TmdbApiException(
      statusCode: res.statusCode,
      tmdbCode: flexibleInt(error['status_code']),
      message: error['status_message']?.toString(),
      retryAfterSeconds: int.tryParse(res.headers['retry-after'] ?? ''),
    );
  }

  Future<TmdbPage<TmdbMedia>> _mediaList(TmdbMediaType type, String list, int page) async {
    final body = await get('/3/${type.id}/$list', query: {'page': '$page'});
    return TmdbPage.parseMedia(body, fallbackType: type);
  }
}
