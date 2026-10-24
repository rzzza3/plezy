# Silo backend migration plan

Plezy stops talking to Plex, Jellyfin and Emby and talks only to a Silo server. It signs in, reads home sections, browses libraries, opens detail, and plays media with the same wire calls Silo's Android TV app makes. Plezy's screens stay. A Dart `SiloClient` feeds them through the existing `MediaServerClient` seam. The rule the program enforces is call-for-call parity with Silo's Kotlin client, cited to its source, for every request Plezy sends.

The work lands as nine stacked branches on top of `feat/tv-silo-sidebar`, in this order: S1 wire client, S2 sign-in and profiles, S3 catalog and home, S4 realtime and home actions, S5 playback, S6 downloads, S7 Silo-only onboarding and data migration, S8 delete Jellyfin and Emby, S9 delete Plex and collapse the seams.

## How to read this
One box is one unit of work. Every box names the evidence that checks it. A nested box is a sub-step of the box above it. Check a box only when its evidence exists, a file, a log line, a screenshot, a test run, or a SHA. The body is a how-to. The appendices explain and record.

The program runs `skills/p3-mode/playbooks/autopilot-stack.md`. The root builds and verifies each branch and appends it to one linear stack. The operator reviews the review-gated branches and lands the stack bottom-up. S2, S3, S4, S5, S7 and S9 are review-gated because they change what the user sees or does.

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

**S1 verdict, 2026-10-12, head `77ea44191`.** Clean for the lanes it can run without the app. Logs are in `/tmp/silo-probe-*.log`.
- Unit. `flutter test --concurrency=1 test/silo` passes 57 tests. `flutter analyze` is clean.
- Lane 2 pass. Device-code sign-in, seven reads, `home 200 sections=17`, `logout 204`.
- Lane 3 pass. The server reported the unapproved code `expired` after about 14 minutes. The probe printed `code expired; no tokens written`, and only the three pre-sign-in samples exist.
- Lane 5 pass. `identity 200 authorization_header=absent`.
- Lane 6 pass. A locally expired token gave `refresh count=1` and `home 200`.
- Lane 7 pass. After `revoke_logout 204`, reusing the old tokens gave `refresh count=1` and `session expired`.
- Lane 8 pass. The samples hold field names, types and counts only, plus Silo's fixed `section_type` labels.
- Lane 10 pass. All five runs sent device id `5e9d27c1-…`.
- Perf pass. Twenty home calls each, `SiloHttp` median 439 ms, bare `dart:io` client with the same headers 440 ms, delta −1 ms. An unauthenticated keep-alive `curl` to the same URL has a median of 182 ms, so the rest is server work and payload.
- Moved to S2, because S1 adds no code the app runs. Lane 1 (Plex home unchanged), lane 4 (network drop mid-poll) and lane 9 (`CredentialVault` storage on device).

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

**S2 verdict, 2026-10-13, head `f634b1f7b` plus this record.** Clean for every lane. Lanes ran on the Android TV emulator with debug builds. Monday's lanes ran at `61d2ecf5e`, and today's at `74d4e0d7f`. Evidence is in `docs/silo-migration/media/s2/` and `docs/silo-migration/media/s2-review*`, and audits are in `docs/silo-migration/audits/`.
- Unit. `flutter test --concurrency=1 test/silo` passes 85 tests. `flutter analyze lib test tool` is clean.
- Lane 1 pass, today. After a fresh Plex sign-in, head shows the Plex home with its rows (`lane-1-plex-home.png`). Plezy gives a Plex approval 2 minutes (`PlexAuthService.pollPinUntilClaimed`), an upstream limit S2 does not touch.
- Lane 2 pass, today. The log reads `device code approved`, then `signed in`, with no withdrawal (`lane-2-code-approval.log`). The picker listed 3 profiles and the operator entered admin.
- Lane 3 pass, Monday. A password sign-in reached the picker and withdrew the code.
- Lane 4 pass, today. A wrong password for admin shows "Invalid credentials", the code stays up, and the log reads `password refused (invalidCredentials)` (`lane-4-wrong-password.png`, `.log`).
- Lane 5 pass, at `d0f61223d`. Back withdraws the code, `device code withdrawn, status 200` (`lane-5-code.png`, `lane-5-leave.png`, `.log`).
- Lanes 6 and 7 pass, Monday. A wrong PIN logged "PIN rejected" twice and the picker stayed. The right PIN entered the profile.
- Lane 8 pass, today. A force-stop and relaunch gives a new process with Silo online and no new code (`lane-8-relaunch.png`, `.log`).
- Lane 9 pass, today. While signed in, the session key holds `enc:v1:` ciphertext and no token field names appear in prefs. Log out gets `logout status 204` and removes the key while keeping `silo_device_id` (`lane-9-storage.txt`, `lane-9-signout.log`, `lane-9-signed-out.png`).
- Lane 10 pass, at `d0f61223d`. "Can't reach this server." (`lane-10-unreachable.png`, `.log`).
- Perf pass, at `74d4e0d7f`. Ten opens from `login screen opened` to `device code shown`: 1081 1085 1089 1091 1094 1103 1105 1106 1108 1123 ms, median 1098.5 ms, under the 1.5 s rule. Before the fix at `55a441413` the median was 1524.5 ms. The 426 ms saved is the second TLS handshake `open()` paid when it discarded the identity read's client.
- Review gate. `media/s2-review.mp4` (42 s) shows the code screen, "Signed in as admin", the picker and home. Stills are `media/s2-review-signed-in.png`, `media/s2-review-picker.png` and `media/s2-review-sheet.png`. Waiting for the operator's go.
- Audits. Secrets H1 (full Logout left the Silo session alive) is fixed in `d0f61223d`. Wire-parity M1 (single-attempt logout) is fixed in `8b1deaf17`. Open: secrets M1 (a slot outlives a process killed on the picker), secrets L1, wire-parity L1 to L6. Two UI notes from the live run: on an empty home Left does not reach the sidebar (Back does), and the profile menu opens as a bottom sheet rather than beside the sidebar.

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
- [ ] Lane 10. Switch profile and reopen the home. Save `profile-switch.png`. Pass when the home shows the new profile's rows. Until S9 a Silo profile is reached through a Plezy profile, so this lane uses two Plezy profiles bound to different Silo profiles (`media/s3/lanes-howto.md`).

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [ ] Metric. Cold start to first home row painted. Trunk produces it with Plex. Head produces it with Silo.
- [ ] Probe. Ten cold starts each, interleaved trunk and head, timed from process start to the logcat line for the first hub frame.
- [ ] Baseline. Record the trunk median first.
- [ ] Rule. The scenarios differ, so use an absolute budget. Head median under 5 s on the emulator with the debug build the boot recipe installs. Fail above that. The operator set this on 2026-10-14, and S9 measures the 2.5 s release budget.

**Review gate.** The operator reviews before merge.
- [ ] Copy lanes 1, 6 and 7 screenshots into `docs/silo-migration/media/s3-review-*.png`.
- [ ] Record a 30 to 60 second video of home, a library, and a detail. Save it as `docs/silo-migration/media/s3-review.mp4`.
- [ ] Post the screenshots and the video in chat. Stop at merge-ready. Wait for the operator's click.

**Merge.**
- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto S2 after the verdict, patch-id unchanged.
- [ ] Appended to the stack. The operator lands it bottom-up.

**S3 lane record, 2026-10-14, code at `35342075d` (no `lib/` change since).** Clean at `22fd99401` for every lane except lane 10, which waits for S9. The two audit lanes found two medium issues, both fixed, tested and rechecked live (`audits/s3-wire-parity.md`, `audits/s3-secrets.md`). Lanes ran on the Android TV emulator with debug builds, on the Plezy profile "Silo A". Evidence is in `docs/silo-migration/media/s3/`.
- Unit. `flutter test --concurrency=1 test/silo` passes 122 tests. `flutter analyze lib test tool` is clean.
- Lane 1 pass, confirmed by the operator against the Silo app. Trunk `5fc148779` shows the Plex home (`lane-1-home-trunk.png`). It logs `failed to decode connection silo:…` for the stored Silo row and leaves the row intact. Head shows 17 Silo rows, matching `Silo: home sections 17`, with Continue Watching first as backdrop cards (`lane-1-home-head.png`, `lane-1-home-rows.png`). Server order is also pinned by unit test.
- Lane 2 pass. All 9 Silo libraries open with items (`lane-2-libraries.png`).
- Lane 3 pass. Sport PPVs Browse scrolled about 230 items, past two 100-item cursor pages, A to Z with no restart, and logcat has no `invalid_cursor` (`lane-3-scroll.png`, `lane-3-library-end.png`).
- Lane 4 pass. Genre Animation on Movies shows only animated titles, and an opened one is tagged animation (`lane-4-library-genre.png`, `lane-4-genre-item.png`).
- Lane 5 pass. The A to Z rail at M lists titles from M3GAN on (`lane-5-library-az.png`).
- Lane 6 pass, confirmed by the operator against the Silo app. A movie detail shows title, year, rating, runtime, synopsis, director and cast (`lane-6-detail-movie.png`).
- Lane 7 pass, confirmed by the operator against the Silo app. Top Gear (2002) opens on Series 13 with S13E1 offered, the season of its Continue Watching episode, as `siloInitialSeason` picks (`lane-7-detail-show.png`).
- Lane 8 pass. "Top Gear" returns 40 results in 843 ms, the series among them (`lane-8-search.png`).
- Lane 9 pass. Mark as watched shows "Marked as watched", the card gains a watched badge, and a reopened detail reads watched (`lane-9-watched.png`). It was toggled back, and a reopened detail reads unwatched (`lane-9-restored.png`).
- Lane 10 deferred to S9 by the operator, because profile switching becomes native there.
- Perf pass under the 5 s debug rule. Ten cold starts each, process start to `Home: first hub frame`. Trunk on Plex has median 6648.5 ms (6207 to 6941). Head on Silo has median 4482 ms (4402 to 4716). Head is 2.2 s under trunk. One head run splits into 0.77 s to Dart main, 1.96 s app start to the main screen, 1.61 s for the home read and hydration, and 0.14 s to paint (`perf-*.txt`). Every number is a debug build, which the boot recipe requires. The operator set the 5 s debug rule and moved the 2.5 s release check to S9. A profile build does install over the debug one and keep app data, because release is debug-signed while `android/key.properties` is absent. Session plezy-c5 reported a 3340 ms profile median on "Silo A", not rerun here.
- Audits. Wire parity M1 (people search sent no `media_scope`) is fixed in `86c98f005`. M2 (half-star ratings rounded up on Silo) is fixed in `e5a6b883e`. L3 (the rate sheet said "Plex - Silo") is fixed in `22fd99401`. Open lows are search reading one page, persisted presigned artwork URLs, and `_parents` outliving a profile switch. The fixes touch search and rating only, rechecked live at `22fd99401` (`recheck-search-people.png`, `recheck-rate-sheet.png`).
- Review gate. `media/s3-review.mp4` (44 s) shows home, the Movies library and a movie detail. Stills are `media/s3-review-home.png`, `media/s3-review-detail-movie.png` and `media/s3-review-detail-show.png`.

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

