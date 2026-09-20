#
# Drink Menu -- DE1app plugin manifest
#
# v0.6.0 (Pass 7): presets are read-only for the user; editing a preset
# always creates a custom copy (the old per-preset "override" is gone).
# Preset data lives in presets.tcl (read-only, never mutated).
#
# v0.6.1 (Pass 8): owner decision, no alcoholic drinks or ingredients in
# the plugin. Removed 4 presets (irish_coffee, carajillo,
# espresso_martini, caffe_corretto), 4 ingredients (whiskey, liqueur,
# vodka, grappa), the irish_glass vessel and the spirited group; 43
# presets / 19 ingredients / 7 vessels remain. Data-only change in
# presets.tcl; a custom drink still using a removed ingredient is
# dropped on load exactly as any other invalid custom drink is (one
# NOTICE naming it, no write). No write-path change.
#
# v0.6.2 (Pass 9): menu responsiveness. The grid refresh no longer goes
# through `dui item get/config/show/hide` for every tag (~540 calls per
# refresh, ~590 ms on the tablet); canvas ids are resolved once and the
# canvas is driven directly, with caches for vessel geometry, physical
# layer polygons and fitted names. No behavior, layout or write change.
# Timing NOTICE lines stay in the code behind
# `::plugins::DrinkMenu::debug_timing` (default 0).
#
# v0.7.0 (Pass 10): polish, v1.0-candidate. Button radius raised to
# match Lumen's pill look (single shared aspect, so every button changes
# together); tile cup/name/chip proportions verified at the spec 62%;
# the detail page's ratio-names line wraps onto a pooled second caption
# line instead of truncating (four-name drinks like Borgia); hidden-view
# pluralization confirmed from Pass 5; Custom tab empty-state copy names
# the "Copy & edit" path; a light-theme contrast audit found `c_crema`
# unreadable as small/caption TEXT on Lumen's light glass/chip surfaces
# and added a `crema_text` derived color (dark theme's crema-as-text is
# untouched, tablet-verified); one leftover per-tap NOTICE removed (log
# hygiene). No behavior, layout-breaking or write change; no new procs
# beyond the pooled second caption line.
#
# v0.7.1 (bugfix): the editor's name entry started at a fixed 240 ref px
# and sat on top of the title "Edit custom drink" (visible in the v0.6.2
# and v0.7.0 tablet captures). The entry now starts after a reserved
# title width plus one lg gap (`L(ed_title_w)`, `L(ed_entry_x)`); the
# headless check asserts the title/entry/Done order. Layout token only;
# no behavior or write change.
#
# v0.8.0 (Pass 12): visual alignment with the owner's design mock, five
# items, no behavior or write change. A1 the tile cup zone is now the
# tile interior minus ONE reserved right-hand column (ml badge, star,
# pen) and the name line instead of a badge-wide column on both sides
# clipped at 62% height, and the presets' tile_scale ladder is
# compressed to 0.88..1.00: the demitasse goes from 0.18 to 0.44 of the
# tile width, the tall glass fills the zone height, and no cup can
# overlap a badge or a marker. A2 card body and edge are derived from
# the page background (a fixed step above it) instead of borrowed from
# the skin's glass tokens, through the one shared glass_card helper, so
# tiles, hero, totals, chips, editor preview and vessel tiles change
# together in both palettes. A3 tab pills get a full-pill radius
# (dm_pill aspect) and each two-way segment (ml/oz, 1 shot/2 shots) is
# drawn as one capsule with the active half filled and a hairline
# between the halves; the two dbuttons keep their tags and commands as
# invisible tap targets. A7 the tile ml badge gains a crema-tinted
# border. B3 one filled action per page (dm_btn_primary aspect): Copy &
# edit / Edit on the detail page, Save in the editor.
#
# v0.9.0 (Pass 13): "+ New drink" and Prev/Next chevrons. The menu's
# bottom bar gains a "+ New drink" button between Done and Hidden (N)
# that opens the editor on a fresh, unsaved custom draft (id
# custom_<epoch>, name "New drink", the cappuccino cup, no layers, no
# garnish); the editor's status line keeps Save hidden until the draft
# validates, and Delete and Save as copy stay hidden until it has been
# saved once. Cancel and a confirmed Save return to the MENU for a draft
# opened this way (there is no detail page for it yet) through the same
# editor_leave / _return_to_page mechanism, which now takes the page the
# editor was opened from. The menu's paging buttons read "< Prev" and
# "Next >", the chevron drawn as a second label in the icon font with
# the ASCII "<" / ">" fallback. NO NEW WRITE CAPABILITY: "+ New drink"
# is a new entry point to the existing confirmed custom save, and
# `_persist` still has exactly six callers.
#
# v0.10.0 (Pass 14): method steps. Every one of the 43 presets carries a
# `steps` list in presets.tcl (2 to 4 short imperative lines, ASCII, each
# short enough for the Method card's text column -- 58 characters then,
# 50 since the wider hero card of v0.10.2, derived from the column by the
# headless STEPS check), and the detail page's right column becomes
# three cards: totals (unchanged), a shrunk ingredients card that is
# exactly the two chip rows the widest drink needs, and a new Method card
# filling the rest with a section title and a pool of four numbered
# caption lines (one grey "No method saved." when a drink has none).
# Steps are preset data, not editable: a custom drink made with
# "Copy & edit" or "Save as copy" carries a copy of its source's steps
# exactly as it carries the garnish, and a "+ New drink" draft gets none.
# `clean_steps` repairs a malformed steps value in memory on load (each
# entry trimmed, non-empty, <= 80 chars, at most 6 entries) with a NOTICE
# and no write. NO WRITE BEHAVIOR CHANGE: `_persist` still has exactly
# six callers and the only new data reaching settings.tdb is the copied
# steps list, through the same confirmed custom save.
#
# v0.10.1 (Pass 15): the last two residuals of the design-mock goal, no
# behavior or write changes. (1) Detail hero: the cup box now takes every
# unit the label column can spare -- an xs inset instead of a card
# padding on the left, an md leader gap, and a label column sized to hold
# the longest ingredient name at the body font untruncated -- so the box
# goes from 486 to 508 virtual units and the large cup from 290 to 303
# tall; the y-range is untouched because the tall vessels already fill it
# (928 units, 87% of the card). The mock's "cup fills 56% of the hero
# height" is NOT reachable in this card and the headless HEROCUP check
# proves it arithmetically: the widest vessel is 1.68 units across per
# unit tall, so 55% of the 1064-unit card height needs a 981-unit box in
# a 950-unit card, before any label column. (2) Menu tiles: a name that
# does not fit at the 22 px primary font is now written at the 16 px
# caption font before it is ever ellipsised, so "Espresso romano copy"
# and every other "<preset> copy" custom shows its full name on one line.
#
# v0.10.2 (Pass 16): a wider detail hero card, layout tokens only, no
# behavior or write changes. The hero goes from 0.40 to 0.47 of the
# content width (950 -> 1116 virtual units) and every gained unit goes to
# the cup box (508 -> 674), because the label column is now a token of
# its own instead of the leftover of a fraction: the large cup grows from
# 303 to 402 units tall (0.285 -> 0.378 of the card height) and the
# cappuccino cup from 305 to 404, a third taller. 0.47 is the widest this
# page allows, not a taste value: the right column pays for the hero, and
# at one xs more the Method card's text column no longer holds the widest
# preset step untruncated (HEROCUP proves both that and why the pass's
# 0.40-of-the-card-height target needs a card this page cannot give). The
# editor's preview card keeps the old 0.40 split as its own token, so the
# editor page is untouched.
#
# v0.10.3 (Pass 17, owner decision): Save as copy is back on fresh
# copies. v0.9.0 had tied it to the Delete rule (hidden until the draft
# was saved once); it now shows whenever Save does, i.e. for any valid
# draft, including an unsaved "Copy & edit" copy. Delete alone still
# waits for the first save. One visibility expression in the editor
# refresh; no write-path change (same confirmed custom_copy caller).
#
# v0.10.4 (Pass 18, owner decision): on the detail page the layer labels
# may overlap the cup's handle, the way the design mock draws them. The
# cup box tokens are unchanged, but they now bound the BOWL instead of
# bowl + handle: `hero_cup_box` widens the box handed to vessel_geometry
# by the vessel's handle share (base_w / bowl_frac), so a handled cup's
# bowl lands exactly where its whole cup landed in v0.10.3 while the
# handle reaches into the leader gap and under the first letters of the
# labels (drawn after it, so the text is on top). Large cup 0.378 ->
# 0.450 of the card height, cappuccino cup 0.380 -> 0.454, demitasse
# 0.452 -> 0.558; handle-less vessels are bit-identical. Layout only.
#
# v0.10.5 (Pass 19, owner decision after design/v0104_detail_borgia.png):
# the part of the hero cup's handle ring that runs under the layer labels
# is now ghosted, so the text reads cleanly while the ring stays at full
# strength beside the bowl. One pooled canvas arc on the detail page
# (`hero_cup_handle_dim`), created right after the ring and before the
# leaders and labels, repainting the ring's own ellipse from the label
# column round to the right in a new palette-derived `ring_dim`
# (card_fill 35% towards c_ink). Half-angles 82.9 / 83.3 / 86.7 degrees
# for the large cup, cappuccino cup and demitasse; hidden for every
# handle-less vessel. Colour and layout only.
#
# v0.11.0 (Pass 20, owner decision): the three pages wear the design
# mock's warm brown look under every skin theme. The page background is
# the mock's radial gradient, shipped as one PNG per physical resolution
# (1340x800, 1280x800, 2560x1600) because a Tk canvas cannot draw a
# gradient and a Tk photo must never be scaled; a screen size with no file
# falls back to the flat #1c1512 fill. `_apply_palette` no longer reads a
# single Lumen token: the mock's :root set (bg1 #1c1512, ink #f4ede3,
# ink-2 #c9b8a5, ink-3 #8f7f6f, gold #e6c58c, gold-ink #2b1a0f) is the one
# colour source, with the glass whites, the badge well and every derived
# token computed from it. Colour only: no layout, behaviour or write
# change.
#
# v0.12.0 (Pass 21, owner decision): every menu tile carries a TAPPABLE
# favorite star in its top-right corner -- hollow and dim when the drink
# is not a favorite, filled and gold when it is. Tapping it toggles the
# favorite through the existing `toggle_favorite` (the detail page's
# Favorite button and the star tab read the same list, so all three stay
# in sync) and the tile repaints in place; no page is opened. The ml
# badge moved one row down the same reserved column, with the custom-drink
# pen under it, so the cup zone beside the column is unchanged. A tap on
# the star can never also open the drink: the tile's own tap area is two
# rects that leave the star's corner out, and the star's rect is created
# after them. NO NEW WRITE CAPABILITY: the star is a new entry point to
# the existing `toggle_favorite` -> `_persist favorite` caller, and
# `_persist` still has exactly six callers.
#
# v0.12.1 (Pass 22): the tile star is now DRAWN -- a five-point canvas
# polygon instead of an icon glyph -- so the favorited state is a real
# solid gold fill. The app ships only the Regular weight of Font Awesome,
# which can draw U+F005 hollow and nothing else, so v0.12.0's "filled"
# star stayed an outline on the tablet; the polygon's -fill fills. The
# attempt to load the Solid weight (and the warning it caused on every
# start) is gone. The star TAB pill and the detail page's Favorite button
# are unchanged. No behaviour or write changes beyond the star's shape.
#
# v0.13.0 (Pass 23): the mock's details. The owner compared the tablet with
# the design mock and listed eight misses; this pass closes all eight, and
# every one of them is paint or geometry. (1) Tile cups are the mock's own
# box now -- a 62% x 64% zone, horizontally centred, with the cup fitted
# into the largest square inside it exactly as the mock's square viewBox
# does -- so the widest cup drops from 0.571 of the tile width to 0.354 and
# every cup is centred. (2) The ml badge is back in the tile's top-right
# corner as a full pill: bold gold #e6c58c at full strength on the black
# .38 well with its gold hairline. (3) Every card carries the mock's
# `linear-gradient(165deg, white .12, white .045)`, painted by the new
# `glass_photo` into one Tk photo per distinct physical size (the twelve
# tiles share one, the seven vessel tiles another) with the corners left
# transparent; 7 photos, 3.69 MB at 1340x800. (4) The favorite star halves
# (outer radius 23 -> 14 virtual) and moves to the top-left corner, and the
# tap partition moves with it: the star owns that corner, the tile owns the
# rest of the top band and everything below. (5) The title, the subtitle
# and the control row are vertically centred between the top of the screen
# and the first card instead of hugging the top edge. (6) Tab pills and the
# two-way capsules shrink from a 60-ref slab to the mock's 46-ref pill at
# 18 px bold, each only as wide as its own measured label. (7) Rounder and
# glassier everywhere: cards 12 -> 24 ref px of DRAWN corner, the hero 29,
# bar buttons 19, and every chip, badge and pill a true half-height pill;
# every button gains the mock's 1 px glass edge (dui's round_outline, no
# extra items) and every bar button its inset top highlight. (8) The menu's
# Done and the editor's keyboard Done are gold. NO BEHAVIOR OR WRITE
# CHANGES: `_persist` still has exactly six callers and `plugins
# save_settings` still appears exactly once, inside it.
#
# v0.13.1 (Pass 24): hero inset and card corners. Two owner notes from the
# v0.13.0 tablet captures. (1) On the detail page the cup sat an xs sliver
# from the card's left edge while the card's own text kept card_pad_x, so
# the cup looked as if it were falling out of the card; the cup box now
# keeps exactly the inset the text keeps -- card_pad_x on the left (the
# right and the top always did) -- which costs the bowl budget 24 units
# (674 -> 650) and the three handled cups about 1.6% of the card height
# (0.450 / 0.454 / 0.559 -> 0.435 / 0.438 / 0.538). The editor preview
# already obeyed the rule and is unchanged; both are now asserted headlessly
# (INSET). (2) Every card showed a small light tick at its top corners: the
# glass photo's highlight row followed the corner arc's own chord, which at
# row 0 is only ~4 px in from the edge, so the lit row ran on into the
# transparent corner. Row 0 is now painted only between x = r and x = w - r,
# so the lit edge ends where the corner curve begins. NO BEHAVIOR OR WRITE
# CHANGES: geometry and paint only, `_persist` still has exactly six callers
# and `plugins save_settings` still appears exactly once, inside it.
#
# v0.13.2 (Pass 25): equal inset above and below the hero cup, and photo
# corners inside the outline. Two owner notes from the v0.13.1 tablet
# captures. (1) The detail hero cup sat 14 physical px under the card's top
# edge but 50 px clear at the bottom, because the top used card_pad_y while
# the bottom stopped a whole reserved garnish zone early. The cup box now
# keeps ONE inset all round -- card_pad_x above it, exactly as at the sides,
# and card_pad_x between it and the top of the garnish caption line, which
# keeps its own bottom padding -- so a height-bound vessel has equal air
# above and below. The zone only grows (928 -> 932 units, the tall glass
# 0.872 -> 0.876 of the card height); the width-bound cups are unchanged and
# the label column is bit-identical. The editor preview cup follows the same
# rule against its Vessel caption line (632 -> 612 units). (2) The glass
# photo's transparent corner is now carved at r + 2 physical px, because the
# card's drawn outline is a smoothed polygon whose corner runs tighter than
# a true circle of r, so a faint lit sliver still showed outside the drawn
# edge at each top corner. NO BEHAVIOR OR WRITE CHANGES: geometry and paint
# only, `_persist` still has exactly six callers and `plugins save_settings`
# still appears exactly once, inside it.
#
# v0.13.3 (Pass 26): one continuous card corner. Owner note on the v0.13.2
# captures ("the notch at the tile corners"). The cause was two shapes: the
# card's edge was a smoothed polygon, whose corner is NOT a circular arc but
# a shallow diagonal, drawn over a photo whose carved corner IS a true
# circle -- between the two a dark wedge of page showed. The photo now bakes
# the whole card: per row, the first and last painted pixel of the circular
# span are the edge colour (white .17 over that row's own colour), row 0 and
# row h - 1 are edge colour across their spans, and row 1 carries the
# highlight (white .26). `glass_card` no longer draws an outline polygon for
# a card that got a photo, so the corner is one shape; the flat fallback
# (no photo -- the editor's confirm panel) keeps its drawn outline. The
# carve is back at exactly r: the r + 2 slack of Pass 25 existed only to
# hide inside the polygon that is now gone. Same seven photos, same bytes,
# setup only. NO BEHAVIOR OR WRITE CHANGES: paint only, `_persist` still has
# exactly six callers and `plugins save_settings` still appears exactly
# once, inside it.
#
# v1.0.0 (release): the owner's sign-off on the design-mock goal. Code
# identical to the tablet-verified v0.13.3; version and docs only.
#
# v1.0.1 (Pass 28: touch-UX audit). Three misses against a touch guideline
# set (touch targets >= 44/48 px, pressed feedback on every tappable
# element, text contrast >= 4.5:1), fixed without changing any behavior:
#  1. Pressed feedback. The three shared aspects (dm_btn, dm_pill,
#     dm_btn_primary) carry a `pressfill` -- a ghost or pill flashes to
#     white .12 over its own fill, the gold primary to the gold 15% of the
#     way to gold-ink, both for 120 ms -- so every styled button gets it at
#     once (the core reads the aspect at dui.tcl:10288 and flashes in
#     dui.tcl:9179). The invisible tap rects over the drawn capsules, the
#     ingredient rows and the vessel tiles are fed the same options
#     explicitly. Labels keep their colour. -pressoutline is documented in
#     the core but never read there, so it is not used.
#  2. Touch targets. The favorite star's tap box goes from 96 x 84 to
#     96 x 96 virtual (50 x 48 physical px); the drawn star does not move
#     and the tile's own two rects re-partition around it. The header pills
#     and capsule halves get dui's -tap_pad so they tap 50 px tall while
#     the drawing is untouched, and the gap between neighbouring tab pills
#     goes from xs to sm (6.3 -> 10.5 physical px).
#  3. Contrast. The Method card's step numbers were c_ink_3, 3.8:1 on the
#     card. They now use a derived `ink_3_text`, computed in _apply_palette
#     as the smallest blend of c_ink_3 towards c_ink that clears 4.5:1 on
#     both card surfaces. The tile star's OUTLINE keeps c_ink_3: it is a
#     mark, not text, and clears the 3:1 that applies to it.
# NO BEHAVIOR OR WRITE CHANGES: no command, no navigation and no write path
# is touched; `_persist` still has exactly six callers and
# `plugins save_settings` still appears exactly once, inside it.
#
# v1.1.0 (Pass 29: a visible gradient glow on the cards). Owner note on the
# detail page: "the cards in detail page need a gradient glow". The cards
# read almost flat because one shallow VERTICAL ramp was shared by every
# card. Three changes, all inside the card photos:
#  1. The ramp is the mock's real 165-deg DIAGONAL: the colour at (x, y)
#     follows t = (0.906 * yn + 0.423 * xn) / 1.329, so the top-left corner
#     is the family's top white and the bottom-right its bottom one. A row
#     is painted as up to 7 runs of equal quantised colour, so the whole set
#     still costs 16,635 `put` calls (budget 20,000).
#  2. Each mock family keeps its OWN pair -- tiles .12 -> .045, detail and
#     editor cards .10 -> .035, the hero .11 -> .04 -- and the family is
#     part of the photo cache key. Same seven photos, same 3.69 MB.
#  3. The mock's `inset 0 1px 0` highlight became a soft glow BAND: rows
#     1..6 (tiles) or 1..10 (cards, hero) fade from the highlight white
#     (.26 / .22) down to the plain row colour. The rim -- row 0, row h - 1
#     and the two side rails -- is untouched.
# The mock's drop shadow is NOT painted: a Tk photo has no per-pixel alpha,
# so it would need a page-coloured margin on each photo, and that margin
# costs 397 KB the 4 MB photo budget does not have (4,266,488 bytes against
# 4,194,304). The pass's own fallback rule drops it first.
# NOTHING MOVED: every photo item is still at its v1.0.1 corner and size, so
# no token, tap rect, badge, button or text changed by a pixel.
# NO BEHAVIOR OR WRITE CHANGES: paint only; `_persist` still has exactly six
# callers and `plugins save_settings` still appears exactly once, inside it.
#
# v1.1.1 (Pass 30: a shadow under every cup). Owner note: "add a shadow
# under the cup just like the mockup". The mock's cup() draws, before the
# bowl, <ellipse cx=cx cy=bot+3 rx=bw/2+10 ry=3 fill=rgba(0,0,0,.35)> in a
# 100-unit box; the cups had none.
#  1. Every drawn cup (12 tiles, the detail hero, the editor preview and
#     the 7 vessel-picker tiles) gains ONE pooled oval, <tag>_shadow,
#     created FIRST so it sits lowest in the cup's stacking order and is
#     placed from the same cached render dict update_cup already uses.
#  2. Geometry, in design units scaled by the fit's own s: the ellipse's
#     top is the cup's floor -- the FOOT for the coupe -- it is 6 units
#     tall and reaches 10 units past the floor on each side. It is clamped
#     to the cup's ZONE: our design box has no bottom margin (the mock's
#     viewBox does), so a height-bound glass would otherwise hang within
#     1.5 units of the tile's name line. Such a glass keeps the full
#     ellipse and slides up to end on the zone's floor.
#  3. Colour: Tk has no alpha, so the shadow is the SURFACE it lies on
#     taken 0.35 towards black -- one token per mock card family
#     (cup_shadow_tile / _card / _hero, off that family's own ramp) plus
#     cup_shadow, the flat card_fill variant. All four are registered for
#     retheme like every other cup item.
# NOTHING ELSE MOVED: no token, tap rect, text or card changed.
# NO BEHAVIOR OR WRITE CHANGES: paint only; `_persist` still has exactly six
# callers and `plugins save_settings` still appears exactly once, inside it.
#
# v1.1.2 (Pass 31: a press flash that does not stick). Found on the tablet
# during the v1.1.1 review: after a tap, a tab pill kept the selected gold
# outline and dark label on its OFF body (an unreadable label), and a
# tapped capsule half kept an opaque grey rectangle over its own label
# until the page was reloaded.
#  1. The core restores the fill captured at CREATION, 120 ms after the tap
#     (`after $ms $can itemconfigure $tag -fill $fill`, dui.tcl:9225), so
#     the restore runs AFTER the tap's command has repainted. On dm_pill,
#     round_outline had baked the aspect's OFF fill into press_args
#     (dui.tcl:10120), so it wiped the gold `_style_pill` had just set.
#  2. On an invisible tap rect the click rect is created with -fill {}
#     (dui.tcl:10186) and `after` CONCATENATES its arguments, so the queued
#     restore loses the empty word and degrades to `itemconfigure -fill`,
#     a query: the flash colour is permanent, an opaque square-cornered
#     rect over the art the rect was supposed to be invisible on.
#  3. Fix: pressfill dropped from the dm_pill aspect and from the five
#     invisible tap-rect call sites (the three capsules' halves, the editor
#     ingredient rows, the vessel tiles). dm_btn and dm_btn_primary keep
#     theirs -- static fills, correct restore -- so every real button still
#     flashes. The press rule is recorded in `_apply_palette` and asserted
#     by the rewritten PRESS section of tools/geometry_check.tcl.
# NOTHING MOVED: no token, coordinate, tap rect, text or card changed.
# NO WRITE BEHAVIOR EXISTS IN THIS VERSION beyond the standing one: paint
# and press feedback only; `_persist` still has exactly six callers and
# `plugins save_settings` still appears exactly once, inside it.
#
# v1.2.0 (Pass 32: pills drawn whole, a flash that cannot stick, the
# shadow always under the glass). Owner notes: "top row buttons have a
# visually wrong horizontal line top and bottom", "add a button press
# effect", "the shadow shifts up behind tall glasses (>300 ml)".
#  1. The tab pills are DRAWN now (pill_shape: one polygon carrying face
#     and edge + a dtext label + an invisible tap rect), not dm_pill
#     round_outline dbuttons: dui paints those with two painters whose
#     silhouettes disagree at a full pill's radius, which was the wrong
#     horizontal line across each pill's top and bottom. The dm_pill
#     aspects are gone. The polygon is _capsule_points, the same 12-step
#     arc the ml/oz capsule has always been drawn from.
#  2. Press effect for the pills and both capsules: _flash_pill /
#     _flash_seg tint the tapped control's own polygon with the primary
#     press tone from the tap's command, and _press_restore repaints FROM
#     STATE after press_ms through _paint_controls, the same proc the
#     refreshes now use -- so the flash can never stick the way the
#     core's pressfill did (pass 31). dm_btn / dm_btn_primary keep the
#     core flash.
#  3. The cup shadow could shift up behind a height-bound vessel (the
#     300 / 350 ml glasses, every hero cup): cup_shadow_box pinned the
#     ellipse's BOTTOM to the zone and derived the top. Now
#     vessel_geometry RESERVES the shadow's strip (2 x mock_shadow_dy
#     design units) below the floor -- the bottom margin the mock's
#     viewBox always had -- and cup_shadow_box pins the TOP to the floor,
#     so the ellipse always hangs under the glass. Height-bound art is
#     ~6% shorter, exactly as in the mock.
# NO WRITE BEHAVIOR EXISTS IN THIS VERSION beyond the standing one:
# `_persist` still has exactly six callers and `plugins save_settings`
# still appears exactly once, inside it.
#
# v1.3.0 (Pass 33: custom ingredient layers). Owner request: a typed
# custom ingredient per layer, with a g/ml unit and a picked colour.
#  1. DATA: a drink dict MAY carry `custom_ings` (c<N> -> {name color
#     unit}), referenced from `layers` like a preset id. The defs live
#     INSIDE the drink; copies carry them. No role, no flags: tabs, the
#     ratio's coffee side and 2-shot doubling are untouched. A g layer's
#     number draws and counts exactly as an ml would (as `ice` always
#     has); only its LABEL is "N g", under either display unit.
#  2. WRITE PATH (this pass's full statement): NO new writer. The defs
#     travel inside the draft and reach settings(custom) only through the
#     existing confirmed editor_save_custom / editor_save_copy (persist
#     callers 4 and 5 of the standing six). _clean_draft prunes defs the
#     layers no longer reference. validate_drink validates the defs (id
#     shape c<N>, name 1..24, #rrggbb colour, unit ml|g) and the load
#     drops an invalid custom drink with the standing NOTICE, writing
#     nothing. `plugins save_settings` still appears exactly once,
#     inside `_persist`, which still has exactly six callers.
#  3. UI: the ingredient palette's last chip, "+ Custom...", opens a new
#     editor mode: name entry (keyboard-safe top zone), ml/g capsule
#     (the header capsules' own shape and flash), 12 colour swatches
#     with a selection ring, Add layer / Cancel. Add builds the def,
#     adds the layer (default 10) through the existing edit_add_layer,
#     and returns to the layers list.
#  4. Every display site (tiles, hero, chips, labels, ratio names,
#     editor rows, preview) resolves name / colour / unit through
#     ing_prop (preset first, then the drink's own defs), and
#     _cup_render's cache key carries the defs, so a recolour can never
#     serve a stale polygon.
#
# v1.4.0 (Pass 34: edit existing custom layers). Owner request. A custom
# layer's editor row shows a gold pen and an invisible tap over dot +
# name (preset rows: neither); the tap reopens the pass-33 form
# PREFILLED (name, ml/g, matching swatch ringed), retitled "Edit
# ingredient" with the button relabelled "Save" (bare dbutton tag). Save
# swaps that def IN PLACE -- layer list and amount untouched -- and a
# def colour outside the twelve swatches prefills ringless and survives
# an untouched save. Cancel resets the edit state. WRITE PATH UNCHANGED:
# the edited def rides the draft to the same two confirmed saves;
# `plugins save_settings` appears exactly once, inside `_persist` (six
# callers).
#
# v1.5.0 (Pass 35: layer reorder in the editor). Owner request (was
# wishlist). Every layer row gains a chevron-up / chevron-down pair left
# of the amount steppers; `edit_move` (pure) swaps the layer with its
# neighbour -- ingredient and amount together, defs untouched, ends
# clamped -- and the preview restacks at once. Rows are top-first and
# layers bottom-first, so up the list is up the glass. No arrow past its
# end (top row no up, bottom no down, single layer neither). The amount
# column's reserve drops 200 -> 140 virtual (widest amount ~132) to help
# pay for the two squares. WRITE PATH UNCHANGED: the order rides the
# draft to the same two confirmed saves; `plugins save_settings` appears
# exactly once, inside `_persist` (six callers).
#
# v1.6.0 (Pass 36: garnish editing). Owner request (was wishlist). The
# editor preview card gains a tappable "Garnish: ..." line (text + pen +
# invisible rect) opening a new mode: a free-text entry in the
# keyboard-safe top zone, prefilled comma-separated, with Cancel / Save.
# Save parses to the token-list shape every preset has always carried
# (split on commas, trim, spaces -> underscores, max 4 x 24 chars; empty
# clears). WRITE-SHAPE CHANGE, stated in full: the two confirmed saves
# no longer OVERRIDE the draft's garnish from the source drink --
# _clean_draft always carries the draft's cleaned garnish (steps still
# travel from the source, unchanged). clean_garnish load-repairs a
# malformed garnish in memory exactly as clean_steps does; nothing is
# written on load. `plugins save_settings` still appears exactly once,
# inside `_persist` (six callers).
#
# v1.7.0 (Pass 37: editable method steps). Owner request (was wishlist).
# The layers mode's bottom row splits into "+ Add layer" and "Method
# (N)"; the Method mode lists the draft's steps (tap to edit via a
# one-entry form in the keyboard-safe zone, x to remove, chevrons to
# reorder, + Add step), capped at FOUR - the detail Method card's own
# line pool - with steps_with / steps_remove / steps_move as pure
# helpers (80-char cap on the way in; clean_steps' 6 x 80 stays the
# load-repair tolerance). WRITE-SHAPE CHANGE, stated in full: the two
# confirmed saves no longer copy the SOURCE drink's steps -- open seeds
# the draft with the drink's own steps (a preset copy starts from the
# preset's, exactly what the save used to produce) and _clean_draft
# always carries the draft's cleaned steps. Nothing is written on load.
# `plugins save_settings` still appears exactly once, inside `_persist`
# (six callers).
#
# v1.8.0 (Pass 38: group choice for custom drinks). Owner request (was
# wishlist). The editor's vessel row splits into "Vessel: ..." and
# "Group: ..."; the Group mode offers the six appendix groups plus "End
# of menu" (`custom`), the draft's choice painted gold. visible_drinks
# interleaves: a custom with a chosen group sorts directly after that
# group's presets (creation order); `custom` keeps the old end-of-menu
# place. A preset copy seeds from the preset's group. WRITE-SHAPE
# CHANGE, stated in full: the saves no longer force `group custom` --
# _clean_draft carries the draft's group, sanitized by valid_group --
# and _validate_settings SANITIZES the stored group instead of forcing
# it (a chosen group survives the load; junk repairs to `custom` in
# memory with a NOTICE, no write). `source custom` is still forced.
# Tabs are untouched (flags/id-based). `plugins save_settings` still
# appears exactly once, inside `_persist` (six callers).
#
# v1.9.0 (Pass 39: a larger vessel for 2-shot overflow). Owner request
# (was wishlist). New `pint` vessel in presets.tcl -- "Pint glass",
# 500 ml, terminal -- filling the vessel picker's 2x4 grid to exactly 8;
# the tall glass now sizes up to it, and the coupe (terminal before)
# sizes up to the latte glass, so 2-shot drinks that used to wear "over
# capacity" step into a vessel that holds them. Data + two size_up
# wirings; NO code change and NO write-path change: presets.tcl remains
# read-only data, sized_drink is display-only, and a drink saved in a
# pint rides the same validation and confirmed saves as any vessel.
# `plugins save_settings` still appears exactly once, inside `_persist`
# (six callers).
#
# v1.10.0 (Pass 40: DE1 tie-ins). Owner request; the wishlist's last
# item. MACHINE-ADJACENT, stated precisely: the detail page's bottom bar
# gains ONE "To machine" ghost button (shown only for drinks that define
# something to apply) whose tap - and nothing else, ever - applies the
# drink's linked profile via the core's own `::select_profile` (the call
# DYE makes) and/or the hot-water volume its hot_water layers sum to
# (clamped 10..250) via `set ::settings(water_volume)` plus the debounced
# `save_settings; save_settings_to_de1` copied from the Lumen skin. No
# flow is ever started; DevBridge's busy guard (copied, fails closed)
# refuses the tap while the machine is mid-operation; the outcome is
# written onto the button and the next refresh restores it. The headless
# net proves each machine-adjacent call appears EXACTLY once, inside
# to_machine_tap, wired to exactly one button. Custom drinks may carry
# `profile_fn`/`profile_title`, stamped from the app's CURRENT profile by
# the editor's new third bottom-row button (toggle link/unlink; rides the
# confirmed saves; linking itself writes nothing).
# THE STANDING CLAIM CHANGES HERE: besides its own settings.tdb, the
# plugin now - on that one explicit tap only - changes the app's selected
# profile and water_volume through the app's own official procs, exactly
# as the skin's own controls do.
#
# SAFETY STATUS: writes ONLY this plugin's own settings.tdb, and only the
# keys unit / favorites / hidden / custom, through DrinkMenu.tcl's single
# `_persist` proc (validated, inside a catch). Six callers: three single
# taps (unit toggle, Favorite, Hide/Unhide) and three editor actions each
# behind an explicit confirmation card (save custom, save as copy, delete
# custom). Nothing is written on load, show, navigation, mode switches or
# keystrokes. SDB is never opened, history/ and history_v2/ are never
# read, written, renamed or deleted.
#
# Manifest order matters: metadata first, so a failure anywhere below can
# never leave the plugin without a version (the core drops a peeked plugin
# with an empty version from the Extensions list, de1app-core/plugins.tcl
# `list`). The implementation file is sourced only if it exists.
#

