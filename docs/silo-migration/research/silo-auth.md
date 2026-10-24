# Silo auth, connection, sign-in, session, profiles

Research notes for the Plezy Dart port. They describe what Silo's Android and Android TV apps put on the wire, so the Dart client can match it call for call.

Source root is `/home/mine/Desktop/silo-android/silo-android`. Paths are relative to it, with these prefixes.

- `S/` is `shared/src/commonMain/kotlin/org/siloserver/silo/`
- `SA/` is `shared/src/androidMain/kotlin/org/siloserver/silo/`
- `AS/` is `android-shared/src/androidMain/kotlin/org/siloserver/silo/common/`
- `TV/` is `androidTvApp/src/androidMain/kotlin/org/siloserver/silo/tv/`
- `PH/` is `androidApp/src/androidMain/kotlin/org/siloserver/silo/android/`

Live checks were unauthenticated GETs against `https://silo.ruleone.xyz` on 2026-10-11. They are marked "measured".

## 1. Wire reference

### 1.0 Conventions

- Every request carries `Content-Type: application/json` from the client default (`S/network/SiloHttpClientImpl.kt:96-98`).
- JSON decoding ignores unknown keys, is lenient, and coerces invalid enum input. Encoding includes defaults and omits nulls (`S/network/SiloHttpClientImpl.kt:17-23`).
- Timeouts are 10 s connect, 60 s request, and 60 s socket (`S/network/SiloHttpClientImpl.kt:84-94`).
- Every v2 error body is RFC 9457 problem JSON with `type`, `title`, `status`, `detail`, `instance`, and `errors[{location, code, detail}]` (`S/network/apiv2/ApiV2Models.kt:36-53`). The stable code is the last path segment of `type` (`S/network/apiv2/ApiV2Models.kt:44-45`). The app keeps `code` as the error string and `detail` as the message (`S/network/apiv2/ApiV2Call.kt:50-61`).
- `safeApiV2Call` returns a gate error before sending anything when the server is marked `UPDATE_REQUIRED` (`S/network/apiv2/ApiV2Call.kt:24-48`). That error has HTTP code `0`, error `update_server`, and a fixed message (`S/network/apiv2/ApiV2Gate.kt:23-38`, `:47`, `S/model/server/ServerContract.kt:28-29`).
- `requireAuthStatus(n)` treats any 2xx other than `n` as a failure (`S/network/api/AuthWireV2.kt:79-81`).

The "Auth" column uses these terms.

- **none** means `skipSiloAuth()`. No `Authorization` and no `X-Profile-*` headers are sent. The `X-Silo-*` device headers are still sent when the URL has the trusted server's origin (`S/network/AuthInterceptorImpl.kt:410-416`).
- **bearer** means `Authorization: Bearer <access>`, plus `X-Profile-Id` and `X-Profile-Token` when they are set (`S/network/AuthInterceptorImpl.kt:480-506`).
- **scope** means the request is pinned to a captured `AuthScopeSnapshot` (server, profile id, and profile token), whatever the active server is (`S/network/AuthInterceptorImpl.kt:451-474`).
- **fresh** means the bearer is refreshed before sending if it expires within 60 s (`S/network/AuthScopeSnapshot.kt:128-141`, `S/network/AuthInterceptorImpl.kt:25`, `:561-566`).
- **single** means no 401 refresh-and-retry (`S/network/AuthInterceptorImpl.kt:551-552`, `:593`).

### 1.1 Server discovery and contract

| Method | Path | Request | Response fields used | Auth | Source |
|---|---|---|---|---|---|
| GET | `/api/v2/system/info` | none | `server_version`, `api_major` (must be 2), `contract_digest`, `links.openapi`, `links.capabilities` | none. The "fresh" probe adds `Cache-Control: no-cache, no-store` and 6 s timeouts | `S/network/apiv2/ApiV2Probe.kt:72-133`, `S/network/apiv2/ApiV2Models.kt:21-32` |
| GET | `/api/v2/system/identity` | none | `server_id` (trimmed; empty means unreachable) | none, single, 8 s overall | `S/network/api/ServerIdentityApi.kt:113-139`, `:159-163` |
| GET | `/api/v2/system/connections` | none | `state` (must be `available`), `allowed` (must not be false), `server_id`, `endpoints[]` with `kind` (`public` or `provider`), `url`, `provider`, `display_name`, `state` | scope, single, 8 s overall | `S/network/api/ServerIdentityApi.kt:67-109`, `:141-156` |
| GET | `/api/v2/system/setup` | none | `needs_setup` | none | `S/network/api/AuthApi.kt:57-77`, `S/network/apiv2/ApiV2Models.kt:57-59` |
| GET | `/api/v2/auth/signup` | none | `enabled` | none | `S/network/api/AuthApi.kt:79-87`, `S/model/auth/AuthModels.kt:71-74` |
| GET | `/api/v2/theme/branding` | none | `server_name` (used as the registry display name), plus `login_subtitle`, `accent_color`, `mark_url`, `wordmark_url` | none | `S/network/api/BrandingApi.kt:15-43`, `S/repository/AuthRepository.kt:446-463` |
| GET | `/health` | none | `status`, `server_name`, `server_id` | none, 6 s timeouts | `S/network/api/HealthApi.kt:20-39` |

Contract verdict rules are in `S/network/apiv2/ApiV2Probe.kt:46-65`.

- A 200 with `api_major == 2` is V2.
- A 404 whose body is exactly `404 page not found`, with at most one trailing `\n`, means the server must be updated (`S/network/apiv2/ApiV2Probe.kt:139-147`).
- Every other outcome is a non-verdict failure. That covers other 404 bodies, 401/403, 429, 5xx, a malformed 200, a timeout, and a connect error (`S/network/apiv2/ApiV2Probe.kt:106-120`).

The identity probe uses the same legacy-404 test to report `UnsupportedServer`. Any other failure reports `Unreachable` (`S/network/api/ServerIdentityApi.kt:123-138`).

Measured on the test server:

- `/api/v2/system/identity` returned `{"server_id":"2b68c785-…"}`.
- `/api/v2/system/info` returned `api_major: 2` and `links.identity`.
- `/api/v2/system/setup` returned `needs_setup: false` plus an extra `wizard_completed: true`.
- `/api/v2/auth/signup` returned `enabled: true`.
- `/api/v2/theme/branding` returned `server_name: "Silo"`.
- `/health` returned the web app's HTML with a 200 (`text/html`). That makes the health fallback decode fail on this deployment.

### 1.2 Password, signup, setup, invitation, logout, account

