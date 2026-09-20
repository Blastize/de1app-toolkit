# Drink Menu - Changelog

Entries follow the CLAUDE.md doc cap (about 15 lines; write-capability
passes documented in full). The long pre-trim entries for v0.1.0 to
v0.13.2 survive in the Desktop archive snapshot of each version.

## v1.17.0 - 2026-09-15 - Pass 48: UX review

Base: tablet-verified v1.16.1. The design critique plus the owner's two
notes, one batch. Protocol lane (show/hide rules, a new tap target, a
new button kind); minor bump.

- **Hairlines exact.** Shape hairlines and the capsule divider are
  one-row / one-column rects, the body runs the caps' full height
  (canvas lines are anti-aliased on AndroWish: the dark row under
  every gold shape). `_shape_geom` returns the hairline rows.
- **Star on the corner's diagonal** (left inset = top inset).
- **Hot water** `#cfc4b4` (warm), no longer the cold-water family.
- **Detail:** Favorite = star icon (`-icon` on `bar_button`, 260 ref
  wide; Hide 160) + fixed label; "Add a method" link on a custom drink
  with no steps (`met_add_tap` -> `method_add_tap`); layer labels fit
  body -> caption -> ellipsis (`fit_label_name`).
- **Editor:** Delete beside Cancel in the `danger` kind
  (`btn_danger_*` tokens); keyboard Done created hidden and driven by
  the entry's focus (`_name_focus`); "Drink name" hint as the entry's
  own text under `edit_loading` (`_name_hint_apply` / `_drop`); the bar
  shows in the layers mode only; Method / Profile on the second header
  row, layer rows from row 2, "+ Add layer" moved by `$can move` to the
  row after the last layer (`ed_add_y`).
- **Menu:** "page / pages" beside Prev's slot (`bar_page`).
- geometry_check: AASHAPE / STARFILL / TOUCH / MARKS / EDITOR
  retargeted, new UX48 section (10): 512 passed, 0 failed.

**Safety status:** no write behavior exists in this version beyond the
standing one (settings.tdb through `_persist`; the v1.10.0 "To machine"
tap). The name hint never reaches the draft: it is written under
`edit_loading`, so the keystroke trace ignores it and validation still
requires a name.

## v1.16.1 - 2026-09-15 - Pass 47: the star on the badge's row

Base: tablet-verified v1.16.0. Owner note on the v1.16.0 screenshots:
the star hugged the card corner. Polish lane, one layout tweak.

- **Star on the badge's row:** `tile_star_inset` = the badge's inset
  (12 ref, was 10) and `tile_star_cy` = the badge's centre line
  (`tile_badge_y1` + `chip_h` / 2, 27 ref, was 17). The 48 ref tap box
  and the tile tap partition are unchanged (the star stays inside with
  >= 8 units of slack); the pen slot follows the centre line.
- geometry_check: STARFILL and TOUCH retargeted; 501 passed, 0 failed.

**Safety status:** no write behavior exists in this version beyond the
standing one (settings.tdb through `_persist`; the v1.10.0 "To machine"
tap); only two layout tokens changed.

## v1.16.0 - 2026-09-15 - Pass 46: the last canvas-drawn marks as sprites

Base: tablet-verified v1.15.0. The remainder of wishlist item 1: the
tile stars, the ingredient dots and the hero ring's dim arc were the
last stair-stepped marks (the divider lines are axis-aligned). Polish
lane, paint only; nothing moved, no behaviour changed.

- **One mechanism:** a PNG photo per key, shown by an image item whose
  photo is swapped at refresh (`_set_image`, cached like `_set_fill`).
- **Tile star:** two faces painted at menu setup (`star_photo`: solid
  crema / hollow ink_3 from the signed distance to the star polygon),
  `star_paint` swaps them; the polygon stays hidden as the fallback.
- **Ingredient dots** (chips, editor rows, palette): a full-radius
  `_shape_rows` circle per colour with the ink rim, `dot_paint` swaps by
  colour; the ovals stay hidden. `star_tags` / `dot_tags` name the live item.
- **Hero dim arc:** baked into the hero's stroke sprite (ring pixels at
  or right of the label column, `dim_x` in the sprite key, painted
  ring_dim); the canvas arc stays hidden while that sprite is on screen.
- One boot NOTICE ("mark sprites") reports count, size and paint time.
- geometry_check: new MARKS section (6): 501 passed, 0 failed.

**Safety status:** no write behavior exists in this version beyond the
standing one (settings.tdb through `_persist`; the v1.10.0 "To machine"
tap); every button keeps its command, only the marks' paint changed.

## v1.15.0 - 2026-09-14 - Pass 45: hierarchy

Base: tablet-verified v1.14.0. The owner's remaining review notes.
Polish lane (layout, colour and copy); no behaviour changed, nothing
navigates differently.

- **One gold action per page.** On the menu "+ New drink" is the gold
  button and Done, being navigation, a ghost (detail: Copy & edit /
  Edit; editor: Save / Done, unchanged).
- **Worded favorites tab:** "Favorites" at the pill font instead of the
  icon-only star among worded pills.
- **The unit toggle apart from the filters:** 48 ref px clear of the
  pills (was the 24 group gap), and every segmented toggle's selected
  half (ml/oz, 1/2 shots, ml/g) wears a secondary tone (ink_2, gold-ink
  text; `seg_on_fill` / `seg_on_text` / `seg_press`), so gold means only
  "active filter" and "the primary action".
- **Custom pen in a fixed slot:** xs right of the star box, centred on
  the star, clear of the cup; it no longer floats under the badge.
- geometry_check: PRIMARY / PERSIST / CONTRAST retargeted, new HIER
  section (5): 495 passed, 0 failed.

**Safety status:** no write behavior exists in this version beyond the
standing one (settings.tdb through `_persist`; the v1.10.0 "To machine"
tap); buttons keep their commands, only their looks and places changed.

## v1.14.0 - 2026-09-14 - Pass 44: anti-aliased cups with a soft shadow

Base: tablet-verified v1.13.0. The last stair-stepped thing on screen.
Polish lane, paint only; nothing moved, no behaviour changed.

- **Two sprites per cup.** `<tag>_fg`, the ink stroke (bowl outline, stem
  outline, handle ring, each a 2 px anti-aliased line from the distance
  to the path, the ring clipped to outside the bowl), lies OVER the flat
  layer polygons; `<tag>_shb`, a soft black shadow ellipse (.30, fading
  40% past the old oval), lies UNDER them. PNG with alpha, painted in
  Tcl (`cup_sprites`), lazily on first use and shared per vessel and
  zone: the 12 tiles use one pair per vessel.
- **Pixel-exact sharing:** `_cup_render` computes the geometry with the
  zone at (0, 0), rescales, then offsets by the zone's rescaled origin.
- **Fallback kept:** the shadow oval, handle oval and stroke polygon stay
  in the pool, hidden; a refused PNG shows them again. One boot NOTICE
  reports the sprite count, size and paint time.
- geometry_check: new CUPSPRITE section (5): 489 passed, 0 failed.

**Safety status:** no write behavior exists in this version beyond the
standing one (settings.tdb through `_persist`; the v1.10.0 "To machine"
tap); this pass touches cup painting only.

