# Silo playback research

This file is for whoever ports Plezy's player onto the Silo backend. It lists the calls that Silo's Android TV app makes to play one item, how it reports progress and stops, how it handles subtitles and downloads, and what an mpv-based player must copy so the server accepts it.

Every claim cites a source line. The source is the Silo Android repo at `/home/mine/Desktop/silo-android/silo-android`. Path prefixes used below:

| Prefix | Expands to |
|---|---|
| `S/` | `shared/src/commonMain/kotlin/org/siloserver/silo/` |
| `A/` | `android-shared/src/androidMain/kotlin/org/siloserver/silo/common/` |
| `T/` | `androidTvApp/src/androidMain/kotlin/org/siloserver/silo/tv/` |

Labels used: **measured** means checked against the test server. **Inferred** means read from code but not exercised. **Guess** means neither.

## 1. Endpoint table

Every call below is authenticated. Each sends `Authorization: Bearer <access>` and `X-Profile-Id`, plus `X-Profile-Token` when the profile has one (`S/network/AuthInterceptorImpl.kt:844-858`). The API client also adds `X-Silo-Device-Id`, `X-Silo-Device-Name` and `X-Silo-Device-Platform`, plus optional `X-Silo-Client*` headers (`S/network/AuthInterceptorImpl.kt:899-911`). An unauthenticated `GET /api/v2/playback/capabilities` on `https://silo.ruleone.xyz` returned 401 (measured, 2026-10-11).

