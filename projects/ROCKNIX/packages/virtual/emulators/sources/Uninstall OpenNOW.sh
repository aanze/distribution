#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Remove the OpenNOW AppImage + its launcher from the GeForce NOW section. The
# default GeForce NOW app is left untouched; your OpenNOW login/config is kept.
source /etc/profile
exec /usr/bin/opennow-update uninstall
