# Plezy backend removal and replacement map

Research for replacing Plex, Jellyfin and Emby with a single Silo backend. Branch `feat/silo-backend`, read on 2026-10-11. Every `path:line` below was read this session. Counts are measured with `grep` over `lib/` and `test/` unless a line says otherwise. Guesses carry the label **(guess)**.

## Summary

Emby is not a separate client. One `JellyfinClient` serves Jellyfin and Emby through a `MediaBrowserDialect` switch (`lib/services/jellyfin_client.dart:261-286`, `lib/media/media_backend.dart:44-55`). So there are two backend stacks to delete, Plex and MediaBrowser.

The neutral seam is real but leaky. `MediaServerClient` has 83 members (measured, `lib/media/media_server_client.dart:121-900`). Two implementations exist, `PlexClient` (`lib/services/plex_client.dart:389-398`) and `JellyfinClient` (`lib/services/jellyfin_client.dart:265-286`). Callers still cast to the concrete classes. `PlexClient` appears in 31 non-generated lib files and `JellyfinClient` in 31 (measured).

The leak below the seam is the data model. `MediaItem` is a sealed union with a `plex` and a `jellyfin` variant (`lib/media/media_item.dart:32`, `:118`, `:206`). `Connection` is a sealed union of `PlexAccountConnection` and `JellyfinConnection` (`lib/connection/connection.dart:13`, `:44`, `:158`). `Profile` is a sealed union of `local` and `plexHome` (`lib/profiles/profile.dart:23`, `:26`, `:38`). All three are persisted.

## 1. `MediaServerClient` interface

Source is `lib/media/media_server_client.dart`. Capability flags live in `ServerCapabilities` (`lib/media/server_capabilities.dart:9-86`). Per-backend presets are `plex` (`:89`), `jellyfin` (`:114`) and `emby` (`:143`).

### Capability flags today

| Flag | Plex | Jellyfin | Emby | Gates |
|---|---|---|---|---|
| `liveTv` (`:14`) | yes | yes | yes | Live TV tab |
| `liveTvDvr` (`:20`) | yes | yes | yes | Recording UI via `liveTvDvr` extension (`media_server_client.dart:974`) |
| `videoTranscoding` (`:23`) | probed per server | yes | yes | Quality presets |
| `richHubs` (`:27`) | yes | no | no | Curated hubs |
| `numericUserRating` (`:31`) | yes | no | no | Star slider in `rating_bottom_sheet.dart` |
| `userFavorites` (`:35`) | no | yes | yes | Heart toggle |
| `continueWatchingRemoval` (`:39`) | yes | no | yes | "Remove from Continue Watching" |
| `externalSubtitleSearch` (`:43`) | yes | no | no | Subtitle search sheet |
| `richMetadataEdit` (`:46`) | yes | yes | yes | Edit metadata screen |
| `scrubThumbnails` (`:52`) | yes (BIF) | yes (trickplay) | yes (BIF) | Seek-bar preview |
| `folderGrouping` (`:57`) | yes | yes | yes | Folder tab |
| `instantMix` (`:62`) | yes | yes | yes | Music radio |
| `libraryChangeEvents` (`:70`) | yes | yes | yes | Push refresh socket |

Flag reads appear in 25 lib files (measured, `capabilities\.\w+`). Silo needs its own preset. Unsupported flags degrade cleanly only where call sites consult the flag.

### Members by concern

Line numbers are the declaration in `lib/media/media_server_client.dart`. "Only" means the method is implemented for one backend and throws or no-ops on the other, per its doc comment or capability flag.

| Concern | Members (line) | Backend notes |
|---|---|---|
| Identity and lifecycle | `serverId` 122, `serverName` 123, `backend` 124, `capabilities` 125, `authenticationSessionId` 130, `close` 133, `checkHealth` 147, `getMachineIdentifier` 151, `isOfflineMode` 155, `setOfflineMode` 156, `cache` 161, `createLibraryEventChannel` 140 | `HealthStatus` enum at 79 distinguishes 401 and 403. `cache` is a per-backend `ApiCache` substrate. |
| Libraries | `fetchLibraries` 163, `fetchLibraryPagedContent` 175, `fetchLibraryFiltersWithValues` 194, `fetchSortOptions` 201, `refreshLibraryMetadata` 210, `fetchLibraryFolders` 248, `fetchFolderChildren` 254 | Folders gated by `folderGrouping`. |
| Items | `fetchItem` 217, `fetchItemWithOnDeck` 234, `fetchChildren` 241, `fetchChildrenPage` 265, `fetchPlayableDescendantsPage` 271, `fetchPlayableDescendants` 294, `fetchClientSideEpisodeQueue` 301, `fetchExtras` 431, `fetchPersonMediaPage` 434, `deleteMediaItem` 593, `getFileInfo` 599 | On-deck bundling is a Plex wire feature (doc at 222-233). |
| Hubs and home | `fetchContinueWatching` 390, `fetchGlobalHubs` 397, `fetchLibraryHubs` 410, `fetchRelatedHubs` 425, `fetchMoreHubItems` 440, `fetchMoreHubItemsPage` 444 | `richHubs` is Plex only. |
| Search | `searchItems` 356, `searchPeople` 376 | Neutral. |
| Music | `fetchArtistAlbums` 308, `fetchArtistDiscography` 322, `fetchAlbumTracks` 329, `fetchInstantMix` 337, `fetchLyrics` 344 | Discography taxonomy is Plex only (doc at 316-321). |
| Watch state and ratings | `markWatched` 459, `markUnwatched` 462, `removeFromContinueWatching` 467, `rate` 474, `setFavorite` 479, `watchedThreshold` 754, `marksWatchedOnPlaybackStopped` 765 | `rate` is Plex only in practice. `setFavorite` is MediaBrowser only. `removeFromContinueWatching` is Plex and Emby. |
| Playlists | `fetchPlaylistsPage` 483, `fetchPlaylistMetadata` 492, `fetchPlaylistPage` 496, `createPlaylist` 503, `addToPlaylist` 506, `deletePlaylist` 509, `movePlaylistItem` 521, `removeFromPlaylist` 530 | Neutral. |
| Collections | `fetchCollectionsPage` 538, `fetchCollectionPage` 549, `fetchCollectionMemberships` 567, `createCollection` 574, `addToCollection` 582, `removeFromCollection` 585, `deleteCollection` 590 | Neutral. Memberships feed the `DownloadCollections` table. |
| Images and headers | `thumbnailUrl` 619, `externalImageUrl` 627, `streamHeaders` 634 | Neutral shape. URLs embed backend auth. |
| External ids | `fetchExternalIds` 643, `findByExternalIds` 695 | Feeds trackers and catalog matching. |
| Playback | `fetchPlaybackExtras` 707, `fetchPlaybackExtrasFromCacheOnly` 720, `fetchCachedMediaSourceInfo` 734, `createScrubPreviewSource` 748, `getPlaybackInitialization` 835, `resolveExternalPlayback` 893 | Chapters and markers come from both. |
| Progress reporting | `reportPlaybackStarted` 776, `reportPlaybackProgress` 791, `reportPlaybackStopped` 812 | Extension `markWatchedFromPlaybackStop` at 930 and `notifyWatchedFromPlaybackSession` at 960 encode Trakt double-scrobble rules for both backends. |
| Live TV | `liveTv` 841 returns `LiveTvSupport` (`lib/media/live_tv_support.dart:173-230`). DVR is `LiveTvDvrSupport` (`live_tv_support.dart:240-262`). | DVR surface is Plex-shaped (subscriptions, grabs, templates). MediaBrowser adapts timers to it. |
| Downloads | `resolveDownload` 856, `stampLibrary` 864, `resolveDownloadArtwork` 870 | Neutral shape. |
| Metadata editing | Not on the interface. Lives on concrete clients and `lib/metadata_edit/metadata_edit_adapters.dart:10` (casts to `PlexClient`). | Plex adds match, unmatch, artwork and agent prefs (`lib/services/plex_client/parts/metadata_edit.dart:6-182`). |
| Admin | `refreshLibraryMetadata` 210, `deleteMediaItem` 593. Library scan, empty trash and analyze live on `PlexClient` via `getPlexClientForLibrary` (`lib/widgets/library_management_sheet.dart:254`, `:276`, `:287`). Server activities via `getPlexClientForServer` (`lib/widgets/server_activities_button.dart:117`, `:196`). | Plex only. |

