# S2 wire parity audit

Every HTTP call S2 makes, checked against `research/silo-auth.md` and the Silo Kotlin source at `/home/mine/Desktop/silo-android/silo-android`. Read-only. Audited at `d0f61223d` on 2026-10-13.

Kotlin paths use the prefixes from `research/silo-auth.md`. `S/` is `shared/src/commonMain/kotlin/org/siloserver/silo/`. `TV/` is `androidTvApp/src/androidMain/kotlin/org/siloserver/silo/tv/`.

## Shared request rules

| Rule | Plezy | Silo | Result |
|---|---|---|---|
| `Content-Type: application/json` on every request | `lib/silo/silo_http.dart:300` | `S/network/SiloHttpClientImpl.kt:96-98` | Match |
| `X-Silo-*` device headers on every same-origin request, including unauthenticated ones | `lib/silo/silo_http.dart:308`, `lib/silo/silo_headers.dart:87-96` | `S/network/AuthInterceptorImpl.kt:410-416`, `:836-861` | Match. `X-Silo-Client` is `Plezy` by design. `X-Silo-Client-Channel` is never sent, which the header rules allow when blank. |
| Credential headers stripped off-origin | `lib/silo/silo_http.dart:330`, `lib/silo/silo_headers.dart:99-106` | `S/network/AuthInterceptorImpl.kt:418-426` | Match |
| Cleartext gate. Only an unauthenticated GET reaches an unapproved `http://` origin. | `lib/silo/silo_http.dart` `send`, first check | `S/network/AuthInterceptorImpl.kt:398-407` | Match |
| `single` requests never refresh and never retry a 401 | `lib/silo/silo_http.dart` `send`, `replayable` | `S/network/AuthInterceptorImpl.kt:551-552`, `:593` | Match |

## Calls

| Call | Plezy | Silo | Body and headers | Status handling | Result |
|---|---|---|---|---|---|
| `GET /api/v2/system/info` | `lib/silo/silo_server_probe.dart:71`, 3 s bound, ungated | `TV/ui/screens/auth/TvServerSetupViewModel.kt:249-312`, `S/repository/AuthRepository.kt:533-539` | none, no auth | Only the update verdict stops the flow | Match |
| `GET /api/v2/system/setup` | `lib/silo/silo_server_probe.dart:83` | `S/network/api/AuthApi.kt:73` | none, no auth | Error moves to the next candidate | Match. Plezy gates it on the contract and Silo does not (`ApiV2Gate.Unrestricted`). The probe already returned on an update verdict, so the outcome is the same. |
| `GET /api/v2/auth/signup` | `lib/silo/silo_server_probe.dart:93` | `S/network/api/AuthApi.kt:83` | none, no auth | Any failure means false | Match |
| `GET /api/v2/system/identity` | `lib/silo/silo_sign_in.dart:407`, `:416`, single, 8 s | `S/network/api/ServerIdentityApi.kt:113-139` | none, no auth | Blank `server_id` means unreachable | Match |
| `GET /api/v2/theme/branding` | `lib/silo/silo_sign_in.dart:417`, parallel with identity | `S/network/api/BrandingApi.kt:15-43` | none, no auth | Blank name falls back to the host | Match |
| `GET /api/v2/auth/device/capability` | `lib/silo/silo_device_sign_in.dart:268` | `S/network/api/DeviceLoginApi.kt:200`, `S/repository/DeviceSignInMachine.kt:193-198` | none, no auth | Unreadable capability still allows cancel | Match. Silo re-reads a failed capability before a replace (`DeviceSignInMachine.kt` `replace`). Plezy reads it once. Both still send the cancel. |
| `POST /api/v2/auth/device/start` | `lib/silo/silo_device_sign_in.dart:295-296` | `S/network/api/DeviceLoginApi.kt:177`, `TV/ui/screens/auth/TvLoginViewModel.kt:535-538` | `device_name`, `device_platform: android-tv`, no auth, single | 201 only. 404/501 none. 410/426 update. Other 4xx failed. Network, 5xx, 408, 429 back off 1 s doubling to 30 s | Match on status handling. See findings L1, L2, L3, L5. |
| `POST /api/v2/auth/device/poll` | `lib/silo/silo_device_sign_in.dart:353`, `:375`, `:403` | `S/network/api/DeviceLoginApi.kt:189`, `S/repository/DeviceLoginRepository.kt:120-190` | `device_code`, no auth, single | Poll at once, then `interval`, then `poll_after`, 1 s floor, backoff from the interval doubling to 30 s, waits clamped to the deadline, deadline extended through the start reply's skew | Match. See finding L4. |
| `POST /api/v2/auth/device/cancel` | `lib/silo/silo_device_sign_in.dart:461`, `:468`, 5 s bound | `S/network/api/DeviceLoginApi.kt:213`, `S/repository/DeviceSignInMachine.kt:374-375` | `device_code`, no auth, single | Best effort, skipped only on `cancel: false` | Match. Live check lane 5 logged status 200 (`media/s2/lane-5-leave.log`). |
| `POST /api/v2/auth/login` | `lib/silo/silo_sign_in.dart:88-91` | `S/network/api/AuthApi.kt:25-33` | `username` (trimmed), `password`, no auth, single | 200 only. Problem code first, then 401, 403, 429, 503 | Match |
| `GET /api/v2/account/me` after a device approval | `lib/silo/silo_sign_in.dart:346` | none | bearer | Failure leaves the name blank | Extra call. See finding L6. |
| `GET /api/v2/account/me`, then `GET /api/v2/profiles` | `lib/silo/silo_profiles.dart:95`, `:98` | `TV/ui/screens/profiles/TvProfileSelectionViewModel.kt:125-190` | bearer and profile headers when set | Stale list dropped on a generation change | Match |
| `POST /api/v2/profiles/{id}/verify-pin` | `lib/silo/silo_profiles.dart:113`, `SiloAuth.account` | `S/network/api/ProfileApi.kt:116-129` | `pin`, bearer without profile headers | Enter only on `valid: true` with a non-blank token | Match. Live lanes 6 and 7 passed on Monday. |
| `POST /api/v2/auth/logout` | `lib/services/silo_client.dart:113`, single, 10 s | `S/network/api/AuthApi.kt:136-138` | bearer | Slot wiped whatever the answer | Mismatch. See finding M1. |
| `POST /api/v2/auth/refresh` (S1, used by every S2 bearer call) | `lib/silo/silo_http.dart:246` | `S/network/AuthInterceptorImpl.kt:199-202` | `refresh_token`, no auth headers | 400/401/403 end the session | Match, covered by the S1 verdict |

