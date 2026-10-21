import '../media/ids.dart';
import '../media/media_backend.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_library.dart';
import '../media/media_person.dart';
import '../media/media_rating.dart';
import '../media/media_role.dart';
import '../media/media_source_info.dart';
import '../mpv/mpv.dart';
import '../services/playback_initialization_types.dart';
import '../services/track_selection_service.dart';
import 'silo_models.dart';
import 'silo_playback.dart';

/// How Plezy's home treats a Silo row.
enum SiloRowRole {
  /// Resumable rows. Plezy shows them as its Continue Watching row.
  continueWatching,

  /// Next-episode rows. They join Continue Watching after the resumable ones.
  nextUp,

  /// Every other row, shown as a poster shelf in server order.
  shelf,
}

/// Every `section_type` the test server returns
/// (`research/samples/home-sections.json`) plus the progress names the Silo
/// TV app tests for.
const Map<String, SiloRowRole> siloSectionRoles = {
  'continue_watching': SiloRowRole.continueWatching,
  'in_progress': SiloRowRole.continueWatching,
  'next_up': SiloRowRole.nextUp,
  'up_next': SiloRowRole.nextUp,
  'collection': SiloRowRole.shelf,
  'custom_filter': SiloRowRole.shelf,
  'favorites': SiloRowRole.shelf,
  'recently_added': SiloRowRole.shelf,
  'recently_released': SiloRowRole.shelf,
  'recommended_for_you': SiloRowRole.shelf,
  'taste_match': SiloRowRole.shelf,
  'trending_on_server': SiloRowRole.shelf,
  'watchlist': SiloRowRole.shelf,
};

/// `section_type` is an open server "recipe" name. A type missing from
/// [siloSectionRoles] gets the Silo TV substring rule
/// (`T/ui/components/TvSkylineSectionFeed.kt:1022-1034`), so any unknown type
/// still renders as a shelf.
SiloRowRole siloSectionRole(String sectionType) {
  final type = sectionType.toLowerCase();
  final known = siloSectionRoles[type];
  if (known != null) return known;
  if (type.contains('continue') || type.contains('in_progress')) return SiloRowRole.continueWatching;
  if (type.contains('next_up') || type.contains('up_next')) return SiloRowRole.nextUp;
  return SiloRowRole.shelf;
}

typedef SiloHomeDismissal = ({String surface, String itemId, String anchor});

/// Null unless the visible [card] still matches its progress row in the
/// [observed] home: the same `progress_updated_at` for continue watching, the
/// same series for next up (`S/viewmodel/HomeViewModel.kt:412-430`).
SiloHomeDismissal? siloHomeDismissal(MediaItem card, List<SiloSection> observed) {
  for (final section in observed) {
    final role = siloSectionRole(section.sectionType);
    for (final seen in section.items) {
      if (seen.contentId != card.id) continue;
      if (role == SiloRowRole.continueWatching) {
        final anchor = seen.progressUpdatedAt;
        if (anchor != null && anchor.isNotEmpty && _epochSeconds(anchor) == card.lastViewedAt) {
          return (surface: 'continue_watching', itemId: card.id, anchor: anchor);
        }
      } else if (role == SiloRowRole.nextUp) {
        final anchor = seen.seriesId;
        if (anchor != null && anchor.isNotEmpty && anchor == card.grandparentId) {
          return (surface: 'next_up', itemId: card.id, anchor: anchor);
        }
      }
    }
  }
  return null;
}

/// Types the TV hides because it has no reader
/// (`S/model/navigation/MediaMode.kt:53-62`).
const Set<String> siloHiddenTypes = {'ebook', 'ebooks', 'book', 'books', 'comic', 'comics', 'manga', 'reading'};

bool isSiloHiddenType(String type) => siloHiddenTypes.contains(type.toLowerCase());

const Map<String, MediaKind> _kindsByType = {
  'movie': MediaKind.movie,
  'series': MediaKind.show,
  'season': MediaKind.season,
  'episode': MediaKind.episode,
  'collection': MediaKind.collection,
};

MediaKind siloKind(String type) => _kindsByType[type.toLowerCase()] ?? MediaKind.unknown;

