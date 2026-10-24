# Silo catalog, home, library, and user-state surface

This is the research input for Plezy's Dart Silo client. It covers every server read a non-playback, non-auth TV screen makes in Silo's Android TV app, and the writes those screens trigger for watched, rating, favorite, watchlist, and home dismissal. Playback (`/api/v2/watch`, sessions, progress) and auth are out of scope and live in other research files.

Path prefixes used in citations:

- `S/` is `silo-android/shared/src/commonMain/kotlin/org/siloserver/silo/`
- `A/` is `silo-android/android-shared/src/androidMain/kotlin/org/siloserver/silo/common/`
- `T/` is `silo-android/androidTvApp/src/androidMain/kotlin/org/siloserver/silo/tv/`

Every claim cites the Kotlin source. Claims checked against the live test server say "Measured". Claims taken from the server's public OpenAPI document (`GET https://silo.ruleone.xyz/api/v2/openapi.json`, fetched unauthenticated on 2026-10-11) say "OpenAPI". Anything else that is not read straight from code is labelled "Inferred" or "Guess".

## Common wire rules

- Every request below is under `/api/v2`. Bodies are JSON with snake_case keys. Errors are RFC 9457 problem documents, and the stable error code is the last path segment of `type` (`S/network/apiv2/ApiV2Models.kt:34-46`, `S/network/apiv2/ApiV2Call.kt:50-60`). Measured. An unauthenticated `GET /api/v2/home/sections` answers 401 with `type` ending in `authentication_required`.
- Authenticated requests carry `Authorization: Bearer <token>`, `X-Profile-Id`, and `X-Profile-Token` when the profile is PIN-locked (`S/network/AuthInterceptorImpl.kt:78-83`). OpenAPI marks `X-Profile-Id` as required on `/home/sections` and `/catalog/people`. The token flow is in `silo-auth.md`.
- Before decoding a 2xx body the client rewrites every relative artwork URL to an absolute one against the origin of the request that returned it (`S/network/apiv2/ApiV2Call.kt:36-38`, `S/network/ArtworkUrls.kt:10-37`). See Artwork below.
- A server in the `UPDATE_REQUIRED` contract state blocks every v2 call client-side (`S/network/apiv2/ApiV2Gate.kt:16-30`).
- Cursor pagination uses `page: { has_more, next_cursor }`. `next_cursor` is absent exactly when `has_more` is false (`S/network/apiv2/ApiV2Models.kt:80-85`).

## Endpoint table

Response fields listed are the ones Silo's models decode. Unknown fields are ignored by the decoder.

### Home

| # | Method | Path | Query / body | Response fields used | Source |
|---|---|---|---|---|---|
| 1 | GET | `/api/v2/home/sections` | none sent. OpenAPI also accepts `image_size`. | `sections[]` of `ResolvedSection`. Each row must carry an `items` array, a non-blank `id`, and non-blank `items[].content_id`, or the whole response is rejected. | `S/network/apiv2/HomeSectionsV2Api.kt:13-23,41-44` |
| 2 | GET | `/api/v2/home/sections/{id}/items` | `id` path-encoded | One `ResolvedSection` object (not wrapped). Its `id` must equal the requested id. | `S/network/apiv2/HomeSectionsV2Api.kt:46-55` |
| 3 | PUT | `/api/v2/home/dismissals/{surface}/{itemId}` | `surface` is `continue_watching` or `next_up`. Body is `{"progress_updated_at": "<anchor>"}` for continue_watching, or `{"series_id": "<anchor>"}` for next_up. | 204 No Content | `S/network/apiv2/HomeSectionsV2Api.kt:28-39` |
| 4 | POST | `/api/v2/events/ws-ticket` | none | `WsTicketResponse` with `ticket`, `protocol` (must be `silo.events.v2`), `expires_in` (1..30 s), `max_connection_seconds` (1..300) | `S/network/apiv2/EventsSocketV2Api.kt:24-35,76-80` |
| 5 | WS | `/api/v2/events/ws?channels=user_state,catalog` | `ws`/`wss` on the server origin. `Sec-WebSocket-Protocol: silo.events.v2, silo.ticket.<ticket>`. No `Authorization` or profile headers. First client frame is `{"type":"subscribe","channels":["user_state","catalog"]}`. `request_id` is null and so omitted, because SiloJson drops nulls. | Text frames of `{type, channel?, event?, data?}`. The `subscribed` reply also lists `channels` and `rejected`. See Realtime below. | `S/network/apiv2/EventsSocketV2Api.kt:37-71,82-98`, `S/model/notifications/NotificationModels.kt:222-254`, `S/network/HomeRealtimeClient.kt:55,65-68` |

### Libraries and browsing

