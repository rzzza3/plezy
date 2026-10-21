# S8 live lanes, how to run them

This file is for whoever runs the S8 **Verify, live** and **Verify, perf** blocks of `docs/silo-migration/plan.md`. No lane has run yet. S7 is `6a1d88684` on `feat/silo-s7-silo-only`. The head is the commit that adds this file on `feat/silo-s8-drop-jellyfin`.

**Read "Back up first" and "Signing" before you install anything.** The emulator holds trunk `5fc148779` with the operator's restored Plex data. The first launch of an S7 or S8 build runs the schema 26 migration and deletes that Plex data. Only a backup taken through `run-as` brings it back, and an uninstall would lose it for good. The operator forbids uninstalling.

## What changes from S7

S8 deletes the Jellyfin and Emby code and nothing else. There is no new schema, preference or screen. The lanes look for S7 behaviour on the head. Watch for:

- `Unknown MediaBackend id "<id>"; dropping the row`. The head logs it if a stored row still names `jellyfin` or `emby`. After the S7 migration none should be left, so it should not appear.
- The catalog match fallback title now reads Silo for a Silo match, where S7 read Plex. It shows only when a match has no title.
- The Add connection, Settings and sign-in screens are unchanged. There was never a Jellyfin button left after S7.

## Ground rules

- These are the S7 howto's ground rules (`media/s7/lanes-howto.md`). Keys are `adb shell input keyevent <n>`: Up 19, Down 20, Left 21, Right 22, Select 23, Back 4, Menu 82. Take a screenshot before every Select. Never press Select on a Continue Watching card.
- Never uninstall. Never `pm clear`. Install only with `adb install -r`, and only after the certificate check under "Signing".
- Build in the repo checkout or a worktree under `~/`, never in `/tmp`. Keep the APKs in `~/plezy-s8/apk/`:
  - `s7-debug.apk` and `head-debug.apk`, from `flutter build apk --debug --target-platform android-x64`.
  - `s7-release.apk` and `head-release.apk`, from `flutter build apk --release --target-platform android-x64`, re-signed as under "Signing".
  - Trunk stays at `~/plezy-s7/apk/trunk.apk`.
- Keep `adb logcat -s flutter` running into `/tmp/swarm-feat-silo-s8-drop-jellyfin/lane-<n>/logcat.txt`, and save screenshots beside it.
- The backups hold every credential the app has. Treat them like a password file. They never go into the repo, `/tmp`, a chat message or a log.

## Signing

