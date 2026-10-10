# Handoff: Chup Desktop Widget — redesign

## Overview

A rebuild of the Chup desktop widget: the always-on-top panel a doctor keeps in
the corner of their clinical screen while a hospital information system fills the
rest of it. It shows who is next, how long they have waited, and gives one action
— call the next patient, end the visit in the room, or mark a no-show.

The redesign replaces a 284×208 window (title bar, avatar, links) with a 216×40
sliver that carries more information in a third of the area. Everything the old
window put on screen permanently now appears under the cursor.

**The design to build is `2a` (`Sliver`).** Options `1a`, `1b`, `1c` are earlier
explorations kept as the record — their window controls are intentionally inert.
Do not implement them.

---

## About the design files

The files in this bundle are **design references written in HTML** — a working
prototype of the intended look and behaviour, not production code to lift.
Recreate them in the target codebase's own environment (Electron + React,
WinUI, Tauri, whatever the desktop shell is) using its established patterns.
The prototype is a single self-contained HTML document driven by a mock clock;
none of its state machine is meant to survive the port, only its behaviour.

Two things in the prototype are scaffolding, not design:
- **The mock clock.** One minute = two seconds, so durations are watchable.
  Ship at 60s. Seeded waits and time-served are capped so the mock does not
  saturate; real data is never capped.
- **The stand-in screen.** The grey 520×448 "HOSPITAL SYSTEM" frame is a
  placeholder for the real desktop. The widget is an OS-level always-on-top
  window positioned against the true screen edge.

## Fidelity

**High-fidelity.** Colours, type, spacing, geometry and timings are final and
measured. Build pixel-accurate. Every value below is taken from the prototype.

---

## Geometry

The widget is a fixed-width overlay window, 216px wide at every size. Height is
the only thing that changes.

| Size | Dimensions | Contains |
|---|---|---|
| Small (default) | 216 × 40 | Action band only |
| Medium | 216 × 128 | Action band + 4 queue rows |
| Large | 216 × 208 | Action band + 8 queue rows |

- Resting position: **12px from the right and bottom screen edges.**
- Border: 1px `#ebebeb`, radius 8px, background `#ffffff`. No drop shadow at rest.
- **The bottom 38px is identical at all three sizes and always sits the same
  distance from the screen corner.** Growing the panel adds rows upward. This is
  load-bearing: the action target never moves under the cursor.
- Queue rows are 20px each, separated by a 1px `#ebebeb` top border.
- The hover reveal opens *upward* from the top edge and needs ~112px of headroom.
- The ⋯ size menu needs ~136px of headroom and flips below the panel when there
  is not enough. The action band never flips.

---

## The three durations

These are the only numbers the design reasons about. All three are backend-owned.

| Constant | Value | Meaning |
|---|---|---|
| `LIMIT` | **20 min** | Wait threshold. A patient waiting longer is red. One flat figure for the whole queue — not per-patient. |
| `SERVE` | **15 min** | Default consultation length, **set per clinic per doctor**. A room past it is red. |
| `GRACE` | **5 min** | How long a called patient has before the widget suggests they are not coming. |

`LIMIT` and `SERVE` deliberately differ: twenty minutes waiting is a failure,
twenty minutes in consultation is often the job.

---

## Screens

### 1. Sign in — 260 × 271

Shown once per install. Centred on screen.

- Card: `#ffffff`, 1px `#ebebeb`, radius 8, padding 14, gap 9 between blocks.
- Window controls at top-right: `–` and `×`, 19×19, gap 1px.
- Chup logo (`assets/chup-logo.svg`), 74px wide.
- Title "Chup Desktop Widget" 13px/800, subtitle "Sign in to follow your queue"
  10.5px/500 `#4f4f4f`.
- Field label 8.5px/800, letter-spacing 0.08em, `#4f4f4f`. Input 30px tall,
  1px `#ebebeb`, radius 6, padding 0 9px, 11.5px/500, focus outline `#115934`.
- Password field has a SHOW/HIDE toggle, 8.5px/800, `#115934` → `#f26522` on hover.
- **One checkbox: "Stay signed in on this computer", default ON.** 13×13, radius 3,
  border `#cfd1d4` unchecked / fill `#115934` checked with a white tick.
  Labelled *stay signed in*, not *remember me* — remembering an email and never
  asking for a password again are different promises.
- Primary button 34px, radius 6, `#115934` (hover `#0d4728`), 12px/800 white.
- Footer line states the consequence of the tick, not the button:
  ticked → "Opens straight to your queue when this computer starts"
  unticked → "Opens when this computer starts, and asks for your password"
