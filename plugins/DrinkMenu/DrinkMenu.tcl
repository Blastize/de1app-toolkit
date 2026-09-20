#
# Drink Menu -- implementation (v0.6.2, Pass 9: menu responsiveness;
# presets stay read-only, editing one always creates a custom copy)
#
# Pass 9 refresh contract: the pages create their items ONCE at setup,
# so a canvas id is stable for the life of the app. Every hot-path
# helper resolves a tag through `_ids` (cached) and then drives the raw
# canvas; `_set_vis` replaces `dui item show|hide -initial 1` and keeps
# the st:hidden initial-state tag in sync itself. `dui item config` is
# used only where dui does real work a raw itemconfigure cannot do: a
# dbutton relabel by BARE tag. Timing NOTICE lines are gated by
# `debug_timing` (default 0).
#
# The ONLY write path is `_persist`, which validates and then calls
# `plugins save_settings DrinkMenu` for four keys: unit, favorites,
# hidden (single-tap callers set_unit, toggle_favorite, toggle_hidden)
# and custom (three editor callers, each behind an explicit confirmation
# card: editor_save_custom, editor_save_copy, editor_delete_custom).
# Never from preload, main, setup, show, mode switches or keystrokes. No
# SDB, no history files, no other file I/O beyond sourcing presets.tcl
# (read-only data next to this file). The obsolete "overrides" settings
# key from Pass 5/6 is dropped from memory on load if found on disk (see
# plugin.tcl); presets can never be edited or overwritten by the user.
#
# Two scale sources (ShotHistoryEditor v0.3.2 lesson):
#   - COORDINATES are virtual (the core's ::dui::_base_screen_width x
#     _base_screen_height, 2560x1600); the framework rescales them.
#   - FONTS are physical pixels (negative Tk sizes) from the detected
#     screen, because Tk font objects bypass the coordinate rescale.
# `dui add canvas_item` rescales -width too, so a 1px line is -width 2.
#
# Cup renderer geometry: a vessel is a profile of {frac_height half_width}
# breakpoints from floor (0) to rim (1). A drink's layers are cumulative
# ml/capacity fractions; each layer becomes ONE straight-edged polygon
# sliced from the profile (breakpoints inserted where a layer spans one).
# Tk canvas has no clip path, so layers are never -smooth: a smoothed
# layer would bulge outside the vessel outline. Stemmed glasses draw one
# stem+foot polygon below the bowl; layers never enter it.
#
# Pools: every page creates its items ONCE at setup and rebinds them in
# a refresh proc (raw canvas coords, tablet-verified in v0.1.0). Nothing
# is created at show time.
#
# Tags (v0.2.1 lesson): "<tag>*" is a LITERAL group tag dui adds only to
# compound widgets (dbutton). Plain canvas items are shown/hidden by their
# exact tag; dbuttons by "<tag>*". Always with -initial 1.
#
# Colour (Pass 20, v0.11.0): `mock_palette` is the ONE source -- the
# design mock's :root tokens -- and no skin token is ever read, so the
# pages look the same under every Lumen theme. Everything else is derived
# in `_apply_palette` and applied by `_retheme` on each page show. The
# page background is the mock's radial gradient, shipped as one
# pixel-exact PNG per PHYSICAL resolution (<W>x<H>/bg.png) because a Tk
# canvas cannot draw a gradient and a Tk photo must never be scaled; an
# unshipped size falls back to the flat bg1 rectangle.
#
# Cards (Pass 23, v0.13.0): the same reasoning one level down. A card is
# the mock's `linear-gradient(165deg, white .12, white .045)`, painted by
# `glass_photo` into ONE Tk photo per distinct PHYSICAL size (the twelve
# tiles share one; so do the seven vessel-picker tiles), with the corners
# outside the radius left transparent so the page's own gradient shows
# through. Since Pass 26 (v0.13.3) the photo carries the card's EDGE and
# its top highlight too, so a card is ONE shape and its corner is one
# continuous arc; `glass_card` lays the photo down and draws no outline of
# its own. Photos are made at page SETUP and never in a refresh; a platform
# that refuses one falls back to the flat card_fill rounded rect, which
# keeps the drawn outline because it has no photo to bake it into.
#
# Cards (Pass 29, v1.1.0): the ramp is the real 165-deg DIAGONAL of the
# mock and each family gets its own pair (tile .12 -> .045, card
# .10 -> .035, hero .11 -> .04), so a card is visibly lighter at the
# top-left corner than at the bottom-right; the mock's inset highlight is
# a soft glow band of 6 (tile) or 10 (card, hero) rows fading to the row
# colour. A row is painted as runs of equal quantised colour, so the whole
# set still costs a few thousand `put` calls. The mock's drop shadow is
# NOT painted: Tk photos have no per-pixel alpha, so it would have to live
# in a margin of each photo, and that margin costs 397 KB the 4 MB photo
# budget does not have (see PROJECT_STATE).
#
# Cards (Pass 41, v1.11.0, tonal): the owner saw the result on the tablet
# -- "the glows are fake" -- and the diagnosis is that Tk cannot do glass:
# no alpha, no blur, so a .17 rim + a lit band + a highlight line + a
# shade line stack into a bevelled plastic tile. The look is now TONAL: a
# card is its gradient photo (each family's pair stepped up a little,
# .14 -> .06 for a tile) with a faint .10 hairline edge, and nothing else
# -- glow band 0 rows, no <tag>_spec / <tag>_shade lines, no <tag>_hi line
# on the bar buttons, gold buttons and selected pills rimless, and the
# cup's flat shadow oval at .15 instead of .35. Nothing moved; no
# behaviour changed.
#
# Cards (Pass 42, v1.12.0, anti-aliased): the owner's other note, "jagged
# curves". A Tk photo loaded from PNG data DOES carry per-pixel alpha, and
# Tcl has zlib, so each card photo is now painted as RGBA rows in Tcl,
# PNG-encoded in memory and created with `image create photo -data`: true
# anti-aliased corner arcs, the hairline as a 1 px ring, and the mock's
# drop shadow in a margin of S px round the card (see glass_rgba). The
# hero joins the cards' one radius. The `put` painter of v1.11.0 remains
# the fallback. Pills, badges, chips and buttons are still canvas shapes:
# their turn is the next passes.
#

namespace eval ::plugins::DrinkMenu {
    variable L
    array set L {}

    # Cups created by draw_cup: tag -> dict {page x y w h drink tile_scale}
    # so update_cup can re-geometry the same item pool later.
    variable cups
    array set cups {}

    # Items whose color follows the palette: list of {page tag prop role};
    # dbuttons restyled by _retheme: list of {page tag}.
    variable themed {}
    variable themed_btns {}

    # ------------------------------------------------------------------
    #  Timing instrumentation (Pass 9). OFF by default; the owner turns
    #  it on with `set ::plugins::DrinkMenu::debug_timing 1` (DevBridge
    #  or a console) -- no code change needed. When on, every measured
    #  section emits one NOTICE "DrinkMenu timing <what> <ms>" plus one
    #  "DrinkMenu timing calls <name>=<n> ..." line with the raw canvas /
    #  dui / font call counts of that refresh. Accumulators are in
    #  microseconds; only the log line converts to whole ms. When off,
    #  every site costs one variable read and one `if`.
    # ------------------------------------------------------------------
    variable debug_timing 0
    variable tstat
    array set tstat {}

    proc t_reset {} {
        variable tstat
        array unset tstat
        array set tstat {}
    }
    proc t_add {key us} {
        variable tstat
        if {[info exists tstat($key)]} {
            set tstat($key) [expr {$tstat($key) + $us}]
        } else {
            set tstat($key) $us
        }
    }
    proc t_count {key {n 1}} {
        variable tstat
        if {[info exists tstat(n_$key)]} {
            incr tstat(n_$key) $n
        } else {
            set tstat(n_$key) $n
        }
    }
    proc t_get {key} {
        variable tstat
        if {[info exists tstat($key)]} { return $tstat($key) }
        return 0
    }
    # One log line per section. `us` is microseconds, logged as whole ms.
    proc t_log {what us} {
        catch { msg -NOTICE "DrinkMenu timing $what [expr {int($us / 1000)}]" }
    }
    proc t_dump {keys} {
        variable tstat
        foreach k $keys { t_log $k [t_get $k] }
        set counts {}
        foreach k [lsort [array names tstat n_*]] {
            lappend counts "[string range $k 2 end]=$tstat($k)"
        }
        if {$counts ne ""} {
            catch { msg -NOTICE "DrinkMenu timing calls [join $counts { }]" }
        }
    }

    # ------------------------------------------------------------------
    #  Preset data: sourced from presets.tcl (read-only). On failure all
    #  three dicts stay empty, presets_ok is 0 and the menu shows one
    #  caption line instead of a grid. The plugin still loads.
    # ------------------------------------------------------------------
    variable presets_ok 0
    variable ingredients {}
    variable vessels {}
    variable drinks {}
    variable group_order {straight water milk_small milk_cup chocolate cold}
    # Pass 38: the labels the group picker shows. `custom` is a position,
    # not a family: such drinks sort after every group, in creation
    # order, exactly where all customs used to sit.
    variable group_names {straight "Straight" water "Water" \
        milk_small "Small milk" milk_cup "Milk cup" chocolate "Chocolate" \
        cold "Cold" custom "End of menu"}

    # A stored group is either one of the appendix groups or `custom`.
    proc valid_group {g} {
        variable group_order
        return [expr {$g in $group_order || $g eq "custom"}]
    }

    proc group_label {g} {
        variable group_names
        if {[dict exists $group_names $g]} { return [dict get $group_names $g] }
        return $g
    }
    variable _presets_file [file join [file dirname [info script]] presets.tcl]

    proc load_presets {} {
        variable presets_ok
        variable ingredients
        variable vessels
        variable drinks
        variable _presets_file
        set presets_ok 0
        if {[catch {
            source $_presets_file
            # Must be well-formed dicts, else treat as a load failure.
            dict size $ingredients
            dict size $vessels
            dict size $drinks
            if {[dict size $drinks] == 0} { error "no drinks defined" }
        } err]} {
            catch { msg -ERROR "DrinkMenu: presets.tcl failed to load: $err" }
            set ingredients {}
            set vessels {}
            set drinks {}
            return 0
        }
        set presets_ok 1
        return 1
    }
    load_presets

    # ------------------------------------------------------------------
    #  UI state. ui_unit mirrors settings(unit) (persisted on tap); tab
    #  and page are session-only. `hidden` is a pseudo-tab reachable
    #  from the "Hidden (N)" button, never a pill.
    # ------------------------------------------------------------------
    variable ui_tab all
    variable ui_page 1
    variable ui_unit ml
    variable page_size 12
    # Pass 45: the favorites tab is worded like its neighbours (it was an
    # icon-only star pill among worded pills).
    variable tabs {all "All" hot "Hot" cold "Cold" milk "Milk" nomilk "No milk" fav "Favorites" custom "Custom"}
    variable empty_captions {
        fav    "No favorites yet. Open a drink and tap Favorite."
        custom "No custom drinks yet. Tap + New drink, or open a drink and tap Copy & edit."
        hidden "No hidden drinks."
    }

    # ------------------------------------------------------------------
    #  Persisted state helpers (settings array lives in plugin.tcl).
    # ------------------------------------------------------------------

    proc _favorites {} {
        variable settings
        set v {}
        catch { set v $settings(favorites) }
        return $v
    }

    proc _hidden {} {
        variable settings
        set v {}
        catch { set v $settings(hidden) }
        return $v
    }

    proc is_favorite {id} { return [expr {$id in [_favorites]}] }
    proc is_hidden {id}   { return [expr {$id in [_hidden]}] }

    proc _customs {} {
        variable settings
        set v {}
        catch { set v $settings(custom) }
        if {[catch { dict size $v }]} { set v {} }
        return $v
    }

    proc is_custom {id} { return [dict exists [_customs] $id] }

    # Does a drink id exist anywhere (preset or custom)?
    proc drink_exists {id} {
        variable drinks
        return [expr {[dict exists $drinks $id] || [is_custom $id]}]
    }

    # THE drink accessor: custom if present, else preset, else "".
    # Presets are read-only (Pass 7): every display/logic read goes
    # through here; only the loader and _validate_settings touch the
    # presets dict directly.
    proc get_drink {id} {
        variable drinks
        set cu [_customs]
        if {[dict exists $cu $id]} { return [dict get $cu $id] }
        if {[dict exists $drinks $id]} { return [dict get $drinks $id] }
        return ""
    }

    # All ids in display order: preset ids (presets.tcl order) then
    # custom ids in creation (dict) order.
    proc all_ids {} {
        variable drinks
        return [concat [dict keys $drinks] [dict keys [_customs]]]
    }

    # Method steps (Pass 14). Pure: takes whatever is stored under the
    # optional `steps` key and returns the list this plugin is willing to
    # display -- each entry trimmed, non-empty, at most 80 characters,
    # at most 6 entries. A value that is not a well-formed list becomes
    # the empty list. Never a reason to reject a drink: a bad steps value
    # is dropped (NOTICE from _validate_settings), the drink survives.
    proc clean_steps {raw} {
        if {[catch { llength $raw } n]} { return {} }
        set out {}
        foreach s $raw {
            set s [string trim $s]
            if {$s eq ""} { continue }
            if {[string length $s] > 80} { continue }
            lappend out $s
            if {[llength $out] >= 6} { break }
        }
        return $out
    }

    # ---- Garnish (Pass 36) ----
    # Stored as it always was: a list of tokens with underscores for
    # spaces ({orange_peel cinnamon}), displayed "orange peel, cinnamon".
    # clean_garnish is the load-repair (mirrors clean_steps: never a
    # reason to drop a drink); the to/from pair converts for the editor's
    # free-text entry. At most 4 entries of at most 24 chars each.
    proc clean_garnish {raw} {
        if {[catch { llength $raw }]} { return {} }
        set out {}
        foreach g $raw {
            set g [string trim $g]
            if {$g eq ""} { continue }
            set g [string range $g 0 23]
            lappend out $g
            if {[llength $out] >= 4} { break }
        }
        return $out
    }

    proc garnish_to_text {g} {
        set parts {}
        foreach x $g { lappend parts [string map {_ " "} $x] }
        return [join $parts ", "]
    }

    proc garnish_from_text {txt} {
        set out {}
        foreach part [split $txt ","] {
            set part [string trim $part]
            if {$part eq ""} { continue }
            regsub -all {\s+} $part "_" part
            set part [string range $part 0 23]
            lappend out $part
            if {[llength $out] >= 4} { break }
        }
        return $out
    }

    # ---- Step editing helpers (Pass 37; pure) ----
    # The editor works on the cleaned list; the DETAIL card pools
    # det_met_pool (4) lines, so that is the editor's cap too -- what you
    # write is what the drink page can show. clean_steps' own tolerance
    # (6 x 80) stays as the load repair.
    variable steps_max 4

    # Replace step i, or append when i is -1 (capped). Empty text is the
    # caller's business (the form treats it as "no change").
    proc steps_with {steps i txt} {
        variable steps_max
        set txt [string range [string trim $txt] 0 79]
        if {$txt eq ""} { return $steps }
        if {$i == -1} {
            if {[llength $steps] >= $steps_max} { return $steps }
            lappend steps $txt
            return $steps
        }
        if {$i < 0 || $i >= [llength $steps]} { return $steps }
        return [lreplace $steps $i $i $txt]
    }

    proc steps_remove {steps i} {
        if {$i < 0 || $i >= [llength $steps]} { return $steps }
        return [lreplace $steps $i $i]
    }

    # Steps are ordered first -> last and displayed the same way, so a
    # row's "up" is simply index - 1.
    proc steps_move {steps i dir} {
        set j [expr {$i + $dir}]
        set n [llength $steps]
        if {$i < 0 || $i >= $n || $j < 0 || $j >= $n || $dir == 0} { return $steps }
        set a [lindex $steps $i]
        set steps [lreplace $steps $i $i [lindex $steps $j]]
        return [lreplace $steps $j $j $a]
    }

    # The steps of a drink dict (preset or custom), already cleaned.
    proc drink_steps {drink} {
        if {[catch { dict exists $drink steps } has] || !$has} { return {} }
        return [clean_steps [dict get $drink steps]]
    }

    # Drink validation -> {ok msg}. Rules: name non-empty after trim and
    # at most 24 chars; vessel exists; 1-6 layers; every ingredient
    # exists; every ml a whole number from 5 to the capacity; at least
    # one coffee-role layer; total within the capacity. An optional
    # `steps` list is accepted and never fatal (see clean_steps): the
    # repair happens in _validate_settings, so a drink is never lost
    # over its method text.
    proc validate_drink {drink} {
        variable vessels
        variable ingredients
        if {[catch { dict size $drink }]} { return [list 0 [translate "Not a drink"]] }
        set name ""
        catch { set name [string trim [dict get $drink name]] }
        if {$name eq ""} { return [list 0 [translate "Name is empty"]] }
        if {[string length $name] > 24} { return [list 0 [translate "Name too long (max 24)"]] }
        set vessel ""
        catch { set vessel [dict get $drink vessel] }
        if {![dict exists $vessels $vessel]} { return [list 0 [translate "Unknown vessel"]] }
        set cap [dict get $vessels $vessel capacity]
        # Pass 33: optional per-drink custom ingredient defs. Malformed
        # defs fail the drink (settings load then drops it, as any other
        # invalid custom drink).
        set cings {}
        catch { set cings [dict get $drink custom_ings] }
        if {[catch { dict size $cings }]} { return [list 0 [translate "Custom ingredients are malformed"]] }
        dict for {cid cdef} $cings {
            if {![regexp {^c[0-9]+$} $cid]} { return [list 0 "[translate "Bad custom ingredient id"]: $cid"] }
            if {[catch { dict size $cdef }]} { return [list 0 [translate "Custom ingredient is malformed"]] }
            set cn ""
            catch { set cn [string trim [dict get $cdef name]] }
            if {$cn eq "" || [string length $cn] > 24} { return [list 0 [translate "Custom ingredient needs a name (max 24)"]] }
            set cc ""
            catch { set cc [dict get $cdef color] }
            if {![regexp {^#[0-9a-fA-F]{6}$} $cc]} { return [list 0 [translate "Custom ingredient colour is invalid"]] }
            set cu ""
            catch { set cu [dict get $cdef unit] }
            if {$cu ni {ml g}} { return [list 0 [translate "Custom ingredient unit must be ml or g"]] }
        }
        set layers {}
        catch { set layers [dict get $drink layers] }
        if {[catch { llength $layers }] || [llength $layers] % 2} { return [list 0 [translate "Layers are malformed"]] }
        set n [expr {[llength $layers] / 2}]
        if {$n < 1} { return [list 0 [translate "Add at least one layer"]] }
        if {$n > 6} { return [list 0 [translate "Too many layers (max 6)"]] }
        set total 0
        set coffee 0
        foreach {ing ml} $layers {
            if {![dict exists $ingredients $ing] && ![dict exists $cings $ing]} {
                return [list 0 "[translate "Unknown ingredient"]: $ing"]
            }
            if {![string is integer -strict $ml]} { return [list 0 [translate "Amounts must be whole numbers"]] }
            if {$ml < 5} { return [list 0 [translate "Amount must be 5 or more"]] }
            set total [expr {$total + $ml}]
            set role base
            catch { set role [dict get $ingredients $ing role] }
            if {$role eq "coffee"} { set coffee 1 }
        }
        if {!$coffee} { return [list 0 [translate "Needs an espresso layer"]] }
        if {$total > $cap} {
            return [list 0 "[translate "Exceeds vessel by"] [expr {$total - $cap}] ml"]
        }
        return [list 1 ""]
    }

    # Corrects the persisted keys IN MEMORY: unit in {ml oz};
    # favorites/hidden are lists of existing drink ids (preset or
    # custom), no duplicates, unknown ids dropped (NOTICE); custom is a
    # dict of valid drinks, invalid entries dropped (NOTICE). Returns the
    # number of corrections. Called once after load (no write) and
    # inside _persist (before the write), so an invalid value is never
    # written.
    proc _validate_settings {} {
        variable settings
        set fixes 0
        set unit ""
        catch { set unit $settings(unit) }
        if {$unit ni {ml oz}} {
            catch { msg -NOTICE "DrinkMenu: settings unit '$unit' corrected to ml" }
            set settings(unit) ml
            incr fixes
        }
        # Custom drinks (favorites/hidden may reference them). Presets
        # are never validated here: they are read-only data from
        # presets.tcl, not user settings.
        set raw {}
        catch { set raw $settings(custom) }
        if {[catch { dict size $raw }]} {
            catch { msg -NOTICE "DrinkMenu: settings custom was not a dict, reset" }
            set settings(custom) {}
            set raw {}
            incr fixes
        }
        set clean {}
        foreach {id d} $raw {
            if {![regexp {^custom_[0-9]+(_[0-9]+)?$} $id]} {
                catch { msg -NOTICE "DrinkMenu: settings custom dropped bad id '$id'" }
                incr fixes
                continue
            }
            # Pass 38: the group is the USER'S choice now -- sanitized,
            # not forced. Anything unknown falls back to `custom` (end of
            # the menu), which is also what every pre-1.8 drink carries.
            catch {
                dict set d source custom
                set g custom
                catch { set g [dict get $d group] }
                if {![valid_group $g]} {
                    catch { msg -NOTICE "DrinkMenu: settings custom '$id' group '$g' -> custom" }
                    set g custom
                    incr fixes
                }
                dict set d group $g
            }
            lassign [validate_drink $d] ok why
            if {!$ok} {
                catch { msg -NOTICE "DrinkMenu: settings custom dropped '$id': $why" }
                incr fixes
                continue
            }
            # Method steps (Pass 14) are optional; a malformed value is
            # repaired in memory (never a reason to drop the drink) and,
            # like every other correction here, only reaches settings.tdb
            # if a later confirmed save runs -- load itself writes nothing.
            if {[dict exists $d steps]} {
                set st [clean_steps [dict get $d steps]]
                if {$st ne [dict get $d steps]} {
                    catch { msg -NOTICE "DrinkMenu: settings custom '$id' steps repaired ([llength $st] kept)" }
                    dict set d steps $st
                    incr fixes
                }
            }
            # Garnish (Pass 36): repaired in memory exactly as steps are,
            # never a reason to drop the drink.
            if {[dict exists $d garnish]} {
                set gn [clean_garnish [dict get $d garnish]]
                if {$gn ne [dict get $d garnish]} {
                    catch { msg -NOTICE "DrinkMenu: settings custom '$id' garnish repaired ([llength $gn] kept)" }
                    dict set d garnish $gn
                    incr fixes
                }
            }
            dict set clean $id $d
        }
        if {$clean ne $raw} { set settings(custom) $clean }
        foreach key {favorites hidden} {
            set raw {}
            catch { set raw $settings($key) }
            set clean {}
            if {[catch { llength $raw }]} {
                catch { msg -NOTICE "DrinkMenu: settings $key was not a list, reset" }
                set settings($key) {}
                set raw {}
                incr fixes
            }
            foreach id $raw {
                if {![drink_exists $id]} {
                    catch { msg -NOTICE "DrinkMenu: settings $key dropped unknown id '$id'" }
                    incr fixes
                    continue
                }
                if {$id in $clean} { incr fixes; continue }
                lappend clean $id
            }
            if {$clean ne $raw} { set settings($key) $clean }
        }
        return $fixes
    }

    # THE write path. Validates, then plugins save_settings inside a
    # catch. Three callers only: set_unit, toggle_favorite, toggle_hidden.
    proc _persist {reason} {
        _validate_settings
        if {[catch { plugins save_settings DrinkMenu } err]} {
            catch { msg -ERROR "DrinkMenu: saving settings ($reason) failed: $err" }
            return 0
        }
        catch { msg -NOTICE "DrinkMenu saved settings: $reason" }
        return 1
    }
    # Slot i -> drink id currently bound ("" when the slot is hidden).
    variable slot_ids {}
    # visible_drinks cache: tab -> ordered id list.
    variable tab_cache
    array set tab_cache {}
    # Pass 9 refresh caches. geom_cache: vessel + design box -> the
    # vessel_geometry dict (pure, only depends on the layout). Cleared by
    # _init_layout. render_cache: cup box + drink signature -> the whole
    # set of PHYSICAL polygon coordinate lists a cup needs, so a slot
    # that has been drawn once is pure canvas work afterwards; cleared by
    # invalidate_cache (custom drinks) and _init_layout. fit_cache:
    # font + width + text -> the ellipsised name. item_cache /
    # vis_cache: see invalidate_items.
    variable geom_cache
    array set geom_cache {}
    variable render_cache
    array set render_cache {}
    variable fit_cache
    array set fit_cache {}
    variable item_cache
    array set item_cache {}
    variable vis_cache
    array set vis_cache {}
    # text_cache / font_cache / pill_cache: the last string written to a
    # text item, the last font written to one (Pass 15: a tile name that
    # does not fit the tile at the primary font is written at the caption
    # font instead) and the last face written to a pill, so an unchanged
    # one is not rewritten. All three are dropped whenever vis_cache is
    # (page show), so a palette change or a repaint always lands.
    variable text_cache
    array set text_cache {}
    variable font_cache
    array set font_cache {}
    variable pill_cache
    array set pill_cache {}
    # Pass 21: the last colour written to a pooled item whose fill is
    # driven by state rather than by the palette alone (the tile star).
    variable fill_cache
    array set fill_cache {}
    # Detail page state.
    variable detail_id ""
    variable detail_size single
    # Editor state (session only; the working dict is never persisted
    # until a confirmed save goes through _persist). edit_kind is always
    # "custom" (Pass 7: presets are read-only). edit_source_id is the id
    # the draft was opened from: a preset id when "Copy & edit" generated
    # a fresh, not-yet-saved id in edit_id, otherwise the same id as
    # edit_id. It is used to carry the garnish across a copy; whether the
    # draft has ever been saved is [is_custom edit_id].
    variable edit_id ""
    variable edit_kind custom
    variable edit_source_id ""
    variable edit_drink {}
    variable edit_name ""
    variable edit_dirty 0
    variable edit_mode layers
    variable edit_pending ""
    variable edit_loading 0
    variable edit_note ""
    # The page the editor was opened FROM, and the only page it returns
    # to (Pass 13). "DrinkMenu_detail" for Copy & edit / Edit, which are
    # always reached from a detail page; "DrinkMenu_main" for the menu's
    # "+ New drink", where no detail page for the draft exists yet. Set
    # once at open time; editor_leave keeps using the same mechanism it
    # always has (_return_to_page), only the target varies.
    variable edit_origin DrinkMenu_detail
    variable name_trace_set 0

    # Pass 20 (v0.11.0): the design mock's warm brown tokens, and the ONLY
    # colour source these three pages have. Straight out of
    # passes/DrinkMenu/design/DrinkMenu_preview.html `:root`:
    #
    #   --bg1 #1c1512   --ink #f4ede3   --ink-2 #c9b8a5   --ink-3 #8f7f6f
    #   --gold #e6c58c  --gold-ink #2b1a0f
    #
    # bg0 #3b2b22 and bg2 #100c0a are the other two stops of the page
    # gradient; they live in the shipped background PNGs (tools/make_bg.py)
    # and never in a canvas fill, so only bg1 -- the ramp's middle, and the
    # flat fallback when no PNG matches the screen -- is a token here.
    # Everything else in the palette is DERIVED from these six through
    # _apply_palette, so a card is always a fixed step above the page.
    variable mock_palette {
        bg        "#1c1512"
        ink       "#f4ede3"
        ink_2     "#c9b8a5"
        ink_3     "#8f7f6f"
        crema     "#e6c58c"
    }
    variable mock_crema_ink "#2b1a0f"
    # The mock's glass whites, as fractions of white: .075 body, and the
    # edge. Pass 41 (v1.11.0, tonal restyle): the mock's .17 rim plus its
    # .16 inset top highlight read as a bevelled plastic tile on the
    # tablet, where Tk has no alpha or blur to make them glass. The edge is
    # now a faint .10 hairline (the flat-UI card border), the inset
    # highlight is gone (mock_glass_hi and the bar buttons' <tag>_hi line
    # were deleted), and so are the glow band, the <tag>_spec highlight
    # line and the <tag>_shade line.
    variable mock_glass      0.075
    variable mock_glass_edge 0.10
    # Pass 23: a card is not a flat step above the page any more, it is the
    # mock's `linear-gradient(165deg, rgba(255,255,255,.12),
    # rgba(255,255,255,.045))` painted into a Tk photo (glass_photo), plus
    # the mock's `inset 0 1px 0 rgba(255,255,255,.26)` top highlight.
    # Pass 23 to v1.0.1 used ONE vertical ramp for every card; Pass 29 gives
    # each mock family its own pair and paints the real 165-deg diagonal
    # (see mock_glass_kinds), so the cache key is "<w>x<h>x<r>x<kind>".
    # mock_glass_top / _bot stay the TILE pair: they are the page's lightest
    # and darkest card surfaces, and _apply_palette derives c_spec, the
    # contrast floor and btn_press from them.
    # Pass 41: the tile pair steps up (.12 -> .14, .045 -> .06) so a card
    # still separates from the page's light top-left corner without the
    # bright rim it used to lean on; .14 is the most the tile star's
    # c_ink_3 outline can take and keep its 3:1 mark contrast (CONTRAST).
    variable mock_glass_top  0.14
    variable mock_glass_bot  0.06
    variable mock_card_hi    0.26
    # Pass 29 (v1.1.0): the three card families of the mock, as
    #   <kind> {<top white fraction> <bottom fraction> <top-edge glow
    #           fraction> <glow band height in px>}
    # .tile is `linear-gradient(165deg, white .12, white .045)` with
    # `inset 0 1px 0 rgba(255,255,255,.26)`, .card is .10 -> .035 with .22,
    # .hero is .11 -> .04 with .26 (passes/DrinkMenu/design/
    # DrinkMenu_preview.html, .tile/.card/.hero). The inset highlight is
    # painted as a soft band of `glow` rows fading from the highlight
    # colour to the row colour, not as the single lit row v0.13.3 baked.
    # Pass 41 (tonal): every family's highlight fraction and glow band
    # are 0 -- the painter's band code is kept, it just never lights a
    # row -- and each pair steps up by the same .02 / .015 as the tile
    # pair above, so the three families keep their relative order.
    variable mock_glass_kinds {
        tile {0.14 0.06  0 0}
        card {0.12 0.05  0 0}
        hero {0.13 0.055 0 0}
    }
    # The 165-deg direction of the mock's gradients, as the pass states it:
    # the colour at (x, y) follows t = 0.906 * yn + 0.423 * xn normalised
    # over the card, so the lightest corner is the top-left and the darkest
    # the bottom-right. xn / yn run 0 -> 1 over w - 1 / h - 1, so the two
    # extreme corners land exactly on the family's pair.
    variable mock_glass_dy   0.906
    variable mock_glass_dx   0.423
    # The ramp is quantised into this many steps so a row can be painted as
    # a handful of equal-colour runs instead of a put per pixel. The whole
    # ramp spans about 17 of 255 in the red channel over this near-black
    # page, so 18 steps is finer than the 8-bit surface itself: the
    # quantisation is invisible, and it holds a row to at most 7 runs
    # (0.423 / 1.329 of the ramp lies across the width).
    variable mock_glass_steps 18
    # The badge / chip well: black at 38% over the card body (mock .tile .ml)
    # and its gold hairline (mock: 1px solid rgba(230,197,140,.35)).
    variable mock_well       0.38
    variable mock_well_brd   0.35
    # Pass 30 -- the mock's cup shadow. `cup()` draws, before the bowl,
    #   <ellipse cx=cx cy=bot+3 rx=bw/2+10 ry=3 fill=rgba(0,0,0,.35)>
    # in its 100-unit box: a flat dark ellipse whose TOP touches the cup's
    # floor and which reaches 6 units below it, 10 units wider than the
    # floor on each side, at 35% black. The three numbers are design units
    # (the same units presets.tcl gives the vessels, scaled by the fit's
    # own `s`); the fraction is an alpha Tk cannot draw, so it is a blend
    # towards black over the surface the shadow sits on.
    # Pass 41: .35 of black is a soft shadow in the mock's SVG and a hard
    # dark sticker as a flat Tk oval; .15 keeps the grounding cue without
    # the sticker. A real soft shadow needs alpha, i.e. a PNG (pass 42+).
    variable mock_shadow_alpha 0.15
    variable mock_shadow_dy    3
    variable mock_shadow_dx    10
    # The row of the card the shadow sits on, as a fraction of the card's
    # height: the cup zones put every floor in the card's lower quarter
    # (the tile's is 20..226 of 322). Only the SURFACE colour is taken from
    # it -- a family's whole ramp spans about 7 of 255 levels, so the exact
    # row moves the darkened result by at most a level either way, which is
    # why one colour per family is enough and no cup needs its own.
    variable mock_shadow_row   0.75

    # ------------------------------------------------------------------
    #  Derived data (pure)
    # ------------------------------------------------------------------

    proc drink_total {drink} {
        set total 0
        foreach {ing ml} [dict get $drink layers] { set total [expr {$total + $ml}] }
        return $total
    }

    # Union of the flags of the drink's ingredients.
    proc drink_flags {drink} {
        variable ingredients
        set flags {}
        foreach {ing ml} [dict get $drink layers] {
            if {[dict exists $ingredients $ing flags]} {
                foreach f [dict get $ingredients $ing flags] {
                    if {$f ni $flags} { lappend flags $f }
                }
            }
        }
        return $flags
    }

    # Tab membership per the appendix, on the EFFECTIVE drink. `fav`
    # reads the persisted favorites; `custom` is custom drinks only
    # (presets are read-only, Pass 7); `hidden` is the recovery
    # pseudo-tab. Hidden drinks are excluded from every real tab by
    # visible_drinks.
    proc drink_in_tab {drink tab {id ""}} {
        switch -- $tab {
            all    { return 1 }
            hot    { return [expr {"cold" ni [drink_flags $drink]}] }
            cold   { return [expr {"cold" in [drink_flags $drink]}] }
            milk   { return [expr {"dairy" in [drink_flags $drink]}] }
            nomilk { return [expr {"dairy" ni [drink_flags $drink]}] }
            fav    { return [expr {$id ne "" && [is_favorite $id]}] }
            custom { return [expr {$id ne "" && [is_custom $id]}] }
            hidden { return [expr {$id ne "" && [is_hidden $id]}] }
        }
        return 0
    }

    # Ordered id list for a tab: presets in appendix group order, then
    # custom drinks in creation order; flags come from the effective
    # drink. Hidden ids are left out of every tab except `hidden`
    # itself. Cached per tab; invalidate_cache runs on any
    # favorites/hidden/custom change.
    proc visible_drinks {tab} {
        variable drinks
        variable group_order
        variable tab_cache
        if {[info exists tab_cache($tab)]} { return $tab_cache($tab) }
        set hidden [_hidden]
        set ids {}
        set ordered {}
        # Pass 38: a custom drink with a chosen group sorts WITH that
        # group, after its presets, in creation order; group `custom`
        # (and anything unknown) keeps the old place at the very end.
        set customs [_customs]
        foreach g $group_order {
            foreach {id d} $drinks {
                if {[dict get $d group] eq $g} { lappend ordered $id }
            }
            foreach {id d} $customs {
                set cg custom
                catch { set cg [dict get $d group] }
                if {$cg eq $g} { lappend ordered $id }
            }
        }
        # Presets with an unknown group still show, after the known ones.
        foreach {id d} $drinks {
            if {[dict get $d group] ni $group_order} { lappend ordered $id }
        }
        foreach {id d} $customs {
            set cg custom
            catch { set cg [dict get $d group] }
            if {$cg ni $group_order} { lappend ordered $id }
        }
        foreach id $ordered {
            if {$tab ne "hidden" && $id in $hidden} { continue }
            set d [get_drink $id]
            if {$d eq ""} { continue }
            if {[drink_in_tab $d $tab $id]} { lappend ids $id }
        }
        set tab_cache($tab) $ids
        return $ids
    }

    proc invalidate_cache {} {
        variable tab_cache
        variable render_cache
        variable fit_cache
        array unset tab_cache
        array set tab_cache {}
        # A custom drink may have gained, lost or renamed layers.
        array unset render_cache
        array unset fit_cache
    }

    # Pass 9 caches that are keyed by canvas identity rather than by
    # drink data. `item_cache` maps page/tag -> canvas ids (items are
    # created once at setup and never destroyed, so the ids are stable
    # for the life of the app; each page's setup clears its own entries).
    # `vis_cache` remembers the visibility we last wrote for a tag, so a
    # refresh only touches the tags that actually change. A page show
    # re-applies live states from the initial-state tags, which is what
    # vis_cache already holds, but it is dropped there anyway so a
    # repaint can never inherit a stale belief.
    proc invalidate_items {{page ""}} {
        variable item_cache
        if {$page eq ""} {
            array unset item_cache
        } else {
            array unset item_cache $page,*
        }
        invalidate_visibility $page
    }

    proc invalidate_visibility {{page ""}} {
        variable vis_cache
        variable text_cache
        variable font_cache
        variable pill_cache
        variable fill_cache
        variable image_cache
        if {$page eq ""} {
            array unset vis_cache
            array unset text_cache
            array unset font_cache
            array unset pill_cache
            array unset fill_cache
            array unset image_cache
        } else {
            array unset vis_cache $page,*
            array unset text_cache $page,*
            array unset font_cache $page,*
            array unset pill_cache $page,*
            array unset fill_cache $page,*
            array unset image_cache $page,*
        }
    }

    # ------------------------------------------------------------------
    #  Custom ingredients (Pass 33)
    # ------------------------------------------------------------------
    # A drink dict MAY carry `custom_ings`: c<N> -> {name .. color #rrggbb
    # unit ml|g}, referenced from `layers` exactly like a preset id. The
    # defs live INSIDE the drink, so copies carry them and nothing outside
    # settings(custom) changes shape. A custom def has no role and no
    # flags (role reads base, flags read {}), so tabs, the ratio's coffee
    # side and 2-shot doubling behave exactly as before.

    # Effective definition of one ingredient id for THIS drink: preset
    # first, then the drink's own defs; {} when neither knows it.
    proc ing_def {drink ing} {
        variable ingredients
        if {[dict exists $ingredients $ing]} { return [dict get $ingredients $ing] }
        # No `return` inside the catch (a return is itself caught); the
        # dict get throws on a missing key and d stays {}.
        set d {}
        if {$drink ne ""} {
            catch { set d [dict get $drink custom_ings $ing] }
        }
        return $d
    }

    proc ing_prop {drink ing prop dflt} {
        set d [ing_def $drink $ing]
        if {[dict exists $d $prop]} { return [dict get $d $prop] }
        return $dflt
    }

    # The unit ONE LAYER displays in: g only for a custom def that says
    # so; everything else is ml (and follows the ml/oz toggle).
    proc layer_unit {drink ing} {
        return [ing_prop $drink $ing unit ml]
    }

    # A layer's amount as the label shows it: "10 g" for a g layer, no
    # matter the ml/oz display toggle (mass does not convert); otherwise
    # format_amount's "60 ml" / "2.0 oz".
    proc format_layer_amount {drink ing amt {unit ""}} {
        if {[layer_unit $drink $ing] eq "g"} {
            return [format "%d g" [expr {int(round($amt))}]]
        }
        return [format_amount $amt $unit]
    }

    # The custing editor mode's session state and its fixed swatch row
    # (layer colours are marks, not text: no contrast floor applies).
    # cust_edit_id (Pass 34): "" while adding a NEW ingredient; the def id
    # (c<N>) while editing an existing one -- then Add layer reads "Save"
    # and applies the form to that def in place, adding no layer.
    # cust_edit_color keeps the def's original colour so a colour that is
    # not one of the twelve swatches (hand-edited settings) survives a
    # save that never touched the swatches (cust_sel stays -1).
    variable cust_name ""
    variable cust_unit ml
    variable cust_sel 0
    variable cust_edit_id ""
    variable cust_edit_color ""
    variable cust_colors [list \
        "#f4e3c1" "#e8c39e" "#b5651d" "#7b3f00" "#4a2c17" "#c0392b" \
        "#e67e22" "#f1c40f" "#7fb069" "#2e86ab" "#d7e6ec" "#f7f1e6"]

    # "60 ml" or "2.0 oz" (1 fl oz = 29.5735 ml, one decimal). Storage
    # and math stay in ml; oz is display-only.
    proc format_amount {ml {unit ""}} {
        variable ui_unit
        if {$unit eq ""} { set unit $ui_unit }
        if {$unit eq "oz"} {
            return [format "%.1f oz" [expr {double($ml) / 29.5735}]]
        }
        return [format "%d ml" [expr {int(round($ml))}]]
    }

    # The number alone ("180" / "6.1") for the totals figure.
    proc amount_number {ml {unit ""}} {
        variable ui_unit
        if {$unit eq ""} { set unit $ui_unit }
        if {$unit eq "oz"} { return [format "%.1f" [expr {double($ml) / 29.5735}]] }
        return [format "%d" [expr {int(round($ml))}]]
    }

    proc page_count {n} {
        variable page_size
        if {$n <= 0} { return 1 }
        return [expr {($n + $page_size - 1) / $page_size}]
    }

    # Ratio line (v0.3.1: coffee first): all `coffee`-role layers first,
    # in layer order, same ingredient merged; then every other
    # non-`minor` layer in layer order, adjacent equal ingredients
    # merged. Normalized to the first coffee layer = 1, one decimal with
    # a trailing ".0" trimmed, joined " : ". The cup and the chips keep
    # true layer order; only this line reorders. Returns
    # {ratio_string names_string}; both empty when no coffee layer.
    proc drink_ratio {drink} {
        variable ingredients
        set coffee {}
        set others {}
        foreach {ing ml} [dict get $drink layers] {
            set role base
            catch { set role [dict get $ingredients $ing role] }
            if {$role eq "minor"} { continue }
            if {$role eq "coffee"} {
                set merged 0
                for {set i 0} {$i < [llength $coffee]} {incr i} {
                    if {[lindex $coffee $i 0] eq $ing} {
                        lset coffee $i 1 [expr {[lindex $coffee $i 1] + $ml}]
                        set merged 1
                        break
                    }
                }
                if {!$merged} { lappend coffee [list $ing $ml $role] }
            } elseif {[llength $others] > 0 && [lindex $others end 0] eq $ing} {
                lset others end 1 [expr {[lindex $others end 1] + $ml}]
            } else {
                lappend others [list $ing $ml $role]
            }
        }
        if {[llength $coffee] == 0} { return [list "" ""] }
        set parts [concat $coffee $others]
        set base [lindex $coffee 0 1]
        if {$base <= 0} { return [list "" ""] }
        set nums {}
        set names {}
        foreach p $parts {
            lassign $p ing ml
            set v [format "%.1f" [expr {double($ml) / $base}]]
            regsub {\.0$} $v "" v
            lappend nums $v
            # Pass 33: a custom layer's typed name, never its c<N> id.
            lappend names [ing_prop $drink $ing name $ing]
        }
        return [list [join $nums " : "] [join $names ", "]]
    }

    # 1 shot / 2 shots (v0.3.1): `double` multiplies only the
    # `coffee`-role layers by 2, everything else unchanged. Then, while
    # the total exceeds the vessel's capacity and size_up differs from
    # the current vessel, step up (at most two steps). `overflow` is set
    # if it still exceeds. Returns the drink dict plus `overflow` and
    # `steps`.
    proc sized_drink {drink size} {
        variable vessels
        variable ingredients
        set d $drink
        if {$size eq "double"} {
            set layers {}
            foreach {ing ml} [dict get $drink layers] {
                set role base
                catch { set role [dict get $ingredients $ing role] }
                lappend layers $ing [expr {$role eq "coffee" ? $ml * 2 : $ml}]
            }
            dict set d layers $layers
        }
        set total [drink_total $d]
        set vessel [dict get $d vessel]
        set cap 0
        catch { set cap [dict get $vessels $vessel capacity] }
        # How many times the vessel was stepped up. Named `size_ups`
        # since Pass 14: this derived key used to be called `steps`,
        # which now collides with a drink's own method steps (the
        # sized dict is a copy of the drink, so it would have
        # overwritten them with 0/1/2 on the detail page).
        set ups 0
        if {$size eq "double"} {
            while {$ups < 2 && $cap > 0 && $total > $cap} {
                set up $vessel
                catch { set up [dict get $vessels $vessel size_up] }
                if {$up eq $vessel || ![dict exists $vessels $up]} { break }
                set vessel $up
                set cap [dict get $vessels $up capacity]
                dict set d vessel $vessel
                incr ups
            }
        }
        dict set d size_ups $ups
        dict set d overflow [expr {$cap > 0 && $total > $cap ? 1 : 0}]
        return $d
    }

    # ------------------------------------------------------------------
    #  DE1 tie-ins (Pass 40)
    # ------------------------------------------------------------------
    # ONE explicit tap ("To machine" on the detail page) applies what the
    # drink defines: its linked profile (custom drinks only, stamped in
    # the editor) and/or the hot-water volume its hot_water layers ask
    # for. NOTHING is automatic: no page load, show, event or timer
    # touches the machine or the app's settings; the only timer is the
    # 1 s debounce Lumen's own settings use, armed by the tap itself.
    # Mechanisms are copied from proven code, not invented:
    #   profile   ::select_profile <filename>   (core vars.tcl:2932; the
    #             call DYE.tcl:1605 makes)
    #   water     set ::settings(water_volume) N (clamped 10..250), then
    #             debounced `save_settings; save_settings_to_de1` --
    #             Lumen skin.tcl:2816/2685, copied
    #   busy      connected and not Idle/Sleep/GoingToSleep refuses the
    #             tap (DevBridge's guard, copied; fails closed)

    # The hot-water amount a drink asks of the machine: the sum of its
    # hot_water layers (pure; call with the SIZED drink).
    proc drink_hot_water {drink} {
        set total 0
        foreach {ing ml} [dict get $drink layers] {
            if {$ing eq "hot_water"} { set total [expr {$total + $ml}] }
        }
        return $total
    }

    # Clamped to the machine UI's own 10..250 range (Lumen's clamp); 0
    # means "the drink asks for no hot water".
    proc water_target {ml} {
        if {![string is double -strict $ml] || $ml <= 0} { return 0 }
        set n [expr {round(double($ml))}]
        if {$n < 10} { set n 10 } elseif {$n > 250} { set n 250 }
        return $n
    }

    # {filename title} when the drink carries a profile link, else {}.
    proc drink_profile {drink} {
        set fn ""
        catch { set fn [string trim [dict get $drink profile_fn]] }
        if {$fn eq ""} { return {} }
        set title $fn
        catch {
            set t [string trim [dict get $drink profile_title]]
            if {$t ne ""} { set title $t }
        }
        return [list $fn $title]
    }

    # DevBridge's busy guard, copied: "" while disconnected or resting,
    # else the state name; fails closed on an unreadable state.
    proc _machine_busy {} {
        set handle unknown
        catch { set handle $::de1(device_handle) }
        if {$handle eq "0"} { return "" }
        set name unknown
        catch { set name $::de1_num_state($::de1(state)) }
        if {$name in {Idle Sleep GoingToSleep}} { return "" }
        return $name
    }

    variable mach_apply_id ""
    variable mach_note_id ""

    # Relabel the To-machine button with the outcome; a one-shot refresh
    # puts the state label back (the refresh always rewrites it).
    proc _machine_note {txt} {
        variable mach_note_id
        variable L
        catch {
            set px [expr {int($L(det_mach_w) * $L(v2px))} ]
            dui item config DrinkMenu_detail det_mach -label \
                [_fit_text $txt $L(font_button) [expr {$px - 20}]]
        }
        catch { after cancel $mach_note_id }
        set mach_note_id [after 2200 ::plugins::DrinkMenu::_refresh_current]
    }

    # THE tap. Applies profile and/or water from the drink AS DISPLAYED
    # (the sized drink), reports on the button, and persists + sends via
    # the app's own procs, debounced exactly as Lumen does.
    proc to_machine_tap {} {
        variable detail_id
        variable detail_size
        variable mach_apply_id
        set d0 [get_drink $detail_id]
        if {$d0 eq ""} { return }
        set d [sized_drink $d0 $detail_size]
        set busy [_machine_busy]
        if {$busy ne ""} {
            _machine_note "[translate "Machine busy"]"
            return
        }
        set done {}
        lassign [drink_profile $d] fn title
        if {$fn ne ""} {
            set r ""
            if {[catch { set r [::select_profile $fn] } err]} {
                catch { msg -ERROR "DrinkMenu: select_profile '$fn' failed: $err" }
                _machine_note [translate "Profile failed"]
                return
            }
            if {$r eq "-1"} {
                _machine_note [translate "Profile file missing"]
                return
            }
            lappend done [translate "Profile set"]
        }
        set w [water_target [drink_hot_water $d]]
        if {$w > 0} {
            if {[catch { set ::settings(water_volume) $w } err]} {
                catch { msg -ERROR "DrinkMenu: could not set water volume: $err" }
            } else {
                lappend done "[translate "Water"] $w ml"
            }
        }
        if {[llength $done] == 0} { return }
        catch { after cancel $mach_apply_id }
        set mach_apply_id [after 1000 {
            if {[catch {
                save_settings
                save_settings_to_de1
            } err]} {
                catch { msg -ERROR "DrinkMenu: could not send the machine settings: $err" }
            }
        }]
        catch { msg -NOTICE "DrinkMenu: to machine: [join $done {; }]" }
        _machine_note [join $done ", "]
    }

    # Label column layout (pure). mids: canvas y of every layer's
    # mid-height, bottom layer first (so y decreases along the list).
    # Labels are pushed apart to `pitch` from the bottom up, then the
    # whole column shifts down if it overruns `top` (+ half a pitch);
    # if that pushes past `bottom` the column shifts back up. Returns the
    # label y list in the same order.
    proc label_layout {mids pitch top bottom} {
        set ys {}
        set prev ""
        foreach m $mids {
            set y [expr {double($m)}]
            if {$prev ne "" && $y > $prev - $pitch} { set y [expr {$prev - $pitch}] }
            lappend ys $y
            set prev $y
        }
        if {[llength $ys] == 0} { return {} }
        set half [expr {$pitch / 2.0}]
        set miny [lindex $ys end]
        set maxy [lindex $ys 0]
        foreach y $ys { if {$y < $miny} { set miny $y }; if {$y > $maxy} { set maxy $y } }
        set shift 0.0
        if {$miny - $half < $top} { set shift [expr {$top + $half - $miny}] }
        if {$maxy + $shift + $half > $bottom} { set shift [expr {$bottom - $half - $maxy}] }
        if {$shift != 0.0} {
            set out {}
            foreach y $ys { lappend out [expr {$y + $shift}] }
            set ys $out
        }
        return $ys
    }

    # Chip flow layout (pure): widths in virtual units, wrapping when the
    # next chip would exceed inner_w. Returns {x y} offsets per chip
    # relative to the card's inner origin.
    proc chip_layout {widths inner_w chip_h gap} {
        set pos {}
        set x 0
        set row 0
        foreach w $widths {
            if {$x > 0 && $x + $w > $inner_w} {
                set x 0
                incr row
            }
            lappend pos [list $x [expr {$row * ($chip_h + $gap)}]]
            set x [expr {$x + $w + $gap}]
        }
        return $pos
    }

    # How many rows a chip_layout result occupies.
    proc chip_rows {pos chip_h gap} {
        set rows 0
        foreach p $pos {
            set r [expr {int([lindex $p 1] / ($chip_h + $gap)) + 1}]
            if {$r > $rows} { set rows $r }
        }
        return $rows
    }

    # Pass 14: the ingredients card is now a FIXED two-row card (the
    # Method card takes the height it used to waste), so the chips have
    # to fit `max_rows` rows. Every preset does -- the widest preset is
    # four layers, which wraps onto two rows -- but a custom drink may
    # carry six layers with long ingredient names and would need a third
    # row. When that happens (and only then) the chip NAMES are
    # ellipsised through _fit_text to an equal share of the row width,
    # so a pathological custom drink shortens its own chips instead of
    # spilling over the Method card. Pure apart from font measurement.
    #
    # chips: a list of {name amount color}. Returns {chips pos}, where
    # each returned chip is {name amount color width} and pos is the
    # matching chip_layout result.
    proc chip_fit {chips inner_w chip_h gap max_rows} {
        variable L
        set out {}
        set widths {}
        foreach c $chips {
            lassign $c nm amt color
            set w [_chip_width $nm $amt]
            lappend out [list $nm $amt $color $w]
            lappend widths $w
        }
        set pos [chip_layout $widths $inner_w $chip_h $gap]
        if {[llength $chips] == 0 || [chip_rows $pos $chip_h $gap] <= $max_rows} {
            return [list $out $pos]
        }
        set per [expr {int(ceil(double([llength $chips]) / $max_rows))}]
        if {$per < 1} { set per 1 }
        # One gap of slack per chip absorbs the ceil() in _chip_width.
        set capw [expr {int(double($inner_w - ($per - 1) * $gap) / $per) - $gap}]
        set out {}
        set widths {}
        foreach c $chips {
            lassign $c nm amt color
            set w [_chip_width $nm $amt]
            if {$w > $capw} {
                set nmw [expr {int([_text_w $L(font_body) $nm] - ($w - $capw) * $L(v2px))}]
                if {$nmw < 1} { set nmw 1 }
                set nm [_fit_text $nm $L(font_body) $nmw]
                set w [_chip_width $nm $amt]
            }
            lappend out [list $nm $amt $color $w]
            lappend widths $w
        }
        return [list $out [chip_layout $widths $inner_w $chip_h $gap]]
    }

    # ------------------------------------------------------------------
    #  Editor pure ops (on a working drink dict; no dui, no writes)
    # ------------------------------------------------------------------

    # Default amount when an ingredient is added from the palette.
    proc default_ml {ing} {
        # Pass 33: a custom layer starts small (10) -- syrups, sugars and
        # powders are the common case, and + grows it fast enough.
        if {[regexp {^c[0-9]+$} $ing]} { return 10 }
        switch -- $ing {
            ice { return 60 }
            sugar { return 5 }
            milk_foam - cold_foam { return 20 }
        }
        return 30
    }

    # Step size in ml for the +/- buttons: 5 ml, or 0.25 fl oz rounded
    # to the nearest whole ml (7.39 -> 7).
    proc step_ml {{unit ""}} {
        variable ui_unit
        if {$unit eq ""} { set unit $ui_unit }
        if {$unit eq "oz"} { return [expr {int(round(0.25 * 29.5735))}] }
        return 5
    }

    proc _capacity_of {drink} {
        variable vessels
        set cap 0
        catch { set cap [dict get $vessels [dict get $drink vessel] capacity] }
        return $cap
    }

    # Appends a layer ON TOP with its default amount, clamped to the
    # remaining capacity. Returns {drink msg}; msg non-empty (and the
    # drink unchanged) when nothing fits or the layer limit is reached.
    proc edit_add_layer {drink ing} {
        set layers [dict get $drink layers]
        if {[llength $layers] / 2 >= 6} { return [list $drink [translate "Too many layers (max 6)"]] }
        set room [expr {[_capacity_of $drink] - [drink_total $drink]}]
        if {$room < 5} { return [list $drink [translate "No room in this vessel"]] }
        set ml [expr {min([default_ml $ing], $room)}]
        lappend layers $ing $ml
        dict set drink layers $layers
        return [list $drink ""]
    }

    # +/- one step on layer index i (0 = bottom), bounded 5 ml .. capacity
    # minus the other layers. Returns the drink (unchanged at a bound).
    proc edit_step {drink i dir {unit ""}} {
        set layers [dict get $drink layers]
        set n [expr {[llength $layers] / 2}]
        if {$i < 0 || $i >= $n} { return $drink }
        set ml [lindex $layers [expr {2 * $i + 1}]]
        set others [expr {[drink_total $drink] - $ml}]
        set max [expr {[_capacity_of $drink] - $others}]
        set new [expr {$ml + $dir * [step_ml $unit]}]
        if {$new < 5} { set new 5 }
        if {$new > $max} { set new $max }
        if {$new < 5} { return $drink }
        lset layers [expr {2 * $i + 1}] $new
        dict set drink layers $layers
        return $drink
    }

    proc edit_remove {drink i} {
        set layers [dict get $drink layers]
        set n [expr {[llength $layers] / 2}]
        if {$i < 0 || $i >= $n} { return $drink }
        dict set drink layers [lreplace $layers [expr {2 * $i}] [expr {2 * $i + 1}]]
        return $drink
    }

    # Pass 35: swap layer i (0 = bottom of the glass) with its neighbour.
    # dir +1 moves it UP the glass (towards the end of the list), -1
    # down. A move past either end returns the drink unchanged. Pure;
    # ingredient AND amount travel together, and the defs dict is
    # untouched (ids keep meaning whatever they meant).
    proc edit_move {drink i dir} {
        set layers [dict get $drink layers]
        set n [expr {[llength $layers] / 2}]
        set j [expr {$i + $dir}]
        if {$i < 0 || $i >= $n || $j < 0 || $j >= $n || $dir == 0} { return $drink }
        set a [lrange $layers [expr {2 * $i}] [expr {2 * $i + 1}]]
        set b [lrange $layers [expr {2 * $j}] [expr {2 * $j + 1}]]
        set layers [lreplace $layers [expr {2 * $i}] [expr {2 * $i + 1}] {*}$b]
        set layers [lreplace $layers [expr {2 * $j}] [expr {2 * $j + 1}] {*}$a]
        dict set drink layers $layers
        return $drink
    }

    proc edit_set_vessel {drink vessel} {
        variable vessels
        if {![dict exists $vessels $vessel]} { return $drink }
        dict set drink vessel $vessel
        return $drink
    }

    # Status line for the preview: "" when valid, else the message.
    proc edit_status {drink} {
        lassign [validate_drink $drink] ok msg
        return [expr {$ok ? "" : $msg}]
    }

    # New custom id from the clock, suffixed on collision.
    proc new_custom_id {existing {now ""}} {
        if {$now eq ""} { set now [clock seconds] }
        set id "custom_$now"
        set n 2
        while {$id in $existing} {
            set id "custom_${now}_$n"
            incr n
        }
        return $id
    }

    # The vessel a brand-new draft starts in: the cappuccino cup, or the
    # first vessel the presets define if that id is ever renamed.
    proc default_vessel {} {
        variable vessels
        if {[dict exists $vessels cup]} { return cup }
        set first [lindex [dict keys $vessels] 0]
        if {$first eq ""} { return cup }
        return $first
    }

    # A fresh, never-saved custom draft for "+ New drink" (Pass 13):
    # id custom_<epoch>, the default vessel, no layers, no garnish.
    # Pure -- no dui, no settings, no write. The draft is invalid until
    # the user adds a coffee layer (validate_drink: "Add at least one
    # layer", then "Needs an espresso layer"), so the editor keeps Save
    # hidden until then. It reaches settings only through the existing
    # confirmed custom_save path.
    proc new_draft {{existing ""} {now ""}} {
        return [dict create id [new_custom_id $existing $now] \
            name [translate "New drink"] vessel [default_vessel] layers {} \
            garnish {} group custom source custom]
    }

    # Prev/next ids of `id` inside an ordered id list ("" at the ends or
    # when id is absent).
    proc detail_neighbors {id ids} {
        set i [lsearch -exact $ids $id]
        if {$i < 0} { return [list "" ""] }
        set prev [expr {$i > 0 ? [lindex $ids $i-1] : ""}]
        set next [expr {$i < [llength $ids] - 1 ? [lindex $ids $i+1] : ""}]
        return [list $prev $next]
    }

    # ------------------------------------------------------------------
    #  Color helpers
    # ------------------------------------------------------------------

    # Flat blend of two #rrggbb colors (frac of c2 over c1). Tk canvas
    # has no alpha, so tints are precomputed solid colors
    # (MaintenanceTracker _blend, copied verbatim).
    proc _blend {c1 c2 frac} {
        set out "#"
        foreach i {1 3 5} {
            scan [string range $c1 $i [expr {$i+1}]] %x a
            scan [string range $c2 $i [expr {$i+1}]] %x b
            append out [format %02x [expr {int(round($a + ($b - $a) * $frac))}]]
        }
        return $out
    }

    # WCAG 2.x relative luminance of an #rrggbb color, and the contrast
    # ratio of two of them. Pass 28: the palette needs to COMPUTE a text
    # colour that clears 4.5:1 rather than have one picked by eye, so the
    # same formula tools/geometry_check.tcl asserts with lives here too.
    proc _rel_lum {hex} {
        set out {}
        foreach i {1 3 5} {
            scan [string range $hex $i [expr {$i+1}]] %x v
            set c [expr {$v / 255.0}]
            lappend out [expr {$c <= 0.03928 ? $c / 12.92 : pow(($c + 0.055) / 1.055, 2.4)}]
        }
        lassign $out r g b
        return [expr {0.2126 * $r + 0.7152 * $g + 0.0722 * $b}]
    }

    proc _contrast {c1 c2} {
        set l1 [_rel_lum $c1]
        set l2 [_rel_lum $c2]
        return [expr {(max($l1, $l2) + 0.05) / (min($l1, $l2) + 0.05)}]
    }

    # FA6 glyph from the app's own symbol table; "" when unknown so the
    # caller falls back to text. Never a literal non-ASCII character.
    proc _glyph_for {name} {
        set glyph ""
        catch {
            if {[dui symbol exists $name]} { set glyph [dui symbol get $name] }
        }
        return $glyph
    }

    # Palette. Pass 20 (v0.11.0), owner decision: these pages wear the
    # design mock's warm brown look under EVERY skin theme, so this proc
    # no longer reads a single Lumen token -- ::lumen::C may exist and is
    # ignored. mock_palette is the one source; everything else is derived
    # from it here, so the page reads as one system and _retheme (which
    # re-applies L() on every page show) keeps working unchanged. Safe to
    # call any time (tablet-verified at show time in v0.1.0).
    proc _apply_palette {} {
        variable L
        variable mock_palette
        variable mock_crema_ink
        variable mock_glass
        variable mock_glass_edge
        variable mock_glass_top
        variable mock_glass_bot
        variable mock_card_hi
        variable mock_well
        variable mock_well_brd
        variable mock_glass_kinds
        variable mock_glass_steps
        variable mock_shadow_alpha
        variable mock_shadow_row
        foreach {k v} $mock_palette { set L(c_$k) $v }
        set L(palette_src) mock
        # The pages were "always dark" in practice and are now literally
        # so: no light branch, no ::lumen::theme_mode read. The token is
        # kept (always 0) so nothing that reads L(theme_light) breaks.
        set L(theme_light) 0
        # The flat fallback fill: bg1, the middle stop of the gradient the
        # shipped PNG paints (_page_bg falls back to this when no PNG
        # matches the physical screen).
        set L(page_bg)      $L(c_bg)
        set L(cup_interior) [_blend $L(c_bg) $L(c_ink) 0.08]
        set L(stem_fill)    [_blend $L(c_bg) $L(c_ink) 0.35]
        # Glass, no alpha: Tk canvas has no compositing, so each of the
        # mock's translucent whites is precomputed as the solid colour it
        # would resolve to over the surface it actually sits on -- the
        # body and the edge over the page (bg1), the inner top highlight
        # over the body it is drawn inside. That ordering is what keeps
        # the highlight (.16 over an already .075 surface = .223 over the
        # page, matching the mock's own inset 0 1px 0 rgba(255,255,255,
        # .22)) brighter than the .17 edge instead of a shade darker.
        set L(card_fill)    [_blend $L(c_bg) "#ffffff" $mock_glass]
        set L(card_edge)    [_blend $L(c_bg) "#ffffff" $mock_glass_edge]
        set L(c_glass)      $L(card_fill)
        set L(c_glass_2)    $L(card_fill)
        set L(c_glass_brd)  $L(card_edge)
        # Pass 23: the two ends of the card gradient glass_photo paints, and
        # the highlight row at its very top. card_fill (.075) stays the FLAT
        # fallback -- the ramp's own middle to within .0075 -- and the colour
        # every derived tint below is still computed from, so a card without
        # a photo is exactly the card v0.12.1 shipped.
        set L(glass_top)    [_blend $L(c_bg) "#ffffff" $mock_glass_top]
        set L(glass_bot)    [_blend $L(c_bg) "#ffffff" $mock_glass_bot]
        # c_spec (the mock's .26 top highlight over glass_top) and
        # card_shade (half way from the card back to the page) were the
        # <tag>_spec / <tag>_shade lines glass_card drew until Pass 41.
        # No item uses them now; the tokens stay defined because the
        # headless WARMLOOK net lists them and nothing else costs anything.
        set L(c_spec)       [_blend $L(glass_top) "#ffffff" $mock_card_hi]
        set L(card_shade)   [_blend $L(card_fill) $L(c_bg) 0.5]
        # Chip / badge well: black at 38% over the card (mock .tile .ml),
        # with the mock's own gold hairline at 35% over that well.
        set L(chip_bg)      [_blend $L(card_fill) "#000000" $mock_well]
        set L(chip_brd)     [_blend $L(chip_bg) $L(c_crema) $mock_well_brd]
        set L(leader)       [_blend $L(c_bg) $L(c_ink) 0.45]
        # Pass 19 (v0.10.5): the ghosted part of the detail hero's handle
        # ring -- the arc that runs under the layer labels. The ring
        # itself is c_ink at full strength; 0.35 of the way from the card
        # body towards ink reads as the same ring, dimmed. Used only by
        # hero_cup_handle_dim, which is registered for retheme exactly as
        # hero_cup_handle is.
        set L(ring_dim)     [_blend $L(card_fill) $L(c_ink) 0.35]
        # Pass 30: the cup shadow. The mock's rgba(0, 0, 0, .35) is an
        # alpha, and a Tk canvas has none, so the shadow is the SURFACE it
        # lies on taken 0.35 of the way to black. Every cup sits on a glass
        # card, so the surface is that card's own photo: one colour per
        # mock family, read off the family ramp at the shadow's row
        # (mock_shadow_row). cup_shadow itself is the card-fill variant --
        # the flat fallback for a card drawn without a photo, and the role
        # a cup drawn on no card at all would take.
        set L(cup_shadow) [_blend $L(card_fill) "#000000" $mock_shadow_alpha]
        set _si [expr {int(round((1.0 - $mock_shadow_row) * $mock_glass_steps))}]
        foreach _sk [dict keys $mock_glass_kinds] {
            set L(cup_shadow_$_sk) [_blend [lindex [_glass_ramp $_sk] $_si] \
                "#000000" $mock_shadow_alpha]
        }
        unset -nocomplain _si _sk
        # The mock's --gold-ink: the one text colour that goes on a gold
        # fill (selected pill, primary button).
        set L(crema_ink)    $mock_crema_ink
        # Pass 10 item 6 added a darker crema for Lumen's LIGHT glass,
        # where gold-as-text measured ~2.0:1. There is no light surface
        # left, so crema_text is simply the mock's gold; it clears 4.5:1
        # on the badge well and on the card body (asserted in WARMLOOK).
        set L(crema_text)   $L(c_crema)
        # Pass 28 (touch-UX audit item 3): c_ink_3 is a MARK colour. It
        # measures 3.8:1 on the card body and 3.3:1 on the lightest row of
        # the card's own gradient, so it is fine for the tile star's
        # outline (a non-text mark, 3:1) and NOT fine for the Method
        # card's step numbers, which are text and owe 4.5:1. ink_3_text is
        # the smallest blend of c_ink_3 towards c_ink -- searched here in
        # 1/100 steps, never eyeballed -- that clears 4.5:1 on BOTH card
        # surfaces: the flat body (card_fill) the pass names and glass_top,
        # the lightest row a card can actually show. Nothing else in the
        # palette moves, so the star outline keeps c_ink_3.
        set L(ink_3_text) $L(c_ink)
        for {set _f 0} {$_f <= 100} {incr _f} {
            set _c [_blend $L(c_ink_3) $L(c_ink) [expr {$_f / 100.0}]]
            if {[_contrast $_c $L(card_fill)] >= 4.5 && [_contrast $_c $L(glass_top)] >= 4.5} {
                set L(ink_3_text) $_c
                break
            }
        }
        unset -nocomplain _f _c
        set L(btn_fill)     $L(c_glass_2)
        set L(btn_disabled_fill) [_blend $L(c_glass_2) $L(c_bg) 0.5]
        set L(btn_label)    $L(c_ink)
        # Segmented controls / tab pills.
        set L(pill_on_fill)  $L(c_crema)
        set L(pill_on_text)  $L(crema_ink)
        set L(pill_off_fill) $L(c_glass)
        set L(pill_off_text) $L(c_ink_2)
        # Pass 23 item 7 / Pass 41: a GHOST button wears the faint edge
        # hairline (mock_glass_edge of white over its own fill) and nothing
        # else. A gold button and a selected pill are rimless: their edge
        # token is their own fill, so dui's round_outline painter and
        # _style_pill draw nothing visible around the gold. The bar
        # buttons' inset top highlight (btn_hi / btn_primary_hi) is gone.
        set L(btn_edge)         [_blend $L(btn_fill) "#ffffff" $mock_glass_edge]
        set L(btn_primary_edge) $L(pill_on_fill)
        set L(pill_on_edge)     $L(pill_on_fill)
        set L(pill_off_edge)    $L(card_edge)
        # Pass 28 (touch-UX audit item 1): pressed feedback. dui's dbutton
        # flashes <tag>-btn to the first colour of -pressfill and puts the
        # button's own fill back after the listed ms (core dui.tcl:9179 /
        # 9229, fed from the `pressfill` ASPECT at dui.tcl:10288, so one
        # aspect covers every button on that style). -pressoutline is
        # documented at dui.tcl:9875 but never read anywhere in the core,
        # so only -pressfill is used here, and -label_pressfill is left
        # unset: the label keeps its colour through the flash.
        #   ghost         -> white .12 over the ghost fill (a lighter glass)
        #   primary       -> the gold, 15% of the way to gold-ink
        #
        # THE PRESS RULE (pass 31, from the tablet). A pressfill belongs
        # ONLY on a button whose <tag>-btn fill this plugin never touches
        # and which actually paints that rect. The core's restore is
        # `after $ms $can itemconfigure $tag -fill $fill` (dui.tcl:9225)
        # with $fill captured at CREATION, so it runs AFTER the tap's own
        # command has repainted, and it breaks two ways:
        #   - State-styled button (dm_pill): round_outline puts the
        #     aspect's fill into press_args (dui.tcl:10120), so the restore
        #     puts the OFF face back over the gold _style_pill just gave a
        #     selected pill. The outline and label keep the selected
        #     colours -- nothing restores those -- so the pill ends up with
        #     a dark label on a dark body until the page is reloaded.
        #   - Invisible tap rect (an unstyled dbutton over drawn art): its
        #     rect is created with -fill {} (dui.tcl:10186) and `after`
        #     CONCATENATES its arguments, so the queued restore loses the
        #     empty word and degrades to `itemconfigure $tag -fill`, a
        #     query. The flash colour is then permanent: an opaque rect
        #     with square corners over the capsule or tile it covers.
        # Hence: dm_btn and dm_btn_primary carry a pressfill (static
        # fills, correct restore); every invisible tap rect carries none.
        # The pills and capsule halves get their own flash instead, painted
        # by _flash_pill / _flash_seg and restored FROM STATE (pass 32), so
        # it cannot stick the way the core's could.
        set L(btn_press)         [_blend $L(btn_fill) "#ffffff" $mock_glass_top]
        set L(btn_primary_press) [_blend $L(pill_on_fill) $L(crema_ink) 0.15]
        # Pass 48: the DANGER tone, worn by the editor's Delete alone: a
        # muted red over the ghost fill, rimless, ink label, a touch
        # lighter when pressed.
        set L(btn_danger_fill)  [_blend $L(btn_fill) "#c0392b" 0.45]
        set L(btn_danger_edge)  $L(btn_danger_fill)
        set L(btn_danger_press) [_blend $L(btn_danger_fill) "#ffffff" 0.12]
        # Pass 45: the segmented toggles (ml/oz, 1/2 shots, ml/g) are
        # display preferences, not filters or actions, so their selected
        # half wears a SECONDARY tone -- the mock's ink_2 with gold-ink
        # text -- and the gold means exactly two things on a page: the
        # active filter and the one primary action.
        set L(seg_on_fill)  $L(c_ink_2)
        set L(seg_on_text)  $L(crema_ink)
        set L(seg_press)    [_blend $L(seg_on_fill) $L(crema_ink) 0.15]
        set L(press_ms)          120
        # Every color token may have moved, and a page show re-applies
        # live states from the initial-state tags: the "already written"
        # caches must not survive either (Pass 9).
        invalidate_visibility
    }

    # Physical text width for one of the plugin's fonts, with a
    # The ONE place that calls `font measure`, so the call count of a
    # refresh is countable (Pass 9). Returns "" when Tk fonts are not
    # available (headless runs).
    proc _fmeasure {font text} {
        variable debug_timing
        if {$debug_timing} { t_count font_measure }
        set w ""
        catch { set w [font measure $font $text] }
        return $w
    }

    proc _text_w {font text} {
        variable L
        set w [_fmeasure $font $text]
        if {$w eq ""} {
            set px 19
            catch { set px $L(font_px_$font) }
            set w [expr {int(ceil([string length $text] * $px * 0.58))}]
        }
        return $w
    }

    # Ellipsis truncation by measurement (GrindAdvisor _fit_text, copied
    # verbatim apart from taking a Tk font name). Tk -width wraps instead
    # of truncating, which collides with the next baseline. maxw is in
    # PHYSICAL pixels, like the font.
    proc _fit_text {text font maxw} {
        variable fit_cache
        set _key "$font|$maxw|$text"
        if {[info exists fit_cache($_key)]} { return $fit_cache($_key) }
        set text [_fit_text_calc $text $font $maxw]
        set fit_cache($_key) $text
        return $text
    }

    proc _fit_text_calc {text font maxw} {
        set w [_fmeasure $font $text]
        # font measure unavailable (headless): leave the text as-is.
        if {$w eq ""} { return $text }
        if {$w > $maxw} {
            while {[string length $text] > 1} {
                set w [_fmeasure $font "$text\u2026"]
                if {$w eq "" || $w <= $maxw} { break }
                set text [string range $text 0 end-1]
            }
            set text "$text\u2026"
        }
        return $text
    }

    # Pass 15 item 2: a tile name is only ellipsised as a last resort.
    # The mock's tile names always fit on one line; v0.10.0 truncated
    # every "<preset> copy" custom ("Espresso romano co...", see
    # design/v080_custom.png) because the 22 px primary font is the only
    # one it ever tried. Try the primary font first, then the caption
    # font (16 px, the design system's floor), and only then truncate at
    # the caption font. Returns {text font} -- the caller writes both.
    # Cached exactly like _fit_text: the key is the name, the width and
    # the "tile" font pair, and the cache is dropped by _init_layout
    # (widths changed) and invalidate_cache (a custom drink was renamed).
    proc fit_tile_name {text maxw} {
        variable fit_cache
        set _key "tile|$maxw|$text"
        if {[info exists fit_cache($_key)]} { return $fit_cache($_key) }
        set out [_fit_tile_name_calc $text $maxw]
        set fit_cache($_key) $out
        return $out
    }

    # Pass 48: the detail page's layer labels fit the same way the tile
    # names do -- body font, then caption, then an ellipsis -- instead of
    # truncating at the body font ("Salted carmel ice cr..."). Cached
    # under its own key family.
    proc fit_label_name {text maxw} {
        variable fit_cache
        set _key "lbl|$maxw|$text"
        if {[info exists fit_cache($_key)]} { return $fit_cache($_key) }
        set out [_fit_label_name_calc $text $maxw]
        set fit_cache($_key) $out
        return $out
    }

    proc _fit_label_name_calc {text maxw} {
        variable L
        set w [_fmeasure $L(font_body) $text]
        if {$w eq "" || $w <= $maxw} { return [list $text $L(font_body)] }
        set w [_fmeasure $L(font_caption) $text]
        if {$w ne "" && $w <= $maxw} { return [list $text $L(font_caption)] }
        return [list [_fit_text_calc $text $L(font_caption) $maxw] $L(font_caption)]
    }

    proc _fit_tile_name_calc {text maxw} {
        variable L
        set w [_fmeasure $L(font_primary) $text]
        # font measure unavailable (headless): keep the primary font and
        # the text as-is, the same way _fit_text_calc gives up.
        if {$w eq "" || $w <= $maxw} { return [list $text $L(font_primary)] }
        set w [_fmeasure $L(font_caption) $text]
        if {$w ne "" && $w <= $maxw} { return [list $text $L(font_caption)] }
        return [list [_fit_text_calc $text $L(font_caption) $maxw] $L(font_caption)]
    }

    # Pass 10 item 3: wrap the ratio-names line onto at most two caption
    # lines instead of truncating (four-ingredient drinks like Borgia
    # overran a single line). Greedily packs comma-separated ingredient
    # names onto line 1 by measured width (_text_w, same physical-px
    # convention as _fit_text); everything left over goes on line 2,
    # ellipsis-truncated with _fit_text_calc only if it still overflows.
    # Returns {line1 line2}; line2 is "" when everything fit on one line.
    proc _wrap_names_2line {names font maxw} {
        if {$names eq ""} { return [list "" ""] }
        set parts {}
        foreach p [split $names ","] { lappend parts [string trim $p] }
        set n [llength $parts]
        set line1 ""
        set i 0
        for {} {$i < $n} {incr i} {
            set cand [expr {$line1 eq "" ? [lindex $parts $i] : "$line1, [lindex $parts $i]"}]
            if {$line1 ne "" && [_text_w $font $cand] > $maxw} { break }
            set line1 $cand
        }
        if {$i >= $n} {
            # Everything fit by the greedy-width check; _fit_text_calc is
            # a no-op unless a single lone name is itself wider than
            # maxw, in which case it still gets the usual ellipsis
            # safety net (same guarantee _fit_text always gave).
            return [list [_fit_text_calc $line1 $font $maxw] ""]
        }
        if {$line1 eq ""} {
            # Even the first name alone overflows: truncate it standalone
            # so line 1 is never left empty.
            set line1 [_fit_text_calc [lindex $parts $i] $font $maxw]
            incr i
        }
        set rest [join [lrange $parts $i end] ", "]
        set line2 [_fit_text_calc $rest $font $maxw]
        return [list $line1 $line2]
    }

    # ------------------------------------------------------------------
    #  Layout tokens (ShotHistoryEditor _init_layout pattern). Every
    #  coordinate on every page comes from L; nothing below hardcodes one.
    # ------------------------------------------------------------------

    proc _init_layout {} {
        variable L
        variable tabs
        variable page_size
        variable geom_cache
        variable render_cache
        variable fit_cache
        array unset L
        array set L {}
        # Every cached geometry, physical polygon and fitted string is
        # keyed by tokens that are about to change (Pass 9).
        array unset geom_cache
        array unset render_cache
        array unset fit_cache

        # Virtual base resolution from the core, 2560x1600 fallback.
        set sw 2560
        set sh 1600
        catch { if {[info exists ::dui::_base_screen_width]}  { set sw [expr {int($::dui::_base_screen_width)}] } }
        catch { if {[info exists ::dui::_base_screen_height]} { set sh [expr {int($::dui::_base_screen_height)}] } }
        if {$sw <= 1} { set sw 2560 }
        if {$sh <= 1} { set sh 1600 }
        set scale [expr {double($sh) / 800.0}]

        # Real physical screen, used ONLY for font pixel sizes and text
        # measurement.
        set psw 1340
        set psh 800
        catch { set psw [winfo screenwidth .] }
        catch { set psh [winfo screenheight .] }
        if {$psw <= 1} { set psw 1340 }
        if {$psh <= 1} { set psh 800 }
        set font_scale [expr {double($psh) / 800.0}]

        set L(screen_w) $sw
        set L(screen_h) $sh
        # The PHYSICAL screen, kept as its own pair of tokens: it names
        # the per-resolution background PNG folder (Pass 20), exactly as
        # Lumen names skins/Lumen/<W>x<H>/. Never used for layout.
        set L(phys_w) $psw
        set L(phys_h) $psh
        set L(scale) $scale
        set L(font_scale) $font_scale
        # virtual -> physical (text measurement) and physical -> virtual
        # (minimum visible sizes given in physical px).
        set L(v2px) [expr {double($psw) / $sw}]
        set L(px2v) [expr {double($sw) / $psw}]

        # Spacing tokens (reference px at 1340x800, scaled).
        foreach {tok ref} {xs 6 sm 10 md 16 lg 24 xl 32 xxl 48} {
            set L($tok) [expr {int(round($ref * $scale))}]
        }

        set L(margin) [expr {int(max($sw * 0.036, 32))}]
        set L(left_x) $L(margin)
        set L(right_x) [expr {$sw - $L(margin)}]
        set L(content_w) [expr {$L(right_x) - $L(left_x)}]
        set L(center_x) [expr {($L(left_x) + $L(right_x)) / 2}]

        # Buttons.
        set L(btn_w_std) [expr {int(round(200 * $scale))}]
        set L(btn_h) [expr {int(max(60, round(60 * $scale)))}]
        # Pass 10 item 1: 12 read nearly square against Lumen's pill
        # look. Lumen's own general-purpose control corner is
        # radius_sm=16 (skins/Lumen/skin.tcl:293), used throughout Lumen
        # for segmented controls, date/time chips and glass buttons (e.g.
        # skin.tcl:3656/3669/3714/3747/3763/3779/3918/3975/4062/4088/
        # 4117/4123/4133) at the SAME 1340x800 design-px reference this
        # file's own spacing tokens already share with Lumen (xs/sm/md/
        # lg/xxl match exactly) -- so 16 is directly comparable to our
        # ref-px 12, not the DYE-theme-specific dbutton.radius 30 (a
        # different, plugin-embedding coordinate convention). Raised to
        # match; card_radius keeps the old 12-based value (already close
        # to Lumen's panel radius 26) so this pass only changes buttons.
        # Pass 23 item 7: btn_radius is now the radius the corner really
        # RENDERS, in virtual units (19 ref px), and it is fed DOUBLED to
        # every drawing layer -- exactly as pill_radius already was. Both
        # painters halve it: dui::item::rounded_rectangle (core dui.tcl:8460,
        # the "shape round"/"round_outline" painter) builds each corner from
        # an oval whose BOX side is the radius it is given, and a -smooth 1
        # polygon renders about half its control-point radius. Until v0.12.1
        # this token was the value HANDED to dui, so the drawn corner was 8
        # ref px, half of what the comment claimed.
        set L(btn_radius) [expr {int(round(19 * $scale))}]
        # Pass 12 item A3 / Pass 23 item 6: tab pills and the two-way
        # segments are full pills (mock: border-radius 999px), i.e. a VISUAL
        # corner radius of half the CONTROL height -- and that height is no
        # longer btn_h: the header row shrank to the mock's 34 CSS px (46
        # ref px) so the pills stop competing with the title.
        set L(pill_h) [expr {int(round(46 * $scale))}]
        set L(pill_radius) [expr {$L(pill_h) / 2}]

        # Page zones. Pass 23 item 5: the header no longer hugs the top
        # edge. The mock's header band runs 4%..15% of the screen height
        # with the cards from 18%, i.e. the title, the subtitle and the
        # control row sit vertically CENTRED between the top of the screen
        # and the top of the grid. That centre is derived from list_top
        # (= grid_y1) so the three pages can never drift apart.
        set L(list_top) [expr {int(round(168 * $scale))}]
        set L(bar_y0) [expr {int(round(716 * $scale))}]
        set L(bar_y1) [expr {int(round(776 * $scale))}]
        set L(content_bottom) [expr {$L(bar_y0) - $L(md)}]
        set L(hdr_band_y1) 0
        set L(hdr_band_y2) $L(list_top)
        set L(hdr_band_mid) [expr {($L(hdr_band_y1) + $L(hdr_band_y2)) / 2}]
        # Control row (pills / capsules), pill_h tall, centred on the band.
        set L(hdr_ctl_y0) [expr {$L(hdr_band_mid) - $L(pill_h) / 2}]
        set L(hdr_ctl_y1) [expr {$L(hdr_ctl_y0) + $L(pill_h)}]
        # The same centre for a header control that keeps the 60-ref touch
        # height of a bar button (the editor's keyboard Done).
        set L(hdr_btn_y0) [expr {$L(hdr_band_mid) - $L(btn_h) / 2}]
        set L(hdr_btn_y1) [expr {$L(hdr_btn_y0) + $L(btn_h)}]
        # Title + subtitle group, also centred on the band. Both are anchor
        # w, so a line's own centre is its y; the group runs from the title's
        # top to the subtitle's bottom. Text heights are ref px x scale: the
        # y mapping is virtual -> physical at sh/psh, so a 40 physical px
        # face is exactly 40 x scale virtual units tall.
        set L(hdr_title_h) [expr {int(round(40 * $scale))}]
        set L(hdr_sub_h) [expr {int(round(16 * $scale))}]
        set L(hdr_sub_dy) [expr {int(round(44 * $scale))}]
        set L(header_title_y) [expr {$L(hdr_band_mid) \
            - ($L(hdr_sub_dy) + $L(hdr_sub_h) / 2 - $L(hdr_title_h) / 2) / 2}]
        set L(header_subtitle_y) [expr {$L(header_title_y) + $L(hdr_sub_dy)}]

        # Header controls row (unit toggle + seven tab pills), right
        # aligned. v0.4.1: widths are budgeted in PHYSICAL px -- the ref-px
        # scale is height-based (2.0) but the screen maps virtual->physical
        # at 2560/1340, so a horizontal budget in ref px lands 4.7% wider on
        # the tablet (the v0.4.0 row overlapped the title). Since Pass 23 a
        # pill is only as wide as its own label needs (see the "Header
        # control row" block below, which runs after the fonts exist), so
        # only the gaps and the minimum are tokens here.
        # Pass 28 (touch-UX audit item 2): xs (12 virtual) left only 6.3
        # physical px between two neighbouring tab pills, under the 8 px
        # the guideline set asks between adjacent targets. sm (20 virtual)
        # is 10.5 px. The pill row is right-aligned, so the whole group
        # simply starts 48 units further left; the header has ~320 px of
        # clearance to the subtitle (HEADER), so nothing else moves.
        set L(pill_gap) $L(sm)
        # Pass 28: the header controls are pill_h (92 virtual = 46
        # physical px) tall, 2 px under the 48 px minimum, and growing the
        # capsule would change the owner-signed-off v1.0.0 header. dui's
        # own -tap_pad (core dui.tcl:9934, virtual units, {left top right
        # bottom}) grows the CLICKABLE rect only, so every pill and
        # capsule half taps as 100 virtual = 50 physical px tall while the
        # drawing is untouched. Vertical only: the horizontal gaps above
        # are already the target spacing.
        set L(hdr_tap_pad) [list 0 4 0 4]
        set L(pill_min_w) [expr {int(round(72 * $scale))}]
        set L(pill_pad_x) $L(md)
        # Pass 12 item A3: the two halves of a two-way segment are drawn
        # as ONE capsule, so they are adjacent -- the old xs gap between
        # them is gone. Kept as a named token (rather than dropped) so
        # every segment on both pages shares one definition and the
        # headless PILLS check can assert it.
        set L(seg_gap) 0
        set L(group_gap) $L(lg)
        set n_tabs [expr {[llength $tabs] / 2}]
        set L(n_tabs) $n_tabs

        # Cards. Both painters render about HALF the radius they are given
        # (see btn_radius above), so card and hero radii are fed doubled.
        # Pass 23 item 7 raises the drawn corner from 12 to the mock's 24
        # ref px on every card, and to 29 on the detail hero (mock .hero:
        # border-radius 22 CSS px = 29 ref px).
        set L(card_radius) [expr {2 * int(round(24 * $scale))}]
        # Pass 42: ONE card radius. The hero used to take the mock's 29;
        # with the corners finally drawn as true anti-aliased arcs the two
        # radii read as two component kits, so the hero joins the cards.
        set L(hero_radius) $L(card_radius)
        # Pass 42: the card photo's shadow margin and the shadow's downward
        # offset, in VIRTUAL units (rescaled to physical by glass_card).
        # 20 / 6 ref px: the mock's `0 6px 18px` blur needs ~14 px of
        # fall-off past the offset at the tablet's scale, and 20 is still
        # under the 25 px grid gap, so a tile's shadow margin never
        # reaches its neighbour's body (their margins may overlap).
        set L(shadow_m)  [expr {int(round(20 * $scale))}]
        set L(shadow_dy) [expr {int(round(6 * $scale))}]
        set L(card_pad_x) [expr {int(round(18 * $scale))}]
        set L(card_pad_y) [expr {int(round(14 * $scale))}]
        # Line widths in VIRTUAL units: canvas_item rescales -width, so
        # 2 -> 1 physical px, 4 -> 2 px.
        set L(line_w) 2
        set L(stroke_w) 4
        # Smallest visible ingredient layer: 3 physical px.
        set L(layer_min_h) [expr {int(round(3 * $L(px2v)))}]
        set L(layer_pool) 6

        # Grid: 4 x 3 tiles from list_top to content_bottom, gap lg.
        set L(grid_cols) 4
        set L(grid_rows) 3
        set L(grid_gap) $L(lg)
        set L(grid_y1) $L(list_top)
        set L(grid_y2) $L(content_bottom)
        set L(tile_w) [expr {int(($L(content_w) - ($L(grid_cols) - 1) * $L(grid_gap)) / $L(grid_cols))}]
        set L(tile_h) [expr {int(($L(grid_y2) - $L(grid_y1) - ($L(grid_rows) - 1) * $L(grid_gap)) / $L(grid_rows))}]
        set page_size [expr {$L(grid_cols) * $L(grid_rows)}]
        # Amount badge (Pass 23 item 2). The mock's `.tile .ml`: a FULL pill
        # (border-radius 999px, so radius = height/2, drawn as an exact
        # stadium by _capsule_points -- a -smooth 1 rounded rect can never
        # reach a half-height cap), bold gold on the black .38 well with the
        # gold .35 hairline, back in the tile's TOP-RIGHT corner with the
        # mock's 9/10 CSS px inset (12 ref px). 70 ref px of width is the
        # mock's own badge (11 ref px of padding either side of a 6-glyph
        # amount at the 16 px caption face); it is a fixed token rather than
        # a measured width so the tile geometry does not move between the
        # headless character estimate and the tablet's real metrics.
        set L(chip_w) [expr {int(round(70 * $scale))}]
        set L(chip_h) [expr {int(round(30 * $scale))}]
        set L(chip_radius) [expr {$L(chip_h) / 2}]
        set L(tile_badge_inset) [expr {int(round(12 * $scale))}]
        set L(tile_badge_x2) [expr {$L(tile_w) - $L(tile_badge_inset)}]
        set L(tile_badge_x1) [expr {$L(tile_badge_x2) - $L(chip_w)}]
        set L(tile_badge_y1) $L(tile_badge_inset)
        set L(tile_badge_y2) [expr {$L(tile_badge_y1) + $L(chip_h)}]
        # Name line box under the cup: 22 px primary at the file's usual
        # ~1.25 line-box convention (cf. det_label_pitch), in ref px.
        set L(tile_name_dy) $L(card_pad_y)
        set L(tile_name_h) [expr {int(round(28 * $scale))}]
        set L(tile_icon_w) [expr {int(round(28 * $scale))}]
        #
        # Pass 23 item 4 -- the favorite star, TOP-LEFT and small.
        #
        # The drawn star drops from a 23-unit outer radius to 14 (7 ref px),
        # centred in a box inset 10 ref px from the tile's top-left corner,
        # exactly where the mock puts `.tile .star` (top 8, left 11 CSS px).
        # Its TAP box is deliberately larger than the drawing -- it is a
        # finger target -- and reaches the tile's top and left edges, so the
        # tile's own tap area is the rest of the top band plus everything
        # below: three rects that tile the card exactly once (STARTAP).
        set L(star_r_out) [expr {int(round(7 * $scale))}]
        set L(star_r_in) [expr {int(round(0.42 * $L(star_r_out)))}]
        set L(tile_star_inset) [expr {int(round(10 * $scale))}]
        # Pass 28 (touch-UX audit item 2): the tap box was 96 x 84 virtual
        # = 50 x 42 physical px, under the 48 x 48 minimum on its short
        # side. It is now square at 48 ref px, so it measures 50 x 48
        # physical. The DRAWN star does not move (tile_star_cx/cy are
        # still inset + star_r_out from the tile's corner); only the
        # finger target grows downward, and the tile's own two tap rects
        # re-partition around it for free, because they are derived from
        # tile_star_x2 / tile_star_y2 (STARTAP). The box ends 96 units
        # down and 96 across, clear of the ml badge (starts at
        # tile_badge_x1) and of the cup square (starts at tile_cup_y1 in
        # the horizontal middle of the tile).
        set L(tile_star_w) [expr {int(round(48 * $scale))}]
        set L(tile_star_h) [expr {int(round(48 * $scale))}]
        set L(tile_star_x1) 0
        set L(tile_star_x2) $L(tile_star_w)
        set L(tile_star_y1) 0
        set L(tile_star_y2) $L(tile_star_h)
        # Pass 47 (owner, 2026-09-15): the star sits on the ml badge's
        # ROW -- its centre at the badge's centre line, its left edge
        # the badge's own inset from the card edge -- so the two corner
        # marks read as one band instead of the star hugging the corner.
        # The tap box does not move (the star stays well inside it: the
        # STARTAP / STARFILL slack rules still hold) and the pen slot
        # follows the centre line for free (tile_pen_dy below).
        set L(tile_star_cy) [expr {$L(tile_badge_y1) + $L(chip_h) / 2}]
        # Pass 48 (owner): the left spacing equals the top spacing, so the
        # star sits on the card corner's 45-degree diagonal (cx == cy).
        set L(tile_star_inset) [expr {$L(tile_star_cy) - $L(star_r_out)}]
        set L(tile_star_cx) [expr {$L(tile_star_inset) + $L(star_r_out)}]
        # Pen (custom drinks). Pass 45: a FIXED slot in the top-left
        # marker row, just right of the star box and centred on the star,
        # so the two markers ("favorite", "custom") read together and the
        # pen never floats under the badge into the cup's handle.
        set L(tile_pen_dx) [expr {$L(tile_star_x2) + $L(xs)}]
        set L(tile_pen_dy) [expr {$L(tile_star_cy) - $L(tile_icon_w) / 2}]
        #
        # Pass 23 item 1 -- cup zone, the mock's own box.
        #
        # `.tile svg { width:62%; height:64% }`, horizontally centred, sitting
        # above the name: the zone is that box (tile_zone_*). Inside it the
        # mock's `viewBox="0 0 100 100"` is SQUARE and its default
        # preserveAspectRatio is "meet", so the cup is really fitted into the
        # largest square the zone holds, centred -- which is what keeps a wide
        # cup and a tall glass reading as the same drink size in a grid, and
        # what keeps every fitted cup clear of the badge and the star
        # (v0.12.1 fitted into the whole 338 x 198 zone, so the large cup ran
        # to 0.571 of the tile width; the mock reads ~0.25). tile_cup_* IS
        # that square, and is what draw_cup receives.
        set L(tile_zone_w) [expr {int(round($L(tile_w) * 0.62))}]
        set L(tile_zone_h) [expr {int(round($L(tile_h) * 0.64))}]
        set L(tile_zone_x1) [expr {($L(tile_w) - $L(tile_zone_w)) / 2}]
        set L(tile_zone_x2) [expr {$L(tile_zone_x1) + $L(tile_zone_w)}]
        set L(tile_zone_y2) [expr {$L(tile_h) - $L(tile_name_dy) - $L(tile_name_h) - $L(xs)}]
        set L(tile_zone_y1) [expr {$L(tile_zone_y2) - $L(tile_zone_h)}]
        set L(tile_cup_sq) [expr {min($L(tile_zone_w), $L(tile_zone_h))}]
        set L(tile_cup_x1) [expr {($L(tile_w) - $L(tile_cup_sq)) / 2}]
        set L(tile_cup_x2) [expr {$L(tile_cup_x1) + $L(tile_cup_sq)}]
        set L(tile_cup_y2) $L(tile_zone_y2)
        set L(tile_cup_y1) [expr {$L(tile_cup_y2) - $L(tile_cup_sq)}]
        # Menu bottom bar (Pass 13). Left group: Done | + New drink |
        # Hidden (N). Right group: "< Prev" | "Next >". Every button is
        # btn_h tall and btn_w_std wide except "Hidden (N)", which keeps
        # the wider face its count needs (btn_w_wide, unchanged since
        # Pass 5). The whole row is budgeted in PHYSICAL px by
        # tools/geometry_check.tcl (NEWDRINK): the ref-px scale is
        # height-based (2.0) while the tablet maps virtual->physical at
        # 2560/1340, so a horizontal budget lands ~4.7% wider on screen.
        set L(btn_w_wide) [expr {int(round(240 * $scale))}]
        set L(bar_new_x1) [expr {$L(left_x) + $L(btn_w_std) + $L(sm)}]
        set L(bar_new_x2) [expr {$L(bar_new_x1) + $L(btn_w_std)}]
        set L(bar_hidden_x1) [expr {$L(bar_new_x2) + $L(sm)}]
        set L(bar_hidden_x2) [expr {$L(bar_hidden_x1) + $L(btn_w_wide)}]
        set L(bar_next_x1) [expr {$L(right_x) - $L(btn_w_std)}]
        set L(bar_prev_x1) [expr {$L(bar_next_x1) - $L(sm) - $L(btn_w_std)}]
        # Pass 48: the "1 / 4" page position, right-aligned lg before
        # Prev's slot, so it sits with the paging buttons.
        set L(bar_page_x) [expr {$L(bar_prev_x1) - $L(lg)}]
        # "< Prev" / "Next >": the chevron is a SECOND label in the icon
        # font (a canvas text item carries one font, so an icon glyph can
        # never sit inside a text label), placed as a fraction of the
        # button width. At btn_w_std the two items are ~60 virtual units
        # apart, far above the 4-unit minimum gap the page checks
        # enforce between text items.
        set L(bar_prev_sym_pos) {0.28 0.5}
        set L(bar_prev_lbl_pos) {0.58 0.5}
        set L(bar_next_lbl_pos) {0.42 0.5}
        set L(bar_next_sym_pos) {0.72 0.5}
        # Empty-state caption inside the grid zone.
        set L(empty_caption_y) [expr {$L(grid_y1) + $L(lg)}]

        # ---- Detail page sub-block ----
        # Bottom bar right group (v0.5.0): Favorite, Hide, Edit at std
        # width, then square chevron Prev/Next (btn_h x btn_h), lg gaps,
        # ending flush at right_x: 3*200 + 2*60 + 4*24 = 816 ref =
        # 854 physical px, starting near x=438 px; Back ends at 257 px.
        set L(btn_sq) $L(btn_h)
        set L(det_next_x1) [expr {$L(right_x) - $L(btn_sq)}]
        set L(det_prev_x1) [expr {$L(det_next_x1) - $L(lg) - $L(btn_sq)}]
        set L(det_edit_x1) [expr {$L(det_prev_x1) - $L(lg) - $L(btn_w_std)}]
        # Pass 48: Favorite is wider (260 ref) -- it carries the star
        # icon beside its label -- and Hide narrower (160 ref; "Unhide"
        # is its longest word), so the To-machine stretch gives up only
        # 20 ref and keeps room for its label.
        set L(det_hide_w)  [expr {int(round(160 * $scale))}]
        set L(det_fav_w)   [expr {int(round(260 * $scale))}]
        set L(det_hide_x1) [expr {$L(det_edit_x1) - $L(lg) - $L(det_hide_w)}]
        set L(det_fav_x1)  [expr {$L(det_hide_x1) - $L(lg) - $L(det_fav_w)}]
        # Pass 40: the "To machine" tie-in button fills the bottom bar's
        # one free stretch, between Back and Favorite, with sm clear of
        # each (the bar is where the page's actions live).
        set L(det_mach_x1) [expr {$L(left_x) + $L(btn_w_std) + $L(sm)}]
        set L(det_mach_x2) [expr {$L(det_fav_x1) - $L(sm)}]
        set L(det_mach_w)  [expr {$L(det_mach_x2) - $L(det_mach_x1)}]

        # Header: unit toggle then 1 shot|2 shots, right-aligned. Both
        # capsules are sized from their own labels in the "Header control
        # row" block below (Pass 23 item 6), which runs after the fonts.
        # Hero card: the left column of the content width, full list zone.
        #
        # Pass 16 (v0.10.2): 0.40 -> 0.47 of the content width, i.e. 950
        # -> 1116 virtual units at the reference geometry, and every one
        # of the 166 gained units goes to the cup box (the label column
        # below keeps its width, its md leader gap and its card padding).
        # 0.47 is the WIDEST hero this page allows, not a taste value:
        # what the right column gives up, the Method card's text width
        # takes back, and the widest preset step ("Fill a tall glass with
        # 80 ml of ice, add the milk.", 50 chars = 551 physical px at the
        # 0.58 em/char estimate `_text_w` falls back to) has to fit that
        # column untruncated. Every unit of hero costs the Method column
        # one unit, so the pass's own 0.52 (and its 0.50/0.48 fallbacks)
        # leave the widest step 494 / 519 / 544 px of a 551 px string --
        # it would be ellipsised on the tablet. 0.47 leaves 556 px, the
        # last stop above the string; the chips card (2 fixed rows) and
        # the ratio-names wrap are still green at the narrower column
        # (asserted headlessly: STEPS, METHOD, CHIPFIT, RATIOWRAP).
        set L(det_hero_frac) 0.47
        set L(det_hero_x1) $L(left_x)
        set L(det_hero_w) [expr {int($L(content_w) * $L(det_hero_frac))}]
        set L(det_hero_x2) [expr {$L(det_hero_x1) + $L(det_hero_w)}]
        set L(det_hero_y1) $L(list_top)
        set L(det_hero_y2) $L(content_bottom)
        # Cup box on the left of the card, garnish caption zone at the
        # bottom, label column on the right.
        #
        # Pass 15 item 1 / Pass 16 (hero cup size). The cup box and the
        # label column share ONE budget, the card interior, and the
        # column is the FIXED part: it has to hold the longest
        # ingredient name at the body font untruncated, and at the 0.58
        # em/char estimate `_text_w` falls back to, "Vanilla ice cream"
        # is 188 physical px = 359 virtual units. det_label_w is that
        # column, 181 ref px = 362 units = 189 px, one px of slack; Pass
        # 16 makes it the token (it was the fraction's remainder before)
        # so that a wider card can only feed the cup box. The cup box
        # takes everything else: the card width, less the card's own
        # card_pad_x on the left, less md of leader gap, less the label
        # column and its card padding. At the reference geometry:
        # 508 -> 674 units (v0.10.0 486), so the wide cups grow by a
        # third.
        #
        # Pass 24 (v0.13.1). That left inset used to be an xs sliver:
        # Pass 16 argued the mock's cup touches the card edge and only
        # TEXT needs card_pad_x. On the tablet the owner read it as the
        # cup crowding the card while the garnish caption below it kept a
        # comfortable margin (out/final/v13_detail_borgia.png), so the
        # rule is now simply "the cup keeps the same inset from every
        # card edge as the text does": card_pad_x on the left (and on the
        # right, since the fitted box can never pass det_cup_x2 + md +
        # label column + card_pad_x); Pass 25 finishes the rule by giving
        # the top and the bottom the same card_pad_x. The bowl budget pays
        # for the horizontal half:
        # 674 -> 650 units, so the three handled cups lose about 1.6% of
        # the card height (0.450 / 0.454 / 0.559 -> 0.435 / 0.438 /
        # 0.538). Asserted headlessly: INSET, HEROCUP.
        #
        # Pass 18 (v0.10.4). These four tokens are unchanged, but they no
        # longer bound the whole cup: the owner decided the labels may
        # overlap the handle, as the mock does. det_cup_x1..det_cup_x2 is
        # now the box the BOWL must fit; `hero_cup_box` hands
        # vessel_geometry a per-vessel box of that width / bowl_frac
        # (bowl_frac = 2*body_half / design_w, 1.0 without a handle), so
        # a handled cup's bowl lands exactly where its whole cup landed
        # in v0.10.3 and only the handle reaches into the md gap and
        # under the first letters of the labels. Handle-less vessels are
        # bit-identical. That is what buys the wide cups the last third:
        # large cup 0.365 -> 0.435 of the card height, cappuccino cup
        # 0.367 -> 0.438, demitasse 0.436 -> 0.538 in the Pass 24 box
        # (HEROCUP prints the table and the handle overlap in px).
        #
        # The mock's 0.56 is still above the ceiling, and so is a whole
        # cup at 0.40: our widest vessel, the large cup, is 124 design
        # units across (bowl plus handle) for 74 tall, so 40% of the
        # 1064-unit card height needs a 713-unit box for the WHOLE cup
        # and 55% needs 981 -- and the widest bowl box this page can give
        # is 650 (674 before Pass 24), because the hero card cannot pass
        # 0.47 without truncating a Method step (see above).
        # tools/geometry_check.tcl asserts that arithmetic (HEROCUP).
        #
        # Pass 25 (v0.13.2). The y-range is now the same ONE inset all
        # round: card_pad_x above the cup, exactly as at the sides, and
        # card_pad_x between the cup and the top of the garnish caption
        # line (which keeps its own card_pad_y under it). Through v0.13.1
        # the top used card_pad_y (28 units) while the bottom stopped a
        # whole reserved garnish ZONE early, so the tall glass sat 14
        # physical px under the card's top edge and 50 px clear at the
        # bottom (out/final/v131_detail_icedlatte.png). The height-bound
        # vessels (latte_glass, tumbler, highball, martini) now sit with
        # equal air above and below and gain 4 units on the way (928 ->
        # 932, 0.872 -> 0.876 of the card height); the width-bound cups
        # are bound by the WIDTH, so they are untouched. Nothing is
        # weakened: the zone only grows. Asserted headlessly: INSET,
        # HEROCUP.
        #
        # det_label_bottom is deliberately NOT the cup zone any more: the
        # labels are text, they keep the text rule (the reserved garnish
        # zone above the caption), so the label column is bit-identical
        # to v0.13.1.
        set L(det_label_w) [expr {int(round(181 * $scale))}]
        set L(det_garnish_h) [expr {int(round(40 * $scale))}]
        set L(det_cup_x1) [expr {$L(det_hero_x1) + $L(card_pad_x)}]
        set L(det_label_x2) [expr {$L(det_hero_x2) - $L(card_pad_x)}]
        set L(det_label_x) [expr {$L(det_label_x2) - $L(det_label_w)}]
        set L(det_label_maxw) $L(det_label_w)
        set L(det_cup_x2) [expr {$L(det_label_x) - $L(md)}]
        # The garnish caption is anchored sw at det_garnish_y, so its line
        # box starts one caption line (16 ref px) higher.
        set L(det_garnish_y) [expr {$L(det_hero_y2) - $L(card_pad_y)}]
        set L(det_garnish_top) [expr {$L(det_garnish_y) - int(round(16 * $scale))}]
        set L(det_cup_y1) [expr {$L(det_hero_y1) + $L(card_pad_x)}]
        set L(det_cup_y2) [expr {$L(det_garnish_top) - $L(card_pad_x)}]
        # Two text lines (body 19 + caption 16, with their line boxes) +
        # sm between label pairs.
        set L(det_label_pitch) [expr {int(round((24 + 20 + 10) * $scale))}]
        set L(det_label_dy) [expr {int(round(3 * $scale))}]
        set L(det_label_top) [expr {$L(det_hero_y1) + $L(card_pad_y)}]
        set L(det_label_bottom) [expr {$L(det_hero_y2) - $L(card_pad_y) - $L(det_garnish_h)}]
        set L(det_lead_w) 2
        set L(det_label_pool) 6
        # Right column: totals card (fixed height) + ingredients card.
        set L(det_right_x1) [expr {$L(det_hero_x2) + $L(xl)}]
        set L(det_right_x2) $L(right_x)
        set L(det_right_w) [expr {$L(det_right_x2) - $L(det_right_x1)}]
        set L(det_tot_y1) $L(list_top)
        # Pass 10 item 3: +22 ref px so a pooled second ratio-names
        # caption line fits (was 100, one line only; four-ingredient
        # drinks like Borgia truncated).
        set L(det_tot_h) [expr {int(round(122 * $scale))}]
        set L(det_tot_y2) [expr {$L(det_tot_y1) + $L(det_tot_h)}]
        set L(det_tot_fig_y) [expr {$L(det_tot_y1) + int(round(40 * $scale))}]
        set L(det_tot_cap_y) [expr {$L(det_tot_y1) + int(round(78 * $scale))}]
        set L(det_tot_names2_y) [expr {$L(det_tot_y1) + int(round(100 * $scale))}]
        set L(det_ratio_x) [expr {$L(det_right_x1) + int($L(det_right_w) * 0.42)}]
        set L(det_ratio_maxw) [expr {$L(det_right_x2) - $L(card_pad_x) - $L(det_ratio_x)}]
        set L(det_ing_y1) [expr {$L(det_tot_y2) + $L(md)}]
        set L(det_chip_h) [expr {int(round(40 * $scale))}]
        set L(det_chip_gap) $L(sm)
        # Pass 23 item 7: an ingredient chip is a FULL pill (mock .chip:
        # border-radius 999px), drawn as an exact stadium by _capsule_points
        # -- so this is the radius the chip really renders, half its height,
        # and nothing feeds it to a smoothing painter any more.
        set L(det_chip_radius) [expr {$L(det_chip_h) / 2}]
        set L(det_chip_pad_x) [expr {int(round(12 * $scale))}]
        set L(det_chip_dot) [expr {int(round(14 * $scale))}]
        set L(det_chip_gap_in) [expr {int(round(8 * $scale))}]
        set L(det_chip_gap_amt) [expr {int(round(6 * $scale))}]
        set L(det_chip_pool) 6
        # Pass 14 (item B1): the ingredients card no longer runs to the
        # bottom bar -- it shrinks to the two chip rows the widest drink
        # needs (v0.8.0 left it two thirds empty, see
        # design/v080_detail_borgia.png) and the Method card takes the
        # rest. chip_fit ellipsises the chip names of a pathological
        # six-layer custom rather than let a third row escape the card.
        set L(det_ing_rows) 2
        set L(det_ing_h) [expr {2 * $L(card_pad_y) + $L(det_ing_rows) * $L(det_chip_h) \
            + ($L(det_ing_rows) - 1) * $L(det_chip_gap)}]
        set L(det_ing_y2) [expr {$L(det_ing_y1) + $L(det_ing_h)}]
        set L(det_ing_inner_x) [expr {$L(det_right_x1) + $L(card_pad_x)}]
        set L(det_ing_inner_y) [expr {$L(det_ing_y1) + $L(card_pad_y)}]
        set L(det_ing_inner_w) [expr {$L(det_right_w) - 2 * $L(card_pad_x)}]
        # Method card: same x range and glass face as the other two, from
        # md below the chips card down to content_bottom. A section title
        # then a pool of 4 caption lines "<n>  <step>"; a drink with no
        # steps shows one grey caption on the first line instead. At the
        # reference geometry the card is 260 ref px tall: title centred at
        # +34, lines at +84/+128/+172/+216, so the last line box ends 22
        # ref px above the card floor (asserted headlessly: METHOD).
        set L(det_met_y1) [expr {$L(det_ing_y2) + $L(md)}]
        set L(det_met_y2) $L(content_bottom)
        set L(det_met_pool) 4
        set L(det_met_num_x) [expr {$L(det_right_x1) + $L(card_pad_x)}]
        set L(det_met_text_x) [expr {$L(det_met_num_x) + int(round(30 * $scale))}]
        set L(det_met_maxw) [expr {$L(det_right_x2) - $L(card_pad_x) - $L(det_met_text_x)}]
        set L(det_met_title_y) [expr {$L(det_met_y1) + int(round(34 * $scale))}]
        set L(det_met_line_y) [expr {$L(det_met_y1) + int(round(84 * $scale))}]
        set L(det_met_pitch) [expr {int(round(44 * $scale))}]
        # Pass 48: the "Add a method" link's tap rect (custom drinks with
        # no steps), and the Favorite button's icon / label positions.
        set L(det_met_add_w) [expr {int(round(300 * $scale))}]
        set L(fav_icon_pos) {0.15 0.5}
        set L(fav_label_pos) {0.6 0.5}

        # ---- Editor page sub-block ----
        # Header: title (font_section) at left_x, name entry to its right
        # (top zone, above the Android keyboard), Done (keyboard dismiss)
        # further right. v0.7.1: the entry used to start at a fixed 240
        # ref and sat on top of the longest title, "Edit custom drink"
        # (~225 physical px from left_x on the tablet, i.e. it ended past
        # 240 ref); it now starts after a reserved title width plus one
        # lg gap. 240 ref reserves the 17-char title at the 24 px section
        # font with the same 0.58 em/char estimate `_text_w` falls back to.
        set L(ed_title_w) [expr {int(round(240 * $scale))}]
        set L(ed_entry_x) [expr {$L(left_x) + $L(ed_title_w) + $L(lg)}]
        # Pass 23 item 5: the entry follows the header band down. `dui add
        # entry` anchors its window item nw (dui.tcl:10929), so this is the
        # entry's TOP: a 22 px face plus its border is ~30 ref px tall, and
        # centring that on the band leaves the whole control -- and the
        # keyboard Done beside it -- far above the 800-virtual keyboard line.
        set L(ed_entry_h) [expr {int(round(30 * $scale))}]
        set L(ed_entry_y) [expr {$L(hdr_band_mid) - $L(ed_entry_h) / 2}]
        set L(ed_entry_chars) 24
        set L(ed_done_x1) [expr {int(round(820 * $scale))}]
        set L(ed_done_x2) [expr {$L(ed_done_x1) + $L(btn_w_std)}]
        # Preview card: the box the detail hero card had through v0.10.1
        # (0.40 of the content width), kept as its own token in Pass 16.
        # The editor's right column is not three cards of running text
        # but 4-across ingredient/vessel chips whose names are already
        # ellipsised at this width; giving the detail page's 166 units to
        # the preview card would take two more characters off every
        # palette chip to enlarge a cup the editor only shows as a
        # thumbnail. The detail page is the one the pass is about, so the
        # editor page keeps its tablet-verified split unchanged.
        set L(ed_prev_frac) 0.40
        set L(ed_prev_x1) $L(det_hero_x1)
        set L(ed_prev_w) [expr {int($L(content_w) * $L(ed_prev_frac))}]
        set L(ed_prev_x2) [expr {$L(ed_prev_x1) + $L(ed_prev_w)}]
        set L(ed_prev_y1) $L(list_top)
        set L(ed_prev_y2) $L(content_bottom)
        # Pass 24: the preview cup obeys the same rule as the detail hero
        # -- the same inset from the card edges that the card's own text
        # keeps; INSET asserts it so it stays that way.
        #
        # Pass 25: that inset is card_pad_x on all four sides here too.
        # The Vessel caption under the cup takes the place of the detail
        # page's garnish line: it is anchored w at ed_vessel_y, so its
        # line box starts half a body line (19 ref px) higher, and the cup
        # zone ends card_pad_x above that. The preview loses 20 units of
        # height (632 -> 612 for the height-bound vessels) and gains the
        # symmetry; the cup is a thumbnail here and the rows beside it are
        # untouched.
        set L(ed_cup_x1) [expr {$L(ed_prev_x1) + $L(card_pad_x)}]
        set L(ed_cup_x2) [expr {$L(ed_prev_x2) - $L(card_pad_x)}]
        set L(ed_vessel_y) [expr {$L(ed_prev_y1) + int(round(352 * $scale))}]
        set L(ed_cap_top) [expr {$L(ed_vessel_y) - int(round(10 * $scale))}]
        set L(ed_cup_y1) [expr {$L(ed_prev_y1) + $L(card_pad_x)}]
        set L(ed_cup_y2) [expr {$L(ed_cap_top) - $L(card_pad_x)}]
        set L(ed_total_y)  [expr {$L(ed_prev_y1) + int(round(384 * $scale))}]
        set L(ed_status_y) [expr {$L(ed_prev_y1) + int(round(424 * $scale))}]
        set L(ed_text_w) [expr {$L(ed_prev_w) - 2 * $L(card_pad_x)}]
        # Pass 36: the tappable garnish line near the preview card's
        # floor -- below a two-line status, above the card bottom; its
        # tap rect is 96 virtual tall (48 physical, the touch floor) and
        # ends card_pad_y clear of the card's edge.
        set L(ed_garn_y) [expr {$L(ed_prev_y1) + int(round(500 * $scale))}]
        set L(ed_garn_tap_y1) [expr {$L(ed_garn_y) - 48}]
        set L(ed_garn_tap_y2) [expr {$L(ed_garn_y) + 48}]
        set L(ed_garn_entry_chars) 26
        # Right column rows: 8 rows of 56 on a 66 pitch from list_top
        # (last row ends at 168 + 7*66 + 56 = 686 ref < 700).
        set L(ed_col_x1) [expr {$L(ed_prev_x2) + $L(xl)}]
        set L(ed_col_x2) $L(det_right_x2)
        set L(ed_col_w) [expr {$L(ed_col_x2) - $L(ed_col_x1)}]
        set L(ed_row_h) [expr {int(round(56 * $scale))}]
        set L(ed_row_pitch) [expr {int(round(66 * $scale))}]
        set L(ed_rows_y0) $L(list_top)
        set L(ed_row_pool) 6
        # Layer row internals: dot, name, amount, then minus / plus /
        # remove squares (row_h) with sm gaps at the right end.
        set L(ed_dot) $L(det_chip_dot)
        set L(ed_row_dot_x) [expr {$L(ed_col_x1) + $L(card_pad_x)}]
        set L(ed_row_name_x) [expr {$L(ed_row_dot_x) + $L(ed_dot) + $L(det_chip_gap_in)}]
        set L(ed_rm_x1) [expr {$L(ed_col_x2) - $L(ed_row_h)}]
        set L(ed_plus_x1) [expr {$L(ed_rm_x1) - $L(sm) - $L(ed_row_h)}]
        set L(ed_minus_x1) [expr {$L(ed_plus_x1) - $L(sm) - $L(ed_row_h)}]
        # Pass 35: the reorder pair sits LEFT of the amount steppers --
        # [chevron-up chevron-down] move the row, [- +] change the
        # amount, [x] removes -- and the amount column derives from it,
        # so the name budget shrinks by exactly the two new squares.
        set L(ed_mvdn_x1) [expr {$L(ed_minus_x1) - $L(sm) - $L(ed_row_h)}]
        set L(ed_mvup_x1) [expr {$L(ed_mvdn_x1) - $L(sm) - $L(ed_row_h)}]
        set L(ed_amt_x) [expr {$L(ed_mvup_x1) - $L(lg)}]
        # 140 (was 100 * scale = 200): the widest amount this plugin can
        # print is "240 ml" / "8.1 oz" at font_body_b, ~132 virtual; the
        # 60 units returned go to the name, which pays for the arrows.
        set L(ed_amt_w) [expr {int(round(70 * $scale))}]
        set L(ed_name_maxw) [expr {$L(ed_amt_x) - $L(ed_amt_w) - $L(md) - $L(ed_row_name_x)}]
        # Pass 37/40: the layers mode's bottom row is THREE buttons now --
        # "+ Add layer", "Method (N)", "Profile: ..." -- equal thirds;
        # the method mode's step rows reuse the grid pitch with
        # [num][text][up][dn][x].
        # Pass 48: Method and Profile move up to a SECOND header row
        # (50/50, under Vessel / Group), the layer rows start at row
        # ed_rows_first, and "+ Add layer" is the only action below the
        # list: a wide ghost button that follows the last layer row
        # (moved at refresh, hidden once six layers are in).
        set L(ed_hdr2_y) [expr {$L(ed_rows_y0) + $L(ed_row_pitch)}]
        set L(ed_rows_first) 2
        set L(ed_b2_w) [expr {($L(ed_col_w) - $L(sm)) / 2}]
        set L(ed_method_x1) $L(ed_col_x1)
        set L(ed_method_x2) [expr {$L(ed_method_x1) + $L(ed_b2_w)}]
        set L(ed_prof_x1) [expr {$L(ed_method_x2) + $L(sm)}]
        set L(ed_add_x2) [expr {$L(ed_col_x1) + $L(btn_w_wide)}]
        set L(ed_st_num_x) [expr {$L(ed_col_x1) + $L(card_pad_x)}]
        set L(ed_st_txt_x) [expr {$L(ed_st_num_x) + int(round(30 * $scale))}]
        set L(ed_st_rm_x1) $L(ed_rm_x1)
        set L(ed_st_dn_x1) [expr {$L(ed_st_rm_x1) - $L(sm) - $L(ed_row_h)}]
        set L(ed_st_up_x1) [expr {$L(ed_st_dn_x1) - $L(sm) - $L(ed_row_h)}]
        set L(ed_st_maxw) [expr {$L(ed_st_up_x1) - $L(md) - $L(ed_st_txt_x)}]
        set L(ed_sf_entry_chars) 30
        # Pass 38: the vessel row splits too -- "Vessel: ..." (58%, the
        # longest vessel label needs the room) and "Group: ..." (the
        # rest). The group mode reuses the palette's 4-column chip grid.
        set L(ed_vbtn_x2) [expr {$L(ed_col_x1) + int($L(ed_col_w) * 0.58)}]
        set L(ed_gbtn_x1) [expr {$L(ed_vbtn_x2) + $L(sm)}]
        # Palette: caption row, then a 4 x 6 chip grid, then Cancel.
        set L(ed_grid_y0) [expr {$L(ed_rows_y0) + int(round(40 * $scale))}]
        set L(ed_pal_cols) 4
        set L(ed_pal_w) [expr {int(($L(ed_col_w) - 3 * $L(sm)) / 4)}]
        # Pool = one chip per ingredient, at most 24 (4 x 6 grid).
        variable ingredients
        set L(ed_pal_pool) 24
        catch { set L(ed_pal_pool) [expr {min(24, [dict size $ingredients])}] }
        set L(ed_cancel_y1) [expr {$L(ed_rows_y0) + 7 * $L(ed_row_pitch)}]
        set L(ed_cancel_y2) [expr {$L(ed_cancel_y1) + $L(ed_row_h)}]
        # Vessel picker: 2 x 4 grid of 190 ref tiles; pool = one tile per
        # vessel, at most 8 (an unfilled grid slot is simply never
        # created, same fix as the ed_pal_pool/ingredient count above).
        set L(ed_ves_h) [expr {int(round(190 * $scale))}]
        set L(ed_ves_w) $L(ed_pal_w)
        set L(ed_ves_cup_pad) $L(md)
        set L(ed_ves_name_dy) [expr {int(round(34 * $scale))}]
        set L(ed_ves_cap_dy) [expr {int(round(12 * $scale))}]
        variable vessels
        set L(ed_ves_pool) 8
        catch { set L(ed_ves_pool) [expr {min(8, [dict size $vessels])}] }
        # Custing mode (Pass 33): caption at the column top, then ONE row
        # with the name entry (left) and the ml/g capsule (right) -- the
        # entry must stay in the keyboard-safe top zone (y < 800 virtual;
        # this row tops out at ed_grid_y0 + pill_h = 508) -- then the 6 x 2
        # swatch grid, then Cancel / Add on the palette's own Cancel row.
        set L(ed_cu_row_y0) $L(ed_grid_y0)
        set L(ed_cu_row_y1) [expr {$L(ed_cu_row_y0) + $L(pill_h)}]
        set L(ed_cu_entry_chars) 18
        # Pass 34: room after a custom row's (shortened) name for the pen
        # that marks it editable.
        set L(ed_pen_slot) [expr {int(round(40 * $scale))}]
        # ed_cu_unit_x1/x2 are set with the header capsules further down:
        # they need unit_seg_w, which is measured there.
        set L(ed_sw) $L(ed_row_h)
        set L(ed_sw_gap) $L(sm)
        set L(ed_sw_y0) [expr {$L(ed_cu_row_y1) + $L(lg)}]
        set L(ed_sw_pitch) [expr {$L(ed_sw) + $L(ed_sw_gap)}]
        set L(ed_sw_ring_pad) [expr {int(round(5 * $scale))}]
        set L(ed_cu_add_x1) [expr {$L(ed_col_x2) - $L(btn_w_std)}]
        set L(ed_cu_cancel_x1) [expr {$L(ed_cu_add_x1) - $L(sm) - $L(btn_w_std)}]
        # Confirm card in the right column.
        set L(ed_cf_y1) $L(ed_rows_y0)
        set L(ed_cf_h) [expr {int(round(220 * $scale))}]
        set L(ed_cf_q_dy) [expr {int(round(28 * $scale))}]
        # Bottom bar: Cancel at left_x; right group Delete (wide, hidden
        # until the draft has been saved once), Save as copy (wide),
        # Save (std) with lg gaps: 240+24+240+24+200 = 728 ref = 762 px,
        # starting near x=530 px.
        set L(ed_save_x1) [expr {$L(right_x) - $L(btn_w_std)}]
        set L(ed_copy_x1) [expr {$L(ed_save_x1) - $L(lg) - $L(btn_w_wide)}]
        # Pass 48: Delete leaves the save group for the LEFT, beside
        # Cancel, at the standard width and in the danger tone.
        set L(ed_first_x1) [expr {$L(left_x) + $L(btn_w_std) + $L(lg)}]

        _apply_palette

        # Pixel-exact fonts, floored at 16px, all on font_scale. Named
        # Helv_* fallbacks first so every key is valid even if the "font"
        # command is unavailable.
        set L(font_title) Helv_20_bold
        set L(font_section) Helv_18_bold
        set L(font_primary) Helv_10_bold
        set L(font_body) Helv_9
        set L(font_body_b) Helv_9_bold
        set L(font_caption) Helv_8
        set L(font_caption_b) Helv_8_bold
        set L(font_button) Helv_10_bold
        set L(font_pill) Helv_9_bold
        foreach {name ref} {title 40 section 24 primary 22 body 19 body_b 19 caption 16 caption_b 16 button 20 pill 18} {
            set L(font_px_DM_$name) [expr {int(max(16, round($ref * $font_scale)))}]
        }
        catch {
            foreach {name ref bold} {title 40 1 section 24 1 primary 22 1 body 19 0 body_b 19 1 caption 16 0 caption_b 16 1 button 20 1 pill 18 1} {
                set px [expr {int(max(16, round($ref * $font_scale)))}]
                set fname "DM_$name"
                set weight [expr {$bold ? "bold" : "normal"}]
                if {[lsearch -exact [font names] $fname] >= 0} {
                    font configure $fname -size [expr {-$px}] -weight $weight
                } else {
                    font create $fname -family Helvetica -size [expr {-$px}] -weight $weight
                }
                set L(font_$name) $fname
            }
        }

        # Icon font from the app's own Font Awesome 6 Pro file
        # (MaintenanceTracker pattern; dui::font::add_or_get_familyname is
        # the core's loader). Used for the favorite star on tiles and the
        # star tab pill (icon-only labels). If unavailable, have_icons
        # stays 0 and text stands in ("*" / "Fav").
        set L(have_icons) 0
        set L(font_icon) $L(font_primary)
        set L(font_px_DM_icon) $L(font_px_DM_primary)
        catch {
            set fam [dui::font::add_or_get_familyname "Font Awesome 6 Pro-Regular-400.otf"]
            if {$fam ne ""} {
                set px [expr {int(max(16, round(22 * $font_scale)))}]
                if {[lsearch -exact [font names] DM_icon] >= 0} {
                    font configure DM_icon -family $fam -size [expr {-$px}]
                } else {
                    font create DM_icon -family $fam -size [expr {-$px}]
                }
                set L(font_icon) DM_icon
                set L(font_px_DM_icon) $px
                set L(have_icons) 1
            }
        }
        set L(star_glyph) [_glyph_for star]
        if {!$L(have_icons) || $L(star_glyph) eq ""} {
            set L(have_icons) 0
            set L(star_glyph) ""
        }
        # ---- The tile star: a DRAWN polygon, not a glyph (Pass 22) ----
        #
        # The star on a tile is a control, so its two states must read as
        # "filled gold" and "empty outline". Font Awesome draws U+F005
        # hollow in its Regular face and solid only in the Solid weight,
        # and the app ships (and loads) the Regular face alone
        # (de1app-core/dui.tcl:335) -- v0.12.0 asked the core's loader for
        # the Solid file and the tablet simply warned, leaving the
        # favorited star gold but still hollow
        # (out/final/final_main_star_on.png). A canvas polygon has no such
        # problem: its -fill really fills, in whatever colour the palette
        # holds. So the tile star is now a regular five-point polygon and
        # the Solid-weight font load is gone. (The star TAB pill and the
        # detail page's Favorite button are untouched: the pill still uses
        # L(star_glyph) in the Regular icon face, above.)
        #
        # Pass 23 item 4 halves it: the owner wants a SMALL star, so the
        # outer radius is 7 ref px (14 virtual units, from 23) and the inner
        # radius 0.42 of that -- a touch fuller than a true {5/2} star's
        # 0.382, which reads thin here. Both radii are set with the rest of
        # the tile geometry above, because the star's box, its tap rect and
        # the tap partition are all derived from them.
        #
        # The ten vertices as offsets from the star's centre, point up:
        # outer vertex k at -90 + 72k degrees, the inner vertex 36 degrees
        # after it. Canvas y grows downwards, so sin() is used as-is and
        # -90 degrees is the top point. Built ONCE here (every layout value
        # lives in L) and placed per slot by the menu page's setup, which
        # hands them to `dui add canvas_item` -- the same virtual ->
        # physical rescale path (dui::page::calc_x/calc_y, i.e.
        # dui::platform::rescale_x/y, exactly what _phys_pts calls) that
        # every cup polygon already goes through.
        set L(tile_star_pts) {}
        set _star_pi 3.14159265358979323846
        for {set _star_k 0} {$_star_k < 5} {incr _star_k} {
            foreach {_star_r _star_deg} [list \
                    $L(star_r_out) [expr {-90 + 72 * $_star_k}] \
                    $L(star_r_in)  [expr {-90 + 72 * $_star_k + 36}]] {
                set _star_a [expr {$_star_deg * $_star_pi / 180.0}]
                lappend L(tile_star_pts) \
                    [expr {int(round($_star_r * cos($_star_a)))}] \
                    [expr {int(round($_star_r * sin($_star_a)))}]
            }
        }
        # Other glyphs used as icon-only labels, with text fallbacks.
        foreach {key name fallback} {pen pen "e" minus minus "-" plus plus "+" xmark xmark "x" chev_l chevron-left "<" chev_r chevron-right ">" chev_u chevron-up "^" chev_d chevron-down "v"} {
            set g ""
            if {$L(have_icons)} { set g [_glyph_for $name] }
            set L(glyph_$key) [expr {$g ne "" ? $g : $fallback}]
            set L(glyph_font_$key) [expr {$g ne "" ? $L(font_icon) : $L(font_button)}]
        }
        set L(warn) [_blend $L(c_crema) $L(c_ink) 0.35]

        # ---- Header control row (Pass 23 item 6; needs the fonts) ----
        #
        # The mock's `.pill` and `.seg span` are 34 CSS px tall (46 ref px)
        # with a 13.5 px label, and each is only as wide as its own text plus
        # its padding -- not the 96-ref fixed slab v0.12.1 gave every tab. So
        # the widths are MEASURED here, which is why this block sits after
        # the font block rather than with the rest of the geometry: `_ctl_w`
        # goes through _text_w, i.e. `font measure` on the plugin's own
        # fonts, with the 0.58 em/char estimate as the headless fallback.
        # pill_min_w (72 ref) keeps the short tabs from shrinking to stubs
        # and, being a minimum, keeps "No milk" and "Custom" honest.
        # Pass 45: every pill, the favorites one included, is measured on
        # its worded label at the pill font.
        set L(pill_ws) {}
        foreach {tab label} $tabs {
            lappend L(pill_ws) [_ctl_w [translate $label] $L(font_pill)]
        }
        set L(pills_w) [expr {($n_tabs - 1) * $L(pill_gap)}]
        foreach _w $L(pill_ws) { set L(pills_w) [expr {$L(pills_w) + $_w}] }
        set L(pills_x1) [expr {$L(right_x) - $L(pills_w)}]
        set L(unit_seg_w) [expr {max([_ctl_w [translate ml] $L(font_pill)], \
                                     [_ctl_w [translate oz] $L(font_pill)])}]
        # Pass 45: the unit toggle is a display preference, not a filter,
        # so it stands a full xxl (48 ref px) clear of the filter pills
        # instead of the lg group gap, and its selected half wears the
        # secondary tone (seg_on_fill), never the filters' gold.
        set L(unit_gap) [expr {int(round(48 * $scale))}]
        set L(unit_x2) [expr {$L(pills_x1) - $L(unit_gap)}]
        set L(unit_x1) [expr {$L(unit_x2) - 2 * $L(unit_seg_w) - $L(seg_gap)}]
        set L(unit_xm) [expr {$L(unit_x1) + $L(unit_seg_w)}]
        # The custing mode's ml/g capsule (Pass 33) reuses the header
        # capsule's segment width; "g" is narrower than "oz", so both
        # labels fit the same halves.
        set L(ed_cu_unit_x2) $L(ed_col_x2)
        set L(ed_cu_unit_x1) [expr {$L(ed_cu_unit_x2) - 2 * $L(unit_seg_w) - $L(seg_gap)}]
        # Detail header: the same two capsules, right-aligned.
        set L(det_seg_w) [expr {max([_ctl_w [translate "1 shot"] $L(font_pill)], \
                                    [_ctl_w [translate "2 shots"] $L(font_pill)])}]
        set L(det_size_x2) $L(right_x)
        set L(det_size_x1) [expr {$L(det_size_x2) - 2 * $L(det_seg_w) - $L(seg_gap)}]
        set L(det_size_xm) [expr {$L(det_size_x1) + $L(det_seg_w)}]
        set L(det_unit_x2) [expr {$L(det_size_x1) - $L(group_gap)}]
        set L(det_unit_x1) [expr {$L(det_unit_x2) - 2 * $L(unit_seg_w) - $L(seg_gap)}]
        set L(det_unit_xm) [expr {$L(det_unit_x1) + $L(unit_seg_w)}]
        set L(det_title_maxw) [expr {$L(det_unit_x1) - $L(lg) - $L(left_x)}]

        # Shared button style. -theme default is REQUIRED: aspect lookup
        # falls back from a named theme to default, never the other way,
        # and under Lumen the current theme is DYE_Lumen by the time this
        # plugin loads (ShotHistoryEditor v0.5.4 / BeanScanner v0.1.2).
        # Two styles, both on -theme default:
        #   dm_btn          ghost bar button, radius btn_radius
        #   dm_btn_primary  the filled action(s) per page (Pass 12 B3, Pass
        #                   23 item 8): crema fill, crema_ink label. Menu =
        #                   Done, detail = Copy & edit / Edit, editor = the
        #                   keyboard Done and Save.
        # (dm_pill was the tab pills' style until pass 32: at a full pill's
        # radius, round_outline's separate fill and outline painters
        # disagreed -- a wrong horizontal line across the top and bottom of
        # every header pill -- so the pills are drawn polygons now, see
        # pill_shape.)
        #
        # Pass 23 item 7: both are `round_outline`, dui's fill-plus-
        # outline painter (dui.tcl:10118), so every button carries the mock's
        # 1 px glass edge without a single extra item -- the outline arcs and
        # lines are created with the button's own tags, so they hide, show
        # and carry st:hidden with it. `width` is in VIRTUAL units (dui
        # rescales it, dui.tcl:10136), so line_w = 2 is 1 physical px. Both
        # painters halve the radius they are given, hence the doubling.
        # Pass 43 (v1.13.0): the dbutton no longer paints its own face.
        # `shape none` is no shape dui knows, so its painter takes the
        # last branch (dui.tcl:10186) and creates the INVISIBLE rect every
        # unstyled tap dbutton gets; the face is drawn art underneath
        # (bar_button -> shape_make: anti-aliased cap photos + a flat body)
        # and the label stays dui's, so every relabel keeps working. NO
        # pressfill on an invisible rect (the press rule); the flash is
        # _flash_btn's, restored from state.
        if {[catch {
            dui aspect set -theme default -type dbutton -style dm_btn [list shape none]
            dui aspect set -theme default -type dbutton_label -style dm_btn [list \
                fill $L(btn_label) disabledfill $L(c_ink_3)]
            dui aspect set -theme default -type dbutton -style dm_btn_primary [list shape none]
            dui aspect set -theme default -type dbutton_label -style dm_btn_primary [list \
                fill $L(pill_on_text) disabledfill $L(c_ink_3)]
        } err]} {
            catch { msg -NOTICE "DrinkMenu: button aspect not set: $err" }
        }
    }

    # One header control's width: its own measured label plus md either
    # side, never under pill_min_w. PHYSICAL text width -> virtual through
    # px2v, like every other measured width in this file.
    proc _ctl_w {text font} {
        variable L
        set w [expr {int(ceil([_text_w $font $text] * $L(px2v))) + 2 * $L(pill_pad_x)}]
        if {$w < $L(pill_min_w)} { set w $L(pill_min_w) }
        return $w
    }

    # ------------------------------------------------------------------
    #  Drawing primitives
    # ------------------------------------------------------------------

    # ---- The gradient background (Pass 20) ----
    #
    # Tk's canvas cannot draw a gradient, so the mock's radial ramp ships
    # as a PNG per PHYSICAL resolution, the way Lumen ships
    # skins/Lumen/<W>x<H>/ (tools/make_bg.py writes them). The photo is
    # never scaled: Tk's `photo copy -zoom/-subsample` replicates or DROPS
    # whole pixels instead of resampling, so a screen size with no file of
    # its own falls back to the flat bg1 fill rather than to a mangled
    # image. ONE photo is created for the whole plugin (1340x800x3 bytes
    # on the tablet) and shared by the three pages; the attempt is made
    # once, so a missing file logs exactly one NOTICE.
    variable bg_photo ""
    variable bg_photo_tried 0
    variable bg_dir [file dirname [info script]]

    proc _bg_photo {} {
        variable L
        variable bg_photo
        variable bg_photo_tried
        variable bg_dir
        if {$bg_photo_tried} { return $bg_photo }
        set bg_photo_tried 1
        set bg_photo ""
        # Match the folder by WIDTH. On the tablet `winfo screenheight`
        # reports the height minus the Android system bar (1340x736 on a
        # 1340x800 screen, seen on the first v0.11.0 boot), so an exact
        # WxH match would miss the one file that fits. Exact match first,
        # else the same-width folder whose height is nearest (the canvas
        # clips or leaves a sliver; never scale a photo).
        set size "$L(phys_w)x$L(phys_h)"
        set fn [file join $bg_dir $size bg.png]
        if {![file exists $fn]} {
            set best ""; set bestd -1
            foreach cand [glob -nocomplain -directory $bg_dir -type d "$L(phys_w)x*"] {
                set tail [file tail $cand]
                if {![regexp {^(\d+)x(\d+)$} $tail -> cw ch]} { continue }
                if {![file exists [file join $cand bg.png]]} { continue }
                set d [expr {abs($ch - $L(phys_h))}]
                if {$bestd < 0 || $d < $bestd} { set best $tail; set bestd $d }
            }
            if {$best ne ""} {
                set size $best
                set fn [file join $bg_dir $size bg.png]
            }
        }
        if {![file exists $fn]} {
            catch { msg -NOTICE "DrinkMenu: background image $size/bg.png not found; using the flat $L(page_bg) fill" }
            return ""
        }
        # The core's own way of turning a file into a photo
        # (de1app-core/dui.tcl ~5117). dui add image is deliberately NOT
        # used: it searches `dui image dirs` (the skin's folders, not the
        # plugin's) and rescales through photoscale on a miss.
        if {[catch { ::image create photo dm_bg_$size -file $fn } err]} {
            catch { msg -NOTICE "DrinkMenu: background image $size/bg.png did not load ($err); using the flat $L(page_bg) fill" }
            return ""
        }
        set bg_photo dm_bg_$size
        return $bg_photo
    }

    # Full-page background, first item of every page -- so it is lowest in
    # the stacking order, and contrast never depends on the active skin
    # theme (fpdialog pages otherwise show whatever lies beneath).
    proc _page_bg {page} {
        variable L
        set img [_bg_photo]
        if {$img ne ""} {
            # Not a bare catch: the page must still get a background if
            # the item is refused, and the NOTICE is the forbidden string
            # the pass's log scan watches for.
            if {![catch { dui add canvas_item image $page 0 0 \
                    -image $img -anchor nw -tags page_bg_img } err]} {
                return
            }
            catch { msg -NOTICE "DrinkMenu: background image item refused on $page ($err); using the flat $L(page_bg) fill" }
        }
        dui add canvas_item rect $page 0 0 $L(screen_w) $L(screen_h) \
            -fill $L(page_bg) -outline $L(page_bg) -tags page_bg
        _theme_item $page page_bg fill page_bg
        _theme_item $page page_bg outline page_bg
    }

    # Control points of the rounded-rect polygon (radius clamped).
    proc _rr_points {x1 y1 x2 y2 radius} {
        set r $radius
        if {$r * 2 > ($x2 - $x1)} { set r [expr {($x2 - $x1) / 2}] }
        if {$r * 2 > ($y2 - $y1)} { set r [expr {($y2 - $y1) / 2}] }
        return [list \
            [expr {$x1 + $r}] $y1 \
            [expr {$x2 - $r}] $y1 \
            $x2 $y1 \
            $x2 [expr {$y1 + $r}] \
            $x2 [expr {$y2 - $r}] \
            $x2 $y2 \
            [expr {$x2 - $r}] $y2 \
            [expr {$x1 + $r}] $y2 \
            $x1 $y2 \
            $x1 [expr {$y2 - $r}] \
            $x1 [expr {$y1 + $r}] \
            $x1 $y1]
    }

    # Rounded-rectangle backdrop (ShotHistoryEditor rounded_rect: smoothed
    # canvas polygon; -fill reconfigurable via `dui item config`).
    proc rounded_rect {page x1 y1 x2 y2 radius args} {
        set pts [_rr_points $x1 $y1 $x2 $y2 $radius]
        return [uplevel #0 [list dui add canvas_item polygon $page {*}$pts -smooth 1 {*}$args]]
    }

    # ---- The card gradient (Pass 23 item 3) ----
    #
    # A Tk canvas rect cannot hold a gradient, so the mock's
    # `linear-gradient(165deg, rgba(255,255,255,.12), rgba(255,255,255,
    # .045))` is painted into a photo, one per distinct PHYSICAL size --
    # the twelve tiles are one size, so they share ONE photo, and so do the
    # seven vessel-picker tiles. `$img put {{#rrggbb}} -to x0 y x1 y+1`
    # tiles a 1x1 colour across a whole run of a row, so a photo costs a
    # handful of puts per row and nothing per pixel.
    #
    # The corners are simply never painted: a freshly created photo is
    # fully transparent, so each row is drawn only across the rounded
    # rectangle's own horizontal span and everything outside radius r
    # keeps alpha 0 -- the page's gradient shows through, with no
    # per-pixel `transparency set` loop at all. If a platform ever hands
    # back an OPAQUE fresh photo (checked, not assumed, with
    # `transparency get`), the corners are painted in c_bg instead, which
    # is the flat fallback the page background already degrades to.
    #
    # Pass 26 (v0.13.3). The photo now carries the card's EDGE and its top
    # highlight too, so the card is ONE shape. Up to v0.13.2 the edge was a
    # separate smoothed polygon drawn over the photo, and a `-smooth 1`
    # corner is not a circular arc: it ran as a shallow diagonal outside
    # the photo's true circle, so a dark wedge of page showed between the
    # two and the corner read as a notch (out/final/final2_main_p1.png).
    # Baking the edge into the image removes the second shape entirely --
    # per row, the first and last painted pixel of the span are the edge
    # colour (white .17 over that row's own colour), row 0 and row h - 1
    # are edge colour right across their spans, and row 1 carries the
    # highlight (white .26 over its row colour) between the span's inner
    # pixels. The carve is back at exactly r: there is no polygon left for
    # it to hide behind, so no slack is needed.
    #
    # Pass 29 (v1.1.0). Three changes, all inside the photo -- no drawn
    # item moves, so every token, tap rect and text of v1.0.1 is where it
    # was:
    #   1. the ramp is the mock's real 165-deg DIAGONAL, so the top-left
    #      corner is the family's top fraction and the bottom-right its
    #      bottom one. A row is no longer one colour: it is up to 7 runs of
    #      equal quantised colour (_glass_runs), which is why the flat
    #      "one put per row" of Pass 23 is gone;
    #   2. each mock family keeps its OWN pair (mock_glass_kinds), so the
    #      cache key is "<w>x<h>x<r>x<kind>". The sizes happen to be
    #      distinct per family anyway, so the photo count is unchanged;
    #   3. row 1's single lit line became a glow BAND: rows 1..glow fade
    #      from the highlight colour to the plain row colour. Row 0 and row
    #      h - 1 and the two side rails are untouched -- still the edge
    #      white over the colour under them.
    # The mock's drop shadow (`0 6px 18px rgba(0,0,0,.35)`) is not painted.
    # A Tk photo has no per-pixel alpha, so the shadow can only live in a
    # page-coloured margin of the photo itself, and S = 10 / 14 px on three
    # sides grows the seven photos from 967,404 to 1,066,622 px: 4,266,488
    # bytes against the pass's 4,194,304 budget. The pass's own fallback
    # rule applies -- the shadow is the first thing dropped.
    #
    # Photos are created at page SETUP through glass_card and never
    # touched again; nothing in a refresh path reaches this proc.
    variable glass_photos
    array set glass_photos {}
    variable glass_bytes 0
    variable glass_n 0
    # Pass 42: per photo NAME, the shadow margin S (physical px) baked
    # round the card, 0 for a `put` fallback photo; and the setup time.
    variable glass_margin
    array set glass_margin {}
    variable glass_ms 0
    variable glass_png_n 0
    variable glass_logged 0

    # Drops the cache WITHOUT deleting any Tk image: only the headless
    # check needs it (each section runs the page setups again over its own
    # image stub). The app calls _init_layout once, from preload.
    proc glass_reset {} {
        variable glass_photos
        variable glass_bytes
        variable glass_n
        variable glass_margin
        variable glass_ms
        variable glass_png_n
        array unset glass_photos
        array set glass_photos {}
        array unset glass_margin
        array set glass_margin {}
        set glass_bytes 0
        set glass_n 0
        set glass_ms 0
        set glass_png_n 0
        # Pass 44: the cup sprites too (the headless net re-records).
        variable cup_sprite_cache
        variable cup_sprite_ok
        variable cup_n
        variable cup_bytes
        variable cup_ms
        array unset cup_sprite_cache
        array set cup_sprite_cache {}
        set cup_sprite_ok 1
        set cup_n 0
        set cup_bytes 0
        set cup_ms 0
        # Pass 46: the mark sprites too.
        variable mark_photos
        variable mark_ok
        variable mark_n
        variable mark_bytes
        variable mark_ms
        array unset mark_photos
        array set mark_photos {}
        set mark_ok 1
        set mark_n 0
        set mark_bytes 0
        set mark_ms 0
    }

    # The photo for a w x h card with a drawn corner radius r, ALL IN
    # PHYSICAL PIXELS (a Tk photo is never scaled). Returns the image name,
    # or "" when the platform refuses one -- glass_card then falls back to
    # the flat card_fill rounded rect v0.12.1 drew.
    # The painted span of row $y is [ins, w - 1 - ins]: the inset of a
    # true circle of radius $rr at the top and bottom corners of an
    # $h-tall photo, sampled at the row's centre (y + 0.5). Pure, so the
    # headless GLASS check can assert the photo really follows a circle.
    proc _glass_inset {rr h y} {
        if {$rr <= 0.0} { return 0 }
        set dy 0.0
        if {$y < $rr} {
            set dy [expr {$rr - 0.5 - $y}]
        } elseif {$y >= $h - $rr} {
            set dy [expr {$y - ($h - $rr) + 0.5}]
        }
        if {$dy <= 0.0} { return 0 }
        if {$dy > $rr} { set dy $rr }
        return [expr {int(ceil($rr - sqrt($rr * $rr - $dy * $dy)))}]
    }

    # The quantised ramp of one card family: mock_glass_steps + 1 solid
    # colours from the family's BOTTOM white fraction (index 0) to its TOP
    # (index mock_glass_steps). Pure, so the headless GLOW check can
    # rebuild it from the same mock numbers instead of reading it back.
    proc _glass_ramp {kind} {
        variable L
        variable mock_glass_kinds
        variable mock_glass_steps
        lassign [dict get $mock_glass_kinds $kind] f_top f_bot f_hi glow
        set out {}
        for {set i 0} {$i <= $mock_glass_steps} {incr i} {
            lappend out [_blend $L(c_bg) "#ffffff" \
                [expr {$f_bot + ($f_top - $f_bot) * $i / double($mock_glass_steps)}]]
        }
        return $out
    }

    # One row of the diagonal ramp, as {x_from x_to colour} triples with
    # x_to INCLUSIVE, covering [$x0, $x1] exactly. `base` is the ramp index
    # at x = 0 of this row and `bx` the index lost per pixel of x, so the
    # index at x is round(base - bx * x) -- the 165-deg diagonal, quantised.
    # Neighbouring runs that landed on the same colour are merged, so no
    # put is wasted on a colour Tk already has there. Pure.
    proc _glass_runs {ramp base bx x0 x1} {
        set n [expr {[llength $ramp] - 1}]
        set out {}
        set x $x0
        while {$x <= $x1} {
            set v [expr {int(floor($base + 0.5 - $bx * $x))}]
            if {$v > $n} { set v $n }
            if {$v < 0}  { set v 0 }
            # The last x of this row that still quantises to $v.
            set xe $x1
            if {$bx > 0.0} {
                set xe [expr {int(floor(($base + 0.5 - $v) / $bx))}]
                if {$xe > $x1} { set xe $x1 }
                if {$xe < $x}  { set xe $x }
            }
            set col [lindex $ramp $v]
            if {[llength $out] > 0 && [lindex [lindex $out end] 2] eq $col} {
                lset out end 1 $xe
            } else {
                lappend out [list $x $xe $col]
            }
            set x [expr {$xe + 1}]
        }
        return $out
    }

    # ---- Pass 42 (v1.12.0): anti-aliased cards with a real drop shadow ----
    #
    # Tk's canvas draws no anti-aliasing and a photo `put` has no alpha, so
    # up to v1.11.0 every card corner stair-stepped and the mock's drop
    # shadow (`0 6px 18px rgba(0,0,0,.35)`, hero `0 8px 24px .4`) was not
    # painted at all. A Tk 8.6 photo CAN carry per-pixel alpha when it is
    # loaded from PNG data, and Tcl 8.6 has zlib built in -- so a card is
    # now painted as RGBA rows in pure Tcl (glass_rgba), encoded as a PNG
    # in memory (png_encode) and created with `image create photo -data`.
    # Nothing is shipped per resolution and nothing is scaled: the photo is
    # made at the exact PHYSICAL size the tablet asks for, as before.
    #
    # The photo is the card plus a margin of S physical px on every side
    # (L(shadow_m) virtual, rescaled): the card body sits at [S, S + w) x
    # [S, S + h), so glass_card places the image S px up and left of the
    # card and every other item keeps its coordinates. The shadow is a
    # black layer under the card, shifted L(shadow_dy) down and blurred
    # by a logistic profile over E = S - dy px -- separable (fx * fy),
    # which is exact for a blurred rectangle and indistinguishable at
    # these radii. Card coverage comes from the rounded-rect signed distance
    # (one pixel of anti-aliasing), the .10 hairline is the 1 px ring just
    # inside the edge, and the pixel is the card composited over the
    # shadow in straight alpha (what PNG stores). The body keeps the
    # quantised 165-deg ramp of Pass 29 as runs of equal colour; only the
    # margin, the corner zone (r + 1 px either side) and the top / bottom
    # rows are painted per pixel, so a tile costs ~25k pixel evaluations.
    #
    # A platform that refuses the PNG (or the encoder throwing) falls back
    # to the v1.11.0 `put` painter, _glass_put_photo, at margin 0 -- the
    # card then simply has no shadow and hard corners again, never a hole.
    # Pure procs (no Tk): _hex_rgb, glass_rgba, png_encode -- the headless
    # net decodes the very PNG the tablet gets.
    variable mock_card_shadow {tile 0.35 card 0.35 hero 0.40}

    proc _hex_rgb {hex} {
        scan $hex "#%2x%2x%2x" r g b
        return [list $r $g $b]
    }

    proc _png_chunk {type data} {
        set td "$type$data"
        return "[binary format I [string length $data]]$td[binary format I [zlib crc32 $td]]"
    }

    # rows: one binary string of 4 * w bytes (RGBA, straight alpha) per row.
    proc png_encode {w h rows} {
        set raw ""
        foreach r $rows { append raw "\x00" $r }
        set ihdr [binary format IIccccc $w $h 8 6 0 0 0]
        return "\x89PNG\r\n\x1a\n[_png_chunk IHDR $ihdr][_png_chunk IDAT [zlib compress $raw 6]][_png_chunk IEND {}]"
    }

    # One per-pixel span [x0, x1) of photo row y (card row cy) -- the
    # margin, the corner zone, or a whole top / bottom row. See glass_rgba.
    proc _glass_px_span {x0 x1 cy w h rr S wy fx rgbs edges base bx n} {
        set out ""
        set hw [expr {$w / 2.0}]
        set hh [expr {$h / 2.0}]
        set py [expr {$cy + 0.5 - $hh}]
        set qy [expr {abs($py) - ($hh - $rr)}]
        set my [expr {$qy > 0.0 ? $qy : 0.0}]
        for {set x $x0} {$x < $x1} {incr x} {
            set as [expr {$wy * [lindex $fx $x]}]
            set cx [expr {$x - $S}]
            set c 0.0
            if {$cx >= 0 && $cx < $w} {
                set px [expr {$cx + 0.5 - $hw}]
                set qx [expr {abs($px) - ($hw - $rr)}]
                set mx [expr {$qx > 0.0 ? $qx : 0.0}]
                set mq [expr {$qx > $qy ? $qx : $qy}]
                set d [expr {sqrt($mx * $mx + $my * $my) + ($mq < 0.0 ? $mq : 0.0) - $rr}]
                set c [expr {0.5 - $d}]
                if {$c > 1.0} { set c 1.0 } elseif {$c < 0.0} { set c 0.0 }
            }
            if {$c <= 0.0} {
                append out [binary format cccc 0 0 0 [expr {int($as * 255.0 + 0.5)}]]
                continue
            }
            set e [expr {-0.5 - $d}]
            if {$e > 1.0} { set e 1.0 } elseif {$e < 0.0} { set e 0.0 }
            set e [expr {$c - $e}]
            set v [expr {int(floor($base + 0.5 - $bx * $cx))}]
            if {$v > $n} { set v $n } elseif {$v < 0} { set v 0 }
            lassign [lindex $rgbs $v] r g b
            if {$e > 0.0} {
                lassign [lindex $edges $v] er eg eb
                set t [expr {$e / $c}]
                set r [expr {$r + ($er - $r) * $t}]
                set g [expr {$g + ($eg - $g) * $t}]
                set b [expr {$b + ($eb - $b) * $t}]
            }
            set oa [expr {$c + $as * (1.0 - $c)}]
            set k [expr {$c / $oa}]
            append out [binary format cccc [expr {int($r * $k + 0.5)}] [expr {int($g * $k + 0.5)}] \
                [expr {int($b * $k + 0.5)}] [expr {int($oa * 255.0 + 0.5)}]]
        }
        return $out
    }

    # The RGBA rows of one card photo: card w x h, control radius r, ramp
    # family kind, shadow margin S and shadow offset dy (all physical px).
    # Pure; returns a list of (h + 2S) rows of 4 (w + 2S) bytes.
    proc glass_rgba {w h r kind S dy} {
        variable mock_glass_kinds
        variable mock_glass_edge
        variable mock_glass_dx
        variable mock_glass_dy
        variable mock_glass_steps
        variable mock_card_shadow
        set ramp [_glass_ramp $kind]
        set rgbs [lmap c $ramp {_hex_rgb $c}]
        set edges [lmap c $ramp {_hex_rgb [_blend $c "#ffffff" $mock_glass_edge]}]
        set n $mock_glass_steps
        set rr [expr {double($r)}]
        if {$rr * 2.0 > $w} { set rr [expr {$w / 2.0}] }
        if {$rr * 2.0 > $h} { set rr [expr {$h / 2.0}] }
        set dsum [expr {$mock_glass_dx + $mock_glass_dy}]
        set bx [expr {$n * $mock_glass_dx / ($dsum * ($w - 1))}]
        set by [expr {$n * $mock_glass_dy / ($dsum * ($h - 1))}]
        set A [dict get $mock_card_shadow $kind]
        set E [expr {double($S - $dy)}]
        if {$E < 2.0} { set E 2.0 }
        set W [expr {$w + 2 * $S}]
        set H [expr {$h + 2 * $S}]
        # The separable shadow weights: the card's rectangle shifted dy
        # down, BLURRED -- each axis is a logistic 1 / (1 + exp(1.7 d /
        # sigma)) of the signed distance d to the rectangle's nearest edge
        # (negative inside), which is the normal CDF to 1%, with sigma =
        # .36 E so the tail is gone by the margin's last pixel; that tail
        # is subtracted so the weight is exactly 0 there. Under the card
        # the weight is ~.85 at the bottom edge, .5 at the shifted edge,
        # .15 five px further and 0 at the margin -- a soft shadow, not
        # the hard slab the first cut of this pass painted (a full-alpha
        # band of dy px, then a quadratic drop).
        set sg [expr {0.36 * $E}]
        set k [expr {1.7 / $sg}]
        set tail [expr {1.0 / (1.0 + exp($k * ($E - 1.0)))}]
        set fx {}
        for {set x 0} {$x < $W} {incr x} {
            set d [expr {max($S - $x, $x - ($S + $w - 1))}]
            set g [expr {(1.0 / (1.0 + exp($k * $d)) - $tail) / (1.0 - $tail)}]
            lappend fx [expr {$g < 0.0 ? 0.0 : $g}]
        }
        set fy {}
        set y0 [expr {$S + $dy}]
        for {set y 0} {$y < $H} {incr y} {
            set d [expr {max($y0 - $y, $y - ($y0 + $h - 1))}]
            set g [expr {(1.0 / (1.0 + exp($k * $d)) - $tail) / (1.0 - $tail)}]
            lappend fy [expr {$g < 0.0 ? 0.0 : $g}]
        }
        set zone [expr {int(ceil($rr)) + 1}]
        set rows {}
        for {set y 0} {$y < $H} {incr y} {
            set wy [expr {$A * [lindex $fy $y]}]
            set cy [expr {$y - $S}]
            if {$cy < 0 || $cy >= $h} {
                lappend rows [binary format c* [concat {*}[lmap f $fx \
                    {list 0 0 0 [expr {int($wy * $f * 255.0 + 0.5)}]}]]]
                continue
            }
            set base [expr {$n - $by * $cy}]
            set xa [expr {$S + $zone}]
            set xb [expr {$S + $w - $zone}]
            if {$cy == 0 || $cy == $h - 1 || $xa >= $xb} { set xa $W ; set xb $W }
            set row [_glass_px_span 0 $xa $cy $w $h $rr $S $wy $fx $rgbs $edges $base $bx $n]
            if {$xa < $xb} {
                foreach run [_glass_runs $ramp $base $bx [expr {$xa - $S}] [expr {$xb - $S - 1}]] {
                    lassign $run rx0 rx1 rcol
                    lassign [_hex_rgb $rcol] r g b
                    append row [string repeat [binary format cccc $r $g $b 255] [expr {$rx1 - $rx0 + 1}]]
                }
                append row [_glass_px_span $xb $W $cy $w $h $rr $S $wy $fx $rgbs $edges $base $bx $n]
            }
            lappend rows $row
        }
        return $rows
    }

    # The card photo: PNG with alpha (margin S round the card) when the
    # platform takes it, else the v1.11.0 `put` painter at margin 0.
    # glass_margin($img) tells glass_card which one it got.
    proc glass_photo {w h r kind {S 0} {dy 0}} {
        variable L
        variable glass_photos
        variable glass_bytes
        variable glass_n
        variable glass_margin
        variable glass_ms
        variable glass_png_n
        variable mock_glass_kinds
        if {$w < 2 || $h < 2} { return "" }
        if {![dict exists $mock_glass_kinds $kind]} { set kind card }
        set key "${w}x${h}x${r}x${kind}"
        if {[info exists glass_photos($key)]} { return $glass_photos($key) }
        if {$S > 0} {
            set img "dm_glass_$key"
            set t0 [clock microseconds]
            if {[catch {
                set W [expr {$w + 2 * $S}]
                set H [expr {$h + 2 * $S}]
                set png [png_encode $W $H [glass_rgba $w $h $r $kind $S $dy]]
                ::image create photo $img -data $png
            } err]} {
                catch { ::image delete $img }
                catch { msg -NOTICE "DrinkMenu: glass png $key refused ($err); painting the flat-corner photo instead" }
            } else {
                set glass_ms [expr {$glass_ms + ([clock microseconds] - $t0) / 1000.0}]
                set glass_photos($key) $img
                set glass_margin($img) $S
                incr glass_n
                incr glass_png_n
                set glass_bytes [expr {$glass_bytes + $W * $H * 4}]
                return $img
            }
        }
        set img [_glass_put_photo $w $h $r $kind]
        if {$img ne ""} { set glass_margin($img) 0 }
        return $img
    }

    # One NOTICE line, once, so a boot log shows what the cards cost.
    proc glass_log {} {
        variable glass_logged
        variable glass_n
        variable glass_png_n
        variable glass_bytes
        variable glass_ms
        if {$glass_logged || $glass_n == 0} { return }
        set glass_logged 1
        catch { msg -NOTICE [format "DrinkMenu: %d card photos (%d png with shadow), %.2f MB, painted in %.0f ms" \
            $glass_n $glass_png_n [expr {$glass_bytes / 1048576.0}] $glass_ms] }
    }

    proc _glass_put_photo {w h r kind} {
        variable L
        variable glass_photos
        variable glass_bytes
        variable glass_n
        variable mock_glass_edge
        variable mock_glass_kinds
        variable mock_glass_dx
        variable mock_glass_dy
        variable mock_glass_steps
        if {$w < 2 || $h < 2} { return "" }
        if {![dict exists $mock_glass_kinds $kind]} { set kind card }
        set key "${w}x${h}x${r}x${kind}"
        if {[info exists glass_photos($key)]} { return $glass_photos($key) }
        set img "dm_glass_$key"
        if {[catch { ::image create photo $img -width $w -height $h } err]} {
            catch { msg -NOTICE "DrinkMenu: glass photo $key not created ($err); using the flat $L(card_fill) fill" }
            set glass_photos($key) ""
            return ""
        }
        if {[catch {
            lassign [dict get $mock_glass_kinds $kind] f_top f_bot f_hi glow
            set ramp [_glass_ramp $kind]
            set rr [expr {double($r)}]
            if {$rr * 2.0 > $w} { set rr [expr {$w / 2.0}] }
            if {$rr * 2.0 > $h} { set rr [expr {$h / 2.0}] }
            # The ramp index lost per pixel across and down: together they
            # are the 165-deg direction, normalised so the top-left pixel
            # is exactly the family's top fraction and the bottom-right
            # pixel exactly its bottom one.
            set dsum [expr {$mock_glass_dx + $mock_glass_dy}]
            set bx [expr {$mock_glass_steps * $mock_glass_dx / ($dsum * ($w - 1))}]
            set by [expr {$mock_glass_steps * $mock_glass_dy / ($dsum * ($h - 1))}]
            for {set y 0} {$y < $h} {incr y} {
                set ins [_glass_inset $rr $h $y]
                if {2 * $ins >= $w} { continue }
                set x0 $ins
                set x1 [expr {$w - 1 - $ins}]
                # The row's own gradient, as runs of equal colour; the edge
                # and the glow are composited over THEM, not over the page,
                # so both keep the mock's alphas exactly as _apply_palette
                # computes card_edge and c_spec at the top of the ramp.
                set runs [_glass_runs $ramp \
                    [expr {$mock_glass_steps - $by * $y}] $bx $x0 $x1]
                if {$y == 0 || $y == $h - 1} {
                    # The card's top and bottom rules: edge colour right
                    # across the span, so the rim runs into the corner
                    # arc without a join.
                    foreach run $runs {
                        lassign $run rx0 rx1 rcol
                        $img put [list [list [_blend $rcol "#ffffff" $mock_glass_edge]]] \
                            -to $rx0 $y [expr {$rx1 + 1}] [expr {$y + 1}]
                    }
                    continue
                }
                # Pass 29: the mock's `inset 0 1px 0 rgba(255,255,255,.26)`
                # as a soft band -- rows 1..glow fade from the highlight
                # colour down to the plain row colour, so the top edge
                # glows instead of carrying one lit line.
                set lit 0.0
                if {$y <= $glow} {
                    set lit [expr {$f_hi * ($glow - $y + 1) / double($glow)}]
                }
                foreach run $runs {
                    lassign $run rx0 rx1 rcol
                    if {$lit > 0.0} { set rcol [_blend $rcol "#ffffff" $lit] }
                    $img put [list [list $rcol]] -to $rx0 $y [expr {$rx1 + 1}] [expr {$y + 1}]
                }
                # The two side rails, one pixel each, at the exact ends of
                # this row's circular span: the edge white over the PLAIN
                # colour of the run they sit in, exactly as v0.13.3 baked
                # the rim (the glow never reaches them).
                $img put [list [list [_blend [lindex [lindex $runs 0] 2] "#ffffff" $mock_glass_edge]]] \
                    -to $x0 $y [expr {$x0 + 1}] [expr {$y + 1}]
                $img put [list [list [_blend [lindex [lindex $runs end] 2] "#ffffff" $mock_glass_edge]]] \
                    -to $x1 $y [expr {$x1 + 1}] [expr {$y + 1}]
            }
            # The corners must have stayed transparent. Verified, not
            # assumed: a platform that hands back an opaque photo gets the
            # c_bg fallback the pass names instead of black corner blocks.
            set clear 1
            if {$rr > 0.0} {
                catch { set clear [$img transparency get 0 0] }
                if {!$clear} {
                    for {set y 0} {$y < $h} {incr y} {
                        set ins [_glass_inset $rr $h $y]
                        if {$ins < 1} { continue }
                        $img put [list [list $L(c_bg)]] -to 0 $y $ins [expr {$y + 1}]
                        $img put [list [list $L(c_bg)]] -to [expr {$w - $ins}] $y $w [expr {$y + 1}]
                    }
                }
            }
        } err]} {
            catch { msg -NOTICE "DrinkMenu: glass photo $key not painted ($err); using the flat $L(card_fill) fill" }
            catch { ::image delete $img }
            set glass_photos($key) ""
            return ""
        }
        set glass_photos($key) $img
        incr glass_n
        # Tk stores a photo as 4 bytes per pixel (pix32), so that is what a
        # photo really costs; the headless GLASS check budgets the total.
        set glass_bytes [expr {$glass_bytes + $w * $h * 4}]
        return $img
    }

    # Glass card (Pass 23 item 3): the mock's gradient body as ONE photo,
    # with the edge hairline baked into it (Pass 26). Items: <tag>_img --
    # plus <tag>_body, the drawn edge polygon, ONLY on the flat fallback
    # path (no photo). Pass 41 (tonal) removed the <tag>_spec highlight
    # and <tag>_shade lines every card used to carry. Callers that hide or
    # re-theme a card by tag must list <tag>_body only for a card they
    # know has no photo (the editor's confirm panel), or `dui item` logs
    # "no canvas tag matches".
    #
    # `radius` is the CONTROL-point radius (fed doubled, see btn_radius);
    # "" takes card_radius. `gradient` 0 keeps the flat card_fill face of
    # v0.12.1 -- the editor's confirm PANEL uses it: it is a transient
    # modal with no counterpart in the mock, and its own 660 KB photo would
    # push the set past the pass's 4 MB budget (see PROJECT_STATE).
    # `kind` (Pass 29) is the mock family whose ramp the photo gets --
    # tile, card or hero, see mock_glass_kinds -- and is part of the photo
    # cache key. It does not change the card's geometry in any way.
    proc glass_card {page tag x y w h {radius ""} {gradient 1} {kind card}} {
        variable L
        set x2 [expr {$x + $w}]
        set y2 [expr {$y + $h}]
        set r [expr {$radius eq "" ? $L(card_radius) : $radius}]
        set items [list ${tag}_img]
        set img ""
        if {$gradient} {
            # PHYSICAL size and corner radius: the photo is drawn 1:1 at
            # the position dui::page::calc_x/calc_y put the image item at,
            # and the drawn corner is half the control radius. The size is
            # rescaled from the card's own w/h, NOT from the difference of
            # two rescaled absolute edges: rescale_x truncates, so the
            # latter can come out a pixel apart for two cards of identical
            # size and split the twelve tiles across two photos.
            set pw [dui::platform::rescale_x $w]
            set ph [dui::platform::rescale_y $h]
            set pr [dui::platform::rescale_x [expr {$r / 2}]]
            # Pass 42: the shadow margin and offset, physical too.
            set ps [dui::platform::rescale_x $L(shadow_m)]
            set pdy [dui::platform::rescale_y $L(shadow_dy)]
            set img [glass_photo $pw $ph $pr $kind $ps $pdy]
        }
        if {$img ne ""} {
            # Pass 42: a PNG photo carries S px of shadow margin on every
            # side, so its item sits S px up and left of the card. The
            # offset is handed to dui in VIRTUAL units: S / scale, less a
            # hair, so dui's truncating rescale lands the item at exactly
            # floor(x * scale) - S and the card body stays where it was.
            set ix $x
            set iy $y
            variable glass_margin
            if {[info exists glass_margin($img)] && $glass_margin($img) > 0} {
                set sx [expr {[dui::platform::rescale_x 10000000] / 10000000.0}]
                set sy [expr {[dui::platform::rescale_y 10000000] / 10000000.0}]
                set ix [expr {$x - $glass_margin($img) / $sx + 0.01}]
                set iy [expr {$y - $glass_margin($img) / $sy + 0.01}]
            }
            if {[catch { dui add canvas_item image $page $ix $iy \
                    -image $img -anchor nw -tags ${tag}_img } err]} {
                catch { msg -NOTICE "DrinkMenu: glass image item refused for $tag on $page ($err); using the flat $L(card_fill) fill" }
                set img ""
            }
        }
        if {$img eq ""} {
            # Pass 12 A2: card_fill / card_edge are derived from the page
            # background (see _apply_palette), not borrowed from the skin's
            # glass tokens, so every card -- tiles, detail hero, totals,
            # chips card, editor preview and vessel tiles -- takes the same
            # step above the page through this one helper.
            rounded_rect $page $x $y $x2 $y2 $r \
                -fill $L(card_fill) -outline $L(card_fill) -width $L(line_w) -tags ${tag}_img
            _theme_item $page ${tag}_img fill card_fill
            _theme_item $page ${tag}_img outline card_fill
            # Pass 26 (v0.13.3): the edge polygon exists ONLY on this flat
            # fallback path, where there is no photo to bake it into. A
            # card that got a photo carries its own rim (glass_photo), and
            # drawing a second smoothed polygon over it was exactly what
            # notched the corners -- a `-smooth 1` corner is not a
            # circular arc, so the two shapes disagreed and a wedge of
            # page showed between them.
            rounded_rect $page $x $y $x2 $y2 $r \
                -fill {} -outline $L(card_edge) -width $L(line_w) -tags ${tag}_body
            _theme_item $page ${tag}_body outline card_edge
            lappend items ${tag}_body
        }
        # Pass 41 (tonal): the <tag>_spec top highlight line and the
        # <tag>_shade bottom line are gone. With the rim and the glow band
        # they stacked into a bevel; a card is now its photo (or the flat
        # fallback pair) and nothing else.
        return $items
    }

    # A bottom-bar (or header) button: the dbutton dui paints -- fill, the
    # edge (a faint hairline on a ghost button, the fill itself on a gold
    # one) and the pass's radius. Pass 41 (tonal) removed the mock's
    # `inset 0 1px 0 var(--glass-hi)` top highlight line (<tag>_hi) this
    # proc used to add: on the tablet it read as a plastic bevel, brightest
    # on the gold Done button. `kind` is btn (ghost) or primary; `args` is
    # passed to the dbutton untouched.
    proc bar_button {page tag x1 y1 x2 y2 kind args} {
        variable L
        set style [expr {$kind eq "primary" ? "dm_btn_primary" : "dm_btn"}]
        set labels -lbl
        if {[lsearch -exact $args -label1] >= 0} { set labels {-lbl -lbl1} }
        # Pass 43: the face is drawn art under an invisible dbutton (see
        # the dm_btn aspects). The art carries the dbutton's literal
        # "<tag>*" group tag, so every show / hide and every st:hidden the
        # page-show path writes reaches it, and the -command is wrapped so
        # the tap flashes the art before it runs.
        set initial normal
        if {[lsearch -exact $args -initial_state] >= 0} { set initial hidden }
        set ci [lsearch -exact $args -command]
        if {$ci >= 0} {
            set cmd [lindex $args [expr {$ci + 1}]]
            lset args [expr {$ci + 1}] [list ::plugins::DrinkMenu::_btn_tap $page $tag $cmd]
        }
        # Pass 48: an optional icon photo (-icon, -icon_pos {fx fy} in
        # button fractions) drawn between the art and the tap rect, under
        # the group tag so show / hide reach it; the label is usually
        # moved aside with -label_pos. Swapped later by _set_image on
        # <tag>_icon. Both options are stripped before dui sees them.
        set icon "" ; set icon_pos {0.25 0.5}
        set ii [lsearch -exact $args -icon]
        if {$ii >= 0} {
            set icon [lindex $args [expr {$ii + 1}]]
            set args [lreplace $args $ii [expr {$ii + 1}]]
        }
        set ip [lsearch -exact $args -icon_pos]
        if {$ip >= 0} {
            set icon_pos [lindex $args [expr {$ip + 1}]]
            set args [lreplace $args $ip [expr {$ip + 1}]]
        }
        if {$kind eq "primary"} {
            shape_make $page ${tag}_art $x1 $y1 $x2 $y2 $L(btn_radius) pill_on_fill pill_on_edge \
                -tags [list ${tag}*] -initial $initial -kind primary \
                -variants {{btn_primary_press btn_primary_press}}
        } elseif {$kind eq "danger"} {
            # Pass 48: the destructive tone (the editor's Delete).
            shape_make $page ${tag}_art $x1 $y1 $x2 $y2 $L(btn_radius) btn_danger_fill btn_danger_edge \
                -tags [list ${tag}*] -initial $initial -kind danger \
                -variants {{btn_danger_press btn_danger_press}}
        } else {
            shape_make $page ${tag}_art $x1 $y1 $x2 $y2 $L(btn_radius) btn_fill btn_edge \
                -tags [list ${tag}*] -initial $initial -kind btn \
                -variants {{btn_press btn_edge}}
        }
        if {$icon ne ""} {
            lassign $icon_pos fx fy
            dui add canvas_item image $page [expr {$x1 + ($x2 - $x1) * $fx}] [expr {$y1 + ($y2 - $y1) * $fy}] \
                -image $icon -anchor center -tags [list ${tag}_icon ${tag}*] \
                {*}[expr {$initial eq "hidden" ? [list -initial_state hidden] : {}}]
        }
        dui add dbutton $page $x1 $y1 $x2 $y2 -tags $tag -style $style {*}$args
        _theme_btn $page $tag $kind $labels
        return $tag
    }

    # Two-way segmented control drawn as ONE capsule (Pass 12 item A3).
    # The mock draws ml|oz and the shot toggle as a single pill with an
    # outline around both halves, the active half filled crema and a
    # hairline between the halves; v0.7.1 drew two separate rounded
    # rects with a gap. The two dbuttons stay (same tags, same commands)
    # but lose their -style, so they are invisible tap targets over the
    # drawn shapes -- exactly how the tile tap target already works.
    #
    # Items, x1..xm the left half and xm..x2 the right half:
    #   <tag>_cap    capsule body + outline, always visible
    #   <tag>_onl    active fill of the left half (rounded outer end,
    #                square inner end); shown when the left half is on
    #   <tag>_onr    the same for the right half
    #   <tag>_div    the hairline between the halves, drawn over the fill
    #   <tag>_lbl0 / <tag>_lbl1  the two labels (recolored, never
    #                relabeled, so no dui relabel path is involved)
    # _style_segment switches which half is filled.
    #
    # The shapes are explicit stadium polygons, NOT rounded_rect: a
    # -smooth 1 polygon renders about half its control-point radius and
    # _rr_points clamps the radius at half the height, so a smoothed
    # rounded rect can never reach a true half-height cap. A polygon with
    # the arc walked out in `caps` segments per end is exact, needs no
    # smoothing, and gives the half-capsules their square inner end for
    # free.
    # ---- Pass 43 (v1.13.0): anti-aliased pills, capsules, badges, chips
    #      and buttons ----
    #
    # The same route the cards took in Pass 42, for every other rounded
    # control: a shape is TWO cap photos (its left and right r columns,
    # PNG with alpha, anti-aliased arcs and the hairline ring painted by
    # _shape_rows) plus a flat body -- a rect and two 1 px hairlines --
    # between them. Only straight edges are drawn by the canvas, which it
    # does perfectly; every arc is a photo. A cap pair is keyed by
    # (h, r, fill, edge) in PHYSICAL px and shared: the twelve badges use
    # one pair, every ghost button another, so a page costs a dozen tiny
    # photos. Widths are free (the body stretches), so shape_move can
    # re-lay a chip at refresh without touching a photo, and every state
    # a shape can show (selected, pressed) is a pair made at SETUP through
    # -variants, so shape_paint / shape_flash only ever swap images.
    #
    # Items, each leading with its own role tag (dui wants a unique first
    # tag per item) and carrying the shape's main tag second (so exact-tag
    # show / hide lists keep working): <tag>_bd rect, <tag>_ht / <tag>_hb
    # hairlines, <tag>_cl / <tag>_cr cap images. The body overlaps
    # each cap by one column and the hairlines cover the top and bottom
    # rows whichever way Tk closes a rect, so there is never a seam.
    # Placement uses the same +0.01 trick as the cards: a virtual offset
    # of k / scale lands on exactly floor(x * scale) +- k physical px.
    #
    # A platform that refuses the cap PNGs gets the v1.12.0 polygon
    # (_capsule_points / rounded_rect) under the same main tag; the state
    # painters then itemconfigure that polygon instead.
    variable shapes
    array set shapes {}
    variable cap_photos
    array set cap_photos {}
    variable cap_n 0
    variable cap_bytes 0

    proc _sx {} { return [expr {[dui::platform::rescale_x 10000000] / 10000000.0}] }
    proc _sy {} { return [expr {[dui::platform::rescale_y 10000000] / 10000000.0}] }

    # The RGBA rows of columns [x0, x1] of a flat w x h rounded rect of
    # radius r: coverage from the signed distance (1 px anti-aliasing),
    # the hairline as the 1 px ring inside the edge, transparent outside.
    # Pure.
    proc _shape_rows {w h r fill edge x0 x1} {
        lassign [_hex_rgb $fill] fr fg fb
        lassign [_hex_rgb $edge] er eg eb
        set rr [expr {double($r)}]
        if {$rr * 2.0 > $w} { set rr [expr {$w / 2.0}] }
        if {$rr * 2.0 > $h} { set rr [expr {$h / 2.0}] }
        set hw [expr {$w / 2.0}]
        set hh [expr {$h / 2.0}]
        set rows {}
        for {set y 0} {$y < $h} {incr y} {
            set py [expr {$y + 0.5 - $hh}]
            set qy [expr {abs($py) - ($hh - $rr)}]
            set my [expr {$qy > 0.0 ? $qy : 0.0}]
            set row ""
            for {set x $x0} {$x <= $x1} {incr x} {
                set px [expr {$x + 0.5 - $hw}]
                set qx [expr {abs($px) - ($hw - $rr)}]
                set mx [expr {$qx > 0.0 ? $qx : 0.0}]
                set mq [expr {$qx > $qy ? $qx : $qy}]
                set d [expr {sqrt($mx * $mx + $my * $my) + ($mq < 0.0 ? $mq : 0.0) - $rr}]
                set c [expr {0.5 - $d}]
                if {$c > 1.0} { set c 1.0 } elseif {$c < 0.0} { set c 0.0 }
                if {$c <= 0.0} {
                    append row [binary format cccc 0 0 0 0]
                    continue
                }
                set e [expr {-0.5 - $d}]
                if {$e > 1.0} { set e 1.0 } elseif {$e < 0.0} { set e 0.0 }
                set t [expr {($c - $e) / $c}]
                append row [binary format cccc [expr {int($fr + ($er - $fr) * $t + 0.5)}] \
                    [expr {int($fg + ($eg - $fg) * $t + 0.5)}] [expr {int($fb + ($eb - $fb) * $t + 0.5)}] \
                    [expr {int($c * 255.0 + 0.5)}]]
            }
            lappend rows $row
        }
        return $rows
    }

    # The cap pair {left right} for (h, r, fill, edge), physical px, made
    # once and cached; "" when the platform refuses the PNG.
    proc shape_caps {h r fill edge} {
        variable cap_photos
        variable cap_n
        variable cap_bytes
        set key "${h}x${r}|$fill|$edge"
        if {[info exists cap_photos($key)]} { return $cap_photos($key) }
        if {$r < 1 || $h < 2} { set cap_photos($key) "" ; return "" }
        set w [expr {2 * $r + 2}]
        set base "dm_cap_${h}x${r}_[string range $fill 1 end]_[string range $edge 1 end]"
        if {[catch {
            ::image create photo ${base}_l -data [png_encode $r $h \
                [_shape_rows $w $h $r $fill $edge 0 [expr {$r - 1}]]]
            ::image create photo ${base}_r -data [png_encode $r $h \
                [_shape_rows $w $h $r $fill $edge [expr {$w - $r}] [expr {$w - 1}]]]
        } err]} {
            catch { ::image delete ${base}_l }
            catch { ::image delete ${base}_r }
            catch { msg -NOTICE "DrinkMenu: cap photos $key refused ($err); drawing that shape as a polygon" }
            set cap_photos($key) ""
            return ""
        }
        set cap_photos($key) [list ${base}_l ${base}_r]
        incr cap_n 2
        incr cap_bytes [expr {2 * $r * $h * 4}]
        return $cap_photos($key)
    }

    # Virtual coordinates of a shape's five items: left cap x, right cap
    # x, body/hairline x1 and x2, hairline top and bottom y.
    proc _shape_geom {x1 y1 x2 y2 pr ends} {
        set sx [_sx]
        set sy [_sy]
        set hasl [expr {[string first l $ends] >= 0}]
        set hasr [expr {[string first r $ends] >= 0}]
        set lx $x1
        set rx [expr {$x2 - $pr / $sx + 0.01}]
        set bx1 [expr {$hasl ? $x1 + ($pr - 1) / $sx + 0.01 : $x1}]
        set bx2 [expr {$hasr ? $x2 - ($pr - 1) / $sx + 0.01 : $x2 - 1.0 / $sx + 0.01}]
        # Pass 48: `ty` is the top hairline's BOTTOM (one row below y1)
        # and `by` the bottom hairline's TOP (one row above y2). Both
        # hairlines are one-row RECTS (y1..ty and by..y2) and the body
        # runs y1..y2, the cap photos' full height. They were canvas
        # lines: AndroWish anti-aliases a line, so a 1 px line centred
        # on a row straddles two rows at half alpha, and the body rect
        # stopped one row short of the caps -- a dark half-row under
        # every gold shape and a light one under every ghost button
        # (owner, v1.16.1 screenshots). Rect fills are never
        # anti-aliased, so the rows are exact.
        set ty [expr {$y1 + 1.0 / $sy + 0.01}]
        set by [expr {$y2 - 1.0 / $sy + 0.01}]
        return [list $lx $rx $bx1 $bx2 $ty $by]
    }

    # Creates a shape at SETUP. radius is the drawn radius in VIRTUAL
    # units (clamped to a full pill). fill_role / edge_role are palette
    # tokens (L keys). Options: -ends lr|l|r (a half capsule has one cap
    # and a square end), -tags extra tags for every item (a dbutton's
    # "<tag>*" group), -initial hidden, -variants {{fill edge} ...} the
    # other states this shape will show (their pairs are made now), -kind
    # pill|seg|btn|primary|chip (what _press_restore puts back).
    proc shape_make {page tag x1 y1 x2 y2 radius fill_role edge_role args} {
        variable L
        variable shapes
        set ends lr ; set extra {} ; set initial normal ; set variants {} ; set kind chip
        foreach {k v} $args {
            switch -- $k {
                -ends { set ends $v }
                -tags { set extra $v }
                -initial { set initial $v }
                -variants { set variants $v }
                -kind { set kind $v }
            }
        }
        set hasl [expr {[string first l $ends] >= 0}]
        set hasr [expr {[string first r $ends] >= 0}]
        set ph [dui::platform::rescale_y [expr {$y2 - $y1}]]
        set pw [dui::platform::rescale_x [expr {$x2 - $x1}]]
        set pr [dui::platform::rescale_x $radius]
        if {$pr * 2 > $ph} { set pr [expr {$ph / 2}] }
        set need [expr {($hasl ? $pr : 0) + ($hasr ? $pr : 0) + 2}]
        if {$need > $pw} { set pr [expr {($pw - 2) / ($hasl + $hasr)}] }
        set caps [shape_caps $ph $pr $L($fill_role) $L($edge_role)]
        foreach v $variants {
            lassign $v vf ve
            shape_caps $ph $pr $L($vf) $L($ve)
        }
        set iopt [expr {$initial eq "hidden" ? [list -initial_state hidden] : {}}]
        set mode png
        if {$caps eq ""} {
            set mode poly
            if {$pr * 2 >= $ph - 1} {
                dui add canvas_item polygon $page {*}[_capsule_points $x1 $y1 $x2 $y2 $hasl $hasr] \
                    -fill $L($fill_role) -outline $L($edge_role) -width $L(line_w) \
                    -tags [list $tag {*}$extra] {*}$iopt
            } else {
                rounded_rect $page $x1 $y1 $x2 $y2 $radius \
                    -fill $L($fill_role) -outline $L($edge_role) -width $L(line_w) \
                    -tags [list $tag {*}$extra] {*}$iopt
            }
        } else {
            # dui insists the FIRST tag of an item is unique per page
            # (process_tags_and_var, dui.tcl:5355 -- the tablet refused
            # four of five items when they shared it), so each item leads
            # with its role tag and carries the shape's main tag SECOND;
            # `dui item get` finds by any tag (`p:<page>&&<tag>`), so the
            # exact-tag show / hide lists and _ids keep working.
            lassign [_shape_geom $x1 $y1 $x2 $y2 $pr $ends] lx rx bx1 bx2 ty by
            dui add canvas_item rect $page $bx1 $y1 $bx2 $y2 \
                -fill $L($fill_role) -outline {} -width 0 -tags [list ${tag}_bd $tag {*}$extra] {*}$iopt
            dui add canvas_item rect $page $bx1 $y1 $bx2 $ty \
                -fill $L($edge_role) -outline {} -width 0 -tags [list ${tag}_ht $tag {*}$extra] {*}$iopt
            dui add canvas_item rect $page $bx1 $by $bx2 $y2 \
                -fill $L($edge_role) -outline {} -width 0 -tags [list ${tag}_hb $tag {*}$extra] {*}$iopt
            if {$hasl} {
                dui add canvas_item image $page $lx $y1 -image [lindex $caps 0] -anchor nw \
                    -tags [list ${tag}_cl $tag {*}$extra] {*}$iopt
            }
            if {$hasr} {
                dui add canvas_item image $page $rx $y1 -image [lindex $caps 1] -anchor nw \
                    -tags [list ${tag}_cr $tag {*}$extra] {*}$iopt
            }
        }
        set shapes($page,$tag) [dict create mode $mode h $ph r $pr ends $ends \
            fill $fill_role edge $edge_role kind $kind x1 $x1 y1 $y1 x2 $x2 y2 $y2]
        return $tag
    }

    proc _shape_apply {page tag fill edge} {
        variable shapes
        variable debug_timing
        if {![info exists shapes($page,$tag)]} { return }
        set s $shapes($page,$tag)
        set can ""
        catch { set can [dui canvas] }
        if {$can eq ""} { return }
        if {$debug_timing} { t_count item_config }
        if {[dict get $s mode] eq "poly"} {
            foreach id [_ids $page $tag] {
                catch { $can itemconfigure $id -fill $fill -outline $edge }
            }
            return
        }
        foreach id [_ids $page ${tag}_bd] { catch { $can itemconfigure $id -fill $fill } }
        foreach sub {ht hb} {
            foreach id [_ids $page ${tag}_$sub] { catch { $can itemconfigure $id -fill $edge } }
        }
        set caps [shape_caps [dict get $s h] [dict get $s r] $fill $edge]
        if {$caps eq ""} { return }
        if {[string first l [dict get $s ends]] >= 0} {
            foreach id [_ids $page ${tag}_cl] { catch { $can itemconfigure $id -image [lindex $caps 0] } }
        }
        if {[string first r [dict get $s ends]] >= 0} {
            foreach id [_ids $page ${tag}_cr] { catch { $can itemconfigure $id -image [lindex $caps 1] } }
        }
    }

    # The shape's STATE: remembered, so a flash can be undone from it.
    proc shape_paint {page tag fill_role edge_role} {
        variable shapes
        variable L
        if {![info exists shapes($page,$tag)]} { return }
        dict set shapes($page,$tag) fill $fill_role
        dict set shapes($page,$tag) edge $edge_role
        _shape_apply $page $tag $L($fill_role) $L($edge_role)
    }

    # A transient look (the press flash): the state is untouched.
    proc shape_flash {page tag fill_role edge_role} {
        variable L
        _shape_apply $page $tag $L($fill_role) $L($edge_role)
    }

    proc shape_restore {page tag} {
        variable shapes
        variable L
        if {![info exists shapes($page,$tag)]} { return }
        set s $shapes($page,$tag)
        _shape_apply $page $tag $L([dict get $s fill]) $L([dict get $s edge])
    }

    # Re-lays a shape (a refresh moving a chip): coordinates only, the
    # photos never change.
    proc shape_move {page tag x1 y1 x2 y2} {
        variable shapes
        variable debug_timing
        if {![info exists shapes($page,$tag)]} { return }
        set s $shapes($page,$tag)
        dict set shapes($page,$tag) x1 $x1
        dict set shapes($page,$tag) y1 $y1
        dict set shapes($page,$tag) x2 $x2
        dict set shapes($page,$tag) y2 $y2
        set can ""
        catch { set can [dui canvas] }
        if {$can eq ""} { return }
        if {$debug_timing} { t_count coords }
        if {[dict get $s mode] eq "poly"} {
            set hasl [expr {[string first l [dict get $s ends]] >= 0}]
            set hasr [expr {[string first r [dict get $s ends]] >= 0}]
            _move_item $page $tag [_capsule_points $x1 $y1 $x2 $y2 $hasl $hasr]
            return
        }
        lassign [_shape_geom $x1 $y1 $x2 $y2 [dict get $s r] [dict get $s ends]] lx rx bx1 bx2 ty by
        foreach {sub pts} [list bd [list $bx1 $y1 $bx2 $y2] ht [list $bx1 $y1 $bx2 $ty] \
                hb [list $bx1 $by $bx2 $y2] cl [list $lx $y1] cr [list $rx $y1]] {
            if {$sub eq "cl" && [string first l [dict get $s ends]] < 0} { continue }
            if {$sub eq "cr" && [string first r [dict get $s ends]] < 0} { continue }
            foreach id [_ids $page ${tag}_$sub] {
                catch { $can coords $id {*}[_phys_pts $pts] }
            }
        }
    }

    # A bar button's tap: flash its art, then run the button's command.
    # bar_button wraps every -command in this, so the flash is one place.
    proc _btn_tap {page tag cmd} {
        _flash_btn $page $tag
        uplevel #0 $cmd
    }

    proc _flash_btn {page tag} {
        variable shapes
        if {![info exists shapes($page,${tag}_art)]} { return }
        if {[dict get $shapes($page,${tag}_art) kind] eq "primary"} {
            shape_flash $page ${tag}_art btn_primary_press btn_primary_press
        } elseif {[dict get $shapes($page,${tag}_art) kind] eq "danger"} {
            shape_flash $page ${tag}_art btn_danger_press btn_danger_press
        } else {
            shape_flash $page ${tag}_art btn_press btn_edge
        }
        _flash_arm $page ${tag}_art btn
    }

    proc _capsule_points {x1 y1 x2 y2 {round_l 1} {round_r 1}} {
        set pi 3.141592653589793
        set r [expr {($y2 - $y1) / 2.0}]
        set cy [expr {($y1 + $y2) / 2.0}]
        set caps 12
        set pts {}
        if {$round_r} {
            set cxr [expr {$x2 - $r}]
            for {set i 0} {$i <= $caps} {incr i} {
                set a [expr {-$pi / 2.0 + $pi * $i / double($caps)}]
                lappend pts [expr {$cxr + $r * cos($a)}] [expr {$cy + $r * sin($a)}]
            }
        } else {
            lappend pts $x2 $y1 $x2 $y2
        }
        if {$round_l} {
            set cxl [expr {$x1 + $r}]
            for {set i 0} {$i <= $caps} {incr i} {
                set a [expr {$pi / 2.0 + $pi * $i / double($caps)}]
                lappend pts [expr {$cxl + $r * cos($a)}] [expr {$cy + $r * sin($a)}]
            }
        } else {
            lappend pts $x1 $y2 $x1 $y1
        }
        return $pts
    }

    # One tab pill, drawn the way the segmented capsule already is: ONE
    # polygon carrying both the face and its own 1 px edge, plus a label.
    # The tap target is a separate invisible dbutton, added by the caller.
    #
    # Pass 32: this replaces a `dm_pill`-styled dbutton. dui paints a
    # round_outline button with TWO painters -- rounded_rectangle for the
    # fill and rounded_rectangle_outline for the edge (dui.tcl:10118) --
    # and at a pill's radius (half its height) the two disagree: the edge's
    # straight top and bottom runs sat a hair inside the fill's silhouette
    # and ended before its arcs began, which read on the tablet as a wrong
    # horizontal line across the top and bottom of every header pill, with
    # a notch at each arc joint. One polygon has one silhouette, so the
    # edge cannot disagree with it. `_capsule_points` is the same 12-step
    # arc the ml/oz and 1-shot/2-shots capsules are drawn from, and those
    # have always looked right.
    proc pill_shape {page tag x1 y1 x2 y2 label font} {
        variable L
        # Pass 43: the pill is a shape (cap photos + flat body); its off,
        # selected and pressed pairs are made here, at setup.
        shape_make $page ${tag}_cap $x1 $y1 $x2 $y2 $L(pill_radius) pill_off_fill pill_off_edge \
            -kind pill -variants {{pill_on_fill pill_on_edge} {btn_primary_press btn_primary_press}}
        dui add dtext $page [expr {($x1 + $x2) / 2}] [expr {($y1 + $y2) / 2}] \
            -tags ${tag}_lbl -text $label -font $font \
            -fill $L(pill_off_text) -anchor center -justify center
        return
    }

    proc segment_capsule {page tag x1 y1 x2 y2 labels fonts {initial normal}} {
        # initial (Pass 33): "hidden" for a capsule that belongs to a
        # hidden editor mode group; the header capsules keep "normal".
        # The active-half overlays always start hidden either way.
        variable L
        set xm [expr {($x1 + $x2) / 2}]
        # Pass 43: the capsule and its two gold half overlays are shapes
        # (cap photos + flat body); a half has ONE cap and a square end.
        shape_make $page ${tag}_cap $x1 $y1 $x2 $y2 $L(pill_radius) pill_off_fill card_edge \
            -kind seg -initial $initial
        foreach {side hx1 hx2 ends} [list l $x1 $xm l   r $xm $x2 r] {
            shape_make $page ${tag}_on$side $hx1 $y1 $hx2 $y2 $L(pill_radius) seg_on_fill seg_on_fill \
                -ends $ends -kind seg -initial hidden \
                -variants {{seg_press seg_press}}
        }
        # Pass 48: the divider is a one-column rect (a canvas line would
        # be anti-aliased across two columns at half alpha).
        dui add canvas_item rect $page $xm [expr {$y1 + $L(line_w)}] \
            [expr {$xm + 1.0 / [_sx] + 0.01}] [expr {$y2 - $L(line_w)}] \
            -fill $L(card_edge) -outline {} -width 0 -tags ${tag}_div -initial_state $initial
        _theme_item $page ${tag}_div fill card_edge
        set i 0
        foreach lbl $labels font $fonts {
            set cx [expr {$i == 0 ? ($x1 + $xm) / 2 : ($xm + $x2) / 2}]
            dui add dtext $page $cx [expr {($y1 + $y2) / 2}] -tags ${tag}_lbl$i \
                -text $lbl -font $font -fill $L(pill_off_text) -anchor center -justify center \
                -initial_state $initial
            incr i
        }
        return $xm
    }

    # ------------------------------------------------------------------
    #  Cup renderer -- pure geometry (no dui calls; headless-testable)
    # ------------------------------------------------------------------

    # Fits the vessel's design box (bowl + handle + stem/foot) into
    # (x y w h) preserving its aspect, optionally shrunk by the vessel's
    # tile_scale so sizes stay comparable in a grid, centered. Returns:
    #   id cx floor_y rim_y interior_h scale box
    #   profile  {frac half_width ...} in virtual units, floor -> rim
    #   outline  bowl polygon: rim-left down to floor-left, floor-right
    #            up to rim-right (closed by the canvas)
    #   handle   oval bbox {x1 y1 x2 y2} or {} when the vessel has none
    #   stem     stem+foot polygon points or {} for flat-bottomed cups
    proc vessel_geometry {vessel_id x y w h {use_tile_scale 1}} {
        variable vessels
        variable geom_cache
        variable mock_shadow_dy
        # Pure function of the vessel and its design box: the same seven
        # vessels are fitted into the same tile box on every refresh.
        set _ckey "$vessel_id|$x|$y|$w|$h|$use_tile_scale"
        if {[info exists geom_cache($_ckey)]} { return $geom_cache($_ckey) }
        if {![dict exists $vessels $vessel_id]} {
            error "DrinkMenu: unknown vessel '$vessel_id'"
        }
        set v [dict get $vessels $vessel_id]
        set profile [dict get $v profile]
        set height [dict get $v height]
        set has_handle [dict get $v handle]
        set handle_w [dict get $v handle_w]
        set stem {}
        catch { set stem [dict get $v stem] }
        set tile_scale 1.0
        if {$use_tile_scale} {
            catch { set tile_scale [dict get $v tile_scale] }
            if {$tile_scale <= 0} { set tile_scale 1.0 }
        }
        set stem_w 0; set stem_h 0; set foot_w 0; set foot_h 0
        if {[llength $stem] == 4} { lassign $stem stem_w stem_h foot_w foot_h }

        set max_hw 0
        foreach {f hw} $profile {
            if {$hw > $max_hw} { set max_hw $hw }
        }
        set body_half [expr {max(double($max_hw), $foot_w / 2.0)}]
        set design_w [expr {2.0 * $body_half + $handle_w}]
        # Pass 32: the design box RESERVES the shadow's own strip below the
        # floor, the bottom margin the mock's viewBox has and ours did not.
        # Without it a height-bound vessel -- the 300 and 350 ml glasses,
        # and every cup on the detail hero -- fitted its art flush to the
        # bottom of the zone, so cup_shadow_box had nowhere to put the
        # ellipse and clamped it UP, behind the glass, which is what the
        # owner saw. With the strip reserved the ellipse always hangs
        # under the floor and the clamp never binds. The cost is that a
        # height-bound vessel's art is 2 * mock_shadow_dy design units
        # shorter, exactly as in the mock.
        set design_h [expr {double($height) + $stem_h + $foot_h \
            + 2.0 * $mock_shadow_dy}]
        set s [expr {min(double($w) / $design_w, double($h) / $design_h) * $tile_scale}]
        set box_w [expr {$design_w * $s}]
        set box_h [expr {$design_h * $s}]
        set bx [expr {$x + ($w - $box_w) / 2.0}]
        set by [expr {$y + ($h - $box_h) / 2.0}]
        set cx [expr {$bx + $body_half * $s}]
        set rim_y $by
        set interior_h [expr {$height * $s}]
        set floor_y [expr {$by + $interior_h}]

        set vprofile {}
        foreach {f hw} $profile {
            lappend vprofile [expr {double($f)}] [expr {$hw * $s}]
        }

        set geom [dict create id $vessel_id cx $cx floor_y $floor_y rim_y $rim_y \
            interior_h $interior_h scale $s box [list $bx $by $box_w $box_h] \
            profile $vprofile]

        # Outline: left wall rim -> floor, right wall floor -> rim.
        set left {}
        set right {}
        foreach {f hw} $vprofile {
            set py [expr {$floor_y - $f * $interior_h}]
            set left [linsert $left 0 [expr {$cx - $hw}] $py]
            lappend right [expr {$cx + $hw}] $py
        }
        dict set geom outline [concat $left $right]

        # Handle: an oval to the right of the bowl, mid-height; the bowl
        # is drawn over its inner half.
        if {$has_handle && $handle_w > 0} {
            set hw_mid [_half_width_at $geom 0.55]
            set hx1 [expr {$cx + $hw_mid - $handle_w * $s * 0.35}]
            set hx2 [expr {$cx + $max_hw * $s + $handle_w * $s}]
            set hy1 [expr {$floor_y - 0.78 * $interior_h}]
            set hy2 [expr {$floor_y - 0.22 * $interior_h}]
            dict set geom handle [list $hx1 $hy1 $hx2 $hy2]
        } else {
            dict set geom handle {}
        }

        # Stem + foot: one polygon hanging from the bowl floor.
        if {$stem_h > 0 || $foot_h > 0} {
            set sw2 [expr {$stem_w * $s / 2.0}]
            set fw2 [expr {$foot_w * $s / 2.0}]
            set y_stem [expr {$floor_y + $stem_h * $s}]
            set y_foot [expr {$y_stem + $foot_h * $s}]
            dict set geom stem [list \
                [expr {$cx - $sw2}] $floor_y \
                [expr {$cx - $sw2}] $y_stem \
                [expr {$cx - $fw2}] $y_stem \
                [expr {$cx - $fw2}] $y_foot \
                [expr {$cx + $fw2}] $y_foot \
                [expr {$cx + $fw2}] $y_stem \
                [expr {$cx + $sw2}] $y_stem \
                [expr {$cx + $sw2}] $floor_y]
        } else {
            dict set geom stem {}
        }
        set geom_cache($_ckey) $geom
        return $geom
    }

    # Piecewise-linear interior half width at fractional height f.
    proc _half_width_at {geom f} {
        set profile [dict get $geom profile]
        if {$f <= 0.0} { return [lindex $profile 1] }
        if {$f >= 1.0} { return [lindex $profile end] }
        set pf [lindex $profile 0]
        set phw [lindex $profile 1]
        foreach {cf chw} [lrange $profile 2 end] {
            if {$f <= $cf} {
                if {$cf == $pf} { return $chw }
                return [expr {$phw + ($chw - $phw) * ($f - $pf) / ($cf - $pf)}]
            }
            set pf $cf
            set phw $chw
        }
        return $phw
    }

    # Pass 30 -- the mock's shadow ellipse for a fitted vessel, in VIRTUAL
    # units: {x1 y1 x2 y2}, the oval's bbox.
    #
    # The mock (design/DrinkMenu_preview.html, cup()) draws
    #   <ellipse cx=cx cy=bot+3 rx=bw/2+10 ry=3 fill=rgba(0,0,0,.35)>
    # so the ellipse's TOP is exactly the cup's floor and it reaches
    # mock_shadow_dy * 2 units below it, mock_shadow_dx units wider than
    # the floor on each side. The base is the FOOT for a vessel that has
    # one (the coupe): its bottom edge, its half width.
    #
    # Two clamps, both against the cup ZONE the caller reserved (the
    # x y w h handed to draw_cup), and both needed because our design box
    # is the drawing itself while the mock's viewBox carries 8 units of
    # margin under `bot`:
    #
    #  * Vertically: a height-bound vessel (the tall glasses) is fitted to
    #    the full zone height, so its floor IS the zone's bottom edge and
    #    there is no room under it. The ellipse keeps its full height and
    #    slides UP until it ends at the zone's bottom, which leaves the
    #    wings beyond the floor showing as a tight contact shadow. Every
    #    other vessel is fitted with slack under it and gets the mock's
    #    geometry exactly. Letting it hang past the zone instead would put
    #    a tile's shadow within 1.5 units of the name line (the zone ends
    #    226, the name starts 238, xs is 12).
    #  * Horizontally: rx never passes the zone's own edges. It only ever
    #    binds for the straight glasses, whose floor is nearly as wide as
    #    their rim (highball 22 of 25) -- and their fitted box is less than
    #    half the zone wide, so in practice nothing is clipped there
    #    either.
    #
    # Pure function of the geometry dict and the zone, so the headless
    # SHADOW check asserts the same numbers the page draws.
    proc cup_shadow_box {geom zone} {
        variable mock_shadow_dy
        variable mock_shadow_dx
        lassign $zone zx zy zw zh
        set s [dict get $geom scale]
        set cx [dict get $geom cx]
        set base_y [dict get $geom floor_y]
        set half [_half_width_at $geom 0.0]
        set stem [dict get $geom stem]
        if {$stem ne ""} {
            # The foot polygon: its lowest edge, and its own half width.
            set xmin ""
            set xmax ""
            set ymax ""
            foreach {px py} $stem {
                if {$xmin eq "" || $px < $xmin} { set xmin $px }
                if {$xmax eq "" || $px > $xmax} { set xmax $px }
                if {$ymax eq "" || $py > $ymax} { set ymax $py }
            }
            set base_y $ymax
            set half [expr {($xmax - $xmin) / 2.0}]
        }
        # Pass 32: the ellipse's TOP is the cup's floor, always. It used to
        # be the bottom that was pinned and the top derived, so a vessel
        # whose art reached the zone's floor had its whole ellipse pushed
        # UP, behind the glass. vessel_geometry now reserves the strip this
        # needs, so the clamp below is only a safety net -- and it shrinks
        # the ellipse against the zone's floor instead of moving it, with a
        # 2 px floor so it never vanishes entirely.
        set eh [expr {2.0 * $mock_shadow_dy * $s}]
        set top $base_y
        set bot [expr {$top + $eh}]
        set zbot [expr {double($zy) + $zh}]
        if {$bot > $zbot} { set bot $zbot }
        if {$bot < $top + 2.0} { set bot [expr {$top + 2.0}] }
        set rx [expr {$half + $mock_shadow_dx * $s}]
        set room [expr {min($cx - double($zx), double($zx) + $zw - $cx)}]
        if {$rx > $room} { set rx $room }
        if {$rx < 0.0} { set rx 0.0 }
        return [list [expr {$cx - $rx}] $top [expr {$cx + $rx}] $bot]
    }

    # The palette role for the shadow of a cup drawn on a `surface` (a mock
    # glass family, see mock_glass_kinds), with the card-fill variant as
    # the fallback for anything else.
    proc cup_shadow_role {surface} {
        variable L
        if {$surface ne "" && [info exists L(cup_shadow_$surface)]} {
            return cup_shadow_$surface
        }
        return cup_shadow
    }

    # The share of a vessel's design width that the BOWL takes:
    #   2*body_half / design_w, exactly as vessel_geometry derives them.
    # 1.0 for a handle-less vessel. Pure function of presets.tcl.
    proc vessel_bowl_frac {vessel_id} {
        variable vessels
        if {![dict exists $vessels $vessel_id]} { return 1.0 }
        set v [dict get $vessels $vessel_id]
        set handle_w [dict get $v handle_w]
        set max_hw 0
        foreach {f hw} [dict get $v profile] {
            if {$hw > $max_hw} { set max_hw $hw }
        }
        set foot_w 0
        set stem {}
        catch { set stem [dict get $v stem] }
        if {[llength $stem] == 4} { set foot_w [lindex $stem 2] }
        set body_half [expr {max(double($max_hw), $foot_w / 2.0)}]
        set design_w [expr {2.0 * $body_half + $handle_w}]
        if {$design_w <= 0.0} { return 1.0 }
        return [expr {2.0 * $body_half / $design_w}]
    }

    # Pass 18 -- the detail hero cup box, PER VESSEL. Owner decision: the
    # layer labels may overlap the cup's handle.
    #
    # v0.10.3 fitted bowl + handle into det_cup_x1..det_cup_x2, so a
    # handled cup paid for its handle out of the bowl. Here the BOWL is
    # what has to end md before the label column, so the box handed to
    # vessel_geometry is widened to base_w / bowl_frac (floored, so the
    # fitted bowl can only come in at or under base_w). The fit is
    # width-bound for every handled vessel, so the bowl's right edge
    # lands where the WHOLE cup's right edge landed in v0.10.3 and only
    # the handle protrudes -- into the md leader gap and under the first
    # letters of the labels, which are drawn after it (setup order:
    # handle -> leaders -> labels, so the text is on top).
    #
    # bowl_frac is 1.0 for handle-less vessels, so their box, their fit
    # and their centering are byte-identical to v0.10.3. The y range is
    # untouched, so the tall glasses stay height-bound. Centering keeps
    # the bowl inside base_w for any vessel with bowl_frac >= 0.5 (ours
    # are all >= 0.80); a height-bound handled vessel would simply sit
    # slightly right of the bowl-flush position, still clear of the
    # label column.
    #
    # Returns {x y w h} in virtual units, for draw_cup / cups(<tag>).
    proc hero_cup_box {vessel_id} {
        variable L
        set x $L(det_cup_x1)
        set y $L(det_cup_y1)
        set w [expr {$L(det_cup_x2) - $L(det_cup_x1)}]
        set h [expr {$L(det_cup_y2) - $L(det_cup_y1)}]
        set frac [vessel_bowl_frac $vessel_id]
        if {$frac > 0.0 && $frac < 1.0} {
            set w [expr {int($w / $frac)}]
        }
        return [list $x $y $w $h]
    }

    # One straight-edged polygon for the slice of the interior between
    # fractional heights f0 and f1, with profile breakpoints inserted.
    proc _slice_polygon {geom f0 f1} {
        set cx [dict get $geom cx]
        set floor_y [dict get $geom floor_y]
        set ih [dict get $geom interior_h]
        set fracs [list $f0]
        foreach {bf bhw} [dict get $geom profile] {
            if {$bf > $f0 && $bf < $f1} { lappend fracs $bf }
        }
        lappend fracs $f1
        set left {}
        set right {}
        foreach f $fracs {
            set hw [_half_width_at $geom $f]
            set py [expr {$floor_y - $f * $ih}]
            # left wall collected top -> bottom, right wall bottom -> top
            set left [linsert $left 0 [expr {$cx - $hw}] $py]
            lappend right [expr {$cx + $hw}] $py
        }
        return [concat $left $right]
    }

    # Layers -> polygons. Returns a dict:
    #   polys     list of {tag pts color ingredient ml}, bottom -> top
    #   raw_spans list of {f0 f1} before the minimum-height rule
    #   spans     list of {f0 f1} actually drawn
    #   fill_frac total_ml / capacity, clamped to 1.0
    #   overflow  1 when total_ml > capacity
    proc layer_polygons {geom layers capacity {cdefs {}}} {
        # cdefs (Pass 33): the drink's own custom_ings dict, the colour
        # fallback for c<N> layer ids.
        variable ingredients
        variable L
        set min_h 6
        catch { if {[info exists L(layer_min_h)]} { set min_h $L(layer_min_h) } }
        set ih [dict get $geom interior_h]
        set min_frac [expr {$ih > 0 ? double($min_h) / $ih : 0.0}]
        set cap [expr {double($capacity)}]
        if {$cap <= 0} { set cap 1.0 }

        set total 0.0
        foreach {ing ml} $layers { set total [expr {$total + $ml}] }
        set overflow [expr {$total > $cap ? 1 : 0}]

        # Raw cumulative spans, clamped at the rim.
        set raw_spans {}
        set f 0.0
        foreach {ing ml} $layers {
            set f0 [expr {min($f, 1.0)}]
            set f1 [expr {min($f + double($ml) / $cap, 1.0)}]
            lappend raw_spans [list $f0 $f1]
            set f [expr {$f + double($ml) / $cap}]
        }

        # Minimum visible height: a real layer never collapses below
        # min_frac; later layers shift up; the stack is compressed back
        # under the rim if the shifts overshoot.
        set spans {}
        set f 0.0
        set i 0
        foreach {ing ml} $layers {
            lassign [lindex $raw_spans $i] rf0 rf1
            set span [expr {$rf1 - $rf0}]
            if {$ml > 0 && $span < $min_frac} { set span $min_frac }
            set f0 $f
            set f1 [expr {$f0 + $span}]
            lappend spans [list $f0 $f1]
            set f $f1
            incr i
        }
        if {$f > 1.0 && $f > 0} {
            set k [expr {1.0 / $f}]
            set fixed {}
            foreach sp $spans {
                lassign $sp f0 f1
                lappend fixed [list [expr {$f0 * $k}] [expr {$f1 * $k}]]
            }
            set spans $fixed
        }

        set polys {}
        set i 0
        foreach {ing ml} $layers {
            lassign [lindex $spans $i] f0 f1
            set color "#888888"
            if {[dict exists $ingredients $ing color]} {
                set color [dict get $ingredients $ing color]
            } elseif {[dict exists $cdefs $ing color]} {
                set color [dict get $cdefs $ing color]
            }
            lappend polys [list layer$i [_slice_polygon $geom $f0 $f1] $color $ing $ml]
            incr i
        }
        return [dict create polys $polys raw_spans $raw_spans spans $spans \
            fill_frac [expr {min($total / $cap, 1.0)}] overflow $overflow]
    }

    # ------------------------------------------------------------------
    #  Cup renderer -- canvas side
    # ------------------------------------------------------------------

    # Virtual -> physical for raw canvas coords (the framework does the
    # same in dui::page::calc_x/calc_y for fpdialog pages).
    proc _phys_pts {pts} {
        set out {}
        set i 0
        foreach c $pts {
            if {$i % 2 == 0} {
                lappend out [dui::platform::rescale_x $c]
            } else {
                lappend out [dui::platform::rescale_y $c]
            }
            incr i
        }
        return $out
    }

    # ------------------------------------------------------------------
    #  Small raw-canvas helpers (exact tags only).
    #
    #  Pass 9: every one of these used to go through `dui item
    #  get/config/show/hide`, and each of those resolves the tag again
    #  with `$can find withtag "p:<page>&&<tag>"` and (for show/hide with
    #  -initial) re-enters `dui item config` for the initial-state tag.
    #  A 12-tile menu refresh made ~540 such calls and measured ~590 ms
    #  on the tablet. The items are created once at page setup and never
    #  destroyed, so their canvas ids are stable: resolve each tag once,
    #  cache the ids, and drive the canvas directly afterwards.
    # ------------------------------------------------------------------

    # Canvas ids for one exact tag on one page, resolved once. A tag that
    # matches nothing is NOT cached, so a later lookup can still find it
    # (and dui keeps logging its own DEBUG line for a real miss).
    proc _ids {page tag} {
        variable item_cache
        if {[info exists item_cache($page,$tag)]} { return $item_cache($page,$tag) }
        variable debug_timing
        if {$debug_timing} { t_count item_get }
        set ids {}
        catch { set ids [dui item get $page $tag] }
        if {$ids ne ""} { set item_cache($page,$tag) $ids }
        return $ids
    }

    proc _page_is_current {page} {
        set cur ""
        catch { set cur [dui page current] }
        return [expr {$cur eq $page}]
    }

    # Raw-canvas replacement for `dui item show|hide <tag> -initial 1`.
    # Writes the live -state only while the page is the one on screen --
    # exactly what dui's own -check_page default does, and what keeps a
    # refresh during setup from painting items over another page -- AND
    # keeps the "st:hidden" initial-state tag in sync, which is what the
    # next page show reads (the dui page-show flash trap). Tags whose
    # visibility has not changed since the last write are skipped.
    proc _set_vis {page tags on} {
        variable vis_cache
        variable debug_timing
        set on [expr {$on ? 1 : 0}]
        set can ""
        catch { set can [dui canvas] }
        if {$can eq ""} { return }
        set live [expr {[_page_is_current $page] ? 1 : 0}]
        set state [expr {$on ? "normal" : "hidden"}]
        set stamp "$on|$live"
        foreach t $tags {
            if {[info exists vis_cache($page,$t)] && $vis_cache($page,$t) eq $stamp} { continue }
            set ids [_ids $page $t]
            if {$ids eq ""} { continue }
            if {$debug_timing} { t_count show_hide }
            foreach id $ids {
                if {$live} { catch { $can itemconfigure $id -state $state } }
                if {$on} {
                    catch { $can dtag $id st:hidden }
                } else {
                    catch { $can addtag st:hidden withtag $id }
                }
            }
            set vis_cache($page,$t) $stamp
        }
    }

    proc _move_item {page tag pts} {
        variable debug_timing
        if {$debug_timing} { t_count coords }
        set id [lindex [_ids $page $tag] 0]
        if {$id ne ""} { [dui canvas] coords $id {*}[_phys_pts $pts] }
    }
    proc _set_text {page tag text} {
        variable debug_timing
        variable text_cache
        if {[info exists text_cache($page,$tag)] && $text_cache($page,$tag) eq $text} { return }
        if {$debug_timing} { t_count item_config }
        set ids [_ids $page $tag]
        if {$ids eq ""} { return }
        set can ""
        catch { set can [dui canvas] }
        if {$can eq ""} { return }
        foreach id $ids { catch { $can itemconfigure $id -text $text } }
        set text_cache($page,$tag) $text
    }
    # Same shape as _set_text for the ONE property a text item can also
    # change at refresh time: its font (Pass 15, the tile-name fit rule).
    # Writing the font of an unchanged item is skipped, so the normal
    # case -- every name fits at the primary font -- costs nothing after
    # the first paint.
    proc _set_font {page tag font} {
        variable debug_timing
        variable font_cache
        if {[info exists font_cache($page,$tag)] && $font_cache($page,$tag) eq $font} { return }
        if {$debug_timing} { t_count item_config }
        set ids [_ids $page $tag]
        if {$ids eq ""} { return }
        set can ""
        catch { set can [dui canvas] }
        if {$can eq ""} { return }
        foreach id $ids { catch { $can itemconfigure $id -font $font } }
        set font_cache($page,$tag) $font
    }
    # Same shape again for the one COLOUR a pooled item changes at refresh
    # time: the tile star's on/off face (Pass 21). Since Pass 22 the star
    # is a polygon, so a face is a fill AND an outline -- an empty fill
    # with a visible outline is the "not a favorite" state -- and both are
    # written in one itemconfigure through the cached ids, never a
    # per-item dui call. The palette itself is still applied by _retheme
    # through the `themed` list; this is for the items whose colour
    # follows DATA, so they are deliberately not registered there.
    # _apply_palette drops this cache with the others
    # (invalidate_visibility), so a palette change always repaints.
    proc _set_fill {page tag fill outline} {
        variable debug_timing
        variable fill_cache
        set face "$fill|$outline"
        if {[info exists fill_cache($page,$tag)] && $fill_cache($page,$tag) eq $face} { return }
        if {$debug_timing} { t_count item_config }
        set ids [_ids $page $tag]
        if {$ids eq ""} { return }
        set can ""
        catch { set can [dui canvas] }
        if {$can eq ""} { return }
        foreach id $ids { catch { $can itemconfigure $id -fill $fill -outline $outline } }
        set fill_cache($page,$tag) $face
    }
    proc _show_tags {page tags on} {
        _set_vis $page $tags $on
    }

    # Geometry + layer result for a pooled cup and a drink.
    # ---- Pass 44 (v1.14.0): anti-aliased cup strokes and a soft cup shadow ----
    #
    # The cups were the last stair-stepped thing on screen: the bowl's
    # slanted sides, the handle oval, the stem and the flat shadow oval
    # were canvas polygons and ovals. Now every cup carries two PHOTOS
    # (PNG with alpha, the Pass 42/43 route): <tag>_fg, the ink stroke --
    # the bowl outline, the stem outline and the handle ring, each a
    # 2 px anti-aliased line from the signed distance to the path -- laid
    # OVER the flat layer polygons (whose own edges lie under the stroke),
    # and <tag>_shb, a soft black shadow ellipse laid UNDER them. The
    # polygons stay: the layers and the interior are flat fills, and the
    # old shadow oval, handle oval and stroke polygon remain in the pool,
    # hidden, as the fallback for a device that refuses the PNGs.
    #
    # A sprite pair depends on the vessel and the cup ZONE's physical size
    # only, never on the drink, so it is keyed "<vessel>|<zw>x<zh>|<tile
    # scale>" and shared: the twelve tiles use one pair per vessel. For
    # that to be pixel-exact, _cup_render now computes the geometry with
    # the zone at (0, 0), rescales it, and OFFSETS it by the zone's own
    # rescaled origin -- so a tile's polygons and its sprite agree to the
    # pixel whatever the tile's absolute position truncates to. Sprites
    # are painted lazily on first use (a vessel's tile pair on the first
    # refresh that shows it, the hero / preview pair when a vessel is
    # first viewed) and cached for the session.
    variable cup_sprite_cache
    array set cup_sprite_cache {}
    variable cup_sprite_ok 1
    variable cup_n 0
    variable cup_bytes 0
    variable cup_ms 0
    variable cup_logged 0
    # The soft cup shadow: black at this alpha under the floor, fading to
    # nothing 40% past the flat ellipse's own edge (the mock's .35; the
    # v1.11.0 flat oval had to drop to .15 because it had no edge to fade).
    variable mock_cup_shadow_alpha 0.30

    proc _offset_pts {pts ox oy} {
        if {$pts eq ""} { return "" }
        set out {}
        set i 0
        foreach c $pts {
            lappend out [expr {$c + ($i % 2 == 0 ? $ox : $oy)}]
            incr i
        }
        return $out
    }

    # The cup's geometry with its zone at (0, 0): what the sprite is
    # painted from and what _cup_render offsets.
    proc _cup_calc_rel {tag drink} {
        variable vessels
        variable cups
        set c $cups($tag)
        set vessel [dict get $drink vessel]
        set geom [vessel_geometry $vessel 0 0 [dict get $c w] [dict get $c h] [dict get $c tile_scale]]
        set cap [dict get $vessels $vessel capacity]
        set cdefs {}
        catch { set cdefs [dict get $drink custom_ings] }
        set res [layer_polygons $geom [dict get $drink layers] $cap $cdefs]
        return [list $geom $res]
    }

    proc _pt_in_poly {x y pts} {
        set n [expr {[llength $pts] / 2}]
        set inside 0
        set j [expr {$n - 1}]
        for {set i 0} {$i < $n} {incr i} {
            set xi [lindex $pts [expr {2 * $i}]]
            set yi [lindex $pts [expr {2 * $i + 1}]]
            set xj [lindex $pts [expr {2 * $j}]]
            set yj [lindex $pts [expr {2 * $j + 1}]]
            if {($yi > $y) != ($yj > $y)} {
                set xc [expr {$xj + ($y - $yj) * ($xi - $xj) / ($yi - $yj)}]
                if {$x < $xc} { set inside [expr {!$inside}] }
            }
            set j $i
        }
        return $inside
    }

    # Anti-aliased stroke coverage of one segment into cov(x,y) (max):
    # walk the segment a pixel at a time and score the (2 hw + 3)^2
    # window round each step by the exact distance to the segment.
    proc _cup_stroke_seg {covname ax ay bx by hw w h} {
        upvar 1 $covname cov
        set dx [expr {$bx - $ax}]
        set dy [expr {$by - $ay}]
        set len [expr {sqrt($dx * $dx + $dy * $dy)}]
        set len2 [expr {$len * $len}]
        if {$len2 < 1e-9} { set len2 1e-9 }
        set win [expr {int(ceil($hw)) + 1}]
        set steps [expr {int(ceil($len))}]
        if {$steps < 1} { set steps 1 }
        for {set s 0} {$s <= $steps} {incr s} {
            set t [expr {double($s) / $steps}]
            set px [expr {$ax + $dx * $t}]
            set py [expr {$ay + $dy * $t}]
            set ix0 [expr {int(floor($px)) - $win}]
            set iy0 [expr {int(floor($py)) - $win}]
            for {set iy $iy0} {$iy <= $iy0 + 2 * $win} {incr iy} {
                if {$iy < 0 || $iy >= $h} { continue }
                for {set ix $ix0} {$ix <= $ix0 + 2 * $win} {incr ix} {
                    if {$ix < 0 || $ix >= $w} { continue }
                    set cxp [expr {$ix + 0.5}]
                    set cyp [expr {$iy + 0.5}]
                    set u [expr {(($cxp - $ax) * $dx + ($cyp - $ay) * $dy) / $len2}]
                    if {$u < 0.0} { set u 0.0 } elseif {$u > 1.0} { set u 1.0 }
                    set qx [expr {$ax + $u * $dx}]
                    set qy [expr {$ay + $u * $dy}]
                    set d [expr {sqrt(($cxp - $qx) * ($cxp - $qx) + ($cyp - $qy) * ($cyp - $qy))}]
                    set c [expr {$hw + 0.5 - $d}]
                    if {$c <= 0.0} { continue }
                    if {$c > 1.0} { set c 1.0 }
                    if {![info exists cov($ix,$iy)] || $cov($ix,$iy) < $c} { set cov($ix,$iy) $c }
                }
            }
        }
    }

    # A closed polygon's stroke (points in sprite coordinates).
    proc _cup_stroke_poly {covname pts hw w h} {
        upvar 1 $covname cov
        set n [expr {[llength $pts] / 2}]
        for {set i 0} {$i < $n} {incr i} {
            set j [expr {($i + 1) % $n}]
            _cup_stroke_seg cov [lindex $pts [expr {2 * $i}]] [lindex $pts [expr {2 * $i + 1}]] \
                [lindex $pts [expr {2 * $j}]] [lindex $pts [expr {2 * $j + 1}]] $hw $w $h
        }
    }

    # The handle ring: the ellipse of its box, stroked hw either side
    # (distance to the ellipse by the first-order rho / |grad rho|), and
    # CLIPPED to outside the bowl outline, where the canvas oval used to
    # hide behind the interior polygon.
    proc _cup_ring_cov {covname handle hw outline x0 y0 w h} {
        upvar 1 $covname cov
        lassign $handle hx1 hy1 hx2 hy2
        set a [expr {($hx2 - $hx1) / 2.0}]
        set b [expr {($hy2 - $hy1) / 2.0}]
        if {$a < 1.0 || $b < 1.0} { return }
        set cx [expr {($hx1 + $hx2) / 2.0 - $x0}]
        set cy [expr {($hy1 + $hy2) / 2.0 - $y0}]
        set win [expr {int(ceil($hw)) + 1}]
        for {set iy [expr {int(floor($cy - $b)) - $win}]} {$iy <= int(ceil($cy + $b)) + $win} {incr iy} {
            if {$iy < 0 || $iy >= $h} { continue }
            for {set ix [expr {int(floor($cx - $a)) - $win}]} {$ix <= int(ceil($cx + $a)) + $win} {incr ix} {
                if {$ix < 0 || $ix >= $w} { continue }
                set pxc [expr {$ix + 0.5}]
                set pyc [expr {$iy + 0.5}]
                set nx [expr {($pxc - $cx) / $a}]
                set ny [expr {($pyc - $cy) / $b}]
                set rho [expr {sqrt($nx * $nx + $ny * $ny)}]
                if {$rho < 1e-6} { continue }
                set g [expr {sqrt($nx * $nx / ($a * $a) + $ny * $ny / ($b * $b))}]
                set d [expr {abs(($rho - 1.0) * $rho / $g)}]
                set c [expr {$hw + 0.5 - $d}]
                if {$c <= 0.0} { continue }
                if {$c > 1.0} { set c 1.0 }
                if {[_pt_in_poly [expr {$pxc + $x0}] [expr {$pyc + $y0}] $outline]} { continue }
                if {![info exists cov($ix,$iy)] || $cov($ix,$iy) < $c} { set cov($ix,$iy) $c }
            }
        }
    }

    # The sprite pair for a render's vessel and zone: {fg fx fy bg bx by}
    # (image names and their offsets from the zone origin, physical px),
    # "" when sprites are off (a refused PNG turns them off for the run).
    proc cup_sprites {r} {
        variable L
        variable cup_sprite_cache
        variable cup_sprite_ok
        variable cup_n
        variable cup_bytes
        variable cup_ms
        variable mock_cup_shadow_alpha
        if {!$cup_sprite_ok} { return "" }
        set key [dict get $r skey]
        if {[info exists cup_sprite_cache($key)]} { return $cup_sprite_cache($key) }
        set t0 [clock microseconds]
        set n [expr {[array size cup_sprite_cache] + 1}]
        set fg "dm_cup_fg_$n"
        set bg "dm_cup_bg_$n"
        if {[catch {
            lassign [dict get $r zone] zw zh
            set rel [dict get $r rel]
            set sw [dui::platform::rescale_x $L(stroke_w)]
            if {$sw < 1} { set sw 1 }
            set hw [expr {$sw / 2.0}]
            set outline [dict get $rel outline]
            set stem [dict get $rel stem]
            set handle [dict get $rel handle]
            # ---- the stroke sprite: the ink paths' box, padded ----
            set pad [expr {int(ceil($hw)) + 2}]
            set xs {} ; set ys {}
            foreach pts [list $outline $stem $handle] {
                set i 0
                foreach c $pts { if {$i % 2 == 0} { lappend xs $c } else { lappend ys $c } ; incr i }
            }
            set fx0 [expr {max(0, int(floor([tcl::mathfunc::min {*}$xs])) - $pad)}]
            set fy0 [expr {max(0, int(floor([tcl::mathfunc::min {*}$ys])) - $pad)}]
            set fx1 [expr {min($zw - 1, int(ceil([tcl::mathfunc::max {*}$xs])) + $pad)}]
            set fy1 [expr {min($zh - 1, int(ceil([tcl::mathfunc::max {*}$ys])) + $pad)}]
            set fw [expr {$fx1 - $fx0 + 1}]
            set fh [expr {$fy1 - $fy0 + 1}]
            array set cov {}
            array set rcov {}
            _cup_stroke_poly cov [_offset_pts $outline [expr {-$fx0}] [expr {-$fy0}]] $hw $fw $fh
            if {$stem ne ""} {
                _cup_stroke_poly cov [_offset_pts $stem [expr {-$fx0}] [expr {-$fy0}]] $hw $fw $fh
            }
            # Pass 46: the ring in its own coverage so the part under the
            # detail page's label column (x >= dim_x, hero zone only) can
            # be painted ring_dim -- the Pass 19 arc, now inside the
            # anti-aliased stroke. Where ring and bowl outline meet (left
            # of the column) the bowl's ink wins.
            if {$handle ne ""} { _cup_ring_cov rcov $handle $hw $outline $fx0 $fy0 $fw $fh }
            set dim_x [dict get $r dim_x]
            lassign [_hex_rgb $L(c_ink)] ir ig ib
            lassign [_hex_rgb $L(ring_dim)] dr dg db
            set rows {}
            for {set y 0} {$y < $fh} {incr y} {
                set row {}
                for {set x 0} {$x < $fw} {incr x} {
                    set a 0.0
                    set dim 0
                    if {[info exists cov($x,$y)]} { set a $cov($x,$y) }
                    if {[info exists rcov($x,$y)] && $rcov($x,$y) > $a} {
                        set a $rcov($x,$y)
                        if {$dim_x ne "" && $x + $fx0 >= $dim_x && ![info exists cov($x,$y)]} { set dim 1 }
                    }
                    if {$a > 0.0} {
                        if {$dim} {
                            lappend row $dr $dg $db [expr {int($a * 255.0 + 0.5)}]
                        } else {
                            lappend row $ir $ig $ib [expr {int($a * 255.0 + 0.5)}]
                        }
                    } else {
                        lappend row 0 0 0 0
                    }
                }
                lappend rows [binary format c* $row]
            }
            ::image create photo $fg -data [png_encode $fw $fh $rows]
            # ---- the shadow sprite: a soft ellipse, 40% past the box ----
            lassign [dict get $rel shadow] sx1 sy1 sx2 sy2
            set scx [expr {($sx1 + $sx2) / 2.0}]
            set scy [expr {($sy1 + $sy2) / 2.0}]
            set srx [expr {max(1.0, ($sx2 - $sx1) / 2.0)}]
            set sry [expr {max(1.0, ($sy2 - $sy1) / 2.0)}]
            set bx0 [expr {max(0, int(floor($scx - 1.4 * $srx)))}]
            set by0 [expr {max(0, int(floor($scy - 1.4 * $sry)))}]
            set bx1 [expr {min($zw - 1, int(ceil($scx + 1.4 * $srx)))}]
            set by1 [expr {min($zh - 1, int(ceil($scy + 1.4 * $sry)))}]
            set bw [expr {$bx1 - $bx0 + 1}]
            set bh [expr {$by1 - $by0 + 1}]
            set A $mock_cup_shadow_alpha
            set rows {}
            for {set y 0} {$y < $bh} {incr y} {
                set row {}
                set ny [expr {($by0 + $y + 0.5 - $scy) / $sry}]
                for {set x 0} {$x < $bw} {incr x} {
                    set nx [expr {($bx0 + $x + 0.5 - $scx) / $srx}]
                    set rho [expr {sqrt($nx * $nx + $ny * $ny)}]
                    if {$rho <= 0.6} {
                        set a $A
                    } elseif {$rho >= 1.4} {
                        set a 0.0
                    } else {
                        set a [expr {$A * (1.0 - ($rho - 0.6) / 0.8) ** 2}]
                    }
                    lappend row 0 0 0 [expr {int($a * 255.0 + 0.5)}]
                }
                lappend rows [binary format c* $row]
            }
            ::image create photo $bg -data [png_encode $bw $bh $rows]
        } err]} {
            catch { ::image delete $fg }
            catch { ::image delete $bg }
            set cup_sprite_ok 0
            catch { msg -NOTICE "DrinkMenu: cup sprites refused ($err); cups keep their canvas strokes" }
            return ""
        }
        set cup_ms [expr {$cup_ms + ([clock microseconds] - $t0) / 1000.0}]
        incr cup_n 2
        incr cup_bytes [expr {($fw * $fh + $bw * $bh) * 4}]
        set cup_sprite_cache($key) [list $fg $fx0 $fy0 $bg $bx0 $by0]
        return $cup_sprite_cache($key)
    }

    # One NOTICE line, once, after the first refresh that painted sprites.
    proc cup_log {} {
        variable cup_logged
        variable cup_n
        variable cup_bytes
        variable cup_ms
        if {$cup_logged || $cup_n == 0} { return }
        set cup_logged 1
        catch { msg -NOTICE [format "DrinkMenu: %d cup sprites (%d vessel/size pairs), %.0f KB, painted in %.0f ms" \
            $cup_n [expr {$cup_n / 2}] [expr {$cup_bytes / 1024.0}] $cup_ms] }
    }

    # The image item's virtual coordinate for a sprite offset of `px`
    # physical px from a zone edge at virtual `v`: dui truncates, so
    # v + px / scale + a hair lands on exactly floor(v * scale) + px.
    proc _spx {v px} { return [expr {$v + $px / [_sx] + 0.01}] }
    proc _spy {v px} { return [expr {$v + $px / [_sy] + 0.01}] }

    # ---- Pass 46 (v1.16.0): the last canvas-drawn marks as sprites ----
    #
    # After the cards (42), the shapes (43) and the cups (44) three marks
    # were still stair-stepped canvas items: the tile star (a polygon),
    # the ingredient dots on the detail chips, the editor rows and the
    # palette (ovals), and the hero ring's dim arc (an arc, now baked into
    # the hero's stroke sprite above). Each mark is an image item whose
    # photo is SWAPPED at refresh -- the star between its two faces, a
    # dot between ingredient colours -- through _set_image, cached like
    # _set_fill so an unchanged mark costs nothing. The photos are tiny
    # (a 20 px star, 14 px dots), made once per key and kept for the
    # session; the polygon and the ovals stay in the pool, hidden, as the
    # fallback for a device that refuses the PNGs (mark_ok drops to 0 for
    # the run and one NOTICE says so). star_mode / dot_mode are decided
    # at page setup, so the show / hide tag lists (star_tags, dot_tags)
    # always name the item that exists.
    variable mark_photos
    array set mark_photos {}
    variable mark_ok 1
    variable mark_n 0
    variable mark_bytes 0
    variable mark_ms 0
    variable mark_logged 0
    variable star_mode 0
    variable dot_mode 0
    variable image_cache
    array set image_cache {}

    # Same shape as _set_fill for the one property an image item changes
    # at refresh time: its photo.
    proc _set_image {page tag img} {
        variable debug_timing
        variable image_cache
        if {$img eq ""} { return }
        if {[info exists image_cache($page,$tag)] && $image_cache($page,$tag) eq $img} { return }
        if {$debug_timing} { t_count item_config }
        set ids [_ids $page $tag]
        if {$ids eq ""} { return }
        set can ""
        catch { set can [dui canvas] }
        if {$can eq ""} { return }
        foreach id $ids { catch { $can itemconfigure $id -image $img } }
        set image_cache($page,$tag) $img
    }

    # One photo from RGBA rows, cached by key; "" once the platform has
    # refused one. `rows` is a script evaluated in the caller's frame
    # only on a miss, so a cache hit never paints.
    proc _mark_photo {key name w h rows_script} {
        variable mark_photos
        variable mark_ok
        variable mark_n
        variable mark_bytes
        variable mark_ms
        if {[info exists mark_photos($key)]} { return $mark_photos($key) }
        if {!$mark_ok} { return "" }
        set t0 [clock microseconds]
        if {[catch {
            set rows [uplevel 1 $rows_script]
            ::image create photo $name -data [png_encode $w $h $rows]
        } err]} {
            catch { ::image delete $name }
            set mark_ok 0
            catch { msg -NOTICE "DrinkMenu: mark sprites refused ($err); stars, dots and the dim arc keep their canvas items" }
            return ""
        }
        set mark_ms [expr {$mark_ms + ([clock microseconds] - $t0) / 1000.0}]
        incr mark_n
        incr mark_bytes [expr {$w * $h * 4}]
        set mark_photos($key) $name
        return $name
    }

    # Signed distance from (x, y) to a closed polygon: the distance to the
    # nearest edge, negative inside (_pt_in_poly).
    proc _poly_sdist {x y pts} {
        set n [expr {[llength $pts] / 2}]
        set best 1e9
        for {set i 0} {$i < $n} {incr i} {
            set j [expr {($i + 1) % $n}]
            set ax [lindex $pts [expr {2 * $i}]]
            set ay [lindex $pts [expr {2 * $i + 1}]]
            set bx [lindex $pts [expr {2 * $j}]]
            set by [lindex $pts [expr {2 * $j + 1}]]
            set dx [expr {$bx - $ax}]
            set dy [expr {$by - $ay}]
            set len2 [expr {$dx * $dx + $dy * $dy}]
            if {$len2 < 1e-9} { set len2 1e-9 }
            set u [expr {(($x - $ax) * $dx + ($y - $ay) * $dy) / $len2}]
            if {$u < 0.0} { set u 0.0 } elseif {$u > 1.0} { set u 1.0 }
            set qx [expr {$ax + $u * $dx}]
            set qy [expr {$ay + $u * $dy}]
            set d [expr {sqrt(($x - $qx) * ($x - $qx) + ($y - $qy) * ($y - $qy))}]
            if {$d < $best} { set best $d }
        }
        if {[_pt_in_poly $x $y $pts]} { return [expr {-$best}] }
        return $best
    }

    # The star sprite's physical geometry: {S hw pts} -- the square photo
    # side, the stroke half-width and the star's vertices centred in it
    # (L(tile_star_pts) rescaled, the same vertices the polygon draws).
    proc star_sprite_geom {{scale 1.0}} {
        variable L
        set sx [_sx]
        set sy [_sy]
        set hw [expr {[dui::platform::rescale_x $L(stroke_w)] / 2.0}]
        if {$hw < 0.5} { set hw 0.5 }
        # Pass 48: `scale` enlarges the star (the detail bar's Favorite
        # icon); the stroke stays the tile star's.
        set R [expr {$L(star_r_out) * $sx * $scale + $hw + 1.5}]
        set S [expr {2 * int(ceil($R))}]
        set c [expr {$S / 2.0}]
        set pts {}
        foreach {ox oy} $L(tile_star_pts) {
            lappend pts [expr {$c + $ox * $sx * $scale}] [expr {$c + $oy * $sy * $scale}]
        }
        return [list $S $hw $pts]
    }
    # The Favorite button's star is this much larger than a tile star
    # (24 px on the tablet beside the 20 px "Favorite" label).
    variable fav_star_scale 1.2
    # The editor's "+ Add layer" row: the virtual y its items currently
    # sit at (the refresh moves them by the delta to the row after the
    # last layer).
    variable ed_add_y 0

    # The star's face as a photo: ON is the polygon dilated by the stroke
    # half-width, solid in c_crema (what the canvas draws for a filled
    # polygon with a same-colour outline); OFF is the stroke alone, in
    # c_ink_3, hollow. Coverage from the signed distance, one pixel of
    # anti-aliasing.
    proc star_photo {on {scale 1.0}} {
        set on [expr {$on ? 1 : 0}]
        lassign [star_face $on] fill edge
        set col [expr {$on ? $fill : $edge}]
        lassign [star_sprite_geom $scale] S hw pts
        set face [expr {$on ? "on" : "off"}]
        set key "star|$S|$face|$col|$hw|$scale"
        set name "dm_star_${face}_${S}_[string range $col 1 end]"
        return [_mark_photo $key $name $S $S {
            lassign [_hex_rgb $col] cr cg cb
            set rows {}
            for {set y 0} {$y < $S} {incr y} {
                set row {}
                for {set x 0} {$x < $S} {incr x} {
                    set d [_poly_sdist [expr {$x + 0.5}] [expr {$y + 0.5}] $pts]
                    if {$on} {
                        set a [expr {$hw + 0.5 - $d}]
                    } else {
                        set a [expr {$hw + 0.5 - abs($d)}]
                    }
                    if {$a > 1.0} { set a 1.0 } elseif {$a < 0.0} { set a 0.0 }
                    lappend row $cr $cg $cb [expr {int($a * 255.0 + 0.5)}]
                }
                lappend rows [binary format c* $row]
            }
            set rows
        }]
    }

    # Both faces, painted at menu setup so a star tap never waits; sets
    # star_mode and returns it (0 = the polygon carries the star).
    proc star_sprites {} {
        variable star_mode
        set off [star_photo 0]
        set on [star_photo 1]
        set star_mode [expr {$off ne "" && $on ne "" ? 1 : 0}]
        return $star_mode
    }

    # The star's face for one slot, whichever item carries it.
    proc star_paint {page i on} {
        variable star_mode
        if {$star_mode} {
            _set_image $page tile${i}_starimg [star_photo $on]
            return
        }
        lassign [star_face $on] fill out
        _set_fill $page tile${i}_star $fill $out
    }

    # The visible star item of a slot (the other stays hidden).
    proc star_tags {i} {
        variable star_mode
        if {$star_mode} { return [list tile${i}_starimg] }
        return [list tile${i}_star]
    }

    # The star image's offset from the tile's origin, physical px.
    proc star_sprite_offset {} {
        variable L
        lassign [star_sprite_geom] S hw pts
        return [list [expr {int(round($L(tile_star_cx) * [_sx] - $S / 2.0))}] \
                     [expr {int(round($L(tile_star_cy) * [_sy] - $S / 2.0))}]]
    }

    # An ingredient dot: a full-radius _shape_rows circle, d px across
    # (the oval's physical height), filled in the ingredient's colour with
    # the same 1 px ink edge the oval draws. "" for a colour that is not
    # #rrggbb (the oval takes any Tk colour; the painter cannot).
    proc dot_px {} {
        variable L
        set d [dui::platform::rescale_y $L(det_chip_dot)]
        if {$d < 2} { set d 2 }
        return $d
    }
    proc dot_photo {fill edge} {
        if {![regexp {^#[0-9a-fA-F]{6}$} $fill] || ![regexp {^#[0-9a-fA-F]{6}$} $edge]} { return "" }
        set fill [string tolower $fill]
        set edge [string tolower $edge]
        set d [dot_px]
        set key "dot|$d|$fill|$edge"
        set name "dm_dot_${d}_[string range $fill 1 end]_[string range $edge 1 end]"
        return [_mark_photo $key $name $d $d {
            _shape_rows $d $d [expr {$d / 2.0}] $fill $edge 0 [expr {$d - 1}]
        }]
    }

    # The ink dot, painted at the first setup; sets dot_mode and returns
    # it (0 = the ovals carry the dots).
    proc dot_sprites {} {
        variable L
        variable dot_mode
        set dot_mode [expr {[dot_photo $L(c_ink) $L(c_ink)] ne "" ? 1 : 0}]
        return $dot_mode
    }

    # One dot's colour, whichever item carries it. In sprite mode a
    # colour the painter cannot take (or a refusal mid-run) leaves the
    # previous photo in place rather than showing nothing.
    proc dot_paint {page tag color} {
        variable L
        variable dot_mode
        if {$dot_mode} {
            set img [dot_photo $color $L(c_ink)]
            if {$img ne ""} {
                _set_image $page ${tag}img $img
                return
            }
        }
        set can ""
        catch { set can [dui canvas] }
        if {$can eq ""} { return }
        foreach id [_ids $page $tag] { catch { $can itemconfigure $id -fill $color } }
    }

    # The visible dot item (the other stays hidden).
    proc dot_tags {tag} {
        variable dot_mode
        if {$dot_mode} { return [list ${tag}img] }
        return [list $tag]
    }

    # Creates one dot: the oval (hidden in sprite mode, else the item
    # itself, still hidden until its row is shown) and, in sprite mode,
    # the image item at the oval's top-left. `color` is the initial fill.
    proc draw_dot {page tag x y color} {
        variable L
        variable dot_mode
        set d $L(det_chip_dot)
        dui add canvas_item oval $page $x $y [expr {$x + $d}] [expr {$y + $d}] \
            -fill $color -outline $L(c_ink) -width $L(line_w) -tags $tag -initial_state hidden
        _theme_item $page $tag outline c_ink
        if {$dot_mode} {
            set img [dot_photo $color $L(c_ink)]
            if {$img eq ""} { set img [dot_photo $L(c_ink) $L(c_ink)] }
            dui add canvas_item image $page $x $y -image $img -anchor nw \
                -tags ${tag}img -initial_state hidden
        }
    }

    # One NOTICE line, once, after the first show that painted marks.
    proc mark_log {} {
        variable mark_logged
        variable mark_n
        variable mark_bytes
        variable mark_ms
        if {$mark_logged || $mark_n == 0} { return }
        set mark_logged 1
        catch { msg -NOTICE [format "DrinkMenu: %d mark sprites (star faces, dots), %.0f KB, painted in %.0f ms" \
            $mark_n [expr {$mark_bytes / 1024.0}] $mark_ms] }
    }

    proc _cup_calc {tag drink} {
        variable vessels
        variable cups
        set c $cups($tag)
        set vessel [dict get $drink vessel]
        set geom [vessel_geometry $vessel [dict get $c x] [dict get $c y] \
            [dict get $c w] [dict get $c h] [dict get $c tile_scale]]
        set cap [dict get $vessels $vessel capacity]
        set cdefs {}
        catch { set cdefs [dict get $drink custom_ings] }
        set res [layer_polygons $geom [dict get $drink layers] $cap $cdefs]
        return [list $geom $res]
    }

    # Everything update_cup needs for one (cup box, drink) pair, already
    # converted to PHYSICAL canvas coordinates:
    #   stem     points or {}      handle  bbox or {}
    #   outline  points            layers  list of {points color}
    #   overflow 0/1
    # Cached: the grid re-shows the same drinks in the same boxes on
    # every tab switch and page turn, and the rescale helpers are the
    # only per-vertex work left. invalidate_cache (custom drink changed)
    # and _init_layout (boxes changed) drop it.
    proc _cup_render {tag drink} {
        variable render_cache
        variable cups
        variable L
        set c $cups($tag)
        # Pass 33: the drink's own ingredient defs are part of the key --
        # a recoloured custom layer must never serve a stale polygon.
        set cdefs {}
        catch { set cdefs [dict get $drink custom_ings] }
        set key "[dict get $c x],[dict get $c y],[dict get $c w],[dict get $c h],[dict get $c tile_scale]|[dict get $drink vessel]|[dict get $drink layers]|$cdefs"
        if {[info exists render_cache($key)]} { return $render_cache($key) }
        # Pass 44: geometry with the zone at (0, 0), rescaled, then offset
        # by the zone's own rescaled origin -- so the sprite (painted from
        # the relative geometry, `rel`) and the polygons agree to the
        # pixel whatever the zone's absolute position truncates to.
        lassign [_cup_calc_rel $tag $drink] geom res
        set ox [dui::platform::rescale_x [dict get $c x]]
        set oy [dui::platform::rescale_y [dict get $c y]]
        set zw [dui::platform::rescale_x [dict get $c w]]
        set zh [dui::platform::rescale_y [dict get $c h]]
        set stem_r [dict get $geom stem]
        if {$stem_r ne ""} { set stem_r [_phys_pts $stem_r] }
        set handle_r [dict get $geom handle]
        if {$handle_r ne ""} { set handle_r [_phys_pts $handle_r] }
        set outline_r [_phys_pts [dict get $geom outline]]
        set layers {}
        foreach p [dict get $res polys] {
            lassign $p _ptag pts color
            lappend layers [list [_offset_pts [_phys_pts $pts] $ox $oy] $color]
        }
        # Pass 30: the shadow's bbox, cached with the rest -- the key
        # already carries the cup box, so a box change invalidates it.
        # A hair under 2 physical px would round away to nothing on the
        # tablet, so a shadow that thin grows DOWNWARD (since pass 32 the
        # TOP edge is the pinned one -- it is the cup's floor).
        set shadow_r [_phys_pts [cup_shadow_box $geom \
            [list 0 0 [dict get $c w] [dict get $c h]]]]
        lassign $shadow_r _sx1 _sy1 _sx2 _sy2
        if {$_sy2 - $_sy1 < 2} { set shadow_r [list $_sx1 $_sy1 $_sx2 [expr {$_sy1 + 2}]] }
        # Pass 46: the hero's stroke sprite carries the Pass 19 dim --
        # ring pixels at or right of the label column are painted
        # ring_dim -- so the column, zone-relative and physical, is part
        # of the sprite key (the hero zone is the only one that has it).
        set dim_x ""
        if {$tag eq "hero_cup"} {
            set dim_x [expr {[dui::platform::rescale_x $L(det_label_x)] - $ox}]
        }
        set out [dict create stem [_offset_pts $stem_r $ox $oy] handle [_offset_pts $handle_r $ox $oy] \
            outline [_offset_pts $outline_r $ox $oy] \
            layers $layers overflow [dict get $res overflow] \
            shadow [_offset_pts $shadow_r $ox $oy] \
            rel [dict create stem $stem_r handle $handle_r outline $outline_r shadow $shadow_r] \
            origin [list $ox $oy] zone [list $zw $zh] dim_x $dim_x \
            skey "[dict get $drink vessel]|${zw}x${zh}|[dict get $c tile_scale][expr {$dim_x ne "" ? "|d$dim_x" : ""}]"]
        set render_cache($key) $out
        return $out
    }

    # Creates the item pool for one cup, drawn inside (x y w h):
    #   <tag>_shadow   the mock's dark ellipse under the floor, FIRST so it
    #                  is lowest in the cup's stacking order
    #   <tag>_stem     stem+foot polygon (hidden for flat-bottomed cups)
    #   <tag>_handle   oval outline (hidden when the vessel has none)
    #   <tag>_interior filled bowl polygon (empty-cup tint)
    #   <tag>_layer0..5 ingredient slices (unused ones start hidden)
    #   <tag>_stroke   bowl outline stroke, on top
    # Returns the list of tags. drink is a dict {name vessel layers}.
    # `surface` is the mock glass family of the CARD the cup is drawn on
    # (tile / card / hero, see mock_glass_kinds): it picks the shadow's
    # colour and nothing else.
    proc draw_cup {page tag x y w h drink {use_tile_scale 1} {surface card}} {
        variable L
        variable cups
        set cups($tag) [dict create page $page x $x y $y w $w h $h drink $drink \
            tile_scale $use_tile_scale surface $surface]
        lassign [_cup_calc $tag $drink] geom res
        set cx [dict get $geom cx]
        set fy [dict get $geom floor_y]
        set tags {}
        set degenerate [list $cx $fy [expr {$cx + 1}] $fy [expr {$cx + 1}] [expr {$fy - 1}]]

        # The shadow FIRST: canvas items stack in creation order, so the
        # stem, the handle and the bowl are all drawn over it, exactly as
        # the mock's SVG puts the ellipse before the bowl polygon. No
        # outline -- a 1 px rim would read as a hard edge on a shape whose
        # whole job is to be soft.
        # Pass 44: the sprite pair (lazily painted, shared per vessel and
        # zone). In sprite mode the old shadow oval, handle oval and stroke
        # polygon are created hidden -- the fallback for a refused PNG --
        # and the stem polygon draws no ink outline (the sprite does).
        set r [_cup_render $tag $drink]
        set sp [cup_sprites $r]
        set smode [expr {$sp ne "" ? 1 : 0}]
        dict set cups($tag) sprite $smode
        if {$smode} {
            lassign $sp fg fx fy bg bx by
            dui add canvas_item image $page [_spx $x $bx] [_spy $y $by] -image $bg -anchor nw \
                -tags ${tag}_shb
            lappend tags ${tag}_shb
        }
        set srole [cup_shadow_role $surface]
        dui add canvas_item oval $page {*}[cup_shadow_box $geom [list $x $y $w $h]] \
            -fill $L($srole) -outline {} -tags ${tag}_shadow \
            {*}[expr {$smode ? [list -initial_state hidden] : {}}]
        _theme_item $page ${tag}_shadow fill $srole
        lappend tags ${tag}_shadow

        set stem [dict get $geom stem]
        if {$stem eq ""} {
            set stem $degenerate
            set sopts [list -initial_state hidden]
        } else {
            set sopts {}
        }
        set stem_edge [expr {$smode ? "stem_fill" : "c_ink"}]
        dui add canvas_item polygon $page {*}$stem -fill $L(stem_fill) -outline $L($stem_edge) \
            -width $L(line_w) -tags ${tag}_stem {*}$sopts
        _theme_item $page ${tag}_stem fill stem_fill
        _theme_item $page ${tag}_stem outline $stem_edge
        lappend tags ${tag}_stem

        set handle [dict get $geom handle]
        if {$handle eq "" || $smode} {
            if {$handle eq ""} { set handle [list $cx $fy [expr {$cx + 1}] [expr {$fy + 1}]] }
            set hopts [list -initial_state hidden]
        } else {
            set hopts {}
        }
        dui add canvas_item oval $page {*}$handle -fill {} -outline $L(c_ink) \
            -width $L(stroke_w) -tags ${tag}_handle {*}$hopts
        _theme_item $page ${tag}_handle outline c_ink
        lappend tags ${tag}_handle

        dui add canvas_item polygon $page {*}[dict get $geom outline] \
            -fill $L(cup_interior) -outline $L(cup_interior) -width $L(line_w) -tags ${tag}_interior
        _theme_item $page ${tag}_interior fill cup_interior
        _theme_item $page ${tag}_interior outline cup_interior
        lappend tags ${tag}_interior

        set polys [dict get $res polys]
        for {set i 0} {$i < $L(layer_pool)} {incr i} {
            if {$i < [llength $polys]} {
                lassign [lindex $polys $i] ptag pts color
                set lopts {}
            } else {
                set pts $degenerate
                set color $L(cup_interior)
                set lopts [list -initial_state hidden]
            }
            # Outline in the layer's own color: adjacent slices then meet
            # without a hairline gap.
            dui add canvas_item polygon $page {*}$pts -fill $color -outline $color \
                -width $L(line_w) -tags ${tag}_layer$i {*}$lopts
            lappend tags ${tag}_layer$i
        }

        dui add canvas_item polygon $page {*}[dict get $geom outline] \
            -fill {} -outline $L(c_ink) -width $L(stroke_w) -tags ${tag}_stroke \
            {*}[expr {$smode ? [list -initial_state hidden] : {}}]
        _theme_item $page ${tag}_stroke outline c_ink
        lappend tags ${tag}_stroke
        if {$smode} {
            dui add canvas_item image $page [_spx $x $fx] [_spy $y $fy] -image $fg -anchor nw \
                -tags ${tag}_fg
            lappend tags ${tag}_fg
        }

        if {[dict get $res overflow]} {
            catch { msg -NOTICE "DrinkMenu: $tag overflows its vessel ([dict get $drink vessel])" }
        }
        return $tags
    }

    # Every tag a cup pool owns (for slot show/hide).
    proc cup_tags {tag} {
        variable L
        set tags [list ${tag}_shb ${tag}_shadow ${tag}_stem ${tag}_handle ${tag}_interior ${tag}_stroke ${tag}_fg]
        set pool 6
        catch { set pool $L(layer_pool) }
        for {set j 0} {$j < $pool} {incr j} { lappend tags ${tag}_layer$j }
        return $tags
    }

    # Re-geometries an existing pool for a (possibly different) drink via
    # raw canvas coords, converted with the platform rescale helpers.
    # Recolors layers and hides the unused ones (tablet-verified path,
    # v0.1.0). Returns the overflow flag.
    proc update_cup {page tag drink} {
        variable L
        variable cups
        variable debug_timing
        set _dbg $debug_timing
        if {![info exists cups($tag)]} {
            error "DrinkMenu: update_cup on unknown cup '$tag'"
        }
        if {$_dbg} { set _t0 [clock microseconds] }
        set r [_cup_render $tag $drink]
        if {$_dbg} { t_add cup_calc [expr {[clock microseconds] - $_t0}] }
        set can [dui canvas]

        # Pass 44: sprite mode when this cup was drawn with sprites and
        # this vessel's pair exists (or paints now, once per vessel and
        # zone); else the canvas shadow, handle and stroke carry the cup as
        # before. Everything is shown here rather than by the slot's frame
        # list, so every caller gets it back after a hide without listing.
        set smode 0
        catch { set smode [dict get $cups($tag) sprite] }
        set sp ""
        if {$smode} { set sp [cup_sprites $r] }
        set use_sp [expr {$sp ne "" ? 1 : 0}]
        # Pass 46: remembered per cup, so update_hero_ring_dim knows
        # whether the stroke sprite (which carries the dim) is on screen.
        dict set cups($tag) use_sp $use_sp
        if {$use_sp} {
            lassign $sp fg fx fy bg bx by
            lassign [dict get $r origin] ox oy
            foreach id [_ids $page ${tag}_shb] {
                if {$_dbg} { t_count coords ; t_count item_config }
                $can coords $id [expr {$ox + $bx}] [expr {$oy + $by}]
                $can itemconfigure $id -image $bg
            }
            foreach id [_ids $page ${tag}_fg] {
                if {$_dbg} { t_count coords ; t_count item_config }
                $can coords $id [expr {$ox + $fx}] [expr {$oy + $fy}]
                $can itemconfigure $id -image $fg
            }
            _set_vis $page [list ${tag}_shb ${tag}_fg] 1
            _set_vis $page [list ${tag}_shadow ${tag}_handle ${tag}_stroke] 0
        } else {
            if {$smode} { _set_vis $page [list ${tag}_shb ${tag}_fg] 0 }
            set srole cup_shadow
            catch { set srole [cup_shadow_role [dict get $cups($tag) surface]] }
            foreach id [_ids $page ${tag}_shadow] {
                if {$_dbg} { t_count coords ; t_count item_config }
                $can coords $id {*}[dict get $r shadow]
                $can itemconfigure $id -fill $L($srole)
            }
            _set_vis $page [list ${tag}_shadow] 1
        }

        set stem [dict get $r stem]
        if {$stem eq ""} {
            _set_vis $page [list ${tag}_stem] 0
        } else {
            foreach id [_ids $page ${tag}_stem] {
                $can coords $id {*}$stem
                $can itemconfigure $id -fill $L(stem_fill) \
                    -outline [expr {$use_sp ? $L(stem_fill) : $L(c_ink)}]
            }
            _set_vis $page [list ${tag}_stem] 1
        }

        set handle [dict get $r handle]
        if {$use_sp} {
            # the sprite draws the ring; the oval stays hidden
        } elseif {$handle eq ""} {
            _set_vis $page [list ${tag}_handle] 0
        } else {
            foreach id [_ids $page ${tag}_handle] {
                $can coords $id {*}$handle
                $can itemconfigure $id -outline $L(c_ink)
            }
            _set_vis $page [list ${tag}_handle] 1
        }

        set outline [dict get $r outline]
        foreach id [_ids $page ${tag}_interior] {
            $can coords $id {*}$outline
            $can itemconfigure $id -fill $L(cup_interior) -outline $L(cup_interior)
        }
        if {!$use_sp} {
            foreach id [_ids $page ${tag}_stroke] {
                $can coords $id {*}$outline
                $can itemconfigure $id -outline $L(c_ink)
            }
            _set_vis $page [list ${tag}_stroke] 1
        }

        set layers [dict get $r layers]
        set nl [llength $layers]
        for {set i 0} {$i < $L(layer_pool)} {incr i} {
            set ids [_ids $page ${tag}_layer$i]
            if {$ids eq ""} { continue }
            if {$i < $nl} {
                lassign [lindex $layers $i] pts color
                foreach id $ids {
                    $can coords $id {*}$pts
                    $can itemconfigure $id -fill $color -outline $color
                }
                _set_vis $page [list ${tag}_layer$i] 1
            } else {
                _set_vis $page [list ${tag}_layer$i] 0
            }
        }
        set cups($tag) [dict replace $cups($tag) drink $drink]
        return [dict get $r overflow]
    }

    # Pass 19 -- the part of the handle ring that lies under the detail
    # page's label column, as ONE canvas arc.
    #
    # Since v0.10.4 a handled cup's ring reaches past det_cup_x2 and runs
    # under the first letters of the layer labels (owner decision, Pass
    # 18: the labels are drawn on top, as the mock draws them). The ring
    # is still a full-strength c_ink outline there, which is what makes
    # "Whipped cream" and "Hot chocolate" hard to read in
    # design/v0104_detail_borgia.png. The fix is to repaint exactly the
    # label-side part of the ring in ring_dim: same ellipse, same stroke
    # width, so the arc covers the ring stroke it sits on and nothing
    # else. The bowl-side part -- including where the leader lines cross
    # it -- keeps full strength.
    #
    # Pure function of the ring's PHYSICAL bbox {x1 y1 x2 y2} (the render
    # dict's `handle`, already through _phys_pts) and the PHYSICAL x of
    # the label column. Returns {} when the vessel has no handle or the
    # ring ends left of the column (every glass, and any future ring that
    # stays inside the cup box), otherwise
    #   {x1 y1 x2 y2 start extent}
    # with the ring's own bbox and the arc centred on the 3 o'clock
    # position:
    #   theta = acos((boundary - cx) / rx)   [degrees]
    #   start = -theta, extent = 2 * theta
    # Tk canvas angles are degrees counter-clockwise from 3 o'clock, and
    # x(a) = cx + rx*cos(a) is even in a, so that range is exactly the
    # part of the ellipse with x >= boundary whichever way y points.
    proc hero_ring_dim_arc {handle boundary} {
        if {[llength $handle] != 4} { return {} }
        lassign $handle x1 y1 x2 y2
        if {$x2 <= $x1 || $x2 <= $boundary} { return {} }
        set cx [expr {($x1 + $x2) / 2.0}]
        set rx [expr {($x2 - $x1) / 2.0}]
        set u [expr {($boundary - $cx) / $rx}]
        # x2 > boundary already rules out u > 1; the clamp is for the
        # degenerate case of a boundary left of the whole ring, which
        # dims all 360 degrees of it.
        if {$u > 1.0} { return {} }
        if {$u < -1.0} { set u -1.0 }
        set theta [expr {acos($u) * 180.0 / 3.14159265358979323846}]
        return [list $x1 $y1 $x2 $y2 [expr {-$theta}] [expr {2.0 * $theta}]]
    }

    # Drives the pooled hero arc (hero_cup_handle_dim) from the same
    # cached render dict update_cup uses: cached ids, raw canvas coords,
    # _set_vis for visibility -- no per-item dui call. Call it right
    # after `update_cup <page> hero_cup <drink>`. Returns the arc spec it
    # wrote, or {} when the arc is hidden.
    proc update_hero_ring_dim {page drink} {
        variable L
        variable cups
        variable debug_timing
        set r [_cup_render hero_cup $drink]
        set spec [hero_ring_dim_arc [dict get $r handle] \
            [dui::platform::rescale_x $L(det_label_x)]]
        # Pass 46: while the hero's stroke sprite is on screen it carries
        # the dim itself (cup_sprites, dim_x), so the canvas arc stays
        # hidden; the spec is still computed and returned (the DIMRING
        # net and the fallback both read it).
        set use_sp 0
        catch { set use_sp [dict get $cups(hero_cup) use_sp] }
        if {$spec eq "" || $use_sp} {
            _set_vis $page [list hero_cup_handle_dim] 0
            return $spec
        }
        lassign $spec ax1 ay1 ax2 ay2 astart aextent
        set can ""
        catch { set can [dui canvas] }
        if {$can eq ""} { return $spec }
        foreach id [_ids $page hero_cup_handle_dim] {
            if {$debug_timing} { t_count coords ; t_count item_config }
            $can coords $id $ax1 $ay1 $ax2 $ay2
            $can itemconfigure $id -start $astart -extent $aextent -outline $L(ring_dim)
        }
        _set_vis $page [list hero_cup_handle_dim] 1
        return $spec
    }

    # ------------------------------------------------------------------
    #  Palette re-application (Lumen theme may differ per app run; each
    #  page re-reads the tokens on every show and recolors by bare tag,
    #  filtered to its own items so no cross-page lookups are logged).
    # ------------------------------------------------------------------

    proc _theme_item {page tag prop role} {
        variable themed
        lappend themed [list $page $tag $prop $role]
    }

    # kind "btn" = ghost bar button, "primary" = the filled crema action
    # (Pass 12 item B3). Both are restyled by _retheme on every show.
    # `labels` lists the label sub-item suffixes this button actually
    # HAS: dui creates "<tag>-lbl" for -label and "<tag>-lbl1" for
    # -label1 (Pass 13's chevron bar buttons). Only real suffixes are
    # listed, because `dui item get` on a tag that matches nothing logs
    # a DEBUG "no canvas tag matches" line on every page show.
    proc _theme_btn {page tag {kind btn} {labels -lbl}} {
        variable themed_btns
        lappend themed_btns [list $page $tag $kind $labels]
    }

    proc _retheme {page} {
        variable L
        variable themed
        variable themed_btns
        set can ""
        catch { set can [dui canvas] }
        if {$can eq ""} { return }
        foreach it $themed {
            lassign $it p tag prop role
            if {$p ne $page} { continue }
            if {![info exists L($role)]} { continue }
            foreach id [_ids $page $tag] {
                catch { $can itemconfigure $id -$prop $L($role) }
            }
        }
        # Bar buttons (Pass 43): the face is the <tag>_art shape, repainted
        # from its state -- never the dbutton's own rect, which is
        # invisible and must stay so; the label is <tag>-lbl
        # (MaintenanceTracker v0.19.1, core-verified).
        foreach it $themed_btns {
            lassign $it p b kind labels
            if {$p ne $page} { continue }
            if {$labels eq ""} { set labels -lbl }
            set text [expr {$kind eq "primary" ? $L(pill_on_text) : $L(btn_label)}]
            shape_restore $page ${b}_art
            foreach suffix $labels {
                foreach id [_ids $page ${b}${suffix}] {
                    catch { $can itemconfigure $id -fill $text }
                }
            }
        }
        # Every other shape on the page (pills, capsules, badges, chips):
        # its remembered state, in the current palette.
        variable shapes
        foreach k [array names shapes "$page,*"] {
            set t [string range $k [string length "$page,"] end]
            if {[string match "*_art" $t]} { continue }
            shape_restore $page $t
        }
    }

    # Every canvas tag one tile slot owns (v0.2.1: exact tags; the tap
    # dbutton is the one item that carries dui's literal "<tag>*").
    proc _slot_tags {i} {
        set tags [list tile${i}_img \
            tile${i}_chip_bg tile${i}_chip_txt tile${i}_name {*}[star_tags $i] tile${i}_pen \
            tile${i}_tap* tile${i}_tap2* tile${i}_startap*]
        return [concat $tags [cup_tags tile${i}_cup]]
    }

    # The tags of a bound slot that are ALWAYS visible. The pen and the
    # cup's stem / handle / layer slices are driven by their own callers
    # (refresh and update_cup) right after, so showing them here only to
    # hide them again is wasted canvas work (Pass 9). The star joined this
    # list in Pass 21: it is shown on every bound slot now, in one of two
    # faces, instead of appearing only on favorites.
    proc _slot_frame_tags {i} {
        return [list tile${i}_img \
            tile${i}_chip_bg tile${i}_chip_txt tile${i}_name {*}[star_tags $i] \
            tile${i}_tap* tile${i}_tap2* tile${i}_startap* \
            tile${i}_cup_interior]
    }

    # The tile star's two faces, as the drawn polygon's {fill outline}
    # pair (Pass 22; it was {glyph font fill} while the star was a text
    # item). Pure, so the headless STARTAP / STARFILL checks can assert
    # that the states really differ. Both pairs read straight from the
    # palette tokens _apply_palette wrote, so a retheme reaches BOTH
    # states: the refresh that follows every page show rewrites whichever
    # face the slot is in, and _apply_palette drops fill_cache with the
    # other "already written" caches so that rewrite is never skipped.
    proc star_face {on} {
        variable L
        # Favorite: a solid gold star (fill and outline the same colour,
        # so the shape does not gain a rim of another hue).
        if {$on} {
            return [list $L(c_crema) $L(c_crema)]
        }
        # Not a favorite: empty, with a dim outline -- the hollow star the
        # icon font could only ever draw, now on purpose.
        return [list {} $L(c_ink_3)]
    }

    proc _show_slot {page i on} {
        if {$on} {
            _set_vis $page [_slot_frame_tags $i] 1
        } else {
            _set_vis $page [_slot_tags $i] 0
        }
    }

    # Active/inactive face of a segmented control or tab pill, by bare
    # tag (relabel-free; only fills change).
    proc _style_pill {page tag on} {
        variable L
        variable debug_timing
        variable pill_cache
        set fill [expr {$on ? $L(pill_on_fill) : $L(pill_off_fill)}]
        set text [expr {$on ? $L(pill_on_text) : $L(pill_off_text)}]
        # Pass 23 item 7: the pill's EDGE follows its state too -- the mock
        # gives `.pill.on` the lighter gold border it needs on a gold fill,
        # not the page's glass edge. Since pass 32 that edge is the drawn
        # polygon's own -outline (pill_shape).
        set edge [expr {$on ? $L(pill_on_edge) : $L(pill_off_edge)}]
        # The face is the cache key, so a palette change always repaints.
        if {[info exists pill_cache($page,$tag)] && $pill_cache($page,$tag) eq "$fill|$text|$edge"} { return }
        if {$debug_timing} { t_count item_config 2 }
        set can ""
        catch { set can [dui canvas] }
        if {$can eq ""} { return }
        # Pass 43: the pill is a shape; its state paint swaps the cap
        # photos and recolours the flat body.
        shape_paint $page ${tag}_cap [expr {$on ? "pill_on_fill" : "pill_off_fill"}] \
            [expr {$on ? "pill_on_edge" : "pill_off_edge"}]
        foreach id [_ids $page ${tag}_lbl] {
            catch { $can itemconfigure $id -fill $text }
        }
        set pill_cache($page,$tag) "$fill|$text|$edge"
    }

    # Active half of a capsule segment built by segment_capsule: `active`
    # is 0 (left) or 1 (right). Only the fill items' visibility and the
    # two label colors change; nothing is created, moved or relabeled.
    # Shares pill_cache, which _apply_palette drops on every page show.
    proc _style_segment {page tag active} {
        variable L
        variable pill_cache
        set active [expr {$active ? 1 : 0}]
        set key "$L(seg_on_fill)|$L(seg_on_text)|$L(pill_off_text)|$active"
        if {[info exists pill_cache($page,$tag)] && $pill_cache($page,$tag) eq $key} { return }
        _set_vis $page [list ${tag}_onl] [expr {$active == 0}]
        _set_vis $page [list ${tag}_onr] [expr {$active == 1}]
        set can ""
        catch { set can [dui canvas] }
        if {$can ne ""} {
            for {set i 0} {$i < 2} {incr i} {
                set col [expr {$i == $active ? $L(seg_on_text) : $L(pill_off_text)}]
                foreach id [_ids $page ${tag}_lbl$i] {
                    catch { $can itemconfigure $id -fill $col }
                }
            }
        }
        set pill_cache($page,$tag) $key
    }

    # ------------------------------------------------------------------
    #  Press feedback for the controls this plugin paints itself (Pass 32)
    # ------------------------------------------------------------------
    # The core's -pressfill cannot sit on these (the press rule in
    # _apply_palette), so the flash is painted here, from the tap's own
    # command, and ALWAYS ends in a repaint FROM STATE: the restore drops
    # the page's pill cache and calls the same painters the refresh uses,
    # so a fast double tap, a page change or a lost timer can never leave
    # a pressed face behind. By the time the flash paints, the tapped
    # control is the SELECTED one, so the flash tone is the primary press
    # colour, exactly what the core flashes Save / Done to.

    variable press_after
    array set press_after {}

    # Header controls of one page, painted from state. The refresh procs
    # call this too, so the flash's restore and the page's own repaint
    # are one and the same code path.
    proc _paint_controls {page} {
        variable ui_unit
        variable ui_tab
        variable detail_size
        variable tabs
        variable cust_unit
        variable pill_cache
        if {$page eq "DrinkMenu_edit"} {
            # Only the custing capsule lives here (Pass 33). Uncached:
            # the mode-group show can re-show BOTH gold overlays, which
            # a cache hit would then leave standing.
            array unset pill_cache $page,cunit
            _style_segment $page cunit [expr {$cust_unit eq "g"}]
            return
        }
        _style_segment $page unit [expr {$ui_unit eq "oz"}]
        if {$page eq "DrinkMenu_detail"} {
            _style_segment $page size [expr {$detail_size eq "double"}]
        } else {
            foreach {tab label} $tabs {
                _style_pill $page tab_$tab [expr {$tab eq $ui_tab}]
            }
        }
    }

    proc _flash_arm {page tag kind} {
        variable L
        variable press_after
        set key $page,$tag
        catch { after cancel $press_after($key) }
        set press_after($key) [after $L(press_ms) \
            [list ::plugins::DrinkMenu::_press_restore $page $key $tag $kind]]
    }

    proc _press_restore {page key tag kind} {
        variable press_after
        variable pill_cache
        variable L
        catch { unset press_after($key) }
        # Pass 43: every flashed shape is put back from its own remembered
        # state. A bar button (kind btn) is done there; a capsule's two
        # gold halves are restored before the state painters run (they
        # only steer visibility and label colours); a pill is repainted by
        # _style_pill through the cleared cache.
        if {$kind eq "btn"} {
            shape_restore $page $tag
            return
        }
        if {$kind eq "seg"} {
            foreach side {l r} { shape_restore $page ${tag}_on$side }
        }
        array unset pill_cache $page,*
        _paint_controls $page
    }

    # Tab pill flash: tint the pill's own polygon; the restore repaints
    # it through _style_pill. A tag with no pill (ui_tab "hidden") or a
    # page that is not ours is a silent no-op.
    proc _flash_pill {tag} {
        variable L
        set page ""
        catch { set page [dui page current] }
        if {$page ni {DrinkMenu_main DrinkMenu_detail DrinkMenu_edit}} { return }
        set can ""
        catch { set can [dui canvas] }
        if {$can eq ""} { return }
        variable shapes
        if {![info exists shapes($page,${tag}_cap)]} { return }
        shape_flash $page ${tag}_cap btn_primary_press btn_primary_press
        _flash_arm $page $tag pill
    }

    # Capsule flash: tint the tapped half's own gold overlay (the refresh
    # has just shown it -- the tapped half is the active one).
    proc _flash_seg {tag side} {
        variable L
        set page ""
        catch { set page [dui page current] }
        if {$page ni {DrinkMenu_main DrinkMenu_detail DrinkMenu_edit}} { return }
        set can ""
        catch { set can [dui canvas] }
        if {$can eq ""} { return }
        variable shapes
        if {![info exists shapes($page,${tag}_on$side)]} { return }
        shape_flash $page ${tag}_on$side seg_press seg_press
        _flash_arm $page $tag seg
    }

    # ------------------------------------------------------------------
    #  Actions (session state only; every change ends in a refresh of
    #  the page that is currently showing)
    # ------------------------------------------------------------------

    proc _refresh_current {} {
        set cur ""
        catch { set cur [dui page current] }
        if {$cur eq "DrinkMenu_detail"} {
            if {[catch { ::dui::pages::DrinkMenu_detail::refresh } err]} {
                catch { msg -ERROR "DrinkMenu: detail refresh failed: $err" }
            }
        } else {
            if {[catch { ::dui::pages::DrinkMenu_main::refresh } err]} {
                catch { msg -ERROR "DrinkMenu: refresh failed: $err" }
            }
        }
    }

    proc set_tab {tab} {
        variable ui_tab
        variable ui_page
        variable tabs
        variable debug_timing
        if {![dict exists $tabs $tab] && $tab ne "hidden"} { return }
        if {$debug_timing} { set _t0 [clock microseconds] }
        set ui_tab $tab
        set ui_page 1
        _refresh_current
        # "hidden" has no pill: probing for one would log a DEBUG
        # "no canvas tag matches" line on every Hidden visit.
        if {[dict exists $tabs $tab]} { _flash_pill tab_$tab }
        if {$debug_timing} { t_log set_tab [expr {[clock microseconds] - $_t0}] }
    }

    # Unit toggle (menu or detail). Persist caller 1 of 3.
    proc set_unit {unit} {
        variable ui_unit
        variable settings
        if {$unit ni {ml oz}} { return }
        set ui_unit $unit
        set settings(unit) $unit
        _persist unit
        _refresh_current
        _flash_seg unit [expr {$unit eq "oz" ? "r" : "l"}]
    }

    # Favorite toggle (detail page button). Persist caller 2 of 3.
    proc toggle_favorite {id} {
        variable drinks
        variable settings
        if {![drink_exists $id]} { return }
        set favs [_favorites]
        set i [lsearch -exact $favs $id]
        if {$i >= 0} {
            set favs [lreplace $favs $i $i]
        } else {
            lappend favs $id
        }
        set settings(favorites) $favs
        invalidate_cache
        _persist favorite
        _refresh_current
    }

    # Hide / unhide (detail page button). Persist caller 3 of 3. Then
    # returns to the menu through the normal Back path; the menu's show
    # reloads the tab and clamps the page. Unhiding from the hidden view
    # stays there, or goes to All once nothing is hidden.
    proc toggle_hidden {id} {
        variable drinks
        variable settings
        variable ui_tab
        variable ui_page
        if {![drink_exists $id]} { return }
        set hid [_hidden]
        set i [lsearch -exact $hid $id]
        if {$i >= 0} {
            set hid [lreplace $hid $i $i]
        } else {
            lappend hid $id
        }
        set settings(hidden) $hid
        invalidate_cache
        _persist hide
        if {$ui_tab eq "hidden" && [llength $hid] == 0} {
            set ui_tab all
            set ui_page 1
        }
        detail_back
    }

    proc favorite_tap {} {
        variable detail_id
        toggle_favorite $detail_id
    }

    proc hide_tap {} {
        variable detail_id
        toggle_hidden $detail_id
    }

    proc show_hidden {} {
        set_tab hidden
    }

    # ------------------------------------------------------------------
    #  Editor actions. The working dict lives in edit_drink; nothing is
    #  persisted until a confirm card's confirming button runs one of
    #  the five editor_* callers below.
    # ------------------------------------------------------------------

    proc _hide_keyboard {} {
        catch { dui platform hide_android_keyboard }
    }

    # ---- Pass 48: the name entry's focus, its keyboard Done and its
    #      "Drink name" hint ----
    #
    # A Tk entry has no placeholder and a window item always sits above
    # the canvas, so the hint is the entry's OWN text: while the name is
    # empty and the entry unfocused, edit_name carries the hint in
    # c_ink_3 with edit_name_hint set, written under edit_loading so the
    # keystroke trace never copies it into the draft (edit_drink's name
    # stays "" and validation still asks for a name). Focus in drops the
    # hint and shows the keyboard Done; focus out puts it back and hides
    # Done. Every code path that sets edit_name resets the flag.
    variable edit_name_hint 0

    proc _name_entry_widget {} {
        set can ""
        catch { set can [dui canvas] }
        if {$can eq ""} { return "" }
        return "$can.drinkmenu_edit-ed_name_entry"
    }

    proc _name_focused {} {
        set w [_name_entry_widget]
        set f 0
        catch { set f [expr {$w ne "" && [winfo exists $w] && [focus] eq $w}] }
        return $f
    }

    proc _name_hint_apply {} {
        variable edit_name
        variable edit_loading
        variable edit_name_hint
        variable L
        set w [_name_entry_widget]
        if {$w eq "" || [catch { winfo exists $w } ex] || !$ex} { return }
        if {[_name_focused]} { _name_hint_drop ; return }
        if {$edit_name_hint || $edit_name ne ""} { return }
        set edit_loading 1
        set edit_name_hint 1
        set edit_name [translate "Drink name"]
        set edit_loading 0
        catch { $w configure -foreground $L(c_ink_3) }
    }

    proc _name_hint_drop {} {
        variable edit_name
        variable edit_loading
        variable edit_name_hint
        variable L
        if {!$edit_name_hint} { return }
        set edit_loading 1
        set edit_name ""
        set edit_loading 0
        set edit_name_hint 0
        catch { [_name_entry_widget] configure -foreground $L(c_ink) }
    }

    proc _name_focus {in} {
        if {$in} { _name_hint_drop } else { _name_hint_apply }
        catch { _show_tags DrinkMenu_edit ed_done* $in }
    }

    # The keyboard Done: hide the keyboard and give the focus back to
    # the canvas, so the entry's FocusOut runs (hint back, Done away).
    proc _name_done {} {
        _hide_keyboard
        catch { focus [dui canvas] }
    }

    proc _refresh_editor {} {
        if {[catch { ::dui::pages::DrinkMenu_edit::refresh } err]} {
            catch { msg -ERROR "DrinkMenu: editor refresh failed: $err" }
        }
    }

    # Keystroke trace on the name entry: marks the draft dirty and
    # updates the preview. Never writes.
    proc _on_name_edit {args} {
        variable edit_loading
        variable edit_dirty
        variable edit_drink
        variable edit_name
        variable edit_name_hint
        if {$edit_loading} { return }
        if {$edit_drink eq ""} { return }
        # Pass 48: a keystroke that lands while the hint is still up is
        # real typing -- keep it, drop the hint's flag and colour.
        if {$edit_name_hint} {
            set edit_name_hint 0
            variable L
            catch { [_name_entry_widget] configure -foreground $L(c_ink) }
        }
        dict set edit_drink name $edit_name
        set edit_dirty 1
        set cur ""
        catch { set cur [dui page current] }
        if {$cur eq "DrinkMenu_edit"} {
            if {[catch { ::dui::pages::DrinkMenu_edit::refresh_preview } err]} {
                catch { msg -ERROR "DrinkMenu: preview refresh failed: $err" }
            }
        }
    }

    # Edit button on the detail page: "Copy & edit" for a preset (opens
    # a fresh, not-yet-saved custom copy named "<preset> copy"); "Edit"
    # for a custom drink (opens that drink itself). open_editor decides
    # which case applies from is_custom.
    proc edit_tap {} {
        variable detail_id
        open_editor $detail_id
    }

    # Pass 48: the detail page's "Add a method" link (custom drinks with
    # no steps): the editor, straight into its method mode.
    proc method_add_tap {} {
        variable detail_id
        if {![is_custom $detail_id]} { return }
        open_editor $detail_id
        edit_set_mode method
    }

    proc open_editor {id} {
        variable edit_id
        variable edit_kind
        variable edit_source_id
        variable edit_drink
        variable edit_name
        variable edit_dirty
        variable edit_mode
        variable edit_pending
        variable edit_loading
        variable edit_note
        variable edit_origin
        set d [get_drink $id]
        if {$d eq ""} { return }
        set edit_origin DrinkMenu_detail
        set edit_kind custom
        set edit_source_id $id
        if {[is_custom $id]} {
            set edit_id $id
        } else {
            # Preset: a fresh, unsaved custom copy. The id exists only
            # in this session until Save (editor_save_custom) writes it.
            set edit_id [new_custom_id [dict keys [_customs]]]
            dict set d name [string range "[string trim [dict get $d name]] [translate "copy"]" 0 23]
        }
        set edit_drink [dict create name [dict get $d name] vessel [dict get $d vessel] \
            layers [dict get $d layers]]
        # Pass 33: an edited custom drink brings its own ingredient defs.
        catch { if {[dict exists $d custom_ings]} {
            dict set edit_drink custom_ings [dict get $d custom_ings]
        } }
        # Pass 36: the garnish is part of the draft now (editable).
        catch { dict set edit_drink garnish [clean_garnish [dict get $d garnish]] }
        # Pass 37: so are the method steps (a preset copy starts from the
        # preset's own steps, exactly what the save used to copy).
        dict set edit_drink steps [drink_steps $d]
        # Pass 38: and the group. A custom drink keeps its choice; a
        # PRESET copy starts from the preset's own group, so the copy
        # sorts next to its source until changed.
        set grp custom
        catch { set grp [dict get $d group] }
        if {![valid_group $grp]} { set grp custom }
        dict set edit_drink group $grp
        # Pass 40: a custom drink brings its profile link into the draft.
        catch {
            if {[dict exists $d profile_fn]} {
                dict set edit_drink profile_fn [dict get $d profile_fn]
                catch { dict set edit_drink profile_title [dict get $d profile_title] }
            }
        }
        set edit_loading 1
        set edit_name [dict get $d name]
        set ::plugins::DrinkMenu::edit_name_hint 0
        catch { [_name_entry_widget] configure -foreground $::plugins::DrinkMenu::L(c_ink) }
        set edit_loading 0
        set edit_dirty 0
        set edit_mode layers
        set edit_pending ""
        set edit_note ""
        open_page DrinkMenu_edit
    }

    # "+ New drink" on the menu bar (Pass 13). Opens the editor on a
    # fresh, unsaved custom draft with the menu as the origin, so Cancel
    # and a confirmed Save both return to the menu (there is no detail
    # page for a drink that does not exist yet). Exactly the editor
    # state open_editor sets; writes nothing -- the draft can only reach
    # settings through the existing confirmed custom_save.
    proc new_drink_tap {} {
        variable edit_id
        variable edit_kind
        variable edit_source_id
        variable edit_drink
        variable edit_name
        variable edit_dirty
        variable edit_mode
        variable edit_pending
        variable edit_loading
        variable edit_note
        variable edit_origin
        set d [new_draft [dict keys [_customs]]]
        set edit_origin DrinkMenu_main
        set edit_kind custom
        set edit_id [dict get $d id]
        set edit_source_id $edit_id
        set edit_drink [dict create name [dict get $d name] vessel [dict get $d vessel] \
            layers [dict get $d layers] garnish {} steps {} group custom]
        set edit_loading 1
        set edit_name [dict get $d name]
        set ::plugins::DrinkMenu::edit_name_hint 0
        catch { [_name_entry_widget] configure -foreground $::plugins::DrinkMenu::L(c_ink) }
        set edit_loading 0
        set edit_dirty 0
        set edit_mode layers
        set edit_pending ""
        set edit_note ""
        open_page DrinkMenu_edit
    }

    # Where the editor returns to: the page it was opened from. Same
    # mechanism editor_leave has always used; only the origin varies.
    proc edit_return_page {} {
        variable edit_origin
        if {$edit_origin eq "DrinkMenu_main"} { return DrinkMenu_main }
        return DrinkMenu_detail
    }

    proc edit_set_mode {mode} {
        variable edit_mode
        variable edit_note
        if {$mode ni {layers palette vessel custing garnish method stepform group confirm}} { return }
        _hide_keyboard
        set edit_mode $mode
        if {$mode ne "layers"} { set edit_note "" }
        _refresh_editor
    }

    # Row i is displayed top-first; layer index = n-1-i.
    proc _row_to_layer {i} {
        variable edit_drink
        set n [expr {[llength [dict get $edit_drink layers]] / 2}]
        return [expr {$n - 1 - $i}]
    }

    proc edit_step_tap {i dir} {
        variable edit_drink
        variable edit_dirty
        _hide_keyboard
        set li [_row_to_layer $i]
        set new [edit_step $edit_drink $li $dir]
        if {$new ne $edit_drink} { set edit_drink $new; set edit_dirty 1 }
        _refresh_editor
    }

    proc edit_remove_tap {i} {
        variable edit_drink
        variable edit_dirty
        _hide_keyboard
        set edit_drink [edit_remove $edit_drink [_row_to_layer $i]]
        set edit_dirty 1
        _refresh_editor
    }

    # Pass 35: the row's chevron-up / chevron-down. dir is in ROW terms
    # (+1 = the row moves up the LIST); rows are top-first while layers
    # are bottom-first, so up the list is also up the glass: the layer
    # index moves by the same +1.
    proc edit_move_tap {i dir} {
        variable edit_drink
        variable edit_dirty
        _hide_keyboard
        set new [edit_move $edit_drink [_row_to_layer $i] $dir]
        if {$new ne $edit_drink} { set edit_drink $new; set edit_dirty 1 }
        _refresh_editor
    }

    proc edit_add_tap {} { edit_set_mode palette }
    proc edit_vessel_tap {} { edit_set_mode vessel }

    # ---- Profile link (Pass 40) ----
    # Toggles the draft's profile link: none -> stamp the app's CURRENT
    # profile (dial it in first, then link it); linked -> clear. Rides
    # the confirmed Save like every other draft field; touches no app
    # setting itself.
    proc edit_profile_toggle {} {
        variable edit_drink
        variable edit_dirty
        variable edit_note
        _hide_keyboard
        if {[drink_profile $edit_drink] ne {}} {
            dict unset edit_drink profile_fn
            dict unset edit_drink profile_title
            set edit_dirty 1
            set edit_note [translate "Profile link removed"]
        } else {
            set fn ""
            catch { set fn [string trim $::settings(profile_filename)] }
            if {$fn eq ""} {
                set edit_note [translate "No profile is selected in the app"]
            } else {
                set title $fn
                catch {
                    set t [string trim $::settings(profile_title)]
                    if {$t ne ""} { set title $t }
                }
                dict set edit_drink profile_fn [string range $fn 0 127]
                dict set edit_drink profile_title [string range $title 0 79]
                set edit_dirty 1
                set edit_note "[translate "Profile linked"]: $title"
            }
        }
        _refresh_editor
    }

    # ---- Group mode (Pass 38) ----
    proc edit_group_tap {} { edit_set_mode group }

    proc edit_pick_group {g} {
        variable edit_drink
        variable edit_dirty
        if {![valid_group $g]} { return }
        set old custom
        catch { set old [dict get $edit_drink group] }
        if {$g ne $old} {
            dict set edit_drink group $g
            set edit_dirty 1
        }
        edit_set_mode layers
    }
    proc edit_mode_cancel {} {
        variable cust_edit_id
        variable cust_edit_color
        # A cancelled custing edit must not leave the NEXT "+ Custom..."
        # opening in edit-in-place mode (Pass 34).
        set cust_edit_id ""
        set cust_edit_color ""
        edit_set_mode layers
    }

    # ---- Garnish mode (Pass 36) ----
    # Session-only state; the list reaches settings only inside the
    # draft, through the existing confirmed saves.
    variable garn_text ""

    proc edit_garnish_tap {} {
        variable edit_drink
        variable garn_text
        set gn {}
        catch { set gn [dict get $edit_drink garnish] }
        set garn_text [garnish_to_text [clean_garnish $gn]]
        edit_set_mode garnish
    }

    proc edit_garnish_save {} {
        variable edit_drink
        variable edit_dirty
        variable garn_text
        _hide_keyboard
        # An empty entry legitimately clears the garnish.
        dict set edit_drink garnish [garnish_from_text $garn_text]
        set edit_dirty 1
        edit_set_mode layers
    }

    # ---- Method steps modes (Pass 37) ----
    # `method` lists the draft's steps (edit / remove / reorder / add);
    # `stepform` is the one-entry form for a single step. Session-only
    # state; the list reaches settings only inside the draft, through the
    # existing confirmed saves.
    variable step_text ""
    variable step_edit_idx -1

    proc _draft_steps {} {
        variable edit_drink
        set st {}
        catch { set st [dict get $edit_drink steps] }
        return [clean_steps $st]
    }

    proc edit_method_tap {} { edit_set_mode method }

    proc edit_step_row_tap {i} {
        variable step_text
        variable step_edit_idx
        set steps [_draft_steps]
        if {$i < 0 || $i >= [llength $steps]} { return }
        set step_text [lindex $steps $i]
        set step_edit_idx $i
        edit_set_mode stepform
    }

    proc edit_step_add_tap {} {
        variable step_text
        variable step_edit_idx
        variable steps_max
        if {[llength [_draft_steps]] >= $steps_max} { return }
        set step_text ""
        set step_edit_idx -1
        edit_set_mode stepform
    }

    # The form's own cancel: back to the step LIST, not to layers.
    proc edit_step_cancel {} { edit_set_mode method }

    proc edit_step_save {} {
        variable edit_drink
        variable edit_dirty
        variable step_text
        variable step_edit_idx
        _hide_keyboard
        # An emptied entry is "no change" -- the row's own x removes.
        set new [steps_with [_draft_steps] $step_edit_idx $step_text]
        if {$new ne [_draft_steps]} {
            dict set edit_drink steps $new
            set edit_dirty 1
        }
        edit_set_mode method
    }

    proc edit_step_rm {i} {
        variable edit_drink
        variable edit_dirty
        _hide_keyboard
        set new [steps_remove [_draft_steps] $i]
        if {$new ne [_draft_steps]} {
            dict set edit_drink steps $new
            set edit_dirty 1
        }
        _refresh_editor
    }

    proc edit_step_move_tap {i dir} {
        variable edit_drink
        variable edit_dirty
        _hide_keyboard
        set new [steps_move [_draft_steps] $i $dir]
        if {$new ne [_draft_steps]} {
            dict set edit_drink steps $new
            set edit_dirty 1
        }
        _refresh_editor
    }

    # ---- Custom ingredient mode (Pass 33) ----
    # Session-only state; nothing here writes. The def reaches
    # settings(custom) only inside the draft, through the existing
    # confirmed Save.
    proc edit_custom_tap {} {
        variable cust_name
        variable cust_unit
        variable cust_sel
        variable cust_edit_id
        variable cust_edit_color
        set cust_name ""
        set cust_unit ml
        set cust_sel 0
        set cust_edit_id ""
        set cust_edit_color ""
        edit_set_mode custing
    }

    # Pen / row tap on a CUSTOM layer (Pass 34): reopen the form
    # prefilled with that def and switch it to edit-in-place.
    proc edit_layer_tap {i} {
        variable edit_drink
        variable cust_name
        variable cust_unit
        variable cust_sel
        variable cust_edit_id
        variable cust_edit_color
        variable cust_colors
        set li [_row_to_layer $i]
        set layers {}
        catch { set layers [dict get $edit_drink layers] }
        if {$li < 0 || 2 * $li >= [llength $layers]} { return }
        set ing [lindex $layers [expr {2 * $li}]]
        if {![dict exists $edit_drink custom_ings] \
                || ![dict exists $edit_drink custom_ings $ing]} { return }
        set def [dict get $edit_drink custom_ings $ing]
        set cust_name ""
        catch { set cust_name [dict get $def name] }
        set cust_unit ml
        catch { if {[dict get $def unit] eq "g"} { set cust_unit g } }
        set cust_edit_color ""
        catch { set cust_edit_color [dict get $def color] }
        # -1 (no ring) for a colour outside the swatches; a save that
        # never taps a swatch then keeps the original colour.
        set cust_sel [lsearch -exact $cust_colors $cust_edit_color]
        set cust_edit_id $ing
        edit_set_mode custing
    }

    proc edit_custom_unit {u} {
        variable cust_unit
        if {$u ni {ml g}} { return }
        set cust_unit $u
        _refresh_editor
        _flash_seg cunit [expr {$u eq "g" ? "r" : "l"}]
    }

    proc edit_custom_color {i} {
        variable cust_sel
        variable cust_colors
        if {![string is integer -strict $i] || $i < 0 || $i >= [llength $cust_colors]} { return }
        set cust_sel $i
        _refresh_editor
    }

    # The next free c<N> within THIS drink's defs.
    proc _new_cust_id {drink} {
        set used {}
        catch { set used [dict keys [dict get $drink custom_ings]] }
        set n 1
        while {"c$n" in $used} { incr n }
        return "c$n"
    }

    proc edit_custom_add {} {
        variable edit_drink
        variable edit_dirty
        variable edit_note
        variable cust_name
        variable cust_unit
        variable cust_sel
        variable cust_edit_id
        variable cust_edit_color
        variable cust_colors
        _hide_keyboard
        set nm [string trim $cust_name]
        if {$nm eq ""} {
            set edit_note [translate "Type a name for the ingredient"]
            _refresh_editor
            return
        }
        set nm [string range $nm 0 23]
        set color [lindex $cust_colors $cust_sel]
        if {$color eq ""} { set color $cust_edit_color }
        if {$color eq ""} { set color [lindex $cust_colors 0] }
        set unit [expr {$cust_unit eq "g" ? "g" : "ml"}]
        # Pass 34: editing an existing def applies the form IN PLACE --
        # the layer list (and the amount) is untouched.
        if {$cust_edit_id ne ""} {
            if {[dict exists $edit_drink custom_ings $cust_edit_id]} {
                dict set edit_drink custom_ings $cust_edit_id \
                    [dict create name $nm color $color unit $unit]
                set edit_dirty 1
            }
            set cust_edit_id ""
            set cust_edit_color ""
            edit_set_mode layers
            return
        }
        set cid [_new_cust_id $edit_drink]
        set draft $edit_drink
        dict set draft custom_ings $cid [dict create name $nm color $color unit $unit]
        lassign [edit_add_layer $draft $cid] new why
        if {$why ne ""} {
            set edit_note $why
            edit_set_mode layers
            set edit_note $why
            _refresh_editor
            return
        }
        set edit_drink $new
        set edit_dirty 1
        edit_set_mode layers
    }

    proc edit_pick_ingredient {ing} {
        variable edit_drink
        variable edit_dirty
        variable edit_note
        lassign [edit_add_layer $edit_drink $ing] new why
        if {$why ne ""} {
            set edit_note $why
            edit_set_mode layers
            set edit_note $why
            _refresh_editor
            return
        }
        set edit_drink $new
        set edit_dirty 1
        edit_set_mode layers
    }

    proc edit_pick_vessel {vessel} {
        variable edit_drink
        variable edit_dirty
        set new [edit_set_vessel $edit_drink $vessel]
        if {$new ne $edit_drink} { set edit_drink $new; set edit_dirty 1 }
        edit_set_mode layers
    }

    # Bottom-bar requests open the confirm card (or leave directly when
    # cancelling a clean draft).
    proc edit_request {action} {
        variable edit_pending
        variable edit_dirty
        variable edit_id
        variable edit_drink
        _hide_keyboard
        if {$action eq "cancel" && !$edit_dirty} {
            editor_leave [edit_return_page]
            return
        }
        if {$action in {save copy}} {
            lassign [validate_drink $edit_drink] ok why
            if {!$ok} { _refresh_editor; return }
        }
        if {$action eq "delete" && ![is_custom $edit_id]} { return }
        set edit_pending $action
        edit_set_mode confirm
    }

    proc edit_confirm_no {} {
        variable edit_pending
        set edit_pending ""
        edit_set_mode layers
    }

    # The confirming button. Dispatches to exactly one persist caller.
    proc edit_confirm_yes {} {
        variable edit_pending
        set action $edit_pending
        set edit_pending ""
        switch -- $action {
            save   { editor_save_custom }
            copy   { editor_save_copy }
            delete { editor_delete_custom }
            cancel { editor_leave [edit_return_page] }
            default { edit_set_mode layers }
        }
    }

    # Name pre-suffixed " copy" when unchanged from the source drink.
    proc _copy_name {} {
        variable edit_id
        variable edit_drink
        set name [string trim [dict get $edit_drink name]]
        set src [get_drink $edit_id]
        if {$src ne "" && $name eq [string trim [dict get $src name]]} {
            set name "$name [translate "copy"]"
        }
        return [string range $name 0 23]
    }

    proc _clean_draft {} {
        variable edit_drink
        set d [dict create name [string trim [dict get $edit_drink name]] \
            vessel [dict get $edit_drink vessel] layers [dict get $edit_drink layers]]
        # Pass 33: carry the drink's own ingredient defs, PRUNED to the
        # ids the layers still reference, so a removed custom layer
        # leaves no orphaned def in settings.
        set cings {}
        catch { set cings [dict get $edit_drink custom_ings] }
        set kept {}
        catch {
            foreach {ing ml} [dict get $d layers] {
                if {[dict exists $cings $ing] && ![dict exists $kept $ing]} {
                    dict set kept $ing [dict get $cings $ing]
                }
            }
        }
        if {[dict size $kept] > 0} { dict set d custom_ings $kept }
        # Pass 36: the DRAFT's garnish is what gets saved (always present,
        # cleaned, exactly the shape every preset carries).
        set gn {}
        catch { set gn [dict get $edit_drink garnish] }
        dict set d garnish [clean_garnish $gn]
        # Pass 37: and the DRAFT's method steps.
        set st {}
        catch { set st [dict get $edit_drink steps] }
        dict set d steps [clean_steps $st]
        # Pass 38: and the DRAFT's group (sanitized; `custom` = end).
        set grp custom
        catch { set grp [dict get $edit_drink group] }
        if {![valid_group $grp]} { set grp custom }
        dict set d group $grp
        # Pass 40: and the profile link, when one is set (both keys or
        # neither; lengths capped).
        set pfn ""
        catch { set pfn [string trim [dict get $edit_drink profile_fn]] }
        if {$pfn ne ""} {
            dict set d profile_fn [string range $pfn 0 127]
            set pt $pfn
            catch {
                set t [string trim [dict get $edit_drink profile_title]]
                if {$t ne ""} { set pt $t }
            }
            dict set d profile_title [string range $pt 0 79]
        }
        return $d
    }

    # Persist caller 4 of 6: save the custom draft. Works whether
    # edit_id already exists as a custom drink (ordinary re-edit) or not
    # yet (the first Save of a "Copy & edit" draft off a preset, or of a
    # "+ New drink" draft) -- either way this is the id it is saved
    # under. Garnish is carried from edit_source_id, since a fresh
    # copy's own edit_id does not exist yet; a "+ New drink" draft is
    # its own source, so the lookup simply finds nothing and the garnish
    # stays empty.
    proc editor_save_custom {} {
        variable settings
        variable edit_id
        variable edit_source_id
        variable detail_id
        set d [_clean_draft]
        lassign [validate_drink $d] ok why
        if {!$ok} { _refresh_editor; return }
        # Pass 36/37/38: garnish, method steps AND the group are the
        # DRAFT's own now (all editable), already in the clean draft.
        dict set d source custom
        set cu [_customs]
        dict set cu $edit_id $d
        set settings(custom) $cu
        invalidate_cache
        _persist custom_save
        set detail_id $edit_id
        editor_leave [edit_return_page]
    }

    # Persist caller 5 of 6: save the draft as a new, distinct custom
    # drink; the source drink (preset or custom) is untouched.
    proc editor_save_copy {} {
        variable settings
        variable edit_source_id
        variable detail_id
        set d [_clean_draft]
        dict set d name [_copy_name]
        lassign [validate_drink $d] ok why
        if {!$ok} { _refresh_editor; return }
        # Pass 36/37/38: garnish, steps and group from the draft
        # (already in the clean draft).
        dict set d source custom
        set cu [_customs]
        set id [new_custom_id [dict keys $cu]]
        dict set cu $id $d
        set settings(custom) $cu
        invalidate_cache
        _persist custom_copy
        set detail_id $id
        editor_leave [edit_return_page]
    }

    # Persist caller 6 of 6: delete a custom drink (and its favorite /
    # hidden entries). Returns to the menu. Unreachable on a draft that
    # has never been saved (edit_request guards on is_custom edit_id and
    # the bottom-bar Delete button stays hidden until then).
    proc editor_delete_custom {} {
        variable settings
        variable edit_id
        variable ui_page
        if {![is_custom $edit_id]} { _refresh_editor; return }
        set cu [_customs]
        dict unset cu $edit_id
        set settings(custom) $cu
        set settings(favorites) [lsearch -all -inline -not -exact [_favorites] $edit_id]
        set settings(hidden) [lsearch -all -inline -not -exact [_hidden] $edit_id]
        invalidate_cache
        _persist custom_delete
        editor_leave DrinkMenu_main
    }

    proc editor_leave {target} {
        variable edit_dirty
        variable edit_pending
        variable edit_mode
        _hide_keyboard
        set edit_dirty 0
        set edit_pending ""
        set edit_mode layers
        _return_to_page $target
    }

    proc page_prev {} {
        variable ui_page
        variable debug_timing
        if {$debug_timing} { set _t0 [clock microseconds] }
        if {$ui_page > 1} { incr ui_page -1 }
        _refresh_current
        if {$debug_timing} { t_log page_prev [expr {[clock microseconds] - $_t0}] }
    }

    proc page_next {} {
        variable ui_page
        variable ui_tab
        variable debug_timing
        if {$debug_timing} { set _t0 [clock microseconds] }
        set n [llength [visible_drinks $ui_tab]]
        if {$ui_page < [page_count $n]} { incr ui_page }
        _refresh_current
        if {$debug_timing} { t_log page_next [expr {[clock microseconds] - $_t0}] }
    }

    # Tile tap: open the detail page for that slot's drink (size resets
    # to single). The detail page refreshes itself in its show{}.
    proc tile_tap {i} {
        variable slot_ids
        set id [lindex $slot_ids $i]
        if {$id eq ""} { return }
        # Pass 10 item 7 (log hygiene): a per-tap NOTICE fired on every
        # normal navigation with no diagnostic value beyond the save
        # NOTICEs this file already logs; removed.
        open_detail $id
    }

    # The favorite star in a tile's top-right corner (Pass 21). A new
    # ENTRY POINT to the existing toggle_favorite -> `_persist favorite`
    # caller: no new write capability, and _persist still has exactly six
    # callers. toggle_favorite refreshes the page that is showing, so the
    # star repaints in place and the star tab drops (or gains) the drink
    # on that same refresh; no page is loaded, so a tap here can never
    # navigate. There is no tap state to reset on a page switch: the slot
    # index is resolved against slot_ids, which every refresh rebuilds.
    #
    # A tap can never ALSO open the drink: the tile's own tap area is two
    # rects that leave this corner out (see the menu page's setup), and
    # this rect is created after them, so it is the topmost item under the
    # finger either way.
    proc star_tap {i} {
        variable slot_ids
        set id [lindex $slot_ids $i]
        if {$id eq ""} { return }
        toggle_favorite $id
    }

    proc open_detail {id} {
        variable drinks
        variable detail_id
        variable detail_size
        if {![drink_exists $id]} { return }
        set detail_id $id
        set detail_size single
        open_page DrinkMenu_detail
    }

    proc set_size {size} {
        variable detail_size
        if {$size ni {single double}} { return }
        set detail_size $size
        _refresh_current
        _flash_seg size [expr {$size eq "double" ? "r" : "l"}]
    }

    # Prev/next drink in the menu's current tab order, in place.
    proc detail_step {dir} {
        variable detail_id
        variable ui_tab
        lassign [detail_neighbors $detail_id [visible_drinks $ui_tab]] prev next
        set target [expr {$dir < 0 ? $prev : $next}]
        if {$target eq ""} { return }
        set detail_id $target
        _refresh_current
    }

    proc detail_back {} {
        _return_to_page DrinkMenu_main
    }

    # ------------------------------------------------------------------
    #  Navigation (MaintenanceTracker v0.21.0 mechanism, copied verbatim;
    #  only the namespace/page prefix differs)
    # ------------------------------------------------------------------

    # Public page-open entry (the cascade Lumen's taskbar expects).
    proc open_page {page} {
        foreach cmd [list \
            [list dui page open_dialog $page] \
            [list dui page load $page] \
            [list dui page show $page]] {
            if {![catch { uplevel #0 $cmd }]} { return 1 }
        }
        catch { msg "DrinkMenu: could not open page $page" }
        return 0
    }

    variable _settings_return_page ""

    proc _is_transient_name {name} {
        if {$name eq ""} { return 1 }
        return [regexp -nocase {espresso|steam|water|rinse|flush|clean|cleaning|descale|purge} $name]
    }

    # Called from the main page's show{page_to_hide page_to_show}.
    # page_to_hide is skipped when it is empty, one of this plugin's own
    # pages, or a transient flow-page name, so a flush/rinse/steam
    # interruption's re-show can never clobber the real return target.
    proc _capture_return_page {page_to_hide} {
        variable _settings_return_page
        if {$page_to_hide eq ""} { return }
        if {[string match "DrinkMenu_*" $page_to_hide]} { return }
        if {![_is_transient_name $page_to_hide]} {
            set _settings_return_page $page_to_hide
        }
    }

    proc _navigate_done {target} {
        set ok 0
        if {$target ne "" && ![_is_transient_name $target]} {
            catch { set ok [dui page exists $target] }
        }
        if {$ok} {
            if {[catch { uplevel #0 [list dui page load $target] } err]} {
                catch { msg "DrinkMenu: ERROR navigating to $target: $err" }
                catch { dui page close_dialog }
            }
        } else {
            catch { dui page close_dialog }
        }
    }

    proc page_done {} {
        variable _settings_return_page
        _navigate_done $_settings_return_page
    }

    # Returns to an ancestor page of this plugin's own dialog stack by
    # unwinding ONE close_dialog per level (the core's page_stack
    # truncation cannot unwind more than one stacked level in a single
    # load, so direct load is unsafe for stacked ancestors). Falls back
    # to _navigate_done's validated load if the stack is corrupted.
    proc _return_to_page {target} {
        set prev ""
        for {set i 0} {$i < 10} {incr i} {
            set cur ""
            catch { set cur [dui page current] }
            if {$cur eq $target} { return }
            if {![string match "DrinkMenu_*" $cur]} { break }
            if {$cur eq $prev} { break }
            set prev $cur
            if {[catch { dui page close_dialog } err]} {
                catch { msg "DrinkMenu: close_dialog failed returning to $target: $err" }
                break
            }
        }
        set cur ""
        catch { set cur [dui page current] }
        if {$cur ne $target} {
            _navigate_done $target
        }
    }

    # ------------------------------------------------------------------
    #  Page registration (called from the manifest's preload). Every step
    #  that could throw is guarded so the plugin never auto-disables; a
    #  failed page add only costs the Settings button.
    # ------------------------------------------------------------------

    proc preload_pages {} {
        if {[catch { package require de1_dui 1.0 } err]} {
            catch { msg -ERROR "DrinkMenu: de1_dui unavailable: $err" }
            return ""
        }
        catch { plugins load_settings DrinkMenu }
        # Validate whatever came off disk, in memory only (no write).
        variable settings
        variable ui_unit
        if {[catch { _validate_settings } err]} {
            catch { msg -ERROR "DrinkMenu: settings validation failed: $err" }
        }
        catch { if {$settings(unit) in {ml oz}} { set ui_unit $settings(unit) } }
        if {[catch { _init_layout } err]} {
            catch { msg -ERROR "DrinkMenu: layout init failed: $err" }
            return ""
        }
        if {[catch {
            dui page add DrinkMenu_main -namespace true -theme default -type fpdialog
        } err]} {
            catch { msg -ERROR "DrinkMenu: page add failed: $err" }
            return ""
        }
        if {[catch {
            dui page add DrinkMenu_detail -namespace true -theme default -type fpdialog
        } err]} {
            catch { msg -ERROR "DrinkMenu: detail page add failed: $err" }
        }
        if {[catch {
            dui page add DrinkMenu_edit -namespace true -theme default -type fpdialog
        } err]} {
            catch { msg -ERROR "DrinkMenu: edit page add failed: $err" }
        }
        # Name-entry keystrokes mark the draft dirty (set once).
        variable name_trace_set
        if {!$name_trace_set} {
            catch {
                trace add variable ::plugins::DrinkMenu::edit_name write ::plugins::DrinkMenu::_on_name_edit
                set name_trace_set 1
            }
        }
        return DrinkMenu_main
    }
}

# ===========================================================================
#  Menu page: header (title, subtitle, unit toggle, tab pills), 4x3 tile
#  grid, bottom bar (Done | + New drink | Hidden (N) ... < Prev | Next >).
# ===========================================================================

namespace eval ::dui::pages::DrinkMenu_main {
    variable widgets
    array set widgets {}

    # A drink used only to give every pooled slot real initial geometry
    # (refresh rebinds each slot before the page is first shown).
    variable seed_drink {name "" vessel cup layers {espresso 60}}

    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::DrinkMenu::L L
        upvar #0 ::plugins::DrinkMenu::tabs tabs
        upvar #0 ::plugins::DrinkMenu::vessels vessels
        variable seed_drink

        # This page's items are about to be (re)created: drop any cached
        # canvas ids and "already written" state for it (Pass 9).
        ::plugins::DrinkMenu::invalidate_items $page
        ::plugins::DrinkMenu::_page_bg $page
        # Pass 46: both star faces, painted now; decides star_mode for
        # the slots below (0 = the polygon carries the star).
        ::plugins::DrinkMenu::star_sprites

        set lx $L(left_x)
        set rx $L(right_x)

        # ---- Header ----
        dui add dtext $page $lx $L(header_title_y) -tags page_title \
            -text [translate "Drink Menu"] \
            -font $L(font_title) -fill $L(c_ink) -anchor w -justify left
        ::plugins::DrinkMenu::_theme_item $page page_title fill c_ink
        # Non-empty creation text (the empty-label rule); refresh sets it.
        dui add dtext $page $lx $L(header_subtitle_y) -tags subtitle \
            -text [translate "espresso drinks"] \
            -font $L(font_caption) -fill $L(c_ink_2) -anchor w -justify left
        ::plugins::DrinkMenu::_theme_item $page subtitle fill c_ink_2

        # Unit toggle: one capsule, two adjacent halves, two invisible
        # dbutton tap targets over it (Pass 12 item A3).
        ::plugins::DrinkMenu::segment_capsule $page unit \
            $L(unit_x1) $L(hdr_ctl_y0) $L(unit_x2) $L(hdr_ctl_y1) \
            [list [translate ml] [translate oz]] [list $L(font_pill) $L(font_pill)]
        set ux $L(unit_x1)
        foreach u {ml oz} {
            # No -pressfill: an invisible rect's flash never washes out
            # (the press rule in _apply_palette). The capsule's own half
            # turning gold is the feedback.
            dui add dbutton $page $ux $L(hdr_ctl_y0) [expr {$ux + $L(unit_seg_w)}] $L(hdr_ctl_y1) \
                -tags unit_$u \
                -command [list ::plugins::DrinkMenu::set_unit $u] \
                -tap_pad $L(hdr_tap_pad)
            set ux [expr {$ux + $L(unit_seg_w) + $L(seg_gap)}]
        }
        # Tab pills, right-aligned, each only as wide as its own label
        # (Pass 23 item 6: L(pill_ws), measured in _init_layout). The
        # favorites pill is an icon-only star when the FA font is
        # available, else the text "Fav".
        set px $L(pills_x1)
        set pi 0
        foreach {tab label} $tabs {
            set lbl [translate $label]
            set lfont $L(font_pill)
            set pw [lindex $L(pill_ws) $pi]
            # Pass 32: drawn polygon + label + an invisible tap rect over
            # it, the capsule's own proven shape. See pill_shape.
            ::plugins::DrinkMenu::pill_shape $page tab_$tab \
                $px $L(hdr_ctl_y0) [expr {$px + $pw}] $L(hdr_ctl_y1) $lbl $lfont
            dui add dbutton $page $px $L(hdr_ctl_y0) [expr {$px + $pw}] $L(hdr_ctl_y1) \
                -tags tab_${tab}_tap \
                -command [list ::plugins::DrinkMenu::set_tab $tab] \
                -tap_pad $L(hdr_tap_pad)
            set px [expr {$px + $pw + $L(pill_gap)}]
            incr pi
        }

        # ---- Presets-failed caption (hidden unless presets_ok is 0) ----
        dui add dtext $page $lx $L(grid_y1) -tags presets_failed \
            -text [translate "Presets failed to load"] \
            -font $L(font_body) -fill $L(c_ink_2) -anchor nw -justify left \
            -initial_state hidden
        ::plugins::DrinkMenu::_theme_item $page presets_failed fill c_ink_2
        # ---- Empty-tab caption (favorites / custom / hidden views) ----
        dui add dtext $page $lx $L(empty_caption_y) -tags empty_caption \
            -text [translate "No drinks"] \
            -font $L(font_body) -fill $L(c_ink_2) -anchor nw -justify left \
            -initial_state hidden
        ::plugins::DrinkMenu::_theme_item $page empty_caption fill c_ink_2

        # ---- Tile pool: 12 slots, created once ----
        set seed $seed_drink
        if {![dict exists $vessels cup]} {
            # Presets missing: any pool still needs a vessel to exist.
            set seed {}
        }
        set n [expr {$L(grid_cols) * $L(grid_rows)}]
        for {set i 0} {$i < $n} {incr i} {
            if {[catch {
                set col [expr {$i % $L(grid_cols)}]
                set row [expr {$i / $L(grid_cols)}]
                set tx [expr {$lx + $col * ($L(tile_w) + $L(grid_gap))}]
                set ty [expr {$L(grid_y1) + $row * ($L(tile_h) + $L(grid_gap))}]
                set tx2 [expr {$tx + $L(tile_w)}]
                set ty2 [expr {$ty + $L(tile_h)}]
                set tcx [expr {$tx + $L(tile_w) / 2}]
                ::plugins::DrinkMenu::glass_card $page tile$i $tx $ty $L(tile_w) $L(tile_h) "" 1 tile
                if {$seed ne ""} {
                    ::plugins::DrinkMenu::draw_cup $page tile${i}_cup \
                        [expr {$tx + $L(tile_cup_x1)}] [expr {$ty + $L(tile_cup_y1)}] \
                        [expr {$L(tile_cup_x2) - $L(tile_cup_x1)}] \
                        [expr {$L(tile_cup_y2) - $L(tile_cup_y1)}] $seed 1 tile
                }
                # ml badge, back in the tile's TOP-RIGHT corner (Pass 23
                # item 2) and now a FULL pill: an exact stadium polygon from
                # _capsule_points, because a -smooth 1 rounded rect clamps
                # its control radius at half the height and then renders
                # half of that, so it can never reach a half-height cap.
                # Bold caption in the mock's gold at full strength, on the
                # black .38 well with its gold .35 hairline.
                set cx1 [expr {$tx + $L(tile_badge_x1)}]
                set cy1 [expr {$ty + $L(tile_badge_y1)}]
                set cx2 [expr {$tx + $L(tile_badge_x2)}]
                set cy2 [expr {$ty + $L(tile_badge_y2)}]
                # Pass 43: the badge is a shape (cap photos + flat body).
                ::plugins::DrinkMenu::shape_make $page tile${i}_chip_bg $cx1 $cy1 $cx2 $cy2 \
                    $L(chip_radius) chip_bg chip_brd -kind chip
                dui add dtext $page [expr {($cx1 + $cx2) / 2}] [expr {($cy1 + $cy2) / 2}] \
                    -tags tile${i}_chip_txt -text "0 ml" \
                    -font $L(font_caption_b) -fill $L(c_crema) -anchor center -justify center
                ::plugins::DrinkMenu::_theme_item $page tile${i}_chip_txt fill c_crema
                # Name, bottom center.
                dui add dtext $page $tcx [expr {$ty2 - $L(tile_name_dy)}] -tags tile${i}_name \
                    -text "-" -font $L(font_primary) -fill $L(c_ink) -anchor s -justify center
                ::plugins::DrinkMenu::_theme_item $page tile${i}_name fill c_ink
                # Favorite star, TOP-LEFT corner of the tile since Pass 23
                # (item 4 -- the mock puts `.tile .star` at top 8 / left 11
                # CSS px, and it is half the size v0.12.1 drew), shown on
                # EVERY bound slot: solid gold when the drink is a favorite,
                # an empty
                # outline when it is not. Since Pass 22 it is a DRAWN
                # five-point polygon rather than an icon glyph, because
                # the app ships no Solid weight of the icon font and the
                # Regular face can only draw the star hollow. The vertices
                # come from L(tile_star_pts) (offsets from the star's
                # centre, built once in _init_layout) and are handed to
                # `dui add canvas_item` in VIRTUAL units, exactly as every
                # cup polygon is -- one rescale path, no raw canvas create,
                # so the item carries the page tag and the initial-state
                # handling the old text item had (visible from the start,
                # no -initial_state). Its face (fill + outline) is written
                # by refresh through star_face, so it is deliberately NOT
                # registered for _retheme -- the palette reaches it because
                # _apply_palette drops the fill cache and the refresh that
                # follows every show rewrites it.
                set _spts {}
                foreach {_sox _soy} $L(tile_star_pts) {
                    lappend _spts [expr {$tx + $L(tile_star_cx) + $_sox}] \
                        [expr {$ty + $L(tile_star_cy) + $_soy}]
                }
                lassign [::plugins::DrinkMenu::star_face 0] _sfill _sout
                # Pass 46: in sprite mode the polygon is the hidden
                # fallback and an image item (the OFF face photo, swapped
                # by star_paint) sits at the star's own centre.
                set _smode $::plugins::DrinkMenu::star_mode
                dui add canvas_item polygon $page {*}$_spts \
                    -fill $_sfill -outline $_sout -width $L(stroke_w) \
                    -tags tile${i}_star \
                    {*}[expr {$_smode ? [list -initial_state hidden] : {}}]
                if {$_smode} {
                    lassign [::plugins::DrinkMenu::star_sprite_offset] _sox _soy
                    dui add canvas_item image $page \
                        [::plugins::DrinkMenu::_spx $tx $_sox] [::plugins::DrinkMenu::_spy $ty $_soy] \
                        -image [::plugins::DrinkMenu::star_photo 0] -anchor nw \
                        -tags tile${i}_starimg
                }
                # Pen marker: custom drinks only (presets are read-only).
                dui add dtext $page [expr {$tx + $L(tile_pen_dx)}] [expr {$ty + $L(tile_pen_dy)}] \
                    -tags tile${i}_pen -text $L(glyph_pen) -font $L(glyph_font_pen) \
                    -fill $L(crema_text) -anchor nw -justify left -initial_state hidden
                ::plugins::DrinkMenu::_theme_item $page tile${i}_pen fill crema_text
                # Invisible tile tap target. Pass 21 split the old
                # full-tile rect into the two rects that make up the tile
                # MINUS the star's corner; Pass 23 moved the star to the
                # TOP-LEFT, so those two rects are now the rest of the top
                # band and everything below it. The two together still cover
                # every pixel of the tile the star does not own, so the tile
                # handler can never receive a point inside the star box --
                # no coordinate test, no tap bookkeeping, and no reliance on
                # which item Tk picks.
                dui add dbutton $page [expr {$tx + $L(tile_star_x2)}] $ty \
                    $tx2 [expr {$ty + $L(tile_star_y2)}] \
                    -tags tile${i}_tap \
                    -command [list ::plugins::DrinkMenu::tile_tap $i]
                dui add dbutton $page $tx [expr {$ty + $L(tile_star_y2)}] $tx2 $ty2 \
                    -tags tile${i}_tap2 \
                    -command [list ::plugins::DrinkMenu::tile_tap $i]
                # The star's own tap target, created LAST so it is also
                # the topmost item of the slot (belt and braces: the two
                # rects above already exclude this box).
                dui add dbutton $page [expr {$tx + $L(tile_star_x1)}] [expr {$ty + $L(tile_star_y1)}] \
                    [expr {$tx + $L(tile_star_x2)}] [expr {$ty + $L(tile_star_y2)}] \
                    -tags tile${i}_startap \
                    -command [list ::plugins::DrinkMenu::star_tap $i]
            } err]} {
                catch { msg -ERROR "DrinkMenu: tile slot $i setup failed: $err" }
            }
        }

        # ---- Bottom bar: Done, + New drink, Hidden (N) left;
        #      "< Prev", "Next >" right (Pass 13) ----
        # Pass 23 item 8: Done is the menu's primary action, so it wears the
        # mock's `.btn` -- gold fill, gold-ink label. Every other bar button
        # on this page stays ghost.
        # Pass 45: Done is navigation, so it is a ghost; the gold goes to
        # the page's one creative action, "+ New drink".
        ::plugins::DrinkMenu::bar_button $page bar_done \
            $lx $L(bar_y0) [expr {$lx + $L(btn_w_std)}] $L(bar_y1) btn \
            -label [translate "Done"] \
            -command ::plugins::DrinkMenu::page_done \
            -label_font $L(font_button)
        # "+ New drink": a new ENTRY POINT to the editor's existing
        # confirmed custom save, not a new write capability.
        ::plugins::DrinkMenu::bar_button $page bar_new \
            $L(bar_new_x1) $L(bar_y0) $L(bar_new_x2) $L(bar_y1) primary \
            -label [translate "+ New drink"] \
            -command ::plugins::DrinkMenu::new_drink_tap \
            -label_font $L(font_button)
        ::plugins::DrinkMenu::bar_button $page bar_hidden \
            $L(bar_hidden_x1) $L(bar_y0) $L(bar_hidden_x2) $L(bar_y1) btn \
            -label [translate "Hidden"] \
            -command ::plugins::DrinkMenu::show_hidden \
            -label_font $L(font_button) -initial_state hidden
        # Chevron + word: -label is the text, -label1 the chevron in the
        # icon font (with the ASCII "<" / ">" fallback and the button
        # font when the FA font is unavailable). One canvas text item
        # carries one font, so the two cannot be a single label.
        ::plugins::DrinkMenu::bar_button $page bar_prev \
            $L(bar_prev_x1) $L(bar_y0) \
            [expr {$L(bar_prev_x1) + $L(btn_w_std)}] $L(bar_y1) btn \
            -label [translate "Prev"] \
            -command ::plugins::DrinkMenu::page_prev \
            -label_font $L(font_button) -label_pos $L(bar_prev_lbl_pos) \
            -label1 $L(glyph_chev_l) -label1_font $L(glyph_font_chev_l) \
            -label1_pos $L(bar_prev_sym_pos) -label1_fill $L(btn_label) \
            -initial_state hidden
        ::plugins::DrinkMenu::bar_button $page bar_next \
            $L(bar_next_x1) $L(bar_y0) $rx $L(bar_y1) btn \
            -label [translate "Next"] \
            -command ::plugins::DrinkMenu::page_next \
            -label_font $L(font_button) -label_pos $L(bar_next_lbl_pos) \
            -label1 $L(glyph_chev_r) -label1_font $L(glyph_font_chev_r) \
            -label1_pos $L(bar_next_sym_pos) -label1_fill $L(btn_label) \
            -initial_state hidden
        # Pass 48: the page position beside the paging buttons (the
        # subtitle keeps it too); hidden on a one-page tab.
        dui add dtext $page $L(bar_page_x) [expr {($L(bar_y0) + $L(bar_y1)) / 2}] -tags bar_page \
            -text "1 / 1" -font $L(font_caption) -fill $L(c_ink_2) -anchor e -justify right \
            -initial_state hidden
        ::plugins::DrinkMenu::_theme_item $page bar_page fill c_ink_2

        # Bind the pool to page 1 of the All tab so the first show is
        # right even before show{} runs (items are drawn before it).
        if {[catch { refresh } err]} {
            catch { msg -ERROR "DrinkMenu: initial refresh failed: $err" }
        }
    }

    # Binds every slot, chip, name, pill face and Prev/Next to the
    # current tab/page/unit. Creates nothing.
    proc refresh {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::DrinkMenu::L L
        upvar #0 ::plugins::DrinkMenu::tabs tabs
        upvar #0 ::plugins::DrinkMenu::drinks drinks
        upvar #0 ::plugins::DrinkMenu::ui_tab ui_tab
        upvar #0 ::plugins::DrinkMenu::ui_page ui_page
        upvar #0 ::plugins::DrinkMenu::ui_unit ui_unit
        upvar #0 ::plugins::DrinkMenu::presets_ok presets_ok
        upvar #0 ::plugins::DrinkMenu::slot_ids slot_ids
        upvar #0 ::plugins::DrinkMenu::page_size page_size
        upvar #0 ::plugins::DrinkMenu::debug_timing debug_timing

        set _dbg $debug_timing
        if {$_dbg} {
            ::plugins::DrinkMenu::t_reset
            set _t_all [clock microseconds]
            set _t $_t_all
        }
        set ids [::plugins::DrinkMenu::visible_drinks $ui_tab]
        if {$_dbg} {
            ::plugins::DrinkMenu::t_add visible_drinks [expr {[clock microseconds] - $_t}]
            set _t [clock microseconds]
        }
        set n [llength $ids]
        set pages [::plugins::DrinkMenu::page_count $n]
        if {$ui_page > $pages} { set ui_page $pages }
        if {$ui_page < 1} { set ui_page 1 }

        # Header. The hidden view names itself; pills show no active
        # state there.
        if {$ui_tab eq "hidden"} {
            ::plugins::DrinkMenu::_set_text $page subtitle \
                "$n [expr {$n == 1 ? [translate "hidden drink"] : [translate "hidden drinks"]}], [translate "page"] $ui_page [translate "of"] $pages"
        } else {
            ::plugins::DrinkMenu::_set_text $page subtitle \
                "$n [expr {$n == 1 ? [translate "espresso drink"] : [translate "espresso drinks"]}], [translate "page"] $ui_page [translate "of"] $pages"
        }
        ::plugins::DrinkMenu::_paint_controls $page

        # Presets failure caption; empty-tab caption.
        ::plugins::DrinkMenu::_show_tags $page presets_failed [expr {!$presets_ok}]
        upvar #0 ::plugins::DrinkMenu::empty_captions empty_captions
        if {$presets_ok && $n == 0 && [dict exists $empty_captions $ui_tab]} {
            ::plugins::DrinkMenu::_set_text $page empty_caption [translate [dict get $empty_captions $ui_tab]]
            ::plugins::DrinkMenu::_show_tags $page empty_caption 1
        } else {
            ::plugins::DrinkMenu::_show_tags $page empty_caption 0
        }

        # "Hidden (N)" beside Done, only while something is hidden.
        set nhidden [llength [::plugins::DrinkMenu::_hidden]]
        if {$nhidden > 0} {
            # A dbutton relabel needs the BARE tag through dui (the
            # wildcard form silently fails on-device); it is the one dui
            # call left in the refresh path, so only make it when the
            # label actually changes.
            set lbl "[translate "Hidden"] ($nhidden)"
            upvar #0 ::plugins::DrinkMenu::text_cache text_cache
            if {![info exists text_cache($page,bar_hidden-lbl)] \
                    || $text_cache($page,bar_hidden-lbl) ne $lbl} {
                catch { dui item config $page bar_hidden -label $lbl }
                set text_cache($page,bar_hidden-lbl) $lbl
            }
            ::plugins::DrinkMenu::_show_tags $page bar_hidden* 1
        } else {
            ::plugins::DrinkMenu::_show_tags $page bar_hidden* 0
        }

        if {$_dbg} {
            ::plugins::DrinkMenu::t_add header [expr {[clock microseconds] - $_t}]
            set _t [clock microseconds]
        }

        # Slots.
        set slot_ids {}
        set first [expr {($ui_page - 1) * $page_size}]
        set maxw [expr {int(($L(tile_w) - 2 * $L(card_pad_x)) * $L(v2px))}]
        for {set i 0} {$i < $page_size} {incr i} {
            set idx [expr {$first + $i}]
            if {$idx < $n && $presets_ok} {
                set id [lindex $ids $idx]
                set d [::plugins::DrinkMenu::get_drink $id]
                lappend slot_ids $id
                if {[catch {
                    # Show the whole slot first, then let update_cup hide
                    # the layers/handle/stem this drink does not use.
                    if {$_dbg} { set _a [clock microseconds] }
                    ::plugins::DrinkMenu::_show_slot $page $i 1
                    if {$_dbg} {
                        ::plugins::DrinkMenu::t_add show_slot [expr {[clock microseconds] - $_a}]
                        set _a [clock microseconds]
                    }
                    ::plugins::DrinkMenu::update_cup $page tile${i}_cup $d
                    if {$_dbg} {
                        ::plugins::DrinkMenu::t_add update_cup [expr {[clock microseconds] - $_a}]
                        set _a [clock microseconds]
                    }
                    lassign [::plugins::DrinkMenu::fit_tile_name \
                        [translate [dict get $d name]] $maxw] _name _name_font
                    if {$_dbg} {
                        ::plugins::DrinkMenu::t_add fit_text [expr {[clock microseconds] - $_a}]
                        set _a [clock microseconds]
                    }
                    ::plugins::DrinkMenu::_set_text $page tile${i}_name $_name
                    ::plugins::DrinkMenu::_set_font $page tile${i}_name $_name_font
                    ::plugins::DrinkMenu::_set_text $page tile${i}_chip_txt \
                        [::plugins::DrinkMenu::format_amount [::plugins::DrinkMenu::drink_total $d] $ui_unit]
                    if {$_dbg} {
                        ::plugins::DrinkMenu::t_add set_text [expr {[clock microseconds] - $_a}]
                        set _a [clock microseconds]
                    }
                    # The star is always shown (it is a control now); its
                    # FACE says whether the drink is a favorite. Since
                    # Pass 22 the star is a polygon, so one cache-guarded
                    # write of the {fill outline} pair says everything the
                    # three text writes used to: a slot whose state did
                    # not change still costs nothing.
                    ::plugins::DrinkMenu::star_paint $page $i [::plugins::DrinkMenu::is_favorite $id]
                    ::plugins::DrinkMenu::_show_tags $page tile${i}_pen [::plugins::DrinkMenu::is_custom $id]
                    if {$_dbg} {
                        ::plugins::DrinkMenu::t_add badges [expr {[clock microseconds] - $_a}]
                    }
                } err]} {
                    catch { msg -ERROR "DrinkMenu: slot $i bind ($id) failed: $err" }
                }
            } else {
                lappend slot_ids ""
                if {$_dbg} { set _a [clock microseconds] }
                ::plugins::DrinkMenu::_show_slot $page $i 0
                if {$_dbg} { ::plugins::DrinkMenu::t_add show_slot [expr {[clock microseconds] - $_a}] }
            }
        }
        if {$_dbg} { set _t [clock microseconds] }

        # Paging buttons: hidden at the ends (no greyed style exists).
        ::plugins::DrinkMenu::_show_tags $page bar_prev* [expr {$ui_page > 1}]
        ::plugins::DrinkMenu::_show_tags $page bar_next* [expr {$ui_page < $pages}]
        ::plugins::DrinkMenu::_set_text $page bar_page "$ui_page / $pages"
        ::plugins::DrinkMenu::_show_tags $page bar_page [expr {$pages > 1}]
        if {$_dbg} {
            ::plugins::DrinkMenu::t_add paging [expr {[clock microseconds] - $_t}]
            ::plugins::DrinkMenu::t_log refresh_grid [expr {[clock microseconds] - $_t_all}]
            ::plugins::DrinkMenu::t_dump {visible_drinks header show_slot update_cup cup_calc fit_text set_text badges paging}
        }
    }

    proc show {page_to_hide page_to_show} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::DrinkMenu::debug_timing debug_timing
        set _dbg $debug_timing
        if {$_dbg} { set _t0 [clock microseconds] }
        ::plugins::DrinkMenu::glass_log
        ::plugins::DrinkMenu::_capture_return_page $page_to_hide
        # Palette follows the skin's current tokens on every show, then
        # the grid rebinds (update_cup re-applies palette-derived colors).
        if {[catch {
            ::plugins::DrinkMenu::_apply_palette
            ::plugins::DrinkMenu::_retheme $page
            refresh
        } err]} {
            catch { msg -ERROR "DrinkMenu: show repaint failed: $err" }
        }
        ::plugins::DrinkMenu::cup_log
        ::plugins::DrinkMenu::mark_log
        if {$_dbg} { ::plugins::DrinkMenu::t_log show [expr {[clock microseconds] - $_t0}] }
    }
}

# ===========================================================================
#  Detail page: hero cup with labeled layers (left), totals + ratio card
#  and ingredient chips (right), Back | Prev drink, Next drink.
# ===========================================================================

namespace eval ::dui::pages::DrinkMenu_detail {
    variable widgets
    array set widgets {}

    variable seed_drink {name "" vessel cup layers {espresso 60}}

    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::DrinkMenu::L L
        upvar #0 ::plugins::DrinkMenu::vessels vessels
        variable seed_drink

        # This page's items are about to be (re)created: drop any cached
        # canvas ids and "already written" state for it (Pass 9).
        ::plugins::DrinkMenu::invalidate_items $page
        ::plugins::DrinkMenu::_page_bg $page
        # Pass 46: the ink dot, painted now; decides dot_mode for the
        # chips below (0 = the ovals carry the dots).
        ::plugins::DrinkMenu::dot_sprites
        set lx $L(left_x)
        set rx $L(right_x)

        # ---- Header ----
        dui add dtext $page $lx $L(header_title_y) -tags det_title \
            -text [translate "Drink"] \
            -font $L(font_title) -fill $L(c_ink) -anchor w -justify left
        ::plugins::DrinkMenu::_theme_item $page det_title fill c_ink
        dui add dtext $page $lx $L(header_subtitle_y) -tags det_subtitle \
            -text [translate "Vessel"] \
            -font $L(font_caption) -fill $L(c_ink_2) -anchor w -justify left
        ::plugins::DrinkMenu::_theme_item $page det_subtitle fill c_ink_2
        # Both header toggles are capsules (Pass 12 item A3): the drawn
        # shapes carry the state, the dbuttons are invisible tap targets.
        ::plugins::DrinkMenu::segment_capsule $page unit \
            $L(det_unit_x1) $L(hdr_ctl_y0) $L(det_unit_x2) $L(hdr_ctl_y1) \
            [list [translate ml] [translate oz]] [list $L(font_pill) $L(font_pill)]
        set ux $L(det_unit_x1)
        foreach u {ml oz} {
            # No -pressfill (the press rule in _apply_palette).
            dui add dbutton $page $ux $L(hdr_ctl_y0) [expr {$ux + $L(unit_seg_w)}] $L(hdr_ctl_y1) \
                -tags unit_$u \
                -command [list ::plugins::DrinkMenu::set_unit $u] \
                -tap_pad $L(hdr_tap_pad)
            set ux [expr {$ux + $L(unit_seg_w) + $L(seg_gap)}]
        }
        ::plugins::DrinkMenu::segment_capsule $page size \
            $L(det_size_x1) $L(hdr_ctl_y0) $L(det_size_x2) $L(hdr_ctl_y1) \
            [list [translate "1 shot"] [translate "2 shots"]] [list $L(font_pill) $L(font_pill)]
        set sx $L(det_size_x1)
        foreach s {single double} {
            # No -pressfill (the press rule in _apply_palette).
            dui add dbutton $page $sx $L(hdr_ctl_y0) [expr {$sx + $L(det_seg_w)}] $L(hdr_ctl_y1) \
                -tags size_$s \
                -command [list ::plugins::DrinkMenu::set_size $s] \
                -tap_pad $L(hdr_tap_pad)
            set sx [expr {$sx + $L(det_seg_w) + $L(seg_gap)}]
        }

        # ---- Hero card: cup + label column + garnish ----
        if {[catch {
            # The hero keeps the mock's own, rounder corner (.hero: 22 CSS
            # px = 29 ref px), the one card that differs from the rest.
            ::plugins::DrinkMenu::glass_card $page hero $L(det_hero_x1) $L(det_hero_y1) \
                $L(det_hero_w) [expr {$L(det_hero_y2) - $L(det_hero_y1)}] $L(hero_radius) 1 hero
            if {[dict exists $vessels cup]} {
                # Pass 18: the box is per vessel (hero_cup_box). Any seed
                # is fine here -- the detail refresh re-boxes the pool for
                # the drink actually shown before update_cup.
                lassign [::plugins::DrinkMenu::hero_cup_box [dict get $seed_drink vessel]] \
                    hcx hcy hcw hch
                ::plugins::DrinkMenu::draw_cup $page hero_cup $hcx $hcy $hcw $hch $seed_drink 0 hero
                # Pass 19: the ghosted part of the handle ring, ONE
                # pooled arc. Created HERE, immediately after draw_cup,
                # so it paints over the ring (hero_cup_handle) and under
                # the leaders and the labels that follow. It starts
                # hidden (the page-show flash trap: a page load re-shows
                # every item that was not created hidden, before show{}
                # runs) and update_hero_ring_dim writes its bbox, its
                # angles and its visibility on every detail refresh.
                # `-arc_style arc` is dui's pass-through for Tk's own
                # `-style arc` (dui.tcl ~9548); a plain `-style` would be
                # eaten as a dui aspect style.
                dui add canvas_item arc $page $L(det_cup_x1) $L(det_cup_y1) \
                    [expr {$L(det_cup_x1) + 1}] [expr {$L(det_cup_y1) + 1}] \
                    -arc_style arc -start 0 -extent 90 -fill {} \
                    -outline $L(ring_dim) -width $L(stroke_w) \
                    -tags hero_cup_handle_dim -initial_state hidden
                ::plugins::DrinkMenu::_theme_item $page hero_cup_handle_dim outline ring_dim
            }
            set ly $L(det_label_top)
            for {set i 0} {$i < $L(det_label_pool)} {incr i} {
                dui add canvas_item line $page $L(det_cup_x2) $ly [expr {$L(det_label_x) - $L(xs)}] $ly \
                    -fill $L(leader) -width $L(det_lead_w) -tags lead$i -initial_state hidden
                ::plugins::DrinkMenu::_theme_item $page lead$i fill leader
                dui add dtext $page $L(det_label_x) $ly -tags lbl${i}_name -text "-" \
                    -font $L(font_body) -fill $L(c_ink) -anchor sw -justify left -initial_state hidden
                ::plugins::DrinkMenu::_theme_item $page lbl${i}_name fill c_ink
                dui add dtext $page $L(det_label_x) $ly -tags lbl${i}_amt -text "-" \
                    -font $L(font_caption) -fill $L(crema_text) -anchor nw -justify left -initial_state hidden
                ::plugins::DrinkMenu::_theme_item $page lbl${i}_amt fill crema_text
            }
            dui add dtext $page [expr {$L(det_hero_x1) + $L(card_pad_x)}] $L(det_garnish_y) \
                -tags det_garnish -text [translate "Garnish"] \
                -font $L(font_caption) -fill $L(c_ink_2) -anchor sw -justify left -initial_state hidden
            ::plugins::DrinkMenu::_theme_item $page det_garnish fill c_ink_2
        } err]} {
            catch { msg -ERROR "DrinkMenu: detail hero setup failed: $err" }
        }

        # ---- Totals card ----
        if {[catch {
            ::plugins::DrinkMenu::glass_card $page tot $L(det_right_x1) $L(det_tot_y1) \
                $L(det_right_w) $L(det_tot_h)
            set tx [expr {$L(det_right_x1) + $L(card_pad_x)}]
            dui add dtext $page $tx $L(det_tot_fig_y) -tags tot_fig -text "0" \
                -font $L(font_title) -fill $L(crema_text) -anchor w -justify left
            ::plugins::DrinkMenu::_theme_item $page tot_fig fill crema_text
            dui add dtext $page $tx $L(det_tot_cap_y) -tags tot_cap -text [translate "ml total"] \
                -font $L(font_caption) -fill $L(c_ink_2) -anchor w -justify left
            ::plugins::DrinkMenu::_theme_item $page tot_cap fill c_ink_2
            dui add dtext $page $L(det_ratio_x) $L(det_tot_fig_y) -tags tot_ratio -text "-" \
                -font $L(font_primary) -fill $L(c_ink) -anchor w -justify left
            ::plugins::DrinkMenu::_theme_item $page tot_ratio fill c_ink
            dui add dtext $page $L(det_ratio_x) $L(det_tot_cap_y) -tags tot_names -text "-" \
                -font $L(font_caption) -fill $L(c_ink_2) -anchor w -justify left
            ::plugins::DrinkMenu::_theme_item $page tot_names fill c_ink_2
            # Pass 10 item 3: pooled second line, shown only when the
            # ratio names overflow one line (e.g. Borgia's four names).
            dui add dtext $page $L(det_ratio_x) $L(det_tot_names2_y) -tags tot_names2 -text "" \
                -font $L(font_caption) -fill $L(c_ink_2) -anchor w -justify left -initial_state hidden
            ::plugins::DrinkMenu::_theme_item $page tot_names2 fill c_ink_2
            # Pass 40: the one DE1 tie-in button, on the bottom bar's
            # free stretch between Back and Favorite; shown only for
            # drinks that define something to apply (a linked profile
            # and/or a hot_water layer). Ghost style: its static fill
            # keeps the core press flash safe.
            ::plugins::DrinkMenu::bar_button $page det_mach \
                $L(det_mach_x1) $L(bar_y0) $L(det_mach_x2) $L(bar_y1) btn \
                -label [translate "To machine"] \
                -command ::plugins::DrinkMenu::to_machine_tap \
                -label_font $L(font_button) -initial_state hidden
        } err]} {
            catch { msg -ERROR "DrinkMenu: detail totals setup failed: $err" }
        }

        # ---- Ingredients card: chip pool ----
        if {[catch {
            ::plugins::DrinkMenu::glass_card $page ing $L(det_right_x1) $L(det_ing_y1) \
                $L(det_right_w) [expr {$L(det_ing_y2) - $L(det_ing_y1)}]
            set cx $L(det_ing_inner_x)
            set cy $L(det_ing_inner_y)
            set ch $L(det_chip_h)
            for {set i 0} {$i < $L(det_chip_pool)} {incr i} {
                # Pass 23 item 7: the mock's `.chip` is a full pill, so the
                # backdrop is an exact stadium polygon (_capsule_points),
                # not a smoothed rounded rect. Creation and refresh use the
                # SAME builder, so the item always has the same vertex count.
                # Pass 43: the chip is a shape; created three chip-heights
                # wide (hidden) so its cap radius is the full one, then
                # re-laid to the fitted width by shape_move at refresh.
                ::plugins::DrinkMenu::shape_make $page chip${i}_bg $cx $cy [expr {$cx + 3 * $ch}] [expr {$cy + $ch}] \
                    $L(det_chip_radius) chip_bg chip_bg -kind chip -initial hidden
                # Pass 46: the dot is a sprite (draw_dot: the oval stays
                # as the hidden fallback), recoloured by dot_paint.
                ::plugins::DrinkMenu::draw_dot $page chip${i}_dot $cx $cy $L(c_ink)
                dui add dtext $page $cx $cy -tags chip${i}_name -text "-" \
                    -font $L(font_body) -fill $L(c_ink) -anchor w -justify left -initial_state hidden
                ::plugins::DrinkMenu::_theme_item $page chip${i}_name fill c_ink
                dui add dtext $page $cx $cy -tags chip${i}_amt -text "-" \
                    -font $L(font_body_b) -fill $L(crema_text) -anchor w -justify left -initial_state hidden
                ::plugins::DrinkMenu::_theme_item $page chip${i}_amt fill crema_text
            }
        } err]} {
            catch { msg -ERROR "DrinkMenu: detail chips setup failed: $err" }
        }

        # ---- Method card: numbered steps (Pass 14) ----
        # Everything is pooled and created HERE, at setup: the four line
        # pairs and the empty-state caption start hidden through
        # -initial_state hidden (the page-show flash trap: a page load
        # re-shows every item that was not created hidden, before show{}
        # runs). refresh only writes text and flips visibility.
        if {[catch {
            ::plugins::DrinkMenu::glass_card $page met $L(det_right_x1) $L(det_met_y1) \
                $L(det_right_w) [expr {$L(det_met_y2) - $L(det_met_y1)}]
            dui add dtext $page $L(det_met_num_x) $L(det_met_title_y) -tags met_title \
                -text [translate "Method"] \
                -font $L(font_section) -fill $L(c_ink) -anchor w -justify left
            ::plugins::DrinkMenu::_theme_item $page met_title fill c_ink
            for {set i 0} {$i < $L(det_met_pool)} {incr i} {
                set my [expr {$L(det_met_line_y) + $i * $L(det_met_pitch)}]
                dui add dtext $page $L(det_met_num_x) $my -tags met${i}_num -text [expr {$i + 1}] \
                    -font $L(font_caption) -fill $L(ink_3_text) -anchor w -justify left -initial_state hidden
                ::plugins::DrinkMenu::_theme_item $page met${i}_num fill ink_3_text
                dui add dtext $page $L(det_met_text_x) $my -tags met${i}_text -text "-" \
                    -font $L(font_caption) -fill $L(c_ink) -anchor w -justify left -initial_state hidden
                ::plugins::DrinkMenu::_theme_item $page met${i}_text fill c_ink
            }
            dui add dtext $page $L(det_met_text_x) $L(det_met_line_y) -tags met_none \
                -text [translate "No method saved."] \
                -font $L(font_caption) -fill $L(c_ink_2) -anchor w -justify left -initial_state hidden
            ::plugins::DrinkMenu::_theme_item $page met_none fill c_ink_2
            # Pass 48: on a custom drink with no steps the caption reads
            # "Add a method" in gold and this invisible rect over it opens
            # the editor's method mode (refresh decides both).
            dui add dbutton $page $L(det_met_text_x) [expr {$L(det_met_line_y) - $L(lg)}] \
                [expr {$L(det_met_text_x) + $L(det_met_add_w)}] [expr {$L(det_met_line_y) + $L(lg)}] \
                -tags met_add_tap -command ::plugins::DrinkMenu::method_add_tap -initial_state hidden
        } err]} {
            catch { msg -ERROR "DrinkMenu: detail method setup failed: $err" }
        }

        # ---- Bottom bar: Back left; Favorite, Hide, Edit/Copy & edit,
        # < > right ----
        ::plugins::DrinkMenu::bar_button $page bar_back \
            $lx $L(bar_y0) [expr {$lx + $L(btn_w_std)}] $L(bar_y1) btn \
            -label [translate "Back"] \
            -command ::plugins::DrinkMenu::detail_back \
            -label_font $L(font_button)
        # Favorite / Hide: real initial labels (the empty-label rule);
        # refresh relabels them through the bare dbutton tag.
        # Pass 48: the Favorite button carries the star sprite (both
        # faces painted now, at fav_star_scale) and a FIXED label; the
        # state lives in the icon, the verb in the label. Without the
        # photos (refused PNG) the label sits centred as before.
        set fav_icon [::plugins::DrinkMenu::star_photo 0 $::plugins::DrinkMenu::fav_star_scale]
        ::plugins::DrinkMenu::star_photo 1 $::plugins::DrinkMenu::fav_star_scale
        ::plugins::DrinkMenu::bar_button $page bar_fav \
            $L(det_fav_x1) $L(bar_y0) [expr {$L(det_fav_x1) + $L(det_fav_w)}] $L(bar_y1) btn \
            -label [translate "Favorite"] \
            -command ::plugins::DrinkMenu::favorite_tap \
            -label_font $L(font_button) \
            {*}[expr {$fav_icon ne "" ? [list -icon $fav_icon -icon_pos $L(fav_icon_pos) -label_pos $L(fav_label_pos)] : {}}]
        ::plugins::DrinkMenu::bar_button $page bar_hide \
            $L(det_hide_x1) $L(bar_y0) [expr {$L(det_hide_x1) + $L(det_hide_w)}] $L(bar_y1) btn \
            -label [translate "Hide"] \
            -command ::plugins::DrinkMenu::hide_tap \
            -label_font $L(font_button)
        # Pass 12 item B3: the detail page's main action is the one
        # filled button; Back / Favorite / Hide / chevrons stay ghost.
        ::plugins::DrinkMenu::bar_button $page bar_edit \
            $L(det_edit_x1) $L(bar_y0) [expr {$L(det_edit_x1) + $L(btn_w_std)}] $L(bar_y1) primary \
            -label [translate "Edit"] \
            -command ::plugins::DrinkMenu::edit_tap \
            -label_font $L(font_button)
        # Square chevron-only Prev / Next (icon font, "<" ">" fallbacks).
        ::plugins::DrinkMenu::bar_button $page bar_prev \
            $L(det_prev_x1) $L(bar_y0) [expr {$L(det_prev_x1) + $L(btn_sq)}] $L(bar_y1) btn \
            -label $L(glyph_chev_l) \
            -command [list ::plugins::DrinkMenu::detail_step -1] \
            -label_font $L(glyph_font_chev_l) -initial_state hidden
        ::plugins::DrinkMenu::bar_button $page bar_next \
            $L(det_next_x1) $L(bar_y0) $rx $L(bar_y1) btn \
            -label $L(glyph_chev_r) \
            -command [list ::plugins::DrinkMenu::detail_step 1] \
            -label_font $L(glyph_font_chev_r) -initial_state hidden
    }

    # Repopulates every pooled item from detail_id + detail_size + unit.
    # Creates nothing. Any failure is caught by the caller; Back is a
    # static dbutton and stays reachable regardless.
    proc refresh {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::DrinkMenu::L L
        upvar #0 ::plugins::DrinkMenu::drinks drinks
        upvar #0 ::plugins::DrinkMenu::vessels vessels
        upvar #0 ::plugins::DrinkMenu::ingredients ingredients
        upvar #0 ::plugins::DrinkMenu::detail_id detail_id
        upvar #0 ::plugins::DrinkMenu::detail_size detail_size
        upvar #0 ::plugins::DrinkMenu::ui_unit ui_unit
        upvar #0 ::plugins::DrinkMenu::ui_tab ui_tab
        namespace import -force ::plugins::DrinkMenu::_set_text ::plugins::DrinkMenu::_show_tags \
            ::plugins::DrinkMenu::_move_item ::plugins::DrinkMenu::_fit_text \
            ::plugins::DrinkMenu::format_amount ::plugins::DrinkMenu::_text_w \
            ::plugins::DrinkMenu::_ids

        set d0 [::plugins::DrinkMenu::get_drink $detail_id]
        if {$d0 eq ""} {
            _set_text $page det_title [translate "No drink selected"]
            _set_text $page det_subtitle ""
            return
        }
        set d [::plugins::DrinkMenu::sized_drink $d0 $detail_size]
        set vessel [dict get $d vessel]
        set cap [dict get $vessels $vessel capacity]
        set total [::plugins::DrinkMenu::drink_total $d]

        # Header.
        _set_text $page det_title \
            [_fit_text [translate [dict get $d name]] $L(font_title) [expr {int($L(det_title_maxw) * $L(v2px))}]]
        set sub "[translate [dict get $vessels $vessel name]], [format_amount $cap $ui_unit]"
        if {[dict get $d overflow]} { append sub " ([translate "over capacity"])" }
        if {[::plugins::DrinkMenu::is_custom $detail_id]} {
            append sub " ([translate "custom"])"
        }
        _set_text $page det_subtitle $sub
        ::plugins::DrinkMenu::_paint_controls $page

        # Hero cup + labels + leaders. Pass 18: the cup box is per vessel
        # (hero_cup_box -- a handled vessel gets a wider fitting box so
        # its BOWL, not bowl + handle, ends md before the label column),
        # so the pool is re-boxed before it is re-geometried. The stored
        # box is part of _cup_render's cache key, so a changed box can
        # never serve the previous vessel's polygons.
        if {[info exists ::plugins::DrinkMenu::cups(hero_cup)]} {
            lassign [::plugins::DrinkMenu::hero_cup_box $vessel] hcx hcy hcw hch
            dict set ::plugins::DrinkMenu::cups(hero_cup) x $hcx
            dict set ::plugins::DrinkMenu::cups(hero_cup) y $hcy
            dict set ::plugins::DrinkMenu::cups(hero_cup) w $hcw
            dict set ::plugins::DrinkMenu::cups(hero_cup) h $hch
        }
        ::plugins::DrinkMenu::update_cup $page hero_cup $d
        # Pass 19: ghost the part of the ring that runs under the label
        # column (hidden for a handle-less vessel, so Prev/Next between a
        # cup and a glass toggles it).
        ::plugins::DrinkMenu::update_hero_ring_dim $page $d
        lassign [::plugins::DrinkMenu::_cup_calc hero_cup $d] geom res
        set cx [dict get $geom cx]
        set fy [dict get $geom floor_y]
        set ih [dict get $geom interior_h]
        set mids {}
        set cup_xs {}
        foreach sp [dict get $res spans] {
            lassign $sp f0 f1
            set fm [expr {($f0 + $f1) / 2.0}]
            lappend mids [expr {$fy - $fm * $ih}]
            lappend cup_xs [expr {$cx + [::plugins::DrinkMenu::_half_width_at $geom $fm]}]
        }
        set ys [::plugins::DrinkMenu::label_layout $mids $L(det_label_pitch) $L(det_label_top) $L(det_label_bottom)]
        set layers [dict get $d layers]
        set n [expr {[llength $layers] / 2}]
        set maxw [expr {int($L(det_label_maxw) * $L(v2px))}]
        for {set i 0} {$i < $L(det_label_pool)} {incr i} {
            if {$i < $n} {
                set ing [lindex $layers [expr {2 * $i}]]
                set ml [lindex $layers [expr {2 * $i + 1}]]
                # Pass 33: preset or the drink's own custom def; a g
                # layer's amount stays in grams under either unit toggle.
                set nm [::plugins::DrinkMenu::ing_prop $d $ing name $ing]
                set ly [lindex $ys $i]
                # Pass 48: body font, then caption, then an ellipsis.
                lassign [::plugins::DrinkMenu::fit_label_name [translate $nm] $maxw] ltxt lfont
                _set_text $page lbl${i}_name $ltxt
                ::plugins::DrinkMenu::_set_font $page lbl${i}_name $lfont
                _set_text $page lbl${i}_amt [::plugins::DrinkMenu::format_layer_amount $d $ing $ml $ui_unit]
                _move_item $page lbl${i}_name [list $L(det_label_x) [expr {$ly - $L(det_label_dy)}]]
                _move_item $page lbl${i}_amt [list $L(det_label_x) [expr {$ly + $L(det_label_dy)}]]
                _move_item $page lead$i [list [lindex $cup_xs $i] [lindex $mids $i] \
                    [expr {$L(det_label_x) - $L(xs)}] $ly]
                _show_tags $page [list lead$i lbl${i}_name lbl${i}_amt] 1
            } else {
                _show_tags $page [list lead$i lbl${i}_name lbl${i}_amt] 0
            }
        }
        set garnish {}
        catch { set garnish [dict get $d garnish] }
        if {[llength $garnish] > 0} {
            set names {}
            foreach g $garnish { lappend names [string map {_ " "} $g] }
            _set_text $page det_garnish "[translate "Garnish"]: [join $names ", "]"
            _show_tags $page det_garnish 1
        } else {
            _show_tags $page det_garnish 0
        }

        # Totals + ratio.
        _set_text $page tot_fig [::plugins::DrinkMenu::amount_number $total $ui_unit]
        _set_text $page tot_cap [expr {$ui_unit eq "oz" ? [translate "oz total"] : [translate "ml total"]}]
        lassign [::plugins::DrinkMenu::drink_ratio $d] ratio names
        set rmaxw [expr {int($L(det_ratio_maxw) * $L(v2px))}]
        _set_text $page tot_ratio [_fit_text $ratio $L(font_primary) $rmaxw]
        # Pass 10 item 3: wrap onto a pooled second caption line instead
        # of truncating (Borgia's four ingredient names overran one line).
        lassign [::plugins::DrinkMenu::_wrap_names_2line $names $L(font_caption) $rmaxw] names1 names2
        _set_text $page tot_names $names1
        _set_text $page tot_names2 $names2
        _show_tags $page tot_names2 [expr {$names2 ne ""}]
        # Pass 40: show the tie-in button only when this drink defines
        # something to apply; the refresh relabel also washes out a
        # previous tap's outcome note.
        set tie [expr {[::plugins::DrinkMenu::drink_profile $d] ne {} \
            || [::plugins::DrinkMenu::water_target [::plugins::DrinkMenu::drink_hot_water $d]] > 0}]
        _show_tags $page det_mach* $tie
        if {$tie} {
            catch { dui item config $page det_mach -label [translate "To machine"] }
        }

        # Ingredient chips. The card is a fixed two-row card since
        # Pass 14, so chip_fit does the wrapping and, only for a custom
        # drink whose six chips would need a third row, shortens the
        # names (no preset ever reaches that branch).
        set chips {}
        foreach {ing ml} $layers {
            # Pass 33: preset or the drink's own custom def.
            set nm [translate [::plugins::DrinkMenu::ing_prop $d $ing name $ing]]
            set amt [::plugins::DrinkMenu::format_layer_amount $d $ing $ml $ui_unit]
            set color [::plugins::DrinkMenu::ing_prop $d $ing color "#888888"]
            lappend chips [list $nm $amt $color]
        }
        lassign [::plugins::DrinkMenu::chip_fit $chips $L(det_ing_inner_w) $L(det_chip_h) \
            $L(det_chip_gap) $L(det_ing_rows)] chips pos
        set ch $L(det_chip_h)
        set can [dui canvas]
        for {set i 0} {$i < $L(det_chip_pool)} {incr i} {
            if {$i < [llength $chips]} {
                lassign [lindex $chips $i] nm amt color w
                lassign [lindex $pos $i] ox oy
                set x1 [expr {$L(det_ing_inner_x) + $ox}]
                set y1 [expr {$L(det_ing_inner_y) + $oy}]
                set ymid [expr {$y1 + $ch / 2.0}]
                ::plugins::DrinkMenu::shape_move $page chip${i}_bg $x1 $y1 [expr {$x1 + $w}] [expr {$y1 + $ch}]
                set dx [expr {$x1 + $L(det_chip_pad_x)}]
                set r2 [expr {$L(det_chip_dot) / 2.0}]
                # Pass 46: whichever item carries the dot (oval or image)
                # moves to the same top-left; dot_paint sets its colour.
                set dtag [lindex [::plugins::DrinkMenu::dot_tags chip${i}_dot] 0]
                if {$dtag eq "chip${i}_dot"} {
                    _move_item $page $dtag [list $dx [expr {$ymid - $r2}] [expr {$dx + $L(det_chip_dot)}] [expr {$ymid + $r2}]]
                } else {
                    _move_item $page $dtag [list $dx [expr {$ymid - $r2}]]
                }
                ::plugins::DrinkMenu::dot_paint $page chip${i}_dot $color
                set nx [expr {$dx + $L(det_chip_dot) + $L(det_chip_gap_in)}]
                _set_text $page chip${i}_name $nm
                _move_item $page chip${i}_name [list $nx $ymid]
                set ax [expr {$nx + [_text_w $L(font_body) $nm] * $L(px2v) + $L(det_chip_gap_amt)}]
                _set_text $page chip${i}_amt $amt
                _move_item $page chip${i}_amt [list $ax $ymid]
                _show_tags $page [list chip${i}_bg $dtag chip${i}_name chip${i}_amt] 1
            } else {
                _show_tags $page [list chip${i}_bg {*}[::plugins::DrinkMenu::dot_tags chip${i}_dot] chip${i}_name chip${i}_amt] 0
            }
        }

        # Method steps (Pass 14). Preset steps are written to fit the
        # card's text width, so _fit_text is a guard here, not a working
        # part: the headless check proves every preset step fits whole.
        set steps [::plugins::DrinkMenu::drink_steps $d]
        set mmaxw [expr {int($L(det_met_maxw) * $L(v2px))}]
        for {set i 0} {$i < $L(det_met_pool)} {incr i} {
            if {$i < [llength $steps]} {
                _set_text $page met${i}_num [expr {$i + 1}]
                _set_text $page met${i}_text \
                    [_fit_text [translate [lindex $steps $i]] $L(font_caption) $mmaxw]
                _show_tags $page [list met${i}_num met${i}_text] 1
            } else {
                _show_tags $page [list met${i}_num met${i}_text] 0
            }
        }
        # Pass 48: a custom drink's empty method is an invitation.
        set no_steps [expr {[llength $steps] == 0}]
        set can_add [expr {$no_steps && [::plugins::DrinkMenu::is_custom $detail_id]}]
        _set_text $page met_none \
            [expr {$can_add ? [translate "Add a method"] : [translate "No method saved."]}]
        foreach mid [::plugins::DrinkMenu::_ids $page met_none] {
            catch { $can itemconfigure $mid -fill [expr {$can_add ? $L(crema_text) : $L(c_ink_2)}] }
        }
        _show_tags $page met_none $no_steps
        _show_tags $page met_add_tap* $can_add

        # Favorite face: the star icon swaps (Pass 48); the label stays
        # "Favorite". Hide keeps its relabel (bare dbutton tag).
        ::plugins::DrinkMenu::_set_image $page bar_fav_icon \
            [::plugins::DrinkMenu::star_photo [::plugins::DrinkMenu::is_favorite $detail_id] \
                $::plugins::DrinkMenu::fav_star_scale]
        catch {
            dui item config $page bar_hide -label \
                [expr {[::plugins::DrinkMenu::is_hidden $detail_id] ? [translate "Unhide"] : [translate "Hide"]}]
        }
        catch {
            dui item config $page bar_edit -label \
                [expr {[::plugins::DrinkMenu::is_custom $detail_id] ? [translate "Edit"] : [translate "Copy & edit"]}]
        }

        # Prev/Next drink in the current tab order.
        lassign [::plugins::DrinkMenu::detail_neighbors $detail_id [::plugins::DrinkMenu::visible_drinks $ui_tab]] prev next
        _show_tags $page bar_prev* [expr {$prev ne ""}]
        _show_tags $page bar_next* [expr {$next ne ""}]
    }

    proc show {page_to_hide page_to_show} {
        set page [namespace tail [namespace current]]
        if {[catch {
            ::plugins::DrinkMenu::_apply_palette
            ::plugins::DrinkMenu::_retheme $page
            refresh
        } err]} {
            catch { msg -ERROR "DrinkMenu: detail show repaint failed: $err" }
        }
    }
}

# ===========================================================================
#  Editor page: name entry in the header (keyboard-safe zone), live
#  preview card (left), right column in one of four in-page modes
#  (layers / palette / vessel / confirm), Cancel | Delete (hidden until
#  the draft has been saved once), Save as copy, Save. Always edits a
#  custom drink: a preset opens here as a fresh, unsaved copy.
# ===========================================================================

namespace eval ::dui::pages::DrinkMenu_edit {
    variable widgets
    array set widgets {}

    variable seed_drink {name "" vessel cup layers {espresso 60}}

    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::DrinkMenu::L L
        upvar #0 ::plugins::DrinkMenu::vessels vessels
        upvar #0 ::plugins::DrinkMenu::ingredients ingredients
        variable seed_drink
        set NS ::plugins::DrinkMenu

        # This page's items are about to be (re)created: drop any cached
        # canvas ids and "already written" state for it (Pass 9).
        ${NS}::invalidate_items $page
        ${NS}::_page_bg $page
        # Pass 46: decides dot_mode for the row and palette dots below.
        ${NS}::dot_sprites
        set lx $L(left_x)
        set rx $L(right_x)

        # ---- Header: title, name entry, keyboard Done ----
        dui add dtext $page $lx $L(header_title_y) -tags ed_title \
            -text [translate "Edit drink"] \
            -font $L(font_section) -fill $L(c_ink) -anchor w -justify left
        ${NS}::_theme_item $page ed_title fill c_ink
        if {[catch {
            dui add entry $page $L(ed_entry_x) $L(ed_entry_y) -tags ed_name_entry \
                -textvariable ::plugins::DrinkMenu::edit_name \
                -width $L(ed_entry_chars) -font $L(font_primary) -borderwidth 1 \
                -bg $L(c_glass_2) -foreground $L(c_ink) -relief flat
            # Not registered for retheme: `dui item config` on the window
            # item resolves it by canvas id and logs a tag miss (tablet,
            # v0.5.1). Colors are set once at creation; the palette only
            # changes with an app restart, which rebuilds the page.
        } err]} {
            catch { msg -ERROR "DrinkMenu: name entry setup failed: $err" }
        }
        # Pass 48: focus in / out on the entry widget (dui names it
        # <canvas>.<page lowercase>-<tag>) drives the keyboard Done and
        # the "Drink name" hint. Headless there is no widget: guarded.
        catch {
            set _w [${NS}::_name_entry_widget]
            bind $_w <FocusIn>  {+::plugins::DrinkMenu::_name_focus 1}
            bind $_w <FocusOut> {+::plugins::DrinkMenu::_name_focus 0}
        }
        # Pass 23 items 5 and 8: the keyboard Done keeps the 60-ref touch
        # height of a bar button, is centred on the header band with the
        # title and the entry, and is gold -- it is this page's "I am done
        # typing" action, the mock's `.btn`. Pass 48: it exists only while
        # the entry has focus (created hidden; _name_focus shows it), so
        # the page has ONE gold action, Save, the rest of the time.
        ${NS}::bar_button $page ed_done \
            $L(ed_done_x1) $L(hdr_btn_y0) $L(ed_done_x2) $L(hdr_btn_y1) primary \
            -label [translate "Done"] \
            -command ${NS}::_name_done \
            -label_font $L(font_button) -initial_state hidden

        # ---- Preview card ----
        if {[catch {
            ${NS}::glass_card $page prev $L(ed_prev_x1) $L(ed_prev_y1) $L(ed_prev_w) \
                [expr {$L(ed_prev_y2) - $L(ed_prev_y1)}]
            if {[dict exists $vessels cup]} {
                ${NS}::draw_cup $page ed_cup $L(ed_cup_x1) $L(ed_cup_y1) \
                    [expr {$L(ed_cup_x2) - $L(ed_cup_x1)}] [expr {$L(ed_cup_y2) - $L(ed_cup_y1)}] \
                    $seed_drink 0 card
            }
            dui add dtext $page $L(ed_cup_x1) $L(ed_vessel_y) -tags ed_vessel -text [translate "Vessel"] \
                -font $L(font_body) -fill $L(c_ink_2) -anchor w -justify left
            ${NS}::_theme_item $page ed_vessel fill c_ink_2
            dui add dtext $page $L(ed_cup_x1) $L(ed_total_y) -tags ed_total -text "0 ml" \
                -font $L(font_primary) -fill $L(crema_text) -anchor w -justify left
            ${NS}::_theme_item $page ed_total fill crema_text
            dui add dtext $page $L(ed_cup_x1) $L(ed_status_y) -tags ed_status -text [translate "OK"] \
                -font $L(font_caption) -fill $L(warn) -anchor nw -justify left -width $L(ed_text_w) \
                -initial_state hidden
            ${NS}::_theme_item $page ed_status fill warn
            # Pass 36: the tappable garnish line (text + pen + invisible
            # rect; the pen follows the fitted text each refresh). The
            # editor only ever edits a custom draft, so it is always
            # editable. No -pressfill (press rule).
            dui add dtext $page $L(ed_cup_x1) $L(ed_garn_y) -tags ed_garnish \
                -text [translate "Garnish"] \
                -font $L(font_caption) -fill $L(c_ink_2) -anchor w -justify left
            ${NS}::_theme_item $page ed_garnish fill c_ink_2
            # Starts hidden: it is created on top of the label and only
            # refresh_preview (which needs a draft) places it after the
            # fitted text -- a bare page load must not show them stacked.
            dui add dtext $page $L(ed_cup_x1) $L(ed_garn_y) -tags ed_garn_pen \
                -text $L(glyph_pen) -font $L(glyph_font_pen) \
                -fill $L(crema_text) -anchor w -justify left -initial_state hidden
            ${NS}::_theme_item $page ed_garn_pen fill crema_text
            dui add dbutton $page $L(ed_cup_x1) $L(ed_garn_tap_y1) \
                $L(ed_cup_x2) $L(ed_garn_tap_y2) -tags ed_garntap \
                -command ${NS}::edit_garnish_tap
        } err]} {
            catch { msg -ERROR "DrinkMenu: editor preview setup failed: $err" }
        }

        # ---- Right column, mode layers ----
        set cx1 $L(ed_col_x1)
        set cx2 $L(ed_col_x2)
        set y0 $L(ed_rows_y0)
        set rh $L(ed_row_h)
        set rp $L(ed_row_pitch)
        if {[catch {
            # Pass 38: the vessel row splits -- vessel left, group right.
            # Non-empty creation labels; the refresh relabels both by
            # BARE dbutton tag.
            ${NS}::bar_button $page ed_vessel_btn $cx1 $y0 $L(ed_vbtn_x2) [expr {$y0 + $rh}] btn \
                -label [translate "Vessel"] \
                -command ${NS}::edit_vessel_tap \
                -label_font $L(font_button)
            ${NS}::bar_button $page ed_group_btn $L(ed_gbtn_x1) $y0 $cx2 [expr {$y0 + $rh}] btn \
                -label [translate "Group"] \
                -command ${NS}::edit_group_tap \
                -label_font $L(font_button)
            # Pass 48: second header row -- Method (step count, relabelled
            # at refresh) and Profile -- so the action row below the list
            # holds "+ Add layer" alone.
            set hy $L(ed_hdr2_y)
            ${NS}::bar_button $page ed_method $L(ed_method_x1) $hy $L(ed_method_x2) [expr {$hy + $rh}] btn \
                -label [translate "Method"] \
                -command ${NS}::edit_method_tap \
                -label_font $L(font_button)
            # Pass 40: link/unlink the app's CURRENT profile to the draft.
            ${NS}::bar_button $page ed_profile_btn $L(ed_prof_x1) $hy $cx2 [expr {$hy + $rh}] btn \
                -label [translate "Profile"] \
                -command ${NS}::edit_profile_toggle \
                -label_font $L(font_button)
            for {set i 0} {$i < $L(ed_row_pool)} {incr i} {
                set ry [expr {$y0 + ($i + $L(ed_rows_first)) * $rp}]
                set ymid [expr {$ry + $rh / 2.0}]
                set r2 [expr {$L(ed_dot) / 2.0}]
                # Pass 46: a sprite dot (the oval stays, hidden).
                ${NS}::draw_dot $page ed_row${i}_dot $L(ed_row_dot_x) [expr {$ymid - $r2}] $L(c_ink)
                dui add dtext $page $L(ed_row_name_x) $ymid -tags ed_row${i}_name -text "-" \
                    -font $L(font_body) -fill $L(c_ink) -anchor w -justify left -initial_state hidden
                ${NS}::_theme_item $page ed_row${i}_name fill c_ink
                dui add dtext $page $L(ed_amt_x) $ymid -tags ed_row${i}_amt -text "-" \
                    -font $L(font_body_b) -fill $L(crema_text) -anchor e -justify right -initial_state hidden
                ${NS}::_theme_item $page ed_row${i}_amt fill crema_text
                foreach {sub key cmd} [list mvup chev_u [list ${NS}::edit_move_tap $i 1] \
                                            mvdn chev_d [list ${NS}::edit_move_tap $i -1] \
                                            minus minus [list ${NS}::edit_step_tap $i -1] \
                                            plus plus [list ${NS}::edit_step_tap $i 1] \
                                            rm xmark [list ${NS}::edit_remove_tap $i]] {
                    set bx1 $L(ed_${sub}_x1)
                    ${NS}::bar_button $page ed_row${i}_$sub $bx1 $ry [expr {$bx1 + $rh}] [expr {$ry + $rh}] btn \
                        -label $L(glyph_$key) -command $cmd \
                        -label_font $L(glyph_font_$key) -initial_state hidden
                }
                # Pass 34: a CUSTOM layer's row is editable -- a pen after
                # the name (moved to the fitted name's end each refresh)
                # and an invisible tap rect over dot + name that reopens
                # the custing form prefilled. Both stay hidden on preset
                # rows (the refresh decides). No -pressfill (press rule).
                dui add dtext $page $L(ed_row_name_x) $ymid -tags ed_row${i}_pen \
                    -text $L(glyph_pen) -font $L(glyph_font_pen) \
                    -fill $L(crema_text) -anchor w -justify left -initial_state hidden
                ${NS}::_theme_item $page ed_row${i}_pen fill crema_text
                dui add dbutton $page $L(ed_row_dot_x) $ry \
                    [expr {$L(ed_row_name_x) + $L(ed_name_maxw)}] [expr {$ry + $rh}] \
                    -tags ed_row${i}_edtap \
                    -command [list ${NS}::edit_layer_tap $i] -initial_state hidden
            }
            # Pass 48: "+ Add layer" follows the last layer row. Created
            # on the first layer row (hidden until the refresh places it
            # with `$can move`, see ed_add_y), never on the bar row.
            set ay [expr {$y0 + $L(ed_rows_first) * $rp}]
            set ::plugins::DrinkMenu::ed_add_y $ay
            ${NS}::bar_button $page ed_add $cx1 $ay $L(ed_add_x2) [expr {$ay + $rh}] btn \
                -label [translate "+ Add layer"] \
                -command ${NS}::edit_add_tap \
                -label_font $L(font_button) -initial_state hidden
        } err]} {
            catch { msg -ERROR "DrinkMenu: editor layers setup failed: $err" }
        }

        # ---- Mode palette: caption + 4-column ingredient chips + Cancel ----
        if {[catch {
            dui add dtext $page $cx1 $y0 -tags ed_cap_pal -text [translate "Add an ingredient"] \
                -font $L(font_body) -fill $L(c_ink_2) -anchor nw -justify left -initial_state hidden
            ${NS}::_theme_item $page ed_cap_pal fill c_ink_2
            set j 0
            set maxw [expr {int(($L(ed_pal_w) - 2 * $L(det_chip_pad_x) - $L(ed_dot) - $L(det_chip_gap_in)) * $L(v2px))}]
            foreach {ing idef} $ingredients {
                if {$j >= $L(ed_pal_pool)} { break }
                set col [expr {$j % $L(ed_pal_cols)}]
                set row [expr {$j / $L(ed_pal_cols)}]
                set px1 [expr {$cx1 + $col * ($L(ed_pal_w) + $L(sm))}]
                set py1 [expr {$L(ed_grid_y0) + $row * $rp}]
                set px2 [expr {$px1 + $L(ed_pal_w)}]
                set py2 [expr {$py1 + $rh}]
                set pmid [expr {$py1 + $rh / 2.0}]
                ${NS}::shape_make $page ed_pal${j}_bg $px1 $py1 $px2 $py2 \
                    [expr {$rh / 2}] chip_bg chip_bg -kind chip -initial hidden
                set dx [expr {$px1 + $L(det_chip_pad_x)}]
                set r2 [expr {$L(ed_dot) / 2.0}]
                # Pass 46: a sprite dot in the ingredient's colour.
                ${NS}::draw_dot $page ed_pal${j}_dot $dx [expr {$pmid - $r2}] [dict get $idef color]
                dui add dtext $page [expr {$dx + $L(ed_dot) + $L(det_chip_gap_in)}] $pmid -tags ed_pal${j}_name \
                    -text [${NS}::_fit_text [translate [dict get $idef name]] $L(font_body) $maxw] \
                    -font $L(font_body) -fill $L(c_ink) -anchor w -justify left -initial_state hidden
                ${NS}::_theme_item $page ed_pal${j}_name fill c_ink
                # No -pressfill (the press rule in _apply_palette): this
                # rect is invisible, and a stuck flash would sit on the
                # row's dot and name for the rest of the session.
                dui add dbutton $page $px1 $py1 $px2 $py2 -tags ed_pal${j}_tap \
                    -command [list ${NS}::edit_pick_ingredient $ing] -initial_state hidden
                incr j
            }
            # Pass 33: the last chip opens the custom-ingredient mode. It
            # takes the next free grid slot after the presets (19 presets
            # in a 4 x 6 = 24-slot grid); if presets ever fill the grid it
            # takes the last slot, covering the 24th preset rather than
            # falling off the page.
            set j [expr {min($j, 23)}]
            set col [expr {$j % $L(ed_pal_cols)}]
            set row [expr {$j / $L(ed_pal_cols)}]
            set px1 [expr {$cx1 + $col * ($L(ed_pal_w) + $L(sm))}]
            set py1 [expr {$L(ed_grid_y0) + $row * $rp}]
            set px2 [expr {$px1 + $L(ed_pal_w)}]
            set py2 [expr {$py1 + $rh}]
            set pmid [expr {$py1 + $rh / 2.0}]
            ${NS}::shape_make $page ed_palnew_bg $px1 $py1 $px2 $py2 \
                [expr {$rh / 2}] chip_bg chip_brd -kind chip -initial hidden
            dui add dtext $page [expr {($px1 + $px2) / 2}] $pmid -tags ed_palnew_name \
                -text "+ [translate "Custom..."]" \
                -font $L(font_body_b) -fill $L(crema_text) -anchor center -justify center \
                -initial_state hidden
            ${NS}::_theme_item $page ed_palnew_name fill crema_text
            dui add dbutton $page $px1 $py1 $px2 $py2 -tags ed_palnew_tap \
                -command ${NS}::edit_custom_tap -initial_state hidden
            ${NS}::bar_button $page ed_pal_cancel \
                [expr {$cx2 - $L(btn_w_std)}] $L(ed_cancel_y1) $cx2 $L(ed_cancel_y2) btn \
                -label [translate "Cancel"] \
                -command ${NS}::edit_mode_cancel \
                -label_font $L(font_button) -initial_state hidden
        } err]} {
            catch { msg -ERROR "DrinkMenu: editor palette setup failed: $err" }
        }

        # ---- Mode custing: name entry + ml/g capsule + swatches (Pass 33) ----
        if {[catch {
            dui add dtext $page $cx1 $y0 -tags ed_cap_cust -text [translate "Custom ingredient"] \
                -font $L(font_body) -fill $L(c_ink_2) -anchor nw -justify left -initial_state hidden
            ${NS}::_theme_item $page ed_cap_cust fill c_ink_2
            # The entry sits in the keyboard-safe top zone; Return and
            # pointer-leave hide the Android keyboard (core dui behaviour,
            # same as the name entry above). Not registered for retheme,
            # for the same window-item reason as ed_name_entry.
            dui add entry $page $cx1 [expr {($L(ed_cu_row_y0) + $L(ed_cu_row_y1)) / 2 - $L(ed_entry_h) / 2}] \
                -tags ed_cust_entry \
                -textvariable ::plugins::DrinkMenu::cust_name \
                -width $L(ed_cu_entry_chars) -font $L(font_primary) -borderwidth 1 \
                -bg $L(c_glass_2) -foreground $L(c_ink) -relief flat -initial_state hidden
            ${NS}::segment_capsule $page cunit \
                $L(ed_cu_unit_x1) $L(ed_cu_row_y0) $L(ed_cu_unit_x2) $L(ed_cu_row_y1) \
                [list [translate ml] [translate g]] [list $L(font_pill) $L(font_pill)] hidden
            set cux $L(ed_cu_unit_x1)
            foreach u {ml g} {
                # No -pressfill (the press rule in _apply_palette); the
                # flash is edit_custom_unit's own _flash_seg.
                dui add dbutton $page $cux $L(ed_cu_row_y0) \
                    [expr {$cux + $L(unit_seg_w)}] $L(ed_cu_row_y1) \
                    -tags cunit_$u -command [list ${NS}::edit_custom_unit $u] \
                    -tap_pad $L(hdr_tap_pad) -initial_state hidden
                set cux [expr {$cux + $L(unit_seg_w) + $L(seg_gap)}]
            }
            upvar #0 ::plugins::DrinkMenu::cust_colors cust_colors
            for {set s 0} {$s < [llength $cust_colors]} {incr s} {
                set scol [expr {$s % 6}]
                set srow [expr {$s / 6}]
                set sx1 [expr {$cx1 + $scol * $L(ed_sw_pitch)}]
                set sy1 [expr {$L(ed_sw_y0) + $srow * $L(ed_sw_pitch)}]
                set sx2 [expr {$sx1 + $L(ed_sw)}]
                set sy2 [expr {$sy1 + $L(ed_sw)}]
                dui add canvas_item rect $page $sx1 $sy1 $sx2 $sy2 \
                    -fill [lindex $cust_colors $s] -outline $L(c_ink_3) -width $L(line_w) \
                    -tags ed_sw$s -initial_state hidden
                ${NS}::_theme_item $page ed_sw$s outline c_ink_3
                # The selection ring, shown for the picked swatch only.
                set rp2 $L(ed_sw_ring_pad)
                dui add canvas_item rect $page [expr {$sx1 - $rp2}] [expr {$sy1 - $rp2}] \
                    [expr {$sx2 + $rp2}] [expr {$sy2 + $rp2}] \
                    -fill {} -outline $L(c_crema) -width [expr {2 * $L(line_w)}] \
                    -tags ed_sw${s}_ring -initial_state hidden
                ${NS}::_theme_item $page ed_sw${s}_ring outline c_crema
                dui add dbutton $page $sx1 $sy1 $sx2 $sy2 -tags ed_sw${s}_tap \
                    -command [list ${NS}::edit_custom_color $s] -initial_state hidden
            }
            ${NS}::bar_button $page ed_cust_cancel \
                $L(ed_cu_cancel_x1) $L(ed_cancel_y1) \
                [expr {$L(ed_cu_cancel_x1) + $L(btn_w_std)}] $L(ed_cancel_y2) btn \
                -label [translate "Cancel"] \
                -command ${NS}::edit_mode_cancel \
                -label_font $L(font_button) -initial_state hidden
            ${NS}::bar_button $page ed_cust_add \
                $L(ed_cu_add_x1) $L(ed_cancel_y1) $L(ed_col_x2) $L(ed_cancel_y2) primary \
                -label [translate "Add layer"] \
                -command ${NS}::edit_custom_add \
                -label_font $L(font_button) -initial_state hidden
        } err]} {
            catch { msg -ERROR "DrinkMenu: editor custing setup failed: $err" }
        }

        # ---- Mode garnish: caption + free-text entry + Save (Pass 36) ----
        if {[catch {
            dui add dtext $page $cx1 $y0 -tags ed_cap_garn -text [translate "Garnish"] \
                -font $L(font_body) -fill $L(c_ink_2) -anchor nw -justify left -initial_state hidden
            ${NS}::_theme_item $page ed_cap_garn fill c_ink_2
            # Keyboard-safe top zone, same row as the custing entry.
            dui add entry $page $cx1 [expr {($L(ed_cu_row_y0) + $L(ed_cu_row_y1)) / 2 - $L(ed_entry_h) / 2}] \
                -tags ed_gn_entry \
                -textvariable ::plugins::DrinkMenu::garn_text \
                -width $L(ed_garn_entry_chars) -font $L(font_primary) -borderwidth 1 \
                -bg $L(c_glass_2) -foreground $L(c_ink) -relief flat -initial_state hidden
            dui add dtext $page $cx1 $L(ed_sw_y0) -tags ed_gn_hint \
                -text [translate "Comma-separated, up to four; leave empty for none."] \
                -font $L(font_caption) -fill $L(c_ink_2) -anchor nw -justify left -initial_state hidden
            ${NS}::_theme_item $page ed_gn_hint fill c_ink_2
            ${NS}::bar_button $page ed_gn_cancel \
                $L(ed_cu_cancel_x1) $L(ed_cancel_y1) \
                [expr {$L(ed_cu_cancel_x1) + $L(btn_w_std)}] $L(ed_cancel_y2) btn \
                -label [translate "Cancel"] \
                -command ${NS}::edit_mode_cancel \
                -label_font $L(font_button) -initial_state hidden
            ${NS}::bar_button $page ed_gn_save \
                $L(ed_cu_add_x1) $L(ed_cancel_y1) $L(ed_col_x2) $L(ed_cancel_y2) primary \
                -label [translate "Save"] \
                -command ${NS}::edit_garnish_save \
                -label_font $L(font_button) -initial_state hidden
        } err]} {
            catch { msg -ERROR "DrinkMenu: editor garnish setup failed: $err" }
        }

        # ---- Mode method: step list + add + done (Pass 37) ----
        if {[catch {
            dui add dtext $page $cx1 $y0 -tags ed_cap_met -text [translate "Method"] \
                -font $L(font_body) -fill $L(c_ink_2) -anchor nw -justify left -initial_state hidden
            ${NS}::_theme_item $page ed_cap_met fill c_ink_2
            upvar #0 ::plugins::DrinkMenu::steps_max steps_max
            for {set i 0} {$i < $steps_max} {incr i} {
                set ry [expr {$L(ed_grid_y0) + $i * $rp}]
                set ymid [expr {$ry + $rh / 2.0}]
                dui add dtext $page $L(ed_st_num_x) $ymid -tags ed_st${i}_num \
                    -text [expr {$i + 1}] -font $L(font_body_b) -fill $L(ink_3_text) \
                    -anchor w -justify left -initial_state hidden
                ${NS}::_theme_item $page ed_st${i}_num fill ink_3_text
                dui add dtext $page $L(ed_st_txt_x) $ymid -tags ed_st${i}_txt \
                    -text "-" -font $L(font_caption) -fill $L(c_ink) \
                    -anchor w -justify left -initial_state hidden
                ${NS}::_theme_item $page ed_st${i}_txt fill c_ink
                # Tap the text to edit; no -pressfill (press rule).
                dui add dbutton $page $L(ed_st_num_x) $ry \
                    [expr {$L(ed_st_txt_x) + $L(ed_st_maxw)}] [expr {$ry + $rh}] \
                    -tags ed_st${i}_tap \
                    -command [list ${NS}::edit_step_row_tap $i] -initial_state hidden
                foreach {sub key cmd} [list mvup chev_u [list ${NS}::edit_step_move_tap $i -1] \
                                            mvdn chev_d [list ${NS}::edit_step_move_tap $i 1] \
                                            rm xmark [list ${NS}::edit_step_rm $i]] {
                    set bx1 [expr {$sub eq "mvup" ? $L(ed_st_up_x1) : \
                                   $sub eq "mvdn" ? $L(ed_st_dn_x1) : $L(ed_st_rm_x1)}]
                    ${NS}::bar_button $page ed_st${i}_$sub $bx1 $ry [expr {$bx1 + $rh}] [expr {$ry + $rh}] btn \
                        -label $L(glyph_$key) -command $cmd \
                        -label_font $L(glyph_font_$key) -initial_state hidden
                }
            }
            ${NS}::bar_button $page ed_st_add \
                $L(ed_cu_cancel_x1) $L(ed_cancel_y1) \
                [expr {$L(ed_cu_cancel_x1) + $L(btn_w_std)}] $L(ed_cancel_y2) btn \
                -label [translate "+ Add step"] \
                -command ${NS}::edit_step_add_tap \
                -label_font $L(font_button) -initial_state hidden
            ${NS}::bar_button $page ed_st_done \
                $L(ed_cu_add_x1) $L(ed_cancel_y1) $L(ed_col_x2) $L(ed_cancel_y2) btn \
                -label [translate "Done"] \
                -command ${NS}::edit_mode_cancel \
                -label_font $L(font_button) -initial_state hidden
        } err]} {
            catch { msg -ERROR "DrinkMenu: editor method setup failed: $err" }
        }

        # ---- Mode stepform: one step's entry (Pass 37) ----
        if {[catch {
            dui add dtext $page $cx1 $y0 -tags ed_cap_sf -text [translate "Edit step"] \
                -font $L(font_body) -fill $L(c_ink_2) -anchor nw -justify left -initial_state hidden
            ${NS}::_theme_item $page ed_cap_sf fill c_ink_2
            dui add entry $page $cx1 [expr {($L(ed_cu_row_y0) + $L(ed_cu_row_y1)) / 2 - $L(ed_entry_h) / 2}] \
                -tags ed_sf_entry \
                -textvariable ::plugins::DrinkMenu::step_text \
                -width $L(ed_sf_entry_chars) -font $L(font_primary) -borderwidth 1 \
                -bg $L(c_glass_2) -foreground $L(c_ink) -relief flat -initial_state hidden
            dui add dtext $page $cx1 $L(ed_sw_y0) -tags ed_sf_hint \
                -text [translate "One short line; leave empty to keep the old text."] \
                -font $L(font_caption) -fill $L(c_ink_2) -anchor nw -justify left -initial_state hidden
            ${NS}::_theme_item $page ed_sf_hint fill c_ink_2
            ${NS}::bar_button $page ed_sf_cancel \
                $L(ed_cu_cancel_x1) $L(ed_cancel_y1) \
                [expr {$L(ed_cu_cancel_x1) + $L(btn_w_std)}] $L(ed_cancel_y2) btn \
                -label [translate "Cancel"] \
                -command ${NS}::edit_step_cancel \
                -label_font $L(font_button) -initial_state hidden
            ${NS}::bar_button $page ed_sf_save \
                $L(ed_cu_add_x1) $L(ed_cancel_y1) $L(ed_col_x2) $L(ed_cancel_y2) primary \
                -label [translate "Save"] \
                -command ${NS}::edit_step_save \
                -label_font $L(font_button) -initial_state hidden
        } err]} {
            catch { msg -ERROR "DrinkMenu: editor stepform setup failed: $err" }
        }

        # ---- Mode group: 7 chips + Cancel (Pass 38) ----
        if {[catch {
            dui add dtext $page $cx1 $y0 -tags ed_cap_grp \
                -text [translate "Where in the menu?"] \
                -font $L(font_body) -fill $L(c_ink_2) -anchor nw -justify left -initial_state hidden
            ${NS}::_theme_item $page ed_cap_grp fill c_ink_2
            upvar #0 ::plugins::DrinkMenu::group_order group_order
            set gk 0
            foreach grp [concat $group_order [list custom]] {
                set col [expr {$gk % $L(ed_pal_cols)}]
                set row [expr {$gk / $L(ed_pal_cols)}]
                set gx1 [expr {$cx1 + $col * ($L(ed_pal_w) + $L(sm))}]
                set gy1 [expr {$L(ed_grid_y0) + $row * $rp}]
                set gx2 [expr {$gx1 + $L(ed_pal_w)}]
                set gy2 [expr {$gy1 + $rh}]
                set gmid [expr {$gy1 + $rh / 2.0}]
                ${NS}::shape_make $page ed_grp${gk}_bg $gx1 $gy1 $gx2 $gy2 \
                    [expr {$rh / 2}] chip_bg chip_bg -kind chip -initial hidden \
                    -variants {{pill_on_fill pill_on_fill}}
                dui add dtext $page [expr {($gx1 + $gx2) / 2}] $gmid -tags ed_grp${gk}_name \
                    -text [translate [${NS}::group_label $grp]] \
                    -font $L(font_body) -fill $L(c_ink) -anchor center -justify center \
                    -initial_state hidden
                ${NS}::_theme_item $page ed_grp${gk}_name fill c_ink
                # No -pressfill (press rule); the gold selection repaint
                # is the feedback.
                dui add dbutton $page $gx1 $gy1 $gx2 $gy2 -tags ed_grp${gk}_tap \
                    -command [list ${NS}::edit_pick_group $grp] -initial_state hidden
                incr gk
            }
            ${NS}::bar_button $page ed_grp_cancel \
                [expr {$cx2 - $L(btn_w_std)}] $L(ed_cancel_y1) $cx2 $L(ed_cancel_y2) btn \
                -label [translate "Cancel"] \
                -command ${NS}::edit_mode_cancel \
                -label_font $L(font_button) -initial_state hidden
        } err]} {
            catch { msg -ERROR "DrinkMenu: editor group setup failed: $err" }
        }

        # ---- Mode vessel: caption + 2x4 vessel tiles + Cancel ----
        if {[catch {
            dui add dtext $page $cx1 $y0 -tags ed_cap_ves -text [translate "Choose a vessel"] \
                -font $L(font_body) -fill $L(c_ink_2) -anchor nw -justify left -initial_state hidden
            ${NS}::_theme_item $page ed_cap_ves fill c_ink_2
            set k 0
            foreach {vid vdef} $vessels {
                if {$k >= $L(ed_ves_pool)} { break }
                set col [expr {$k % 4}]
                set row [expr {$k / 4}]
                set vx1 [expr {$cx1 + $col * ($L(ed_ves_w) + $L(sm))}]
                set vy1 [expr {$L(ed_grid_y0) + $row * ($L(ed_ves_h) + $L(md))}]
                set vx2 [expr {$vx1 + $L(ed_ves_w)}]
                set vy2 [expr {$vy1 + $L(ed_ves_h)}]
                ${NS}::glass_card $page ed_ves$k $vx1 $vy1 $L(ed_ves_w) $L(ed_ves_h) "" 1 tile
                ${NS}::draw_cup $page ed_ves${k}_cup [expr {$vx1 + $L(ed_ves_cup_pad)}] [expr {$vy1 + $L(ed_ves_cup_pad)}] \
                    [expr {$L(ed_ves_w) - 2 * $L(ed_ves_cup_pad)}] \
                    [expr {$L(ed_ves_h) - 2 * $L(ed_ves_cup_pad) - $L(ed_ves_name_dy) - $L(ed_ves_cap_dy)}] \
                    [dict create name "" vessel $vid layers {}] 1 tile
                set vcx [expr {$vx1 + $L(ed_ves_w) / 2}]
                dui add dtext $page $vcx [expr {$vy2 - $L(ed_ves_name_dy)}] -tags ed_ves${k}_name \
                    -text [${NS}::_fit_text [translate [dict get $vdef name]] $L(font_caption) [expr {int(($L(ed_ves_w) - 2 * $L(card_pad_x)) * $L(v2px))}]] \
                    -font $L(font_caption) -fill $L(c_ink) -anchor s -justify center -initial_state hidden
                ${NS}::_theme_item $page ed_ves${k}_name fill c_ink
                dui add dtext $page $vcx [expr {$vy2 - $L(ed_ves_cap_dy)}] -tags ed_ves${k}_cap \
                    -text "[dict get $vdef capacity] ml" \
                    -font $L(font_caption) -fill $L(c_ink_2) -anchor s -justify center -initial_state hidden
                ${NS}::_theme_item $page ed_ves${k}_cap fill c_ink_2
                # No -pressfill (the press rule in _apply_palette): this
                # rect is invisible, and a stuck flash would cover the
                # tile's cup and name on every later visit to the picker.
                dui add dbutton $page $vx1 $vy1 $vx2 $vy2 -tags ed_ves${k}_tap \
                    -command [list ${NS}::edit_pick_vessel $vid] -initial_state hidden
                incr k
            }
            ${NS}::bar_button $page ed_ves_cancel \
                [expr {$cx2 - $L(btn_w_std)}] $L(ed_cancel_y1) $cx2 $L(ed_cancel_y2) btn \
                -label [translate "Cancel"] \
                -command ${NS}::edit_mode_cancel \
                -label_font $L(font_button) -initial_state hidden
        } err]} {
            catch { msg -ERROR "DrinkMenu: editor vessel setup failed: $err" }
        }

        # ---- Mode confirm: one card, a question, two buttons ----
        if {[catch {
            # The one card with no gradient photo of its own: a transient
            # modal panel with no counterpart in the mock, whose 660 KB
            # photo would push the set past the pass's 4 MB budget (see
            # PROJECT_STATE). It keeps the flat card_fill face of v0.12.1.
            ${NS}::glass_card $page ed_cf $cx1 $L(ed_cf_y1) $L(ed_col_w) $L(ed_cf_h) "" 0
            dui add dtext $page [expr {$cx1 + $L(card_pad_x)}] [expr {$L(ed_cf_y1) + $L(ed_cf_q_dy)}] \
                -tags ed_cf_q -text [translate "Confirm?"] \
                -font $L(font_primary) -fill $L(c_ink) -anchor nw -justify left \
                -width [expr {$L(ed_col_w) - 2 * $L(card_pad_x)}] -initial_state hidden
            ${NS}::_theme_item $page ed_cf_q fill c_ink
            set by1 [expr {$L(ed_cf_y1) + $L(ed_cf_h) - $L(card_pad_y) - $L(btn_h)}]
            set by2 [expr {$by1 + $L(btn_h)}]
            ${NS}::bar_button $page ed_cf_no [expr {$cx1 + $L(card_pad_x)}] $by1 \
                [expr {$cx1 + $L(card_pad_x) + $L(btn_w_wide)}] $by2 btn \
                -label [translate "Cancel"] \
                -command ${NS}::edit_confirm_no \
                -label_font $L(font_button) -initial_state hidden
            ${NS}::bar_button $page ed_cf_yes [expr {$cx2 - $L(card_pad_x) - $L(btn_w_wide)}] $by1 \
                [expr {$cx2 - $L(card_pad_x)}] $by2 btn \
                -label [translate "Save"] \
                -command ${NS}::edit_confirm_yes \
                -label_font $L(font_button) -initial_state hidden
        } err]} {
            catch { msg -ERROR "DrinkMenu: editor confirm setup failed: $err" }
        }

        # ---- Bottom bar ----
        ${NS}::bar_button $page bar_cancel $lx $L(bar_y0) \
            [expr {$lx + $L(btn_w_std)}] $L(bar_y1) btn \
            -label [translate "Cancel"] \
            -command [list ${NS}::edit_request cancel] \
            -label_font $L(font_button)
        # Pass 48: Delete stands beside Cancel, in the danger tone, well
        # away from the saves (it was 30 px from Save as copy).
        ${NS}::bar_button $page bar_first $L(ed_first_x1) $L(bar_y0) \
            [expr {$L(ed_first_x1) + $L(btn_w_std)}] $L(bar_y1) danger \
            -label [translate "Delete"] \
            -command ${NS}::edit_first_tap \
            -label_font $L(font_button)
        ${NS}::bar_button $page bar_copy $L(ed_copy_x1) $L(bar_y0) \
            [expr {$L(ed_copy_x1) + $L(btn_w_wide)}] $L(bar_y1) btn \
            -label [translate "Save as copy"] \
            -command [list ${NS}::edit_request copy] \
            -label_font $L(font_button)
        # Pass 12 item B3: Save is the filled action; Cancel, Delete and
        # Save as copy stay ghost.
        ${NS}::bar_button $page bar_save $L(ed_save_x1) $L(bar_y0) $rx $L(bar_y1) primary \
            -label [translate "Save"] \
            -command [list ${NS}::edit_request save] \
            -label_font $L(font_button)

        # Hide every mode group but layers before the first show
        # (-initial 1 so the pre-show re-show cannot flash them).
        if {[catch { refresh } err]} {
            catch { msg -ERROR "DrinkMenu: editor initial refresh failed: $err" }
        }
    }

    proc _row_tags {i} {
        # The pen, edit tap and reorder arrows join the group so leaving
        # the mode hides them; within the mode the refresh row loop
        # re-decides each per row (pen/edtap: custom layers only; arrows:
        # not past their end), before the next idle redraw.
        return [list {*}[::plugins::DrinkMenu::dot_tags ed_row${i}_dot] ed_row${i}_name ed_row${i}_amt \
            ed_row${i}_mvup* ed_row${i}_mvdn* \
            ed_row${i}_minus* ed_row${i}_plus* ed_row${i}_rm* \
            ed_row${i}_pen ed_row${i}_edtap*]
    }

    proc _group_tags {mode} {
        upvar #0 ::plugins::DrinkMenu::L L
        set tags {}
        switch -- $mode {
            layers {
                lappend tags ed_vessel_btn* ed_group_btn* ed_add* ed_method* ed_profile_btn*
                for {set i 0} {$i < $L(ed_row_pool)} {incr i} { lappend tags {*}[_row_tags $i] }
            }
            group {
                lappend tags ed_cap_grp ed_grp_cancel*
                for {set k 0} {$k < 7} {incr k} {
                    lappend tags ed_grp${k}_bg ed_grp${k}_name ed_grp${k}_tap*
                }
            }
            method {
                lappend tags ed_cap_met ed_st_add* ed_st_done*
                upvar #0 ::plugins::DrinkMenu::steps_max sm_
                for {set i 0} {$i < $sm_} {incr i} {
                    lappend tags ed_st${i}_num ed_st${i}_txt ed_st${i}_tap* \
                        ed_st${i}_mvup* ed_st${i}_mvdn* ed_st${i}_rm*
                }
            }
            stepform {
                lappend tags ed_cap_sf ed_sf_entry ed_sf_hint ed_sf_cancel* ed_sf_save*
            }
            palette {
                lappend tags ed_cap_pal ed_pal_cancel* \
                    ed_palnew_bg ed_palnew_name ed_palnew_tap*
                for {set j 0} {$j < $L(ed_pal_pool)} {incr j} {
                    lappend tags ed_pal${j}_bg {*}[::plugins::DrinkMenu::dot_tags ed_pal${j}_dot] ed_pal${j}_name ed_pal${j}_tap*
                }
            }
            custing {
                # The gold half-overlays and the selection rings are in
                # the list too: entering the mode shows them all, and the
                # refresh's custing branch immediately corrects both to
                # their state (before the next idle redraw, so nothing
                # flashes); leaving the mode hides everything.
                lappend tags ed_cap_cust ed_cust_entry \
                    cunit_cap cunit_div cunit_lbl0 cunit_lbl1 \
                    cunit_onl cunit_onr cunit_ml* cunit_g* \
                    ed_cust_cancel* ed_cust_add*
                upvar #0 ::plugins::DrinkMenu::cust_colors cc
                for {set s 0} {$s < [llength $cc]} {incr s} {
                    lappend tags ed_sw$s ed_sw${s}_ring ed_sw${s}_tap*
                }
            }
            vessel {
                lappend tags ed_cap_ves ed_ves_cancel*
                for {set k 0} {$k < $L(ed_ves_pool)} {incr k} {
                    lappend tags ed_ves${k}_img \
                        ed_ves${k}_name ed_ves${k}_cap ed_ves${k}_tap* \
                        {*}[::plugins::DrinkMenu::cup_tags ed_ves${k}_cup]
                }
            }
            garnish {
                lappend tags ed_cap_garn ed_gn_entry ed_gn_hint ed_gn_cancel* ed_gn_save*
            }
            confirm {
                lappend tags ed_cf_img ed_cf_body ed_cf_q ed_cf_no* ed_cf_yes*
            }
        }
        return $tags
    }

    # Preview card only (also called from the name-entry trace).
    proc refresh_preview {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::DrinkMenu::L L
        upvar #0 ::plugins::DrinkMenu::vessels vessels
        upvar #0 ::plugins::DrinkMenu::edit_drink d
        upvar #0 ::plugins::DrinkMenu::edit_note note
        upvar #0 ::plugins::DrinkMenu::ui_unit ui_unit
        set NS ::plugins::DrinkMenu
        if {$d eq ""} { return }
        set vessel [dict get $d vessel]
        if {[dict exists $vessels $vessel]} {
            catch { ${NS}::update_cup $page ed_cup $d }
            ${NS}::_set_text $page ed_vessel \
                "[translate [dict get $vessels $vessel name]], [${NS}::format_amount [dict get $vessels $vessel capacity] $ui_unit]"
        } else {
            ${NS}::_set_text $page ed_vessel [translate "Unknown vessel"]
        }
        ${NS}::_set_text $page ed_total "[${NS}::format_amount [${NS}::drink_total $d] $ui_unit] [translate "total"]"
        set status [${NS}::edit_status $d]
        if {$status eq "" && $note ne ""} { set status $note }
        ${NS}::_set_text $page ed_status $status
        ${NS}::_show_tags $page ed_status [expr {$status ne ""}]
        # Pass 36: the tappable garnish line, pen after the fitted text.
        set gn {}
        catch { set gn [${NS}::clean_garnish [dict get $d garnish]] }
        set gtxt [translate "Garnish"]
        if {[llength $gn] > 0} {
            append gtxt ": [${NS}::garnish_to_text $gn]"
        } else {
            append gtxt ": [translate "none"]"
        }
        set gmaxw [expr {int(($L(ed_text_w) - $L(ed_pen_slot)) * $L(v2px))}]
        set gfit [${NS}::_fit_text $gtxt $L(font_caption) $gmaxw]
        ${NS}::_set_text $page ed_garnish $gfit
        ${NS}::_move_item $page ed_garn_pen [list \
            [expr {$L(ed_cup_x1) + $L(xs) \
                + int(ceil([${NS}::_text_w $L(font_caption) $gfit] * $L(px2v)))}] \
            $L(ed_garn_y)]
        ${NS}::_show_tags $page ed_garn_pen 1
    }

    # Full rebind: preview, the active mode group, rows, confirm card,
    # bottom bar. Creates nothing.
    proc refresh {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::DrinkMenu::L L
        upvar #0 ::plugins::DrinkMenu::vessels vessels
        upvar #0 ::plugins::DrinkMenu::ingredients ingredients
        upvar #0 ::plugins::DrinkMenu::edit_drink d
        upvar #0 ::plugins::DrinkMenu::edit_mode mode
        upvar #0 ::plugins::DrinkMenu::edit_pending pending
        upvar #0 ::plugins::DrinkMenu::edit_id edit_id
        upvar #0 ::plugins::DrinkMenu::ui_unit ui_unit
        set NS ::plugins::DrinkMenu
        set can [dui canvas]

        ${NS}::_set_text $page ed_title [translate "Edit custom drink"]
        refresh_preview

        # Mode groups.
        foreach m {layers palette vessel custing garnish method stepform group confirm} {
            ${NS}::_show_tags $page [_group_tags $m] [expr {$m eq $mode}]
        }
        if {$mode eq "custing"} {
            # Correct the just-shown dynamic items to their state: the
            # capsule's active half (uncached repaint) and the one
            # selection ring (Pass 33).
            upvar #0 ::plugins::DrinkMenu::cust_sel cust_sel
            upvar #0 ::plugins::DrinkMenu::cust_colors cust_colors
            upvar #0 ::plugins::DrinkMenu::cust_edit_id cust_edit_id
            ${NS}::_paint_controls $page
            for {set s 0} {$s < [llength $cust_colors]} {incr s} {
                ${NS}::_show_tags $page ed_sw${s}_ring [expr {$s == $cust_sel}]
            }
            # Pass 34: the same form edits an existing def; only the
            # words change. Bare dbutton tag for the relabel (the
            # wildcard form silently fails on-device).
            set editing [expr {$cust_edit_id ne ""}]
            ${NS}::_set_text $page ed_cap_cust \
                [expr {$editing ? [translate "Edit ingredient"] : [translate "Custom ingredient"]}]
            catch { dui item config $page ed_cust_add -label \
                [expr {$editing ? [translate "Save"] : [translate "Add layer"]}] }
        }

        set layers {}
        if {$d ne ""} { set layers [dict get $d layers] }
        set n [expr {[llength $layers] / 2}]
        if {$mode eq "layers"} {
            set vessel ""
            catch { set vessel [dict get $d vessel] }
            if {[dict exists $vessels $vessel]} {
                catch {
                    dui item config $page ed_vessel_btn -label \
                        "[translate "Vessel"]: [translate [dict get $vessels $vessel name]] ([${NS}::format_amount [dict get $vessels $vessel capacity] $ui_unit])"
                }
            }
            set maxw [expr {int($L(ed_name_maxw) * $L(v2px))}]
            for {set i 0} {$i < $L(ed_row_pool)} {incr i} {
                if {$i < $n} {
                    set li [expr {$n - 1 - $i}]
                    set ing [lindex $layers [expr {2 * $li}]]
                    set ml [lindex $layers [expr {2 * $li + 1}]]
                    # Pass 33: preset or the draft's own custom def.
                    set nm [${NS}::ing_prop $d $ing name $ing]
                    set color [${NS}::ing_prop $d $ing color "#888888"]
                    ${NS}::dot_paint $page ed_row${i}_dot $color
                    # Pass 34: a custom layer's row shows the pen right
                    # after its (pen-slot-shortened) name and arms the
                    # edit tap; preset rows show and arm neither.
                    set is_cust [expr {[dict exists $d custom_ings] \
                        && [dict exists $d custom_ings $ing]}]
                    set row_maxw [expr {$is_cust ? \
                        int(($L(ed_name_maxw) - $L(ed_pen_slot)) * $L(v2px)) : $maxw}]
                    set fitted [${NS}::_fit_text [translate $nm] $L(font_body) $row_maxw]
                    ${NS}::_set_text $page ed_row${i}_name $fitted
                    ${NS}::_set_text $page ed_row${i}_amt [${NS}::format_layer_amount $d $ing $ml $ui_unit]
                    ${NS}::_show_tags $page [_row_tags $i] 1
                    if {$is_cust} {
                        set penx [expr {$L(ed_row_name_x) + $L(xs) \
                            + int(ceil([${NS}::_text_w $L(font_body) $fitted] * $L(px2v)))}]
                        set peny [expr {$L(ed_rows_y0) + ($i + $L(ed_rows_first)) * $L(ed_row_pitch) + $L(ed_row_h) / 2.0}]
                        ${NS}::_move_item $page ed_row${i}_pen [list $penx $peny]
                    }
                    ${NS}::_show_tags $page [list ed_row${i}_pen ed_row${i}_edtap*] $is_cust
                    # Pass 35: no arrow past its end -- the top row has
                    # no up, the bottom visible row no down, a
                    # single-layer drink neither.
                    ${NS}::_show_tags $page ed_row${i}_mvup* [expr {$i > 0}]
                    ${NS}::_show_tags $page ed_row${i}_mvdn* [expr {$i < $n - 1}]
                } else {
                    ${NS}::_show_tags $page [_row_tags $i] 0
                }
            }
            # Pass 48: "+ Add layer" sits on the row after the last layer;
            # every item under ed_add* (art, tap rect, label) moves by the
            # same physical delta from where it last was, so nothing
            # depends on an anchor or on the shape's remembered box.
            set ay [expr {$L(ed_rows_y0) + ($n + $L(ed_rows_first)) * $L(ed_row_pitch)}]
            upvar #0 ::plugins::DrinkMenu::ed_add_y ed_add_y
            if {$ay != $ed_add_y} {
                set dy [expr {[dui::platform::rescale_y $ay] - [dui::platform::rescale_y $ed_add_y]}]
                catch {
                    foreach aid [$can find withtag "p:$page&&ed_add*"] { $can move $aid 0 $dy }
                }
                set ed_add_y $ay
            }
            ${NS}::_show_tags $page ed_add* [expr {$n < 6}]
            # Pass 37: the Method button always shows and carries the
            # step count (bare dbutton tag for the relabel).
            set stn [llength [${NS}::_draft_steps]]
            catch { dui item config $page ed_method -label \
                "[translate "Method"] ($stn)" }
            # Pass 38: the group button names the draft's choice.
            set grp custom
            catch { set grp [dict get $d group] }
            catch { dui item config $page ed_group_btn -label \
                "[translate "Group"]: [translate [${NS}::group_label $grp]]" }
            # Pass 40: the profile button says whether the draft is linked.
            catch { dui item config $page ed_profile_btn -label \
                [expr {[${NS}::drink_profile $d] ne {} ? \
                    [translate "Profile: linked"] : [translate "Profile: none"]}] }
        }

        if {$mode eq "group"} {
            # Paint the draft's group gold, the rest as plain chips
            # (uncached: seven chips, a handful of itemconfigures).
            upvar #0 ::plugins::DrinkMenu::group_order group_order
            upvar #0 ::plugins::DrinkMenu::L LL
            set grp custom
            catch { set grp [dict get $d group] }
            set gk 0
            foreach g [concat $group_order [list custom]] {
                set on [expr {$g eq $grp}]
                ${NS}::shape_paint $page ed_grp${gk}_bg [expr {$on ? "pill_on_fill" : "chip_bg"}] \
                    [expr {$on ? "pill_on_fill" : "chip_bg"}]
                foreach gid [${NS}::_ids $page ed_grp${gk}_name] {
                    catch { $can itemconfigure $gid \
                        -fill [expr {$on ? $LL(pill_on_text) : $LL(c_ink)}] }
                }
                incr gk
            }
        }

        if {$mode eq "method"} {
            upvar #0 ::plugins::DrinkMenu::steps_max steps_max
            set steps [${NS}::_draft_steps]
            set stn [llength $steps]
            set stmaxw [expr {int($L(ed_st_maxw) * $L(v2px))}]
            for {set i 0} {$i < $steps_max} {incr i} {
                if {$i < $stn} {
                    ${NS}::_set_text $page ed_st${i}_txt \
                        [${NS}::_fit_text [lindex $steps $i] $L(font_caption) $stmaxw]
                    ${NS}::_show_tags $page [list ed_st${i}_num ed_st${i}_txt \
                        ed_st${i}_tap* ed_st${i}_rm*] 1
                    ${NS}::_show_tags $page ed_st${i}_mvup* [expr {$i > 0}]
                    ${NS}::_show_tags $page ed_st${i}_mvdn* [expr {$i < $stn - 1}]
                } else {
                    ${NS}::_show_tags $page [list ed_st${i}_num ed_st${i}_txt \
                        ed_st${i}_tap* ed_st${i}_mvup* ed_st${i}_mvdn* ed_st${i}_rm*] 0
                }
            }
            ${NS}::_show_tags $page ed_st_add* [expr {$stn < $steps_max}]
        }

        if {$mode eq "stepform"} {
            upvar #0 ::plugins::DrinkMenu::step_edit_idx step_edit_idx
            ${NS}::_set_text $page ed_cap_sf [expr {$step_edit_idx == -1 ? \
                [translate "New step"] : "[translate "Edit step"] [expr {$step_edit_idx + 1}]"}]
        }

        if {$mode eq "confirm"} {
            set name ""
            catch { set name [string trim [dict get $d name]] }
            switch -- $pending {
                save   { set q "[translate "Save changes to"] $name?"; set yes [translate "Save"]; set no [translate "Cancel"] }
                copy   { set q "[translate "Save a copy as"] [${NS}::_copy_name]?"; set yes [translate "Save copy"]; set no [translate "Cancel"] }
                delete { set q "[translate "Delete"] $name? [translate "Hidden drinks can be restored; deleted ones cannot."]"; set yes [translate "Delete"]; set no [translate "Cancel"] }
                cancel { set q [translate "Discard changes?"]; set yes [translate "Discard"]; set no [translate "Keep editing"] }
                default { set q [translate "Confirm?"]; set yes [translate "OK"]; set no [translate "Cancel"] }
            }
            ${NS}::_set_text $page ed_cf_q $q
            catch { dui item config $page ed_cf_yes -label $yes }
            catch { dui item config $page ed_cf_no -label $no }
        }

        # Bottom bar: Delete only once the draft has been saved at least
        # once (hidden for a never-saved draft: an unsaved "Copy & edit"
        # copy or a "+ New drink" draft). Save and Save as copy show as
        # soon as the draft validates and no confirmation card is open --
        # v0.10.3 (owner decision) restores Save as copy on fresh copies,
        # which v0.9.0 had tied to the Delete rule.
        set valid 0
        if {$d ne ""} { lassign [${NS}::validate_drink $d] valid why }
        # Pass 48: the bar belongs to the layers mode alone -- every
        # sub-mode (palette, vessel, group, method, garnish, custom
        # ingredient, confirm) has its own Cancel / Save, so the page
        # never shows two Cancels.
        set show_actions [expr {$mode eq "layers"}]
        set saved [${NS}::is_custom $edit_id]
        ${NS}::_show_tags $page bar_cancel* $show_actions
        ${NS}::_show_tags $page bar_first* [expr {$show_actions && $saved}]
        ${NS}::_show_tags $page bar_copy* [expr {$show_actions && $valid}]
        ${NS}::_show_tags $page bar_save* [expr {$show_actions && $valid}]
        # Pass 48: the keyboard Done shows only while the name entry has
        # focus, and an empty name shows its hint.
        ${NS}::_name_hint_apply
        ${NS}::_show_tags $page ed_done* [${NS}::_name_focused]
    }

    proc show {page_to_hide page_to_show} {
        set page [namespace tail [namespace current]]
        if {[catch {
            ::plugins::DrinkMenu::_apply_palette
            ::plugins::DrinkMenu::_retheme $page
            refresh
        } err]} {
            catch { msg -ERROR "DrinkMenu: editor show repaint failed: $err" }
        }
    }
}

namespace eval ::plugins::DrinkMenu {
    # First bottom-bar action button: always Delete, hidden until the
    # draft has been saved once (see the visibility check in
    # DrinkMenu_edit::refresh).
    proc edit_first_tap {} {
        edit_request delete
    }

    # Chip width in virtual units from measured text (physical px ->
    # virtual via px2v). Used by the detail page and the headless check.
    proc _chip_width {name amount} {
        variable L
        set tw [expr {([_text_w $L(font_body) $name] + [_text_w $L(font_body_b) $amount]) * $L(px2v)}]
        return [expr {int(ceil(2 * $L(det_chip_pad_x) + $L(det_chip_dot) + $L(det_chip_gap_in) \
            + $L(det_chip_gap_amt) + $tw))}]
    }
    # Make the helper procs importable by the page namespaces.
    namespace export _set_text _show_tags _move_item _fit_text format_amount _text_w _ids
}
