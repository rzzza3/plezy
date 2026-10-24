# S7 live lanes, how to run them

This file is for whoever runs the S7 **Verify, live** and **Verify, perf** blocks of `docs/silo-migration/plan.md`. No lane has run yet. The code head is `bed4e1d5b` on `feat/silo-s7-silo-only`. Run the lanes at the commit that adds this file, which differs from the code head only by this file.

**Read "Back up before the first head install" before you install anything.** The first launch of an S7 build on the emulator deletes its Plex, Jellyfin and Emby data. There is no undo inside the app, and from S7 on the app cannot sign into Plex.

## What the head does on upgrade

- **Schema 26.** On the first open after the upgrade, `AppDatabase` deletes, in one migration transaction:
  - every `connections` row whose kind is not `silo`, and the `profile_connections` rows that point at them
  - `profiles` rows of kind `plex_home`
  - every `downloaded_media` row that is neither in a `silo:` scope nor from a server with a Silo connection, with their `download_owners` and `download_queue` rows
  - `sync_rules`, `sync_rule_downloads`, `download_collections` and `download_collection_syncs` for non-Silo servers
  - queued `offline_watch_progress` for non-Silo servers
  - every `api_cache` row outside a `silo:` scope
  - `music_sessions` that hold any Plex, Jellyfin or Emby item

  It keeps local profiles and every Silo row: the `silo:<server_id>` connection, the profile's join row, Silo downloads in `silo:<server_id>/<profile_id>` scopes, and their cache rows. It then runs `VACUUM` once outside the transaction, so the file shrinks.
- **Files are not deleted.** Removed downloads keep their files under `app_flutter/downloads/`. The delete path needs the download manager's storage and SAF services, which do not exist while the database migrates. Lane 5 and lane 10 must take this into account (see there).
- **Preferences.** On the first setup run, `StorageService.clearLegacyBackendPrefsOnce` removes `plex_token`, `current_user_uuid`, `servers_list`, `server_order`, `home_users_cache*`, the unscoped library keys, and every `server_endpoint_*`, `plex_home_users_*`, `library_filters_*`, `library_sort_*`, `library_grouping_*` and `library_tab_*` key. It then sets `legacy_backend_prefs_cleared_v1`. It keeps `active_app_profile_id`, `profile_last_used_*`, `client_identifier`, the Silo session and device id, and every `user_<scope>_` key.
- **UI.** The sign-in screen has one button, Connect to Silo. Settings > Add connection lists Silo, plus Borrow from another profile when it is opened for a profile. After the migration only Silo connections exist to borrow.

## Logcat lines to watch

- `Removing Plex, Jellyfin and Emby data (v26 migration)`. It appears once, on the first launch after the upgrade. Lane 8 depends on it never appearing again.
- `Could not reclaim space after the v26 migration`. VACUUM failed, usually from low disk space. The data is already purged, but the file keeps its size. Note it, since lane 10 would then fail.
- `Unknown MediaBackend id "<id>"; dropping the row`. A stored row named a backend this build does not know. It should not appear.
- Neither the migration nor the preference clear logs a token, path, title or key value. Lane 9 checks that.

## Ground rules

- Follow the plan's boot recipe. Build with `flutter build apk --debug --target-platform android-x64` and install with `adb install -r`. Never uninstall. Clear data only where a lane below says so, and only after the backup exists.
- Keys are `adb shell input keyevent <n>`. Up 19, Down 20, Left 21, Right 22, Select 23, Back 4. Take a screenshot before every Select.
- Never press Select on a Continue Watching card.
- Keep `adb logcat -s flutter` running into `/tmp/swarm-feat-silo-s7-silo-only/lane-<n>/logcat.txt`, and save screenshots beside it.
- Build trunk and head in the repo checkout or a worktree, never in `/tmp`. Keep both APKs: copy each to `~/plezy-s7/apk/trunk.apk` and `~/plezy-s7/apk/head.apk` after building. Every restore below reinstalls trunk.

