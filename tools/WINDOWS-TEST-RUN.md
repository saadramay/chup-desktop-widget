# Windows test run, real data on staging

For a Claude Code session on the Windows WorkSpace. The widget was fixed on a Mac that cannot run
it. Your job is to prove it on Windows against **staging with real data**, and report back. You
are testing, not developing: do not change app code, do not commit, do not push.

## Rules

- **Staging only.** Base URL `https://chup.tech/api/v1/`. Never point anything at `chup.online`.
  Debug builds default to staging; do not pass a `BASE_URL` define at all.
- **Alert sends a real WhatsApp.** Act only on visits the user names as test patients (their own
  phone). Ask for the visit IDs; never pick patients yourself.
- **No-Show has no undo.** Only on the test visit the user names for it.
- Ask the user for the staging staff email and password. Do not write them to any file.
- If something fails, record it and carry on with the next check. Do not fix code.

## 1. Get the code

```powershell
cd D:\Users\chup\Downloads\chup-desktop-widget
git status            # only windows/flutter/generated_* may show (CRLF noise); anything else, stop and tell the user
git checkout -- windows/flutter
git pull --ff-only origin main
git log --oneline -3  # tools/WINDOWS-TEST-RUN.md (this file) must exist
flutter pub get
```

Windows Developer Mode must be on (plugin symlinks). Debug runs work under Smart App Control;
release builds do not, so build nothing in release here.

## 2. Automated checks

```powershell
flutter analyze
flutter test
flutter test integration_test -d windows --dart-define=MOCK=true
```

Expect analyze clean and every test passing. On Windows the Segoe UI layout tests run (they skip
on the Mac). The integration test opens a real window with fixtures: boot at Large, menu at Small.
It is the only fixture-based step; everything after this uses real data.

## 3. Backend on staging (read-only)

```powershell
python tools/verify-backend.py --base https://chup.tech/api/v1/ --email <staff> --password <pw>
```

The account needs patients in its queue today. Expect `limits` present, and `called_at` /
`started_at` present on visits that have been alerted / started (backend commit `577101b68` on
chup.online develop).

## 4. The app against staging

```powershell
flutter run -d windows
```

Sign in with the staff account. Check each, and note PASS / FAIL with what you saw:

1. Window lands 12px from the bottom-right corner, 216 wide, no red error boxes.
2. Resting line names the **next** patient (not the one in the room), position `n/total` reads
   sensibly, minutes waiting count up every minute without a poll.
3. Appointment time shows the real slot, not `12.00 AM`.
4. Hover opens the reveal upward; the bottom band does not move.
5. Size menu (⋯) at Small: all six items visible (Small, Medium, Large, Help, Sign out, Quit) and
   the reveal stays open under the menu. Medium and Large show the queue list.
6. Quit the app with Large selected, run again: it comes back at Large, not blank.
7. Minimise to the chip and restore; Close to the edge tab and restore.
8. Drag by the grip. If there is a second monitor, drag there, change size, it must stay there.
9. "Open in Chup" (arrow icon) opens `https://chup.tech/live-queues` in the browser.
10. Help replays the tour; every step's text fits, the ring sits on the region described, and
    pressing the action button during the tour does nothing.

Then the actions, **only on the test visit the user names**:

11. ALERT on the test patient: bell rings, the line switches to `CALLED nM`, button becomes START.
12. START: patient moves to NOW in the reveal with `SERVING nM`, button becomes END VISIT.
13. END VISIT: visit leaves the panel.
14. Failure path: with someone already serving, ALERT then START another test patient. The
    resting line must show the server's reason in red for a few seconds.
15. No-Show, on the second test visit only: ALERT it, open the reveal, **hold** NO-SHOW. A single
    click must not fire; the hold must. The visit leaves the panel.
16. Sign out: window shrinks back to the centred sign-in card. Untick "Stay signed in", sign in,
    quit, run again: it must ask for the password.

Cross-check states in the web app at `https://chup.tech/live-queues` as you go.

## 5. Scripted actions (optional, two more test visits)

```powershell
python tools/e2e-actions.py --email <staff> --password <pw> --visit-a <id> --visit-b <id> --yes
```

## Report

Write `tools/windows-test-report.md` (do not commit it) and also paste it to the user:

- Git commit tested, Windows version, screen scaling.
- Each numbered check: PASS / FAIL, and for every FAIL what you saw, plus the console error if
  any (`flutter run` prints them).
- Output of steps 2, 3 and 5.

If this session has Remote Control, also message the report to session `chup-online-4f`.
