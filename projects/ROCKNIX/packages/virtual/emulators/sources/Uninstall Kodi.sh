#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Tools menu wrapper: remove the Kodi ES section (keeps /storage/.kodi with
# the Plex login and settings).

source /etc/profile
exec /usr/bin/kodi-setup uninstall
