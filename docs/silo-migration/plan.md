# Silo backend migration plan

Plezy stops talking to Plex, Jellyfin and Emby and talks only to a Silo server. It signs in, reads home sections, browses libraries, opens detail, and plays media with the same wire calls Silo's Android TV app makes. Plezy's screens stay. A Dart `SiloClient` feeds them through the existing `MediaServerClient` seam. The rule the program enforces is call-for-call parity with Silo's Kotlin client, cited to its source, for every request Plezy sends.

The work lands as nine stacked branches on top of `feat/tv-silo-sidebar`, in this order: S1 wire client, S2 sign-in and profiles, S3 catalog and home, S4 realtime and home actions, S5 playback, S6 downloads, S7 Silo-only onboarding and data migration, S8 delete Jellyfin and Emby, S9 delete Plex and collapse the seams.

## How to read this
One box is one unit of work. Every box names the evidence that checks it. A nested box is a sub-step of the box above it. Check a box only when its evidence exists, a file, a log line, a screenshot, a test run, or a SHA. The body is a how-to. The appendices explain and record.

The program runs `skills/p3-mode/playbooks/autopilot-stack.md`. The root builds and verifies each branch and appends it to one linear stack. The operator reviews the review-gated branches and lands the stack bottom-up. S2, S3, S4, S5 and S7 are review-gated because they change what the user sees or does.

Research inputs live next to this file in `research/`. `silo-auth.md`, `silo-catalog.md` and `silo-playback.md` give the wire contract. `plezy-backend-map.md` gives the Plezy side. Every Silo citation below uses those files' path prefixes. `S/` is Silo's `shared/src/commonMain/kotlin/org/siloserver/silo/`, `A/` is `android-shared/.../common/`, and `T/` is `androidTvApp/.../tv/`.

## Program checklist
- [ ] Operator approves this plan. Evidence is the go message in chat.
- [ ] Operator approves one device-code sign-in for the S1 probe. Evidence is `research/samples/home-sections.json`.
- [ ] S1 to S9 each reach a clean verdict at their head SHA. Evidence is each branch's verdict line in Appendix D's trail.
- [ ] The operator lands the stack. Evidence is the landed SHAs.

### Rules for every branch
- [ ] Branch from the previous branch's head. Names are `feat/silo-s1-wire` through `feat/silo-s9-delete-plex`.
- [ ] Commit messages end with the Claude co-author line. Nothing is pushed until the operator says so.
- [ ] Every new Silo call carries a comment-free implementation and a test that cites the Silo source line it mirrors in the test name or assertion message.
- [ ] `flutter analyze` is clean and `flutter test` passes at the head before the live lanes run.
- [ ] No token, password or profile token is printed, logged, committed or written outside `CredentialVault`.

### Verdict and merge, for every branch
- [ ] At the code-ready head SHA, run the lanes per `skills/swarm/SKILL.md`. That is one gates lane, the ten live lanes from the branch's **Verify, live** block, the perf lane from its **Verify, perf** block, and two audit lanes. One audit lane checks wire parity against the research files. The other checks secrets handling and data loss.
- [ ] Clean only when every lane is `PASS`. Findings go back to the owner. A new head gets a fresh verdict.
- [ ] Append the branch to the stack only after its clean verdict, with the patch-id rule from `playbooks/shipping.md`.

### Boot recipe, for every live lane
Each live lane drives the Android TV emulator with `adb`. Lanes run one at a time, because four parallel workers hit the API rate limit during research (Appendix C).

- [ ] `git checkout <head SHA>`.
- [ ] `export PATH=$HOME/Android/Sdk/platform-tools:$HOME/flutter/bin:$PATH`, then `flutter build apk --debug --target-platform android-x64` and `adb install -r build/app/outputs/flutter-apk/app-debug.apk`. Never uninstall. Never clear app data unless the lane says so.
- [ ] Start with `adb shell monkey -p com.edde746.plezy -c android.intent.category.LEANBACK_LAUNCHER 1`. Wait for the first frame.
- [ ] Send input only with `adb shell input keyevent`. Read state only with `adb exec-out screencap -p` and `adb logcat -s flutter`.
- [ ] Never press Select on a Continue Watching card. It starts playback and moves the server's resume position (Appendix C).
- [ ] Save every screenshot to `/tmp/swarm-<branch>/lane-<n>/<slug>.png` and return the paths.

## Build the Silo wire client (S1)
**Depends on.** None.

**Files.**
- [ ] Create `lib/silo/silo_http.dart`.
- [ ] Create `lib/silo/silo_headers.dart`.
- [ ] Create `lib/silo/silo_session.dart`.
- [ ] Create `lib/silo/silo_problem.dart`.
- [ ] Create `lib/silo/silo_artwork.dart`.
- [ ] Create `lib/silo/silo_contract_gate.dart`.
- [ ] Create `test/silo/silo_http_test.dart`, `test/silo/silo_session_test.dart`, `test/silo/silo_artwork_test.dart`.
- [ ] Create `tool/silo_probe.dart`.

**Build.**
- [ ] `SiloHeaders` builds the `X-Silo-*` set from `research/silo-auth.md` section 4.4. `X-Silo-Device-Id` is a UUID persisted once, apart from tokens, so sign-out keeps it. Platform is `android-tv` on TV and `android` elsewhere.
- [ ] `SiloSession` holds server origin, access token, refresh token, expiry, lifetime, profile id and profile token in `CredentialVault`, written as one commit. It bumps a generation counter on every identity change.
- [ ] `SiloHttp` sends JSON with 10 s connect and 60 s request timeouts. It adds `Authorization` and `X-Profile-*` only on the trusted origin and strips them on cross-origin redirects.
- [ ] `SiloHttp` refreshes under one lock with the double check from port note 1. Only 400, 401 or 403 from `/api/v2/auth/refresh` ends the session. It retries a 401 at most once and never retries `single` calls. Proactive refresh uses a 60 s margin clamped to half the lifetime.
- [ ] `SiloProblem` parses RFC 9457 bodies and takes the code from the last segment of `type`.
- [ ] `SiloContractGate` records `UPDATE_REQUIRED` only from the legacy 404 body and blocks v2 calls while set.
- [ ] `SiloArtwork` resolves a value that starts with a single `/` against the origin of the response that held it, at decode time.
- [ ] `tool/silo_probe.dart` signs in by device code, runs the read-only calls from `research/samples/`, writes structural summaries only, and logs out.

