#
# GrindAdvisor.tcl  --  implementation for the "Grind Advisor" DE1app plugin.
#
# Everything here is READ-ONLY with respect to SDB. The plugin never inserts,
# updates, deletes, or alters schema. It opens the shot database read-only (or
# reuses an existing connection) purely to SELECT the latest one or two shots.
#
# The two integration points most likely to need tweaking for a given install
# are (a) how a finished shot is detected and (b) where the SDB file lives.
# Both are handled defensively below with several fallbacks.
#

catch {package require sqlite3}

namespace eval ::plugins::GrindAdvisor {

    # Handle name used if we have to open our own read-only connection.
    variable _own_db ::plugins::GrindAdvisor::__sdb_ro

    # Throttle for the last-resort state-trace fallback.
    variable _last_state_run 0

    # ------------------------------------------------------------------
    #  Column-name recognition
    #
    #  Each logical field maps to an ordered list of case-insensitive regex
    #  patterns. The first pattern that matches a column wins, and more
    #  specific patterns are listed first so e.g. "extraction_time" is
    #  preferred over a bare "time", and "clock" is claimed as the timestamp
    #  before "time" can be mistaken for the shot duration.
    # ------------------------------------------------------------------
    variable field_patterns
    array set field_patterns {
        grind        {{^grinder_setting$} {grinder_?setting} {grind_?setting} {grind} {grinder}}
        duration     {{^extraction_time$} {extraction_?time} {shot_?time} {brew_?time} {espresso_?elapsed} {elapsed} {duration} {(^|_)secs?(_|$)} {(^|_)time(_|$)}}
        dose         {{^grinder_dose_weight$} {grinder_?dose} {dose_?weight} {(^|_)dose(_|$)} {bean_?weight} {(^|_)in_?weight}}
        set_yield    {{^target_drink_weight$} {target_?drink_?weight} {target_?yield} {set_?yield} {desired_?shot_?weight} {final_?desired_?shot_?weight}}
        actual_yield {{^drink_weight$} {actual_?yield} {actual_?drink_?weight} {measured_?yield} {scale_?weight} {drink_?weight} {beverage_?weight} {weight_?out} {(^|_)yield} {(^|_)out_?weight}}
        actual_dose  {{^bean_weight$} {actual_?dose} {measured_?dose} {dose_?in} {scale_?dose} {dry_?weight} {ground_?weight}}
        timestamp    {{(^|_)clock(_|$)} {timestamp} {datetime} {(^|_)date(_|$)} {epoch}}
        profile      {{^profile_title$} {profile_?title} {profile_?name} {(^|_)profile(_|$)}}
        bev_type     {{^beverage_type$} {^final_beverage_type$} {beverage_?type} {beverage} {drink_?type}}
        filename     {{^filename$}}
        removed      {{^removed$}}
    }

    variable bag_field_patterns
    array set bag_field_patterns {
        bean       {{^bean_?name$} {^coffee_?name$} {^beans?$} {^coffee$} {bean_?type} {bean_?desc} {bean}}
        roaster    {{^roaster$} {bean_?brand} {coffee_?roaster} {roaster}}
        origin     {{^origin$} {bean_?origin} {coffee_?origin} {bean_?country} {bean_?region} {country} {region}}
        roast_date {{^roast_?date$} {roast}}
    }

    variable last_recommendation {}

    # Field -> SDB column mapping for the bag fields, cached by
    # _resolve_bag_fields so current_bag_key never has to open the database.
    variable bag_field_cols {}

    # v1.8.2 guard state: popup re-entry flag and navigation-watch installer.
    variable popup_active 0
    variable nav_watched  0

    # ------------------------------------------------------------------
    #  Settings safety net
    #
    #  The DE1app plugin framework may create ::plugins::GrindAdvisor::settings
    #  as an empty array *before* this file's defaults run, so we (a) fill any
    #  missing key without clobbering user-set ones, and (b) always read through
    #  _setting so a missing key falls back to a literal default instead of
    #  throwing "no such element in array".
    # ------------------------------------------------------------------
    proc apply_defaults {} {
        variable settings
        foreach {k v} {
            target_time              28.0
            popup_delay_ms           1500
            popup_theme              dark
            popup_font_scale         1.0
            enable_popup             1
            grinder_min              0
            grinder_max              50
            grind_rounding_increment 0.5
            history_show_datetime    1
            history_show_set_grind   1
            history_show_recommended_grind 1
            history_show_set_dose    1
            history_show_set_ratio   1
            history_show_set_yield   1
            history_show_actual_yield 0
            history_show_shot_time   1
            history_show_reason      1
            history_show_bag_shot    1
            history_show_bag_name    1
            dose_yield_mode          auto
            dose_min                 12.0
            dose_max                 22.0
            ratio_min                1.0
            ratio_max                4.0
            segment_by_profile       1
            theme                    light
        } {
            if {![info exists settings($k)]} { set settings($k) $v }
        }
        # v3.12.0: the page theme must be one of exactly two values.
        if {$settings(theme) ni {light dark}} { set settings(theme) light }
        # v3.17.0 (F5): the nine numeric settings are kept canonical and in
        # range ("28,5" -> 28.5, "abc" -> the default, 99999 ms -> 30000),
        # so the steppers, the engine's _to_float readers, `after` and the
        # popup fonts all see the same number. The ranges are wide enough
        # that no sensible old value moves; one that does is logged.
        variable num_spec
        foreach key [array names num_spec] {
            set new [_num_text $key]
            set old $settings($key)
            if {[scan $old %f oldnum] != 1 || abs($oldnum - $new) > 1e-9} {
                catch { msg "GrindAdvisor: setting $key '$old' read as $new (v3.17.0 steppers)" }
            }
            set settings($key) $new
        }
    }

    # ------------------------------------------------------------------
    #  v3.17.0 (F5) numeric settings: every one is a stepper now, so the
    #  value can only ever be a number inside its range. Per key:
    #    step  min  max  decimals  default
    #  The lower of each pair stays below the upper (_num_bounds).
    # ------------------------------------------------------------------
    # Ranges are deliberately wide (review: a 65 s target, a 32 g dose bound
    # or a 0.5 grinder bound must survive the upgrade unchanged); the
    # grinder bounds keep one decimal for fine-scale grinders.
    variable num_spec
    array set num_spec {
        target_time      {0.5    5   120   1  28.0}
        grinder_min      {1    -99   999   1  0}
        grinder_max      {1    -99   999   1  50}
        popup_delay_ms   {250    0 30000   0  1500}
        popup_font_scale {0.05 0.8   1.5   2  1.0}
        dose_min         {0.5    1    50   1  12.0}
        dose_max         {0.5    1    50   1  22.0}
        ratio_min        {0.1  0.5    10   1  1.0}
        ratio_max        {0.1  0.5    10   1  4.0}
    }
    variable num_pairs {grinder_min grinder_max dose_min dose_max ratio_min ratio_max}

    proc _num_round {v dec} {
        set m [expr {10 ** $dec}]
        return [expr {round($v * $m) / double($m)}]
    }

    # The setting as a number, in range. On a key with decimals a comma
    # separator reads as a point ("28,5" is 28.5; the old typed entries
    # silently used 28) -- not on a whole-number key, where "1,500" means
    # thousands. Anything else that is not a plain decimal -- "", "abc",
    # "NaN", "1e5" -- falls back to the default. `scan`, not double(): Tcl
    # 8.6 reads a leading zero ("08") as an invalid octal and throws.
    proc _num_value {key} {
        variable settings
        variable num_spec
        lassign $num_spec($key) step lo hi dec def
        set raw $def
        if {[info exists settings($key)]} { set raw [string trim $settings($key)] }
        if {$dec > 0 && [regexp {^[-+]?[0-9]+,[0-9]+$} $raw]} { set raw [string map {, .} $raw] }
        if {![regexp {^[-+]?([0-9]+\.?[0-9]*|\.[0-9]+)$} $raw]} { set raw $def }
        scan $raw %f num
        return [_num_round [_clamp $num $lo $hi] $dec]
    }

    proc _num_text {key} {
        variable num_spec
        return [format %.[lindex $num_spec($key) 3]f [_num_value $key]]
    }

    proc _num_partner {key} {
        variable num_pairs
        set i [lsearch -exact $num_pairs $key]
        if {$i < 0} { return "" }
        return [lindex $num_pairs [expr {$i % 2 ? $i - 1 : $i + 1}]]
    }

    # Effective range: the key's own, narrowed so a pair keeps one step
    # between its ends while it is in order -- equal counts as in order
    # (review: an equal pair left free let one tap invert dose or ratio
    # bounds, which the engine does not swap back). An inverted pair
    # (possible from old typed values; the engine swaps grinder bounds
    # itself) gets the plain range, and _step never moves against the tap,
    # so one tap can never jump across the scale.
    proc _num_bounds {key} {
        variable num_spec
        variable num_pairs
        lassign $num_spec($key) step lo hi dec def
        set i [lsearch -exact $num_pairs $key]
        if {$i >= 0} {
            set partner [_num_partner $key]
            set v [_num_value $key]
            set pv [_num_value $partner]
            if {$i % 2 == 0 && $v <= $pv} {
                set hi [_num_round [expr {min($hi, $pv - $step)}] $dec]
            } elseif {$i % 2 == 1 && $pv <= $v} {
                set lo [_num_round [expr {max($lo, $pv + $step)}] $dec]
            }
        }
        return [list $lo $hi]
    }

    # Quick taps speed up, copied from Lumen's ::lumen::act::_accel_step
    # (skin.tcl, 350 ms window since Lumen 0.28.1) so both steppers the
    # owner uses feel the same: 1x the step, 5x once three taps land under
    # 350 ms apart in the same direction, 10x after six. A pause or a
    # direction change drops straight back to 1x. `info exists` instead of
    # Lumen's catch: a swallowed error dirties errorInfo (MT v0.21.3).
    variable accel
    array set accel {}
    proc _accel_mult {key dir} {
        variable accel
        set now [clock milliseconds]
        set last 0 ; set streak 0 ; set lastdir 0
        if {[info exists accel($key)]} { lassign $accel($key) last streak lastdir }
        if {$dir == $lastdir && ($now - $last) < 350} {
            incr streak
        } else {
            set streak 0
        }
        set accel($key) [list $now $streak $dir]
        if {$streak >= 6} { return 10 }
        if {$streak >= 3} { return 5 }
        return 1
    }

    # A -/+ tap. Saved with the rest on the page's Done, as the typed
    # entries were.
    proc _step {page key dir} {
        variable settings
        variable num_spec
        lassign $num_spec($key) step lo hi dec def
        lassign [_num_bounds $key] lo hi
        set v [_num_value $key]
        set nv [expr {$v + $dir * $step * [_accel_mult $key $dir]}]
        set nv [_num_round [_clamp $nv $lo $hi] $dec]
        if {($dir > 0 && $nv < $v) || ($dir < 0 && $nv > $v)} { set nv $v }
        set settings($key) [format %.${dec}f $nv]
        _stepper_refresh $page $key
        set partner [_num_partner $key]
        if {$partner ne ""} { _stepper_refresh $page $partner }
    }

    # Value text, and each end disabled at its limit (the pager rule:
    # always visible, greyed when it can do nothing). Through dui's own
    # enable_or_disable, which leaves hidden items alone (dui.tcl ~7943):
    # show hooks run after idle, so a GA page left in the same event-loop
    # turn must not set `-state normal` -- that would un-hide its buttons
    # over the page now on screen (review; the MT v0.23.1 trap). The
    # literal ga_<key>_dec* tag reaches shape, label and tap rect.
    # v3.17.4 (F22, review): -initial 1 also writes the st: tag, so a load
    # (items hidden) still paints the greyed end on the first frame. The
    # stepper buttons are never hidden, so the shared st: slot is safe.
    proc _stepper_refresh {page key} {
        lassign [_num_bounds $key] lo hi
        set v [_num_value $key]
        catch { dui item config $page ga_${key}_value -text [_num_text $key] }
        catch { dui item enable_or_disable [expr {$v > $lo}] $page ga_${key}_dec* -initial 1 }
        catch { dui item enable_or_disable [expr {$v < $hi}] $page ga_${key}_inc* -initial 1 }
    }

    # [-] value [+], right-aligned so the + button ends at x2, on a btn_h
    # row starting at y. Returns the stepper's left edge. Tags ga_<key>_*
    # (unique: dui refuses a repeated first tag, and dui's press flash is
    # canvas-global by tag name).
    proc _add_stepper {page key x2 y} {
        variable L
        set y2 [expr {$y + $L(btn_h)}]
        set x0 [expr {$x2 - $L(step_w)}]
        set vx0 [expr {$x0 + $L(step_btn_w) + $L(sm)}]
        set vx1 [expr {$vx0 + $L(step_val_w)}]
        dui add dbutton $page $x0 $y [expr {$x0 + $L(step_btn_w)}] $y2 \
            -tags ga_${key}_dec -label [format %c 0x2212] \
            -command [list ::plugins::GrindAdvisor::_tap $page ga_${key}_dec [list ::plugins::GrindAdvisor::_step $page $key -1]] \
            -label_font $L(font_button) -style ga_btn
        # The plate is outlined in the card's own hairline: entry_bg alone is
        # invisible on the light theme's white card (review).
        rounded_rect $page $vx0 $y $vx1 $y2 $L(btn_radius) \
            -fill $L(entry_bg) -outline $L(sec_outline) -width 2 -tags ga_${key}_box
        dui add dtext $page [expr {($vx0 + $vx1) / 2}] [expr {($y + $y2) / 2}] \
            -tags ga_${key}_value -text [_num_text $key] -font $L(font_primary) \
            -fill $L(value_blue) -anchor center -justify center
        dui add dbutton $page [expr {$x2 - $L(step_btn_w)}] $y $x2 $y2 \
            -tags ga_${key}_inc -label "+" \
            -command [list ::plugins::GrindAdvisor::_tap $page ga_${key}_inc [list ::plugins::GrindAdvisor::_step $page $key 1]] \
            -label_font $L(font_button) -style ga_btn
        return $x0
    }

    proc _setting {key default} {
        variable settings
        if {[info exists settings($key)]} { return $settings($key) }
        return $default
    }

    # ------------------------------------------------------------------
    #  v2.0.0 design-system layout tokens, mirrored from the proven
    #  ShotHistoryEditor implementation (plugins/ShotHistoryEditor,
    #  _init_layout) -- same coordinate basis, same two scale factors:
    #
    #  * Coordinates are in the app's VIRTUAL 2560x1600 canvas space; the
    #    dui framework rescales them to the physical screen itself
    #    (confirmed against de1app-core/dui.tcl: dui::platform::rescale_x/y
    #    convert virtual -> physical, and stock pages draw at x up to 2560).
    #    Never feed physical winfo sizes into coordinates (double-scaling,
    #    half-size UI -- ShotHistoryEditor v0.3.2 lesson).
    #  * Fonts are real Tk font objects sized in PHYSICAL pixels (negative
    #    Tk size = pixels), because -font / -label_font values bypass dui's
    #    coordinate rescale entirely (ShotHistoryEditor v0.3.2/v0.3.3
    #    lesson). v3.23.0 (F8): their scale comes from the SAME source as the
    #    coordinates -- `dui cget screen_size_height`, the canvas height the
    #    core rescales to (800 on the 1340x800 tablet) -- never from
    #    `winfo screenheight`, which is 736 there (the Android bar is cut
    #    off) and drew every page font at 92%. One shared helper; every
    #    button label uses L(font_button); no per-button font sizes.
    #
    #  All page-body coordinates below live in this one block; no page
    #  hardcodes coordinates. (The after-shot popup overlay is a separate
    #  raw-Tk canvas widget stacked above the skin canvas, NOT a dui page,
    #  so it correctly uses physical-pixel geometry via _pgeom/_font.)
    # ------------------------------------------------------------------
    variable L
    array set L {}

    # ------------------------------------------------------------------
    #  Page-theme palette (v3.12.0). Every color the settings pages
    #  paint comes from these tokens, per settings(theme) (light | dark,
    #  default light). The after-shot popup and the History / Bag Stats
    #  overlays keep their own independent popup_theme (_colors).
    #
    #  v3.16.7 contrast pass (WCAG 2.1 at the tablet's rendered sizes;
    #  the same values as ShotHistoryEditor, MaintenanceTracker and
    #  BeanScanner): btn_label_fill lives here now, per theme -- dark ink
    #  on the light periwinkle (the old white was 1.7:1), white on the
    #  dark slate. text_mut is #595959 light (was #666666, 4.0:1 on the
    #  page) and #9aa0ad dark (was #8d92a0, 3.9:1 on cards); the light
    #  value_blue is #2753bb (was #4e85f4, 3.4:1 in the entries).
    # ------------------------------------------------------------------

    # v3.23.0 (design review F21): the four status roles shared by every
    # owner plugin and Lumen -- the ONE place their colours are written;
    # _apply_palette (pages, per theme) and _colors (overlays, per family)
    # both read them. Text colours, >= 4.5:1 on every surface they reach at
    # the rendered size (dark: page, card, entry, overlay panel and scrim,
    # glass panel and Lumen's baked glass, worst danger 4.67 on the entry;
    # light: worst ok 4.75 on the grey page). Never on a button label.
    #   ok      a good result (the high-confidence dot)
    #   warn    a warning in words (out of reach, channeling)
    #   danger  a failure (Recalculate from History failed)
    #   info    a value or a neutral plot (setting values, the gauge, Curve)
    proc _status_roles {dark} {
        if {$dark} {
            return [dict create ok "#2FD3A4" warn "#E8B34C" danger "#ff8a80" info "#8ab4ff"]
        }
        return [dict create ok "#086750" warn "#7a4b00" danger "#962219" info "#2753bb"]
    }

    proc _apply_palette {} {
        variable L
        variable settings
        set dark 0
        if {[info exists settings(theme)] && $settings(theme) eq "dark"} { set dark 1 }
        # v3.23.0 (F21): L(ok) L(warn) L(danger) L(info). value_blue (setting
        # values, the on-glyph) IS info; the gauge fill is info too (light
        # was #4d84f3: 2.85:1 against the empty segment, now 5.53:1; dark
        # #8fb8ff -> #8ab4ff, 4.24:1).
        dict for {role c} [_status_roles $dark] { set L($role) $c }
        set L(value_blue) $L(info)
        set L(conf_fill)  $L(info)
        if {$dark} {
            set L(page_bg)      "#23252e"
            set L(sec_fill)     "#32353f"
            set L(sec_outline)  "#464b58"
            set L(text_hi)      "#e8e9ee"
            set L(text_body)    "#c2c5cf"
            set L(text_mut)     "#9aa0ad"   ;# v3.16.7
            set L(entry_bg)     "#3a3e4a"
            set L(conf_empty)   "#454a57"
            set L(btn_fill)     "#4a5473"
            set L(btn_disabled_fill) "#3a3e4a"
            set L(btn_label_fill) "#ffffff" ;# v3.16.7
            set L(btn_press_fill) "#5f6a8c" ;# v3.22.0 (F9): white 5.35:1, 1.40:1 vs rest
        } else {
            set L(page_bg)      "#d5d6e3"   ;# stock settings-page grey
            set L(sec_fill)     "#FFFFFF"
            set L(sec_outline)  "#dcdcdc"
            set L(text_hi)      "#2b2b2b"
            set L(text_body)    "#444444"
            set L(text_mut)     "#595959"   ;# v3.16.7
            set L(entry_bg)     "#fbfaff"
            set L(conf_empty)   "#e3e6ee"
            set L(btn_fill)     "#c0c5e3"   ;# stock dbutton periwinkle
            set L(btn_disabled_fill) "#dddddd"
            set L(btn_label_fill) "#2b2b2b" ;# v3.16.7
            set L(btn_press_fill) "#a6acd1" ;# v3.22.0 (F9): #2b2b2b 6.37:1, 1.31:1 vs rest
        }
        # v3.22.0 (F10): the one primary action per page -- MaintenanceTracker's
        # green with a white label in both themes (5.30:1), pressed darker
        # (7.97:1). GA has no destructive action, so no danger button face
        # (the danger TEXT colour is L(danger), F21).
        set L(btn_primary_fill)  "#0a7a5f"
        set L(btn_primary_label) "#ffffff"
        set L(btn_primary_press) "#075c48"
        # v3.22.0 (F9): how long a pressed button keeps its press tone after
        # its command returns (DrinkMenu's 120 ms).
        set L(press_ms) 120
    }

    proc _glyph_for {name} {
        set glyph ""
        catch {
            if {[dui symbol exists $name]} { set glyph [dui symbol get $name] }
        }
        return $glyph
    }

    # v3.24.0 (design review F23): the punctuation GA draws, named once and
    # built from code points so the source stays ASCII (owner rule). An
    # unknown name gives "" (a typo shows nothing, never a wrong glyph).
    proc _char {name} {
        switch -- $name {
            ellipsis { return [format %c 0x2026] }
            middot   { return [format %c 0xB7] }
            endash   { return [format %c 0x2013] }
            arrow    { return [format %c 0x2192] }
            warning  { return [format %c 0x26A0] }
        }
        return ""
    }

    # The separator between facts on one line, GA's spacing ("a  .  b").
    proc _sep {} {
        return "  [_char middot]  "
    }

    # Moon in light mode (tap for dark), sun-bright in dark; text fallback.
    proc _theme_button_face {} {
        variable L
        variable settings
        set dark 0
        if {[info exists settings(theme)] && $settings(theme) eq "dark"} { set dark 1 }
        # v3.23.0: text picked with if, never `expr ?:`.
        set icon moon
        set word [translate "Dark"]
        if {$dark} {
            set icon sun-bright
            set word [translate "Light"]
        }
        if {[info exists L(have_icons)] && $L(have_icons)} {
            set g [_glyph_for $icon]
            if {$g ne ""} { return $g }
        }
        return $word
    }

    # v3.17.1 (F19): the History Display Options row glyph -- Font Awesome
    # square-check / square from the icon font the theme toggle uses, or
    # On / Off where either glyph is missing (then drawn in the body font).
    proc _toggle_icons {} {
        variable L
        return [expr {[info exists L(have_icons)] && $L(have_icons)
                      && [_glyph_for square] ne "" && [_glyph_for square-check] ne ""}]
    }

    proc _toggle_face {on} {
        if {[_toggle_icons]} {
            if {$on} { return [_glyph_for square-check] }
            return [_glyph_for square]
        }
        if {$on} { return [translate "On"] }
        return [translate "Off"]
    }

    proc toggle_theme {} {
        variable settings
        if {$settings(theme) eq "dark"} {
            set settings(theme) light
        } else {
            set settings(theme) dark
        }
        save_settings
        _apply_palette
        _retheme_all
        catch { ::dui::pages::GrindAdvisor_settings::refresh_values GrindAdvisor_settings }
        catch { dui item config GrindAdvisor_settings btn_theme -label [_theme_button_face] }
        catch { msg "GrindAdvisor: page theme switched to $settings(theme)" }
    }

    # Repaint every palette-colored item by bare tag across the 7 dui
    # pages (the popup/overlay dialogs re-read their own _colors on every
    # draw and need nothing here). Buttons restyle through their -btn
    # shape tags and (v3.16.7) their -lbl label tags: the label ink
    # follows the theme now (was white in both). History Display Options'
    # toggle glyphs are painted by that page's render (v3.17.1).
    proc _retheme_all {} {
        variable L
        foreach p {GrindAdvisor_settings GrindAdvisor_history_options
                   GrindAdvisor_advanced GrindAdvisor_help
                   GrindAdvisor_diagnostics GrindAdvisor_calculation_details
                   GrindAdvisor_dose_yield} {
            catch { dui item config $p page_bg -fill $L(page_bg) -outline $L(page_bg) }
            catch { dui item config $p page_title -fill $L(text_hi) }
            catch { dui item config $p subtitle -fill $L(text_mut) }
            catch { dui item config $p version_text -fill $L(text_mut) }
            catch { dui item config $p pg_ind -fill $L(text_mut) }
        }
        # Section cards.
        foreach {p sec} {
            GrindAdvisor_settings sec_shot
            GrindAdvisor_settings sec_actions
            GrindAdvisor_settings sec_reco
            GrindAdvisor_settings sec_popup
            GrindAdvisor_advanced sec_ptun
            GrindAdvisor_advanced sec_data
            GrindAdvisor_advanced sec_tools
            GrindAdvisor_help sec_help
            GrindAdvisor_diagnostics sec_diag
            GrindAdvisor_calculation_details sec_calcd
            GrindAdvisor_dose_yield sec_dy
            GrindAdvisor_history_options sec_hgrind
            GrindAdvisor_history_options sec_hdose
            GrindAdvisor_history_options sec_hshot
        } {
            catch { dui item config $p ${sec}_bg -fill $L(sec_fill) -outline $L(sec_outline) }
            catch { dui item config $p ${sec}_title -fill $L(text_hi) }
        }
        # Text roles.
        foreach {p tag role} {
            GrindAdvisor_settings target_time_label text_body
            GrindAdvisor_settings grinder_min_label text_body
            GrindAdvisor_settings grinder_max_label text_body
            GrindAdvisor_settings rounding_label text_body
            GrindAdvisor_settings theme_label text_body
            GrindAdvisor_settings popup_label text_body
            GrindAdvisor_settings conf_label text_body
            GrindAdvisor_settings conf_text text_body
            GrindAdvisor_settings conf_step text_body
            GrindAdvisor_settings rounding_value value_blue
            GrindAdvisor_settings popup_theme_value value_blue
            GrindAdvisor_settings enable_popup_value value_blue
            GrindAdvisor_advanced popup_delay_ms_label text_body
            GrindAdvisor_advanced popup_font_scale_label text_body
            GrindAdvisor_advanced recalc_note text_mut
            GrindAdvisor_help help_text text_body
            GrindAdvisor_diagnostics diagnostics_text text_body
            GrindAdvisor_calculation_details calculation_text text_body
            GrindAdvisor_dose_yield mode_label text_body
            GrindAdvisor_dose_yield mode_value value_blue
            GrindAdvisor_dose_yield dose_min_label text_body
            GrindAdvisor_dose_yield dose_max_label text_body
            GrindAdvisor_dose_yield ratio_min_label text_body
            GrindAdvisor_dose_yield ratio_max_label text_body
            GrindAdvisor_dose_yield dy_help text_mut
            GrindAdvisor_history_options history_show_set_grind_label text_body
            GrindAdvisor_history_options history_show_recommended_grind_label text_body
            GrindAdvisor_history_options history_show_reason_label text_body
            GrindAdvisor_history_options history_show_set_dose_label text_body
            GrindAdvisor_history_options history_show_set_ratio_label text_body
            GrindAdvisor_history_options history_show_set_yield_label text_body
            GrindAdvisor_history_options history_show_actual_yield_label text_body
            GrindAdvisor_history_options history_show_datetime_label text_body
            GrindAdvisor_history_options history_show_shot_time_label text_body
            GrindAdvisor_history_options history_show_bag_shot_label text_body
            GrindAdvisor_history_options history_show_bag_name_label text_body
        } {
            catch { dui item config $p $tag -fill $L($role) }
        }
        # v3.17.0 (F5): steppers -- the value plate and value, and both
        # buttons (shape, disabled shape, label) the way every button below
        # is repainted. They replace the nine Tk entries.
        foreach {p keys} {
            GrindAdvisor_settings {target_time grinder_min grinder_max}
            GrindAdvisor_advanced {popup_delay_ms popup_font_scale}
            GrindAdvisor_dose_yield {dose_min dose_max ratio_min ratio_max}
        } {
            foreach k $keys {
                catch { dui item config $p ga_${k}_box -fill $L(entry_bg) -outline $L(sec_outline) }
                catch { dui item config $p ga_${k}_value -fill $L(value_blue) }
                foreach t [list ga_${k}_dec ga_${k}_inc] {
                    catch { _paint_btn $p $t }
                }
            }
        }
        # v3.17.1 (F19): History Display Options toggle glyphs -- their
        # colour follows each row's state, so the page's own render paints
        # them (value blue on, muted off). The invisible row buttons have no
        # fill and are deliberately not in the button walk below.
        catch { ::dui::pages::GrindAdvisor_history_options::render GrindAdvisor_history_options }
        # Confidence gauge segments get their real fills from
        # refresh_confidence (palette-aware); park them on the empty color
        # so nothing keeps a stale tint if refresh cannot run.
        for {set i 0} {$i < 10} {incr i} {
            catch { dui item config GrindAdvisor_settings conf_seg$i \
                -fill $L(conf_empty) -outline $L(conf_empty) }
        }
        # Buttons: shape fills, and (v3.16.7) the label ink per theme via
        # the bare <tag>-lbl text item -- btn_theme's label is its
        # sun/moon icon, recolored the same way. -disabledfill stays the
        # ga_btn aspect's #999999.
        foreach {p tags} {
            GrindAdvisor_settings {show_latest_recommendation recent_shot_history
                                   bag_stats_action rounding_btn theme_btn popup_btn
                                   page_done advanced ga_help btn_theme}
            GrindAdvisor_history_options {page_done}
            GrindAdvisor_advanced {recalc_from_history dose_yield_source
                                   history_display_options diagnostics
                                   calculation_details bag_stats page_done}
            GrindAdvisor_help {page_done pg_prev pg_next}
            GrindAdvisor_diagnostics {page_done pg_prev pg_next}
            GrindAdvisor_calculation_details {page_done pg_prev pg_next}
            GrindAdvisor_dose_yield {mode_btn page_done}
        } {
            # v3.22.0 (F10): by role (show_latest_recommendation is primary),
            # through the same painter the press restore uses.
            foreach t $tags {
                catch { _paint_btn $p $t }
            }
        }
    }

    # ------------------------------------------------------------------
    #  v3.22.0 (design review F9 / F10): press feedback and button roles.
    #
    #  dui runs a dbutton's -command at touch-down, synchronously, and Tk
    #  repaints only after it returns, so a slow command (an SDB read, a
    #  page load) looked like a missed tap. Every labelled GA button is
    #  created with -command [list ::plugins::GrindAdvisor::_tap $page
    #  $tag <cmd>]: _tap tints THIS page's face (<tag>-btn, page-scoped
    #  through dui item config) to the role's press tone, paints it now
    #  (update idletasks, never a full update), arms the restore BEFORE
    #  running the command (an error cannot strand the tint), then runs it.
    #  The restore repaints through _paint_btn from the palette and role
    #  AT RESTORE TIME, so a tap that switches the theme restores in the
    #  new one. The core's -pressfill is never used: it restores the
    #  creation fill and recolours same-named buttons in other plugins.
    #  The History Display Options rows are invisible tap rects (no face):
    #  never wrapped; their glyph flip is the feedback.
    #
    #  Roles (F10): neutral (ga_btn) everywhere, one primary per page at
    #  most -- only "Show next grind" on the main page (ga_btn_primary).
    #  GA deletes nothing, so there is no danger button role.
    # ------------------------------------------------------------------
    variable btn_roles
    array set btn_roles {GrindAdvisor_settings,show_latest_recommendation primary}
    variable press_after
    array set press_after {}

    proc _btn_role {page tag} {
        variable btn_roles
        if {[info exists btn_roles($page,$tag)]} { return $btn_roles($page,$tag) }
        return neutral
    }

    # The one writer of a button's colours after creation: the theme
    # repaint and the press restore.
    proc _paint_btn {page tag} {
        variable L
        if {[_btn_role $page $tag] eq "primary"} {
            set f $L(btn_primary_fill)
            set ink $L(btn_primary_label)
        } else {
            set f $L(btn_fill)
            set ink $L(btn_label_fill)
        }
        dui item config $page ${tag}-btn -fill $f -outline $f \
            -disabledfill $L(btn_disabled_fill) -disabledoutline $L(btn_disabled_fill)
        dui item config $page ${tag}-lbl -fill $ink
    }

    proc _tap {page tag cmd} {
        variable L
        variable press_after
        set key $page,$tag
        if {[info exists press_after($key)]} { after cancel $press_after($key) }
        set p $L(btn_press_fill)
        if {[_btn_role $page $tag] eq "primary"} { set p $L(btn_primary_press) }
        dui item config $page ${tag}-btn -fill $p -outline $p
        update idletasks
        set press_after($key) [after $L(press_ms) [list ::plugins::GrindAdvisor::_tap_restore $page $tag]]
        uplevel #0 $cmd
    }

    proc _tap_restore {page tag} {
        variable press_after
        unset -nocomplain press_after($page,$tag)
        _paint_btn $page $tag
    }

    proc _init_layout {} {
        variable L
        array unset L
        array set L {}

        # Virtual base resolution: fixed constants, not detected.
        set sw 2560
        set sh 1600
        set scale [expr {double($sh) / 800.0}]

        # v3.23.0 (F8): font pixel sizes follow the canvas height the core
        # rescales coordinates to (dui cget screen_size_height: 800 on the
        # tablet, dui.tcl maps its 1340x736 screen to 800) -- one scale source
        # for fonts and coordinates. Never `winfo screenheight` (736 there:
        # every page font drew at 92%). No dui (offline) or no number: 800.
        set ch 800
        if {[llength [info commands ::dui::cget]]} {
            set v [::dui::cget screen_size_height]
            if {[string is double -strict $v] && $v > 1} { set ch $v }
        }
        set font_scale [expr {double($ch) / 800.0}]

        set L(screen_w) $sw
        set L(screen_h) $sh
        set L(scale) $scale
        set L(font_scale) $font_scale

        # Spacing tokens (reference px at 1340x800, scaled).
        foreach {tok ref} {xs 6 sm 10 md 16 lg 24 xl 32 xxl 48} {
            set L($tok) [expr {int(round($ref * $scale))}]
        }

        set L(margin) [expr {int(max($sw * 0.036, 32))}]
        set L(left_x) $L(margin)
        set L(right_x) [expr {$sw - $L(margin)}]
        set L(content_w) [expr {$L(right_x) - $L(left_x)}]
        set L(center_x) [expr {($L(left_x) + $L(right_x)) / 2}]
        set L(label_col_w) [expr {int(round(420 * $scale))}]
        set L(value_x) [expr {$L(left_x) + $L(label_col_w) + $L(lg)}]

        set L(card_w) $L(content_w)
        set L(card_h) [expr {int(round(96 * $scale))}]
        set L(card_gap) [expr {int(round(12 * $scale))}]
        set L(card_pad_x) [expr {int(round(18 * $scale))}]
        set L(card_line1_dy) [expr {int(round(30 * $scale))}]
        set L(card_line2_dy) [expr {int(round(56 * $scale))}]
        set L(card_line3_dy) [expr {int(round(80 * $scale))}]

        # v2.0.1 section cards (stock App-tab pattern: white rounded blocks
        # with a section title, grouped controls, on the grey page bg).
        set L(sec_top) [expr {int(round(104 * $scale))}]   ;# cards start here (no toolbar row on card pages)
        set L(sec_gutter) $L(lg)
        set L(sec_col_w) [expr {($L(content_w) - $L(sec_gutter)) / 2}]
        set L(sec_col2_x) [expr {$L(left_x) + $L(sec_col_w) + $L(sec_gutter)}]
        set L(sec_pad) $L(lg)
        set L(sec_gap) $L(lg)
        set L(sec_title_h) [expr {int(round(24 * $scale))}]
        set L(sec_label_w) [expr {int(round(200 * $scale))}]
        set L(sec_value_dx) [expr {$L(sec_pad) + $L(sec_label_w) + $L(lg)}]
        set L(sec_btn_w) [expr {int(round(140 * $scale))}]
        # v3.17.0 (F5): numeric settings are [-] value [+] steppers
        # (MaintenanceTracker's threshold stepper with one step size; the
        # half-width cards have no room for a second). 60 px buttons (67 px
        # wide on the tablet), a value plate that fits "10000" at primary
        # size, sm gaps. Rows use row_pitch (btn_h + md) like every other
        # button row; the 48 px entry rows are gone.
        set L(step_btn_w) [expr {int(round(64 * $scale))}]
        set L(step_val_w) [expr {int(round(120 * $scale))}]
        set L(step_w) [expr {2 * $L(step_btn_w) + $L(step_val_w) + 2 * $L(sm)}]
        # v3.17.1 (F19): History Display Options -- three equal cards in one
        # row, and the glyph column each toggle row keeps clear of its label.
        set L(hopt_card_w) [expr {($L(content_w) - 2 * $L(sec_gutter)) / 3}]
        set L(tog_w) [expr {int(round(40 * $scale))}]
        # v3.12.0: all colors live in _apply_palette (light / dark per
        # settings(theme)) so the sun/moon toggle can swap them at
        # runtime. The popup keeps its own independent popup_theme.
        _apply_palette

        # v2.1.0 calibration-accuracy gauge: 10-segment bar, one accent for
        # filled segments and one neutral for empty (no rainbow), plus the
        # band thresholds (upper bound of each band).
        set L(conf_segments) 10
        set L(conf_seg_w) [expr {int(round(15 * $scale))}]
        set L(conf_seg_gap) [expr {int(round(3 * $scale))}]
        set L(conf_seg_h) [expr {int(round(20 * $scale))}]
        set L(conf_seg_r) [expr {int(round(4 * $scale))}]
        # conf_fill / conf_empty come from _apply_palette (above).
        set L(conf_poor_max) 39
        set L(conf_fair_max) 64
        set L(conf_good_max) 84
        # v3.24.0 (F24): one caption line (16 px) for the next step under
        # the Confidence row; the Recommendation card grows by this much.
        set L(conf_step_h) [expr {int(round(20 * $scale))}]

        set L(btn_w_std) [expr {int(round(200 * $scale))}]
        set L(btn_w_wide) [expr {int(round(240 * $scale))}]
        set L(btn_h) [expr {int(max(60, round(60 * $scale)))}]
        set L(btn_radius) [expr {int(round(12 * $scale))}]
        set L(card_radius) $L(btn_radius)

        # v3.6.1: self-contained colors (BeanScanner v0.1.2 / SHE v0.5.4
        # pattern). The plugin paints its own page background and its button
        # style carries explicit fills, so nothing depends on which dui
        # theme is current at load time (Lumen's DYE integration switches
        # the current theme to DYE_Lumen mid-load; this plugin escaped the
        # resulting invisible-button bug only by loading before the switch).
        # page_bg / btn_fill / btn_disabled_fill come from _apply_palette,
        # and so does btn_label_fill since v3.16.7 (per theme; this block
        # used to force white in both themes).
        set L(sec_radius) $L(card_radius)

        set L(header_title_y) [expr {int(round(28 * $scale))}]
        set L(header_subtitle_y) [expr {int(round(72 * $scale))}]
        set L(header_y1) [expr {int(round(96 * $scale))}]
        set L(toolbar_y0) [expr {int(round(104 * $scale))}]
        set L(toolbar_y1) [expr {int(round(152 * $scale))}]
        set L(list_top) [expr {int(round(168 * $scale))}]
        set L(row_h) $L(btn_h)
        set L(row_gap) $L(md)
        set L(row_pitch) [expr {$L(row_h) + $L(row_gap)}]
        set L(bar_y0) [expr {int(round(716 * $scale))}]
        set L(bar_y1) [expr {int(round(776 * $scale))}]

        # Pixel-exact fonts (negative Tk size = pixels), floored at 16px.
        # Fallbacks to named Helv_* fonts first so every key is valid even
        # if the "font" command is unavailable.
        set L(font_title) Helv_20_bold
        set L(font_section) Helv_18_bold
        set L(font_primary) Helv_10_bold
        set L(font_body) Helv_9
        set L(font_caption) Helv_8
        set L(font_button) Helv_10_bold
        catch {
            foreach {name ref bold} {title 40 1 section 24 1 primary 22 1 body 19 0 caption 16 0 button 20 1} {
                set px [expr {int(max(16, round($ref * $font_scale)))}]
                set fname "GA_$name"
                set weight normal
                if {$bold} { set weight bold }
                if {[lsearch -exact [font names] $fname] >= 0} {
                    font configure $fname -size [expr {-$px}] -weight $weight
                } else {
                    font create $fname -family Helvetica -size [expr {-$px}] -weight $weight
                }
                set L(font_$name) $fname
            }
        }

        # v3.12.0: icon font for the theme toggle's sun/moon face (the
        # app's own FA6 Pro file; text fallback when unavailable).
        set L(have_icons) 0
        set L(font_icon) $L(font_button)
        catch {
            set fam [dui::font::add_or_get_familyname "Font Awesome 6 Pro-Regular-400.otf"]
            if {$fam ne ""} {
                set px [expr {int(max(16, round(26 * $font_scale)))}]
                if {[lsearch -exact [font names] GA_icon] >= 0} {
                    font configure GA_icon -family $fam -size [expr {-$px}]
                } else {
                    font create GA_icon -family $fam -size [expr {-$px}]
                }
                set L(font_icon) GA_icon
                set L(have_icons) 1
            }
        }

        # Shared button aspect style: same corner radius everywhere. Label
        # fonts are passed per-instance via -label_font (the aspect
        # font_size key is not honored on the tablet -- SHE v0.3.3 lesson).
        #
        # -theme default is REQUIRED (BeanScanner v0.1.2 lesson): without
        # it, "dui aspect set" writes into whatever theme is current, and
        # any load-order change (e.g. Lumen's `dui theme set DYE_Lumen` at
        # skin.tcl:1831 running first) would leave these -theme default
        # pages unable to find the style -- buttons then render with no
        # shape at all, as happened to ShotHistoryEditor v0.5.3.
        #
        # v3.16.7: the label fill is the palette's btn_label_fill, so a
        # restart in either theme creates readable labels; the live toggle
        # recolors them in _retheme_all.
        catch {
            dui aspect set -theme default -type dbutton -style ga_btn [list \
                shape round radius $L(btn_radius) \
                fill $L(btn_fill) disabledfill $L(btn_disabled_fill)]
            dui aspect set -theme default -type dbutton_label -style ga_btn [list \
                fill $L(btn_label_fill) disabledfill "#999999"]
            # v3.22.0 (F10): the primary role. No pressfill on any GA style:
            # the core flash restores the creation fill and recolours
            # same-named buttons in other plugins; _tap does it instead.
            dui aspect set -theme default -type dbutton -style ga_btn_primary [list \
                shape round radius $L(btn_radius) \
                fill $L(btn_primary_fill) disabledfill $L(btn_disabled_fill)]
            dui aspect set -theme default -type dbutton_label -style ga_btn_primary [list \
                fill $L(btn_primary_label) disabledfill "#999999"]
        }
    }

    # Full-page background, drawn as the first item of every page so the
    # plugin's contrast never depends on the active skin theme (fpdialog
    # pages otherwise show whatever page or canvas lies beneath them --
    # near-black under Lumen's dark mode). Copied verbatim from
    # BeanScanner's proven _page_bg (also SHE v0.5.4).
    proc _page_bg {page} {
        variable L
        dui add canvas_item rect $page 0 0 $L(screen_w) $L(screen_h) \
            -fill $L(page_bg) -outline $L(page_bg) -tags page_bg
    }

    # Rounded-rectangle backdrop via the dui canvas_item wrapper (smoothed
    # polygon -- copied verbatim from ShotHistoryEditor's proven helper; no
    # rounded-rect primitive exists in the core).
    proc rounded_rect {page x1 y1 x2 y2 radius args} {
        set r $radius
        if {$r * 2 > ($x2 - $x1)} { set r [expr {($x2 - $x1) / 2}] }
        if {$r * 2 > ($y2 - $y1)} { set r [expr {($y2 - $y1) / 2}] }
        set pts [list \
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
        return [uplevel #0 [list dui add canvas_item polygon $page {*}$pts -smooth 1 {*}$args]]
    }

    # v2.0.1 section card: white rounded block with a section title, stock
    # App-tab style. Returns the y where the first content row starts.
    # Height must be precomputed by the caller (content-driven):
    #   h = sec_pad + sec_title_h + md + <content height> + sec_pad
    proc _sec_card {page tag x y w h title} {
        variable L
        rounded_rect $page $x $y [expr {$x + $w}] [expr {$y + $h}] $L(sec_radius) \
            -fill $L(sec_fill) -outline $L(sec_outline) -width 2 -tags ${tag}_bg
        dui add dtext $page [expr {$x + $L(sec_pad)}] [expr {$y + $L(sec_pad) + $L(sec_title_h) / 2}] \
            -tags ${tag}_title -text [translate $title] -font $L(font_section) \
            -width [expr {$w - 2 * $L(sec_pad)}] -fill $L(text_hi) -anchor w -justify left
        return [expr {$y + $L(sec_pad) + $L(sec_title_h) + $L(md)}]
    }

    proc preload_settings_page {} {
        package require de1_dui 1.0
        catch { plugins load_settings GrindAdvisor }
        # v3.24.0 (design review F26, CLAUDE.md "No save_settings in
        # preload"): the defaults live in memory only; the first real change
        # (a toggle, a page's Done / Back) saves the whole array, every
        # default with it. load_settings' result is never read (always 0).
        apply_defaults
        _init_layout
        dui page add GrindAdvisor_settings -namespace true -theme default -type fpdialog
        dui page add GrindAdvisor_history_options -namespace true -theme default -type fpdialog
        dui page add GrindAdvisor_advanced -namespace true -theme default -type fpdialog
        dui page add GrindAdvisor_help -namespace true -theme default -type fpdialog
        dui page add GrindAdvisor_diagnostics -namespace true -theme default -type fpdialog
        dui page add GrindAdvisor_calculation_details -namespace true -theme default -type fpdialog
        dui page add GrindAdvisor_dose_yield -namespace true -theme default -type fpdialog
        # v3.12.0: a retheme pass for a dark restart. v3.16.7: it reaches
        # nothing -- plugins load before `dui setup_ui` creates the page
        # items (gui.tcl) -- so every item takes its palette colour at
        # creation (v3.17.1: the History Display Options glyphs too); this
        # call stays, harmless.
        variable settings
        if {[info exists settings(theme)] && $settings(theme) eq "dark"} {
            catch { _retheme_all }
        }
        return GrindAdvisor_settings
    }

    proc save_settings {} {
        catch { plugins save_settings GrindAdvisor }
    }

    proc show_last_recommendation {} {
        variable last_recommendation
        if {$last_recommendation eq ""} { load_last_recommendation }
        if {$last_recommendation eq ""} {
            set est {}
            catch { set est [starting_estimate] }
            if {$est ne ""} {
                present_result [dict create ok 0 error \
                    "[dict get $est label]\n\n[new_bag_note].\n\n[dict get $est reason]."]
            } else {
                present_result [dict create ok 0 error "No saved Grind Advisor recommendation yet."]
            }
            return
        }
        # v3.7.0: the saved recommendation is about a specific bag and
        # profile. If the user has switched since, presenting that number
        # would be actively misleading -- it is a calibration for a different
        # coffee. Say so instead of showing it.
        #
        # v3.13.0: when the loaded bag also has NO shots of its own, a
        # display-only starting estimate is shown above the new-bag note
        # (see starting_estimate). This reverses the owner decision of
        # 2026-08-15 ("reset only, never seed a guessed grind for a new
        # bag") -- reversed by the owner in the v3.13.0 pass spec. The
        # v3.7.0 reset itself stays, the estimate is never labeled
        # "Recommended", and it feeds no math. present_result never saves
        # ok-0 dicts (save_last_recommendation guards on ok), so the
        # estimate cannot overwrite the saved recommendation either.
        if {![last_recommendation_is_current]} {
            set was ""
            if {[dict exists $last_recommendation bag_label]} {
                set was [string trim [dict get $last_recommendation bag_label]]
            }
            set detail "The saved recommendation is for a different bag or profile."
            if {$was ne ""} { set detail "The saved recommendation is for $was." }
            set est {}
            catch { set est [starting_estimate] }
            if {$est ne ""} {
                present_result [dict create ok 0 error \
                    "[dict get $est label]\n\n[new_bag_note].\n\n[dict get $est reason].\n$detail"]
            } else {
                present_result [dict create ok 0 error \
                    "[new_bag_note].\n\n$detail"]
            }
            return
        }
        present_result $last_recommendation
    }

    # Public entry point: open the Calibration Curve directly, without going
    # through the after-shot popup first. Skins that put a Curve control on
    # their own grind tile call this (Lumen v0.17.0) rather than reaching into
    # the overlay internals.
    #
    # Same source ladder as show_last_recommendation -- in-memory rec, then the
    # saved one, then a fresh read-only analysis -- and _curve_rec fills in the
    # bag's shots from SDB either way. _last_rec_shown is seeded so the curve's
    # Back button lands on the normal popup.
    proc show_calibration_curve {} {
        variable last_recommendation
        variable _last_rec_shown
        variable popup_active

        if {$last_recommendation eq ""} { load_last_recommendation }
        set rec $last_recommendation
        if {$rec eq "" || ![dict exists $rec ok] || ![dict get $rec ok]} {
            set rec [analyze_latest_shot]
        }
        if {![dict exists $rec ok] || ![dict get $rec ok]} {
            # Nothing to plot: show the normal error card rather than an empty
            # pair of axes.
            present_result $rec
            return
        }

        set _last_rec_shown $rec
        set popup_active 1
        if {[_show_curve_dialog $rec]} { return }
        set popup_active 0
        catch { msg "GrindAdvisor: could not open the calibration curve" }
        catch { borg toast "Grind Advisor: could not open the calibration curve" }
    }

    proc show_latest_recommendation {} {
        variable last_shown_id
        variable last_recommendation
        set rec [analyze_latest_shot]
        if {[dict exists $rec ok] && [dict get $rec ok]} {
            # Record the shown id so the next automatic trigger (e.g. a rinse
            # state change) cannot re-pop this same shot.
            if {[dict exists $rec id]} { set last_shown_id [dict get $rec id] }
            present_result $rec
            return
        }
        if {$last_recommendation eq ""} { load_last_recommendation }
        if {$last_recommendation ne ""} {
            if {[dict exists $last_recommendation id]} {
                set last_shown_id [dict get $last_recommendation id]
            }
            present_result $last_recommendation
            return
        }
        present_result $rec
    }

    proc test_latest_shot {} {
        variable last_shown_id
        set rec [analyze_latest_shot]
        if {[dict exists $rec ok] && [dict get $rec ok] && [dict exists $rec id]} {
            set last_shown_id [dict get $rec id]
        }
        present_result $rec
    }

    proc open_settings_dialog {page} {
        foreach cmd [list \
            [list dui page open_dialog $page] \
            [list dui page load $page] \
            [list dui page show $page]] {
            if {![catch { uplevel #0 $cmd }]} { return 1 }
        }
        catch { msg "GrindAdvisor: could not open settings page $page" }
        return 0
    }

    proc _last_recommendation_file {} {
        variable plugin_dir
        if {[info exists plugin_dir] && $plugin_dir ne ""} {
            return [file join $plugin_dir last_recommendation.tdb]
        }
        return [file join [plugin_directory] GrindAdvisor last_recommendation.tdb]
    }

    proc save_last_recommendation {rec} {
        variable last_recommendation
        if {![dict exists $rec ok] || ![dict get $rec ok]} { return }
        set last_recommendation $rec
        # A new shot exists, so every cached per-bag recommendation is now
        # potentially out of date -- including the one for THIS bag, which
        # this shot has just changed. Dropping the whole cache here is the
        # single invalidation point (v3.8.0); the next lookup recomputes.
        invalidate_bag_rec_cache
        set fn [_last_recommendation_file]
        if {[catch {
            set f [open $fn w]
            puts $f $rec
            close $f
        } err]} {
            catch { close $f }
            catch { msg "GrindAdvisor: could not save last recommendation: $err" }
        }
    }

    proc load_last_recommendation {} {
        variable last_recommendation
        variable last_shown_id
        set fn [_last_recommendation_file]
        if {![file exists $fn]} { return }
        if {[catch {
            set f [open $fn r]
            set raw [string trim [read $f]]
            close $f
            if {$raw ne "" && ![catch { dict size $raw }]} {
                set last_recommendation $raw
                # Seed dedup at startup so a restart followed by any state
                # change (e.g. a rinse) cannot re-pop an old recommendation.
                if {$last_shown_id eq "" && [dict exists $raw id]} {
                    set last_shown_id [dict get $raw id]
                }
                # v3.19.1: a rec saved before 3.19.0 has no `plain`; word it
                # once here, so a skin tile (Lumen reads plain.short) shows
                # the plain words before the next shot rewrites the file.
                if {[dict exists $raw ok] && [dict get $raw ok] eq "1" \
                        && ![dict exists $raw plain] && [dict exists $raw grind] \
                        && [dict exists $raw next] && [dict exists $raw actual] \
                        && [dict exists $raw target]} {
                    dict set last_recommendation plain [_plain_words $raw]
                }
            }
        } err]} {
            catch { close $f }
            catch { msg "GrindAdvisor: could not load last recommendation: $err" }
        }
    }

    # ==================================================================
    #  Event wiring
    # ==================================================================

    # v3.16.3: when visualizer_upload is enabled, SDB does not insert the shot
    # in its own after_flow_complete listener; it inserts on the LEAVE of the
    # upload proc (SDB.tcl: trace add execution
    # ::plugins::visualizer_upload::uploadShotData leave ...). The upload is a
    # synchronous http::geturl that services the event loop, so a slow or
    # failing upload (retries, up to ~27 s) outlasts after_flow_complete (+5 s)
    # plus popup_delay_ms: run then saw the PREVIOUS id, returned without
    # marking, and the espresso popup surfaced after the next flush / steam /
    # rinse event. Hooking the same leave re-schedules run once the row exists.
    # The handler only schedules an `after`, so it never depends on the order
    # of the two leave traces: SDB's synchronous insert is done before the
    # timer can fire.
    proc _install_upload_trace {} {
        variable upload_traced
        if {$upload_traced} { return 1 }
        set p ::plugins::visualizer_upload::uploadShotData
        if {![llength [info procs $p]]} { return 0 }
        if {[catch { trace add execution $p leave ::plugins::GrindAdvisor::_upload_trace } err]} {
            msg -ERROR "GrindAdvisor: could not trace $p: $err"
            return 0
        }
        set upload_traced 1
        msg "GrindAdvisor: also hooked via leave trace on $p"
        return 1
    }

    proc _upload_trace {args} {
        # "any": the popup still needs a NEW valid espresso id, exactly like the
        # event path; no new error-popup behaviour is introduced.
        _schedule_run any
    }

    proc register_shot_complete_hook {} {
        variable hooked
        _install_nav_watch
        _install_upload_trace
        if {$hooked} { return }
        set done 0

        # Preferred: DE1app event system, if present in this version.
        foreach adder {
            ::de1::event::listener::after_flow_complete_add
            ::de1::event::listener::on_major_state_change_add
        } {
            if {[llength [info commands $adder]]} {
                if {![catch { $adder ::plugins::GrindAdvisor::_event_dispatch }]} {
                    set done 1
                    catch { msg "GrindAdvisor: hooked via $adder" }
                    break
                }
            }
        }

        # Fallback: trace the long-standing shot-save proc. This fires exactly
        # when an espresso shot is written to history, which is ideal.
        if {!$done} {
            foreach p {::save_this_espresso_shot save_this_espresso_shot} {
                if {[llength [info procs $p]]} {
                    if {![catch { trace add execution $p leave ::plugins::GrindAdvisor::_save_trace }]} {
                        set done 1
                        catch { msg "GrindAdvisor: hooked via trace on $p" }
                        break
                    }
                }
            }
        }

        # Last resort: watch the machine state variable.
        if {!$done} {
            if {[_install_state_trace]} {
                set done 1
                catch { msg "GrindAdvisor: hooked via state-variable trace" }
            }
        }

        if {!$done} {
            catch { msg "GrindAdvisor: WARNING - could not find a shot-complete hook. Use ::plugins::GrindAdvisor::test to trigger manually." }
        }
        set hooked $done
        return
    }

    proc _save_trace {args} {
        _schedule_run espresso
    }

    proc _event_dispatch {args} {
        # The successful path only pops when the latest espresso shot id is
        # new, so passing "any" here is safe even for steam/water/flush
        # events (those produce no new espresso row -> no popup).
        _schedule_run any
    }

    proc _install_state_trace {} {
        set ok 0
        foreach v {::de1(state) ::de1_num_state ::de1(substate)} {
            if {[info exists $v]} {
                if {![catch { trace add variable $v write ::plugins::GrindAdvisor::_state_trace }]} {
                    set ok 1
                }
            }
        }
        return $ok
    }

    proc _state_trace {args} {
        variable _last_state_run
        set now [clock milliseconds]
        if {($now - $_last_state_run) < 4000} { return }
        set _last_state_run $now
        _schedule_run any
    }

    proc _schedule_run {context} {
        variable _pending_after
        if {$_pending_after ne ""} { catch { after cancel $_pending_after } }
        # v3.17.0 (F5): through _num_value -- a blank or typed "1.5s" delay
        # used to make `after` throw here, and the popup silently stopped.
        set delay [expr {int([_num_value popup_delay_ms])}]
        set _pending_after [after $delay [list ::plugins::GrindAdvisor::run $context]]
    }

    # ------------------------------------------------------------------
    #  Popup guards + navigation watch (v1.8.2)
    #
    #  The automatic popup may only open when (a) no Grind Advisor popup is
    #  already showing, (b) the machine is not running any flow, and (c) the
    #  user is not sitting on a settings page. Machine-state and page-change
    #  watchers reset the guard flag so it can never stay stuck.
    # ------------------------------------------------------------------

    proc _overlay_exists {} {
        if {[winfo exists .grindadvisor_overlay]} { return 1 }
        if {[winfo exists .grindadvisor]} { return 1 }
        set sc [_get_canvas]
        if {$sc ne ""} {
            set parent [winfo parent $sc]
            if {$parent ne "." && [winfo exists "$parent.grindadvisor_overlay"]} { return 1 }
        }
        return 0
    }

    # Re-entry guard: true only while a popup is really on screen. A set flag
    # without a live overlay self-heals to 0 so it can never block the UI.
    proc _popup_blocked {} {
        variable popup_active
        if {!$popup_active} { return 0 }
        if {[_overlay_exists]} { return 1 }
        set popup_active 0
        return 0
    }

    # True while the machine runs any flow (espresso, steam, water, rinse,
    # clean, descale) or waits for a refill (v3.16.5: the core loads its
    # tank-empty page on Refill, gui.tcl:63; the popup must not stay over
    # it). Read defensively: state may be a number that maps to a name via
    # ::de1_num_state, or already a name.
    proc _flow_active {} {
        set name ""
        catch {
            if {[info exists ::de1(state)]} {
                set s $::de1(state)
                if {[info exists ::de1_num_state($s)]} {
                    set name $::de1_num_state($s)
                } else {
                    set name $s
                }
            }
        }
        if {$name eq ""} { return 0 }
        return [regexp -nocase {espresso|steam|water|rinse|clean|descale|purge|refill} $name]
    }

    # v3.16.5: the app's tank-empty pages (core "tankempty"; Lumen also
    # declares "refill").
    proc _on_refill_page {} {
        set ctx ""
        catch { set ctx $::de1(current_context) }
        if {$ctx eq ""} { catch { set ctx [dui page current] } }
        return [expr {$ctx in {tankempty refill}}]
    }

    proc _on_settings_page {} {
        set ctx ""
        catch { set ctx $::de1(current_context) }
        if {$ctx eq ""} { catch { set ctx [dui page current] } }
        if {$ctx eq ""} { return 0 }
        return [regexp -nocase {settings|config|preference|extension|plugin|grindadvisor} $ctx]
    }

    proc _install_nav_watch {} {
        variable nav_watched
        if {$nav_watched} { return }
        set nav_watched 1
        catch { trace add variable ::de1(state) write ::plugins::GrindAdvisor::_nav_state_change }
        foreach p {::page_display_change page_display_change} {
            if {[llength [info procs $p]]} {
                catch { trace add execution $p leave ::plugins::GrindAdvisor::_nav_page_change }
                break
            }
        }
    }

    proc _nav_state_change {args} {
        variable popup_active
        variable _pending_after
        if {[_flow_active]} {
            # A flow just started (e.g. rinse from the GHC): drop any pending
            # auto-popup and never leave an open popup raised over the flow
            # screen.
            if {$_pending_after ne ""} {
                catch { after cancel $_pending_after }
                set _pending_after ""
            }
            if {[_overlay_exists]} { _close_dialog }
        }
        if {$popup_active && ![_overlay_exists]} { set popup_active 0 }
    }

    proc _nav_page_change {args} {
        variable popup_active
        # v3.16.5: a popup still up when the tank-empty page loads (it
        # opened before the state trace could see Refill, or by hand) is
        # closed -- it would sit over the page and hold the grab.
        if {[_overlay_exists] && [_on_refill_page]} { _close_dialog }
        # Any page navigation resets a stuck guard flag so it can never
        # permanently block the popup or buttons.
        if {$popup_active && ![_overlay_exists]} { set popup_active 0 }
    }

    # ------------------------------------------------------------------
    #  Done/Back navigation (v1.8.8 -- root cause confirmed from de1app-core)
    #
    #  Root cause (de1app-core/dui.tcl, proc ::dui::page::load, the "Handle
    #  page stack" block around line 6462): when a "default"-type page loads
    #  (e.g. the flow-monitor screen shown while a flush/rinse/steam runs),
    #  the framework unconditionally resets page_stack to a single entry:
    #  "set page_stack [dict create $page_to_show {}]". This happens even
    #  while a fpdialog (GrindAdvisor_settings) is the current page, because
    #  the "only one dialog visible" guard a few lines above only checks
    #  page type "dialog", not "fpdialog" (dui.tcl ~line 6415). When the app
    #  re-shows GrindAdvisor_settings after the flow ends, it gets pushed
    #  onto that freshly-wiped stack, so page_stack becomes
    #  {<flow_page>: {}, GrindAdvisor_settings: <cb>}. dui::page::close_dialog
    #  (dui.tcl ~line 6780) navigates to "previous", which is defined as the
    #  second-to-last key of page_stack (dui.tcl proc ::dui::page::previous,
    #  ~line 5964) -- i.e. the flow page. That is exactly why Done lands on
    #  the flush screen: it is not a GrindAdvisor bug, it is how this DE1app
    #  build's page_stack always behaves for any fpdialog left open across a
    #  state-driven page change, and it does not self-heal.
    #
    #  Graphical_Flow_Calibrator survives the same interruption because its
    #  "GFC" page is plain (type "default", never fpdialog) and its Exit
    #  never consults page_stack/close_dialog at all: it renames the global
    #  ::page_show and captures [dui page current] into ::gfc_start_page only
    #  when the wrapped call is genuinely "page_show GFC", then Exit calls
    #  "dui page load $::gfc_start_page" directly (plugins/Graphical_Flow_
    #  Calibrator/plugin.tcl, proc exit and the "rename ::page_show" block).
    #
    #  Fix: do the same thing GFC does, adapted to fpdialog pages. Every
    #  GrindAdvisor page's show{} callback (called by dui::page::load itself,
    #  dui.tcl ~line 6704, on every single page-show, genuine or not) records
    #  its real page_to_hide as the return target -- but skips the update
    #  whenever page_to_hide looks like a machine-state flow page, so a
    #  flush/rinse/steam interruption can never overwrite the last real
    #  target. Done then uses that captured, dui-page-exists-verified target
    #  via "dui page load" (confirmed in dui.tcl: open_dialog is literally
    #  "dui page load $page {*}$args", so this is not a different mechanism
    #  from opening the dialog, just re-using it) instead of trusting
    #  page_stack's "previous". "dui page close_dialog" remains the fallback
    #  whenever nothing valid was captured, matching the reference plugins'
    #  normal-case behavior exactly.
    # ------------------------------------------------------------------
    variable _settings_return_page ""

    # Matches machine-state flow/monitor pages by name (real state names
    # confirmed in de1app-core/machine.tcl: Espresso, Steam, HotWater,
    # HotWaterRinse, SteamRinse, Descale, Clean, AirPurge, ...). Used only to
    # reject capturing a bad return target -- never to construct/guess one.
    proc _is_transient_name {name} {
        if {$name eq ""} { return 1 }
        return [regexp -nocase {espresso|steam|water|rinse|flush|clean|cleaning|descale|purge} $name]
    }

    # Called from the settings page's show{page_to_hide page_to_show}.
    # page_to_hide is the real previous page per dui::page::load -- captured
    # unconditionally except when it looks like a flow/monitor page (so a
    # flush/rinse/steam interruption's re-show can never clobber the last
    # legitimate target) or when it is one of this plugin's OWN pages
    # (v2.0.2 fix: returning from a sub-page, e.g. Advanced -> Done,
    # re-shows settings with page_to_hide = that sub-page; capturing it made
    # the next Done ping-pong back to the sub-page instead of leaving to the
    # genuine entry page captured when the user first opened the plugin).
    proc _capture_return_page {page_to_hide} {
        variable _settings_return_page
        if {$page_to_hide eq ""} { return }
        if {[string match "GrindAdvisor_*" $page_to_hide]} { return }
        if {![_is_transient_name $page_to_hide]} {
            set _settings_return_page $page_to_hide
        }
    }

    # Navigates to $target via "dui page load" (equivalent to open_dialog,
    # per dui.tcl) only if it is a real, currently-registered page; otherwise
    # falls back to "dui page close_dialog" (the reference-plugin mechanism,
    # correct whenever page_stack has not been corrupted by an interruption).
    # Errors are logged, never swallowed by a bare catch.
    proc _navigate_done {target} {
        set ok 0
        if {$target ne "" && ![_is_transient_name $target]} {
            catch { set ok [dui page exists $target] }
        }
        if {$ok} {
            if {[catch { uplevel #0 [list dui page load $target] } err]} {
                catch { msg "GrindAdvisor: ERROR navigating to $target: $err" }
                catch { dui page close_dialog }
            }
        } else {
            catch { dui page close_dialog }
        }
    }

    proc _exit_settings {} {
        variable _settings_return_page
        _navigate_done $_settings_return_page
    }

    # Advanced goes Back to the main settings page -- a real page this
    # plugin itself registers, one level up, not a guess.
    proc _exit_subpage {} {
        _navigate_done GrindAdvisor_settings
    }

    # v3.17.2 (F13): every Tools page (Dose / Yield Source, History Display
    # Options, Diagnostics, Calculation Details, Help) goes Back ONE level,
    # to Advanced, the page that opened it. Its Done used to jump to the main
    # page, two levels up in a single `dui page load`; the core removes only
    # one stacked level per load (page_stack truncation, dui.tcl ~6470), so
    # the stack kept Advanced and the tool page, and a later close_dialog
    # fell back into Advanced instead of leaving. A plain, logged load of the
    # known parent, as the core's own pages return.
    proc _back_to_advanced {} {
        if {[catch { dui page load GrindAdvisor_advanced } err]} {
            catch { msg -ERROR "GrindAdvisor: Back to Advanced failed: $err" }
            if {[catch { dui page close_dialog } err2]} {
                catch { msg -ERROR "GrindAdvisor: close_dialog fallback failed: $err2" }
            }
        }
    }

    # v3.17.4 (F22): show hooks run after idle, so one queued for a page the
    # user has already left must not repaint it. Copied verbatim from
    # MaintenanceTracker (_page_is_current, MaintenanceTracker.tcl ~2105).
    proc _page_is_current {page} {
        set cur ""
        catch { set cur [dui page current] }
        return [expr {$cur eq $page}]
    }

    # v3.17.4 (F22): a page's load hook. dui page load runs it synchronously
    # BEFORE the page appears (dui.tcl ~6448); show runs after idle, when the
    # last visit's content is already on screen. So the refresh goes here.
    # Rules (dui.tcl ~6449-6458, 6618): skip until the page is set up (a
    # late-enabled plugin loads before its setup); never let an error escape
    # (open_settings_dialog's cascade would fall back to `dui page show`,
    # which skips load, and hide the error); ALWAYS return 1 -- a refresh
    # body ending in a caught catch returns 0, and 0 cancels the open. The
    # page's items are hidden during load: no -state here (enable_or_disable
    # skips hidden items; show re-applies state).
    proc _page_load {what page script} {
        if {![dui page is_setup $page]} { return 1 }
        if {[catch { uplevel 1 $script } err]} {
            catch { msg -ERROR "GrindAdvisor: $what load refresh failed: $err" }
        }
        return 1
    }

    # v3.17.4 (F22): an SDB-backed page's text, parked before the page
    # appears (owner 2026-10-01: placeholder, then fill); its show reads SDB
    # and replaces it a moment later.
    proc _reading_placeholder {page tag} {
        catch { dui item config $page $tag -text "[translate {Reading the shot database}][_char ellipsis]" }
        catch { dui item config $page pg_ind -text "" }
        # Nothing to page through yet: both ends greyed on the first frame.
        _pager_initial $page 0 1
    }

    # ==================================================================
    #  Top-level run
    # ==================================================================

    proc run {{context any}} {
        variable last_shown_id
        variable last_error_text
        variable last_error_time
        variable _pending_after
        set _pending_after ""

        # Automatic-popup gates (v1.8.2). Manual buttons call present_result
        # directly and are not affected.
        if {[_popup_blocked]} { return }
        if {[_flow_active]} { return }

        set rec [analyze_latest_shot]

        if {![dict get $rec ok]} {
            set etext [dict get $rec error]
            set now [clock seconds]
            # Don't spam the same error; and only surface errors when we were
            # actually expecting a shot (an espresso just saved).
            if {$etext eq $last_error_text && ($now - $last_error_time) < 30} { return }
            set last_error_text $etext
            set last_error_time $now
            if {$context eq "espresso"} { present_result $rec }
            return
        }

        set id [dict get $rec id]
        if {$id eq $last_shown_id} { return }
        set last_shown_id $id
        if {![_setting enable_popup 1]} {
            save_last_recommendation $rec
            return
        }
        # While the user is on a settings page, record the recommendation
        # silently instead of popping over the page; the manual
        # "Show Latest Recommendation" button can display it.
        if {[_on_settings_page]} {
            save_last_recommendation $rec
            return
        }
        present_result $rec
        return
    }

    # Manual trigger for testing from the Tcl console:
    #   ::plugins::GrindAdvisor::test
    proc test {} {
        test_latest_shot
    }

    # ==================================================================
    #  Analysis  (READ-ONLY)
    # ==================================================================

    # ------------------------------------------------------------------
    #  Real-espresso-shot validation gate (v1.8.2)
    #
    #  SDB stores rinse/flush/hot-water/steam flows in the same shot table,
    #  so every consumer filters rows through this gate. Checks are
    #  defensive: each field is only tested when the schema exposes it.
    # ------------------------------------------------------------------
    variable _reject_re {\m(rinse|flush|backflush|clean|cleaning|descale|hot\s*water|water|steam|skip|dummy|calibrat\w*)\M}

    proc _text_is_nonespresso {text} {
        variable _reject_re
        set t [string tolower [string trim $text]]
        if {$t eq ""} { return 0 }
        return [regexp -nocase -- $_reject_re $t]
    }

    # Beverage-type whitelist (v3.16.4). The keyword reject above only knows
    # the names of non-espresso runs; the core's other beverage types
    # (pourover, tea, tea_portafilter, manual, ...) carry none of them, so a
    # "Pour Over 15g" or tea row with grind/dose/yield passed as espresso.
    # A SET beverage type must be espresso. A blank one is still accepted:
    # older untagged shots are real espresso (DYE keeps them the same way,
    # COALESCE(beverage_type,'')).
    proc _bev_type_is_espresso {text} {
        set t [string tolower [string trim $text]]
        if {$t eq ""} { return 1 }
        return [expr {$t eq "espresso"}]
    }

    # ------------------------------------------------------------------
    #  Deleted-shot tolerance (v2.1.1)
    #
    #  Deleting a shot (e.g. ShotHistoryEditor's soft delete) removes the
    #  history file but never touches SDB; SDB's own resync then flags the
    #  row removed=1 rather than deleting it. Two defensive layers keep
    #  such shots out of everything (popup, history, calibration,
    #  confidence): the removed flag is filtered in the SQL WHERE (see
    #  _fetch_recent), and -- for the window before any resync has run --
    #  rows whose file no longer exists in history/ or history_archive/
    #  are rejected below. If the schema has no filename column or the
    #  history folders can't be located (e.g. desktop testing), nothing
    #  is filtered.
    # ------------------------------------------------------------------
    variable _hist_probed 0
    variable _hist_dirs {}

    proc _history_dirs {} {
        variable _hist_probed
        variable _hist_dirs
        if {!$_hist_probed} {
            set _hist_probed 1
            set dirs {}
            catch {
                foreach sub {history history_archive} {
                    set d [file join [homedir] $sub]
                    if {[file isdirectory $d]} { lappend dirs $d }
                }
            }
            set _hist_dirs $dirs
        }
        return $_hist_dirs
    }

    proc _shot_file_exists {fn} {
        set dirs [_history_dirs]
        if {[llength $dirs] == 0} { return 1 }
        if {![string match -nocase "*.shot" $fn]} { append fn ".shot" }
        foreach d $dirs {
            if {[file exists [file join $d $fn]]} { return 1 }
        }
        return 0
    }

    proc _row_is_valid_espresso {row fields} {
        # Reject by profile title / beverage type keywords when available.
        foreach key {profile bev_type} {
            if {[dict exists $fields $key] && [_text_is_nonespresso [_dget $row $key]]} {
                return 0
            }
        }
        # ... and anything whose beverage type is set but not espresso.
        if {[dict exists $fields bev_type] && ![_bev_type_is_espresso [_dget $row bev_type]]} {
            return 0
        }
        # Reject deleted shots (see deleted-shot tolerance note above).
        if {[dict exists $fields removed]} {
            set rm [string trim [_dget $row removed]]
            if {[string is true -strict $rm]} { return 0 }
        }
        if {[dict exists $fields filename]} {
            set fn [string trim [_dget $row filename]]
            if {$fn ne "" && ![_shot_file_exists $fn]} { return 0 }
        }
        # Reject shots under 5 seconds (rinses, aborts, dummies).
        set dur [_duration_seconds [_dget $row duration]]
        if {$dur eq "" || $dur < 5.0} { return 0 }
        # Grind must be numeric; dose and target yield must be positive, but
        # only when the schema actually has those columns.
        if {[_to_float [_dget $row grind]] eq ""} { return 0 }
        if {[dict exists $fields dose]} {
            set dose [_to_float [_dget $row dose]]
            if {$dose eq "" || $dose <= 0} { return 0 }
        }
        if {[dict exists $fields set_yield]} {
            set y [_to_float [_dget $row set_yield]]
            if {$y eq "" || $y <= 0} { return 0 }
        }
        return 1
    }

    proc _filter_valid_rows {rows fields} {
        set out {}
        foreach r $rows {
            if {[_row_is_valid_espresso $r $fields]} { lappend out $r }
        }
        return $out
    }

    # ------------------------------------------------------------------
    #  Calibration Accuracy (v2.1.0) -- DISPLAY ONLY. Never feeds back
    #  into any recommendation; computed purely from rows already read.
    #
    #  Relevant shots = valid shots sharing the current shot's bag (or
    #  matching its recipe when no bag fields exist -- the same fallback
    #  order the calibration search uses), so a new bag resets the score
    #  exactly like it resets calibration.
    #    evidence    = min(relevant_count, 5) / 5
    #    consistency = 1 - avg(|shot_time - target|)/10s  (floored at 0,
    #                  over the most recent up-to-4 relevant shots)
    #    score       = round(100 * (0.4*evidence + 0.6*consistency))
    #  Fewer than 2 relevant shots -> not scored ("Not enough data").
    # ------------------------------------------------------------------
    proc _confidence_band {score} {
        variable L
        set poor 39; set fair 64; set good 84
        catch { set poor $L(conf_poor_max); set fair $L(conf_fair_max); set good $L(conf_good_max) }
        if {$score <= $poor} { return "Poor" }
        if {$score <= $fair} { return "Fair" }
        if {$score <= $good} { return "Good" }
        return "Excellent"
    }

    proc _calibration_confidence {rows} {
        set nrows [llength $rows]
        if {$nrows == 0} { return [dict create ok 0] }
        set current [_shot_from_row [lindex $rows 0]]
        if {[dict size $current] == 0} { return [dict create ok 0] }
        set target [_to_float [_setting target_time 28.0]]
        if {$target eq "" || $target <= 0} { set target 28.0 }

        set count 0
        set recent_errs {}
        for {set pos 0} {$pos < $nrows} {incr pos} {
            set shot [_shot_from_row [lindex $rows $pos]]
            if {[dict size $shot] == 0} { continue }
            if {[dict exists $current bag_key]} {
                if {![_same_bag $current $shot]} { continue }
            } elseif {![_recipe_matches $current $shot]} {
                continue
            }
            incr count
            if {[llength $recent_errs] < 4} {
                lappend recent_errs [expr {abs([dict get $shot duration] - $target)}]
            }
        }
        if {$count < 2} { return [dict create ok 0] }

        set evidence [expr {double(min($count, 5)) / 5.0}]
        set sum 0.0
        foreach e $recent_errs { set sum [expr {$sum + $e}] }
        set avg_err [expr {$sum / double([llength $recent_errs])}]
        set consistency [expr {1.0 - $avg_err / 10.0}]
        if {$consistency < 0.0} { set consistency 0.0 }
        set score [expr {int(round(100.0 * (0.4 * $evidence + 0.6 * $consistency)))}]
        if {$score > 100} { set score 100 }
        if {$score < 0} { set score 0 }
        return [dict create ok 1 score $score band [_confidence_band $score]]
    }

    # Fresh score for the settings page (read-only SELECT, same pipeline
    # every other consumer uses).
    proc calibration_confidence {} {
        variable GA_FETCH_LIMIT
        lassign [locate_shot_source] db table fields
        if {$db eq "" || $table eq ""} { return [dict create ok 0] }
        set rows [_fetch_recent $db $table $fields $GA_FETCH_LIMIT]
        set rows [_filter_valid_rows $rows $fields]
        set conf [_calibration_confidence $rows]
        # v3.24.0 (F24): the row's next step, from the same rows (display
        # only, like the score). A failure loses only the step.
        set step ""
        if {[catch { set step [_conf_step $conf $rows $fields] } err]} {
            catch { msg -ERROR "GrindAdvisor: confidence next step failed: $err" }
            set step ""
        }
        dict set conf step $step
        return $conf
    }

    # v3.24.0 (design review F24): ONE short next step under the main
    # page's Confidence row while the word is below High, built only from
    # facts GA already computes for the latest shot's bag; "" when there is
    # no grounded step. In order:
    #   out of reach  the bag's regression puts the target beyond the
    #                 grinder (_reach, the popup's dead end): more shots will
    #                 not help, so say what will -- the History card's words.
    #   few shots     fewer than GA_FIT_MIN_SHOTS eligible shots (the
    #                 forecast's n, outliers left out), the minimum Bag Stats
    #                 fits an ideal grind from ("needs 4+ shots"): say how
    #                 many more.
    # Nothing when the latest shot has no bag (no "this bag" to name), or
    # when a different bag is loaded now (the step would name the wrong one).
    proc _conf_step {conf rows fields} {
        variable GA_FIT_MIN_SHOTS
        if {[llength $rows] == 0} { return "" }
        if {[_dget $conf band] in {Good Excellent}} { return "" }
        set current [_shot_from_row [lindex $rows 0]]
        if {![dict exists $current bag_key]} { return "" }
        set ck [current_bag_key]
        if {$ck ne "" && $ck ne [dict get $current bag_key]} { return "" }
        set rec [_forecast_rec $rows $fields 0]
        if {[dict size $rec] == 0} { return "" }
        if {[_reach_out $rec]} {
            return "[_num1 [dict get $rec target]] s is out of reach by grind: change dose or yield."
        }
        set n [_dget $rec n]
        if {[string is integer -strict $n] && $n >= 1 && $n < $GA_FIT_MIN_SHOTS} {
            set more [_plural [expr {$GA_FIT_MIN_SHOTS - $n}] {more shot} {more shots}]
            return "Pull $more on this bag for a steadier fit."
        }
        return ""
    }

    # ==================================================================
    #  Dose / yield source mode (v2.3.0) -- DISPLAY ONLY.
    #
    #  Chooses which dose and yield values the plugin REPORTS (popup rows,
    #  reason line, ratio, Diagnostics) per the dose_yield_mode setting:
    #    fixed  -> always the set/target values (grinder_dose_weight,
    #              target_drink_weight).
    #    actual -> the measured values (a detected actual-dose column and
    #              drink_weight), unless a measured value is 0/empty/missing,
    #              which always fails and falls back to set (with a label).
    #    auto   -> measured values only if they pass plausibility (dose
    #              within [dose_min,dose_max]; yield ratio within
    #              [ratio_min,ratio_max]); otherwise set (with a label).
    #
    #  This never touches the grind recommendation math or calibration
    #  shot-matching -- both keep using set/target values (user decision,
    #  v2.3.0). The resolver only affects what is DISPLAYED, and always
    #  states which source was used (no silent fallback).
    # ==================================================================
    proc _setting_num {key default} {
        set v [_to_float [_setting $key $default]]
        if {$v eq ""} { return $default }
        return $v
    }

    proc _fmt_g {v} {
        if {$v eq ""} { return "n/a" }
        return "[format %.1f $v]g"
    }

    # Label for a rejected measured value: distinguishes missing from 0.
    proc _reject_lbl {act reason} {
        if {$act eq ""} { return "no actual" }
        return "actual [_fmt_g $act] $reason"
    }

    proc _resolve_dose {mode set_d act_d} {
        switch -- $mode {
            fixed {
                return [list $set_d "set [_fmt_g $set_d]"]
            }
            actual {
                if {$act_d ne "" && $act_d > 0} {
                    return [list $act_d "actual [_fmt_g $act_d]"]
                }
                return [list $set_d "set [_fmt_g $set_d] ([_reject_lbl $act_d rejected])"]
            }
            default {
                if {$act_d eq "" || $act_d <= 0} {
                    return [list $set_d "set [_fmt_g $set_d] ([_reject_lbl $act_d rejected])"]
                }
                set lo [_setting_num dose_min 12.0]
                set hi [_setting_num dose_max 22.0]
                if {$act_d < $lo || $act_d > $hi} {
                    return [list $set_d "set [_fmt_g $set_d] (actual [_fmt_g $act_d] out of range)"]
                }
                return [list $act_d "actual [_fmt_g $act_d]"]
            }
        }
    }

    # Yield resolves against the already-resolved dose (for the ratio check).
    proc _resolve_yield {mode set_y act_y dose} {
        switch -- $mode {
            fixed {
                return [list $set_y "set [_fmt_g $set_y]"]
            }
            actual {
                if {$act_y ne "" && $act_y > 0} {
                    return [list $act_y "actual [_fmt_g $act_y]"]
                }
                return [list $set_y "set [_fmt_g $set_y] ([_reject_lbl $act_y rejected])"]
            }
            default {
                if {$act_y eq "" || $act_y <= 0} {
                    return [list $set_y "set [_fmt_g $set_y] ([_reject_lbl $act_y rejected])"]
                }
                if {$dose ne "" && $dose > 0} {
                    set ratio [expr {$act_y / double($dose)}]
                    set lo [_setting_num ratio_min 1.0]
                    set hi [_setting_num ratio_max 4.0]
                    if {$ratio < $lo || $ratio > $hi} {
                        return [list $set_y "set [_fmt_g $set_y] (actual [_fmt_g $act_y] out of ratio [format %.1f $ratio])"]
                    }
                }
                return [list $act_y "actual [_fmt_g $act_y]"]
            }
        }
    }

    # Resolve effective dose/yield for a raw SDB row. Returns a dict:
    #   dose yield  -> the effective numeric values ("" if none)
    #   dose_src yield_src -> human labels ("actual 18.4g", "set 18.0g (...)")
    #   ratio -> effective yield/dose ("" if not computable)
    proc _effective_dose_yield {row} {
        set mode [_setting dose_yield_mode auto]
        set set_d [_to_float [_dget $row dose]]
        set act_d [expr {[dict exists $row actual_dose] ? [_to_float [_dget $row actual_dose]] : ""}]
        set set_y [_to_float [_dget $row set_yield]]
        set act_y [_to_float [_dget $row actual_yield]]

        lassign [_resolve_dose $mode $set_d $act_d] dose dose_src
        lassign [_resolve_yield $mode $set_y $act_y $dose] yield yield_src

        set ratio ""
        if {$dose ne "" && $dose > 0 && $yield ne ""} {
            set ratio [format %.1f [expr {$yield / double($dose)}]]
        }
        return [dict create dose $dose yield $yield \
            dose_src $dose_src yield_src $yield_src ratio $ratio]
    }

    # Suffix appended to a reason line so the source is never silent.
    proc _source_reason_suffix {dy} {
        return " (dose: [dict get $dy dose_src]; yield: [dict get $dy yield_src])"
    }

    proc analyze_latest_shot {} {
        variable GA_FETCH_LIMIT
        lassign [locate_shot_source] db table fields
        if {$db eq "" || $table eq ""} {
            return [dict create ok 0 error \
                "Couldn't find a usable shot table in SDB.\nNeed columns for grind and shot time."]
        }

        set rows [_fetch_recent $db $table $fields $GA_FETCH_LIMIT]
        if {[llength $rows] == 0} {
            return [dict create ok 0 error \
                "No saved shots found in SDB yet.\nPull a shot, then try again."]
        }

        # Only real espresso shots may drive recommendations: rinse, flush,
        # steam, hot-water and other non-espresso rows are skipped, so the
        # newest VALID espresso shot is always used.
        set rows [_filter_valid_rows $rows $fields]
        if {[llength $rows] == 0} {
            return [dict create ok 0 error \
                "No valid espresso shots found in SDB.\nRinse/flush/steam rows and shots under 5s are ignored."]
        }

        set cur   [lindex $rows 0]
        set current [_shot_from_row $cur]

        if {[dict size $current] == 0} {
            return [dict create ok 0 error \
                "Latest shot is missing a numeric grind or time value."]
        }

        # Regression Forecast recommendation (v3.0.0) for the latest shot.
        set rec [_forecast_rec $rows $fields 0]
        if {[dict size $rec] == 0} {
            return [dict create ok 0 error \
                "Latest shot is missing a numeric grind or time value."]
        }

        return [_decorate_rec $rec $rows $fields 0]
    }

    # Everything the popup and the skin show beyond the bare forecast:
    # bag shot number, channel warning, confidence, identity, dose/yield
    # source and the stable id.
    #
    # v3.8.0 lifted this out of analyze_latest_shot unchanged so
    # recommendation_for_bag can produce a rec that is decorated identically.
    # Splitting it was the alternative to duplicating it, and a second copy
    # would have drifted the moment either changed.
    #
    # `pos` is the row the recommendation is about -- 0 for the latest shot,
    # or the newest row of a chosen bag.
    proc _decorate_rec {rec rows fields pos} {
        set cur     [lindex $rows $pos]
        set current [_shot_from_row $cur]

        # Bag shot number and channel warning are display extras.
        set bag_shot [_bag_shot_count $current $rows $pos]
        if {$bag_shot ne ""} { dict set rec bag_shot $bag_shot }
        set channel_warning [_channel_warning $current $rows [expr {$pos + 1}]]
        if {$channel_warning ne ""} { dict set rec channel_warning $channel_warning }

        # Display-only calibration confidence (v2.1.0); attached after the
        # recommendation is fully computed so it can never influence it.
        set conf [_calibration_confidence [lrange $rows $pos end]]
        if {[dict get $conf ok]} {
            dict set rec confidence [dict get $conf score]
            dict set rec confidence_band [dict get $conf band]
        }

        dict set rec timestamp [_dget $cur timestamp]

        # v3.7.0: stamp the recommendation with WHICH bag and profile it is
        # about, so a skin can tell a live number from a stale one after the
        # user switches bags. Display/identity only -- never read back by any
        # math. bag_key comes from _shot_from_row via _forecast_rec.
        dict set rec bag_label [_bag_label $cur]
        dict set rec profile [string trim [_dget $cur profile]]
        dict set rec segment_by_profile [_segment_by_profile]

        # Display extras (shown only when present in SDB). Dose and yield come
        # from the source-mode resolver (v2.3.0), so the popup reports the
        # chosen source; the source is also stamped onto the reason line so
        # it is never silent. This is display only -- the recommendation and
        # calibration matching above already used set/target values.
        set dy [_effective_dose_yield $cur]
        if {[dict get $dy dose] ne ""} { dict set rec dose [dict get $dy dose] }
        if {[dict get $dy yield] ne ""} { dict set rec set_yield [dict get $dy yield] }
        dict set rec dose_src [dict get $dy dose_src]
        dict set rec yield_src [dict get $dy yield_src]
        if {[dict get $dy ratio] ne ""} { dict set rec ratio [dict get $dy ratio] }
        if {[dict exists $rec reason]} {
            dict set rec reason "[dict get $rec reason][_source_reason_suffix $dy]"
        }
        set actual_yld [_to_float [_dget $cur actual_yield]]
        if {$actual_yld ne ""} { dict set rec actual_yield $actual_yld }

        # Stable id for dedup: prefer timestamp, else rowid.
        if {[dict exists $cur timestamp] && [_dget $cur timestamp] ne ""} {
            dict set rec id "ts:[_dget $cur timestamp]"
        } else {
            dict set rec id "rid:[_dget $cur __rid]"
        }
        # v3.19.0: the plain words, last, from the finished rec -- here so
        # the saved rec and every per-bag rec Lumen's tile reads carry them.
        dict set rec plain [_plain_words $rec]
        return $rec
    }

    # ------------------------------------------------------------------
    #  Recommendation math
    # ------------------------------------------------------------------
    #  Higher grind number = coarser = faster.   Lower = finer = slower.
    #  next_grind = current_grind - ((target - actual) / seconds_per_step)
    # ------------------------------------------------------------------
    proc _shot_from_row {row} {
        set grind [_to_float [_dget $row grind]]
        set dur   [_duration_seconds [_dget $row duration]]
        if {$grind eq "" || $dur eq ""} { return {} }

        set shot [dict create grind $grind duration $dur]
        set dose [_to_float [_dget $row dose]]
        if {$dose ne ""} { dict set shot dose $dose }
        set set_yld [_to_float [_dget $row set_yield]]
        if {$set_yld ne ""} { dict set shot set_yield $set_yld }

        set bag_key [_bag_key $row]
        if {$bag_key ne ""} { dict set shot bag_key $bag_key }
        return $shot
    }

    # v3.7.0: the calibration key gained the profile.
    #
    # Changing profile changes the extraction, so shots taken on a different
    # profile are not evidence about the current one -- the ladder must start
    # fresh, exactly as it does for a new bag. Owner decision, 2026-08-15.
    #
    # HONEST NOTE ON EVIDENCE, so nobody over-claims this later: replaying the
    # real engine over the tablet's history produces **7 segments either way
    # and identical ideal grinds**. This changes nothing about any shot on
    # record. The two JIVA "Origin Colombia" bags that look like a
    # profile-driven 10.2 / 12.7 split were ALREADY separate bags -- their
    # roast_date differs (one empty, one 19.09.2025). So this is a
    # forward-looking feature with zero backward validation, and equally with
    # zero regression risk. Do not cite the JIVA bags as proof it works.
    #
    # Gated by the `segment_by_profile` setting (default on) so it can be
    # turned off without a code change if fragmenting turns out to hurt.
    proc _segment_by_profile {} {
        set v [_setting segment_by_profile 1]
        if {![string is boolean -strict $v]} { return 1 }
        return [expr {$v ? 1 : 0}]
    }

    # Lowercase, trim, drop empties, join. Shared by the row-built key and the
    # live-settings key so the two can never normalize differently -- if they
    # did, the skin would see every recommendation as stale.
    proc _normalize_key_parts {vals} {
        set parts {}
        foreach v $vals {
            set v [string trim $v]
            if {$v eq ""} { continue }
            lappend parts [string tolower $v]
        }
        if {[llength $parts] == 0} { return "" }
        return [join $parts "|"]
    }

    # Builds the key from bag values + a profile title. Profile is appended
    # only when there is already bean identity: a profile on its own is not a
    # bag, and treating it as one would make every shot on a machine with no
    # bean fields look like the same "bag".
    proc _compose_bag_key {bag_values profile} {
        set vals {}
        foreach field {bean roaster origin roast_date} {
            if {[dict exists $bag_values $field]} {
                lappend vals [dict get $bag_values $field]
            }
        }
        set base [_normalize_key_parts $vals]
        if {$base eq ""} { return "" }
        if {[_segment_by_profile]} {
            set p [_normalize_key_parts [list $profile]]
            if {$p ne ""} { append base "|" $p }
        }
        return $base
    }

    proc _bag_key {row} {
        if {![dict exists $row bag_values]} { return "" }
        return [_compose_bag_key [dict get $row bag_values] [_dget $row profile]]
    }

    proc _same_bag {current shot} {
        if {![dict exists $current bag_key] || ![dict exists $shot bag_key]} {
            return 0
        }
        return [expr {[dict get $current bag_key] eq [dict get $shot bag_key]}]
    }

    # Human-readable bag name for a row: bean, then roaster. The profile is
    # appended when it is part of the key, otherwise two segments of the same
    # bean render as identical-looking duplicates in Bag Stats.
    proc _bag_label {row} {
        set bv {}
        if {[dict exists $row bag_values]} { set bv [dict get $row bag_values] }
        set parts {}
        foreach f {bean roaster} {
            set v [string trim [_dget $bv $f]]
            if {$v ne ""} { lappend parts $v }
        }
        # v3.23.0: the middle dot from a code point (ASCII source).
        # v3.24.0 (F23): one separator between all three facts -- bean,
        # roaster, profile; the profile was set off with an em dash.
        set label [join $parts " [_char middot] "]
        if {[_segment_by_profile]} {
            set p [string trim [_dget $row profile]]
            if {$p ne ""} {
                if {$label eq ""} { return $p }
                append label " [_char middot] $p"
            }
        }
        return $label
    }

    # ==================================================================
    #  Public API for skins (v3.7.0)
    #
    #  Lumen's grind tile reads ::plugins::GrindAdvisor::last_recommendation
    #  directly. Before 3.7.0 the rec carried no bag identity, so after the
    #  user switched bags the tile kept showing the PREVIOUS bag's number
    #  until the next shot was pulled. These two procs let a skin ask
    #  "is what I am holding still about the bag that is loaded now?".
    #
    #  Neither opens the database or touches the filesystem: they are safe to
    #  call from a UI refresh path that runs every 200 ms.
    # ==================================================================

    # The bag columns to read out of ::settings. Uses the mapping cached by
    # _resolve_bag_fields when an analysis has already run this session;
    # otherwise falls back to the core's own metadata names, which is what
    # shot.tcl writes into every shot file and therefore what SDB's columns
    # are called (de1app-core/app_metadata.tcl).
    proc _current_bag_cols {} {
        variable bag_field_cols
        if {[dict size $bag_field_cols] > 0} { return $bag_field_cols }
        return [dict create bean bean_type roaster bean_brand roast_date roast_date]
    }

    # The live bag metadata values from ::settings, read through the same
    # field->column mapping the row-built keys use. Split out of
    # current_bag_key in v3.13.0 so starting_estimate can match the loaded
    # bag's bean/roaster field-by-field (the composed key drops empty
    # segments, so it cannot be parsed back into fields).
    proc _current_bag_values {} {
        set bv {}
        dict for {field col} [_current_bag_cols] {
            set v ""
            catch {
                if {[info exists ::settings($col)]} { set v $::settings($col) }
            }
            dict set bv $field $v
        }
        return $bv
    }

    proc _current_profile {} {
        set profile ""
        catch {
            if {[info exists ::settings(profile_title)]} {
                set profile $::settings(profile_title)
            }
        }
        return $profile
    }

    # The calibration key for what is loaded RIGHT NOW, built from the live
    # ::settings the way a shot pulled this instant would be recorded.
    #
    # v3.13.1: a NON-ESPRESSO profile (cleaning, backflush, rinse, descale
    # ... -- the same _text_is_nonespresso gate that keeps such rows out of
    # the evidence) is not a bag identity. Owner report, 2026-08-31: running
    # "Cleaning/Forward Flush x5" blanked the skin's grind tile, because the
    # bean + cleaning-profile key named a "bag" with no shots. Returning ""
    # is the documented identity-indeterminate value, so every consumer
    # falls back to its fail-safe: last_recommendation_is_current answers 1,
    # recommendation_for_current_bag hands back the saved recommendation
    # (the number survives the cleaning session on screen), and
    # starting_estimate stays silent. Only when segmentation is on -- with
    # it off the bean-only key still matches the bag's shots and there is
    # no bug to fix. Rows are untouched: a recorded cleaning run is already
    # rejected by _row_is_valid_espresso before any key is built.
    proc current_bag_key {} {
        set profile [_current_profile]
        if {[_segment_by_profile] && [_text_is_nonespresso $profile]} {
            return ""
        }
        return [_compose_bag_key [_current_bag_values] $profile]
    }

    # 1 when the saved recommendation describes the currently loaded bag and
    # profile, 0 when the user has switched and no shot has been pulled yet.
    #
    # Deliberately fails SAFE: a recommendation saved before 3.7.0 has no
    # bag_key, and a machine with no bean fields produces an empty key. In
    # both cases we cannot tell, and returning 1 keeps a usable number on
    # screen rather than blanking the tile for everyone on older data.
    proc last_recommendation_is_current {} {
        variable last_recommendation
        if {![dict exists $last_recommendation bag_key]} { return 1 }
        set rk [dict get $last_recommendation bag_key]
        set ck [current_bag_key]
        if {$rk eq "" || $ck eq ""} { return 1 }
        return [expr {$rk eq $ck}]
    }

    # What the skin shows when a bag has no shots to calibrate from.
    proc new_bag_note {} {
        # v3.24.0 (F23): ": " between the label and what to do (was " - ").
        return "New bag: pull a shot to calibrate"
    }

    # ==================================================================
    #  New-bag starting estimate (v3.13.0)
    #
    #  What to show for a bag that has NO shots yet: a display-only
    #  starting point borrowed from bags this plugin has already
    #  calibrated, so the first shot is not a blind guess.
    #
    #  This REVERSES the owner decision of 2026-08-15 ("reset only, never
    #  seed a guessed grind for a new bag") -- reversed by the owner in
    #  the v3.13.0 pass spec, 2026-08-29. The v3.7.0 bag-key reset itself
    #  stays: the estimate is layered on top of it, not a replacement.
    #
    #  STRICTLY DISPLAY-ONLY. The estimate is not evidence: it never
    #  enters the regression, never counts as a shot, and never touches
    #  n, the slope, or Calibration Accuracy. Nothing in the engine
    #  (analyze_latest_shot -> _forecast_rec -> _compute_forecast /
    #  _ladder_small) calls this proc; shot 1 on a new bag still runs the
    #  first_shot rung exactly as before. It is called only from display
    #  paths (show_last_recommendation, show_bag_stats) and exposed for
    #  skins, which must present it as an estimate -- the word
    #  "Recommended" must not appear next to it.
    #
    #  Candidates are bags with a CONVERGED ideal grind -- the Bag Stats
    #  Theil-Sen fit behind the v3.5.0 trust gate (4+ shots, >= 1.0 grind
    #  spread, |slope| >= 0.5) -- on the SAME profile as the current bag.
    #  First rung that yields data wins:
    #    same_coffee   same bean AND roaster (a re-bought coffee; the
    #                  loaded bag has no shots, so its roast_date is
    #                  necessarily different) -> the most recent such
    #                  bag's ideal grind.
    #    same_roaster  same roaster -> median of those bags' ideals.
    #    same_profile  any bag on this profile -> median of the
    #                  GA_EST_BAG_WINDOW most recently used bags' ideals.
    #    none          -> {} ; callers keep today's "-" + new-bag note.
    #
    #  Returns {} or a dict:
    #    grind    estimate, rounded to grind_rounding_increment and
    #             clamped to the grinder range
    #    rung     same_coffee | same_roaster | same_profile
    #    bags     how many bags fed the number
    #    rung_txt "same roaster (4 bags)" -- short, for card lines
    #    label    "Start ~13.5 (est. from 4 bags)"
    #    reason   "Starting estimate: same roaster (4 bags)"
    #    sources  labels of the source bags, most recent first
    #
    #  READ-ONLY (SELECTs via _bag_data). Not memoized: do not call it
    #  from a per-tick refresh path -- it is for open-a-dialog moments.
    # ==================================================================
    variable GA_EST_BAG_WINDOW 6

    proc starting_estimate {} {
        variable GA_EST_BAG_WINDOW

        set ck [current_bag_key]
        if {$ck eq ""} { return {} }

        set data {}
        if {[catch { set data [_bag_data] } err]} {
            catch { msg -ERROR "GrindAdvisor: starting_estimate failed: $err" }
            return {}
        }
        if {![dict exists $data ok] || ![dict get $data ok]} { return {} }

        set bv [_current_bag_values]
        set cur_bean    [_normalize_key_parts [list [_dget $bv bean]]]
        set cur_roaster [_normalize_key_parts [list [_dget $bv roaster]]]
        set cur_profile [_normalize_key_parts [list [_current_profile]]]

        # Candidates: converged fit, same profile, and not this bag. If the
        # loaded bag has ANY shots the estimate does not apply -- the normal
        # recommendation path owns the display then.
        set cands {}
        foreach bag [dict get $data bags] {
            if {[dict get $bag key] eq $ck} { return {} }
            if {![dict get $bag trusted]} { continue }
            # v3.18.0: a bag whose fit puts the target outside the grinder
            # range has no real ideal (only the clamped end); never seed a
            # new bag from it -- assessed or not (v3.18.2).
            if {[_dget $bag reach_out] eq "1" || [_dget $bag reach_unassessed] eq "1"} { continue }
            if {[_normalize_key_parts [list [dict get $bag profile]]] ne $cur_profile} { continue }
            lappend cands $bag
        }
        if {[llength $cands] == 0} { return {} }

        # First rung that yields data wins. Bags are newest-first, so the
        # first same-coffee match is the most recent one.
        set rung ""
        set picked {}
        if {$cur_bean ne "" && $cur_roaster ne ""} {
            foreach bag $cands {
                set bbv [dict get $bag bag_values]
                if {[_normalize_key_parts [list [_dget $bbv bean]]] eq $cur_bean \
                 && [_normalize_key_parts [list [_dget $bbv roaster]]] eq $cur_roaster} {
                    set rung same_coffee
                    set picked [list $bag]
                    break
                }
            }
        }
        if {$rung eq "" && $cur_roaster ne ""} {
            foreach bag $cands {
                set bbv [dict get $bag bag_values]
                if {[_normalize_key_parts [list [_dget $bbv roaster]]] eq $cur_roaster} {
                    lappend picked $bag
                }
            }
            if {[llength $picked] > 0} { set rung same_roaster }
        }
        if {$rung eq ""} {
            set picked [lrange $cands 0 [expr {$GA_EST_BAG_WINDOW - 1}]]
            set rung same_profile
        }
        if {[llength $picked] == 0} { return {} }

        set ideals {}
        set sources {}
        foreach bag $picked {
            lappend ideals [dict get $bag ideal]
            lappend sources [dict get $bag label]
        }
        set grind [_clamp_grind [_round_grind [_median $ideals]]]
        set nb [llength $picked]

        # v3.23.0 (F21): the one pluraliser (was an `expr ?:` text pick).
        set nbags [_plural $nb bag]
        switch -- $rung {
            same_coffee  { set rung_txt "same coffee" }
            same_roaster { set rung_txt "same roaster ($nbags)" }
            default      { set rung_txt "this profile ($nbags)" }
        }

        return [dict create grind $grind rung $rung bags $nb \
            rung_txt $rung_txt \
            label "Start ~[_grind_fmt $grind] (est. from $nbags)" \
            reason "Starting estimate: $rung_txt" \
            sources $sources]
    }

    # ==================================================================
    #  Per-bag recommendations (v3.8.0)
    #
    #  v3.7.0 let a skin detect that the saved recommendation belonged to a
    #  different bag. That was half a solution: the tile went blank. But a bag
    #  you switch BACK to already has its own shots and its own regression, so
    #  blanking throws away a recommendation the data fully supports.
    #
    #  This computes the recommendation for any bag, from that bag's own
    #  shots, by running the EXACT same engine at that bag's most recent shot
    #  instead of the newest shot overall. No math is duplicated:
    #  _forecast_rec already takes a position and _bag_forecast_shots already
    #  filters same-bag from it.
    #
    #  Distinct from the new-bag case: a bag with NO history still returns
    #  {} here -- this only ever shows numbers a bag's own shots justify.
    #  (The 2026-08-15 "reset only, no seeded number" decision that used to
    #  govern the {} case was reversed by the owner in the v3.13.0 pass:
    #  the shotless-bag display is now starting_estimate's job, which stays
    #  a separate, display-only path and never flows through this proc.)
    # ==================================================================

    # bag_key -> rec. The skin's grind tile is re-evaluated on the app's
    # update tick (every ~200 ms), so an uncached lookup would mean opening
    # SDB and re-running the whole engine several times a second.
    variable bag_rec_cache {}

    # Dropped whenever a new shot lands, so a fresh shot can never be masked
    # by a cached recommendation computed before it.
    proc invalidate_bag_rec_cache {} {
        variable bag_rec_cache
        set bag_rec_cache {}
    }

    # The recommendation for one bag, or {} when that bag has no eligible
    # shots in the window. Memoized.
    proc recommendation_for_bag {bag_key} {
        variable bag_rec_cache
        variable GA_FETCH_LIMIT

        if {$bag_key eq ""} { return {} }
        if {[dict exists $bag_rec_cache $bag_key]} {
            return [dict get $bag_rec_cache $bag_key]
        }

        set rec {}
        if {![catch {
            lassign [locate_shot_source] db table fields
            if {$db ne "" && $table ne ""} {
                set rows [_filter_valid_rows \
                    [_fetch_recent $db $table $fields $GA_FETCH_LIMIT] $fields]
                # The bag's most recent shot; rows are newest-first.
                set nrows [llength $rows]
                for {set pos 0} {$pos < $nrows} {incr pos} {
                    if {[_bag_key [lindex $rows $pos]] ne $bag_key} { continue }
                    set r [_forecast_rec $rows $fields $pos]
                    if {[dict size $r] > 0} { set rec [_decorate_rec $r $rows $fields $pos] }
                    break
                }
            }
        } err]} {
            # Only cache a successful lookup: caching a failure would keep
            # returning {} after a transient database problem cleared.
            dict set bag_rec_cache $bag_key $rec
        } else {
            catch { msg -ERROR "GrindAdvisor: recommendation_for_bag failed: $err" }
        }
        return $rec
    }

    # Rebuild everything this plugin believes about the current bag, from the
    # shot history back up. v3.9.0, owner request.
    #
    # THE PROBLEM. Correcting a shot in the Shot History Editor changes
    # history/<file>.shot and nothing else -- that plugin never writes SDB, by
    # its own documented design. Grind Advisor reads SDB, so a corrected grind
    # or yield is invisible to it, and four separate things keep it that way:
    #
    #   1. SDB only re-reads a .shot whose mtime is newer than its stored one
    #      when populate runs -- on load if sync_on_startup is set (it is 0 by
    #      default), or from the "Resync database to history" button.
    #   2. bag_rec_cache memoizes per bag and is only dropped when a NEW shot
    #      lands.
    #   3. recommendation_for_current_bag prefers last_recommendation while it
    #      matches the loaded bag, so even an empty cache changes nothing.
    #   4. last_recommendation.tdb reloads that same saved answer at startup,
    #      so restarting does not clear it either.
    #
    # This walks all four, in order. It is deliberately NOT automatic: step 1
    # asks SDB to rescan the whole history folder, which is expensive, and it
    # is the only thing in this plugin that causes a database write -- SDB's
    # own, through SDB's own public entry point, the one its settings page
    # calls. Grind Advisor still issues no SQL but SELECT.
    #
    # Returns a human-readable summary of what it did.
    # v3.16.8 (F4): is an SDB sync running right now? populate yields with
    # `update` every ten files, so a tap handled during a run (a second
    # Recalculate, or ShotHistoryEditor's refresh after an edit) would
    # otherwise start a SECOND populate on top of the first, which then
    # resumed from its stale list of what the database held.
    # SDB's own flag, updating_db, is set by populate / create / upgrade for
    # their whole run -- but no error path clears it, so after a failed sync
    # it stays 1 for the session (SDB's Resync then refuses for good; before
    # this pass our Recalculate was what cleared it). So the flag counts only
    # while one of those three is really on the call stack: they run
    # synchronously, and anything that runs during them runs inside their
    # `update`, where `info frame` still shows the outer proc (checked on Tcl
    # 8.6.18 for a timer event; Tk bindings are dispatched the same way). A
    # stale flag is logged and ignored, and the next populate resets it.
    proc _sdb_busy {} {
        if {![info exists ::plugins::SDB::updating_db] \
         || $::plugins::SDB::updating_db != 1} { return 0 }
        for {set i [info frame]} {$i >= 1} {incr i -1} {
            set f [info frame $i]
            if {[dict exists $f proc] && [dict get $f proc] in {
                    ::plugins::SDB::populate ::plugins::SDB::create
                    ::plugins::SDB::upgrade}} { return 1 }
        }
        catch { msg "GrindAdvisor: SDB updating_db is 1 but no SDB sync is running (an earlier run failed); not treated as busy" }
        return 0
    }

    # v3.23.0 (F21): 1 when the last refresh_from_history hit a failure (the
    # SDB resync threw), so Advanced paints its note in the danger role. The
    # returned text is unchanged (ShotHistoryEditor prints it).
    variable refresh_failed 0

    proc refresh_from_history {} {
        variable refresh_failed
        set refresh_failed 0
        set steps {}

        # v3.16.8 (F4): never start a sync while one is running (see
        # _sdb_busy). Nothing is recomputed either: SDB is mid-sync. Only
        # ShotHistoryEditor can arrive here busy (recalculate checks first),
        # and it prints this after "Grind Advisor: " on its result page, so
        # the text names the button that picks the change up afterwards.
        if {[_sdb_busy]} {
            set out [translate "SDB was busy syncing, not refreshed: run Advanced > Recalculate from history once it finishes"]
            catch { msg "GrindAdvisor: refresh_from_history: $out" }
            return $out
        }

        # 1. Let SDB pick up the edited shot files.
        if {[info procs ::plugins::SDB::populate] ne ""} {
            if {[catch { ::plugins::SDB::populate "" "" 1 } err]} {
                catch { msg "GrindAdvisor: SDB resync failed: $err" }
                lappend steps [translate "SDB resync failed"]
                set refresh_failed 1
            } else {
                lappend steps [translate "SDB resynced"]
            }
        } else {
            lappend steps [translate "SDB not loaded"]
        }

        # 2. Drop every memoized per-bag recommendation.
        invalidate_bag_rec_cache

        # 3. Recompute for the loaded bag. recommendation_for_bag is the
        #    COMPUTE path on purpose: recommendation_for_current_bag would
        #    hand back the saved recommendation, which is the stale answer
        #    this whole proc exists to replace.
        set ck [current_bag_key]
        set rec {}
        if {$ck ne ""} {
            catch { set rec [recommendation_for_bag $ck] }
        }

        # 4. Persist it, or the next restart reloads the stale one from
        #    last_recommendation.tdb and prefers it all over again.
        if {$rec ne "" && ![catch { dict size $rec }] \
         && [dict exists $rec ok] && [dict get $rec ok]} {
            save_last_recommendation $rec
            set g ""
            # v3.10.2: through _fmt_num, like every other user-facing number in
            # this plugin. The source fix in _round_grind means there is no
            # artifact left to hide here -- but this string is read by people
            # (ShotHistoryEditor prints it on its Edit and Delete Result
            # pages), so it formats for the same reason the rest do.
            catch { set g [_fmt_num [dict get $rec next]] }
            if {$g ne ""} {
                lappend steps "[translate {recomputed}]: $g"
            } else {
                lappend steps [translate "recomputed"]
            }
        } elseif {$ck eq ""} {
            lappend steps [translate "no bean set, nothing to recompute"]
        } else {
            lappend steps [translate "no eligible shots for this bag"]
        }

        set out [join $steps ", "]
        catch { msg "GrindAdvisor: refresh_from_history: $out" }
        return $out
    }

    # The recommendation to DISPLAY for whatever bag is loaded right now.
    #
    # Prefers the saved one when it already describes this bag -- that is the
    # freshest possible answer, since it was computed from the shot just
    # pulled -- and otherwise computes from the bag's own history.
    proc recommendation_for_current_bag {} {
        variable last_recommendation
        set ck [current_bag_key]

        # The saved recommendation wins only when we can POSITIVELY confirm it
        # is about this bag -- it is the freshest answer, computed from the
        # shot just pulled.
        #
        # It must NOT go through last_recommendation_is_current here. That
        # proc fails SAFE by answering "current" whenever identity is unknown,
        # which is right for "should the tile blank?" but exactly wrong for
        # "should I bother computing?": a recommendation saved before v3.7.0
        # has no bag_key, so it would claim to match every bag and this would
        # hand back the same number forever. That bug shipped in v3.8.0's
        # first build and was reported from the tablet.
        if {$ck ne "" && [dict exists $last_recommendation bag_key]} {
            if {[dict get $last_recommendation bag_key] eq $ck} {
                return $last_recommendation
            }
        }

        set rec [recommendation_for_bag $ck]
        if {$rec ne "" && [dict size $rec] > 0} { return $rec }

        # Nothing computable. With no bean identity at all there is no per-bag
        # answer to be had, so fall back to whatever was saved rather than
        # blanking a machine that simply has no bean fields filled in. With a
        # real key and no shots, the bag genuinely has no calibration yet.
        if {$ck eq ""} { return $last_recommendation }
        return {}
    }

    proc _recipe_matches {current shot} {
        set checked 0
        foreach {key tol} {dose 0.2 set_yield 1.0} {
            set has_cur [dict exists $current $key]
            set has_shot [dict exists $shot $key]
            if {$has_cur && !$has_shot} { return 0 }
            if {!$has_cur && $has_shot} { return 0 }
            if {$has_cur && $has_shot} {
                set checked 1
                if {abs([dict get $current $key] - [dict get $shot $key]) > $tol} {
                    return 0
                }
            }
        }
        return $checked
    }

    proc _bag_shot_count {current rows {start 0}} {
        if {![dict exists $current bag_key]} { return "" }
        set count 0
        set nrows [llength $rows]
        for {set pos $start} {$pos < $nrows} {incr pos} {
            set shot [_shot_from_row [lindex $rows $pos]]
            if {[dict size $shot] == 0} { continue }
            if {[_same_bag $current $shot]} { incr count }
        }
        return $count
    }

    proc _channel_warning {current rows {start 1}} {
        if {![dict exists $current bag_key]} { return "" }
        set count 0
        set sum_time 0.0
        set sum_grind 0.0
        set nrows [llength $rows]
        for {set pos $start} {$pos < $nrows} {incr pos} {
            set shot [_shot_from_row [lindex $rows $pos]]
            if {[dict size $shot] == 0} { continue }
            if {![_same_bag $current $shot]} { continue }
            if {![_recipe_matches $current $shot]} { continue }
            set sum_time [expr {$sum_time + [dict get $shot duration]}]
            set sum_grind [expr {$sum_grind + [dict get $shot grind]}]
            incr count
        }
        if {$count < 2} { return "" }
        set avg_time [expr {$sum_time / double($count)}]
        set avg_grind [expr {$sum_grind / double($count)}]
        if {[dict get $current duration] < ($avg_time - 6.0) &&
            abs([dict get $current grind] - $avg_grind) < 0.5} {
            return "Possible channeling / puck issue"
        }
        return ""
    }

    # ==================================================================
    #  Recommendation engine (v3.0.0): Regression Forecast ladder.
    #
    #  One non-selectable method. By eligible-shot count n on the CURRENT
    #  bag (n resets when the bag changes):
    #    n=1  change = (shot_time - target) / S_PER_STEP_DEFAULT * DAMP
    #    n=2  same, but s/step = |(t2-t1)/(g2-g1)| when the grind moved and
    #         |slope| >= SLOPE_MIN, else the default.
    #    n>=3 recency-weighted least-squares of normalized time vs grind;
    #         solve the fitted line for the grind that predicts the target.
    #         Guards (all shots at one grind, or |m| < M_MIN) fall back to
    #         the n=2 method, stated in the reason.
    #
    #  Verified against GrindAdvisor_Shot_Calculation2.xlsx "Forecast
    #  Method": the five weighted sums, m=-4.0977, b=81.139, ideal grind
    #  12.968 -> 13.0, predicted 27.87s all reproduce exactly.
    #
    #  Internal constants (documented in Help, never settings):
    #    S_PER_STEP_DEFAULT 3.0  DAMP 0.5  SLOPE_MIN 0.1  M_MIN 0.5
    #    DECAY 0.85  DOSE_SENS 1.8 s/g  OUTLIER 2.0 g  MIN_SHOTS 3
    # ==================================================================
    variable GA_S_PER_STEP_DEFAULT 3.0
    variable GA_DAMP 0.5
    variable GA_SLOPE_MIN 0.1
    variable GA_M_MIN 0.5
    variable GA_DECAY 0.85

    # v3.10.0 -- two guards on the regression, both owner-requested after the
    # Sure Shot bag produced a recommendation of 4.0 from shots that had only
    # ever been pulled between 7.5 and 8.2.
    #
    # GA_R2_MIN: a fit explaining less than this much of the variation is not
    # a calibration, it is a line through a cloud. Measured against the real
    # history on 2026-08-19, the threshold separates the two cases cleanly and
    # changes nothing on the bags that were working:
    #
    #     Jorge Diaz Campos  R2 0.80   unchanged
    #     Origin Colombia    R2 0.65   unchanged
    #     Chelchele          R2 0.57   unchanged
    #     Hamasho Anaerobic  R2 0.42   unchanged
    #     ---------------------------- 0.30 sits in the gap
    #     Guji Hambela       R2 0.06   blocked (slope said -15.3 s/grind)
    #     Sure Shot          R2 -0.05  blocked (worse than a flat line)
    #
    # GA_EXTRAP_MARGIN: how far past the grind settings a bag has ACTUALLY
    # been pulled at we are willing to recommend. The engine used to solve the
    # fitted line anywhere at all, which is how 3.5 steps beyond the finest
    # grind ever tried became an instruction.
    variable GA_R2_MIN 0.30
    variable GA_EXTRAP_MARGIN 0.5
    variable GA_DOSE_SENS 1.8
    variable GA_OUTLIER 2.0
    variable GA_MIN_SHOTS 3
    # v3.24.0 (F24): the fewest eligible shots Bag Stats fits an ideal grind
    # from (its trust gate, "needs 4+ shots"); the main page's next step
    # counts toward the same number. Was a literal 4 in _bag_data.
    variable GA_FIT_MIN_SHOTS 4

    # How many rows the recommendation path pulls from SDB (v3.7.0: was a
    # hardcoded 40 at both call sites).
    #
    # The window must reach back far enough to hold every shot of the CURRENT
    # bag, and with several bags in rotation those shots are interleaved with
    # other bags'. Measured on the real history: the deepest single-bag span
    # is 13 shots, so a 3-bag rotation spans ~39 rows and a 5-bag one ~65 --
    # and on a machine where rinses and flushes are not purged they consume
    # the same limit (the SQL filters removed=1, not rinses). 40 was tight for
    # two bags and short for three.
    #
    # Cost, measured against the real 1071-row database: LIMIT 40 = 0.20 ms,
    # LIMIT 200 = 0.34 ms. Bag Stats already runs 600 on every open.
    variable GA_FETCH_LIMIT 200

    proc _forecast_target {} {
        set t [_to_float [_setting target_time 28.0]]
        if {$t eq "" || $t <= 0} { return 28.0 }
        return $t
    }

    # Outlier: weighed dose or yield more than OUTLIER g from the set value
    # (only checkable when the schema exposes the actual columns).
    proc _is_outlier {row} {
        variable GA_OUTLIER
        set ds [_to_float [_dget $row dose]]
        set ys [_to_float [_dget $row set_yield]]
        set da [expr {[dict exists $row actual_dose] ? [_to_float [_dget $row actual_dose]] : ""}]
        set ya [expr {[dict exists $row actual_yield] ? [_to_float [_dget $row actual_yield]] : ""}]
        if {$da ne "" && $ds ne "" && abs($da - $ds) > $GA_OUTLIER} { return 1 }
        if {$ya ne "" && $ys ne "" && abs($ya - $ys) > $GA_OUTLIER} { return 1 }
        return 0
    }

    # Normalized time: scales out yield weighing error and dose error.
    # Returns {t_norm active}. active=0 with no scale data -> raw time.
    #
    # v3.11.1: the actuals are gated through the SAME plausibility rules as
    # _resolve_dose / _resolve_yield before they are used. They were not,
    # and the engine contradicted itself on the tablet: the yield-source
    # logic rejected a 13.9g actual against a 19.1g dose as noise ("out of
    # ratio 0.7") while this proc normalized by it anyway, inflating a real
    # 50.1s shot into a fictitious 137.0s one -- 50.1 * (38/13.9). On the
    # n=1 rung, which v3.11.0 moved onto normalized time, that single point
    # WAS the recommendation: +18 steps, 5.5 -> 23.7. The regression rung
    # carried the same exposure ever since normalization existed; it was
    # only diluted by the other shots and the outlier exclusion.
    #
    # A yield ratio outside ratio_min..ratio_max or a dose outside
    # dose_min..dose_max is a scale mishap or an aborted shot, not a
    # measurement -- exactly what the source logic already concluded. An
    # implausible actual now contributes nothing: the corresponding
    # correction is skipped and, with no other actual, the shot normalizes
    # to its raw time. Deliberately independent of dose_yield_mode: these
    # are sanity bounds, not source preferences.
    proc _norm_time {row} {
        variable GA_DOSE_SENS
        set st [_duration_seconds [_dget $row duration]]
        if {$st eq ""} { return [list "" 0] }
        set ys [_to_float [_dget $row set_yield]]
        set ya [expr {[dict exists $row actual_yield] ? [_to_float [_dget $row actual_yield]] : ""}]
        set ds [_to_float [_dget $row dose]]
        set da [expr {[dict exists $row actual_dose] ? [_to_float [_dget $row actual_dose]] : ""}]
        # Gate the actual dose first: the yield gate needs the best dose
        # figure available, which _resolve_yield mirrors by taking the
        # resolved dose.
        if {$da ne ""} {
            set dlo [_setting_num dose_min 12.0]
            set dhi [_setting_num dose_max 22.0]
            if {$da <= 0 || $da < $dlo || $da > $dhi} { set da "" }
        }
        if {$ya ne ""} {
            if {$ya <= 0} {
                set ya ""
            } else {
                set dref [expr {$da ne "" ? $da : $ds}]
                if {$dref ne "" && $dref > 0} {
                    set ratio [expr {$ya / double($dref)}]
                    set rlo [_setting_num ratio_min 1.0]
                    set rhi [_setting_num ratio_max 4.0]
                    if {$ratio < $rlo || $ratio > $rhi} { set ya "" }
                }
            }
        }
        set tnorm $st
        set active 0
        if {$ya ne "" && $ya > 0 && $ys ne ""} {
            set tnorm [expr {$tnorm * ($ys / double($ya))}]
            set active 1
        }
        if {$da ne "" && $ds ne ""} {
            set tnorm [expr {$tnorm - ($da - $ds) * $GA_DOSE_SENS}]
            set active 1
        }
        return [list $tnorm $active]
    }

    # Current-bag eligible dataset from row index 'start' (newest-first).
    # Returns {shots excluded}. Same-bag when the schema has bag fields;
    # otherwise the recent valid run is treated as the current bag.
    proc _bag_forecast_shots {rows fields start} {
        set out {}
        set excluded 0
        set nrows [llength $rows]
        if {$start >= $nrows} { return [dict create shots {} excluded 0] }
        set cur [_shot_from_row [lindex $rows $start]]
        set has_bag [dict exists $cur bag_key]
        for {set pos $start} {$pos < $nrows} {incr pos} {
            set r [lindex $rows $pos]
            set sh [_shot_from_row $r]
            if {[dict size $sh] == 0} { continue }
            if {$has_bag && ![_same_bag $cur $sh]} { continue }
            if {[_is_outlier $r]} { incr excluded; continue }
            lassign [_norm_time $r] tnorm active
            if {$tnorm eq ""} { continue }
            lappend out [dict create grind [dict get $sh grind] \
                t_raw [dict get $sh duration] t_norm $tnorm norm_active $active]
        }
        return [dict create shots $out excluded $excluded]
    }

    # Recency-weighted least-squares of y vs grind (ynorm=1 -> t_norm,
    # else t_raw), newest-first with DECAY^index weights. R2 is the ordinary
    # (unweighted) goodness-of-fit of the fitted line (the sheet's "model
    # fit"). Returns {ok 1 m b r2 normalized} or {ok 0 why ...}.
    proc _weighted_regression {shots ynorm} {
        variable GA_DECAY
        set n [llength $shots]
        set Sw 0.0; set Swx 0.0; set Swy 0.0; set Swxx 0.0; set Swxy 0.0
        set distinct {}
        set normalized 0
        set xs {}; set ysv {}
        for {set k 0} {$k < $n} {incr k} {
            set s [lindex $shots $k]
            set x [dict get $s grind]
            if {$ynorm} { set y [dict get $s t_norm] } else { set y [dict get $s t_raw] }
            if {[dict get $s norm_active]} { set normalized 1 }
            set w [expr {pow($GA_DECAY, $k)}]
            set Sw   [expr {$Sw   + $w}]
            set Swx  [expr {$Swx  + $w*$x}]
            set Swy  [expr {$Swy  + $w*$y}]
            set Swxx [expr {$Swxx + $w*$x*$x}]
            set Swxy [expr {$Swxy + $w*$x*$y}]
            lappend xs $x; lappend ysv $y
            if {[lsearch -exact $distinct $x] < 0} { lappend distinct $x }
        }
        if {[llength $distinct] < 2} { return [dict create ok 0 why "all shots at one grind"] }
        set denom [expr {$Sw*$Swxx - $Swx*$Swx}]
        if {abs($denom) < 1e-9} { return [dict create ok 0 why "degenerate fit"] }
        set m [expr {($Sw*$Swxy - $Swx*$Swy) / double($denom)}]
        set b [expr {($Swy - $m*$Swx) / double($Sw)}]
        set my 0.0
        foreach y $ysv { set my [expr {$my + $y}] }
        set my [expr {$my / double($n)}]
        set sst 0.0; set ssr 0.0
        foreach x $xs y $ysv {
            set p [expr {$m*$x + $b}]
            set sst [expr {$sst + ($y-$my)*($y-$my)}]
            set ssr [expr {$ssr + ($y-$p)*($y-$p)}]
        }
        set r2 ""
        if {$sst > 1e-9} { set r2 [expr {1.0 - $ssr/$sst}] }
        return [dict create ok 1 m $m b $b r2 $r2 normalized $normalized]
    }

    proc _forecast_round {x} {
        return [_clamp_grind [_round_grind $x]]
    }

    # Hold a recommendation to the ground the bag has actually been pulled on,
    # plus GA_EXTRAP_MARGIN (v3.10.0).
    #
    # A fitted line is only evidence between the points that made it. Solving
    # it far outside them is arithmetic, not calibration: the Sure Shot bag
    # was pulled 13 times between 7.5 and 8.2 and the engine answered 4.0.
    #
    # Returns {value limited}: limited is 1 when the clamp actually bit, so
    # the caller can say so rather than quietly handing back a different
    # number than it computed. With fewer than two distinct grinds there is no
    # range to speak of, and the value passes through untouched.
    proc _limit_to_evidence {shots value} {
        variable GA_EXTRAP_MARGIN
        set lo ""; set hi ""; set distinct {}
        foreach s $shots {
            if {![dict exists $s grind]} { continue }
            set g [dict get $s grind]
            if {$lo eq "" || $g < $lo} { set lo $g }
            if {$hi eq "" || $g > $hi} { set hi $g }
            if {[lsearch -exact $distinct $g] < 0} { lappend distinct $g }
        }
        if {[llength $distinct] < 2} { return [list $value 0] }
        set lo [expr {$lo - $GA_EXTRAP_MARGIN}]
        set hi [expr {$hi + $GA_EXTRAP_MARGIN}]
        if {$value < $lo} { return [list $lo 1] }
        if {$value > $hi} { return [list $hi 1] }
        return [list $value 0]
    }

    # n=1 / n=2 rungs (also the tripped-regression fallback).
    #
    # v3.11.0 (owner-requested): these rungs use NORMALIZED time, the same
    # series the regression fits. They used raw time before, which made the
    # two halves of the engine answer different questions: the owner's real
    # first shot ran 9.6s but weighed only 22.2g of a 38g target -- had it
    # been allowed to run to yield it would have taken ~16.4s, and THAT is
    # the number that says how far off the grind is. Raw time answered
    # "when was the cup pulled away" instead, and recommended a 3-step move
    # (2.4) where the yield-corrected error justifies half that (3.6).
    #
    # _norm_time returns t_norm == t_raw whenever a shot carries no scale
    # data, so shots without actuals behave exactly as before -- the same
    # convention _weighted_regression has always relied on with ynorm=1.
    # The `normalized` flag reports whether normalization was actually
    # active on the shots THIS rung consumed, so the reason, the Why? row
    # and the Curve view can all say which series produced the number.
    proc _ladder_small {shots} {
        variable GA_S_PER_STEP_DEFAULT
        variable GA_DAMP
        variable GA_SLOPE_MIN
        set target [_forecast_target]
        set n [llength $shots]
        set latest [lindex $shots 0]
        set grind [dict get $latest grind]
        set st [dict get $latest t_norm]
        set normalized [expr {[dict get $latest norm_active] ? 1 : 0}]
        set sps $GA_S_PER_STEP_DEFAULT
        set method first_shot
        set rc "First shot"
        if {$n >= 2} {
            set prev [lindex $shots 1]
            set dg [expr {$grind - [dict get $prev grind]}]
            if {abs($dg) >= 1e-9} {
                set slope [expr {abs(($st - [dict get $prev t_norm]) / double($dg))}]
                if {$slope >= $GA_SLOPE_MIN} {
                    set sps $slope; set method two_shot; set rc "2-shot calibration"
                    if {[dict get $prev norm_active]} { set normalized 1 }
                }
            }
        }
        # Say which time drove the answer whenever it is not the raw one on
        # the clock -- otherwise "9.6s, target 28s, went COARSER" reads as a
        # contradiction.
        if {$normalized} {
            append rc " on normalized time [format %.1f $st]s"
        }
        set change [expr {($st - $target) / double($sps) * $GA_DAMP}]
        # v3.10.0: the ladder is held to the same evidence as the regression.
        # It can bolt too: a 2-shot slope is allowed down to GA_SLOPE_MIN
        # (0.1 s/grind), and dividing a 5-second error by that asks for a
        # 25-step move.
        lassign [_limit_to_evidence $shots [expr {$grind + $change}]] want limited
        set next [_forecast_round $want]
        return [dict create method $method next $next m "" b "" r2 "" r2raw "" \
            n $n normalized $normalized predicted_time "" s_per_step $sps reason_core $rc \
            limited $limited]
    }

    # v3.18.0 -- say when grind cannot reach the target (owner 2026-10-01:
    # "yes, add that as a GrindAdvisor pass"). Lykke Bam Bam on Gentle and
    # sweet, 38 g, target 28 s: four shots from 10.0 down to 5.7 ran 11.1 to
    # 15.5 s, the bag's own regression (n 4, R2 0.77, -0.99 s/grind) puts
    # 28 s at grind -7.7, yet the popup only ever said "finer by 0.5". The
    # profile caps flow on a weak puck, so the shot ends near the same time
    # whatever the grind; the honest answer is "not by grind".
    #
    # Rule: on the regression rung only (n >= GA_MIN_SHOTS, R2 >= GA_R2_MIN,
    # |m| >= GA_M_MIN, so a fit worth believing), the unclamped ideal grind
    # (target - b) / m lies outside the grinder range. Never on first_shot,
    # two_shot or either fallback: a flow-capped pair looks flat (Bam Bam's
    # first pair fitted 0.2 s/step although finer grinds still gained time).
    # The pass also proposed "more than GA_REACH_STEPS finer than the finest
    # grind tried"; the read-only backtest over all 93 regression positions
    # since 2026-06-28 (tools/backtest_reach.py on the 2026-10-02 copy of
    # shots.db) flags Bam Bam's two positions with the range rule ALONE and
    # nothing else, while any steps threshold below 6.5 also flags early
    # n=3 fits of bags that later converged (Chelchele 6.43, Origin
    # Colombia 4.41). So there is no steps constant.
    #
    # v3.18.1 (review): two more gates, neither changes the Bam Bam result.
    #   GA_REACH_TOL       out only when the fit at the range end still
    #                      misses the target by more than this many seconds,
    #                      the same 2 s window Bag Stats calls "on target".
    #                      Without it an ideal of -0.2 (0.6 s short at grind
    #                      0) said "change dose or yield" while `next` was 0.0.
    #   GA_REACH_MIN_GRINDS  at least this many DIFFERENT grinds in the fit:
    #                      3 shots at 2 grinds are pair evidence, the case the
    #                      rule already refuses on two_shot.
    # Bam Bam misses by 7.6 s (n 4, 4 grinds) and 10.3 s (n 3, 3 grinds).
    #
    # The recommendation itself is unchanged: `next` still comes from the
    # ladder. `reach` only names the dead end:
    #   out         1 when the target needs a grind outside the range
    #   assessed    1 when the gates above allowed a verdict at all
    #   g_target    the unclamped ideal grind (normalized time, like m and b)
    #   limit       the range end it falls beyond ("" when inside)
    #   t_at_limit  the fit's time at that end (an extrapolation)
    variable GA_REACH_TOL 2.0
    variable GA_REACH_MIN_GRINDS 3
    # v3.20.0: what "on target" means wherever a shot is called that -- Bag
    # Stats' shots-to-target and the History card's verdict (review: History
    # said "on target" within 1 s, Bag Stats within 2 s, for the same shot).
    variable GA_ON_TARGET_TOL 2.0

    # Shared by the rec and Bag Stats: {} when the ideal grind lies inside
    # lo..hi, else {limit miss} -- the range end it falls beyond and how many
    # seconds the line still misses the target by there. miss is
    # |m * (limit - ideal)|, which equals |target - t_at_limit|.
    proc _reach_miss {m ideal lo hi} {
        if {$ideal < $lo} {
            set lim $lo
        } elseif {$ideal > $hi} {
            set lim $hi
        } else {
            return {}
        }
        return [list $lim [expr {abs($m * ($lim - $ideal))}]]
    }

    proc _reach {fc shots gmin gmax} {
        variable GA_REACH_TOL
        variable GA_REACH_MIN_GRINDS
        set out [dict create out 0 assessed 0 g_target "" limit "" t_at_limit ""]
        if {[dict get $fc method] ne "regression" || ![dict exists $fc ideal_raw]} {
            return $out
        }
        set m [dict get $fc m]
        set b [dict get $fc b]
        set gt [dict get $fc ideal_raw]
        if {$m eq "" || $b eq "" || $gt eq ""} { return $out }
        dict set out g_target $gt
        set distinct {}
        foreach s $shots {
            set g [dict get $s grind]
            if {[lsearch -exact $distinct $g] < 0} { lappend distinct $g }
        }
        if {[llength $distinct] < $GA_REACH_MIN_GRINDS} { return $out }
        dict set out assessed 1
        set miss [_reach_miss $m $gt $gmin $gmax]
        if {[llength $miss] == 2} {
            lassign $miss limit secs
            dict set out limit $limit
            dict set out t_at_limit [expr {$m * $limit + $b}]
            if {$secs > $GA_REACH_TOL} { dict set out out 1 }
        }
        return $out
    }

    # 1 when a rec (or a saved one from before v3.18.0, which has no
    # `reach`) says the target is out of reach by grind.
    proc _reach_out {rec} {
        if {![dict exists $rec reach out]} { return 0 }
        if {[dict get $rec reach out] eq "1"} { return 1 }
        return 0
    }

    # The one plain sentence for every surface that names the dead end.
    proc _reach_line {rec} {
        if {![_reach_out $rec]} { return "" }
        return "[_fmt_num [dict get $rec target]] s is out of reach by grind on this bag: change dose or yield instead."
    }

    # ==================================================================
    #  Plain words (v3.19.0, design review F15; owner 2026-10-02: "Plain,
    #  tile too", "Both popups"). Barista words up front on the popup, the
    #  main page and Lumen's tile; slope, R2, method and rungs stay behind
    #  Why? and Calculation Details. Built from rec keys only, so a saved rec
    #  from an older version gets the same words at draw time. The technical
    #  `reason`, the method literals and confidence_band stay byte-stable:
    #  Lumen parses them.
    # ==================================================================

    # v3.19.1: a grind setting as the owner's mock writes it: "3.0", "3.25",
    # "5.2" -- _fmt_num keeps a quarter step's two decimals but turned a
    # whole number into "3" ("3.5 -> 3" on the card).
    proc _grind_fmt {v} {
        set s [_fmt_num $v]
        if {$s ne "" && [string first . $s] < 0} { append s ".0" }
        return $s
    }

    # A number as a barista reads it (seconds, grams): one decimal, no ".0".
    proc _num1 {v} {
        set s [format %.1f $v]
        if {[string match "*.0" $s]} { set s [string range $s 0 end-2] }
        return $s
    }

    # Poor / Fair / Good / Excellent (_confidence_band) in plain words.
    proc _band_plain {band} {
        switch -- $band {
            Poor      { return "low" }
            Fair      { return "medium" }
            Good      { return "high" }
            Excellent { return "very high" }
        }
        return ""
    }

    # v3.24.0 (design review F23, word before number): the Why? Confidence
    # row reads "Medium (40%)" (was "40% (medium)"); the bare score when
    # there is no band.
    proc _conf_words {score band} {
        set w [_band_plain $band]
        if {$w eq ""} { return "$score%" }
        return "[string totitle $w] ($score%)"
    }

    # The words every surface shares. Keys:
    #   move       "finer by 0.5" / "coarser by 0.5" / "keep this grind"
    #   conf       "medium confidence, 4 shots" / "first shot on this bag"
    #   band       the confidence_band it came from ("" without one)
    #   time_line  "15.5 s against a 28 s target" -- the time the engine
    #              used: when yield normalization moved it by 0.5 s or
    #              more, "16.4 s yield-adjusted ..." (v3.11.0: the raw
    #              clock time can point the other way)
    #   reach      the out-of-reach sentence, or ""
    #   warning    the channeling warning in plain words, or ""
    #   short      one line for a skin tile, about 55 characters at most
    #              (Lumen's tile note is one line of ~560 px)
    proc _plain_words {rec} {
        # v3.20.0: `used` / `adj` -- the shot time the engine judged and
        # whether that is the yield-adjusted time -- so the History card's
        # fast / slow word agrees with the move (review: "1 s fast" next to
        # "coarser by 0.1" when the adjusted time was 28.3 s).
        set out [dict create move "" conf "" band "" time_line "" reach "" warning "" short "" used "" adj 0]
        if {![dict exists $rec ok] || ![dict get $rec ok]} { return $out }
        set grind [dict get $rec grind]
        set next  [dict get $rec next]
        set delta [expr {$next - $grind}]
        if {abs($delta) < 0.001} {
            set move "keep this grind"
            set go "keep this grind"
        } elseif {$delta < 0} {
            set move "finer by [_grind_fmt [expr {abs($delta)}]]"
            set go "go finer"
        } else {
            set move "coarser by [_grind_fmt [expr {abs($delta)}]]"
            set go "go coarser"
        }
        dict set out move $move

        set n [_dget $rec n]
        set band [_dget $rec confidence_band]
        dict set out band $band
        set bw [_band_plain $band]
        # v3.19.1: n is the shots the forecast USED (outliers left out); the
        # card's recipe line counts every shot of the bag ("shot 5 on this
        # bag"), so say "4 of 5 shots" rather than two different counts.
        set cnt ""
        if {$n ne ""} {
            set cnt [_plural $n shot]
            set bs [_dget $rec bag_shot]
            if {[string is integer -strict $bs] && [string is integer -strict $n] && $bs > $n} {
                set cnt "$n of $bs shots"
            }
        }
        if {$bw ne "" && $n ne ""} {
            dict set out conf "$bw confidence, $cnt"
        } elseif {$n eq "1"} {
            dict set out conf "first shot on this bag"
        } elseif {$n ne ""} {
            dict set out conf "[_plural $n shot] on this bag"
        }

        set actual [dict get $rec actual]
        set used $actual
        set adj 0
        if {[_dget $rec normalized] eq "1"} {
            set s0 {}
            catch { set s0 [lindex [dict get $rec shots] 0] }
            if {[dict exists $s0 t_norm] && [dict exists $s0 t_raw] \
                    && abs([dict get $s0 t_raw] - $actual) < 0.05 \
                    && abs([dict get $s0 t_norm] - $actual) >= 0.5} {
                set used [dict get $s0 t_norm]
                set adj 1
            }
        }
        dict set out used $used
        dict set out adj $adj
        set tgt [_num1 [dict get $rec target]]
        if {$adj} {
            dict set out time_line "[_num1 $used] s yield-adjusted against a $tgt s target"
        } else {
            dict set out time_line "[_num1 $used] s against a $tgt s target"
        }

        dict set out reach [_reach_line $rec]
        # The rule (_channel_warning) is "much faster than the recent shots
        # at about this grind": say that, then the likely cause.
        if {[dict exists $rec channel_warning]} {
            dict set out warning "Much faster than recent shots at this grind: check puck prep"
        }
        if {[_reach_out $rec]} {
            dict set out short "$tgt s is out of reach by grind: change dose or yield"
        } elseif {$adj} {
            # v3.19.1: label the adjusted time here too -- next to the LAST
            # SHOT card's clock time a bare 26.2 s reads as a contradiction.
            dict set out short "[_num1 $used] s yield-adjusted, target $tgt s: $go"
        } else {
            dict set out short "[_num1 $used] s, target $tgt s: $go"
        }
        return $out
    }

    # Calculation Details wording: the technical side of the same fact.
    proc _reach_txt {rec} {
        variable GA_REACH_MIN_GRINDS
        variable GA_REACH_TOL
        if {![dict exists $rec reach out]} { return "n/a (saved before v3.18.0)" }
        if {[dict exists $rec reach assessed] && ![dict get $rec reach assessed]} {
            return "not assessed (fewer than $GA_REACH_MIN_GRINDS different grinds tried)"
        }
        set tgt [_fmt_num [dict get $rec target]]
        set lim [_dget [dict get $rec reach] limit]
        if {[_reach_out $rec]} {
            return "out of the grinder range: at [_fmt_num $lim] the fit predicts [format %.1f [dict get $rec reach t_at_limit]]s against a ${tgt}s target. Change dose or yield instead."
        }
        if {$lim ne ""} {
            return "at the grinder's end: at [_fmt_num $lim] the fit predicts [format %.1f [dict get $rec reach t_at_limit]]s, within [_fmt_num $GA_REACH_TOL]s of the ${tgt}s target"
        }
        return "inside the grinder range"
    }

    # The ladder: choose the rung by eligible count n.
    proc _compute_forecast {shots} {
        variable GA_MIN_SHOTS
        variable GA_M_MIN
        variable GA_R2_MIN
        set target [_forecast_target]
        set n [llength $shots]
        if {$n >= $GA_MIN_SHOTS} {
            set reg [_weighted_regression $shots 1]
            if {[dict get $reg ok]} {
                set m [dict get $reg m]; set b [dict get $reg b]
                if {abs($m) >= $GA_M_MIN} {
                    # GUARD 1 (v3.10.0): does the fit explain anything at all?
                    #
                    # |m| >= GA_M_MIN only rejects a FLAT line. Noise produces
                    # a steep one just as easily -- Sure Shot fitted -0.62
                    # s/grind through shots whose R2 was -0.05, worse than no
                    # line at all. A slope that confident out of data that
                    # scattered is not measuring the bean, it is measuring the
                    # puck prep. Hand back to the ladder, which at least only
                    # claims to be nudging from the last shot.
                    set r2 [dict get $reg r2]
                    if {$r2 ne "" && $r2 < $GA_R2_MIN} {
                        set fb [_ladder_small $shots]
                        dict set fb method regression_untrusted
                        dict set fb n $n
                        dict set fb r2 $r2
                        dict set fb reason_core \
                            "Shot times are not tracking grind on this bag (R2 [format %.2f $r2] over $n shots), so the fit was not used"
                        return $fb
                    }

                    # GUARD 2 (v3.10.0): stay on ground this bag has been
                    # pulled on. See _limit_to_evidence.
                    set ideal [expr {($target - $b) / double($m)}]
                    lassign [_limit_to_evidence $shots $ideal] want limited
                    set next [_forecast_round $want]
                    set pred [expr {$m*$next + $b}]
                    set regraw [_weighted_regression $shots 0]
                    set r2raw [expr {[dict get $regraw ok] ? [dict get $regraw r2] : ""}]
                    set core "Regression over $n shots"
                    if {$limited} {
                        append core ", held to the grind range actually tried"
                    }
                    return [dict create method regression next $next m $m b $b \
                        r2 $r2 r2raw $r2raw n $n \
                        normalized [dict get $reg normalized] \
                        predicted_time $pred s_per_step "" \
                        limited $limited ideal_raw $ideal \
                        reason_core $core]
                }
                set why "slope [format %.2f $m] too flat"
            } else {
                set why [dict get $reg why]
            }
            set fb [_ladder_small $shots]
            dict set fb method regression_fallback
            dict set fb reason_core "Regression fallback: $why"
            dict set fb n $n
            return $fb
        }
        return [_ladder_small $shots]
    }

    proc _forecast_reason {fc next} {
        set core [dict get $fc reason_core]
        if {[dict get $fc method] eq "regression"} {
            return "$core (slope [format %.2f [dict get $fc m]] s/grind, predicts [format %.1f [dict get $fc predicted_time]]s at [format %.1f $next])."
        }
        set out "$core (s/step [format %.1f [dict get $fc s_per_step]])"
        # v3.10.0: say when the answer was pulled back to the tried range,
        # rather than quietly returning a different number than was computed.
        if {[dict exists $fc limited] && [dict get $fc limited]} {
            append out ", held to the grind range actually tried"
        }
        return "$out."
    }

    # Every rung _compute_forecast can set must have an arm here. v3.10.0 added
    # regression_untrusted and did not add one, so the raw dict key reached the
    # UI: the Why? dialog's Method row read "regression_untrusted", and the
    # Lumen skin's method chip -- which has its own map with the same gap --
    # showed a truncated "regression_unt...".
    #
    # The default arm no longer hands back the key verbatim. A rung added later
    # degrades to readable words instead of leaking an internal identifier
    # again. It is a net, not a substitute for the arm: add the arm.
    proc _forecast_method_label {method} {
        switch -- $method {
            first_shot           { return "First shot" }
            two_shot             { return "2-shot calibration" }
            regression           { return "Regression forecast" }
            regression_fallback  { return "Regression fallback (pairwise)" }
            regression_untrusted { return "Regression not trusted (ladder)" }
        }
        if {$method eq ""} { return "" }
        return [string totitle [string map {_ " "} $method]]
    }

    proc _forecast_excluded_txt {rec} {
        set ex [expr {[dict exists $rec excluded] ? [dict get $rec excluded] : 0}]
        # v3.23.0 (F21): "1 outlier" / "2 outliers" (was "outlier(s)").
        if {$ex > 0} { return ", [_plural $ex outlier] excluded" }
        return ""
    }

    proc _forecast_r2_txt {rec} {
        set r2 [_dget $rec r2]
        if {$r2 eq ""} { return "n/a" }
        set out [format %.2f $r2]
        set r2r [_dget $rec r2raw]
        if {[dict get $rec normalized] && $r2r ne "" && $r2r ne $r2} {
            append out " (normalized; raw [format %.2f $r2r])"
        }
        return $out
    }

    # Full recommendation dict for the shot at row index 'pos', using the
    # current-bag eligible dataset from pos onward.
    proc _forecast_rec {rows fields pos} {
        set cur [_shot_from_row [lindex $rows $pos]]
        if {[dict size $cur] == 0} { return {} }
        set elig [_bag_forecast_shots $rows $fields $pos]
        set shots [dict get $elig shots]
        if {[llength $shots] == 0} {
            lassign [_norm_time [lindex $rows $pos]] tn ac
            if {$tn eq ""} { set tn [dict get $cur duration]; set ac 0 }
            set shots [list [dict create grind [dict get $cur grind] \
                t_raw [dict get $cur duration] t_norm $tn norm_active $ac]]
        }
        set fc [_compute_forecast $shots]
        set grind [dict get $cur grind]
        set actual [dict get $cur duration]
        set target [_forecast_target]
        set next [dict get $fc next]
        lassign [_grinder_range] gmin gmax
        set r2raw [expr {[dict exists $fc r2raw] ? [dict get $fc r2raw] : ""}]
        # v3.23.0: the key is text, picked with if (never `expr ?:`).
        set bag_key ""
        if {[dict exists $cur bag_key]} { set bag_key [dict get $cur bag_key] }
        set rec [dict create ok 1 \
            grind $grind actual $actual target $target next $next \
            error [expr {$target - $actual}] \
            reason [_forecast_reason $fc $next] \
            shots $shots \
            bag_key $bag_key \
            method [dict get $fc method] \
            m [dict get $fc m] b [dict get $fc b] r2 [dict get $fc r2] r2raw $r2raw \
            n [dict get $fc n] normalized [dict get $fc normalized] \
            excluded [dict get $elig excluded] \
            predicted_time [dict get $fc predicted_time] \
            s_per_step [dict get $fc s_per_step] \
            rounding_increment [_safe_rounding_increment] \
            grinder_min $gmin grinder_max $gmax]
        # v3.18.0: here, not in _decorate_rec, so History cards, the per-bag
        # recommendation cache and the saved rec all carry it.
        dict set rec reach [_reach $fc $shots $gmin $gmax]
        return $rec
    }

    # Round to the configured increment.
    #
    # v3.10.2: the multiply is where 2.4 stopped being 2.4. round(2.43/0.1) is
    # 24, and 24 * 0.1 is the next representable double ABOVE 2.4 -- it prints
    # as 2.4000000000000004. Seen on the tablet in
    #
    #   GrindAdvisor: refresh_from_history: SDB resynced, recomputed:
    #   2.4000000000000004
    #
    # That was never only cosmetic. This value becomes `next` in the rec dict,
    # which is written to last_recommendation.tdb and handed to the skin and to
    # ShotHistoryEditor. Every DISPLAY path happened to format it, so the
    # artifact stayed hidden until refresh_from_history's summary -- which
    # interpolated it raw -- started being printed on ShotHistoryEditor's
    # result pages.
    #
    # Fixed at the source so the artifact never enters the dict at all, rather
    # than in the one string that happened to reveal it. Snapping through a
    # fixed-precision string returns the closest double to the decimal the
    # user actually set: no grinder increment is anywhere near as fine as
    # 1e-6, so nothing real is lost.
    proc _round_grind {value} {
        set inc [_safe_rounding_increment]
        set out [expr {round($value / double($inc)) * double($inc)}]
        # Also collapses the -0.0 that a tiny negative would otherwise carry
        # into every downstream format as "-0.0".
        if {$out == 0} { return 0.0 }
        return [expr {double([format %.6f $out])}]
    }

    proc _safe_rounding_increment {} {
        set inc [_to_float [_setting grind_rounding_increment 0.5]]
        if {$inc eq "" || $inc <= 0} { return 0.5 }
        return $inc
    }

    proc _grinder_range {} {
        set lo [_to_float [_setting grinder_min 0]]
        set hi [_to_float [_setting grinder_max 50]]
        if {$lo eq ""} { set lo 0.0 }
        if {$hi eq ""} { set hi 50.0 }
        if {$lo > $hi} {
            set tmp $lo
            set lo $hi
            set hi $tmp
        }
        return [list $lo $hi]
    }

    proc _clamp_grind {value} {
        lassign [_grinder_range] lo hi
        if {$value < $lo} { return $lo }
        if {$value > $hi} { return $hi }
        return $value
    }

    # ==================================================================
    #  SDB discovery  (defensive, read-only)
    # ==================================================================

    proc locate_shot_source {} {
        variable _own_db

        # 1) Reuse an already-open sqlite connection that contains a shot table.
        foreach handle {
            ::plugins::SDB::db ::db db ::sdb sdb
            ::dui::sqlite::db ::de1::sqlite::db
        } {
            if {![_is_db $handle]} { continue }
            lassign [_find_shot_table $handle] t f
            if {$t ne ""} { return [list $handle $t $f] }
        }

        # 2) If we already opened our own read-only connection, reuse it.
        if {[_is_db $_own_db]} {
            lassign [_find_shot_table $_own_db] t f
            if {$t ne ""} { return [list $_own_db $t $f] }
        }

        # 3) Open our own read-only connection to a likely SDB file.
        foreach path [_candidate_sdb_files] {
            if {[_open_readonly $path]} {
                lassign [_find_shot_table $_own_db] t f
                if {$t ne ""} { return [list $_own_db $t $f] }
            }
        }

        return [list "" "" ""]
    }

    proc _is_db {handle} {
        if {$handle eq ""} { return 0 }
        if {![llength [info commands $handle]]} { return 0 }
        return [expr {![catch { $handle eval {SELECT 1} }]}]
    }

    proc _open_readonly {path} {
        variable _own_db
        if {$path eq "" || ![file isfile $path]} { return 0 }
        catch { $_own_db close }
        # Prefer a true read-only handle so we can never lock or alter SDB.
        if {![catch { sqlite3 $_own_db $path -readonly true }]} { return 1 }
        # Older sqlite3 builds without -readonly: open normally, still SELECT-only.
        if {![catch { sqlite3 $_own_db $path }]} { return 1 }
        return 0
    }

    proc _candidate_sdb_files {} {
        set dirs {}
        catch { lappend dirs [homedir] }
        catch { lappend dirs [file join [homedir] db] }
        catch { lappend dirs [file join [homedir] data] }
        catch { lappend dirs [file join [homedir] plugins SDB] }
        catch { lappend dirs [file dirname [homedir]] }

        set found {}
        foreach d $dirs {
            if {$d eq "" || ![file isdirectory $d]} { continue }
            foreach pat {*.sqlite *.sqlite3 *.db *.sdb} {
                foreach f [glob -nocomplain -directory $d $pat] {
                    if {[file isfile $f]} { lappend found $f }
                }
            }
        }
        set found [lsort -unique $found]

        # Rank by filename hints; most-likely shot DB first.
        set scored {}
        foreach f $found {
            set n [string tolower [file tail $f]]
            set s 0
            foreach kw {sdb shot history espresso de1} {
                if {[string match *$kw* $n]} { incr s }
            }
            lappend scored [list $s $f]
        }
        set scored [lsort -integer -decreasing -index 0 $scored]
        set out {}
        foreach pair $scored { lappend out [lindex $pair 1] }
        return $out
    }

    # ------------------------------------------------------------------
    #  Schema inspection
    # ------------------------------------------------------------------

    proc _tables {db} {
        set t {}
        catch {
            $db eval {SELECT name FROM sqlite_master
                      WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%'} r {
                lappend t $r(name)
            }
        }
        return $t
    }

    proc _columns {db table} {
        set cols {}
        catch {
            $db eval "PRAGMA table_info([_q $table])" r {
                lappend cols $r(name)
            }
        }
        return $cols
    }

    # Choose the table whose columns best match a real shot record. We require
    # at least a grind column and a shot-duration column, and reward having a
    # timestamp so we can order by recency.
    proc _find_shot_table {db} {
        set best_table ""
        set best_fields {}
        set best_score -1
        foreach t [_tables $db] {
            set cols [_columns $db $t]
            if {[llength $cols] == 0} { continue }
            set f [_resolve_fields $cols]
            if {![dict exists $f grind] || ![dict exists $f duration]} { continue }
            set score [dict size $f]
            if {[dict exists $f timestamp]} { incr score 2 }
            if {$score > $best_score} {
                set best_score $score
                set best_table $t
                set best_fields $f
            }
        }
        return [list $best_table $best_fields]
    }

    # Map logical fields -> actual column names. Resolves in an order that
    # lets the timestamp claim a "clock"/"time" column before duration's
    # generic fallback can grab it; already-assigned columns are skipped.
    proc _resolve_fields {cols} {
        variable field_patterns
        set assigned {}
        set result {}
        foreach field {grind dose set_yield actual_yield actual_dose timestamp duration profile bev_type filename removed} {
            foreach pat $field_patterns($field) {
                foreach c $cols {
                    if {[dict exists $assigned $c]} { continue }
                    if {[regexp -nocase -- $pat $c]} {
                        dict set result $field $c
                        dict set assigned $c 1
                        break
                    }
                }
                if {[dict exists $result $field]} { break }
            }
        }
        set bag_fields [_resolve_bag_fields $cols]
        if {[dict size $bag_fields] > 0} {
            dict set result bag_fields $bag_fields
        }
        return $result
    }

    proc _resolve_bag_fields {cols} {
        variable bag_field_patterns
        variable bag_field_cols
        set result {}
        foreach field {bean roaster origin roast_date} {
            foreach pat $bag_field_patterns($field) {
                foreach c $cols {
                    if {[regexp -nocase -- $pat $c]} {
                        dict set result $field $c
                        break
                    }
                }
                if {[dict exists $result $field]} { break }
            }
        }
        # Cache the field->column mapping so current_bag_key can build the
        # live key WITHOUT reopening the database. The skin may ask whether a
        # recommendation is still current on every UI refresh, and that path
        # must never touch the filesystem.
        set bag_field_cols $result
        return $result
    }

    proc _fetch_recent {db table fields limit} {
        set sel {}
        set order {}
        set selected {}
        foreach field {grind duration dose set_yield actual_yield actual_dose timestamp profile bev_type filename removed} {
            if {[dict exists $fields $field]} {
                set col [dict get $fields $field]
                if {![dict exists $selected $col]} {
                    lappend sel [_q $col]
                    dict set selected $col 1
                }
                lappend order $field
            }
        }
        set bag_order {}
        if {[dict exists $fields bag_fields]} {
            foreach {field col} [dict get $fields bag_fields] {
                if {![dict exists $selected $col]} {
                    lappend sel [_q $col]
                    dict set selected $col 1
                }
                lappend bag_order [list $field $col]
            }
        }
        set gcol [_q [dict get $fields grind]]
        set dcol [_q [dict get $fields duration]]

        # Views can expose shot data without a rowid. If there is a timestamp,
        # use it for ordering and stable ids so table/view discovery stays safe.
        set include_rowid [expr {![dict exists $fields timestamp]}]
        if {$include_rowid} {
            set q "SELECT rowid AS __rid, [join $sel {, }] FROM [_q $table]"
        } else {
            set q "SELECT [join $sel {, }] FROM [_q $table]"
        }
        append q " WHERE $gcol IS NOT NULL AND $dcol IS NOT NULL"
        # v2.1.1: honor SDB's own deleted-shot flag. SDB's resync marks rows
        # whose history file vanished with removed=1 (it never deletes rows),
        # so filtering here keeps deleted shots out without touching SDB.
        # Read-only SELECT filter; only applies when the column exists.
        if {[dict exists $fields removed]} {
            set rmcol [_q [dict get $fields removed]]
            append q " AND ($rmcol IS NULL OR $rmcol = 0)"
        }
        if {[dict exists $fields timestamp]} {
            append q " ORDER BY [_q [dict get $fields timestamp]] DESC"
        } else {
            append q " ORDER BY __rid DESC"
        }
        append q " LIMIT $limit"

        set rows {}
        catch {
            $db eval $q row {
                if {$include_rowid} {
                    set d [dict create __rid $row(__rid)]
                } else {
                    set d [dict create]
                }
                foreach field $order {
                    set col [dict get $fields $field]
                    dict set d $field $row($col)
                }
                if {[llength $bag_order] > 0} {
                    set bag_values {}
                    foreach pair $bag_order {
                        lassign $pair field col
                        dict set bag_values $field $row($col)
                    }
                    dict set d bag_values $bag_values
                }
                lappend rows $d
            }
        }
        return $rows
    }

    # ==================================================================
    #  Value parsing helpers
    # ==================================================================

    proc _dget {d k} {
        if {[dict exists $d $k]} { return [dict get $d $k] }
        return ""
    }

    proc _to_float {raw} {
        set raw [string trim $raw]
        if {$raw eq ""} { return "" }
        if {[string is double -strict $raw]} { return [expr {double($raw)}] }
        if {[regexp {[-+]?[0-9]*\.?[0-9]+} $raw m]} { return [expr {double($m)}] }
        return ""
    }

    # Shot duration may be stored either as a scalar (e.g. "22.4") or as the
    # full elapsed-time series ("0.0 0.5 ... 22.4"). For a series we take the
    # maximum value, which is the total shot time.
    proc _duration_seconds {raw} {
        set raw [string trim $raw]
        if {$raw eq ""} { return "" }
        if {[string is double -strict $raw]} { return [expr {double($raw)}] }
        set toks [regexp -all -inline {[-+]?[0-9]*\.?[0-9]+} $raw]
        if {[llength $toks] == 0} { return "" }
        set mx ""
        foreach v $toks {
            if {$mx eq "" || $v > $mx} { set mx $v }
        }
        if {$mx eq ""} { return "" }
        return [expr {double($mx)}]
    }

    proc _q {ident} {
        return "\"[string map [list \" \"\"] $ident]\""
    }

    # ==================================================================
    #  Presentation
    # ==================================================================

    proc present_result {rec} {
        variable popup_active
        # Always log the outcome so it's recoverable even if no UI shows.
        catch { msg "GrindAdvisor: [_oneline $rec]" }
        save_last_recommendation $rec

        set popup_active 1
        if {[_show_overlay_dialog $rec]} { return }
        if {[_show_tk_dialog $rec]}      { return }
        set popup_active 0
        catch { borg toast [_toast_line $rec] }
        return
    }

    # v3.19.1: the last-resort toast (no overlay, no Tk dialog) in the
    # popup's plain words; the log keeps the technical _oneline.
    proc _toast_line {rec} {
        if {![dict exists $rec ok] || ![dict get $rec ok]} { return [_oneline $rec] }
        set P [_plain_words $rec]
        return "Next grind [_grind_fmt [dict get $rec grind]] [_char arrow] [_grind_fmt [dict get $rec next]]: [dict get $P move] ([dict get $P time_line])"
    }

    proc _oneline {rec} {
        if {[dict get $rec ok]} {
            set line [format "Shot %.1fs (target %.1fs), grind %.1f -> next %.1f" \
                [dict get $rec actual] [dict get $rec target] \
                [dict get $rec grind] [dict get $rec next]]
            if {[dict exists $rec reason]} {
                append line " - [dict get $rec reason]"
            }
            return $line
        }
        return [string map {\n { }} [dict get $rec error]]
    }

    # Returns {body bignum tail} for the plain-Tk fallback dialog. bignum and
    # tail are "" for errors. v3.19.0: the same plain words as the overlay
    # popup (title, neutral hero, move and confidence, time, warnings).
    proc _dialog_lines {rec} {
        if {![dict get $rec ok]} {
            return [list "[format %c 0x26A0] Grind Advisor\n\n[dict get $rec error]" "" ""]
        }
        set P [_plain_words $rec]
        set sub [dict get $P move]
        if {[dict get $P conf] ne ""} {
            append sub "  [format %c 0xB7]  [dict get $P conf]"
        }
        set tail [list $sub [dict get $P time_line]]
        foreach k {reach warning} {
            if {[dict get $P $k] ne ""} { lappend tail "[format %c 0x26A0] [dict get $P $k]" }
        }
        # v3.19.1: the recipe line too (this fallback has no Why? button).
        set recipe {}
        if {[dict exists $rec dose]} { lappend recipe "[_num1 [dict get $rec dose]] g in" }
        if {[dict exists $rec set_yield]} { lappend recipe "[_num1 [dict get $rec set_yield]] g out" }
        if {[dict exists $rec bag_shot]} { lappend recipe "shot [dict get $rec bag_shot] on this bag" }
        if {[llength $recipe]} { lappend tail "" [join $recipe "  [format %c 0xB7]  "] }
        set hero "[_grind_fmt [dict get $rec grind]] [format %c 0x2192] [_grind_fmt [dict get $rec next]]"
        return [list "Next grind" $hero [join $tail "\n"]]
    }

    # ------------------------------------------------------------------
    #  Primary UI: a dedicated, opaque canvas widget placed on top of the
    #  skin's canvas. Because it's a separate widget (not items on the skin's
    #  own canvas), the skin's graph cannot redraw over it or bleed through.
    #  Fonts are clamped and text is wrapped so nothing overflows the panel.
    # ------------------------------------------------------------------
    # ------------------------------------------------------------------
    #  v2.0.0 popup overlays.
    #
    #  The after-shot popup, Why? explainer, and history list are raw Tk
    #  canvas widgets placed ABOVE the skin canvas (not dui pages), so they
    #  are laid out in PHYSICAL pixels detected from the real canvas -- the
    #  proven v1.3 mechanism (pixel fonts via _font, own opaque widget the
    #  skin cannot redraw over). Only the drawing inside changed in v2.0.0:
    #  content now sits on a centered rounded card over the theme scrim,
    #  using the design-system type scale (_pfonts) and label/value grid.
    #  popup_active guarding is untouched: present_result sets the flag
    #  before drawing and _close_dialog clears it; replacing the overlay
    #  content (Why?/History) keeps the flag set because the overlay widget
    #  continues to exist.
    # ------------------------------------------------------------------

    # Rec shown by the current popup; lets Why?/Back redraw without
    # recomputing or re-triggering anything.
    variable _last_rec_shown {}

    # Overlay geometry: skin-canvas parent, physical W/H, overlay path.
    proc _pgeom {} {
        set sc [_get_canvas]
        if {$sc ne ""} {
            set parent [winfo parent $sc]
            set W [winfo width $sc]
            set H [winfo height $sc]
        } else {
            set parent "."
            set W 0
            set H 0
        }
        if {$W <= 1} { catch { set W [winfo width  $parent] } }
        if {$H <= 1} { catch { set H [winfo height $parent] } }
        # v3.23.0 (F8): last resort = the core's own canvas size (the
        # coordinate source), else 1340x800 -- never winfo screenwidth /
        # screenheight (736 tall on the tablet: every overlay at 92%).
        if {$W <= 1 || $H <= 1} {
            set cw 1340
            set ch 800
            if {[llength [info commands ::dui::cget]]} {
                set v [::dui::cget screen_size_width]
                if {[string is double -strict $v] && $v > 1} { set cw $v }
                set v [::dui::cget screen_size_height]
                if {[string is double -strict $v] && $v > 1} { set ch $v }
            }
            if {$W <= 1} { set W $cw }
            if {$H <= 1} { set H $ch }
        }
        set o "$parent.grindadvisor_overlay"
        if {$parent eq "."} { set o ".grindadvisor_overlay" }
        return [list $parent $W $H $o]
    }

    # Design-system type scale for overlays, in physical pixels (title 40,
    # section 24, primary 22, body 19, caption 16, button 20 at the 800px
    # reference height), scaled by real height and the popup_font_scale
    # setting, clamped to tablet-sane ranges.
    # v3.20.0: `scale` overrides the setting -- the full-page lists (History,
    # Bag Stats) pass 1.0: their 96 px cards and page zones are fixed, so a
    # 1.5 popup scale stacked their three lines into each other. Like the dui
    # pages, they follow the page type scale, not the popup's.
    proc _pfonts {H {scale ""}} {
        set s [expr {$scale ne "" ? $scale : [_num_value popup_font_scale]}]   ;# v3.17.0: always a number
        set fs [expr {double($H) / 800.0 * $s}]
        return [dict create \
            title   [_clamp [expr {int(40 * $fs)}] 30 56] \
            section [_clamp [expr {int(24 * $fs)}] 20 34] \
            primary [_clamp [expr {int(22 * $fs)}] 18 30] \
            body    [_clamp [expr {int(19 * $fs)}] 16 26] \
            caption [_clamp [expr {int(16 * $fs)}] 14 22] \
            button  [_clamp [expr {int(20 * $fs)}] 18 28]]
    }

    # Rounded rectangle on a raw overlay canvas (smoothed polygon, same
    # technique as the dui-page rounded_rect helper above).
    proc _opoly {o x0 y0 x1 y1 r fill outline tags} {
        if {$r * 2 > ($x1 - $x0)} { set r [expr {($x1 - $x0) / 2}] }
        if {$r * 2 > ($y1 - $y0)} { set r [expr {($y1 - $y0) / 2}] }
        set pts [list \
            [expr {$x0 + $r}] $y0 [expr {$x1 - $r}] $y0 $x1 $y0 \
            $x1 [expr {$y0 + $r}] $x1 [expr {$y1 - $r}] $x1 $y1 \
            [expr {$x1 - $r}] $y1 [expr {$x0 + $r}] $y1 $x0 $y1 \
            $x0 [expr {$y1 - $r}] $x0 [expr {$y0 + $r}] $x0 $y0]
        $o create polygon {*}$pts -smooth 1 -fill $fill -outline $outline -width 2 -tags $tags
    }

    # Estimated wrapped-line count for a text at a font size and wrap width.
    proc _text_lines {text size wrap} {
        set n 1
        catch {
            set wpx [font measure [_font $size] $text]
            set n [expr {int(ceil(double($wpx) / double($wrap > 0 ? $wrap : 1)))}]
        }
        if {$n < 1} { set n 1 }
        return $n
    }

    # v3.19.0: the real rendered height of a wrapped text item, measured on
    # the overlay canvas itself (created, measured, deleted). 0 when it
    # cannot be measured; callers then fall back to one line.
    proc _measure_h {o text size wrap} {
        set h 0
        if {[catch {
            # Created visible (a hidden item has no bbox) and deleted before
            # any redraw can show it.
            set id [$o create text 0 0 -text $text -anchor nw -width $wrap \
                -font [_font $size]]
            set bb [$o bbox $id]
            $o delete $id
            if {[llength $bb] == 4} { set h [expr {[lindex $bb 3] - [lindex $bb 1]}] }
        } err]} {
            catch { msg -NOTICE "GrindAdvisor: could not measure overlay text: $err" }
        }
        if {$h <= 0} { set h [expr {int($size * 135 / 100)}] }
        return $h
    }

    # Single-line ellipsis truncation for card text (Tk -width wraps instead
    # of truncating, which would collide with the next baseline).
    # v3.20.0: weight -- a bold line measured at normal weight came out
    # wider than its budget (the card titles are bold).
    proc _fit_text {text size maxw {weight normal}} {
        if {[catch {
            set f [_font $size $weight]
            if {[font measure $f $text] > $maxw} {
                # v3.24.0: the one ellipsis glyph (_char), measured as drawn.
                set e [_char ellipsis]
                while {[string length $text] > 1 && [font measure $f "$text$e"] > $maxw} {
                    set text [string range $text 0 end-1]
                }
                set text "$text$e"
            }
        }]} {
            # font measure unavailable: leave text as-is.
        }
        return $text
    }

    # ==================================================================
    #  Frosted-glass popup (v3.14.0, reworked v3.14.1) -- skin-provided
    #  material, opaque fallback everywhere else.
    #
    #  When the active skin offers a glass material (Lumen 0.39.0's
    #  ::lumen::glass_material), the after-shot popup renders as an
    #  iOS-style frosted card: a crop of the skin's pre-blurred slab (Tk
    #  has no runtime blur/alpha, so it is a baked PNG on the skin side),
    #  with corners rounded by setting the outside-the-arc pixels
    #  transparent.
    #
    #  v3.14.1: the overlay covers ONLY THE CARD. v3.14.0 covered the
    #  whole screen and painted the skin's baked art as the scrim -- but
    #  the bake has no live text or chart (those are drawn by the app on
    #  top of the background), so the owner saw "empty placeholder
    #  blocks". Neither the app nor AndroWish can photograph the live
    #  screen, so the fix is architectural: shrink the overlay to the
    #  card's rect and the REAL page -- live numbers, chart, all of it --
    #  stays visible around the glass. Modality is kept with a Tk grab on
    #  the overlay (see _glass_grab); the skin's dim asset is no longer
    #  consumed (still validated -- it is part of the provider contract).
    #
    #  OPAQUE FALLBACK IS THE RULE (owner requirement): no glass_material
    #  proc (any other skin), material {} (not on the home page, missing
    #  or wrong-resolution assets), unreadable files, or ANY error while
    #  loading or presenting -- every path lands on the exact v3.13.x
    #  full-screen opaque popup. Layout, buttons, popup_active guarding
    #  and navigation are shared: glass only changes what the card sits
    #  on and how much screen the overlay claims.
    #
    #  Text colors follow the MATERIAL's theme via the _colors override
    #  (light text on the dark slab); the Popup theme setting keeps
    #  governing every opaque fallback. v3.15.0 put the Curve overlay on
    #  this same glass-or-opaque path, v3.16.0 added Why?; History is
    #  deliberately opaque (owner decision, v3.16.2).
    # ==================================================================
    variable _glass_mat {}
    variable _glass_slab_src ""
    variable _glass_bg_src ""
    variable _glass_photos {}

    proc _glass_cleanup {} {
        variable _glass_mat
        variable _glass_slab_src
        variable _glass_bg_src
        variable _glass_photos
        foreach im $_glass_photos { catch { image delete $im } }
        set _glass_photos {}
        set _glass_slab_src ""
        set _glass_bg_src ""
        set _glass_mat {}
    }

    # Tk grab keeps the card-only overlay modal: pointer events outside
    # the card are swallowed instead of landing on the live controls
    # beneath (a stray tap must not nudge a grind stepper or open the
    # camera). Release is layered: destroying the overlay auto-releases
    # its grab (Tk semantics), _close_dialog ungrabs explicitly first,
    # and _nav_state_change closes the dialog the moment any flow starts
    # -- the same path that already tore the popup down pre-glass. `grab
    # set` fails while a freshly placed window is not yet viewable, so it
    # is retried on the same delayed ticks that re-raise the overlay; if
    # it never lands the popup is simply not modal for that one showing
    # -- degrade, never block.
    proc _glass_grab {o} {
        catch { grab set $o }
        after 200 [list catch [list grab set $o]]
        after 600 [list catch [list grab set $o]]
    }

    proc _glass_ungrab {} {
        catch {
            set g [grab current]
            if {$g ne "" && [string match "*grindadvisor_overlay*" $g]} {
                grab release $g
            }
        }
    }

    # The material dict from the active skin, or {}. Trust but verify:
    # every field this plugin consumes is checked before use.
    proc _glass_material {} {
        if {[info procs ::lumen::glass_material] eq ""} { return {} }
        set m {}
        if {[catch { set m [::lumen::glass_material] } err]} {
            catch { msg "GrindAdvisor: glass_material failed: $err" }
            return {}
        }
        if {$m eq "" || [catch { dict size $m }]} { return {} }
        if {![dict exists $m ok] || ![dict get $m ok]} { return {} }
        # bg (the plain page art, v3.14.4) is required: the card's seam-free
        # ring is built from it. A provider without it (Lumen 0.39.0) gets
        # the opaque popup rather than the seamed glass it would produce.
        foreach k {glass bg theme} {
            if {![dict exists $m $k]} { return {} }
        }
        foreach k {glass bg} {
            if {![file exists [dict get $m $k]]} { return {} }
        }
        return $m
    }

    # Load and validate the slab for this draw. Returns 1 with
    # _glass_mat/_glass_slab_src set, or 0 with everything cleaned -- the
    # caller then renders the opaque popup unchanged. The size check is
    # strict: the consumer crops in physical pixels and a mismatched
    # image would put the wrong art under the card.
    proc _glass_setup {W H} {
        variable _glass_mat
        variable _glass_slab_src
        variable _glass_bg_src
        variable _glass_photos
        _glass_cleanup
        set m [_glass_material]
        if {$m eq ""} { return 0 }
        if {[catch {
            set slab [image create photo -file [dict get $m glass]]
            lappend _glass_photos $slab
            set bg [image create photo -file [dict get $m bg]]
            lappend _glass_photos $bg
            if {[image width $slab] != $W || [image height $slab] != $H \
             || [image width $bg] != $W || [image height $bg] != $H} {
                error "material is [image width $slab]x[image height $slab] / [image width $bg]x[image height $bg], overlay is ${W}x${H}"
            }
            set _glass_slab_src $slab
            set _glass_bg_src $bg
            set _glass_mat $m
        } err]} {
            catch { msg "GrindAdvisor: glass disabled for this draw: $err" }
            _glass_cleanup
            return 0
        }
        return 1
    }

    # (v3.16.0 briefly loaded the material's DIM art and cut slab panels
    # for a glass History; v3.16.2 removed both -- the owner keeps that
    # full-page list opaque. See the archive snapshot if it returns.)

    # Present the glass card inside a seam-free ART RING (v3.14.4).
    #
    #  Every earlier attempt to color the overlay's boundary -- one
    #  sampled -bg (v3.14.1), per-corner sampled rects (v3.14.3) -- still
    #  read as a hard cliff on-tablet, because ANY guessed color
    #  mismatches the live page somewhere along the edge. So stop
    #  guessing: the overlay now extends a margin ring beyond the card
    #  and paints that ring (in fact its whole base layer) with the
    #  skin's PLAIN page background, cropped at the identical screen
    #  coordinates. The page beneath IS that art plus live text, so the
    #  canvas boundary lands on pixel-identical art and disappears; the
    #  card's transparent corners reveal genuine local art; every edge
    #  transition happens inside the canvas, against matching pixels.
    #
    #  The slab crop, transparency-rounded corners, double-radius border
    #  (the -smooth 1 half-curvature lesson) and grab are unchanged.
    #  Returns the card-local origin {mx my} for the caller.
    proc _glass_present {o parent sx0 sy0 cw ch radius col} {
        variable _glass_slab_src
        variable _glass_bg_src
        variable _glass_photos

        # Margin ring: 24px, clamped so the overlay never leaves the
        # screen (the bg image's size IS the screen's).
        set W [image width $_glass_bg_src]
        set H [image height $_glass_bg_src]
        set M 24
        foreach lim [list $sx0 $sy0 [expr {$W - ($sx0 + $cw)}] [expr {$H - ($sy0 + $ch)}]] {
            if {$lim < $M} { set M $lim }
        }
        if {$M < 0} { set M 0 }
        set ox [expr {$sx0 - $M}]
        set oy [expr {$sy0 - $M}]
        set ow [expr {$cw + 2 * $M}]
        set oh [expr {$ch + 2 * $M}]

        # v3.16.1 flash fix (owner report: Curve -> Back flashed a glitchy
        # black square slightly larger than the card for a frame): that
        # square was THIS canvas, placed at card+ring size while its
        # background was still the bare scrim, before the art below got
        # drawn. So now everything is drawn FIRST and the canvas is
        # placed LAST -- a leaked frame can only ever show finished art.
        # The glass dialogs leave the canvas unplaced until here.

        # Base layer: the page's own art at these exact coordinates.
        set ring [image create photo]
        lappend _glass_photos $ring
        $ring copy $_glass_bg_src -from $ox $oy [expr {$ox + $ow}] [expr {$oy + $oh}]
        $o create image 0 0 -anchor nw -image $ring -tags gad

        set card [image create photo]
        lappend _glass_photos $card
        $card copy $_glass_slab_src -from $sx0 $sy0 [expr {$sx0 + $cw}] [expr {$sy0 + $ch}]
        set r $radius
        for {set i 0} {$i < $r} {incr i} {
            for {set j 0} {$j < $r} {incr j} {
                set dx [expr {$r - 0.5 - $i}]
                set dy [expr {$r - 0.5 - $j}]
                if {$dx * $dx + $dy * $dy <= $r * $r} { continue }
                $card transparency set $i $j 1
                $card transparency set [expr {$cw - 1 - $i}] $j 1
                $card transparency set $i [expr {$ch - 1 - $j}] 1
                $card transparency set [expr {$cw - 1 - $i}] [expr {$ch - 1 - $j}] 1
            }
        }
        $o create image $M $M -anchor nw -image $card -tags gad
        _opoly $o $M $M [expr {$M + $cw}] [expr {$M + $ch}] [expr {$radius * 2}] "" [dict get $col border] gad

        # place MERGES options across calls (v3.14.2, seen on-tablet): the
        # overlay was first placed -relwidth 1 -relheight 1, and Tk SUMS
        # -width with -relwidth*parent, so re-placing without a forget left
        # a card-positioned canvas the size of the whole screen PLUS the
        # card -- it blacked out everything right and below the card.
        # Forget first: the new placement then carries only these options.
        # (A glass dialog's canvas is normally still unplaced here and the
        # forget is a no-op; the merge trap bites on the opaque-fallback
        # re-place, which keeps its own forget.)
        place forget $o
        place $o -in $parent -x $ox -y $oy -width $ow -height $oh
        _glass_grab $o
        return [list $M $M]
    }

    # What the card sits on -- ONE call site per card so glass and opaque
    # can never diverge. Glass shrinks the overlay to the card plus its
    # art ring and hands back CARD-LOCAL coordinates for all the text
    # that follows; any glass failure logs, restores the full-screen
    # overlay, drops the grab, and paints the v3.13.x opaque panel with
    # the original coordinates. Returns {x0 y0 x1 y1 cx}; may clear the
    # caller's glass flag (passed by name).
    proc _present_card {o parent glassvar x0 y0 x1 y1 radius col} {
        upvar 1 $glassvar glass
        if {$glass} {
            set cw [expr {$x1 - $x0}]
            set ch [expr {$y1 - $y0}]
            if {![catch { _glass_present $o $parent $x0 $y0 $cw $ch $radius $col } m]} {
                lassign $m mx my
                return [list $mx $my [expr {$mx + $cw}] [expr {$my + $ch}] \
                    [expr {$mx + int($cw / 2)}]]
            }
            set err $m
            catch { msg "GrindAdvisor: glass card failed, using opaque: $err" }
            set glass 0
            _glass_ungrab
            catch { $o delete gad }
            catch { $o configure -bg [dict get $col scrim] }
            # forget first -- place merges options (see _glass_present), and
            # -relwidth 1 on top of a leftover -width would oversize it here
            # exactly as it did there.
            place forget $o
            place $o -in $parent -x 0 -y 0 -relwidth 1 -relheight 1
        }
        _opoly $o $x0 $y0 $x1 $y1 $radius [dict get $col panel] [dict get $col border] gad
        return [list $x0 $y0 $x1 $y1 [expr {int(($x0 + $x1) / 2)}]]
    }

    proc _show_overlay_dialog {rec} {
        variable _last_rec_shown
        variable _glass_mat
        variable _colors_override
        lassign [_pgeom] parent W H o

        set ok 1
        if {[catch {
            catch { destroy $o }
            # v3.14.0: glass when the skin offers the material; the whole
            # draw then follows the MATERIAL's theme, not popup_theme --
            # via the draw-scoped override, so helpers that fetch their
            # own colors (_obutton) agree too (v3.14.5).
            set glass [_glass_setup $W $H]
            set _colors_override ""
            if {$glass} { set _colors_override [dict get $_glass_mat theme] }
            set col [_colors]
            set F [_pfonts $H]
            set fsec  [dict get $F section]
            set fhero [dict get $F title]
            set fbody [dict get $F body]
            set fcap  [dict get $F caption]
            set fbtn  [dict get $F button]

            # Neutral theme scrim; the card floats centered on it. With
            # glass, _present_card re-places this canvas over just the
            # card's rect, so the live page stays visible around it.
            # v3.16.1: in glass mode the canvas stays UNPLACED until
            # _glass_present has drawn its art -- placing it here leaked
            # one frame of bare black scrim (the glitchy square the owner
            # saw on Curve -> Back). Opaque keeps the immediate place.
            canvas $o -bg [dict get $col scrim] -highlightthickness 0 -bd 0 \
                -takefocus 0
            if {!$glass} {
                place $o -in $parent -x 0 -y 0 -relwidth 1 -relheight 1
            }
            raise $o

            # Card: ~65% width, content-driven height, never edge-to-edge.
            set cw [expr {int($W * 0.65)}]
            if {$cw > ($W - 120)} { set cw [expr {$W - 120}] }
            if {$cw < 320} { set cw [expr {$W - 24}] }
            set pad    [_clamp [expr {int($H * 0.055)}] 28 56]
            set inner  [expr {$cw - 2 * $pad}]
            set gap_sm [_clamp [expr {int($H * 0.012)}] 8 14]
            set gap_lg [_clamp [expr {int($H * 0.025)}] 14 26]
            set gap_xl [_clamp [expr {int($H * 0.040)}] 24 40]
            set btnh   [_clamp [expr {int($H * 0.085)}] 54 70]
            set radius [_clamp [expr {int($H * 0.02)}] 10 20]
            set row_pitch [expr {int($fbody * 175 / 100)}]
            set reason_lineh [expr {int($fbody * 135 / 100)}]

            if {[dict get $rec ok]} {
                set _last_rec_shown $rec

                # v3.19.0 (design review F15; owner 2026-10-02: "Plain, tile
                # too", "Both popups"): the barista version, glass and opaque
                # alike. "Next grind" (the old check-mark "Shot Saved" claimed
                # something GrindAdvisor never did), a NEUTRAL hero (green read
                # as "all good" even at low confidence), the move and the
                # confidence directly under it, one plain time line, warnings
                # in amber behind a warning sign, a one-line recipe caption.
                # Slope, method, the technical reason and the % score are
                # behind Why?. Numbers via _fmt_num (format %.1f showed a
                # 0.25-step grind of 3.25 as "3.2").
                set P [_plain_words $rec]
                set arrow [format %c 0x2192]
                set sep "  [format %c 0xB7]  "
                set sign [format %c 0x26A0]
                set bullet [format %c 0x25CF]
                set hero "[_grind_fmt [dict get $rec grind]] $arrow [_grind_fmt [dict get $rec next]]"
                set move [dict get $P move]
                set conf [dict get $P conf]
                # v3.23.0 (F21): the shared ok role (was `good`).
                switch -- [dict get $P band] {
                    Poor             { set dotcol [dict get $col warn] }
                    Good - Excellent { set dotcol [dict get $col ok] }
                    default          { set dotcol [dict get $col muted] }
                }
                set alerts {}
                if {[dict get $P reach] ne ""}   { lappend alerts "$sign [dict get $P reach]" }
                if {[dict get $P warning] ne ""} { lappend alerts "$sign [dict get $P warning]" }
                set recipe {}
                if {[dict exists $rec dose]} { lappend recipe "[_num1 [dict get $rec dose]] g in" }
                if {[dict exists $rec set_yield]} {
                    set out_g "[_num1 [dict get $rec set_yield]] g out"
                    if {[dict exists $rec ratio]} { append out_g " (1:[dict get $rec ratio])" }
                    lappend recipe $out_g
                }
                if {[dict exists $rec bag_shot]} { lappend recipe "shot [dict get $rec bag_shot] on this bag" }
                set recipe [join $recipe $sep]
                # Captions never below the 16 px floor (_pfonts allows 14).
                set fnote [expr {max($fcap, 16)}]

                # Real heights for the wrapped amber lines, measured on this
                # canvas before the card is sized (an estimate from one
                # font measure can be a line short).
                set alert_h {}
                foreach a $alerts { lappend alert_h [_measure_h $o $a $fbody $inner] }

                # Content-driven card height.
                set ch [expr {$pad + $fsec + $gap_lg + $fhero + $gap_sm + $fbody \
                    + $gap_xl + $fbody}]
                foreach h $alert_h { set ch [expr {$ch + $gap_sm + $h}] }
                if {$recipe ne ""} { set ch [expr {$ch + $gap_lg + $fnote}] }
                set ch [expr {$ch + $gap_xl + $btnh + $pad}]
                if {$ch > ($H - 40)} { set ch [expr {$H - 40}] }

                set x0 [expr {int(($W - $cw) / 2)}]
                set y0 [expr {int(($H - $ch) / 2)}]
                set x1 [expr {$x0 + $cw}]
                set y1 [expr {$y0 + $ch}]
                set cx [expr {int(($x0 + $x1) / 2)}]

                lassign [_present_card $o $parent glass $x0 $y0 $x1 $y1 $radius $col] \
                    x0 y0 x1 y1 cx

                set y [expr {$y0 + $pad}]
                _otext $o $cx [expr {$y + $fsec / 2}] center "Next grind" $fsec [dict get $col text] $inner center bold
                incr y [expr {$fsec + $gap_lg}]

                # Hero: the grind change is the one number the user came for.
                _otext $o $cx [expr {$y + $fhero / 2}] center $hero $fhero [dict get $col text] $inner center bold
                incr y [expr {$fhero + $gap_sm}]

                # "finer by 0.5  .  * medium confidence, 4 shots", centred as
                # one line; the dot alone carries the status colour.
                set ly [expr {$y + $fbody / 2}]
                set parts [list $move [dict get $col text]]
                if {$conf ne ""} {
                    lappend parts $sep [dict get $col muted]
                    if {[dict get $P band] ne ""} { lappend parts "$bullet " $dotcol }
                    lappend parts $conf [dict get $col text]
                }
                # v3.19.1: a 3 px seam between the pieces. Tk pads every
                # text bbox by 1 px a side, so pieces laid end to end had
                # boxes overlapping by 2 px -- invisible, but verify.sh's
                # overlay overlap rule (no tolerance) would fail them.
                set f [_font $fbody]
                set seam 3
                set total [expr {-$seam}]
                foreach {s c} $parts { incr total [expr {[font measure $f $s] + $seam}] }
                set lx [expr {$cx - $total / 2}]
                foreach {s c} $parts {
                    _otext $o $lx $ly w $s $fbody $c $inner left
                    incr lx [expr {[font measure $f $s] + $seam}]
                }
                incr y [expr {$fbody + $gap_xl}]

                _otext $o $cx [expr {$y + $fbody / 2}] center [dict get $P time_line] $fbody [dict get $col body] $inner
                incr y $fbody

                foreach a $alerts h $alert_h {
                    incr y $gap_sm
                    _otext $o $cx $y n $a $fbody [dict get $col warn] $inner center
                    incr y $h
                }
                if {$recipe ne ""} {
                    incr y $gap_lg
                    _otext $o $cx [expr {$y + $fnote / 2}] center [_fit_text $recipe $fnote $inner] $fnote [dict get $col muted] $inner
                }

                # Button row: OK / Why? / Curve / History, identical size,
                # evenly spaced. Four buttons now, so the gap is tightened --
                # at 4 x the old 5%-of-card gap the labels would not fit.
                set bgap [_clamp [expr {int($cw * 0.03)}] 14 36]
                set btnw [expr {int(($cw - 2 * $pad - 3 * $bgap) / 4)}]
                set bty2 [expr {$y1 - $pad}]
                set bty1 [expr {$bty2 - $btnh}]
                set bx0 [expr {$x0 + $pad}]
                _obutton $o $bx0 $bty1 [expr {$bx0 + $btnw}] $bty2 "OK" $fbtn \
                    [list ::plugins::GrindAdvisor::_close_dialog]
                set bx0 [expr {$bx0 + $btnw + $bgap}]
                _obutton $o $bx0 $bty1 [expr {$bx0 + $btnw}] $bty2 "Why?" $fbtn \
                    [list ::plugins::GrindAdvisor::_why_and_stay]
                set bx0 [expr {$bx0 + $btnw + $bgap}]
                _obutton $o $bx0 $bty1 [expr {$bx0 + $btnw}] $bty2 "Curve" $fbtn \
                    [list ::plugins::GrindAdvisor::_curve_and_stay]
                set bx0 [expr {$bx0 + $btnw + $bgap}]
                _obutton $o $bx0 $bty1 [expr {$bx0 + $btnw}] $bty2 "History" $fbtn \
                    [list ::plugins::GrindAdvisor::_history_and_close]
            } else {
                # Error card: warning title + wrapped message + OK/History.
                set etext [dict get $rec error]
                set elines [_text_lines $etext $fbody $inner]
                if {$elines > 8} { set elines 8 }
                set ch [expr {$pad + $fsec + $gap_lg + $elines * $reason_lineh \
                    + $gap_xl + $btnh + $pad}]
                if {$ch > ($H - 40)} { set ch [expr {$H - 40}] }

                set x0 [expr {int(($W - $cw) / 2)}]
                set y0 [expr {int(($H - $ch) / 2)}]
                set x1 [expr {$x0 + $cw}]
                set y1 [expr {$y0 + $ch}]
                set cx [expr {int(($x0 + $x1) / 2)}]

                lassign [_present_card $o $parent glass $x0 $y0 $x1 $y1 $radius $col] \
                    x0 y0 x1 y1 cx

                set y [expr {$y0 + $pad}]
                _otext $o $cx [expr {$y + $fsec / 2}] center "\u26A0 Grind Advisor" $fsec [dict get $col text] $inner center bold
                incr y [expr {$fsec + $gap_lg}]
                _otext $o [expr {$x0 + $pad}] $y nw $etext $fbody [dict get $col text] $inner left

                set bgap [_clamp [expr {int($cw * 0.05)}] 24 56]
                set btnw [expr {int(($cw - 2 * $pad - $bgap) / 2)}]
                set bty2 [expr {$y1 - $pad}]
                set bty1 [expr {$bty2 - $btnh}]
                set bx0 [expr {$x0 + $pad}]
                _obutton $o $bx0 $bty1 [expr {$bx0 + $btnw}] $bty2 "OK" $fbtn \
                    [list ::plugins::GrindAdvisor::_close_dialog]
                set bx0 [expr {$bx0 + $btnw + $bgap}]
                _obutton $o $bx0 $bty1 [expr {$bx0 + $btnw}] $bty2 "History" $fbtn \
                    [list ::plugins::GrindAdvisor::_history_and_close]
            }

            # Win any race with a final skin redraw that might re-raise itself.
            after 200  [list catch [list raise $o]]
            after 600  [list catch [list raise $o]]
        } err]} {
            catch { destroy $o }
            catch { msg "GrindAdvisor: overlay dialog failed: $err" }
            set ok 0
        }
        # The material palette is scoped to THIS draw; the Curve and
        # Why? sub-dialogs run their own glass draws with their own
        # overrides, and History stays on popup_theme (opaque, v3.16.2).
        set _colors_override ""
        return $ok
    }

    # Why? button: redraw the overlay as a read-only explainer built purely
    # from the rec dict already computed and shown (no new SDB reads, no new
    # analysis). Back returns to the popup; OK closes everything.
    proc _why_and_stay {} {
        variable _last_rec_shown
        if {$_last_rec_shown eq "" || ![dict exists $_last_rec_shown ok] || \
            ![dict get $_last_rec_shown ok]} { return }
        _show_why_dialog $_last_rec_shown
    }

    proc _reshow_popup {} {
        variable _last_rec_shown
        if {$_last_rec_shown ne ""} {
            _show_overlay_dialog $_last_rec_shown
        } else {
            _close_dialog
        }
    }

    # ------------------------------------------------------------------
    #  v3.1.0 calibration curve.
    #
    #  A calibration curve is only honest if it shows the scatter and the
    #  residuals, not just a correlation number: a very high R2 can sit on top
    #  of a real bias, and a line drawn through two points always has R2 = 1
    #  while saying nothing about accuracy. So this view draws the shots, the
    #  line the model actually solved, the residuals about that line, and a
    #  caption reporting bias and spread alongside R2.
    #
    #  Everything comes from the rec dict already computed and shown. No SDB
    #  read, no re-analysis, no writes -- same rule as the Why? explainer.
    # ------------------------------------------------------------------

    # The plotted y series MUST be the series the model fitted, or the drawn
    # residuals and the reported R2 would describe different things:
    # _weighted_regression is always called with ynorm=1, so `regression`
    # works in t_norm -- and since v3.11.0 the ladder rungs work in t_norm
    # too. The choice is keyed on the REC's own `normalized` flag rather
    # than hardcoded per rung, because a recommendation saved by 3.10.x was
    # computed from raw time and carries normalized 0: plotting it in
    # t_norm would draw residuals that disagree with its own `next`. (When
    # normalization was never active the two series are identical anyway --
    # _norm_time returns t_norm == t_raw without scale data.) For ladder
    # rungs there is no fitted line, so we draw the one the ladder implies:
    # through the latest shot with slope -s_per_step, because it solves
    # next = grind + (t - target)/s_per_step.
    # Guarantee a rec that carries the bag's shots.
    #
    # A recommendation saved by an older version has no `shots` key -- but the
    # shots themselves are sitting in SDB regardless, and the plugin already
    # knows how to read them. So re-run the same read-only analysis the popup
    # itself uses, rather than asking for a shot that has already been pulled.
    #
    # The whole rec is replaced, not just its shots: captioning a stale R2 and
    # n against freshly gathered points would describe two different fits.
    proc _curve_rec {rec} {
        if {[_dget $rec shots] ne ""} { return $rec }
        if {[catch { set fresh [analyze_latest_shot] } err]} {
            catch { msg "GrindAdvisor: curve could not re-read SDB: $err" }
            return $rec
        }
        if {![dict exists $fresh ok] || ![dict get $fresh ok]} { return $rec }
        if {[_dget $fresh shots] eq ""} { return $rec }
        return $fresh
    }

    proc _curve_model {rec} {
        set shots [_dget $rec shots]
        if {$shots eq "" || [catch { llength $shots }] || [llength $shots] == 0} {
            return [dict create ok 0 why "No shots for this bag could be read from SDB. Check that SDB is enabled and has espresso shots recorded."]
        }

        set method [_dget $rec method]
        set use_norm [expr {$method eq "regression" || [_dget $rec normalized] == 1}]

        set pts {}
        foreach s $shots {
            if {[catch {
                set x [_to_float [dict get $s grind]]
                if {$use_norm} {
                    set y [_to_float [dict get $s t_norm]]
                } else {
                    set y [_to_float [dict get $s t_raw]]
                }
            }]} { continue }
            if {$x eq "" || $y eq ""} { continue }
            lappend pts [list $x $y]
        }
        if {[llength $pts] == 0} {
            return [dict create ok 0 why "No usable grind/time pairs in this recommendation."]
        }

        # The line. shots is newest-first, so index 0 is the latest shot.
        set m [_to_float [_dget $rec m]]
        set b [_to_float [_dget $rec b]]
        if {$m eq "" || $b eq ""} {
            set sps [_to_float [_dget $rec s_per_step]]
            if {$sps eq "" || $sps == 0} {
                set m ""
                set b ""
            } else {
                lassign [lindex $pts 0] lx ly
                set m [expr {-1.0 * $sps}]
                set b [expr {$ly - $m * $lx}]
            }
        }

        # Residuals about that line, and the accuracy the correlation hides.
        #
        # The residuals themselves are always drawable, but bias and spread are
        # only reported at n>=3. Below that the line is pinned to the latest
        # shot by construction (_ladder_small solves through it), so those two
        # numbers describe the construction, not the calibration -- at n=1 they
        # are identically zero and at n=2 they just restate the pair. Printing
        # them beside a verdict that says there is no fit quality yet would
        # contradict it.
        set resid {}
        set bias ""
        set rmse ""
        set maxabs ""
        if {$m ne "" && $b ne ""} {
            set sum 0.0
            set sumsq 0.0
            set mx 0.0
            foreach p $pts {
                lassign $p x y
                set r [expr {$y - ($m * $x + $b)}]
                lappend resid $r
                set sum   [expr {$sum + $r}]
                set sumsq [expr {$sumsq + $r * $r}]
                if {abs($r) > $mx} { set mx [expr {abs($r)}] }
            }
            set k [llength $resid]
            if {$k >= 3} {
                set bias   [expr {$sum / double($k)}]
                set rmse   [expr {sqrt($sumsq / double($k))}]
                set maxabs $mx
            }
        }

        return [dict create ok 1 pts $pts resid $resid m $m b $b \
            normalized $use_norm bias $bias rmse $rmse maxabs $maxabs]
    }

    # Caption under the plot: the point of the whole view. R2 alone is not
    # accuracy, so bias and spread are shown beside it, and a fit that scores
    # well while missing badly is called out rather than left to look good.
    # v3.23.0: superscript two, plus-minus and middle dot from code points
    # (ASCII source); the drawn caption is unchanged.
    proc _curve_caption {rec cm} {
        set parts {}
        set r2 [_dget $rec r2]
        set R2 "R[format %c 0xB2]"
        if {$r2 eq ""} {
            lappend parts "$R2 n/a"
        } else {
            lappend parts "$R2 [format %.3f $r2]"
        }
        if {[dict get $cm bias] ne ""} {
            lappend parts "bias [format %+.2f [dict get $cm bias]]s"
            lappend parts "spread [format %c 0xB1][format %.2f [dict get $cm rmse]]s"
        }
        set n [_dget $rec n]
        if {$n ne ""} { lappend parts "n=$n" }
        return [join $parts "   [format %c 0xB7]   "]
    }

    proc _curve_verdict {rec cm} {
        set npts [llength [dict get $cm pts]]
        if {$npts < 3} {
            return "Fewer than 3 shots on this bag: a line through them fits perfectly by definition, so there is no fit quality to judge yet."
        }
        set r2 [_dget $rec r2]
        set rmse [dict get $cm rmse]
        if {$r2 ne "" && $rmse ne "" && $r2 >= 0.97 && $rmse > 1.0} {
            return "High R[format %c 0xB2] but the residuals are large: the trend is right, the individual predictions are not. Treat the next number as a nudge, not a target."
        }
        if {$rmse ne "" && $rmse > 2.0} {
            return "Residuals are scattered widely, so shot time is being driven by something other than grind alone. Check dose and distribution before chasing the grind."
        }
        if {[dict get $cm bias] ne "" && abs([dict get $cm bias]) > 0.75} {
            return "The line sits off-centre through the points, so the model is consistently over- or under-shooting across the range."
        }
        if {$rmse ne "" && $rmse <= 1.0} {
            return "Residuals are small and evenly spread about the line: this calibration is behaving."
        }
        return "Residuals are moderate. More shots on this bag will tighten the fit."
    }

    # A "nice" tick step (1, 2 or 5 x a power of ten) giving roughly $target
    # intervals across $span, so grind ticks land on readable values like 8.5
    # or 13.0 instead of 8.437.
    proc _nice_step {span target} {
        if {$span <= 0 || $target <= 0} { return 1.0 }
        set raw [expr {double($span) / double($target)}]
        if {$raw <= 0} { return 1.0 }
        set mag [expr {pow(10, floor(log10($raw)))}]
        set n [expr {$raw / $mag}]
        # Round to the NEAREST nice value (breakpoints at the geometric
        # midpoints 1.5 / 3 / 7), not up to the next one. Rounding up halves
        # the tick count: a 3.0-wide grind range wants 0.5 steps -- 8.0, 8.5,
        # 9.0 ... which is how grinders are marked anyway -- but rounding up
        # turns that into whole numbers and three lonely ticks.
        if {$n < 1.5} {
            set s 1.0
        } elseif {$n < 3.0} {
            set s 2.0
        } elseif {$n < 7.0} {
            set s 5.0
        } else {
            set s 10.0
        }
        return [expr {$s * $mag}]
    }

    proc _curve_and_stay {} {
        variable _last_rec_shown
        if {$_last_rec_shown eq "" || ![dict exists $_last_rec_shown ok] || \
            ![dict get $_last_rec_shown ok]} { return }
        _show_curve_dialog $_last_rec_shown
    }

    proc _show_curve_dialog {rec} {
        variable _glass_mat
        variable _colors_override
        lassign [_pgeom] parent W H o
        if {[catch {
            catch { destroy $o }
            # v3.15.0: same glass-or-opaque presentation as the after-shot
            # popup (v3.14.x): glass when the skin offers the material, and
            # the whole draw then follows the MATERIAL's theme through the
            # draw-scoped override so _obutton and the plot agree (v3.14.5
            # rule). Any glass failure falls back to the opaque card.
            set glass [_glass_setup $W $H]
            set _colors_override ""
            if {$glass} { set _colors_override [dict get $_glass_mat theme] }
            set col [_colors]
            set F [_pfonts $H]
            set fsec  [dict get $F section]
            set fbody [dict get $F body]
            set fcap  [dict get $F caption]
            set fbtn  [dict get $F button]

            canvas $o -bg [dict get $col scrim] -highlightthickness 0 -bd 0 \
                -takefocus 0
            # v3.16.1: unplaced until the glass art is drawn (flash fix).
            if {!$glass} {
                place $o -in $parent -x 0 -y 0 -relwidth 1 -relheight 1
            }
            raise $o

            # Wider than the other cards: a plot needs the horizontal room.
            set cw [expr {int($W * 0.78)}]
            if {$cw > ($W - 80)} { set cw [expr {$W - 80}] }
            if {$cw < 320} { set cw [expr {$W - 24}] }
            set pad    [_clamp [expr {int($H * 0.045)}] 24 48]
            set inner  [expr {$cw - 2 * $pad}]
            set gap_sm [_clamp [expr {int($H * 0.012)}] 8 14]
            set gap_lg [_clamp [expr {int($H * 0.025)}] 14 26]
            set btnh   [_clamp [expr {int($H * 0.085)}] 54 70]
            set radius [_clamp [expr {int($H * 0.02)}] 10 20]

            # Fill in the bag's shots from SDB when the stored rec predates
            # them, so the curve works on the shots already pulled.
            set rec [_curve_rec $rec]
            set cm [_curve_model $rec]

            # Plot geometry: main panel plus a short residual strip beneath it,
            # sharing one x axis so a point and its residual line up visually.
            set axis_w [expr {int($fcap * 3.2)}]
            set main_h [_clamp [expr {int($H * 0.30)}] 150 300]
            set res_h  [_clamp [expr {int($H * 0.11)}] 60 120]
            set caption_h [expr {$fcap + $gap_sm}]
            set cap_lineh [expr {int($fcap * 135 / 100)}]

            if {[dict get $cm ok]} {
                # Measure the verdict rather than assuming two lines: it wraps
                # to three on a narrow card, and a fixed guess would push the
                # text into the button row.
                set vlines [_text_lines [_curve_verdict $rec $cm] $fcap $inner]
                if {$vlines > 3} { set vlines 3 }
                set verdict_h [expr {$vlines * $cap_lineh}]
                # main plot | y-label row | residual strip | tick + grind
                # numbers | axis caption row | caption | verdict
                set tickh [_clamp [expr {int($fcap * 0.35)}] 3 7]
                set body_h [expr {$main_h + $gap_sm + $fcap + $gap_sm + $res_h \
                    + $tickh + 2 + $fcap + $gap_sm + $fcap \
                    + $gap_lg + $caption_h + $verdict_h}]
            } else {
                # No plot to draw: a compact message card, not a tall empty one.
                set wlines [_text_lines [dict get $cm why] [dict get $F body] $inner]
                if {$wlines > 6} { set wlines 6 }
                set body_h [expr {$wlines * int([dict get $F body] * 135 / 100)}]
            }

            set ch [expr {$pad + $fsec + $gap_lg + $body_h + $gap_lg + $btnh + $pad}]
            if {$ch > ($H - 24)} { set ch [expr {$H - 24}] }

            set x0 [expr {int(($W - $cw) / 2)}]
            set y0 [expr {int(($H - $ch) / 2)}]
            set x1 [expr {$x0 + $cw}]
            set y1 [expr {$y0 + $ch}]
            set cx [expr {int(($x0 + $x1) / 2)}]

            lassign [_present_card $o $parent glass $x0 $y0 $x1 $y1 $radius $col] \
                x0 y0 x1 y1 cx

            set y [expr {$y0 + $pad}]
            _otext $o $cx [expr {$y + $fsec / 2}] center "Calibration curve" $fsec [dict get $col text] $inner center bold
            incr y [expr {$fsec + $gap_lg}]

            if {![dict get $cm ok]} {
                _otext $o [expr {$x0 + $pad}] $y nw [dict get $cm why] $fbody [dict get $col text] $inner left
            } else {
                set plot_x0 [expr {$x0 + $pad + $axis_w}]
                set plot_x1 [expr {$x1 - $pad}]
                _draw_curve_panels $o $rec $cm $plot_x0 $y $plot_x1 \
                    $main_h $res_h $fcap $gap_sm $col
                # Must match the body_h budget above, term for term.
                incr y [expr {$main_h + $gap_sm + $fcap + $gap_sm + $res_h \
                    + $tickh + 2 + $fcap + $gap_sm + $fcap + $gap_lg}]

                _otext $o $cx [expr {$y + $fcap / 2}] center [_curve_caption $rec $cm] \
                    $fcap [dict get $col info] $inner center bold
                incr y [expr {$fcap + $gap_sm}]
                _otext $o [expr {$x0 + $pad}] $y nw [_curve_verdict $rec $cm] \
                    $fcap [dict get $col muted] $inner left
            }

            set bgap [_clamp [expr {int($cw * 0.05)}] 24 56]
            set btnw [expr {int(($cw - 2 * $pad - $bgap) / 2)}]
            set bty2 [expr {$y1 - $pad}]
            set bty1 [expr {$bty2 - $btnh}]
            set bx0 [expr {$x0 + $pad}]
            _obutton $o $bx0 $bty1 [expr {$bx0 + $btnw}] $bty2 "Back" $fbtn \
                [list ::plugins::GrindAdvisor::_reshow_popup]
            set bx0 [expr {$bx0 + $btnw + $bgap}]
            _obutton $o $bx0 $bty1 [expr {$bx0 + $btnw}] $bty2 "OK" $fbtn \
                [list ::plugins::GrindAdvisor::_close_dialog]

            after 200  [list catch [list raise $o]]
            after 600  [list catch [list raise $o]]
        } err]} {
            catch { destroy $o }
            catch { msg "GrindAdvisor: curve dialog failed: $err" }
            set _colors_override ""
            return 0
        }
        # Draw-scoped, exactly like _show_overlay_dialog (v3.14.5).
        set _colors_override ""
        return 1
    }

    # Scatter + fitted line above, residuals about that line below, on one
    # shared x scale. Drawn with plain canvas primitives (no BLT) because this
    # overlay is a raw Tk canvas in physical pixels, like the rest of the popup.
    proc _draw_curve_panels {o rec cm px0 py0 px1 main_h res_h fcap gap col} {
        set pts   [dict get $cm pts]
        set resid [dict get $cm resid]
        set m     [dict get $cm m]
        set b     [dict get $cm b]

        # x range over the shots, widened to include the recommended grind so
        # the marker for it is always on the plot.
        set xs {}
        set ys {}
        foreach p $pts { lassign $p x yy; lappend xs $x; lappend ys $yy }
        set xmin [::tcl::mathfunc::min {*}$xs]
        set xmax [::tcl::mathfunc::max {*}$xs]
        set nextg [_to_float [_dget $rec next]]
        if {$nextg ne ""} {
            if {$nextg < $xmin} { set xmin $nextg }
            if {$nextg > $xmax} { set xmax $nextg }
        }
        if {$xmax - $xmin < 1e-6} {
            set xmin [expr {$xmin - 0.5}]
            set xmax [expr {$xmax + 0.5}]
        }
        set xpadv [expr {($xmax - $xmin) * 0.10}]
        set xmin [expr {$xmin - $xpadv}]
        set xmax [expr {$xmax + $xpadv}]

        # y range over the shots and the target line.
        set ymin [::tcl::mathfunc::min {*}$ys]
        set ymax [::tcl::mathfunc::max {*}$ys]
        set tgt [_to_float [_dget $rec target]]
        if {$tgt ne ""} {
            if {$tgt < $ymin} { set ymin $tgt }
            if {$tgt > $ymax} { set ymax $tgt }
        }
        if {$ymax - $ymin < 1e-6} {
            set ymin [expr {$ymin - 1.0}]
            set ymax [expr {$ymax + 1.0}]
        }
        set ypadv [expr {($ymax - $ymin) * 0.12}]
        set ymin [expr {$ymin - $ypadv}]
        set ymax [expr {$ymax + $ypadv}]

        set py1 [expr {$py0 + $main_h}]
        set sx [expr {double($px1 - $px0) / double($xmax - $xmin)}]
        set sy [expr {double($main_h) / double($ymax - $ymin)}]

        # Residual strip geometry is needed up here because the grind
        # gridlines run through both panels, and the grid has to be drawn
        # before the data or Tk stacks it on top of the points.
        set ry0 [expr {$py1 + $gap + $fcap + $gap}]
        set ry1 [expr {$ry0 + $res_h}]
        set rmid [expr {($ry0 + $ry1) / 2}]
        set tickh [_clamp [expr {int($fcap * 0.35)}] 3 7]

        # Axes, both panels.
        $o create line $px0 $py0 $px0 $py1 -fill [dict get $col muted] -width 1 -tags gad
        $o create line $px0 $py1 $px1 $py1 -fill [dict get $col muted] -width 1 -tags gad
        $o create line $px0 $ry0 $px0 $ry1 -fill [dict get $col muted] -width 1 -tags gad
        $o create line $px0 $rmid $px1 $rmid -fill [dict get $col muted] -width 1 -tags gad

        # ---- shared grind axis ----
        #
        # Ticks carry the grind numbers, and each runs a faint gridline through
        # BOTH panels, so a point (or its residual) can be traced straight down
        # to the grind that produced it. That is the whole reason the panels
        # share an x scale. Drawn here, before the data, so it sits underneath.
        set step [_nice_step [expr {$xmax - $xmin}] 5]
        set t [expr {ceil($xmin / $step) * $step}]
        while {$t <= $xmax + 1e-9} {
            set tx [expr {$px0 + ($t - $xmin) * $sx}]
            if {$tx >= $px0 - 1 && $tx <= $px1 + 1} {
                $o create line $tx $py0 $tx $py1 -fill [dict get $col border] \
                    -width 1 -dash {1 6} -tags gad
                $o create line $tx $ry0 $tx $ry1 -fill [dict get $col border] \
                    -width 1 -dash {1 6} -tags gad
                $o create line $tx $py1 $tx [expr {$py1 + $tickh}] \
                    -fill [dict get $col muted] -width 1 -tags gad
                $o create line $tx $ry1 $tx [expr {$ry1 + $tickh}] \
                    -fill [dict get $col muted] -width 1 -tags gad
                _otext $o $tx [expr {$ry1 + $tickh + 2}] n [_fmt_num $t] \
                    $fcap [dict get $col muted] 0 center
            }
            set t [expr {$t + $step}]
        }

        # Target-time guide: the horizontal the model is solving for.
        if {$tgt ne ""} {
            set ty [expr {$py1 - ($tgt - $ymin) * $sy}]
            $o create line $px0 $ty $px1 $ty -fill [dict get $col muted] \
                -width 1 -dash {3 4} -tags gad
            _otext $o [expr {$px1 - 4}] [expr {$ty - $fcap}] se \
                "target [_fmt_num $tgt]s" $fcap [dict get $col muted] 0 right
        }

        # The fitted line, evaluated at the plot edges and clipped to the box.
        if {$m ne "" && $b ne ""} {
            set lx0 $xmin
            set lx1 $xmax
            set ly0 [expr {$m * $lx0 + $b}]
            set ly1 [expr {$m * $lx1 + $b}]
            # Clip to [ymin,ymax] by solving for x where the line leaves the box.
            foreach {edge} {0 1} {
                if {$edge == 0} { set ly $ly0 } else { set ly $ly1 }
                if {$ly < $ymin || $ly > $ymax} {
                    set bound [expr {$ly < $ymin ? $ymin : $ymax}]
                    if {abs($m) > 1e-9} {
                        set nx [expr {($bound - $b) / double($m)}]
                        if {$nx >= $xmin && $nx <= $xmax} {
                            if {$edge == 0} {
                                set lx0 $nx; set ly0 $bound
                            } else {
                                set lx1 $nx; set ly1 $bound
                            }
                        }
                    }
                }
            }
            $o create line \
                [expr {$px0 + ($lx0 - $xmin) * $sx}] [expr {$py1 - ($ly0 - $ymin) * $sy}] \
                [expr {$px0 + ($lx1 - $xmin) * $sx}] [expr {$py1 - ($ly1 - $ymin) * $sy}] \
                -fill [dict get $col info] -width 2 -tags gad
        }

        # The recommended grind, as a labelled vertical. On the regression rung
        # this is exactly where the fitted line crosses the target time (then
        # rounded to the grinder's increment), so the crossing of the two
        # dashed guides IS the answer the popup gives -- label it as such
        # rather than leaving the user to read it off the axis.
        if {$nextg ne ""} {
            set nx [expr {$px0 + ($nextg - $xmin) * $sx}]
            $o create line $nx $py0 $nx $py1 -fill [dict get $col info] \
                -width 1 -dash {2 5} -tags gad
            # Label inside the plot, flipped to the other side of the line when
            # the marker sits near the right edge so it cannot run off the card.
            set ntxt "grind [_fmt_num $nextg]"
            if {$nx > ($px0 + $px1) / 2} {
                _otext $o [expr {$nx - 5}] [expr {$py0 + 2}] ne $ntxt $fcap [dict get $col info] 0 right
            } else {
                _otext $o [expr {$nx + 5}] [expr {$py0 + 2}] nw $ntxt $fcap [dict get $col info] 0 left
            }
        }

        # Shot points. Newest first, so index 0 is the latest shot: draw it
        # filled and larger so "where am I now" is readable at a glance.
        set r [_clamp [expr {int($fcap * 0.34)}] 3 7]
        set i 0
        foreach p $pts {
            lassign $p x yy
            set cxp [expr {$px0 + ($x - $xmin) * $sx}]
            set cyp [expr {$py1 - ($yy - $ymin) * $sy}]
            if {$i == 0} {
                set rr [expr {$r + 2}]
                $o create oval [expr {$cxp - $rr}] [expr {$cyp - $rr}] \
                    [expr {$cxp + $rr}] [expr {$cyp + $rr}] \
                    -fill [dict get $col info] -outline [dict get $col panel] \
                    -width 2 -tags gad
            } else {
                $o create oval [expr {$cxp - $r}] [expr {$cyp - $r}] \
                    [expr {$cxp + $r}] [expr {$cyp + $r}] \
                    -fill [dict get $col text] -outline "" -tags gad
            }
            incr i
        }

        # y axis end labels, and the axis caption naming the series actually
        # fitted -- normalized time is not the same thing as shot time.
        _otext $o [expr {$px0 - 6}] $py0 ne [format %.0f $ymax] $fcap [dict get $col muted] 0 right
        _otext $o [expr {$px0 - 6}] $py1 se [format %.0f $ymin] $fcap [dict get $col muted] 0 right
        set ylab "shot time, s"
        if {[dict get $cm normalized]} { set ylab "time (normalized), s" }
        _otext $o $px0 [expr {$py1 + $gap}] nw $ylab $fcap [dict get $col muted] 0 left

        # ---- residual strip data, same x scale (axes and grid already drawn) ----
        _otext $o [expr {$px0 - 6}] $rmid e "0" $fcap [dict get $col muted] 0 right

        if {[llength $resid] > 0} {
            set rmax 0.0
            foreach rv $resid { if {abs($rv) > $rmax} { set rmax [expr {abs($rv)}] } }
            if {$rmax < 1e-6} { set rmax 1.0 }
            set rsy [expr {double($res_h) / 2.0 / ($rmax * 1.15)}]
            set i 0
            foreach p $pts rv $resid {
                lassign $p x yy
                set cxp [expr {$px0 + ($x - $xmin) * $sx}]
                set cyp [expr {$rmid - $rv * $rsy}]
                # Stem to zero: makes a one-sided (biased) pattern obvious.
                $o create line $cxp $rmid $cxp $cyp -fill [dict get $col muted] \
                    -width 1 -tags gad
                set fillc [dict get $col text]
                if {$i == 0} { set fillc [dict get $col info] }
                $o create oval [expr {$cxp - $r}] [expr {$cyp - $r}] \
                    [expr {$cxp + $r}] [expr {$cyp + $r}] \
                    -fill $fillc -outline "" -tags gad
                incr i
            }
            _otext $o [expr {$px0 - 6}] $ry0 ne "+[format %.1f $rmax]" $fcap [dict get $col muted] 0 right
        }

        _otext $o $px0 [expr {$ry1 + $tickh + 2 + $fcap + $gap}] nw \
            "residuals, s" $fcap [dict get $col muted] 0 left
        _otext $o $px1 [expr {$ry1 + $tickh + 2 + $fcap + $gap}] ne \
            "grind setting [format %c 0x2192]" $fcap [dict get $col muted] 0 right
    }

    proc _show_why_dialog {rec} {
        variable _glass_mat
        variable _colors_override
        lassign [_pgeom] parent W H o
        if {[catch {
            catch { destroy $o }
            # v3.16.0: same glass-or-opaque presentation as the popup
            # (v3.14.x) and the Curve (v3.15.0): the material's theme via
            # the draw-scoped override, the shared _present_card call
            # site, the opaque v3.13.x card on any glass failure.
            set glass [_glass_setup $W $H]
            set _colors_override ""
            if {$glass} { set _colors_override [dict get $_glass_mat theme] }
            set col [_colors]
            set F [_pfonts $H]
            set fsec  [dict get $F section]
            set fbody [dict get $F body]
            set fcap  [dict get $F caption]
            set fbtn  [dict get $F button]

            canvas $o -bg [dict get $col scrim] -highlightthickness 0 -bd 0 \
                -takefocus 0
            # v3.16.1: unplaced until the glass art is drawn (flash fix).
            if {!$glass} {
                place $o -in $parent -x 0 -y 0 -relwidth 1 -relheight 1
            }
            raise $o

            set cw [expr {int($W * 0.70)}]
            if {$cw > ($W - 120)} { set cw [expr {$W - 120}] }
            if {$cw < 320} { set cw [expr {$W - 24}] }
            set pad    [_clamp [expr {int($H * 0.055)}] 28 56]
            set inner  [expr {$cw - 2 * $pad}]
            set gap_sm [_clamp [expr {int($H * 0.012)}] 8 14]
            set gap_lg [_clamp [expr {int($H * 0.025)}] 14 26]
            set gap_xl [_clamp [expr {int($H * 0.040)}] 24 40]
            set btnh   [_clamp [expr {int($H * 0.085)}] 54 70]
            set radius [_clamp [expr {int($H * 0.02)}] 10 20]
            set row_pitch [expr {int($fbody * 175 / 100)}]
            set reason_lineh [expr {int($fbody * 135 / 100)}]

            set rows [list \
                "Method" [_forecast_method_label [_dget $rec method]] \
                "Bag shots (n)" "[_dget $rec n] eligible[_forecast_excluded_txt $rec]" \
                "Shot time" "[_fmt_num [dict get $rec actual]]s  (target [_fmt_num [dict get $rec target]]s)"]
            # v3.19.0: the score left the popup (it shows plain words now).
            if {[dict exists $rec confidence]} {
                # v3.19.1: the popup's word for the band, not GA's internal
                # Poor/Fair/Good/Excellent (confidence_band stays raw for Lumen).
                # v3.24.0 (F23): word first, the score after: "Medium (40%)".
                lappend rows "Confidence" [_conf_words [dict get $rec confidence] [_dget $rec confidence_band]]
            }
            if {[dict get $rec method] eq "regression"} {
                lappend rows "Learned slope" "[_fmt_num [dict get $rec m]] s/grind" \
                    "Model fit R\u00B2" [_forecast_r2_txt $rec] \
                    "Predicted time" "[_fmt_num [dict get $rec predicted_time]]s at [_fmt_num [dict get $rec next]]"
                # v3.18.0: one row, only when the target is out of reach.
                # v3.18.1: advice first, number last -- _fit_text clips the
                # END of a value, and at popup_font_scale 1.25+ it clipped
                # "change dose or yield" itself.
                if {[_reach_out $rec]} {
                    lappend rows "Grind reach" \
                        "change dose or yield (ideal [format %.1f [dict get $rec reach g_target]])"
                }
            } else {
                # v3.11.0: the ladder works in normalized time now. When that
                # differs from the clock, show the number the rung actually
                # used, or the Shot time row above makes the recommendation
                # look like it moved the wrong way.
                if {[_dget $rec normalized] == 1} {
                    set _tn ""
                    catch { set _tn [dict get [lindex [dict get $rec shots] 0] t_norm] }
                    if {$_tn ne ""} {
                        lappend rows "Normalized time" "[_fmt_num $_tn]s (what this rung used)"
                    }
                }
                lappend rows "Seconds per step" [_fmt_num [dict get $rec s_per_step]]
            }
            lappend rows "Rounded" "to [_fmt_num [dict get $rec rounding_increment]] \u2192 [_fmt_num [dict get $rec next]]" \
                "Grinder range" "[_fmt_num [dict get $rec grinder_min]] \u2013 [_fmt_num [dict get $rec grinder_max]]"
            set nrows [expr {[llength $rows] / 2}]

            set reason ""
            if {[dict exists $rec reason]} { set reason [dict get $rec reason] }
            set rlines [_text_lines $reason $fbody $inner]
            if {$rlines > 3} { set rlines 3 }

            set reason_h 0
            if {$reason ne ""} {
                set reason_h [expr {$gap_xl + $fcap + $gap_sm + $rlines * $reason_lineh}]
            }
            set fixed_h [expr {$pad + $fsec + $gap_lg + $reason_h + $gap_xl + $btnh + $pad}]
            # v3.18.1: the card is capped at H-40 and the buttons hang from
            # its bottom, so anything over the cap used to come out of the
            # gap above them -- at popup_font_scale 1.4+ the reason's last
            # line ran into Back / OK once the Grind reach row was added.
            # Take the overflow from the row pitch instead, never below one
            # reason line.
            set over [expr {$fixed_h + $nrows * $row_pitch - ($H - 40)}]
            if {$over > 0 && $nrows > 0} {
                set row_pitch [expr {max($reason_lineh, $row_pitch - int(ceil(double($over) / $nrows)))}]
            }
            set ch [expr {$fixed_h + $nrows * $row_pitch}]
            if {$ch > ($H - 40)} { set ch [expr {$H - 40}] }

            set x0 [expr {int(($W - $cw) / 2)}]
            set y0 [expr {int(($H - $ch) / 2)}]
            set x1 [expr {$x0 + $cw}]
            set y1 [expr {$y0 + $ch}]
            set cx [expr {int(($x0 + $x1) / 2)}]

            lassign [_present_card $o $parent glass $x0 $y0 $x1 $y1 $radius $col] \
                x0 y0 x1 y1 cx

            set y [expr {$y0 + $pad}]
            _otext $o $cx [expr {$y + $fsec / 2}] center "Why this recommendation" $fsec [dict get $col text] $inner center bold
            incr y [expr {$fsec + $gap_lg}]

            set lab_x [expr {$x0 + $pad}]
            set val_x [expr {$x0 + $pad + int($inner * 0.40)}]
            set val_w [expr {$x1 - $pad - $val_x}]
            foreach {lab val} $rows {
                set ly [expr {$y + $row_pitch / 2}]
                _otext $o $lab_x $ly w $lab $fbody [dict get $col muted] [expr {$val_x - $lab_x - 10}] left
                _otext $o $val_x $ly w [_fit_text $val $fbody $val_w] $fbody [dict get $col text] $val_w left
                incr y $row_pitch
            }
            if {$reason ne ""} {
                incr y $gap_xl
                _otext $o $lab_x [expr {$y + $fcap / 2}] w "Reason" $fcap [dict get $col muted] $inner left
                incr y [expr {$fcap + $gap_sm}]
                _otext $o $lab_x $y nw $reason $fbody [dict get $col text] $inner left
            }

            set bgap [_clamp [expr {int($cw * 0.05)}] 24 56]
            set btnw [expr {int(($cw - 2 * $pad - $bgap) / 2)}]
            set bty2 [expr {$y1 - $pad}]
            set bty1 [expr {$bty2 - $btnh}]
            set bx0 [expr {$x0 + $pad}]
            _obutton $o $bx0 $bty1 [expr {$bx0 + $btnw}] $bty2 "Back" $fbtn \
                [list ::plugins::GrindAdvisor::_reshow_popup]
            set bx0 [expr {$bx0 + $btnw + $bgap}]
            _obutton $o $bx0 $bty1 [expr {$bx0 + $btnw}] $bty2 "OK" $fbtn \
                [list ::plugins::GrindAdvisor::_close_dialog]

            after 200  [list catch [list raise $o]]
            after 600  [list catch [list raise $o]]
        } err]} {
            catch { destroy $o }
            catch { msg "GrindAdvisor: why dialog failed: $err" }
            set _colors_override ""
            return 0
        }
        # Draw-scoped, exactly like _show_overlay_dialog (v3.14.5).
        set _colors_override ""
        return 1
    }

    proc _clamp {v lo hi} {
        if {$v < $lo} { return $lo }
        if {$v > $hi} { return $hi }
        return $v
    }

    proc _font {size {weight normal}} {
        # Negative sizes in Tk are pixels. This is much more predictable on
        # Android/AndroWish than positive point sizes, which were causing the
        # popup to look enormous on 1340x800 tablets.
        set px [expr {int(abs($size))}]
        if {$px < 8} { set px 8 }
        return [list Helvetica [expr {-$px}] $weight]
    }

    proc _otext {o x y anchor text size fill wrap {justify center} {weight normal}} {
        if {[catch {
            $o create text $x $y -text $text -anchor $anchor -justify $justify \
                -fill $fill -width $wrap -font [_font $size $weight] -tags gad
        }]} {
            $o create text $x $y -text $text -anchor $anchor -justify $justify \
                -fill $fill -width $wrap -tags gad
        }
    }

    # v3.16.6: enabled 0 draws the palette's disabled look (btnoff fill,
    # btnofftext label) and binds no tap -- the pager's unavailable end,
    # the same "disabled, never hidden" rule the dui pages follow.
    proc _obutton {o x0 y0 x1 y1 label size cmd {enabled 1}} {
        variable _btnseq
        set col [_colors]
        set tag "gad_btn_[incr _btnseq]"
        set r [_clamp [expr {int(($y1 - $y0) * 0.22)}] 8 18]
        if {$enabled} {
            set fill [dict get $col btn]
            set edge [dict get $col btnborder]
            set ink  [dict get $col btntext]
        } else {
            set fill [dict get $col btnoff]
            set edge $fill
            set ink  [dict get $col btnofftext]
        }
        # v3.22.0 (F9): the shape alone carries ${tag}_face (the label shares
        # $tag), so a press tints the face and never the text.
        if {[catch {
            _opoly $o $x0 $y0 $x1 $y1 $r $fill $edge [list gad $tag ${tag}_face]
        }]} {
            $o create rectangle $x0 $y0 $x1 $y1 -fill $fill \
                -outline $edge -width 1 -tags [list gad $tag ${tag}_face]
        }
        if {[catch {
            $o create text [expr {($x0 + $x1) / 2}] [expr {($y0 + $y1) / 2}] \
                -text $label -anchor center -fill $ink \
                -font [_font $size bold] -tags [list gad $tag]
        }]} {
            $o create text [expr {($x0 + $x1) / 2}] [expr {($y0 + $y1) / 2}] \
                -text $label -anchor center -fill $ink \
                -tags [list gad $tag]
        }
        # v3.22.0 (F9): tint on touch-down (painted at once), act on release
        # as before. The tones are captured here: the glass/opaque choice is
        # draw-scoped (_colors_override is cleared after each draw).
        if {$enabled} {
            $o bind $tag <ButtonPress-1> [list ::plugins::GrindAdvisor::_obutton_press $o ${tag}_face \
                [dict get $col btnpress] $fill $edge]
            $o bind $tag <ButtonRelease-1> [list ::plugins::GrindAdvisor::_obutton_release $o ${tag}_face \
                $fill $edge $cmd]
        }
    }

    # The outline takes the tone too where it normally matches the fill (the
    # opaque families: one solid shape, like a pressed page button); the
    # glass families keep their deliberate border (review). A safety
    # restore after 2 s covers a touch Android cancels without a release
    # (the face would otherwise stay tinted until the next redraw).
    proc _obutton_press {o face tone fill edge} {
        if {$edge eq $fill} {
            $o itemconfigure $face -fill $tone -outline $tone
        } else {
            $o itemconfigure $face -fill $tone
        }
        update idletasks
        after 2000 [list ::plugins::GrindAdvisor::_obutton_unpress $o $face $fill $edge]
    }

    proc _obutton_unpress {o face fill edge} {
        if {[winfo exists $o] && [llength [$o find withtag $face]] > 0} {
            $o itemconfigure $face -fill $fill -outline $edge
        }
    }

    # The face goes back to its resting fill, then the action runs. Most
    # actions destroy or redraw the overlay, so the restore comes first and
    # only touches the face if the canvas still exists.
    proc _obutton_release {o face fill edge cmd} {
        _obutton_unpress $o $face $fill $edge
        uplevel #0 $cmd
    }

    # Color scheme for the popup. Dark by default to match dark skins; set
    # ::plugins::GrindAdvisor::settings(popup_theme) to "light" for a light one.
    # One layout, two color sets (v2.0.0 added the "muted" secondary text
    # color; everything else unchanged).
    #
    # v3.14.0: optional theme override. The glass popup must follow the
    # MATERIAL's theme (light text on a dark slab and vice versa), so a
    # glass draw passes the skin's theme here; the Popup theme setting
    # keeps governing the opaque popup and every other overlay.
    #
    # v3.14.5: the override is also a DRAW-SCOPED variable, because
    # helpers like _obutton call _colors themselves -- on the tablet the
    # light-material popup rendered dark buttons (owner screenshot,
    # light theme). _show_overlay_dialog sets _colors_override for the
    # duration of a glass draw and clears it before returning (and
    # _close_dialog clears it again, belt and braces), so every helper
    # in that draw agrees on the material's palette. The popup, Curve
    # and Why? glass this way; History and every opaque fallback keep
    # following popup_theme (v3.16.2).
    #
    # v3.16.6: two palette families. GLASS draws (override = the
    # material's theme) keep the v3.14 material palettes byte for byte.
    # OPAQUE draws (no override: History, Bag Stats, the opaque popup,
    # Curve/Why without glass) follow popup_theme with the SHARED PLUGIN
    # PAGE palette -- _apply_palette's values, the ones ShotHistoryEditor,
    # MaintenanceTracker and BeanScanner paint -- instead of the old black
    # #000000 scrim and iOS greys (owner 2026-09-30: "should be the same
    # dark as all the plugins"). New keys: body (secondary card line,
    # text_body) and btnoff/btnofftext (a disabled pager button).
    #
    # v3.16.7 contrast pass: the OPAQUE palettes follow _apply_palette's
    # new values -- light btntext #2b2b2b (white on the periwinkle was
    # 1.7:1) and muted #595959, dark muted #9aa0ad. The GLASS palettes
    # are untouched.
    # v3.22.0 (F9): btnpress, an enabled button's face while a finger is
    # on it (opaque = the pages' btn_press_fill; glass light #D1D1D6 keeps
    # #222222 at 10.5:1, glass dark #48484A keeps #ECECEC at 7.7:1).
    variable _colors_override ""

    proc _colors {{override ""}} {
        variable _colors_override
        if {$override eq ""} { set override $_colors_override }
        # v3.19.0 (F15): status colours only on warnings and the confidence
        # dot, never the hero. v3.23.0 (F21): every family takes the shared
        # roles from _status_roles -- ok (was `good`: #0B6E4F / #34C759),
        # warn (dark #E8B34C everywhere; opaque dark was #e0a860), danger,
        # and info (was `accent`, the Curve's green: a neutral plot no
        # longer reads as "OK"). Text >= 4.5:1 on the panel, the scrim and
        # Lumen's baked glass (worst: light ok 4.75 on the #d5d6e3 scrim,
        # light ok 4.94 on the #D8DBE1 glass); glass art is baked, so
        # check its screenshot.
        if {$override eq "light"} {
            return [dict merge [dict create \
                scrim "#F2F3F5" panel "#FFFFFF" border "#CCCCCC" \
                text "#222222" body "#222222" muted "#6a6a6a" \
                btn "#EFEFEF" btnborder "#999999" btntext "#222222" \
                btnoff "#EFEFEF" btnofftext "#999999" btnpress "#D1D1D6"] \
                [_status_roles 0]]
        }
        if {$override eq "dark"} {
            return [dict merge [dict create \
                scrim "#000000" panel "#1C1C1E" border "#3A3A3C" \
                text "#ECECEC" body "#ECECEC" muted "#A0A0A6" \
                btn "#2C2C2E" btnborder "#48484A" btntext "#ECECEC" \
                btnoff "#2C2C2E" btnofftext "#6A6A6E" btnpress "#48484A"] \
                [_status_roles 1]]
        }
        if {[_setting popup_theme dark] eq "light"} {
            return [dict merge [dict create \
                scrim "#d5d6e3" panel "#FFFFFF" border "#dcdcdc" \
                text "#2b2b2b" body "#444444" muted "#595959" \
                btn "#c0c5e3" btnborder "#c0c5e3" btntext "#2b2b2b" \
                btnoff "#dddddd" btnofftext "#999999" btnpress "#a6acd1"] \
                [_status_roles 0]]
        }
        return [dict merge [dict create \
            scrim "#23252e" panel "#32353f" border "#464b58" \
            text "#e8e9ee" body "#c2c5cf" muted "#9aa0ad" \
            btn "#4a5473" btnborder "#4a5473" btntext "#ffffff" \
            btnoff "#3a3e4a" btnofftext "#999999" btnpress "#5f6a8c"] \
            [_status_roles 1]]
    }

    proc _close_dialog {} {
        variable popup_active
        variable _colors_override
        set _colors_override ""
        # Release the glass grab first (v3.14.1); destroying the overlay
        # would release it too (Tk drops a destroyed window's grab), this
        # is belt and braces.
        catch { _glass_ungrab }
        # Destroy the overlay widget wherever it was parented.
        catch { destroy .grindadvisor_overlay }
        set sc [_get_canvas]
        if {$sc ne ""} {
            set parent [winfo parent $sc]
            if {$parent ne "."} { catch { destroy "$parent.grindadvisor_overlay" } }
            catch { $sc delete grindadvisor_dialog }
        }
        catch { destroy .grindadvisor }
        # Drop the glass photos (v3.14.0) AFTER the widgets that showed
        # them are gone -- they are the only thing an overlay leaves
        # behind.
        catch { _glass_cleanup }
        set popup_active 0
    }

    proc _history_and_close {} {
        # Safe history: do NOT navigate to the skin's history page. Some skins
        # accept a guessed page name but show a blank white screen. Instead,
        # show a small read-only recent-shot list using the same overlay.
        _show_history_dialog
    }

    # ------------------------------------------------------------------
    #  v3.23.0 (design review F21): one date and one count language across
    #  the owner's plugins and Lumen. Copied verbatim from the shared spec;
    #  they replace _format_clock ("2026-09-29 21:29", always 24 h) and
    #  _bag_date_short ("29 Sep"), and the "Shots 1-5 of 25" / "Page 1 / 3"
    #  strings. SDB's shot clock is an INTEGER epoch; anything else reads as
    #  no date.
    # ------------------------------------------------------------------
    # F21 (shared): dates follow Lumen's clock settings when Lumen is the skin, else the
    # core's enable_ampm; day first unless Lumen says mdy. Text is picked with if, never expr ?:.
    proc _clock_24h {} {
        if {[llength [info commands ::lumen::time_format]]} {
            if {[::lumen::time_format] == 12} { return 0 }
            return 1
        }
        if {[info exists ::settings(enable_ampm)] && $::settings(enable_ampm) == 1} { return 0 }
        return 1
    }
    proc _clock_mdy {} {
        if {[llength [info commands ::lumen::date_format]] && [::lumen::date_format] eq "mdy"} { return 1 }
        return 0
    }
    # Same day/time strings as Lumen's own taskbar (zero-padded day and 12 h hour), so a
    # plugin date and Lumen read identically: "Fri 02 Oct 21:29", "Fri Oct 02 09:29 PM".
    # " 2025" is added when the date is not in the current year.
    proc _fmt_when {ts} {
        if {![string is wide -strict $ts] || $ts <= 0} { return {} }
        if {[_clock_mdy]} { set f {%a %b %d} } else { set f {%a %d %b} }
        if {[clock format $ts -format %Y] ne [clock format [clock seconds] -format %Y]} { append f { %Y} }
        if {[_clock_24h]} { append f { %H:%M} } else { append f { %I:%M %p} }
        return [clock format $ts -format $f]
    }
    # Date only, for ranges and tight columns: "29 Sep" / "Sep 29" (+ " 2025" if not this year).
    proc _fmt_day {ts} {
        if {![string is wide -strict $ts] || $ts <= 0} { return {} }
        if {[_clock_mdy]} { set f {%b %d} } else { set f {%d %b} }
        if {[clock format $ts -format %Y] ne [clock format [clock seconds] -format %Y]} { append f { %Y} }
        return [clock format $ts -format $f]
    }
    # Time only (e.g. "comes back at 21:39" / "09:39 PM"): same 12/24 h rule.
    proc _fmt_time {ts} {
        if {![string is wide -strict $ts] || $ts <= 0} { return {} }
        if {[_clock_24h]} { return [clock format $ts -format %H:%M] }
        return [clock format $ts -format {%I:%M %p}]
    }

    # MaintenanceTracker's _fmt_ago, verbatim (the shared relative caption).
    # v0.20.0: human relative time -- minutes up to 59, hours up to 23,
    # then days (owner request; "0 days ago" told you nothing on the day
    # you actually did the task). Singular/plural spelled out; a clock
    # skew into the future reads as "just now".
    proc _fmt_ago {ts} {
        if {![string is wide -strict $ts] || $ts <= 0} { return "" }
        set secs [expr {[clock seconds] - $ts}]
        if {$secs < 60} { return [translate "just now"] }
        set mins [expr {$secs / 60}]
        if {$mins < 60} {
            if {$mins == 1} { return "1 [translate {minute ago}]" }
            return "$mins [translate {minutes ago}]"
        }
        set hours [expr {$secs / 3600}]
        if {$hours < 24} {
            if {$hours == 1} { return "1 [translate {hour ago}]" }
            return "$hours [translate {hours ago}]"
        }
        set days [expr {$secs / 86400}]
        if {$days == 1} { return "1 [translate {day ago}]" }
        return "$days [translate {days ago}]"
    }

    # F21 counts: one pattern per list type (shared spec, verbatim).
    proc _plural {n one {many ""}} {
        if {$many eq ""} { set many "${one}s" }
        if {$n == 1} { return "$n $one" }
        return "$n $many"
    }
    # Card lists: "1-5 of 188 shots" (en dash); "No shots" when empty.
    proc _range_count {first last total one {many ""}} {
        if {$many eq ""} { set many "${one}s" }
        if {$total <= 0} { return "No $many" }
        set word $many
        if {$total == 1} { set word $one }
        return "$first[format %c 0x2013]$last of $total $word"
    }
    # Paged text, grids, menus: "Page 1 of 4" ("" for one page).
    proc _page_count {idx total} {
        if {$total <= 1} { return "" }
        return "Page [expr {$idx + 1}] of $total"
    }

    proc _fmt1 {value suffix} {
        if {$value eq ""} { return "" }
        return "[format %.1f $value]$suffix"
    }

    proc _fmt_num {value} {
        if {$value eq ""} { return "" }
        set out [format %.3f $value]
        set out [string trimright $out 0]
        set out [string trimright $out .]
        if {$out eq "-0"} { set out "0" }
        return $out
    }

    # ------------------------------------------------------------------
    #  v2.0.0 history card list. Same data pipeline as before (read-only
    #  SDB fetch -> valid-espresso filter -> per-shot recommendation).
    #  v3.20.0 (F16): one card dict per shot for _draw_card:
    #    big / cap: the recommended grind, large on the right, the move
    #    l1 (primary): the grind used + the time against the target
    #    l2 (body): date/time, dose, ratio, yields
    #    l3 (caption): bag name, "shot N on this bag", the confidence word
    #       (or "first shot on this bag") -- never the shot time
    #    warn (amber): out of reach, then channeling; warn_short when both
    #  honoring the user's history_show_* display options.
    # ------------------------------------------------------------------
    variable _hist_offset 0
    variable _hist_cards {}

    proc _history_cards {{max_shots 25}} {
        variable GA_ON_TARGET_TOL
        lassign [locate_shot_source] db table fields
        if {$db eq "" || $table eq ""} { return [list] }
        set rows [_fetch_recent $db $table $fields [expr {$max_shots + 35}]]
        set rows [_filter_valid_rows $rows $fields]
        set cards {}
        set nrows [llength $rows]
        for {set pos 0} {$pos < $nrows && [llength $cards] < $max_shots} {incr pos} {
            set r [lindex $rows $pos]
            set g [_to_float [_dget $r grind]]
            set t [_duration_seconds [_dget $r duration]]
            if {$g eq "" || $t eq ""} { continue }
            set d [_to_float [_dget $r dose]]
            set set_y [_to_float [_dget $r set_yield]]
            set actual_y [_to_float [_dget $r actual_yield]]

            set current [_shot_from_row $r]
            set rec [_forecast_rec $rows $fields $pos]
            set bag_shot [_bag_shot_count $current $rows $pos]
            if {$bag_shot ne ""} { dict set rec bag_shot $bag_shot }
            set warning [_channel_warning $current $rows [expr {$pos + 1}]]
            if {$warning ne ""} { dict set rec channel_warning $warning }
            # The confidence that shot's popup showed (as _decorate_rec,
            # display only): the plain reason in l3, read only when shown.
            if {[_setting history_show_reason 1]} {
                set conf [_calibration_confidence [lrange $rows $pos end]]
                if {[dict get $conf ok]} { dict set rec confidence_band [dict get $conf band] }
            }

            # v3.20.0 (design review F16, plain words): the recommended grind
            # LARGE on the right with the move under it; the left column
            # leads with what happened -- the grind and the time against the
            # target -- then the recipe, then the bag. Each part still obeys
            # its history_show_* option (History Display Options).
            set P [_plain_words $rec]
            set sep "  [format %c 0xB7]  "
            set card [dict create]
            # Every valid row forecasts (first_shot at least); a rec without
            # `next` only loses its big number, never the whole list.
            if {[_setting history_show_recommended_grind 1] && [_dget $rec next] ne ""} {
                dict set card big [_grind_fmt [dict get $rec next]]
                dict set card cap [dict get $P move]
            }

            set l1 {}
            if {[_setting history_show_set_grind 1]} { lappend l1 "Grind [_grind_fmt $g]" }
            if {[_setting history_show_shot_time 1]} {
                # The time the engine judged (review): the yield-adjusted one
                # when normalization moved it 0.5 s+, labelled as the popup
                # labels it, so "fast" never sits next to "coarser by".
                set tu $t
                set adj 0
                if {[dict get $P used] ne ""} {
                    set tu [dict get $P used]
                    set adj [dict get $P adj]
                }
                set tgt [_dget $rec target]
                if {$tgt eq ""} { set tgt [_setting target_time 28.0] }
                # Judged at the 0.1 s it is printed at, so "30 s ... (2 s
                # slow)" never sits beside a "30 s (on target)".
                set err [expr {round(($tgt - $tu) * 10) / 10.0}]
                if {abs($err) <= $GA_ON_TARGET_TOL} {
                    set how "on target"
                } elseif {$err > 0} {
                    set how "[_num1 $err] s fast"
                } else {
                    set how "[_num1 [expr {-$err}]] s slow"
                }
                if {$adj} {
                    lappend l1 "[_num1 $tu] s yield-adjusted ($how)"
                } else {
                    lappend l1 "[_num1 $tu] s ($how)"
                }
            }
            dict set card l1 [join $l1 $sep]

            set l2 {}
            if {[_setting history_show_datetime 1]} {
                # v3.23.0 (F21): "Mon 29 Sep 21:29" / "Mon Sep 29 09:29 PM"
                # (Lumen's clock settings) leads l2; "4 days ago" is the
                # caption in the l1 row's date column, which ends on one
                # column for the page (datebw, as Bag Stats).
                set ts [string trim [_dget $r timestamp]]
                set dt [_fmt_when $ts]
                if {$dt ne ""} {
                    lappend l2 $dt
                    dict set card date [_fmt_ago $ts]
                }
            }
            if {[_setting history_show_set_dose 1] && $d ne ""} { lappend l2 "[_num1 $d] g in" }
            if {[_setting history_show_set_ratio 1] && $d ne "" && $set_y ne "" && $d > 0} {
                lappend l2 [format "1:%.1f" [expr {$set_y / double($d)}]]
            }
            if {[_setting history_show_set_yield 1] && $set_y ne ""} { lappend l2 "[_num1 $set_y] g target" }
            if {[_setting history_show_actual_yield 0] && $actual_y ne ""} { lappend l2 "[_num1 $actual_y] g out" }
            dict set card l2 [join $l2 $sep]

            # F16: "the bean on line 3" -- shots of two bags must not run
            # together -- so the bag leads, then its shot number, then the
            # reason in plain words: how sure the recommendation was (the
            # time is l1's, under its own Shot Time option; the move is
            # under the big number; the technical reason lives under Why?).
            set l3 {}
            if {[_setting history_show_bag_name 1]} {
                set bl [_bag_label $r]
                if {$bl ne ""} { lappend l3 $bl }
            }
            set bs_shown 0
            if {[_setting history_show_bag_shot 1] && [dict exists $rec bag_shot]} {
                lappend l3 "shot [dict get $rec bag_shot] on this bag"
                set bs_shown 1
            }
            if {[_setting history_show_reason 1]} {
                set bw [_band_plain [dict get $P band]]
                if {$bw ne ""} {
                    lappend l3 "$bw confidence"
                } elseif {[_dget $rec n] eq "1" && !$bs_shown} {
                    # "shot 1 on this bag" already says it when shown.
                    lappend l3 "first shot on this bag"
                }
            }
            dict set card l3 [join $l3 $sep]
            # Warnings in amber, as the popup shows them: the bag's dead end
            # (out of reach, the actionable one) first, then the shot's own
            # (channeling). Both together outgrow a shared row, so the card
            # also carries a short form _draw_card uses when it must.
            set sign [format %c 0x26A0]
            set reach ""
            if {[_reach_out $rec]} {
                set reach "[_num1 [dict get $rec target]] s is out of reach by grind: change dose or yield"
            }
            set chan [dict get $P warning]
            set warns {}
            foreach w [list $reach $chan] { if {$w ne ""} { lappend warns $w } }
            if {[llength $warns] > 0} {
                dict set card warn "$sign [join $warns $sep]"
            }
            if {$reach ne "" && $chan ne ""} {
                dict set card warn_short "$sign $reach${sep}check puck prep"
            }
            lappend cards $card
        }
        return $cards
    }

    # v3.20.0 (design review F16): one card of the History / Bag Stats
    # lists, drawn the same way for both. The number you came for is LARGE
    # and right-aligned (`big`, title size -- or primary size for a word,
    # `bigsize word` -- in `bigrole`'s colour, `cap` under it); the left
    # column keeps the three baselines (l1 bold, l2 body, l3 caption with
    # `warn` appended in amber; stacked, so an empty line leaves no hole),
    # clipped an xl gap short of that block;
    # `date` sits right-aligned in the l1 row, left of the block. Card keys
    # are all optional. Physical px, like every overlay.
    proc _draw_card {o lx rx top pf F col card} {
        set fprim [dict get $F primary]
        set fbody [dict get $F body]
        set fcap  [dict get $F caption]
        set card_h [expr {int(96 * $pf)}]
        set pad_x  [expr {int(18 * $pf)}]
        set xl     [expr {int(32 * $pf)}]
        set lg     [expr {int(24 * $pf)}]
        set seam   3
        _opoly $o $lx $top $rx [expr {$top + $card_h}] [expr {int(12 * $pf)}] \
            [dict get $col panel] [dict get $col border] gad
        set left  [expr {$lx + $pad_x}]
        set right [expr {$rx - $pad_x}]

        lassign [_card_block $card $F [_card_maxbw $lx $rx $pf]] bw big cap bsize
        set role [_dget $card bigrole]
        if {$role eq ""} { set role text }
        if {$big ne ""} {
            _otext $o $right [expr {$top + int(40 * $pf)}] e $big $bsize [dict get $col $role] [expr {$bw + 4}] right bold
        }
        if {$cap ne ""} {
            _otext $o $right [expr {$top + int(80 * $pf)}] e $cap $fcap [dict get $col muted] [expr {$bw + 4}] right
        }
        set text_r [expr {$bw > 0 ? $right - $bw - $xl : $right}]
        set text_w [expr {$text_r - $left}]

        # The left lines stack on the three baselines with no hole: a line
        # whose options are all off (the owner's History has date, dose,
        # ratio and yield off, so l2 is empty) lets the next one move up.
        # Text is picked with if, never `expr ?:` (it rewrites "0715").
        set ys [list [expr {$top + int(30 * $pf)}] [expr {$top + int(56 * $pf)}] [expr {$top + int(80 * $pf)}]]
        set k 0
        set l1 [_dget $card l1]
        set date [_dget $card date]
        if {$l1 ne "" || $date ne ""} {
            set y [lindex $ys $k]
            set l1w $text_w
            if {$date ne ""} {
                # v3.21.0: `datebw` (Bag Stats) is the widest right block
                # on the page, so every date ends on one column (they moved
                # ~70 px between "Out of reach" and number cards).
                set date_r $text_r
                set dbw [_dget $card datebw]
                if {[string is double -strict $dbw] && $dbw > $bw} {
                    set date_r [expr {$right - $dbw - $xl}]
                }
                set dw [font measure [_font $fcap] $date]
                _otext $o $date_r $y e $date $fcap [dict get $col muted] [expr {$dw + 4}] right
                set l1w [expr {$date_r - $dw - $lg - $left}]
            }
            if {$l1 ne ""} {
                _otext $o $left $y w [_fit_text $l1 $fprim $l1w bold] $fprim [dict get $col text] $l1w left bold
            }
            incr k
        }
        set l2 [_dget $card l2]
        if {$l2 ne ""} {
            _otext $o $left [lindex $ys $k] w [_fit_text $l2 $fbody $text_w] $fbody [dict get $col body] $text_w left
            incr k
        }
        # The caption (l3, muted) and the warning (amber). A warning takes
        # its own full-width row when one is free below the caption (the
        # owner's History: l2 off), or the caption's row when there is no
        # caption. Otherwise they share the last row: the warning is
        # budgeted FIRST (up to 60%) and l3 gets what is left, so a long
        # caption never pushes a warning off; it follows l3 an lg gap (+ the
        # bbox seam) on. `warn_short` stands in when `warn` would be cut.
        set fc [_font $fcap]
        set l3 [_dget $card l3]
        set warn [_dget $card warn]
        set wshort [_dget $card warn_short]
        if {$warn eq ""} {
            if {$l3 ne ""} {
                _otext $o $left [lindex $ys $k] w [_fit_text $l3 $fcap $text_w] $fcap [dict get $col muted] $text_w left
            }
            return
        }
        if {$l3 eq "" || $k < 2} {
            if {$l3 ne ""} {
                _otext $o $left [lindex $ys $k] w [_fit_text $l3 $fcap $text_w] $fcap [dict get $col muted] $text_w left
                incr k
            }
            if {$wshort ne "" && [font measure $fc $warn] > $text_w} { set warn $wshort }
            _otext $o $left [lindex $ys $k] w [_fit_text $warn $fcap $text_w] $fcap [dict get $col warn] $text_w left
            return
        }
        set y [lindex $ys $k]
        set wmax [expr {int($text_w * 0.60)}]
        if {$wshort ne "" && [font measure $fc $warn] > $wmax} { set warn $wshort }
        set warn [_fit_text $warn $fcap $wmax]
        set l3w [expr {$text_w - [font measure $fc $warn] - $lg - $seam}]
        set l3t ""
        if {$l3w > 40} { set l3t [_fit_text $l3 $fcap $l3w] }
        set used 0
        if {$l3t ne ""} {
            _otext $o $left $y w $l3t $fcap [dict get $col muted] $l3w left
            set used [expr {[font measure $fc $l3t] + $lg + $seam}]
        }
        _otext $o [expr {$left + $used}] $y w $warn $fcap [dict get $col warn] [expr {$text_w - $used}] left
    }

    # The right block's widest line and its fitted texts: {bw big cap bsize}.
    # One measure for _draw_card and for Bag Stats' date column (datebw).
    proc _card_block {card F maxbw} {
        set fcap [dict get $F caption]
        set bsize [dict get $F title]
        if {[_dget $card bigsize] eq "word"} { set bsize [dict get $F primary] }
        set big [_dget $card big]
        set cap [_dget $card cap]
        set bw 0
        if {$big ne ""} {
            set big [_fit_text $big $bsize $maxbw bold]
            set bw [font measure [_font $bsize bold] $big]
        }
        if {$cap ne ""} {
            set cap [_fit_text $cap $fcap $maxbw]
            set bw [expr {max($bw, [font measure [_font $fcap] $cap])}]
        }
        return [list $bw $big $cap $bsize]
    }

    # The right block's cap: 40% of the card's inner width.
    proc _card_maxbw {lx rx pf} {
        set pad_x [expr {int(18 * $pf)}]
        return [expr {int((($rx - $pad_x) - ($lx + $pad_x)) * 0.40)}]
    }

    # One page of a card list (History, Bag Stats): up to five cards from
    # the list top. v3.21.0: the date column ends on one column, left of the
    # page's widest right block (datebw), not each card's own; v3.23.0 (F21)
    # moved it here so History's "4 days ago" lines up the same way.
    proc _draw_card_page {o lx rx pf F col cards} {
        set list_top [expr {int(168 * $pf)}]
        set card_h [expr {int(96 * $pf)}]
        set card_gap [expr {int(12 * $pf)}]
        set maxbw [_card_maxbw $lx $rx $pf]
        set dbw 0
        foreach c $cards { set dbw [expr {max($dbw, [lindex [_card_block $c $F $maxbw] 0])}] }
        set i 0
        foreach c $cards {
            set top [expr {$list_top + $i * ($card_h + $card_gap)}]
            dict set c datebw $dbw
            _draw_card $o $lx $rx $top $pf $F $col $c
            incr i
        }
    }

    # The card's words in reading order, for tests and logs.
    proc _card_text {card} {
        set out {}
        foreach k {l1 date l2 l3 warn big cap} {
            if {[_dget $card $k] ne ""} { lappend out [_dget $card $k] }
        }
        return [join $out " | "]
    }

    # v3.16.6: page chrome for the full-page card-list overlays (History,
    # Bag Stats), so they read as plugin pages: the GA page header (title
    # 40 bold at y 28, caption subtitle at y 72), Done bottom-left, and the
    # cross-plugin pager bottom-right -- Next's right edge on the right
    # margin, Prev an sm gap to its left, both always drawn, the
    # unavailable end disabled. Physical px: vertical ref px scale by H/800;
    # the bar's x edges come from the dui pages' own virtual tokens
    # (left_x, right_x, btn_w_std, sm) mapped by W/2560, so these buttons
    # land on exactly the pixels of the Help page's Done / Prev / Next.
    proc _overlay_chrome {o W H col title subtitle has_prev has_next prev_cmd next_cmd} {
        variable L
        set F [_pfonts $H 1.0]
        set ftitle [dict get $F title]
        set fcap   [dict get $F caption]
        set fbtn   [dict get $F button]
        set pf [expr {double($H) / 800.0}]
        set mg [expr {int(max($W * 0.036, 32))}]
        set lx $mg
        set rx [expr {$W - $mg}]
        set cx [expr {($lx + $rx) / 2}]
        set content_w [expr {$rx - $lx}]

        _otext $o $cx [expr {int(28 * $pf)}] center $title $ftitle [dict get $col text] $content_w center bold
        if {$subtitle ne ""} {
            _otext $o $cx [expr {int(72 * $pf)}] center [_fit_text $subtitle $fcap $content_w] \
                $fcap [dict get $col muted] $content_w center
        }

        set bar_y0 [expr {int(716 * $pf)}]
        set bar_y1 [expr {int(776 * $pf)}]
        # Virtual tokens (defaults = the 2560x1600 values if layout init
        # has not run), then virtual -> physical.
        set vl 92; set vr 2468; set vw 400; set vg 20
        if {[info exists L(btn_w_std)] && [info exists L(sm)] && [info exists L(right_x)]} {
            set vl $L(left_x); set vr $L(right_x); set vw $L(btn_w_std); set vg $L(sm)
        }
        set hx [expr {double($W) / 2560.0}]
        set done_x0 [expr {int(round($vl * $hx))}]
        set done_x1 [expr {int(round(($vl + $vw) * $hx))}]
        set prev_x0 [expr {int(round(($vr - 2 * $vw - $vg) * $hx))}]
        set prev_x1 [expr {int(round(($vr - $vw - $vg) * $hx))}]
        set next_x0 [expr {int(round(($vr - $vw) * $hx))}]
        set next_x1 [expr {int(round($vr * $hx))}]
        _obutton $o $done_x0 $bar_y0 $done_x1 $bar_y1 "Done" $fbtn \
            [list ::plugins::GrindAdvisor::_close_dialog]
        _obutton $o $prev_x0 $bar_y0 $prev_x1 $bar_y1 \
            "[format %c 0x25C0] Prev" $fbtn $prev_cmd $has_prev
        _obutton $o $next_x0 $bar_y0 $next_x1 $bar_y1 \
            "Next [format %c 0x25B6]" $fbtn $next_cmd $has_next
    }

    proc _show_history_dialog {} {
        variable _hist_offset
        variable _hist_cards
        set _hist_offset 0
        set _hist_cards [_history_cards]
        return [_render_history_dialog]
    }

    proc _hist_page {delta} {
        variable _hist_offset
        variable _hist_cards
        set total [llength $_hist_cards]
        set new [expr {$_hist_offset + 5 * $delta}]
        if {$new < 0} { set new 0 }
        if {$new >= $total || $new == $_hist_offset} { return }
        set _hist_offset $new
        _render_history_dialog
    }

    proc _render_history_dialog {} {
        variable _hist_offset
        variable _hist_cards
        lassign [_pgeom] parent W H o
        if {[catch {
            catch { destroy $o }
            # v3.16.2: History is deliberately OPAQUE (owner decision,
            # 2026-09-03, reverting v3.16.0's glass here): the card
            # dialogs keep their material glass, but this full-page list
            # stays on the flat popup_theme scrim.
            set col [_colors]
            set F [_pfonts $H 1.0]
            set fsec  [dict get $F section]
            set fprim [dict get $F primary]
            set fbody [dict get $F body]
            set fcap  [dict get $F caption]
            set fbtn  [dict get $F button]

            canvas $o -bg [dict get $col scrim] -highlightthickness 0 -bd 0 -takefocus 0
            place $o -in $parent -x 0 -y 0 -relwidth 1 -relheight 1
            raise $o

            # Standard page geometry mapped to physical pixels (reference
            # height 800): header, toolbar, 5 cards, bottom bar.
            set pf [expr {double($H) / 800.0}]
            set mg [expr {int(max($W * 0.036, 32))}]
            set lx $mg
            set rx [expr {$W - $mg}]
            set cx [expr {($lx + $rx) / 2}]
            set content_w [expr {$rx - $lx}]

            set total [llength $_hist_cards]
            # v3.16.6: GA page header, Done bottom-left and the standard
            # pager bottom-right (was a 24 px title and a top-right,
            # always-enabled Prev/Next pair).
            _overlay_chrome $o $W $H $col "Recent shot history" "Newest first. Espresso shots only." \
                [expr {$_hist_offset > 0}] [expr {$_hist_offset + 5 < $total}] \
                [list ::plugins::GrindAdvisor::_hist_page -1] \
                [list ::plugins::GrindAdvisor::_hist_page 1]

            set tb0 [expr {int(104 * $pf)}]
            set tb1 [expr {int(152 * $pf)}]
            # v3.23.0 (F21): "1-5 of 25 shots" (en dash) / "No shots", the
            # card-list count every owner plugin uses.
            set last [expr {$_hist_offset + 5}]
            if {$last > $total} { set last $total }
            set count_text [_range_count [expr {$_hist_offset + 1}] $last $total shot]
            _otext $o $lx [expr {($tb0 + $tb1) / 2}] w [_fit_text $count_text $fcap $content_w] \
                $fcap [dict get $col muted] $content_w left

            set list_top [expr {int(168 * $pf)}]
            set card_h [expr {int(96 * $pf)}]
            set card_gap [expr {int(12 * $pf)}]

            # v3.20.0 (F16): the shared card -- next grind large on the right.
            # v3.23.0: through the shared page drawer, so "4 days ago" ends
            # on one column like Bag Stats' dates.
            _draw_card_page $o $lx $rx $pf $F $col \
                [lrange $_hist_cards $_hist_offset [expr {$_hist_offset + 4}]]
            if {$total == 0} {
                _otext $o $cx [expr {$list_top + 2 * ($card_h + $card_gap)}] center \
                    "No valid espresso shots found yet (rinse, flush and steam are skipped)." \
                    $fbody [dict get $col text] $content_w
            }

            after 200  [list catch [list raise $o]]
            after 600  [list catch [list raise $o]]
        } err]} {
            catch { destroy $o }
            catch { msg "GrindAdvisor: history dialog failed: $err" }
            catch { borg toast "History unavailable" }
            return 0
        }
        return 1
    }

    # ------------------------------------------------------------------
    #  v3.6.0 Bag Stats card list -- same overlay mechanism and page
    #  geometry as the history list (5 cards, Prev/Next, Done), fed by
    #  the v3.5.0 per-bag comparison numbers. Read-only, display only.
    # ------------------------------------------------------------------
    variable _bag_offset 0
    variable _bag_cards {}
    variable _bag_summary ""
    # v3.13.0: 1 when _bag_cards leads with the starting-estimate card (which
    # is not a bag and must not be counted as one in the toolbar).
    variable _bag_est_present 0

    # Per-bag comparison cards. Returns {summary <text> cards {{l1 l2 l3}...}}.
    # Structured per-bag data (v3.13.0): the per-bag grouping, eligibility
    # filtering and Theil-Sen ideal-grind fit that Bag Stats has always run,
    # extracted from _bag_cards_data so starting_estimate can read the
    # NUMBERS instead of parsing rendered card strings. The math moved here
    # verbatim (v3.5.0/v3.6.0 code); _bag_cards_data below renders from it
    # and the offline harness asserts the rendered cards are byte-identical
    # to v3.12.0's. READ-ONLY: SELECTs via locate_shot_source only.
    #
    # Returns {ok 0 summary <error>} or {ok 1 target <t> bags <list>}.
    # bags is newest-first; each entry:
    #   key label bag_values profile n excluded spread stt_txt trusted r2
    #   newest_ts oldest_ts  + when trusted: m b ideal drift_txt
    #                        + when not:     why
    proc _bag_data {} {
        variable GA_REACH_TOL
        variable GA_REACH_MIN_GRINDS
        variable GA_ON_TARGET_TOL
        variable GA_FIT_MIN_SHOTS
        lassign [locate_shot_source] db table fields
        if {$db eq "" || $table eq ""} {
            return [dict create ok 0 summary "No SDB source detected."]
        }
        if {![dict exists $fields bag_fields]} {
            return [dict create ok 0 summary "No bean/bag columns detected in SDB."]
        }
        set rows [_filter_valid_rows [_fetch_recent $db $table $fields 600] $fields]
        if {[llength $rows] == 0} {
            return [dict create ok 0 summary "No valid espresso shots found yet."]
        }
        set target [_forecast_target]

        # Group rows (newest-first) by bag key; bag order = most recent first.
        set order {}
        set bagrows [dict create]
        foreach r $rows {
            set k [_bag_key $r]
            if {$k eq ""} { set k "(no bag info)" }
            if {![dict exists $bagrows $k]} { lappend order $k }
            dict lappend bagrows $k $r
        }

        set bags {}
        foreach k $order {
            set brows [dict get $bagrows $k]

            # Label from the newest row (bean, roaster, and the profile when
            # segmentation is on -- without it the same bean run on two
            # profiles renders as two identical-looking cards).
            set newest [lindex $brows 0]
            set label [_bag_label $newest]
            if {$label eq ""} { set label $k }

            # Eligible shots (newest-first): outliers excluded, normalized
            # time -- the exact dataset the forecast regression fits.
            set pts {}
            set draws {}
            set traws {}
            set excluded 0
            set t_first ""
            foreach r $brows {
                if {[_is_outlier $r]} { incr excluded; continue }
                lassign [_norm_time $r] tnorm active
                if {$tnorm eq ""} { continue }
                set sh [_shot_from_row $r]
                if {[dict size $sh] == 0} { continue }
                set g [dict get $sh grind]
                lappend pts [list $g $tnorm]
                # v3.20.0: the time the engine judged, as History shows it
                # (_plain_words' rule: the yield-adjusted time once it moved
                # 0.5 s+), so one shot never gets two verdicts.
                set traw [dict get $sh duration]
                lappend traws [expr {abs($tnorm - $traw) >= 0.5 ? $tnorm : $traw}]
                set ts [_dget $r timestamp]
                if {$ts ne "" && [string is integer -strict $ts]} {
                    lappend draws [list $g $ts $tnorm]
                    set t_first $ts
                }
            }
            set n [llength $pts]

            set gmin ""; set gmax ""
            foreach p $pts {
                set g [lindex $p 0]
                if {$gmin eq "" || $g < $gmin} { set gmin $g }
                if {$gmax eq "" || $g > $gmax} { set gmax $g }
            }
            set spread [expr {$n > 0 ? $gmax - $gmin : 0.0}]

            # Average-R2 feed (same recency-weighted fit as the forecast).
            set r2 ""
            if {$n >= 3} {
                set shots {}
                foreach p $pts {
                    lappend shots [dict create grind [lindex $p 0] \
                        t_raw [lindex $p 1] t_norm [lindex $p 1] norm_active 0]
                }
                set reg [_weighted_regression $shots 1]
                if {[dict get $reg ok] && [dict get $reg r2] ne ""} {
                    set r2 [dict get $reg r2]
                }
            }

            # Shots-to-target: first shot within GA_ON_TARGET_TOL (2 s) on the
            # time the engine judged (traws above), oldest first.
            set stt ""
            set idx 0
            foreach t [lreverse $traws] {
                incr idx
                if {abs($t - $target) <= $GA_ON_TARGET_TOL} { set stt $idx; break }
            }
            if {$stt eq ""} {
                set stt_txt "Never within [_fmt_num $GA_ON_TARGET_TOL]s of target"
            } elseif {$stt == 1} {
                set stt_txt "On target in 1 shot"
            } else {
                set stt_txt "On target in $stt shots"
            }

            # Robust per-bag calibration with the v3.5.0 trust gate.
            set fit [_theil_sen $pts]
            set trusted [expr {$n >= $GA_FIT_MIN_SHOTS && $spread >= 1.0 && $fit ne "" \
                && abs([lindex $fit 0]) >= 0.5}]

            # v3.23.0: the bag's values are text, picked with if.
            set bvals {}
            if {[dict exists $newest bag_values]} { set bvals [dict get $newest bag_values] }
            set bag [dict create key $k label $label \
                bag_values $bvals \
                profile [string trim [_dget $newest profile]] \
                n $n excluded $excluded spread $spread stt_txt $stt_txt \
                trusted $trusted r2 $r2 \
                newest_ts [_dget $newest timestamp] \
                oldest_ts [_dget [lindex $brows end] timestamp]]

            if {$trusted} {
                lassign $fit m b
                dict set bag m $m
                dict set bag b $b
                # v3.18.0: keep the unclamped ideal and say when it is out of
                # the grinder range: a clamped 0.0 read as a real ideal, and
                # fed starting_estimate. v3.18.1: the same range test and
                # tolerance as the rec's `reach` (_reach_miss, GA_REACH_TOL),
                # but on THIS card's own robust fit -- Theil-Sen over every
                # eligible shot, no R2 gate, not recency-weighted -- so its
                # ideal (Bam Bam -4.0) is not the forecast's (-7.7) and the
                # two verdicts can differ. reach_out gates starting_estimate,
                # which consumes this same Theil-Sen ideal.
                # v3.18.2: and the same GA_REACH_MIN_GRINDS gate -- 4 shots at
                # two grinds pass the trust gate but are pair evidence. Such
                # a trend is NOT assessed (reach_unassessed): never shown as
                # out of reach, never as its clamped "Ideal", never a seed.
                set raw [expr {($target - $b) / double($m)}]
                lassign [_grinder_range] rlo rhi
                dict set bag ideal_raw $raw
                set gdistinct {}
                foreach p $pts {
                    if {[lsearch -exact $gdistinct [lindex $p 0]] < 0} { lappend gdistinct [lindex $p 0] }
                }
                dict set bag reach_out 0
                dict set bag reach_unassessed 0
                set miss [_reach_miss $m $raw $rlo $rhi]
                if {[llength $miss] == 2 && [lindex $miss 1] > $GA_REACH_TOL} {
                    if {[llength $gdistinct] >= $GA_REACH_MIN_GRINDS} {
                        dict set bag reach_out 1
                    } else {
                        dict set bag reach_unassessed 1
                    }
                }
                dict set bag ideal [_clamp_grind $raw]
                set drift_txt ""
                if {[llength $draws] >= 6 && $t_first ne ""} {
                    set dpts {}
                    set span_d 0.0
                    foreach p $draws {
                        lassign $p g ts2 t
                        set d [expr {($ts2 - $t_first) / 86400.0}]
                        if {$d > $span_d} { set span_d $d }
                        lappend dpts [list $g $d $t]
                    }
                    if {$span_d >= 3.0} {
                        set c [_drift_fit $dpts]
                        if {$c ne ""} {
                            set drift_txt "drift [format %+.1f $c] s/day"
                        }
                    }
                }
                dict set bag drift_txt $drift_txt
            } else {
                if {$n < $GA_FIT_MIN_SHOTS} {
                    set why "needs ${GA_FIT_MIN_SHOTS}+ shots"
                } elseif {$spread < 1.0} {
                    set why "grind spread only [format %.1f $spread]"
                } else {
                    set why "slope too flat"
                }
                dict set bag why $why
            }
            lappend bags $bag
        }
        return [dict create ok 1 target $target bags $bags]
    }

    proc _bag_cards_data {{max_bags 25}} {
        variable GA_R2_MIN
        variable GA_REACH_MIN_GRINDS
        set data [_bag_data]
        if {![dict get $data ok]} {
            return [dict create summary [dict get $data summary] cards {}]
        }
        set target [dict get $data target]

        set cards {}
        set r2_sum 0.0
        set r2_count 0
        set slopes {}
        set shown 0
        foreach bag [dict get $data bags] {
            if {$shown >= $max_bags} { break }
            incr shown

            if {[dict get $bag r2] ne ""} {
                set r2_sum [expr {$r2_sum + [dict get $bag r2]}]
                incr r2_count
            }

            # v3.20.0 (design review F16): the ideal grind LARGE on the right
            # ("ideal grind" under it), or the reason there is none; the bag
            # name with its dates in the first row; how it went on the second
            # (shots to target, shot count); slope, drift and fit in the
            # caption. The verdict rules are 3.18.x's, unchanged.
            set sep "  [format %c 0xB7]  "
            set card [dict create l1 [dict get $bag label]]
            set cap3 {}
            if {[dict get $bag trusted]} {
                lappend slopes [dict get $bag m]
                lappend cap3 "slope [format %.1f [dict get $bag m]] s/grind"
                if {[dict get $bag drift_txt] ne ""} { lappend cap3 [dict get $bag drift_txt] }
                # r2 is numeric for every trusted bag (n >= 4, a real slope);
                # the "" test only guards a future change of the trust gate.
                set r2b [dict get $bag r2]
                if {$r2b ne ""} { lappend cap3 "fit R2 [format %.2f $r2b]" }
                if {[_dget $bag reach_out] eq "1" && ($r2b eq "" || $r2b < $GA_R2_MIN)} {
                    # v3.18.1: never claim "out of reach" from a fit whose times
                    # do not track the grind (the forecast refuses that fit).
                    dict set card big "No ideal yet" ; dict set card bigsize word ; dict set card bigrole muted
                    dict set card cap "times not tracking grind"
                } elseif {[_dget $bag reach_unassessed] eq "1"} {
                    dict set card big "No ideal yet" ; dict set card bigsize word ; dict set card bigrole muted
                    dict set card cap "fewer than $GA_REACH_MIN_GRINDS different grinds"
                } elseif {[_dget $bag reach_out] eq "1"} {
                    dict set card big "Out of reach" ; dict set card bigsize word ; dict set card bigrole warn
                    dict set card cap "trend ideal [format %.1f [dict get $bag ideal_raw]]"
                } else {
                    dict set card big [_grind_fmt [_round_grind [dict get $bag ideal]]]
                    dict set card cap "ideal grind"
                }
            } else {
                dict set card big "No ideal yet" ; dict set card bigsize word ; dict set card bigrole muted
                dict set card cap [dict get $bag why]
            }

            # v3.23.0 (F21): date only on both ends ("30 Sep - 01 Oct" with an
            # en dash; "Sep 30 - Oct 01" when Lumen says mdy; + the year when
            # not this year) -- a timed range would squeeze the bag name.
            if {[dict get $bag n] > 0} {
                set d_new [_fmt_day [string trim [dict get $bag newest_ts]]]
                set d_old [_fmt_day [string trim [dict get $bag oldest_ts]]]
                if {$d_old ne "" && $d_new ne ""} {
                    if {$d_old eq $d_new} {
                        dict set card date $d_new
                    } else {
                        dict set card date "$d_old [format %c 0x2013] $d_new"
                    }
                }
            }
            set ex [dict get $bag excluded]
            set n [dict get $bag n]
            set shots [_plural $n shot]
            if {$ex > 0} { append shots ", $ex left out" }
            dict set card l2 "[dict get $bag stt_txt]$sep$shots"
            dict set card l3 [join $cap3 $sep]
            lappend cards $card
        }

        # v3.23.0: separator, superscript two and the plural from code
        # (ASCII source; "1 reliable bag" no longer reads "1 reliable bags").
        set sep "  [format %c 0xB7]  "
        set sparts [list "Target [format %.0f $target]s"]
        if {[llength $slopes] > 0} {
            lappend sparts "Median slope [format %.1f [_median $slopes]] s/grind ([_plural [llength $slopes] {reliable bag}])"
        }
        if {$r2_count > 0} {
            lappend sparts "Average R[format %c 0xB2] [format %.2f [expr {$r2_sum / double($r2_count)}]]"
        }
        return [dict create summary [join $sparts $sep] cards $cards]
    }

    proc show_bag_stats {} {
        variable _bag_offset
        variable _bag_cards
        variable _bag_summary
        variable _bag_est_present
        set _bag_offset 0
        set data [_bag_cards_data]
        set _bag_cards [dict get $data cards]
        set _bag_summary [dict get $data summary]
        # v3.13.0: when the loaded bag has no shots and a starting estimate
        # exists, lead with a card naming the rung and the source bags.
        # Display only; the toolbar counter excludes it from the bag count.
        set _bag_est_present 0
        set est {}
        catch { set est [starting_estimate] }
        if {$est ne "" && [llength $_bag_cards] > 0} {
            # v3.20.0 (F16): the same card shape -- the estimate large on the
            # right, never captioned as a recommendation.
            set _bag_cards [linsert $_bag_cards 0 [dict create \
                l1 "New bag: starting estimate" \
                l2 "Borrowed from [dict get $est rung_txt]" \
                l3 "From: [join [dict get $est sources] {, }]" \
                big "~[_grind_fmt [dict get $est grind]]" cap "starting estimate"]]
            set _bag_est_present 1
        }
        return [_render_bag_stats_dialog]
    }

    proc _bag_page {delta} {
        variable _bag_offset
        variable _bag_cards
        set total [llength $_bag_cards]
        set new [expr {$_bag_offset + 5 * $delta}]
        if {$new < 0} { set new 0 }
        if {$new >= $total || $new == $_bag_offset} { return }
        set _bag_offset $new
        _render_bag_stats_dialog
    }

    proc _render_bag_stats_dialog {} {
        variable _bag_offset
        variable _bag_cards
        variable _bag_summary
        variable _bag_est_present
        lassign [_pgeom] parent W H o
        if {[catch {
            catch { destroy $o }
            set col [_colors]
            set F [_pfonts $H 1.0]
            set fsec  [dict get $F section]
            set fprim [dict get $F primary]
            set fbody [dict get $F body]
            set fcap  [dict get $F caption]
            set fbtn  [dict get $F button]

            canvas $o -bg [dict get $col scrim] -highlightthickness 0 -bd 0 -takefocus 0
            place $o -in $parent -x 0 -y 0 -relwidth 1 -relheight 1
            raise $o

            set pf [expr {double($H) / 800.0}]
            set mg [expr {int(max($W * 0.036, 32))}]
            set lx $mg
            set rx [expr {$W - $mg}]
            set cx [expr {($lx + $rx) / 2}]
            set content_w [expr {$rx - $lx}]

            set total [llength $_bag_cards]
            # v3.16.6: GA page header (the summary is the subtitle), Done
            # bottom-left and the standard pager bottom-right.
            _overlay_chrome $o $W $H $col "Bag stats" $_bag_summary \
                [expr {$_bag_offset > 0}] [expr {$_bag_offset + 5 < $total}] \
                [list ::plugins::GrindAdvisor::_bag_page -1] \
                [list ::plugins::GrindAdvisor::_bag_page 1]

            set tb0 [expr {int(104 * $pf)}]
            set tb1 [expr {int(152 * $pf)}]
            # v3.23.0 (F21): "1-5 of 16 bags" (en dash) / "No bags".
            if {$_bag_est_present} {
                # v3.13.0: card 0 is the starting estimate, not a bag. Cards
                # shown on this page are indices offset..offset+4, i.e. bags
                # max(offset,1)..min(offset+4, nbags) since bag i is card i.
                set nbags [expr {$total - 1}]
                set first [expr {max($_bag_offset, 1)}]
                set last [expr {$_bag_offset + 4}]
                if {$last > $nbags} { set last $nbags }
                set count_text [_range_count $first $last $nbags bag]
            } else {
                set last [expr {$_bag_offset + 5}]
                if {$last > $total} { set last $total }
                set count_text [_range_count [expr {$_bag_offset + 1}] $last $total bag]
            }
            _otext $o $lx [expr {($tb0 + $tb1) / 2}] w [_fit_text $count_text $fcap $content_w] \
                $fcap [dict get $col muted] $content_w left

            set list_top [expr {int(168 * $pf)}]
            set card_h [expr {int(96 * $pf)}]
            set card_gap [expr {int(12 * $pf)}]

            # v3.20.0 (F16): the shared card -- the ideal grind large on the right.
            # v3.21.0: the dates end on one column (now _draw_card_page).
            _draw_card_page $o $lx $rx $pf $F $col \
                [lrange $_bag_cards $_bag_offset [expr {$_bag_offset + 4}]]
            if {$total == 0} {
                _otext $o $cx [expr {$list_top + 2 * ($card_h + $card_gap)}] center \
                    $_bag_summary $fbody [dict get $col text] $content_w
            }

            after 200  [list catch [list raise $o]]
            after 600  [list catch [list raise $o]]
        } err]} {
            catch { destroy $o }
            catch { msg "GrindAdvisor: bag stats dialog failed: $err" }
            catch { borg toast "Bag stats unavailable" }
            return 0
        }
        return 1
    }

    proc _get_canvas {} {
        # Known global first.
        if {[info exists ::can] && [_is_canvas $::can]} { return $::can }
        foreach w {.can .skincanvas .canvas} {
            if {[_is_canvas $w]} { return $w }
        }
        # Otherwise find the largest canvas under the root window.
        set best ""
        set bestarea 0
        foreach w [_all_widgets .] {
            if {[_is_canvas $w]} {
                set a [expr {[winfo width $w] * [winfo height $w]}]
                if {$a > $bestarea} { set bestarea $a; set best $w }
            }
        }
        return $best
    }

    proc _is_canvas {w} {
        if {$w eq ""} { return 0 }
        if {![winfo exists $w]} { return 0 }
        return [expr {[winfo class $w] eq "Canvas"}]
    }

    proc _all_widgets {w} {
        set res [list $w]
        foreach c [winfo children $w] {
            foreach x [_all_widgets $c] { lappend res $x }
        }
        return $res
    }

    # ------------------------------------------------------------------
    #  Secondary UI: a plain Tk toplevel (useful for desktop testing, or any
    #  environment without the shared canvas).
    # ------------------------------------------------------------------
    proc _show_tk_dialog {rec} {
        if {[catch {
            set col [_colors]
            set bg  [dict get $col panel]
            set fg  [dict get $col text]
            catch { destroy .grindadvisor }
            toplevel .grindadvisor
            wm title .grindadvisor "Grind Advisor"
            catch { wm transient .grindadvisor . }
            catch { .grindadvisor configure -bg $bg }

            lassign [_dialog_lines $rec] body bignum tail
            label .grindadvisor.body -text $body -justify center -padx 24 -pady 16 \
                -bg $bg -fg $fg
            pack .grindadvisor.body -fill x
            if {$bignum ne ""} {
                # v3.19.0: neutral hero, like the overlay popup.
                label .grindadvisor.big -text $bignum -justify center \
                    -bg $bg -fg $fg
                catch { .grindadvisor.big configure -font [_font 28 bold] }
                pack .grindadvisor.big -pady {0 12}
            }
            if {$tail ne ""} {
                label .grindadvisor.tail -text $tail -justify center -padx 24 \
                    -bg $bg -fg $fg -wraplength 600
                pack .grindadvisor.tail -fill x -pady {0 8}
            }
            frame .grindadvisor.btns -bg $bg
            button .grindadvisor.btns.ok -text "OK" \
                -command ::plugins::GrindAdvisor::_close_dialog
            button .grindadvisor.btns.hist -text "History" \
                -command ::plugins::GrindAdvisor::_history_and_close
            pack .grindadvisor.btns.ok .grindadvisor.btns.hist \
                -side left -padx 12 -pady 12
            pack .grindadvisor.btns -pady {0 16}
        }]} {
            return 0
        }
        return 1
    }

    # Best-effort: open the skin's shot-history page. The correct page name
    # varies by skin; we try the common ones and quietly stop if none exist.
    proc _open_history {} {
        set attempts {
            {dui page load shot_history}
            {dui page load history_viewer}
            {dui page load DSx_past}
            {dui page load past}
            {dui page load history}
            {load_history_page}
        }
        foreach cmd $attempts {
            if {![catch { uplevel #0 $cmd }]} { return 1 }
        }
        catch { msg "GrindAdvisor: no known history page found for this skin." }
        return 0
    }

    proc _field_debug_value {fields key} {
        if {[dict exists $fields $key]} { return [dict get $fields $key] }
        return "not detected"
    }

    # v3.24.0 (F23): ": " between a state and its reason (was " - ").
    proc _key_debug_value {k} {
        if {$k eq ""} { return "(none: no bean fields set)" }
        return $k
    }

    proc _saved_rec_key_text {} {
        variable last_recommendation
        if {$last_recommendation eq ""} { return "(nothing saved yet)" }
        if {![dict exists $last_recommendation bag_key]} {
            return "(saved before v3.7.0: no key)"
        }
        set k [dict get $last_recommendation bag_key]
        if {$k eq ""} { return "(none)" }
        # Braces, not square brackets: [..] inside a quoted Tcl string is
        # command substitution and would try to run "MATCHES CURRENT".
        if {[last_recommendation_is_current]} { return "$k  (matches current)" }
        return "$k  (stale: different bag or profile)"
    }

    proc detected_fields_text {} {
        variable GA_FETCH_LIMIT
        lassign [locate_shot_source] db table fields
        if {$table eq ""} {
            set table "not detected"
            set fields {}
        }
        # v3.23.0: text picked with if, never `expr ?:`.
        set hist_check "off (history folder not found)"
        if {[llength [_history_dirs]] > 0} { set hist_check "active (history folder found)" }
        set seg_txt off
        if {[_segment_by_profile]} { set seg_txt on }
        # v3.24.0 (F23): a range takes a spaced en dash (was " - ").
        set nd " [_char endash] "
        set lines [list \
            "Detected SDB table: $table" \
            "Detected grind column: [_field_debug_value $fields grind]" \
            "Detected set dose column: [_field_debug_value $fields dose]" \
            "Detected actual dose column: [_field_debug_value $fields actual_dose]" \
            "Detected set yield column: [_field_debug_value $fields set_yield]" \
            "Detected actual yield column: [_field_debug_value $fields actual_yield]" \
            "Detected shot time column: [_field_debug_value $fields duration]" \
            "Detected bag fields: [_field_debug_value $fields bag_fields]" \
            "Detected filename column: [_field_debug_value $fields filename]" \
            "Detected removed-flag column: [_field_debug_value $fields removed]" \
            "Deleted-shot file check: $hist_check" \
            "" \
            "Dose/yield source mode: [_dose_yield_mode_label [_setting dose_yield_mode auto]]" \
            "Dose plausibility (Auto): [_fmt_num [_setting dose_min 12.0]]$nd[_fmt_num [_setting dose_max 22.0]] g" \
            "Ratio plausibility (Auto): [_fmt_num [_setting ratio_min 1.0]]$nd[_fmt_num [_setting ratio_max 4.0]]" \
            "" \
            "Detected profile column: [_field_debug_value $fields profile]" \
            "Segment calibration by profile: $seg_txt" \
            "Current bag key: [_key_debug_value [current_bag_key]]" \
            "Saved rec bag key: [_saved_rec_key_text]" \
            "Shot window: $GA_FETCH_LIMIT rows" \
            "" \
            "Per-shot input/intermediate trace: see Calculation details."]
        return [join $lines "\n"]
    }

    # ------------------------------------------------------------------
    #  Shot trace (v2.2.0) -- READ-ONLY diagnostics. Recomputes each recent
    #  shot's recommendation through the exact same procs the popup and
    #  history use (no math duplicated, no math changed) and dumps every
    #  input and intermediate: time/target/error, dose, yield, bag shot,
    #  seconds-per-step + calibration source, cap, raw next, final rec,
    #  and reason. Two lines per shot, newest first.
    # ------------------------------------------------------------------
    proc _shot_trace_text {{limit 5}} {
        lassign [locate_shot_source] db table fields
        if {$db eq "" || $table eq ""} {
            return "Recent shot trace: no SDB source detected."
        }
        set rows [_fetch_recent $db $table $fields [expr {$limit + 35}]]
        set rows [_filter_valid_rows $rows $fields]
        if {[llength $rows] == 0} {
            return "Recent shot trace: no valid espresso shots."
        }
        set lines [list "Recent shot trace (newest first; same engine the popup uses):"]
        # v3.24.0 (F23): a middle dot between the facts of a line (was " | ").
        set d " [_char middot] "
        set nrows [llength $rows]
        set idx 1
        for {set pos 0} {$pos < $nrows && $idx <= $limit} {incr pos} {
            set r [lindex $rows $pos]
            set current [_shot_from_row $r]
            if {[dict size $current] == 0} { continue }
            set bag_shot [_bag_shot_count $current $rows $pos]
            set rec [_forecast_rec $rows $fields $pos]
            if {[dict size $rec] == 0} { continue }

            # v3.23.0 (F21): the shared date ("Mon 29 Sep 21:29" / 12 h per
            # Lumen); text picked with if, never `expr ?:`.
            set dt [_fmt_when [string trim [_dget $r timestamp]]]
            if {$dt eq ""} { set dt "(no timestamp)" }
            set dy [_effective_dose_yield $r]
            set bag_t "-"
            if {$bag_shot ne ""} { set bag_t "#$bag_shot" }
            set ratio_t "-"
            if {[dict get $dy ratio] ne ""} { set ratio_t "1:[dict get $dy ratio]" }

            lappend lines [format "%d) %s%sgrind %s time %ss target %ss err %+.1f%sbag %s" \
                $idx $dt $d [_fmt_num [dict get $rec grind]] [_fmt_num [dict get $rec actual]] \
                [_fmt_num [dict get $rec target]] [dict get $rec error] $d $bag_t]
            lappend lines "   dose [dict get $dy dose_src]${d}yield [dict get $dy yield_src]${d}ratio $ratio_t"
            if {[dict get $rec method] eq "regression"} {
                lappend lines [format "   %s: n=%s m=%s b=%s R2=%s %s rec %s (pred %ss)" \
                    [_forecast_method_label [dict get $rec method]] [dict get $rec n] \
                    [_fmt_num [dict get $rec m]] [_fmt_num [dict get $rec b]] \
                    [_forecast_r2_txt $rec] [_char arrow] [_fmt_num [dict get $rec next]] \
                    [_fmt_num [dict get $rec predicted_time]]]
            } else {
                lappend lines "   [_forecast_method_label [dict get $rec method]]: n=[dict get $rec n] s/step [_fmt_num [dict get $rec s_per_step]] [_char arrow] rec [_fmt_num [dict get $rec next]]"
            }
            incr idx
        }
        return [join $lines "\n"]
    }

    proc _calculation_diagnostics_text {} {
        set rec [analyze_latest_shot]
        if {![dict exists $rec ok] || ![dict get $rec ok]} {
            if {[dict exists $rec error]} {
                return "Calculation diagnostics:\nLatest recommendation unavailable: [string map {\n { }} [dict get $rec error]]"
            }
            return "Calculation diagnostics:\nLatest recommendation unavailable."
        }
        # v3.23.0: text picked with if, never `expr ?:` (it rewrites
        # number-like text: "1.50" -> "1.5").
        set dose_src "n/a"
        if {[dict exists $rec dose_src]} { set dose_src [dict get $rec dose_src] }
        set yield_src "n/a"
        if {[dict exists $rec yield_src]} { set yield_src [dict get $rec yield_src] }
        set ratio_txt "n/a"
        if {[dict exists $rec ratio]} { set ratio_txt "1:[dict get $rec ratio]" }
        set norm_txt "off (no scale data or no correction)"
        if {[dict get $rec normalized]} { set norm_txt "active (yield/dose)" }
        set lines [list \
            "Calculation diagnostics:" \
            "Method: [_forecast_method_label [dict get $rec method]]" \
            "Eligible bag shots (n): [dict get $rec n]" \
            "Outliers excluded: [dict get $rec excluded]" \
            "Normalization: $norm_txt" \
            "Dose/yield source mode: [_dose_yield_mode_label [_setting dose_yield_mode auto]]" \
            "Dose used: $dose_src" \
            "Yield used: $yield_src" \
            "Ratio (yield/dose): $ratio_txt" \
            "Current grind: [_fmt_num [dict get $rec grind]]" \
            "Target time: [_fmt_num [dict get $rec target]]s" \
            "Actual time: [_fmt_num [dict get $rec actual]]s"]
        if {[dict get $rec method] eq "regression"} {
            lappend lines \
                "Learned slope m: [_fmt_num [dict get $rec m]] s/grind" \
                "Intercept b: [_fmt_num [dict get $rec b]] s" \
                "Model fit R2: [_forecast_r2_txt $rec]" \
                "Ideal grind (predicts target): [_fmt_num [expr {([dict get $rec target] - [dict get $rec b]) / double([dict get $rec m])}]]" \
                "Grind reach: [_reach_txt $rec]" \
                "Predicted time at recommendation: [_fmt_num [dict get $rec predicted_time]]s"
        } else {
            lappend lines "Seconds per step: [_fmt_num [dict get $rec s_per_step]]"
        }
        lappend lines \
            "Rounded final grind: [_fmt_num [dict get $rec next]]" \
            "Rounding increment: [_fmt_num [dict get $rec rounding_increment]]" \
            "Grinder min/max: [_fmt_num [dict get $rec grinder_min]] / [_fmt_num [dict get $rec grinder_max]]" \
            "" \
            "Constants: s/step default 3.0, damping 0.5, decay 0.85, dose sens 1.8 s/g, outlier 2.0 g, min shots 3."
        return [join $lines "\n"]
    }

    proc _dose_yield_mode_label {mode} {
        switch -- $mode {
            fixed  { return "Fixed (set values)" }
            actual { return "Actual (measured)" }
            default { return "Auto (measured if plausible)" }
        }
    }

    # ------------------------------------------------------------------
    #  v3.6.0 long-text pagination. The full-width text card fits about
    #  20 body lines (~24 caption lines); longer content used to run past
    #  the card and clip under the bottom bar (Help, Calculation
    #  Details). Split on newlines, charge each line its estimated
    #  wrapped-line count, and pack pages conservatively so nothing can
    #  clip; Prev/Next in the bottom bar flips pages.
    # ------------------------------------------------------------------
    # v3.21.0 (F17): word-wrap a paragraph at `width` characters with
    # explicit newlines, so Help reads as a column of <= width characters
    # whatever the card's pixel width (a word longer than width keeps its
    # own line).
    proc _wrap_text {text width} {
        set out {}
        set line ""
        foreach w [split [string trim $text] " "] {
            if {$w eq ""} { continue }
            if {$line eq ""} {
                set line $w
            } elseif {[string length $line] + 1 + [string length $w] <= $width} {
                append line " " $w
            } else {
                lappend out $line
                set line $w
            }
        }
        if {$line ne ""} { lappend out $line }
        return [join $out "\n"]
    }

    proc _paginate_text {text max_lines chars_per_line} {
        set pages {}
        set cur {}
        set used 0
        foreach line [split $text "\n"] {
            set cost 1
            set len [string length $line]
            if {$len > $chars_per_line} {
                set cost [expr {($len + $chars_per_line - 1) / $chars_per_line}]
            }
            if {$used > 0 && $used + $cost > $max_lines} {
                lappend pages [join $cur "\n"]
                set cur {}
                set used 0
            }
            # v3.18.1: a blank line never opens a page (Calculation Details
            # page 2 started with one once Grind reach shifted the text).
            if {$used == 0 && [llength $pages] > 0 && [string trim $line] eq ""} { continue }
            lappend cur $line
            incr used $cost
        }
        if {[llength $cur] > 0} { lappend pages [join $cur "\n"] }
        if {[llength $pages] == 0} { lappend pages "" }
        return $pages
    }

    # Shared bottom-bar pager controls for the long-text sub-pages.
    # Adds Prev/Next (right side) and a page indicator; the caller's
    # namespace provides a _pg {delta} proc.
    # v3.16.6: the cross-plugin pager standard -- Prev sits an sm gap from
    # Next (was lg), the pair ShotHistoryEditor and MaintenanceTracker use;
    # _pager_state disables the unavailable end instead of leaving it live.
    proc _add_pager {page ns} {
        variable L
        set rx $L(right_x)
        set prev_x0 [expr {$rx - 2 * $L(btn_w_std) - $L(sm)}]
        set next_x0 [expr {$rx - $L(btn_w_std)}]
        dui add dtext $page [expr {$prev_x0 - $L(lg)}] [expr {($L(bar_y0) + $L(bar_y1)) / 2}] \
            -tags pg_ind -text "" -font $L(font_caption) -fill $L(text_mut) -anchor e -justify right
        dui add dbutton $page $prev_x0 $L(bar_y0) [expr {$prev_x0 + $L(btn_w_std)}] $L(bar_y1) \
            -tags pg_prev -label "[format %c 0x25C0] [translate "Prev"]" \
            -command [list ::plugins::GrindAdvisor::_tap $page pg_prev [list ${ns}::_pg -1]] -label_font $L(font_button) -style ga_btn
        dui add dbutton $page $next_x0 $L(bar_y0) $rx $L(bar_y1) \
            -tags pg_next -label "[translate "Next"] [format %c 0x25B6]" \
            -command [list ::plugins::GrindAdvisor::_tap $page pg_next [list ${ns}::_pg 1]] -label_font $L(font_button) -style ga_btn
    }

    # Disables the pager end that has no page (MaintenanceTracker's GFC
    # -state pattern: the wildcard tag reaches the shape, the label and the
    # tap rect; ga_btn carries the disabled fills). Called by each text
    # page's _render with the 0-based page index and the page count.
    proc _pager_state {page idx total} {
        # v3.23.0: states picked with if, never `expr ?:`.
        set ps disabled
        if {$idx > 0} { set ps normal }
        set ns disabled
        if {$idx < $total - 1} { set ns normal }
        catch { dui item config $page pg_prev* -state $ps }
        catch { dui item config $page pg_next* -state $ns }
    }

    # v3.17.4 (F22, review): the pager's state for the FIRST frame. Called
    # from load, where the items are hidden: enable_or_disable's -initial 1
    # writes the st: tag that dui's re-show applies (dui.tcl ~7953), so the
    # ends paint greyed from the start; _pager_state sets the live state in
    # show. Safe: GA's pager buttons are never hidden.
    proc _pager_initial {page idx total} {
        catch { dui item enable_or_disable [expr {$idx > 0}] $page pg_prev* -initial 1 }
        catch { dui item enable_or_disable [expr {$idx < $total - 1}] $page pg_next* -initial 1 }
    }

    # ------------------------------------------------------------------
    #  Bag Stats helpers (v3.5.0; the card-list dialog itself is
    #  _bag_cards_data/_render_bag_stats_dialog, v3.6.0) -- READ-ONLY.
    #  _theil_sen: median of pairwise slopes + median-residual intercept,
    #  so one channeled shot can't drag the fit. _drift_fit: least-squares
    #  t = b + m*grind + c*days, Cramer's rule on the 3x3 normal
    #  equations. Nothing here feeds back into any recommendation.
    # ------------------------------------------------------------------
    proc _median {vals} {
        set n [llength $vals]
        if {$n == 0} { return "" }
        set s [lsort -real $vals]
        set mid [expr {$n / 2}]
        if {$n % 2} { return [lindex $s $mid] }
        return [expr {([lindex $s [expr {$mid - 1}]] + [lindex $s $mid]) / 2.0}]
    }

    # Robust line fit: median of pairwise slopes, median-residual intercept.
    # pts = list of {grind time} pairs. Returns {m b} or "" when every shot
    # sits at one grind.
    proc _theil_sen {pts} {
        set slopes {}
        set n [llength $pts]
        for {set i 0} {$i < $n} {incr i} {
            lassign [lindex $pts $i] gi ti
            for {set j [expr {$i + 1}]} {$j < $n} {incr j} {
                lassign [lindex $pts $j] gj tj
                if {abs($gj - $gi) < 1e-9} { continue }
                lappend slopes [expr {($tj - $ti) / double($gj - $gi)}]
            }
        }
        if {[llength $slopes] == 0} { return "" }
        set m [_median $slopes]
        set resid {}
        foreach p $pts {
            lassign $p g t
            lappend resid [expr {$t - $m * $g}]
        }
        return [list $m [_median $resid]]
    }

    # Least-squares t = b + m*grind + c*days; returns the drift c (s/day)
    # or "". pts = list of {grind days time}. Solved by Cramer's rule on
    # the 3x3 normal equations.
    proc _drift_fit {pts} {
        if {[llength $pts] < 3} { return "" }
        foreach v {a11 a12 a13 a22 a23 a33 b1 b2 b3} { set $v 0.0 }
        foreach p $pts {
            lassign $p g d t
            set a11 [expr {$a11 + 1.0}]
            set a12 [expr {$a12 + $g}]
            set a13 [expr {$a13 + $d}]
            set a22 [expr {$a22 + $g * $g}]
            set a23 [expr {$a23 + $g * $d}]
            set a33 [expr {$a33 + $d * $d}]
            set b1 [expr {$b1 + $t}]
            set b2 [expr {$b2 + $g * $t}]
            set b3 [expr {$b3 + $d * $t}]
        }
        set det [expr {$a11*($a22*$a33 - $a23*$a23) - $a12*($a12*$a33 - $a23*$a13) \
            + $a13*($a12*$a23 - $a22*$a13)}]
        if {abs($det) < 1e-9} { return "" }
        set detc [expr {$a11*($a22*$b3 - $b2*$a23) - $a12*($a12*$b3 - $b2*$a13) \
            + $b1*($a12*$a23 - $a22*$a13)}]
        return [expr {$detc / double($det)}]
    }

}

namespace eval ::dui::pages::GrindAdvisor_settings {
    # v2.0.0 main page: content-first label/value grid. All coordinates come
    # from the ::plugins::GrindAdvisor::L token array; nothing is hardcoded.
    variable data
    array set data {
        popup_theme_value {}
        rounding_value {}
        enable_popup_value {}
    }

    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::GrindAdvisor::L L
        ::plugins::GrindAdvisor::_page_bg $page
        set lx $L(left_x)
        set rx $L(right_x)
        set cx $L(center_x)

        # Header (on the grey page background, outside any card).
        dui add dtext $page $cx $L(header_title_y) -tags page_title -text [translate "Grind Advisor"] \
            -font $L(font_title) -width $L(content_w) -fill $L(text_hi) -anchor center -justify center
        dui add dtext $page $cx $L(header_subtitle_y) -tags subtitle \
            -text [translate "Reads your saved shots and recommends the next grind. Read-only."] \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) -anchor center -justify center

        # v3.12.0: page-theme toggle, top-right corner of the header
        # (sun/moon; the popup's own theme stays a separate setting).
        # v3.16.6: y = 11 ref, the box MaintenanceTracker, BeanScanner and
        # ShotHistoryEditor use (was header-centred, 7 px lower).
        set th_y1 [expr {int(round(11 * $L(scale)))}]
        set th_font $L(font_button)
        if {$L(have_icons)} { set th_font $L(font_icon) }
        dui add dbutton $page [expr {$rx - $L(btn_h)}] $th_y1 \
            $rx [expr {$th_y1 + $L(btn_h)}] \
            -tags btn_theme -label [::plugins::GrindAdvisor::_theme_button_face] \
            -command [list ::plugins::GrindAdvisor::_tap $page btn_theme ::plugins::GrindAdvisor::toggle_theme] \
            -label_font $th_font \
            -style ga_btn

        # v2.0.1: stock App-tab section cards, two balanced columns.
        # Precomputed content-driven heights:
        #   stepper card  = pad + title + md + (3*row_pitch - md) + pad
        #   2-row card    = pad + title + md + (2*row_pitch - md) + pad
        #   actions card  = pad + title + md + 2*btn_h + md + pad
        # v3.17.0 (F5): Shot Settings holds three 60 px stepper rows (it held
        # 48 px entries), so History and Bag Stats share the Actions card's
        # second row: the left column ends 64 px above the bottom bar.
        set col_w $L(sec_col_w)
        set c2x $L(sec_col2_x)
        set shot_h [expr {2 * $L(sec_pad) + $L(sec_title_h) + $L(md) + 3 * $L(row_pitch) - $L(md)}]
        set act_h  [expr {2 * $L(sec_pad) + $L(sec_title_h) + $L(md) + 2 * $L(btn_h) + $L(md)}]
        set two_h  [expr {2 * $L(sec_pad) + $L(sec_title_h) + $L(md) + 2 * $L(row_pitch) - $L(md)}]
        set three_h [expr {2 * $L(sec_pad) + $L(sec_title_h) + $L(md) + 3 * $L(row_pitch) - $L(md)}]
        # v3.24.0 (F24): the Recommendation card is one caption line taller
        # for the Confidence row's next step (the right column still ends
        # well above the left one).
        set reco_h [expr {$two_h + $L(conf_step_h)}]

        # --- LEFT column: Shot settings, then Actions.
        set y0 $L(sec_top)
        set rows_y [::plugins::GrindAdvisor::_sec_card $page sec_shot $lx $y0 $col_w $shot_h "Shot settings"]
        set lab_x [expr {$lx + $L(sec_pad)}]
        set step_x2 [expr {$lx + $col_w - $L(sec_pad)}]
        set row 0
        foreach {key label} {
            target_time "Target shot time (s)"
            grinder_min "Grinder minimum"
            grinder_max "Grinder maximum"
        } {
            set ry [expr {$rows_y + $row * $L(row_pitch)}]
            dui add dtext $page $lab_x [expr {$ry + $L(btn_h) / 2}] -tags ${key}_label \
                -text [translate $label] -font $L(font_body) \
                -width [expr {$step_x2 - $L(step_w) - $L(lg) - $lab_x}] \
                -fill $L(text_body) -anchor w -justify left
            ::plugins::GrindAdvisor::_add_stepper $page $key $step_x2 $ry
            incr row
        }

        set y0 [expr {$y0 + $shot_h + $L(sec_gap)}]
        set rows_y [::plugins::GrindAdvisor::_sec_card $page sec_actions $lx $y0 $col_w $act_h "Actions"]
        set abtn_x1 [expr {$lx + $L(sec_pad)}]
        set abtn_x2 [expr {$lx + $col_w - $L(sec_pad)}]
        dui add dbutton $page $abtn_x1 $rows_y $abtn_x2 [expr {$rows_y + $L(btn_h)}] \
            -tags show_latest_recommendation -label [translate "Show next grind"] \
            -command [list ::plugins::GrindAdvisor::_tap $page show_latest_recommendation ::plugins::GrindAdvisor::show_latest_recommendation] \
            -label_font $L(font_button) -style ga_btn_primary
        set rows_y [expr {$rows_y + $L(btn_h) + $L(md)}]
        set half_w [expr {($abtn_x2 - $abtn_x1 - $L(lg)) / 2}]
        dui add dbutton $page $abtn_x1 $rows_y [expr {$abtn_x1 + $half_w}] [expr {$rows_y + $L(btn_h)}] \
            -tags recent_shot_history -label [translate "History"] \
            -command [list ::plugins::GrindAdvisor::_tap $page recent_shot_history ::plugins::GrindAdvisor::_show_history_dialog] \
            -label_font $L(font_button) -style ga_btn
        dui add dbutton $page [expr {$abtn_x2 - $half_w}] $rows_y $abtn_x2 [expr {$rows_y + $L(btn_h)}] \
            -tags bag_stats_action -label [translate "Bag stats"] \
            -command [list ::plugins::GrindAdvisor::_tap $page bag_stats_action ::plugins::GrindAdvisor::show_bag_stats] \
            -label_font $L(font_button) -style ga_btn

        # --- RIGHT column: Recommendation (2 rows: rounding control + the
        # --- calibration-accuracy gauge), then Popup. Rows use the
        # --- card-relative grid: label / value / right-aligned button.
        # (v3.0.0: the recommendation-mode selector is gone -- there is one
        # built-in Regression Forecast method, no modes.)
        foreach {card_tag card_title card_y card_h rows} [list \
            sec_reco "Recommendation" $L(sec_top) $reco_h {
                rounding "Grind rounding increment" rounding_value "Next" cycle_rounding
            } \
            sec_popup "Popup" [expr {$L(sec_top) + $reco_h + $L(sec_gap)}] $two_h {
                theme "Popup theme" popup_theme_value "Toggle" toggle_popup_theme
                popup "Automatic popup" enable_popup_value "Toggle" toggle_enable_popup
            }] {
            set rows_y [::plugins::GrindAdvisor::_sec_card $page $card_tag $c2x $card_y $col_w $card_h $card_title]
            set lab_x [expr {$c2x + $L(sec_pad)}]
            set val_x [expr {$c2x + $L(sec_value_dx)}]
            set btn_x2 [expr {$c2x + $col_w - $L(sec_pad)}]
            set btn_x1 [expr {$btn_x2 - $L(sec_btn_w)}]
            set val_w [expr {$btn_x1 - $L(lg) - $val_x}]
            set row 0
            foreach {key label value_tag btn_label btn_cmd} $rows {
                set ry [expr {$rows_y + $row * $L(row_pitch)}]
                set mid [expr {$ry + $L(btn_h) / 2}]
                dui add dtext $page $lab_x $mid -tags ${key}_label -text [translate $label] \
                    -font $L(font_body) -width $L(sec_label_w) -fill $L(text_body) -anchor w -justify left
                dui add dtext $page $val_x $mid -tags $value_tag -text "" \
                    -font $L(font_primary) -width $val_w -fill $L(value_blue) -anchor w -justify left
                dui add dbutton $page $btn_x1 $ry $btn_x2 [expr {$ry + $L(btn_h)}] \
                    -tags ${key}_btn -label [translate $btn_label] \
                    -command [list ::plugins::GrindAdvisor::_tap $page ${key}_btn ::dui::pages::GrindAdvisor_settings::$btn_cmd] \
                    -label_font $L(font_button) -style ga_btn
                incr row
            }
        }

        # Calibration Accuracy gauge: second row of the Recommendation card.
        # 10 rounded segments at the value column; score text (caption size,
        # so "100% -- Excellent" always fits) to their right; no button.
        set reco_rows_y [expr {$L(sec_top) + $L(sec_pad) + $L(sec_title_h) + $L(md)}]
        set gy [expr {$reco_rows_y + 1 * $L(row_pitch)}]
        set gmid [expr {$gy + $L(btn_h) / 2}]
        set glab_x [expr {$c2x + $L(sec_pad)}]
        set gval_x [expr {$c2x + $L(sec_value_dx)}]
        dui add dtext $page $glab_x $gmid -tags conf_label -text [translate "Confidence"] \
            -font $L(font_body) -width $L(sec_label_w) -fill $L(text_body) -anchor w -justify left
        set seg_y0 [expr {$gy + ($L(btn_h) - $L(conf_seg_h)) / 2}]
        set seg_y1 [expr {$seg_y0 + $L(conf_seg_h)}]
        for {set i 0} {$i < $L(conf_segments)} {incr i} {
            set sx0 [expr {$gval_x + $i * ($L(conf_seg_w) + $L(conf_seg_gap))}]
            ::plugins::GrindAdvisor::rounded_rect $page $sx0 $seg_y0 [expr {$sx0 + $L(conf_seg_w)}] $seg_y1 \
                $L(conf_seg_r) -fill $L(conf_empty) -outline $L(conf_empty) -width 1 -tags conf_seg$i
        }
        set conf_text_x [expr {$gval_x + $L(conf_segments) * ($L(conf_seg_w) + $L(conf_seg_gap)) - $L(conf_seg_gap) + $L(lg)}]
        dui add dtext $page $conf_text_x $gmid -tags conf_text -text "" \
            -font $L(font_caption) -width [expr {$c2x + $col_w - $L(sec_pad) - $conf_text_x}] \
            -fill $L(text_body) -anchor w -justify left
        # v3.24.0 (F24): one next step under the row, below High only, from
        # facts GA computes (refresh_confidence; "" when there is none).
        # Top at the row's bottom edge, one caption line (conf_step_h), the
        # card's inner width; the card's sec_pad stays below it.
        dui add dtext $page $glab_x [expr {$gy + $L(btn_h)}] -tags conf_step -text "" \
            -font $L(font_caption) -width [expr {$col_w - 2 * $L(sec_pad)}] \
            -fill $L(text_body) -anchor nw -justify left

        # Bottom bar, outside any card: Done left, Advanced right.
        # v3.21.0 (F17): Help one slot left of Advanced, an md gap apart
        # (BeanScanner's Diagnostics | Help), so Advanced keeps its corner.
        # Tag ga_help: unique across plugins (the press flash repaints a
        # same-named <tag>-btn on every page).
        dui add dbutton $page $lx $L(bar_y0) [expr {$lx + $L(btn_w_std)}] $L(bar_y1) \
            -tags page_done -label [translate "Done"] \
            -command [list ::plugins::GrindAdvisor::_tap $page page_done ::dui::pages::GrindAdvisor_settings::page_done] \
            -label_font $L(font_button) -style ga_btn
        dui add dbutton $page [expr {$rx - $L(btn_w_std)}] $L(bar_y0) $rx $L(bar_y1) \
            -tags advanced -label [translate "Advanced"] \
            -command [list ::plugins::GrindAdvisor::_tap $page advanced {::plugins::GrindAdvisor::open_settings_dialog GrindAdvisor_advanced}] \
            -label_font $L(font_button) -style ga_btn
        set help_x1 [expr {$rx - $L(btn_w_std) - $L(md)}]
        dui add dbutton $page [expr {$help_x1 - $L(btn_w_std)}] $L(bar_y0) $help_x1 $L(bar_y1) \
            -tags ga_help -label [translate "Help"] \
            -command [list ::plugins::GrindAdvisor::_tap $page ga_help {::plugins::GrindAdvisor::open_settings_dialog GrindAdvisor_help}] \
            -label_font $L(font_button) -style ga_btn
    }

    # v3.17.4 (F22): the values are written before the page appears; the
    # Calibration Accuracy gauge reads SDB (200 rows), so load parks it on
    # "Reading shots..." and show fills it, as before (owner 2026-10-01:
    # placeholder, then fill -- no added tap delay, never last visit's score).
    proc load { page_to_hide page_to_show args } {
        return [::plugins::GrindAdvisor::_page_load "settings page" $page_to_show {
            ::plugins::GrindAdvisor::apply_defaults
            _refresh_texts $page_to_show
            _conf_placeholder $page_to_show
        }]
    }

    proc show { page_to_hide page_to_show } {
        variable data
        ::plugins::GrindAdvisor::_capture_return_page $page_to_hide
        if {![::plugins::GrindAdvisor::_page_is_current $page_to_show]} { return }
        ::plugins::GrindAdvisor::apply_defaults
        refresh_values $page_to_show
    }

    proc refresh_values {page} {
        _refresh_texts $page
        refresh_confidence $page
    }

    # Everything on the page that needs no database read.
    proc _refresh_texts {page} {
        variable data
        set data(popup_theme_value) [string totitle $::plugins::GrindAdvisor::settings(popup_theme)]
        set data(rounding_value) $::plugins::GrindAdvisor::settings(grind_rounding_increment)
        if {[string is true -strict $::plugins::GrindAdvisor::settings(enable_popup)]} {
            set data(enable_popup_value) [translate "On"]
        } else {
            set data(enable_popup_value) [translate "Off"]
        }
        catch { dui item config $page popup_theme_value -text $data(popup_theme_value) }
        catch { dui item config $page rounding_value -text $data(rounding_value) }
        catch { dui item config $page enable_popup_value -text $data(enable_popup_value) }
        # v3.17.0 (F5): stepper values and their greyed ends.
        foreach key {target_time grinder_min grinder_max} {
            ::plugins::GrindAdvisor::_stepper_refresh $page $key
        }
        # v3.12.0: page-theme button face follows the current theme.
        catch { dui item config $page btn_theme \
            -label [::plugins::GrindAdvisor::_theme_button_face] }
    }

    # v3.17.4 (F22): the gauge empty, its line reading "Reading shots...",
    # until refresh_confidence has read SDB (in show).
    proc _conf_placeholder {page} {
        upvar #0 ::plugins::GrindAdvisor::L L
        for {set i 0} {$i < $L(conf_segments)} {incr i} {
            catch { dui item config $page conf_seg$i -fill $L(conf_empty) -outline $L(conf_empty) }
        }
        # v3.19.1: "Reading..." -- "Reading shots..." was wider than the
        # 114 px gauge column and wrapped. v3.24.0 (F23): the one ellipsis
        # glyph; the next step stays empty until show has read SDB.
        catch { dui item config $page conf_text -text "[translate Reading][::plugins::GrindAdvisor::_char ellipsis]" }
        catch { dui item config $page conf_step -text "" }
    }

    # Calibration Accuracy gauge (v2.1.0, display-only; read-only fetch).
    proc refresh_confidence {page} {
        upvar #0 ::plugins::GrindAdvisor::L L
        set conf [::plugins::GrindAdvisor::calibration_confidence]
        if {[dict exists $conf ok] && [dict get $conf ok]} {
            set score [dict get $conf score]
            set filled [expr {int(round($score / 10.0))}]
            # v3.19.0 (F15 plain words): the word the popup uses; the ten
            # segments already show the score (Why? keeps the number). The
            # old "85% - Excellent" was wider than this column.
            set txt [string totitle [::plugins::GrindAdvisor::_band_plain [dict get $conf band]]]
        } else {
            set filled 0
            set txt [translate "Too few shots"]
        }
        for {set i 0} {$i < $L(conf_segments)} {incr i} {
            set color $L(conf_empty)
            if {$i < $filled} { set color $L(conf_fill) }
            catch { dui item config $page conf_seg$i -fill $color -outline $color }
        }
        catch { dui item config $page conf_text -text $txt }
        # v3.24.0 (F24): the next step ("" at High and above, or with no
        # grounded step; a dict without the key shows none).
        catch { dui item config $page conf_step -text [::plugins::GrindAdvisor::_dget $conf step] }
    }

    proc toggle_enable_popup {} {
        # Flips the same enable_popup 0/1 setting the old checkbox bound to.
        if {[string is true -strict $::plugins::GrindAdvisor::settings(enable_popup)]} {
            set ::plugins::GrindAdvisor::settings(enable_popup) 0
        } else {
            set ::plugins::GrindAdvisor::settings(enable_popup) 1
        }
        save_settings
        refresh_values GrindAdvisor_settings
    }

    proc toggle_popup_theme {} {
        if {$::plugins::GrindAdvisor::settings(popup_theme) eq "light"} {
            set ::plugins::GrindAdvisor::settings(popup_theme) dark
        } else {
            set ::plugins::GrindAdvisor::settings(popup_theme) light
        }
        save_settings
        refresh_values GrindAdvisor_settings
    }

    proc cycle_rounding {} {
        set values {0.1 0.25 0.5 1.0}
        set idx [lsearch -exact $values $::plugins::GrindAdvisor::settings(grind_rounding_increment)]
        if {$idx < 0} { set idx 1 }
        set idx [expr {($idx + 1) % [llength $values]}]
        set ::plugins::GrindAdvisor::settings(grind_rounding_increment) [lindex $values $idx]
        save_settings
        refresh_values GrindAdvisor_settings
    }

    proc save_settings {} {
        ::plugins::GrindAdvisor::save_settings
    }

    proc page_done {} {
        ::plugins::GrindAdvisor::save_settings
        ::plugins::GrindAdvisor::_exit_settings
    }
}

namespace eval ::dui::pages::GrindAdvisor_history_options {
    # v3.17.1 (F19): three cards of full-row toggles in one row (was a
    # two-column grid of 20 px dcheckboxes, box and label separate targets).
    # Each 60 px row: label left, a square / square-check glyph right (value
    # blue when on, muted when off), and one invisible core dbutton over the
    # whole row -- MaintenanceTracker's card-tap mechanism: shape-less,
    # label-less, no press fill. A tap flips the setting and saves at once,
    # as the checkboxes did. The settings, grouped by what they show (v3.20.0
    # adds Bag Name, the eleventh; every card still holds at most four rows).
    # v3.24.0 (F23): every row label in sentence case.
    variable groups {
        sec_hgrind "Grind" {
            history_show_set_grind "Set grind"
            history_show_recommended_grind "Recommended grind"
            history_show_reason "Recommendation reason"
        }
        sec_hdose "Dose and yield" {
            history_show_set_dose "Set dose"
            history_show_set_ratio "Set ratio"
            history_show_set_yield "Set yield"
            history_show_actual_yield "Actual yield"
        }
        sec_hshot "Shot" {
            history_show_datetime "Date & time"
            history_show_shot_time "Shot time"
            history_show_bag_shot "Bag shot number"
            history_show_bag_name "Bag name"
        }
    }

    proc setup {} {
        variable groups
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::GrindAdvisor::L L
        ::plugins::GrindAdvisor::_page_bg $page
        set lx $L(left_x)
        set cx $L(center_x)

        dui add dtext $page $cx $L(header_title_y) -tags page_title -text [translate "History display options"] \
            -font $L(font_title) -width $L(content_w) -fill $L(text_hi) -anchor center -justify center
        dui add dtext $page $cx $L(header_subtitle_y) -tags subtitle \
            -text [translate "Choose which fields each history card shows."] \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) -anchor center -justify center

        # Equal cards; the tallest holds four rows.
        set card_w $L(hopt_card_w)
        set card_h [expr {2 * $L(sec_pad) + $L(sec_title_h) + $L(md) + 4 * $L(row_pitch) - $L(md)}]
        set tog_font $L(font_body)
        if {[::plugins::GrindAdvisor::_toggle_icons]} { set tog_font $L(font_icon) }
        set c 0
        foreach {tag title rows} $groups {
            set x [expr {$lx + $c * ($card_w + $L(sec_gutter))}]
            set rows_y [::plugins::GrindAdvisor::_sec_card $page $tag $x $L(sec_top) $card_w $card_h $title]
            set x0 [expr {$x + $L(sec_pad)}]
            set x1 [expr {$x + $card_w - $L(sec_pad)}]
            set r 0
            foreach {key label} $rows {
                set ry [expr {$rows_y + $r * $L(row_pitch)}]
                set mid [expr {$ry + $L(btn_h) / 2}]
                dui add dtext $page $x0 $mid -tags ${key}_label -text [translate $label] \
                    -font $L(font_body) -width [expr {$x1 - $L(tog_w) - $L(lg) - $x0}] \
                    -fill $L(text_body) -anchor w -justify left
                dui add dtext $page $x1 $mid -tags ${key}_tog \
                    -text [::plugins::GrindAdvisor::_toggle_face [_on $key]] \
                    -font $tog_font -fill [_tog_fill $key] -anchor e -justify right
                # After the texts, so its tap rect sits above them.
                dui add dbutton $page $x0 $ry $x1 [expr {$ry + $L(btn_h)}] \
                    -tags ${key}_row \
                    -command [list ::dui::pages::GrindAdvisor_history_options::toggle $key]
                incr r
            }
            incr c
        }

        dui add dbutton $page $lx $L(bar_y0) [expr {$lx + $L(btn_w_std)}] $L(bar_y1) \
            -tags page_done -label [translate "Back"] \
            -command [list ::plugins::GrindAdvisor::_tap $page page_done ::dui::pages::GrindAdvisor_history_options::page_done] \
            -label_font $L(font_button) -style ga_btn
    }

    proc _on {key} {
        return [string is true -strict [::plugins::GrindAdvisor::_setting $key 0]]
    }

    proc _tog_fill {key} {
        upvar #0 ::plugins::GrindAdvisor::L L
        if {[_on $key]} { return $L(value_blue) }
        return $L(text_mut)
    }

    # Every row's glyph and colour from its setting and the current palette
    # (show, each tap, and the live theme switch).
    proc render {page} {
        variable groups
        foreach {tag title rows} $groups {
            foreach {key label} $rows {
                catch { dui item config $page ${key}_tog \
                    -text [::plugins::GrindAdvisor::_toggle_face [_on $key]] -fill [_tog_fill $key] }
            }
        }
    }

    proc toggle {key} {
        set ::plugins::GrindAdvisor::settings($key) [expr {[_on $key] ? 0 : 1}]
        ::plugins::GrindAdvisor::save_settings
        render GrindAdvisor_history_options
    }

    proc show { page_to_hide page_to_show } {
        ::plugins::GrindAdvisor::apply_defaults
        render $page_to_show
    }

    # v3.17.2 (F13): Back, one level, to Advanced.
    proc page_done {} {
        ::plugins::GrindAdvisor::save_settings
        ::plugins::GrindAdvisor::_back_to_advanced
    }
}

namespace eval ::dui::pages::GrindAdvisor_advanced {
    # v2.0.0: Advanced gathers the popup tuning values plus every secondary
    # page (History Display Options, Diagnostics, Calculation Details, Help).
    # v3.17.0: the tuning values are steppers (no keyboard).
    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::GrindAdvisor::L L
        ::plugins::GrindAdvisor::_page_bg $page
        set lx $L(left_x)
        set rx $L(right_x)
        set cx $L(center_x)

        dui add dtext $page $cx $L(header_title_y) -tags page_title -text [translate "Advanced"] \
            -font $L(font_title) -width $L(content_w) -fill $L(text_hi) -anchor center -justify center
        dui add dtext $page $cx $L(header_subtitle_y) -tags version_text \
            -text "Grind Advisor $::plugins::GrindAdvisor::version[::plugins::GrindAdvisor::_sep]tuning and tools" \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) -anchor center -justify center

        # v3.0.0 section cards. The Regression Forecast method has no user
        # tuning (its constants are fixed). v3.17.0 (F5): the popup values
        # are steppers. v3.17.3 (F18): grouped by purpose instead of a
        # six-button Tools wall -- SETTINGS (left: the two popup values,
        # then Dose / Yield Source and History Display Options) and INSPECT
        # (right, under Shot Data: Diagnostics, Calculation Details, Help,
        # Bag Stats in a 2x2 grid). Same buttons, tags and commands; the
        # card tags sec_ptun / sec_tools are kept for the retheme walk.
        # v3.21.0 (F17): Help moved to the main page; Inspect holds three.
        set col_w $L(sec_col_w)
        set c2x $L(sec_col2_x)
        set ptun_h [expr {2 * $L(sec_pad) + $L(sec_title_h) + $L(md) + 4 * $L(row_pitch) - $L(md)}]
        set tools_h [expr {2 * $L(sec_pad) + $L(sec_title_h) + $L(md) + 2 * $L(row_pitch) - $L(md)}]

        set rows_y [::plugins::GrindAdvisor::_sec_card $page sec_ptun $lx $L(sec_top) $col_w $ptun_h "Settings"]
        set lab_x [expr {$lx + $L(sec_pad)}]
        set step_x2 [expr {$lx + $col_w - $L(sec_pad)}]
        set row 0
        foreach {key label} {
            popup_delay_ms "Popup delay (ms)"
            popup_font_scale "Popup font scale"
        } {
            set ry [expr {$rows_y + $row * $L(row_pitch)}]
            dui add dtext $page $lab_x [expr {$ry + $L(btn_h) / 2}] -tags ${key}_label \
                -text [translate $label] -font $L(font_body) \
                -width [expr {$step_x2 - $L(step_w) - $L(lg) - $lab_x}] \
                -fill $L(text_body) -anchor w -justify left
            ::plugins::GrindAdvisor::_add_stepper $page $key $step_x2 $ry
            incr row
        }
        # v3.17.3 (F18): the two settings pages, full card width, rows 3-4.
        # v3.24.0 (F23): button labels in sentence case, as the pages' titles.
        foreach {tag label target} [list \
            dose_yield_source "Dose / yield source" GrindAdvisor_dose_yield \
            history_display_options "History display options" GrindAdvisor_history_options] {
            set ry [expr {$rows_y + $row * $L(row_pitch)}]
            dui add dbutton $page $lab_x $ry $step_x2 [expr {$ry + $L(btn_h)}] \
                -tags $tag -label [translate $label] \
                -command [list ::plugins::GrindAdvisor::_tap $page $tag [list ::plugins::GrindAdvisor::open_settings_dialog $target]] \
                -label_font $L(font_button) -style ga_btn
            incr row
        }

        # Shot Data card (v3.9.0), top right. One button plus a status line
        # that starts as its explanation and is replaced by the result.
        # Height budget: pad, title, md, button, md, two caption lines, pad;
        # the note is kept short enough not to wrap past two lines, so the
        # card ends clear of the Inspect card below it.
        set data_note_h [expr {int(round(32 * $L(scale)))}]
        set data_h [expr {2 * $L(sec_pad) + $L(sec_title_h) + $L(md) \
                          + $L(btn_h) + $L(md) + $data_note_h}]
        set drows_y [::plugins::GrindAdvisor::_sec_card $page sec_data $c2x $L(sec_top) \
            $col_w $data_h "Shot data"]
        dui add dbutton $page [expr {$c2x + $L(sec_pad)}] $drows_y \
            [expr {$c2x + $col_w - $L(sec_pad)}] [expr {$drows_y + $L(btn_h)}] \
            -tags recalc_from_history -label [translate "Recalculate from history"] \
            -command [list ::plugins::GrindAdvisor::_tap $page recalc_from_history ::dui::pages::GrindAdvisor_advanced::recalculate] \
            -label_font $L(font_button) -style ga_btn
        dui add dtext $page [expr {$c2x + $L(sec_pad)}] \
            [expr {$drows_y + $L(btn_h) + $L(md)}] -tags recalc_note \
            -text [::dui::pages::GrindAdvisor_advanced::_default_note] \
            -font $L(font_caption) -width [expr {$col_w - 2 * $L(sec_pad)}] \
            -fill $L(text_mut) -anchor nw -justify left

        # v3.17.3 (F18): INSPECT card, right column under Shot Data, 2x2
        # grid of the read-only views (was the full-width "Tools" card).
        set tools_y [expr {$L(sec_top) + $data_h + $L(sec_gap)}]
        set rows_y [::plugins::GrindAdvisor::_sec_card $page sec_tools $c2x $tools_y $col_w $tools_h "Inspect"]
        set inner_w [expr {$col_w - 2 * $L(sec_pad)}]
        set half_w [expr {($inner_w - $L(lg)) / 2}]
        set bx0 [expr {$c2x + $L(sec_pad)}]
        set bx1 [expr {$bx0 + $half_w + $L(lg)}]
        # v3.21.0 (F17): Help left for the main page's bottom bar (one
        # parent), so Bag Stats moves up into its slot: Diagnostics |
        # Calculation Details over Bag Stats.
        foreach {c r tag label target} [list \
            0 0 diagnostics "Diagnostics" GrindAdvisor_diagnostics \
            1 0 calculation_details "Calculation details" GrindAdvisor_calculation_details] {
            set bx [expr {$c == 0 ? $bx0 : $bx1}]
            set by [expr {$rows_y + $r * $L(row_pitch)}]
            dui add dbutton $page $bx $by [expr {$bx + $half_w}] [expr {$by + $L(btn_h)}] \
                -tags $tag -label [translate $label] \
                -command [list ::plugins::GrindAdvisor::_tap $page $tag [list ::plugins::GrindAdvisor::open_settings_dialog $target]] \
                -label_font $L(font_button) -style ga_btn
        }
        # v3.6.0: Bag Stats opens the overlay card list (same mechanism as
        # History), not a dui page, so it has its own command.
        set by [expr {$rows_y + $L(row_pitch)}]
        dui add dbutton $page $bx0 $by [expr {$bx0 + $half_w}] [expr {$by + $L(btn_h)}] \
            -tags bag_stats -label [translate "Bag stats"] \
            -command [list ::plugins::GrindAdvisor::_tap $page bag_stats ::plugins::GrindAdvisor::show_bag_stats] \
            -label_font $L(font_button) -style ga_btn

        dui add dbutton $page $lx $L(bar_y0) [expr {$lx + $L(btn_w_std)}] $L(bar_y1) \
            -tags page_done -label [translate "Back"] \
            -command [list ::plugins::GrindAdvisor::_tap $page page_done ::dui::pages::GrindAdvisor_advanced::page_done] \
            -label_font $L(font_button) -style ga_btn
    }

    # v3.17.4 (F22): the note and stepper values are reset before the page
    # appears (also on every Back from a tool page, a dui page load); show
    # repeats it for the button states, which need the items visible.
    proc load { page_to_hide page_to_show args } {
        return [::plugins::GrindAdvisor::_page_load "Advanced" $page_to_show {
            _refresh $page_to_show
        }]
    }

    proc show { page_to_hide page_to_show } {
        if {![::plugins::GrindAdvisor::_page_is_current $page_to_show]} { return }
        _refresh $page_to_show
    }

    proc _refresh {page} {
        ::plugins::GrindAdvisor::apply_defaults
        foreach key {popup_delay_ms popup_font_scale} {
            ::plugins::GrindAdvisor::_stepper_refresh $page $key
        }
        # Back to the explanation: a status line from a previous visit would
        # read as the result of something that just happened.
        # v3.16.8: unless a run is still going (the user left and came back
        # while SDB was syncing): then the button stays greyed and the note
        # says so until the next progress line replaces it.
        variable recalc_running
        # v3.23.0: back to the muted ink (a failure's danger ink is for the
        # visit that saw it).
        _note_ink $page 0
        if {$recalc_running} {
            catch { dui item disable $page recalc_from_history* }
            catch { dui item config $page recalc_note -text [_working_note] }
        } else {
            catch { dui item config $page recalc_note -text [_default_note] }
        }
    }

    # v3.24.0 (F23): "Working" and the one ellipsis glyph (was "...").
    proc _working_note {} {
        return "[translate Working][::plugins::GrindAdvisor::_char ellipsis]"
    }

    # Deliberately short: the card's note area is two caption lines, and a
    # third would spill past the card into the Inspect card below.
    proc _default_note {} {
        return [translate "Re-reads edited shots into SDB and recomputes this bag."]
    }

    # v3.16.8 (F4): 1 while this button's run is in progress. Cleared in the
    # finally below, so it can never stick.
    variable recalc_running 0

    # v3.16.8: SDB's progress line ("Synchronizing DB: 120/1203 (9%)") shown
    # in the note while the run lasts; SDB repaints right after setting it.
    proc _progress {args} {
        catch { dui item config GrindAdvisor_advanced recalc_note \
            -text $::plugins::SDB::progress_msg }
    }

    # v3.9.0. The whole chain lives in ::plugins::GrindAdvisor::refresh_from
    # _history; this only reports what it did.
    # v3.16.8 (F4): one run at a time, the way SDB's own Resync works: a tap
    # that arrives while SDB is syncing (populate yields every ten files)
    # does nothing if it is this button's own run, and is refused with a
    # note if SDB is busy for another reason; the button is disabled for the
    # run (dui item disable, SDB_settings::resync_db's call) and the note
    # follows SDB's progress_msg. Everything is restored in `finally`.
    proc recalculate {} {
        variable recalc_running
        set page GrindAdvisor_advanced
        if {$recalc_running} { return }
        if {[::plugins::GrindAdvisor::_sdb_busy]} {
            _note_ink $page 0
            catch { dui item config $page recalc_note \
                -text [translate "SDB is updating its database. Try again when it finishes."] }
            catch { msg "GrindAdvisor: recalculate refused, SDB is busy" }
            return
        }
        set recalc_running 1
        set traced 0
        set status ""
        set failed 0
        try {
            dui item disable $page recalc_from_history*
            catch { dui item config $page recalc_note -text [_working_note] }
            if {[info exists ::plugins::SDB::progress_msg]} {
                trace add variable ::plugins::SDB::progress_msg write \
                    ::dui::pages::GrindAdvisor_advanced::_progress
                set traced 1
            }
            if {[catch { set status [::plugins::GrindAdvisor::refresh_from_history] } err]} {
                catch { msg "GrindAdvisor: recalculate failed: $err" }
                set status [translate "Failed: see the app log"]
                set failed 1
            } elseif {$::plugins::GrindAdvisor::refresh_failed} {
                set failed 1
            }
        } finally {
            # The flag first: nothing after it can leave the button blocked.
            set recalc_running 0
            if {$traced} {
                catch { trace remove variable ::plugins::SDB::progress_msg write \
                    ::dui::pages::GrindAdvisor_advanced::_progress }
            }
            catch { dui item enable $page recalc_from_history* }
            # v3.23.0 (F21): a failure reads in the danger role; anything
            # else stays muted (_refresh puts the muted ink back on load).
            _note_ink $page $failed
            catch { dui item config $page recalc_note -text $status }
        }
    }

    # The note's ink: danger after a failure, else muted (the page's
    # palette at the time of the call).
    proc _note_ink {page failed} {
        upvar #0 ::plugins::GrindAdvisor::L L
        if {![info exists L(text_mut)] || ![info exists L(danger)]} { return }
        set ink $L(text_mut)
        if {$failed} { set ink $L(danger) }
        catch { dui item config $page recalc_note -fill $ink }
    }

    proc page_done {} {
        ::plugins::GrindAdvisor::save_settings
        ::plugins::GrindAdvisor::_exit_subpage
    }
}

namespace eval ::dui::pages::GrindAdvisor_help {
    # v3.21.0 (design review F17): Help in plain words -- three headed
    # sections, one per page (the card title is the section name), each
    # paragraph wrapped at <= 90 characters (the old guide ran 130-160 and
    # explained rungs, damping and decay constants; those live in the README
    # and under Why? / Calculation Details). Opened from the main page's
    # Help button; Back returns there (one load, its only parent).
    variable wrap_chars 90
    variable sections {
        "What it does" {
            {After every espresso, Grind Advisor reads the shot you just pulled and suggests the grind setting for your next one.}
            {It learns from the shots of the bag you have loaded: one shot gives a first nudge, two show how your coffee reacts, and from three shots on it fits a line through them and aims at your target time. A new bag, or a different profile, starts fresh.}
            {As on most grinders, a lower number means finer: "finer by 0.5" is 0.5 lower.}
            {It only reads your shots. It never edits them and never changes anything on the machine.}
        }
        "Daily use" {
            {Pull a shot as usual. A moment later a card shows the next grind and how sure it is, for example "finer by 0.5".}
            {Set your grinder to that number, enter the same number as the grind in the app (your skin's grind setting, or DYE), and pull the next shot. Grind Advisor learns from the grind saved with each shot.}
            {Confidence rises as the bag collects shots that land near your target time.}
            {Why? on the card shows how the number was worked out. History lists your recent shots with the grind each one suggested; Bag stats compares your bags.}
            {A new bag with no shots yet shows a starting estimate ("Start ~4.8") borrowed from bags you have already dialled in on the same profile.}
            {On the main page: your target shot time, your grinder's lowest and highest numbers, how finely the grind is rounded, and the popup's theme and whether it opens by itself.}
        }
        "If something looks wrong" {
            {No card after a shot: check that Automatic popup is On. Rinses, flushes, steam, cleaning and shots under 5 seconds are skipped on purpose, and so is a shot saved without a grind, dose or target yield.}
            {Advice for the wrong coffee, or it starts over: it follows the coffee loaded in the app (bean, roaster and roast date) and the profile. Changing any of them starts fresh, like a new bag.}
            {"Out of reach": even the end of your grinder cannot reach the target time. Change the dose or the yield instead.}
            {"Much faster than recent shots at this grind": check your puck prep.}
            {"4 of 5 shots": a shot whose dose or yield missed its target by more than 2 g is left out.}
            {You edited a shot in another plugin: Advanced > Recalculate from history.}
            {The full working is under Why? and Advanced > Calculation details.}
        }
    }

    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::GrindAdvisor::L L
        ::plugins::GrindAdvisor::_page_bg $page
        set lx $L(left_x)
        set cx $L(center_x)

        dui add dtext $page $cx $L(header_title_y) -tags page_title -text [translate "Help"] \
            -font $L(font_title) -width $L(content_w) -fill $L(text_hi) -anchor center -justify center
        dui add dtext $page $cx $L(header_subtitle_y) -tags version_text \
            -text "Grind Advisor $::plugins::GrindAdvisor::version" \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) -anchor center -justify center

        set card_h [expr {$L(bar_y0) - $L(md) - $L(sec_top)}]
        variable sections
        set rows_y [::plugins::GrindAdvisor::_sec_card $page sec_help $lx $L(sec_top) $L(content_w) $card_h \
            [lindex $sections 0]]
        # v3.6.0: text is paginated; v3.21.0: one section per page, its name
        # the card title (sec_help_title), Prev/Next flip sections.
        dui add dtext $page [expr {$lx + $L(sec_pad)}] $rows_y -tags help_text -text "" \
            -font $L(font_body) -width [expr {$L(content_w) - 2 * $L(sec_pad)}] -fill $L(text_body) -anchor nw -justify left

        dui add dbutton $page $lx $L(bar_y0) [expr {$lx + $L(btn_w_std)}] $L(bar_y1) \
            -tags page_done -label [translate "Back"] \
            -command [list ::plugins::GrindAdvisor::_tap $page page_done ::dui::pages::GrindAdvisor_help::page_done] \
            -label_font $L(font_button) -style ga_btn
        ::plugins::GrindAdvisor::_add_pager $page [namespace current]
    }

    # v3.17.4 (F22): page 1 is written before the page appears (it showed
    # the page the user left on, then jumped); the pager state, a raw -state
    # config, stays in show.
    proc load { page_to_hide page_to_show args } {
        return [::plugins::GrindAdvisor::_page_load "Help" $page_to_show {
            variable data
            _first_page
            _render_text $page_to_show
            ::plugins::GrindAdvisor::_pager_initial $page_to_show 0 [llength $data(pages)]
        }]
    }

    proc show { page_to_hide page_to_show } {
        if {![::plugins::GrindAdvisor::_page_is_current $page_to_show]} { return }
        _first_page
        _render $page_to_show
    }

    # v3.21.0: one page per section, paragraphs wrapped at wrap_chars and
    # separated by a blank line. A section that ever outgrows the card (a
    # longer translation, a bigger font) continues on a page titled
    # "<section> (2)" instead of clipping.
    proc _first_page {} {
        variable data
        variable sections
        variable wrap_chars
        set data(pages) {}
        set data(titles) {}
        foreach {title paras} $sections {
            set lines {}
            foreach para $paras {
                if {[llength $lines] > 0} { lappend lines "" }
                # Not translated, like the guide before it: a desktop build
                # appends every translation miss to translation.tcl.
                lappend lines [::plugins::GrindAdvisor::_wrap_text $para $wrap_chars]
            }
            set n 0
            foreach pg [::plugins::GrindAdvisor::_paginate_text [join $lines "\n"] 19 $wrap_chars] {
                incr n
                lappend data(pages) $pg
                if {$n == 1} {
                    lappend data(titles) [translate $title]
                } else {
                    lappend data(titles) "[translate $title] ($n)"
                }
            }
        }
        set data(page_idx) 0
    }

    proc _render_text {page} {
        variable data
        set total [llength $data(pages)]
        catch { dui item config $page help_text -text [lindex $data(pages) $data(page_idx)] }
        catch { dui item config $page sec_help_title -text [lindex $data(titles) $data(page_idx)] }
        # v3.23.0 (F21): "Page 1 of 3" ("" for one page), every pager.
        set ind [::plugins::GrindAdvisor::_page_count $data(page_idx) $total]
        catch { dui item config $page pg_ind -text $ind }
    }

    proc _render {page} {
        variable data
        _render_text $page
        ::plugins::GrindAdvisor::_pager_state $page $data(page_idx) [llength $data(pages)]
    }

    proc _pg {delta} {
        variable data
        set new [expr {$data(page_idx) + $delta}]
        if {$new < 0 || $new >= [llength $data(pages)]} { return }
        set data(page_idx) $new
        _render GrindAdvisor_help
    }

    # v3.21.0 (F17): Help's one parent is the main page (its Help button),
    # so Back is one load of GrindAdvisor_settings -- Advanced's own proven
    # Back (_exit_subpage). It no longer opens from Advanced.
    proc page_done {} {
        ::plugins::GrindAdvisor::_exit_subpage
    }
}

namespace eval ::dui::pages::GrindAdvisor_diagnostics {
    variable data
    array set data {
        diagnostics_text {}
    }

    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::GrindAdvisor::L L
        ::plugins::GrindAdvisor::_page_bg $page
        set lx $L(left_x)
        set cx $L(center_x)

        dui add dtext $page $cx $L(header_title_y) -tags page_title -text [translate "Diagnostics"] \
            -font $L(font_title) -width $L(content_w) -fill $L(text_hi) -anchor center -justify center
        dui add dtext $page $cx $L(header_subtitle_y) -tags subtitle \
            -text [translate "Detected SDB source and columns. Read-only."] \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) -anchor center -justify center

        set card_h [expr {$L(bar_y0) - $L(md) - $L(sec_top)}]
        set rows_y [::plugins::GrindAdvisor::_sec_card $page sec_diag $lx $L(sec_top) $L(content_w) $card_h "Detected fields"]
        dui add dtext $page [expr {$lx + $L(sec_pad)}] $rows_y -tags diagnostics_text -text "" \
            -font $L(font_body) -width [expr {$L(content_w) - 2 * $L(sec_pad)}] -fill $L(text_body) -anchor nw -justify left

        dui add dbutton $page $lx $L(bar_y0) [expr {$lx + $L(btn_w_std)}] $L(bar_y1) \
            -tags page_done -label [translate "Back"] \
            -command [list ::plugins::GrindAdvisor::_tap $page page_done ::dui::pages::GrindAdvisor_diagnostics::page_done] \
            -label_font $L(font_button) -style ga_btn
        ::plugins::GrindAdvisor::_add_pager $page [namespace current]
    }

    # v3.17.4 (F22): the fields come from SDB schema reads, so load parks the
    # text on a placeholder (never the last visit's fields) and show reads.
    proc load { page_to_hide page_to_show args } {
        return [::plugins::GrindAdvisor::_page_load "Diagnostics" $page_to_show {
            ::plugins::GrindAdvisor::_reading_placeholder $page_to_show diagnostics_text
        }]
    }

    proc show { page_to_hide page_to_show } {
        variable data
        if {![::plugins::GrindAdvisor::_page_is_current $page_to_show]} { return }
        set data(pages) [::plugins::GrindAdvisor::_paginate_text \
            [::plugins::GrindAdvisor::detected_fields_text] 19 115]
        set data(page_idx) 0
        _render $page_to_show
    }

    proc _render {page} {
        variable data
        set total [llength $data(pages)]
        catch { dui item config $page diagnostics_text -text [lindex $data(pages) $data(page_idx)] }
        set ind [::plugins::GrindAdvisor::_page_count $data(page_idx) $total]
        catch { dui item config $page pg_ind -text $ind }
        ::plugins::GrindAdvisor::_pager_state $page $data(page_idx) $total
    }

    proc _pg {delta} {
        variable data
        set new [expr {$data(page_idx) + $delta}]
        if {$new < 0 || $new >= [llength $data(pages)]} { return }
        set data(page_idx) $new
        _render GrindAdvisor_diagnostics
    }

    # v3.17.2 (F13): Back, one level, to Advanced.
    proc page_done {} {
        ::plugins::GrindAdvisor::_back_to_advanced
    }
}

namespace eval ::dui::pages::GrindAdvisor_calculation_details {
    variable data
    array set data {
        calculation_text {}
    }

    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::GrindAdvisor::L L
        ::plugins::GrindAdvisor::_page_bg $page
        set lx $L(left_x)
        set cx $L(center_x)

        dui add dtext $page $cx $L(header_title_y) -tags page_title -text [translate "Calculation details"] \
            -font $L(font_title) -width $L(content_w) -fill $L(text_hi) -anchor center -justify center
        dui add dtext $page $cx $L(header_subtitle_y) -tags subtitle \
            -text [translate "How the latest recommendation was computed. Read-only."] \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) -anchor center -justify center

        set card_h [expr {$L(bar_y0) - $L(md) - $L(sec_top)}]
        set rows_y [::plugins::GrindAdvisor::_sec_card $page sec_calcd $lx $L(sec_top) $L(content_w) $card_h "Latest calculation"]
        # v2.2.0: caption font so the per-shot trace fits below the summary
        # block without overflowing the card.
        dui add dtext $page [expr {$lx + $L(sec_pad)}] $rows_y -tags calculation_text -text "" \
            -font $L(font_caption) -width [expr {$L(content_w) - 2 * $L(sec_pad)}] -fill $L(text_body) -anchor nw -justify left

        dui add dbutton $page $lx $L(bar_y0) [expr {$lx + $L(btn_w_std)}] $L(bar_y1) \
            -tags page_done -label [translate "Back"] \
            -command [list ::plugins::GrindAdvisor::_tap $page page_done ::dui::pages::GrindAdvisor_calculation_details::page_done] \
            -label_font $L(font_button) -style ga_btn
        ::plugins::GrindAdvisor::_add_pager $page [namespace current]
    }

    # v3.17.4 (F22): the calculation reads SDB twice, so load parks the text
    # on a placeholder (never the last visit's numbers) and show reads.
    proc load { page_to_hide page_to_show args } {
        return [::plugins::GrindAdvisor::_page_load "Calculation details" $page_to_show {
            ::plugins::GrindAdvisor::_reading_placeholder $page_to_show calculation_text
        }]
    }

    proc show { page_to_hide page_to_show } {
        variable data
        if {![::plugins::GrindAdvisor::_page_is_current $page_to_show]} { return }
        # v3.6.0: summary + 5-shot trace is ~1.5 cards tall at caption
        # size and used to clip under the bottom bar; now paginated.
        set data(pages) [::plugins::GrindAdvisor::_paginate_text \
            "[::plugins::GrindAdvisor::_calculation_diagnostics_text]\n\n[::plugins::GrindAdvisor::_shot_trace_text 5]" 23 135]
        set data(page_idx) 0
        _render $page_to_show
    }

    proc _render {page} {
        variable data
        set total [llength $data(pages)]
        catch { dui item config $page calculation_text -text [lindex $data(pages) $data(page_idx)] }
        set ind [::plugins::GrindAdvisor::_page_count $data(page_idx) $total]
        catch { dui item config $page pg_ind -text $ind }
        ::plugins::GrindAdvisor::_pager_state $page $data(page_idx) $total
    }

    proc _pg {delta} {
        variable data
        set new [expr {$data(page_idx) + $delta}]
        if {$new < 0 || $new >= [llength $data(pages)]} { return }
        set data(page_idx) $new
        _render GrindAdvisor_calculation_details
    }

    # v3.17.2 (F13): Back, one level, to Advanced.
    proc page_done {} {
        ::plugins::GrindAdvisor::_back_to_advanced
    }
}

namespace eval ::dui::pages::GrindAdvisor_dose_yield {
    # v2.3.0 sub-page (under Advanced). Mode selector + the four plausibility
    # bounds (steppers since v3.17.0).
    variable data
    array set data { mode_value {} }

    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::GrindAdvisor::L L
        ::plugins::GrindAdvisor::_page_bg $page
        set lx $L(left_x); set rx $L(right_x); set cx $L(center_x)

        dui add dtext $page $cx $L(header_title_y) -tags page_title -text [translate "Dose / yield source"] \
            -font $L(font_title) -width $L(content_w) -fill $L(text_hi) -anchor center -justify center
        dui add dtext $page $cx $L(header_subtitle_y) -tags subtitle \
            -text [translate "Whether recommendations report set or measured dose and yield."] \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) -anchor center -justify center

        # One full-width card: mode selector row, then the 4 bounds in two
        # columns. v3.17.0 (F5): steppers, each right-aligned in its column.
        set card_h [expr {2 * $L(sec_pad) + $L(sec_title_h) + $L(md) + $L(btn_h) + $L(md) + 2 * $L(row_pitch) - $L(md)}]
        set rows_y [::plugins::GrindAdvisor::_sec_card $page sec_dy $lx $L(sec_top) $L(content_w) $card_h "Source mode"]

        set mid [expr {$rows_y + $L(btn_h) / 2}]
        # v3.6.2: the button's right edge is inset by sec_pad so it keeps
        # the card's inner padding instead of sitting flush on the card
        # border (owner-reported; same rule every other in-card button
        # already follows).
        set btn_x2 [expr {$rx - $L(sec_pad)}]
        set btn_x1 [expr {$btn_x2 - $L(btn_w_std)}]
        dui add dtext $page [expr {$lx + $L(sec_pad)}] $mid -tags mode_label -text [translate "Dose / yield mode"] \
            -font $L(font_body) -width $L(sec_label_w) -fill $L(text_body) -anchor w -justify left
        dui add dtext $page [expr {$lx + $L(sec_value_dx)}] $mid -tags mode_value -text "" \
            -font $L(font_primary) -width [expr {$btn_x1 - $L(lg) - ($lx + $L(sec_value_dx))}] \
            -fill $L(value_blue) -anchor w -justify left
        dui add dbutton $page $btn_x1 $rows_y $btn_x2 [expr {$rows_y + $L(btn_h)}] \
            -tags mode_btn -label [translate "Next"] \
            -command [list ::plugins::GrindAdvisor::_tap $page mode_btn ::dui::pages::GrindAdvisor_dose_yield::cycle_mode] \
            -label_font $L(font_button) -style ga_btn

        set steppers_top [expr {$rows_y + $L(btn_h) + $L(md)}]
        set in_x0 [expr {$lx + $L(sec_pad)}]
        set in_x1 [expr {$rx - $L(sec_pad)}]
        set dcol_w [expr {($in_x1 - $in_x0 - $L(lg)) / 2}]
        foreach {c r key label} [list \
            0 0 dose_min  "Dose min (g)" \
            1 0 ratio_min "Ratio min" \
            0 1 dose_max  "Dose max (g)" \
            1 1 ratio_max "Ratio max"] {
            set label_x [expr {$c == 0 ? $in_x0 : $in_x0 + $dcol_w + $L(lg)}]
            set step_x2 [expr {$label_x + $dcol_w}]
            set ry [expr {$steppers_top + $r * $L(row_pitch)}]
            dui add dtext $page $label_x [expr {$ry + $L(btn_h) / 2}] -tags ${key}_label \
                -text [translate $label] -font $L(font_body) \
                -width [expr {$step_x2 - $L(step_w) - $L(lg) - $label_x}] \
                -fill $L(text_body) -anchor w -justify left
            ::plugins::GrindAdvisor::_add_stepper $page $key $step_x2 $ry
        }

        set cap_y [expr {$L(sec_top) + $card_h + $L(sec_gap)}]
        dui add dtext $page $lx $cap_y -tags dy_help -width $L(content_w) \
            -font $L(font_caption) -fill $L(text_mut) -anchor nw -justify left \
            -text [translate "Fixed always uses your set dose and target yield. Actual uses the measured dose and final yield when present. Auto uses measured values only when the dose is within Dose min/max and the ratio (yield/dose) is within Ratio min/max, otherwise it falls back to the set values; a missing or zero measurement always falls back. Plausibility bounds apply to Auto only. This choice affects what the popup, reason line, and Diagnostics report; it does not change the grind recommendation itself."]

        dui add dbutton $page $lx $L(bar_y0) [expr {$lx + $L(btn_w_std)}] $L(bar_y1) \
            -tags page_done -label [translate "Back"] \
            -command [list ::plugins::GrindAdvisor::_tap $page page_done ::dui::pages::GrindAdvisor_dose_yield::page_done] \
            -label_font $L(font_button) -style ga_btn
    }

    # v3.17.4 (F22): the mode and bounds are written before the page appears
    # (the mode used to paint blank on the first visit).
    proc load { page_to_hide page_to_show args } {
        return [::plugins::GrindAdvisor::_page_load "Dose / yield source" $page_to_show {
            ::plugins::GrindAdvisor::apply_defaults
            refresh_values $page_to_show
        }]
    }

    proc show { page_to_hide page_to_show } {
        if {![::plugins::GrindAdvisor::_page_is_current $page_to_show]} { return }
        ::plugins::GrindAdvisor::apply_defaults
        refresh_values $page_to_show
    }

    proc refresh_values {page} {
        variable data
        set data(mode_value) [::plugins::GrindAdvisor::_dose_yield_mode_label $::plugins::GrindAdvisor::settings(dose_yield_mode)]
        catch { dui item config $page mode_value -text $data(mode_value) }
        foreach key {dose_min dose_max ratio_min ratio_max} {
            ::plugins::GrindAdvisor::_stepper_refresh $page $key
        }
    }

    proc cycle_mode {} {
        set values {fixed actual auto}
        set idx [lsearch -exact $values $::plugins::GrindAdvisor::settings(dose_yield_mode)]
        if {$idx < 0} { set idx 2 }
        set idx [expr {($idx + 1) % [llength $values]}]
        set ::plugins::GrindAdvisor::settings(dose_yield_mode) [lindex $values $idx]
        ::plugins::GrindAdvisor::save_settings
        refresh_values GrindAdvisor_dose_yield
    }

    # v3.17.2 (F13): Back, one level, to Advanced.
    proc page_done {} {
        ::plugins::GrindAdvisor::save_settings
        ::plugins::GrindAdvisor::_back_to_advanced
    }
}

