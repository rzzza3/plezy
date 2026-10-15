# S5 live lanes, how to run them

This is for the operator and the lane workers who run the S5 live and perf lanes. It names the items, the keys, the evidence, and every server-side change each lane makes and how to undo it. No lane has run yet. The code head is `07ea665bd` on `feat/silo-s5-playback`. Run the lanes at the commit that adds this file, which differs from the code head only by this file.

## Before any lane

1. The operator approves the run in chat. Every lane except perf trunk plays on the Silo server `https://silo.ruleone.xyz` as profile admin. Each play opens a server session and moves that item's resume position.
2. Follow the plan's boot recipe. Build with `flutter build apk --debug --target-platform android-x64`, then `adb install -r`. Never uninstall and never clear data.
3. Check that nobody else is driving. `adb shell uptime` must show the uptime you expect, and `adb logcat -s flutter` must show no intents you did not send.
4. Never press Select on a Continue Watching card. Open every item from Libraries, then its detail page, then Play.
5. Before the first play of an item, screenshot its detail page as `before-<id>.png`. That screenshot is the restore target, because it shows the watched mark and the progress bar.
6. Keep `adb logcat -s flutter` running into `/tmp/swarm-s5/lane-<n>/logcat.txt`. The Silo lines are safe to keep. They carry no token, URL, title or session id.

## Items

- **Movie M.** Use `movie-tmdb-1381078`, the movie the S4 lanes and the S5 probe used. It plays direct with `auto` and transcodes with `480p` (measured on 2026-10-14). If its detail page shows it watched, or shows progress the operator wants to keep, pick another unwatched movie and use that id below.
- **Movie A.** A movie with two or more audio tracks, for lane 4. The detail page's audio picker lists them. The operator names it.
- **Movie S.** A movie with at least one text subtitle track, for lane 5. M qualifies if its detail page lists a subtitle.
- **Episode E.** The second-to-last episode of a season, with a next episode in the same season, for lane 9. Pick one nobody on the server is watching.

## Restoring server state

- **Resume position.** A play moves the item's position. To clear it, mark the item unwatched. The lanes before this one used the probe for that:
  `echo "unwatched <id>" | dart run tool/silo_probe.dart --actions -`
  The probe signs in by device code, so the operator approves one code each time. Whether unwatched also clears the position is inferred, not measured. Check the detail page after, against `before-<id>.png`.
- **Watched.** Lane 9 marks E watched when it finishes. Restore it with `unwatched <E id>` as above, or `watched` if it started watched.
- **Sessions.** Each Plezy stop ends its own session. Lane 8 leaves one open on purpose, and the next start in that lane stops it. The server also expires sessions nobody stops.
- **Plex (perf trunk only).** The perf lane's trunk plays move the Plex item's position. Mark it unwatched in Plex after, or restore it to the position its `before` screenshot shows.

## Lanes

Each lane saves its screenshot to `/tmp/swarm-s5/lane-<n>/<slug>.png` with `adb exec-out screencap -p`.

