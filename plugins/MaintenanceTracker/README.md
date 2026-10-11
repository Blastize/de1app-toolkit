# Maintenance Tracker

**Backflush, descale, gaskets, burrs, water filter, bottle level. Counted from your shots, recorded with one tap.**
Version 0.31.1 · a plugin for the Decent DE1app · by Blastize

![The tracker list: every item with its counter and a green, amber or red bar](docs/trackers.png)

**Everything on one page.** Each tracker shows shots or days since it was last done and a bar that goes amber, then red. Backflush and descale record themselves when the machine runs a real clean or descale cycle.

![Tracker detail: a status card with the wear bar, the record history beside the linked cleaning profile and a green Start button](docs/detail.png)

**Tracker detail.** A status card with the same bar as the list, the history of records (tap one to remove it; Undo takes back the last), and the tracker's link: a profile, or the app's own Descale or Clean action, with what records it automatically. The green Start button opens the steps.

![Steps: six numbered instructions for a Cafiza backflush, with Mark done and a green Start button](docs/steps.png)

**Steps.** Numbered instructions for the job and one green button to do it. Edit steps (top right) lets you reword, add, remove and reorder them. For a cleaning profile, Start loads it, tells you to press the espresso button on the group head, and puts your espresso profile back when the run is done. Descale and Clean links open the app's own actions; anything else is marked done.

![Edit steps: numbered steps with Up, Down and Remove, and Cancel, Reset to default, Add step and a green Save](docs/step_editor.png)

![New tracker: name, count by days, shots or ml, threshold and icon](docs/new_tracker.png)

**Your own trackers.** A second grinder, a water tank clean, anything: name it, count by days, shots or millilitres, set the threshold, pick an icon.

![Edit tracker: name and link, due-after threshold and auto-record, icon](docs/edit_tracker.png)

**Edit any tracker.** Rename it, link it to a profile or the app's Descale or Clean, change the threshold, auto-record or icon. Nothing changes until Save.

## Recommended: the Lumen skin

![The Lumen taskbar: the wrench icon wears an amber dot because a tracker is due soon](docs/lumen_wrench.png)

