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
`flutter analyze` is clean and 68 tests pass (layout tests skip off Windows).

**2026-10-11 audit fixes.** The API sends `state` as an integer, so states are matched on it,
not on the translated label. ALERTED counts as called without `called_at`. The action goes
ALERT, START, END VISIT, because `served` 404s on a visit that is not SERVING. Called and
serving times fall back to when the app first saw them. Failed actions show their reason. An
expired token returns to sign-in, and sign-out stops the controller. "Stay signed in"
unticked no longer writes the token. Backend `limits` are read. Positions count against the
session total. Booking times combine `date` and `time`. Polling backs off. Debug builds
default to staging. The morph, landing blink, tour, startup registration, Open in Chup and
Quit are built. CI signs the exe once certificate secrets exist.

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

**Four more, found by watching it run** (the log stayed clean for the last of these — it is a
logic bug, not an exception):

- **The offline line overflowed by 18px at *every* size.** `CANNOT REACH CHUP` beside
  `LAST READ …M AGO` needs 214px in a 196px band (216 − the shell's 1px border − 9px padding
  each side). Both strings were laid out at the Row's *full* width with a `Spacer` between
  them, so once the pair outgrew the band the Spacer collapsed to nothing and neither gave way.
  `_StatusLine` now lays the headline out first at whatever it needs and gives the trailing
  clock an `Expanded` that ellipsises into the remainder — the two can no longer sum past the
  Row at any width. Guarded by three new cases in `test/resting_band_test.dart`, red on the old
  code. It was invisible before only because nothing exercised `offline` *with* a trailing:
  drop `lastGoodPoll` and the trailing is simply not printed.
- **Windows clamps a 5×34 closed tab to a 136×39 minimum.** `setEdgeTab` and
  `setSizeKeepingBottom(44, 44)` therefore do not get the window they ask for, so the view is
  still 136×39 when the panel comes back — and one frame at that size is three errors: 116px of
  band against a 117px `NO ONE IN THE QUEUE`, `_ServingLine`'s row squeezed to 33px and
  overflowing by 62, and 39px of window against a 38px band plus a 1px border (the
  `overflowed by 1.00 pixels on the bottom` line). That is where the live log's
  `Row …:178 overflowed by 1.0 pixels` came from.

  Two changes, because the obvious one is not enough on its own: `QueueController.showPanel()`
  awaits `applyWindowGeometry()` *before* flipping `presentation`, and `WidgetShell` refuses to
  build `SliverPanel` at all unless its constraints are at least `kWidgetWidth × size.height`.
  Awaiting was tried first and still threw — `SetWindowPos` has already returned success by the
  time the Dart side resumes, while the view keeps reporting the old size for a frame or two
  afterwards. The guard reads `LayoutBuilder` rather than `MediaQuery`, because `MediaQuery`
  answers for the view, which in a widget test is the 800×600 test surface rather than the
  `SizedBox` the shell was pumped into.

  Guarded by `test/panel_size_guard_test.dart`: pumping the real shell at 136×39 is red on the
  unguarded code with exactly the logged `overflowed by 1.00 pixels on the bottom`, and green
  with it; a third case pumps at 216×40 to pin down that the guard hides nothing when the
  window *is* big enough.
- **The size menu collapsed the reveal it was anchored to.** `PopupMenuButton` pushes a route,
  and that route lands a full-screen barrier over the panel. The pointer has not moved, but the
  render tree has — so `MouseTracker` re-hit-tests and the panel's `MouseRegion` reports an
  exit while the menu is still open. Take that at face value and the window goes 158 → 40 with
  the menu open: 167px of menu items drawn into a 40px window, roughly one row of it and none
  of it clickable, and hover dead afterwards because the barrier swallows the pointer. This one
  never touched the log — it only shows up by clicking ⋯.

  Fix: `QueueController.menuOpen`, set from the button's `onOpened` / `onCanceled` /
  `onSelected`, makes `setRevealed(false)` a no-op for as long as it is true. Holding the
  reveal was only half of it, though — the reveal is 158px and the menu needs ~188px from the
  top of the window (a button 21px down, five 30px rows, a divider and the surface padding), so
  even fully open it clipped "Sign out" to an unreadable 8px sliver. `QueueController.windowHeight`
  is now the single place the window's height is derived, and it floors at
  `kSizeMenuWindowHeight = 212` while the menu is up; medium and large already outgrow that, so
  it only ever bites on small.

  Guarded by `test/size_menu_pin_test.dart`: red without the pin line
  (`Expected: true, Actual: <false>`), and it also pins `windowHeight` — the reveal's own
  height, the menu's floor, the floor released when the menu is down, and that a size which
  already outgrows the floor is not forced taller. The pin is deliberately temporary: the test
  asserts the reveal closes again once the menu is down, or the first use of the menu would
  leave it open forever.
