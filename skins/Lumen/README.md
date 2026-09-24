# Lumen

**A glass dashboard home screen for the Decent DE1: grind recommendation, last shot, shot graph and next-shot beans, without opening Settings.**
Version 0.57.5 · a skin for the Decent DE1app · by Blastize

![The Lumen home screen in a custom theme: grind tile, last shot, live graph, next-shot strip, and the taskbar with three favorite profile names, the loaded one glowing](docs/home_custom_theme.png)

**Home.** The recommended grind and how sure it is, the last shot, the shot graph, and the bean, grind, dose and yield for the next shot. The three profile names on the taskbar are favorite slots: one tap loads the profile, and the loaded one glows.

![The default dark theme home screen](docs/screenshot.png)

**Dark, the default.** Light, the presets and your own colours are behind the THEME row's Change button.

![Grind Advisor's after-shot popup on Lumen's glass, in the theme's colours](docs/glass_popup.png)

**Glass popups.** Grind Advisor's Shot analysis and Calibration Curve float on frosted glass over the live page, in your theme's own colours.

![The custom theme picker: base, backdrop and accent swatches, presets and a live preview](docs/theme_picker.png)

**Your own colours.** Dark or light base, a backdrop tint and an accent, six presets, and a preview painted from the home page itself. Every page switches at once.

![The settings page: brew, steam, flush, hot water, theme, bags to cycle, clock and low water](docs/settings.png)

**Settings.** Brew temperature, steam, flush, hot water, theme, how many recent bags the home strip cycles through, clock format, low-water warning.

![The home screen on a light custom theme: warm cream page, blue accent](docs/home_light_custom.png)

**Light, in your colours.** The same home on a light base with a warm backdrop and a blue accent.

![Grind Advisor's popup on the light theme's glass](docs/glass_popup_light.png)

**Glass follows the theme.** The popup on the light theme: pale frosted glass, the page still visible around it.

## Install

Copy the folder to `de1plus/skins/Lumen/`, restart the app, pick **Lumen** under Settings > App > Skin. Built to work with Grind Advisor, DYE, Bean Scanner, Shot History Editor, Maintenance Tracker and SDB; each is optional.

## Safety

Lumen writes only the app's own settings through the app's own calls (temperatures, volumes, its theme and favorite slots). It never touches shot files or the shot database and never starts a flow on its own.

<details>
<summary><b>Full reference and version notes</b></summary>

## Reference

A glass dashboard skin for the Decent DE1, by Blastize.

Lumen replaces the home screen with a dashboard: the current grind
recommendation, the last shot, the shot graph, and the beans for the next
shot — all reachable without going into Settings. It is built to work with
GrindAdvisor, DYE, Bean Scanner, ShotHistoryEditor, MaintenanceTracker
and SDB.

**Version 0.57.0 — every page built, baked and running on the tablet.**

New in 0.57.0: **the taskbar, re-laid out.** Sleep (the moon) sits alone
at the far left where a stray tap finds nothing else; the date sits under
the time with the water level beside it; the four remaining icons close up
at the right edge; the wordmark is gone. The three favorite slots now show
their **profile names**, centred, cut with an ellipsis when long: a dim
`+` is an empty slot, grey is a set one, and the loaded profile's slot
reads in crema over a soft **halo** that follows the profile wherever it
was chosen. Tapping a slot moves the halo there the instant you touch it.

New in 0.56.0: **Auto glass.** The colour picker's BASE row offers Dark,
Light or Auto. With Auto, your own colours sit on light glass from one
time of day and on dark glass from another (tap a time to step it by 30
minutes; 07:00 and 19:00 to start), and Done draws both looks at once so
the change of glass is instant. The flip happens on the home screen
while the machine is idle, never mid-shot.

New in 0.54.0: the THEME row's button reads **Change** and opens the
colour picker, where Lumen dark and Lumen light sit among the presets;
the old Dark → Light → Custom cycle is gone. The caption names the theme
on screen.

New in 0.52.0: **truer custom accents.** The accent colour is now kept
readable on the tinted card it actually sits on (the hero number, Done,
Steam and Water), not only on plain glass; on light bases that lifts a
few combinations that used to wash out. The white / black accent swatch
now really gives white on a dark base and near-black on a light one,
and survives being saved. Existing custom sets are redrawn once at the
next start.

New in 0.51.0: **a roomier colour picker with 52 swatches and a true
preview.** Backdrop and accent each offer two rows of thirteen: a neutral
(grey backdrop; white or black accent), brown and taupe, and the twelve
hues both tinted and rich (backdrop) or vivid and muted (accent). The
preview is the home page itself, painted by the theme's own painter from
the colours you are choosing, with chips of the derived page, glass, text,
accent and chip colours beneath it.

New in 0.50.0: **a wait pill while a theme applies.** Switching a theme
takes a few seconds (the DYE pages are rebuilt, and a new custom set is
painted first); the screen no longer just stops — a pill in the middle
names each step as it goes.

New in 0.49.0: **glass popups in your own colours.** Grind Advisor's
Shot analysis and Curve popups over a custom theme used to show the dark
theme's home art around and through the card; the custom theme now
paints its own frosted slab and dimmed scrim beside its backgrounds and
serves them to the popup.

New in 0.48.0: **DYE follows the theme.** The Describe Your Espresso
editor and its dialogs now take the new colours the moment you switch,
like every Lumen page; nothing waits for the next launch any more.

New in 0.47.0: **themes switch live.** Tap THEME and the page you are on
changes to Dark, Light or Custom on the spot; tap Done in the colour
picker and every page takes your colours at once. No more quitting and
reopening the app. The first time a set of custom colours is chosen the
tablet paints its five backgrounds, which takes a few seconds; after
that they are reused.

New in 0.46.0: a **Custom theme**. Beside Dark and Light, the THEME row
now cycles to Custom, and its caption opens a picker where you choose a
base (dark or pale glass), a **backdrop** tint and an **accent** colour
from twelve swatches each, or one of six presets. A preview card repaints
on every tap. The backgrounds are painted on the tablet itself the first
time, so nothing is baked ahead of time. Labels and the accent are
guarded for contrast whatever you pick.

New in 0.45.0: a **LOW WATER** row on the Lumen settings page sets the
tank level under which the taskbar's water reading turns amber (100 to
800 ml in 50 ml steps, default 300). It fills the slot the DECENT APP row
left empty, so both settings columns are four rows again.

