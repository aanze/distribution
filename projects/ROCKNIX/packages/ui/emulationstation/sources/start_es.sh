#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024 ROCKNIX (https://github.com/ROCKNIX)

### setup is the same
. $(dirname $0)/es_settings

# Boot directly into the Steam (gamescope / "SteamOS") session when the user
# enabled it under Main Menu > System Settings, instead of EmulationStation.
#
# We mark the FIRST EmulationStation start of each boot in /run (tmpfs, wiped on
# every reboot) BEFORE deciding anything. This script runs again on every essway
# (re)start — Steam "return to desktop", quitting a game, or any Tools app that
# relaunches EmulationStation (e.g. the Theme Manager). On all of those the mark
# already exists, so we fall straight through to EmulationStation: Steam is
# entered ONLY on the genuine boot pass, never on a mid-session restart, and
# enabling the toggle takes effect on the next boot (not on the next ES restart).
# On the boot pass we launch Steam and wait (ES is never started -> no flash).
BOOT_MARK=/run/.es-boot-started
if [ ! -e "${BOOT_MARK}" ]; then
  : > "${BOOT_MARK}"
  if [ "$(get_setting system.boottosteam)" = "1" ] && \
     [ -e /storage/.local/share/applications/Steam.desktop ] && \
     [ -x /usr/bin/runemu.sh ]; then
    /usr/bin/runemu.sh /storage/.local/share/applications/Steam.desktop \
      -Psteam --core=steam --emulator=steam --controllers="" &
    wait
    exit 0
  fi
fi

emulationstation --log-path /var/log --no-splash