- Error state: "Wrong email or password" 10px/700 `#e03127`, above the button.
- **Startup is not a question.** On first successful sign-in the installer
  registers the app in the Windows startup list. Turned off in Windows'
  own Startup Apps list.

### 2. Widget at rest (Small) — the default

One 36px band + a 3px wait meter.

- Left block, padding-left 9px, two lines:
  - Line 1: shortened patient name 11.5px/600 `#1d1d1d` (ellipsised, flex 1),
    then position `3/10` 9.5px/800 `#4f4f4f`, tabular numerals.
  - Line 2: appointment time `3.30 PM` 10px/700, then minutes waited
    `44M WAITING` 9px/800 `#4f4f4f`, right-aligned.
- **The resting line is the NEXT patient — not the one in the room.**
- Right: the action button, **82 × 36**, radius 6, margin 2px.
- Bottom edge: 3px meter, green `#115934` up to `LIMIT`, red `#e03127` beyond.
  Tracks the same person the line names.
- **While a patient is called** the line shows `CALLED nM` instead of the wait,
  green until `GRACE`, then red — and the meter switches to tracking the grace
  window rather than the wait, because that is now the thing being waited on.

### 3. Hover reveal

Opens upward on `mouseenter`, closes on `mouseleave`. Adds a block above the
action band, separated by a 1px `#ebebeb` border, radius 7px 7px 0 0.

- Header row: label `NOW` 10px/800 `#115934` (or `CHUP` when there is no
  consultation), then the control cluster right-aligned.
- Patient's **full name, unabbreviated**, 19px/700, wrapping to as many lines as
  it needs. Only the resting line shortens names.
- Token `AD 126` 15px/800 `#0c6e3c`, position `3/10` 12px/800 `#4f4f4f`,
  `· SERVING 12M` 12px/800 — `#4f4f4f` under `SERVE`, `#e03127` over.
- **2px serving meter** beneath, green to `SERVE`, red beyond.
- When a patient is called, a hairline **NO-SHOW** button appears here carrying
  the called patient's name (see Actions).

**Control cluster** — five controls, 20×20 each, gap 1px, hover
`background: #edf7f3; color: #115934`:
1. **Grip** (6-dot glyph) — the only drag handle. `cursor: grab` / `grabbing`.
2. **Open in Chup** (arrow-out-of-box) — opens the full queue in the web app.
3. **⋯** — size menu (Small / Medium / Large), then Help, then Sign out.
4. **–** minimise.
5. **×** close. Hover `background: #f9e9e8; color: #e03127`.

### 4. Minimised and closed

Neither removes the widget from the screen. An always-on-top tool has no tray to
hide in, and a doctor who dismissed it mid-session would lose the queue.

- **Minimised**: 44 × 44 chip in the same corner. Shows the one number the
  resting line leads with (minutes waited, or minutes since a call), coloured
  green/red, with the same 2px meter across its bottom edge. Click restores.
- **Closed**: 5 × 34 tab, `#115934`, flush to the right screen edge at the same
  height, radius 3px on the inner corners. Hover widens to 9px and lightens to
  `#0c6e3c`. Click reopens. This is the system-tray equivalent.
- Both restore to the **same size and position** the widget had.

### 5. The four data states

Every state keeps the full title bar on hover — the controls are always reachable.
Each holds its size's height and puts its line in the same bottom 38px the action
occupies, with empty paper above.

| State | Line | Colour |
|---|---|---|
| `serving` | the normal panel | — |
| `empty` | NO ONE IN THE QUEUE | `#4f4f4f` |
| `offline` | CANNOT REACH CHUP · LAST READ nM AGO | `#e03127` / `#4f4f4f` |
| `loading` | READING THE QUEUE | `#4f4f4f` + 1px green sweep along the bottom edge |

### 6. First-run tour — 236px card

Ten steps plus a closing card, in **Bahasa Malaysia**. Sits in the opposite screen
corner from the widget and never covers it. Each step **drives the live panel**
into the state it describes and rings a 1.5px `#115934` hairline round the region
in question — every claim is the live thing, not a picture of it.

Runs once per install. `Help` in the ⋯ menu restarts it from step one.

Function names stay English throughout (`Alert`, `End Visit`, `No-Show`, `Help`,
`Sign out`, the three sizes, `NOW`, and the three self-appearing lines) because
that is what is printed on the button the doctor is being told to press. Industry
English also stays English: *queue, token, grip, reveal, undo, WhatsApp*.