1. **Regression against trunk.** Changes Plex and Silo positions. Build trunk (`main`), play a Plex movie from its detail page for 30 s, then Back. Confirm the Plex home still loads and the movie shows progress. Build head, sign in to Silo if needed, play M from its detail page for 30 s, then Back. Save `play-head.png` while video plays. Pass when video renders and M's detail page shows the new position after Back. Restore both items.
2. **Direct play.** Changes M's position. Quality on Original, play M. Logcat shows `Silo playback: plan delivery=original_http`. Save `direct.png`. Pass on that line plus rendered video. Restore M.
3. **Transcode.** Changes M's position. In the player's quality menu choose 480p, or set it before Play. Logcat shows `plan delivery=server_transcode_hls`, and on an in-player change, `replanned quality_change`. Save `transcode.png`. Pass when video renders on that plan. Restore M.
4. **Audio switch.** Changes A's position. Play A, open the audio menu, pick the other track. Logcat shows `Silo playback: replanned track_change`. Save `audio-switch.png`. Pass when that line appears and the audio language audibly or visibly (track label) changes. Restore A.
5. **Subtitles on and off.** Changes S's position. Play S at 480p, so the plan lists sidecars. Turn a subtitle on, wait for a line, save `subs.png`, then turn it off and save `subs-off.png`. Pass when the text renders and then disappears. Direct play reads embedded tracks from the file, so on Original the same check covers mpv's own track. Restore S.
6. **Seek far ahead in a transcode.** Changes M's position. Play M at 480p and seek about 40 minutes ahead with repeated DPAD_RIGHT or the seek bar. Save `seek-replan.png` once it plays. Pass when playback continues at the target. This server sends no seek window and `can_seek_anywhere: true` (measured), so mpv seeks natively and no `replanned seek_reanchor` line is expected. A `seek_reanchor` line would mean the server started sending windows. Note it if it appears. Restore M.
7. **Longer than the token lifetime.** Changes M's position. Play M at Original and leave it playing past one access-token lifetime. That lifetime is the `expires_in` the server returns at sign-in, which this repo does not record. Use it plus 5 minutes. If nobody knows it, play 65 minutes, which is a guess at a one-hour token. Save `long-play.png` at the end. Pass when playback never stalls and logcat shows no `Silo proxy: upstream failed`. The direct stream also carries a signed `st` query, so a stall would point at its expiry, not the bearer. Restore M.
8. **Kill mid-play and relaunch.** Changes M's position and leaves one session open until step 3. (1) Play M for 30 s. (2) `adb shell am force-stop com.edde746.plezy`, then relaunch with the boot recipe's monkey command. (3) Play M again. Logcat shows `Silo playback: stopped (status 200)` before the new `Silo playback: started`, which is the journal stopping the old session. Save `journal.png`. Pass when that order holds and the old session no longer shows as active on the server. Where the server shows active sessions is a guess: an admin dashboard, if this server has one. The `stopped (status 200)` line is the client-side proof either way. Leftovers are stopped at the next start, not at launch, so step 3 is what proves it. Restore M.
9. **Finish an episode.** Marks E watched and moves the next episode's state only if it autoplays. Play E, seek to about 30 s before its end, and let it finish. Save `next-episode.png` when Up Next shows. Pass when the next episode is offered. Back out before it autoplays, or let it play and restore it too. Restore E with `unwatched`.
10. **Position sync.** Changes M's position. Play M, stop at a position you read off the player, such as 10:00, then Back. Note the time. Open M in the Silo Android app, on a phone or TV, without starting it. Save `position-sync.png` of its resume point. Pass when the stored position is within 2 s of the stop. The Silo app starts playback 7 s before the stored position by design, so compare the stored position, not where its playback begins. Restore M.

## Perf lane

This lane changes the Plex item's position on trunk and M's on head, ten plays each.

- **Marker.** Neither trunk nor head logs the first frame at info level. Apply this one-line change to both builds, the same way, and do not commit it. In `lib/screens/video_player/parts/playback_services.dart`, right after `_firstFrame.markReady();`, add `appLogger.i('Perf: first frame');`.
- **Probe.** Ten plays each of the same direct-play file, interleaved trunk, head, trunk, head. Trunk plays a Plex direct-play movie. Head plays M at Original. Start each from the detail page with focus on Play. Record the host time when `adb shell input keyevent DPAD_CENTER` is sent, and the logcat time of `Perf: first frame`. Use `adb logcat -v epoch` so both are epoch seconds. Back out and wait 5 s between plays.
- **Baseline.** Compute the trunk median first.
- **Rule.** Head median under 3 s for direct play. Fail above that. Report both medians and the ten raw pairs for each side.
- **Restore.** Mark the Plex movie and M unwatched, or back to their `before` screenshots.

## What the operator approves

- The run itself, and each device code the probe needs for restores.
- Which items are M, A, S and E, if M does not fit or A, S and E are unknown.
- Lane 7's hour of playback.
- Lane 9 marking E watched.
- The perf lane's ten Plex plays.