| Method | Path | Request body | Response fields used | Expected | Auth | Source |
|---|---|---|---|---|---|---|
| POST | `/api/v2/auth/login` | `username`, `password`, `provider` (omitted when null; the apps never send it) | `access_token`, `refresh_token`, `expires_in` (seconds), `user{id, username, email, role, download_allowed, impersonation?}` | 200 | none, single | `S/network/api/AuthApi.kt:27-32`, `S/model/auth/AuthModels.kt:6-11`, `S/network/api/AuthWireV2.kt:11-41`, `S/model/auth/ExternalSignInModels.kt:9` |
| POST | `/api/v2/auth/refresh` | `refresh_token` | `access_token`, `refresh_token`, `expires_in` | 200 | no auth headers (see 4.3) | `S/network/AuthInterceptorImpl.kt:199-202`, `:327-330`, `S/model/auth/AuthModels.kt:21-31` |
| POST | `/api/v2/auth/signup` | `username`, `email`, `password`, `invite_code` | token pair, as for login | 201 | none, single | `S/network/api/AuthApi.kt:41-46`, `S/model/auth/AuthModels.kt:63-69` |
| POST | `/api/v2/auth/setup` | `username`, `email`, `password` | token pair, as for login | 201 | none, single | `S/network/api/AuthApi.kt:48-55`, `S/model/auth/AuthModels.kt:51-56` |
| GET | `/api/v2/invitations/capabilities` | none | `revision`, `state`, `default_profile`, `profileless` | 200 | none | `S/network/api/AuthApi.kt:104-108`, `S/model/auth/InvitationModels.kt:25-31` |
| GET | `/api/v2/invitations/{token}` | none (token is path-encoded) | `email`, `inviter_name?`, `server_name`, `expires_at`, `show_tour`, `acceptance_available` | 200 | none | `S/network/api/AuthApi.kt:93-102`, `S/model/auth/InvitationModels.kt:10-18` |
| POST | `/api/v2/invitations/{token}/accept` | `password` | `status` (must be `accepted`), `login_status` (`signed_in` with `tokens`, or `sign_in_required` without them), `username`, `tokens?` | 201 | none, single | `S/network/api/AuthApi.kt:110-117`, `S/network/api/AuthWireV2.kt:83-96` |
| GET | `/api/v2/account/me` | none | `id` (string), `username`, `email`, `role`, `download_allowed` (default false), `impersonation{active, impersonator_user_id, impersonator_username}?` | 2xx | bearer. The scoped variant is scope and fresh | `S/network/api/AuthApi.kt:119-134`, `S/network/apiv2/ApiV2Models.kt:63-78` |
| POST | `/api/v2/auth/logout` | none | none | 204 | bearer | `S/network/api/AuthApi.kt:136-138` |

`user.id` decodes from either a string or a number (`S/network/api/AuthWireV2.kt:13`, `S/model/auth/AuthModels.kt:35`).

### 1.3 Device sign-in (TV code) and its approval

| Method | Path | Request body | Response fields used | Expected | Auth | Source |
|---|---|---|---|---|---|---|
| GET | `/api/v2/auth/device/capability` | none | `revision`, `state`, `remote_playback_handoff`, `protocol_versions[]`, `cancel`, `opened_signal`. Every flag reads false unless `state == "available"` | 200 | none | `S/network/api/DeviceLoginApi.kt:198-208`, `S/network/api/AuthWireV2.kt:61-77` |
| POST | `/api/v2/auth/device/start` | `device_name`, `device_platform`. Remote playback also sends `client_purpose: "remote_playback"` and `temporary: true` | `device_code` (secret, never shown), `user_code`, `match_code`, `verification_uri`, `verification_uri_complete` (QR payload), `expires_at` (RFC 3339), `expires_in` (s), `interval` (s), `device_name`, `device_platform` | 201 | none, single | `S/network/api/DeviceLoginApi.kt:152-184`, `:222-240`, `S/model/auth/DeviceLoginModels.kt:6-33` |
| POST | `/api/v2/auth/device/poll` | `device_code` | `status`, `poll_after` (s), `profile_id`, `profile_token`, `temporary`, `tokens?` (token pair), `session_expires_at?`, `opened` (default false), `expires_at?` | 200 | none, single | `S/network/api/DeviceLoginApi.kt:164-196`, `S/network/api/AuthWireV2.kt:43-59` |
| POST | `/api/v2/auth/device/cancel` | `device_code` | `status` | 200 | none, single | `S/network/api/DeviceLoginApi.kt:210-220` |
| GET | `/api/v2/auth/device?token=&code=` | none (blank parameters are omitted) | `status`, `user_code`, `match_code`, `device_name`, `device_platform`, `ip_address_hint`, `expires_at`, `requested_at`, `client_purpose`, `temporary`, `server_id`, `server_name` | 200 | none. The scoped variant sends only `code` and still sets `skipSiloAuth` | `S/network/api/DeviceLoginApi.kt:242-251`, `:277-286`, `S/model/auth/DeviceLoginModels.kt:73-90` |
| POST | `/api/v2/auth/device/approve` | `token?`, `code?` (the scoped variant sends `code` only) | `status` | 200 | bearer or scope, fresh | `S/network/api/DeviceLoginApi.kt:253-263`, `:288-299` |
| POST | `/api/v2/auth/device/deny` | `token?`, `code?` | `status` | 200 | bearer or scope, fresh | `S/network/api/DeviceLoginApi.kt:265-275`, `:319-330` |
| POST | `/api/v2/auth/device/approve-handoff` | `code` | `status` | 200 | scope | `S/network/api/DeviceLoginApi.kt:301-310` |

Poll `status` values are `pending`, `approved`, `denied`, `expired`, `consumed`, and `canceled`. Anything else is Unknown (`S/model/auth/DeviceLoginModels.kt:123-136`).

Tokens arrive only on the first `approved` reply, because the server consumes the record atomically (`S/model/auth/DeviceLoginModels.kt:40-47`).

`DevicePollV2` declares `poll_after`, `profile_id`, `profile_token`, and `temporary` as non-null with no default (`S/network/api/AuthWireV2.kt:43-52`). A strict decoder would fail on a pending reply that leaves them out. Guess: the server always sends them.

Measured on the test server, the capability returned `state: "available"`, `cancel: true`, `opened_signal: true`, and `protocol_versions: [2]`.

The code display rules are in `S/model/auth/DeviceCodeFormat.kt:9-45`.

- Codes have 8 characters. Current servers issue digits and older ones issue letters and digits.
- Display groups them 4+4 with a space.
- `normalize` keeps letters and digits only and uppercases them.
- The activate text is `verification_uri` with a leading `https://` and trailing `/` removed. When `verification_uri` is blank, it falls back to `verification_uri_complete` without its query.

### 1.4 External sign-in (OIDC, LDAP, network identity)

