# Maintenance Tracker - Changelog

Entries follow the CLAUDE.md doc cap (~15 lines each; entries that added or
changed a write capability keep their full write-path description). The long
pre-trim entries survive in the Desktop archive snapshot of each version.

## v0.23.1 - 2026-09-23 - Pass 28: stale show hooks no longer repaint - verify.sh PASS 2026-09-23 on run 1 (three page dumps + logcat clean; list page renders in full; owner re-tap of Open Descale open)

Base: v0.23.0. Owner, tablet screenshot 23:09: Open Descale shows the app's
"Prepare to descale" page with MT's Prev / Next buttons painted on top.

- Cause: dui runs page show hooks `after idle` (dui.tcl ~6705) but sets the
  current page at once (~6487). Leaving for the app's page closes Detail
  (queues the list page's show), closes the list and loads descale_prepare
  in one tap; the queued list show then refreshed and its Prev / Next
  `-state normal|disabled` calls made them visible over the app's page.
  Start Clean shared the path (stray buttons on home after the cycle).
- Fix: the list and Detail `show` hooks still reset their flags, then skip
  the refresh unless their page is current.
- pass_28_offline.tcl replays the tap with an after-idle queue: it FAILS on
  the v0.23.0 archive and PASSES here.

**Safety status: no write behavior changes; display-only guard. Link
writes and the Start Clean confirmation are exactly as in v0.23.0.**

## v0.23.0 - 2026-09-23 - Pass 27: link the app's Descale or Clean action - verify.sh PASS 2026-09-23 on run 1 (settings, detail, diagnostics dumps clean; logcat clean; link row proven offline incl. geometry; owner checklist open)

Base: v0.22.0 (verify.sh PASS, on the tablet). Owner request: a tracker may
link the app's own Descale or Clean (Settings > Machine > Maintenance)
instead of a profile.

- Item dict gains optional `link_kind` descale | clean. Linking any kind
  clears the others; Unlink (`unlink_profile`, name kept) removes
  `profile_fn`, `profile_title` and `link_kind`. `_item_profile` reads ""
  under a Descale / Clean link. `status_summary` unchanged.
- Detail row "Linked to:". Unlinked: value "none" + [Link profile] [Link
  Descale] [Link Clean], all btn_w_std (240-wide ones ran over the value:
  caught by the new offline geometry check). Linked: [Unlink] + the action
  button relabelled (bare tag): Load profile | Open Descale | Start Clean.
- Open Descale: busy guard, leave MT's own dialogs one close_dialog per
  level, then the core's `show_settings descale_prepare` -- the app's own
  descale-warning entry (standard_includes.tcl:32). It backs settings up
  first, so the stock Cancel -> Machine tab -> Cancel restores CURRENT
  settings (a bare page switch would restore a stale backup). The user
  presses the stock "Descale now"; MT never calls `start_decaling`.
- Start Clean: refused unless connected and not busy. First tap arms for
  8 s ("Yes, start Clean" + red reminder); the second leaves MT's dialogs
  and calls the core's `start_cleaning` (the Machine tab Clean button's
  call). Timeout, page show, undo-confirm and Unlink disarm.

**Safety status: FIRST capability in this plugin that starts a machine
cycle -- the clean cycle, via the core's `start_cleaning`, only on the
second tap of an 8 s confirmation, connected and Idle/Sleep/GoingToSleep
only. One new settings.tdb key (`link_kind`), written on the Link Descale /
Link Clean / Unlink taps through the existing `save_settings`. Descale is
never started by MT. SDB stays read-only; history/ untouched.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE,
passes/MaintenanceTracker/pass_27.md, pass_27_offline.tcl, pass_27.checks.json.

## v0.22.0 - 2026-09-18 - Pass 26: linked profile per tracker - verify.sh PASS 2026-09-18 12:2x (settings, detail, diagnostics dumps: no text overlap, inside the virtual canvas; logcat clean; tap behaviour proven offline, owner checklist open)

Base: v0.21.3 (tablet-verified). Owner request: a backflush alert should
offer the cleaning profile instead of a trip through the app's chooser.

