# S4 live lanes, how to run them

This file is for whoever runs the S4 **Verify, live** and **Verify, perf** blocks of `docs/silo-migration/plan.md`. Most S4 lanes need a watched or watchlist change made outside Plezy. The plan says "in the Silo app". This file proposes a cheaper way. `tool/silo_probe.dart` makes the change from the host, in one signed-in session that the operator approves once for the whole run.

Checked on the Android TV emulator `Television_1080p` with a debug build of `68bc6a099`, with Plezy profile "Silo A" signed in to `https://silo.ruleone.xyz`. Only the socket connect and lane 10 have run live (`lane-10-*`, `ticket-log.png`, `silo-a-home.png`, `silo-a-return.log`). The probe's `--actions` and `--profile` flags have run only against the local fake server in `test/silo/silo_probe_test.dart`. Nobody has run them against the live server yet.

## Ground rules

- Follow the plan's boot recipe and the S3 ground rules in `media/s3/lanes-howto.md`. Never uninstall or clear data. Never press Select on a Continue Watching card. On a cold start, focus lands on the first one.
- Read state with `adb exec-out screencap -p` and `adb logcat -s flutter`. Every S4 log line is structural. They are `Silo events: <phase>` (idle, fetchingTicket, connecting, subscribed, backingOff, closed), `Silo events: 2 channels, 0 rejected`, `Silo events: user_state.changed (<change>)`, `Silo events: catalog event`, `Silo events: home refetch`, `Silo: home sections <n>`, and `Home: rows repainted`.
- The server sends `subscribed` twice per connection, about 220 ms apart. The 2 s debouncer turns both into one `home refetch`.
- `user_state.changed` is account-wide. Plezy refetches only when the event's profile is the active Silo profile. So the probe must act as the Silo profile "Silo A" is bound to, which is `2b4a12c9-fd29-4dd7-b478-abb1b70568ee` on this emulator. Read it again with the query below if the binding changes. It reads only the id column, never `user_token`.

```bash
d=$(mktemp -d)
for f in plezy_downloads.db plezy_downloads.db-wal plezy_downloads.db-shm; do
  adb exec-out run-as com.edde746.plezy cat app_flutter/$f > $d/$f
done
sqlite3 $d/plezy_downloads.db "select p.display_name, pc.user_identifier from profile_connections pc
  join connections c on c.id = pc.connection_id join profiles p on p.id = pc.profile_id where c.kind = 'silo';"
rm -rf $d
```

## The method. One probe session for the whole run

The probe signs in by device code and holds the tokens in memory only. With `--actions -` it reads one command per line from stdin, runs each in that session, and logs out at end of input. A FIFO held open by the lane runner keeps it alive across every lane. It prints ids, statuses and times, never a title or a token.

| Command | Wire call | Prints |
| --- | --- | --- |
| `home` | `GET /api/v2/home/sections` | `section <section_type> ids=<content ids>` per row |
| `watched <id>` | `POST /api/v2/watched/{id}` | `action watched <id> <status> done_ms=<epoch ms>` |
| `unwatched <id>` | `DELETE /api/v2/watched/{id}` | same shape |
| `watchlist-add <id>` | `PUT /api/v2/watchlist/{id}` | same shape |
| `watchlist-remove <id>` | `DELETE /api/v2/watchlist/{id}` | same shape |
| `toggle <id> <n> <s>` | n flips, watched first, `s` seconds apart | one line per flip |
| `sleep <s>` | none | nothing |

Start it once, in bash, with samples sent to `/tmp` so the research samples are not overwritten:

```bash
mkfifo /tmp/silo-lanes.fifo
dart run tool/silo_probe.dart https://silo.ruleone.xyz \
  --samples /tmp/silo-lane-samples \
  --profile 2b4a12c9-fd29-4dd7-b478-abb1b70568ee \
  --actions - < /tmp/silo-lanes.fifo > /tmp/silo-lanes.out 2>&1 &
exec 3> /tmp/silo-lanes.fifo
lane() { echo "$*" >&3; sleep 1; tail -n 3 /tmp/silo-lanes.out; }
```

**The operator's part.** `/tmp/silo-lanes.out` shows `USER_CODE xxxx xxxx` and a `VERIFY` URL. The operator approves that code once, as admin. The agent never approves it. `profile selected id=2b4a12c9-… pin_token=false` confirms the profile. That profile must have no PIN. If it has one, `--profile` fails with 403 and the operator types the PIN on the approval page instead, without `--profile`. When every lane is done, `exec 3>&-` ends input and the probe logs out (`logout 204`).

Then `lane home` lists ids. Pick these from it and keep them for the run.

- `M`, a movie in a shelf row such as `recently_added` that is not watched and not in the watchlist. It is used by lanes 1, 4, 5, 6, 8 and perf.
- `CW`, a movie in `continue_watching`, for lane 2. A dismissal has no undo route in Silo's client. Inferred from the code, the card comes back only when its progress moves. So pick one the operator does not mind losing from the row.
- `NU`, an episode in `next_up`, for lane 3. The same caution applies.
- `W`, an item not in `watchlist`, for lane 7.

Every lane below undoes its own watched and watchlist changes.

Probe writes are single attempt, so they are never refreshed first. After about 15 minutes without a read, a write returns 401. Send `lane home` before a write that follows a long gap. Kotlin has the same rule (`S/network/AuthInterceptorImpl.kt:551-593`).

