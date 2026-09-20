#
# ShotHistoryEditor.tcl -- shot history browser with soft delete (v0.4.0)
# and real metadata save (v0.5.0).
#
# Runtime safety rules:
# - No automatic shot hooks.
# - SDB is opened with a separate read-only sqlite handle. SDB is never
#   written to (no INSERT/UPDATE/DELETE/ALTER/DROP/CREATE TABLE/VACUUM/
#   REINDEX anywhere in this file).
# - Two, and only two, authorized write capabilities against history files:
#   1) Soft delete (v0.4.0): `file rename` MOVES `history/<filename>.shot`
#      and, if present, `history_v2/<filename>.json` into
#      plugins/ShotHistoryEditor/trash/. See perform_delete_batch/
#      restore_batch. Content is never edited by this path.
#   2) Real metadata save (v0.5.0): perform_metadata_edit rewrites ONLY the
#      one targeted key line inside history/<filename>.shot's settings{}
#      block (via a verified temp-file + atomic `file rename`), after first
#      copying the whole original file to plugins/ShotHistoryEditor/
#      backups/. Every other byte of the file -- including the raw sensor
#      arrays -- is preserved untouched. history_v2/*.json is never written
#      by a save.
# - `file delete` is never called on a history file anywhere in this file.
# - Raw chart and sensor arrays are never displayed for editing and never
#   modified by either write path.
#

catch { package require sqlite3 }
catch { package require json }

namespace eval ::plugins::ShotHistoryEditor {
    variable db_handle ::plugins::ShotHistoryEditor::__sdb_ro
    variable recent_rows {}
    variable selected_row {}
    variable last_error ""
    variable table_used ""
    variable detected_objects {}
    # v0.8.6: 7 (was 8) so the Source Inspector's Open buttons reach the
    # design-system 60 px touch minimum inside their row band. The page's
    # row count, the refresh loop and the SQL scan cap all read this.
    variable max_recent 7
    variable detail_page_index 0
    variable diagnostics_page_index 0
    variable help_page_index 0
    variable delete_review_page_index 0
    # v0.10.0: the reconciliation view is a row list with an Unhide button per
    # row (was paged text in v0.9.0); same pager shape as the Trash page.
    variable reconcile_offset 0
    variable reconcile_page_size 6
    variable reconcile_note ""
    # v0.11.0: "Empty trash" PREVIEW page (paged text). Nothing is deleted in
    # this version; see empty_trash_preview_text.
    variable empty_preview_page_index 0
    # v0.12.0: real Empty trash. Snapshot of the batch ids taken when the
    # confirmation opens (perform_purge refuses if the set changed), the typed
    # confirmation, and the result text.
    variable purge_batch_ids {}
    variable purge_input ""
    variable purge_error ""
    variable purge_result_text ""
    # v0.13.0: Advanced > Tidy result, shown in the Advanced note until the
    # page is next shown.
    variable tidy_note ""
    variable page_line_count 22
    variable editable_fields {grinder_setting grinder_dose_weight drink_weight bean_brand bean_type espresso_notes my_name drinker_name}
    variable edit_field "grinder_setting"
    variable edit_new_value ""
    variable edit_preview_text "Preview only - no files will be modified."
    variable edit_warning ""
    variable edit_return_page "ShotHistoryEditor_settings"

    # v0.5.2: captured by the Settings page's own show{} (see
    # _capture_return_page below) -- the real DE1app page that opened this
    # plugin, so the Settings page's Done button can navigate straight back
    # to it instead of trusting the framework's own "previous page" stack.
    variable _settings_return_page ""

    # Pass 3 -- main-page card list state (all still read-only; see card_rows/sel below).
    variable card_rows {}
    variable card_page_size 5
    variable card_offset 0
    variable select_mode 0
    array set sel {}
    variable delete_target_count 0

    # Pass 3.1 -- design-system layout tokens, computed once in _init_layout from the
    # real detected screen size (see that proc for the full token table). Everything in
    # this plugin's UI is positioned from this array; no page should hardcode coordinates.
    array set L {}

    # Pass 4.0 -- real soft delete state. review_filenames/review_rows are a
    # snapshot taken the moment Delete is pressed, so the Review/Confirm flow
    # stays correct even if the underlying card list re-pages later. Nothing
    # here is a guard flag that could get stuck: every navigation into or out
    # of the delete flow goes through open_page, and the settings page's own
    # `show` proc already unconditionally resets select_mode/sel (v0.3.0
    # lesson), which is what actually exits the flow safely on Cancel.
    variable review_filenames {}
    variable review_rows {}
    variable confirm_input ""
    variable confirm_error ""
    variable delete_result_text ""
    variable trash_offset 0
    variable trash_page_size 6

    # Pass 5.0 -- real metadata save state. Snapshot taken the moment "Save
    # Change" is pressed on Edit Preview, so the Confirm/Result flow stays
    # correct even if the field selector is touched again later. As with
    # delete, there is no guard flag that can strand a button: every
    # navigation uses open_page (forward) or _return_to_page (back to an
    # ancestor), and edit_return_page is where the whole edit+confirm+result
    # mini-flow always returns to.
    variable edit_confirm_filename ""
    variable edit_confirm_field ""
    variable edit_confirm_old_value ""
    variable edit_confirm_new_value ""
    variable edit_result_text ""
}

# v0.8.3: the core logger honours a severity flag (-NOTICE, -INFO, ...)
# only in argument position one (logging.tcl default_logger). This wrapper
# used to put the namespace first, so every flagged call logged at the
# default INFO level with the flag as literal text. A leading flag is now
# hoisted ahead of the namespace, matching how the core itself calls msg.
proc ::plugins::ShotHistoryEditor::msg {args} {
    if {[string index [lindex $args 0] 0] eq "-"} {
        catch { ::msg [lindex $args 0] [namespace current] {*}[lrange $args 1 end] }
    } else {
        catch { ::msg [namespace current] {*}$args }
    }
}

# ---------------------------------------------------------------------------
# Pass 3.1 -- design-system layout tokens.
#
# Pass 3.2 bugfix note (v0.3.1 rendered at ~half size, top-left, with
# overlapping card text):
#
# v0.3.1's comment above was wrong. DE1app fpdialog pages are NOT drawn at
# real physical screen pixels -- they are drawn in a fixed VIRTUAL coordinate
# space that the dui framework itself rescales to whatever the physical
# screen actually is. Re-inspecting the reference plugins confirms this:
# SDB.tcl:3254 centers its page title at x=1280 (exactly half of 2560), and
# GrindAdvisor.tcl repeatedly places fpdialog buttons at y up to ~1580-1600
# (GrindAdvisor.tcl:1720 etc: "dui add dbutton $page 980 1375 1580 1495").
# Those coordinates are far larger than any physical tablet screen, so they
# only make sense in a virtual canvas of roughly 2560x1600 -- 2x the
# 1340x800 physical reference. The one confirmed dui coordinate-scaling API
# in this workspace, `dui::platform::rescale_x`/`rescale_y`
# (plugins/visualizer_upload/plugin.tcl:509), exists precisely to convert a
# value from that virtual space to physical pixels, which only makes sense
# if `dui add dtext/dbutton/canvas_item` coordinates are themselves expected
# in virtual-space units -- dui does the physical conversion for us. No
# constant literally named "2560"/"1600" is declared anywhere in this
# workspace (checked plugins/SDB, plugins/GrindAdvisor,
# plugins/visualizer_upload, skins/*/skin.tcl again for this pass); the
# virtual size is only inferable from the coordinates plugins actually draw
# at, so it is hardcoded below as the two constants VIRTUAL_W/VIRTUAL_H.
#
# v0.3.1 fed `winfo screenwidth/screenheight` (the REAL physical size, e.g.
# 1340x800) into every coordinate formula. Since dui treats all incoming
# coordinates as virtual-space (~2560x1600) and rescales them down to the
# real physical screen regardless, our already-physical-sized coordinates
# got shrunk a second time (physical 1340x800 treated as if it were
# 2560x1600 virtual -> rescaled by roughly 1340/2560 ~= 0.52), which is
# exactly the "half size, top-left" symptom (bottom bar and right edge never
# reached, because our right_x/bar_y0 were themselves only ~52% of where
# they needed to be).
#
# Font sizes are a separate problem: our SHE_* fonts are plain Tk font
# objects created with `font create ... -size -N` (negative = literal
# pixels) and referenced by name via `-font`. dui has no way to intercept or
# rescale an arbitrary Tk font object handed to it this way -- `-font` is
# passed straight through to the underlying canvas text item, so whatever
# pixel size we create it at is what renders, completely unaffected by
# dui's coordinate rescale. That means fonts must be sized for the REAL
# physical screen (so they render at the intended physical pixel size),
# while coordinates must be computed in the virtual space (so dui's own
# rescale lands them in the right physical place). v0.3.1 used one scale
# factor for both from the same (real, physical) screen_h -- coincidentally
# correct for fonts, but wrong for coordinates, which is why fonts looked
# oversized relative to the doubly-shrunk card spacing and the baselines
# collided. This pass introduces two independent scale factors from two
# different sources for exactly that reason: `scale` (coordinates, from the
# fixed virtual base resolution) and `font_scale` (fonts, from the real
# detected physical screen, same winfo pattern as before).
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
#  Theme palette (v0.8.0). Every color the plugin paints comes from these
#  tokens, chosen per settings(theme) (light | dark, default light, persisted
#  in the plugin's own settings.tdb -- this plugin's first persisted setting).
#  Called from _init_layout at startup and from toggle_theme at runtime.
# ---------------------------------------------------------------------------

proc ::plugins::ShotHistoryEditor::_apply_palette {} {
    variable L
    variable settings
    set dark 0
    catch { if {$settings(theme) eq "dark"} { set dark 1 } }
    if {$dark} {
        set L(page_bg)      "#23252e"
        set L(card_bg)      "#32353f"
        set L(card_outline) "#464b58"
        set L(text_hi)      "#e8e9ee"
        set L(text_body)    "#c2c5cf"
        set L(text_mut)     "#8d92a0"
        set L(danger)       "#ff8a80"
        set L(warn)         "#e0a860"
        set L(value_blue)   "#8ab4ff"
        set L(entry_bg)     "#3a3e4a"
        set L(entry_danger_bg) "#4a3438"
        set L(btn_fill)     "#4a5473"
        set L(btn_disabled_fill) "#3a3e4a"
    } else {
        set L(page_bg)      "#d5d6e3"   ;# stock settings-page grey
        set L(card_bg)      "#fbfbfd"
        set L(card_outline) "#dcdcdc"
        set L(text_hi)      "#2b2b2b"
        set L(text_body)    "#444444"
        set L(text_mut)     "#666666"
        set L(danger)       "#c0392b"
        set L(warn)         "#7a4b00"
        set L(value_blue)   "#4e85f4"
        set L(entry_bg)     "#fbfaff"
        set L(entry_danger_bg) "#fff5f5"
        set L(btn_fill)     "#c0c5e3"   ;# stock dbutton periwinkle
        set L(btn_disabled_fill) "#dddddd"
    }
}

proc ::plugins::ShotHistoryEditor::_glyph_for {name} {
    set glyph ""
    catch {
        if {[dui symbol exists $name]} { set glyph [dui symbol get $name] }
    }
    return $glyph
}

# v0.8.5: label glyphs (pencil, arrows, checkboxes) are built from their
# code points so the source stays plain ASCII (CLAUDE.md rule) and no editor
# or tool can mangle a raw character or a backslash escape. Every label that
# uses one keeps its plain-text word beside it as the fallback.
proc ::plugins::ShotHistoryEditor::_u {code} {
    return [format %c $code]
}

# Moon in light mode (tap for dark), sun-bright in dark; text fallback.
proc ::plugins::ShotHistoryEditor::_theme_button_face {} {
    variable L
    variable settings
    set dark 0
    catch { if {$settings(theme) eq "dark"} { set dark 1 } }
    if {[info exists L(have_icons)] && $L(have_icons)} {
        set g [_glyph_for [expr {$dark ? "sun-bright" : "moon"}]]
        if {$g ne ""} { return $g }
    }
    return [expr {$dark ? [translate "Light"] : [translate "Dark"]}]
}

proc ::plugins::ShotHistoryEditor::toggle_theme {} {
    variable settings
    set settings(theme) [expr {$settings(theme) eq "dark" ? "light" : "dark"}]
    catch { plugins save_settings ShotHistoryEditor }
    _apply_palette
    _retheme_all
    catch { dui item config ShotHistoryEditor_settings btn_theme -label [_theme_button_face] }
    catch { msg "ShotHistoryEditor: theme switched to $settings(theme)" }
}

# Repaint every palette-colored item by bare tag on all 13 pages. All
# colors in this plugin are creation-time (no refresh reconfigures a
# fill), so this walk IS the complete repaint. Buttons restyle through
# their -btn shape tags (labels stay white in both themes, except the
# three danger-labeled buttons, whose -lbl follows L(danger)).
proc ::plugins::ShotHistoryEditor::_retheme_all {} {
    variable L
    foreach p {ShotHistoryEditor_settings ShotHistoryEditor_advanced
               ShotHistoryEditor_delete_review ShotHistoryEditor_delete_confirm
               ShotHistoryEditor_delete_result ShotHistoryEditor_trash
               ShotHistoryEditor_recent ShotHistoryEditor_detail
               ShotHistoryEditor_edit_preview ShotHistoryEditor_edit_confirm
               ShotHistoryEditor_edit_result ShotHistoryEditor_diagnostics
               ShotHistoryEditor_help ShotHistoryEditor_reconcile
               ShotHistoryEditor_empty_preview ShotHistoryEditor_purge_confirm
               ShotHistoryEditor_purge_result} {
        catch { dui item config $p page_bg -fill $L(page_bg) -outline $L(page_bg) }
    }
    # Text roles: {page tag role} triplets.
    foreach {p tag role} {
        ShotHistoryEditor_settings page_title text_hi
        ShotHistoryEditor_settings subtitle text_mut
        ShotHistoryEditor_settings recent_status text_mut
        ShotHistoryEditor_advanced page_title text_body
        ShotHistoryEditor_advanced subtitle text_mut
        ShotHistoryEditor_advanced deleted_note warn
        ShotHistoryEditor_delete_review page_title danger
        ShotHistoryEditor_delete_review review_count_text text_body
        ShotHistoryEditor_delete_review review_intro text_mut
        ShotHistoryEditor_delete_review review_page_status text_mut
        ShotHistoryEditor_delete_review review_text text_body
        ShotHistoryEditor_delete_confirm page_title danger
        ShotHistoryEditor_delete_confirm confirm_instructions text_body
        ShotHistoryEditor_delete_confirm confirm_error_text danger
        ShotHistoryEditor_delete_result page_title text_body
        ShotHistoryEditor_delete_result result_text text_body
        ShotHistoryEditor_edit_confirm page_title danger
        ShotHistoryEditor_edit_confirm confirm_shot_text text_body
        ShotHistoryEditor_edit_confirm confirm_file_text text_mut
        ShotHistoryEditor_edit_confirm confirm_field_text text_body
        ShotHistoryEditor_edit_confirm confirm_before_text text_body
        ShotHistoryEditor_edit_confirm confirm_after_text danger
        ShotHistoryEditor_edit_confirm confirm_warning_text warn
        ShotHistoryEditor_edit_result page_title text_body
        ShotHistoryEditor_edit_result edit_result_text text_body
        ShotHistoryEditor_trash page_title text_body
        ShotHistoryEditor_trash trash_status text_mut
        ShotHistoryEditor_trash header text_body
        ShotHistoryEditor_recent page_title text_body
        ShotHistoryEditor_recent recent_status text_mut
        ShotHistoryEditor_recent header text_body
        ShotHistoryEditor_detail page_title text_body
        ShotHistoryEditor_detail detail_page_status text_mut
        ShotHistoryEditor_detail detail_text text_body
        ShotHistoryEditor_edit_preview page_title text_body
        ShotHistoryEditor_edit_preview selected_shot text_body
        ShotHistoryEditor_edit_preview editable_source text_mut
        ShotHistoryEditor_edit_preview fs_label text_body
        ShotHistoryEditor_edit_preview field_value value_blue
        ShotHistoryEditor_edit_preview cv_label text_body
        ShotHistoryEditor_edit_preview current_value text_body
        ShotHistoryEditor_edit_preview preview_status warn
        ShotHistoryEditor_edit_preview preview_text text_body
        ShotHistoryEditor_diagnostics page_title text_body
        ShotHistoryEditor_diagnostics diagnostics_page_status text_mut
        ShotHistoryEditor_diagnostics diagnostics_text text_body
        ShotHistoryEditor_help page_title text_body
        ShotHistoryEditor_help help_page_status text_mut
        ShotHistoryEditor_help help_text text_body
        ShotHistoryEditor_reconcile page_title text_body
        ShotHistoryEditor_reconcile reconcile_status text_mut
        ShotHistoryEditor_reconcile header text_body
        ShotHistoryEditor_empty_preview page_title text_body
        ShotHistoryEditor_empty_preview empty_preview_page_status text_mut
        ShotHistoryEditor_empty_preview empty_preview_text text_body
        ShotHistoryEditor_purge_confirm page_title danger
        ShotHistoryEditor_purge_confirm purge_instructions text_body
        ShotHistoryEditor_purge_confirm purge_error_text danger
        ShotHistoryEditor_purge_result page_title text_body
        ShotHistoryEditor_purge_result purge_result_text text_body
    } {
        catch { dui item config $p $tag -fill $L($role) }
    }
    # Card rows on the main page.
    for {set i 0} {$i < 12} {incr i} {
        catch { dui item config ShotHistoryEditor_settings row${i}_bg \
            -fill $L(card_bg) -outline $L(card_outline) }
        catch { dui item config ShotHistoryEditor_settings row${i}_line1 -fill $L(text_hi) }
        catch { dui item config ShotHistoryEditor_settings row${i}_line2 -fill $L(text_body) }
        catch { dui item config ShotHistoryEditor_settings row${i}_line3 -fill $L(text_mut) }
        catch { dui item config ShotHistoryEditor_trash row${i}_text -fill $L(text_body) }
        catch { dui item config ShotHistoryEditor_recent row${i}_text -fill $L(text_body) }
        catch { dui item config ShotHistoryEditor_reconcile row${i}_text -fill $L(text_body) }
    }
    # Entries (Tk widgets; their attached labels are -lbl sub-items).
    catch { dui item config ShotHistoryEditor_delete_confirm confirm_entry \
        -bg $L(entry_danger_bg) -foreground $L(danger) }
    catch { dui item config ShotHistoryEditor_delete_confirm confirm_entry-lbl -fill $L(text_body) }
    catch { dui item config ShotHistoryEditor_purge_confirm purge_entry \
        -bg $L(entry_danger_bg) -foreground $L(danger) }
    catch { dui item config ShotHistoryEditor_purge_confirm purge_entry-lbl -fill $L(text_body) }
    catch { dui item config ShotHistoryEditor_edit_preview new_value \
        -bg $L(entry_bg) -foreground $L(value_blue) }
    catch { dui item config ShotHistoryEditor_edit_preview new_value-lbl -fill $L(text_body) }
    # Buttons: shape fills (labels stay white; three danger labels follow).
    foreach {p tags} {
        ShotHistoryEditor_settings {mode_btn prev_page next_page bar_left bar_right btn_theme
                                    row0_btn row1_btn row2_btn row3_btn row4_btn}
        ShotHistoryEditor_advanced {source_inspector diagnostics help_guide trash_restore reconcile tidy back}
        ShotHistoryEditor_delete_review {cancel continue_btn}
        ShotHistoryEditor_delete_confirm {cancel confirm_delete}
        ShotHistoryEditor_delete_result {page_done}
        ShotHistoryEditor_edit_confirm {cancel save_change}
        ShotHistoryEditor_edit_result {page_done}
        ShotHistoryEditor_trash {page_done back trash_prev_page trash_next_page empty_preview
                                 row0_restore row1_restore row2_restore row3_restore
                                 row4_restore row5_restore row6_restore row7_restore}
        ShotHistoryEditor_recent {page_done back
                                  row0_open row1_open row2_open row3_open
                                  row4_open row5_open row6_open}
        ShotHistoryEditor_detail {page_done back prev_page next_page edit_preview}
        ShotHistoryEditor_edit_preview {next_field preview_change save_change page_done back}
        ShotHistoryEditor_diagnostics {back prev_page next_page page_done}
        ShotHistoryEditor_help {back prev_page next_page page_done}
        ShotHistoryEditor_reconcile {page_done back reconcile_prev_page reconcile_next_page
                                     row0_unhide row1_unhide row2_unhide row3_unhide
                                     row4_unhide row5_unhide}
        ShotHistoryEditor_empty_preview {back prev_page next_page page_done empty_now}
        ShotHistoryEditor_purge_confirm {cancel purge_confirm_btn}
        ShotHistoryEditor_purge_result {page_done}
    } {
        foreach t $tags {
            catch { dui item config $p ${t}-btn \
                -fill $L(btn_fill) -outline $L(btn_fill) \
                -disabledfill $L(btn_disabled_fill) -disabledoutline $L(btn_disabled_fill) }
        }
    }
    foreach {p t} {
        ShotHistoryEditor_delete_confirm confirm_delete
        ShotHistoryEditor_edit_confirm save_change
        ShotHistoryEditor_edit_preview save_change
        ShotHistoryEditor_empty_preview empty_now
        ShotHistoryEditor_purge_confirm purge_confirm_btn
    } {
        catch { dui item config $p ${t}-lbl -fill $L(danger) }
    }
}

proc ::plugins::ShotHistoryEditor::_init_layout {} {
    variable L
    array unset L
    array set L {}

    # Virtual base resolution: fixed constants, not detected. Every token
    # below keeps its exact v0.3.1 formula; only this input changed.
    set sw 2560
    set sh 1600
    set scale [expr {double($sh) / 800.0}]

    # Real physical screen, used ONLY for font pixel sizes (see note above).
    set psw 1340
    set psh 800
    catch { set psw [winfo screenwidth .] }
    catch { set psh [winfo screenheight .] }
    if {$psw <= 1} { set psw 1340 }
    if {$psh <= 1} { set psh 800 }
    set font_scale [expr {double($psh) / 800.0}]

    set L(screen_w) $sw
    set L(screen_h) $sh
    set L(scale) $scale
    set L(physical_screen_w) $psw
    set L(physical_screen_h) $psh
    set L(font_scale) $font_scale

    # Spacing tokens (reference px at 1340x800, scaled by screen factor).
    foreach {tok ref} {xs 6 sm 10 md 16 lg 24 xl 32 xxl 48} {
        set L($tok) [expr {int(round($ref * $scale))}]
    }

    set L(margin) [expr {int(max($sw * 0.036, 32))}]
    set L(left_x) $L(margin)
    set L(right_x) [expr {$sw - $L(margin)}]
    set L(content_w) [expr {$L(right_x) - $L(left_x)}]
    set L(label_col_w) [expr {int(round(420 * $scale))}]
    set L(value_x) [expr {$L(left_x) + $L(label_col_w) + $L(lg)}]

    set L(card_w) $L(content_w)
    set L(card_h) [expr {int(round(96 * $scale))}]
    set L(card_gap) [expr {int(round(12 * $scale))}]
    set L(card_pad_x) [expr {int(round(18 * $scale))}]
    set L(card_pad_y) [expr {int(round(14 * $scale))}]
    set L(card_line1_dy) [expr {int(round(30 * $scale))}]
    set L(card_line2_dy) [expr {int(round(56 * $scale))}]
    set L(card_line3_dy) [expr {int(round(80 * $scale))}]

    set L(btn_w_std) [expr {int(round(200 * $scale))}]
    set L(btn_w_wide) [expr {int(round(240 * $scale))}]
    set L(btn_h) [expr {int(max(60, round(60 * $scale)))}]
    set L(card_btn_w) [expr {int(round(150 * $scale))}]
    set L(card_btn_h) [expr {int(max(56, round(56 * $scale)))}]
    set L(btn_radius) [expr {int(round(12 * $scale))}]
    set L(card_radius) $L(btn_radius)

    # v0.5.4: self-contained colors (BeanScanner v0.1.2 pattern). The plugin
    # paints its own page background and its button style carries explicit
    # fills, so nothing depends on which dui theme or skin palette happens
    # to be current when this plugin loads or renders.
    # v0.8.0: every color token lives in _apply_palette (light / dark, per
    # settings(theme)) so the sun/moon toggle can swap it at runtime.
    _apply_palette
    set L(btn_label_fill) white

    set L(header_y1) [expr {int(round(96 * $scale))}]
    # Fixed header baselines (not fractions of header_y1) so title/subtitle
    # always keep at least an "md" gap between their text blocks -- an
    # earlier draft used header_y1*0.42/0.8 fractions which left only ~3px
    # between the two lines at some scales, effectively touching.
    set L(header_title_y) [expr {int(round(28 * $scale))}]
    set L(header_subtitle_y) [expr {int(round(72 * $scale))}]
    set L(header_solo_title_y) [expr {int(round(48 * $scale))}]
    set L(toolbar_y0) [expr {int(round(104 * $scale))}]
    set L(toolbar_y1) [expr {int(round(152 * $scale))}]
    set L(list_top) [expr {int(round(168 * $scale))}]
    set L(bar_y0) [expr {int(round(716 * $scale))}]
    set L(bar_y1) [expr {int(round(776 * $scale))}]

    # Pixel-exact fonts (Tk convention: negative -size means pixels, not points),
    # each floored at 16px per spec. Only these six sizes are used anywhere.
    # Fallbacks to the pre-existing named Helv_* fonts are set first so every
    # L(font_*) key is always valid even if the "font" command is unavailable.
    #
    # IMPORTANT (v0.3.2/v0.3.3): every one of these fonts -- including
    # font_button -- is scaled by `font_scale` (real physical screen), NOT
    # `scale` (virtual coordinate space). v0.3.1's bug was using `scale` for
    # these. v0.3.2 fixed the five text fonts but left button labels on a
    # `dui aspect set -type dbutton_label {font_size ...}` call using `scale`
    # -- that aspect key turned out not to be honored by the framework on
    # the tablet (buttons still rendered at a small skin-default size), which
    # is a different, second code path from the raw-Tk-font one card text
    # uses. Fix: font_button is now a real Tk font object on `font_scale`,
    # same basis as font_primary, passed directly via `-label_font` on every
    # `dui add dbutton` call (a per-instance override confirmed to work in
    # plugins/visualizer_upload/plugin.tcl:467,505-507) instead of relying on
    # the aspect style's font_size key.
    set L(font_title) Helv_20_bold
    set L(font_section) Helv_18_bold
    set L(font_primary) Helv_10_bold
    set L(font_body) Helv_9
    set L(font_caption) Helv_8
    set L(font_button) Helv_10_bold

    catch {
        foreach {name ref bold} {title 40 1 section 24 1 primary 22 1 body 19 0 caption 16 0 button 20 1} {
            set px [expr {int(max(16, round($ref * $font_scale)))}]
            set fname "SHE_$name"
            set weight [expr {$bold ? "bold" : "normal"}]
            if {[lsearch -exact [font names] $fname] >= 0} {
                font configure $fname -size [expr {-$px}] -weight $weight
            } else {
                font create $fname -family Helvetica -size [expr {-$px}] -weight $weight
            }
            set L(font_$name) $fname
        }
    }

    # v0.8.0: icon font for the theme toggle's sun/moon face (the app's
    # own FA6 Pro file, dui's loader; text fallback when unavailable).
    # v0.8.4: line height of the caption font in VIRTUAL units, for stacking
    # a text line above another item (the Trash / Source Inspector column
    # header sat 32 virtual px above row 0 while the caption line is 38
    # tall: tablet-found overlap, verify.sh pass 02). `font metrics` answers
    # in physical px; the y axis maps physical -> virtual by sh/psh. The
    # fallback is 1.25 x the 16 px reference when no font system exists.
    set L(caption_h) [expr {int(ceil(16 * 1.25 * $scale))}]
    catch {
        set lh [font metrics $L(font_caption) -linespace]
        if {$lh > 0} { set L(caption_h) [expr {int(ceil($lh * double($sh) / $psh))}] }
    }

    set L(have_icons) 0
    set L(font_icon) $L(font_button)
    catch {
        set fam [dui::font::add_or_get_familyname "Font Awesome 6 Pro-Regular-400.otf"]
        if {$fam ne ""} {
            set px [expr {int(max(16, round(26 * $font_scale)))}]
            if {[lsearch -exact [font names] SHE_icon] >= 0} {
                font configure SHE_icon -family $fam -size [expr {-$px}]
            } else {
                font create SHE_icon -family $fam -size [expr {-$px}]
            }
            set L(font_icon) SHE_icon
            set L(have_icons) 1
        }
    }

    # Shared button aspect style: same corner radius everywhere (B4). Label
    # font is set directly per-instance via -label_font (see note above), so
    # no dbutton_label font aspect is defined. Per-instance calls still pass
    # their own -bwidth/-bheight/-label.
    #
    # -theme default is REQUIRED (BeanScanner v0.1.2 lesson, reconfirmed for
    # this plugin in v0.5.4): "dui aspect set" writes into the *current*
    # theme, and by the time this plugin loads, Lumen's DYE integration has
    # switched the current theme to DYE_Lumen (skins/Lumen/skin.tcl:1831,
    # confirmed in the app log: GrindAdvisor loads before that switch, this
    # plugin after it). Aspect lookup falls back from a named theme to
    # default, never the other way, so a style registered into DYE_Lumen is
    # invisible to these -theme default pages -- no button shape was drawn
    # at all. Explicit fills make the style independent of load order.
    catch {
        dui aspect set -theme default -type dbutton -style she_btn [list \
            shape round radius $L(btn_radius) \
            fill $L(btn_fill) disabledfill $L(btn_disabled_fill)]
        dui aspect set -theme default -type dbutton_label -style she_btn [list \
            fill $L(btn_label_fill) disabledfill "#999999"]
    }
}