## v1.13.0 - 2026-09-14 - Pass 43: anti-aliased pills, badges, chips and buttons

Base: tablet-verified v1.12.0. The second half of the owner's "jagged
curves" note. Polish lane, paint only; nothing moved, no behaviour changed.

- **One shape engine** (`shape_make` / `shape_paint` / `shape_flash` /
  `shape_move`): a rounded control is two cap PHOTOS (its left and right
  r columns, PNG with alpha, anti-aliased arc + hairline ring) and a
  flat body (rect + two 1 px hairlines) between them. Cap pairs are
  keyed by (h, r, fill, edge) and shared: 16 pairs, 140 KB, for every
  tab pill, the three capsules and their gold halves, the 12 ml badges,
  the ingredient / palette / group chips and all 77 bar and row buttons.
- **Buttons:** the dbutton no longer paints a face (`shape none`, dui's
  invisible rect); the art sits under it with the button's `<tag>*`
  group tag, the label and every relabel stay dui's. No `pressfill`
  anywhere; `bar_button` wraps each `-command` in `_btn_tap`, which
  flashes the art and restores it from state (`_press_restore`).
- Fallback: a refused cap PNG draws the v1.12.0 polygon under the same
  tag. geometry_check: RADII / PRESS / TONAL retargeted, new AASHAPE
  section decoding the caps and enforcing dui's unique-first-tag rule
  (the first tablet run failed on it): 484 passed, 0 failed.

**Safety status:** no write behavior exists in this version beyond the
standing one (settings.tdb through `_persist`; the v1.10.0 "To machine"
tap); the command wrapper only adds the flash before the same command.

## v1.12.0 - 2026-09-14 - Pass 42: anti-aliased cards with a real shadow

Base: tablet-verified v1.11.0. Owner's tablet review: "jagged curves".
Polish lane, paint only; nothing moved, no behaviour changed.

- **Cards are PNG photos with alpha.** Painted as RGBA rows in pure Tcl
  (`glass_rgba`), zlib-encoded in memory (`png_encode`) and created
  with `image create photo -data` at the exact physical size: true
  anti-aliased corner arcs, the .10 hairline as a 1 px ring, and the
  mock's drop shadow (offset 6, logistic blur over 14, .35 / hero .40)
  in a 20 px margin round the card. Nothing shipped per resolution,
  nothing scaled. (The first tablet cut used a hard quadratic fall-off
  and read as a dark slab; the blur replaced it before release.)
- **One card radius:** the detail hero drops its 29 for the cards' 24.
- **Fallback kept:** the v1.11.0 `put` painter runs if the PNG is refused
  (no shadow, hard corners, never a hole). One boot NOTICE reports the
  photo count, size and paint time (7 photos, 4.55 MB, ~1.2 s at app
  start on the Tab A9). Photo budget 4 -> 5 MB.
- geometry_check: the put-replay GLASS/GLOW pixel net is replaced by
  AACARD, which decodes the very PNG bytes: 474 passed, 0 failed.

**Safety status:** no write behavior exists in this version beyond the
standing one (settings.tdb through `_persist`; the v1.10.0 "To machine"
tap); this pass touches photo painting and one radius token only.

## v1.11.0 - 2026-09-14 - Pass 41: tonal restyle

Base: tablet-verified v1.10.0. Owner's tablet review of the menu page:
"cards and buttons glows are really fake and bad looking". Polish lane,
paint only; nothing moved, no behaviour changed.

- **Glass imitation dropped.** Tk has no alpha or blur, so the .17 rim,
  the lit glow band, the top highlight line and the bottom shade line
  stacked into a bevelled plastic tile. Cards are now their gradient
  photo (pairs stepped up: tile .14 -> .06, card .12 -> .05, hero
  .13 -> .055) with a faint .10 hairline edge and nothing else.
- **Buttons.** The bar buttons' inset top highlight line is gone; gold
  buttons and the selected pill are rimless; ghosts keep the hairline.
- **Cup shadow** oval lightened, .35 -> .15 of black.
- geometry_check: PRIMARY's highlight assertions inverted, new TONAL
  section (6): 476 passed, 0 failed. Jagged curves are pass 42+ (PNGs).

**Safety status:** no write behavior exists in this version beyond the
standing one (settings.tdb through `_persist`; the v1.10.0 "To machine"
tap); this pass touches colours and item creation only.

## v1.10.0 - 2026-09-03 - Pass 40: DE1 tie-ins

Base: tablet-verified v1.9.0. Owner request; the wishlist's last item.
This pass is machine-adjacent, so its write statement is the full one.

- **One explicit tap.** The detail bar's free stretch (between Back and
  Favorite) gains a "To machine" ghost button, shown only for drinks
  that define something to apply. The tap - and nothing else, ever -
  applies from the drink AS DISPLAYED (the sized drink):
  its linked profile via the core's own `::select_profile` (the exact
  call DYE makes), and/or the hot-water volume its `hot_water` layers
  sum to (clamped to the machine UI's 10..250) via
  `set ::settings(water_volume)` plus the debounced
  `save_settings; save_settings_to_de1` copied from the Lumen skin.
- **Nothing automatic.** No page load, show, event or timer touches the
  machine or app settings; the only timer is the tap's own 1 s debounce.
  No flow is ever started. DevBridge's busy guard (copied, fails closed)
  refuses the tap mid-operation. The outcome is written onto the button;
  the next refresh restores its label.
- **Profile linking.** Custom drinks may carry `profile_fn` +
  `profile_title`, stamped from the app's CURRENT profile by the
  editor's new third bottom-row button (toggle link/unlink, notes in the
  status line); rides the confirmed saves; linking writes nothing.
- **The standing claim changes here:** besides its own settings.tdb, the
  plugin now - on that one tap only - changes the app's selected profile
  and water_volume through the app's own official procs, exactly as the
  skin's controls do. The headless TIEIN net proves each machine-
  adjacent call appears EXACTLY once, inside `to_machine_tap`, wired to
  exactly one button: 470 passed, 0 failed.

## v1.9.0 - 2026-09-03 - Pass 39: a larger vessel for 2-shot overflow

Base: tablet-verified v1.8.0. Owner request (the wishlist's second-to-
last item).

- New vessel: `pint` - "Pint glass", 500 ml, straight-sided, terminal -
  filling the vessel picker's 2x4 grid to exactly 8 tiles and choosable
  like any vessel. The tall glass (350) now sizes up to it, and the
  coupe (180, terminal before) sizes up to the latte glass, so 2-shot
  drinks that used to wear "over capacity" step into a vessel that
  holds them. Its tile_scale matches the tall glass (both height-bound
  in a tile; the badge tells them apart; hero/preview show the truth).
- Data plus two `size_up` wirings in presets.tcl; no code change.
- geometry_check: vessel count/pool 8, the chain spec, three new SIZED
  assertions (tall glass -> pint, coupe -> latte glass, pint terminal
  with a truthful overflow flag): 461 passed, 0 failed.

**Safety status:** no write behavior exists in this version beyond the
standing one - and no write-path proximity at all: presets.tcl remains
read-only data, `sized_drink` is display-only, and a drink saved in a
pint rides the same validation and confirmed saves as any vessel.
`plugins save_settings` appears exactly once, inside `_persist` (six
callers, unchanged).