Optional side interfaces in the same file:

- `ScopedMediaServerClient` (903) supplies `cacheServerId` (911). Both clients implement it. Plex uses a per-profile scope, Jellyfin uses `{machineId}/{userId}`.
- `SeasonEpisodePagingClient` (980) is Jellyfin only.
- `MediaDeletionPermissionClient` (1000) is Jellyfin only (doc at 990-999).
- `GracefullyCloseable` (81) is implemented by both.
- `MediaServerCacheMixin` (1025) is shared cache plumbing.

Plex-only methods outside the interface that screens reach through casts:

- Play queues (`lib/services/plex_client/parts/play_queues.dart:45`, `:78`, `:106`), used by `lib/services/play_queue_launcher.dart:20-27` and `lib/screens/video_player/parts/episode_queue.dart:24`.
- Filter values (`lib/services/agent_scoped_settings_commands.dart:743`).
- Server prefs for offline sync (`lib/services/offline_watch_sync_service.dart:78`).
- Track preference persistence (`lib/screens/video_player/parts/playback_open.dart:722`).
- Section prefs on detail (`lib/screens/media_detail_screen.dart:1773`, `:1795`).

24 lib files cast to or fetch `PlexClient` directly (measured, `getPlexClient|is PlexClient|as PlexClient`). 9 lib files cast to `JellyfinClient` (measured).

## 2. Sign-in and server onboarding

### App start

1. `lib/main.dart:1862` sets `SetupScreen` as `home`.
2. `SetupScreen._loadSavedCredentials` (`lib/main.dart:2041`) runs `ConnectionBootstrap.run` (`:2082-2089`). That is the one-shot migration of legacy SharedPreferences Plex state (`lib/connection/connection_bootstrap.dart:16-25`).
3. It prunes orphan MediaBrowser connections via `ProfileConnectionCleanup.pruneUnreferencedJellyfinConnections` (`lib/main.dart:2090-2095`).
4. No stored connections routes to `AuthScreen` (`lib/main.dart:2145-2148`).
5. Otherwise it starts `ActiveProfileBinder` (`lib/main.dart:2208`). It may push `ProfileSwitchScreen(requireSelection: true)` (`:2223-2225`). It then enters offline mode (`:2245`) or `ProfileSessionScreen` (`:2257`).
6. Splash status rows branch on `PlexAccountConnection` versus `JellyfinConnection` (`lib/main.dart:2157-2170`).

### Provider wiring

`lib/main.dart:1643-1715` builds `PlexHomeService`, `ActiveProfileProvider` (takes `plexHome`, `:1662`), `MultiServerProvider` and `ActiveProfileBinder`. `onJellyfinConnectionUpdated` persists refreshed MediaBrowser endpoints into `ConnectionRegistry` (`lib/main.dart:1673`, `lib/services/multi_server_manager.dart:72`). `JellyfinApiCache.initialize` runs at `lib/main.dart:1322`.

### Plex

- `AuthScreen` (`lib/screens/auth_screen.dart:37`) hosts `PlexPinAuthFlow` (`:348`, file `lib/screens/auth/plex_pin_auth_flow.dart`). That flow is PIN plus QR, with an Android Automotive QR-only mode (`plex_pin_auth_flow.dart:15-20`).
- `PlexAuthService` (`lib/services/plex_auth_service.dart:53`) owns `createPin` 155, `checkPin` 173, `pollPinUntilClaimed` 203, `fetchServers` 227, `getHomeUsers` 301, `switchToUser` 309 and endpoint racing (`PlexNetworkClass` 337).
- After the token arrives, `registerPlexAccountFromToken` (`lib/connection/plex_account_setup.dart`) builds the `PlexAccountConnection` and fetches Home users. `AuthScreen` calls it at `:146`. It auto-selects a single unprotected Home user (`:484-492`) or pushes the picker (`:206-208`).
- Add-later path is `AddPlexAccountScreen` (`lib/screens/settings/add_plex_account_screen.dart:26-31`, `:70`, `:147`).
- Debug token entry is in `auth_screen.dart:466` and `:508-583`.

### Jellyfin and Emby