| Method | Path | Params / body fields sent | Response fields used | Source |
|---|---|---|---|---|
| GET | `/api/v2/watch/{content_id}` | query `library_id` (optional) | `content_id`, `versions[]` (`file_id` as a string, `duration_seconds`, `audio_tracks`, `subtitle_tracks`, `effective_audio_track_index`), `intro`/`credits`/`recap`/`preview` `{start_seconds,end_seconds}`, `user_data` (`position_seconds`, `last_file_id`) | `S/network/apiv2/WatchDetailV2Api.kt:14-21`, `:25-55`; `S/model/catalog/CatalogModels.kt:318-340`, `:571-580`, `:593-617` |
| GET | `/api/v2/playback/capabilities` | none | `installation_id`, `state` (must be `available`), `allowed`, `protocol_versions` (must contain 3), `features` (must contain `sequenced_progress_v1`) | `S/network/apiv2/PlaybackV2Api.kt:33-39`, `:96-99`; `S/repository/SequencedPlayback.kt:191-205` |
| GET | `/api/v2/account/me` | none | `id` (journaled as the account id) | `S/network/apiv2/PlaybackV2Api.kt:101-103`; `S/repository/SequencedPlayback.kt:213-217` |
| POST | `/api/v2/playback/start` | `PlaybackStartRequestV3` plus `installation_id`. `file_id` is re-encoded as a string. Expects **201**. Sent once with no retry. | `protocol_version`, `server_features`, `outcome`, `session_id`, `playback_plan`, `terminal` | `S/network/apiv2/PlaybackV2Api.kt:69-74`, `:106-112`; `S/model/playback/PlaybackProtocolV3.kt:160-168`, `:418-444` |
| POST | `/api/v2/playback/{session_id}/replan` | `PlaybackReplanRequestV3` plus `installation_id`. Expects **200**. Sent once. | same decision shape as start | `S/network/apiv2/PlaybackV2Api.kt:76-78`, `:114-121`; `S/model/playback/PlaybackProtocolV3.kt:454-487` |
| POST | `/api/v2/playback/{session_id}/progress` | `installation_id`, `sequence`, `position` (seconds), `is_paused`. Expects **200**. One refresh-and-resend after a 401 is allowed. | `outcome` (`applied`, `replayed` or `stale_sample`), `accepted{sequence,position,is_paused}` | `S/network/apiv2/PlaybackV2Api.kt:23-29`, `:41-50`, `:136-151` |
| DELETE | `/api/v2/playback/{session_id}` | JSON body `installation_id`, `stop_id`, plus optional `sequence`, `position`, `is_paused`. Expects **200**. | `outcome` (`stopped` echoing `stop_id`, or `replayed`) | `S/network/apiv2/PlaybackV2Api.kt:53-66`, `:154-170` |
| POST | `/api/v2/playback/route-events` | `PlaybackRouteEventV3` plus `installation_id` and `event_id`. Expects **202**. | receipt must echo `event_id` with `outcome: "accepted"` | `S/network/apiv2/PlaybackV2Api.kt:80-84`, `:124-134`; `S/model/playback/PlaybackProtocolV3.kt:490-504` |
| POST | `/api/v2/playback/sessions/{session_id}/control/ws-ticket` | body `{installation_id}` | `ticket`, `expires_in` (1..30), `max_connection_seconds` (1..14400), `protocol` = `silo.playback-control.v2` | `S/network/PlaybackRealtimeClient.kt:113-136`, `:270-275`; `S/model/notifications/NotificationModels.kt:134-139` |
| WS | `/api/v2/playback/sessions/{session_id}/control/ws` | `Sec-WebSocket-Protocol: silo.playback-control.v2, silo.ticket.<ticket>`. No bearer or profile headers. | `command` and `event` frames | `S/network/PlaybackRealtimeClient.kt:277-291` |
| (media) GET | `playback_plan.stream.url` | headers from `stream.headers` plus session auth (section 6) | bytes, an HLS playlist, or segments | `S/model/playback/PlaybackProtocolV3.kt:285-296` |
| (media) GET | `subtitle.inventory[].url` or `subtitle.artifact.url` | same as the stream, or captured proxy headers | `.ass`, `.ssa`, `.srt`, `.vtt` or `.sup` | `S/network/apiv2/ProxyAuxiliaryV2.kt:6-8`, `:27-44` |
| POST | `/api/v2/auth/refresh` | `{refresh_token}` (the `RefreshRequest` model) | `access_token`, `refresh_token`, `expires_in` | `A/player/MediaAuthSession.kt:201-211` |
| GET | `/api/v2/subtitles/{media_file_id}` | none | `subtitles[]` (`id`, `media_file_id`, `provider`, `language`, `format`, `release_name`, `score`, `hearing_impaired`, `created_at`, `timing`, `sync`) | `S/network/apiv2/SubtitleReadsV2Api.kt:33-40`; `S/network/apiv2/SubtitleDownloadV2Api.kt:21-39` |
| POST | `/api/v2/subtitles/search` | `media_file_id` (string), `languages[]` (at most 100) | `results[]`, `warnings[]` | `S/network/apiv2/SubtitleReadsV2Api.kt:12-23`, `:41-47` |
| POST | `/api/v2/subtitles/download` | `media_file_id` (string), `provider`, `subtitle_id`, `language`, `release_name`, `score`, `hearing_impaired`. Sent once. | `subtitle` (stored row) | `S/network/apiv2/SubtitleDownloadV2Api.kt:12-20`, `:45-56` |
| GET/POST/PUT | `/api/v2/subtitles/sync/status`, `/api/v2/subtitles/{file}/sync`, `/api/v2/subtitles/{file}/sync/{key}`, `.../timing` | `sync_key` from the inventory | sync state | `S/network/apiv2/SubtitleSyncV2Api.kt:27-89` |
| GET/POST | `/api/v2/subtitles/ai/{status,quota,translate,jobs,jobs/{id},jobs/{id}/cancel}` | see the interface docs | AI subtitle jobs | `S/network/api/SubtitlesApi.kt:27-52` |
| GET | `/api/v2/capabilities/downloads` | none | `DownloadCapability` | `S/network/apiv2/DownloadRegistryV2Api.kt:91-94` |
| POST | `/api/v2/downloads` | query `limit=100`, `cursor`. Body `content_id`, `episode_id`, `media_file_id` (string), `quality` (default `original`), `caps`. Expects **202**. | created record(s) | `S/network/apiv2/DownloadCreationV2Api.kt:32-54` |
| GET | `/api/v2/downloads` | `limit=100`, `cursor` | page of records | `S/network/apiv2/DownloadRegistryV2Api.kt:61-68` |
| PATCH | `/api/v2/downloads/{id}` | `status` (`downloading` or `completed`), `updated_at`, `revision` | record | `S/network/apiv2/DownloadRegistryV2Api.kt:106-118` |
| DELETE | `/api/v2/downloads/{id}` | none. Expects 204. | none | `S/network/apiv2/DownloadRegistryV2Api.kt:96-98`, `:47` |
| GET | `/api/v2/downloads/{id}/file` | `Range`, `If-Range`, `Accept-Encoding: identity` | file bytes | `A/downloads/DownloadWorker.kt:219-241` |
| GET | `/api/v2/downloads/{id}/manifest` | none | offline track assets | `A/downloads/OfflineTrackAssetFetcher.kt:103` |

## 2. Playback start sequence (Android TV)

The TV entry point is `TvVideoPlaybackStarter.start` (`T/ui/screens/player/TvVideoPlaybackStarter.kt:66`). Steps in order:

