# S9 live lanes, how to run them

This file is for whoever runs the S9 **Verify, live**, **Verify, perf** and **Review gate** blocks of `docs/silo-migration/plan.md`. S8 is `5fc13ef1a` on `feat/silo-s8-drop-jellyfin`. The head is the tip of `feat/silo-s9-delete-plex`. The lanes have not run yet.

**Read "Back up first", "Signing" and "Schema 27" before you install anything.** The emulator holds the operator's state. The first launch of the head runs the schema 27 migration, which deletes the Plezy profile rows for good. Only a backup taken through `run-as` brings them back. The operator forbids uninstalling.

## What changes from S8

- **Silo profiles replace Plezy profiles.** The picker lists the signed-in server's `GET /api/v2/profiles`. A PIN profile asks for its PIN, and the server checks it with `verify-pin`. There is no Add profile, Manage, Delete or "Borrow connection" any more. The tile menu has one entry, Sign out, which signs out of that profile's server. The picker's bottom button is Add connection.
- **First launch after the upgrade.** The stored active profile id is a Plezy id such as `local-…`. The head drops it and adopts the profile the Silo session already selected. Expect `ActiveProfileProvider: adopted the session profile of <server>` in logcat, and the home with no picker. If the session names no profile, the picker opens.
- **Schema 27** deletes the `profiles` and `profile_connections` rows, every `download_owners` row, sync rules, download collections and music session snapshots. Silo downloads and their `silo:<server_id>/<profile_id>` scope stay. Each one is claimed back by the profile of its own scope when that profile becomes active. Queued offline watch actions keep their scope as their owner. Expect `Removing Plezy profiles and the data they owned (v27 migration)`.
- **Preferences.** Once, at the first setup after the upgrade, every `user_<id>_*` and `profile_last_used_<id>` key outside a `silo:` scope goes. That includes each Plezy profile's Seerr and tracker sessions, so Trakt, Simkl, MAL, AniList, MDBList and Seerr need signing in again.
- **Companion remote.** The shared secret is now derived from the Silo server id and the Silo account id. Two devices pair when they are signed in to the same Silo server with the same account. The account id is read from `/api/v2/account/me` at sign-in, and filled in by the first household read on an upgraded install. Until then the remote is off, with `CompanionRemote: Skipping <server> — its account id is not known yet` in logcat.
- **Removed with no replacement.** Plex, live TV and DVR, Plex Discover, Plex play queues (local queues are back for shuffle, collections and playlists), match and metadata edit, server activities, account preferences, library scan, folder play, Explore provider hubs, delete-from-server, and Seerr sign-in through Plex, Jellyfin, Emby or Quick Connect. Seerr local sign-in stays.
- **Subtitle search** runs on Silo: `POST /api/v2/subtitles/search`, then `POST /api/v2/subtitles/download`, then the `subtitle_ready` row or a `subtitle_inventory_changed` replan. Lane 11 checks it.

## Ground rules

These are the S8 howto's ground rules (`media/s8/lanes-howto.md`), with S9 paths:

- Keys are `adb shell input keyevent <n>`: Up 19, Down 20, Left 21, Right 22, Select 23, Back 4, Menu 82. Take a screenshot before every Select. Never press Select on a Continue Watching card.
- Never uninstall. Never `pm clear`. Install only with `adb install -r`, and only after the certificate check under "Signing".
- Build in the repo checkout or a worktree under `~/`, never in `/tmp`. The APKs are in `~/plezy-s9/apk/`:
  - `head-debug.apk`, from `flutter build apk --debug --target-platform android-x64`.
  - `head-release.apk`, from `flutter build apk --release --target-platform android-x64`, re-signed as under "Signing".
  - S8's APKs stay at `~/plezy-s8/apk/` (`head-debug.apk` and `head-release.apk` there are S8). Trunk stays at `~/plezy-s7/apk/trunk.apk`.
- Keep `adb logcat -s flutter` running into `~/plezy-s9/lanes/lane-<n>/logcat.txt`, and save screenshots beside it. Copy only screenshots into `docs/silo-migration/media/s9/`, never a log: logs can hold server addresses and session ids.
- The backups hold every credential the app has. Treat them like a password file. They never go into the repo, `/tmp`, a chat message or a log.

## Signing

Unchanged from S8. Every build must carry the installed app's key, or `install -r` fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`, and the only way past that is an uninstall.

