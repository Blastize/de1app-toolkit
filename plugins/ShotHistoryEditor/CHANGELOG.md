# Changelog

Note: entries follow the CLAUDE.md doc cap (about 15 lines each; entries that added or
changed a write capability keep their full write-path description). The long pre-trim
entries survive in the Desktop archive snapshot of each version.

## v0.13.0 - Tidy empty trash folders (2026-09-18)

Base: v0.12.0. Restore never removed an emptied batch folder (14 on the tablet). CLAUDE.md's
exception now also names EMPTY batch folders directly under the trash (owner-approved).

- `_remove_empty_trash_dirs`: removes every EMPTY folder directly under the plugin trash
  (`_inside_trash_dir` guard; a folder holding anything stays). Holds the plugin's only
  folder `file delete`; `perform_purge` calls it after its file pass and reports
  `folders_removed` (result page + PURGE log line).
- Advanced > "Tidy empty trash folders" calls it alone: one TIDY line in delete_log.txt,
  result in the Advanced note (`refresh_advanced_page`, cleared on next show).
- Preview page states the empty-folder count; Advanced subtitle drops "read-only".
- Offline fixture: two empty folders removed; a folder with a file and a stray file under
  the trash kept; TIDY logged; purge reports folders_removed. verify.sh pass 11: PASS on
  run 2 (run 1 failed only on my check expecting 14 empty folders; the tablet has 13, and
  one untracked non-empty folder that both sweeps correctly leave alone).

**Safety: the permanent-deletion capability (v0.12.0) is extended to EMPTY folders directly
under plugins/ShotHistoryEditor/trash/ only. Still exactly two `file delete` lines, both
tagged `;# purge-only`; 11 write-mode opens; no other write path changed.** Files:
ShotHistoryEditor.tcl, plugin.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md; CLAUDE.md.

## v0.12.0 - real Empty trash: PERMANENT deletion (2026-09-18)

Base: v0.11.0. Owner decision after the preview and after the concern was raised:
CLAUDE.md's "never permanent deletion" now carries ONE exception for this plugin's own
trash folder, and loop/verify.sh exempts only `file delete` lines tagged `;# purge-only`.
Sixth write capability; first permanent deletion; clearly flagged.

- UI: preview page far-right red "Empty trash" (hidden while the trash is empty) ->
  `ShotHistoryEditor_purge_confirm` (type the batch count; entry in the top half) ->
  "Remove permanently" -> `ShotHistoryEditor_purge_result` -> Done returns to Trash.
- Write path, in full (`perform_purge`, called only from `confirm_purge_submit`):
  1. refuses unless the batch set equals the snapshot taken when the confirmation opened;
  2. per manifest line: trash path must resolve strictly inside
     plugins/ShotHistoryEditor/trash/ (`_inside_trash_dir`; else kept + logged SKIPPED) and
     be a listed file (else logged "already gone", line dropped);
  3. ONE `file delete` per file; ONE `file delete` per batch folder only when it is empty
     (a folder with unknown files stays);
  4. every file -> purge_log.txt `ts|batch|orig|trash|bytes|status` (append-only); the
     trash manifest is rewritten without the removed lines; delete_log.txt gets one PURGE
     summary; a NOTICE is logged.
  history/, history_v2/ and SDB are never touched. No undo.
- Help line updated. Offline fixture: two batches purged; an outside-trash manifest line
  kept and its file untouched; an already-gone line dropped; empty batch folders removed,
  a folder with a stray file kept; logs/manifest correct; batch-set mismatch and wrong
  typed count refuse with nothing removed.
