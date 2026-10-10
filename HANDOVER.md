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
`flutter analyze` is clean and 23 tests pass.

Two fixes worth knowing about, both guarded by tests:

- `kRevealHeight` is **118**, not 112. The tallest reveal — somebody in the room *and*
  somebody called, which is when NO-SHOW shows — needs 116px inside the shell's 1px border;
  at 112 it clipped the button by exactly 6px. `test/reveal_height_test.dart` measures this
  with real Segoe UI metrics at all three sizes, because flutter_test's placeholder font is
  a different height and would pass on a broken constant.
- `ActionButton` builds its `AnimationController`s in `initState`, never lazily. A
  `late final` field is only realised when it is first read, and `dispose()` reads it, so
  **END VISIT** — the button that is never held — constructed its controller while being
  torn down and threw "Looking up a deactivated widget's ancestor is unsafe".
  `test/action_button_dispose_test.dart` covers it.

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

- **A long patient name overflows the reveal.** The big name in `_Reveal` has no `maxLines`,
  so it wraps and the NO-SHOW button is pushed past the panel — measured 42px over at
  `kRevealHeight = 118` for a three-line name (a two-line name is ~21px over). No fix
  applied, because each option is a design call: ellipsise the reveal name (which
  contradicts "full name, unabbreviated"), allow two lines and pay ~21px of permanent
  window height for everyone, or measure the content and resize the window to suit.
- The 1150ms sign-in → widget morph and landing blink
- The ten-step first-run tour in Bahasa Malaysia (script is in the `.dc.html`)
- Sound coordination with the web app (local IPC — only one surface may own the sound)
- Windows startup registration (installer)
- The "Open in Chup" target URL
