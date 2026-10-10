# Wiring the redesign to the real backend

**Read `design/README.md` first** — that is the design spec. This file is the bridge between it
and the API that actually exists.

The design proposes its own backend shape (a single poll returning `session` / `serving` /
`called` / `queue` / `limits`, and `POST /queue/*` actions). **That endpoint does not exist.**
The real API is a different shape, verified live against staging on 2026-07-31. Everything below
is what a developer needs to reconcile the two.

---

## What already works — reuse it, don't rewrite it

`lib/core/api.dart`, `lib/core/visit.dart` and `lib/core/queue_controller.dart` are wired to the
live API and verified working. **Only the UI is superseded by the redesign.** Keep the transport
layer, replace `lib/ui/`.

Base URLs (note the `v1` — it is added at deploy time and appears nowhere in the Laravel source):

| Environment | Base URL |
|---|---|
| Production | `https://chup.online/api/v1/` |
| Staging | `https://chup.tech/api/v1/` |

Auth: `POST user/auth/widget-login` with `{email, password}` → the token is in
`data.api_token`. Send it as `Authorization: Bearer <token>`.

Two traps that will cost a day if rediscovered:
- **A wrong password returns HTTP 200** with `{"error": true}` in the body. Status codes alone
  will report success.
- **An expired token returns an HTML redirect**, not a JSON 401. Detect a leading `<`.

---

## Endpoint mapping

| Design calls for | Real endpoint | Notes |
|---|---|---|
| poll | `GET user/visits` + `GET user/visits/serving` | **Two calls, not one.** Both return a Laravel paginator — `{data:{data:[…]}}`. `serving` is a *list* too, take `[0]`. |
| `POST /queue/alert {token}` | `PUT user/visits/{id}/alert` | Keys on **`id`, not `token`** |
| `POST /queue/end-visit {token}` | `PUT user/visits/{id}/served` | |
| `POST /queue/no-show {token}` | `PUT user/visits/{id}/no-show` | Route exists (`visits.no-show`); **no client has ever called it.** First real use — watch it. |
| (not in design) | `PUT user/visits/{id}/undo-alert` | Exists. The design has no undo; this makes one possible. |
| Open in Chup | web app queue URL | |

---

## Field mapping

Authoritative source: `app/Http/Resources/Visits/VisitResource.php` on the `develop`/`v1`
branches of `100Startups/chup.online`.

| Design field | Real field | Status |
|---|---|---|
| `session.total` | paginator `total` | ✅ |
| `session.position` | `sort_index` | ✅ |
| `serving.token` / `.name` | `token`, `client.name` | ✅ |
| `queue[].token` / `.name` | `token`, `client.name` | ✅ |
| `queue[].waiting_since` | **`arrived_at`** | ✅ a real timestamp, exactly as the design wants |
| `queue[].appointment_at` | `booking` relation | ⚠️ only present when the visit came from a booking; walk-ins have none |
| `state` (drives the button) | `state.name` + `state.id` | ✅ match the **enum**, never the label — labels arrive in Malay too (`"Tidak Hadir"` = `NO_SHOW`) |

### The gaps — smaller than they look

**No migration is required for the two timestamps. They are already in the database.**

`visit_histories` records `(visit_id, state, created_at)` on every state transition, and
`App\Enums\Visit\State` has exactly the two states needed:

```php
case ALERTED = 2;   // -> called_at
case SERVING = 4;   // -> started_at
```

So `called_at` and `started_at` are both "the newest `visit_histories.created_at` for this visit
at state N". Two accessors and two resource lines.

#### 1 + 2 · `called_at` and `started_at`

Do it as a query aggregate rather than an accessor, so a queue of 10 does not become 11 queries:

```php
// wherever visits are listed for the widget (index + serving)
use App\Enums\Visit\State;

Visit::query()
    ->withMax(
        ['histories as called_at' => fn ($q) => $q->where('state', State::ALERTED->value)],
        'created_at'
    )
    ->withMax(
        ['histories as started_at' => fn ($q) => $q->where('state', State::SERVING->value)],
        'created_at'
    );
```

`app/Models/Visit.php` needs the relation if it is not there yet:

```php
public function histories(): HasMany
{
    return $this->hasMany(VisitHistory::class);
}
```

Then in `app/Http/Resources/Visits/VisitResource.php`, beside the existing fields:

```php
'called_at'  => $visit->called_at  ? Carbon::parse($visit->called_at)->toIso8601String()  : null,
'started_at' => $visit->started_at ? Carbon::parse($visit->started_at)->toIso8601String() : null,
```

**ISO 8601 with the offset, please** — the widget parses these and counts from them. A bare
`Y-m-d H:i:s` with no zone will be read as local and the minute figures will be wrong by the
UTC offset.

The widget already reads both keys (`Visit.fromJson` in `lib/core/visit.dart`) and also accepts
`alerted_at` as an alias, so nothing on the client side changes when these appear.

#### 3 · `limits`

The one genuinely new piece. Three integers, per clinic, ideally per doctor for `consult`:

```json
"limits": { "wait_minutes": 20, "consult_minutes": 15, "grace_minutes": 5 }
```

Anywhere in the response the widget can reach it. Until it exists the widget uses 20 / 15 / 5
(`lib/core/limits.dart`) and `Limits.fromJson` will pick the real values up the moment the key
appears — no client change needed.

`estimated_time` and `service_time` already exist per visit, but they are not the same thing:
the design wants one flat consultation length for the doctor, not a per-visit estimate. Worth a
conversation before substituting.

#### Verify it

```bash
python tools/verify-backend.py --base https://chup.tech/api/v1/ --email <staff> --password <pw>
```

Checks the login shape, both endpoints, and reports which of the fields above are present or
still missing. Run it after each change instead of eyeballing JSON.

`supposed_waiting_duration` is returned as a **duration**, not a timestamp. The design is
explicit that durations freeze between polls — derive minutes from `arrived_at` and the local
clock instead, and use the duration only as a cross-check.

---

## Things in the design that are not backend work

Flagged so nobody goes looking for an API for them:

- **Sound coordination.** The design says the widget must stay silent while the Chup web app is
  open — one surface owns the sound. That is local IPC (named pipe / lock file), not an endpoint.
- **Startup registration.** Registering in the Windows startup list is installer work.
- **Position, size, `first_run_completed`, tour state.** All local storage.
- **The first-run tour** is ten steps in Bahasa Malaysia, driving the live panel. No backend.

## Platform note

The current app is **Flutter/Dart** (Windows desktop). The design handoff was written
shell-agnostically and mentions Electron/React/WinUI as examples — that is not a
recommendation to switch. The Web Animations API note in the design maps to Flutter's
`AnimationController`; the underlying warning still applies: **drive the morph from an
animation object that owns itself, not from anything that restarts on rebuild.**

`window_manager` already provides always-on-top, frameless, sizing and positioning. The
redesign needs three things it is not yet doing: corner-anchored positioning (12px from right
and bottom), the minimised 44×44 chip, and the 5×34 closed tab flush to the screen edge.