| # | Method | Path | Query / body | Response fields used | Source |
|---|---|---|---|---|---|
| 6 | GET | `/api/v2/user/libraries` | none | `items[]` with `id` (decimal string, positive, fits Int), `name`, `type`, `sort_order`, `poster_url?`. `page` must not report more. Duplicate ids are rejected. | `S/network/api/PersonalDataApi.kt:54-61`, `S/network/apiv2/UserLibrariesV2.kt:7-24`, `S/network/apiv2/ApiV2Call.kt:142-146` |
| 7 | GET | `/api/v2/settings/values/effective` | repeated `keys=ui.disabled_library_ids` (also accepts repeated `library_ids`, `series_ids`) | `items[]` of `{key, value, profile_id?, library_id?}` plus `revision` (int). For this key, `value` is a JSON array of library ids, or a legacy JSON string encoding one. | `S/network/apiv2/SettingsV2Api.kt:50-67`, `S/model/settings/SettingKeys.kt:136`, `S/repository/HiddenLibrariesStore.kt:94-111` |
| 8 | GET | `/api/v2/library/{libraryId}/sections` | `libraryId` must be > 0 | Same shape as #1 | `S/network/apiv2/LibrarySectionItemsV2Api.kt:25-30` |
| 9 | GET | `/api/v2/library/{libraryId}/sections/{sectionId}/items` | none | Same shape as #2 | `S/network/apiv2/LibrarySectionItemsV2Api.kt:13-24` |
| 10 | GET | `/api/v2/catalog` | `source`, `scope`, `library_id`, `collection_id`, `person_id`, `section_id`, `type`, `q`, `name_prefix`, `match`, `group`, `query_limit`, `skip_total`, `limit` (client enforces 1..100), `image_size`, `sort` (`-field` means descending), `cursor`. Null params are omitted. Used whenever the query has no rule groups. | `items[]` of `BrowseItem`, `page`, `total`, `total_exact`, `window_cursor`, `effective_sort? {field, order}`, `search_diagnostics?` | `S/network/apiv2/CatalogV2Api.kt:29-82`, `S/network/apiv2/CatalogV2Models.kt:12-31,61-70` |
| 11 | POST | `/api/v2/catalog/query` | Same query as a JSON body (`CatalogQueryV2` field names, `sort` and `order` as separate fields) plus `groups: [{match, rules: [{field, op, value}]}]` and `cursor`. `image_size` stays a query param. Used whenever `groups` is non-empty. | Same as #10 | `S/network/apiv2/CatalogV2Api.kt:35,40-46`, `S/network/apiv2/CatalogV2Models.kt:33-36` |
| 12 | GET | `/api/v2/catalog/filters` | `library_id?`, `source?`, `collection_id?`, `skip_technical` (bool, always sent) | `genres`, `studios`, `networks`, `countries`, `original_languages`, `content_ratings`, `authors`, `narrators`, `series`, `technical? {resolutions, audio_languages, subtitle_languages}` | `S/network/apiv2/CatalogV2Api.kt:110-119`, `S/network/apiv2/CatalogV2Models.kt:99-114` |
| 13 | GET | `/api/v2/catalog/filters/search` | `library_id?`, `source?`, `collection_id?`, `facet`, `q` (prefix), `limit=100` | `matches[]` (strings), `has_more` | `S/network/apiv2/CatalogV2Api.kt:121-131`, `S/network/apiv2/CatalogV2Models.kt:161-162` |
| 14 | GET | `/api/v2/catalog/audiobook-groups` | `library_id`, `group_by` (`author`/`series` on TV), `sort` (`name`), `q?`, `limit`, `skip_total`, `cursor?` | `items[]` of `AudiobookGroup`, `page`, `total`, `total_exact` | `S/network/apiv2/CatalogV2Api.kt:84-108`, `S/model/catalog/CatalogModels.kt:152-160` |
| 15 | GET | `/api/v2/library/{libraryId}/collections` | none | `library_id`, `collections[]` (`CuratedCollectionV2`), `groups[]` (`LibraryCollectionGroupV2`), `ungrouped? {sort_order, collections[]}` | `S/network/apiv2/CatalogV2Api.kt:137-139`, `S/network/apiv2/CatalogV2Models.kt:116-157` |

`source` values the TV app sends to #10/#11 are `query` (library browse, search, networks, movie-collection matching), `section` with `scope=library` (library shelf refill), `library_collection`, `user_collection`, `favorites`, `watchlist`, and `person` (`S/network/api/SectionApi.kt:43-45,86-89`, `S/network/api/CatalogApi.kt:39-41,100-101`, `S/network/api/CollectionApi.kt:181-187`, `S/viewmodel/PersonalListViewModels.kt:313-319,344-350`). OpenAPI lists the same enum plus `history`.

### Catalog detail

| # | Method | Path | Query / body | Response fields used | Source |
|---|---|---|---|---|---|
| 16 | GET | `/api/v2/catalog/items/{id}` | `library_id?` | `ItemDetailReadV2`. `cast`, `crew`, `versions`, `subtitles` are required arrays on the wire. | `S/network/apiv2/CatalogV2Api.kt:141-147`, `S/network/apiv2/CatalogDetailReadV2Models.kt:17-81` |
| 17 | GET | `/api/v2/catalog/items/{id}/versions` | `library_id?` | `items[]` of `FileVersionReadV2`. Must be complete (no continuation). | `S/network/apiv2/CatalogV2Api.kt:165-171` |
| 18 | GET | `/api/v2/catalog/items/{id}/episodes` | `library_id?` | `items[]` of `EpisodeListItemReadV2`. Complete. | `S/network/apiv2/CatalogV2Api.kt:173-179` |
| 19 | GET | `/api/v2/catalog/series/{seriesId}/seasons` | `library_id?` | `items[]` of `Season`. Complete. | `S/network/apiv2/CatalogV2Api.kt:149-155` |
| 20 | GET | `/api/v2/catalog/series/{seriesId}/seasons/{seasonNumber}/episodes` | `library_id?` | `items[]` of `EpisodeListItemReadV2`. Complete. | `S/network/apiv2/CatalogV2Api.kt:157-163` |
| 21 | GET | `/api/v2/catalog/people/{personId}` | none | `PersonReadV2` | `S/network/apiv2/CatalogV2Api.kt:181-184`, `S/network/apiv2/PersonRefreshV2Api.kt:31` |
| 22 | GET | `/api/v2/catalog/people` | `q`, `limit` (1..100, default 20), `media_scope?` | `items[]` of `PersonReadV2`. Complete. | `S/network/apiv2/CatalogV2Api.kt:186-196` |
| 23 | POST | `/api/v2/catalog/people/{personId}/refresh` | none | Unit. Not called by any TV screen (no TV reference to `refreshPerson`). | `S/network/apiv2/PersonRefreshV2Api.kt:20` |
| 24 | GET | `/api/v2/recommendations/similar/{id}` | `limit` (1..50, TV sends 12) | `items[]` of `BrowseItem`. Must be complete, at most `limit` items, unique non-blank `content_id`. | `S/network/apiv2/SimilarCardsV2Api.kt:15-28`, `S/repository/RecommendationRepository.kt:29` |
| 25 | GET | `/api/v2/catalog/search/capabilities` | none | `revision`, `state`, `provider`, `people_media_scope` (bool), `result_window_limit?`, `session_ttl_seconds?`, `max_sessions_per_account?` | `S/network/apiv2/CatalogV2Api.kt:133-135`, `S/network/apiv2/CatalogV2Models.kt:49-59` |