**S4 lane record, 2026-10-14, debug build of `68bc6a099`. The only later `lib/` change is the M1 fix in `02f92bd28`.** Clean for every lane. The operator waived lane 3 on 2026-10-14. Lanes ran on the Android TV emulator with Plezy profile "Silo A" (Silo profile admin, `2b4a12c9-…`). Changes outside Plezy came from `tool/silo_probe.dart --actions` in one device-code session that the operator approved once (`media/s4/lanes-howto.md`). Evidence is in `docs/silo-migration/media/s4/`. Times run from the probe's 204 to the device log line, with the host-to-device clock offset taken through `adb shell date`.
- Unit. `flutter test --concurrency=1 test/silo` passes 148 tests. `flutter analyze lib test tool` is clean.
- Lane 1 pass. Marking a Recently Released movie watched shows the badge, with `user_state.changed (watched)`, `home refetch` and `Home: rows repainted` 3.23 s after the 204 (`realtime-head.png`, `lane-1.log`). Trunk has no Silo, as in S3 lane 1.
- Lane 2 pass. Menu (keyevent 82) on a Continue Watching card, then Remove from Continue Watching. The card goes, the server echoes `home_dismissal`, and it is still gone after a force-stop and relaunch (`dismiss.png`, `lane-2-relaunch.png`).
- Lane 3 waived by the operator. This server's home has no `next_up` row, so the lane had nothing to act on. The Next Up dismissal is covered by the unit test "a next up card sends its series_id anchor".
- Lane 4 pass. Airplane mode does not cut this emulator, so Plezy alone was blocked through `FIREWALL_CHAIN_OEM_DENY_3` for 60 s. Ticket attempts backed off 1, 2, 4, 8, 16 and 30 s, and after the unblock the socket subscribed and refetched once (`reconnect.png`, `lane-4.log`).
- Lane 5 pass. A switch to the Plex profile logs `Silo events: idle` and `closed`, and a Silo watched change afterwards logs nothing (`realtime-profile.png`, `lane-5.log`).
- Lane 6 pass. Over 10 idle minutes the socket reconnected at each 5-minute ticket limit with a 1 s backoff. Catalog event bursts of 2 to 5 each became one refetch, and a watched change after the idle repainted in 3.26 s (`idle.png`, `lane-6.log`).
- Lane 7 pass. A watchlist add puts the movie first in My Watchlist 3.68 s after the 204, and it was removed again (`watchlist-event.png`, `lane-7.log`).
- Lane 8 pass. Home closes the socket. A watched change made while backgrounded shows on resume after a new ticket and one refetch, in the same process (`resume.png`, `lane-8.log`).
- Lane 9 pass. The profile sheet's Log out signs out every account, Plex included, so Silo was removed from "Silo A" instead. `Silo: logout status 204` is followed by `idle` and `closed` 6 ms later, with no ticket fetch after it (`signout-socket.png`, `lane-9.log`). The operator approved a new code, and "Silo A" is back on the same Silo profile.
- Lane 10 pass. No ticket or token appears in logcat (`ticket-log.png`, `lane-10-ticket-scan.txt`).
- Perf pass. Ten flips, from the 204 to `Home: rows repainted`: 3.68 2.95 2.58 2.52 2.55 2.60 2.57 2.56 2.53 2.54 s, median 2.561 s, under the 3 s rule. The baseline, from the 204 to frame delivery, has a median of -19 ms, because the server pushes before its reply reaches the host. A typical run is 2.00 s of debounce, about 0.55 s of home read and about 0.04 s of paint (`perf.txt`).
- Plex regression. The Plex profile home loads with its rows (`plex-profile-home.png`).
- Audits. Wire parity M1 (the events upgrade sent no device headers) is fixed in `02f92bd28`, with a test. It was rechecked live: the socket still subscribes and logcat holds no ticket (`m1-recheck.log`). The other findings are lows (`audits/s4-wire-parity.md`, `audits/s4-secrets.md`).
- Review gate. The operator tested the build and approved it. `media/s4-review.mp4` (52 s) shows a live watched badge appearing and clearing, then a dismissal. Stills are `media/s4-review-*.png`.
- Findings. Silo sends `subscribed` twice per connection, and the debouncer merges them. Single-attempt writes are not refreshed first, as in Kotlin, so a write after a long gap with no reads can return 401. While Plezy is foregrounded, the socket's ticket request refreshes the token at least every 5 minutes.
- Verdict. Clean at `6d6b2f817`. The full `flutter test --concurrency=1` passes 8093 tests with 6 skipped, `flutter analyze lib test tool` is clean, every live and perf lane passes with lane 3 waived, and both audits are done with M1 fixed. S4 sits on S3's tip `a9716d723`, so no rebase was needed. The operator deferred Bugbot triage for the whole stack to the end of the plan. Nothing is pushed.

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

**S5 lane record, 2026-10-15 to 2026-10-16, debug builds of `feat/silo-s5-playback`. The last `lib/` change is `810d3ae28`.** Lanes ran one at a time on the Android TV emulator `Television_1080p`, on the Plezy profile "Silo A" (Silo profile admin) against `https://silo.ruleone.xyz`, per `media/s5/lanes-howto.md`. Evidence is in `docs/silo-migration/media/s5/`. Every lane except 7 passes. The perf rule fails.
- Items. M is Love of Your Life (`movie-tmdb-1381078`). A and S are Ponyo (`movie-tmdb-12429`, 2 audio tracks, 22 subtitles). E is Taskmaster (SE) S7E9 (`episode-tvdb-386002-7-9`), with S7E10 next. Perf trunk plays Plex "Clown Panic" (the SmellyCats copy, 1080p H.264). Dementium (`movie-tmdb-1746176`) was played by someone outside the run and restored.
- Fixes found by the lanes. `4814ca384` addresses the file the plan plays (`effective_media_file_id`), not the one asked for. `810d3ae28` resolves the carried audio choice on a start or replan.
- Lane 1 pass. Trunk plays Clown Panic on Plex. Head plays M at `original_http`, and M's detail page shows Resume after Back (`lane-1-*.png`, `lane-1-head.log`, `lane-1-trunk.log`).
- Lane 2 pass. `plan delivery=original_http` with rendered video (`lane-2-direct.png`, `lane-2.log`).
- Lane 3 pass after `4814ca384`. 480p in the player logs `replanned quality_change, delivery=server_transcode_hls` and video renders (`lane-3-transcode.png`, `lane-3.log`). `lane-3-before-fix.log` shows the stop-and-restart the fix removed.
- Lane 4 pass after `810d3ae28`. On direct play mpv switches audio itself. On the transcode, Japanese logs `replanned track_change` (`audio-switch.png`, `lane-4.log`).
- Lane 5 pass on Original. The embedded English SRT renders and clears (`subs.png`, `subs-off.png`).
- Lane 6 pass. M at 480p seeked from 0:52 to about 39:00 plays on, with no `seek_reanchor`, as expected with `can_seek_anywhere` (`seek-replan.png`, `lane-6.log`).
- Lane 7 cut by the operator after 126 s of clean play. It says nothing about the token lifetime (`lane-7-cut.log`).
- Lane 8 pass. After a force-stop mid-play, the next start logs `stopped (status 200)` 0.44 s before `started` (`journal.png`, `lane-8.log`).
- Lane 9 pass. Finishing E9 logs `Video completed: action=presentNext` and offers S7 E10 (`next-episode.png`, `lane-9.log`). The re-run is described in the lane 9 finding below.
- Lane 10 pass. M stopped at 10:09 (last sample 609 s). The Silo TV app shows "Resume 10:09" on M without playing it (`position-sync.png`, `lane-10.log`).
- Perf fail. From the key event to `Perf: first frame`, trunk (Plex, Clown Panic) sorted: 2.479 2.500 2.515 2.549 2.734 2.764 2.920 3.397 3.622 3.959 s, median 2.749 s. Head (Silo, M at Original, all ten `original_http`) sorted: 4.562 4.616 4.741 4.828 4.846 4.860 4.946 5.023 5.042 6.794 s, median 4.853 s, above the 3 s rule. Head resumed M from 602 s. Three diagnostic head plays from the beginning took 2.796 2.885 3.188 s, median 2.885 s. So about 2 s of the head median is mpv opening the original at a 602 s offset over the proxy. Trunk started Clown Panic a few seconds in, so the two sides did not start at the same offset. Plays ran in blocks of five per build (trunk, head, trunk, head), because each build swap also needs a profile switch. The marker was in both APKs and was never committed. The clean head build was reinstalled afterwards (`perf.txt`, `perf-plays.log`).
- Perf re-run at equal offset. One marker build, both sides resumed from 627 to 663 s, alternating. Plex (Clown Panic) median 4.653 s, Silo (M, `original_http`) median 4.871 s, a 0.218 s gap. So the first run's 2.1 s gap was the resume offset, not Silo. Neither side meets the 3 s rule on a resume at that offset on the emulator, which is an operator call on the rule. Debug timelines put most of both on mpv's four sequential range requests at the seek target. Silo's slow tail follows the server's first byte on that request (0.61 to 2.02 s). Side finding, not root-caused: the debug app hit Dart heap exhaustion several times, mostly during Plex hub loads, once aborting the process. Silo M, Plex Clown Panic and the Silo copy of Clown Panic (which picked up the Plex progress through server sync) were restored, and the clean head was reinstalled (`perf.txt`).
- Lane 9 finding. Plezy matches Kotlin. The final position goes out as one more sequenced progress sample before the stop (`A/player/PlaybackSessionLifecycle.kt:894-900`, `S/repository/SequencedPlayback.kt:394-423`). The stop carries a sample only when the last one is unreceipted (`S/repository/SequencedPlayback.kt:433-459`). Kotlin sends no separate played mark at the end of playback. The server marks a finished episode played later. Lane 9 read nothing at 0 s and 30 s after the stop, but E9 was found watched (check mark, 58min) hours later. The re-run unwatched E9, finished it again (last sample 3537 s, stop 11:51:34) and found it watched at 12:06:02. The events socket stayed subscribed and carried no `user_state.changed` for it (`lane-9-rerun.log`, `lane-9-rerun-*.png`). Which short positions the server keeps is server behaviour this run did not pin down. M at 136 s and Dementium at 177 s read back empty, while M at 609 s and Ponyo at 232 s and 319 s resumed. The re-run also hit mpv's spurious-EOF recovery at 3537.2 s, which opened one more session before Up Next.
- Open issue 1. At 480p, Silo answers the VTT sidecar in about 220 ms but streams its body over 24 to 32 s. Plezy's sidecar guard waits 10 s (`lib/services/mpv_sidecar_open_guard.dart:28-29`) and reopens without subtitles (`lane-5-sidecar-480p.log`, `lane-5-sidecar-480p.png`). Not fixed in S5.
- Open issue 2. After an audio switch on direct play, a quality change drops the chosen audio (`lane-4-audio-after-quality.png`). Not fixed in S5.
- Restores. M, Ponyo, Dementium and E9 went back to unwatched, by the probe's `unwatched` early on and by Plezy's own Mark as Unwatched later, which sends the same `DELETE /api/v2/watched/{id}`. E10 never changed. Plex Clown Panic holds no progress. Lane 1's position is gone, and the perf plays left none. After a force-stop and relaunch, each item matches its `before-*.png` (`after-*.png`). Probe reads are in `server-state.txt`.
- Review gate. Stills are `media/s5-review-lane1-resume.png`, `-lane3-transcode.png`, `-lane5-subs.png` and `-lane5-subs-off.png`. Lane 1's play shot is a near-black opening frame, so it is left out. `media/s5-review.mp4` (56 s, Ponyo) shows a resume, a switch from English to Japanese with the sheet reopened to show the check, a seek, a stop at Resume, then a resume 7 s before the stop and a second stop.
- Verdict. Approved by the operator ("Go", 2026-10-16) at `e1fbda206`, with the perf result as recorded: at equal resume offset Silo is 0.22 s behind Plex and neither meets 3 s. Open issues 1 and 2, mpv's spurious-EOF extra session, and the Dart heap exhaustion carry forward unfixed. Lane 7 was cut by the operator. The operator deferred Bugbot triage for the whole stack to the end of the plan. Nothing is pushed.

