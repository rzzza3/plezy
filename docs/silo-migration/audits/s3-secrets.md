# S3 secrets and data-loss audit

S3's catalog code, checked for credentials leaking into logs, errors or storage, and for writes that can lose user data. Read-only. Audited at `9d656fee7` (S3 code unchanged since `35342075d`) on 2026-10-14.

## Secrets

| Check | Evidence | Result |
|---|---|---|
| New log lines carry no title, token or profile token | `lib/services/silo_client.dart` logs `Silo: home sections <n>` and `Silo: next-up read failed (<status>)`. `lib/screens/discover_screen.dart` logs `Home: first hub frame, rows <n>`. | Pass. Counts and status codes only. Lane logcat captures matched. |
| Error objects carry no query or credential | `lib/silo/silo_catalog.dart:137,154` build the request URI from the path alone. `:167` strips the query from the response URL. | Pass. A search term never reaches an exception message through these paths. |
| No Silo credential on image requests | `thumbnailUrl` and `externalImageUrl` return the server URL unchanged, and `streamHeaders` is empty (`lib/services/silo_client.dart`). | Pass |
| No token stored outside `CredentialVault` | S3 adds no storage writes. Reads go through `SiloHttp`, which S2 audited. | Pass |

## Data loss

| Check | Evidence | Result |
|---|---|---|
| Writes are single attempt and report failure | `lib/silo/silo_catalog.dart:148-158`. Test "a refused write is not retried and throws". | Pass |
| Watched toggle round-trips | Live lane 9 marked a movie watched and back, and both reopened details matched. | Pass |
| A read that straddles a profile switch is dropped, not shown under the new profile | `lib/silo/silo_catalog.dart:139,156`, home cache and pager keyed by generation. Test "a read that straddles a profile switch is dropped". | Pass |
| Stored Silo items decode | `MediaItem.silo` round-trips through JSON (`test/silo/silo_mappers_test.dart` "a Silo item survives the MediaItem JSON round trip"). | Pass |
| Trunk does not destroy a Silo connection | Lane 1 ran trunk over stored Silo data. Trunk logged `failed to decode connection silo:…` and returned null. The head build then found the connection intact. | Pass |
| Ratings keep the user's value | See wire-parity M2. A half-star rating was rounded up on the server. | Fixed in `e5a6b883e` |

## Findings

- **M2, fixed in `e5a6b883e`.** Shared with the wire-parity audit. A half-star rating was silently saved as the next whole star.
- **L1. Presigned artwork URLs are persisted.** Artwork URLs are resolved at decode time and kept on `MediaItem`, so a saved item holds presigned URLs (`exp`/`sig`, research line 302). They grant one image each and expire, and they are not account credentials, so this is not a secrets failure. The expiry means a saved card can lose its artwork, which S4's home refresh covers.
- **L3, fixed in `22fd99401`.** Found during the M2 recheck. The rate sheet labelled a Silo server row "Plex - Silo", because the label fell back to Plex for every backend without a MediaBrowser dialect.
- **L2. The `_parents` map outlives a profile switch.** `SiloClient._parents` maps show and season ids to parent info and is not cleared on a generation change. It holds ids, titles and poster URLs, which are the same for every profile on a server, so nothing personal crosses profiles.
