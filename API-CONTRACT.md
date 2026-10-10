# Chup Widget — API contract

The Windows desktop queue widget. **A separate product** from `chup-tab` (the staff *tablet*
app) — they share this backend API and nothing else.

Contract assembled 2026-07-31 by reading the backend routes (`chup.tech-develop`
`routes/api/api.php`) and the only existing client of them (`chup-tab`). **No backend work is
required** — every endpoint below already exists and all but one are proven in production.

## Hosts — and the `v1` prefix

| Environment | Base URL | Branch |
|---|---|---|
| **Production** (live clinics) | `https://chup.online/api/v1/` | `v1` |
| **Staging** | `https://chup.tech/api/v1/` | `develop` |

Both folders on disk are the *same repo* (`100Startups/chup.online`) at different branches.

**The deployed API lives under `/api/v1/`, not `/api/`.** The repo's `RouteServiceProvider`
registers only a bare `api` prefix, so the `v1` segment is added at deploy time and appears
nowhere in the source. Getting this wrong returns a Laravel JSON 404 —
`"The route api/user/auth/widget-login could not be found."` — which reads exactly like a wrong
path or a missing route, and cost real time to track down. Verified 2026-07-31: with the `v1`
segment both hosts answer `422` asking for email and password.

All calls are authenticated with the token from login.

## Auth

| Purpose | Method + path |
|---|---|
| Login | `POST user/auth/widget-login` |
| Validate / refresh token | `user/auth/validate-token` |
| Logout | `user/logout` |

`widget-login` was added Feb 2024 (commit `745b9b96a`) — almost certainly built *for* this
widget; the tablet app later reused it, so it is well exercised.

## Queue

| Purpose | Method + path |
|---|---|
| Who is being served | `GET user/visits/serving` |
| The queue | `GET user/visits` |

## Actions — the mockup's button, in order

| Button | Method + path | Proven? |
|---|---|---|
| **Alert** | `PUT user/visits/{visitId}/alert` | yes, in `chup-tab` |
| (undo alert) | `PUT user/visits/{visitId}/undo-alert` | yes |
| **No-Show** | `PUT user/visits/{visitId}/no-show` | **route exists (`visits.no-show`), never called by any client** |
| **End Visit** | `PUT user/visits/{visitId}/served` | yes |
| Start serving | `PUT user/visits/{visitId}/serving` — body `{"force": true}` | yes |

## Visit fields the widget renders

From `visits_queue_response.dart` (`data[]`):

| Field | Used for |
|---|---|
| `id` | the `{visitId}` in every action above |
| `token` | the queue number — "AD124" in the SERVING band, "AD 125" on rows |
| `clientName` | patient name |
| `shouldBeServedAt` | the "3:30 PM" on the row |
| `stateName` / `stateColor` | which action to show, and its colour |
| `isEndVisit` | whether End Visit applies |
| `waitingDuration`, `supposedWaitingDuration`, `estimatedTime` | not shown in the mockup; available |

The list response is paginated: `currentPage`, `perPage`, `total`, `lastPage`, `data[]`.

## Traps

- **`is_end_visit` returns `0`/`1`, not `true`/`false`.** The tablet app carries a comment
  flagging this as an API defect. A fresh Dart client that types it as `bool` will throw on
  decode — coerce it.
- Status strings appear in both English and Malay in places (`"Tidak Hadir" || "NO_SHOW"` in the
  tablet's `t_helper.dart`) — match on the enum name, never the display label.
- Do **not** copy `chup-tab`'s Firebase setup. It is mobile-only: its `firebase_options.dart`
  throws `UnsupportedError` for `TargetPlatform.windows`, which is exactly why that app cannot
  run on desktop. The widget needs no Firebase at all — auth is this API plus a stored token.
