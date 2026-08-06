#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Mirror the PS3 section (*.ps3 folders) and the GeForce NOW / OpenNOW
# launchers into Steam non-Steam shortcuts, with the EmulationStation-scraped
# cover/hero/logo installed as Steam grid art. Rerunnable after adding or
# removing games (scrape them in ES first so the art follows). Steam must NOT
# be running: it rewrites shortcuts.vdf from memory when it exits.
#
# The live wrappers stay under /storage/.config/steam-shortcuts because the
# shortcuts.vdf Exe paths (and therefore the appids Steam keys its per-app
# settings on) are baked to those paths; this refresh keeps them current with
# the image's payload without ever changing the appids.

. /etc/profile

PAYLOAD=/usr/share/steam-shortcuts
LIVE=/storage/.config/steam-shortcuts

mkdir -p "${LIVE}"
for f in app-launch.sh ps3-launch.sh steam-shortcuts-sync.py; do
  cp -f "${PAYLOAD}/${f}" "${LIVE}/${f}"
done
chmod 0755 "${LIVE}"/app-launch.sh "${LIVE}"/ps3-launch.sh "${LIVE}"/steam-shortcuts-sync.py

OUT="$(python3 "${LIVE}/steam-shortcuts-sync.py" 2>&1)"
RC=$?
echo "${OUT}"
if [ ${RC} -eq 0 ]; then
  N="$(echo "${OUT}" | grep -c '^  + ')"
  /usr/bin/mako-notify "Steam shortcuts updated (${N} entries)" 2>/dev/null
else
  /usr/bin/mako-notify "Steam shortcuts: $(echo "${OUT}" | tail -n1 | cut -c1-80)" 2>/dev/null
fi
sleep 3
exit ${RC}