| Method | Path | Request body | Response fields used | Expected | Auth | Source |
|---|---|---|---|---|---|---|
| GET | `/api/v2/auth/providers` | none | `password_login` (default true), `items[]` with `id`, `display_name`, `mode` (`credentials`, `oauth`, `network`), `default`, `icon_url`, `installation_id`, `native_start_path`, `network_sign_in_path`, `network_identity{display_name, username}` | 2xx | none, not gated | `S/network/api/ExternalSignInApi.kt:123-126`, `:287-372` |
| GET | `/api/v2/auth/oauth/capabilities` | none | `state`, `available`, `native`, `linking`, `select_account` | 2xx | none, not gated | `S/network/api/ExternalSignInApi.kt:128-131`, `:374-391` |
| POST | `/api/v2/auth/oauth/complete` | `code`, `code_verifier` | token pair | 200 | none, single | `S/network/api/ExternalSignInApi.kt:138-148`, `:413-419` |
| POST | `/api/v2/auth/network/{id}/sign-in` (taken from `network_sign_in_path`) | `{}` (required; the server answers 415 without a JSON body) | token pair | 200 | none, single | `S/network/api/ExternalSignInApi.kt:150-159` |
| GET | `/api/v2/auth/external-sign-in/capabilities` | none | `state`, `available`, `identities`, `credentials_linking`, `network_sign_in`, `network_link_keeps_password` | 2xx | scope | `S/network/api/ExternalSignInApi.kt:133-136`, `:393-411` |
| GET | `/api/v2/account/identities` | none | `items[]{id, installation_id, provider_id, provider_name, username, email, display_name, linked_at, last_sign_in_at}`, `can_unlink?` | 2xx | scope | `S/network/api/ExternalSignInApi.kt:161-164`, `:421-450` |
| DELETE | `/api/v2/account/identities/{id}` | none | none | 2xx | scope, single | `S/network/api/ExternalSignInApi.kt:166-171` |
| POST | `/api/v2/account/identities/link-ticket` | `installation_id`, `password` | `ticket`, `expires_at` | 200 | scope, fresh, single | `S/network/api/ExternalSignInApi.kt:173-187` |
| POST | `/api/v2/account/identities/link-complete` | `code`, `code_verifier` | none | 2xx | scope, fresh, single | `S/network/api/ExternalSignInApi.kt:189-196` |
| POST | `/api/v2/account/identities/link-credentials` | `installation_id`, `password`, `username`, `directory_password` | an identity | 201 | scope, fresh, single | `S/network/api/ExternalSignInApi.kt:198-219` |
| POST | `/api/v2/account/identities/link-network` | `installation_id`, `password` | an identity | 201 | scope, fresh, single | `S/network/api/ExternalSignInApi.kt:221-233` |

The app keeps only the base-relative route from `native_start_path` and `network_sign_in_path`. Any prefix before `/api/v2/` is dropped, and the remainder must match the regexes at `S/network/api/ExternalSignInApi.kt:351-354`, or the path becomes null (`:332-349`). A relative `icon_url` resolves against the server URL that listed it (`:357-361`). A 422 is split into `wrong_password` (`body.password`) and `directory_refused` (`body.directory_password`) by the problem's `errors[].location` (`:274-283`).

Measured on the test server:

- Providers returned only `local` (`mode: credentials`) with `password_login: true`.
- OAuth capabilities returned `native: false`, `linking: true`, and `select_account: true`.

### 1.5 Profiles

| Method | Path | Request body | Response fields used | Expected | Auth | Source |
|---|---|---|---|---|---|---|
| GET | `/api/v2/profiles` | none | `items[]` of profile (see below) | 200 | scope (the current scope; profile headers sent when set) | `S/network/api/ProfileApi.kt:71-73` |
| POST | `/api/v2/profiles` | profile fields, nulls stripped, `allowed_library_ids` as strings | profile | 201 | scope, single; with manage mode on, the scope carries the primary profile's id and token | `S/network/api/ProfileApi.kt:75-88`, `S/model/profile/ProfileModels.kt:54-71` |
| PATCH | `/api/v2/profiles/{id}` | omitted means unchanged. On clearable members an explicit `null` clears | profile | 200 | scope, single, manage-mode aware | `S/network/api/ProfileApi.kt:97-108`, `:173-200` |
| DELETE | `/api/v2/profiles/{id}` | none | none | 204 | scope, single, manage-mode aware | `S/network/api/ProfileApi.kt:110-114` |
| POST | `/api/v2/profiles/{id}/verify-pin` | `pin` | `valid`, `profile_token?`, `expires_at?` | 200 | scope with profile id and token removed | `S/network/api/ProfileApi.kt:116-129`, `S/model/profile/ProfileModels.kt:98-108` |

The profile object has `id`, `name`, `avatar`, `avatar_url` (presigned, about 900 s), and `avatar_source`. It also has `has_pin`, `is_child`, `is_primary`, `max_content_rating`, `quality_preference`, `language`, `preferred_metadata_language`, `subtitle_language`, and `subtitle_mode`. Then come `auto_skip_intro`, `auto_skip_credits`, `auto_skip_recap`, `auto_play_next_preview`, `show_forced_subtitles`, `library_restrictions_enabled`, `allowed_library_ids` (strings), `max_playback_quality`, `created_at`, and `updated_at` (`S/network/apiv2/ApiV2Models.kt:89-114`, `S/model/profile/ProfileModels.kt:11-21`).

Every profile call sets `requireSiloAuth`. The request then never goes out without a bearer (`S/network/api/ProfileApi.kt:64`, `S/network/AuthInterceptorImpl.kt:455-461`).

A wrong PIN comes back as 200 with `valid: false`. The app enters a profile only when `valid` is true and `profile_token` is non-blank (`S/model/profile/ProfileModels.kt:124-125`, `TV/ui/screens/profiles/TvProfileSelectionViewModel.kt:323-338`).

## 2. Server connection

### 2.1 Address entry and candidate URLs

TV (`TV/ui/screens/auth/TvServerSetupViewModel.kt:324-337`):

1. Trim the input and strip trailing `/`.
2. If it starts with `http://` or `https://`, it is the only candidate.
3. Otherwise try `https://<input>` first, then `http://<input>`.
4. Each candidate goes through `normalizeUrl`.

Phone (`PH/ui/screens/auth/ServerSetupViewModel.kt:320-412`):

- A separate port field and a scheme picker (Auto, HTTP, HTTPS) feed the candidate list.
- In Auto mode, with no scheme and no port typed, the candidates are `https://host`, then `http://host`, then `http://host:8090`.
- Ports must be 1 to 65535.
- The path is preserved.
- An IPv6 host is bracketed.

`normalizeUrl` trims the input and strips trailing `/`. It lowercases the scheme and the authority and keeps the path as typed (`SA/network/AndroidServerRegistry.kt:535-547`).

The TV pre-fills the field with the saved URL unless it is the placeholder `http://localhost:8090` (`TV/ui/screens/auth/TvServerSetupViewModel.kt:97-112`).

### 2.2 Probe sequence per candidate

This runs in order and stops at the first success (`TV/ui/screens/auth/TvServerSetupViewModel.kt:249-312`).

1. `GET {candidate}/api/v2/system/info`, bounded to 3 s by `withTimeoutOrNull` (`S/repository/AuthRepository.kt:37`, `:533-539`). Only an "update server" result stops the flow, with `ServerContract.UPDATE_REQUIRED_MESSAGE`. Other outcomes are ignored.
2. `GET {candidate}/api/v2/system/setup`. If `needs_setup` is true, the destination is Setup. An error or network failure moves on to the next candidate. On the last candidate it reports "Could not reach server: …" or "Network error. Check the URL and try again."
3. `GET {candidate}/api/v2/auth/signup`. `enabled` decides whether Login offers "Create account". Any failure means false.
4. A successful setup call counts as proof of V2 and is recorded as such (`S/repository/AuthRepository.kt:581-592`).

The TV connect flow never calls `/system/identity`. The identity is probed later by the login screen and by pairing (`TV/ui/screens/auth/TvLoginViewModel.kt:836-845`, `S/repository/ServerIdentityRepository.kt:30-44`).

### 2.3 Cleartext consent

The connect screen (`TV/ui/screens/auth/TvServerSetupViewModel.kt:178-239`):

1. If the chosen URL is `http://`, compute `cleartextOrigin`. That is `http://host[:port]` with the host lowercased and port 80 dropped (`AS/network/CleartextConsentStore.kt:55-61`).
2. If the origin cannot be computed, show "Could not safely identify this HTTP server."
3. If it is already approved, continue.
4. Otherwise show a confirm prompt. On confirm, `approve(origin)` stores the SHA-256 digest of the origin in DataStore `silo_cleartext_consent` (`AS/network/CleartextConsentStore.kt:33-50`). Then continue.