New in 0.44.0: the **tank-empty page** is a Lumen page. When the machine
runs dry it used to drop into the default skin's cracked-earth photo; now
it shows a glass panel with "Please add water", the app's own "Touch
screen to retry" hint, and the live tank reading so you can watch the
level rise as you pour. The three taps are exactly the stock ones: the
screen retries, bottom-left exits the app, bottom-right is Ok.

New in 0.43.1 (polish): the confidence band is coloured by what it says
(green for Good, amber for Poor), the LAST SHOT card says **when** the
shot was pulled, the chart legend carries each curve's final value with
its unit, the water readout turns amber under 300 ml, the scale box says
"Tap to retry" instead of "Connecting" forever, the espresso page shows
the target under the live weight, and the tertiary text is a step
brighter for contrast.

New in 0.43.0: the chart and the LAST SHOT card show the last **real**
shot of the loaded bean. A cleaning run (or a backflush, calibration,
descale, or an abort under 5 s) is saved by the app exactly like a shot,
so it used to take over the home page until the next espresso; now it is
skipped at startup, when a Shot History Editor change reloads the page,
when the bag cycler switches bags, and the moment the cleaning run
finishes. The card also names the bean the shot file records, so a fresh
bag with no shots yet shows the previous bag's last shot under that bag's
own name.

New in 0.42.0: the stock app settings are one tap away again, behind a
**drawn side view of the DE1** in the taskbar slot the old sliders glyph
held (0.41.0 had briefly moved them behind a settings-page row — two
taps — after the gear-next-to-sliders ambiguity was fixed). The icon is
vector strokes in the palette ink: body, tilted screen, group head,
drip tray.