- Debug builds from this host sign with `~/.android/debug.keystore` (`CN=Android Debug`, SHA-256 `b4a70e966d64a9a2bb99c7562e5448738555c4eae474ed9548021a6a5e7e1ee9`). So does every installed build so far.
- `android/key.properties` does not exist on this host. Never create one for these lanes. Re-sign each release APK with the debug key:

  ```
  export JAVA_HOME=$HOME/.jdks/jbr-21.0.11 PATH=$HOME/.jdks/jbr-21.0.11/bin:$PATH
  BT=$HOME/Android/Sdk/build-tools/36.1.0
  $BT/zipalign -f -p 4 build/app/outputs/flutter-apk/app-release.apk ~/plezy-s9/apk/head-release-aligned.apk
  $BT/apksigner sign --ks ~/.android/debug.keystore --ks-pass pass:android --ks-key-alias androiddebugkey \
    --out ~/plezy-s9/apk/head-release.apk ~/plezy-s9/apk/head-release-aligned.apk
  ```

  The debug keystore's password is the public Android default, not a secret.
- Before each install, compare the digests. The two must match:

  ```
  $BT/apksigner verify --print-certs ~/plezy-s9/apk/<apk> | grep SHA-256
  adb shell dumpsys package com.edde746.plezy | grep -A1 signatures
  ```

  If the `dumpsys` short hash is hard to compare, pull the installed APK (`adb shell pm path com.edde746.plezy`, `adb pull`) and run `apksigner verify --print-certs` on it. If they differ, stop and ask the operator.
- Every APK carries `applicationId` `com.edde746.plezy` and version code 152, so `install -r` works between debug and release with no `-d`.

## Back up first

`run-as` works only while a debug build is installed. Take every backup and do every restore with a debug build installed, then `install -r` a release build over it if a lane needs one.

S8 left two backups in `~/plezy-s8/backup` (mode 700). Both must stay as they are:

- `trunk.tar`: trunk `5fc148779` with the operator's Plex data. Its Silo session was revoked in S8 lane 10.
- `s8-signed-in.tar`: S8 head, signed in to Silo, schema 26, with the Plezy profile `Silo A` bound to the Silo `admin` profile.

Before the first head install:

1. `sha256sum ~/plezy-s8/backup/*.tar` and compare with the S8 lane record in `plan.md`. If either differs, stop.
2. Note which state is on the emulator now. The S8 record ends with trunk installed and `trunk.tar` restored.
3. Screenshot `before-home.png`, `before-profiles.png` and `before-downloads.png`.

Create `~/plezy-s9/backup` (mode 700) for any S9 state you save. Do not write into `~/plezy-s8/backup`.

The restore is the S7 howto's "Restore", with the tar for the state you want and its matching debug build installed first: trunk for `trunk.tar`, S8 debug (`~/plezy-s8/apk/head-debug.apk`) for `s8-signed-in.tar`. Remove the old folders before unpacking.

## Schema 27

- The head migrates a schema 26 database to 27 on first launch. There is no way back in place. **S8 cannot open the head's database**: drift sees version 27, newer than S8's 26, and the S8 build would run with tables it does not expect. To go back to S8, install S8 debug and restore `s8-signed-in.tar`. Never install S8 over a head-migrated state without that restore.
- The S8 start state (`s8-signed-in.tar`) goes 26 → 27. The trunk start state (`trunk.tar`, lane 10) goes 25 → 26 → 27 in one launch: the S7 purge, then the S9 one.
- After the migration, the `ActiveProfileProvider` adoption (see "What changes") must leave you on the home of the session's Silo profile. A picker on that first launch means the session named no profile. That is a pass only if the Silo app shows no selected profile for this device either. Otherwise it is a finding.

## Order

1. Backups, as above.
2. With S8 debug installed and `s8-signed-in.tar` restored, run lane 1 at S8. Read only.
3. `install -r head-debug.apk` (certificate check first). Launch once. Check the schema 27 and adoption lines. Save `upgrade-s8.png`.
4. Lanes 1, 3, 4 and 9 at head. Read only.
5. Lanes 5, 6, 11, 7 and 8 at head. They change server state (playback positions, a downloaded subtitle) or pair devices.
6. Take `~/plezy-s9/backup/s9-signed-in.tar` with head debug installed. It is the perf lane's state.
7. Lane 2 at head. It switches and re-enters profiles, and may need a device code.
8. Lane 10 from trunk, last of the functional lanes, because it starts from `trunk.tar`.
9. Perf lane, release builds.
10. Review gate.
11. Final restore.