1. **Reachability gate.** The app refuses to start when the server is known unreachable (`T/.../TvVideoPlaybackStarter.kt:70-72`). The TV app plays streams only and has no downloads (`T/.../TvVideoPlaybackStarter.kt:67-69`).
2. **Watch detail.** `GET /api/v2/watch/{content_id}` (`T/.../TvVideoPlaybackStarter.kt:84`). Zero `versions` is a hard failure (`:97-103`).
3. **Pick a version (file).** In priority order: an explicit preferred file id, then the carried episode intent, then `selectPlaybackVersion` (`T/.../TvVideoPlaybackStarter.kt:520-541`). `selectPlaybackVersion` returns `user_data.last_file_id` if it is present. Otherwise, for `auto` or `original`, it returns the best version by resolution rank, then bitrate, then size. For other values, it returns the highest version at or below the preferred height (`S/playback/PlaybackVersionSelector.kt:5-29`).
4. **Pick the audio track.** In priority order: an explicit index, then the carried index, then a stored fingerprint, then the best compatible track for the preferred language (`T/.../TvVideoPlaybackStarter.kt:483-501`). The index is the **list ordinal** in `audio_tracks`, not `AudioTrack.index`. The wire carries no audio index, so `AudioTrack.index` is always 0 (`T/.../TvVideoPlaybackStarter.kt:554-557`).
5. **Pick the subtitle track.** The resolved index is sent only when it is `>= 0` (`T/.../TvVideoPlaybackStarter.kt:576-584`). Off means the field is omitted. The server rejects `-1` with 400 (`A/player/PlaybackSessionManager.kt:364-373`).
6. **Detect capabilities.** The app builds `client_capabilities` and `client_playback_context` with `form_factor = "tv"` (`T/.../TvVideoPlaybackStarter.kt:175-184`). The context declares three delivery classes. `original_http` is enabled (`A/player/PlaybackCapabilityDetector.kt:513-579`). `progressive` is disabled with `failure_reason: disabled_pending_seekable_transport` (`:580-604`). `hls` is enabled (`:605-638`). Every enabled class sets `auth_header_refresh: true` (`:560`, `:637`).
7. **Resume position.** The app uses an explicit override if one exists. Otherwise it uses `user_data.position_seconds` when that is above 0 (`S/model/playback/PlaybackStartPosition.kt:17-22`). It then applies a resume rewind, which is a per-profile setting with default 7 s (`T/.../TvVideoPlaybackStarter.kt:208-222`). The rewind is skipped for Start Over (override exactly `0.0`), for explicit overrides, for Watch Together, and for resumes under 30 s (`S/model/playback/PlaybackStartPosition.kt:15`, `:40`, `:59-72`).
8. **Build `PlaybackStartRequestV3`** (`A/player/PlaybackSessionManager.kt:352-381`):
   - `protocol_version: 3`.
   - `client_features` is always `playback_plan_v3`, `client_video_transformations_v1`, `device_quirks_v1`, `seek_reanchor_v1` and `direct_stream_resume_v1`. It adds `embedded_subtitles_v1` and `layout_aware_passthrough` only when backed by capability data (`S/model/playback/PlaybackProtocolV3.kt:91-118`).
   - `file_id`, `profile_id`, and a fresh UUID `playback_attempt_id`.
   - `quality_preference` (lowercased, default `auto`) and `bandwidth_cap_kbps` from the bitrate setting. The cap is only applied from what the request carries (`A/player/PlaybackSessionManager.kt:285-295`).
   - `subtitle_fidelity_preference` (default `preserve`) and `progress_persistence` (default `server`). `client` requires `start_position` (`A/player/PlaybackSessionManager.kt:296-297`, `:333-339`).
   - `audio_track_id` and `subtitle_track_id` in the form `file:{fileId}:{kind}:{index}`, next to the matching `*_track_index` (`A/player/PlaybackSessionManager.kt:2424-2425`).
   - `metered` and `bandwidth_estimate_kbps` from the network snapshot.
   - `allow_alternate_versions`. This is `false` for Watch Together and omitted otherwise (`S/model/playback/PlaybackProtocolV3.kt:437-443`).
9. **Admission** (`S/repository/SequencedPlayback.kt:186-239`). The app calls `GET /playback/capabilities`. A 404 means "server update required" (`:195`, `:201`). It requires `sequenced_progress_v1`, `allowed`, `state == available`, a non-blank `installation_id` and protocol 3 (`:202-205`). It then calls `GET /account/me` (`:213`). It tries one stop each for sessions an earlier run left open, and does not block on them (`:220-225`). It journals the exact request body to disk before sending (`:230-232`).
10. **`POST /api/v2/playback/start`** (`S/repository/SequencedPlayback.kt:245`). The app persists `session_id` before it decodes the plan, so it can still stop a session whose plan is invalid (`:247-262`). A response with no session but `outcome: adaptation_unavailable` plus `terminal` is a clean refusal (`:249-260`).
11. **Decode the plan.** File ids arrive as strings and are converted to positive ints (`S/repository/SequencedPlayback.kt:510-517`). Every delivery URL must start with `/api/v2/`, `https://` or `http://`. Any URL containing `/api/v1/` is rejected (`:519-527`). Proxy subtitle URLs must match `/stream/v3/{session}/subtitles/{n}.{ass|ssa|srt|vtt|sup}` on the stream's origin (`S/network/apiv2/ProxyAuxiliaryV2.kt:6-44`).
12. **Validate** with `validateForMedia3` (`S/model/playback/PlaybackProtocolV3.kt:543-680`). The response needs `protocol_version == 3`, and `server_features` must contain both `playback_plan_v3` and `neutral_playback_v3_contract_v1` (`:544-549`). It needs `outcome == playable`, a plan, a session id and a non-blank `plan_attempt_key` (`:550-578`). The subtitle inventory must be valid (`:579-585`, `:682-708`). `header_refresh: refresh_endpoint` is terminal on Android (`:617-623`). Unknown runtime corrections or client transforms trigger a replan, not a failure (`:624-678`).
13. **Map the plan to the player** (`T/.../TvVideoPlaybackStarter.kt:296-330`). The stream URL is `playback_plan.stream.url`. A relative URL is prefixed with the server origin (`A/player/SiloPlayerFactory.kt:772-785`). `delivery` maps to a play method. `original_http` is direct, `server_remux_*` is remux and `server_transcode_hls` is transcode (`A/player/PlaybackV3Session.kt:50-57`). The player starts at `timeline.player_start_seconds`, and the UI uses `timeline.source_start_seconds` (`T/.../TvVideoPlaybackStarter.kt:309-330`). Request headers come from `stream.headers`, or from captured proxy headers when subtitles are proxied (`T/.../TvVideoPlaybackStarter.kt:383`; `S/model/playback/PlaybackProtocolV3.kt:295`).
14. **After publication.** The app emits route event `plan_selected` (`A/player/PlaybackSessionManager.kt:412`). It starts the intro auto-skip observer and resolves the next episode (`T/ui/screens/player/TvPlayerViewModel.kt:2441-2442`). It opens the control socket (section 3.4).

