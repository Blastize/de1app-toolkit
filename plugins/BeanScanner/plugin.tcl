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
# Bean Scanner  --  DE1app plugin manifest
#
# Photograph a bag of coffee with the tablet camera, send the picture to a
# vision AI model (Anthropic Claude or OpenAI GPT, switchable), and put the
# recognized roaster / bean / roast date / roast level / notes into DYE's
# "next shot" description after you confirm them on screen.
#
# Requires the DYE (Describe Your Espresso) plugin to be enabled: DYE owns
# the next-shot definition and its persistence into shot history. This plugin
# never writes SDB, never touches history/ or history_v2/, and never writes
# ::settings directly -- the only write it performs is the DYE next-shot
# update, and only after you press Accept on the review page.
#
# An API key is required (a ChatGPT or Claude subscription is NOT API access;
# create a key with pay-as-you-go credit at platform.openai.com or
# console.anthropic.com). The key can be typed in the settings page or placed
# in a file next to this manifest (api_key_anthropic.txt / api_key_openai.txt).
#
# Install path:  de1plus/plugins/BeanScanner/
#

package require Tcl 8.5

set plugin_name "BeanScanner"

namespace eval ::plugins::BeanScanner {
    variable author      "Blastize"
    variable contact     "https://github.com/Blastize/de1app-plugin-BeanScanner"
    variable version     "0.9.13"
    variable name        "Bean Scanner"
    variable description "Photograph a bean bag, an AI vision model reads it, and the details go into DYE's next shot after you confirm. Requires DYE and an API key."

    # ---- Defaults ----
    # Set each key only if missing: the plugin framework may already have
    # created this array (possibly empty) before this file is sourced.
    variable settings
    foreach {__k __v} {
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
        flash_mode          off
        max_photos          6
        screen_flash_ms     600

        apply_bean_brand    1
        apply_bean_type     1
        apply_roast_date    1
        apply_roast_level   1
        apply_bean_notes    1
        overwrite_existing  1
        theme               {}
    } {
        if {![info exists settings($__k)]} { set settings($__k) $__v }
    }
    unset -nocomplain __k __v

    # ---- Runtime state (never persisted) ----
    variable L                       ;# layout tokens
    array set L {}

    variable cam                     ;# camera state
    array set cam {
        open 0  started 0  preview 0  after {}  photo {}  index -1
        probe {}  last_bytes 0
        flash_hw {}  flash_modes {}  screenflash 0  saved_brightness {}
        flash_after {}  zoom {1 1}  photo_disp {}
    }

    # Captured-but-not-yet-sent JPEGs for the current scan (binary data,
    # runtime only, never persisted). One bag can need several photos:
    # front, back, side panels with the roast date, etc.
    variable photos [list]

    variable scan                    ;# current scan state
    array set scan {
        busy 0  stage idle  status {}  token {}
        roaster {}  bean {}  roast_date {}  roast_level {}
        origin {}  process {}  varietal {}  notes {}
        have_result 0
    }

    variable last_error   ""
    variable last_raw     ""
    variable last_http    ""
    variable _settings_return_page ""
    variable dye_ready    0

    # Directory this manifest lives in (used to load the implementation).
    variable plugin_dir [file dirname [info script]]
}

# Load the implementation that sits next to this manifest.
if {[file exists [file join $::plugins::BeanScanner::plugin_dir BeanScanner.tcl]]} {
    source [file join $::plugins::BeanScanner::plugin_dir BeanScanner.tcl]
}

# Called by the plugin framework. Returns the name of the settings page.
proc ::plugins::BeanScanner::preload {} {
    return [preload_settings_page]
}

# Called by the framework when the plugin is enabled / on startup.
proc ::plugins::BeanScanner::main {} {
    catch { plugins load_settings BeanScanner }
    apply_defaults
    catch { msg "BeanScanner: started (provider [_setting provider anthropic])" }
    return
}

proc ::plugins::BeanScanner::save_settings {} {
    catch { plugins save_settings BeanScanner }
}
