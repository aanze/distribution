#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Launcher for the Citron (Nintendo Switch) emulator.
#
#   start_citron.sh "<rom>"   -> boots the given game fullscreen (called by runemu)
#   start_citron.sh           -> opens the Citron GUI (called by the "Start Citron"
#                                tool) so the user can install firmware, manage
#                                keys and tweak settings. A mouse + keyboard is
#                                recommended for the GUI.
#
# Citron is NOT bundled in the system image. The AppImage is downloaded on
# demand by the "Install Citron" tool and lives in the writable storage tree:
#   /storage/.local/share/citron-sa/current.AppImage   (managed install)
#   /storage/.local/share/citron-sa/previous.AppImage  (auto-rollback copy)
# This launcher resolves the binary in that order. There is deliberately no
# factory fallback (nothing is shipped in the squashfs), so if neither exists
# we tell the user to run Tools -> Install Citron and exit cleanly.

. /etc/profile

ROM="$1"

CITRON_BASE="/storage/.local/share/citron-sa"
CITRON_BIN=""
for candidate in \
  "${CITRON_BASE}/current.AppImage" \
  "${CITRON_BASE}/previous.AppImage"; do
  if [ -x "${candidate}" ]; then
    CITRON_BIN="${candidate}"
    break
  fi
done

if [ -z "${CITRON_BIN}" ]; then
  echo "==================================================================="
  echo " Citron is not installed yet."
  echo ""
  echo " Open EmulationStation -> Tools -> 'Install Citron' first, then"
  echo " launch your Switch games from the Nintendo Switch section."
  echo "==================================================================="
  sleep 8
  exit 1
fi

# Citron (a yuzu fork) stores its data under $HOME/.local/share/citron. On
# ROCKNIX $HOME is /storage. We back its keys / firmware (NAND) / SD card folders
# with discoverable locations under /storage/roms/bios via symlinks.
#
# prod.keys / title.keys go in /storage/roms/bios/keys (device-verified working
# location, 2026-06-02); NAND (firmware) and SD card live under
# /storage/roms/bios/citron/{nand,sdmc}.
CITRON_DATA="/storage/.local/share/citron"
CITRON_BIOS="/storage/roms/bios/citron"
CITRON_KEYS="/storage/roms/bios/keys"

mkdir -p "${CITRON_DATA}" "${CITRON_KEYS}" "${CITRON_BIOS}/nand" "${CITRON_BIOS}/sdmc"

link_into_bios() {
  # $1 = citron data subdir to expose; $2 = the bios dir to back it with.
  # Migrates any pre-existing real dir once, then ensures the symlink points at
  # $2 even if an earlier launch linked it somewhere else.
  local data_dir="$1"
  local bios_dir="$2"
  mkdir -p "${bios_dir}"
  if [ -d "${data_dir}" ] && [ ! -L "${data_dir}" ]; then
    cp -rf "${data_dir}/." "${bios_dir}/" 2>/dev/null
    rm -rf "${data_dir}"
  fi
  if [ "$(readlink -f "${data_dir}" 2>/dev/null)" != "$(readlink -f "${bios_dir}" 2>/dev/null)" ]; then
    rm -rf "${data_dir}"
    ln -sf "${bios_dir}" "${data_dir}"
  fi
}
link_into_bios "${CITRON_DATA}/keys" "${CITRON_KEYS}"
link_into_bios "${CITRON_DATA}/nand" "${CITRON_BIOS}/nand"
link_into_bios "${CITRON_DATA}/sdmc" "${CITRON_BIOS}/sdmc"

# Run as an XWayland client (Qt6); matches how the other heavy standalone
# emulators behave on these devices.
export QT_QPA_PLATFORM=xcb

# Register the binary with the global kill combo (L1+Start+Select) and ask the
# compositor to fullscreen the Citron window once it appears.
set_kill set "-9 citron"
sway_fullscreen "citron" "class" &

if [ -n "${ROM}" ]; then
  # Game mode: -f = start fullscreen, -g = boot straight into the given game.
  "${CITRON_BIN}" -f -g "${ROM}"
else
  # GUI mode: no game -> open the Citron interface for firmware/keys/setup.
  "${CITRON_BIN}"
fi