**Direct play versus transcode.** The client never decides. It declares what each delivery class can carry, and the server returns `delivery`, `stream.protocol` (`http_progressive` or `hls`) and `decision_reason` (`S/model/playback/PlaybackProtocolV3.kt:127-130`, `:199-232`; `S/model/playback/PlaybackModels.kt:211-217`). Quality menus render `available_qualities` from the plan, not values the client computes (`S/model/playback/PlaybackProtocolV3.kt:220-225`). DASH does not appear anywhere in the playback contract (inferred, from the protocol enum at `:127-130`).

**Duration.** Use `plan.source.duration_seconds` and keep null as null. Never use the engine's duration. An HLS remux reports only the window produced so far (`S/model/playback/PlaybackProtocolV3.kt:252-264`; `T/ui/screens/player/TvPlayerViewModel.kt:3055-3071`).

## 3. Progress reporting and session lifecycle

### 3.1 Position timeline

The reported `position` is **source (movie) seconds**, not player seconds. The mapping is `source = player + timeline_offset_seconds`, and the reverse is `player = source - timeline_offset_seconds` (`A/player/seek/PlaybackTimelineSeekPolicy.kt:61-66`). The TV app clamps the result to the server duration (`T/ui/screens/player/TvPlayerViewModel.kt:3063-3066`).

### 3.2 Progress rules

- **Interval.** The reporter loop sleeps 10 s, then sends the latest sample (`A/player/PlaybackSessionLifecycle.kt:666-678`, `:931`). Player callbacks only update the cached sample (`:411-415`).
- **Sequencing.** Each new sample takes `sequence = last + 1` and is journaled before it is sent (`S/repository/SequencedPlayback.kt:406-410`). If the previous sample has no receipt, it is resent verbatim before a new one is created (`:399-405`).
- **Receipt check.** `outcome` must be `applied`, `replayed` or `stale_sample`. `accepted.sequence` must be at least the sent sequence, and an equal sequence must echo the same position and paused flag. Otherwise the receipt is rejected (`S/repository/SequencedPlayback.kt:415-423`).
- **Rejected positions.** Non-finite or negative positions are dropped on the client (`S/repository/SequencedPlayback.kt:398`).
- **401 mid-session.** Progress is the only session mutation that may refresh and resend once (`S/network/apiv2/PlaybackV2Api.kt:136-142`).
- **Failure handling.** A failed tick loses nothing. After 3 consecutive failures (about 30 s) the app shows a warning and does not replace the session (`A/player/PlaybackSessionLifecycle.kt:695-706`, `:934`).
- **Exit.** The app flushes the final position through the same progress call, then stops (`A/player/PlaybackSessionLifecycle.kt:894-900`).

### 3.3 Stop rules

- The stop body is built once with a fresh `stop_id` and the last unsent sample, then journaled (`S/repository/SequencedPlayback.kt:436-440`).
- There are up to 3 attempts, with backoff of 250 ms times the attempt number. A 404 counts as stopped because the server already expired the session. A 503 or a network error is retried. Any other error is returned (`S/repository/SequencedPlayback.kt:443-459`).
- A stop that never succeeds stays in the journal. The app retries it, once per entry, at the start of the next playback (`S/repository/SequencedPlayback.kt:462-506`). The server also expires sessions nobody stops (`:220-221`).

### 3.4 Replan (playback control v2)