Maintenance Tracker is built to remind you, and it works best with the [Lumen skin](https://github.com/Blastize/de1app-skin-Lumen). Lumen puts a **wrench** on its home-screen taskbar that wears an **amber dot** when a tracker is due soon and a **red dot** when one is overdue, so you see it without opening anything. One tap on the wrench opens the tracker list. Without Lumen the plugin still works, but you reach it through the app's Settings, Extensions and the plugin's settings button, and nothing tells you when something is due.

Both are in the [de1app-toolkit](https://github.com/Blastize/de1app-toolkit) download.

## Install

Copy the folder to `de1plus/plugins/MaintenanceTracker/`, restart the app, enable **Maintenance Tracker** under Extensions. Needs the SDB plugin (ships with the app).

## Safety

Counters come from read-only queries of the shot database; it is never written. The only file the plugin writes is its own settings file. Load profile uses the app's own profile call and never starts a flow. The one thing that can start the machine is a tracker linked to the app's Clean action, and only on a second, confirming tap.

<details>
<summary><b>Full reference and version notes</b></summary>

## Reference

A DE1app plugin that tracks espresso machine and grinder maintenance:
backflush, descale, group gasket replacement, burr cleaning, burr
installation (with a pre-history shot-count offset), water filter
changes, **water bottle level** (how much is left in the supply bottle,
measured from the machine's own dispense reports) — plus your own
**custom trackers** (a second grinder, a water tank clean, anything)
with their own name, unit and threshold.

Author: **Blastize** · Current version: **0.31.1** (one voice in the words)

## What it will do (target design)

- You record each maintenance event with one tap; the plugin stores only a
  timestamp and an optional note **in its own settings file**.
- Counters are derived by combining those timestamps with **read-only**
  queries against the SDB shot database: "N shots since X" and
  "N days since X".
- A silent status page shows green / amber / red per item — no automatic
  popups (the after-shot popup slot belongs to GrindAdvisor).
- A small public API (`status_summary`, `open_page`) lets the Lumen skin
  show a notification dot near a maintenance icon.

## What it does right now (v0.31.1 — one voice in the words)

- **One voice in the words** (v0.31.1): titles and buttons read in sentence
  case like the other plugins (New tracker, Edit tracker, Hide tracker,
  Undo last record, Yes, delete last record, Yes, remove this record,
  Delete tracker, Record maintenance); the Diagnostics page is titled
  just "Diagnostics" with the plugin name in the line under it; no
  double hyphens in any text (a full stop, brackets or a middle dot
  instead, e.g. "Nothing left. Change it now."); the auto toggle reads
  "Auto: clean cycle"; cut names end in a real ellipsis character. The
  Steps page's button reads **Record** like the list and the tracker page
  (it opens the same confirm; was "Mark done"), the app's cycles are
  always "clean cycle" / "descale cycle" ("Descale cycle (app)"), and a
  threshold of 1 reads "0 / 1 day". Start-up no longer saves the settings
  file; the first real change does. The meaning of every text and button
  is unchanged.
- **Text at its design size, dates you can read** (v0.31.0): every text was
  drawn at 92% of its size on the tablet; titles, tracker names, buttons and
  body text are now full size (captions were already). Dates read like the
  Lumen taskbar and follow its 12/24 h and date-order settings ("Last done
  Fri Oct 02 09:29 PM · 4 days ago"; the year only appears for last year's
  records); the history shows the date on the left and "recorded
  automatically · 4 days ago" on the right. The list counts "1–5 of 11
  trackers". OK / due soon / overdue use the colours the other plugins use,
  and the AUTO-RECORD / AUTO-COUNT tags are blue. Long names are cut with
  an ellipsis where they only get one line: the hidden-tracker chips, the Steps
  title and the Edit page's delete question. Diagnostics says "due soon"
  instead of "amber".
- **Buttons react to your finger** (v0.30.0): every button takes a slightly
  different tone the moment you touch it and returns to its colour a moment
  after its action, so a slow tap (opening a tracker, Confirm, Done) no longer
  looks missed. Green and red buttons press in their own colour, and a tracker
  card or an icon in the picker tints toward the button colour under your
  finger (lighter in the dark theme, greyer in the light one).
- **Clearer in both themes** (v0.29.3): buttons in the light theme have dark
  labels, and grey text and the status words (OK, DUE SOON, OVERDUE, NEVER
  RECORDED) now read clearly in the light and the dark theme; the sun / moon
  button repaints everything, button labels included.
- **Same pager as the other plugins** (v0.29.2): ◀ Prev / Next ▶ now sit at
  the bottom right of the tracker list (easier to reach), in the same place
  and style as Shot History Editor and Grind Advisor; Done, New tracker and
  Diagnostics line up from the left.
- **Easier to read** (v0.29.1): every section sits on its own card. A
  tracker's page shows its status card (the same bar as the list), the
  history beside the linked profile, the steps with green numbers, and the
  New tracker and Edit tracker pages in three cards each.
- **Remove any record** (v0.29.0): tap a line in a tracker's history; it
  turns red and the bottom button reads **Yes, remove this record** (tap
  another line to change your mind, Cancel to leave it). Removing an older
  record leaves the counter as it is; the newest is the usual Undo.
- **Your own steps** (v0.28.0): **Edit steps** (top right of a tracker's
  Steps page) lists its steps with **Up**, **Down** and **Remove**; tap a
  step to rewrite it, **Add step** for a new one (up to eight, one line
  each). Nothing changes until **Save**; **Cancel** drops the edits and
  **Reset to default** brings back the built-in steps. The "tap Start"
  line keeps following the tracker's link until you rewrite it.
- **Start, then back to your espresso profile** (v0.27.0): on a tracker
  linked to a cleaning profile, the Steps page's green **Start** remembers
  the profile you have loaded, loads the cleaning profile and shows
  "press the espresso button on the group head" (on a machine with a
  group head controller only the group head can start espresso). Your
  profile comes back by itself a few seconds after the run, when you tap
  **Switch back now**, 10 minutes after Start if the run never began, or
  at the next app start. It never switches while the machine is busy, and
  if you picked another profile in the meantime, that one stays. Start
  refuses when your current profile has unsaved changes.
- **Step-by-step instructions** (v0.26.0): every tracker's Detail page has a
  green **Start** button that opens its Steps page: numbered instructions
  and one green button for the job: **Load profile**, **Open Descale** or
  **Start Clean** for a linked tracker, **Record** otherwise (a linked
  tracker has Record beside it too; "Mark done" until v0.31.1). The steps come from a built-in
  library matched to the tracker's name (backflush with detergent or water,
  Rinza steam wand soak, descale, drip tray, water tank, drain, group head,
  burrs, water filter, water bottle, ball-joint grease, and a generic set),
  and the "how to start" step follows the tracker's link. Editing steps
  comes later.
- **Tidier Detail page, links on the Edit page** (v0.25.0): Link profile,
  Link Descale, Link Clean and Unlink moved to the Edit page, beside the
  name, and only take effect when you tap Save (Cancel undoes a stray
  Unlink). Detail shows the link in full with its one action, has a green
  **Record** button that comes back to Detail, and Undo last record is a
  normal button that turns red only after the first tap.
- **Worst first, properly** (v0.25.0): inside each colour, the tracker
  closest to due comes first.
- **Missing profile files are caught** (v0.24.1): Load profile first checks the
  linked profile's file still exists in `profiles/`; if not, it says "Profile
  file missing. Unlink and link it again." and leaves the app's profile alone.
  Link profile refuses a loaded profile that has no saved file.
- **A linked cleaning profile records its own tracker** (v0.24.0): when a
  run of a `cleaning` profile finishes, the trackers linked to *that*
  profile auto-record — and only those, even with their Auto-record
  source off. So "Backflush - Cafiza" linked to the Powder profile and
  "Backflush - Water" linked to the plain one each record their own run.
  A cleaning run of a profile no tracker links still records every
  tracker set to Clean cycle, as before. Such trackers wear
  **AUTO-RECORD** and the Detail page names the profile.
- **Link the app's Descale or Clean** (v0.23.0): the Detail row reads
  **Linked to:** and, while nothing is linked, offers **Link profile**,
  **Link Descale** and **Link Clean** (the two actions on the app's
  Settings > Machine > Maintenance tab). Linking one replaces any other
  link; **Unlink** removes it.
  - **Open Descale** shows the app's own "Prepare to descale" page,
    entered the way the app's own descale warning enters it (a fresh
    settings backup first, so its Cancel is safe). You still press the
    app's **Descale now**.
  - **Start Clean** asks first: the button turns into **Yes, start
    Clean** with a red reminder (blind basket and cleaning tablet in)
    for 8 seconds; the second tap starts the machine's clean cycle
    through the app's own call. It is refused unless the machine is
    connected and idle or asleep, and any page change, undo or unlink
    cancels the question.
  - The completed cycle still auto-records on trackers set to record
    Clean or Descale cycles, as before.
- **Linked profile** (v0.22.0): every tracker's Detail page has a
  **Profile:** row. **Link current profile** remembers the profile
  loaded in the app right now (load it once from the app's profile
  list, then tap); **Unlink** forgets it; **Load profile** hands it
  back to the app through the core's own `select_profile` (the same
  call DrinkMenu makes) and sends it to the machine a second later.
  It never starts a flow — the GHC does. So a Backflush alert is:
  wrench, card, Load profile, press the machine's espresso button,
  and the run auto-records that tracker (the profile must carry beverage
  type `cleaning`; since v0.24.0 only the trackers linked to it). Refused while the machine is running anything;
  the row's message line says what happened for four seconds.