- `AuthScreen._connectToMediaBrowser` (`lib/screens/auth_screen.dart:237-248`) pushes `AddJellyfinScreen(dialect:)`. Buttons are at `:363-364` and `:438-450`.
- `AddJellyfinScreen` (`lib/screens/settings/add_jellyfin_screen.dart:77-81`) has three steps. It probes `/System/Info/Public`, then signs in with password or Quick Connect, then persists.
- LAN discovery is `JellyfinLanDiscoveryService` (`lib/services/jellyfin_lan_discovery_service.dart:19`, called at `add_jellyfin_screen.dart:182`).
- Endpoint racing is `lib/services/jellyfin_endpoint_discovery.dart:16-95`.
- `JellyfinConnectionAuthService` (`lib/services/jellyfin_auth_service.dart:50`) owns `probe` 87, `raceEndpoints` 91, `authenticateByName` 112, `isQuickConnectEnabled` 169, `initiateQuickConnect` 189, `authenticateByQuickConnect` 250.
- Quick Connect UI is shared with Seerr (`lib/screens/settings/quick_connect_flow_mixin.dart:5-10`, `lib/widgets/quick_connect_code_panel.dart:9-14`).
- Edit is `EditJellyfinConnectionScreen` (`lib/screens/settings/edit_jellyfin_connection_screen.dart:19`).
- Emby is the same screens with `MediaBrowserDialect.emby`.

### Neutral onboarding pieces

- `AddConnectionScreen` (`lib/screens/settings/add_connection_screen.dart:17-22`) is the "Add connection" picker. It also offers "Borrow from another profile".
- `connection_persistence.dart` (`lib/screens/settings/connection_persistence.dart:15-20`) commits connection, first-run profile and join row in one transaction. This is the best template for Silo **(guess)**.
- `BorrowConnectionScreen` (`lib/screens/profile/borrow_connection_screen.dart:31-36`) copies a connection to another profile.
- `PendingAuthDialog` (`lib/widgets/pending_auth_dialog.dart:16-21`) is a generic QR wait dialog. Trackers use it too.

## 3. Profiles

### Model

- `Profile` is sealed (`lib/profiles/profile.dart:23`). `Profile.local` (`:26`) has an optional local PIN hash. `Profile.plexHome` (`:38`) carries `parentConnectionId`, `plexHomeUserUuid`, `plexRestricted`, `plexAdmin` and `plexProtected`. Accessors that switch on the variant are at `:118-163`.
- Plex Home profile ids are `plex-home-{accountId}-{homeUserUuid}` (`lib/database/tables.dart:221-222`). Parsing is at `lib/profiles/profile.dart:248-251`.
- `ProfileConnection` (`lib/profiles/profile_connection.dart:18-31`) joins a profile to a connection. It carries `userToken` and `userIdentifier`. For Plex the token is a Home-user token minted by `/home/users/{uuid}/switch`, and empty means "mint lazily". For MediaBrowser it mirrors the connection's access token.

### Runtime

- `PlexHomeService` (`lib/profiles/plex_home_service.dart:13-22`) fetches `/home/users` per Plex account and caches raw JSON in SharedPreferences under `plex_home_users_{connectionId}` (`lib/services/storage_service.dart:32`). It emits a stream that the picker merges with local profiles. Plex Home profiles are virtual and never stored in `profiles` (`lib/database/tables.dart:261-266`). The table doc at `tables.dart:214-216` says the opposite. The FK comment matches the code path `Profile.virtualPlexHome` (`lib/screens/auth_screen.dart:492`), so treat the table doc as stale **(inferred)**.
- `ActiveProfileBinder` (`lib/profiles/active_profile_binder.dart:74`, 1162 lines) turns the active profile into live clients. `_runRebindOnce` (`:286`) reads join rows and connections. `_bindPlexHome` (`:493`) mints or reuses Home tokens and refreshes plex.tv resources. `_bindJoinRows` (`:598`) handles every other row and branches per connection kind (`:624`, `:636`). The MediaBrowser path calls `serverManager.addJellyfinConnection` (`:1106-1110`). PIN prompt policy is at `:101-170`.
- `profile_activation.dart` validates Plex Home PINs through `/switch` before activation (`lib/profiles/profile_activation.dart:38-42`, `:256-262`).
- `active_plex_token.dart` and `active_plex_identity.dart` resolve the Plex credential for Discover, Seerr and companion remote.

### Plex-specific versus neutral

| Plex-specific (delete) | Neutral (keep, edit) |
|---|---|
| `plex_home_service.dart`, `plex_home_switch.dart`, `plex_home_cache_codec.dart`, `active_plex_token.dart`, `active_plex_identity.dart`, `Profile.plexHome`, `_bindPlexHome`, Plex token policy (`active_profile_binder.dart:651-1050`) | `Profile.local`, `ProfileConnection`, `profile_registry.dart`, `profile_connection_registry.dart`, `active_profile_provider.dart`, `profile_menu.dart`, `profile_avatar*.dart`, `profile_selection_policy.dart`, `profile_merge.dart`, `_bindJoinRows` |

The MediaBrowser model (one user per connection, token on the join row, local profiles own connections) is the shape Silo can reuse **(guess, depends on whether Silo has server-side multi-user profiles; `docs/silo-migration/research/silo-auth.md` is still in progress)**.

## 4. Persistence

Drift database at `lib/database/app_database.dart:49`, `schemaVersion` 25 (`:371`). Tables are in `lib/database/tables.dart`.

| Table (line) | Backend-bearing columns | Breaks on swap |
|---|---|---|
| `ApiCache` (5) | `cacheKey` is `serverId:endpoint` with Plex or Jellyfin paths. `data` is raw backend JSON. `pinned` keeps download metadata. | Every row is unreadable once the parsers (`lib/utils/plex_cache_parser.dart`, `lib/services/jellyfin_cache_resolver.dart`) are deleted. |
| `DownloadedMedia` (39) | `serverId`, `clientScopeId`, `ratingKey`, `globalKey`, `mediaSourceId`, `additionalPartPaths` (Plex stacked parts) | Files stay on disk but metadata comes from `ApiCache`. Offline library becomes blank or orphaned. |
| `DownloadOwners` (90) | `backend`, `clientScopeId` | Rows point at removed backends. |
| `SyncRules` (110), `SyncRuleDownloads` (138) | `serverId`, `ratingKey`, `globalKey` | Rules target servers that no longer exist. |
| `DownloadCollections` (155), `DownloadCollectionSyncs` (169) | `serverId`, `collectionId` | Stale. |
| `Connections` (187) | `kind` is `plex`, `jellyfin` or `emby`. `configJson` holds encrypted tokens. | `MediaBackend.fromId` throws on unknown ids (`lib/media/media_backend.dart:20-25`). `_rowToConnection` catches and returns null (`lib/connection/connection_registry.dart:141-173`). Old rows vanish silently and are never cleaned. |
| `Profiles` (220) | `kind` is `local` or `plex_home` | Locals survive. |
| `ProfileConnections` (260) | `userToken`, `userIdentifier` | Cascades on `Connections` delete (`tables.dart:268`). Only works if the rows are actually deleted. |
| `OfflineWatchProgress` (286) | `serverId`, `clientScopeId`, `globalKey` | Queued actions for gone servers never sync. |
| `MusicSessions` (340) | `queueJson` is serialized `MediaItem` JSON | See `MediaItem` below. |

