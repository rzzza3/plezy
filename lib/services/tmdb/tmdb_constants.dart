/// App-wide TMDB credentials and endpoints.
///
/// TMDB is read with one app credential rather than a per-user sign-in: the
/// v4 "API Read Access Token" from https://www.themoviedb.org/settings/api,
/// which authenticates both the v3 and v4 APIs as a bearer token. It is
/// injected at build time so it never lands in the repository:
///
/// ```
/// flutter run --dart-define=TMDB_READ_ACCESS_TOKEN=eyJ...
/// ```
///
/// A v3 "API Key" (`TMDB_API_KEY`) works as a fallback. TMDB only accepts it
/// as an `?api_key=` query parameter and only on `/3` endpoints, so the v4
/// list API is unavailable with it; [TmdbClient.getList] falls back to the
/// unpaginated `/3/list/{id}`.
///
/// Builds with neither still run; [TmdbClient.isConfigured] is false and
/// every call throws [TmdbNotConfiguredException], so callers hide TMDB
/// surfaces.
class TmdbConstants {
  TmdbConstants._();

  static const String readAccessToken = String.fromEnvironment('TMDB_READ_ACCESS_TOKEN');
  static const String apiKey = String.fromEnvironment('TMDB_API_KEY');

  static const String apiBase = 'https://api.themoviedb.org';
  static const String webBase = 'https://www.themoviedb.org';

  static const String appName = 'plezy';
  static const String appVersion = '2';

  /// Headers for every TMDB call. A read access token rides the
  /// `Authorization` header; a v3 key has no header form and goes in the
  /// query instead (request logs carry only the path, never the query).
  static Map<String, String> headers({String? token}) => {
    'Accept': 'application/json',
    'User-Agent': '$appName/$appVersion',
    if (token != null) 'Authorization': 'Bearer $token',
  };
}
