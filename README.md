# Chup Widget — Windows desktop

> ## The redesign is built
>
> `lib/` implements **section 2a (Sliver)** of `design/README.md`: the 284×208 panel is gone,
> replaced by a **216×40 sliver** anchored 12px from the bottom-right corner.
>
> - **`design/README.md`** — the spec. 1a/1b/1c are dead ends; do not implement them.
> - **`design/BACKEND-WIRING.md`** — **read this before touching the API.** The design assumes a
>   backend shape that does not exist; this maps it to the real one and lists the four fields
>   still missing.
> - **`design/Widget Redesign.dc.html`** — the interactive prototype, in a browser.
>
> ### Built
>
> Resting sliver naming the *next* patient · hover reveal opening upward with the full name and
> the five-control cluster · the action state machine (ALERT / START / END VISIT single click,
> **NO-SHOW hold-to-confirm 550ms** with the patient's name on it) · wait and serving meters
> against `LIMIT`/`SERVE`/`GRACE` · Small/Medium/Large growing upward with the bottom 38px
> pinned · all four data states · minimised 44×44 chip · closed 5×34 edge tab · grip-only
> dragging with position persisted per display · sign-in with "stay signed in" · sign-in to
> corner morph · first-run landing blink and the Bahasa Malaysia tour (Help replays it) ·
> Windows startup registration on sign-in · "Open in Chup" to the web live queue · Quit.
>
> ### Not built
>
> | Item | Why |
> |---|---|
> | Sound coordination with the web app | The widget makes no sound, so there is nothing to coordinate yet |
> | Tour card in the opposite screen corner | Needs a second native window; it sits beside the panel instead |
>
> `called_at` and `started_at` are used when the API sends them. Until it does, the widget
> counts from when it first saw the alert or the consultation start; see
> `design/BACKEND-WIRING.md`.

A small always-on-top queue panel for consultants. It sits above whatever clinical system the
doctor is working in and shows who is being served, who is next, and one action button.

**This is its own product.** It is *not* related to `chup-tab` (the staff **tablet** app) beyond
sharing the same backend API. Nothing here is derived from that codebase.

## What it does

| | |
|---|---|
| SERVING band | the queue token currently being served |
| Current patient | token, name, and the time they should be seen |
| One action | **Alert**, then **Start** once called, then **End Visit**. **No-Show** (hold) in the reveal while called |
| Upcoming | the next patients, however many the current size shows |
| Sizes | Small / Medium / Large from the "…" menu, remembered between sessions |

The window is frameless and always-on-top. Drag it by the grip. Close tucks it into an edge
tab; Quit in the menu exits. The queue is polled every 10 seconds, every 60 while closed, and
backs off to 60 while the server is unreachable. A failed action shows its reason on the
resting line for a few seconds. An expired session returns to sign-in.

## Running it

The base URL is supplied at build time, so no environment file ships beside the exe.

| Environment | Base URL |
|---|---|
| **Production** (live clinics, the release-build default) | `https://chup.online/api/v1/` |
| **Staging** (the debug-build default, safe to test against) | `https://chup.tech/api/v1/` |

Test against staging — the actions write real queue state:

```bash
flutter run -d windows --dart-define=BASE_URL=https://chup.tech/api/v1/
```

Production build for clinics (the release default, so the define is optional):

```bash
flutter build windows --release --dart-define=BASE_URL=https://chup.online/api/v1/
```

The build lands in `build\windows\x64\runner\Release\`. Ship that whole folder — the exe needs
the DLLs beside it.

Sign in with an account that can use `widget-login`; the token is stored locally via
`get_storage` and reused until sign-out.

## Layout

```
lib/
  main.dart                  window setup (frameless, always-on-top) + theme
  core/api.dart              endpoints + HTTP client + login
  core/visit.dart            the Visit model and the action state machine
  core/queue_controller.dart polling, size modes, action dispatch
  ui/widget_shell.dart       the panel
  ui/login_screen.dart       sign in
test/widget_test.dart        model + state-machine tests
API-CONTRACT.md              every endpoint, verified against the backend
```

## Things that will bite you

- **`is_end_visit` comes back as `0`/`1`, not a JSON boolean.** Typing it as `bool` throws on
  decode. Everything goes through `Visit._flag`, and a test pins that behaviour.
- **Status strings arrive in English and Malay** (`"Tidak Hadir"` / `"NO_SHOW"`). Match the enum
  name, never the display label.
- **No Firebase, deliberately.** The tablet app's `firebase_options.dart` throws
  `UnsupportedError` on Windows, which is why that app cannot run on desktop at all. This app
  authenticates with the API and a stored token, and needs nothing else.
- **Windows Developer Mode must be on** to build — Flutter needs symlink support for plugins.
- **`no-show` had never been called by any client** before this widget. The route exists
  (`visits.no-show`) and is registered, but this is its first real use — worth watching closely
  the first time it runs against production.

## Tests

```bash
flutter test
```

Covers parsing (the integer `state`, booking times, 0/1 flags), the Alert, Start, End Visit
sequence, positions, limits, polling backoff, session expiry, and layout. Layout tests need
Segoe UI, so they skip on macOS and Linux and run in CI on Windows. No server required.
