#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Downloads the latest Citron (Nintendo Switch) arm64 AppImage and installs it
# into the writable storage tree. See /usr/bin/citron-update for details.
source /etc/profile
/usr/bin/citron-update install
