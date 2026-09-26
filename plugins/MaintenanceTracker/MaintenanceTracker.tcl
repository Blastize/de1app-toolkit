# ===========================================================================
# Maintenance Tracker -- implementation
#
# Pass 22 (v0.21.0): auto choice at creation + auto-count tags (owner
# follow-ups on Pass 21). The Add page gained an auto-source toggle in
# its top-right header slot ("Auto: off / Clean cycle / Descale
# cycle"; the page body is full, and the mode-button slot is the
# design system's place for exactly this kind of choice) -- add_save
# stores the pick. The card tag now distinguishes the two kinds of
# automation: AUTO-RECORD (auto_src resets the tracker on a detected
# cycle) vs AUTO-COUNT (shots/ml counters climb by themselves but
# recording stays manual -- the owner's ml water tracker looked
# "manual" despite metering itself); _item_auto_kind decides, the
# Detail page spells it out ("Counts automatically: all water
# dispensed"). Also: the Edit page's auto_toggle joined the theme
# restyle list (v0.20.0 gap). No new write behavior.
#
# Pass 21 (v0.20.0): relative time + per-tracker auto sources. The
# "Last done" line now shows "(just now / N minutes / N hours / N days
# ago)" via _fmt_ago instead of always days. Every tracker dict gained
# `auto_src` ("" / clean / descale): the cycle detectors dispatch
# through _record_auto_src to ALL subscribed trackers instead of the
# previously hardwired backflush/descale ids (a one-time migration in
# apply_defaults reproduces the old wiring, so behavior is unchanged
# until the user edits it). The Edit page's new "Auto-record" row
# cycles off -> Clean cycle -> Descale cycle for ANY tracker; cards
# wear an accent "AUTO" tag under the counter, the Detail page names
# the source, Diagnostics shows per-source subscriber counts. No new
# write behavior: the same settings.tdb save paths as v0.6.0.
#
# Pass 20 (v0.19.0): dark mode. Every non-state color the plugin
# paints now flows from _apply_palette (light/dark values per
# settings(theme); state tints recompute automatically via the blend
# onto the card color). A sun/moon button top-right of the main page
# toggles instantly: _retheme_all repaints every page's static items
# by bare tag, the main page's refresh repaints its dynamics, and
# every other page repaints its dynamics in its own show-refresh.
# Deliberately theme-INdependent: ok/amber/red state colors and all
# button faces (dbutton compounds are not restyled at runtime).
# The choice persists in settings(theme).
#
# Pass 19 (v0.18.0): icon meaning + Detail header icon. The Add/Edit
# "Icon:" label now reads "Icon:  <name>" for the current selection
# (icon_labels table, updated inside _refresh_picker -- one item, no
# new layout zone). The Detail page gained the tracker's icon top-left
# as a state-tinted card-style plate (det_plate/det_icon/det_v*),
# rendered by _apply_item_icon -- the card refresh's icon swap factored
# into that shared helper.
#
# Pass 18 (v0.17.0): plugin-drawn vector icons. The FA font has no
# honest steam wand or flat gasket, so the picker's steam-wand and
# gasket-flat slots are now stroke drawings the plugin renders itself:
# round-capped canvas lines / hollow ovals in a 0..100 design box,
# scaled into L(vec_box_plate|pick) (sized via px2v to match the
# physical-px glyph sizes) and recolored per state exactly like the
# glyphs (lines via -fill, ovals via -outline; bare segment tags per
# the v0.6.2 rule). Card plates carry both vector icons born hidden
# (-initial_state hidden, the v0.10.1 no-flash rule) and refresh shows
# at most one, swapping the glyph dtext out. Owner picked the two
# designs from rendered mockups (spout-with-steam; ring squashed
# flat).
#
# Pass 17 (v0.16.0): required-meaning icons. Owner needed steam wand,
# drain pipe, ball joint and gasket; four duplicate picker slots (8,
# 14, 15, 20: pump-soap, coffee-pot, mug-saucer, brush) now carry
# wand, pipe-section, circle-dot and record-vinyl. Robustness fix in
# open_edit: the stored icon seeds the Edit page even when it is no
# longer a picker candidate, so an unrelated Save keeps a legacy icon
# instead of silently swapping it for the wrench fallback.
#
# Pass 16 (v0.15.0): consolidation + button standard. Every tracker is
# now editable (built-in dicts gained label/icon fields; "" label means
# the fixed default name) and hideable (hide_max 6 at once, the chip
# count); built-ins still cannot be deleted -- Hide is their reversible
# retirement (owner decision: deleting would lose auto-record / burr
# offset / water-meter wiring forever). Delete (customs only) moved
# from the Detail bar into the Edit page. "Add Custom Tracker" became
# "New Tracker".
#
# BUTTON STANDARD (applies to every page in this plugin):
# - Bottom-left = navigation, always safe: "Done" on the main page
#   (closes the tracker), "Back" on read-only sub-pages, "Cancel" on
#   form/confirm pages. While a destructive confirm is armed, this
#   button DISARMS first; leaving takes another tap.
# - Bottom-right = the page's single positive action, normal style:
#   "Save" on forms, "Confirm" on record pages. Never destructive.
# - Destructive actions (Undo, Delete) are red (mt_btn_danger), always
#   two-step: first tap arms with an explicit "Yes, ..." label plus a
#   message saying what the second tap does; any page show disarms
#   (stuck-flag rule). At least a button-width of empty canvas
#   separates red from safe buttons. Delete lives only inside Edit --
#   one deliberate level below Detail.
# - Edit = top-right header slot on Detail (the mode-button slot).
#   Hide = Detail bottom-center, normal style (reversible), disabled
#   with an explanatory grey note when hide_max trackers are hidden.
# - Prev/Next = paired top-right toolbar, disabled at the ends.
# - Buttons wear text labels, not icons: on a 60px touch target a word
#   is unambiguous; glyphs decorate cards and the picker only.
#
# Pass 15 (v0.14.0): 12 more picker icons. picker_icons doubles to 24
# and the shared _build_picker_row wraps at picker_cols (12) into two
# rows -- same cells, same tap mechanism, tags pick0..pick23. Every new
# name was verified against the app's FA6 Pro symbol table
# (de1app-core/dui.tcl:1346+). The Add page's validation message moved
# up beside the "Icon:" label (its old slot is the second row) and the
# hidden-tracker chips moved up to keep their clearances; the Edit
# page's note/error moved down. Pure UI -- no data or write changes.
#
# Pass 14 (v0.13.0): water-bottle tracking in millilitres. The DE1 reports
# its water draw in every ShotSample; the app integrates it into
# ::de1(volume), reset at the start of every water-drawing operation
# (de1app-core/de1_de1.tcl:572-595, machine.tcl:675-976) -- steam included
# (gui.tcl:3536 charts the same GroupFlow field during steam). The existing
# on_major_state_change listener harvests ::de1(volume) whenever the
# machine LEAVES a water-drawing state and accumulates it into
# settings(water_total_ml), an ever-growing meter. A new built-in
# `water_bottle` tracker (new unit `ml`) counts the meter against a
# baseline stored in each record event: Record = "fresh bottle attached",
# value = meter - newest event's baseline, so Undo restores the previous
# baseline through the existing events-are-truth design. An armed/cleared
# flag makes the harvest miss-never-double-count (the auto-record
# philosophy); per-flow reads are sanity-clamped.
#
# Pass 10 (v0.9.0): "Service Bay" card redesign (owner's pick of three
# mockups). Cards gain a state-tinted icon plate (glyphs from the app's
# own Font Awesome 6 Pro symbol table, dui.tcl:1346+, resolved via
# `dui symbol exists/get`), a segmented wear bar with the amber
# threshold ticked, an uppercase state word and a right-aligned counter;
# the list sorts worst-first so trouble is always on page one. The Add
# page gains an icon picker for custom trackers (`icon` field, default
# wrench). Everything is flat fills on proven mechanisms: rounded_rect
# polygons, plain canvas rects whose -fill reconfigures (the dot
# mechanism), dtext glyphs on physical-pixel fonts. No raw-canvas coords
# manipulation anywhere.
#
# Pass 8 (v0.7.0): custom trackers. Users with more than one grinder (or
# any gear the built-in six don't cover) can add their own named trackers
# -- label, days/shots unit, threshold -- which ride every existing
# mechanism unchanged (cards, Record/Confirm, event log, Detail, Undo;
# manual-record only until v0.20.0's auto_src). Custom trackers can
# be deleted from their Detail page (two-tap confirm; the deleted dict is
# kept in settings as `last_deleted_custom` so a mistake is recoverable
# by hand). Shot-unit custom counters count ALL shots -- the database
# cannot tell grinders apart -- which the Add page says out loud.
#
# Pass 7 (v0.6.0): auto-recording. on_major_state_change watches the
# machine's Clean/Descale cycles (not flow states -- after_flow_complete
# never sees them) and appends `source auto` events for real cycles;
# the flow-complete callback additionally detects cleaning-profile
# backflushes. Everything else (event log, Detail page, undo, counts,
# SQL, navigation) untouched from v0.5.0.
#
# Every mechanism in this file is copied from a proven source in this
# workspace rather than invented:
# - Layout/font system: ShotHistoryEditor v0.7.1 _init_layout (two scale
#   sources: virtual 2560x1600 for coordinates, physical screen for fonts;
#   ShotHistoryEditor.tcl:157-296).
# - Page background + aspect style with -theme default: ShotHistoryEditor
#   _page_bg / she_btn (BeanScanner v0.1.2 lesson; ShotHistoryEditor.tcl
#   :289-308).
# - Navigation: ShotHistoryEditor v0.5.3 open_page cascade +
#   _capture_return_page + _navigate_done (ShotHistoryEditor.tcl:356-440),
#   the same contract Lumen already relies on (skins/Lumen/skin.tcl:2656).
# ===========================================================================

namespace eval ::plugins::MaintenanceTracker {

    # The maintenance items, in display order. Each maps to a settings key
    # item_<id>. Labels are shown on the (future) status page; Pass 1 only
    # uses them to validate settings defaults.
    variable item_ids {backflush descale group_gasket burr_clean burr_install water_filter water_bottle}

    # v0.15.0: at most this many trackers hidden at once -- the restore
    # chips on the New Tracker page have exactly this many slots.
    variable hide_max 6

    # v0.7.0: user-created trackers live in settings(custom_ids), ordered,
    # each id shaped custom_<n> (n from the never-reused custom_next
    # counter, so a deleted tracker's settings key can never be revived by
    # a later add). Display order is always built-ins first, customs after.
    proc _is_custom_id {id} {
        return [string match "custom_*" $id]
    }

    proc _all_item_ids {} {
        variable item_ids
        variable settings
        set customs {}
        catch { set customs $settings(custom_ids) }
        return [concat $item_ids $customs]
    }

    # v0.8.0: built-in trackers can be hidden (settings(hidden_ids),
    # validated to built-in ids only -- customs are deleted instead).
    # Hidden items vanish from the cards AND from the status rollup, so
    # they can never light the skin's attention dot.
    proc _visible_item_ids {} {
        variable settings
        set hidden {}
        catch { set hidden $settings(hidden_ids) }
        set out {}
        foreach id [_all_item_ids] {
            if {$id ni $hidden} { lappend out $id }
        }
        return $out
    }

    # ------------------------------------------------------------------
    #  Settings
    # ------------------------------------------------------------------

    # v0.5.0: recompute an item's `last_done` from its event log (newest
    # event is LAST in the list). Every mutation goes through this, and
    # apply_defaults runs it as self-healing, so `last_done` can never
    # disagree with `events`. All counter/state logic keeps reading
    # `last_done` unchanged.
    proc _sync_last_done {d} {
        set events {}
        catch { set events [dict get $d events] }
        if {[llength $events] == 0} {
            dict set d last_done 0
            return $d
        }
        set ts 0
        catch { set ts [dict get [lindex $events end] ts] }
        if {![string is wide -strict $ts]} { set ts 0 }
        dict set d last_done $ts
        return $d
    }

    # v0.13.0: an ml-unit item's baseline is the water-meter reading
    # stored in its NEWEST record event (`ml` field). Deriving it from
    # the event log -- exactly like last_done -- means Undo restores the
    # previous bottle's baseline with no extra bookkeeping. Events
    # without an ml field (or an empty log) read as baseline 0.
    proc _ml_baseline {d} {
        set events {}
        catch { set events [dict get $d events] }
        if {[llength $events] == 0} { return 0 }
        set b 0
        catch { set b [dict get [lindex $events end] ml] }
        if {![string is double -strict $b] || $b < 0} { set b 0 }
        return $b
    }

    # Make sure every settings key exists and every item dict has every
    # field it should. `plugins load_settings` replaces the whole array
    # from settings.tdb, which may have been written by an older version.
    #
    # v0.5.0 migration (idempotent): an item dict without an `events` key
    # is a v0.4.x dict -- seed the log from its last_done (one manual
    # event, or an empty log if never recorded). `events` is deliberately
    # NOT in the defaults list below: the field-fill loop would plant an
    # empty log into old dicts before the seeding check could see them,
    # wiping a real last_done on the sync that follows.
    proc apply_defaults {} {
        variable settings
        variable item_ids
        if {![info exists settings(settings_version)]} { set settings(settings_version) 1 }
        if {![info exists settings(amber_fraction)]}   { set settings(amber_fraction) 0.8 }
        # v0.19.0: UI theme, toggled from the main page's sun/moon.
        if {![info exists settings(theme)] || $settings(theme) ni {light dark}} {
            set settings(theme) light
        }
        # v0.6.0 auto-record knobs. Thresholds are conservative floors that
        # separate a real cycle from an entered-and-aborted one: the
        # firmware's CleanSoak substate alone is a fixed 60s
        # (de1app-core/machine.tcl:630); descales run many minutes.
        if {![info exists settings(auto_record)]}            { set settings(auto_record) 1 }
        # v0.27.0: a pending switch-back ("" = none), see start_profile_run.
        if {![info exists settings(run_restore)]}            { set settings(run_restore) "" }
        if {![info exists settings(auto_clean_min_s)]}       { set settings(auto_clean_min_s) 90 }
        if {![info exists settings(auto_descale_min_s)]}     { set settings(auto_descale_min_s) 300 }
        if {![info exists settings(auto_bf_shot_min_s)]}     { set settings(auto_bf_shot_min_s) 15 }
        # v0.13.0: lifetime water meter (ml ever dispensed while the app
        # was running). Monotonic; ml-unit items count against per-event
        # baselines, so the meter itself is never reset.
        if {![info exists settings(water_total_ml)] \
                || ![string is double -strict $settings(water_total_ml)] \
                || $settings(water_total_ml) < 0} {
            set settings(water_total_ml) 0
        }
        # v0.15.0 (consolidation): built-in dicts carry `label` and
        # `icon` like customs do, so Edit works uniformly. label ""
        # means "use the fixed default name" (_item_label falls back);
        # icon defaults to the classic built-in glyph.
        # v0.20.0: `auto_src` names the cycle detector that auto-records
        # this tracker ("" = manual only). The migration reproduces the
        # previously hardwired wiring (Clean cycle -> backflush, Descale
        # cycle -> descale); the field-fill loop plants it into persisted
        # older dicts, and the Edit page can change it on ANY tracker.
        foreach {id defaults} {
            backflush     {last_done 0 note {} threshold 30   unit shots label {} icon grate-droplet auto_src clean}
            descale       {last_done 0 note {} threshold 90   unit days  label {} icon droplet-slash auto_src descale}
            group_gasket  {last_done 0 note {} threshold 365  unit days  label {} icon ring auto_src {}}
            burr_clean    {last_done 0 note {} threshold 400  unit shots label {} icon coffee-beans auto_src {}}
            burr_install  {last_done 0 note {} threshold 30000 unit shots pre_sdb_offset 0 label {} icon gears auto_src {}}
            water_filter  {last_done 0 note {} threshold 60   unit days  label {} icon filter auto_src {}}
            water_bottle  {last_done 0 note {} threshold 18900 unit ml   label {} icon tank-water auto_src {}}
        } {
            set key "item_$id"
            if {![info exists settings($key)] || [catch { dict size $settings($key) }]} {
                set settings($key) $defaults
            } else {
                # Fill in any field missing from a persisted older dict.
                foreach {f v} $defaults {
                    if {![dict exists $settings($key) $f]} {
                        dict set settings($key) $f $v
                    }
                }
            }
            # v0.4.x -> v0.5.0 event-log migration.
            if {![dict exists $settings($key) events]} {
                set ld [dict get $settings($key) last_done]
                if {[string is wide -strict $ld] && $ld > 0} {
                    dict set settings($key) events \
                        [list [dict create ts $ld source manual note ""]]
                } else {
                    dict set settings($key) events {}
                }
            }
            if {[dict get $settings($key) auto_src] ni {{} clean descale}} {
                dict set settings($key) auto_src {}
            }
            set settings($key) [_sync_last_done $settings($key)]
        }

        # v0.7.0: custom trackers. Validate the id list (well-formed,
        # no leading zeros -- they would read as octal downstream -- and
        # no duplicates), then give every listed item a complete dict,
        # with the same events-seeding rule as the built-ins above.
        if {![info exists settings(custom_ids)]}          { set settings(custom_ids) {} }
        if {![info exists settings(custom_next)]}         { set settings(custom_next) 1 }
        if {![info exists settings(last_deleted_custom)]} { set settings(last_deleted_custom) {} }
        set valid {}
        foreach id $settings(custom_ids) {
            if {[regexp {^custom_[1-9]\d*$} $id] && [lsearch -exact $valid $id] < 0} {
                lappend valid $id
            }
        }
        set settings(custom_ids) $valid
        if {![string is wide -strict $settings(custom_next)] || $settings(custom_next) < 1} {
            set settings(custom_next) 1
        }
        set maxn 0
        foreach id $settings(custom_ids) {
            regexp {^custom_(\d+)$} $id -> n
            if {$n > $maxn} { set maxn $n }
            set key "item_$id"
            set cdefaults {label {} last_done 0 note {} threshold 60 unit days icon wrench auto_src {}}
            if {![info exists settings($key)] || [catch { dict size $settings($key) }]} {
                set settings($key) $cdefaults
            } else {
                foreach {f v} $cdefaults {
                    if {![dict exists $settings($key) $f]} {
                        dict set settings($key) $f $v
                    }
                }
            }
            if {![dict exists $settings($key) events]} {
                set ld [dict get $settings($key) last_done]
                if {[string is wide -strict $ld] && $ld > 0} {
                    dict set settings($key) events \
                        [list [dict create ts $ld source manual note ""]]
                } else {
                    dict set settings($key) events {}
                }
            }
            if {[dict get $settings($key) unit] ni {days shots ml}} {
                dict set settings($key) unit days
            }
            if {[dict get $settings($key) auto_src] ni {{} clean descale}} {
                dict set settings($key) auto_src {}
            }
            if {[string trim [dict get $settings($key) label]] eq ""} {
                dict set settings($key) label $id
            }
            set settings($key) [_sync_last_done $settings($key)]
        }
        if {$settings(custom_next) <= $maxn} {
            set settings(custom_next) [expr {$maxn + 1}]
        }

        # v0.8.0: hidden trackers; v0.15.0: ANY existing tracker may hide
        # (built-in or custom), at most hide_max at once (the restore
        # chips have that many slots). Duplicates and unknown ids drop;
        # overflow truncates oldest-first order preserved.
        variable hide_max
        if {![info exists settings(hidden_ids)]} { set settings(hidden_ids) {} }
        set vh {}
        foreach id $settings(hidden_ids) {
            if {($id in $item_ids || $id in $settings(custom_ids)) \
                    && [lsearch -exact $vh $id] < 0} { lappend vh $id }
        }
        if {[llength $vh] > $hide_max} { set vh [lrange $vh 0 [expr {$hide_max - 1}]] }
        set settings(hidden_ids) $vh
        # One-shot migration (owner decision, Pass 9): burr install is
        # not routine maintenance -- burrs last ~30k shots -- so it
        # starts hidden. The flag makes this run exactly once, so a
        # deliberate later un-hide sticks across restarts.
        if {![info exists settings(hide_burr_done)]} {
            set settings(hide_burr_done) 1
            if {"burr_install" ni $settings(hidden_ids)} {
                lappend settings(hidden_ids) burr_install
            }
        }
    }

    # ------------------------------------------------------------------
    #  Read-only SDB access (Pass 2)
    #
    #  Own handle, opened with -readonly true (ShotHistoryEditor
    #  _open_ro_db pattern, ShotHistoryEditor.tcl:1260-1281, with
    #  GrindAdvisor's fallback for sqlite3 builds without -readonly,
    #  GrindAdvisor.tcl:2227-2236). Opened per refresh, closed right
    #  after. Only SELECT COUNT statements are ever issued.
    #
    #  Design rule (Pass 0): counts use RAW shot-table rows -- no
    #  `removed=0` filter and no reading of ShotHistoryEditor's trash
    #  manifest. A soft-deleted shot still physically ran water and
    #  coffee through the machine, so it still counts for wear.
    # ------------------------------------------------------------------

    variable db_handle "::plugins::MaintenanceTracker::sdb"
    variable last_db_error ""

    # Defensive exclusion filter: espresso-state runs of cleaning-type
    # profiles (blind-basket backflush etc.) do reach SDB when the
    # history_exclusion_filter plugin is disabled, and old rows predate
    # its enablement. These lists are surfaced verbatim on Diagnostics.
    variable exclude_bev_types  {cleaning calibration test testing}
    variable exclude_title_kw   {rinse flush backflush clean descale calibrat}

    proc _homedir {} {
        if {[llength [info commands homedir]]} {
            return [homedir]
        }
        variable plugin_dir
        return [file dirname [file dirname $plugin_dir]]
    }

    proc _plugins_dir {} {
        if {[llength [info commands plugin_directory]]} {
            set pd [plugin_directory]
            if {[file pathtype $pd] eq "absolute"} { return $pd }
            return [file join [_homedir] $pd]
        }
        variable plugin_dir
        return [file dirname $plugin_dir]
    }

    proc sdb_path {} {
        set candidates [list \
            [file join [_plugins_dir] SDB shots.db] \
            [file join [_homedir] plugins SDB shots.db]]
        foreach p $candidates {
            if {[file isfile $p]} { return $p }
        }
        return [lindex $candidates 0]
    }

    # Pass 25: idempotent. The handle is closed after every refresh and
    # again before every open, so the old bare `catch { $db_handle close }`
    # failed on every refresh; catch swallows the error but leaves
    # $::errorInfo dirty, and the core BLE runner prints $::errorInfo
    # (de1_comms.tcl:120) -- "invalid command name ...::sdb" surfaced as
    # "BLE error info". Closing only an existing command raises nothing.
    proc _close_db {} {
        variable db_handle
        if {[llength [info commands $db_handle]]} {
            if {[catch { $db_handle close } err]} {
                catch { msg "MaintenanceTracker: SDB close failed: $err" }
            }
        }
    }

    proc _open_ro_db {} {
        variable db_handle
        variable last_db_error
        set last_db_error ""
        set path [sdb_path]

        if {![file isfile $path]} {
            set last_db_error "SDB database not found: $path"
            return ""
        }
        if {![llength [info commands sqlite3]]} {
            catch { package require sqlite3 }
        }
        if {![llength [info commands sqlite3]]} {
            set last_db_error "sqlite3 package is not available."
            return ""
        }

        _close_db
        # Prefer a true read-only handle so we can never lock or alter SDB.
        if {![catch { sqlite3 $db_handle $path -readonly true }]} { return $db_handle }
        # Older sqlite3 builds without -readonly: open normally, still SELECT-only.
        if {![catch { sqlite3 $db_handle $path }]} { return $db_handle }
        set last_db_error "Could not open SDB read-only."
        return ""
    }

    # --- Dynamic schema detection (never assume a fixed schema) ---

    proc _q {name} {
        set escaped [string map [list "\"" "\"\""] $name]
        return "\"$escaped\""
    }

