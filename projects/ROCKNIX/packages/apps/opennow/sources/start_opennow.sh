#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Launch the OpenNOW (GeForce NOW) AppImage.
#
# The first-time NVIDIA login uses xdg-open, which is provided system-wide
# (xdg-utils -> cog/WPEWebKit). OpenNOW listens for the OAuth redirect on
# localhost, so the login completes entirely on the device: no SSH, no second
# computer, and no app-specific browser hack.

source /etc/profile
# Process names as seen in /proc/PID/comm (what input_sense's `killall` matches):
# the Electron app is "opennow-stable", wrapped by the AppImage runtime
# "OpenNOW.AppImag" (comm is truncated to 15 chars). The exit combo
# (L1+START+SELECT) kills both. rocknix-browser appends "firefox" while the
# login browser is open and restores this on exit.
set_kill set "opennow-stable OpenNOW.AppImag"

OPENNOW_DIR="/storage/roms/opennow"
APPIMAGE="${OPENNOW_DIR}/OpenNOW.AppImage"
LOG="${OPENNOW_DIR}/opennow.log"

if [ ! -x "${APPIMAGE}" ]; then
  echo "OpenNOW is not installed." | tee "${LOG}"
  echo "Run 'Install OpenNOW' from the Tools menu first." | tee -a "${LOG}"
  sleep 10
  exit 1
fi

cd "${OPENNOW_DIR}" || exit 1

# The NVIDIA OAuth login opens https in the on-device browser, so the system
# clock must be correct or the TLS cert looks invalid ("your computer clock is
# wrong"). Right after a cold boot NTP may not have synced yet; wait briefly.
if command -v timedatectl >/dev/null 2>&1; then
  for _ in $(seq 1 10); do
    [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = "yes" ] && break
    systemctl start systemd-timesyncd >/dev/null 2>&1 || true
    sleep 1
  done
fi

# The on-screen keyboard is summoned only while the login browser is open
# (handled by rocknix-browser), not for the whole stream session.
./OpenNOW.AppImage --no-sandbox 2>&1 | tee "${LOG}"
