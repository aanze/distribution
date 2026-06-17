#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2024 ROCKNIX (https://github.com/ROCKNIX)

### setup is the same
. $(dirname $0)/es_settings

# Boot directly into the Steam (gamescope / "SteamOS") session when the user
# enabled it under Main Menu > System Settings, instead of EmulationStation.
#
# A one-shot latch in tmpfs makes this fire ONLY on the boot session: Steam runs
# in its own systemd scope and, on exit ("return to desktop"), restarts essway,
# which re-runs this script. By then the latch is set, so the second pass falls
# through to EmulationStation = the desktop — no reload loop. And because ES is
# never started on the boot pass, there is no EmulationStation flash before
# gamescope (we launch Steam and wait; we do not fall through to ES here).
if [ "$(get_setting system.boottosteam)" = "1" ] && \
   [ ! -f /tmp/.steamos-booted ] && \
   [ -e /storage/.local/share/applications/Steam.desktop ] && \
   [ -x /usr/bin/runemu.sh ]; then
  touch /tmp/.steamos-booted
  /usr/bin/runemu.sh /storage/.local/share/applications/Steam.desktop \
    -Psteam --core=steam --emulator=steam --controllers="" &
  wait
  exit 0
fi

emulationstation --log-path /var/log --no-splash
