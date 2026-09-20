#
# Bean Scanner -- a plugin for the Decent Espresso DE1app
# Copyright (C) 2026 Blastize
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
# more details. You should have received a copy of the GNU General Public
# License along with this program. If not, see <https://www.gnu.org/licenses/>.
#
# ---------------------------------------------------------------------------
#
# Bean Scanner -- implementation
#
# Pipeline:  camera preview -> JPEG capture -> base64 -> vision API (Anthropic
# or OpenAI) -> strict JSON -> review page -> DYE next-shot update on Accept.
#
# Safety: no SQL of any kind, no history/ or history_v2/ access, no direct
# ::settings writes. The single write path is
# ::plugins::DYE::shots::source_next_from, called only from the review page's
# Accept button.
#

package require http
package require tls
package require json

namespace eval ::plugins::BeanScanner {

    # ==================================================================
    #  Navigation state
    #
    #  These MUST have namespace-level defaults. _exit_settings reads
    #  _settings_return_page without a catch, so when it had no default and
    #  the plugin was entered at a sub-page (nothing had assigned it yet),
    #  Done threw "can't read _settings_return_page: no such variable" and
    #  silently did nothing -- a button that looked dead with no error on
    #  screen. Declaring them here makes that failure impossible.
    # ==================================================================

    variable _settings_return_page ""
    variable _entered_at_subpage   0

    # ==================================================================
    #  Settings helpers
    # ==================================================================

    proc apply_defaults {} {
        variable settings
        foreach {k v} {
            provider            anthropic
            model_anthropic     claude-opus-5
            model_openai        gpt-4o
            api_key_anthropic   {}
            api_key_openai      {}
            max_tokens          1500
            request_timeout_ms  90000
            camera_pref         front
            preview_size        640x480
            capture_size        1600x1200
            capture_retries     24
            capture_poll_ms     250
            preview_poll_ms     150
            max_image_bytes     4000000
            import_dir          /sdcard/DCIM/Camera
            max_photos          6
            screen_flash_ms     600
            apply_bean_brand    1
            apply_bean_type     1
            apply_roast_date    1
            apply_roast_level   1
            apply_bean_notes    1
            overwrite_existing  1
        } {
            if {![info exists settings($k)] || $settings($k) eq ""} {
                # Empty string is a legitimate value for the API keys.
                if {$k in {api_key_anthropic api_key_openai}} {
                    if {![info exists settings($k)]} { set settings($k) $v }
                } else {
                    set settings($k) $v
                }
            }
        }
        # v0.5.0: UI theme. "" (follow the skin) is a legitimate value,
        # so it lives outside the empty-resets loop above.
        if {![info exists settings(theme)] || $settings(theme) ni {{} light dark}} {
            set settings(theme) {}
        }
        # v0.8.0: flash_mode (off/on/auto) replaces the v0.6-0.7 boolean
        # flash_enabled; an enabled flash migrates to "on".
        if {![info exists settings(flash_mode)] || $settings(flash_mode) ni {off on auto}} {
            set settings(flash_mode) off
            if {[info exists settings(flash_enabled)] \
                    && [string is true -strict $settings(flash_enabled)]} {
                set settings(flash_mode) on
            }
        }
        unset -nocomplain settings(flash_enabled)
        # v0.8.3: the shipped capture_size default rose to 1600x1200 for
        # label detail; an install still sitting on the old 1280x960
        # default is lifted once. Any other explicit choice is kept.
        if {$settings(capture_size) eq "1280x960"} {
            set settings(capture_size) 1600x1200
        }
    }

    proc _setting {key default} {
        variable settings
        if {[info exists settings($key)] && $settings($key) ne ""} {
            return $settings($key)
        }
        return $default
    }

    proc _setting_int {key default} {
        set v [_setting $key $default]
        if {![string is integer -strict $v]} { return $default }
        return $v
    }

    proc _is_true {key} {
        variable settings
        if {![info exists settings($key)]} { return 0 }
        return [string is true -strict $settings($key)]
    }

    # API key: the settings entry wins; otherwise a plain text file next to
    # the plugin (api_key_anthropic.txt / api_key_openai.txt) so a long key
    # can be pushed to the tablet instead of typed on the Android keyboard.
    proc api_key {} {
        variable plugin_dir
        set provider [_setting provider anthropic]
        set k [string trim [_setting api_key_$provider ""]]
        if {$k ne ""} { return $k }
        set f [file join $plugin_dir "api_key_$provider.txt"]
        if {[file exists $f]} {
            if {[catch {
                set fd [open $f r]
                set k [string trim [read $fd]]
                close $fd
            } err]} {
                catch { msg "BeanScanner: ERROR reading $f: $err" }
                return ""
            }
        }
        return $k
    }

    proc api_key_source {} {
        variable plugin_dir
        set provider [_setting provider anthropic]
        if {[string trim [_setting api_key_$provider ""]] ne ""} { return "settings" }
        if {[file exists [file join $plugin_dir "api_key_$provider.txt"]]} { return "file" }
        return "missing"
    }

    proc model_id {} {
        set provider [_setting provider anthropic]
        if {$provider eq "openai"} { return [_setting model_openai gpt-4o] }
        return [_setting model_anthropic claude-opus-5]
    }

    # ==================================================================
    #  Layout tokens
    #
    #  Coordinates are VIRTUAL (2560x1600 fixed constants -- the dui
    #  framework rescales them). Fonts are PHYSICAL pixels derived from the
    #  detected screen, because Tk font objects bypass the coordinate
    #  rescale. Mixing the two sources is the classic half-size-UI bug.
    #
    #  vpx converts a physical pixel count into virtual units, which is
    #  needed for the camera preview: a Tk photo image renders at its own
    #  pixel size, not at a rescaled canvas size.
    # ==================================================================

    # ------------------------------------------------------------------
    #  Theme palette (v0.5.0). Three modes via settings(theme):
    #  "" (default) = the pre-v0.5.0 behavior -- stock light look, with
    #  the active skin's palette adopted when it publishes one;
    #  "light" / "dark" = the explicit palettes, overriding adoption.
    #  The sun-moon toggle on the settings page flips light<->dark based
    #  on the EFFECTIVE darkness (page_bg luminance), so it also works
    #  when the starting point is an adopted skin palette.
    # ------------------------------------------------------------------

    proc _apply_palette {} {
        variable L
        variable settings
        set theme ""
        catch { set theme $settings(theme) }
        # DEFAULTS: the stock light settings-page look, used on every skin.
        set L(sec_fill) "#FFFFFF"
        set L(sec_outline) "#dcdcdc"
        set L(page_bg)  "#d5d6e3"   ;# matches the stock settings-page grey
        set L(fg_title) "#2b2b2b"
        set L(fg_body)  "#2b2b2b"
        set L(fg_muted) "#666666"
        set L(fg_warn)  "#a33a00"   ;# "will be cleared" on the review page
        set L(on_card_title) "#2b2b2b"   ;# on a white section card
        set L(on_card_label) "#444444"
        set L(on_card_value) "#4e85f4"
        set L(entry_bg) "#fbfaff"
        set L(btn_fill) "#c0c5e3"        ;# matches the stock dbutton default
        set L(btn_disabled_fill) "#dddddd"
        set L(btn_label_fill) "#2b2b2b"
        if {$theme eq "dark"} {
            set L(sec_fill) "#32353f"
            set L(sec_outline) "#464b58"
            set L(page_bg)  "#23252e"
            set L(fg_title) "#e8e9ee"
            set L(fg_body)  "#d0d3db"
            set L(fg_muted) "#8d92a0"
            set L(fg_warn)  "#ff9e6b"
            set L(on_card_title) "#e8e9ee"
            set L(on_card_label) "#c2c5cf"
            set L(on_card_value) "#8ab4ff"
            set L(entry_bg) "#3a3e4a"
            set L(btn_fill) "#4a5473"
            set L(btn_disabled_fill) "#3a3e4a"
            set L(btn_label_fill) "#e8e9ee"
        } elseif {$theme ne "light"} {
            # No explicit choice yet: follow the active skin's palette
            # when it publishes one (the pre-v0.5.0 behavior).
            _adopt_skin_palette
        }
    }

