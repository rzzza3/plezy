# S4 wire parity audit

Every call and rule S4 adds, checked against `research/silo-catalog.md` and the Silo Kotlin source at `/home/mine/Desktop/silo-android/silo-android`. Audited at `83c5e098a` on 2026-10-14. The one fix is listed under Findings.

Prefixes follow the research file. `S/` is `shared/src/commonMain/kotlin/org/siloserver/silo/`. `T/` is `androidTvApp/src/androidMain/kotlin/org/siloserver/silo/tv/`.

## Calls and rules

| Call or rule | Plezy | Silo | Result |
|---|---|---|---|
| `POST /api/v2/events/ws-ticket` | `lib/silo/silo_events.dart` `_fetchTicket` | `S/network/apiv2/EventsSocketV2Api.kt:24-35` | Match. Bearer and profile headers, ordinary refresh allowed, 200 only. |
| Ticket validation | `SiloWsTicket.parse` | `S/network/apiv2/EventsSocketV2Api.kt:78-80` | Match. Protocol `silo.events.v2`, `expires_in` 1 to 30, `max_connection_seconds` 1 to 300, token characters only. |
| No session, no attempt | `_attempt` | `S/network/apiv2/EventsSocketV2Api.kt:38` | Match. Nothing is minted while signed out. The loop still backs off, as Kotlin's empty flow does. |
| Ticket expired before the upgrade | `_attempt` | `S/network/apiv2/EventsSocketV2Api.kt:39,45` | Match. The clock starts before the mint. |
| Upgrade URL | `siloEventsUri` | `S/network/apiv2/EventsSocketV2Api.kt:82-92` | Match. `ws` or `wss` on the origin, `/api/v2/events/ws`, only `channels=user_state,catalog`. |
| Upgrade headers | `_attempt`, `connectSiloSocket` | `S/network/apiv2/EventsSocketV2Api.kt:93-97`, `S/network/AuthInterceptorImpl.kt:409-414` | Fixed, see M1. The two subprotocols and the device headers, with no `Authorization` or `X-Profile-*`. |
| Server must choose `silo.events.v2` | `_attempt` | `S/network/apiv2/EventsSocketV2Api.kt:50` | Match |
| One ticket, one upgrade | `_attempt` | `S/network/apiv2/EventsSocketV2Api.kt:46-48` | Match. A ticket lives in one attempt and is never retried. Unit test "a ticket is never reused, even when the upgrade fails". |
| Subscribe first | `_attempt` | `S/network/apiv2/EventsSocketV2Api.kt:63`, `S/model/notifications/NotificationModels.kt:222-228` | Match. `{"type":"subscribe","channels":["user_state","catalog"]}`, with the null `request_id` omitted. |
| Authority watch | `_attempt` | `S/network/apiv2/EventsSocketV2Api.kt:51-67` | Match. A moved session generation closes the socket within 1 s and drops frames at once. |
| Connection lifetime | `_attempt` | `S/network/apiv2/EventsSocketV2Api.kt:48` | Match in effect. Kotlin's timer also covers the handshake. Plezy's starts once connected, so a connection can outlive `max_connection_seconds` by at most the 10 s connect timeout. The server enforces its own limit, and lane 6 saw it close at 5 minutes. |
| Frame decoding | `parseSiloEventFrame` | `S/network/HomeRealtimeClient.kt:76-101` | Match |
| Refetch rule | `siloHomeRefreshTrigger` | `S/network/HomeRealtimeClient.kt:108-114` | Match. The active profile is read live from the session, as `tokenManager.getProfileId()` is. |
| Debounce | `_trigger`, `_flush` | `S/repository/HomeRealtimeCoordinator.kt:32-36,63` | Match on the 2 s trailing window. See L1. |
| Backoff | `_loop` | `S/repository/HomeRealtimeCoordinator.kt:38-59,64-65` | Match. 1 s doubling to 30 s, reset once a frame decodes. Lane 4 measured 1, 2, 4, 8, 16, 30 s. |
| Foreground only, restart on profile switch | `LibraryEventService` (`suspend`, `resume`, stale client) | `T/home/HomeRealtimeForegroundStarter.kt:34-66` | Match. Lanes 5, 8 and 9 confirmed close on switch, background and sign-out. |
| `PUT /api/v2/home/dismissals/{surface}/{itemId}` | `lib/silo/silo_catalog.dart` `dismissHomeItem` | `S/network/apiv2/HomeSectionsV2Api.kt:28-39` | Match. `progress_updated_at` body for `continue_watching`, `series_id` for `next_up`, 204, single attempt. Lane 2 confirmed it live. |
| Dismiss only a matching card | `siloHomeDismissal` | `S/viewmodel/HomeViewModel.kt:412-430` | Match in rule. See L2 and L3. |
| Card leaves every progress row | `WatchStateNotifier` removal in `DiscoverProvider` | `S/viewmodel/HomeViewModel.kt:438-441` | Match |

## Findings

- **M1. The upgrade carried no device headers.** Kotlin treats the upgrade as a same-origin skip-auth request, so it strips credentials but attaches `X-Silo-Device-Id` and the client headers (`S/network/AuthInterceptorImpl.kt:409-414`). Plezy sent only the subprotocols, so the server could not tie the socket to this device. Fixed: `connectSiloSocket` now sends `SiloHeaders.toMap()`, which holds no credential. The unit test checks `x-silo-device-id` on the upgrade, along with no `authorization` or `x-profile-*`.
- **L1. A pending refetch does not survive a reconnect.** Kotlin's debounce lives in the coordinator, so a trigger pending when the socket drops still fires. Plezy's lives in the channel, and `stop` drops it. The next connection's `subscribed` refetches anyway, so nothing is missed.
- **L2. The Continue Watching anchor is compared to the second.** Plezy's card keeps `progress_updated_at` only as epoch seconds (`lastViewedAt`). Two progress writes inside one second would let a stale card through. The PUT always sends the server's exact string from the last home read.
- **L3. The progress-row test uses the substring rule.** Kotlin dismisses only from rows typed exactly `continue_watching`, `in_progress`, `next_up` or `up_next`. Plezy uses `siloSectionRole`, which also accepts unknown types containing those words. The live server sends only `continue_watching`.
- **L4. No guard against a double dismiss.** Kotlin keeps `pendingDismissals` per item. Plezy's menu closes on the first choice, so a second request needs a second menu open while the first is in flight.