## v1.8.0 - 2026-09-03 - Pass 38: group choice for custom drinks

Base: tablet-verified v1.7.0. Owner request (was on the wishlist).

- A drink's `group` is its menu SECTION (the All tab's six appendix
  groups); customs were forced to `custom` = the very end. The editor's
  vessel row now splits into "Vessel: ..." and "Group: ..."; the Group
  mode offers the six groups plus "End of menu", the draft's choice
  painted gold; a tap picks and returns.
- `visible_drinks` interleaves: a chosen group sorts the custom directly
  after that group's presets (creation order); "End of menu" keeps the
  old place. A preset copy seeds from its source's group; "+ New drink"
  starts at the end. Tabs are untouched (flags/id-based).
- **Write-shape change, stated in full:** the saves no longer force
  `group custom` - `_clean_draft` carries the draft's group, sanitized
  by `valid_group` (unknown -> custom) - and `_validate_settings`
  SANITIZES the stored group instead of forcing it: a chosen group
  survives the load; junk repairs to `custom` in memory with a NOTICE,
  no write. `source custom` is still forced everywhere.
- geometry_check gains GROUPS (7 assertions incl. the interleaving):
  457 passed, 0 failed.

**Safety status:** no write behavior exists in this version beyond the
standing one. The group rides the draft to the same two confirmed saves;
`plugins save_settings` appears exactly once, inside `_persist` (six
callers, unchanged).

## v1.7.0 - 2026-09-03 - Pass 37: editable method steps

Base: tablet-verified v1.6.0. Owner request (was on the wishlist).

- The layers mode's bottom row splits into "+ Add layer" and "Method
  (N)". The Method mode lists the draft's steps: number, text, tap to
  edit, chevrons to reorder, x to remove, "+ Add step", Done. Capped at
  FOUR - the detail Method card pools four lines, so what you write is
  what the drink page can show (clean_steps' 6 x 80 stays the
  load-repair tolerance). A step caps at 80 chars on the way in.
- Tap or "+ Add step" opens a one-entry form in the keyboard-safe top
  zone ("Edit step N" / "New step", prefilled, Cancel back to the LIST,
  Save primary). An emptied entry is "no change"; x removes.
- Pure helpers `steps_with` / `steps_remove` / `steps_move`.
- **Write-shape change, stated in full:** the two confirmed saves no
  longer copy the SOURCE drink's steps. `open_editor` seeds the draft
  with the drink's own steps (a preset copy starts from the preset's,
  exactly what the save used to produce); `_clean_draft` always carries
  the draft's cleaned steps. The load-repair is unchanged and the load
  writes nothing.
- geometry_check gains STEPEDIT (9 assertions incl. a source-scan):
  450 passed, 0 failed.

**Safety status:** no write behavior exists in this version beyond the
standing one. The steps ride the draft to the same two confirmed saves;
`plugins save_settings` appears exactly once, inside `_persist` (six
callers, unchanged).

## v1.6.0 - 2026-09-03 - Pass 36: garnish editing

Base: tablet-verified v1.5.0. Owner request (was on the wishlist).

- The editor preview card gains a tappable "Garnish: ..." line (text,
  gold pen, invisible rect - the editor only ever edits a custom draft).
  It opens a new mode: a free-text entry in the keyboard-safe top zone,
  prefilled comma-separated, a hint line, Cancel / Save.
