# Drink Menu

**A visual espresso drink menu on the tablet: every drink drawn as a cup with its layers.**
Version 1.17.0 · a plugin for the Decent DE1app · by Blastize

![The menu: a grid of cups with coloured layers, tabs for hot, cold, milk, favorites and custom](docs/menu.png)

**The menu.** 45 espresso drinks, each drawn as a cup with its ingredient layers and its size. Tabs for hot, cold, milk, no milk, favorites and your own drinks; ml or oz.

![Drink detail: the cup with labelled layers, totals, ratio and method](docs/detail.png)

**Drink detail.** The layers labelled on the cup, the total and ratio, the method steps, one or two shots. Star it, hide it, or send its linked profile to the machine.

![The editor: vessel, layers, method, group and linked profile for a custom drink](docs/editor.png)

**Custom drinks.** Pick a vessel, add and reorder layers, write the method, choose where it sits in the menu, link a profile.

## Install

Copy the folder to `de1plus/plugins/DrinkMenu/` (including the three `<width>x<height>/bg.png` folders), restart the app, enable **Drink Menu** under Extensions.

## Safety

Writes only its own settings file (unit, favorites, hidden drinks, custom drinks). No shot database or history access. "To machine" loads a profile and sets the hot-water volume through the app's own calls, on one explicit tap, and never starts a flow.

<details>
<summary><b>Full reference and version notes</b></summary>

## Reference

A DE1app plugin that draws a visual espresso drink menu on the tablet:
every drink rendered as a cup with colored ingredient layers, a
tab-filtered grid, a full-screen detail page, and favorites, hiding and
custom drinks. Presets are read-only for the user. Since v0.11.0 the
pages carry the design mock's own warm brown look, whatever skin theme
is active.

Author: **Blastize** - Current version: **1.17.0** (Pass 48: UX review)

## New in v1.17.0

A round of usability fixes from a design review and the owner's notes.
The faint dark line under every button and pill is gone (the edges are
now drawn exactly, row by row). The tile star sits on the card corner's
diagonal. Hot water is a warm tone, so a hot Americano no longer looks
iced. On the detail page the Favorite button shows the star itself,
filled or hollow, with a fixed label, and a custom drink with no method
offers "Add a method". The menu shows "1 / 4" beside Next. In the
editor, Delete moved next to Cancel in a red tone, the keyboard Done
appears only while you type the name, an empty name shows "Drink name",
the bottom bar hides while a picker is open, Method and Profile sit
under Vessel and Group, and "+ Add layer" follows the last layer. Long
layer labels shrink one step before they are shortened. Nothing the
plugin writes changed.

## New in v1.16.1

The favorite star on each tile sits on the same row as the ml badge now,
a little further in from the card corner, and a custom drink's pen mark
follows it. Nothing else changed.

## New in v1.16.0

The last jagged marks are smooth. The favorite star on every tile (both
its hollow and its filled face), the coloured ingredient dots on the
detail chips, the editor rows and the palette, and the dimmed part of a
cup's handle ring on the detail page are now anti-aliased images, made
inside the plugin on first use. Nothing moved and nothing the plugin
does changed; a device that refuses the images keeps the previous
canvas marks.

## New in v1.15.0

Clearer hierarchy. "+ New drink" is now the menu's gold button and Done
a plain one; the favorites tab says "Favorites"; the ml/oz toggle stands
further from the filter tabs and, like the shot and ml/g toggles, shows
its choice in a quiet grey rather than the filters' gold; a custom
drink's pen mark sits in a fixed spot next to the star instead of under
the ml badge. Nothing the plugin does changed.

## New in v1.14.0

The cups are smooth too. Each cup's outline, stem and handle are now
drawn as one anti-aliased image over its flat ingredient layers, and a
soft shadow image sits under it instead of the flat dark oval. Images
are made on first use and shared, so the menu tiles cost one per vessel.
Nothing moved and nothing the plugin does changed; a device that refuses
the images keeps the previous canvas strokes.

## New in v1.13.0

Every remaining rounded control is smooth now: the tab pills, the ml/oz
and shot toggles, the ml badges on the tiles, the ingredient and palette
chips, and every button on all three pages. Each is drawn from two tiny
anti-aliased end-cap images and a flat middle, so any width costs
nothing extra and a tap still flashes the button. Nothing moved and
nothing the plugin does changed.

## New in v1.12.0

Card corners are smooth at last. Every card is now painted as a PNG with
transparency, generated inside the plugin at the tablet's exact pixel
size: true anti-aliased corner arcs, a crisp hairline edge, and the
design mock's soft drop shadow under and beside each card. The detail
page's big cup card shares the same corner radius as the menu tiles.
Nothing moved and nothing the plugin does changed; if a device refuses
the PNG, the previous flat-corner painter takes over unchanged.

## New in v1.11.0

The pages stop pretending to be glass. The tablet's canvas has no
transparency or blur, so the old rim, the lit band under each card's top
edge, the highlight and shade lines and the buttons' top highlight read
as a plastic bevel. Cards are now plain tonal tiles a step above the
page with a faint hairline edge; gold buttons and the selected tab are
rimless; the cup's shadow is a light smudge. Nothing moved and nothing
the plugin does changed.