# Full-page background, drawn as the first item of every page so the
# plugin's contrast never depends on which skin theme happens to be active
# (fpdialog pages otherwise show whatever page or canvas lies beneath them
# -- under Lumen's dark mode that is near-black, which made this plugin's
# dark-on-light design unreadable). Copied verbatim from BeanScanner's
# proven _page_bg.
proc ::plugins::ShotHistoryEditor::_page_bg {page} {
    variable L
    dui add canvas_item rect $page 0 0 $L(screen_w) $L(screen_h) \
        -fill $L(page_bg) -outline $L(page_bg) -tags page_bg
}

# Draws a rounded-rectangle card backdrop through the dui canvas_item wrapper
# using the standard Tk smoothed-polygon technique (no rounded-rect primitive
# was found anywhere in this workspace's plugins, so this is the new helper
# requested by the spec; reused by every card/panel background in this file).
proc ::plugins::ShotHistoryEditor::rounded_rect {page x1 y1 x2 y2 radius args} {
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

proc ::plugins::ShotHistoryEditor::preload_pages {} {
    package require de1_dui 1.0
    catch { package require sqlite3 }
    catch { package require json }
    # v0.8.0: the theme choice is this plugin's first persisted setting.
    catch { plugins load_settings ShotHistoryEditor }
    variable settings
    if {![info exists settings(theme)] || $settings(theme) ni {light dark}} {
        set settings(theme) light
    }
    _init_layout

    dui page add ShotHistoryEditor_settings -namespace true -theme default -type fpdialog
    dui page add ShotHistoryEditor_advanced -namespace true -theme default -type fpdialog
    dui page add ShotHistoryEditor_delete_review -namespace true -theme default -type fpdialog
    dui page add ShotHistoryEditor_delete_confirm -namespace true -theme default -type fpdialog
    dui page add ShotHistoryEditor_delete_result -namespace true -theme default -type fpdialog
    dui page add ShotHistoryEditor_trash -namespace true -theme default -type fpdialog
    dui page add ShotHistoryEditor_recent -namespace true -theme default -type fpdialog
    dui page add ShotHistoryEditor_detail -namespace true -theme default -type fpdialog
    dui page add ShotHistoryEditor_edit_preview -namespace true -theme default -type fpdialog
    dui page add ShotHistoryEditor_edit_confirm -namespace true -theme default -type fpdialog
    dui page add ShotHistoryEditor_edit_result -namespace true -theme default -type fpdialog
    dui page add ShotHistoryEditor_diagnostics -namespace true -theme default -type fpdialog
    dui page add ShotHistoryEditor_help -namespace true -theme default -type fpdialog
    dui page add ShotHistoryEditor_reconcile -namespace true -theme default -type fpdialog
    dui page add ShotHistoryEditor_empty_preview -namespace true -theme default -type fpdialog
    dui page add ShotHistoryEditor_purge_confirm -namespace true -theme default -type fpdialog
    dui page add ShotHistoryEditor_purge_result -namespace true -theme default -type fpdialog
    return ShotHistoryEditor_settings
}

proc ::plugins::ShotHistoryEditor::open_page {page} {
    foreach cmd [list \
        [list dui page open_dialog $page] \
        [list dui page load $page] \
        [list dui page show $page]] {
        if {![catch { uplevel #0 $cmd }]} { return 1 }
    }
    catch { msg "ShotHistoryEditor: could not open page $page" }
    return 0
}

# ---------------------------------------------------------------------------
# v0.5.2 -- safe Done/Back navigation against the confirmed de1app-core
# page_stack bug (root cause verified for GrindAdvisor v1.8.8, from
# de1app-core/dui.tcl; see GrindAdvisor/CHANGELOG.md's "v1.8.8" entry for
# the full trace). `::dui::page::load`'s "Handle page stack" block resets
# `page_stack` to a single entry every time a page of type "default" is
# shown -- e.g. the flow-monitor page shown while a flush/rinse/steam/clean/
# etc. runs -- even while an `fpdialog` page (every page in this plugin) is
# current, because the framework's "only one dialog page visible" guard
# only checks type "dialog", not "fpdialog". When this plugin's page is
# re-shown afterwards, it gets pushed onto that freshly-wiped stack, so
# `dui page close_dialog` (which navigates to "previous" in page_stack)
# lands on the flow page instead of this plugin's real parent page -- not a
# bug specific to GrindAdvisor, but how this DE1app build's page_stack
# behaves for any fpdialog left open across a flush/rinse/steam
# interruption, with no self-healing. This class of bug is different from
# (and layered on top of) the v0.4.1/v0.5.1 multi-level-stack bugs already
# fixed above: those were about `close_dialog` only popping one level of a
# plugin-internal flow; this one is about `close_dialog` trusting a stack
# that an *external* page change silently corrupted.
#
# Fix: two complementary mechanisms, split by destination (v0.5.3 -- the
# v0.5.2 version of this fix used `dui page load` for BOTH cases, which
# broke multi-level returns; see _return_to_page's note below for the core
# truncation bug that makes direct load unsafe for stacked ancestors).
# - Exiting the plugin (Settings Done): _navigate_done with the outside
#   page captured by _capture_return_page. Loading a default-type page
#   resets the core's page_stack entirely (dui.tcl ~line 6464), so this
#   exit is clean regardless of what a flush interruption did to the stack.
# - Returning to an ancestor within this plugin's own dialog stack:
#   _return_to_page, which unwinds one close_dialog at a time (the only
#   stack shape this core truncates correctly) and falls back to
#   _navigate_done's validated load only if the stack is corrupted.
proc ::plugins::ShotHistoryEditor::_is_transient_name {name} {
    if {$name eq ""} { return 1 }
    return [regexp -nocase {espresso|steam|water|rinse|flush|clean|cleaning|descale|purge} $name]
}

# Called from the Settings page's own show{page_to_hide page_to_show} (the
# only page in this plugin whose Done target is dynamic rather than a
# hardcoded ancestor name). page_to_hide is skipped whenever it looks like a
# flow/monitor page name, so a flush/rinse/steam interruption's re-show can
# never clobber the last legitimate return target.
#
# v0.5.3 bugfix: also skip this plugin's OWN pages. Returning to Settings
# from a sub-flow (e.g. Cancel on Delete Step 2) re-shows Settings with
# page_to_hide = that sub-page; v0.5.2 captured it, so the next Settings
# Done loaded the sub-page again instead of leaving the plugin (tablet-
# reproduced: Done ping-ponged back to the Step 2 confirm page). Only a
# page that is neither ours nor a flow screen -- i.e. the genuine outside
# page the plugin was opened from -- is a valid exit target.
proc ::plugins::ShotHistoryEditor::_capture_return_page {page_to_hide} {
    variable _settings_return_page
    if {$page_to_hide eq ""} { return }
    if {[string match "ShotHistoryEditor_*" $page_to_hide]} { return }
    if {![_is_transient_name $page_to_hide]} {
        set _settings_return_page $page_to_hide
    }
}

proc ::plugins::ShotHistoryEditor::_navigate_done {target} {
    set ok 0
    if {$target ne "" && ![_is_transient_name $target]} {
        catch { set ok [dui page exists $target] }
    }
    # v0.8.3: the close_dialog fallbacks used to be bare catches; a failed
    # exit is now logged (CLAUDE.md: navigation errors must be visible).
    if {$ok} {
        if {[catch { uplevel #0 [list dui page load $target] } err]} {
            msg -ERROR "ShotHistoryEditor: navigating to $target failed: $err"
            if {[catch { dui page close_dialog } err2]} {
                msg -ERROR "ShotHistoryEditor: close_dialog fallback failed: $err2"
            }
        }
    } else {
        if {[catch { dui page close_dialog } err]} {
            msg -ERROR "ShotHistoryEditor: close_dialog failed (no valid return page '$target'): $err"
        }
    }
}

# v0.5.3 bugfix -- returns to an ancestor page of this plugin's own dialog
# stack. v0.5.2 did this with a single `dui page load $target`, trusting the
# core to truncate the stale stack entries above $target. Reading the actual
# truncation code (de1app-core/dui.tcl, "Handle page stack" block, ~line
# 6470) shows why that failed on the tablet: it truncates with
#   dict unset page_stack {*}[lrange [dict keys $page_stack] idx+1 end]
# and multi-argument `dict unset` treats the extra keys as a NESTED KEY
# PATH, not a list of top-level keys (verified empirically with tclsh
# against a simulated stack). So truncating exactly 1 stale page works,
# 2 stale pages silently does nothing (stale entries stay stacked), and 3+
# throws, aborting the whole load -- which is exactly the tablet behavior:
# Done on Delete Result (3 stale pages) errored into the close_dialog
# fallback and landed on Step 2; Cancel on Step 2 (2 stale pages) looked
# fine but left review+confirm buried in the stack to resurface later.
#
# Fix: unwind ONE level at a time with `dui page close_dialog` -- each step
# is the 1-stale-page case the core truncates correctly -- until the target
# is current. Bounded, with a progress check, and it stops immediately if
# the current page is no longer one of ours (e.g. a flush interruption
# corrupted the stack), falling back to _navigate_done's validated direct
# load in that case. Failures are logged via msg, never swallowed silently.
proc ::plugins::ShotHistoryEditor::_return_to_page {target} {
    set prev ""
    for {set i 0} {$i < 10} {incr i} {
        set cur ""
        catch { set cur [dui page current] }
        if {$cur eq $target} { return }
        if {![string match "ShotHistoryEditor_*" $cur]} { break }
        if {$cur eq $prev} { break }
        set prev $cur
        if {[catch { dui page close_dialog } err]} {
            catch { msg "ShotHistoryEditor: close_dialog failed returning to $target: $err" }
            break
        }
    }
    set cur ""
    catch { set cur [dui page current] }
    if {$cur ne $target} {
        _navigate_done $target
    }
}

proc ::plugins::ShotHistoryEditor::_homedir {} {
    if {[llength [info commands homedir]]} {
        return [homedir]
    }
    variable plugin_dir
    return [file dirname [file dirname $plugin_dir]]
}

proc ::plugins::ShotHistoryEditor::_plugins_dir {} {
    if {[llength [info commands plugin_directory]]} {
        set pd [plugin_directory]
        if {[file pathtype $pd] eq "absolute"} { return $pd }
        return [file join [_homedir] $pd]
    }
    variable plugin_dir
    return [file dirname $plugin_dir]
}

proc ::plugins::ShotHistoryEditor::sdb_path {} {
    set candidates [list \
        [file join [_plugins_dir] SDB shots.db] \
        [file join [_homedir] plugins SDB shots.db]]
    foreach p $candidates {
        if {[file isfile $p]} { return $p }
    }
    return [lindex $candidates 0]
}

proc ::plugins::ShotHistoryEditor::history_path {} {
    return [file join [_homedir] history]
}

proc ::plugins::ShotHistoryEditor::history_v2_path {} {
    return [file join [_homedir] history_v2]
}

# ---------------------------------------------------------------------------
# Pass 4.0 -- soft delete: trash folder, manifest, and audit log.
#
# Step 1 finding (see README/CHANGELOG for the full writeup): nothing in this
# workspace indexes, watches, or rebuilds from history_v2/*.json filenames --
# grepping plugins/SDB/SDB.tcl, plugins/GrindAdvisor/GrindAdvisor.tcl, and
# plugins/visualizer_upload/plugin.tcl for "history_v2" or ".json" returns no
# matches at all, and history_v2/ itself contains no index/manifest file, only
# loose per-shot json files. SDB's own resync/rebuild path
# (::plugins::SDB::populate/::plugins::SDB::create) is driven entirely from
# history/*.shot. Given that, and per this plugin's own docs ("history_v2 is
# secondary; verify safety before touching it"), this pass moves BOTH the
# .shot and its matching .json (when present) together into the same trash
# batch -- there is no functional reason to leave an orphaned json behind
# with no consumer, and leaving one on disk would only be clutter.
# ---------------------------------------------------------------------------

proc ::plugins::ShotHistoryEditor::trash_dir {} {
    return [file join [_plugins_dir] ShotHistoryEditor trash]
}

proc ::plugins::ShotHistoryEditor::trash_manifest_path {} {
    return [file join [_plugins_dir] ShotHistoryEditor trash_manifest.txt]
}

proc ::plugins::ShotHistoryEditor::delete_log_path {} {
    return [file join [_plugins_dir] ShotHistoryEditor delete_log.txt]
}

# Filenames here always originate from SDB's own `filename` column (never
# free-typed by a user), but this plugin never trusts that fully: reject
# anything that looks like a path or a traversal attempt before it is ever
# used to build a move destination.
proc ::plugins::ShotHistoryEditor::_safe_filename {fn} {
    if {$fn eq ""} { return 0 }
    if {[string match {*[/\\]*} $fn]} { return 0 }
    if {[string first ".." $fn] >= 0} { return 0 }
    return 1
}

proc ::plugins::ShotHistoryEditor::_new_batch_id {} {
    return [format "%04x" [expr {int(rand()*65536)}]]
}

# ---------------------------------------------------------------------------
# Pass 5.0 -- real metadata save: backups, edit manifest, audit log.
#
# Step 1 findings (see README/CHANGELOG for the full writeup):
#
# a) .shot format: a flat "key value" line per top-level entry, plus one
#    `settings {` ... `}` block containing the user-facing metadata as
#    tab-indented "key value" lines in the SAME flat style. Inspecting the
#    3 sample files in history/*.shot shows the settings{} block itself
#    contains a NESTED sub-value (`read_only_backup {...}`, a backup copy of
#    prior settings) that spans many lines and is NOT balanced within a
#    single line -- a naive scan for the first bare closing-brace line (which is
#    exactly what this plugin's own read_legacy_settings/_parse_settings_file
#    already does, and is harmless for reading only because every editable
#    field's key happens to sort alphabetically before "read_only_backup")
#    would stop partway through the real settings{} block. That is fine for
#    read-only display, but WRITING against a truncated boundary risks
#    corrupting/truncating the file, so the write path below tracks brace
#    depth properly (_settings_block_bounds/_find_settings_key_line) to find
#    the block's true end and the exact target key's line, instead of
#    reusing the existing (unmodified, still fine for reading) parser.
# b) plugins/SDB/SDB.tcl:2948 calls a core app proc `modify_shot_file $path
#    new_settings` (via `get_shot_file_path`) to edit categories in a .shot
#    file -- proving the app itself considers targeted .shot-file edits a
#    normal, supported operation. Neither proc's implementation exists
#    anywhere in this workspace, and SDB's call site immediately follows it
#    with `db eval "UPDATE ..."` against SDB in the same breath (SDB.tcl:
#    2954-2973), which this plugin must never do -- so, per "do not guess
#    the DE1app plugin API", this pass does not call modify_shot_file and
#    instead implements its own self-contained, verified read-modify-
#    temp-write-rename cycle below, touching only the one targeted
#    settings{} line and nothing else in the file.
# c) history_v2/<filename>.json is NOT written in this pass. Per the same
#    evidence as the delete pass (no plugin or manifest in this workspace
#    reads/depends on it), and because its meta.bean/meta.grinder structure
#    uses different key names than the .shot settings block (so keeping it
#    in sync would require a second, separate write path with no proven
#    need), this pass leaves it untouched. This means history_v2 can show a
#    stale value for an edited field until/unless a future pass addresses
#    it -- documented in README/Help, same as the existing SDB-staleness
#    note.
# d) SDB is never written to, so the card list and Detail page's SDB column
#    would otherwise keep showing the pre-edit value. Reusing the delete
#    pass's manifest-overlay pattern: an edit_manifest.txt entry per saved
#    field is read back and overlaid onto SDB-sourced values before display
#    (_all_edit_overlays/_apply_edit_overlay), so the user sees their
#    correction immediately even though SDB itself is untouched and may
#    resync on its own.
# ---------------------------------------------------------------------------

proc ::plugins::ShotHistoryEditor::backups_dir {} {
    return [file join [_plugins_dir] ShotHistoryEditor backups]
}

proc ::plugins::ShotHistoryEditor::edit_manifest_path {} {
    return [file join [_plugins_dir] ShotHistoryEditor edit_manifest.txt]
}

proc ::plugins::ShotHistoryEditor::edit_log_path {} {
    return [file join [_plugins_dir] ShotHistoryEditor edit_log.txt]
}

# Tcl-list-safe quoting for a single value being written back into a
# "key value" settings line (mirrors how this file format already quotes
# multi-word/list values, e.g. "chart_dashes_espresso_weight {2 1}").
proc ::plugins::ShotHistoryEditor::_tcl_quote_value {v} {
    return [list $v]
}

# Finds the [start end] line indices (0-based, inclusive) of the outermost
# `settings { ... }` block by tracking brace depth across the whole file,
# rather than stopping at the first bare closing-brace line -- see finding (a) above.
# Returns {-1 -1} if no settings{} block is found.
proc ::plugins::ShotHistoryEditor::_settings_block_bounds {lines} {
    set n [llength $lines]
    set start -1
    set depth 0
    for {set i 0} {$i < $n} {incr i} {
        set line [lindex $lines $i]
        if {$start < 0} {
            if {[string trim $line] eq "settings \{"} {
                set start $i
                set o [regexp -all -- {\{} $line]
                set c [regexp -all -- {\}} $line]
                set depth [expr {$o - $c}]
                if {$depth <= 0} { return [list $start $i] }
            }
            continue
        }
        set o [regexp -all -- {\{} $line]
        set c [regexp -all -- {\}} $line]
        incr depth [expr {$o - $c}]
        if {$depth <= 0} { return [list $start $i] }
    }
    return [list -1 -1]
}

# Finds the line index of $key's entry directly inside the settings{} block
# (depth exactly 1, i.e. not nested inside a sub-value like
# read_only_backup), scanning the WHOLE block and keeping the LAST match --
# matching how _parse_settings_file's `dict set values $key $val` naturally
# lets a later occurrence win. Returns -1 if not found at depth 1.
proc ::plugins::ShotHistoryEditor::_find_settings_key_line {lines start end key} {
    set found -1
    set depth 1
    for {set i [expr {$start + 1}]} {$i < $end} {incr i} {
        set line [lindex $lines $i]
        set trimmed [string trim $line]
        if {$depth == 1 && $trimmed ne ""} {
            if {![catch { lindex $trimmed 0 } k] && $k eq $key} {
                set found $i
            }
        }
        set o [regexp -all -- {\{} $line]
        set c [regexp -all -- {\}} $line]
        incr depth [expr {$o - $c}]
    }
    return $found
}

proc ::plugins::ShotHistoryEditor::_append_edit_manifest {ts filename field old_value new_value backup_path} {
    catch {
        set fh [open [edit_manifest_path] a]
        fconfigure $fh -encoding utf-8
        puts $fh "$ts|$filename|$field|$old_value|$new_value|$backup_path"
        close $fh
    }
}

proc ::plugins::ShotHistoryEditor::_append_edit_log {ts filename field old_value new_value backup_path status} {
    catch {
        set fh [open [edit_log_path] a]
        fconfigure $fh -encoding utf-8
        puts $fh "$ts EDIT $status filename=$filename field=$field old=[_display $old_value] new=[_display $new_value] backup=$backup_path"
        close $fh
    }
}

proc ::plugins::ShotHistoryEditor::_edit_manifest_lines {} {
    set path [edit_manifest_path]
    if {![file isfile $path]} { return {} }
    set lines {}
    if {[catch {
        set fh [open $path r]
        fconfigure $fh -encoding utf-8
        while {[gets $fh line] >= 0} {
            set line [string trim $line]
            if {$line ne ""} { lappend lines $line }
        }
        close $fh
    }]} {
        catch { close $fh }
    }
    return $lines
}

# Manifest line format (one per saved field): timestamp|filename|field|old_value|new_value|backup_path
proc ::plugins::ShotHistoryEditor::_edit_manifest_records {} {
    set records {}
    foreach line [_edit_manifest_lines] {
        set parts [split $line "|"]
        if {[llength $parts] != 6} { continue }
        lassign $parts ts filename field old_value new_value backup_path
        lappend records [dict create ts $ts filename $filename field $field \
            old_value $old_value new_value $new_value backup_path $backup_path]
    }
    return $records
}

# Builds filename -> {field -> latest edited value} from the whole edit
# manifest once, so a list refresh doesn't re-parse the manifest per row
# (same shape as _deleted_filenames_dict for the trash manifest).
proc ::plugins::ShotHistoryEditor::_all_edit_overlays {} {
    set overlays [dict create]
    foreach rec [_edit_manifest_records] {
        set fn [dict get $rec filename]
        if {![dict exists $overlays $fn]} { dict set overlays $fn [dict create] }
        dict set overlays $fn [dict get $rec field] [dict get $rec new_value]
    }
    return $overlays
}

# Overlays any edited field values onto an SDB-sourced row dict so the user
# sees their correction immediately, even though SDB itself is never
# written to and may show the stale value until it resyncs on its own.
proc ::plugins::ShotHistoryEditor::_apply_edit_overlay {row overlays} {
    set filename [_dget $row filename]
    if {$filename eq "" || ![dict exists $overlays $filename]} { return $row }
    dict for {field value} [dict get $overlays $filename] {
        if {[dict exists $row $field]} { dict set row $field $value }
    }
    return $row
}

# Real write path: modifies ONLY the one targeted settings{} key line of
# history/<filename>.shot, preserving every other byte (including the raw
# data arrays, which live entirely outside the settings{} block and are
# never touched). Backs up before writing, verifies the temp file with the
# proven _parse_settings_file reader before ever touching the original, and
# additionally re-verifies after the rename with an automatic restore-from-
# backup as a second safety net (per the requested design). Never calls
# `file delete`: a failed pre-rename verification simply leaves the temp
# file behind (harmless, and the original was never touched); a failed
# post-rename verification restores via `file rename` from the backup.
# Tell Grind Advisor that this plugin changed what is on disk, so its
# recommendation follows without anyone having to know that it should. Its
# refresh_from_history asks SDB to resync, drops its per-bag cache, recomputes
# for the loaded bag and re-saves. Returns its human-readable summary, or ""
# when it is not installed or the call failed.
#
# Guarded on both existence and errors: by the time this is called THIS
# plugin's own work has already succeeded, and it must report success whatever
# another plugin does.
#
# Answering the obvious question -- why not refresh on every recommendation
# lookup instead? Because the resync rescans the whole history folder. Once
# per edit or per delete batch is the right moment to spend that; a display
# tick is not.
#
# v0.6.3: this was inline in perform_metadata_edit and nowhere else, so an
# edit updated the recommendation and a DELETE did not -- owner-reported from
# the tablet, the same symptom as the v0.6.0 edit bug and the same cause one
# path over. Deleting needs no mtime trick, unlike editing: SDB's populate
# flags a vanished file `removed=1` by absence alone, and Grind Advisor
# already filters that column in its SQL. The notification was the only
# missing link. Kept as ONE proc so the three paths cannot drift apart.
#
# `what` is a short phrase for the log line, e.g. "the edit", "the delete".
proc ::plugins::ShotHistoryEditor::_refresh_grind_advisor {what} {
    if {[info procs ::plugins::GrindAdvisor::refresh_from_history] eq ""} { return "" }
    set note ""
    if {[catch { set note [::plugins::GrindAdvisor::refresh_from_history] } err]} {
        catch { msg -NOTICE "ShotHistoryEditor: Grind Advisor refresh failed after $what: $err" }
        return ""
    }
    catch { msg -INFO "ShotHistoryEditor: Grind Advisor refreshed after $what: $note" }
    return $note
}

# Everything downstream that should follow a change to history/, in order
# (v0.7.0). Called wherever _refresh_grind_advisor used to be called alone.
#
#   1. Grind Advisor first: its refresh_from_history resyncs SDB, which the
#      next step reads.
#   2. The Lumen skin second: refresh_after_history_change reloads the home
#      page's last-shot chart and card from the (possibly new) newest shot
#      file, and rebuilds the bag cycler from the freshly-resynced SDB.
#
# Each is guarded on existence -- a different skin, or no Grind Advisor,
# simply skips its step -- and on errors, because this plugin's own work has
# already succeeded by the time this runs. Returns Grind Advisor's summary
# for the result pages, same contract as _refresh_grind_advisor.
proc ::plugins::ShotHistoryEditor::_notify_downstream {what} {
    set note [_refresh_grind_advisor $what]
    if {[info procs ::lumen::refresh_after_history_change] ne ""} {
        if {[catch { ::lumen::refresh_after_history_change } err]} {
            catch { msg -NOTICE "ShotHistoryEditor: Lumen refresh failed after $what: $err" }
        } else {
            catch { msg -INFO "ShotHistoryEditor: Lumen home refreshed after $what" }
        }
    }
    return $note
}

proc ::plugins::ShotHistoryEditor::perform_metadata_edit {filename field new_value} {
    variable editable_fields

    set new_value [string trim $new_value]
    if {$new_value eq ""} {
        return [dict create ok 0 message "New value is empty; nothing was written." \
            old_value "" new_value "" backup_path ""]
    }
    if {[lsearch -exact $editable_fields $field] < 0} {
        return [dict create ok 0 message "'$field' is not in the safe editable field list." \
            old_value "" new_value $new_value backup_path ""]
    }
    if {![_safe_filename $filename]} {
        return [dict create ok 0 message "Unsafe filename." old_value "" new_value $new_value backup_path ""]
    }
    set path [_legacy_file $filename]
    if {![file isfile $path]} {
        return [dict create ok 0 message "history/$filename.shot not found." \
            old_value "" new_value $new_value backup_path ""]
    }

    if {[catch {
        set fh [open $path r]
        fconfigure $fh -encoding utf-8 -translation lf
        set raw [read $fh]
        close $fh
    } err]} {
        catch { close $fh }
        return [dict create ok 0 message "Could not read $path: $err" \
            old_value "" new_value $new_value backup_path ""]
    }
    set had_trailing_nl [string match "*\n" $raw]
    set lines [split $raw "\n"]
    if {$had_trailing_nl} { set lines [lrange $lines 0 end-1] }

    lassign [_settings_block_bounds $lines] sstart send
    if {$sstart < 0} {
        return [dict create ok 0 message "No settings {} block found in $path." \
            old_value "" new_value $new_value backup_path ""]
    }
    set key_idx [_find_settings_key_line $lines $sstart $send $field]
    if {$key_idx < 0} {
        return [dict create ok 0 message "Field '$field' not found in the settings block of $path." \
            old_value "" new_value $new_value backup_path ""]
    }

    set orig_line [lindex $lines $key_idx]
    set trimmed [string trim $orig_line]
    set old_value [_clean_value [join [lrange $trimmed 1 end] " "]]
    if {![regexp -- {^(\s*)(\S+)} $orig_line -> ws k]} {
        return [dict create ok 0 message "Could not parse the existing '$field' line." \
            old_value $old_value new_value $new_value backup_path ""]
    }

    set new_line "$ws$field [_tcl_quote_value $new_value]"
    set new_lines [lreplace $lines $key_idx $key_idx $new_line]
    set new_content [join $new_lines "\n"]
    if {$had_trailing_nl} { append new_content "\n" }

    set ts [clock format [clock seconds] -format {%Y%m%dT%H%M%S}]
    set batch_id [_new_batch_id]
    set backup_dir [file join [backups_dir] "${ts}_${batch_id}"]
    set backup_path [file join $backup_dir "$filename.shot"]
    if {[catch { file mkdir $backup_dir } err]} {
        return [dict create ok 0 message "Could not create backup folder: $err" \
            old_value $old_value new_value $new_value backup_path ""]
    }
    if {[catch { file copy -- $path $backup_path } err]} {
        return [dict create ok 0 message "Could not create backup: $err" \
            old_value $old_value new_value $new_value backup_path ""]
    }

    set tmp_path "${path}.tmp${batch_id}"
    if {[catch {
        set th [open $tmp_path w]
        fconfigure $th -encoding utf-8 -translation lf
        puts -nonewline $th $new_content
        close $th
    } err]} {
        catch { close $th }
        return [dict create ok 0 message "Could not write temp file: $err" \
            old_value $old_value new_value $new_value backup_path $backup_path]
    }

    set verify1 [_parse_settings_file $tmp_path]
    set verify1_val [_dget [_dget $verify1 values] $field]
    if {[dict get $verify1 status] ne "found" || $verify1_val ne $new_value} {
        return [dict create ok 0 \
            message "Verification failed before saving; the original file was not touched. Temp file left at $tmp_path for inspection." \
            old_value $old_value new_value $new_value backup_path $backup_path]
    }

    if {[catch { file rename -force -- $tmp_path $path } err]} {
        return [dict create ok 0 message "Could not replace the original file: $err" \
            old_value $old_value new_value $new_value backup_path $backup_path]
    }

    set verify2 [_parse_settings_file $path]
    set verify2_val [_dget [_dget $verify2 values] $field]
    if {[dict get $verify2 status] ne "found" || $verify2_val ne $new_value} {
        catch { file rename -force -- $backup_path $path }
        _append_edit_log $ts $filename $field $old_value $new_value $backup_path \
            "FAILED post-rename verification; automatically restored from backup"
        return [dict create ok 0 \
            message "Save did not verify after writing; the original was automatically restored from backup." \
            old_value $old_value new_value $new_value backup_path $backup_path]
    }

    # v0.6.0: make the file LOOK modified, because it is.
    #
    # MEASURED ON THE TABLET, 2026-08-19. The 16:44:30 shot was edited at
    # 16:45:30 (grinder_setting 7.5 -> 8; the edit_log records it and the file
    # does contain 8). Its modification time was still 1787057093 = 16:44:53 --
    # the moment the app first WROTE the shot. `file rename` landed the
    # replacement carrying the original's timestamp: Tcl's rename falls back
    # to a copy on this storage, and Tcl's copy preserves file times.
    #
    # That silently defeats every consumer that detects edits by mtime.
    # SDB re-reads a .shot only when `file mtime > file_modification_date`
    # (SDB.tcl:2060), and SDB's stored value for that shot was 1787057093 --
    # byte-identical to the file's. Not greater, so it was skipped, and would
    # have been skipped forever. Confirmed by reading SDB read-only: the row
    # still said grinder_setting '7.5' while the file said 8.
    #
    # So SDB's OWN "Resync database to history" button could never pick up an
    # edit made by this plugin, and neither could anything downstream of it --
    # which is exactly what the owner reported about Grind Advisor.
    #
    # One `file mtime` stamp on the file this proc has just legitimately
    # rewritten. No content is touched. It is deliberately AFTER the
    # post-rename verification, so a save that failed verification and was
    # rolled back never stamps anything.
    if {[catch { file mtime $path [clock seconds] } err]} {
        catch { msg -NOTICE "ShotHistoryEditor: could not stamp the modification time of $path: $err (SDB will not see this edit until it is resynced another way)" }
    }

    _append_edit_manifest $ts $filename $field $old_value $new_value $backup_path
    _append_edit_log $ts $filename $field $old_value $new_value $backup_path "OK"

    # v0.6.0: tell Grind Advisor, so the recommendation follows the correction
    # without anyone having to know that it should. v0.6.3 shared that with
    # the delete and restore paths; v0.7.0 widened it to the Lumen home page.
    set note [_notify_downstream "the edit"]

    return [dict create ok 1 message "" old_value $old_value new_value $new_value \
        backup_path $backup_path refresh_note $note]
}

# SQL string-literal quoting (distinct from _q, which quotes identifiers).
# Used only to look up metadata for an already-known, internally-sourced
# list of filenames -- never for free-form user input.
proc ::plugins::ShotHistoryEditor::_qval {s} {
    return "'[string map {' ''} $s]'"
}

proc ::plugins::ShotHistoryEditor::_manifest_lines {} {
    set path [trash_manifest_path]
    if {![file isfile $path]} { return {} }
    set lines {}
    if {[catch {
        set fh [open $path r]
        fconfigure $fh -encoding utf-8
        while {[gets $fh line] >= 0} {
            set line [string trim $line]
            if {$line ne ""} { lappend lines $line }
        }
        close $fh
    }]} {
        catch { close $fh }
    }
    return $lines
}

# Manifest line format (one per moved FILE, not per shot):
#   timestamp|original_path|trash_path|batch_id
proc ::plugins::ShotHistoryEditor::_manifest_records {} {
    set records {}
    foreach line [_manifest_lines] {
        set parts [split $line "|"]
        if {[llength $parts] != 4} { continue }
        lassign $parts ts orig trash batch
        lappend records [dict create ts $ts orig $orig trash $trash batch $batch]
    }
    return $records
}

proc ::plugins::ShotHistoryEditor::_rewrite_manifest {records} {
    if {[catch {
        set fh [open [trash_manifest_path] w]
        fconfigure $fh -encoding utf-8
        foreach rec $records {
            puts $fh "[dict get $rec ts]|[dict get $rec orig]|[dict get $rec trash]|[dict get $rec batch]"
        }
        close $fh
    } err]} {
        catch { close $fh }
        return 0
    }
    return 1
}

proc ::plugins::ShotHistoryEditor::_append_manifest_and_log {moved batch_id ts shot_count} {
    if {[llength $moved] == 0} { return }
    catch {
        set mh [open [trash_manifest_path] a]
        fconfigure $mh -encoding utf-8
        foreach m $moved {
            lassign $m fn src dst
            puts $mh "$ts|$src|$dst|$batch_id"
        }
        close $mh
    }
    catch {
        set lh [open [delete_log_path] a]
        fconfigure $lh -encoding utf-8
        puts $lh "$ts DELETE batch=$batch_id shots=$shot_count files=[llength $moved] -> [trash_dir]/${ts}_${batch_id}"
        close $lh
    }
}

proc ::plugins::ShotHistoryEditor::_append_restore_log {batch_id restored collisions} {
    catch {
        set lh [open [delete_log_path] a]
        fconfigure $lh -encoding utf-8
        set ts [clock format [clock seconds] -format {%Y%m%dT%H%M%S}]
        puts $lh "$ts RESTORE batch=$batch_id restored_files=$restored collisions=$collisions"
        close $lh
    }
}

# Base shot filenames (no extension) currently hidden because their .shot
# was moved to trash. Rebuilt from the manifest on demand; this is what
# every shot list filters against so deleted shots disappear immediately
# even though SDB still has their rows untouched.
proc ::plugins::ShotHistoryEditor::_deleted_filenames_dict {} {
    set d [dict create]
    # v0.10.0: a manifest line that has been unhidden (reconcile manifest,
    # keyed to that exact line) hides nothing any more.
    set reconciled [_reconciled_keys_dict]
    foreach rec [_manifest_records] {
        set orig [dict get $rec orig]
        if {[string match "*.shot" $orig]} {
            if {[dict exists $reconciled [_manifest_key $rec]]} { continue }
            dict set d [file rootname [file tail $orig]] 1
        }
    }
    return $d
}

proc ::plugins::ShotHistoryEditor::deleted_shot_count {} {
    return [dict size [_deleted_filenames_dict]]
}

# ---------------------------------------------------------------------------
# v0.9.0 -- reconciliation view (READ-ONLY). A trash-manifest line hides its
# shot from every list here for as long as the line stands. If the original
# path is populated again meanwhile -- seen for real on 2026-08-24, when the
# core's flush-save bug parked a corpse under a restored shot's name; also a
# hand copy, or a restore whose manifest rewrite failed -- the shot is on
# disk and SDB re-lists it on its next resync, yet this plugin neither shows
# it nor lets you delete it, and Restore reports a collision for it. This
# pass only SURFACES that state (Advanced > Reconcile hidden shots). The
# action (un-hide, or forget the stale line) is a later, separately
# authorized pass. Nothing below writes anything.
# ---------------------------------------------------------------------------

proc ::plugins::ShotHistoryEditor::_reconcile_records {} {
    set out {}
    set reconciled [_reconciled_keys_dict]
    foreach rec [_manifest_records] {
        set orig [dict get $rec orig]
        if {![string match "*.shot" $orig]} { continue }
        if {![file exists $orig]} { continue }
        if {[dict exists $reconciled [_manifest_key $rec]]} { continue }
        set trash [dict get $rec trash]
        set trash_exists [file exists $trash]
        set disk_mtime ""
        set trash_mtime ""
        catch { set disk_mtime [file mtime $orig] }
        if {$trash_exists} { catch { set trash_mtime [file mtime $trash] } }
        lappend out [dict create filename [file rootname [file tail $orig]] orig $orig \
            trash $trash trash_exists $trash_exists ts [dict get $rec ts] \
            batch [dict get $rec batch] disk_mtime $disk_mtime trash_mtime $trash_mtime]
    }
    return [lsort -command ::plugins::ShotHistoryEditor::_batch_ts_cmp -decreasing $out]
}

proc ::plugins::ShotHistoryEditor::reconcile_count {} {
    return [llength [_reconcile_records]]
}

# SDB's view of a known list of filenames: "listed", "flagged removed", or
# absent from the dict. One read-only SELECT on the same handle path every
# other reader uses; filenames come from the manifest, never typed.
proc ::plugins::ShotHistoryEditor::_sdb_presence {filenames} {
    set presence [dict create]
    if {[llength $filenames] == 0} { return $presence }
    set db [_open_ro_db]
    if {$db eq ""} { return $presence }
    set table [_choose_source $db]
    if {$table ne ""} {
        set cols [_columns $db $table]
        if {[_has_col $cols filename]} {
            set removed_expr [expr {[_has_col $cols removed] ? [_q removed] : "NULL"}]
            set in_list [join [lmap fn $filenames { _qval $fn }] ", "]
            if {[catch {
                $db eval "SELECT [_q filename] AS fn, $removed_expr AS rm FROM [_q $table] WHERE [_q filename] IN ($in_list)" row {
                    set flagged [expr {[string is integer -strict $row(rm)] && $row(rm) != 0}]
                    dict set presence $row(fn) [expr {$flagged ? "flagged removed" : "listed"}]
                }
            } err]} {
                msg -NOTICE "ShotHistoryEditor: reconcile SDB lookup failed: $err"
            }
        }
    }
    _close_db
    return $presence
}

proc ::plugins::ShotHistoryEditor::_fmt_mtime {t} {
    if {$t eq ""} { return "unknown" }
    return [_fmt_time $t]
}

# ---------------------------------------------------------------------------
# v0.10.0 -- reconcile ACTION "Unhide" (the fifth authorized write
# capability). Writes exactly two plugin-owned files and nothing else:
#   - reconcile_manifest.txt: one appended line per unhide,
#       unhidden_at|ts|orig|batch   (ts|orig|batch = the trash-manifest line)
#   - delete_log.txt: one appended RECONCILE UNHIDE audit line.
# The trash manifest is NEVER edited by this path (so a still-present trash
# copy stays tracked and Restore keeps reporting its collision), no file is
# moved, and history/ is not touched. The marker is keyed to the exact
# manifest line, so deleting the same shot again later creates a new line
# that hides it again; that re-delete is also the in-app undo.
# ---------------------------------------------------------------------------

proc ::plugins::ShotHistoryEditor::reconcile_manifest_path {} {
    return [file join [_plugins_dir] ShotHistoryEditor reconcile_manifest.txt]
}

proc ::plugins::ShotHistoryEditor::_manifest_key {rec} {
    return "[dict get $rec ts]|[dict get $rec orig]|[dict get $rec batch]"
}

# Keys (ts|orig|batch) of every trash-manifest line that has been unhidden.
proc ::plugins::ShotHistoryEditor::_reconciled_keys_dict {} {
    set d [dict create]
    set path [reconcile_manifest_path]
    if {![file isfile $path]} { return $d }
    if {[catch {
        set fh [open $path r]
        fconfigure $fh -encoding utf-8
        while {[gets $fh line] >= 0} {
            set parts [split [string trim $line] "|"]
            if {[llength $parts] != 4} { continue }
            dict set d "[lindex $parts 1]|[lindex $parts 2]|[lindex $parts 3]" 1
        }
        close $fh
    }]} {
        catch { close $fh }
    }
    return $d
}

proc ::plugins::ShotHistoryEditor::_append_reconcile_log {now orig batch} {
    catch {
        set lh [open [delete_log_path] a]
        fconfigure $lh -encoding utf-8
        puts $lh "$now RECONCILE UNHIDE orig=$orig batch=$batch (trash entry kept, shot visible again)"
        close $lh
    }
}

# The one write of this capability. Refuses unless the manifest line still
# exists, the file is really on disk, and it was not unhidden already.
proc ::plugins::ShotHistoryEditor::perform_unhide {ts orig batch} {
    set key "$ts|$orig|$batch"
    set found 0
    foreach rec [_manifest_records] {
        if {[_manifest_key $rec] eq $key} { set found 1; break }
    }
    if {!$found} {
        return [dict create ok 0 message "that trash entry is no longer in the manifest; nothing written."]
    }
    if {![file exists $orig]} {
        return [dict create ok 0 message "[file tail $orig] is not on disk any more; nothing written."]
    }
    if {[dict exists [_reconciled_keys_dict] $key]} {
        return [dict create ok 0 message "already unhidden."]
    }
    set now [clock format [clock seconds] -format {%Y%m%dT%H%M%S}]
    if {[catch {
        set fh [open [reconcile_manifest_path] a]
        fconfigure $fh -encoding utf-8
        puts $fh "$now|$ts|$orig|$batch"
        close $fh
    } err]} {
        if {[info exists fh]} { catch { close $fh } }
        return [dict create ok 0 message "could not write the reconcile manifest: $err"]
    }
    _append_reconcile_log $now $orig $batch
    msg -INFO "ShotHistoryEditor: unhid $orig (trash entry $ts/$batch kept)"
    return [dict create ok 1 message ""]
}

proc ::plugins::ShotHistoryEditor::scroll_reconcile {delta} {
    variable reconcile_offset
    variable reconcile_page_size
    incr reconcile_offset [expr {$delta * $reconcile_page_size}]
    if {$reconcile_offset < 0} { set reconcile_offset 0 }
    refresh_reconcile_page ShotHistoryEditor_reconcile
}

proc ::plugins::ShotHistoryEditor::_reconcile_shown {} {
    variable reconcile_offset
    variable reconcile_page_size
    set records [_reconcile_records]
    set total [llength $records]
    if {$total <= 0} {
        set reconcile_offset 0
    } else {
        set max_offset [expr {(($total - 1) / $reconcile_page_size) * $reconcile_page_size}]
        if {$reconcile_offset > $max_offset} { set reconcile_offset $max_offset }
    }
    if {$reconcile_offset < 0} { set reconcile_offset 0 }
    return [list $total [lrange $records $reconcile_offset [expr {$reconcile_offset + $reconcile_page_size - 1}]]]
}

proc ::plugins::ShotHistoryEditor::refresh_reconcile_page {page} {
    variable reconcile_offset
    variable reconcile_page_size
    variable reconcile_note

    lassign [_reconcile_shown] total shown
    # Status: always at most two lines (the header sits 3 caption lines below).
    if {$total == 0} {
        set status "No hidden shots exist on disk again."
        set hint "Every shot the trash manifest hides is really absent from history/."
    } else {
        set status "Showing [expr {$reconcile_offset + 1}]-[expr {$reconcile_offset + [llength $shown]}] of $total hidden shot(s) that exist on disk again."
        set hint "Unhide puts a shot back in the lists; its trash entry and any trash copy are kept."
    }
    append status "\n" [expr {$reconcile_note ne "" ? $reconcile_note : $hint}]
    catch { dui item config $page reconcile_status -text $status }

    set presence [_sdb_presence [lmap r $shown { dict get $r filename }]]
    for {set i 0} {$i < $reconcile_page_size} {incr i} {
        if {$i < [llength $shown]} {
            set r [lindex $shown $i]
            set fn [dict get $r filename]
            set sdb "not in SDB"
            if {[dict exists $presence $fn]} { set sdb [dict get $presence $fn] }
            set ts [dict get $r ts]
            set deleted_at $ts
            catch { set deleted_at [clock format [clock scan $ts -format {%Y%m%dT%H%M%S}] -format "%Y/%m/%d %H:%M"] }
            if {[dict get $r trash_exists]} {
                set copy "trash copy present (two different files)"
            } else {
                set copy "trash copy missing (stale manifest line)"
            }
            set text "$fn  |  deleted $deleted_at, batch [dict get $r batch]\non disk, modified [_fmt_mtime [dict get $r disk_mtime]]  |  $copy\nSDB: $sdb"
            catch { dui item config $page row${i}_text -text $text }
            catch { dui item show $page row${i}_text }
            catch { dui item show $page row${i}_unhide* -initial 1 }
        } else {
            catch { dui item config $page row${i}_text -text "" }
            catch { dui item hide $page row${i}_text }
            catch { dui item hide $page row${i}_unhide* -initial 1 }
        }
    }
    if {$reconcile_offset > 0} {
        catch { dui item show $page reconcile_prev_page* -initial 1 }
    } else {
        catch { dui item hide $page reconcile_prev_page* -initial 1 }
    }
    if {$reconcile_offset + [llength $shown] < $total} {
        catch { dui item show $page reconcile_next_page* -initial 1 }
    } else {
        catch { dui item hide $page reconcile_next_page* -initial 1 }
    }
}

proc ::plugins::ShotHistoryEditor::unhide_row {i} {
    variable reconcile_note
    lassign [_reconcile_shown] total shown
    if {$i < 0 || $i >= [llength $shown]} { return }
    set r [lindex $shown $i]
    set result [perform_unhide [dict get $r ts] [dict get $r orig] [dict get $r batch]]
    if {[dict get $result ok]} {
        set reconcile_note "Unhidden [dict get $r filename]: back in the card list and Source Inspector; its trash entry is unchanged."
    } else {
        set reconcile_note "Not unhidden: [dict get $result message]"
    }
    refresh_reconcile_page ShotHistoryEditor_reconcile
}

# Groups manifest records by batch id for the Trash/Restore page. Returns a
# list of dicts: {batch_id ts file_count shot_count shots}, most recent first.
proc ::plugins::ShotHistoryEditor::_trash_batches {} {
    array set ts_by_batch {}
    array set files_by_batch {}
    array set shots_by_batch {}
    foreach rec [_manifest_records] {
        set b [dict get $rec batch]
        set ts_by_batch($b) [dict get $rec ts]
        if {![info exists files_by_batch($b)]} { set files_by_batch($b) 0 }
        incr files_by_batch($b)
        set orig [dict get $rec orig]
        if {[string match "*.shot" $orig]} {
            if {![info exists shots_by_batch($b)]} { set shots_by_batch($b) {} }
            lappend shots_by_batch($b) [file rootname [file tail $orig]]
        }
    }
    set result {}
    foreach b [array names ts_by_batch] {
        set shots [expr {[info exists shots_by_batch($b)] ? $shots_by_batch($b) : {}}]
        lappend result [dict create batch_id $b ts $ts_by_batch($b) \
            file_count $files_by_batch($b) shot_count [llength $shots] shots $shots]
    }
    return [lsort -command ::plugins::ShotHistoryEditor::_batch_ts_cmp -decreasing $result]
}

proc ::plugins::ShotHistoryEditor::_batch_ts_cmp {a b} {
    return [string compare [dict get $a ts] [dict get $b ts]]
}

# ---------------------------------------------------------------------------
# v0.11.0 -- "Empty trash" PREVIEW. The workspace rule is "never permanent
# deletion" and the verify harness rejects any `file delete`; per the
# destructive-feature process this pass ships the preview stage only: what a
# future Empty trash would remove (batches, files, sizes, ages, totals), with
# the statement that nothing is deleted. Read-only: walks the trash manifest
# and `file size`; writes nothing. A real Empty trash needs the CLAUDE.md
# rule and the harness audit changed first, in its own explicit pass.
# ---------------------------------------------------------------------------

proc ::plugins::ShotHistoryEditor::_fmt_bytes {n} {
    if {$n >= 1048576} { return [format "%.1f MB" [expr {$n / 1048576.0}]] }
    if {$n >= 1024} { return [format "%.1f KB" [expr {$n / 1024.0}]] }
    return "$n B"
}

proc ::plugins::ShotHistoryEditor::empty_trash_preview_text {} {
    set batches [_trash_batches]
    set records [_manifest_records]
    set now [clock seconds]
    set lines [list \
        "Empty trash removes every file in the plugin trash PERMANENTLY. Nothing is removed" \
        "until you tap Empty trash (bottom right) and type the batch count on the confirmation" \
        "page. Restore first anything you might still want; history/ is never touched." \
        ""]
    set empties [_empty_trash_dir_count]
    if {[llength $batches] == 0} {
        lappend lines "The trash is empty: no batches, no files."
        if {$empties > 0} {
            lappend lines "$empties empty batch folder(s) remain under the trash; Advanced > Tidy empty trash folders removes them."
        }
        return [join $lines "\n"]
    }
    set tot_bytes 0; set tot_files 0; set tot_shots 0; set tot_missing 0
    foreach b $batches {
        set bid [dict get $b batch_id]
        set bytes 0; set present 0; set missing 0
        foreach rec $records {
            if {[dict get $rec batch] ne $bid} { continue }
            set t [dict get $rec trash]
            if {[file isfile $t]} {
                incr present
                catch { incr bytes [file size $t] }
            } else {
                incr missing
            }
        }
        set ts [dict get $b ts]
        set when $ts
        set age "?"
        catch {
            set secs [clock scan $ts -format {%Y%m%dT%H%M%S}]
            set when [clock format $secs -format "%Y/%m/%d %H:%M"]
            set age [expr {($now - $secs) / 86400}]
        }
        set fc [dict get $b file_count]
        set files_note [expr {$missing ? "$present of $fc files present" : "all $fc files present"}]
        lappend lines "$when  |  batch $bid  |  [dict get $b shot_count] shot(s)  |  $files_note  |  [_fmt_bytes $bytes]  |  $age day(s) old"
        incr tot_bytes $bytes
        incr tot_files $present
        incr tot_shots [dict get $b shot_count]
        incr tot_missing $missing
    }
    lappend lines ""
    lappend lines "Would be removed permanently: [llength $batches] batch(es), $tot_shots shot(s), $tot_files file(s), [_fmt_bytes $tot_bytes] under [trash_dir]"
    if {$tot_missing > 0} {
        lappend lines "$tot_missing manifest entr(y/ies) point at files that are already gone (restored, or moved by hand)."
    }
    if {$empties > 0} {
        lappend lines "$empties empty batch folder(s) under the trash (left by earlier restores) would go too; Advanced > Tidy removes them on their own."
    }
    lappend lines "The trash manifest and delete log would be kept as the audit trail."
    return [join $lines "\n"]
}

# ---------------------------------------------------------------------------
# v0.12.0 -- real Empty trash (the sixth authorized write capability; the
# first permanent deletion, under the CLAUDE.md exception of 2026-09-18).
# The whole write path, in order:
#   1. open_purge_confirm snapshots the batch ids; confirm_purge_submit
#      requires the typed batch count.
#   2. perform_purge refuses if the batch set changed since the snapshot.
#   3. For every trash-manifest line: the trash path must resolve STRICTLY
#      inside plugins/ShotHistoryEditor/trash/ (else kept + logged), must be
#      a listed file (else "already gone", line dropped); then ONE
#      `file delete` on that file. Then `file delete` on each batch folder
#      only if it is now empty (non-empty folders stay).
#   4. Every file gets a line in purge_log.txt (append-only); the trash
#      manifest is rewritten without the removed lines; delete_log.txt gets
#      one PURGE summary line.
# history/, history_v2/ and SDB are never touched by this path.
# ---------------------------------------------------------------------------

proc ::plugins::ShotHistoryEditor::purge_log_path {} {
    return [file join [_plugins_dir] ShotHistoryEditor purge_log.txt]
}

# True only for a path strictly inside the plugin's own trash folder.
proc ::plugins::ShotHistoryEditor::_inside_trash_dir {path} {
    if {$path eq ""} { return 0 }
    set prefix "[file normalize [trash_dir]]/"
    set p [file normalize $path]
    return [expr {[string length $p] > [string length $prefix] &&
                  [string equal -length [string length $prefix] $prefix $p]}]
}

proc ::plugins::ShotHistoryEditor::_append_purge_line {ts rec bytes status} {
    catch {
        set fh [open [purge_log_path] a]
        fconfigure $fh -encoding utf-8
        puts $fh "$ts|[dict get $rec batch]|[dict get $rec orig]|[dict get $rec trash]|$bytes|$status"
        close $fh
    }
}

proc ::plugins::ShotHistoryEditor::perform_purge {expected_batch_ids} {
    set ts [clock format [clock seconds] -format {%Y%m%dT%H%M%S}]
    set batches [_trash_batches]
    set ids [lsort [lmap b $batches { dict get $b batch_id }]]
    if {$ids ne [lsort $expected_batch_ids]} {
        return [dict create ok 0 message "The trash changed since the preview; nothing was removed. Open the preview again." \
            batches 0 removed_files 0 bytes 0 skipped {} already_gone 0 manifest_ok 1]
    }
    if {[llength $batches] == 0} {
        return [dict create ok 0 message "The trash is empty; nothing to remove." \
            batches 0 removed_files 0 bytes 0 skipped {} already_gone 0 manifest_ok 1]
    }
    set removed 0
    set bytes 0
    set already_gone 0
    set skipped {}
    set keep {}
    foreach rec [_manifest_records] {
        set t [dict get $rec trash]
        if {![_inside_trash_dir $t]} {
            lappend skipped [dict create path $t reason "outside the plugin trash folder"]
            lappend keep $rec
            _append_purge_line $ts $rec 0 "SKIPPED outside trash"
            continue
        }
        if {![file isfile $t]} {
            incr already_gone
            _append_purge_line $ts $rec 0 "already gone"
            continue
        }
        set sz 0
        catch { set sz [file size $t] }
        if {[catch { file delete -- $t } err]} {   ;# purge-only (CLAUDE.md exception 2026-09-18)
            lappend skipped [dict create path $t reason "could not remove: $err"]
            lappend keep $rec
            _append_purge_line $ts $rec $sz "FAILED $err"
            continue
        }
        incr removed
        incr bytes $sz
        _append_purge_line $ts $rec $sz "removed"
    }
    # v0.13.0: every empty folder directly under the trash goes, not only
    # the ones this purge emptied (earlier restores left theirs behind).
    set folders_removed [_remove_empty_trash_dirs]
    set manifest_ok [_rewrite_manifest $keep]
    catch {
        set lh [open [delete_log_path] a]
        fconfigure $lh -encoding utf-8
        puts $lh "$ts PURGE batches=[llength $batches] files_removed=$removed bytes=$bytes folders_removed=$folders_removed already_gone=$already_gone skipped=[llength $skipped] manifest_rewritten=$manifest_ok (Empty trash)"
        close $lh
    }
    msg -NOTICE "ShotHistoryEditor: Empty trash removed $removed file(s), $bytes bytes, [llength $batches] batch(es), $folders_removed empty folder(s); skipped [llength $skipped]"
    return [dict create ok 1 message "" batches [llength $batches] removed_files $removed bytes $bytes \
        skipped $skipped already_gone $already_gone manifest_ok $manifest_ok folders_removed $folders_removed]
}

# ---------------------------------------------------------------------------
# v0.13.0 -- empty trash folders. Restore moves files out of a batch folder
# but never removed the folder, so the tablet had 14 empty ones. This sweep
# removes every EMPTY folder directly under the plugin trash (the ONLY folder
# `file delete` in the plugin, guarded by _inside_trash_dir; a folder holding
# anything at all stays). Shared by Empty trash and Advanced > Tidy.
# ---------------------------------------------------------------------------

proc ::plugins::ShotHistoryEditor::_empty_trash_dirs {} {
    set root [trash_dir]
    if {![file isdirectory $root]} { return {} }
    set out {}
    foreach d [lsort [glob -nocomplain -directory $root -types d *]] {
        if {![_inside_trash_dir $d]} { continue }
        set left [lsearch -all -inline -not -regexp [glob -nocomplain -directory $d -tails * .*] {^\.\.?$}]
        if {[llength $left] == 0} { lappend out $d }
    }
    return $out
}

proc ::plugins::ShotHistoryEditor::_empty_trash_dir_count {} {
    return [llength [_empty_trash_dirs]]
}

proc ::plugins::ShotHistoryEditor::_remove_empty_trash_dirs {} {
    set removed 0
    foreach d [_empty_trash_dirs] {
        if {[catch { file delete -- $d } err]} {   ;# purge-only (CLAUDE.md exception 2026-09-18)
            msg -NOTICE "ShotHistoryEditor: could not remove the empty trash folder $d: $err"
        } else {
            incr removed
        }
    }
    return $removed
}

# Advanced > Tidy: folders only, files and batches untouched; one audit line.
proc ::plugins::ShotHistoryEditor::tidy_trash_folders {} {
    variable tidy_note
    set n [_remove_empty_trash_dirs]
    set ts [clock format [clock seconds] -format {%Y%m%dT%H%M%S}]
    catch {
        set lh [open [delete_log_path] a]
        fconfigure $lh -encoding utf-8
        puts $lh "$ts TIDY removed $n empty trash folder(s)"
        close $lh
    }
    msg -INFO "ShotHistoryEditor: Tidy removed $n empty trash folder(s)"
    set tidy_note "Tidy: removed $n empty trash folder(s); files and batches untouched."
    refresh_advanced_page ShotHistoryEditor_advanced
}

proc ::plugins::ShotHistoryEditor::refresh_advanced_page {page} {
    variable tidy_note
    set n [deleted_shot_count]
    set r [reconcile_count]
    set note ""
    if {$n > 0} {
        set note "$n deleted shot(s) hidden (SDB not modified; it may resync on its own)."
    }
    if {$r > 0} {
        append note [expr {$note eq "" ? "" : " "}] "$r of them exist on disk again - see Reconcile hidden shots."
    }
    if {$tidy_note ne ""} {
        append note [expr {$note eq "" ? "" : "\n"}] $tidy_note
    }
    catch { dui item config $page deleted_note -text $note }
}

proc ::plugins::ShotHistoryEditor::open_purge_confirm {} {
    variable purge_batch_ids
    variable purge_input
    variable purge_error
    set purge_batch_ids [lmap b [_trash_batches] { dict get $b batch_id }]
    if {[llength $purge_batch_ids] == 0} { return }
    set purge_input ""
    set purge_error ""
    open_page ShotHistoryEditor_purge_confirm
}

proc ::plugins::ShotHistoryEditor::cancel_purge_confirm {} {
    _return_to_page ShotHistoryEditor_empty_preview
}

proc ::plugins::ShotHistoryEditor::refresh_purge_confirm_page {page} {
    variable purge_batch_ids
    variable purge_error
    set n [llength $purge_batch_ids]
    catch { dui item config $page purge_instructions -text \
        "Type $n (the number of trash batches) below, then tap Remove permanently. Every file in the plugin trash is deleted for good; this cannot be undone. history/ is not touched." }
    catch { dui item config $page purge_error_text -text $purge_error }
}

# The one place that calls perform_purge.
proc ::plugins::ShotHistoryEditor::confirm_purge_submit {} {
    variable purge_batch_ids
    variable purge_input
    variable purge_error
    variable purge_result_text
    set n [llength $purge_batch_ids]
    set typed [string trim $purge_input]
    if {$n == 0 || $typed ne [expr {$n}]} {
        set purge_error "Type exactly \"$n\" to confirm. Nothing was removed."
        refresh_purge_confirm_page ShotHistoryEditor_purge_confirm
        return
    }
    set result [perform_purge $purge_batch_ids]
    set lines [list]
    if {[dict get $result ok]} {
        lappend lines "Removed [dict get $result removed_files] file(s) ([_fmt_bytes [dict get $result bytes]]) from [dict get $result batches] trash batch(es), permanently."
        if {[dict get $result already_gone] > 0} {
            lappend lines "[dict get $result already_gone] manifest entr(y/ies) pointed at files that were already gone."
        }
        if {[dict get $result folders_removed] > 0} {
            lappend lines "Removed [dict get $result folders_removed] empty batch folder(s)."
        }
        if {![dict get $result manifest_ok]} {
            lappend lines "WARNING: the trash manifest could not be rewritten; see the log."
        }
    } else {
        lappend lines "Not removed: [dict get $result message]"
    }
    set skipped [dict get $result skipped]
    if {[llength $skipped] > 0} {
        lappend lines ""
        lappend lines "Kept (not removed):"
        foreach s $skipped { lappend lines "  [dict get $s path]: [dict get $s reason]" }
    }
    lappend lines ""
    lappend lines "Audit: purge_log.txt (one line per file) and delete_log.txt. history/ and SDB were not touched."
    set purge_result_text [join $lines "\n"]
    open_page ShotHistoryEditor_purge_result
}

proc ::plugins::ShotHistoryEditor::refresh_purge_result_page {page} {
    variable purge_result_text
    catch { dui item config $page purge_result_text -text $purge_result_text }
}

# Back to the Trash page, whose show{} refreshes the (now emptier) list.
proc ::plugins::ShotHistoryEditor::close_purge_result {} {
    _return_to_page ShotHistoryEditor_trash
}

# Moves history/<filename>.shot and (if present) history_v2/<filename>.json
# for each filename into a new trash batch folder. Uses `file rename` only --
# never `file delete`. If any single file fails to move, the WHOLE batch
# stops immediately; files already moved before the failure are still
# recorded in the manifest (so nothing moved is ever left untracked) and
# reported back as moved, alongside the failure.
proc ::plugins::ShotHistoryEditor::perform_delete_batch {filenames} {
    set batch_id [_new_batch_id]
    set ts [clock format [clock seconds] -format {%Y%m%dT%H%M%S}]
    set batch_dir [file join [trash_dir] "${ts}_${batch_id}"]
    set moved {}
    set failed {}
    set shot_count 0

    if {[catch { file mkdir $batch_dir } err]} {
        return [dict create ok 0 message "Could not create trash folder: $err" \
            moved_files 0 shot_count 0 failed $filenames batch_id $batch_id]
    }

    foreach fn $filenames {
        if {![_safe_filename $fn]} {
            lappend failed [dict create filename $fn reason "unsafe filename"]
            continue
        }
        set legacy_src [_legacy_file $fn]
        set json_src [_json_file $fn]
        set pair {}
        if {[file isfile $legacy_src]} {
            lappend pair [list $legacy_src [file join $batch_dir [file tail $legacy_src]]]
        }
        if {[file isfile $json_src]} {
            lappend pair [list $json_src [file join $batch_dir [file tail $json_src]]]
        }
        if {[llength $pair] == 0} {
            lappend failed [dict create filename $fn reason "no matching history/history_v2 files found"]
            continue
        }

        set pair_moved {}
        set move_err ""
        foreach p $pair {
            lassign $p src dst
            if {[catch { file rename -- $src $dst } err]} {
                set move_err $err
                break
            }
            lappend pair_moved [list $fn $src $dst]
        }

        if {$move_err ne ""} {
            # Stop the whole batch here; keep whatever already succeeded.
            foreach pm $pair_moved { lappend moved $pm }
            lappend failed [dict create filename $fn reason "move failed: $move_err"]
            _append_manifest_and_log $moved $batch_id $ts $shot_count
            # Some files DID move before the stop, so the history folder has
            # changed and the recommendation is stale even though this batch
            # failed. Refresh on exactly that condition (v0.6.3).
            set note ""
            if {[llength $moved] > 0} {
                set note [_notify_downstream "a partial delete"]
            }
            return [dict create ok 0 message "A file move failed partway through the batch; stopped." \
                moved_files [llength $moved] shot_count $shot_count failed $failed batch_id $batch_id \
                trash_path $batch_dir refresh_note $note]
        }

        foreach pm $pair_moved { lappend moved $pm }
        incr shot_count
    }

    _append_manifest_and_log $moved $batch_id $ts $shot_count

    # v0.6.3: the deleted shots must stop counting towards the grind
    # recommendation. Once per batch, after the manifest is written -- never
    # per file, and never before, so a batch that moved nothing asks SDB for
    # nothing.
    set note ""
    if {[llength $moved] > 0} {
        set note [_notify_downstream "the delete"]
    }
    return [dict create ok 1 message "" moved_files [llength $moved] shot_count $shot_count \
        failed $failed batch_id $batch_id trash_path $batch_dir refresh_note $note]
}

# Moves every file in a trash batch back to its original path. Move only --
# never overwrites. If the original path already has a file (name
# collision), that file is skipped and left in the trash/manifest so it can
# be retried later rather than silently lost.
proc ::plugins::ShotHistoryEditor::restore_batch {batch_id} {
    set records [_manifest_records]
    set keep {}
    set restored 0
    set collisions 0

    foreach rec $records {
        if {[dict get $rec batch] ne $batch_id} {
            lappend keep $rec
            continue
        }
        set orig [dict get $rec orig]
        set trash [dict get $rec trash]
        if {![file isfile $trash]} {
            # Nothing left to restore for this line; drop it from the manifest.
            continue
        }
        if {[file exists $orig]} {
            incr collisions
            lappend keep $rec
            continue
        }
        catch { file mkdir [file dirname $orig] }
        if {[catch { file rename -- $trash $orig }]} {
            incr collisions
            lappend keep $rec
        } else {
            incr restored
            # v0.7.1: stamp the restored file's modification time -- the
            # same mechanism the edit path has used since v0.6.0, for the
            # same reason. `file rename` preserves the original mtime, and
            # SDB's populate only re-reads a file whose mtime is NEWER than
            # the one it stored. Normally that is harmless (the row already
            # matches the file), but if the path was rewritten while the
            # shot sat in trash -- seen for real on 2026-08-24, when the
            # core's flush-save bug parked a corpse under a restored shot's
            # name -- SDB has stored the REWRITE's metadata, and the
            # restored original's older mtime stops it from ever being
            # re-read. Stamping makes the resync (which _notify_downstream
            # triggers right after this loop) pick up the restored truth
            # unconditionally.
            if {[catch { file mtime $orig [clock seconds] } err]} {
                catch { msg -NOTICE "ShotHistoryEditor: could not stamp the modification time of $orig: $err (SDB may keep older metadata for this shot until it is resynced another way)" }
            }
        }
    }

    _rewrite_manifest $keep
    _append_restore_log $batch_id $restored $collisions

    # v0.6.3: the same gap in reverse. A restored shot must start counting
    # again -- SDB's populate clears `removed` for a file that has reappeared,
    # so this needs no special handling beyond asking for the resync.
    set note ""
    if {$restored > 0} {
        set note [_notify_downstream "the restore"]
    }
    return [dict create restored $restored collisions $collisions refresh_note $note]
}

# v0.8.2: idempotent. Every reader closes the handle when done and
# _open_ro_db closes it again before opening, so the old bare
# `catch { $db_handle close }` failed on every open; catch swallowed the
# error but left $::errorInfo dirty, and the core BLE runner prints
# $::errorInfo (de1_comms.tcl:120) -- surfaced as "BLE error info invalid
# command name ..." (first seen in MaintenanceTracker v0.21.2). Closing
# only an existing command raises nothing.
proc ::plugins::ShotHistoryEditor::_close_db {} {
    variable db_handle
    if {[llength [info commands $db_handle]]} {
        if {[catch { $db_handle close } err]} {
            catch { msg "ShotHistoryEditor: SDB close failed: $err" }
        }
    }
}

proc ::plugins::ShotHistoryEditor::_open_ro_db {} {
    variable db_handle
    variable last_error
    set last_error ""
    set path [sdb_path]

    if {![file isfile $path]} {
        set last_error "SDB database not found: $path"
        return ""
    }
    if {![llength [info commands sqlite3]]} {
        set last_error "sqlite3 package is not available."
        return ""
    }

    _close_db
    if {[catch { sqlite3 $db_handle $path -readonly true } err]} {
        set last_error "Could not open SDB read-only: $err"
        return ""
    }
    return $db_handle
}

proc ::plugins::ShotHistoryEditor::_q {name} {
    set escaped [string map [list "\"" "\"\""] $name]
    return "\"$escaped\""
}

proc ::plugins::ShotHistoryEditor::_tables_views {db} {
    set objects {}
    catch {
        $db eval {SELECT name, type FROM sqlite_master
                  WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%'
                  ORDER BY type, name} row {
            lappend objects [dict create name $row(name) type $row(type)]
        }
    }
    return $objects
}

proc ::plugins::ShotHistoryEditor::_object_exists {objects name} {
    foreach item $objects {
        if {[dict get $item name] eq $name} { return 1 }
    }
    return 0
}

proc ::plugins::ShotHistoryEditor::_columns {db table} {
    set cols {}
    catch {
        $db eval "PRAGMA table_info([_q $table])" row {
            lappend cols $row(name)
        }
    }
    return $cols
}

proc ::plugins::ShotHistoryEditor::_has_col {cols col} {
    return [expr {[lsearch -exact $cols $col] >= 0}]
}

proc ::plugins::ShotHistoryEditor::_select_expr {cols col alias} {
    if {[_has_col $cols $col]} {
        return "[_q $col] AS [_q $alias]"
    }
    return "NULL AS [_q $alias]"
}

proc ::plugins::ShotHistoryEditor::_choose_source {db} {
    variable detected_objects
    variable table_used

    set detected_objects [_tables_views $db]
    if {[_object_exists $detected_objects V_shot]} {
        set table_used V_shot
        return V_shot
    }
    if {[_object_exists $detected_objects shot]} {
        set table_used shot
        return shot
    }
    set table_used ""
    return ""
}

proc ::plugins::ShotHistoryEditor::_fmt_time {clock_value} {
    if {$clock_value eq ""} { return "" }
    if {![string is integer -strict $clock_value]} { return $clock_value }
    if {[catch { clock format $clock_value -format "%Y/%m/%d %H:%M" } out]} {
        return $clock_value
    }
    return $out
}

proc ::plugins::ShotHistoryEditor::_dget {dict_value key {default ""}} {
    if {[catch { dict exists $dict_value $key } exists]} { return $default }
    if {$exists} { return [dict get $dict_value $key] }
    return $default
}

proc ::plugins::ShotHistoryEditor::_display {value} {
    if {$value eq ""} { return "-" }
    return $value
}

proc ::plugins::ShotHistoryEditor::_bean_label {brand type} {
    set text [string trim "$brand $type"]
    if {$text eq ""} { return "-" }
    return $text
}

proc ::plugins::ShotHistoryEditor::scrolling_support_text {} {
    return "enabled: paged scrolling with fixed navigation buttons"
}

proc ::plugins::ShotHistoryEditor::_page_count {text} {
    variable page_line_count
    set n [llength [split $text "\n"]]
    if {$n <= 0} { return 1 }
    set pages [expr {int(ceil(double($n) / double($page_line_count)))}]
    if {$pages < 1} { set pages 1 }
    return $pages
}

proc ::plugins::ShotHistoryEditor::_paged_text {text page_index} {
    variable page_line_count
    set lines [split $text "\n"]
    set pages [_page_count $text]
    if {$page_index < 0} { set page_index 0 }
    if {$page_index >= $pages} { set page_index [expr {$pages - 1}] }
    set start [expr {$page_index * $page_line_count}]
    set finish [expr {$start + $page_line_count - 1}]
    return [list [join [lrange $lines $start $finish] "\n"] $page_index $pages]
}

proc ::plugins::ShotHistoryEditor::_set_paged_text {dui_page text_tag status_tag text index_var} {
    upvar #0 ::plugins::ShotHistoryEditor::$index_var page_index
    lassign [_paged_text $text $page_index] shown page_index pages
    catch { dui item config $dui_page $text_tag -text $shown }
    catch { dui item config $dui_page $status_tag -text "Page [expr {$page_index + 1}] of $pages" }
}

proc ::plugins::ShotHistoryEditor::scroll_page {kind delta dui_page} {
    switch -- $kind {
        detail {
            variable detail_page_index
            incr detail_page_index $delta
            _set_paged_text $dui_page detail_text detail_page_status [build_detail_text] detail_page_index
        }
        diagnostics {
            variable diagnostics_page_index
            incr diagnostics_page_index $delta
            _set_paged_text $dui_page diagnostics_text diagnostics_page_status [diagnostics_text] diagnostics_page_index
        }
        help {
            variable help_page_index
            incr help_page_index $delta
            _set_paged_text $dui_page help_text help_page_status [help_text] help_page_index
        }
        delete_review {
            variable delete_review_page_index
            incr delete_review_page_index $delta
            _set_paged_text $dui_page review_text review_page_status [build_delete_review_text] delete_review_page_index
        }
        empty_preview {
            variable empty_preview_page_index
            incr empty_preview_page_index $delta
            _set_paged_text $dui_page empty_preview_text empty_preview_page_status [empty_trash_preview_text] empty_preview_page_index
        }
    }
}

proc ::plugins::ShotHistoryEditor::load_recent_shots {} {
    variable recent_rows
    variable max_recent
    variable last_error

    set recent_rows {}
    set db [_open_ro_db]
    if {$db eq ""} { return $recent_rows }

    set table [_choose_source $db]
    if {$table eq ""} {
        set last_error "No SDB shot table or V_shot view detected."
        _close_db
        return $recent_rows
    }

    set cols [_columns $db $table]
    set aliases {clock filename profile_title grinder_setting grinder_dose_weight drink_weight bean_brand bean_type espresso_notes extraction_time removed}
    set select_parts {}
    foreach alias $aliases {
        lappend select_parts [_select_expr $cols $alias $alias]
    }

    set sql "SELECT [join $select_parts {, }] FROM [_q $table]"
    if {[_has_col $cols removed]} {
        append sql " WHERE (removed IS NULL OR removed=0)"
    }
    if {[_has_col $cols clock]} {
        append sql " ORDER BY [_q clock] DESC"
    } elseif {[_has_col $cols filename]} {
        append sql " ORDER BY [_q filename] DESC"
    }
    # SDB has no idea about soft-deleted shots (it is never modified), so
    # this scans more rows than needed and filters/truncates in Tcl below.
    append sql " LIMIT [expr {$max_recent + 200}]"

    set deleted [_deleted_filenames_dict]
    set overlays [_all_edit_overlays]
    if {[catch {
        $db eval $sql row {
            if {[dict exists $deleted $row(filename)]} { continue }
            set item {}
            foreach a $aliases {
                dict set item $a $row($a)
            }
            dict set item table_used $table
            set item [_apply_edit_overlay $item $overlays]
            lappend recent_rows $item
            if {[llength $recent_rows] >= $max_recent} { break }
        }
    } err]} {
        set last_error "Could not read recent shots: $err"
    }

    _close_db
    return $recent_rows
}

proc ::plugins::ShotHistoryEditor::_legacy_file {filename} {
    if {$filename eq ""} { return "" }
    if {[string match "*.shot" $filename]} {
        return [file join [history_path] $filename]
    }
    return [file join [history_path] "$filename.shot"]
}

proc ::plugins::ShotHistoryEditor::_json_file {filename} {
    if {$filename eq ""} { return "" }
    if {[string match "*.json" $filename]} {
        return [file join [history_v2_path] $filename]
    }
    return [file join [history_v2_path] "$filename.json"]
}

proc ::plugins::ShotHistoryEditor::_clean_value {value} {
    set value [string trim $value]
    if {$value eq "{}"} { return "" }
    return $value
}

# Pass 5.0 refactor note: this used to be the whole body of
# read_legacy_settings, inlined against a path computed from a filename.
# Extracted unchanged (byte-for-byte same parsing logic) so the save path's
# verification step (perform_metadata_edit) can run the identical, proven
# reader against an arbitrary path (a temp file, or the real file after
# rename) without needing a filename that resolves through _legacy_file.
# read_legacy_settings's own behavior/signature is completely unchanged.
proc ::plugins::ShotHistoryEditor::_parse_settings_file {path} {
    set wanted {bean_brand bean_type grinder_setting grinder_dose_weight drink_weight espresso_notes my_name drinker_name}
    set result [dict create status missing path $path values {} message ""]
    if {$path eq "" || ![file isfile $path]} {
        dict set result message "Matching legacy .shot file not found."
        return $result
    }

    if {[catch {
        set fh [open $path r]
        fconfigure $fh -encoding utf-8
        set in_settings 0
        set values {}
        while {[gets $fh line] >= 0} {
            set trimmed [string trim $line]
            if {!$in_settings} {
                # Pass 5.0 finding: comparing against the literal string
                # "settings {" (unescaped) here previously only survived
                # Tcl's source-time brace-matching by accident, because this
                # proc's total brace count is coincidentally balanced by the
                # "}" comparison a few lines below -- but at RUNTIME, once
                # this comparison actually executes against a real
                # "settings {" line, Tcl's expression evaluator throws
                # "invalid character '}' in expression". This was never
                # triggered by this plugin's own tests before, since those
                # only used single-line synthetic settings{} fixtures where
                # this exact line was never reached with a matching value.
                # Escaping the brace (\{) fixes the runtime error without
                # changing what this comparison matches.
                if {$trimmed eq "settings \{"} {
                    set in_settings 1
                }
                continue
            }
            if {$trimmed eq "\}"} {
                break
            }
            if {$trimmed eq ""} { continue }
            if {[catch {
                set key [lindex $trimmed 0]
                set val [_clean_value [join [lrange $trimmed 1 end] " "]]
            }]} {
                continue
            }
            if {[lsearch -exact $wanted $key] >= 0} {
                dict set values $key $val
            }
        }
        close $fh
    } err]} {
        catch { close $fh }
        dict set result status error
        dict set result message "Could not read legacy .shot settings block: $err"
        return $result
    }

    if {![info exists in_settings] || !$in_settings} {
        dict set result status error
        dict set result message "No settings block found in legacy .shot file."
        return $result
    }
    dict set result status found
    dict set result values $values
    return $result
}

proc ::plugins::ShotHistoryEditor::read_legacy_settings {filename} {
    return [_parse_settings_file [_legacy_file $filename]]
}

proc ::plugins::ShotHistoryEditor::_selected_filename {} {
    variable selected_row
    if {$selected_row eq ""} { return "" }
    return [_dget $selected_row filename]
}

proc ::plugins::ShotHistoryEditor::_field_kind {field} {
    if {[lsearch -exact {grinder_setting grinder_dose_weight drink_weight} $field] >= 0} {
        return numeric
    }
    return text
}

proc ::plugins::ShotHistoryEditor::_editable_field_count {values} {
    variable editable_fields
    set n 0
    foreach field $editable_fields {
        if {[_dget $values $field] ne ""} { incr n }
    }
    return $n
}

proc ::plugins::ShotHistoryEditor::_selected_source_info {} {
    set filename [_selected_filename]
    if {$filename eq ""} {
        return [dict create filename "" shot_exists "not selected" json_exists "not selected" editable_count "not selected"]
    }
    set legacy_path [_legacy_file $filename]
    set json_path [_json_file $filename]
    set legacy_info [read_legacy_settings $filename]
    set values [_dget $legacy_info values]
    return [dict create \
        filename $filename \
        shot_exists [expr {[file isfile $legacy_path] ? "yes" : "no"}] \
        json_exists [expr {[file isfile $json_path] ? "yes" : "no"}] \
        editable_count [_editable_field_count $values]]
}

proc ::plugins::ShotHistoryEditor::open_edit_preview {{return_page ShotHistoryEditor_settings}} {
    variable edit_new_value
    variable edit_preview_text
    variable edit_warning
    variable edit_return_page
    set edit_return_page $return_page
    set edit_new_value ""
    set edit_preview_text "No change previewed yet."
    set edit_warning ""
    open_page ShotHistoryEditor_edit_preview
}

# v0.5.0: switched from open_page to _return_to_page. Edit Preview can be
# entered from Settings (1 level deep) or from Shot Detail (up to 4 levels
# deep), and the new Save/Confirm/Result mini-flow hangs another 2 pages off
# of this same page -- exactly the class of dialog-stack bug fixed in
# v0.4.1 (see CLAUDE.md's "Dialog navigation" rule). Using the proven
# close_dialog + corrective load pattern here up front avoids shipping
# another copy of that bug in the very flow being extended.
proc ::plugins::ShotHistoryEditor::back_from_edit_preview {} {
    variable edit_return_page
    _return_to_page $edit_return_page
}

proc ::plugins::ShotHistoryEditor::cycle_edit_field {} {
    variable editable_fields
    variable edit_field
    set idx [lsearch -exact $editable_fields $edit_field]
    if {$idx < 0} { set idx 0 }
    set idx [expr {($idx + 1) % [llength $editable_fields]}]
    set edit_field [lindex $editable_fields $idx]
    set ::plugins::ShotHistoryEditor::edit_preview_text "Preview only - no files will be modified."
    set ::plugins::ShotHistoryEditor::edit_warning ""
    refresh_edit_preview_page ShotHistoryEditor_edit_preview
}

proc ::plugins::ShotHistoryEditor::_current_edit_value {} {
    variable edit_field
    set filename [_selected_filename]
    if {$filename eq ""} { return "" }
    set legacy_info [read_legacy_settings $filename]
    set values [_dget $legacy_info values]
    return [_dget $values $edit_field]
}

proc ::plugins::ShotHistoryEditor::preview_change {} {
    variable edit_field
    variable edit_new_value
    variable edit_preview_text
    variable edit_warning

    set old_value [_current_edit_value]
    set new_value [string trim $edit_new_value]
    set edit_warning ""

    if {[_field_kind $edit_field] eq "numeric" && ![string is double -strict $new_value]} {
        set edit_warning "Warning: $edit_field should be numeric. This is still preview only."
    }

    set edit_preview_text [join [list \
        "Preview only -- tap Save Change below to write this." \
        "" \
        "Before:" \
        "$edit_field = [_display $old_value]" \
        "" \
        "After:" \
        "$edit_field = [_display $new_value]" \
        "" \
        "Editable source:" \
        "history/[_selected_filename].shot settings block" \
        "" \
        "SDB and history_v2 are not written to; only history/*.shot changes on Save."] "\n"]
    refresh_edit_preview_page ShotHistoryEditor_edit_preview
}

# ---------------------------------------------------------------------------
# v0.5.0 -- real metadata save confirmation flow: Save Change (on Edit
# Preview) -> Confirm (Before/After + danger Save Change button) -> Result
# -> back to edit_return_page. Cancel at Confirm and Done at Result both use
# _return_to_page (see back_from_edit_preview's note above for why).
# ---------------------------------------------------------------------------

proc ::plugins::ShotHistoryEditor::open_edit_confirm {} {
    variable edit_field
    variable edit_new_value
    variable edit_confirm_filename
    variable edit_confirm_field
    variable edit_confirm_old_value
    variable edit_confirm_new_value

    set filename [_selected_filename]
    if {$filename eq ""} { return }
    set new_value [string trim $edit_new_value]
    if {$new_value eq ""} { return }

    set edit_confirm_filename $filename
    set edit_confirm_field $edit_field
    set edit_confirm_old_value [_current_edit_value]
    set edit_confirm_new_value $new_value
    open_page ShotHistoryEditor_edit_confirm
}

proc ::plugins::ShotHistoryEditor::cancel_edit_confirm {} {
    _return_to_page ShotHistoryEditor_edit_preview
}

proc ::plugins::ShotHistoryEditor::refresh_edit_confirm_page {page} {
    variable edit_confirm_filename
    variable edit_confirm_field
    variable edit_confirm_old_value
    variable edit_confirm_new_value

    set warning ""
    if {[_field_kind $edit_confirm_field] eq "numeric" && ![string is double -strict $edit_confirm_new_value]} {
        set warning "Warning: $edit_confirm_field is usually numeric."
    }

    catch { dui item config $page confirm_shot_text -text "Shot: $edit_confirm_filename" }
    catch { dui item config $page confirm_file_text -text "File: history/$edit_confirm_filename.shot" }
    catch { dui item config $page confirm_field_text -text "Field: $edit_confirm_field" }
    catch { dui item config $page confirm_before_text -text "Before: [_display $edit_confirm_old_value]" }
    catch { dui item config $page confirm_after_text -text "After: [_display $edit_confirm_new_value]" }
    catch { dui item config $page confirm_warning_text -text $warning }
}

# The one place this pass authorizes a real write. Everything up to here is
# navigation/preview; tapping Save Change here is the only path that ever
# calls perform_metadata_edit.
proc ::plugins::ShotHistoryEditor::confirm_save_submit {} {
    variable edit_confirm_filename
    variable edit_confirm_field
    variable edit_confirm_new_value
    variable edit_result_text

    set result [perform_metadata_edit $edit_confirm_filename $edit_confirm_field $edit_confirm_new_value]
    set lines [list]
    if {[dict get $result ok]} {
        lappend lines "Saved. $edit_confirm_field for $edit_confirm_filename was updated."
        lappend lines "Before: [_display [dict get $result old_value]]"
        lappend lines "After: [_display [dict get $result new_value]]"
    } else {
        lappend lines "Not saved: [dict get $result message]"
    }
    lappend lines ""
    lappend lines "Backup: [dict get $result backup_path]"
    lappend lines ""
    # v0.6.0: the file's modification time is stamped on a successful save, so
    # SDB's own resync can finally see the edit -- before this, an edited shot
    # kept the timestamp it was first written with and SDB skipped it forever.
    # Grind Advisor is refreshed straight afterwards when it is installed.
    lappend lines "This plugin still writes nothing but history/<shot>.shot. history_v2 is unchanged."
    set note ""
    catch { set note [dict get $result refresh_note] }
    if {$note ne ""} {
        lappend lines "Grind Advisor: $note"
    } else {
        lappend lines "SDB is not written to directly; the card list overlays this correction until SDB resyncs."
    }
    set edit_result_text [join $lines "\n"]

    open_page ShotHistoryEditor_edit_result
}

proc ::plugins::ShotHistoryEditor::refresh_edit_result_page {page} {
    variable edit_result_text
    catch { dui item config $page edit_result_text -text $edit_result_text }
}

proc ::plugins::ShotHistoryEditor::close_edit_result {} {
    variable edit_return_page
    _return_to_page $edit_return_page
}

proc ::plugins::ShotHistoryEditor::refresh_edit_preview_page {page} {
    variable selected_row
    variable edit_field
    variable edit_new_value
    variable edit_preview_text
    variable edit_warning

    set filename [_selected_filename]
    if {$filename eq ""} {
        set selected_text "No shot selected."
        set source_text "Editable source: none"
        set current_value ""
    } else {
        set selected_text "Selected shot: $filename | [_fmt_time [_dget $selected_row clock]]"
        set source_text "Editable source: history/$filename.shot settings block"
        set current_value [_current_edit_value]
    }

    set field_text "$edit_field ([_field_kind $edit_field])"
    set status_text "Tap Preview Change to see Before/After, then Save Change to write it. SDB and history_v2 are never written to."
    if {$edit_warning ne ""} { append status_text "\n$edit_warning" }

    catch { dui item config $page selected_shot -text $selected_text }
    catch { dui item config $page editable_source -text $source_text }
    catch { dui item config $page field_value -text $field_text }
    catch { dui item config $page current_value -text [_display $current_value] }
    catch { dui item config $page preview_text -text $edit_preview_text }
    catch { dui item config $page preview_status -text $status_text }
}

proc ::plugins::ShotHistoryEditor::_json_meta_value {meta path} {
    set cur $meta
    foreach key $path {
        if {[catch { dict exists $cur $key } exists] || !$exists} {
            return ""
        }
        set cur [dict get $cur $key]
    }
    return $cur
}

proc ::plugins::ShotHistoryEditor::read_history_v2_meta {filename} {
    set path [_json_file $filename]
    set result [dict create status missing path $path values {} message ""]
    if {$path eq "" || ![file isfile $path]} {
        dict set result message "Matching history_v2 JSON file not found."
        return $result
    }
    if {![llength [info commands ::json::json2dict]]} {
        dict set result status error
        dict set result message "json package is not available."
        return $result
    }

    if {[catch {
        set fh [open $path r]
        fconfigure $fh -encoding utf-8
        set raw [read $fh]
        close $fh
        set obj [::json::json2dict $raw]
        if {![dict exists $obj meta]} {
            error "meta block missing"
        }
        set meta [dict get $obj meta]
        set values [dict create \
            bean_brand [_json_meta_value $meta {bean brand}] \
            bean_type [_json_meta_value $meta {bean type}] \
            bean_notes [_json_meta_value $meta {bean notes}] \
            roast_level [_json_meta_value $meta {bean roast_level}] \
            roast_date [_json_meta_value $meta {bean roast_date}] \
            espresso_notes [_json_meta_value $meta {shot notes}] \
            espresso_enjoyment [_json_meta_value $meta {shot enjoyment}] \
            drink_tds [_json_meta_value $meta {shot tds}] \
            drink_ey [_json_meta_value $meta {shot ey}] \
            grinder_model [_json_meta_value $meta {grinder model}] \
            grinder_setting [_json_meta_value $meta {grinder setting}] \
            grinder_dose_weight [_json_meta_value $meta {in}] \
            drink_weight [_json_meta_value $meta {out}] \
            extraction_time [_json_meta_value $meta {time}]]
    } err]} {
        catch { close $fh }
        dict set result status error
        dict set result message "Could not read history_v2 meta block: $err"
        return $result
    }

    dict set result status found
    dict set result values $values
    return $result
}

proc ::plugins::ShotHistoryEditor::_norm {value} {
    set value [string trim $value]
    if {$value eq "" || $value eq "-"} { return "" }
    if {[string is double -strict $value]} {
        set out [format %.4f [expr {double($value)}]]
        regsub {0+$} $out "" out
        regsub {\.$} $out "" out
        return $out
    }
    return [string tolower $value]
}

proc ::plugins::ShotHistoryEditor::_status {values} {
    set normalized {}
    set missing 0
    foreach v $values {
        set n [_norm $v]
        if {$n eq ""} {
            set missing 1
        } else {
            lappend normalized $n
        }
    }
    if {[llength $normalized] == 0 || $missing} { return "missing" }
    set first [lindex $normalized 0]
    foreach n $normalized {
        if {$n ne $first} { return "differs" }
    }
    return "match"
}

proc ::plugins::ShotHistoryEditor::_comparison_lines {sdb legacy json_values} {
    set lines [list "Comparison:"]
    foreach item {
        {Grind grinder_setting grinder_setting grinder_setting}
        {Dose grinder_dose_weight grinder_dose_weight grinder_dose_weight}
        {Yield drink_weight drink_weight drink_weight}
        {Bean bean_pair bean_pair bean_pair}
        {Notes espresso_notes espresso_notes espresso_notes}
        {Shot_time extraction_time {} extraction_time}
    } {
        lassign $item label sdb_key legacy_key json_key
        if {$sdb_key eq "bean_pair"} {
            set sv [_bean_label [_dget $sdb bean_brand] [_dget $sdb bean_type]]
            set hv [_bean_label [_dget $legacy bean_brand] [_dget $legacy bean_type]]
            set jv [_bean_label [_dget $json_values bean_brand] [_dget $json_values bean_type]]
        } else {
            set sv [_dget $sdb $sdb_key]
            if {$legacy_key eq ""} {
                set hv ""
            } else {
                set hv [_dget $legacy $legacy_key]
            }
            set jv [_dget $json_values $json_key]
        }
        lappend lines "$label: SDB=[_display $sv] | history=[_display $hv] | history_v2=[_display $jv] | status=[_status [list $sv $hv $jv]]"
    }
    return $lines
}

proc ::plugins::ShotHistoryEditor::build_detail_text {} {
    variable selected_row
    if {$selected_row eq ""} {
        return "No shot selected."
    }

    # v0.5.0: overlay any saved edits onto the SDB-sourced fields so the
    # "SDB:" section below reflects the correction immediately, even though
    # SDB itself is never written to. Uses a separate local variable
    # (display_row) since `selected_row` above is `variable`-linked to the
    # namespace variable -- assigning to it directly would overwrite the
    # real stored selection with overlaid values.
    set display_row [_apply_edit_overlay $selected_row [_all_edit_overlays]]

    set filename [_dget $display_row filename]
    set legacy_info [read_legacy_settings $filename]
    set json_info [read_history_v2_meta $filename]
    set legacy_values [_dget $legacy_info values]
    set json_values [_dget $json_info values]

    set lines [list \
        "SDB:" \
        "filename / id: [_display $filename] / [_display [_dget $display_row clock]]" \
        "date/time: [_display [_fmt_time [_dget $display_row clock]]]" \
        "profile: [_display [_dget $display_row profile_title]]" \
        "grinder_setting: [_display [_dget $display_row grinder_setting]]" \
        "grinder_dose_weight: [_display [_dget $display_row grinder_dose_weight]]" \
        "drink_weight: [_display [_dget $display_row drink_weight]]" \
        "bean_brand: [_display [_dget $display_row bean_brand]]" \
        "bean_type: [_display [_dget $display_row bean_type]]" \
        "espresso_notes: [_display [_dget $display_row espresso_notes]]" \
        "shot time: [_display [_dget $display_row extraction_time]]" \
        "" \
        "history/*.shot:" \
        "file: [_display [_dget $legacy_info path]]" \
        "status: [_dget $legacy_info status] [_dget $legacy_info message]" \
        "bean_brand: [_display [_dget $legacy_values bean_brand]]" \
        "bean_type: [_display [_dget $legacy_values bean_type]]" \
        "grinder_setting: [_display [_dget $legacy_values grinder_setting]]" \
        "grinder_dose_weight: [_display [_dget $legacy_values grinder_dose_weight]]" \
        "drink_weight: [_display [_dget $legacy_values drink_weight]]" \
        "espresso_notes: [_display [_dget $legacy_values espresso_notes]]" \
        "my_name: [_display [_dget $legacy_values my_name]]" \
        "drinker_name: [_display [_dget $legacy_values drinker_name]]" \
        "" \
        "history_v2/*.json:" \
        "file: [_display [_dget $json_info path]]" \
        "status: [_dget $json_info status] [_dget $json_info message]" \
        "meta.bean: brand=[_display [_dget $json_values bean_brand]], type=[_display [_dget $json_values bean_type]], notes=[_display [_dget $json_values bean_notes]], roast=[_display [_dget $json_values roast_level]] [_display [_dget $json_values roast_date]]" \
        "meta.shot: notes=[_display [_dget $json_values espresso_notes]], enjoyment=[_display [_dget $json_values espresso_enjoyment]], tds=[_display [_dget $json_values drink_tds]], ey=[_display [_dget $json_values drink_ey]]" \
        "meta.grinder: model=[_display [_dget $json_values grinder_model]], setting=[_display [_dget $json_values grinder_setting]]" \
        "meta.in: [_display [_dget $json_values grinder_dose_weight]]" \
        "meta.out: [_display [_dget $json_values drink_weight]]" \
        "meta.time: [_display [_dget $json_values extraction_time]]" \
        ""]

    foreach line [_comparison_lines $display_row $legacy_values $json_values] {
        lappend lines $line
    }
    return [join $lines "\n"]
}

proc ::plugins::ShotHistoryEditor::_count_files {dir pattern} {
    if {![file isdirectory $dir]} { return 0 }
    return [llength [glob -nocomplain -directory $dir $pattern]]
}

proc ::plugins::ShotHistoryEditor::diagnostics_text {} {
    variable last_error
    variable table_used
    variable detected_objects

    set db [_open_ro_db]
    set shot_count "not available"
    set schema_issue ""
    if {$db ne ""} {
        set table [_choose_source $db]
        if {$table ne ""} {
            if {[catch { set shot_count [$db onecolumn "SELECT COUNT(*) FROM [_q $table]"] } err]} {
                set shot_count "not available"
                set schema_issue $err
            }
        } else {
            set schema_issue "No V_shot view or shot table detected."
        }
        _close_db
    } else {
        set schema_issue $last_error
    }

    set object_lines {}
    foreach item $detected_objects {
        lappend object_lines "[dict get $item type]: [dict get $item name]"
    }
    if {[llength $object_lines] == 0} { lappend object_lines "none detected" }

    set history_dir [history_path]
    set history_v2_dir [history_v2_path]
    set issues {}
    if {![file isfile [sdb_path]]} { lappend issues "SDB database file is missing." }
    if {![file isdirectory $history_dir]} { lappend issues "history folder is missing." }
    if {![file isdirectory $history_v2_dir]} { lappend issues "history_v2 folder is missing." }
    if {$schema_issue ne ""} { lappend issues "Schema issue: $schema_issue" }
    if {[llength $issues] == 0} { lappend issues "No missing folders or schema issues detected." }
    set selected_info [_selected_source_info]

    set deleted_n [deleted_shot_count]

    return [join [list \
        "SDB database path: [sdb_path]" \
        "Detected SDB tables/views:" \
        "  [join $object_lines "\n  "]" \
        "Detected table/view used: [_display $table_used]" \
        "Scrolling support: [scrolling_support_text]" \
        "history folder path: $history_dir" \
        "history_v2 folder path: $history_v2_dir" \
        "Number of SDB shots found: $shot_count" \
        "Number of .shot files found: [_count_files $history_dir *.shot]" \
        "Number of .json files found: [_count_files $history_v2_dir *.json]" \
        "Selected shot: [_display [_dget $selected_info filename]]" \
        "Matching .shot file exists: [_dget $selected_info shot_exists]" \
        "Matching history_v2 JSON exists: [_dget $selected_info json_exists]" \
        "Editable fields detected in selected .shot: [_dget $selected_info editable_count]" \
        "Trash folder path: [trash_dir]" \
        "Trash manifest path: [trash_manifest_path]" \
        "Delete log path: [delete_log_path]" \
        "$deleted_n deleted shot(s) hidden (SDB not modified; it may resync on its own)." \
        "Hidden shots that exist on disk again: [reconcile_count] (Advanced > Reconcile hidden shots)" \
        "Reconcile manifest path: [reconcile_manifest_path]" \
        "Backups folder path: [backups_dir]" \
        "Edit manifest path: [edit_manifest_path]" \
        "Edit log path: [edit_log_path]" \
        "Issues:" \
        "  [join $issues "\n  "]"] "\n"]
}

proc ::plugins::ShotHistoryEditor::help_text {} {
    return [join [list \
        "SDB is used for browsing and searching recent shots and is never written to." \
        "The legacy history/*.shot settings block is the durable, real source for editable metadata." \
        "history_v2 is read-only for comparison; edits and deletes never write to it (see below)." \
        "" \
        "Real metadata save (v0.5.0): pick one safe field, type a value, Preview Change, then Save Change and confirm. Only that one settings line of history/<filename>.shot is rewritten, after a whole-file backup (plugins/ShotHistoryEditor/backups/) and verified before and after; a failed save restores the backup. SDB and history_v2 are never written." \
        "" \
        "Safe editable fields:" \
        "grinder_setting, grinder_dose_weight, drink_weight, bean_brand, bean_type, espresso_notes, my_name, drinker_name." \
        "" \
        "Soft delete (v0.4.0): selecting shots and tapping Delete opens a two-step confirmation (Review, then a typed Confirm). Confirming MOVES history/<filename>.shot and, if present, history_v2/<filename>.json into plugins/ShotHistoryEditor/trash/ -- files are only ever moved, never deleted, and never edited. SDB itself is never written to, so deleted shots are hidden by filtering the list against a manifest file, not by changing SDB." \
        "Advanced > Trash / Restore lists every deleted batch and can move its files back to their original location." \
        "Empty trash (Trash page) permanently removes the plugin trash's files after a typed confirmation; history/ is never touched." \
        "" \
        "Raw pressure, flow, temperature, resistance, shot_series, chart arrays, and machine sensor data are off-limits -- never displayed for editing, never modified." \
        "Reconcile hidden shots (Advanced, v0.10.0): shots the trash manifest still hides although their file is back in history/. Unhide appends one marker line to reconcile_manifest.txt (plus an audit line); the trash entry is never edited." \
        "" \
        "Rinse, flush, steam, hot water, and cleaning shots never trigger anything in this plugin -- it has no automatic hooks at all."] "\n"]
}

proc ::plugins::ShotHistoryEditor::select_recent_row {idx} {
    variable recent_rows
    variable selected_row
    if {$idx < 0 || $idx >= [llength $recent_rows]} { return }
    set selected_row [lindex $recent_rows $idx]
    open_page ShotHistoryEditor_detail
}

proc ::plugins::ShotHistoryEditor::refresh_recent_page {page} {
    variable recent_rows
    variable last_error
    variable max_recent
    load_recent_shots

    if {[llength $recent_rows] == 0} {
        set status "No recent SDB shots found."
        if {$last_error ne ""} { append status "\n$last_error" }
    } else {
        set status "Showing latest [llength $recent_rows] SDB shots. Select Open for source detail."
    }
    catch { dui item config $page recent_status -text $status }

    for {set i 0} {$i < $max_recent} {incr i} {
        if {$i < [llength $recent_rows]} {
            set row [lindex $recent_rows $i]
            set bean [_bean_label [_dget $row bean_brand] [_dget $row bean_type]]
            set text "[_fmt_time [_dget $row clock]] | [_display [_dget $row filename]] | grind [_display [_dget $row grinder_setting]] | dose [_display [_dget $row grinder_dose_weight]] | yield [_display [_dget $row drink_weight]] | $bean | time [_display [_dget $row extraction_time]]"
            catch { dui item config $page row${i}_text -text $text }
            catch { dui item show $page row${i}_open* -initial 1 }
        } else {
            catch { dui item config $page row${i}_text -text "" }
            # v0.8.3: -initial 1, the same form the card list and Trash page
            # use since v0.8.1, so a hidden Open cannot flash back on the
            # framework's pre-show{} re-show.
            catch { dui item hide $page row${i}_open* -initial 1 }
        }
    }
}

# ---------------------------------------------------------------------------
# Pass 3/4.0 -- main-page card list, selection mode, and real soft delete.
# Card selection only drives an in-memory "sel" array (never SDB). SDB is
# never written to. Actual file moves only happen in perform_delete_batch/
# restore_batch, both further below, and only after the Review/Confirm flow.
# ---------------------------------------------------------------------------

proc ::plugins::ShotHistoryEditor::load_recent_shots_paged {offset limit} {
    variable card_rows
    variable last_error

    set card_rows {}
    set last_error ""
    set db [_open_ro_db]
    if {$db eq ""} { return $card_rows }

    set table [_choose_source $db]
    if {$table eq ""} {
        set last_error "No SDB shot table or V_shot view detected."
        _close_db
        return $card_rows
    }

    set cols [_columns $db $table]
    set aliases {clock filename profile_title grinder_setting grinder_dose_weight drink_weight bean_brand bean_type espresso_notes extraction_time removed}
    set select_parts {}
    foreach alias $aliases {
        lappend select_parts [_select_expr $cols $alias $alias]
    }

    set sql "SELECT [join $select_parts {, }] FROM [_q $table]"
    if {[_has_col $cols removed]} {
        append sql " WHERE (removed IS NULL OR removed=0)"
    }
    if {[_has_col $cols clock]} {
        append sql " ORDER BY [_q clock] DESC"
    } elseif {[_has_col $cols filename]} {
        append sql " ORDER BY [_q filename] DESC"
    }
    # Soft-deleted shots are invisible to SDB (never modified), so this
    # scans from the top and filters/slices in Tcl instead of using SQL
    # OFFSET directly -- otherwise a deleted row between two pages would
    # shift every later page by one and could under-fill a page.
    set scan_cap [expr {$offset + $limit + 200}]
    append sql " LIMIT $scan_cap"

    set deleted [_deleted_filenames_dict]
    set overlays [_all_edit_overlays]
    set matched {}
    if {[catch {
        $db eval $sql row {
            if {[dict exists $deleted $row(filename)]} { continue }
            set item {}
            foreach a $aliases {
                dict set item $a $row($a)
            }
            dict set item table_used $table
            set item [_apply_edit_overlay $item $overlays]
            lappend matched $item
            if {[llength $matched] >= $offset + $limit} { break }
        }
    } err]} {
        set last_error "Could not read recent shots: $err"
    }
    set card_rows [lrange $matched $offset [expr {$offset + $limit - 1}]]

    _close_db
    return $card_rows
}

proc ::plugins::ShotHistoryEditor::_total_shot_count {} {
    set n ""
    set db [_open_ro_db]
    if {$db eq ""} { return $n }
    set table [_choose_source $db]
    if {$table ne ""} {
        set where ""
        if {[_has_col [_columns $db $table] removed]} { set where " WHERE (removed IS NULL OR removed=0)" }
        catch { set n [$db onecolumn "SELECT COUNT(*) FROM [_q $table]$where"] }
    }
    _close_db
    return $n
}

# Count of shots the card pager can actually reach: the SAME removed-column
# filter and the SAME trash-manifest filename filter as
# load_recent_shots_paged, so "Showing x-y of N" and the last page always
# agree. v0.8.1 bugfix: the old version subtracted the WHOLE trash manifest
# from SDB's raw count, but SDB's own resync also flags trashed files
# removed=1 -- those shots were then subtracted twice, under-reporting the
# total (tablet showed "Showing 121-121 of 106 shots") while Next kept
# finding real rows past the fake total.
proc ::plugins::ShotHistoryEditor::_visible_shot_count {} {
    set n ""
    set db [_open_ro_db]
    if {$db eq ""} { return $n }
    set table [_choose_source $db]
    if {$table ne ""} {
        set cols [_columns $db $table]
        set where ""
        if {[_has_col $cols removed]} { set where " WHERE (removed IS NULL OR removed=0)" }
        if {[_has_col $cols filename]} {
            set deleted [_deleted_filenames_dict]
            set count 0
            if {![catch {
                $db eval "SELECT [_q filename] AS fn FROM [_q $table]$where" row {
                    if {![dict exists $deleted $row(fn)]} { incr count }
                }
            }]} {
                set n $count
            }
        } else {
            # No filename column detected: the pager cannot filter by the
            # trash manifest either, so the raw count IS the reachable count.
            catch { set n [$db onecolumn "SELECT COUNT(*) FROM [_q $table]$where"] }
        }
    }
    _close_db
    return $n
}

# Looks up date/time (clock) and profile for a known list of filenames, used
# to build the Delete Review page. Filenames are always sourced internally
# (from card_rows/sel), never typed by a user, but _qval still escapes them.
proc ::plugins::ShotHistoryEditor::_lookup_shots_by_filename {filenames} {
    set rows {}
    if {[llength $filenames] == 0} { return $rows }
    set db [_open_ro_db]
    if {$db eq ""} { return $rows }
    set table [_choose_source $db]
    if {$table eq ""} { _close_db; return $rows }

    set cols [_columns $db $table]
    set aliases {clock filename profile_title}
    set select_parts {}
    foreach alias $aliases { lappend select_parts [_select_expr $cols $alias $alias] }
    set in_list [join [lmap fn $filenames { _qval $fn }] ", "]
    set sql "SELECT [join $select_parts {, }] FROM [_q $table] WHERE [_q filename] IN ($in_list)"

    catch {
        $db eval $sql row {
            set item {}
            foreach a $aliases { dict set item $a $row($a) }
            lappend rows $item
        }
    }
    _close_db
    return $rows
}

proc ::plugins::ShotHistoryEditor::selected_count {} {
    variable sel
    return [array size sel]
}

proc ::plugins::ShotHistoryEditor::_is_selected {filename} {
    variable sel
    return [info exists sel($filename)]
}

proc ::plugins::ShotHistoryEditor::clear_selection_state {} {
    variable sel
    array unset sel
}

proc ::plugins::ShotHistoryEditor::clear_selection {} {
    clear_selection_state
    refresh_main_page ShotHistoryEditor_settings
}

proc ::plugins::ShotHistoryEditor::toggle_select_mode {} {
    variable select_mode
    if {$select_mode} {
        set select_mode 0
        clear_selection_state
    } else {
        set select_mode 1
    }
    refresh_main_page ShotHistoryEditor_settings
}

proc ::plugins::ShotHistoryEditor::row_toggle_select {i} {
    variable card_rows
    variable sel
    if {$i < 0 || $i >= [llength $card_rows]} { return }
    set filename [_dget [lindex $card_rows $i] filename]
    if {$filename eq ""} { return }
    if {[info exists sel($filename)]} {
        array unset sel $filename
    } else {
        set sel($filename) 1
    }
    refresh_main_page ShotHistoryEditor_settings
}

proc ::plugins::ShotHistoryEditor::edit_from_card {i} {
    variable card_rows
    variable selected_row
    if {$i < 0 || $i >= [llength $card_rows]} { return }
    set selected_row [lindex $card_rows $i]
    open_edit_preview ShotHistoryEditor_settings
}

# Pass 3.1 -- single dispatcher per card button. There is exactly one dbutton
# per card row (no overlapping duplicate buttons, see the Part A fix note at
# the top of the settings page setup{}); this proc decides what a tap on that
# one button does, based on the current mode, instead of swapping widgets.
proc ::plugins::ShotHistoryEditor::card_btn_click {i} {
    variable select_mode
    if {$select_mode} {
        row_toggle_select $i
    } else {
        edit_from_card $i
    }
}

# Single dispatcher for the bottom-left bar button (Done in normal mode,
# Delete in selection mode).
#
# v0.5.2: Done no longer calls dui page close_dialog directly -- see
# _navigate_done's note above. Uses the return page captured by the
# Settings page's own show{} instead of trusting close_dialog's "previous".
proc ::plugins::ShotHistoryEditor::bar_left_click {} {
    variable select_mode
    variable _settings_return_page
    if {$select_mode} {
        if {[selected_count] > 0} { open_delete_review }
    } else {
        _navigate_done $_settings_return_page
    }
}

# Single dispatcher for the bottom-right bar button (Advanced in normal mode,
# Clear Selection in selection mode).
proc ::plugins::ShotHistoryEditor::bar_right_click {} {
    variable select_mode
    if {$select_mode} {
        clear_selection
    } else {
        open_page ShotHistoryEditor_advanced
    }
}

proc ::plugins::ShotHistoryEditor::scroll_cards {delta} {
    variable card_offset
    variable card_page_size
    incr card_offset [expr {$delta * $card_page_size}]
    if {$card_offset < 0} { set card_offset 0 }
    refresh_main_page ShotHistoryEditor_settings
}

# ---------------------------------------------------------------------------
# Pass 4.0 -- real soft-delete confirmation flow: Review -> Confirm -> Result.
# Cancel at either step (and the settings page's own defensive `show` reset)
# is what actually exits the flow -- no separate guard flag to get stuck.
# ---------------------------------------------------------------------------

# Step 1 entry point (from the main page's Delete button). Snapshots the
# selected filenames now, since selection could change if the user paged
# around before this point -- the Review/Confirm flow must describe exactly
# what will be deleted, not whatever is selected later.
proc ::plugins::ShotHistoryEditor::open_delete_review {} {
    variable sel
    variable review_filenames
    variable review_rows
    variable delete_result_text

    set review_filenames [lsort [array names sel]]
    set review_rows [_lookup_shots_by_filename $review_filenames]
    set delete_result_text ""
    set ::plugins::ShotHistoryEditor::delete_review_page_index 0
    open_page ShotHistoryEditor_delete_review
}

proc ::plugins::ShotHistoryEditor::_review_file_list_text {filename} {
    set legacy [_legacy_file $filename]
    set json [_json_file $filename]
    set has_shot [file isfile $legacy]
    set has_json [file isfile $json]
    if {$has_shot && $has_json} {
        return "history/$filename.shot, history_v2/$filename.json"
    } elseif {$has_shot} {
        return "history/$filename.shot only"
    } elseif {$has_json} {
        return "history_v2/$filename.json only"
    }
    return "no matching files found (already moved or missing)"
}

proc ::plugins::ShotHistoryEditor::build_delete_review_text {} {
    variable review_filenames
    variable review_rows

    if {[llength $review_filenames] == 0} {
        return "No shots selected."
    }

    array set by_filename {}
    foreach row $review_rows {
        set by_filename([_dget $row filename]) $row
    }

    set lines {}
    foreach fn $review_filenames {
        if {[info exists by_filename($fn)]} {
            set row $by_filename($fn)
            set label "[_fmt_time [_dget $row clock]]  |  $fn"
        } else {
            set label $fn
        }
        lappend lines $label
        lappend lines "  Files: [_review_file_list_text $fn]"
    }
    return [join $lines "\n"]
}

proc ::plugins::ShotHistoryEditor::cancel_delete_review {} {
    _return_to_page ShotHistoryEditor_settings
}

proc ::plugins::ShotHistoryEditor::refresh_delete_review_page {page} {
    variable review_filenames
    set n [llength $review_filenames]
    catch { dui item config $page review_count_text -text "$n shot(s) selected" }
    set ::plugins::ShotHistoryEditor::delete_review_page_index 0
    scroll_page delete_review 0 $page
}

# Step 2 entry point.
proc ::plugins::ShotHistoryEditor::open_delete_confirm {} {
    variable confirm_input
    variable confirm_error
    set confirm_input ""
    set confirm_error ""
    open_page ShotHistoryEditor_delete_confirm
}

proc ::plugins::ShotHistoryEditor::cancel_delete_confirm {} {
    _return_to_page ShotHistoryEditor_settings
}

proc ::plugins::ShotHistoryEditor::refresh_delete_confirm_page {page} {
    variable review_filenames
    variable confirm_error
    set n [llength $review_filenames]
    catch { dui item config $page confirm_instructions -text \
        "Type $n (the number of shots being deleted) below, then tap Confirm Delete." }
    catch { dui item config $page confirm_error_text -text $confirm_error }
}

# Typed strong-confirmation submit. Chosen over hold-to-confirm because this
# codebase has no existing press-and-hold/progress-timer UI pattern to build
# on (nothing in plugins/SDB, plugins/GrindAdvisor, or plugins/visualizer_upload
# implements one), and the spec explicitly allows a typed count as the
# fallback when hold-to-confirm isn't reliably implementable -- for the
# first destructive-capability pass, a proven, unambiguous confirmation is
# safer than a novel interaction with no precedent to verify against.
proc ::plugins::ShotHistoryEditor::confirm_delete_submit {} {
    variable review_filenames
    variable confirm_input
    variable confirm_error
    variable delete_result_text

    set n [llength $review_filenames]
    set typed [string trim $confirm_input]
    if {$typed ne [expr {$n}]} {
        set confirm_error "Type exactly \"$n\" to confirm. Nothing was deleted."
        refresh_delete_confirm_page ShotHistoryEditor_delete_confirm
        return
    }

    set result [perform_delete_batch $review_filenames]
    set moved_files [dict get $result moved_files]
    set shot_count [dict get $result shot_count]
    set failed [dict get $result failed]
    set trash_path [dict get $result trash_path]

    set lines [list]
    if {[dict get $result ok]} {
        lappend lines "Moved $moved_files file(s) for $shot_count shot(s) to the plugin trash folder."
    } else {
        lappend lines "Stopped: [dict get $result message]"
        lappend lines "Moved $moved_files file(s) for $shot_count shot(s) before stopping."
    }
    lappend lines "Trash location: $trash_path"
    if {[llength $failed] > 0} {
        lappend lines ""
        lappend lines "Not moved:"
        foreach f $failed {
            lappend lines "  [dict get $f filename]: [dict get $f reason]"
        }
    }
    lappend lines ""
    # v0.6.3: say whether the recommendation was recomputed, the same way the
    # edit result page does. Before this the deleted shots kept counting
    # towards the grind recommendation and nothing on screen said so.
    set note ""
    catch { set note [dict get $result refresh_note] }
    if {$note ne ""} {
        lappend lines "Grind Advisor: $note"
    } else {
        lappend lines "SDB is not written to directly; the card list overlays this until SDB resyncs."
    }
    lappend lines ""
    lappend lines "Nothing was permanently deleted. Use Advanced > Trash / Restore to undo."
    set delete_result_text [join $lines "\n"]

    open_page ShotHistoryEditor_delete_result
}

proc ::plugins::ShotHistoryEditor::refresh_delete_result_page {page} {
    variable delete_result_text
    catch { dui item config $page result_text -text $delete_result_text }
}

# Exit point: returns to the main page, which (via its own `show` proc)
# unconditionally resets select_mode/sel and reloads the card list, so
# deleted shots disappear immediately -- no separate "refresh" call needed.
# v0.4.1 bugfix: this used to call open_page, which tries `dui page
# open_dialog` on ShotHistoryEditor_settings -- a page already open 3 levels
# down the stack (settings -> review -> confirm -> result). That call did
# not throw (so open_page's catch treated it as success and never tried
# `load`/`show`), but it also performed no real page transition, so Done
# appeared to do nothing: no error, no crash, no navigation. See
# _return_to_page for the proven fix (GrindAdvisor.tcl:412-439).
proc ::plugins::ShotHistoryEditor::close_delete_result {} {
    _return_to_page ShotHistoryEditor_settings
}

# ---------------------------------------------------------------------------
# Pass 4.0 -- Trash / Restore page (under Advanced).
# ---------------------------------------------------------------------------

proc ::plugins::ShotHistoryEditor::restore_trash_batch {batch_id} {
    variable trash_offset
    set result [restore_batch $batch_id]
    set trash_offset 0
    refresh_trash_page ShotHistoryEditor_trash
    return $result
}

proc ::plugins::ShotHistoryEditor::scroll_trash {delta} {
    variable trash_offset
    variable trash_page_size
    incr trash_offset [expr {$delta * $trash_page_size}]
    if {$trash_offset < 0} { set trash_offset 0 }
    refresh_trash_page ShotHistoryEditor_trash
}

proc ::plugins::ShotHistoryEditor::refresh_trash_page {page} {
    variable trash_offset
    variable trash_page_size

    set batches [_trash_batches]
    set total [llength $batches]
    # v0.9.1: clamp the offset to the last real page (same rule as the card
    # list since v0.8.1), so Next can never walk past the end and a restore
    # that empties the last page snaps back instead of showing nothing.
    if {$total <= 0} {
        set trash_offset 0
    } else {
        set max_offset [expr {(($total - 1) / $trash_page_size) * $trash_page_size}]
        if {$trash_offset > $max_offset} { set trash_offset $max_offset }
    }
    if {$trash_offset < 0} { set trash_offset 0 }
    set shown [lrange $batches $trash_offset [expr {$trash_offset + $trash_page_size - 1}]]

    if {$total == 0} {
        set status "No trashed shots. Deleted shots appear here as restorable batches."
    } else {
        set from [expr {$trash_offset + 1}]
        set to [expr {$trash_offset + [llength $shown]}]
        set status "Showing $from-$to of $total batch(es)."
    }
    catch { dui item config $page trash_status -text $status }

    for {set i 0} {$i < $trash_page_size} {incr i} {
        if {$i < [llength $shown]} {
            set b [lindex $shown $i]
            set ts [dict get $b ts]
            set friendly $ts
            catch { set friendly [clock format [clock scan $ts -format {%Y%m%dT%H%M%S}] -format "%Y/%m/%d %H:%M"] }
            set text "$friendly  |  [dict get $b shot_count] shot(s), [dict get $b file_count] file(s)  |  batch [dict get $b batch_id]"
            catch { dui item config $page row${i}_text -text $text }
            catch { dui item show $page row${i}_text }
            catch { dui item show $page row${i}_restore* -initial 1 }
        } else {
            catch { dui item config $page row${i}_text -text "" }
            catch { dui item hide $page row${i}_text }
            catch { dui item hide $page row${i}_restore* -initial 1 }
        }
    }

    # v0.8.1: wildcard tag form for dbutton show/hide -- see the note in
    # refresh_main_page. The old bare-tag hides left dead-but-visible
    # Restore/Prev buttons on this page too.
    if {$trash_offset > 0} {
        catch { dui item show $page trash_prev_page* -initial 1 }
    } else {
        catch { dui item hide $page trash_prev_page* -initial 1 }
    }
    # v0.9.1: Next, hidden on the last page and on an empty list. Before
    # this the page had no Next at all, so with more than trash_page_size
    # batches the older ones were unreachable (tablet: "Showing 1-6 of 7").
    if {$trash_offset + [llength $shown] < $total} {
        catch { dui item show $page trash_next_page* -initial 1 }
    } else {
        catch { dui item hide $page trash_next_page* -initial 1 }
    }
}

proc ::plugins::ShotHistoryEditor::restore_row {i} {
    variable trash_offset
    variable trash_page_size
    set batches [_trash_batches]
    set shown [lrange $batches $trash_offset [expr {$trash_offset + $trash_page_size - 1}]]
    if {$i < 0 || $i >= [llength $shown]} { return }
    set batch_id [dict get [lindex $shown $i] batch_id]
    restore_trash_batch $batch_id
}

proc ::plugins::ShotHistoryEditor::refresh_main_page {page} {
    variable card_rows
    variable card_offset
    variable card_page_size
    variable last_error
    variable select_mode

    # v0.8.1: clamp the offset to the last real page BEFORE loading, using
    # the same-filtered count (see _visible_shot_count), so Next can never
    # walk past the end and a delete that shrinks the list snaps the view
    # back to the last page instead of stranding it on an empty one.
    set total [_visible_shot_count]
    if {$total ne ""} {
        if {$total <= 0} {
            set card_offset 0
        } else {
            set max_offset [expr {(($total - 1) / $card_page_size) * $card_page_size}]
            if {$card_offset > $max_offset} { set card_offset $max_offset }
        }
    }
    if {$card_offset < 0} { set card_offset 0 }

    load_recent_shots_paged $card_offset $card_page_size
    set shown [llength $card_rows]

    # Toolbar status / paging label.
    if {$select_mode} {
        set status "[selected_count] selected. Tap a card's button to choose shots."
    } elseif {$shown == 0} {
        set status "No recent SDB shots found."
        if {$last_error ne ""} { append status "\n$last_error" }
    } else {
        set from [expr {$card_offset + 1}]
        set to [expr {$card_offset + $shown}]
        if {$total ne ""} {
            set status "Showing $from-$to of $total shots."
        } else {
            set status "Showing $from-$to."
        }
    }
    catch { dui item config $page recent_status -text $status }

    # Mode button (top-right) and bottom bar: one physical button per slot,
    # command never changes -- only the caption is reconfigured. See the Part
    # A fix note in the settings page setup{} for why this replaced the
    # overlapping-duplicate-button design from v0.3.0.
    catch { dui item config $page mode_btn -label [translate [expr {$select_mode ? "Cancel" : "Select"}]] }
    catch { dui item config $page bar_left -label [translate [expr {$select_mode ? "Delete" : "Done"}]] }
    catch { dui item config $page bar_right -label [translate [expr {$select_mode ? "Clear Selection" : "Advanced"}]] }

    for {set i 0} {$i < $card_page_size} {incr i} {
        if {$i < $shown} {
            set row [lindex $card_rows $i]
            set filename [_dget $row filename]
            set bean [_bean_label [_dget $row bean_brand] [_dget $row bean_type]]
            set profile [_display [_dget $row profile_title]]
            set line1 "[_fmt_time [_dget $row clock]]   |   $filename"
            set line2 "Grind [_display [_dget $row grinder_setting]]   Dose [_display [_dget $row grinder_dose_weight]]g   Yield [_display [_dget $row drink_weight]]g   |   [_display [_dget $row extraction_time]]s"
            set line3 "Bean: $bean   |   Profile: $profile"

            catch { dui item show $page row${i}_bg -initial 1 }
            catch { dui item config $page row${i}_line1 -text $line1 }
            catch { dui item config $page row${i}_line2 -text $line2 }
            catch { dui item config $page row${i}_line3 -text $line3 }
            catch { dui item show $page row${i}_line1 -initial 1 }
            catch { dui item show $page row${i}_line2 -initial 1 }
            catch { dui item show $page row${i}_line3 -initial 1 }
            catch { dui item show $page row${i}_btn* -initial 1 }

            if {$select_mode} {
                if {[_is_selected $filename]} {
                    set lbl "[::plugins::ShotHistoryEditor::_u 0x2611] Selected"
                } else {
                    set lbl "[::plugins::ShotHistoryEditor::_u 0x2610] Select"
                }
                catch { dui item config $page row${i}_btn -label [translate $lbl] }
            } else {
                catch { dui item config $page row${i}_btn -label [translate "[::plugins::ShotHistoryEditor::_u 0x270e] Edit"] }
            }
        } else {
            catch { dui item hide $page row${i}_bg -initial 1 }
            catch { dui item config $page row${i}_line1 -text "" }
            catch { dui item config $page row${i}_line2 -text "" }
            catch { dui item config $page row${i}_line3 -text "" }
            catch { dui item hide $page row${i}_line1 -initial 1 }
            catch { dui item hide $page row${i}_line2 -initial 1 }
            catch { dui item hide $page row${i}_line3 -initial 1 }
            catch { dui item hide $page row${i}_btn* -initial 1 }
        }
    }

    # v0.8.1: dbutton show/hide MUST use the wildcard tag form. dui gives a
    # dbutton's visible shape/label their own -btn/-lbl tags plus a shared
    # literal "<tag>*" tag (de1app-core/dui.tcl process_tags_and_var); the
    # bare tag only matches the invisible clickable rect, so the old bare-tag
    # hides left Prev and the empty rows' Edit buttons fully visible (but
    # dead) on the tablet. Same form every reference plugin uses (A_Flow,
    # DPx_Flow_Calibrator: "dui item hide <page> <tag>*"). -initial 1 also
    # persists the state through the framework's pre-show{} re-show of all
    # items, so hidden buttons cannot flash back on a page revisit.
    if {$card_offset > 0} {
        catch { dui item show $page prev_page* -initial 1 }
    } else {
        catch { dui item hide $page prev_page* -initial 1 }
    }
    # Next hides on the last page (offset+shown reaches the clamped total).
    # When the total is unknown (SDB unreadable), fall back to "a full page
    # probably has a next one".
    if {($total ne "" && $card_offset + $shown < $total) ||
        ($total eq "" && $shown == $card_page_size)} {
        catch { dui item show $page next_page* -initial 1 }
    } else {
        catch { dui item hide $page next_page* -initial 1 }
    }
}

namespace eval ::dui::pages::ShotHistoryEditor_settings {
    # Pass 3.1 main page. Layout comes entirely from the ::plugins::ShotHistoryEditor::L
    # token array (see _init_layout) -- no hardcoded coordinates below.
    #
    # Part A fix: v0.3.0 stacked multiple full-size interactive dbuttons at
    # identical coordinates (select_btn/cancel_btn, bar_advanced/bar_delete,
    # bar_done/bar_clear, and three buttons per card row) and toggled which
    # one was visible with `dui item show/hide`. That overlapping-duplicate
    # pattern does not exist anywhere else in this plugin's proven-working
    # v0.2.0 code, where every button occupies a unique, non-overlapping
    # rectangle. Root cause: once more than one interactive widget shares a
    # bounding box, tap routing on this page/canvas system becomes ambiguous
    # (see causes #1/#2 in the brief) and none of the stacked widgets respond
    # reliably. Fix: every slot below now has exactly one dbutton, created
    # once, whose -command is a stable dispatcher (card_btn_click,
    # bar_left_click, bar_right_click, toggle_select_mode) that reads
    # select_mode at click time; only the button's caption is reconfigured
    # via `dui item config ... -label` (the same generic config path already
    # proven for -text throughout this file), so no two widgets ever occupy
    # the same rectangle and no command binding is ever swapped.
    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::ShotHistoryEditor::L L
        ::plugins::ShotHistoryEditor::_page_bg $page

        set lx $L(left_x)
        set rx $L(right_x)
        set cx [expr {($lx + $rx) / 2}]

        dui add dtext $page $cx $L(header_title_y) -tags page_title -text [translate "Shot History Editor"] \
            -font $L(font_title) -width $L(content_w) -fill $L(text_hi) -anchor center -justify center
        dui add dtext $page $cx $L(header_subtitle_y) -tags subtitle -text [translate "Edits and Delete both require confirmation. Delete moves files to trash, never permanent."] \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) -anchor center -justify center

        # Mode button, top-right (single button; see fix note above).
        set mode_btn_y1 [expr {int(($L(header_y1)-$L(btn_h))/2)}]
        dui add dbutton $page [expr {$rx-$L(btn_w_std)}] $mode_btn_y1 $rx [expr {$mode_btn_y1+$L(btn_h)}] \
            -tags mode_btn -label [translate "Select"] -command ::plugins::ShotHistoryEditor::toggle_select_mode \
            -label_font $L(font_button) -style she_btn

        # v0.8.0: theme toggle. The top-right header slot is taken by the
        # mode button on this page, so the toggle mirrors it in the
        # top-LEFT corner (square, sun/moon face).
        dui add dbutton $page $lx $mode_btn_y1 [expr {$lx+$L(btn_h)}] [expr {$mode_btn_y1+$L(btn_h)}] \
            -tags btn_theme -label [::plugins::ShotHistoryEditor::_theme_button_face] \
            -command ::plugins::ShotHistoryEditor::toggle_theme \
            -label_font [expr {$L(have_icons) ? $L(font_icon) : $L(font_button)}] \
            -style she_btn

        # Toolbar: status left, Prev/Next right (moved up from the bottom per spec).
        dui add dtext $page $lx $L(toolbar_y0) -tags recent_status -text "" \
            -font $L(font_caption) -width [expr {$L(content_w)-2*($L(btn_w_std)+$L(sm))}] \
            -fill $L(text_mut) -anchor nw -justify left
        set next_x1 [expr {$rx - $L(btn_w_std)}]
        set prev_x1 [expr {$next_x1 - $L(sm) - $L(btn_w_std)}]
        dui add dbutton $page $prev_x1 $L(toolbar_y0) [expr {$prev_x1+$L(btn_w_std)}] $L(toolbar_y1) \
            -tags prev_page -label [translate "[::plugins::ShotHistoryEditor::_u 0x25c0] Prev"] -command {::plugins::ShotHistoryEditor::scroll_cards -1} \
            -label_font $L(font_button) -style she_btn
        dui add dbutton $page $next_x1 $L(toolbar_y0) $rx $L(toolbar_y1) \
            -tags next_page -label [translate "Next [::plugins::ShotHistoryEditor::_u 0x25b6]"] -command {::plugins::ShotHistoryEditor::scroll_cards 1} \
            -label_font $L(font_button) -style she_btn

        # Card list: exactly one background + 3 text lines + 1 action button per row.
        set btn_x2 [expr {$rx - $L(card_pad_x)}]
        set btn_x1 [expr {$btn_x2 - $L(card_btn_w)}]
        set text_x [expr {$lx + $L(card_pad_x)}]
        set text_w [expr {$L(card_w) - 2*$L(card_pad_x) - $L(card_btn_w) - $L(xl)}]

        for {set i 0} {$i < $::plugins::ShotHistoryEditor::card_page_size} {incr i} {
            set top [expr {$L(list_top) + $i*($L(card_h)+$L(card_gap))}]
            set bottom [expr {$top + $L(card_h)}]

            ::plugins::ShotHistoryEditor::rounded_rect $page $lx $top $rx $bottom $L(card_radius) \
                -fill $L(card_bg) -outline $L(card_outline) -width 2 -tags row${i}_bg

            dui add dtext $page $text_x [expr {$top+$L(card_line1_dy)}] -tags row${i}_line1 -text "" \
                -font $L(font_primary) -width $text_w -fill $L(text_hi) -anchor w -justify left
            dui add dtext $page $text_x [expr {$top+$L(card_line2_dy)}] -tags row${i}_line2 -text "" \
                -font $L(font_body) -width $text_w -fill $L(text_body) -anchor w -justify left
            dui add dtext $page $text_x [expr {$top+$L(card_line3_dy)}] -tags row${i}_line3 -text "" \
                -font $L(font_caption) -width $text_w -fill $L(text_mut) -anchor w -justify left

            set btn_y1 [expr {$top + int(($L(card_h)-$L(card_btn_h))/2)}]
            set btn_y2 [expr {$btn_y1 + $L(card_btn_h)}]
            dui add dbutton $page $btn_x1 $btn_y1 $btn_x2 $btn_y2 -tags row${i}_btn \
                -label [translate "[::plugins::ShotHistoryEditor::_u 0x270e] Edit"] -command "::plugins::ShotHistoryEditor::card_btn_click $i" \
                -label_font $L(font_button) -style she_btn
        }

        # Bottom bar: one row, left/right slots. Single dispatcher per slot (see fix note).
        dui add dbutton $page $lx $L(bar_y0) [expr {$lx+$L(btn_w_std)}] $L(bar_y1) \
            -tags bar_left -label [translate "Done"] -command ::plugins::ShotHistoryEditor::bar_left_click \
            -label_font $L(font_button) -style she_btn
        dui add dbutton $page [expr {$rx-$L(btn_w_std)}] $L(bar_y0) $rx $L(bar_y1) \
            -tags bar_right -label [translate "Advanced"] -command ::plugins::ShotHistoryEditor::bar_right_click \
            -label_font $L(font_button) -style she_btn
    }

    proc show {page_to_hide page_to_show} {
        # Defensive rule: entering/returning to the main page always clears
        # any selection-mode guard state, so a stuck mode can never persist
        # across a page transition even if Cancel was somehow never tapped.
        set ::plugins::ShotHistoryEditor::select_mode 0
        ::plugins::ShotHistoryEditor::clear_selection_state
        # v0.5.2: capture the real caller so Done can navigate straight back
        # to it instead of trusting dui page close_dialog's "previous" (see
        # _navigate_done's note above -- that "previous" is wrong after a
        # flush/rinse/steam interruption).
        ::plugins::ShotHistoryEditor::_capture_return_page $page_to_hide
        ::plugins::ShotHistoryEditor::refresh_main_page $page_to_show
    }
}

namespace eval ::dui::pages::ShotHistoryEditor_advanced {
    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::ShotHistoryEditor::L L
        ::plugins::ShotHistoryEditor::_page_bg $page
        set lx $L(left_x); set rx $L(right_x); set cx [expr {($lx+$rx)/2}]

        dui add dtext $page $cx $L(header_title_y) -tags page_title -text [translate "Advanced / Source Inspector"] \
            -font $L(font_section) -width $L(content_w) -fill $L(text_body) -anchor center -justify center
        dui add dtext $page $cx $L(header_subtitle_y) -tags subtitle \
            -text [translate "Optional tools. Not required for normal use."] \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) -anchor center -justify center
        dui add dtext $page $lx $L(toolbar_y0) -tags deleted_note -text "" \
            -font $L(font_caption) -width $L(content_w) -fill $L(warn) -anchor nw -justify left

        set y $L(list_top)
        dui add dbutton $page $lx $y $rx [expr {$y+$L(btn_h)}] -tags source_inspector \
            -label [translate "Source Inspector (Shot Detail)"] -command {::plugins::ShotHistoryEditor::open_page ShotHistoryEditor_recent} \
            -label_font $L(font_button) -style she_btn
        incr y [expr {$L(btn_h)+$L(md)}]
        dui add dbutton $page $lx $y $rx [expr {$y+$L(btn_h)}] -tags diagnostics \
            -label [translate "Diagnostics"] -command {::plugins::ShotHistoryEditor::open_page ShotHistoryEditor_diagnostics} \
            -label_font $L(font_button) -style she_btn
        incr y [expr {$L(btn_h)+$L(md)}]
        dui add dbutton $page $lx $y $rx [expr {$y+$L(btn_h)}] -tags help_guide \
            -label [translate "Help / Guide"] -command {::plugins::ShotHistoryEditor::open_page ShotHistoryEditor_help} \
            -label_font $L(font_button) -style she_btn
        incr y [expr {$L(btn_h)+$L(md)}]
        dui add dbutton $page $lx $y $rx [expr {$y+$L(btn_h)}] -tags trash_restore \
            -label [translate "Trash / Restore"] -command {::plugins::ShotHistoryEditor::open_page ShotHistoryEditor_trash} \
            -label_font $L(font_button) -style she_btn
        incr y [expr {$L(btn_h)+$L(md)}]
        # v0.9.0: read-only reconciliation view (see _reconcile_records).
        dui add dbutton $page $lx $y $rx [expr {$y+$L(btn_h)}] -tags reconcile \
            -label [translate "Reconcile hidden shots"] -command {::plugins::ShotHistoryEditor::open_page ShotHistoryEditor_reconcile} \
            -label_font $L(font_button) -style she_btn
        incr y [expr {$L(btn_h)+$L(md)}]
        # v0.13.0: removes only EMPTY folders directly under the plugin trash.
        dui add dbutton $page $lx $y $rx [expr {$y+$L(btn_h)}] -tags tidy \
            -label [translate "Tidy empty trash folders"] -command ::plugins::ShotHistoryEditor::tidy_trash_folders \
            -label_font $L(font_button) -style she_btn

        # v0.4.1 bugfix: was open_page (open_dialog on an ancestor already in
        # the stack, same fault class as the delete-flow exits -- see
        # _return_to_page). Advanced is only ever reached from the main
        # settings page, so this call always targets the immediate parent.
        dui add dbutton $page $lx $L(bar_y0) [expr {$lx+$L(btn_w_std)}] $L(bar_y1) -tags back \
            -label [translate "Back"] -command {::plugins::ShotHistoryEditor::_return_to_page ShotHistoryEditor_settings} \
            -label_font $L(font_button) -style she_btn
    }

    proc show {page_to_hide page_to_show} {
        # v0.13.0: the note is built by refresh_advanced_page (also called
        # after Tidy); a Tidy result shows only until the page is next shown.
        set ::plugins::ShotHistoryEditor::tidy_note ""
        ::plugins::ShotHistoryEditor::refresh_advanced_page $page_to_show
    }
}

namespace eval ::dui::pages::ShotHistoryEditor_delete_review {
    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::ShotHistoryEditor::L L
        ::plugins::ShotHistoryEditor::_page_bg $page
        set lx $L(left_x); set rx $L(right_x); set cx [expr {($lx+$rx)/2}]

        dui add dtext $page $cx $L(header_solo_title_y) -tags page_title -text [translate "Delete -- Step 1: Review"] \
            -font $L(font_section) -width $L(content_w) -fill $L(danger) -anchor center -justify center
        dui add dtext $page $lx $L(toolbar_y0) -tags review_count_text -text "" \
            -font $L(font_body) -width $L(content_w) -fill $L(text_body) -anchor nw -justify left
        dui add dtext $page $lx [expr {$L(toolbar_y0)+$L(lg)}] -tags review_intro \
            -text [translate "These shots will be moved to the plugin trash folder. Nothing is permanently deleted."] \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) -anchor nw -justify left

        dui add dtext $page $lx [expr {$L(toolbar_y0)+2*$L(lg)}] -tags review_page_status -text "" \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) -anchor nw -justify left
        dui add dtext $page $lx $L(list_top) -tags review_text -text "" \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_body) -anchor nw -justify left

        set right_btn_x1 [expr {$rx-$L(btn_w_std)}]
        set left_btn_x1 [expr {$right_btn_x1-$L(sm)-$L(btn_w_std)}]
        # v0.6.2: Cancel to the far left, with the delete flow's forward
        # button left where it is. Same reasoning as the edit flow: the way
        # OUT is always the bottom-left corner, and the destructive button is
        # never under the thumb that keeps tapping there.
        dui add dbutton $page $lx $L(bar_y0) [expr {$lx+$L(btn_w_std)}] $L(bar_y1) -tags cancel \
            -label [translate "Cancel"] -command ::plugins::ShotHistoryEditor::cancel_delete_review \
            -label_font $L(font_button) -style she_btn
        dui add dbutton $page $right_btn_x1 $L(bar_y0) $rx $L(bar_y1) -tags continue_btn \
            -label [translate "Continue"] -command ::plugins::ShotHistoryEditor::open_delete_confirm \
            -label_font $L(font_button) -style she_btn
    }

    proc show {page_to_hide page_to_show} {
        ::plugins::ShotHistoryEditor::refresh_delete_review_page $page_to_show
    }
}

