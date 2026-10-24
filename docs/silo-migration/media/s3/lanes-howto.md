# S3 live lanes, how to run them

This file is for whoever runs the S3 **Verify, live** and **Verify, perf** blocks of `docs/silo-migration/plan.md`. It covers setup, the key sequence for each lane, what a pass looks like, and which lanes change server state. The lanes need a signed-in Silo profile, and only the operator can approve a device code or type a password. So setup comes first and needs the operator once, or twice for lane 10.

The steps were checked by hand on the Android TV emulator `Television_1080p` at `35342075d` with the Plex sign-in. The Silo steps follow the code at that head and the S2 lanes. Nobody has run them against a live Silo server yet.

## Ground rules

- Boot recipe from the plan. Build with `flutter build apk --debug --target-platform android-x64`, install with `adb install -r`. Never uninstall, never clear data.
- Keys are `adb shell input keyevent <n>`. Up 19, Down 20, Left 21, Right 22, Select 23, Back 4.
- The sidebar scrolls to keep focus centred, and Plex brings many libraries. A fixed count of Downs is not reliable. Take `adb exec-out screencap -p` and read where focus is before every Select.
- Never press Select on a Continue Watching card. On a cold start, focus lands on the first Continue Watching card.
- Reset to the home with a relaunch, `adb shell am force-stop com.edde746.plezy`, then `adb shell monkey -p com.edde746.plezy -c android.intent.category.LEANBACK_LAUNCHER 1`.
- The home has painted when logcat shows `Home: first hub frame, rows <n>`. A Silo home also logs `Silo: home sections <n>`, which counts the rows left after hydration and ebook drops. Neither line holds a title.

## Sidebar landmarks, checked at `35342075d`

- From a card on the home, Left opens the sidebar on Home.
- Holding Down (40 presses) stops on Settings, the last entry. Holding Up (40 presses) stops at the top. From there one Down reaches Search and two reach Home, but take a screenshot to confirm.
- In Settings, focus starts on General. Five Downs reach **Add connection** and six reach **Profiles**.
- Profiles opens "Switch Profile". Down from the active profile reaches **Add Plezy profile**.
- Each server shows as a group header (`›` and the server name) with its libraries under it.
- A library opens on its first tab. A Silo library has two tabs, **Recommended** and **Browse**, because `visibleLibraryTabs` drops Collections and Playlists for Silo. Browse has the kind chip, **Filters** and **Sort** above the grid, and the A-Z rail on the right edge.

## Order of work

Trunk is `feat/tv-silo-sidebar` at `5fc148779`. It predates S1 and has never run on a device that stores a Silo connection. So take every trunk capture, lane 1's `home-trunk.png` and the ten trunk perf runs, before setup adds one. Then do setup, then the head lanes and the ten head perf runs. That breaks the plan's interleaving. Interleaving would mean a trunk build reading stored Silo data, and nobody has tested that.

## Setup. Put Silo on its own Plezy profile

Use a separate Plezy profile so the home shows only Silo rows. With Silo added to the Plex profile instead, Silo rows mix with Plex rows and Continue Watching merges both. Lane 1 then cannot be read.

1. From the Plex home, Left, hold Down to **Settings**, Select.
2. Six Downs to **Profiles**, Select. Down to **Add Plezy profile**, Select.
3. Name it `Silo A` and save. `AddLocalProfileScreen` then opens **Add connection** scoped to the new profile.
4. Pick **Connect to Silo**, the second card. Enter `https://silo.ruleone.xyz`.
5. The login screen shows a device code. **The operator approves it**, or types the password. The agent never does either.
6. The Silo profile picker lists the server's profiles. Pick a profile without a PIN, or let the operator type the PIN.
7. The app returns to `Silo A`'s home. Logcat shows `Silo: profile entered`, then `Silo: home sections <n>`.

**Lane 10 needs a second Plezy profile.** Repeat steps 1 to 6 as `Silo B` and pick a different Silo profile. This costs a second device-code approval, because `SiloServerScreen` always opens a new login. "Borrow from another profile" copies the same Silo profile id, so it cannot stand in. Both Plezy profiles share one Silo session slot per server, and `SiloClient.create` re-selects the bound profile without a token. Switching to a PIN profile that way fails, so `Silo B` must use a profile without a PIN.

To switch Plezy profiles, Left, hold Up to the avatar at the top of the sidebar, Select, and pick the profile.

To reach the Plex home again for lane 1 trunk, switch back to the Plex profile.

## Lanes

Save screenshots to `/tmp/swarm-feat-silo-s3-catalog/lane-<n>/<slug>.png`, per the boot recipe.

**Lane 1. Regression against trunk.** Read only.
1. Before setup, build trunk, install, relaunch on the Plex profile, and wait for the home. Save `home-trunk.png`.
2. Build the S3 head, install, switch to `Silo A`, relaunch, and wait for `Silo: home sections <n>`. Save `home-head.png`. Press Down to reveal later rows, never Select, and save `home-head-<k>.png` for each.
3. Pass when Continue Watching is at the top as backdrop cards, and the rows below follow the server's order for that profile.