    proc _tables {db} {
        set t {}
        catch {
            $db eval {SELECT name FROM sqlite_master
                      WHERE type = 'table' AND name NOT LIKE 'sqlite_%'} r {
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

    # Map logical fields -> real column names with ordered regex patterns
    # (GrindAdvisor _resolve_fields pattern, GrindAdvisor.tcl:2324). We only
    # need three: the shot timestamp (required), and the two optional
    # columns the exclusion filter can use.
    proc _resolve_columns {cols} {
        set result [dict create]
        foreach {field patterns} {
            clock    {^clock$ ^timestamp$ ^shot_clock$}
            bev_type {^beverage_type$ beverage}
            profile  {^profile_title$ ^profile$ profile.*title}
        } {
            foreach pat $patterns {
                foreach c $cols {
                    if {[regexp -nocase -- $pat $c]} {
                        dict set result $field $c
                        break
                    }
                }
                if {[dict exists $result $field]} { break }
            }
        }
        return $result
    }

    # Choose the shot table: prefer one literally named "shot" if it has a
    # clock column; otherwise the table with the most logical fields.
    proc _find_shot_table {db} {
        set best_table ""
        set best_fields {}
        set best_score -1
        foreach t [_tables $db] {
            set cols [_columns $db $t]
            if {[llength $cols] == 0} { continue }
            set f [_resolve_columns $cols]
            if {![dict exists $f clock]} { continue }
            set score [dict size $f]
            if {[string tolower $t] eq "shot"} { incr score 10 }
            if {$score > $best_score} {
                set best_score $score
                set best_table $t
                set best_fields $f
            }
        }
        return [list $best_table $best_fields]
    }

    # WHERE fragment (starting with " AND ...") excluding cleaning-type
    # rows, built ONLY from columns that actually exist. Keyword lists are
    # plugin constants, never user input, so inlining them is safe.
    #
    # v0.4.0: NO lower() anywhere. On this tablet's AndroWish SQLite build
    # lower() dies with "ICU error: u_strToLower(): link error" (seen live
    # on Diagnostics 2026-08-25), killing every filtered query while plain
    # COUNT worked. LIKE is case-insensitive for ASCII in SQLite by
    # default, so LIKE without wildcards is a case-insensitive equality
    # and LIKE '%kw%' a case-insensitive substring match -- everything the
    # filter needs, with no ICU involvement.
    proc _exclusion_sql {fields} {
        variable exclude_bev_types
        variable exclude_title_kw
        set ex ""
        if {[dict exists $fields bev_type]} {
            set c [_q [dict get $fields bev_type]]
            set neq {}
            foreach b $exclude_bev_types { lappend neq "$c NOT LIKE '$b'" }
            append ex " AND ($c IS NULL OR ([join $neq { AND }]))"
        }
        if {[dict exists $fields profile]} {
            set c [_q [dict get $fields profile]]
            foreach kw $exclude_title_kw {
                append ex " AND ($c IS NULL OR $c NOT LIKE '%$kw%')"
            }
        }
        return $ex
    }

    proc _count_since {db table fields since {use_filter 1}} {
        if {![string is wide -strict $since]} { set since 0 }
        set cc [_q [dict get $fields clock]]
        set sql "SELECT COUNT(*) FROM [_q $table] WHERE $cc > $since"
        if {$use_filter} { append sql [_exclusion_sql $fields] }
        return [$db onecolumn $sql]
    }

    # ------------------------------------------------------------------
    #  Status computation and cache
    #
    #  Lumen polls plugin status procs on a fast refresh tick
    #  (skins/Lumen/skin.tcl:856-859), so status_summary must serve from
    #  a cache. The cache is invalidated by the after-flow listener, by
    #  a TTL (days-based items advance without any event), and by the
    #  plugin's own pages on show.
    # ------------------------------------------------------------------

    variable status_cache {}
    variable status_cache_time 0
    variable status_dirty 1
    variable cache_ttl 600
    # Pass 23: detected shot table + fields, kept for the whole session
    # (unset again on any SDB read error, forcing re-detection).
    variable _schema_cache {}
    variable _pending_after ""

    # diag() is filled by every refresh and read by the Diagnostics page.
    variable diag
    array set diag {}

    proc _invalidate_status_cache {args} {
        variable status_dirty
        variable _pending_after
        set status_dirty 1
        # SDB syncs new shots on its own schedule, possibly after this
        # event fires -- re-invalidate once more a minute later so the
        # next poll after the sync picks the new row up.
        catch { after cancel $_pending_after }
        set _pending_after [after 60000 {
            set ::plugins::MaintenanceTracker::status_dirty 1
            set ::plugins::MaintenanceTracker::_pending_after ""
        }]
        return
    }

    # ------------------------------------------------------------------
    #  Auto-recording (Pass 7). Two detectors, both silent, both feeding
    #  the same append path as manual recording but with source `auto`:
    #
    #  1. Machine cycles: on_major_state_change reports entry into and
    #     exit from the DE1's own Clean (18) and Descale (10) states
    #     (state tables at de1app-core/machine.tcl:522-560; the firmware
    #     walks the substate program itself). Duration = exit event_time
    #     minus enter event_time (epoch seconds, binary.tcl:1472,
    #     dict shape binary.tcl:1490-1496); a cycle shorter than the
    #     threshold was aborted and never counts. The enter stamp lives
    #     only in memory: a restart mid-cycle misses that one cycle,
    #     never double-counts it.
    #
    #  2. Cleaning-profile backflush: a blind-basket backflush run as an
    #     espresso profile IS a flow, so it arrives via
    #     after_flow_complete. Detected by ::settings(beverage_type)
    #     "cleaning" (the profile field history_exclusion_filter keys
    #     on) plus a minimum duration from the same state-change stamps.
    # ------------------------------------------------------------------

    variable _cycle_state ""
    variable _cycle_enter 0
    variable _espresso_enter 0
    # v0.24.0: the profile loaded when the Espresso state began -- the
    # one that actually ran, even if something reloads another profile
    # before after_flow_complete fires.
    variable _espresso_profile ""

    # Append one auto event, with the same cap/sync/save path as manual
    # recording. Rejects a duplicate within 30s of the item's newest
    # event (belt-and-braces against any double-fired exit).
    proc _record_auto {id now} {
        variable settings
        if {![info exists settings(auto_record)] || !$settings(auto_record)} { return 0 }
        if {![info exists settings(item_$id)]} { return 0 }
        set d $settings(item_$id)
        set events {}
        catch { set events [dict get $d events] }
        if {[llength $events] > 0} {
            set last_ts 0
            catch { set last_ts [dict get [lindex $events end] ts] }
            if {[string is wide -strict $last_ts] && $now - $last_ts < 30} { return 0 }
        }
        lappend events [dict create ts $now source auto note ""]
        if {[llength $events] > 20} { set events [lrange $events end-19 end] }
        dict set d events $events
        set d [_sync_last_done $d]
        set settings(item_$id) $d
        save_settings
        catch { msg -NOTICE "MaintenanceTracker: auto-recorded '$id' (cycle detected)" }
        _invalidate_status_cache
        return 1
    }

    # v0.20.0: dispatch one detected cycle to EVERY tracker whose
    # auto_src subscribes to it (previously hardwired backflush/descale).
    # Hidden trackers still record -- hiding only affects display, and
    # their history must stay truthful for when they are restored.
    proc _record_auto_src {src now} {
        variable settings
        foreach id [_all_item_ids] {
            if {![info exists settings(item_$id)]} { continue }
            set a ""
            catch { set a [dict get $settings(item_$id) auto_src] }
            if {$a eq $src} { _record_auto $id $now }
        }
    }

    # v0.24.0 (Pass 29): a finished cleaning-PROFILE run records the
    # trackers linked to that exact profile, and only those (owner: the
    # Powder backflush recorded "Backflush - Water", because every
    # cleaning run went to all Clean-cycle subscribers and the link was
    # never consulted). A linked tracker records even with its Auto
    # source off -- linking a cleaning profile names the runs it tracks.
    # No tracker linked to the profile -> the v0.20.0 rule unchanged:
    # every Clean-cycle subscriber records.
    proc _record_auto_profile {fn now} {
        set hits {}
        if {$fn ne ""} {
            foreach id [_all_item_ids] {
                set prof [_item_profile $id]
                if {$prof ne "" && [string equal -nocase [lindex $prof 0] $fn]} {
                    lappend hits $id
                }
            }
        }
        if {[llength $hits] == 0} {
            _record_auto_src clean $now
            return
        }
        catch { msg -INFO "MaintenanceTracker: cleaning profile '$fn' -> linked tracker(s) $hits" }
        foreach id $hits { _record_auto $id $now }
    }

    # v0.24.0: beverage type of a profile file, read-only and cached for
    # the session ("" when the file is missing or unreadable). Parsed
    # the way the core's load_settings_vars reads it (vars.tcl:3217).
    variable _prof_bev_cache [dict create]
    proc _profile_bev {fn} {
        variable _prof_bev_cache
        if {$fn eq ""} { return "" }
        if {[dict exists $_prof_bev_cache $fn]} { return [dict get $_prof_bev_cache $fn] }
        # The core's homedir is where select_profile looks (vars.tcl:2940);
        # without it (offline) there is nothing to read -- and no caching.
        if {![llength [info commands ::homedir]]} { return "" }
        set bev ""
        set path [file join [::homedir] profiles "${fn}.tcl"]
        if {[file isfile $path] && [file readable $path] \
                && [llength [info commands ::read_binary_file]]} {
            if {[catch {
                set data [encoding convertfrom utf-8 [::read_binary_file $path]]
                if {[string is list $data] && [llength $data] % 2 == 0} {
                    foreach {k v} $data {
                        if {$k eq "beverage_type"} { set bev [string tolower [string trim $v]] }
                    }
                }
            } err]} {
                catch { msg -WARN "MaintenanceTracker: could not read profile '$fn': $err" }
                set bev ""
            }
        }
        dict set _prof_bev_cache $fn $bev
        return $bev
    }

    # v0.24.1 (Pass 30): 1 when `profiles/<fn>.tcl` exists -- the exact
    # path select_profile loads (vars.tcl:2940) -- 0 when it does not,
    # "" when unknown (no core homedir: offline only). Checked BEFORE
    # select_profile: the core resets part of ::settings before its own
    # file check, and Graphical_Flow_Calibrator's wrapper (its
    # plugin.tcl:456) drops the core's "-1", so the return value alone
    # cannot be trusted on a real tablet.
    proc _profile_file_exists {fn} {
        if {$fn eq ""} { return 0 }
        if {![llength [info commands ::homedir]]} { return "" }
        return [file isfile [file join [::homedir] profiles "${fn}.tcl"]]
    }

    # v0.24.0: {filename title} when the tracker links a CLEANING
    # profile (so its runs auto-record it), else "".
    proc _item_cleaning_profile {id} {
        set prof [_item_profile $id]
        if {$prof eq ""} { return "" }
        if {[_profile_bev [lindex $prof 0]] ne "cleaning"} { return "" }
        return $prof
    }

    # ------------------------------------------------------------------
    #  Water meter (Pass 14). ::de1(volume) integrates the machine's
    #  reported flow for the CURRENT operation (de1_de1.tcl:572-595) and
    #  is reset only at the START of the next water-drawing operation
    #  (machine.tcl:675-976), so at the moment the machine leaves a
    #  water-drawing state it still holds that operation's total ml.
    #  Steam reports its draw in the same field (gui.tcl:3536). The
    #  armed/cleared flag mirrors auto-record's philosophy: a duplicate
    #  exit event or an app restart mid-flow can only ever MISS water,
    #  never count it twice.
    # ------------------------------------------------------------------

    variable water_states {Espresso Steam HotWater HotWaterRinse SteamRinse Clean Descale}
    variable _water_active 0

    proc _harvest_water {} {
        variable settings
        variable _water_active
        if {!$_water_active} { return }
        set _water_active 0
        set vol 0
        catch { set vol $::de1(volume) }
        if {![string is double -strict $vol] || $vol <= 0} { return }
        if {$vol > 5000} {
            catch { msg -WARN "MaintenanceTracker: ignoring implausible flow volume ${vol}ml" }
            return
        }
        if {![info exists settings(water_total_ml)] \
                || ![string is double -strict $settings(water_total_ml)]} {
            set settings(water_total_ml) 0
        }
        set settings(water_total_ml) \
            [expr {round(($settings(water_total_ml) + $vol) * 10.0) / 10.0}]
        save_settings
        _invalidate_status_cache
        catch { msg -INFO "MaintenanceTracker: water +[format %.0f $vol]ml (meter [format %.0f $settings(water_total_ml)]ml)" }
    }

    # on_major_state_change callback. Never throws (a listener error
    # would surface in the core's event dispatch); every read is guarded.
    proc _on_state_change {event_dict} {
        variable _cycle_state
        variable _cycle_enter
        variable _espresso_enter
        variable _espresso_profile
        variable settings
        variable water_states
        variable _water_active
        if {[catch {
            set this ""
            set prev ""
            set now [clock seconds]
            catch { set this [dict get $event_dict this_state] }
            catch { set prev [dict get $event_dict previous_state] }
            catch {
                set t [dict get $event_dict event_time]
                if {[string is double -strict $t] && $t > 0} { set now [expr {int($t)}] }
            }

            # Water meter (Pass 14): harvest the finished operation's
            # ::de1(volume) when leaving a water-drawing state, then
            # re-arm if the new state draws water too. The flag was set
            # on entry, so a duplicate event finds it cleared. On a
            # direct water->water hop the new operation's start may have
            # already reset ::de1(volume) -- that under-counts one flow,
            # never double-counts (the machine passes Idle in practice).
            if {$_water_active && $prev in $water_states} {
                _harvest_water
            }
            if {$this in $water_states} {
                set _water_active 1
            } else {
                set _water_active 0
            }

            # Cycle exit first (state can in principle hop cycle->cycle).
            if {$_cycle_state ne "" && $this ne $_cycle_state} {
                set dur [expr {$now - $_cycle_enter}]
                set which $_cycle_state
                set _cycle_state ""
                set _cycle_enter 0
                if {$which eq "Clean" && $dur >= $settings(auto_clean_min_s)} {
                    _record_auto_src clean $now
                } elseif {$which eq "Descale" && $dur >= $settings(auto_descale_min_s)} {
                    _record_auto_src descale $now
                }
            }
            # Cycle entry (a re-enter overwrites any stale stamp).
            if {$this in {Clean Descale}} {
                set _cycle_state $this
                set _cycle_enter $now
            }
            # v0.27.0: the profile-run switch-back watches Espresso too.
            _run_on_state $this $prev
            # Espresso timing for the cleaning-profile backflush check,
            # measured here and consumed by _on_flow_complete.
            if {$this eq "Espresso"} {
                set _espresso_enter $now
                set _espresso_profile ""
                catch { set _espresso_profile [string trim $::settings(profile_filename)] }
            }
        } err]} {
            catch { msg "MaintenanceTracker: state-change handler error: $err" }
        }
        return
    }

    # after_flow_complete callback: the v0.2.0 cache invalidation, plus
    # the cleaning-profile backflush check. No `return` inside the catch
    # body -- catch reports TCL_RETURN as a non-zero code and the guard
    # would log a phantom error -- so the checks nest instead.
    proc _on_flow_complete {args} {
        variable _espresso_enter
        variable _espresso_profile
        variable settings
        _invalidate_status_cache
        if {[catch {
            set want [expr {[info exists settings(auto_record)] && $settings(auto_record)}]
            set prev ""
            catch { set prev [dict get [lindex $args 0] previous_state] }
            set bev ""
            catch { set bev [string tolower $::settings(beverage_type)] }
            if {$want && $prev eq "Espresso" && $bev eq "cleaning" \
                    && [string is wide -strict $_espresso_enter] && $_espresso_enter > 0} {
                set dur [expr {[clock seconds] - $_espresso_enter}]
                set _espresso_enter 0
                set fn $_espresso_profile
                set _espresso_profile ""
                if {$fn eq ""} {
                    catch { set fn [string trim $::settings(profile_filename)] }
                }
                if {$dur >= $settings(auto_bf_shot_min_s)} {
                    # v0.24.0: trackers linked to THIS profile record;
                    # none linked -> every Clean-cycle subscriber, as
                    # before (_record_auto_profile).
                    _record_auto_profile $fn [clock seconds]
                }
            }
        } err]} {
            catch { msg "MaintenanceTracker: flow-complete handler error: $err" }
        }
        # v0.27.0: AFTER the auto-record above (it reads the cleaning
        # profile's beverage_type) -- schedule the switch-back.
        if {[catch { _run_on_flow_complete } err]} {
            catch { msg "MaintenanceTracker: switch-back scheduling error: $err" }
        }
        return
    }

    proc _worst_state {states} {
        set worst ok
        foreach s $states {
            if {$s eq "red"} { return red }
            if {$s eq "amber"} { set worst amber }
        }
        return $worst
    }

    proc _state_for {value threshold amber_fraction} {
        if {![string is double -strict $threshold] || $threshold <= 0} { return ok }
        if {![string is double -strict $value]} { return unknown }
        if {$value >= $threshold} { return red }
        if {$value >= $amber_fraction * $threshold} { return amber }
        return ok
    }

    # Full recompute. Always returns a status dict and never throws; every
    # failure path lands in an `ok 0` dict or a per-item `unknown` state.
    proc _refresh_status {} {
        variable settings
        variable diag
        variable last_db_error
        variable status_cache
        variable status_cache_time
        variable status_dirty

        set now [clock seconds]
        array unset diag
        array set diag {}
        set diag(refreshed) $now
        set diag(sdb_path) [sdb_path]

        # -- Read-only DB pass: totals + per-item counts --
        set sdb_ok 0
        set sdb_error ""
        set table ""
        set fields {}
        set total_raw ""
        set total_counted ""
        array unset _counts
        array set _counts {}

        # v0.4.0: the exclusion filter failing (e.g. an exotic SQLite
        # build) must not take the counters down with it -- fall back to
        # unfiltered counts and say so on Diagnostics.
        set filter_ok 1
        set filter_error ""

        set db [_open_ro_db]
        if {$db eq ""} {
            set sdb_error $last_db_error
        } else {
            # Pass 23: schema detection (sqlite_master walk + one PRAGMA
            # per table) runs once per app session, not once per refresh
            # -- the schema cannot change under a read-only browser. On
            # any read error the cache is dropped so the next refresh
            # re-detects from scratch.
            variable _schema_cache
            if {[catch {
                if {[info exists _schema_cache] && [llength $_schema_cache] == 2} {
                    lassign $_schema_cache table fields
                } else {
                    lassign [_find_shot_table $db] table fields
                }
                if {$table eq ""} {
                    error "no table with a shot clock column found"
                }
                set total_raw [$db onecolumn "SELECT COUNT(*) FROM [_q $table]"]
                set sdb_ok 1
                set _schema_cache [list $table $fields]
            } err]} {
                set sdb_error "SDB read failed: $err"
                catch { unset _schema_cache }
            }
            if {$sdb_ok} {
                if {[catch {
                    set total_counted [$db onecolumn \
                        "SELECT COUNT(*) FROM [_q $table] WHERE 1=1[_exclusion_sql $fields]"]
                } err]} {
                    set filter_ok 0
                    set filter_error $err
                    set total_counted $total_raw
                    catch { msg "MaintenanceTracker: exclusion filter unavailable, counting unfiltered: $err" }
                }
                foreach id [_visible_item_ids] {
                    if {![info exists settings(item_$id)]} { continue }
                    set d $settings(item_$id)
                    if {[dict get $d unit] eq "shots" && [dict get $d last_done] > 0} {
                        if {[catch {
                            set _counts($id) [_count_since $db $table $fields \
                                [dict get $d last_done] $filter_ok]
                        } err]} {
                            catch { msg "MaintenanceTracker: count for $id failed: $err" }
                        }
                    }
                }
            }
            _close_db
        }

        set diag(sdb_ok) $sdb_ok
        set diag(sdb_error) $sdb_error
        set diag(filter_ok) $filter_ok
        set diag(filter_error) $filter_error
        set diag(table) $table
        set diag(fields) $fields
        set diag(total_raw) $total_raw
        set diag(total_counted) $total_counted
        if {$sdb_ok && $filter_ok && [string is wide -strict $total_raw] && [string is wide -strict $total_counted]} {
            set diag(total_excluded) [expr {$total_raw - $total_counted}]
        } else {
            set diag(total_excluded) ""
        }

        # -- Per-item states (days items need no DB at all) --
        set amber_fraction 0.8
        catch { set amber_fraction $settings(amber_fraction) }
        set items [dict create]
        set known_states {}
        foreach id [_visible_item_ids] {
            if {![info exists settings(item_$id)]} { continue }
            set d $settings(item_$id)
            set last_done [dict get $d last_done]
            set threshold [dict get $d threshold]
            set unit [dict get $d unit]
            set entry [dict create last_done $last_done threshold $threshold unit $unit]

            if {![string is wide -strict $last_done] || $last_done <= 0} {
                dict set entry state unset
                dict set items $id $entry
                continue
            }

            set days_since [expr {int(($now - $last_done) / 86400)}]
            dict set entry days_since $days_since

            if {$unit eq "days"} {
                set value $days_since
            } elseif {$unit eq "ml"} {
                # v0.13.0: meter minus the newest event's baseline.
                # Needs no database at all; never yields "unknown".
                set total 0
                catch {
                    if {[string is double -strict $settings(water_total_ml)]} {
                        set total $settings(water_total_ml)
                    }
                }
                set value [expr {int(round($total - [_ml_baseline $d]))}]
                if {$value < 0} { set value 0 }
                dict set entry ml_since $value
            } else {
                if {[info exists _counts($id)]} {
                    set value $_counts($id)
                    if {$id eq "burr_install" && [dict exists $d pre_sdb_offset] \
                            && [string is wide -strict [dict get $d pre_sdb_offset]]} {
                        set value [expr {$value + [dict get $d pre_sdb_offset]}]
                    }
                    dict set entry shots_since $value
                } else {
                    set value ""
                }
            }
            dict set entry value $value
            set state [_state_for $value $threshold $amber_fraction]
            dict set entry state $state
            if {$state in {ok amber red}} { lappend known_states $state }
            dict set items $id $entry
        }

        set status_cache [dict create \
            ok 1 \
            state [_worst_state $known_states] \
            sdb_ok $sdb_ok \
            generated $now \
            items $items]
        if {!$sdb_ok} {
            dict set status_cache sdb_error $sdb_error
        }
        set status_cache_time $now
        set status_dirty 0
        return $status_cache
    }

    # ------------------------------------------------------------------
    #  Public API (Lumen guarded-read convention: dict with an `ok` key,
    #  skins/Lumen/skin.tcl:856-892)
    # ------------------------------------------------------------------

    proc status_summary {} {
        variable status_cache
        variable status_cache_time
        variable status_dirty
        variable cache_ttl
        if {!$status_dirty && [dict size $status_cache] > 0 \
                && [clock seconds] - $status_cache_time < $cache_ttl} {
            return $status_cache
        }
        if {[catch { set s [_refresh_status] } err]} {
            catch { msg "MaintenanceTracker: status refresh failed: $err" }
            return [dict create ok 0 error "MaintenanceTracker: $err"]
        }
        return $s
    }

    # Public page-open entry, same cascade as ShotHistoryEditor::open_page
    # (ShotHistoryEditor.tcl:356-365) / GrindAdvisor::open_settings_dialog
    # (GrindAdvisor.tcl:447-456), copied verbatim.
    proc open_page {page} {
        foreach cmd [list \
            [list dui page open_dialog $page] \
            [list dui page load $page] \
            [list dui page show $page]] {
            if {![catch { uplevel #0 $cmd }]} { return 1 }
        }
        catch { msg "MaintenanceTracker: could not open page $page" }
        return 0
    }

    # ------------------------------------------------------------------
    #  Navigation (ShotHistoryEditor v0.5.3 mechanism, copied verbatim;
    #  only the namespace/page prefix differs)
    # ------------------------------------------------------------------

    variable _settings_return_page ""

    proc _is_transient_name {name} {
        if {$name eq ""} { return 1 }
        return [regexp -nocase {espresso|steam|water|rinse|flush|clean|cleaning|descale|purge} $name]
    }

    # Called from the settings page's show{page_to_hide page_to_show}.
    # page_to_hide is skipped when it is empty, one of this plugin's own
    # pages, or a transient flow-page name, so a flush/rinse/steam
    # interruption's re-show can never clobber the real return target.
    proc _capture_return_page {page_to_hide} {
        variable _settings_return_page
        if {$page_to_hide eq ""} { return }
        if {[string match "MaintenanceTracker_*" $page_to_hide]} { return }
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
                catch { msg "MaintenanceTracker: ERROR navigating to $target: $err" }
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
    # unwinding ONE close_dialog per level (ShotHistoryEditor v0.5.3
    # mechanism, copied verbatim: the core's page_stack truncation cannot
    # unwind more than one stacked level in a single load, so direct load
    # is unsafe for stacked ancestors). Falls back to _navigate_done's
    # validated load if the stack is corrupted. Failures are logged.
    proc _return_to_page {target} {
        set prev ""
        for {set i 0} {$i < 10} {incr i} {
            set cur ""
            catch { set cur [dui page current] }
            if {$cur eq $target} { return }
            if {![string match "MaintenanceTracker_*" $cur]} { break }
            if {$cur eq $prev} { break }
            set prev $cur
            if {[catch { dui page close_dialog } err]} {
                catch { msg "MaintenanceTracker: close_dialog failed returning to $target: $err" }
                break
            }
        }
        set cur ""
        catch { set cur [dui page current] }
        if {$cur ne $target} {
            _navigate_done $target
        }
    }

    proc open_diagnostics {} {
        open_page MaintenanceTracker_diagnostics
    }

    proc diagnostics_back {} {
        _return_to_page MaintenanceTracker_settings
    }

    # ------------------------------------------------------------------
    #  Layout tokens (ShotHistoryEditor v0.7.1 _init_layout pattern)
    #
    #  Coordinates: virtual 2560x1600 canvas space (fixed constants; the
    #  framework rescales to the physical screen itself -- never feed
    #  winfo screenwidth/height into coordinates, that double-scales).
    #  Fonts: physical pixels from the real detected screen (negative Tk
    #  size = pixels), all through the shared MT_* font objects including
    #  font_button, passed per-instance via -label_font.
    # ------------------------------------------------------------------

    variable L

    # ------------------------------------------------------------------
    #  Theme palette (Pass 20). Every non-state color the plugin paints
    #  comes from these tokens; _apply_palette fills them for the
    #  current settings(theme) and recomputes the state tints (blends
    #  onto the card color, so they follow the theme automatically).
    #  ok/amber/red state colors and all button colors are the same in
    #  both themes. Called from _init_layout at startup and from
    #  toggle_theme at runtime.
    # ------------------------------------------------------------------

    proc _apply_palette {} {
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
            set L(icon_idle)    "#b8bcc8"
            set L(icon_sel)     "#a8bdf0"
            set L(entry_bg)     "#3a3e4a"
            set L(bar_track)    "#454a57"
            set L(bar_tick)     "#5b6170"
            set L(col_unset)    "#8f95a3"
            set L(col_unknown)  "#7d828f"
            # v0.19.1: buttons follow the theme too (muted indigo on
            # dark; the white label reads on both).
            set L(btn_fill)          "#4a5473"
            set L(btn_disabled_fill) "#3a3e4a"
            # Tints need a stronger blend to show on the dark card.
            set tint_frac 0.30
        } else {
            set L(page_bg)      "#d5d6e3"
            set L(card_bg)      "#fbfbfd"
            set L(card_outline) "#dcdcdc"
            set L(text_hi)      "#2b2b2b"
            set L(text_body)    "#444444"
            set L(text_mut)     "#777777"
            set L(icon_idle)    "#4a4f59"
            set L(icon_sel)     "#3b4a6b"
            set L(entry_bg)     "#fbfaff"
            set L(bar_track)    "#e7e9ee"
            set L(bar_tick)     "#c2c6d0"
            set L(col_unset)    "#b8b8b8"
            set L(col_unknown)  "#999999"
            set L(btn_fill)          "#c0c5e3"
            set L(btn_disabled_fill) "#dddddd"
            set tint_frac 0.16
        }
        foreach st {ok amber red unset unknown} {
            set L(tint_$st) [_blend $L(card_bg) $L(col_$st) $tint_frac]
        }
    }

    # The theme button's face: moon in light mode (tap for dark), sun
    # in dark mode (tap for light); text fallback when icons are off.
    proc _theme_button_face {} {
        variable L
        variable settings
        set dark 0
        catch { if {$settings(theme) eq "dark"} { set dark 1 } }
        if {[info exists L(have_icons)] && $L(have_icons)} {
            # v0.19.1: sun-bright, not the plain FA sun glyph -- that
            # one is an eight-spiked star the owner read as a shuriken.
            set g [_glyph_for [expr {$dark ? "sun-bright" : "moon"}]]
            if {$g ne ""} { return $g }
        }
        return [expr {$dark ? [translate "Light"] : [translate "Dark"]}]
    }

    proc toggle_theme {} {
        variable settings
        set settings(theme) [expr {$settings(theme) eq "dark" ? "light" : "dark"}]
        save_settings
        _apply_palette
        _retheme_all
        # The main page is where the button lives -- repaint its dynamic
        # parts (cards, counters, button face) immediately.
        if {[catch { ::dui::pages::MaintenanceTracker_settings::refresh } err]} {
            catch { msg "MaintenanceTracker: refresh after theme toggle failed: $err" }
        }
        catch { msg "MaintenanceTracker: theme switched to $settings(theme)" }
    }

    # Repaint every page's palette-colored STATIC items (dynamic items
    # -- card contents, picker selection, detail header -- recolor in
    # their refresh procs, which run on every page show). Bare tags
    # only; every call is guarded, so a missing item can never break
    # the walk.
    proc _retheme_all {} {
        variable L
        variable picker_icons
        set all_pages {
            MaintenanceTracker_settings MaintenanceTracker_diagnostics
            MaintenanceTracker_confirm MaintenanceTracker_confirm_burr
            MaintenanceTracker_confirm_bottle MaintenanceTracker_detail
            MaintenanceTracker_add MaintenanceTracker_edit
            MaintenanceTracker_steps MaintenanceTracker_stepedit
        }
        foreach p $all_pages {
            catch { dui item config $p page_bg -fill $L(page_bg) -outline $L(page_bg) }
        }
        # Text roles: {page tag role} triplets.
        foreach {p tag role} {
            MaintenanceTracker_settings page_title text_hi
            MaintenanceTracker_settings subtitle text_mut
            MaintenanceTracker_settings toolbar_status text_mut
            MaintenanceTracker_confirm page_title text_hi
            MaintenanceTracker_confirm confirm_question text_hi
            MaintenanceTracker_confirm confirm_current text_body
            MaintenanceTracker_confirm confirm_note text_mut
            MaintenanceTracker_confirm_burr page_title text_hi
            MaintenanceTracker_confirm_burr confirm_question text_hi
            MaintenanceTracker_confirm_burr offset_label text_body
            MaintenanceTracker_confirm_burr offset_value text_hi
            MaintenanceTracker_confirm_burr confirm_note text_mut
            MaintenanceTracker_confirm_bottle page_title text_hi
            MaintenanceTracker_confirm_bottle confirm_question text_hi
            MaintenanceTracker_confirm_bottle size_label text_body
            MaintenanceTracker_confirm_bottle size_value text_hi
            MaintenanceTracker_confirm_bottle confirm_note text_mut
            MaintenanceTracker_detail page_title text_hi
            MaintenanceTracker_detail detail_counter text_hi
            MaintenanceTracker_detail detail_last text_mut
            MaintenanceTracker_detail hist_card_title text_hi
            MaintenanceTracker_detail hist_hint text_mut
            MaintenanceTracker_detail link_card_title text_hi
            MaintenanceTracker_detail auto_cap text_mut
            MaintenanceTracker_detail auto_txt0 text_body
            MaintenanceTracker_detail auto_txt1 text_body
            MaintenanceTracker_add page_title text_hi
            MaintenanceTracker_add name_label text_body
            MaintenanceTracker_add unit_label text_body
            MaintenanceTracker_add unit_value text_hi
            MaintenanceTracker_add unit_hint text_mut
            MaintenanceTracker_add thr_label text_body
            MaintenanceTracker_add thr_value text_hi
            MaintenanceTracker_add icon_label text_hi
            MaintenanceTracker_add hidden_title text_hi
            MaintenanceTracker_edit page_title text_hi
            MaintenanceTracker_edit edit_current text_mut
            MaintenanceTracker_edit name_label text_body
            MaintenanceTracker_edit thr_label text_body
            MaintenanceTracker_edit thr_value text_hi
            MaintenanceTracker_edit icon_label text_hi
            MaintenanceTracker_edit auto_label text_body
            MaintenanceTracker_edit auto_value text_hi
            MaintenanceTracker_edit link_value text_body
            MaintenanceTracker_steps page_title text_hi
            MaintenanceTracker_steps steps_sub text_mut
            MaintenanceTracker_stepedit page_title text_hi
            MaintenanceTracker_stepedit se_sub text_mut
            MaintenanceTracker_edit edit_note text_mut
            MaintenanceTracker_diagnostics page_title text_hi
            MaintenanceTracker_diagnostics subtitle text_mut
        } {
            catch { dui item config $p $tag -fill $L($role) }
        }
        # Detail event rows.
        for {set i 0} {$i < 5} {incr i} {
            catch { dui item config MaintenanceTracker_detail ev$i -fill $L(text_hi) }
            catch { dui item config MaintenanceTracker_detail evs$i -fill $L(text_body) }
            catch { dui item config MaintenanceTracker_detail ev${i}_chev -fill $L(text_mut) }
            catch { dui item config MaintenanceTracker_detail ev${i}_div -fill $L(card_outline) }
        }
        # v0.29.1 section cards: backdrops + header dividers (Steps and
        # editor row dividers are walked below; the per-count Steps /
        # editor backdrops share one tag per page).
        foreach {p tag} {
            MaintenanceTracker_detail det_card
            MaintenanceTracker_detail hist_card
            MaintenanceTracker_detail link_card
            MaintenanceTracker_steps steps_card
            MaintenanceTracker_stepedit se_card
            MaintenanceTracker_stepedit se_fcard
            MaintenanceTracker_add add_c1
            MaintenanceTracker_add add_c2
            MaintenanceTracker_add add_c3
            MaintenanceTracker_edit ed_c1
            MaintenanceTracker_edit ed_c2
            MaintenanceTracker_edit ed_c3
        } {
            catch { dui item config $p $tag -fill $L(card_bg) -outline $L(card_outline) }
            catch { dui item config $p ${tag}_div -fill $L(card_outline) }
            catch { dui item config $p ${tag}_title -fill $L(text_hi) }
        }
        for {set i 0} {$i < 8} {incr i} {
            catch { dui item config MaintenanceTracker_steps stepd$i -fill $L(card_outline) }
            catch { dui item config MaintenanceTracker_stepedit se_d$i -fill $L(card_outline) }
        }
        catch { dui item config MaintenanceTracker_add add_c1_vdiv -fill $L(card_outline) }
        catch { dui item config MaintenanceTracker_add thr_box -fill $L(entry_bg) -outline $L(entry_bg) }
        catch { dui item config MaintenanceTracker_edit thr_box -fill $L(entry_bg) -outline $L(entry_bg) }
        catch { dui item config MaintenanceTracker_edit ed_c1_vdiv -fill $L(card_outline) }
        for {set j 0} {$j < 20} {incr j} {
            catch { dui item config MaintenanceTracker_detail det_seg$j -fill $L(bar_track) -outline $L(bar_track) }
        }
        catch { dui item config MaintenanceTracker_detail det_tick -fill $L(bar_tick) -outline $L(bar_tick) }
        # Diagnostics label/value rows.
        for {set i 0} {$i < 16} {incr i} {
            catch { dui item config MaintenanceTracker_diagnostics row${i}_label -fill $L(text_hi) }
            catch { dui item config MaintenanceTracker_diagnostics row${i}_value -fill $L(text_body) }
        }
        # Card backdrops + static text fills + amber ticks (contents are
        # repainted by the settings refresh).
        for {set i 0} {$i < 5} {incr i} {
            catch { dui item config MaintenanceTracker_settings row${i}_bg \
                -fill $L(card_bg) -outline $L(card_outline) }
            catch { dui item config MaintenanceTracker_settings row${i}_line1 -fill $L(text_hi) }
            catch { dui item config MaintenanceTracker_settings row${i}_line3 -fill $L(text_mut) }
            catch { dui item config MaintenanceTracker_settings row${i}_auto -fill $L(icon_sel) }
            catch { dui item config MaintenanceTracker_settings row${i}_tick \
                -fill $L(bar_tick) -outline $L(bar_tick) }
        }
        # Picker cell backdrops + unselected icon colors on both pages
        # (the pages' own refreshes re-apply the selection colors).
        foreach p {MaintenanceTracker_add MaintenanceTracker_edit} {
            for {set k 0} {$k < [llength $picker_icons]} {incr k} {
                set nm [lindex $picker_icons $k]
                catch { dui item config $p pick${k}_bg \
                    -fill $L(card_bg) -outline $L(card_outline) }
                if {[_is_vector_icon $nm]} {
                    _config_vector_icon $p pick${k}_ic $nm $L(icon_idle)
                } else {
                    catch { dui item config $p pick${k}_ic -fill $L(icon_idle) }
                }
            }
        }
        # Name entries (Tk widgets -- dui item config passes through).
        catch { dui item config MaintenanceTracker_add name_entry \
            -bg $L(entry_bg) -foreground $L(text_hi) }
        catch { dui item config MaintenanceTracker_edit edit_entry \
            -bg $L(entry_bg) -foreground $L(text_hi) }
        # v0.19.1: normal-style buttons follow the theme. A round
        # dbutton's shape is several ovals/rects all tagged
        # ${tag}-btn with -fill AND -outline (dui.tcl:8476-8478), so
        # one bare-tag config recolors the whole face. Danger buttons
        # (red) and every label (white) stay as they are; the invisible
        # tap zones (picker cells, card text) are never touched.
        set btn_list {
            MaintenanceTracker_settings {btn_theme prev_page next_page mt_done bar_add bar_diag
                                         row0_btn row1_btn row2_btn row3_btn row4_btn}
            MaintenanceTracker_confirm {mt_cancel bar_confirm}
            MaintenanceTracker_confirm_burr {minus100 minus10 plus10 plus100 mt_cancel bar_confirm}
            MaintenanceTracker_confirm_bottle {minus1000 minus100 plus100 plus1000 mt_cancel bar_confirm}
            MaintenanceTracker_detail {btn_edit bar_left mt_hide bar_undo mt_record}
            MaintenanceTracker_steps {mt_sback mt_sdone mt_sedit}
            MaintenanceTracker_stepedit {mt_secancel mt_sereset mt_seadd mt_sefcancel
                                         mt_seup0 mt_seup1 mt_seup2 mt_seup3 mt_seup4 mt_seup5 mt_seup6 mt_seup7
                                         mt_sedn0 mt_sedn1 mt_sedn2 mt_sedn3 mt_sedn4 mt_sedn5 mt_sedn6 mt_sedn7
                                         mt_serm0 mt_serm1 mt_serm2 mt_serm3 mt_serm4 mt_serm5 mt_serm6 mt_serm7}
            MaintenanceTracker_add {btn_auto unit_toggle step0 step1 step2 step3
                                    hid0 hid1 hid2 hid3 hid4 hid5 mt_cancel mt_save}
            MaintenanceTracker_edit {auto_toggle step0 step1 step2 step3 mt_cancel mt_save
                                     mt_elink mt_elinkds mt_elinkcl mt_eunlink}
            MaintenanceTracker_diagnostics {mt_back}
        }
        foreach {p tags} $btn_list {
            foreach tag $tags {
                catch { dui item config $p ${tag}-btn \
                    -fill $L(btn_fill) -outline $L(btn_fill) \
                    -disabledfill $L(btn_disabled_fill) -disabledoutline $L(btn_disabled_fill) }
            }
        }
    }

    proc _init_layout {} {
        variable L
        array unset L
        array set L {}

        # Virtual base resolution: fixed constants, not detected.
        set sw 2560
        set sh 1600
        set scale [expr {double($sh) / 800.0}]

        # Real physical screen, used ONLY for font pixel sizes.
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
        set L(font_scale) $font_scale

        # Spacing tokens (reference px at 1340x800, scaled).
        foreach {tok ref} {xs 6 sm 10 md 16 lg 24 xl 32 xxl 48} {
            set L($tok) [expr {int(round($ref * $scale))}]
        }

        set L(margin) [expr {int(max($sw * 0.036, 32))}]
        set L(left_x) $L(margin)
        set L(right_x) [expr {$sw - $L(margin)}]
        set L(content_w) [expr {$L(right_x) - $L(left_x)}]
        set L(label_col_w) [expr {int(round(420 * $scale))}]
        set L(value_x) [expr {$L(left_x) + $L(label_col_w) + $L(lg)}]

        # Diagnostics label/value rows: start under the header, one row
        # per fact, everything ends above the bottom bar.
        set L(list_top) [expr {int(round(168 * $scale))}]
        set L(diag_row_h) [expr {int(round(34 * $scale))}]

        # Toolbar zone (count status left, Prev/Next right).
        set L(toolbar_y0) [expr {int(round(104 * $scale))}]
        set L(toolbar_y1) [expr {int(round(152 * $scale))}]

        # Card tokens (ShotHistoryEditor card system + Pass 10 Service
        # Bay internals: icon plate, state word, counter, segmented wear
        # bar with amber tick, caption).
        set L(card_w) $L(content_w)
        set L(card_h) [expr {int(round(96 * $scale))}]
        set L(card_gap) [expr {int(round(12 * $scale))}]
        set L(card_pad_x) [expr {int(round(18 * $scale))}]
        set L(card_line1_dy) [expr {int(round(30 * $scale))}]
        set L(card_line2_dy) [expr {int(round(56 * $scale))}]
        set L(card_line3_dy) [expr {int(round(80 * $scale))}]
        set L(card_btn_w) [expr {int(round(150 * $scale))}]
        set L(card_btn_h) [expr {int(max(56, round(56 * $scale)))}]
        set L(dot_size) [expr {int(round(28 * $scale))}]
        set L(plate_size) [expr {int(round(56 * $scale))}]
        # v0.17.0: vector icons are drawn in VIRTUAL coordinates but must
        # visually match the icon glyphs, whose sizes are PHYSICAL px --
        # px2v converts. Box = the square the 0..100 design maps into.
        set px2v [expr {double($sw) / $psw}]
        set L(vec_box_plate) [expr {int(round(max(16, 26 * $font_scale) * $px2v))}]
        set L(vec_box_pick)  [expr {int(round(max(16, 24 * $font_scale) * $px2v))}]
        set L(plate_radius) [expr {int(round(14 * $scale))}]
        set L(card_name_dy)  [expr {int(round(24 * $scale))}]
        set L(card_state_dy) [expr {int(round(47 * $scale))}]
        set L(card_bar_dy)   [expr {int(round(64 * $scale))}]
        set L(card_cap_dy)   [expr {int(round(82 * $scale))}]
        set L(bar_h) [expr {int(round(8 * $scale))}]
        set L(bar_segs) 20
        set L(bar_seg_gap) [expr {int(round(3 * $scale))}]

        # Per-state colors (dot + accents). Stock palette values already
        # used by installed plugins (history_exclusion_filter, GFC).
        # ok/amber/red are theme-INdependent (legible on both palettes);
        # everything else color-related lives in _apply_palette (Pass
        # 20) so the theme toggle can swap it at runtime.
        set L(col_ok) "#0CA581"
        set L(col_amber) "#fe7e00"
        set L(col_red) "#DA515E"
        _apply_palette

        set L(btn_w_std) [expr {int(round(200 * $scale))}]
        set L(btn_w_wide) [expr {int(round(240 * $scale))}]
        # v0.6.1: wide enough for "Yes, Delete Last Record" at the 20px
        # button face -- the Undo button wears this label in its confirm
        # state and the width is fixed at creation.
        set L(btn_w_xwide) [expr {int(round(300 * $scale))}]
        set L(btn_h) [expr {int(max(60, round(60 * $scale)))}]
        set L(btn_radius) [expr {int(round(12 * $scale))}]

        set L(header_title_y) [expr {int(round(28 * $scale))}]
        set L(header_subtitle_y) [expr {int(round(72 * $scale))}]
        set L(header_solo_title_y) [expr {int(round(48 * $scale))}]
        set L(bar_y0) [expr {int(round(716 * $scale))}]
        set L(bar_y1) [expr {int(round(776 * $scale))}]

        # v0.29.1: section cards behind Detail, Steps, Edit steps and New
        # Tracker (the list card's backdrop, full content width or split).
        # A card = rounded backdrop + optional header band (title centred
        # sec_head_h/2 down) closed by a one-row divider RECT (a canvas
        # line anti-aliases into two half rows). Inner x = card edge +
        # card_pad_x. Rows inside a card are fixed-pitch.
        set L(sec_head_h) [expr {int(round(48 * $scale))}]
        set L(sec_pad_y)  [expr {int(round(8 * $scale))}]
        set L(div_h) 2
        set L(badge) [expr {int(round(30 * $scale))}]
        # Detail: status card (the list card's anatomy, no plate/button),
        # then History (left, 66% of the width) beside Linked profile.
        set L(det_top)     [expr {int(round(104 * $scale))}]
        set L(det_low_y0)  [expr {int(round(216 * $scale))}]
        set L(det_low_y1)  [expr {int(round(600 * $scale))}]
        set L(det_hist_x1) [expr {$L(left_x) + int($L(content_w) * 0.66)}]
        set L(det_row_h)   [expr {int(round(64 * $scale))}]
        set L(det_msg_y)   [expr {int(round(658 * $scale))}]
        # Steps: one card whose height follows the step count (one
        # pre-built backdrop per count), the message callout fixed above
        # the bar.
        set L(steps_y0)    [expr {int(round(122 * $scale))}]
        set L(steps_row_h) [expr {int(round(54 * $scale))}]
        set L(call_y0)     [expr {int(round(626 * $scale))}]
        set L(call_y1)     [expr {int(round(700 * $scale))}]
        # Edit steps: same card, taller rows (Up/Down/Remove inside).
        set L(se_row_h)    [expr {int(round(64 * $scale))}]
        set L(se_btn_h)    [expr {int(round(56 * $scale))}]
        # New Tracker: three cards -- name + counting + due-after, icon
        # picker, hidden trackers.
        set L(add_c1_y0)   [expr {int(round(104 * $scale))}]
        set L(add_c1_y1)   [expr {int(round(328 * $scale))}]
        set L(add_c2_y0)   [expr {int(round(344 * $scale))}]
        set L(add_c2_y1)   [expr {int(round(534 * $scale))}]
        set L(add_c3_y0)   [expr {int(round(550 * $scale))}]
        set L(add_c3_y1)   [expr {int(round(674 * $scale))}]
        set L(add_col_x)   [expr {$L(left_x) + int($L(content_w) * 0.47)}]
        # Edit Tracker: subtitle, then name | link, due-after + auto-
        # record + note, icon; the message line above the bar.
        set L(ed_sub_y)    [expr {int(round(92 * $scale))}]
        set L(ed_c1_y0)    [expr {int(round(120 * $scale))}]
        set L(ed_c1_y1)    [expr {int(round(230 * $scale))}]
        set L(ed_c2_y0)    [expr {int(round(246 * $scale))}]
        set L(ed_c2_y1)    [expr {int(round(440 * $scale))}]
        set L(ed_c3_y0)    [expr {int(round(456 * $scale))}]
        set L(ed_c3_y1)    [expr {int(round(646 * $scale))}]
        set L(ed_msg_y)    [expr {int(round(681 * $scale))}]

        # Self-contained colors (BeanScanner v0.1.2 pattern): the plugin
        # paints its own background and explicit button fills, so nothing
        # depends on which dui theme or skin palette is current.
        # v0.19.1: btn_fill/btn_disabled_fill moved into _apply_palette
        # (owner wanted dark buttons); labels stay white and the danger
        # red stays identical in both themes. Existing buttons restyle
        # at toggle via their ${tag}-btn shape tag -- every segment of
        # a round dbutton carries it with -fill AND -outline
        # (de1app-core/dui.tcl:9896, 8476-8478), and dui item config
        # itemconfigures all matches (dui.tcl:7440-7452).
        set L(btn_label_fill) white

        # Pixel-exact fonts, floored at 16px, all on font_scale. Named
        # Helv_* fallbacks first so every key is valid even if the "font"
        # command is unavailable.
        set L(font_title) Helv_20_bold
        set L(font_primary) Helv_10_bold
        set L(font_body) Helv_9
        set L(font_caption) Helv_8
        set L(font_caption_b) Helv_8_bold
        set L(font_button) Helv_10_bold
        catch {
            foreach {name ref bold} {title 40 1 primary 22 1 body 19 0 caption 16 0 caption_b 16 1 button 20 1} {
                set px [expr {int(max(16, round($ref * $font_scale)))}]
                set fname "MT_$name"
                set weight [expr {$bold ? "bold" : "normal"}]
                if {[lsearch -exact [font names] $fname] >= 0} {
                    font configure $fname -size [expr {-$px}] -weight $weight
                } else {
                    font create $fname -family Helvetica -size [expr {-$px}] -weight $weight
                }
                set L(font_$name) $fname
            }
        }

        # Pass 10: icon fonts from the app's own Font Awesome 6 Pro file
        # (dui::font::add_or_get_familyname is the core's loader). Same
        # physical-pixel sizing rule as every other font. If the font is
        # unavailable, have_icons stays 0 and plates render glyph-less.
        set L(have_icons) 0
        set L(font_icon_plate) $L(font_primary)
        set L(font_icon_pick) $L(font_primary)
        catch {
            set fam [dui::font::add_or_get_familyname "Font Awesome 6 Pro-Regular-400.otf"]
            if {$fam ne ""} {
                foreach {n ref} {icon_plate 26 icon_pick 24} {
                    set px [expr {int(max(16, round($ref * $font_scale)))}]
                    set fname "MT_$n"
                    if {[lsearch -exact [font names] $fname] >= 0} {
                        font configure $fname -family $fam -size [expr {-$px}]
                    } else {
                        font create $fname -family $fam -size [expr {-$px}]
                    }
                    set L(font_$n) $fname
                }
                set L(have_icons) 1
            }
        }

        # Shared button style. -theme default is REQUIRED: aspect lookup
        # falls back from a named theme to default, never the other way,
        # and under Lumen the current theme is DYE_Lumen by the time this
        # plugin loads (ShotHistoryEditor v0.5.4 / BeanScanner v0.1.2).
        catch {
            dui aspect set -theme default -type dbutton -style mt_btn [list \
                shape round radius $L(btn_radius) \
                fill $L(btn_fill) disabledfill $L(btn_disabled_fill)]
            dui aspect set -theme default -type dbutton_label -style mt_btn [list \
                fill $L(btn_label_fill) disabledfill "#999999"]
            # Danger style (destructive actions: Undo), same geometry,
            # state-red fill -- the design system's danger slot.
            dui aspect set -theme default -type dbutton -style mt_btn_danger [list \
                shape round radius $L(btn_radius) \
                fill $L(col_red) disabledfill $L(btn_disabled_fill)]
            dui aspect set -theme default -type dbutton_label -style mt_btn_danger [list \
                fill white disabledfill "#999999"]
            # v0.25.0: primary style -- the page's ONE go-ahead action
            # (Detail's Record), state-green in both themes so it reads
            # at a glance. No pressfill (the flash would stick).
            dui aspect set -theme default -type dbutton -style mt_btn_primary [list \
                shape round radius $L(btn_radius) \
                fill $L(col_ok) disabledfill $L(btn_disabled_fill)]
            dui aspect set -theme default -type dbutton_label -style mt_btn_primary [list \
                fill white disabledfill "#999999"]
        }
    }

    # Full-page background, first item of every page, so contrast never
    # depends on the active skin theme (fpdialog pages otherwise show
    # whatever lies beneath -- near-black under Lumen's dark mode).
    proc _page_bg {page} {
        variable L
        dui add canvas_item rect $page 0 0 $L(screen_w) $L(screen_h) \
            -fill $L(page_bg) -outline $L(page_bg) -tags page_bg
    }

    # Rounded-rectangle card/dot backdrop (ShotHistoryEditor rounded_rect,
    # copied verbatim: smoothed canvas polygon; -fill reconfigurable via
    # `dui item config`, proven in GrindAdvisor.tcl:4683).
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

    # v0.29.1: a section card -- the list card's backdrop (tag <tag>) and,
    # with a title, a header band: title dtext <tag>_title (primary, left)
    # and the divider rect <tag>_div under it. Extra args go to the
    # backdrop (e.g. -initial_state hidden). Returns the y where the
    # card's rows start.
    proc _sec_card {page tag x1 y1 x2 y2 title args} {
        variable L
        rounded_rect $page $x1 $y1 $x2 $y2 $L(btn_radius) \
            -fill $L(card_bg) -outline $L(card_outline) -width 2 -tags $tag {*}$args
        if {$title eq ""} { return [expr {$y1 + $L(sec_pad_y)}] }
        set hy [expr {$y1 + $L(sec_head_h)}]
        dui add dtext $page [expr {$x1 + $L(card_pad_x)}] [expr {$y1 + $L(sec_head_h) / 2}] \
            -tags ${tag}_title -text $title -font $L(font_primary) \
            -width [expr {$x2 - $x1 - 2 * $L(card_pad_x)}] \
            -fill $L(text_hi) -anchor w -justify left {*}$args
        _sec_divider $page ${tag}_div $x1 $hy $x2 {*}$args
        return $hy
    }

    # One-row divider (a rect, not a line: lines anti-alias into two
    # half-alpha rows on AndroWish).
    proc _sec_divider {page tag x1 y x2 args} {
        variable L
        dui add canvas_item rect $page $x1 $y $x2 [expr {$y + $L(div_h)}] \
            -fill $L(card_outline) -outline "" -width 0 -tags $tag {*}$args
    }

    # Numbered badge: a state-green disc with the white number. Tags
    # <tag> (disc) and <tag>_n (number).
    proc _sec_badge {page tag cx cy args} {
        variable L
        set r [expr {$L(badge) / 2}]
        dui add canvas_item oval $page [expr {$cx - $r}] [expr {$cy - $r}] \
            [expr {$cx + $r}] [expr {$cy + $r}] \
            -fill $L(col_ok) -outline $L(col_ok) -width 1 -tags $tag {*}$args
        dui add dtext $page $cx $cy -tags ${tag}_n -text "0" -font $L(font_caption_b) \
            -fill white -anchor center -justify center {*}$args
    }

    # Row chevron (">", two round-capped strokes) -- says "tap me".
    proc _sec_chevron {page tag cx cy args} {
        variable L
        set w [expr {int(round(5 * $L(scale)))}]
        set h [expr {int(round(9 * $L(scale)))}]
        dui add canvas_item line $page [expr {$cx - $w}] [expr {$cy - $h}] \
            [expr {$cx + $w}] $cy [expr {$cx - $w}] [expr {$cy + $h}] \
            -fill $L(text_mut) -width [expr {int(round(2.5 * $L(scale)))}] \
            -capstyle round -joinstyle round -tags $tag {*}$args
    }

    # ------------------------------------------------------------------
    #  Page registration (called from the manifest's preload)
    # ------------------------------------------------------------------

    proc preload_pages {} {
        package require de1_dui 1.0
        catch { plugins load_settings MaintenanceTracker }
        apply_defaults
        catch { plugins save_settings MaintenanceTracker }
        _init_layout
        dui page add MaintenanceTracker_settings -namespace true -theme default -type fpdialog
        dui page add MaintenanceTracker_diagnostics -namespace true -theme default -type fpdialog
        dui page add MaintenanceTracker_confirm -namespace true -theme default -type fpdialog
        dui page add MaintenanceTracker_confirm_burr -namespace true -theme default -type fpdialog
        dui page add MaintenanceTracker_confirm_bottle -namespace true -theme default -type fpdialog
        dui page add MaintenanceTracker_detail -namespace true -theme default -type fpdialog
        dui page add MaintenanceTracker_add -namespace true -theme default -type fpdialog
        dui page add MaintenanceTracker_edit -namespace true -theme default -type fpdialog
        dui page add MaintenanceTracker_steps -namespace true -theme default -type fpdialog
        dui page add MaintenanceTracker_stepedit -namespace true -theme default -type fpdialog
        return MaintenanceTracker_settings
    }

    # ------------------------------------------------------------------
    #  Detail page state (Pass 6). detail_mode is the single-page confirm
    #  swap (view <-> confirm); any page show resets it (stuck-flag rule).
    # ------------------------------------------------------------------

    variable detail_item ""
    variable detail_mode view
    # v0.29.0 (Pass 35): the events-list index the confirm mode targets
    # (-1 = the newest, i.e. the classic Undo). Reset with the mode.
    variable detail_target -1

    proc open_detail {id} {
        variable detail_item
        variable detail_mode
        variable detail_target
        variable settings
        if {![info exists settings(item_$id)]} {
            catch { msg "MaintenanceTracker: unknown item for detail: $id" }
            return
        }
        set detail_item $id
        set detail_mode view
        set detail_target -1
        open_page MaintenanceTracker_detail
    }

    # One line of event history: date/time + how it was recorded.
    # `auto` is reserved for a future pass; tolerate and display it now.
    # v0.29.1: one history row as two texts for the card's two columns:
    # {"<date time>  (<ago>)" "recorded automatically|manually"}.
    proc _event_parts {ev} {
        set ts 0
        catch { set ts [dict get $ev ts] }
        if {![string is wide -strict $ts] || $ts <= 0} { return [list "" ""] }
        set when [clock format $ts -format {%Y-%m-%d %H:%M}]
        set ago [_fmt_ago $ts]
        if {$ago ne ""} { append when "  ($ago)" }
        set src manual
        catch { set src [dict get $ev source] }
        if {$src eq "auto"} {
            return [list $when [translate {recorded automatically}]]
        }
        return [list $when [translate {recorded manually}]]
    }

    # ------------------------------------------------------------------
    #  Icons (Pass 10). Glyphs come from the app's own Font Awesome 6
    #  Pro symbol table (dui.tcl:1346+): scalable, tintable, no image
    #  files. Built-ins have fixed glyphs; customs carry an `icon` field
    #  chosen on the Add page (default wrench). Rendering degrades to an
    #  empty plate if the font or a symbol is unavailable.
    # ------------------------------------------------------------------

    variable builtin_icons {
        backflush     grate-droplet
        descale       droplet-slash
        group_gasket  ring
        burr_clean    coffee-beans
        burr_install  gears
        water_filter  filter
        water_bottle  tank-water
    }

    # Picker candidates for custom trackers, in display order. Two rows
    # of 12 (v0.14.0); every name verified against the app's own FA6 Pro
    # symbol table (de1app-core/dui.tcl:1346+) -- an unknown name would
    # render an empty cell. _build_picker_row wraps at picker_cols.
    # v0.15.0: gears and droplet-slash replaced screwdriver-wrench and
    # soap (near-duplicates of wrench/pump-soap) so every built-in
    # tracker's default glyph is pickable on the Edit page.
    # v0.16.0 (owner request): four duplicates gave way to required
    # meanings -- pump-soap -> wand (steam wand), coffee-pot ->
    # pipe-section (drain pipe), mug-saucer -> circle-dot (ball joint),
    # brush -> record-vinyl (flat gasket). All names verified in the
    # app's FA6 table; trackers still storing a retired name keep
    # rendering it (glyphs resolve by name, not picker membership).
    # v0.17.0: two picker slots are VECTOR icons drawn by the plugin
    # itself (owner picked the designs from rendered mockups): the FA
    # font has no honest steam wand ("wand" is a magic wand) and no flat
    # gasket. steam-wand replaced wand, gasket-flat replaced
    # record-vinyl.
    variable picker_cols 12
    variable picker_icons {
        wrench mug-hot coffee-beans filter droplet grate-droplet
        ring steam-wand faucet-drip tank-water stopwatch spray-can
        bottle-water pipe-section circle-dot gauge-high scale-balanced temperature-half
        gears gasket-flat droplet-slash calendar-check bell star
    }

    # ------------------------------------------------------------------
    #  Cached-canvas rendering (Pass 23; DrinkMenu v0.6.2 mechanism,
    #  ported). Every `dui item show|hide|config` re-resolves its tag
    #  against the whole canvas (`find withtag p:<page>&&<tag>`) and
    #  show/hide with -initial re-enters `dui item config` for the
    #  initial-state tag; DrinkMenu measured ~1 ms per call on the
    #  tablet (~540 calls = ~590 ms per refresh). Card items are
    #  created once at page setup and never destroyed, so their canvas
    #  ids are stable: resolve each tag once, cache the ids, and drive
    #  the canvas directly afterwards.
    # ------------------------------------------------------------------

    variable item_cache
    array set item_cache {}
    variable vis_cache
    array set vis_cache {}
    variable cfg_cache
    array set cfg_cache {}
    # 1 = log refresh timings via msg (dev only, never ship enabled).
    variable debug_timing 0

    # Canvas ids for one exact tag on one page, resolved once. A tag
    # that matches nothing is NOT cached, so a later lookup can still
    # find it (and dui keeps logging its own DEBUG line for a real miss).
    proc _ids {page tag} {
        variable item_cache
        if {[info exists item_cache($page,$tag)]} { return $item_cache($page,$tag) }
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

    # Raw-canvas replacement for `dui item config` on plain text/shape
    # options (-text, -fill, -outline). NOT for -state (_set_vis), not
    # for scaled options (-width), not for dbutton -label/-state (those
    # stay real dui calls). Unchanged option sets are skipped.
    proc _cfg {page tag args} {
        variable cfg_cache
        if {[info exists cfg_cache($page,$tag)] && $cfg_cache($page,$tag) eq $args} { return }
        set ids [_ids $page $tag]
        if {$ids eq ""} { return }
        set can ""
        catch { set can [dui canvas] }
        if {$can eq ""} { return }
        foreach id $ids { catch { $can itemconfigure $id {*}$args } }
        set cfg_cache($page,$tag) $args
    }

    # ------------------------------------------------------------------
    #  Vector icons (Pass 18). Stroke drawings on the page canvas:
    #  round-capped lines and hollow ovals in a 0..100 design box,
    #  mapped into a box sized to match the FA glyphs (L(vec_box_*)).
    #  Coordinates are virtual (the framework rescales, canvas_item
    #  rescales -width too, dui.tcl:9551-9553). Segments get unique
    #  bare tags ${basetag}_s<i>; show/hide/config loop over them with
    #  bare tags (the v0.6.2 wildcard rule). Lines recolor via -fill,
    #  ovals via -outline.
    # ------------------------------------------------------------------

    variable vector_icons {steam-wand gasket-flat}
    # kind width-pct coords: line = polyline points, oval = cx cy rx ry.
    variable vector_defs {
        steam-wand {
            {line 13 {50 8 50 32}}
            {line 24 {50 40 50 52}}
            {line 9 {33 68 26 80}}
            {line 9 {50 70 50 84}}
            {line 9 {67 68 74 80}}
        }
        gasket-flat {
            {oval 14 {50 50 34 17}}
        }
    }

    proc _is_vector_icon {name} {
        variable vector_icons
        return [expr {$name in $vector_icons}]
    }

    # Create one vector icon centered on (cx, cy), box px wide/tall
    # (all virtual). hidden=1 creates every segment with
    # -initial_state hidden (the v0.10.1 no-flash rule).
    proc _add_vector_icon {page basetag name cx cy box color hidden} {
        variable vector_defs
        set s [expr {double($box) / 100.0}]
        set i 0
        foreach seg [dict get $vector_defs $name] {
            lassign $seg kind wpct coords
            set w [expr {int(round($wpct * $s))}]
            if {$w < 4} { set w 4 }
            set opts [list -width $w -tags ${basetag}_s$i]
            if {$hidden} { lappend opts -initial_state hidden }
            if {$kind eq "oval"} {
                lassign $coords ocx ocy rx ry
                set x1 [expr {int(round($cx + ($ocx - 50 - $rx) * $s))}]
                set y1 [expr {int(round($cy + ($ocy - 50 - $ry) * $s))}]
                set x2 [expr {int(round($cx + ($ocx - 50 + $rx) * $s))}]
                set y2 [expr {int(round($cy + ($ocy - 50 + $ry) * $s))}]
                dui add canvas_item oval $page $x1 $y1 $x2 $y2 \
                    -outline $color {*}$opts
            } else {
                set pts {}
                foreach {px py} $coords {
                    lappend pts [expr {int(round($cx + ($px - 50) * $s))}] \
                                [expr {int(round($cy + ($py - 50) * $s))}]
                }
                dui add canvas_item line $page {*}$pts \
                    -fill $color -capstyle round -joinstyle round {*}$opts
            }
            incr i
        }
    }

    proc _config_vector_icon {page basetag name color} {
        variable vector_defs
        set i 0
        foreach seg [dict get $vector_defs $name] {
            if {[lindex $seg 0] eq "oval"} {
                _cfg $page ${basetag}_s$i -outline $color
            } else {
                _cfg $page ${basetag}_s$i -fill $color
            }
            incr i
        }
    }

    proc _show_vector_icon {page basetag name show} {
        variable vector_defs
        set n [llength [dict get $vector_defs $name]]
        set tags {}
        for {set i 0} {$i < $n} {incr i} { lappend tags ${basetag}_s$i }
        _set_vis $page $tags $show
    }

    # v0.28.1: the DE1 group head's espresso-button icon (owner photo of
    # the GHC), for the Steps page's "press this button" hint: a SOLID
    # bowl-shaped cup with a horizontal slot under the rim, a round ring
    # handle, a thick saucer bar. Box 0..100, centred on (cx, cy), `box`
    # virtual px. Parts (tags <base>_body/_slot/_ring/_saucer) are born
    # hidden; the slot is filled with the page background by the caller
    # (it is a cut-out, so it follows the theme).
    variable ghc_cup_parts {body slot ring saucer}
    proc _add_ghc_cup {page base cx cy box color} {
        set s [expr {double($box) / 100.0}]
        set P [list]
        # Doubled points keep the rim corners sharp under -smooth 1.
        foreach {x y} {12 22 12 22 72 22 72 22 72 36 69 48 62 57 52 60 32 60 22 57 15 48 12 36} {
            lappend P [expr {int(round($cx + ($x - 50) * $s))}] [expr {int(round($cy + ($y - 47) * $s))}]
        }
        dui add canvas_item polygon $page {*}$P -smooth 1 -fill $color -outline $color \
            -width 1 -tags ${base}_body -initial_state hidden
        dui add canvas_item rect $page \
            [expr {int(round($cx + (19 - 50) * $s))}] [expr {int(round($cy + (29 - 47) * $s))}] \
            [expr {int(round($cx + (65 - 50) * $s))}] [expr {int(round($cy + (39 - 47) * $s))}] \
            -fill $color -outline "" -width 0 -tags ${base}_slot -initial_state hidden
        set rw [expr {max(3, int(round(4.5 * $s)))}]
        dui add canvas_item oval $page \
            [expr {int(round($cx + (80 - 6.5 - 50) * $s))}] [expr {int(round($cy + (30 - 6.5 - 47) * $s))}] \
            [expr {int(round($cx + (80 + 6.5 - 50) * $s))}] [expr {int(round($cy + (30 + 6.5 - 47) * $s))}] \
            -outline $color -width $rw -tags ${base}_ring -initial_state hidden
        dui add canvas_item line $page \
            [expr {int(round($cx + (14 - 50) * $s))}] [expr {int(round($cy + (70 - 47) * $s))}] \
            [expr {int(round($cx + (70 - 50) * $s))}] [expr {int(round($cy + (70 - 47) * $s))}] \
            -fill $color -width [expr {max(4, int(round(6 * $s)))}] -capstyle round \
            -tags ${base}_saucer -initial_state hidden
    }

    # v0.29.1: `under` = the colour the cup sits on (the slot is a
    # cut-out); default the page background.
    proc _show_ghc_cup {page base show {under ""}} {
        variable ghc_cup_parts
        variable L
        set tags {}
        foreach part $ghc_cup_parts { lappend tags ${base}_$part }
        if {$under eq ""} { set under $L(page_bg) }
        if {$show} { _cfg $page ${base}_slot -fill $under }
        _set_vis $page $tags $show
    }

    # v0.18.0: human-readable names for every picker icon, shown next
    # to "Icon:" on the Add/Edit pages so the selection has a meaning,
    # not just a shape. Keys match picker_icons exactly.
    variable icon_labels {
        wrench          "Wrench"
        mug-hot         "Hot mug"
        coffee-beans    "Coffee beans"
        filter          "Filter"
        droplet         "Water drop"
        grate-droplet   "Drip tray"
        ring            "O-ring"
        steam-wand      "Steam wand"
        faucet-drip     "Dripping faucet"
        tank-water      "Water tank"
        stopwatch       "Stopwatch"
        spray-can       "Spray can"
        bottle-water    "Water bottle"
        pipe-section    "Drain pipe"
        circle-dot      "Ball joint"
        gauge-high      "Pressure gauge"
        scale-balanced  "Scale"
        temperature-half "Thermometer"
        gears           "Gears"
        gasket-flat     "Flat gasket"
        droplet-slash   "Descale"
        calendar-check  "Calendar"
        bell            "Bell"
        star            "Star"
    }

    proc _icon_label {name} {
        variable icon_labels
        if {[dict exists $icon_labels $name]} {
            return [translate [dict get $icon_labels $name]]
        }
        return $name
    }

    # v0.18.0: one item-icon renderer shared by the card plates and the
    # Detail page's header plate: shows the glyph dtext OR exactly one
    # of the two vector drawings (tags ${vbase}_vsw_* / ${vbase}_vgf_*,
    # both born hidden) and colors whichever is visible.
    proc _apply_item_icon {page dtext_tag vbase id color} {
        set iname [_item_icon_name $id]
        if {[_is_vector_icon $iname]} {
            _set_vis $page [list $dtext_tag] 0
            foreach {vtag vname} {vsw steam-wand vgf gasket-flat} {
                if {$vname eq $iname} {
                    _show_vector_icon $page ${vbase}_$vtag $vname 1
                    _config_vector_icon $page ${vbase}_$vtag $vname $color
                } else {
                    _show_vector_icon $page ${vbase}_$vtag $vname 0
                }
            }
        } else {
            foreach {vtag vname} {vsw steam-wand vgf gasket-flat} {
                _show_vector_icon $page ${vbase}_$vtag $vname 0
            }
            _set_vis $page [list $dtext_tag] 1
            _cfg $page $dtext_tag -text [_item_glyph $id] -fill $color
        }
    }

    # The item's icon NAME (v0.17.0, split out of _item_glyph so the
    # card renderer can branch on vector icons before glyph lookup).
    # v0.15.0 (consolidation): the item dict's own icon wins for EVERY
    # tracker; the fixed table is the built-in fallback.
    proc _item_icon_name {id} {
        variable builtin_icons
        variable settings
        set name ""
        if {[info exists settings(item_$id)]} {
            catch { set name [dict get $settings(item_$id) icon] }
        }
        if {$name eq "" && [dict exists $builtin_icons $id]} {
            set name [dict get $builtin_icons $id]
        }
        if {$name eq ""} { set name wrench }
        return $name
    }

    # The FA glyph character for an item, or "" when unavailable --
    # including for vector icons, which are not glyphs at all.
    proc _item_glyph {id} {
        variable L
        if {![info exists L(have_icons)] || !$L(have_icons)} { return "" }
        set name [_item_icon_name $id]
        if {[_is_vector_icon $name]} { return "" }
        set glyph [_glyph_for $name]
        # A stored icon name this app build doesn't know falls back to
        # the default so the plate is never left empty by bad data.
        if {$glyph eq "" && $name ne "wrench"} { set glyph [_glyph_for wrench] }
        return $glyph
    }

    proc _glyph_for {name} {
        set glyph ""
        catch {
            if {[dui symbol exists $name]} { set glyph [dui symbol get $name] }
        }
        return $glyph
    }

    # Flat blend of two #rrggbb colors (frac of c2 over c1). Tk canvas
    # has no alpha, so state tints are precomputed solid colors.
    proc _blend {c1 c2 frac} {
        set out "#"
        foreach i {1 3 5} {
            scan [string range $c1 $i [expr {$i+1}]] %x a
            scan [string range $c2 $i [expr {$i+1}]] %x b
            append out [format %02x [expr {int(round($a + ($b - $a) * $frac))}]]
        }
        return $out
    }

    # Worst-first ordering for the card list.
    proc _state_rank {state} {
        switch -- $state {
            red     { return 0 }
            amber   { return 1 }
            ok      { return 2 }
            unknown { return 3 }
            default { return 4 }
        }
    }

    # v0.25.0 (Pass 31): card order. State rank first (red, amber, ok,
    # unknown, never recorded), then -- within a rank -- how far along
    # the tracker is (value / threshold, highest first), then the
    # original order. Until v0.24.1 a rank kept creation order, so a
    # 71%-due tracker sat under a 5% one. lsort is stable (merge sort),
    # so sorting by the minor keys first and the rank last nests them.
    proc _worst_first_ids {summary ids} {
        set rows {}
        set idx 0
        foreach id $ids {
            set st unset
            set frac 0.0
            if {[dict exists $summary items $id]} {
                set e [dict get $summary items $id]
                if {[dict exists $e state]} { set st [dict get $e state] }
                if {[dict exists $e value] && [dict exists $e threshold]} {
                    set v [dict get $e value]
                    set t [dict get $e threshold]
                    if {[string is double -strict $v] && [string is double -strict $t] && $t > 0} {
                        set frac [expr {double($v) / $t}]
                    }
                }
            }
            lappend rows [list [_state_rank $st] $frac $idx $id]
            incr idx
        }
        set rows [lsort -real -decreasing -index 1 $rows]
        set rows [lsort -integer -index 0 $rows]
        set out {}
        foreach r $rows { lappend out [lindex $r 3] }
        return $out
    }

    # Human-readable item names, shared by all pages.
    variable item_labels {
        backflush     "Backflush"
        descale       "Descale"
        group_gasket  "Group gasket"
        burr_clean    "Burr clean"
        burr_install  "Burr install"
        water_filter  "Water filter"
        water_bottle  "Water bottle"
    }

    proc _item_label {id} {
        variable item_labels
        variable settings
        # v0.15.0 (consolidation): the item dict's own label wins for
        # EVERY tracker (built-ins store "" until renamed); the fixed
        # table is the built-in fallback, the id the last resort.
        if {[info exists settings(item_$id)]} {
            set lbl ""
            catch { set lbl [dict get $settings(item_$id) label] }
            if {[string trim $lbl] ne ""} { return $lbl }
        }
        if {[dict exists $item_labels $id]} { return [dict get $item_labels $id] }
        return $id
    }

    # Card text helpers, from a status_summary item entry.
    proc _state_word {state} {
        switch -- $state {
            ok      { return [translate "OK"] }
            amber   { return [translate "due soon"] }
            red     { return [translate "overdue"] }
            unset   { return [translate "never recorded"] }
            default { return [translate "no data"] }
        }
    }

    # v0.13.0: human ml formatting -- litres with one decimal from 1000ml
    # up, plain ml below. Non-numbers render as "?" (never an empty cell).
    proc _fmt_ml {ml} {
        if {![string is double -strict $ml]} { return "?" }
        if {$ml >= 1000} { return "[format %.1f [expr {$ml / 1000.0}]] L" }
        return "[expr {int(round($ml))}] ml"
    }

    # "left" line for ml items, shared by the card caption and the
    # Detail/confirm text. Empty when there is nothing sensible to say.
    proc _ml_left_text {value threshold} {
        if {![string is double -strict $value] || ![string is double -strict $threshold]} {
            return ""
        }
        set left [expr {$threshold - $value}]
        if {$left <= 0} { return [translate "Nothing left -- change it now."] }
        return "[translate {About}] [_fmt_ml $left] [translate {left}]"
    }

    proc _item_detail {id entry} {
        set state [dict get $entry state]
        if {$state eq "unset"} {
            if {[dict exists $entry unit] && [dict get $entry unit] eq "ml"} {
                return [translate "Tap Record when you attach the next bottle."]
            }
            return [translate "Tap Record after you do this the next time."]
        }
        if {$state eq "unknown"} {
            return [translate "Shot database unavailable -- see Diagnostics."]
        }
        set unit [dict get $entry unit]
        set value [dict get $entry value]
        set threshold [dict get $entry threshold]
        if {$unit eq "days"} {
            return "$value [translate {of}] $threshold [translate {days since last done}]"
        }
        if {$unit eq "ml"} {
            set line "[_fmt_ml $value] [translate {of}] [_fmt_ml $threshold] [translate {dispensed since last change}]"
            set left [_ml_left_text $value $threshold]
            if {$left ne ""} { append line " -- $left" }
            return $line
        }
        return "$value [translate {of}] $threshold [translate {shots since last done}]"
    }

    # The card's counter, caption and filled wear-bar segment count for
    # one tracker: {cnt cap nfill}. Moved out of the list refresh in
    # v0.29.1 unchanged, so the Detail status card shows exactly the
    # list card's numbers.
    proc _card_numbers {id entry} {
        variable L
        set state [dict get $entry state]
        set frac 0
        set cnt ""
        set cap ""
        if {$state eq "unset"} {
            # Unit-aware never-recorded text (the ml wording
            # differs); _item_detail owns that phrasing.
            set cap [_item_detail $id $entry]
        } elseif {$state eq "unknown"} {
            set cnt "?"
            set cap [translate "Shot database unavailable -- see Diagnostics."]
        } else {
            set value [dict get $entry value]
            set threshold [dict get $entry threshold]
            set unit [dict get $entry unit]
            if {$unit eq "ml"} {
                # v0.13.0: litres read better at bottle scale, and
                # the caption leads with what the owner actually
                # wants to know -- how much is left.
                if {$threshold >= 1000} {
                    set cnt "[format %.1f [expr {$value / 1000.0}]] / [format %.1f [expr {$threshold / 1000.0}]] L"
                } else {
                    set cnt "$value / $threshold ml"
                }
                set cap [_ml_left_text $value $threshold]
                set ld [_item_last_done_line $entry]
                if {$cap eq ""} {
                    set cap $ld
                } elseif {$ld ne ""} {
                    append cap "   ·   $ld"
                }
            } else {
                set cnt "$value / $threshold [translate $unit]"
                set cap [_item_last_done_line $entry]
            }
            if {[string is double -strict $value] && [string is double -strict $threshold] \
                    && $threshold > 0} {
                set frac [expr {double($value) / $threshold}]
            }
        }
        set nfill [expr {int(round($frac * $L(bar_segs)))}]
        if {$nfill > $L(bar_segs)} { set nfill $L(bar_segs) }
        if {$nfill < 0} { set nfill 0 }
        if {$frac > 0 && $nfill == 0} { set nfill 1 }
        return [list $cnt $cap $nfill]
    }

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

    proc _item_last_done_line {entry} {
        set ts [dict get $entry last_done]
        if {![string is wide -strict $ts] || $ts <= 0} { return "" }
        set line "[translate {Last done:}] [clock format $ts -format {%Y-%m-%d %H:%M}]"
        set ago [_fmt_ago $ts]
        if {$ago ne ""} { append line "  ($ago)" }
        return $line
    }

    # v0.20.0: an item's validated auto-record source ("" = manual only).
    proc _item_auto_src {id} {
        variable settings
        set a ""
        catch { set a [dict get $settings(item_$id) auto_src] }
        if {$a ni {clean descale}} { set a "" }
        return $a
    }

    # Human name for an auto source, shared by the Edit page's value
    # text and the Detail page's auto line.
    proc _auto_src_label {src} {
        switch -- $src {
            clean   { return [translate "Clean cycle"] }
            descale { return [translate "Descale cycle"] }
        }
        return [translate "off -- record manually"]
    }

    # Short form for button faces (the Add page's header toggle).
    proc _auto_src_short {src} {
        switch -- $src {
            clean   { return [translate "Clean cycle"] }
            descale { return [translate "Descale cycle"] }
        }
        return [translate "off"]
    }

    # v0.21.0: what is automatic about this tracker (owner request --
    # the ml water tracker climbs by itself yet showed no tag).
    #   record -- an auto_src resets it when a cycle completes (it also
    #            counts by itself if its unit is shots/ml);
    #   count  -- no auto_src, but its shots/ml counter climbs on its
    #            own (recording the maintenance stays manual);
    #   ""     -- fully manual (days unit, no auto_src).
    # v0.24.0: a linked CLEANING profile also makes it `record`.
    proc _item_auto_kind {id} {
        variable settings
        if {[_item_auto_src $id] ne ""} { return record }
        if {[_item_cleaning_profile $id] ne ""} { return record }
        set u ""
        catch { set u [dict get $settings(item_$id) unit] }
        if {$u in {shots ml}} { return count }
        return ""
    }

    proc _state_color {state} {
        variable L
        switch -- $state {
            ok      { return $L(col_ok) }
            amber   { return $L(col_amber) }
            red     { return $L(col_red) }
            unset   { return $L(col_unset) }
            default { return $L(col_unknown) }
        }
    }

    # ------------------------------------------------------------------
    #  Recording (Pass 3). The ONLY write this feature performs is to the
    #  plugin's own settings array, persisted via `plugins save_settings`.
    #
    #  Flow: card Record button -> request_record (remembers the item,
    #  opens the confirm page; burr install gets its own page with the
    #  offset stepper) -> Confirm records + returns, Cancel just returns.
    #  Any settings-page show clears the pending flag (a stuck flag must
    #  never survive a page switch).
    # ------------------------------------------------------------------

    variable pending_item ""
    # v0.25.0: where Record's confirm returns (the list, or Detail when
    # Record was tapped there). Reset by every return and by the list
    # page's show (stuck-flag rule).
    variable record_return MaintenanceTracker_settings
    variable burr_offset 0
    variable bottle_size 18900

    proc request_record {id {from MaintenanceTracker_settings}} {
        variable pending_item
        variable record_return
        variable burr_offset
        variable bottle_size
        variable settings
        if {![info exists settings(item_$id)]} {
            catch { msg "MaintenanceTracker: unknown item to record: $id" }
            return
        }
        set pending_item $id
        set record_return MaintenanceTracker_settings
        if {$from eq "MaintenanceTracker_detail"} { set record_return MaintenanceTracker_detail }
        if {$id eq "burr_install"} {
            set burr_offset 0
            open_page MaintenanceTracker_confirm_burr
        } elseif {$id eq "water_bottle"} {
            # v0.13.0: the bottle confirm page carries size steppers (the
            # burr-offset mechanism) -- built-ins have no Edit page, so
            # the swap confirmation is where the size gets adjusted.
            set bottle_size 18900
            catch {
                set t [dict get $settings(item_$id) threshold]
                if {[string is wide -strict $t] && $t >= 500} { set bottle_size $t }
            }
            open_page MaintenanceTracker_confirm_bottle
        } else {
            open_page MaintenanceTracker_confirm
        }
    }

    proc adjust_bottle_size {delta} {
        variable bottle_size
        set v $bottle_size
        if {![string is wide -strict $v]} { set v 18900 }
        incr v $delta
        if {$v < 500} { set v 500 }
        if {$v > 99999} { set v 99999 }
        set bottle_size $v
    }

    proc cancel_record {} {
        variable pending_item
        set pending_item ""
        _return_to_page [_take_record_return]
    }

    # v0.25.0: the confirm pages' way back, consumed once.
    proc _take_record_return {} {
        variable record_return
        set r $record_return
        set record_return MaintenanceTracker_settings
        if {$r ne "MaintenanceTracker_detail"} { set r MaintenanceTracker_settings }
        return $r
    }

    proc adjust_burr_offset {delta} {
        variable burr_offset
        set v [expr {$burr_offset + $delta}]
        if {$v < 0} { set v 0 }
        if {$v > 99999} { set v 99999 }
        set burr_offset $v
    }

    # v0.5.0: recording APPENDS to the item's event log (newest last,
    # capped at the newest 20) instead of overwriting last_done, which is
    # now derived via _sync_last_done. `source` is always `manual` here;
    # `auto` is reserved for a future auto-detection pass.
    proc record_pending {} {
        variable pending_item
        variable burr_offset
        variable bottle_size
        variable settings
        if {$pending_item eq "" || ![info exists settings(item_$pending_item)]} {
            catch { msg "MaintenanceTracker: nothing pending to record" }
            _return_to_page [_take_record_return]
            return
        }
        set d $settings(item_$pending_item)
        set events {}
        catch { set events [dict get $d events] }
        set ev [dict create ts [clock seconds] source manual note ""]
        # v0.13.0: ml-unit records carry the meter reading as the new
        # baseline (see _ml_baseline -- Undo then reverts it for free).
        if {[dict exists $d unit] && [dict get $d unit] eq "ml"} {
            set total 0
            catch {
                if {[string is double -strict $settings(water_total_ml)]} {
                    set total $settings(water_total_ml)
                }
            }
            dict set ev ml $total
        }
        lappend events $ev
        if {[llength $events] > 20} { set events [lrange $events end-19 end] }
        dict set d events $events
        set d [_sync_last_done $d]
        if {$pending_item eq "burr_install"} {
            set off $burr_offset
            if {![string is wide -strict $off] || $off < 0} { set off 0 }
            dict set d pre_sdb_offset $off
        }
        if {$pending_item eq "water_bottle"} {
            set sz $bottle_size
            if {[string is wide -strict $sz] && $sz >= 500 && $sz <= 99999} {
                dict set d threshold $sz
            }
        }
        set settings(item_$pending_item) $d
        save_settings
        catch { msg "MaintenanceTracker: recorded '$pending_item' done now" }
        set pending_item ""
        _invalidate_status_cache
        _return_to_page [_take_record_return]
    }

    # v0.5.0: pop the newest event off an item's log; last_done falls back
    # to the previous event (or 0 / unset when the log empties). The only
    # write is the plugin's own settings save. Returns 1 on success, 0 if
    # there was nothing to undo (the Detail page hides Undo in that case,
    # this guard is belt-and-braces).
    proc undo_last_event {id} {
        variable settings
        if {$id eq "" || ![info exists settings(item_$id)]} { return 0 }
        set d $settings(item_$id)
        set events {}
        catch { set events [dict get $d events] }
        if {[llength $events] == 0} { return 0 }
        dict set d events [lrange $events 0 end-1]
        set d [_sync_last_done $d]
        set settings(item_$id) $d
        save_settings
        catch { msg "MaintenanceTracker: undid last record of '$id'" }
        _invalidate_status_cache
        return 1
    }

    # v0.29.0 (Pass 35): remove ONE chosen record (owner: a stray entry
    # from before the v0.24.0 fix sat in the middle of a history, where
    # Undo cannot reach). The second destructive capability of this
    # plugin, reached only through Detail's two-tap confirm. The removed
    # event is escrowed in settings(last_removed_event) (newest only, the
    # last_deleted_custom pattern) and logged; last_done is re-derived.
    # Removing the newest is exactly undo_last_event, so that path keeps
    # its own proc and wording; this one refuses the newest index.
    proc remove_event {id idx} {
        variable settings
        if {$id eq "" || ![info exists settings(item_$id)]} { return 0 }
        set d $settings(item_$id)
        set events {}
        catch { set events [dict get $d events] }
        set n [llength $events]
        if {![string is integer -strict $idx] || $idx < 0 || $idx >= $n - 1} { return 0 }
        set ev [lindex $events $idx]
        set settings(last_removed_event) [dict create id $id index $idx event $ev removed [clock seconds]]
        dict set d events [lreplace $events $idx $idx]
        set d [_sync_last_done $d]
        set settings(item_$id) $d
        save_settings
        set when "?"
        catch { set when [clock format [dict get $ev ts] -format {%Y-%m-%d %H:%M}] }
        catch { msg "MaintenanceTracker: removed the $when record of '$id' ([expr {$idx + 1}] of $n)" }
        _invalidate_status_cache
        return 1
    }

    # ------------------------------------------------------------------
    #  Custom trackers (Pass 8). Adding writes one new item dict into the
    #  plugin's own settings; deleting (the ONE destructive capability of
    #  this pass) removes a custom item dict from the same settings after
    #  a two-tap confirm on its Detail page, keeping the removed dict in
    #  settings(last_deleted_custom) as a hand-recoverable escrow.
    #  Built-in items can never be deleted.
    # ------------------------------------------------------------------

    variable add_label ""
    variable add_unit days
    variable add_threshold 60
    variable add_error ""
    variable add_icon wrench
    # v0.21.0: auto-record source chosen at creation ("" / clean /
    # descale), via the Add page's header toggle.
    variable add_auto ""

    # Per-unit starting thresholds (also applied when the unit toggles:
    # a days threshold makes no sense as a shots threshold and vice versa).
    proc _add_default_threshold {unit} {
        if {$unit eq "shots"} { return 400 }
        if {$unit eq "ml"} { return 10000 }
        return 60
    }

    proc open_add {} {
        variable add_label
        variable add_unit
        variable add_threshold
        variable add_error
        variable add_icon
        variable add_auto
        set add_label ""
        set add_unit days
        set add_threshold [_add_default_threshold days]
        set add_error ""
        set add_icon wrench
        set add_auto ""
        open_page MaintenanceTracker_add
    }

    # v0.21.0: same cycle as the Edit page's row, for the Add header
    # toggle: off -> Clean cycle -> Descale cycle -> off.
    proc toggle_add_auto {} {
        variable add_auto
        switch -- $add_auto {
            ""      { set add_auto clean }
            clean   { set add_auto descale }
            default { set add_auto "" }
        }
    }

    proc toggle_add_unit {} {
        variable add_unit
        variable add_threshold
        # v0.13.0: three units now -- cycle days -> shots -> ml -> days.
        switch -- $add_unit {
            days    { set add_unit shots }
            shots   { set add_unit ml }
            default { set add_unit days }
        }
        set add_threshold [_add_default_threshold $add_unit]
    }

    proc adjust_add_threshold {delta} {
        variable add_threshold
        set v $add_threshold
        if {![string is wide -strict $v]} { set v [_add_default_threshold days] }
        incr v $delta
        if {$v < 1} { set v 1 }
        if {$v > 99999} { set v 99999 }
        set add_threshold $v
    }

    proc cancel_add {} {
        _return_to_page MaintenanceTracker_settings
    }

    proc add_save {} {
        variable add_label
        variable add_unit
        variable add_threshold
        variable add_error
        variable settings

        # The entry is free text from the Android keyboard: collapse all
        # whitespace runs (incl. newlines) and trim before validating.
        set label [string trim [regsub -all {\s+} $add_label " "]]
        if {$label eq ""} {
            set add_error [translate "Give the tracker a name first."]
            _refresh_add_page
            return
        }
        if {[string length $label] > 40} {
            set add_error [translate "Keep the name under 40 characters."]
            _refresh_add_page
            return
        }
        if {$add_unit ni {days shots ml}} { set add_unit days }
        set thr $add_threshold
        if {![string is wide -strict $thr] || $thr < 1} {
            set thr [_add_default_threshold $add_unit]
        }

        variable add_icon
        variable picker_icons
        set icon $add_icon
        if {$icon ni $picker_icons} { set icon wrench }
        # v0.21.0: the auto source is chosen at creation via the header
        # toggle (still editable later on the Edit page).
        variable add_auto
        set asrc $add_auto
        if {$asrc ni {{} clean descale}} { set asrc "" }
        set id "custom_$settings(custom_next)"
        incr settings(custom_next)
        set settings(item_$id) [dict create \
            label $label last_done 0 note "" threshold $thr unit $add_unit \
            icon $icon events {} auto_src $asrc]
        lappend settings(custom_ids) $id
        save_settings
        catch { msg "MaintenanceTracker: added custom tracker '$id' ($label, $thr $add_unit, auto '$asrc')" }
        _invalidate_status_cache
        # Land the user on the card page that shows the new tracker.
        catch { ::dui::pages::MaintenanceTracker_settings::goto_last_page }
        _return_to_page MaintenanceTracker_settings
    }

    proc _refresh_add_page {} {
        if {[catch { ::dui::pages::MaintenanceTracker_add::refresh } err]} {
            catch { msg "MaintenanceTracker: add-page refresh failed: $err" }
        }
    }

    # Stepper deltas match the unit's magnitude: fine steps for days,
    # coarse for shots. Shared by the Add and Edit pages.
    proc _step_deltas_for {unit} {
        if {$unit eq "shots"} { return {-100 -10 10 100} }
        if {$unit eq "ml"}    { return {-1000 -100 100 1000} }
        return {-10 -1 1 10}
    }

    proc _add_step_deltas {} {
        variable add_unit
        return [_step_deltas_for $add_unit]
    }

    # ------------------------------------------------------------------
    #  Icon picker row, shared by the Add and Edit pages (Pass 13).
    #  Cells: white backdrop whose outline marks the selection, glyph
    #  dtext, invisible tap dbutton. Tags pick<k>_bg/_ic/_tap per page.
    # ------------------------------------------------------------------

    # v0.29.1: `inset` narrows the grid on both sides (New Tracker's
    # picker sits inside a card); 0 = the full content width (Edit).
    proc _build_picker_row {page y1 select_cmd {inset 0}} {
        variable picker_icons
        variable picker_cols
        variable L
        set np [llength $picker_icons]
        set cols $picker_cols
        set cell_w [expr {int(round(88 * $L(scale)))}]
        set cell_h [expr {int(round(60 * $L(scale)))}]
        # Horizontal gap sized for a full row of picker_cols cells;
        # rows after the first sit L(xs) below the previous one.
        set grid_x [expr {$L(left_x) + $inset}]
        set cell_gap [expr {($L(content_w) - 2 * $inset - $cols * $cell_w) / ($cols - 1)}]
        set row_gap $L(xs)
        for {set k 0} {$k < $np} {incr k} {
            set row [expr {$k / $cols}]
            set col [expr {$k % $cols}]
            set ry1 [expr {$y1 + $row * ($cell_h + $row_gap)}]
            set ry2 [expr {$ry1 + $cell_h}]
            set cx1 [expr {$grid_x + $col * ($cell_w + $cell_gap)}]
            set cx2 [expr {$cx1 + $cell_w}]
            rounded_rect $page $cx1 $ry1 $cx2 $ry2 $L(btn_radius) \
                -fill $L(card_bg) -outline $L(card_outline) -width 2 -tags pick${k}_bg
            set nm [lindex $picker_icons $k]
            if {[_is_vector_icon $nm]} {
                # v0.17.0: this cell's icon is a plugin-drawn stroke
                # icon, not a glyph. Segments pick${k}_ic_s<i>.
                _add_vector_icon $page pick${k}_ic $nm \
                    [expr {($cx1 + $cx2) / 2}] [expr {($ry1 + $ry2) / 2}] \
                    $L(vec_box_pick) $L(icon_idle) 0
            } else {
                dui add dtext $page [expr {($cx1 + $cx2) / 2}] [expr {($ry1 + $ry2) / 2}] \
                    -tags pick${k}_ic \
                    -text [_glyph_for $nm] \
                    -font $L(font_icon_pick) -fill $L(icon_idle) -anchor center -justify center
            }
            dui add dbutton $page $cx1 $ry1 $cx2 $ry2 -tags pick${k}_tap \
                -command [list {*}$select_cmd $k]
        }
    }

    proc _refresh_picker {page selected} {
        variable picker_icons
        variable L
        for {set k 0} {$k < [llength $picker_icons]} {incr k} {
            set nm [lindex $picker_icons $k]
            if {$nm eq $selected} {
                set bw 5
                set boc $L(icon_sel)
                set ic $L(icon_sel)
            } else {
                set bw 2
                set boc $L(card_outline)
                set ic $L(icon_idle)
            }
            catch { dui item config $page pick${k}_bg -outline $boc -width $bw }
            if {[_is_vector_icon $nm]} {
                _config_vector_icon $page pick${k}_ic $nm $ic
            } else {
                catch { dui item config $page pick${k}_ic -fill $ic }
            }
        }
        # v0.18.0: say what the selected icon depicts, right on the
        # "Icon:" label (one item -- no new layout zone to collide).
        catch { dui item config $page icon_label \
            -text "[translate {Icon:}]  [_icon_label $selected]" }
    }

    # ------------------------------------------------------------------
    #  Edit a custom tracker (Pass 12 rename, extended in Pass 13 to
    #  threshold and icon). Only label/threshold/icon change; the event
    #  history, counting unit and id stay untouched. Built-ins keep
    #  their fixed names and glyphs.
    # ------------------------------------------------------------------

    variable edit_item ""
    variable edit_label ""
    variable edit_threshold 60
    variable edit_unit days
    variable edit_icon wrench
    # v0.20.0: the tracker's auto-record source ("" / clean / descale),
    # cycled by the Edit page's Change button.
    variable edit_auto ""
    variable edit_error ""
    # v0.15.0: two-step delete lives on the Edit page (customs only).
    variable edit_delete_armed 0
    # v0.25.0 (Pass 31): the link, as a DRAFT in _item_link's shape
    # ("" | descale | clean | {profile fn title}). Link / Unlink only
    # change the draft; Save writes it with everything else, Cancel
    # drops it -- an accidental Unlink is one Cancel away from undone.
    variable edit_link ""

    proc open_edit {id} {
        variable edit_item
        variable edit_label
        variable edit_threshold
        variable edit_unit
        variable edit_icon
        variable edit_auto
        variable edit_link
        variable edit_error
        variable edit_delete_armed
        variable picker_icons
        variable settings
        # v0.15.0 (consolidation): every tracker is editable.
        if {![info exists settings(item_$id)]} { return 0 }
        set edit_delete_armed 0
        set d $settings(item_$id)
        set edit_item $id
        set edit_label [_item_label $id]
        set edit_threshold 60
        catch {
            set t [dict get $d threshold]
            if {[string is wide -strict $t] && $t >= 1} { set edit_threshold $t }
        }
        set edit_unit days
        catch {
            if {[dict get $d unit] in {days shots ml}} { set edit_unit [dict get $d unit] }
        }
        # v0.16.0: seed the STORED icon even when it is no longer a
        # picker candidate (retired names keep rendering from the FA
        # table). edit_save only writes icons that are in the picker,
        # so an unrelated Save can never silently swap a legacy icon
        # for the fallback; the picker simply shows no selection until
        # the user taps a new one.
        set edit_icon wrench
        catch {
            set ic [dict get $d icon]
            if {$ic ne ""} { set edit_icon $ic }
        }
        set edit_auto [_item_auto_src $id]
        set edit_link [_item_link $id]
        set edit_error ""
        open_page MaintenanceTracker_edit
        return 1
    }

    # v0.25.0: Edit-page link controls (draft only, no save here). The
    # profile capture applies link_profile's checks: a loaded profile,
    # with a file (v0.24.1).
    proc edit_link_profile {} {
        variable edit_link
        variable edit_error
        variable edit_delete_armed
        if {$edit_delete_armed} { return 0 }
        set fn ""
        catch { set fn [string trim $::settings(profile_filename)] }
        if {$fn eq ""} {
            set edit_error [translate "No profile is loaded in the app. Pick one in the profile list first."]
            return 0
        }
        if {[_profile_file_exists $fn] eq "0"} {
            set edit_error [translate "No saved file for this profile. Pick it in the profile list first."]
            return 0
        }
        set title $fn
        catch {
            set t [string trim $::settings(profile_title)]
            if {$t ne ""} { set title $t }
        }
        set edit_link [list profile [string range $fn 0 127] [string range $title 0 79]]
        set edit_error ""
        return 1
    }

    proc edit_link_kind {kind} {
        variable edit_link
        variable edit_error
        variable edit_delete_armed
        if {$edit_delete_armed || $kind ni {descale clean}} { return 0 }
        set edit_link $kind
        set edit_error ""
        return 1
    }

    proc edit_unlink {} {
        variable edit_link
        variable edit_error
        variable edit_delete_armed
        if {$edit_delete_armed} { return 0 }
        set edit_link ""
        set edit_error ""
        return 1
    }

    # Human text for a link draft (Edit page value).
    proc _link_text {link} {
        switch -- [lindex $link 0] {
            profile { return [_short_text [lindex $link 2] 40] }
            descale { return [translate "Descale (app)"] }
            clean   { return [translate "Clean cycle (app)"] }
        }
        return [translate "none"]
    }

    # Writes a link draft into an item dict (pure; edit_save saves).
    proc _apply_link {d link} {
        dict unset d profile_fn
        dict unset d profile_title
        dict unset d link_kind
        switch -- [lindex $link 0] {
            profile {
                dict set d profile_fn [lindex $link 1]
                dict set d profile_title [lindex $link 2]
            }
            descale - clean {
                dict set d link_kind [lindex $link 0]
            }
        }
        return $d
    }

    # v0.20.0: cycle the Edit page's auto-record source through the
    # available detectors: off -> Clean cycle -> Descale cycle -> off.
    proc toggle_edit_auto {} {
        variable edit_auto
        switch -- $edit_auto {
            ""      { set edit_auto clean }
            clean   { set edit_auto descale }
            default { set edit_auto "" }
        }
    }

    proc cancel_edit {} {
        variable edit_delete_armed
        # Standard: while a destructive confirm is armed, the left
        # button's first job is to disarm; leaving takes another tap.
        if {$edit_delete_armed} {
            set edit_delete_armed 0
            _refresh_edit_page
            return
        }
        _return_to_page MaintenanceTracker_detail
    }

    proc adjust_edit_threshold {delta} {
        variable edit_threshold
        set v $edit_threshold
        if {![string is wide -strict $v]} { set v 60 }
        incr v $delta
        if {$v < 1} { set v 1 }
        if {$v > 99999} { set v 99999 }
        set edit_threshold $v
    }

    proc edit_save {} {
        variable edit_item
        variable edit_label
        variable edit_threshold
        variable edit_icon
        variable edit_auto
        variable edit_link
        variable edit_error
        variable edit_delete_armed
        variable picker_icons
        variable settings
        set id $edit_item
        if {$edit_delete_armed} { return }
        if {![info exists settings(item_$id)]} {
            _return_to_page MaintenanceTracker_settings
            return
        }
        # Same normalization and limits as add_save: collapse whitespace
        # runs (incl. newlines from the Android keyboard) and trim.
        set label [string trim [regsub -all {\s+} $edit_label " "]]
        if {$label eq ""} {
            set edit_error [translate "Give the tracker a name first."]
            _refresh_edit_page
            return
        }
        if {[string length $label] > 40} {
            set edit_error [translate "Keep the name under 40 characters."]
            _refresh_edit_page
            return
        }
        set d $settings(item_$id)
        dict set d label $label
        set thr $edit_threshold
        if {[string is wide -strict $thr] && $thr >= 1 && $thr <= 99999} {
            dict set d threshold $thr
        }
        if {$edit_icon in $picker_icons} {
            dict set d icon $edit_icon
        }
        # v0.20.0: auto-record source. Only validated values are written;
        # "" (off) is a deliberate, storable choice.
        if {$edit_auto in {{} clean descale}} {
            dict set d auto_src $edit_auto
        }
        # v0.25.0: the link draft (Link / Unlink moved here from Detail).
        set old_link [_item_link $id]
        if {$edit_link ne $old_link} {
            set d [_apply_link $d $edit_link]
            _disarm_clean
        }
        set settings(item_$id) $d
        save_settings
        catch { msg "MaintenanceTracker: edited '$id' ($label, [dict get $d threshold] [dict get $d unit], [dict get $d icon], auto '[dict get $d auto_src]', link '[lindex $edit_link 0] [lindex $edit_link 1]')" }
        set edit_error ""
        # The threshold feeds the state math -- recompute on return.
        _invalidate_status_cache
        _return_to_page MaintenanceTracker_detail
    }

    proc _refresh_edit_page {} {
        if {[catch { ::dui::pages::MaintenanceTracker_edit::refresh } err]} {
            catch { msg "MaintenanceTracker: edit-page refresh failed: $err" }
        }
    }

    # ------------------------------------------------------------------
    #  Linked profile (Pass 26, v0.22.0). A tracker may remember one
    #  profile (filename + title, the DrinkMenu "use current" capture)
    #  and its Detail page offers to load it -- the owner's backflush
    #  alert becomes: wrench, card, Load profile, GHC button. Loading
    #  copies DrinkMenu v1.16.0's To-machine tap (tablet-verified):
    #  busy guard, ::select_profile <filename> (core vars.tcl:2932),
    #  then the 1 s debounced save_settings + save_settings_to_de1.
    #  Nothing here starts a flow. Link / Unlink write the item dict
    #  through the plugin's own save path; status_summary builds its
    #  entries from named keys, so its frozen shape is unaffected.
    # ------------------------------------------------------------------

    # The outcome shown in the Detail page's message slot, and the
    # timers behind it.
    variable prof_note ""
    variable prof_note_id ""
    variable prof_send_id ""

    # {filename title} or "" when the tracker links no profile.
    proc _item_profile {id} {
        variable settings
        if {![info exists settings(item_$id)]} { return "" }
        set d $settings(item_$id)
        # v0.23.0: a Descale / Clean link replaces any profile link.
        if {[dict exists $d link_kind] && [dict get $d link_kind] in {descale clean}} { return "" }
        if {![dict exists $d profile_fn]} { return "" }
        set fn [string trim [dict get $d profile_fn]]
        if {$fn eq ""} { return "" }
        set title $fn
        catch {
            set t [string trim [dict get $d profile_title]]
            if {$t ne ""} { set title $t }
        }
        return [list $fn $title]
    }

    # Ellipsis cut for one-line value cells (pure).
    proc _short_text {s max} {
        if {[string length $s] <= $max} { return $s }
        return "[string range $s 0 [expr {$max - 4}]]..."
    }

    proc _set_prof_note {txt} {
        variable prof_note
        variable prof_note_id
        set prof_note $txt
        catch { after cancel $prof_note_id }
        set prof_note_id [after 4000 ::plugins::MaintenanceTracker::_clear_prof_note]
    }

    proc _clear_prof_note {} {
        variable prof_note
        set prof_note ""
        _refresh_action_pages
    }

    # v0.26.0: the pages that show action notes / the Clean arm (Detail
    # and, since Pass 32, Steps) repaint only when on screen.
    proc _refresh_action_pages {} {
        foreach pg {MaintenanceTracker_detail MaintenanceTracker_steps} {
            if {[_page_is_current $pg]} {
                if {[catch { ::dui::pages::${pg}::refresh } err]} {
                    catch { msg "MaintenanceTracker: $pg refresh failed: $err" }
                }
            }
        }
    }

    # DrinkMenu's _machine_busy, copied: "" when a tap may change the
    # loaded profile, else the state name that refuses it.
    proc _machine_busy {} {
        set handle unknown
        catch { set handle $::de1(device_handle) }
        if {$handle eq "0"} { return "" }
        set name unknown
        catch { set name $::de1_num_state($::de1(state)) }
        if {$name in {Idle Sleep GoingToSleep}} { return "" }
        return $name
    }

    proc link_profile {id} {
        variable settings
        if {![info exists settings(item_$id)]} { return 0 }
        set fn ""
        catch { set fn [string trim $::settings(profile_filename)] }
        if {$fn eq ""} {
            _set_prof_note [translate "No profile is loaded in the app. Pick one in the profile list first."]
            return 0
        }
        # v0.24.1: a profile with no file (e.g. loaded from a shot) would
        # make a link that can never load again.
        if {[_profile_file_exists $fn] eq "0"} {
            catch { msg -WARN "MaintenanceTracker: not linking '$fn' to '$id': no profiles/$fn.tcl" }
            _set_prof_note [translate "No saved file for this profile. Pick it in the profile list first."]
            return 0
        }
        set title $fn
        catch {
            set t [string trim $::settings(profile_title)]
            if {$t ne ""} { set title $t }
        }
        set d $settings(item_$id)
        dict set d profile_fn [string range $fn 0 127]
        dict set d profile_title [string range $title 0 79]
        dict unset d link_kind
        set settings(item_$id) $d
        save_settings
        catch { msg "MaintenanceTracker: linked profile '$fn' to '$id'" }
        _set_prof_note "[translate {Linked:}] $title"
        return 1
    }

    # v0.23.0: removes WHATEVER the tracker links (profile, Descale or
    # Clean) -- the name is kept for the v0.22.0 call sites.
    proc unlink_profile {id} {
        variable settings
        if {![info exists settings(item_$id)]} { return 0 }
        set d $settings(item_$id)
        if {![dict exists $d profile_fn] && ![dict exists $d link_kind]} { return 0 }
        dict unset d profile_fn
        dict unset d profile_title
        dict unset d link_kind
        set settings(item_$id) $d
        _disarm_clean
        save_settings
        catch { msg "MaintenanceTracker: unlinked '$id'" }
        _set_prof_note [translate "Unlinked."]
        return 1
    }

    # ------------------------------------------------------------------
    #  v0.23.0 (Pass 27): a tracker may link the app's own DESCALE or
    #  CLEAN action (Settings > Machine > Maintenance) instead of a
    #  profile. Stored as `link_kind` descale | clean in the item dict.
    #
    #  Descale opens the app's "Prepare to descale" page through
    #  `show_settings descale_prepare` -- the entry the app's own descale
    #  warning uses (skins/default/standard_includes.tcl:32): it takes a
    #  fresh settings backup first, so the stock page's Cancel (-> the
    #  Machine tab) and that tab's Cancel restore the CURRENT settings,
    #  not a stale backup. The user still presses the stock "Descale
    #  now"; MT never calls start_decaling.
    #
    #  Clean has no stock confirmation page (the Machine tab's Clean
    #  button calls start_cleaning directly), so MT asks first: the
    #  first tap arms for 8 s, the second calls the core's
    #  start_cleaning. Connected + not busy, or it refuses.
    #
    #  Both leave MT's own dialog stack one close_dialog per level first
    #  (the _return_to_page loop), so the core's page load never has to
    #  unwind stacked dialogs (page_stack truncation bug).
    # ------------------------------------------------------------------

    variable clean_armed 0
    variable clean_arm_id ""

    # "" | {profile <fn> <title>} | descale | clean
    proc _item_link {id} {
        variable settings
        if {![info exists settings(item_$id)]} { return "" }
        set d $settings(item_$id)
        if {[dict exists $d link_kind]} {
            set k [dict get $d link_kind]
            if {$k in {descale clean}} { return $k }
        }
        set prof [_item_profile $id]
        if {$prof ne ""} { return [list profile {*}$prof] }
        return ""
    }

    proc link_action {id kind} {
        variable settings
        if {$kind ni {descale clean}} { return 0 }
        if {![info exists settings(item_$id)]} { return 0 }
        set d $settings(item_$id)
        dict unset d profile_fn
        dict unset d profile_title
        dict set d link_kind $kind
        set settings(item_$id) $d
        _disarm_clean
        save_settings
        catch { msg "MaintenanceTracker: linked the app's $kind action to '$id'" }
        if {$kind eq "descale"} {
            _set_prof_note [translate "Linked: the app's Descale."]
        } else {
            _set_prof_note [translate "Linked: the app's Clean cycle."]
        }
        return 1
    }

    proc _disarm_clean {} {
        variable clean_armed
        variable clean_arm_id
        set clean_armed 0
        if {$clean_arm_id ne ""} {
            after cancel $clean_arm_id
            set clean_arm_id ""
        }
    }

    # The 8 s timeout: disarm, and repaint the Detail page if it shows.
    proc _clean_arm_expired {} {
        variable clean_arm_id
        set clean_arm_id ""
        _disarm_clean
        _refresh_action_pages
    }

    # Leave this plugin's own dialog stack, one close_dialog per level
    # (the _return_to_page loop): stops at the first page that is not
    # ours. Failures are logged.
    proc _leave_own_dialogs {} {
        set prev ""
        for {set i 0} {$i < 10} {incr i} {
            set cur ""
            catch { set cur [dui page current] }
            if {![string match "MaintenanceTracker_*" $cur]} { return }
            if {$cur eq $prev} { break }
            set prev $cur
            if {[catch { dui page close_dialog } err]} {
                catch { msg "MaintenanceTracker: close_dialog failed leaving for a machine page: $err" }
                break
            }
        }
    }

    # Public: open the app's "Prepare to descale" page. Returns 1 when
    # the page was asked for.
    proc open_linked_descale {id} {
        if {[_item_link $id] ne "descale"} { return 0 }
        set busy [_machine_busy]
        if {$busy ne ""} {
            _set_prof_note "[translate {Machine busy}] ($busy). [translate {Wait until it is idle.}]"
            return 0
        }
        if {[llength [info commands ::show_settings]] == 0} {
            catch { msg "MaintenanceTracker: the app's show_settings is missing, cannot open descale_prepare" }
            _set_prof_note [translate "The app's descale page is not available."]
            return 0
        }
        catch { msg "MaintenanceTracker: opening the app's descale page for '$id'" }
        _leave_own_dialogs
        if {[catch { ::show_settings descale_prepare } err]} {
            catch { msg "MaintenanceTracker: ERROR opening descale_prepare: $err" }
            return 0
        }
        return 1
    }

    # Public: the Clean action's tap. First tap arms (returns "armed"),
    # the second starts the machine's clean cycle through the core's
    # start_cleaning (returns "started"); refusals return "refused".
    proc clean_tap {id} {
        variable clean_armed
        variable clean_arm_id
        if {[_item_link $id] ne "clean"} { return "refused" }
        set handle 0
        catch { set handle $::de1(device_handle) }
        if {$handle eq "0" || $handle eq ""} {
            _disarm_clean
            _set_prof_note [translate "The machine is not connected."]
            return "refused"
        }
        set busy [_machine_busy]
        if {$busy ne ""} {
            _disarm_clean
            _set_prof_note "[translate {Machine busy}] ($busy). [translate {Wait until it is idle.}]"
            return "refused"
        }
        if {!$clean_armed} {
            set clean_armed 1
            if {$clean_arm_id ne ""} { after cancel $clean_arm_id }
            set clean_arm_id [after 8000 ::plugins::MaintenanceTracker::_clean_arm_expired]
            return "armed"
        }
        _disarm_clean
        if {[llength [info commands ::start_cleaning]] == 0} {
            catch { msg "MaintenanceTracker: the app's start_cleaning is missing" }
            _set_prof_note [translate "The app's clean cycle is not available."]
            return "refused"
        }
        catch { msg "MaintenanceTracker: starting the app's clean cycle for '$id'" }
        _leave_own_dialogs
        if {[catch { ::start_cleaning } err]} {
            catch { msg "MaintenanceTracker: ERROR starting the clean cycle: $err" }
            return "refused"
        }
        return "started"
    }

    # v0.27.0: the ONE way this plugin changes the app's profile (Load,
    # Start, and the automatic switch-back all come here): file check
    # first (v0.24.1), the core's select_profile, then the debounced
    # save + send to the machine (DrinkMenu v1.16.0's To-machine tap).
    # Returns "" on success, else the reason for the page's message line.
    proc _switch_profile {fn} {
        variable prof_send_id
        if {[_profile_file_exists $fn] eq "0"} {
            return [translate "Profile file missing. Unlink and link it again."]
        }
        set r ""
        if {[catch { set r [::select_profile $fn] } err]} {
            catch { msg "MaintenanceTracker: select_profile '$fn' failed: $err" }
            return [translate "Could not load the profile (see the log)."]
        }
        if {$r eq "-1"} {
            return [translate "Profile file missing. Unlink and link it again."]
        }
        catch { after cancel $prof_send_id }
        set prof_send_id [after 1000 {
            if {[catch {
                save_settings
                save_settings_to_de1
            } err]} {
                catch { msg "MaintenanceTracker: could not send the machine settings: $err" }
            }
        }]
        return ""
    }

    # Public: load the tracker's linked profile into the app (the
    # machine receives it on the debounced send). Returns 1 on success.
    proc load_linked_profile {id} {
        set prof [_item_profile $id]
        if {$prof eq ""} { return 0 }
        lassign $prof fn title
        set busy [_machine_busy]
        if {$busy ne ""} {
            _set_prof_note "[translate {Machine busy}] ($busy). [translate {Wait until it is idle.}]"
            return 0
        }
        # v0.24.1: never hand the core a missing file (logged here, the
        # check itself lives in _switch_profile).
        if {[_profile_file_exists $fn] eq "0"} {
            catch { msg -WARN "MaintenanceTracker: linked profile '$fn' for '$id' has no profiles/$fn.tcl; not loading" }
        }
        set why [_switch_profile $fn]
        if {$why ne ""} {
            _set_prof_note $why
            return 0
        }
        catch { msg "MaintenanceTracker: loaded linked profile '$fn' for '$id'" }
        _set_prof_note "[translate {Loaded:}] $title. [translate {Press the espresso button on the machine.}]"
        return 1
    }

    # ------------------------------------------------------------------
    #  Profile run with switch-back (Pass 33, v0.27.0). Start on a
    #  profile-linked tracker's Steps page remembers the loaded (espresso)
    #  profile, loads the cleaning profile and asks for the group head's
    #  espresso button (a GHC machine refuses tablet-started espresso:
    #  de1app-core machine.tcl:936, vars.tcl:3476). The remembered profile
    #  comes back:
    #    - 5 s after the cleaning run's after_flow_complete (the core
    #      saves the shot file and MT auto-records in that same event, so
    #      the profile must still be the cleaning one then), or 20 s after
    #      the Espresso state ends if the run never reached the pour;
    #    - on "Switch back now";
    #    - 10 minutes after Start if the group head was never pressed;
    #    - on the next app start, if the app restarted in between.
    #  Never while the machine is busy (retries every 5 s), and only when
    #  the cleaning profile is still the loaded one -- a profile the user
    #  picked meanwhile is theirs, and the switch-back is dropped. The
    #  pending switch-back is persisted in settings(run_restore) so a
    #  restart cannot strand the cleaning profile.
    # ------------------------------------------------------------------

    variable run_timeout_s 600
    variable run_started 0
    variable _run_timeout_id ""
    variable _run_restore_id ""
    variable _run_retry_id ""
    variable _run_tries 0

    # The pending switch-back as a dict, or "" when none.
    proc _run_pending {} {
        variable settings
        set rr ""
        catch { set rr $settings(run_restore) }
        if {![string is list $rr] || [llength $rr] % 2 != 0 || ![dict exists $rr prev_fn] \
                || ![dict exists $rr clean_fn]} {
            return ""
        }
        return $rr
    }

    proc _run_pending_for {id} {
        set rr [_run_pending]
        if {$rr eq ""} { return 0 }
        return [expr {[dict exists $rr item] && [dict get $rr item] eq $id}]
    }

    proc _loaded_profile {} {
        set fn ""
        catch { set fn [string trim $::settings(profile_filename)] }
        return $fn
    }

    proc _cancel_run_timers {} {
        variable _run_timeout_id
        variable _run_restore_id
        variable _run_retry_id
        foreach v {_run_timeout_id _run_restore_id _run_retry_id} {
            set idv [set $v]
            if {$idv ne ""} { catch { after cancel $idv } }
            set $v ""
        }
    }

    proc _clear_run {} {
        variable settings
        variable run_started
        variable _run_tries
        _cancel_run_timers
        set run_started 0
        set _run_tries 0
        set settings(run_restore) ""
        save_settings
    }

    # Public: the Steps page's Start on a profile-linked tracker. Returns
    # "armed" or "refused" (the reason lands in the message line).
    proc start_profile_run {id} {
        variable settings
        variable run_started
        variable run_timeout_s
        variable _run_timeout_id
        set prof [_item_profile $id]
        if {$prof eq ""} { return "refused" }
        lassign $prof clean_fn clean_title
        set busy [_machine_busy]
        if {$busy ne ""} {
            _set_prof_note "[translate {Machine busy}] ($busy). [translate {Wait until it is idle.}]"
            return "refused"
        }
        if {[_profile_file_exists $clean_fn] eq "0"} {
            _set_prof_note [translate "Profile file missing. Unlink and link it again."]
            return "refused"
        }
        set changed 0
        catch { set changed $::settings(profile_has_changed) }
        if {$changed eq "1"} {
            _set_prof_note [translate "Your current profile has unsaved changes. Save it first, then tap Start."]
            return "refused"
        }
        set cur [_loaded_profile]
        set cur_title $cur
        catch {
            set t [string trim $::settings(profile_title)]
            if {$t ne ""} { set cur_title $t }
        }
        # The profile to come back to. A switch-back already pending (a
        # cleaning profile loaded by an earlier Start) keeps ITS espresso
        # profile -- never "come back" to a cleaning profile.
        set rr [_run_pending]
        if {$rr ne "" && [string equal -nocase $cur [dict get $rr clean_fn]]} {
            set prev_fn [dict get $rr prev_fn]
            set prev_title [dict get $rr prev_title]
        } elseif {[string equal -nocase $cur $clean_fn]} {
            _set_prof_note [translate "The cleaning profile is already loaded. Pick your espresso profile in the app first, so it can come back afterwards."]
            return "refused"
        } else {
            set prev_fn $cur
            set prev_title $cur_title
        }
        if {$prev_fn eq "" || [_profile_file_exists $prev_fn] eq "0"} {
            _set_prof_note [translate "Your current profile has no saved file, so it could not come back. Pick a saved profile first."]
            return "refused"
        }
        _cancel_run_timers
        set settings(run_restore) [dict create prev_fn $prev_fn prev_title $prev_title \
            clean_fn $clean_fn clean_title $clean_title item $id ts [clock seconds]]
        save_settings
        set why [_switch_profile $clean_fn]
        if {$why ne ""} {
            _clear_run
            _set_prof_note $why
            return "refused"
        }
        set run_started 0
        set _run_timeout_id [after [expr {$run_timeout_s * 1000}] ::plugins::MaintenanceTracker::_run_timeout]
        catch { msg -NOTICE "MaintenanceTracker: run armed for '$id': '$clean_fn' loaded, '$prev_fn' comes back after the run (or in [expr {$run_timeout_s / 60}] min)" }
        _refresh_action_pages
        return "armed"
    }

    # Public: "Switch back now".
    proc cancel_profile_run {} {
        if {[_run_pending] eq ""} { return 0 }
        _restore_profile cancel
        return 1
    }

    proc _run_timeout {} {
        variable _run_timeout_id
        variable run_started
        set _run_timeout_id ""
        if {!$run_started} { _restore_profile timeout }
    }

    # Switch back to the remembered profile. Idempotent; never throws.
    proc _restore_profile {reason} {
        variable _run_retry_id
        variable _run_tries
        set _run_retry_id ""
        if {[catch {
            set rr [_run_pending]
            if {$rr ne ""} {
                set busy [_machine_busy]
                if {$busy ne "" && $_run_tries < 120} {
                    incr _run_tries
                    set _run_retry_id [after 5000 [list ::plugins::MaintenanceTracker::_restore_profile $reason]]
                } elseif {$busy ne ""} {
                    catch { msg -WARN "MaintenanceTracker: switch-back gave up, machine busy ($busy) for 10 min; '[dict get $rr clean_fn]' stays loaded" }
                    _clear_run
                    _refresh_action_pages
                } else {
                    set cur [_loaded_profile]
                    set prev_fn [dict get $rr prev_fn]
                    set prev_title [dict get $rr prev_title]
                    if {![string equal -nocase $cur [dict get $rr clean_fn]]} {
                        catch { msg -NOTICE "MaintenanceTracker: switch-back dropped ($reason): '$cur' is loaded now, not the cleaning profile" }
                        _clear_run
                    } else {
                        set why [_switch_profile $prev_fn]
                        _clear_run
                        if {$why eq ""} {
                            catch { msg -NOTICE "MaintenanceTracker: switched back to '$prev_fn' ($reason)" }
                            _set_prof_note "[translate {Switched back to}] $prev_title."
                        } else {
                            catch { msg -WARN "MaintenanceTracker: switch-back to '$prev_fn' failed ($reason): $why" }
                            _set_prof_note "[translate {Could not switch back to}] $prev_title: $why"
                        }
                    }
                    _refresh_action_pages
                }
            }
        } err]} {
            catch { msg "MaintenanceTracker: switch-back error: $err" }
        }
        return
    }

    # State-change hook (from _on_state_change).
    proc _run_on_state {this prev} {
        variable run_started
        variable _run_timeout_id
        variable _run_restore_id
        set rr [_run_pending]
        if {$rr eq ""} { return }
        if {$this eq "Espresso" && $prev ne "Espresso"} {
            if {[string equal -nocase [_loaded_profile] [dict get $rr clean_fn]]} {
                set run_started 1
                if {$_run_timeout_id ne ""} { catch { after cancel $_run_timeout_id } }
                set _run_timeout_id ""
                catch { msg -NOTICE "MaintenanceTracker: cleaning run started with '[dict get $rr clean_fn]'" }
            } else {
                catch { msg -NOTICE "MaintenanceTracker: a run started with '[_loaded_profile]', not the cleaning profile; switch-back dropped" }
                _clear_run
            }
        } elseif {$prev eq "Espresso" && $this ne "Espresso" && $run_started} {
            # Fallback for a run that never reached the pour (no
            # after_flow_complete); the flow-complete path replaces it.
            if {$_run_restore_id ne ""} { catch { after cancel $_run_restore_id } }
            set _run_restore_id [after 20000 [list ::plugins::MaintenanceTracker::_restore_profile run-ended]]
        }
    }

    # Flow-complete hook (from _on_flow_complete, after auto-record).
    proc _run_on_flow_complete {} {
        variable run_started
        variable _run_restore_id
        if {[_run_pending] eq "" || !$run_started} { return }
        if {$_run_restore_id ne ""} { catch { after cancel $_run_restore_id } }
        set _run_restore_id [after 5000 [list ::plugins::MaintenanceTracker::_restore_profile run-complete]]
    }

    # App start: a switch-back left pending by a restart. Runs once, 20 s
    # after main (profile and connection settled).
    proc _resume_pending_run {} {
        set rr [_run_pending]
        if {$rr eq ""} { return }
        catch { msg -NOTICE "MaintenanceTracker: a switch-back was pending at start; restoring '[dict get $rr prev_fn]'" }
        _restore_profile restart
    }

    # ------------------------------------------------------------------
    #  Instructions (Pass 32, v0.26.0). Every tracker gets a Steps page:
    #  numbered instructions plus ONE coloured action (the link's: Load
    #  profile / Open Descale / Start Clean, or Mark done). Steps come
    #  from the item's own `steps` list when it has one (the Pass 34
    #  editor writes it; nothing writes it yet) or from a built-in
    #  template picked by keywords in the tracker's name, so every user,
    #  and every custom tracker, starts with sensible steps. "{start}" in
    #  a template becomes the link-aware "how to start it" line.
    #  Read-only: nothing on this page writes anything new.
    # ------------------------------------------------------------------

    variable steps_max 8
    variable steps_item ""
    variable step_templates {
        backflush_detergent {
            "Put the blind basket in the portafilter."
            "Add one scoop of Cafetto Evo powder (or your cleaner's dose) to the basket."
            "Add a little warm water and stir until the powder dissolves."
            "Lock the portafilter into the group head."
            "{start}"
            "When it finishes, rinse the basket and run a water backflush to clear the detergent."
        }
        backflush_water {
            "Put the clean blind basket in the portafilter, with no detergent."
            "Lock the portafilter into the group head."
            "{start}"
            "When it finishes, remove the portafilter and run a short flush."
        }
        steam_wand_soak {
            "Dissolve half a Rinza tablet in 500 ml of water in a milk jug."
            "Submerge the tip of the steam wand in the solution."
            "Leave it to soak for 15 to 30 minutes."
            "Wipe the wand and purge steam for a few seconds to rinse it."
        }
        ball_joint_grease {
            "Let the steam wand cool down completely."
            "Apply a thin layer of food-safe silicone grease to the ball joint O-rings."
            "Move the wand through its full range to spread the grease."
        }
        descale {
            "Mix the descaling solution (citric acid: use the dose on the pack)."
            "{start}"
            "Afterwards, rinse the water tank and refill it with fresh water."
        }
        drip_tray {
            "Pull out the drip tray and lift off its grate."
            "Empty it and wash both parts in warm soapy water."
            "Rinse, dry and slide the tray back in."
        }
        water_tank {
            "Lift out the water tank and empty it."
            "Wash it with warm water and a soft brush, leaving no soap behind."
            "Rinse it well, refill with fresh water and put it back."
        }
        drain {
            "Check the drain pipe for coffee build-up and kinks."
            "Flush it with hot water (a little espresso machine cleaner if it smells)."
            "Make sure it runs freely into the drain before refitting it."
        }
        gasket_change {
            "Let the machine cool down and remove the portafilter."
            "Take out the shower screen and pry out the old group gasket."
            "Clean the gasket seat, then press the new gasket in evenly."
            "Refit the shower screen and pull a test shot to check for leaks."
        }
        group_inspection {
            "With the machine cool, check the group gasket for cracks, hardness or leaks."
            "Check the shower screen for coffee build-up."
            "Wipe the group head with a damp cloth or a group brush."
            "Plan a gasket change if it leaks or feels hard."
        }
        burr_clean {
            "Unplug the grinder."
            "Open the burr chamber and brush the burrs and the chute clean."
            "Reassemble, then grind a few beans to purge it."
        }
        burr_install {
            "Unplug the grinder and remove the old burrs."
            "Clean the burr carrier and the chamber."
            "Fit the new burrs and re-zero the grind setting."
            "Grind a few doses to season them before dialling in."
        }
        water_filter {
            "Remove the old filter cartridge."
            "Soak or flush the new cartridge as its instructions say."
            "Fit it and run some water through before the next shot."
        }
        water_supply {
            "Swap the empty water bottle for a full one."
            "Check that the intake tube reaches the bottom and the lid seals."
            "Tap Mark done to restart the bottle meter."
        }
        generic {
            "Do the maintenance task."
            "Check that everything is refitted, clean and dry."
            "Tap Mark done to record it."
        }
    }

    # Keyword rules, first match wins (the tracker's name, lower-cased,
    # plus its id). Grease before steam wand, water before backflush's
    # detergent default, supply/bottle before tank/filter.
    variable step_rules {
        {ball joint|grease|silicone}                           ball_joint_grease
        {backflush.*water|water.*backflush}                    backflush_water
        {backflush|back flush|cafiza|cafetto|detergent}        backflush_detergent
        {rinza|steam wand|steam tip|wand}                      steam_wand_soak
        {descal|citric}                                        descale
        {drip tray|drip}                                       drip_tray
        {water supply|bottle|water_bottle}                     water_supply
        {water tank|tank}                                      water_tank
        {drain}                                                drain
        {inspect}                                              group_inspection
        {gasket.*(change|replace|new)|(change|replace|new).*gasket|group_gasket} gasket_change
        {gasket|group head|inspect}                            group_inspection
        {burr.*(install|replace|new|change)|burr_install}      burr_install
        {burr|grinder}                                         burr_clean
        {filter}                                               water_filter
    }

    proc _steps_template_id {id} {
        variable step_rules
        set hay [string tolower "[_item_label $id] $id"]
        foreach {re tpl} $step_rules {
            if {[regexp -- $re $hay]} { return $tpl }
        }
        return generic
    }

    # The link-aware "how to start it" step.
    proc _start_step {kind} {
        switch -- $kind {
            profile { return [translate "Tap Start below, then press the espresso button on the group head."] }
            descale { return [translate "Tap Open Descale below and follow the app's steps."] }
            clean   { return [translate "Tap Start Clean below, then tap it again to confirm."] }
        }
        return [translate "Load the cleaning profile in the app, then press the espresso button on the group head."]
    }

    # The tracker's steps, ready to show: its own list when it has one
    # (trimmed, empties dropped, capped), else the template; "{start}"
    # resolved for the tracker's current link.
    proc _item_steps {id} {
        set raw [_item_steps_raw $id]
        set kind [lindex [_item_link $id] 0]
        set out {}
        foreach st $raw {
            if {$st eq "{start}"} { set st [_start_step $kind] }
            lappend out [translate $st]
        }
        return $out
    }

    # The Steps page's coloured action for a tracker's link.
    proc _steps_action_label {id} {
        variable clean_armed
        switch -- [lindex [_item_link $id] 0] {
            profile { return [expr {[_run_pending_for $id] ? [translate "Switch back now"] : [translate "Start"]}] }
            descale { return [translate "Open Descale"] }
            clean   { return [expr {$clean_armed ? [translate "Yes, start Clean"] : [translate "Start Clean"]}] }
        }
        return [translate "Mark done"]
    }

    proc open_steps {id} {
        variable steps_item
        variable settings
        if {![info exists settings(item_$id)]} { return 0 }
        set steps_item $id
        _disarm_clean
        open_page MaintenanceTracker_steps
        return 1
    }

    # ------------------------------------------------------------------
    #  Step editor (Pass 34, v0.28.0) -- DrinkMenu's Method editor
    #  pattern: every change edits a DRAFT (se_draft); only Save writes,
    #  once, into the tracker's own `steps` list (settings.tdb via
    #  save_settings). Cancel drops the draft. A draft equal to the
    #  built-in template is stored as NO list (the key is removed), so
    #  the tracker keeps following the template. "{start}" (the
    #  link-aware start line) stays a token until its row is edited.
    # ------------------------------------------------------------------

    variable se_item ""
    variable se_draft {}
    variable se_mode list
    variable se_form_idx -1
    variable se_text ""
    variable se_error ""
    variable step_max_chars 120

    # The template's raw steps ({start} kept as a token).
    proc _steps_template_raw {id} {
        variable step_templates
        variable steps_max
        return [lrange [dict get $step_templates [_steps_template_id $id]] 0 [expr {$steps_max - 1}]]
    }

    # The tracker's raw steps: its own list, else the template.
    proc _item_steps_raw {id} {
        variable settings
        variable steps_max
        variable step_max_chars
        set own {}
        if {[info exists settings(item_$id)] && [dict exists $settings(item_$id) steps]} {
            foreach st [dict get $settings(item_$id) steps] {
                set st [string trim $st]
                if {$st ne ""} { lappend own [string range $st 0 [expr {$step_max_chars - 1}]] }
            }
        }
        if {[llength $own] > 0} { return [lrange $own 0 [expr {$steps_max - 1}]] }
        return [_steps_template_raw $id]
    }

    # One draft row as shown ({start} resolved for the tracker's link).
    proc _se_display {st} {
        variable se_item
        if {$st eq "{start}"} { return [_start_step [lindex [_item_link $se_item] 0]] }
        return $st
    }

    # Typed text, cleaned: whitespace runs (incl. Android newlines) -> one
    # space, trimmed, capped.
    proc _se_clean {txt} {
        variable step_max_chars
        set t [string trim [regsub -all {\s+} $txt " "]]
        return [string range $t 0 [expr {$step_max_chars - 1}]]
    }

    proc open_step_editor {id} {
        variable settings
        variable se_item
        variable se_draft
        variable se_mode
        variable se_form_idx
        variable se_text
        variable se_error
        if {![info exists settings(item_$id)]} { return 0 }
        set se_item $id
        set se_draft [_item_steps_raw $id]
        set se_mode list
        set se_form_idx -1
        set se_text ""
        set se_error ""
        open_page MaintenanceTracker_stepedit
        return 1
    }

    proc se_move {i delta} {
        variable se_draft
        variable se_mode
        if {$se_mode ne "list"} { return 0 }
        set j [expr {$i + $delta}]
        if {$i < 0 || $j < 0 || $i >= [llength $se_draft] || $j >= [llength $se_draft]} { return 0 }
        set a [lindex $se_draft $i]
        lset se_draft $i [lindex $se_draft $j]
        lset se_draft $j $a
        return 1
    }

    proc se_remove {i} {
        variable se_draft
        variable se_mode
        variable se_error
        if {$se_mode ne "list" || $i < 0 || $i >= [llength $se_draft]} { return 0 }
        set se_draft [lreplace $se_draft $i $i]
        set se_error ""
        return 1
    }

    # Open the form for row i (-1 = a new step at the end).
    proc se_edit {i} {
        variable se_draft
        variable se_mode
        variable se_form_idx
        variable se_text
        variable se_error
        variable steps_max
        if {$se_mode ne "list"} { return 0 }
        if {$i < 0} {
            if {[llength $se_draft] >= $steps_max} {
                set se_error [translate "Eight steps is the most a tracker can hold."]
                return 0
            }
            set se_form_idx -1
            set se_text ""
        } else {
            if {$i >= [llength $se_draft]} { return 0 }
            set se_form_idx $i
            set se_text [_se_display [lindex $se_draft $i]]
        }
        set se_error ""
        set se_mode form
        return 1
    }

    proc se_form_save {} {
        variable se_draft
        variable se_mode
        variable se_form_idx
        variable se_text
        variable se_error
        if {$se_mode ne "form"} { return 0 }
        set t [_se_clean $se_text]
        if {$t eq ""} {
            set se_error [translate "Type the step first, or tap Cancel."]
            return 0
        }
        if {$se_form_idx < 0} {
            lappend se_draft $t
        } else {
            set old [lindex $se_draft $se_form_idx]
            # An untouched start line stays the link-aware token.
            if {!($old eq "{start}" && $t eq [_se_clean [_se_display $old]])} {
                lset se_draft $se_form_idx $t
            }
        }
        set se_mode list
        set se_form_idx -1
        set se_text ""
        set se_error ""
        return 1
    }

    proc se_form_cancel {} {
        variable se_mode
        variable se_form_idx
        variable se_text
        variable se_error
        set se_mode list
        set se_form_idx -1
        set se_text ""
        set se_error ""
        return 1
    }

    proc se_reset {} {
        variable se_item
        variable se_draft
        variable se_mode
        variable se_error
        if {$se_mode ne "list"} { return 0 }
        set se_draft [_steps_template_raw $se_item]
        set se_error ""
        return 1
    }

    # The ONE write of this editor: the draft into the tracker's `steps`
    # (or the key removed when the draft is the template). One save.
    proc se_save {} {
        variable settings
        variable se_item
        variable se_draft
        variable se_mode
        variable se_error
        variable steps_max
        if {$se_mode ne "list"} { return 0 }
        set id $se_item
        if {![info exists settings(item_$id)]} { return 0 }
        set clean {}
        foreach st $se_draft {
            if {$st eq "{start}"} { lappend clean $st ; continue }
            set t [_se_clean $st]
            if {$t ne ""} { lappend clean $t }
        }
        set clean [lrange $clean 0 [expr {$steps_max - 1}]]
        if {[llength $clean] == 0} {
            set se_error [translate "Keep at least one step, or tap Reset to default."]
            return 0
        }
        set d $settings(item_$id)
        if {$clean eq [_steps_template_raw $id]} {
            dict unset d steps
            set how "template"
        } else {
            dict set d steps $clean
            set how "[llength $clean] own steps"
        }
        set settings(item_$id) $d
        save_settings
        catch { msg "MaintenanceTracker: steps saved for '$id' ($how)" }
        set se_error ""
        return 1
    }

    # Delete one CUSTOM tracker: unlist it and remove its item dict, both
    # before a single save. The removed dict is kept (newest only) in
    # settings(last_deleted_custom) -- save_array_to_file writes the whole
    # array, so the unset key is gone from settings.tdb after the save
    # (de1app-core/plugins.tcl:252-253) and apply_defaults only ever
    # creates items listed in custom_ids, so it cannot come back.
    proc delete_custom {id} {
        variable settings
        if {![_is_custom_id $id]} { return 0 }
        if {![info exists settings(item_$id)]} { return 0 }
        set settings(last_deleted_custom) [dict create \
            id $id deleted [clock seconds] item $settings(item_$id)]
        set idx [lsearch -exact $settings(custom_ids) $id]
        if {$idx >= 0} {
            set settings(custom_ids) [lreplace $settings(custom_ids) $idx $idx]
        }
        # v0.15.0: customs can be hidden too -- a deleted one must not
        # leave a stale id occupying a hidden slot.
        set hidx [lsearch -exact $settings(hidden_ids) $id]
        if {$hidx >= 0} {
            set settings(hidden_ids) [lreplace $settings(hidden_ids) $hidx $hidx]
        }
        unset settings(item_$id)
        save_settings
        catch { msg "MaintenanceTracker: deleted custom tracker '$id'" }
        _invalidate_status_cache
        return 1
    }

    # ------------------------------------------------------------------
    #  Hide / restore built-in trackers (v0.8.0). Non-destructive and
    #  fully reversible: hiding only lists the id in hidden_ids -- the
    #  item dict, its history and its offset stay untouched, and Restore
    #  All (on the Add page) brings everything back.
    # ------------------------------------------------------------------

    # v0.15.0: any existing tracker may hide, at most hide_max at once
    # (the Detail page disables the button at the cap; this guard is
    # belt-and-braces).
    proc hide_item {id} {
        variable settings
        variable hide_max
        if {![info exists settings(item_$id)]} { return 0 }
        if {$id in $settings(hidden_ids)} { return 0 }
        if {[llength $settings(hidden_ids)] >= $hide_max} {
            catch { msg "MaintenanceTracker: hide refused, $hide_max trackers already hidden" }
            return 0
        }
        lappend settings(hidden_ids) $id
        save_settings
        catch { msg "MaintenanceTracker: hid tracker '$id'" }
        _invalidate_status_cache
        return 1
    }

    # v0.10.0: per-item restore (replaces the all-or-nothing Restore All).
    proc unhide_item {id} {
        variable settings
        set idx [lsearch -exact $settings(hidden_ids) $id]
        if {$idx < 0} { return 0 }
        set settings(hidden_ids) [lreplace $settings(hidden_ids) $idx $idx]
        save_settings
        catch { msg "MaintenanceTracker: restored hidden tracker '$id'" }
        _invalidate_status_cache
        return 1
    }
}

# ===========================================================================
#  Settings page -- Pass 3: card list, 5 cards per page, Prev/Next paging
# ===========================================================================

namespace eval ::dui::pages::MaintenanceTracker_settings {

    variable card_page_size 5
    variable card_page 0

    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::MaintenanceTracker::L L
        variable card_page_size

        ::plugins::MaintenanceTracker::_page_bg $page

        set lx $L(left_x)
        set rx $L(right_x)
        set cx [expr {($lx + $rx) / 2}]

        dui add dtext $page $cx $L(header_title_y) -tags page_title \
            -text [translate "Maintenance Tracker"] \
            -font $L(font_title) -width $L(content_w) -fill $L(text_hi) \
            -anchor center -justify center
        dui add dtext $page $cx $L(header_subtitle_y) -tags subtitle \
            -text [translate "Tap Record when you have done a maintenance task. Counters come from your shot history."] \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) \
            -anchor center -justify center

        # v0.19.0: theme toggle, top-right corner of the header (the
        # design system's mode-button slot). Face = moon in light mode
        # / sun in dark (FA glyphs from the app's table; text fallback
        # when icons are unavailable). Created with the CURRENT theme's
        # face -- non-empty either way (the v0.7.1 empty-label rule) --
        # and relabeled by refresh.
        set th_y1 [expr {int(round(11 * $L(scale)))}]
        dui add dbutton $page [expr {$rx - $L(btn_h)}] $th_y1 \
            $rx [expr {$th_y1 + $L(btn_h)}] \
            -tags btn_theme -label [::plugins::MaintenanceTracker::_theme_button_face] \
            -command ::plugins::MaintenanceTracker::toggle_theme \
            -label_font [expr {$L(have_icons) ? $L(font_icon_plate) : $L(font_button)}] \
            -style mt_btn

        # Toolbar: paging status left, Prev/Next right (SHE toolbar zone).
        dui add dtext $page $lx $L(toolbar_y0) -tags toolbar_status -text "" \
            -font $L(font_caption) \
            -width [expr {$L(content_w) - 2 * ($L(btn_w_std) + $L(sm))}] \
            -fill $L(text_mut) -anchor nw -justify left
        set next_x1 [expr {$rx - $L(btn_w_std)}]
        set prev_x1 [expr {$next_x1 - $L(sm) - $L(btn_w_std)}]
        dui add dbutton $page $prev_x1 $L(toolbar_y0) [expr {$prev_x1 + $L(btn_w_std)}] $L(toolbar_y1) \
            -tags prev_page -label [translate "Prev"] \
            -command {::dui::pages::MaintenanceTracker_settings::scroll_cards -1} \
            -label_font $L(font_button) -style mt_btn
        dui add dbutton $page $next_x1 $L(toolbar_y0) $rx $L(toolbar_y1) \
            -tags next_page -label [translate "Next"] \
            -command {::dui::pages::MaintenanceTracker_settings::scroll_cards 1} \
            -label_font $L(font_button) -style mt_btn

        # Card rows (Pass 10 Service Bay): bg + tinted icon plate + name
        # + state word + counter + segmented wear bar with amber tick +
        # caption + Record button each.
        set plate_x1 [expr {$lx + $L(card_pad_x)}]
        set plate_x2 [expr {$plate_x1 + $L(plate_size)}]
        set text_x [expr {$plate_x2 + $L(md)}]
        set btn_x2 [expr {$rx - $L(card_pad_x)}]
        set btn_x1 [expr {$btn_x2 - $L(card_btn_w)}]
        set bar_x1 $text_x
        set bar_x2 [expr {$btn_x1 - $L(xl)}]
        set bar_w [expr {$bar_x2 - $bar_x1}]
        # Name text stops 260 ref-px short of the bar's right edge -- the
        # counter's zone -- so the two can never collide.
        set name_w [expr {$bar_w - int(round(260 * $L(scale)))}]
        set seg_stride [expr {($bar_w + $L(bar_seg_gap)) / $L(bar_segs)}]
        set seg_w [expr {$seg_stride - $L(bar_seg_gap)}]
        set amber_frac 0.8
        catch {
            if {[string is double -strict $::plugins::MaintenanceTracker::settings(amber_fraction)]} {
                set amber_frac $::plugins::MaintenanceTracker::settings(amber_fraction)
            }
        }
        set tick_x [expr {$bar_x1 + int(round($bar_w * $amber_frac))}]

        for {set i 0} {$i < $card_page_size} {incr i} {
            set top [expr {$L(list_top) + $i * ($L(card_h) + $L(card_gap))}]
            set bottom [expr {$top + $L(card_h)}]

            ::plugins::MaintenanceTracker::rounded_rect $page $lx $top $rx $bottom $L(btn_radius) \
                -fill $L(card_bg) -outline $L(card_outline) -width 2 -tags row${i}_bg

            set plate_y1 [expr {$top + ($L(card_h) - $L(plate_size)) / 2}]
            ::plugins::MaintenanceTracker::rounded_rect $page $plate_x1 $plate_y1 \
                $plate_x2 [expr {$plate_y1 + $L(plate_size)}] $L(plate_radius) \
                -fill $L(tint_unset) -outline $L(tint_unset) -width 1 -tags row${i}_plate
            dui add dtext $page [expr {($plate_x1 + $plate_x2) / 2}] \
                [expr {$plate_y1 + $L(plate_size) / 2}] -tags row${i}_icon -text "" \
                -font $L(font_icon_plate) -fill $L(col_unset) -anchor center -justify center
            # v0.17.0: each plate also carries both vector icons, born
            # hidden; refresh shows at most one (the framework's own
            # stacked-but-exclusive mechanism, like mt_hide/bar_delete
            # was). Tags row<i>_vsw_s* / row<i>_vgf_s*.
            ::plugins::MaintenanceTracker::_add_vector_icon $page row${i}_vsw steam-wand \
                [expr {($plate_x1 + $plate_x2) / 2}] [expr {$plate_y1 + $L(plate_size) / 2}] \
                $L(vec_box_plate) $L(col_unset) 1
            ::plugins::MaintenanceTracker::_add_vector_icon $page row${i}_vgf gasket-flat \
                [expr {($plate_x1 + $plate_x2) / 2}] [expr {$plate_y1 + $L(plate_size) / 2}] \
                $L(vec_box_plate) $L(col_unset) 1

            dui add dtext $page $text_x [expr {$top + $L(card_name_dy)}] -tags row${i}_line1 -text "" \
                -font $L(font_primary) -width $name_w -fill $L(text_hi) -anchor w -justify left
            dui add dtext $page $text_x [expr {$top + $L(card_state_dy)}] -tags row${i}_state -text "" \
                -font $L(font_caption_b) -width $name_w -fill $L(text_mut) -anchor w -justify left
            dui add dtext $page $bar_x2 [expr {$top + $L(card_name_dy)}] -tags row${i}_cnt -text "" \
                -font $L(font_primary) -fill $L(text_hi) -anchor e -justify right
            # v0.20.0: "AUTO" tag under the counter (right-aligned, in
            # the counter's reserved 260-ref-px zone -- the left texts
            # stop at name_w, so nothing can collide). Shown only for
            # trackers with an auto_src; accent color, both themes.
            # Non-empty creation label (v0.7.1 rule) + -initial_state
            # hidden (v0.10.1 no-flash rule for start-hidden items).
            dui add dtext $page $bar_x2 [expr {$top + $L(card_state_dy)}] -tags row${i}_auto \
                -text [translate "AUTO"] -font $L(font_caption_b) -fill $L(icon_sel) \
                -anchor e -justify right -initial_state hidden

            # Wear bar: fixed segment rects whose -fill reconfigures (the
            # dot mechanism -- no canvas coords manipulation), plus a
            # static tick at the amber threshold.
            set bar_yc [expr {$top + $L(card_bar_dy)}]
            set bar_y1 [expr {$bar_yc - $L(bar_h) / 2}]
            set bar_y2 [expr {$bar_yc + $L(bar_h) / 2}]
            for {set j 0} {$j < $L(bar_segs)} {incr j} {
                set sx1 [expr {$bar_x1 + $j * $seg_stride}]
                dui add canvas_item rect $page $sx1 $bar_y1 [expr {$sx1 + $seg_w}] $bar_y2 \
                    -fill $L(bar_track) -outline $L(bar_track) -tags row${i}_seg${j}
            }
            dui add canvas_item rect $page [expr {$tick_x - 2}] [expr {$bar_y1 - $L(xs)}] \
                [expr {$tick_x + 2}] [expr {$bar_y2 + $L(xs)}] \
                -fill $L(bar_tick) -outline $L(bar_tick) -tags row${i}_tick

            dui add dtext $page $text_x [expr {$top + $L(card_cap_dy)}] -tags row${i}_line3 -text "" \
                -font $L(font_caption) -width [expr {$bar_w}] -fill $L(text_mut) -anchor w -justify left

            set btn_y1 [expr {$top + ($L(card_h) - $L(card_btn_h)) / 2}]
            dui add dbutton $page $btn_x1 $btn_y1 $btn_x2 [expr {$btn_y1 + $L(card_btn_h)}] \
                -tags row${i}_btn -label [translate "Record"] \
                -command "::dui::pages::MaintenanceTracker_settings::card_record $i" \
                -label_font $L(font_button) -style mt_btn

            # v0.5.0: invisible tap zone over the card's text area, opening
            # the item's Detail page. A shape-less, label-less dbutton is
            # the core's own invisible-clickable-rect mechanism (the tap
            # binding of EVERY dui button lives on exactly such a rect,
            # de1app-core/dui.tcl:10247-10253 + 10300). Created after the
            # text lines so its clickable rect sits above them. Its right
            # edge stops an xl-gap short of the Record button's left edge:
            # the two interactive rectangles never overlap (v0.3.0 rule).
            dui add dbutton $page $lx $top [expr {$btn_x1 - $L(xl)}] $bottom \
                -tags row${i}_open \
                -command "::dui::pages::MaintenanceTracker_settings::card_open $i"
        }

        # Bottom bar: Done left, Add Tracker center (v0.7.0), Diagnostics
        # right. All three fit with room to spare: Done ends at lx+400,
        # the wide center button spans cx +/- 240, Diagnostics starts at
        # rx-400 (virtual px) -- every gap is far beyond the md minimum.
        # v0.21.2: mt_ prefix on tags that DrinkMenu also used (done/
        # back/cancel/save/hide). Tk canvas tags are canvas-GLOBAL, and
        # the core's press flash (dui.tcl:9181) itemconfigures by bare
        # <tag>-btn -- a same-named pressfill button in ANY plugin
        # repaints ours to its color on every press.
        dui add dbutton $page $lx $L(bar_y0) [expr {$lx + $L(btn_w_std)}] $L(bar_y1) \
            -tags mt_done -label [translate "Done"] \
            -command ::plugins::MaintenanceTracker::page_done \
            -label_font $L(font_button) -style mt_btn
        dui add dbutton $page [expr {$cx - $L(btn_w_wide) / 2}] $L(bar_y0) \
            [expr {$cx + $L(btn_w_wide) / 2}] $L(bar_y1) \
            -tags bar_add -label [translate "New Tracker"] \
            -command ::plugins::MaintenanceTracker::open_add \
            -label_font $L(font_button) -style mt_btn
        dui add dbutton $page [expr {$rx - $L(btn_w_std)}] $L(bar_y0) $rx $L(bar_y1) \
            -tags bar_diag -label [translate "Diagnostics"] \
            -command ::plugins::MaintenanceTracker::open_diagnostics \
            -label_font $L(font_button) -style mt_btn
    }

    # v0.9.0: the rendered order is worst-first, computed by refresh and
    # cached here so taps map to exactly what is on screen. Falls back
    # to the canonical visible order before the first refresh.
    variable displayed_ids {}

    # Item ids shown on the current card page, in row order.
    proc _page_items {} {
        variable card_page_size
        variable card_page
        variable displayed_ids
        set ids $displayed_ids
        if {[llength $ids] == 0} {
            set ids [::plugins::MaintenanceTracker::_visible_item_ids]
        }
        set first [expr {$card_page * $card_page_size}]
        return [lrange $ids $first [expr {$first + $card_page_size - 1}]]
    }

    # v0.7.0: called after adding a tracker so the user lands on the card
    # page that shows it (customs always sort last).
    proc goto_last_page {} {
        variable card_page_size
        variable card_page
        set n [llength [::plugins::MaintenanceTracker::_visible_item_ids]]
        set card_page [expr {($n - 1) / $card_page_size}]
    }

    proc card_record {row} {
        set ids [_page_items]
        if {$row < [llength $ids]} {
            ::plugins::MaintenanceTracker::request_record [lindex $ids $row]
        }
    }

    proc card_open {row} {
        set ids [_page_items]
        if {$row < [llength $ids]} {
            ::plugins::MaintenanceTracker::open_detail [lindex $ids $row]
        }
    }

    proc scroll_cards {delta} {
        variable card_page_size
        variable card_page
        set n [llength [::plugins::MaintenanceTracker::_visible_item_ids]]
        set last_page [expr {($n - 1) / $card_page_size}]
        set p [expr {$card_page + $delta}]
        if {$p < 0} { set p 0 }
        if {$p > $last_page} { set p $last_page }
        if {$p == $card_page} { return }
        set card_page $p
        # Paging needs no fresh DB pass -- render from the cached summary.
        if {[catch { refresh } err]} {
            catch { msg "MaintenanceTracker: card paging failed: $err" }
        }
    }

    proc refresh {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::MaintenanceTracker::L L
        variable card_page_size
        variable card_page
        set _t0 [clock milliseconds]

        set s [::plugins::MaintenanceTracker::status_summary]

        # v0.9.0: worst-first ordering. Rank by state (red, amber, ok,
        # unknown, never-recorded), stable within a rank via the
        # composite integer key. Recomputed on every refresh from the
        # same summary the cards render, so taps always match the screen.
        variable displayed_ids
        set displayed_ids [::plugins::MaintenanceTracker::_worst_first_ids $s \
            [::plugins::MaintenanceTracker::_visible_item_ids]]

        set n [llength $displayed_ids]
        # v0.7.0: deleting (or v0.8.0 hiding) a tracker can shrink the
        # list below the current page -- clamp so the page is never empty.
        set last_page [expr {($n - 1) / $card_page_size}]
        if {$card_page > $last_page} { set card_page $last_page }
        if {$card_page < 0} { set card_page 0 }
        set ids [_page_items]
        set first [expr {$card_page * $card_page_size + 1}]
        set last [expr {$card_page * $card_page_size + [llength $ids]}]

        # Toolbar: item range + database headline.
        set status "[translate {Items}] $first-$last [translate {of}] $n   ·   [translate {worst first}]"
        upvar #0 ::plugins::MaintenanceTracker::diag diag
        if {[dict exists $s sdb_ok] && [dict get $s sdb_ok]} {
            append status "   ·   [translate {Shots in database:}] $diag(total_counted)"
            if {$diag(total_excluded) ne "" && $diag(total_excluded) > 0} {
                append status " ([translate {excluded as cleaning:}] $diag(total_excluded))"
            }
        } elseif {[dict exists $s ok] && [dict get $s ok]} {
            append status "   ·   [translate {Shot database unavailable -- see Diagnostics}]"
        }
        ::plugins::MaintenanceTracker::_cfg $page toolbar_status -text $status

        # v0.19.0: theme button face follows the current theme.
        # (dbutton -label stays a real dui call: label sub-item mapping.)
        catch { dui item config $page btn_theme \
            -label [::plugins::MaintenanceTracker::_theme_button_face] }

        # Cards (Pass 10 Service Bay render; Pass 23 cached-canvas path:
        # _set_vis/_cfg keep the v0.10.1 st:hidden semantics -- see the
        # helper block -- while skipping dui's per-call tag resolution).
        for {set i 0} {$i < $card_page_size} {incr i} {
            if {$i < [llength $ids]} {
                set id [lindex $ids $i]
                # row icon is owned by _apply_item_icon below (glyph OR
                # vector), so it is not in the blanket show list.
                set vtags {}
                foreach tag {bg plate line1 state cnt line3 tick} {
                    lappend vtags row${i}_$tag
                }
                for {set j 0} {$j < $L(bar_segs)} {incr j} {
                    lappend vtags row${i}_seg${j}
                }
                lappend vtags row${i}_btn* row${i}_open*
                ::plugins::MaintenanceTracker::_set_vis $page $vtags 1

                if {[dict exists $s items $id]} {
                    set entry [dict get $s items $id]
                    set state [dict get $entry state]
                } else {
                    set entry [dict create state unknown last_done 0]
                    set state unknown
                }
                set color [::plugins::MaintenanceTracker::_state_color $state]
                set tint $L(tint_unknown)
                catch { set tint $L(tint_$state) }

                ::plugins::MaintenanceTracker::_cfg $page row${i}_line1 \
                    -text [::plugins::MaintenanceTracker::_item_label $id]
                ::plugins::MaintenanceTracker::_cfg $page row${i}_state \
                    -text [string toupper [::plugins::MaintenanceTracker::_state_word $state]] \
                    -fill $color
                # v0.20.0: AUTO tag on trackers with an auto_src;
                # v0.21.0: shots/ml trackers count by themselves too, so
                # the tag now says WHICH automation this tracker has --
                # AUTO-RECORD (resets itself on a detected cycle) or
                # AUTO-COUNT (counter climbs by itself; recording the
                # maintenance stays manual). Fully manual = no tag.
                switch -- [::plugins::MaintenanceTracker::_item_auto_kind $id] {
                    record {
                        ::plugins::MaintenanceTracker::_cfg $page row${i}_auto \
                            -text [translate "AUTO-RECORD"]
                        ::plugins::MaintenanceTracker::_set_vis $page [list row${i}_auto] 1
                    }
                    count {
                        ::plugins::MaintenanceTracker::_cfg $page row${i}_auto \
                            -text [translate "AUTO-COUNT"]
                        ::plugins::MaintenanceTracker::_set_vis $page [list row${i}_auto] 1
                    }
                    default {
                        ::plugins::MaintenanceTracker::_set_vis $page [list row${i}_auto] 0
                    }
                }
                ::plugins::MaintenanceTracker::_cfg $page row${i}_plate -fill $tint -outline $tint
                # v0.17.0 vector swap, v0.18.0 factored into the shared
                # renderer (the Detail page header uses it too).
                ::plugins::MaintenanceTracker::_apply_item_icon $page \
                    row${i}_icon row${i} $id $color

                # Counter + caption + wear-bar fraction per state
                # (v0.29.1: shared with the Detail status card).
                lassign [::plugins::MaintenanceTracker::_card_numbers $id $entry] cnt cap nfill
                ::plugins::MaintenanceTracker::_cfg $page row${i}_cnt -text $cnt \
                    -fill [expr {$state in {amber red} ? $color : $L(text_hi)}]
                ::plugins::MaintenanceTracker::_cfg $page row${i}_line3 -text $cap

                for {set j 0} {$j < $L(bar_segs)} {incr j} {
                    set c [expr {$j < $nfill ? $color : $L(bar_track)}]
                    ::plugins::MaintenanceTracker::_cfg $page row${i}_seg${j} -fill $c -outline $c
                }
            } else {
                set vtags {}
                foreach tag {bg plate icon line1 state cnt line3 tick auto} {
                    lappend vtags row${i}_$tag
                }
                for {set j 0} {$j < $L(bar_segs)} {incr j} {
                    lappend vtags row${i}_seg${j}
                }
                lappend vtags row${i}_btn* row${i}_open*
                ::plugins::MaintenanceTracker::_set_vis $page $vtags 0
                foreach {vtag vname} {vsw steam-wand vgf gasket-flat} {
                    ::plugins::MaintenanceTracker::_show_vector_icon $page row${i}_$vtag $vname 0
                }
            }
        }

        # Prev/Next enabled only where a page exists (GFC -state pattern;
        # dbutton -state stays a real dui call, it restyles the label too).
        set last_page [expr {($n - 1) / $card_page_size}]
        catch { dui item config $page prev_page* -state [expr {$card_page > 0 ? "normal" : "disabled"}] }
        catch { dui item config $page next_page* -state [expr {$card_page < $last_page ? "normal" : "disabled"}] }

        if {$::plugins::MaintenanceTracker::debug_timing} {
            catch { msg "MaintenanceTracker: settings refresh [expr {[clock milliseconds] - $_t0}] ms" }
        }
    }

    proc show {page_to_hide page_to_show} {
        # Any arrival at the main page clears the pending-record flag and
        # the detail confirm mode (a stuck flag must never survive a page
        # switch). Pass 23: no forced cache invalidation here -- every
        # mutating path (record/confirm, auto-record, add/edit/delete)
        # already calls _invalidate_status_cache, machine events do too,
        # and the 600 s TTL covers long-idle staleness; re-running the
        # full SDB pass on every arrival made Done/Back taps lag.
        set ::plugins::MaintenanceTracker::pending_item ""
        set ::plugins::MaintenanceTracker::record_return MaintenanceTracker_settings
        set ::plugins::MaintenanceTracker::detail_mode view
        set ::plugins::MaintenanceTracker::edit_delete_armed 0
        ::plugins::MaintenanceTracker::_capture_return_page $page_to_hide
        # v0.23.1: dui runs show hooks "after idle" (dui.tcl ~6705) but
        # sets the current page at once (~6487). Open Descale / Start
        # Clean close this page on their way out in the SAME tap, so its
        # queued show ran on top of the app's page and the Prev/Next
        # -state calls (normal/disabled = visible) painted this page's
        # toolbar over "Prepare to descale". A stale show only resets.
        if {![::plugins::MaintenanceTracker::_page_is_current MaintenanceTracker_settings]} { return }
        if {[catch { refresh } err]} {
            catch { msg "MaintenanceTracker: settings refresh failed: $err" }
        }
    }
}

# ===========================================================================
#  Confirm pages -- Pass 3 recording flow
# ===========================================================================

namespace eval ::dui::pages::MaintenanceTracker_confirm {

    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::MaintenanceTracker::L L
        ::plugins::MaintenanceTracker::_page_bg $page

        set lx $L(left_x)
        set rx $L(right_x)
        set cx [expr {($lx + $rx) / 2}]

        dui add dtext $page $cx $L(header_solo_title_y) -tags page_title \
            -text [translate "Record Maintenance"] \
            -font $L(font_title) -width $L(content_w) -fill $L(text_hi) \
            -anchor center -justify center

        set q_y [expr {int(round(220 * $L(scale)))}]
        dui add dtext $page $cx $q_y -tags confirm_question -text "" \
            -font $L(font_primary) -width $L(content_w) -fill $L(text_hi) \
            -anchor center -justify center
        set cur_y [expr {$q_y + $L(xxl)}]
        dui add dtext $page $cx $cur_y -tags confirm_current -text "" \
            -font $L(font_body) -width $L(content_w) -fill $L(text_body) \
            -anchor center -justify center
        set note_y [expr {$cur_y + $L(xxl)}]
        dui add dtext $page $cx $note_y -tags confirm_note \
            -text [translate "This sets the item's last-done time to now and restarts its counter. Only this plugin's own settings file is changed."] \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) \
            -anchor center -justify center

        dui add dbutton $page $lx $L(bar_y0) [expr {$lx + $L(btn_w_std)}] $L(bar_y1) \
            -tags mt_cancel -label [translate "Cancel"] \
            -command ::plugins::MaintenanceTracker::cancel_record \
            -label_font $L(font_button) -style mt_btn
        dui add dbutton $page [expr {$rx - $L(btn_w_std)}] $L(bar_y0) $rx $L(bar_y1) \
            -tags bar_confirm -label [translate "Confirm"] \
            -command ::plugins::MaintenanceTracker::record_pending \
            -label_font $L(font_button) -style mt_btn
    }

    proc show {page_to_hide page_to_show} {
        set page [namespace tail [namespace current]]
        set id $::plugins::MaintenanceTracker::pending_item
        if {$id eq ""} {
            catch { dui item config $page confirm_question -text [translate "Nothing selected."] }
            catch { dui item config $page confirm_current -text "" }
            return
        }
        set label [::plugins::MaintenanceTracker::_item_label $id]
        catch { dui item config $page confirm_question \
            -text "[translate {Record}] \"$label\" [translate {as done now?}]" }
        set current ""
        catch {
            set s [::plugins::MaintenanceTracker::status_summary]
            if {[dict exists $s items $id]} {
                set entry [dict get $s items $id]
                set current "[translate {Currently:}] [::plugins::MaintenanceTracker::_item_detail $id $entry]"
                set ld [::plugins::MaintenanceTracker::_item_last_done_line $entry]
                if {$ld ne ""} { append current "\n$ld" }
            }
        }
        catch { dui item config $page confirm_current -text $current }
    }
}

# Burr install gets its own confirm page: same layout plus the pre-history
# shot offset, entered with +/- stepper buttons (no Android keyboard, so no
# top-half-of-screen constraint issue; the block still sits high).
namespace eval ::dui::pages::MaintenanceTracker_confirm_burr {

    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::MaintenanceTracker::L L
        ::plugins::MaintenanceTracker::_page_bg $page

        set lx $L(left_x)
        set rx $L(right_x)
        set cx [expr {($lx + $rx) / 2}]

        dui add dtext $page $cx $L(header_solo_title_y) -tags page_title \
            -text [translate "Record Burr Install"] \
            -font $L(font_title) -width $L(content_w) -fill $L(text_hi) \
            -anchor center -justify center

        set q_y [expr {int(round(200 * $L(scale)))}]
        dui add dtext $page $cx $q_y -tags confirm_question \
            -text [translate "Record new burrs installed now?"] \
            -font $L(font_primary) -width $L(content_w) -fill $L(text_hi) \
            -anchor center -justify center

        # Offset stepper: label line, then [-100][-10] value [+10][+100].
        set off_label_y [expr {int(round(280 * $L(scale)))}]
        dui add dtext $page $cx $off_label_y -tags offset_label \
            -text [translate "Shots already on these burrs (0 if brand new):"] \
            -font $L(font_body) -width $L(content_w) -fill $L(text_body) \
            -anchor center -justify center

        set step_y1 [expr {int(round(330 * $L(scale)))}]
        set step_y2 [expr {$step_y1 + $L(btn_h)}]
        set step_w [expr {int(round(120 * $L(scale)))}]
        set value_w [expr {int(round(200 * $L(scale)))}]
        set row_w [expr {4 * $step_w + $value_w + 4 * $L(md)}]
        set x [expr {$cx - $row_w / 2}]
        foreach {tag delta} {minus100 -100 minus10 -10} {
            dui add dbutton $page $x $step_y1 [expr {$x + $step_w}] $step_y2 \
                -tags $tag -label $delta \
                -command [list ::plugins::MaintenanceTracker::adjust_burr_offset $delta] \
                -label_font $L(font_button) -style mt_btn
            set x [expr {$x + $step_w + $L(md)}]
        }
        dui add variable $page [expr {$x + $value_w / 2}] [expr {($step_y1 + $step_y2) / 2}] \
            -tags offset_value -fill $L(text_hi) -font $L(font_primary) -anchor center -justify center \
            -textvariable {$::plugins::MaintenanceTracker::burr_offset}
        set x [expr {$x + $value_w + $L(md)}]
        foreach {tag delta} {plus10 10 plus100 100} {
            dui add dbutton $page $x $step_y1 [expr {$x + $step_w}] $step_y2 \
                -tags $tag -label +$delta \
                -command [list ::plugins::MaintenanceTracker::adjust_burr_offset $delta] \
                -label_font $L(font_button) -style mt_btn
            set x [expr {$x + $step_w + $L(md)}]
        }

        set note_y [expr {$step_y2 + $L(xl)}]
        dui add dtext $page $cx $note_y -tags confirm_note \
            -text [translate "The burr counter becomes this offset plus every shot pulled from now on. Only this plugin's own settings file is changed."] \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) \
            -anchor center -justify center

        dui add dbutton $page $lx $L(bar_y0) [expr {$lx + $L(btn_w_std)}] $L(bar_y1) \
            -tags mt_cancel -label [translate "Cancel"] \
            -command ::plugins::MaintenanceTracker::cancel_record \
            -label_font $L(font_button) -style mt_btn
        dui add dbutton $page [expr {$rx - $L(btn_w_std)}] $L(bar_y0) $rx $L(bar_y1) \
            -tags bar_confirm -label [translate "Confirm"] \
            -command ::plugins::MaintenanceTracker::record_pending \
            -label_font $L(font_button) -style mt_btn
    }

    proc show {page_to_hide page_to_show} {
        return
    }
}

# v0.13.0: the water bottle gets its own confirm page -- the burr-offset
# stepper mechanism, verbatim, carrying the bottle size instead. Built-in
# trackers have no Edit page, so the swap confirmation is where the size
# is adjusted; Confirm writes it into the item's threshold.
namespace eval ::dui::pages::MaintenanceTracker_confirm_bottle {

    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::MaintenanceTracker::L L
        ::plugins::MaintenanceTracker::_page_bg $page