namespace eval ::dui::pages::ShotHistoryEditor_delete_confirm {
    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::ShotHistoryEditor::L L
        ::plugins::ShotHistoryEditor::_page_bg $page
        set lx $L(left_x); set rx $L(right_x); set cx [expr {($lx+$rx)/2}]

        dui add dtext $page $cx $L(header_solo_title_y) -tags page_title -text [translate "Delete -- Step 2: Confirm"] \
            -font $L(font_section) -width $L(content_w) -fill $L(danger) -anchor center -justify center

        # Typed confirmation input stays in the top half of the screen (Android
        # keyboard covers the bottom).
        dui add dtext $page $lx $L(toolbar_y0) -tags confirm_instructions -text "" \
            -font $L(font_body) -width $L(content_w) -fill $L(text_body) -anchor nw -justify left
        dui add entry $page $lx [expr {$L(toolbar_y0)+3*$L(lg)}] -tags confirm_entry \
            -textvariable ::plugins::ShotHistoryEditor::confirm_input \
            -width 20 -font $L(font_primary) -borderwidth 1 -bg $L(entry_danger_bg) -foreground $L(danger) -relief flat \
            -label [translate "Type the number here"] -label_pos [list $lx [expr {$L(toolbar_y0)+2*$L(lg)}]] \
            -label_font $L(font_body) -label_width $L(label_col_w) -label_fill $L(text_body)
        dui add dtext $page $lx [expr {$L(toolbar_y0)+5*$L(lg)}] -tags confirm_error_text -text "" \
            -font $L(font_caption) -width $L(content_w) -fill $L(danger) -anchor nw -justify left

