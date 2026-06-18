#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Rolls back a Proton-CachyOS (ARM64) release line to the version kept by
# "Update Proton CachyOS". CachyOS ships two parallel lines (e.g. 10.x and 11.x)
# that are managed side by side, so this tool first asks WHICH line to roll back
# (when more than one has a saved previous), then for that line:
#   - a live version AND a saved previous exist : swap them (so you can toggle
#     back and forth between the two).
#   - only a saved previous exists (no live)    : just restore it.
#   - nothing saved for that line               : no-op.
#
# Per-line rollback stores live under <Steam>/.cachyos-rollback/<major>/, all on
# /storage so every move is an instant rename. One line is never affected by a
# rollback of the other.

source /etc/profile

STEAM="${STEAM:-/storage/.local/share/Steam}"
CTD="${STEAM}/compatibilitytools.d"
ROLLBACK_STORE="${STEAM}/.cachyos-rollback"
LOCK_DIR="/tmp/cachyos-update.lock"

# proton-cachyos-11.0-20260602-slr-arm64 -> 11
major_of() {
  local b="${1##*/}"
  b="${b#proton-cachyos-}"
  echo "${b%%.*}"
}

newest_live_for_major() {
  ls -d "${CTD}"/proton-cachyos-"${1}".*-arm64 2>/dev/null | sort | tail -n1
}

# Newest saved previous for a line. Supports both the per-line store
# (<store>/<major>/...) and any legacy flat entry (<store>/...).
newest_prev_for_major() {
  { ls -d "${ROLLBACK_STORE}/${1}"/proton-cachyos-"${1}".*-arm64 2>/dev/null
    ls -d "${ROLLBACK_STORE}"/proton-cachyos-"${1}".*-arm64 2>/dev/null
  } | sort | tail -n1
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

# Which lines have a saved previous to roll back to?
declare -A PREV_FOR_MAJOR
MAJORS=()
while IFS= read -r d; do
  [ -n "${d}" ] || continue
  m="$(major_of "${d}")"
  [ -n "${PREV_FOR_MAJOR[$m]}" ] && continue
  PREV_FOR_MAJOR[$m]="$(newest_prev_for_major "${m}")"
  MAJORS+=("${m}")
done < <(find "${ROLLBACK_STORE}" -mindepth 1 -maxdepth 2 -type d -name 'proton-cachyos-*-arm64' 2>/dev/null | sort)

if [ "${#MAJORS[@]}" -eq 0 ]; then
  echo "No saved previous version to roll back to."
  echo "Run \"Update Proton CachyOS\" first; it keeps the version you had per line."
  sleep 6
  exit 0
fi

# Pick the line to roll back. With one candidate, proceed; otherwise prompt.
CHOICE=""
if [ "${#MAJORS[@]}" -eq 1 ]; then
  CHOICE="${MAJORS[0]}"
else
  if command -v zenity >/dev/null 2>&1; then
    ZARGS=()
    for m in "${MAJORS[@]}"; do
      ZARGS+=("${m}.x" "$(basename "${PREV_FOR_MAJOR[$m]}")")
    done
    CHOICE="$(zenity --list \
      --title="Rollback Proton-CachyOS" \
      --text="Which Proton-CachyOS line do you want to roll back?" \
      --column="Line" --column="Roll back to" \
      "${ZARGS[@]}" 2>/dev/null)"
    CHOICE="${CHOICE%%.x*}"
  fi
  # Fallback (e.g. over SSH, no display): numbered text prompt.
  if [ -z "${CHOICE}" ]; then
    echo "Which line do you want to roll back?"
    i=1
    for m in "${MAJORS[@]}"; do
      echo "  ${i}) ${m}.x  ->  $(basename "${PREV_FOR_MAJOR[$m]}")"
      i=$((i + 1))
    done
    printf "Enter a number (or anything else to cancel): "
    read -r sel
    if [[ "${sel}" =~ ^[0-9]+$ ]] && [ "${sel}" -ge 1 ] && [ "${sel}" -le "${#MAJORS[@]}" ]; then
      CHOICE="${MAJORS[$((sel - 1))]}"
    fi
  fi
fi

if [ -z "${CHOICE}" ]; then
  echo "Cancelled. Nothing changed."
  sleep 4
  exit 0
fi

echo ""
echo "Rolling back the ${CHOICE}.x line..."

PREV_DIR="$(newest_prev_for_major "${CHOICE}")"
CURRENT_DIR="$(newest_live_for_major "${CHOICE}")"
STORE="${ROLLBACK_STORE}/${CHOICE}"

if [ -z "${PREV_DIR}" ]; then
  echo "No saved previous version for the ${CHOICE}.x line."
  sleep 6
  exit 0
fi

if [ -n "${CURRENT_DIR}" ]; then
  echo "Swapping live <-> previous:"
  echo "  live now : $(basename "${CURRENT_DIR}")"
  echo "  going to : $(basename "${PREV_DIR}")"
  TMP="${CTD}/.cachyos-swap-${CHOICE}"
  rm -rf "${TMP}"
  mv -f "${CURRENT_DIR}" "${TMP}"   || { echo "ERROR: swap step 1 failed."; sleep 10; exit 1; }
  mv -f "${PREV_DIR}" "${CTD}/"     || { echo "ERROR: swap step 2 failed."; sleep 10; exit 1; }
  mkdir -p "${STORE}"
  # Clear only this line's saved previous, then store the just-replaced version.
  for d in "${STORE}"/proton-cachyos-"${CHOICE}".*-arm64; do
    [ -d "${d}" ] && rm -rf "${d}"
  done
  rm -f "${ROLLBACK_STORE}"/proton-cachyos-"${CHOICE}".*-arm64 2>/dev/null || true
  mv -f "${TMP}" "${STORE}/$(basename "${CURRENT_DIR}")" \
                                    || { echo "ERROR: swap step 3 failed."; sleep 10; exit 1; }
  echo ""
  echo "Done. The previous ${CHOICE}.x version is now live."
  echo "Run \"Rollback Proton CachyOS\" again to swap back, or \"Update Proton CachyOS\" for the latest."
else
  echo "No live ${CHOICE}.x version present; restoring saved: $(basename "${PREV_DIR}")"
  mv -f "${PREV_DIR}" "${CTD}/" || { echo "ERROR: restore failed."; sleep 10; exit 1; }
  rmdir "${STORE}" 2>/dev/null || true
  echo "Done."
fi

echo ""
echo "Fully close and relaunch Steam for the change to take effect."
sleep 8
