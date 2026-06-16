#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Tools-menu launcher for the Steamlike Theme Manager (Pyxel GUI). Reuses the
# Pyxel venv shipped by gamepadcalibration (same as Perf Control). On exit it
# restarts EmulationStation IF the GUI changed something, so theme tweaks apply.

source /etc/profile

APP="/usr/share/themecfg/app/themecfg_ui.py"
[ -f "${APP}" ] || APP="/storage/.config/themecfg/app/themecfg_ui.py"
GPVENV="/usr/local/share/gpcal/pyxel"

if [ ! -d "${GPVENV}" ]; then
  mako-notify "Theme Manager: Pyxel runtime missing (gamepadcalibration)" 2>/dev/null
  exit 1
fi

set_kill set "python3"
sway_fullscreen "python3" &

cd "$(dirname "${GPVENV}")"
source pyxel/bin/activate
PYTHONDONTWRITEBYTECODE=1 python3 "${APP}"

# Apply theme/art changes by reloading ES (the sway session respawns it).
if [ -f /storage/.config/themecfg/.reload ]; then
  rm -f /storage/.config/themecfg/.reload
  killall emulationstation 2>/dev/null
fi
