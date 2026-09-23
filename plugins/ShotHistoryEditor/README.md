# Shot History Editor

**Browse your shots as cards, fix a wrong grind or bean name, delete mistakes to a restorable trash.**
Version v0.13.0 · a plugin for the Decent DE1app · by Blastize

![The shot list: five cards per page with grind, dose, yield, time, bean and profile](docs/shot_list.png)

**Your shots as cards.** Grind, dose, yield, time, bean and profile, five per page, newest first. Edit on the card, Select to pick shots for the trash.

![Edit Preview: pick one field, type the new value, preview before and after, then save](docs/edit_preview.png)

**Edit one field.** Pick the field, type the value, preview the before and after, then save. Only that one line of the shot file changes, after a backup. The shot database is never written.

![Trash / Restore: deleted shots in batches, each with a Restore button](docs/trash.png)

**Trash and restore.** Deleting moves the files into the plugin's own trash, in batches. Restore puts a batch back. Emptying the trash is a separate, typed confirmation.

![Source Inspector: the raw shot rows the database knows about](docs/source_inspector.png)

**Source Inspector.** The raw rows behind the cards, for when you want to see exactly what the database recorded.

## Recommended: the Lumen skin

![Lumen's Last Shot card: profile, bean, grind, dose, yield, time and when it was pulled, with the Shot history link](docs/lumen_last_shot.png)

Shot History Editor is designed around the [Lumen skin](https://github.com/Blastize/de1app-skin-Lumen). Lumen's home screen shows your last real espresso on its **Last Shot** card, read from the shot file itself, so a correction you make here shows up there. The card's **Shot history** link opens the shot list in one tap. Without Lumen the plugin still works, but you reach it through the app's Settings, Extensions and the plugin's settings button.

Both are in the [de1app-toolkit](https://github.com/Blastize/de1app-toolkit) download.

## Install

Copy the folder to `de1plus/plugins/ShotHistoryEditor/`, restart the app, enable **Shot History Editor** under Extensions.

## Safety

SDB is read-only. Edits rewrite exactly one line of one `.shot` file after a whole-file backup. Deletes move files into the plugin's trash and are logged; only Empty trash deletes for good, only inside that trash folder, after a typed confirmation. Raw pressure, flow and temperature data are never shown or edited.

<details>
<summary><b>Full reference and version notes</b></summary>

## Reference

Version: v0.13.0
Author: Blastize

## Tidy empty trash folders (v0.13.0)

Restoring a batch moves its files back but used to leave the empty batch
folder behind. Advanced > "Tidy empty trash folders" removes every empty
folder directly under the plugin trash, and nothing else: files, batches
and anything inside a folder are untouched, and one TIDY line goes to the
delete log. Empty trash now does the same sweep after removing its files,
so old leftovers go with it. The preview page says how many empty folders
exist. This extends the owner's permanent-deletion exception in CLAUDE.md
to empty folders under the trash.

## Empty trash, real (v0.12.0) -- PERMANENT DELETION

The plugin's sixth write capability and its first permanent deletion,
owner-authorized on 2026-09-18 under a one-line exception to the
workspace's "never permanent deletion" rule. Trash page > "Empty trash..."
shows the preview; its far-right red "Empty trash" button opens a typed
confirmation (the number of batches); "Remove permanently" then runs the
purge and shows a result page.

The write path, in full: the batch set must be unchanged since the
confirmation opened. For every trash-manifest line, the trash path must
resolve strictly inside `plugins/ShotHistoryEditor/trash/` (anything else is
kept and logged) and be a listed file (a missing one is logged as "already
gone" and its line dropped). Each such file is deleted, one `file delete`
per file; each batch folder is deleted only once it is empty. Every file
gets a line in the append-only `purge_log.txt`
(`ts|batch|orig|trash|bytes|status`), the trash manifest is rewritten
without the removed lines, and `delete_log.txt` gets one PURGE summary line.
Nothing under history/ or history_v2/ and nothing in SDB is touched. There
is no undo: restore what you still want before emptying.

## Empty trash, preview stage (v0.11.0)

No change to any write capability; nothing is deleted in this version. The
Trash page gains an "Empty trash..." button that opens a preview page: for
every trash batch the date, batch id, shot and file counts, whether the
files are still present, their size and age, then the totals a future Empty
trash would remove permanently. This is the preview stage of the plugin's
destructive-feature process. Real permanent deletion does not exist and
would need the workspace's "never permanent deletion" rule and the verify
harness audit changed first, in a separate explicit pass.

## Reconcile action: Unhide (v0.10.0)

Adds the plugin's fifth write capability, owner-authorized. The Reconcile
page (Advanced > Reconcile hidden shots) is now a row list with an Unhide
button per shot. Unhide appends one line to the plugin's own
`reconcile_manifest.txt` (`unhidden_at|ts|orig|batch`, the exact trash
manifest line it refers to) and one `RECONCILE UNHIDE` line to
`delete_log.txt`. That is the entire write path: the trash manifest is never
edited, no file is moved, and nothing under history/ is touched. From then
on that manifest line hides nothing, so the shot is back in the card list
and Source Inspector, while its trash entry and any trash copy stay exactly
where they were (Restore keeps reporting the collision). Because the marker
is tied to that one line, deleting the shot again hides it again, which is
also how to undo an Unhide.

## Trash page Next button (v0.9.1)

Bugfix; no change to any write capability. The Trash / Restore page had a
Prev button but no Next, so once more than six batches had been deleted
the older ones could not be reached. Next now sits beside Prev, appears
only while more batches follow, and the page can no longer scroll past
the last batch.

## Reconcile hidden shots, read-only view (v0.9.0)

New page under Advanced; no change to any write capability. A shot the
trash manifest lists as deleted is hidden from every list here for as long
as that line stands. If its file turns up in history/ again (the app's own
flush-save bug did this once; a hand copy or a failed restore could too),
the shot is on disk and back in SDB, yet invisible here, cannot be deleted
here, and Restore reports a collision for it. The new view lists exactly
those shots: when and in which batch they were deleted, the on-disk file's
modification time, whether the trash copy still exists (a stale manifest
line, or two different files), and what SDB thinks. The Advanced note and
Diagnostics show the count. Nothing on this page changes anything; the
un-hide action, if wanted, is a separate later step.

## Source Inspector shows 7 shots (v0.8.6)

Small behaviour change, owner-approved; no change to any write capability.
The Source Inspector (Advanced > Source Inspector) lists the latest 7 SDB
shots instead of 8, so its Open buttons reach the full touch height like
every other button in the plugin. One variable now drives the row count,
the refresh loop and the query.

## Polish batch (v0.8.5)

Visual-only; no change to any write capability. The Trash page's Restore
buttons are now full touch height and centred on their row, and the
Source Inspector's Open buttons are taller and evenly spaced (the row
count keeps them a little under the full height). The pencil, arrow and
checkbox glyphs in button labels are built from their code points so the
source is plain ASCII; they render exactly as before. A stray Windows `desktop.ini`
no longer ships with the plugin.

## Header / row gap (v0.8.4)

Layout-only bugfix; no change to any write capability. On the Trash and
Source Inspector pages the column header touched the first row (the
caption line is taller than the gap the list started at). A new layout
token holds the caption font's real line height in virtual units and both
lists now start below it, with the rows redistributed over the remaining
space. Regression net: `tools/check_header_gap.tcl`.

## Review follow-ups (v0.8.3)

Navigation/logging hygiene pass from the 2026-09-17 code review; no change
to any write capability. Log lines carry their real severity (the wrapper
now passes `-NOTICE`/`-INFO` where the core logger reads it), a failed
Done/Back exit is logged instead of swallowed, every Back button unwinds
the dialog stack the same way its neighbouring Done does, and the Source
Inspector's Open buttons hide with the same `-initial 1` form as the rest.

## Idempotent SDB close (v0.8.2)

Log-hygiene bugfix; no change to any write capability. The read-only SDB
handle is now closed only when it actually exists, so the old bare
`catch { $db_handle close }` no longer fails on every open and leaks a
stale `$::errorInfo` into the app's "BLE error info" log line.

## Card-list pagination fixes (v0.8.1)

Display/navigation-only bugfix pass; no change to any write capability.
Prev now really disappears on the first page and Edit buttons on empty
rows really disappear (dbutton show/hide needs the `<tag>*` wildcard
form — the bare tag only hides the invisible click area, leaving the
visible button behind). Next stops at the last shot and disappears on
the last page: the page offset is clamped to the real end, and the
shot total is now counted with exactly the pager's own filters (the old
count subtracted trashed shots twice once SDB's resync flagged them
`removed=1`, so paging could pass the reported total). The same
wildcard fix was applied to the Trash/Restore page's buttons.

## Dark mode (v0.8.0)

A sun/moon button in the main page's top-left corner switches all pages
between a light and a dark palette instantly; the choice persists across
restarts (the plugin's first persisted setting, in its own settings.tdb).
State reds/ambers lighten on dark for contrast. No change to any write
capability.

## Downstream effect of an edit, a delete or a restore (v0.6.0 / v0.6.3 / v0.7.0)

A change made here is invisible downstream until someone is told: Grind
Advisor reads SDB, and the Lumen skin reads the newest shot file only at
startup. So whenever this plugin changes what is on disk — a metadata save
(v0.6.0), a delete or restore batch (v0.6.3) — it notifies both, in order
(v0.7.0):

1. **Grind Advisor** — `refresh_from_history` resyncs SDB, drops its per-bag
   cache, recomputes for the loaded bag and re-saves; the result page
   reports what it did.
2. **Lumen** — `refresh_after_history_change` reloads the home page's chart
   and LAST SHOT card from the (possibly new) newest shot file, and rebuilds
   the bag cycler from the freshly-resynced SDB.

It runs **once per batch**, and only when files actually moved, because the
resync rescans the whole history folder. Either target may be missing (a
different skin, no Grind Advisor) or may fail — this plugin's own save or
delete still succeeds; its work is already done by then.

## Pass 5.4 Scope -- Theme/Contrast Bugfix (display only)

Fixes the pages rendering "inverted" under the Lumen skin (near-black
background, buttons reduced to bare labels): Lumen's DYE integration leaves
the current dui theme as DYE_Lumen before this plugin loads, so the
un-themed `she_btn` style landed in the wrong theme (no button shapes), and
fpdialog pages showed the dark canvas beneath them (no background of their
own). Fix copied verbatim from BeanScanner's proven pattern: the style is
registered with `-theme default` and explicit fills, and every page paints
its own full-page grey background first. No write behavior changed.

Shot History Editor is a Decent Espresso DE1app plugin for browsing and inspecting saved shot metadata across SDB, legacy `history/*.shot`, and `history_v2/*.json`. It can soft-delete shots (move their files to a plugin trash folder, restorable, since v0.4.0) and, as of v0.5.0, really save an edited metadata field back into `history/<filename>.shot`. SDB is never written to in either case.

## Pass 5.3 Scope -- Delete/Edit Flow Navigation Bugfix (bugfix only, no write behavior changes; root cause confirmed from core source and reproduced offline)

Tablet-reported against v0.5.2: Done on the Delete Result page landed back on the Step 2 confirmation page; and after cancelling out to the main page, the main page's own Done reopened the Step 2 page instead of leaving to the Extensions menu.

Two distinct defects, both introduced by v0.5.2, both confirmed rather than guessed:

1. **The core cannot truncate more than one stale dialog level.** v0.5.2 returned to a stacked ancestor with a single `dui page load $ancestor`, trusting the core's "Handle page stack" block to drop the pages above it. Reading that block (`de1app-core/dui.tcl` ~line 6470) shows it truncates with `dict unset page_stack {*}[lrange [dict keys $page_stack] idx+1 end]` -- and multi-argument `dict unset` treats the extra keys as a **nested key path**, not a list of top-level keys (verified empirically in tclsh). Consequences, all reproduced in an offline simulator that implements the core's stack code verbatim: truncating exactly 1 stale page works; 2 stale pages silently does nothing (stale entries stay stacked -- why Cancel *looked* fine but left `delete_review`/`delete_confirm` buried); 3+ stale pages throws inside `load`, aborting it and dropping into the `close_dialog` fallback, which pops exactly one level (why Done on Delete Result landed on Step 2).
2. **Return-page capture accepted this plugin's own pages.** Coming back to the main page from a sub-flow re-shows it with `page_to_hide` = that sub-page, and v0.5.2 captured it as the "return target" -- so the main page's Done ping-ponged back into the sub-flow instead of leaving the plugin.

**Fix (v0.5.3):**

- `_return_to_page` (every internal Done/Back/Cancel) unwinds **one `dui page close_dialog` at a time** until the target page is current -- each step is the 1-stale-page case the core truncates correctly. The loop is bounded, stops if navigation stops making progress, and stops immediately if the current page is no longer one of this plugin's own (e.g. a flush interruption corrupted the stack), falling back to `_navigate_done`'s validated direct load. Failures are logged via `msg`.
- `_capture_return_page` now also skips `ShotHistoryEditor_*` pages, so only a genuine outside page (the Extensions page the plugin was opened from) can become the main page Done's exit target. The main page's Done keeps v0.5.2's `_navigate_done` exit: loading a default-type page resets the core's `page_stack` entirely, so the exit is clean regardless of history.

Verified in an offline simulator (real plugin file sourced unmodified; `dui page` stubbed with the core's exact load/close_dialog/stack code, including the buggy truncation): the full delete flow, the edit-save flow from both Settings and Shot Detail (6 levels deep), the flush-interruption exit, and the Extensions exit all land on the right page with a clean stack -- 11/11 checks pass. Re-running the same simulator with the v0.5.2 procs restored reproduces all three tablet symptoms exactly, including the core's internal `dict unset` error. **Tablet-verified 2026-07-09: delete flow, edit-save flow, and Extensions exit all navigate correctly.**

## Pass 5.2 Scope -- Flush/Rinse/Steam Interruption Navigation Bugfix (bugfix only, proactive hardening, no write behavior changes)

Applies the same fix landed for GrindAdvisor v1.8.8's "Done lands on the flush screen" bug to this plugin, since the confirmed root cause is a property of the shared DE1app framework, not something specific to GrindAdvisor -- so this plugin was equally exposed even though it hadn't been reported here yet.

**Root cause (confirmed in `de1app-core/dui.tcl`, see GrindAdvisor/CHANGELOG.md's "v1.8.8" entry for the full trace):** `::dui::page::load`'s "Handle page stack" block resets `page_stack` to a single entry every time a page of type `"default"` is shown -- e.g. the flow-monitor screen shown while a flush/rinse/steam/clean/etc. runs. This happens even while an `fpdialog` page (every page this plugin registers) is current, because the framework's "only one dialog page visible" guard only checks page type `"dialog"`, not `"fpdialog"`. When this plugin's page is re-shown afterwards, it gets pushed onto that freshly-wiped stack. `dui page close_dialog` navigates to "previous" in `page_stack` -- which, after such an interruption, is the flow page instead of this plugin's real parent page. This is a different failure mode than the v0.4.1/v0.5.1 bugs above (those were about a single `close_dialog` not popping enough levels of a plugin-internal flow); this one is about `close_dialog` trusting a stack that an *external* page change silently corrupted.

**Fix:** every Done/Back/Cancel button in this plugin (Settings, Advanced, the delete review/confirm/result flow, the edit preview/confirm/result flow, Trash, Recent/Source Inspector, Shot Detail, Diagnostics, Help) now navigates via `_navigate_done $target`, which reaches a specific, already-known real target page with `dui page load $target` (confirmed in `dui.tcl` to be the exact same underlying call `open_dialog` itself uses, not a different or riskier mechanism) instead of trusting `close_dialog`'s "previous" page resolution; `close_dialog` remains only as the fallback if `$target` is somehow missing or unregistered. The Settings page's own Done button (the one exit point whose correct target is dynamic -- whatever DE1app page opened the plugin, not a hardcoded name inside it) captures that real caller in its own `show{}` via `_capture_return_page`, skipping the capture whenever the incoming page name looks like a flow/monitor page (matching the same `espresso|steam|water|rinse|flush|clean|cleaning|descale|purge` name check GrindAdvisor uses), so a flush/rinse/steam interruption's re-show can never overwrite the last legitimate return target. `_return_to_page` (used throughout the file already) is now a thin wrapper over `_navigate_done`, so no call site needed to change. Not tablet-reproduced yet for this plugin (applied proactively, mirroring the confirmed GrindAdvisor mechanism) -- please retest the full Done/Back path on every page after a flush/rinse interruption to confirm.

## Pass 5.1 Scope -- Settings Page Double-Done Navigation Bugfix (bugfix only, no write behavior changes)

Reported after tablet testing of v0.5.0: after editing a field, saving, and tapping Done through the save flow's Result page, tapping Done again on the Settings page (to exit the plugin) landed back on the Edit Preview page instead of exiting -- a second Done tap was needed to actually leave.

Root cause: `_return_to_page` (used by `close_edit_result`, `close_delete_result`, and the Cancel buttons in the delete review/confirm flow) only called `dui page close_dialog` **once**, then papered over any mismatch with a forced `dui page load $target`. That forced load changes what's displayed but does not pop the underlying dialog stack -- so multi-level flows like Edit Preview -> Confirm -> Result (3 stacked levels) left 1-2 stale, un-popped levels sitting underneath the forced display. The Settings page's own Done button (`bar_left_click`) does a single real `close_dialog`, which then popped one of those stale leftovers -- surfacing Edit Preview -- instead of exiting the plugin.

Fix: `_return_to_page` now loops `close_dialog` (bounded to 10 iterations) until `dui page current` actually reports the target page, only falling back to the forced `load` if the stack runs out before reaching it. This fully unwinds multi-level flows instead of masking the mismatch, so no stale levels remain for a later Done button to consume. No file writes, delete/trash/restore behavior, or save behavior changed in this pass -- navigation only.

## Pass 5.0 Scope -- Real Metadata Save (second destructive-capability pass)

This pass authorizes exactly one new capability: writing ONE targeted `settings{}` key at a time into `history/<filename>.shot`. It does not authorize anything about delete/trash/restore (unchanged from v0.4.1) or SDB writes (still never happen).

### Step 1 findings

- **`.shot` file format:** a flat `key value` line per top-level entry, plus one `settings { ... }` block holding the user-facing metadata in the same style. All 3 sample files in `history/` contain a nested `read_only_backup {...}` sub-value inside the settings block that spans many lines and is unbalanced within any single line. This plugin's existing `read_legacy_settings`/`_parse_settings_file` stops at the first bare closing-brace line -- harmless for reading only, since every editable field's key happens to sort alphabetically before `read_only_backup` -- but writing against that truncated boundary would risk silently corrupting the file. The new write path tracks real brace depth (`_settings_block_bounds`/`_find_settings_key_line`) to find the block's true end (verified against the sample files: line 490, not the first bare `}` at line 409) and the exact line for the target key.
- **Write mechanics:** `plugins/SDB/SDB.tcl:2948` calls a core app proc `modify_shot_file $path new_settings` for its own category-edit feature, confirming targeted `.shot` writes are normal and supported -- but neither that proc nor `get_shot_file_path` exists anywhere in this workspace, and SDB's call site immediately follows it with an `UPDATE` against SDB in the same breath. Per "do not guess the DE1app plugin API" and "SDB stays read-only", this pass implements its own self-contained cycle instead: backup -> build new content in memory (only the one line changes) -> write to a temp file in the same directory -> verify the temp file with the existing `_parse_settings_file` reader -> only then atomically `file rename` it over the original -> re-verify the now-current file, auto-restoring from backup if that somehow still fails.
- **`history_v2/<filename>.json` decision:** NOT written by this pass. Same evidence as the delete pass (nothing in this workspace reads or depends on it), plus its `meta.bean`/`meta.grinder` key names differ from the `.shot` settings block, so keeping them in sync would need a second write path with no proven need. A saved field can leave history_v2 showing a stale value until a future pass addresses it.
- **SDB staleness:** SDB is never written to, so the card list and Detail page overlay saved edits from a new `edit_manifest.txt`, reusing the exact pattern already proven for the delete pass's trash-manifest filter.
- **Bug found and fixed in existing code:** while testing against the real sample files, `read_legacy_settings`/`_parse_settings_file`'s `$trimmed eq "settings {"` and `$trimmed eq "}"` comparisons turned out to only survive Tcl's source-time brace-matching by an accidental cancellation between the two, and threw a runtime "invalid character '}' in expression" error the first time either was actually exercised against a genuine multi-line `.shot` file -- never triggered before because this plugin's own prior tests only used single-line synthetic fixtures. Fixed by escaping both literal braces (`\{`/`\}`); behavior is unchanged, this only fixes a latent crash in the existing read path that every previous version's Detail/Diagnostics display would have hit against a real file.

### v0.6.0 — an edited shot now looks edited

Until v0.6.0 an edit made here was invisible to **SDB**, and therefore to
everything downstream of it. Not because SDB was stale in the "will catch up
later" sense — because it could never catch up at all.

`file rename` landed the rewritten file carrying the **original's**
modification time (Tcl's rename falls back to a copy on this storage, and
Tcl's copy preserves file times). SDB only re-reads a `.shot` when
`file mtime > file_modification_date`, and those two values were byte-identical
— measured on the tablet: an edit made at 16:45:30 left the file claiming
16:44:53, exactly what SDB had stored. So SDB skipped it, and **SDB's own
"Resync database to history" button could not have helped either.**

v0.6.0 stamps the file's modification time after a verified save. Content is
untouched; this is the same file the save has just legitimately rewritten.

It also calls `::plugins::GrindAdvisor::refresh_from_history` when that plugin
is installed, so the recommendation follows a correction without anyone having
to know that it should. The save-result page reports what it did. Both are
guarded: the save has already succeeded by that point and reports success
regardless.

**Edits made before v0.6.0** still carry their original timestamps. Re-saving
the field fixes each one — there is no no-op guard, so saving the same value
again is a real write and stamps the time.

### Save flow

Edit Metadata Preview (unchanged: pick a field, type a new value, Preview Change) gained one new button, **Save Change**, leading to a Before/After **Confirm** page (exact shot, exact file, before/after values, a numeric-mismatch warning if relevant, Cancel / danger-colored Save Change) -> **Result** page (saved/failed message + backup path) -> back to wherever Edit Preview was entered from. An empty new value is rejected before any file operation. Cancel at Confirm, Done at Result, and Edit Preview's own Back button all use the v0.4.1-proven `_return_to_page` navigation helper (not `open_page`), since this mini-flow can be 2-6 pages deep in the dialog stack -- exactly the class of bug fixed in v0.4.1, applied here proactively.

### Safety

Backups live in `plugins/ShotHistoryEditor/backups/<timestamp>_<batchid>/`, excluded from `filelist.txt`/packaging like the trash folder. Every save attempt is logged to `edit_log.txt`; successful saves are also recorded in `edit_manifest.txt`. `file delete` is never called anywhere in the plugin -- a failed pre-rename verification simply leaves the original untouched and the temp file behind for inspection.

## Pass 4.1 Scope -- Delete-Flow Navigation Bugfix (bugfix only)

After v0.4.0, the Delete Result page's Done button did nothing (no error, no crash). Root cause and fix:

- **Root cause:** `close_delete_result` returned to the main page via `open_page ShotHistoryEditor_settings`, which tries `dui page open_dialog`/`load`/`show` in order and stops at the first call that doesn't throw. By the time Result's Done is tapped, `ShotHistoryEditor_settings` is already open 3 levels down the dialog stack (settings -> delete_review -> delete_confirm -> delete_result). `open_dialog` on a page already in the stack doesn't throw -- so `open_page`'s `catch` treats it as success -- but it performs no real page transition either, so the settings page's `show{}` (which resets selection mode and reloads the list) never runs. Every other proven-working exit in this plugin, and the reference plugin GrindAdvisor's `_close_settings_dialog`/`_close_subpage_dialog` (`GrindAdvisor.tcl:412-439`), instead exit a stacked dialog with `dui page close_dialog` -- GrindAdvisor's own comments confirm `close_dialog` "reveals whatever page the framework currently considers current," and GrindAdvisor restricts `open_dialog`-style entry to genuine top-level entry, never to returning to an already-stacked ancestor. A headless test independently ruled out the alternative theory (an uncaught error in `refresh_main_page`/`show{}` with a populated `trash_manifest.txt`) -- that path runs cleanly regardless of manifest contents.
- **Fix:** added `_return_to_page {target}`, reusing GrindAdvisor's own proven two-step recovery technique (`GrindAdvisor.tcl:412-423`): call `dui page close_dialog` once, then check `dui page current`; if it isn't exactly `$target`, force it with `dui page load $target` (never `open_dialog`). Applied to Delete Review's Cancel, Delete Confirm's Cancel, and Delete Result's Done (all three share the identical faulty pattern), and to Advanced's Back button (same pattern, checked per the bug report; safe since the corrective `load` branch only fires when a plain `close_dialog` doesn't already land on the target, so it can't regress a case that happened to already work). Diagnostics/Help/Detail/Recent's own Back buttons use the same shape but target their immediate parent, weren't reported broken, and were left untouched.
- **Verified:** a headless simulation of the exact failure mode (`open_dialog` "succeeding" with no real transition) confirmed `_return_to_page` falls through correctly to `dui page load`; the same test at 1-level depth (Review Cancel / Advanced Back) confirmed the corrective branch never fires there, so no working case regresses. Re-ran the full v0.4.0 delete/cancel/restore test end-to-end -- delete/restore/manifest/log behavior is unchanged.

## Pass 4.0 Scope -- Real Soft Delete (first destructive-capability pass)

This pass authorizes exactly one new capability: moving `history/*.shot` (and its matching `history_v2/*.json`, when present) to a trash folder inside the plugin. It does **not** authorize editing file contents, writing to SDB, or permanent deletion of anything -- Edit Metadata Preview is unchanged and still writes nothing.

### Step 1 finding: is it safe to move `history_v2/*.json` too?

Grepped `plugins/SDB/SDB.tcl`, `plugins/GrindAdvisor/GrindAdvisor.tcl`, and `plugins/visualizer_upload/plugin.tcl` for `history_v2`/`.json` -- no matches in any of them. SDB's own resync/rebuild path (`::plugins::SDB::populate`/`::plugins::SDB::create`) reads only `history/*.shot`; nothing in this workspace indexes, watches, or rebuilds from `history_v2` filenames, and `history_v2/` itself has no manifest/index file of its own (just loose per-shot `.json` files). **Decision: move both files together** in the same trash batch -- there is no functional reason to leave an orphaned `.json` with zero consumers behind.

### Trash / manifest / audit log

```
plugins/ShotHistoryEditor/trash/<timestamp>_<batchid>/   <- moved files
plugins/ShotHistoryEditor/trash_manifest.txt              <- one line per moved file:
    timestamp|original_path|trash_path|batch_id
plugins/ShotHistoryEditor/delete_log.txt                  <- human-readable audit log
```

All three live under the plugin folder and are intentionally excluded from `filelist.txt`/packaging (per CLAUDE.md: "Backup/trash/log folders live under the plugin folder but are never shipped when sharing").

File operations use `file rename` only -- `file delete` is never called on a history file anywhere in this plugin. If a move fails partway through a batch of multiple shots, the whole batch stops immediately; every file that already moved is still recorded in the manifest (nothing moved is ever left untracked) and the failure is reported back.

### Confirmation flow (selection mode -> Delete)

1. **Review** (Step 1): exact list of shots (date/time + filename) and exactly which files will move for each ("history/x.shot, history_v2/x.json" or "history/x.shot only"). Text: "These shots will be moved to the plugin trash folder. Nothing is permanently deleted." Buttons: Cancel / Continue.
2. **Confirm** (Step 2): type the exact number of shots being deleted into a field in the top half of the screen (Android keyboard doesn't cover it), then tap the danger-colored Confirm Delete. Typed input is chosen over hold-to-confirm: no press-and-hold/progress-timer UI pattern exists anywhere in this workspace to build on, and this is the first destructive-capability pass, so a proven, unambiguous confirmation was preferred over a novel interaction with no precedent. Cancel is always available and performs zero file operations.
3. **Result**: reports how many files moved (and for how many shots) and the trash path. Returns to the main page, which unconditionally exits selection mode and reloads the list.

### List consistency after delete

SDB is never modified by delete, so its rows for deleted shots still exist. Every shot list (`load_recent_shots`, `load_recent_shots_paged`) scans a buffer of SDB rows and filters out anything present in `trash_manifest.txt` before slicing to the requested page, so deleted shots disappear from the list immediately. Advanced and Diagnostics show: "N deleted shot(s) hidden (SDB not modified; it may resync on its own)."

### Restore

Advanced > **Trash / Restore** lists every batch (date, shot count, file count) with a Restore button per batch. Restore moves files back to their original paths (move only); if a file already exists at the original path, that one file is left in the trash/manifest as a collision rather than overwritten, so it can be retried. There is no "Empty trash" button in this version -- permanent deletion does not exist yet.

## Pass 3.3 Scope -- Button Font Bugfix (bugfix only)

After v0.3.2, layout and card text rendered at the correct size, but every button label (Select, Prev, Next, Edit, Done, Advanced, and all buttons on Edit Preview / Delete Preview / Advanced / Diagnostics / Help) still rendered noticeably smaller than the design-system button font. Root cause and fix:

- **Root cause:** button labels are created through a different dui code path than card text. Card text uses our own `-font` on `dui add dtext` with a real Tk font object; button labels instead relied on `dui aspect set -type dbutton_label -style she_btn {font_size ...}` (added in v0.3.2, on the assumption that this aspect key gets rescaled the same way `bwidth`/`bheight`/`radius` are). That assumption was wrong -- the framework did not honor the aspect font_size key on the tablet, so every button fell back to a small skin-default font.
- **Fix:** added a single `font_button` Tk font object to the layout block, built the same way as the five card-text fonts (`font_title`/`font_section`/`font_primary`/`font_body`/`font_caption`) -- 20px bold equivalent, scaled by `font_scale` (the real physical screen, same basis as `font_primary`), not `scale` (virtual coordinate space). It's passed directly via `-label_font $L(font_button)` on all 32 `dui add dbutton` calls across every page -- a per-instance override confirmed to work in `plugins/visualizer_upload/plugin.tcl:467,505-507`. Removed the non-functional `dbutton_label` aspect font_size key and the old virtual-scale `btn_px` variable; the `dbutton` aspect style now only sets `shape round radius ...`, which was already rendering correctly.
- **Verified:** no `-label_pos`/`-label_justify`/`-label_width` overrides were touched, so button-label centering is unaffected. Checked "Clear Selection" (selection mode's longest label, `btn_w_std`-wide bottom-bar slot) against the new font size -- comfortably fits at the reference resolution.

## Pass 3.2 Scope -- Coordinate-Basis Bugfix (bugfix only)

v0.3.1 rendered the whole UI at roughly half size in the top-left quadrant of the screen, with card text overlapping. Root cause and fix:

- **Root cause:** DE1app `fpdialog` pages draw in a fixed VIRTUAL coordinate space (~2560x1600, inferred from SDB.tcl centering titles at x=1280 -- exactly half of 2560 -- and GrindAdvisor.tcl placing fpdialog buttons at y up to ~1580-1600), which dui itself rescales down to the real physical screen. The one confirmed dui coordinate-rescale API in this workspace, `dui::platform::rescale_x`/`rescale_y` (`plugins/visualizer_upload/plugin.tcl:509`), exists precisely to convert a virtual-space value to physical pixels -- confirming `dui add` coordinates are expected in that virtual space, not physical pixels. v0.3.1 instead computed every coordinate from `winfo screenwidth/screenheight` (the real physical size), so dui rescaled our already-physical coordinates a second time (~0.52x), shrinking and shifting everything toward the top-left. Meanwhile our own `SHE_*` Tk fonts (`font create ... -size -N`) are plain font objects referenced by name -- dui has no way to rescale a font object we created ourselves, so text stayed at its original (correct-for-physical) size while the coordinate spacing around it shrank a second time, causing the card baselines to collide.
- **Fix:** `_init_layout` now derives two independent scale factors: `scale` (every coordinate/spacing/card/button token) from a fixed virtual base resolution constant (2560x1600), and `font_scale` (the 5 named `SHE_*` fonts) from the real detected physical screen via `winfo`, same as before. `btn_px` (feeds `dui aspect set -type dbutton_label`, part of dui's own button-rendering pipeline alongside virtual-space `bwidth`/`bheight`) correctly stays on `scale`. Every v0.3.1 token formula/ratio/rule is otherwise unchanged -- only the input driving `scale` changed.

## Pass 3.1 Scope -- Input Fix + UI Precision Pass

v0.3.0's selection mode shipped with a critical bug: once you tapped Select, no button on the page responded (Cancel, Delete, Clear Selection, cards, Prev/Next all dead) and the app had to be force-closed. Root cause and fix:

- **Root cause:** v0.3.0 drew multiple full-size interactive buttons at identical coordinates for each mode-dependent control (Select/Cancel, Advanced/Delete, Done/Clear Selection, and three buttons per card row) and toggled which one was visible with `dui item show/hide`. That overlapping-duplicate-widget pattern doesn't exist anywhere else in this plugin's proven-working v0.2.0 code -- every button there occupies a unique, non-overlapping rectangle. Once more than one interactive widget shares a bounding box, tap routing on this page system becomes ambiguous and none of the stacked widgets respond reliably.
- **Fix:** every one of those slots now has exactly one button, created once, whose command is a stable dispatcher that checks the current mode when tapped; only the button's caption text is reconfigured (via the same `dui item config ... -label` pattern already used for `-text` everywhere else in this file). No two interactive widgets ever share a rectangle again, and Cancel / Done / Back are structurally always reachable. Entering the main page also force-resets selection-mode state as a defensive guard.

This pass also replaces guessed/fixed coordinates with a small design-token system computed from the real detected screen size, and applies it consistently across every page. See "Layout / Responsiveness" below.

## Pass 3 Scope

This version redesigns the main page as a one-page, card-based workflow. It is still fully read-only, with edit and delete both preview-only.

- Opens from Settings -> App -> Extensions.
- Opens directly to recent shot cards -- no menu/button step before seeing shots.
- Each card shows date/time, shot time, grind, dose, yield, bean/profile, and an Edit (✎) button.
- A Select button switches into selection mode: cards get a Select/Selected toggle, the top-right button becomes Cancel, and a bottom bar shows Delete and Clear Selection.
- Delete opens a "Delete Preview" screen showing how many shots were selected and the message "No files will be modified in this version." Cancel and OK both simply close the preview -- nothing is moved, deleted, or updated anywhere.
- Edit opens the existing Edit Metadata Preview page from v0.2.0, unchanged -- still preview only, no Save button.
- Shot Detail (source comparison), Diagnostics, and Help / Guide have moved behind a single Advanced / Source Inspector page, reached from the main page's Advanced button. Normal use does not require entering Advanced.
- Prev/Next buttons page through the shot list (offset-based).

## Pages

- Main page (`ShotHistoryEditor_settings`): card list of recent (non-deleted) shots, Select/Cancel, Prev/Next paging, Advanced, Done.
- Advanced / Source Inspector (`ShotHistoryEditor_advanced`): entry points to Source Inspector, Diagnostics, Help / Guide, and Trash / Restore; shows the "N deleted shot(s) hidden" note.
- Source Inspector picker (`ShotHistoryEditor_recent`): the v0.2.0 recent-shots list (also filtered against the trash manifest), reached only from Advanced, used to open Shot Detail for one shot.
- Shot Detail (`ShotHistoryEditor_detail`): source comparison for one selected shot (unchanged from v0.2.0).
- Delete Review (`ShotHistoryEditor_delete_review`): Step 1 of real delete -- exact shot list + exact files that will move.
- Delete Confirm (`ShotHistoryEditor_delete_confirm`): Step 2 of real delete -- typed confirmation of the shot count.
- Delete Result (`ShotHistoryEditor_delete_result`): reports files/shots moved and the trash path.
- Trash / Restore (`ShotHistoryEditor_trash`): lists trash batches with a Restore button per batch.
- Edit Preview (`ShotHistoryEditor_edit_preview`): choose one safe legacy metadata field, type a possible new value, preview before/after text. Reachable from a card's Edit button or from Shot Detail, and returns to whichever page opened it. As of v0.5.0, gained a Save Change button leading to the two pages below.
- Edit Confirm (`ShotHistoryEditor_edit_confirm`): Before/After confirmation for a real save -- exact shot, exact file, before/after values, danger-colored Save Change button.
- Edit Result (`ShotHistoryEditor_edit_result`): reports whether the save succeeded and the backup path.
- Diagnostics / Help / Guide: updated to describe both the real delete/restore and real save capabilities; still nested under Advanced.

## Source Rules

SDB is used for browsing and searching, and is never written to. Legacy `history/*.shot` is the durable source for editable metadata -- as of v0.5.0, saving via Edit Metadata Preview really writes ONE targeted key into its `settings{}` block (backup + verified write; every other byte untouched), and as of v0.4.0 the whole file can be moved (never permanently deleted) by soft delete. `history_v2/*.json` stays read-only for comparison in both cases: moved alongside its matching `.shot` on delete, never edited by a save.

Raw pressure, flow, temperature, resistance, and chart data are off-limits -- never displayed for editing, never modified by either write path.

Safe editable fields are `grinder_setting`, `grinder_dose_weight`, `drink_weight`, `bean_brand`, `bean_type`, `espresso_notes`, `my_name`, and `drinker_name`.

## Layout / Responsiveness

v0.3.1 replaces the fixed-canvas assumption from v0.2.0/v0.3.0 with real screen detection. No dui skin-scaling helper or rounded-rectangle primitive exists anywhere in this workspace (checked `plugins/SDB`, `plugins/GrindAdvisor`, and `skins/*/skin.tcl`); GrindAdvisor's own popups already fall back to `winfo screenwidth/screenheight`, so this plugin now does the same for its `fpdialog` pages.

A single `_init_layout` proc (called once from `preload_pages`) computes a token array `::plugins::ShotHistoryEditor::L(...)`: spacing tokens (`xs` 6 / `sm` 10 / `md` 16 / `lg` 24 / `xl` 32 / `xxl` 48), margins, `left_x`/`right_x`/`content_w`/`value_x`, card and button dimensions, header/toolbar/list/bottom-bar zone boundaries, and five fixed pixel fonts (title 40 / section 24 / primary 22 / body 19 / caption 16, each floored at 16px), all scaled by `screen_h / 800.0`. Every page's `setup{}` reads its coordinates from this array -- there are no hardcoded coordinates left in any `dui add` call.

- Card list: 5 cards per page (down from 6), each a rounded-rectangle card (new `rounded_rect` helper) with 3 text lines and one action button.
- Prev/Next moved from the bottom bar to a toolbar row directly under the header, alongside a "Showing X-Y of N shots" status line (backed by a new read-only `_total_shot_count` COUNT(*) query).
- Bottom bar has exactly one Done/Delete button on the left and one Advanced/Clear Selection button on the right (see the Part A fix above for why there is exactly one button per slot, not two).
- Advanced, Delete Preview, the Source Inspector picker, Shot Detail, Edit Metadata Preview, Diagnostics, and Help all use the same token system for margins, header placement, and button rows; Edit Metadata Preview's labels sit at `left_x` and values at `value_x`.

Known limitations:

- The card list's Next button is always shown (no total-row count gates it); paging past the last page shows an empty list with a status message instead of disabling Next.
- `page_line_count` (the number of text lines shown per page on Detail/Diagnostics/Help) is unchanged from v0.2.0 per "do not change plugin logic" -- its visual fit now depends on the real screen height and the new caption font size, and may want tuning in a future pass.
- The `she_btn` dui aspect style (shared button corner radius + font) is a best-effort use of the framework's documented aspect keys (`shape round radius N`, `font_family`/`font_size`); no other plugin in this workspace defines a custom aspect style, so it's wrapped in `catch` and falls back to whatever the framework's default button look is if those keys aren't accepted.

</details>