## Findings

### M1. Logout never refreshes an expired access token. Medium.

Plezy sends logout with `single: true` (`lib/services/silo_client.dart:113`). Silo's `logout()` has no `singleAttempt()` (`S/network/api/AuthApi.kt:136-138`), so it gets the proactive refresh and the one 401 refresh-and-retry like any bearer call.

Failure scenario. The access token expired while the TV sat idle. The person signs out. Plezy sends the stale bearer, the server answers 401, and the local slot is wiped. The server keeps the refresh token's session alive until it expires on its own, and it still lists this device. The plan's lane 9 pass condition says "the server lists no session for this device", and that fails here.

Fix for the root. Drop `single: true` from the logout request. Logout is safe to replay. Add a test with an expired session that asserts refresh, then logout, then the wipe.

### L1. A code started after the run was superseded is never withdrawn. Low.

Plezy drops the reply when the run moved on during `start` (`lib/silo/silo_device_sign_in.dart:309`). Silo withdraws that code (`S/repository/DeviceSignInMachine.kt:247-253`).

Failure scenario. The person presses Back while `device/start` is in flight. The server issues a code that nobody sees, and it stays approvable until it expires. Nobody saw the user code, so the risk is small.

### L2. A renewal blanks the code while it fetches the next one. Low.

`_startCode` always publishes `SiloDeviceGettingCode` (`lib/silo/silo_device_sign_in.dart:286`). Silo keeps showing the old code during a renewal and publishes `GettingCode` only from other states (`S/repository/DeviceSignInMachine.kt:241-246`).

Failure scenario. Each renewal makes the code flash to the loading state for one round trip.

### L3. Rate-limited starts trip "Can't reach" after 10 s. Low.

Plezy measures every failing start from one clock and shows Unreachable at 10 s, even for 429s (`lib/silo/silo_device_sign_in.dart:319-323`). Silo keeps separate clocks for 429 and for other failures (`S/repository/DeviceSignInMachine.kt:204-217`).

Failure scenario. A server answering 429 to `device/start` shows "Can't reach this server" from 10 s to 60 s, then "Too many requests".

### L4. An unreadable 200 poll ends the code instead of retrying. Low.

Plezy finishes with Failed when a 200 poll body does not decode (`lib/silo/silo_device_sign_in.dart:370`). Silo maps an unreadable response to Transient and retries (`S/repository/DeviceLoginRepository.kt:59`).

Failure scenario. A proxy returns a truncated 200 once. Plezy shows the failed state and needs "Try again". Silo would have polled again.

### L5. `device_name` carries the manufacturer. Low.

Plezy sends `X-Silo-Device-Name`'s value, `<manufacturer> <model>` (`lib/screens/auth/silo_login_screen.dart:60`). Silo TV sends `Build.MODEL`, or "Android TV" (`TV/ui/screens/auth/TvLoginViewModel.kt:920`).

Failure scenario. On the test emulator (`getprop` reports `Google` and `sdk_google_atv64_x86_64`), the approval page names the device "Google sdk_google_atv64_x86_64" where Silo would send "sdk_google_atv64_x86_64". This is cosmetic.

### L6. The device approval reads the name with an extra call and skips the contract re-probe. Low.

Plezy calls `GET /api/v2/account/me` after the commit (`lib/silo/silo_sign_in.dart:346`). Silo takes `user.username` from the approving poll reply (`TV/ui/screens/auth/TvLoginViewModel.kt:711`) and runs `onSessionCommitted()` to re-probe the contract (`:703`). Plezy has no post-commit re-probe on either sign-in path.

Failure scenario. One extra request per device sign-in. A server upgraded between probe and sign-in keeps its old verdict until the next launch.

### Not findings

- Plezy gates the device calls on the contract. Silo TV uses the `...At` variants with `ApiV2Gate.Unrestricted` (`S/network/api/DeviceLoginApi.kt:177`, `:189`, `:200`, `:213`). The login screen is reachable only after the probe passed, so the gate is open in practice.
- `SiloSignInError.fromResponse` has no case for `email_in_use` or `identity_linked_elsewhere`. Those come only from external sign-in, which S2 does not port (`plan.md`, test server limits).