        set right_btn_x1 [expr {$rx-$L(btn_w_std)}]
        set left_btn_x1 [expr {$right_btn_x1-$L(sm)-$L(btn_w_std)}]
        # v0.6.2: Cancel to the far left; Delete stays on the right.
        dui add dbutton $page $lx $L(bar_y0) [expr {$lx+$L(btn_w_std)}] $L(bar_y1) -tags cancel \
            -label [translate "Cancel"] -command ::plugins::ShotHistoryEditor::cancel_delete_confirm \
            -label_font $L(font_button) -style she_btn
        dui add dbutton $page $right_btn_x1 $L(bar_y0) $rx $L(bar_y1) -tags confirm_delete \
            -label [translate "Confirm Delete"] -label_fill $L(danger) \
            -command ::plugins::ShotHistoryEditor::confirm_delete_submit \
            -label_font $L(font_button) -style she_btn
    }

    proc show {page_to_hide page_to_show} {
        ::plugins::ShotHistoryEditor::refresh_delete_confirm_page $page_to_show
    }
}

namespace eval ::dui::pages::ShotHistoryEditor_delete_result {
    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::ShotHistoryEditor::L L
        ::plugins::ShotHistoryEditor::_page_bg $page
        set lx $L(left_x); set rx $L(right_x); set cx [expr {($lx+$rx)/2}]

