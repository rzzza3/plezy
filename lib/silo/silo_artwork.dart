const Set<String> _artworkUrlFields = {
  'poster_url',
  'backdrop_url',
  'logo_url',
  'avatar_url',
  'photo_url',
  'still_url',
  'thumbnail_url',
};

/// Resolves a server-relative artwork path against the origin of the response
/// that held it. Absolute and protocol-relative values pass through untouched,
/// so signed paths and queries are never re-encoded.
String resolveSiloArtworkUrl(String value, Uri responseUrl) {
  if (!value.startsWith('/') || value.startsWith('//')) return value;
  if (responseUrl.scheme != 'http' && responseUrl.scheme != 'https') {
    throw ArgumentError.value(responseUrl, 'responseUrl', 'must be http or https');
  }
  final host = responseUrl.host.contains(':') ? '[${responseUrl.host}]' : responseUrl.host;
  final port = responseUrl.hasPort && responseUrl.port != _defaultPort(responseUrl.scheme)
      ? ':${responseUrl.port}'
      : '';
  return '${responseUrl.scheme}://$host$port$value';
}

/// Rewrites every artwork field in decoded JSON. Runs at decode time so cached
/// JSON already holds absolute URLs and rendering never consults whichever
/// server happens to be active later.
Object? resolveSiloArtworkUrls(Object? json, Uri responseUrl) {
  if (json is Map) {
    return <String, Object?>{
      for (final entry in json.entries)
        entry.key as String: switch (entry.value) {
          final String url when _artworkUrlFields.contains(entry.key) => resolveSiloArtworkUrl(url, responseUrl),
          final List<Object?> urls when entry.key == 'poster_urls' => [
            for (final url in urls) url is String ? resolveSiloArtworkUrl(url, responseUrl) : url,
          ],
          final value => resolveSiloArtworkUrls(value, responseUrl),
        },
    };
  }
  if (json is List) return [for (final item in json) resolveSiloArtworkUrls(item, responseUrl)];
  return json;
}

int _defaultPort(String scheme) => scheme == 'https' ? 443 : 80;
