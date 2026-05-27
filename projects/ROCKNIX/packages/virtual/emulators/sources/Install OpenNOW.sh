#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Downloads the latest OpenNOW (GeForce NOW client) arm64 AppImage and installs
# it into the writable storage tree, then creates the launchers that make the
# OpenNOW main-menu section appear. See /usr/bin/opennow-update for details.
# From SSH, pass --force to redownload even if already up to date.
source /etc/profile
exec /usr/bin/opennow-update install "$@"