        set lx $L(left_x)
        set rx $L(right_x)
        set cx [expr {($lx + $rx) / 2}]

        dui add dtext $page $cx $L(header_solo_title_y) -tags page_title \
            -text [translate "Record Water Bottle"] \
            -font $L(font_title) -width $L(content_w) -fill $L(text_hi) \
            -anchor center -justify center

        set q_y [expr {int(round(200 * $L(scale)))}]
        dui add dtext $page $cx $q_y -tags confirm_question \
            -text [translate "Record a fresh water bottle attached now?"] \
            -font $L(font_primary) -width $L(content_w) -fill $L(text_hi) \
            -anchor center -justify center

        # Size stepper: label line, then [-1000][-100] value [+100][+1000].
        set size_label_y [expr {int(round(280 * $L(scale)))}]
        dui add dtext $page $cx $size_label_y -tags size_label \
            -text [translate "Bottle size in ml (5 US gal = 18900):"] \
            -font $L(font_body) -width $L(content_w) -fill $L(text_body) \
            -anchor center -justify center

        set step_y1 [expr {int(round(330 * $L(scale)))}]
        set step_y2 [expr {$step_y1 + $L(btn_h)}]
        set step_w [expr {int(round(120 * $L(scale)))}]
        set value_w [expr {int(round(200 * $L(scale)))}]
        set row_w [expr {4 * $step_w + $value_w + 4 * $L(md)}]
        set x [expr {$cx - $row_w / 2}]
        foreach {tag delta} {minus1000 -1000 minus100 -100} {
            dui add dbutton $page $x $step_y1 [expr {$x + $step_w}] $step_y2 \
                -tags $tag -label $delta \
                -command [list ::plugins::MaintenanceTracker::adjust_bottle_size $delta] \
                -label_font $L(font_button) -style mt_btn
            set x [expr {$x + $step_w + $L(md)}]
        }
        dui add variable $page [expr {$x + $value_w / 2}] [expr {($step_y1 + $step_y2) / 2}] \
            -tags size_value -fill $L(text_hi) -font $L(font_primary) -anchor center -justify center \
            -textvariable {$::plugins::MaintenanceTracker::bottle_size}
        set x [expr {$x + $value_w + $L(md)}]
        foreach {tag delta} {plus100 100 plus1000 1000} {
            dui add dbutton $page $x $step_y1 [expr {$x + $step_w}] $step_y2 \
                -tags $tag -label +$delta \
                -command [list ::plugins::MaintenanceTracker::adjust_bottle_size $delta] \
                -label_font $L(font_button) -style mt_btn
            set x [expr {$x + $step_w + $L(md)}]
        }

