# S6 live lanes, how to run them

This file is for whoever runs the S6 **Verify, live** and **Verify, perf** blocks of `docs/silo-migration/plan.md`. It covers setup, the key sequence for each lane, what a pass looks like, and which lanes change server state and how to restore them. No lane has run yet. The code head is `287b0459c` on `feat/silo-s6-downloads`. Run the lanes at the commit that adds this file, which differs from the code head only by this file.

## How a Silo download works at this head

Read this first, because several lanes depend on it.

- **Create.** Queueing a download calls `SiloClient.resolveDownload`. It reads `GET /api/v2/capabilities/downloads` and stops if the profile may not download. It reads `/api/v2/watch/{id}` for the file, then lists `GET /api/v2/downloads` and reuses a usable entry for that file. Only when there is none does it send one `POST /api/v2/downloads`, which is never replayed. An episode is registered under its series, with the episode as `episode_id`.
- **Transfer.** The bytes do not go through the native downloader. Plezy streams `GET /api/v2/downloads/{id}/file` in Dart with the session's bearer and profile headers, so no credential is written into a native task. Bytes land in `<file>.part`. The response's strong ETag (else `Last-Modified`) lands in `<file>.part.silo`, which holds the download id, revision and validator, never a token. The transfer only runs while Plezy's process is alive. A killed app re-queues the row on the next launch and resumes.
- **Resume.** A later attempt at the same download id and revision sends `Range: bytes=N-` and `If-Range: <validator>`. A matching 206 appends. A 200 starts over. A 416 drops the partial and starts from zero in the same attempt.
- **Status.** Plezy sends `PATCH /api/v2/downloads/{id}` with `downloading` when bytes start and `completed` when the file is whole, at the entry's revision. A failed report is logged and does not fail the download.
- **Subtitles.** Once the server holds the download as completed, the next resolve reads `GET /api/v2/downloads/{id}/manifest` and saves each mountable sidecar (srt, vtt, ass, ssa, pgs, ttml) next to the video with the session's headers.
- **Offline progress.** A downloaded file plays with no server session. When playback stops, the position goes to `POST /api/v1/sync/progress` with `force_overwrite: true` and the time it was observed. Offline, the position is queued and sent the same way when the server is back. No `/api/v2/playback/*` call is made for a downloaded file.
- **Scope.** Each row's `clientScopeId` is `silo:<server_id>/<profile_id>`. Only the client bound to that Silo profile can run, show or resume it.

## Logcat lines to watch

These carry no token, URL query, title or session id. A download's global key is `<server_id>:<content_id>`.

- `Started Silo transfer <task id> for <key>` when a transfer starts.
- `Silo downloads: resuming at byte <n>` on a resume. Lane 3 depends on it.
- `Silo downloads: partial rejected with 416, restarting from zero` when the server refuses the range.
- `Silo downloads: downloading report failed (<code>)` or `completed report failed (<code>)` when a PATCH fails. Note any of these.
- `Silo downloads: manifest unavailable (HTTP <n>)` when there is no manifest.
- `Download failed for <key> (attempt <k>/3), scheduling auto-retry in 30s` after an interrupted transfer.

## Ground rules

- Follow the plan's boot recipe. Build with `flutter build apk --debug --target-platform android-x64`, install with `adb install -r`. Never uninstall, never clear data.
- Keys are `adb shell input keyevent <n>`. Up 19, Down 20, Left 21, Right 22, Select 23, Back 4.
- Take `adb exec-out screencap -p` and read where focus is before every Select. Counts of Downs drift.
- Never press Select on a Continue Watching card. Open every item from Libraries, then its detail page.
- Keep `adb logcat -s flutter` running into `/tmp/swarm-feat-silo-s6-downloads/lane-<n>/logcat.txt`, and save screenshots beside it.
- Before the first download of an item, screenshot its detail page as `before-<id>.png`. That is the restore target for its watched mark and progress.
- Network off and on, for lanes 2, 3, 5 and 10: `adb shell cmd connectivity airplane-mode enable` and `adb shell cmd connectivity airplane-mode disable`. If the emulator ignores it, use `adb shell svc wifi disable` and `adb shell svc data disable`, then `enable`. Check with a screenshot that Plezy shows its offline state.
- Storage must be app storage. A custom SAF download folder fails every Silo download with "Silo downloads need app storage". Check **Settings > Downloads** before lane 1.

## Items

The probe signs in by device code and keeps tokens in memory, so nobody picked these against the server for this file. They are the items the S5 lanes recorded (`plan.md`, S5 "Items"). Confirm each before its lane, with the operator's device code, in one probe run:

```
printf 'watch movie-tmdb-1381078\nwatch movie-tmdb-12429\nwatch episode-tvdb-386002-7-9\n' \
  | dart run tool/silo_probe.dart --actions -
```

`watch` prints the stored position, the played flag and the track counts. It does not print file size.