New in 0.40.0: a taskbar button, the **mug**, opens the Drink Menu
plugin's grid (Done returns straight to the home page). The water
readout moved 72 px left to make room; nothing else changed. If the
Drink Menu plugin is absent or disabled the tap only logs a line.

New in 0.39.0: Lumen offers plugins a baked **glass material**
(`::lumen::glass_material`) so overlays like GrindAdvisor's after-shot
popup can render as an iOS-style frosted card showing the home screen
through it. Provider only — nothing visible changes in Lumen yet, and on
any other skin the popup stays opaque.

New in 0.38.0: a freshly scanned bag with no shots shows GrindAdvisor's
**starting estimate** on the grind tile — header STARTING ESTIMATE, a `~`
before the number, an Estimate chip, and the source ("Starting estimate:
same roaster (4 bags)") — instead of just `--`. It is display-only and
disappears the moment the bag's first real shot produces a calibration.

Since 0.30.0 the top of the screen is a **taskbar** (re-laid out in
0.57.0): the moon (sleep) alone at the far left, a live clock over the date
(12/24-hour and day-month/month-day formats, chosen on the settings CLOCK
row) with the water level beside it, the three favorite profile names
across the middle, and mug / wrench / gear / DE1 icons at the right — Drink
Menu, plugin maintenance, Lumen settings and the stock app settings (a drawn
side view of the machine). A
**maintenance dot** at the wrench turns amber or red when the
MaintenanceTracker plugin says something is due or overdue. The old side
panel is gone; the bean strip runs the full width, and the chart lost its
toggle pills — it is always smooth, always showing stage lines. Every tap
answers with a **press flash** fitted to the control: a neutral chip behind
buttons and text links, an outline for the grind card.

Earlier milestones: the home page follows Shot History Editor edits
(0.28.0); the LAST SHOT card reports what the shot file records, so
corrections show up (0.24.1–0.25.0); every page has a pre-rendered frosted
background and the strip carries the bag cycler (0.18.0–0.23.x). The full
story is in the CHANGELOG.

## The home screen

Everything above is one page: the grind recommendation with its method and
confidence, the last shot's numbers, the full shot graph, and the next shot's
bean and targets. A light theme ships alongside this dark one — it is not an
inversion, since on a pale ground the panels have to sit *brighter* than the
backdrop and let the shadow do the separating.

## What the home screen does

| Tile | Shows | Tap |
|---|---|---|
| Taskbar (top) | Live clock over the date, and the water left in the tank in mL — amber under 300 ml, blank when no machine is connected | The five icons: moon (far left, alone) = sleep; at the right, mug = Drink Menu, wrench = MaintenanceTracker's card list, gear = Lumen settings, DE1 side view = the stock app settings |
| Favorite profiles (taskbar, three slots across the middle) | Each slot shows its profile's name, centred and cut with an ellipsis when long: a dim `+` is an empty slot, grey is a set one, and the loaded profile's slot reads in crema over a soft crema halo | Tap an empty slot to store the profile loaded now; tap a set slot to load its profile (refused while the machine is running). Put your backflush profile in one and a cleaning run is one tap plus the GHC button. "Clear favorite profiles" on the Lumen settings page empties all three |
| Maintenance dot (at the wrench) | Amber when a maintenance item is due soon, red when one is overdue — driven by the MaintenanceTracker plugin's status; blank when all is well or the plugin is absent | — |
| Grind | GrindAdvisor's next setting for the loaded bag, the change from the last one, method, confidence and shot count. A bag with no shots yet shows the **starting estimate** instead (GrindAdvisor 3.13.0): STARTING ESTIMATE header, `~` before the number, an Estimate chip, and which bags it was borrowed from | Opens GrindAdvisor's settings (target time, rounding, history) |
| Shot analysis (on the grind tile) | — | Opens GrindAdvisor's result popup |
| Curve (on the grind tile) | — | Opens GrindAdvisor's Calibration Curve directly |
| Last shot | The last **real espresso** of the loaded bean (cleaning, backflush, calibration and sub-5 s runs are skipped; a bag with no shots yet falls back to the newest real shot of any bag): the profile it ran on, the roaster and bean, then grind, dose, yield (with the ratio beneath) and time — as **that shot recorded them**, read back from the shot file, so corrections made in the Shot History Editor appear here. `--` when the shot had no weight | — |
| Shot history (Last shot tile) | — | Opens the Shot History Editor (edit / soft-delete past shots) |
| Graph | Pressure, flow, cumulative weight and basket temperature for that shot — always smoothed (Catmull-Rom through the recorded samples), with dashed stage separators at every frame change. Live during a shot; after a cleaning run it goes back to the bean's last real shot | — |
| Next shot | The profile, the roaster, the bean, and its tasting notes | PROFILE row opens the app's profile chooser |
| ◀ ▶ (next-shot card) | The bag being cycled, with a dot per reachable bag beside Edit — filled for the one loaded, leftmost the most recent | Steps through your recently used beans; the grind tile, chart and LAST SHOT card all switch to that bag (0.30.0). It does not wrap: at the newest or oldest bag, that direction stops |
| Edit | — | Opens DYE's next-shot editor |
| − value + steppers | GRIND, DOSE, YIELD — the live value sits between the pills, with the derived ratio under the yield | Each tap ±0.1; drumming rapidly (3+ taps a second) escalates to ±0.5 then ±1.0. Any measured pace stays at ±0.1 (0.28.1) |
| Scale readout | Live weight, or `Connecting` (then `Tap to retry` after 30 s) / `Connect` / `no scale` | Forces a scale reconnect |
| Set dose | — | Stores the current scale weight as the dose |
| Scan bag | — | Bean Scanner |

The bag cycler reads your recent beans through SDB's public API and applies
the chosen one through DYE, so the skin itself opens no database. How many
bags it offers is set on the Lumen settings page (3–10, default 5). The dots
under it catch up as soon as SDB records a shot, so a newly scanned bag's dot
lights after its first shot without touching the arrows.

There are no Espresso/Steam/Water/Flush buttons — the machine's GHC starts
those, and the flow pages take over the screen as soon as it does.

The Grind tile's method chip names the rung GrindAdvisor used: **First shot**
(1 shot on the bag), **2-shot**, **Regression** (3 or more), or **Pairwise**
when the regression is too flat to solve.

## If the scale does not connect

Tap the weight readout. The app only retries a dropped scale about 20 times,
roughly 10 seconds apart, and then stops for good — so a scale switched on a
few minutes late is never picked up on its own. Tapping the readout clears the
app's retry counter and starts a fresh connection attempt; it shows
`Connecting` while one is in flight.

## During a shot

Espresso, steam, water and flush each get their own page: what the machine is
doing, a large elapsed timer, and live pressure / flow / weight / temperature.
Tap anywhere to stop — including on flush, which the stock skin does not offer.

Each page reads its own timer, and only reports the flow **this** page visit
is running. The machine's timers keep describing the previous flow until the
new one starts pouring, and the page opens before that — which is why the
espresso page used to flash the seconds since the last shot began (0.24.0).

The steam page's temperature column is labelled **STEAM HEATER**, because
that is what the machine reports there: the steam heater sensor
(`ShotSample(SteamTemp)`), which idles at the steam set point — about 158°C
with the heater set to 160°C. The set point is stated right under the value.
It is not the temperature of the steam at the wand tip, and the DE1 has no
sensor that measures that.

Everything degrades gracefully: with a plugin missing or disabled the values
read `--` and the buttons log a line to the app log rather than failing
silently. Look for `Lumen:` in the log if a button seems dead.

Dose and grinder setting persist across shots in the DE1app, so "last shot"
and "next shot" show the same figures until you change them. That is the
app's own behaviour, not a quirk of the skin.

The two cards do answer different questions, though, and 0.25.0 made that
real: **LAST SHOT is the record** — grind, dose and yield as the shot file
holds them, corrections included — while **NEXT SHOT is the plan**, the live
and DYE-staged values the next shot will use. Since 0.57.5 the card reads a
new shot's record back from the file the app just saved, so Grind Advisor
moving the grind to its next recommendation no longer changes LAST SHOT. It
only falls back to the live settings while a shot is running, or if the app
did not save one.

## Typography

Inter for UI text, NotoSansMono for every number — doses, yields, times and
grind settings line up in columns, and a proportional face makes those
columns ragged. Both families ship in `fonts/` and are already proven on this
tablet.

The skin does not use the app's `load_font`, because that hands a *positive*
(point) size to `font create`, scaled by `::settings(default_font_calibration)`
— 0.5 on this tablet — which makes text size unpredictable across DPI. Lumen
takes only the family name from the font loader and creates every font itself
at negative (pixel) sizes, with a 16px floor. If the TTFs cannot be
registered, each face falls back to Helvetica or Courier.

## Install

Copy the `Lumen` folder to `de1plus/skins/` on the tablet, so you end up with:

```
de1plus/skins/Lumen/skin.tcl
de1plus/skins/Lumen/fonts/
```

Then pick it in **Settings → Tablet → (skin list)**.

### If Lumen does not appear in the skin list

The app hides unknown skins by default. `skin_directories` in
`de1app-core/vars.tcl` filters the list against a hardcoded
`most_popular_skins` set whenever `show_only_most_popular_skins` is 1 — and
1 is the default.

Turn off **"Only show most popular skins"** on that same Tablet settings
page and Lumen will appear.

## What it looks like

Tk has no runtime backdrop blur and canvas shapes have no alpha channel, so
the frosted panels are composited offline into background PNGs — real
translucency, blurred backdrops, soft shadows and specular edges — and the
skin draws only text, the chart widget and tap targets on top.

As of 0.20.0 **every** page is baked, not just home. Five images cover
the seven pages:

| Image | Page |
|---|---|
| `lumen_home` | home (`off`) |
| `lumen_settings` | Lumen settings |
| `lumen_flow_chart` | espresso (compact layout, live chart) |
| `lumen_flow` | steam, water, hotwaterrinse |
| `lumen_message` | tankempty, refill (the out-of-water page, 0.44.0) |

The three roomy flow pages share one image because `build_flow_page` draws
identical panels for all three — only the label text differs, and text is not
baked.

The images are pre-rendered, so their panel coordinates mirror
`::lumen::_init_layout` and `::lumen::build_settings` exactly — change a
layout token and the background has to be re-rendered to match, or the text
will sit off its panel.

## Themes

Dark, light and custom. The mode comes from `::settings(lumen_theme)`
(`dark`, `light` or `custom`, default dark) and, since 0.47.0, changes
live: `::lumen::apply_theme` loads the new palette, swaps every page's
background photo (or refills the flat ones), recolours every item by its
role tag, repaints the photo panels and restyles the graphs.

**Custom** (0.46.0) derives a whole palette from five saved values: the
base (dark or light glass), the backdrop hue and tint strength, and the
accent hue and saturation. Backdrop drives the page gradient, the glass
(translucent white over it, so it inherits the tint) and the three inks;
accent replaces crema everywhere. Good/warn/danger and the chart colours
never change. The page backgrounds cannot be pre-rendered for arbitrary
colours, so at the first launch after a change the skin paints them in
pure Tcl — the gradient, every panel and pill with a soft shadow, the
bloom — and writes `lumen_<page>_custom.png` next to the baked images,
with a `lumen_custom.sig` stamp so unchanged colours draw nothing. If
painting fails, the pages fall back to flat colour with vector panels.
Grind Advisor's glass popup stays opaque under Custom.

The Lumen settings page carries the **machine column** on the left: Brew
temperature (±0.5°C), Steam, Flush time (±1 s) and Hot Water, each with the
same − value + steppers as the home strip. Changes are saved and sent to the
machine automatically, one second after the last tap.

**Steam and Hot Water each carry two settings** (0.26.0). Tap the mode line
under the row's label to choose which one the − / + pills drive:

| Row | Modes | Step |
|---|---|---|
| Steam | **TIME** (`steam_timeout`) / **FLOW** (`steam_flow`) | ±5 s / ±0.1 mL/s |
| Hot Water | **TEMP** (`water_temperature`) / **VOL** (`water_volume`) | ±1 °C / ±10 ml |

The selected setting is the large value between the pills; the other sits
small beneath it, so both are always readable. The choice persists — whichever
half you last steered is the one waiting next time.

The right column runs **THEME**, **BAGS TO CYCLE**, **CLOCK** and
**LOW WATER**. The stock app settings (profiles, plugins, firmware) open
from the taskbar's DE1 icon, and Grind Advisor's settings from the grind
card itself — so neither needs a row here.

*Low water* (100–800 ml, default 300) is the tank level under which the
taskbar's water reading, and the out-of-water page's, turn amber. Stored
in `::settings(lumen_water_low_ml)`; a Lumen preference only.

*Bags to cycle* (3–10, default 5) sets how many recent bean bags the home
strip's bag cycler offers. It is stored in `::settings(lumen_bag_count)` and
is a Lumen preference only — it never reaches the machine.

*Clock* carries two live-labelled buttons: the date sample toggles
day-month ↔ month-day, the time button toggles 24H ↔ 12H. Both apply to
the taskbar immediately — no restart — and persist in
`::settings(lumen_date_format)` / `::settings(lumen_time_format)`.

## The next-shot strip

`NEXT SHOT` names the bag, with **◀ ▶** arrows that cycle it through the most
recently used bags (as many as *Bags to cycle* allows). A bag not in that
window steps onto the most recent one. Tapping the bag name still opens DYE.

Then **GRIND**, **DOSE**, **YIELD** and **PROFILE**. Ratio is shown as a
derived caption under the yield value rather than a stepper of its own: it was
never independent — stepping it only ever wrote the target yield — and the
column was needed for the profile, which now scopes calibration (Grind Advisor
3.7.0 starts a fresh calibration when the profile changes).

Profiles are chosen in the app's own picker, which tapping the **PROFILE**
row on the NEXT SHOT card opens directly (`show_settings settings_1`, the
stock profile tab).

The **LAST SHOT** card names the profile that shot ran on, which is not
necessarily the one loaded now — when the two differ, Grind Advisor has
started a fresh calibration.

Nothing in the cycler touches the database directly: the bag list and shot
clock come from SDB's public read API, and the write goes through DYE's own
`source_next_from`, the same path Bean Scanner uses.

The **THEME** row's Change button opens the picker (0.54.0; until 0.53.1
the button cycled the three), and tapping Done there puts the change on
screen before your finger lifts (0.47.0). The picker's **Auto** base
(0.56.0) puts your custom colours on light or dark glass by time of day:
`lumen_custom_base` = auto with `lumen_auto_light_from` and
`lumen_auto_dark_from` (minutes past midnight); both halves are drawn
(`_custom` and `_customl` files) and a minute tick swaps them on the
home or saver page while the machine is idle. Every item a Lumen helper
draws carries a role tag naming the palette token it took its colour from
(`lumen_c_ink`, `lumen_o_glass_brd`, ...), so a theme is one
`itemconfigure` per token; the page backgrounds swap their photo through
dui's own image resolver. DYE's pages are styled by a dui theme
(`DYE_Lumen`) whose aspects are read when each page is set up, so a theme
change sets those aspects again and hands every page on that theme to
dui's own `page retheme`, which recreates it (0.48.0). Grind Advisor's
popup reads the theme when it opens, so it follows by itself.