## Lanes

**Lane 1. Home, S8 against head (S3 lane 1).** Read only.
1. At S8, open the `Silo A` home. Save `home-s8.png` and note the `Silo: home sections <n>` line.
2. At head, after the upgrade launch, the same. Save `home.png`.
3. Pass when both show the same rows in the same order, with the same section count in logcat. Continue Watching is first.

**Lane 2. Sign in with a PIN profile, then switch (S2 lanes 2 and 7).** Changes server state: a new session if sign-in runs, and the session's selected profile.
1. From the avatar, open the picker. Save `picker.png`. Pass when it lists the server's profiles with their Silo names and avatars, the server name on each tile, and no Add profile or Manage entry.
2. Pick a PIN profile. Enter a wrong PIN first: the dialog must say the PIN is wrong and stay open. Then the right PIN (ask the operator). Save `signin-pin.png` while the dialog shows. Logcat must show `verify-pin` for that profile, and the home must switch to that profile's rows.
3. From the avatar, switch to a second profile without a PIN. Save `profile-switch.png`. Pass when the home shows the second profile's rows, with no Plezy profile screen on the way, and the Silo app shows the device on that profile.
4. If the session is gone (a dead token), sign in again as in S2 lane 2: Add connection, Silo, `https://silo.ruleone.xyz`, device code, approved by the operator.

**Lane 3. Settings (new).** Read only.
1. Walk every settings screen and sub-screen. Save `settings-<n>.png`.
2. Pass when no screen shows Plex, Jellyfin or Emby. The Profiles entry must not say "managed users". There is no Live TV, server activities, account preferences or Quick Connect entry. Seerr offers only local sign-in.

**Lane 4. Show detail (S3 lane 7).** Read only.
1. Open a show from a library. Save `detail-show.png`.
2. Pass as S3 lane 7. A show with one season lists its episodes directly. A show with several shows season tabs.

**Lane 5. Transcode (S5 lane 3).** Changes server state: the item's position.
1. Play an item that needs a transcode, as in S5 lane 3. Save `transcode.png`.
2. Pass as there.

**Lane 6. Next episode (S5 lane 9).** Changes server state: positions and watched state.
1. Play an episode near its end and let it roll to the next. Save `next-episode.png`.
2. Pass as there. The queue is now local (no Plex play queue), so also check that Previous and Next in the player move by one episode.

**Lane 7. Companion remote (new).** No server change.
1. On a second device or a second emulator signed in to the same Silo server with the same account, open Companion remote. On the emulator, start the host.
2. Save `companion.png` when paired. Pass when pairing succeeds and a command (pause) works. A device signed in with another account must not see the host.
3. If pairing does not start, check logcat for `its account id is not known yet`. An upgraded install fills the account id on its first household read. Reopen the picker once to force a read, and record that you did.

**Lane 8. Watch Together (new).** Changes server state: a room on the relay.
1. Start a Watch Together room. Save `watch-together.png`.
2. Pass when the room shows the Silo profile's name.

**Lane 9. Sidebar and libraries (S3 lane 2).** Read only.
1. Open the sidebar and each library. Save `sidebar.png` and `library-<n>.png`.
2. Pass when no Live TV entry shows and every library opens with items.

**Lane 10. Upgrade from trunk (S7 lane 1).** Changes local state. Needs a device code, because `trunk.tar`'s Silo session was revoked in S8.
1. With trunk installed, restore `trunk.tar`. Launch trunk and match `before-home.png` from the S8 record, so you know the start state.
2. `install -r head-debug.apk` (certificate check). Launch.
3. Logcat must show the v26 purge, then the v27 migration, in that order. The Plex data is gone, as in S7.
4. The Silo connection is still there but its token is dead, so expect the sign-in path. Sign in with a device code. Save `upgrade.png` at the Silo home.
5. Pass as S7 lane 1, and the picker lists Silo profiles only.

