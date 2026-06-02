#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Reverts the managed Citron install to the previously kept AppImage. See
# /usr/bin/citron-update for details.
source /etc/profile
/usr/bin/citron-update rollback
