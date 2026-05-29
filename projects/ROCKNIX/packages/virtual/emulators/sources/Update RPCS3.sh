#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Downloads the latest official RPCS3 arm64 AppImage from
# https://github.com/RPCS3/rpcs3-binaries-linux-arm64 and installs it to the
# writable storage tree, so the user can stay current between system releases.
#
# The bundled /usr/bin/rpcs3-sa shipped in the squashfs SYSTEM image is never
# touched. The launchers (start_rpcs3.sh and "Start RPCS3.sh") resolve the
# binary at runtime in this order:
#   1. /storage/.local/share/rpcs3-sa/current.AppImage   (this updater)
#   2. /storage/.local/share/rpcs3-sa/previous.AppImage  (auto-rollback)
#   3. /usr/bin/rpcs3-sa                                 (factory fallback)
#
# Safety:
#   - Atomic install (download to .part, rename only after sanity probe).
#   - Sanity probe runs `--version` on the new AppImage inside a 20s timeout;
#     a failure aborts the install without ever swapping the live copy.
#   - The previous good AppImage is kept as previous.AppImage so the launcher
#     can auto-rollback if the new one crashes at runtime.
#   - Lock dir prevents concurrent updates.
#   - Idempotent: skips download if the latest tag is already installed.

source /etc/profile

RPCS3_BASE="/storage/.local/share/rpcs3-sa"
CURRENT="${RPCS3_BASE}/current.AppImage"
PREVIOUS="${RPCS3_BASE}/previous.AppImage"
PART="${RPCS3_BASE}/download.part"
VERSION_FILE="${RPCS3_BASE}/.installed-version"
LOCK_DIR="/tmp/rpcs3-update.lock"
RELEASES_API="https://api.github.com/repos/RPCS3/rpcs3-binaries-linux-arm64/releases/latest"

cleanup() {
  rm -f "${PART}"
  rmdir "${LOCK_DIR}" 2>/dev/null || true
}

fail() {
  echo ""
  echo "ERROR: $*"
  echo ""
  echo "The currently installed RPCS3 has NOT been modified."
  cleanup
  sleep 15
  exit 1
}

mkdir -p "${RPCS3_BASE}"

if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  echo "An RPCS3 update is already running. Retry in a few seconds."
  sleep 5
  exit 1
fi
trap cleanup EXIT

echo "=== RPCS3 updater ==="
echo "Source: ${RELEASES_API}"
echo ""

if [ -f "${VERSION_FILE}" ]; then
  echo "Currently installed: $(cat "${VERSION_FILE}")"
else
  echo "No managed install yet (factory bundled binary in use)."
fi
echo ""

echo "Querying the latest arm64 release..."
META="$(curl -fsSL "${RELEASES_API}")" || fail "could not reach the GitHub API. Check your network."

LATEST_TAG="$(echo "${META}" | grep -oE '"tag_name": *"[^"]*"' | head -n1 | sed -E 's/.*"([^"]+)".*/\1/')"
[ -n "${LATEST_TAG}" ] || fail "could not parse the latest tag name from the GitHub API."

ASSET_URL="$(echo "${META}" \
  | grep -oE '"browser_download_url": *"[^"]*"' \
  | sed -E 's/.*"(https[^"]+)".*/\1/' \
  | grep -iE 'aarch64|arm64' \
  | grep -iE '\.AppImage$' \
  | head -n1)"
[ -n "${ASSET_URL}" ] || fail "no aarch64 .AppImage found in release ${LATEST_TAG}."

echo "Latest available: ${LATEST_TAG}"
echo ""

if [ -f "${VERSION_FILE}" ] && [ "$(cat "${VERSION_FILE}")" = "${LATEST_TAG}" ] && [ -x "${CURRENT}" ]; then
  echo "Already up to date. Nothing to do."
  sleep 5
  exit 0
fi

echo "Downloading: ${ASSET_URL}"
rm -f "${PART}"
wget -c -t 5 -O "${PART}" "${ASSET_URL}" || fail "download failed."

# Basic integrity checks: non-trivial size + ELF magic bytes (AppImages are ELF).
SIZE="$(stat -c%s "${PART}" 2>/dev/null || echo 0)"
if [ "${SIZE}" -lt 10000000 ]; then
  fail "downloaded file is suspiciously small (${SIZE} bytes)."
fi
MAGIC="$(head -c4 "${PART}" | od -An -tx1 | tr -d ' \n')"
if [ "${MAGIC}" != "7f454c46" ]; then
  fail "downloaded file is not an ELF binary (magic=${MAGIC})."
fi

chmod +x "${PART}"

echo ""
echo "Running sanity probe (--version with 20s timeout)..."
PROBE_OUT="$(timeout 20 "${PART}" --appimage-extract-and-run --version 2>&1)"
PROBE_RC=$?
if [ ${PROBE_RC} -ne 0 ]; then
  echo "Probe output:"
  echo "${PROBE_OUT}" | head -n 20
  fail "the new AppImage failed to start (exit ${PROBE_RC}). It is likely incompatible with the libraries shipped on this firmware. The current install is untouched."
fi
echo "Probe OK."
echo ""

# Rotate: current -> previous, .part -> current. Use mv -f so partial states
# are impossible; the AppImage is a single self-contained file.
if [ -f "${CURRENT}" ]; then
  mv -f "${CURRENT}" "${PREVIOUS}"
fi
mv -f "${PART}" "${CURRENT}"
echo "${LATEST_TAG}" > "${VERSION_FILE}"

echo "RPCS3 updated to ${LATEST_TAG}."
echo "Location: ${CURRENT}"
if [ -f "${PREVIOUS}" ]; then
  echo "Previous version kept at: ${PREVIOUS} (auto-rollback if the new one crashes)."
fi
echo ""
echo "Launch RPCS3 from the PS3 section or the 'Start RPCS3' tool to use the new version."
sleep 10
