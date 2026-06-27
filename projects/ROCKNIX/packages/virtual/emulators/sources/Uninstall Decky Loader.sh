#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Thin wrapper — removes Decky Loader (stops/disables the service, removes its
# unit, the boot watcher, and the homebrew tree) via /usr/bin/decky-update.

exec /usr/bin/decky-update uninstall