Enforcement in the HTTP client (`S/network/AuthInterceptorImpl.kt:398-407`, `S/network/CleartextOriginConsent.kt:16-33`):

- Any request to an unapproved `http` or `ws` origin is aborted before sending with `CleartextOriginNotApprovedException`, and its credential headers are stripped.
- The one exception is a GET marked `skipSiloAuth`. That lets candidate probes reach a server before consent.
- `skipSiloAuth` POSTs, such as login and device start, are still blocked, because they carry credentials in the body.

At launch, an unapproved cleartext active server routes back to ServerSetup (`TV/MainTvActivity.kt:383-388`).

### 2.4 Origin checks

`httpOrigin` accepts only `http` and `https` (with `ws` and `wss` mapped to them). It rejects user-info, whitespace, control characters, `\`, and malformed IPv6. It lowercases the host (`S/network/HttpOriginPolicy.kt:11-153`).

`isSameHttpOrigin` compares scheme, host, and port (`S/network/HttpOriginPolicy.kt:37-41`). The plugin attaches Silo credentials only to requests whose origin equals the trusted server's origin. Otherwise it strips `Authorization`, `X-Profile-*`, and every `X-Silo-*` header (`S/network/AuthInterceptorImpl.kt:409-426`, `:927-934`).

Relative `/api/...` and `/health` URLs are rebased onto the active server URL. A websocket's scheme is restored to `ws` or `wss` afterwards (`S/network/AuthInterceptorImpl.kt:390-396`, `:913-971`).

### 2.5 Server registry

- Each entry stores `id`, `url`, `fetchedName`, `userOverrideName`, `profileId`, `lastUsedAtEpochMs`, `contract` (`UNKNOWN`, `V2`, `UPDATE_REQUIRED`), and `verifiedServerId` (`S/model/server/ServerEntry.kt:19-42`, `S/model/server/ServerContract.kt:15-26`).
- `displayName` is the override name, then the fetched name, then the host, then the URL (`S/model/server/ServerEntry.kt:37-42`).
- `id` is the unpadded base64url of the normalized URL. The same URL always gets the same id, so re-adding a server updates it in place (`SA/network/AndroidServerRegistry.kt:70-93`, `:411-414`).
- State is persisted as JSON under key `server_registry.v1` in EncryptedSharedPreferences `silo_secure_tokens` (AES256-SIV keys, AES256-GCM values) (`SA/network/AndroidServerRegistry.kt:403`, `SA/network/SecureSharedPrefs.kt:14-28`).
- When no active id is saved, the active entry falls back to the most recently used one (`SA/network/AndroidServerRegistry.kt:312-319`).
- `remove` deletes every `<serverId>.*` key, then picks the next most recent server, inside a `SERVER_REMOVE` identity transition (`SA/network/AndroidServerRegistry.kt:146-182`).
- `switchTo` bumps `lastUsedAt` inside a `SERVER_SWITCH` transition (`SA/network/AndroidServerRegistry.kt:193-205`).

`AuthRepository.setServerUrl` performs `addOrUpdate`, then `switchTo`, then `tokenManager.switchActiveServer`. It records the contract the probe already learned, then refreshes the display name (`S/repository/AuthRepository.kt:286-297`). The name comes from `/api/v2/theme/branding` `server_name`. `/health` `server_name` is the fallback, and only after a branding 404 (`S/repository/AuthRepository.kt:446-463`).

At launch, a stored contract other than V2 is re-probed with a 3 s bound before routing (`S/repository/AuthRepository.kt:500-503`, `TV/MainTvActivity.kt:375-381`).

`ServerIdentityRepository.identityOf` returns the recorded `verifiedServerId`, or probes `/system/identity` when it has none or when asked to refresh. An unreachable server keeps the recorded value. An unsupported server clears it (`S/repository/ServerIdentityRepository.kt:30-44`).

## 3. Sign-in flows

### 3.0 TV launch routing

`resolveStartDestination` (`TV/MainTvActivity.kt:358-421`):

1. No active server goes to ServerSetup.
2. Re-probe the contract (3 s bound). Refresh the server name in the background.
3. An unapproved cleartext server goes to ServerSetup.
4. No access token goes to Login.
5. No profile id goes to ProfileSelection.
6. A remote-playback overlay goes to Main.
7. If the "Profile Selection" launch setting requires it, clear the active profile (see 5.4) and go to ProfileSelection.
8. Otherwise go to Main.

After the connect screen, Login goes straight to Profiles when the server already holds an access token (`TV/ui/screens/auth/TvServerSetupViewModel.kt:218-239`, `TV/di/AndroidTvModule.kt:403`).

A successful login goes to ProfileSelection and pops Login (`TV/ui/navigation/TvAppNavigation.kt:909-911`). `sessionExpired` routes to `Login(sessionExpired = true)` and clears the back stack (`TV/ui/navigation/TvAppNavigation.kt:739-748`).

### 3.1 TV login screen: two flows race

`TvLoginViewModel` starts the device code as soon as the screen opens and offers the password form beside it (`TV/ui/screens/auth/TvLoginViewModel.kt:225-250`, `:318-321`). Whichever flow finishes first wins through the `authCompleted` flag (`:797-801`).

On open (`:824-879`):

1. Show the server name, host, and `<url>/activate`.
2. Read the sign-in options. `GET /api/v2/auth/providers` and `GET /api/v2/auth/oauth/capabilities` run in parallel (`S/repository/ExternalSignInRepository.kt:35-49`). A 5xx, 429, or network failure leaves the options unknown and changes nothing. Any other error means "password form only".
3. The password form shows if `password_login` is true or any `credentials` provider exists (`S/model/auth/ExternalSignInModels.kt:130-151`).
4. A `network` provider with a sign-in path adds a "Continue as …" button.
5. The options are read again on `onStart` after a stop, on "Try again", and after a `local_login_disabled` refusal (`TV/ui/screens/auth/TvLoginViewModel.kt:451`, `:479-480`, `:509`).

### 3.2 TV password login

1. Validate locally. "Username required" and "Password required" are the only checks (`TV/ui/screens/auth/TvLoginViewModel.kt:326-340`).
2. Capture the session expectation (generation, server id, server URL). If it is null, retry up to 3 attempts, 250 ms apart (`:808-815`).
3. `POST {serverUrl}/api/v2/auth/login` with `{username, password}`, through `loginForTokens`. The tokens are not saved yet. The result is discarded as `identity_changed` if the expectation moved during the call (`S/repository/AuthRepository.kt:164-180`).
4. On success, claim `authCompleted`. Then `replaceAccountSession(expectedIdentity, access, refresh, expiresIn)` commits atomically. No profile is set (`TV/ui/screens/auth/TvLoginViewModel.kt:392-404`).
5. `onSessionCommitted()` re-probes the contract in the background (`S/repository/AuthRepository.kt:107-122`).
6. Check that the generation is exactly `expected + 1`, or report IdentityChanged (`TV/ui/screens/auth/TvLoginViewModel.kt:431-435`).
7. Withdraw the device code (cancel), then set `loginSuccess`, which routes to ProfileSelection (`:436-437`, `:748-751`).

Error mapping is by problem code first, then status (`S/model/auth/ExternalSignInModels.kt:231-245`).

- `local_login_disabled`, `not_permitted`, `password_expired`, `provider_unavailable`, `email_in_use`, `identity_linked_elsewhere`, and `account_required` each map to their own case.
- `rate_limited` or 429 means rate limited.
- 401 means invalid credentials.
- 403 means account disabled.
- 503 means provider unavailable.
- Anything else shows the server's `detail`.
- A network error shows the generic Network error (`TV/ui/screens/auth/TvLoginViewModel.kt:46-62`, `:439-459`).

If the save fails without committing, the device code keeps running. An approval that arrived during the save is held and used then (`:411-427`, `:754-764`).

### 3.3 TV device code (QR) sign-in

This is driven by `DeviceSignInMachine` (`S/repository/DeviceSignInMachine.kt:106-399`) and `DeviceLoginPoller` (`S/repository/DeviceLoginRepository.kt:92-189`).

1. `GET {url}/api/v2/auth/device/capability` once. If the capability says device login is unavailable, the screen goes password-only (`S/repository/DeviceSignInMachine.kt:193-198`).
2. `POST {url}/api/v2/auth/device/start` with `device_name` and `device_platform: "android-tv"`. `device_name` is `Build.MODEL`, or "Android TV" (`TV/ui/screens/auth/TvLoginViewModel.kt:531-543`, `:920`).
   - 404 or 501 on start means no device sign-in.
   - 410, 426, or the gate means update required.
   - Another 4xx means failed.
   - A network error, 5xx, 408, or 429 is retried with backoff 1 s, 2 s, 4 s, up to 30 s (`S/repository/DeviceSignInMachine.kt:247-287`, `S/repository/DeviceLoginRepository.kt:50-76`).
3. Show the code. `user_code` is shown grouped, the QR encodes `verification_uri_complete`, and the activate text is built from `verification_uri` (`TV/ui/screens/auth/TvLoginViewModel.kt:881-886`).
4. Poll at once, then every `interval` seconds. A pending reply's `poll_after` replaces the interval. The minimum is 1 s (`S/repository/DeviceLoginRepository.kt:141`, `:170`).
   - A pending reply with `opened: true` switches the status to "Opened".
   - A pending reply's `expires_at` can only extend the local deadline. It is converted through the start reply's own `expires_at` and `expires_in` pair to cancel out clock skew (`:127-135`, `:163-172`).
   - Every wait is clamped to the deadline (`:187-188`).
5. Poll outcomes:
   - `approved` with both tokens wins.
   - `approved` without tokens, or an unknown status, means Failed.
   - `denied` means Denied.
   - `expired`, `consumed`, `canceled`, 404, or another 4xx means Gone, and the code is replaced with a new start.
   - 410 or 426 means update required.
   - A network error, 5xx, or 429 backs off from the interval, doubling up to 30 s (`S/repository/DeviceLoginRepository.kt:148-185`, `S/repository/DeviceSignInMachine.kt:291-341`).
6. If the local deadline passes while the server may still hold the code, cancel it first with `POST /api/v2/auth/device/cancel`. That call is bounded to 5 s and is not cancellable. The cancel is skipped only when the capability says `cancel: false`. Then start a new code and mark it "New code" for 5 s (`S/repository/DeviceSignInMachine.kt:352-379`, `TV/ui/screens/auth/TvLoginViewModel.kt:639-648`).
7. UI thresholds: "Can't reach" after 10 s of failing starts or 30 s of failing polls. "Too many requests" after 60 s of 429s. "Paused" after 60 minutes of renewals with no activity (`S/repository/DeviceSignInMachine.kt:65-76`).
8. On approval, check the expectation is unchanged, cancel any running password attempt, and run `replaceAccountSession(expectedIdentity, access, refresh, expires_in ?: 0)`. Then `onSessionCommitted()`, then the generation check (`TV/ui/screens/auth/TvLoginViewModel.kt:656-708`). The poll's `profile_id` and `profile_token` are not used on this path.
9. Show "Signed in as {user.username}" for 1 s, then set `loginSuccess` (`:709-715`).

Lifecycle (`TV/ui/screens/auth/TvLoginViewModel.kt:469-498`, `:817-822`, `:893-899`):

- `onStop` stops polling but lets a poll that is already in flight finish.
- `onStart` polls at once and renews the code if it expired.
- Leaving the screen, "Change server", "Try again", or a password win withdraws the code with cancel.

### 3.4 TV "Continue as …" (network identity)

1. This is offered only when `/auth/providers` lists a `mode: network` provider with a valid `network_sign_in_path`. The server lists one only to requests that came through that network (`S/model/auth/ExternalSignInModels.kt:107-119`).
2. `POST {serverUrl}{network_sign_in_path}` with body `{}`. It is never retried (`S/network/api/ExternalSignInApi.kt:150-159`).
3. The rest matches 3.2 steps 4 to 7 (`TV/ui/screens/auth/TvLoginViewModel.kt:348-357`).

Error mapping (`S/model/auth/ExternalSignInModels.kt:284-297`):

- `network_identity_required`, `not_permitted`, `account_required`, `email_in_use`, and `identity_linked_elsewhere` each map to their own case.
- `permission_denied` means account disabled.
- `provider_unavailable` or 503 means provider unavailable.
- `rate_limited` or 429 means rate limited.
- `not_found` or 404 means the provider is gone.

### 3.5 First-run setup (create admin)

TV and phone (`TV/ui/screens/auth/TvSetupViewModel.kt:48-92`, `S/repository/AuthRepository.kt:129-132`, `:186-188`):

1. Reached when `/system/setup` says `needs_setup: true`.
2. Local validation requires a username, an email containing `@`, and a password of at least 8 characters.
3. `POST {serverUrl}/api/v2/auth/setup` with `{username, email, password}`. The expected status is 201.
4. `persistSession` runs `replaceAccountSession` with the captured expectation, then `onSessionCommitted`, then the generation check (`S/repository/AuthRepository.kt:60-89`).

### 3.6 Signup with invite code

TV and phone (`TV/ui/screens/auth/TvSignupViewModel.kt:56-103`):

1. Offered from Login when `/auth/signup` reported `enabled: true`.
2. Validation is as for setup, plus a required invite code.
3. `POST {serverUrl}/api/v2/auth/signup` with `{username, email, password, invite_code}`. The expected status is 201. The session is saved as in setup.
4. 409 shows "Username or email already in use". 403 shows "Invalid invite code". Otherwise the server's `detail` is shown.

### 3.7 Emailed invitation claim (phone only)

`S/repository/AuthRepository.kt:201-243`, `PH/ui/screens/auth/InviteClaimViewModel.kt:85`, `:138-182`:

1. `GET {url}/api/v2/invitations/capabilities`. Continue only if `state == "available"` and (`default_profile` or `profileless`). Otherwise fail locally with 409 `capability_unavailable`.
2. `GET {url}/api/v2/invitations/{token}`. This shows the email, the server name, and the inviter.
3. The password must be at least 8 code points. Then `POST {url}/api/v2/invitations/{token}/accept` with `{password}`.
4. With `login_status: signed_in`, run `addOrUpdate(url)` and `persistSession` with the tokens. With `sign_in_required`, there are no tokens, and the user signs in normally.

### 3.8 Native OAuth (phone only, never on TV)

TVs never run this flow (`S/repository/ExternalSignInRepository.kt:17-22`).

`PH/auth/NativeSignIn.kt:16-95`, `:159-240`, `PH/auth/NativeSignInCoordinator.kt:173-264`, `PH/auth/NativeSignInPlatform.kt:25-70`:

1. Offered for `oauth` providers that have a native start path, and only when OAuth capabilities say `available` and `native`.
2. Probe `/system/identity` with refresh to get the verified server id (`PH/ui/screens/auth/LoginViewModel.kt:228-252`).
3. Generate the verifier (32 random bytes, unpadded base64url) and `app_state` the same way. The challenge is `BASE64URL(SHA256(verifier))`.
4. Open the system browser at `{savedBase}{native_start_path}?code_challenge=…&code_challenge_method=S256&app_state=…`. Add `&prompt=select_account` and `&link_ticket=…` when they apply.
5. Persist the pending flow on disk, encrypted, for 10 minutes.
6. The callback is `org.siloserver.silo:/auth/callback?code=&state=&server=&iss=` (or `error=`). Checks are applied in order.
   - The callback must be within 10 minutes.
   - `state` must match in constant time.
   - `iss` must equal the saved base's origin.
   - `server` must equal the verified server id.
7. `POST {savedBase}/api/v2/auth/oauth/complete` with `{code, code_verifier}`. This runs only while the saved server's origin and `loginSessionId` are unchanged. The session then commits as in a password sign-in.

### 3.9 Phone approving a TV (and TV "Pair a device")

This uses the shared `DevicePairingViewModel`. The TV hosts the same view model in `TvPairDeviceScreen` to approve another device (`TV/ui/screens/auth/TvPairDeviceScreen.kt:56-65`).

1. Input comes from a `silo://device?token=` link, a `silo://device?server=` link, or a typed code. Typed codes are normalized and limited to 8 characters (`S/viewmodel/DevicePairingViewModel.kt:221`, `:261-270`).
2. The server choices are saved servers that hold an access token, the active one first (`S/network/ServerRegistry.kt:88-93`). Each approval runs in a profileless scope for that server (`S/network/AuthScopeSnapshot.kt:75-82`, `S/viewmodel/DevicePairingViewModel.kt:63-72`).
3. Read the account to name it on the card with `GET /api/v2/account/me` (scope, fresh) (`S/network/api/AuthApi.kt:127-134`). Approval is refused unless the account is confirmed (`S/viewmodel/DevicePairingViewModel.kt:411-412`).
4. `GET /api/v2/auth/device?code=` (scoped) or `?token=`. This shows the device name, platform, IP hint, match code, and server name.
5. `POST /api/v2/auth/device/approve` or `/deny` with `{code}` (scoped) or `{token, code}` (`S/viewmodel/DevicePairingViewModel.kt:495-509`).
6. After approving, look the code up again every 3 s, up to 40 times. `consumed` means the TV signed in. `canceled`, `expired`, and `denied` are reported as such. Otherwise the follow times out (`S/viewmodel/DevicePairingViewModel.kt:458-478`, `:571-572`).

