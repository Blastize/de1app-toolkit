# Grind Advisor - Changelog

Entries follow the CLAUDE.md doc cap (about 15 lines each; entries that added or changed a write
capability keep their full write-path description). The long pre-trim entries survive in the
Desktop archive snapshot of each version ("GrindAdvisor Archive/GrindAdvisor vX.Y.Z").

## v3.16.3 (popup timer vs Visualizer upload race) - 2026-09-17

Base: v3.16.2.

- With visualizer_upload enabled, SDB inserts a shot on the LEAVE of
  `::plugins::visualizer_upload::uploadShotData` (SDB.tcl:107-109), not in its own listener. The
  upload is a synchronous http::geturl that keeps the event loop running, so a slow or failing
  upload (retries, up to ~27 s) outlasted after_flow_complete (+5 s) plus popup_delay_ms; `run`
  read the previous id, returned without marking, and the espresso popup surfaced after the NEXT
  flow event (flush / steam / rinse). Found by the 2026-09-17 review.
- New `_install_upload_trace` (own `upload_traced` guard, called beside `_install_nav_watch`) adds
  a leave trace on that proc; `_upload_trace` calls `_schedule_run any`. The handler only schedules
  an `after`, so SDB's synchronous insert is always done before the timer fires. No upload proc =>
  no trace, no error. The after_flow_complete path is unchanged (covers the no-Visualizer install).
- Offline: 4 procs byte-compiled, trace install/idempotence/fire/no-proc asserted in tclsh.