Full script is in the Turn 3 table of `Widget Redesign.dc.html`.

---

## Actions

The action button has three faces. Only one is ever shown.

| Face | Colour | Trigger | Behaviour |
|---|---|---|---|
| **ALERT** | `#f26522` (hover `#dd5717`) | queue has a next patient | Single click. Sends the WhatsApp. |
| **END VISIT** | `#115934` (hover `#0d4728`) | a patient has been called | Single click. Ends the visit in the room, advances the queue. |
| **NO-SHOW** | `#e03127` | in the reveal, only while a patient is called | **Hold 550ms.** |

- 12px/800, letter-spacing 0.05em, white. `transform: translateY(0.5px)` on active.
- **Alert confirmation**: a bell glyph animates in (`bellIn` 180ms scale 0.45→1)
  and rings (`bellRing` ~900ms, rotate ±15° decaying) with two expanding wave
  arcs. No toast, nothing to dismiss.
- **No-Show is hold-to-confirm** because it writes to production and marks a real
  person absent, and there is no undo. The button fills red left-to-right over
  550ms; releasing early cancels. It carries the patient's name so there is no
  doubt who is being marked absent.
- **No-Show lives in the reveal, not at rest.** The button at rest is always the
  outcome you expect; the outcome you dread costs a hover and a hold.

## Dragging

- Only the grip starts a drag. Nothing else on the panel is draggable.
- The panel follows the cursor, clamped to the screen so it cannot be dragged off.
- **The clamp reserves the reveal's height (112px)** so the panel can never park
  somewhere the reveal would open past the top of the screen.
- Position persists across minimise, close and restore.

## Animations

| What | Duration | Easing | Notes |
|---|---|---|---|
| Sign-in → widget morph | **1150ms** | `cubic-bezier(0.45, 0.05, 0.2, 1)` | The card *is* the widget. 260×271 → 216×40, travelling to the corner it will live in. Shadow settles `0 14px 34px rgba(0,0,0,0.15)` → `0 1px 4px rgba(0,0,0,0.05)`. |
| — sign-in content fade out | same clock | linear | opacity 1 → 0 by 28% |
| — resting line fade in | same clock | linear | opacity 0 from 42% → 1 at 82% |
| Landing blink | **2600ms** | ease-out | Three green ring flashes in the first 50%, then a halo decaying to nothing. Fires once, first run only. |
| Tour opens | 800ms after landing | — | Arrive, then explain. |
| No-Show hold | 550ms | linear | fill sweep |
| Bell ring | ~900ms | — | |

**Implementation note that cost real time:** drive the morph and the blink with
the **Web Animations API** (`element.animate(...)`), not CSS transitions or
CSS keyframes. The widget re-renders on every clock tick; a transition gets
cancelled mid-flight and a CSS animation restarts from frame zero, so the box
sits still and then jumps. An animation handed to the element belongs to the
element and completes regardless of renders. Start the landing blink from the
render callback so it cannot fire before the panel is mounted.

## Sound

**Do not play the Alert or long-wait sounds while the Chup web app is open.**
Both surfaces watch the same queue and would fire on the same event a few hundred
milliseconds apart; the doctor hears a stutter and learns to distrust it.

Rule: **whichever surface is present owns the sound, and only one is ever present.**
Web app open → it keeps both sounds, widget silent. Web app closed → the widget
takes them over unchanged. Coordinate over a local channel (named pipe, lock file,
or a shared local server) — the widget can already tell whether the app is running.

First-run audio is separate and cannot clash: three short synthesised tones (no
asset files) — two falling as the card travels, one brighter tick on contact.

---

## What the backend must supply

### Poll

The widget polls the queue. `loading` on first read, `offline` after a failed
poll with the timestamp of the last good one.

```json
{
  "session": { "total": 10, "position": 3 },
  "serving": {
    "token": "AD 126",
    "name": "Ahmad Abu",
    "started_at": "2026-08-01T15:18:00+08:00"
  },
  "called": {
    "token": "HF 024",
    "name": "Kawthar Falah",
    "called_at": "2026-08-01T15:31:00+08:00"
  },
  "queue": [
    {
      "token": "HF 024",
      "name": "Kawthar Falah",
      "appointment_at": "2026-08-01T15:45:00+08:00",
      "waiting_since": "2026-08-01T15:05:00+08:00"
    }
  ],
  "limits": { "wait_minutes": 20, "consult_minutes": 15, "grace_minutes": 5 }
}
```