**You see.**
- [ ] `dart run tool/silo_probe.dart` prints `USER_CODE`, then after approval prints `home 200 sections=<n>` and `logout 204`.
- [ ] `research/samples/home-sections.json` lists the real `section_type` values.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [ ] `silo_session_test.dart` asserts two concurrent 401s cause exactly one `/auth/refresh` call. Run `flutter test test/silo`.
- [ ] `silo_session_test.dart` asserts a 503 from refresh keeps the tokens and a 401 clears them.
- [ ] `silo_http_test.dart` asserts a redirect to another origin carries no `Authorization` and no `X-Silo-*` header.
- [ ] `silo_artwork_test.dart` asserts `/img/a.jpg` resolves to `https://silo.ruleone.xyz/img/a.jpg` and `//cdn/x` stays unchanged.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on the `swarm workers` role in `p3-models.md` at the PR head, per the boot recipe.
- [ ] Lane 1. Regression lane against trunk. Install head and trunk builds in turn and open the Plex home. Trunk has no Silo client, so gate that head still reaches the Plex home unchanged. Save `regression-home.png`. Pass when both screenshots show the same home rows.
- [ ] Lane 2. Run the probe and approve the code. Save `probe-log.png` of the terminal. Pass when the log shows `logout 204`.
- [ ] Lane 3. Rerun the probe and let the code expire. Save `probe-expired.png`. Pass when the log shows the code withdrawn and no tokens written.
- [ ] Lane 4. Probe with the network down mid-poll. Save `probe-offline.png`. Pass when it backs off and resumes polling.
- [ ] Lane 5. Probe `GET /api/v2/system/identity` through `SiloHttp`. Save `identity.png`. Pass when the request log shows no `Authorization` header.
- [ ] Lane 6. Probe with an expired access token. Save `refresh.png`. Pass when one refresh occurs and the call succeeds.
- [ ] Lane 7. Probe with a revoked refresh token. Save `revoked.png`. Pass when the session clears and the probe reports session expired.
- [ ] Lane 8. Read `research/samples/` after a run. Save `samples.png`. Pass when no file contains a token, title or name.
- [ ] Lane 9. Inspect `CredentialVault` storage after a run. Save `vault.png`. Pass when tokens are encrypted and the device id is outside the token store.
- [ ] Lane 10. Run the probe twice. Save `device-id.png`. Pass when both runs send the same `X-Silo-Device-Id`.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [ ] Metric. Wall time for one authenticated `GET /api/v2/home/sections` through `SiloHttp`. Trunk lacks the client, so the diff-added work is that call and the user-visible state is the probe's `home 200` line.
- [ ] Probe. Twenty probe runs against the test server, timing the request alone.
- [ ] Baseline. Record the same request with `curl` first.
- [ ] Rule. Median `SiloHttp` time within 50 ms of the `curl` median. Fail above that.

**Review gate.** None. S1 is not review-gated.

**Merge.**
- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto `feat/tv-silo-sidebar` after the verdict, patch-id unchanged.
- [ ] Appended to the stack. The operator lands it bottom-up.

## Sign in to Silo and pick a profile (S2)
**Depends on.** S1.

**Files.**
- [ ] Edit `lib/media/media_backend.dart` to add `silo`.
- [ ] Edit `lib/media/server_capabilities.dart` to add the `silo` preset.
- [ ] Edit `lib/connection/connection.dart` to add `SiloConnection`.
- [ ] Edit `lib/connection/connection_registry.dart` at the row parser.
- [ ] Edit `lib/services/credential_vault.dart` at `_tokenKeyForKind`.
- [ ] Edit `lib/services/multi_server_manager.dart` to add `addSiloConnection`.
- [ ] Edit `lib/profiles/active_profile_binder.dart` to add `_bindSilo`.
- [ ] Create `lib/screens/auth/silo_server_screen.dart`.
- [ ] Create `lib/screens/auth/silo_login_screen.dart`.
- [ ] Create `lib/silo/silo_device_sign_in.dart`.
- [ ] Create `lib/silo/silo_profiles.dart`.
- [ ] Create `lib/screens/profile/silo_profile_screen.dart`.
- [ ] Edit `lib/screens/auth_screen.dart` and `lib/screens/settings/add_connection_screen.dart` to add a Silo entry.
- [ ] Create `lib/services/silo_client.dart` with identity members only.
- [ ] Create `test/silo/silo_device_sign_in_test.dart`, `test/silo/silo_profiles_test.dart`, `test/test_helpers/fake_silo_server.dart`.