- verify.sh pass 10: PASS first run (pages incl. the two new ones, `file delete` pinned to
  exactly 2 tagged lines, write-mode opens 10, logcat free of "Empty trash removed": the
  tablet's 7 batches are untouched). Screenshots checked by eye.

**Safety: this version ADDS permanent deletion, limited to files inside the plugin's own
trash folder that the trash manifest lists, behind a typed confirmation, with a per-file
audit log. Exactly two `file delete` lines exist and both are tagged `;# purge-only`.
Edit/soft-delete/restore/unhide are untouched; history files are never deleted.** Files:
ShotHistoryEditor.tcl, plugin.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md; workspace:
CLAUDE.md (rule exception), loop/verify.sh (audit exemption).

## v0.11.0 - Empty trash, PREVIEW stage (2026-09-18)

Base: v0.10.0. Owner asked for Empty trash; CLAUDE.md says "never permanent deletion" and
verify.sh rejects `file delete`, so this is the preview stage of the destructive process.

- Trash page: far-right "Empty trash..." opens "Empty trash - preview" (paged text,
  Done/Back return to Trash). `empty_trash_preview_text`: per batch date, id, shots, files
  present/missing, bytes, age; totals a future Empty trash would remove; states nothing
  is deleted and manifest + delete log would stay as audit. Help line updated.
- Offline fixture (known sizes, one file missing): totals correct, nothing written.
  verify.sh pass 09: PASS first run (nine pages, `file delete` grep 0, write counts
  unchanged); tablet preview 7 batches / 15 shots / 30 files / 1.2 MB; screenshots checked.

**Safety: no change to the write capability; the new page is read-only. Permanent deletion
does not exist; a real Empty trash needs the "never permanent deletion" rule and the harness
audit amended first, in its own pass.** Files: ShotHistoryEditor.tcl, plugin.tcl, README.md,
CHANGELOG.md, PROJECT_STATE.md.

## v0.10.0 - reconcile action "Unhide" (2026-09-17)

Base: v0.9.1. Owner-authorized fifth write capability (minor bump, flagged). The v0.9.0
view only reported; this adds the one action for a shot that is on disk again while a
trash-manifest line still hides it.

- Reconcile page is now a row list (6 per page, Trash-style Prev/Next pager, 60 px
  buttons, three caption lines per row) with an Unhide button per shot.
- Write path, in full: `perform_unhide ts orig batch` refuses unless that manifest line
  still exists, the file is on disk, and it was not unhidden before; then it APPENDS one
  line `unhidden_at|ts|orig|batch` to plugins/ShotHistoryEditor/reconcile_manifest.txt
  and one `RECONCILE UNHIDE orig=... batch=...` line to delete_log.txt, and logs at INFO.
  Nothing else is written: the trash manifest is never edited, no file moves, history/
  and history_v2/ are untouched, SDB is untouched. No backup is needed because no
  existing byte changes; the append-only files are the audit.
- Effect: `_deleted_filenames_dict` and `_reconcile_records` skip manifest lines whose
  key (ts|orig|batch) is in the reconcile manifest. The shot reappears in the card list
  and Source Inspector; the trash entry and any trash copy stay tracked, so the Trash page
  is unchanged and Restore keeps reporting the collision. Undo = delete the shot again
  (a new manifest line, new key, hides it again).
- Help page: a Reconcile paragraph added; the v0.5.0 save paragraph tightened to make
  room (the block had 36 virtual px left above the bottom bar; verify.sh run 1 caught
  the overflow).
- Offline fixture: stale line and two-file collision unhidden; trash manifest
  byte-identical afterwards; files untouched; bogus key refused with no write; re-delete
  hides again. Nets: check_header_gap.tcl covers the new rows.
- verify.sh pass 08: PASS on run 2 (eight pages incl. the empty state, write-count greps:
  8 write-mode opens, exactly one on the reconcile manifest, logcat); help block ends 56
  virtual px above the bar. Screenshots checked by eye.

**Safety: this version ADDS a write capability (the fifth): append-only writes to two
plugin-owned files, reconcile_manifest.txt and delete_log.txt. Edit/soft-delete/restore
are untouched; no change to the write capability against history files; SDB never
written; `file delete` still absent.** Files: ShotHistoryEditor.tcl, plugin.tcl, README.md,
CHANGELOG.md, PROJECT_STATE.md, tools/check_header_gap.tcl.

## v0.9.1 - Trash page Next button (2026-09-17)

Base: v0.9.0. Tablet-found the same day: Trash had Prev but no Next, so with more than
6 batches the older ones were unreachable ("Showing 1-6 of 7").

- `trash_next_page` dbutton beside Prev, shown only while more batches follow (hidden on
  the last page and on an empty list), `<tag>*` + `-initial 1` form.
- `refresh_trash_page` clamps the offset to the last real page (card-list rule since
  v0.8.1), so over-scrolling or a restore that empties the last page cannot strand the view.
- New regression net `tools/check_trash_pager.tcl` (7-batch fixture: page 1, Next, clamp,
  Prev, empty list). verify.sh pass 07: PASS first tablet run ("Showing 1-6 of 7", Next
  visible, Prev hidden on the screenshot; seven pages, greps, logcat).

**Safety: no change to the write capability (edit/soft-delete/restore untouched); no SQL
or data change - display and paging only.** Files: ShotHistoryEditor.tcl, plugin.tcl,
README.md, CHANGELOG.md, PROJECT_STATE.md, tools/check_trash_pager.tcl.

## v0.9.0 - reconciliation view, read-only (2026-09-17)

Base: v0.8.6. Surfaces the v0.7.0 finding ("file exists on disk but manifest says deleted").

- New page Advanced > "Reconcile hidden shots" (Diagnostics skeleton, paged text).
  `_reconcile_records` = every manifest .shot line whose original path exists again;
  `reconcile_text` reports deleted when/batch, on-disk mtime, trash copy present (two
  files) or missing (stale line), and SDB's view via one read-only SELECT.
- Advanced's note appends "N of them exist on disk again"; Diagnostics gains the count.
- Offline fixture: stale line / two-file collision / absent shot classified correctly,
  nothing moved. verify.sh pass 06: PASS on run 2 (run 1 failed only on a check that
  expected a Diagnostics line that lands on page 2). Screenshots checked by eye.

**Safety: no change to the write capability (edit/soft-delete/restore untouched). The
new page is READ-ONLY: no action buttons, no manifest write, no file move; write-call
counts are pinned by the pass greps.** Files: ShotHistoryEditor.tcl, plugin.tcl,
README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.8.6 - Source Inspector 7-row list (2026-09-17)

Base: v0.8.5. Owner-approved behaviour change, follow-up to the v0.8.5 note.

- `max_recent` 8 -> 7: the Source Inspector lists the latest 7 SDB shots, so its Open
  buttons reach the 60 px touch minimum (52-53 px at 8 rows). `max_recent` is now the
  single source for the page's `n_rows`, the refresh loop (was a hard-coded 8) and the
  query scan cap; `row7_open` left the retheme list.
- `tools/check_header_gap.tcl` asserts every row button on both pages is >= btn_h.
- verify.sh pass 05: PASS first tablet run (six pages, "Showing latest 7 SDB shots", all
  seven Open buttons measured 60 px, greps, logcat); screenshot checked by eye.

**Safety: no change to the write capability (edit/soft-delete/restore untouched); no
SQL, navigation or data change - one fewer row is read and shown.** Files:
ShotHistoryEditor.tcl, plugin.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md,
tools/check_header_gap.tcl.

## v0.8.5 - polish batch (2026-09-17)

Base: v0.8.4. Polish lane: the three notes left by the 2026-09-17 review, one bump.

- Trash Restore / Source Inspector Open buttons: rows are centred bands, button height
  `row_btn_h` = min(btn_h, row_h - sm): Trash 60 px (touch minimum), Source Inspector
  ~53 px (8 rows; the full 60 needs a 7-row list = behaviour change). Was 42 px.
- Glyph literals (pencil, arrows, checkboxes; six lines) come from code points via the
  one-line `_u` helper (`format %c`, always fully qualified): ASCII source, identical
  rendering, each label keeps its text. Not `dui symbol get`: a dbutton label is one
  text item in one font, so a Font Awesome glyph cannot share it with Helvetica.
- `desktop.ini` removed from the plugin folder (workspace and tablet).
- verify.sh pass 04: PASS first tablet run (six pages, "no non-ASCII byte" grep, logcat);
  Restore 60 px / Open 52-53 px measured, glyphs render, screenshots checked by eye.

**Safety: no change to the write capability (edit/soft-delete/restore untouched); no
SQL, navigation, behaviour or data change.** Files: ShotHistoryEditor.tcl, plugin.tcl,
README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.8.4 - header/row gap on Trash + Source Inspector (2026-09-17)

Base: v0.8.3. Tablet-found by verify.sh pass 02: the column header (caption font, 38
virtual px tall) started only md (32) above row 0 on both pages, so the lines touched.

- New layout token `L(caption_h)`: caption line height in virtual units, from
  `font metrics -linespace` (physical) x sh/psh; fallback 1.25 x 16 px x scale.
- Both pages start their list at `header_y + caption_h + md`; the 6 (Trash) and 8
  (Source Inspector) rows redistribute over the remaining space above the bottom bar.
- New offline net `tools/check_header_gap.tcl` (header gap, row spacing, bottom
  clearance); `tools/check_bars.tcl` still passes.
- verify.sh pass 03: PASS first run (six pages incl. the two fixed ones, greps, logcat);
  header 324-362 vs row 0 from 398 virtual on both pages; screenshots checked by eye.

**Safety: no change to the write capability (edit/soft-delete/restore untouched); no
SQL, navigation or data change.** Files: ShotHistoryEditor.tcl, plugin.tcl, README.md,
CHANGELOG.md, PROJECT_STATE.md, tools/check_header_gap.tcl.

## v0.8.3 - review follow-ups (2026-09-17)

Base: v0.8.2. Four hygiene findings from the 2026-09-17 code review.

- `msg` wrapper: core logging.tcl reads a severity flag only in position one, so the six
  `-NOTICE`/`-INFO` calls logged at INFO with the flag as text; a leading flag is hoisted.
- `_navigate_done`: both `close_dialog` fallbacks log via `msg -ERROR` instead of bare catch.
- Five Back buttons (Trash, Source Inspector, Detail, Diagnostics, Help) use
  `_return_to_page` like the Done beside each, not `open_page` on an ancestor.
- Source Inspector Open buttons show/hide with `-initial 1` (v0.8.1 form).
- verify.sh pass 02: version, greps, logcat, 4 of 6 pages PASS; Trash and Source Inspector
  FAIL a pre-existing header/row proximity check (header bottom 362 vs row top 356,
  virtual). Not touched here; its own layout pass. Offline byte-compile + wrapper test: pass.

**Safety: no change to the write capability (edit/soft-delete/restore untouched); no
SQL, layout or data change.** Files: ShotHistoryEditor.tcl, plugin.tcl, README.md,
CHANGELOG.md, PROJECT_STATE.md.

## v0.8.2 - idempotent SDB close (2026-09-15)

Base: v0.8.1. Same defect MaintenanceTracker v0.21.3 fixed the same day.

- `_close_db` was a bare `catch { $db_handle close }`. Every reader closes the handle
  when done and `_open_ro_db` closes it again before opening, so the pre-open close
  failed on every open. catch swallowed the error but left `$::errorInfo` dirty; the
  core BLE runner prints `$::errorInfo` whenever a queued command returns non-1
  (de1_comms.tcl:120), so SHE's error could surface as `BLE error info invalid
  command name "::plugins::ShotHistoryEditor::__sdb_ro"`.
- Fix: close only when `info commands $db_handle` is non-empty; a real close failure
  is logged via `msg`. All 9 close sites (before open + after each reader) go through
  it; no reader touches the handle after closing.

**Safety: no change to the write capability (edit/soft-delete/restore untouched); the
SDB handle stays read-only and no SQL changed.**

Files: ShotHistoryEditor.tcl, plugin.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.8.1 - card-list pagination fixes

Base: v0.8.0. Three owner-reported bugs from tablet screenshots, two root causes.

- Prev showed on page 1 and empty rows kept live-looking Edit buttons: the hides used the
  BARE dbutton tag, which matches only the invisible click rect. All dbutton show/hide
  now uses `<tag>*` with `-initial 1` (survives the pre-`show{}` re-show). Same fix on
  the Trash page (Restore rows, Prev).
- Next paged forever ("Showing 121-121 of 106"): no offset clamp, and the trash manifest
  was subtracted from a count SDB's resync had already reduced via `removed=1`. The count
  now uses exactly the pager's filters; the offset is clamped; Next hides on the last
  page and on an empty list (which also hides Prev).
- Offline harness verify_she_081.tcl: 4 procs byte-compiled, 9 visibility/clamp states,
  no bare-tag dbutton show/hide left. All passed. Tablet verification pending.

**Safety: no change to the write capability; the one SQL change is a read-only SELECT.**

Files: ShotHistoryEditor.tcl, plugin.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.8.0 - dark mode

Base: v0.7.1. Tablet-verified 2026-08-29.

- Sun/moon toggle at the top-LEFT of the main page (top-right is the Select mode button)
  switches all 13 pages between a light and a dark palette instantly.
- All colors moved into one `_apply_palette` proc (harness enforces no palette literal
  elsewhere). Colors are creation-time only, so `_retheme_all`'s bare-tag walk is the
  whole repaint: page backgrounds, text roles, card rows, trash/inspector row loops,
  both entries with their -lbl labels, every button -btn face, three danger -lbl labels.
  Dark danger #ff8a80 / warn #e0a860 / value #8ab4ff lightened for contrast.
- Two previously untagged Edit Preview labels gained fs_label/cv_label tags.
- FA icon font SHE_icon via dui::font, with text fallback.
- Offline harness verify_she_v080.tcl: 79 checks.

**Safety: write capability for history files unchanged. This version adds this plugin's
FIRST persisted setting, `settings(theme)` (light|dark).** Write path: plugin.tcl declares
the settings variable; `preload_pages` runs `plugins load_settings` and heals a missing or
invalid value before `_init_layout`; the toggle handler saves via `plugins save_settings`
on each explicit tap (never in preload). The only file touched is the plugin's own
settings.tdb in the plugin folder, which appears after the first toggle. History files,
history_v2, SDB, backups and the trash mechanism are untouched.

Files: ShotHistoryEditor.tcl, plugin.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.7.1 - a restored file's modification time is stamped

Base: v0.7.0. Built 2026-08-24, after the v0.7.0 tablet run.

**Safety: the write capability is UNCHANGED in kind - one `file mtime` stamp on a file
this plugin has just legitimately moved back into place. No content is touched. This is
the exact mechanism the edit path has used since v0.6.0.**

Write path change: `restore_batch` now stamps `file mtime $path [clock seconds]` on each
successfully restored file, right before `_notify_downstream` triggers the SDB resync
that reads it. Reason: `file rename` preserves the original mtime on this storage, and
SDB's populate only re-reads a shot file whose mtime is NEWER than the one it stored. If
the shot's path was rewritten while the original sat in trash (seen 2026-08-24: the
core's flush-save bug parked a corpse under a trashed shot's filename), SDB holds the
rewrite's metadata and the restored original, being older on the clock, would never be
re-read; Grind Advisor kept computing from the corpse ("yield (no actual)") although the
restored file held `drink_weight 22.2`. That session was fixed by hand-stamping over adb;
this version does it in the restore path. Files that fail to restore are not stamped.
Standing rule: any path that puts a file into history/ must leave its mtime newer than
what SDB stored.

- tools/check_refresh.tcl section H: a day-old file is deleted and restored; the restored
  file's mtime must postdate the restore (fails on the rename-only code).

Files: ShotHistoryEditor.tcl, plugin.tcl, tools/check_refresh.tcl, README.md,
CHANGELOG.md, PROJECT_STATE.md.

## v0.7.0 - the Lumen home page is told about edits and deletes too

Base: v0.6.4. Tablet-verified 2026-08-24 over adb: a full delete printed "Grind Advisor:
SDB resynced, recomputed: 2.4"; the restore brought the Lumen grind card, LAST SHOT yield
and chart series back.

- New `_notify_downstream {what}` wraps `_refresh_grind_advisor` and then calls
  `::lumen::refresh_after_history_change` (Lumen 0.28.0), in that order because Lumen's
  bag cycler reads the SDB that Grind Advisor's step just resynced. All four call sites
  (edit, delete, partial delete, restore) use it, with the v0.6.3 contract: once per
  batch, only when files moved, `info procs` guard, errors logged and swallowed.
- tools/check_refresh.tcl section G proves it with a counter stub; sections A-E pass
  unchanged (without `::lumen` the wrapper degrades to v0.6.3 behaviour).
- Finding: the card list hides any filename present in the trash manifest even if a file
  by that name exists on disk (un-deletable here); reconciliation view is owner's call.

**Safety: the write capability is UNCHANGED. Adds a second guarded, read-only downstream
call; no new write of any kind.**

Files: ShotHistoryEditor.tcl, plugin.tcl, tools/check_refresh.tcl, README.md,
CHANGELOG.md, PROJECT_STATE.md.

## v0.6.4 - the startup line said "vv0.6.3" (log text only)

Base: v0.6.3. Verified on the 23:48 restart ("started card browser v0.6.4").

- plugin.tcl's startup message prepends a literal `v` and the `version` value carried one
  too. Fixed on the variable: this was the only plugin of 24 on the tablet storing a
  prefixed version. The core reads the variable only as a "metadata loaded" sentinel
  (plugins.tcl:204). Keep the `v` in prose, out of the value.
- tools/check_refresh.tcl section F rebuilds the startup line from plugin.tcl's own
  literal and fails on a doubled prefix.
- v0.6.3 was tablet-verified before this (23:34 restart, no error from SHE, GrindAdvisor
  or Lumen; the D_Flow_Espresso_Profile / A_Flow namespace errors are pre-existing).

**Safety: nothing changed. One string literal and one comment. No code path, no write.**

Files: plugin.tcl, tools/check_refresh.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.6.3 - a deleted shot now stops counting towards the grind recommendation

Base: v0.6.2. Owner-reported: deleting a shot did not move the grind recommendation,
"just like last time when I edited".

- v0.6.0 put the Grind Advisor call inline in `perform_metadata_edit` only. SDB's
  populate already flags a vanished file `removed=1` by absence and Grind Advisor already
  filters that column, so the missing notification was the whole gap.
- The call now lives in ONE shared proc `_refresh_grind_advisor` used by edit, delete and
  restore (do not re-inline): once per batch, only when files actually moved; absent
  plugin or thrown error leaves this plugin's own result a success with an empty note.
  The Delete Result page now reports the resync line like the Edit Result page.
- New tools/check_refresh.tcl drives the real procs against a temp history folder with a
  counter stub and asserts all of the above; negative-tested against v0.6.2 wiring.

**Safety: the write capability is UNCHANGED. Soft delete still moves `history/<f>.shot`
and `history_v2/<f>.json` into this plugin's trash/ with manifest and audit log; the edit
path still writes exactly one targeted settings-block line. No SQL, nothing permanently
deleted; this version adds a NOTIFICATION, no new write.**

Files: ShotHistoryEditor.tcl, plugin.tcl, tools/check_refresh.tcl (new), README.md,
CHANGELOG.md, PROJECT_STATE.md.

## v0.6.2 - every page's way out is the bottom-left corner (display only)

Base: v0.6.1. Owner asked for the rest of the pages after v0.6.1.

- All 13 bottom bars now lead with the exit control at `left_x`: Done on Detail,
  Diagnostics, Help, Trash, Recent, Edit Result, Delete Result; Cancel on Edit Confirm,
  Delete Review and Delete Confirm (the destructive button deliberately stays right).
- Every button keeps its width (Detail's wide Edit Metadata Preview stays 696px).
- New tools/check_bars.tcl runs all 13 pages' `setup{}` with the framework stubbed and
  asserts each bar starts at the left margin, has no overlaps, stays inside the right
  margin. It caught the first cut dropping Done on top of Back on Diagnostics/Help.

**Safety: no write behavior changed. Button x coordinates only.**

Files: ShotHistoryEditor.tcl, plugin.tcl, tools/check_bars.tcl (new), README.md,
CHANGELOG.md, PROJECT_STATE.md.

## v0.6.1 - Edit Preview's Done moves to the far left (display only)

Base: v0.6.0. Owner request: leaving the editor is Done on Edit Preview then Done on the
card list, and the two were in opposite corners.

- Edit Preview's Done now sits at `left_x` (92..492), Back beside it (512..912); both run
  the same command. No overlap, no overflow.
- Other dialog pages still carried Done at the right; out of scope here (done in v0.6.2).

**Safety: no write behavior changed. One button's x coordinate.**

Files: ShotHistoryEditor.tcl, plugin.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.6.0 - an edited shot now LOOKS edited (and Grind Advisor follows it)

Base: v0.5.4. Tablet-verified 2026-08-19: re-saving grinder_setting 8 over 8 on
20260818T164430 stamped mtime 1787084996 and SDB's row picked up '8' with that
file_modification_date; before, both were 1787057093 and SDB said '7.5'.

**Safety: the write capability is unchanged in kind. This plugin still writes exactly one
thing - the single targeted line inside `history/<shot>.shot`'s settings block - plus its
own backups, manifest and log. `history_v2` is untouched, no SQL is issued, nothing is
deleted. Two things were added on top of that same save: the file's modification TIME is
stamped, and Grind Advisor is told the edit happened.**

The bug: every edit this plugin had ever made was invisible to SDB. `file rename` on this
tablet's storage falls back to a copy, and Tcl's copy preserves timestamps, so the
replacement file carried the original's mtime. SDB re-reads a .shot only when
`file mtime > file_modification_date` (SDB.tcl:2060), so it skipped every edited file
forever; SDB's own "Resync database to history" button could not see them either.

Write path change: one `file mtime $path [clock seconds]` on the file this plugin has just
rewritten, run AFTER the post-rename verification so a rolled-back save never stamps.
Wrapped in `catch`: a failed stamp logs a NOTICE and does not fail the already-successful
save. Content is untouched.

- Auto-refresh: on a successful save `::plugins::GrindAdvisor::refresh_from_history` is
  called when that plugin exists (guarded on existence and errors); its result line is
  shown on the save-result page ("Grind Advisor: SDB resynced, recomputed: 6.0").
- Existing edits: files edited before this version keep their original timestamp;
  re-saving the field (no no-op guard) is a real write and restamps them.

Files: ShotHistoryEditor.tcl, plugin.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.5.4 - Pass 5.4 Theme/Contrast Bugfix (display only)

Base: v0.5.3. Tablet-verified 2026-08-09 by owner. Fixes the "inverted colors" report
under Lumen (near-black background, shapeless buttons).

- Root cause (from the app log): Lumen's DYE integration runs `dui theme set DYE_Lumen`
  (skin.tcl:1831) and never restores it; this late-loading plugin's un-themed `she_btn`
  aspect landed in that theme and its shape resolved empty (BeanScanner v0.1.2's bug).
  Also fpdialog pages carry no background of their own, so the dark canvas showed through.
- Fix (BeanScanner's verbatim pattern): `she_btn` registered with `-theme default` plus
  explicit fills; new `_page_bg` paints a full-page grey (#d5d6e3) first on all 13 pages;
  color tokens (page_bg/btn_fill/btn_disabled_fill/btn_label_fill) in the layout block.

**Safety: display-only. Same write capabilities as v0.5.0 (metadata save + soft delete),
nothing new.**

Files: ShotHistoryEditor.tcl, plugin.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.5.1 / v0.5.2 / v0.5.3 - navigation bugfixes

Recorded in plugin.tcl's header at the time; summarized here.

- 5.1: `_return_to_page` loops `close_dialog` once per stacked level.
- 5.2: applied GrindAdvisor v1.8.8's flow-interruption navigation pattern.
- 5.3: reverted 5.2's direct `dui page load` to stacked ancestors (core page_stack
  truncation bug, confirmed in de1app-core source) in favor of one-level-at-a-time
  unwinding, and made the Done capture skip this plugin's own pages.

**Safety: navigation only; write capabilities unchanged from v0.5.0.**

Files: ShotHistoryEditor.tcl, plugin.tcl.

## v0.5.0 - Pass 5.0 Real Metadata Save

Base: v0.4.1. Second destructive-capability pass. Adds real metadata save: one settings{}
key at a time into `history/<filename>.shot`, with backup, verified write, edit manifest
and audit log. SDB and history_v2 remain untouched; soft delete/trash/restore unchanged.

Findings:
- .shot format: flat `key value` lines plus one `settings { ... }` block. Real files hold a
  nested multi-line `read_only_backup {...}` inside it, so the existing first-bare-brace
  scan (harmless for reading because editable keys sort before it) would be wrong for
  writing. The write path tracks brace depth (`_settings_block_bounds` /
  `_find_settings_key_line`); true block end verified at line 490 of a sample, not 409.
- SDB.tcl:2948 calls a core `modify_shot_file` for category edits, immediately followed by
  an SDB UPDATE; neither core proc is in this workspace, so this pass implements its own
  verified cycle rather than guess the API or touch SDB.
- `history_v2/<f>.json` is NOT written (no consumers found; its meta key names differ).
  A saved field can leave history_v2 stale; documented in Help/README.
- Latent crash fixed in the existing read path: `read_legacy_settings` /
  `_parse_settings_file` compared unescaped braces and threw on the first real multi-line
  file; both braces now escaped, behavior unchanged.

Write path (`perform_metadata_edit`): validates field against the `editable_fields`
allowlist and filename via `_safe_filename`; backs up the WHOLE original file to
`plugins/ShotHistoryEditor/backups/<timestamp>_<batchid>/` before any write; builds the
new content in memory (only the one targeted line changes; never inserts a key - a
missing settings{} block or missing key fails cleanly); writes to a temp file in the same
directory and verifies it with `_parse_settings_file` (a failed pre-rename verify leaves
the original untouched and the temp file behind, never `file delete`); atomically
`file rename`s the temp over the original; re-verifies, and if that fails renames the
backup back into place automatically. Every save is appended to `edit_log.txt`; successful
saves also to `edit_manifest.txt`, which the card list and Detail page overlay onto
SDB-sourced values (`_all_edit_overlays` / `_apply_edit_overlay`) since SDB is never
written. Empty new value is rejected before any file operation; numeric warnings do not
block.

UI: Edit Preview gained Save Change -> Before/After Edit Confirm (Cancel / danger Save
Change) -> Edit Result (message + backup path) -> back via `_return_to_page`.

**Safety: SDB never written (zero INSERT/UPDATE/DELETE/ALTER/DROP/CREATE TABLE/VACUUM/
REINDEX in the plugin); `file delete` never called. File writes: temp+rename of the one
targeted .shot, the plugin's own backups/, edit_manifest.txt, edit_log.txt, plus the
unchanged delete-pass writes (trash/, trash_manifest.txt, delete_log.txt).** Headless test
against the real sample .shot files: exactly one line changes, byte-identical otherwise
(raw sensor arrays and read_only_backup untouched); backup equals the original; Cancel
performs zero file operations; a simulated post-rename failure auto-restores and logs.

Known limitations: history_v2 stays stale after a save; edit manifest grows forever.

Files: ShotHistoryEditor.tcl, plugin.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.4.1 - Pass 4.1 Delete-Flow Navigation Bugfix

Base: v0.4.0. Tablet-tested by owner: delete single/multiple, Cancel at Review and
Confirm, restore from Trash, persistence across restart, Result page Done - all PASS.

- Delete Result's Done did nothing: `open_page` targeted a page already 3 levels down the
  dialog stack; `open_dialog` on a stacked page does not throw but performs no
  transition, so `show{}` never ran.
- Fix: `_return_to_page {target}` (GrindAdvisor's recovery technique): `close_dialog`
  once, then `dui page load $target` only if `dui page current` is not the target; never
  `open_dialog`. Applied to Delete Review/Confirm Cancel, Delete Result Done, Advanced
  Back. Headless simulation confirmed the fall-through; 1-level cases never take the
  corrective branch; delete/restore output byte-identical to v0.4.0.

**Safety: navigation only. No SQL write keywords, no `file delete`; delete/restore/trash
logic and SDB reading untouched.**

Files: ShotHistoryEditor.tcl, plugin.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.4.0 - Pass 4.0 Real Soft Delete

Base: v0.3.3. First destructive-capability pass. Adds soft delete: file moves to a plugin
trash with two-step confirmation, manifest, audit log and restore. No permanent deletion,
no metadata editing, SDB untouched.

Finding: SDB.tcl, GrindAdvisor.tcl and visualizer_upload never reference history_v2;
SDB's populate/create read only `history/*.shot`; history_v2 has no index of its own.
Decision: move both `history/<f>.shot` and its `history_v2/<f>.json` together.

Write path:
- Trash structure: `plugins/ShotHistoryEditor/trash/<timestamp>_<batchid>/` holds moved
  files; `trash_manifest.txt` has one `timestamp|original_path|trash_path|batch_id` line
  per moved file; `delete_log.txt` is the human-readable audit log. All under the plugin
  folder, excluded from filelist.txt/packaging.
- `perform_delete_batch`: rejects unsafe/path-traversal filenames before touching the
  filesystem; moves `history/<f>.shot` and, if present, `history_v2/<f>.json` with
  `file rename` only (never `file delete`). If any move fails the batch stops at once;
  everything already moved is still recorded in the manifest and reported.
- `restore_batch`: moves files from a trash batch back to their original paths (move
  only) and drops them from the manifest; if the original path already has a file, that
  one is left in trash/manifest as a collision rather than overwritten, retryable later.
- Confirmation flow (replaces the preview-only Delete Preview): Review (exact shots and
  exact files that will move, "Nothing is permanently deleted", Cancel/Continue) ->
  Confirm (type the exact shot count into a top-half field, danger-colored Confirm
  Delete, Cancel always available) -> Result (counts + trash path) -> main page, which
  exits selection mode and reloads. Typed count chosen because no hold-to-confirm pattern
  exists in this workspace.
- List consistency: SDB is never modified, so `load_recent_shots` /
  `load_recent_shots_paged` scan a buffer of rows and filter out manifest filenames
  before slicing to the page; `_visible_shot_count` feeds "Showing X-Y of N"; Advanced
  shows "N deleted shot(s) hidden (SDB not modified; it may resync on its own)".
- New Advanced > Trash / Restore page: one row per batch (date, shot count, file count)
  with a Restore button. No "Empty trash" button exists.

**Safety: SDB never written (grep for INSERT/UPDATE/DELETE/ALTER/DROP/CREATE TABLE/VACUUM/
REINDEX: none); history file CONTENT never edited or deleted - only `file rename` moves
whole files, plus `file open w/a` on the plugin's own manifest and log. Metadata editing
still writes nothing. No permanent deletion.** Headless sandbox test: correct files move
with correct manifest/log; Cancel at either step performs zero file operations; restore
round-trips including a simulated collision; unsafe filename rejected before any move.

Known limitations: 200-row filter buffer; empty batch folders may remain if every file
fails validation (no `file delete` added to clean them); restore is per batch.

Files: ShotHistoryEditor.tcl, plugin.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.3.3 - Pass 3.3 Button Font Bugfix

Base: v0.3.2. Every button label still rendered undersized after v0.3.2.

- Root cause: button labels go through dui's own label path; the v0.3.2
  `dui aspect set -type dbutton_label ... font_size` key was not honored on the tablet,
  so buttons fell back to a small skin default.
- Fix: one `font_button` Tk font (20px bold, `font_scale` basis like the card fonts)
  passed via `-label_font $L(font_button)` on all 32 `dui add dbutton` calls (per-instance
  override proven in visualizer_upload/plugin.tcl:467). Removed the dead aspect
  font_size key and `btn_px`; the aspect keeps only `shape round radius`.
- "Clear Selection" (longest label) checked to fit at the reference resolution.

**Safety: button font only; still no write/delete behavior in this version.**

Files: ShotHistoryEditor.tcl, plugin.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.3.2 - Pass 3.2 Coordinate-Basis Bugfix

Base: v0.3.1. The whole UI rendered at about half size in the top-left quadrant with
overlapping card text.

- Root cause: fpdialog pages are drawn in a fixed VIRTUAL 2560x1600 space that dui
  rescales to the physical screen; v0.3.1 fed `winfo screenwidth/screenheight` into every
  coordinate, so dui rescaled already-physical coordinates a second time (~0.52x). The
  plain Tk fonts were not rescaled, so they no longer fit the shrunk card spacing.
- Fix: `scale` (all coordinate tokens) from the fixed virtual base; `font_scale` (the
  five SHE_* fonts) from the physical screen. Every token formula otherwise unchanged.
- Verified by headless recompute: content spans ~1244px physical, bottom bar ~50px above
  the bottom edge, card baselines clear the fonts.

**Safety: no SQL write keywords, no file delete/rename/move/copy calls anywhere. Delete
remains preview-only.**

Files: ShotHistoryEditor.tcl, plugin.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.3.1 - Pass 3.1 Input Fix + UI Precision Pass

Base: v0.3.0. Selection mode had no working buttons on the tablet.

- Root cause: v0.3.0 stacked several full-size dbuttons at identical coordinates and
  toggled visibility; tap routing became ambiguous. Fix: exactly one dbutton per slot
  with a stable dispatcher reading `select_mode` at click time; only the label is
  reconfigured. Entering the main page always resets selection state.
- New `_init_layout` token array (spacing, margins, card/button dimensions, zones, five
  fixed fonts 40/24/22/19/16) verified at 1340x800 (margin 48, content_w 1244, value_x
  492, bar 716-776); `rounded_rect` helper; 5 cards per page; Prev/Next toolbar row with
  "Showing X-Y of N shots" (read-only COUNT); tokens applied to every page.

**Safety: no save buttons, hooks or popups; no shot-history files modified; delete is
preview-only; no SQL write keywords, no file delete/rename/copy/mkdir calls.**

Files: ShotHistoryEditor.tcl, plugin.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.3.0 - Pass 3 One-Page Workflow Redesign

Base: v0.2.0.

- Card-based main page opens directly to recent shot cards (date/time, shot time, grind,
  dose, yield, bean/profile) with an Edit button to the existing Edit Metadata Preview.
- Select/Cancel selection mode with a bottom bar (Delete, Clear Selection). Delete opens
  a Delete Preview showing the count and "No files will be modified in this version";
  Cancel and OK both just close it.
- Shot Detail, Diagnostics and Help moved behind a new Advanced / Source Inspector page.
- Prev/Next paging for the card list (offset-based, existing read-only SDB query).
- Layout from a small set of constants against the virtual dui canvas.

**Safety: no write behavior exists in this version. No SQL write keywords, no file
delete/rename/move calls. Delete is preview-only; raw sensor data never shown or edited.**

Files: ShotHistoryEditor.tcl, plugin.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.2.0 - Pass 2 Edit Preview + Scrollable Detail Pages

Base: v0.1.0.

- Paged scrolling controls for Shot Detail, Diagnostics and Help / Guide.
- Edit Metadata Preview page from Shot Detail: safe field selection for legacy
  `history/*.shot` settings metadata, current value, new value, before/after preview,
  numeric warnings.
- Diagnostics for scrolling support and selected-shot source matching.

**Safety: all runtime data access read-only; no save button, no shot hooks, no
after-shot popups.**

Files: ShotHistoryEditor.tcl, plugin.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.1.0 - Pass 1 Read-only Source Inspector

- Initial plugin shell with read-only SDB browsing from `plugins/SDB/shots.db`.
- Recent-shot list, detail comparison, diagnostics and help pages.
- Legacy `history/*.shot` settings-block and `history_v2/*.json` meta-block inspection.

**Safety: read-only; no edit controls, save buttons, shot hooks or after-shot popups.**

Files: ShotHistoryEditor.tcl, plugin.tcl, filelist.txt, README.md, CHANGELOG.md,
PROJECT_STATE.md.
