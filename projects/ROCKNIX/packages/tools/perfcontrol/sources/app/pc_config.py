# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 ROCKNIX (https://github.com/ROCKNIX)
#
# Perf Control - shared paths, constants and the profile schema version.
# Pure stdlib so it is importable by BOTH the headless CLI (system python3)
# and the Pyxel GUI (the gamepadcalibration venv).

import os

# --- schema -----------------------------------------------------------------
# Bump only on an INCOMPATIBLE change to OUR own store. Used as a guard so a
# newer build's store is not silently mis-read by an older one (and vice versa).
SCHEMA = 1

# --- our own (canonical, always-writable) store -----------------------------
OUR_DIR = "/storage/.config/perfcontrol"
OUR_STORE = os.path.join(OUR_DIR, "profiles.json")
LOG_FILE = os.path.join(OUR_DIR, "perfcontrol.log")

# --- the Steam/Decky plugin's shared library (thefiqs/rocknix-control) -------
# On ROCKNIX, Decky installs under /storage/homebrew and per-plugin settings
# live in /storage/homebrew/settings/<plugin>/. This is the file we two-way
# sync with so a profile shows up in both the ES tool and the Steam plugin.
PLUGIN_DIR = "/storage/homebrew/settings/rocknix-control"
PLUGIN_STORE = os.path.join(PLUGIN_DIR, "presets.json")

# --- ROCKNIX system fan service ---------------------------------------------
# The fancontrol daemon honours this file only while cooling.profile == custom.
FANCONTROL_CONF = "/storage/.config/fancontrol.conf"
COOLING_PROFILE_KEY = "cooling.profile"
GPU_OC_KEY = "enable.gpu-overclock"

# --- sysfs roots ------------------------------------------------------------
CPUFREQ_ROOT = "/sys/devices/system/cpu/cpufreq"
DEVFREQ_ROOT = "/sys/class/devfreq"
HWMON_ROOT = "/sys/class/hwmon"
THERMAL_ROOT = "/sys/devices/virtual/thermal"
# Fallback GPU devfreq node for SM8750 if the /sys/class/devfreq glob fails.
GPU_DEVFREQ_FALLBACK = "/sys/devices/platform/soc@0/3d00000.gpu/devfreq/3d00000.gpu"

# --- fan curve defaults (millidegrees C -> pwm 0..255), ascending -----------
# Mirrors the Decky plugin's default curve so a fresh install matches it.
DEFAULT_FAN_CURVE = {"temps": [40000, 60000, 80000], "speeds": [51, 51, 153]}
PWM_MAX = 255

# --- sync status values -----------------------------------------------------
SYNC_SYNCED = "synced"            # plugin file present, parseable, compatible
SYNC_ABSENT = "absent"            # plugin / Decky not installed (normal)
SYNC_DESYNCED = "desynced"        # plugin file present but incompatible


def log(msg):
    """Best-effort append to our log; never raise."""
    try:
        os.makedirs(OUR_DIR, exist_ok=True)
        with open(LOG_FILE, "a") as fh:
            fh.write(msg.rstrip("\n") + "\n")
    except Exception:
        pass
