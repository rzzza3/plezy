# S2 secrets and data-loss audit

Where Silo credentials flow, what is logged and stored, what sign-out wipes, and whether anything from `feat/tv-silo-sidebar` to S2 can remove existing Plex, Jellyfin or Emby connections. Audited at `d0f61223d` on 2026-10-13 against the code and the Android TV emulator's app data.

## Secrets

| Secret | Where it lives | Where it goes | Logged |
|---|---|---|---|
| Password | `TextEditingController` on the login screen, disposed with the screen (`lib/screens/auth/silo_login_screen.dart:38`, `:105-114`) | The `POST /api/v2/auth/login` body only (`lib/silo/silo_sign_in.dart:88-91`). Blocked on an unapproved `http://` origin. | No |
| Username | Login form, then `SiloConnection.username` in the connection row's config | Login body. Shown in the connection label. | No |
| `device_code` | `SiloDeviceCode.deviceCode` in memory | Poll and cancel bodies only (`lib/silo/silo_device_sign_in.dart:353`, `:461`) | No. `toString` prints the user code, never the device code (`:73`). |
| `user_code` | On screen and in the QR, by design | Nowhere else | No |
| Access and refresh tokens | `silo_session_v1.<server_id>` in prefs, wrapped by `CredentialVault` (`lib/silo/silo_vault_store.dart:21-31`). `SiloIssuedTokens.toString` is redacted (`lib/silo/silo_device_sign_in.dart:101`). `SiloTokens` has no `toString`, so it prints as `Instance of 'SiloTokens'`. | `Authorization` on same-origin requests only. The refresh body. | No |
| Profile token | Same session slot, written with the profile id (`lib/silo/silo_session.dart` `selectProfile`) | `X-Profile-Token` on same-origin requests. Never on `verify-pin` (`lib/silo/silo_profiles.dart:113-116`). | No |
| Device id | `silo_device_id` in prefs, apart from the session | `X-Silo-Device-Id` | No |

Every `appLogger` line under `lib/silo`, `lib/screens/auth/silo_*`, `lib/screens/profile/silo_profile_screen.dart` and `lib/services/silo_client.dart` logs a fixed string, a status code, a count, an error `runtimeType`, a server name or a connection id. None interpolates a token, code, password or username. `SiloExchange` carries header names only (`lib/silo/silo_http.dart` `SiloExchange`), and its one consumer is `tool/silo_probe.dart:169`.

Measured on the emulator today, the one remaining slot value starts with `enc:v1:`. Monday's lane 9 found no token text in prefs or in the connection row. By construction the Silo `config_json` holds `origin`, `serverId`, `serverName` and `username` only (`lib/connection/connection.dart`, `SiloConnection.toConfigJson`).

`isSiloSessionPrefKey` is in the sensitive-prefs list (`lib/services/sensitive_prefs.dart:44`, `:87`). A corrupt-store repair salvages the slots, and a tolerant read never drops one silently.

## Sign-out paths

| Path | Server logout | Local slot | Before this audit |
|---|---|---|---|
| Last profile lets go of a Silo connection, from settings or the startup prune (`lib/profiles/profile_connection_cleanup.dart` `_removeSiloConnection`) | Yes | Wiped | Same |
| Backing out of the picker, or the login screen closing before the picker (`lib/screens/auth/silo_login_screen.dart:89`, `:96-99`) | Yes | Wiped | Same |
| Profile menu "Logout" (`lib/screens/profile/profile_teardown.dart` `logoutAllProfiles`) | Yes, per Silo connection | Wiped, and `clearCredentials` sweeps every `silo_session_v1.*` key | Neither. Finding H1. |

## Findings

### H1. Full logout left the Silo session alive. High. Fixed in `d0f61223d`.

`logoutAllProfiles` cleared the connection rows but never called `POST /api/v2/auth/logout`, and `clearCredentials` did not remove `silo_session_v1.*`.

Failure scenario, measured on the emulator. After Monday's last Logout the database held no connections and no profiles, yet prefs still held `silo_session_v1.2b68c785-…` (1073 bytes, `enc:v1:`). The device kept a refresh token for a server it showed as signed out, and the server still listed the session.

