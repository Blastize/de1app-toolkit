package require de1plus 1.0

#############################################################################
#
#  LUMEN  --  a glass dashboard skin for the Decent DE1
#
#  Author:  Blastize
#  Version: 0.57.5  (LAST SHOT reads the just-saved shot file, not the live grind; see `variable version`)
#
#
#
#  SAFETY STATUS: no database is opened. Nothing in history/ or history_v2/
#  is written, renamed or deleted -- ever, in any version.
#
#  READ access is limited to history/*.shot files, read one at a time and
#  only when a shot is being SELECTED for the home page (startup, a bag
#  cycle, a Shot History Editor change, the end of a cleaning run) -- never
#  on the 200 ms refresh tick. 0.43.0: load_last_shot_curves walks a short
#  candidate list (the loaded bean's newest shots, from SDB's public read
#  API, then the directory) and rejects cleaning / calibration / rinse
#  runs and sub-5 s aborts, so it may open a handful of files before one
#  passes. Each is parsed into a LOCAL array; the stock preview_history
#  does `array set ::settings $props(settings)`, which would overwrite the
#  live configuration with a stale one.
#
#  (Before 0.25.0 this block claimed nothing in history/ was read at all.
#  That was already untrue -- the curve loader has been there since 0.9.0.)
#
#  Every ::settings write happens only on an explicit tap, and every stepper
#  clamps its value so a runaway tap cannot write junk.
#
#  Preferences (Lumen settings page):
#    lumen_theme                     -- dark | light | custom
#    lumen_custom_base, lumen_custom_bh, lumen_custom_bs, lumen_custom_ah,
#    lumen_custom_as                 -- the custom theme's five inputs
#                                       (0.46.0; written by the picker's
#                                       Done only, clamped on read)
#  (0.36.0: the chart's Raw/Smooth and Stages pills are GONE, owner
#  request -- Lumen's charts are always smooth (catrom) with stage
#  separators shown; live_graph_smoothing_technique and
#  lumen_chart_stages are no longer read or written.)
#    lumen_bag_count                 -- how many recent bean bags the home
#                                       strip's bag cycler offers (3..10)
#    lumen_water_low_ml              -- the tank level under which the
#                                       taskbar water reading turns amber
#                                       (100..800 ml, step 50, default 300;
#                                       0.45.0; a Lumen preference, never
#                                       sent to the machine)
#
#  Next-shot steppers (home strip):
#    grinder_dose_weight             -- "Set dose" from the scale reading,
#                                       and the -/+ dose stepper (2..40)
#    grinder_setting                 -- the -/+ grind stepper (0..100)
#    final_desired_shot_weight       -- the -/+ yield stepper
#    final_desired_shot_weight_advanced -- same, when the profile is 2c
#
#  The bag cycler writes nothing directly: it calls DYE's own
#  ::plugins::DYE::shots::source_next_from, which owns that write. Lumen
#  opens no database and issues no SQL -- the bag list and the shot clock
#  come from SDB's public read API.
#  DYE's staged next_grinder_setting / next_grinder_dose_weight are kept in
#  step when DYE is loaded -- the same pairing DYE's own DSx2 stepper
#  performs (setup_DSx2.tcl change_grinder_setting). grinder_dose_weight is
#  the field shot.tcl records as the shot's dose, so that one is real data:
#  "Set dose" refuses a zero or negative reading.
#
#  Machine steppers (Lumen settings page, mirroring Streamline's column):
#    espresso_temperature            -- Brew, via the core's
#                                       change_espresso_temperature so step
#                                       and advanced profile frames follow
#    steam_timeout, steam_disabled   -- Steam time (0 = off)
#    flush_seconds                   -- Flush time (3..254)
#    water_volume                    -- Hot water volume (10..250)
#  These are persisted with save_settings and sent to the machine with the
#  core's own save_settings_to_de1, debounced by 1s (Streamline's pattern).
#
#  It hands off to plugins -- GrindAdvisor, DYE, Bean Scanner, Shot History
#  Editor, MaintenanceTracker, Drink Menu -- through their public entry
#  points, and any writing those do is their own, behind their own
#  confirmation.
#
#  ---------------------------------------------------------------------
#  Two scale sources (see de1app-core/dui.tcl):
#
#    Coordinates are VIRTUAL. Everything handed to `dui add ...` lives in
#    the app's 2560x1600 canvas; dui rescales to the physical screen. Never
#    feed `winfo screenwidth` into a coordinate.
#
#    Fonts are PHYSICAL. Tk font objects bypass that rescale, so they are
#    sized in real pixels from the detected screen, with negative Tk sizes
#    (negative = pixels; positive = points, which explode on Android DPI).
#
#  This file is authored entirely in DESIGN pixels on a 1340x800 basis --
#  the same basis as the design mockup -- and converts to virtual through
#  ::lumen::X and ::lumen::Y. Note 2560/1340 is 1.9104 while 1600/800 is
#  2.0, so x and y genuinely need different factors; using one factor for
#  both drifts the layout horizontally.
#
#  All layout numbers live in ::lumen::_init_layout. Nothing below it
#  hardcodes a coordinate.
#
#############################################################################

namespace eval ::lumen {
    variable version "0.57.5"

    variable C        ;# colour tokens
    array set C {}

    variable L        ;# layout + font tokens
    array set L {}

    variable F        ;# resolved font family names
    array set F {}

    # Pages whose panels are baked into a pre-rendered background image.
    # ::lumen::glass draws nothing on these -- the panel is already in the
    # PNG, with real translucency and blur that Tk canvas cannot produce.
    # Regenerate with tools/make_backgrounds.py after ANY layout change --
    # on ANY of these pages, not just home.
    #
    # 0.20.0: every page is baked now, not just home. Before that, settings
    # and the four flow pages fell through to the vector `glass` primitive --
    # flat fills, a hard line along the top edge only, no shadow -- and read
    # a generation behind the home screen.
    # 0.44.0: the stock tank-empty pages (tankempty refill) are re-declared
    # on lumen_message, so they are baked too.
    variable baked_pages [list off lumen_settings \
                               espresso steam water hotwaterrinse \
                               tankempty refill]

    variable theme_mode   "dark"

    # 0.47.0: live retheme. Every canvas item a Lumen helper draws carries
    # ROLE tags naming the palette token its colours came from --
    # lumen_c_<token> for -fill, lumen_o_<token> for -outline -- so a theme
    # change is one itemconfigure per token, no restart. The tokens, in
    # the order the reverse lookup tries them (first match wins should a
    # derived custom palette ever give two tokens one value).
    variable role_tokens [list ink ink_2 ink_3 crema crema_lo crema_brd \
                               glass glass_2 glass_brd spec good warn danger \
                               c_press c_flow c_temp c_weight grid \
                               chart_bg chart_bg_flow bg]
    variable C_rev        ;# colour -> token, rebuilt by set_palette
    set C_rev [dict create]
    variable item_n 0     ;# unique first tag per item (dui refuses duplicates)
    variable photo_items  ;# tag -> {page x y w h radius kind}: photo panels to redraw
    set photo_items [dict create]
    variable charts [list]   ;# {widget token} per graph widget, restyled on retheme
    variable bg_owned [list] ;# background photos Lumen created for a live swap
    variable theme_status "" ;# one-line note under THEME after a failed apply

    # The profile the LAST shot ran on. Latched when the espresso page opens
    # (a shot is starting, so the loaded profile is the one it will use) and
    # seeded at startup from the newest history file. NOT read live from
    # ::settings(profile_title): that is the profile loaded right now, and it
    # stops describing the last shot the moment you switch -- which is exactly
    # the case this line exists to show.
    variable last_shot_profile ""
    variable shot_rec_pending 0 ;# 0.57.5: see record_saved_shot

    # What the loaded shot FILE records: grind, dose and yield, read out of
    # its settings block by load_last_shot_curves. Keys grind, dose, yield,
    # plus (0.43.0) roaster and bean -- the identity the file carries, so
    # the LAST SHOT card names the shot's own bean even when the loaded bag
    # differs (a fresh bag with no shots falls back to the previous bag's
    # last shot, and the card must say so). Absent means "not recorded".
    #
    # These are what the LAST SHOT card shows, in preference to the live
    # ::settings, because the two answer different questions (0.25.0):
    #
    #   ::settings(grinder_setting) and friends are what is staged RIGHT NOW
    #   -- what the NEXT shot will use and record. The shot file is what the
    #   LAST shot actually used. They agree until you change a setting, or
    #   until you correct a shot's record in the Shot History Editor -- which
    #   writes the file and nothing else, so the live value keeps reporting
    #   the figure you just corrected away from.
    #
    # ::settings(drink_weight) additionally does not survive a restart, which
    # is how the tablet came to show "YIELD 0.0" beside a grind tile calling
    # the same shot 37.8g (0.24.1).
    #
    # CLEARED when a shot starts (latch_shot_profile): from that moment the
    # file is no longer about the last shot, and the live settings are exactly
    # what the running shot is recording, so they become the better source.
    variable last_shot_rec
    array set last_shot_rec {}

    # 0.43.0: 1 while the flow that last opened the espresso page runs a
    # NON-espresso profile (cleaning, backflush, calibration ...). Set by
    # latch_shot_profile, consumed by after_flow_complete, which then
    # reloads the loaded bean's last real shot so a cleaning run never
    # stays on the home chart.
    variable last_flow_nonespresso 0

    # after-id of the debounced machine-settings save/send (settings page).
    variable machine_apply_id ""

    # The bags the cycler can reach, newest first, capped at lumen_bag_count.
    # Cached because the page indicator reads it on every refresh tick and
    # SDB must not be. See ::lumen::refresh_bag_list.
    variable bag_list [list]

    # When each flow page was last SHOWN, in clock milliseconds.
    #
    # The core's flow timers keep describing the PREVIOUS flow until the new
    # one reaches its "during" phase, so a page that reads them the moment it
    # opens reports the wrong thing (0.24.0: the espresso page flashed the
    # seconds since the last shot -- 450s -- before resetting to 0 and
    # counting properly). ::lumen::data::_flow_secs uses this to tell "this
    # visit's flow" from "the one before it".
    variable flow_opened
    array set flow_opened {}
}

#############################################################################
#  Colours
#
#  Tk canvas items have no alpha channel, so every "translucent" glass tone
#  is pre-composited against the page background by hand. That is the whole
#  trick behind the glass look: no runtime blur, no image assets.
#############################################################################

proc ::lumen::set_palette { mode } {
    variable C
    array unset C
    array set C {}

    if { $mode eq "custom" } {
        # 0.46.0: every token derived from the five saved preferences (see
        # ::lumen::custom::palette); the semantic and chart colours inside
        # it come from the matching baked base.
        set pr [::lumen::custom::prefs]
        set P [::lumen::custom::palette [dict get $pr eff] [dict get $pr bh] \
                   [dict get $pr bs] [dict get $pr ah] [dict get $pr as]]
        # 0.56.0: the base on screen, for the schedule tick to compare.
        set ::lumen::custom::active_base [dict get $pr eff]
        foreach k {bg glass glass_2 glass_brd spec ink ink_2 ink_3 crema crema_lo crema_brd \
                   good warn danger c_press c_flow c_temp c_weight grid chart_bg chart_bg_flow} {
            set C($k) [dict get $P $k]
        }
    } elseif { $mode eq "light" } {
        set C(bg)          "#E9EDF3"
        set C(glass)       "#F8F9FB"
        set C(glass_2)     "#FBFCFD"
        set C(glass_brd)   "#CCD2DA"
        set C(spec)        "#FFFFFF"

        set C(ink)         "#121826"
        set C(ink_2)       "#4A5568"
        # 0.43.1: was #7C8798, ~3.4:1 on the card fill -- under the 4.5:1
        # normal-text guideline for the 15-16 px labels. #65708A is ~4.7:1.
        set C(ink_3)       "#65708A"

        set C(crema)       "#C2761B"
        set C(crema_lo)    "#E4DDD7"
        set C(crema_brd)   "#DCC4AA"

        set C(good)        "#12805F"
        set C(warn)        "#B4761A"
        # 0.32.0: dedicated danger token (maintenance dot's red). The
        # palette had no red that wasn't a chart series colour; c_temp was
        # the closest but means "temperature curve". Light variant darker
        # than dark, same as good/warn/crema.
        set C(danger)      "#B23641"

        set C(c_press)     "#0E9E7C"
        set C(c_flow)      "#3F72E0"
        set C(c_temp)      "#E04F5C"
        set C(c_weight)    "#A8763F"
        set C(grid)        "#D5DBE3"
        # Sampled from the middle of the chart panel in
        # 1340x800/lumen_home_light.png -- the generator prints both.
        # (0.31.0: re-sampled at the taskbar-shifted panel centre, y=410.)
        set C(chart_bg)    "#DEE0E4"
        # The espresso page's chart panel sits at 186..504, the home one at
        # 268..600. Same baked gradient, different height, so a shared value
        # would read as a box cut into one of them. Sampled separately from
        # 1340x800/lumen_flow_chart_light.png.
        set C(chart_bg_flow) "#DEE1E4"

    } else {
        set C(bg)          "#0A0E15"
        set C(glass)       "#191E26"
        set C(glass_2)     "#23282F"
        set C(glass_brd)   "#2B2F36"
        set C(spec)        "#75787C"

        set C(ink)         "#F0F4FA"
        set C(ink_2)       "#AFBBCC"
        # 0.43.1: was #74829A, ~4.3:1 on the card fill; #8290A8 is ~5.1:1.
        # Still clearly the tertiary step below ink_2.
        set C(ink_3)       "#8290A8"

        set C(crema)       "#F0A63C"
        set C(crema_lo)    "#282219"
        set C(crema_brd)   "#614824"

        set C(good)        "#2FD3A4"
        set C(warn)        "#E8B34C"
        set C(danger)      "#DA515E"

        set C(c_press)     "#17C29A"
        set C(c_flow)      "#6C9BFF"
        set C(c_temp)      "#FF7880"
        set C(c_weight)    "#E6C9A8"
        set C(grid)        "#1C2129"

        # The graph is an opaque Tk widget sitting inside a panel that is a
        # baked gradient, so a flat page-coloured background reads as a box
        # cut into the panel. Sampled from the middle of the chart panel in
        # 1340x800/lumen_home.png -- resample if the generator changes.
        set C(chart_bg)    "#151618"
        # Same reasoning, for the espresso page's chart panel: it sits at
        # 186..504 rather than 268..600, and the backdrop is a vertical
        # gradient, so the tone at that height is genuinely different.
        # Sampled from 1340x800/lumen_flow_chart.png.
        set C(chart_bg_flow) "#171719"

    }

    # 0.46.1: the painter's parameters for THIS theme, so non-baked pages
    # (the picker, any fallback page) get photo panels drawn by the same
    # painter as the custom backgrounds. Dark and light map onto their
    # presets; custom onto the saved colours.
    variable theme_P
    if { [catch {
        switch -exact -- $mode {
            light   { set theme_P [::lumen::custom::palette light 220 30 34 76] }
            custom  { set pr [::lumen::custom::prefs]
                      set theme_P [::lumen::custom::palette [dict get $pr eff] [dict get $pr bh] \
                                       [dict get $pr bs] [dict get $pr ah] [dict get $pr as]] }
            default { set theme_P [::lumen::custom::palette dark 222 32 34 86] }
        }
    } err] } {
        set theme_P ""
        msg -NOTICE "Lumen: no painter parameters for theme '$mode': $err"
    }

    # 0.47.0: colour -> token, for the role tags the drawing helpers attach.
    variable C_rev
    variable role_tokens
    set C_rev [dict create]
    foreach tok $role_tokens {
        set v [string toupper $C($tok)]
        if { ![dict exists $C_rev $v] } { dict set C_rev $v $tok }
    }

    # The espresso chart reads these globals straight out of the skin.
    set ::pressurelinecolor        $C(c_press)
    set ::flow_line_color          $C(c_flow)
    set ::temperature_line_color   $C(c_temp)
    set ::weightlinecolor          $C(c_weight)
    set ::chart_background         $C(bg)
    set ::grid_color               $C(grid)
    set ::skin_background_colour   $C(bg)
}

#############################################################################
#  Layout
#############################################################################

# Design px (1340x800 basis) -> virtual canvas px.
proc ::lumen::X { v } { return [expr {int(round($v * 2560.0 / 1340.0))}] }
proc ::lumen::Y { v } { return [expr {int(round($v * 1600.0 /  800.0))}] }

proc ::lumen::_init_layout {} {
    variable L
    array unset L
    array set L {}

    # Real physical screen, used ONLY for font pixel sizes.
    set psh 800
    catch { set psh [winfo screenheight .] }
    if { $psh <= 1 } { set psh 800 }
    set font_scale [expr {double($psh) / 800.0}]
    set L(font_scale) $font_scale

    # ---- spacing -------------------------------------------------------
    set L(xs) 6 ; set L(sm) 10 ; set L(md) 16 ; set L(lg) 24 ; set L(xl) 32

    set L(margin)  16
    set L(radius)  26          ;# glass panel corner
    set L(radius_sm) 16

    # ---- dashboard (full width; the action rail was removed in 0.18.0:
    # the espresso/steam/water/flush buttons duplicated the machine's own
    # GHC controls and the width was needed for the next-shot steppers) ----
    set L(col_x)     16
    set L(col_w)   1308

    # 0.23.0 re-proportioned the page (owner mockup): the two top cards were
    # taller than their content needed, and the next-shot card -- the one you
    # actually operate -- was the most cramped. 46px moved from the top row
    # and 4 from the chart into the bottom row.
    #
    # 0.31.0 adds the taskbar (Apple-status-bar style) along the top edge.
    # The page had zero vertical slack (16+190+16+336+16+210+16 = 800), so
    # the bar's 48 come from the least information-dense donors per the
    # discovery pass: the chart plot gives 40 and the top cards give 8 of
    # the ~14px their 0.23.0 budget left genuinely spare. The bean strip --
    # the page's operating surface -- gives nothing and does not move.
    #
    #   taskbar      0..48
    #   top cards   64..254  (h 190 -- 0.34.1 gave the cards their 8px
    #                         back after the owner reported the tiles'
    #                         bottom text rows crowding the border at
    #                         h 182; the chart pays instead)
    #   chart      270..558  (h 288, was 336 pre-taskbar)
    #   bottom     574..784  (h 210, unchanged)
    #
    # Every gap is md (16) and the bottom margin is 16, as before.
    set L(bar_y)      0 ; set L(bar_h)   48
    # 0.57.0 (owner's mockup): the bar is re-laid out. Sleep (moon) is
    # ALONE at the far left -- nothing tappable near it, so the corner tap
    # that used to put the machine to sleep by accident lands on nothing.
    # The clock takes two rows (time over date) so the water reading can
    # follow it on the left; the four remaining icons close up to the
    # right margin; the wordmark is gone; the favorite slots widen to
    # carry the profile NAMES, centred on the free span between water
    # and icons. Every zone is the bar's full 48px height.
    #
    #   moon      0..56
    #   time     66.. (row 1, 26px mono, widest "12:59 PM" ends ~190)
    #   date     68.. (row 2, caption)
    #   water   206.. (anchored w, widest "1500 ml" ends ~315)
    #   slots   396..576  586..766  776..956  (180 wide, 10 apart)
    #   mug 1052..1108  wrench 1124..1180  gear 1196..1252  DE1 1268..1324
    set L(bar_moon_x)   0
    set L(bar_time_x)  66 ; set L(bar_time_y) 20
    set L(bar_day_x)   68 ; set L(bar_day_y)  40
    set L(bar_water_x) 206
    set L(bar_icon_w)    56
    set L(bar_icon_pitch) 72
    set L(bar_drinkmenu_x) 1052
    set L(bar_wrench_x) 1124
    set L(bar_gear_x)   1196
    set L(bar_de1_x)    1268
    # Maintenance state dot: top-right corner of the wrench zone, clear of
    # the 22px glyph centred at (1152, 24).
    set L(bar_dot_x)    1174 ; set L(bar_dot_y) 12

    # Favorite profile slots (0.53.0 digits; 0.57.0 text). Three 180-wide
    # zones, 10 apart, centred on 676 -- the middle of the free span from
    # the water reading (~315) to the mug (1052). The title is centred on
    # its slot and ellipsis-truncated to the inner width (180 - 2 x sm),
    # so a short and a long name sit identically. The active slot's halo
    # is one photo of fav_glow_w x bar_h design px, inset 2 in the zone.
    set L(bar_fav_x) {396 586 776}
    set L(bar_fav_w) 180
    set L(bar_fav_text_w) 160
    set L(bar_fav_glow_w) 176
    set L(bar_fav_glow_soft) 12     ;# halo falloff, design px each side
    # The settings header's "Clear favorite profiles" link: right-aligned
    # to the right column's edge (1170), its zone 56..100 ends above the
    # first row at 110.
    set L(set_favclr_x) 950 ; set L(set_favclr_w) 220
    set L(set_favclr_y)  56 ; set L(set_favclr_h)  44

    set L(grind_x)   16 ; set L(grind_y)  64
    set L(grind_w)  650 ; set L(grind_h) 190

    set L(last_x)   682 ; set L(last_y)   64
    set L(last_w)   642 ; set L(last_h)  190

    set L(chart_x)   16 ; set L(chart_y) 270
    set L(chart_w) 1308 ; set L(chart_h) 288

    # 0.33.0 (taskbar pass 3, owner's Layout 2): the side panel is GONE --
    # Settings and Sleep live on the taskbar now (tablet-verified in
    # 0.32.0), Profile is a tap on the identity row's PROFILE value below,
    # and the strip takes the panel's 184px: full content width, 1308.
    set L(bean_x)    16 ; set L(bean_y)  574
    set L(bean_w)  1308 ; set L(bean_h)  210

    # PROFILE tap zone, over the 0.35.0 dedicated PROFILE row: the full
    # block width (40..500), 44 tall, centred on the row. It brushes the
    # label row above and the roaster line below -- text is not a tap
    # target, zones only may not overlap each OTHER, and no other zone
    # exists in the identity block above the action row.
    set L(id_prof_tap_x)  40 ; set L(id_prof_tap_y) 592
    set L(id_prof_tap_w) 460 ; set L(id_prof_tap_h) 44

    # ---- bean strip internals (0.23.0) ---------------------------------
    #
    # PROFILE left the stepper row for the identity block, so there are three
    # stepper groups instead of four. That freed enough width to widen the
    # identity block from 280 to 460 -- which is what makes a 44-character
    # roaster name fit without truncation.
    #
    # Identity rows. The ROASTER is the small line and the BEAN TYPE is the
    # hero, not the other way round: roasters run long ("MAN VERSUS MACHINE
    # Specialty Coffee Roasters" is 44 chars) while the bean type is short
    # and is what actually distinguishes one bag from another day to day.
    set L(bean_id_x)    40
    set L(bean_id_w)   460

    # 0.35.0 (owner request): PROFILE gets its own row under NEXT SHOT,
    # matching the LAST SHOT card's stacked order (label / PROFILE /
    # roaster / hero). That reverses half of 0.27.0, which had merged
    # PROFILE into the label row to buy even 11px gaps; a dedicated row
    # costs them. The block re-spaces to a UNIFORM 7px gap everywhere
    # (top pad 10), so nothing is singled out as wedged, and the action
    # row does not move:
    #
    #   584 label (->601)   606 profile (->622)   629 roaster (->645)
    #   652 hero (40px ->692)   699 notes (->715)
    #   722 action row (->770), 14 clear of the strip edge at 784
    set L(id_label_y)  584      ;# NEXT SHOT
    set L(id_prof_y)   606      ;# PROFILE <value>, its own row again
    set L(id_roast_y)  629      ;# roaster, small
    set L(id_name_y)   652      ;# bean type, hero (40px -> 692)
    set L(id_notes_y)  699      ;# tasting notes, only when non-empty
    set L(id_act_y)    722      ;# action row (48 tall -> 770)

    set L(id_prof_x)    40      ;# the PROFILE label, left-aligned like
                                ;# the LAST SHOT card's
    set L(id_val_x)    130      ;# and its value (90 after the label,
                                ;# the last card's own pitch)
    set L(id_val_w)    370      ;# the full-row width the move buys

    # The cycler arrows are a stepper pill's size now (owner request), down
    # from 120 wide. They stay on the action row with Edit BETWEEN them: two
    # arrows side by side invite a mis-tap that sends you the wrong way
    # through the bags, which is why Edit was put between them in 0.23.0.
    #
    # A first cut of 0.27.0 moved them up to flank the bag name at the
    # block's two edges. The preview killed it: the right arrow landed 20px
    # from the GRIND column's minus pill, at the same size, shape and height
    # -- it read as one of GRIND's controls. The name row is better off with
    # the full 460 anyway.
    #
    #   40..84   96..256   268..312
    set L(cyc_w)        44 ; set L(cyc_h)  48
    set L(cyc_y)       722
    set L(cyc_prev_x)   40
    set L(cyc_next_x)  268
    set L(id_edit_x)    96 ; set L(id_edit_w) 160 ; set L(id_edit_h) 48

    # The hero name keeps the block's full width.
    set L(id_name_x)    40 ; set L(id_name_w) 460

    # iPhone-style page indicator for the bag cycler (0.27.0), centred in the
    # action row's remaining width: (312 + 500) / 2 = 406. At 10 bags -- the
    # most lumen_bag_count allows -- the row of dots is about 140 wide, so it
    # keeps ~35px clear of the right arrow and of the block's edge.
    set L(bag_dots_x)  406 ; set L(bag_dots_y) 746

    # 0.33.0: three columns spread evenly across 520..1300 (the full-width
    # strip's inner edge): groups are 240 wide now (pill 44, gap 6, value
    # 140, gap 6, pill 44 -- the value span finally fits "38.0 (1:2.0)"-
    # class strings, the 0.21.0 complaint), 3 x 240 = 720, two 30 gaps,
    # so a 270 pitch ending flush at 1060 + 240 = 1300.
    set L(bean_fact_x)  520
    set L(bean_fact_w)  270        ;# column pitch

    # The "-" glyph renders LOW inside its pill. Measured on the tablet
    # (0.27.0): against a pill centre at y=666, the minus ink sat at 668.5 and
    # the plus at 666.5 -- Tk centres the text bounding box, and a hyphen's
    # ink is not centred within that box the way a plus sign's is. Two design
    # px up puts the two glyphs on the same line as each other.
    set L(step_minus_dy) -2

    # Stepper group internals: pill, gap, value span, gap, pill = 176.
    #
    # The right column is evenly distributed and its bottom row is LEVEL with
    # the identity block's action row on the left (owner request, 0.23.1):
    #
    #   pad 20   label 594..610   gap 32   steppers 642..690
    #            gap 32           bottom 722..770   14 clear to the strip edge
    #
    # 722 is id_act_y, so Connect / Set dose / Scan bag sit on exactly the
    # same baseline as the cycler arrows and Edit. Both columns end at 770.
    set L(step_w)       44
    set L(step_gap)      6
    set L(step_val_w)  140        ;# 0.33.0: was 76 -- see the pitch note
    set L(step_y)      642
    set L(step_h)       48

    # Bottom row of the strip, on the SAME grid as the steppers above and the
    # same y as the identity block's action row.
    set L(scale_y)      722
    set L(scale_h)       48
    set L(scale_read_x) 520 ; set L(scale_read_w) 240   ;# live readout
    set L(scale_set_x)  790 ; set L(scale_set_w)  240   ;# Set dose button
    set L(act_scan_x)  1060                             ;# Scan bag
    set L(act_w)        240 ; set L(act_h)         48

    # ---- last shot tile internals (0.23.0) ------------------------------
    #
    # Identity on the left, metrics on the right, so the taller type fits in
    # a shorter card. Mirrors the next-shot card's row order exactly:
    # LABEL -> PROFILE -> roaster -> bean type.
    set L(last_id_x)   706 ; set L(last_id_w)  274
    set L(last_val_x)  796      ;# PROFILE value on THIS card -- NOT id_val_x,
                                ;# which is the next-shot card's 130 and lands
                                ;# inside the grind tile (seen on the tablet)
    # 0.31.0: these are ABSOLUTE page y values (unlike the grind tile,
    # whose rows hang off grind_y), so the taskbar's +48 shift is applied
    # to every one of them here. Relative spacing is unchanged; the tile's
    # 8px height loss comes out of the bottom clearance.
    set L(last_label_y) 84
    set L(last_prof_y) 108
    set L(last_roast_y) 136
    # The last shot's bean name uses font_primary (22px), not the 40px hero:
    # 274px holds ~11 characters at 40px, which cut "Jorge Diaz Campos" to
    # "Jorge Dia...". The owner's mockup also shows this name smaller than the
    # next-shot one -- this card is a summary, that one is the control.
    set L(last_name_y) 156

    # Four metrics on a 76 pitch: 996 + 3*76 + 76 = 1300, the tile's inner
    # edge (682 + 642 - 24).
    set L(last_met_x)  996 ; set L(last_met_pitch) 76
    set L(last_met_label_y) 136
    set L(last_met_val_y)  160
    set L(last_met_sub_y)  188  ;# the derived ratio, under YIELD

    # Water tank level (0.24.0), in the card's top-right corner -- the only
    # space on the page that was empty, and where every other skin puts its
    # tank indicator. It is machine status rather than shot data, so it takes
    # (0.34.0: the water readout moved to the taskbar -- it is machine
    # status, which is what a status bar is for; the card's top-right
    # corner is empty again.)

    # Shot history is a text link now, matching Curve / Shot analysis on the
    # grind tile rather than being the only button on the card.
    set L(hist_y)      220

    set L(pad_x)     24        ;# inner padding of a tile
    set L(pad_y)     20

    # ---- flow pages (espresso / steam / water / flush) -----------------
    set L(center_x)      670
    set L(flow_state_y)  110
    set L(flow_timer_y)  210
    set L(flow_panel_x)  170
    set L(flow_panel_y)  420
    set L(flow_panel_w) 1000
    set L(flow_panel_h)  170
    set L(flow_hint_y)   640

    # Compact variant, used on the espresso page so a live chart fits.
    set L(fc_state_y)    30
    set L(fc_timer_y)    76
    set L(fc_chart_x)    16  ; set L(fc_chart_y)  186
    set L(fc_chart_w)  1308  ; set L(fc_chart_h)  318
    set L(fc_panel_x)   170  ; set L(fc_panel_y)  520
    set L(fc_panel_w)  1000  ; set L(fc_panel_h)  150
    set L(fc_hint_y)    700

    # ---- tank-empty page (0.44.0) --------------------------------------
    #
    # The stock `tankempty refill` pages, re-declared on a baked Lumen
    # background. One centred panel carries the message; the two pills sit
    # INSIDE the stock tap zones, which are copied verbatim (design px:
    # retry 0..1340 x 0..700, Exit App 0..419 x 701..800, Ok 921..1340 x
    # 701..800). make_backgrounds.py MESSAGE_* mirrors these numbers.
    set L(msg_panel_x) 270 ; set L(msg_panel_y) 200
    set L(msg_panel_w) 800 ; set L(msg_panel_h) 300
    set L(msg_title_y) 240
    set L(msg_body_y)  306
    set L(msg_retry_y) 392
    set L(msg_water_y) 440
    set L(msg_btn_y)   714 ; set L(msg_btn_w) 240 ; set L(msg_btn_h) 72
    set L(msg_exit_x)   90 ; set L(msg_ok_x) 1010

    # ---- settings page grid --------------------------------------------
    #
    # These were literals inside build_settings and restated again in
    # tools/check_skin.tcl and make_backgrounds.py, so a change had to be made
    # in three places. They are tokens now; the generator still mirrors them
    # by hand (it is Python) but the harness reads these.
    #
    # Left 170..630 (460 wide), right 670..1170 (500 wide) -- 170 clear on
    # BOTH page edges, one md gap between the columns.
    #
    # 0.24.0 briefly made them equal; a 200-wide button does not clear the
    # caption beside it inside 460, so the wide right column holds every
    # button and these are the tablet-verified 460 / 500. Do not "tidy" them
    # to equal widths without moving a button first. (The DECENT APP row
    # itself is gone since 0.42.0 -- the taskbar's DE1 icon opens the app
    # settings -- which is why the right column's fourth slot is empty.)
    set L(set_col_l)  170 ; set L(set_col_l_w) 460
    set L(set_col_r)  670 ; set L(set_col_r_w) 500
    set L(set_row_h)  118 ; set L(set_rows) {110 244 378 512}
    set L(set_done_y) 690 ; set L(set_done_w) 240 ; set L(set_done_h) 72

    # Stepper group inside a settings row: pill, gap, value, gap, pill.
    set L(set_step_w) 44 ; set L(set_step_gap) 8
    set L(set_val_w) 100 ; set L(set_step_h)  48

    # The alternating rows' mode line (0.26.0): "TIME | flow". The second word
    # starts at a fixed offset so the two text items never reflow -- the
    # longest first word is TEMP at ~40px, so 70 clears it.
    #
    # Its tap target is 48 tall (over the 44px floor) and wide enough to be
    # hit without aiming, while ending well clear of the stepper group: the
    # left column's group starts at 402, this ends at 170 + 24 + 180 = 374.
    set L(set_mode_dx) 70
    set L(set_mode_w) 180 ; set L(set_mode_h) 48

    # Theme picker (0.51.0 redesign): a 640-wide controls column with the
    # labels ABOVE full-width swatch grids (two rows of 13 circles), and a
    # 330-wide preview column holding a painted miniature of the home page
    # (1340x800 at 330/1340), five token chips and the notes.
    # 0.54.1 (owner's mock): both columns pushed out into the page margins
    # (110 each side, was 170) and the room given to the PREVIEW column --
    # 450 wide, was 330 -- so the miniature grows from 282 to 402 wide.
    set L(thp_x)  110 ; set L(thp_w)  640      ;# controls 110..750
    set L(thp_px) 780 ; set L(thp_pw) 450      ;# preview 780..1230
    set L(thp_piw) 402                         ;# preview inner width: 450 - 2 x pad_x
    set L(thp_base_y) 104 ; set L(thp_base_h) 80
    set L(thp_bh_y) 196 ; set L(thp_ah_y) 360 ; set L(thp_sw_h) 152
    # 0.53.1: presets in TWO rows of three 192-wide pills on the swatch
    # rows' rhythm (label +18, first row +48, 8 between, 16 below): six
    # in a row left 3 px between pills and 8 under them. The card is 160
    # tall, so Cancel / Done moved under it to 712 (ending at 784, the
    # home strip's own bottom edge).
    set L(thp_pre_y) 524 ; set L(thp_pre_h) 160
    set L(thp_pre_w) 192 ; set L(thp_pre_gap) 8 ; set L(thp_pre_ph) 44
    set L(thp_done_y) 712
    set L(thp_dot) 38 ; set L(thp_pitch) 46    ;# 13 x 46 - 8 = 590 inside 592
    set L(thp_row1) 48 ; set L(thp_row2) 96    ;# swatch row offsets inside the row
    # Preview column internals, all inside the card's pad_x (0.53.1, owner:
    # nothing hugs a card border): miniature 402 wide (800 x 402/1340 =
    # 240 tall) at the swatch rows' +48, five 66-wide chips on an 18 gap
    # (= 402), notes at the inner width, lg between the groups (0.54.1
    # sizes; the caption notes wrap to two lines each at 402).
    set L(thp_mini_y) 152 ; set L(thp_mini_h) 240
    set L(thp_chip_y) 416 ; set L(thp_chip_w) 66 ; set L(thp_chip_h) 48 ; set L(thp_chip_gap) 18
    set L(thp_note_y) 514 ; set L(thp_note2_y) 566 ; set L(thp_status_y) 618

    # ---- fonts: physical pixels, 16px floor ----------------------------
    # Fallback names first, so every key is valid even if font creation
    # fails on an unusual build.
    set L(font_title)   Helv_20_bold
    set L(font_hero)    Helv_20_bold
    set L(font_section) Helv_18_bold
    set L(font_primary) Helv_10_bold
    set L(font_body)    Helv_9
    set L(font_caption) Helv_8
    set L(font_button)  Helv_10_bold
    set L(font_label)   Helv_8
    set L(font_data)    Helv_10_bold
    set L(font_metric)  Helv_20_bold
    set L(font_bt)      Helv_8

    _load_font_families

    # Deliberately NOT dui's own load_font here. That routes through
    # `dui font load`, which computes int([dui cget fontm] * size) and hands
    # a POSITIVE size to `font create` -- i.e. points, which scale
    # unpredictably with Android DPI. fontm is
    # ::settings(default_font_calibration), 0.5 on this tablet, so a 19 would
    # become a 9pt font. We take Inter's family name from the loader and
    # create the fonts ourselves at NEGATIVE (pixel) sizes instead.
    #
    # Weight comes from the file, not from -weight, so each weight is loaded
    # from its own TTF. -weight bold is only used on the Helvetica fallback,
    # where there is no separate bold face to point at.
    catch {
        foreach {key famkey ref bold} {
            hero    mono_bold 84 1
            title   sans_bold 40 1
            metric  mono_bold 40 1
            data    mono      26 0
            section mono      24 0
            primary sans_semi 22 1
            button  sans_semi 20 1
            body    sans      19 0
            caption sans      16 0
            label   sans_semi 15 1
            bt      symbol    22 0
        } {
            set px [expr {int(max(16, round($ref * $font_scale)))}]
            set fname "LUMEN_$key"
            set family [_font_family $famkey]
            set weight [_font_weight $famkey $bold]

            if { [lsearch -exact [font names] $fname] >= 0 } {
                font configure $fname -family $family -size [expr {-$px}] -weight $weight
            } else {
                font create $fname -family $family -size [expr {-$px}] -weight $weight
            }
            set L(font_$key) $fname
        }
    }
}

#############################################################################
#  Font families
#
#  Inter for UI text, NotoSansMono for every number. The mono faces matter:
#  doses, yields, times and grind settings all line up in columns, and a
#  proportional face makes those columns ragged.
#############################################################################

proc ::lumen::_load_font_families {} {
    variable F
    array unset F
    array set F {}

    # Fallbacks, used if the TTFs cannot be registered (e.g. off-tablet).
    set F(sans)      "Helvetica" ; set F(sans_ok)      0
    set F(sans_semi) "Helvetica" ; set F(sans_semi_ok) 0
    set F(sans_bold) "Helvetica" ; set F(sans_bold_ok) 0
    set F(mono)      "Courier"   ; set F(mono_ok)      0
    set F(mono_bold) "Courier"   ; set F(mono_bold_ok) 0
    set F(symbol)    "Helvetica" ; set F(symbol_ok)    0
    foreach k {sans sans_semi sans_bold mono mono_bold symbol} { set F(${k}_collides) 0 }

    # The app's own icon font, which carries a real Bluetooth glyph at
    # U+F293 (dui.tcl:1640). Loaded from wherever dui already has it.
    catch {
        set fam [::dui::font::add_or_get_familyname $::dui::symbol::font_filename]
        if { $fam ne "" } { set F(symbol) $fam ; set F(symbol_ok) 1 }
    }

    set dir "[homedir]/skins/Lumen/fonts"

    foreach {key file} {
        sans      Inter-Regular.ttf
        sans_semi Inter-SemiBold.ttf
        sans_bold Inter-Bold.ttf
        mono      NotoSansMono-SemiBold.ttf
        mono_bold NotoSansMono-ExtraBold.ttf
    } {
        if { [catch {
            set fam [::dui::font::add_or_get_familyname [file join $dir $file]]
        } err] } {
            msg -NOTICE "Lumen: could not register $file ($err); falling back"
            continue
        }
        if { $fam ne "" } {
            set F($key) $fam
            set F(${key}_ok) 1
        } else {
            msg -NOTICE "Lumen: no family name for $file; falling back"
        }
    }

    # Several weights of one typeface can register under a SINGLE family
    # name. On this tablet Inter-Bold.ttf reports family "Inter" -- exactly
    # what Inter-Regular.ttf reports -- so naming the family alone does not
    # select the bold face, and text asked for in "bold" would silently
    # render regular. Where that happened, ask Tk for the weight explicitly.
    foreach k {sans sans_semi sans_bold mono mono_bold} {
        foreach k2 {sans sans_semi sans_bold mono mono_bold} {
            if { $k eq $k2 } { continue }
            if { $F($k) eq $F($k2) } { set F(${k}_collides) 1 }
        }
    }
}

proc ::lumen::_font_weight { famkey bold } {
    variable F
    if { !$bold } { return "normal" }
    # Nothing real loaded: let Tk embolden the fallback face.
    if { ![_font_family_ok $famkey] } { return "bold" }
    # Family name is shared with another face, so it cannot select this one.
    if { [info exists F(${famkey}_collides)] && $F(${famkey}_collides) } { return "bold" }
    # This face owns its family name; the file already carries the weight.
    return "normal"
}

proc ::lumen::_font_family { key } {
    variable F
    if { [info exists F($key)] } { return $F($key) }
    return "Helvetica"
}

proc ::lumen::_font_family_ok { key } {
    variable F
    if { [info exists F(${key}_ok)] } { return $F(${key}_ok) }
    return 0
}

#############################################################################
#  Glass primitive
#
#  Mechanism copied verbatim from the proven rounded_rect in
#  plugins/GrindAdvisor/GrindAdvisor.tcl: a smoothed canvas polygon. The
#  specular top edge is what actually sells "glass" without a blur.
#############################################################################

#############################################################################
#  Depth
#
#  Tk canvas has no gradients and no alpha, so every soft edge here is built
#  from stacked solid shapes in interpolated colours. All of it is drawn once
#  at page build, so there is no runtime cost at all.
#
#  Deliberately NOT attempted: a gradient inside each panel. Bands clipped to
#  a rounded rectangle need either clipping (Tk has none) or bands with the
#  panel's own 26px corner radius, whose rounded bottom edges read as stacked
#  pills rather than a gradient. The backdrop, bloom and shadow carry the
#  depth without that artefact.
#############################################################################

# A vertical gradient wash and a warm radial bloom were built here in 0.6.0
# and removed in 0.6.1. Both made the screen worse, for one reason worth
# recording:
#
#   The design mockup's panels were genuinely TRANSLUCENT, so they tracked
#   whatever gradient sat behind them and kept their edges everywhere. Tk
#   canvas has no alpha, so Lumen's panels are one fixed tone. Put a gradient
#   behind them and near the top of the screen the backdrop (#151C2A) and the
#   panel fill (#191E26) are practically the same colour -- the panels
#   dissolve into the background and only the shadow ring shows, which reads
#   as a crude black outline around everything.
#
# A flat ground is not a compromise here, it is what makes the panels legible.
# Reproducing the mockup's depth honestly needs real translucency, i.e. baked
# PNG panels, which is the tooling route rejected at the start of the project.

# 0.47.0: the tag list for one item -- a unique first tag (dui refuses a
# second item whose FIRST tag already exists on the page, so no role tag
# may ever lead), the caller's own tags, then the role tags: lumen_c_<tok>
# when -fill is a palette token, lumen_o_<tok> when -outline is one.
# ::lumen::apply_theme recolours by these. Colours that are not tokens
# (the picker's hue swatches, "" fills) get no role tag and keep their
# colour across themes, which is what they mean.
proc ::lumen::_tags { fill outline {own ""} } {
    variable C_rev
    variable item_n
    set tags [list lumen_i_[incr item_n] {*}$own]
    if { $fill ne "" && [dict exists $C_rev [string toupper $fill]] } {
        lappend tags lumen_c_[dict get $C_rev [string toupper $fill]]
    }
    if { $outline ne "" && [dict exists $C_rev [string toupper $outline]] } {
        lappend tags lumen_o_[dict get $C_rev [string toupper $outline]]
    }
    return $tags
}

proc ::lumen::rounded_rect { page x1 y1 x2 y2 radius args } {
    set r $radius
    if { $r * 2 > ($x2 - $x1) } { set r [expr {($x2 - $x1) / 2}] }
    if { $r * 2 > ($y2 - $y1) } { set r [expr {($y2 - $y1) / 2}] }
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
    array set o [list -fill "" -outline "" -tags ""]
    array set o $args
    set rest {}
    foreach {k v} $args { if { $k ne "-tags" } { lappend rest $k $v } }
    return [uplevel #0 [list dui add canvas_item polygon $page {*}$pts -smooth 1 {*}$rest \
        -tags [_tags $o(-fill) $o(-outline) $o(-tags)]]]
}

# All arguments in DESIGN px.
proc ::lumen::glass { page x y w h args } {
    variable C
    variable L
    variable baked_pages

    # Already in the background image; drawing it again would flatten it.
    if { [lsearch -exact $baked_pages $page] >= 0 } { return }

    array set o [list \
        -radius  $L(radius) \
        -fill    $C(glass) \
        -outline $C(glass_brd) \
        -spec    1 \
        -tags    "" ]
    array set o $args

    set x1 [X $x] ; set y1 [Y $y]
    set x2 [X [expr {$x + $w}]] ; set y2 [Y [expr {$y + $h}]]

    set tagargs {}
    if { $o(-tags) ne "" } { set tagargs [list -tags $o(-tags)] }

    # 0.46.1: where Tk can paint, the panel is a photo from the same
    # painter that draws the custom backgrounds -- real translucency over
    # the ground, a soft shadow, the tapered specular -- placed with its
    # shadow margin around the requested rect. The vector polygon below is
    # the headless / failure fallback.
    variable theme_P
    variable photo_items
    if { [info commands image] ne "" && [info exists theme_P] && $theme_P ne "" } {
        if { ![catch {
            set kind plain
            if { $o(-fill) eq $C(crema_lo) } { set kind accent } \
            elseif { $o(-fill) eq $C(glass_2) } { set kind raised }
            set spec [list page $page x $x y $y w $w h $h radius $o(-radius) kind $kind]
            lassign [_panel_photo $spec] img px py
            # 0.47.0: the item is tagged so apply_theme can hand it a panel
            # painted from the next theme's parameters (see photo_items).
            set tags [_tags "" "" $o(-tags)]
            uplevel #0 [list dui add canvas_item image $page $px $py \
                -image $img -anchor nw -tags [concat $tags lumen_photo]]
            dict set photo_items [lindex $tags 0] $spec
        } err] } {
            return
        }
        msg -NOTICE "Lumen: photo panel failed on $page, drawing a polygon: $err"
    }

    # NO drop shadow on the vector path. Tried in 0.6.0 and reverted: on a
    # near-black ground the shadow tones span about two RGB values, so the
    # "falloff" was a solid near-black ring around every panel.

    rounded_rect $page $x1 $y1 $x2 $y2 [X $o(-radius)] \
        -fill $o(-fill) -outline $o(-outline) -width 2 {*}$tagargs

    if { $o(-spec) } {
        # Bright hairline inset from the corners along the top edge.
        set sx1 [X [expr {$x + $o(-radius) * 0.6}]]
        set sx2 [X [expr {$x + $w - $o(-radius) * 0.6}]]
        set sy  [expr {$y1 + 2}]
        uplevel #0 [list dui add canvas_item line $page $sx1 $sy $sx2 $sy \
            -fill $C(spec) -width 2 -tags [_tags $C(spec) ""]]
    }
}

# Paints one photo panel from the CURRENT theme's painter parameters.
# `spec` is the dict glass records (design px); returns the photo name
# and the virtual x y of its top-left corner (the panel sits inside its
# shadow margin S). Throws when Tk or the screen size is missing.
proc ::lumen::_panel_photo { spec } {
    variable theme_P
    if { ![info exists theme_P] || $theme_P eq "" } { error "no painter parameters" }
    lassign [::lumen::custom::screen] W H
    if { $W <= 0 } { error "no screen size" }
    set sx [expr {$W / 1340.0}] ; set sy [expr {$H / 800.0}]
    set S [expr {int(round(18 * $sy))}] ; set dy [expr {int(round(6 * $sy))}]
    set png [::lumen::custom::panel_png $theme_P \
        [expr {int(round([dict get $spec w] * $sx))}] [expr {int(round([dict get $spec h] * $sy))}] \
        [expr {int(round([dict get $spec radius] * $sy))}] [dict get $spec kind] $S $dy]
    set img [image create photo -data $png]
    return [list $img [X [expr {[dict get $spec x] - $S / $sx}]] [Y [expr {[dict get $spec y] - $S / $sy}]]]
}

# Small pill used for status chips.
proc ::lumen::chip { page x y text args } {
    variable C
    variable L

    array set o [list -fill $C(ink_2) -outline $C(glass_brd) -bg $C(glass) -w 0]
    array set o $args

    set h 26
    set w $o(-w)
    if { $w <= 0 } { set w [expr {[string length $text] * 8 + 24}] }

    glass $page $x $y $w $h -radius 13 -fill $o(-bg) -outline $o(-outline) -spec 0
    dui add dtext $page [X [expr {$x + $w / 2.0}]] [Y [expr {$y + $h / 2.0}]] \
        -text $text -font $L(font_label) -fill $o(-fill) \
        -anchor center -justify center -tags [_tags $o(-fill) ""]
}

# 0.42.0: the Decent app taskbar icon -- a SIDE VIEW of the DE1, drawn
# as vector strokes (owner-picked sample 1 of 3, 2026-09-03: body,
# tilted screen edge-on, group head block, drip tray). No Font Awesome
# glyph exists for this, and drawn strokes take the palette ink exactly
# like the font glyphs do. `cx`/`cy`/`size` in DESIGN px; the normalized
# 0..1 geometry is copied from the approved sample sheet's template
# (scratch de1_icons.py, variant 1), content centre (0.59, 0.495).
# Stroke -width 4 is VIRTUAL (canvas_item rescales -width): ~2 physical
# px, matching the FA regular glyph weight beside it.
proc ::lumen::draw_de1_icon { page cx cy size color } {
    foreach {x0 y0 x1 y1 r} [list \
        0.40 0.18 0.94 0.78 0.09  \
        0.24 0.86 0.94 0.97 0.045 \
        0.24 0.44 0.40 0.56 0.035] {
        rounded_rect $page \
            [X [expr {$cx + ($x0 - 0.59) * $size}]] \
            [Y [expr {$cy + ($y0 - 0.495) * $size}]] \
            [X [expr {$cx + ($x1 - 0.59) * $size}]] \
            [Y [expr {$cy + ($y1 - 0.495) * $size}]] \
            [X [expr {2 * $r * $size}]] \
            -fill {} -outline $color -width 4
    }
    # The tilted screen, edge-on (rises above the body's top front).
    uplevel #0 [list dui add canvas_item line $page \
        [X [expr {$cx + (0.44 - 0.59) * $size}]] \
        [Y [expr {$cy + (0.22 - 0.495) * $size}]] \
        [X [expr {$cx + (0.64 - 0.59) * $size}]] \
        [Y [expr {$cy + (0.02 - 0.495) * $size}]] \
        -fill $color -width 4 -capstyle round -tags [_tags $color ""]]
}

#############################################################################
#  Live data
#
#  Every proc here is called from a -textvariable, which dui re-substitutes
#  every ::settings(timer_interval) ms (200 on this app) for the CURRENT page
#  only, and only touches the canvas when the value actually changed. So
#  these must stay cheap and must never touch the filesystem.
#
#  In particular: GrindAdvisor's own load_last_recommendation reads a file.
#  We never call it. Its plugin.tcl already calls it once at load, and
#  save_last_recommendation keeps the in-memory dict current, so reading the
#  namespace variable is free.
#
#  Everything degrades to "--" when a plugin is absent or disabled.
#############################################################################

namespace eval ::lumen::data {}

# Safe global read. Works for array elements: _s ::settings(drink_weight)
proc ::lumen::data::_s { name {default ""} } {
    upvar #0 $name v
    if { [info exists v] } { return $v }
    return $default
}

proc ::lumen::data::_is_pos { v } {
    if { $v eq "" } { return 0 }
    if { [catch { set ok [expr {double($v) > 0}] }] } { return 0 }
    return $ok
}

proc ::lumen::data::_ellipsis { s max } {
    if { [string length $s] <= $max } { return $s }
    return "[string range $s 0 [expr {$max - 3}]]..."
}

# GrindAdvisor states its working in parentheses -- "Regression over 8 shots
# (slope -29.16 s/grind, predicts 26.8s at 8.1). (dose: ...)". That is three
# wrapped lines on the tile and it collided with the row beneath. The tile
# shows the summary; the full text is one tap away in the popup.
proc ::lumen::data::_short_reason { s } {
    set i [string first " (" $s]
    if { $i > 12 } { set s [string trim [string range $s 0 [expr {$i - 1}]]] }
    return [_ellipsis $s 88]
}

proc ::lumen::data::_num { v {dp 1} {default "--"} } {
    if { $v eq "" } { return $default }
    if { [catch { set out [format "%.${dp}f" $v] }] } { return $default }
    return $out
}

# ---------------------------------------------------------------- grind ---

# The recommendation dict, or {} if unavailable/not ok/not about this bag.
#
# 0.21.0: the bag-currency check. Every grind accessor funnels through here,
# so one guard resets the whole tile coherently -- the hero goes to "--", the
# delta, method chip and confidence band blank, and grind_note explains why.
#
# Before this, the tile kept displaying the PREVIOUS bag's number after a bag
# or profile switch, right up until the next shot was pulled. That number was
# a calibration for a different coffee.
#
# last_recommendation_is_current arrived in Grind Advisor 3.7.0 and fails safe
# on its own side (unknown identity -> "current"). The [info procs] guard here
# is for OLDER Grind Advisor builds, where the proc does not exist at all: in
# that case behave exactly as 0.20.0 did rather than blanking the tile for
# everyone still on 3.6.x.
proc ::lumen::data::grind_rec {} {
    # 0.22.0 preferred path: ask for the recommendation belonging to the bag
    # that is loaded NOW. Grind Advisor 3.8.0 computes it from that bag's own
    # shots and memoizes per bag, so this is safe on the 200 ms refresh tick.
    #
    # This replaces blanking. 0.21.0 could only tell that the saved
    # recommendation was about a different bag and cleared the tile -- but a
    # bag you cycle back to has its own history and its own regression, and
    # throwing that away was the wrong call.
    if { [info procs ::plugins::GrindAdvisor::recommendation_for_current_bag] ne "" } {
        if { ![catch { set rec [::plugins::GrindAdvisor::recommendation_for_current_bag] } err] } {
            if { $rec eq "" } { return {} }
            if { ![catch { dict size $rec }] \
              && [dict exists $rec ok] && [dict get $rec ok] } {
                return $rec
            }
            return {}
        }
        msg -ERROR "Lumen: could not get the recommendation for this bag: $err"
    }

    # Fallbacks for older Grind Advisor builds, in descending order of
    # capability: 3.7.x can at least say whether the saved rec is current;
    # 3.6.x and earlier can only hand over whatever was saved last.
    if { ![info exists ::plugins::GrindAdvisor::last_recommendation] } { return {} }
    set rec $::plugins::GrindAdvisor::last_recommendation
    if { $rec eq "" } { return {} }
    if { [catch { dict size $rec }] } { return {} }
    if { ![dict exists $rec ok] || ![dict get $rec ok] } { return {} }
    if { [info procs ::plugins::GrindAdvisor::last_recommendation_is_current] ne "" } {
        if { [catch { set cur [::plugins::GrindAdvisor::last_recommendation_is_current] }] } {
            return $rec
        }
        if { !$cur } { return {} }
    }
    return $rec
}

proc ::lumen::data::_g { rec key {default ""} } {
    if { $rec ne "" && [dict exists $rec $key] } { return [dict get $rec $key] }
    return $default
}

# 0.38.0: the new-bag starting estimate (GrindAdvisor 3.13.0).
#
# For a bag with NO shots the tile used to show only "--" and "pull a
# shot". starting_estimate returns a display-only starting grind borrowed
# from already-calibrated bags (same coffee -> same roaster -> same
# profile). It is an ESTIMATE, not a calibration: GrindAdvisor's contract
# is that the word "Recommended" never appears next to it -- which is why
# the tile's header label is an accessor now (grind_header) -- and that it
# is NEVER called from a per-tick path, because it reads SDB and is not
# memoized on the plugin side.
#
# So this caches per bag key. current_bag_key is explicitly safe on the
# 200 ms tick (GrindAdvisor README, v3.7.0); the one SDB read happens on
# the first tick after the key changes, then the dict is served from here.
# A cached MISS ({}) is cached too, or a bag with no candidates would
# re-read SDB five times per second. The cache never needs invalidating
# beyond the key change: the moment the bag gets its first shot,
# recommendation_for_current_bag returns a real rec, every accessor
# prefers it, and the estimate is simply never consulted again.
namespace eval ::lumen::data {
    variable est_key ""
    variable est_val {}
}

proc ::lumen::data::grind_est {} {
    variable est_key
    variable est_val
    if { [info procs ::plugins::GrindAdvisor::starting_estimate] eq "" } { return {} }
    if { [info procs ::plugins::GrindAdvisor::current_bag_key] eq "" } { return {} }
    if { [catch { set ck [::plugins::GrindAdvisor::current_bag_key] }] } { return {} }
    if { $ck eq "" } { return {} }
    if { $ck eq $est_key } { return $est_val }
    set est_key $ck
    set est_val {}
    if { [catch { set e [::plugins::GrindAdvisor::starting_estimate] } err] } {
        msg -ERROR "Lumen: starting_estimate failed: $err"
        return {}
    }
    if { $e ne "" && ![catch { dict size $e }] \
      && [dict exists $e grind] && [dict exists $e label] \
      && [dict exists $e reason] } {
        set est_val $e
    }
    return $est_val
}

# The tile's header label. Static "RECOMMENDED GRIND" until 0.38.0, now an
# accessor purely so an estimate is never captioned "Recommended"
# (GrindAdvisor's display contract for estimates).
proc ::lumen::data::grind_header {} {
    if { [grind_rec] eq "" && [grind_est] ne "" } {
        return [translate "STARTING ESTIMATE"]
    }
    return [translate "RECOMMENDED GRIND"]
}

proc ::lumen::data::grind_next {} {
    set rec [grind_rec]
    if { $rec ne "" } { return [_num [_g $rec next] 1] }
    # "~" marks the hero as an estimate even before the header registers.
    set est [grind_est]
    if { $est ne "" } { return "~[_num [dict get $est grind] 1]" }
    return "--"
}

proc ::lumen::data::grind_delta {} {
    set rec [grind_rec]
    if { $rec eq "" } { return "" }
    set from [_g $rec grind]
    set to   [_g $rec next]
    if { $from eq "" || $to eq "" } { return "" }
    if { [catch { set d [expr {double($to) - double($from)}] }] } { return "" }
    if { abs($d) < 0.05 } { return [translate "no change"] }
    return [format "%+.1f" $d]
}

# GrindAdvisor v3's ladder has FIVE rungs, not two -- see its own
# _forecast_method_label in plugins/GrindAdvisor/GrindAdvisor.tcl:1997:
#   first_shot  (n=1)  two_shot  (n=2)  regression  (n>=3)
#   regression_fallback   (n>=3, but the fitted slope is too flat to solve)
#   regression_untrusted  (n>=3, the slope solves but R2 < 0.30 -- the times
#                          are not tracking grind, so the fit is discarded
#                          and the ladder answers instead)
# Only the first two were mapped here originally, so the chip sat empty for
# the first two shots of every bag. Then GrindAdvisor 3.10.0 added the fifth
# rung and this map was not updated with it, so the chip fell through to the
# raw dict key and read "regression_unt..." on the tablet (0.27.2).
#
# Labels are shortened to fit the 150px chip; the Why? popup carries
# GrindAdvisor's own full wording. Keep them SHORT -- see the budget on the
# fallback below.
proc ::lumen::data::grind_method {} {
    set rec [grind_rec]
    if { $rec eq "" } {
        # 0.38.0: an estimate gets its own chip so the tile never presents
        # a borrowed number as one of the calibration rungs.
        if { [grind_est] ne "" } { return [translate "Estimate"] }
        return ""
    }
    set m [_g $rec method]
    switch -exact -- $m {
        first_shot           { return [translate "First shot"] }
        two_shot             { return [translate "2-shot"] }
        regression           { return [translate "Regression"] }
        regression_fallback  { return [translate "Pairwise"] }
        regression_untrusted { return [translate "Weak fit"] }
    }
    # A rung added by a newer GrindAdvisor: show it rather than nothing, so
    # the chip never silently goes blank again.
    #
    # 12, not the 16 this started at. 16 was picked without measuring, and
    # measured off the tablet screenshot it is ~134px of text in a 150px
    # chip -- ink to the rounded ends, no margin. font_label is 16px Inter
    # SemiBold, about 8.4px per character here, so 12 characters is ~100px
    # and sits inside the chip with room on both sides.
    return [_ellipsis $m 12]
}

proc ::lumen::data::grind_band {} {
    set rec [grind_rec]
    if { $rec eq "" } {
        # 0.38.0: GrindAdvisor's reason string names the estimate's source
        # rung -- "Starting estimate: same roaster (4 bags)". Worst case is
        # 44 chars; the 48 ellipsis is a guard, not a working truncation.
        set est [grind_est]
        if { $est ne "" } { return [_ellipsis [dict get $est reason] 48] }
        return ""
    }
    set band [_g $rec confidence_band]
    set n    [_g $rec n]
    if { $band eq "" } {
        if { $n ne "" } { return "[translate {Shots}]: $n" }
        return ""
    }
    if { $n ne "" } { return "$band  -  $n [translate {shots}]" }
    return $band
}

# 0.43.1: the band line was always green, so "Poor - 2 shots" looked as
# reassuring as "Good - 11 shots". Three stacked fixed-colour items share
# the spot (the maintenance-dot pattern); the text moves between them.
# GrindAdvisor's bands are Poor / Fair / Good / Excellent (_confidence_band).
# The starting-estimate line and anything unrecognised take the neutral
# item, so nothing ever goes missing.
proc ::lumen::data::_band_word {} {
    set rec [grind_rec]
    if { $rec eq "" } { return "" }
    return [string tolower [string trim [_g $rec confidence_band]]]
}

proc ::lumen::data::grind_band_good {} {
    if { [_band_word] in {good excellent} } { return [grind_band] }
    return ""
}

proc ::lumen::data::grind_band_poor {} {
    if { [_band_word] eq "poor" } { return [grind_band] }
    return ""
}

proc ::lumen::data::grind_band_neutral {} {
    if { [_band_word] in {good excellent poor} } { return "" }
    return [grind_band]
}

# Regression needs 3 shots on a bag before it can forecast. Say so plainly
# rather than showing a number the model cannot justify.
proc ::lumen::data::grind_note {} {
    set rec [grind_rec]
    if { $rec eq "" } {
        # 0.38.0: the owner-specced estimate line plus the standing
        # instruction. Widest case "Start ~50.0 (est. from 6 bags) - pull
        # a shot to calibrate" is 57 chars -- one line at font_body in the
        # note's 560px, same budget as the reasons _short_reason passes.
        set est [grind_est]
        if { $est ne "" } {
            return "[dict get $est label] - [translate {pull a shot to calibrate}]"
        }
        return [translate "Pull a shot on this bag to get a grind recommendation."]
    }
    set reason [_g $rec reason]
    if { $reason ne "" } { return [_short_reason $reason] }
    if { [_g $rec method] eq "regression_fallback" } {
        return [translate "Not enough shots on this bag yet for a full forecast."]
    }
    return ""
}

# ------------------------------------------------------------ last shot ---
#
# 0.25.0: this card reports THE SHOT'S OWN RECORD, not the machine's current
# settings.
#
# It used to read ::settings(grinder_setting) / (grinder_dose_weight) /
# (drink_weight) directly -- the same fields shot.tcl writes into the file, so
# for a shot pulled in this session the two agree and the distinction never
# showed. It shows in two situations the owner hit:
#
#   * Correcting a shot in the Shot History Editor writes the .shot FILE and
#     nothing else -- by that plugin's design. The live setting keeps
#     reporting the figure you just corrected away from, so the card denied
#     an edit that had actually worked.
#   * ::settings(drink_weight) does not survive a restart at all (0.24.1).
#
# So while ::lumen::last_shot_rec holds the newest file's values -- i.e. until
# a shot starts in this session and the live settings become the better
# source -- they win. Cost is nil: the file was already read at startup for
# the chart and the profile name.
#
# The NEXT SHOT card is unaffected and still reads the live/DYE-staged values.
# That is the whole point: one card is the record, the other is the plan.

# One latched field, or "" when the file did not record it.
proc ::lumen::data::_rec { key } {
    if { ![info exists ::lumen::last_shot_rec($key)] } { return "" }
    return $::lumen::last_shot_rec($key)
}

proc ::lumen::data::_dose_raw {} {
    foreach src [list [_rec dose] [_s ::settings(grinder_dose_weight)]] {
        if { [_is_pos $src] } { return $src }
    }
    return ""
}

proc ::lumen::data::last_dose {} {
    return [_num [_dose_raw] 1]
}

# The last shot's yield, in descending order of authority:
#
#   the file latch            -- what the shot RECORDED, corrections included.
#   ::settings(drink_weight)  -- what the app recorded for a shot pulled in
#                                this session, and the field shot.tcl writes.
#   ::de1(pour_volume)        -- volumetric fallback when no scale reported.
#
# Returns "" rather than 0 when there is nothing: a shot pulled without a
# scale has no yield, and _num turns "" into "--". It used to fall through to
# whatever the last source held, which printed a confident "0.0" -- the tablet
# showed exactly that next to a grind tile reporting 37.8g for the same shot.
proc ::lumen::data::_yield_raw {} {
    foreach src [list [_rec yield] \
                      [_s ::settings(drink_weight)] \
                      [_s ::de1(pour_volume)]] {
        if { [_is_pos $src] } { return $src }
    }
    return ""
}

proc ::lumen::data::last_yield {} {
    return [_num [_yield_raw] 1]
}

proc ::lumen::data::last_time {} {
    if { [catch { set n [espresso_elapsed length] }] } { return "--" }
    if { $n <= 0 } { return "--" }
    if { [catch { set t [espresso_elapsed range end end] }] } { return "--" }
    # A cleared series reads 0.0 at idle; that is "no shot", not a 0.0s shot.
    if { ![_is_pos $t] } { return "--" }
    return [_num $t 1]
}

proc ::lumen::data::last_ratio {} {
    # Same sources as the DOSE and YIELD shown above it, or the caption would
    # contradict the two numbers it sits between.
    set d [_dose_raw]
    set y [_yield_raw]
    if { ![_is_pos $d] || ![_is_pos $y] } { return "--" }
    if { [catch { set r [expr {double($y) / double($d)}] }] } { return "--" }
    # One decimal, matching the NEXT SHOT card (0.43.1; was two).
    return [format "1:%.1f" $r]
}

# The ratio as it appears UNDER the last shot's yield (0.23.0), matching the
# next-shot card. Parenthesised so it reads as derived, and blank rather than
# "--" when there is nothing to derive.
proc ::lumen::data::last_ratio_note {} {
    set r [last_ratio]
    if { $r eq "--" } { return "" }
    return "($r)"
}

# ------------------------------------------------------------ next shot ---
#
# DYE stages next-shot values in ::plugins::DYE::settings(next_*) and falls
# back to the core ::settings. We do the same, so the strip still works with
# DYE disabled.

proc ::lumen::data::_dye { field } {
    if { ![info exists ::plugins::DYE::settings(next_$field)] } { return "" }
    return [string trim [set ::plugins::DYE::settings(next_$field)]]
}

proc ::lumen::data::_field { field } {
    set v [_dye $field]
    if { $v ne "" } { return $v }
    return [string trim [_s ::settings($field)]]
}

proc ::lumen::data::bean_brand {} {
    set v [_field bean_brand]
    if { $v eq "" } { return [translate "No bean set"] }
    # Must stay on ONE line. The item is 272px wide at 40px Inter, so a
    # longer name wraps and the second line lands on top of the type/roast
    # line below it. ~13 characters is what fits; beyond that, truncate.
    return [_ellipsis $v 13]
}

# ---- identity, 0.23.0 -----------------------------------------------------
#
# The ROASTER is the small line and the BEAN TYPE is the hero. Roasters run
# long -- "MAN VERSUS MACHINE Specialty Coffee Roasters" is 44 characters --
# while the bean type is short and is what actually tells two bags apart on
# the counter. Leading with the roaster meant every hero line was truncated.

# Roaster, small line above the hero. 460px at 16px caption holds ~52
# characters, so this almost never truncates; the cap is a backstop.
proc ::lumen::data::bean_roaster_line {} {
    set v [_field bean_brand]
    if { $v eq "" } { return "" }
    return [_ellipsis $v 46]
}

# Bean type, the hero line. 460px at 40px Inter holds ~19 characters.
proc ::lumen::data::bean_name_line {} {
    set v [_field bean_type]
    if { $v ne "" } { return [_ellipsis $v 19] }
    # No type: fall back to the roaster rather than showing nothing, since
    # a bag with only a roaster is still a bag.
    set b [_field bean_brand]
    if { $b ne "" } { return [_ellipsis $b 19] }
    return [translate "No bean set"]
}

# Tasting notes, forced onto ONE line. Blank when unset -- the row is simply
# not drawn, so an empty field never leaves a gap. This is the best-populated
# optional bean field (42% of shots) and the most informative.
#
# bean_notes is genuinely MULTI-LINE in real data: this tablet's Morgon bag
# holds "Peru | Washed | Bourbon\nJuicy, Forest Berries, Cacao". Drawn as-is
# the second line ran straight through the cycler arrows and Edit. Newlines
# (and any other whitespace runs) collapse to a separator, and the result is
# capped at what 460px holds at the 16px caption size, so it can neither wrap
# nor overflow into the stepper columns.
proc ::lumen::data::bean_notes_line {} {
    set v [_field bean_notes]
    if { $v eq "" } { return "" }
    regsub -all {\s*[\r\n]+\s*} $v " - " v
    regsub -all {[ \t]+} $v " " v
    return [_ellipsis [string trim $v] 52]
}

# The same three for the LAST shot's card. The narrower column (274px) takes
# a tighter cap.
#
# 0.43.0: the FILE's bean first (last_shot_rec roaster/bean), the live
# settings only as the in-session fallback -- the same record-versus-plan
# split grind/dose/yield already follow. Until then the card read the live
# bean fields, so a shot loaded for a different bag (startup with a fresh
# bag scanned, or the fallback below) sat under the wrong name.
proc ::lumen::data::last_roaster_line {} {
    set v [string trim [_rec roaster]]
    if { $v eq "" } { set v [string trim [_s ::settings(bean_brand)]] }
    if { $v eq "" } { return "" }
    return [_ellipsis $v 30]
}

proc ::lumen::data::last_name_line {} {
    # 274px at font_primary (22px) holds ~24 characters.
    set v [string trim [_rec bean]]
    if { $v eq "" } { set v [string trim [_s ::settings(bean_type)]] }
    if { $v ne "" } { return [_ellipsis $v 24] }
    set b [string trim [_rec roaster]]
    if { $b eq "" } { set b [string trim [_s ::settings(bean_brand)]] }
    if { $b ne "" } { return [_ellipsis $b 24] }
    return "--"
}

# The grind the last shot was pulled at. ::settings(grinder_setting) persists
# across shots, so this reads the same as the next shot's grind until you
# change it -- the same caveat the dose and yield readouts already carry.
# Not routed through _is_pos: a grinder setting is not necessarily a number.
# Plenty of grinders are labelled in clicks, letters or half-steps, and the
# field is free text, so anything non-empty is a real setting.
proc ::lumen::data::last_grind {} {
    foreach src [list [_rec grind] [_s ::settings(grinder_setting)]] {
        set v [string trim $src]
        if { $v ne "" } { return $v }
    }
    return "--"
}

proc ::lumen::data::bean_sub {} {
    set parts {}
    set t [_field bean_type]
    if { $t ne "" } { lappend parts $t }
    set r [_field roast_date]
    if { $r ne "" } { lappend parts "[translate {roasted}] $r" }
    if { [llength $parts] == 0 } { return [translate "Tap to add bean details"] }
    return [join $parts "  -  "]
}

proc ::lumen::data::next_grind {} {
    set v [_field grinder_setting]
    if { $v eq "" } { return "--" }
    return $v
}

proc ::lumen::data::next_dose {} {
    return [_num [_s ::settings(grinder_dose_weight)] 1]
}

# Mirrors DYE's own get_next: the 2c profile type keeps its target in a
# separate setting.
proc ::lumen::data::_target_raw {} {
    if { [string trim [_s ::settings(settings_profile_type)]] eq "settings_2c" } {
        set v [_s ::settings(final_desired_shot_weight_advanced)]
        if { [_is_pos $v] } { return $v }
    }
    return [_s ::settings(final_desired_shot_weight)]
}

proc ::lumen::data::next_yield {} {
    return [_num [_target_raw] 1]
}

# One decimal, matching the +/- stepper's 0.1 increment (and fitting the
# 76px value span between the stepper pills).
proc ::lumen::data::next_ratio {} {
    set d [_s ::settings(grinder_dose_weight)]
    set y [_target_raw]
    if { ![_is_pos $d] || ![_is_pos $y] } { return "--" }
    if { [catch { set r [expr {double($y) / double($d)}] }] } { return "--" }
    return [format "1:%.1f" $r]
}

# The ratio as it appears UNDER the yield value (0.21.0). Parenthesised so it
# reads as a derived note rather than a second editable number, and blank --
# not "--" -- when there is nothing to derive, because an empty line under the
# yield is quieter than a placeholder.
proc ::lumen::data::next_ratio_note {} {
    set r [next_ratio]
    if { $r eq "--" } { return "" }
    return "($r)"
}

# The profile the NEXT shot will use. DYE can stage a profile for the next
# shot, so _field checks that first and falls back to the loaded one.
proc ::lumen::data::next_profile {} {
    set v [_field profile_title]
    if { $v eq "" } { return "--" }
    # The tile is 176 wide at 19px; ~18 characters fit before it wraps into
    # the row beneath.
    return [_ellipsis $v 18]
}

# The profile the LAST shot actually ran on.
#
# NOT ::settings(profile_title): that is the profile loaded RIGHT NOW, which
# stops matching the last shot the moment you switch profiles -- and showing
# the two side by side when they differ is the entire point of this line.
# ::lumen::last_shot_profile is latched at shot completion and seeded at
# startup from the newest history file.
proc ::lumen::data::last_profile {} {
    set v [string trim $::lumen::last_shot_profile]
    if { $v eq "" } { return "--" }
    return [_ellipsis $v 22]
}

# ---- chart legend with final values (0.43.1) ------------------------------
#
# The last sample of a live vector, or "" when the vector holds no shot
# (a cleared vector reads length 1 with a leading 0, so <= 1 is empty).
# In-memory BLT reads only; no file, no plugin.
proc ::lumen::data::_vec_last { vec } {
    if { [catch { set n [$vec length] }] || $n <= 1 } { return "" }
    if { [catch { set v [$vec range end end] }] } { return "" }
    if { ![string is double -strict $v] } { return "" }
    return $v
}

proc ::lumen::data::_legend { word vec unit {mult 1.0} } {
    set v [_vec_last $vec]
    if { $v eq "" } { return [translate $word] }
    return "[translate $word] [format %.1f [expr {$v * $mult}]]$unit"
}

# Weight and temperature read the vectors the chart PLOTS -- the app's
# pre-scaled espresso_weight_chartable (0.10 x g) and
# espresso_temperature_basket10th (degrees / 10) -- times ten. The raw
# espresso_weight / espresso_temperature_basket vectors are not what the
# loader restores from a shot file (tablet, 0.43.1 first push: those two
# legend entries stayed bare words), and the chartable pair is filled
# both by the loader and by the app during a live shot.
proc ::lumen::data::legend_pressure {} { return [_legend "Pressure" espresso_pressure " bar"] }
proc ::lumen::data::legend_flow {}     { return [_legend "Flow" espresso_flow " mL/s"] }
proc ::lumen::data::legend_weight {}   { return [_legend "Weight" espresso_weight_chartable " g" 10.0] }
proc ::lumen::data::legend_temp {}     { return [_legend "Temp" espresso_temperature_basket10th "[format %c 0xB0]C" 10.0] }

# When the LAST shot was pulled (0.43.1): the file's clock, latched with the
# rest of the record; in-session (record cleared at shot start) the core's
# espresso_clock, which is that shot's own clock. "Today 15:05",
# "Yesterday 14:24", else "Fri 12 Sep 12:40" -- honouring the CLOCK row's
# 12/24 h and day-month preferences. Blank when nothing is known.
proc ::lumen::data::last_shot_when {} {
    set c [_rec clock]
    if { $c eq "" } { set c [_s ::settings(espresso_clock)] }
    if { ![string is integer -strict $c] || $c <= 0 } { return "" }
    set now [clock seconds]
    set tf [expr {[::lumen::time_format] == 12 ? "%I:%M %p" : "%H:%M"}]
    if { [catch {
        set day  [clock format $c -format %Y-%m-%d]
        set t    [clock format $c -format $tf]
        if { $day eq [clock format $now -format %Y-%m-%d] } {
            set out "[translate Today] $t"
        } elseif { $day eq [clock format [expr {$now - 86400}] -format %Y-%m-%d] } {
            set out "[translate Yesterday] $t"
        } else {
            set df [expr {[::lumen::date_format] eq "mdy" ? "%a %b %d" : "%a %d %b"}]
            set out "[clock format $c -format $df] $t"
        }
    }] } { return "" }
    return $out
}

# The target under the live weight on the espresso page (0.43.1): what you
# are pouring towards. Blank when no target is set (a cleaning profile).
proc ::lumen::data::target_yield_note {} {
    set y [_target_raw]
    if { ![_is_pos $y] } { return "" }
    return "[translate of] [_num $y 1] g"
}

# Live scale weight for the flow pages. Shows "--" rather than blank here,
# because on those pages the column always needs to read as a value.
# Blank once the chart has data. An empty BLT graph autoscales x to
# -0.1..0.1, which reads as a broken chart rather than an empty one.
proc ::lumen::data::chart_empty_note {} {
    if { [catch { set n [espresso_elapsed length] }] } { return "" }
    if { $n > 1 } { return "" }
    return [translate "No shot data yet - pull a shot"]
}

# Last line of defence on anything shown as a duration. espresso_timer is
# ([clock milliseconds] - $::timers(espresso_start))/1000, so before
# espresso_start has ever been assigned it subtracts from zero and yields
# epoch time -- a colossal number. flush_pour_timer returns the literal
# strings "-0" and "-1" when its timer has not been started, and "%.0f" of
# "-0" prints "-0". Anything outside a plausible flow duration is a glitch,
# not a reading; the +0 normalises "-0" to 0.
proc ::lumen::data::_sane_secs { v } {
    if { ![string is double -strict $v] } { return 0 }
    if { $v < 0 || $v > 3600 } { return 0 }
    return [expr {$v + 0}]
}

# Elapsed seconds of the flow THIS page visit is showing, or 0.
#
# 0.24.0. The core's four flow timers (de1app-core/vars.tcl:295-339) are only
# reset when the NEXT flow of that kind reaches its "during" phase
# (binary.tcl:1507-1527), while the page opens as soon as the machine enters
# the state. Between those two moments every timer still describes the
# PREVIOUS flow, and reading it there is what the owner saw: the espresso page
# showed ~450s -- the seconds since the last shot began -- for a few frames
# before flipping to 0 and counting normally. _sane_secs cannot catch that,
# because 450 is a perfectly plausible number.
#
# So the value is only shown when the flow it describes started after this
# page was last shown (::lumen::flow_opened, latched by latch_flow_open on
# each page's `show` action):
#
#   stop unset/0/before start -> the flow is RUNNING, count from start. Not
#       gated on the open time: if a page is shown mid-flow -- the skin
#       reloading, or a dialog closing over it -- the count must not blank.
#   stop after start          -> the flow has FINISHED. Show its total only if
#       it is the one this visit ran, so the final time stays on screen after
#       the shot; a flow from an earlier visit reads 0.
#
# Integer division throughout, matching the core's own timer procs, so the
# display truncates rather than rounding up at the half second.
proc ::lumen::data::_flow_secs { page start_key stop_key } {
    set st 0 ; set sp 0
    catch { set st $::timers($start_key) }
    catch { set sp $::timers($stop_key) }

    if { ![string is double -strict $st] || $st <= 0 } { return 0 }
    if { ![string is double -strict $sp] } { set sp 0 }

    if { $sp <= 0 || $sp < $st } {
        return [expr {([clock milliseconds] - $st) / 1000}]
    }

    set opened 0
    catch { set opened $::lumen::flow_opened($page) }
    if { $st < $opened } { return 0 }
    return [expr {($sp - $st) / 1000}]
}

proc ::lumen::data::_flow_text { page start_key stop_key } {
    set t 0
    catch { set t [_flow_secs $page $start_key $stop_key] }
    return "[format %.0f [_sane_secs $t]]s"
}

# Each page reads ITS OWN timer. They used to share espresso_secs, which is
# time since the last ESPRESSO started rather than the duration of the current
# flow: plausible shortly after a shot and 0 once more than an hour had passed
# (_sane_secs rejects > 3600). That was the "stuck at 0s" of 0.23.2.
proc ::lumen::data::espresso_secs {} {
    return [_flow_text espresso espresso_start espresso_stop]
}

proc ::lumen::data::steam_secs {} {
    return [_flow_text steam steam_pour_start steam_pour_stop]
}

proc ::lumen::data::water_secs {} {
    return [_flow_text water water_pour_start water_pour_stop]
}

proc ::lumen::data::flush_secs {} {
    return [_flow_text hotwaterrinse flush_pour_start flush_pour_stop]
}

# The steam page's temperature is the STEAM HEATER sensor
# (::de1(steam_heater_temperature) <- ShotSample(SteamTemp), de1_de1.tcl:544),
# which idles at the steam set point -- ~158C when the setting is 160. That
# is a real reading, not a glitch, but shown as plain "TEMP" it looks like a
# broken value. The column is labelled STEAM HEATER and this line states the
# set point underneath, so the number reads as intentional.
proc ::lumen::data::steam_target_note {} {
    set t [_s ::settings(steam_temperature)]
    if { ![string is double -strict $t] || $t <= 0 } { return "" }
    if { [catch { set out [return_temperature_measurement $t 1] }] } { return "" }
    return "[translate {target}] $out"
}

# ---- machine stepper readouts (Lumen settings page) -----------------------

proc ::lumen::data::brew_temp_value {} {
    set t [_s ::settings(espresso_temperature)]
    if { ![string is double -strict $t] } { return "--" }
    if { [catch { set out [return_temperature_measurement $t 0] }] } { return "--" }
    return $out
}

proc ::lumen::data::steam_time_value {} {
    set v [_s ::settings(steam_timeout)]
    if { ![string is double -strict $v] } { return "--" }
    if { $v <= 0 } { return [translate "off"] }
    return "[expr {round($v)}]s"
}

# steam_flow is stored as ml/s x 100 (Streamline steps it by 10 = 0.1 ml/s).
proc ::lumen::data::steam_flow_note {} {
    set v [_s ::settings(steam_flow)]
    if { ![string is double -strict $v] } { return "" }
    return "[format %.1f [expr {$v / 100.0}]] mL/s"
}

# The same number without the unit, for the big value in FLOW mode -- the row
# already says Flow, so "0.8 mL/s" at 26px mono only crowds the pills.
proc ::lumen::data::steam_flow_value {} {
    set v [_s ::settings(steam_flow)]
    if { ![string is double -strict $v] } { return "--" }
    return [format %.1f [expr {$v / 100.0}]]
}

# ---- alternating rows (0.26.0) --------------------------------------------
#
# STEAM shows time OR flow, HOT WATER temperature OR volume: one -/+ group per
# row driving whichever half is selected, with the other shown small beneath
# it. Owner request, from a mockup.
#
# The mode is a Lumen preference, not a machine setting, and it persists --
# whichever half you last steered is the one waiting for you next time.

proc ::lumen::data::steam_value {} {
    if { [::lumen::steam_mode] eq "flow" } { return [steam_flow_value] }
    return [steam_time_value]
}

proc ::lumen::data::steam_value_alt {} {
    if { [::lumen::steam_mode] eq "flow" } { return [steam_time_value] }
    # 0.43.1: WITH its unit -- as the small line it has no FLOW label to
    # lean on, and a bare "2.5" under "35s" read as nothing in particular.
    return [steam_flow_note]
}

proc ::lumen::data::water_value {} {
    if { [::lumen::water_mode] eq "vol" } { return [water_volume_value] }
    return [water_temp_note]
}

proc ::lumen::data::water_value_alt {} {
    if { [::lumen::water_mode] eq "vol" } { return [water_temp_note] }
    return [water_volume_value]
}

# The mode line, split across TWO text items so the selected half can be the
# accent colour and the other one dim: a canvas text item's -fill is fixed at
# creation, so the words move between two fixed-colour items rather than the
# colours moving between two fixed words.
proc ::lumen::data::steam_mode_active {} {
    if { [::lumen::steam_mode] eq "flow" } { return [translate "FLOW"] }
    return [translate "TIME"]
}

proc ::lumen::data::steam_mode_other {} {
    if { [::lumen::steam_mode] eq "flow" } { return "| [translate {time}]" }
    return "| [translate {flow}]"
}

proc ::lumen::data::water_mode_active {} {
    if { [::lumen::water_mode] eq "vol" } { return [translate "VOL"] }
    return [translate "TEMP"]
}

proc ::lumen::data::water_mode_other {} {
    if { [::lumen::water_mode] eq "vol" } { return "| [translate {temp}]" }
    return "| [translate {vol}]"
}

proc ::lumen::data::flush_time_value {} {
    set v [_s ::settings(flush_seconds)]
    if { ![string is double -strict $v] } { return "--" }
    return "[expr {round($v)}]s"
}

proc ::lumen::data::water_volume_value {} {
    set v [_s ::settings(water_volume)]
    if { ![string is double -strict $v] } { return "--" }
    return "[expr {round($v)}] ml"
}

proc ::lumen::data::water_temp_note {} {
    set t [_s ::settings(water_temperature)]
    if { ![string is double -strict $t] } { return "" }
    if { [catch { set out [return_temperature_measurement $t 1] }] } { return "" }
    return $out
}

# The theme that is on screen right now. 0.47.0: a tap applies live, so
# there is no pending state to show any more.
proc ::lumen::data::theme_label {} {
    set m $::lumen::theme_mode
    if { $m eq "dark" } { return [translate "Dark"] }
    if { $m eq "custom" } { return [translate "Custom"] }
    return [translate "Light"]
}

# 0.54.0: the caption names the theme on screen and what the Change
# button offers (it is no longer a tap of its own). 0.47.0: after a
# failed custom apply it carries the reason instead.
proc ::lumen::data::theme_note {} {
    if { $::lumen::theme_status ne "" } { return $::lumen::theme_status }
    set now [theme_label]
    if { [::lumen::auto_enabled] } {
        append now " ([translate Auto], [translate $::lumen::custom::active_base] [translate glass])"
    }
    return "[translate "Now"] $now. [translate "Dark, Light, presets or your own colours."]"
}

proc ::lumen::data::version_line {} {
    return "Lumen v$::lumen::version"
}

proc ::lumen::data::bag_count_value {} {
    return [::lumen::bag_count]
}

# The bag cycler's page indicator (0.27.0): one dot per reachable bag, filled
# for the one loaded. Leftmost is the most recent bag, which is the direction
# the left arrow moves in.
#
# Drawn as TEXT, not as canvas ovals, because a canvas item's -fill is fixed
# at creation: N ovals would need retagging and reconfiguring on every cycle,
# while a text item is re-evaluated on the refresh tick for free. Both glyphs
# were verified present in the shipped Inter faces before being used, and go
# through [format %c] rather than literal UTF-8 -- a literal arrow in this
# file was mangled once already (Grind Advisor v2.0.2's lesson).
proc ::lumen::data::bag_dots {} {
    set n [llength $::lumen::bag_list]
    # One bag is not a carousel, and zero means SDB has nothing to say.
    if { $n <= 1 } { return "" }
    set idx [::lumen::bag_index]
    set filled [format %c 0x25CF]
    set hollow [format %c 0x25CB]
    set out {}
    for { set i 0 } { $i < $n } { incr i } {
        lappend out [expr {$i == $idx ? $filled : $hollow}]
    }
    return [join $out "  "]
}

# Which bag of how many, for anyone who cannot read the dots at a glance.
proc ::lumen::data::bag_position {} {
    set n [llength $::lumen::bag_list]
    if { $n <= 1 } { return "" }
    set idx [::lumen::bag_index]
    if { $idx < 0 } { return "" }
    return "[expr {$idx + 1}]/$n"
}

# Water in the tank, in millilitres (0.24.0, owner request).
#
# ::de1(water_level) is the sensor reading in MILLIMETRES, already corrected
# by ::de1(water_level_mm_correction) where the notification is parsed
# (de1_comms.tcl:467). The mm -> mL curve comes from the machine's CAD and
# lives in the core as water_tank_level_to_milliliters (vars.tcl:3924), so
# that is what converts it -- exactly as DSx2 does it (procs_vars.tcl:470).
# Never reimplement that table here.
#
# The core seeds water_level to 20 before any machine has connected
# (machine.tcl:137), which would render as a confident "537 ml" with nothing
# plugged in, so the readout is suppressed unless the machine is actually
# talking to us. ::de1(last_ping) is the app's own liveness stamp and the
# water-level notification is one of the things that refreshes it
# (bluetooth.tcl:2640-2645), so it stays fresh for as long as there is a
# reading to show -- including while the machine is idle. 10s is the core's
# own staleness threshold (bluetooth.tcl:1693).
proc ::lumen::data::_water_ml_num {} {
    set ping 0
    catch { set ping $::de1(last_ping) }
    if { ![string is double -strict $ping] || $ping <= 0 } { return "" }
    if { [expr {[clock seconds] - $ping}] > 10 } { return "" }

    set mm [_s ::de1(water_level)]
    if { ![string is double -strict $mm] || $mm <= 0 } { return "" }
    if { [catch { set ml [water_tank_level_to_milliliters $mm] }] } { return "" }
    if { ![string is double -strict $ml] } { return "" }
    return [expr {round($ml)}]
}

# 0.43.1: the readout warns. Under the threshold (default 300 ml, a couple
# of shots plus a flush) the value moves from the blue item to an amber
# one -- two stacked fixed-colour items, the maintenance-dot pattern. The
# number itself is unchanged; only which item carries it.
#
# 0.45.0: the threshold is a preference (LOW WATER row on the settings
# page), stored like the bag count and clamped the same way so a
# hand-edited settings file can never push it outside 100..800.
proc ::lumen::water_low_ml {} {
    set v 300
    catch {
        if { [info exists ::settings(lumen_water_low_ml)] \
          && $::settings(lumen_water_low_ml) ne "" } {
            set v $::settings(lumen_water_low_ml)
        }
    }
    if { ![string is integer -strict $v] } { set v 300 }
    if { $v < 100 } { set v 100 }
    if { $v > 800 } { set v 800 }
    return $v
}

proc ::lumen::data::water_low_value {} {
    return "[::lumen::water_low_ml] ml"
}

proc ::lumen::data::water_ml {} {
    set ml [_water_ml_num]
    if { $ml eq "" || $ml < [::lumen::water_low_ml] } { return "" }
    return "$ml ml"
}

proc ::lumen::data::water_ml_low {} {
    set ml [_water_ml_num]
    if { $ml eq "" || $ml >= [::lumen::water_low_ml] } { return "" }
    return "$ml ml"
}

# (0.34.0: water_label is gone with the card corner readout; the taskbar
# shows the bare blue value, which needs no heading.)

# 0.53.0 favorite profile slots (taskbar digits 1 2 3).
#
# One preference, ::settings(lumen_fav_profiles): a dict slot -> {filename
# title}, slots 1..3, written only by a tap on an EMPTY slot (stores the
# profile loaded right now) and by the settings header's Clear link. Read
# with validation on every 200 ms tick: a missing, malformed or partial
# value reads as "no favorites", never as an error.
proc ::lumen::fav_slots {} {
    set d [::lumen::data::_s ::settings(lumen_fav_profiles)]
    if { $d eq "" || [catch { dict size $d }] } { return {} }
    set out [dict create]
    foreach n {1 2 3} {
        if { ![dict exists $d $n] } { continue }
        set v [dict get $d $n]
        if { [llength $v] != 2 } { continue }
        set fn [string trim [lindex $v 0]]
        if { $fn eq "" } { continue }
        dict set out $n [list $fn [lindex $v 1]]
    }
    return $out
}

# {filename title} for slot n, or "" when the slot is empty.
proc ::lumen::fav_slot { n } {
    set d [fav_slots]
    if { [dict exists $d $n] } { return [dict get $d $n] }
    return ""
}

# "empty", "set" or "active" (the slot's file is the loaded profile).
proc ::lumen::fav_state { n } {
    set v [fav_slot $n]
    if { $v eq "" } { return "empty" }
    set cur [string trim [::lumen::data::_s ::settings(profile_filename)]]
    if { $cur ne "" && $cur eq [lindex $v 0] } { return "active" }
    return "set"
}

# 0.57.0: the slots show NAMES. Three stacked fixed-ink items per slot
# share the slot's centre; the text moves between them (the taskbar dot
# pattern -- a canvas item's -fill is fixed at creation). Empty reads as
# a dim "+" (the data mono, the steppers' own plus), set as the profile
# title in the icons' grey, active as the title in crema over the halo.
proc ::lumen::data::fav_empty { n } {
    if { [::lumen::fav_state $n] eq "empty" } { return "+" }
    return ""
}
proc ::lumen::data::fav_set { n } {
    if { [::lumen::fav_state $n] eq "set" } { return [::lumen::fav_title $n] }
    return ""
}
proc ::lumen::data::fav_active { n } {
    set on [expr {[::lumen::fav_state $n] eq "active"}]
    ::lumen::_fav_glow_sync $n $on
    if { $on } { return [::lumen::fav_title $n] }
    return ""
}

# The slot's title (the file name when the title is blank), fitted to
# the slot's inner width: measured in the caption font -- physical px,
# like the font itself -- and cut with an ellipsis until it fits, so a
# long name never wraps or runs into the next slot. Memoised per title:
# the 200 ms tick measures nothing once a name has been seen. Off-tablet,
# or if measuring throws, a 20-character cut stands in.
namespace eval ::lumen { variable fav_fit [dict create] }
proc ::lumen::fav_title { n } {
    variable fav_fit
    set v [fav_slot $n]
    if { $v eq "" } { return "" }
    set title [string trim [lindex $v 1]]
    if { $title eq "" } { set title [lindex $v 0] }
    if { [dict exists $fav_fit $title] } { return [dict get $fav_fit $title] }
    set out [_fit_caption $title $::lumen::L(bar_fav_text_w)]
    if { [dict size $fav_fit] > 64 } { set fav_fit [dict create] }
    dict set fav_fit $title $out
    return $out
}

# `s` cut to fit `design_w` design px in the caption font, "..." on the
# cut. Any measuring trouble falls back to a character cap.
proc ::lumen::_fit_caption { s design_w } {
    variable L
    set max_px ""
    catch {
        lassign [::lumen::custom::screen] W H
        if { $W > 0 } { set max_px [expr {int($design_w * $W / 1340.0)}] }
    }
    if { $max_px eq "" || [catch { set w [font measure $L(font_caption) $s] }] \
             || ![string is integer -strict $w] } {
        return [::lumen::data::_ellipsis $s 20]
    }
    if { $w <= $max_px } { return $s }
    set n [string length $s]
    while { $n > 1 } {
        incr n -1
        set t "[string trimright [string range $s 0 [expr {$n - 1}]]]..."
        if { [catch { set w [font measure $L(font_caption) $t] }] || ![string is integer -strict $w] } {
            return [::lumen::data::_ellipsis $s 20]
        }
        if { $w <= $max_px } { return $t }
    }
    return "..."
}

# The halo behind the ACTIVE slot (0.57.0). One photo, painted by
# fav_glow_photo from the theme's crema, is shared by the three slot
# items; a 1x1 blank stands in the other two. The item is never hidden
# or shown -- dui re-shows every item on page load -- the IMAGE moves,
# as the theme's background swap does. Called from the fav_active
# accessor on the 200 ms tick, so it follows a profile change from
# anywhere (the stock chooser, Drink Menu, a slot tap) within a tick;
# it touches the canvas only when a slot's state changes.
namespace eval ::lumen {
    variable fav_glow_img ""
    variable fav_glow_blank ""
    variable fav_glow_state [dict create]
}
proc ::lumen::_fav_glow_sync { n on } {
    variable fav_glow_img
    variable fav_glow_blank
    variable fav_glow_state
    if { [dict exists $fav_glow_state $n] && [dict get $fav_glow_state $n] == $on } { return }
    dict set fav_glow_state $n $on
    if { $fav_glow_img eq "" || $fav_glow_blank eq "" } { return }
    if { [catch {
        [dui canvas] itemconfigure lumen_favglow_$n -image [expr {$on ? $fav_glow_img : $fav_glow_blank}]
    } err] } {
        msg -ERROR "Lumen: favorite $n halo not switched: $err"
    }
}

# 0.57.3 instant tap answer. _fav_light_now lights slot n (and only n)
# and paints it straight away -- the press_flash precedent's `update
# idletasks`, no event processing. _fav_refresh_now runs dui's own
# on-screen variable pass for the page (which cancels and re-arms its own
# 200 ms timer, as every page load does), so the slot inks and the halo
# re-derive from the profile actually loaded, then paints.
proc ::lumen::_fav_light_now { n } {
    foreach k {1 2 3} { _fav_glow_sync $k [expr {$k == $n}] }
    update idletasks
}
proc ::lumen::_fav_refresh_now {} {
    if { [catch { dui page update_onscreen_variables } err] } {
        msg -ERROR "Lumen: favorite slots not refreshed: $err"
        return
    }
    update idletasks
}

# The halo photo for the CURRENT palette: bar_fav_glow_w x bar_h design
# px at the screen's scale, crema, 0.62 inside the pill. Throws without
# Tk or a screen size; the build then draws no halo and the active slot
# is told apart by its crema text alone.
proc ::lumen::fav_glow_photo {} {
    variable C
    variable L
    lassign [::lumen::custom::screen] W H
    if { $W <= 0 } { error "no screen size" }
    set sx [expr {$W / 1340.0}] ; set sy [expr {$H / 800.0}]
    if { [scan $C(crema) "#%2x%2x%2x" r g b] != 3 } { error "crema '$C(crema)' is not #rrggbb" }
    # 0.57.1 (owner: "very dark", then "lighter still"; 0.57.2 "a bit
    # darker"): quieter than the 0.62 it launched with -- 0.36 inside --
    # and on LIGHT glass, where the crema is a dark amber that painted a
    # brown pill, the tint is the crema lifted half way toward white, so
    # the halo reads as a pale glow behind the name. Light is read off
    # the ground's luminance, so the custom theme's two halves sort
    # themselves. Tuned on the tablet: 0.62 brown, 0.30/60% too faint.
    set a 0.36
    if { [scan $C(bg) "#%2x%2x%2x" gr gg gb] == 3 \
             && (0.2126 * $gr + 0.7152 * $gg + 0.0722 * $gb) / 255.0 > 0.45 } {
        foreach v {r g b} { set $v [expr {int(round([set $v] + (255 - [set $v]) * 0.5))}] }
    }
    set png [::lumen::custom::halo_png [list $r $g $b] $a \
        [expr {int(round($L(bar_fav_glow_w) * $sx))}] [expr {int(round($L(bar_h) * $sy))}] \
        [expr {int(round($L(bar_fav_glow_soft) * $sy))}]]
    return [image create photo -data $png]
}

# A live theme change: paint the halo again from the new crema, hand it
# to every lit slot, free the old photo. (apply_theme calls this after
# the photo panels; nothing to do while no halo exists.)
proc ::lumen::_redraw_fav_glow {} {
    variable fav_glow_img
    variable fav_glow_state
    if { $fav_glow_img eq "" } { return }
    set old $fav_glow_img
    set fav_glow_img [fav_glow_photo]
    set can [dui canvas]
    dict for {n on} $fav_glow_state {
        if { $on } { $can itemconfigure lumen_favglow_$n -image $fav_glow_img }
    }
    image delete $old
}

# The settings header link, blank while no slot is set.
proc ::lumen::data::fav_clear_label {} {
    if { [dict size [::lumen::fav_slots]] == 0 } { return "" }
    return [translate "Clear favorite profiles"]
}

# 0.34.0 clock format preferences (Lumen settings CLOCK row). Read with
# defaults so an unset key -- every install until now -- behaves exactly
# as 0.31.0 did: 24-hour, day-month.
proc ::lumen::time_format {} {
    if { [info exists ::settings(lumen_time_format)] \
             && $::settings(lumen_time_format) eq "12" } { return 12 }
    return 24
}

# ---- Auto theme schedule (0.55.0; 0.56.0 owner redesign) ----------------
#
# Auto is a BASE for the custom theme: light glass from one time of day,
# dark glass from another, with the owner's own hues and accent on both
# (0.55.0 flipped the two baked themes instead and switched itself off
# at the picker's Done -- the owner found that incoherent). So:
#   lumen_custom_base         dark | light | auto (saved by the picker's Done)
#   lumen_auto_light_from     minutes past midnight, 0..1439 (default 420 = 07:00)
#   lumen_auto_dark_from      minutes past midnight, 0..1439 (default 1140 = 19:00)
# The schedule is in force only while the custom theme is on screen with
# base auto. Every read is guarded and clamped: junk reads as the default.
proc ::lumen::auto_enabled {} {
    if { $::lumen::theme_mode ne "custom" } { return 0 }
    return [expr {[dict get [::lumen::custom::prefs] base] eq "auto"}]
}

proc ::lumen::auto_minutes { which } {
    if { $which eq "light" } { set key lumen_auto_light_from ; set default 420 } \
    else { set key lumen_auto_dark_from ; set default 1140 }
    if { ![info exists ::settings($key)] } { return $default }
    set v $::settings($key)
    if { ![string is integer -strict $v] || $v < 0 || $v > 1439 } { return $default }
    return $v
}

proc ::lumen::auto_time_text { which } {
    set m [auto_minutes $which]
    return [format "%02d:%02d" [expr {$m / 60}] [expr {$m % 60}]]
}

# The theme the schedule wants at `now` (minutes past midnight; the clock
# when omitted). Light runs from light_from up to dark_from, wrapping
# past midnight when light_from is the later time; equal times mean Dark
# all day. scan, not expr, on the clock fields: "08" is not octal.
proc ::lumen::auto_wanted { {now ""} } {
    if { $now eq "" } {
        set s [clock seconds]
        set now [expr {[scan [clock format $s -format %H] %d] * 60 + [scan [clock format $s -format %M] %d]}]
    }
    set l [auto_minutes light] ; set d [auto_minutes dark]
    if { $l == $d } { return dark }
    if { $l < $d } { return [expr {$now >= $l && $now < $d ? "light" : "dark"}] }
    return [expr {$now >= $l || $now < $d ? "light" : "dark"}]
}

# The minute tick. Rescheduled FIRST, so a failure inside can never stop
# the clock; the check itself is a separate proc so the harness can drive
# it. Errors are logged, never swallowed.
proc ::lumen::auto_tick {} {
    after cancel ::lumen::auto_tick
    after 60000 ::lumen::auto_tick
    if { [catch { auto_check } err] } {
        msg -ERROR "Lumen: auto theme tick failed: $err"
    }
}

# Switches only when Auto is in force, the scheduled base differs from the
# one on screen (::lumen::custom::active_base, recorded by set_palette),
# the skin is on its home or saver page, and the machine is idle or asleep
# (machine_busy, the favorites' guard): the switch re-applies the custom
# theme -- a 1-5 s synchronous photo swap behind the wait pill when that
# half's files exist (Done draws both halves), a bake when they do not --
# so it happens only where nothing else is going on. Returns the reason
# it did or did not switch.
proc ::lumen::auto_check {} {
    if { ![auto_enabled] } { return off }
    set wanted [auto_wanted]
    if { $wanted eq $::lumen::custom::active_base } { return same }
    if { [dui page current] ni {off saver} } { return page }
    if { [machine_busy] ne "" } { return busy }
    msg -INFO "Lumen: auto theme: [clock format [clock seconds] -format %H:%M] -> $wanted glass"
    if { ![::lumen::act::_switch_theme custom] } { return failed }
    return switched
}

# The schedule line on the picker reads the PENDING times while it is
# open (seeded from the prefs by open_theme_picker, saved by Done).
proc ::lumen::pend_minutes { which } {
    variable ::lumen::custom::pend
    set k [expr {$which eq "light" ? "lf" : "df"}]
    if { [info exists pend($k)] && [string is integer -strict $pend($k)] && $pend($k) >= 0 && $pend($k) <= 1439 } {
        return $pend($k)
    }
    return [auto_minutes $which]
}
proc ::lumen::data::auto_light_text {} {
    set m [::lumen::pend_minutes light]
    return "[translate Light] [format %02d:%02d [expr {$m / 60}] [expr {$m % 60}]]"
}
proc ::lumen::data::auto_dark_text {} {
    set m [::lumen::pend_minutes dark]
    return "[translate Dark] [format %02d:%02d [expr {$m / 60}] [expr {$m % 60}]]"
}

proc ::lumen::date_format {} {
    if { [info exists ::settings(lumen_date_format)] \
             && $::settings(lumen_date_format) eq "mdy" } { return "mdy" }
    return "dmy"
}

# 0.31.0 taskbar clock. Rides the app's own 200ms onscreen-variable tick
# like every other live label (the tick only reconfigures the canvas item
# when the substituted string CHANGES, dui.tcl:6981-6984, so this costs one
# `clock format` per tick and one redraw per displayed minute). One
# `clock seconds` per tick is the water readout's own precedent above.
# Cheap, no filesystem -- per the accessor rule at the top of this section.
proc ::lumen::data::bar_time {} {
    if { [::lumen::time_format] == 12 } {
        # Zero-padded on purpose: the day label sits at a fixed x, so the
        # widest 12h time must be constant-width ("08:05 AM").
        return [clock format [clock seconds] -format "%I:%M %p"]
    }
    return [clock format [clock seconds] -format "%H:%M"]
}

# Day as its own item: the time is a number and takes the mono face, the
# day is a word and takes the sans caption -- the typography rule.
proc ::lumen::data::bar_day {} {
    if { [::lumen::date_format] eq "mdy" } {
        return [clock format [clock seconds] -format "%a %b %d"]
    }
    return [clock format [clock seconds] -format "%a %d %b"]
}

# Live labels for the CLOCK row's two buttons: the time one names the
# mode, the date one shows a real sample of what the bar will print.
proc ::lumen::data::clock_time_label {} {
    if { [::lumen::time_format] == 12 } { return "12H" }
    return "24H"
}

proc ::lumen::data::clock_date_label {} {
    if { [::lumen::date_format] eq "mdy" } {
        return [clock format [clock seconds] -format "%b %d"]
    }
    return [clock format [clock seconds] -format "%d %b"]
}

# 0.32.0 maintenance state, for the taskbar dot. Guarded exactly like
# grind_rec above: info procs gate, catch, dict validated, degrade to "".
# status_summary is cache-backed on the plugin side (600s TTL plus a
# silent after-flow invalidation), so calling it on the 200ms tick is the
# same deal as recommendation_for_current_bag -- the plugin memoizes, the
# skin just reads. Returns "amber", "red", or "" (ok / plugin absent /
# anything malformed): the dot only exists to say "attention", so every
# failure mode maps to no dot.
proc ::lumen::data::maint_state {} {
    if { [info procs ::plugins::MaintenanceTracker::status_summary] eq "" } { return "" }
    if { [catch { set s [::plugins::MaintenanceTracker::status_summary] } err] } {
        msg -ERROR "Lumen: could not read the maintenance status: $err"
        return ""
    }
    if { $s eq "" || [catch { dict size $s }] } { return "" }
    if { ![dict exists $s ok] || ![dict get $s ok] } { return "" }
    if { ![dict exists $s state] } { return "" }
    set st [dict get $s state]
    if { $st in {amber red} } { return $st }
    return ""
}

# Two stacked fixed-colour items share the dot's spot; the glyph moves
# between them (the settings mode-line pattern -- a canvas item's -fill is
# fixed at creation). U+25CF via format %c: the proven glyph path.
proc ::lumen::data::maint_dot_amber {} {
    if { [maint_state] eq "amber" } { return [format %c 0x25CF] }
    return ""
}

proc ::lumen::data::maint_dot_red {} {
    if { [maint_state] eq "red" } { return [format %c 0x25CF] }
    return ""
}

proc ::lumen::data::live_weight {} {
    set w [_s ::de1(scale_weight)]
    if { ![_is_pos $w] } { return "--" }
    return "[_num $w 1] g"
}

proc ::lumen::data::scale_connected {} {
    if { [catch { set c [::device::scale::is_connected] }] } { return 0 }
    if { [string is true -strict $c] || $c == 1 } { return 1 }
    return 0
}

# The real Bluetooth glyph from the app's own icon font (dui.tcl:1640 maps
# "bluetooth" to U+F293). Falls back to the letters "BT" if that font could
# not be registered, so this can never render as a tofu box.
proc ::lumen::data::scale_bt {} {
    if { ![scale_connected] } { return "" }
    if { [::lumen::_font_family_ok symbol] } { return "\uF293" }
    return "BT"
}

# True only while a `ble connect` to the scale is actually in flight
# (de1app-core/bluetooth.tcl:2018 sets it, the disconnect handler clears it).
# Without this the readout jumps straight from "no scale" to a weight with
# nothing in between, which reads as "the skin isn't noticing my scale" during
# the core's 10-second-per-attempt retry loop.
proc ::lumen::data::scale_connecting {} {
    if { ![info exists ::currently_connecting_scale_handle] } { return 0 }
    if { [catch { set c [expr {$::currently_connecting_scale_handle != 0}] }] } { return 0 }
    return $c
}

# 0.43.1: "Connecting" with no exit. With the scale switched off the core's
# connect handle stays non-zero indefinitely, so the readout said
# "Connecting" for hours and nothing hinted that the box is the retry
# button. After 30 s of one continuous attempt it says "Tap to retry"
# instead. The stamp lives here, in memory, on the tick; a fresh attempt
# (handle back to 0 in between) restarts the window.
namespace eval ::lumen::data {
    variable connecting_since 0
}

proc ::lumen::data::_connecting_text {} {
    variable connecting_since
    set now [clock seconds]
    if { $connecting_since <= 0 } { set connecting_since $now }
    if { $now - $connecting_since > 30 } { return [translate "Tap to retry"] }
    return [translate "Connecting"]
}

proc ::lumen::data::scale_weight_line {} {
    variable connecting_since
    if { ![scale_connected] } {
        # No paired scale at all -- there is nothing to reconnect to.
        if { [_s ::settings(scale_bluetooth_address)] eq "" } {
            set connecting_since 0
            return [translate "no scale"]
        }
        if { [scale_connecting] } { return [_connecting_text] }
        set connecting_since 0
        return [translate "Connect"]
    }
    set connecting_since 0
    set w [_s ::de1(scale_weight)]
    if { $w eq "" } { return "--" }
    # An idle scale drifts a hair below zero and %.1f then prints "-0.0",
    # which looks broken. Anything inside a tenth is zero.
    if { ![catch { set n [expr {double($w)}] }] && abs($n) < 0.05 } { set w 0 }
    return "[_num $w 1] g"
}

# Live scale reading, blank unless a scale is actually reporting weight.
proc ::lumen::data::scale_line {} {
    set w [_s ::de1(scale_weight)]
    if { ![_is_pos $w] } { return "" }
    return "[_num $w 1] g [translate {on scale}]"
}

#############################################################################
#  Shot chart
#
#  The chart is a BLT/RBC `graph` widget bound to the app's live vectors, so
#  it draws itself during a shot and keeps the curves afterwards. Element
#  creation follows the proven pattern in skins/Streamline/skin.tcl.
#
#  Everything shares one 0..10 y axis, which is why two of the vectors are
#  pre-scaled by the app: espresso_temperature_basket10th is degrees/10, and
#  espresso_weight_chartable is 0.10 * scale weight (so 38g plots as 3.8).
#############################################################################

# 0.36.0 (owner request): the Raw/Smooth and Stages pills are gone and
# these two are policy, not preference -- Lumen charts are always
# smooth (Catmull-Rom through the recorded samples) with the stage
# separators shown. These procs stay as the single source of that
# policy for both chart builders (home + espresso page).
proc ::lumen::chart_smoothing {} {
    return "catrom"
}

proc ::lumen::stages_shown {} {
    return 1
}

# How many recent bean bags the home strip's bag cycler offers. Lumen
# preference, default 5, clamped to the same 3..10 band the stepper writes so
# a hand-edited settings file can never widen it.
#
# 0.20.0 ships the preference and its settings row only -- the cycler that
# consumes it lands in 0.21.0. The row has to exist now because the settings
# page background is baked, and a baked page cannot grow a row later without
# regenerating every asset.
# ---- the bag cycler's window (0.27.0) --------------------------------------
#
# The page indicator has to know how many bags the cycler offers and which one
# is loaded, on the 200 ms refresh tick. Asking SDB that often is exactly what
# the accessor rules forbid, so the LIST is cached here and only the index is
# computed live -- an lsearch over at most 10 strings, against values already
# in ::settings.
#
# Refreshed when the home page is shown and once at startup. That covers a new
# shot, a scan and a DYE edit without a database read per frame.

proc ::lumen::refresh_bag_list { args } {
    variable bag_list
    if { [catch {
        if { [info procs ::plugins::SDB::available_categories] eq "" } {
            set bag_list {}
            return
        }
        set bags [::plugins::SDB::available_categories bean_desc 1 {} 0]
        # Drop blanks: a shot saved with no bean fields yields an empty
        # bean_desc, and a dot for it would be a dot you cannot reach.
        set clean {}
        foreach b $bags {
            if { [string trim $b] ne "" } { lappend clean [string trim $b] }
        }
        set n [::lumen::bag_count]
        if { [llength $clean] > $n } { set clean [lrange $clean 0 [expr {$n - 1}]] }
        set bag_list $clean
    } err] } {
        msg -ERROR "Lumen: could not read the bag list: $err"
    }
}

# The loaded bag, as the string SDB builds for bean_desc: brand, type and
# roast date joined by single spaces.
proc ::lumen::current_bag {} {
    set cur [string trim "[::lumen::data::_field bean_brand] [::lumen::data::_field bean_type] [::lumen::data::_field roast_date]"]
    regsub -all { +} $cur " " cur
    return $cur
}

# Position of the loaded bag in that window, or -1 when it is not in it (a
# hand-typed bag, or one older than the window allows).
proc ::lumen::bag_index {} {
    variable bag_list
    if { [llength $bag_list] == 0 } { return -1 }
    return [lsearch -exact $bag_list [current_bag]]
}

# Which half of the STEAM row the -/+ pills drive: "time" or "flow" (0.26.0).
# A Lumen preference, stored the same way as the theme and the bag count, so
# an unknown or missing value falls back rather than throwing.
proc ::lumen::steam_mode {} {
    set v "time"
    catch {
        if { [info exists ::settings(lumen_steam_mode)] } {
            set v $::settings(lumen_steam_mode)
        }
    }
    if { $v ne "flow" } { set v "time" }
    return $v
}

# Same for HOT WATER: "temp" or "vol".
proc ::lumen::water_mode {} {
    set v "temp"
    catch {
        if { [info exists ::settings(lumen_water_mode)] } {
            set v $::settings(lumen_water_mode)
        }
    }
    if { $v ne "vol" } { set v "temp" }
    return $v
}

proc ::lumen::bag_count {} {
    set v 5
    catch {
        if { [info exists ::settings(lumen_bag_count)] \
          && $::settings(lumen_bag_count) ne "" } {
            set v $::settings(lumen_bag_count)
        }
    }
    if { ![string is integer -strict $v] } { set v 5 }
    if { $v < 3 }  { set v 3 }
    if { $v > 10 } { set v 10 }
    return $v
}

# ---- what counts as a real shot (0.43.0) ----------------------------------
#
# A cleaning run ("Cleaning/Forward Flush x5" and friends) is an espresso
# flow to the machine, so the core saves it to history/ exactly like a
# shot: a <clock>.shot file with `beverage_type cleaning` in its settings
# block, ~140 s of samples, and the bean fields of whatever bag was loaded
# copied in. Verified on the tablet 2026-09-15 (seven such files). Picking
# "the newest file" therefore put the cleaning run on the home chart and
# the LAST SHOT card until the next real shot, and because it carries the
# bag's bean fields, "the bag's newest SDB clock" landed on it too.
#
# The regex is GrindAdvisor's own _reject_re (GrindAdvisor.tcl:1101),
# copied verbatim so the skin and the advisor agree on what a real shot
# is; the 5 s floor is the workspace event-safety rule and GA's gate.
namespace eval ::lumen {
    variable nonespresso_re {\m(rinse|flush|backflush|clean|cleaning|descale|hot\s*water|water|steam|skip|dummy|calibrat\w*)\M}
}

proc ::lumen::text_is_nonespresso { text } {
    variable nonespresso_re
    set t [string trim $text]
    if { $t eq "" } { return 0 }
    return [regexp -nocase -- $nonespresso_re $t]
}

proc ::lumen::shot_min_secs {} { return 5.0 }

# "" when the parsed shot file (an array name in the caller) is a real
# espresso, else a short reason for the log. Checks the settings block's
# beverage_type and profile_title against the regex, then the duration.
proc ::lumen::_shot_reject_reason { propsvar } {
    upvar 1 $propsvar props
    if { [info exists props(settings)] && ![catch { array set s $props(settings) }] } {
        foreach f {beverage_type profile_title} {
            if { [info exists s($f)] && [text_is_nonespresso $s($f)] } {
                return "$f '[string trim $s($f)]'"
            }
        }
    }
    if { ![info exists props(espresso_elapsed)] } { return "no samples" }
    set t [lindex $props(espresso_elapsed) end]
    if { ![string is double -strict $t] } { return "no elapsed time" }
    if { $t < [shot_min_secs] } { return "only ${t}s" }
    return ""
}

# The files worth trying for the home chart, best first (0.43.0):
#
#   1. the bag's own shots, newest first, from SDB -- filtered in SQL the
#      way DYE filters its recent list (`beverage_type NOT IN cleaning /
#      calibrate`, COALESCE so an old untagged shot is kept)
#   2. any bag's shots, same filter -- a fresh bag with no shots yet gets
#      the previous bag's last shot rather than a blank chart, and the
#      LAST SHOT card names that bag (last_roaster_line reads the file)
#   3. the directory, newest FILENAME first (the 0.26.1 rule), capped --
#      the path with SDB absent or not loaded yet (the 5 s startup call)
#
# SDB is only ever its public read API, guarded and caught; nothing here
# opens a database handle or a file. Clock -> file is the app's own naming
# rule, and a clock whose file is gone (soft-deleted) is skipped. The
# loader applies the file-level filter (_shot_reject_reason) as the
# second net, so a stale or absent SDB only costs a few extra reads.
proc ::lumen::last_shot_candidates { {bag ""} } {
    set out {}
    set cap 12
    if { $bag eq "" } { set bag [current_bag] }
    set dir "[homedir]/history"
    if { ![file isdirectory $dir] } { return {} }

    if { [info procs ::plugins::SDB::shots] ne "" \
      && [info procs ::plugins::SDB::string2sql] ne "" } {
        set bev "COALESCE(beverage_type,'') NOT IN ('cleaning','calibrate')"
        set filters {}
        if { $bag ne "" } {
            lappend filters "bean_desc=[::plugins::SDB::string2sql $bag] AND $bev"
        }
        lappend filters $bev
        foreach filter $filters {
            if { [catch { set clocks [::plugins::SDB::shots clock 1 $filter $cap "clock DESC"] } err] } {
                msg -NOTICE "Lumen: SDB shot query failed ($filter): $err"
                continue
            }
            foreach c $clocks {
                if { ![string is integer -strict $c] } { continue }
                if { [catch { set f "$dir/[clock format $c -format %Y%m%dT%H%M%S].shot" }] } { continue }
                if { [file isfile $f] && $f ni $out } { lappend out $f }
            }
        }
    }

    # "Newest" means the most recent SHOT, which is not the most recently
    # modified FILE (0.26.1): the app names every shot file
    # YYYYMMDDTHHMMSS.shot, so sorting the names is sorting by shot time,
    # while editing a shot's metadata in the Shot History Editor touches
    # its mtime (a July shot corrected today became the home page, seen on
    # the tablet 2026-08-19). mtime remains the fallback for files whose
    # name is not a timestamp, used only when NO file has a parseable one.
    set named {} ; set others {}
    foreach f [glob -nocomplain -directory $dir *.shot] {
        if { [regexp {^[0-9]{8}T[0-9]{6}$} [file rootname [file tail $f]]] } {
            lappend named $f
        } else {
            lappend others $f
        }
    }
    if { [llength $named] > 0 } {
        # Every path shares the same directory prefix, so sorting the
        # paths sorts the names.
        foreach f [lrange [lsort -decreasing $named] 0 [expr {$cap - 1}]] {
            if { $f ni $out } { lappend out $f }
        }
    } else {
        set newest "" ; set newest_t 0
        foreach f $others {
            if { [catch { set t [file mtime $f] }] } { continue }
            if { $t > $newest_t } { set newest_t $t ; set newest $f }
        }
        if { $newest ne "" && $newest ni $out } { lappend out $newest }
    }
    return $out
}

# Loads the loaded bean's last real shot into the live chart vectors.
# Without this the home chart is blank every time you open the app until
# you pull a shot -- the vectors are created empty at launch and only
# filled as a shot runs; nothing in the app restores them.
#
# READ ONLY. It opens history files one at a time and writes nothing. In
# particular it does NOT copy a shot's `settings` block: the stock
# preview_history does `array set ::settings $props(settings)`, which would
# replace your entire current configuration -- grinder, dose, profile --
# with whatever was saved in that old shot. Only the curve vectors are
# taken, plus what the LAST SHOT card reports.
#
#   force  0: the startup call, refused once the vectors hold samples.
#          1: reload (SHE change, bag cycle, end of a cleaning run),
#             refused while a shot is genuinely in progress.
#   path   an exact file to load, as asked, with NO filtering -- for
#          callers (and tests) that already chose the file.
#   bag    the SDB bean_desc string whose last real shot is wanted;
#          "" means the bag loaded now. The bag cycler passes the bag it
#          just switched to (0.30.0 behaviour, now filtered like startup).
proc ::lumen::load_last_shot_curves { {force 0} {path ""} {bag ""} } {
    if { !$force } {
        # Startup path, unchanged: never clobber a shot in progress. This
        # guard also makes the plain call a no-op forever after -- once a
        # shot is loaded the vectors always hold samples -- which is fine at
        # startup and exactly why the reload path below cannot use it.
        if { ![catch { set n [espresso_elapsed length] }] && $n > 1 } { return }
    } else {
        # Reload path (0.28.0): the vectors legitimately hold the previous
        # shot, so length proves nothing. The real "shot in progress" signal
        # is history_saved: reset_gui_starting_espresso zeroes it when a shot
        # STARTS (machine.tcl:846) and the core's save sets it back to 1 --
        # and our own startup load sets it to 1 for exactly the same reason
        # (see the CRITICAL block below). So 0 here means live unsaved
        # samples, and reloading would clobber a shot mid-pull or arm the
        # 0.27.1 overwrite; refuse loudly rather than silently.
        if { ![catch { set hs $::settings(history_saved) }] && !$hs } {
            msg -INFO "Lumen: history reload skipped, a shot is in progress"
            return
        }
    }

    if { $path ne "" } {
        if { ![file isfile $path] } {
            msg -NOTICE "Lumen: requested shot file [file tail $path] does not exist"
            return
        }
        _load_shot_file $path 0
        return
    }

    set cands [last_shot_candidates $bag]
    if { [llength $cands] == 0 } {
        msg -INFO "Lumen: no shot files to load"
        return
    }
    foreach f $cands {
        if { [_load_shot_file $f 1] } { return }
    }
    msg -NOTICE "Lumen: none of [llength $cands] candidate shot files is a real espresso; chart left as-is"
}

# The LAST SHOT record from a parsed shot file (an array NAME in the
# caller): profile, clock, grind, dose, yield, roaster, bean. Split out of
# _load_shot_file in 0.57.5 so record_saved_shot can refresh the card
# without touching the chart vectors.
proc ::lumen::_read_shot_rec { propsvar } {
    upvar 1 $propsvar props
    # Seed the last shot's profile from the file's own settings block. This
    # reads into a LOCAL array on purpose -- the stock preview_history does
    # `array set ::settings $props(settings)`, which would replace the entire
    # live configuration with a stale one (see the warning above).
    if { [info exists props(settings)] } {
        if { ![catch { array set _shot_settings $props(settings) }] } {
            if { [info exists _shot_settings(profile_title)] } {
                variable last_shot_profile
                set last_shot_profile [string trim $_shot_settings(profile_title)]
            }
            # ... and what the shot was pulled with (0.24.1 yield, 0.25.0
            # grind and dose). These are what the LAST SHOT card reports:
            # they carry Shot History Editor corrections, which never reach
            # the live ::settings, and the yield does not survive a restart
            # there at all. See the last_shot_rec comment at the top.
            variable last_shot_rec
            # 0.28.0: this array must describe THIS file only. It used to be
            # add-only, which was invisible at startup (the array is empty)
            # but wrong on reload: delete the newest shot and the previous
            # shot becomes newest -- if ITS file lacks a value the deleted
            # shot's number would linger on the card.
            array unset last_shot_rec
            array set last_shot_rec {}
            # 0.43.1: the file's top-level clock joins the record (the
            # LAST SHOT card's "Today 15:05" line). It is not in the
            # settings block, so it is latched here, before the loop.
            if { [info exists props(clock)] \
              && [string is integer -strict [string trim $props(clock)]] } {
                set last_shot_rec(clock) [string trim $props(clock)]
            }
            foreach {key field} {grind   grinder_setting \
                                 dose    grinder_dose_weight \
                                 yield   drink_weight \
                                 roaster bean_brand \
                                 bean    bean_type} {
                if { ![info exists _shot_settings($field)] } { continue }
                set v [string trim $_shot_settings($field)]
                if { $v eq "" } { continue }
                # Grind and the bean fields are free text; the two weights
                # must be real positive numbers or they are noise.
                if { $key in {dose yield} && ![::lumen::data::_is_pos $v] } { continue }
                set last_shot_rec($key) $v
            }
        }
        array unset _shot_settings
    }
}

# 0.57.5: the shot that just ended, read back from the file the core just
# wrote, into the LAST SHOT record only -- the chart vectors already hold
# it. latch_shot_profile empties the record when a shot starts, so until
# now the card fell back to the live ::settings, and Grind Advisor moves
# grinder_setting to its next recommendation the moment the shot ends: the
# card said 3.8 for a shot pulled at 2.8 (owner screenshots 2026-09-24).
# The path is the core's own history_saved_shot_filename (vars.tcl:3465),
# trusted only when history_saved says the save happened and the name is
# this shot's espresso_clock; anything else keeps the fallback. Read-only.
proc ::lumen::record_saved_shot {} {
    set path ""
    if { [info exists ::settings(history_saved)] && $::settings(history_saved) eq "1" \
      && [info exists ::settings(history_saved_shot_filename)] \
      && [info exists ::settings(espresso_clock)] \
      && [string is integer -strict $::settings(espresso_clock)] } {
        set want "[clock format $::settings(espresso_clock) -format %Y%m%dT%H%M%S].shot"
        if { [file tail $::settings(history_saved_shot_filename)] eq $want } {
            set path $::settings(history_saved_shot_filename)
        }
    }
    if { $path eq "" || ![file isfile $path] } {
        msg -INFO "Lumen: no saved file for this shot; LAST SHOT keeps the live values"
        return
    }
    if { [catch {
        array set props [encoding convertfrom utf-8 [read_binary_file $path]]
    } err] } {
        msg -ERROR "Lumen: could not read $path: $err"
        return
    }
    _read_shot_rec props
    msg -INFO "Lumen: LAST SHOT record read from [file tail $path]"
}

# Reads ONE shot file into the chart vectors and the LAST SHOT record.
# Returns 1 when loaded, 0 when unreadable or (strict) rejected by
# _shot_reject_reason -- and a rejected file touches nothing, so the
# previous record survives while the caller tries the next candidate.
proc ::lumen::_load_shot_file { path strict } {
    if { [catch {
        array set props [encoding convertfrom utf-8 [read_binary_file $path]]
    } err] } {
        msg -ERROR "Lumen: could not read $path: $err"
        return 0
    }
    if { $strict } {
        set why [_shot_reject_reason props]
        if { $why ne "" } {
            msg -INFO "Lumen: skipping [file tail $path]: $why"
            return 0
        }
    }
    _read_shot_rec props

    if { ![info exists props(espresso_elapsed)] } { return 1 }

    # A saved shot's first samples often repeat elapsed = 0.0 while the
    # y-values already move (captured before the shot timer starts). Plotted,
    # that is a vertical line at x=0 ending in a stray point. Slice every
    # series from the first strictly positive elapsed value; all series are
    # appended per-sample by the app, so one index aligns them all.
    set skip 0
    foreach t $props(espresso_elapsed) {
        if { ![string is double -strict $t] || $t > 0.0 } { break }
        incr skip
    }
    if { $skip > 0 } {
        foreach v {espresso_elapsed espresso_pressure espresso_flow
                   espresso_flow_weight espresso_state_change
                   espresso_weight espresso_temperature_basket} {
            if { [info exists props($v)] } {
                set props($v) [lrange $props($v) $skip end]
            }
        }
    }

    # Vectors stored verbatim in the file.
    foreach v {espresso_elapsed espresso_pressure espresso_flow
               espresso_flow_weight espresso_state_change} {
        if { [info exists props($v)] } {
            catch { $v length 0 ; $v append $props($v) }
        }
    }

    # Two vectors the chart needs are DERIVED, not stored: the app scales
    # them at capture time so everything shares one 0..10 axis.
    if { [info exists props(espresso_weight)] } {
        catch {
            espresso_weight_chartable length 0
            foreach w $props(espresso_weight) {
                espresso_weight_chartable append [expr {0.10 * $w}]
            }
        }
    }
    if { [info exists props(espresso_temperature_basket)] } {
        catch {
            espresso_temperature_basket10th length 0
            foreach t $props(espresso_temperature_basket) {
                espresso_temperature_basket10th append [expr {$t / 10.0}]
            }
        }
    }

    # CRITICAL (0.27.1). Tell the app these samples are already in history.
    #
    # Without this line, loading a past shot into the live vectors ARMS THE
    # APP TO OVERWRITE THAT SHOT'S FILE. Measured on the tablet 2026-08-19,
    # from the log:
    #
    #   01:39:30  Lumen: loaded last shot curves from 20260818T164430.shot
    #   11:42:28  DE1 major state change: Idle => HotWaterRinse, pouring
    #   11:42:38  Saved this espresso to history      <-- the flush did this
    #
    # The 18 Aug shot file was rewritten by a FLUSH the next morning. Its
    # grinder_setting went from the corrected 8 back to the live 7.5, its
    # drink_weight from 37.8 to 0, and the file shrank from 29,948 bytes to
    # 21,506 -- the flush's own data, under the espresso's filename.
    #
    # The core's save is registered on after_flow_complete, which fires after
    # ANY flow, flush and steam included (vars.tcl:3440). Its only guard is
    #
    #     !$::settings(history_saved) && [espresso_elapsed length] > 5
    #                                 && [espresso_pressure length] > 5
    #
    # and the filename comes from ::settings(espresso_clock) -- still pointing
    # at the PREVIOUS shot (vars.tcl:3452-3457). It never checks that the flow
    # that just finished was an espresso, nor that the samples belong to this
    # session. Filling those vectors for the home chart is what makes that
    # guard pass, so the exposure is ours to close even though the write is
    # the core's.
    #
    # history_saved says "the samples currently in the vectors have been
    # written to history". Having just read them OUT of history, that is
    # exactly true. reset_gui_starting_espresso sets it back to 0 when a real
    # shot starts (machine.tcl:846), so a genuine shot still saves normally.
    if { [catch { set ::settings(history_saved) 1 } err] } {
        msg -ERROR "Lumen: could not mark the loaded shot as already saved: $err"
    }

    msg -INFO "Lumen: loaded last shot curves from [file tail $path] (history_saved marked)"
    return 1
}

# Public entry point for plugins that change what history/ holds (0.28.0).
#
# ShotHistoryEditor calls this after an edit, a delete or a restore, the same
# way it already tells Grind Advisor -- so the home page follows a correction
# without the user pulling a shot first. Everything downstream of the reload
# is already live: the chart's elements are bound to the BLT vectors, so
# refilling them redraws the graph, and the LAST SHOT card reads
# last_shot_rec through polled `var` bindings.
#
# The bag list is refreshed too: it is built from SDB, which the caller
# (ShotHistoryEditor via Grind Advisor's refresh_from_history) has just
# resynced -- deleting a bag's only shot removes that bag from the cycler.
#
# Callers guard on [info procs ::lumen::refresh_after_history_change], so a
# different skin simply skips this. Safe to call at any time: the loader's
# reload guard refuses while a shot is in progress. 0.43.0: the reload
# lands on the LOADED bean's last real shot, not the globally newest file.
proc ::lumen::refresh_after_history_change {} {
    if { [catch { load_last_shot_curves 1 } err] } {
        msg -ERROR "Lumen: history reload failed: $err"
    }
    if { [catch { refresh_bag_list } err] } {
        msg -ERROR "Lumen: bag list refresh failed: $err"
    }
    return ""
}

# Glass material provider (0.38.0 idea -> shipped 0.39.0).
#
# Plugin overlays -- GrindAdvisor's after-shot popup first -- can render an
# iOS-style frosted-glass card IF the active skin offers the material. Tk
# has no runtime blur or alpha, so the material is baked offline by
# tools/make_backgrounds.py from this skin's own home background:
#
#   lumen_home_glass[_light].png  full-screen blur+tint slab; the consumer
#                                 crops its card rect out of it with
#                                 `photo copy -from` (never rescales)
#   lumen_home_dim[_light].png    the home art dimmed, drawn full-screen as
#                                 the modal scrim around the card
#
# Recipe: the owner-approved 2026-09-01 "variant C" mockup (blur 20@1340w,
# dark tint 16/18/24 @34%, scrim 66%), with slab brightness/saturation run
# hotter than the mock because baked art has no live content doing half the
# glowing -- constants and rationale live in make_backgrounds.py GLASS.
#
# Contract -- returns {} unless BOTH hold, else a dict:
#   * the current page is the home page ("off"): the material is baked from
#     home art, and that is where the popup fires; on any other page a
#     consumer keeps its opaque look.
#   * both baked files exist in the folder matching this screen's exact
#     physical WxH (consumers draw in physical pixels and cannot rescale;
#     a 1280x800 tablet simply gets no material).
# Dict: ok 1  page off  theme dark|light  radius 26  glass <path> dim <path>
#
# A consumer guards with [info procs ::lumen::glass_material] -- on any
# other skin the proc does not exist and the popup stays opaque, which is
# the owner's explicit requirement. Called once per popup open (it touches
# the filesystem), NOT from a per-tick path.
proc ::lumen::glass_material {} {
    variable theme_mode

    set pg ""
    catch { set pg $::de1(current_context) }
    if { $pg eq "" } { catch { set pg [dui page current] } }
    if { $pg ne "off" } { return {} }

    set sw 0
    set sh 0
    catch { set sw [winfo screenwidth .]; set sh [winfo screenheight .] }
    if { $sw <= 0 || $sh <= 0 } { return {} }

    # 0.49.0: the custom theme serves its own material, painted on the
    # tablet by ensure_bake beside the page backgrounds (before this it
    # got the DARK files: the popup's ring and see-through card showed
    # the blue baked home art over a warm custom page -- owner report).
    # The consumer's `theme` is the text-colour set it should use, so a
    # custom theme reports its BASE (dark or light glass), never "custom".
    switch -exact -- $theme_mode {
        light   { set suffix "_light"  ; set theme light }
        custom  { set theme [dict get [::lumen::custom::prefs] eff] ; set suffix [::lumen::custom::suffix $theme] }
        default { set suffix ""        ; set theme dark }
    }
    set dir "[homedir]/skins/Lumen/${sw}x${sh}"
    set glass "$dir/lumen_home_glass$suffix.png"
    set dim   "$dir/lumen_home_dim$suffix.png"
    # 0.39.1: the PLAIN page background joins the contract. The consumer
    # rings its card with a crop of it so the overlay's boundary shows
    # pixel-identical art to the page it covers -- no seam, no guessed
    # blend color (owner report on 3.14.3: every edge read as a hard
    # cliff). It is the same file the page itself is built on.
    set bg "$dir/lumen_home$suffix.png"
    if { ![file exists $glass] || ![file exists $dim] || ![file exists $bg] } { return {} }

    return [dict create ok 1 page off theme $theme radius 26 \
        glass $glass dim $dim bg $bg]
}

# Recolours a CORE dui dialog that the skin cannot reach through theming.
#
# Pages like dui_item_selector -- the one behind "Select the beans batch" --
# are added by dui itself with `-theme default` hardcoded (dui.tcl:405), and
# their background is painted into a canvas item at `dui page add` time,
# before any skin code runs. Setting the aspect afterwards updates the
# lookup table but never repaints an existing item, which is why doing that
# had no effect at all (tried in 0.13.2, reverted).
#
# So reconfigure the item directly. dui tags page items with the PAGE NAME
# (`-tags [list $page pages]`), and that includes the text -- so filter by
# canvas item TYPE. Polygons are the rounded background; text is relabelled
# to a lighter ink, which is safe because it is scoped to this one page
# rather than the app-wide dtext aspect.
# Records the profile a shot is about to run with.
#
# Hooked to the espresso page's `show`, which is the moment a shot starts, so
# the value captured is the profile that shot actually uses. Doing this on
# flow COMPLETE would be wrong in a subtle way: after_flow_complete fires for
# steam, hot water and flush too, and any of those could land after you have
# already switched profiles for the next coffee.
proc ::lumen::latch_shot_profile { args } {
    variable last_shot_profile
    variable last_shot_rec
    variable last_flow_nonespresso
    catch {
        set p [string trim [::lumen::data::_s ::settings(profile_title)]]
        if { $p ne "" } { set last_shot_profile $p }
    }
    # 0.43.0: is the flow about to run a real espresso? The loaded
    # profile carries beverage_type (cleaning / calibrate / espresso ...)
    # and its title; either naming a non-espresso run arms
    # after_flow_complete to put the bean's last real shot back.
    set last_flow_nonespresso 0
    # 0.57.5: arms after_flow_complete to read this shot's record back.
    variable shot_rec_pending 1
    catch {
        foreach f {beverage_type profile_title} {
            if { [text_is_nonespresso [::lumen::data::_s ::settings($f)]] } {
                set last_flow_nonespresso 1
            }
        }
    }
    # A shot is starting, so the file those values came from is no longer the
    # last shot. Drop them (0.24.1 yield, 0.25.0 grind and dose): the live
    # settings are precisely what this shot is about to record, and quoting
    # the previous shot's numbers as this one's would be worse than either
    # showing the live values or, for a yield that never arrives, "--".
    array unset last_shot_rec
    array set last_shot_rec {}
}

# Runs after every flow completes (0.43.0), registered through the core's
# own ::de1::event::listener::after_flow_complete_add at skin load.
#
# Ordering is what makes this safe: the listener lists run first-in
# first-out (event.tcl _generic, `after idle` per callback in registration
# order), the core registers its history save in vars.tcl before the skin
# is sourced (gui.tcl load_skin), so by the time this runs the cleaning
# run's file is written and ::settings(history_saved) is 1 -- exactly the
# state the loader's reload guard requires. With should_save_history off
# the flag stays 0 and the reload is refused with a log line, never
# forced.
#
# Only a flow that latch_shot_profile flagged as non-espresso triggers a
# reload; a real shot leaves the live vectors alone (they ARE the last
# shot) and, since 0.57.5, reads its LAST SHOT record back from the saved
# file -- once per espresso-page flow, so a later steam or flush does not
# re-read it. `args` is the core's event dict, unused.
proc ::lumen::after_flow_complete { args } {
    variable last_flow_nonespresso
    variable shot_rec_pending
    set pending [expr {[info exists shot_rec_pending] && $shot_rec_pending}]
    set shot_rec_pending 0
    if { !$last_flow_nonespresso } {
        if { $pending } {
            if { [catch { record_saved_shot } err] } {
                msg -ERROR "Lumen: reading the saved shot's record failed: $err"
            }
        }
        return
    }
    set last_flow_nonespresso 0
    msg -INFO "Lumen: a non-espresso run finished; reloading the loaded bean's last real shot"
    if { [catch { load_last_shot_curves 1 } err] } {
        msg -ERROR "Lumen: reload after the non-espresso run failed: $err"
    }
}

# Stamps when a flow page was last shown. See ::lumen::data::_flow_secs: the
# core's timers keep describing the previous flow until the new one reaches
# its "during" phase, and this is how the accessor tells the two apart.
#
# `args` because dui hands a show action the page names it is switching
# between.
proc ::lumen::latch_flow_open { page args } {
    variable flow_opened
    set flow_opened($page) [clock milliseconds]
}

proc ::lumen::restyle_core_dialog { page } {
    variable C
    if { [catch { set can [dui canvas] } ] } { return }
    if { [catch { set ids [$can find withtag $page] } ] } { return }
    if { [llength $ids] == 0 } { return }

    set shapes 0 ; set texts 0
    foreach id $ids {
        if { [catch { set type [$can type $id] }] } { continue }
        switch -exact -- $type {
            polygon {
                catch { $can itemconfigure $id -fill $C(glass) -outline $C(glass_brd) }
                incr shapes
            }
            rectangle {
                catch { $can itemconfigure $id -fill $C(glass) -outline $C(glass_brd) }
                incr shapes
            }
            text {
                catch { $can itemconfigure $id -fill $C(ink_2) }
                incr texts
            }
        }
    }
    msg -INFO "Lumen: restyled core dialog $page ($shapes shapes, $texts texts)"
}

proc ::lumen::chart_setup { widget } {
    variable C
    variable L

    set sm [chart_smoothing]
    # Line widths are physical pixels here: the graph is a Tk widget, not a
    # canvas item, so it never goes through the coordinate rescale.
    set lw  [expr {int(max(1, round(3 * $L(font_scale))))}]
    set lw2 [expr {int(max(1, round(2 * $L(font_scale))))}]

    foreach {name vector colour width} [list \
        l_pressure espresso_pressure                  $C(c_press)  $lw \
        l_flow     espresso_flow                      $C(c_flow)   $lw \
        l_weight   espresso_weight_chartable          $C(c_weight) $lw2 \
        l_temp     espresso_temperature_basket10th    $C(c_temp)   $lw2 ] {
        if { [catch {
            $widget element create $name -xdata espresso_elapsed -ydata $vector \
                -smooth $sm -symbol none -label "" -linewidth $width \
                -color $colour -pixels 0
        } err] } {
            msg -ERROR "Lumen: could not create chart element $name: $err"
        }
    }

    # Stage separators: espresso_state_change is 0 except at frame changes,
    # where the app appends 10000000 (gui.tcl:3487) -- clipped to the 0..10
    # axis that plots as a dashed vertical line at each transition
    # (preinfusion -> extraction -> decline...). Mechanism from Streamline
    # skin.tcl:3915; toggled via -hide, the mechanism Insight uses for its
    # optional chart lines. NOT smoothed -- a spline would bend the spikes.
    set dash [expr {int(max(2, round(8 * $L(font_scale))))}]
    if { [catch {
        $widget element create l_stages -xdata espresso_elapsed \
            -ydata espresso_state_change -symbol none -label "" \
            -linewidth $lw2 -color $C(ink_3) -pixels 0 \
            -dashes [list $dash $dash] \
            -hide [expr {[stages_shown] ? "no" : "yes"}]
    } err] } {
        msg -ERROR "Lumen: could not create the stage separators: $err"
    }

    catch { gridconfigure $widget }
    catch {
        $widget axis configure x -color $C(ink_3) -tickfont $L(font_caption) \
            -linewidth 1 -subdivisions 5 -min 0
        $widget axis configure y -color $C(ink_3) -tickfont $L(font_caption) \
            -min 0 -max 10 -subdivisions 5 -majorticks {2 4 6 8 10}
    }
}

#############################################################################
#  Actions
#
#  Each one targets a plugin that may not be installed. Failures are logged
#  to the app log, never swallowed -- a dead button that says nothing is far
#  worse to diagnose than one that leaves a line in the log.
#############################################################################

namespace eval ::lumen::act {
    # Per-stepper tap-rate state: key -> {last_ms streak dir}.
    variable accel
    array set accel {}
}

# Tap-rate acceleration for the grind / dose / yield steppers (owner
# request): a slow tap moves 0.1; taps in RAPID succession escalate to 0.5
# after three and 1.0 after six, so a big adjustment does not take forty
# taps. A pause or a direction change drops straight back to 0.1. The app's
# legacy buttons fire once per press (there is no hold event), so holding
# registers as its taps do.
#
# The window is 350ms (0.28.1). It shipped at 700ms, and the owner's
# careful step-step-step pace -- roughly 500-700ms per tap -- landed
# inside it, so deliberate 0.1 nudges escalated to 0.5 mid-adjustment.
# Escalation is meant for drumming on the button (3+ taps a second, i.e.
# under ~350ms apart); a measured pace must stay at 0.1 no matter how many
# taps it runs to.
proc ::lumen::act::_accel_step { key dir } {
    variable accel
    set now [clock milliseconds]
    set last 0 ; set streak 0 ; set lastdir 0
    catch { lassign $accel($key) last streak lastdir }
    if { $dir == $lastdir && ($now - $last) < 350 } {
        incr streak
    } else {
        set streak 0
    }
    set accel($key) [list $now $streak $dir]
    if { $streak >= 6 } { return 1.0 }
    if { $streak >= 3 } { return 0.5 }
    return 0.1
}

proc ::lumen::act::grind_popup {} {
    if { [catch { ::plugins::GrindAdvisor::show_last_recommendation } err] } {
        msg -ERROR "Lumen: could not open the Grind Advisor result: $err"
    }
}

# GrindAdvisor >= 3.3.0 exposes show_calibration_curve for exactly this: it
# opens the Calibration Curve straight from a skin tile, without the after-shot
# popup having to be on screen first. Its Back button lands on the normal
# popup. On an older GrindAdvisor the proc is absent, so fall back to the
# result popup rather than leaving a dead button.
proc ::lumen::act::grind_curve {} {
    if { [info procs ::plugins::GrindAdvisor::show_calibration_curve] eq "" } {
        msg -NOTICE "Lumen: GrindAdvisor has no calibration curve, opening the result popup instead"
        grind_popup
        return
    }
    if { [catch { ::plugins::GrindAdvisor::show_calibration_curve } err] } {
        msg -ERROR "Lumen: could not open the calibration curve: $err"
    }
}

proc ::lumen::act::dye_next {} {
    if { [catch { ::plugins::DYE::open -which_shot next } err] } {
        msg -ERROR "Lumen: could not open DYE next shot: $err"
    }
}

# Straight to the camera, one tap.
#
# BeanScanner records its return page only in BeanScanner_settings::show, and
# ::plugins::BeanScanner::_settings_return_page is never initialised at
# namespace level. Jumping directly to a sub-page therefore left that
# variable unset, and _exit_settings reads it WITHOUT a catch:
#
#     proc _exit_settings {} {
#         variable _settings_return_page
#         _navigate_done $_settings_return_page
#     }
#
# so Done threw "no such variable" and silently did nothing -- the dead end.
#
# Seeding the variable with the page we came from is exactly what entering
# through the settings page would have done, so the plugin's own navigation
# then works unmodified. Guarded and logged: if BeanScanner ever renames it,
# this must fail loudly rather than trap the user again.
# Theme switch. 0.46.0-0.53.1 the THEME button cycled Dark -> Light ->
# Custom through this; 0.54.0 removed that cycle (owner: Lumen dark and
# Lumen light are presets in the picker, so the button now just opens
# it) and the picker's Done is the one caller. Applies the new theme on
# the spot (0.47.0) -- the page you are on redraws in it. Custom uses the
# colours last saved by the picker (Lumen-dark defaults if none); the
# first time a set of colours is chosen its five backgrounds are drawn
# on the tablet (a few seconds), after that the files are reused. A
# failed apply keeps the current theme and says so in the row's caption.
#
# Persists lumen_theme and applies it live; on failure the preference is
# put back so the next launch matches what is on screen. Returns 1 when
# the new theme is on screen.
proc ::lumen::act::_switch_theme { new } {
    set old $::lumen::theme_mode
    if { [catch {
        set ::settings(lumen_theme) $new
        save_settings
    } err] } {
        msg -ERROR "Lumen: could not save the theme preference: $err"
        return 0
    }
    # 0.50.0: the wait pill covers the whole synchronous apply.
    ::lumen::wait_show "[translate {Applying}] [::lumen::_theme_word $new] [translate {theme...}]"
    set applied [::lumen::apply_theme $new]
    ::lumen::wait_hide
    if { $applied } { return 1 }
    if { [catch {
        set ::settings(lumen_theme) $old
        save_settings
    } err] } {
        msg -ERROR "Lumen: could not restore the theme preference: $err"
    }
    return 0
}

# 0.56.0: the schedule's times on the picker are PENDING like every other
# picker choice -- +30 minutes a tap, wrapping at midnight, saved by Done,
# dropped by Cancel. (The Auto pill itself is theme_pick base auto.)
proc ::lumen::act::auto_step { which } {
    variable ::lumen::custom::pend
    set k [expr {$which eq "light" ? "lf" : "df"}]
    set pend($k) [expr {([::lumen::pend_minutes $which] + 30) % 1440}]
    ::lumen::refresh_preview
}

proc ::lumen::act::open_settings {} {
    if { [catch { dui page load lumen_settings } err] } {
        msg -ERROR "Lumen: could not open Lumen settings: $err"
    }
}

# 0.34.0 clock format toggles (CLOCK row). Same persist-or-log contract
# as the theme toggle above; the taskbar picks the change up on its next
# 200ms tick -- no restart, unlike the theme.
proc ::lumen::act::toggle_time_format {} {
    set new [expr {[::lumen::time_format] == 24 ? "12" : "24"}]
    if { [catch {
        set ::settings(lumen_time_format) $new
        save_settings
    } err] } {
        msg -ERROR "Lumen: could not save the time format: $err"
    }
}

proc ::lumen::act::toggle_date_format {} {
    set new [expr {[::lumen::date_format] eq "dmy" ? "mdy" : "dmy"}]
    if { [catch {
        set ::settings(lumen_date_format) $new
        save_settings
    } err] } {
        msg -ERROR "Lumen: could not save the date format: $err"
    }
}

# 0.53.0 favorite profile slots.
#
# Mechanisms copied from DrinkMenu v1.16.0's To-machine tap (tablet-
# verified), not invented: the busy guard (connected and not Idle/Sleep/
# GoingToSleep refuses the tap; fails closed), ::select_profile <filename>
# (core vars.tcl:2932 -- it loads the file into ::settings, marks the
# profile unchanged and queues the DE1 send itself), then the same 1 s
# debounced `save_settings; save_settings_to_de1`. Nothing here starts a
# flow: the GHC does, as everywhere else in this skin.
proc ::lumen::machine_busy {} {
    set handle unknown
    catch { set handle $::de1(device_handle) }
    if { $handle eq "0" } { return "" }
    set name unknown
    catch { set name $::de1_num_state($::de1(state)) }
    if { $name in {Idle Sleep GoingToSleep} } { return "" }
    return $name
}

namespace eval ::lumen::act { variable fav_send_id "" }

proc ::lumen::act::fav_tap { n } {
    variable fav_send_id
    set slot [::lumen::fav_slot $n]
    if { $slot eq "" } {
        # Empty: remember the profile loaded right now.
        set fn [string trim [::lumen::data::_s ::settings(profile_filename)]]
        if { $fn eq "" } {
            msg -NOTICE "Lumen: no profile is loaded, favorite $n left empty"
            return
        }
        set title $fn
        catch {
            set t [string trim $::settings(profile_title)]
            if { $t ne "" } { set title $t }
        }
        if { [catch {
            set d [::lumen::fav_slots]
            dict set d $n [list [string range $fn 0 127] [string range $title 0 79]]
            set ::settings(lumen_fav_profiles) $d
            save_settings
        } err] } {
            msg -ERROR "Lumen: could not save favorite $n: $err"
            return
        }
        msg -NOTICE "Lumen: favorite $n set to '$fn'"
        # 0.57.3: the slot's name and halo appear on the tap, not a tick later.
        ::lumen::_fav_refresh_now
        return
    }
    lassign $slot fn title
    set busy [::lumen::machine_busy]
    if { $busy ne "" } {
        msg -NOTICE "Lumen: machine busy ($busy), favorite $n not loaded"
        return
    }
    # 0.57.3: the halo moves to this slot and is PAINTED before the
    # profile loads, so the tap answers at once; the refresh after the
    # load brings the name inks along -- or, if the load failed, puts the
    # halo back on whatever profile is really loaded.
    ::lumen::_fav_light_now $n
    set r ""
    if { [catch { set r [::select_profile $fn] } err] } {
        msg -ERROR "Lumen: select_profile '$fn' failed: $err"
        ::lumen::_fav_refresh_now
        return
    }
    ::lumen::_fav_refresh_now
    if { $r eq "-1" } {
        msg -ERROR "Lumen: favorite $n profile file '$fn' is missing"
        return
    }
    catch { after cancel $fav_send_id }
    set fav_send_id [after 1000 {
        if { [catch {
            save_settings
            save_settings_to_de1
        } err] } {
            msg -ERROR "Lumen: could not send the machine settings: $err"
        }
    }]
    msg -NOTICE "Lumen: favorite $n loaded profile '$fn'"
}

proc ::lumen::act::clear_favorites {} {
    if { [dict size [::lumen::fav_slots]] == 0 } { return }
    if { [catch {
        unset -nocomplain ::settings(lumen_fav_profiles)
        save_settings
    } err] } {
        msg -ERROR "Lumen: could not clear the favorite profiles: $err"
        return
    }
    msg -NOTICE "Lumen: favorite profiles cleared"
}

# 0.47.0: Done is a plain page switch again. Until 0.46.1 a changed theme
# made it quit the app (the palette was read once at load and every item
# was created from it; the app cannot relaunch itself on Android 16, so
# the owner reopened it by hand). ::lumen::apply_theme now recolours in
# place, so nothing is pending when Done is tapped.
proc ::lumen::act::close_settings {} {
    if { [catch { dui page load off } err] } {
        msg -ERROR "Lumen: could not return to the home page: $err"
    }
}

proc ::lumen::act::open_app_settings {} {
    if { [catch { show_settings } err] } {
        msg -ERROR "Lumen: could not open the app settings: $err"
    }
}

# Profile chooser, straight from the home page (0.24.0, owner request).
#
# settings_1 is the stock profile page -- the profiles listbox, the explanation
# chart and the brew-temperature control (skins/default/de1_skin_settings.tcl:
# 192, 934, 1026). show_settings takes the tab to open as its first argument
# and does the rest itself, including sizing the profile scrollbar on idle
# (gui.tcl:1403-1425). This is Streamline's own home-page shortcut
# (Streamline/skin.tcl:607) minus its zoomed-page bookkeeping: no custom
# navigation of our own, so Done comes back the same way it does from the
# DECENT APP button, which is tablet-proven.
proc ::lumen::act::open_profiles {} {
    if { [catch { show_settings settings_1 } err] } {
        msg -ERROR "Lumen: could not open the profile list: $err"
    }
}


# Writes ::settings(grinder_dose_weight) -- the same field shot.tcl records
# as the shot's dose. Refuses to store a zero or negative reading, so a
# mis-tap with nothing on the scale cannot wipe your dose.
proc ::lumen::act::set_dose_from_scale {} {
    set w ""
    catch { set w $::de1(scale_weight) }
    if { ![::lumen::data::_is_pos $w] } {
        msg -NOTICE "Lumen: no positive scale weight, dose left unchanged"
        return
    }
    if { [catch {
        set ::settings(grinder_dose_weight) [format %.1f $w]
        save_settings
    } err] } {
        msg -ERROR "Lumen: could not set the dose from the scale: $err"
    }
}

# ---- next-shot steppers ---------------------------------------------------
#
# Mechanisms copied from the proven implementations, not invented here:
#   grind  -- DYE's own setup_DSx2.tcl change_grinder_setting: stage the
#             value in DYE's next_grinder_setting AND mirror it into
#             ::settings(grinder_setting), saving both.
#   yield  -- DSx2 procs_vars.tcl "saw" stepper: settings_2c profiles keep
#             their target in final_desired_shot_weight_advanced, everything
#             else in final_desired_shot_weight.
#   ratio  -- DSx2 procs_vars.tcl "er" stepper: a ratio change is just a
#             yield write of dose * new_ratio.
# Every path clamps, so holding the button cannot write junk.

proc ::lumen::act::adjust_grind { delta } {
    # Read the same source the strip displays (DYE's staged value first).
    set cur [::lumen::data::_field grinder_setting]
    if { ![string is double -strict $cur] } { set cur 0 }
    set dir [expr {$delta >= 0 ? 1 : -1}]
    set new [expr {double($cur) + $dir * [_accel_step grind $dir]}]
    if { $new < 0 } { set new 0 } elseif { $new > 100 } { set new 100 }
    set new [format %.1f $new]
    if { [catch {
        if { [info exists ::plugins::DYE::settings(next_grinder_setting)] } {
            set ::plugins::DYE::settings(next_grinder_setting) $new
            plugins save_settings DYE
        }
        set ::settings(grinder_setting) $new
        save_settings
    } err] } {
        msg -ERROR "Lumen: could not change the grind setting: $err"
        return
    }
    # DYE keeps a human-readable summary of the next shot; refresh it the way
    # its own stepper does. Absent or old DYE: nothing to refresh.
    catch { ::plugins::DYE::shots::define_next_desc }
}

# ---- machine steppers (Lumen settings page) -------------------------------
#
# Mechanism from Streamline's settings column: mutate the setting, then
# persist AND send to the machine, debounced by 1s so a run of taps lands
# as one save + one BLE update (save_profile_and_update_de1_soon's pattern).
# save_settings_to_de1 re-sends the shot frames plus the steam / hot-water /
# flush settings (de1_comms.tcl:1539), so it covers all four rows.

proc ::lumen::act::_apply_machine_settings {} {
    catch { after cancel $::lumen::machine_apply_id }
    set ::lumen::machine_apply_id [after 1000 {
        if { [catch {
            save_settings
            save_settings_to_de1
        } err] } {
            msg -ERROR "Lumen: could not send the machine settings: $err"
        }
    }]
}

# Brew temperature must go through the core's change_espresso_temperature:
# it applies the RELATIVE change to every frame of step-temperature and
# advanced profiles, not just the headline number (vars.tcl:4213).
proc ::lumen::act::adjust_brew_temp { delta } {
    set cur [::lumen::data::_s ::settings(espresso_temperature)]
    if { ![string is double -strict $cur] } { return }
    set new [expr {double($cur) + $delta}]
    # Streamline's guard rails: never below 1 or above 110.
    if { $new < 70.0 || $new > 110.0 } { return }
    if { [catch { change_espresso_temperature $delta } err] } {
        msg -ERROR "Lumen: could not change the brew temperature: $err"
        return
    }
    _apply_machine_settings
}

proc ::lumen::act::adjust_steam_time { delta } {
    set cur [::lumen::data::_s ::settings(steam_timeout)]
    if { ![string is double -strict $cur] } { set cur 0 }
    set new [expr {round(double($cur) + $delta)}]
    if { $new < 0 } { set new 0 } elseif { $new > 255 } { set new 255 }
    if { [catch {
        set ::settings(steam_timeout) $new
        # Timeout 0 means steam off; keep the flag in step the way
        # Streamline's save path does.
        set ::settings(steam_disabled) [expr {$new == 0 ? 1 : 0}]
    } err] } {
        msg -ERROR "Lumen: could not change the steam time: $err"
        return
    }
    _apply_machine_settings
}

proc ::lumen::act::adjust_flush_time { delta } {
    set cur [::lumen::data::_s ::settings(flush_seconds)]
    if { ![string is double -strict $cur] } { set cur 5 }
    set new [expr {round(double($cur) + $delta)}]
    # Streamline's bounds: 3..254.
    if { $new < 3 } { set new 3 } elseif { $new > 254 } { set new 254 }
    if { [catch { set ::settings(flush_seconds) $new } err] } {
        msg -ERROR "Lumen: could not change the flush time: $err"
        return
    }
    _apply_machine_settings
}

# steam_flow is ml/s x 100. Step and bounds copied from Streamline's own
# steam stepper (skin.tcl:2707-2716): 10 per tap, and it refuses to go past
# 250. The floor is 40 rather than Streamline's 0, because 0.4 mL/s is the
# minimum its own data-entry dialog for this field declares (skin.tcl:1913)
# and a tenth of a mL/s is not a steam setting anyone wants to reach by
# holding a button.
proc ::lumen::act::adjust_steam_flow { delta } {
    set cur [::lumen::data::_s ::settings(steam_flow)]
    if { ![string is double -strict $cur] } { set cur 0 }
    set new [expr {round(double($cur) + $delta)}]
    if { $new < 40 } { set new 40 } elseif { $new > 250 } { set new 250 }
    if { [catch { set ::settings(steam_flow) $new } err] } {
        msg -ERROR "Lumen: could not change the steam flow: $err"
        return
    }
    _apply_machine_settings
}

# Hot water temperature, in degrees C. Streamline steps this by 1 and holds it
# between 1 and 100 (skin.tcl:2657-2668); the floor here is 20, for the same
# reason as the steam floor -- nothing below it is a hot water setting, and a
# runaway tap should stop somewhere sensible.
proc ::lumen::act::adjust_water_temp { delta } {
    set cur [::lumen::data::_s ::settings(water_temperature)]
    if { ![string is double -strict $cur] } { set cur 0 }
    set new [expr {round(double($cur) + $delta)}]
    if { $new < 20 } { set new 20 } elseif { $new > 100 } { set new 100 }
    if { [catch { set ::settings(water_temperature) $new } err] } {
        msg -ERROR "Lumen: could not change the hot water temperature: $err"
        return
    }
    _apply_machine_settings
}

# The STEAM and HOT WATER pills drive whichever half of their row is selected,
# so the buttons are wired to a direction (-1 / +1) and the step belongs to
# the setting, not to the button (0.26.0).
proc ::lumen::act::adjust_steam { dir } {
    if { [::lumen::steam_mode] eq "flow" } {
        adjust_steam_flow [expr {$dir * 10}]
    } else {
        adjust_steam_time [expr {$dir * 5}]
    }
}

proc ::lumen::act::adjust_water { dir } {
    if { [::lumen::water_mode] eq "vol" } {
        adjust_water_volume [expr {$dir * 10}]
    } else {
        adjust_water_temp $dir
    }
}

proc ::lumen::act::toggle_steam_mode {} {
    set new [expr {[::lumen::steam_mode] eq "flow" ? "time" : "flow"}]
    if { [catch {
        set ::settings(lumen_steam_mode) $new
        save_settings
    } err] } {
        msg -ERROR "Lumen: could not save the steam row mode: $err"
    }
}

proc ::lumen::act::toggle_water_mode {} {
    set new [expr {[::lumen::water_mode] eq "vol" ? "temp" : "vol"}]
    if { [catch {
        set ::settings(lumen_water_mode) $new
        save_settings
    } err] } {
        msg -ERROR "Lumen: could not save the hot water row mode: $err"
    }
}

proc ::lumen::act::adjust_water_volume { delta } {
    set cur [::lumen::data::_s ::settings(water_volume)]
    if { ![string is double -strict $cur] } { set cur 0 }
    set new [expr {round(double($cur) + $delta)}]
    if { $new < 10 } { set new 10 } elseif { $new > 250 } { set new 250 }
    if { [catch { set ::settings(water_volume) $new } err] } {
        msg -ERROR "Lumen: could not change the hot water volume: $err"
        return
    }
    _apply_machine_settings
}

# Bag cycler depth. A Lumen preference, NOT a machine setting, so it saves
# with plain save_settings and never goes near save_settings_to_de1 -- the
# machine has no idea what a bean bag is.
proc ::lumen::act::adjust_bag_count { delta } {
    set new [expr {[::lumen::bag_count] + $delta}]
    if { $new < 3 }  { set new 3 } elseif { $new > 10 } { set new 10 }
    if { [catch {
        set ::settings(lumen_bag_count) $new
        save_settings
    } err] } {
        msg -ERROR "Lumen: could not save the bag count preference: $err"
    }
}

# Low-water threshold (0.45.0). A Lumen preference like the bag count:
# plain save_settings, never save_settings_to_de1. 50 ml per tap.
proc ::lumen::act::adjust_water_low { delta } {
    set new [expr {[::lumen::water_low_ml] + $delta}]
    if { $new < 100 } { set new 100 } elseif { $new > 800 } { set new 800 }
    if { [catch {
        set ::settings(lumen_water_low_ml) $new
        save_settings
    } err] } {
        msg -ERROR "Lumen: could not save the low-water threshold: $err"
    }
}

proc ::lumen::act::adjust_dose { delta } {
    set cur [::lumen::data::_s ::settings(grinder_dose_weight)]
    if { ![string is double -strict $cur] } { set cur 0 }
    set dir [expr {$delta >= 0 ? 1 : -1}]
    set new [expr {double($cur) + $dir * [_accel_step dose $dir]}]
    # DSx2's dose stepper clamps 2..40; a dose outside that is a mis-tap.
    if { $new < 2 } { set new 2 } elseif { $new > 40 } { set new 40 }
    set new [format %.1f $new]
    if { [catch {
        if { [info exists ::plugins::DYE::settings(next_grinder_dose_weight)] } {
            set ::plugins::DYE::settings(next_grinder_dose_weight) $new
            plugins save_settings DYE
        }
        set ::settings(grinder_dose_weight) $new
        save_settings
    } err] } {
        msg -ERROR "Lumen: could not change the dose: $err"
        return
    }
    catch { ::plugins::DYE::shots::define_next_desc }
}

proc ::lumen::act::_write_yield { new } {
    if { ![string is double -strict $new] } { return }
    if { $new < 0 } { set new 0 } elseif { $new > 200 } { set new 200 }
    set new [format %.1f $new]
    if { [catch {
        if { [string trim [::lumen::data::_s ::settings(settings_profile_type)]] eq "settings_2c" } {
            set ::settings(final_desired_shot_weight_advanced) $new
        } else {
            set ::settings(final_desired_shot_weight) $new
        }
        save_settings
    } err] } {
        msg -ERROR "Lumen: could not change the target yield: $err"
    }
}

proc ::lumen::act::adjust_yield { delta } {
    set cur [::lumen::data::_target_raw]
    if { ![string is double -strict $cur] } { set cur 0 }
    set dir [expr {$delta >= 0 ? 1 : -1}]
    _write_yield [expr {double($cur) + $dir * [_accel_step yield $dir]}]
}

# 0.21.0 removed ::lumen::act::adjust_ratio. The RATIO stepper gave up its
# slot to the PROFILE tile, and ratio is now shown as a derived caption under
# the YIELD value. It was never an independent quantity -- it only ever wrote
# final_desired_shot_weight, exactly like the yield stepper does -- so nothing
# is lost: stepping yield moves the ratio and vice versa.

# Kick a scale reconnect by hand.
#
# The core gives up permanently once its automatic retries are spent: on each
# disconnect scale_disconnect_handler (de1app-core/de1_comms.tcl:587) calls
# ble_connect_to_scale up to scale_max_connection_retry_attempts (20) times,
# ~10s apart. After the 20th it only schedules
#   after 300000 "set ::de1(bluetooth_scale_connection_attempts_tried) 0"
# -- it resets the counter and never retries. So a scale switched on more than
# ~3.5 minutes after it went away is never reconnected on its own. Every other
# skin covers this with a tap target (Insight skin.tcl:904, DSx2, DSx,
# Streamline skin.tcl:696, SWDark4); Lumen had none, which is why the readout
# looked random. Copied verbatim from Insight -- the counter must be cleared
# first, or the 20 already-spent attempts stay spent.
proc ::lumen::act::reconnect_scale {} {
    if { [::lumen::data::_s ::settings(scale_bluetooth_address)] eq "" } {
        msg -NOTICE "Lumen: no scale paired, nothing to reconnect"
        return
    }
    if { [catch {
        set ::de1(bluetooth_scale_connection_attempts_tried) 0
        ble_connect_to_scale
    } err] } {
        msg -ERROR "Lumen: could not reconnect the scale: $err"
    }
}

# Opens the Shot History Editor's card list -- the shortcut for editing and
# soft-deleting past shots. open_page is the plugin's public entry, and its
# settings page captures the page it was opened from by itself, so Done
# returns straight back here with no bookkeeping on our side.
proc ::lumen::act::shot_history {} {
    if { [catch {
        if { [info procs ::plugins::ShotHistoryEditor::open_page] eq "" } {
            error "the Shot History Editor plugin is not loaded"
        }
        ::plugins::ShotHistoryEditor::open_page ShotHistoryEditor_settings
    } err] } {
        msg -ERROR "Lumen: could not open the Shot History Editor: $err"
    }
}

# Opens Grind Advisor's settings. open_settings_dialog is its public entry
# (it tries open_dialog, then load, then show, and logs if all three fail),
# and its page's show{} captures the page it was opened from as its own return
# target (GrindAdvisor v1.8.8), so Done comes straight back here. Same
# contract as the Shot History shortcut above -- no bookkeeping on our side.
proc ::lumen::act::open_grind_advisor {} {
    if { [catch {
        if { [info procs ::plugins::GrindAdvisor::open_settings_dialog] eq "" } {
            error "the Grind Advisor plugin is not loaded"
        }
        ::plugins::GrindAdvisor::open_settings_dialog GrindAdvisor_settings
    } err] } {
        msg -ERROR "Lumen: could not open Grind Advisor: $err"
    }
}

# Opens the Maintenance Tracker's card list from the taskbar wrench
# (0.32.0). Same contract as the two shortcuts above: open_page is the
# plugin's public entry, its settings page captures the page it was opened
# from by itself (the home page is "off", which its transient-name filter
# accepts), so Done returns straight here with no bookkeeping on our side.
proc ::lumen::act::open_maintenance {} {
    if { [catch {
        if { [info procs ::plugins::MaintenanceTracker::open_page] eq "" } {
            error "the Maintenance Tracker plugin is not loaded"
        }
        ::plugins::MaintenanceTracker::open_page MaintenanceTracker_settings
    } err] } {
        msg -ERROR "Lumen: could not open the Maintenance Tracker: $err"
    }
}

# Opens the Drink Menu's grid from the taskbar mug (0.40.0). Same
# contract as the three shortcuts above: open_page is the plugin's
# public entry (the MaintenanceTracker cascade, copied verbatim into
# DrinkMenu v0.1.0), its menu page captures the page it was opened from
# by itself ("off" passes its transient-name filter), so Done returns
# straight here with no bookkeeping on our side. Absent or disabled
# plugin: the tap logs the error and does nothing else.
proc ::lumen::act::open_drinkmenu {} {
    if { [catch {
        if { [info procs ::plugins::DrinkMenu::open_page] eq "" } {
            error "the Drink Menu plugin is not loaded"
        }
        ::plugins::DrinkMenu::open_page DrinkMenu_main
    } err] } {
        msg -ERROR "Lumen: could not open the Drink Menu: $err"
    }
}

# Cycles the next shot's bean bag through the most recent bags.
#
# Read and write both go through OTHER PLUGINS' public APIs. Lumen opens no
# database and writes no SQL -- that is a standing property of this skin and
# this feature does not change it:
#
#   list   ::plugins::SDB::available_categories bean_desc 1 {} 0
#          The trailing 0 is use_lookup_table and it matters three times over:
#          it selects the branch that orders by MAX(shot.clock) DESC (most
#          recently used bag first, which is the whole point), it is the only
#          branch that applies the removed=0 filter, and it avoids the
#          lookup-table branch, which reads an undefined `lookup_order_by`
#          (SDB.tcl:2723 -- its assignment is commented out at 2657).
#   clock  ::plugins::SDB::shots_using_category bean_desc <value> clock
#          Newest first, so [lindex ... 0] is that bag's most recent shot.
#   apply  ::plugins::DYE::shots::source_next_from <clock> {} beans
#          "beans" is resolved by DYE through
#          `metadata fields -domain shot -section beans`, so it copies the
#          whole bean section (brand, type, roast date, level, notes) and
#          persists it into the next shot the same way Bean Scanner does.
#
# Every call is guarded: with SDB or DYE missing this logs and does nothing
# rather than throwing inside a button handler.
# The shot clocks for one bag, newest first.
#
# WORKAROUND for a real defect in SDB, hit on the tablet in 0.21.0: for
# bean_desc the data dictionary gives db_table = V_shot rather than "shot", so
# shots_using_category takes its aliased branch and builds
#
#   SELECT DISTINCT clock FROM V_shot t INNER JOIN V_shot s ON t.clock=s.clock
#
# where the bare `clock` is ambiguous across both aliases. SQLite rejects it
# with "ambiguous column name: clock" and the cycler could never resolve a
# clock. Qualifying it as t.clock through the documented `return_what`
# parameter produces valid SQL and the ordering SDB already intends
# (ORDER BY t.clock DESC).
#
# Both spellings are tried, qualified first: t.clock is correct for the
# aliased branch that bean_desc actually takes, and the bare form is the right
# one if a future SDB maps bean_desc onto the plain `shot` table, where there
# is no `t` to qualify. Neither is assumed to work.
proc ::lumen::act::_bag_clocks { bag } {
    foreach form {t.clock clock} {
        if { ![catch {
            set c [::plugins::SDB::shots_using_category bean_desc $bag $form]
        } err] } {
            if { [llength $c] > 0 } { return $c }
        } else {
            msg -DEBUG "Lumen: bag clock lookup via '$form' failed: $err"
        }
    }
    return {}
}

# (0.43.0: _bag_last_shot_file is gone -- the cycler loads through
# ::lumen::load_last_shot_curves with the bag name, the same resolver as
# startup, so the bag's cleaning runs are skipped here too.)

proc ::lumen::act::cycle_bag { dir } {
    if { [catch {
        if { [info procs ::plugins::SDB::available_categories] eq "" } {
            error "the SDB plugin is not loaded"
        }
        if { [info procs ::plugins::DYE::shots::source_next_from] eq "" } {
            error "the DYE plugin is not loaded"
        }

        # Rebuild the window first: a shot pulled since the last refresh may
        # have added a bag, and this is a tap, so it can afford the query.
        # The page indicator reads the same cached list.
        ::lumen::refresh_bag_list
        set bags $::lumen::bag_list
        if { [llength $bags] == 0 } {
            msg -NOTICE "Lumen: no bean bags in the shot database yet"
            return
        }

        set cur [::lumen::current_bag]
        set idx [lsearch -exact $bags $cur]

        # Not in the list (a hand-typed bag, or one older than the window):
        # step onto the most recent bag rather than doing nothing.
        if { $idx < 0 } {
            set target 0
        } else {
            # 0.27.0: the ends are ENDS. Wrapping made every bag look alike --
            # you could not tell the newest from the oldest, which is exactly
            # what the owner wanted the indicator to show. Running off either
            # end now does nothing, and the dots say why.
            set target [expr {$idx + $dir}]
            if { $target < 0 || $target >= [llength $bags] } {
                msg -INFO "Lumen: already at the [expr {$dir < 0 ? {newest} : {oldest}}] bag"
                return
            }
        }
        set want [lindex $bags $target]
        if { $want eq $cur } { return }

        set clocks [_bag_clocks $want]
        if { [llength $clocks] == 0 } {
            error "no shots found for bag '$want'"
        }
        ::plugins::DYE::shots::source_next_from [lindex $clocks 0] {} beans
        msg -INFO "Lumen: next shot bag set to '$want'"

        # 0.30.0 (owner request): the chart and LAST SHOT card follow the
        # bag, like the grind tile has since 0.22.0. 0.43.0: through the
        # shared resolver, so the bag's last REAL shot is what loads (a
        # cleaning run recorded under this bag is skipped). Failure here
        # must not undo the cycle itself, which has already succeeded.
        if { [catch { ::lumen::load_last_shot_curves 1 "" $want } lerr] } {
            msg -ERROR "Lumen: could not load '$want' last shot: $lerr"
        }
    } err] } {
        msg -ERROR "Lumen: could not cycle the bean bag: $err"
    }
}

proc ::lumen::act::scan_bag {} {
    if { [catch {
        # BeanScanner >= 0.3.0 exposes set_return_page for exactly this: it
        # records where we came from AND marks that we entered at a sub-page,
        # so Cancel comes straight back here instead of via its settings
        # page. Falls back to seeding the variable directly on older builds.
        if { [info procs ::plugins::BeanScanner::set_return_page] ne "" } {
            ::plugins::BeanScanner::set_return_page "off"
        } else {
            set ::plugins::BeanScanner::_settings_return_page "off"
        }
        ::plugins::BeanScanner::open_page BeanScanner_capture
    } err] } {
        msg -ERROR "Lumen: could not open Bean Scanner camera: $err"
    }
}

proc ::lumen::txt { page x y text args } {
    variable C
    variable L
    array set o [list -font $L(font_body) -fill $C(ink) -anchor nw -justify left -width 0 -tags ""]
    array set o $args

    set extra {}
    if { $o(-width) > 0 } { lappend extra -width [X $o(-width)] }

    uplevel #0 [list dui add dtext $page [X $x] [Y $y] -text $text \
        -font $o(-font) -fill $o(-fill) -anchor $o(-anchor) \
        -justify $o(-justify) -tags [_tags $o(-fill) "" $o(-tags)] {*}$extra]
}

# Like txt, but the text is a Tcl snippet re-evaluated on the app's update
# tick. Goes through `dui add variable` rather than the legacy
# add_de1_variable, whose argument order depends on -textvariable being the
# very last option.
proc ::lumen::var { page x y code args } {
    variable C
    variable L
    array set o [list -font $L(font_body) -fill $C(ink) -anchor nw -justify left -width 0]
    array set o $args

    set extra {}
    if { $o(-width) > 0 } { lappend extra -width [X $o(-width)] }

    uplevel #0 [list dui add variable $page [X $x] [Y $y] -textvariable $code \
        -font $o(-font) -fill $o(-fill) -anchor $o(-anchor) \
        -justify $o(-justify) -tags [_tags $o(-fill) ""] {*}$extra]
}

# Invisible tap target. Coordinates in DESIGN px.
# Visual press feedback (0.29.0, owner request: buttons felt "flat and
# dead"). The controls are pixels baked into the background image with an
# invisible zone on top, so nothing reacts natively; this draws a brief
# crema glow in the zone's own rounded shape the moment it is tapped.
#
# Mechanics, and why each choice:
#  * Drawn straight on .can, NOT through dui add canvas_item -- a press
#    flash is transient, not page state; dui would keep it in the page's
#    item list forever.
#  * Coordinates arrive VIRTUAL (2560x1600, what add_de1_button was given)
#    and are mapped to screen pixels with the core's rescale_x/y_skin --
#    the same transform the button zone itself went through, so the glow
#    lands exactly on the control.
#  * Tk canvas has no alpha, and faking it was a mistake: 0.29.0 shipped
#    -stipple gray25, a raw 4x4 checkerboard that the owner read as "a
#    graphics bug" -- on a high-DPI panel a pixel mesh over the button
#    looks like corruption, not translucency. 0.29.1 drew a hollow accent
#    RING instead, which looked right on baked pills but drew a floating
#    empty rectangle around TEXT-LINK controls (Shot history, Curve...) --
#    owner report, 0.36.0. Now the flash is a FILLED crema-tinted chip
#    with a thin crema border, and it is LOWERED beneath the control's
#    own label: a chip materialises behind the text like a real pressed
#    button, on pills and text links alike.
#  * The lowering trick: canvas items stack in creation order, so the
#    fresh flash lands on top of the label it must sit under. The zone's
#    overlapping items (bottom -> top) start at the baked background;
#    the flash is lowered to just below the LOWEST visible text item in
#    the zone -- above the baked background and pills, below every
#    label. If no visible text overlaps (never in practice -- every
#    control's face is a text or glyph item), it stays on top, which
#    only costs covering nothing.
#  * `update idletasks` before returning, or the command that follows
#    (which may open a page or query a plugin) would run to completion
#    before the canvas ever painted the flash -- feedback after the fact
#    is no feedback.
#  * One shared tag: a new press deletes the previous glow first, so
#    drumming on a stepper reads as one live glow, not a stack of stale
#    ones. The 150ms timer clears it by item id; a flash that outlives an
#    instant page switch dies on the same timer.
# Rounded-rect point list for the flash polygons, shared by all styles.
proc ::lumen::_flash_pts { px1 py1 px2 py2 r } {
    if { $r * 2 > ($px2 - $px1) } { set r [expr {($px2 - $px1) / 2}] }
    if { $r * 2 > ($py2 - $py1) } { set r [expr {($py2 - $py1) / 2}] }
    return [list \
        [expr {$px1 + $r}] $py1 \
        [expr {$px2 - $r}] $py1 \
        $px2 $py1 \
        $px2 [expr {$py1 + $r}] \
        $px2 [expr {$py2 - $r}] \
        $px2 $py2 \
        [expr {$px2 - $r}] $py2 \
        [expr {$px1 + $r}] $py2 \
        $px1 $py2 \
        $px1 [expr {$py2 - $r}] \
        $px1 [expr {$py1 + $r}] \
        $px1 $py1]
}

# 0.37.0 (owner picked "Option B" from the press-flash samples): the
# flash is a NEUTRAL chip that fits what you actually see, not the tap
# zone, in three per-zone styles declared at the tap site:
#
#   zone   (default) chip over the whole zone -- correct for every
#          control whose zone IS its drawn bounds (baked pills,
#          steppers, taskbar glyphs, Done...). Raised glass_2 fill with
#          a glass_brd hairline, lowered beneath the control's label,
#          stepped to C(glass) at 90ms -- a press, not a highlighter.
#   label  chip fitted to the control's VISIBLE text: the bboxes of the
#          visible text items inside the zone, unioned, padded 10x6
#          design px and clamped to the zone. For the text links (Shot
#          history, Curve, Shot analysis, the PROFILE row, the
#          steam/water mode line) whose padded zones are much bigger
#          than the words -- the 0.36.0 "yellow rectangle" report.
#   ring <x y w h>  crema hairline around the CONTAINER the zone is
#          part of (design px -- the grind card), for card-sized zones
#          where a filled chip would flood the tile.
#
# Still no alpha anywhere: flat palette tones, one shared tag, 150ms.
# 0.50.0: the WAIT PILL. A theme apply is one synchronous stretch of
# 1-5 s (up to ~15 s when a custom set has to be painted first), during
# which nothing on screen moves -- the owner read that as a freeze. This
# is a centred pill drawn straight on .can (transient, like the press
# flash) that names the step in progress; `update idletasks` paints it
# before the work starts and after every step change. No user events are
# processed in between, so nothing can be tapped under it, and the
# 200 ms variable tick cannot run -- which is exactly why the text is
# pushed by hand rather than bound to a variable. wait_step also
# restyles the pill from the palette in force, so it changes sides the
# moment set_palette has run.
proc ::lumen::wait_show { text } {
    variable C
    variable L
    if { [catch {
        .can delete lumen_wait
        # The tap that started this left its press flash on the button; its
        # 150 ms timer cannot fire during the apply, so clear it here or it
        # sits there in the OLD theme's fill until the end (seen on-tablet).
        .can delete lumen_tapflash
        lassign [_wait_pill_box $text] px1 py1 px2 py2
        set lw [expr {int(max(2, [rescale_y_skin 4]))}]
        .can create polygon {*}[_flash_pts $px1 $py1 $px2 $py2 [rescale_y_skin 96]] -smooth 1 \
            -fill $C(glass_2) -outline $C(crema) -width $lw -tags [list lumen_wait lumen_wait_pill]
        .can create text [rescale_x_skin [X 670]] [rescale_y_skin [Y 400]] -text $text \
            -font $L(font_primary) -fill $C(ink) -anchor center -justify center \
            -tags [list lumen_wait lumen_wait_text]
        update idletasks
    } err] } {
        msg -DEBUG "Lumen: wait pill: $err"
    }
}

# 0.51.0: the pill is sized to its text (owner report: a long step line
# ran past the card). Physical px: measured text width plus 40 design px
# each side, never narrower than 560 design px, never wider than the
# screen minus the margins; centred on (670, 400).
proc ::lumen::_wait_pill_box { text } {
    variable L
    set tw 0
    if { [catch { set tw [font measure $L(font_primary) $text] }] || ![string is double -strict $tw] } { set tw 0 }
    set pad [rescale_x_skin [X 40]]
    set w [expr {max([rescale_x_skin [X 560]], $tw + 2 * $pad)}]
    set maxw [rescale_x_skin [X 1300]]
    if { $w > $maxw } { set w $maxw }
    set cx [rescale_x_skin [X 670]]
    set py1 [rescale_y_skin [Y 352]] ; set py2 [rescale_y_skin [Y 448]]
    return [list [expr {$cx - $w / 2.0}] $py1 [expr {$cx + $w / 2.0}] $py2]
}

proc ::lumen::wait_step { text } {
    variable C
    if { [catch {
        lassign [_wait_pill_box $text] px1 py1 px2 py2
        .can coords lumen_wait_pill {*}[_flash_pts $px1 $py1 $px2 $py2 [rescale_y_skin 96]]
        .can itemconfigure lumen_wait_pill -fill $C(glass_2) -outline $C(crema)
        .can itemconfigure lumen_wait_text -text $text -fill $C(ink)
        update idletasks
    } err] } {
        msg -DEBUG "Lumen: wait pill step: $err"
    }
}

proc ::lumen::wait_hide {} {
    if { [catch { .can delete lumen_wait } err] } {
        msg -DEBUG "Lumen: wait pill hide: $err"
    }
}

# The theme's name for the pill and the log.
proc ::lumen::_theme_word { mode } {
    switch -exact -- $mode {
        light  { return [translate "Light"] }
        custom { return [translate "Custom"] }
        default { return [translate "Dark"] }
    }
}

# 0.53.1 (owner reports, three fit fixes and one more style):
#  * Virtual -> physical went through the core's rescale_x/y, which
#    TRUNCATES. The baked pills sit at exact design px, so a zone whose
#    virtual edge truncated low landed a pixel left of its pill, and the
#    inset chip read "shorter on the right" on the -, < and > pills.
#    _flash_px/_flash_py ROUND instead; the ratio is read off the core's
#    own transform, so the harness's identity stub is still identity.
#  * label: the union took EVERY text item overlapping the zone, so the
#    grind note ("Regression over 8 shots..."), whose right end pokes
#    10 px into Curve's zone, made the Curve chip card-wide. An item
#    joins the union only when at least half of it lies inside the
#    zone; when nothing qualifies, any overlap counts (the old rule).
#  * Lowering only looked for TEXT items, so a zone drawn with strokes
#    (the taskbar's DE1 icon: three hollow polygons and a line) had its
#    chip land ON TOP and the icon vanished for the 150 ms. Strokes --
#    lines, and polygons/ovals with no fill -- count as labels now.
#  * chip <x y w h>: the filled chip on a CONTAINER rect (design px) at
#    the card radius, for a zone that should light its whole card (the
#    THEME row's caption tap).
proc ::lumen::_flash_px { v } {
    set fx [expr {[rescale_x_skin 2560000] / 2560000.0}]
    return [expr {int(round($v * $fx))}]
}
proc ::lumen::_flash_py { v } {
    set fy [expr {[rescale_y_skin 1600000] / 1600000.0}]
    return [expr {int(round($v * $fy))}]
}

proc ::lumen::press_flash { x1 y1 x2 y2 {style zone} } {
    variable C
    if { [catch {
        .can delete lumen_tapflash
        set kind [lindex $style 0]
        # 0.54.2: `none` -- the tap has its own selected state (the picker's
        # colour swatches take a ring), so no chip; the previous glow is
        # still cleared. The ring and chip branches used to `return` from
        # inside this catch, which made catch report code 2 and log an
        # empty "press flash failed" line at DEBUG; branches now.
        if { $kind eq "none" } {
            # nothing to draw
        } elseif { $kind eq "ring" } {
            lassign $style - rx ry rw rh
            set px1 [_flash_px [X $rx]]
            set py1 [_flash_py [Y $ry]]
            set px2 [_flash_px [X [expr {$rx + $rw}]]]
            set py2 [_flash_py [Y [expr {$ry + $rh}]]]
            # The cards' baked corner radius is 24 design px; the smooth
            # polygon renders ~half its control-point radius, so feed
            # double (0.37.1, same correction as the chip).
            set pts [_flash_pts $px1 $py1 $px2 $py2 [rescale_y_skin 96]]
            set lw [expr {int(max(2, [rescale_y_skin 4]))}]
            set id [.can create polygon {*}$pts -smooth 1 \
                -fill "" -outline $C(crema) -width $lw \
                -tags lumen_tapflash]
            after 150 [list catch [list .can delete $id]]
            update idletasks
        } else {
            _press_chip $x1 $y1 $x2 $y2 $style
        }
    } err] } {
        msg -DEBUG "Lumen: press flash failed: $err"
    }
}

# The filled chip (zone / label / chip styles); see press_flash.
proc ::lumen::_press_chip { x1 y1 x2 y2 style } {
    variable C
    set kind [lindex $style 0]
        # chip: the container rect replaces the zone; card radius.
        set rad [rescale_y_skin 56]
        if { $kind eq "chip" } {
            lassign $style - cx cy cw ch
            set x1 [X $cx] ; set y1 [Y $cy]
            set x2 [X [expr {$cx + $cw}]] ; set y2 [Y [expr {$cy + $ch}]]
            set rad [rescale_y_skin 96]
        }

        set px1 [_flash_px $x1] ; set py1 [_flash_py $y1]
        set px2 [_flash_px $x2] ; set py2 [_flash_py $y2]

        if { $kind eq "label" } {
            # Union the visible text bboxes inside the zone: those at
            # least half inside first, else any that overlap.
            set inside {} ; set touching {}
            foreach it [.can find overlapping $px1 $py1 $px2 $py2] {
                if { [.can type $it] ne "text" } { continue }
                if { [.can itemcget $it -state] eq "hidden" } { continue }
                set bb [.can bbox $it]
                if { [llength $bb] != 4 } { continue }
                lassign $bb tx1 ty1 tx2 ty2
                set area [expr {double(max(1, ($tx2 - $tx1) * ($ty2 - $ty1)))}]
                set ox [expr {min($tx2, $px2) - max($tx1, $px1)}]
                set oy [expr {min($ty2, $py2) - max($ty1, $py1)}]
                lappend touching $bb
                if { $ox > 0 && $oy > 0 && $ox * $oy / $area >= 0.5 } {
                    lappend inside $bb
                }
            }
            if { ![llength $inside] } { set inside $touching }
            set bx1 ""
            foreach bb $inside {
                lassign $bb tx1 ty1 tx2 ty2
                if { $bx1 eq "" } {
                    set bx1 $tx1 ; set by1 $ty1 ; set bx2 $tx2 ; set by2 $ty2
                } else {
                    if { $tx1 < $bx1 } { set bx1 $tx1 }
                    if { $ty1 < $by1 } { set by1 $ty1 }
                    if { $tx2 > $bx2 } { set bx2 $tx2 }
                    if { $ty2 > $by2 } { set by2 $ty2 }
                }
            }
            if { $bx1 ne "" } {
                # Pad, then clamp back into the zone so the chip can
                # never outgrow the tap target.
                set padx [rescale_x_skin 20] ; set pady [rescale_y_skin 12]
                set px1 [expr {max($px1, $bx1 - $padx)}]
                set py1 [expr {max($py1, $by1 - $pady)}]
                set px2 [expr {min($px2, $bx2 + $padx)}]
                set py2 [expr {min($py2, $by2 + $pady)}]
            }
            # No visible text in the zone: fall through as a zone chip.
        }

        # 0.37.1 (owner report: the chip's sharper corners poked past the
        # pills' rounded edges). Two corrections: a 3-design-px inset so
        # the chip sits INSIDE the drawn control, and an over-provisioned
        # corner radius -- a -smooth 1 polygon renders roughly HALF the
        # curvature of its control-point radius, so matching the pills'
        # 16-design-px arc needs ~28 design px fed to the point list (the
        # half-size clamp in _flash_pts keeps small chips pill-ended).
        set inset [expr {int(max(2, [rescale_y_skin 6]))}]
        set px1 [expr {$px1 + $inset}] ; set py1 [expr {$py1 + $inset}]
        set px2 [expr {$px2 - $inset}] ; set py2 [expr {$py2 - $inset}]
        set pts [_flash_pts $px1 $py1 $px2 $py2 $rad]
        set lw [expr {int(max(1, [rescale_y_skin 2]))}]
        set id [.can create polygon {*}$pts -smooth 1 \
            -fill $C(glass_2) -outline $C(glass_brd) -width $lw \
            -tags lumen_tapflash]
        # Lower the filled chip beneath the control's face: the lowest
        # visible text or stroke item in the zone (canvas items stack in
        # creation order, and `find overlapping` lists bottom-up).
        foreach it [.can find overlapping $px1 $py1 $px2 $py2] {
            if { $it == $id } { continue }
            if { [.can itemcget $it -state] eq "hidden" } { continue }
            set t [.can type $it]
            if { $t eq "text" || $t eq "line" \
                    || (($t eq "polygon" || $t eq "oval") && [.can itemcget $it -fill] eq "") } {
                .can lower $id $it
                break
            }
        }
        after 90 [list catch [list .can itemconfigure $id -fill $C(glass)]]
        after 150 [list catch [list .can delete $id]]
        update idletasks
}

proc ::lumen::tap { page x y w h command label {style zone} } {
    set x1 [X $x] ; set y1 [Y $y]
    set x2 [X [expr {$x + $w}]] ; set y2 [Y [expr {$y + $h}]]
    add_de1_button $page \
        "::lumen::press_flash $x1 $y1 $x2 $y2 [list $style]; say \[translate {$label}\] \$::settings(sound_button_in); $command" \
        $x1 $y1 $x2 $y2
}

#############################################################################
#  Custom theme (0.46.0)
#
#  A third theme beside the two baked ones. The owner picks a BASE (dark or
#  light glass), a BACKDROP hue and tint strength, and an ACCENT hue and
#  saturation; everything else is derived (::lumen::custom::palette). The
#  page backgrounds cannot be baked ahead of time for arbitrary colours, so
#  they are drawn ON THE TABLET in pure Tcl (::lumen::custom::bake): the
#  gradient as a one-column photo zoomed to the page width, every panel and
#  pill as an RGBA PNG with a soft shadow (DrinkMenu v1.12.0's encoder
#  pattern), composited over it and written to lumen_<page>_custom.png in
#  the resolution folder dui already resolves. A signature file records the
#  colours they were drawn from, so a launch with unchanged colours draws
#  nothing. If drawing fails the pages fall back to -bg_color plus the
#  vector glass primitive -- a generation behind, never blank.
#
#  Preferences (all Lumen, never sent to the machine), written only by the
#  picker page's Done: lumen_custom_base dark|light, lumen_custom_bh 0..360,
#  lumen_custom_bs 0..70, lumen_custom_ah 0..360, lumen_custom_as 20..100,
#  and lumen_theme = custom. 0.47.0: applying is live (::lumen::apply_theme),
#  for this theme and the two baked ones alike.
#############################################################################

namespace eval ::lumen::custom {
    # Pending picker state (what the preview shows); committed by Done.
    variable pend
    array set pend {base dark bh 222 bs 32 ah 34 as 86}

    # The twelve hues (also the harness's contrast sweep).
    variable hues {0 30 45 60 100 150 180 200 222 250 280 320}

    # 0.51.0: a swatch is a {hue saturation display} triple -- two rows of
    # thirteen per control. Backdrop row 1: a neutral (grey; black or
    # white pages come from the base) then the hues tinted at 36, like the
    # presets; row 2: taupe then the hues rich at 62. Accent row 1: a
    # neutral (white on a dark base, black on a light one, the contrast
    # guard settles the exact tone) then the hues vivid at 85; row 2: a
    # brown then the hues muted at 45 (olive, navy, plum, rust...).
    # Built on first use by ::lumen::custom::swatches (the colour maths
    # procs are defined below this block).
    variable swatch_table ""

    # name base bh bs ah as
    variable presets {
        {Lumen dark}  dark  222 32 34  86
        {Lumen light} light 220 30 34  76
        {Espresso}    dark  25  40 40  90
        {Sea glass}   light 190 40 165 70
        {Rose}        dark  330 34 350 80
        {Graphite}    dark  222 0  200 60
    }

    # Design-px page tables, mirroring tools/make_backgrounds.py exactly:
    # panels {x y w h r kind}, inner pills the same, bloom {cx cy rx ry}.
    variable pages
    set pages [dict create]
    set _home_inner [list {492 84 150 26 13 accent} \
        {520 722 240 48 16 plain} {790 722 240 48 16 accent} {1060 722 240 48 16 accent} \
        {40 722 44 48 16 plain} {96 722 160 48 16 plain} {268 722 44 48 16 plain}]
    foreach _c {0 1 2} {
        set _x [expr {520 + $_c * 270}]
        lappend _home_inner [list $_x 642 44 48 16 plain] [list [expr {$_x + 196}] 642 44 48 16 plain]
    }
    dict set pages home [dict create out lumen_home bloom {340 168 430 260} \
        panels [list {16 64 650 190 26 accent} {682 64 642 190 26 plain} \
                     {16 270 1308 288 26 plain} {16 574 1308 210 26 plain}] \
        inner $_home_inner]
    set _set_panels {} ; set _set_inner {}
    foreach _y {110 244 378 512} {
        lappend _set_panels [list 170 $_y 460 118 26 plain] [list 670 $_y 500 118 26 plain]
        set _gy [expr {$_y + 35}]
        lappend _set_inner [list 402 $_gy 44 48 16 plain] [list 562 $_gy 44 48 16 plain]
    }
    foreach _y {244 512} {
        set _gy [expr {$_y + 35}]
        lappend _set_inner [list 942 $_gy 44 48 16 plain] [list 1102 $_gy 44 48 16 plain]
    }
    lappend _set_inner {996 141 150 56 16 raised} {894 409 130 56 16 raised} \
        {1036 409 110 56 16 raised} {550 690 240 72 16 accent}
    dict set pages settings [dict create out lumen_settings bloom {670 60 520 240} \
        panels $_set_panels inner $_set_inner]
    dict set pages flow_chart [dict create out lumen_flow_chart bloom {670 90 460 260} \
        panels [list {16 186 1308 318 26 plain} {170 520 1000 150 26 plain}] inner {}]
    dict set pages flow_plain [dict create out lumen_flow bloom {670 200 460 280} \
        panels [list {170 420 1000 170 26 plain}] inner {}]
    dict set pages message [dict create out lumen_message bloom {670 300 460 260} \
        panels [list {270 200 800 300 26 plain}] \
        inner [list {90 714 240 72 16 raised} {1010 714 240 72 16 accent}]]
    # 0.49.0: the glass material for plugin overlays (::lumen::glass_material),
    # two more takes of the home page: `glass` is the frosted slab the
    # popup card is cropped from, `dim` the scrim around it. Same panels
    # as home, painted from a derived palette (see glass_gen / dim_gen);
    # the slab's panels get soft edges in place of the bake's Gaussian
    # blur, which pure Tcl cannot afford on a full screen.
    dict set pages home_glass [dict merge [dict get $pages home] [dict create out lumen_home_glass variant glass]]
    dict set pages home_dim   [dict merge [dict get $pages home] [dict create out lumen_home_dim variant dim]]
    # make_backgrounds.py GLASS, per base: tint rgb, tint alpha, dim
    # factor, saturation, brightness, blur radius (design px).
    variable glass_params
    set glass_params [dict create \
        dark  [dict create tint {16 18 24}    tint_a 0.20 dim 0.66 sat 1.50 bright 1.28 blur 16] \
        light [dict create tint {246 248 251} tint_a 0.38 dim 0.78 sat 1.15 bright 1.00 blur 20]]
    unset -nocomplain _home_inner _c _x _set_panels _set_inner _y _gy
}

# ---- colour maths (pure Tcl, harness-tested) -----------------------------

proc ::lumen::custom::hsl_rgb { h s l } {
    set h [expr {fmod(double($h), 360.0)}] ; if { $h < 0 } { set h [expr {$h + 360.0}] }
    set s [expr {double($s) / 100.0}] ; set l [expr {double($l) / 100.0}]
    set a [expr {$s * min($l, 1.0 - $l)}]
    set out {}
    foreach n {0 8 4} {
        set k [expr {fmod($n + $h / 30.0, 12.0)}]
        set v [expr {$l - $a * max(-1.0, min($k - 3.0, min(9.0 - $k, 1.0)))}]
        lappend out [expr {int(round($v * 255.0))}]
    }
    return $out
}

proc ::lumen::custom::rgb_hex { rgb } {
    lassign $rgb r g b
    foreach v {r g b} { set $v [expr {max(0, min(255, int(round([set $v]))))}] }
    return [format "#%02X%02X%02X" $r $g $b]
}

proc ::lumen::custom::hex_rgb { hex } {
    scan $hex "#%2x%2x%2x" r g b
    return [list $r $g $b]
}

proc ::lumen::custom::hsl_hex { h s l } { return [rgb_hex [hsl_rgb $h $s $l]] }

# The picker's swatch table (see the namespace comment): dict bh|ah ->
# list of {hue sat display}, 26 each, memoized.
proc ::lumen::custom::swatches { key } {
    variable swatch_table
    variable hues
    if { $swatch_table eq "" } {
        set r1 [list [list 0 0 "#7A7A7A"]] ; set r2 [list [list 30 22 [hsl_hex 30 22 40]]]
        foreach h $hues { lappend r1 [list $h 36 [hsl_hex $h 36 45]] ; lappend r2 [list $h 62 [hsl_hex $h 62 45]] }
        dict set swatch_table bh [concat $r1 $r2]
        set r1 [list [list 0 0 "#C8C8C8"]] ; set r2 [list [list 30 30 [hsl_hex 30 30 42]]]
        foreach h $hues { lappend r1 [list $h 85 [hsl_hex $h 85 58]] ; lappend r2 [list $h 45 [hsl_hex $h 45 50]] }
        dict set swatch_table ah [concat $r1 $r2]
    }
    return [dict get $swatch_table $key]
}

# top (rgb list) at alpha a over bottom (rgb list) -> rgb list.
proc ::lumen::custom::over { top a bot } {
    set out {}
    foreach t $top b $bot { lappend out [expr {$t * $a + $b * (1.0 - $a)}] }
    return $out
}

proc ::lumen::custom::_lin { c } {
    set c [expr {$c / 255.0}]
    return [expr {$c <= 0.03928 ? $c / 12.92 : pow(($c + 0.055) / 1.055, 2.4)}]
}

proc ::lumen::custom::luminance { rgb } {
    lassign $rgb r g b
    return [expr {0.2126 * [_lin $r] + 0.7152 * [_lin $g] + 0.0722 * [_lin $b]}]
}

proc ::lumen::custom::contrast { rgb1 rgb2 } {
    set l1 [luminance $rgb1] ; set l2 [luminance $rgb2]
    if { $l1 < $l2 } { lassign [list $l1 $l2] l2 l1 }
    return [expr {($l1 + 0.05) / ($l2 + 0.05)}]
}

# Linear interpolation of two rgb lists.
proc ::lumen::custom::mix { a b t } {
    set out {}
    foreach x $a y $b { lappend out [expr {$x + ($y - $x) * $t}] }
    return $out
}

# 0.49.0 colour maths for the glass material. `_tone` scales brightness
# and saturation (the latter around the plain luma), `_tint` blends
# toward a colour; both clamp to 0..255 and work on rgb lists.
proc ::lumen::custom::_tone { rgb bright sat } {
    lassign $rgb r g b
    set l [expr {0.299 * $r + 0.587 * $g + 0.114 * $b}]
    set out {}
    foreach v [list $r $g $b] {
        set v [expr {($l + ($v - $l) * $sat) * $bright}]
        lappend out [expr {max(0.0, min(255.0, $v))}]
    }
    return $out
}
proc ::lumen::custom::_tint { rgb tint a } { return [mix $rgb $tint $a] }

# The painter parameters for the frosted SLAB: the bake's recipe
# (saturation and brightness up, then the tint) applied to the ground
# and the panel fills, no borders, no specular, no lift -- a blur has
# none of those -- and the same shadow, which the blur spreads anyway.
proc ::lumen::custom::glass_gen { P } {
    variable glass_params
    set g [dict get $glass_params [dict get $P base]]
    set G [dict get $P gen]
    set tint [dict get $g tint] ; set ta [dict get $g tint_a]
    set br [dict get $g bright] ; set sa [dict get $g sat]
    foreach k {top bot accfill_rgb bloom_rgb lo_rgb} {
        dict set G $k [_tint [_tone [dict get $G $k] $br $sa] $tint $ta]
    }
    dict set G white [_tint {255 255 255} $tint $ta]
    dict set G brd_a 0.0 ; dict set G brdacc_a 0.0 ; dict set G spec_a 0.0 ; dict set G lift_a 0.0
    return [dict replace $P gen $G]
}

# The painter parameters for the DIMMED page (the modal scrim): every
# colour scaled by the base's dim factor, alphas untouched.
proc ::lumen::custom::dim_gen { P } {
    variable glass_params
    set f [dict get [dict get $glass_params [dict get $P base]] dim]
    set G [dict get $P gen]
    foreach k {top bot white brd_rgb spec_rgb acc lo_rgb brdacc_rgb accfill_rgb bloom_rgb} {
        dict set G $k [_tone [dict get $G $k] $f 1.0]
    }
    return [dict replace $P gen $G]
}

# The saved preferences, clamped; unknown or missing values take the
# Lumen-dark defaults so a hand-edited settings file can never break the
# derivation.
# 0.56.0: `base` may be auto -- the glass follows the day/night schedule
# -- and `eff` is the base in force right now (auto resolved through
# ::lumen::auto_wanted; otherwise the same as base). Palette, signature,
# bake and material all work from eff. active_base is the half on screen
# (set_palette records it; the schedule tick compares against it).
namespace eval ::lumen::custom { variable active_base "" }
proc ::lumen::custom::prefs {} {
    set base dark ; set bh 222 ; set bs 32 ; set ah 34 ; set as 86
    catch {
        if { [info exists ::settings(lumen_custom_base)] && $::settings(lumen_custom_base) in {light auto} } {
            set base $::settings(lumen_custom_base)
        }
        # 0.52.0: accent saturation may be 0 (the neutral swatch); the old
        # floor of 20 turned a saved white / black accent into a tinted grey.
        foreach {k lo hi} {bh 0 360 bs 0 70 ah 0 360 as 0 100} {
            if { [info exists ::settings(lumen_custom_$k)] \
              && [string is integer -strict [string trim $::settings(lumen_custom_$k)]] } {
                set v [string trim $::settings(lumen_custom_$k)]
                if { $v < $lo } { set v $lo } elseif { $v > $hi } { set v $hi }
                set $k $v
            }
        }
    }
    set eff [expr {$base eq "auto" ? [::lumen::auto_wanted] : $base}]
    return [dict create base $base bh $bh bs $bs ah $ah as $as eff $eff]
}

# The file suffix of the custom set for a base: the dark-glass set keeps
# the 0.46.0 name (_custom), the light-glass set is _customl, so both can
# sit on disk at once and an Auto flip is a photo swap, not a re-bake.
proc ::lumen::custom::suffix { {base ""} } {
    if { $base eq "" } { set base [dict get [prefs] eff] }
    return [expr {$base eq "light" ? "_customl" : "_custom"}]
}

# The whole palette from the five inputs. Returns a dict with every C()
# token the skin uses (opaque hex, so canvas items can take them) plus the
# generator's own parameters (gradient ends, glass alphas, shadow).
#
# Contrast guard: ink_3 (the 15-16 px labels) is pushed away from the glass
# until it reads at >= 4.5:1, the accent until >= 3:1 -- the same floors
# the 0.43.1 palette review used. Semantic colours (good / warn / danger)
# and the four chart colours come from the matching baked theme and never
# change: they carry meaning, not style.
proc ::lumen::custom::palette { base bh bs ah as } {
    # 0.56.0: an auto base is the one the schedule wants right now.
    if { $base eq "auto" } { set base [::lumen::auto_wanted] }
    set dark [expr {$base ne "light"}]
    set P [dict create base $base]
    # Alphas are the bake's own (make_backgrounds.py THEMES, /255): glass
    # 14 | 150, raised 26 | 200, border 34, specular 80 | 120, shadow
    # 150 | 70, top lift 11 | 70, accent wash 12 | 120.
    if { $dark } {
        set top [hsl_rgb $bh $bs 12] ; set bot [hsl_rgb $bh [expr {min(70, $bs + 4)}] 3]
        set mid [mix $top $bot 0.5]
        set white {255 255 255}
        set glass_a 0.055 ; set raised_a 0.10 ; set brd_a 0.13 ; set spec_a 0.31 ; set lift_a 0.043
        set brd_rgb $white ; set spec_rgb $white
        set shadow_rgb {0 0 0} ; set shadow_a 0.59
        set ink   [hsl_rgb $bh 30 96]
        set ink2  [hsl_rgb $bh 20 75]
        set ink3_l 60 ; set ink3_step 4 ; set ink3_max 84
        set acc_l 59 ; set acc_step 4 ; set acc_max 78
        set lo_rgb [hsl_rgb $ah [expr {$as * 0.6}] 20] ; set lo_a 0.35
        set brdacc_rgb [hsl_rgb $ah $as 45] ; set brdacc_a 0.55
        dict set P good "#2FD3A4" ; dict set P warn "#E8B34C" ; dict set P danger "#DA515E"
        dict set P c_press "#17C29A" ; dict set P c_flow "#6C9BFF"
        dict set P c_temp "#FF7880" ; dict set P c_weight "#E6C9A8" ; dict set P grid "#1C2129"
    } else {
        set top [hsl_rgb $bh [expr {min(70, $bs + 10)}] 97] ; set bot [hsl_rgb $bh $bs 87]
        set mid [mix $top $bot 0.5]
        set white {255 255 255}
        set glass_a 0.59 ; set raised_a 0.78 ; set brd_a 0.13 ; set spec_a 0.47 ; set lift_a 0.27
        set brd_rgb [hsl_rgb $bh 40 13] ; set spec_rgb $white
        set shadow_rgb [hsl_rgb $bh 40 16] ; set shadow_a 0.27
        set ink   [hsl_rgb $bh 30 11]
        set ink2  [hsl_rgb $bh 16 35]
        set ink3_l 47 ; set ink3_step -4 ; set ink3_max 30
        # Floor 18: a saturated yellow only clears 3:1 on pale glass as a
        # dark olive, and the guard must be allowed to get there.
        set acc_l 44 ; set acc_step -4 ; set acc_max 18
        set lo_rgb [hsl_rgb $ah $as 78] ; set lo_a 0.45
        set brdacc_rgb [hsl_rgb $ah [expr {$as * 0.8}] 55] ; set brdacc_a 0.60
        dict set P good "#12805F" ; dict set P warn "#B4761A" ; dict set P danger "#B23641"
        dict set P c_press "#0E9E7C" ; dict set P c_flow "#3F72E0"
        dict set P c_temp "#E04F5C" ; dict set P c_weight "#A8763F" ; dict set P grid "#D5DBE3"
    }
    # Opaque tokens for canvas items are the panel as it really renders:
    # the glass over the SHADOWED ground (the bake casts the shadow under
    # the translucent panel). Check: this model gives #131518 for the dark
    # preset and #DEE1E5 for the light one, against the sampled chart
    # tones #151618 / #DEE0E4 of the baked images.
    set shaded [over $shadow_rgb $shadow_a $mid]
    set glass [over $white $glass_a $shaded]
    set raised [over $white $raised_a $shaded]

    # Tertiary ink: step away from the glass until the label floor holds.
    set ink3 [hsl_rgb $bh 16 $ink3_l]
    set l $ink3_l
    # Floors carry a small margin over 4.5 / 3.0 so the 8-bit hex the
    # canvas gets still clears them after channel rounding.
    while { [contrast $ink3 $glass] < 4.56 && ($ink3_step > 0 ? $l < $ink3_max : $l > $ink3_max) } {
        set l [expr {$l + $ink3_step}]
        set ink3 [hsl_rgb $bh 16 $l]
    }
    # Accent panels and pills: the bake's crema_fil REPLACES the white glass
    # -- a faint accent wash over the shadowed ground (12/255 on dark,
    # (255,206,132) at 120/255 on light), never the full-strength accent.
    # On dark the wash is the accent itself, so it is re-derived inside
    # the guard loop below.
    set accfill_a [expr {$dark ? 0.06 : 0.47}]
    set accfill_rgb [hsl_rgb $ah $as 76]
    # 0.52.0: the neutral accent (saturation 0, the picker's white / black
    # swatch) starts near white on dark and near black on light; the
    # hue-tuned start (59 / 44) is a mid grey for it, which read as dull.
    if { $as <= 0 } { set acc_l [expr {$dark ? 88 : 25}] }
    # Accent: the same, to 3:1 (large text and controls), against the plain
    # glass AND its own wash (0.52.0): the hero number, Done and the Steam /
    # Water buttons sit on the wash, a mid tone on a light base that the
    # plain-glass floor left at 2.1:1 in the worst case.
    set acc [hsl_rgb $ah $as $acc_l]
    set l $acc_l
    while { 1 } {
        if { $dark } { set accfill_rgb $acc }
        set accpanel [over $accfill_rgb $accfill_a $shaded]
        if { [contrast $acc $glass] >= 3.06 && [contrast $acc $accpanel] >= 3.06 } { break }
        if { $acc_step > 0 ? $l >= $acc_max : $l <= $acc_max } { break }
        set l [expr {$l + $acc_step}]
        set acc [hsl_rgb $ah $as $l]
    }

    dict set P bg        [rgb_hex $mid]
    dict set P bg_top    [rgb_hex $top]
    dict set P bg_bot    [rgb_hex $bot]
    dict set P glass     [rgb_hex $glass]
    dict set P glass_2   [rgb_hex $raised]
    dict set P glass_brd [rgb_hex [over $brd_rgb $brd_a $shaded]]
    dict set P spec      [rgb_hex [over $spec_rgb $spec_a $shaded]]
    dict set P ink       [rgb_hex $ink]
    dict set P ink_2     [rgb_hex $ink2]
    dict set P ink_3     [rgb_hex $ink3]
    dict set P crema     [rgb_hex $acc]
    dict set P crema_lo  [rgb_hex $accpanel]
    dict set P crema_brd [rgb_hex [over $brdacc_rgb $brdacc_a $accpanel]]
    # The chart widgets are opaque: match the flat panel at its centre
    # height, 414 of 800 on home and 345 of 800 on the espresso page.
    dict set P chart_bg      [rgb_hex [over $white $glass_a [over $shadow_rgb $shadow_a [mix $top $bot [expr {414 / 800.0}]]]]]
    dict set P chart_bg_flow [rgb_hex [over $white $glass_a [over $shadow_rgb $shadow_a [mix $top $bot [expr {345 / 800.0}]]]]]

    # Generator parameters (rgb lists / alphas), consumed by bake.
    dict set P gen [dict create top $top bot $bot white $white \
        glass_a $glass_a raised_a $raised_a brd_rgb $brd_rgb brd_a $brd_a \
        spec_rgb $spec_rgb spec_a $spec_a lift_a $lift_a \
        shadow_rgb $shadow_rgb shadow_a $shadow_a \
        acc $acc lo_rgb $lo_rgb lo_a $lo_a brdacc_rgb $brdacc_rgb brdacc_a $brdacc_a \
        accfill_rgb $accfill_rgb accfill_a $accfill_a \
        bloom_rgb $acc bloom_a [expr {$dark ? 0.16 : 0.28}]]
    return $P
}

# ---- the runtime baker ----------------------------------------------------

proc ::lumen::custom::_png_chunk { type data } {
    set td "$type$data"
    return "[binary format I [string length $data]]$td[binary format I [zlib crc32 $td]]"
}

# rows: one binary string of 4*w bytes (RGBA, straight alpha) per row.
proc ::lumen::custom::png_encode { w h rows } {
    set raw ""
    foreach r $rows { append raw "\x00" $r }
    set ihdr [binary format IIccccc $w $h 8 6 0 0 0]
    return "\x89PNG\r\n\x1a\n[_png_chunk IHDR $ihdr][_png_chunk IDAT [zlib compress $raw 6]][_png_chunk IEND {}]"
}

# A Gaussian-blurred rectangle's edge profile, separable: 1 deep inside
# the rectangle, 0.5 ON its edge, 0 beyond ~2 sigma outside. d is the
# SIGNED distance to the edge (negative inside), S ~ 2 sigma. Continuous,
# which is the whole point: 0.46.0 jumped from 1 to 0.5 at the shadow's
# offset edge and every panel wore a hard darker strip underneath.
proc ::lumen::custom::_fall { d S } {
    if { $d <= -$S } { return 1.0 }
    if { $d >= $S } { return 0.0 }
    set t [expr {($S - $d) / (2.0 * $S)}]
    return [expr {$t * $t * (3.0 - 2.0 * $t)}]
}

# One RGBA pixel: the panel colour rgb at straight alpha a, with coverage
# c from the rounded-rect distance, over its shadow (alpha sa). The shadow
# lies UNDER the glass, as in the Python bake (shadow first, translucent
# fill over it): that darkening is what makes the real panels read grey
# instead of white, and the sampled chart tones confirm it.
proc ::lumen::custom::_px { c rgb a shrgb sa } {
    set ca [expr {$a * $c}]
    set oa [expr {$ca + $sa * (1.0 - $ca)}]
    if { $oa <= 0.0 } { return [binary format cccc 0 0 0 0] }
    set out {}
    foreach t $rgb s $shrgb {
        lappend out [expr {int(round(($t * $ca + $s * $sa * (1.0 - $ca)) / $oa))}]
    }
    lassign $out r g b
    return [binary format cccc $r $g $b [expr {int(round($oa * 255.0))}]]
}

# A rounded panel of w x h physical px with corner radius rr, painted as a
# PNG (w + 2S) x (h + 2S) with the shadow margin S around it (shadow rect
# offset dy down, edge profile _fall). kind: plain | raised | accent; flat
# skips the top-lift gradient (the chart panels, whose opaque graph must
# match one tone). Per-pixel work is confined to the margins, the corner
# bands, the two specular rows and the top-lift rows; identical rows are
# painted once (memo by shadow factor and row alpha).
# 0.49.0 `soft`: > 0 paints a BLURRED look-alike for the glass material --
# the fill's alpha ramps over `soft` px across the panel edge (1 inside,
# 0.5 on the edge, 0 outside, the shadow's own _fall profile) instead of
# the one-pixel anti-aliased edge, and there is no border and no specular.
# The caller keeps S >= soft so the ramp fits the margin.
proc ::lumen::custom::panel_png { P w h rr kind S dy {flat 0} {soft 0} } {
    set G [dict get $P gen]
    set white [dict get $G white]
    set shrgb [dict get $G shadow_rgb] ; set sha [dict get $G shadow_a]
    switch -exact -- $kind {
        raised { set fill $white ; set fa [dict get $G raised_a]
                 set brd [dict get $G brd_rgb] ; set ba [dict get $G brd_a] }
        accent { set fill [dict get $G accfill_rgb] ; set fa [dict get $G accfill_a]
                 set brd [dict get $G brdacc_rgb] ; set ba [dict get $G brdacc_a] }
        default { set fill $white ; set fa [dict get $G glass_a]
                  set brd [dict get $G brd_rgb] ; set ba [dict get $G brd_a] }
    }
    set spa [dict get $G spec_a] ; set hi [dict get $G lift_a]
    if { $rr * 2 > $w } { set rr [expr {$w / 2}] }
    if { $rr * 2 > $h } { set rr [expr {$h / 2}] }
    set W [expr {$w + 2 * $S}] ; set H [expr {$h + 2 * $S}]
    set hw [expr {$w / 2.0}] ; set hh [expr {$h / 2.0}]
    set edge [expr {max($rr, $soft)}]
    set zone [expr {$S + $edge + 2}]         ;# per-pixel columns each side
    # 0.50.1: a panel too narrow for a middle stretch is painted per pixel
    # end to end. Clamping `zone` to W/2 (as before) put the shortcut's
    # "x == zone" exactly where its "set x W - zone - 1" jumped back to,
    # and the row loop never advanced: the Sea glass set (light base,
    # blur 20, 44 px pills) hung the bake at skin load -- owner report.
    if { 2 * $zone >= $W } { set zone -1 }
    set span [expr {$flat ? 0 : int($h * 0.85)}]
    set rows {}
    array set memo {}
    for { set y 0 } { $y < $H } { incr y } {
        set cy [expr {$y - $S}]
        set py [expr {$cy + 0.5 - $hh}]
        set qy [expr {abs($py) - ($hh - $rr)}]
        # Shadow: signed distance to the offset shadow rect, vertically.
        set dys [expr {max($dy - ($cy + 0.5), ($cy + 0.5) - ($h + $dy))}]
        set fy [_fall $dys $S]
        set inner_row [expr {$cy >= 0 && $cy < $h}]
        # Top lift: a white wash fading down 85% of the panel (Python's
        # glass_hi), folded into this row's fill alpha (white over fill).
        set la 0.0
        if { $inner_row && $cy < $span } {
            set la [expr {$hi * pow(1.0 - double($cy) / $span, 1.15)}]
        }
        # Quantised to what a PNG byte can hold, so consecutive lift rows
        # that round to the same alpha share one painted row.
        set fa_row [expr {int(round(($fa + $la - $fa * $la) * 255.0)) / 255.0}]
        set spec_row [expr {($cy == 1 || $cy == 2) && !$soft}]
        set straight [expr {$inner_row && $cy > $edge && $cy < $h - $edge - 1}]
        set key "[expr {int(round($fy * 255.0))}]|[expr {int(round($fa_row * 255.0))}]"
        if { $straight && [info exists memo($key)] } {
            lappend rows $memo($key)
            continue
        }
        set row ""
        if { $soft } {
            # Middle stretch of a soft panel: the vertical distance alone.
            set midd [expr {abs($py) - $hh}]
            set midc [_fall $midd $soft]
            set midpx [_px $midc $fill $fa_row $shrgb [expr {$sha * $fy}]]
        } else {
            if { $straight } {
                set midc 1.0 ; set midd -2.0
            } elseif { $inner_row } {
                set midc 1.0 ; set midd [expr {abs($py) - $hh}]
            } else {
                set midc 0.0 ; set midd 1.0
            }
            if { $midd > -1.0 && $midc > 0.0 } {
                set midpx [_px $midc $brd $ba $shrgb [expr {$sha * $fy}]]
            } else {
                set midpx [_px $midc $fill $fa_row $shrgb [expr {$sha * $fy}]]
            }
        }
        for { set x 0 } { $x < $W } { incr x } {
            if { $x == $zone && !$spec_row } {
                append row [string repeat $midpx [expr {$W - 2 * $zone}]]
                set x [expr {$W - $zone - 1}]
                continue
            }
            set cx [expr {$x - $S}]
            set px [expr {$cx + 0.5 - $hw}]
            set qx [expr {abs($px) - ($hw - $rr)}]
            set mx [expr {$qx > 0.0 ? $qx : 0.0}] ; set my [expr {$qy > 0.0 ? $qy : 0.0}]
            set d [expr {sqrt($mx * $mx + $my * $my) + min(max($qx, $qy), 0.0) - $rr}]
            if { $soft } {
                set c [_fall $d $soft]
            } else {
                set c [expr {0.5 - $d}]
                if { $c > 1.0 } { set c 1.0 } elseif { $c < 0.0 } { set c 0.0 }
            }
            set dxs [expr {max(-($cx + 0.5), ($cx + 0.5) - $w)}]
            set sa [expr {$sha * $fy * [_fall $dxs $S]}]
            if { !$soft && $c > 0.0 && $d > -1.0 } {
                append row [_px $c $brd $ba $shrgb $sa]
            } elseif { $spec_row && $c > 0.0 && $cx >= $rr && $cx < $w - $rr } {
                # The specular run: fades to nothing at both ends (a plain
                # line "stopped dead and read as a seam" -- the bake's own
                # note), full on row 1, half on row 2.
                set t [expr {double($cx - $rr) / max(1, $w - 2 * $rr - 1)}]
                set sp [expr {$spa * pow(1.0 - abs(2.0 * $t - 1.0), 0.8) * ($cy == 1 ? 1.0 : 0.5)}]
                set a [expr {$fa_row + $sp - $fa_row * $sp}]
                set rgb [mix $fill $white [expr {$a > 0 ? $sp / $a : 0.0}]]
                append row [_px $c $rgb $a $shrgb $sa]
            } else {
                append row [_px $c $fill $fa_row $shrgb $sa]
            }
        }
        if { $straight } { set memo($key) $row }
        lappend rows $row
    }
    return [png_encode $W $H $rows]
}

# The soft glow behind a page's hero, at 1/4 scale (zoomed x4 on copy):
# an ellipse whose alpha falls off smoothly to the rim.
proc ::lumen::custom::bloom_png { P rx ry } {
    set G [dict get $P gen]
    lassign [dict get $G bloom_rgb] r g b
    set a0 [dict get $G bloom_a]
    set w [expr {int(2 * $rx)}] ; set h [expr {int(2 * $ry)}]
    set rows {}
    for { set y 0 } { $y < $h } { incr y } {
        set row ""
        set ny [expr {($y + 0.5 - $ry) / $ry}]
        for { set x 0 } { $x < $w } { incr x } {
            set nx [expr {($x + 0.5 - $rx) / $rx}]
            set dd [expr {$nx * $nx + $ny * $ny}]
            if { $dd >= 1.0 } {
                append row [binary format cccc 0 0 0 0]
            } else {
                set t [expr {1.0 - $dd}]
                append row [binary format cccc [expr {int($r)}] [expr {int($g)}] [expr {int($b)}] \
                    [expr {int(round(255.0 * $a0 * $t * $t))}]]
            }
        }
        lappend rows $row
    }
    return [png_encode $w $h $rows]
}

# 0.57.0: the halo behind the active favorite slot -- a pill (radius
# h/2) of the accent whose alpha falls from a0 inside its edge to 0 over
# `soft` px outside it, (1 - d/soft)^2: the shape the mockup's blurred
# pill had. w x h is the PNG in physical px; the pill is inset `soft` on
# every side so the falloff fits.
proc ::lumen::custom::halo_png { rgb a0 w h soft } {
    lassign $rgb r g b
    set r [expr {int($r)}] ; set g [expr {int($g)}] ; set b [expr {int($b)}]
    set pw [expr {$w - 2 * $soft}] ; set ph [expr {$h - 2 * $soft}]
    if { $pw < 2 || $ph < 2 || $soft < 1 } { error "halo too small ($w x $h, soft $soft)" }
    set rr [expr {$ph / 2.0}]
    set hw [expr {$pw / 2.0}] ; set hh [expr {$ph / 2.0}]
    set cx [expr {$w / 2.0}] ; set cy [expr {$h / 2.0}]
    set clear [binary format cccc 0 0 0 0]
    set rows {}
    for { set y 0 } { $y < $h } { incr y } {
        set row ""
        set qy [expr {abs($y + 0.5 - $cy) - ($hh - $rr)}]
        for { set x 0 } { $x < $w } { incr x } {
            set qx [expr {abs($x + 0.5 - $cx) - ($hw - $rr)}]
            # Signed distance to the rounded rect (negative inside).
            set ox [expr {max($qx, 0.0)}] ; set oy [expr {max($qy, 0.0)}]
            set d [expr {sqrt($ox * $ox + $oy * $oy) + min(max($qx, $qy), 0.0) - $rr}]
            if { $d >= $soft } { append row $clear ; continue }
            set t [expr {$d <= 0.0 ? 1.0 : 1.0 - $d / $soft}]
            append row [binary format cccc $r $g $b [expr {int(round(255.0 * $a0 * $t * $t))}]]
        }
        lappend rows $row
    }
    return [png_encode $w $h $rows]
}

# Pastes src onto img at (tx, ty) with integer zoom z, cropping the source
# so nothing lands outside img: a Tk photo `copy -to` refuses negative
# coordinates and GROWS the destination past its right and bottom edges.
proc ::lumen::custom::_paste { img src tx ty z } {
    set sw [image width $src] ; set sh [image height $src]
    set dw [image width $img] ; set dh [image height $img]
    set fx 0 ; set fy 0
    if { $tx < 0 } { set fx [expr {int(ceil(-$tx / double($z)))}] ; set tx [expr {$tx + $fx * $z}] }
    if { $ty < 0 } { set fy [expr {int(ceil(-$ty / double($z)))}] ; set ty [expr {$ty + $fy * $z}] }
    set fx2 [expr {min($sw, $fx + int(($dw - $tx) / $z))}]
    set fy2 [expr {min($sh, $fy + int(($dh - $ty) / $z))}]
    if { $fx2 <= $fx || $fy2 <= $fy } { return }
    $img copy $src -from $fx $fy $fx2 $fy2 -to $tx $ty -zoom $z $z
}

# Draws ONE page background at W x H physical px into a Tk photo and
# returns its name (caller deletes). Needs Tk.
proc ::lumen::custom::page_photo { P spec W H } {
    set sx [expr {$W / 1340.0}] ; set sy [expr {$H / 800.0}]
    # 0.49.0: the two material takes paint the same layout from a derived
    # palette; the slab also softens every edge (blur stand-in).
    set soft 0
    switch -exact -- [expr {[dict exists $spec variant] ? [dict get $spec variant] : ""}] {
        glass { set P [glass_gen $P]
                variable glass_params
                set soft [expr {int(round([dict get [dict get $glass_params [dict get $P base]] blur] * $sy))}] }
        dim   { set P [dim_gen $P] }
    }
    set G [dict get $P gen]
    set top [dict get $G top] ; set bot [dict get $G bot]

    # Backdrop: a one-column photo, one put per row, zoomed to the width.
    set col [image create photo]
    for { set y 0 } { $y < $H } { incr y } {
        set t [expr {$y / double($H - 1)}]
        $col put [list [list [rgb_hex [mix $top $bot $t]]]] -to 0 $y
    }
    set img [image create photo -width $W -height $H]
    $img copy $col -zoom $W 1
    image delete $col

    # Bloom, behind everything, quarter-scale then zoomed.
    lassign [dict get $spec bloom] bcx bcy brx bry
    set qrx [expr {int(round($brx * $sx / 4.0))}] ; set qry [expr {int(round($bry * $sy / 4.0))}]
    if { $qrx > 2 && $qry > 2 } {
        set bl [image create photo -data [bloom_png $P $qrx $qry]]
        _paste $img $bl [expr {int(round($bcx * $sx)) - 4 * $qrx}] [expr {int(round($bcy * $sy)) - 4 * $qry}] 4
        image delete $bl
    }

    # Panels then inner pills. One shadow recipe for both, the bake's own:
    # blur sigma 9 (S = 2 sigma = 18) offset 6 design px. The chart panels
    # (the second panel of flow_chart, the third of home) are flat.
    set S [expr {int(round(18 * $sy))}] ; set dy [expr {int(round(6 * $sy))}]
    if { $soft > $S } { set S $soft }
    foreach group {panels inner} {
        set i 0
        foreach item [dict get $spec $group] {
            lassign $item x y w h r kind
            set flat [expr {$group eq "panels" && [dict get $spec out] in {lumen_home lumen_flow_chart} \
                            && (([dict get $spec out] eq "lumen_home" && $i == 2) \
                             || ([dict get $spec out] eq "lumen_flow_chart" && $i == 0))}]
            set pw [expr {int(round($w * $sx))}] ; set ph [expr {int(round($h * $sy))}]
            set png [panel_png $P $pw $ph [expr {int(round($r * $sy))}] $kind $S $dy $flat $soft]
            set pi [image create photo -data $png]
            _paste $img $pi [expr {int(round($x * $sx)) - $S}] [expr {int(round($y * $sy)) - $S}] 1
            image delete $pi
            incr i
        }
    }
    return $img
}

# The screen in physical px, from dui or Tk, or 0 0 when neither answers.
proc ::lumen::custom::screen {} {
    set W 0 ; set H 0
    catch { set W [expr {int([dui cget screen_size_width])}] ; set H [expr {int([dui cget screen_size_height])}] }
    if { $W <= 0 || $H <= 0 } { catch { set W [winfo screenwidth .] ; set H [winfo screenheight .] } }
    if { $W <= 0 || $H <= 0 } { return {0 0} }
    return [list $W $H]
}

# Signature of what the custom files were drawn from. The leading number
# is the PAINTER version: bump it whenever the painter changes so files
# drawn by an older one are redrawn (2 = 0.46.1's shadow-under-glass model).
proc ::lumen::custom::signature { pr } {
    # 3 = 0.49.0: the glass material files joined the set.
    # 4 = 0.52.0: the accent derivation changed (wash guard, neutral start),
    #     so files painted with the old accent are redrawn once.
    # 0.56.0: the base IN FORCE (auto resolved), so an auto set's two
    # halves each carry their own signature beside their own files.
    set base [dict get $pr base]
    if { [dict exists $pr eff] } { set base [dict get $pr eff] } elseif { $base eq "auto" } { set base [::lumen::auto_wanted] }
    return "4 $base [dict get $pr bh] [dict get $pr bs] [dict get $pr ah] [dict get $pr as]"
}

# Makes sure lumen_*_custom.png exist for the screen and match the saved
# colours; draws them when they do not. Returns 1 when every file is in
# place, 0 when drawing was impossible (no Tk, write failed) -- the caller
# then falls back to -bg_color pages. Runs at skin load, before any page
# is declared, and only for the custom theme.
# 0.56.0: `base` picks which half of an auto set to draw (default: the
# base in force). Files, signature and marker carry that base's suffix.
proc ::lumen::custom::ensure_bake { {base ""} } {
    variable pages
    if { [info commands image] eq "" } { return 0 }
    lassign [screen] W H
    if { $W <= 0 || $H <= 0 } { return 0 }
    set dir "[homedir]/skins/Lumen/${W}x${H}"
    set pr [prefs]
    if { $base eq "" } { set base [dict get $pr eff] }
    dict set pr eff $base
    set sfx [suffix $base]
    set sig [signature $pr]
    set sigfile "$dir/lumen$sfx.sig"
    set have 1
    dict for {name spec} $pages {
        if { ![file isfile "$dir/[dict get $spec out]$sfx.png"] } { set have 0 }
    }
    set old ""
    catch { set fh [open $sigfile r] ; set old [string trim [read $fh]] ; close $fh }
    if { $have && $old eq $sig } { return 1 }

    # 0.50.1 safety net: a bake that never returns (the Sea glass hang)
    # locks the app at every start, because the same bake runs at skin
    # load. So a marker is written before painting and removed after; a
    # marker found here means the last attempt died mid-way, and this
    # set is refused -- flat pages, a usable app, and a log line -- until
    # the colours change or the marker is cleared by hand.
    set marker "$dir/lumen$sfx.baking"
    if { [file exists $marker] } {
        set was ""
        catch { set fh [open $marker r] ; set was [string trim [read $fh]] ; close $fh }
        file delete -force $marker
        if { $was eq $sig } {
            msg -ERROR "Lumen: the last bake of this custom set ($sig) never finished; not trying it again at load"
            return 0
        }
    }
    msg -INFO "Lumen: drawing custom theme backgrounds ($sig) at ${W}x${H}"
    set t0 [clock milliseconds]
    if { [catch {
        file mkdir $dir
        set fh [open $marker w] ; puts $fh $sig ; close $fh
        set P [palette $base [dict get $pr bh] [dict get $pr bs] [dict get $pr ah] [dict get $pr as]]
        dict for {name spec} $pages {
            set img [page_photo $P $spec $W $H]
            set path "$dir/[dict get $spec out]$sfx.png"
            if { [catch { $img write $path -format png } werr] } {
                # Some Img builds want the tkimg spelling.
                $img write $path -format {png -alpha 1.0}
            }
            image delete $img
        }
        set fh [open $sigfile w] ; puts $fh $sig ; close $fh
        file delete -force $marker
    } err] } {
        msg -ERROR "Lumen: custom theme backgrounds failed: $err"
        return 0
    }
    msg -INFO "Lumen: custom theme backgrounds drawn in [expr {[clock milliseconds] - $t0}] ms"
    return 1
}

#############################################################################
#  Live retheme (0.47.0)
#
#  Until 0.46.1 the palette was read once at load and every canvas item was
#  created from it, so a theme change meant quitting the app (which cannot
#  relaunch itself on Android 16). Now a theme is applied in place:
#
#    1. custom only: ::lumen::custom::ensure_bake draws the five page
#       backgrounds for the saved colours if they are not on disk yet;
#    2. ::lumen::set_palette loads the new C() tokens;
#    3. every page background swaps its photo (the theme's baked PNG,
#       loaded through dui's own resolver) or, on flat pages, its fill;
#    4. every role-tagged item (see ::lumen::_tags) is reconfigured, one
#       itemconfigure per token;
#    5. the photo panels on non-baked pages are repainted from the new
#       painter parameters, the graph widgets restyled, the picker's
#       selection rings refreshed.
#
#    6. (0.48.0) DYE's pages: the DYE_Lumen aspects are set again and every
#       page on that theme goes through dui's own `page retheme`.
#
#  The GrindAdvisor glass popup reads glass_material when it opens, so it
#  follows by itself.
#############################################################################

# Applies `mode` (dark | light | custom) live. Returns 1 when the theme is
# on screen, 0 when it could not be (the current theme stays, the reason
# is in the log and in theme_status for the THEME row's caption).
proc ::lumen::apply_theme { mode } {
    variable C
    variable theme_mode
    variable theme_status
    variable role_tokens
    variable _flat_pages

    set t0 [clock milliseconds]
    set old $theme_mode
    set theme_status ""
    if { $mode ni {dark light custom} } {
        msg -ERROR "Lumen: unknown theme '$mode' not applied"
        return 0
    }

    # Custom on photo pages needs its backgrounds before anything changes.
    # (Pages declared flat at load carry drawn panels and a plain fill, so
    # they retint without files.)
    set word [_theme_word $mode]
    if { $mode eq "custom" && !$_flat_pages } {
        wait_step "[translate {Applying}] $word: [translate {drawing backgrounds...}]"
        set baked 0
        if { [catch { set baked [::lumen::custom::ensure_bake] } err] } {
            msg -ERROR "Lumen: custom theme bake threw: $err"
            set baked 0
        }
        if { !$baked } {
            msg -ERROR "Lumen: custom theme not applied: its backgrounds could not be drawn"
            set theme_status [translate "Custom not applied: its backgrounds could not be drawn. See the log."]
            return 0
        }
    }

    set_palette $mode
    set theme_mode $mode
    switch -exact -- $mode {
        light   { set ::lumen::_bg_suffix "_light" }
        custom  { set ::lumen::_bg_suffix [::lumen::custom::suffix] }
        default { set ::lumen::_bg_suffix "" }
    }
    wait_step "[translate {Applying}] $word: [translate {colours and backgrounds...}]"

    set problems 0
    if { [catch { set can [dui canvas] ; $can configure -bg $C(bg) } err] } {
        msg -ERROR "Lumen: could not recolour the canvas ground: $err" ; incr problems
    }
    if { [catch { _swap_backgrounds } err] } {
        msg -ERROR "Lumen: could not swap the page backgrounds: $err" ; incr problems
    }
    foreach tok $role_tokens {
        if { [catch {
            $can itemconfigure lumen_c_$tok -fill $C($tok)
            $can itemconfigure lumen_o_$tok -outline $C($tok)
        } err] } {
            msg -ERROR "Lumen: could not recolour the $tok items: $err" ; incr problems
        }
    }
    if { [catch { _redraw_photo_panels } err] } {
        msg -ERROR "Lumen: could not repaint the photo panels: $err" ; incr problems
    }
    if { [catch { _redraw_fav_glow } err] } {
        msg -ERROR "Lumen: could not repaint the favorite halo: $err" ; incr problems
    }
    if { [catch { _retheme_charts } err] } {
        msg -ERROR "Lumen: could not restyle the charts: $err" ; incr problems
    }
    if { [catch { _retheme_dye } err] } {
        msg -ERROR "Lumen: could not retheme the DYE pages: $err" ; incr problems
    }
    # The picker's selection rings and base pills read C() -- refresh_preview
    # logs its own failures.
    refresh_preview

    msg -INFO "Lumen: theme $old -> $mode applied live in [expr {[clock milliseconds] - $t0}] ms ($problems problems)"
    return 1
}

# The photo for one background file of the current theme, through dui's
# own resolver (screen-size folder, 2560x1600 rescale fallback). Reuses
# the image dui loaded at page add when it has one; otherwise Lumen owns
# it. A custom file is re-read from disk on every swap, because the same
# filename holds different pixels after a re-bake.
proc ::lumen::_bg_photo { file } {
    variable bg_owned
    set path [dui::image::find $file 1]
    if { $path eq "" } { error "background '$file' not found" }
    set custom [expr {[string match "*_custom.png" $file] || [string match "*_customl.png" $file]}]
    if { [dui::image::is_loaded $path] } {
        set img [dui::image::get $path]
        if { $custom } { $img read $path -shrink }
        return $img
    }
    if { [dict exists $bg_owned $path] } {
        set img [dict get $bg_owned $path]
        if { $custom } { $img read $path -shrink }
        return $img
    }
    set img [image create photo -file $path]
    dict set bg_owned $path $img
    return $img
}

# Every Lumen page background: photo items take the theme's file, flat
# ones (the picker; every page when custom loaded without backgrounds)
# take the page colour. Photos Lumen loaded for a theme no longer on any
# page are freed, so at most one spare set stays in memory.
proc ::lumen::_swap_backgrounds {} {
    variable C
    variable bg_owned
    set can [dui canvas]
    set in_use [list]
    foreach {page file} [list off lumen_home lumen_settings lumen_settings \
                              espresso lumen_flow_chart steam lumen_flow \
                              water lumen_flow hotwaterrinse lumen_flow \
                              tankempty lumen_message refill lumen_message \
                              lumen_theme ""] {
        foreach id [$can find withtag "pages&&$page"] {
            if { [$can type $id] eq "image" } {
                if { $file eq "" } { continue }
                set img [_bg_photo "$file$::lumen::_bg_suffix.png"]
                $can itemconfigure $id -image $img
                lappend in_use $img
            } else {
                $can itemconfigure $id -fill $C(bg)
            }
        }
    }
    dict for {path img} $bg_owned {
        if { $img ni $in_use } {
            image delete $img
            dict unset bg_owned $path
        }
    }
}

# Photo panels on non-baked pages: paint each again from the new theme's
# painter parameters, hand the item the new photo, free the old one.
proc ::lumen::_redraw_photo_panels {} {
    variable photo_items
    set can [dui canvas]
    dict for {tag spec} $photo_items {
        set ids [$can find withtag $tag]
        if { $ids eq "" } { continue }
        set old [$can itemcget [lindex $ids 0] -image]
        lassign [_panel_photo $spec] img px py
        $can itemconfigure $tag -image $img
        if { $old ne "" && $old ne $img } { image delete $old }
    }
}

# 0.48.0: DYE's pages follow. They are styled by the DYE_Lumen dui theme,
# whose aspects were read when the pages were set up, so: set the aspects
# again from the new palette, then hand every page on that theme to dui's
# own `page retheme` (delete keeping its data, add again with the saved
# arguments, run the page's setup) -- the mechanism dui names for exactly
# this in its "already setup" warning. Returns the number of pages redone.
# Skipped, with a NOTICE, if a DYE page is the one on screen (dui refuses
# to delete the current page); nothing else is ever on screen while the
# THEME row or the picker's Done runs, so this is a guard, not a path.
proc ::lumen::_retheme_dye {} {
    if { ![string is true -strict [dui theme exists DYE_Lumen]] } { return 0 }
    dye_aspects
    set pages [list] ; set skipped [list]
    foreach p [dui page list] {
        if { [dui page theme $p] ne "DYE_Lumen" } { continue }
        # 0.48.1: only DYE's own pages, and only those dui can rebuild. A
        # page without a namespace `setup` proc comes back EMPTY from a
        # recreate (the delete succeeds, nothing redraws it). Other
        # plugins' pages land on this theme when they are added while it
        # is current (seen on the tablet: DPx_SS_options and
        # history_exclusion_filter, both namespace-less); they keep their
        # look, as before 0.48.0.
        if { ![string match {DYE*} $p] && ![string match {dye_*} $p] } { lappend skipped $p ; continue }
        set ns [dui page get_namespace $p]
        if { $ns eq "" || [info procs ${ns}::setup] eq "" } { lappend skipped $p ; continue }
        lappend pages $p
    }
    if { [llength $skipped] } {
        msg -DEBUG "Lumen: pages on DYE_Lumen left alone (not DYE's, or no setup): $skipped"
    }
    if { [llength $pages] == 0 } { return 0 }
    set cur [dui page current]
    if { $cur in $pages } {
        msg -NOTICE "Lumen: DYE page '$cur' is on screen, DYE keeps its colours until the next launch"
        return 0
    }
    set t0 [clock milliseconds]
    set n 0 ; set i 0 ; set total [llength $pages]
    # 0.50.0: one page per call so the wait pill can count them off.
    set word [_theme_word $::lumen::theme_mode]
    foreach p $pages {
        wait_step "[translate {Applying}] $word: [translate {DYE pages}] [incr i] / $total..."
        foreach ok [dui page retheme $p DYE_Lumen 1] {
            if { [string is true -strict $ok] } { incr n }
        }
    }
    msg -INFO "Lumen: DYE rethemed, $n of $total pages recreated in [expr {[clock milliseconds] - $t0}] ms"
    return $n
}

# The graph widgets: opaque Tk widgets, so their backgrounds are the
# sampled panel tones, and their series carry the theme's chart colours.
proc ::lumen::_retheme_charts {} {
    variable C
    variable charts
    foreach {w tok} $charts {
        if { [catch {
            $w configure -background $C($tok) -plotbackground $C($tok)
            set have [$w element names]
            foreach {el ctok} {l_pressure c_press l_flow c_flow l_weight c_weight \
                               l_temp c_temp l_stages ink_3} {
                if { $el in $have } { $w element configure $el -color $C($ctok) }
            }
            $w axis configure x -color $C(ink_3)
            $w axis configure y -color $C(ink_3)
            gridconfigure $w
        } err] } {
            msg -ERROR "Lumen: could not restyle chart $w: $err"
        }
    }
}

#############################################################################
#  Boot
#############################################################################

# Use the stock utility pages (settings, firmware, descale, profile editors)
# rather than reimplementing them. This is the same approach DSx2 takes.
source "[homedir]/skins/default/standard_includes.tcl"

set ::lumen::theme_mode "dark"
catch {
    if { [info exists ::settings(lumen_theme)] && $::settings(lumen_theme) in {dark light custom} } {
        set ::lumen::theme_mode $::settings(lumen_theme)
    }
}
::lumen::set_palette $::lumen::theme_mode
::lumen::_init_layout

# 0.46.0: the custom theme draws its own page backgrounds on the tablet
# (see ::lumen::custom::ensure_bake). When that is impossible the pages
# are declared on a flat colour and the vector glass primitive draws the
# panels instead -- the pre-0.20.0 look, never a blank screen.
set ::lumen::_custom_baked 0
if { $::lumen::theme_mode eq "custom" } {
    if { [catch { set ::lumen::_custom_baked [::lumen::custom::ensure_bake] } err] } {
        msg -ERROR "Lumen: custom theme bake threw: $err"
        set ::lumen::_custom_baked 0
    }
    if { !$::lumen::_custom_baked } {
        msg -NOTICE "Lumen: custom theme running on flat pages (no backgrounds drawn)"
        set ::lumen::baked_pages [list]
    }
}
# 0.47.0: fixed for the session -- flat pages carry drawn panels over a
# plain fill and retint without files; photo pages swap their PNG.
set ::lumen::_flat_pages [expr {$::lumen::theme_mode eq "custom" && !$::lumen::_custom_baked}]

# Every page uses a pre-rendered background. Tk canvas has no alpha and no
# blur, so the frosted panels, their blurred backdrops, the soft shadows and
# the crema bloom are composited offline by tools/make_backgrounds.py and
# loaded here as images. dui resolves each file from the resolution folder
# that matches the screen (1340x800 / 2560x1600).
#
# We deliberately do not source skins/default/standard_stop_buttons.tcl: it
# would re-declare the flow pages with the default skin's background JPGs and
# paint over ours. Its stop-button bindings are reproduced verbatim further
# down.
#
# The four flow pages are NOT one dui page add call any more: espresso uses
# the compact layout (its live chart needs the middle of the screen) while
# steam, water and hotwaterrinse keep the roomier one, so they take different
# images. The three roomy ones still share a single file -- build_flow_page
# draws identical panels for all three and only the label text differs.
#
# 0.20.0: before this, everything except home was -bg_color plus vector
# glass, which is why the settings and flow pages looked a generation behind.
set ::lumen::pages [list espresso steam water hotwaterrinse]

switch -exact -- $::lumen::theme_mode {
    light   { set ::lumen::_bg_suffix "_light" }
    custom  { set ::lumen::_bg_suffix [::lumen::custom::suffix] }
    default { set ::lumen::_bg_suffix "" }
}

# The five page declarations, either on their image or (custom theme with
# no drawn backgrounds) on the flat page colour.
proc ::lumen::_page_bg_args { img } {
    if { $::lumen::theme_mode eq "custom" && !$::lumen::_custom_baked } {
        return [list -bg_color $::lumen::C(bg)]
    }
    return [list -bg_img "$img$::lumen::_bg_suffix.png"]
}

dui page add off            {*}[::lumen::_page_bg_args lumen_home]
dui page add lumen_settings {*}[::lumen::_page_bg_args lumen_settings]
dui page add espresso       {*}[::lumen::_page_bg_args lumen_flow_chart]
dui page add [list steam water hotwaterrinse] {*}[::lumen::_page_bg_args lumen_flow]
# 0.46.0: the picker page is never baked -- it draws vector glass in the
# CURRENT theme and a live preview of the pending one.
dui page add lumen_theme -bg_color $::lumen::C(bg)

# 0.44.0: the tank-empty page. standard_includes.tcl (sourced above)
# declares `tankempty refill` on the default skin's cracked-earth
# fill_tank.jpg with its own text and buttons; dui refuses a second
# declaration of an existing page, so the pair is deleted first (dui's
# own `page delete`, which drops the items and the page data) and
# re-added on Lumen's baked image. build_message_page redraws the
# content: the stock tap zones verbatim, Lumen type on top. Neither page
# can be current while the skin loads, so the delete never refuses.
if { [catch { dui page delete [list tankempty refill] } err] } {
    msg -ERROR "Lumen: could not remove the stock tank-empty pages: $err"
}
if { [catch {
    dui page add [list tankempty refill] {*}[::lumen::_page_bg_args lumen_message]
} err] } {
    msg -ERROR "Lumen: could not declare the tank-empty page: $err"
}

.can configure -bg $::lumen::C(bg)

#############################################################################
#  Home page ("off")
#############################################################################

proc ::lumen::build_home {} {
    variable C
    variable L
    set p "off"

    # The 0.17 action rail (Espresso/Steam/Water/Flush buttons) is gone:
    # those duplicated the machine's own GHC controls and the width was
    # needed for the next-shot steppers. Settings and Sleep -- which must
    # stay reachable or the skin is a dead end -- moved into the 2x2 action
    # grid in the next-shot strip.

    ####################################################################
    #  Taskbar (0.31.0 geometry + time; 0.32.0 tappables + dot)
    #
    #  Sits naked on the baked gradient -- no glass pill, so the bar
    #  bakes nothing. 0.57.0 (owner's mockup): Sleep (moon) ALONE at
    #  the far left, where a stray tap finds nothing else; the clock on
    #  two rows (time over date) with the water reading beside it; the
    #  three favorite slots as NAMES across the middle; the other four
    #  tappables closed up at the right edge in escalating consequence
    #  toward the corner: Drink Menu (mug, 0.40.0), maintenance (wrench,
    #  with the amber/red state dot), Lumen settings (gear), the Decent
    #  app (drawn DE1 side view, 0.42.0). The 0.34.0 wordmark is gone.
    #
    #  Icon glyphs come from the app's own FA6 Pro font (F(symbol), the
    #  scale_bt precedent), as [format %c ...] escapes -- never literal
    #  UTF-8 (mangling trap). If the font failed to register, short
    #  letter labels stand in so nothing renders as a tofu box.
    ####################################################################
    set bar_mid [expr {$L(bar_y) + $L(bar_h) / 2.0}]
    var $p $L(bar_time_x) $L(bar_time_y) {[::lumen::data::bar_time]} \
        -font $L(font_data) -fill $C(ink) -anchor w -justify left
    var $p $L(bar_day_x) $L(bar_day_y) {[::lumen::data::bar_day]} \
        -font $L(font_caption) -fill $C(ink_3) -anchor w -justify left

    # 0.34.0: the water readout, moved here from the last-shot card's
    # corner -- machine status belongs on the status bar. Same accessor,
    # same blue, blank when the machine has not reported recently.
    # 0.57.0: on the time's row, anchored w after the widest time.
    var $p $L(bar_water_x) $L(bar_time_y) {[::lumen::data::water_ml]} \
        -font $L(font_data) -fill $C(c_flow) -anchor w -justify left
    # 0.43.1: the same value in amber when the tank runs low.
    var $p $L(bar_water_x) $L(bar_time_y) {[::lumen::data::water_ml_low]} \
        -font $L(font_data) -fill $C(warn) -anchor w -justify left

    set sym_ok [_font_family_ok symbol]
    set bar_font [expr {$sym_ok ? $L(font_bt) : $L(font_label)}]
    foreach {xkey glyph fallback action label} [list \
        bar_drinkmenu_x 0xF7B6 "CUP" {::lumen::act::open_drinkmenu}  "Drink menu" \
        bar_wrench_x  0xF0AD "MNT" {::lumen::act::open_maintenance}  "Maintenance" \
        bar_gear_x    0xF013 "SET" {::lumen::act::open_settings}     "Settings" \
        bar_moon_x    0xF186 "ZZZ" {start_sleep}                     "Sleep" ] {
        set ix $L($xkey)
        txt $p [expr {$ix + $L(bar_icon_w) / 2.0}] $bar_mid \
            [expr {$sym_ok ? [format %c $glyph] : $fallback}] \
            -font $bar_font -fill $C(ink_2) -anchor center -justify center
        tap $p $ix $L(bar_y) $L(bar_icon_w) $L(bar_h) $action $label
    }

    # 0.53.0: the three favorite profile slots; 0.57.0: NAMES, not
    # digits. Per slot, bottom to top: the halo photo (blank until the
    # slot's profile is the loaded one, see _fav_glow_sync), then three
    # stacked fixed-ink items -- a dim mono "+" when empty, the title in
    # the icons' grey when set, the title in crema when active -- all
    # centred on the slot, and one zone; a tap on an empty slot stores
    # the loaded profile, on a set slot loads it. The halo is painted
    # once here from the palette (apply_theme repaints it); without Tk
    # or a screen size the slots go without it.
    set glow_ok 0
    if { [info commands image] ne "" } {
        if { [catch {
            set ::lumen::fav_glow_img [fav_glow_photo]
            set ::lumen::fav_glow_blank [image create photo -width 1 -height 1]
            set glow_ok 1
        } err] } {
            msg -NOTICE "Lumen: no halo behind the active favorite slot: $err"
        }
    }
    set glow_dx [expr {($L(bar_fav_w) - $L(bar_fav_glow_w)) / 2.0}]
    foreach fx $L(bar_fav_x) n {1 2 3} {
        set fcx [expr {$fx + $L(bar_fav_w) / 2.0}]
        if { $glow_ok } {
            uplevel #0 [list dui add canvas_item image $p \
                [X [expr {$fx + $glow_dx}]] [Y $L(bar_y)] \
                -image $::lumen::fav_glow_blank -anchor nw \
                -tags [_tags "" "" [list lumen_favglow_$n]]]
        }
        foreach {code col font} [list \
            "\[::lumen::data::fav_empty $n\]"  $C(ink_3) $L(font_data) \
            "\[::lumen::data::fav_set $n\]"    $C(ink_2) $L(font_caption) \
            "\[::lumen::data::fav_active $n\]" $C(crema) $L(font_caption)] {
            var $p $fcx $bar_mid $code \
                -font $font -fill $col -anchor center -justify center
        }
        # 0.57.3: no press flash -- the halo itself is the tap's answer
        # (style none still clears any previous flash).
        tap $p $fx $L(bar_y) $L(bar_fav_w) $L(bar_h) \
            [list ::lumen::act::fav_tap $n] "Favorite $n" none
    }

    # 0.42.0: the Decent app slot -- a drawn icon, not a glyph, so it
    # sits outside the foreach. Same ink, same zone, one tap to the
    # stock settings (reversing 0.41.0's two-tap DECENT APP row).
    draw_de1_icon $p [expr {$L(bar_de1_x) + $L(bar_icon_w) / 2.0}] \
        $bar_mid 26 $C(ink_2)
    tap $p $L(bar_de1_x) $L(bar_y) $L(bar_icon_w) $L(bar_h) \
        {::lumen::act::open_app_settings} "Decent app"

    # Maintenance state dot: two stacked fixed-colour items, the glyph
    # moves between them (settings mode-line pattern; a canvas item's
    # -fill is fixed at creation). Both blank when all is well, when the
    # plugin is absent, or when anything about the read is off.
    var $p $L(bar_dot_x) $L(bar_dot_y) {[::lumen::data::maint_dot_amber]} \
        -font $L(font_caption) -fill $C(warn) -anchor center -justify center
    var $p $L(bar_dot_x) $L(bar_dot_y) {[::lumen::data::maint_dot_red]} \
        -font $L(font_caption) -fill $C(danger) -anchor center -justify center

    ####################################################################
    #  Grind recommendation tile  ->  GrindAdvisor result popup
    ####################################################################
    glass $p $L(grind_x) $L(grind_y) $L(grind_w) $L(grind_h) \
        -fill $C(glass) -outline $C(crema_brd)

    set gx [expr {$L(grind_x) + $L(pad_x)}]
    set gy [expr {$L(grind_y) + $L(pad_y)}]

    # 0.38.0: the header is live -- "STARTING ESTIMATE" when the tile shows
    # GrindAdvisor 3.13.0's new-bag estimate, because the plugin's display
    # contract forbids captioning an estimate "Recommended". Same position,
    # font and ink as the static label it replaces (both texts are 17 chars).
    var $p $gx $gy {[::lumen::data::grind_header]} \
        -font $L(font_label) -fill $C(ink_3)

    # Vertical budget inside the 190-tall tile (0.23.0; content 36..192):
    #   label 36..51   hero 56..140   note 142..161   row 176..192
    # 14 clear to the tile edge at 206.
    # Hero and note are CENTRED on the tile (owner request); the delta sits
    # to the right of the widest hero the grind range allows ("50.0" is
    # ~101px half-width at the 84px mono size, so +120 clears it).
    set gmid [expr {$L(grind_x) + $L(grind_w) / 2.0}]
    var $p $gmid [expr {$gy + 20}] {[::lumen::data::grind_next]} \
        -font $L(font_hero) -fill $C(crema) -anchor n -justify center
    # 0.43.1: the delta in the secondary ink, not green -- it is a
    # direction, not a verdict.
    var $p [expr {$gmid + 120}] [expr {$gy + 60}] {[::lumen::data::grind_delta]} \
        -font $L(font_primary) -fill $C(ink_2)

    var $p $gmid [expr {$gy + 106}] {[::lumen::data::grind_note]} \
        -font $L(font_body) -fill $C(ink_2) -width 560 \
        -anchor n -justify center

    # Method chip, top right. Blank until there is a recommendation.
    set mchip_x [expr {$L(grind_x) + $L(grind_w) - $L(pad_x) - 150}]
    glass $p $mchip_x $gy 150 26 -radius 13 \
        -fill $C(crema_lo) -outline $C(crema_brd) -spec 0
    var $p [expr {$mchip_x + 75}] [expr {$gy + 13}] {[::lumen::data::grind_method]} \
        -font $L(font_label) -fill $C(crema) -anchor center -justify center

    # Confidence band: three stacked items, coloured by what it says.
    # 0.56.1: the whole bottom row sits on L(hist_y), the same row the
    # last-shot tile uses, so the two tiles' footers line up (they were
    # 4 px apart: gy + 140 = 224 against 220).
    foreach {code col} [list \
        {[::lumen::data::grind_band_good]}    $C(good) \
        {[::lumen::data::grind_band_poor]}    $C(warn) \
        {[::lumen::data::grind_band_neutral]} $C(ink_2)] {
        var $p $gx $L(hist_y) $code -font $L(font_caption) -fill $col
    }

    txt $p [expr {$L(grind_x) + $L(grind_w) - $L(pad_x)}] \
        $L(hist_y) \
        [translate "Shot analysis"] -font $L(font_caption) -fill $C(crema) \
        -anchor ne -justify right

    # "Curve" sits on the same baseline as "Shot analysis", one lg gap to its
    # left, and opens GrindAdvisor's calibration plot directly.
    set gcv_r [expr {$L(grind_x) + $L(grind_w) - $L(pad_x) - 130}]
    txt $p $gcv_r $L(hist_y) \
        [translate "Curve"] -font $L(font_caption) -fill $C(crema) \
        -anchor ne -justify right

    # The tile tap is carved into three rectangles around the Curve target,
    # so no two tap targets overlap (design-system rule).
    #   A: everything above the bottom row
    #   B: bottom row, left of Curve      C: bottom row, right of Curve
    # 0.36.0 (owner request): the CARD (zones A and B) opens Grind
    # Advisor's SETTINGS -- the same open_grind_advisor the Lumen
    # settings page's GRIND ADVISOR row used to call (that row is gone).
    # Zone C keeps the "Shot analysis" result popup, whose text link
    # lives inside it, and Curve is unchanged.
    set gcv_x [expr {$gcv_r - 84}]                  ;# Curve tap left edge
    set gcv_y [expr {$L(grind_y) + $L(grind_h) - 62}]
    set gcv_w 90
    set gcv_h 62

    # Flash styles (0.37.0): the two card-body zones ring the CARD, the
    # two text links get label-fitted chips.
    set card_ring [list ring $L(grind_x) $L(grind_y) $L(grind_w) $L(grind_h)]
    tap $p $L(grind_x) $L(grind_y) $L(grind_w) \
        [expr {$gcv_y - $L(grind_y) - $L(xs)}] \
        {::lumen::act::open_grind_advisor} "Grind Advisor" $card_ring
    tap $p $L(grind_x) $gcv_y [expr {$gcv_x - $L(grind_x)}] $gcv_h \
        {::lumen::act::open_grind_advisor} "Grind Advisor" $card_ring
    tap $p [expr {$gcv_x + $gcv_w}] $gcv_y \
        [expr {$L(grind_x) + $L(grind_w) - $gcv_x - $gcv_w}] $gcv_h \
        {::lumen::act::grind_popup} "Shot analysis" label

    tap $p $gcv_x $gcv_y $gcv_w $gcv_h {::lumen::act::grind_curve} "Curve" label

    ####################################################################
    #  Last shot tile
    ####################################################################
    glass $p $L(last_x) $L(last_y) $L(last_w) $L(last_h)

    # 0.23.0: identity on the left, metrics on the right, in the SAME row
    # order as the next-shot card -- LABEL, PROFILE, roaster, bean type --
    # so the two cards read as a pair.
    set lx $L(last_id_x)

    txt $p $lx $L(last_label_y) [translate "LAST SHOT"] \
        -font $L(font_label) -fill $C(ink_3)

    # The profile that shot ran on. Directly under the card label, matching
    # the next-shot card, so the two profiles can be read against each other:
    # when they differ, Grind Advisor has started a fresh calibration.
    txt $p $lx $L(last_prof_y) [translate "PROFILE"] \
        -font $L(font_label) -fill $C(ink_3)
    var $p $L(last_val_x) $L(last_prof_y) {[::lumen::data::last_profile]} \
        -font $L(font_caption) -fill $C(ink_2) -width 190

    var $p $lx $L(last_roast_y) {[::lumen::data::last_roaster_line]} \
        -font $L(font_caption) -fill $C(ink_3) -width $L(last_id_w)
    var $p $lx $L(last_name_y) {[::lumen::data::last_name_line]} \
        -font $L(font_primary) -fill $C(ink) -width $L(last_id_w)

    # (0.34.0: the water readout moved from this corner to the taskbar.)

    # Metrics: GRIND joins dose/yield/time (0.23.0), with the derived ratio
    # tucked under YIELD exactly as the next-shot card does it.
    set i 0
    foreach {k code} [list \
        [translate "GRIND"] {[::lumen::data::last_grind]} \
        [translate "DOSE"]  {[::lumen::data::last_dose]} \
        [translate "YIELD"] {[::lumen::data::last_yield]} \
        [translate "TIME"]  {[::lumen::data::last_time]} ] {
        set cx [expr {$L(last_met_x) + $i * $L(last_met_pitch)}]
        txt $p $cx $L(last_met_label_y) $k -font $L(font_label) -fill $C(ink_3)
        var $p $cx $L(last_met_val_y) $code -font $L(font_section) -fill $C(ink)
        if { $k eq [translate "YIELD"] } {
            var $p $cx $L(last_met_sub_y) {[::lumen::data::last_ratio_note]} \
                -font $L(font_caption) -fill $C(ink_3)
        }
        incr i
    }

    # --- Shot history: a text link on the tile's bottom row, matching Curve
    # and Shot analysis on the grind tile. It was the only button on this
    # card, which gave it more weight than a history shortcut deserves.
    set lh_r [expr {$L(last_x) + $L(last_w) - $L(pad_x)}]
    txt $p $lh_r $L(hist_y) [translate "Shot history"] \
        -font $L(font_caption) -fill $C(crema) -anchor ne -justify right
    tap $p [expr {$lh_r - 150}] [expr {$L(hist_y) - 8}] 150 40 \
        {::lumen::act::shot_history} "Shot history" label

    # 0.43.1: WHEN the shot was pulled, on the same bottom row at the
    # card's left edge -- the card can now legitimately describe a shot
    # from days ago (a bag with only a cleaning run since, or a fresh bag
    # showing the previous bag's last shot), and it never said so. Widest
    # string "Wed 12 Sep 12:40 PM" is ~150 px at the caption size, ending
    # near 860; the Shot history zone starts at 1150.
    var $p $lx $L(hist_y) {[::lumen::data::last_shot_when]} \
        -font $L(font_caption) -fill $C(ink_3)

    ####################################################################
    #  Shot chart   (real graph widget added in Pass 3)
    ####################################################################
    glass $p $L(chart_x) $L(chart_y) $L(chart_w) $L(chart_h)

    set cx [expr {$L(chart_x) + $L(pad_x)}]
    set cy [expr {$L(chart_y) + $L(md)}]

    # 0.43.1: each legend entry carries the shot's final value with its
    # unit ("Weight 38.0 g", "Temp 93.2 C"), so the shared 0..10 axis is
    # readable -- 9.3 on the temperature line is 93 degrees, 3.8 on the
    # weight line is 38 g. Plain words until there is a shot. Pitch 170
    # (was 110) for the longer strings; 4 x 170 = 680 of the 1260 inside.
    set i 0
    foreach {code col} [list \
        {[::lumen::data::legend_pressure]} $C(c_press) \
        {[::lumen::data::legend_flow]}     $C(c_flow) \
        {[::lumen::data::legend_weight]}   $C(c_weight) \
        {[::lumen::data::legend_temp]}     $C(c_temp) ] {
        var $p [expr {$cx + $i * 170}] $cy $code \
            -font $L(font_caption) -fill $col
        incr i
    }

    # 0.36.0 (owner request): the Raw/Smooth and Stages pills are gone --
    # the chart is always smooth with stage separators shown. The pills
    # were also removed from the baked background (make_backgrounds.py).

    # The graph widget itself, below the legend row.
    set cgx [expr {$L(chart_x) + $L(pad_x)}]
    set cgy [expr {$L(chart_y) + 52}]
    set cgw [expr {$L(chart_w) - 2 * $L(pad_x)}]
    set cgh [expr {$L(chart_h) - 52 - $L(md)}]

    if { [catch {
        set gw [dui add graph $p [X $cgx] [Y $cgy] \
            -width [X $cgw] -height [Y $cgh] \
            -background $C(chart_bg) -plotbackground $C(chart_bg) \
            -borderwidth 0 -plotrelief flat -relief flat \
            -plotpadx 18 -plotpady 8 \
            -tclcode {::lumen::chart_setup %W}]
        # 0.47.0: remembered so a live retheme can restyle it.
        if { $gw ne "" } { lappend ::lumen::charts $gw chart_bg }
    } err] } {
        msg -ERROR "Lumen: could not create the shot chart: $err"
    }

    # Sits over the plot area and blanks itself as soon as there is data.
    var $p [expr {$L(chart_x) + $L(chart_w) / 2.0}] \
        [expr {$L(chart_y) + $L(chart_h) / 2.0}] \
        {[::lumen::data::chart_empty_note]} \
        -font $L(font_body) -fill $C(ink_3) -anchor center -justify center

    ####################################################################
    #  Next shot / bean strip   (data wired in Pass 2)
    ####################################################################
    glass $p $L(bean_x) $L(bean_y) $L(bean_w) $L(bean_h)

    set bx2 [expr {$L(bean_x) + $L(pad_x)}]
    set by2 [expr {$L(bean_y) + $L(pad_y)}]

    set bx2 $L(bean_id_x)
    set by2 [expr {$L(bean_y) + $L(pad_y)}]

    # 0.35.0 identity block: NEXT SHOT on its own line, PROFILE on the
    # row beneath it -- the LAST SHOT card's exact stacked order (owner
    # request; the two cards read as a pair again). The dedicated row
    # also gives the profile value the block's full width instead of the
    # 255 it had sharing the label row.
    txt $p $bx2 $L(id_label_y) [translate "NEXT SHOT"] \
        -font $L(font_label) -fill $C(ink_3)
    txt $p $L(id_prof_x) $L(id_prof_y) [translate "PROFILE"] \
        -font $L(font_label) -fill $C(ink_3)
    var $p $L(id_val_x) $L(id_prof_y) {[::lumen::data::next_profile]} \
        -font $L(font_caption) -fill $C(ink_2) -width $L(id_val_w)
    # The profile chooser tap (0.33.0, moved with the row in 0.35.0):
    # same open_profiles the old side-panel button called.
    tap $p $L(id_prof_tap_x) $L(id_prof_tap_y) $L(id_prof_tap_w) $L(id_prof_tap_h) \
        {::lumen::act::open_profiles} "Profile" label

    var $p $bx2 $L(id_roast_y) {[::lumen::data::bean_roaster_line]} \
        -font $L(font_caption) -fill $C(ink_3) -width $L(bean_id_w)

    # --- the bag name, on a row of its own with the block's full width.
    var $p $L(id_name_x) $L(id_name_y) {[::lumen::data::bean_name_line]} \
        -font $L(font_title) -fill $C(ink) -width $L(id_name_w)

    # Tasting notes. Blank when the field is unset, so the row costs nothing
    # on a bag that has none.
    var $p $bx2 $L(id_notes_y) {[::lumen::data::bean_notes_line]} \
        -font $L(font_caption) -fill $C(ink_2) -width $L(bean_id_w)

    # --- action row: [<] [Edit] [>], then the cycler's page indicator. The
    # arrows shrank to a stepper pill's size (owner request); the 150px that
    # frees is what the indicator sits in.
    foreach ax [list $L(cyc_prev_x) $L(cyc_next_x)] \
            glyph [list [format %c 0x25C0] [format %c 0x25B6]] \
            dir {-1 1} \
            lbl {"Previous bag" "Next bag"} {
        glass $p $ax $L(cyc_y) $L(cyc_w) $L(cyc_h) \
            -radius $L(radius_sm) -spec 0
        # Arrow glyphs via [format %c ...] -- the proven pattern; a literal
        # UTF-8 arrow in the source got mangled once already (Grind Advisor
        # v2.0.2 lesson) and there is no ASCII arrow that reads as one.
        txt $p [expr {$ax + $L(cyc_w) / 2.0}] \
            [expr {$L(cyc_y) + $L(cyc_h) / 2.0}] $glyph \
            -font $L(font_caption) -fill $C(crema) \
            -anchor center -justify center
        tap $p $ax $L(cyc_y) $L(cyc_w) $L(cyc_h) \
            "::lumen::act::cycle_bag $dir" $lbl
    }

    glass $p $L(id_edit_x) $L(id_act_y) $L(id_edit_w) $L(id_edit_h) \
        -radius $L(radius_sm) -spec 0
    txt $p [expr {$L(id_edit_x) + $L(id_edit_w) / 2.0}] \
        [expr {$L(id_act_y) + $L(id_edit_h) / 2.0}] \
        [translate "Edit"] -font $L(font_button) -fill $C(ink_2) \
        -anchor center -justify center
    tap $p $L(id_edit_x) $L(id_act_y) $L(id_edit_w) $L(id_edit_h) \
        {::lumen::act::dye_next} "Edit"

    # One dot per reachable bag, filled for the loaded one, leftmost being
    # the most recent -- which is the direction the left arrow moves in. The
    # cycler does not wrap any more, so the dots also say when you have run
    # out of bags in one direction (owner request).
    var $p $L(bag_dots_x) $L(bag_dots_y) {[::lumen::data::bag_dots]} \
        -font $L(font_caption) -fill $C(crema) -anchor center -justify center

    # --- three Streamline-style stepper groups: label above, then
    # [-]  value  [+] with the live value BETWEEN the pills. ASCII glyphs
    # only (design rule); the mono face renders them cleanly.
    #
    # 0.21.0: RATIO lost its stepper. Nothing is actually lost -- ratio is
    # fully DERIVED from dose and yield, so it is a caption under the YIELD
    # value instead of a control of its own. It sits INSIDE the pill band,
    # not under it: the strip's bottom row leaves no room between them.
    #
    # 0.23.0: PROFILE left this row for the identity block, so three columns
    # now span 520..1116 on a 210 pitch instead of four on a 206 pitch.
    set i 0
    foreach {k code minus_code plus_code what} [list \
        [translate "GRIND"]  {[::lumen::data::next_grind]} \
            {::lumen::act::adjust_grind -0.1} {::lumen::act::adjust_grind 0.1} "Grind" \
        [translate "DOSE"]   {[::lumen::data::next_dose]} \
            {::lumen::act::adjust_dose -0.1}  {::lumen::act::adjust_dose 0.1}  "Dose" \
        [translate "YIELD"]  {[::lumen::data::next_yield]} \
            {::lumen::act::adjust_yield -0.1} {::lumen::act::adjust_yield 0.1} "Yield" ] {
        set kx [expr {$L(bean_fact_x) + $i * $L(bean_fact_w)}]
        txt $p $kx $by2 $k -font $L(font_label) -fill $C(ink_3)

        set mx $kx
        set px2 [expr {$kx + $L(step_w) + $L(step_gap) + $L(step_val_w) + $L(step_gap)}]
        set mid_y [expr {$L(step_y) + $L(step_h) / 2.0}]

        foreach sx [list $mx $px2] glyph [list "-" "+"] \
                scode [list $minus_code $plus_code] \
                lbl [list "$what down" "$what up"] {
            glass $p $sx $L(step_y) $L(step_w) $L(step_h) \
                -radius $L(radius_sm) -spec 0
            txt $p [expr {$sx + $L(step_w) / 2.0}] \
                [expr {$mid_y + ($glyph eq "-" ? $L(step_minus_dy) : 0)}] $glyph \
                -font $L(font_section) -fill $C(crema) \
                -anchor center -justify center
            tap $p $sx $L(step_y) $L(step_w) $L(step_h) $scode $lbl
        }

        # The value, centred between the pills. YIELD carries the derived
        # ratio beneath it, so its value shifts up to make room and the two
        # lines share the pill band (the reference the owner supplied:
        # "36g" with "(1:2.4)" tucked under it).
        set vx [expr {$kx + $L(step_w) + $L(step_gap) + $L(step_val_w) / 2.0}]
        if { $what eq "Yield" } {
            var $p $vx [expr {$L(step_y) + 16}] $code \
                -font $L(font_data) -fill $C(ink) \
                -anchor center -justify center
            var $p $vx [expr {$L(step_y) + 38}] \
                {[::lumen::data::next_ratio_note]} \
                -font $L(font_caption) -fill $C(ink_3) \
                -anchor center -justify center
        } else {
            var $p $vx $mid_y $code -font $L(font_data) -fill $C(ink) \
                -anchor center -justify center
        }

        incr i
    }

    # --- scale row, under the stepper groups: live readout, then Set dose
    # aligned under the DOSE group (these belong with the NEXT shot).
    set mid [expr {$L(scale_y) + $L(scale_h) / 2.0}]
    glass $p $L(scale_read_x) $L(scale_y) $L(scale_read_w) $L(scale_h) \
        -radius $L(radius_sm) -spec 0
    var $p [expr {$L(scale_read_x) + 22}] $mid {[::lumen::data::scale_bt]} \
        -font $L(font_bt) -fill $C(c_flow) -anchor center -justify center
    # Centred on the box, not nudged clear of the icon: the icon is only
    # there when a scale is connected, so the nudge threw "no scale" off
    # centre exactly when it was the only thing showing.
    var $p [expr {$L(scale_read_x) + $L(scale_read_w) / 2.0}] $mid \
        {[::lumen::data::scale_weight_line]} \
        -font $L(font_data) -fill $C(ink_2) -anchor center -justify center
    # The readout was a dead zone. Tapping it forces a scale reconnect --
    # the affordance every other skin puts on its weight display, and the
    # only way back once the core has spent its automatic retries.
    tap $p $L(scale_read_x) $L(scale_y) $L(scale_read_w) $L(scale_h) \
        {::lumen::act::reconnect_scale} "Scale"

    glass $p $L(scale_set_x) $L(scale_y) $L(scale_set_w) $L(scale_h) \
        -radius $L(radius_sm) -fill $C(crema_lo) -outline $C(crema_brd)
    txt $p [expr {$L(scale_set_x) + $L(scale_set_w) / 2.0}] $mid \
        [translate "Set dose"] \
        -font $L(font_button) -fill $C(crema) -anchor center -justify center
    tap $p $L(scale_set_x) $L(scale_y) $L(scale_set_w) $L(scale_h) \
        {::lumen::act::set_dose_from_scale} "Set dose"

    # --- Scan bag completes the bottom row, under the YIELD group.
    #
    # 0.23.0: Edit left this row for the identity block, where it sits with
    # the bag it edits. The identity block no longer carries a full-height
    # DYE tap either -- with the cycler arrows and Edit both on its action
    # row, a block-wide tap would have overlapped them, and a tap target may
    # never overlap another (design-system rule). Edit is the one way in,
    # which is clearer than a large invisible region that did the same thing.
    glass $p $L(act_scan_x) $L(scale_y) $L(act_w) $L(act_h) \
        -radius $L(radius_sm) -fill $C(crema_lo) -outline $C(crema_brd)
    txt $p [expr {$L(act_scan_x) + $L(act_w) / 2.0}] \
        [expr {$L(scale_y) + $L(act_h) / 2.0}] \
        [translate "Scan bag"] -font $L(font_button) -fill $C(crema) \
        -anchor center -justify center
    tap $p $L(act_scan_x) $L(scale_y) $L(act_w) $L(act_h) \
        {::lumen::act::scan_bag} "Scan bag"

    # 0.33.0: the side panel is gone. Settings and Sleep are on the
    # taskbar (tablet-verified in 0.32.0 before the panel was removed --
    # the skin was never left without a way back to the skin picker), and
    # Profile is the tap on the identity row's PROFILE value above.
}

#############################################################################
#  Flow pages: espresso, steam, water, flush
#
#  These pages exist because the machine switches to them on its own during a
#  shot. The stock skin puts all of their content INSIDE its background JPGs
#  (espresso_on.png and friends); since Lumen declares its pages with a
#  background colour instead, that content has to be drawn here. Without it
#  the tablet shows a blank screen for the whole shot.
#############################################################################

proc ::lumen::build_flow_page { page timer_code temp_code {with_chart 0} {temp_label "TEMP"} {temp_note_code ""} {weight_note_code ""} } {
    variable C
    variable L

    # The espresso page uses a compact layout so a live chart fits above the
    # metrics; steam, water and flush keep the roomier one.
    if { $with_chart } {
        set state_y $L(fc_state_y) ; set timer_y $L(fc_timer_y)
        set panel_x $L(fc_panel_x) ; set panel_y $L(fc_panel_y)
        set panel_w $L(fc_panel_w) ; set panel_h $L(fc_panel_h)
        set hint_y  $L(fc_hint_y)
    } else {
        set state_y $L(flow_state_y) ; set timer_y $L(flow_timer_y)
        set panel_x $L(flow_panel_x) ; set panel_y $L(flow_panel_y)
        set panel_w $L(flow_panel_w) ; set panel_h $L(flow_panel_h)
        set hint_y  $L(flow_hint_y)
    }

    # What the machine is doing right now.
    var $page $L(center_x) $state_y {[translate [de1_substate_text]]} \
        -font $L(font_title) -fill $C(ink) -anchor n -justify center \
        -width $panel_w

    # Elapsed time, the thing you actually watch.
    var $page $L(center_x) $timer_y $timer_code \
        -font $L(font_hero) -fill $C(crema) -anchor n -justify center

    # Live curves, drawn as the shot runs. Same vectors and the same
    # smoothing setting as the home chart; the toggle drives both.
    if { $with_chart } {
        glass $page $L(fc_chart_x) $L(fc_chart_y) $L(fc_chart_w) $L(fc_chart_h)
        set gx [expr {$L(fc_chart_x) + $L(pad_x)}]
        set gy [expr {$L(fc_chart_y) + $L(md)}]
        set gw [expr {$L(fc_chart_w) - 2 * $L(pad_x)}]
        set gh [expr {$L(fc_chart_h) - 2 * $L(md)}]
        if { [catch {
            set gwidget [dui add graph $page [X $gx] [Y $gy] \
                -width [X $gw] -height [Y $gh] \
                -background $C(chart_bg_flow) -plotbackground $C(chart_bg_flow) \
                -borderwidth 0 -plotrelief flat -relief flat \
                -plotpadx 18 -plotpady 8 \
                -tclcode {::lumen::chart_setup %W}]
            if { $gwidget ne "" } { lappend ::lumen::charts $gwidget chart_bg_flow }
        } err] } {
            msg -ERROR "Lumen: could not create the live chart on $page: $err"
        }
    }

    glass $page $panel_x $panel_y $panel_w $panel_h

    set px [expr {$panel_x + $L(pad_x)}]
    set cw [expr {($panel_w - 2 * $L(pad_x)) / 4.0}]

    set i 0
    foreach {label code colour} [list \
        [translate "PRESSURE"]   {[pressure_text]}              $C(c_press) \
        [translate "FLOW"]       {[waterflow_text]}             $C(c_flow) \
        [translate "WEIGHT"]     {[::lumen::data::live_weight]} $C(c_weight) \
        [translate $temp_label]  $temp_code                     $C(c_temp) ] {
        set cx [expr {$px + $i * $cw}]
        txt $page $cx [expr {$panel_y + 30}] $label \
            -font $L(font_label) -fill $C(ink_3)
        var $page $cx [expr {$panel_y + 66}] $code \
            -font $L(font_metric) -fill $colour
        incr i
    }

    # Optional caption under the temperature value (the steam page states
    # its set point there, so the heater reading reads as intentional).
    if { $temp_note_code ne "" } {
        var $page [expr {$px + 3 * $cw}] [expr {$panel_y + 112}] \
            $temp_note_code -font $L(font_caption) -fill $C(ink_3)
    }
    # 0.43.1: the same caption slot under WEIGHT, for the espresso page's
    # target ("of 38.0 g") -- the number you are pouring towards.
    if { $weight_note_code ne "" } {
        var $page [expr {$px + 2 * $cw}] [expr {$panel_y + 112}] \
            $weight_note_code -font $L(font_caption) -fill $C(ink_3)
    }

    txt $page $L(center_x) $hint_y \
        [translate "Tap anywhere to stop"] \
        -font $L(font_body) -fill $C(ink_3) -anchor n -justify center
}

#############################################################################
#  Tank-empty page (0.44.0)
#
#  The machine switches to `tankempty` on its own (gui.tcl: state Refill).
#  Content and tap zones follow skins/default/standard_includes.tcl's
#  "out of water page" block exactly -- the same three zones with the same
#  commands (retry = start_refill_kit over the top 1400 virtual px; Exit
#  App bottom-left through the stock message page + app_exit; Ok
#  bottom-right = start_refill_kit) -- with Lumen's type and the live tank
#  reading so you can watch the level rise as you pour.
#############################################################################

proc ::lumen::build_message_page {} {
    variable C
    variable L
    set pages [list tankempty refill]

    foreach p $pages {
        txt $p $L(center_x) $L(msg_title_y) [translate "Please add water"] \
            -font $L(font_title) -fill $C(ink) -anchor n -justify center
        txt $p $L(center_x) $L(msg_body_y) \
            [translate "The tank is empty. Fill it and the machine carries on where it left off."] \
            -font $L(font_body) -fill $C(ink_2) -anchor n -justify center \
            -width [expr {$L(msg_panel_w) - 2 * $L(xl)}]
        # The core's own retry hint ("Touch screen to retry" once the
        # machine reports a substate), exactly as the stock page shows it.
        var $p $L(center_x) $L(msg_retry_y) {[refill_kit_retry_button]} \
            -font $L(font_body) -fill $C(crema) -anchor n -justify center
        # Live tank level, the taskbar's two stacked items (blue / amber).
        var $p $L(center_x) $L(msg_water_y) {[::lumen::data::water_ml]} \
            -font $L(font_data) -fill $C(c_flow) -anchor n -justify center
        var $p $L(center_x) $L(msg_water_y) {[::lumen::data::water_ml_low]} \
            -font $L(font_data) -fill $C(warn) -anchor n -justify center
    }

    # Button labels. Exit App exists on tankempty only (as in the stock
    # file); Ok on both.
    txt tankempty [expr {$L(msg_exit_x) + $L(msg_btn_w) / 2.0}] \
        [expr {$L(msg_btn_y) + $L(msg_btn_h) / 2.0}] [translate "Exit App"] \
        -font $L(font_button) -fill $C(ink_2) -anchor center -justify center
    foreach p $pages {
        txt $p [expr {$L(msg_ok_x) + $L(msg_btn_w) / 2.0}] \
            [expr {$L(msg_btn_y) + $L(msg_btn_h) / 2.0}] [translate "Ok"] \
            -font $L(font_button) -fill $C(crema) -anchor center -justify center
    }

    # The three stock zones, VERBATIM from standard_includes.tcl (virtual
    # coordinates as written there), each with a press flash in front: the
    # retry zone rings the message panel (the grind-card style -- a filled
    # chip over 1400 virtual px would flood the screen), the two corner
    # buttons get label-fitted chips.
    set ring [list ring $L(msg_panel_x) $L(msg_panel_y) $L(msg_panel_w) $L(msg_panel_h)]
    add_de1_button "tankempty refill" "::lumen::press_flash 0 0 2560 1400 [list $ring]; say \[translate {awake}\] \$::settings(sound_button_in);start_refill_kit" 0 0 2560 1400
    add_de1_button "tankempty" {::lumen::press_flash 0 1402 800 1600 label; say [translate {Exit}] $::settings(sound_button_in); .can itemconfigure $::message_label -text [translate "Going to sleep"]; .can itemconfigure $::message_button_label -text [translate "Wait"]; after 10000 {.can itemconfigure $::message_button_label -text [translate "Ok"]; }; set_next_page off message; page_show message; after 500 app_exit} 0 1402 800 1600
    add_de1_button "tankempty refill" {::lumen::press_flash 1760 1402 2560 1600 label; say [translate {awake}] $::settings(sound_button_in);start_refill_kit} 1760 1402 2560 1600
}

#############################################################################
#  Custom theme picker page (0.46.0)
#
#  lumen_theme, reached from the THEME row's caption. Never baked: the
#  rows are vector glass in the CURRENT theme, the PREVIEW column is
#  redrawn from the PENDING colours on every tap (canvas items carry a
#  role tag per palette token, and refresh_preview reconfigures them --
#  the retheme recipe MaintenanceTracker uses). Done saves the five
#  preferences and quits through the theme restart path; Cancel discards.
#############################################################################

# ---- the actions ----------------------------------------------------------

proc ::lumen::act::open_theme_picker {} {
    variable ::lumen::custom::pend
    # Seed the pending state from what is saved, so the preview opens on
    # the current custom colours (or the Lumen-dark defaults).
    set pr [::lumen::custom::prefs]
    foreach k {base bh bs ah as} { set pend($k) [dict get $pr $k] }
    # 0.56.0: the schedule's two times ride along.
    set pend(lf) [::lumen::auto_minutes light] ; set pend(df) [::lumen::auto_minutes dark]
    if { [catch { dui page load lumen_theme } err] } {
        msg -ERROR "Lumen: could not open the theme picker: $err"
        return
    }
    ::lumen::refresh_preview
}

# key: base | bh | ah. 0.51.0: a hue swatch carries its saturation too
# (bh -> bs, ah -> as).
proc ::lumen::act::theme_pick { key value {sat ""} } {
    variable ::lumen::custom::pend
    set pend($key) $value
    if { $sat ne "" && $key in {bh ah} } { set pend([string index $key 0]s) $sat }
    ::lumen::refresh_preview
}

proc ::lumen::act::theme_preset { i } {
    variable ::lumen::custom::pend
    variable ::lumen::custom::presets
    set p [lrange $presets [expr {$i * 6}] [expr {$i * 6 + 5}]]
    if { [llength $p] != 6 } { return }
    lassign $p - pend(base) pend(bh) pend(bs) pend(ah) pend(as)
    ::lumen::refresh_preview
}

proc ::lumen::act::theme_cancel {} {
    if { [catch { dui page load lumen_settings } err] } {
        msg -ERROR "Lumen: could not leave the theme picker: $err"
    }
}

# Done: persist the five preferences, then (0.47.0) apply the custom theme
# LIVE: the backgrounds are drawn if these colours have none yet, every
# page is recoloured in place, and the picker goes back to the settings
# page -- already in the new colours. Nothing to apply (already custom
# with the same colours) just goes back. The status line under the
# preview says what is happening while the tablet paints (a few seconds
# during which nothing else moves), and names the failure if it fails.
proc ::lumen::act::theme_apply {} {
    variable ::lumen::custom::pend
    set before [::lumen::custom::signature [::lumen::custom::prefs]]
    if { [catch {
        set ::settings(lumen_custom_base) $pend(base)
        foreach k {bh bs ah as} { set ::settings(lumen_custom_$k) $pend($k) }
        # 0.56.0: the schedule's times are picker state too.
        set ::settings(lumen_auto_light_from) [::lumen::pend_minutes light]
        set ::settings(lumen_auto_dark_from)  [::lumen::pend_minutes dark]
        save_settings
    } err] } {
        msg -ERROR "Lumen: could not save the custom theme: $err"
        return
    }
    set after [::lumen::custom::signature [::lumen::custom::prefs]]
    if { $::lumen::theme_mode eq "custom" && $before eq $after } {
        _bake_other_half
        theme_cancel
        return
    }
    ::lumen::theme_page_status [translate "Drawing your theme..."]
    if { ![::lumen::act::_switch_theme custom] } {
        ::lumen::theme_page_status [translate "Could not draw this theme. See the log."]
        return
    }
    _bake_other_half
    ::lumen::theme_page_status ""
    theme_cancel
}

# 0.56.0: with base auto, the half the schedule is NOT showing right now
# is drawn here too (a few seconds behind the status line), so the flip
# at the next boundary is a photo swap and never a bake on the home page.
# A failure only logs: the flip falls back to baking on its own.
proc ::lumen::act::_bake_other_half {} {
    set pr [::lumen::custom::prefs]
    if { [dict get $pr base] ne "auto" || $::lumen::_flat_pages } { return }
    set other [expr {[dict get $pr eff] eq "light" ? "dark" : "light"}]
    ::lumen::theme_page_status "[translate {Drawing the}] [translate $other] [translate {glass for later...}]"
    ::lumen::wait_show "[translate {Drawing the}] [translate $other] [translate {glass for later...}]"
    if { [catch { set ok [::lumen::custom::ensure_bake $other] } err] } { set ok 0 ; msg -ERROR "Lumen: other half bake threw: $err" }
    ::lumen::wait_hide
    if { !$ok } { msg -ERROR "Lumen: the $other half of the auto set could not be drawn now; it will be drawn at the first flip" }
}

# The picker's status line, repainted at once: the apply that follows is
# synchronous and the 200 ms variable tick never runs during it.
proc ::lumen::theme_page_status { text } {
    if { [catch {
        set can [dui canvas]
        $can itemconfigure lumen_th_status -text $text
        update idletasks
    } err] } {
        msg -DEBUG "Lumen: picker status line: $err"
    }
}

# ---- the page ------------------------------------------------------------

# Reconfigures every preview item from the pending colours. Items carry
# tags lumen_thp_<token> (fill) and lumen_tho_<token> (outline); the
# selection rings on the base pills, swatches and presets follow the
# pending state too.
proc ::lumen::refresh_preview {} {
    variable C
    variable ::lumen::custom::pend
    variable ::lumen::custom::presets
    if { [catch {
        set P [::lumen::custom::palette $pend(base) $pend(bh) $pend(bs) $pend(ah) $pend(as)]
        set can [dui canvas]
        foreach tok {bg glass glass_2 glass_brd ink ink_2 ink_3 crema crema_lo crema_brd good} {
            set v [dict get $P $tok]
            $can itemconfigure lumen_thp_$tok -fill $v
            $can itemconfigure lumen_tho_$tok -outline $v
        }
        # Base pills: the selected one takes the accent look (0.56.0: Auto
        # is a third base, one of the three is selected).
        foreach b {dark light auto} {
            set on [expr {$pend(base) eq $b}]
            $can itemconfigure lumen_thb_$b -fill [expr {$on ? $C(crema_lo) : $C(glass_2)}] \
                -outline [expr {$on ? $C(crema_brd) : $C(glass_brd)}]
            $can itemconfigure lumen_thbt_$b -fill [expr {$on ? $C(crema) : $C(ink_2)}]
        }
        # 0.51.0: a swatch is selected when BOTH its hue and saturation are
        # the pending ones (a preset's values may match none).
        foreach key {bh ah} {
            set sk [string index $key 0]s
            set i 0
            foreach sw [::lumen::custom::swatches $key] {
                lassign $sw h s
                set on [expr {$pend($key) == $h && $pend($sk) == $s}]
                $can itemconfigure lumen_ths_${key}_$i \
                    -outline [expr {$on ? $C(ink) : $C(glass_brd)}] -width [expr {$on ? 6 : 2}]
                incr i
            }
        }
        for { set i 0 } { $i < [llength $presets] / 6 } { incr i } {
            lassign [lrange $presets [expr {$i * 6 + 1}] [expr {$i * 6 + 5}]] pb ph ps pa pas
            set on [expr {$pend(base) eq $pb && $pend(bh) == $ph && $pend(bs) == $ps \
                          && $pend(ah) == $pa && $pend(as) == $pas}]
            $can itemconfigure lumen_thpr_$i \
                -outline [expr {$on ? $C(ink) : $C(glass_brd)}] -width [expr {$on ? 6 : 2}]
        }
        _preview_render $P
    } err] } {
        msg -ERROR "Lumen: theme preview refresh failed: $err"
    }
}

# 0.51.0: the miniature. The home page painted by the same painter that
# draws the custom backgrounds, from the PENDING palette, at the preview
# column's width (330/1340 of the real thing), handed to the image item
# under the preview texts; the previous photo is freed. Headless, or on
# any failure, the pending page colour rect beneath it stays visible.
proc ::lumen::_preview_render { P } {
    variable L
    variable preview_img
    if { [info commands image] eq "" } { return }
    if { [catch {
        lassign [::lumen::custom::screen] W H
        if { $W <= 0 } { error "no screen size" }
        set mw [expr {int(round($L(thp_piw) * $W / 1340.0))}]
        set mh [expr {int(round($L(thp_mini_h) * $H / 800.0))}]
        set t0 [clock milliseconds]
        set img [::lumen::custom::page_photo $P [dict get $::lumen::custom::pages home] $mw $mh]
        set can [dui canvas]
        $can itemconfigure lumen_th_mini -image $img
        if { [info exists preview_img] && $preview_img ne "" && $preview_img ne $img } {
            image delete $preview_img
        }
        set preview_img $img
        msg -DEBUG "Lumen: preview miniature ${mw}x${mh} painted in [expr {[clock milliseconds] - $t0}] ms"
    } err] } {
        msg -NOTICE "Lumen: preview miniature not painted: $err"
    }
}

proc ::lumen::build_theme_page {} {
    variable C
    variable L
    variable ::lumen::custom::presets
    set p "lumen_theme"
    set n 0     ;# unique first tag per item (dui refuses duplicates)

    txt $p $L(center_x) 24 [translate "Custom theme"] \
        -font $L(font_title) -fill $C(ink) -anchor n -justify center
    var $p $L(center_x) 72 {[::lumen::data::version_line]} \
        -font $L(font_caption) -fill $C(ink_3) -anchor n -justify center

    set lx $L(thp_x) ; set lw $L(thp_w) ; set ix [expr {$lx + $L(pad_x)}]

    # ---- BASE, with the Auto schedule (0.55.0) ----
    # Three pills right-aligned to the card's inner edge: Dark and Light
    # (the pending custom base, as before) and Auto (the schedule toggle,
    # persisted at once). The second line is the schedule itself: "Auto:"
    # then the two times, each a 116 x 44 zone that steps it 30 min per
    # tap; the zones end 6 short of the Dark pill's.
    set by $L(thp_base_y)
    glass $p $lx $by $lw $L(thp_base_h)
    txt $p $ix [expr {$by + 18}] [translate "BASE"] -font $L(font_label) -fill $C(ink_3)
    txt $p $ix [expr {$by + 44}] [translate "Auto:"] -font $L(font_caption) -fill $C(ink_2)
    foreach which {light dark} dx {52 172} {
        var $p [expr {$ix + $dx}] [expr {$by + 44}] "\[::lumen::data::auto_[set which]_text\]" \
            -font $L(font_caption) -fill $C(ink_2)
        tap $p [expr {$ix + $dx - 6}] [expr {$by + 30}] 116 44 \
            "::lumen::act::auto_step $which" "Auto $which time" label
    }
    set pr [expr {$lx + $lw - $L(pad_x)}]
    foreach {b bx bw lbl} [list dark [expr {$pr - 304}] 96 "Dark" light [expr {$pr - 200}] 96 "Light" \
                               auto [expr {$pr - 96}] 96 "Auto"] {
        set py [expr {$by + 16}]
        rounded_rect $p [X $bx] [Y $py] [X [expr {$bx + $bw}]] [Y [expr {$py + 48}]] [X 32] \
            -fill $C(glass_2) -outline $C(glass_brd) -width 2 -tags [list lumen_thi_[incr n] lumen_thb_$b]
        dui add dtext $p [X [expr {$bx + $bw / 2.0}]] [Y [expr {$py + 24}]] -text [translate $lbl] \
            -font $L(font_button) -fill $C(ink_2) -anchor center -justify center \
            -tags [list lumen_thi_[incr n] lumen_thbt_$b]
        tap $p $bx $py $bw 48 "::lumen::act::theme_pick base $b" "Base $lbl"
    }

    # ---- BACKDROP and ACCENT: label + caption on one line, two rows of 13 ----
    set d $L(thp_dot) ; set pitch $L(thp_pitch)
    foreach {key ry title cap} [list \
        bh $L(thp_bh_y) "BACKDROP" "Page and glass tint. Grey, tinted, taupe, rich." \
        ah $L(thp_ah_y) "ACCENT"   "Hero number, buttons, links. White, vivid, brown, muted."] {
        glass $p $lx $ry $lw $L(thp_sw_h)
        txt $p $ix [expr {$ry + 18}] [translate $title] -font $L(font_label) -fill $C(ink_3)
        txt $p [expr {$ix + 110}] [expr {$ry + 18}] [translate $cap] \
            -font $L(font_caption) -fill $C(ink_2)
        set i 0
        foreach sw [::lumen::custom::swatches $key] {
            lassign $sw h s disp
            set sx [expr {$ix + ($i % 13) * $pitch}]
            set sy [expr {$ry + ($i < 13 ? $L(thp_row1) : $L(thp_row2))}]
            dui add canvas_item oval $p [X $sx] [Y $sy] [X [expr {$sx + $d}]] [Y [expr {$sy + $d}]] \
                -fill $disp -outline $C(glass_brd) -width 2 \
                -tags [list lumen_thi_[incr n] lumen_ths_${key}_$i]
            # 44 px zones on a 46 px pitch: touch floor kept, never overlapping.
            # 0.54.2: no press chip -- the swatch takes the selection ring.
            tap $p [expr {$sx - 3}] [expr {$sy - 3}] 44 44 "::lumen::act::theme_pick $key $h $s" "Colour $h $s" none
            incr i
        }
    }

    # ---- PRESETS: two rows of three pills (0.53.1) ----
    set ry $L(thp_pre_y)
    glass $p $lx $ry $lw $L(thp_pre_h)
    txt $p $ix [expr {$ry + 18}] [translate "PRESETS"] -font $L(font_label) -fill $C(ink_3)
    set pw $L(thp_pre_w) ; set pg $L(thp_pre_gap) ; set pph $L(thp_pre_ph)
    for { set i 0 } { $i < [llength $presets] / 6 } { incr i } {
        lassign [lrange $presets [expr {$i * 6}] [expr {$i * 6 + 5}]] name pb ph ps pa pas
        set PP [::lumen::custom::palette $pb $ph $ps $pa $pas]
        set px [expr {$ix + ($i % 3) * ($pw + $pg)}]
        set py [expr {$ry + $L(thp_row1) + ($i / 3) * ($pph + $pg)}]
        rounded_rect $p [X $px] [Y $py] [X [expr {$px + $pw}]] [Y [expr {$py + $pph}]] [X 24] \
            -fill [dict get $PP bg] -outline $C(glass_brd) -width 2 \
            -tags [list lumen_thi_[incr n] lumen_thpr_$i]
        dui add dtext $p [X [expr {$px + $pw / 2.0}]] [Y [expr {$py + $pph / 2.0}]] -text [translate $name] \
            -font $L(font_label) -fill [dict get $PP crema] -anchor center -justify center \
            -tags [list lumen_thi_[incr n]]
        tap $p $px $py $pw $pph "::lumen::act::theme_preset $i" $name
    }

    # ---- PREVIEW column ----
    set rx $L(thp_px) ; set rw $L(thp_pw)
    set pv_y $L(thp_base_y) ; set pv_h [expr {$L(thp_pre_y) + $L(thp_pre_h) - $pv_y}]
    glass $p $rx $pv_y $rw $pv_h
    txt $p [expr {$rx + $L(pad_x)}] [expr {$pv_y + 18}] [translate "PREVIEW"] \
        -font $L(font_label) -fill $C(ink_3)
    # 0.53.1: everything inside the card keeps pad_x clear of both edges
    # (owner: nothing hugs a card border); mx / mw is that inner span.
    set mx [expr {$rx + $L(pad_x)}] ; set mw $L(thp_piw)
    # The miniature: a rect in the pending page colour, the painted photo
    # over it, a hairline around both, and a few readable labels on top
    # (the real text would be 4 px tall at this scale).
    set my $L(thp_mini_y) ; set mh $L(thp_mini_h)
    dui add canvas_item rectangle $p [X $mx] [Y $my] [X [expr {$mx + $mw}]] [Y [expr {$my + $mh}]] \
        -fill $C(bg) -outline "" -tags [list lumen_thi_[incr n] lumen_thp_bg]
    dui add canvas_item image $p [X $mx] [Y $my] -anchor nw \
        -tags [list lumen_thi_[incr n] lumen_th_mini]
    dui add canvas_item rectangle $p [X $mx] [Y $my] [X [expr {$mx + $mw}]] [Y [expr {$my + $mh}]] \
        -fill "" -outline $C(glass_brd) -width 2 -tags [list lumen_thi_[incr n] lumen_tho_glass_brd]
    set k [expr {double($mw) / 1340.0}]
    # grind card (16,64 650x190): the hero and the band. 0.52.1: the fonts
    # do not shrink with the card (40 px tall here), so the two lines are
    # placed from the card's TOP in design px, the hero one size down
    # (primary), and neither bbox crosses the other or the card edge.
    set gc_top [expr {$my + 64 * $k}]
    dui add dtext $p [X [expr {$mx + (16 + 325) * $k}]] [Y [expr {$gc_top + 13.5}]] -text "2.8" \
        -font $L(font_primary) -fill $C(crema) -anchor center -justify center \
        -tags [list lumen_thi_[incr n] lumen_thp_crema]
    dui add dtext $p [X [expr {$mx + 40 * $k}]] [Y [expr {$gc_top + 36.5}]] -text "[translate Good] - 12 [translate shots]" \
        -font $L(font_caption) -fill $C(good) -anchor w -justify left \
        -tags [list lumen_thi_[incr n] lumen_thp_good]
    # last-shot card (682,64 642x190). 0.53.1: the two lines sit on the
    # grind card's baselines (+13.5 / +36.5 from the card top) -- at the
    # 282-wide scale their old 84-design-px pitch was 17.7 px, and the
    # verify run flagged the caption against the values row.
    dui add dtext $p [X [expr {$mx + 706 * $k}]] [Y [expr {$gc_top + 13.5}]] -text [translate "LAST SHOT"] \
        -font $L(font_caption) -fill $C(ink_3) -anchor w -justify left \
        -tags [list lumen_thi_[incr n] lumen_thp_ink_3]
    dui add dtext $p [X [expr {$mx + 706 * $k}]] [Y [expr {$gc_top + 36.5}]] -text "2.1  19.0  38.0" \
        -font $L(font_caption) -fill $C(ink) -anchor w -justify left \
        -tags [list lumen_thi_[incr n] lumen_thp_ink]
    # next-shot strip (16,574 1308x210): the bean name only. 0.52.1: the
    # NEXT SHOT caption is gone -- the caption, the name and the painted
    # pill row did not fit; LAST SHOT already shows ink_3. 0.54.1: the
    # name sits where the real one does (652 design px, the identity
    # block's hero line), which at this scale is 23 px into the 63-tall
    # strip -- clear of the top edge and of the painted rows.
    dui add dtext $p [X [expr {$mx + 40 * $k}]] [Y [expr {$my + 652 * $k}]] -text "Las Brumas" \
        -font $L(font_primary) -fill $C(ink) -anchor w -justify left \
        -tags [list lumen_thi_[incr n] lumen_thp_ink]
    # 0.54.2 (owner): the strip's GRIND / DOSE / YIELD row. Labels at their
    # real x (520 + i x 270) and top (594); values centred where the real
    # ones sit between the pills (kx + 120), one line down. 0.55.0: the
    # values in the CAPTION size like the LAST SHOT card's (the data mono
    # was huge at this scale -- owner), at 700 so the two bboxes keep the
    # checker's gap. Row: my + 178..220, strip ends 235.
    set i 0
    foreach lbl {GRIND DOSE YIELD} val {2.8 19.0 38.0} {
        set kx [expr {$mx + (520 + $i * 270) * $k}]
        dui add dtext $p [X $kx] [Y [expr {$my + 594 * $k}]] -text [translate $lbl] \
            -font $L(font_label) -fill $C(ink_3) -anchor nw -justify left \
            -tags [list lumen_thi_[incr n] lumen_thp_ink_3]
        dui add dtext $p [X [expr {$kx + 120 * $k}]] [Y [expr {$my + 700 * $k}]] -text $val \
            -font $L(font_caption) -fill $C(ink) -anchor center -justify center \
            -tags [list lumen_thi_[incr n] lumen_thp_ink]
        incr i
    }

    # Token chips: the derived colours themselves, labelled.
    set cy $L(thp_chip_y) ; set cw $L(thp_chip_w) ; set ch $L(thp_chip_h)
    set i 0
    foreach {tok lbl} [list bg "Page" glass "Glass" ink "Text" crema "Accent" crema_lo "Chip"] {
        set cx [expr {$mx + $i * ($cw + $L(thp_chip_gap))}]
        rounded_rect $p [X $cx] [Y $cy] [X [expr {$cx + $cw}]] [Y [expr {$cy + $ch}]] [X 16] \
            -fill $C($tok) -outline $C(glass_brd) -width 2 \
            -tags [list lumen_thi_[incr n] lumen_thp_$tok lumen_tho_glass_brd]
        dui add dtext $p [X [expr {$cx + $cw / 2.0}]] [Y [expr {$cy + $ch + 6}]] -text [translate $lbl] \
            -font $L(font_caption) -fill $C(ink_3) -anchor n -justify center \
            -tags [list lumen_thi_[incr n] lumen_thp_ink_3]
        incr i
    }

    dui add dtext $p [X $mx] [Y $L(thp_note_y)] -width [X $mw] -anchor nw -justify left \
        -text [translate "Tap Done: every page switches to these colours at once. New colours take a few seconds to draw."] \
        -font $L(font_caption) -fill $C(ink_2) -tags [list lumen_thi_[incr n] lumen_thp_ink_2]
    dui add dtext $p [X $mx] [Y $L(thp_note2_y)] -width [X $mw] -anchor nw -justify left \
        -text [translate "Contrast is guarded: labels and the accent always stay readable on the glass."] \
        -font $L(font_caption) -fill $C(ink_3) -tags [list lumen_thi_[incr n] lumen_thp_ink_3]
    # Status line for the live apply ("Drawing your theme..." / the
    # failure), in the CURRENT theme's accent, blank otherwise.
    txt $p $mx $L(thp_status_y) "" -font $L(font_caption) -fill $C(crema) -width $mw -tags lumen_th_status

    # ---- Cancel / Done (0.53.1: under the taller presets card) ----
    set dy $L(thp_done_y)
    txt $p 194 [expr {$dy + 26}] [translate "Cancel"] -font $L(font_button) -fill $C(crema)
    tap $p 170 [expr {$dy + 10}] 120 56 {::lumen::act::theme_cancel} "Cancel" label
    set dw $L(set_done_w) ; set dh $L(set_done_h)
    set dx [expr {$L(center_x) - $dw / 2}]
    glass $p $dx $dy $dw $dh -radius $L(radius_sm) -fill $C(crema_lo) -outline $C(crema_brd)
    txt $p [expr {$dx + $dw / 2.0}] [expr {$dy + $dh / 2.0}] [translate "Done"] \
        -font $L(font_button) -fill $C(crema) -anchor center -justify center
    tap $p $dx $dy $dw $dh {::lumen::act::theme_apply} "Done"
}

#############################################################################
#  Lumen settings page
#
#  Reached from the rail's Settings button. Lumen's own preferences live
#  here, and the app's stock settings are one tap further -- so the rail
#  keeps a single entry point and Lumen's options stay discoverable.
#############################################################################

# One settings row carrying a -/+ stepper group: the row panel, its label, an
# optional caption, and [-] value [+] right-aligned inside the row.
#
# Factored out in 0.24.0: with the rows re-dealt between the columns, inline
# copies in each column would have been two versions of the same row that
# could drift apart. All arguments in DESIGN px.
proc ::lumen::settings_stepper_row { p x y w label notecode valcode \
                                     minus_code plus_code what } {
    variable C
    variable L

    set rh  $L(set_row_h)
    set sw  $L(set_step_w)  ; set sg  $L(set_step_gap)
    set svw $L(set_val_w)   ; set sh  $L(set_step_h)

    glass $p $x $y $w $rh
    txt $p [expr {$x + $L(pad_x)}] [expr {$y + 26}] $label \
        -font $L(font_label) -fill $C(ink_3)
    if { $notecode ne "" } {
        var $p [expr {$x + $L(pad_x)}] [expr {$y + 56}] $notecode \
            -font $L(font_caption) -fill $C(ink_2)
    }

    set gx [expr {$x + $w - $L(pad_x) - (2 * $sw + 2 * $sg + $svw)}]
    set gy [expr {$y + ($rh - $sh) / 2}]
    set gmid_y [expr {$gy + $sh / 2.0}]
    foreach sx [list $gx [expr {$gx + $sw + $sg + $svw + $sg}]] \
            glyph [list "-" "+"] scode [list $minus_code $plus_code] \
            lbl [list "$what down" "$what up"] {
        glass $p $sx $gy $sw $sh -radius $L(radius_sm) -spec 0
        txt $p [expr {$sx + $sw / 2.0}] \
            [expr {$gmid_y + ($glyph eq "-" ? $L(step_minus_dy) : 0)}] $glyph \
            -font $L(font_section) -fill $C(crema) \
            -anchor center -justify center
        tap $p $sx $gy $sw $sh $scode $lbl
    }
    var $p [expr {$gx + $sw + $sg + $svw / 2.0}] $gmid_y $valcode \
        -font $L(font_data) -fill $C(ink) -anchor center -justify center
}

# A settings row whose -/+ pills drive one of TWO settings, with a tappable
# mode line choosing which (0.26.0, owner request: STEAM alternates time and
# flow, HOT WATER temperature and volume).
#
# Same panel, same pills, same x geometry as settings_stepper_row -- so the
# baked background does not change and nothing was re-rendered for this. What
# differs is inside the row:
#
#   * the caption line becomes MODE | other, in two text items. A canvas text
#     item's -fill is fixed at creation, so the words move between a crema
#     item and a dim one rather than the colours moving between fixed words.
#   * the value stacks: the selected setting at 26px on the pill band's upper
#     line, the other at 16px beneath it -- the same two-line arrangement the
#     home strip's YIELD column already uses for its ratio.
#
# All arguments in DESIGN px.
proc ::lumen::settings_dual_row { p x y w label active_code other_code \
                                  valcode altcode dir_cmd toggle_cmd what } {
    variable C
    variable L

    set rh  $L(set_row_h)
    set sw  $L(set_step_w)  ; set sg  $L(set_step_gap)
    set svw $L(set_val_w)   ; set sh  $L(set_step_h)

    glass $p $x $y $w $rh
    txt $p [expr {$x + $L(pad_x)}] [expr {$y + 26}] $label \
        -font $L(font_label) -fill $C(ink_3)

    # Mode line. The selected half is the accent colour, the other dim.
    var $p [expr {$x + $L(pad_x)}] [expr {$y + 56}] $active_code \
        -font $L(font_label) -fill $C(crema)
    var $p [expr {$x + $L(pad_x) + $L(set_mode_dx)}] [expr {$y + 56}] $other_code \
        -font $L(font_label) -fill $C(ink_3)
    # One tap over both words: with two modes, "tap the other one" and "toggle"
    # are the same action, and one target cannot be mis-hit the way two 60px
    # ones side by side can.
    tap $p [expr {$x + $L(pad_x)}] [expr {$y + 40}] \
        $L(set_mode_w) $L(set_mode_h) $toggle_cmd $what label

    set gx [expr {$x + $w - $L(pad_x) - (2 * $sw + 2 * $sg + $svw)}]
    set gy [expr {$y + ($rh - $sh) / 2}]
    set gmid_y [expr {$gy + $sh / 2.0}]
    foreach sx [list $gx [expr {$gx + $sw + $sg + $svw + $sg}]] \
            glyph [list "-" "+"] d [list -1 1] \
            lbl [list "$what down" "$what up"] {
        glass $p $sx $gy $sw $sh -radius $L(radius_sm) -spec 0
        txt $p [expr {$sx + $sw / 2.0}] \
            [expr {$gmid_y + ($glyph eq "-" ? $L(step_minus_dy) : 0)}] $glyph \
            -font $L(font_section) -fill $C(crema) \
            -anchor center -justify center
        tap $p $sx $gy $sw $sh "$dir_cmd $d" $lbl
    }

    # Selected value on top, the other beneath it -- the YIELD column's
    # arrangement, on the same 48-tall band.
    set vx [expr {$gx + $sw + $sg + $svw / 2.0}]
    var $p $vx [expr {$gy + 16}] $valcode \
        -font $L(font_data) -fill $C(ink) -anchor center -justify center
    var $p $vx [expr {$gy + 38}] $altcode \
        -font $L(font_caption) -fill $C(ink_3) -anchor center -justify center
}

# (0.36.0: settings_button_row is gone with its last caller, the GRIND
# ADVISOR row -- the grind card on the home page opens those settings
# now. Resurrect it from git/an archive if a button row returns.)

proc ::lumen::build_settings {} {
    variable C
    variable L
    set p "lumen_settings"

    txt $p $L(center_x) 24 [translate "Lumen"] \
        -font $L(font_title) -fill $C(ink) -anchor n -justify center
    var $p $L(center_x) 72 {[::lumen::data::version_line]} \
        -font $L(font_caption) -fill $C(ink_3) -anchor n -justify center

    # 0.53.0: the favorite slots' one management control, a text link in
    # the header (the page is baked and both columns are full). Blank,
    # and its tap a no-op, while no slot is set.
    var $p [expr {$L(set_favclr_x) + $L(set_favclr_w)}] \
        [expr {$L(set_favclr_y) + $L(set_favclr_h) / 2.0}] \
        {[::lumen::data::fav_clear_label]} \
        -font $L(font_caption) -fill $C(crema) -anchor e -justify right
    tap $p $L(set_favclr_x) $L(set_favclr_y) $L(set_favclr_w) $L(set_favclr_h) \
        {::lumen::act::clear_favorites} "Clear favorite profiles" label

    ####################################################################
    #  Two columns:
    #
    #    left  170..630 : BREW / STEAM / FLUSH / HOT WATER  (machine)
    #    right 670..1170: THEME / BAGS TO CYCLE / CLOCK / LOW WATER
    #
    #  0.36.0 (owner request): the GRIND ADVISOR row is GONE -- tapping
    #  the grind card on the home page opens those settings now -- and
    #  CLOCK moved up into its slot (0.41.0 briefly added a DECENT APP
    #  fourth row; 0.42.0 removed it for the taskbar's one-tap DE1 icon).
    #  0.45.0: the fourth slot holds LOW WATER, the taskbar's amber
    #  threshold, so both columns are four rows on the 110/244/378/512
    #  grid again. The left column is the machine column and all four
    #  of its steppers stay together.
    ####################################################################
    set lx $L(set_col_l) ; set lw $L(set_col_l_w)
    set rx $L(set_col_r) ; set rw $L(set_col_r_w)
    lassign $L(set_rows) ry1 ry2 ry3 ry4

    # ---- left column: the machine steppers ------------------------------
    #
    # BREW and FLUSH each steer one setting. STEAM and HOT WATER steer two,
    # chosen by the tappable mode line under their label (0.26.0).
    foreach {ry label notecode valcode minus_code plus_code what} [list \
        $ry1 [translate "BREW"] "" {[::lumen::data::brew_temp_value]} \
            {::lumen::act::adjust_brew_temp -0.5} {::lumen::act::adjust_brew_temp 0.5} "Brew" \
        $ry3 [translate "FLUSH"] "" {[::lumen::data::flush_time_value]} \
            {::lumen::act::adjust_flush_time -1} {::lumen::act::adjust_flush_time 1} "Flush" ] {
        settings_stepper_row $p $lx $ry $lw $label $notecode $valcode \
            $minus_code $plus_code $what
    }

    settings_dual_row $p $lx $ry2 $lw [translate "STEAM"] \
        {[::lumen::data::steam_mode_active]} {[::lumen::data::steam_mode_other]} \
        {[::lumen::data::steam_value]} {[::lumen::data::steam_value_alt]} \
        ::lumen::act::adjust_steam ::lumen::act::toggle_steam_mode "Steam"

    settings_dual_row $p $lx $ry4 $lw [translate "HOT WATER"] \
        {[::lumen::data::water_mode_active]} {[::lumen::data::water_mode_other]} \
        {[::lumen::data::water_value]} {[::lumen::data::water_value_alt]} \
        ::lumen::act::adjust_water ::lumen::act::toggle_water_mode "Hot water"

    # ---- right column ---------------------------------------------------
    #
    # THEME. 0.54.0 (owner request): the button reads "Change" and opens
    # the picker -- Dark and Light live there as the Lumen dark / Lumen
    # light presets, so the three-way cycle of 0.46.0-0.53.1 is gone. The
    # caption is live: it names the theme on screen (or a failed apply's
    # reason). The button is the row's ONLY tap and the only thing that
    # flashes (zone chip); the caption tap and the whole-card chip went
    # with the cycle. The button stays plain glass (it renders dark in
    # the dark theme, light in the light theme), and the row is drawn
    # here because the caption is a variable.
    set bw 150 ; set bh 56
    glass $p $rx $ry1 $rw $L(set_row_h)
    txt $p [expr {$rx + $L(pad_x)}] [expr {$ry1 + 26}] [translate "THEME"] \
        -font $L(font_label) -fill $C(ink_3)
    var $p [expr {$rx + $L(pad_x)}] [expr {$ry1 + 56}] \
        {[::lumen::data::theme_note]} \
        -font $L(font_caption) -fill $C(ink_2) -width 290
    set bx [expr {$rx + $rw - $L(pad_x) - $bw}]
    set by [expr {$ry1 + ($L(set_row_h) - $bh) / 2}]
    glass $p $bx $by $bw $bh -radius $L(radius_sm) -fill $C(glass_2)
    txt $p [expr {$bx + $bw / 2.0}] [expr {$by + $bh / 2.0}] [translate "Change"] \
        -font $L(font_button) -fill $C(ink) -anchor center -justify center
    tap $p $bx $by $bw $bh {::lumen::act::open_theme_picker} "Change theme"

    # BAGS TO CYCLE, with the same stepper geometry as the left column
    # mirrored to this column's inner edge: 670 + 500 - 24 = 1146, and the
    # group is 204 wide, so it starts at 942.
    glass $p $rx $ry2 $rw $L(set_row_h)
    txt $p [expr {$rx + $L(pad_x)}] [expr {$ry2 + 26}] [translate "BAGS TO CYCLE"] \
        -font $L(font_label) -fill $C(ink_3)
    txt $p [expr {$rx + $L(pad_x)}] [expr {$ry2 + 56}] \
        [translate "Recent bean bags the home strip can cycle through."] \
        -font $L(font_caption) -fill $C(ink_2) -width 220

    set sw $L(set_step_w) ; set sg $L(set_step_gap)
    set svw $L(set_val_w) ; set sh $L(set_step_h)
    set gx [expr {$rx + $rw - $L(pad_x) - (2 * $sw + 2 * $sg + $svw)}]
    set gy [expr {$ry2 + ($L(set_row_h) - $sh) / 2}]
    set gmid_y [expr {$gy + $sh / 2.0}]
    foreach sx [list $gx [expr {$gx + $sw + $sg + $svw + $sg}]] \
            glyph [list "-" "+"] \
            scode [list {::lumen::act::adjust_bag_count -1} \
                        {::lumen::act::adjust_bag_count 1}] \
            lbl [list "Bags down" "Bags up"] {
        glass $p $sx $gy $sw $sh -radius $L(radius_sm) -spec 0
        txt $p [expr {$sx + $sw / 2.0}] \
            [expr {$gmid_y + ($glyph eq "-" ? $L(step_minus_dy) : 0)}] $glyph \
            -font $L(font_section) -fill $C(crema) \
            -anchor center -justify center
        tap $p $sx $gy $sw $sh $scode $lbl
    }
    var $p [expr {$gx + $sw + $sg + $svw / 2.0}] $gmid_y \
        {[::lumen::data::bag_count_value]} \
        -font $L(font_data) -fill $C(ink) -anchor center -justify center

    # CLOCK (0.34.0), third row since 0.36.0 -- it moved up into the
    # GRIND ADVISOR row's slot when that row was removed (the grind card
    # on the home page opens Grind Advisor's settings now). Two
    # live-labelled raised buttons on the THEME-row pattern: date sample
    # left, time mode right. Both apply on the next taskbar tick -- no
    # restart.
    glass $p $rx $ry3 $rw $L(set_row_h)
    txt $p [expr {$rx + $L(pad_x)}] [expr {$ry3 + 26}] [translate "CLOCK"] \
        -font $L(font_label) -fill $C(ink_3)
    txt $p [expr {$rx + $L(pad_x)}] [expr {$ry3 + 56}] \
        [translate "Taskbar time and date format."] \
        -font $L(font_caption) -fill $C(ink_2) -width 190
    set ck_bh 56
    set ck_by [expr {$ry3 + ($L(set_row_h) - $ck_bh) / 2}]
    set ck_time_w 110
    set ck_date_w 130
    set ck_time_x [expr {$rx + $rw - $L(pad_x) - $ck_time_w}]
    set ck_date_x [expr {$ck_time_x - 12 - $ck_date_w}]
    glass $p $ck_date_x $ck_by $ck_date_w $ck_bh -radius $L(radius_sm) -fill $C(glass_2)
    var $p [expr {$ck_date_x + $ck_date_w / 2.0}] [expr {$ck_by + $ck_bh / 2.0}] \
        {[::lumen::data::clock_date_label]} \
        -font $L(font_button) -fill $C(ink) -anchor center -justify center
    tap $p $ck_date_x $ck_by $ck_date_w $ck_bh \
        {::lumen::act::toggle_date_format} "Date format"
    glass $p $ck_time_x $ck_by $ck_time_w $ck_bh -radius $L(radius_sm) -fill $C(glass_2)
    var $p [expr {$ck_time_x + $ck_time_w / 2.0}] [expr {$ck_by + $ck_bh / 2.0}] \
        {[::lumen::data::clock_time_label]} \
        -font $L(font_button) -fill $C(ink) -anchor center -justify center
    tap $p $ck_time_x $ck_by $ck_time_w $ck_bh \
        {::lumen::act::toggle_time_format} "Time format"

    # LOW WATER (0.45.0), fourth row: the level under which the taskbar's
    # water reading turns amber. Same stepper geometry as BAGS TO CYCLE
    # two rows up; 50 ml per tap. (0.41.0 put a DECENT APP row here;
    # 0.42.0 removed it for the taskbar's one-tap DE1 icon.)
    glass $p $rx $ry4 $rw $L(set_row_h)
    txt $p [expr {$rx + $L(pad_x)}] [expr {$ry4 + 26}] [translate "LOW WATER"] \
        -font $L(font_label) -fill $C(ink_3)
    txt $p [expr {$rx + $L(pad_x)}] [expr {$ry4 + 56}] \
        [translate "Taskbar water turns amber below this level."] \
        -font $L(font_caption) -fill $C(ink_2) -width 220
    set gy4 [expr {$ry4 + ($L(set_row_h) - $sh) / 2}]
    set gmid_y4 [expr {$gy4 + $sh / 2.0}]
    foreach sx [list $gx [expr {$gx + $sw + $sg + $svw + $sg}]] \
            glyph [list "-" "+"] \
            scode [list {::lumen::act::adjust_water_low -50} \
                        {::lumen::act::adjust_water_low 50}] \
            lbl [list "Low water down" "Low water up"] {
        glass $p $sx $gy4 $sw $sh -radius $L(radius_sm) -spec 0
        txt $p [expr {$sx + $sw / 2.0}] \
            [expr {$gmid_y4 + ($glyph eq "-" ? $L(step_minus_dy) : 0)}] $glyph \
            -font $L(font_section) -fill $C(crema) \
            -anchor center -justify center
        tap $p $sx $gy4 $sw $sh $scode $lbl
    }
    var $p [expr {$gx + $sw + $sg + $svw / 2.0}] $gmid_y4 \
        {[::lumen::data::water_low_value]} \
        -font $L(font_data) -fill $C(ink) -anchor center -justify center

    set dw $L(set_done_w) ; set dh $L(set_done_h)
    set dx [expr {$L(center_x) - $dw / 2}]
    set dy $L(set_done_y)
    glass $p $dx $dy $dw $dh -radius $L(radius_sm) \
        -fill $C(crema_lo) -outline $C(crema_brd)
    txt $p [expr {$dx + $dw / 2.0}] [expr {$dy + $dh / 2.0}] \
        [translate "Done"] -font $L(font_button) -fill $C(crema) \
        -anchor center -justify center
    tap $p $dx $dy $dw $dh {::lumen::act::close_settings} "Done"
}

::lumen::build_home
::lumen::build_settings
::lumen::build_message_page
::lumen::build_theme_page
# 0.55.0: the Auto schedule's minute tick (a no-op unless Auto is on).
after 60000 ::lumen::auto_tick

# Each page gets ITS OWN timer. Sharing espresso_secs across all of them
# reported time-since-the-last-espresso on the water and flush pages -- see
# water_secs / flush_secs for why that showed as 0s.
::lumen::build_flow_page espresso      {[::lumen::data::espresso_secs]} {[watertemp_text]} 1 \
    "TEMP" "" {[::lumen::data::target_yield_note]}
::lumen::build_flow_page hotwaterrinse {[::lumen::data::flush_secs]}    {[watertemp_text]}
::lumen::build_flow_page water         {[::lumen::data::water_secs]}    {[watertemp_text]}
# The steam column shows the STEAM HEATER sensor (the only steam-side sensor
# the machine has), labelled as such and with the set point stated under it.
# Shown as a bare "TEMP" it read as a wrong value -- 158C with the heater
# set to 160 is the heater at its set point, not a misreading.
::lumen::build_flow_page steam         {[::lumen::data::steam_secs]}    {[steamtemp_text 1]} 0 \
    "STEAM HEATER" {[::lumen::data::steam_target_note]}

#############################################################################
#  DYE integration
#
#  DYE looks for ::plugins::DYE::setup_ui_<skin> and calls it if it exists
#  (DYE.tcl:103). The skin is sourced before `plugins init` runs in
#  ui_startup, so defining it here is enough -- DYE itself is never edited.
#
#  IMPORTANT, so nobody re-litigates this later: setup_ui_* is a THEMING
#  hook, not a page-replacement hook. Every proven example (setup_Streamline,
#  setup_DSx2) registers a dui theme and sets aspects; DYE still builds and
#  owns its own editor pages, including all the data binding and persistence
#  into shot history. Rebuilding that form in the skin would mean duplicating
#  the plugin, so what this does is restyle DYE's pages to match Lumen.
#
#  Font SIZES stay in DYE's own convention (dui units, scaled by fontm), not
#  Lumen's pixel sizes -- DYE's page geometry is laid out against those
#  numbers and substituting pixel sizes would blow its layout apart. Only the
#  family and the colours change.
#############################################################################

# The skin runs before `plugins init`, so this namespace does not exist yet
# and `proc ::plugins::DYE::...` would fail with "unknown namespace". Creating
# it here is safe and additive: DYE's own `namespace eval ::plugins::DYE`
# extends it, and the plugin framework's peek only adds variables to it.
namespace eval ::plugins::DYE {}

proc ::plugins::DYE::setup_ui_Lumen {} {
    dui theme add DYE_Lumen
    dui theme set DYE_Lumen
    ::lumen::dye_aspects
    msg -INFO "Lumen: DYE styled with the DYE_Lumen theme"
}

# The DYE_Lumen aspects from the CURRENT palette. 0.48.0: split out of the
# hook so a live theme change can set them again before the DYE pages are
# recreated (::lumen::_retheme_dye). Fonts and sizes never change.
proc ::lumen::dye_aspects {} {
    set C_bg      $::lumen::C(bg)
    set C_panel   $::lumen::C(glass)
    set C_panel2  $::lumen::C(glass_2)
    set C_brd     $::lumen::C(glass_brd)
    set C_ink     $::lumen::C(ink)
    set C_ink2    $::lumen::C(ink_2)
    set C_ink3    $::lumen::C(ink_3)
    set C_accent  $::lumen::C(crema)
    set C_err     $::lumen::C(warn)

    set font  [::lumen::_font_family sans]
    set fontb [::lumen::_font_family sans_semi]
    set base  16

    dui aspect set -theme DYE_Lumen [subst {
        page.bg_img {}
        page.bg_color $C_bg
        dialog_page.bg_shape round_outline
        dialog_page.bg_color $C_panel
        dialog_page.fill $C_panel
        dialog_page.outline $C_brd
        dialog_page.width 1

        font.font_family "$font"
        font.font_size $base

        dtext.font_family "$font"
        dtext.font_size $base
        dtext.fill $C_ink
        dtext.disabledfill $C_ink3
        dtext.anchor nw
        dtext.justify left
        dtext.fill.remark $C_accent
        dtext.fill.error $C_err
        dtext.font_family.section_title "$fontb"
        dtext.font_family.page_title "$fontb"
        dtext.font_size.page_title 26
        dtext.fill.page_title $C_ink
        dtext.anchor.page_title center
        dtext.justify.page_title center

        symbol.fill $C_ink2
        symbol.disabledfill $C_ink3
        symbol.anchor nw
        symbol.justify left

        dbutton.fill $C_panel2
        dbutton.disabledfill $C_panel
        dbutton.outline $C_brd
        dbutton.disabledoutline $C_panel
        dbutton.width 1
        dbutton.radius 30

        dbutton_label.pos {0.5 0.5}
        dbutton_label.font_family "$fontb"
        dbutton_label.font_size [expr {$base + 1}]
        dbutton_label.anchor center
        dbutton_label.justify center
        dbutton_label.fill $C_ink
        dbutton_label.disabledfill $C_ink3

        entry.font_family "$font"
        entry.font_size $base
        entry.bg $C_panel2
        entry.foreground $C_ink
        entry.relief flat
        entry.borderwidth 1
        entry.highlightthickness 1
        entry.highlightcolor $C_accent
        entry.highlightbackground $C_brd
        entry.insertbackground $C_accent

        multiline_entry.font_family "$font"
        multiline_entry.font_size $base
        multiline_entry.bg $C_panel2
        multiline_entry.foreground $C_ink
        multiline_entry.relief flat
        multiline_entry.borderwidth 1
        multiline_entry.highlightthickness 1
        multiline_entry.highlightcolor $C_accent
        multiline_entry.highlightbackground $C_brd
        multiline_entry.insertbackground $C_accent

        listbox.font_family "$font"
        listbox.font_size $base
        listbox.background $C_panel2
        listbox.foreground $C_ink
        listbox.relief flat
        listbox.borderwidth 1
        listbox.selectbackground $C_accent
        listbox.selectforeground $C_bg
        listbox.disabledforeground $C_ink3

        dcheckbox.font_family "$font"
        dcheckbox.fill $C_ink
        dcheckbox.disabledfill $C_ink3
    }]
}

#############################################################################
#  Stop buttons
#
#  Copied verbatim from skins/default/standard_stop_buttons.tcl (minus its
#  add_de1_page lines, which would replace our colour backgrounds with the
#  default skin's JPGs, and minus its tankempty/refill block, which
#  standard_includes.tcl already provides).
#############################################################################

add_de1_button "steam" {say [translate {stop}] $::settings(sound_button_in); start_idle; check_if_steam_clogged} 0 0 2560 1600
add_de1_button "water" {say [translate {stop}] $::settings(sound_button_in); start_idle} 0 0 2560 1600
add_de1_button "espresso" {say [translate {stop}] $::settings(sound_button_in); start_idle} 0 0 2560 1600

# Deliberate addition, not in the stock file: the default skin has no
# tap-to-stop on the flush page because its flush is time-limited. Lumen
# gives flush a full page of its own, so it gets the same stop affordance as
# every other flow -- being unable to stop a running flush is worse than the
# inconsistency.
add_de1_button "hotwaterrinse" {say [translate {stop}] $::settings(sound_button_in); start_idle} 0 0 2560 1600

add_de1_button "saver descaling cleaning" {say [translate {awake}] $::settings(sound_button_in);start_idle; de1_send_waterlevel_settings} 0 0 2560 1600 "buttonnativepress"

add_de1_text "sleep" 2500 1450 -justify right -anchor "ne" -text [translate "Going to sleep"] -font Helv_20_bold -fill "#DDDDDD"

focus .can
bind Canvas <KeyPress> {handle_keypress %k}

# Deferred: the BLT vectors are created during app setup, which has not
# finished while the skin is being sourced. Five seconds is comfortably after
# startup and long before anyone pulls a shot.
after 5000 {
    if { [catch { ::lumen::load_last_shot_curves } err] } {
        msg -ERROR "Lumen: loading the last shot curves failed: $err"
    }
    # Same deferral, same reason: SDB is a plugin and has not finished
    # loading while the skin is being sourced.
    ::lumen::refresh_bag_list
    ::lumen::hook_sdb_save
}

# 0.57.4: the bag list also follows SDB's own save. The page-show refresh
# below fires the moment a shot ends, but SDB writes the new row later --
# on after_flow_complete, or after the Visualizer upload when that plugin
# is on (SDB.tcl:107-117). So the first shot on a newly scanned bag left
# the cached list without that bag: every dot hollow until an arrow tap
# re-read SDB (owner report 2026-09-24). A leave trace on the hook SDB runs
# on both paths re-reads once the row exists; one query per saved shot.
proc ::lumen::hook_sdb_save {} {
    set p ::plugins::SDB::save_espresso_to_history_hook
    if { [info procs $p] eq "" } {
        msg -INFO "Lumen: SDB save hook not found; the bag dots refresh on page show only"
        return
    }
    if { [lsearch -exact [trace info execution $p] {leave ::lumen::refresh_bag_list}] >= 0 } { return }
    trace add execution $p leave ::lumen::refresh_bag_list
    msg -INFO "Lumen: bag dots follow SDB's shot save"
}

# The bag cycler's window, rebuilt whenever the home page is shown -- which
# catches a new shot, a bag scan or a DYE edit without any of them needing to
# know about this skin. Once per page show, never on the refresh tick: the
# page indicator reads the cached list (0.27.0).
if { [catch { dui page add_action off show ::lumen::refresh_bag_list } err] } {
    msg -ERROR "Lumen: could not hook the bag-list refresh: $err"
}

# Core dui dialogs cannot be reached by theming, and recolouring them once at
# startup does not stick: dui repaints the page background when the page is
# SHOWN, discarding the change (measured -- the restyle reported "1 shapes"
# and the panel was still white).
#
# So hook the show event, which runs after dui has painted. add_action
# accepts a page that does not exist yet, so this can be registered here at
# skin load with no deferral.
foreach _p {dui_item_selector} {
    catch {
        dui page add_action $_p show "::lumen::restyle_core_dialog $_p"
    }
}
unset -nocomplain _p

# The espresso page opening means a shot is starting: record which profile it
# runs with, so the Last shot card can still name it after you switch. Guarded
# because add_action is a dui facility and a failure here must not stop the
# skin loading -- the value simply stays at whatever startup seeded.
if { [catch { dui page add_action espresso show ::lumen::latch_shot_profile } err] } {
    msg -ERROR "Lumen: could not hook the shot-profile latch: $err"
}

# 0.43.0: after a cleaning / calibration run the live vectors hold that
# run, so the home chart would keep showing it until the next real shot.
# The core's own after-flow event, registered here AFTER the core's
# history save (see ::lumen::after_flow_complete for why the order holds),
# puts the loaded bean's last real shot back.
if { [catch { ::de1::event::listener::after_flow_complete_add ::lumen::after_flow_complete } err] } {
    msg -ERROR "Lumen: could not hook after_flow_complete: $err"
}

# Each flow page stamps when it was shown, so its timer can tell the flow it
# is about to run from the one before it. Without this the espresso page
# spends the moments between "the machine entered Espresso" and "the pour
# started" reading the PREVIOUS shot's timer -- the owner saw it flash 450s,
# then drop to 0 and count normally (0.24.0). See ::lumen::data::_flow_secs.
foreach _p {espresso steam water hotwaterrinse} {
    if { [catch { dui page add_action $_p show \
                    [list ::lumen::latch_flow_open $_p] } err] } {
        msg -ERROR "Lumen: could not hook the flow-timer latch for $_p: $err"
    }
}
unset -nocomplain _p

msg -INFO "Lumen skin v$::lumen::version loaded ($::lumen::theme_mode)"

