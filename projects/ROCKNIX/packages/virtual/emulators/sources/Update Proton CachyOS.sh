#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Updates the Proton-CachyOS (ARM64) Steam compatibility tool in place, without
# re-running the full "Install Steam" routine. Fetches the latest arm64 release
# from https://github.com/CachyOS/proton-cachyos, patches it for ARM (strips the
# require_tool_appid line that otherwise makes Steam fail with "unable to launch
# the compatibility tool"), and keeps the version you had as a rollback copy.
#
# Layout:
#   compatibilitytools.d/proton-cachyos-<ver>-arm64   <- the live (active) tool
#   <Steam>/.cachyos-rollback/proton-cachyos-<ver>-arm64
#                                                     <- one kept previous version
#
# The .cachyos-rollback store lives OUTSIDE compatibilitytools.d so Steam never
# shows it as a second, duplicate entry. Both stores are on /storage, so moving
# between them is an instant rename (no large copy).
#
# Safety:
#   - Download to a .part file, verified (size + xz magic) before extraction.
#   - Extract to a staging dir and validated (proton + files/) before going live.
#   - The previous good version is kept for one-press rollback.
#   - Lock dir prevents concurrent update/rollback.
#   - Idempotent: skips if the live tool is already the latest arm64 release.

source /etc/profile

STEAM="${STEAM:-/storage/.local/share/Steam}"
CTD="${STEAM}/compatibilitytools.d"
ROLLBACK_STORE="${STEAM}/.cachyos-rollback"
STAGING="${CTD}/.cachyos-staging"
PART="${CTD}/.cachyos-download.part"
LOCK_DIR="/tmp/cachyos-update.lock"
RELEASES_API="https://api.github.com/repos/CachyOS/proton-cachyos/releases?per_page=20"

cleanup() {
  rm -f "${PART}"
  rm -rf "${STAGING}"
  rmdir "${LOCK_DIR}" 2>/dev/null || true
}

fail() {
  echo ""
  echo "ERROR: $*"
  echo ""
  echo "The currently installed Proton-CachyOS has NOT been modified."
  cleanup
  sleep 15
  exit 1
}

# Newest installed proton-cachyos-*-arm64 dir inside a given directory (by name,
# which sorts chronologically thanks to the YYYYMMDD in the version), or empty.
newest_cachyos_in() {
  ls -d "${1}"/proton-cachyos-*-arm64 2>/dev/null | sort | tail -n1
}

echo "=== Proton-CachyOS updater (ARM64) ==="
echo ""

if [ ! -d "${CTD}" ]; then
  echo "Steam is not installed yet (no compatibilitytools.d)."
  echo "Run the \"Install Steam\" tool first, then come back here to update Proton-CachyOS."
  sleep 10
  exit 1
fi

if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  echo "A Proton-CachyOS update or rollback is already running. Retry in a few seconds."
  sleep 5
  exit 1
fi
trap cleanup EXIT

CURRENT_DIR="$(newest_cachyos_in "${CTD}")"
if [ -n "${CURRENT_DIR}" ]; then
  echo "Currently installed: $(basename "${CURRENT_DIR}")"
else
  echo "No Proton-CachyOS currently installed."
fi
echo ""

echo "Querying the latest arm64 release from CachyOS/proton-cachyos..."
META="$(curl -fsSL "${RELEASES_API}")" || fail "could not reach the GitHub API. Check your network."

ASSET_URL="$(echo "${META}" \
  | grep -oE '"browser_download_url": *"[^"]*"' \
  | sed -E 's/.*"(https[^"]+)".*/\1/' \
  | grep -E 'arm64\.tar\.xz$' \
  | head -n1)"
[ -n "${ASSET_URL}" ] || fail "no arm64 .tar.xz asset found in the latest CachyOS releases (API rate limit or asset naming changed?)."

TAR_NAME="$(basename "${ASSET_URL}")"
TARGET_NAME="${TAR_NAME%.tar.xz}"
TARGET_DIR="${CTD}/${TARGET_NAME}"

echo "Latest available: ${TARGET_NAME}"
echo ""

if [ -d "${TARGET_DIR}" ] && [ -f "${TARGET_DIR}/proton" ]; then
  echo "Already up to date. Nothing to do."
  sleep 5
  exit 0
fi

echo "Downloading: ${ASSET_URL}"
rm -f "${PART}"
wget -c -t 5 -O "${PART}" "${ASSET_URL}" || fail "download failed."

# Integrity: non-trivial size + xz magic bytes (FD 37 7A 58 5A 00).
SIZE="$(stat -c%s "${PART}" 2>/dev/null || echo 0)"
if [ "${SIZE}" -lt 50000000 ]; then
  fail "downloaded file is suspiciously small (${SIZE} bytes)."
fi
MAGIC="$(head -c6 "${PART}" | od -An -tx1 | tr -d ' \n')"
if [ "${MAGIC}" != "fd377a585a00" ]; then
  fail "downloaded file is not an xz archive (magic=${MAGIC})."
fi

echo ""
echo "Extracting..."
rm -rf "${STAGING}"
mkdir -p "${STAGING}"
tar -xf "${PART}" -C "${STAGING}" || fail "extraction failed (corrupt download?)."

EXTRACTED="${STAGING}/${TARGET_NAME}"
if [ ! -d "${EXTRACTED}" ]; then
  # Fall back to the single top-level directory the tarball produced.
  EXTRACTED="$(find "${STAGING}" -mindepth 1 -maxdepth 1 -type d | head -n1)"
fi
if [ -z "${EXTRACTED}" ] || [ ! -f "${EXTRACTED}/proton" ] || [ ! -d "${EXTRACTED}/files" ]; then
  fail "extracted tool is incomplete (proton/files missing)."
fi

# Patch for ARM64: drop require_tool_appid (points at an x86 runtime that can't
# launch on ARM, the classic "unable to launch the compatibility tool" crash).
MANIFEST="${EXTRACTED}/toolmanifest.vdf"
if [ -f "${MANIFEST}" ] && grep -q require_tool_appid "${MANIFEST}"; then
  sed -i '/require_tool_appid/d' "${MANIFEST}" || fail "could not patch toolmanifest.vdf."
  echo "Patched toolmanifest.vdf (removed require_tool_appid)."
fi

# Rotate rollback store: keep the version we currently have as the single
# "previous"; discard any older leftovers.
echo ""
echo "Saving current version for rollback..."
rm -rf "${ROLLBACK_STORE}"
mkdir -p "${ROLLBACK_STORE}"
if [ -n "${CURRENT_DIR}" ]; then
  mv -f "${CURRENT_DIR}" "${ROLLBACK_STORE}/" || fail "could not move current version into the rollback store."
fi
# Remove any remaining (older) live copies so only the new one stays visible.
for d in "${CTD}"/proton-cachyos-*-arm64; do
  [ -d "${d}" ] && rm -rf "${d}"
done

# Go live: move the validated new tool into place.
mv -f "${EXTRACTED}" "${TARGET_DIR}" || fail "could not move the new version into place."

echo ""
echo "Proton-CachyOS updated to ${TARGET_NAME}."
echo "Location: ${TARGET_DIR}"
PREV="$(newest_cachyos_in "${ROLLBACK_STORE}")"
if [ -n "${PREV}" ]; then
  echo "Previous version kept for rollback: $(basename "${PREV}")"
  echo "Run \"Rollback Proton CachyOS\" to switch back to it."
fi
echo ""
echo "Fully close and relaunch Steam, then pick \"${TARGET_NAME}\" under a game's"
echo "Properties > Compatibility."
sleep 10