Every build must be signed with the key of the installed app, or `install -r` fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`. The only way past that error is an uninstall, which deletes the data. So check the certificate before every install.

- The installed trunk, and the S7 debug APKs, are signed with the host's debug key, `~/.android/debug.keystore` (`CN=Android Debug`, SHA-256 `b4a70e966d64a9a2bb99c7562e5448738555c4eae474ed9548021a6a5e7e1ee9`). Debug builds from this host use the same key.
- A release build signs with the release key only when `android/key.properties` exists. It does not exist on this host, so `flutter build apk --release` gives no signing config of its own. Never create a `key.properties` for these lanes. A release-key APK cannot be installed over the debug-key trunk.
- Re-sign each release APK with the debug key. `apksigner` needs Java, which is not on the `PATH`. Use the JDK in `~/.jdks/jbr-21.0.11`:

  ```
  export JAVA_HOME=$HOME/.jdks/jbr-21.0.11 PATH=$HOME/.jdks/jbr-21.0.11/bin:$PATH
  BT=$HOME/Android/Sdk/build-tools/36.1.0
  $BT/zipalign -f -p 4 build/app/outputs/flutter-apk/app-release.apk ~/plezy-s8/apk/head-release-aligned.apk
  $BT/apksigner sign --ks ~/.android/debug.keystore --ks-pass pass:android --ks-key-alias androiddebugkey \
    --out ~/plezy-s8/apk/head-release.apk ~/plezy-s8/apk/head-release-aligned.apk
  ```

  The debug keystore's password is the public Android default, not a secret.
- Before each install, compare the digest with the installed app. The two lines must be equal:

  ```
  $BT/apksigner verify --print-certs ~/plezy-s8/apk/<apk> | grep SHA-256
  adb shell dumpsys package com.edde746.plezy | grep -A1 signatures
  ```

  `dumpsys` prints a short hash, not the SHA-256. If the format is hard to compare, pull the installed APK with `adb shell pm path com.edde746.plezy` and `adb pull`, and run `apksigner verify --print-certs` on it. If they differ, stop and ask the operator.
- All APKs carry `applicationId` `com.edde746.plezy` and version code 152, so `install -r` works between debug and release with no `-d`. The data stays.

## Back up first

A release build is not debuggable, so `run-as` fails while it is installed. Take every backup and do every restore while a debug build is installed (trunk, S7 debug or head debug), then `install -r` the release build over it.

Two backups are needed:

1. **`trunk.tar`, the operator's Plex data.** Trunk debug is installed now. Follow the S7 howto's "Back up before the first head install" with `~/plezy-s8/backup` (mode 700) in place of `~/plezy-s7/backup`. Take `app_flutter`, `files`, `shared_prefs`, `databases` and `no_backup`, as S7 did. Record the size and `sha256sum` in the lane notes. Screenshot `before-trunk-home.png`, `before-profiles.png` and `downloads-before-trunk.png`.
2. **`s7-state.tar`, the migrated Silo state.** `install -r ~/plezy-s8/apk/s7-debug.apk`, launch it, and pick `Silo A` in the startup picker. Wait for the Silo home, then force-stop and relaunch once. The relaunch must go straight to the `Silo A` home with no picker. Force-stop, then take the same tar into `~/plezy-s8/backup/s7-state.tar`. It is the starting state for the perf lane and for any lane that needs a clean start.

The restore is the S7 howto's "Restore", with the tar named for the state you want and the matching debug APK installed first: trunk for `trunk.tar`, S7 debug or head debug for `s7-state.tar`. Remove the old folders before unpacking.

## Order

S8 has no schema step, so S7 and the head read the same data. Run S7 first and then install the head over it with `install -r`.

1. Backups, as above.
2. Lane 1 at S7 (debug). Read only.
3. `install -r head-debug.apk`. Lanes 1, 3, 4, 5 and 7 at head. Read only.
4. Lanes 8, 6 and 9 at head. They change local or server state.
5. Lanes 10 and 2 at head, last. They change the Silo session (see "Silo sessions").
6. Perf lane, release builds.
7. Final restore of `trunk.tar`.

Only lane 1 compares S7 and the head. The other lanes repeat an older lane at the head and pass as that lane did.

## Lanes

**Lane 1. Home, S7 against head (S3 lane 1).** Read only.
1. At S7, open the `Silo A` home. Save `home-s7.png` and note the `Silo: home sections <n>` line.
2. At head, the same. Save `home.png`.
3. Pass when both show the same rows in the same order, matching `research/samples/home-sections.json`, with the same section count in logcat. Continue Watching is first, as backdrop cards.

**Lane 2. Sign in (S2 lane 2).** Changes server state: a new Silo session for this device. Needs the operator to approve a device code. Run it right after lane 10.
1. From the screen lane 10 leaves, add Silo: Connect to Silo, `https://silo.ruleone.xyz`, device code.
2. Save `silo-code.png` while the code shows, then `signin.png` when the profile picker opens.
3. Pass when the log reads `device code approved` then `signed in`, and the picker lists the server's profiles. Pick admin, so `Silo A` is back on the same Silo profile.

**Lane 3. Libraries (S3 lane 2).** Read only.
1. Open each library from the sidebar. Save `library-<n>.png`, and a contact sheet as `libraries.png`.
2. Pass when every library shows items. S3 had 9 libraries.

**Lane 4. Movie detail (S3 lane 6).** Read only.
1. Open a movie from a library, not from Continue Watching. Save `detail.png`.
2. Pass when title, year, synopsis and cast match the Silo app. Ask the operator to confirm against the Silo app, as in S3.

**Lane 5. Search (S3 lane 8).** Read only.
1. Search "Top Gear". Save `search.png`.
2. Pass when the series is in the results. S3 had 40 results.

**Lane 6. Play a movie (S5 lane 1).** Changes server state: the movie's saved position.
1. Pick a movie nobody is partway through, and start it from its detail page, never from Continue Watching. Note its server position first.
2. Let it play for a minute. Save `play.png` while video renders. Back out.
3. Pass when video renders, the detail page shows Resume, and the Silo app shows the new position. This movie is the target of lane 9.

**Lane 7. Subtitles (S5 lane 5).** Read only. The subtitle choice is a local preference.
1. Play an item with an embedded subtitle track at Original. S5 used an English SRT. Turn subtitles on, save `subs.png`, then turn them off and save `subs-off.png`.
2. Pass when the subtitles render and then clear.

**Lane 8. Offline play (S6 lane 2).** Changes local state, and S6 logs a server transfer (`Started Silo transfer`).
1. `s7-state.tar` has no Silo download. S7's lane 5 showed "No downloads". Make one first, as in S6 lane 1: download a short movie or episode at head and wait for `Download completed`. S6's 441 MB episode took 12 minutes.
2. Cut the app's network with the per-app firewall, as in S7 lane 3. Do not use airplane mode, which also cuts adb on some images.
3. Play the download. Save `offline.png` while video renders.
4. Pass when video renders with the network cut. Restore the network. Leave the download; the final restore removes it.

**Lane 9. Dismiss from Continue Watching (S4 lane 2).** Changes server state: a home dismissal.
1. Use lane 6's movie, so no real Continue Watching entry is lost. Move focus onto its card without Select, then Menu (keyevent 82) and Remove from Continue Watching.
2. Save `dismiss.png`. Force-stop, relaunch, and save `dismiss-relaunch.png`.
3. Pass when the card goes, logcat shows the `home_dismissal` echo, and the card is still gone after the relaunch.

