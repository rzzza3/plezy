import '../../media/media_kind.dart';
import '../../utils/json_utils.dart';
import 'tmdb_images.dart';

/// TMDB's `media_type` discriminator.
enum TmdbMediaType {
  movie('movie'),
  tv('tv'),
  person('person');

  const TmdbMediaType(this.id);

  /// The path segment / `media_type` value TMDB uses.
  final String id;

  static TmdbMediaType? fromId(Object? value) => switch (value) {
    'movie' => movie,
    'tv' => tv,
    'person' => person,
    _ => null,
  };

  MediaKind? get kind => switch (this) {
    movie => MediaKind.movie,
    tv => MediaKind.show,
    person => null,
  };
}

/// One movie, show or person from any TMDB result list (trending, popular,
/// discover, search, list items) or a details body.
///
/// Movies and shows name the same fields differently (`title` / `name`,
/// `release_date` / `first_air_date`); this normalizes them. Everything else
/// stays reachable through [raw], including `append_to_response` extras.
class TmdbMedia {
  final int id;
  final TmdbMediaType type;
  final String title;
  final String? originalTitle;
  final String? overview;
  final String? posterPath;
  final String? backdropPath;

  /// `release_date` for movies, `first_air_date` for shows.
  final DateTime? releaseDate;

  /// TMDB community rating, 0–10.
  final double? voteAverage;
  final int? voteCount;
  final double? popularity;
  final List<int> genreIds;
  final String? originalLanguage;
  final bool adult;
  final Map<String, dynamic> raw;

  const TmdbMedia({
    required this.id,
    required this.type,
    required this.title,
    this.originalTitle,
    this.overview,
    this.posterPath,
    this.backdropPath,
    this.releaseDate,
    this.voteAverage,
    this.voteCount,
    this.popularity,
    this.genreIds = const [],
    this.originalLanguage,
    this.adult = false,
    this.raw = const {},
  });

  /// Parses one entry. [fallbackType] covers endpoints whose entries carry no
  /// `media_type` (`/movie/popular`, `/tv/{id}`, ...). Returns null for an
  /// entry with no id, title or recognizable type.
  static TmdbMedia? tryParse(Map<String, dynamic> json, {TmdbMediaType? fallbackType}) {
    final id = flexibleInt(json['id']);
    final type = TmdbMediaType.fromId(json['media_type']) ?? fallbackType;
    final title = _nonEmpty(json['title']) ?? _nonEmpty(json['name']);
    if (id == null || type == null || title == null) return null;
    // Detail bodies carry full `genres`; result lists carry `genre_ids`.
    final genreIds = [
      for (final g in flexibleList(json['genre_ids']) ?? const []) ?flexibleInt(g),
      for (final g in flexibleMapList(json['genres'])) ?flexibleInt(g['id']),
    ];
    return TmdbMedia(
      id: id,
      type: type,
      title: title,
      originalTitle: _nonEmpty(json['original_title']) ?? _nonEmpty(json['original_name']),
      overview: _nonEmpty(json['overview']),
      posterPath: _nonEmpty(json['poster_path']) ?? _nonEmpty(json['profile_path']),
      backdropPath: _nonEmpty(json['backdrop_path']),
      releaseDate: DateTime.tryParse(_nonEmpty(json['release_date']) ?? _nonEmpty(json['first_air_date']) ?? ''),
      voteAverage: flexibleDouble(json['vote_average']),
      voteCount: flexibleInt(json['vote_count']),
      popularity: flexibleDouble(json['popularity']),
      genreIds: genreIds,
      originalLanguage: _nonEmpty(json['original_language']),
      adult: flexibleBool(json['adult']),
      raw: json,
    );
  }

  int? get year => releaseDate?.year;

  /// Null for people.
  MediaKind? get kind => type.kind;

  String? posterUrl([String size = 'w500']) => tmdbImageUrl(posterPath, size);

  String? backdropUrl([String size = 'w1280']) => tmdbImageUrl(backdropPath, size);

  Map<int, String>? get posterVariants => tmdbPosterVariants(posterPath);

  Map<int, String>? get backdropVariants => tmdbBackdropVariants(backdropPath);

  /// `external_ids.imdb_id` (when appended) or a movie body's own `imdb_id`.
  String? get imdbId {
    final external = raw['external_ids'];
    return _nonEmpty(external is Map ? external['imdb_id'] : null) ?? _nonEmpty(raw['imdb_id']);
  }

  /// `external_ids.tvdb_id`, only present when appended to a details call.
  int? get tvdbId {
    final external = raw['external_ids'];
    return external is Map ? flexibleInt(external['tvdb_id']) : null;
  }

  static String? _nonEmpty(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// One page of a paginated TMDB result list.
class TmdbPage<T> {
  final List<T> results;
  final int page;
  final int totalPages;
  final int totalResults;

  const TmdbPage({required this.results, this.page = 1, this.totalPages = 1, this.totalResults = 0});

  bool get hasMore => page < totalPages;

  /// Reads `results`, or a v3 list body's unpaginated `items`.
  static TmdbPage<TmdbMedia> parseMedia(Object? json, {TmdbMediaType? fallbackType}) {
    final body = json is Map ? json.cast<String, dynamic>() : const <String, dynamic>{};
    final entries = flexibleMapList(body['results'] ?? body['items']);
    return TmdbPage(
      results: [for (final entry in entries) ?TmdbMedia.tryParse(entry, fallbackType: fallbackType)],
      page: flexibleInt(body['page']) ?? 1,
      totalPages: flexibleInt(body['total_pages']) ?? 1,
      totalResults: flexibleInt(body['total_results']) ?? flexibleInt(body['item_count']) ?? entries.length,
    );
  }
}

/// A user-curated TMDB list (`/4/list/{id}`): its header plus one page of
/// mixed movie/show items.
class TmdbList {
  final int id;
  final String name;
  final String? description;
  final String? posterPath;
  final String? backdropPath;
  final TmdbPage<TmdbMedia> items;
  final Map<String, dynamic> raw;

  const TmdbList({
    required this.id,
    required this.name,
    this.description,
    this.posterPath,
    this.backdropPath,
    required this.items,
    this.raw = const {},
  });

  static TmdbList? tryParse(Object? json) {
    if (json is! Map) return null;
    final body = json.cast<String, dynamic>();
    final id = flexibleInt(body['id']);
    if (id == null) return null;
    return TmdbList(
      id: id,
      name: TmdbMedia._nonEmpty(body['name']) ?? '',
      description: TmdbMedia._nonEmpty(body['description']),
      posterPath: TmdbMedia._nonEmpty(body['poster_path']),
      backdropPath: TmdbMedia._nonEmpty(body['backdrop_path']),
      items: TmdbPage.parseMedia(body),
      raw: body,
    );
  }
}

/// A TV network or streamer (`/3/network/{id}`): Netflix, HBO, BBC One.
class TmdbNetwork {
  final int id;
  final String name;

  /// Transparent PNG wordmark, relative like every TMDB image path.
  final String? logoPath;
  final String? originCountry;

  const TmdbNetwork({required this.id, required this.name, this.logoPath, this.originCountry});

  static TmdbNetwork? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = flexibleInt(json['id']);
    final name = TmdbMedia._nonEmpty(json['name']);
    if (id == null || name == null) return null;
    return TmdbNetwork(
      id: id,
      name: name,
      logoPath: TmdbMedia._nonEmpty(json['logo_path']),
      originCountry: TmdbMedia._nonEmpty(json['origin_country']),
    );
  }

  String? logoUrl([String size = 'w300']) => tmdbImageUrl(logoPath, size);
}
