#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# DUCKTALE-SAVESYNC GUI (Tools menu). Same recipe as perfcontrol-gui: reuses
# the Pyxel venv shipped by the gamepadcalibration package. The app code lives
# with the Decky plugin under /storage, so it updates with the plugin deploy
# and needs no image rebuild.

. /etc/profile

APP="/storage/homebrew/plugins/ducktale-savesync/savesync_gui.py"
GPVENV="/usr/local/share/gpcal/pyxel"

if [ ! -f "${APP}" ]; then
  mako-notify "SaveSync: plugin not installed (deploy ducktale-savesync first)" 2>/dev/null
  exit 1
fi
if [ ! -d "${GPVENV}" ]; then
  mako-notify "SaveSync: Pyxel runtime missing (gamepadcalibration)" 2>/dev/null
  exit 1
fi

# Make the app killable by the global panic combo and force it full screen.
set_kill set "python3"
sway_fullscreen "python3" &

# The venv's activate script resolves relative to its parent dir (mirrors GPcal).
cd "$(dirname "${GPVENV}")" || exit 1
. pyxel/bin/activate

PYTHONDONTWRITEBYTECODE=1 python3 "${APP}"