## Back up before the first head install

The emulator's app data today holds the RULEONE Plex account (the trunk side of every regression lane through S6), the Plezy profiles `Silo A` and `Silo B` with their Silo binding, and possibly Jellyfin or Emby connections. S8 and S9 still need a Plex-signed-in trunk for their regression lanes. The head deletes all of it except the local profiles and the Silo rows, and it can no longer sign into Plex. Signing Plex in again needs a trunk build and the operator's Plex PIN link. So copy the app data off the emulator first.

`adb backup` is not used. It is deprecated, and it skips apps that opt out. Copy the data directory with `run-as` instead. That works only for a debuggable build, which the boot recipe's debug APK is.

The copy holds every credential the app has: the credential-vault key in the preferences file and the encrypted tokens in the database. Treat it like a password file. It never goes into the repo, `/tmp`, a chat message or a log.

1. Install trunk (`feat/tv-silo-sidebar`, `5fc148779`) with `adb install -r ~/plezy-s7/apk/trunk.apk` if it is not already installed. Open it once and confirm the Plex profile reaches the Plex home. Then stop it:
   `adb shell am force-stop com.edde746.plezy`
2. Check the size and the host's free space:
   `adb shell run-as com.edde746.plezy du -sh .`
   `adb shell run-as com.edde746.plezy ls -la`
   The folders that matter are `app_flutter` (database and downloads), `files` (the preferences DataStore) and `shared_prefs`. Note any others.
3. Make a private folder on the host and copy:
   `mkdir -p ~/plezy-s7/backup && chmod 700 ~/plezy-s7/backup`
   `adb exec-out run-as com.edde746.plezy tar -cf - app_flutter files shared_prefs > ~/plezy-s7/backup/app-data.tar`
   Add any other folder from step 2 except `cache`, `code_cache` and `lib`.
4. Check the copy:
   `tar -tf ~/plezy-s7/backup/app-data.tar | grep -E 'plezy_downloads.db$|preferences_pb$|FlutterSharedPreferences.xml$'`
   It must list `app_flutter/plezy_downloads.db` and the preferences file. Compare `ls -l` against the size from step 2. Record `sha256sum` of the tar in the lane notes, not the tar itself.
5. Screenshot the trunk home as `before-trunk-home.png` and the profile picker as `before-profiles.png`. These are the restore targets.

### Restore

Use this after lane 1, after each perf upgrade, and at the end of the run.

1. `adb install -r ~/plezy-s7/apk/trunk.apk`. Both builds carry version code 152, so `-r` is enough. If install refuses a downgrade, add `-d`.
2. `adb shell am force-stop com.edde746.plezy`
3. Remove the head's data first, so no newer database file or WAL is left beside the restored one, then unpack:
   `adb exec-in run-as com.edde746.plezy sh -c 'rm -rf app_flutter files shared_prefs && tar -xf -' < ~/plezy-s7/backup/app-data.tar`
   Name the same folders the backup took.
4. Check: `adb shell run-as com.edde746.plezy ls -la app_flutter`. `plezy_downloads.db` must be there, with no `-wal` or `-shm` newer than the backup.
5. Launch trunk. Pass when it matches `before-trunk-home.png` and `before-profiles.png`.

At the end of the run, restore once more, confirm, and delete the copy: `rm -rf ~/plezy-s7/backup`. Say in the lane record that it was deleted.

If `exec-in` is missing from the host's `adb`, use `adb shell "run-as com.edde746.plezy sh -c 'rm -rf app_flutter files shared_prefs && tar -xf -'" < ~/plezy-s7/backup/app-data.tar`. Do not stage the tar in `/data/local/tmp` or `/sdcard`, where other apps and the shell user can read it.

## Starting state for lane 1