- Detail page: a "Profile:" row under the history (buttons at 520..580
  ref px, the message slot moved 600 -> 624). Unlinked: "Link current
  profile" stores `::settings(profile_filename)` + `profile_title` in the
  tracker's item dict (DrinkMenu's "use current" capture). Linked: the
  title, "Unlink", and "Load profile" -- DrinkMenu v1.16.0's To-machine
  tap copied: busy guard, `::select_profile <fn>`, `-1` = file missing,
  1 s debounced `save_settings; save_settings_to_de1`. The row's buttons
  hide while an undo is armed. Outcomes show in the message slot for 4 s.
- `status_summary` shape unchanged (entries are built from named keys).

**Safety status: two NEW settings.tdb writes, each on an explicit tap
(Link current profile, Unlink) through the existing `save_settings` path;
Load profile changes the app's loaded profile via the core's own
`select_profile` and never starts a flow. SDB stays read-only; history/
untouched.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE,
passes/MaintenanceTracker/pass_26.*.

## v0.21.3 - 2026-09-15 - Pass 25: idempotent SDB close

Base: v0.21.2 (tablet-verified). Tablet log 2026-09-15 21:44:39:
`ERROR: BLE error info invalid command name "::plugins::MaintenanceTracker::sdb"`
while executing `$db_handle close`.

- Cause: `_close_db` ran a bare `catch { $db_handle close }`. The handle
  is closed after every refresh and closed again before every open, so
  the second close failed every refresh; catch swallowed the error but
  left `$::errorInfo` dirty, and the core BLE runner prints `$::errorInfo`
  whenever a queued command returns non-1 (de1_comms.tcl:120).
- Fix: `_close_db` closes only when `info commands $db_handle` exists and
  logs a real close failure via `msg` instead of hiding it. Both close
  sites (before open in `_open_ro_db`, after refresh in `_refresh_status`)
  go through it; no code path touches the handle after close.

**Safety status: no write behavior changes; SDB stays read-only.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.21.2 - 2026-09-03 - Pass 24: unique button tags (DrinkMenu press bleed)

Base: v0.21.1 (tablet-verified). Owner report: after visiting DrinkMenu,
MT's Done button wore DrinkMenu's yellow until a theme toggle.

- Cause: Tk canvas tags are canvas-global and the core's press flash
  (dui.tcl:9181) itemconfigures bare `<tag>-btn` -- pressing DrinkMenu's
  `bar_done` (style with -pressfill) repainted every `bar_done-btn` on
  the canvas, including ours, restoring to DrinkMenu's fill.
- Fix: the five tags both plugins used are now mt_-prefixed: mt_done,
  mt_back, mt_cancel, mt_save, mt_hide (creation, retheme list, detail
  mode show/hide, edit-page delete/save toggle). No other tag collides
  with any installed plugin's pressfill-styled buttons.

**Safety status: no write behavior changes; canvas tag rename only.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.21.1 - 2026-09-03 - Pass 23: main-page tap responsiveness

Base: v0.21.0. Owner report: buttons lag. Same disease DrinkMenu v0.6.2
measured (~1 ms per `dui item` call; the card refresh made ~330).