        set note_y [expr {$step_y2 + $L(xl)}]
        dui add dtext $page $cx $note_y -tags confirm_note \
            -text [translate "The bottle meter restarts at zero and fills as the machine dispenses water (espresso, steam, hot water, flushes, cleaning). Only this plugin's own settings file is changed."] \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) \
            -anchor center -justify center

        dui add dbutton $page $lx $L(bar_y0) [expr {$lx + $L(btn_w_std)}] $L(bar_y1) \
            -tags mt_cancel -label [translate "Cancel"] \
            -command ::plugins::MaintenanceTracker::cancel_record \
            -label_font $L(font_button) -style mt_btn
        dui add dbutton $page [expr {$rx - $L(btn_w_std)}] $L(bar_y0) $rx $L(bar_y1) \
            -tags bar_confirm -label [translate "Confirm"] \
            -command ::plugins::MaintenanceTracker::record_pending \
            -label_font $L(font_button) -style mt_btn
    }

    proc show {page_to_hide page_to_show} {
        return
    }
}

# ===========================================================================
#  Detail page -- Pass 6: per-item event history + Undo Last Record
#
#  Single page with a view <-> confirm swap (the burr-stepper single-page
#  pattern): the SAME two bottom-bar buttons serve both modes through
#  dispatchers that read detail_mode at click time; only labels and texts
#  are reconfigured. No two interactive widgets ever share a rectangle
#  (v0.3.0 rule).
# ===========================================================================