## New in v1.10.0

Drinks can now set up the machine. A "To machine" button appears on the
detail page's bottom bar for any drink that defines something to apply:
tapping it selects the drink's linked espresso profile and/or sets the
hot-water volume to what its water layer asks for, using the app's own
mechanisms - the same ones the skin's controls use. Nothing ever happens
without that tap, no brewing is ever started, and the button reports
what it did. Custom drinks link a profile in the editor: dial in the
profile you want first, then tap "Profile: none" to stamp it onto the
drink.

## New in v1.9.0

A new vessel: the Pint glass, 500 ml. Tall-glass drinks that overflowed
at 2 shots now step up into it, and coupe drinks - which had nowhere to
go at all - step into the latte glass. The pint is also a normal choice
in the vessel picker, which now shows all eight vessels in its grid.

## New in v1.8.0

Custom drinks can pick where they live in the menu. The editor's vessel
row now also shows "Group: ..."; the picker offers the six menu sections
plus "End of menu", and a drink given a group appears right after that
section's presets in the All tab instead of being dumped at the end. A
copy starts in its source's section.

## New in v1.7.0

Method steps are editable. The editor's bottom row now reads "+ Add
layer" and "Method (N)"; the Method list shows up to four numbered steps
with tap-to-edit, reorder chevrons, remove, and "+ Add step". A preset
copy starts with the preset's own steps, and what you write is what the
drink's detail page shows. Four is the cap because that is exactly what
the Method card there can display.

## New in v1.6.0

Garnish is editable. The editor's preview card shows a "Garnish: ..."
line with a pen; tapping it opens a small form where you type the
garnishes as free text, comma-separated ("orange peel, cinnamon"), up to
four. Emptying the field removes the garnish. Copies used to inherit
their source's garnish forever - now what you type is what the drink
keeps, shown on its detail page as always.

## New in v1.5.0

Layers can be reordered. Each row in the editor carries an up and a down
chevron next to the amount steppers; a tap swaps the layer with its
neighbour, amount and all, and the preview cup restacks immediately. The
top row has no up-chevron and the bottom row no down-chevron, so the
buttons always mean something.

## New in v1.4.0

Custom layers can now be edited after the fact. Their row in the editor
carries a small gold pen; tapping the row reopens the same form,
prefilled, as "Edit ingredient" with a Save button. Saving changes the
name, unit or colour in place - the amount and the layer order stay put -
and the preview repaints at once. Preset layers are unchanged and show no
pen.

## New in v1.3.0

The editor's ingredient palette ends in a "+ Custom..." chip. It opens a
small form: type any ingredient name, choose whether it measures in ml or
grams, and pick one of twelve colours. The layer then behaves like any
other - steppers, remove, capacity, the drawn cup - except its amount
always reads in grams if that is what you chose, no matter the ml/oz
display toggle. The definition is saved inside the drink itself (copies
carry it along), only through the same confirmed Save as every other
change; nothing new writes to disk.

## New in v1.2.0

Three owner notes. The header tab pills are drawn as single polygons now,
so the wrong horizontal line dui's two-painter button left across their
top and bottom is gone. Tapping a pill or a capsule half flashes it with
the same press tone the real buttons use - painted by the plugin and
restored from state, so it can never stick. And the cup shadow always
hangs under the glass: tall vessels used to push it up behind themselves,
because the cup's fitting box reserved no room below the floor. It does
now, exactly like the design mock's own view box.

## New in v1.1.2

A tap used to leave the control it hit wearing the wrong face until the
page was reloaded: a selected tab pill kept its gold outline and dark
label on the unselected dark body, and a tapped `oz` or `2 shots` half
kept a grey rectangle over its own label. Both came from the press flash,
which the app restores to the fill a button had when it was created - too
late, and impossible on an invisible rect. The flash is now used only
where it can be undone, so every real button still flashes and the pills
and capsules paint their selected state and keep it.

## New in v1.1.1

Owner note: "add a shadow under the cup just like the mockup". Every
drawn cup - the twelve tiles, the detail hero, the editor preview and the
vessel picker - now sits on the mock's own shadow: one flat dark ellipse
whose top is the cup's floor (the foot, on the coupe), six design units
tall and ten units wider than the floor on each side, drawn under
everything else the cup owns. It is the colour of the card beneath it
taken 35% towards black, because a Tk canvas has no transparency. Paint
only: nothing moved and nothing the plugin *does* changed.

## New in v1.1.0

Owner note on the detail page: "the cards in detail page need a gradient
glow". Paint only - nothing moved and nothing the plugin *does* changed.

- **The ramp is diagonal now.** A card face is the mock's
  `linear-gradient(165deg, ...)` for real: the colour at (x, y) follows
  `t = (0.906 * yn + 0.423 * xn) / 1.329`, so a card is lightest at its
  top-left corner and darkest at the bottom-right instead of shading by
  one shallow step from top to bottom. Each row is painted as up to seven
  runs of equal colour, so the seven photos still cost only 16,635 `put`
  calls at setup.
- **Every card family keeps its own whites.** Tiles run white .12 ->
  .045, the detail and editor cards .10 -> .035, the hero .11 -> .04,
  exactly as the mock's `.tile` / `.card` / `.hero` do; the family is part
  of the photo cache key. Same seven photos, same 3.69 MB.