### 3.10 LAN companion pairing (TLS-PSK)

- **Discovery.** The TV advertises NSD service `_silopair._tcp` (`S/pairing/PairingProtocol.kt:8-14`). The TXT record carries `v` (1), `name`, `id`, `sid` (a fresh UUID on every start), and `st` (`setup` or `login`). In `login` mode it adds `srv`, the server's verified identity (`AS/pairing/TvPairingAdvertiser.kt:191-206`).
- **Rollout gate.** The TV login screen advertises `st=login` only when `advertisesSignIn` is on. It defaults to false and is "debug builds only" (`TV/ui/screens/auth/TvLoginViewModel.kt:263-272`).
- **Transport.** TLS with a fixed PSK `silo-companion-pairing-v1` and identity `silo-pairing`. Suites are `TLS_PSK_WITH_AES_128_GCM_SHA256` (TLS 1.2) and `TLS_AES_128_GCM_SHA256` (TLS 1.3). The handshake times out after 10 s (`AS/pairing/TlsPskPairingTransport.kt:34-44`, `:142-175`, `:197-225`).
- **Framing.** A 4-byte big-endian length, then JSON, at most 1 MiB per frame (`S/pairing/PairingFrame.kt:5-26`, `:50-66`).
- **Messages.** Every message has `type` and `v`.
  - `hello` (TV to phone) carries `tvName`, `tvDeviceId`, `state`, and `supportedVersions`.
  - `pushServer` (phone to TV) carries `serverURL`, `serverName?`, `serverIdentity?`, and `endpoints?[{url, kind, provider?, displayName?}]`.
  - `deviceStarted` (TV) carries `serverURL`, `userCode`, and `matchCode`.
  - `serverResult` (TV) carries `serverURL`, `status` (`signedIn` or `failed`), and `error?`.
  - `done` and `cancel{reason}` close the session (`S/pairing/PairingMessage.kt:123-290`).
  - Tokens never travel over the LAN (`S/pairing/PairingMessage.kt:117-119`).