Lane 1 passes when the head "opens to the Silo sign-in". That only happens when the upgraded data has no Silo connection. The emulator's data has one, from S2 to S6. Trunk has no Silo backend and ignores those rows, but leaves them in place. The head keeps them, so on this data it opens to the profile picker or the `Silo A` home, not to the sign-in.

Ask the operator which they want before lane 1:

- **As written.** After the backup, clear the app's data (`adb shell pm clear com.edde746.plezy`), open trunk, and sign into Plex with the operator's PIN link. Then fill the cache by browsing a few libraries and download one short Plex item for lane 5. Back that state up as a second copy, `~/plezy-s7/backup/plex-only.tar`, for the perf lane. The head then opens to the Silo sign-in.
- **On the current data.** Upgrade over the backup as it is. Pass when the head opens to the profile picker or the `Silo A` home with no error, no Plex profile and no Plex server. Lane 7 still checks the sign-in on a fresh install.

## Lanes

**Lane 1. Upgrade from trunk.** Destroys the Plex data. The backup must exist.
1. Trunk is installed in the agreed starting state. Screenshot its home as `trunk-home.png`.
2. `adb install -r ~/plezy-s7/apk/head.apk`, then launch.
3. Save `upgrade.png`. Pass when it opens as agreed above, logcat shows the migration line once, and there is no error banner.

**Lane 2. Sign into Silo after the upgrade.** Changes server state: one Silo sign-in session on the Silo server.
1. From the sign-in, Select Connect to Silo, enter `https://silo.ruleone.xyz`, and sign in by device code with the operator's approval, as in S2.
2. Pick the Silo profile admin. Save `upgrade-signin.png` when the home rows load.
3. Pass when the home loads. If lane 1 ran on the current data, sign-in is already done. Record the `Silo A` home instead.

**Lane 3. The auth screen.** Read only.
1. Reach the sign-in screen: on the current data, use Settings > sign out of the Silo connection only if the operator agrees, or use the lane 7 fresh install.
2. Save `auth-silo-only.png`. Pass when the only button is Connect to Silo, with no Plex, QR, browser, Jellyfin, Emby or debug-token option.

**Lane 4. Settings > Add connection.** Read only.
1. Open Settings, then Add connection, both from the global entry and from a profile's detail screen.
2. Save `add-connection.png`. Pass when only Connect to Silo shows, plus Borrow from another profile on the profile-scoped picker.

**Lane 5. Downloads after the upgrade.** Read only.
1. Before lane 1, the trunk data needs one completed Plex download. List it with `adb shell run-as com.edde746.plezy find app_flutter/downloads -type f` into `lane-5-before.txt`.
2. After the upgrade, open Downloads. Save `downloads-empty.png`.
3. Pass when the Plex download is gone from the list and the screen shows no error. List the files again into `lane-5-after.txt`. The Plex file is still there (see "Files are not deleted"). Record the bytes left behind.

**Lane 6. Local profiles after the upgrade.** Read only.
1. Open the profile picker. Save `profiles-kept.png`.
2. Pass when every local profile from `before-profiles.png` is there (`Silo A`, `Silo B`, any others) and the Plex Home profiles are not.

**Lane 7. Fresh install.** Needs a cleared app. Do it after the final restore copy is safe, or on a second emulator.
1. `adb shell pm clear com.edde746.plezy`, then launch head.
2. Save `fresh.png`. Pass when it opens to the Silo sign-in.
3. Restore afterwards.

**Lane 8. The migration runs once.** Read only.
1. After lane 1, force-stop and relaunch twice.
2. Save `migration-once.png` (the logcat window) and `lane-8.log`.
3. Pass when `Removing Plex, Jellyfin and Emby data (v26 migration)` appears only in the first launch's log.

