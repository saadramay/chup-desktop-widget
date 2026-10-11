# Chup Desktop Widget — context for Claude Code

An always-on-top Windows queue panel for consultants. Flutter/Dart, desktop only.

**Read `design/README.md` before changing any UI**, and `design/BACKEND-WIRING.md` before
touching the API. Both are authoritative; this file is the short version.

## Run it

```bash
flutter run -d windows --dart-define=MOCK=true
```

**Use `MOCK=true` for all UI work.** Staging's queue is usually empty and two fields the design
depends on don't exist yet, so without fixtures most states never render. Fixtures skip sign-in,
never write to a real queue, and use timestamps relative to now so meters fill and figures tick
exactly as they would live. Change `Mock.scenario` in `lib/core/mock.dart` to reach:
`calledPatient`, `graceExpired`, `longWait`, `consultOverrun`, `emptyQueue`.

Against real data:

```bash
flutter run -d windows --dart-define=BASE_URL=https://chup.tech/api/v1/
```

| Environment | Base URL |
|---|---|
| Production (release-build default) | `https://chup.online/api/v1/` |
| Staging | `https://chup.tech/api/v1/` |

## Traps that have already cost time

- **The API lives under `/api/v1/`.** The Laravel source registers only a bare `api` prefix; the
  `v1` is added at deploy time and appears nowhere in the repo. Get it wrong and every call
  returns a Laravel JSON 404 that reads like a wrong path.
- **A wrong password returns HTTP 200** with `{"error": true}` in the body. Status codes alone
  report success.
- **An expired token returns an HTML redirect**, not a JSON 401. Detect a leading `<`.
- **`GET user/visits/serving` is a paginated *list***, not an object. Parsing it as an object
  yields a junk visit with `id: 0` that renders as a blank row instead of throwing.
- **`is_*` flags come back as `0`/`1`**, not JSON booleans. Everything goes through `Visit._flag`.
- **Status labels arrive in Malay and English** (`"Tidak Hadir"` = `NO_SHOW`). Match the enum
  name, never the label.
- **Windows Developer Mode must be on** to build (Flutter needs symlinks for plugins).
- **Release builds are blocked locally by Smart App Control**, which blocks Flutter's unsigned
  `gen_snapshot.exe`. Debug builds use the JIT and are unaffected. Build releases in CI
  (`.github/workflows/`), not on a machine with SAC enforced.

## Layout

```
lib/core/     transport and state — verified against the live API, reuse it
  api.dart              endpoints, HTTP, login
  visit.dart            the model + parsing quirks
  limits.dart           LIMIT 20 / SERVE 15 / GRACE 5, and minutesSince()
  queue_controller.dart polling, derived figures, actions
  window_anchor.dart    corner anchoring; grows upward
  mock.dart             fixtures
lib/ui/       the design; this is what changes
design/       the spec, the prototype, and the backend gap analysis
```

## Rules the design treats as load-bearing

Change the visuals freely, but these are behavioural:

1. **The bottom 38px never moves.** Sizes and the hover reveal both grow *upward*, so the action
   target stays put under the cursor. That needs window repositioning, not just resizing —
   setting size alone grows a window downward.
2. **Exactly one action is ever visible.** ALERT, then START once called, then END VISIT. The
   backend only ends a visit that is SERVING, so START cannot be skipped. NO-SHOW only in the
   reveal, and only as a 550ms hold. It marks a real person absent and there is no undo.
3a. **Match states on the integer.** The API sends `state` as the enum integer and `state_name`
   as a translated label. `Visit.stateNames` maps one to the other.
3. **The resting line names the NEXT patient**, not the one in the room.
4. **Derive every minute from a timestamp and the clock.** Durations from the API freeze between
   polls; the widget must keep counting.
5. **Neither minimise nor close removes it from the screen.** There is no tray; Quit in the
   menu is the way out.

## Checking the backend

```bash
python tools/verify-backend.py --base https://chup.tech/api/v1/ --email <staff> --password <pw>
```

Reports which fields the widget needs are present or missing. Read-only, safe against staging.
Cloudflare fronts both hosts and 403s a default urllib user-agent — the script sets one.

## Still owed by the backend

`serving.started_at`, a `called` object with `called_at`, and `limits`
(`wait_minutes`/`grace_minutes`/`consult_minutes`). Until they land, the widget counts from when it first
saw the alert or the start, and uses 20 / 15 / 5 for limits. Details and suggested shapes in `design/BACKEND-WIRING.md`.

## Conventions

- Tokens live in `lib/ui/tokens.dart`; never hardcode a hex in a widget.
- `flutter analyze` must be clean and `flutter test` green before committing.
- Commit as the repo owner, on every machine (the WorkSpaces box defaults to `chup`):
  `git config --local user.name "Saad Arshad"` and
  `git config --local user.email "73756649+saadramay@users.noreply.github.com"`.