#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Launch the GeForce NOW client (gfn-electron, arm64) under sway.
#
# This is a native-arm64 Electron wrapper of the GeForce NOW web app, so its
# Chromium uses the device's VAAPI/V4L2 (qcom-iris) decode path - no box64, no
# Vulkan-Video (which the Adreno/Turnip driver lacks).
#
# Must be started FROM EmulationStation (it appears in the "GeForce NOW" main-menu
# section). Launching it any other way lets ES think it is idle at the menu, which
# triggers the OLED screensaver over the top and tiles the window half-screen.
#
# First login: use your NVIDIA account (e-mail + password) or Discord. Google
# "Sign in with Google" is blocked inside any Electron/webview ("this browser or
# app may not be secure"), regardless of user-agent spoofing. The on-screen
# keyboard is hidden by default - summon/hide it with: hold left-Home + tap screen.
#
# Exit any time with the global combo L1 + START + SELECT.

source /etc/profile

APP_DIR="/usr/share/gfn-electron"
APPBIN="${APP_DIR}/geforcenow-electron"
LOG="/storage/.config/gfn-electron/gfn-electron.log"
mkdir -p "$(dirname "${LOG}")"

if [ ! -x "${APPBIN}" ]; then
  echo "gfn-electron is not installed (${APPBIN} missing)." | tee "${LOG}"
  sleep 10
  exit 1
fi

# Global exit combo (L1+START+SELECT): input_sense runs `killall` on these names.
# NOTE: busybox killall matches the FULL exe name, not the 15-char /proc/comm,
# so this must be "geforcenow-electron", not the truncated "geforcenow-elec".
set_kill set "geforcenow-electron wvkbd-mobintl"

# --- On-screen keyboard (hidden; summon with left-Home + tap) -----------------
# Use wvkbd directly with the clean rocknix-browser styling. The system
# touchkeyboard daemon's bigger font spills the cells, so stop it while we run.
TOUCHKB_WAS_ACTIVE=0
if systemctl is-active --quiet touchkeyboard.service; then
  TOUCHKB_WAS_ACTIVE=1
  systemctl stop touchkeyboard.service >/dev/null 2>&1 || true
fi
killall wvkbd-mobintl >/dev/null 2>&1 || true
sleep 0.3
KB_OUT="$(swaymsg -t get_outputs -r 2>/dev/null | jq -r '.[] | select(.focused==true) | .name' | head -n1)"
KB_ARGS=(--hidden -L 380 -fn "Sans 22" -l simple)
[ -n "${KB_OUT}" ] && KB_ARGS+=(--output "${KB_OUT}")
/usr/bin/wvkbd-mobintl "${KB_ARGS[@]}" >/dev/null 2>&1 &
WVKBD_PID=$!

# Keep GFN fullscreen even when it spawns extra windows (OAuth popups), so it
# never ends up tiled to half the screen next to ES.
swaymsg 'for_window [app_id="GeForce NOW"] fullscreen enable' >/dev/null 2>&1 || true

cleanup() {
  kill "${WVKBD_PID}" 2>/dev/null || true
  [ "${TOUCHKB_WAS_ACTIVE}" = "1" ] && systemctl start touchkeyboard.service >/dev/null 2>&1 || true
  set_kill stop
}
trap cleanup EXIT

# The NVIDIA OAuth/login opens https, so the clock must be correct or the TLS
# cert looks invalid. Right after a cold boot NTP may not have synced yet.
if command -v timedatectl >/dev/null 2>&1; then
  for _ in $(seq 1 10); do
    [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = "yes" ] && break
    systemctl start systemd-timesyncd >/dev/null 2>&1 || true
    sleep 1
  done
fi

# Inhibit suspend/idle for the whole streaming session: a stream has long stretches
# with no local input, and an auto-suspend re-enumerates the gamepad and wedges
# input on resume. exec so the inhibitor lives exactly as long as the app.
exec systemd-inhibit \
  --what=sleep:idle:handle-suspend-key:handle-lid-switch \
  --who="gfn-electron" --why="GeForce NOW streaming" \
  "${APPBIN}" --no-sandbox \
    --ozone-platform=wayland \
    --enable-features=UseOzonePlatform,VaapiVideoDecoder \
    --enable-wayland-ime \
  2>&1 | tee "${LOG}"
