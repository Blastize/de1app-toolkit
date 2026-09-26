#
# Maintenance Tracker -- DE1app plugin manifest
#
# v0.29.1 polish: section cards behind Detail (status, History, Linked
# profile), Steps, Edit steps and New Tracker. Layout only.
#
# Pass 35 (v0.29.0): remove one chosen history record. Tap a row of the
# Detail page's history; the two-tap confirm names it ("Yes, Remove This
# Record"); the removed record is escrowed and logged. Undo (newest)
# works as before.
#
# Pass 34 (v0.28.0): step editor. The Steps page's Edit steps opens a
# page to edit, add, remove and reorder a tracker's steps (DrinkMenu's
# Method pattern: a draft, written once by Save into the tracker's own
# `steps`; Reset to default returns it to the built-in template).
#
# Pass 33 (v0.27.0): Start on a profile-linked tracker remembers the
# loaded espresso profile, loads the cleaning profile and asks for the
# group head's espresso button; the espresso profile comes back after the
# run, on Switch back now, after 10 min unused, or at the next app start.
# New automatic write: the switch-back's select_profile + save + send.
#
# Pass 32 (v0.26.0): every tracker gets a Steps page -- numbered
# instructions (built-in templates picked by keywords in its name,
# "{start}" resolved for its link) and one green action: Load profile,
# Open Descale, Start Clean or Mark done. Detail's Start opens it. No
# new write behavior.
#
# Pass 31 (v0.25.0): tracker list sorts worst first by how close each
# tracker is to due (was: by status only, creation order inside it).
# Detail: Link / Unlink moved to the Edit page (a draft, applied on Save),
# the linked profile shows in full, a green Record button, Undo demoted
# to a normal button that turns red only when armed. Same write paths.
#
# Pass 30 (v0.24.1): Load profile and Link profile check that
# profiles/<fn>.tcl exists before touching the app's profile. The core
# resets part of the profile before its own check, and a wrapper from
# another plugin drops its "missing" answer. No write behavior changes.
#
# Pass 29 (v0.24.0): a finished cleaning-PROFILE run auto-records the
# trackers linked to that exact profile, and only those; with none linked,
# every Clean-cycle subscriber records as before. A tracker linked to a
# cleaning profile shows AUTO-RECORD and names the profile. Same single
# write path (settings.tdb); profile files are only read.
#
# Pass 28 (v0.23.1): the list and Detail pages' show hooks skip their
# refresh unless the page is still on screen. Open Descale left the
# list page's queued (after idle) show to paint Prev/Next over the app's
# "Prepare to descale" page. No write behavior changes.
#
# Pass 27 (v0.23.0): a tracker may link the app's own DESCALE or CLEAN
# action (Settings > Machine > Maintenance) instead of a profile. The
# Detail row reads "Linked to:" with [Link profile] [Link Descale]
# [Link Clean]. Open Descale shows the app's "Prepare to descale" page
# through the core's show_settings (fresh settings backup; the user still
# presses the stock "Descale now"). Start Clean asks first -- the first
# tap arms for 8 s, the second calls the core's start_cleaning, refused
# unless the machine is connected and idle or asleep. FIRST capability
# in this plugin that starts a machine cycle, and only on that second tap.
# Writes: the link taps save settings.tdb (link_kind in the item dict).
#
# Pass 26 (v0.22.0): linked profile per tracker. The Detail page gains
# a "Profile:" row -- "Link current profile" stores the profile loaded
# in the app (filename + title) in the tracker's item dict, "Unlink"
# removes it, "Load profile" hands it to the app through the core's
# own select_profile (DrinkMenu's proven call and busy guard), so a
# backflush alert becomes: wrench, card, Load profile, GHC button.
# Writes: the two link taps save settings.tdb; loading never touches a
# file of ours and never starts a flow.
#
# Pass 22 (v0.21.0): auto choice at creation + auto-count tags. The
# New Tracker page's top-right header toggle picks the auto-record
# source while creating ("Auto: off / Clean cycle / Descale cycle").
# Card tags now tell the two automations apart: AUTO-RECORD (the
# tracker resets itself when a Clean/Descale cycle completes) vs
# AUTO-COUNT (shots/ml counters climb by themselves; recording the
# maintenance stays a manual tap), and the Detail page says which in
# words. No new write behavior of any kind.
#
# Pass 21 (v0.20.0): relative time + choosable auto-record sources.
# "Last done" now reads "(just now / N minutes / N hours / N days
# ago)" instead of always days. Every tracker (built-in or custom)
# carries an `auto_src` field -- off, Clean cycle or Descale cycle --
# set from a new "Auto-record" row on its Edit page; the existing
# cycle detectors now record EVERY subscribed tracker instead of the
# hardwired backflush/descale pair (a migration reproduces the old
# wiring exactly, so nothing changes until the user edits it).
# Auto-recording trackers wear an "AUTO" tag on their card and name
# their source on the Detail page; Diagnostics shows how many trackers
# each detector feeds. No new write behavior: the same settings.tdb
# save paths (explicit taps + one auto event per real detected cycle,
# still gated by the auto_record toggle and the duration thresholds).
#
# v0.19.1 (owner follow-up): the normal-style buttons follow the theme
# too (muted indigo faces on dark, restyled live via their -btn shape
# tags). Danger red and the white labels stay identical in both.
#
# Pass 20 (v0.19.0): dark mode. A sun/moon button in the main page's
# top-right corner switches the whole plugin between a light and a
# dark palette instantly (all pages repaint on the spot; the choice
# persists in the plugin's own settings). State colors and button
# faces are identical in both themes. The one new write is
# settings(theme) saved on each explicit toggle tap.
#
# Pass 19 (v0.18.0): the Add/Edit pages name the selected icon next to
# "Icon:" (e.g. "Icon:  Steam wand") so the pick has a meaning, and
# the Detail page shows the tracker's icon top-left on a state-tinted
# plate, matching its card. Pure UI pass; no write-behavior changes.
#
# Pass 18 (v0.17.0): plugin-drawn vector icons. steam-wand (a spout
# blasting steam, side view) and gasket-flat (the ring squashed flat)
# are stroke drawings rendered by the plugin on the canvas -- the FA
# font has no honest versions of either. They live in the picker where
# wand and record-vinyl were, store as icon names like any other, and
# recolor with the state tint. Pure UI pass; no write-behavior
# changes.
#
# Pass 17 (v0.16.0): required-meaning picker icons. Steam wand (wand),
# drain pipe (pipe-section), ball joint (circle-dot) and gasket
# (record-vinyl) replace four duplicates (pump-soap, coffee-pot,
# mug-saucer, brush). Trackers still storing a retired icon name keep
# rendering it, and editing them no longer risks swapping it for the
# fallback. Pure UI pass; no write-behavior changes.
#
# Pass 16 (v0.15.0): consolidation + button standard. Every tracker
# (built-in or custom) can be edited -- name, threshold, icon; the
# counting unit stays locked -- and hidden (at most 6 hidden at once,
# matching the 6 restore chips). Built-ins still cannot be deleted;
# Hide is their reversible retirement, protecting the auto-record,
# burr-offset and water-meter wiring. Delete (customs only) moved off
# the Detail page into the Edit page behind the same two-step confirm.
# "Add Custom Tracker" is now "New Tracker" with a "Save" action. A
# written button standard (see MaintenanceTracker.tcl header) fixes
# placement, naming, style and confirmation for Back/Cancel/Done,
# Save/Confirm, Edit, Hide, Delete, Undo, Prev/Next.
#
# Pass 15 (v0.14.0): the custom-tracker icon picker doubles to 24
# glyphs in two rows of 12 (new row: water bottle, coffee pot, espresso
# cup, pressure gauge, scale, thermometer, screwdriver+wrench, brush,
# soap, calendar-check, bell, star -- all from the app's own FA6 Pro
# symbol table). Layout-only changes on the Add and Edit pages; no new
# write behavior of any kind.
#
# Pass 14 (v0.13.0): water tracking in millilitres. A new lifetime water
# meter (settings water_total_ml) accumulates ::de1(volume) -- the
# machine's own reported dispense total for each operation -- every time
# the machine leaves a water-drawing state (espresso, steam, hot water,
# flush, steam rinse, clean, descale), via the existing
# on_major_state_change listener. A new built-in "Water bottle" tracker
# (new unit `ml`, default 18900 ml = 5 US gal) counts the meter against
# a baseline stored in each record event: Record = fresh bottle
# attached, and its confirm page carries bottle-size steppers (the burr
# offset mechanism). The card shows used/size in litres and "About X L
# left". Custom trackers can also pick the ml unit (e.g. a water filter
# tracked by throughput). The meter only runs while the app runs; an
# armed/cleared flag guarantees a flow is never counted twice (a restart
# mid-flow misses that flow, never double-counts).
#
# Pass 13 (v0.12.0): the Rename button became Edit -- a custom
# tracker's Detail page now opens a full Edit page: name (prefilled
# entry), threshold (steppers scaled to the tracker's unit) and icon
# (the shared picker row). Save rewrites only label/threshold/icon;
# the event history, counting unit and id stay untouched. Built-ins
# keep their fixed names and glyphs. The only write remains the
# plugin's own settings.tdb per explicit tap.
#
# Pass 12 (v0.11.0): rename custom trackers (superseded by Pass 13's
# Edit page).
#
# Pass 11 (v0.10.0): per-item restore for hidden trackers. The Add
# page's Restore All button is replaced by one chip button per hidden
# tracker (its name on the face); tapping a chip restores exactly that
# tracker. No new write behavior: restoring only removes an id from
# hidden_ids in the plugin's own settings.tdb.
#
# Pass 10 (v0.9.0): "Service Bay" card redesign (owner's pick). Cards
# gain a state-tinted icon plate (glyphs from the app's own Font
# Awesome 6 Pro symbol table), an uppercase state word, a right-aligned
# counter, and a segmented wear bar with the amber threshold ticked;
# the card list sorts worst-first. Custom trackers pick their icon on
# the Add page (new `icon` field, default wrench). Rendering degrades
# gracefully when the icon font or a symbol is unavailable. No new
# write behavior of any kind.
#
# Pass 9 (v0.8.0): hide/restore built-in trackers + v0.7.1 stepper-label
# fix. Built-in trackers can be hidden from their Detail page (single
# tap, non-destructive: the item dict, history and offset stay in
# settings; hidden items leave the cards AND the status rollup) and all
# restored at once from the Add page. Burr install starts hidden by a
# one-shot migration (owner decision: burrs last ~30k shots, not routine
# maintenance; its fresh-install threshold is now 30000). The v0.7.1
# fix: the Add page's threshold stepper buttons are created with real
# initial labels -- a dbutton created with -label "" never gets a label
# sub-item (dui.tcl:10227), so the later per-unit relabel had nothing
# to configure and the buttons rendered blank.
#
# Pass 8 (v0.7.0): custom trackers. Users can add their own named
# trackers (e.g. a second grinder's burr clean) with a days or shots
# threshold; custom trackers use the same card list, Record/Confirm,
# event log, Detail and Undo mechanisms as the built-ins, and can be
# deleted again from their Detail page after a two-tap confirm (the
# removed dict is kept in settings as `last_deleted_custom`). Built-in
# items can never be deleted. Shot-unit custom trackers count all shots
# -- the shot database cannot tell grinders apart.
#
# Pass 7 (v0.6.0): auto-recording. A second silent listener
# (on_major_state_change) watches the machine enter and leave its Clean
# and Descale states -- which after_flow_complete can NEVER report, since
# is_flow_state excludes them (de1app-core/de1_de1.tcl:435-441) -- and
# appends a `source auto` event when a cycle ran long enough to be real:
# Clean >= 90s -> backflush (the firmware's CleanSoak alone is 60s),
# Descale >= 300s -> descale. A cleaning-profile espresso run (blind-
# basket backflush, beverage_type "cleaning") >= 15s also records a
# backflush. Aborted cycles fall under the thresholds and never count.
# Undo works on auto events exactly as on manual ones. A settings toggle
# (auto_record) turns the whole feature off.
#
# Safety status of this version (v0.13.0):
# - The water meter adds ONE new automatic write: the plugin's own
#   settings.tdb is saved when a flow/cycle completes (the same
#   save_settings path auto-record already uses). Nothing else changed.
#
# Safety status (carried forward):
# - SDB access is READ-ONLY: the plugin opens its own sqlite3 handle with
#   -readonly true and issues only SELECT COUNT queries. No INSERT, UPDATE,
#   DELETE, ALTER, DROP, CREATE, VACUUM, or REINDEX anywhere.
# - NO history/ or history_v2/ access of any kind exists.
# - NO popups or automatic UI triggers. Two silent event listeners:
#   after_flow_complete (cache invalidation + cleaning-profile backflush
#   detection) and on_major_state_change (Clean/Descale cycle detection).
#   Neither ever draws anything.
# - Writes remain confined to the plugin's own settings.tdb via the
#   app's `plugins save_settings`: after an explicit user tap (Confirm /
#   Confirm Undo / Add Tracker / Yes, Delete Tracker), or when a real
#   maintenance cycle is auto-detected (one `source auto` event per
#   completed cycle, visible and undoable on the Detail page, disabled
#   by the `auto_record` setting).
# - The ONE destructive capability of this version is deleting a CUSTOM
#   tracker (user-created data inside settings.tdb only): two-tap
#   confirm on its Detail page, and the removed dict is escrowed in
#   settings(last_deleted_custom). Built-in items, SDB and history files
#   can never be deleted or altered.
#

