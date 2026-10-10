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
`flutter analyze` is clean and 32 tests pass.

**Latest: the red "No Material widget found" panel is fixed.** Build against a live backend,
sign in, and the reveal drew Flutter's red error box over the whole panel with a
`RenderFlex overflowed by 99914 pixels` banner underneath it. Cause: `Scaffold` only wraps the
route it is built in, so `home:`'s `Scaffold` covered the *first* screen and nothing else —
`Get.offAll(() => const WidgetShell())` (sign_in.dart) pushes a **new route** holding the bare
shell, with no `Material` above it. The size menu is a `PopupMenuButton` with a custom child,
which Flutter builds as `Tooltip → InkWell → child`, and `InkWell` asserts
`debugCheckHasMaterial`; the assert threw and the panel was replaced by the error widget, whose
unbounded text then overflowed a Row by ~99,000px. That second number is a *cascade*, not a
second bug — reverting the fix reproduces both in `test/material_ancestor_test.dart`. Fix:
`GetMaterialApp(builder: …)` puts one transparent `Material` above the Navigator, so it covers
every route, present and future. It only bit with the reveal open, because `_SizeMenu` lives in
`_Reveal`, which is not in the tree at rest.

Two more from the same session: `assets/chup-logo.svg` existed on disk but was missing from
`pubspec.yaml`, so `SvgPicture` threw `Unable to load asset` and drew nothing; and the sign-in
card now fits its window (see Still open for what that cost).

Five fixes worth knowing about. Four are guarded by tests; the two that live in window
setup are not, because a widget test has neither an OS window nor a `main()` to run —
verify those by measuring `GetClientRect` against `GetWindowRect` in the running app.

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
- The reveal's patient name is `maxLines: 1` with an ellipsis. The reveal's height is fixed
  by the window, so a name that wrapped pushed the NO-SHOW button off the bottom — measured
  42px past it for a three-line name. The resting line has always shortened names; this
  means the reveal ellipsises too once the name is wider than the panel.
- `QueueController` is registered before `runApp`, not inside the window-ready callback.
  `window_manager` types that callback `VoidCallback?` and invokes it as a bare
  `callback();` — an async closure therefore runs only to its first `await` and hands back a
  Future nobody awaits. `runApp` was building `WidgetShell`, which `Get.find`s the
  controller, before `Get.put` ran: **every warm start with a stored token threw
  "QueueController not found"** and left the window stuck on the error widget, since nothing
  marked the shell dirty once the controller did arrive. Only a cold start (sign-in) worked,
  which is why it went unnoticed.
- The window is **frameless** and the resting band is **38**, not 40. Both were needed:
  `titleBarStyle: TitleBarStyle.hidden` is *not* frameless — its `WM_NCCALCSIZE` handler
  insets 8px on the left, right and bottom (commented "required for resizing the window",
  window_manager #483), so `setBounds(216, 40)` produced a 200×32 view: 16px narrow, 8px
  short, plus an 8px dead zone that swallowed the cursor. The band at 40 also claimed 2px the
  column did not have at *any* size. Together they drew a red
  "BOTTOM OVERFLOWED BY 10.0 PIXELS" banner across the lead meter. `setAsFrameless()` has to
  come **after** `waitUntilReadyToShow`, or `SetTitleBarStyle` clears `is_frameless_` again.
  `test/resting_band_test.dart` guards the 38 at all three sizes and goes red on 40; the
  frameless half is verified by measuring the running app (both rects 216 × 40).

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

- **The sign-in card's height was a design call, and it was made without the designer.** The
  spec says 260 × 271 (design/README.md §1); measured against real Segoe UI the card needs
  260 × 312, so `kSignInHeight` is 312. Two things the spec's number predates: the logo was
  not rendering when the sheet was written (it was missing from `pubspec`, so `SvgPicture`
  drew nothing rather than its 28px), and the 271 was measured from the HTML mock rather than
  from Segoe at these sizes. The height is guarded by `test/sign_in_fit_test.dart`, which
  fails on 311 by 0.433px. **If the sign-in card should be 271 tall, that is a design
  decision to make by cutting content — not by lowering the constant back.**
- The 1150ms sign-in → widget morph and landing blink
- The ten-step first-run tour in Bahasa Malaysia (script is in the `.dc.html`)
- Sound coordination with the web app (local IPC — only one surface may own the sound)
- Windows startup registration (installer)
- The "Open in Chup" target URL