package require Tcl 8.5

set plugin_name "DrinkMenu"

namespace eval ::plugins::DrinkMenu {
    variable author      "Blastize"
    variable contact     "n/a"
    # Bare number, no "v" prefix (the core's startup log prepends one).
    variable version     "1.17.0"
    variable name        "Drink Menu"
    variable description "Visual espresso drink menu: every drink drawn as a cup with colored ingredient layers, tab-filtered grid with ml/oz display, a detail page with labeled layers, ratio, 1/2 shots and numbered method steps, favorites, hide, and an editor for custom drinks reached from a drink or from the menu's + New drink button (presets are read-only; editing one creates a custom copy). Writes only its own settings file; no data access outside the plugin folder."

    # ---- Settings defaults ----
    # Each key is set only if missing: the plugin framework creates this
    # array during peek and loads settings.tdb BEFORE this manifest is
    # sourced, so a whole-array guard would skip every default
    # (MaintenanceTracker manifest pattern). Nothing in v0.1.0 reads or
    # writes these yet; they are the Pass 4 storage contract (spec F).
    variable settings
    foreach {__k __v} {
        settings_version 1
        unit       ml
        favorites  {}
        hidden     {}
        custom     {}
    } {
        if {![info exists settings($__k)]} { set settings($__k) $__v }
    }
    unset -nocomplain __k __v

