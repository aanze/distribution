#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Manual rollback for the managed RPCS3 install. Three cases:
#   - current + previous exist : swap them (current <-> previous).
#   - only current exists      : delete current; the factory bundled
#                                /usr/bin/rpcs3-sa takes over.
#   - nothing managed          : no-op (factory bundled already in use).
#
# The factory bundled binary in the squashfs SYSTEM image is never modified.

source /etc/profile

RPCS3_BASE="/storage/.local/share/rpcs3-sa"
CURRENT="${RPCS3_BASE}/current.AppImage"
PREVIOUS="${RPCS3_BASE}/previous.AppImage"
VERSION_FILE="${RPCS3_BASE}/.installed-version"
LOCK_DIR="/tmp/rpcs3-update.lock"

if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  echo "An RPCS3 update or rollback is already running. Retry in a few seconds."
  sleep 5
  exit 1
fi
trap 'rmdir "${LOCK_DIR}" 2>/dev/null || true' EXIT

echo "=== RPCS3 rollback ==="
echo ""

if [ ! -f "${CURRENT}" ] && [ ! -f "${PREVIOUS}" ]; then
  echo "No managed RPCS3 install found. The factory bundled binary at /usr/bin/rpcs3-sa is already in use."
  sleep 5
  exit 0
fi

if [ -f "${CURRENT}" ] && [ -f "${PREVIOUS}" ]; then
  echo "Swapping current <-> previous AppImage..."
  TMP="${RPCS3_BASE}/.swap.AppImage"
  mv -f "${CURRENT}" "${TMP}"
  mv -f "${PREVIOUS}" "${CURRENT}"
  mv -f "${TMP}" "${PREVIOUS}"
  rm -f "${VERSION_FILE}"
  echo "Done. The previously installed AppImage is now active."
  echo "Re-run 'Update RPCS3' to go back to the latest, or run rollback again to revert this swap."
  sleep 8
  exit 0
fi

# Only current exists -> drop it and fall back to bundled.
echo "No previous managed version available."
echo "Removing the managed AppImage and falling back to the factory bundled /usr/bin/rpcs3-sa."
rm -f "${CURRENT}" "${VERSION_FILE}"
echo "Done."
sleep 5