Fix. `ProfileConnectionCleanup.signOutAllSiloConnections` signs out each Silo connection while its bearer is still present. `logoutAllProfiles` calls it before credentials go. `StorageService.clearCredentials` also removes every Silo session slot and keeps `silo_device_id`. Tests are in `test/profiles/profile_connection_cleanup_test.dart` ("full logout signs out every Silo connection and leaves other kinds alone") and `test/services/storage_service_test.dart` ("removes every Silo session slot and keeps the Silo device id").

The orphan slot is still on the emulator. The brief rules out signing anything out, and the next full Logout on this build removes it.

### M1. A session committed before the picker can outlive a killed process. Medium. Open.

The tokens are saved when the sign-in wins (`lib/silo/silo_sign_in.dart` `_commit`). The connection row is written only after a profile is entered (`lib/screens/profile/silo_profile_screen.dart:127-171`). If the process dies on the picker, the slot survives with no connection row. Nothing at startup sweeps slots without a row. The startup prune walks connection rows only (`lib/profiles/profile_connection_cleanup.dart`, the Silo loop in the prune).

Failure scenario. Sign in, then force-stop the app on the profile picker. The encrypted refresh token stays in prefs and the server keeps the session until the next full Logout, or until a later sign-in to the same server overwrites the slot without logging the old session out.

Fix for the root. In the startup prune, sign out every `silo_session_v1.<server_id>` slot whose `silo:<server_id>` connection row is missing.

### M2. Logout with an expired access token does not end the server session. Medium. Open.

This is wire-parity finding M1 in `s2-wire-parity.md`. It also bears on data hygiene, because the server keeps a session the device has forgotten.

### L1. Silo tokens are not registered with `LogRedactionManager`. Low. Open.

Plex tokens and server URLs are registered for log redaction (`lib/services/storage_service.dart:53`, `lib/services/plex_client.dart:554`). Silo tokens are not. No current log line carries one, so this is defence in depth. A future `appLogger.e(..., error: e)` with a response body in the error would not be scrubbed.

## Existing connections on upgrade

Nothing in `feat/tv-silo-sidebar..d0f61223d` removes a Plex, Jellyfin or Emby connection or its prefs. I checked as follows.

- `git diff feat/tv-silo-sidebar..HEAD -- lib` adds removal calls only for `SiloConnection` (`_removeSiloConnection`, the Silo loop in the prune, the sign-out helpers), plus the H1 fix.
- `lib/database` is unchanged in the range. There is no schema change or migration.
- The row parser change only adds the `silo` case and drops a Silo row that lacks its origin or server id (`lib/connection/connection_registry.dart:147-173`). Plex and Jellyfin rows parse as before.
- `CredentialVault._tokenKeyForKind('silo')` returns null, so the vault migration leaves Silo rows alone (`lib/services/credential_vault.dart:132-139`).
- Adding Silo binds to the active or target profile and writes one connection and one join row (`lib/screens/profile/silo_profile_screen.dart:127-171`). It does not touch other connections.
- `clearCredentials` now also removes `silo_session_v1.*`. It runs only inside `clearUserData`, which only the full Logout calls.

### What happened to the emulator's Plex sign-in

Measured from the app database's WAL (frames decoded by page, ids and kinds only). Since the checkpoint at Monday 00:08 the device went through four sign-ins: Silo `admin`, Plex `NotVeryPrivateAccount`, Silo `pintest`, then Silo `admin`. Each was removed in the same order, `profile_connections`, then `profiles`, then `connections`. That is exactly the order in `logoutAllProfiles`, and nothing else in the code deletes all three. The Plex sign-in used for lane 1 was removed by a profile-menu Logout before the second Silo sign-in. That Logout needs a confirm dialog, so a person ran it. S2 code did not remove it.

The Sunday-night loss at 00:08 cannot be traced from the device. The 00:08 checkpoint image already holds zero connections, profiles and cached rows, with 170 of its 214 pages free. The WAL from before that checkpoint is gone, and no Plex strings survive in the free pages. It predates S2, and I found nothing in the range that could cause it. A profile-menu Logout explains the same end state.