Until 0.46.1 a theme change quit the app, because **the app cannot reopen
itself** on Android 16 — `am start` from the app's uid is rejected by the
platform, and `borg activity` would start the activity in the process
that is exiting. The CHANGELOG entry for 0.15.0 has the measurements.

Both baked themes ship backgrounds for every page
(`1340x800/lumen_*[_light].png`, `2560x1600/...`).

## Layout basis

The whole file is authored in **design pixels on a 1340x800 basis** — the
same basis as the design mockup — and converted to the app's 2560x1600
virtual canvas through `::lumen::X` and `::lumen::Y`.

Those two factors are deliberately different: 2560/1340 is 1.9104 but
1600/800 is 2.0. Using a single factor for both axes drifts the layout
horizontally, which is why x and y convert separately.

All layout numbers live in one block, `::lumen::_init_layout`. Nothing below
it hardcodes a coordinate.

## Safety

No database is opened, and no file in `history/` or `history_v2/` is
written, renamed or deleted. Shot files in `history/` are **read**, one at
a time and only when the home page selects a shot to show (startup, a bag
cycle, a Shot History Editor change, the end of a cleaning run) — never on
the refresh tick. Which files to try comes from SDB's public read API when
the plugin is loaded, else from the directory listing; a file's curves are
copied into the chart and its `settings` block is parsed into a local
array, never into the live settings.