- DrinkMenu's cached-canvas mechanism ported: `_ids` (canvas ids resolved
  once), `_set_vis` (raw show/hide keeping `st:hidden` in sync), `_cfg`
  (dedup'd itemconfigure). Settings-page refresh, vector icons and
  `_apply_item_icon` (Detail header too) now render through them.
- SDB schema detection cached per session (`_schema_cache`); dropped and
  re-detected on any read error.
- Main page `show{}` no longer forces a full SDB pass: every mutating path
  already invalidates, machine events too, 600 s TTL backstop. Diagnostics
  keeps fresh-on-open. Timing line behind `debug_timing` (default 0).

**Safety status: no write behavior changes; internal rendering + read-path
caching only. SDB stays read-only SELECT; history files never touched.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.21.0 - 2026-09-01 - Pass 22: auto choice at creation + auto-count tags

Base: v0.20.0 (owner-confirmed). Owner follow-ups.

- New Tracker page: header-slot toggle cycles Auto: off -> Clean cycle ->
  Descale cycle; `add_save` stores it, `open_add` resets it; title wrap
  trimmed clear of the button. Source stays editable on the Edit page.
- Card tags via `_item_auto_kind`: AUTO-RECORD (auto source set) vs
  AUTO-COUNT (shots/ml unit counting by itself, recording manual); days +
  no source = no tag. Detail: "Auto-records on: X" / "Counts automatically:
  every espresso shot | all water dispensed".
- Fix: Edit page's Auto-record Change button joined the live retheme list.
- Offline harness: 50 checks, all green.

**Safety status: no new write behavior. `auto_src` chosen at creation rides
the existing add_save settings.tdb write; SDB read-only SELECT COUNT;
history files never touched.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.20.0 - 2026-09-01 - Pass 21: relative time + choosable auto-record sources

Base: v0.19.1. Owner requests: minutes/hours/days captions, tell auto and
manual trackers apart, choose auto sources for custom trackers.

- `_fmt_ago`: "just now" / "N minute(s)" / "N hour(s)" / "N day(s) ago" on
  every Last-done line (cards + Detail); day counters unchanged.
- Every item dict gained `auto_src` ("" | clean | descale), validated in
  `apply_defaults`; one-time idempotent migration seeds Backflush <- clean
  and Descale <- descale, everything else off (behavior unchanged until
  edited). The two cycle detectors (Clean-state exit >= threshold, incl.
  cleaning-profile espresso backflush; Descale-state exit >= threshold)
  dispatch via `_record_auto_src` to EVERY subscribed tracker instead of the
  hardwired ids. Hidden trackers still auto-record.
- Edit page "Auto-record" row (Change button cycles off -> Clean -> Descale)
  for ANY tracker, persisted by the ordinary Save (`edit_save` writes
  `auto_src`); no-ops while a delete is armed. New trackers created manual.
- Cards show an accent AUTO tag under the counter; Detail appends
  "Auto-records on: ..."; Diagnostics row shows per-source subscriber counts.
- Offline harness: 45 checks, all green.

**Safety status: no new write behavior. Writes remain confined to the
plugin's own settings.tdb on the existing paths: explicit taps plus one
`source auto` event per completed real cycle, now per subscribed tracker,
still gated by the `auto_record` toggle, the duration thresholds and the
30 s dup guard. SDB read-only SELECT COUNT; history files never touched.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.19.1 - 2026-08-28 - dark buttons + a real sun

Base: v0.19.0. Owner follow-ups: buttons should go dark too; better sun icon.

- Dark-mode toggle face is `sun-bright` (owner picked from a rendered sheet;
  plain FA `sun` looks like a shuriken).
- `btn_fill` / `btn_disabled_fill` moved into the palette (dark #4a5473 /
  #3a3e4a). `_retheme_all` restyles every normal-style button live via its
  `${tag}-btn` shape tag (all face segments carry it; `dui item config`
  hits every match). Danger red, white labels and invisible tap zones are
  never touched (explicit per-page button lists).
- Offline harness: 246 checks.

**Safety status: pure UI patch; write behavior identical to v0.19.0.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.19.0 - 2026-08-28 - Pass 20: dark mode

Base: v0.18.0. Owner request: sun/moon toggle, instant switch.

- All non-state colors flow from `_apply_palette` (light/dark per
  `settings(theme)`); state tints recompute from the card color. Harness
  enforces each themed literal appears exactly once in the source.
- Sun/moon button (top-right header) -> `toggle_theme`: palette swap ->
  `_retheme_all` repaints every page's static items by bare tag -> main
  page refresh. Other pages repaint on their own show-refresh.
- Identical in both themes: ok/amber/red state colors and button faces
  (buttons followed in v0.19.1).
- Theme persists in `settings(theme)` (default light; unknown heals to light).
- Offline harness: 238 checks.

**Safety status: the ONE new write is `settings(theme)` into the plugin's
own settings.tdb on each explicit toggle tap. SDB read-only; history files
untouched; automatic writes exactly as in v0.13.0.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.18.0 - 2026-08-28 - Pass 19: icon names + Detail header icon

Base: v0.17.0. Owner request: name the selected icon; show the icon on Detail.

- 24-entry `icon_labels` table; `_refresh_picker` rewrites the "Icon:" label
  as "Icon:  <name>" (one existing item, no new zone).
- Detail page shows the tracker's icon top-left as a state-tinted plate
  (glyph or vector), aligned with the Edit header slot; hidden on the
  nothing-selected branch.
- Card glyph-vs-vector swap factored into shared `_apply_item_icon`.
- Offline harness: 205 checks.

**Safety status: pure UI pass; no write-behavior changes; SDB read-only,
history files untouched, automatic writes exactly as in v0.13.0.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.17.0 - 2026-08-28 - Pass 18: plugin-drawn vector icons

Base: v0.16.0. Owner rejected the FA wand and wanted a flatter gasket; picked
two generated stroke designs from PNG mockups rendered with the tablet font.

- Vector icon mechanism: `vector_defs` (0..100 box, line/oval segments)
  scaled into `L(vec_box_plate|pick)` via a physical->virtual factor so they
  match the physical-px FA glyphs. `canvas_item` rescales coords AND -width
  and honors `-initial_state`.
- Segments carry bare tags `<base>_s<i>`; helpers `_add_vector_icon` /
  `_config_vector_icon` / `_show_vector_icon`. Card plates carry both vector
  icons born hidden; refresh shows at most one and hides the glyph dtext.
- `_item_icon_name` split from `_item_glyph` ("" for vectors, no wrench
  fallback). Picker: steam-wand at slot 8, gasket-flat at slot 20.
- Offline harness: 193 checks.

**Safety status: pure UI pass; no write-behavior changes; SDB read-only,
history files untouched, automatic writes exactly as in v0.13.0.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.16.0 - 2026-08-28 - Pass 17: required-meaning icons

Base: v0.15.0. Owner request: meaningful icons for steam wand, drain pipe,
ball joint, gasket.

- Picker slots 8/14/15/20: pump-soap -> wand, coffee-pot -> pipe-section,
  mug-saucer -> circle-dot, brush -> record-vinyl (names verified in the
  app's FA6 table).
- Legacy-icon safety: `open_edit` seeds the STORED icon even off-picker;
  `edit_save` only writes picker-member icons, so an unrelated Save keeps a
  legacy icon instead of swapping it for the wrench fallback.
- Offline harness: 166 checks.

**Safety status: pure UI pass; no write-behavior changes of any kind; SDB
read-only, history files untouched, automatic writes exactly as in v0.13.0.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.15.0 - 2026-08-28 - Pass 16: consolidated trackers + button standard

Base: v0.14.0. Owner request: all trackers editable/deletable, one button
standard. Owner decisions: built-ins stay undeletable (Hide is their
reversible retirement; deleting would lose auto-record/burr-offset/water-
meter wiring), Delete moves into the Edit page, hide cap 6.

- Every tracker editable: built-in dicts gained `label` ("" = fixed default)
  and `icon`; `_item_label` / `_item_glyph` prefer the dict. Edit seeds and
  saves name/threshold/icon for built-ins exactly as for customs; unit stays
  locked. Picker swaps screwdriver-wrench -> gears, soap -> droplet-slash so
  every built-in glyph is pickable.
- Every tracker hideable, at most 6 (`hide_max`); Hide disables with a grey
  note at the cap. `apply_defaults` validates hidden_ids against built-ins
  AND customs and truncates overflow; deleting a hidden custom frees its slot.
- Delete relocated to the Edit page (customs only, danger style, bottom-
  center): first tap arms ("Yes, Delete Tracker", Save hides), second tap
  deletes and returns to the card list via `_return_to_page settings`
  (2-level unwind); Cancel disarms first; any page show disarms; edit_save /
  step_click no-op while armed. Detail's delete button and `confirm_delete`
  mode are gone; Detail bar = Back | Hide | Undo for every tracker.
- Wording: "New Tracker" page/button, action button "Save". Button standard
  documented in the .tcl header.
- Offline harness: 149 checks.

**Safety status: no new destructive capability. Deleting remains possible
only for custom trackers (two-tap, escrowed in `last_deleted_custom`), now
reached via Edit. Built-ins, SDB and history files can never be deleted or
altered. SDB read-only; automatic writes exactly v0.13.0's (own settings.tdb).**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.14.0 - 2026-08-28 - Pass 15: 24-icon picker

Base: v0.13.0 (owner-confirmed). Owner request: 12 more icons.

- `picker_icons` doubles to 24 glyphs in two rows of 12 (new row:
  bottle-water, coffee-pot, mug-saucer, gauge-high, scale-balanced,
  temperature-half, screwdriver-wrench, brush, soap, calendar-check, bell,
  star), all verified against the core FA6 table.
- `_build_picker_row` wraps at `picker_cols`; tags pick0..pick23.
- Add page: validation message moved beside "Icon:", chips moved up; Edit
  page note/error moved below the second row; all clearances kept.
- Offline harness: 94 checks.

**Safety status: pure UI pass; no write behavior added or changed; SDB
read-only, history files untouched; automatic writes exactly v0.13.0's (own
settings.tdb: user taps, auto-record events, water-meter updates).**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.13.0 - 2026-08-28 - Pass 14: water-bottle tracking in ml

Base: v0.12.0. Owner request: track what is left in the 5-gallon supply bottle.

- Lifetime water meter `settings(water_total_ml)`: `::de1(volume)` holds
  the finished operation's total until the next operation starts, so the
  existing `on_major_state_change` listener harvests it whenever the machine
  LEAVES a water-drawing state (Espresso, Steam, HotWater, HotWaterRinse,
  SteamRinse, Clean, Descale). An armed/cleared flag means a duplicate exit
  or a restart mid-flow can only miss water, never double-count; per-flow
  reads clamped 0-5000 ml; meter monotonic, rounded to 0.1.
- New built-in "Water bottle" tracker (unit ml, threshold 18900): Record =
  fresh bottle attached; the event stores the meter reading as baseline,
  value = meter - newest baseline, so Undo restores the previous baseline
  through the events-are-truth design.
- Bottle confirm page (burr-stepper mechanism, +-100/+-1000, clamp
  500-99999); Confirm writes the size into the item's threshold.
- ml counters render in litres; card caption "About X L left". ml is a
  third custom unit (Add toggle days -> shots -> ml, default 10000).
- Diagnostics: "Water dispensed (lifetime)" row; row-count rows merged.
- Offline harness: 80 checks.

**Safety status: SDB strictly read-only (no new queries); history files
untouched; no popups. The ONE new automatic write is the plugin's own
settings.tdb being saved when a flow/cycle completes (the same
`save_settings` path auto-record already used). The one destructive
capability remains deleting a custom tracker (two-tap, escrowed).**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.12.0 - 2026-08-27 - Pass 13: edit threshold and icon too

Base: v0.11.0. Owner request extending rename.

- Detail's Rename button became Edit, opening a full Edit page for custom
  trackers: prefilled name entry (top half), unit-scaled threshold steppers
  (clamped 1..99999), icon picker with the current glyph pre-selected.
- Save rewrites only `label`, `threshold`, `icon`; event history, unit and
  id untouched (verified field-by-field). Threshold change invalidates the
  status cache. Unit deliberately NOT editable (would reinterpret history).
- Picker row/refresh factored into shared `_build_picker_row` /
  `_refresh_picker` used by Add and Edit.
- Offline harness: 68 checks.

**Safety status: unchanged - three fields of one dict in the plugin's own
settings.tdb rewritten per explicit Save tap. SDB read-only; no history-file
access; no popups.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.11.0 - 2026-08-27 - Pass 12: rename custom trackers

Base: v0.10.1. Owner request: rename a custom tracker without losing anything.

- Rename button top-right on custom Detail pages (title wrap narrowed);
  opens a Rename page with the prefilled entry (top half), note, Cancel/Save.
- Save applies the Add page's validation (collapsed whitespace, non-empty,
  max 40) and rewrites ONLY the `label` field; history, icon, unit,
  threshold, id untouched. Hidden for built-ins and while a confirm is armed.
- Created `-initial_state hidden` with `-initial 1` show/hides.
- Offline harness: 61 checks.

**Safety status: unchanged - one dict field in the plugin's own settings.tdb
rewritten per explicit Save tap. SDB read-only; no history-file access; no
popups.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.10.1 - 2026-08-26 - bugfix: one-frame flash of hidden items on page entry

Base: v0.10.0. Owner report: hidden card / blank chips flashed on page entry.

- Root cause: `dui page load` re-shows every incoming item without an
  `st:hidden` tag BEFORE `show{}` runs; plain `dui item show/hide` never
  sets that tag.
- Every dynamic show/hide now passes `-initial 1`; start-hidden contextual
  items (chips, hidden-trackers title, Detail's Undo/Delete/Hide) are
  created `-initial_state hidden`. Harness enforces both.

**Safety status: unchanged - visibility mechanics only.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.10.0 - 2026-08-26 - Pass 11: per-item restore for hidden trackers

Base: v0.9.0.

- Add page's Restore All replaced by one chip per hidden tracker (6 fixed
  slots, non-empty creation labels, bare-tag relabels, tap maps through the
  list cached at refresh time). `unhide_all` -> `unhide_item`.
- Offline harness: chip labels/order, tap -> restore -> slide, guards, full
  Pass 10 suite.

**Safety status: unchanged - restoring only removes an id from `hidden_ids`
in the plugin's own settings.tdb, per explicit tap. SDB read-only; no
history-file access; no popups.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.9.0 - 2026-08-26 - Pass 10: "Service Bay" card redesign + icon picker

Base: v0.8.0. Owner picked Concept 01 of three mockups.

- Cards: state-tinted icon plate (`_blend` solid tints), name, uppercase
  state word, right-aligned counter, 20-segment wear bar (fill reconfigs
  only) with amber tick, last-done caption.
- Worst-first sorting (red -> amber -> ok -> no-data -> never); rendered
  order cached in `displayed_ids` so taps match the screen.
- Icons from the app's FA6 Pro symbol table (`dui symbol get`, font via
  `dui::font::add_or_get_familyname`); missing font degrades to glyph-less.
