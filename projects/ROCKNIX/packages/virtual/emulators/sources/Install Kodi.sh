#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Tools menu wrapper: create the opt-in Kodi ES section (client is already
# baked in the image - this only creates /storage/roms/kodi).

source /etc/profile
exec /usr/bin/kodi-setup install
