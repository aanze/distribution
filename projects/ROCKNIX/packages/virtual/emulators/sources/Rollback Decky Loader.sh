#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Thin wrapper — reverts Decky Loader to the previously installed PluginLoader
# (kept by the last update) via /usr/bin/decky-update, then restarts the service.

exec /usr/bin/decky-update rollback
