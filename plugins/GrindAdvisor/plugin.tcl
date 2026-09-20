#
# Grind Advisor  --  DE1app plugin manifest
#
# After every completed espresso shot, Grind Advisor reads the most recent
# shot (and the one before it) from SDB and shows a popup recommending your
# next grind setting. You never enter anything by hand.
#
# It is strictly READ-ONLY: it opens the shot database read-only (or reuses an
# existing connection for SELECTs only) and never writes, deletes, or alters
# the schema.
#
# Install path:  de1plus/plugins/GrindAdvisor/
#

package require Tcl 8.5

set plugin_name "GrindAdvisor"

namespace eval ::plugins::GrindAdvisor {
    variable author      "Blastize"
    variable contact     "n/a"
    variable version     "3.16.3"
    variable name        "Grind Advisor"
    variable description  "Reads your latest shot from SDB and recommends your next grind. Read-only, no manual entry."

    # ---- Defaults (no manual per-shot entry required) ----
    # These are tunable but ship with the values from the spec. We set each key
    # only if it is missing, because the plugin framework may have already
    # created this array (possibly empty) before this file is sourced. Using a
    # whole-array "if exists" guard here would skip the defaults entirely.
    variable settings
    foreach {__k __v} {
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
        dose_yield_mode          auto
        dose_min                 12.0
        dose_max                 22.0
        ratio_min                1.0
        ratio_max                4.0
        theme                    light
    } {
        if {![info exists settings($__k)]} { set settings($__k) $__v }
    }
    unset -nocomplain __k __v

    # ---- Runtime state ----
    variable last_shown_id   ""
    variable last_error_text ""
    variable last_error_time 0
    variable _pending_after  ""
    variable hooked          0
    variable upload_traced   0
    variable _btnseq         0

    # Directory this manifest lives in (used to load the implementation).
    variable plugin_dir [file dirname [info script]]
}

# Load the implementation that sits next to this manifest.
if {[file exists [file join $::plugins::GrindAdvisor::plugin_dir GrindAdvisor.tcl]]} {
    source [file join $::plugins::GrindAdvisor::plugin_dir GrindAdvisor.tcl]
}

# Called by the plugin framework. Return the name of a settings page.
proc ::plugins::GrindAdvisor::preload {} {
    return [preload_settings_page]
}

# Called by the framework when the plugin is enabled / on startup.
proc ::plugins::GrindAdvisor::main {} {
    variable settings
    # Pick up any persisted overrides if the framework stored them, then make
    # sure every key has a value (load_settings may not include all of them).
    catch { plugins load_settings GrindAdvisor }
    apply_defaults
    load_last_recommendation
    register_shot_complete_hook
    catch { msg "GrindAdvisor: started (target [_setting target_time 28.0]s)" }
    return
}

proc ::plugins::GrindAdvisor::save_settings {} {
    catch { plugins save_settings GrindAdvisor }
}