### User collections

| # | Method | Path | Query / body | Response fields used | Source |
|---|---|---|---|---|---|
| 26 | GET | `/api/v2/collections` | none | `items[]` of `Collection`, `groups[]` of `CollectionGroup` | `S/network/api/CollectionApi.kt:118-120`, `S/model/personal/PersonalDataModels.kt:15-44,111-115` |
| 27 | GET | `/api/v2/collections/{id}` | none | `Collection`. The `ETag` header is kept for later conditional edits. | `S/network/api/CollectionApi.kt:78-83,110` |

User-collection items are paged through #10 with `source=user_collection&collection_id=…&limit=…` and an optional `library_id` (`S/network/api/CollectionApi.kt:167-211`). The TV collection editor also writes through `/api/v2/collections/...` (`S/network/api/CollectionApi.kt:122-281`). Those writes are listed in the source but are out of scope here.

### User item state

| # | Method | Path | Query / body | Response | Source |
|---|---|---|---|---|---|
| 28 | POST / DELETE | `/api/v2/watched/{itemId}` | POST marks watched, DELETE marks unwatched. No body. Works on movie, episode, season, and series ids (the TV season toggle sends the season `content_id`). | 204 | `S/repository/port/PersonalWrite.kt:17-21`, `T/ui/screens/detail/TvItemDetailViewModel.kt:928-931` |
| 29 | PUT / DELETE | `/api/v2/ratings/{itemId}` | PUT body `{"rating": 1..5}`. DELETE clears. | 204 | `S/repository/port/PersonalWrite.kt:23-30` |
| 30 | GET | `/api/v2/favorites/{itemId}` | none | `{item_id, added_at}`. A 404 means "not a favorite". | `S/network/apiv2/MembershipV2Api.kt:12-16,30-39` |
| 31 | PUT / DELETE | `/api/v2/favorites/{itemId}` | no body | 204 | `S/network/apiv2/MembershipV2Api.kt:41-54` |
| 32 | GET | `/api/v2/watchlist/{itemId}` | none | Same as #30 | `S/network/apiv2/MembershipV2Api.kt:24,30-39` |
| 33 | PUT / DELETE | `/api/v2/watchlist/{itemId}` | no body | 204 | `S/network/apiv2/MembershipV2Api.kt:27-28,41-54` |
| 34 | GET | `/api/v2/history` | `limit` (40 default), `image_size?`, `cursor?` | History page. Only the TV Explore screen reads it. | `S/network/apiv2/HistoryV2Api.kt:13-24`, `T/ui/screens/explore/TvExploreLibrary.kt:411` |

Favorite and watchlist lists are #10 with `source=favorites` or `source=watchlist` (`S/viewmodel/PersonalListViewModels.kt:313-319,344-350`).

### Artwork

| # | Method | Path | Query / body | Response fields used | Source |
|---|---|---|---|---|---|
| 35 | GET | `/api/v2/images/capabilities` | none | `storage_backend?`, `delivery?` | `S/network/api/ImageCapabilitiesApi.kt:16-31` |

### External calls (not Silo)

| # | Method | URL | Purpose | Source |
|---|---|---|---|---|
| 36 | GET | `https://api.themoviedb.org/3/movie/{tmdbId}` then `/collection/{collectionId}`, `api_key` query param | Movie collection row on detail | `S/network/api/TmdbCollectionApi.kt:20,53-71` |
| 37 | GET | `https://api.themoviedb.org/3/discover/{movie\|tv}` and `/network/{id}/images` | Home "Networks" row | `S/network/api/TmdbNetworkApi.kt:12,37-61` |

That makes 35 Silo endpoints and 2 groups of TMDB calls.

## Domain models for the Dart port

Types are Kotlin types. `?` means nullable, and the decoder default applies when the key is missing. The decoder ignores unknown keys, so a Dart port should do the same.

### `SectionItem` (home and library shelf card)

`S/model/section/SectionModels.kt:8-42`

| Field | Wire key | Type |
|---|---|---|
| contentId | `content_id` | String (required, non-blank) |
| type | `type` | String (required) |
| title | `title` | String (required) |
| seriesId | `series_id` | String? |
| seriesTitle | `series_title` | String? |
| seasonNumber | `season_number` | Int? |
| episodeNumber | `episode_number` | Int? |
| year | `year` | Int, default 0 |
| genres | `genres` | List<String>, default [] |
| status | `status` | String? |
| ratingImdb, ratingTmdb | `rating_imdb`, `rating_tmdb` | Double? |
| ratingRtCritic, ratingRtAudience | `rating_rt_critic`, `rating_rt_audience` | Int? |
| contentRating | `content_rating` | String? |
| runtime | `runtime` | Int? (minutes, inferred from the detail model) |
| originalLanguage | `original_language` | String? |
| studios, networks | `studios`, `networks` | List<String>, default [] |
| showStatus | `show_status` | String? |
| overlaySummary | `overlay_summary` | OverlaySummary? |
| overview | `overview` | String? |
| itemSource | `item_source` | String? |
| positionSeconds, durationSeconds | `position_seconds`, `duration_seconds` | Double? |
| progressUpdatedAt | `progress_updated_at` | String? (RFC 3339 text) |
| posterUrl, posterThumbhash | `poster_url`, `poster_thumbhash` | String? |
| backdropUrl, backdropThumbhash | `backdrop_url`, `backdrop_thumbhash` | String? |
| logoUrl | `logo_url` | String? |
| userState | `user_state` | MediaItemUserState? |