## Download Silo media for offline play (S6)
**Depends on.** S5.

**Files.**
- [x] Create `lib/silo/silo_downloads.dart`.
- [x] Edit `lib/services/silo_client.dart` at `resolveDownload`, `resolveDownloadArtwork`, `stampLibrary`.
- [x] Edit `lib/services/download_manager_service.dart` where the file request is built.
- [x] Create `test/silo/silo_downloads_test.dart`.

**Build.**
- [x] Follow `research/silo-playback.md` section 7. Gate on `/capabilities/downloads`, create with `POST /downloads` once, stream `GET /downloads/{id}/file` with `Range` and `If-Range`, fetch `/manifest` for tracks, and report state with `PATCH` and a revision.
- [x] Download rows use the `silo:<server_id>/<profile_id>` scope id.
- [x] Offline progress syncs through the personal-data progress path, not playback sessions.

**You see.**
- [x] Download on a movie completes, and the movie plays with the network off.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [x] `silo_downloads_test.dart` asserts a resume sends `Range: bytes=N-` and `If-Range`, and a 416 restarts from zero. Run `flutter test test/silo`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on the `swarm workers` role in `p3-models.md` at the PR head, per the boot recipe.
- [x] Lane 1. Regression lane against trunk. Download a movie at trunk with Plex and at head with Silo. Trunk lacks Silo, so gate head's completed download. Save `download-head.png`. Pass when it completes.
- [x] Lane 2. Play the download offline. Save `offline-play.png`. Pass when video renders.
- [x] Lane 3. Interrupt the network mid-download. Save `download-resume.png`. Pass when it resumes, not restarts.
- [ ] Lane 4. Download an episode with subtitles. Save `download-subs.png`. Pass when subtitles render offline.
- [x] Lane 5. Watch offline, then go online. Save `offline-sync.png`. Pass when the server shows the position.
- [x] Lane 6. Delete the download. Save `download-delete.png`. Pass when the file is gone.
- [ ] Lane 7. Retry a failed download in bulk. Save `download-retry.png`. Pass when it completes.
- [ ] Lane 8. Download a season. Save `download-season.png`. Pass when every episode completes.
- [ ] Lane 9. Switch profile. Save `download-profile.png`. Pass when the other profile cannot see this download.
- [x] Lane 10. Relaunch offline. Save `offline-launch.png`. Pass when the downloads list opens.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [x] Metric. Download throughput for one 1 GB file. Trunk produces it with Plex. Head produces it with Silo.
- [ ] Probe. Three downloads each, interleaved, timed from start to completion.
- [ ] Baseline. Record `curl` throughput for the same Silo file first.
- [ ] Rule. Head throughput at least 80 percent of `curl`. Fail below that.

**Review gate.** None. S6 is not review-gated.

**Merge.**
- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto S5 after the verdict, patch-id unchanged.
- [ ] Appended to the stack. The operator lands it bottom-up.