- **Fast taps** (v0.21.1): the main page renders through cached canvas
  ids (DrinkMenu v0.6.2 mechanism) and plain navigation no longer
  re-runs the shot-database pass — counts refresh when something
  actually changed (recording, auto-detect, machine events, 10 min TTL).

- **Auto source chosen at creation**: the New tracker page has an
  "Auto: off / clean cycle / descale cycle" toggle in its top-right
  header corner, so a new tracker can auto-record from day one (still
  changeable later via Edit).
- **Two kinds of AUTO, told apart**: cards wear **AUTO-RECORD** when
  the tracker resets itself after a detected Clean/Descale cycle, and
  **AUTO-COUNT** when its shots/ml counter climbs by itself while
  recording the maintenance stays a manual tap (e.g. a water-supply
  tracker meters every ml dispensed, but you still tap Record when
  you swap the bottle). Fully manual trackers (days, no source) have
  no tag. The Detail page says it in words: "Auto-records on: …" or
  "Counts automatically: every espresso shot / all water dispensed".

- **Human relative time**: the "Last done" line on cards and Detail
  pages now reads "(just now)", "(N minutes ago)" up to 59, "(N hours
  ago)" up to 23, then "(N days ago)" — no more "(0 days ago)" on the
  day you actually did the task.
- **Choosable auto-record sources**: every tracker — built-in or
  custom — has an **Auto-record** row on its Edit page that cycles
  **off → clean cycle → descale cycle**. A completed Clean cycle (or a
  blind-basket backflush run as a "cleaning" espresso profile) and a
  completed Descale cycle now auto-record *every* tracker subscribed
  to that source, not just the fixed Backflush/Descale pair — so your
  own "group head clean" tracker can tick over automatically, and you
  can turn auto-recording off for a built-in. Existing installs keep
  exactly the old wiring (Backflush ← Clean cycle, Descale ← Descale
  cycle) until you change it.