- Save parses to the token-list shape every preset has always carried:
  split on commas, trim, runs of spaces to underscores, at most 4
  entries of 24 chars; an empty entry clears. Display code everywhere is
  unchanged (the detail hero's caption already renders any list).
- **Write-shape change, stated in full:** the two confirmed saves no
  longer override the draft's garnish from the SOURCE drink;
  `_clean_draft` always carries the draft's cleaned garnish. Steps still
  travel from the source (unchanged). `clean_garnish` load-repairs a
  malformed garnish in memory exactly as `clean_steps` does; the load
  writes nothing.
- geometry_check gains GARNISH (round-trip, caps, clears, repair, and a
  source-scan proving no save reads the source's garnish):
  441 passed, 0 failed.

**Safety status:** no write behavior exists in this version beyond the
standing one. The garnish rides the draft to the same two confirmed
saves; `plugins save_settings` appears exactly once, inside `_persist`
(six callers, unchanged).

## v1.5.0 - 2026-09-03 - Pass 35: layer reorder in the editor

Base: tablet-verified v1.4.0. Owner request (was on the wishlist).

- Every layer row gains a chevron-up / chevron-down pair, LEFT of the
  amount steppers: name, amount, move up/down, - / +, remove. Rows are
  top-first and layers bottom-first, so up the list is up the glass.
- `edit_move` (pure) swaps the layer with its neighbour - ingredient and
  amount travel together, defs untouched, both ends clamp - and the
  preview restacks at once. No arrow past its end: the top row hides its
  up, the bottom row its down, a single-layer drink both.
- Paying for the squares: the amount reserve drops 200 -> 140 virtual
  (the widest amount, "240 ml" / "8.1 oz", is ~132); the name column
  still holds the widest preset name.
- geometry_check gains REORDER (swaps, clamps, no-ops, validation):
  432 passed, 0 failed.

**Safety status:** no write behavior exists in this version beyond the
standing one. The order rides the draft to the same two confirmed saves;
`plugins save_settings` appears exactly once, inside `_persist` (six
callers, unchanged).

## v1.4.0 - 2026-09-03 - Pass 34: edit existing custom layers

Base: tablet-verified v1.3.0. Owner request: "add editing for existing
custom layers".

- A custom layer's editor row shows a gold pen after its name (the name
  budget shrinks by the pen slot on those rows only) and an invisible tap
  over dot + name; preset rows show and arm neither. The tap reopens the
  pass-33 form PREFILLED - name, ml/g, matching swatch ringed - retitled
  "Edit ingredient", its button relabelled "Save" (bare dbutton tag).
- Save swaps that def IN PLACE: the layer list and the amount are
  untouched; the preview recolours immediately (the render key already
  carries the defs). A def colour outside the twelve swatches prefills
  ringless and survives a save that never tapped a swatch. Cancel resets
  the edit state, so "+ Custom..." always opens a clean form.
- geometry_check: five new CUSTING assertions (prefill, in-place save,
  off-swatch colour round-trip, preset row no-op): 426 passed, 0 failed.

**Safety status:** no write behavior exists in this version beyond the
standing one. The edited def rides the draft to the same two confirmed
saves; `plugins save_settings` still appears exactly once, inside
`_persist` (six callers, unchanged).

## v1.3.0 - 2026-09-03 - Pass 33: custom ingredient layers

Base: tablet-verified v1.2.0. Owner request: a typed custom ingredient
per layer, a g/ml unit for it, and a picked colour.

- **Data.** A drink dict MAY carry `custom_ings` (`c<N>` -> `{name color
  unit}`), referenced from `layers` like a preset id; the defs live
  inside the drink and travel with copies. No role, no flags, so tabs,
  the ratio's coffee side and 2-shot doubling are untouched. A `g`
  layer's number draws and counts exactly as an ml would; only its label
  is "N g", under either display unit (mass does not convert to oz).
- **Write path (full statement, write-shape change).** No new writer.
  The defs reach `settings(custom)` only inside the draft, through the
  existing confirmed `editor_save_custom` / `editor_save_copy` (persist
  callers 4 and 5 of the standing six). `validate_drink` validates the
  defs (id `c<N>`, name 1..24, `#rrggbb`, unit ml|g); the load still
  drops an invalid custom drink with a NOTICE and writes nothing;
  `_clean_draft` prunes defs the layers no longer reference. `plugins
  save_settings` still appears exactly once, inside `_persist` (six
  callers, unchanged).
- **UI.** The palette's last chip, "+ Custom...", opens a new editor
  mode: name entry (keyboard-safe top zone), ml/g capsule, 12 swatches
  with a selection ring, Add layer / Cancel. All display sites resolve
  through `ing_prop`; `_cup_render`'s key carries the defs. Also folds
  in a 1-line pass-32 consistency fix (the sub-2 px shadow grows DOWN).
- geometry_check gains the CUSTING section: 421 passed, 0 failed.

## v1.2.0 - 2026-09-03 - Pass 32: drawn pills, own press flash, shadow under the glass

Base: tablet-verified v1.1.2. Three owner notes in one pass.

- **The wrong horizontal line on the header pills.** dui paints a
  round_outline dbutton with two painters (fill, dui.tcl:10118; outline)
  whose silhouettes disagree at a full pill's radius: the edge's straight
  top and bottom runs sat inside the fill and ended before its arcs. The
  tab pills are drawn now - `pill_shape`: ONE polygon carrying face and
  edge (the capsules' own `_capsule_points`), a dtext label, an invisible
  tap rect. The dm_pill aspects are removed.
- **Press effect** for the pills and both capsules: `_flash_pill` /
  `_flash_seg` tint the tapped control's polygon with the primary press
  tone from the tap's own command; `_press_restore` repaints FROM STATE
  after 120 ms through `_paint_controls`, which the page refreshes now
  use too - one code path, so the flash cannot stick (the pass 31 rule).
- **The cup shadow sat behind tall glasses** (>300 ml, and hero cups):
  the ellipse's BOTTOM was pinned to the cup zone. `vessel_geometry` now
  reserves the shadow's strip below the floor (the mock viewBox's own
  bottom margin) and `cup_shadow_box` pins the TOP to the floor.
  Height-bound art is ~6% shorter, as in the mock.
- geometry_check: PRESS/RADII/CONTRAST follow the pills' new form, SHADOW
  gains top-on-floor and full-height assertions: 407 passed, 0 failed.

**Safety status:** no write behavior exists in this version beyond the
standing one. Paint and press feedback only; `_persist` still has exactly
six callers, `plugins save_settings` appears exactly once, inside it.

## v1.1.2 - 2026-09-03 - Pass 31: press flash

Base: tablet-verified v1.1.1. Found on the tablet during the v1.1.1 review,
not by the headless net: after any tap, a tab pill kept the selected gold
outline and dark label on its unselected dark body (an unreadable label),
and a tapped capsule half kept an opaque grey rectangle over its own label
until the page was reloaded.

- **Cause, read in the core.** The flash restores the fill captured at
  CREATION, `after $ms $can itemconfigure $tag -fill $fill`
  (dui.tcl:9225), so it lands after the tap's own command has repainted.
  On `dm_pill`, `round_outline` had baked the aspect's OFF fill into
  press_args (dui.tcl:10120), wiping the gold `_style_pill` had just set.
  On an invisible tap rect (`-fill {}`, dui.tcl:10186) `after` concatenates
  its arguments, the empty word is lost, the restore degrades to a query -
  and the flash colour is permanent.
- **Fix.** `pressfill` dropped from the `dm_pill` aspect and from the five
  invisible tap-rect call sites: the main and detail unit capsules, the
  detail size capsule, the editor ingredient rows, the vessel tiles.
  `dm_btn` and `dm_btn_primary` keep theirs (static fills, correct
  restore), so every real button still flashes.
- The press rule is recorded in `_apply_palette`; `PRESS` in
  geometry_check is rewritten from coverage into that rule: 404 passed,
  0 failed. This closes the v1.0.1 open press-flash item by removal.

**Safety status:** no write behavior exists in this version beyond the
standing one. Paint and press feedback only: no command, navigation or
write path is touched, `_persist` still has exactly six callers, and
`plugins save_settings` still appears exactly once, inside it.

## v1.1.1 - 2026-09-03 - Pass 30: cup shadow

Base: tablet-verified v1.1.0. Owner note: "add a shadow under the cup just
like the mockup". The mock's `cup()` draws
`<ellipse cx=cx cy=bot+3 rx=bw/2+10 ry=3 fill=rgba(0,0,0,.35)>` before the
bowl; our cups had nothing under them.

- **One pooled oval per cup**, `<tag>_shadow`, created FIRST in `draw_cup`
  so the stem, handle, bowl, layers and stroke all stack over it - the
  order the mock's SVG uses. It is placed from the same cached
  `_cup_render` dict `update_cup` already drives (one more cached move and
  fill per cup; TIMING unchanged), joins `cup_tags` / `_slot_tags` so a
  hidden slot hides it, and is registered for retheme.
- **Geometry** (`cup_shadow_box`, pure): the ellipse's top is the cup's
  floor - the FOOT for the coupe, with the foot's half width - it is
  `2 x 3` design units tall and `10` units wider than the floor on each
  side, all through the fit's own `s`. Both are clamped to the cup's ZONE:
  our design box has no bottom margin where the mock's viewBox has eight
  units, so a height-bound glass would otherwise reach within 1.5 units of
  the tile's name line. Such a glass keeps the full ellipse and slides up
  to end on the zone's floor. On a tile the shadows run 58 - 108 px wide
  and 5 - 9 px tall; on the detail hero 217 - 340 x 19 - 36 px.
- **Colour**: Tk has no alpha, so the shadow is the surface it lies on
  taken 0.35 towards black. One token per mock card family
  (`cup_shadow_tile` `#1c1716`, `cup_shadow_card` `#1a1514`,
  `cup_shadow_hero` `#1b1715`, each off that family's own ramp at the
  shadow's row) plus `cup_shadow` `#1d1917`, the flat `card_fill` variant.
- Nothing else moved. geometry_check gained a SHADOW section: 403 passed,
  0 failed.

**Safety status:** no behavior or write changes. Paint only: no command,
no navigation and no write path is touched; the plugin still writes only
its own settings.tdb through the single `_persist` proc with its six
confirmed callers, and `plugins save_settings` still appears exactly once,
inside it. Tablet verification pending.

## v1.1.0 - 2026-09-03 - Pass 29: gradient glow on the cards

Base: tablet-verified v1.0.1. Owner note on the detail page: "the cards in
detail page need a gradient glow" - the cards read almost flat because one
shallow vertical ramp was shared by every card. Three changes, all inside
the card photos: paint only, no behavior or write changes.

- **Diagonal ramp.** `glass_photo` paints the mock's real 165-deg
  direction: the colour at (x, y) follows
  `t = (0.906 * yn + 0.423 * xn) / 1.329`, lightest at the top-left,
  darkest at the bottom-right. A row is up to 7 runs of equal quantised
  colour (`_glass_runs`, 18 ramp steps - finer than the 17 of 255 the
  whole ramp spans on this page), so the seven photos cost 16,635 `put`
  calls (budget 20,000) and 3,869,616 bytes, unchanged.
- **Per-family whites.** `mock_glass_kinds`: tiles .12 -> .045, detail and
  editor cards .10 -> .035, hero .11 -> .04, each with its own highlight
  (.26 / .22 / .26). `glass_card` takes a `kind` and it is part of the
  photo cache key (`<w>x<h>x<r>x<kind>`); the sizes are distinct per
  family anyway, so it is still seven photos.
- **Glow band.** Row 1's single lit line became rows 1..G (G = 6 tiles,
  10 hero and cards) fading from the highlight white to the plain row
  colour. Row 0, row h - 1 and the two side rails stay exactly as v0.13.3
  baked them.
- **The drop shadow is dropped**, by the pass's own fallback rule: a Tk
  photo has no per-pixel alpha, so it needs a page-coloured margin of
  S = 10 / 14 px, which takes the seven photos from 967,404 to 1,066,622
  px = 4,266,488 bytes, over the 4,194,304 budget.
- Nothing moved: every photo item is still at its v1.0.1 corner and size
  (asserted), so tokens, tap rects and text are untouched. geometry_check
  gained a GLOW section: 391 passed, 0 failed.

**Safety status:** no write behavior exists in this version beyond the one
already shipped: the plugin writes only its own settings.tdb through the
single `_persist` proc with its six confirmed callers; one
`plugins save_settings` call site; no SQL, no history file access;
presets.tcl is never written at runtime.

## v1.0.1 - 2026-09-03 - Pass 28: touch-UX audit

Base: tablet-verified v1.0.0. An audit against a touch-UX guideline set
(touch targets >= 44/48 px, pressed feedback on every tappable element,
text contrast >= 4.5:1) found three misses; this pass fixes exactly
those. No behavior or write changes.

- **Pressed feedback.** The three shared aspects carry a `pressfill`
  (core dui.tcl:10288 -> 9179), so every styled button flashes for
  120 ms: ghost buttons and pills to white .12 over their own fill,
  the gold primary to the gold 15% of the way to gold-ink. Labels keep
  their colour (no `-label_pressfill`). The invisible tap rects over the
  drawn capsules, the ingredient rows and the vessel tiles get the same
  options explicitly; the tile and star rects stay bare on purpose.
  `-pressoutline` is documented in the core but never read there.
- **Touch targets.** The star's tap box is 96 x 96 virtual (50 x 48
  physical px, was 50 x 42); the drawn star does not move and the tile's
  two rects re-partition around it. Header pills and capsule halves get
  dui's `-tap_pad` (50 px tall taps, drawing untouched) and the gap
  between neighbouring tab pills goes from xs to sm (6.3 -> 10.5 px).