    # Pass 7 (v0.6.0): presets are read-only for the user, so the old
    # per-preset "overrides" key is obsolete. A tablet upgrading from an
    # older version may still have it in settings.tdb; drop it from
    # memory here (never migrated into a custom drink) and let the next
    # user-triggered save simply omit it -- nothing is written on load.
    if {[info exists settings(overrides)]} {
        set __n 0
        catch { set __n [dict size $settings(overrides)] }
        catch { msg -NOTICE "DrinkMenu: dropping $__n obsolete override(s)" }
        unset settings(overrides)
    }
    unset -nocomplain __n

    # Directory this manifest lives in (used to load the implementation).
    variable plugin_dir [file dirname [info script]]
}

# Load the implementation that sits next to this manifest.
if {[file exists [file join $::plugins::DrinkMenu::plugin_dir DrinkMenu.tcl]]} {
    source [file join $::plugins::DrinkMenu::plugin_dir DrinkMenu.tcl]
}

# Called by the plugin framework. Returns the settings page name (or ""
# when the page could not be built, which only hides the Settings button
# instead of auto-disabling the plugin).
proc ::plugins::DrinkMenu::preload {} {
    if {[info procs ::plugins::DrinkMenu::preload_pages] eq ""} {
        catch { msg -ERROR "DrinkMenu: DrinkMenu.tcl did not load; no page registered" }
        return ""
    }
    return [preload_pages]
}

# Called by the framework when the plugin is enabled / on startup.
proc ::plugins::DrinkMenu::main {} {
    catch { msg "DrinkMenu: started v$::plugins::DrinkMenu::version (menu + detail + favorites/hide + editor; presets are read-only, editing one makes a custom copy; writes unit/favorites/hidden on tap and custom behind confirmation, all to its own settings.tdb; no other data access)" }
    return
}