Other stored state:

- `MediaItem.toJson` writes a `backend` union key (`lib/media/media_item.dart:305-309`). `MediaItem.fromJson` dispatches on it (`:297-303`). `MediaBackend.fromString` maps any unknown id to Plex (`lib/media/media_backend.dart:33-42`). Removing the Plex variant changes the fallback for every old cache row, music session and download.
- `CredentialVault._tokenKeyForKind` (`lib/services/credential_vault.dart:128-136`) encrypts tokens only for listed kinds. A new `silo` kind not added there persists its token in plaintext, per the doc comment at `:128-130`.
- SharedPreferences keys in `lib/services/storage_service.dart:15-32` include `plex_token`, `client_identifier`, `current_user_uuid`, `servers_list`, `server_order`, `server_endpoint_*`, `plex_home_users_*`, and per-library keys keyed by Plex section ids. `lib/services/server_registry.dart` holds the legacy Plex server list read by `ConnectionBootstrap`.
- `lib/database/plex_metadata_recovery.dart` strips profile-private Plex fields from shared cache rows.
- Seerr sessions (`lib/services/seerr/seerr_session_store.dart`) store an auth method of `plex`, `jellyfin` or `emby` (`lib/models/seerr/seerr_session.dart:5-11`).

What a swap breaks, in plain terms. A user who upgrades loses every server connection and every downloaded item's metadata. Their local profiles survive with no servers attached. Queued offline progress is lost. A schema migration to version 26 that deletes old-kind rows and unpinned cache is the clean option **(recommendation)**.

## 5. Coupling census

Method. `grep -rlP` over `*.dart` in `lib/` and `test/` with `(?<![a-zA-Z])[pP]lex|Plex|PLEX|[jJ]ellyfin|JELLYFIN|(?<![a-z])emby|Emby|EMBY`. This excludes `complex`, `totalMemBytes` and `ItemByServer` false positives that a plain `grep -rli` catches. Buckets:

- **delete** is a file whose path names plex, jellyfin or emby.
- **edit** has at least one non-comment hit.
- **ui-copy** is generated i18n Dart. The source is 34 matching lines in `lib/i18n/en.i18n.json` (measured), mirrored across locales.
- **comment-only** has hits only in `//` or `///` lines. These need doc cleanup, not logic changes.

705 files match out of 1655 Dart files (measured). 32 of the matches are generated (`.g.dart`, `.freezed.dart`).

| Directory | delete | edit | ui-copy | comment-only | total |
|---|---|---|---|---|---|
| lib/connection | 1 | 3 | 0 | 0 | 4 |
| lib/data | 0 | 0 | 0 | 1 | 1 |
| lib/database | 1 | 2 | 0 | 2 | 5 |
| lib/dev | 0 | 0 | 0 | 1 | 1 |
| lib/exceptions | 0 | 0 | 0 | 1 | 1 |
| lib/i18n | 0 | 0 | 23 | 0 | 23 |
| lib/main.dart | 0 | 1 | 0 | 0 | 1 |
| lib/media | 0 | 10 | 0 | 29 | 39 |
| lib/metadata_edit | 2 | 1 | 0 | 0 | 3 |
| lib/mixins | 0 | 0 | 0 | 2 | 2 |
| lib/models | 0 | 0 | 0 | 7 | 7 |
| lib/models/catalog | 0 | 1 | 0 | 0 | 1 |
| lib/models/jellyfin | 2 | 0 | 0 | 0 | 2 |
| lib/models/plex | 16 | 0 | 0 | 0 | 16 |
| lib/models/seerr | 0 | 1 | 0 | 0 | 1 |
| lib/models/trackers, lib/models/trakt | 0 | 0 | 0 | 5 | 5 |
| lib/mpv/player | 0 | 0 | 0 | 1 | 1 |
| lib/navigation | 0 | 1 | 0 | 0 | 1 |
| lib/profiles | 5 | 9 | 0 | 1 | 15 |
| lib/providers | 0 | 7 | 0 | 5 | 12 |
| lib/screens (top level) | 1 | 8 | 0 | 2 | 11 |
| lib/screens/auth | 1 | 0 | 0 | 0 | 1 |
| lib/screens/downloads | 0 | 1 | 0 | 1 | 2 |
| lib/screens/libraries | 0 | 4 | 0 | 9 | 13 |
| lib/screens/livetv | 0 | 3 | 0 | 5 | 8 |
| lib/screens/music | 0 | 0 | 0 | 1 | 1 |
| lib/screens/playlist | 0 | 1 | 0 | 1 | 2 |
| lib/screens/profile | 0 | 5 | 0 | 1 | 6 |
| lib/screens/settings | 3 | 3 | 0 | 4 | 10 |
| lib/screens/video_player | 0 | 5 | 0 | 9 | 14 |
| lib/services (top level) | 24 | 32 | 0 | 16 | 72 |
| lib/services/catalog | 1 | 1 | 0 | 2 | 4 |
| lib/services/companion_remote | 0 | 2 | 0 | 1 | 3 |
| lib/services/jellyfin_client | 12 | 0 | 0 | 0 | 12 |
| lib/services/library_events | 1 | 0 | 0 | 3 | 4 |
| lib/services/music | 0 | 0 | 0 | 2 | 2 |
| lib/services/plex_client | 5 | 0 | 0 | 0 | 5 |
| lib/services/seerr | 0 | 4 | 0 | 2 | 6 |
| lib/services/trackers | 0 | 0 | 0 | 6 | 6 |
| lib/utils | 5 | 8 | 0 | 27 | 40 |
| lib/watch_together/screens | 0 | 1 | 0 | 0 | 1 |
| lib/widgets | 0 | 6 | 0 | 4 | 10 |
| lib/widgets/video_controls | 0 | 9 | 0 | 4 | 13 |
| **lib total** | **80** | **129** | **23** | **155** | **387** |
| test (all) | 68 | 240 | 0 | 10 | 318 |
| **grand total** | **148** | **369** | **23** | **165** | **705** |

The 80 lib files in the delete bucket add up to 26,079 lines (measured with `wc -l`).

Six more lib files are backend implementation without the backend in their name **(judgment)**:

