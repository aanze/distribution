#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Pulls the latest Citron (Nintendo Switch) arm64 nightly AppImage, keeping the
# previous one for rollback. Idempotent. See /usr/bin/citron-update for details.
source /etc/profile
/usr/bin/citron-update update
