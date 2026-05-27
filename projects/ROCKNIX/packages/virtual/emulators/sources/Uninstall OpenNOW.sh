#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Removes the downloaded OpenNOW AppImage(s) and launchers. Your NVIDIA
# login/config under /storage/.config/opennow-stable is kept. The OpenNOW
# section disappears once its ROM folder is empty. See /usr/bin/opennow-update.
source /etc/profile
exec /usr/bin/opennow-update uninstall
