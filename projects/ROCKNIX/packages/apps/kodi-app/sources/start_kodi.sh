#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Launch Kodi (21 "Omega", with the PM4K Plex client preinstalled) under sway.
#
# Kodi is not a mediacenter session here: it runs as a fullscreen wayland
# client inside the ES session. Playback Direct Plays through the system
# ffmpeg - HEVC 8/10-bit included - so a Plex server never has to transcode.
#
# Must be started FROM EmulationStation (the "Kodi" main-menu section).
# Launching it any other way lets ES think it is idle at the menu, which
# triggers the OLED screensaver over the top and tiles the window half-screen.
#
# Plex: open PM4K from the Add-ons row; it shows a plex.tv/link code - enter
# it on your phone or PC. No on-screen keyboard needed (Kodi has its own OSK).
#
# Exit: quit from Kodi's power menu, hold gamepad Back 2s, or the global
# combo L1 + START + SELECT. Poweroff/reboot/suspend from inside Kodi are
# blocked by the inhibitor below.

source /etc/profile

KODI_BIN="/usr/lib/kodi/kodi.bin"
LOG="/storage/.config/kodi-app/kodi-launch.log"
mkdir -p "$(dirname "${LOG}")"

if [ ! -x "${KODI_BIN}" ]; then
  echo "kodi is not installed (${KODI_BIN} missing)." | tee "${LOG}"
  sleep 10
  exit 1
fi

# Global exit combo (L1+START+SELECT): input_sense runs `killall` on these
# names. NOTE: busybox killall matches the FULL exe name, not the truncated
# 15-char /proc/comm.
set_kill set "kodi.bin"

# First-run seeding: PM4K kiosk autostart, gamepad quit keymap, guisettings.
/usr/bin/kodi-setup ensure

# Kodi env: HOME=/storage, KODI_HOME, KODI_TEMP, audio backend, WAYLAND_DISPLAY.
set -a
. /usr/lib/kodi/kodi.conf
set +a

# LE's userdata provisioning (sources.xml seed, addon bin exec bits).
/usr/lib/kodi/kodi-config

# Keep Kodi fullscreen whatever windows it spawns, so it never ends up tiled
# to half the screen next to ES.
swaymsg 'for_window [app_id="kodi"] fullscreen enable' >/dev/null 2>&1 || true

cleanup() {
  set_kill stop
}
trap cleanup EXIT

# plex.tv sign-in/token refresh is HTTPS, so the clock must be correct or the
# TLS cert looks invalid. Right after a cold boot NTP may not have synced yet.
if command -v timedatectl >/dev/null 2>&1; then
  for _ in $(seq 1 10); do
    [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = "yes" ] && break
    systemctl start systemd-timesyncd >/dev/null 2>&1 || true
    sleep 1
  done
fi

# Inhibit suspend/idle for the whole session: video playback has long
# stretches with no local input, and an auto-suspend re-enumerates the
# gamepad and wedges input on resume. "shutdown" also blocks Kodi's own
# power menu from powering off/rebooting the console (logind refuses the
# request while the inhibitor is held) - quitting Kodi is the only exit.
exec systemd-inhibit \
  --what=shutdown:sleep:idle:handle-suspend-key:handle-lid-switch \
  --who="kodi-app" --why="Kodi/Plex playback" \
  "${KODI_BIN}" --standalone ${KODI_AUDIO_ARGS} \
  2>&1 | tee "${LOG}"