**S6 lane record, 2026-10-20 to 2026-10-21, debug builds of `feat/silo-s6-downloads`. The last `lib/` change is `fc35e90e9`.** Lanes ran one at a time on the Android TV emulator `Television_1080p`, on the Plezy profile "Silo A" (Silo profile admin) against `https://silo.ruleone.xyz`, per `media/s6/lanes-howto.md`. Trunk is `5fc148779` on the Plex profile. Evidence is in `docs/silo-migration/media/s6/`. Lanes 1, 2, 3, 5, 6 and 10 pass. Lanes 4, 7 and 8 did not finish. Lane 9 was skipped by the operator.
- Items. Taskmaster (US) S1E1 "Physics" (`episode-tvdb-344961-1-1`, 441,046,679 B) stood in for Movie M in lanes 1 to 3, 5, 6, 10 and perf, and its RULEONE Plex copy is the trunk side. Lanes 4 and 7 used Taskmaster (SE) S7E9 and S7E10.
- Fixes found by the lanes. `86981ee05` reads download progress against the entry size when the response has no Content-Length. `fc35e90e9` keeps Silo download metadata for offline use (a `SiloApiCache`, the scope read from the profile's `profile_connections` row) and replaces the Downloads TV Shows stub that crashed on a Silo episode.
- Unit pass. `flutter test test/silo test/services/download_manager_service_test.dart` at `fc35e90e9`: 349 tests pass.
- Lane 1 pass. Trunk downloads the Plex copy (`download-trunk.png`). Head logs `Started Silo transfer` at 22:23:01 and `Download completed` at 22:34:48, with no `report failed` (`download-head.png`, `lane-1-head.log`).
- Lane 2 pass. The download plays with the app's network cut (`offline-play.png`).
- Lane 3 pass. The network was cut at 132,382,720 B. The next attempt logs `Silo downloads: resuming at byte 132415488` and completes at 22:58:35, with no `restarting from zero` (`download-resume.png`, `lane-3.log`).
- Lane 4 not done. The S7E9 download was resuming at 8 % when the operator cancelled the run and said to assume it works. Subtitles were not shown offline.
- Lane 5 pass. Stopped offline at about 10:34. The queued row held `view_offset=640430`. After network on and Reconnect the queue emptied, and the server read back `viewOffsetMs=640430` (`offline-sync*.png`, `lane-5.log`). The emulator's per-app firewall toggle raises no connectivity event, so the queue flushed only on the in-app Reconnect.
- Lane 6 pass. The row is gone and no `.part`, `.part.silo` or video file remains (`download-delete.png`, `lane-6-files.txt`).
- Lane 7 not done. With E9 and E10 queued, the network was cut at 100.3 MB into E9. E9 used its three retries and failed, and Retry all on Season 7 resumed it (`resuming at byte 103940096`). E10 never transferred, because its create was refused with 429 (open issue 1). Both rows read failed before the retry (`download-retry-failed.png`). The run was cancelled before either completed.
- Lane 8 not run, on the operator's call. Open issue 1 would very likely stop every episode after the first.
- Lane 9 skipped by the operator.
- Lane 10 pass after `fc35e90e9`. Before the fix the download vanished from Downloads after an offline relaunch (`offline-launch-before-fix.png`, `lane-10-before-fix.log`). After it, the list opens offline with artwork and the item plays (`offline-launch.png`, `offline-launch-manage.png`).
- Perf. Taskmaster (US) S1E1, 441,046,679 B, timed from Select to `Download completed`. Trunk on Plex took 20.32, 22.41 and 6.69 s (median 20.32 s, 21.7 MB/s). T3 was probably served from the Plex server's cache. Head on Silo ran once: 712.40 s, 0.619 MB/s. The operator waived the curl baseline and the 80 percent rule (2026-10-21), because the Silo server is capped at about 0.62 MB/s. H1 matches that cap, so the app adds no measurable cost. H2 and H3 were skipped with the operator's leave (`perf.txt`).
- Incident. Game of Thrones moved to S4E9 on Plex and Silo, with E6 to E8 watched, after 18:19 on 2026-10-20. The lanes' only touch was an accidental play of about 10 s, so another viewer moved it. It was left as is (`incident-got-before.png`, `incident-got-s4-now.png`).
- Restores. Taskmaster (US) S1E1 is unwatched with no progress on Silo and both Plex copies, and Continue Watching matches the before shots (`before-*.png`, `after-*.png`). Taskmaster (SE) S7E9 and S7E10 were never played and match `before-taskmaster-se-s7e9-e10.png`. Every download is deleted, `/data` has 7.1 GB free, and the clean `fc35e90e9` build is installed. The server's download registry keeps its entries, since Plezy sends no `DELETE /api/v2/downloads/{id}`.
- Open issue 1. A create sent while another Silo download from this device is active is refused with `429 rate_limited` (`POST /api/v2/downloads`). The operator confirmed this is the server's rule: one download at a time per device. It is not a Plezy bug. Plezy still fails a second queued row with no auto-retry and the text "an unexpected error occurred" (`_isRetryablePrepareFailure`, `lib/services/download_manager_service.dart:2795`), where it could wait for the active transfer instead. Carried forward, not blocking.
- Open issue 2. A Silo series' cache row stays pinned after its last episode is deleted. This happens on every backend. The delete dialog for a single-episode group names the show, not the episode.
- Verdict. Passed by the operator (2026-10-21) at `fc35e90e9`. The operator accepted lanes 4, 7 and 8 without a re-run, kept lane 9 skipped, and accepted perf on H1 alone with the curl baseline and the 80 percent rule waived. Open issues 1 and 2 carry forward unfixed. Nothing is pushed.

## Make Silo the only way in and migrate stored data (S7)
**Depends on.** S6.

**Files.**
- [x] Edit `lib/screens/auth_screen.dart` and `lib/screens/settings/add_connection_screen.dart` to offer Silo only.
- [x] Edit `lib/media/media_backend.dart` so an unknown id drops the row instead of defaulting to Plex.
- [x] Edit `lib/database/app_database.dart` to schema 26.
- [x] Edit `lib/services/storage_service.dart` to clear legacy keys.
- [x] Create `test/database/schema_26_migration_test.dart`.

**Build.**
- [x] Schema 26 deletes `connections` rows of kind `plex`, `jellyfin` and `emby`, their `profile_connections`, all `api_cache` rows, downloads and their owners, sync rules, download collections and queued offline progress for those backends. It keeps local profiles, because S9 replaces them with Silo profiles and migrates them then. Silo `api_cache` rows are kept (operator decision, 2026-10-21).
- [x] Legacy SharedPreferences keys from `storage_service.dart` lines 15 to 32 are cleared once.

**You see.**
- [ ] An upgraded install opens to the Silo sign-in with local profiles kept and no stale servers. Not seen as written: on the current data, which holds a Silo connection, the upgrade opens to the profile picker (operator decision), and lane 7 was skipped.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [x] `schema_26_migration_test.dart` migrates a seeded schema 25 database and asserts zero Plex, Jellyfin and Emby rows remain and local profiles are kept. Run `flutter test test/database`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on the `swarm workers` role in `p3-models.md` at the PR head, per the boot recipe.
- [x] Lane 1. Regression lane against trunk. Install trunk signed into Plex, then upgrade to head with `adb install -r`. Save `upgrade.png`. Pass when head opens to the Silo sign-in with no error.
- [x] Lane 2. Sign into Silo after the upgrade. Save `upgrade-signin.png`. Pass when the home loads.
- [x] Lane 3. Check the auth screen. Save `auth-silo-only.png`. Pass when no Plex, Jellyfin or Emby option shows.
- [x] Lane 4. Check settings, Add connection. Save `add-connection.png`. Pass when only Silo shows.
- [x] Lane 5. Check downloads after the upgrade. Save `downloads-empty.png`. Pass when old downloads are gone and the screen shows no errors.
- [x] Lane 6. Check local profiles after the upgrade. Save `profiles-kept.png`. Pass when they remain.
- [ ] Lane 7. Fresh install. Save `fresh.png`. Pass when it opens to the Silo sign-in. Skipped by the operator.
- [x] Lane 8. Relaunch twice after the upgrade. Save `migration-once.png`. Pass when the migration does not rerun.
- [x] Lane 9. Check logcat after the upgrade. Save `migration-log.png`. Pass when no token or path leaks.
- [x] Lane 10. Check storage use before and after. Save `storage.png`. Pass when the app data shrinks by at least the old cache size.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [x] Metric. First launch time after upgrade.
- [x] Probe. Five upgrades from a trunk install with a full cache, timed from process start to first frame.
- [x] Baseline. Record trunk's cold start first.
- [x] Rule. Head's first post-upgrade launch within 2 s of trunk's cold start. Fail above that.

**Review gate.** The operator reviews before merge.
- [x] Copy lanes 1 and 3 screenshots into `docs/silo-migration/media/s7-review-*.png`.
- [x] Record a 30 to 60 second video of an upgrade and sign-in. Save it as `docs/silo-migration/media/s7-review.mp4`.
- [x] Post the screenshots and the video in chat. Stop at merge-ready. Wait for the operator's click.

**Merge.**
- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto S6 after the verdict, patch-id unchanged.
- [ ] Appended to the stack. The operator lands it bottom-up.


**S7 lane record, 2026-10-21, debug builds of `feat/silo-s7-silo-only`.** Lanes ran one at a time on the Android TV emulator `Television_1080p`, per `media/s7/lanes-howto.md`, on the emulator's current data (the operator's choice, no `pm clear`). Trunk is `5fc148779`. Lanes 1 and 3 to 10 ran on `d4d78b2a4` (code head `bed4e1d5b`). Lane 2's shot, the perf lane and the review video ran on `30bb0a60f`, after the two fixes below. Evidence is in `docs/silo-migration/media/s7/`. Lanes 1 to 6 and 8 to 10 pass, lane 7 was skipped by the operator, and perf passes.
- Operator decisions (2026-10-21). Removed downloads keep their files on disk. Silo `api_cache` rows are kept. The migration also removes Plex music sessions and `plex_home` profile rows. Lane 1 runs on the current data and passes on the profile picker or the `Silo A` home. Lane 2 records the `Silo A` home with no new sign-in. Lane 3 must not sign out of the Silo server. Lane 7 is skipped.
- Starting state. Trunk on the Plex Home profile NotVeryPrivateAccount (active), plus the local profile `Silo A` bound to the Silo profile admin. There is no `Silo B`. One completed Plex download, Taskmaster (US) S1E1 from the RULEONE copy (441,046,679 B), was made for lane 5 and left unwatched. `api_cache` held 10 rows, 65,278 B: 8 Plex rows (58,933 B) and 2 Silo rows (6,345 B).
- Backup. `run-as` tar of `app_flutter`, `files`, `shared_prefs`, `databases` and `no_backup` into `~/plezy-s7/backup` (mode 700): 617,499,648 B, sha256 `153d7fdd17ff2796c2395c49180d8ff35cb72956c3bd2e69199b11434476e949`. It listed `plezy_downloads.db` with its WAL, the preferences DataStore and the Plex file. Restore targets are `before-trunk-home.png`, `before-profiles.png` and `downloads-before-trunk.png`.
- Fixes found by the lanes. `bd327dedc` stops `CredentialVault` from calling `reloadCache` on the app-wide preference cache, which empties it until the store answers. After the upgrade the first credential reveal is the bind of the profile picked in the startup picker, and in that window the active profile id read as null, so the bind reported failure and the picker stayed open (`upgrade-picker-stuck-before-fix.png`, `picker-fix.log`). `30bb0a60f` replaces the Settings > Add connection subtitle, which still named Plex, Jellyfin and Emby (`settings-subtitle-before-fix.png`, `settings-subtitle-after-fix.png`). Both have tests.
- Unit pass. `flutter test test/database` at `30bb0a60f`: 167 tests pass. The vault, preference, profile and database suites (472) pass at `bd327dedc`, and `test/i18n` with `test/screens/settings` (154) at `30bb0a60f`.
- Lane 1 pass. Head opened to the profile picker with only `Silo A (Silo)`, no Plex profile, no Plex server and no error (`upgrade.png`). The migration line appeared once. There was no `Could not reclaim space` or `Unknown MediaBackend` line.
- Lane 2 pass at `30bb0a60f`. Picking `Silo A` in the startup picker opens the `Silo A` home (`upgrade-signin.png`), on all six upgrades of the perf lane and the video. At `d4d78b2a4` the pick did nothing until a relaunch (`upgrade-relaunch-home.png`). That was the bug fixed in `bd327dedc`.
- Lane 3 pass. No in-app route reaches the auth screen while a connection exists, and a new local profile opens Add connection instead. Plezy's network was cut with the per-app firewall (the app could not resolve the Silo host), then Log out ran. The logout request failed (`lane-3.log`), the local wipe opened the auth screen with Connect to Silo as its only option (`auth-silo-only.png`), and the backup was restored before the network came back. The server session was never revoked: `Silo A` bound online on every later upgrade.
- Lane 4 pass. Settings > Add connection and `Silo A`'s detail screen both list Connect to Silo and Borrow from another profile only (`add-connection.png`, `add-connection-profile.png`). The unscoped screen is reachable only from the auth error banner and was not run.
- Lane 5 pass. Downloads shows "No downloads" with no error (`downloads-empty.png`). The Plex file stays on disk, 441,046,679 B (`lane-5-before.txt`, `lane-5-after.txt`), as the operator accepted.
- Lane 6 pass. `Silo A` is kept and the Plex Home profile is gone (`profiles-kept.png`). The temporary local profile "S7 Temp" made for lane 3 was removed by the next restore.
- Lane 7 skipped by the operator.
- Lane 8 pass. The migration line is in the first launch's log only. The second and third launches have none (`lane-8.log`, `migration-once.png`).
- Lane 9 pass. Lane 1's full logcat has no token, ticket, device code, signed URL or app-data path in Plezy's lines. The only `token=` and `/data/` hits are system processes (`lane-9.txt`, `migration-log.png`). The operator gave no Plex token prefix, so the search was by pattern.
- Lane 10 pass. `plezy_downloads.db` went from 876,544 B to 184,320 B, 692,224 B smaller, which is more than the old cache's 65,278 B. The WAL went from 4,120,032 B to 8,272 B (`storage.png`, `lane-10-before.txt`, `lane-10-after.txt`).
- Perf pass. Debug builds on both sides, because a profile build is not debuggable and the restores need `run-as`. Each of five cycles restored the backup, timed trunk's cold start, then installed head and timed its first launch. Time runs from `Start proc` to `Startup phase: phase=database_ready`, which comes after the migration and VACUUM; the howto's `image-cache` marker is logged in profile builds only. Trunk: 1,906, 1,938, 1,862, 1,815 and 1,844 ms (median 1,862). Head: 1,785, 1,743, 1,691, 1,757 and 1,721 ms (median 1,743), 119 ms faster, with the migration line in every head launch (`perf.txt`, `perf.png`, `perf-<n>.log`, `perf-T<n>.log`). The database was 876,544 B plus a 4,120,032 B WAL before every upgrade.
- Restores. After the lanes (`after-restore1-*.png`), before every perf cycle, two debugging cycles with a temporarily instrumented APK (not committed), the video, and finally at 07:56. Trunk `5fc148779` is installed, the profiles screen is pixel-identical to `before-profiles.png` (`after-profiles.png`), the home shows the same profile, hero and Continue Watching (`after-trunk-home.png`), and the Plex download is back. The backup was deleted (`rm -rf ~/plezy-s7/backup`). No server state changed: nothing signed into or out of Silo, and the Plex episode was never played.
- Open issue 1. The Settings > Profiles subtitle still reads "Add profiles to mix managed users and local identities", where managed users are Plex Home users. Left for S9, which replaces the profiles.
- Open issue 2. A profile with no connection shows "Unable to load Discover" on Home. This predates S7.
- Review gate. Stills are `media/s7-review-lane1-upgrade.png`, `-lane1-silo-home.png` and `-lane3-auth.png`. `media/s7-review.mp4` (40 s) shows the trunk Plex home, the upgrade, the picker with `Silo A` only, and the `Silo A` home.
- Verdict. Approved by the operator ("Go", 2026-10-21) at `face01086`, with lane 7 skipped and lanes 1 to 3 run on the current data by the operator's decisions above. Open issues 1 and 2 carry forward. Bugbot triage stays deferred to the end of the plan. Nothing is pushed.