/// Library type to the catalog `type` param
/// (`T/ui/util/TvMediaTypeFilters.kt:44-49`). Null leaves the browse scoped by
/// library alone.
String? siloCatalogTypeForLibrary(String libraryType) => switch (libraryType.toLowerCase()) {
  'movie' || 'movies' => 'movie',
  'series' || 'shows' || 'tv' => 'series',
  'audiobook' || 'audiobooks' => 'audiobook',
  _ => null,
};

String? siloCatalogTypeForKind(MediaKind? kind) => switch (kind) {
  MediaKind.movie => 'movie',
  MediaKind.show => 'series',
  MediaKind.episode => 'episode',
  _ => null,
};

MediaKind _libraryKind(String type) => switch (siloCatalogTypeForLibrary(type)) {
  'movie' => MediaKind.movie,
  'series' => MediaKind.show,
  _ => MediaKind.unknown,
};

/// Where a mapped item came from, stamped on every result.
class SiloOrigin {
  final ServerId serverId;
  final String? serverName;

  const SiloOrigin(this.serverId, this.serverName);
}

int? _epochSeconds(String? timestamp) {
  final parsed = timestamp == null ? null : DateTime.tryParse(timestamp);
  return parsed == null ? null : parsed.millisecondsSinceEpoch ~/ 1000;
}

int? _ms(double? seconds) => seconds == null || seconds <= 0 ? null : (seconds * 1000).round();

int? _minutesMs(int? minutes) => minutes == null || minutes <= 0 ? null : minutes * 60000;

List<MediaRatingSource>? _ratings({double? imdb, double? tmdb, int? rtCritic, int? rtAudience}) {
  final ratings = [
    if (imdb != null && imdb > 0) MediaRatingSource(source: 'imdb', value: imdb),
    if (tmdb != null && tmdb > 0) MediaRatingSource(source: 'tmdb', value: tmdb),
    if (rtCritic != null && rtCritic > 0) MediaRatingSource(source: 'rottenTomatoesCritic', value: rtCritic / 10),
    if (rtAudience != null && rtAudience > 0)
      MediaRatingSource(source: 'rottenTomatoesAudience', value: rtAudience / 10),
  ];
  return ratings.isEmpty ? null : ratings;
}

MediaItem siloCardToItem(SiloCard card, SiloOrigin origin, {String? libraryId, String? libraryTitle}) {
  final kind = siloKind(card.type);
  final isEpisode = kind == MediaKind.episode;
  final ratings = _ratings(
    imdb: card.ratingImdb,
    tmdb: card.ratingTmdb,
    rtCritic: card.ratingRtCritic,
    rtAudience: card.ratingRtAudience,
  );
  return MediaItem.silo(
    id: card.contentId,
    kind: kind,
    title: card.title,
    summary: card.overview,
    year: card.year,
    contentRating: card.contentRating,
    studio: card.studios.firstOrNull,
    genres: card.genres,
    parentId: kind == MediaKind.season ? card.seriesId : null,
    parentTitle: kind == MediaKind.season ? card.seriesTitle : null,
    parentIndex: isEpisode ? card.seasonNumber : null,
    index: isEpisode ? card.episodeNumber : (kind == MediaKind.season ? card.seasonNumber : null),
    grandparentId: isEpisode ? card.seriesId : null,
    grandparentTitle: isEpisode ? card.seriesTitle : null,
    grandparentThumbPath: isEpisode ? card.posterUrl : null,
    grandparentArtPath: isEpisode ? card.backdropUrl : null,
    thumbPath: isEpisode ? (card.backdropUrl ?? card.posterUrl) : card.posterUrl,
    artPath: card.backdropUrl,
    clearLogoPath: card.logoUrl,
    durationMs: _ms(card.durationSeconds) ?? _minutesMs(card.runtimeMinutes),
    viewOffsetMs: _ms(card.positionSeconds),
    viewCount: card.userState.played ? 1 : 0,
    lastViewedAt: _epochSeconds(card.progressUpdatedAt),
    addedAt: _epochSeconds(card.addedAt),
    originallyAvailableAt: card.releaseDate,
    rating: ratings?.first.value,
    ratings: ratings,
    isFavorite: card.userState.isFavorite,
    libraryId: libraryId,
    libraryTitle: libraryTitle,
    serverId: origin.serverId.value,
    serverName: origin.serverName,
  );
}