- **TV side, setup mode.**
  1. Ask the user to allow the pushed server.
  2. Resolve the target address. With an identity, `/system/identity` at the pushed URL must match, or another offered endpoint with the same identity is offered to the user. A mismatch fails with `identity_mismatch` (`AS/pairing/PairingReceiver.kt:631-660`).
  3. Run the device-login start-and-poll flow (3.3) at that URL and send `deviceStarted`.
  4. The phone approves through the server (3.9).
  5. Commit the tokens with `addOrUpdate`, then `replaceAccountSession`. The previous server is restored on failure.
  6. Send `serverResult` (`AS/pairing/PairingReceiver.kt:530-623`, `AS/pairing/PairingAuthPort.kt:48-110`).
- **Failure codes.** `auth_failed`, `denied`, `expired`, `unreachable`, `identity_mismatch`, and `update_required` (`S/pairing/PairingMessage.kt:51-79`).

## 4. Token model, refresh, and headers

### 4.1 Storage

Per-server keys in EncryptedSharedPreferences `silo_secure_tokens` are named `<serverId>.<key>` (`SA/network/EncryptedTokenManagerImpl.kt:823-834`, `SA/network/AndroidServerRegistry.kt:549-550`). The keys are listed below.

- `access_token`
- `refresh_token`
- `token_expiry_epoch_ms` (now plus `expires_in` × 1000)
- `token_lifetime_ms`
- `profile_id`
- `profile_token`
- `login_authority_id` (a UUID that is new on every sign-in and removed on sign-out)

The TV wires `EncryptedTokenManagerImpl` as the `TokenManager` (`TV/di/AndroidTvModule.kt:101-103`).

`replaceAccountSession` writes the registry active id, the entry's `profileId`, a new login id, both tokens, the expiry, the lifetime, and the profile id and token in one synchronous `commit()`. It does this inside an `ACCOUNT_REPLACE` transition. It throws `AccountSessionChangedException` if the generation moved since `captureAccountSessionExpectation` (`SA/network/EncryptedTokenManagerImpl.kt:174-243`, `SA/network/AndroidServerRegistry.kt:212-248`).

A refresh writes the two tokens, the expiry, and the lifetime with `apply()` (`SA/network/EncryptedTokenManagerImpl.kt:775-794`).

