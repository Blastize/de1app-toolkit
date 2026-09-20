#
# Shot History Editor -- DE1app plugin manifest
#
# Pass 5.0 (second destructive-capability pass): activates real metadata
# save. Editing a shot's field on Edit Metadata Preview and confirming Save
# Change now rewrites ONLY that one key inside history/<filename>.shot's
# settings{} block (backup + verified temp-write + atomic rename; every
# other byte, including raw sensor arrays, is untouched). Soft delete/
# trash/restore from v0.4.0/v0.4.1 are unchanged. SDB is never written to;
# the card list and Detail page overlay saved edits from a plugin-owned
# manifest until SDB resyncs on its own. This plugin only opens from
# Extensions and does not register shot hooks.
#
# Pass 5.1 (bugfix): _return_to_page now loops close_dialog until it
# actually reaches its target instead of closing once and papering over a
# mismatch with a forced page load. Multi-level flows (Edit Preview ->
# Confirm -> Result) left stale un-popped levels in the dialog stack, so
# the Settings page's own Done button needed two taps to really exit (the
# first tap surfaced the stale Edit Preview page instead). No new write
# behavior; navigation-only fix.
#
# Pass 5.2 (bugfix, proactive hardening): applies the same fix GrindAdvisor
# v1.8.8 landed for its "Done lands on the flush screen" bug, since the
# confirmed root cause (de1app-core's page_stack getting reset to a single
# entry whenever a flow-monitor page -- flush/rinse/steam/etc. -- is shown,
# even while an fpdialog page is current) applies to any fpdialog plugin,
# not just GrindAdvisor. Every Done/Back/Cancel button in this plugin now
# navigates via `dui page load` to a specific known real target
# (_navigate_done) instead of `dui page close_dialog` trusting the
# framework's "previous page" bookkeeping, which a flush interruption can
# silently corrupt. No new write behavior; navigation-only fix.
#
# Pass 5.3 (bugfix, root cause confirmed from de1app-core source AND
# reproduced in an offline simulator): v0.5.2's direct `dui page load` to a
# stacked ancestor is unsafe in this core build -- the core's page_stack
# truncation uses multi-key `dict unset`, which Tcl treats as a nested key
# path, so unwinding 2 levels silently leaves stale stack entries and 3+
# levels errors out. Internal returns now unwind one close_dialog at a time
# (_return_to_page loop); the Settings Done exit keeps _navigate_done with
# a captured outside page, and the capture now also skips this plugin's own
# pages (the missing filter that made Done ping-pong back into sub-flows).
# No new write behavior; navigation-only fix.
#
# Pass 5.4 (bugfix, root cause confirmed from the app log): under Lumen,
# the pages rendered "inverted" -- near-black background, buttons reduced
# to bare labels. Two defects, one cause: Lumen's DYE integration switches
# the current dui theme to DYE_Lumen (skin.tcl:1831) before this plugin
# loads, so (a) the she_btn style, registered without -theme, landed in
# DYE_Lumen where the -theme default pages never find it (BeanScanner
# v0.1.2's exact bug), and (b) fpdialog pages have no background of their
# own and showed the dark canvas beneath. Fix copied verbatim from
# BeanScanner: aspect set with -theme default + explicit fills, and a
# self-painted full-page background (_page_bg) on every page. Display-only
# fix; no write behavior changed.
#

package require Tcl 8.5

set plugin_name "ShotHistoryEditor"

namespace eval ::plugins::ShotHistoryEditor {
    variable author      "Blastize"
    variable contact     "n/a"
    # No "v" prefix in the VALUE. The startup message below prepends one, so a
    # prefixed value logged as "vv0.6.3" (v0.6.4). Every other plugin on the
    # tablet stores a bare number here too; the core only reads this variable
    # to decide whether the plugin's metadata loaded, and never displays it.
    variable version     "0.13.0"
    variable name        "Shot History Editor"
    variable description "Card-based shot browser with real metadata save and soft delete (move to trash, restorable) for DE1app shot history."

    # v0.8.0: first persisted setting -- the UI theme (light | dark),
    # toggled by the sun/moon button on the main page.
    variable settings
    if {![info exists settings(theme)]} { set settings(theme) light }

    variable plugin_dir [file dirname [info script]]
}

if {[file exists [file join $::plugins::ShotHistoryEditor::plugin_dir ShotHistoryEditor.tcl]]} {
    source [file join $::plugins::ShotHistoryEditor::plugin_dir ShotHistoryEditor.tcl]
}

proc ::plugins::ShotHistoryEditor::preload {} {
    return [preload_pages]
}

proc ::plugins::ShotHistoryEditor::main {} {
    catch { msg "ShotHistoryEditor: started card browser v$::plugins::ShotHistoryEditor::version (edit save + soft delete active)" }
    return
}
