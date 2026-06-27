#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Thin wrapper — updates Decky Loader to the latest OFFICIAL stable release via
# /usr/bin/decky-update. Reliable on the Odin (box64) unlike Decky's in-app
# updater; a no-op if you are already current. Keeps the previous build for
# rollback. Plugins and settings are preserved.

exec /usr/bin/decky-update update