/// Drops hidden types from a row and the row itself once it is empty
/// (`T/ui/util/TvMediaTypeFilters.kt:32-36`).
SiloSection? siloVisibleSection(SiloSection section) {
  final visible = [
    for (final item in section.items)
      if (!isSiloHiddenType(item.type)) item,
  ];
  return visible.isEmpty ? null : section.withItems(visible);
}

String _hubType(List<MediaItem> items) {
  final kinds = {for (final item in items) item.kind};
  if (kinds.length != 1) return 'mixed';
  return switch (kinds.single) {
    MediaKind.movie => 'movie',
    MediaKind.show || MediaKind.season || MediaKind.episode => 'show',
    _ => 'mixed',
  };
}

/// [hubId] is what [SiloHubId] encoded for the row, so "see more" can find it
/// again. The `section_type` travels as the hub identifier.
MediaHub siloSectionToHub(SiloSection section, SiloOrigin origin, {required String hubId}) {
  final items = [for (final card in section.items) siloCardToItem(card, origin)];
  return MediaHub(
    id: hubId,
    identifier: section.sectionType,
    title: section.title,
    type: _hubType(items),
    items: items,
    size: section.totalCount > items.length ? section.totalCount : items.length,
    more: section.totalCount > items.length,
    serverId: origin.serverId.value,
    serverName: origin.serverName,
  );
}

MediaLibrary siloLibraryToMedia(SiloLibrary library, SiloOrigin origin) => MediaLibrary(
  id: library.id,
  backend: MediaBackend.silo,
  title: library.name,
  kind: _libraryKind(library.type),
  serverId: origin.serverId.value,
  serverName: origin.serverName,
);

const Set<String> _directorJobs = {'director'};
const Set<String> _writerJobs = {'writer', 'screenplay', 'story', 'novel', 'author'};
const Set<String> _producerJobs = {'producer', 'executive producer'};

List<String>? _crewNames(List<SiloCredit> crew, Set<String> jobs) {
  final names = [
    for (final member in crew)
      if (jobs.contains(member.role?.toLowerCase()) && member.name.isNotEmpty) member.name,
  ];
  return names.isEmpty ? null : names.toSet().toList();
}

MediaItem siloDetailToItem(SiloItemDetail detail, SiloOrigin origin) {
  final kind = siloKind(detail.type);
  final isEpisode = kind == MediaKind.episode;
  final userData = detail.userData;
  final ratings = _ratings(
    imdb: detail.ratingImdb,
    tmdb: detail.ratingTmdb,
    rtCritic: detail.ratingRtCritic,
    rtAudience: detail.ratingRtAudience,
  );
  final userRating = detail.userRating;
  return MediaItem.silo(
    id: detail.contentId,
    kind: kind,
    title: detail.title,
    titleSort: detail.sortTitle,
    originalTitle: detail.originalTitle,
    summary: detail.overview,
    tagline: detail.tagline,
    year: detail.year,
    contentRating: detail.contentRating,
    studio: detail.studios.firstOrNull,
    genres: detail.genres,
    countries: detail.countries,
    roles: [
      for (final member in detail.cast)
        if (member.name.isNotEmpty)
          MediaRole(id: member.personId, tag: member.name, role: member.role, thumbPath: member.photoUrl),
    ],
    directors: _crewNames(detail.crew, _directorJobs),
    writers: _crewNames(detail.crew, _writerJobs),
    producers: _crewNames(detail.crew, _producerJobs),
    parentId: kind == MediaKind.season ? detail.seriesId : null,
    parentTitle: kind == MediaKind.season ? detail.seriesTitle : null,
    parentIndex: isEpisode ? detail.seasonNumber : null,
    index: isEpisode ? detail.episodeNumber : (kind == MediaKind.season ? detail.seasonNumber : null),
    grandparentId: isEpisode ? detail.seriesId : null,
    grandparentTitle: isEpisode ? detail.seriesTitle : null,
    thumbPath: detail.posterUrl,
    artPath: detail.backdropUrl,
    clearLogoPath: detail.logoUrl,
    durationMs: _ms(userData?.durationSeconds) ?? _minutesMs(detail.runtimeMinutes),
    viewOffsetMs: _ms(userData?.positionSeconds),
    viewCount: kind.usesLeafWatchCounts ? null : ((userData?.played ?? false) ? 1 : 0),
    leafCount: kind == MediaKind.show ? detail.episodeCount : null,
    childCount: kind == MediaKind.show ? detail.seasonCount : null,
    originallyAvailableAt: detail.releaseDate ?? detail.firstAirDate ?? detail.airDate,
    rating: ratings?.first.value,
    ratings: ratings,
    userRating: userRating == null ? null : userRating * 2.0,
    serverId: origin.serverId.value,
    serverName: origin.serverName,
  );
}