namespace eval ::dui::pages::MaintenanceTracker_detail {

    variable event_rows 5

    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::MaintenanceTracker::L L
        variable event_rows
        ::plugins::MaintenanceTracker::_page_bg $page

        set lx $L(left_x)
        set rx $L(right_x)
        set cx [expr {($lx + $rx) / 2}]

        # Title width stops well short of the header's right corner so a
        # long custom name wraps instead of running under Rename.
        dui add dtext $page $cx $L(header_solo_title_y) -tags page_title -text "" \
            -font $L(font_title) -width [expr {$L(content_w) - 2 * ($L(btn_w_std) + $L(lg))}] \
            -fill $L(text_hi) -anchor center -justify center

        # v0.18.0: the tracker's icon, top-left corner (the card
        # plate design, state-tinted): rounded plate + glyph dtext +
        # both vector drawings born hidden; refresh renders via the
        # shared _apply_item_icon. Vertically aligned with the Edit
        # button's header slot; the title's trimmed width keeps clear.
        set dp_y1 [expr {int(round(22 * $L(scale)))}]
        set dp_x2 [expr {$lx + $L(plate_size)}]
        ::plugins::MaintenanceTracker::rounded_rect $page $lx $dp_y1 \
            $dp_x2 [expr {$dp_y1 + $L(plate_size)}] $L(plate_radius) \
            -fill $L(tint_unset) -outline $L(tint_unset) -width 1 -tags det_plate
        set dp_cx [expr {($lx + $dp_x2) / 2}]
        set dp_cy [expr {$dp_y1 + $L(plate_size) / 2}]
        dui add dtext $page $dp_cx $dp_cy -tags det_icon -text "" \
            -font $L(font_icon_plate) -fill $L(col_unset) -anchor center -justify center
        ::plugins::MaintenanceTracker::_add_vector_icon $page det_vsw steam-wand \
            $dp_cx $dp_cy $L(vec_box_plate) $L(col_unset) 1
        ::plugins::MaintenanceTracker::_add_vector_icon $page det_vgf gasket-flat \
            $dp_cx $dp_cy $L(vec_box_plate) $L(col_unset) 1