- **Auto trackers are marked**: the accent-colored tag sits on the
  card under the counter (AUTO-RECORD / AUTO-COUNT since v0.21.0),
  the Detail page names what is automatic, and Diagnostics shows how
  many trackers each cycle detector feeds.

- **Dark mode**: a sun/moon button in the main page's top-right corner
  switches the whole plugin between light and dark instantly — every
  page repaints on the spot, and the choice is remembered across
  restarts. Buttons darken with the theme (v0.19.1); state colors
  (green/amber/red) and the red danger buttons are the same in both.

- **One consolidated tracker model**: every tracker — built-in or
  custom — can be **edited** (name, threshold, icon; the counting unit
  stays locked so history keeps meaning what it meant) and **hidden**
  (at most 6 at once, matching the 6 restore chips on the New tracker
  page; the Hide button disables with an explanation at the cap).
  Built-ins cannot be deleted — hiding is their reversible retirement,
  which protects the auto-record, burr-offset and water-meter wiring —
  while custom trackers delete from the bottom of their **Edit** page
  behind the same two-step "Yes, delete tracker" confirm.
- **A written button standard** (see the implementation header) now
  governs every page: bottom-left is always safe navigation
  (Done / Back / Cancel — and while a destructive confirm is armed, it
  disarms first); bottom-right is the page's one positive action
  (Save / Confirm); destructive actions (Undo, Delete) are red,
  two-step with explicit "Yes, …" labels, and separated from safe
  buttons by at least a button-width of empty space; Edit sits in the
  Detail page's top-right header slot; Prev/Next are paired top-right
  and disable at the ends. Buttons wear text labels, not icons.

- **Water bottle tracking in millilitres**: the machine reports how much
  water every operation dispenses (espresso, steam, hot water, flushes,
  clean and descale cycles); the plugin accumulates this into a lifetime
  water meter whenever an operation completes. The built-in **Water
  bottle** tracker counts that meter against the bottle size (default
  18.9 L = 5 US gal): its card shows "used / size" in litres, **"About
  X L left"**, and the wear bar fills as the bottle empties. Tap Record
  when you attach a fresh bottle — the confirm page also carries
  ±100/±1000 ml steppers to adjust the bottle size, and Undo restores
  the previous bottle's baseline. The meter only runs while the app is
  running (which commands every flow, so in practice that is complete),
  and it is the machine's flow *estimate* — expect a few percent drift,
  so treat "due soon" (80%) as the swap signal. Custom trackers can also
  pick the **ml** unit, e.g. a water filter tracked by real throughput.
- **"Service Bay" cards**: every tracker card shows a state-tinted icon
  plate (glyphs from the Font Awesome 6 Pro font the app already
  ships), the state word in color, a right-aligned counter, a segmented
  wear bar with a tick at the amber threshold, and the last-done date.
  The list sorts **worst first** (overdue → due soon → OK → never
  recorded; within each, closest to due first), so what needs attention
  is always on page one.
