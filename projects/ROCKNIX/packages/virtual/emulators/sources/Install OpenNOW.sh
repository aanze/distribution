#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Download + install OpenNOW, an open-source GeForce NOW client, as an
# ALTERNATIVE inside the existing GeForce NOW main-menu section (the default
# GeForce NOW app stays). After running it, restart EmulationStation and launch
# "OpenNOW" from the GeForce NOW section. First login: NVIDIA account or Discord.
source /etc/profile
exec /usr/bin/opennow-update install