        # v0.11.0 (Rename) -> v0.12.0 (Edit) -> v0.15.0: every tracker
        # is editable, so this shows for all items in view mode.
        # Top-right of the header (design system's mode-button slot);
        # hidden while an undo confirm is armed.
        dui add dbutton $page [expr {$rx - $L(btn_w_std)}] [expr {int(round(22 * $L(scale)))}] \
            $rx [expr {int(round(22 * $L(scale))) + $L(btn_h)}] \
            -tags btn_edit -label [translate "Edit"] \
            -command ::dui::pages::MaintenanceTracker_detail::edit_click \
            -label_font $L(font_button) -style mt_btn -initial_state hidden

        # v0.29.1: status card -- the list card's anatomy without plate
        # and button: summary line + counter (right), state word + AUTO
        # tag (right), segmented wear bar with the amber tick, caption.
        # Replaces the loose dot + counter + last-done lines.
        set sy0 $L(det_top)
        set sy1 [expr {$sy0 + $L(card_h)}]
        set ix1 [expr {$lx + $L(card_pad_x)}]
        set ix2 [expr {$rx - $L(card_pad_x)}]
        ::plugins::MaintenanceTracker::_sec_card $page det_card $lx $sy0 $rx $sy1 ""
        # The counter's zone (260 ref) is kept free of the summary line.
        dui add dtext $page $ix1 [expr {$sy0 + $L(card_name_dy)}] -tags detail_counter -text "" \
            -font $L(font_primary) -width [expr {$ix2 - $ix1 - int(round(260 * $L(scale)))}] \
            -fill $L(text_hi) -anchor w -justify left
        dui add dtext $page $ix2 [expr {$sy0 + $L(card_name_dy)}] -tags det_cnt -text "" \
            -font $L(font_primary) -fill $L(text_hi) -anchor e -justify right
        dui add dtext $page $ix1 [expr {$sy0 + $L(card_state_dy)}] -tags det_state -text "" \
            -font $L(font_caption_b) -fill $L(text_mut) -anchor w -justify left
        dui add dtext $page $ix2 [expr {$sy0 + $L(card_state_dy)}] -tags det_auto \
            -text [translate "AUTO"] -font $L(font_caption_b) -fill $L(icon_sel) \
            -anchor e -justify right -initial_state hidden
        set bar_w [expr {$ix2 - $ix1}]
        set seg_stride [expr {($bar_w + $L(bar_seg_gap)) / $L(bar_segs)}]
        set seg_w [expr {$seg_stride - $L(bar_seg_gap)}]
        set bar_yc [expr {$sy0 + $L(card_bar_dy)}]
        set bar_y1 [expr {$bar_yc - $L(bar_h) / 2}]
        set bar_y2 [expr {$bar_yc + $L(bar_h) / 2}]
        for {set j 0} {$j < $L(bar_segs)} {incr j} {
            set sx1 [expr {$ix1 + $j * $seg_stride}]
            dui add canvas_item rect $page $sx1 $bar_y1 [expr {$sx1 + $seg_w}] $bar_y2 \
                -fill $L(bar_track) -outline $L(bar_track) -tags det_seg$j
        }
        set amber_frac 0.8
        catch {
            if {[string is double -strict $::plugins::MaintenanceTracker::settings(amber_fraction)]} {
                set amber_frac $::plugins::MaintenanceTracker::settings(amber_fraction)
            }
        }
        set tick_x [expr {$ix1 + int(round($bar_w * $amber_frac))}]
        dui add canvas_item rect $page [expr {$tick_x - 2}] [expr {$bar_y1 - $L(xs)}] \
            [expr {$tick_x + 2}] [expr {$bar_y2 + $L(xs)}] \
            -fill $L(bar_tick) -outline $L(bar_tick) -tags det_tick
        dui add dtext $page $ix1 [expr {$sy0 + $L(card_cap_dy)}] -tags detail_last -text "" \
            -font $L(font_caption) -width $bar_w -fill $L(text_mut) \
            -anchor w -justify left

        # Event history: up to 5 events, newest first. v0.29.0: each row
        # is a tap zone (the whole row, contiguous) that arms its removal
        # in the confirm mode; a caption on the title line says so.
        # v0.29.1: a History card (left 66%): per row the date + age
        # (left), how it was recorded (right) and a chevron; one-row
        # dividers between rows; rows 64 ref tall.
        set hx2 $L(det_hist_x1)
        set hy [::plugins::MaintenanceTracker::_sec_card $page hist_card \
            $lx $L(det_low_y0) $hx2 $L(det_low_y1) [translate "History (newest first)"]]
        dui add dtext $page [expr {$hx2 - $L(card_pad_x)}] [expr {$L(det_low_y0) + $L(sec_head_h) / 2}] \
            -tags hist_hint -text [translate "Tap a record to remove it"] \
            -font $L(font_caption) -fill $L(text_mut) -anchor e -justify right \
            -initial_state hidden
        set chev_x [expr {$hx2 - $L(card_pad_x) - int(round(5 * $L(scale)))}]
        set src_x [expr {$chev_x - int(round(5 * $L(scale))) - $L(md)}]
        for {set i 0} {$i < $event_rows} {incr i} {
            set ry0 [expr {$hy + $i * $L(det_row_h)}]
            set rcy [expr {$ry0 + $L(det_row_h) / 2}]
            dui add dtext $page $ix1 $rcy -tags ev$i -text "" \
                -font $L(font_body) -width [expr {int(($hx2 - $lx) * 0.55)}] \
                -fill $L(text_hi) -anchor w -justify left
            dui add dtext $page $src_x $rcy -tags evs$i -text "" \
                -font $L(font_caption) -fill $L(text_body) -anchor e -justify right
            ::plugins::MaintenanceTracker::_sec_chevron $page ev${i}_chev $chev_x $rcy \
                -initial_state hidden
            if {$i < $event_rows - 1} {
                ::plugins::MaintenanceTracker::_sec_divider $page ev${i}_div \
                    $ix1 [expr {$ry0 + $L(det_row_h)}] [expr {$hx2 - $L(card_pad_x)}] \
                    -initial_state hidden
            }
        }
        for {set i 0} {$i < $event_rows} {incr i} {
            set ry0 [expr {$hy + $i * $L(det_row_h)}]
            dui add dbutton $page $lx $ry0 $hx2 [expr {$ry0 + $L(det_row_h)}] \
                -tags mt_ev$i \
                -command [list ::dui::pages::MaintenanceTracker_detail::event_click $i] \
                -initial_state hidden
        }

        # v0.22.0: linked-profile row between the history and the
        # message slot. Label / value on the label-value grid, buttons
        # right-aligned at 520..580 ref px: linked -> [Unlink] md [Load
        # profile]; unlinked -> [Link current profile]. The last event
        # line's glyphs end ~493, the message slot (moved 600 -> 624,
        # two lines 599..649) still clears the bar at 716. All three
        # buttons are born hidden; refresh shows the right pair and
        # hides them all while an undo is armed.
        # v0.25.0 (Pass 31): the row only SHOWS the link and offers its
        # one action -- Link / Unlink moved to the Edit page (owner:
        # Unlink sat beside Load profile, same size, easy to hit by
        # mistake). The value gets the room the Unlink button had, so a
        # profile title shows in full. Row 520 -> 476 ref with the
        # history; the last event line ends ~444.
        # v0.29.0: 476 -> 500 ref, below the taller history rows (the last
        # row's tap zone ends at 480).
        # v0.29.1: a Linked profile card beside History: the link (up to
        # two lines), what the tracker records / counts on by itself (a
        # caption + up to two bulleted lines -- the "Auto-records on"
        # text moved here from the last-done line), Start at the bottom,
        # card-wide.
        set kx1 [expr {$hx2 + $L(md)}]
        set kix1 [expr {$kx1 + $L(card_pad_x)}]
        set kiw [expr {$rx - $L(card_pad_x) - $kix1}]
        set ky [::plugins::MaintenanceTracker::_sec_card $page link_card \
            $kx1 $L(det_low_y0) $rx $L(det_low_y1) [translate "Linked profile"]]
        dui add dtext $page $kix1 [expr {$ky + $L(md)}] -tags prof_value -text "" \
            -font $L(font_primary) -width $kiw \
            -fill $L(text_hi) -anchor nw -justify left
        set acap_y [expr {$ky + int(round(86 * $L(scale)))}]
        dui add dtext $page $kix1 $acap_y -tags auto_cap -text "-" \
            -font $L(font_caption) -width $kiw -fill $L(text_mut) \
            -anchor nw -justify left -initial_state hidden
        set dot_r [expr {int(round(4 * $L(scale)))}]
        set atx [expr {$kix1 + int(round(18 * $L(scale)))}]
        for {set k 0} {$k < 2} {incr k} {
            set ay [expr {$acap_y + int(round((36 + 28 * $k) * $L(scale)))}]
            dui add canvas_item oval $page [expr {$kix1 + $dot_r}] [expr {$ay - $dot_r}] \
                [expr {$kix1 + 3 * $dot_r}] [expr {$ay + $dot_r}] \
                -fill $L(col_ok) -outline $L(col_ok) -width 1 -tags auto_dot$k \
                -initial_state hidden
            dui add dtext $page $atx $ay -tags auto_txt$k -text "-" \
                -font $L(font_caption) -width [expr {$kix1 + $kiw - $atx}] \
                -fill $L(text_body) -anchor w -justify left -initial_state hidden
        }
        # v0.26.0 (Pass 32): the button is always "Start" (primary,
        # green): it opens the tracker's Steps page, where the link's own
        # action (Load profile / Open Descale / Start Clean / Mark done)
        # sits under the instructions.
        set prof_y1 [expr {$L(det_low_y1) - $L(card_pad_x)}]
        set prof_y0 [expr {$prof_y1 - $L(btn_h)}]
        dui add dbutton $page $kix1 $prof_y0 [expr {$kix1 + $kiw}] $prof_y1 \
            -tags mt_start -label [translate "Start"] \
            -command ::dui::pages::MaintenanceTracker_detail::start_click \
            -label_font $L(font_button) -style mt_btn_primary -initial_state hidden

        # Confirm-mode message (empty in view mode), between the cards
        # and the bottom bar. v0.22.0: also the linked-profile outcome
        # note for 4 s.
        dui add dtext $page $cx $L(det_msg_y) -tags confirm_msg -text "" \
            -font $L(font_primary) -width $L(content_w) -fill $L(col_red) \
            -anchor center -justify center

        # Bottom bar per the v0.15.0 button standard: Back (left,
        # navigation, always safe), Hide Tracker (center, normal style
        # -- non-destructive and reversible, disabled at the hide cap),
        # Undo Last Record (right, danger, two-step). Delete moved to
        # the Edit page in v0.15.0 -- destructive delete lives one
        # deliberate level deeper, never beside everyday buttons.
        # Geometry: Back ends at lx+400, Hide spans cx +/- 300, Undo
        # starts at rx-600 (virtual px) -- a full button-width of empty
        # canvas separates the danger button from its neighbors.
        # v0.25.0 (Pass 31): [Back] [Undo Last Record] ... [Hide Tracker]
        # [Record]. Record is the page's one go-ahead action (primary,
        # green, right). Undo lost the red main-action slot: it is a
        # normal button beside Back and turns red only once armed (its
        # second tap is the destructive one; Back becomes its Cancel).
        # Gaps = (content_w - 2 std - 2 xwide) / 3 (62 ref).
        set bar_gap [expr {($L(content_w) - 2 * $L(btn_w_std) - 2 * $L(btn_w_xwide)) / 3}]
        set undo_x0 [expr {$lx + $L(btn_w_std) + $bar_gap}]
        set rec_x0 [expr {$rx - $L(btn_w_std)}]
        set hide_x1 [expr {$rec_x0 - $bar_gap}]
        dui add dbutton $page $lx $L(bar_y0) [expr {$lx + $L(btn_w_std)}] $L(bar_y1) \
            -tags bar_left -label [translate "Back"] \
            -command ::dui::pages::MaintenanceTracker_detail::left_click \
            -label_font $L(font_button) -style mt_btn
        dui add dbutton $page $undo_x0 $L(bar_y0) [expr {$undo_x0 + $L(btn_w_xwide)}] $L(bar_y1) \
            -tags bar_undo -label [translate "Undo Last Record"] \
            -command ::dui::pages::MaintenanceTracker_detail::right_click \
            -label_font $L(font_button) -style mt_btn -initial_state hidden
        dui add dbutton $page [expr {$hide_x1 - $L(btn_w_xwide)}] $L(bar_y0) $hide_x1 $L(bar_y1) \
            -tags mt_hide -label [translate "Hide Tracker"] \
            -command ::dui::pages::MaintenanceTracker_detail::hide_click \
            -label_font $L(font_button) -style mt_btn -initial_state hidden
        dui add dbutton $page $rec_x0 $L(bar_y0) $rx $L(bar_y1) \
            -tags mt_record -label [translate "Record"] \
            -command ::dui::pages::MaintenanceTracker_detail::record_click \
            -label_font $L(font_button) -style mt_btn -initial_state hidden
    }

    proc refresh {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::MaintenanceTracker::L L
        variable event_rows
        set id $::plugins::MaintenanceTracker::detail_item
        set mode $::plugins::MaintenanceTracker::detail_mode

        if {$id eq "" || ![info exists ::plugins::MaintenanceTracker::settings(item_$id)]} {
            catch { dui item config $page page_title -text [translate "Nothing selected"] }
            foreach t {detail_counter detail_last confirm_msg det_cnt det_state} {
                catch { dui item config $page $t -text "" }
            }
            _show_status_card $page "" 0
            _show_auto_rows $page "" {}
            for {set i 0} {$i < $event_rows} {incr i} {
                catch { dui item config $page ev$i -text "" }
                catch { dui item config $page evs$i -text "" }
                catch { dui item hide $page mt_ev$i* -initial 1 }
            }
            _show_row_marks $page 0
            catch { dui item hide $page hist_hint -initial 1 }
            catch { dui item hide $page bar_undo* -initial 1 }
            catch { dui item hide $page mt_hide* -initial 1 }
            catch { dui item hide $page btn_edit* -initial 1 }
            catch { dui item hide $page mt_start* -initial 1 }
            catch { dui item hide $page mt_record* -initial 1 }
            catch { dui item config $page prof_value -text "" }
            catch { dui item config $page bar_left -label [translate "Back"] }
            # v0.28.1: plain canvas items by their EXACT tags -- `det_plate*`
            # is a literal compound-widget tag and matched nothing, leaving
            # the grey plate on screen. (v0.29.1: the state dot is gone --
            # the status card carries the state.)
            catch { dui item hide $page det_plate -initial 1 }
            catch { dui item hide $page det_icon -initial 1 }
            foreach {vtag vname} {vsw steam-wand vgf gasket-flat} {
                ::plugins::MaintenanceTracker::_show_vector_icon $page det_$vtag $vname 0
            }
            return
        }

        # Header reuses the card's own formatting procs.
        set s [::plugins::MaintenanceTracker::status_summary]
        if {[dict exists $s items $id]} {
            set entry [dict get $s items $id]
        } else {
            set entry [dict create state unknown last_done 0]
        }
        set state [dict get $entry state]
        catch { dui item config $page page_title \
            -text [::plugins::MaintenanceTracker::_item_label $id] }
        # v0.29.1 status card: the list card's numbers (_card_numbers),
        # the summary sentence on line 1 (ml: without the "-- left" tail,
        # the caption already says it), the state word in its colour.
        set color [::plugins::MaintenanceTracker::_state_color $state]
        lassign [::plugins::MaintenanceTracker::_card_numbers $id $entry] cnt cap nfill
        set line1 [::plugins::MaintenanceTracker::_item_detail $id $entry]
        if {$state in {unset unknown}} {
            # line 1 already says it; the caption would repeat it.
            set cap ""
        } else {
            set cut [string first " -- " $line1]
            if {$cut > 0} { set line1 [string range $line1 0 [expr {$cut - 1}]] }
        }
        catch { dui item config $page detail_counter -text $line1 }
        catch { dui item config $page det_cnt -text $cnt \
            -fill [expr {$state in {amber red} ? $color : $L(text_hi)}] }
        catch { dui item config $page det_state \
            -text [string toupper [::plugins::MaintenanceTracker::_state_word $state]] -fill $color }
        catch { dui item config $page detail_last -text $cap }
        _show_status_card $page $color $nfill

        # v0.20.0: say whether (and from what) this tracker auto-records;
        # v0.21.0: auto-COUNTING trackers (shots/ml, no auto_src) get
        # their own wording -- the exact thing the card's AUTO-RECORD /
        # AUTO-COUNT tag points at. v0.29.1: a caption + one line per
        # source in the Linked profile card (was a tail on the last-done
        # line).
        set auto_cap ""
        set auto_lines {}
        set auto_tag ""
        switch -- [::plugins::MaintenanceTracker::_item_auto_kind $id] {
            record {
                set auto_tag [translate "AUTO-RECORD"]
                set auto_cap [translate "Auto-records on"]
                # v0.24.0: name the linked cleaning profile too.
                set asrc [::plugins::MaintenanceTracker::_item_auto_src $id]
                if {$asrc ne ""} {
                    lappend auto_lines [::plugins::MaintenanceTracker::_auto_src_label $asrc]
                }
                set cprof [::plugins::MaintenanceTracker::_item_cleaning_profile $id]
                if {$cprof ne ""} {
                    lappend auto_lines [::plugins::MaintenanceTracker::_short_text [lindex $cprof 1] 36]
                }
            }
            count {
                set auto_tag [translate "AUTO-COUNT"]
                set auto_cap [translate "Counts automatically"]
                set u ""
                catch { set u [dict get $::plugins::MaintenanceTracker::settings(item_$id) unit] }
                if {$u eq "ml"} {
                    lappend auto_lines [translate "all water dispensed"]
                } else {
                    lappend auto_lines [translate "every espresso shot"]
                }
            }
        }
        if {$auto_tag ne ""} {
            catch { dui item config $page det_auto -text $auto_tag }
            catch { dui item show $page det_auto -initial 1 }
        } else {
            catch { dui item hide $page det_auto -initial 1 }
        }
        _show_auto_rows $page $auto_cap $auto_lines

        # v0.18.0: header icon plate, tinted and colored by state
        # exactly like the tracker's card.
        set tint $L(tint_unknown)
        catch { set tint $L(tint_$state) }
        catch { dui item show $page det_plate -initial 1 }
        catch { dui item config $page det_plate -fill $tint -outline $tint }
        ::plugins::MaintenanceTracker::_apply_item_icon $page det_icon det $id $color

        # Event list, newest first. v0.29.0: row i shows events index
        # n-1-i and is a tap zone; in the confirm mode the targeted row
        # turns red (v0.29.1: all three of its parts).
        set events {}
        catch { set events [dict get $::plugins::MaintenanceTracker::settings(item_$id) events] }
        set n [llength $events]
        set target $::plugins::MaintenanceTracker::detail_target
        # -1 (the classic Undo) or a stale index -> the newest record.
        if {![string is integer -strict $target] || $target < 0 || $target >= $n} {
            set target [expr {$n - 1}]
            set ::plugins::MaintenanceTracker::detail_target -1
        }
        if {$n == 0} {
            catch { dui item config $page ev0 -text [translate "Never recorded."] -fill $L(text_body) }
            catch { dui item config $page evs0 -text "" }
            catch { dui item hide $page mt_ev0* -initial 1 }
            for {set i 1} {$i < $event_rows} {incr i} {
                catch { dui item config $page ev$i -text "" }
                catch { dui item config $page evs$i -text "" }
                catch { dui item hide $page mt_ev$i* -initial 1 }
            }
            _show_row_marks $page 0
        } else {
            set shown 0
            for {set j [expr {$n - 1}]} {$j >= 0 && $shown < $event_rows} {incr j -1} {
                set armed [expr {$mode eq "confirm" && $j == $target}]
                lassign [::plugins::MaintenanceTracker::_event_parts [lindex $events $j]] when src
                catch { dui item config $page ev$shown -text $when \
                    -fill [expr {$armed ? $L(col_red) : $L(text_hi)}] }
                catch { dui item config $page evs$shown -text $src \
                    -fill [expr {$armed ? $L(col_red) : $L(text_body)}] }
                catch { dui item config $page ev${shown}_chev \
                    -fill [expr {$armed ? $L(col_red) : $L(text_mut)}] }
                catch { dui item show $page mt_ev$shown* -initial 1 }
                incr shown
            }
            for {set i $shown} {$i < $event_rows} {incr i} {
                catch { dui item config $page ev$i -text "" }
                catch { dui item config $page evs$i -text "" }
                catch { dui item hide $page mt_ev$i* -initial 1 }
            }
            _show_row_marks $page $shown
        }
        if {$mode ne "confirm" && $n > 0} {
            catch { dui item show $page hist_hint -initial 1 }
        } else {
            catch { dui item hide $page hist_hint -initial 1 }
        }

        # Mode-dependent parts. v0.15.0: only two modes remain (view and
        # the armed undo confirm) -- delete lives on the Edit page now,
        # and Edit/Hide apply to every tracker uniformly.
        if {$mode eq "confirm" && $n > 0} {
            if {$target == $n - 1} {
                set newest [lindex $events end]
                set when ""
                catch { set when [clock format [dict get $newest ts] -format {%Y-%m-%d %H:%M}] }
                if {$n >= 2} {
                    set prev ""
                    catch { set prev [clock format [dict get [lindex $events end-1] ts] -format {%Y-%m-%d %H:%M}] }
                    set falls "[translate {The counter returns to}] $prev."
                } else {
                    set falls "[translate {The counter returns to: never recorded.}]"
                }
                set ctext "[translate {Undo the record from}] $when?  $falls"
                set clabel [translate "Yes, Delete Last Record"]
            } else {
                # v0.29.0: an older record -- the counter keeps the newest.
                set when ""
                catch { set when [clock format [dict get [lindex $events $target] ts] -format {%Y-%m-%d %H:%M}] }
                set ctext "[translate {Remove the record from}] $when?  [translate {The counter stays as it is.}]"
                set clabel [translate "Yes, Remove This Record"]
            }
            catch { dui item config $page confirm_msg -text $ctext -fill $L(col_red) }
            catch { dui item config $page bar_left -label [translate "Cancel"] }
            # v0.6.1 (owner request): the confirm-state label spells out
            # exactly what the second tap does -- the eye is already
            # locked on this button, so the button itself carries the
            # warning, not just the message text above it.
            catch { dui item config $page bar_undo -label $clabel }
            catch { dui item show $page bar_undo* -initial 1 }
            # v0.25.0: red only while armed (the bare-tag face recolor,
            # the same mechanism as the theme walk).
            catch { dui item config $page bar_undo-btn -fill $L(col_red) -outline $L(col_red) }
            catch { dui item hide $page mt_hide* -initial 1 }
            catch { dui item hide $page btn_edit* -initial 1 }
            catch { dui item hide $page mt_record* -initial 1 }
            # v0.22.0: the profile row's controls step aside too.
            # v0.23.0: and a mode switch disarms an armed Clean.
            ::plugins::MaintenanceTracker::_disarm_clean
            catch { dui item hide $page mt_start* -initial 1 }
        } else {
            catch { dui item config $page bar_left -label [translate "Back"] }
            catch { dui item config $page bar_undo -label [translate "Undo Last Record"] }
            catch { dui item config $page bar_undo-btn -fill $L(btn_fill) -outline $L(btn_fill) }
            catch { dui item show $page mt_record* -initial 1 }
            if {$n > 0} {
                catch { dui item show $page bar_undo* -initial 1 }
            } else {
                catch { dui item hide $page bar_undo* -initial 1 }
            }
            # v0.15.0: Edit and Hide for every tracker. Hide disables at
            # the cap, with the reason spelled out where the armed-
            # confirm message otherwise lives (grey -- informational).
            catch { dui item show $page btn_edit* -initial 1 }
            catch { dui item show $page mt_hide* -initial 1 }
            set hidden_n 0
            catch { set hidden_n [llength $::plugins::MaintenanceTracker::settings(hidden_ids)] }
            set hide_capped [expr {$hidden_n >= $::plugins::MaintenanceTracker::hide_max \
                    && $id ni $::plugins::MaintenanceTracker::settings(hidden_ids)}]
            catch { dui item config $page mt_hide* -state [expr {$hide_capped ? "disabled" : "normal"}] }
            # v0.26.0: the Clean arm lives on the Steps page now.
            if {$hide_capped} {
                catch { dui item config $page confirm_msg \
                    -text [translate "Hide is unavailable: six trackers are already hidden. Restore one from the New Tracker page first."] \
                    -fill $L(text_mut) }
            } elseif {$::plugins::MaintenanceTracker::prof_note ne ""} {
                # v0.22.0: the link outcome (Load / Link / Unlink /
                # refusals), cleared by its own 4 s timer.
                catch { dui item config $page confirm_msg \
                    -text $::plugins::MaintenanceTracker::prof_note -fill $L(text_hi) }
            } else {
                catch { dui item config $page confirm_msg -text "" }
            }
            # v0.26.0: Start (every tracker) opens the Steps page.
            catch { dui item show $page mt_start* -initial 1 }
        }
        # v0.22.0 linked profile; v0.23.0 any of three kinds. v0.25.0:
        # display only; Link / Unlink live on the Edit page. v0.29.1: the
        # card keeps showing it in both modes.
        set link [::plugins::MaintenanceTracker::_item_link $id]
        if {[lindex $link 0] eq ""} {
            catch { dui item config $page prof_value \
                -text [translate "none -- link one on the Edit page"] -fill $L(text_mut) }
        } else {
            catch { dui item config $page prof_value \
                -text [::plugins::MaintenanceTracker::_link_text $link] -fill $L(text_hi) }
        }
    }

    # v0.29.1: the status card's wear bar (nfill segments in the state
    # colour, the rest the track) and amber tick; color "" = empty card.
    proc _show_status_card {page color nfill} {
        upvar #0 ::plugins::MaintenanceTracker::L L
        for {set j 0} {$j < $L(bar_segs)} {incr j} {
            set c [expr {$color ne "" && $j < $nfill ? $color : $L(bar_track)}]
            ::plugins::MaintenanceTracker::_cfg $page det_seg$j -fill $c -outline $c
        }
        if {$color eq ""} {
            catch { dui item hide $page det_auto -initial 1 }
        }
    }

    # v0.29.1: the Linked profile card's automation block -- caption plus
    # one bulleted line per entry (max 2); an empty caption hides it all.
    proc _show_auto_rows {page cap lines} {
        if {$cap eq ""} {
            catch { dui item hide $page auto_cap -initial 1 }
        } else {
            catch { dui item config $page auto_cap -text $cap }
            catch { dui item show $page auto_cap -initial 1 }
        }
        for {set k 0} {$k < 2} {incr k} {
            if {$cap ne "" && $k < [llength $lines]} {
                catch { dui item config $page auto_txt$k -text [lindex $lines $k] }
                catch { dui item show $page auto_dot$k -initial 1 }
                catch { dui item show $page auto_txt$k -initial 1 }
            } else {
                catch { dui item hide $page auto_dot$k -initial 1 }
                catch { dui item hide $page auto_txt$k -initial 1 }
            }
        }
    }

    # v0.29.1: chevrons on the first `shown` history rows, dividers
    # between them (row i's divider sits under it, shown when row i+1
    # is shown too).
    proc _show_row_marks {page shown} {
        variable event_rows
        for {set i 0} {$i < $event_rows} {incr i} {
            catch { dui item [expr {$i < $shown ? "show" : "hide"}] $page ev${i}_chev -initial 1 }
            if {$i < $event_rows - 1} {
                catch { dui item [expr {$i + 1 < $shown ? "show" : "hide"}] $page ev${i}_div -initial 1 }
            }
        }
    }

    # v0.25.0: Record from Detail -- the list's confirm flow, returning
    # here. View mode only (an armed Undo hides the button anyway).
    proc record_click {} {
        if {$::plugins::MaintenanceTracker::detail_mode ne "view"} { return }
        set id $::plugins::MaintenanceTracker::detail_item
        if {$id eq ""} { return }
        ::plugins::MaintenanceTracker::request_record $id MaintenanceTracker_detail
    }

    # v0.26.0 (Pass 32): Start opens the tracker's Steps page; the link's
    # action lives there now. View mode only.
    proc start_click {} {
        if {$::plugins::MaintenanceTracker::detail_mode ne "view"} { return }
        ::plugins::MaintenanceTracker::open_steps $::plugins::MaintenanceTracker::detail_item
    }

    # v0.12.0 -> v0.15.0: Edit, any tracker, view mode only.
    proc edit_click {} {
        set id $::plugins::MaintenanceTracker::detail_item
        if {$::plugins::MaintenanceTracker::detail_mode ne "view"} { return }
        ::plugins::MaintenanceTracker::open_edit $id
    }

    # v0.29.0: tap a history row -> the confirm mode targets that record
    # (row i = events index n-1-i). A tap on another row re-targets.
    proc event_click {i} {
        set id $::plugins::MaintenanceTracker::detail_item
        if {$id eq ""} { return }
        set events {}
        catch { set events [dict get $::plugins::MaintenanceTracker::settings(item_$id) events] }
        set n [llength $events]
        set idx [expr {$n - 1 - $i}]
        if {$i < 0 || $idx < 0} { return }
        ::plugins::MaintenanceTracker::_disarm_clean
        set ::plugins::MaintenanceTracker::detail_target $idx
        set ::plugins::MaintenanceTracker::detail_mode confirm
        if {[catch { refresh } err]} {
            catch { msg "MaintenanceTracker: detail refresh failed: $err" }
        }
    }

    proc left_click {} {
        # Cancel out of EITHER confirm mode back to view; leave from view.
        set ::plugins::MaintenanceTracker::detail_target -1
        if {$::plugins::MaintenanceTracker::detail_mode ne "view"} {
            set ::plugins::MaintenanceTracker::detail_mode view
            if {[catch { refresh } err]} {
                catch { msg "MaintenanceTracker: detail refresh failed: $err" }
            }
        } else {
            ::plugins::MaintenanceTracker::_return_to_page MaintenanceTracker_settings
        }
    }

    proc right_click {} {
        set id $::plugins::MaintenanceTracker::detail_item
        set mode $::plugins::MaintenanceTracker::detail_mode
        if {$mode eq "view"} {
            set events {}
            catch { set events [dict get $::plugins::MaintenanceTracker::settings(item_$id) events] }
            if {[llength $events] == 0} { return }
            set ::plugins::MaintenanceTracker::detail_target -1
            set ::plugins::MaintenanceTracker::detail_mode confirm
        } else {
            set ::plugins::MaintenanceTracker::detail_mode view
            set events {}
            catch { set events [dict get $::plugins::MaintenanceTracker::settings(item_$id) events] }
            set t $::plugins::MaintenanceTracker::detail_target
            set ::plugins::MaintenanceTracker::detail_target -1
            if {[string is integer -strict $t] && $t >= 0 && $t < [llength $events] - 1} {
                # v0.29.0: an older record; stay on Detail to see the result.
                ::plugins::MaintenanceTracker::remove_event $id $t
            } elseif {[::plugins::MaintenanceTracker::undo_last_event $id]} {
                ::plugins::MaintenanceTracker::_return_to_page MaintenanceTracker_settings
                return
            }
        }
        if {[catch { refresh } err]} {
            catch { msg "MaintenanceTracker: detail refresh failed: $err" }
        }
    }

    # v0.8.0 -> v0.15.0: Hide Tracker, any tracker (single tap -- hiding
    # is non-destructive and reversible via the restore chips; hide_item
    # itself enforces the hide_max cap the disabled button communicates).
    proc hide_click {} {
        set id $::plugins::MaintenanceTracker::detail_item
        if {$::plugins::MaintenanceTracker::detail_mode ne "view"} { return }
        if {[::plugins::MaintenanceTracker::hide_item $id]} {
            set ::plugins::MaintenanceTracker::detail_item ""
            ::plugins::MaintenanceTracker::_return_to_page MaintenanceTracker_settings
        }
    }

    proc show {page_to_hide page_to_show} {
        # Stuck-flag rule: every show starts in view mode, and (v0.23.0)
        # with the Clean action disarmed.
        set ::plugins::MaintenanceTracker::detail_mode view
        set ::plugins::MaintenanceTracker::detail_target -1
        ::plugins::MaintenanceTracker::_disarm_clean
        # v0.23.1: a show hook queued before the page was left (dui runs
        # them after idle) must not repaint over the page now on screen.
        if {![::plugins::MaintenanceTracker::_page_is_current MaintenanceTracker_detail]} { return }
        if {[catch { refresh } err]} {
            catch { msg "MaintenanceTracker: detail refresh failed: $err" }
        }
    }
}