- **Movie M.** Love of Your Life, `movie-tmdb-1381078`. Plays direct (`original_http`) at `auto`, so its download is the original file. Lanes 1, 2, 3, 5, 6, 9, 10 and perf. Its size is not recorded. If the detail page or the Plex copy shows it far above 1 GB, ask the operator for a movie under about 1 GB and use that id for lanes 1 to 3 and 6. For perf, any single file near 1 GB works.
- **Movie S.** Ponyo, `movie-tmdb-12429`, with 22 subtitles. The fallback for lane 4 if E has no text subtitle.
- **Episode E.** Taskmaster (SE) S7E9, `episode-tvdb-386002-7-9`. Lane 4 needs a text subtitle on it. If `watch` shows zero subtitle tracks, use Movie S for lane 4 instead.
- **Season.** Taskmaster (SE) season 7, the season E sits in, for lane 8. Its episode count is not recorded. If it is more than about six episodes or several GB, ask the operator for a shorter season. List a season's episodes read-only with `ids /api/v2/catalog/series/<series_id>/seasons/<n>/episodes` in the same probe run.

## Setup

1. Use the Plezy profile `Silo A` from the S3 lanes, bound to the Silo profile admin. Lane 9 also needs `Silo B`, bound to a different Silo profile with no PIN. See `docs/silo-migration/media/s3/lanes-howto.md`, "Setup".
2. Relaunch on `Silo A` and wait for `Silo: home sections <n>`.
3. Open **Downloads** from the sidebar. It must be empty for Silo, or hold only items you can identify.

## Server state each lane changes

- **The download registry.** Every download creates or reuses one entry in this installation's registry, and moves it through `downloading` and `completed`. The registry is per device, so it does not touch other devices' downloads. Deleting the download in Plezy (lane 6) deletes the local files. **It does not send `DELETE /api/v2/downloads/{id}`** at this head, so the entry stays on the server. A later download of the same file reuses it. To clear entries after the run, delete them in the Silo phone app or web UI, or leave them. They hold no bytes on the server.
- **Resume positions.** Lanes 2, 4, 5 and 10 play downloaded files, and the stop sends `/api/v1/sync/progress`. That moves the item's position. Restore it as S5 does: `echo "unwatched <id>" | dart run tool/silo_probe.dart --actions -` (one device code), then compare with `before-<id>.png`.
- **Watched state.** A play past 90 percent can mark the item watched. Restore with `unwatched`, or `watched` if it started watched.
- **Plex (lane 1 trunk and perf trunk).** The trunk download adds a Plex download on the device only. Delete it in Plezy after.

## Lanes

**Lane 1. Regression against trunk.** Changes the registry.
1. Build trunk (`feat/tv-silo-sidebar`), install, switch to the Plex profile, and download a Plex movie from its detail page (the download button in the action row). Wait for it to complete in **Downloads**. Save `download-trunk.png`. Delete it.
2. Build the S6 head, install, switch to `Silo A`, open M from Libraries, move along the action row to the download button, and Select. Pick the version if asked.
3. Open **Downloads** and wait. Save `download-head.png` when M shows complete.
4. Pass when M completes, and logcat shows `Started Silo transfer` and no `report failed`.

**Lane 2. Play the download offline.** Moves M's position.
1. With M downloaded, turn the network off.
2. Open **Downloads**, Select M, and play. Wait for video, then save `offline-play.png`.
3. Stop with Back. Turn the network on.
4. Pass when video renders with the network off. Restore M's position after lane 5.

**Lane 3. Interrupt the network mid-download.** Changes the registry.
1. Delete M from **Downloads** if it is there, then start its download again. A delete keeps the server entry, so this reuses it and Plezy fetches the bytes again.
2. When the row shows about 20 to 40 percent, turn the network off. Wait for the row to fail, and for `scheduling auto-retry in 30s` in logcat.
3. Turn the network on within about a minute. The app retries three times, 30 s apart. A retry that runs while still offline uses one of them.
4. Save `download-resume.png` when the row moves again.
5. Pass when logcat shows `Silo downloads: resuming at byte <n>` with `n` above zero, and the row's percentage continues from where it stopped instead of 0. A `restarting from zero` line, or a fresh transfer with no resume line, is a fail unless the server answered 416 (note it).

**Lane 4. Download an episode with subtitles.** Moves E's position.
1. Download E (or S, per Items). Wait for complete.
2. Subtitles are fetched after the file completes, in a second pass. Wait a few seconds after the row completes, then turn the network off.
3. Play E from **Downloads**, open the subtitle picker, turn on a text subtitle, and wait for a line. Save `download-subs.png`.
4. Pass when the subtitle text renders with the network off. If the picker lists no sidecar, check logcat for `manifest unavailable` and record its status. Restore E.