Notes:
- `called` is `null` when nobody has been called. Its presence is what switches
  the action button to END VISIT and reveals NO-SHOW.
- Send **timestamps, not durations.** The widget derives every minute figure from
  the clock so the numbers keep counting between polls and never freeze.
- `limits.consult_minutes` is per clinic per doctor.
- `queue` is the patients *behind* the next one, in order. The widget renders
  4 at Medium and 8 at Large, and marks the true end of the list when the session
  is shorter than the panel — an **END OF SESSION** row rather than empty paper.

### Actions

| Control | Request | Optimistic UI |
|---|---|---|
| ALERT | `POST /queue/alert` `{token}` | bell rings immediately; roll back and re-show ALERT on failure |
| END VISIT | `POST /queue/end-visit` `{token}` | queue advances immediately |
| NO-SHOW | `POST /queue/no-show` `{token}` | only fires after the 550ms hold completes |
| Open in Chup | opens the web app queue URL | — |
| Sign out | clears the stored session, returns to the sign-in card | — |

Poll cadence: whatever the web app uses. The widget shows staleness honestly, so
a slow poll degrades gracefully rather than lying.

### Persisted locally

```
session token          (only if "stay signed in" is ticked)
widget size            S | M | L
widget position        right, bottom offsets in px
first_run_completed    bool — gates the tour
```

---

## Design tokens

All from the Chup design system.

| Token | Hex | Use |
|---|---|---|
| `--chup-green-700` | `#115934` | Labels, END VISIT, meter green, rules, tour accent |
| `--chup-green-600` | `#0c6e3c` | Token numerals, display headings |
| `--chup-orange-500` | `#f26522` | ALERT only (hover `#dd5717`) |
| `--chup-red-600` | `#a82d2d` | Problem labels in documents |
| — | `#e03127` | NO-SHOW, overrun red (from the shipped widget) |
| `--chup-ink-800` | `#1d1d1d` | Body ink |
| `--chup-ink-500` | `#4f4f4f` | Secondary text, micro labels |
| `--chup-line-200` | `#ebebeb` | Every hairline |
| `--chup-line-300` | `#cfd1d4` | Unchecked control borders |
| `--chup-white` | `#ffffff` | Paper |
| `--chup-green-50` | `#edf7f3` | Control hover |
| — | `#f9e9e8` | Close-button hover |

**Type in the widget** is the Windows UI stack —
`'Segoe UI Variable Text', 'Segoe UI', system-ui, sans-serif` — not the document
faces. The widget is a Windows citizen; the documents are Chup stationery.

Sizes used: 19 / 15 / 12 / 11.5 / 10.5 / 10 / 9.5 / 9 / 8.5 / 6.5px.
Weights: 800 for every label and numeral, 700 and 600 for names, 500 for prose.
Letter-spacing: `-0.01em` on large numerals, `0.02–0.1em` on uppercase micro labels.
All numerals `font-variant-numeric: tabular-nums` so figures do not jitter as they tick.

Radii: 8px panel, 6px buttons and inputs, 3–4px small controls.
Hit targets: the action button is 82 × 36; control-cluster glyphs are 20 × 20
(acceptable for a mouse-driven desktop overlay, not for touch).

## Iconography

**Chup ships no icon set.** The bell, the grip dots and the open-in-Chup arrow are
**additions drawn from primitives** for this design — flagged deliberately, not
matched to a public icon library. If the codebase has an icon system, substitute
its equivalents rather than importing these.

## Assets

| File | From |
|---|---|
| `assets/chup-logo.svg` | Chup design system — the flat single-colour lockup with the tagline |
| `assets/mark/bubble.svg` | Chup design system — the orange bubble from the two-colour mark, used on the minimised chip |
| `assets/mark/letter-*.svg` | Chup design system — the remaining lockup pieces |

## Files

| File | What |
|---|---|
| `Widget Redesign.dc.html` | The full design document. Build from section **2a**. |
| `support.js` | Prototype runtime. Not part of the design; do not port. |
| `assets/` | Brand artwork listed above. |

### Reading the prototype

Open `Widget Redesign.dc.html` in a browser.

- **▶ PLAY FIRST RUN** (orange, in the review row under 2a) runs sign-in → morph
  → landing blink → tour.
- **TOUR ONLY** replays the ten steps on the panel.
- **SIZE / ACTION / STATE** buttons in the same row put the panel into any state
  directly.
- Hover the panel to open the reveal. Drag it by the grip.
- The rationale for every decision is written beside each option in the document
  itself — read Turn 2 before building.