- Add page icon picker (12 glyphs); custom `icon` field, default wrench,
  render-time fallback for unknown names.
- Offline harness: 97 procs compiled, 36 checks.

**Safety status: presentation-only pass, zero new write behavior. The only
settings change is the custom-tracker `icon` field written by the same
explicit Add Tracker tap as before. SDB read-only; no history-file access;
no popups.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.8.0 - 2026-08-26 - Pass 9: hide/restore built-in trackers

Base: v0.7.1. Owner request: remove burr install; make built-ins hideable.

- Hide Tracker on built-in Detail pages: one tap adds the id to
  `hidden_ids` (validated to built-in ids on load), removing the tracker
  from the card list AND the status rollup; dict, event history and burr
  offset stay untouched in settings.
- Restore All on the Add page (with a hidden-names line) removes every id.
- Burr install starts hidden via a one-shot migration flag `hide_burr_done`
  (a later restore sticks); fresh-install threshold 30000 (stored values kept).
- Detail center slot holds two stacked mutually-exclusive buttons (Delete
  for customs / Hide for built-ins). Diagnostics "Hidden trackers" row.
- Offline harness: 92 procs compiled, 38 checks.

**Safety status: unchanged write surface - only the plugin's own
settings.tdb via `plugins save_settings`. Hiding is non-destructive (list
membership only, all data kept) and reversible via Restore All. The only
destructive capability remains deleting a CUSTOM tracker (two-tap confirm,
escrowed). SDB read-only; no history-file access; no popups.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.7.1 - 2026-08-26 - bugfix: Add-page stepper buttons rendered blank

