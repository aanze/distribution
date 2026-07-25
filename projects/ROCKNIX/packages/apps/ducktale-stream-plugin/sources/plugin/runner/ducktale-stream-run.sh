#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 ROCKNIX (https://github.com/ROCKNIX)
#
# DUCKTALE-STREAM runner. Steam starts this through a non-Steam shortcut, and
# that indirection is the whole point: gamescope runs in Steam-integrated mode
# and gives focus ONLY to what Steam declares as the running game. Launching
# moonlight from the plugin backend instead streams perfectly but stays behind
# the Steam UI - verified on the Odin 3 on 2026-07-25, in X11 AND as a native
# Wayland client on gamescope-0.
#
# Parameters come from LAUNCH_FILE, never from the environment: this Steam build
# silently drops the "VAR=value %command%" env prefix of a shortcut's launch
# options (that is what kills MoonDeck's runner before it does anything).

LAUNCH_FILE="/storage/.config/ducktale-stream/launch.json"
LOG="/tmp/ducktale-stream.log"
CONTROLLER_DB="/storage/.config/moonlight/gamecontrollerdb.txt"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >>"${LOG}"; }

# Minimal JSON field reader: the values we write are plain strings/ints without
# escapes, and this runs under whatever python the system has (or none at all).
field() {
  sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${LAUNCH_FILE}" | head -1
}

[ -f "${LAUNCH_FILE}" ] || { log "no ${LAUNCH_FILE} - nothing staged"; exit 1; }

HOST="$(field host)"
APP="$(field app)"
GAME="$(field game_name)"

if [ -z "${HOST}" ] || [ -z "${APP}" ]; then
  log "incomplete launch file (host='${HOST}' app='${APP}')"
  exit 1
fi

log "streaming '${GAME}' via Sunshine app '${APP}' on ${HOST}"

# Same gamepad mapping step ROCKNIX's own generated Moonlight launchers do.
[ -x /usr/bin/controller-layout ] && \
  /usr/bin/controller-layout moonlight "ducktale-stream" "${CONTROLLER_DB}" >>"${LOG}" 2>&1

# Moonlight Embedded's real syntax. Any extra options the user wants live in
# /storage/.config/moonlight/moonlight.conf, which moonlight reads by itself.
exec /usr/bin/moonlight stream -app "${APP}" -platform sdl "${HOST}" >>"${LOG}" 2>&1
