#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Removes the GeForce NOW (gfn-electron) launcher so the main-menu section
# disappears. The bundled client stays in the image and your NVIDIA login/config
# under /storage/.config/gfn-electron is kept. Re-run "Install GeForce NOW" to
# bring the section back.
source /etc/profile
exec /usr/bin/gfn-electron-setup uninstall
