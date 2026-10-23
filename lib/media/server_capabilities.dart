/// Static capability flags advertised by a [MediaServerClient]. UI consults
/// these to gate feature affordances per server (e.g. hide Live TV when no
/// connected server supports it).
///
/// These describe what the *backend kind* supports in this app's current
/// implementation — not necessarily what the wire protocol can do. As more
/// Silo features are wired in over time, the corresponding flags flip
/// without changing call sites.
class ServerCapabilities {
  /// This backend kind has a Live TV / DVR API the app can talk to. Whether
  /// a *specific* server has Live TV configured is a runtime concern —
  /// [MultiServerProvider.checkLiveTvAvailability] probes each server and
  /// only those with channels surface in [MultiServerProvider.liveTvServers].
  final bool liveTv;

  /// Backend has a recording/DVR API wired in this app. Channel listing is
  /// gated by [liveTv]; this flag enables the additional recordings/scheduling
  /// UI. Plex serves `/media/subscriptions`.
  final bool liveTvDvr;

  /// Server can transcode video.
  final bool videoTranscoding;

  /// Server provides curated recommendation hubs (Plex Discover, Silo home
  /// sections).
  final bool richHubs;

  /// Numeric ratings (Plex 0–10 via [Item.userRating]). Backends without a
  /// numeric user rating hide the star sliders.
  final bool numericUserRating;

  /// The server stores whole stars only, so the rating sheet steps by one
  /// star instead of a half. Silo keeps 1 to 5 (`PersonalWrite.kt:23-30`).
  final bool wholeStarRating;

  /// Per-user favorite flag ("heart") on media items. Silo stores it per
  /// profile; Plex has no equivalent.
  final bool userFavorites;

  /// Hide an item from Continue Watching without changing watch state or
  /// playback progress. Plex and Silo expose this directly.
  final bool continueWatchingRemoval;

  /// External subtitle search/marketplace (Plex `/library/metadata/{id}/subtitles`).
  /// Hides the "Search subtitles" affordance when false.
  final bool externalSubtitleSearch;

  /// Server exposes metadata edit endpoints. Hides edit affordances when false.
  final bool richMetadataEdit;

  /// Server can supply thumbnails for the player's seek-bar scrub preview.
  /// Plex serves them as a `.bif` asset, wired through
  /// [ScrubPreviewSource]; the flag gates whether the player attempts the
  /// load at all.
  final bool scrubThumbnails;

  /// Library section exposes a folder hierarchy. Plex uses
  /// `/library/sections/{id}/folders`.
  final bool folderGrouping;

  /// Server can build an "instant mix" / radio track list from a seed item.
  /// Plex: station play queues
  /// (`POST /playQueues?type=audio&uri=...station...`).
  final bool instantMix;

  /// Server pushes library-content change notifications over a websocket the
  /// app can subscribe to (#1646). Plex: `/:/websockets/notifications`
  /// timeline entries; Silo: its realtime event stream.
  /// Whether a *specific* server's socket is reachable (reverse proxies may
  /// not upgrade) is a runtime concern handled by [LibraryEventService]'s
  /// silent degradation.
  final bool libraryChangeEvents;

  const ServerCapabilities({
    this.liveTv = false,
    this.liveTvDvr = false,
    this.videoTranscoding = true,
    this.richHubs = false,
    this.numericUserRating = false,
    this.wholeStarRating = false,
    this.userFavorites = false,
    this.continueWatchingRemoval = false,
    this.externalSubtitleSearch = false,
    this.richMetadataEdit = false,
    this.scrubThumbnails = false,
    this.folderGrouping = false,
    this.instantMix = false,
    this.libraryChangeEvents = false,
  });

  /// Defaults for a Silo server. A flag turns on in the step that implements
  /// it on `SiloClient`, so no screen offers a feature the client cannot
  /// serve yet. Silo has no wire for live TV, DVR, folders, instant mixes,
  /// metadata editing or external subtitle search.
  static const ServerCapabilities silo = ServerCapabilities(
    liveTv: false,
    liveTvDvr: false,
    videoTranscoding: true,
    richHubs: true,
    numericUserRating: true,
    wholeStarRating: true,
    userFavorites: true,
    externalSubtitleSearch: true,
    richMetadataEdit: false,
    scrubThumbnails: false,
    folderGrouping: false,
    instantMix: false,
    continueWatchingRemoval: true,
    libraryChangeEvents: true,
  );

  /// Every flag here is fixed per backend *kind* except [videoTranscoding],
  /// which Plex probes per server (`PlexClient.capabilities`) — so that is the
  /// only override this type needs. Widen the parameter list if another flag
  /// ever becomes a runtime probe.
  ServerCapabilities copyWith({bool? videoTranscoding}) {
    return ServerCapabilities(
      liveTv: liveTv,
      liveTvDvr: liveTvDvr,
      videoTranscoding: videoTranscoding ?? this.videoTranscoding,
      richHubs: richHubs,
      numericUserRating: numericUserRating,
      wholeStarRating: wholeStarRating,
      userFavorites: userFavorites,
      continueWatchingRemoval: continueWatchingRemoval,
      externalSubtitleSearch: externalSubtitleSearch,
      richMetadataEdit: richMetadataEdit,
      scrubThumbnails: scrubThumbnails,
      folderGrouping: folderGrouping,
      instantMix: instantMix,
      libraryChangeEvents: libraryChangeEvents,
    );
  }
}