Ambiguous. `research/samples/home-sections.json` records the shape, 17 sections, and the 10 `section_type` values, but not their order or titles. So "match in order" needs a live reference. Use the Silo TV app or web UI for the same profile, or `GET /api/v2/home/sections` with the operator's session. Plezy shows the `continue_watching` and `next_up` rows as its single Continue Watching row. It drops rows that are empty after hydration, rows that only hold ebooks, and rows whose `/items` read failed. The other rows keep server order.

**Lane 2. Every library shows items.** Read only. Left, then Down to each library under the Silo server header, Select, and wait. Save `library-<n>.png`. Pass when each library shows items on Recommended or Browse. Hidden libraries (`ui.disabled_library_ids`) and ebook libraries are not listed, by design.

**Lane 3. Scroll to the end.** Read only. Open the largest library, Right to **Browse**, Select, then Down to the grid. Hold Down in bursts of 20, taking a screenshot after each, until the grid stops moving. Save `library-end.png`. Pass when items keep loading without a repeated poster, and logcat has no `SiloInvalidCursorException`. Pages are 100 items, so a library over 100 items crosses at least one cursor.

**Lane 4. Genre filter.** Read only. On Browse, Up to the chip row, Right to **Filters**, Select. Pick **Genre**, then one value, and apply. Save `library-genre.png`. Pass when every item shows that genre. Open two or three to check on detail. The request goes out as `POST /api/v2/catalog/query`.

**Lane 5. A-Z rail.** Read only. On Browse, move Right from the right-most grid column into the rail and Down to a letter such as `M`. Select. Save `library-az.png`. Pass when the first item starts with that letter. Select the same letter again to clear it. Avoid `#`, because `name_prefix=#` has not been checked against the server.

**Lane 6. Movie detail.** Read only. On a movie poster in Browse (not on the home), Select. Save `detail-movie.png`. Pass when title, year, synopsis and cast match the Silo app for the same item. Do not Select the Play button. Focus starts on it.

**Lane 7. Show detail.** Read only. Open a show from a series library's Browse. Save `detail-show.png`. Pass when the season selected first matches the Silo app's choice. The rule is a season with an episode in progress, then a partly watched season, then the first unwatched one, then the first season, with specials last (`siloInitialSeason`). A show with history across several seasons is the useful case.

**Lane 8. Search.** Read only. Left, hold Up, Down to **Search**, Select. Type a title the operator knows exists with `adb shell input text '<title>'`, using `%s` for spaces. Wait one second for the 300 ms debounce. Save `search.png`. Pass when it appears in results.

**Lane 9. Watched toggle.** Changes server state.
1. Open a movie detail as in lane 6. Note whether the Silo app shows it watched.
2. Right along the action row, taking a screenshot after each step, until the check-circle "Mark as watched" button has focus. The row's order depends on the item, so never count. Select.
3. Back, reopen the movie, and save `watched.png`. Check the Silo app shows the same state.
4. **Toggle it back.** Repeat step 2 on "Mark as unwatched" and confirm the Silo app shows the original state. Pick an unwatched movie with no resume position, so the toggle back restores it exactly.

**Lane 10. Profile switch.** Read only. From `Silo A`'s home, switch to `Silo B`, then relaunch. Save `profile-switch.png`. Pass when the home shows `Silo B`'s rows, which differ from `Silo A`'s in favorites, watchlist or Continue Watching. Pick two profiles with different history so the difference shows.

## Perf lane

Read only. The metric is cold start to the first home row painted.

1. Trunk has no `first hub frame` line, because `fb99ddc84` adds it. Build the baseline from a scratch worktree, `git worktree add /tmp/s3-trunk 5fc148779`, then `git -C /tmp/s3-trunk cherry-pick fb99ddc84`. It touches only `discover_screen.dart` and applies cleanly. Remove the worktree afterwards.
2. Each run is `adb shell am force-stop com.edde746.plezy`, `adb logcat -c`, the monkey launch, then wait for `first hub frame`. Time from the `ActivityManager: Start proc <pid>:com.edde746.plezy` line to the `Home: first hub frame` line, both from `adb logcat -v threadtime`.
3. Ten trunk runs on the Plex profile before setup, then ten head runs on `Silo A` after it. See Order of work for why they are not interleaved.
4. Record the trunk median first. Pass when the head median is under 2.5 s.

`rows <n>` counts what painted in that frame. At `35342075d` on Plex it read `rows 1`, which is Continue Watching only, because Plex hubs land a moment later. Report the row count with the timings.

## State-changing lanes

Only lane 9 writes to the server, and it must be toggled back. Setup creates Plezy profiles on the device and Silo sessions on the server. Remove both after the verdict if the operator wants a clean device. Never press Select on a Continue Watching card, because it starts playback and moves the resume position.