The app sends `POST /playback/{session}/replan` for track changes, quality changes, seeks outside the window and failure recovery. `operation` is one of `failure_recovery` (the default), `seek_reanchor`, `seek_failure_recovery`, `track_change` or `quality_change` (`S/model/playback/PlaybackProtocolV3.kt:68-78`). Audio, subtitle and inventory changes map to `track_change`. Quality maps to `quality_change`. Everything else maps to `failure_recovery` (`A/player/PlaybackSessionManager.kt:2542-2547`; `T/ui/screens/player/TvSubtitleTransactionAdapter.kt:1200-1208`). The body echoes `failed_plan_id`, `plan_attempt_key`, the `attempted_plan_keys` list and `position_seconds` in source time (`S/model/playback/PlaybackProtocolV3.kt:454-487`). Each `replan_request_id` is journaled and may not be reused with a different body (`S/repository/SequencedPlayback.kt:321-347`). A 501 settles the replan as rejected. Other errors leave it pending (`:359-364`).

**Seek decision.** Seek natively when the target is inside the seek window, or when the window is absent and `can_seek_anywhere` is true. Otherwise ask the server to reanchor (`A/player/seek/PlaybackTimelineSeekPolicy.kt:131-210`).

### 3.5 Control WebSocket

After the session is adopted, the app gets a ticket and opens the socket (`S/network/PlaybackRealtimeClient.kt:113-136`, `:277-291`). On open it sends `{"type":"hello","session_id","client":{"name":"silo-android","version":"1"},"capabilities":{"commands":[...]}}` (`S/network/PlaybackRealtimeModels.kt:37-49`; `S/network/PlaybackRealtimeClient.kt:239-249`). The advertised commands are `pause`, `unpause`, `play_pause`, `seek`, `stop`, `terminate`, `display_message`, `server_restarting`, `server_shutting_down`, `set_audio_track` and `set_subtitle_track` (`S/network/PlaybackRealtimeModels.kt:30-34`). Inbound frames are `{"type":"command","command_id","session_id","name","payload"}` or `{"type":"event","session_id","name","payload"}` (`S/network/PlaybackRealtimeClient.kt:45-68`). The client answers a command with `ack` (status `accepted`), then `result` (`completed` or `rejected` plus `error`) (`S/network/PlaybackRealtimeModels.kt:51-66`). The TV app handles the server events `subtitle_ready`, `subtitle_timing_changed`, `subtitle_sync_updated` and `markers_updated` (`T/ui/screens/player/TvPlaybackRealtimeController.kt:113-118`).

## 4. Subtitles

- **Source of truth.** `playback_plan.subtitle.inventory` is the complete, gap-free list for the effective file. Select a track by echoing `track_id` or `combined_index`. Never count tracks (`S/model/playback/PlaybackProtocolV3.kt:355-362`). Each row carries `track_id`, `combined_index`, `source`, `codec`, `language`, `label`, `forced`, `default`, `hearing_impaired`, `delivery`, `url`, `font_bundle_url` and `sync_key` (`:367-386`).
- **Delivery.** `sidecar` rows must have a `url`. `burn_in_only` rows must not (`S/model/playback/PlaybackProtocolV3.kt:691-696`). The plan's `subtitle.mode` is `off`, `render`, `convert` or `burn_in` (`:140-145`). The selected track is either an `artifact` (`url`, `mime_type`, `format`, `timing_origin_seconds`) or `embedded` (`stream_index`, `container_track_id`) (`:336-354`).
- **Embedded tracks.** Native embedded selection by container track id is accepted only for `mp4` with `mov_text` and `mkv` with `subrip`/`ass`, and only on `original_http` (`S/model/playback/PlaybackProtocolV3.kt:522-525`, `:604-613`).
- **Bitmap subtitles.** On original HTTP, a bitmap `render` artifact refers to the embedded stream. It must not be mounted as a sidecar (`A/player/PlaybackV3Session.kt:58-80`). On HLS, PGS arrives as a raw `.sup` sidecar (`A/player/PlaybackCapabilityDetector.kt:617-622`).
- **Burn-in.** Inventory URLs are blanked during a burn-in plan, so nothing is drawn over baked-in captions (`A/player/PlaybackV3Session.kt:81-104`).
- **SRT.** The client normalizes `.srt` bodies, which are capped at 32 MiB (`A/player/AuthenticatedDataSourceFactory.kt:460-469`).
- **libass.** Android advertises `ass_styling`, `font_attachments` and the `libass_subtitles` feature only when its libass bridge can render with embedded fonts (`A/player/PlaybackCapabilityDetector.kt:465-467`, `:523-551`). These flags steer the server toward keeping ASS instead of converting it (inferred).
- **Switching tracks.** An embedded track that can be mounted locally is switched in the player. Everything else goes through a `track_change` replan (`T/ui/screens/player/TvSubtitleTransactionAdapter.kt:1078-1091`, `:1180-1208`).
- **External subtitles.** `search` finds candidates, `download` stores one on the server, and `list` shows stored rows (section 1). A newly stored or AI-made track arrives as a realtime `subtitle_ready` row. If the row does not fit the current inventory, the app replans with `subtitle_inventory_changed` (`T/ui/screens/player/TvPlayerViewModel.kt:5684-5695`).
- **Sync.** Timing correction uses the row's `sync_key` against the `/subtitles/{file}/sync/...` routes (`S/network/apiv2/SubtitleSyncV2Api.kt:27-89`).