Base: v0.7.0. Owner report: stepper faces empty.

- Root cause: a dbutton created with `-label ""` never gets a label
  sub-item, so later relabels silently no-op inside `catch`. Steppers now
  created with their day-unit labels; the harness stub rejects `-label`
  config on empty-created buttons.

**Safety status: unchanged - creation-label fix only.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.7.0 - 2026-08-26 - Pass 8: custom trackers

Base: v0.6.2. Owner request: user-named trackers for extra gear.

- Add Tracker page: name entry (SHE pattern, top half), days/shots unit
  toggle, unit-scaled steppers. Name required, trimmed, collapsed, max 40;
  rejections change nothing.
- Customs ride every existing mechanism (cards, Record/Confirm, event log,
  Detail, Undo, `status_summary` rollup); manual-record only. Shot-unit
  caveat stated in the UI (the DB cannot tell which grinder pulled a shot).
- Delete Tracker (custom only) on the custom Detail page: danger button,
  two-tap confirm (armed delete and armed undo mutually exclusive; Cancel
  or any page switch disarms). The removed dict is kept in
  `settings(last_deleted_custom)` (newest only) for hand recovery.
- Storage: `custom_ids` list + never-reused `custom_next`; ids `custom_<n>`;
  idempotent migration validates and heals. Diagnostics custom-count row.