        dui add dtext $page $cx $L(header_solo_title_y) -tags page_title -text [translate "Delete Result"] \
            -font $L(font_section) -width $L(content_w) -fill $L(text_body) -anchor center -justify center
        dui add dtext $page $lx $L(list_top) -tags result_text -text "" \
            -font $L(font_body) -width $L(content_w) -fill $L(text_body) -anchor nw -justify left

        # v0.6.2: Done at the FAR LEFT, like every other page in this plugin
        # now and like the card list it returns to.
        dui add dbutton $page $lx $L(bar_y0) [expr {$lx+$L(btn_w_std)}] $L(bar_y1) -tags page_done \
            -label [translate "Done"] -command ::plugins::ShotHistoryEditor::close_delete_result \
            -label_font $L(font_button) -style she_btn
    }

    proc show {page_to_hide page_to_show} {
        ::plugins::ShotHistoryEditor::refresh_delete_result_page $page_to_show
    }
}

namespace eval ::dui::pages::ShotHistoryEditor_edit_confirm {
    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::ShotHistoryEditor::L L
        ::plugins::ShotHistoryEditor::_page_bg $page
        set lx $L(left_x); set rx $L(right_x); set cx [expr {($lx+$rx)/2}]

        dui add dtext $page $cx $L(header_solo_title_y) -tags page_title -text [translate "Save -- Confirm Change"] \
            -font $L(font_section) -width $L(content_w) -fill $L(danger) -anchor center -justify center

