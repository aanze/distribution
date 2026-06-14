#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Rolls back the Proton-CachyOS (ARM64) compatibility tool to the version kept
# by "Update Proton CachyOS". Two cases:
#   - a live version AND a saved previous exist : swap them (so you can toggle
#     back and forth between the two).
#   - only a saved previous exists (no live)    : just restore it.
#   - nothing saved                             : no-op.
#
# Both stores live on /storage so every move is an instant rename.

source /etc/profile

STEAM="${STEAM:-/storage/.local/share/Steam}"
CTD="${STEAM}/compatibilitytools.d"
ROLLBACK_STORE="${STEAM}/.cachyos-rollback"
LOCK_DIR="/tmp/cachyos-update.lock"

newest_cachyos_in() {
  ls -d "${1}"/proton-cachyos-*-arm64 2>/dev/null | sort | tail -n1
}

echo "=== Proton-CachyOS rollback ==="
echo ""

if [ ! -d "${CTD}" ]; then
  echo "Steam is not installed (no compatibilitytools.d). Nothing to roll back."
  sleep 5
  exit 0
fi

if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  echo "A Proton-CachyOS update or rollback is already running. Retry in a few seconds."
  sleep 5
  exit 1
fi
trap 'rmdir "${LOCK_DIR}" 2>/dev/null || true' EXIT

PREV_DIR="$(newest_cachyos_in "${ROLLBACK_STORE}")"
CURRENT_DIR="$(newest_cachyos_in "${CTD}")"

if [ -z "${PREV_DIR}" ]; then
  echo "No saved previous version to roll back to."
  if [ -n "${CURRENT_DIR}" ]; then
    echo "Live version stays: $(basename "${CURRENT_DIR}")"
  fi
  sleep 6
  exit 0
fi

if [ -n "${CURRENT_DIR}" ]; then
  echo "Swapping live <-> previous:"
  echo "  live now : $(basename "${CURRENT_DIR}")"
  echo "  going to : $(basename "${PREV_DIR}")"
  TMP="${CTD}/.cachyos-swap"
  rm -rf "${TMP}"
  mv -f "${CURRENT_DIR}" "${TMP}"        || { echo "ERROR: swap step 1 failed."; sleep 10; exit 1; }
  mv -f "${PREV_DIR}" "${CTD}/"          || { echo "ERROR: swap step 2 failed."; sleep 10; exit 1; }
  rm -rf "${ROLLBACK_STORE:?}"/*
  mv -f "${TMP}" "${ROLLBACK_STORE}/$(basename "${CURRENT_DIR}")" \
                                        || { echo "ERROR: swap step 3 failed."; sleep 10; exit 1; }
  echo ""
  echo "Done. The previous version is now live."
  echo "Run \"Rollback Proton CachyOS\" again to swap back, or \"Update Proton CachyOS\" for the latest."
else
  echo "No live version present; restoring saved: $(basename "${PREV_DIR}")"
  mv -f "${PREV_DIR}" "${CTD}/" || { echo "ERROR: restore failed."; sleep 10; exit 1; }
  rmdir "${ROLLBACK_STORE}" 2>/dev/null || true
  echo "Done."
fi

echo ""
echo "Fully close and relaunch Steam for the change to take effect."
sleep 8