- `lib/media/media_browser_dialect.dart`
- `lib/services/media_browser_paths.dart`
- `lib/services/media_browser_account_preferences_source.dart`
- `lib/services/library_events/media_browser_library_event_socket.dart`
- `lib/services/server_registry.dart` (legacy Plex server list)
- `lib/services/play_queue_launcher.dart` (Plex play queues, doc at `:20-27`)

With those, the lib delete set is 86 files.

The test "edit" bucket is an upper bound on edits. Many of those 240 files test Plex or Jellyfin behaviour through neutral-named files and will be deleted, not edited **(guess)**. `test/services` alone has 49 such files and `test/widgets` has 40.

Hot spots in the lib edit bucket, by non-comment hit count (measured):

| File | Hits | Why it matters |
|---|---|---|
| `lib/services/multi_server_manager.dart` | 181 | Per-backend client maps, Plex endpoint racing, relay escape, reconnect (`:29-184`, `:439`, `:802`, `:1376`, `:1421`) |
| `lib/services/track_selection_service.dart` | 125 | Mostly naming. Server tracks are called "Plex tracks" (`:1-4`). |
| `lib/profiles/active_profile_binder.dart` | 75 | See section 3 |
| `lib/connection/connection_bootstrap.dart` | 63 | Legacy Plex migration. Deletable once Plex is gone. |
| `lib/media/media_item.freezed.dart`, `media_item.dart` | 51, 20 | Union variants |
| `lib/screens/auth_screen.dart` | 47 | Sign-in entry |
| `lib/profiles/profile.dart` | 44 | `Profile.plexHome` |
| `lib/providers/companion_remote_provider.dart` | 42 | Plex Home or MediaBrowser identity for pairing |
| `lib/services/file_info_parser.dart` | 38 | Plex file-info payload shape |
| `lib/services/cached_playback_metadata_service.dart` | 34 | Reads raw cache through both parsers |
| `lib/utils/active_client_scope.dart` | 33 | `PlexProfileScopeId` and Jellyfin compound scope (`:7-8`, `:69`) |
| `lib/database/app_database.dart` | 29 | Migrations and download ops |

Other symbol counts in non-generated lib files (measured):

- `MediaBackend.(plex|jellyfin|emby)` appears in 32 files, 96 hits.
- `PlexAccountConnection` appears in 27 files, `JellyfinConnection` in 21.
- `PlexHomeService` appears in 20 files.
- `cacheServerId` or `ScopedMediaServerClient` appears in 28 files, 159 hits.
- `ratingKey`, a Plex term used as the neutral item id, appears in 68 files, 815 hits.

## 6. Features with no obvious Silo equivalent

Each line names the feature, where it lives, and which backend it needs. Whether Silo offers it is a guess until the Silo API research lands.

- **Plex Discover catalog and watchlist.** `lib/services/plex_discover_client.dart:14-81`, `lib/services/catalog/plex_catalog_source.dart`, wired in `lib/providers/catalog_sources_provider.dart`. Needs a plex.tv account token. Note that `lib/screens/discover_screen.dart` is the neutral home screen, not Plex Discover.
- **Plex Home profiles and PIN switching.** See section 3.
- **Server-side play queues.** `lib/services/plex_client/parts/play_queues.dart`, `lib/services/play_queue_launcher.dart`. Jellyfin already uses `fetchClientSideEpisodeQueue` (`media_server_client.dart:301`) and `lib/services/jellyfin_sequential_launcher.dart`. Silo can take the client-side path.
- **Live TV and DVR.** `lib/screens/livetv/` (11 files plus tabs), `lib/media/live_tv_support.dart`. Both backends today. DVR shape is Plex's.
- **Plex match, unmatch, artwork and agent prefs.** `lib/screens/plex_match_screen.dart`, `lib/services/plex_client/parts/metadata_edit.dart:91-182`.
- **Rich metadata editing.** `lib/metadata_edit/` adapters for both backends (`metadata_edit_adapters.dart:10`).
- **External subtitle search.** Plex only (`server_capabilities.dart:41-43`, model `lib/models/plex/plex_subtitle_search_result.dart`).
- **Library admin and server activities.** Scan, empty trash, analyze (`lib/widgets/library_management_sheet.dart:218-287`), activity monitor (`lib/widgets/server_activities_button.dart`, `lib/models/plex/plex_activity.dart`). Plex only.
- **Server-stored account preferences.** Plex account prefs (`lib/services/plex_account_preferences_source.dart`, `plex_auth_service.dart:275-286`) and Jellyfin user configuration (`lib/services/jellyfin_client/parts/account_preferences.dart`) through `lib/providers/account_preferences_controller.dart`.
- **Plex relay and endpoint racing.** `multi_server_manager.dart:206-209`, `:1356-1361`, `plex_auth_service.dart:337`. Plex only.
- **Plex Pass features.** No dedicated gate found. Transcoding is probed per server (`server_capabilities.dart:159-162`). Treat Plex Pass as implicit in server responses **(inferred)**.
- **Seerr.** Signs in with Plex, Jellyfin or Emby credentials (`lib/services/seerr/seerr_auth_service.dart:186-208`). Without those backends only a Seerr-local login remains, if Seerr offers one **(guess)**.
- **Companion remote pairing.** Shared secret derived from Plex Home data or MediaBrowser server/user identity (`lib/services/companion_remote/remote_auth_service.dart:1-15`, `companion_remote_host_controller.dart:5-38`). Silo needs its own identity derivation.
- **Watch Together display name.** Reads the profile name (`lib/watch_together/screens/*.dart:109`). Relay itself is backend-neutral.
- **Jellyfin-only extras.** Quick Connect, LAN discovery, per-item delete permission, season episode paging, user favorites, trickplay sprites.
- **Plex stacked multi-part files.** `DownloadedMedia.additionalPartPaths` (`tables.dart:59-64`), `resolveExternalPlayback` doc (`media_server_client.dart:880-890`).

## Suggested phase boundaries

These phases are a recommendation, not measured. Each phase should end with `flutter analyze` and the test suite green.

**Phase 1. Add Silo next to the others.** Plex and Jellyfin still compile.

- Add `MediaBackend.silo` and `ServerCapabilities.silo`. The compiler then lists every exhaustive `switch` on the enum, about 32 files by the symbol count above. That error list is the work list.
- Add `SiloConnection` to the sealed `Connection`, parse it in `connection_registry.dart:150`, and add its token key to `credential_vault.dart:132`.
- Add a `MediaItem.silo` variant, or map Silo DTOs into an existing variant as a stopgap. The variant is cleaner because `fromJson` dispatch already keys on `backend`.
- Write `SiloClient implements MediaServerClient, ScopedMediaServerClient, GracefullyCloseable` with `MediaServerCacheMixin`. Follow the `JellyfinClient` part-file layout.
- Add `MultiServerManager.addSiloConnection` modeled on `addJellyfinConnection` (`multi_server_manager.dart:802`), with a `_bindJoinRows` branch (`active_profile_binder.dart:636`).
- Add `AddSiloScreen` that uses `connection_persistence.dart`, and a sign-in button on `AuthScreen`.