**Lane 5. Watch offline, then go online.** Moves M's position.
1. Turn the network off. Play M from **Downloads**, seek to about 10 minutes, let it play 30 s, and stop with Back. Note the position.
2. Turn the network on. Wait for Plezy to show online, up to a minute.
3. Check the position on the server: open M's detail page in the Silo app or web UI, or run `echo "watch movie-tmdb-1381078" | dart run tool/silo_probe.dart --actions -` (one device code). Save `offline-sync.png`.
4. Pass when the server shows the position within a few seconds of the one noted.
5. **Watch this one.** The Kotlin app's sessionless progress call is a stub today, so this path follows the older Kotlin wire and the Apple app (see the S6 notes in the final report). If the server answers `/api/v1/sync/progress` with 404 or 410, the position stays queued and the lane fails. Logcat then shows `Failed to sync action <n>: SiloDownloadException(progress_sync_failed, HTTP <status>)`. Record the status and stop.
6. Restore M with `unwatched`, and compare with `before-movie-tmdb-1381078.png`.

**Lane 6. Delete the download.** Local files only.
1. In **Downloads**, open M's menu and delete it.
2. Save `download-delete.png`.
3. Check the files are gone: `adb shell run-as com.edde746.plezy find . -name '*.part' -o -name '*.part.silo'` and the movie folder under the app's download directory must show no file for M.
4. Pass when M is gone from the list and no file for it is left. The server entry stays (see above).

**Lane 7. Retry a failed download in bulk.** Changes the registry.
1. The bulk action is **Retry all** on a show or season group in **Downloads**, which retries that group's failed episodes. So start downloads of E and the next episode, S7E10, from the same season.
2. Turn the network off while both run, and keep it off until both rows read failed after their three retries (about 2 minutes).
3. Turn the network on. In **Downloads**, open the season group's menu and pick **Retry all**.
4. Save `download-retry.png` when both complete.
5. Pass when both complete. A `resuming at byte` line for each is expected, since both kept their partials.

**Lane 8. Download a season.** Changes the registry, one entry per episode.
1. Open the season from the show's detail page and use its download action.
2. Wait for every episode to complete. Save `download-season.png`.
3. Pass when every episode completes. Each episode is created under the series with its own `episode_id`. Delete them after.

**Lane 9. Switch profile.** Read only.
1. With M downloaded on `Silo A`, switch to `Silo B` and relaunch.
2. Open **Downloads**. Save `download-profile.png`.
3. Pass when M is not listed. Switch back to `Silo A` and check M is still listed and plays.
4. If a transfer is running when you switch, it stops with `identity_changed` and waits for `Silo A`. That is intended.

**Lane 10. Relaunch offline.** Read only.
1. With M downloaded, turn the network off, force-stop the app, and relaunch.
2. Open **Downloads**. Save `offline-launch.png`.
3. Pass when the list opens and shows M with its artwork. Select it and check it plays. Turn the network on after.

## Perf lane

**Metric.** Time from start to completion for one file near 1 GB. Trunk downloads a Plex file, head downloads the Silo file. Throughput is size divided by time.

**Baseline first.** Record `curl` throughput for the same Silo file. The file route needs the profile's bearer, so only the operator can run it, and the token must never reach a log, the shell history or this repo:

1. Download the file once at head (lane 1), so its registry entry exists. Note its download id from the Silo app or from `GET /api/v2/downloads`, which the operator can read.
2. The operator writes the headers to a file outside the repo and outside `/tmp`, readable only by them: `Authorization: Bearer …`, `X-Profile-Id: …`, and `X-Silo-Device-Id:` with the emulator install's device id if the server checks it. Then:
   `curl -s -o /dev/null -H @"$HEADERS" -H 'Accept-Encoding: identity' -w '%{size_download} %{time_total} %{speed_download}\n' https://silo.ruleone.xyz/api/v2/downloads/<id>/file`
   Run it three times on the host, delete the header file, and record the three lines.
3. The emulator's network is the host's network, so this is the same path.

**Probe.** Three runs each, interleaved trunk, head, trunk, head, trunk, head. Each run deletes the previous copy first. Time from Select on the download button to the row reading complete, using the logcat timestamps of `Started Silo transfer` and the completion line for head, and the row screenshots for trunk.

**Rule.** Head throughput must be at least 80 percent of the `curl` median. Fail below that. Head's figure includes the PATCH reports and Plezy's progress updates every 500 ms, which should cost well under 1 percent.

## What the lanes must watch for

- `/api/v1/sync/progress` is the one call here that no current Kotlin code sends (lane 5).
- A completed PATCH that fails is only logged. If lane 1 shows `completed report failed`, the subtitles in lane 4 may never be fetched, because the manifest is read only once the server holds the download as completed.
- The transfer stops when Plezy's process dies. Lane 3 uses the network, not a force-stop, for that reason. A force-stop mid-download should resume on relaunch, which is worth one extra screenshot if time allows.
- Only three app retries, 30 s apart. A long outage fails the row, and a manual retry then resumes it.