- **A soft glow under the top edge.** The mock's `inset 0 1px 0` line is
  now a band: rows 1..6 on a tile, 1..10 on a card or the hero, fading
  from the highlight white (.26 / .22) down to the plain row colour. The
  rim - row 0, row h - 1 and the two side rails - is untouched.
- **The mock's drop shadow is not painted.** A Tk photo has no per-pixel
  alpha, so the shadow would have to live in a page-coloured margin of
  each photo, and that margin costs 397 KB the 4 MB photo budget does not
  have. It is the first thing the pass drops.
- Nothing moved: every photo item is still at its v1.0.1 corner and size,
  so tokens, tap rects, badges, buttons and text are unchanged. Geometry
  check **391/391**.

## New in v0.13.3

One owner note on the v0.13.2 tablet captures: "the notch at the tile
corners". Paint only; nothing the plugin *does* changed.

- **The card is one shape now.** A card used to be two: a gradient photo
  whose corner was carved as a true circle, and a *smoothed* edge
  polygon drawn over it - and a `-smooth 1` corner is not a circular
  arc, it is a shallow diagonal. The two disagreed, so a dark wedge of
  page showed between them and the corner read as a notch
  (`out/final/final2_main_p1.png`).
- **The photo carries the edge.** `glass_photo` now bakes the rim in:
  per row, the first and last painted pixel of the circular span are the
  edge colour (white .17 over that row's own colour), row 0 and row
  h - 1 are edge colour right across their spans, and row 1 is the
  highlight (white .26). `glass_card` draws no outline polygon for a
  card that got a photo, so the edge follows the same arc as the carve.
  The flat fallback (no photo - the editor's confirm panel) keeps its
  drawn outline, since there is no image to bake into.
- The corner is carved at exactly `r` again: the `r + 2` slack v0.13.2
  added existed only to hide inside the polygon that is now gone. Same
  seven photos, same 3.69 MB, setup only. Geometry check **370/370**.

## New in v0.13.2

Two more spacing notes from the v0.13.1 tablet captures. Both are
geometry and paint; nothing the plugin *does* changed.

- **One inset all round the hero cup.** v0.13.1 fixed the sides; the
  vertical half was still uneven. The top used `card_pad_y` (28 units)
  and the bottom stopped a whole reserved garnish zone early, so the
  tall glass sat 14 physical px under the card's top edge and 50 px
  clear at the bottom (`out/final/v131_detail_icedlatte.png`). The cup
  box now keeps `card_pad_x` above it - the same inset it keeps at the
  sides - and `card_pad_x` between it and the top of the garnish caption
  line, which keeps its own bottom padding. A height-bound vessel (tall
  glass, latte glass) now has **equal air above and below**, and the
  zone only grows: 928 -> **932** units, the tall glass 0.872 ->
  **0.876** of the card height. The width-bound cups are bound by the
  width, so large cup 0.435, cappuccino cup 0.438 and demitasse 0.538
  are unchanged, and the label column is bit-identical. The editor
  preview cup follows the same rule against its Vessel caption line
  (632 -> 612 units, 18.8 px of air above and below).
- **No light sliver at a card's corners.** v0.13.1 stopped the highlight
  row at `x = r`, but the card's drawn outline is a *smoothed* polygon
  whose corner runs slightly tighter than a true circle of `r`, so a lit
  pixel or two still showed outside the drawn edge
  (`out/final/v131_main_p1.png`). The photo's transparent corner is now
  carved at `r + 2` physical px, on every row and in the opaque-photo
  fallback, so nothing lit lands outside the outline.

## New in v0.13.1

Two spacing notes the owner made on the v0.13.0 tablet captures. Both
are geometry and paint; nothing the plugin *does* changed.

- **The detail cup keeps the card's own inset.** Through v0.13.0 the
  hero cup box started an `xs` sliver (12 units) from the card's left
  edge, while the card's garnish caption below it kept `card_pad_x`
  (36) - so the cup read as crowding the card. The cup now keeps
  exactly the inset the text keeps: `card_pad_x` on the left and the
  right, `card_pad_y` at the top. The bowl budget pays for it, 674 ->
  650 units, so the three handled cups give back about 1.6% of the card
  height: large cup 0.450 -> **0.435**, cappuccino cup 0.454 ->
  **0.438**, demitasse 0.559 -> **0.538** of the hero card. The editor
  preview already obeyed the rule and is unchanged; both cards are now
  asserted headlessly (`INSET`).
- **No light tick at a card's top corners.** The glass photo's
  highlight row followed the corner arc's own chord, which at row 0 is
  only ~4 px in from the edge, so the lit row ran on into the
  transparent corner and left a small bright tick at each top corner of
  every card. Row 0 is now painted only between `x = r` and
  `x = w - r`; rows 1..r keep the arc inset and carry the plain
  gradient, so the lit edge ends where the corner curve begins.

## New in v0.13.0

The owner compared the tablet with the design mock and listed eight
misses. All eight are closed here, and every one of them is paint or
geometry - nothing about what the plugin *does* changed.

- **Smaller, centred cups.** A tile's cup used to be fitted into the
  whole width beside the badge column, so the wide cups filled 57% of
  the tile. It now sits in the mock's own box - 62% of the tile's width
  by 64% of its height, horizontally centred - and, like the mock's
  square drawing area, the cup is fitted into the largest square inside
  that box. The widest cup drops to 35% of the tile width, the demitasse
  to 33%, and every cup is centred over its name with room to breathe.
- **A gold ml pill, top right.** The amount badge is back in the tile's
  top-right corner as a **full pill** (not a rounded box), its amount in
  **bold gold** at full strength on the dark well with the gold
  hairline - 10.7:1 of contrast.
- **Glass cards with a real gradient.** Every card - the tiles, the
  detail hero and its three cards, the editor's preview and the
  vessel-picker tiles - is now the mock's top-to-bottom glass gradient
  instead of one flat step above the page, with a lit line along its top
  edge. A Tk canvas cannot draw a gradient, so each distinct card size
  gets one generated image (the twelve tiles share one; so do the seven
  vessel tiles): 7 images, 3.7 MB. The corners are left transparent, so
  the page's own gradient shows through a card's rounded corner.
- **A small star, top left.** The favorite star is half its old size and
  has moved to the tile's top-left corner, where the mock puts it. Its
  tap area moved with it: the star owns that corner, and a tap anywhere
  else on the tile - including the badge - still opens the drink.
- **A lower header.** The title, the subtitle and the row of controls no
  longer hug the top edge: they sit vertically centred between the top of
  the screen and the first card.
- **Smaller header buttons.** The tab pills and the ml/oz and 1 shot/2
  shots capsules shrink from the height of a bar button to the mock's own
  pill, at a smaller bold label, and each pill is only as wide as its own
  text needs. The bar buttons keep their full touch height.
- **Rounder, glassier everything.** Cards are twice as round as before,
  the detail hero rounder still, bar buttons rounder, and every chip,
  badge and pill is a true half-height pill. Every button gained a thin
  glass edge, and every bar button a lit line just inside its top edge.
- **Done is gold.** The menu's **Done** and the editor's keyboard
  **Done** are now the filled gold action, like **Copy & edit** and
  **Save** already were.

## New in v0.12.1

- **The favorite star really fills.** The star on a tile is now drawn as
  a five-point shape instead of being set in the icon font, which on this
  tablet only comes in an outline weight: tap a star and it turns solid
  gold, tap it again and it goes back to an empty outline. Nothing else
  about it changed - the star tab pill and the detail page's **Favorite**
  button look and behave exactly as before.

## New in v0.12.0

- **A tappable favorite star on every tile.** Each drink in the grid now
  shows a star in its top-right corner: dim and hollow when the drink is
  not a favorite, **gold** when it is. Tap the star and the drink is
  added to your favorites straight from the menu - no need to open it
  first; tap again to remove it. The tile repaints on the spot, and on
  the star tab the drink appears or disappears with that same refresh.
- **The star never opens the drink.** The tile's own tap area is two
  rectangles that leave the star's corner out, and the star's tap target
  sits on top of them, so a tap on the star only toggles the favorite,
  while a tap on the cup, the name, the ml badge or anywhere else still
  opens the detail page.
- **The marker column re-stacked.** The star took the top-right corner,
  so the **ml badge** moved one row down the same column and the
  custom-drink **pen** sits under the badge. The column keeps its width,
  so the cup beside it is drawn exactly as before - no cup can sit under
  the star, the badge or the pen.
- **Everything stays in sync.** The detail page's **Favorite /
  Favorited** button, the tile star and the star tab all read the same
  list, so toggling from any of them updates the others.
- **No new write capability.** The star is a new entry point to the
  favorite toggle the detail page already had; the plugin still writes
  only its own settings file, through the same single `_persist` proc
  with the same six callers.

## New in v0.11.0

- **The mock's warm brown look.** Menu, detail and editor now share the
  design mock's page background - a soft radial gradient that runs from
  a warm brown at the top left (#3b2b22) through #1c1512 to a near-black
  #100c0a in the bottom right - with gold accents and glass cards over
  it. It looks the same under every skin theme, light or dark.
- **The gradient is a shipped image, not a fill.** A Tk canvas cannot
  draw a gradient, and a Tk photo cannot be resized without dropping
  pixels, so the plugin ships one pixel-exact PNG per physical screen
  size: `1340x800/bg.png` (the DE1 tablet), `1280x800/bg.png` and
  `2560x1600/bg.png`, 79 / 77 / 242 KB. They are ordered-dithered, so
  there is no banding. One photo is created for the whole plugin and
  shared by the three pages. **These folders must be copied to the
  tablet with the rest of the plugin** - a screen size with no file of
  its own simply gets the flat #1c1512 background instead.
- **One palette, from the mock.** The colours no longer come from the
  skin: the mock's `:root` set (ink #f4ede3, ink-2 #c9b8a5, ink-3
  #8f7f6f, gold #e6c58c, gold-ink #2b1a0f, glass whites at 7.5% / 16% /
  17%) is the single source, and every card, chip, badge, pill, button
  and cup tone is derived from it. Text contrast is asserted in the
  headless check: 12.7:1 for body text on a card, 7.6:1 for secondary
  text, 10.7:1 for gold on a badge, 10.1:1 for the label on a gold
  button.

## New in v0.10.5

- **The handle ring is dimmed under the labels.** On a drink's detail
  page the part of the cup's handle that passes behind the layer names
  is drawn in a ghosted tone, so the text reads cleanly, while the rest
  of the ring - the part beside the bowl, where the leader lines cross
  it - stays at full strength. Cups without a handle are unaffected.

## New in v0.10.4

- **A bigger cup on the detail page, with the labels running over the
  handle.** The cup box is unchanged, but it now measures the *bowl*
  instead of the bowl plus its handle, so a handled cup fills the box
  with the drink itself and lets its handle reach into the gap and under
  the first letters of the labels - the way the design mock draws it. A
  large cup goes from 38% to 45% of the card height, a cappuccino cup
  from 38% to 45%, a demitasse from 45% to 56%; the glasses, which have
  no handle, are exactly as before. Labels are drawn on top of the
  handle ring, so nothing is hidden.

## New in v0.10.2

- **A wider hero card, so the cup is a third bigger.** On a drink's
  detail page the card holding the drawing grows from 40% to 47% of the
  page width and every gained unit goes to the cup: a large cup is now
  402 units tall instead of 303 (38% of the card height instead of 28%),
  the demitasse and the glasses grow to match, and the labels, the
  garnish line and the three cards in the right column keep their places
  and their rules. The editor page is unchanged.

## New in v0.10.1

- **A bigger hero cup.** On a drink's detail page the cup now takes every
  unit of the card that the label column can spare: it starts a hair in
  from the card's left edge instead of a full padding, and the label
  column beside it is exactly as wide as the longest ingredient name
  needs. The cup box grows from 486 to 508 units, so a large cup is 303
  units tall instead of 290; the tall glasses already filled the card
  from top to bottom and are unchanged. The mock's even bigger cup is not
  reachable in a card this wide without either widening the card or
  drawing the labels over the cup - the headless check now carries that
  arithmetic.
- **Tile names always fit.** A drink name that does not fit a tile at the
  normal font is now drawn one step smaller (the 16 px caption size)
  before it is ever shortened, so "Espresso romano copy" and the other
  "<name> copy" customs show their full name on one line instead of
  "Espresso romano co...". Nothing moved: same tiles, same name line.

## New in v0.10.0

- **Method card.** The detail page's right column is three cards now:
  the totals card (unchanged), the ingredient chips - which no longer
  run to the bottom of the screen but shrink to exactly the two chip
  rows the busiest drink needs - and a new **Method** card filling the
  rest of the column down to the bottom bar, in the same glass as the
  others. It lists the drink's method as up to four short numbered
  lines: *"1  Pull a doppio, 18 g in, 60 ml out, about 28 s."*,
  *"2  Steam 120 ml of milk to a thick, glossy foam."* and so on. The
  cold drinks mention the ice and the cold milk, the layered ones the
  order to pour in.
- **Every preset has one.** All 43 presets in `presets.tcl` carry two
  to four steps, written to fit the card's width without truncation.
- **Copies keep the steps.** A custom drink made with **Copy & edit**
  or **Save as copy** carries a copy of its source's steps, exactly as
  it carries the garnish. A **+ New drink** draft has none, and its
  Method card reads *"No method saved."*
- Steps are preset data and are **not editable** in the editor (on the
  wishlist). This is not a new write capability: the copied steps reach
  `settings.tdb` only through the same confirmed custom save, and
  `_persist` still has exactly six callers.

## New in v0.9.0

- **+ New drink.** The menu's bottom bar now reads
  **Done | + New drink | Hidden (N)** on the left. Tapping **+ New
  drink** opens the editor on an empty custom draft called "New drink"
  in the cappuccino cup: no layers yet, so the status line under the
  preview says "Add at least one layer" and **Save** stays hidden until
  the draft is valid (add a layer and it becomes "Needs an espresso
  layer" until a coffee layer is there). **Delete** stays hidden too,
  because the drink does not exist yet; **Save as copy** appears with
  Save once the draft is valid (v0.10.3). **Cancel**
  returns to the menu; a confirmed **Save** also returns to the menu,
  where the new drink is waiting in **Custom** (and on its own detail
  page the button now reads **Edit**).
  This is a new *entry point* to the editor's existing confirmed save,
  not a new write capability: it goes through the same confirmation card
  and the same single `_persist` write path as **Copy & edit** always
  has, and the number of `_persist` callers is unchanged at six.
- **Prev / Next chevrons.** The menu's paging buttons read **< Prev**
  and **Next >**, with the same chevron glyphs the detail page uses (and
  plain `<` / `>` if the icon font is unavailable). They are still
  hidden on the first and last page.

## The look (v0.8.0, completed in v0.11.0)

The pages follow the owner's design mock. Every step of it has been a
visual pass only - no behavior, navigation, data or write change.

- **The warm brown page** (v0.11.0). The background is the mock's radial
  gradient: an ellipse of 120% x 90% centred just off the top-left
  corner, running #3b2b22 -> #1c1512 (at 48%) -> #100c0a. Tk cannot draw
  a gradient, so it ships as a dithered PNG per physical resolution
  (1340x800, 1280x800, 2560x1600) and is drawn as the first, lowest item
  of each page; an unlisted screen size falls back to a flat #1c1512.
  The photo is never scaled - Tk's photo zoom replicates or drops whole
  pixels rather than resampling - which is why the sizes are shipped
  pixel-exact.
- **One palette, and it is the mock's** (v0.11.0). The pages no longer
  read the skin's tokens at all, so they look the same under Lumen light
  and Lumen dark:

  | Token | From the mock | Hex |
  |---|---|---|
  | page background | `--bg1` (the gradient's middle stop, and the flat fallback) | `#1c1512` |
  | primary text | `--ink` | `#f4ede3` |
  | secondary text | `--ink-2` | `#c9b8a5` |
  | muted text (step numbers, disabled labels) | `--ink-3` | `#8f7f6f` |
  | gold (amounts, selected pill, primary button) | `--gold` | `#e6c58c` |
  | text on gold | `--gold-ink` | `#2b1a0f` |
  | card gradient, top -> bottom (v0.13.0) | white 12% -> 4.5% over bg1 | `#37312e` -> `#26201d` |
  | card body without a gradient (flat fallback) | `--glass`, white 7.5% over bg1 | `#2d2724` |
  | card edge | `--glass-edge`, white 17% | `#433d3a` |
  | inner top highlight | white 26% over the card's own top colour (`.tile` `inset 0 1px 0`) | `#6b6764` |
  | badge / chip well | black 38% over the card (`.tile .ml`) | `#1c1816` |
  | badge hairline | gold 35% over the well | `#63553f` |
  | button glass edge / highlight (v0.13.0) | white 17% / 16% over the button's own fill | `#514c49` / `#4f4a47` |

- **Centred cups in the mock's box** (v0.13.0). A tile's cup sits in the
  mock's own drawing area - 62% of the tile's width by 64% of its height,
  horizontally centred above the name - and is fitted into the largest
  square inside that box, exactly as the mock's square viewBox does. The
  widest cup fills 0.35 of the tile width and the demitasse 0.33 (they
  were 0.57 and 0.44 in v0.12.1, and the mock reads about 0.25 and 0.19).
  Relative sizes still read - a demitasse is visibly smaller than a tall
  glass - and no cup can touch the star in the top-left corner or the ml
  badge in the top-right, with at least 14 units to spare at the tightest.
- **A hero cup that fills its card** (v0.10.2, v0.10.4): the detail
  page's cup box measures the bowl only, so a handled cup fills the card
  with the drink and lets its handle run under the start of the layer
  labels, which are drawn on top of it - and since v0.10.5 the ring is
  ghosted for exactly that stretch, so the label text reads cleanly.
- **Glass tiles and cards.** Every card - tiles, the detail hero, the
  totals, ingredient and Method cards, the editor preview and the
  vessel-picker tiles - carries the mock's top-to-bottom glass gradient
  with a thin edge and a lit top line. Since v0.13.0 the gradient is a
  generated image, one per distinct card size (the twelve tiles share
  one, the seven vessel tiles another): a Tk canvas rectangle cannot hold
  a gradient, and a Tk photo cannot be resized without dropping pixels,
  so each size gets its own. The corners outside the card's radius are
  left transparent, so the page's own gradient shows through them. Seven
  images, 3.7 MB at 1340x800. The editor's confirmation panel is the one
  card that keeps the flat fill: it is a transient modal with no
  counterpart in the mock, and its own image would push the set past the
  memory budget.
- **Pills.** The tab pills are full pills, and each two-way toggle
  (ml / oz, 1 shot / 2 shots) is drawn as one capsule with the active
  half filled and a hairline between the halves. Since v0.13.0 they are
  the mock's smaller pill (46 reference px tall against a bar button's
  60) at an 18 px bold label, and each is only as wide as its own text
  plus its padding, with a floor so the short tabs stay tappable.
- **One filled action per page** (v0.13.0 adds Done). Gold: the menu's
  **Done**, the detail page's **Copy & edit / Edit**, and the editor's
  keyboard **Done** and **Save**. Everything else is a ghost button with
  a glass fill, a 1 px glass edge and - on the bottom bars - a lit line
  just inside the top edge.
- **One filled action per page.** The detail page's **Copy & edit** (or
  **Edit**) and the editor's **Save** are filled; everything else stays
  ghost. The ml badge gains a crema-tinted border.

## What it does (menu, detail, favorites, hide, editor; no alcoholic drinks)

- Appears in Settings > App > Extensions as "Drink Menu".
- **Presets are read-only and can never be edited or overwritten.** On
  a preset's detail page the edit button reads **Copy & edit**: it
  opens the editor on a fresh, unsaved custom copy (named "<name>
  copy"); the original preset is untouched no matter what you do to the
  copy. On a custom drink's detail page the button reads **Edit** and
  opens that drink itself.
- **Editing**: the editor shows a live preview on the left and, on the
  right, the vessel button, one row per layer (top layer first) with
  **-** / **+** / **x**, and **+ Add layer** which opens the ingredient
  palette. The name is typed in the header field; tap **Done** there to
  put the keyboard away. Steps are 5 ml, or 0.25 oz (7 ml) in oz mode.
  The status line under the preview names anything that blocks saving
  ("Needs an espresso layer", "Exceeds vessel by 40 ml"), and Save stays
  hidden until it is clear. Bottom bar: Cancel, Delete, Save as copy,
  Save. **Delete is hidden until the draft has been saved at least
  once** - a fresh "Copy & edit" or "+ New drink" draft cannot be
  deleted before it exists. **Save as copy** shows whenever Save does
  (v0.10.3 restored it on fresh copies; v0.9.0 to v0.10.2 had hidden it
  there).
- **Copies and custom drinks**: **Save as copy** creates another,
  distinct custom drink (named "<name> copy" unless you renamed it)
  that appears after the presets in every tab and in Custom. Custom
  drinks can be edited and **deleted**; deleting also drops their
  favorite/hidden entries. Only custom drinks carry the pen marker on
  their tile.
- Every save, copy and delete asks for confirmation first; cancelling a
  changed draft asks "Discard changes?".
- Limitation: layers cannot be reordered (remove and re-add instead);
  garnish, group and method steps are not editable (a copy inherits the
  garnish and the steps of the drink it came from).
- **Favorites**: since v0.12.0 the fastest way is the **star in a tile's
  corner** - top-left since v0.13.0, and half the size it was. Tap it and
  the drink is a favorite (since v0.12.1 the star fills solid gold), tap
  it again to undo (it goes back to an empty outline). The detail page still has its **Favorite**
  button, whose label flips to **Favorited**, and the star tab (the pill
  after "No milk") lists whatever is starred; all three stay in sync. The
  star tab shows "No favorites yet" until you have one.
- **Hide / unhide**: on the detail page tap **Hide**; the drink leaves
  every tab and the menu shows a **Hidden (N)** button beside Done.
  Tap it to see the hidden drinks, open one and tap **Unhide** to bring
  it back. Hiding never touches the preset data; it is one id in a list.
- **Unit**: the ml / oz toggle is remembered across app restarts.
- **Custom** tab pill is present as a placeholder ("No custom drinks
  yet."); the editor arrives in v0.5.0.
- Tapping a tile opens the **detail page**. On the left, a glass hero
  card: the drink drawn as large as the card allows (since v0.10.2 that
  card is 47% of the page width and the cup fills it right up to the
  label column; since v0.10.4 it is the bowl that fills it, with a
  handle allowed to reach under the start of the labels), every layer
  labeled beside it with its name and amount on a leader line, and the
  garnish, if any, as a caption along the bottom. A tall vessel fills the
  card top to bottom; a wide cup is limited by the card's width, not by
  its height. On the right, three cards: **totals** (total amount and the
  ratio line - coffee first, then the other ingredients, normalized to
  the coffee), **ingredients** (one chip per layer: color dot, name,
  amount) and **Method** with the numbered steps (v0.10.0). The header
  carries the ml / oz toggle and a **1 shot | 2 shots** toggle (2 shots
  doubles only the coffee layers and steps the vessel up, at most twice,
  when it would overflow); the bottom bar carries Back, Favorite, Hide,
  Copy & edit (or Edit) and Prev / Next to step through the current tab.
  Back returns to the menu with tab, page and unit unchanged.
- **Preset count**: presets.tcl holds 43 drinks (7 straight, 4 water,
  8 small milk, 9 cup milk, 5 chocolate and cream, 10 cold). Pass 8
  removed the 4 alcoholic drinks and the spirited group entirely (owner
  decision: no alcoholic drinks or ingredients in the plugin), along
  with the 4 spirit ingredients and the Irish coffee glass vessel.
- Its Settings button opens the menu page:
  - 43 preset espresso drinks from `presets.tcl`, drawn in their own
    vessels (demitasse, cappuccino cup, large cup, small glass, latte
    glass, tall glass, coupe glass on a stem) as a 4 x 3 grid of glass
    tiles, 12 per page;
  - each tile shows the cup, the drink name and an amount chip;
  - tab pills All / Hot / Cold / Milk / No milk, derived from the
    ingredients' flags (no manual tagging);
  - an ml / oz toggle that changes every visible chip at once (display
    only, storage stays in ml; resets to ml on app restart);
  - a bottom bar with Done, **+ New drink** and (when something is
    hidden) Hidden (N) on the left, and **< Prev** / **Next >** paging
    on the right.
- Tapping a tile only writes a log line in this version; the detail page
  arrives in v0.3.0.
- Colors follow Lumen's palette when the Lumen skin is active (light or
  dark) and fall back to the plugin's own dark palette elsewhere.

## Speed

Tab switches and Prev / Next redraw the whole 12-tile grid in place.
Since v0.6.2 that costs about **6 ms** on the tablet (it was ~584 ms):
the canvas ids behind each tag are resolved once instead of on every
call, and vessel geometry, layer polygons and fitted names are cached.

If you ever want the numbers yourself, set
`::plugins::DrinkMenu::debug_timing` to 1; every refresh then logs
`DrinkMenu timing <section> <ms>` lines plus a call-count line. It
defaults to 0 and logs nothing.

## Safety

- **Settings writes**: the plugin writes only its own
  `plugins/DrinkMenu/settings.tdb`, and only the keys `unit`,
  `favorites`, `hidden` and `custom`, through one proc (`_persist`).
  Three single-tap callers (unit toggle, Favorite, Hide/Unhide) and
  three editor callers that run only from a confirmation card (save
  custom, save as copy, delete custom). Nothing is written on load,
  show, navigation, mode switches or keystrokes. An obsolete `overrides`
  key left over from an older version is dropped from memory on load
  (logged, never written back) if found on disk.
- **"+ New drink" is not a new write capability** (v0.9.0): it only
  opens the editor on an empty draft. The draft reaches `settings.tdb`
  only through the same confirmation card and the same `custom save`
  caller that "Copy & edit" has always used; `_persist` still has
  exactly six callers.
- **Method steps are not a new write capability** (v0.10.0): they are
  preset data, they are never editable, and a copy's inherited steps
  reach `settings.tdb` only through the existing confirmed custom save.
  A malformed `steps` value found in `settings.tdb` is repaired in
  memory on load (logged, never written back).
- **presets.tcl is read-only data**; nothing mutates it at runtime, and
  the user can never edit or overwrite a preset -- editing one always
  creates a custom copy.
- **No data access outside the plugin folder**: SDB is never opened,
  `history/` and `history_v2/` are never read or written.
- The Lumen skin is not modified.

## Install

Copy the folder to the tablet so it looks like this:

```
de1plus/plugins/DrinkMenu/
    plugin.tcl
    DrinkMenu.tcl
    presets.tcl
    filelist.txt
    README.md
    CHANGELOG.md
    1340x800/bg.png
    1280x800/bg.png
    2560x1600/bg.png
```

The three `<width>x<height>/bg.png` folders are new in v0.11.0 and must
be copied too - they are the page background. Without them the pages
still work, but they fall back to a flat brown instead of the gradient.

Restart the app, enable "Drink Menu" under Extensions, tap Settings.

## Roadmap

| Pass | Version | Scope |
|---|---|---|
| 1 | v0.1.0 | Loadable plugin; renderer test page |
| 2 | v0.2.0 | `presets.tcl` data, menu grid, tabs, paging, ml/oz toggle (this version) |
| 3 | v0.3.0 | Detail page with labeled layers, totals, ratio, Single/Double |
| 4 | v0.4.0 | Favorites, hide, overrides, custom drink editor (first settings write) |
| 5 | v0.5.0 | Lumen taskbar button + icon, graceful degrade |
| 6 | v0.5.2 | Glass polish, on-device sizing, text truncation audit |
| 7 | v0.6.0 | Presets locked read-only; editing one always makes a custom copy |
| 8 | v0.6.1 | No alcoholic drinks/ingredients: 43 presets, 19 ingredients, 7 vessels |
| 9 | v0.6.2 | Menu responsiveness: tab/page refresh 584 ms -> 6 ms on the tablet |
| 10 | v0.7.0 | Polish: button radius, ratio-names wrap, light-theme contrast |
| 11 | v0.7.1 | Bugfix: editor name entry no longer over the "Edit custom drink" title |
| 12 | v0.8.0 | Visual alignment with the design mock: big tile cups, glass cards, capsule pills, crema badge border, one filled action per page |
| 13 | v0.9.0 | "+ New drink" on the menu bar (new entry point to the same confirmed save) and "< Prev" / "Next >" chevrons |
| 14 | v0.10.0 | Method steps for all 43 presets and a Method card on the detail page |
| 15 | v0.10.1 | Final mock comparison: the hero cup takes the width the label column can spare; tile names drop one font size before they truncate |
| 16 | v0.10.2 | Wider detail hero card (40% -> 47% of the page width): the cup is a third bigger, the right column keeps every card rule |
| 17 | v0.10.3 | Save as copy is back on fresh copies (shows whenever Save does) |
| 18 | v0.10.4 | The detail cup box measures the bowl, not bowl + handle: the handled cups grow again and their handle runs under the start of the labels |
| 19 | v0.10.5 | The handle ring is ghosted where it passes under the layer labels, full strength beside the bowl |
| 20 | v0.11.0 | The mock's warm brown look: a shipped gradient background PNG per resolution, and the mock palette as the single colour source |
| 21 | v0.12.0 | A tappable favorite star in every tile's top-right corner; the ml badge and the pen move down the same column |
| 22 | v0.12.1 | The tile star is drawn as a polygon, so a favorited star is a real solid gold fill |
| 23 | v0.13.0 | The mock's details: smaller centred cups, a gold ml pill top right, gradient glass cards, a small star top left, a lower header with smaller pills, rounder radii with glass edges, and a gold Done |
| 24 | v0.13.1 | The detail and preview cups keep the card's own text inset from every edge, and the glass highlight ends where the corner curve begins |
| 25 | v0.13.2 | One inset all round the hero and preview cups (equal air above and below a height-bound vessel), and the photo's transparent corner carved at r + 2 so no lit pixel shows outside the outline |
| 26 | v0.13.3 | One continuous card corner: the glass photo bakes the card's edge and highlight in along a true circular corner, and no outline polygon is drawn over a card that has a photo (this version) |

</details>