### `ResolvedSection`

`S/model/section/SectionModels.kt:44-58`

`id` String, `section_type` String, `title` String, `featured` Bool (false), `item_limit` Int (0), `total_count` Int (0), `is_custom` Bool (false), `customized` Bool (false), `items` List<SectionItem>. OpenAPI types `section_type` as a free string up to 100 chars that names a server "recipe". It is not a closed enum.

### `MediaItemUserState` and `OverlaySummary`

`S/model/catalog/CatalogModels.kt:23-50`

- `MediaItemUserState` has `played`, `is_favorite`, `in_watchlist`, all Bool default false.
- `OverlaySummary` has `resolution`, `hdr`, `audio`, `audio_channels` (preformatted, for example "5.1"), `video_codec`, `container`, `aspect_ratio`, `release_type`, `edition`, all String?, plus `multi_audio` and `multi_sub` as Bool?.

### `BrowseItem` (catalog grid card, similar card)

`S/model/catalog/CatalogModels.kt:52-91`

Same as `SectionItem` except it has no `logo_url`, and it adds `added_at` String?, `release_date` String?, `last_air_date` String?, and `tmdb_id` String?. `tmdb_id` is decoded leniently. A JSON number or a string is accepted, and anything else becomes null (`S/model/catalog/CatalogModels.kt:93-110`). The TV converts a `BrowseItem` to a `SectionItem` by a JSON round trip (`T/ui/screens/library/TvLibraryMediaScope.kt:44-45`).

### `CatalogPage` (wire) and `CatalogResponse` (domain)

`S/network/apiv2/CatalogV2Models.kt:61-89`, `S/model/catalog/CatalogModels.kt:112-136`

Wire fields are `items` (required), `page` (required), `total` Int (required), `total_exact` Bool (required), `window_cursor` String (required), `effective_sort? {field?, order?}`, and `search_diagnostics?` (`provider`, `mode`, `semantic_used`, `fallback_reason?`, `result_window_limit?`, `session_expires_at?`, `index_pending_updates?`). The domain response adds `hasMore` derived from the continuation.

### `ItemDetail`

`S/network/apiv2/CatalogDetailReadV2Models.kt:17-81`, `S/model/catalog/CatalogModels.kt:190-267`

Required are `content_id`, `type`, `title`, and the arrays `cast`, `crew`, `versions`, `subtitles`. Everything else is optional:

- Text, all String?: `status`, `sort_title`, `original_title`, `original_language`, `show_status`, `overview`, `pending_translation_language`, `tagline`, `content_rating`, `imdb_id`, `tmdb_id`, `tvdb_id`, `release_date`, `first_air_date`, `last_air_date`, `air_date`, `series_id`, `series_title`.
- Numbers. `year` Int (0) and `runtime` Int (0). `season_count`, `season_number`, `episode_number`, `episode_count`, `user_rating` (1..5) are Int?. `rating_imdb` and `rating_tmdb` are Double?, and the two RT ratings are Int?.
- Lists. `genres`, `studios`, `networks`, `countries` are List<String>. `locked_fields` is List<Int>?. `ratings` is List<DisplayRating>? and is absent on older servers (`S/model/catalog/ExternalRatings.kt`).
- Artwork, all String?: `poster_url`, `poster_thumbhash`, `backdrop_url`, `backdrop_thumbhash`, `logo_url`.
- `is_specials` Bool?, `user_data` LeafItemUserData?, `overlay_summary`.
- `playback_variants` List (default []), and `intro`, `credits`, `recap`, `preview` as TimeRange? `{start, end}` Doubles. These are playback inputs.
- `audiobook?`, `book?`, `ebook?` metadata objects.
- `videos` List<ItemVideo>? has `kind`, `site`, `site_key`, `name?`, `language?`, `is_official` Bool.
- `extras` List<ItemExtra>? has `content_id`, `kind`, `title?`, `duration_seconds` Int?, `file_id` Int?.

`CastMember` (`S/model/catalog/CatalogModels.kt:288-300`) has `name`, `character?`, `order` Int (0), `person_id?`, `tmdb_id?`, `tvdb_id?`, `imdb_id?`, `plex_guid?`, `photo_url?`, `photo_thumbhash?`. `CrewMember` (`:302-313`) is the same with `job?` in place of `character` and `order`. `person_id` is a string here even though `Person.id` is a Long.

### `Season`

`S/model/catalog/CatalogModels.kt:464-476,582-588`

`content_id` String, `season_number` Int, `is_specials` Bool (false), `title?`, `overview?`, `air_date?`, `episode_count` Int (0), `poster_url?`, `poster_thumbhash?`, `user_data?` of `SeasonUserData`. `SeasonUserData` has `played` Bool, `watched_count`, `unplayed_count`, `in_progress_count` Int, all defaulting to false or 0.

### `EpisodeListItem`

`S/network/apiv2/CatalogDetailReadV2Models.kt:266-321`, `S/model/catalog/CatalogModels.kt:534-561`

`content_id` String, `season_number` Int, `episode_number` Int (all three required). Optional are `title?`, `overview?`, `air_date?`, `runtime` Int (0), `imdb_id?`, `tmdb_id?`, `tvdb_id?`, `still_url?`, `still_thumbhash?`, `user_data?`, and `files[]`. Each file has `file_id` (decimal string on the wire, Int in the domain), `resolution?`, `codec_video?`, `hdr` Bool, `audio_channels` Int, `container?`, `file_size` Long.