**Build.**
- [ ] `SiloServerScreen` normalizes the address, tries `https://` then `http://`, and probes `system/info`, `system/setup` and `auth/signup` per `research/silo-auth.md` section 2.2. Cleartext needs a one-time per-origin consent.
- [ ] `SiloLoginScreen` starts the device code on open and shows the password form beside it. The first finisher wins. The device code follows port notes 10 to 13, including poll timing, renewal, cancel on leave, and the held approval.
- [ ] Sign-in commits are fenced by the generation check from port note 9.
- [ ] `SiloProfileScreen` lists `GET /api/v2/profiles`. A PIN profile calls `verify-pin` without profile headers and enters only when `valid` is true and `profile_token` is non-blank.
- [ ] `SiloConnection` stores the server origin and server id. Its join row stores the profile id. Tokens live only in `CredentialVault`.
- [ ] `_bindSilo` builds a `SiloClient` whose `cacheServerId` is `silo:<server_id>/<profile_id>`.
- [ ] Sign-out calls `POST /api/v2/auth/logout` and wipes the slot whatever the result.

**You see.**
- [ ] The TV auth screen shows a "Silo" option. Choosing it asks for the server address, then shows a code, a QR and a password form side by side.
- [ ] Approving the code shows "Signed in as <username>" for one second, then the profile picker.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [ ] `silo_device_sign_in_test.dart` asserts poll waits follow `interval`, then `poll_after`, with a 1 s floor and doubling backoff to 30 s. Run `flutter test test/silo`.
- [ ] Same file asserts an expired code is cancelled before a new start.
- [ ] Same file asserts a password win cancels the device code.
- [ ] `silo_profiles_test.dart` asserts a 200 with `valid: false` does not enter the profile.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on the `swarm workers` role in `p3-models.md` at the PR head, per the boot recipe.
- [ ] Lane 1. Regression lane against trunk. Cold start with the existing Plex sign-in at trunk and head. Save `regression-plex-home.png`. Pass when head still reaches the Plex home.
- [ ] Lane 2. Add Silo from the auth screen and approve the code. Save `silo-code.png` and `silo-profiles.png`. Pass when the picker lists the server's profiles.
- [ ] Lane 3. Sign in with username and password instead. Save `silo-password.png`. Pass when the picker appears and the device code is withdrawn.
- [ ] Lane 4. Enter a wrong password. Save `silo-wrong-password.png`. Pass when "Invalid credentials" shows and the code keeps running.
- [ ] Lane 5. Leave the login screen with Back. Save `silo-leave.png`. Pass when the server shows the code cancelled.
- [ ] Lane 6. Pick a PIN profile and type a wrong PIN. Save `silo-pin-wrong.png`. Pass when the picker stays.
- [ ] Lane 7. Pick a PIN profile with the right PIN. Save `silo-pin-right.png`. Pass when the app enters that profile.
- [ ] Lane 8. Kill and relaunch the app. Save `silo-relaunch.png`. Pass when it opens signed in without a new code.
- [ ] Lane 9. Sign out from settings. Save `silo-signout.png`. Pass when the auth screen shows and the server lists no session for this device.
- [ ] Lane 10. Enter an unreachable address. Save `silo-unreachable.png`. Pass when the screen says the server can't be reached.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [ ] Metric. Time from opening the login screen to the code being shown. Trunk has no Silo login, so the diff-added work is device start and render, and the user-visible state is a readable code.
- [ ] Probe. Ten opens, timed from the logcat line for the route push to the logcat line for the first code frame.
- [ ] Baseline. Record trunk's Plex PIN screen time to code shown first.
- [ ] Rule. Median under 1.5 s on the emulator. Fail above that.

**Review gate.** The operator reviews before merge.
- [ ] Copy lane 2 and lane 7 screenshots into `docs/silo-migration/media/s2-review-*.png`.
- [ ] Record a 30 to 60 second video of sign-in through profile pick. Save it as `docs/silo-migration/media/s2-review.mp4`.
- [ ] Post the screenshots and the video in chat. Stop at merge-ready. Wait for the operator's click.

**Merge.**
- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto S1 after the verdict, patch-id unchanged.
- [ ] Appended to the stack. The operator lands it bottom-up.

## Read home sections, libraries and detail from Silo (S3)
**Depends on.** S2.

**Files.**
- [ ] Edit `lib/services/silo_client.dart` to implement the catalog members of `MediaServerClient`.
- [ ] Create `lib/silo/silo_catalog.dart`, `lib/silo/silo_models.dart`, `lib/silo/silo_mappers.dart`.
- [ ] Edit `lib/media/media_item.dart` to add a `silo` variant.
- [ ] Create `test/silo/silo_catalog_test.dart`, `test/silo/silo_mappers_test.dart`.

**Build.**
- [ ] `fetchGlobalHubs` reads `GET /api/v2/home/sections` and hydrates sections with empty `items` and `total_count > 0` through `/items`, at most four at once. It maps each section to a `MediaHub` that keeps `section_type`.
- [ ] `fetchContinueWatching` reads the progress sections. A section is a progress row when its lowercased `section_type` contains `continue`, `in_progress`, `next_up` or `up_next`.
- [ ] `fetchLibraries` reads `/user/libraries` and `/settings/values/effective?keys=ui.disabled_library_ids`, then drops hidden ids and ebook types.
- [ ] `fetchLibraryPagedContent` uses `GET /catalog` with no rule groups and `POST /catalog/query` with any. It pages with cursors at 100 per page and restarts on `invalid_cursor`.
- [ ] `fetchItem`, `fetchChildren` and seasons and episodes follow `research/silo-catalog.md` Detail rules, including season order and initial season choice.
- [ ] `searchItems` and `searchPeople` follow the Search row of the screen map, with a 300 ms debounce in the caller.
- [ ] `markWatched`, `markUnwatched`, `rate`, `setFavorite` and watchlist writes are single attempt and expect 204.
- [ ] Every read drops its result if the session generation moved during the call.
- [ ] The `silo` capability preset turns off flags Silo has no wire for, such as live TV, DVR, folder grouping and external subtitle search.

