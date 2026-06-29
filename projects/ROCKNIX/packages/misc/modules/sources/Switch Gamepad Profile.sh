#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2025-present ROCKNIX (https://github.com/ROCKNIX)
#
# Toggle the InputPlumber controller-emulation profile between
# Xbox Elite (the AYN Odin 3 back paddles work as real game buttons P1/P3)
# and DualSense (PlayStation layout/prompts, no paddles). The preference persists across
# reboots. All the actual work lives in the shared /usr/bin/gamepad-profile
# backend, which also drives the Quick Settings and Ducktale Controls toggles.

source /etc/profile

gamepad-profile toggle >/dev/null
LABEL="$(gamepad-profile label)"

zenity --info --timeout=4 \
    --text="Gamepad profile switched to:\n<b>${LABEL}</b>" 2>/dev/null || \
notify-send "Gamepad Profile" "Switched to: ${LABEL}" 2>/dev/null || true