    # Perceived luminance below mid-grey = dark. Guards return 0 (light)
    # on anything that is not a plain #rrggbb.
    proc _is_dark_color {c} {
        if {![regexp {^#([0-9a-fA-F]{2})([0-9a-fA-F]{2})([0-9a-fA-F]{2})$} $c -> r g b]} {
            return 0
        }
        scan $r %x r
        scan $g %x g
        scan $b %x b
        return [expr {(0.299 * $r + 0.587 * $g + 0.114 * $b) < 128}]
    }

    proc _effective_dark {} {
        variable L
        if {![info exists L(page_bg)]} { return 0 }
        return [_is_dark_color $L(page_bg)]
    }

    proc _glyph_for {name} {
        set glyph ""
        catch {
            if {[dui symbol exists $name]} { set glyph [dui symbol get $name] }
        }
        return $glyph
    }

    # Moon when the effective look is light (tap for dark), sun-bright
    # when dark; text fallback when the icon font is unavailable.
    proc _theme_button_face {} {
        variable L
        set dark [_effective_dark]
        if {[info exists L(have_icons)] && $L(have_icons)} {
            set g [_glyph_for [expr {$dark ? "sun-bright" : "moon"}]]
            if {$g ne ""} { return $g }
        }
        return [expr {$dark ? [translate "Light"] : [translate "Dark"]}]
    }

    proc toggle_theme {} {
        variable settings
        set settings(theme) [expr {[_effective_dark] ? "light" : "dark"}]
        save_settings
        _apply_palette
        _retheme_all
        catch { ::dui::pages::BeanScanner_settings::refresh BeanScanner_settings }
        catch { dui item config BeanScanner_settings btn_theme -label [_theme_button_face] }
        catch { msg "BeanScanner: theme switched to $settings(theme)" }
    }

    # Repaint every palette-coloured item by bare tag; every call is
    # guarded so a missing item can never break the walk. Buttons are
    # restyled through their -btn shape tags (every segment of a round
    # dbutton carries the tag with -fill AND -outline) and their -lbl
    # label tags (this plugin's button labels are dark-on-light, so
    # they must follow the theme too).
    proc _retheme_all {} {
        variable L
        # BeanScanner_capture is absent on purpose (v0.8.0): it is a
        # camera screen with fixed dark chrome in both themes.
        foreach p {BeanScanner_settings BeanScanner_apikey
                   BeanScanner_review BeanScanner_diagnostics BeanScanner_help} {
            catch { dui item config $p page_bg -fill $L(page_bg) -outline $L(page_bg) }
            catch { dui item config $p page_title -fill $L(fg_title) }
            catch { dui item config $p subtitle -fill $L(fg_muted) }
        }
        # Settings page: section cards + label/value rows.
        foreach sec {sec_scan sec_apply sec_ai sec_cam} {
            catch { dui item config BeanScanner_settings ${sec}_bg \
                -fill $L(sec_fill) -outline $L(sec_outline) }
            catch { dui item config BeanScanner_settings ${sec}_title -fill $L(on_card_title) }
        }
        foreach k {notes overwrite provider model apikey camera capsize} {
            catch { dui item config BeanScanner_settings ${k}_label -fill $L(on_card_label) }
            catch { dui item config BeanScanner_settings ${k}_value -fill $L(on_card_value) }
        }
        # API key page.
        catch { dui item config BeanScanner_apikey provider_label -fill $L(fg_body) }
        catch { dui item config BeanScanner_apikey key_help -fill $L(fg_muted) }
        catch { dui item config BeanScanner_apikey key_entry \
            -bg $L(entry_bg) -foreground $L(on_card_value) }
        # Review / diagnostics / help texts.
        foreach t {roaster_value_label bean_value_label date_value_label level_value_label notes_label} {
            catch { dui item config BeanScanner_review $t -fill $L(fg_muted) }
        }
        foreach t {roaster_value bean_value date_value level_value} {
            catch { dui item config BeanScanner_review $t -fill $L(fg_title) }
        }
        catch { dui item config BeanScanner_review notes_value -fill $L(fg_body) }
        catch { dui item config BeanScanner_diagnostics diag_text -fill $L(fg_body) }
        catch { dui item config BeanScanner_help help_text -fill $L(fg_body) }
        # Buttons: shape + label, both theme-dependent here.
        foreach {p tags} {
            BeanScanner_settings {scan_bean_bag use_latest_photo last_result
                                  notes_btn overwrite_btn provider_btn apikey_btn
                                  camera_btn capsize_btn page_done page_diag
                                  page_help btn_theme}
            BeanScanner_apikey {page_done page_clear}
            BeanScanner_review {accept_btn rescan_btn page_done}
            BeanScanner_diagnostics {page_done probe_btn}
            BeanScanner_help {page_done}
        } {
            foreach t $tags {
                catch { dui item config $p ${t}-btn \
                    -fill $L(btn_fill) -outline $L(btn_fill) \
                    -disabledfill $L(btn_disabled_fill) -disabledoutline $L(btn_disabled_fill) }
                catch { dui item config $p ${t}-lbl -fill $L(btn_label_fill) }
            }
        }
    }

    proc _init_layout {} {
        variable L
        array unset L
        array set L {}

        set sw 2560
        set sh 1600
        set scale [expr {double($sh) / 800.0}]

        set psw 1340
        set psh 800
        catch { set psw [winfo screenwidth .] }
        catch { set psh [winfo screenheight .] }
        if {$psw <= 1} { set psw 1340 }
        if {$psh <= 1} { set psh 800 }
        set font_scale [expr {double($psh) / 800.0}]

        set L(screen_w) $sw
        set L(screen_h) $sh
        set L(phys_w) $psw
        set L(phys_h) $psh
        set L(scale) $scale
        set L(font_scale) $font_scale
        # Virtual units per physical pixel (for sizing photo images).
        set L(vpx_x) [expr {double($sw) / double($psw)}]
        set L(vpx_y) [expr {double($sh) / double($psh)}]

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

        # Section cards (stock App-tab pattern: white rounded blocks on grey).
        set L(sec_top) [expr {int(round(104 * $scale))}]
        set L(sec_gutter) $L(lg)
        set L(sec_col_w) [expr {($L(content_w) - $L(sec_gutter)) / 2}]
        set L(sec_col2_x) [expr {$L(left_x) + $L(sec_col_w) + $L(sec_gutter)}]
        set L(sec_pad) $L(lg)
        set L(sec_gap) $L(lg)
        set L(sec_title_h) [expr {int(round(24 * $scale))}]
        # 180, not 220: the label column is subtracted from the value column,
        # and at 220 the value column came to only ~121 physical px -- one
        # pixel-width short of the longest value the UI can produce
        # ("2048x1536" at font_primary), which wrapped onto a second line and
        # collided with the row below. The longest label ("Overwrite
        # existing") still fits comfortably in 180.
        set L(sec_label_w) [expr {int(round(180 * $scale))}]
        set L(sec_value_dx) [expr {$L(sec_pad) + $L(sec_label_w) + $L(lg)}]
        set L(sec_btn_w) [expr {int(round(150 * $scale))}]
        # Colour tokens. Two surfaces exist: the page background and the
        # section cards, and text must be coloured for whichever it sits on
        # -- getting that backwards makes items invisible rather than merely
        # ugly. This plugin paints its own page background (see _page_bg)
        # rather than inheriting the active skin theme's, so the contrast is
        # deterministic on any skin.
        #
        # v0.5.0: every colour lives in _apply_palette (light / dark /
        # follow-the-skin), so the sun-moon toggle can swap it at runtime.
        _apply_palette

        set L(btn_w_std) [expr {int(round(200 * $scale))}]
        set L(btn_w_wide) [expr {int(round(260 * $scale))}]
        set L(btn_h) [expr {int(max(60, round(60 * $scale)))}]
        set L(btn_radius) [expr {int(round(12 * $scale))}]
        set L(sec_radius) $L(btn_radius)

        # v0.8.0: camera-app chrome for the capture page. Deliberately
        # fixed (NOT part of _apply_palette): a camera screen is dark in
        # both themes, so the capture page is excluded from _retheme_all.
        # Tk has no alpha, so the "translucent" circles are solid dark.
        set L(cam_bg)        "#000000"
        set L(cam_circle)    "#26262b"   ;# floating control circles / pills
        set L(cam_icon)      "#ffffff"
        set L(cam_icon_dim)  "#6f7278"   ;# flash glyph when no flash exists
        set L(cam_flash_on)  "#ffd60a"   ;# yellow bolt (on / auto)
        set L(cam_send_fill) "#f2f2f4"
        set L(cam_send_text) "#17181c"
        set L(cam_margin)    60          ;# edge inset for floating controls
        set L(cam_circle_d)  128         ;# small circles (cancel/flash/clear)
        set L(cam_flip_d)    152         ;# camera-flip circle
        set L(cam_ring_d)    180         ;# shutter ring outer diameter
        set L(cam_shutter_d) 132         ;# shutter button (white disc)
        set L(cam_row_cy)    1400        ;# bottom control row centre line
        set L(cam_pill_w)    1000        ;# status pill width, centred
        set L(cam_pill_h)    72          ;# status pill height (slim, per mock)
        set L(cam_send_w)    360
        set L(cam_badge_d)   88          ;# count badge inside the Send pill

        set L(header_title_y) [expr {int(round(28 * $scale))}]
        set L(header_subtitle_y) [expr {int(round(72 * $scale))}]
        set L(toolbar_y0) [expr {int(round(104 * $scale))}]
        set L(list_top) [expr {int(round(168 * $scale))}]
        set L(row_h) $L(btn_h)
        set L(row_gap) $L(md)
        set L(row_pitch) [expr {$L(row_h) + $L(row_gap)}]
        set L(bar_y0) [expr {int(round(716 * $scale))}]
        set L(bar_y1) [expr {int(round(776 * $scale))}]

        # Fonts: physical pixels (negative Tk size = pixels), 16px floor.
        set L(font_title) Helv_20_bold
        set L(font_section) Helv_18_bold
        set L(font_primary) Helv_10_bold
        set L(font_body) Helv_9
        set L(font_caption) Helv_8
        set L(font_button) Helv_10_bold
        catch {
            foreach {name ref bold} {title 40 1 section 24 1 primary 22 1 body 19 0 caption 16 0 button 20 1} {
                set px [expr {int(max(16, round($ref * $font_scale)))}]
                set fname "BSC_$name"
                set weight [expr {$bold ? "bold" : "normal"}]
                if {[lsearch -exact [font names] $fname] >= 0} {
                    font configure $fname -size [expr {-$px}] -weight $weight
                } else {
                    font create $fname -family Helvetica -size [expr {-$px}] -weight $weight
                }
                set L(font_$name) $fname
            }
        }

        # v0.5.0: icon font for the theme toggle's sun/moon face (the
        # app's own FA6 Pro file, dui's loader). Text fallback when
        # unavailable -- have_icons stays 0.
        set L(have_icons) 0
        set L(font_icon) $L(font_button)
        catch {
            set fam [dui::font::add_or_get_familyname "Font Awesome 6 Pro-Regular-400.otf"]
            if {$fam ne ""} {
                set px [expr {int(max(16, round(26 * $font_scale)))}]
                if {[lsearch -exact [font names] BSC_icon] >= 0} {
                    font configure BSC_icon -family $fam -size [expr {-$px}]
                } else {
                    font create BSC_icon -family $fam -size [expr {-$px}]
                }
                set L(font_icon) BSC_icon
                set L(have_icons) 1
                # Smaller icon size for inline accents (the Send plane).
                set px [expr {int(max(14, round(20 * $font_scale)))}]
                if {[lsearch -exact [font names] BSC_icon_sm] >= 0} {
                    font configure BSC_icon_sm -family $fam -size [expr {-$px}]
                } else {
                    font create BSC_icon_sm -family $fam -size [expr {-$px}]
                }
                set L(font_icon_sm) BSC_icon_sm
            }
        }
        if {![info exists L(font_icon_sm)]} { set L(font_icon_sm) $L(font_caption) }

        # One shared button style. Label fonts are passed per instance via
        # -label_font; the aspect font_size key is not honored on the tablet.
        #
        # -theme default is REQUIRED here and is the whole bugfix behind
        # v0.1.2. "dui aspect set" writes into the *current* theme, which by
        # the time this plugin's preload runs is the skin's theme (DSx2), but
        # the pages below are created with "-theme default". Aspect lookup
        # falls back from a named theme toward "default", never the other
        # way, so a style registered under DSx2 is simply not found when a
        # default-theme page renders: shape resolved empty (no button
        # background drawn at all) and the label fell back to the theme
        # default white, invisible on the white section cards.
        # Tablet-confirmed: the diagnostic build logged "theme=DSx2".
        catch {
            dui aspect set -theme default -type dbutton -style bsc_btn [list \
                shape round radius $L(btn_radius) \
                fill $L(btn_fill) disabledfill $L(btn_disabled_fill)]
            dui aspect set -theme default -type dbutton_label -style bsc_btn [list \
                fill $L(btn_label_fill) disabledfill "#999999"]
        }
    }

    # Full-page background, drawn as the first item of every page so the
    # plugin's contrast never depends on which skin theme happens to be
    # active (the fpdialog pages inherit a dark background under DSx2, which
    # made dark-on-light text unreadable).
    proc _page_bg {page} {
        variable L
        dui add canvas_item rect $page 0 0 $L(screen_w) $L(screen_h) \
            -fill $L(page_bg) -outline $L(page_bg) -tags page_bg
    }

    # Rounded-rectangle backdrop (no rounded-rect primitive exists in core).
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

    # White section card with a title. Returns the y of the first content row.
    #   h = 2*sec_pad + sec_title_h + md + <content height>
    proc _sec_card {page tag x y w h title} {
        variable L
        rounded_rect $page $x $y [expr {$x + $w}] [expr {$y + $h}] $L(sec_radius) \
            -fill $L(sec_fill) -outline $L(sec_outline) -width 2 -tags ${tag}_bg
        dui add dtext $page [expr {$x + $L(sec_pad)}] [expr {$y + $L(sec_pad) + $L(sec_title_h) / 2}] \
            -tags ${tag}_title -text [translate $title] -font $L(font_section) \
            -width [expr {$w - 2 * $L(sec_pad)}] -fill $L(on_card_title) -anchor w -justify left
        return [expr {$y + $L(sec_pad) + $L(sec_title_h) + $L(md)}]
    }

    proc preload_settings_page {} {
        package require de1_dui 1.0
        catch { plugins load_settings BeanScanner }
        apply_defaults
        catch { plugins save_settings BeanScanner }
        _init_layout
        foreach p {BeanScanner_settings BeanScanner_apikey BeanScanner_capture \
                   BeanScanner_review BeanScanner_diagnostics BeanScanner_help} {
            dui page add $p -namespace true -theme default -type fpdialog
        }
        return BeanScanner_settings
    }

    proc open_page {page} {
        foreach cmd [list \
            [list dui page open_dialog $page] \
            [list dui page load $page] \
            [list dui page show $page]] {
            if {![catch { uplevel #0 $cmd }]} { return 1 }
        }
        catch { msg "BeanScanner: could not open page $page" }
        return 0
    }

    # ==================================================================
    #  Navigation (the app's own mechanism; no custom bookkeeping)
    # ==================================================================

    proc _is_transient_name {name} {
        if {$name eq ""} { return 1 }
        return [regexp -nocase {espresso|steam|water|rinse|flush|clean|cleaning|descale|purge} $name]
    }

    # page_to_hide is the real previous page per dui::page::load. Skip
    # transient machine-state pages (a flush/rinse interruption re-shows this
    # page and would otherwise clobber the real target) and skip this
    # plugin's own pages (returning from a sub-page would otherwise make Done
    # ping-pong back into it).
    proc _capture_return_page {page_to_hide} {
        variable _settings_return_page
        if {$page_to_hide eq ""} { return }
        if {[string match "BeanScanner_*" $page_to_hide]} { return }
        if {![_is_transient_name $page_to_hide]} {
            set _settings_return_page $page_to_hide
        }
    }

    # Adopts the active skin's palette when that skin publishes one, so the
    # plugin stops looking like a stock settings page pasted into a themed
    # skin. Everything is guarded and falls back to the defaults already set
    # by the caller, so an absent or partial palette changes nothing.
    #
    # Only ::lumen is recognised today; the shape is a plain colour array, so
    # any other skin can opt in by exposing the same keys.
    proc _adopt_skin_palette {} {
        variable L
        if { ![info exists ::lumen::C(bg)] } { return }

        # Maps skin token -> our token. Text tokens must come from the skin's
        # "on dark/light panel" inks, not its page inks, because our body
        # text sits on the section cards rather than the page.
        foreach { ours theirs } {
            page_bg        bg
            sec_fill       glass
            sec_outline    glass_brd
            fg_title       ink
            fg_body        ink
            fg_muted       ink_3
            fg_warn        warn
            on_card_title  ink
            on_card_label  ink_3
            on_card_value  crema
            btn_fill       glass_2
            btn_label_fill ink
        } {
            if { [info exists ::lumen::C($theirs)] } {
                set v [set ::lumen::C($theirs)]
                if { [string match "#*" $v] } { set L($ours) $v }
            }
        }
        # No direct equivalent: a disabled button should read as the card
        # surface, one step back from the live button fill.
        if { [info exists ::lumen::C(glass)] } {
            set L(btn_disabled_fill) $::lumen::C(glass)
        }
        catch { msg -INFO "BeanScanner: adopted the Lumen palette" }
    }

    # Records the page a sub-page should return to. Callers that jump
    # straight to a sub-page (a skin putting "Scan bag" on its home screen,
    # for example) set this so Cancel goes back where the user came from
    # instead of stranding them on the settings page.
    proc set_return_page {page} {
        variable _settings_return_page
        variable _entered_at_subpage
        if {$page eq "" || [_is_transient_name $page]} { return 0 }
        if {[string match "BeanScanner_*" $page]} { return 0 }
        set _settings_return_page $page
        set _entered_at_subpage 1
        return 1
    }

    proc _navigate_done {target} {
        set ok 0
        if {$target ne "" && ![_is_transient_name $target]} {
            catch { set ok [dui page exists $target] }
        }
        if {$ok} {
            if {[catch { uplevel #0 [list dui page load $target] } err]} {
                catch { msg "BeanScanner: ERROR navigating to $target: $err" }
                catch { dui page close_dialog }
            }
        } else {
            catch { dui page close_dialog }
        }
    }

    proc _exit_settings {} {
        variable _settings_return_page
        variable _entered_at_subpage
        set _entered_at_subpage 0
        _navigate_done $_settings_return_page
    }

    # Sub-pages normally hand back to the settings page, because that is how
    # they are reached. But when the plugin was entered directly AT a
    # sub-page, the settings page was never shown and returning to it strands
    # the user one extra tap from where they started -- so go straight home.
    proc _exit_subpage {} {
        variable _settings_return_page
        variable _entered_at_subpage
        if {$_entered_at_subpage && $_settings_return_page ne ""} {
            set _entered_at_subpage 0
            _navigate_done $_settings_return_page
            return
        }
        _navigate_done BeanScanner_settings
    }

    # ==================================================================
    #  Camera (AndroWish borg camera; see AndroWish "Android facilities")
    # ==================================================================

    proc camera_probe {} {
        variable cam
        set lines [list]
        set n -1
        if {[catch { set n [borg camera numcameras] } err]} {
            lappend lines "numcameras: FAILED ($err)"
        } else {
            lappend lines "numcameras: $n"
        }
        set state "?"
        catch { set state [borg camera state] }
        lappend lines "state: $state"
        set perms_camera "unknown"
        if {[catch {
            set all [borg checkpermission]
            if {[lsearch -exact $all android.permission.CAMERA] >= 0} {
                set granted [borg checkpermission android.permission.CAMERA]
                set perms_camera "declared, granted=$granted"
            } else {
                set perms_camera "NOT DECLARED in the app manifest"
            }
        } err]} {
            set perms_camera "check failed ($err)"
        }
        lappend lines "android.permission.CAMERA: $perms_camera"
        set cam(probe) [join $lines "\n"]
        return $cam(probe)
    }

    # front / back / auto -> camera index. borg camera info reports the
    # facing of the currently opened camera, so with "auto" (or when the
    # preference cannot be honored) we simply use camera 0.
    proc _pick_camera {} {
        set pref [_setting camera_pref front]
        set n 1
        catch { set n [borg camera numcameras] }
        if {![string is integer -strict $n] || $n < 1} { set n 1 }
        if {$pref eq "back"} { return 0 }
        if {$pref eq "front"} {
            # Android convention: 0 = back, 1 = front on multi-camera devices.
            if {$n > 1} { return 1 }
            return 0
        }
        return 0
    }

    proc _ensure_photo {} {
        variable cam
        if {$cam(photo) ne "" && [lsearch -exact [image names] $cam(photo)] >= 0} {
            return $cam(photo)
        }
        set cam(photo) ""
        catch { set cam(photo) [image create photo BeanScanner_preview] }
        return $cam(photo)
    }

    # The photo shown on the canvas: the raw preview photo, or -- when
    # the preview is display-zoomed -- a second photo that _preview_tick
    # fills with an integer-zoomed copy of each frame.
    proc _display_photo {} {
        variable cam
        if {$cam(zoom) eq "1 1"} { return [_ensure_photo] }
        if {$cam(photo_disp) ne "" && [lsearch -exact [image names] $cam(photo_disp)] >= 0} {
            return $cam(photo_disp)
        }
        set cam(photo_disp) ""
        catch { set cam(photo_disp) [image create photo BeanScanner_preview_disp] }
        if {$cam(photo_disp) eq ""} { return [_ensure_photo] }
        return $cam(photo_disp)
    }

    proc camera_open {} {
        variable cam
        if {$cam(open)} { return 1 }
        set idx [_pick_camera]
        set ok 0
        if {[catch { set ok [borg camera open $idx] } err]} {
            set_error "Camera open failed: $err"
            return 0
        }
        if {!$ok} {
            set_error "Camera $idx could not be opened. Check that the app has the CAMERA permission (see Diagnostics)."
            return 0
        }
        set cam(open) 1
        set cam(index) $idx

        # One read of the camera's Camera.Parameters ("borg camera
        # parameters" with no arguments returns them as a key-value list)
        # feeds both the flash detection and the preview-size choice.
        array set __cp {}
        catch { array set __cp [borg camera parameters] }

        # Hardware flash detection, per camera: flash-capable cameras
        # report flash-mode-values (comma separated, e.g.
        # "off,auto,on,torch"). Front cameras normally have none -- there
        # the flash setting means screen flash instead.
        set cam(flash_hw) ""
        set cam(flash_modes) {}
        if {[info exists __cp(flash-mode-values)]} {
            set cam(flash_modes) [split $__cp(flash-mode-values) ","]
        }
        foreach __m {torch on} {
            if {[lsearch -exact $cam(flash_modes) $__m] >= 0} {
                set cam(flash_hw) $__m
                break
            }
        }
        catch { msg "BeanScanner: camera $idx flash modes {$cam(flash_modes)} using [expr {$cam(flash_hw) eq {} ? {screen flash} : $cam(flash_hw)}]" }

        # Preview and capture resolution, set BEFORE the preview starts.
        # v0.8.0: the preview fills the screen, so pick the largest size
        # the camera offers that fits the physical display. Camera1's
        # flattened key for the supported list is preview-size-values
        # (v0.8.1 fix -- v0.8.0 read "preview-sizes", which does not
        # exist, so the preview silently stayed at the 640x480 fallback).
        # Device-specific failures are logged, not fatal -- the camera
        # keeps its own defaults.
        set __psizes ""
        foreach __k {preview-size-values preview-sizes} {
            if {[info exists __cp($__k)]} {
                set __psizes $__cp($__k)
                break
            }
        }
        set psize [_pick_preview_size $__psizes]
        catch { msg "BeanScanner: camera $idx preview sizes {$__psizes} -> $psize" }
        set __csizes ""
        foreach __k {picture-size-values picture-sizes} {
            if {[info exists __cp($__k)]} {
                set __csizes $__cp($__k)
                break
            }
        }
        set csize [_pick_picture_size $__csizes]
        catch { msg "BeanScanner: camera $idx capture sizes {$__csizes} -> $csize (wanted [_setting capture_size 1600x1200])" }
        if {[catch { borg camera parameters preview-size $psize } err]} {
            catch { msg "BeanScanner: preview-size $psize rejected: $err" }
        }
        if {[catch { borg camera parameters picture-size $csize } err]} {
            catch { msg "BeanScanner: picture-size $csize rejected: $err" }
        }
        # v0.9.11: NO 3A parameter writes at all. Ten rounds of the
        # back-camera freeze saga (fps pin, focus modes, scene, anti-
        # banding, stabilization, AF boxes -- each dump-verified applied,
        # none curative, some suspect) taught the workspace lesson the
        # hard way: converge on the proven mechanism. The proven state
        # is v0.9.0's -- the camera's factory automatics untouched; the
        # plugin sets only what the user actually controls (sizes,
        # flash) below.

        # What the camera ACTUALLY accepted is authoritative -- a
        # rejected size silently keeps the camera's own default, and the
        # display maths below must work from the real frame size.
        catch {
            array set __cp2 [borg camera parameters]
            if {[info exists __cp2(preview-size)]} { set psize $__cp2(preview-size) }
        }
        catch { msg "BeanScanner: camera $idx actual preview-size $psize" }

        # Display scale, v0.8.3: 1:1 whenever the preview covers or
        # nearly fills the screen (a covering preview is centre-cropped
        # by the screen edges -- sharp and borderless). Integer x2 zoom
        # ONLY for genuinely small previews (no covering size reported):
        # zoom replicates every source pixel, so nothing is thrown away.
        # Fractional zoom/subsample is banned -- subsample discards
        # pixels first, which is what pixelated v0.8.2.
        variable L
        set cam(zoom) {1 1}
        if {[regexp {^(\d+)x(\d+)$} $psize -> __pw __ph]} {
            set __sw 1340
            if {[info exists L(phys_w)]} { set __sw $L(phys_w) }
            if {$__pw * 4 <= $__sw * 3} { set cam(zoom) {2 1} }
        }
        catch { msg "BeanScanner: display scale [join $cam(zoom) /] for $psize" }

        if {[catch { borg camera start } err]} {
            set_error "Camera start failed: $err"
            camera_close
            return 0
        }
        set cam(started) 1
        _flash_apply
        return 1
    }

    # Preview size choice, v0.8.3: Tk photos can only scale by integer
    # factors (fractional zoom/subsample DESTROYS resolution -- it drops
    # pixels before replicating them, which is what pixelated v0.8.2).
    # So the preview is shown at 1:1 and full-bleed comes from the
    # camera itself: prefer the SMALLEST reported size that covers the
    # screen (shown centre-cropped, sharp, borderless), else the largest
    # that fits, else the setting.
    proc _pick_preview_size {sizes_csv} {
        variable L
        set fallback [_setting preview_size 640x480]
        set sw 1340
        set sh 800
        if {[info exists L(phys_w)]} { set sw $L(phys_w) }
        if {[info exists L(phys_h)]} { set sh $L(phys_h) }
        set best_cover ""
        set best_cover_area -1
        set best_cover_aligned 0
        set best_fit $fallback
        set best_fit_area 0
        foreach s [split $sizes_csv ","] {
            set s [string trim $s]
            if {![regexp {^(\d+)x(\d+)$} $s -> w h]} { continue }
            set area [expr {$w * $h}]
            # v0.9.5: prefer hardware-aligned modes (both dimensions
            # divisible by 8). The Tab A9 back camera's screen-exact
            # 1340x800 mode (1340 is not) hiccuped ~1x/second on-device
            # while the front's aligned 1600x960 ran smoothly -- exotic
            # sizes go through slower HAL scaler paths.
            set aligned [expr {($w % 8) == 0 && ($h % 8) == 0}]
            if {$w >= $sw && $h >= $sh} {
                if {($aligned && !$best_cover_aligned) \
                        || ($aligned == $best_cover_aligned \
                            && ($best_cover_area < 0 || $area < $best_cover_area))} {
                    set best_cover $s
                    set best_cover_area $area
                    set best_cover_aligned $aligned
                }
            } elseif {$w <= $sw && $h <= $sh && $area > $best_fit_area} {
                set best_fit $s
                set best_fit_area $area
            }
        }
        if {$best_cover ne ""} { return $best_cover }
        return $best_fit
    }

    # Capture (JPEG) size: the smallest reported picture size that is at
    # least the requested capture_size, so "high res" in Settings really
    # captures at that detail; when the camera cannot reach it, its
    # largest size is used. Absent list -> the setting as-is.
    proc _pick_picture_size {sizes_csv} {
        set want [_setting capture_size 1600x1200]
        if {![regexp {^(\d+)x(\d+)$} $want -> ww wh]} { return $want }
        set want_area [expr {$ww * $wh}]
        set best ""
        set best_area -1
        set biggest ""
        set biggest_area 0
        foreach s [split $sizes_csv ","] {
            set s [string trim $s]
            if {![regexp {^(\d+)x(\d+)$} $s -> w h]} { continue }
            set area [expr {$w * $h}]
            if {$area > $biggest_area} {
                set biggest $s
                set biggest_area $area
            }
            if {$area >= $want_area && ($best_area < 0 || $area < $best_area)} {
                set best $s
                set best_area $area
            }
        }
        if {$best ne ""} { return $best }
        if {$biggest ne ""} { return $biggest }
        return $want
    }

    proc _is_front_camera {} {
        return [expr {[_setting camera_pref front] eq "front"}]
    }

    # (v0.9.1's _pick_fps_range pin lived here; removed in v0.9.9 -- the
    # fixed floor correlated with the light-in-frame stall on both
    # cameras, and the HAL's own variable range handles dim scenes.)

    # (The freeze-saga camera_debug.txt dump and on-screen frame stats
    # lived here through v0.9.6-v0.9.11; removed once the diagnosis
    # closed. Verdict: the preview stalls when a bright PWM light
    # source dominates the frame, on BOTH cameras, on a completely
    # clean camera configuration -- a device/HAL behavior below what
    # Camera1 parameters or AndroWish can reach. It does not occur in
    # normal scanning conditions, and captures are unaffected.)

    proc camera_close {} {
        variable cam
        preview_stop
        if {$cam(flash_after) ne ""} {
            catch { after cancel $cam(flash_after) }
            set cam(flash_after) ""
        }
        _screen_flash_end
        if {$cam(started)} { _flash_hw_set off }
        if {$cam(started)} { catch { borg camera stop } }
        if {$cam(open)}    { catch { borg camera close } }
        set cam(started) 0
        set cam(open) 0
        set cam(index) -1
        # flash_hw / flash_modes are deliberately kept: they describe the
        # last-opened camera for the Diagnostics page, and every user of
        # them also checks cam(open)/cam(started).
    }

    # ==================================================================
    #  Flash: hardware torch on cameras that have one, screen flash
    #  (white overlay + full brightness) on those that do not.
    # ==================================================================

    # Low-level: set the Camera1 flash-mode on the running camera.
    # Rejections are logged, never fatal.
    proc _flash_hw_set {mode} {
        variable cam
        if {!$cam(open) || $cam(flash_hw) eq ""} { return }
        if {[catch { borg camera parameters flash-mode $mode } err]} {
            catch { msg "BeanScanner: flash-mode $mode rejected: $err" }
        }
    }

    # Applies the flash_mode setting (off/on/auto) to the running camera.
    # "on" uses torch when available -- it lights the preview too, so what
    # you see is what gets captured; "auto" lets the camera decide at
    # capture time. Cameras without hardware flash are handled at capture
    # (screen flash, front camera only), so nothing to do here.
    proc _flash_apply {} {
        variable cam
        if {$cam(flash_hw) eq ""} { return }
        switch -- [_setting flash_mode off] {
            on      { _flash_hw_set $cam(flash_hw) }
            auto    { _flash_hw_set auto }
            default { _flash_hw_set off }
        }
    }

    # The states the flash button can cycle through on the current camera:
    # front camera has no light meter for its screen flash, so no "auto";
    # a back camera without hardware flash has no flash at all (the screen
    # faces away from the subject there, so screen flash is pointless).
    proc _flash_states {} {
        variable cam
        if {[_is_front_camera]} { return {off on} }
        if {$cam(flash_hw) eq ""} { return {} }
        if {[lsearch -exact $cam(flash_modes) auto] >= 0} { return {off on auto} }
        return {off on}
    }

    proc flash_cycle {} {
        variable settings
        set states [_flash_states]
        if {[llength $states] == 0} {
            catch { borg toast [translate "This camera has no flash."] }
            return
        }
        set i [lsearch -exact $states [_setting flash_mode off]]
        set settings(flash_mode) [lindex $states [expr {($i + 1) % [llength $states]}]]
        save_settings
        _flash_apply
        _update_capture_ui
    }

    # Glyph from the app's icon font, or a plain-text stand-in when the
    # font is unavailable (then EVERY face is text, so the button's
    # creation font always matches).
    proc _glyph_or {name fallback} {
        variable L
        if {[info exists L(have_icons)] && $L(have_icons)} {
            set g [_glyph_for $name]
            if {$g ne ""} { return $g }
        }
        return [translate $fallback]
    }

    # Flash button face: {label colour}. White slashed bolt = off, yellow
    # bolt = on, yellow bolt-A = auto, dimmed = this camera has no flash.
    proc _flash_button_face {} {
        variable L
        if {[llength [_flash_states]] == 0} {
            return [list [_glyph_or bolt-slash "no fl"] $L(cam_icon_dim)]
        }
        switch -- [_setting flash_mode off] {
            on   { return [list [_glyph_or bolt "fl on"] $L(cam_flash_on)] }
            auto { return [list [_glyph_or bolt-auto "fl A"] $L(cam_flash_on)] }
        }
        return [list [_glyph_or bolt-slash "fl off"] $L(cam_icon)]
    }

    # Flip front <-> back from the capture page. The pending photos are
    # kept -- they show the same bag, whichever camera took them -- and
    # camera_open re-detects the new camera's flash hardware, so an
    # enabled flash switches between torch and screen flash by itself.
    proc camera_flip {} {
        variable settings
        variable scan
        if {$scan(busy)} {
            set_stage sending [translate "Already working -- please wait."]
            return
        }
        if {[_setting camera_pref front] eq "front"} {
            set settings(camera_pref) back
        } else {
            set settings(camera_pref) front
        }
        save_settings
        restart_camera
    }

    # (Re)start the camera for the capture page: used by the page's show{}
    # and by camera_flip. camera_close first is safe when nothing is open,
    # and cancels a pending screen-flash timer if a flip lands mid-flash.
    proc restart_camera {} {
        variable photos
        variable cam
        camera_close
        # Fresh preview photos for every (re)start: reusing one Tk photo
        # across cameras let a smaller new preview SHRINK it in place,
        # and the canvas never repainted the vacated area -- the old
        # camera's last frame stayed on screen as garbage (seen on the
        # first on-device flip of v0.8.3). A brand-new photo only ever
        # grows, and re-configuring the item repaints the old extent.
        if {$cam(photo) ne ""} { catch { image delete $cam(photo) } }
        if {$cam(photo_disp) ne ""} { catch { image delete $cam(photo_disp) } }
        set cam(photo) ""
        set cam(photo_disp) ""
        set_stage idle [translate "Starting the camera..."]
        set opened [camera_open]
        # After open: flash hardware of THIS camera is known, so the
        # flash face (yellow/white/dimmed) can be brought up to date.
        _update_capture_ui
        if {!$opened} { return }
        set photo [_ensure_photo]
        if {$photo ne ""} {
            catch { dui item config BeanScanner_capture cam_preview -image [_display_photo] }
        }
        preview_start
        set n [llength $photos]
        if {$n > 0} {
            set_stage preview "$n photo[expr {$n == 1 ? {} : {s}}] taken. Capture another side, or tap Send."
        } else {
            set_stage preview [translate "Ready. Tap Capture."]
        }
    }

    # Screen flash: cover the whole page with a white rectangle and push
    # the tablet brightness to maximum via the app's own brightness proc
    # (which also re-hides the system bar). Balanced by _screen_flash_end
    # on every exit path, including errors and page hides.
    proc _screen_flash_begin {} {
        variable cam
        if {$cam(screenflash)} { return }
        set cam(screenflash) 1
        catch { dui item show BeanScanner_capture flash_overlay -initial 1 }
        catch {
            set b [get_set_tablet_brightness]
            if {[string is integer -strict $b]} { set cam(saved_brightness) $b }
            get_set_tablet_brightness 100
        }
    }

    proc _screen_flash_end {} {
        variable cam
        if {!$cam(screenflash)} { return }
        set cam(screenflash) 0
        catch { dui item hide BeanScanner_capture flash_overlay -initial 1 }
        if {$cam(saved_brightness) ne ""} {
            catch { get_set_tablet_brightness $cam(saved_brightness) }
        }
        set cam(saved_brightness) ""
    }

    proc preview_start {} {
        variable cam
        if {$cam(preview)} { return }
        if {[_ensure_photo] eq ""} { return }
        set cam(preview) 1
        _preview_tick
    }

    proc preview_stop {} {
        variable cam
        set cam(preview) 0
        if {$cam(after) ne ""} {
            catch { after cancel $cam(after) }
            set cam(after) ""
        }
    }

    # Plain fixed-rate poll (v0.9.13, reverted to the v0.8.x mechanism
    # the owner preferred): one grab per preview_poll_ms. The v0.9.x
    # frame-driven <<ImageCapture>> path chased the camera's full rate
    # and, at 30-50 ms of main-thread cost per grab on this tablet,
    # made the UI laggy; ~7 fps with a responsive UI feels better.
    proc _preview_tick {} {
        variable cam
        if {!$cam(preview)} { return }
        catch { borg camera image $cam(photo) }
        if {$cam(zoom) ne "1 1" && $cam(photo_disp) ne ""} {
            lassign $cam(zoom) __z __s
            catch { $cam(photo_disp) copy $cam(photo) -zoom $__z $__z -subsample $__s $__s }
        }
        set cam(after) [after [_setting_int preview_poll_ms 150] ::plugins::BeanScanner::_preview_tick]
    }

    # Takes one photo and adds it to the pending set. The camera stays
    # open between shots so several sides of the same bag can be captured;
    # nothing is sent until send_photos.
    proc capture_jpeg {} {
        variable cam
        variable scan
        variable photos
        if {$scan(busy)} {
            set_stage sending [translate "Already working -- please wait."]
            return
        }
        if {!$cam(started)} {
            set_error "Camera is not running."
            return
        }
        set maxp [_setting_int max_photos 6]
        if {[llength $photos] >= $maxp} {
            set_stage preview "All $maxp photo slots are used. Tap Send, or Clear to start over."
            return
        }
        preview_stop
        set_stage capturing "Taking picture [expr {[llength $photos] + 1}]..."
        set delay 0
        if {[_setting flash_mode off] ne "off" && $cam(flash_hw) eq "" \
                && [_is_front_camera]} {
            # Screen flash: FRONT camera only -- the screen faces away
            # from the subject on the back camera, so it never fires
            # there. Light the scene with the screen and give the
            # auto-exposure a moment to adapt.
            _screen_flash_begin
            set delay [_setting_int screen_flash_ms 600]
        }
        if {$delay > 0} {
            # The timer is remembered so a page hide mid-wait cancels it.
            set cam(flash_after) [after $delay ::plugins::BeanScanner::_do_takejpeg]
        } else {
            _do_takejpeg
        }
    }

    proc _do_takejpeg {} {
        variable cam
        set cam(flash_after) ""
        if {!$cam(started)} {
            # The page was hidden (e.g. a flush screen) while waiting.
            _screen_flash_end
            return
        }
        if {[catch { borg camera takejpeg } err]} {
            _screen_flash_end
            set_error "takejpeg failed: $err"
            return
        }
        _poll_jpeg 0
    }

    proc _poll_jpeg {tries} {
        variable cam
        variable photos
        set max [_setting_int capture_retries 24]
        set data ""
        catch { set data [borg camera jpeg] }
        set len [string length $data]
        if {$len > 2000} {
            _screen_flash_end
            set cam(last_bytes) $len
            set limit [_setting_int max_image_bytes 4000000]
            if {$len > $limit} {
                set_error "That photo is [_fmt_bytes $len], over the [_fmt_bytes $limit] limit -- not added. Lower the capture size in Settings."
                _resume_preview
                return
            }
            lappend photos $data
            _resume_preview
            _update_capture_ui
            set n [llength $photos]
            set_stage preview "$n photo[expr {$n == 1 ? {} : {s}}] taken. Capture another side, or tap Send."
            return
        }
        if {$tries >= $max} {
            _screen_flash_end
            set_error "No JPEG returned after [expr {$max * [_setting_int capture_poll_ms 250]}] ms."
            return
        }
        after [_setting_int capture_poll_ms 250] \
            [list ::plugins::BeanScanner::_poll_jpeg [expr {$tries + 1}]]
    }

    # Camera1 halts the preview after a still capture; restarting is
    # harmless when it did not. Errors are logged, never fatal.
    proc _resume_preview {} {
        variable cam
        if {!$cam(open)} { return }
        if {[catch { borg camera start } err]} {
            catch { msg "BeanScanner: preview restart failed: $err" }
        }
        set cam(started) 1
        preview_start
    }

    # Send badge / flash button faces on the capture page. The photo
    # count lives in the dark badge inside the Send pill (mock design),
    # shown only while at least one photo is pending.
    proc _update_capture_ui {} {
        variable photos
        set n [llength $photos]
        if {$n > 0} {
            catch { dui item config BeanScanner_capture send_badge_n -text $n }
            catch { dui item show BeanScanner_capture send_badge -initial 1 }
            catch { dui item show BeanScanner_capture send_badge_n -initial 1 }
        } else {
            catch { dui item hide BeanScanner_capture send_badge -initial 1 }
            catch { dui item hide BeanScanner_capture send_badge_n -initial 1 }
        }
        lassign [_flash_button_face] fl_label fl_fill
        catch { dui item config BeanScanner_capture flash_btn -label $fl_label }
        catch { dui item config BeanScanner_capture flash_btn-lbl -fill $fl_fill }
    }

    proc clear_photos {} {
        variable photos
        set photos [list]
        _update_capture_ui
    }

    # Sends every pending photo as ONE vision request.
    proc send_photos {} {
        variable photos
        variable scan
        if {$scan(busy)} {
            set_stage sending [translate "Already working -- please wait."]
            return
        }
        if {[llength $photos] == 0} {
            set_error "No photos yet -- tap Capture first."
            return
        }
        # The pending set is kept until the response parses, so a network
        # error never costs the photos -- Send can simply be tapped again.
        camera_close
        send_images $photos
    }

    # Fallback path: take the photo with the tablet's own camera app, then
    # use the newest JPEG in the import folder. Deterministic, and it works
    # even if the app has no CAMERA permission.
    proc import_latest {} {
        set dir [_setting import_dir /sdcard/DCIM/Camera]
        if {![file isdirectory $dir]} {
            set_error "Import folder not found: $dir"
            return
        }
        set files [list]
        catch { set files [glob -nocomplain -directory $dir *.jpg *.JPG *.jpeg *.JPEG] }
        if {[llength $files] == 0} {
            set_error "No JPEG files in $dir"
            return
        }
        set newest ""
        set newest_t 0
        foreach f $files {
            set t 0
            catch { set t [file mtime $f] }
            if {$t > $newest_t} { set newest_t $t; set newest $f }
        }
        if {$newest eq ""} {
            set_error "Could not determine the newest photo in $dir"
            return
        }
        set limit [_setting_int max_image_bytes 4000000]
        set sz 0
        catch { set sz [file size $newest] }
        if {$sz > $limit} {
            set_error "[file tail $newest] is [_fmt_bytes $sz], over the [_fmt_bytes $limit] limit."
            return
        }
        if {[catch {
            set fd [open $newest rb]
            fconfigure $fd -translation binary
            set data [read $fd]
            close $fd
        } err]} {
            set_error "Could not read $newest: $err"
            return
        }
        set_stage sending "Using [file tail $newest]..."
        send_image $data
    }

    proc _fmt_bytes {n} {
        if {$n >= 1048576} { return "[format %.1f [expr {$n / 1048576.0}]] MB" }
        if {$n >= 1024}    { return "[expr {$n / 1024}] kB" }
        return "$n B"
    }

    # ==================================================================
    #  Encoding helpers
    # ==================================================================

    proc _b64 {bytes} {
        set out ""
        if {![catch { set out [binary encode base64 $bytes] }]} {
            return [string map {"\n" "" "\r" ""} $out]
        }
        if {[catch {
            package require base64
            set out [::base64::encode -maxlen 0 $bytes]
        } err]} {
            error "base64 encoding unavailable: $err"
        }
        return [string map {"\n" "" "\r" ""} $out]
    }

    # JSON string literal. Everything outside printable ASCII becomes \uXXXX
    # so the request body stays pure ASCII and no charset negotiation is
    # needed on the way out.
    proc _jstr {s} {
        set out ""
        foreach ch [split $s ""] {
            switch -exact -- $ch {
                "\"" { append out "\\\"" ; continue }
                "\\" { append out "\\\\" ; continue }
                "\n" { append out "\\n"  ; continue }
                "\r" { append out "\\r"  ; continue }
                "\t" { append out "\\t"  ; continue }
            }
            scan $ch %c code
            if {$code < 32 || $code > 126} {
                append out [format {\u%04x} $code]
            } else {
                append out $ch
            }
        }
        return "\"$out\""
    }

    proc _prompt_text {} {
        return [join {
            "You are reading one or more photographs of the SAME bag of roasted coffee beans, taken from different sides of the bag."
            "Combine the information printed across all of the photographs into one answer."
            "Extract only what is actually printed on the bag."
            "Reply with a single JSON object and nothing else - no prose, no markdown, no code fences."
            "Use exactly these keys: roaster, bean, roast_date, roast_level, origin, process, varietal, notes."
            "roaster is the roasting company. bean is the coffee's name or blend name."
            "roast_date must be YYYY-MM-DD; if only a roast week or month is printed, use the first day of it."
            "roast_level is one of Light, Medium-Light, Medium, Medium-Dark, Dark, or Omniroast, whichever the bag states or clearly implies."
            "origin is the country and region. process is e.g. Washed, Natural, Honey, Anaerobic."
            "varietal is the cultivar. notes is the printed tasting notes, comma separated."
            "Use null for anything not legible or not printed. Never guess and never invent a value."
        } " "]
    }

    # ==================================================================
    #  Vision API request (Anthropic or OpenAI, switchable)
    # ==================================================================

    proc send_image {jpeg_bytes} {
        send_images [list $jpeg_bytes]
    }

    proc send_images {jpeg_list} {
        variable scan
        set key [api_key]
        if {$key eq ""} {
            set_error "No API key. Add one in Settings > API Key, or put it in api_key_[_setting provider anthropic].txt inside the plugin folder."
            return
        }
        set b64s [list]
        set total 0
        foreach jpeg_bytes $jpeg_list {
            incr total [string length $jpeg_bytes]
            if {[catch { lappend b64s [_b64 $jpeg_bytes] } err]} {
                set_error $err
                return
            }
        }
        set provider [_setting provider anthropic]
        set model [model_id]
        set n [llength $b64s]
        set_stage sending "Sending $n photo[expr {$n == 1 ? {} : {s}}] ([_fmt_bytes $total]) to $model..."

        if {$provider eq "openai"} {
            set host "api.openai.com"
            set url  "https://api.openai.com/v1/chat/completions"
            set headers [list Authorization "Bearer $key"]
            set body [_openai_body $model $b64s]
        } else {
            set host "api.anthropic.com"
            set url  "https://api.anthropic.com/v1/messages"
            set headers [list x-api-key $key anthropic-version "2023-06-01"]
            set body [_anthropic_body $model $b64s]
        }

        if {[catch { _post_json $host $url $headers $body } err]} {
            set_error "Request failed: $err"
        }
    }

    proc _anthropic_body {model b64list} {
        set prompt [_jstr [_prompt_text]]
        set mt [_setting_int max_tokens 1500]
        set imgs ""
        foreach b64 $b64list {
            if {$imgs ne ""} { append imgs "," }
            append imgs "{\"type\":\"image\",\"source\":{\"type\":\"base64\",\"media_type\":\"image/jpeg\",\"data\":\"$b64\"}}"
        }
        return "{\"model\":[_jstr $model],\"max_tokens\":$mt,\"messages\":\[{\"role\":\"user\",\"content\":\[$imgs,{\"type\":\"text\",\"text\":$prompt}\]}\]}"
    }

    # No output-token cap is sent to OpenAI on purpose: the parameter name
    # differs across their model generations (max_tokens vs
    # max_completion_tokens) and the expected reply is a short JSON object
    # well under any default.
    proc _openai_body {model b64list} {
        set prompt [_jstr [_prompt_text]]
        set imgs ""
        foreach b64 $b64list {
            append imgs ",{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/jpeg;base64,$b64\"}}"
        }
        return "{\"model\":[_jstr $model],\"messages\":\[{\"role\":\"user\",\"content\":\[{\"type\":\"text\",\"text\":$prompt}$imgs\]}\]}"
    }

    # Asynchronous POST: -command keeps the Tk event loop alive so the tablet
    # UI does not freeze (and Android does not flag the app as unresponsive)
    # while a multi-megabyte upload is in flight.
    proc _post_json {host url headers body} {
        variable scan
        variable last_http
        set last_http ""
        ::http::register https 443 [list ::tls::socket -servername $host]
        catch { ::tls::init -tls1 0 -ssl2 0 -ssl3 0 -tls1.1 0 -tls1.2 1 -servername $host }
        set tmo [_setting_int request_timeout_ms 90000]
        set scan(busy) 1
        set scan(token) [::http::geturl $url \
            -headers $headers \
            -method POST \
            -type "application/json" \
            -query $body \
            -timeout $tmo \
            -command ::plugins::BeanScanner::_on_http_done]
    }

    proc _on_http_done {token} {
        variable scan
        variable last_http
        set scan(busy) 0
        set scan(token) ""
        set status ""
        set code 0
        set data ""
        catch { set status [::http::status $token] }
        catch { set code   [::http::ncode $token] }
        catch { set data   [::http::data $token] }
        catch { ::http::cleanup $token }
        catch { ::http::unregister https }
        set last_http "status=$status code=$code bytes=[string length $data]"

        if {$status eq "timeout"} {
            set_error "The request timed out. Increase the timeout or lower the capture size."
            return
        }
        if {$status ne "ok"} {
            set_error "HTTP $status. Check the tablet's network connection."
            return
        }
        if {$code < 200 || $code >= 300} {
            set_error "API returned HTTP $code: [_short $data 300]"
            return
        }
        _handle_response $data
    }

    proc _short {s n} {
        set s [string map {"\n" " " "\r" " "} $s]
        if {[string length $s] > $n} { return "[string range $s 0 $n]..." }
        return $s
    }

    # ==================================================================
    #  Response parsing
    # ==================================================================

    proc _handle_response {raw} {
        variable last_raw
        set last_raw $raw
        if {[catch { set text [_extract_text $raw] } err]} {
            set_error "Could not read the API response: $err"
            return
        }
        if {[string trim $text] eq ""} {
            set_error "The model returned no text. Try again with a sharper photo."
            return
        }
        if {[catch { set fields [_parse_fields $text] } err]} {
            set_error "The model did not return usable JSON: $err"
            return
        }
        _store_fields $fields
        # The scan succeeded, so the pending photos have served their
        # purpose (they are kept across send errors so Send can be retried).
        clear_photos
        set_stage done "Bag read."
        open_page BeanScanner_review
    }

    # Anthropic: content is a list of blocks; take the first "text" block
    # (thinking blocks may precede it and carry no text). OpenAI:
    # choices[0].message.content is the string.
    proc _extract_text {raw} {
        set d [::json::json2dict $raw]
        if {[dict exists $d content]} {
            foreach block [dict get $d content] {
                if {[catch { set t [dict get $block type] }]} { continue }
                if {$t eq "text" && [dict exists $block text]} {
                    set txt [dict get $block text]
                    if {[string trim $txt] ne ""} { return $txt }
                }
            }
        }
        if {[dict exists $d choices]} {
            set choices [dict get $d choices]
            if {[llength $choices] > 0} {
                set first [lindex $choices 0]
                if {[dict exists $first message content]} {
                    return [dict get $first message content]
                }
            }
        }
        if {[dict exists $d error message]} {
            error [dict get $d error message]
        }
        error "unrecognized response shape"
    }

    # Strip markdown fences and any prose around the JSON object, then parse.
    proc _parse_fields {text} {
        set t [string trim $text]
        regsub -all {```[a-zA-Z]*} $t "" t
        regsub -all {```} $t "" t
        set start [string first "\{" $t]
        set end   [string last  "\}" $t]
        if {$start < 0 || $end <= $start} {
            error "no JSON object in: [_short $t 160]"
        }
        set t [string range $t $start $end]
        return [::json::json2dict $t]
    }

    proc _dget {d k} {
        if {![dict exists $d $k]} { return "" }
        set v [string trim [dict get $d $k]]
        set blanks [list null none "n/a" unknown "not printed" "not legible" "not specified"]
        if {[lsearch -exact $blanks [string tolower $v]] >= 0} { return "" }
        return $v
    }

    proc _store_fields {d} {
        variable scan
        foreach k {roaster bean roast_date roast_level origin process varietal notes} {
            set scan($k) [_dget $d $k]
        }
        set scan(have_result) 1
    }

    proc clear_result {} {
        variable scan
        foreach k {roaster bean roast_date roast_level origin process varietal notes} {
            set scan($k) ""
        }
        set scan(have_result) 0
    }

    # Composed bean_notes: origin / process / varietal, then tasting notes.
    proc composed_notes {} {
        variable scan
        set parts [list]
        foreach k {origin process varietal} {
            if {$scan($k) ne ""} { lappend parts $scan($k) }
        }
        set head [join $parts " | "]
        if {$scan(notes) ne "" && $head ne ""} { return "$head\n$scan(notes)" }
        if {$scan(notes) ne ""} { return $scan(notes) }
        return $head
    }

    # ==================================================================
    #  Status / error reporting
    # ==================================================================

    proc set_stage {stage text} {
        variable scan
        set scan(stage) $stage
        set scan(status) $text
        catch { dui item config BeanScanner_capture scan_status -text $text }
        catch { msg "BeanScanner: $stage - $text" }
    }

    proc set_error {text} {
        variable scan
        variable last_error
        set last_error $text
        set scan(busy) 0
        set scan(stage) error
        set scan(status) $text
        catch { dui item config BeanScanner_capture scan_status -text $text }
        catch { msg -ERROR "BeanScanner: $text" }
        catch { borg toast "Bean Scanner: $text" 1 }
    }

    # ==================================================================
    #  DYE integration (the only write this plugin performs)
    # ==================================================================

    proc dye_available {} {
        if {[info procs ::plugins::DYE::shots::source_next_from] eq ""} { return 0 }
        if {[info procs ::plugins::DYE::shots::get_next] eq ""} { return 0 }
        return 1
    }

    # Maps the scanned values onto the app's bean metadata fields.
    #
    # A scan describes ONE bag, so with "Overwrite existing" on, every
    # enabled field is written -- including the ones the bag does not state,
    # which are written as EMPTY. Skipping empties (as v0.1.x did) left the
    # previous bag's roaster sitting next to the new bag's bean name, which
    # is then saved to shot history as a record of a bag that never existed.
    #
    # With "Overwrite existing" off the intent is the opposite -- fill only
    # what is currently blank -- so nothing is ever cleared in that mode.
    #
    # Guard: if the scan recognized nothing at all, no write happens, so a
    # failed read can never wipe the next-shot description.
    proc apply_to_dye {} {
        variable scan
        if {!$scan(have_result)} {
            set_error "Nothing to apply -- scan a bag first."
            return 0
        }
        if {![dye_available]} {
            set_error "DYE is not loaded. Enable the DYE plugin in Settings > App > Extensions."
            return 0
        }

        if {[catch { array set nx [::plugins::DYE::shots::get_next] } err]} {
            set_error "Could not read DYE's next shot: $err"
            return 0
        }
        # get_next leaves clock empty; source_next_from compares it numerically.
        set nx(clock) 0

        set proposed [list \
            bean_brand  $scan(roaster) \
            bean_type   $scan(bean) \
            roast_date  $scan(roast_date) \
            roast_level $scan(roast_level) \
            bean_notes  [composed_notes]]

        # Refuse to write when the scan produced nothing at all -- otherwise
        # a failed read would clear the whole next-shot description.
        set recognized 0
        foreach {field value} $proposed {
            if {$value ne ""} { set recognized 1; break }
        }
        if {!$recognized} {
            set_error "Nothing was recognized on the bag, so nothing was changed. Try again with a sharper, better-lit photo."
            return 0
        }

        set fields [list]
        set cleared [list]
        set overwrite [_is_true overwrite_existing]
        foreach {field value} $proposed {
            if {![_is_true apply_$field]} { continue }
            if {$overwrite} {
                # Write every enabled field, empty ones included: this bag
                # does not have that detail, so neither should the shot.
                if {$value eq "" && [info exists nx($field)] \
                        && [string trim $nx($field)] ne ""} {
                    lappend cleared $field
                }
                set nx($field) $value
                lappend fields $field
            } else {
                if {$value eq ""} { continue }
                if {[info exists nx($field)] && [string trim $nx($field)] ne ""} {
                    continue
                }
                set nx($field) $value
                lappend fields $field
            }
        }

        if {[llength $fields] == 0} {
            if {!$overwrite} {
                set_error "Overwrite existing is off and every field already has a value, so nothing was changed."
            } else {
                set_error "Nothing to apply: no field is enabled in Apply To Next Shot."
            }
            return 0
        }

        if {[catch { ::plugins::DYE::shots::source_next_from {} nx $fields } err]} {
            set_error "DYE rejected the update: $err"
            return 0
        }
        catch {
            if {[llength $cleared] > 0} {
                msg "BeanScanner: applied to DYE next shot: $fields (cleared: $cleared)"
            } else {
                msg "BeanScanner: applied to DYE next shot: $fields"
            }
        }
        catch { borg toast [translate "Bean details sent to your next shot"] 1 }
        return 1
    }
}

# ======================================================================
#  Pages
# ======================================================================

namespace eval ::dui::pages::BeanScanner_settings {

    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::BeanScanner::L L
        ::plugins::BeanScanner::_page_bg $page
        set lx $L(left_x)
        set rx $L(right_x)
        set cx $L(center_x)

        dui add dtext $page $cx $L(header_title_y) -tags page_title \
            -text [translate "Bean Scanner"] -font $L(font_title) \
            -width $L(content_w) -fill $L(fg_title) -anchor center -justify center
        dui add dtext $page $cx $L(header_subtitle_y) -tags subtitle \
            -text [translate "Photograph a bag, confirm what the AI reads, send it to your next shot."] \
            -font $L(font_caption) -width $L(content_w) -fill $L(fg_muted) \
            -anchor center -justify center

        # v0.5.0: theme toggle, top-right corner (the design system's
        # mode-button slot; same placement as MaintenanceTracker's).
        set th_y1 [expr {int(round(11 * $L(scale)))}]
        dui add dbutton $page [expr {$rx - $L(btn_h)}] $th_y1 \
            $rx [expr {$th_y1 + $L(btn_h)}] \
            -tags btn_theme -label [::plugins::BeanScanner::_theme_button_face] \
            -command ::plugins::BeanScanner::toggle_theme \
            -label_font [expr {$L(have_icons) ? $L(font_icon) : $L(font_button)}] \
            -style bsc_btn

        set col_w $L(sec_col_w)
        set c2x $L(sec_col2_x)
        set scan_h  [expr {2 * $L(sec_pad) + $L(sec_title_h) + $L(md) + 3 * $L(btn_h) + 2 * $L(md)}]
        set two_h   [expr {2 * $L(sec_pad) + $L(sec_title_h) + $L(md) + 2 * $L(row_pitch) - $L(md)}]
        set three_h [expr {2 * $L(sec_pad) + $L(sec_title_h) + $L(md) + 3 * $L(row_pitch) - $L(md)}]

        # ---- LEFT: actions, then what gets applied ----
        set y0 $L(sec_top)
        set ry [::plugins::BeanScanner::_sec_card $page sec_scan $lx $y0 $col_w $scan_h "Scan"]
        set bx1 [expr {$lx + $L(sec_pad)}]
        set bx2 [expr {$lx + $col_w - $L(sec_pad)}]
        foreach {label cmd} {
            "Scan Bean Bag"    "::plugins::BeanScanner::open_page BeanScanner_capture"
            "Use Latest Photo" "::plugins::BeanScanner::start_import"
            "Last Result"      "::plugins::BeanScanner::open_page BeanScanner_review"
        } {
            dui add dbutton $page $bx1 $ry $bx2 [expr {$ry + $L(btn_h)}] \
                -tags [string map {" " _} [string tolower $label]] -label [translate $label] \
                -command $cmd -label_font $L(font_button) -style bsc_btn
            set ry [expr {$ry + $L(btn_h) + $L(md)}]
        }

        set y0 [expr {$y0 + $scan_h + $L(sec_gap)}]
        _rows_card $page sec_apply $lx $y0 $col_w $two_h "Apply To Next Shot" {
            notes     "Include bag notes" notes_value     "Toggle" toggle_notes
            overwrite "Overwrite existing" overwrite_value "Toggle" toggle_overwrite
        }

        # ---- RIGHT: provider, then camera ----
        _rows_card $page sec_ai $c2x $L(sec_top) $col_w $three_h "AI Provider" {
            provider "Provider"  provider_value "Switch" toggle_provider
            model    "Model"     model_value    ""       {}
            apikey   "API key"   apikey_value   "Set"    open_apikey
        }
        set y0 [expr {$L(sec_top) + $three_h + $L(sec_gap)}]
        _rows_card $page sec_cam $c2x $y0 $col_w $two_h "Camera" {
            camera   "Camera"       camera_value  "Switch" toggle_camera
            capsize  "Capture size" capsize_value "Change" cycle_capture_size
        }

        # ---- Bottom bar ----
        dui add dbutton $page $lx $L(bar_y0) [expr {$lx + $L(btn_w_std)}] $L(bar_y1) \
            -tags page_done -label [translate "Done"] \
            -command ::dui::pages::BeanScanner_settings::page_done \
            -label_font $L(font_button) -style bsc_btn
        set b2 [expr {$rx - $L(btn_w_std)}]
        dui add dbutton $page $b2 $L(bar_y0) $rx $L(bar_y1) \
            -tags page_help -label [translate "Help"] \
            -command {::plugins::BeanScanner::open_page BeanScanner_help} \
            -label_font $L(font_button) -style bsc_btn
        set b1 [expr {$b2 - $L(md) - $L(btn_w_wide)}]
        dui add dbutton $page $b1 $L(bar_y0) [expr {$b1 + $L(btn_w_wide)}] $L(bar_y1) \
            -tags page_diag -label [translate "Diagnostics"] \
            -command {::plugins::BeanScanner::open_page BeanScanner_diagnostics} \
            -label_font $L(font_button) -style bsc_btn
    }

    # label / value / optional right-aligned button, inside a section card.
    proc _rows_card {page tag x y w h title rows} {
        upvar #0 ::plugins::BeanScanner::L L
        set ry [::plugins::BeanScanner::_sec_card $page $tag $x $y $w $h $title]
        set lab_x [expr {$x + $L(sec_pad)}]
        set val_x [expr {$x + $L(sec_value_dx)}]
        set btn_x2 [expr {$x + $w - $L(sec_pad)}]
        set btn_x1 [expr {$btn_x2 - $L(sec_btn_w)}]
        set val_w [expr {$btn_x1 - $L(lg) - $val_x}]
        set row 0
        foreach {key label value_tag btn_label btn_cmd} $rows {
            set y1 [expr {$ry + $row * $L(row_pitch)}]
            set mid [expr {$y1 + $L(btn_h) / 2}]
            # A row without a button gives its value the full width to the
            # card edge; otherwise a long value (e.g. a model id) wraps onto
            # a second line and collides with the next row.
            if {$btn_label ne "" && $btn_cmd ne ""} {
                set this_val_w $val_w
            } else {
                set this_val_w [expr {$btn_x2 - $val_x}]
            }
            dui add dtext $page $lab_x $mid -tags ${key}_label -text [translate $label] \
                -font $L(font_body) -width $L(sec_label_w) -fill $L(on_card_label) \
                -anchor w -justify left
            dui add dtext $page $val_x $mid -tags $value_tag -text "" \
                -font $L(font_primary) -width $this_val_w -fill $L(on_card_value) -anchor w -justify left
            if {$btn_label ne "" && $btn_cmd ne ""} {
                dui add dbutton $page $btn_x1 $y1 $btn_x2 [expr {$y1 + $L(btn_h)}] \
                    -tags ${key}_btn -label [translate $btn_label] \
                    -command ::dui::pages::BeanScanner_settings::$btn_cmd \
                    -label_font $L(font_button) -style bsc_btn
            }
            incr row
        }
    }

    proc show {page_to_hide page_to_show} {
        ::plugins::BeanScanner::_capture_return_page $page_to_hide
        # Reached through the settings page, so sub-pages should hand back
        # here rather than jumping past it.
        set ::plugins::BeanScanner::_entered_at_subpage 0
        ::plugins::BeanScanner::apply_defaults
        refresh $page_to_show
    }

    proc refresh {page} {
        set p [::plugins::BeanScanner::_setting provider anthropic]
        set pname [expr {$p eq "openai" ? "OpenAI" : "Anthropic"}]
        catch { dui item config $page provider_value -text $pname }
        catch { dui item config $page model_value -text [::plugins::BeanScanner::model_id] }
        switch -- [::plugins::BeanScanner::api_key_source] {
            settings { set ks [translate "Set"] }
            file     { set ks [translate "From file"] }
            default  { set ks [translate "Missing"] }
        }
        catch { dui item config $page apikey_value -text $ks }
        catch { dui item config $page camera_value -text \
            [string totitle [::plugins::BeanScanner::_setting camera_pref front]] }
        catch { dui item config $page capsize_value -text \
            [::plugins::BeanScanner::_setting capture_size 1600x1200] }
        catch { dui item config $page notes_value -text [_onoff apply_bean_notes] }
        catch { dui item config $page overwrite_value -text [_onoff overwrite_existing] }
        # v0.5.0: theme button face follows the effective theme.
        catch { dui item config $page btn_theme \
            -label [::plugins::BeanScanner::_theme_button_face] }
    }

    proc _onoff {key} {
        if {[::plugins::BeanScanner::_is_true $key]} { return [translate "On"] }
        return [translate "Off"]
    }

    proc _toggle {key} {
        if {[::plugins::BeanScanner::_is_true $key]} {
            set ::plugins::BeanScanner::settings($key) 0
        } else {
            set ::plugins::BeanScanner::settings($key) 1
        }
        ::plugins::BeanScanner::save_settings
        refresh BeanScanner_settings
    }

    proc toggle_notes {}     { _toggle apply_bean_notes }
    proc toggle_overwrite {} { _toggle overwrite_existing }

    proc toggle_provider {} {
        if {[::plugins::BeanScanner::_setting provider anthropic] eq "anthropic"} {
            set ::plugins::BeanScanner::settings(provider) openai
        } else {
            set ::plugins::BeanScanner::settings(provider) anthropic
        }
        ::plugins::BeanScanner::save_settings
        refresh BeanScanner_settings
    }

    proc toggle_camera {} {
        set values {front back auto}
        set cur [::plugins::BeanScanner::_setting camera_pref front]
        set idx [lsearch -exact $values $cur]
        if {$idx < 0} { set idx 0 }
        set ::plugins::BeanScanner::settings(camera_pref) \
            [lindex $values [expr {($idx + 1) % [llength $values]}]]
        ::plugins::BeanScanner::save_settings
        refresh BeanScanner_settings
    }

    proc cycle_capture_size {} {
        set values {640x480 1024x768 1280x960 1600x1200 2048x1536}
        set cur [::plugins::BeanScanner::_setting capture_size 1600x1200]
        set idx [lsearch -exact $values $cur]
        if {$idx < 0} { set idx 2 }
        set ::plugins::BeanScanner::settings(capture_size) \
            [lindex $values [expr {($idx + 1) % [llength $values]}]]
        ::plugins::BeanScanner::save_settings
        refresh BeanScanner_settings
    }

    proc open_apikey {} { ::plugins::BeanScanner::open_page BeanScanner_apikey }

    proc page_done {} {
        ::plugins::BeanScanner::save_settings
        ::plugins::BeanScanner::_exit_settings
    }
}

namespace eval ::dui::pages::BeanScanner_apikey {
    # The entry sits in the top half of the screen: the Android keyboard
    # covers the bottom half.
    variable key_text ""

    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::BeanScanner::L L
        ::plugins::BeanScanner::_page_bg $page
        set lx $L(left_x)
        set rx $L(right_x)
        set cx $L(center_x)

        dui add dtext $page $cx $L(header_title_y) -tags page_title \
            -text [translate "API Key"] -font $L(font_title) \
            -width $L(content_w) -fill $L(fg_title) -anchor center -justify center
        dui add dtext $page $cx $L(header_subtitle_y) -tags subtitle \
            -text [translate "A ChatGPT or Claude subscription is not API access -- create a key with pay-as-you-go credit."] \
            -font $L(font_caption) -width $L(content_w) -fill $L(fg_muted) \
            -anchor center -justify center

        set y $L(list_top)
        dui add dtext $page $lx $y -tags provider_label -text "" \
            -font $L(font_primary) -width $L(content_w) -fill $L(fg_body) \
            -anchor w -justify left

        set y [expr {$y + $L(row_pitch)}]
        dui add entry $page $lx $y -tags key_entry \
            -textvariable ::dui::pages::BeanScanner_apikey::key_text \
            -width 46 -font $L(font_body) -canvas_anchor w \
            -borderwidth 1 -bg $L(entry_bg) -foreground $L(on_card_value) -relief flat

        set y [expr {$y + $L(row_pitch)}]
        dui add dtext $page $lx $y -tags key_help \
            -text [translate "Alternatively, put the key in api_key_anthropic.txt or api_key_openai.txt inside the BeanScanner plugin folder on the tablet -- easier than typing it here. The settings entry wins when both exist."] \
            -font $L(font_caption) -width $L(content_w) -fill $L(fg_muted) \
            -anchor nw -justify left

        dui add dbutton $page $lx $L(bar_y0) [expr {$lx + $L(btn_w_std)}] $L(bar_y1) \
            -tags page_done -label [translate "Save"] \
            -command ::dui::pages::BeanScanner_apikey::page_done \
            -label_font $L(font_button) -style bsc_btn
        dui add dbutton $page [expr {$rx - $L(btn_w_std)}] $L(bar_y0) $rx $L(bar_y1) \
            -tags page_clear -label [translate "Clear"] \
            -command ::dui::pages::BeanScanner_apikey::clear_key \
            -label_font $L(font_button) -style bsc_btn
    }

    proc show {page_to_hide page_to_show} {
        variable key_text
        set p [::plugins::BeanScanner::_setting provider anthropic]
        set key_text [::plugins::BeanScanner::_setting api_key_$p ""]
        set pname [expr {$p eq "openai" ? "OpenAI" : "Anthropic"}]
        catch { dui item config $page_to_show provider_label \
            -text "[translate {Key for}] $pname" }
    }

    proc clear_key {} {
        variable key_text
        set key_text ""
    }

    proc page_done {} {
        variable key_text
        set p [::plugins::BeanScanner::_setting provider anthropic]
        set ::plugins::BeanScanner::settings(api_key_$p) [string trim $key_text]
        ::plugins::BeanScanner::save_settings
        ::plugins::BeanScanner::_exit_subpage
    }
}

namespace eval ::dui::pages::BeanScanner_capture {

    # v0.8.0: camera-app layout. Full-bleed preview on black, floating
    # circular controls (Tk has no alpha, so they are solid dark), the
    # shutter is a white disc in a ring, flash and flip are icon circles.
    # This page is deliberately theme-independent -- camera screens are
    # dark everywhere -- so it is excluded from _retheme_all.
    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::BeanScanner::L L
        set sw $L(screen_w)
        set sh $L(screen_h)
        set cx $L(center_x)
        set m  $L(cam_margin)
        set d  $L(cam_circle_d)
        set cy $L(cam_row_cy)
        set ifont [expr {$L(have_icons) ? $L(font_icon) : $L(font_button)}]
        set G ::plugins::BeanScanner::_glyph_or

        # Fixed black backdrop (NOT _page_bg: that one follows the theme).
        dui add canvas_item rect $page 0 0 $sw $sh \
            -fill $L(cam_bg) -outline $L(cam_bg) -tags page_bg

        # The preview is a Tk photo image: it renders at its own PHYSICAL
        # pixel size (camera_open asks for the largest preview that fits
        # the screen), anchored at the centre of the whole page.
        dui add canvas_item image $page $cx [expr {$sh / 2}] \
            -tags cam_preview -anchor center

        # --- top row: Cancel (x), status pill, flash ---
        dui add dbutton $page $m $m [expr {$m + $d}] [expr {$m + $d}] \
            -tags page_done -shape oval -fill $L(cam_circle) \
            -label [$G xmark "X"] -label_font $ifont -label_fill $L(cam_icon) \
            -command ::dui::pages::BeanScanner_capture::page_done
        # Slim status pill (per the mock), centred on the top row's axis.
        # A TRUE capsule, composed of two end ovals and a middle rect --
        # both the smooth-polygon helper and dui's round shape render
        # visibly squarer corners than their radius argument promises.
        set px0 [expr {$cx - $L(cam_pill_w) / 2}]
        set px1 [expr {$cx + $L(cam_pill_w) / 2}]
        set pcy [expr {$m + $d / 2}]
        set ph  $L(cam_pill_h)
        set py0 [expr {$pcy - $ph / 2}]
        set py1 [expr {$pcy + $ph / 2}]
        dui add canvas_item oval $page $px0 $py0 [expr {$px0 + $ph}] $py1 \
            -fill $L(cam_circle) -outline $L(cam_circle) -tags status_pill_l
        dui add canvas_item oval $page [expr {$px1 - $ph}] $py0 $px1 $py1 \
            -fill $L(cam_circle) -outline $L(cam_circle) -tags status_pill_r
        dui add canvas_item rect $page [expr {$px0 + $ph / 2}] $py0 \
            [expr {$px1 - $ph / 2}] $py1 \
            -fill $L(cam_circle) -outline $L(cam_circle) -tags status_pill_c
        dui add dtext $page $cx $pcy -tags scan_status \
            -text "" -font $L(font_caption) -width [expr {$L(cam_pill_w) - $L(lg)}] \
            -fill $L(cam_icon) -anchor center -justify center
        dui add dbutton $page [expr {$sw - $m - $d}] $m [expr {$sw - $m}] [expr {$m + $d}] \
            -tags flash_btn -shape oval -fill $L(cam_circle) \
            -label [$G bolt-slash "fl off"] -label_font $ifont -label_fill $L(cam_icon) \
            -command ::plugins::BeanScanner::flash_cycle

        # --- bottom row: Send pill, Clear, shutter, flip ---
        set sy0 [expr {$cy - $L(btn_h) / 2}]
        set sy1 [expr {$cy + $L(btn_h) / 2}]
        set snd_x0 [expr {$m + 94}]
        set snd_x1 [expr {$snd_x0 + $L(cam_send_w)}]
        # -radius equals the FULL button height on purpose: dui's round
        # shape draws corner circles whose DIAMETER is the radius value,
        # so height-sized "radius" (clamped to the height internally) is
        # what actually renders as a capsule.
        dui add dbutton $page $snd_x0 $sy0 $snd_x1 $sy1 \
            -tags send_btn -shape round -radius $L(btn_h) \
            -fill $L(cam_send_fill) \
            -label [translate "Send"] -label_font $L(font_button) \
            -label_fill $L(cam_send_text) \
            -command ::plugins::BeanScanner::send_photos
        # Inside the pill, per the mock: a dark count badge on the left
        # (hidden until a photo exists) and a paper plane on the right.
        # They sit ON TOP of the button, so their taps are forwarded to
        # send_photos with a raw canvas tag binding below.
        set bd $L(cam_badge_d)
        set bx0 [expr {$snd_x0 + 24}]
        dui add canvas_item oval $page $bx0 [expr {$cy - $bd / 2}] \
            [expr {$bx0 + $bd}] [expr {$cy + $bd / 2}] \
            -fill $L(cam_send_text) -outline $L(cam_send_text) \
            -tags send_badge -initial_state hidden
        dui add dtext $page [expr {$bx0 + $bd / 2}] $cy -tags send_badge_n \
            -text "0" -font $L(font_button) -fill $L(cam_send_fill) \
            -anchor center -justify center -initial_state hidden
        # Plane: smaller than the other icons, centred between the end of
        # the "Send" label and the pill's right wall.
        dui add dtext $page [expr {$snd_x1 - 66}] $cy -tags send_plane \
            -text [$G paper-plane ">"] \
            -font [expr {$L(have_icons) ? $L(font_icon_sm) : $L(font_button)}] \
            -fill $L(cam_send_text) \
            -anchor center -justify center
        catch {
            set can [dui canvas]
            foreach t {send_badge send_badge_n send_plane} {
                $can bind $t <ButtonRelease-1> ::plugins::BeanScanner::send_photos
            }
        }
        set clr_x0 [expr {$snd_x1 + $L(md)}]
        dui add dbutton $page $clr_x0 [expr {$cy - $d / 2}] \
            [expr {$clr_x0 + $d}] [expr {$cy + $d / 2}] \
            -tags clear_btn -shape oval -fill $L(cam_circle) \
            -label [$G trash-can "Clr"] -label_font $ifont -label_fill $L(cam_icon) \
            -command ::dui::pages::BeanScanner_capture::clear_pressed

        set rr [expr {$L(cam_ring_d) / 2}]
        dui add canvas_item oval $page [expr {$cx - $rr}] [expr {$cy - $rr}] \
            [expr {$cx + $rr}] [expr {$cy + $rr}] \
            -outline "#ffffff" -width 5 -fill {} -tags shutter_ring
        set sr [expr {$L(cam_shutter_d) / 2}]
        # The shutter is label-free by design; the single space keeps a
        # real label sub-item in existence (empty-label dbuttons can
        # never be relabelled later -- the sub-item is simply not built).
        dui add dbutton $page [expr {$cx - $sr}] [expr {$cy - $sr}] \
            [expr {$cx + $sr}] [expr {$cy + $sr}] \
            -tags capture_btn -shape oval -fill "#ffffff" \
            -label " " -label_font $L(font_button) \
            -command ::plugins::BeanScanner::capture_jpeg

        # Flip: the plain two-arrow loop (per the mock -- arrows-rotate,
        # not the camera-with-arrows glyph).
        set fr [expr {$L(cam_flip_d) / 2}]
        set flip_cx [expr {$cx + 786}]
        dui add dbutton $page [expr {$flip_cx - $fr}] [expr {$cy - $fr}] \
            [expr {$flip_cx + $fr}] [expr {$cy + $fr}] \
            -tags cam_btn -shape oval -fill $L(cam_circle) \
            -label [$G arrows-rotate "Flip"] -label_font $ifont \
            -label_fill $L(cam_icon) \
            -command ::plugins::BeanScanner::camera_flip

        # Screen-flash overlay: created LAST so it covers everything,
        # starts hidden (st:hidden via -initial_state, so page loads never
        # flash it), and is pure white -- it is a light source, not a
        # surface, so _retheme_all must not touch it.
        dui add canvas_item rect $page 0 0 $sw $sh \
            -fill "#ffffff" -outline "#ffffff" -tags flash_overlay \
            -initial_state hidden
    }

    proc show {page_to_hide page_to_show} {
        # A fresh visit is a fresh scan: pending photos from an interrupted
        # or cancelled session must not leak into this one (mode/page
        # switches reset input state).
        ::plugins::BeanScanner::clear_photos
        ::plugins::BeanScanner::restart_camera
    }

    # Always release the camera when this page goes away -- including when a
    # flush/rinse/steam screen takes over, which the framework routes here.
    # camera_close also cancels a pending screen-flash timer and restores
    # the brightness if a screen flash was mid-way.
    proc hide {page_to_hide page_to_show} {
        ::plugins::BeanScanner::camera_close
    }

    proc clear_pressed {} {
        ::plugins::BeanScanner::clear_photos
        ::plugins::BeanScanner::set_stage preview [translate "Photos cleared. Tap Capture."]
    }

    proc page_done {} {
        ::plugins::BeanScanner::camera_close
        ::plugins::BeanScanner::clear_photos
        ::plugins::BeanScanner::_exit_subpage
    }
}

namespace eval ::dui::pages::BeanScanner_review {

    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::BeanScanner::L L
        ::plugins::BeanScanner::_page_bg $page
        set lx $L(left_x)
        set rx $L(right_x)
        set cx $L(center_x)

        dui add dtext $page $cx $L(header_title_y) -tags page_title \
            -text [translate "Check The Bag Details"] -font $L(font_title) \
            -width $L(content_w) -fill $L(fg_title) -anchor center -justify center
        dui add dtext $page $cx $L(header_subtitle_y) -tags subtitle \
            -text [translate "Nothing is saved until you press Accept. Blank means the model could not read it."] \
            -font $L(font_caption) -width $L(content_w) -fill $L(fg_muted) \
            -anchor center -justify center

        set y $L(list_top)
        foreach {tag label} {
            roaster_value    "Roaster"
            bean_value       "Beans"
            date_value       "Roasted"
            level_value      "Roast level"
        } {
            set mid [expr {$y + $L(btn_h) / 2}]
            dui add dtext $page $lx $mid -tags ${tag}_label -text [translate $label] \
                -font $L(font_body) -width $L(label_col_w) -fill $L(fg_muted) \
                -anchor w -justify left
            dui add dtext $page $L(value_x) $mid -tags $tag -text "" \
                -font $L(font_primary) -width [expr {$rx - $L(value_x)}] \
                -fill $L(fg_title) -anchor w -justify left
            set y [expr {$y + $L(row_pitch)}]
        }
        # Notes can wrap over several lines, so it is anchored top-left.
        dui add dtext $page $lx [expr {$y + $L(sm)}] -tags notes_label \
            -text [translate "Notes"] -font $L(font_body) -width $L(label_col_w) \
            -fill $L(fg_muted) -anchor nw -justify left
        dui add dtext $page $L(value_x) [expr {$y + $L(sm)}] -tags notes_value \
            -text "" -font $L(font_body) -width [expr {$rx - $L(value_x)}] \
            -fill $L(fg_body) -anchor nw -justify left

        dui add dbutton $page $lx $L(bar_y0) [expr {$lx + $L(btn_w_wide)}] $L(bar_y1) \
            -tags accept_btn -label [translate "Accept"] \
            -command ::dui::pages::BeanScanner_review::accept \
            -label_font $L(font_button) -style bsc_btn
        set b2 [expr {$rx - $L(btn_w_std)}]
        dui add dbutton $page $b2 $L(bar_y0) $rx $L(bar_y1) \
            -tags page_done -label [translate "Cancel"] \
            -command {::plugins::BeanScanner::_exit_subpage} \
            -label_font $L(font_button) -style bsc_btn
        set b1 [expr {$b2 - $L(md) - $L(btn_w_std)}]
        dui add dbutton $page $b1 $L(bar_y0) [expr {$b1 + $L(btn_w_std)}] $L(bar_y1) \
            -tags rescan_btn -label [translate "Rescan"] \
            -command {::plugins::BeanScanner::open_page BeanScanner_capture} \
            -label_font $L(font_button) -style bsc_btn
    }

    proc show {page_to_hide page_to_show} {
        upvar #0 ::plugins::BeanScanner::scan scan
        upvar #0 ::plugins::BeanScanner::L L
        set dash "—"
        set overwrite [::plugins::BeanScanner::_is_true overwrite_existing]

        # In overwrite mode a blank field is not "left alone", it is cleared
        # -- so show that explicitly rather than letting Accept do it
        # silently. Only fields that currently hold a value are flagged.
        array set cur {}
        if {$overwrite && [::plugins::BeanScanner::dye_available]} {
            catch { array set cur [::plugins::DYE::shots::get_next] }
        }

        foreach {tag key field} {
            roaster_value roaster     bean_brand
            bean_value    bean        bean_type
            date_value    roast_date  roast_date
            level_value   roast_level roast_level
            notes_value   {}          bean_notes
        } {
            if {$key eq ""} {
                set v [::plugins::BeanScanner::composed_notes]
            } else {
                set v $scan($key)
            }
            set fill $L(fg_title)
            if {$tag eq "notes_value"} { set fill $L(fg_body) }
            if {$v eq ""} {
                if {$overwrite && [::plugins::BeanScanner::_is_true apply_$field] \
                        && [info exists cur($field)] \
                        && [string trim $cur($field)] ne ""} {
                    set v "$dash  [translate {will be cleared}]"
                    set fill $L(fg_warn)
                } else {
                    set v $dash
                }
            }
            catch { dui item config $page_to_show $tag -text $v -fill $fill }
        }

        if {$overwrite} {
            set sub [translate "Nothing is saved until you press Accept. Blank fields are cleared, because these details belong to one bag."]
        } else {
            set sub [translate "Nothing is saved until you press Accept. Blank fields are left as they are (Overwrite existing is off)."]
        }
        catch { dui item config $page_to_show subtitle -text $sub }
    }

    proc accept {} {
        if {[::plugins::BeanScanner::apply_to_dye]} {
            ::plugins::BeanScanner::_exit_subpage
        }
    }
}

namespace eval ::dui::pages::BeanScanner_diagnostics {

    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::BeanScanner::L L
        ::plugins::BeanScanner::_page_bg $page
        set lx $L(left_x)
        set rx $L(right_x)
        set cx $L(center_x)

        dui add dtext $page $cx $L(header_title_y) -tags page_title \
            -text [translate "Bean Scanner Diagnostics"] -font $L(font_title) \
            -width $L(content_w) -fill $L(fg_title) -anchor center -justify center

        dui add dtext $page $lx $L(toolbar_y0) -tags diag_text -text "" \
            -font $L(font_caption) -width $L(content_w) -fill $L(fg_body) \
            -anchor nw -justify left

        dui add dbutton $page $lx $L(bar_y0) [expr {$lx + $L(btn_w_std)}] $L(bar_y1) \
            -tags page_done -label [translate "Done"] \
            -command {::plugins::BeanScanner::_exit_subpage} \
            -label_font $L(font_button) -style bsc_btn
        dui add dbutton $page [expr {$rx - $L(btn_w_wide)}] $L(bar_y0) $rx $L(bar_y1) \
            -tags probe_btn -label [translate "Probe Camera"] \
            -command ::dui::pages::BeanScanner_diagnostics::probe \
            -label_font $L(font_button) -style bsc_btn
    }

    proc show {page_to_hide page_to_show} { refresh $page_to_show }

    proc probe {} {
        ::plugins::BeanScanner::camera_probe
        refresh BeanScanner_diagnostics
    }

    proc refresh {page} {
        upvar #0 ::plugins::BeanScanner::cam cam
        set lines [list]
        lappend lines "Version: $::plugins::BeanScanner::version"
        lappend lines "Provider: [::plugins::BeanScanner::_setting provider anthropic]   Model: [::plugins::BeanScanner::model_id]"
        lappend lines "API key: [::plugins::BeanScanner::api_key_source]"
        lappend lines "DYE loaded: [expr {[::plugins::BeanScanner::dye_available] ? {yes} : {NO - enable DYE in Extensions}}]"
        lappend lines "Camera preference: [::plugins::BeanScanner::_setting camera_pref front]   Capture: [::plugins::BeanScanner::_setting capture_size 1600x1200]"
        set fl [::plugins::BeanScanner::_setting flash_mode off]
        if {$cam(flash_modes) ne ""} {
            set fhw [expr {$cam(flash_hw) eq "" ? "none - screen flash" : $cam(flash_hw)}]
            lappend lines "Flash: $fl   Hardware (last camera): $fhw (modes: [join $cam(flash_modes) {, }])"
        } else {
            lappend lines "Flash: $fl   Hardware: unknown until a camera is opened (front cameras use screen flash)"
        }
        lappend lines "Import folder: [::plugins::BeanScanner::_setting import_dir /sdcard/DCIM/Camera]"
        lappend lines ""
        if {$cam(probe) eq ""} {
            lappend lines "Camera probe: not run yet - tap Probe Camera."
        } else {
            lappend lines "Camera probe:"
            lappend lines $cam(probe)
        }
        if {$cam(last_bytes) > 0} {
            lappend lines "Last capture: [::plugins::BeanScanner::_fmt_bytes $cam(last_bytes)]"
        }
        lappend lines ""
        lappend lines "Last HTTP: [expr {$::plugins::BeanScanner::last_http eq {} ? {none} : $::plugins::BeanScanner::last_http}]"
        lappend lines "Last error: [expr {$::plugins::BeanScanner::last_error eq {} ? {none} : $::plugins::BeanScanner::last_error}]"
        if {$::plugins::BeanScanner::last_raw ne ""} {
            lappend lines "Last response: [::plugins::BeanScanner::_short $::plugins::BeanScanner::last_raw 400]"
        }
        catch { dui item config $page diag_text -text [join $lines "\n"] }
    }
}

namespace eval ::dui::pages::BeanScanner_help {

    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::BeanScanner::L L
        ::plugins::BeanScanner::_page_bg $page
        set lx $L(left_x)
        set cx $L(center_x)

        dui add dtext $page $cx $L(header_title_y) -tags page_title \
            -text [translate "Bean Scanner Help"] -font $L(font_title) \
            -width $L(content_w) -fill $L(fg_title) -anchor center -justify center

        set body [join {
            "1. Put your API key in Settings > API key, or push a file named api_key_anthropic.txt (or api_key_openai.txt) into the BeanScanner plugin folder. A ChatGPT Plus or Claude Pro subscription does NOT include API access -- create a key with pay-as-you-go credit instead. One scan costs a fraction of a cent."
            ""
            "2. Tap Scan Bean Bag. The screen becomes a camera: the white circle at the bottom takes a picture. Photograph every side of the bag that has printing on it -- the roast date is often on the back -- then tap Send to have all the photos read together. The trash circle drops the photos and starts over; the X (top left) cancels. Good light and a steady hand matter more than resolution."
            ""
            "The lightning circle (top right) is the flash: slashed white = off, yellow = on, yellow with an A = auto (back camera only). On the back camera the real flash is used as a steady light; the front camera has no flash, so the whole screen turns white while the picture is taken -- the screen never flashes for the back camera. The two-arrow circle flips between the front and back camera without leaving the page; photos already taken are kept."
            ""
            "Known tablet quirk: pointing the camera straight at a bright LED or lamp in a dark room can make the live preview stutter. That is the tablet's camera itself, not the plugin, and it does not affect the captured photos -- scan bags in normal light and it never comes up."
            ""
            "3. Check what came back. Blank fields mean the model could not read them -- it is told never to guess. Tap Rescan for another photo, or Accept to send the details to DYE's next shot."
            ""
            "A scan describes one bag, so a blank field is CLEARED rather than left holding the previous bag's value -- otherwise a bag with no roaster printed on it would inherit the last roaster and your shot history would record a bag that never existed. The review page marks every field that is about to be cleared. If you would rather keep whatever is already there and only fill in the blanks, turn Overwrite existing off."
            ""
            "4. If the camera will not start, open Diagnostics and tap Probe Camera. If it reports that android.permission.CAMERA is not declared in the app manifest, this build of the app cannot use the camera directly: take the photo with the tablet's own camera app instead, then use Use Latest Photo."
            ""
            "Nothing is written until you press Accept, and the only thing written is DYE's next-shot description. Your shot database and history files are never touched."
        } "\n"]
        dui add dtext $page $lx $L(list_top) -tags help_text -text [translate $body] \
            -font $L(font_caption) -width $L(content_w) -fill $L(fg_body) \
            -anchor nw -justify left

        dui add dbutton $page $lx $L(bar_y0) [expr {$lx + $L(btn_w_std)}] $L(bar_y1) \
            -tags page_done -label [translate "Done"] \
            -command {::plugins::BeanScanner::_exit_subpage} \
            -label_font $L(font_button) -style bsc_btn
    }
}

# Entry point used by the settings page's "Use Latest Photo" button: shows the
# capture page for status feedback, but takes the image from the import folder
# instead of the camera.
proc ::plugins::BeanScanner::start_import {} {
    clear_result
    import_latest
}
