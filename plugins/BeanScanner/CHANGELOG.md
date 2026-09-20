# Bean Scanner - Changelog

Entries follow the CLAUDE.md doc cap (about 15 lines each; entries that
added or changed a write capability keep their full write-path text). The
long pre-trim entries survive in the Desktop "BeanScanner Archive" snapshot
of each version.

## v0.9.13 - preview refresh reverted to the classic poll

Base: v0.9.12.

* At the owner's call ("still laggy"), the frame-driven preview (v0.9.0's
  `<<ImageCapture>>` path, adaptive throttle, `preview_min_ms`,
  frame/grab state) is fully removed. The preview polls one frame per
  `preview_poll_ms` (150 ms, ~7 fps) exactly as v0.8.x did: each grab costs
  30-50 ms of UI-thread time on this tablet, so a steady ~7 fps with a
  responsive UI wins. All other v0.9.x gains (full-bleed sharp preview,
  size selection, clean camera automatics, flip/flash) are kept.
* Harness verify_bsc_v0913.tcl, 248 checks.

**Safety status: no change to data behavior.** The only data write remains
the DYE next-shot update after you press Accept. No SQL, no history files,
no direct `::settings` writes. `preview_min_ms` is removed.

Files: plugin.tcl, BeanScanner.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.9.12 - the freeze saga closes (v0.9.1 -> v0.9.12)

Base: v0.9.11 (test-tablet only).

* v0.9.1-v0.9.11 chased a once-a-second preview freeze through every
  Camera1 parameter (fps ranges, focus modes, scene modes, antibanding,
  stabilization, focus/metering areas), each dump-verified as applied,
  none curative. The clean baseline (v0.9.11: zero parameter writes) still
  froze. Verdict: **the stall is the tablet camera firmware's own behavior
  when a bright light source dominates the frame in a dark room.** Both
  cameras, below anything Camera1/AndroWish can reach, never on a lit bag,
  never in captured photos. Documented in README and Help.
* Kept: frame-driven preview with a bounded adaptive throttle (3x measured
  grab cost, capped 250 ms); factory automatics untouched - the plugin sets
  only preview/capture sizes and the flash.
* v0.9.6-v0.9.11 were diagnostic iterations pushed only to the test
  tablet; their details live in the archive snapshots. Harness 256 checks.

**Safety status: no change to data behavior.** The only data write remains
the DYE next-shot update after you press Accept. No SQL, no history files,
no direct `::settings` writes. All temporary diagnostics (`camera_debug
.txt`, on-screen frame stats) are removed; `capture_focus_ms` and the
unused stat state are gone.

Files: plugin.tcl, BeanScanner.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.9.5 - back-camera freeze: it was the exotic preview mode

Base: v0.9.4.

* The v0.9.4 experiment showed the freeze persisted with the lens parked,
  so autofocus was innocent. The remaining difference from the smooth
  front camera was the preview mode: the back ran the screen-exact
  1340x800 (width not 8-pixel aligned). Preview-size selection now prefers
  hardware-aligned modes (both dimensions divisible by 8), landing the
  back camera on 1600x960.
* Park-and-scan focus reverted: continuous-video CAF again, instant
  capture. Harness verify_bsc_v095.tcl, 257 checks.

**Safety status: no change to data behavior.** The only data write remains
the DYE next-shot update after you press Accept. No SQL, no history files,
no direct `::settings` writes. `capture_focus_ms` (added in v0.9.4) is
removed again.

Files: plugin.tcl, BeanScanner.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.9.4 - back-camera freeze, endgame: park-and-scan focus

Base: v0.9.3.

* v0.9.3's resets all applied yet the freeze survived; suspect by
  elimination: the continuous-AF re-scan cycle. AndroWish has no manual
  focus trigger, so the plugin parks focus ("auto") during the preview
  and does one scan at capture: switch to continuous-picture, show
  "Focusing...", wait `capture_focus_ms`, shoot, re-park. Trade-off: soft
  live preview up close; captures are the sharp ones.
* Harness verify_bsc_v094.tcl, 259 checks.

