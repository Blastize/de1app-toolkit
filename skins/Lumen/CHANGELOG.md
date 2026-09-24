# Changelog - Lumen

Entries follow a documentation cap (about 15 lines each; longer only where a
version added or changed a write capability). The original long-form entries
survive unchanged in the archive snapshot of each version.

## 0.57.5 - LAST SHOT shows the grind the shot was pulled at (2026-09-24)

Base: 0.57.4. Same owner screenshots: right after a shot the LAST SHOT card
said grind 3.8 for a shot pulled at 2.8. A shot start empties the card's
record, so it fell back to the live `grinder_setting`, which Grind Advisor
had already moved to its next recommendation. `after_flow_complete` now
reads the record back from the file the core just wrote
(`history_saved_shot_filename`, trusted only when `history_saved` is 1 and
the name matches `espresso_clock`), once per espresso-page flow; the chart
vectors are not touched. The record parser moved out of `_load_shot_file`
into `_read_shot_rec`, unchanged.
**Safety status: read-only change; one history/*.shot file read per shot,
nothing written.**

## 0.57.4 - the bag dots follow SDB's shot save (2026-09-24)

Base: 0.57.3. Owner (two tablet screenshots): after the first shot on a
newly scanned bag, all five dots stayed hollow until right-then-left on the
arrows. The cached bag list refreshed on the home page's `show`, which fires
as the shot ends, while SDB writes the new row later (after_flow_complete, or
after the Visualizer upload). A leave trace on
`::plugins::SDB::save_espresso_to_history_hook`, added 5 s after startup
with the first refresh (guarded, never doubled), re-reads the list once the
row exists: one `available_categories` query per saved shot.
**Safety status: read-only change; no new write path. SDB is only observed
through a trace, its hook and return value untouched.**

## 0.57.3 - favorite slots answer the tap with the halo, no press flash (2026-09-22)

Base: 0.57.2. Owner: drop the square tap highlight on the three slots and
make the glow appear the instant the slot is tapped. The slot zones use
press-flash style `none`. A set-slot tap lights and paints the halo on that
slot BEFORE `select_profile` runs, then runs dui's own on-screen variable
pass (it re-arms its own 200 ms timer) so the name inks follow at once; a
failed load re-derives the halo from the profile really loaded, and a busy
machine still refuses before anything lights. Storing an empty slot lights
it on the same tap. Owner also confirmed 0.56.0 Auto flipped the glass by
itself on the tablet.
**Safety status: no write path changed; the tap loads the same profile
through the same `select_profile` call as 0.53.0.**

## 0.57.2 - polish: the favorite halo tuned on the tablet (2026-09-22)

Base: 0.57.1. Owner: "a bit darker". The halo sits at 0.36 inside (0.62 was
brown, 0.30 too faint) and on light glass its tint is the crema lifted half
way toward white (was 60%).
**Safety status: display only, no behaviour or write change.**

## 0.57.1 - polish: a lighter, quieter favorite halo (2026-09-22)

Base: 0.57.0. Owner, on the tablet (light glass): the halo was "very dark" --
the light crema is a dark amber, so at 0.62 it painted a brown pill. The halo
now sits at 0.30 (a 0.40 preview was still too much for the owner), and on
light glass (ground luminance > 0.45, so the custom theme's halves sort
themselves) its tint is the crema lifted 60% toward white.
**Safety status: display only, no behaviour or write change.**

## 0.57.0 - taskbar re-layout: sleep far left, profile names in the slots, halo on the active one (pass 08) - verify.sh PASS 2026-09-22 18:30 on run 1 (home dump: three 180-wide slots, the loaded profile's slot carries the 176x48 halo photo, the other two the 1x1 blank; logcat clean; light glass eyeballed, dark on the painter render only -- owner checklist open)

Base: 0.56.1. Owner's mockup: the moon (Sleep) moves ALONE to the far left
so a stray tap near the corner no longer sleeps the machine; the date sits
under the time with the water reading beside it; mug / wrench / gear / DE1
close up to the right edge; the "Lumen" wordmark is gone. The three
favorite slots widen to 180 and show their PROFILE NAMES, centred and
ellipsis-cut to the slot (measured in the caption font, memoised): a dim
mono `+` when empty, the icons' grey when set, crema when active -- over a
soft crema HALO, one runtime alpha PNG (`custom::halo_png`, the 0.49.0
encoder) swapped into the slot's image item by the 200 ms accessor, so it
follows a profile change from anywhere within a tick; `apply_theme`
repaints it from the new crema.
**Safety status: no write path changed. `lumen_fav_profiles` is written
exactly as in 0.53.0 (empty-slot tap, settings Clear); a set-slot tap still
calls the core's `select_profile`. No file, database or history is touched.**

Files: skin.tcl, tools/check_skin.tcl (bar geometry rewritten; 0.57.0 section
rebuilds the home page under the photo stub), docs; passes/Lumen/pass_08.*.

## 0.56.1 - polish: the grind and last-shot tile footers share one row (2026-09-22) - TABLET-VERIFIED 16:45 (headless harness PASSED, home screenshot: both footers at the same row, logcat clean)

Base: 0.56.0. Owner spotted on the home page that "Fair - 6 shots / Curve /
Shot analysis" sat 4 px lower than "Today 12:57 PM / Shot history": the grind
tile placed its bottom row at tile top + 140 (224) while the last-shot tile
used `L(hist_y)` (220). The grind row now uses `L(hist_y)` too; tap zones
are unchanged (they were already tied to the tile bottom).
**Safety status: display only, no behaviour or write change.**

Files: skin.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## 0.56.0 - Auto is a BASE: the custom theme's glass follows the schedule (pass 07) - verify.sh PASS 2026-09-22 15:58 on run 2 (run 1 was a checks-file call count, nothing on the tablet; picker dump 42 texts, 0 overlaps; logcat clean. The tablet's saved custom set is the Lumen light preset, so this boot drew its LIGHT half once as `_customl` (12.7 s, "4 light 220 30 34 76"); the old `_custom` files now stand for the dark half and are re-checked by signature before use. Owner checklist open)

Base: 0.55.0. Owner, on seeing 0.55.0: Auto must be one of THREE base
choices (Dark, Light, Auto -- not "Auto plus Light"), and Auto should
cycle the custom theme's own dark / light glass through the day.
**Safety status: `lumen_theme_auto` is GONE (never written again; a
leftover value is ignored). `lumen_custom_base` now takes dark | light |
auto, and `lumen_auto_light_from` / `lumen_auto_dark_from` are picker
state: all saved together by the picker's Done, nothing on a pill or
time tap. The schedule writes `lumen_theme` only through `_switch_theme
custom` (the value never changes) from `auto_tick`, on home / saver while
the machine is idle. NEW files: with base auto Done also draws the OTHER
half's set, `lumen_<page>_customl.png` (+ glass, dim, `lumen_customl.sig`,
transient `lumen_customl.baking`) beside the `_custom` (dark) set, so a
flip is a photo swap. No file, database or history is touched otherwise.**

- prefs: `base` may be auto; `eff` is the half in force (auto resolved
  by the clock). Palette, signature, bake, backgrounds and the glass
  material all follow eff; `custom::suffix` names each half's files.
- Tick: flips when the schedule's half differs from
  `custom::active_base` (recorded by set_palette), same four guards.
- Picker: Auto is a third base pill (only one lights); the times are
  pending like every other choice; Done saves and pre-draws both halves.
- Settings caption: "Now Custom (Auto, light glass). ...".

Files: skin.tcl, tools/check_skin.tcl, docs; passes/Lumen/pass_07.*.

## 0.55.0 - Auto theme schedule: Light / Dark by time of day (pass 06) - verify.sh PASS 2026-09-22 15:29 on run 2 (run 1 died in the static phase on a checks-file grep inherited from pass 03, nothing on the tablet; picker dump 42 texts, 0 overlaps, logcat clean incl. the two new auto lines; owner checklist open, above all a real switch at a boundary)

Base: 0.54.2. Owner request: an Auto mode that switches Dark at night and
Light by day, as a schedule with two times and an Auto toggle in the
picker's BASE row.
**Safety status: three NEW preferences, all via `save_settings` on an
explicit tap in the picker: `lumen_theme_auto` (0/1, the Auto pill),
`lumen_auto_light_from` and `lumen_auto_dark_from` (minutes past
midnight, +30 per tap on the time, wrapping; defaults 07:00 / 19:00). The
schedule may also write `lumen_theme` through the existing
`_switch_theme` (dark or light only, never custom): on an Auto or time
tap, and once a minute from `auto_tick` -- only on the home or saver
page and only while the machine is idle or asleep (`machine_busy`). At
boot the scheduled theme is chosen before pages build (no live switch).
The picker's Done, which applies Custom, sets `lumen_theme_auto` 0. No
file, database or history is touched.**

- BASE row: Dark | Light | Auto pills right-aligned; second line
  "Auto: Light 07:00  Dark 19:00", each time a 116 x 44 tap zone.
- Settings caption: "Now Light (Auto). ..." while the schedule is on.
- Polish rider: the miniature's 2.8 / 19.0 / 38.0 in the caption size
  (the data mono was huge at this scale -- owner).
- Harness: schedule cases (defaults, wrap past midnight, equal times,
  junk prefs), the tick's four guards, the taps, Done turning Auto off.

Files: skin.tcl, tools/check_skin.tcl, docs; passes/Lumen/pass_06.*.

## 0.54.2 - polish: GRIND / DOSE / YIELD row in the miniature, silent swatch taps - verify.sh PASS 2026-09-22 15:21 on run 1 (picker dump: 39 texts, 0 overlaps; logcat clean; owner checklist open)

Base: 0.54.1. Owner's two follow-ups after seeing 0.54.1.
**Safety status: unchanged; no behaviour change.**

- Miniature: the next-shot strip's GRIND / DOSE / YIELD labels at their
  real x and top, with 2.8 / 19.0 / 38.0 in the data mono beneath them,
  centred where the real values sit between the pills.
- Picker swatches: no press chip any more (the white square the owner
  saw); the selection ring is the feedback. New `none` press style.
- press_flash: the ring and chip branches no longer `return` from inside
  the catch (which logged an empty "press flash failed" DEBUG line on
  every ring); the chip drawing moved to `_press_chip`.
- Harness: `none` draws nothing and every one of the 52 swatch zones
  carries it.

Files: skin.tcl, tools/check_skin.tcl, docs; passes/Lumen/pass_05.checks.json.

## 0.54.1 - polish: picker columns out to the margins, larger preview - verify.sh PASS 2026-09-22 15:02 on run 1 (home, settings and picker dumps, picker text-overlap check on, logcat clean; the run also puts 0.54.0 on the tablet; owner checklists open)

Base: 0.54.0. Owner's mock of 2026-09-22: use the empty horizontal room.
**Safety status: unchanged; no behaviour change.**

- Both picker columns move out to a 110 margin (was 170); the controls
  column keeps its 640 (the swatch grid needs 592 inside), the preview
  column takes the rest: 450 wide (was 330), 30 between them.
- Preview: miniature 402 x 240 (was 282 x 168); five 66 x 48 token chips
  on an 18 gap; the notes wrap to two lines each at the new width; the
  miniature's bean name sits where the real one does (652 design px).
- Harness: symmetric margins, lg between the columns, miniature aspect,
  status line clear of the card's bottom padding.

Files: skin.tcl, tools/check_skin.tcl, docs; passes/Lumen/pass_04.checks.json.

## 0.54.0 - THEME row: a "Change" button that opens the picker (pass 03) - 2026-09-22 (headless PASS both font modes; tablet-verified inside the 0.54.1 run, verify.sh PASS 15:02)

Base: 0.53.1. Owner request: the Dark -> Light -> Custom cycle felt untidy
now that Lumen dark and Lumen light are presets in the picker.
**Safety status: the settings-page path that wrote `lumen_theme` on every
THEME tap is REMOVED. `lumen_theme` and the five custom prefs are now
written only by the picker's Done through `_switch_theme` (unchanged).
No new writes; no file, database or history is touched.**

- THEME row: the button reads "Change" and opens the picker
  (`open_theme_picker`). It is the row's only tap and the only thing that
  flashes (zone chip); the caption tap (0.46.0) and the whole-card chip
  (0.53.1) are gone.
- Caption is live: "Now <theme>. Dark, Light, presets or your own
  colours." A failed apply's reason still replaces it.
- The cycling proc is deleted; the harness drives the live-retheme cases
  through `_switch_theme` and asserts the row has exactly one picker zone.

Files: skin.tcl, tools/check_skin.tcl, docs; passes/Lumen/pass_03.*.

## 0.53.1 - polish: press-flash fit, THEME card chip, picker spacing - verify.sh PASS 2026-09-22 14:25 on run 2 (run 1 flagged the miniature's LAST SHOT caption against its values row at the new scale; both lines now sit on the grind card's baselines; picker item dump: 0 text overlaps, logcat clean; owner checklist of six taps open)

Base: 0.53.0. Owner's polish batch of 2026-09-22 (five reports, one bump).
**Safety status: unchanged; no behaviour change, no new writes.**

- Press flash: virtual -> physical now ROUNDS (`_flash_px` / `_flash_py`;
  the core's rescale truncates, so the chip sat a pixel left of the -, <
  and > pills and read shorter on the right). The label chip unions only
  text at least half inside the zone (the grind note's tail made Curve's
  chip card-wide). The chip is lowered beneath strokes too (lines, hollow
  polygons), so the taskbar DE1 icon no longer vanishes under it. New
  `chip <x y w h>` style lights a whole container at the card radius.
- Settings: the THEME caption tap lights the whole THEME card (chip style).
- Picker: presets in two rows of three 192-wide pills on the swatch rows'
  rhythm (label +18, row +48, 8 between, 16 below; card 160 tall), Cancel
  and Done under it at 712..784; the preview's miniature, chips and notes
  sit pad_x inside the card (inner 282: miniature 168 tall, chips 50 on 8).
- Harness: chip flash case, rounding case (40..84 vs the core's 39..83),
  picker spacing net; Done / Cancel zones follow `thp_done_y`.

Files: skin.tcl, tools/check_skin.tcl, docs; passes/Lumen/pass_02.checks.json.

## 0.53.0 - favorite profile slots 1 2 3 on the taskbar (pass 01) - verify.sh PASS 2026-09-18 11:55 (home + settings dumps inside the virtual canvas, logcat clean, screenshot: three dim digits clear of the date and the wordmark; the assign / load / Clear taps are harness-proven, owner checklist open)

Base: 0.52.1. Owner request: switch profiles without the stock chooser,
above all the backflush profile a maintenance alert asks for.
**Safety status: one NEW preference, `lumen_fav_profiles` (slot -> filename
+ title), written by a tap on an EMPTY slot and removed by the settings
header's "Clear favorite profiles" link, both via `save_settings`. One NEW
machine-facing action: a tap on a set slot calls the core's
`select_profile <filename>` (DrinkMenu v1.16.0's proven call, copied with
its busy guard) and a second later `save_settings; save_settings_to_de1`.
No flow is ever started; no file, database or history is touched.**

- Taskbar: digits 1 2 3 at 300/372/444, 56x48 zones, between the day
  label and the wordmark. Dim = empty, ink = set, accent = that slot's
  profile is loaded now (three stacked fixed-ink items, the dot pattern).
- Settings header: the Clear link, right-aligned above row 1, blank while
  no slot is set. No settings row (the page is baked and full).
- Harness: slot geometry + zone commands; empty tap assigns, set tap
  selects, busy refuses, a missing file logs and keeps the slot, Clear
  empties, junk preference reads as no favorites.

Files: skin.tcl, tools/check_skin.tcl, docs; passes/Lumen/pass_01.*.

## 0.52.1 - polish: the picker miniature's labels no longer touch - TABLET-VERIFIED 2026-09-17 22:58 (picker eyeballed and its item dump checked: 0 text overlaps, hero 163-188 and band 188-208 inside the 162-209 card, bean name 291-316 above the pills at 324; no re-bake, no Lumen errors)

Base: 0.52.0. Polish batch from the 0.52.0 review (items 5 and 6).
**Safety status: unchanged; no behaviour change.**

- Miniature: the fonts do not shrink with the 47 px grind card, so the
  hero "2.8" is one size down (primary) and both lines are placed from
  the card's top; the NEXT SHOT caption is dropped from the 52 px strip
  (LAST SHOT already shows that ink) and the bean name sits clear of the
  painted pill row. Bboxes no longer overlap each other or the card edges.
- Preset pill labels: already >= 4.5:1 after 0.52.0's accent change (light
  pills 4.71 / 4.61); the harness now asserts it for every preset.

Files: skin.tcl, tools/check_skin.tcl, docs.

## 0.52.0 - custom palette: the accent clears 3:1 on its own wash too; the neutral swatch gives a white / black accent and survives a save - TABLET-VERIFIED 2026-09-17 22:48 (restart re-baked the owner's taupe/neutral set as sig `4 dark 30 22 0 0`, 7 files, no marker; home shows the hero, Curve / Shot analysis and Done in #E0E0E0 instead of the pink #AB8282; the picker reopened with BOTH saved swatches ringed and the Accent chip #E0E0E0; a Sea glass tap previewed #157960 on wash #A2D4CB, then Cancel; no Lumen errors)

Base: 0.51.0. A review swept all 1352 swatch pairs through the palette
maths: the accent was guarded against the plain glass only, while the hero
number, Done and the Steam / Water buttons draw it on the accent WASH
(`crema_lo`), a mid tone on a light base - 479 of 676 light pairs fell
under 3:1 there (2.13 worst; the Lumen light and Sea glass presets 2.59).
And the "white" accent swatch came out mid grey (#969696 / #707070), then
a saved neutral was clamped from saturation 0 to 20, so it applied as a
tinted grey (the owner's taupe set showed a pink #AB8282 accent).
**Safety status: unchanged. Same five prefs, same files.** The painter
signature is 3 -> 4, so every custom set is redrawn ONCE at the next
start (about 12 s behind the wait pill).

- `palette`: the accent loop stops only when it clears 3.06:1 on the glass
  AND on its wash (the dark wash is re-derived per step); saturation 0
  starts at lightness 88 (dark) / 25 (light) -> #E0E0E0 / #404040.
- `prefs`: accent saturation clamps to 0..100 (was 20..100).
- Harness: the 1352-pair sweep asserts wash >= 3:1 (now 3.05 worst) and the
  neutral tones; clamp test updated; signature 4.
- Presets move slightly on light: Lumen light accent #A26516 -> #905A14,
  Sea glass #188B6E -> #157960. Dark presets unchanged.

Files: skin.tcl, tools/check_skin.tcl, docs.

## 0.51.0 - picker redesign: 52 swatches incl. neutral and brown, a roomy grid, a painted miniature; the wait pill fits its text - TABLET-VERIFIED 2026-09-17 22:11 (picker eyeballed over the owner's rose/violet light set: grids breathe, neutral + brown + rich + vivid taps set both values and ring the swatch, the miniature repaints in 220 ms per tap and tracks the gradient, bloom and panels; first capture showed both captions and two preset labels overrunning and the miniature's band on the card edge, all three fixed in the same pass; a forced re-bake showed "Applying Custom: drawing backgrounds..." inside a pill sized to it; whole custom apply with bake 17.9 s, 0 problems; owner's set restored, no marker left)

Base: 0.50.1. Owner review of the picker: swatches too close and mashed,
text too tight, the preview less colourful than the applied theme, and a
wish for more colours (black, white, brown); plus a wait-pill line that
ran past its card. **Safety status: unchanged. Same five prefs, same
files; a miniature photo per preview refresh, freed each time.**

- Swatches are {hue saturation} pairs now, two rows of 13 per control:
  BACKDROP row 1 grey + 12 hues tinted (36), row 2 taupe + 12 hues rich
  (62); ACCENT row 1 white/black (neutral, the contrast guard settles it
  per base) + 12 vivid (85), row 2 brown + 12 muted (45). A tap sets both
  values (`theme_pick key hue sat`); presets unchanged.
- Layout: a 640-wide controls column with labels ABOVE full-width grids
  (38 px dots on a 46 px pitch, 44 px zones that never overlap), presets
  as one row of six; a 330-wide preview column. Tokens `L(thp_*)`.
- Preview: `_preview_render` paints the HOME page from the pending palette
  with the custom painter at 330/1340 (gradient, bloom, real panels) into
  an image item under a few readable labels; five token chips (Page,
  Glass, Text, Accent, Chip) show the derived colours themselves.
- `_wait_pill_box`: the pill is measured to its text (floor 560, cap 1300
  design px); the bake line is shorter.
- Harness: 26 + 26 swatches, neutral and brown positions, pair taps, the
  miniature and chips, the pill growth and floor.

Files: skin.tcl, tools/check_skin.tcl, docs.

## 0.50.1 - fix: a light-base custom set hung the bake (app stuck on "Applying", then at startup) - TABLET-VERIFIED 2026-09-16 22:25 (rescue build pushed over the stuck app; restart drew the Sea glass set in 12.5 s and loaded)

Base: 0.50.0. Owner report: applying Sea glass stuck on the wait pill; after
a kill the app hung at startup (the same bake runs at skin load).
**Safety status: unchanged.** Cause: 0.49.0's soft-edge painter clamps the
per-pixel column count to half the PNG width for a panel too narrow for a
middle stretch; that put the row shortcut's "x == zone" exactly where its
jump-back landed, so the row loop never advanced. Only a LIGHT base
(blur 20) on the 44 px inner pills reaches it; dark bases (blur 16) do
not, which is why Graphite and Espresso were fine. Now a narrow panel is
painted per pixel end to end. Harness: every inner-pill size of the light
Sea glass set must paint and return.

## 0.50.0 - a wait pill counts the theme apply off - TABLET-VERIFIED 2026-09-16 20:10 (captures taken DURING the apply: "Applying Dark: colours and backgrounds...", "DYE pages 4 / 10...", "10 / 10..."; the pill changes to the new palette with the page; gone after; a stale press-flash chip seen on the THEME button mid-apply in the first run is now cleared when the pill appears; cycle custom -> dark -> light -> custom 4.5-4.9 s each, 0 problems, no errors)

Base: 0.49.0. Owner report: cycling the themes "freezes the screen for a
couple of seconds". The apply IS one synchronous stretch (about 1 s for
the colours, 3.3 s for DYE's ten pages, plus ~11 s when a custom set has to
be painted first) and cannot yield without letting taps land on half-built
pages, so it now SAYS what it is doing. **Safety status: unchanged; no
writes, no new reads; a transient canvas pill only.**

- `::lumen::wait_show / wait_step / wait_hide`: a centred pill drawn
  straight on `.can` (press-flash style), painted with `update idletasks`
  before the work and on every step: "Applying Light theme...", then
  "drawing the backgrounds (a few seconds)..." (custom only), "colours and
  backgrounds...", "DYE pages 1 / 10..." per page, removed at the end,
  also on a refused apply. The pill takes the new palette as soon as it
  is loaded, so it changes sides with the page.
- `_retheme_dye` rethemes one page per call so the count can advance.
- Harness: pill drawn first, colours + per-page steps, removed last; the
  bake step on a custom apply; per-page forced retheme calls in order.

Files: skin.tcl, tools/check_skin.tcl, docs.

## 0.49.0 - the custom theme serves its own glass material to plugin popups - TABLET-VERIFIED 2026-09-16 20:03 (the owner's Graphite custom set redrawn at launch in 11.4 s, seven files; Shot analysis and Curve popups from the home page: ring cropped from the custom home art, seam-free against the page, card a dark frosted slab with the soft chip shape showing through; Dark and Light popups unchanged after live switches; 5x zooms clean; no errors)

Base: 0.48.1. Owner report: the Shot analysis and Curve popups over a custom
page showed the DARK theme's home art in their ring and through the card.
`glass_material` only knew dark and light and handed custom the dark files.
**Safety status: TWO more files in the same place, same trigger:
`lumen_home_glass_custom.png` and `lumen_home_dim_custom.png` join the
custom set written by `ensure_bake` into `skins/Lumen/<WxH>/` (painter
signature 3, so every existing custom set is redrawn once). Nothing else.**

- `::lumen::custom::pages` gains `home_glass` and `home_dim`: home's own
  panel table painted from a derived palette. `dim_gen` scales every
  colour by the bake's dim factor (0.66 dark / 0.78 light). `glass_gen`
  applies the bake's slab recipe (saturation, brightness, tint) and drops
  border, specular and lift; the slab's panels are painted with the new
  `soft` mode of `panel_png` (fill alpha ramps over the blur radius across
  the edge) as the stand-in for the Gaussian blur pure Tcl cannot afford.
- `glass_material` under custom serves the `_custom` trio and reports the
  custom BASE (dark/light) as the consumer's colour set, never "custom".
  A missing file still means no material, i.e. GrindAdvisor's opaque popup.
- Harness: custom material against a scratch folder (served / refused),
  the pages table, glass_gen / dim_gen, the soft ramp, signature 3.

Files: skin.tcl, tools/check_skin.tcl, docs.

## 0.48.1 - retheme only DYE's own rebuildable pages - TABLET-VERIFIED 2026-09-16 19:43 (custom -> dark -> light -> custom: "DYE rethemed, 10 of 10 pages recreated" in 3.3-3.4 s each, whole apply 4.4-4.7 s, 0 problems; DYE editor plus its Edit data and Manage dialogs eyeballed in Light and again in Custom; the three foreign pages on the theme are listed at DEBUG and keep their items across every switch (8 / 19 items before and after); only the pre-existing D_Flow startup error in the log)

Base: 0.48.0, first tablet run. **Safety status: unchanged.** The 0.48.0 run
worked for DYE (editor + dialogs in Light and Custom, 11 pages in ~3.5 s,
0 problems) but its page filter was "every page on the DYE_Lumen theme",
and two OTHER plugins' pages sit on that theme because they were added while
it was current (DPx_SS_options, history_exclusion_filter); both are
namespace-less, so the recreate deleted them and could not redraw them
(empty until restart). Now only pages named `DYE*`/`dye_*` whose namespace
has a `setup` proc are rethemed; the rest are listed at DEBUG and keep
their look. Harness: three stray pages on the theme must be left alone.

## 0.48.0 - DYE's pages follow a live theme change - superseded by 0.48.1 before verification (first tablet run 2026-09-16 19:39: DYE editor, Edit data and Manage dialogs correct in Light and Custom; two foreign pages emptied, see 0.48.1)

Base: 0.47.0. Custom theme pass 3. **Safety status: unchanged. No new writes
of any kind; DYE's data arrays and its persistence are untouched -- only its
canvas items and widgets are recreated, by dui's own page machinery.**

- The DYE_Lumen aspects moved out of the `setup_ui_Lumen` hook into
  `::lumen::dye_aspects`, called by the hook at DYE init and again by
  `apply_theme` from the new palette.
- `::lumen::_retheme_dye` (step 6 of apply_theme): every page whose
  `dui page theme` is DYE_Lumen goes through `dui page retheme ... 1`
  (delete keeping its data, add with the saved arguments, run the page's
  setup) -- the mechanism dui itself names for an already-set-up page. No
  DYE file is edited. Skipped with a NOTICE if a DYE page is on screen
  (never the case from the THEME row or the picker); nothing happens when
  the theme does not exist (DYE absent).
- Harness: aspects re-set from the new palette exactly once per apply, the
  three fake DYE pages rethemed forced, the on-screen guard, DYE absent.

Files: skin.tcl, tools/check_skin.tcl, docs.

## 0.47.0 - live retheme: a theme change applies in place, no quit-and-reopen - TABLET-VERIFIED 2026-09-16 (THEME taps custom -> dark -> light -> custom on the settings page, each redrawn in 1.1-1.3 s with 0 problems; home eyeballed in light and custom, chart panel tones and series right; picker Done with Sea glass: "Drawing your theme..." shown, five backgrounds drawn in 7.4 s, settings returned in the new colours; Espresso preset restored the same way in 7.0 s over the same filenames, new pixels shown; no Lumen errors in the log; tablet left on home in the owner's Espresso theme. Colour audit via DevBridge 0.3.2: 286 coloured options over all nine Lumen pages, flow pages included, 0 stale in each theme; 5x zooms artefact-free. Known gap: DYE's pages keep the launch palette until the next start)

Base: 0.46.1. Custom theme pass 2 of 2. **Safety status: unchanged. No new
writes; the same five prefs and `lumen_theme` are saved by the same taps,
and the custom PNGs plus `lumen_custom.sig` are still the only files
written -- now also when THEME or the picker's Done lands on Custom, not
only at skin load. Nothing in history/, history_v2/ or any database.**

- `::lumen::apply_theme mode`: (custom) `ensure_bake` first; `set_palette`;
  `.can -bg`; every page background swaps its photo through
  `dui::image::find` (a custom file is re-read in place, so a re-bake
  shows) or refills its flat rect; one `itemconfigure` per role tag; the
  photo panels are repainted from the new painter parameters; the graphs
  restyled; `refresh_preview`. A failed custom apply changes nothing,
  logs, restores the preference and says so in the THEME caption.
- Role tags (`::lumen::_tags`): every item drawn by `txt`, `var`,
  `rounded_rect`, `glass`, `chip`, `draw_de1_icon` leads with a unique
  `lumen_i_N` tag and carries `lumen_c_<token>` / `lumen_o_<token>` from a
  colour->token reverse map built in `set_palette`.
- THEME applies on the tap; the picker's Done saves, shows "Drawing your
  theme..." while the tablet paints, applies, returns to settings.
  `pending_theme` and `restart_for_theme` are gone; Done is a page switch.
- Not live (next launch): DYE's `DYE_Lumen` theme. GrindAdvisor's popup
  reads `glass_material` when it opens, so it follows.
- Harness: role-tag audit (unique first tags, no untagged token fills),
  fake canvas / photo / graph, every apply path incl. failure and flat pages.

Files: skin.tcl, tools/check_skin.tcl, docs.

## 0.46.1 - the custom painter matches the bake; photo panels on the picker - TABLET-VERIFIED 2026-09-16 (owner's Espresso preset redrawn at launch in 7.0 s: home, settings and the picker's photo panels all soft-shadowed, no strips, no seams; theme left as the owner set it)

Base: 0.46.0. **Safety status: unchanged (same files, same prefs; the
signature's painter number is 2, so existing custom PNGs are redrawn once).**

- Owner report: artefacts on the custom pages. Cause: the shadow was clipped
  to OUTSIDE the panel with a profile that jumped from full to half at the
  shadow rect's offset edge -- a hard darker strip under every panel and
  chalk-white interiors -- while the bake casts a Gaussian shadow UNDER the
  translucent glass (that darkening is what makes its panels read grey).
  `_fall` is now a continuous blurred-edge profile (1 inside, 0.5 on the
  edge, 0 at 2 sigma); the shadow sits under the glass; S 18 / offset 6 for
  panels and pills alike; the bake's own alphas (glass 14|150, raised
  26|200, shadow 150|70, lift 11|70, accent wash 12|120, specular 80|120).
- Tapered specular on rows 1-2 (0 at both ends), the top-lift wash over
  85% of each non-flat panel, chart panels flat. Opaque tokens are now
  "glass over shadowed ground": the model reproduces the sampled chart
  tones (#131418 vs #151618 dark, #DDE0E5 vs #DEE0E4 light; harness-pinned).
- `glass` on non-baked pages draws a photo panel from the same painter
  (polygon only headless / on failure), so the picker rows are real glass.
- Light accent floor 18 (a yellow accent must be allowed down to olive to
  clear 3:1 on pale glass). Memo rows keyed by 8-bit alpha.

Files: skin.tcl, tools/check_skin.tcl, docs.

## 0.46.0 - Custom theme: your own backdrop and accent, drawn on the tablet - TABLET-VERIFIED 2026-09-16 (picker opened from the THEME caption, Sea glass preset, Done, relaunch: the five backgrounds drew in 5.6 s, home + settings rendered in the custom palette, chart flush with its panel; cycled back to dark via THEME + Done)

Base: 0.45.0. Tablet lesson: the first picker screenshot showed the preview's
bean name over its stepper pills; the mini strip grew to 136 px. **Safety status: TWO new write capabilities, both confined to
Lumen's own data. (1) Five preferences `lumen_custom_base|bh|bs|ah|as`
plus `lumen_theme=custom`, written only by the picker page's Done through
`save_settings`. (2) Five PNG files `lumen_<page>_custom.png` and a
`lumen_custom.sig` stamp written into `skins/Lumen/<WxH>/` at skin load
when the custom theme is active and the stamp disagrees with the saved
colours. Nothing in history/, history_v2/ or any database is touched.**

- THEME cycles Dark -> Light -> Custom; the row's caption opens the new
  `lumen_theme` picker: BASE (dark/light), BACKDROP and ACCENT (12 hue
  swatches each), six PRESETS, and a PREVIEW column redrawn from the pending
  colours on every tap (role-tagged canvas items). Done saves and applies
  through the existing quit-and-reopen; Cancel discards.
- `::lumen::custom::palette` derives every token from the five inputs, with
  a contrast guard (labels >= 4.5:1, accent >= 3:1 against the glass) that
  the harness proves over 864 palettes; semantic and chart colours stay.
- `::lumen::custom::ensure_bake` draws the five page backgrounds in pure
  Tcl (gradient column zoomed wide, panels and pills as alpha PNGs with
  outside-only soft shadows, quarter-scale bloom) and writes them where dui
  already looks. ~1.3 s of painting on the PC; expect several seconds on
  the tablet, once per colour change. On failure the pages fall back to
  `-bg_color` plus vector glass, never blank. GrindAdvisor's glass popup
  stays opaque under Custom (no glass slab is drawn for it).
- Harness: palette guard, PNG decode + pixel probes, prefs clamp, theme
  cycle, apply + restart-once, preview refresh, picker zones.

Files: skin.tcl, tools/check_skin.tcl, docs.

## 0.45.0 - LOW WATER threshold row fills the settings page's fourth slot - TABLET-VERIFIED 2026-09-15 (dark theme via DevBridge: "300 ml" between its pills, caption on two lines clear of the group, columns level; no log errors)

Base: 0.44.0. **Safety status: ONE new preference write, `lumen_water_low_ml`
(100..800 ml, step 50, default 300), written only by the row's -/+ taps
through `save_settings`, never sent to the machine. Nothing else changes.**

- The right column's empty fourth slot (since 0.42.0 removed DECENT APP)
  now holds LOW WATER: the level under which the taskbar's water reading
  turns amber (0.43.1 hard-coded 300). Same stepper geometry as BAGS TO
  CYCLE; both columns are four rows on the 110/244/378/512 grid again.
- `::lumen::water_low_ml` reads and clamps the setting (junk -> 300);
  `adjust_water_low` steps it; the taskbar's blue/amber split and the
  tank-empty page's readout follow it on the next tick.
- make_backgrounds.py: right column four panels + the row-4 stepper pills;
  only the four `lumen_settings*.png` changed, palette samples unchanged.
- Harness: LOW WATER in the row table; the row-4 stepper must call
  adjust_water_low; default / step / clamp / junk cases and the taskbar
  split at a custom threshold.

Files: skin.tcl, tools/make_backgrounds.py, tools/check_skin.tcl, 4 settings PNGs, docs.

## 0.44.0 - the tank-empty page is a Lumen page - TABLET-VERIFIED 2026-09-15 (dark theme via DevBridge page load: panel, title, body, live "760 ml", Exit App / Ok pills in the stock zones; retry hint blank while idle, as the core intends; light theme checked as the baked image only)

Base: 0.43.1. **Safety status: unchanged. No writes; the page's three tap
commands are the stock ones, copied verbatim (start_refill_kit twice, the
stock Exit App sequence through the message page + app_exit).**

- The stock `tankempty refill` pages (cracked-earth fill_tank.jpg from
  skins/default/standard_includes.tcl) are deleted with dui's own
  `page delete` right after that file is sourced and re-declared on a new
  baked `lumen_message[_light].png` (centred panel, two bottom pills inside
  the stock Exit App / Ok zones). Both pages join `baked_pages`.
- Content: "Please add water" title, a one-line explanation, the core's
  own retry hint (`refill_kit_retry_button`), and the live tank reading in
  the taskbar's blue/amber pair so the level can be watched rising. Press
  flash: ring on the panel for the retry zone, label chips on the pills.
- make_backgrounds.py: MESSAGE_PANELS / MESSAGE_INNER + the `message` page;
  every existing PNG re-baked byte-identical (only the four new files
  appeared), palette samples unchanged.
- Harness: page add/delete recorded by the dui stub; asserts delete-then-add
  on lumen_message, the five stock zones with their commands, pills inside
  the zones; `refill_kit_retry_button` stubbed.

Files: skin.tcl, tools/make_backgrounds.py, tools/check_skin.tcl, 4 new PNGs, docs.

## 0.43.1 - polish batch from the 2026-09-15 review - TABLET-VERIFIED 2026-09-15 (dark theme: home + settings screenshots; "Tap to retry" seen after 30 s; light theme and the espresso-page note not yet eyeballed)

Base: 0.43.0. Lesson from the first push: the loader restores only the chart's
pre-scaled weight/temperature vectors, so the legend reads those (x10), not
the raw ones. **Safety status: unchanged. No new writes; the one new read is
the shot file's top-level `clock`, latched with the rest of the record.**

- Confidence band coloured by meaning: Good/Excellent green, Poor amber, Fair
  and the estimate line neutral (three stacked items). Grind delta in ink_2.
- LAST SHOT card gains "Today 15:05" / "Yesterday" / "Fri 12 Sep 12:40"
  (file clock, espresso_clock in-session; honours the CLOCK row formats).
- Chart legend shows each series' final value with its unit; pitch 110 -> 170.
- LAST SHOT ratio one decimal, like NEXT SHOT. STEAM row's small line carries
  its unit. Theme copy says the app closes (it never restarted itself).
- Scale readout: "Connecting" becomes "Tap to retry" after 30 s of one attempt.
- Taskbar water turns amber under 300 ml (second stacked item).
- Espresso page: "of 38.0 g" under the live weight (blank with no target).
- Tertiary ink lifted for contrast: dark #74829A -> #8290A8, light #7C8798 -> #65708A.
- Stale header/layout comments fixed. Harness expectations updated (ratio, steam
  unit, low-water split). No bake, no asset change.

## 0.43.0 - the chart shows the last REAL shot of the loaded bean - TABLET-VERIFIED 2026-09-15 (startup, bag cycler, and a live cleaning cycle: the core saved 20260915T220626 at 22:08:57.841, Lumen's listener reloaded the bean's 20.8 s real shot at .842, SDB indexed the cleaning run afterwards)

Base: 0.42.0.

**Safety status: unchanged. No writes of any kind; reads are history/*.shot
files, one at a time, only when a shot is selected for the home page (never
per tick). SDB through its public `shots` / `string2sql` only.**

- Owner report: a cleaning run took over the home chart and LAST SHOT card.
  Cause, verified on the tablet: the core saves a cleaning run as a normal
  shot file (`beverage_type cleaning`, ~140 s, the loaded bag's bean fields
  copied in), so "newest file" (startup) and "the bag's newest SDB clock"
  (cycler) both landed on it, and nothing reloaded after the run.
- New `last_shot_candidates`: the bag's shots from SDB filtered like DYE
  (`beverage_type NOT IN cleaning/calibrate`), then any bag, then the
  directory newest-first; `_load_shot_file` rejects by GrindAdvisor's
  non-espresso regex on profile/beverage type and by a 5 s floor, and
  steps to the next candidate. Used by startup, SHE refresh and the cycler.
- `after_flow_complete` listener (registered after the core's save, FIFO):
  a flow latched as non-espresso at espresso-page show reloads the bean's
  last real shot once the file is saved.
- LAST SHOT card names the FILE's roaster/bean (was the live settings).
- Harness: check_last_shot.tcl section K (directory + SDB paths, in-session
  hook, regex), J rewritten for the resolver; check_skin asserts the hook.

Files: skin.tcl, tools/check_last_shot.tcl, tools/check_skin.tcl, docs.

## 0.42.0 - drawn DE1 side-view icon opens the app settings (one tap again)

Base: 0.41.0.

**Safety status: unchanged. The icon's tap runs the existing `open_app_settings`; no writes.**

- Owner verdict on 0.41.0: the DECENT APP row costs two taps - reversed. Fifth taskbar
  slot returns at 1196 (mug/wrench/gear back to 980/1052/1124, dot to 1102), but with a
  DRAWN side view of the DE1 (owner-picked sample 1: body, tilted screen edge-on, group
  head, drip tray) instead of the ambiguous sliders glyph. New `draw_de1_icon`: three
  `rounded_rect` outlines + one round-capped line, palette ink, virtual -width 4 (~2px
  physical, matching the FA glyph weight). No glyph fallback needed - vectors always draw.
- DECENT APP settings row removed; right column back to three rows; the four settings
  PNGs re-baked byte-identical to the 0.40.0 assets (hash-verified).
- check_skin.tcl: five-zone bar again + the DE1 zone must carry open_app_settings.

Files: skin.tcl, tools/make_backgrounds.py, tools/check_skin.tcl, 4 PNGs (reverted).

## 0.41.0 - settings merge: sliders icon folded into a DECENT APP row - TABLET-VERIFIED 2026-09-03 (dark theme; four icons, Open -> stock settings -> home, no log errors) - REVERSED by 0.42.0 same day (two taps)

Base: 0.40.0.

**Safety status: unchanged. No new writes; the row's tap runs the existing
`::lumen::act::open_app_settings` (core `show_settings`), same as the removed icon.**

- Taskbar: the sliders icon is gone -- gear and sliders side by side both read
  as "settings" (owner report). Four tappables remain (mug 1052, wrench 1124,
  gear 1196, moon 1268 -- shifted one pitch right, moon flush at 1324);
  maintenance dot follows the wrench to 1174.
- Lumen settings: DECENT APP row in the empty fourth right-column slot (512),
  THEME-row pattern -- label, caption, neutral raised 150x56 "Open" button.
- Baked `lumen_settings*.png` regenerated (both themes, 1340x800 + 2560x1600);
  image-diff clean, only those four files changed. Palette samples unchanged.
- check_skin.tcl regression rows updated (four-icon bar, CLOCK at ry3, DECENT
  APP corner button); ALL CHECKS PASSED, no warnings.

Files: skin.tcl, tools/make_backgrounds.py, tools/check_skin.tcl, 4 PNGs.

## 0.40.0 - Drink Menu taskbar button

Base: 0.39.1.

**Safety status: unchanged. No settings writes added; no database, no history files.**

- Fifth taskbar tappable, leftmost of the right-hand group at design x 980
  (56x48 on the 72 pitch): FA6 `mug-hot` (`[format %c 0xF7B6]`) in `font_bt`,
  text fallback "CUP" through the same mechanism as the other four.
- Tap runs `::lumen::act::open_drinkmenu` (the Maintenance shortcut's
  `catch` + `info procs` + `msg -ERROR` shape) calling
  `::plugins::DrinkMenu::open_page DrinkMenu_main`; the plugin captures "off"
  as its return page, so Done lands back home.
- `bar_water_x` 1028 -> 956 so the widest readout ("1500 ml") stays one lg
  clear of the mug zone. Banner version line now tracks `variable version`.

Files: skin.tcl.

## 0.39.1 - the material adds `bg`, the plain page background - TABLET-VERIFIED 2026-09-01 (with GrindAdvisor 3.14.5)

Base: 0.39.0.

**Safety status: unchanged. One dict key in `glass_material`.**

- GrindAdvisor 3.14.1-3.14.3 could not hide the card boundary with any
  guessed blend colour; 3.14.4 rings the card with a crop of the page's own
  art, so the material now carries `bg` = the path to `lumen_home[_light].png`,
  required alongside `glass`/`dim` and existence-checked like them.
- Dark slab retuned the same day for more see-through (tint 0.20, blur 16,
  brightness 1.28); harness H2 checks all three files.
- Owner confirmed the glass popup on the tablet: both themes, grab modality,
  live page around the card, seamless edges.

Files: skin.tcl, tools/make_backgrounds.py, tools/check_skin.tcl, glass PNGs.

## 0.39.0 - glass material provider for plugin overlays - TABLET-VERIFIED 2026-09-01 (via 0.39.1 + GrindAdvisor 3.14.5)

Base: 0.38.0.

**Safety status: unchanged. Nothing visible changes in Lumen itself - one
new public proc and eight baked PNGs; no settings writes, no page edits.**

- First half of the iOS-style "liquid glass" popup (owner mockup "variant C").
  Tk has no runtime blur/alpha, so `make_backgrounds.py` bakes
  `lumen_home_glass[_light].png` (blurred, tinted, saturated slab) and
  `lumen_home_dim[_light].png` (scrim) for both themes and both resolution
  folders (~730 KB); all existing PNGs regenerate byte-identical.
- New public `::lumen::glass_material`: returns
  `{ok 1 page off theme dark|light radius 26 glass <path> dim <path>}` only
  when the current page is home AND the files exist for the screen's exact
  physical WxH; otherwise `{}`. Consumers guard with `[info procs]` (no glass
  off-skin, owner requirement) and call it once per popup open, never per tick.
- Honest limit: the slab shows the baked art; live values do not bleed through.
- Harness section H2: served on home in both themes, refused off-home and for
  unknown resolutions, quiet with no page context.

Files: skin.tcl, tools/make_backgrounds.py, tools/check_skin.tcl, 8 new PNGs.

## 0.38.0 - the grind tile shows GrindAdvisor's new-bag starting estimate - TABLET-VERIFIED 2026-08-29

Base: 0.37.1.

**Safety status: unchanged. Read-only accessors; no bake, no settings
writes. The one new plugin call reads SDB through GrindAdvisor's own
public, SELECT-only path.**

- GrindAdvisor 3.13.0's `starting_estimate` (display-only grind borrowed from
  calibrated bags) is shown for a bag with no shots: header STARTING ESTIMATE
  (live accessor `grind_header`; an estimate is never captioned
  "Recommended"), hero `~13.5`, chip "Estimate", GA's reason band, and a
  "Start ~13.5 (est. from 4 bags) - pull a shot to calibrate" note.
- `::lumen::data::grind_est` caches the result PER BAG KEY: `current_bag_key`
  is compared each 200 ms tick and the single unmemoized SDB read runs only on
  a key change (misses cached too). A real recommendation always wins.
- Older, absent, throwing or junk GrindAdvisor degrades byte-for-byte to the
  0.37.1 tile (harness-pinned). Harness section H added; a `{{{` self-parse
  trap in the harness fixed with `string repeat`.

Files: skin.tcl, tools/check_skin.tcl.

## 0.37.1 - the chip stays inside the button and matches its corners

Base: 0.37.0.

**Safety status: unchanged. Two numbers in press_flash.**

- Owner report: the zone chip read larger than the pill with sharper corners.
  Root cause: a `-smooth 1` canvas polygon renders roughly HALF the curvature
  of its control-point radius, so nominal 16 px corners poked past the pills'
  true 16 px arcs at a 1 px inset.
- Inset 1 -> 3 design px; corner control radius over-provisioned to ~28 design
  px so the RENDERED curve matches; card ring 48 -> 96 virtual for its 24 px
  baked corners. Rule: feed a smoothed-polygon rounded rect ~double the target
  radius.

Files: skin.tcl.

## 0.37.0 - press flash Option B: a chip that fits what you see

Base: 0.36.0.

**Safety status: unchanged. Flash mechanics only; no bake, no settings
writes.**

- Owner picked "Option B" after the 0.36.0 flash still read as a yellow
  rectangle: the flash had painted the TAP ZONE, far bigger than the visible
  control on the grind card and text links.
- `::lumen::tap` gains a per-zone style passed to `press_flash`: `zone`
  (default; neutral `glass_2` chip + `glass_brd` hairline lowered under the
  label, stepped to `glass` at 90 ms) for pill-backed controls; `label` (chip
  fitted to the union of visible text bboxes, padded 10x6, clamped to the
  zone) for Shot history / Curve / Shot analysis / PROFILE row / steam+water
  mode line; `ring x y w h` (hollow crema hairline on the card rect) for the
  grind card's two body zones. The 0.36.0 crema-filled chip is gone.
- Harness section L rewritten with `_flash_case` per style against a
  context-aware canvas stub.

Files: skin.tcl, tools/check_skin.tcl.

## 0.36.0 - chart pills gone, press flash is a chip, grind card opens Grind Advisor

Base: 0.35.0.

**Safety status: unchanged - Lumen still opens no database and writes
no history file. This version REMOVES two settings writes (the
smoothing and stages toggles are gone). Home + settings backgrounds
re-baked.**

- Stages and Raw/Smooth pills removed from the chart; always smooth
  (Catmull-Rom) with stage separators (`chart_smoothing` / `stages_shown` are
  fixed policy). Deleted: both toggle actions, their label accessors,
  `chart_apply_smoothing` / `chart_apply_stages`, the `chart_widgets`
  registry. `live_graph_smoothing_technique` and `lumen_chart_stages` are no
  longer read or written.
- Press flash became a crema-tinted filled chip with a thin border, lowered
  beneath the control's own label (find-overlapping + lower below the lowest
  visible text), so text links get a real pressed look.
- Grind card zones A+B open Grind Advisor's settings; "Shot analysis" keeps
  the popup, Curve unchanged. Settings page GRIND ADVISOR row removed, CLOCK
  moved up to row 3, `settings_button_row` deleted with its last caller.
- Re-bake changed only the 8 home + settings PNGs; chart_bg samples unchanged.

Files: skin.tcl, tools/make_backgrounds.py, tools/check_skin.tcl, 8 PNGs.

## 0.35.0 - NEXT SHOT card: PROFILE stacked under the label

Base: 0.34.1.

**Safety status: unchanged. Text and tap-zone geometry only; no bake.**

- Owner request: PROFILE moves to its own row under NEXT SHOT, matching the
  LAST SHOT card's stacked order (label / PROFILE / roaster / hero). This
  reverses half of 0.27.0.
- Six rows in 148 px cannot keep 10 px gaps, so the block re-spaces to a
  uniform 7 px gap with a 10 px top pad: label 584, PROFILE 606, roaster 629,
  hero 652, notes 699, action row 722 unchanged. PROFILE value width 255 ->
  370; profile tap zone moved onto its row (40,592 460x44).
- Harness: identity gap floor 7 for this layout (escape hatches documented);
  profile-zone assertions reworked.

Files: skin.tcl, tools/check_skin.tcl.

## 0.34.1 - spacing fixes (owner report on 0.34.0)

Base: 0.34.0.

**Safety status: unchanged. Geometry only.**

- Taskbar day label touched the 12-hour time's "AM": the tablet's 26 px mono
  advances ~15.5 px/glyph, not the 13 estimated. Day moved 130 -> 170; the
  harness estimate corrected to 16 px/glyph.
- Tiles' bottom text rows crowded the card border after 0.31.0 took 8 px from
  the cards. Cards back to h 190 (ends 254), the chart pays (270..558, h 288);
  every internal row keeps its clearance with zero row edits.
- Re-bake: only the four `lumen_home*` PNGs changed; `chart_bg` unchanged.

Files: skin.tcl, tools/make_backgrounds.py, tools/check_skin.tcl, 4 PNGs.

## 0.34.0 - taskbar wordmark + water readout; CLOCK formats row

Base: 0.33.0.

**Safety status: unchanged. No new reads or writes beyond two new
`lumen_*` preference keys saved through the standard `save_settings`
path.**

- Water level moved from the last-shot card corner to the taskbar (same
  accessor, blue mono, anchored right of centre, blank when the machine has
  not reported in 10 s). "Lumen" wordmark dead-centre, passive.
- DECENT APP removed from Lumen settings (the taskbar's sliders icon opens the
  same place); its bottom-right row is now CLOCK with a 24H/12H toggle and a
  date toggle ("26 Aug" vs "Aug 26"). New settings `lumen_time_format`
  (24|12) / `lumen_date_format` (dmy|mdy), defaults identical to 0.31.0,
  written only on a tap via `save_settings`, picked up on the next 200 ms tick.
  12-hour time is zero-padded so the widest time is constant-width; day label
  110 -> 130.
- Re-bake: only the four `lumen_settings*` PNGs changed. Harness: section E
  updated, section N added (format matrix, toggles, labels), taskbar spacing.

Files: skin.tcl, tools/make_backgrounds.py, tools/check_skin.tcl, 4 PNGs.

## 0.33.0 - taskbar pass 3 of 3: side panel absorbed, full-width strip

Base: 0.32.0.

**Safety status: unchanged. No new reads or writes; Profile's tap calls
the same `open_profiles` the deleted panel button called.**

- Owner's Layout 2 end state, landed only after the 0.32.0 taskbar was
  tablet-verified carrying Settings and Sleep.
- Side panel deleted (panel, three pills, three tap zones); the bean strip is
  full width, 16..1324. Stepper columns on a 270 pitch, value spans 140 (so
  "38.0 (1:2.0)" fits), groups 240 wide flush at 1300; bottom row on the same
  grid, level with the identity block's action row.
- Profile is a tap on the identity row's PROFILE label+value (170..500, 48
  tall), same `open_profiles` -> stock settings_1 tab.
- Second re-bake: only the four `lumen_home*` PNGs changed; chart_bg
  unchanged. Harness: PROFILE-zone checks replace side-panel checks; 40 zones
  flash-covered.

Files: skin.tcl, tools/make_backgrounds.py, tools/check_skin.tcl, 4 PNGs.

## 0.32.0 - taskbar pass 2 of 3: tappables + maintenance dot

Base: 0.31.0.

**Safety status: read access widens by one guarded case - the taskbar dot
reads `::plugins::MaintenanceTracker::status_summary` (cache-backed on the
plugin side) through the standard info-procs + catch + degrade guard.
Nothing written; the wrench opens the plugin's own page via its public
`open_page`, same contract as the Shot History and Grind Advisor
shortcuts.**

- Four tap zones on the bar, 56x48 on a 72 pitch, flush at 1324: wrench
  (Maintenance Tracker), gear (Lumen settings), sliders (app settings), moon
  (Sleep, the app's own `start_sleep`). FA6 glyphs via `F(symbol)` as
  `[format %c]` escapes with letter fallbacks MNT/SET/APP/ZZZ.
- Maintenance dot at the wrench corner: amber "due soon", red "overdue",
  nothing when fine, absent, or when anything about the read is off. New
  palette token `C(danger)` (#DA515E dark / #B23641 light).
- New guarded `::lumen::act::open_maintenance`. The side panel still
  duplicates Settings/Sleep on purpose until this bar is verified.
- No bake. Harness: taskbar budget checks and section M (dot through absent /
  ok / amber / red / failed / malformed / throwing plugin); 42 zones covered.

Files: skin.tcl, tools/check_skin.tcl.

## 0.31.0 - taskbar pass 1 of 3: geometry, re-bake, live time

Base: 0.30.0.

**Safety status: unchanged. No new reads, no writes, no plugin calls. The
two new accessors (`bar_time` / `bar_day`) call only `clock`, on the app's
existing 200 ms variable tick.**

- Owner picked Layout 2 ("panel absorbed") from the discovery report; this
  pass carves the bar and puts passive time/day on it. Taskbar 0..48; top
  cards 64..246 (h 182); chart 262..558 (h 296); strip and side panel
  untouched. Last-shot tile absolute row tokens +48; grind tile rows are
  `grind_y`-relative.
- Time (`%H:%M`, mono) and day (`%a %d %b`) ride the 200 ms tick; dui
  reconfigures on change only, so one redraw per minute.
- All four `lumen_home*` PNGs re-baked; the twelve others MD5-identical.
  Light `chart_bg` re-sampled #DEE0E5 -> #DEE0E4.
- Harness: taskbar budget block; fixed a latent fault where `clock format`'s
  lazy autoload died under the stubbed `source`/`package` (pre-warm added).

Files: skin.tcl, tools/make_backgrounds.py, tools/check_skin.tcl, 4 PNGs.

## 0.30.0 - the chart follows the bag cycler; the flash ring hugs the control

Base: 0.29.1.

**Safety status: unchanged. Read access widens by one case: the loader can
be pointed at a SPECIFIC `history/*.shot` file (the cycled bag's newest)
instead of only the newest overall. Same single-file read, same local
parse, same `history_saved` guard. Nothing written.**

- `cycle_bag` resolves the bag's newest shot file (`_bag_last_shot_file`:
  filenames ARE clocks, `%Y%m%dT%H%M%S`) and calls
  `load_last_shot_curves 1 <path>`, so chart, LAST SHOT card and profile all
  describe the bag on screen. A soft-deleted newest shot falls back to the
  next on disk; a fully trashed bag leaves the chart alone with a NOTICE; a
  load failure never undoes the cycle.
- Flash ring inset 5 -> 1 px (pill zones ARE their drawn bounds), radius =
  the baked pills' RADIUS_S (16 design px).
- Accepted asymmetry: an SHE reload loads the GLOBAL newest and snaps a
  cycled view back to the newest bag.
- `check_last_shot.tcl` section J covers the explicit-path loads.

Files: skin.tcl, tools/check_last_shot.tcl.

## 0.29.1 - the press flash is a clean accent ring, not a stipple

Base: 0.29.0.

**Safety status: unchanged - drawing options inside `press_flash` only.**

- Owner: the 0.29.0 flash "looks like a graphics bug". `-stipple gray25` is a
  raw 4x4 checkerboard and reads as pixel corruption at tablet DPI.
- The flash is now a hollow crema ring: >= 3 px accent outline in the
  control's rounded shape, inset a few px, no fill, label fully visible; same
  150 ms life and shared-tag lifecycle.
- Rule: never fake alpha with `-stipple` on this panel.

Files: skin.tcl.

## 0.29.0 - every tap gets a visual press flash

Base: 0.28.1.

**Safety status: unchanged. One new drawing helper and one line in `tap`.
Nothing written, no file handling, no page structure changes.**

- Owner: buttons felt "flat and dead" (every control is baked pixels with an
  invisible zone). `::lumen::press_flash` draws a 150 ms crema glow in the
  zone's rounded shape; wired inside `tap`, so all 38 zones got it at once.
- Rules baked in: transient items go straight on `.can`, never through dui;
  direct `.can` drawing needs `rescale_x/y_skin`; `update idletasks` before
  the button's command; a new press clears the previous glow; the five
  full-screen flow-stop zones deliberately do not flash.
- Harness section L: every button either flashes with its own zone
  coordinates or is a full-screen stop.

Files: skin.tcl, tools/check_skin.tcl.

## 0.28.1 - stepper acceleration only on genuinely rapid taps

Base: 0.28.0.

**Safety status: unchanged - one timing constant in the stepper
acceleration. No file handling, no page changes, nothing written.**

- Owner report: careful tapping on the grind stepper escalated to 0.5 steps.
  The 700 ms window contained a measured step-step-step pace (~500-700 ms).
- Window now 350 ms: escalation needs drumming (3+ taps a second);
  thresholds (0.5 after three, 1.0 after six) and resets unchanged.
- Harness section K drives `_accel_step` on a fake clock: 600 and 400 ms
  paces stay 0.1, 250 ms drumming escalates, pause and direction reset;
  negative-tested against the old window, which reproduces the report.

Files: skin.tcl, tools/check_skin.tcl.

## 0.28.0 - the home page follows Shot History Editor changes - TABLET-VERIFIED 2026-08-24

Base: 0.27.2.

**Safety status: unchanged. No database is opened, and nothing in `history/`
or `history_v2/` is written, renamed or deleted. This version adds a REREAD
of the newest shot file - the same single-file read the skin has done at
startup since 0.24.1 - triggered by ShotHistoryEditor instead of only by
startup.**

- `load_last_shot_curves {force 0}`: the plain call is byte-identical; force
  guards on `history_saved` (0 = live unsaved samples = refuse loudly) instead
  of the vector-length startup guard. Do not merge the two guards.
- `last_shot_rec` is cleared before repopulating so a deleted shot's values
  cannot linger on the previous shot's card.
- `::lumen::refresh_after_history_change` is the ONE public entry point (SHE
  v0.7.0 calls it guarded on `info procs`): force reload + `refresh_bag_list`.
  Every reload path ends `history_saved 1`, so the 0.27.1 flush trap stays
  closed (harness-asserted after each case).
- Verified on the tablet by driving a real SHE delete + restore: grind card,
  LAST SHOT yield and chart all followed with no shot and no restart.
- `check_last_shot.tcl` section I: plain refused, force refused mid-shot,
  delete-newest, sparse-file carry-over, flush trap.

Files: skin.tcl, tools/check_last_shot.tcl.

## 0.27.2 - the method chip showed a raw GrindAdvisor key - NOT YET TABLET-TESTED

Base: 0.27.1.

**Safety status: unchanged. No database is opened, and nothing in `history/`
or `history_v2/` is written, renamed or deleted. This version changes one
label map and one character budget; it touches no file and no shot data.**

- The chip read `regression_unt...`: GrindAdvisor 3.10.0 added a fifth rung,
  `regression_untrusted`, and `::lumen::data::grind_method` fell through to
  the raw-key fallback. Mapped to "Weak fit".
- Fallback budget 16 -> 12 characters (16 was ~134 px of 16 px Inter SemiBold
  in a 150 px chip).
- Harness section G reads the rung names out of `GrindAdvisor.tcl` (never a
  hand-written list) and asserts every rung has a short, underscore-free chip
  label that fits 12 characters.

Files: skin.tcl, tools/check_skin.tcl.

## 0.27.1 - a flush could overwrite the last shot's file - NOT YET TABLET-TESTED

Base: 0.27.0.

**This one destroyed real data on the tablet, and the exposure was ours.
Lumen writes no shot file; the fix is one settings flag that stops the core's
own save from firing on samples the skin loaded.**

- What happened: the 18 August shot file was rewritten by a FLUSH the next
  morning (`grinder_setting` 8 -> 7.5, `drink_weight` 37.8 -> 0, 29,948 ->
  21,506 bytes). The log shows `Idle => HotWaterRinse` followed by "Saved this
  espresso to history" with no espresso in between.
- Why: the core saves on `after_flow_complete`, which fires after ANY flow,
  guarded only by `!history_saved` plus the vector lengths, and writes to the
  filename from the PREVIOUS espresso's clock (`vars.tcl:3440-3457`).
  `load_last_shot_curves` fills exactly those vectors at startup for the home
  chart, which is what lets that guard pass. The write is the core's; the
  condition was ours.
- Fix: `set ::settings(history_saved) 1` after the vectors are loaded. The
  flag then states the truth (the samples were read out of history).
  `reset_gui_starting_espresso` clears it at a real espresso start
  (`machine.tcl:846`), so genuine shots still save. Anything that loads past
  shot vectors (the stock `preview_history` included) has this exposure.
- Recovery: ShotHistoryEditor's backup `20260819T002956_0d17` holds the intact
  file. `check_last_shot.tcl` sets `history_saved` 0 before the load and
  asserts it comes back 1 ("a flush would overwrite it").

Files: skin.tcl, tools/check_last_shot.tcl.

## 0.27.0 - the bag cycler gets a page indicator, and room to breathe - NOT YET TABLET-TESTED

Base: 0.26.1.

**Safety: display only. No new writes; the cycler still hands the bag change
to DYE's own `source_next_from`, as before.**

- Arrows shrunk from 120x48 to a stepper pill's 44x48 with Edit still between
  them. A draft that flanked the bag name was killed by the preview: the right
  arrow read as one of GRIND's controls. Assertion: arrows never share the
  stepper pills' row.
- Minus glyph lifted 2 design px in every stepper (`L(step_minus_dy)`),
  measured on a tablet screenshot (ink +2.5 vs +0.5 for plus).
- Dot-per-bag page indicator (text items U+25CF / U+25CB via `format %c`, not
  ovals, so the tick re-evaluates them free); the cycler no longer wraps.
  Bag list cached in `::lumen::bag_list` (refreshed on home `show` and at
  startup) so no SDB call rides the 200 ms tick.
- Identity block re-spaced to even 11 px gaps by moving PROFILE up beside
  NEXT SHOT; bag name gets the full 460 px. Backgrounds re-baked (three action
  row pills changed size). Harness section J: indicator states and end stops.

Files: skin.tcl, tools/make_backgrounds.py, tools/check_skin.tcl, home PNGs.

## 0.26.1 - the last shot is the newest SHOT, not the newest FILE

Base: 0.26.0.

**Safety unchanged: one file read, nothing written.**

- Caught in the tablet log minutes after 0.26.0: `loaded last shot curves from
  20260715T170133.shot`, a July shot, because the loader picked by mtime.
  ShotHistoryEditor v0.6.0 deliberately stamps mtime on a metadata edit so SDB
  re-reads the file, which promoted that shot to "last shot".
- The loader now sorts by FILENAME (`YYYYMMDDTHHMMSS.shot` is shot time);
  mtime survives only as a fallback for a name that is not a timestamp.
- Rule: the plugins are right to touch mtime; the skin was wrong to read it as
  a clock. `check_last_shot.tcl` builds two shots with the older one's mtime a
  day ahead and asserts the trap is live before relying on it.

Files: skin.tcl, tools/check_last_shot.tcl.

## 0.26.0 - STEAM and HOT WATER alternate between two settings - NOT YET TABLET-TESTED

Base: 0.25.0.

**Safety: display and machine preferences only. No database is opened; the
only file read is the newest `history/*.shot`, as since 0.9.0. The two new
steppers write `::settings(steam_flow)` and `::settings(water_temperature)`,
both clamped, both saved and sent through the same debounced
`save_settings` + `save_settings_to_de1` path the other machine steppers
already use.**

- One -/+ group per settings row drives whichever half is selected: STEAM
  alternates TIME (`steam_timeout`, +/-5 s) and FLOW (`steam_flow`, +/-0.1
  mL/s); HOT WATER alternates TEMP (`water_temperature`, +/-1 C) and VOL
  (`water_volume`, +/-10 ml). The mode line under the label is one 180x48 tap;
  the choice persists in `lumen_steam_mode` / `lumen_water_mode` (Lumen
  preferences, saved with `save_settings`).
- Clamps come from Streamline's own controls for the same fields:
  `steam_flow` 40..250 (floor from its data-entry dialog), `water_temperature`
  20..100.
- Rendering: selected value 26 px on the pill band's upper line, the other
  16 px beneath (the YIELD/ratio arrangement); mode line is two text items
  because a canvas item's `-fill` is fixed at creation. No re-bake.
- Harness section I: four display states, mode fallbacks, a tap moves only the
  selected setting, both clamps, toggle round trip.

Files: skin.tcl, tools/check_skin.tcl.

## 0.25.0 - the LAST SHOT card reports the shot's own record - NOT YET TABLET-TESTED

Base: 0.24.1.

**Safety: display only. No database is opened. Nothing in `history/` or
`history_v2/` is written, renamed or deleted - no version of this skin ever
has. Read access is one file: the newest `history/*.shot`, which
`load_last_shot_curves` has opened at startup since 0.9.0; this version takes
three more fields out of the copy it had already parsed. The header's SAFETY
STATUS block was corrected: it had claimed nothing in `history/` was read.**

- Owner case: a Shot History edit set `grinder_setting 8` in the file while the
  card kept showing the live `7.5`. The card now prefers the record:
  `::lumen::last_shot_rec(grind|dose|yield)` latched from the newest shot
  file's settings block at startup, winning over live `::settings` until a
  shot starts (`latch_shot_profile` drops the latch). The NEXT SHOT card is
  untouched: one card is the record, the other the plan.
- `last_ratio` now uses the same two accessors as the numbers it sits between.
  Grind is free text (not `_is_pos`); the weights must be positive.
- Not fixed here: Grind Advisor following a Shot History edit (it reads SDB;
  SHE never writes SDB; `sync_on_startup` is 0) - a Grind Advisor pass.
- Harness: G gains file-beats-live; G2 covers grind/dose across five states;
  `check_last_shot.tcl` reproduces the tablet state exactly.

Files: skin.tcl, tools/check_skin.tcl, tools/check_last_shot.tcl.

## 0.24.1 - the last shot's yield survives a restart - NOT YET TABLET-TESTED

Base: 0.24.0.

**Safety: display only. No database is opened; the only file read is the
newest `history/*.shot`, which `load_last_shot_curves` was already reading for
the chart and the profile name - one more field is taken from the copy it
already has in memory. Nothing in `history/` or `history_v2/` is written,
renamed or deleted, and no version of this skin has ever written to them.**

- The LAST SHOT card read `YIELD 0.0` while the grind tile called the same
  shot 37.8 g: `::settings(drink_weight)` does not survive a restart. The
  yield is now latched from the newest shot file (`::lumen::last_shot_yield`)
  and dropped when a shot starts.
- A missing yield was formatted as a reading: `_yield_raw` returns `""` when
  no source is positive, so the card shows `--` and the ratio blanks instead of
  `1:0.00`. Source order: `drink_weight` -> `pour_volume` -> file latch.
- Harness section G (five yield states); `tools/check_last_shot.tcl` added,
  running the loader against a real `.shot` file off-device.

Files: skin.tcl, tools/check_skin.tcl, tools/check_last_shot.tcl.

## 0.24.0 - water level, Profile shortcut, settings shuffle, flow-timer fix - NOT YET TABLET-TESTED

Base: 0.23.2.

**Safety: display and preferences only. No database is opened, no file in
`history/` or `history_v2/` is read, written, renamed or deleted, and this
version adds no write of any kind - the Profile button hands off to the app's
own profile page and the app owns everything that happens there.**

- Water tank level (blue, mL) top-right of the LAST SHOT card, converted by
  the core's `water_tank_level_to_milliliters`; suppressed unless
  `::de1(last_ping)` is within the core's 10 s (the core seeds `water_level`
  to 20 with no machine).
- Profile button in the side panel (Profile / Settings / Sleep, 56 tall) via
  `show_settings settings_1`, Streamline's own shortcut, no custom navigation.
- DECENT APP is the bottom-right settings card; THEME and BAGS TO CYCLE moved
  up, GRIND ADVISOR above it. Columns stay 460/500 (an intermediate 492/492
  build was reverted; `_init_layout` warns against equalising them).
- Flow timers gated to the current page visit: `::lumen::data::_flow_secs`
  reads `::timers` and reports a finished flow only if it started after the
  page was last shown (`::lumen::latch_flow_open` on each flow page's `show`),
  fixing the ~450 s flash at shot start. `_sane_secs` normalises `-0`.
- Settings row geometry moved into `_init_layout` tokens; backgrounds
  re-baked (home + settings); chart sample tokens unchanged. Harness sections
  D, E, F added.

Files: skin.tcl, tools/make_backgrounds.py, tools/check_skin.tcl, PNGs.

## 0.23.2 - water and flush pages read their own timers - TABLET-VERIFIED 2026-08-15

Base: 0.23.1.

**Safety status: display only, no new writes.**

- Water and flush were both reading `espresso_secs` (time since the last
  espresso), which looked right shortly after a shot and read 0 an hour later.
  New `data::water_secs` / `data::flush_secs` use the core's
  `water_pour_timer` / `flush_pour_timer`.
- Two harness defects exposed: `espresso_timer` was never stubbed (the
  accessors' `catch` hid it) and the harness hardcoded an absolute path to the
  workspace skin, so a modified copy silently re-ran the original. Path now
  from `[info script]`, printed at start; all four timers stubbed distinctly.
- The new check inspects the recorded `dui add variable` calls per page and
  asserts each flow page is wired to its own accessor.

Files: skin.tcl, tools/check_skin.tcl.

## 0.23.1 - strip rows levelled, even vertical rhythm - TABLET-VERIFIED 2026-08-15

Base: 0.23.0.

**Safety status: display only. Two token values.**

- The strip's bottom row sat 6 px above the identity block's action row:
  `scale_y` 716 -> 722 (= `id_act_y`), so all six controls share one baseline
  ending at 770.
- Right column evenly distributed: `step_y` 644 -> 642, giving exactly 32 px
  above and below the stepper pills (measured on the baked asset).
- Three harness assertions: rows share y and height; the two gaps are equal.

Files: skin.tcl, tools/check_skin.tcl.

## 0.23.0 - re-proportioned home, bean details on both cards - NOT YET TABLET-VERIFIED

Base: 0.22.0.

**Safety status: no new writes and no new settings.** Layout and display only.

- Owner mockup: top cards 16..206 (h 190), chart 222..558 (h 336), bottom row
  574..784 (h 210); every gap md.
- Both cards read LABEL -> PROFILE -> roaster (small) -> bean type (hero);
  identity block widened 280 -> 460 so a 44-character roaster fits. Tasting
  notes (`bean_notes`) on the next-shot card when non-empty.
- Last shot gained GRIND and the ratio note; Shot history became a text link.
  PROFILE left the stepper row (three columns on a 210 pitch); Edit moved to
  the action row between the cycler arrows (all 48 tall); the identity block's
  full-height DYE tap is gone (Edit is the single entry point).
- `C(chart_bg)` -> #151618 / #DEE0E5: the generator's sample point is absolute
  and the panel moved; re-sample whenever the chart panel moves.
- Four tablet text bugs fixed: last-shot profile drawn at the next-shot x,
  Curve left outside the shortened tile, last-shot bean name truncated (now
  `font_primary`, 24 chars), multi-line `bean_notes` collapsed to one line.

Files: skin.tcl, tools/make_backgrounds.py, tools/check_skin.tcl, home PNGs.

## 0.22.0 - the grind tile follows the cycled bag - NOT YET TABLET-VERIFIED

Base: 0.21.0.

**Safety status: no new writes, no new settings, no asset change.** No layout
change either, so nothing was re-baked.

- Owner report: cycling a bag changed the bean fields but the grind card kept
  its old number. Blanking (0.21.0's design) was wrong anyway - a bag you
  cycle back to has its own regression.
- `grind_rec` calls Grind Advisor 3.8.0's `recommendation_for_current_bag`
  (memoized per bag, so the 200 ms tick costs nothing). Older plugin builds
  are handled behind `[info procs]` in descending order of capability.
- A bag with no shots still shows the "pull a shot" note; nothing invents a
  grind.

Files: skin.tcl.

## 0.21.0 - bag cycler, profile on the strip and the last-shot card - NOT YET TABLET-VERIFIED

Base: 0.20.0.

**Safety status: no new write class, and Lumen still opens no database.** The
bag cycler reads through SDB's public API and writes through DYE's own
`::plugins::DYE::shots::source_next_from` - the same path Bean Scanner uses.
Lumen issues no SQL and holds no database handle. No file in `history/` or
`history_v2/` is read, written, renamed or deleted.

- Bag cycler on the NEXT SHOT label row, depth from `lumen_bag_count`. List:
  `::plugins::SDB::available_categories bean_desc 1 {} 0` (the trailing 0
  picks the `MAX(shot.clock) DESC` branch, the only one applying `removed=0`,
  and avoids the lookup branch's undefined `lookup_order_by`). Clock:
  `shots_using_category bean_desc <value> t.clock` - the `t.` works around an
  SDB "ambiguous column name" defect found on the tablet; `_bag_clocks` tries
  qualified then bare, returns {} rather than throwing. Apply:
  `source_next_from <clock> {} beans` (DYE expands the whole bean section).
- Arrows sit just after the label at x 150/196, NOT right-aligned (that touched
  the GRIND column at 320 and read as its controls); harness asserts >= md.
- RATIO's stepper became a read-only PROFILE tile; ratio is a derived caption
  inside the pill band. `act::adjust_ratio` deleted.
- LAST SHOT names the profile the shot ran on: `::lumen::last_shot_profile`
  latched on the espresso page's `show`, seeded from the newest `.shot` file
  into a LOCAL array (never `array set ::settings`).
- Grind tile resets on a bag/profile change via GA 3.7.0's
  `last_recommendation_is_current` (guarded for older builds). DYE tap starts
  below the arrows. Home re-baked (RATIO pills out, cycler pills in).

Files: skin.tcl, tools/make_backgrounds.py, tools/check_skin.tcl, home PNGs.

## 0.20.0 - every page baked; settings right column filled - TABLET-VERIFIED 2026-08-15

Base: 0.19.0.

**Safety status: one new setting, no new write class.**
`::settings(lumen_bag_count)` (3-10, default 5) is written only on an
explicit stepper tap and saved with plain `save_settings` - it is a skin
preference and deliberately never goes near `save_settings_to_de1`. No
database is opened; no file in `history/` or `history_v2/` is read, written,
renamed or deleted. Everything else in this version is display-only.

- Only `off` was baked; every other page fell through to the flat vector
  `glass`. `tools/make_home_bg.py` became `tools/make_backgrounds.py` with a
  `PAGES` table: `lumen_home`, `lumen_settings`, `lumen_flow_chart`
  (espresso), `lumen_flow` (steam/water/hotwaterrinse share one image). Home
  PNGs regenerate byte-identical (SHA256), proving the refactor safe.
- New token `C(chart_bg_flow)` (#171719 / #DEE1E4), separate from
  `C(chart_bg)`: the espresso chart panel sits at a different gradient height.
- Settings right column gains BAGS TO CYCLE (ships inert; the cycler is
  0.21.0) and GRIND ADVISOR (`open_settings_dialog`, guarded). THEME baked
  with the raised fill to match `build_settings`.
- Harness: settings-page budget check; every `baked_pages` entry must have an
  image for both themes at both resolutions.
- Verified on the tablet including all four flow pages (owner, 2026-08-15).

Files: skin.tcl, tools/make_backgrounds.py (renamed), tools/check_skin.tcl, PNGs.

## 0.19.0 - tap-rate acceleration on the grind / dose / yield steppers - TABLET-VERIFIED 2026-08-14

Base: 0.18.0.

**Safety status: no new settings and no new writes.** Same fields as 0.18.0,
same clamps; only the per-tap step size changed.

- Slow tap moves 0.1; taps within 700 ms of each other escalate to 0.5 after
  three and 1.0 after six; a pause or direction change resets to 0.1. RATIO
  and the settings-page machine steppers keep fixed increments.
- "Hold to repeat" is impossible: legacy canvas buttons fire once per press
  with no hold event, so the fast-tap ladder is the mechanism.

Files: skin.tcl.

## 0.18.0 - rail removed, next-shot steppers, steam heater labelled honestly - TABLET-VERIFIED 2026-08-14

Base: 0.17.0.

**Safety status: this version adds settings writes in two groups, each only
on an explicit tap and each clamped.**

- Next-shot steppers (home strip): `grinder_dose_weight` (Set dose, and the
  +/-0.5 dose stepper clamped 2..40), `grinder_setting` (grind stepper,
  0..100), `final_desired_shot_weight` / `final_desired_shot_weight_advanced`
  (yield and ratio steppers, 0..200; `_advanced` only for `settings_2c`
  profiles, mirroring DSx2's saw stepper). With DYE loaded its staged
  `next_grinder_setting` / `next_grinder_dose_weight` are kept in step (DYE's
  own `setup_DSx2.tcl change_grinder_setting` pairing).
- Machine steppers (Lumen settings page, mirroring Streamline):
  `espresso_temperature` (Brew +/-0.5 C, 70..110, via the core's
  `change_espresso_temperature`), `steam_timeout` + `steam_disabled` (Steam
  +/-5 s, 0..255, 0 = off), `flush_seconds` (Flush +/-1 s, 3..254),
  `water_volume` (Hot Water +/-10 ml, 10..250). Applied with `save_settings` +
  the core's `save_settings_to_de1`, debounced 1 s (Streamline's
  `save_profile_and_update_de1_soon` pattern); the profile file is NOT saved.
- Preferences: `lumen_theme`, `live_graph_smoothing_technique`, and the new
  `lumen_chart_stages` (Stages toggle). The Shot history button only opens
  ShotHistoryEditor; no database is opened and no history file is written,
  renamed or deleted by Lumen.
- Steam page "158 C" is the steam HEATER at its 160 set point (the same value
  every stock skin shows): relabelled STEAM HEATER with a `target 160 C` note.
- Action rail removed (the GHC covers it); tiles span 16..1324. Settings and
  Sleep survive in a side panel (never to be dropped - the skin would be a dead
  end). Streamline-style stepper groups for GRIND / DOSE / YIELD / RATIO on one
  even grid; bottom row: scale readout, Set dose, Scan bag, Edit.
- Shot history shortcut on the Last shot tile (`open_page
  ShotHistoryEditor_settings`); stage separators on the chart with a Stages
  pill; loaded-shot 0 s artifact fixed by slicing from the first positive
  elapsed value. Settings page is two columns (machine steppers left; THEME as
  plain glass and DECENT APP right). Home PNGs regenerated; chart_bg unchanged.

Files: skin.tcl, tools/make_home_bg.py, tools/check_skin.tcl, home PNGs.

## 0.17.0 - Curve opens from the grind tile - TABLET-VERIFIED 2026-08-02

Base: 0.16.0.

**Safety status: unchanged.** Still exactly three settings written, each only
on an explicit tap (`lumen_theme`, `live_graph_smoothing_technique`,
`grinder_dose_weight`). No database is opened and no file in `history/` or
`history_v2/` is written, renamed or deleted. The new control calls
GrindAdvisor's own read-only viewer and writes nothing.

- A Curve control on the grind tile's bottom row opens GrindAdvisor's
  Calibration Curve via its public `show_calibration_curve` (v3.3.0+); on an
  older plugin `::lumen::act::grind_curve` logs a NOTICE and falls back to the
  result popup.
- The tile's single tap is carved into three rectangles around Curve (A above
  the bottom row, B left, C right; Curve 506..596 x 190..252), contiguous and
  non-overlapping, all still opening the result popup.

Files: skin.tcl.

## 0.16.0 - method chip shows the first two shots; scale readout reconnects

Base: 0.15.0.

**Safety status: no new write behaviour.** Still exactly three settings
written, each only on an explicit tap (`lumen_theme`,
`live_graph_smoothing_technique`, `grinder_dose_weight`). No database is
opened and no file in `history/` or `history_v2/` is written, renamed or
deleted. The scale reconnect calls the app's own `ble_connect_to_scale` and
resets one in-memory `::de1()` counter - nothing is persisted.

- The method chip was blank for the first two shots of a bag: only 2 of
  GrindAdvisor v3's 4 ladder rungs were mapped. Now First shot / 2-shot /
  Regression / Pairwise; an unknown rung shows verbatim (16 chars).
- The scale readout is a tap target that forces a reconnect
  (`::lumen::act::reconnect_scale`, copied from Insight: clear
  `bluetooth_scale_connection_attempts_tried`, then `ble_connect_to_scale`).
  Core cause, read from `de1_comms.tcl:587` / `bluetooth.tcl:1880`: after 20
  failed attempts the core resets its counter and never retries. The readout
  now distinguishes `no scale` / `Connecting` / `Connect`.

Files: skin.tcl.

## 0.15.0 - Done restarts the app when the theme changed

Base: 0.14.1.

**Safety status: unchanged.** Still exactly three settings written, each only
on an explicit tap (`lumen_theme`, `live_graph_smoothing_technique`,
`grinder_dose_weight`). No database is opened and no file in `history/` or
`history_v2/` is written, renamed or deleted. The restart path adds one
`save_settings` - the same call the toggle already made - and no new write.

- `::lumen::act::restart_for_theme` copies the app's restart-on-skin-change
  sequence verbatim (`skins/default/de1_skin_settings.tcl:65-71`): message
  page, `set_next_page off message`, `page_show message`, `after 200
  app_exit`. Tablet-verified: the theme switches and the app quits.
- The app cannot reopen itself (measured on Android 16): `am start` from the
  app's uid throws a SecurityException; `borg activity` starts inside the
  dying process. You relaunch by hand; no custom exit machinery written.
- `close_settings` restarts only when `pending_theme` differs from the loaded
  `theme_mode`; `theme_note` says the app will restart.

Files: skin.tcl.

## 0.13.0 - the last shot loads at startup

Base: 0.12.4.

**Safety status: unchanged.** Three settings written, each only on an
explicit tap (`live_graph_smoothing_technique`, `lumen_theme`,
`grinder_dose_weight`). This version adds a **read** of one history file and
writes nothing.

- `::lumen::load_last_shot_curves` finds the newest `history/*.shot`, reads
  it and fills the chart vectors, deferred 5 s after load (the BLT vectors are
  created during app setup); skips if a shot is running. Tablet-verified.
- `espresso_weight_chartable` and `espresso_temperature_basket10th` are
  derived (0.10 x weight, temperature / 10) because the app does not store
  the scaled forms.
- Trap avoided: `preview_history` also does `array set ::settings
  $props(settings)`, which would replace the live configuration on every
  launch. Only the vector half was taken; the test asserts `::settings` is
  untouched.

Files: skin.tcl.

## 0.12.4 - long bean names no longer wrap into the line below

Base: 0.12.3.

**Safety status: unchanged (display only).**

- The brand at 40 px in a 272 px column with `-width` wrapped onto the
  type/roast line beneath. Truncated to 13 characters.
- Auto-scaling the font was rejected: a canvas item's font is fixed at
  creation, and a name rendering at a different size each session breaks the
  fixed type scale.

Files: skin.tcl.

## 0.12.3 - chart panel flat and padded, scale readout centred

Base: 0.12.2.

**Safety status: unchanged (display only).**

- Chart panel rendered flat (new per-panel `flat` flag in the generator): a
  BLT graph is an opaque widget with one background colour, so a gradient
  panel showed it as a box. `chart_bg` re-sampled #141517 dark / #DDE0E4
  light.
- `plotpadx 18 / plotpady 8` on both charts so the outermost tick label is
  not clipped. Scale readout text centred on its box.
- `::lumen::version` corrected to match the archive (0.12.1 and 0.12.2 had
  bumped the header and archive name but not the constant).

Files: skin.tcl, tools/make_home_bg.py, home PNGs.

## 0.6.0 - Pass 3b: depth

Base: 0.5.1.

**Safety status: unchanged** - one setting written
(`live_graph_smoothing_technique`), no database, no history files.

- Depth cues built from stacked solid shapes in interpolated colours (Tk
  canvas has neither gradients nor alpha), drawn once at page build:
  `::lumen::mix`, `::lumen::paint_backdrop` (32-band vertical wash plus a
  crema bloom of 14 ovals), soft drop shadows (four concentric rounded rects)
  on every glass panel; palette tokens `bg_top`, `bg_bot`, `shadow`, `bloom`.
- Deliberately not done: a gradient inside each panel (no clipping in Tk
  canvas). Later reverted in favour of the baked PNG background.
- Fixed: the shot timer flashed a colossal number on the first tick
  (`espresso_start` unset); all four flow pages guard 0..3600 s and show `0s`.

Files: skin.tcl.

## 0.5.1 - Empty-chart state

Base: 0.5.0.

**Safety status: unchanged (display only).**

- "No shot data yet - pull a shot" centred in the chart panel, blanking once
  data arrives (threshold `length > 1` because the app appends a leading 0 at
  shot start); an empty BLT graph otherwise autoscales to -0.1..0.1 and reads
  as broken.
- x-axis pinned to `-min 0`.

Files: skin.tcl.

## 0.5.0 - Pass 3: the shot chart

Base: 0.4.1.

**Safety status: this version writes exactly one value** -
`::settings(live_graph_smoothing_technique)`, a stock DE1app display
preference, and only when you tap the toggle. No database is opened and no
`history/` or `history_v2/` file is read, written, renamed or deleted.
Earlier versions wrote nothing at all; this is the change.

- Shot chart on the home panel: pressure, flow, cumulative weight and basket
  temperature, a BLT/RBC `graph` bound to the app's live vectors (element
  pattern from Streamline). Raw / Smooth toggle flips
  `live_graph_smoothing_technique` between `linear` and `catrom`, reconfigures
  the existing elements and saves the preference.
- All four series share one 0..10 y axis, so the app's pre-scaled vectors
  (`espresso_temperature_basket10th`, `espresso_weight_chartable`) are used.
  Line widths are physical pixels (a Tk widget, not a canvas item); the
  widget is created via `dui add graph` with virtual `-width`/`-height`;
  `-tclcode` uses `%W`. Goal lines deliberately not drawn.
- Known gap: chart on the home screen only; the flow pages get theirs later.

Files: skin.tcl.

## 0.4.1 - Scan bag goes straight to the camera again

Base: 0.4.0.

**Safety status: no write behavior exists in this version.**

- Root cause of the 0.4.0 dead end: BeanScanner's `_settings_return_page` is
  declared with `variable` inside procs but never initialised at namespace
  level, and `_exit_settings` reads it without a catch, so entering at a
  sub-page made Done throw "no such variable" and do nothing.
- Scan bag jumps to `BeanScanner_capture` again, seeding
  `_settings_return_page` first with the page it came from. Guarded and
  logged; verified with the plugin absent and present.
- Known limitation: Cancel from the camera lands on Bean Scanner's own page
  (two taps out) because `_exit_subpage` is hardcoded; fixing that is a
  BeanScanner pass.

Files: skin.tcl.

## 0.4.0 - Flow pages, and fixes from the first tablet test

Base: 0.3.0.

**Safety status: no write behavior exists in this version.** No database is
opened, no `history/` or `history_v2/` file is read or written, and no
`::settings` value is modified.

- First version run on the tablet: both scale sources confirmed right, panels
  fill the screen, Inter legible.
- Added the flow pages (espresso / steam / water / flush were blank black):
  machine state, a large elapsed timer, a glass panel of live pressure / flow
  / weight / temperature, "Tap anywhere to stop"; flush gets a tap-to-stop
  button (deliberate deviation from the stock skin).
- Fixed: bold text was not bold (`Inter-Bold.ttf` registered under the same
  family name as Regular; the loader now asks Tk for the weight explicitly
  when two faces collide); grind tile reason text overlapped the confidence
  row (summary before the first parenthesis, 88 chars); Bean Scanner trapped
  the user (entry via `BeanScanner_settings`); last shot time read `0.0`
  instead of `--`.
- Harness extended to the flow pages using the tablet's exact font family
  names; it caught a self-inflicted `last_time` regression.

Files: skin.tcl, tools/check_skin.tcl.

## 0.3.0 - Pass 2: live plugin data

Base: 0.2.0.

**Safety status: no write behavior exists in this version.** No database is
opened, no `history/` or `history_v2/` file is read or written, and no
`::settings` value is modified - the skin reads globals and draws. It hands
off to GrindAdvisor's result popup, DYE's next-shot editor and Bean Scanner's
capture page; any writing those perform is their own, behind their own
confirmation.

- `::lumen::data` accessors (failure-tolerant), `::lumen::act` guarded plugin
  entry points, `::lumen::var` / `::lumen::tap` helpers.
- Grind tile (recommendation, delta, method, confidence, reason; tap opens
  GrindAdvisor's popup), Last shot tile (dose, yield, time, ratio), Bean strip
  (bag identity, grind, dose, yield, ratio, live scale, Scan bag / Edit).
- Values go through `dui add variable` on the 200 ms tick, current page only;
  no accessor touches the filesystem (GrindAdvisor's in-memory
  `last_recommendation` is read directly, never the loader).
- Sources: GrindAdvisor `last_recommendation`; the same `::settings` fields
  `shot.tcl` writes; DYE `next_*` with core fallback; `::de1(scale_weight)`.
- File made pure ASCII. Verified under `tclsh` in cold, populated and hostile
  states; 14 tap targets, none intersecting.

Files: skin.tcl, tools/check_skin.tcl.

## 0.2.0 - Inter typography

Base: 0.1.0.

**Safety status: no write behavior exists in this version.** No database is
opened, no `history/` or `history_v2/` file is read or written, and no
`::settings` value is modified. The skin only draws.

- `fonts/`: Inter Regular / SemiBold / Bold for UI text, NotoSansMono
  SemiBold / ExtraBold for numbers (both proven on this tablet by DSx2 and
  Streamline). New `font_data` role (mono, 26 px) for tabular values.
- `::lumen::_load_font_families` resolves each TTF to a family name via
  `::dui::font::add_or_get_familyname`, with Helvetica/Courier fallback.
- Why not `load_font`: it computes `int(fontm * size)` in points and this
  tablet's `default_font_calibration` is 0.5, so 19 would become 9 pt. Lumen
  takes only the family name and creates fonts at negative pixel sizes with a
  16 px floor; weight comes from the file, `-weight bold` only on the fallback.

Files: skin.tcl, fonts/.

## 0.1.0 - Pass 1: skeleton and static home page

First version.

**Safety status: no write behavior exists in this version.** No database is
opened, no `history/` or `history_v2/` file is read or written, and no
`::settings` value is modified. The skin only draws.

- `skin.tcl`, the whole skin in one file: dark and light palettes
  pre-composited by hand (mode from `::settings(lumen_theme)`, default dark);
  layout token block `_init_layout` in 1340x800 design px with `X`/`Y`
  converting to the 2560x1600 virtual canvas by separate factors (1.9104 /
  2.0); `LUMEN_*` fonts at negative pixel sizes with a 16 px floor;
  `::lumen::glass` rounded panel (mechanism from GrindAdvisor's
  `rounded_rect`).
- Home page: action rail (Espresso, Steam, Water, Flush, Settings, Sleep),
  grind tile, last shot tile, chart panel, next-shot bean strip. Pages
  declared with `-bg_color`, no image assets.
- `standard_stop_buttons.tcl` deliberately not sourced (its stop bindings are
  reproduced verbatim); `standard_includes.tcl` is sourced so the stock
  settings, firmware, descale and profile pages keep working (DSx2's approach).
- Known limitations: placeholder values, empty chart frame, flat background,
  untested on the tablet.

Files: skin.tcl.