        dui add dtext $page $lx $L(toolbar_y0) -tags confirm_shot_text -text "" \
            -font $L(font_body) -width $L(content_w) -fill $L(text_body) -anchor nw -justify left
        dui add dtext $page $lx [expr {$L(toolbar_y0)+$L(lg)}] -tags confirm_file_text -text "" \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) -anchor nw -justify left
        dui add dtext $page $lx [expr {$L(toolbar_y0)+2*$L(lg)}] -tags confirm_field_text -text "" \
            -font $L(font_body) -width $L(content_w) -fill $L(text_body) -anchor nw -justify left
        dui add dtext $page $lx [expr {$L(toolbar_y0)+3*$L(lg)}] -tags confirm_before_text -text "" \
            -font $L(font_primary) -width $L(content_w) -fill $L(text_body) -anchor nw -justify left
        dui add dtext $page $lx [expr {$L(toolbar_y0)+4*$L(lg)}] -tags confirm_after_text -text "" \
            -font $L(font_primary) -width $L(content_w) -fill $L(danger) -anchor nw -justify left
        dui add dtext $page $lx [expr {$L(toolbar_y0)+5*$L(lg)}] -tags confirm_warning_text -text "" \
            -font $L(font_caption) -width $L(content_w) -fill $L(warn) -anchor nw -justify left

        # v0.6.2: Cancel takes the far-left slot -- it is this page's way out,
        # the same role Done plays everywhere else, so backing out of the
        # whole flow is the same corner every time.
        #
        # Save Change deliberately does NOT move. It is the destructive
        # button, and the one place it must not be is under the thumb that is
        # tapping bottom-left repeatedly to leave.
        dui add dbutton $page $lx $L(bar_y0) [expr {$lx+$L(btn_w_std)}] $L(bar_y1) -tags cancel \
            -label [translate "Cancel"] -command ::plugins::ShotHistoryEditor::cancel_edit_confirm \
            -label_font $L(font_button) -style she_btn
        dui add dbutton $page [expr {$rx-$L(btn_w_std)}] $L(bar_y0) $rx $L(bar_y1) -tags save_change \
            -label [translate "Save Change"] -label_fill $L(danger) \
            -command ::plugins::ShotHistoryEditor::confirm_save_submit \
            -label_font $L(font_button) -style she_btn
    }

    proc show {page_to_hide page_to_show} {
        ::plugins::ShotHistoryEditor::refresh_edit_confirm_page $page_to_show
    }
}

