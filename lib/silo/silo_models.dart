/// Silo catalog wire shapes, parsed once at the boundary. Field names follow
/// `docs/silo-migration/research/silo-catalog.md` "Domain models". Unknown
/// keys are ignored, as SiloJson does. Enum-like values (`type`,
/// `section_type`) stay raw strings because the server treats them as open.
library;

/// A required field was missing or had the wrong JSON type. The message names
/// the field only, never a value, so it is safe to log.
class SiloDecodeException extends FormatException {
  const SiloDecodeException(String field) : super('Silo response field "$field" is missing or malformed');
}

typedef SiloJson = Map<String, Object?>;

SiloJson siloObject(Object? json, String field) =>
    json is Map<String, Object?> ? json : throw SiloDecodeException(field);

List<SiloJson> siloObjectList(Object? json, String field) {
  if (json is! List) throw SiloDecodeException(field);
  return [for (final entry in json) siloObject(entry, field)];
}

String _required(SiloJson json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) return value;
  throw SiloDecodeException(key);
}

String? _string(SiloJson json, String key) {
  final value = json[key];
  return value is String && value.isNotEmpty ? value : null;
}

int? _int(SiloJson json, String key) {
  final value = json[key];
  return value is num && value == value.roundToDouble() ? value.toInt() : null;
}

double? _double(SiloJson json, String key) {
  final value = json[key];
  return value is num ? value.toDouble() : null;
}

bool _bool(SiloJson json, String key) => json[key] == true;

List<String> _strings(SiloJson json, String key) {
  final value = json[key];
  return value is List
      ? [
          for (final entry in value)
            if (entry is String && entry.isNotEmpty) entry,
        ]
      : const [];
}

/// Library, person and file ids are decimal strings on the wire, and Silo
/// rejects JSON numbers (`S/network/apiv2/ApiV2Call.kt:142-146`).
String _decimalId(SiloJson json, String key) {
  final value = _required(json, key);
  final parsed = int.tryParse(value);
  if (parsed == null || parsed <= 0) throw SiloDecodeException(key);
  return value;
}

/// `MediaItemUserState`, `S/model/catalog/CatalogModels.kt:23-31`.
class SiloUserState {
  final bool played;
  final bool isFavorite;
  final bool inWatchlist;

  const SiloUserState({this.played = false, this.isFavorite = false, this.inWatchlist = false});

  factory SiloUserState.fromJson(SiloJson json) => SiloUserState(
    played: _bool(json, 'played'),
    isFavorite: _bool(json, 'is_favorite'),
    inWatchlist: _bool(json, 'in_watchlist'),
  );
}

/// A home or library shelf card (`SectionItem`) or a catalog grid card
/// (`BrowseItem`), `S/model/section/SectionModels.kt:8-42` and
/// `S/model/catalog/CatalogModels.kt:52-91`. The TV treats them as one shape.
class SiloCard {
  final String contentId;
  final String type;
  final String title;
  final String? seriesId;
  final String? seriesTitle;
  final int? seasonNumber;
  final int? episodeNumber;
  final int? year;
  final List<String> genres;
  final String? contentRating;
  final int? runtimeMinutes;
  final String? overview;
  final List<String> studios;
  final double? ratingImdb;
  final double? ratingTmdb;
  final int? ratingRtCritic;
  final int? ratingRtAudience;
  final double? positionSeconds;
  final double? durationSeconds;
  final String? progressUpdatedAt;
  final String? addedAt;
  final String? releaseDate;
  final String? posterUrl;
  final String? backdropUrl;
  final String? logoUrl;
  final SiloUserState userState;

  const SiloCard({
    required this.contentId,
    required this.type,
    required this.title,
    this.seriesId,
    this.seriesTitle,
    this.seasonNumber,
    this.episodeNumber,
    this.year,
    this.genres = const [],
    this.contentRating,
    this.runtimeMinutes,
    this.overview,
    this.studios = const [],
    this.ratingImdb,
    this.ratingTmdb,
    this.ratingRtCritic,
    this.ratingRtAudience,
    this.positionSeconds,
    this.durationSeconds,
    this.progressUpdatedAt,
    this.addedAt,
    this.releaseDate,
    this.posterUrl,
    this.backdropUrl,
    this.logoUrl,
    this.userState = const SiloUserState(),
  });