### `LeafItemUserData`

`S/network/apiv2/CatalogDetailReadV2Models.kt:242-264`

`played` Bool (false), `is_in_progress` Bool?, `position_seconds` Double?, `duration_seconds` Double?, `last_file_id` (decimal string on the wire) Int?, `last_resolution?`, `last_hdr` Bool?, `last_codec_video?`.

### `Person`

`S/network/apiv2/CatalogDetailReadV2Models.kt:323-354`

`id` is a decimal string on the wire, decoded to a positive Long. `name` String. All String?: `bio`, `birth_date`, `death_date`, `birthplace`, `homepage`, `photo_url`, `photo_thumbhash`, `tmdb_id`, `imdb_id`, `tvdb_id`, `plex_guid`.

### `UserLibrary`

`S/model/personal/PersonalDataModels.kt:102-109`

`id` Int (wire is a decimal string), `name` String, `type` String, `sort_order` Int, `poster_url?`.

### Library collections

`S/network/apiv2/CatalogV2Models.kt:116-157`, normalized in `S/network/api/SectionApi.kt:52-73`

- `LibraryCollectionCardV2` has `id`, `title`, `poster_url` (required String), `poster_thumbhash?`, `item_count` Int, `featured` Bool, `creator_profile_id?`.
- `CuratedCollectionV2` has `id`, `title`, `library_id`, `library_ids[]`, `collection_type`, `poster_url`, `poster_thumbhash?`, `item_count`, `sort_order`, `group_id?`.
- `LibraryCollectionGroupV2` has `id`, `name`, `kind`, `sort_mode`, `sort_order`, `collections[]`.
- The client maps `kind == "admin"` to `"regular"`. Groups of kind `user_collections` hold profile collections, which must be opened with `source=user_collection` (`T/ui/screens/library/TvLibraryDetailViewModel.kt:55-63`).

### `AudiobookGroup`

`S/model/catalog/CatalogModels.kt:152-160`

`name`, `item_count`, `total_duration_seconds` Long?, `in_progress_count`, `finished_count`, `poster_urls[]`.

### `Collection` (user collection)

`S/model/personal/PersonalDataModels.kt:15-35`

`id`, `name`, `collection_type` (default `manual`), `is_shared`, `allowed_profile_ids[]`, `sort_order`, `item_count?`, `poster_url?`, `poster_thumbhash?`, `profile_id?`, `creator_profile_id?`, `description?`, `query_definition?`, `sort_config?`, `group_id?`, `include_in_server_collections?`, `created_at?`, `updated_at?`.

## Screen-to-call map (TV)

| TV screen | Entry | Calls, in order | Source |
|---|---|---|---|
| Home | shared `HomeViewModel` | (1) read the cached home for the current server and profile and show it, then (2) `GET /home/sections`, then (3) `GET /home/sections/{id}/items` only for sections with empty `items` and `total_count > 0`, at most 4 at once. Rows still empty after that are dropped. (4) Cache the result only if every fallback succeeded. Resume and realtime trigger a quiet refetch. Dismiss sends #3. | `S/viewmodel/HomeViewModel.kt:149-204,239-330,412-446`, `S/viewmodel/HomeSectionHydrator.kt:22-55`, `T/ui/screens/home/TvHomeScreen.kt:87-128` |
| Home, Networks row | `NetworksRepository` | Pages #10 with `type=movie` and `type=series`, `sort=title`, `limit=100`, then matches the titles against TMDB discover (#37) | `S/repository/NetworksRepository.kt:102-127,516-541`, `T/ui/screens/home/TvHomeScreen.kt:93-105` |
| Libraries list | `TvLibrariesViewModel` | #6 and #7 in parallel, then drop hidden ids. A background recheck re-reads #6 once if a known id is missing. | `T/ui/screens/libraries/TvLibrariesViewModel.kt:73,104-106`, `S/repository/PersonalDataRepository.kt:56-117` |
| Library, Recommended tab | `TvLibraryDetailViewModel.loadRecommended` | #8, then #9 for un-inlined sections, then optional #10 `source=section&scope=library&section_id=…&limit=100` refills when a media scope filter is active. Featured sections are excluded. | `T/ui/screens/library/TvLibraryDetailViewModel.kt:421-520`, `T/ui/screens/library/TvLibraryMediaScope.kt:20-50`, `T/ui/screens/library/TvLibraryDetailScreen.kt:313` |
| Library, Browse / Genres / A-Z / Recently Added | `loadBrowse` | #12 (`skip_technical=false`) once, then #10/#11 `source=query&library_id=…&limit=100` with sort, genre, name prefix, facet groups | `T/ui/screens/library/TvLibraryDetailViewModel.kt:529-600` |
| Library, Authors / Series (audiobooks) | `loadAudiobookGroups` | #14 `sort=name&limit=100` | `T/ui/screens/library/TvLibraryDetailViewModel.kt:686-695` |
| Library, Collections tab | `loadCollections` | #15. Groups and the ungrouped bucket are sorted by `sort_order`. | `T/ui/screens/library/TvLibraryDetailViewModel.kt:737-810` |
| Library collection detail | `TvLibraryCollectionDetailViewModel` | #12 with `source`/`collection_id`, then #10/#11 `source=library_collection&collection_id=…&limit=60`. No `sort` is sent by default, which keeps the collection's own order. | `T/ui/screens/library/TvLibraryCollectionDetailViewModel.kt:102,178`, `S/network/api/SectionApi.kt:74-89` |
| Facet picker | `TvLibraryBrowseControls` | #13 | `T/ui/screens/library/TvLibraryBrowseControls.kt:680` |
| Item detail | `TvItemDetailViewModel.loadAll` | cached detail first, then in parallel #30 and #32, and #16. Series, season, or episode then triggers #19 and #20 for the chosen season. Then #24 (`limit=12`, skipped for episodes) and the TMDB movie collection (#36 plus #10 `q=title&type=movie` matching). | `T/ui/screens/detail/TvItemDetailViewModel.kt:523-685,2225-2250`, `S/repository/MovieCollectionRepository.kt:34-42,72-76` |
| Item detail actions | same | Watched toggles #28 on the item. Season watched toggles #28 on the season id. Favorite and watchlist use #31 and #33. Rating uses #29. A cast tap without `person_id` uses #22 `q=name` and picks the exact name match. | `T/ui/screens/detail/TvItemDetailViewModel.kt:492-503,776-827,928-931,1012-1045` |
| Person detail | `TvPersonDetailViewModel` | #21, then #10 `source=person&person_id=…&sort=year` (desc). Per-media-type probes use `limit=1` to read totals. | `T/ui/screens/people/TvPersonDetailViewModel.kt:120,160,228`, `S/network/api/CatalogApi.kt:98-101` |
| Search | `TvSearchViewModel` | On open, #12 (no library) for genre chips and #6 for media-type chips. Typing is debounced 300 ms, then #10 `source=query&q=…&type=…&limit=40`. In parallel #25, and only if `people_media_scope` is true, #22 once per scope. | `T/ui/screens/search/TvSearchViewModel.kt:30-47,88-120,151-152,186,240-300`, `S/repository/SearchPeople.kt:23-58` |
| Favorites / Watchlist | `TvPersonalScreens` | #10 `source=favorites` or `source=watchlist`, plus #12 with that `source` | `S/viewmodel/PersonalListViewModels.kt:313-350`, `T/ui/screens/personal/TvPersonalListControlsViewModel.kt:106-108` |
| Collections | `CollectionsViewModel`, `TvCollectionDetailViewModel` | #26, then #27, then #10 `source=user_collection` | `S/viewmodel/CollectionsViewModel.kt:83,90`, `T/ui/screens/collections/TvCollectionDetailViewModel.kt:71,112` |
| Any signed-in session | `ImageCapabilitiesSession` | #35 once per identity change. It is best effort, and artwork never waits for it. | `S/repository/ImageCapabilitiesSession.kt:20-43` |

