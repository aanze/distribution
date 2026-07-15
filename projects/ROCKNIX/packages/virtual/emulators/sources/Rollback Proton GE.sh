#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Rolls Proton-GE (ARM64) back to the version kept by "Update Proton GE".
# GE ships a single release line, so this is a plain swap:
#   - a live version AND a saved previous exist : swap them (so you can toggle
#     back and forth between the two).
#   - only a saved previous exists (no live)    : just restore it.
#   - nothing saved                             : no-op.
#
# The rollback store lives under <Steam>/.geproton-rollback/, all on /storage
# so every move is an instant rename.

source /etc/profile

STEAM="${STEAM:-/storage/.local/share/Steam}"
CTD="${STEAM}/compatibilitytools.d"
ROLLBACK_STORE="${STEAM}/.geproton-rollback"
LOCK_DIR="/tmp/geproton-update.lock"

cleanup() { rmdir "${LOCK_DIR}" 2>/dev/null || true; }
trap cleanup EXIT

echo "=== Proton-GE rollback (ARM64) ==="
echo ""

if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  echo "A Proton-GE update or rollback is already running. Retry in a few seconds."
  sleep 5
  exit 1
fi

shopt -s nullglob
LIVE=("${CTD}"/GE-Proton*-aarch64)
SAVED=("${ROLLBACK_STORE}"/GE-Proton*-aarch64)
shopt -u nullglob

if [ "${#SAVED[@]}" -eq 0 ]; then
  echo "No saved previous Proton-GE version — nothing to roll back to."
  echo "(A previous version is kept automatically by \"Update Proton GE\".)"
  sleep 8
  exit 0
fi

SAVED_ONE="${SAVED[0]}"
mkdir -p "${CTD}"

if [ "${#LIVE[@]}" -gt 0 ]; then
  LIVE_ONE="${LIVE[0]}"
  echo "Swapping:"
  echo "  live     : $(basename "${LIVE_ONE}")  ->  saved"
  echo "  restored : $(basename "${SAVED_ONE}")"
  TMP="${ROLLBACK_STORE}/.swap.$$"
  mv -f "${SAVED_ONE}" "${TMP}"             || { echo "ERROR: move failed"; sleep 10; exit 1; }
  mv -f "${LIVE_ONE}" "${ROLLBACK_STORE}/"  || { mv -f "${TMP}" "${SAVED_ONE}"; echo "ERROR: swap failed, state restored"; sleep 10; exit 1; }
  mv -f "${TMP}" "${CTD}/$(basename "${SAVED_ONE}")" || { echo "ERROR: restore failed"; sleep 10; exit 1; }
else
  echo "Restoring: $(basename "${SAVED_ONE}")"
  mv -f "${SAVED_ONE}" "${CTD}/" || { echo "ERROR: restore failed"; sleep 10; exit 1; }
fi

echo ""
echo "Done. Fully close and relaunch Steam so it rescans compatibility tools."
sleep 8
