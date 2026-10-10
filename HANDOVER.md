# Chup Desktop Widget — handover

The always-on-top Windows queue panel for consultants. Flutter/Dart, desktop only.
Lives here because its backend is this repo; it is otherwise a self-contained app.

## Read in this order

| File | What it gives you |
|---|---|
| `CLAUDE.md` | The short version — how to run it, and every trap that has already cost time |
| `design/README.md` | The approved design spec. Build **section 2a (Sliver)**; 1a/1b/1c are dead ends |
| `design/BACKEND-WIRING.md` | **The backend job.** Exact code for the fields still missing |
| `design/Widget Redesign.dc.html` | The interactive prototype — open in a browser |
| `API-CONTRACT.md` | Every endpoint the widget uses, verified live |

## State

The app is **built and running**. The redesign (216×40 sliver, hover reveal, hold-to-confirm
No-Show, three sizes, four data states, minimised chip, closed edge tab) is implemented.
`flutter analyze` is clean and 14 tests pass.

Verified against staging: sign-in through `user/auth/widget-login`, and both queue reads.
Not yet verified end-to-end: the three actions, because staging's queue has been empty. That
includes the **first-ever call to `user/visits/{id}/no-show`** — the route exists but no client
has ever used it.

## The backend job, in short

Two timestamps and one settings block. **No migration is needed for the timestamps** —
`visit_histories` already records `(visit_id, state, created_at)` on every transition, and
`App\Enums\Visit\State` has `ALERTED = 2` and `SERVING = 4`. So:

- `called_at` = newest history row at state `ALERTED`
- `started_at` = newest history row at state `SERVING`
- `limits` = `{wait_minutes: 20, consult_minutes: 15, grace_minutes: 5}` per clinic,
  `consult_minutes` ideally per doctor

`design/BACKEND-WIRING.md` has the `withMax` query, the relation and the resource lines.
Emit ISO 8601 **with the offset** — a bare `Y-m-d H:i:s` is read as local time and every minute
figure comes out wrong.

Check your work in seconds:

```bash
python tools/verify-backend.py --base https://chup.tech/api/v1/ --email <staff> --password <pw>
```

## Running the app

```bash
cd desktop-widget
flutter run -d windows --dart-define=MOCK=true
```

`MOCK=true` is how to do UI work: staging's queue is usually empty, so without fixtures most
states never render. Fixtures never write to a real queue.

Requires Windows Developer Mode (Flutter needs symlinks for plugins). Release builds must be
made in CI — Smart App Control blocks Flutter's unsigned AOT compiler locally.

## Still open

- The 1150ms sign-in → widget morph and landing blink
- The ten-step first-run tour in Bahasa Malaysia (script is in the `.dc.html`)
- Sound coordination with the web app (local IPC — only one surface may own the sound)
- Windows startup registration (installer)
- The "Open in Chup" target URL