- **Contrast.** New derived `ink_3_text` (#a59789, the smallest blend of
  c_ink_3 towards c_ink clearing 4.5:1 on both card surfaces) replaces
  c_ink_3 on the Method card's step numbers: 3.8:1 -> 5.2:1 on the card
  body. The tile star's outline keeps c_ink_3 (a mark, 3.8:1 >= 3:1).
- geometry_check gained PRESS / TOUCH / CONTRAST (12 assertions over the
  three real page setups). 382 passed, 0 failed.

**Safety status:** no write behavior was added or changed in this
version. The plugin still writes only its own settings.tdb through the
single `_persist` proc with its six confirmed callers; one
`plugins save_settings` call site; no SQL, no history file access;
presets.tcl is never written at runtime.

## v1.0.0 - 2026-09-03 - Release

Base: tablet-verified v0.13.3. The owner signed off the design-mock goal
after the v0.13.3 captures; this release changes the version and the
docs only. The code, presets and shipped PNG backgrounds are byte-identical
to v0.13.3.

**Safety status:** no change to any write behavior. The plugin writes only
its own settings.tdb (keys unit / favorites / hidden / custom) through the
single `_persist` proc with its six confirmed callers; one
`plugins save_settings` call site; no SQL, no history file access;
presets.tcl is never written at runtime.

## v0.13.3 - 2026-09-03 - Pass 26: continuous card corners

Base: tablet-verified v0.13.2. Owner note on the v0.13.2 captures: "fix
the notch at the tile corners".

- Cause: a card was TWO shapes. The photo's carved corner is a true
  circle; the edge drawn over it was a `-smooth 1` polygon, whose corner
  is a shallow diagonal, not an arc. A dark wedge of page showed between
  them (`out/final/final2_main_p1.png`).
- `glass_photo` now bakes the rim: per row the first and last painted
  pixel of the circular span are the edge colour (white .17 over that
  row's colour), rows 0 and h - 1 are edge colour across their spans,
  row 1 is the highlight (white .26). Carve back at exactly `r`.
- `glass_card` draws no outline polygon for a card that has a photo, so
  `<tag>_body` exists only on the flat fallback (the editor's confirm
  panel). `_slot_tags`, `_slot_frame_tags` and the editor's vessel-mode
  tag list dropped their `_body` entries, so nothing looks up a tag that
  no longer exists.
- GLASS rewritten around a multi-put recording stub (+4 assertions).
  Geometry check 370/370. Same 7 photos, same 3.69 MB.

**Safety: no behavior or write changes.** One `plugins save_settings`
inside `_persist`, six callers; no SQL, no file delete/rename;
`presets.tcl` untouched. Files: `DrinkMenu.tcl`,
`tools/geometry_check.tcl`, `plugin.tcl`, docs.

## v0.13.2 - 2026-09-03 - Pass 25: hero inset all round; photo corners

Base: tablet-verified v0.13.1. Two owner notes on the v0.13.1 captures.

- Detail hero and editor preview cup boxes now keep `card_pad_x` from
  every card edge, including the bottom against the caption line
  (`det_garnish_top`, `ed_cap_top`). Height-bound vessels get equal air
  above and below; `det_label_bottom` keeps the text rule.
- `glass_photo` carves the transparent corner at `r + 2` px so no lit
  pixel pokes outside the smoothed outline.
- INSET grows to 7 assertions, GLASS +1. Geometry check 367/367.

**Safety: no behavior or write changes.** One `plugins save_settings`
inside `_persist`, six callers; no SQL, no file delete/rename;
`presets.tcl` untouched. Files: `DrinkMenu.tcl`,
`tools/geometry_check.tcl`, `plugin.tcl`, docs.

## v0.13.1 - 2026-09-02 - Pass 24: hero inset and card corners

Base: tablet-verified v0.13.0. Two owner notes on the v0.13.0 captures.

- Rule stated once: the cup keeps the same inset from every card edge
  that the card's text keeps. `det_cup_x1` moves from `xs` to
  `card_pad_x`; the bowl budget goes 674 -> 650, handled cups shrink
  about 1.6% of card height, tall glasses unchanged.
- Glass photo row 0 highlight now spans `r .. w - r` only, removing the
  light tick at the top corners.
- New INSET section (5); GLASS updated. Geometry check 364/364.

**Safety: no behavior or write changes.** Same write path as v0.13.0.
Files: `DrinkMenu.tcl`, `tools/geometry_check.tcl`, `plugin.tcl`, docs.

## v0.13.0 - 2026-09-02 - Pass 23: the mock's details

Base: tablet-verified v0.12.1. The owner's eight misses against the mock.

- Tile cup fitted into a centred 62% x 64% box; ml badge a full crema
  pill top-right; star smaller, top-left; header band centred on 168;
  header buttons the mock's 46-ref pill with measured widths.
- Card faces are Tk photos with the mock's gradient (`glass_photo`, one
  per distinct size, made at setup, corners transparent; 7 photos,
  3.69 MB). Editor confirm panel stays flat. Flat-rect fallback if a
  platform refuses photos.