**Safety status: read-only, unchanged. No write behavior exists in this version beyond the
v3.9.0 Recalculate button (SDB's own resync). Hook registration only.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.16.2 (History back to opaque - owner preference) - 2026-09-03 - TABLET-VERIFIED 2026-09-03 (dark theme: History renders the flat v3.15.x page again, popup->History->Done clean, no glass/fallback/error lines)

Base: v3.16.1.

- Review + DevBridge re-verification 2026-09-17: all 7 fpdialog pages pass (text, overlap, bounds),
  hook/start lines present, no Tcl errors; README version header corrected from v3.15.0 to v3.16.2.
  No code change, no version bump. Read-only status unchanged.
- Owner verdict on the v3.16.0 glass History: "doesn't have to be glass" - reverted.
  `_render_history_dialog` is the opaque v3.15.x draw again (popup_theme scrim + flat cards);
  the `_glass_dim` / `_glass_panel` helpers and the dim loading are removed (History was their
  only consumer; they live on in the v3.16.1 archive if ever wanted back).
- The popup, Curve and Why? keep their glass; the v3.16.1 draw-before-place flash fix stands.
- Offline: 175 procs byte-compiled; asserted History references no glass, Why?/Curve/popup
  still do, and the flash-fix ordering is intact.

**Safety status: read-only, unchanged. Presentation only.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.16.1 (glass draws before the canvas is placed - kills the black flash) - 2026-09-03 - TABLET-VERIFIED 2026-09-03 (dark theme: Why? glass card, History glass over dim art incl. Next re-render and Done, Curve->Back regression clean, no fallback or error lines; flash gone by construction, owner to confirm by eye)

Base: v3.16.0 (below; never shipped alone).

- Owner report on v3.15.0: Curve -> Back flashed a glitchy black square slightly larger than
  the popup for a frame. That square is the overlay canvas: placed at card+ring size while its
  background was still the bare scrim (black in the dark material), before the art was drawn.
- `_glass_present` now draws the ring, card and border FIRST and places the canvas LAST; the
  popup/Curve/Why? dialogs leave the canvas unplaced in glass mode until then (opaque keeps the
  immediate full-screen place); History places only after its dim base layer exists.
- Offline: 177 procs byte-compiled; ordering asserted (place after border / after dim) in all
  four overlays.

**Safety status: read-only, unchanged. Draw-order only.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.16.0 (Why? and History go glass - every overlay now) - 2026-09-03 - shipped inside v3.16.1

Base: v3.15.0.

- Why? card: the exact popup/Curve path (`_glass_setup`, draw-scoped `_colors_override`,
  shared `_present_card`; opaque v3.13.x card on any failure).
- History keeps its full-screen page layout, so its glass is different: the skin's baked DIM
  art (the modal scrim, unconsumed until now - new lazy `_glass_dim` loader, strict size check)
  as the base layer, each shot card cut from the slab by new `_glass_panel` (corner rounding
  and double-radius border copied verbatim from `_glass_present`); per-card and whole-draw
  opaque fallbacks.
- All four overlays (popup, Curve, Why?, History) now glass; opaque fallbacks follow popup_theme.
- Offline: 177 procs byte-compiled clean; body assertions for both dialogs' glass wiring.

**Safety status: read-only, unchanged. Presentation only.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.15.0 (the Calibration Curve goes glass) - 2026-09-03 - TABLET-VERIFIED 2026-09-03 (dark theme, Lumen 0.41.0: tile->Curve->OK and popup->Curve->Back->OK, glass both times, no fallback or errors in the log)

Base: v3.14.5.

- `_show_curve_dialog` now runs the exact glass-or-opaque path the after-shot popup proved in
  v3.14.x: `_glass_setup`, the draw-scoped `_colors_override` (so `_obutton` and the plot wear
  the material's palette), and the shared `_present_card` call site (card + 24px art ring,
  Tk grab, opaque v3.13.x card on ANY glass failure). No new mechanism, no layout change.
- Why?/History overlays intentionally stay opaque; comments updated to say so.
- Offline harness: sourced + all 175 procs byte-compiled clean; curve body asserted to use
  `_glass_setup`/`_present_card` and to have dropped its own `_opoly` panel.

**Safety status: read-only, unchanged. Presentation only; no write behavior exists beyond the
v3.9.0 button-gated SDB resync.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.14.5 (the glass draw's palette reaches the buttons too) - 2026-09-01 - TABLET-VERIFIED 2026-09-01 (closes the glass-popup feature: both themes, grab modality, live page around the card, seam-free ring)

Base: v3.14.4.

- Owner's light-theme screenshot: the light material card rendered DARK buttons, because
  `_obutton` fetches its own colors and got the popup_theme palette.
- The theme override is now a draw-scoped variable consulted by `_colors` itself:
  `_show_overlay_dialog` sets it for a glass draw and clears it on exit (`_close_dialog`
  clears it again), so every helper in that draw wears the material's palette while the
  Why?/Curve/History overlays keep following the Popup theme setting.
- Harness 98 checks.

**Safety status: read-only, unchanged. Palette plumbing only.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.14.4 (seam-free art ring: stop guessing edge colors) - 2026-09-01 - superseded by v3.14.5 before tablet sign-off

Base: v3.14.3.

- Owner zoomed screenshot: the card boundary still read as a hard cliff on ALL edges. Every
  approach so far guessed a boundary color; any guessed color mismatches the live page somewhere.
- Overlay now extends a 24px art ring beyond the card; its whole base layer is the skin's PLAIN
  page background (new required `bg` material key, Lumen 0.39.1) cropped at identical screen
  coordinates, so the canvas boundary lands on pixel-identical art and disappears.
- Corner-rect and sampled-bg guessing removed; a material without `bg` falls back to the opaque
  popup; margin clamps at screen edges; text coords shift via the single `_present_card` call site.
- Harness 93 checks (two crops, base-layer order, margin placement, no-guessed-colors assertion).

**Safety status: read-only, unchanged.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.14.3 (per-corner blending softens the card's lower edges) - 2026-09-01 - superseded by v3.14.4 before tablet sign-off

Base: v3.14.2.

- Owner review of v3.14.2 ("much better"): lower corners read as sharp dark notches, because the
  canvas background was sampled once from the slab's top-left.
- Each corner gets its own small rect under the card image, filled with the slab's pixel at that
  corner, so all four corners blend.
- Paired with a Lumen bake-recipe tune (dark tint 0.34->0.20, blur 20->16, brightness 1.22->1.28);
  asset change only.

**Safety status: read-only, unchanged. Four canvas rects.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.14.2 (place merges options: the card-only overlay was oversized) - 2026-09-01 - superseded by v3.14.3 before tablet sign-off

Base: v3.14.1.

- On the tablet everything right and below the card's top-left corner was black.
- Root cause: Tk `place` merges options across calls and sums `-width` with `-relwidth`; re-placing
  the full-screen overlay at the card rect left the rel options standing, so the canvas was
  screen+card sized at the card's position.
- `place forget` before each re-place, in both directions (card placement and the glass-failure
  full-screen restore). Two harness checks pin the forget-first ordering; 90 checks total.

**Safety status: read-only, unchanged. Two `place forget` calls.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.14.1 (glass popup shows the LIVE page around it) - 2026-09-01 - superseded by v3.14.2 before tablet sign-off

Base: v3.14.0.

- Owner report: the area around the glass card showed empty blocks. The full-screen scrim was the
  skin's baked art, which contains no live text/chart; nothing can photograph the live screen
  (checked core + AndroWish).
- The overlay now covers only the card; the real live page stays visible around it. Card itself
  unchanged (slab crop, transparent corners, double-radius border).
- Modality via Tk grab (owner's pick): released explicitly in `_close_dialog` (only our own grab),
  by widget destroy, and by `_nav_state_change`'s flow-start close; grab retried on the 200/600 ms
  raise ticks, degrades to non-modal if it never lands.
- Corners sit on a canvas bg sampled from the slab's corner pixel; the `dim` asset is no longer
  consumed (still contract-validated); any glass failure restores the full-screen opaque popup.
- Harness 88 checks.

**Safety status: read-only, unchanged. Display/input-shape only; no math, hooks or popup guarding touched.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.14.0 (frosted-glass popup on skins that provide the material) - 2026-09-01 - superseded by v3.14.1 before tablet sign-off

Base: v3.13.1.

- Owner request ("iOS 27 liquid glass"): when the skin offers a glass material, the after-shot
  popup renders as a frosted translucent card.
- Consumes `::lumen::glass_material` (Lumen 0.39.0): a pre-blurred full-screen slab cropped to the
  card rect (`photo copy -from`), corners rounded by transparent pixels, hairline border poly at
  double radius (the `-smooth 1` half-curvature lesson).
- Opaque fallback is the rule: no proc, `{}`, unreadable files, size mismatch or any error mid-draw
  renders the exact v3.13.x popup; one shared `_card_backdrop` call site per card.
- Glass text follows the material's theme via a `_colors` override; Why?/Curve/History stay opaque.
  Both cards (result and error/estimate) get glass. Photos tracked per draw and deleted on close.
- Harness 80 checks (gating, lifecycle, photo-leak, corner math, glass-vs-fallback).

**Safety status: read-only, unchanged. No write behavior exists beyond the v3.9.0 SDB resync button. Display-only.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.13.1 (a cleaning profile no longer blanks the recommendation) - 2026-08-31 - TABLET-VERIFIED 2026-08-31

Base: v3.13.0.

- Owner report: the "Cleaning/Forward Flush x5" profile made the skin's grind tile drop to "-".
  With segmentation on, `current_bag_key` composed bean + cleaning profile, a bag with no shots.
- `current_bag_key` now answers "" (identity indeterminate) when segmentation is on and the live
  `profile_title` matches the existing `_text_is_nonespresso` gate; consumers fall back to their
  fail-safes (saved rec stays on the tile, `starting_estimate` silent). Segmentation-off untouched.
- Known corner: Recalculate under a cleaning profile reports "no bean set, nothing to recompute".
- Harness 58 checks incl. the exact tablet profile string and a v3.12.0 repro.

**Safety status: read-only, unchanged. No write behavior exists beyond the v3.9.0 SDB resync button. One identity guard; no recommendation math touched.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.13.0 (new-bag starting estimate) - 2026-08-29 - TABLET-VERIFIED 2026-08-29

Base: v3.12.0.

- Owner-decision reversal, recorded: reverses the 2026-08-15 "reset only, never seed a guessed
  grind" decision (owner, v3.13.0 pass spec). The v3.7.0 bag-key reset itself stays.
- New public `starting_estimate`: display-only starting grind for a bag with NO shots, from bags
  whose Bag Stats Theil-Sen fit converged (v3.5.0 trust gate) on the same profile. Ladder:
  same_coffee -> same_roaster (median) -> same_profile (median of 6 most recent bags) -> {}.
  Median, rounded to increment, clamped.
- Not evidence: never enters the regression, n, slope or Calibration Accuracy. Only callers are
  `show_last_recommendation` ("Start ~X (est. from N bags)", ok-0 card, never saved) and
  `show_bag_stats` (leading source card, excluded from the bag counter). Help paragraph added.
- Plumbing: `_bag_cards_data` split into `_bag_data` + renderer (byte-identical cards vs v3.12.0);
  `current_bag_key` split into `_current_bag_values`/`_current_profile`.
  `recommendation_for_current_bag` still returns {} for a shotless bag (Lumen tile: later pass).
- Harness verify_ga_v3130.tcl: 47 checks incl. nothing-new sweeps for SQL writes and file writes.

**Safety status: read-only, unchanged. No write behavior exists beyond the v3.9.0 SDB resync button; the estimate path issues only the existing Bag Stats SELECTs.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.12.0 (page dark mode) - 2026-08-28

Base: v3.11.1.

- Sun/moon button top-right of the settings page switches all seven dui pages between a light and
  a dark palette instantly; the choice persists across restarts. Separate from Popup theme, which
  keeps governing the after-shot popup and the History/Bag Stats overlays.
- Every page color moved into one `_apply_palette` proc (harness enforces no palette literal
  elsewhere; the popup's independent `_colors` dict excluded). `_retheme_all` repaints backgrounds,
  section cards, texts, the nine entries, the ten checkboxes, the gauge and every button face.
  A restart in dark runs one retheme pass after page creation.
- Harness verify_ga_v3120.tcl, 75 checks. Tablet-verified 2026-08-29.

**Safety status: read-only, unchanged. The one new persisted value is `theme` (light | dark) in the plugin's own settings, saved on each explicit toggle tap.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.11.1 (normalization only trusts plausible actuals) - 2026-08-24

Base: v3.11.0.

- Caught live during v3.11.0 verification: recommendation 5.5 -> 23.7. `_norm_time` normalized by
  a 13.9g actual yield the engine's own yield-source logic had rejected ("out of ratio 0.7"),
  inflating a 50.1s shot to 137.0s; the n=1 rung, newly on normalized time, made that the answer.
  The regression rung carried the same exposure since normalization existed, merely diluted.
- `_norm_time` now gates actuals through the same plausibility bounds as `_resolve_dose` /
  `_resolve_yield` (dose within dose_min..dose_max, yield ratio within ratio_min..ratio_max);
  a rejected actual contributes nothing and the shot falls back to raw time. Independent of
  `dose_yield_mode`.
- check_guards.tcl pins both incident rows, absurd ratio, zero weigh, out-of-range dose, and the
  end-to-end case: the 50.1s/13.9g shot alone answers 9.2.
- Tablet-verified the same hour: Recalculate reports "SDB resynced, recomputed: 9.2".

**Safety status: read-only, unchanged. No write behavior exists beyond the v3.9.0 SDB resync button.**

Files: GrindAdvisor.tcl, tools/check_guards.tcl, plugin.tcl, docs.

## v3.11.0 (the 1- and 2-shot rungs use normalized time) - 2026-08-24

Base: v3.10.2.

- Owner-requested from a real shot: 9.6s on the clock but 22.2g of a 38g target; yield-corrected
  16.4s. Raw time recommended 5.5 -> 2.4; normalized error justifies 5.5 -> 3.6.
- `_ladder_small` consumes `t_norm` for the latest shot and the 2-shot slope. No behaviour change
  without scale data (`t_norm == t_raw`); all six historical bag cases answer byte-identically.
- The rec's `normalized` flag is set from the shots the rung consumed; the reason names the series
  ("First shot on normalized time 16.4s"); Why? gains a "Normalized time" row on ladder rungs.
- The Curve keys its y series on the rec's `normalized` flag, so a 3.10.x-saved rec still plots
  in the series that produced its number; axis caption follows.
- check_guards.tcl: tablet case (-> 3.6), no-scale identity (-> 2.4), both 2-shot flag paths.

**Safety status: read-only, unchanged. No write behavior was added; the one database write remains the SDB resync behind the Recalculate button (v3.9.0).**

Files: GrindAdvisor.tcl, tools/check_guards.tcl, plugin.tcl, docs.

## v3.10.2 (a rounded grind was not a clean decimal) - 2026-08-23

Base: v3.10.1.

- Tablet log after Recalculate: `recomputed: 2.4000000000000004`. `_round_grind` divides, rounds
  and multiplies back; at increment 0.1, 24 x 0.1 is the next double above 2.4.
- Not cosmetic: the value becomes `next` in the rec dict, so it was already in
  last_recommendation.tdb and in what Lumen and ShotHistoryEditor read; every display path formats
  numbers, so it surfaced only when SHE printed `refresh_from_history`'s raw summary.
- `_round_grind` snaps through a fixed-precision string (also collapses -0.0);
  `refresh_from_history`'s summary goes through `_fmt_num`. Fixed at the source, not the display.
- check_guards.tcl sweeps 0.0-50.0 at every real increment asserting on the PRINTED form, plus the
  tablet case 2.43 -> 2.4. The old code fails only at increment 0.1 (the one this tablet uses).
- No recommendation moved; all six bag cases byte-identical.

**Safety status: read-only, unchanged. No write behavior was added; the one database write remains the SDB resync behind the Recalculate button (v3.9.0).**

Files: GrindAdvisor.tcl, tools/check_guards.tcl, plugin.tcl, docs.

## v3.10.1 (the untrusted rung had no label) - 2026-08-23

Base: v3.10.0.

- Owner saw `regression_unt...` on the home screen: v3.10.0 added the `regression_untrusted` rung
  without a `_forecast_method_label` arm, and the `default` arm returned the key verbatim.
- New arm: "Regression not trusted (ladder)", same length as "Regression fallback (pairwise)" so it
  fits the Why? value column. The `default` arm now prettifies instead of leaking the key.
- check_guards.tcl proves every rung has a label by reading the `method` literals out of
  GrindAdvisor.tcl (no hand-written list); fails on the v3.10.0 proc.
- No engine change: every `eq "regression"` test is string equality, so the rung was already routed
  correctly. Lumen's own `grind_method` map has the same gap and needs its own skin pass.

**Safety status: read-only, unchanged. No write behavior was added; the one database write remains the SDB resync behind the Recalculate button (v3.9.0).**

Files: GrindAdvisor.tcl, tools/check_guards.tcl, plugin.tcl, docs.

## v3.10.0 (two guards on the regression) - 2026-08-19

Base: v3.9.0.

- Owner-reported: Sure Shot recommended 4.0 for a bag pulled 13 times at 7.5-8.2. Spreadsheet
  rebuild: m -0.621, b 30.49, R2 -0.054. `|m| >= GA_M_MIN` rejects a flat slope, not a meaningless one.
- `GA_R2_MIN` 0.30: below it the fit is discarded and the ladder answers, reason naming R2 and n.
  Measured, not chosen: working bags 0.42-0.80 (unchanged), broken bags 0.06 and -0.05 (blocked).
- `GA_EXTRAP_MARGIN` 0.5: `_limit_to_evidence` holds any answer to the grind range actually tried
  plus half a step, on both regression and ladder paths (a 2-shot slope at GA_SLOPE_MIN 0.1 could
  ask for a 25-step move). Reason says "held to the grind range actually tried".
- Not fixed: a noisy bag needs a deliberately large grind move the 0.5-damped engine never suggests.
- New tools/check_guards.tcl drives `_compute_forecast` with all six bags' real shot lists: guards
  fire on the bad two, change nothing on the good four. Fixtures generated from shots.db.

**Safety status: read-only, unchanged. Still nothing but SELECT; the one database write remains the SDB resync behind the Recalculate button (v3.9.0).**

Files: GrindAdvisor.tcl, tools/check_guards.tcl (new), plugin.tcl, docs.

## v3.9.0 (Recalculate from History, after editing a shot) - 2026-08-18

Base: v3.8.1. This entry keeps its full write-path description: it is the only version that
added a (indirect) database write capability.

**Safety status: this plugin still issues no SQL but SELECT and still opens the shot database
read-only. One thing changed and it must be stated plainly: the new button asks SDB to resync
itself, and SDB writes its own database when it does.** That is SDB's own public entry point (the
one behind its "Resync database to history" button) called with SDB's own arguments. It runs only
when you press the new button. Nothing else in Grind Advisor writes anywhere, and no history file
is touched by either plugin here.

### The problem

Owner-reported: editing a shot's grind in the Shot History Editor did not update the Grind
Advisor recommendation. SHE writes `history/<file>.shot` only; Grind Advisor reads SDB; four
things kept the old answer alive:

1. SDB had not re-read the file (it re-reads a `.shot` with a newer mtime, SDB.tcl:2060, but only
   when `populate` runs: on load if `sync_on_startup` is set, which is 0 on this tablet, or from
   SDB's own resync button).
2. `bag_rec_cache` memoizes per bag and is dropped only when a NEW shot lands.
3. `recommendation_for_current_bag` prefers `last_recommendation` while it matches the loaded bag.
4. `last_recommendation.tdb` reloads that saved answer at startup.

Any fix addressing fewer than all four would have looked like it worked and changed nothing.

### refresh_from_history (public) - the write path

1. `::plugins::SDB::populate "" "" 1` if SDB is loaded: SDB's own call, copied from its own
   settings page, guarded by `info procs` and `catch`. THIS is the step that makes SDB write its
   own database (a full history-folder rescan).
2. `invalidate_bag_rec_cache`.
3. Recompute through `recommendation_for_bag` (the compute path), not
   `recommendation_for_current_bag` (which would return the stale saved answer).
4. `save_last_recommendation` on the result, so `last_recommendation.tdb` holds the corrected
   figure and a restart cannot resurrect the old one (this is the plugin's own existing file
   write, unchanged in shape).

Returns and logs a summary ("SDB resynced, recomputed: 8.5").

### Where it lives

Advanced -> Shot Data -> Recalculate from History, a new card in the empty top-right quadrant
beside Popup Tuning; nothing else moved. A caption explains the button, shows the result after a
run, and resets on the next visit. Deliberately NOT automatic: step 1 rescans the whole history
folder and is the only thing in this plugin that causes a database write. Flagged to the owner
2026-08-18; deleting step 1 leaves a button that drops the caches and recomputes from whatever
SDB already holds.

### Verified

File parses; `refresh_from_history`, the page's `recalculate`/`_default_note`/`show` and the
Advanced `setup` byte-compile; card geometry from `_init_layout` tokens (208..600, 56px clear of
Tools at 656, right column on the content edge). Tablet-verified later (v3.11.1 session).

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.8.1 (fix: a keyless saved recommendation masked every per-bag answer) - 2026-08-15

Base: v3.8.0.

- Owner-reported: cycling bags still did not change the recommended grind.
  `recommendation_for_current_bag` returned the saved rec whenever `last_recommendation_is_current`
  said so, and that proc fails SAFE ("current") when identity is unknown; a pre-v3.7.0 saved rec
  has no `bag_key`, so it claimed to match every bag.
- The saved rec is now preferred only on a POSITIVE match (non-empty current key equal to the
  stored `bag_key`); otherwise the bag's own recommendation is computed. With no bean identity at
  all the saved rec remains the fallback rather than blanking.
- Regression test: a keyless saved rec must not mask the per-bag answer; cycling two bags changes
  the number.

**Safety status: read-only, unchanged.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.8.0 (per-bag recommendations) - NOT YET TABLET-VERIFIED, 2026-08-15

Base: v3.7.0.

- v3.7.0 could detect that the saved rec belonged to another bag, so the skin's tile blanked;
  a bag you switch back to has its own shots and regression, so blanking discarded a supported
  answer.
- `recommendation_for_bag {bag_key}` runs the existing engine at that bag's most recent shot
  (`_forecast_rec` already takes a position; `_bag_forecast_shots` already filters same-bag).
  Real values: Morgon 4.4, Pirates 8.9, Chelchele 7.3, JIVA Colombia 12.7 / 10.3, Saraya 8.2.
  Does not contradict "reset only": a bag with NO history still returns {}.
- `_decorate_rec {rec rows fields pos}` extracted from `analyze_latest_shot` so both paths decorate
  identically; harness asserts `analyze_latest_shot` == `_decorate_rec` at pos 0 (keep it).
- Memoized per bag key (skin tile evaluates every ~200 ms); invalidated wholesale in
  `save_last_recommendation`; only successful lookups cached.
- Verified offline; per-bag numbers cross-checked by an independent Python replication.

**Safety status: still read-only. No write behavior is added. SDB opened read-only, SELECT only; nothing in history/ or history_v2/ read, written, renamed or deleted; the only file written remains last_recommendation.tdb, unchanged in shape from v3.7.0.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.7.0 (profile-aware calibration; bag identity on the recommendation) - NOT YET TABLET-VERIFIED, 2026-08-15

Base: v3.6.3.

- Profile joins the calibration key: bean . roaster . origin . roast date . profile via a shared
  `_compose_bag_key`, gated by new setting `segment_by_profile` (default 1). A profile alone never
  forms a key. Evidence, honestly: replaying the real history gives 7 segments either way with
  identical ideals; the two JIVA "Origin Colombia" bags were already separate (roast_date differs)
  and are NOT evidence for this. With segmentation off the key is byte-identical to v3.6.3.
- Rec dict carries `bag_key`, `bag_label`, `profile` (identity/display only; no math reads them).
- Public procs for skins, neither opens the DB or touches the filesystem: `current_bag_key`
  (live `::settings` through the cached detected columns, asserted equal to the row-built key) and
  `last_recommendation_is_current` (fails SAFE = 1 when identity is unknown).
- `show_last_recommendation` refuses a stale rec and names its bag; owner decision 2026-08-15:
  reset only, never a seeded grind (reversed later in v3.13.0).
- Shot window 40 -> 200 via one `GA_FETCH_LIMIT` (measured 0.20 -> 0.34 ms on 1071 rows).
- Bag Stats labels via `_bag_label`; Diagnostics reports profile column, segmentation, keys, window.
- Harness byte-compiles 18 procs and checks all key equivalences and fail-safe paths.

**Safety status: still read-only. No write behavior is added. SDB read-only, SELECT only; never writes, moves, renames or deletes anything in history/, history_v2/ or SDB. The only file it writes remains its own last_recommendation.tdb, which gains three small identity fields (bag_key, bag_label, profile) and no new write path.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.6.3 (display-name consistency: "Grind Advisor" in all prose) - docs only, 2026-08-10

Base: v3.6.2.

- Owner request: the display name is always "Grind Advisor" (with a space) in prose, matching
  Bean Scanner / Shot History Editor. UI strings and `plugin.tcl`'s `name` already used it; this
  pass aligned README, CHANGELOG and PROJECT_STATE.
- Technical identifiers unchanged: folder, namespace, `GrindAdvisor_*` pages, filenames, log
  prefixes, GitHub repo name. No tablet verification needed.

**Safety status: no write behavior exists in this version. Docs-only pass; the only code change is the version string.**

Files: plugin.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v3.6.2 (Dose/Yield page: Next button inset from the card border) - TABLET-VERIFIED 2026-08-09

Base: v3.6.1.

- Owner-reported: on Advanced -> Dose / Yield Source the "Next" button's right edge sat flush on
  the card border. Now `btn_x2 = rx - sec_pad`, the rule every other in-card button follows.
  Nothing else changed.

**Safety status: no write behavior exists in this version. One-geometry bugfix, display only.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.6.1 (theme hardening - self-painted page background, themed button style) - TABLET-VERIFIED 2026-08-09

Base: v3.6.0.

- Same fix class as ShotHistoryEditor v0.5.4: Lumen's DYE integration switches the dui theme to
  DYE_Lumen mid-load; this plugin escaped only by load order, and its fpdialog pages never painted
  their own background.
- `ga_btn` registered with `-theme default` plus explicit fills (stock periwinkle/white, rendered
  look unchanged); `_page_bg` paints an explicit full-page grey (#d5d6e3) on all 7 pages. Color
  tokens added to the layout block.

**Safety status: no write behavior exists in this version. Display-only hardening.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.6.0 (Bag Stats card list + Actions entry; long-text clipping fixed) - TABLET-VERIFIED 2026-08-09

Base: v3.5.0.

- Bag Stats is now an overlay card list (same mechanism as History: 5 cards per page, Prev/Next,
  Done), up to 25 bags; opened from a new third Actions button and the same Advanced Tools slot.
  The `GrindAdvisor_bag_stats` dui page and `_bag_stats_text` are removed; data logic moved intact
  into `_bag_cards_data`; overlay procs mirror the History dialog verbatim.
- Owner-reported clipping fixed: `_paginate_text` (newline split, wrapped-line costing, 19 body /
  23 caption lines) + shared `_add_pager` on Help, Calculation Details and Diagnostics.
- Verified offline against the real tablet shots.db (9 bags, numbers identical to v3.5.0);
  geometry re-checked (Actions card ends y=1384, 48 above the bottom bar).
- Editing hazard recorded: external in-place writes to GrindAdvisor.tcl did not persist; use Edit.

**Safety status: no write behavior exists in this version. Read-only SDB access unchanged; still the one written file, last_recommendation.tdb.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.5.0 (Bag Stats becomes a bag comparison view) - TABLET-VERIFIED 2026-08-09

Base: v3.4.0.

- Per bag: ideal grind at target, Theil-Sen slope (`_theil_sen`), drift s/day (`_drift_fit`,
  3-param LS via Cramer's rule, 6+ dated shots over 3+ days), shots-to-target (first raw shot
  within +/-2s), shot counts. Trust gate: n>=4 AND grind spread >= 1.0 AND |slope| >= 0.5, else
  "fit not reliable (reason)". Header: median bean slope over reliable bags + average R2 (gauge).
- Rationale: owner goal of per-bag comparison; drift is the backtest's validated finding.
- Verified offline against the real shots.db + Python replication: Pirates 8.9 / -3.4 / -1.6,
  Chelchele 7.2 / -3.1 / -0.8, Morgon 3.0 / -2.2 exact; Saraya and LANGBIANG correctly gated.
- Beware: `ts` holds the Theil-Sen result; the drift loop uses `ts2` for row timestamps.

**Safety status: no write behavior exists in this version. Same read-only 600-row SELECT path as v3.4.0; display-only; still the one written file, last_recommendation.tdb.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.4.0 (Bag Stats page: per-bag R2 and average) - TABLET-VERIFIED 2026-08-09

Base: v3.3.0.

- New Advanced -> Tools -> Bag Stats fpdialog page (Diagnostics pattern): latest 8 bags with
  per-bag R2, learned slope, eligible shots, excluded outliers, first-last dates; summary with
  average R2 and median bean slope of fits with R2 >= 0.5. Built by `_bag_stats_text` from a
  600-row `_fetch_recent` window; display-only, nothing feeds back into recommendations.
- Verified offline against the real shots.db and a Python replication (0.94 / 0.42 / 0.12 exact;
  the saved rec next 3.6, m -2.5115, R2 0.9383, n 4 reproduced).
- Accuracy analysis 2026-08-08: bags took ~3 shots to land within +/-2s; the n=1 rung's effective
  6.0 s/step is the bottleneck. Slope-prior proposal later REJECTED by backtest (see PROJECT_STATE).

**Safety status: no write behavior exists in this version. Read-only SELECTs only; still the one written file, last_recommendation.tdb.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.3.0 (grind axis labelled; Curve openable from a skin tile) - TABLET-VERIFIED 2026-08-02

Base: v3.2.0.

- Labelled grind axis on both Curve panels: `_nice_step` rounds to the NEAREST 1/2/5 x power of
  ten (breakpoints 1.5/3/7); rounding up halved the tick count. Gridlines run through both panels
  and are drawn before the data (Tk stacks later items on top).
- New public `show_calibration_curve` for skins (Lumen 0.17.0 grind tile); same source ladder as
  `show_last_recommendation`; seeds `_last_rec_shown` so Back lands on the normal popup.
- Verified: procs byte-compile; tick steps across six ranges; geometry at 1340x800, 1280x800,
  2560x1600.

**Safety status: no write behavior is added in this version. Read-only SDB access, no history-file writes, raw sensor/chart data untouched; still the one written file, last_recommendation.tdb.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.2.0 (Curve reads the bag from SDB; optimal grind labelled) - TABLET-VERIFIED 2026-08-02

Base: v3.1.0.

- `_curve_rec` re-runs `analyze_latest_shot` (read-only) when the stored rec carries no `shots`,
  replacing the WHOLE rec so a stale R2/n is never captioned against fresh points.
- The dashed vertical at the recommended grind carries its value; the label flips sides near the
  right edge.
- Verified: procs byte-compile; geometry at three resolutions; a legacy rec now yields a full
  5-shot plot. Tablet-verified on the Tab A9 without pulling a new shot.

**Safety status: no write behavior is added in this version. The SDB re-read uses the same read-only SELECT path the popup uses; still the one written file, last_recommendation.tdb.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.1.0 (feature: Calibration Curve view) - superseded by v3.2.0, never tablet-verified

Base: v3.0.0.

- Popup gains a fourth button (OK / Why? / Curve / History). Curve shows scatter + fitted line, a
  residual strip on the same grind axis, caption `R2 . bias . spread . n` and a plain-language
  verdict (high R2 over large residuals is called out). Back returns to the popup; no new dui page.
- Design rules: plot the series the model fitted (regression rung = normalized time; ladder rungs
  = raw time in this version); no bias/spread below n=3; everything derived from the rec dict.
- `_forecast_rec` now carries `shots` in the rec dict. New `_curve_model`, `_curve_caption`,
  `_curve_verdict`, `_curve_and_stay`, `_show_curve_dialog`, `_draw_curve_panels`. Button gap 5% -> 3%.
- Verified off-tablet only: byte-compile, every ladder rung, geometry at three resolutions.

**Safety status: no write behavior is added in this version. SDB read-only; no history-file writes; raw sensor/chart data untouched. The only file this plugin has ever written, last_recommendation.tdb, is still the only one; it now also carries the eligible shot list (grind + time pairs), growing the file by roughly 60 bytes per shot on the bag. Hooks, triggers, guards and navigation unchanged.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v3.0.0 (major: single Regression Forecast method; modes removed) - TABLET-VERIFIED 2026-07-10

Base: v2.3.0.

- The four recommendation modes and their caps are REMOVED; one built-in ladder by eligible
  bag-shot count n (resets per bag): n=1 change=(t-target)/3.0x0.5; n=2 measured s/step from the
  pair (|slope| >= 0.1 else default); n>=3 recency-weighted (0.85^k) least squares of normalized
  time vs grind solved at target, rounded sign-safe and clamped; guards (one grind, |m| < 0.5)
  fall back to n=2. t_norm = time x (yield_set/yield_actual) - (dose_actual-dose_set) x 1.8, with
  2.0 g outlier exclusion; raw when no scale data. Direction learned from the sign of m.
- Constants are `GA_*` variables documented in Help, never settings. Removed settings
  `recommendation_mode`, `default_seconds_per_step`, `first_cap`, `later_cap` (silently ignored).
- Reason names the rung, slope and predicted time; Why?/Calc Details show n, excluded, m, b, R2.
- UI: Recommendation card dropped the mode row; Advanced dropped Calculation Tuning.
- Validated EXACTLY against the xlsx "Forecast Method" sheet (m -4.0977, b 81.139, 12.968 -> 13.0,
  pred 27.87) and edge cases in tclsh.

**Safety status: no write behavior exists in this version. SDB read-only; no history-file writes; raw sensor/chart data untouched; hooks, triggers, guards and navigation unchanged.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v2.3.0 (feature: dose/yield source mode)

Base: v2.2.0.

- New Advanced -> Dose / Yield Source sub-page: mode Fixed / Actual / Auto (default Auto) with
  editable plausibility bounds dose_min 12, dose_max 22, ratio_min 1, ratio_max 4 (top half of
  the screen for the keyboard).
- Scope (user-confirmed): display only. The grind math is time-based and calibration matching
  keeps set/target values, so the mode never changes the recommended grind.
- Transparency: reason line and Diagnostics always state the source ("dose: actual 18.4g",
  "set 18.0g (actual 0.0g rejected)"). New `actual_dose` field detection, graceful when absent.
- Popup "Set Yield" row became "Yield" plus a "Ratio 1:x.x" row; Tools grid now 2x3.
- Verified in tclsh across all modes and edge cases. Tablet-verified 2026-07-10.

**Safety status: no write behavior exists in this version. SDB read-only; no history-file writes; recommendation math byte-identical to v2.2.0.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v2.2.0 (read-only diagnostics: per-shot calculation trace) - TABLET-VERIFIED 2026-07-10

Base: v2.1.1.

- New `_shot_trace_text`: for the latest 5 valid shots, every input and intermediate of the real
  recommendation chain, two compact lines per shot, appended to Calculation Details (caption
  font); Diagnostics points to it.
- Verified via a stubbed-data tclsh run.

**Safety status: no write behavior exists in this version. Display-only; zero changes to math, hooks, popups, gates, navigation or settings.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v2.1.1 (bugfix: deleted shots no longer appear) - TABLET-VERIFIED 2026-07-10

Base: v2.1.0.

- Bug: a shot soft-deleted via ShotHistoryEditor kept appearing. SDB's resync only flags orphaned
  rows `removed=1` (SDB.tcl:2205-2216), and the fetch ignored both the flag and file existence.
- Fix, two read-only layers through the shared pipeline: `_fetch_recent` adds
  `AND (removed IS NULL OR removed=0)` when the column exists; `_row_is_valid_espresso` rejects
  rows whose `filename` exists in neither history/ nor history_archive/ (skipped when the schema
  or folders are unavailable). Diagnostics shows both detections.
- Verified in tclsh with a simulated history folder, pre- and post-resync.

**Safety status: no write behavior exists in this version. Read-only SELECT filters and file-existence checks only.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v2.1.0 (feature: Calibration Accuracy confidence gauge) - TABLET-VERIFIED 2026-07-10

Base: v2.0.2.

- Display-only confidence score: evidence = min(relevant shots, 5)/5; consistency = 1 - avg
  |time - target| over the last <=4 relevant shots / 10 s; score = 100 x (0.4 evidence +
  0.6 consistency); fewer than 2 relevant shots -> "Not enough data". Bands 0-39 Poor, 40-64 Fair,
  65-84 Good, 85-100 Excellent. Relevant = same bag (or recipe fallback), so a new bag resets it.
- Shown as a 10-segment bar + "82% - Good" in the Recommendation card (now 3 rows), one caption
  line in the popup, and explained on Help. Attached to the rec dict after computation; never
  read back by any math.
- New `_calibration_confidence`, `_confidence_band`, `calibration_confidence`, `refresh_confidence`.
- Verified against concrete histories (1 shot -> n/a; 3 consistent -> 77%; 6 consistent -> 96%).

**Safety status: no write behavior exists in this version. Display-only gauge; recommendation outputs unchanged.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v2.0.2 (bugfix: history-button glyphs + Done ping-pong) - TABLET-VERIFIED 2026-07-07

Base: v2.0.1.

- History overlay showed "25C0 Prev" / "Next 25B6": the v2.0.1 sed build step ate the backslashes
  of six `\uXXXX` escapes. Restored via a Tcl rewrite; file pure ASCII again. Lesson: never use
  sed for backslash-escape edits.
- Done ping-pong (Advanced -> Done -> Done went back to Advanced): `_capture_return_page` now also
  rejects the plugin's own `GrindAdvisor_*` pages, so the entry target survives sub-page
  round-trips (latent since v1.8.8, reachable once v2.0.0 moved sub-pages behind Advanced).
- No changes to math, SDB reads, gates, popup logic or any control's command.

**Safety status: no write behavior exists in this version.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v2.0.1 (visual grouping into section cards; behavior identical)

Base: v2.0.0.

- Stock "App tab" pattern: controls grouped in white rounded section cards (existing
  `rounded_rect` helper) with titles on the grey page background. New `sec_*` tokens and a
  `_sec_card` helper.
- Main page: LEFT Shot Settings (entries at y centers 384/512/640, top half for the keyboard) +
  Actions; RIGHT Recommendation + Popup. Advanced: Calculation Tuning + Popup Tuning cards plus a
  full-width Tools card. Help/Diagnostics/Calc Details body inside a full-width card.
- Overlap audit clean; zero hardcoded coordinates outside the token block; zero SQL write
  keywords; file pure ASCII. Tablet-tested 2026-07-07 (cards "perfectly neat"; two bugs -> v2.0.2).

**Safety status: no write behavior exists in this version. Layout only; all commands byte-identical to v2.0.0.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v2.0.0 (complete UI redesign; behavior identical to v1.8.8) - TABLET-VERIFIED 2026-07-07

Base: v1.8.8.

- Design system mirrored from ShotHistoryEditor v0.3.1-v0.3.3: `_init_layout` token array `L`
  in the virtual 2560x1600 canvas space, physical-pixel `GA_*` fonts (title 40, section 24,
  primary 22, body 19, caption 16, button 20; 16px floor), shared `ga_btn` style, `rounded_rect`
  helper. Zero hardcoded coordinates below the token block.
- Pages: main settings (label/value grid, numeric entries in the top half, Done/Advanced bar);
  Advanced (5 tuning entries + 2x2 tools grid: History Display Options, Diagnostics, Calc Details,
  Help); History Display Options 2x5 grid; Help/Diagnostics/Calc Details standard pages.
- After-shot popup as a rounded card with hero "13.5 -> 12.0", detail grid, reason, [OK] [Why?]
  [History]; new display-only Why? explainer built from the rec dict; error card; light/dark.
- History overlay rebuilt as 5 cards per page with Prev/Next paging from memory.
- Temporary v1.8.8 DIAG log lines removed after tablet verification.

**Safety status: no write behavior exists in this version. Math, SDB reads, hooks, gates, popup_active guards and the v1.8.8 Done/Back mechanism unchanged.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v1.8.8 addendum

Tablet-verified: the v1.8.8 captured-return-page navigation fix works (settings -> flush -> stop
-> Done exits correctly, no crash, no popup).

## v1.8.8 (final navigation fix, root cause confirmed from de1app-core source)

Base: v1.8.7.

- Root cause confirmed in `de1app-core/dui.tcl`: `::dui::page::load` resets `page_stack` to a
  single entry whenever a `default`-type page (the flow screen during a flush) is shown, even
  under an open `fpdialog`, because the one-dialog guard checks type `dialog` only. After the
  flow, `close_dialog`'s `previous` is the flow page.
- Fix: every page's `show{}` calls `_capture_return_page $page_to_hide`, skipping machine-state
  names (from `machine.tcl`'s `::de1_num_state`). `_navigate_done` uses `dui page load` on the
  captured, `dui page exists`-verified target (the same call `open_dialog` itself uses), else
  `dui page close_dialog`. Sub-pages always return to `GrindAdvisor_settings`. Errors logged via
  `msg`, never swallowed.
- v1.8.7 exploratory logging removed; one DIAG line kept on Done until tablet-verified.
- Not changed: math, SDB reads, popup content, settings semantics, the v1.8.2 popup guards.

**Safety status: no write behavior exists in this version. Only Done/Back navigation changed.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v1.8.7 (diagnostic only - no behavior change)

Base: v1.8.6.

- Confirmed on-tablet: v1.8.6 fixed the crash; the milder stale-flush-page bug is back as expected.
- Rather than a fourth guess, read-only `msg` DIAG logging added at preload, on every
  `::de1(state)` / `page_display_change` transition, and before/after `dui page close_dialog` in
  Done, so the framework's page bookkeeping can be read from the log after a repro.

**Safety status: no write behavior exists in this version. No SDB, history-file or navigation code touched.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v1.8.6 (bugfix: revert Done navigation to the reference-plugin mechanism)

Base: v1.8.5.

- v1.8.5 made Done crash with the `A_Flow` error on EVERY press: GFC's `dui page load` pattern
  belongs to plain pages, while Grind Advisor's settings pages are `-type fpdialog`.
- Done reverted to a bare `dui page close_dialog` exactly as SDB and visualizer_upload use it; no
  fallback, no capture. Trade-off stated: the milder stale-page-after-flush nuisance returns.
- Do not attempt another `dui page load` fallback without confirming the fpdialog-aware call from
  the core source or on-tablet testing.

**Safety status: no write behavior exists in this version. Only the Done/Back navigation call changed.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v1.8.5 (diagnostic + bugfix, converges v1.8.2-v1.8.4 navigation attempts)

Base: v1.8.4.

- Comparative diagnosis against Graphical_Flow_Calibrator: plain pages, `::page_show` wrapper
  captures `gfc_start_page` on genuine entry, Exit is one bare `dui page load`, no catch.
- Removed all v1.8.3/v1.8.4 guard machinery (`_transient_page_re`, `_is_transient_page`,
  `_recover_from_transient_page`, `_close_settings_dialog`, `_close_subpage_dialog`).
- Added `_settings_return_page` (default "extensions"), captured unconditionally in
  `preload_settings_page`; `_exit_settings` / `_exit_subpage` do one `dui page load` with a narrow
  catch that logs via `msg`. All six `page_done` procs use them.
- Outcome (see v1.8.6): crashed on every press; mechanism does not transfer to fpdialog pages.

**Safety status: no write behavior exists in this version. Only the Done/Back navigation mechanism changed.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v1.8.4 (bugfix)

Base: v1.8.3.

- v1.8.3's captured fallback page name made the app's page resolver fall through to its
  plugin-loading machinery and error on the unrelated `A_Flow` plugin.
- Removed the dynamic capture; `_close_settings_dialog` calls `dui page close_dialog` and, only if
  the revealed page still looks transient, `dui page load GrindAdvisor_settings` (hardcoded
  literal, the same fallback sub-pages already used). No empty or computed page name can reach
  `dui page load`.
- Outcome (see v1.8.5): the call was wrapped in a bare catch and its failure was invisible.

**Safety status: no write behavior exists in this version. Only the settings Done fallback target changed.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v1.8.3 (bugfix)

Base: v1.8.2.

- Root cause: Done/Back trusted `dui page close_dialog` alone; after a flush/rinse while settings
  were open the framework revealed the flow screen.
- Added `_capture_settings_return_page` (from `preload_settings_page`, guarded by
  `_is_transient_page`), `_close_settings_dialog` (close, then force-navigate to the captured page
  if the current one looks transient) and `_close_subpage_dialog` (fallback `GrindAdvisor_settings`).
- v1.8.2 popup guards unaffected; a flush during settings still produces no popup.

**Safety status: no write behavior exists in this version. Only Done/Back navigation changed.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.

## v1.8.2 (bugfix)

Base: v1.8.1.

- Bug 1: rinse/flush/steam/water triggered the popup because the flow-complete hooks fire on any
  flow and `analyze_latest_shot` took the newest SDB row as a shot.
- Bug 2: no popup re-entry guard and no reset on navigation/state changes.
- Fix: `_row_is_valid_espresso` gate (rejects rinse, flush, backflush, clean/cleaning, descale,
  hot water, water, steam, skip, dummy, calibration; shots under 5 s; missing grind/dose/yield);
  `popup_active` guard that self-heals when no popup widget exists; `_install_nav_watch` on
  `::de1(state)` and `page_display_change` cancels/force-closes popups on flow start and resets
  the flag on any page change; auto-popup suppressed on settings pages (still computed and saved);
  `show_latest_recommendation`/`test_latest_shot` search the filtered list and seed the dedup id;
  `load_last_recommendation` seeds `last_shown_id` at startup.
- Not changed: math, settings UI, SDB discovery, popup layout.

**Safety status: no write behavior exists in this version. SDB opened read-only / SELECT-only as in v1.8.1; read-side filtering only.**

Files: GrindAdvisor.tcl, plugin.tcl, docs.