## Behaviour the screens apply to the data

### Home

- **Section order.** The server order is kept. A local, per-profile and per-server layout then reorders by remembered id and hides ids the viewer turned off. Unknown ids keep their server position after the remembered ones (`T/data/preferences/TvHomeSectionPreferences.kt:161-187`). The layout lives on the device, not on the server (`T/data/preferences/TvHomeSectionPreferences.kt:59,198-201`).
- **Normalization.** Items whose `type` is ebook-like are removed, and a section left empty is removed (`T/ui/util/TvMediaTypeFilters.kt:10,32-36`). A progress row with audiobook items is split into the original row and a synthetic `continue_listening` row with id `<id>-continue-listening` (`T/ui/screens/home/TvHomeSections.kt:9-47`).
- **Progress rows.** A section is a progress row when its lowercased `section_type` contains `continue`, `in_progress`, `next_up`, or `up_next`. Progress rows render backdrop cards and others render posters (`T/ui/components/TvSkylineSectionFeed.kt:1022-1034`, `T/ui/screens/home/TvHomeSections.kt:17-21`). Selecting a `continue`/`in_progress` card resumes directly.
- **Episode cards.** An episode card opens the series detail with `season_number` and the episode id preselected (`T/ui/screens/home/TvHomeScreen.kt:356-375`).
- **For You row.** It is detected by `section_type` in `for_you`/`foryou`/`recommendations` or by title (`T/ui/screens/home/TvHomeScreen.kt:388-395`).
- **Featured flag.** No TV screen calls `splitFeatured`, so Home has no featured hero from this flag. Inferred from a grep with no hits under `T/`.
- **Dismiss rules.** A dismiss is only sent when the visible card's anchor still matches. The anchor is `progress_updated_at` for continue watching and `series_id` for next up. On success the card is removed from every progress row (`S/viewmodel/HomeViewModel.kt:412-446`).
- **Watched toggle on Home.** It is optimistic. On success Home is refetched, and on failure the change is rolled back (`S/viewmodel/HomeViewModel.kt:386-398`).

### Realtime

- Frames decode as `{type, channel, event, data}`. `type=subscribed` means connected or reconnected, and the client refetches. `type=event` on channel `catalog` (any event) means the catalog changed, and the client refetches. `channel=user_state` with `event=user_state.changed` carries `data {profile_id, content_id?, series_id?, change}`, and the client refetches only if `profile_id` is the active profile (`S/network/HomeRealtimeClient.kt:14-22,76-114`). `change` is one of progress, favorite, watchlist, history, watched, home_dismissal.
- The socket never carries data. Every trigger becomes a REST refetch of `/home/sections`.
- Triggers are debounced with a 2 s trailing window. Reconnect backoff starts at 1 s, doubles, caps at 30 s, and resets once a frame arrives (`S/repository/HomeRealtimeCoordinator.kt:28-67`).
- A ticket is single use. A failed upgrade is never retried with the same ticket (`S/network/apiv2/EventsSocketV2Api.kt:46-48`).

### Library browse