  factory SiloCard.fromJson(SiloJson json) {
    final userState = json['user_state'];
    final year = _int(json, 'year');
    return SiloCard(
      contentId: _required(json, 'content_id'),
      type: json['type'] is String ? json['type'] as String : throw const SiloDecodeException('type'),
      title: json['title'] is String ? json['title'] as String : throw const SiloDecodeException('title'),
      seriesId: _string(json, 'series_id'),
      seriesTitle: _string(json, 'series_title'),
      seasonNumber: _int(json, 'season_number'),
      episodeNumber: _int(json, 'episode_number'),
      year: year == null || year <= 0 ? null : year,
      genres: _strings(json, 'genres'),
      contentRating: _string(json, 'content_rating'),
      runtimeMinutes: _int(json, 'runtime'),
      overview: _string(json, 'overview'),
      studios: _strings(json, 'studios'),
      ratingImdb: _double(json, 'rating_imdb'),
      ratingTmdb: _double(json, 'rating_tmdb'),
      ratingRtCritic: _int(json, 'rating_rt_critic'),
      ratingRtAudience: _int(json, 'rating_rt_audience'),
      positionSeconds: _double(json, 'position_seconds'),
      durationSeconds: _double(json, 'duration_seconds'),
      progressUpdatedAt: _string(json, 'progress_updated_at'),
      addedAt: _string(json, 'added_at'),
      releaseDate: _string(json, 'release_date'),
      posterUrl: _string(json, 'poster_url'),
      backdropUrl: _string(json, 'backdrop_url'),
      logoUrl: _string(json, 'logo_url'),
      userState: userState is Map<String, Object?> ? SiloUserState.fromJson(userState) : const SiloUserState(),
    );
  }
}

/// `ResolvedSection`, `S/model/section/SectionModels.kt:44-58`. A row
/// without an `items` array or a non-blank `id` rejects the whole response,
/// as `S/network/apiv2/HomeSectionsV2Api.kt:41-44` does.
class SiloSection {
  final String id;
  final String sectionType;
  final String title;
  final bool featured;
  final int totalCount;
  final List<SiloCard> items;

  const SiloSection({
    required this.id,
    required this.sectionType,
    required this.title,
    this.featured = false,
    this.totalCount = 0,
    required this.items,
  });

  factory SiloSection.fromJson(SiloJson json) => SiloSection(
    id: _required(json, 'id'),
    sectionType: json['section_type'] is String ? json['section_type'] as String : '',
    title: json['title'] is String ? json['title'] as String : '',
    featured: _bool(json, 'featured'),
    totalCount: _int(json, 'total_count') ?? 0,
    items: [for (final item in siloObjectList(json['items'], 'items')) SiloCard.fromJson(item)],
  );

  SiloSection withItems(List<SiloCard> items) => SiloSection(
    id: id,
    sectionType: sectionType,
    title: title,
    featured: featured,
    totalCount: totalCount,
    items: items,
  );

  static List<SiloSection> listFromJson(Object? json) => [
    for (final section in siloObjectList(siloObject(json, 'sections')['sections'], 'sections'))
      SiloSection.fromJson(section),
  ];
}

/// `UserLibrary`, `S/model/personal/PersonalDataModels.kt:102-109`.
class SiloLibrary {
  final String id;
  final String name;
  final String type;
  final int sortOrder;

  const SiloLibrary({required this.id, required this.name, required this.type, this.sortOrder = 0});

  factory SiloLibrary.fromJson(SiloJson json) => SiloLibrary(
    id: _decimalId(json, 'id'),
    name: json['name'] is String ? json['name'] as String : '',
    type: json['type'] is String ? json['type'] as String : '',
    sortOrder: _int(json, 'sort_order') ?? 0,
  );
}

/// `CatalogPage` with its `page` continuation,
/// `S/network/apiv2/CatalogV2Models.kt:61-89`.
class SiloCatalogPage {
  final List<SiloCard> items;
  final int total;
  final bool hasMore;
  final String? nextCursor;

  const SiloCatalogPage({required this.items, required this.total, required this.hasMore, this.nextCursor});

  factory SiloCatalogPage.fromJson(Object? json) {
    final body = siloObject(json, 'catalog');
    final page = siloObject(body['page'], 'page');
    return SiloCatalogPage(
      items: [for (final item in siloObjectList(body['items'], 'items')) SiloCard.fromJson(item)],
      total: _int(body, 'total') ?? 0,
      hasMore: _bool(page, 'has_more'),
      nextCursor: _string(page, 'next_cursor'),
    );
  }
}

/// `CastMember` and `CrewMember`, `S/model/catalog/CatalogModels.kt:288-313`.
/// [role] is the cast `character` or the crew `job`.
class SiloCredit {
  final String name;
  final String? role;
  final String? personId;
  final String? photoUrl;

  const SiloCredit({required this.name, this.role, this.personId, this.photoUrl});

  factory SiloCredit.fromJson(SiloJson json, {required String roleKey}) => SiloCredit(
    name: json['name'] is String ? json['name'] as String : '',
    role: _string(json, roleKey),
    personId: _string(json, 'person_id'),
    photoUrl: _string(json, 'photo_url'),
  );
}

