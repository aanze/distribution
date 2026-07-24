#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Launch the OpenNOW (GeForce NOW) AppImage.
#
# OpenNOW is an ALTERNATIVE cloud-gaming client offered inside the "GeForce NOW"
# main-menu section (gfn-electron stays the default). Its launcher lives in the
# geforcenow ROM folder; the AppImage itself is downloaded on demand by the
# "Install OpenNOW" tool into /storage/.local/share/opennow/.
#
# Login note: the current OpenNOW builds are expected to log in inside their own
# Electron window (like gfn-electron), so this launcher does NOT pull in an
# external browser. If a future OpenNOW delegates the NVIDIA OAuth to xdg-open,
# re-add a dependency on rocknix-browser (the on-device Firefox shim) here.
#
# This launcher also runs opennow-touchmouse-daemon for the whole session, so
# the touchscreen acts as a mouse (tap = left click, drag = pointer move) -
# useful when GeForce NOW boots a game into the desktop Steam UI instead of Big
# Picture, a screen the controller cannot navigate. The daemon is killed on exit.
#
# Exit any time with the global combo L1 + START + SELECT.

source /etc/profile

OPENNOW_DIR="/storage/.local/share/opennow"
APPIMAGE="${OPENNOW_DIR}/OpenNOW.AppImage"
LOG="/storage/.config/opennow/opennow.log"
mkdir -p "$(dirname "${LOG}")"

if [ ! -x "${APPIMAGE}" ]; then
  echo "OpenNOW is not installed (${APPIMAGE} missing)." | tee "${LOG}"
  echo "Run 'Install OpenNOW' from the Tools menu first." | tee -a "${LOG}"
  sleep 10
  exit 1
fi

# Global exit combo (L1+START+SELECT): input_sense runs `killall` on these names.
# NOTE: busybox killall matches the FULL exe name, not the 15-char /proc/comm.
# The Electron app has historically been "opennow-stable"; the AppImage runtime
# comm is truncated to 15 chars -> "OpenNOW.AppImag". VERIFY on device (v0.5.2)
# with `cat /proc/<pid>/comm` and adjust if the app renamed its binary.
set_kill set "opennow-stable OpenNOW.AppImag"

# Touchscreen-as-mouse companion for the whole session.
/usr/bin/opennow-touchmouse-daemon >/dev/null 2>&1 &
DAEMON_PID=$!

cleanup() {
  kill "${DAEMON_PID}" 2>/dev/null || true
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

cd "${OPENNOW_DIR}" || exit 1
./OpenNOW.AppImage --no-sandbox 2>&1 | tee "${LOG}"