**You see.**
- [ ] The TV home shows the Silo server's sections in server order, with Continue Watching as backdrop cards.
- [ ] Opening a library shows its items. Opening an item shows the restyled detail with Silo metadata.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [ ] `silo_catalog_test.dart` asserts a genre filter switches the request to `POST /catalog/query`. Run `flutter test test/silo`.
- [ ] Same file asserts a second page sends the same query plus `cursor`, and a repeated `next_cursor` restarts from page one.
- [ ] `silo_mappers_test.dart` maps a recorded section sample to a `MediaHub` with the expected title, type and item count.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on the `swarm workers` role in `p3-models.md` at the PR head, per the boot recipe.
- [ ] Lane 1. Regression lane against trunk. Open the home at trunk with Plex and at head with Silo. Trunk lacks Silo, so gate that head's home shows Silo sections. Save `home-trunk.png` and `home-head.png`. Pass when head's rows match `research/samples/home-sections.json` in order.
- [ ] Lane 2. Open each library from the sidebar. Save `library-<n>.png`. Pass when every library shows items.
- [ ] Lane 3. Scroll a large library to the end. Save `library-end.png`. Pass when items keep loading without duplicates.
- [ ] Lane 4. Apply a genre filter. Save `library-genre.png`. Pass when every item shows that genre.
- [ ] Lane 5. Use the A to Z rail. Save `library-az.png`. Pass when the first item starts with the chosen letter.
- [ ] Lane 6. Open a movie detail. Save `detail-movie.png`. Pass when title, year, synopsis and cast match the Silo app.
- [ ] Lane 7. Open a show detail. Save `detail-show.png`. Pass when the initial season matches the Silo app's choice.
- [ ] Lane 8. Search for a known title. Save `search.png`. Pass when it appears in results.
- [ ] Lane 9. Toggle watched on a movie and reopen it. Save `watched.png`. Pass when the Silo app shows the same state.
- [ ] Lane 10. Switch profile and reopen the home. Save `profile-switch.png`. Pass when the home shows the new profile's rows.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [ ] Metric. Cold start to first home row painted. Trunk produces it with Plex. Head produces it with Silo.
- [ ] Probe. Ten cold starts each, interleaved trunk and head, timed from process start to the logcat line for the first hub frame.
- [ ] Baseline. Record the trunk median first.
- [ ] Rule. The scenarios differ, so use an absolute budget. Head median under 2.5 s on the emulator. Fail above that.

**Review gate.** The operator reviews before merge.
- [ ] Copy lanes 1, 6 and 7 screenshots into `docs/silo-migration/media/s3-review-*.png`.
- [ ] Record a 30 to 60 second video of home, a library, and a detail. Save it as `docs/silo-migration/media/s3-review.mp4`.
- [ ] Post the screenshots and the video in chat. Stop at merge-ready. Wait for the operator's click.

**Merge.**
- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto S2 after the verdict, patch-id unchanged.
- [ ] Appended to the stack. The operator lands it bottom-up.

## Keep the home live and dismissable (S4)
**Depends on.** S3.

**Files.**
- [ ] Create `lib/silo/silo_events.dart`.
- [ ] Edit `lib/services/silo_client.dart` at `createLibraryEventChannel` and `removeFromContinueWatching`.
- [ ] Create `test/silo/silo_events_test.dart`.

**Build.**
- [ ] `SiloEvents` gets a ticket from `POST /api/v2/events/ws-ticket` and opens `/api/v2/events/ws?channels=user_state,catalog` with the two subprotocols and no auth headers. It sends the subscribe frame first.
- [ ] A `subscribed` frame, any `catalog` event, or a `user_state.changed` event for the active profile triggers a home refetch, debounced 2 s. Reconnect backs off from 1 s to 30 s. A ticket is never reused.
- [ ] `removeFromContinueWatching` sends `PUT /home/dismissals/{surface}/{itemId}` with the anchor, only when the visible card's anchor still matches.

**You see.**
- [ ] Marking an item watched in the Silo app updates Plezy's home within a few seconds.
- [ ] "Remove from Continue Watching" removes the card.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [ ] `silo_events_test.dart` asserts five events within 2 s cause one refetch. Run `flutter test test/silo`.
- [ ] Same file asserts a `user_state.changed` for another profile causes none.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on the `swarm workers` role in `p3-models.md` at the PR head, per the boot recipe.
- [ ] Lane 1. Regression lane against trunk. Change watched state elsewhere and watch Plezy's home at trunk and head. Trunk lacks Silo, so gate head's live update. Save `realtime-head.png`. Pass when head updates within 5 s.
- [ ] Lane 2. Dismiss a Continue Watching card. Save `dismiss.png`. Pass when it disappears and stays gone after relaunch.
- [ ] Lane 3. Dismiss a Next Up card. Save `dismiss-next-up.png`. Pass when it disappears.
- [ ] Lane 4. Turn the network off for a minute, then on. Save `reconnect.png`. Pass when the socket reconnects and the home refetches once.
- [ ] Lane 5. Switch profile. Save `realtime-profile.png`. Pass when events for the old profile no longer refetch.
- [ ] Lane 6. Leave the app idle for ten minutes. Save `idle.png`. Pass when the socket is still connected or reconnected.
- [ ] Lane 7. Add an item to the watchlist in the Silo app. Save `watchlist-event.png`. Pass when Plezy's watchlist row updates.
- [ ] Lane 8. Background and foreground the app. Save `resume.png`. Pass when the home refetches quietly.
- [ ] Lane 9. Sign out. Save `signout-socket.png`. Pass when the socket closes.
- [ ] Lane 10. Check logcat for the ticket. Save `ticket-log.png`. Pass when no ticket value appears in logs.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [ ] Metric. Time from a watched change in the Silo app to Plezy's home repainting. Trunk lacks it, so this is an absolute budget.
- [ ] Probe. Ten changes, timed from the server event to the repaint logcat line.
- [ ] Baseline. Record the server event to frame delivery time first.
- [ ] Rule. Median under 3 s including the 2 s debounce. Fail above that.