**Lane 10. Sign out (S2 lane 9).** Changes server state: revokes this device's Silo session.
1. Do it as in S4: the profile sheet's Log out signs out every account, so remove Silo from `Silo A` instead, in the profile's detail screen.
2. Save `signout.png`. Note `Silo: logout status 204` in logcat.
3. Pass when the logout returns 204, the Silo socket closes with no ticket fetch after it, and the Silo app lists no session for this device. Then run lane 2.

## Silo sessions

Lane 10 revokes the Silo session that `trunk.tar` and `s7-state.tar` hold. After it, restoring either tar gives `Silo A` a dead token. Trunk cannot use Silo, so trunk's Plex home is not affected. But the perf lane, and the next stage's upgrade from trunk, would start without a working Silo session.

Ask the operator before lane 10:

- **Recommended.** Run lanes 10 and 2 last, as ordered above. After lane 2 the head holds a new session. Take one more backup then, with head debug installed: `~/plezy-s8/backup/s8-signed-in.tar`. Use it for the perf lane in place of `s7-state.tar`. At the end, restore `trunk.tar` as the operator's state, and record that its Silo session is revoked. The next upgrade needs one code approval.
- **Without revoking.** Cut the app's network before Log out, as in S7 lane 3. The local wipe runs and the session stays valid. This does not meet S2 lane 9's "the server lists no session" rule, so record lane 10 as partial.

## Perf lane

**Metric.** Two numbers: the release APK size, and the cold start to the first home row.

**APK size.** From `flutter build apk --release --target-platform android-x64`, before re-signing. On this host:

| Build | Commit | `app-release.apk` |
|---|---|---|
| S7 | `6a1d88684` | 176,602,610 B |
| Head | `5fc13ef1a` | 175,813,898 B (−788,712 B) |

**Cold start.** Release builds log at info level, so `appLogger.i` lines reach `adb logcat -s flutter`. The `Startup phase <name>` lines are profile-only, but these two are logged in release:

- Start: the `ActivityManager` line `Start proc <pid>:com.edde746.plezy/...`, with `adb logcat -v epoch` running from before the launch.
- End: `Home: first hub frame, rows <n>`, from `discover_screen.dart`. It is logged after the first frame that shows home rows, once per launch. `Startup phase: phase=database_ready` from `AndroidExitDiagnostics` is a second marker for reference.
- Check the first launch of each build: both lines must appear. If the end line does not appear in release, stop and report it. Do not switch markers between builds.

**State.** Both builds start from the same migrated Silo state, so neither run includes the migration.
1. With head debug installed, restore `s8-signed-in.tar`, or `s7-state.tar` if lane 10 did not run. Launch once and wait for the `Silo A` home with no picker, then force-stop.
2. `install -r` each release APK after the certificate check. The data stays across the swap.

**Probe.** Ten cold starts of each build, interleaved: S7, head, S7, head, and so on.
1. `adb install -r ~/plezy-s8/apk/<build>-release.apk`.
2. `adb shell am force-stop com.edde746.plezy`, wait 5 s.
3. `adb shell am start -W -n com.edde746.plezy/.MainActivity`. Record `end - start` from logcat, and `TotalTime` for reference.
4. Screenshot the home. It must be the `Silo A` home, not the picker. Save `perf-<build>-<n>.log`.

The swap between builds is part of each step, so the page cache is cold for the new APK in every cycle. Do not press any key during a timed launch.

**Baseline.** S7's APK size and its median cold start. Record them first.

**Rule.** The head's APK is not larger than S7's, and the head's median is within 5 percent of S7's. Fail otherwise.

**After.** With a debug build installed, restore `trunk.tar`.

## Restores at the end

- Install trunk (`install -r ~/plezy-s7/apk/trunk.apk`, after the certificate check), restore `trunk.tar`, launch trunk, and match `before-trunk-home.png`, `before-profiles.png` and `downloads-before-trunk.png`.
- If the operator wants S9 to start from the signed-in S8 state, keep `s8-signed-in.tar` and say so in the record. Otherwise delete `~/plezy-s8/backup` and record that it was deleted.
- Record the server state the lanes changed: lane 6's position, lane 9's dismissal, lane 8's transfer, and the session lanes 10 and 2 replaced.

## What the lanes must watch for

- An install that fails on the signature. Stop, do not uninstall, and ask the operator.
- `run-as` while a release build is installed fails with `package not debuggable`. Install a debug build first.
- The release build runs R8, and no release build was installed in S2 to S7. A crash on a reflective or JNI path at S7 release is not an S8 regression, but it blocks the perf lane. Record it and ask the operator.
- A startup picker on a timed launch means `active_app_profile_id` did not stick. Fix the state with a debug build and restart the probe.
- A Silo download made in lane 8 stays in the data until the final restore. It is in the perf state only if the backup was taken after lane 8. Note which.