namespace eval ::dui::pages::ShotHistoryEditor_edit_result {
    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::ShotHistoryEditor::L L
        ::plugins::ShotHistoryEditor::_page_bg $page
        set lx $L(left_x); set rx $L(right_x); set cx [expr {($lx+$rx)/2}]

        dui add dtext $page $cx $L(header_solo_title_y) -tags page_title -text [translate "Save Result"] \
            -font $L(font_section) -width $L(content_w) -fill $L(text_body) -anchor center -justify center
        dui add dtext $page $lx $L(list_top) -tags edit_result_text -text "" \
            -font $L(font_body) -width $L(content_w) -fill $L(text_body) -anchor nw -justify left

        # v0.6.2: Done at the FAR LEFT. This is the page you land on after
        # saving, so it is the one whose Done gets tapped straight after
        # another one.
        dui add dbutton $page $lx $L(bar_y0) [expr {$lx+$L(btn_w_std)}] $L(bar_y1) -tags page_done \
            -label [translate "Done"] -command ::plugins::ShotHistoryEditor::close_edit_result \
            -label_font $L(font_button) -style she_btn
    }

    proc show {page_to_hide page_to_show} {
        ::plugins::ShotHistoryEditor::refresh_edit_result_page $page_to_show
    }
}

namespace eval ::dui::pages::ShotHistoryEditor_trash {
    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::ShotHistoryEditor::L L
        ::plugins::ShotHistoryEditor::_page_bg $page
        set lx $L(left_x); set rx $L(right_x); set cx [expr {($lx+$rx)/2}]
        set restore_w $L(btn_w_std)
        set text_w [expr {$L(content_w)-$restore_w-$L(lg)}]

        dui add dtext $page $cx $L(header_solo_title_y) -tags page_title -text [translate "Trash / Restore"] \
            -font $L(font_section) -width $L(content_w) -fill $L(text_body) -anchor center -justify center
        dui add dtext $page $lx $L(toolbar_y0) -tags trash_status -text "" \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) -anchor nw -justify left

        set header_y [expr {$L(toolbar_y1)+$L(sm)}]
        dui add dtext $page $lx $header_y -tags header \
            -text "Deleted  |  shots, files  |  batch id" \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_body) -anchor nw -justify left

        set n_rows $::plugins::ShotHistoryEditor::trash_page_size
        set list_start [expr {$header_y+$L(caption_h)+$L(md)}]
        set list_end [expr {$L(bar_y0)-$L(md)}]
        set row_h [expr {double($list_end-$list_start)/$n_rows}]
        # v0.8.5: each row is a band of row_h; the text line and the button
        # are both centred in it, and the button takes the design-system
        # height (btn_h, the 60 px touch minimum) when the band allows, else
        # the band minus sm. Was a fixed 0.7 x btn_h = 42 physical px.
        set row_btn_h [expr {min($L(btn_h), $row_h - $L(sm))}]
        for {set i 0} {$i < $n_rows} {incr i} {
            set band_top [expr {$list_start + $i*$row_h}]
            set ty [expr {$band_top + ($row_h - $L(caption_h))/2.0}]
            set by0 [expr {$band_top + ($row_h - $row_btn_h)/2.0}]
            dui add dtext $page $lx $ty -tags row${i}_text -text "" \
                -font $L(font_caption) -width $text_w -fill $L(text_body) -anchor nw -justify left
            dui add dbutton $page [expr {$rx-$restore_w}] $by0 $rx [expr {$by0+$row_btn_h}] \
                -tags row${i}_restore -label [translate "Restore"] \
                -command "::plugins::ShotHistoryEditor::restore_row $i" -label_font $L(font_button) -style she_btn
        }

        # v0.6.2: Done leads the row from the far left; Back and the pager
        # keep their order behind it.
        set bw $L(btn_w_std)
        set x $lx
        dui add dbutton $page $x $L(bar_y0) [expr {$x+$bw}] $L(bar_y1) -tags page_done \
            -label [translate "Done"] -command ::dui::pages::ShotHistoryEditor_trash::page_done \
            -label_font $L(font_button) -style she_btn
        incr x [expr {$bw+$L(sm)}]
        dui add dbutton $page $x $L(bar_y0) [expr {$x+$bw}] $L(bar_y1) -tags back \
            -label [translate "Back"] -command {::plugins::ShotHistoryEditor::_return_to_page ShotHistoryEditor_advanced} \
            -label_font $L(font_button) -style she_btn
        incr x [expr {$bw+$L(sm)}]
        dui add dbutton $page $x $L(bar_y0) [expr {$x+$bw}] $L(bar_y1) -tags trash_prev_page \
            -label [translate "[::plugins::ShotHistoryEditor::_u 0x25c0] Prev"] -command {::plugins::ShotHistoryEditor::scroll_trash -1} \
            -label_font $L(font_button) -style she_btn
        # v0.9.1: Next beside Prev (was missing; see refresh_trash_page).
        incr x [expr {$bw+$L(sm)}]
        dui add dbutton $page $x $L(bar_y0) [expr {$x+$bw}] $L(bar_y1) -tags trash_next_page \
            -label [translate "Next [::plugins::ShotHistoryEditor::_u 0x25b6]"] -command {::plugins::ShotHistoryEditor::scroll_trash 1} \
            -label_font $L(font_button) -style she_btn
        # v0.11.0: far right, opens the Empty trash PREVIEW page (read-only).
        dui add dbutton $page [expr {$rx-$bw}] $L(bar_y0) $rx $L(bar_y1) -tags empty_preview \
            -label [translate "Empty trash..."] -command {::plugins::ShotHistoryEditor::open_page ShotHistoryEditor_empty_preview} \
            -label_font $L(font_button) -style she_btn
    }

    proc show {page_to_hide page_to_show} {
        set ::plugins::ShotHistoryEditor::trash_offset 0
        ::plugins::ShotHistoryEditor::refresh_trash_page $page_to_show
    }

    # Trash is only ever reached from Advanced, so that is always the real
    # target (matches this page's own Back button). v0.5.3: routed through
    # _return_to_page (close_dialog-based unwind) like every other internal
    # return -- see _return_to_page's note.
    proc page_done {} {
        ::plugins::ShotHistoryEditor::_return_to_page ShotHistoryEditor_advanced
    }
}

namespace eval ::dui::pages::ShotHistoryEditor_recent {
    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::ShotHistoryEditor::L L
        ::plugins::ShotHistoryEditor::_page_bg $page
        set lx $L(left_x); set rx $L(right_x); set cx [expr {($lx+$rx)/2}]
        set open_w $L(btn_w_std)
        set text_w [expr {$L(content_w)-$open_w-$L(lg)}]

        dui add dtext $page $cx $L(header_solo_title_y) -tags page_title -text [translate "Source Inspector"] \
            -font $L(font_section) -width $L(content_w) -fill $L(text_body) -anchor center -justify center
        dui add dtext $page $lx $L(toolbar_y0) -tags recent_status -text "" \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) -anchor nw -justify left
        set header_y [expr {$L(toolbar_y1)+$L(sm)}]
        dui add dtext $page $lx $header_y -tags header \
            -text "Date/time | Filename | Grind | Dose | Yield | Bean | Shot time" \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_body) -anchor nw -justify left

        # 8 rows must fit exactly between the header line and the bottom bar,
        # so row_h is derived from the actual available space (not a fixed
        # fraction of card_h) -- a fixed 0.68*card_h row height overflowed
        # past bar_y0 on an 8-row list at the reference resolution.
        # v0.8.6: the row count IS max_recent (7), so the list, the refresh
        # loop and the query always agree; with 7 rows the band is ~143
        # virtual and the button reaches the full btn_h (60 physical px).
        set n_rows $::plugins::ShotHistoryEditor::max_recent
        set list_start [expr {$header_y+$L(caption_h)+$L(md)}]
        set list_end [expr {$L(bar_y0)-$L(md)}]
        set row_h [expr {double($list_end-$list_start)/$n_rows}]
        # v0.8.5: centred bands, same as the Trash page.
        set row_btn_h [expr {min($L(btn_h), $row_h - $L(sm))}]
        for {set i 0} {$i < $n_rows} {incr i} {
            set band_top [expr {$list_start + $i*$row_h}]
            set ty [expr {$band_top + ($row_h - $L(caption_h))/2.0}]
            set by0 [expr {$band_top + ($row_h - $row_btn_h)/2.0}]
            dui add dtext $page $lx $ty -tags row${i}_text -text "" \
                -font $L(font_caption) -width $text_w -fill $L(text_body) -anchor nw -justify left
            dui add dbutton $page [expr {$rx-$open_w}] $by0 $rx [expr {$by0+$row_btn_h}] \
                -tags row${i}_open -label [translate "Open"] \
                -command "::plugins::ShotHistoryEditor::select_recent_row $i" -label_font $L(font_button) -style she_btn
        }

        # v0.6.2: Done at the far left, Back beside it.
        set bw $L(btn_w_std)
        dui add dbutton $page $lx $L(bar_y0) [expr {$lx+$bw}] $L(bar_y1) -tags page_done \
            -label [translate "Done"] -command ::dui::pages::ShotHistoryEditor_recent::page_done \
            -label_font $L(font_button) -style she_btn
        set back_x [expr {$lx+$bw+$L(sm)}]
        dui add dbutton $page $back_x $L(bar_y0) [expr {$back_x+$bw}] $L(bar_y1) -tags back \
            -label [translate "Back"] -command {::plugins::ShotHistoryEditor::_return_to_page ShotHistoryEditor_advanced} \
            -label_font $L(font_button) -style she_btn
    }

    proc show {page_to_hide page_to_show} {
        ::plugins::ShotHistoryEditor::refresh_recent_page $page_to_show
    }

    # Recent (Source Inspector) is only ever reached from Advanced. v0.5.3:
    # routed through _return_to_page like every other internal return.
    proc page_done {} {
        ::plugins::ShotHistoryEditor::_return_to_page ShotHistoryEditor_advanced
    }
}