## Delete Jellyfin and Emby (S8)
**Depends on.** S7.

**Files.**
- [x] Delete `lib/services/jellyfin_client.dart`, `lib/services/jellyfin_client/`, every `lib/services/jellyfin_*.dart`, every `lib/services/media_browser_*.dart`, `lib/media/media_browser_dialect.dart`, `lib/models/jellyfin/`.
- [x] Delete `lib/screens/settings/add_jellyfin_screen.dart`, `lib/screens/settings/edit_jellyfin_connection_screen.dart`, `lib/widgets/quick_connect_code_panel.dart`, `lib/screens/settings/quick_connect_flow_mixin.dart` unless Seerr still needs them.
- [x] Delete the matching tests under `test/`.
- [x] Edit the importers the analyzer lists. `plezy-backend-map.md` counts 25 for `jellyfin_api_cache.dart` and 23 for `jellyfin_client.dart`.

**Build.**
- [x] Remove `JellyfinConnection`, `MediaItem.jellyfin`, the `usesMediaBrowserApi` branches, `SeasonEpisodePagingClient` and `MediaDeletionPermissionClient` if Silo does not implement them.

**You see.**
- [x] The app behaves exactly as at S7.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [x] `grep -rli "jellyfin\|emby\|media_browser" lib test` returns only i18n sources and comments listed in S9. Run `flutter analyze && flutter test`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on the `swarm workers` role in `p3-models.md` at the PR head, per the boot recipe.
- [x] Lane 1. Regression lane against trunk. Run S3's lane 1 scenario at S7 and at head. Save `home.png`. Pass when both match.
- [x] Lane 2. Repeat S2 lane 2. Save `signin.png`. Pass as there.
- [x] Lane 3. Repeat S3 lane 2. Save `libraries.png`. Pass as there.
- [x] Lane 4. Repeat S3 lane 6. Save `detail.png`. Pass as there.
- [x] Lane 5. Repeat S3 lane 8. Save `search.png`. Pass as there.
- [x] Lane 6. Repeat S5 lane 1. Save `play.png`. Pass as there.
- [x] Lane 7. Repeat S5 lane 5. Save `subs.png`. Pass as there.
- [x] Lane 8. Repeat S6 lane 2. Save `offline.png`. Pass as there.
- [x] Lane 9. Repeat S4 lane 2. Save `dismiss.png`. Pass as there.
- [x] Lane 10. Repeat S2 lane 9. Save `signout.png`. Pass as there.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [x] Metric. Release APK size and cold start to first home row.
- [x] Probe. Build release APKs at S7 and head. Run ten cold starts each, interleaved.
- [x] Baseline. Record S7's size and median first.
- [x] Rule. Head is not larger, and its median is within 5 percent of S7's. Fail otherwise.

**Review gate.** None. S8 is not review-gated.