- **Tabs.** Recommended, Collections, Browse, Genres, A-Z, Recently Added. Authors and Series appear for audiobook libraries (`T/ui/screens/library/TvLibraryDetailViewModel.kt:37-46`).
- **Sort keys.** Video libraries offer `title`, `added_at`, `release_date`, `year`, `rating_imdb`, `runtime`, `resolution`. Audiobook libraries offer `title`, `author`, `narrator`, `series`, `added_at`, `runtime`. The default order is `asc` for name-like keys and `desc` for the rest (`T/ui/screens/library/TvLibraryDetailViewModel.kt:69-139,894-911`).
- **Sort direction on the wire.** It goes out as `sort=-field` for descending on GET, or as separate `sort`/`order` fields on POST (`S/network/apiv2/CatalogV2Api.kt:64`).
- **Tab defaults.** Browse opens Title A-Z. Recently Added uses `added_at` desc. A-Z sorts by title asc with `name_prefix` (`T/ui/screens/library/TvLibraryDetailViewModel.kt:826-880`).
- **First-letter jump.** `name_prefix` is null for "All", `#`, or a single letter `A`..`Z` (`T/ui/components/TvAlphabetRail.kt:86-87,180-189`). OpenAPI says it matches the start of the sort title, or the title when there is no sort title.
- **Genre.** It becomes the rule group `{match: all, rules: [{field: genre, op: contains, value}]}`, which forces POST `/catalog/query` (`S/network/api/CatalogApi.kt:25-41`).
- **Facets.** Each selected facet becomes its own group, `{match: any, rules: [...]}`. The fields are `genre` (contains), `studio`, `network`, `country`, `content_rating`, `resolution`, `audio_language`, `subtitle_language`, `original_language`, `author`, `narrator`, `series` (op `is`), and decades as `year between [start, start+9]`. The top-level `match` is `all` or `any` (`T/ui/screens/library/TvLibraryBrowseFacets.kt:207-232`, `T/ui/screens/library/TvLibraryDetailViewModel.kt:593-597`).
- **Library type to catalog `type`.** `movie`/`movies` map to `movie`. `series`/`shows`/`tv` map to `series`, and the Browse tab can switch to `episode`. `audiobook(s)` maps to `audiobook`. Any other type sends no `type` (`T/ui/util/TvMediaTypeFilters.kt:44-49`, `T/ui/screens/library/TvLibraryDetailViewModel.kt:817-824`, `S/model/catalog/SeriesBrowseUnit.kt:3-11`).
- **Hidden library types on TV.** `ebook(s)`, `book(s)`, `comic(s)`, `manga`, `reading` (`S/model/navigation/MediaMode.kt:52-62`, `T/ui/util/TvMediaTypeFilters.kt:10`).

### Detail

- **Season order.** Numbered seasons come first and specials (`is_specials` or number 0) come last (`S/model/catalog/CatalogModels.kt:483-493`).
- **Initial season.** The route's season wins. Then the first season with `in_progress_count > 0`, then the first partly watched, then the first not `played`, then the first (`S/model/catalog/CatalogModels.kt:495-531`).
- **Next-up episode within the season.** The first episode with `is_in_progress`, then the first not `played`, then the first (`T/ui/screens/detail/TvItemDetailViewModel.kt:1835-1839`). There is no separate next-up endpoint in the detail flow. Home's `next_up` section is the only server-side next-up.
- **Trailers rail.** YouTube `videos` come first, in server order. Then local `extras`. Non-YouTube sites are dropped. YouTube thumbnails come from `https://i.ytimg.com/vi/<key>/hqdefault.jpg` (`S/model/catalog/TrailerRail.kt:39-47`).
- **Similar.** Hidden types and the source item are dropped (`T/ui/screens/detail/TvItemDetailViewModel.kt:2513-2514`).
- **Movie collection.** It needs `tmdb_id` on the detail and a TMDB API key. Without both the row is hidden (`S/repository/MovieCollectionRepository.kt:62,72-76`).

## Artwork

- **URLs come from the server.** No client code builds an image path from an id. Fields named `poster_url`, `backdrop_url`, `logo_url`, `avatar_url`, `photo_url`, `still_url`, `thumbnail_url`, and each entry of `poster_urls` are resolved against the origin of the response that contained them, but only when the value starts with a single `/`. Absolute and protocol-relative values are left untouched, and so are signed queries (`S/network/ArtworkUrls.kt:10-37`).
- **Resolution happens at decode time.** It runs before caching, so cached JSON already holds absolute URLs (`S/network/ArtworkUrls.kt:19-21`).
- **No credentials on image requests.** The image loader sends no Silo login or profile headers (`A/images/SiloImageLoader.kt:36-39`). Inferred from the expiry parser below: artwork URLs are presigned, using `exp`/`sig`, S3 `X-Amz-*`, or Cloudflare `verify=` (`S/repository/NetworksRepository.kt:561-588`). A cached card can therefore expire. The Networks row refreshes posters before expiry, and Home refetches on resume.
- **Sizes.** The server accepts `image_size` of `small`, `medium`, `large`, or `original` on catalog, home, and history reads (OpenAPI). The TV catalog, home, and library calls send none. Only shuffles send `large` (`S/network/apiv2/ShufflesV2Api.kt:83`). The default variant is unknown.
- **Thumbhash.** `*_thumbhash` fields are base64 ThumbHash strings, decoded to a 32x32 or smaller placeholder (`A/ui/components/ThumbhashImage.kt:75-97`).
- **Logos.** `logo_url` exists on `SectionItem`, `ItemDetail`, and `WatchDetail`. It is absent from `BrowseItem`.
- **Image capabilities.** `/images/capabilities` is fetched but no reader of `storage_backend`/`delivery` is in scope here. Guess. It is diagnostic only.

## Port notes for Dart

