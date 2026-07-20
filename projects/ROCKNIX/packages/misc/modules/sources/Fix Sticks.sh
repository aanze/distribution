#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX/DUCKTALE
#
# Restore the known-good AYN Odin 3 stick calibration (BOTH sticks), live
# AND in the boot value store, then restart InputPlumber.
#
# Use when a stick stops reaching the edges (slow camera, Steam tester dot
# short of the ring) or the rest position sits off-center. Known culprits:
#  - a GPcal re-run: its rotation sweep records diagonal PEAKS as axis
#    maxima, which a sustained cardinal push can never reach;
#  - hand-tuned ASYMMETRIC ranges: consumers (InputPlumber/SDL/Steam) place
#    the center at (min+max)/2, so the rest position drifts off-center;
#  - an Android factory reset / AYN recalibration changing what the MCU
#    actually outputs (the store then no longer matches the hardware).
#
# Values live in ONE place: rsinput-cal-default (quirks bin, staged into
# /run/rsinput at boot by 052-stick-calibration). This tool just rewrites
# the store from it and re-applies.

source /etc/profile

RD="/run/rsinput"
QB="/usr/lib/autostart/quirks/devices/AYN Odin 3/bin"
[ -x "${RD}/rsinput-cal-default" ] || RD="${QB}"

"${RD}/rsinput-cal-default" --force
"${RD}/rsinput-cal-apply"
systemctl restart inputplumber

zenity --info --timeout=4 \
    --text="Stick calibration restored (both sticks):\n<b>LX ±700  LY ±835  RX ±910  RY ±950</b>" 2>/dev/null || \
notify-send "Fix Sticks" "Calibration restored" 2>/dev/null || true
