#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Reverts the managed OpenNOW install to the previously kept AppImage. See
# /usr/bin/opennow-update for details.
source /etc/profile
exec /usr/bin/opennow-update rollback