/// `LeafItemUserData`, `S/network/apiv2/CatalogDetailReadV2Models.kt:242-264`.
class SiloLeafUserData {
  final bool played;
  final bool isInProgress;
  final double? positionSeconds;
  final double? durationSeconds;

  const SiloLeafUserData({this.played = false, this.isInProgress = false, this.positionSeconds, this.durationSeconds});

  static SiloLeafUserData? tryFromJson(Object? json) => json is Map<String, Object?>
      ? SiloLeafUserData(
          played: _bool(json, 'played'),
          isInProgress: _bool(json, 'is_in_progress'),
          positionSeconds: _double(json, 'position_seconds'),
          durationSeconds: _double(json, 'duration_seconds'),
        )
      : null;
}

/// `ItemDetail`, `S/network/apiv2/CatalogDetailReadV2Models.kt:17-81`. Only
/// the fields Plezy's detail screen shows are kept.
class SiloItemDetail {
  final String contentId;
  final String type;
  final String title;
  final String? originalTitle;
  final String? sortTitle;
  final String? overview;
  final String? tagline;
  final String? contentRating;
  final int? year;
  final int? runtimeMinutes;
  final String? releaseDate;
  final String? firstAirDate;
  final String? airDate;
  final String? seriesId;
  final String? seriesTitle;
  final int? seasonNumber;
  final int? episodeNumber;
  final int? seasonCount;
  final int? episodeCount;
  final int? userRating;
  final double? ratingImdb;
  final double? ratingTmdb;
  final int? ratingRtCritic;
  final int? ratingRtAudience;
  final List<String> genres;
  final List<String> studios;
  final List<String> countries;
  final String? posterUrl;
  final String? backdropUrl;
  final String? logoUrl;
  final List<SiloCredit> cast;
  final List<SiloCredit> crew;
  final SiloLeafUserData? userData;

  const SiloItemDetail({
    required this.contentId,
    required this.type,
    required this.title,
    this.originalTitle,
    this.sortTitle,
    this.overview,
    this.tagline,
    this.contentRating,
    this.year,
    this.runtimeMinutes,
    this.releaseDate,
    this.firstAirDate,
    this.airDate,
    this.seriesId,
    this.seriesTitle,
    this.seasonNumber,
    this.episodeNumber,
    this.seasonCount,
    this.episodeCount,
    this.userRating,
    this.ratingImdb,
    this.ratingTmdb,
    this.ratingRtCritic,
    this.ratingRtAudience,
    this.genres = const [],
    this.studios = const [],
    this.countries = const [],
    this.posterUrl,
    this.backdropUrl,
    this.logoUrl,
    this.cast = const [],
    this.crew = const [],
    this.userData,
  });

  factory SiloItemDetail.fromJson(Object? raw) {
    final json = siloObject(raw, 'item');
    final year = _int(json, 'year');
    final runtime = _int(json, 'runtime');
    return SiloItemDetail(
      contentId: _required(json, 'content_id'),
      type: _required(json, 'type'),
      title: json['title'] is String ? json['title'] as String : throw const SiloDecodeException('title'),
      originalTitle: _string(json, 'original_title'),
      sortTitle: _string(json, 'sort_title'),
      overview: _string(json, 'overview'),
      tagline: _string(json, 'tagline'),
      contentRating: _string(json, 'content_rating'),
      year: year == null || year <= 0 ? null : year,
      runtimeMinutes: runtime == null || runtime <= 0 ? null : runtime,
      releaseDate: _string(json, 'release_date'),
      firstAirDate: _string(json, 'first_air_date'),
      airDate: _string(json, 'air_date'),
      seriesId: _string(json, 'series_id'),
      seriesTitle: _string(json, 'series_title'),
      seasonNumber: _int(json, 'season_number'),
      episodeNumber: _int(json, 'episode_number'),
      seasonCount: _int(json, 'season_count'),
      episodeCount: _int(json, 'episode_count'),
      userRating: _int(json, 'user_rating'),
      ratingImdb: _double(json, 'rating_imdb'),
      ratingTmdb: _double(json, 'rating_tmdb'),
      ratingRtCritic: _int(json, 'rating_rt_critic'),
      ratingRtAudience: _int(json, 'rating_rt_audience'),
      genres: _strings(json, 'genres'),
      studios: _strings(json, 'studios'),
      countries: _strings(json, 'countries'),
      posterUrl: _string(json, 'poster_url'),
      backdropUrl: _string(json, 'backdrop_url'),
      logoUrl: _string(json, 'logo_url'),
      cast: [for (final c in siloObjectList(json['cast'], 'cast')) SiloCredit.fromJson(c, roleKey: 'character')],
      crew: [for (final c in siloObjectList(json['crew'], 'crew')) SiloCredit.fromJson(c, roleKey: 'job')],
      userData: SiloLeafUserData.tryFromJson(json['user_data']),
    );
  }
}