**Review gate.** The operator reviews before merge.
- [ ] Copy lanes 1 and 2 screenshots into `docs/silo-migration/media/s4-review-*.png`.
- [ ] Record a 30 to 60 second video of a live update and a dismissal. Save it as `docs/silo-migration/media/s4-review.mp4`.
- [ ] Post the screenshots and the video in chat. Stop at merge-ready. Wait for the operator's click.

**Merge.**
- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto S3 after the verdict, patch-id unchanged.
- [ ] Appended to the stack. The operator lands it bottom-up.

## Play Silo media with the v3 playback contract (S5)
**Depends on.** S3.

**Files.**
- [ ] Create `lib/silo/silo_playback.dart`, `lib/silo/silo_playback_journal.dart`, `lib/silo/silo_media_proxy.dart`.
- [ ] Edit `lib/services/silo_client.dart` at `getPlaybackInitialization`, `reportPlaybackStarted`, `reportPlaybackProgress`, `reportPlaybackStopped`.
- [ ] Edit `lib/screens/video_player/parts/playback_open.dart` where the backend's stream URL and headers are applied.
- [ ] Create `test/silo/silo_playback_test.dart`, `test/silo/silo_media_proxy_test.dart`.

**Build.**
- [ ] `SiloPlayback.start` follows `research/silo-playback.md` section 2. It reads `GET /watch/{id}`, picks the version and tracks, checks `/playback/capabilities` admission, journals the body, and sends `POST /playback/start` with protocol 3. It declares `original_http` and `hls` and leaves `progressive` disabled.
- [ ] It advertises no Media3-only features, per port note 2.
- [ ] `SiloMediaProxy` is a local HTTP proxy that injects the current bearer, profile headers and `stream.headers` on same-origin and same-directory requests. It refreshes once on a 401 and replays. It never forwards credentials across origins.
- [ ] Proxied subtitles are fetched in Dart with the captured start headers, with no refresh, no retry and no redirect, then added to mpv.
- [ ] Progress posts every 10 s in source time. Stop sends `DELETE /playback/{session}` with a `stop_id`. Seeks outside the seek window replan with `seek_reanchor`.
- [ ] The journal survives a restart. Leftover sessions are stopped at the next start.

**You see.**
- [ ] Play on a movie starts playback. Resume starts 7 s before the saved position.
- [ ] The Silo app shows the new position after Plezy stops.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [ ] `silo_playback_test.dart` asserts the start body for a recorded watch detail field by field, including `subtitle_track_index` omitted when off. Run `flutter test test/silo`.
- [ ] Same file asserts a journalled open session is stopped before the next start.
- [ ] `silo_media_proxy_test.dart` asserts a segment on another origin is fetched without credentials.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on the `swarm workers` role in `p3-models.md` at the PR head, per the boot recipe.
- [ ] Lane 1. Regression lane against trunk. Play a movie at trunk with Plex and at head with Silo. Trunk lacks Silo, so gate head's playback and the saved position. Save `play-head.png`. Pass when video renders and the position syncs.
- [ ] Lane 2. Play a file the server direct plays. Save `direct.png`. Pass when the plan's delivery is `original_http`.
- [ ] Lane 3. Play a file the server transcodes. Save `transcode.png`. Pass when the plan's delivery is `server_transcode_hls` and video renders.
- [ ] Lane 4. Switch audio track. Save `audio-switch.png`. Pass when a replan occurs and audio changes.
- [ ] Lane 5. Turn subtitles on and off. Save `subs.png`. Pass when subtitles render and then disappear.
- [ ] Lane 6. Seek far ahead in a transcode. Save `seek-replan.png`. Pass when playback continues at the target.
- [ ] Lane 7. Play for longer than the token lifetime. Save `long-play.png`. Pass when playback never stalls on a 401.
- [ ] Lane 8. Kill the app mid-play and relaunch. Save `journal.png`. Pass when the server shows the old session stopped.
- [ ] Lane 9. Finish an episode. Save `next-episode.png`. Pass when the next episode is offered.
- [ ] Lane 10. Stop at a known position. Save `position-sync.png`. Pass when the Silo app resumes within 2 s of it.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [ ] Metric. Time from pressing Play to the first video frame. Trunk produces it with Plex. Head produces it with Silo.
- [ ] Probe. Ten plays of the same direct-play file each, interleaved, timed from the key event to the first-frame logcat line.
- [ ] Baseline. Record the trunk median first.
- [ ] Rule. The scenarios differ, so use an absolute budget. Head median under 3 s for direct play. Fail above that.

**Review gate.** The operator reviews before merge.
- [ ] Copy lanes 1, 3 and 5 screenshots into `docs/silo-migration/media/s5-review-*.png`.
- [ ] Record a 30 to 60 second video of play, track switch, seek and stop. Save it as `docs/silo-migration/media/s5-review.mp4`.
- [ ] Post the screenshots and the video in chat. Stop at merge-ready. Wait for the operator's click.

**Merge.**
- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto S4 after the verdict, patch-id unchanged.
- [ ] Appended to the stack. The operator lands it bottom-up.

## Download Silo media for offline play (S6)
**Depends on.** S5.

**Files.**
- [ ] Create `lib/silo/silo_downloads.dart`.
- [ ] Edit `lib/services/silo_client.dart` at `resolveDownload`, `resolveDownloadArtwork`, `stampLibrary`.
- [ ] Edit `lib/services/download_manager_service.dart` where the file request is built.
- [ ] Create `test/silo/silo_downloads_test.dart`.