## Lanes

Before each lane, clear logcat with `adb logcat -c`, and keep `adb logcat -s flutter | grep -E 'Silo events|Home: '` running.

1. **Live update.** On the "Silo A" home, `lane watched M`. Pass when logcat shows `user_state.changed (watched)`, then `home refetch` and `Home: rows repainted`, within 5 s of `done_ms`, and M's card gains the watched badge or leaves its row. Save `realtime-head.png`. Restore with `lane unwatched M`. Trunk `5fc148779` has no Silo, so the trunk half is only the S3 lane 1 trunk capture.
2. **Dismiss Continue Watching.** Move focus to CW without Select. Open its context menu with the Menu key, `adb shell input keyevent 82`, never with Select. Android's Menu maps to Flutter's `contextMenu` key, which `lib/focus/dpad_navigator.dart:49` treats as a context-menu key. Nobody has pressed it on a live card yet, so take a screenshot to confirm the menu opened before going on. Choose **Remove from Continue Watching**. Pass when the card disappears with "Removed from Continue Watching", logcat shows `user_state.changed (home_dismissal)`, and the card is still gone after a force-stop and relaunch. Save `dismiss.png`.
3. **Dismiss Next Up.** Same as lane 2 on NU. The request carries `series_id`. Save `dismiss-next-up.png`. On 2026-10-14 the server had no `next_up` row, so this lane had nothing to act on. Run it when `lane home` lists one.
4. **Network off a minute.** Airplane mode does not cut this TV emulator, which stays on Ethernet. Block Plezy alone instead with `adb shell cmd connectivity set-package-networking-enabled false com.edde746.plezy` and `adb shell cmd connectivity set-chain3-enabled true`, wait 60 s, then undo both (`true`, then `false`). Pass when logcat shows ticket attempts backing off 1, 2, 4, 8, 16 and 30 s while blocked, then `fetchingTicket`, `connecting`, `subscribed` and exactly one `home refetch` after the unblock. Save `reconnect.png`.
5. **Profile switch.** Switch to the Plex profile from the sidebar profile sheet. Logcat shows `Silo events: idle`, then `closed`. Then `lane watched M`. Pass when no `Silo events` line follows and the Plex home is untouched. Save `realtime-profile.png`. Switch back to "Silo A", which should show a fresh `fetchingTicket` to `subscribed`, and `lane unwatched M`. Checked once by hand already (`plex-profile-switch.log`, `silo-a-return.log`). A switch between two Silo profiles waits for S9, as S3 lane 10 did.
6. **Idle ten minutes.** Leave the home for 10 minutes, then `lane watched M`. The ticket allows a connection of at most `max_connection_seconds` (300 or less), so expect a `backingOff` (1 s) then `subscribed` cycle at least every 5 minutes. Pass when the change still updates the home. Save `idle.png`. Restore.
7. **Watchlist.** `lane watchlist-add W`. Pass when the watchlist row gains W within 5 s, logged as `user_state.changed (watchlist)` then `home refetch`. Save `watchlist-event.png`. Then `lane watchlist-remove W` removes it again.
8. **Background and foreground.** Press Home (`keyevent 3`). Logcat shows `Silo events: idle`, then `closed`. While backgrounded, `lane watched M`. Relaunch with the monkey command. Pass when the socket reconnects, one `home refetch` follows `subscribed`, and M shows watched with no spinner. Save `resume.png`. Restore.
9. **Sign out. Run this lane last.** Do not use **Log out** on the profile sheet. It runs `logoutAllProfiles` (`lib/profiles/profile_menu.dart:76`) and would also sign the emulator out of Plex. Instead open Settings, then Profiles, then "Silo A" ⋮ **Manage**. On the Silo connection's ⋮ choose **Remove** and confirm. As the last reference, that sends `POST /api/v2/auth/logout` (`lib/profiles/profile_connection_cleanup.dart:197-210`). Pass when logcat shows `Silo: logout status 204`, then `Silo events: idle` and `closed`, and no `fetchingTicket` follows. Save `signout-socket.png`. Re-add it with **+ Add**, **Connect to Silo**, `silo.ruleone.xyz`, and a device code the operator approves. Then pick admin, which is `2b4a12c9-…`.
10. **Ticket in logs.** Done at `5ccc4c7a0` on a relaunch. The full logcat (1484 lines) mentions "ticket" only in the phase name `fetchingTicket`. No string of 28 or more opaque characters appears in flutter lines except a local Plezy profile id (`lane-10-ticket-scan.txt`, `ticket-log.png`). Rerun the same scan at the verdict head.

## Perf lane

The metric is server change to repaint. Within one session:

1. Baseline first. `lane toggle M 10 8` makes 10 changes 8 s apart, ending unwatched. For each flip, take the gap from the probe's `done_ms` to the logcat `Silo events: user_state.changed` line. That gap is server event to frame delivery.
2. The same 10 flips give the metric, from `done_ms` to the next `Home: rows repainted`.
3. Pass when the median is under 3 s. The 2 s debounce is inside that, so delivery, the refetch and the paint share about 1 s.

The host clock and logcat must agree. Check `adb shell date +%s%3N` against `date +%s%3N` before the run and subtract the offset. Logcat prints wall time to the millisecond. Use `adb logcat -v epoch` to get epoch seconds directly.