**Phase 2. Pull Plex-only calls behind the interface or capabilities.** Replace the 24 `getPlexClient` or `is PlexClient` sites with interface methods or capability gates. That way deleting Plex removes features, not compile paths. Move metadata editing and library admin to an optional interface like `MediaDeletionPermissionClient`.

**Phase 3. Delete Plex.** This has the largest payoff and the most risk. It covers all `plex_*` files, `lib/models/plex/`, `Profile.plexHome`, `PlexHomeService`, the Plex half of the binder, `connection_bootstrap.dart`, `server_registry.dart`, Plex Discover, Plex catalog source, Seerr Plex auth, and companion remote's Plex Home path. The profile model collapses to local profiles plus join rows, which is what Silo uses.

**Phase 4. Delete Jellyfin and Emby.** This covers `jellyfin_*`, `media_browser_*`, `lib/services/jellyfin_client/`, `MediaBrowserDialect`, Quick Connect panel (unless Seerr keeps it) and LAN discovery. Do it after Silo onboarding is stable, because the Jellyfin flow is the closest working reference for Silo's shape **(judgment)**.

**Phase 5. Collapse the seams and migrate data.**

- Reduce `MediaBackend`, `Connection` and `MediaItem` to their Silo case, or remove the discriminator.
- Bump drift schema to 26. Delete `Connections` rows of old kinds so `ProfileConnections` cascade. Clear `ApiCache`. Decide whether to drop or keep orphaned downloads.
- Clear legacy SharedPreferences keys.
- Rename `ratingKey`, "Plex track" and similar leftovers.
- Regenerate i18n and clean the 165 comment-only files.

## Riskiest couplings

1. **`MediaItem` as a persisted backend union.** `lib/media/media_item.dart:32`, `:118`, `:206`, `:297-309` with the Plex-default fallback at `lib/media/media_backend.dart:33-42`. It is serialized into `ApiCache`, `MusicSessions.queueJson` and download metadata. Changing the union silently changes how every stored row decodes.
2. **Plex Home woven into profiles and binding.** `Profile.plexHome` (`lib/profiles/profile.dart:38`), virtual profiles without FK (`lib/database/tables.dart:261-266`), and `_bindPlexHome` in a 1162-line binder (`lib/profiles/active_profile_binder.dart:493`). Companion remote, Seerr and Discover read the same identity through `active_plex_token.dart` and `active_plex_identity.dart`.
3. **Per-backend scope ids as storage keys.** `cacheServerId` or `ScopedMediaServerClient` appears in 28 files (`lib/media/media_server_client.dart:903-915`, `lib/utils/active_client_scope.dart:7-69`). Those ids are written into `clientScopeId` and `serverId` columns of downloads, owners and offline progress, and `MultiServerManager` resolves them by backend (`lib/services/multi_server_manager.dart:257-263`). Silo must choose a scope id format before its first download row is written.

A smaller hazard sits next to these. `ConnectionRegistry` drops undecodable rows silently (`lib/connection/connection_registry.dart:170-173`). `CredentialVault` stores tokens of unlisted kinds in plaintext (`lib/services/credential_vault.dart:128-136`).
## Addendum. Second research pass

A second worker wrote this file in parallel. Its sections 1 to 4 were overwritten by the report above, and only its sections 5 to 7 survived. They are kept here because they add a per-file classification (delete, edit, comment only, i18n copy), import-break counts and the test-fake count. Where numbers differ from the report above, the cause is the matching rule. This pass used plain `grep -rli`, which also matches words like `complex`. That gives 709 files, against 705 above. Prefer the counts above for totals. Section numbers below are prefixed with A.

## A5. Coupling census

### Method

I ran `grep -rliE "plex|jellyfin|emby"` over `.dart` files in `lib/` and `test/`. 709 of 1,655 Dart files match (991 in `lib`, 664 in `test`). Each match was classified by a script with these rules.
- **Delete.** The path contains `plex`, `jellyfin`, `emby` or `media_browser`. These are the backend implementations and their models, auth screens and tests.
- **Edit.** Neutral code with at least one matching line that is not a `//` comment. These are type references, imports, `switch` arms and `is PlexClient` checks.
- **Comment.** Every matching line is a comment. These compile untouched after the backends go. Only the doc text goes stale.
- **Copy.** Generated i18n Dart under `lib/i18n`. The source is `lib/i18n/*.i18n.json`, and 22 of those files mention a backend (34 matching lines in `en.i18n.json`).

The rule is path-based, so it has known misses. Several Plex-only files have neutral names and land in "edit". Examples are `lib/services/server_registry.dart` (Plex server list), `lib/connection/connection_bootstrap.dart` (legacy Plex prefs migration), `lib/services/play_queue_launcher.dart` ("Plex-specific play queue launcher", line 1) and `PlexServer`, which lives inside `plex_auth_service.dart:350`. Generated `*.freezed.dart` and `*.g.dart` files are counted and are regenerated rather than hand-edited.

### Totals

| | Delete | Edit | Comment only | Copy | Total |
|---|---|---|---|---|---|
| `lib/` | 84 | 128 | 154 | 23 | 389 |
| `test/` | 71 | 238 | 11 | 0 | 320 |
| **All** | **155** | **366** | **165** | **23** | **709** |

58 surviving `lib` files and 94 surviving `test` files import at least one deletable file. Those imports are the compile breaks you hit on deletion. The most-imported deletable files are listed here. The `account_preferences.dart` basename collides with a neutral file, so that figure is inflated.

| Deletable file | Importers that survive |
|---|---|
| `plex_api_cache.dart` | 40 |
| `plex_home_service.dart` | 29 |
| `plex_client.dart` | 27 |
| `jellyfin_api_cache.dart` | 25 |
| `jellyfin_client.dart` | 23 |
| `plex_home_user.dart` | 23 |
| `plex_auth_service.dart` | 19 |
| `media_browser_dialect.dart` | 12 |

In `test/`, 65 files implement or extend `MediaServerClient` (fakes), and 76 reference `PlexClient` or `JellyfinClient`. Every interface signature change touches the 65 fakes.

### By directory

Rows are directories with at least 3 matching files. Smaller rows are in the script output and are omitted here.