Every `::settings` write happens only on an explicit tap, and every stepper
clamps its value. Three groups:

* **Preferences:** `lumen_theme` (theme), `lumen_bag_count` (bag cycler
  depth), `lumen_time_format` / `lumen_date_format` (taskbar clock),
  `lumen_water_low_ml` (amber threshold, 100–800), the custom theme's
  `lumen_custom_base` / `_bh` / `_bs` / `_ah` / `_as` (picker Done only),
  and `lumen_fav_profiles` (the three favorite slots: a tap on an empty
  slot stores the loaded profile's filename and title; the settings
  page's Clear link removes the key).
* **Profile switch (0.53.0):** a tap on a set favorite slot calls the
  core's own `select_profile` with that slot's filename (the same call
  DrinkMenu and DYE make), then `save_settings` + `save_settings_to_de1`
  a second later. Refused while the machine is running. It never starts
  a flow: the GHC does.
* **Files:** the custom theme writes `lumen_<page>_custom.png` and
  `lumen_custom.sig` into `skins/Lumen/<width>x<height>/` — its own
  folder, nothing else.
  Since 0.36.0 the chart is always smooth with stage lines shown —
  `live_graph_smoothing_technique` and `lumen_chart_stages` are no
  longer read or written.
* **Next-shot steppers:** `grinder_dose_weight` (Set dose — refuses
  non-positive readings — and the dose stepper, 2..40), `grinder_setting`
  (grind stepper, 0..100), `final_desired_shot_weight` /
  `final_desired_shot_weight_advanced` (yield and ratio steppers, 0..200).
  With DYE loaded, its staged `next_grinder_setting` and
  `next_grinder_dose_weight` are kept in step, the same pairing DYE's own
  DSx2 stepper performs.
* **Machine steppers (settings page):** `espresso_temperature` (via the
  core's `change_espresso_temperature`, 70..110), `steam_timeout` +
  `steam_disabled` (0..255, 0 = off), `flush_seconds` (3..254),
  `water_volume` (10..250) — persisted and sent to the machine with the
  core's `save_settings_to_de1`, debounced by a second.

The Shot history button only opens the Shot History Editor; edits and
deletions there are that plugin's own, behind its own preview/confirm flow.
Nothing else is touched.

The grind tile, bean strip and Scan bag button hand off to GrindAdvisor, DYE
and Bean Scanner; any writing those perform is their own, behind their own
confirmation.

## Credits

The rounded-panel primitive is the same smoothed-polygon mechanism used in
the GrindAdvisor plugin. The stop-button bindings on the espresso, steam and
water pages are copied verbatim from `skins/default/standard_stop_buttons.tcl`.
The stock settings, firmware, descale and profile-editor pages come from
`skins/default/standard_includes.tcl` and are untouched; only its
out-of-water page is re-declared by Lumen (0.44.0), keeping its tap
commands verbatim.

</details>