**Build.**
- [ ] Follow `research/silo-playback.md` section 7. Gate on `/capabilities/downloads`, create with `POST /downloads` once, stream `GET /downloads/{id}/file` with `Range` and `If-Range`, fetch `/manifest` for tracks, and report state with `PATCH` and a revision.
- [ ] Download rows use the `silo:<server_id>/<profile_id>` scope id.
- [ ] Offline progress syncs through the personal-data progress path, not playback sessions.

**You see.**
- [ ] Download on a movie completes, and the movie plays with the network off.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [ ] `silo_downloads_test.dart` asserts a resume sends `Range: bytes=N-` and `If-Range`, and a 416 restarts from zero. Run `flutter test test/silo`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on the `swarm workers` role in `p3-models.md` at the PR head, per the boot recipe.
- [ ] Lane 1. Regression lane against trunk. Download a movie at trunk with Plex and at head with Silo. Trunk lacks Silo, so gate head's completed download. Save `download-head.png`. Pass when it completes.
- [ ] Lane 2. Play the download offline. Save `offline-play.png`. Pass when video renders.
- [ ] Lane 3. Interrupt the network mid-download. Save `download-resume.png`. Pass when it resumes, not restarts.
- [ ] Lane 4. Download an episode with subtitles. Save `download-subs.png`. Pass when subtitles render offline.
- [ ] Lane 5. Watch offline, then go online. Save `offline-sync.png`. Pass when the server shows the position.
- [ ] Lane 6. Delete the download. Save `download-delete.png`. Pass when the file is gone.
- [ ] Lane 7. Retry a failed download in bulk. Save `download-retry.png`. Pass when it completes.
- [ ] Lane 8. Download a season. Save `download-season.png`. Pass when every episode completes.
- [ ] Lane 9. Switch profile. Save `download-profile.png`. Pass when the other profile cannot see this download.
- [ ] Lane 10. Relaunch offline. Save `offline-launch.png`. Pass when the downloads list opens.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [ ] Metric. Download throughput for one 1 GB file. Trunk produces it with Plex. Head produces it with Silo.
- [ ] Probe. Three downloads each, interleaved, timed from start to completion.
- [ ] Baseline. Record `curl` throughput for the same Silo file first.
- [ ] Rule. Head throughput at least 80 percent of `curl`. Fail below that.

**Review gate.** None. S6 is not review-gated.

**Merge.**
- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto S5 after the verdict, patch-id unchanged.
- [ ] Appended to the stack. The operator lands it bottom-up.

## Make Silo the only way in and migrate stored data (S7)
**Depends on.** S6.

**Files.**
- [ ] Edit `lib/screens/auth_screen.dart` and `lib/screens/settings/add_connection_screen.dart` to offer Silo only.
- [ ] Edit `lib/media/media_backend.dart` so an unknown id drops the row instead of defaulting to Plex.
- [ ] Edit `lib/database/app_database.dart` to schema 26.
- [ ] Edit `lib/services/storage_service.dart` to clear legacy keys.
- [ ] Create `test/database/schema_26_migration_test.dart`.

**Build.**
- [ ] Schema 26 deletes `connections` rows of kind `plex`, `jellyfin` and `emby`, their `profile_connections`, all `api_cache` rows, downloads and their owners, sync rules, download collections and queued offline progress for those backends. It keeps local profiles.
- [ ] Legacy SharedPreferences keys from `storage_service.dart` lines 15 to 32 are cleared once.

**You see.**
- [ ] An upgraded install opens to the Silo sign-in with local profiles kept and no stale servers.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [ ] `schema_26_migration_test.dart` migrates a seeded schema 25 database and asserts zero Plex, Jellyfin and Emby rows remain and local profiles are kept. Run `flutter test test/database`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on the `swarm workers` role in `p3-models.md` at the PR head, per the boot recipe.
- [ ] Lane 1. Regression lane against trunk. Install trunk signed into Plex, then upgrade to head with `adb install -r`. Save `upgrade.png`. Pass when head opens to the Silo sign-in with no error.
- [ ] Lane 2. Sign into Silo after the upgrade. Save `upgrade-signin.png`. Pass when the home loads.
- [ ] Lane 3. Check the auth screen. Save `auth-silo-only.png`. Pass when no Plex, Jellyfin or Emby option shows.
- [ ] Lane 4. Check settings, Add connection. Save `add-connection.png`. Pass when only Silo shows.
- [ ] Lane 5. Check downloads after the upgrade. Save `downloads-empty.png`. Pass when old downloads are gone and the screen shows no errors.
- [ ] Lane 6. Check local profiles after the upgrade. Save `profiles-kept.png`. Pass when they remain.
- [ ] Lane 7. Fresh install. Save `fresh.png`. Pass when it opens to the Silo sign-in.
- [ ] Lane 8. Relaunch twice after the upgrade. Save `migration-once.png`. Pass when the migration does not rerun.
- [ ] Lane 9. Check logcat after the upgrade. Save `migration-log.png`. Pass when no token or path leaks.
- [ ] Lane 10. Check storage use before and after. Save `storage.png`. Pass when the app data shrinks by at least the old cache size.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [ ] Metric. First launch time after upgrade.
- [ ] Probe. Five upgrades from a trunk install with a full cache, timed from process start to first frame.
- [ ] Baseline. Record trunk's cold start first.
- [ ] Rule. Head's first post-upgrade launch within 2 s of trunk's cold start. Fail above that.

**Review gate.** The operator reviews before merge.
- [ ] Copy lanes 1 and 3 screenshots into `docs/silo-migration/media/s7-review-*.png`.
- [ ] Record a 30 to 60 second video of an upgrade and sign-in. Save it as `docs/silo-migration/media/s7-review.mp4`.
- [ ] Post the screenshots and the video in chat. Stop at merge-ready. Wait for the operator's click.

