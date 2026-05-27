#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Enables the GeForce NOW (gfn-electron) main-menu section. The client is already
# bundled in the image, so this is instant and needs no network. After running it,
# restart EmulationStation and launch GeForce NOW from its main-menu section.
# First login: NVIDIA account or Discord (Google sign-in is blocked in Electron).
source /etc/profile
exec /usr/bin/gfn-electron-setup install