package require Tcl 8.5

set plugin_name "MaintenanceTracker"

namespace eval ::plugins::MaintenanceTracker {
    variable author      "Blastize"
    variable contact     "n/a"
    # Bare number, no "v" prefix (ShotHistoryEditor v0.6.4 lesson: the
    # startup log message prepends one).
    variable version     "0.29.1"
    variable name        "Maintenance Tracker"
    variable description "Tracks machine maintenance (backflush, descale, gasket, burrs, water filter, water bottle level, plus your own custom trackers) from user-recorded events and the machine's own dispense reports. Read-only by design; writes only its own settings file."

    # ---- Settings defaults ----
    # Each key is set only if missing, because the plugin framework may have
    # already created this array before this file is sourced (GrindAdvisor
    # manifest pattern). Item values are Tcl dicts; `last_done` is Unix epoch
    # seconds, 0 = never recorded. `unit` says what the threshold counts.
    variable settings
    foreach {__k __v} {
        settings_version 1
        amber_fraction   0.8
        item_backflush     {last_done 0 note {} threshold 30   unit shots}
        item_descale       {last_done 0 note {} threshold 90   unit days}
        item_group_gasket  {last_done 0 note {} threshold 365  unit days}
        item_burr_clean    {last_done 0 note {} threshold 400  unit shots}
        item_burr_install  {last_done 0 note {} threshold 30000 unit shots pre_sdb_offset 0}
        item_water_filter  {last_done 0 note {} threshold 60   unit days}
        item_water_bottle  {last_done 0 note {} threshold 18900 unit ml}
        water_total_ml      0
        theme               light
        custom_ids          {}
        custom_next         1
        last_deleted_custom {}
        hidden_ids          {}
    } {
        if {![info exists settings($__k)]} { set settings($__k) $__v }
    }
    unset -nocomplain __k __v