**Lane 9. Logcat after the upgrade.** Read only.
1. Take lane 1's full `adb logcat` (not just `-s flutter`) from install to home.
2. Search it for the Plex token prefix and the Silo origin's tokens. The operator can name the first characters of the Plex token without revealing it. Also search for `plezy_downloads.db`, `/data/`, `app_flutter` and `X-Plex-Token`.
3. Save `migration-log.png`. Pass when nothing matches.

**Lane 10. Storage before and after.** Read only.
1. Before lane 1, with trunk stopped: `adb shell run-as com.edde746.plezy du -k app_flutter/plezy_downloads.db app_flutter/downloads .` into `lane-10-before.txt`. Also record the cache size: `adb shell run-as com.edde746.plezy sqlite3 app_flutter/plezy_downloads.db "SELECT sum(length(data)) FROM api_cache"` if `sqlite3` exists on the image. Otherwise pull a copy of the database into `~/plezy-s7/backup/` and run the query on the host.
2. After lane 1, stopped, the same `du` into `lane-10-after.txt`. Save `storage.png`.
3. Pass when the database file shrank by at least the old cache size. Judge the database file, not the whole folder: the removed downloads' files stay (see "Files are not deleted"), so the folder total only shrinks by the cache.

## Perf lane

**Metric.** Time from process start to the first frame of the first real screen after the upgrade. The startup splash draws before the database opens, so Android's `Displayed` line and `am start -W` stop too early to include the migration. Use the logcat markers below.

**Build.** Use the same build type on both sides. `flutter build apk --profile --target-platform android-x64` logs `Startup phase <name>: <n>ms (total <n>ms)` lines, which give the gate's end. Check that the profile APK allows `run-as` (`adb shell run-as com.edde746.plezy id`) before relying on it for restores. If it does not, use debug APKs for both sides and say so in the record.

**Timing.** For each launch, with `adb logcat -v epoch` running from before the launch:
- Start: the `ActivityManager` line `Start proc <pid>:com.edde746.plezy/...`.
- End: the `Startup phase image-cache` line, which comes after the database is open, migrated and vacuumed. Check with a screenshot that the next screen is the expected one.
- Record `end - start` in ms. Also record `am start -W`'s `TotalTime` for reference.

**Baseline first.** Trunk's cold start on the restored data: restore, `adb shell am force-stop com.edde746.plezy`, launch, record. Do this five times. The median is the baseline.

**Probe.** Five upgrades. Each one:
1. Restore the backup (the `plex-only.tar` copy if lane 1 ran "as written"), so the cache is full and the database is at schema 25.
2. Launch trunk once and wait for the home, so the restored state is what trunk sees on a normal start. Force-stop.
3. `adb install -r ~/plezy-s7/apk/head.apk`. Then launch and time it as above. Confirm the migration line appears in that launch.
4. Save `perf-<n>.log`.

Interleave baselines and upgrades if time allows (trunk, upgrade, trunk, upgrade, and so on), since the emulator's disk cache warms over a run.

**Rule.** Head's median first post-upgrade launch is at most 2 s above trunk's median cold start. Fail otherwise. VACUUM rewrites the whole database file, so a large cache costs time here. Record the database file size before each upgrade beside the timing.

## Restores at the end

- Restore the backup, launch trunk, and match `before-trunk-home.png` and `before-profiles.png`.
- If lane 2 signed into Silo, the Silo server has one more session for this device. Sign out from Plezy's settings before restoring, or leave it. It holds no data.
- Delete `~/plezy-s7/backup` and record that it was deleted.

## What the lanes must watch for

- Lane 1's pass condition depends on the starting state (see "Starting state for lane 1").
- The migration does not delete downloaded files. A device with large Plex downloads keeps those bytes after the upgrade with no way to see or delete them in the app. This is the main open question for the review gate.
- If VACUUM fails for lack of space, the purge still happened. The device needs about the database's size free for VACUUM.
- `active_app_profile_id` may still name a Plex Home profile after the upgrade. The boot guard clears it when no profile resolves. Watch for a blank screen instead of the picker in lane 1.