MediaItem siloSeasonToItem(SiloSeason season, SiloOrigin origin, {required String seriesId, String? seriesTitle}) =>
    MediaItem.silo(
      id: season.contentId,
      kind: MediaKind.season,
      title: season.title,
      summary: season.overview,
      index: season.seasonNumber,
      parentId: seriesId,
      parentTitle: seriesTitle,
      thumbPath: season.posterUrl,
      leafCount: season.episodeCount,
      viewedLeafCount: season.played ? season.episodeCount : season.watchedCount,
      serverId: origin.serverId.value,
      serverName: origin.serverName,
    );

MediaItem siloEpisodeToItem(
  SiloEpisode episode,
  SiloOrigin origin, {
  required String seriesId,
  String? seriesTitle,
  String? seasonId,
  String? seriesPosterUrl,
}) {
  final userData = episode.userData;
  return MediaItem.silo(
    id: episode.contentId,
    kind: MediaKind.episode,
    title: episode.title,
    summary: episode.overview,
    parentId: seasonId,
    parentIndex: episode.seasonNumber,
    index: episode.episodeNumber,
    grandparentId: seriesId,
    grandparentTitle: seriesTitle,
    grandparentThumbPath: seriesPosterUrl,
    thumbPath: episode.stillUrl,
    durationMs: _ms(userData?.durationSeconds) ?? _minutesMs(episode.runtimeMinutes),
    viewOffsetMs: _ms(userData?.positionSeconds),
    viewCount: (userData?.played ?? false) ? 1 : 0,
    originallyAvailableAt: episode.airDate,
    serverId: origin.serverId.value,
    serverName: origin.serverName,
  );
}

MediaPerson siloPersonToMedia(SiloPerson person, SiloOrigin origin) => MediaPerson(
  id: person.id,
  name: person.name,
  thumbPath: person.photoUrl,
  backend: MediaBackend.silo,
  serverId: origin.serverId,
  serverName: origin.serverName,
);

/// Numbered seasons first, specials last
/// (`S/model/catalog/CatalogModels.kt:483-493`).
List<SiloSeason> siloSeasonsForDisplay(List<SiloSeason> seasons) => [...seasons]
  ..sort((a, b) {
    final specials = (a.isSpecialsForDisplay ? 1 : 0).compareTo(b.isSpecialsForDisplay ? 1 : 0);
    if (specials != 0) return specials;
    final number = a.seasonNumber.compareTo(b.seasonNumber);
    if (number != 0) return number;
    final title = (a.title ?? '').compareTo(b.title ?? '');
    return title != 0 ? title : a.contentId.compareTo(b.contentId);
  });

/// The season a show opens on, from seasons already in display order
/// (`S/model/catalog/CatalogModels.kt:495-509`).
SiloSeason? siloInitialSeason(List<SiloSeason> displayOrder, {int? preferredSeasonNumber}) {
  if (displayOrder.isEmpty) return null;
  bool partlyWatched(SiloSeason s) => s.watchedCount > 0 && s.watchedCount < s.episodeCount;
  return (preferredSeasonNumber == null
          ? null
          : displayOrder.where((s) => s.seasonNumber == preferredSeasonNumber).firstOrNull) ??
      displayOrder.where((s) => s.inProgressCount > 0).firstOrNull ??
      displayOrder.where(partlyWatched).firstOrNull ??
      displayOrder.where((s) => !s.played).firstOrNull ??
      displayOrder.first;
}

/// The episode a season offers next
/// (`T/ui/screens/detail/TvItemDetailViewModel.kt:1835-1839`).
SiloEpisode? siloNextUpEpisode(List<SiloEpisode> episodes) =>
    episodes.where((e) => e.userData?.isInProgress ?? false).firstOrNull ??
    episodes.where((e) => !(e.userData?.played ?? false)).firstOrNull ??
    episodes.firstOrNull;