**Safety status: no change to data behavior.** The only data write remains
the DYE next-shot update after you press Accept. No SQL, no history files,
no direct `::settings` writes. New settings key: `capture_focus_ms`
(focus-lock wait before a back-camera shot, default 900 ms).

Files: plugin.tcl, BeanScanner.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.9.3 - back-camera freeze, round two

Base: v0.9.2.

* The v0.9.2 focus-mode change applied but the freeze survived. The full
  parameter dump revealed two anomalies the plugin never set, normalized
  right after the preview starts: `video-stabilization` forced on although
  reported unsupported (switched off); `focus-areas`/`metering-areas`
  carried a custom box (reset to `(0,0,0,0,0)`).
* Learned: camera 0 = back with AF, camera 1 = front, fixed focus.
  Harness verify_bsc_v093.tcl, 255 checks.

**Safety status: no change to data behavior.** The only data write remains
the DYE next-shot update after you press Accept. No SQL, no history files,
no direct `::settings` writes. The `camera_debug.txt` diagnostic stays
until the freeze is confirmed gone.

Files: plugin.tcl, BeanScanner.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.9.2 - no more once-a-second preview freezes

Base: v0.9.1.

* The back camera froze for a beat every second. Diagnosis (inferred):
  continuous-picture autofocus pauses the preview during every refocus
  scan; the fixed-focus front never does. When supported, focus mode is
  switched to `continuous-video` (logged; rejection non-fatal).
* Harness verify_bsc_v092.tcl, 252 checks.

**Safety status: no change to data behavior.** The only data write remains
the DYE next-shot update after you press Accept. No SQL, no history files,
no direct `::settings` writes. The temporary `camera_debug.txt`
diagnostic returns (plugin folder only, never shipped) until the freeze
diagnosis is confirmed on-device.

Files: plugin.tcl, BeanScanner.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.9.1 - the back camera no longer crawls in dim light

Base: v0.9.0.

* Back camera preview ran at ~1 fps: Camera1 defaults to a variable
  fps range and dim scenes ride its floor. The plugin now pins an explicit
  `preview-fps-range` from the camera's own list - floor >= 15 fps with
  the most exposure headroom (15-20 fps on the Tab A9 back camera).
  Logged; rejection non-fatal. Trade-off: darker rather than slower
  previews in dim light; stills keep their own exposure.
* Harness verify_bsc_v091.tcl, 250 checks.

**Safety status: no change to data behavior.** The only data write remains
the DYE next-shot update after you press Accept. No SQL, no history files,
no direct `::settings` writes. No settings changes.

Files: plugin.tcl, BeanScanner.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.9.0 - smooth preview (frame-driven, up to ~25 fps)

Base: v0.8.4.

* The preview updates at the camera's own frame rate: AndroWish fires
  `<<ImageCapture>>` per ready frame; the plugin binds it once and
  refreshes per frame, throttled by `preview_min_ms` (default 40 ms).
  The old poll loop remains as a watchdog (polls only after 1 s without
  a frame event; keeps the fetch-within-5-seconds rule satisfied).
* Dump findings: back camera offers a native 1340x800 preview, 30 fps,
  picture 2560x1920, no flash-mode-values. Harness 244 checks.

**Safety status: no change to data behavior.** The only data write remains
the DYE next-shot update after you press Accept. No SQL, no history files,
no direct `::settings` writes. New settings key: `preview_min_ms`
(frame throttle, default 40 ms ~ 25 fps). The temporary v0.8.4
`camera_debug.txt` diagnostic is removed - it answered its question.

Files: plugin.tcl, BeanScanner.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.8.4 - clean camera flips

Base: v0.8.3.

* Flipping cameras left garbage on screen: one Tk photo was reused across
  cameras, shrank in place, and the canvas never repainted the vacated
  area. Every camera (re)start now deletes and recreates the photos.
* Display maths use the preview size the camera actually accepted (read
  back after setting), so a silently rejected size cannot break layout.
* Harness verify_bsc_v084.tcl, 236 checks (plugin_dir redirected so the
  debug file never lands in the real plugin folder during tests).