/// `Season` with `SeasonUserData`, `S/model/catalog/CatalogModels.kt:464-476,582-588`.
class SiloSeason {
  final String contentId;
  final int seasonNumber;
  final bool isSpecials;
  final String? title;
  final String? overview;
  final int episodeCount;
  final String? posterUrl;
  final bool played;
  final int watchedCount;
  final int inProgressCount;

  const SiloSeason({
    required this.contentId,
    required this.seasonNumber,
    this.isSpecials = false,
    this.title,
    this.overview,
    this.episodeCount = 0,
    this.posterUrl,
    this.played = false,
    this.watchedCount = 0,
    this.inProgressCount = 0,
  });

  factory SiloSeason.fromJson(SiloJson json) {
    final userData = json['user_data'];
    final user = userData is Map<String, Object?> ? userData : const <String, Object?>{};
    return SiloSeason(
      contentId: _required(json, 'content_id'),
      seasonNumber: _int(json, 'season_number') ?? (throw const SiloDecodeException('season_number')),
      isSpecials: _bool(json, 'is_specials'),
      title: _string(json, 'title'),
      overview: _string(json, 'overview'),
      episodeCount: _int(json, 'episode_count') ?? 0,
      posterUrl: _string(json, 'poster_url'),
      played: _bool(user, 'played'),
      watchedCount: _int(user, 'watched_count') ?? 0,
      inProgressCount: _int(user, 'in_progress_count') ?? 0,
    );
  }

  bool get isSpecialsForDisplay => isSpecials || seasonNumber == 0;
}

/// `EpisodeListItem`, `S/network/apiv2/CatalogDetailReadV2Models.kt:266-321`.
class SiloEpisode {
  final String contentId;
  final int seasonNumber;
  final int episodeNumber;
  final String? title;
  final String? overview;
  final String? airDate;
  final int? runtimeMinutes;
  final String? stillUrl;
  final SiloLeafUserData? userData;

  const SiloEpisode({
    required this.contentId,
    required this.seasonNumber,
    required this.episodeNumber,
    this.title,
    this.overview,
    this.airDate,
    this.runtimeMinutes,
    this.stillUrl,
    this.userData,
  });

  factory SiloEpisode.fromJson(SiloJson json) {
    final runtime = _int(json, 'runtime');
    return SiloEpisode(
      contentId: _required(json, 'content_id'),
      seasonNumber: _int(json, 'season_number') ?? (throw const SiloDecodeException('season_number')),
      episodeNumber: _int(json, 'episode_number') ?? (throw const SiloDecodeException('episode_number')),
      title: _string(json, 'title'),
      overview: _string(json, 'overview'),
      airDate: _string(json, 'air_date'),
      runtimeMinutes: runtime == null || runtime <= 0 ? null : runtime,
      stillUrl: _string(json, 'still_url'),
      userData: SiloLeafUserData.tryFromJson(json['user_data']),
    );
  }
}

/// `Person`, `S/network/apiv2/CatalogDetailReadV2Models.kt:323-354`.
class SiloPerson {
  final String id;
  final String name;
  final String? photoUrl;

  const SiloPerson({required this.id, required this.name, this.photoUrl});

  factory SiloPerson.fromJson(SiloJson json) =>
      SiloPerson(id: _decimalId(json, 'id'), name: _required(json, 'name'), photoUrl: _string(json, 'photo_url'));
}

/// The facets `GET /catalog/filters` lists, `S/network/apiv2/CatalogV2Models.kt:99-114`.
class SiloFilterFacets {
  final Map<String, List<String>> values;

  const SiloFilterFacets(this.values);

  static const List<String> keys = [
    'genres',
    'studios',
    'networks',
    'countries',
    'original_languages',
    'content_ratings',
  ];

  factory SiloFilterFacets.fromJson(Object? raw) {
    final json = siloObject(raw, 'filters');
    return SiloFilterFacets({for (final key in keys) key: _strings(json, key)});
  }
}

/// A complete detail collection (`items` with no continuation). Silo refuses
/// a partial envelope (`S/network/apiv2/CatalogV2Api.kt:198-202`).
List<Map<String, Object?>> siloCompleteItems(Object? raw) {
  final json = siloObject(raw, 'collection');
  final page = json['page'];
  if (page is Map<String, Object?> && (page['has_more'] == true || _string(page, 'next_cursor') != null)) {
    throw const SiloDecodeException('page');
  }
  return siloObjectList(json['items'], 'items');
}