- **The widget booted blank, dead and cursor-deaf whenever the stored size was not small.**
  `main()` sized the window to a hardcoded `Size(kWidgetWidth, 40)` — 40 being the *small*
  height — while the panel's size is persisted by the size menu (`_box.read('size')`). Pick
  large, restart, and you get a 208px panel asked to draw into a 40px window: the guard refuses
  (correctly), and since `applyWindowGeometry()` is the only thing that sizes the window and
  nothing was calling it, it stayed 40px **for good**. Transparent window, no hover, no click,
  nothing in the log — it looked hung rather than broken, which is why it hid for so long.

  Found by watching it fail, not by a test: the app came up empty twice in a row and the log was
  clean. Diagnosed by pausing the main isolate over the VM service (idle, so still alive) and
  then plugging a print into the guard — `GUARD: view=216.0x40.0 need=216.0x208.0`.

  Three changes: `QueueController.storedSize()` is now the single read of the stored size and
  `main()` starts the window at `storedSize().height` instead of 40; and the guard's other half,
  `reclaimGeometry()`, means a shell that cannot draw asks for the height it is missing rather
  than waiting for someone who never comes. Guarded by the fourth case in
  `test/panel_size_guard_test.dart`, which pumps the shell at 216x40 with `size = large` and
  asserts the shell asked.

Five earlier fixes worth knowing about. All five are guarded by tests. Three of the newer ones
above are too — but note which is not: nothing in a widget test can observe *when* the OS window
is resized, so `showPanel()`'s ordering is only load-bearing in combination with the guard, and
it is the guard the test pins down. The two `main()` window-setup fixes below remain unguarded
for the usual reason — a widget test has neither an OS window nor a `main()` to run — so verify
those by measuring `GetClientRect` against `GetWindowRect` in the running app.

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
- **Modern restyle** (2026-10-11): sentence case instead of all-caps micro labels, Semibold
  instead of Black weights, 12px panel / 8px control radii, buttons with icons ("Alert", "Start",
  "End visit"), token and position pills, a soft red hold-to-confirm No-show, a cleaner reveal,
  menu, sign-in card (now 336 tall) and tour card. Colours stay the Chup brand set; secondary
  ink is a cooler grey. Geometry and behaviour are unchanged. Supersedes the spec's type rules.
- **The panel sizes to its rows** (2026-10-11, after testing on the WorkSpace). Medium and Large
  are now maximums: a short session ends with the END OF SESSION row instead of holding the full
  height with empty paper above, and the reveal keeps its own 118px. Rows show time, token, full
  name and minutes (red past the wait limit), as the spec's rows do.
- **Tour step 7 copy changed** to describe START. A Malay speaker should review it.
- The tour card sits beside the panel, not in the opposite screen corner. That needs a second
  native window, and `desktop_multi_window` only does it with a forked `window_manager`, which
  would replace the package carrying the frameless and sizing fixes.
- Sound coordination: the widget makes no sound yet, so there is nothing to coordinate.
- Code signing needs `WINDOWS_SIGN_CERT_PFX_BASE64` and `WINDOWS_SIGN_CERT_PASSWORD` secrets.
- Backend: committed on chup.online `develop` as `577101b68` (staging once pushed). Not on `v1`,
  so production still lacks the fields; the widget uses its own observed times and default
  limits there until it lands.
- Live checks: CI's `window` job runs `integration_test/window_test.dart` in a real Windows
  window (boot at Large, menu at Small). Actions against staging: `tools/e2e-actions.py` with a
  staging login and two test patients.
