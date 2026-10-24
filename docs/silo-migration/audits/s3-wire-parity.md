# S3 wire parity audit

Every HTTP call S3 adds, checked against `research/silo-catalog.md` and the Silo Kotlin source at `/home/mine/Desktop/silo-android/silo-android`. Read-only. Audited at `9d656fee7` (S3 code unchanged since `35342075d`) on 2026-10-14.

Prefixes follow the research file. `S/` is `shared/src/commonMain/kotlin/org/siloserver/silo/`. `T/` is `androidTvApp/src/androidMain/kotlin/org/siloserver/silo/tv/`.

## Calls

| Call | Plezy | Silo | Result |
|---|---|---|---|
| `GET /api/v2/home/sections` | `lib/silo/silo_catalog.dart:172-175` | `S/network/apiv2/HomeSectionsV2Api.kt:46-49` | Match. A row without `items` rejects the response (`decodeSectionV2`). |
| `GET /api/v2/home/sections/{id}/items` | `lib/silo/silo_catalog.dart:179-180`, `:200-204` | `S/network/apiv2/HomeSectionsV2Api.kt:51-59` | Match. The returned id must equal the requested one. |
| Hydration of empty rows, at most 4 at once | `lib/silo/silo_catalog.dart:346-379` | `S/viewmodel/HomeSectionHydrator.kt:22-55` | Match. Failed or still-empty rows are dropped. |
| `GET /api/v2/library/{id}/sections`, `/sections/{sid}/items` | `lib/silo/silo_catalog.dart:185-198` | `S/network/apiv2/LibrarySectionItemsV2Api.kt:13-30` | Match. Featured sections are left out of Recommended, as `T/ui/screens/library/TvLibraryDetailViewModel.kt:421-520` does. |
| `GET /api/v2/user/libraries` | `lib/silo/silo_catalog.dart:221-230` | `S/network/apiv2/UserLibrariesV2.kt:7-24` | Match. Duplicate ids refuse the response. |
| `GET /api/v2/settings/values/effective?keys=ui.disabled_library_ids` | `lib/silo/silo_catalog.dart:234-247`, `:384-398` | `S/network/apiv2/SettingsV2Api.kt:50-67`, `S/repository/HiddenLibrariesStore.kt:94-111` | Match |
| `GET /api/v2/catalog` | `lib/silo/silo_catalog.dart:67-79`, `:251-261` | `S/network/apiv2/CatalogV2Api.kt:29-66` | Match on parameter set, order and `sort=-field`. `image_size` is never sent, as the TV library browse and search also omit it. |
| `POST /api/v2/catalog/query` | `lib/silo/silo_catalog.dart:82-96` | `S/network/apiv2/CatalogV2Api.kt:35,40-46` | Match. Used only when rule groups exist. Plezy always sends `order` with `sort`. The Kotlin body drops a null `order`, and this audit did not check whether a TV caller ever sorts without one. |
| Cursor paging and restart | `lib/silo/silo_catalog.dart:403-458` | `S/network/apiv2/CatalogV2Api.kt:68-80,208-217` | Match. A repeated or missing `next_cursor` with `has_more`, or `invalid_cursor`, restarts from page one once. |
| `GET /api/v2/catalog/filters` | `lib/silo/silo_catalog.dart:265-269` | `S/network/apiv2/CatalogV2Api.kt:110-119` | Match. `skip_technical=false` as the TV Browse tab sends it. Plezy surfaces only genre and content rating. |
| `GET /api/v2/catalog/items/{id}` | `lib/silo/silo_catalog.dart:271-272` | `S/network/apiv2/CatalogV2Api.kt:141-147` | Match. `library_id` is optional and not sent. |
| `GET /api/v2/catalog/series/{id}/seasons`, `/seasons/{n}/episodes` | `lib/silo/silo_catalog.dart:274-288` | `S/network/apiv2/CatalogV2Api.kt:149-163` | Match. Season order and initial season follow `S/model/catalog/CatalogModels.kt:483-509` (`lib/silo/silo_mappers.dart:336-360`). |
| Search, `GET /api/v2/catalog?source=query&q=…&limit=40` | `lib/services/silo_client.dart` `searchItems` | `T/ui/screens/search/TvSearchViewModel.kt:151,287-294` | Match for the first page, with no `type` for All. See L1. |
| `GET /api/v2/catalog/search/capabilities` | `lib/silo/silo_catalog.dart:292-295` | `S/repository/SearchPeople.kt:30` | Match. Read before every people lookup. |
| `GET /api/v2/catalog/people` | `lib/silo/silo_catalog.dart:297-302` | `S/repository/SearchPeople.kt:24-36`, `T/ui/screens/search/TvSearchViewModel.kt:42-47` | Fixed. See M1. |
| `GET /api/v2/recommendations/similar/{id}?limit=12` | `lib/silo/silo_catalog.dart:306-319` | `S/network/apiv2/SimilarCardsV2Api.kt:15-28` | Match. Over-long or duplicate lists refuse the response. |
| `POST`/`DELETE /api/v2/watched/{id}` | `lib/silo/silo_catalog.dart:323-324` | `S/repository/port/PersonalWrite.kt:17-21` | Match. Single attempt, 204 only. Live lane 9 confirmed both directions. |
| `PUT`/`DELETE /api/v2/ratings/{id}` | `lib/silo/silo_catalog.dart:328-332` | `S/repository/port/PersonalWrite.kt:23-30` | Match. M2 fixed the value sent. |
| `PUT`/`DELETE /api/v2/favorites/{id}`, `/watchlist/{id}` | `lib/silo/silo_catalog.dart:335-340` | `S/network/apiv2/MembershipV2Api.kt:27-28,41-54` | Match |

## Findings

Audit run at `9d656fee7`. Fixes landed after it, up to `22fd99401`.


- **M1. People search sends no `media_scope`.** Plezy asks `/catalog/people` once with no scope, which searches every media scope. The Silo TV app's All filter asks with `media_scope=video`, plus `audiobook` only when audiobooks are shown (`T/ui/screens/search/TvSearchViewModel.kt:42-47`). Plezy can therefore list authors and narrators of ebooks and audiobooks, media it hides elsewhere. Fixed in `86c98f005`: Plezy now sends `media_scope=video`, with a test. Rechecked live, a search for a cast name lists the person (`media/s3/recheck-search-people.png`).
- **M2. Half-star ratings are rounded.** The rating sheet allows half stars (`lib/widgets/rating_bottom_sheet.dart:349`). Silo stores 1 to 5 whole stars, and `SiloClient.rate` rounds half up (`lib/services/silo_client.dart` `rate`). A 2.5-star rating is saved as 3, and the user sees 3 on reopening. Fixed in `e5a6b883e`: a `wholeStarRating` capability, on for Silo, makes the sheet step and snap by whole stars, with a test. Rechecked live, one Right press gives one full star, and clearing it restored the unrated state.
- **L1. Search reads one page.** The TV loads further 40-item pages as the user scrolls (`T/ui/screens/search/TvSearchViewModel.kt:232,324-343`). Plezy shows at most 40 results. Lane 8 found the target title on the first page.