- **Icon picker**: when adding (or editing) a tracker you pick its icon
  from **two rows of twelve** — wrench, hot mug, beans, filter,
  droplet, drip-tray grate, O-ring, steam wand, faucet, water tank,
  stopwatch, spray can / water bottle, drain pipe, ball joint, pressure
  gauge, scale, thermometer, gears, flat gasket, descale, calendar
  check, bell, star. Two of these — the **steam wand** (a spout
  blasting steam) and the **flat gasket** (the O-ring squashed flat) —
  are not font glyphs at all: the FA font has no honest version of
  either, so the plugin draws them itself as stroke graphics that
  recolor with the state tint like every other icon. The "Icon:" line
  names the current selection (e.g. "Icon:  Steam wand") so every pick
  has a meaning, not just a shape. A tracker whose
  stored icon is no longer offered keeps rendering it, and editing
  such a tracker never swaps the icon unless you pick a new one.
- **Detail page icon**: opening a tracker shows its icon top-left on a
  state-tinted plate, matching its card.
- **Hide / restore trackers**: every tracker's Detail page has a Hide
  tracker button — hiding removes it from the card list and the status
  rollup (it can no longer light the skin's dot) while keeping all its
  data. The New tracker page shows one chip per hidden tracker — tap a
  chip to restore just that one. At most 6 trackers can be hidden at
  once. **Burr install starts hidden** (burrs last ~30k shots — not a
  routine maintenance item; restore it if you want it back).
- **Edit any tracker**: the Edit button on every Detail page changes
  the tracker's name, threshold and icon — the history and the
  counting unit (days, shots or ml) stay as they are. Custom trackers
  additionally have Delete tracker at the bottom of their Edit page
  (two-tap confirm).
- **Custom trackers**: the New tracker button (bottom center of the
  main page) creates your own named tracker — e.g. "Grinder 2 burr
  clean" — counting days, shots or ml against a threshold you set with
  stepper buttons. Custom trackers appear as cards after the built-ins
  and use the exact same Record / history / Undo flows, and they feed
  the Lumen notification dot like every other item. They start
  manual-record only — attach a Clean/Descale auto source from their
  Edit page if you want one. Built-in items can never be deleted.
  **Note:** a
  shot-based custom tracker counts *every* shot on the machine — the
  shot database cannot tell which grinder pulled which shot — so
  prefer days for gear that does not see every shot.
- **Auto-recording**: running the machine's own Clean or Descale program
  records every subscribed tracker automatically once the cycle
  completes (aborted cycles are ignored via duration thresholds), and a
  blind-basket backflush run as a "cleaning" espresso profile counts as
  a Clean cycle (since v0.24.0: for the trackers linked to that profile,
  or, when none is, every Clean-cycle tracker). Which trackers subscribe to which cycle is set per
  tracker on its Edit page (v0.20.0). Auto events appear in the Detail
  page history as "recorded automatically" and can be undone exactly
  like manual ones. Turn the whole feature off with the `auto_record`
  setting; thresholds are tunable in settings and shown on Diagnostics.

- Every maintenance item keeps an **append-only event log** (newest 20
  kept). Recording appends an event; the familiar `last_done` is derived
  from the log, so all counters behave exactly as before. Settings from
  v0.4.x migrate automatically the first time v0.5.0 loads.
- **Tapping a card's text area** (anywhere left of its Record button)
  opens a per-item **Detail page**: current state and counter, the 5
  newest events with date and how they were recorded, and — when at
  least one event exists — an **Undo last record** button (red once armed). Undo
  asks for confirmation on the same page, showing exactly which record
  will be removed and what the counter falls back to; confirming pops
  just that one event and returns to the card list.

- Appears in Settings → App → Extensions as "Maintenance Tracker".
- The main page is a **card list** (5 cards per page, Prev/Next paging):
  one card per maintenance item with a green/amber/red state dot (grey =
  never recorded), the current count ("12 of 30 shots since last done" /
  "41 of 90 days"), the last-done date, and a **Record** button.
- **Record** opens a confirmation page ("Record X as done now?" with the
  current counter shown); Confirm sets the item's last-done time to now
  and restarts its counter, Cancel changes nothing. **Burr install** has
  its own confirmation page with a "shots already on these burrs" offset
  entered via −100/−10/+10/+100 stepper buttons (no on-screen keyboard).
- A **Diagnostics** page shows everything detected: database path, open
  status, detected table and columns, raw/counted/excluded row counts,
  whether the cleaning filter is active, and the exclusion keyword lists.
  Back returns to the settings page.
- The count SQL avoids SQLite's `lower()` entirely (this tablet's
  AndroWish SQLite fails it with an ICU link error; `LIKE` is already
  case-insensitive for ASCII), and if the exclusion filter ever fails,
  counting falls back to unfiltered rows instead of going dark — flagged
  on Diagnostics.