# ===========================================================================
#  Add Custom Tracker page -- Pass 8
#
#  Name entry (ShotHistoryEditor's tablet-proven entry pattern, kept in
#  the top half of the screen because the Android keyboard covers the
#  bottom), a days/shots unit toggle, and threshold steppers (the burr
#  stepper pattern -- no keyboard needed for the number). Stepper labels
#  are reconfigured with BARE tags only (v0.6.2 rule).
# ===========================================================================

namespace eval ::dui::pages::MaintenanceTracker_add {

    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::MaintenanceTracker::L L

        ::plugins::MaintenanceTracker::_page_bg $page

        set lx $L(left_x)
        set rx $L(right_x)
        set cx [expr {($lx + $rx) / 2}]

        # v0.21.0: title width trimmed clear of the header's corners --
        # the auto toggle now lives in the top-right mode-button slot.
        dui add dtext $page $cx $L(header_solo_title_y) -tags page_title \
            -text [translate "New Tracker"] \
            -font $L(font_title) \
            -width [expr {$L(content_w) - 2 * ($L(btn_w_xwide) + $L(lg))}] \
            -fill $L(text_hi) -anchor center -justify center

        # v0.21.0: auto-record source toggle, top-right header corner
        # (the design system's mode-button slot -- the same place the
        # main page's theme button and Detail's Edit button live; the
        # page is otherwise full, and the choice IS a mode of the new
        # tracker). Face carries the current value ("Auto: off" ->
        # "Auto: Clean cycle" -> "Auto: Descale cycle"); created with
        # its real initial label (v0.7.1 rule) and relabeled by
        # refresh.
        set at_y1 [expr {int(round(22 * $L(scale)))}]
        dui add dbutton $page [expr {$rx - $L(btn_w_xwide)}] $at_y1 \
            $rx [expr {$at_y1 + $L(btn_h)}] \
            -tags btn_auto \
            -label "[translate {Auto:}] [::plugins::MaintenanceTracker::_auto_src_short {}]" \
            -command ::dui::pages::MaintenanceTracker_add::toggle_auto \
            -label_font $L(font_button) -style mt_btn

        # v0.29.1: three cards. Card 1: name (left) | counting unit +
        # Change (right), the unit's hint under both, a divider, then
        # the due-after stepper row. Card 2: icon picker. Card 3: hidden
        # trackers (shown only when there are any).
        set ix1 [expr {$lx + $L(card_pad_x)}]
        set ix2 [expr {$rx - $L(card_pad_x)}]
        set c1y0 $L(add_c1_y0)
        ::plugins::MaintenanceTracker::_sec_card $page add_c1 $lx $c1y0 $rx $L(add_c1_y1) ""

        # Name entry, top half of the screen (Android keyboard rule).
        # v0.9.0: the whole column moved up to make room for the icon
        # picker row above the error line.
        set name_label_y [expr {$c1y0 + int(round(16 * $L(scale)))}]
        set entry_y [expr {$c1y0 + int(round(42 * $L(scale)))}]
        set col_x $L(add_col_x)
        dui add dtext $page $ix1 $name_label_y -tags name_label \
            -text [translate "Tracker name (e.g. \"Grinder 2 burr clean\"):"] \
            -font $L(font_caption) -width [expr {$col_x - $L(lg) - $ix1}] -fill $L(text_body) \
            -anchor nw -justify left
        dui add entry $page $ix1 $entry_y -tags name_entry \
            -textvariable ::plugins::MaintenanceTracker::add_label \
            -width 30 -font $L(font_primary) -borderwidth 1 -bg $L(entry_bg) \
            -foreground $L(text_hi) -relief flat

        # Unit column: label / current unit, Change button on the right.
        dui add canvas_item rect $page $col_x $name_label_y [expr {$col_x + $L(div_h)}] \
            [expr {$c1y0 + int(round(76 * $L(scale)))}] \
            -fill $L(card_outline) -outline "" -width 0 -tags add_c1_vdiv
        set ux [expr {$col_x + $L(lg)}]
        set chg_x0 [expr {$ix2 - $L(btn_w_std)}]
        dui add dtext $page $ux $name_label_y -tags unit_label \
            -text [translate "Counts:"] \
            -font $L(font_caption) -width [expr {$chg_x0 - $L(lg) - $ux}] -fill $L(text_body) \
            -anchor nw -justify left
        dui add dtext $page $ux [expr {$c1y0 + int(round(38 * $L(scale)))}] -tags unit_value -text "" \
            -font $L(font_primary) -width [expr {$chg_x0 - $L(lg) - $ux}] \
            -fill $L(text_hi) -anchor nw -justify left
        dui add dbutton $page $chg_x0 [expr {$c1y0 + int(round(14 * $L(scale)))}] \
            $ix2 [expr {$c1y0 + int(round(14 * $L(scale))) + $L(btn_h)}] \
            -tags unit_toggle -label [translate "Change"] \
            -command ::dui::pages::MaintenanceTracker_add::toggle_unit \
            -label_font $L(font_button) -style mt_btn
        # The hint spans the card (two caption lines at most, even for
        # the long ml wording).
        set hint_y [expr {$c1y0 + int(round(86 * $L(scale)))}]
        dui add dtext $page $ix1 $hint_y -tags unit_hint -text "" \
            -font $L(font_caption) -width [expr {$ix2 - $ix1}] -fill $L(text_mut) \
            -anchor nw -justify left
        ::plugins::MaintenanceTracker::_sec_divider $page add_c1_div \
            $lx [expr {$c1y0 + int(round(138 * $L(scale)))}] $rx

        # Threshold: label left, stepper row right-aligned in the card
        # (burr pattern); the value sits on an entry-coloured plate.
        set step_y1 [expr {$c1y0 + int(round(150 * $L(scale)))}]
        set step_y2 [expr {$step_y1 + $L(btn_h)}]
        set step_w [expr {int(round(120 * $L(scale)))}]
        set value_w [expr {int(round(120 * $L(scale)))}]
        set row_w [expr {4 * $step_w + $value_w + 4 * $L(md)}]
        set x [expr {$ix2 - $row_w}]
        dui add dtext $page $ix1 [expr {($step_y1 + $step_y2) / 2}] -tags thr_label \
            -text [translate "Due after this many days / shots / ml:"] \
            -font $L(font_body) -width [expr {$x - $L(lg) - $ix1}] -fill $L(text_body) \
            -anchor w -justify left
        set vb_x1 [expr {$x + 2 * ($step_w + $L(md))}]
        ::plugins::MaintenanceTracker::rounded_rect $page $vb_x1 $step_y1 \
            [expr {$vb_x1 + $value_w}] $step_y2 $L(btn_radius) \
            -fill $L(entry_bg) -outline $L(entry_bg) -width 1 -tags thr_box
        # v0.7.1: the creation labels MUST be non-empty -- a dbutton
        # created with -label "" never gets a label sub-item at all
        # (de1app-core/dui.tcl:10227-10235 only adds the dtext when the
        # label is non-empty), so later `dui item config -label` has
        # nothing to configure and the button face stays blank forever.
        # Seed with the days-unit labels; refresh reconfigures per unit.
        foreach i {0 1} lbl {-10 -1} {
            dui add dbutton $page $x $step_y1 [expr {$x + $step_w}] $step_y2 \
                -tags step$i -label $lbl \
                -command [list ::dui::pages::MaintenanceTracker_add::step_click $i] \
                -label_font $L(font_button) -style mt_btn
            set x [expr {$x + $step_w + $L(md)}]
        }
        dui add variable $page [expr {$x + $value_w / 2}] [expr {($step_y1 + $step_y2) / 2}] \
            -tags thr_value -fill $L(text_hi) -font $L(font_primary) -anchor center -justify center \
            -textvariable {$::plugins::MaintenanceTracker::add_threshold}
        set x [expr {$x + $value_w + $L(md)}]
        foreach i {2 3} lbl {+1 +10} {
            dui add dbutton $page $x $step_y1 [expr {$x + $step_w}] $step_y2 \
                -tags step$i -label $lbl \
                -command [list ::dui::pages::MaintenanceTracker_add::step_click $i] \
                -label_font $L(font_button) -style mt_btn
            set x [expr {$x + $step_w + $L(md)}]
        }

        # v0.9.0: icon picker for the custom tracker (glyphs from the
        # app's FA6 Pro symbol table); v0.14.0: two rows of 12 (the
        # shared builder wraps at picker_cols). Cells: white backdrop
        # whose outline marks the selection, glyph dtext, invisible tap
        # dbutton (the proven card-tap mechanism).
        # v0.29.1: Icon card -- "Icon:  <name>" is its header, the grid
        # inset by the card padding.
        set c2y0 $L(add_c2_y0)
        ::plugins::MaintenanceTracker::_sec_card $page add_c2 $lx $c2y0 $rx $L(add_c2_y1) ""
        set icon_label_y [expr {$c2y0 + $L(sec_head_h) / 2}]
        dui add dtext $page $ix1 $icon_label_y -tags icon_label \
            -text [translate "Icon:"] \
            -font $L(font_primary) -width $L(label_col_w) -fill $L(text_hi) \
            -anchor w -justify left
        # Validation message (red, empty until add_save rejects) shares
        # the Icon: label's line (v0.14.0 -- the second picker row took
        # its old slot). Width trimmed on both sides so the centered
        # text can never reach the left label.
        dui add dtext $page $cx $icon_label_y -tags add_error_text -text "" \
            -font $L(font_primary) \
            -width [expr {$L(content_w) - 2 * int(round(160 * $L(scale)))}] \
            -fill $L(col_red) -anchor center -justify center
        ::plugins::MaintenanceTracker::_build_picker_row $page \
            [expr {$c2y0 + $L(sec_head_h)}] \
            [list ::dui::pages::MaintenanceTracker_add::select_icon] $L(card_pad_x)

        # v0.10.0: hidden built-in trackers -- caption plus one chip
        # button PER hidden tracker (max 6 built-ins, so 6 fixed slots
        # relabeled/shown per refresh; created with non-empty placeholder
        # labels so the label sub-item exists -- the v0.7.1 lesson).
        # Tapping a chip restores just that tracker.
        # v0.14.0: moved up (was 612/635) to keep >= md clearance under
        # the second picker row while the chips keep their bar_y0 gap.
        # v0.29.1: in the Hidden trackers card (shown with the chips).
        set c3y0 $L(add_c3_y0)
        ::plugins::MaintenanceTracker::rounded_rect $page $lx $c3y0 $rx $L(add_c3_y1) $L(btn_radius) \
            -fill $L(card_bg) -outline $L(card_outline) -width 2 -tags add_c3 -initial_state hidden
        set hid_title_y [expr {$c3y0 + $L(sec_head_h) / 2}]
        dui add dtext $page $ix1 $hid_title_y -tags hidden_title \
            -text [translate "Hidden trackers -- tap one to restore it:"] \
            -font $L(font_body) -width [expr {$ix2 - $ix1}] \
            -fill $L(text_hi) -anchor w -justify left -initial_state hidden
        set chip_gap [expr {int(round(12 * $L(scale)))}]
        set chip_w [expr {min(int(round(186 * $L(scale))), ($ix2 - $ix1 - 5 * $chip_gap) / 6)}]
        set chip_y1 [expr {$c3y0 + $L(sec_head_h)}]
        set chip_y2 [expr {$chip_y1 + $L(btn_h)}]
        for {set k 0} {$k < 6} {incr k} {
            set cx1 [expr {$ix1 + $k * ($chip_w + $chip_gap)}]
            dui add dbutton $page $cx1 $chip_y1 [expr {$cx1 + $chip_w}] $chip_y2 \
                -tags hid$k -label "-" \
                -command [list ::dui::pages::MaintenanceTracker_add::hid_click $k] \
                -label_font $L(font_button) -style mt_btn -initial_state hidden
        }

        # Bottom bar: Cancel left, Add Tracker right.
        dui add dbutton $page $lx $L(bar_y0) [expr {$lx + $L(btn_w_std)}] $L(bar_y1) \
            -tags mt_cancel -label [translate "Cancel"] \
            -command ::plugins::MaintenanceTracker::cancel_add \
            -label_font $L(font_button) -style mt_btn
        dui add dbutton $page [expr {$rx - $L(btn_w_wide)}] $L(bar_y0) $rx $L(bar_y1) \
            -tags mt_save -label [translate "Save"] \
            -command ::plugins::MaintenanceTracker::add_save \
            -label_font $L(font_button) -style mt_btn
    }

    proc refresh {} {
        set page [namespace tail [namespace current]]
        set unit $::plugins::MaintenanceTracker::add_unit
        if {$unit eq "shots"} {
            set unit_txt [translate "shots since last done"]
            set hint [translate "Counts EVERY shot on the machine -- the shot database cannot tell which grinder pulled which shot. Use days if this gear does not see every shot."]
        } elseif {$unit eq "ml"} {
            set unit_txt [translate "ml of water dispensed"]
            set hint [translate "Counts ALL water the machine dispenses -- espresso, steam, hot water, flushes and cleaning cycles -- since the last record. The meter only runs while this app is running."]
        } else {
            set unit_txt [translate "days since last done"]
            set hint [translate "Goes amber, then red, as days pass since the last record."]
        }
        catch { dui item config $page unit_value -text $unit_txt }
        catch { dui item config $page unit_hint -text $hint }
        # Stepper labels follow the unit's magnitude. BARE tags only:
        # the wildcard form silently fails for -label on-device (v0.6.2).
        set deltas [::plugins::MaintenanceTracker::_add_step_deltas]
        foreach i {0 1 2 3} {
            set d [lindex $deltas $i]
            # NOT via expr: a braced expr canonicalizes "+10" back to 10.
            set lbl $d
            if {$d > 0} { set lbl "+$d" }
            catch { dui item config $page step$i -label $lbl }
        }
        catch { dui item config $page add_error_text \
            -text $::plugins::MaintenanceTracker::add_error }
        # v0.21.0: auto toggle face follows the current choice. BARE
        # tag (the v0.6.2 wildcard rule).
        catch { dui item config $page btn_auto \
            -label "[translate {Auto:}] [::plugins::MaintenanceTracker::_auto_src_short \
                $::plugins::MaintenanceTracker::add_auto]" }
        # v0.9.0: selection outline on the icon picker (shared helper).
        ::plugins::MaintenanceTracker::_refresh_picker $page \
            $::plugins::MaintenanceTracker::add_icon
        # v0.10.0: per-item restore chips. The rendered id list is cached
        # so a chip tap restores exactly the tracker whose name it wears.
        variable hidden_shown
        set hidden {}
        catch { set hidden $::plugins::MaintenanceTracker::settings(hidden_ids) }
        set hidden_shown $hidden
        if {[llength $hidden] > 0} {
            catch { dui item show $page add_c3 -initial 1 }
            catch { dui item show $page hidden_title -initial 1 }
        } else {
            catch { dui item hide $page add_c3 -initial 1 }
            catch { dui item hide $page hidden_title -initial 1 }
        }
        for {set k 0} {$k < 6} {incr k} {
            if {$k < [llength $hidden]} {
                catch { dui item config $page hid$k \
                    -label [::plugins::MaintenanceTracker::_item_label [lindex $hidden $k]] }
                catch { dui item show $page hid$k* -initial 1 }
            } else {
                catch { dui item hide $page hid$k* -initial 1 }
            }
        }
    }

    # Ids currently shown on the restore chips, in chip order (set by
    # refresh; a tap maps through this, never through live settings).
    variable hidden_shown {}

    proc hid_click {k} {
        variable hidden_shown
        if {$k < 0 || $k >= [llength $hidden_shown]} { return }
        ::plugins::MaintenanceTracker::unhide_item [lindex $hidden_shown $k]
        if {[catch { refresh } err]} {
            catch { msg "MaintenanceTracker: add refresh failed: $err" }
        }
    }

    proc toggle_unit {} {
        ::plugins::MaintenanceTracker::toggle_add_unit
        if {[catch { refresh } err]} {
            catch { msg "MaintenanceTracker: add refresh failed: $err" }
        }
    }

    # v0.21.0: header auto-source toggle.
    proc toggle_auto {} {
        ::plugins::MaintenanceTracker::toggle_add_auto
        if {[catch { refresh } err]} {
            catch { msg "MaintenanceTracker: add refresh failed: $err" }
        }
    }

    proc step_click {i} {
        set deltas [::plugins::MaintenanceTracker::_add_step_deltas]
        ::plugins::MaintenanceTracker::adjust_add_threshold [lindex $deltas $i]
    }

    # v0.9.0: icon picker tap.
    proc select_icon {k} {
        set picker $::plugins::MaintenanceTracker::picker_icons
        if {$k < 0 || $k >= [llength $picker]} { return }
        set ::plugins::MaintenanceTracker::add_icon [lindex $picker $k]
        if {[catch { refresh } err]} {
            catch { msg "MaintenanceTracker: add refresh failed: $err" }
        }
    }

    proc show {page_to_hide page_to_show} {
        # No reset here: open_add seeds the fields, and a flow
        # interruption's re-show must not wipe a half-typed name.
        if {[catch { refresh } err]} {
            catch { msg "MaintenanceTracker: add refresh failed: $err" }
        }
    }
}

# ===========================================================================
#  Edit page -- Pass 12 (rename) extended in Pass 13 to threshold and
#  icon. Name entry prefilled (top half, Android keyboard rule),
#  threshold steppers scaled to the tracker's own unit, and the shared
#  icon picker row. Save rewrites label/threshold/icon only -- history,
#  counting unit and id stay untouched.
# ===========================================================================

namespace eval ::dui::pages::MaintenanceTracker_edit {

    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::MaintenanceTracker::L L
        ::plugins::MaintenanceTracker::_page_bg $page

        set lx $L(left_x)
        set rx $L(right_x)
        set cx [expr {($lx + $rx) / 2}]

        dui add dtext $page $cx $L(header_solo_title_y) -tags page_title \
            -text [translate "Edit Tracker"] \
            -font $L(font_title) -width $L(content_w) -fill $L(text_hi) \
            -anchor center -justify center

        # v0.29.1: "Tracker: <name>" is the header's subtitle; the page is
        # three cards like New Tracker's -- name | link, due-after +
        # auto-record (+ the note), icon.
        dui add dtext $page $cx $L(ed_sub_y) -tags edit_current -text "" \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) \
            -anchor center -justify center
        set ix1 [expr {$lx + $L(card_pad_x)}]
        set ix2 [expr {$rx - $L(card_pad_x)}]
        set c1y0 $L(ed_c1_y0)
        ::plugins::MaintenanceTracker::_sec_card $page ed_c1 $lx $c1y0 $rx $L(ed_c1_y1) ""

        set name_label_y [expr {$c1y0 + int(round(14 * $L(scale)))}]
        set entry_y [expr {$c1y0 + int(round(38 * $L(scale)))}]
        dui add dtext $page $ix1 $name_label_y -tags name_label \
            -text [translate "Name:"] \
            -font $L(font_caption) -width [expr {$L(content_w) / 2}] -fill $L(text_body) \
            -anchor nw -justify left
        dui add entry $page $ix1 $entry_y -tags edit_entry \
            -textvariable ::plugins::MaintenanceTracker::edit_label \
            -width 30 -font $L(font_primary) -borderwidth 1 -bg $L(entry_bg) \
            -foreground $L(text_hi) -relief flat

        # v0.25.0 (Pass 31): the link row moved here from Detail, into
        # the empty band right of the name entry (keyboard-safe top
        # zone). "Linked to: <value>" on the Name label's line, buttons
        # on the entry's line, right-aligned (3 x btn_w_std, md gaps;
        # the 30-char entry ends well left of them). Unlinked: [Link
        # profile] [Link Descale] [Link Clean]; linked: [Unlink]. Draft
        # until Save. v0.29.1: inside card 1, a divider between.
        set lk_y0 [expr {$c1y0 + int(round(36 * $L(scale)))}]
        set lk_y1 [expr {$lk_y0 + $L(btn_h)}]
        set lkcl_x0 [expr {$ix2 - $L(btn_w_std)}]
        set lkds_x1 [expr {$lkcl_x0 - $L(md)}]
        set lkds_x0 [expr {$lkds_x1 - $L(btn_w_std)}]
        set lk_x1 [expr {$lkds_x0 - $L(md)}]
        set lk_x0 [expr {$lk_x1 - $L(btn_w_std)}]
        # ONE text item, "Linked to: <value>": a label + value pair placed
        # with `font measure` collided on the tablet (it returns PHYSICAL
        # px, canvas coords are virtual 2560 -- 1.91x short; v0.25.0
        # verify run 1).
        dui add canvas_item rect $page [expr {$lk_x0 - $L(lg)}] $name_label_y \
            [expr {$lk_x0 - $L(lg) + $L(div_h)}] $lk_y1 \
            -fill $L(card_outline) -outline "" -width 0 -tags ed_c1_vdiv
        dui add dtext $page $lk_x0 $name_label_y -tags link_value -text "" \
            -font $L(font_caption) -width [expr {$ix2 - $lk_x0}] -fill $L(text_body) \
            -anchor nw -justify left
        dui add dbutton $page $lk_x0 $lk_y0 $lk_x1 $lk_y1 \
            -tags mt_elink -label [translate "Link profile"] \
            -command ::dui::pages::MaintenanceTracker_edit::link_click \
            -label_font $L(font_button) -style mt_btn -initial_state hidden
        dui add dbutton $page $lkds_x0 $lk_y0 $lkds_x1 $lk_y1 \
            -tags mt_elinkds -label [translate "Link Descale"] \
            -command [list ::dui::pages::MaintenanceTracker_edit::link_kind_click descale] \
            -label_font $L(font_button) -style mt_btn -initial_state hidden
        dui add dbutton $page $lkcl_x0 $lk_y0 $ix2 $lk_y1 \
            -tags mt_elinkcl -label [translate "Link Clean"] \
            -command [list ::dui::pages::MaintenanceTracker_edit::link_kind_click clean] \
            -label_font $L(font_button) -style mt_btn -initial_state hidden
        dui add dbutton $page $lkcl_x0 $lk_y0 $ix2 $lk_y1 \
            -tags mt_eunlink -label [translate "Unlink"] \
            -command ::dui::pages::MaintenanceTracker_edit::unlink_click \
            -label_font $L(font_button) -style mt_btn -initial_state hidden

        # Card 2. Threshold steppers (burr/Add pattern): label left,
        # [-][-] value [+][+] right-aligned (New Tracker's row, value on
        # an entry-coloured plate), deltas relabeled per the unit.
        set c2y0 $L(ed_c2_y0)
        ::plugins::MaintenanceTracker::_sec_card $page ed_c2 $lx $c2y0 $rx $L(ed_c2_y1) ""
        set step_y1 [expr {$c2y0 + int(round(14 * $L(scale)))}]
        set step_y2 [expr {$step_y1 + $L(btn_h)}]
        set step_w [expr {int(round(120 * $L(scale)))}]
        set value_w [expr {int(round(120 * $L(scale)))}]
        set row_w [expr {4 * $step_w + $value_w + 4 * $L(md)}]
        set x [expr {$ix2 - $row_w}]
        dui add dtext $page $ix1 [expr {($step_y1 + $step_y2) / 2}] -tags thr_label -text "" \
            -font $L(font_body) -width [expr {$x - $L(lg) - $ix1}] -fill $L(text_body) \
            -anchor w -justify left
        set vb_x1 [expr {$x + 2 * ($step_w + $L(md))}]
        ::plugins::MaintenanceTracker::rounded_rect $page $vb_x1 $step_y1 \
            [expr {$vb_x1 + $value_w}] $step_y2 $L(btn_radius) \
            -fill $L(entry_bg) -outline $L(entry_bg) -width 1 -tags thr_box
        foreach i {0 1} lbl {-10 -1} {
            dui add dbutton $page $x $step_y1 [expr {$x + $step_w}] $step_y2 \
                -tags step$i -label $lbl \
                -command [list ::dui::pages::MaintenanceTracker_edit::step_click $i] \
                -label_font $L(font_button) -style mt_btn
            set x [expr {$x + $step_w + $L(md)}]
        }
        dui add variable $page [expr {$x + $value_w / 2}] [expr {($step_y1 + $step_y2) / 2}] \
            -tags thr_value -fill $L(text_hi) -font $L(font_primary) -anchor center -justify center \
            -textvariable {$::plugins::MaintenanceTracker::edit_threshold}
        set x [expr {$x + $value_w + $L(md)}]
        foreach i {2 3} lbl {+1 +10} {
            dui add dbutton $page $x $step_y1 [expr {$x + $step_w}] $step_y2 \
                -tags step$i -label $lbl \
                -command [list ::dui::pages::MaintenanceTracker_edit::step_click $i] \
                -label_font $L(font_button) -style mt_btn
            set x [expr {$x + $step_w + $L(md)}]
        }

        # v0.20.0: auto-record row (the Add page's unit-row pattern:
        # label / current value / Change button). Cycles off -> Clean
        # cycle -> Descale cycle; refresh renders the current value.
        # v0.29.1: card 2, under a divider, then the note (history and
        # unit stay) as the card's caption.
        ::plugins::MaintenanceTracker::_sec_divider $page ed_c2_div \
            $lx [expr {$step_y2 + int(round(12 * $L(scale)))}] $rx
        set at_y1 [expr {$step_y2 + int(round(22 * $L(scale)))}]
        set at_mid [expr {$at_y1 + $L(btn_h) / 2}]
        set vx $L(value_x)
        set chg_x0 [expr {$ix2 - $L(btn_w_wide)}]
        dui add dtext $page $ix1 $at_mid -tags auto_label \
            -text [translate "Auto-record:"] \
            -font $L(font_body) -width [expr {$vx - $L(lg) - $ix1}] -fill $L(text_body) \
            -anchor w -justify left
        dui add dtext $page $vx $at_mid -tags auto_value -text "" \
            -font $L(font_primary) -width [expr {$chg_x0 - $L(lg) - $vx}] \
            -fill $L(text_hi) -anchor w -justify left
        dui add dbutton $page $chg_x0 $at_y1 $ix2 [expr {$at_y1 + $L(btn_h)}] \
            -tags auto_toggle -label [translate "Change"] \
            -command ::dui::pages::MaintenanceTracker_edit::toggle_auto \
            -label_font $L(font_button) -style mt_btn
        dui add dtext $page $ix1 [expr {$at_y1 + $L(btn_h) + $L(sm)}] -tags edit_note \
            -text [translate "The tracker's history and its counting unit (days, shots or ml) stay as they are."] \
            -font $L(font_caption) -width [expr {$ix2 - $ix1}] -fill $L(text_mut) \
            -anchor nw -justify left

        # Card 3: icon picker (shared builder, inset like New Tracker's;
        # two rows of 12 since v0.14.0). "Icon:  <name>" is its header.
        set c3y0 $L(ed_c3_y0)
        ::plugins::MaintenanceTracker::_sec_card $page ed_c3 $lx $c3y0 $rx $L(ed_c3_y1) ""
        dui add dtext $page $ix1 [expr {$c3y0 + $L(sec_head_h) / 2}] -tags icon_label \
            -text [translate "Icon:"] \
            -font $L(font_primary) -width $L(label_col_w) -fill $L(text_hi) \
            -anchor w -justify left
        ::plugins::MaintenanceTracker::_build_picker_row $page \
            [expr {$c3y0 + $L(sec_head_h)}] \
            [list ::dui::pages::MaintenanceTracker_edit::select_icon] $L(card_pad_x)

        # Error / armed-delete message between the cards and the bar.
        dui add dtext $page $cx $L(ed_msg_y) -tags edit_error_text -text "" \
            -font $L(font_primary) -width $L(content_w) -fill $L(col_red) \
            -anchor center -justify center

        # Bottom bar per the v0.15.0 button standard: Cancel (left,
        # disarms an armed delete first), Delete Tracker (center,
        # danger, customs only, two-step -- destructive delete lives
        # here, one deliberate level below Detail), Save (right, the
        # page's one positive action, hidden while delete is armed).
        dui add dbutton $page $lx $L(bar_y0) [expr {$lx + $L(btn_w_std)}] $L(bar_y1) \
            -tags mt_cancel -label [translate "Cancel"] \
            -command ::plugins::MaintenanceTracker::cancel_edit \
            -label_font $L(font_button) -style mt_btn
        set cx2 [expr {($lx + $rx) / 2}]
        dui add dbutton $page [expr {$cx2 - $L(btn_w_xwide) / 2}] $L(bar_y0) \
            [expr {$cx2 + $L(btn_w_xwide) / 2}] $L(bar_y1) \
            -tags bar_delete -label [translate "Delete Tracker"] \
            -command ::dui::pages::MaintenanceTracker_edit::delete_click \
            -label_font $L(font_button) -style mt_btn_danger -initial_state hidden
        dui add dbutton $page [expr {$rx - $L(btn_w_std)}] $L(bar_y0) $rx $L(bar_y1) \
            -tags mt_save -label [translate "Save"] \
            -command ::plugins::MaintenanceTracker::edit_save \
            -label_font $L(font_button) -style mt_btn
    }

    proc refresh {} {
        set page [namespace tail [namespace current]]
        set id $::plugins::MaintenanceTracker::edit_item
        set cur ""
        if {$id ne ""} {
            set cur "[translate {Tracker:}] [::plugins::MaintenanceTracker::_item_label $id]"
        }
        catch { dui item config $page edit_current -text $cur }
        set unit $::plugins::MaintenanceTracker::edit_unit
        catch { dui item config $page thr_label \
            -text "[translate {Due after this many}] [translate $unit]:" }
        # Stepper labels follow the tracker's unit. BARE tags, and never
        # via a braced expr (it canonicalizes "+10" to 10) -- v0.7.1.
        set deltas [::plugins::MaintenanceTracker::_step_deltas_for $unit]
        foreach i {0 1 2 3} {
            set d [lindex $deltas $i]
            set lbl $d
            if {$d > 0} { set lbl "+$d" }
            catch { dui item config $page step$i -label $lbl }
        }
        ::plugins::MaintenanceTracker::_refresh_picker $page \
            $::plugins::MaintenanceTracker::edit_icon
        # v0.20.0: current auto-record source. v0.24.0: "off" on a
        # tracker linked to a cleaning profile says that profile's runs
        # still record it.
        set auto_txt [::plugins::MaintenanceTracker::_auto_src_label \
            $::plugins::MaintenanceTracker::edit_auto]
        if {$::plugins::MaintenanceTracker::edit_auto eq "" && [::plugins::MaintenanceTracker::_item_cleaning_profile \
                $::plugins::MaintenanceTracker::edit_item] ne ""} {
            set auto_txt [translate "off (linked profile records)"]
        }
        catch { dui item config $page auto_value -text $auto_txt }
        # v0.25.0: link draft row.
        set elink $::plugins::MaintenanceTracker::edit_link
        catch { dui item config $page link_value \
            -text "[translate {Linked to:}] [::plugins::MaintenanceTracker::_link_text $elink]" }
        if {$elink eq ""} {
            catch { dui item hide $page mt_eunlink* -initial 1 }
            foreach t {mt_elink* mt_elinkds* mt_elinkcl*} {
                catch { dui item show $page $t -initial 1 }
            }
        } else {
            foreach t {mt_elink* mt_elinkds* mt_elinkcl*} {
                catch { dui item hide $page $t -initial 1 }
            }
            catch { dui item show $page mt_eunlink* -initial 1 }
        }
        # v0.15.0: delete lives here now (customs only), two-step. While
        # armed, Save hides, the button carries the explicit "Yes, ..."
        # label and the message line says exactly what the second tap
        # does; Cancel disarms first (cancel_edit). The error line and
        # the armed message share the same slot -- they can never both
        # apply at once (arming ignores Save, so no validation runs).
        set id $::plugins::MaintenanceTracker::edit_item
        set is_custom [::plugins::MaintenanceTracker::_is_custom_id $id]
        if {$::plugins::MaintenanceTracker::edit_delete_armed && $is_custom} {
            set label [::plugins::MaintenanceTracker::_item_label $id]
            catch { dui item config $page edit_error_text \
                -text "[translate {Delete the tracker}] \"$label\" [translate {and its recorded history?}]" }
            catch { dui item config $page bar_delete -label [translate "Yes, Delete Tracker"] }
            catch { dui item show $page bar_delete* -initial 1 }
            catch { dui item hide $page mt_save* -initial 1 }
        } else {
            catch { dui item config $page edit_error_text \
                -text $::plugins::MaintenanceTracker::edit_error }
            catch { dui item config $page bar_delete -label [translate "Delete Tracker"] }
            if {$is_custom} {
                catch { dui item show $page bar_delete* -initial 1 }
            } else {
                catch { dui item hide $page bar_delete* -initial 1 }
            }
            catch { dui item show $page mt_save* -initial 1 }
        }
    }

    proc step_click {i} {
        if {$::plugins::MaintenanceTracker::edit_delete_armed} { return }
        set deltas [::plugins::MaintenanceTracker::_step_deltas_for \
            $::plugins::MaintenanceTracker::edit_unit]
        ::plugins::MaintenanceTracker::adjust_edit_threshold [lindex $deltas $i]
    }

    # v0.20.0: cycle the auto-record source (no-op while a delete is
    # armed, like every other editing control on this page).
    proc toggle_auto {} {
        if {$::plugins::MaintenanceTracker::edit_delete_armed} { return }
        ::plugins::MaintenanceTracker::toggle_edit_auto
        if {[catch { refresh } err]} {
            catch { msg "MaintenanceTracker: edit refresh failed: $err" }
        }
    }

    # v0.25.0: link row taps -- draft only. In-page actions hide the
    # keyboard themselves (CLAUDE.md: only page loads do it for free).
    proc _after_link_tap {} {
        catch { dui platform hide_android_keyboard }
        if {[catch { refresh } err]} {
            catch { msg "MaintenanceTracker: edit refresh failed: $err" }
        }
    }
    proc link_click {} {
        ::plugins::MaintenanceTracker::edit_link_profile
        _after_link_tap
    }
    proc link_kind_click {kind} {
        ::plugins::MaintenanceTracker::edit_link_kind $kind
        _after_link_tap
    }
    proc unlink_click {} {
        ::plugins::MaintenanceTracker::edit_unlink
        _after_link_tap
    }

    # v0.15.0: two-step delete dispatcher (customs only -- re-checked
    # here, belt-and-braces). First tap arms, second deletes and
    # returns to the card list two dialog levels up.
    proc delete_click {} {
        set id $::plugins::MaintenanceTracker::edit_item
        if {![::plugins::MaintenanceTracker::_is_custom_id $id]} { return }
        if {!$::plugins::MaintenanceTracker::edit_delete_armed} {
            set ::plugins::MaintenanceTracker::edit_delete_armed 1
        } else {
            set ::plugins::MaintenanceTracker::edit_delete_armed 0
            if {[::plugins::MaintenanceTracker::delete_custom $id]} {
                set ::plugins::MaintenanceTracker::detail_item ""
                ::plugins::MaintenanceTracker::_return_to_page MaintenanceTracker_settings
                return
            }
        }
        if {[catch { refresh } err]} {
            catch { msg "MaintenanceTracker: edit refresh failed: $err" }
        }
    }

    proc select_icon {k} {
        set picker $::plugins::MaintenanceTracker::picker_icons
        if {$k < 0 || $k >= [llength $picker]} { return }
        set ::plugins::MaintenanceTracker::edit_icon [lindex $picker $k]
        if {[catch { refresh } err]} {
            catch { msg "MaintenanceTracker: edit refresh failed: $err" }
        }
    }

    proc show {page_to_hide page_to_show} {
        # No field reset here: open_edit seeds the fields, and a flow
        # interruption's re-show must not wipe a half-typed name. The
        # armed-delete flag DOES reset (stuck-flag rule: no armed
        # destructive state ever survives a page switch).
        set ::plugins::MaintenanceTracker::edit_delete_armed 0
        if {[catch { refresh } err]} {
            catch { msg "MaintenanceTracker: edit refresh failed: $err" }
        }
    }
}