## 5. Next episode, markers, trickplay

- **Markers.** `intro`, `credits`, `recap` and `preview` come from watch detail as `{start_seconds,end_seconds}` (`S/network/apiv2/WatchDetailV2Api.kt:43-49`). They can be replaced mid-play by `markers_updated` with payload `{start,end}` or null (`S/playback/PlaybackMarkersUpdate.kt:9-30`). Only `intro` drives auto-skip and only `credits` drives auto-advance (`:12-14`). The intro skip modes are `never`, `ask` and `always`, from setting `playback.intro_skip_mode` (`S/domain/player/IntroSkipMode.kt:3-25`).
- **Up Next trigger.** The trigger fires when playback crosses `credits.start` during normal play, not after a seek (`T/ui/screens/player/TvPlayerViewModel.kt:3111-3118`). Stream end is the fallback (`T/ui/screens/player/TvPlayerScreen.kt:1535-1542`).
- **Next episode.** The app loads the current season's episodes, which is required. It then adds the next regular (non-specials) season, best-effort, and picks the smallest (season, episode) after the current one (`T/ui/screens/player/TvPlayerViewModel.kt:4359-4389`; `S/playback/NextEpisodeResolver.kt:24-34`). Watch Together disables this (`T/.../TvPlayerViewModel.kt:4361`). The next episode starts a fresh start sequence, carrying audio and subtitle intent by meaning, not by index (`T/ui/screens/player/TvVideoPlaybackStarter.kt:542-569`).
- **`SequencedPlayback.kt`.** Despite the name, this is the session journal for start, replan, progress and stop (section 3). It is not episode sequencing (`S/repository/SequencedPlayback.kt:16-56`).
- **Trickplay.** No trickplay, BIF or thumbnail-track code was found in `shared`, `android-shared` or `androidTvApp` (searched for `trickplay`, `bif` and `thumbnails.vtt`).

## 6. Media request auth (what the player transport does)

- **Headers on every same-origin media request.** The transport sends `Authorization: Bearer <current access>`, `X-Profile-Id` and `X-Profile-Token` from a fresh snapshot on each open (`A/player/MediaAuthSession.kt:39-101`, `:222-226`; `A/player/AuthenticatedDataSourceFactory.kt:98-102`, `:206-219`).
- **Plan headers.** `stream.headers` win over session headers. Session headers only fill in what is missing (`A/player/AuthenticatedDataSourceFactory.kt:206-251`).
- **Header scope.** Plan headers are sent only to the issued stream URL and to paths under the same directory, which covers HLS child playlists and segments (`A/player/SiloPlayerFactory.kt:549-573`). Session credentials never go to another origin (`A/player/AuthenticatedDataSourceFactory.kt:262-267`). Redirects that cross origins have credentials and `X-Silo-*` headers removed (`A/player/PlayerOkHttpClient.kt:40-49`, `:67-77`).
- **Proxy subtitle URLs** (`/stream/v3/{session}/subtitles/...`). These use only the `Authorization` and `X-Profile-Id` values captured from the start or replan request. They never refresh, never retry after a 401 and never follow redirects (`S/network/apiv2/ProxyAuxiliaryV2.kt:16-24`, `:46-56`; `A/player/AuthenticatedDataSourceFactory.kt:87-93`, `:103-113`; `A/player/PlayerOkHttpClient.kt:93-99`). `/stream/v3/{session}/master.m3u8` and `/stream/v3/{session}/segment/*` share that captured authority when the primary stream is header-authenticated (`A/player/AuthenticatedDataSourceFactory.kt:473-489`).
- **Token refresh mid-stream.** On a same-origin 401, the transport runs one single-flight `POST /api/v2/auth/refresh`, then retries the request once with new headers (`A/player/AuthenticatedDataSourceFactory.kt:103-118`; `A/player/MediaAuthSession.kt:103-158`). If another request already refreshed, the retry skips the refresh (`A/player/MediaAuthSession.kt:107-110`). A 400, 401 or 403 from refresh invalidates the session (`:229-230`).
- **Ranged resume on direct play.** For `original_http` the transport remembers the strong ETag. It sends `If-Range` on ranged reopens and fails if the entity changed (`A/player/SiloPlayerFactory.kt:494-498`; `A/player/AuthenticatedDataSourceFactory.kt:163-198`).
- **Timeouts.** Connect 20 s, read and write 30 s, HTTP/2 preferred (`A/player/PlayerOkHttpClient.kt:30-50`). The refresh client uses a 20 s call timeout (`:84-90`).

