#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Removes the downloaded Citron AppImage(s). Keys, saves and config are kept.
# See /usr/bin/citron-update for details.
source /etc/profile
/usr/bin/citron-update uninstall