**Merge.**
- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto S6 after the verdict, patch-id unchanged.
- [ ] Appended to the stack. The operator lands it bottom-up.

## Delete Jellyfin and Emby (S8)
**Depends on.** S7.

**Files.**
- [ ] Delete `lib/services/jellyfin_client.dart`, `lib/services/jellyfin_client/`, every `lib/services/jellyfin_*.dart`, every `lib/services/media_browser_*.dart`, `lib/media/media_browser_dialect.dart`, `lib/models/jellyfin/`.
- [ ] Delete `lib/screens/settings/add_jellyfin_screen.dart`, `lib/screens/settings/edit_jellyfin_connection_screen.dart`, `lib/widgets/quick_connect_code_panel.dart`, `lib/screens/settings/quick_connect_flow_mixin.dart` unless Seerr still needs them.
- [ ] Delete the matching tests under `test/`.
- [ ] Edit the importers the analyzer lists. `plezy-backend-map.md` counts 25 for `jellyfin_api_cache.dart` and 23 for `jellyfin_client.dart`.

**Build.**
- [ ] Remove `JellyfinConnection`, `MediaItem.jellyfin`, the `usesMediaBrowserApi` branches, `SeasonEpisodePagingClient` and `MediaDeletionPermissionClient` if Silo does not implement them.

**You see.**
- [ ] The app behaves exactly as at S7.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [ ] `grep -rli "jellyfin\|emby\|media_browser" lib test` returns only i18n sources and comments listed in S9. Run `flutter analyze && flutter test`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on the `swarm workers` role in `p3-models.md` at the PR head, per the boot recipe.
- [ ] Lane 1. Regression lane against trunk. Run S3's lane 1 scenario at S7 and at head. Save `home.png`. Pass when both match.
- [ ] Lane 2. Repeat S2 lane 2. Save `signin.png`. Pass as there.
- [ ] Lane 3. Repeat S3 lane 2. Save `libraries.png`. Pass as there.
- [ ] Lane 4. Repeat S3 lane 6. Save `detail.png`. Pass as there.
- [ ] Lane 5. Repeat S3 lane 8. Save `search.png`. Pass as there.
- [ ] Lane 6. Repeat S5 lane 1. Save `play.png`. Pass as there.
- [ ] Lane 7. Repeat S5 lane 5. Save `subs.png`. Pass as there.
- [ ] Lane 8. Repeat S6 lane 2. Save `offline.png`. Pass as there.
- [ ] Lane 9. Repeat S4 lane 2. Save `dismiss.png`. Pass as there.
- [ ] Lane 10. Repeat S2 lane 9. Save `signout.png`. Pass as there.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [ ] Metric. Release APK size and cold start to first home row.
- [ ] Probe. Build release APKs at S7 and head. Run ten cold starts each, interleaved.
- [ ] Baseline. Record S7's size and median first.
- [ ] Rule. Head is not larger, and its median is within 5 percent of S7's. Fail otherwise.

**Review gate.** None. S8 is not review-gated.

**Merge.**
- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto S7 after the verdict, patch-id unchanged.
- [ ] Appended to the stack. The operator lands it bottom-up.

## Delete Plex and collapse the seams (S9)
**Depends on.** S8.

**Files.**
- [ ] Delete `lib/services/plex_client.dart`, `lib/services/plex_client/`, every `lib/services/plex_*.dart`, `lib/models/plex/`, `lib/screens/plex_match_screen.dart`, `lib/screens/auth/plex_pin_auth_flow.dart`, `lib/screens/settings/add_plex_account_screen.dart`.
- [ ] Delete `lib/profiles/plex_home_*.dart`, `lib/profiles/active_plex_token.dart`, `lib/profiles/active_plex_identity.dart`, `lib/connection/connection_bootstrap.dart`, `lib/services/server_registry.dart`, `lib/services/play_queue_launcher.dart`, `lib/database/plex_metadata_recovery.dart`, `lib/utils/plex_cache_parser.dart`.
- [ ] Delete `lib/services/catalog/plex_catalog_source.dart` and `lib/services/plex_discover_client.dart`.
- [ ] Delete the live TV screens under `lib/screens/livetv/` and `lib/media/live_tv_support.dart`.
- [ ] Delete the matching tests.
- [ ] Edit `lib/profiles/active_profile_binder.dart`, `lib/services/multi_server_manager.dart`, `lib/profiles/profile.dart`, `lib/main.dart`, `lib/metadata_edit/`, `lib/widgets/library_management_sheet.dart`, `lib/widgets/server_activities_button.dart`, the Seerr auth service and the companion remote auth service.
- [ ] Edit the 22 i18n JSON sources and regenerate.

**Build.**
- [ ] Remove `Profile.plexHome`, `PlexAccountConnection`, `MediaItem.plex` and `PlexHomeService`. The binder keeps only the join-row path. `MultiServerManager` drops relay and endpoint racing.
- [ ] Reduce `MediaBackend`, `Connection` and `MediaItem` to Silo. Remove capability flags Silo never sets, with their UI branches.
- [ ] Derive the companion remote secret from the Silo server id and account id.
- [ ] Remove Seerr sign-in through media-server credentials. Keep Seerr local login if Seerr offers one.