**S8 lane record, 2026-10-22, at `f0252a767` on `feat/silo-s8-drop-jellyfin`.** Lanes ran one at a time on the Android TV emulator `Television_1080p`, per `media/s8/lanes-howto.md`. Debug and release APKs were signed with the host debug key (SHA-256 `b4a70e96…1ee9`, the installed trunk's key). Evidence is in `media/s8/`, with the filtered log in `lanes.log`.
- Unit. `flutter analyze` clean. `flutter test --concurrency=1` gives `+7296 ~6: All tests passed!` (S7 had 8213; the difference is the deleted Jellyfin, Emby and MediaBrowser tests). The grep leaves only the migration and vault kind strings, the Seerr files and Quick Connect panel, the `x-emby-token` redaction, their tests, and the false positives `totalMemBytes` and `_deleteForItemByServer`.
- Backups. Trunk `5fc148779` was installed with the operator's Plex data. `trunk.tar` 617,499,648 B, sha256 `cdd226c7…db36787`. S7 debug then ran the v26 migration once and opened the `Silo A` home. `s7-state.tar` 613,526,528 B, sha256 `381a51a0…259daba`. Both are in `~/plezy-s8/backup` (mode 700).
- Lane 1 pass. S7 and head both log `Silo: home sections 18` and show the same home, Continue Watching first (`home-s7.png`, `home.png`; pixel diff 36 of 2,073,600 px, the clock).
- Lane 2 pass. Device code shown, approved by the operator, `device code approved` then `signed in`. The picker listed admin, Test and pintest. Admin was picked, and the relaunch opened the `Silo A` home with 18 sections (`silo-code.png`, `signin.png`).
- Lane 3 pass. All 9 libraries open with items (`libraries.png`).
- Lane 4 pass. Holiday Touchdown: A Bears Love Story, opened from Recently Added Movies. Title, year, synopsis and cast confirmed against the Silo app by the operator (`detail.png`).
- Lane 5 pass. "Top Gear" returns 40 results (4 movies, 6 shows, 30 episodes) with the series in them (`search.png`).
- Lane 6 pass. Holiday Touchdown started from its detail page, `original_http`, played to 276 s, stopped with status 200. The detail page shows Resume, and the operator read 4:35 in the Silo app (`play.png`).
- Lane 7 pass. English SRT rendered, then Off cleared it (`subs.png`, `subs-off.png`).
- Lane 8 pass. The first creates got HTTP 429 `rate_limited` from Silo for about 10 minutes. S8 changed no `lib/silo` code. The operator raised the server's download limit, then `Started Silo transfer 3782227688` for The New Prince of Tennis S5E4 and `Download completed` 69 s later. With the per-app firewall on (`set-package-networking-enabled false`, `set-chain3-enabled true`), the episode played from the TV Shows tab while host lookups failed (`offline.png`). The network was restored.
- Lane 9 pass. Holiday Touchdown removed from Continue Watching through Menu, `Silo events: user_state.changed (home_dismissal)`, and still gone after a force-stop and relaunch (`dismiss.png`, `dismiss-relaunch.png`).
- Lane 10 pass. Removed Silo from `Silo A`'s detail screen. `Silo: logout status 204`, then `Silo events: idle` and `closed`, and no ticket fetch after (`signout.png`). The server-side session list is for the operator to read in the Silo app.
- Perf pass. APK 176,602,610 B at S7, 175,813,898 B at head (−788,712 B). Ten interleaved release cold starts each, `Start proc` to `Home: first hub frame`: S7 median 2287.5 ms, head 2268.0 ms (−0.9%). All 20 opened the `Silo A` home, with no release crash (`perf.txt`, `results.tsv`, `perf.png`).
- No `Unknown MediaBackend` line from S7 or head. Trunk logs `ConnectionRegistry: failed to decode connection silo:…` after the final restore, as it always has.
- Server state changed. Holiday Touchdown position about 4:35 and its home dismissal. Silo download record 3782227688 for The New Prince of Tennis S5E4. The Silo session in `trunk.tar` and `s7-state.tar` is revoked, and a new one is in `~/plezy-s8/backup/s8-signed-in.tar` (613,407,232 B, sha256 `fd2dacb0…2892c09`). Plex now lists Holiday Touchdown first in trunk's Continue Watching, which the restored files cannot cause, so the Silo server likely forwarded lane 6's progress.
- Server state restored, 2026-10-22, with the operator's approval. Every item was opened from Search, never from Continue Watching, and cleared with ⋮ → Mark as Unwatched.
  - Holiday Touchdown on Plex. The RULEONE- copy showed Resume and now shows Play (`restore-plex-ht-resume.png`, `restore-plex-ht-unwatched.png`). The SmellyCats copy had a progress bar on its search poster and was cleared too (`restore-plex-ht-smellycats-unwatched.png`). The FamFlix copy already showed Play. After that it is no longer in trunk's Continue Watching.
  - Holiday Touchdown on Silo. Clearing it on Plex did not clear Silo: head debug with `s8-signed-in.tar` still showed Resume. Mark as Unwatched there logged `Silo events: user_state.changed (watched)` and the button now reads Play (`restore-silo-ht-resume.png`, `restore-silo-ht-unwatched.png`). Lane 9's home dismissal is left in place, so it stays off Silo's Continue Watching (`restore-silo-home.png`).
  - Plex item 306090 from the first restore attempt (below). Its logcat was lost, so it was not identified by key. Both candidates were checked instead. All 4 Plex copies of 1UP and all 8 of 2 Fast 2 Furious show Play with no progress, and so do the Silo copies of both (`restore-silo-1up.png`, `restore-silo-2f2f.png`). Nothing was changed.
  - The Traitors S5E6, first in trunk's Continue Watching, is the operator's own viewing and was left alone.
- First restore attempt, interrupted. Something else drove `emulator-5554` during it: key events nobody sent, and a Plex playback of item 306090 at about 08:57 device time that the Plex owner stopped after about 10 s. The attempt stopped without changing anything. The rerun had the emulator to itself, and no screen changed without its input. A host reboot between the two attempts cleared the first attempt's evidence from `/tmp`.
- End state. Trunk reinstalled and `trunk.tar` restored. Home, profiles and downloads match the before shots (`after-trunk-home.png`, `after-profiles.png`, `after-downloads.png`) apart from that Continue Watching entry. After the server-state restore, trunk was installed again (certificate `b4a70e96…1ee9` checked) and `trunk.tar` restored. The home matches `before-trunk-home.png` apart from The Traitors S5E6 at the front of Continue Watching (`restore-trunk-home-before.png`, `after-restore-trunk-home.png`). `trunk.tar` and `s8-signed-in.tar` are kept for S9, with their checksums unchanged.

**Merge.**
- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto S7 after the verdict, patch-id unchanged.
- [ ] Appended to the stack. The operator lands it bottom-up.

## Delete Plex and collapse the seams (S9)
**Depends on.** S8.

**Operator decisions (2026-10-22).** These amend the boxes below.
- The grep rule allowlists the files that must keep the old names to read or scrub old data: the schema migrations in `lib/database/app_database.dart`, the legacy key names in `lib/services/credential_vault.dart` and `lib/services/storage_service.dart`, the persisted backend ids in `lib/media/media_backend.dart`, the header and host patterns in `lib/utils/log_redaction_manager.dart`, their tests, and `test/database/schema_*`. Every other hit fails the rule.
- The v17 migration's call into `lib/database/plex_metadata_recovery.dart` is inlined into the migration, and the file is deleted.
- Schema 27 drops the rows keyed by Plezy profile ids: `download_owners`, `sync_rules`, `sync_rule_downloads`, `download_collections`, `download_collection_syncs`, and the profile-scoped Seerr and tracker preferences. They are not re-keyed to Silo profile ids. Silo downloads and their `silo:<server_id>/<profile_id>` scope rows stay, and so does the Silo connection.
- The companion remote secret is derived from the Silo server id and the Silo account id. The account id is persisted at sign-in from `GET /api/v2/account/me`.
- These Plex features go with no Silo replacement: account preferences, metadata edit, server activities, play queues, Plex Discover, and Quick Connect, once Seerr is checked for its use of the Quick Connect panel.
- Online subtitle search stays, rebuilt on Silo: `POST /api/v2/subtitles/search`, then `POST /api/v2/subtitles/download`, then the `subtitle_ready` row or a `subtitle_inventory_changed` replan (`research/silo-playback.md` lines 34 to 36 and 120). Silo sets the `externalSubtitleSearch` capability. The rebuild lands before `PlexClient` is deleted, and lane 11 checks it live.

**Files.**
- [ ] Delete `lib/services/plex_client.dart`, `lib/services/plex_client/`, every `lib/services/plex_*.dart`, `lib/models/plex/`, `lib/screens/plex_match_screen.dart`, `lib/screens/auth/plex_pin_auth_flow.dart`, `lib/screens/settings/add_plex_account_screen.dart`.
- [ ] Delete `lib/profiles/plex_home_*.dart`, `lib/profiles/active_plex_token.dart`, `lib/profiles/active_plex_identity.dart`, `lib/connection/connection_bootstrap.dart`, `lib/services/server_registry.dart`, `lib/services/play_queue_launcher.dart`, `lib/database/plex_metadata_recovery.dart`, `lib/utils/plex_cache_parser.dart`.
- [ ] Delete `lib/services/catalog/plex_catalog_source.dart` and `lib/services/plex_discover_client.dart`.
- [ ] Delete the live TV screens under `lib/screens/livetv/` and `lib/media/live_tv_support.dart`.
- [ ] Delete the matching tests.
- [ ] Edit `lib/profiles/active_profile_binder.dart`, `lib/services/multi_server_manager.dart`, `lib/profiles/profile.dart`, `lib/main.dart`, `lib/metadata_edit/`, `lib/widgets/library_management_sheet.dart`, `lib/widgets/server_activities_button.dart`, the Seerr auth service and the companion remote auth service.
- [ ] Edit the 22 i18n JSON sources and regenerate.
- [ ] Delete Plezy profiles: `lib/profiles/profile_registry.dart`, `profile_connection_registry.dart`, `profile_merge.dart`, `profile_selection_policy.dart`, `profile_connection_cleanup.dart`, and `lib/screens/profile/add_local_profile_screen.dart`, `borrow_connection_screen.dart`, `profile_detail_screen.dart`, `profile_name_field.dart`, `pin_status_row.dart`, `profile_teardown.dart`.
- [ ] Edit `lib/screens/profile/profile_switch_screen.dart`, `lib/profiles/profile_menu.dart`, `lib/profiles/active_profile_provider.dart` and `lib/screens/profile/silo_profile_screen.dart` so they list and switch Silo profiles.
- [ ] Edit `lib/database/app_database.dart` to schema 27. Create `test/database/schema_27_migration_test.dart` and `test/silo/silo_profile_switch_test.dart`.

**Build.**
- [ ] Silo profiles replace Plezy profiles. The operator decided this on 2026-10-13. The avatar and the profile switcher list `GET /api/v2/profiles` for the signed-in server. Switching selects the profile, asking for its PIN through `verify-pin` when it has one, and rebinds the client, so the session generation moves and in-flight reads drop. There is no Plezy-side profile, PIN, name, avatar or "Add Plezy profile".
- [ ] Schema 27 drops the `profiles` and `profile_connections` rows and keeps the Silo connection. The active Silo profile id lives in the Silo session in `CredentialVault`, as S2 stores it. A profile id the server no longer lists opens the picker.
- [ ] Remove `Profile.plexHome`, `PlexAccountConnection`, `MediaItem.plex` and `PlexHomeService`. The binder keeps only the join-row path. `MultiServerManager` drops relay and endpoint racing.
- [ ] Reduce `MediaBackend`, `Connection` and `MediaItem` to Silo. Remove capability flags Silo never sets, with their UI branches.
- [ ] Derive the companion remote secret from the Silo server id and account id.
- [ ] Remove Seerr sign-in through media-server credentials. Keep Seerr local login if Seerr offers one.

**You see.**
- [ ] The app behaves as at S8, and no screen mentions Plex, Jellyfin or Emby.
- [ ] The avatar opens the Silo profile picker. Picking a profile switches the home to its rows. No screen offers to add or edit a Plezy profile.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [ ] `grep -rliw "plex\|jellyfin\|emby" lib test` returns nothing outside the allowlist in the operator decisions above. Run `flutter analyze && flutter test`.
- [ ] `schema_27_migration_test.dart` migrates a seeded schema 26 database with two local profiles bound to one Silo connection, and asserts no profile rows remain and the connection survives.
- [ ] `silo_profile_switch_test.dart` asserts a switch to a PIN profile calls `verify-pin` and enters only on `valid: true`, and that a home read in flight across the switch is dropped.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on the `swarm workers` role in `p3-models.md` at the PR head, per the boot recipe.
- [ ] Lane 1. Regression lane against trunk. Run S3's lane 1 scenario at S8 and at head. Save `home.png`. Pass when both match.
- [ ] Lane 2. Repeat S2 lanes 2 and 7, then switch to another Silo profile from the avatar. Save `signin-pin.png` and `profile-switch.png`. Pass as there, and when the home shows the second profile's rows with no Plezy profile screen on the way.
- [ ] Lane 3. Walk every settings screen. Save `settings-<n>.png`. Pass when no Plex, Jellyfin or Emby text shows.
- [ ] Lane 4. Repeat S3 lane 7. Save `detail-show.png`. Pass as there.
- [ ] Lane 5. Repeat S5 lane 3. Save `transcode.png`. Pass as there.
- [ ] Lane 6. Repeat S5 lane 9. Save `next-episode.png`. Pass as there.
- [ ] Lane 7. Pair the companion remote. Save `companion.png`. Pass when pairing succeeds.
- [ ] Lane 8. Start Watch Together. Save `watch-together.png`. Pass when the room shows the profile name.
- [ ] Lane 9. Open the sidebar and every library. Save `sidebar.png`. Pass when no live TV entry shows and every library opens.
- [ ] Lane 10. Repeat S7 lane 1 from a trunk install. Save `upgrade.png`. Pass as there.
- [ ] Lane 11. Search online subtitles during playback, download one and select it. Save `subtitle-search.png`. Pass when the downloaded subtitle renders without restarting playback from the start.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.
- [ ] Metric. Release APK size and cold start to first home row.
- [ ] Probe. Build release APKs at S8 and head. Run ten cold starts each, interleaved.
- [ ] Baseline. Record S8's size and median first.
- [ ] Rule. Head is not larger, and its median is within 5 percent of S8's. Fail otherwise.
- [ ] Release budget, carried from S3. On a fresh release install signed in to Silo, ten cold starts to the first home row have a median under 2.5 s.

**Review gate.** The operator reviews before merge, because S9 replaces Plezy profiles with Silo profiles.
- [ ] Copy lane 2 screenshots into `docs/silo-migration/media/s9-review-*.png`.
- [ ] Record a 30 to 60 second video of sign-in, profile pick and a profile switch. Save it as `docs/silo-migration/media/s9-review.mp4`.
- [ ] Post the screenshots and the video in chat. Stop at merge-ready. Wait for the operator's click.

**S9 lane record, 2026-10-23, at `ae7a47871` on `feat/silo-s9-delete-plex`.** Lanes ran one at a time on the Android TV emulator `Television_1080p`, per `media/s9/lanes-howto.md`. S8 is the S8 branch's APKs in `~/plezy-s8/apk` (branch head now `41bad98e6`; the howto names `5fc13ef1a`). Every APK installed was checked against the installed app's certificate first, and all carry the host debug key (SHA-256 `b4a70e96…1ee9`). Evidence is in `media/s9/`. Logs stayed in `~/plezy-s9/lanes`.
- Found state. The S8 record left trunk installed with `trunk.tar` restored. The emulator instead held S9 `head-debug.apk` (byte-identical to `~/plezy-s9/apk/head-debug.apk`) on a near-empty first-run data set: a 180 KB database, no downloads, `firstInstallTime` equal to `lastUpdateTime`. The Silo habitat app, installed on 10-11, was still there, so the emulator was not wiped. The app was uninstalled and reinstalled, or its data cleared, by someone between the S8 run and this one. The AVD was last running at 17:09 today. Nothing of the operator's was lost on the host: both S8 backups match the S8 record (`trunk.tar` `cdd226c7…db36787`, `s8-signed-in.tar` `fd2dacb0…2892c09`). The found data was saved to `~/plezy-s9/backup/found-state.tar` (mode 600, folder 700) before anything changed.
- Backups. Trunk installed, `trunk.tar` restored, trunk launched. The home, Switch Profile and Downloads screens match S8's end state, apart from server-side artwork and a rating chip (`before-home.png`, `before-profiles.png`, `before-downloads.png`).
- Upgrade from S8. S8 debug with `s8-signed-in.tar`, then `install -r` head debug. The first launch logs `Removing Plezy profiles and the data they owned (v27 migration)`, then `ActiveProfileProvider: adopted the session profile of Silo` and `rebinding for admin (silo:…)`, and opens the admin home with no picker (`upgrade-s8.png`).
- Lane 1 pass. S8 and head both log `Silo: home sections 18` and show the same 18 rows in the same order, Continue Watching first: Continue Watching, Halloween Favorites, Recently Released Episodes, Recently Released Movies, Trakt Trending Shows, Trakt Trending Movies, Recommended For You, Trending on Server, Top Picks Today, My Favorites, My Watchlist, Shows Streaming on Apple TV, HBO, Prime, Peacock, Disney+ and Netflix, Latest PPV's (`home-s8.png`, `home.png`, `home-rows-s8.jpg`, `home-rows.jpg`). At each of the ten scroll positions the pixel diff is 322 to 370 of 2,073,600 px, all in the clock and in the avatar letter (S8's Plezy profile `Silo A` shows S; the head shows the Silo profile `admin`, A).
- Lane 3 pass, with one copy finding. Every settings screen was walked and its text read through `uiautomator dump`: the main list, General, Appearance, Video Playback, Manage Libraries, Services, Connect Seerr, Add connection, Switch Profile, the Watch Together Relay dialog and About (`settings-*.png`). No text names Plex, Jellyfin or Emby, and neither does `en.i18n.json`. Profiles reads `3 profiles · active: admin`. There is no Live TV, server activities, account preferences or Quick Connect entry. Add connection offers only Connect to Silo. Connect Seerr asks for the instance URL. Its next step was not reached, because that needs the operator's Seerr address, but `SeerrAuthMethod` has only `local` and the screen offers only email and password. Every tracker and Seerr reads Not connected, as the howto expects after the preference purge. The tracker rows were not opened, because each starts a sign-in flow. Finding: the Add connection row's subtitle still reads `Add to admin: a Silo server or another profile's connection` (`addConnectionSubtitleScoped`, `lib/i18n/en.i18n.json:868`, and the comment at `settings_screen.dart:339`). Borrowing a connection is gone in S9.
- Lane 9 pass. The sidebar shows admin, Search, Home, Downloads and the 9 libraries, with no Live TV or Explore entry (`sidebar.png`). All 9 libraries open with items (`libraries.jpg`).
- Lane 4 pass. Top Gear (2002), opened from Search as in S3, opens on Series 13 with S13E1 offered. The screen is pixel-identical to S3's `lane-7-detail-show.png` (`detail-show.png`). $#*! My Dad Says and Crystal Lake, one season each, list their episodes under Episodes with no season heading (`detail-show-one-season.png`). Shows with several seasons list one row per season, as in S3. The layout has no season tabs.
- Before lanes 5 and 6. Head state saved as `~/plezy-s9/backup/s9-pre-play.tar`. Restore targets were recorded first. Silo, head: Holiday Touchdown: A Bears Love Story shows Play (`restore-before-silo-ht.png`), and $#*! My Dad Says shows Play S1E1 with no marks (`restore-before-silo-mydadsays.png`). Plex, trunk with `trunk.tar`: the FamFlix, SmellyCats and RULEONE- copies of Holiday Touchdown are all `movie, unwatched` in their accessibility labels. The FamFlix, SmellyCats and RULEONE- copies of My Dad Says are all `TV show, unwatched`. Trunk's 17-card Continue Watching contains neither (`restore-before-plex-cw.jpg`).
- Lane 5 pass. Holiday Touchdown started from its detail page on `original_http`. Quality → 480p 1.5 Mbps in the player logs `replanned quality_change, delivery=server_transcode_hls`, and video renders at 1:42 (`transcode.png`). Back logs `stopped (status 200)` at 112 s, and the detail page shows Resume.
- Lane 6 pass. My Dad Says S1E2 from the detail page, seeked to 1199 s. At the end `Video completed: action=presentNext prompt` offers S1 E3 (`next-episode.png`). Play Next started E3. The player's queue lists S1E1 to S1E8 from the season, with no server play queue (`queue.png`). In E3, Previous restarted E3 at 0:31, then went to E2 when pressed again within 3 s, as `restartBeforePreviousItemThreshold` sets (`previous-e2.png`). Next went from E2 to E3 (`next-e3.png`). Each move logged one `stopped (status 200)` and one `started`. After Back, E2 carries the watched check (`next-episode-watched.png`).
- Lanes 5 and 6 restored on Silo. Holiday Touchdown: ⋮ → Mark as Unwatched logged `user_state.changed (watched)`, and the button reads Play again (`restore-after-silo-ht.png`). E2: card Menu → Mark as Unwatched logged `user_state.changed (watched)`, and the check went. E3's menu offers only Mark as Watched and its button reads Play S1E3, so it kept no position. The show reads Play S1E1 again (`restore-after-silo-mydadsays.png`). Silo's Continue Watching front is unchanged. The Plex copies are checked at the final restore.
- Lane 11 pass. 1UP (2022), from Search and its detail page, shows Play on Silo (`restore-before-silo-1up.png`). All four Plex copies are `movie, unwatched`. It has German PGS twice and English PGS, and no Spanish. Played to 1:05 and paused. Subtitles → Search Subtitles logs `Silo subtitles: search found 16 (0 warnings)` for English, then `found 6` for Spanish. Picked `1UP.2022.1080p.AMZN.WEB-DL.DDP5.1.H.264-CMRG`, opensubtitles, SRT. The log reads `Silo subtitles: stored a srt subtitle`, `replanned track_change, delivery=original_http`, then `Silo subtitles: replanned inventory has the stored row`. That is the `subtitle_inventory_changed` replan path. The player came back at 1:05, paused as it was, and played on from there with Spanish lines rendering (`subtitle-search.png`, `subtitle-search-310.png` at 3:10). The subtitle menu now lists `Spanish | 1UP.2022.1080p.AMZN.WEB-DL.DDP5.1.H.264-CMRG (opensubtitles) · SRT` (`subtitle-menu-after.png`). The downloaded subtitle stays on the server for the operator to remove if wanted. Stopped at 190 s with status 200. ⋮ → Mark as Unwatched logged `user_state.changed (watched)`, and 1UP reads Play again (`restore-silo-1up-resume.png`, `restore-after-silo-1up.png`).
- Finding while setting up lane 11. ⋮ → File Info on 1UP shows `Error loading file info: an unexpected error occurred`. `SiloClient` does not implement `getFileInfo`, so its `noSuchMethod` returns an `UnsupportedError`. The menu entry still shows for Silo items. S8's `SiloClient` has the same `noSuchMethod`, so this is not new in S9.
- Lane 7 not run. It needs a second device signed in to the same Silo account, and there was none. The operator chose to skip it. No `CompanionRemote` line appeared in any lane's log, because the host was never started.
- Lane 8 pass. Home → Watch Together → Create Session → Anyone. The room lists `Participants (1) | admin | Host`, the Silo profile's name (`watch-together.png`, room code masked). End Session → End closed the room on the relay, and the screen returned to Create Session. The app keeps the code under Recent Rooms locally.
- Perf state. After lanes 5 to 11 and their restores, with head debug installed and the admin profile active: `~/plezy-s9/backup/s9-signed-in.tar`, 605,867,520 B, sha256 `9d28c50d…07acb41`, mode 600. It holds the same live Silo session as `s8-signed-in.tar`, at schema 27.
- Lane 2 pass, with one howto gap. The session was alive, so no device code was needed and no new session was made. The avatar opens a sheet listing the other profiles (Test, pintest with a lock), then Profiles, Settings and Log out (`picker-sheet.png`). Profiles opens Switch Profile: admin (Active), Test and pintest with their Silo initials and colours, `Silo` as the server on each tile, and Add connection. There is no Add profile or Manage screen (`picker.png`). Each tile's ⋮ (labelled Manage for accessibility) holds one entry, Sign out (`tile-menu.png`). Picking pintest opens the PIN dialog (`signin-pin.png`). The operator meant to enter a wrong PIN first but entered the right one: `ActiveProfileProvider: activated pintest`, `rebinding for pintest`, and its own home with 15 sections and no Continue Watching (`after-right-pin.png`). From the avatar sheet, Test (no PIN) switched straight to its home with no Plezy profile screen on the way: `activated Test`, 16 sections, its own Continue Watching, and 4 libraries (`profile-switch.png`). Then pintest again from Test, and the operator entered a wrong PIN. The dialog stays open with its boxes cleared and reads `Incorrect PIN. Please try again.`, and no profile change is logged (`signin-pin-wrong.png`). Back closed it. Switching back to admin logged `activated admin` and 18 sections, and a cold relaunch opens the admin home with no picker (`relaunch-admin.png`). Gap: the howto asks for a `verify-pin` line in logcat, but `SiloProfiles.enter` logs nothing, so the wrong and right PIN show only through the dialog and the activation lines. Which profile the Silo app shows for this device is for the operator to read. The session's selected profile is admin again, as before the lane.
- Plex copies restored, on trunk with `trunk.tar`. After lane 6, trunk's Continue Watching had gained $#*! My Dad Says S1E3 (`restore-plex-cw-after-lanes.png` is local only). Silo had forwarded E2's watched mark to Plex, but not the later Mark as Unwatched, so E3 was On Deck. The FamFlix copy had E2 checked, with no position on E3 (`restore-plex-famflix-mds-before.jpg`). Its card Menu → Mark as Unwatched cleared it. The SmellyCats copy had the same check, and clearing it also cleared RULEONE-'s count, so the two share watch state (`restore-plex-smellycats-mds-after.jpg`). Search now shows the three copies' unwatched badges as 17, 18 and 18, as before the lanes (`restore-plex-mds-after.jpg`). Holiday Touchdown's three copies and 1UP's four copies show no progress bar and read `movie, unwatched`, so neither the 112 s nor the 190 s position reached Plex. Continue Watching again runs The Traitors, Game of Thrones, Mortimer & Whitehouse as before (`restore-plex-cw-after-restore.jpg`). Its new first card, Slow Horses S6E2, was not played by any lane, so it is the operator's own viewing and was left alone. Finding for Silo, not Plezy: Silo forwards watched to Plex but not unwatched.
- Lane 10 pass, with one copy finding. Trunk with `trunk.tar` matched `before-home.png`, apart from server-side Continue Watching. `install -r` head debug, then launch. Logcat reads `Removing Plex, Jellyfin and Emby data (v26 migration)`, then `Removing Plezy profiles and the data they owned (v27 migration)`, in that order. Then `adopted the session profile of Silo`, `household read failed (SiloCredentialsRepudiatedException)` and `Added Silo server: Silo (authError)`. The home shows `Session expired for Silo` with Sign in again, and no Plex data (`upgrade-session-expired.jpg`). Sign in again opens Add connection → Connect to Silo with the address empty, so the address was typed again (`silo.ruleone.xyz`). The operator approved the device code: `Silo: signed in`, then `profile picker listed 3 profiles`. The picker shows admin, Test and pintest with its lock, and no Plezy-era name (`upgrade-picker.jpg`). admin opened its home with 18 sections (`upgrade.png`). After a cold relaunch the app opens the admin home with no picker (`upgrade-relaunch.jpg`). Finding: Sign in again does not carry over the expired connection's address.
- Emulator crash. During lane 10's relaunch the emulator's `qemu-system-x86_64` died on SIGSEGV (01:05:19, core dump of 975 MB kept by `systemd-coredump`). adb lost the device mid-command. It was restarted with its own flags (`-no-audio -no-boot-anim -no-snapshot-load`), and the app, its data and the head install were intact. The relaunch check above ran after the restart.
- Sessions. Lane 2 made no new session. Lane 10 made one on the device state that grew from `trunk.tar`. That state was overwritten by the final restore and is in no backup, so the new session is orphaned on the server and can be revoked there. `trunk.tar` still holds the revoked session. `s8-signed-in.tar` and `s9-signed-in.tar` hold the same live one.
- Perf, release builds. APK size from `flutter build apk --release --target-platform android-x64` before re-signing: head 171,781,851 B against S8 175,813,898 B, pass. Signed sizes are 171,830,566 B and 175,865,217 B. Cold start from `Start proc` (`logcat -v epoch`) to `Home: first hub frame, rows 1`, both present on every run of both release builds. S8: S8 debug, `s8-signed-in.tar`, one launch on the Silo A home, then `install -r` S8 release. Runs, ms: 2096, 2090, 2279, 2072, 2167, 2088, 2088, 2125, 2117, 2105, median 2100.5. Head: head debug, `s9-signed-in.tar`, one launch on the admin home, then `install -r` head release. Runs, ms: 2073, 2104, 2130, 2084, 2069, 2138, 2171, 2080, 2154, 2080, median 2094.0. The head median is 0.3 percent under S8's, pass. It is under the 2.5 s release budget, pass. Deviation: ten of S8, then ten of the head, not interleaved, because S8 cannot open the head's schema 27 database, so every switch needs a debug install and a restore. Each block started from its own restore and reinstall.
- 100 Humans, at S8 debug before the perf runs. It lists its episodes (`perf/s8-100humans.png`, local only). At head the episode row went missing on 100 Humans, and on My Dad Says on a second visit, and came back after a relaunch, so one good visit at S8 does not show whether the miss is new.
- Review gate. `s9-review-picker.png`, `s9-review-signin-pin.png` and `s9-review-profile-switch.png` are copies of lane 2's shots. `s9-review.mp4` is 42.8 s, cut from three lane 2 recordings: Switch Profile, the avatar sheet, the pintest PIN dialog, pintest's home, and the switch to Test. A 1 fps sheet of the copied file shows the PIN boxes empty in every frame and the pad with focus on 1 only. The cut goes from the empty dialog to the home. Gap: the video has no sign-in, because lane 2 needed none. Lane 10's sign-in was not recorded, because its screen shows the device code.
- Final restore. Trunk (certificate checked), `trunk.tar` restored before any launch, trunk launched. Home, Switch Profile (NotVeryPrivateAccount active, Silo A with No connections) and Downloads (Taskmaster, 1/1 completed) match `before-home.png`, `before-profiles.png` and `before-downloads.png`, apart from server-side Continue Watching. `trunk.tar` is still `cdd226c7…db36787` and `s8-signed-in.tar` is still `fd2dacb0…2892c09`. `~/plezy-s9/backup/s9-signed-in.tar` (`9d28c50d…07acb41`) and `found-state.tar` are kept for the operator to decide on. `s9-pre-play.tar` was deleted after the Silo restores, to save disk.
- Server state left changed. Lane 11's Spanish subtitle `1UP.2022.1080p.AMZN.WEB-DL.DDP5.1.H.264-CMRG` (opensubtitles, SRT) on Silo's 1UP. Lane 10's new Silo session. The Watch Together room is closed. Positions and watched marks from lanes 5, 6 and 11 are cleared on Silo and on the Plex copies.