- Lesson: braced `expr` canonicalizes "+10" to 10; build labels with string
  ops. Offline harness: 87 procs compiled, full flow + geometry audit.

**Safety status: writes remain confined to the plugin's own settings.tdb
via `plugins save_settings`. The ONE destructive capability added this pass
is deleting a CUSTOM tracker - user-created data inside the plugin's own
settings only, behind a two-tap confirm, with the removed dict escrowed in
`last_deleted_custom`. Built-in items cannot be deleted. SDB access
unchanged: read-only handle, SELECT COUNT only. No history-file access. No
popups.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.6.2 - 2026-08-26 - bugfix: Undo relabel actually happens on-device

Base: v0.6.1. Owner report: label swap did not show.

- The five bottom-bar relabels used the wildcard tag form, which is proven
  only for show/hide/-state; `-label` config needs the BARE main tag. All
  five now use bare tags; the harness stub rejects wildcard `-label`.

**Safety status: unchanged - tag-form fix only.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.6.1 - 2026-08-26 - Undo confirm label spells out the deletion

Base: v0.6.0. Owner request: the button itself carries the warning.

- Confirm-mode label "Yes, Delete Last Record" (was "Confirm Undo"); danger
  button widened to 300 px (`btn_w_xwide`).

**Safety status: unchanged from v0.6.0 - label and width only.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.6.0 - 2026-08-26 - Pass 7: auto-recording