**You see.**
- [ ] The app behaves exactly as at S8, and no screen mentions Plex, Jellyfin or Emby.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [ ] `grep -rliw "plex\|jellyfin\|emby" lib test` returns nothing except the app name. Run `flutter analyze && flutter test`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on the `swarm workers` role in `p3-models.md` at the PR head, per the boot recipe.
- [ ] Lane 1. Regression lane against trunk. Run S3's lane 1 scenario at S8 and at head. Save `home.png`. Pass when both match.
- [ ] Lane 2. Repeat S2 lanes 2 and 7. Save `signin-pin.png`. Pass as there.
- [ ] Lane 3. Walk every settings screen. Save `settings-<n>.png`. Pass when no Plex, Jellyfin or Emby text shows.
- [ ] Lane 4. Repeat S3 lane 7. Save `detail-show.png`. Pass as there.
- [ ] Lane 5. Repeat S5 lane 3. Save `transcode.png`. Pass as there.
- [ ] Lane 6. Repeat S5 lane 9. Save `next-episode.png`. Pass as there.
- [ ] Lane 7. Pair the companion remote. Save `companion.png`. Pass when pairing succeeds.
- [ ] Lane 8. Start Watch Together. Save `watch-together.png`. Pass when the room shows the profile name.
- [ ] Lane 9. Open the sidebar and every library. Save `sidebar.png`. Pass when no live TV entry shows and every library opens.
- [ ] Lane 10. Repeat S7 lane 1 from a trunk install. Save `upgrade.png`. Pass as there.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [ ] Metric. Release APK size and cold start to first home row.
- [ ] Probe. Build release APKs at S8 and head. Run ten cold starts each, interleaved.
- [ ] Baseline. Record S8's size and median first.
- [ ] Rule. Head is not larger, and its median is within 5 percent of S8's. Fail otherwise.

**Review gate.** None. S9 is not review-gated.

**Merge.**
- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto S8 after the verdict, patch-id unchanged.
- [ ] Appended to the stack. The operator lands it bottom-up.

## Close the program
- [ ] Every box above is checked with its evidence.
- [ ] Reply to the operator with the report the execution playbook names.

## Appendix A. Prototype evidence
- The test server is `https://silo.ruleone.xyz`. `GET /api/v2/system/identity` answered 200 with a `server_id`, measured on 2026-10-11.
- `GET /api/v2/auth/device/capability` answered `state: available`, `cancel: true`, `opened_signal: true`, `protocol_versions: [2]`, measured on 2026-10-11 by `/tmp/silo-proto/probe.py`.
- `POST /api/v2/auth/device/start` answered 201 with an 8 digit code and a 900 s lifetime, measured.
- The code expired without approval. The probe withdrew it with `device/cancel`. No session was created and nothing was saved.
- Unproven until the S1 probe runs signed in: the real `section_type` values, the `/playback/capabilities` features, the default artwork size, whether `rating_imdb` sorts, and whether HLS segments are signed in the URL or need headers.

## Appendix B. Alternatives rejected
- **Port Silo's data layer class by class.** It would rewrite most of Plezy's 398k lines and leave a long stretch with nothing running. The operator chose the seam approach.
- **Delete Plex before Jellyfin.** The case for it is that Jellyfin stays as a working sign-in reference. Silo's sign-in is ported from Silo's own Kotlin, so that reference is not needed. Jellyfin and Emby are self-contained, so deleting them first is the smaller, safer step.
- **Keep Plex and Jellyfin beside Silo.** The operator asked for removal.
- **Let mpv fetch segments with static headers.** It cannot refresh on a 401 mid-stream and does not strip credentials on cross-origin redirects. A local proxy matches Silo's transport rules.
- **Map Silo items into the Plex or Jellyfin `MediaItem` variant.** Saved caches would then decode Silo data as another backend. A `silo` variant keeps stored rows honest.

## Appendix C. Risks
- **Data loss on upgrade (S7).** Users lose their Plex and Jellyfin connections, downloads and queued offline progress. This is intended, but it is irreversible on their devices. The S7 review gate is where the operator confirms it.
- **Playback contract fit (S5).** Silo's v3 contract is shaped around Media3. An mpv client that declares only `declared` evidence may get worse plans. The owner watches S5 lanes 2 and 3 for the delivery chosen.
- **Token refresh mid-stream (S5).** Without the proxy, long plays stall. The owner watches S5 lane 7.
- **Profile binder rewrite (S2, S9).** A mistake strands users on the splash or leaks one profile's servers into another. The owner watches S2 lane 8 and S9 lane 2.
- **Persisted unions (S3, S7, S9).** `MediaItem` and `Connection` are stored. A changed union changes how every saved row decodes. The S7 migration test is the guard.
- **Features removed with no Silo equivalent (S9).** Live TV and DVR, Plex Discover, Plex play queues, Plex match and agent editing, library scan and server activities, external subtitle search, and Seerr sign-in through Plex or Jellyfin. Silo-only features such as requests, calendar, ebooks and audiobooks are out of scope for this program.
- **TMDB rows.** Silo's Networks row and movie-collection row need a TMDB key in the build. Plezy ships without them unless the operator supplies a key.
- **Test server limits.** It offers only password and device-code sign-in. OIDC, LDAP, network identity and LAN pairing cannot be tested, so they are not ported.
- **Lane parallelism.** Four parallel research workers hit the API rate limit, and the resumed runs then wrote the same files twice. Lanes run one at a time, and each worker writes only its own output path.
- **Accidental playback.** A key sequence once started a Continue Watching episode during testing and may have moved its resume position by a few seconds. Lanes never press Select on Continue Watching cards.
- **Control surface.** There is no `device_*` driver for the Android TV emulator in this setup, so lanes drive it with `adb`.

## Appendix D. Links and reading list
- `research/silo-auth.md`, `research/silo-catalog.md`, `research/silo-playback.md` and `research/plezy-backend-map.md` must be read before editing.
- S2, S5 and S9 get `skills/how/SKILL.md` before building and `skills/interrogate/SKILL.md` before the verdict, if those skills are installed. They are not installed today.
- The decision trail is kept in `docs/silo-migration/trail.md` per `skills/show-me-your-work/SKILL.md`, one entry per branch verdict.