namespace eval ::dui::pages::ShotHistoryEditor_detail {
    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::ShotHistoryEditor::L L
        ::plugins::ShotHistoryEditor::_page_bg $page
        set lx $L(left_x); set rx $L(right_x); set cx [expr {($lx+$rx)/2}]

        dui add dtext $page $cx $L(header_solo_title_y) -tags page_title -text [translate "Shot Detail"] \
            -font $L(font_section) -width $L(content_w) -fill $L(text_body) -anchor center -justify center
        dui add dtext $page $lx $L(toolbar_y0) -tags detail_page_status -text "" \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) -anchor nw -justify left
        dui add dtext $page $lx $L(list_top) -tags detail_text -text "" \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_body) -anchor nw -justify left

        set bw $L(btn_w_std)
        # v0.6.2: Done leads, then Back / Prev / Next in their existing order,
        # and Edit Metadata Preview still fills the rest of the bar. Every
        # button keeps the width it had -- the wide one included, since it
        # gains on the right exactly what the row lost on the left.
        set x $lx
        dui add dbutton $page $x $L(bar_y0) [expr {$x+$bw}] $L(bar_y1) -tags page_done \
            -label [translate "Done"] -command ::dui::pages::ShotHistoryEditor_detail::page_done \
            -label_font $L(font_button) -style she_btn
        incr x [expr {$bw+$L(sm)}]
        dui add dbutton $page $x $L(bar_y0) [expr {$x+$bw}] $L(bar_y1) -tags back \
            -label [translate "Back"] -command {::plugins::ShotHistoryEditor::_return_to_page ShotHistoryEditor_recent} \
            -label_font $L(font_button) -style she_btn
        incr x [expr {$bw+$L(sm)}]
        dui add dbutton $page $x $L(bar_y0) [expr {$x+$bw}] $L(bar_y1) -tags prev_page \
            -label [translate "Prev"] -command {::plugins::ShotHistoryEditor::scroll_page detail -1 ShotHistoryEditor_detail} \
            -label_font $L(font_button) -style she_btn
        incr x [expr {$bw+$L(sm)}]
        dui add dbutton $page $x $L(bar_y0) [expr {$x+$bw}] $L(bar_y1) -tags next_page \
            -label [translate "Next"] -command {::plugins::ShotHistoryEditor::scroll_page detail 1 ShotHistoryEditor_detail} \
            -label_font $L(font_button) -style she_btn
        incr x [expr {$bw+$L(sm)}]
        dui add dbutton $page $x $L(bar_y0) $rx $L(bar_y1) -tags edit_preview \
            -label [translate "Edit Metadata Preview"] -command {::plugins::ShotHistoryEditor::open_edit_preview ShotHistoryEditor_detail} \
            -label_font $L(font_button) -style she_btn
    }

    proc show {page_to_hide page_to_show} {
        set ::plugins::ShotHistoryEditor::detail_page_index 0
        ::plugins::ShotHistoryEditor::scroll_page detail 0 $page_to_show
    }

    # Shot Detail is only ever reached from Recent, matching its Back button.
    # v0.5.3: routed through _return_to_page like every other internal return.
    proc page_done {} {
        ::plugins::ShotHistoryEditor::_return_to_page ShotHistoryEditor_recent
    }
}

namespace eval ::dui::pages::ShotHistoryEditor_edit_preview {
    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::ShotHistoryEditor::L L
        ::plugins::ShotHistoryEditor::_page_bg $page
        set lx $L(left_x); set rx $L(right_x); set cx [expr {($lx+$rx)/2}]
        set vx $L(value_x)

        dui add dtext $page $cx $L(header_solo_title_y) -tags page_title -text [translate "Edit Preview"] \
            -font $L(font_section) -width $L(content_w) -fill $L(text_body) -anchor center -justify center
        dui add dtext $page $lx $L(toolbar_y0) -tags selected_shot -text "" \
            -font $L(font_body) -width $L(content_w) -fill $L(text_body) -anchor nw -justify left
        dui add dtext $page $lx [expr {$L(toolbar_y0)+$L(lg)}] -tags editable_source -text "" \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) -anchor nw -justify left

        set row1_y $L(list_top)
        dui add dtext $page $lx $row1_y -tags fs_label -text [translate "Field selector"] \
            -font $L(font_body) -width $L(label_col_w) -fill $L(text_body) -anchor nw -justify left
        dui add dtext $page $vx $row1_y -tags field_value -text "" \
            -font $L(font_body) -width [expr {$rx-$L(btn_w_wide)-$L(lg)-$vx}] -fill $L(value_blue) -anchor nw -justify left
        dui add dbutton $page [expr {$rx-$L(btn_w_wide)}] [expr {$row1_y-$L(sm)}] $rx [expr {$row1_y-$L(sm)+$L(btn_h)}] \
            -tags next_field -label [translate "Next Field"] \
            -command ::plugins::ShotHistoryEditor::cycle_edit_field -label_font $L(font_button) -style she_btn

        set row2_y [expr {$row1_y+$L(btn_h)+$L(lg)}]
        dui add dtext $page $lx $row2_y -tags cv_label -text [translate "Current value"] \
            -font $L(font_body) -width $L(label_col_w) -fill $L(text_body) -anchor nw -justify left
        dui add dtext $page $vx $row2_y -tags current_value -text "" \
            -font $L(font_body) -width [expr {$rx-$vx}] -fill $L(text_body) -anchor nw -justify left

        set row3_y [expr {$row2_y+$L(xxl)}]
        dui add entry $page $lx [expr {$row3_y+$L(xl)}] -tags new_value \
            -textvariable ::plugins::ShotHistoryEditor::edit_new_value \
            -width 42 -font $L(font_body) -borderwidth 1 -bg $L(entry_bg) -foreground $L(value_blue) -relief flat \
            -label [translate "New value"] -label_pos [list $lx $row3_y] \
            -label_font $L(font_body) -label_width $L(label_col_w) -label_fill $L(text_body)

        dui add dbutton $page [expr {$rx-$L(btn_w_wide)}] $row3_y $rx [expr {$row3_y+$L(btn_h)}] \
            -tags preview_change -label [translate "Preview Change"] \
            -command ::plugins::ShotHistoryEditor::preview_change -label_font $L(font_button) -style she_btn

        # v0.5.0: the one new control on this otherwise-unchanged page. Goes
        # to the Before/After Confirm page (Step 2 of the real save flow);
        # it does not write anything itself.
        set row4_y [expr {$row3_y+$L(btn_h)+$L(md)}]
        dui add dbutton $page [expr {$rx-$L(btn_w_wide)}] $row4_y $rx [expr {$row4_y+$L(btn_h)}] \
            -tags save_change -label [translate "Save Change"] -label_fill $L(danger) \
            -command ::plugins::ShotHistoryEditor::open_edit_confirm -label_font $L(font_button) -style she_btn

        set status_y [expr {$row4_y+$L(btn_h)+$L(xxl)}]
        dui add dtext $page $lx $status_y -tags preview_status -text "" \
            -font $L(font_caption) -width $L(content_w) -fill $L(warn) -anchor nw -justify left
        dui add dtext $page $lx [expr {$status_y+$L(xl)}] -tags preview_text -text "" \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_body) -anchor nw -justify left

        # v0.6.1, owner request: Done sits at the FAR LEFT on this page, not
        # the far right.
        #
        # This page's Done returns to the card list, whose own Done is the
        # bar's left button (bar_left, and the design system's "Done left /
        # Advanced right"). With Done here on the right, leaving the editor
        # meant tapping the bottom-right corner and then the bottom-LEFT one.
        # Aligned, it is the same spot twice.
        #
        # Back keeps its place beside Done rather than moving to the far
        # right: on this page the two run the identical command
        # (page_done reuses back_from_edit_preview), so separating them across
        # the bar would suggest a difference that does not exist.
        set done_x1 $lx
        set back_x1 [expr {$done_x1+$L(btn_w_std)+$L(sm)}]
        dui add dbutton $page $done_x1 $L(bar_y0) [expr {$done_x1+$L(btn_w_std)}] $L(bar_y1) -tags page_done \
            -label [translate "Done"] -command ::dui::pages::ShotHistoryEditor_edit_preview::page_done \
            -label_font $L(font_button) -style she_btn
        dui add dbutton $page $back_x1 $L(bar_y0) [expr {$back_x1+$L(btn_w_std)}] $L(bar_y1) -tags back \
            -label [translate "Back"] -command ::plugins::ShotHistoryEditor::back_from_edit_preview \
            -label_font $L(font_button) -style she_btn
    }

    proc show {page_to_hide page_to_show} {
        ::plugins::ShotHistoryEditor::refresh_edit_preview_page $page_to_show
    }

    # v0.5.2: was a raw dui page close_dialog -- see _navigate_done's note.
    # Reuses back_from_edit_preview so Done and Back agree on the same real
    # target (edit_return_page), same as before this fix in the normal case.
    proc page_done {} {
        ::plugins::ShotHistoryEditor::back_from_edit_preview
    }
}

namespace eval ::dui::pages::ShotHistoryEditor_diagnostics {
    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::ShotHistoryEditor::L L
        ::plugins::ShotHistoryEditor::_page_bg $page
        set lx $L(left_x); set rx $L(right_x); set cx [expr {($lx+$rx)/2}]

        dui add dtext $page $cx $L(header_solo_title_y) -tags page_title -text [translate "Diagnostics"] \
            -font $L(font_section) -width $L(content_w) -fill $L(text_body) -anchor center -justify center
        dui add dtext $page $lx $L(toolbar_y0) -tags diagnostics_page_status -text "" \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) -anchor nw -justify left
        dui add dtext $page $lx $L(list_top) -tags diagnostics_text -text "" \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_body) -anchor nw -justify left

        # v0.6.2: the row starts one slot in, because Done now occupies the
        # far-left slot (added at the end of this block).
        set bw $L(btn_w_std)
        set x [expr {$lx+$bw+$L(sm)}]
        dui add dbutton $page $x $L(bar_y0) [expr {$x+$bw}] $L(bar_y1) -tags back \
            -label [translate "Back"] -command {::plugins::ShotHistoryEditor::_return_to_page ShotHistoryEditor_advanced} \
            -label_font $L(font_button) -style she_btn
        incr x [expr {$bw+$L(sm)}]
        dui add dbutton $page $x $L(bar_y0) [expr {$x+$bw}] $L(bar_y1) -tags prev_page \
            -label [translate "Prev"] -command {::plugins::ShotHistoryEditor::scroll_page diagnostics -1 ShotHistoryEditor_diagnostics} \
            -label_font $L(font_button) -style she_btn
        incr x [expr {$bw+$L(sm)}]
        dui add dbutton $page $x $L(bar_y0) [expr {$x+$bw}] $L(bar_y1) -tags next_page \
            -label [translate "Next"] -command {::plugins::ShotHistoryEditor::scroll_page diagnostics 1 ShotHistoryEditor_diagnostics} \
            -label_font $L(font_button) -style she_btn
        # v0.6.2: Done moved from the far right to the far left. It is added
        # last but positioned first, so Back/Prev/Next keep the x values they
        # already had and only Done changes place.
        dui add dbutton $page $lx $L(bar_y0) [expr {$lx+$bw}] $L(bar_y1) -tags page_done \
            -label [translate "Done"] -command ::dui::pages::ShotHistoryEditor_diagnostics::page_done \
            -label_font $L(font_button) -style she_btn
    }

    proc show {page_to_hide page_to_show} {
        set ::plugins::ShotHistoryEditor::diagnostics_page_index 0
        ::plugins::ShotHistoryEditor::scroll_page diagnostics 0 $page_to_show
    }

    # Diagnostics is only ever reached from Advanced, matching its Back button.
    # v0.5.3: routed through _return_to_page like every other internal return.
    proc page_done {} {
        ::plugins::ShotHistoryEditor::_return_to_page ShotHistoryEditor_advanced
    }
}

namespace eval ::dui::pages::ShotHistoryEditor_help {
    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::ShotHistoryEditor::L L
        ::plugins::ShotHistoryEditor::_page_bg $page
        set lx $L(left_x); set rx $L(right_x); set cx [expr {($lx+$rx)/2}]

        dui add dtext $page $cx $L(header_solo_title_y) -tags page_title -text [translate "Help / Guide"] \
            -font $L(font_section) -width $L(content_w) -fill $L(text_body) -anchor center -justify center

        dui add dtext $page $lx $L(toolbar_y0) -tags help_page_status -text "" \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) -anchor nw -justify left
        dui add dtext $page $lx $L(list_top) -tags help_text -text "" \
            -font $L(font_body) -width $L(content_w) -fill $L(text_body) -anchor nw -justify left

        # v0.6.2: the row starts one slot in, because Done now occupies the
        # far-left slot (added at the end of this block).
        set bw $L(btn_w_std)
        set x [expr {$lx+$bw+$L(sm)}]
        dui add dbutton $page $x $L(bar_y0) [expr {$x+$bw}] $L(bar_y1) -tags back \
            -label [translate "Back"] -command {::plugins::ShotHistoryEditor::_return_to_page ShotHistoryEditor_advanced} \
            -label_font $L(font_button) -style she_btn
        incr x [expr {$bw+$L(sm)}]
        dui add dbutton $page $x $L(bar_y0) [expr {$x+$bw}] $L(bar_y1) -tags prev_page \
            -label [translate "Prev"] -command {::plugins::ShotHistoryEditor::scroll_page help -1 ShotHistoryEditor_help} \
            -label_font $L(font_button) -style she_btn
        incr x [expr {$bw+$L(sm)}]
        dui add dbutton $page $x $L(bar_y0) [expr {$x+$bw}] $L(bar_y1) -tags next_page \
            -label [translate "Next"] -command {::plugins::ShotHistoryEditor::scroll_page help 1 ShotHistoryEditor_help} \
            -label_font $L(font_button) -style she_btn
        # v0.6.2: Done moved from the far right to the far left. Added last,
        # positioned first, so the other three keep their existing x values.
        dui add dbutton $page $lx $L(bar_y0) [expr {$lx+$bw}] $L(bar_y1) -tags page_done \
            -label [translate "Done"] -command ::dui::pages::ShotHistoryEditor_help::page_done \
            -label_font $L(font_button) -style she_btn
    }

    proc show {page_to_hide page_to_show} {
        set ::plugins::ShotHistoryEditor::help_page_index 0
        ::plugins::ShotHistoryEditor::scroll_page help 0 $page_to_show
    }

    # Help is only ever reached from Advanced, matching its Back button.
    # v0.5.3: routed through _return_to_page like every other internal return.
    proc page_done {} {
        ::plugins::ShotHistoryEditor::_return_to_page ShotHistoryEditor_advanced
    }
}

# v0.9.0: reconciliation view. v0.10.0: a row list with an Unhide button per
# row and the Trash-style pager (was paged text). Rows are centred bands of
# three caption lines; layout mirrors the Trash page.
namespace eval ::dui::pages::ShotHistoryEditor_reconcile {
    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::ShotHistoryEditor::L L
        ::plugins::ShotHistoryEditor::_page_bg $page
        set lx $L(left_x); set rx $L(right_x); set cx [expr {($lx+$rx)/2}]
        set unhide_w $L(btn_w_std)
        set text_w [expr {$L(content_w)-$unhide_w-$L(lg)}]

        dui add dtext $page $cx $L(header_solo_title_y) -tags page_title -text [translate "Reconcile hidden shots"] \
            -font $L(font_section) -width $L(content_w) -fill $L(text_body) -anchor center -justify center
        dui add dtext $page $lx $L(toolbar_y0) -tags reconcile_status -text "" \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) -anchor nw -justify left

        # Two status lines can sit above this header: toolbar_y0 + 2 caption
        # lines + sm.
        set header_y [expr {$L(toolbar_y0)+2*$L(caption_h)+$L(sm)}]
        dui add dtext $page $lx $header_y -tags header \
            -text "Shot  |  deleted when, batch  |  on disk vs trash copy  |  SDB" \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_body) -anchor nw -justify left

        set n_rows $::plugins::ShotHistoryEditor::reconcile_page_size
        set list_start [expr {$header_y+$L(caption_h)+$L(md)}]
        set list_end [expr {$L(bar_y0)-$L(md)}]
        set row_h [expr {double($list_end-$list_start)/$n_rows}]
        set row_btn_h [expr {min($L(btn_h), $row_h - $L(sm))}]
        for {set i 0} {$i < $n_rows} {incr i} {
            set band_top [expr {$list_start + $i*$row_h}]
            set ty [expr {$band_top + ($row_h - 3*$L(caption_h))/2.0}]
            set by0 [expr {$band_top + ($row_h - $row_btn_h)/2.0}]
            dui add dtext $page $lx $ty -tags row${i}_text -text "" \
                -font $L(font_caption) -width $text_w -fill $L(text_body) -anchor nw -justify left
            dui add dbutton $page [expr {$rx-$unhide_w}] $by0 $rx [expr {$by0+$row_btn_h}] \
                -tags row${i}_unhide -label [translate "Unhide"] \
                -command "::plugins::ShotHistoryEditor::unhide_row $i" -label_font $L(font_button) -style she_btn
        }

        set bw $L(btn_w_std)
        set x $lx
        dui add dbutton $page $x $L(bar_y0) [expr {$x+$bw}] $L(bar_y1) -tags page_done \
            -label [translate "Done"] -command ::dui::pages::ShotHistoryEditor_reconcile::page_done \
            -label_font $L(font_button) -style she_btn
        incr x [expr {$bw+$L(sm)}]
        dui add dbutton $page $x $L(bar_y0) [expr {$x+$bw}] $L(bar_y1) -tags back \
            -label [translate "Back"] -command {::plugins::ShotHistoryEditor::_return_to_page ShotHistoryEditor_advanced} \
            -label_font $L(font_button) -style she_btn
        incr x [expr {$bw+$L(sm)}]
        dui add dbutton $page $x $L(bar_y0) [expr {$x+$bw}] $L(bar_y1) -tags reconcile_prev_page \
            -label [translate "[::plugins::ShotHistoryEditor::_u 0x25c0] Prev"] -command {::plugins::ShotHistoryEditor::scroll_reconcile -1} \
            -label_font $L(font_button) -style she_btn
        incr x [expr {$bw+$L(sm)}]
        dui add dbutton $page $x $L(bar_y0) [expr {$x+$bw}] $L(bar_y1) -tags reconcile_next_page \
            -label [translate "Next [::plugins::ShotHistoryEditor::_u 0x25b6]"] -command {::plugins::ShotHistoryEditor::scroll_reconcile 1} \
            -label_font $L(font_button) -style she_btn
    }

    proc show {page_to_hide page_to_show} {
        set ::plugins::ShotHistoryEditor::reconcile_offset 0
        set ::plugins::ShotHistoryEditor::reconcile_note ""
        ::plugins::ShotHistoryEditor::refresh_reconcile_page $page_to_show
    }

    # Only ever reached from Advanced, matching its Back button.
    proc page_done {} {
        ::plugins::ShotHistoryEditor::_return_to_page ShotHistoryEditor_advanced
    }
}

# v0.11.0: Empty trash PREVIEW. Diagnostics skeleton (paged text, Done / Back /
# Prev / Next); content from empty_trash_preview_text; reached from the Trash
# page and returns there. Nothing on this page deletes anything.
namespace eval ::dui::pages::ShotHistoryEditor_empty_preview {
    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::ShotHistoryEditor::L L
        ::plugins::ShotHistoryEditor::_page_bg $page
        set lx $L(left_x); set rx $L(right_x); set cx [expr {($lx+$rx)/2}]

        dui add dtext $page $cx $L(header_solo_title_y) -tags page_title -text [translate "Empty trash - preview"] \
            -font $L(font_section) -width $L(content_w) -fill $L(text_body) -anchor center -justify center
        dui add dtext $page $lx $L(toolbar_y0) -tags empty_preview_page_status -text "" \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) -anchor nw -justify left
        dui add dtext $page $lx $L(list_top) -tags empty_preview_text -text "" \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_body) -anchor nw -justify left

        set bw $L(btn_w_std)
        set x [expr {$lx+$bw+$L(sm)}]
        dui add dbutton $page $x $L(bar_y0) [expr {$x+$bw}] $L(bar_y1) -tags back \
            -label [translate "Back"] -command {::plugins::ShotHistoryEditor::_return_to_page ShotHistoryEditor_trash} \
            -label_font $L(font_button) -style she_btn
        incr x [expr {$bw+$L(sm)}]
        dui add dbutton $page $x $L(bar_y0) [expr {$x+$bw}] $L(bar_y1) -tags prev_page \
            -label [translate "Prev"] -command {::plugins::ShotHistoryEditor::scroll_page empty_preview -1 ShotHistoryEditor_empty_preview} \
            -label_font $L(font_button) -style she_btn
        incr x [expr {$bw+$L(sm)}]
        dui add dbutton $page $x $L(bar_y0) [expr {$x+$bw}] $L(bar_y1) -tags next_page \
            -label [translate "Next"] -command {::plugins::ShotHistoryEditor::scroll_page empty_preview 1 ShotHistoryEditor_empty_preview} \
            -label_font $L(font_button) -style she_btn
        dui add dbutton $page $lx $L(bar_y0) [expr {$lx+$bw}] $L(bar_y1) -tags page_done \
            -label [translate "Done"] -command ::dui::pages::ShotHistoryEditor_empty_preview::page_done \
            -label_font $L(font_button) -style she_btn
        # v0.12.0: the real action, far right, danger label; hidden while the
        # trash is empty. Opens the typed confirmation; deletes nothing itself.
        dui add dbutton $page [expr {$rx-$bw}] $L(bar_y0) $rx $L(bar_y1) -tags empty_now \
            -label [translate "Empty trash"] -label_fill $L(danger) \
            -command ::plugins::ShotHistoryEditor::open_purge_confirm \
            -label_font $L(font_button) -style she_btn
    }

    proc show {page_to_hide page_to_show} {
        set ::plugins::ShotHistoryEditor::empty_preview_page_index 0
        ::plugins::ShotHistoryEditor::scroll_page empty_preview 0 $page_to_show
        if {[llength [::plugins::ShotHistoryEditor::_trash_batches]] > 0} {
            catch { dui item show $page_to_show empty_now* -initial 1 }
        } else {
            catch { dui item hide $page_to_show empty_now* -initial 1 }
        }
    }

    # Only ever reached from the Trash page, matching its Back button.
    proc page_done {} {
        ::plugins::ShotHistoryEditor::_return_to_page ShotHistoryEditor_trash
    }
}

# v0.12.0: Empty trash -- typed confirmation (copy of the delete confirm page;
# the entry stays in the top half for the Android keyboard).
namespace eval ::dui::pages::ShotHistoryEditor_purge_confirm {
    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::ShotHistoryEditor::L L
        ::plugins::ShotHistoryEditor::_page_bg $page
        set lx $L(left_x); set rx $L(right_x); set cx [expr {($lx+$rx)/2}]

        dui add dtext $page $cx $L(header_solo_title_y) -tags page_title -text [translate "Empty trash -- Confirm (permanent)"] \
            -font $L(font_section) -width $L(content_w) -fill $L(danger) -anchor center -justify center
        dui add dtext $page $lx $L(toolbar_y0) -tags purge_instructions -text "" \
            -font $L(font_body) -width $L(content_w) -fill $L(text_body) -anchor nw -justify left
        dui add entry $page $lx [expr {$L(toolbar_y0)+3*$L(lg)}] -tags purge_entry \
            -textvariable ::plugins::ShotHistoryEditor::purge_input \
            -width 20 -font $L(font_primary) -borderwidth 1 -bg $L(entry_danger_bg) -foreground $L(danger) -relief flat \
            -label [translate "Type the number here"] -label_pos [list $lx [expr {$L(toolbar_y0)+2*$L(lg)}]] \
            -label_font $L(font_body) -label_width $L(label_col_w) -label_fill $L(text_body)
        dui add dtext $page $lx [expr {$L(toolbar_y0)+5*$L(lg)}] -tags purge_error_text -text "" \
            -font $L(font_caption) -width $L(content_w) -fill $L(danger) -anchor nw -justify left

        dui add dbutton $page $lx $L(bar_y0) [expr {$lx+$L(btn_w_std)}] $L(bar_y1) -tags cancel \
            -label [translate "Cancel"] -command ::plugins::ShotHistoryEditor::cancel_purge_confirm \
            -label_font $L(font_button) -style she_btn
        dui add dbutton $page [expr {$rx-$L(btn_w_wide)}] $L(bar_y0) $rx $L(bar_y1) -tags purge_confirm_btn \
            -label [translate "Remove permanently"] -label_fill $L(danger) \
            -command ::plugins::ShotHistoryEditor::confirm_purge_submit \
            -label_font $L(font_button) -style she_btn
    }

    proc show {page_to_hide page_to_show} {
        ::plugins::ShotHistoryEditor::refresh_purge_confirm_page $page_to_show
    }
}

namespace eval ::dui::pages::ShotHistoryEditor_purge_result {
    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::ShotHistoryEditor::L L
        ::plugins::ShotHistoryEditor::_page_bg $page
        set lx $L(left_x); set rx $L(right_x); set cx [expr {($lx+$rx)/2}]

        dui add dtext $page $cx $L(header_solo_title_y) -tags page_title -text [translate "Empty trash - result"] \
            -font $L(font_section) -width $L(content_w) -fill $L(text_body) -anchor center -justify center
        dui add dtext $page $lx $L(list_top) -tags purge_result_text -text "" \
            -font $L(font_body) -width $L(content_w) -fill $L(text_body) -anchor nw -justify left

        dui add dbutton $page $lx $L(bar_y0) [expr {$lx+$L(btn_w_std)}] $L(bar_y1) -tags page_done \
            -label [translate "Done"] -command ::plugins::ShotHistoryEditor::close_purge_result \
            -label_font $L(font_button) -style she_btn
    }

    proc show {page_to_hide page_to_show} {
        ::plugins::ShotHistoryEditor::refresh_purge_result_page $page_to_show
    }
}