Base: v0.5.0. Built from the approved auto-detect discovery report.

- New silent `on_major_state_change` listener: Clean (18) and Descale (10)
  are not flow states, so the after-flow listener never sees them.
  Enter/exit stamps from the event dict's `event_time`; a completed cycle
  appends one `source auto` event: Clean >= 90 s -> backflush, Descale >=
  300 s -> descale. Aborted cycles never count; the enter stamp is
  memory-only, so a restart mid-cycle misses, never double-counts.
- `_on_flow_complete` also detects cleaning-profile blind-basket backflush
  (previous state Espresso + beverage_type "cleaning" + >= 15 s).
- Auto events ride the exact Pass 6 append path (cap 20, `_sync_last_done`,
  save, cache invalidation), show as "recorded automatically", Undo works
  unchanged. A duplicate within 30 s of the newest event is swallowed.
- Settings: `auto_record` (1) master toggle; thresholds `auto_clean_min_s`
  90 / `auto_descale_min_s` 300 / `auto_bf_shot_min_s` 15. Diagnostics
  "Auto-record cycles" row. Handlers never throw into core dispatch.
- Offline harness: 69 procs compiled; full state-machine drive.

**Safety status: writes remain confined to the plugin's own settings.tdb
via `plugins save_settings` - user taps as before, plus one `source auto`
event per completed real maintenance cycle (undoable, and off with
`auto_record 0`). No popups; both listeners are silent. SDB read-only
(SELECT COUNT only); no history-file access.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.5.0 - 2026-08-25 - Pass 6: event log + revert

Base: v0.4.0.

- Storage converted to an append-only per-item event log `{ts source
  note}`, newest last, capped at 20; `source` always manual here.
- `last_done` stays in schema and `status_summary` but is derived-and-
  stored via `_sync_last_done` on every mutation. Idempotent migration
  seeds a v0.4.x dict's log from its `last_done`; `events` kept out of the
  defaults list so field-fill cannot plant an empty log over real data.
- Recording appends an event instead of overwriting; Cancel unchanged;
  burr `pre_sdb_offset` untouched by events.
- New Detail page (card text-area tap = invisible clickable rect, disjoint
  from Record): state + counter, 5 newest events, Undo Last Record (danger,
  hidden when empty), in-page confirm by relabel; Confirm Undo pops exactly
  the newest event. Every page show resets the confirm mode.
- `status_summary` shape UNCHANGED (verified key-for-key).
- Offline harness: 66 procs compiled; migration, cap, undo, geometry.

**Safety status: the ONLY writes in this version are to the plugin's own
`settings.tdb` via `plugins save_settings`, each behind an explicit user
tap (Confirm to record, Confirm Undo to remove the single newest record).
No bulk delete or reset exists. SDB access unchanged: read-only handle,
SELECT COUNT / sqlite_master / PRAGMA only. No history-file access. No
popups; the one event listener still only invalidates the counter cache.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.4.0 - 2026-08-25 - Pass 5: UI polish + count-query fix

Base: v0.3.0. Root cause from adb screenshots: the tablet's SQLite cannot run
`lower()` (`ICU error: u_strToLower(): link error`).

- Exclusion SQL rewritten lower()-free (`LIKE` / `NOT LIKE '%kw%'`);
  identical results on a copy of the real shots.db (1064 / 7 / 1071).
- Filter failure no longer kills counting: log, count unfiltered, flag on
  the new Diagnostics "Cleaning filter" row; per-item failures caught.
- Diagnostics renders `n/a` instead of blanks (rows 12 -> 13).
- Stale confirm page after the skin's home navigation recovers via Cancel's
  `_return_to_page`; no plugin change needed.