    # ---- Runtime state ----
    variable hooked 0

    # Directory this manifest lives in (used to load the implementation).
    variable plugin_dir [file dirname [info script]]
}

# Load the implementation that sits next to this manifest.
if {[file exists [file join $::plugins::MaintenanceTracker::plugin_dir MaintenanceTracker.tcl]]} {
    source [file join $::plugins::MaintenanceTracker::plugin_dir MaintenanceTracker.tcl]
}

# Called by the plugin framework. Return the name of a settings page.
proc ::plugins::MaintenanceTracker::preload {} {
    return [preload_pages]
}

# Called by the framework when the plugin is enabled / on startup.
proc ::plugins::MaintenanceTracker::main {} {
    variable hooked
    catch { plugins load_settings MaintenanceTracker }
    apply_defaults
    # Two silent listeners (registered together under one guard; if the
    # listener API is missing on some build, the cache TTL still
    # refreshes counts on its own and auto-record simply stays inert):
    # - after_flow_complete (the same event the core uses to save shot
    #   history, de1app-core/vars.tcl:3440): cache invalidation plus the
    #   cleaning-profile backflush check (an espresso-state flow IS
    #   reported here).
    # - on_major_state_change: Clean/Descale cycle detection -- those are
    #   NOT flow states (de1app-core/de1_de1.tcl:435-441), so
    #   after_flow_complete never fires for them.
    # Neither callback ever draws UI.
    if {!$hooked} {
        catch {
            ::de1::event::listener::after_flow_complete_add \
                ::plugins::MaintenanceTracker::_on_flow_complete
            ::de1::event::listener::on_major_state_change_add \
                ::plugins::MaintenanceTracker::_on_state_change
            set hooked 1
        }
    }
    # v0.27.0: a switch-back left pending by an app restart comes back
    # once the profile and the connection have settled.
    after 20000 ::plugins::MaintenanceTracker::_resume_pending_run
    catch { msg "MaintenanceTracker: started v$::plugins::MaintenanceTracker::version (Pass 35: remove a chosen history record; GHC cup; step editor; links to a profile or the app's Descale / Clean, SDB read-only)" }
    return
}

proc ::plugins::MaintenanceTracker::save_settings {} {
    catch { plugins save_settings MaintenanceTracker }
}