- Radii: cards 24 ref, hero 29, bar buttons 19, pills height/2; inset
  top highlight line on bar buttons. `bar_done` and `ed_done` become
  primary.
- New GLASS / HEADER / BADGE / RADII / PRIMARY sections. 358/358.

**Safety: no behavior or write changes.** Same write path. Files:
`DrinkMenu.tcl`, `tools/geometry_check.tcl`, `plugin.tcl`, docs.

## v0.12.1 - 2026-09-02 - Pass 22: drawn star, real fill

Base: tablet-verified v0.12.0. The favorited star was gold but hollow:
the app loads only Font Awesome Regular, which cannot draw U+F005 solid.

- The tile star is now a canvas polygon (outer radius 23 virtual, inner
  10). On: crema fill and outline. Off: empty fill, `c_ink_3` outline.
  `_set_fill` writes fill and outline in one `itemconfigure`.
- The Solid-900 font load attempt and its tokens are removed. The star
  tab pill and the detail Favorite button are untouched.
- New STARFILL section (8). 316/316.

**Safety: no behavior or write changes beyond the star's shape.** Same
`toggle_favorite` -> `_persist` path. Files: `DrinkMenu.tcl`,
`tools/geometry_check.tcl`, `plugin.tcl`, docs.

## v0.12.0 - 2026-09-02 - Pass 21: tappable favorite star

Base: tablet-verified v0.11.0. Owner decision: a star top-right of the
tile; tapping it toggles the favorite.

- A tile's tap area is now two rects plus the star's own rect; the
  three partition the tile exactly, so no coordinate test is needed.
  The star rect calls `star_tap` -> `toggle_favorite`.
- Badge and pen move down the reserved column; cup zone unchanged.
- New STARTAP section (12), TILECUP +4. 308/308.

**Safety: no new write capability.** The star is a new entry point to
the existing `toggle_favorite` -> `_persist favorite` caller; six
callers unchanged. Files: `DrinkMenu.tcl`, `tools/geometry_check.tcl`,
`plugin.tcl`, docs.

## v0.11.0 - 2026-09-02 - Pass 20: the mock's warm brown look

Base: tablet-verified v0.10.5. Owner decision: the plugin's pages take
the mock's warm brown gradient regardless of the Lumen theme.

- Background is a pixel-exact PNG per physical resolution
  (`1340x800`, `1280x800`, `2560x1600`, made by `tools/make_bg.py`),
  loaded once, matched by width (Tk reports 1340x736 on the tablet).
- `_apply_palette` now derives every colour from the mock's `:root`
  set; the Lumen light branch is gone. WCAG contrast asserted.
- New WARMLOOK section. 293/293.

**Safety: no behavior or write changes.** The only new file access is a
read of the plugin's own `bg.png`. Files: `DrinkMenu.tcl`, three PNGs,
`filelist.txt`, `tools/make_bg.py`, `tools/geometry_check.tcl`,
`plugin.tcl`, docs.

## v0.10.5 - 2026-09-02 - Pass 19: dimmed handle ring under the labels

Base: tablet-verified v0.10.4. The part of the hero cup's handle ring
that lies under the label column is ghosted with a pooled arc
(`hero_cup_handle_dim`, colour `ring_dim`), computed per refresh from
the ring's bbox and the label column x. Handle-less vessels hide it.
New DIMRING section (7), SMOKE +1. 285/285.

**Safety: no behavior or write changes.** Files: `DrinkMenu.tcl`,
`tools/geometry_check.tcl`, `plugin.tcl`, docs.

## v0.10.4 - 2026-09-02 - Pass 18: labels may overlap the handle

Base: tablet-verified v0.10.3. Owner decision: detail labels may overlap
the cup handle as the mock draws them. `hero_cup_box` fits the bowl, not
bowl plus handle, so handled cups grow (demitasse 0.452 -> 0.559 of card
height); the per-vessel box is part of the render-cache key. HEROCUP
rebuilt. 277/277.

**Safety: no behavior or write changes.** Files: `DrinkMenu.tcl`,
`tools/geometry_check.tcl`, `plugin.tcl`, docs.

## v0.10.3 - 2026-09-02 - Pass 17: Save as copy back on fresh copies

Base: tablet-verified v0.10.2. Save as copy shows whenever Save does,
including unsaved Copy & edit and + New drink drafts; Delete alone still
waits for a first save. Reverts the v0.9.0 rule. SAVECOPY +1. 271/271.

**Safety: no change to any write behavior**; same confirm card and
`_persist` caller. Files: `DrinkMenu.tcl`, `tools/geometry_check.tcl`,
`plugin.tcl`, docs.

## v0.10.2 - 2026-09-02 - Pass 16: wider hero card

Base: tablet-verified v0.10.1. Hero card 0.40 -> 0.47 of the content
width; the cup box takes every gained unit (large cup +33%). 0.47 is
the widest that leaves the Method column room for the longest preset
step untruncated; the pass's 0.52 and 0.40-of-height targets are proven
unreachable in the check. Editor page untouched. 270/270.

**Safety: no behavior or write changes.** Files: `DrinkMenu.tcl`,
`tools/geometry_check.tcl`, `plugin.tcl`, docs.

## v0.10.1 - 2026-09-02 - Pass 15: final mock comparison

Base: tablet-verified v0.10.0. Design goal reached. Hero cup box takes
the interior left of a fixed label column; tile names try the primary
font, then the caption font, then ellipsise (`fit_tile_name`,
`_set_font`). The 55%-hero-height target is proven unreachable. New
HEROCUP and TILENAME sections. 267/267.

**Safety: no behavior or write changes.** Files: `DrinkMenu.tcl`,
`tools/geometry_check.tcl`, `plugin.tcl`, docs.

## v0.10.0 - 2026-09-02 - Pass 14: method steps

Base: tablet-verified v0.9.0. Design review item B1.

- All 43 presets gain a `steps` list (2-4 one-line imperative steps,
  ASCII, max 50 chars). `clean_steps` repairs bad values on load with
  no write. The `sized_drink` key collision on `steps` renamed to
  `size_ups`.
- Detail page: the chips card is a fixed two-row card; a new Method
  card below it shows up to 4 pooled step lines or "No method saved."
  `chip_fit` ellipsises chip names only when a custom drink overflows.
