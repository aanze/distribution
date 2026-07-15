#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX/DUCKTALE
#
# Re-apply the measured AYN Odin 3 RIGHT-stick calibration to the rsinput
# driver, live AND in the boot calibration file, then restart InputPlumber.
#
# Use when the right stick stops reaching the edges again (slow camera, Steam
# tester dot short of the ring). Usual culprit: a GPcal re-run — its rotation
# sweep records diagonal PEAKS (~±1301 X / ~±1195 Y) as the axis maxima, which
# a sustained cardinal push can never reach, so downstream (InputPlumber/SDL)
# normalizes to ~75-90% and the edge becomes unreachable. The values below are
# the SUSTAINED cardinal reach measured live on this unit (2026-07-15).

source /etc/profile

P=/sys/module/rsinput/parameters
F=/storage/.config/autostart/GPcal.sh

set_param() { echo "${2}" > "${P}/axis_${1}" 2>/dev/null; }

set_param rightx_min -940;      set_param rightx_max 980
set_param righty_min -870;      set_param righty_max 845
set_param rightx_center 0;      set_param righty_center 0
set_param rightx_deadzone 70;   set_param righty_deadzone 70
set_param rightx_antideadzone 0; set_param righty_antideadzone 0
echo 1 > "${P}/update_params"
sleep 0.5
systemctl restart inputplumber

# Persist into the boot calibration file (re-run at every boot) so the fix
# survives reboots; create a minimal one if GPcal never wrote it.
if [ -f "${F}" ]; then
  sed -i \
    -e "s|^echo .* \(.*/axis_rightx_min\)$|echo -940 > \1|" \
    -e "s|^echo .* \(.*/axis_rightx_max\)$|echo 980 > \1|" \
    -e "s|^echo .* \(.*/axis_rightx_center\)$|echo 0 > \1|" \
    -e "s|^echo .* \(.*/axis_rightx_deadzone\)$|echo 70 > \1|" \
    -e "s|^echo .* \(.*/axis_rightx_antideadzone\)$|echo 0 > \1|" \
    -e "s|^echo .* \(.*/axis_righty_min\)$|echo -870 > \1|" \
    -e "s|^echo .* \(.*/axis_righty_max\)$|echo 845 > \1|" \
    -e "s|^echo .* \(.*/axis_righty_center\)$|echo 0 > \1|" \
    -e "s|^echo .* \(.*/axis_righty_deadzone\)$|echo 70 > \1|" \
    -e "s|^echo .* \(.*/axis_righty_antideadzone\)$|echo 0 > \1|" \
    "${F}"
else
  mkdir -p "$(dirname "${F}")"
  cat > "${F}" <<'EOF'
#!/usr/bin/env bash
# AYN Odin 3 right-stick calibration (measured sustained reach, DUCKTALE)
echo -940 > /sys/module/rsinput/parameters/axis_rightx_min
echo 980 > /sys/module/rsinput/parameters/axis_rightx_max
echo 0 > /sys/module/rsinput/parameters/axis_rightx_center
echo 70 > /sys/module/rsinput/parameters/axis_rightx_deadzone
echo 0 > /sys/module/rsinput/parameters/axis_rightx_antideadzone
echo -870 > /sys/module/rsinput/parameters/axis_righty_min
echo 845 > /sys/module/rsinput/parameters/axis_righty_max
echo 0 > /sys/module/rsinput/parameters/axis_righty_center
echo 70 > /sys/module/rsinput/parameters/axis_righty_deadzone
echo 0 > /sys/module/rsinput/parameters/axis_righty_antideadzone
echo 1 > /sys/module/rsinput/parameters/update_params
sleep 0.5
systemctl restart inputplumber
EOF
  chmod +x "${F}"
fi

zenity --info --timeout=4 \
    --text="Right stick calibration restored:\n<b>X -940..980   Y -870..845</b>" 2>/dev/null || \
notify-send "Right Stick" "Calibration restored" 2>/dev/null || true