**Lane 11. Online subtitle search (new).** Changes server state: a downloaded subtitle on the item.
1. Play a movie with no subtitle in the wanted language. Let it play for 30 s and note the position.
2. Open the subtitle menu, choose Search, pick a language, and download a result. Save `subtitle-search.png` while the downloaded subtitle renders.
3. Logcat must show the search and download calls, then either the `subtitle_ready` row or a `subtitle_inventory_changed` replan.
4. Pass when the subtitle renders and playback continues from about the noted position, not from the start.
5. Record the movie and subtitle, so the operator can remove it on the server if wanted.

## Silo sessions

Lane 2 may sign in again and lane 10 must, so the session the start states hold changes during the run. After lane 10, `trunk.tar`'s Silo session is still the revoked one. The head's new session is in `s9-signed-in.tar` only if you took that backup after the sign-in. Note which session each backup holds.

## Perf lane

**Metric.** Release APK size and cold start to the first home row, as S8.

**APK size.** From `flutter build apk --release --target-platform android-x64`, before re-signing:

| Build | Commit | `app-release.apk` |
|---|---|---|
| S8 | `5fc13ef1a` | 175,813,898 B |
| Head | see the S9 report | see the S9 report |

**Cold start.** Same markers as S8. Start: the `ActivityManager` `Start proc <pid>:com.edde746.plezy/...` line from `adb logcat -v epoch`. End: `Home: first hub frame, rows <n>`. Both must appear on the first launch of each build. If the end line does not appear in release, stop and report it.

**State.** S8 and the head cannot share one database: the head migrates it to 27, and S8 cannot read 27. So each build gets its own start state, restored with a debug build of the same version:
- S8: S8 debug installed, `s8-signed-in.tar` restored, one launch to the home, force-stop, then `install -r ~/plezy-s8/apk/head-release.apk`.
- Head: head debug installed, `s9-signed-in.tar` restored, one launch to the home, force-stop, then `install -r ~/plezy-s9/apk/head-release.apk`.

Switching builds means a restore each time, so do not interleave. Run ten cold starts of S8, then ten of the head. Before each run: `adb shell am force-stop com.edde746.plezy`, wait 5 s, then `adb shell am start -W -n com.edde746.plezy/.MainActivity`. Drop the page cache between builds by restoring and reinstalling, as above. Record this deviation from the plan's "interleaved", and why.

**Rule.** The head's APK is not larger than S8's, and its median is within 5 percent of S8's. Fail otherwise.

**Release budget, carried from S3.** On the head release build signed in to Silo, the median of the ten cold starts is under 2.5 s. Fail above that.

## Review gate

1. Copy lane 2's `picker.png`, `signin-pin.png` and `profile-switch.png` into `docs/silo-migration/media/s9-review-<name>.png`.
2. Record 30 to 60 s of sign-in, a profile pick with a PIN and a profile switch: `adb shell screenrecord --time-limit 60 /sdcard/s9-review.mp4`, then `adb pull`. Save it as `docs/silo-migration/media/s9-review.mp4`. Check the video shows no PIN digits. The PIN field is masked, but the on-screen number pad shows each press, so record the PIN entry with the pad off-screen or cut that part.
3. Post the screenshots and the video in chat. Stop at merge-ready and wait for the operator.

## Restores at the end

- Install trunk (certificate check), restore `trunk.tar`, launch, and match `before-home.png`, `before-profiles.png` and `before-downloads.png`.
- Keep `~/plezy-s8/backup/trunk.tar` and `s8-signed-in.tar` untouched, and check their `sha256sum` against the S8 record once more. Keep `~/plezy-s9/backup/s9-signed-in.tar` only if the operator wants it for the next stage. Otherwise delete it and record that.
- Record the server state the lanes changed: positions from lanes 5 and 6, lane 11's subtitle, the Watch Together room, and any session lanes 2 and 10 replaced.

## What the lanes must watch for

- An install that fails on the signature. Stop, do not uninstall, and ask the operator.
- S8 installed over a head-migrated database (see "Schema 27"). If it happens, restore `s8-signed-in.tar` with S8 debug before doing anything else.
- A Plezy-era profile name (for example `Silo A`) anywhere after the upgrade. Every profile name now comes from the server.
- A picker on every launch. It means `active_app_profile_id` did not stick or the household no longer lists the profile. Check logcat for `the active profile left <server>`.
- Downloads missing after the upgrade. They come back for the profile whose scope made them, once that profile is active. A download made by another Silo profile shows only under that profile.
- The release build runs R8. A crash on a reflective or JNI path blocks the perf lane. Record it and ask the operator.