# ===========================================================================
#  Steps page -- Pass 32 (v0.26.0). The tracker's instructions, numbered,
#  and ONE coloured action under them: the link's own (Load profile /
#  Open Descale / Start Clean, two-tap) or Mark done. Mark done (and a
#  linked tracker's secondary Mark done) is the list's confirm flow,
#  returning to Detail. Nothing here writes anything new.
# ===========================================================================

namespace eval ::dui::pages::MaintenanceTracker_steps {

    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::MaintenanceTracker::L L
        ::plugins::MaintenanceTracker::_page_bg $page
        set lx $L(left_x)
        set rx $L(right_x)
        set cx [expr {($lx + $rx) / 2}]

        # Title width stops short of the header's right corner (Detail's
        # rule) -- v0.28.0's Edit steps button sits there.
        dui add dtext $page $cx $L(header_solo_title_y) -tags page_title -text "" \
            -font $L(font_title) -width [expr {$L(content_w) - 2 * ($L(btn_w_std) + $L(lg))}] \
            -fill $L(text_hi) -anchor center -justify center
        dui add dbutton $page [expr {$rx - $L(btn_w_std)}] [expr {int(round(22 * $L(scale)))}] \
            $rx [expr {int(round(22 * $L(scale))) + $L(btn_h)}] \
            -tags mt_sedit -label [translate "Edit steps"] \
            -command ::dui::pages::MaintenanceTracker_steps::edit_click \
            -label_font $L(font_button) -style mt_btn -initial_state hidden
        set sub_y [expr {int(round(96 * $L(scale)))}]
        dui add dtext $page $cx $sub_y -tags steps_sub -text "" \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) \
            -anchor center -justify center

        # v0.29.1: the steps sit in a Steps card. Up to steps_max rows,
        # 54 ref apart under the card's header: a green numbered badge
        # and the text (body, may wrap to two lines = 46 ref < pitch),
        # one-row dividers between rows. The backdrop's height follows
        # the step count: one backdrop per count 0..steps_max (tags
        # steps_card<n> + the shared steps_card), refresh shows one.
        set n_max $::plugins::MaintenanceTracker::steps_max
        set ix1 [expr {$lx + $L(card_pad_x)}]
        set ix2 [expr {$rx - $L(card_pad_x)}]
        set y0 $L(steps_y0)
        set hy [expr {$y0 + $L(sec_head_h)}]
        for {set k 0} {$k <= $n_max} {incr k} {
            ::plugins::MaintenanceTracker::rounded_rect $page $lx $y0 $rx \
                [expr {$hy + $k * $L(steps_row_h) + $L(sec_pad_y)}] $L(btn_radius) \
                -fill $L(card_bg) -outline $L(card_outline) -width 2 \
                -tags [list steps_card$k steps_card] -initial_state hidden
        }
        dui add dtext $page $ix1 [expr {$y0 + $L(sec_head_h) / 2}] -tags steps_card_title \
            -text [translate "Steps"] -font $L(font_primary) -fill $L(text_hi) \
            -anchor w -justify left
        dui add dtext $page $ix2 [expr {$y0 + $L(sec_head_h) / 2}] -tags steps_count -text "" \
            -font $L(font_caption) -fill $L(text_mut) -anchor e -justify right
        ::plugins::MaintenanceTracker::_sec_divider $page steps_card_div $lx $hy $rx
        set txt_x [expr {$ix1 + $L(badge) + $L(md)}]
        for {set i 0} {$i < $n_max} {incr i} {
            set ry0 [expr {$hy + $i * $L(steps_row_h)}]
            set rcy [expr {$ry0 + $L(steps_row_h) / 2}]
            ::plugins::MaintenanceTracker::_sec_badge $page stepb$i \
                [expr {$ix1 + $L(badge) / 2}] $rcy -initial_state hidden
            dui add dtext $page $txt_x $rcy -tags stept$i -text "" \
                -font $L(font_body) -width [expr {$ix2 - $txt_x}] \
                -fill $L(text_hi) -anchor w -justify left
            if {$i < $n_max - 1} {
                ::plugins::MaintenanceTracker::_sec_divider $page stepd$i \
                    $txt_x [expr {$ry0 + $L(steps_row_h)}] $ix2 -initial_state hidden
            }
        }

        # v0.29.1: the message slot is a callout card above the bar,
        # shown only with a message: green tint for the run hint, red
        # tint for the armed Clean, the plain card for a note.
        ::plugins::MaintenanceTracker::rounded_rect $page $lx $L(call_y0) $rx $L(call_y1) \
            $L(btn_radius) -fill $L(card_bg) -outline $L(card_outline) -width 2 \
            -tags steps_call -initial_state hidden
        set msg_y [expr {($L(call_y0) + $L(call_y1)) / 2}]
        dui add dtext $page $cx $msg_y -tags steps_msg -text "" \
            -font $L(font_primary) -width [expr {$ix2 - $ix1}] -fill $L(text_hi) \
            -anchor center -justify center
        # v0.27.0: while a profile run is armed, the message slot becomes
        # a hint row: the group head's cup glyph + what to do and when
        # the espresso profile comes back. Both born hidden.
        # v0.28.1: the cup is the group head's own espresso icon (owner
        # photo of the DE1 GHC: solid bowl with a slot, ring handle,
        # saucer bar), drawn 72 ref wide -- the font glyph was a
        # different, smaller cup.
        set ghc_w [expr {int(round(76 * $L(scale)))}]
        ::plugins::MaintenanceTracker::_add_ghc_cup $page steps_ghc \
            [expr {$ix1 + $ghc_w / 2}] $msg_y [expr {int(round(72 * $L(scale)))}] $L(col_ok)
        dui add dtext $page [expr {$ix1 + $ghc_w + $L(md)}] $msg_y -tags steps_hint -text "" \
            -font $L(font_primary) -width [expr {$ix2 - $ix1 - $ghc_w - $L(md)}] \
            -fill $L(text_hi) -anchor w -justify left -initial_state hidden

        # Bottom bar: [Back] ... [Mark done] [<action>]. The action is the
        # page's one primary (green, xwide, right); Mark done (normal)
        # shows only when the action is something else.
        set go_x0 [expr {$rx - $L(btn_w_xwide)}]
        set done_x1 [expr {$go_x0 - $L(lg)}]
        dui add dbutton $page $lx $L(bar_y0) [expr {$lx + $L(btn_w_std)}] $L(bar_y1) \
            -tags mt_sback -label [translate "Back"] \
            -command ::dui::pages::MaintenanceTracker_steps::back_click \
            -label_font $L(font_button) -style mt_btn
        dui add dbutton $page [expr {$done_x1 - $L(btn_w_wide)}] $L(bar_y0) $done_x1 $L(bar_y1) \
            -tags mt_sdone -label [translate "Mark done"] \
            -command ::dui::pages::MaintenanceTracker_steps::done_click \
            -label_font $L(font_button) -style mt_btn -initial_state hidden
        dui add dbutton $page $go_x0 $L(bar_y0) $rx $L(bar_y1) \
            -tags mt_sgo -label [translate "Mark done"] \
            -command ::dui::pages::MaintenanceTracker_steps::go_click \
            -label_font $L(font_button) -style mt_btn_primary -initial_state hidden
    }

    proc refresh {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::MaintenanceTracker::L L
        set id $::plugins::MaintenanceTracker::steps_item
        set n_max $::plugins::MaintenanceTracker::steps_max
        if {$id eq "" || ![info exists ::plugins::MaintenanceTracker::settings(item_$id)]} {
            catch { dui item config $page page_title -text [translate "Nothing selected"] }
            catch { dui item config $page steps_sub -text "" }
            _show_rows $page {}
            catch { dui item config $page steps_msg -text "" }
            ::plugins::MaintenanceTracker::_show_ghc_cup $page steps_ghc 0
            catch { dui item hide $page steps_hint -initial 1 }
            _show_callout $page ""
            catch { dui item hide $page mt_sdone* -initial 1 }
            catch { dui item hide $page mt_sgo* -initial 1 }
            catch { dui item hide $page mt_sedit* -initial 1 }
            return
        }
        catch { dui item show $page mt_sedit* -initial 1 }
        catch { dui item config $page page_title \
            -text [::plugins::MaintenanceTracker::_item_label $id] }
        set link [::plugins::MaintenanceTracker::_item_link $id]
        set kind [lindex $link 0]
        if {$kind eq ""} {
            set sub [translate "Not linked to a machine action -- tap Mark done when you have finished."]
        } else {
            set sub "[translate {Linked to:}] [::plugins::MaintenanceTracker::_link_text $link]"
        }
        catch { dui item config $page steps_sub -text $sub }
        _show_rows $page [::plugins::MaintenanceTracker::_item_steps $id]
        set armed [expr {$kind eq "clean" && $::plugins::MaintenanceTracker::clean_armed}]
        # v0.27.0: a pending profile run for THIS tracker owns the slot.
        set run [expr {$kind eq "profile" && [::plugins::MaintenanceTracker::_run_pending_for $id]}]
        if {$run} {
            set rr [::plugins::MaintenanceTracker::_run_pending]
            set back_at [clock format [expr {[dict get $rr ts] + $::plugins::MaintenanceTracker::run_timeout_s}] -format %H:%M]
            if {$::plugins::MaintenanceTracker::run_started} {
                set hint "[translate {Running. Your profile}] [dict get $rr prev_title] [translate {comes back when it finishes.}]"
            } else {
                set hint "[translate {Press this button on the group head to start.}] [dict get $rr prev_title] [translate {comes back after the run, or at}] $back_at."
            }
            catch { dui item config $page steps_hint -text $hint }
            catch { dui item config $page steps_msg -text "" }
            ::plugins::MaintenanceTracker::_show_ghc_cup $page steps_ghc 1 $L(tint_ok)
            catch { dui item show $page steps_hint -initial 1 }
        } else {
            ::plugins::MaintenanceTracker::_show_ghc_cup $page steps_ghc 0
            catch { dui item hide $page steps_hint -initial 1 }
        }
        if {$run} {
            _show_callout $page ok
        } elseif {$armed} {
            catch { dui item config $page steps_msg \
                -text [translate "Blind basket and cleaning tablet in the group head? Tap again to start the clean cycle."] \
                -fill $L(text_hi) }
            _show_callout $page red
        } elseif {$::plugins::MaintenanceTracker::prof_note ne ""} {
            catch { dui item config $page steps_msg \
                -text $::plugins::MaintenanceTracker::prof_note -fill $L(text_hi) }
            _show_callout $page note
        } else {
            catch { dui item config $page steps_msg -text "" }
            _show_callout $page ""
        }
        # Relabel through the BARE dbutton tag (the wildcard form
        # silently fails on-device).
        catch { dui item config $page mt_sgo -label [::plugins::MaintenanceTracker::_steps_action_label $id] }
        # v0.27.0: "Switch back now" is a way out, not the go-ahead: normal
        # face while a run is pending, green otherwise (bare-tag recolor).
        set face [expr {$run ? $L(btn_fill) : $L(col_ok)}]
        catch { dui item config $page mt_sgo-btn -fill $face -outline $face }
        catch { dui item show $page mt_sgo* -initial 1 }
        if {$kind eq "" || $run} {
            catch { dui item hide $page mt_sdone* -initial 1 }
        } else {
            catch { dui item show $page mt_sdone* -initial 1 }
        }
    }

    # v0.29.1: the Steps card for a list of steps -- badge + text per
    # row, dividers between rows, the backdrop sized to the count, the
    # count on the header's right.
    proc _show_rows {page steps} {
        upvar #0 ::plugins::MaintenanceTracker::L L
        set n_max $::plugins::MaintenanceTracker::steps_max
        set n [llength $steps]
        if {$n > $n_max} { set n $n_max }
        for {set i 0} {$i < $n_max} {incr i} {
            set on [expr {$i < $n}]
            if {$on} {
                catch { dui item config $page stepb${i}_n -text [expr {$i + 1}] }
                catch { dui item config $page stept$i -text [lindex $steps $i] }
            } else {
                catch { dui item config $page stept$i -text "" }
            }
            foreach t [list stepb$i stepb${i}_n] {
                catch { dui item [expr {$on ? "show" : "hide"}] $page $t -initial 1 }
            }
            if {$i < $n_max - 1} {
                catch { dui item [expr {$i + 1 < $n ? "show" : "hide"}] $page stepd$i -initial 1 }
            }
        }
        for {set k 0} {$k <= $n_max} {incr k} {
            catch { dui item [expr {$k == $n ? "show" : "hide"}] $page steps_card$k -initial 1 }
        }
        if {$n == 0} {
            set cnt ""
        } elseif {$n == 1} {
            set cnt [translate "1 step"]
        } else {
            set cnt "$n [translate {steps}]"
        }
        catch { dui item config $page steps_count -text $cnt }
    }

    # v0.29.1: the message callout -- ok (green tint, the run hint), red
    # (red tint, the armed Clean), note (plain card) or "" (hidden).
    proc _show_callout {page kind} {
        upvar #0 ::plugins::MaintenanceTracker::L L
        switch -- $kind {
            ok   { set f $L(tint_ok) ;  set o $L(col_ok) }
            red  { set f $L(tint_red) ; set o $L(col_red) }
            note { set f $L(card_bg) ;  set o $L(card_outline) }
            default {
                catch { dui item hide $page steps_call -initial 1 }
                return
            }
        }
        catch { dui item config $page steps_call -fill $f -outline $o }
        catch { dui item show $page steps_call -initial 1 }
    }

    proc back_click {} {
        ::plugins::MaintenanceTracker::_disarm_clean
        ::plugins::MaintenanceTracker::_return_to_page MaintenanceTracker_detail
    }

    # v0.28.0: the step editor for this tracker.
    proc edit_click {} {
        set id $::plugins::MaintenanceTracker::steps_item
        if {$id eq ""} { return }
        ::plugins::MaintenanceTracker::_disarm_clean
        ::plugins::MaintenanceTracker::open_step_editor $id
    }

    proc done_click {} {
        set id $::plugins::MaintenanceTracker::steps_item
        if {$id eq ""} { return }
        ::plugins::MaintenanceTracker::_disarm_clean
        ::plugins::MaintenanceTracker::request_record $id MaintenanceTracker_detail
    }

    # The coloured action. A page the tap has left (Descale opened, Clean
    # started, Record's confirm) is not repainted.
    proc go_click {} {
        set id $::plugins::MaintenanceTracker::steps_item
        if {$id eq ""} { return }
        switch -- [lindex [::plugins::MaintenanceTracker::_item_link $id] 0] {
            profile {
                # v0.27.0: Start (remember, switch, switch back later) or,
                # while that run is pending, Switch back now.
                if {[::plugins::MaintenanceTracker::_run_pending_for $id]} {
                    ::plugins::MaintenanceTracker::cancel_profile_run
                } else {
                    ::plugins::MaintenanceTracker::start_profile_run $id
                }
            }
            descale {
                if {[::plugins::MaintenanceTracker::open_linked_descale $id]} { return }
            }
            clean {
                if {[::plugins::MaintenanceTracker::clean_tap $id] eq "started"} { return }
            }
            default {
                done_click
                return
            }
        }
        if {[catch { refresh } err]} {
            catch { msg "MaintenanceTracker: steps refresh failed: $err" }
        }
    }

    proc show {page_to_hide page_to_show} {
        # Stuck-flag rule: no armed Clean survives a page switch.
        ::plugins::MaintenanceTracker::_disarm_clean
        if {![::plugins::MaintenanceTracker::_page_is_current MaintenanceTracker_steps]} { return }
        if {[catch { refresh } err]} {
            catch { msg "MaintenanceTracker: steps refresh failed: $err" }
        }
    }
}

# ===========================================================================
#  Step editor page -- Pass 34 (v0.28.0). List mode: up to 8 numbered
#  rows, each with Up / Down / Remove; tap a row's text to edit it. Bar:
#  Cancel, Reset to default, Add step, Save (green). Form mode: one entry
#  in the keyboard-safe top zone with Cancel / Save step right under it;
#  the rows and the bar step aside. Everything edits the draft; only Save
#  writes (::plugins::MaintenanceTracker::se_save).
# ===========================================================================

namespace eval ::dui::pages::MaintenanceTracker_stepedit {

    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::MaintenanceTracker::L L
        ::plugins::MaintenanceTracker::_page_bg $page
        set lx $L(left_x)
        set rx $L(right_x)
        set cx [expr {($lx + $rx) / 2}]
        set n_max $::plugins::MaintenanceTracker::steps_max

        dui add dtext $page $cx $L(header_solo_title_y) -tags page_title \
            -text [translate "Edit steps"] \
            -font $L(font_title) -width $L(content_w) -fill $L(text_hi) \
            -anchor center -justify center
        set sub_y [expr {int(round(96 * $L(scale)))}]
        dui add dtext $page $cx $sub_y -tags se_sub -text "" \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) \
            -anchor center -justify center

        # List rows inside a Steps card (v0.29.1): 64 ref apart under the
        # card's header, buttons 56 tall (the card action size) centred
        # in the row; row 8 ends at 682, the card at 690, the bar starts
        # at 716. Right to left inside the card: Remove (130), Down
        # (100), Up (100), md apart; the text stops xl short of Up. A
        # green numbered badge leads each row; dividers between rows.
        # Backdrop per count 0..steps_max (se_card<n> + shared se_card).
        set y0 $L(steps_y0)
        set hy [expr {$y0 + $L(sec_head_h)}]
        set pitch $L(se_row_h)
        set bh $L(se_btn_h)
        set ix1 [expr {$lx + $L(card_pad_x)}]
        set ix2 [expr {$rx - $L(card_pad_x)}]
        set rm_w [expr {int(round(130 * $L(scale)))}]
        set ud_w [expr {int(round(100 * $L(scale)))}]
        set rm_x0 [expr {$ix2 - $rm_w}]
        set dn_x1 [expr {$rm_x0 - $L(md)}] ; set dn_x0 [expr {$dn_x1 - $ud_w}]
        set up_x1 [expr {$dn_x0 - $L(md)}] ; set up_x0 [expr {$up_x1 - $ud_w}]
        set txt_x [expr {$ix1 + $L(badge) + $L(md)}]
        set txt_w [expr {$up_x0 - $L(xl) - $txt_x}]
        for {set k 0} {$k <= $n_max} {incr k} {
            ::plugins::MaintenanceTracker::rounded_rect $page $lx $y0 $rx \
                [expr {$hy + $k * $pitch + $L(sec_pad_y)}] $L(btn_radius) \
                -fill $L(card_bg) -outline $L(card_outline) -width 2 \
                -tags [list se_card$k se_card] -initial_state hidden
        }
        dui add dtext $page $ix1 [expr {$y0 + $L(sec_head_h) / 2}] -tags se_card_title \
            -text [translate "Steps"] -font $L(font_primary) -fill $L(text_hi) \
            -anchor w -justify left -initial_state hidden
        dui add dtext $page $ix2 [expr {$y0 + $L(sec_head_h) / 2}] -tags se_count -text "-" \
            -font $L(font_caption) -fill $L(text_mut) -anchor e -justify right \
            -initial_state hidden
        ::plugins::MaintenanceTracker::_sec_divider $page se_card_div $lx $hy $rx \
            -initial_state hidden
        for {set i 0} {$i < $n_max} {incr i} {
            set y [expr {$hy + $i * $pitch + ($pitch - $bh) / 2}]
            set ym [expr {$y + $bh / 2}]
            ::plugins::MaintenanceTracker::_sec_badge $page se_b$i \
                [expr {$ix1 + $L(badge) / 2}] $ym -initial_state hidden
            dui add dtext $page $txt_x $ym -tags se_t$i -text "" \
                -font $L(font_body) -width $txt_w -fill $L(text_hi) -anchor w -justify left
            if {$i < $n_max - 1} {
                ::plugins::MaintenanceTracker::_sec_divider $page se_d$i \
                    $txt_x [expr {$hy + ($i + 1) * $pitch}] $ix2 -initial_state hidden
            }
            # Invisible tap zone over badge + text (the card-open rect
            # pattern: no style, so no pressfill that could stick).
            dui add dbutton $page $lx $y [expr {$up_x0 - $L(xl)}] [expr {$y + $bh}] \
                -tags mt_serow$i \
                -command [list ::dui::pages::MaintenanceTracker_stepedit::row_click $i] \
                -initial_state hidden
            dui add dbutton $page $up_x0 $y $up_x1 [expr {$y + $bh}] \
                -tags mt_seup$i -label [translate "Up"] \
                -command [list ::dui::pages::MaintenanceTracker_stepedit::move_click $i -1] \
                -label_font $L(font_button) -style mt_btn -initial_state hidden
            dui add dbutton $page $dn_x0 $y $dn_x1 [expr {$y + $bh}] \
                -tags mt_sedn$i -label [translate "Down"] \
                -command [list ::dui::pages::MaintenanceTracker_stepedit::move_click $i 1] \
                -label_font $L(font_button) -style mt_btn -initial_state hidden
            dui add dbutton $page $rm_x0 $y $ix2 [expr {$y + $bh}] \
                -tags mt_serm$i -label [translate "Remove"] \
                -command [list ::dui::pages::MaintenanceTracker_stepedit::remove_click $i] \
                -label_font $L(font_button) -style mt_btn -initial_state hidden
        }

        # Form mode (top zone, y < 400 ref): caption, entry, hint, then
        # Cancel / Save step, on a card (v0.29.1). Born hidden.
        set fcap_y [expr {int(round(138 * $L(scale)))}]
        set fent_y [expr {int(round(170 * $L(scale)))}]
        set fhint_y [expr {int(round(220 * $L(scale)))}]
        set fbtn_y [expr {int(round(254 * $L(scale)))}]
        ::plugins::MaintenanceTracker::rounded_rect $page $lx $y0 $rx \
            [expr {$fbtn_y + $L(btn_h) + $L(card_pad_x)}] $L(btn_radius) \
            -fill $L(card_bg) -outline $L(card_outline) -width 2 \
            -tags se_fcard -initial_state hidden
        dui add dtext $page $ix1 $fcap_y -tags se_fcap -text "" \
            -font $L(font_primary) -fill $L(text_hi) -anchor nw -justify left \
            -initial_state hidden
        dui add entry $page $ix1 $fent_y -tags se_entry \
            -textvariable ::plugins::MaintenanceTracker::se_text \
            -width 90 -font $L(font_body) -borderwidth 1 -bg $L(entry_bg) \
            -foreground $L(text_hi) -relief flat -initial_state hidden
        dui add dtext $page $ix1 $fhint_y -tags se_fhint \
            -text [translate "One line, up to 120 characters."] \
            -font $L(font_caption) -fill $L(text_mut) -anchor nw -justify left \
            -initial_state hidden
        dui add dbutton $page $ix1 $fbtn_y [expr {$ix1 + $L(btn_w_std)}] [expr {$fbtn_y + $L(btn_h)}] \
            -tags mt_sefcancel -label [translate "Cancel"] \
            -command ::dui::pages::MaintenanceTracker_stepedit::form_cancel_click \
            -label_font $L(font_button) -style mt_btn -initial_state hidden
        dui add dbutton $page [expr {$ix2 - $L(btn_w_wide)}] $fbtn_y $ix2 [expr {$fbtn_y + $L(btn_h)}] \
            -tags mt_sefsave -label [translate "Save step"] \
            -command ::dui::pages::MaintenanceTracker_stepedit::form_save_click \
            -label_font $L(font_button) -style mt_btn_primary -initial_state hidden

        # Bottom bar (list mode): [Cancel] [Reset to default] [Add step]
        # [Save] -- Detail's four-slot geometry; Save is the primary.
        set bar_gap [expr {($L(content_w) - 2 * $L(btn_w_std) - 2 * $L(btn_w_xwide)) / 3}]
        set rs_x0 [expr {$lx + $L(btn_w_std) + $bar_gap}]
        set sv_x0 [expr {$rx - $L(btn_w_std)}]
        set ad_x1 [expr {$sv_x0 - $bar_gap}]
        dui add dbutton $page $lx $L(bar_y0) [expr {$lx + $L(btn_w_std)}] $L(bar_y1) \
            -tags mt_secancel -label [translate "Cancel"] \
            -command ::dui::pages::MaintenanceTracker_stepedit::cancel_click \
            -label_font $L(font_button) -style mt_btn -initial_state hidden
        dui add dbutton $page $rs_x0 $L(bar_y0) [expr {$rs_x0 + $L(btn_w_xwide)}] $L(bar_y1) \
            -tags mt_sereset -label [translate "Reset to default"] \
            -command ::dui::pages::MaintenanceTracker_stepedit::reset_click \
            -label_font $L(font_button) -style mt_btn -initial_state hidden
        dui add dbutton $page [expr {$ad_x1 - $L(btn_w_xwide)}] $L(bar_y0) $ad_x1 $L(bar_y1) \
            -tags mt_seadd -label [translate "Add step"] \
            -command ::dui::pages::MaintenanceTracker_stepedit::add_click \
            -label_font $L(font_button) -style mt_btn -initial_state hidden
        dui add dbutton $page $sv_x0 $L(bar_y0) $rx $L(bar_y1) \
            -tags mt_sesave -label [translate "Save"] \
            -command ::dui::pages::MaintenanceTracker_stepedit::save_click \
            -label_font $L(font_button) -style mt_btn_primary -initial_state hidden
    }

    proc _set_list_vis {page on} {
        set n_max $::plugins::MaintenanceTracker::steps_max
        set n [llength $::plugins::MaintenanceTracker::se_draft]
        for {set i 0} {$i < $n_max} {incr i} {
            set row [expr {$on && $i < $n}]
            foreach t [list mt_serow$i mt_seup$i mt_sedn$i mt_serm$i] {
                set show $row
                if {$t eq "mt_seup$i" && $i == 0} { set show 0 }
                if {$t eq "mt_sedn$i" && $i == $n - 1} { set show 0 }
                catch { dui item [expr {$show ? "show" : "hide"}] $page $t* -initial 1 }
            }
            # v0.29.1: badge + divider (plain canvas items: exact tags).
            foreach t [list se_b$i se_b${i}_n] {
                catch { dui item [expr {$row ? "show" : "hide"}] $page $t -initial 1 }
            }
            if {$i < $n_max - 1} {
                catch { dui item [expr {$on && $i + 1 < $n ? "show" : "hide"}] $page se_d$i -initial 1 }
            }
            if {!$row} {
                catch { dui item config $page se_t$i -text "" }
            }
        }
        # v0.29.1: the card -- the backdrop for this count, its header.
        for {set k 0} {$k <= $n_max} {incr k} {
            catch { dui item [expr {$on && $k == $n ? "show" : "hide"}] $page se_card$k -initial 1 }
        }
        foreach t {se_card_title se_count se_card_div} {
            catch { dui item [expr {$on ? "show" : "hide"}] $page $t -initial 1 }
        }
        foreach t {mt_secancel mt_sereset mt_seadd mt_sesave} {
            catch { dui item [expr {$on ? "show" : "hide"}] $page $t* -initial 1 }
        }
    }

    proc _set_form_vis {page on} {
        foreach t {se_fcard se_fcap se_entry se_fhint} {
            catch { dui item [expr {$on ? "show" : "hide"}] $page $t -initial 1 }
        }
        foreach t {mt_sefcancel mt_sefsave} {
            catch { dui item [expr {$on ? "show" : "hide"}] $page $t* -initial 1 }
        }
    }

    proc refresh {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::MaintenanceTracker::L L
        set id $::plugins::MaintenanceTracker::se_item
        set err $::plugins::MaintenanceTracker::se_error
        if {$id eq "" || ![info exists ::plugins::MaintenanceTracker::settings(item_$id)]} {
            catch { dui item config $page se_sub -text [translate "Nothing selected"] -fill $L(text_mut) }
            set ::plugins::MaintenanceTracker::se_draft {}
            _set_form_vis $page 0
            _set_list_vis $page 0
            return
        }
        if {$err ne ""} {
            catch { dui item config $page se_sub -text $err -fill $L(col_red) }
        } else {
            catch { dui item config $page se_sub \
                -text [::plugins::MaintenanceTracker::_item_label $id] -fill $L(text_mut) }
        }
        if {$::plugins::MaintenanceTracker::se_mode eq "form"} {
            _set_list_vis $page 0
            set fi $::plugins::MaintenanceTracker::se_form_idx
            set cap [expr {$fi < 0 ? [translate "New step"] : "[translate {Edit step}] [expr {$fi + 1}]"}]
            catch { dui item config $page se_fcap -text $cap }
            _set_form_vis $page 1
            return
        }
        _set_form_vis $page 0
        set draft $::plugins::MaintenanceTracker::se_draft
        set nd [llength $draft]
        catch { dui item config $page se_count \
            -text [expr {$nd == 1 ? [translate "1 step"] : "$nd [translate {steps}]"}] }
        for {set i 0} {$i < $nd} {incr i} {
            catch { dui item config $page se_b${i}_n -text [expr {$i + 1}] }
            catch { dui item config $page se_t$i \
                -text [::plugins::MaintenanceTracker::_short_text \
                    [::plugins::MaintenanceTracker::_se_display [lindex $draft $i]] 90] }
        }
        _set_list_vis $page 1
        if {[llength $draft] >= $::plugins::MaintenanceTracker::steps_max} {
            catch { dui item hide $page mt_seadd* -initial 1 }
        }
    }

    proc _after {} {
        if {[catch { refresh } err]} {
            catch { msg "MaintenanceTracker: step editor refresh failed: $err" }
        }
    }
    proc _hide_kb {} { catch { dui platform hide_android_keyboard } }

    proc row_click {i}          { ::plugins::MaintenanceTracker::se_edit $i ; _after }
    proc move_click {i delta}   { ::plugins::MaintenanceTracker::se_move $i $delta ; _after }
    proc remove_click {i}       { ::plugins::MaintenanceTracker::se_remove $i ; _after }
    proc add_click {}           { ::plugins::MaintenanceTracker::se_edit -1 ; _after }
    proc reset_click {}         { ::plugins::MaintenanceTracker::se_reset ; _after }
    proc form_save_click {} {
        _hide_kb
        ::plugins::MaintenanceTracker::se_form_save
        _after
    }
    proc form_cancel_click {} {
        _hide_kb
        ::plugins::MaintenanceTracker::se_form_cancel
        _after
    }
    proc cancel_click {} {
        _hide_kb
        set ::plugins::MaintenanceTracker::se_error ""
        ::plugins::MaintenanceTracker::_return_to_page MaintenanceTracker_steps
    }
    proc save_click {} {
        _hide_kb
        if {[::plugins::MaintenanceTracker::se_save]} {
            ::plugins::MaintenanceTracker::_return_to_page MaintenanceTracker_steps
            return
        }
        _after
    }

    proc show {page_to_hide page_to_show} {
        # Stuck-flag rule: a (re)shown editor starts in list mode; the
        # draft itself survives (a flow interruption must not wipe it).
        ::plugins::MaintenanceTracker::se_form_cancel
        if {![::plugins::MaintenanceTracker::_page_is_current MaintenanceTracker_stepedit]} { return }
        _after
    }
}

# ===========================================================================
#  Diagnostics page -- everything the plugin detected, read-only
# ===========================================================================

namespace eval ::dui::pages::MaintenanceTracker_diagnostics {

    variable row_count 16

    proc setup {} {
        set page [namespace tail [namespace current]]
        upvar #0 ::plugins::MaintenanceTracker::L L
        variable row_count
        ::plugins::MaintenanceTracker::_page_bg $page

        set lx $L(left_x)
        set rx $L(right_x)
        set cx [expr {($lx + $rx) / 2}]

        dui add dtext $page $cx $L(header_title_y) -tags page_title \
            -text [translate "Maintenance Tracker -- Diagnostics"] \
            -font $L(font_title) -width $L(content_w) -fill $L(text_hi) \
            -anchor center -justify center
        dui add dtext $page $cx $L(header_subtitle_y) -tags subtitle \
            -text [translate "Detected database, table, columns and filters. Everything on this page is read-only."] \
            -font $L(font_caption) -width $L(content_w) -fill $L(text_mut) \
            -anchor center -justify center

        # Label/value rows: labels at left_x, values at value_x, never
        # touching (gap enforced by the value_x token).
        set value_w [expr {$L(right_x) - $L(value_x)}]
        for {set i 0} {$i < $row_count} {incr i} {
            set y [expr {$L(list_top) + $i * $L(diag_row_h)}]
            dui add dtext $page $lx $y -tags row${i}_label -text "" \
                -font $L(font_body) -width $L(label_col_w) -fill $L(text_hi) \
                -anchor nw -justify left
            dui add dtext $page $L(value_x) $y -tags row${i}_value -text "" \
                -font $L(font_body) -width $value_w -fill $L(text_body) \
                -anchor nw -justify left
        }

        # Bottom bar: Back, left slot.
        dui add dbutton $page $lx $L(bar_y0) [expr {$lx + $L(btn_w_std)}] $L(bar_y1) \
            -tags mt_back -label [translate "Back"] \
            -command ::plugins::MaintenanceTracker::diagnostics_back \
            -label_font $L(font_button) -style mt_btn
    }

    proc _set_row {page i label value} {
        dui item config $page row${i}_label -text $label
        dui item config $page row${i}_value -text $value
    }

    proc refresh {} {
        set page [namespace tail [namespace current]]
        variable row_count
        # Same fresh-on-show rule as the settings page.
        set ::plugins::MaintenanceTracker::status_dirty 1
        set s [::plugins::MaintenanceTracker::status_summary]
        upvar #0 ::plugins::MaintenanceTracker::diag diag

        set fields {}
        catch { set fields $diag(fields) }
        set col_clock "";  catch { set col_clock [dict get $fields clock] }
        set col_bev "not present"
        catch { if {[dict exists $fields bev_type]} { set col_bev [dict get $fields bev_type] } }
        set col_profile "not present"
        catch { if {[dict exists $fields profile]} { set col_profile [dict get $fields profile] } }

        set open_txt "FAILED"
        catch { if {$diag(sdb_ok)} { set open_txt "OK (read-only)" } else { set open_txt "FAILED: $diag(sdb_error)" } }
        set filter_txt [translate "active"]
        catch {
            if {!$diag(filter_ok)} {
                set filter_txt "[translate {unavailable, counting unfiltered:}] $diag(filter_error)"
            }
        }
        set refreshed ""
        catch { set refreshed [clock format $diag(refreshed) -format "%Y-%m-%d %H:%M:%S"] }

        set overall "unavailable"
        catch { if {[dict get $s ok]} { set overall [dict get $s state] } }

        # Blank facts render as "n/a", never as an empty cell.
        set na [translate "n/a"]
        foreach v {col_clock refreshed} { if {[set $v] eq ""} { set $v $na } }
        set v_table $diag(table);          if {$v_table eq ""} { set v_table $na }
        set v_raw $diag(total_raw);        if {$v_raw eq ""} { set v_raw $na }
        if {$diag(total_counted) eq ""} {
            set v_counted $na
        } elseif {$diag(total_excluded) eq ""} {
            set v_counted "$diag(total_counted) / $na"
        } else {
            set v_counted "$diag(total_counted) / $diag(total_excluded)"
        }

        set i 0
        _set_row $page $i [translate "Plugin version"] $::plugins::MaintenanceTracker::version; incr i
        _set_row $page $i [translate "Database file"] $diag(sdb_path); incr i
        _set_row $page $i [translate "Database open"] $open_txt; incr i
        _set_row $page $i [translate "Detected shot table"] $v_table; incr i
        _set_row $page $i [translate "Clock column"] $col_clock; incr i
        _set_row $page $i [translate "Beverage-type column"] $col_bev; incr i
        _set_row $page $i [translate "Profile-title column"] $col_profile; incr i
        # v0.13.0: one merged row -- the page holds exactly 16 rows above
        # the bottom bar and the water meter needed the freed slot.
        _set_row $page $i [translate "Rows raw / counted / excluded"] "$v_raw / $v_counted"; incr i
        _set_row $page $i [translate "Cleaning filter"] $filter_txt; incr i
        _set_row $page $i [translate "Excluded beverage types"] [join $::plugins::MaintenanceTracker::exclude_bev_types ", "]; incr i
        _set_row $page $i [translate "Excluded title keywords"] [join $::plugins::MaintenanceTracker::exclude_title_kw ", "]; incr i
        set auto_txt [translate "off"]
        catch {
            if {$::plugins::MaintenanceTracker::settings(auto_record)} {
                # v0.20.0: per-source attached-tracker counts, so the
                # auto_src wiring is inspectable at a glance.
                set n_clean 0
                set n_descale 0
                foreach aid [::plugins::MaintenanceTracker::_all_item_ids] {
                    switch -- [::plugins::MaintenanceTracker::_item_auto_src $aid] {
                        clean   { incr n_clean }
                        descale { incr n_descale }
                    }
                }
                set auto_txt "[translate {on}] ([translate {clean}] >= $::plugins::MaintenanceTracker::settings(auto_clean_min_s)s -> $n_clean, [translate {descale}] >= $::plugins::MaintenanceTracker::settings(auto_descale_min_s)s -> $n_descale)"
            }
        }
        _set_row $page $i [translate "Auto-record cycles"] $auto_txt; incr i
        set custom_n 0
        catch { set custom_n [llength $::plugins::MaintenanceTracker::settings(custom_ids)] }
        _set_row $page $i [translate "Custom trackers"] $custom_n; incr i
        set hidden_txt [translate "none"]
        catch {
            set hl $::plugins::MaintenanceTracker::settings(hidden_ids)
            if {[llength $hl] > 0} {
                set hn {}
                foreach h $hl { lappend hn [::plugins::MaintenanceTracker::_item_label $h] }
                set hidden_txt [join $hn ", "]
            }
        }
        _set_row $page $i [translate "Hidden trackers"] $hidden_txt; incr i
        set water_txt $na
        catch {
            set w $::plugins::MaintenanceTracker::settings(water_total_ml)
            if {[string is double -strict $w]} {
                set water_txt "[::plugins::MaintenanceTracker::_fmt_ml $w] ([translate {while the app was running}])"
            }
        }
        _set_row $page $i [translate "Water dispensed (lifetime)"] $water_txt; incr i
        _set_row $page $i [translate "Overall state / refreshed"] "$overall / $refreshed"; incr i
        while {$i < $row_count} { _set_row $page $i "" ""; incr i }
    }

    proc show {page_to_hide page_to_show} {
        if {[catch { refresh } err]} {
            catch { msg "MaintenanceTracker: diagnostics refresh failed: $err" }
        }
    }
}
