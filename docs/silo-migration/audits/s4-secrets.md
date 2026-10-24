# S4 secrets and data-loss audit

Where S4 could leak the ticket, a token or a title, or lose user data. Audited at `83c5e098a` on 2026-10-14, together with the M1 fix in `s4-wire-parity.md`.

## Secrets

| Path | Result |
|---|---|
| Ticket value | Kept in a private field of `SiloWsTicket`. `toString` prints `<redacted>`. It leaves the object only as the `silo.ticket.<value>` subprotocol on the one upgrade. Lane 10 found no ticket and no opaque string of 28 or more characters in 1484 lines of logcat. |
| Ticket response body | Parsed and dropped. Never logged. `SiloExchange` carries header names only. |
| Upgrade request | The URL holds only `channels`. Headers are the subprotocols and the device headers, with no `Authorization` or `X-Profile-*` (unit test). |
| Cleartext origins | The ticket is minted by a `POST` that `SiloHttp` refuses on an unapproved `http://` origin, so a `ws://` upgrade only happens to an origin the person approved. |
| Error paths | Ticket and upgrade failures log only the error's runtime type and the HTTP status. `dart:io` upgrade errors name the URL, which holds no secret. |
| Logs | Phases, channel counts, the `change` kind and `Home: rows repainted`. No ids, titles, tokens or profile tokens. |
| Sentry | `appLogger` does not forward to Sentry, and `recordHttpBreadcrumbs` is off (`lib/main.dart:280`). `SiloEvents` catches its own network errors, so none reaches the uncaught handler. |
| Probe `--actions` | Prints content ids, the Silo profile id, statuses and times. It never prints titles or tokens (unit test). Its output file during the run held no token (checked). The device code it prints is the same one Plezy shows on screen. |

## Data loss

| Path | Result |
|---|---|
| Dismissing the wrong card | The PUT goes only when the visible card's id and anchor match the last home read, and it names that card's id. A stale card is refused. |
| Dismissal is permanent | Silo's client has no undo route, and the menu asks for no confirmation, as Plex's own removal does not. Lanes 2 and the review video each removed one card, with the operator's consent. |
| Identity moving mid-dismiss | `SiloCatalog._write` throws `siloIdentityMoved` if the session generation moved, so the result is not applied to the new profile. |
| Plex, Jellyfin and Emby | Their events never set `homeChanged`, and their pacing is unchanged (unit test "a home-stale push refetches every time"). `WebSocketConnectAttempt` sends `protocols` only when given. Lane 5 loaded the Plex home. |

## Findings

- **L1. A refused stale dismissal reads as "Error: the request was cancelled".** The refusal is right, but the wording does not say the card had changed. The next refetch replaces the card. Kotlin ignores the tap silently.
- **L2. A profile playing on another device refetches the home about every 10 s.** `user_state.changed (progress)` for the active profile passes the filter, as in Kotlin. The live run saw it while someone watched Game of Thrones on the account.
- **L3. A long gap with no reads can make a write return 401.** Single-attempt writes are not refreshed first, as Kotlin's are not (`S/network/AuthInterceptorImpl.kt:551-593`). While Plezy is in the foreground, the socket's ticket mint refreshes the token at least every 5 minutes, which hides this. This is S3's write path, recorded for the operator.
- **Not S4. The profile sheet's Log out signs out every account.** `logoutAllProfiles` signs out Plex too. Lane 9 used the per-connection Remove instead. This is existing Plezy behaviour.