**After the review gate, 2026-10-24.** The operator answered the gate's open issues: the Plex forwarding gap does not matter (Silo's own watched state was checked and is right), the Sign in again address and lane 7 stay as they are, and 100 Humans is theirs to check. They asked for three changes, each tested and checked live on the emulator with head debug builds and `s9-signed-in.tar`.
- `37012a560`, Add connection subtitle. The tile always reads `Connect to a Silo server`. The scoped variant and its "another profile's connection" wording are gone, because the screen behind the tile is not scoped to a profile. `flutter analyze` clean. `test/i18n` (8) and `test/screens/settings` (101) pass, and `silo_only_copy_test.dart` now also rejects "another profile".
- `a8844a3ba`, version choice on Play and Silo File Info. The catalog item detail's `versions[]` is decoded (a malformed row is dropped, not fatal) into `MediaItem.mediaVersions`. Play on a detail page, its first-episode play and episode cards ask which file to play when there are two or more, and play straight away with one. Continue Watching cards on the home still play directly. A pick is started with `allow_alternate_versions: false`. If the server refuses it, the start is retried with the server choosing, and the player names the version it plays. File Info reads the same versions with their streams. Silo's version `bitrate` is in kbps: the 1080p Fast Five remux reads 25,500. `flutter analyze` clean. `test/silo`, `test/i18n` and `test/screens/settings` (382) and `test/screens/video_player` with `test/services` (2,100) pass, with new cases for the version mapping, file info, the requested file id and the pinned start. Live, Fast Five lists `Extended Cut · 1080p H.264 MKV (25.5 Mbps)` and two `Extended · HDR · 4K HEVC MKV` files (31.5 and 53.3 Mbps). The 1080p plays as picked (`version=0 effective=0`). A 4K HDR pick is refused by the test server (`no_alternate_version`, "A lower-resolution source is required because 4K transcoding is disabled", since Plezy declares no HDR), falls back to the 1080p and shows `That version can't play here, so Extended Cut · 1080p H.264 MKV (25.5 Mbps) is playing`. Holiday Touchdown: A Bears Love Story, one file, plays with no picker. File Info shows resolution, codec and profile, audio channels, path, size, duration and file id. The two test plays were cleared with Mark as Unwatched (`user_state.changed (watched)`, both read Play). Silo now remembers the 1080p as Fast Five's last file, which is the file it picks unpinned anyway.
- `e1e95e5ab`, Back on a dialog left the screen behind it. Logs from a debug build showed one press doing two pops: the dialog's DismissAction pops it on KeyDown, and Android TV delivers the same press's platform back just before its KeyUp, which `ProfileSessionScreen` forwarded to the nested navigator, now topped by the detail page. The forwarder now drops a platform back while `BackKeyUpSuppressor` is armed by that press. The instrumentation was removed before the commit. `flutter analyze` clean. `test/focus`, `test/navigation`, `test/widgets` and `test/screens` (1,758) pass. The new `profile_session_screen_test.dart` case replays the order (Escape down closes a dialog, platform back, Escape up) and fails with the guard removed. Live, Back on the Play picker and on the Play Version... picker closes only the picker, and a second Back leaves the page.
- Final restore, again. The host rebooted after the restore at 02:22, and the emulator shut down cleanly with it. Restarted with its flags, it held trunk (255,513,587 B, debug key) and the full `trunk.tar` file set (app_flutter 25, files 9, shared_prefs 5, databases 0, no_backup 3). The restore was redone: `install -r` trunk, `trunk.tar`, launch. Home (apart from the operator's Slow Horses card), Switch Profile and Downloads match the before shots. `trunk.tar` `cdd226c7…db36787`, `s8-signed-in.tar` `fd2dacb0…2892c09` and `s9-signed-in.tar` `9d28c50d…07acb41` are unchanged.
- Release check at `6b8e6df1a`, for the code added after the perf lane. `flutter build apk --release --target-platform android-x64`: 171,986,163 B before re-signing, still under S8's 175,813,898 B. Signed with the debug key as `~/plezy-s9/apk/post-gate-release.apk`, installed over head debug with `s9-signed-in.tar`. Ten cold starts, ms: 2230, 2145, 2167, 2091, 2071, 2117, 2096, 2169, 2105, 2118, median 2117.5, 0.8 percent over S8's 2100.5 and under 2.5 s. These runs followed a host reboot and an emulator cold boot, not the original perf session. Under R8, Fast Five's Play lists its three files, Back closes only the list, the 1080p pick plays and stops with status 200, and File Info reads `Version 1 of 3` with resolution, codecs, size and file name. The play was cleared with Mark as Unwatched (`user_state.changed (watched)`, Play again). Trunk and `trunk.tar` were restored afterwards, with all five folders complete and the home matching.
- Stack state. `main` (`65b4c2d3e`, the same on `origin`) through `feat/silo-s9-delete-plex` is one chain, each stage an ancestor of the next. S9 already sits on S8's head `41bad98e6`, so the rebase is a no-op. No stage branch is on `origin` and no PR exists yet.

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
- **Keep Plezy profiles beside Silo profiles.** Two profile layers made the user pick a Plezy profile and then a Silo profile. The operator chose Silo profiles only on 2026-10-13. They land in S9, because until then Plex Home users are Plezy profiles and the Plex regression lanes need them.
- **Map Silo items into the Plex or Jellyfin `MediaItem` variant.** Saved caches would then decode Silo data as another backend. A `silo` variant keeps stored rows honest.

## Appendix C. Risks
- **Data loss on upgrade (S7).** Users lose their Plex and Jellyfin connections, downloads and queued offline progress. This is intended, but it is irreversible on their devices. The S7 review gate is where the operator confirms it.
- **Playback contract fit (S5).** Silo's v3 contract is shaped around Media3. An mpv client that declares only `declared` evidence may get worse plans. The owner watches S5 lanes 2 and 3 for the delivery chosen.
- **Token refresh mid-stream (S5).** Without the proxy, long plays stall. The owner watches S5 lane 7.
- **Profile binder rewrite (S2, S9).** A mistake strands users on the splash or leaks one profile's servers into another. The owner watches S2 lane 8 and S9 lane 2.
- **Plezy profiles removed (S9).** Upgraded users lose Plezy profile names, PINs and avatars. Their Silo sign-in survives and the Silo picker takes over. The S9 review gate is where the operator confirms it.
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