### 4.2 Proactive refresh

The margin is 60 s (`S/network/AuthInterceptorImpl.kt:25`). It is clamped to half the token's lifetime. An unknown lifetime means no proactive refresh. An expired token is always refreshed first (`S/network/ProactiveRefreshPolicy.kt:28-38`).

The check runs only for active-scope requests that carry a bearer and are not `/auth/login` or `/auth/refresh` (`S/network/AuthInterceptorImpl.kt:655-665`). Outcomes:

- A rejected refresh means the request is not sent. It fails with `CREDENTIALS_REPUDIATED` (`:693-698`).
- A transient failure means the old token is spent, and the 401 path will not refresh again over the network (`:712-716`, `:802`).

### 4.3 Refresh call and 401 handling

`refreshScopeOnce` (`S/network/AuthInterceptorImpl.kt:134-297`):

1. It runs under one mutex. If the stored token already differs from the one this request sent, another request refreshed it, so retry with the new token without a network call (`:155-166`).
2. `POST {trustedServerUrl}/api/v2/auth/refresh` with `{refresh_token}`, no `Authorization` header (`:199-202`, `:476-478`).
3. After the response, drop the result if the active server changed or the refresh token was cleared. The second check stops a logout race from signing the user back in (`:209-226`).
4. A 200 saves the rotated pair and its `expires_in` (`:228-236`).
5. Only 400, 401, or 403 invalidates the session. That means clearing the tokens and profile for this server and emitting `sessionExpired` (`:248`, `:285-288`, `:890-893`).
6. 5xx, network errors, and other statuses keep the session. A 503 whose problem code is `provider_unavailable` is reported separately (`:249-257`).

The 401 path (`S/network/AuthInterceptorImpl.kt:748-832`):

- A response 401 on the active scope triggers one refresh and exactly one retry with the new bearer.
- `/auth/login`, `/auth/refresh`, `single` requests, cross-origin requests, and requests whose active server changed in flight never refresh.

Pinned-scope requests refresh against their own scope. They never invalidate the active session, and a rejected refresh token is remembered so it is not tried again (`S/network/AuthInterceptorImpl.kt:311-371`, `:553-619`).

### 4.4 Required headers

`S/network/AuthInterceptorImpl.kt:836-861` and `:899-911`:

| Header | Value | When |
|---|---|---|
| `Authorization` | `Bearer <access_token>` | auth requests on the trusted origin |
| `X-Profile-Id` | selected profile id (string) | when set; removed for `verify-pin` |
| `X-Profile-Token` | token from `verify-pin` | when set (PIN-protected profile) |
| `X-Silo-Device-Id` | random UUID, persisted once in prefs `silo_device_metadata` / `device_id` | every same-origin request, including `skipSiloAuth` ones |
| `X-Silo-Device-Name` | `"<Build.MANUFACTURER> <Build.MODEL>"` (duplicates and blanks removed), or `Android Device` | same |
| `X-Silo-Device-Platform` | `android-tv` (TV) or `android` (phone) | same |
| `X-Silo-Client` | `Silo Android TV` or `Silo Android` | same, if not blank |
| `X-Silo-Client-Version` | package `versionName` | same, if not blank |
| `X-Silo-Client-Build` | CI build number; omitted when it is `"0"` (unstamped) | same, if not blank |
| `X-Silo-Client-Channel` | `internal`, `alpha`, `beta`, `production`, `sideload`, or `dev` | same, if not blank |
| `X-Silo-Client-Family` | `tv`, or `mobile`/`tablet` (smallest width of 600 dp or more means tablet), computed once per process | same, if not blank |

Sources for the device values are `AS/network/AndroidDeviceMetadataProvider.kt:30-90`, `AS/network/ClientBuildIdentity.kt:16-17`, `:54-63`, `TV/di/AndroidTvModule.kt:178-184`, and `PH/di/AndroidModule.kt:219-225`. The device-login `device_platform` body field uses the same `android-tv` value (`TV/ui/screens/auth/TvLoginViewModel.kt:536-538`).

### 4.5 Logout

TV Settings "Sign out" (`TV/ui/screens/settings/TvSettingsViewModel.kt:748-762`):

1. Flush pending device settings.
2. `POST /api/v2/auth/logout`, expecting 204. Whatever the result, the active server's slot is wiped (`signOutCurrentServer`): tokens, profile, and login id. The registry entry is kept with `profileId = null` (`S/repository/AuthRepository.kt:266-272`, `SA/network/EncryptedTokenManagerImpl.kt:474-483`, `SA/network/AndroidServerRegistry.kt:250-269`).
3. `clearProfile()`, then `clearTokens()` again.
4. Clear the per-profile caches (library prefs, overlay prefs, card presentation, seek interval).
5. Navigate to sign-in.

A user sign-out never emits `sessionExpired`. Only invalidation does (`S/network/TokenManager.kt:94-134`).

### 4.6 Identity transition barrier

Every identity change runs through `changing(kind)` (`S/network/IdentityTransitionBarrier.kt:13-24`, `:99-133`). The kinds are `SIGN_IN`, `ACCOUNT_REPLACE`, `SIGN_OUT`, `SERVER_SWITCH`, `SERVER_REMOVE`, `PROFILE_SWITCH`, `TEMPORARY_SCOPE_BEGIN`, and `TEMPORARY_SCOPE_END`.

The sequence is fixed:

1. Take the mutex.
2. Run every installed gate inline with `WILL_CHANGE`. These are privacy cleanups, such as downloads, notifications, watch party, and diagnostics (`S/repository/DownloadsRepository.kt:80`, `S/repository/NotificationsRepository.kt:195`).
3. Increment `generation`.
4. Run the mutation.
5. Publish `DID_CHANGE`.

`AccountSessionExpectation` captures `generation`, `serverId`, and `serverUrl`. A sign-in commit fails when the generation moved (`S/network/TokenManager.kt:42-58`).

## 5. Profiles and household

### 5.1 Listing

`TvProfileSelectionViewModel.loadProfiles` (`TV/ui/screens/profiles/TvProfileSelectionViewModel.kt:125-190`):

1. Capture the scope.
2. `GET /api/v2/account/me`. Role `admin` enables manage mode.
3. `GET /api/v2/profiles`.
4. Drop the result if the identity changed in between.
5. A single profile without a PIN is opened automatically, once per sign-in.

### 5.2 Switching

`TV/ui/screens/profiles/TvProfileSelectionViewModel.kt:268-393`:

1. A profile without a PIN goes straight to `selectProfile(id, null, gridScope)`.
2. A PIN profile:
   1. Capture the scope.
   2. `POST /api/v2/profiles/{id}/verify-pin` with `{pin}`, sent without profile headers.
   3. Drop the answer if another tap superseded it.
   4. A token from `authorizedProfileToken` is committed with `selectProfile(id, token, scope)`.
   5. A 200 without a token shows "Wrong PIN. Try again."

`ProfileRepository.selectProfile` (`S/repository/ProfileRepository.kt:110-160`) runs inside `PROFILE_SWITCH`:

1. Refuse if a remote-playback overlay exists, or if the scope moved.
2. `setProfileIdentity(id, token)` writes both in one edit.
3. `registry.setProfileId(server, id)`.
4. Reset the notifications and requests repositories.
5. Emit `profileSwitches`. That restarts the home realtime socket (`TV/home/HomeRealtimeForegroundStarter.kt:62`).

