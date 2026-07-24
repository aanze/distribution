#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Update OpenNOW to the latest arm64 release. Skips the download if already
# current (idempotent). No-op if OpenNOW was never installed.
source /etc/profile
exec /usr/bin/opennow-update update