1. **Ids are strings on the wire.** `content_id`, `series_id`, collection ids, and section ids are opaque strings. Library, person, and file ids are decimal strings that Silo converts to positive Int or Long and rejects if they are JSON numbers (`S/network/apiv2/CatalogDetailReadV2Models.kt:359-379`, `S/network/apiv2/ApiV2Call.kt:142-146`). Keep them as `String` in Dart, and parse only where an Int is needed (`library_id` query params). `CastMember.person_id` is a string, and the TV parses it with `toLongOrNull` (`T/ui/screens/detail/TvItemDetailViewModel.kt:493`).
2. **Path-encode every id** before putting it in a path (`encodeURLPathPart` throughout).
3. **Cursor pagination.**
   - Send the same query on every page and add only `cursor`. Never mix pages from different queries. Silo keys a continuation by `METHOD/catalog:<image_size>:<query JSON>` and refuses a cursor from another query (`S/network/apiv2/CatalogV2Api.kt:36-38`).
   - Treat `has_more=true` with a missing or repeated `next_cursor` as an error, and restart from page one (`S/network/apiv2/CatalogV2Api.kt:208-213`).
   - A server `invalid_cursor` problem also means "reload from page one" (`S/network/apiv2/CatalogV2Api.kt:216-217`).
   - Cursors are never persisted (`S/network/apiv2/CatalogV2Models.kt:72-78`).
4. **Page size.** Silo enforces 1..100 client-side (`S/network/apiv2/CatalogV2Api.kt:34`). OpenAPI allows up to 200. Matching Silo means staying at 100 or below. The TV uses 100 for library browse, 40 for search, 60 for library collections, and 40 for user collections.
5. **GET versus POST.** Use `GET /catalog` when there are no rule groups. Use `POST /catalog/query` as soon as any group exists, including the implicit genre, year, and content-rating groups (`S/network/api/CatalogApi.kt:25-41`, `S/network/apiv2/CatalogV2Api.kt:35`).
6. **Detail collections are complete reads.** Seasons, episodes, versions, and people search must arrive with no continuation. Silo rejects a partial envelope (`S/network/apiv2/CatalogV2Api.kt:198-202`).
7. **Section payloads are inline.** `/home/sections` and `/library/{id}/sections` already embed items. Only call `/items` for a section with empty `items` and `total_count > 0` (`S/viewmodel/HomeSectionHydrator.kt:29`). `total_count` is not an exhaustion signal for library shelves (`T/ui/screens/library/TvLibraryMediaScope.kt:30-31`).
8. **Cache keys.**
   - Home is cached as one JSON blob per (server id, profile id) under key `home-sections-v2`, scoped by identity. It is only written for a fully resolved fetch, and skipped above 1.5 MB (`A/data/repository/RoomHomeCacheRepository.kt:34-66,122`, `S/repository/port/HomeCachePort.kt:22-24`).
   - Catalog cache keys are `libraries`, `library:<id>` (only the unfiltered first page with sort `added_at` desc), `library-sections-v2:<id>`, `item-detail:<contentId>`, `seasons:<seriesId>`, and `episodes:<seriesId>:<season>` (`A/data/repository/RoomCatalogCacheRepository.kt:89-90,173-179`, `S/repository/CatalogRepository.kt:96-105`).
   - Library-scoped detail reads (`library_id` set) are never cached (`S/repository/CatalogRepository.kt:158-163`).
   - The cache serves only when the network fails (`canServeCache`).
9. **Identity fencing.** Every Silo read checks that the server, account, and profile did not change during the request, and drops the result if they did. A Dart port needs the equivalent: a generation counter bumped on profile switch, checked before publishing (`S/repository/CatalogRepository.kt:398-405`, `S/repository/HiddenLibrariesStore.kt:63-81`).
10. **Hidden libraries are a preference, not access control.** Filter `ui.disabled_library_ids` out of `/user/libraries` on the client. Parse it as an array of positive whole numbers, or as a JSON string containing such an array, and drop strings and non-integers (`S/repository/HiddenLibrariesStore.kt:21-31,94-111`).
11. **Membership reads.** A 404 on `GET /favorites/{id}` or `GET /watchlist/{id}` means "not present", not an error. The response `item_id` must equal the requested id (`S/network/apiv2/MembershipV2Api.kt:34-38`).
12. **Writes are single-attempt.** Watched, rating, favorite, watchlist, and dismissal writes are sent once and not retried automatically (`S/network/api/PersonalDataApi.kt:43`, `S/network/apiv2/MembershipV2Api.kt:51`). Watched and rating writes expect 204 (`S/network/api/PersonalDataApi.kt:45`).
13. **Unknown enum values.** Silo keeps `section_type`, `type`, `kind`, and similar values as raw strings (`S/network/apiv2/ApiV2Enums.kt:6-11`). Use `String` in Dart, not closed enums.
14. **`library_id` on detail.** Pass it only when the user came from a specific library. It changes which versions are listed, and Silo skips the cache and the request coalescing in that case (`S/repository/CatalogRepository.kt:158-163`).

## Open questions

1. **Full set of `section_type` values.** OpenAPI types it as a free string (a "recipe" name), and the client only pattern-matches substrings. The full list needs the server's section recipe catalog or an authenticated `/home/sections` sample. Values seen in client code are `continue_watching`, `in_progress`, `next_up`, `up_next`, `recently_added`, `for_you`, `recommendations`, `trending*`, `popular*`, `genre`, `collection`, `watchlist`, `favorites`. Several of those come from non-home code, so treat the list as a guess.
2. **What `name_prefix=#` matches.** The TV sends a literal `#`, and the server semantics (digits, symbols, or both) are not in the client or the OpenAPI description.
3. **Default artwork variant when no `image_size` is sent**, and the URL lifetime of presigned artwork. Neither is visible without an authenticated response.
4. **Sort field naming.** The TV sends `rating_imdb`, but OpenAPI's sort description lists `rating`. Whether both are accepted needs an authenticated test.
5. **`user_state` and `catalog` event names.** Only `user_state.changed` is named. Any `catalog` channel event triggers a refetch, so the specific catalog event names were not needed by Silo and are not documented here.
6. **TMDB features.** The Networks row and movie-collection row need a TMDB API key in the app build. Whether Plezy wants to ship TMDB calls at all is a product decision, not a wire question.