- `::plugins::MaintenanceTracker::status_summary` is real: it returns
  `ok 1`, the overall worst state (`ok`/`amber`/`red`), and a per-item
  dict (state, value, threshold, unit, days_since, shots_since). Results
  are cached; the cache is invalidated silently after each completed
  flow and by a 10-minute TTL, so fast skin polling never hits the
  database. Day-based items keep working even if the database is
  unavailable (shot-based items report `unknown`).
- Counting rules: **raw** shot-table rows (soft-deleted/archived shots
  still count — they physically ran), minus a defensive exclusion of
  cleaning-type rows (`beverage_type` in cleaning/calibration/test/
  testing, or `profile_title` containing rinse/flush/backflush/clean/
  descale/calibrat), applied only to columns that actually exist.
- Table and columns are detected dynamically (ordered regex patterns,
  GrindAdvisor mechanism) — no fixed schema is assumed.

## Safety

- **SDB access is strictly read-only**: the plugin opens its own sqlite3
  handle with `-readonly true` and the only SQL shape it ever issues is
  `SELECT COUNT(...)` (plus schema inspection via `sqlite_master` /
  `PRAGMA table_info`). It never reuses or blocks the app's own handle.
- **History files (`history/`, `history_v2/`) are never touched by this
  plugin, in this or any future version.**
- No popups, no automatic UI. Two silent listeners: `after_flow_complete`
  (marks the counter cache stale; a finished cleaning-profile run
  auto-records) and `on_major_state_change` (a real clean or descale
  cycle auto-records; the water meter adds each finished flow).
- The only file of ours written is
  `plugins/MaintenanceTracker/settings.tdb`, via `plugins save_settings`,
  never at start-up (v0.31.1). It is saved after a tap (**Confirm** on a
  Record page; **Save** on New tracker, Edit tracker and Edit steps;
  **Hide tracker**; a restore chip; the sun / moon theme button;
  **Start** on a profile-linked tracker, which remembers the profile to
  bring back, and **Switch back now**; the removals below) and by itself
  (one auto record per real cycle or cleaning-profile run, off with
  `auto_record`; the water meter; clearing a finished switch-back).
- Removing data always takes two taps: **Undo last record**
  then **Yes, delete last record** (the newest record); a history row
  then **Yes, remove this record** (any other record, kept in
  `last_removed_event`); **Delete tracker** then **Yes, delete tracker**
  (custom trackers only, kept in `last_deleted_custom`). No bulk delete
  or reset anywhere.
- App-facing actions: **Start** on a profile-linked tracker loads the
  cleaning profile through the core's `select_profile` (then the core's
  `save_settings` + `save_settings_to_de1`) and switches back the same
  way; **Open Descale** shows the app's own descale page (`show_settings
  descale_prepare`, never `start_decaling`); **Start Clean** is the
  **only machine cycle this plugin can start**: the core's
  `start_cleaning` on the second tap within 8 seconds, refused unless
  connected and idle or asleep. Profile files are only read.

## Install

Copy the folder to the tablet as:

```text
de1plus/plugins/MaintenanceTracker/
```

(never nested as `MaintenanceTracker/MaintenanceTracker/`), then restart
the DE1app by hand and enable it under Settings → App → Extensions.

## Files

- `plugin.tcl` — manifest: metadata, settings defaults, framework hooks.
- `MaintenanceTracker.tcl` — implementation: layout tokens, navigation,
  settings page, public API.
- `filelist.txt`, `README.md`, `CHANGELOG.md` — docs.
- `settings.tdb` — created at runtime by the app; not part of the package.

</details>