- New STEPS / METHOD / CHIPFIT sections. 254/254.

**Safety: no write behavior changes.** Steps are preset data carried
into custom copies by the existing confirmed `editor_save_custom` /
`editor_save_copy` path, exactly as the garnish is; six callers, one
`plugins save_settings`. Files: `presets.tcl`, `DrinkMenu.tcl`,
`tools/geometry_check.tcl`, `plugin.tcl`, docs.

## v0.9.0 - 2026-09-02 - Pass 13: + New drink and chevrons

Base: tablet-verified v0.8.0. Design review item A5 and the chevrons.

- Menu bottom bar: Done | + New drink | Hidden (N) left, Prev / Next
  right. `new_drink_tap` opens the editor on a fresh unsaved draft
  (`new_draft`); Save stays hidden until it validates.
- `edit_origin` records which page opened the editor so leave sites
  return there; no new guard or fallback bookkeeping.
- Prev/Next carry a chevron as a second label (`-label1`) in the icon
  font. New NEWDRINK (14) and CHEVRON (5) sections. 227/227.

**Safety: no new write capability.** + New drink is a new entry point
to the existing confirmed custom save; six callers unchanged. Files:
`DrinkMenu.tcl`, `tools/geometry_check.tcl`, `plugin.tcl`, docs.

## v0.8.0 - 2026-09-02 - Pass 12: visual alignment with the design mock

Base: tablet-verified v0.7.1. Design review items A1, A2, A3, A7, B3.
Tile cup zone becomes the tile interior minus one reserved right column
(demitasse 0.18 -> 0.437 of tile width); card body and edge derived
from the page background; two-way segments drawn as one capsule with
`pill_radius = btn_h / 2`; ml badge gets a crema border; `dm_btn_primary`
aspect on the detail Edit and editor Save. New TILECUP and PILLS
sections. 208/208.

**Safety: no behavior or write changes.** Files: `DrinkMenu.tcl`,
`presets.tcl` (tile_scale ladder), `tools/geometry_check.tcl`,
`plugin.tcl`, docs.

## v0.7.1 - 2026-09-02 - Pass 11: Bugfix, editor title overlap

Base: tablet-verified v0.7.0. The editor's name entry sat on the title;
`ed_entry_x` is now `left_x + ed_title_w + lg`. EDHEADER +3. 189/189.

**Safety: no change to any write behavior.** Files: `DrinkMenu.tcl`,
`tools/geometry_check.tcl`, `plugin.tcl`, docs.

## v0.7.0 - 2026-09-02 - Pass 10: Polish (v1.0-candidate)

Base: tablet-verified v0.6.2. Button radius 12 -> 16 ref (Lumen's
`radius_sm`); ratio names wrap to a second caption line
(`_wrap_names_2line`); Custom tab empty-state copy; light-theme
contrast fix via a derived `crema_text` colour for every crema-as-text
site; one per-tap NOTICE removed. RATIOWRAP +2. 186/186. Marked
v1.0-candidate pending owner sign-off.

**Safety: no behavior or write changes.** Files: `DrinkMenu.tcl`,
`tools/geometry_check.tcl`, `plugin.tcl`, docs.

## v0.6.2 - 2026-09-02 - Pass 9: menu responsiveness

Base: tablet-verified v0.6.1. Owner report: tab switch and paging lag.
Measured on the tablet: 584 ms -> 6 ms median per refresh. Canvas ids
cached once per page (`_ids`); `_set_vis` replaces per-item dui
show/hide and maintains `st:hidden` itself; geometry, render, fit and
text caches; `_retheme` and `_style_pill` use cached ids. Timing lines
stay behind `debug_timing` (default 0). TIMING and SMOKE checks added.
184/184.

**Safety: no write behavior changes**; internal rendering path only.
Files: `DrinkMenu.tcl`, `tools/geometry_check.tcl`, `plugin.tcl`, docs.

## v0.6.1 - 2026-09-02 - Pass 8: no alcoholic drinks

Base: tablet-verified v0.6.0. Owner decision. Removed four alcoholic
presets, four spirit ingredients, the `spirited` group and the Irish
glass; 43 presets / 19 ingredients / 7 vessels remain. Custom drinks
using a removed ingredient are dropped on load with a NOTICE, no write.
Editor vessel pool token `ed_ves_pool` follows the vessel count.
179/179.

**Safety: no write behavior changes.** `presets.tcl` edited as source
data only. Files: `presets.tcl`, `DrinkMenu.tcl`,
`tools/geometry_check.tcl`, `plugin.tcl`, docs.

## v0.6.0 - 2026-09-02 - Pass 7: presets are read-only for the user

Base: tablet-verified v0.5.2. Owner decision: presets can never be
edited or overwritten; editing one always creates a custom copy. The
v0.5.0 per-preset override capability is removed. (Write-capability
change: documented in full.)

- **Data.** The `overrides` settings key is gone from defaults,
  `_validate_settings` and every reader. A stale `overrides` key in
  `settings.tdb` is dropped from memory on load with one NOTICE and
  never written back; nothing is migrated. `get_drink id` is custom if
  present, else preset.
- **Detail page.** On a preset the edit button reads Copy & edit and
  opens the editor on a fresh unsaved custom copy (id `custom_<epoch>`,
  name "<preset> copy"); on a custom drink it reads Edit. Only custom
  drinks carry the pen marker.
- **Editor.** `edit_kind` is always custom. Reset to preset and the
  `override_save` / `override_reset` confirmations are removed. Bottom
  bar: Cancel | Delete | Save as copy | Save; Delete hidden until the
  draft has been saved once. `edit_source_id` carries the garnish
  across a copy.
- **Write path.** `_persist` callers are exactly 3 + 3: `set_unit`,
  `toggle_favorite`, `toggle_hidden`; `editor_save_custom`,
  `editor_save_copy`, `editor_delete_custom`. Each editor caller is
  reachable only from a confirm card's confirming button (or the first
  Save of a Copy & edit draft). `plugins save_settings` appears exactly
  once, inside `_persist`.
- Headless: stale-overrides drop with zero writes; the full Copy & edit
  flow; every override case removed. 179/179.

**Safety status:** writes `unit` / `favorites` / `hidden` / `custom`
via `plugins save_settings` behind confirmations; presets are read-only
and can never be edited or overwritten; `overrides` is read only to be
dropped, never written; no other file access.

## v0.5.2 - 2026-09-02 - cosmetic fixes + headless layout coverage

Base: v0.5.1. Palette pool now equals the ingredient count (the 24th
slot logged "no canvas tag matches" on every mode switch); startup log
line names the editor writes. Headless check now runs `_init_layout`
with stubs and checks page-critical tokens. 171/171.

**Safety: no change to any write behavior.** Files: `DrinkMenu.tcl`,
`tools/geometry_check.tcl`, `plugin.tcl`, docs.

## v0.5.1 - 2026-09-02 - Bugfix: layout init failed on the tablet

Base: v0.5.0. Found by the DevBridge loop on first boot: the editor
sub-block of `_init_layout` read `det_*` tokens before they were
assigned, so `preload` returned "" and the plugin had no pages. The
block now sits after the last detail token; no value changed.