**Safety status: unchanged from v0.3.0 - SDB read-only (SELECT COUNT only),
no history-file access, no popups, the only write is the plugin's own
`settings.tdb` after explicit Confirm.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.3.0 - 2026-08-25 - Pass 3: recording + status cards

Base: v0.2.0.

- Main page = standard card list (SHE card system): 5 cards per page,
  Prev/Next paging, state dot (green/amber/red/grey), three text lines,
  Record button.
- Recording flow: Record -> dedicated confirmation page showing the current
  counter -> Confirm writes `last_done = now` into the item's dict in the
  plugin's own settings and saves via `plugins save_settings`; Cancel
  changes nothing. Pending-item flag cleared on every settings-page show.
- Burr install confirmation adds the pre-history shot offset steppers
  (clamped 0..99999); burr counter = offset + shots since install.
- New tokens (toolbar, cards, state colors); `rounded_rect` copied verbatim
  from SHE. Prev/Next disable at the ends; unused rows hidden.
- Offline harness: 56 procs compiled; geometry + flows against stub dui.

**Safety status: the ONLY write in this version - including the new Record
feature - is to the plugin's own `settings.tdb` via `plugins
save_settings`, after an explicit user Confirm. SDB access unchanged from
v0.2.0: read-only handle, SELECT COUNT only. No history-file access. No
popups; the one event listener only invalidates the counter cache.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.2.0 - 2026-08-25 - Pass 2: safe data reading

Base: v0.1.0.

- Own read-only SDB connection (`-readonly true`, SHE `_open_ro_db` pattern
  with GrindAdvisor's fallback), opened per refresh, closed immediately.
  Only SQL shapes: `SELECT COUNT(...)`, `sqlite_master` listing,
  `PRAGMA table_info`.
- Dynamic schema detection (shot table, clock/beverage_type/profile_title
  columns by regex); missing optional columns disable only what needs them.
- Defensive cleaning-row exclusion filter built only from existing columns;
  keyword lists shown on Diagnostics.
- Real `status_summary`: per-item ok/amber/red/unset/unknown, worst-state
  rollup, counts as RAW rows (soft-deleted shots still count; SHE's trash
  manifest never read). Burr total = pre_sdb_offset + count since install.
  Cached 10 min; invalidated by a silent `after_flow_complete` listener
  (60 s re-invalidation for SDB sync lag).
- Settings page headline + six status lines; new Diagnostics page (12 rows)
  with Back via `_return_to_page`.
- Offline harness: 40 procs compiled; every generated statement replayed
  via sqlite3.exe against a read-only copy of the real DB (1071 raw / 7).

**Safety status: SDB access is read-only (own `-readonly true` handle,
SELECT COUNT only - verified by replaying every generated statement). No
history-file access. No popups; the one event listener only invalidates
the counter cache. The only file written remains the plugin's own
`settings.tdb` via `plugins save_settings`.**

Files: plugin.tcl, MaintenanceTracker.tcl, README, CHANGELOG, PROJECT_STATE.

## v0.1.0 - 2026-08-25 - Pass 1: minimal loadable plugin

First version: appear in Extensions, load cleanly, navigate, persist settings.

- Manifest with author/version/description and settings defaults (six
  maintenance items as dicts: `last_done`, `note`, `threshold`, `unit`,
  plus `pre_sdb_offset` on `item_burr_install`; `amber_fraction`).
- `apply_defaults` fills missing keys/fields after `plugins load_settings`.
- One fpdialog settings page (`-namespace true -theme default`) with a
  static confirmation, painted background, Done button.
- Layout/font system copied from ShotHistoryEditor v0.7.1 (virtual 2560x1600,
  shared `MT_*` fonts incl. `font_button`). Navigation copied verbatim from
  SHE v0.5.3 (`open_page`, `_capture_return_page`, `_navigate_done`).
- Public API stubs for Lumen: `status_summary` (returns `ok 0`), `open_page`.

**Safety status: no write behavior exists in this version except the
plugin's own `settings.tdb`, written by the app's standard `plugins
save_settings` mechanism. No SDB access of any kind (not even read-only).
No history-file access. No hooks, popups, or automatic triggers.**

Files: plugin.tcl, MaintenanceTracker.tcl, filelist.txt, README, CHANGELOG,
PROJECT_STATE.
