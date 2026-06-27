#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Thin wrapper — the whole Decky lifecycle lives in /usr/bin/decky-update.
# Installs the OFFICIAL Decky Loader (latest stable release, fetched straight
# from github.com/SteamDeckHomebrew/decky-loader) plus the Steam-launch
# re-inject watcher. Re-runnable any time as a clean repair/reinstall.

exec /usr/bin/decky-update install
