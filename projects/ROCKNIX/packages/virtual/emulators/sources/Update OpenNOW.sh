#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Pulls the latest OpenNOW (GeForce NOW client) arm64 AppImage, keeping the
# previous one for rollback. Idempotent. See /usr/bin/opennow-update for details.
# From SSH, pass --force to redownload even if already up to date.
source /etc/profile
exec /usr/bin/opennow-update update "$@"