| Directory | Delete | Edit | Comment | Copy | Total |
|---|---|---|---|---|---|
| `lib/services` (top level) | 26 | 32 | 15 | 0 | 73 |
| `lib/services/jellyfin_client` | 12 | 0 | 0 | 0 | 12 |
| `lib/services/plex_client` | 5 | 0 | 0 | 0 | 5 |
| `lib/services/seerr` | 0 | 4 | 2 | 0 | 6 |
| `lib/services/trackers` | 0 | 0 | 6 | 0 | 6 |
| `lib/services/catalog` | 1 | 1 | 2 | 0 | 4 |
| `lib/services/library_events` | 2 | 0 | 2 | 0 | 4 |
| `lib/services/companion_remote` | 0 | 2 | 1 | 0 | 3 |
| `lib/utils` | 5 | 8 | 27 | 0 | 40 |
| `lib/media` | 1 | 9 | 29 | 0 | 39 |
| `lib/i18n` | 0 | 0 | 0 | 23 | 23 |
| `lib/models/plex` | 16 | 0 | 0 | 0 | 16 |
| `lib/models` (top level) | 0 | 0 | 7 | 0 | 7 |
| `lib/models/trackers` | 0 | 0 | 3 | 0 | 3 |
| `lib/profiles` | 5 | 9 | 1 | 0 | 15 |
| `lib/screens` (top level) | 1 | 8 | 2 | 0 | 11 |
| `lib/screens/video_player` | 0 | 5 | 9 | 0 | 14 |
| `lib/screens/libraries` | 0 | 4 | 9 | 0 | 13 |
| `lib/screens/settings` | 3 | 3 | 4 | 0 | 10 |
| `lib/screens/livetv` | 0 | 3 | 5 | 0 | 8 |
| `lib/screens/profile` | 0 | 5 | 1 | 0 | 6 |
| `lib/widgets/video_controls` | 0 | 9 | 4 | 0 | 13 |
| `lib/widgets` (top level) | 0 | 6 | 5 | 0 | 11 |
| `lib/providers` | 0 | 7 | 5 | 0 | 12 |
| `lib/database` | 1 | 2 | 2 | 0 | 5 |
| `lib/connection` | 1 | 3 | 0 | 0 | 4 |
| `lib/metadata_edit` | 2 | 1 | 0 | 0 | 3 |
| `test/services` | 50 | 48 | 1 | 0 | 99 |
| `test/widgets` | 0 | 40 | 0 | 0 | 40 |
| `test/utils` | 5 | 27 | 4 | 0 | 36 |
| `test/screens/video_player` | 0 | 13 | 1 | 0 | 14 |
| `test/providers` | 0 | 13 | 0 | 0 | 13 |
| `test/profiles` | 3 | 10 | 0 | 0 | 13 |
| `test/screens` (top level) | 0 | 12 | 1 | 0 | 13 |
| `test/screens/libraries` | 0 | 9 | 1 | 0 | 10 |
| `test/services/trackers` | 0 | 7 | 1 | 0 | 8 |
| `test/media` | 1 | 7 | 0 | 0 | 8 |
| `test/models` | 6 | 1 | 0 | 0 | 7 |
| `test/screens/settings` | 1 | 6 | 0 | 0 | 7 |
| `test/screens/livetv` | 0 | 7 | 0 | 0 | 7 |
| `test/metadata_edit` | 3 | 1 | 0 | 0 | 4 |
| `test/services/catalog` | 1 | 3 | 0 | 0 | 4 |

### Heaviest neutral files to edit

These counts are non-comment matching lines, measured.

| File | Code lines | Why |
|---|---|---|
| `lib/services/multi_server_manager.dart` | 181 | `PlexServer` map, Plex client factory, relay failover |
| `lib/services/track_selection_service.dart` | 125 | Per-backend audio and subtitle stream rules (not read in detail) |
| `lib/profiles/active_profile_binder.dart` | 75 | Plex Home binding and token policy |
| `lib/connection/connection_bootstrap.dart` | 63 | Legacy Plex prefs migration (delete, not edit) |
| `lib/screens/auth_screen.dart` | 47 | Plex PIN, Jellyfin and Emby buttons |
| `lib/profiles/profile.dart` | 44 | `plexHome` variant |
| `lib/providers/companion_remote_provider.dart` | 42 | Plex Home identity |
| `lib/services/file_info_parser.dart` | 38 | |
| `lib/services/cached_playback_metadata_service.dart` | 34 | |
| `lib/utils/active_client_scope.dart` | 33 | |
| `lib/services/download_manager_service.dart` | 31 | |
| `lib/database/app_database.dart` | 29 | Not read in detail. Probably migrations and queries that name backend kinds (guess). |

## A6. Features that exist only because of Plex or Jellyfin

| Feature | Where | Backend tie | Silo equivalent |
|---|---|---|---|
| Plex Discover and universal watchlist | `lib/services/plex_discover_client.dart`, `lib/services/catalog/plex_catalog_source.dart`, `lib/providers/catalog_sources_provider.dart` | plex.tv cloud, scoped to the Plex Home token | None. Other catalog sources (Trakt, Simkl, AniList, MAL, MDBList, Seerr) stay. |
| Plex Home profiles and PIN switch | `lib/profiles/plex_home_*.dart`, `Profile.plexHome` | plex.tv `/home/users` | Local profiles cover it unless Silo has users |
| Plex server list, relay and failover | `plex_auth_service.dart`, `multi_server_manager.dart:534` | plex.tv `/resources` | None needed if Silo is one URL |
| Server-side play queues | `lib/services/plex_client/parts/play_queues.dart`, `lib/services/play_queue_launcher.dart`, `lib/models/plex/play_queue_response.dart` | `/playQueues` | The Jellyfin path already uses `fetchClientSideEpisodeQueue` (`media_server_client.dart:301`) |
| Match / unmatch and subtitle marketplace | `lib/screens/plex_match_screen.dart`, `plex_match_result.dart`, `plex_subtitle_search_result.dart`, flag `externalSubtitleSearch` | PMS agents | None |
| Metadata editing | `lib/metadata_edit/{plex,jellyfin}_metadata_edit_adapter.dart`, `lib/screens/metadata_edit_screen.dart`, flag `richMetadataEdit` | Server edit APIs | Only if Silo exposes edits |
| Live TV and DVR | `lib/screens/livetv/` (11 entries), `LiveTvSupport` and `LiveTvDvrSupport`, client `live_tv*.dart` parts | PMS DVR, `/LiveTv/*` | Unknown. Gate off with `liveTv: false`. |
| Account preferences (server-stored) | `lib/services/{plex,media_browser}_account_preferences_source.dart`, `lib/models/plex/plex_account_preferences.dart`, `lib/models/jellyfin/*` | plex.tv prefs, Jellyfin `UserConfiguration` | Local settings, or a Silo prefs endpoint |
| Companion remote pairing secret | `lib/services/companion_remote/remote_auth_service.dart:15`, `companion_remote_host_controller.dart:23` | Derived from Plex Home metadata or the MediaBrowser server and user id | Needs a new shared-secret source, such as a Silo server id plus user id |
| Seerr sign-in | `lib/services/seerr/seerr_auth_service.dart:185` (`/auth/plex`) and `:195` (`/auth/jellyfin`) | Seerr authenticates through the media server account | Seerr has no Silo auth. Only local Seerr accounts would remain. This depends on what Seerr supports, which I have not checked. |
| Watch together display name | `lib/watch_together/screens/watch_together_screen.dart:109` | Named `_plexDisplayName` but reads the active profile | Rename only |
| Websocket library events | `lib/services/library_events/{plex,media_browser}_library_event_socket.dart` | Per-backend sockets | Optional (`libraryChangeEvents`) |
| Scrub thumbnails | `jellyfin_trickplay_service.dart`, BIF service | Plex BIF, Jellyfin trickplay | Optional (`scrubThumbnails`) |
| Numeric ratings, favourites, hide from Continue Watching | Capability flags | Per backend | Optional |
| Trakt double-scrobble avoidance | `marksWatchedOnPlaybackStopped` (`media_server_client.dart:765`) | Jellyfin Trakt plugin | Silo picks `false` unless it marks played on stop |