**Safety status: no change to data behavior.** The only data write remains
the DYE next-shot update after you press Accept. No SQL, no history files,
no direct `::settings` writes. One temporary diagnostic file is written:
`camera_debug.txt` inside the plugin's own folder (the last-opened
camera's full Camera.Parameters list, overwritten on every camera open;
never shipped, to be removed once the back-camera preview question is
settled).

Files: plugin.tcl, BeanScanner.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.8.3 - sharp full-screen preview, higher-res captures

Base: v0.8.2.

* The preview was pixelated: Tk's `image copy -zoom -subsample` drops
  pixels before enlarging, collapsing 640x480 to an effective 160x120.
  Fractional scaling is gone: the plugin asks for the smallest preview
  size that COVERS the screen and shows it 1:1, centre-cropped. Integer
  x2 zoom remains only for cameras that report no size list.
* Captures are validated against `picture-size-values`: smallest supported
  size >= the setting (or the camera's largest), logged. Harness 233 checks.

**Safety status: no change to data behavior.** The only data write remains
the DYE next-shot update after you press Accept. No SQL, no history files,
no direct `::settings` writes. Settings: the shipped `capture_size`
default rises to 1600x1200, and an install still on the old 1280x960
default is lifted once (any other explicit choice is kept).

Files: plugin.tcl, BeanScanner.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.8.2 - capsule pills, borderless preview

Base: v0.8.1.

* No black border: the display copy uses the smallest zoom/subsample
  ratio that covers the screen (9/8 for 1280x720), overflow clipped -
  aspect-fill. Captured JPEGs unaffected.
* True capsules: dui round dbutton corner circles have diameter = radius
  argument, and the smooth-polygon helper renders ~half its radius; the
  Send pill passes a height-sized radius and the status pill is built
  from two end ovals plus a rect. Smaller, centred paper plane.
* Harness verify_bsc_v082.tcl, 227 checks.

**Safety status: no change to data behavior.** The only data write remains
the DYE next-shot update after you press Accept. No SQL, no history files,
no direct `::settings` writes. No settings changes.

Files: plugin.tcl, BeanScanner.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.8.1 - match the approved mock exactly

Base: v0.8.0.

* The preview really fills the screen: v0.8.0 read a non-existent key
  (`preview-sizes`); Camera1 publishes `preview-size-values`. Both keys
  read, choice logged; with only a small preview available the on-screen
  copy is integer-zoomed 2x.
* Send pill carries the dark count badge (left, shown once a photo exists)
  and a paper-plane icon (right); taps on both go to Send. Flip icon is
  the plain two-arrow loop; status pill slimmer; flip circle moved out.
* Harness verify_bsc_v081.tcl, 222 checks.

**Safety status: no change to data behavior.** The only data write remains
the DYE next-shot update after you press Accept. No SQL, no history files,
no direct `::settings` writes. No settings changes.

Files: plugin.tcl, BeanScanner.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.8.0 - full-screen camera redesign

Base: v0.7.0.

* The capture page is a camera app: full-screen preview on black (largest
  preview size fitting the physical screen), circular shutter, flip
  circle, lightning flash icon top-right with off/on/auto states (auto
  only where the camera has a real auto mode; dimmed = no flash), Send
  pill with count bottom-left, trash Clear circle, X Cancel top-left,
  status in a dark pill top-centre.
* The screen flash never fires on the back camera; hardware flash "on" is
  a steady torch, "auto" the camera's own. Fixed dark chrome in both
  themes, excluded from the light/dark repaint. Icons from the app's Font
  Awesome font with text stand-ins. Harness verify_bsc_v080.tcl, 208 checks.

**Safety status: no change to data behavior.** The only data write remains
the DYE next-shot update after you press Accept. No SQL, no `history/` or
`history_v2/` access, no direct `::settings` writes. Settings change:
`flash_mode` (off/on/auto) replaces the boolean `flash_enabled`, migrated
automatically (enabled -> on).

Files: plugin.tcl, BeanScanner.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.7.0 - camera flip on the capture page

Base: v0.6.0.

* A Front Cam / Back Cam button on the capture page flips the camera in
  place: the camera restarts, the new camera's flash hardware is
  re-detected (torch vs screen flash switches by itself), photos already
  taken are kept with the count. A flip during a pending screen flash
  cancels it cleanly (brightness restored, no late capture). The choice
  persists and stays in sync with the settings page's Camera row.
* Harness verify_bsc_v070.tcl, 187 checks.

**Safety status: no change to data behavior.** The only data write remains
the DYE next-shot update after you press Accept. No SQL, no `history/` or
`history_v2/` access, no direct `::settings` writes. No new settings keys -
the flip reuses `camera_pref`, shared with the settings page.

Files: plugin.tcl, BeanScanner.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.6.0 - multi-photo scans and a flash

Base: v0.5.0.

* Multiple photos per scan: each Capture adds a photo (preview resumes),
  Send ships all of them as one request, Clear drops them; up to 6
  (`max_photos`). The pending set (runtime-only) survives a network error
  and is cleared on success, Cancel, and every fresh capture-page entry.
* Flash toggle (persists): back camera = steady torch via `flash-mode`;
  front camera = full-screen white plus max brightness for
  `screen_flash_ms` (600 ms), restored on every path incl. flush/rinse
  interruption. Diagnostics reports flash setting and modes.
* Over-sized photos are rejected without aborting the scan. Harness 166
  checks.

**Safety status: no change to data behavior.** The only data write remains
the DYE next-shot update after you press Accept. No SQL, no `history/` or
`history_v2/` access, no direct `::settings` writes. New settings keys:
`flash_enabled`, `max_photos`, `screen_flash_ms`.

Files: plugin.tcl, BeanScanner.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.5.0 - dark mode

Base: v0.4.2.

* Sun/moon toggle top-right of the settings page switches all six pages
  between light and dark instantly; persists across restarts.
* Three theme modes: "" keeps the pre-v0.5.0 look (stock light, adopting
  the active skin's palette when published, e.g. Lumen); "light"/"dark"
  override adoption. The toggle direction follows the effective look
  (background luminance).
* Every colour token lives in `_apply_palette` (harness enforces no
  literal elsewhere); buttons and labels retheme live. Harness 66 checks.

**Safety status: no change to data behavior.** The only data write remains
the DYE next-shot update after you press Accept. The one new settings key
is `theme`, saved when you tap the new toggle.

Files: plugin.tcl, BeanScanner.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.4.2 - repository renamed

Base: v0.4.1.

* The GitHub repository was renamed from `Blastize/BeanScanner` to
  `Blastize/de1app-plugin-BeanScanner`; README clone URL and plugin.tcl
  `contact` URL updated. GitHub redirects the old URLs.

**Safety status: no change.** No code behavior changed in this version. The
only write remains the DYE next-shot update after you press Accept. No
database, no history files.

Files: plugin.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.4.1 - the longest capture size no longer wraps

Base: v0.4.0.

* "Capture size" wrapped at `2048x1536` and collided with the row below:
  the value column (after label column and button) was ~121 physical px,
  the longest value needs ~120. `sec_label_w` 220 -> 180 gives ~163 px.
* Tablet-verified: v0.4.1 renders on one line; v0.4.0's palette adoption
  confirmed on real hardware; v0.3.0's deep link confirmed via Lumen's
  "Scan bag" button. All three navigation routes exercised and the
  `_entered_at_subpage` flag does not leak: deep link + Cancel -> Lumen
  home; settings -> Scan -> Cancel -> plugin settings; settings + Done ->
  Extensions dialog.

**Safety status: no change.** The only write remains the DYE next-shot
update after you press Accept. No database, no history files.

Files: plugin.tcl, BeanScanner.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.4.0 - adopts the active skin's palette

Base: v0.3.0.

* `_adopt_skin_palette`, called at the end of layout init, maps a skin's
  published colour array onto the plugin's tokens so every page follows
  the skin. Only `::lumen::C` is recognised; the contract is a plain array
  of `#RRGGBB` values with keys `bg glass glass_2 glass_brd ink ink_3
  crema warn`, so other skins can opt in.
* Defensive: each token is overwritten only when the skin provides a valid
  value (no skin / partial palette -> stock look / partial adoption). The
  plugin still paints its own page background. Text tokens come from the
  skin's panel inks, since body text sits on cards.
* Verified under tclsh (four palette states); not tablet-tested until v0.4.1.

**Safety status: no change.** The only write remains the DYE next-shot
update after you press Accept. No database, no history files.

Files: plugin.tcl, BeanScanner.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.3.0 - sub-pages can return where you came from

Base: v0.2.0.

* Fixed a dead Done button when the plugin was entered at a sub-page (as
  Lumen's "Scan bag" does): `_settings_return_page` and
  `_entered_at_subpage` now have namespace-level defaults, so
  `_exit_settings` can no longer throw on an unset variable.
* Added `::plugins::BeanScanner::set_return_page <page>` for deep-link
  callers; refuses empty, transient and BeanScanner_* pages (returns 0).
  `_exit_subpage` returns to that page when entered at a sub-page; the
  settings page clears the flag in its own `show`.
* Six navigation scenarios verified under tclsh; not tablet-tested until
  v0.4.1.

**Safety status: no change.** The only write remains the DYE next-shot
update after you press Accept. No database, no history files.

Files: plugin.tcl, BeanScanner.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.2.0 - 2026-07-25 (write semantics changed - read this entry)

Base: v0.1.3.

**Safety status: the write path is unchanged in scope - still only
`::plugins::DYE::shots::source_next_from`, still only from the review page's
Accept button, still no SQL and no `history/` access. What changed is *what*
that write contains: with "Overwrite existing" on, an enabled field the bag
does not state is now written as EMPTY instead of being skipped.**

### Fixed

* **A blank field kept the previous bag's value.** Reported from the first
  real end-to-end scan: a bag with no roaster name printed on it inherited
  the previous bag's roaster, so the next shot recorded the new bean under
  the old roaster - a bag that never existed, saved into shot history.
  A scan describes one bag, so with "Overwrite existing" on every enabled
  field is now written, blanks included. Verified against DYE first:
  `source_next_from` assigns `settings(next_$field)` and `::settings($field)`
  unconditionally (`plugins/DYE/DYE.tcl:1615`), and its zero-coercion special
  case applies only to `number` fields - all five bean fields are
  category/text/long_text, so an empty value genuinely clears rather than
  being dropped or turned into 0.
  With "Overwrite existing" **off** the intent is the opposite (fill only
  what is blank), so nothing is ever cleared in that mode.

### Added

* **Guard against a destructive no-op:** if the scan recognized nothing at
  all, no write happens and the user is told to retake the photo - a failed
  read can never wipe the next-shot description.
* **The review page shows what will be cleared.** Each blank field that
  currently holds a value is marked "- will be cleared" in a warning colour,
  and the subtitle states which mode is active. Accept never clears anything
  silently. The applied-fields log line names the cleared fields.

Files: plugin.tcl, BeanScanner.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.1.3 - 2026-07-25 (tablet-verified)

Base: v0.1.2.

* Capture page: status text overlapped the preview (a Tk photo whose
  physical height is unknown at layout time, so nothing below it is
  safe). Status now sits above the preview, in the toolbar band.
* Diagnostics: dead space between title and body removed.
* Tablet-verified: plugin loads and `main()` runs clean; Diagnostics
  reports `numcameras: 2`, CAMERA declared and granted, DYE loaded; the
  capture page opens a live front-camera preview; leaving the page
  releases the camera. Not yet exercised end to end at this version.

**Safety status: no write behavior exists beyond the DYE next-shot update
behind Accept**, unchanged.

Files: plugin.tcl, BeanScanner.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.1.2 - 2026-07-25 (the button-render bugfix)

Base: v0.1.1.

* No button had a background and card labels were invisible. Root cause
  (found by instrumenting the running app): `dui aspect set` writes into
  the CURRENT theme, which the skin has switched to `DSx2` by the time
  `preload` runs, while the pages are created with `-theme default`;
  aspect lookup never falls back toward a named theme, so the `bsc_btn`
  style was never found. Fix: `dui aspect set -theme default`.
* The page background is now painted by the plugin (`_page_bg`), so
  contrast is deterministic on any skin; all colours route through tokens.

**Safety status: no change** - no write behavior added or altered; the only
write remains the DYE next-shot update behind the review page's Accept.

Files: plugin.tcl, BeanScanner.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.1.1 - 2026-07-25 (first tablet run: visual fixes)

Base: v0.1.0.

* Invisible buttons: a custom style defining only `shape`/`radius`
  resolves fill to empty (`de1app-core/dui.tcl:10070`), not to
  `default.dbutton.fill`. `bsc_btn` now sets `fill`, `disabledfill` and a
  `dbutton_label` fill explicitly.
* Near-invisible text on the dark fpdialog background: explicit colour
  tokens (`fg_title/fg_body/fg_muted`, `on_card_title/label/value`)
  introduced and every item routed through them.
* Wrapped value text: button-less rows now span to the card edge.

**Safety status: no write behavior was added or altered in this version** -
the only write remains the DYE next-shot update behind the review page's
Accept button.

Files: plugin.tcl, BeanScanner.tcl, README.md, CHANGELOG.md, PROJECT_STATE.md.

## v0.1.0 - 2026-07-25 (superseded by v0.1.1)

First version. Camera capture, AI vision recognition, review page, and a
confirmed write into DYE's next shot.

**Safety status:** the only write this version performs is
`::plugins::DYE::shots::source_next_from`, reached solely from the review
page's Accept button. There is no SQL of any kind, no `history/` or
`history_v2/` access, no direct `::settings` write, and no raw sensor data is
read or displayed. The plugin writes one file only if the user types an API
key into the settings page (the framework's own plugin settings store).

### Added

* **Camera capture** via AndroWish `borg camera` - open / start / live
  preview polled into a Tk photo / `takejpeg` + `jpeg` byte retrieval, with
  configurable preview and capture resolution and a front/back/auto camera
  preference (front by default).
* **Import fallback** - "Use Latest Photo" picks the newest JPEG from
  `/sdcard/DCIM/Camera` (read only), for builds without the CAMERA permission.
* **Two switchable vision providers** - Anthropic Messages API (base64
  image block) and OpenAI Chat Completions (`image_url` data URI), each
  with its own model id and API key.
* **Asynchronous HTTPS** - `http::geturl -command` over TLS 1.2 so the UI
  never freezes during upload.
* **Strict JSON extraction** - the prompt forbids guessing and requires
  `null` for anything not legible; the parser strips fences and prose,
  tolerates a leading thinking block, and maps null-ish values to empty.
* **Review page** - shows roaster, beans, roast date, roast level and
  composed notes before anything is written. Accept / Rescan / Cancel.
* **DYE integration (the write path)** - builds on
  `::plugins::DYE::shots::get_next`, sets `clock` to 0 (DYE compares it
  numerically and `get_next` leaves it empty), and calls
  `source_next_from` with only enabled, non-empty fields (`bean_brand`,
  `bean_type`, `roast_date`, `roast_level`, `bean_notes`); DYE then sets
  its `next_<field>` settings and `::settings(<field>)`, saves, and
  refreshes the next-shot description. With "Overwrite existing" off,
  already-filled next-shot fields are left alone.
* **API key from file** - `api_key_anthropic.txt` / `api_key_openai.txt`
  next to the plugin (read only, never shipped).
* **Diagnostics page** - camera probe (`numcameras`, `state`, CAMERA
  permission declared/granted), provider / model / key source, DYE
  availability, last capture size, last HTTP result, last error, truncated
  last raw response. **Help page** covering setup and capture technique.

### Notes

* Navigation uses the app's own mechanism: the true return page is captured
  in each page's `show{}`, transient and own pages are skipped, Done loads a
  verified registered page or falls back to `dui page close_dialog`;
  failures are logged via `msg`, never swallowed.
* The capture page's `hide{}` always releases the camera, so a flush /
  rinse / steam interruption cannot leave it held.
* No output-token cap is sent to OpenAI (parameter name differs across
  model generations; the expected reply is a short JSON object).

Files: plugin.tcl, BeanScanner.tcl, filelist.txt, README.md, CHANGELOG.md,
PROJECT_STATE.md.