From then on every request carries the new `X-Profile-Id` and `X-Profile-Token`.

### 5.3 Household management (manage mode)

The server lets only the primary profile create, edit, or delete profiles (`S/repository/HouseholdManagementSession.kt` class doc). To enter manage mode, verify the primary profile's PIN if it has one. Keep `HouseholdManager(primaryId, token, scope)` in memory only (`:69-80`).

Management calls send the primary's id and token through a copy of the pinned scope (`S/network/api/ProfileApi.kt:48-68`). A 403 with code `profile_verification_required` or `profile_unverified` re-asks for the PIN and retries once (`S/repository/HouseholdManagementSession.kt:104-108`, `:169-172`).

### 5.4 Profile teardown

"Switch profile" and launch-time profile selection call `TvActiveProfileReset.clearActiveProfile` (`TV/profiles/TvActiveProfileReset.kt:16-42`). It runs these steps.

1. `clearProfile()` sets the id and token to null under `PROFILE_SWITCH` (`S/repository/ProfileRepository.kt:251-259`).
2. Clear the library prefs, overlay prefs, card presentation, seek interval, and title art stores.
3. Clear the Watch Next rows.

## 6. Account endpoint usage

`GET /api/v2/account/me` returns `id`, `username`, `email`, `role`, `download_allowed`, and `impersonation?` (`S/network/apiv2/ApiV2Models.kt:63-78`). The UI uses these fields.

- **TV top-bar account chip.** The name is the active profile's name, then `username`, then "Profile". The subtitle is the capitalized `role` (or `username`), shown only when the active profile `is_primary`. The server name comes from the registry entry (`TV/ui/shell/TvMainShell.kt:640-674`).
- **TV Settings.** Stores the whole `User`, the active profile's name, and its avatar. It retries a bounded number of times (`TV/ui/screens/settings/TvSettingsViewModel.kt:183-230`).
- **Profile picker.** `role == "admin"`, compared case-insensitively, gates manage mode. `username` is the account name (`TV/ui/screens/profiles/TvProfileSelectionViewModel.kt:131-132`, `:165-172`).
- **Approval card.** The scoped `me` names the account a TV will be signed in to (`S/viewmodel/DevicePairingViewModel.kt:52`, `:72`).

## 7. Port notes for Dart

Non-obvious behaviours a reimplementation must copy:

1. **One refresh at a time, with a double check.** Serialize refreshes behind a single lock. Inside it, compare the stored token with the `Authorization` this request sent. If they differ, retry without calling `/auth/refresh` (`S/network/AuthInterceptorImpl.kt:155-166`). Refresh tokens rotate, so two parallel refreshes would void each other.
2. **Re-check after the refresh round trip.** Discard the result if the active server changed, or the refresh token was cleared (logout), while the request was in flight (`S/network/AuthInterceptorImpl.kt:209-226`).
3. **Only 400, 401, or 403 from refresh ends the session.** Keep the session through 5xx, network failures, and 503 `provider_unavailable` (`S/network/AuthInterceptorImpl.kt:248-257`).
4. **Retry a 401 at most once.** Never retry `/auth/login`, `/auth/refresh`, or any non-replayable POST. That covers login, signup, setup, device start/poll/cancel, OAuth complete, network sign-in, invitation accept, and profile mutations (`singleAttempt` sites in 1.2 to 1.5).
5. **Proactive refresh.** Use a 60 s margin clamped to half of `expires_in`. Do nothing when the lifetime is unknown. A rejected proactive refresh fails the request before it is sent (`S/network/ProactiveRefreshPolicy.kt:28-38`, `S/network/AuthInterceptorImpl.kt:693-698`).
6. **Credentials only to the trusted origin.** Strip `Authorization`, `X-Profile-*`, and `X-Silo-*` from any request whose scheme, host, or port differs from the active server's, including after a redirect (`S/network/AuthInterceptorImpl.kt:418-426`, `:754-756`).
7. **Public probes carry no bearer.** `system/info`, `system/identity`, `system/setup`, `auth/signup`, `auth/providers`, `oauth/capabilities`, `device/capability`, branding, and health are sent without auth headers, so a dead session cannot break them.
8. **Cleartext gate.** Block every non-GET to an unapproved `http://` origin, and every request that would carry a bearer. Store approvals per canonical origin (`S/network/AuthInterceptorImpl.kt:398-407`).
9. **Sign-in commits are fenced.** Capture `(generation, serverId, serverUrl)` before the sign-in call. Commit only if it is unchanged, and verify the generation is exactly `+1` afterwards. Otherwise report `identity_changed` (`S/repository/AuthRepository.kt:60-89`, `:129-132`).
10. **Device code tokens arrive once.** Never drop a poll reply that is already in flight when the screen stops. Run the token save in a job that the screen's lifecycle cannot cancel (`TV/ui/screens/auth/TvLoginViewModel.kt:584-588`, `S/repository/DeviceSignInMachine.kt:151-158`).
11. **Device code timing.** Poll right after start. Use `interval`, then `poll_after`, with a 1 s minimum. Back off from the interval, doubling up to 30 s. Clamp every wait to the deadline. Extend the deadline only from a pending reply's `expires_at`, converted through the start reply's `expires_at` and `expires_in` pair (`S/repository/DeviceLoginRepository.kt:68-189`).
12. **Withdraw abandoned codes.** Before replacing an expired code, and when leaving the screen, `POST device/cancel` best-effort with a 5 s bound. Skip it only when the capability says `cancel: false` (`S/repository/DeviceSignInMachine.kt:364-379`).
13. **Password and device code race.** The first finisher wins. A device approval that arrives while the password save is running is held and used if the save fails (`TV/ui/screens/auth/TvLoginViewModel.kt:313`, `:664-668`, `:754-764`).
14. **Commit the profile id and token together.** Write them atomically, read them together, and clear the token whenever the id changes. Send `verify-pin` without profile headers, or a stale token turns a correct PIN into 403 (`S/network/api/ProfileApi.kt:116-129`, `S/network/TokenManager.kt:141-180`).
15. **A wrong PIN is a 200.** Enter a profile only when `valid` is true and `profile_token` is non-blank (`S/model/profile/ProfileModels.kt:124-125`).
16. **Drop stale profile lists.** Discard a list fetched under an identity that has since changed, and drop a PIN reply that another tap superseded (`TV/ui/screens/profiles/TvProfileSelectionViewModel.kt:136-150`, `:316-321`).
17. **Contract gate.** Record the `UPDATE_REQUIRED` verdict only from the exact legacy 404 body. While it is set, block every v2 call locally. Re-probe a non-V2 verdict at launch with a 3 s bound (`S/network/apiv2/ApiV2Probe.kt:146-147`, `S/repository/AuthRepository.kt:500-503`).
18. **Stable device id.** Generate the `X-Silo-Device-Id` UUID once and persist it apart from the tokens, so sign-out does not change it (`AS/network/AndroidDeviceMetadataProvider.kt:31-33`).
19. **`expires_in` may be absent on device approval.** The TV passes `0` when it is missing (`TV/ui/screens/auth/TvLoginViewModel.kt:686`). Combined with the half-life clamp, that disables proactive refresh until the first 401 refresh records a real lifetime.