## A7. Suggested phase boundaries

Each phase leaves the app compiling and shippable. This ordering is my proposal.

**Phase 1. Add Silo beside the others.**
- Add `MediaBackend.silo` (`lib/media/media_backend.dart:9`). Add the `silo` arms in every exhaustive `switch` the analyzer flags.
- Add the `silo` token key in `CredentialVault._tokenKeyForKind` (`lib/services/credential_vault.dart:132`). Without it the token is stored in plaintext.
- Add a `SiloConnection` subclass of the sealed `Connection` (`lib/connection/connection.dart:13`). Model it on `JellyfinConnection`. Add its arm in `ConnectionRegistry._rowToConnection` (`lib/connection/connection_registry.dart:150`).
- Write `SiloClient implements MediaServerClient` with `ServerCapabilities.silo` set to all false except `videoTranscoding`. Implement `ScopedMediaServerClient` if Silo has users.
- Add `MultiServerManager.addSiloConnection` beside `addJellyfinConnection` (`:802`). Add `_bindSilo` beside `_bindMediaBrowser` (`lib/profiles/active_profile_binder.dart:1105`).
- Add a Silo sign-in screen. Add one button to `AuthScreen` and one card to `AddConnectionScreen`.
- Add a test fake. The 65 existing fakes are untouched because the interface is unchanged.

**Phase 2. Make Silo the default.**
- Remove the Plex, Jellyfin and Emby buttons from `AuthScreen` and `AddConnectionScreen` but keep the code.
- Change the `MediaBackend.fromString` default (`:33`) from Plex to drop-the-row.
- Add a Drift migration (schema 26) that purges `connections` rows of kind `plex`, `jellyfin` and `emby`, their `profile_connections` rows, `api_cache`, `downloaded_media` and dependants, `sync_rules` and `offline_watch_progress`. Existing users get a clean sign-in to Silo.

**Phase 3. Delete Emby and Jellyfin.** Do this first because the MediaBrowser stack is self-contained.
- Delete `JellyfinClient` and its parts, the `jellyfin_*` services, `media_browser_*`, `MediaBrowserDialect`, the add and edit Jellyfin screens, Quick Connect, LAN discovery, `lib/models/jellyfin` and their tests.
- Collapse `usesMediaBrowserApi` branches.
- Drop `SeasonEpisodePagingClient` and `MediaDeletionPermissionClient` if Silo does not use them.
- Expect 25 importers of `jellyfin_api_cache.dart` and 23 of `jellyfin_client.dart` to break (measured above).

**Phase 4. Delete Plex.** This phase is larger and riskier.
- Delete `PlexClient` and its parts, `plex_auth_service.dart` (and `PlexServer` with it), the mappers, `lib/models/plex`, the Plex Discover catalog source, play queues, the match screen and the Plex metadata edit adapter.
- In profiles, delete `plex_home_*.dart` and `active_plex_*.dart`, remove `Profile.plexHome` and `ProfileKind.plexHome`, delete `connection_bootstrap.dart` and `server_registry.dart`, and remove the Plex prefs keys from `StorageService`.
- Strip `_plexServers`, the factory and relay logic from `MultiServerManager`. Strip Plex Home binding from `ActiveProfileBinder`, which should then shrink to the join-row path.
- Re-point the companion remote secret and Seerr sign-in.
- Delete `PlexHomeService` from the provider tree (`lib/main.dart:1643`).

**Phase 5. Remove dead flags and copy.**
- Drop `MediaBackend.plex`, `jellyfin` and `emby`. The exhaustive `switch` arms collapse.
- Remove capability flags Silo will never set. Their UI branches go with them.
- Clean the 22 i18n JSON sources and the 165 comment-only files.

### A7 riskiest couplings

1. **`ActiveProfileBinder` plus `MultiServerManager`.** Together they are 2,827 lines (`lib/profiles/active_profile_binder.dart` 1,162 and `lib/services/multi_server_manager.dart` 1,665) with 256 non-comment backend references (measured). They own cold-start connect, PIN prompts, token rotation and offline routing. A mistake here strands users on the splash or leaks one profile's servers into another, which the binder comments call out (`active_profile_binder.dart:857`).
2. **Persistence keyed by Plex vocabulary and backend ids.** The `connections.kind` and `profiles.kind = 'plex_home'` columns, `ratingKey` and `globalKey` in five download and progress tables, the `profileUserScope` uuid scoping of prefs, and the `MediaBackend.fromString` default to Plex all matter here. A swap without a deliberate migration either signs users out silently (`connection_registry.dart:170`) or leaves downloads that no client can resolve.
3. **The `MediaServerClient` contract surface.** It has 83 members with backend-specific semantics in the doc comments: watch thresholds, double-scrobble rules, hub diagnostics and `excludedLibraryIds` server-side scoping. It also has 65 test fakes. Silo has to meet those contracts or flip capability flags off. Any change to the interface to suit Silo ripples through every fake.