**Safety: no change to any write behavior.** Files: `DrinkMenu.tcl`,
`plugin.tcl`, docs.

## v0.5.0 - 2026-09-02 - Pass 5: custom drinks, overrides, editor

Base: tablet-verified v0.4.1. (Write-capability change: documented in
full. The override half was removed again in v0.6.0.)

- **Data model.** `settings(custom)` (id -> drink, ids `custom_<epoch>`
  with `_2`... on collision, `source custom`, `group custom`) and
  `settings(overrides)` (preset id -> drink, `source override`).
  `get_drink id` returns override, else custom, else preset; every
  display and logic read goes through it. `validate_drink` enforces
  name (non-empty, <= 24 chars), vessel, 1-6 layers, known
  ingredients, whole ml >= 5, a coffee-role layer and the capacity.
  `_validate_settings` drops invalid custom/override entries on load
  with a NOTICE, no write.
- **Detail bar.** Favorite, Hide, Edit, then chevron Prev/Next.
- **Editor page `DrinkMenu_edit`** (stacked level 3): name entry in
  the header with a keyboard Done button; live preview card; right
  column in four in-page modes (`layers`, `palette`, `vessel`,
  `confirm`) switched by exact-tag show/hide of pooled groups. Bottom
  bar: Cancel | Reset to preset or Delete | Save as copy | Save
  (Save/copy hidden while the draft fails validation). Steps 5 ml or
  0.25 oz, clamped to remaining capacity.
- **Keyboard.** `dui platform hide_android_keyboard` on every mode
  switch and bottom-bar action; the entry and Done sit in the top zone.
- **Write path.** `_persist` unchanged; callers now 3 + 5
  (`editor_save_override`, `editor_save_custom`, `editor_save_copy`,
  `editor_delete_custom`, `editor_reset_override`), each reachable only
  from the confirm card's confirming button. Deleting a custom drink
  also removes it from favorites and hidden. Cancel with a dirty draft
  asks "Discard changes?" and writes nothing.
- Headless: every `validate_drink` rule, the five flows counting
  exactly one save each, cancel-dirty and invalid-save writing nothing,
  load validation, id collision. 167/167.

**Safety status:** writes `custom` and `overrides` via `plugins
save_settings`, each behind an explicit confirmation; `unit` /
`favorites` / `hidden` unchanged; presets remain read-only; no other
file access.

## v0.4.1 - 2026-09-02 - bugfix: header row overlapped the title

Found on the tablet: the seven-pill row ran over the title. The row
was budgeted in ref px at the height scale (2.0) but the tablet maps
width at 1.91, so it landed 4.7% wider. Pill width 96 ref, gap xs, unit
segment 64 ref; the check now computes the row start in physical px.
Lesson added to CLAUDE.md.

**Safety status:** unchanged from v0.4.0. Files: `DrinkMenu.tcl`,
`tools/geometry_check.tcl`, `plugin.tcl`, docs.

## v0.4.0 - 2026-09-02 - Pass 4: persistence, favorites, hide

Base: tablet-verified v0.3.1. **First settings-write version.**
(Write-capability change: documented in full.)

- **Write path.** One proc, `_persist reason`, runs
  `_validate_settings` (unit in ml/oz; favorites and hidden are lists
  of existing drink ids, duplicates and unknown ids dropped with a
  NOTICE; non-list values reset) and then `plugins save_settings
  DrinkMenu` inside a catch, logging "DrinkMenu saved settings:
  <reason>" or an ERROR. Exactly three callers, each a single user
  tap: `set_unit` (menu or detail unit toggle), `toggle_favorite`
  (detail Favorite button), `toggle_hidden` (detail Hide/Unhide
  button). The same validation runs once in preload after `plugins
  load_settings`, without writing.
- **Favorites.** `settings(favorites)` id list; detail Favorite /
  Favorited button; crema star on favorited tiles; the star tab pill
  is real; empty-state caption.
- **Hide / unhide.** `settings(hidden)` id list; hidden drinks leave
  every tab; the menu's Hidden (N) button opens the `hidden`
  pseudo-tab; unhiding stays there or falls back to All when empty.
- **Custom** tab pill added as an empty scaffold. **Unit** persists on
  tap. `visible_drinks` cache invalidated on every favorites/hidden
  change.
- Headless: validation cases, round trip through the core's settings
  file format, one save per tap for all three callers, invalid inputs
  write nothing. 112/112.

**Safety status:** first settings-write version. Writes only `unit`,
`favorites`, `hidden` via `plugins save_settings` behind single user
taps; no other file access; presets remain read-only.

## v0.3.1 - 2026-09-02 - Pass 3.1: coffee-first ratio, 2-shot doubling

Base: tablet-verified v0.3.0. `drink_ratio` lists coffee-role layers
first, then the rest in layer order. `sized_drink` doubles only the
coffee layers and steps the vessel up at most twice; 5 of 47 presets
still overflow at 2 shots. Segmented control relabeled 1 shot | 2
shots. 91/91.

**Safety status:** unchanged, no settings writes. Files:
`DrinkMenu.tcl`, `tools/geometry_check.tcl`, `plugin.tcl`, docs.

## v0.3.0 - 2026-09-02 - Pass 3: detail page

Base: tablet-verified v0.2.1. Vessels gain `size_up`, ingredients gain
`role` (additive data). New fpdialog page `DrinkMenu_detail`: header
with unit toggle and Single | Double, hero card with the full-size cup
and a pooled label column with leaders, totals card with ratio,
ingredients chips card, Back | Prev | Next through `_return_to_page`.
Tile tap opens it. Theme registry becomes per page. 84/84.

**Safety status:** no settings writes; `presets.tcl` read-only; no
data access outside the plugin folder. Files: `presets.tcl`,
`DrinkMenu.tcl`, `tools/geometry_check.tcl`, `plugin.tcl`, docs.

## v0.2.1 - 2026-09-02 - bugfix: last page showed a stale twelfth tile

dui's `<tag>*` is a literal group tag on compound widgets, not a glob,
so `dui item hide tile11_*` matched nothing. `_slot_tags` now lists
every exact tag a slot owns and `_show_slot` handles them one by one.

**Safety status:** unchanged from v0.2.0. Files: `DrinkMenu.tcl`,
`plugin.tcl`, docs.

## v0.2.0 - 2026-09-02 - Pass 2: presets + menu grid + tabs + unit toggle

New shipped `presets.tcl` (23 ingredients, 8 vessels, 47 drinks; sourced
inside a catch with a visible failure caption). Derived data helpers,
stem/foot vessels with per-vessel `tile_scale`, the menu page with
title, ml | oz toggle, five tab pills, a 4 x 3 recycled tile pool,
Done left and Prev/Next right. Unit seeds once from settings and is
never written back.

**Safety status:** no settings writes; `presets.tcl` read-only; no data
access outside the plugin folder.

## v0.1.0 - 2026-09-02 - Pass 1: loadable plugin + cup renderer

First version, tablet-verified. One fpdialog page proving the cup
renderer (vessel profile slices, fixed item pool), the shared layout
system, the palette read at show time and MaintenanceTracker's
navigation mechanism.

**Safety status:** no settings writes, no data access of any kind.