## 7. Downloads

The TV app has no downloads (`T/ui/screens/player/TvVideoPlaybackStarter.kt:67-69`). The phone app uses this flow:

1. `GET /api/v2/capabilities/downloads` gates the quality picker (`S/network/api/DownloadsApi.kt:41-49`).
2. `POST /api/v2/downloads` with `content_id`, optional `episode_id` and `media_file_id`, `quality` (default `original`) and optional `caps`. It expects 202 and is sent once. The device id comes from the auth plugin's `X-Silo-Device-Id`, and sending it twice breaks the receipt check (`S/network/apiv2/DownloadCreationV2Api.kt:32-54`). A request with `series` set returns a batch (`S/network/api/DownloadsApi.kt:54-61`).
3. `GET /api/v2/downloads/{id}/file` streams the file. Resume sends `Range: bytes=N-` with `If-Range` set to the strong ETag or `Last-Modified`, plus `Accept-Encoding: identity`. A 416 restarts from zero (`A/downloads/DownloadWorker.kt:212-241`, `:857-860`).
4. `GET /api/v2/downloads/{id}/manifest` fetches offline subtitle and track assets (`A/downloads/OfflineTrackAssetFetcher.kt:103`).
5. `PATCH /api/v2/downloads/{id}` reports `downloading` or `completed` with a `revision`. A moved revision returns 409 (`S/network/apiv2/DownloadRegistryV2Api.kt:100-118`).
6. Offline playback uses a `file://` URL through the same data source (`A/player/AuthenticatedDataSourceFactory.kt:28-30`, `:305-311`). Offline progress goes through the personal-data `syncProgress` path, not playback sessions (`A/player/PlaybackSessionLifecycle.kt:870-905`).

## 8. Watch Together (out of scope)

The REST routes are under `/api/v2/watch-together`. They include `/capabilities`, `/join`, `/rooms` and `/rooms/{roomId}` with actions below it (`S/network/api/WatchTogetherApi.kt:165-179`, `:408-411`). The room socket is `/api/v2/watch-together/rooms/{roomId}/ws` with a ticket subprotocol (`S/network/WatchTogetherRealtimeClient.kt:131`, `:169-178`). Room playback still uses `/playback/start` with `allow_alternate_versions: false` (`T/ui/screens/player/TvVideoPlaybackStarter.kt:117-121`).

## 9. Port notes for Dart (mpv or another non-ExoPlayer player)

1. **Send the same start body shape.** The server validates the neutral v3 contract. Plezy must send honest `client_capabilities` and `client_playback_context.deliveries`. For mpv, declaring `original_http` and `hls`, and leaving `progressive` disabled as Android does, is the closest match (inferred). The evidence fields allow `platform_attested` or `declared` when exact decoder lists are unavailable. Audio passthrough is granted only at `exact` (`S/model/playback/PlaybackProtocolV3.kt:48-56`).
2. **Do not advertise Media3-only features.** These are `client_video_transformations_v1`, the DV transform recipes and the Media3 runtime corrections. If mpv cannot execute them, a plan naming them makes Android replan (`S/model/playback/PlaybackProtocolV3.kt:624-678`). Advertising only what mpv does is safer. **Guess:** the server will avoid client transforms when `transformations` is empty. `CLIENT_SELECTED_AUDIO_TRACK_V1_CLAIM` commits the client to a typed failure report when it cannot honor the server's audio ordinal (`:26-32`).
3. **Headers on every segment.** mpv sets headers per file through `http-header-fields`. Every HLS child playlist and segment needs `Authorization`, `X-Profile-Id` and `X-Profile-Token` when present, plus `stream.headers`. This works only if those requests stay on the same origin and directory (`A/player/SiloPlayerFactory.kt:549-573`). mpv sends the configured header list on segment requests too, but it does not strip them on a cross-origin redirect. **Guess:** a local proxy, or a check that segment URLs stay same-origin, is needed to match Android's credential scoping.
4. **Token refresh mid-stream.** mpv cannot refresh on a 401 inside its demuxer. Options are to refresh before expiry and update `http-header-fields` (the change applies to new requests, inferred). Another is a local HTTP proxy in Dart that injects fresh headers and replays one 401. The server tolerates a 401 on progress being resent once (`S/network/apiv2/PlaybackV2Api.kt:136-142`).
5. **Proxy subtitles use captured headers only.** Fetch `/stream/v3/{session}/subtitles/{n}.{ext}` in Dart with the exact `Authorization` and `X-Profile-Id` sent on the start or replan request. Do not refresh, retry or follow redirects. Then hand the bytes to mpv with `sub-add` (`S/network/apiv2/ProxyAuxiliaryV2.kt:16-56`).
6. **Two timelines.** Seek mpv in player time and report source time (`source = player + timeline_offset_seconds`). Start at `player_start_seconds`. Use `source.duration_seconds` for the seek bar (`A/player/seek/PlaybackTimelineSeekPolicy.kt:61-66`; `S/model/playback/PlaybackProtocolV3.kt:252-264`, `:299-308`). Seeks outside the seek window must replan with `seek_reanchor`, not seek in mpv (`A/player/seek/PlaybackTimelineSeekPolicy.kt:155-210`).
7. **Persist the journal.** Start bodies, the unsent progress sample, the `stop_id` and the replan intents must survive a restart. Stop leftover sessions at the next start (`S/repository/SequencedPlayback.kt:16-47`, `:462-506`). Without this, a crash leaks a transcode slot until the server expires it (`A/player/PlaybackSessionManager.kt:306-330`).
8. **IDs are strings on the wire.** `file_id` in the start body and in plan responses is a decimal string (`S/network/apiv2/PlaybackV2Api.kt:72`; `S/repository/SequencedPlayback.kt:511-516`). `media_file_id` in the subtitle and download bodies is a string too (`S/network/apiv2/SubtitleDownloadV2Api.kt:13`; `S/network/apiv2/DownloadCreationV2Api.kt:35`).
9. **Audio index is a list ordinal.** Send the position in `versions[].audio_tracks` (`T/ui/screens/player/TvVideoPlaybackStarter.kt:554-557`). After start, map the server's ordinal onto mpv's `aid` yourself. Android does the same against the mounted inventory (`A/player/PlaybackCapabilityDetector.kt:561-566`).
10. **Subtitles off means the index is omitted,** never `-1` (`A/player/PlaybackSessionManager.kt:364-373`).
11. **`header_refresh`.** Android executes `none` and `session` and refuses `refresh_endpoint` (`S/model/playback/PlaybackProtocolV3.kt:133-137`, `:617-623`). Plezy can refuse the same way.
12. **ASS and fonts.** mpv renders ASS through libass natively, so declaring `ass_styling` and `font_attachments` on `original_http` is reasonable (inferred). `font_bundle_url` on inventory rows is the server's font source for sidecar ASS. Android has no native caller for it (`S/network/apiv2/ProxyAuxiliaryV2.kt:26`). A port would fetch it and pass fonts to mpv (`sub-fonts-dir`). **Guess:** the bundle format still has to be confirmed.