/// The ordinal of the audio track the plan plays: the server's pick, else
/// the file's effective track, else the first default, else the first.
int siloSelectedAudioOrdinal(SiloFileVersion version, SiloPlan plan) {
  final count = version.audioTracks.length;
  bool valid(int? i) => i != null && i >= 0 && i < count;
  final picked = plan.selectedAudio?.index;
  if (valid(picked)) return picked!;
  if (valid(version.effectiveAudioTrackIndex)) return version.effectiveAudioTrackIndex!;
  final fallback = version.audioTracks.indexWhere((t) => t.isDefault);
  return fallback < 0 ? 0 : fallback;
}

List<MediaAudioTrack> siloAudioTracks(SiloFileVersion version, {int? selected}) => [
  for (var i = 0; i < version.audioTracks.length; i++)
    MediaAudioTrack(
      id: i + 1,
      index: i,
      codec: version.audioTracks[i].codec,
      language: version.audioTracks[i].language,
      languageCode: version.audioTracks[i].language,
      title: version.audioTracks[i].title,
      channels: version.audioTracks[i].channels,
      selected: i == selected,
      isDefault: version.audioTracks[i].isDefault,
    ),
];

/// The ordinal of [version]'s track that serves a carried audio choice, the
/// way the other backends resolve `preferredAudioTrack`. A transcode bakes
/// the audio in, so a reload that drops the carry loses the user's pick.
int? siloCarriedAudioOrdinal(AudioTrack? carried, SiloFileVersion version) =>
    carried == null ? null : findSourceAudioTrackForIntent(carried, siloAudioTracks(version))?.index;

/// Track ids are the ordinal plus one, so no Silo track is 0, which other
/// backends use for "off". The ordinal is what the start body carries
/// (`T/ui/screens/player/TvVideoPlaybackStarter.kt:554-557`).
MediaSourceInfo siloMediaSourceInfo(
  SiloFileVersion version,
  SiloPlan plan, {
  required String videoUrl,
  required int mediaIndex,
}) {
  final audio = siloSelectedAudioOrdinal(version, plan);
  return MediaSourceInfo(
    videoUrl: videoUrl,
    audioTracks: siloAudioTracks(version, selected: audio),
    subtitleTracks: plan.isTranscode
        ? [
            for (final row in plan.subtitleInventory)
              MediaSubtitleTrack(
                id: row.combinedIndex + 1,
                index: row.combinedIndex,
                codec: row.codec,
                language: row.language,
                languageCode: row.language,
                title: row.label,
                selected: false,
                forced: row.forced,
                usesExternalDelivery: row.url != null,
              ),
          ]
        : [
            for (var i = 0; i < version.subtitleTracks.length; i++)
              MediaSubtitleTrack(
                id: i + 1,
                index: i,
                codec: version.subtitleTracks[i].codec,
                language: version.subtitleTracks[i].language,
                languageCode: version.subtitleTracks[i].language,
                title: version.subtitleTracks[i].title,
                selected: false,
                forced: version.subtitleTracks[i].forced,
              ),
          ],
    chapters: const [],
    mediaSourceId: '${version.fileId}',
    mediaIndex: mediaIndex,
    defaultAudioStreamIndex: version.audioTracks.isEmpty ? null : audio + 1,
  );
}

/// Sidecars for a transcode, which carries no subtitle track of its own.
/// Direct play reads embedded tracks from the container. [playerUrl] maps a plan URL to what mpv opens, or to
/// null when mpv cannot open it.
List<PlaybackSubtitleSidecar> siloSubtitleSidecars(SiloPlan plan, Uri? Function(String planUrl) playerUrl) => [
  if (plan.isTranscode)
    for (final row in plan.subtitleInventory)
      if (row.delivery == 'sidecar' && row.url != null)
        if (playerUrl(row.url!) case final uri?)
          PlaybackSubtitleSidecar(
            sourceStreamId: row.combinedIndex + 1,
            track: SubtitleTrack.uri(
              '$uri',
              title: row.label ?? row.language,
              language: row.language,
              codec: row.codec,
              isForced: row.forced,
            ),
          ),
];
