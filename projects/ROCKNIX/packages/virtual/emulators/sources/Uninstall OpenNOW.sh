#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Removes the OpenNOW AppImage and launcher. Once the ROM folder is empty,
# EmulationStation hides the OpenNOW section again.

source /etc/profile

OPENNOW_DIR="/storage/roms/opennow"

if [ -d "${OPENNOW_DIR}" ]; then
  rm -rf "${OPENNOW_DIR}"
  echo "OpenNOW removed."
else
  echo "OpenNOW was not installed (nothing to remove)."
fi

echo "Restart EmulationStation to hide the OpenNOW section."
sleep 5