## Open questions

1. What does `GET /api/v2/playback/capabilities` return on this server, and does `features` include `sequenced_progress_v1`? This needs an authenticated session, which was out of scope.
2. Does the server accept a `client_playback_context` that has no Media3-style decoder evidence, such as `video_evidence: declared`? What does it plan for it? The code documents the tiers but the server's behavior is unseen.
3. Is `header_refresh: session` the only mode this server issues? The `refresh_endpoint` shape (`header_refresh_url`) has no client implementation to read.
4. What format does `font_bundle_url` serve?
5. Are `/stream/v3/{session}/...` segment URLs signed in the query string for HLS, or header-authenticated? The code handles both (`S/network/apiv2/ProxyAuxiliaryV2.kt:36-40`). Which one this server uses decides whether mpv needs per-segment headers at all.
6. Does the server require the `X-Silo-Device-*` headers on playback calls, or only on downloads? The API client sends them everywhere (`S/network/AuthInterceptorImpl.kt:899-911`).

## Live answers, 2026-10-14

Measured with `tool/silo_probe.dart --play movie-tmdb-1381078 --play movie-tmdb-1381078@480p` on `https://silo.ruleone.xyz`, profile admin. The probe sent the mpv start body from `lib/silo/silo_playback.dart`, at `declared` evidence with no Media3 features.

1. Capabilities are `state=available`, `allowed=true`, `protocol_versions=[3]`, and `features` include `sequenced_progress_v1`, `neutral_playback_v3_contract_v1` and `seek_reanchor_v1`.
2. The server plans for the declared mpv context. `auto` gave `original_http` (`validated_original_playback`). `480p` gave `server_transcode_hls` (`quality_fixed_rung`).
3. Both plans use `header_refresh: none` with empty `stream.headers`. The direct URL is `/api/v2/stream/{session}?st=…` and the transcode URL is `/api/v2/playback/transcode/{session}/master.m3u8?st=…`, so the `st` query token authenticates them. The direct stream answers ranges with `Content-Range` and an `ETag`.
4. The transcode playlist lists segments as `segment/seg_N.m4s?{$silo_query}`, an `EXT-X-DEFINE` variable the client substitutes.
5. Neither plan has a seek window, and `can_seek_anywhere` is true.
6. Subtitle rows are `embedded`/`subrip`/`sidecar` at `/api/v2/stream/{session}/subtitles/N.vtt?embedded_stream_index=…&file_id=…`. They do not match the proxy-auxiliary pattern `/stream/v3/…`, so they are ordinary same-origin media requests.
7. Progress returned `applied` with `accepted.sequence` 1, and stop returned `stopped` with the `stop_id` echoed.
