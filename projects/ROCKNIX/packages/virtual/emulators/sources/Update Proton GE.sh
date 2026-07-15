#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Updates the Proton-GE (ARM64) Steam compatibility tool in place, without
# re-running the full "Install Steam" routine. Same scheme as the
# Proton-CachyOS updater: fetch the newest release that ships an aarch64
# build from https://github.com/GloriousEggroll/proton-ge-custom, verify it
# (official sha512 when published, plus size + gzip magic), patch it for ARM
# (strip the require_tool_appid line that otherwise makes Steam fail with
# "unable to launch the compatibility tool"), and keep the version you had
# as a one-press rollback.
#
# GE ships a single release line, so unlike CachyOS there is no per-major
# side-by-side handling: one live dir, one rollback slot.
#
# Layout:
#   compatibilitytools.d/GE-ProtonX-Y-aarch64      <- live (active) tool
#   <Steam>/.geproton-rollback/GE-Proton*-aarch64  <- one kept previous version
#
# Safety:
#   - Download to a .part file, checksum/size/magic-verified before extraction.
#   - Extract to a staging dir and validated (proton + files/) before going live.
#   - The previous good version is kept for one-press rollback.
#   - Lock dir prevents concurrent update/rollback.
#   - Idempotent: exits early if the live tool is already the latest release.

source /etc/profile

STEAM="${STEAM:-/storage/.local/share/Steam}"
CTD="${STEAM}/compatibilitytools.d"
ROLLBACK_STORE="${STEAM}/.geproton-rollback"
STAGING="${CTD}/.geproton-staging"
PART="${CTD}/.geproton-download.part"
LOCK_DIR="/tmp/geproton-update.lock"
RELEASES_API="https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases?per_page=20"

cleanup() {
  rm -f "${PART}" "${PART}.sha512"
  rm -rf "${STAGING}"
  rmdir "${LOCK_DIR}" 2>/dev/null || true
}

trap cleanup EXIT

fail() {
  echo "ERROR: $*" >&2
  sleep 15
  exit 1
}

echo "=== Proton-GE updater (ARM64) ==="
echo ""

if [ ! -d "${CTD}" ]; then
  echo "Steam is not installed yet (no compatibilitytools.d)."
  echo "Run the \"Install Steam\" tool first, then come back here to update Proton-GE."
  sleep 10
  exit 1
fi

if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  echo "A Proton-GE update or rollback is already running. Retry in a few seconds."
  sleep 5
  exit 1
fi

echo "Currently installed:"
shopt -s nullglob
INSTALLED=("${CTD}"/GE-Proton*-aarch64)
shopt -u nullglob
if [ "${#INSTALLED[@]}" -gt 0 ]; then
  for d in "${INSTALLED[@]}"; do
    echo "  - $(basename "${d}")"
  done
else
  echo "  (none)"
fi
echo ""

echo "Querying the latest aarch64 release from GloriousEggroll/proton-ge-custom..."
META="$(curl -fsSL "${RELEASES_API}")" || fail "could not reach the GitHub API. Check your network."

# Newest release that ships an aarch64 tarball (older GE lines are x86-only).
URL="$(echo "${META}" \
  | grep -oE '"browser_download_url": *"[^"]*-aarch64\.tar\.gz"' \
  | sed -E 's/.*"(https[^"]+)".*/\1/' \
  | head -n1)"
[ -n "${URL}" ] || fail "no aarch64 .tar.gz asset found in the latest GE releases (API rate limit or asset naming changed?)."

NAME="${URL##*/}"                    # GE-ProtonX-Y-aarch64.tar.gz
TARGET_NAME="${NAME%.tar.gz}"        # GE-ProtonX-Y-aarch64
TARGET_DIR="${CTD}/${TARGET_NAME}"

echo "Latest: ${TARGET_NAME}"
echo ""

if [ -d "${TARGET_DIR}" ] && [ -f "${TARGET_DIR}/proton" ]; then
  echo "Already up to date."
  sleep 6
  exit 0
fi

rm -f "${PART}"
echo "Downloading: ${NAME}"
# busybox wget draws its progress bar (%, size, ETA) on stderr; keep it on
# the tool console so the download never looks stuck.
wget -c -t 5 -O "${PART}" "${URL}" 1>&2 || fail "download failed."

# Integrity: GE publishes an official sha512 next to the tarball — use it
# when available; always keep the size + gzip-magic sanity net.
if command -v sha512sum >/dev/null 2>&1 \
   && wget -q -T 15 -O "${PART}.sha512" "${URL%.tar.gz}.sha512sum" 2>/dev/null; then
  WANT="$(awk '{print $1; exit}' "${PART}.sha512")"
  HAVE="$(sha512sum "${PART}" | awk '{print $1}')"
  [ -n "${WANT}" ] && [ "${WANT}" = "${HAVE}" ] || fail "sha512 mismatch on the downloaded tarball."
  echo "  sha512 verified."
fi
size="$(stat -c%s "${PART}" 2>/dev/null || echo 0)"
if [ "${size}" -lt 50000000 ]; then
  fail "downloaded file is suspiciously small (${size} bytes)."
fi
magic="$(head -c2 "${PART}" | od -An -tx1 | tr -d ' \n')"
[ "${magic}" = "1f8b" ] || fail "downloaded file is not a gzip archive (magic=${magic})."

rm -rf "${STAGING}"
mkdir -p "${STAGING}"
echo "Extracting (a few hundred MB, takes a minute or two)..."
tar -xzf "${PART}" -C "${STAGING}" || fail "extraction failed (corrupt download?)."
echo "Extraction done."

EXTRACTED="${STAGING}/${TARGET_NAME}"
if [ ! -d "${EXTRACTED}" ]; then
  EXTRACTED="$(find "${STAGING}" -mindepth 1 -maxdepth 1 -type d | head -n1)"
fi
if [ -z "${EXTRACTED}" ] || [ ! -f "${EXTRACTED}/proton" ] || [ ! -d "${EXTRACTED}/files" ]; then
  fail "extracted tool is incomplete (proton/files missing)."
fi

# Patch for ARM64: drop require_tool_appid (points at an x86 runtime that can't
# launch on ARM -- the classic "unable to launch the compatibility tool" crash).
MANIFEST="${EXTRACTED}/toolmanifest.vdf"
if [ -f "${MANIFEST}" ] && grep -q require_tool_appid "${MANIFEST}"; then
  sed -i '/require_tool_appid/d' "${MANIFEST}" || fail "could not patch toolmanifest.vdf."
fi

# Rotate the rollback: keep the current live version as the single "previous";
# discard any older leftovers. Same-store rename on /storage = instant.
mkdir -p "${ROLLBACK_STORE}"
shopt -s nullglob
CURRENT=("${CTD}"/GE-Proton*-aarch64)
OLD_SAVED=("${ROLLBACK_STORE}"/GE-Proton*-aarch64)
shopt -u nullglob
for d in "${OLD_SAVED[@]}"; do rm -rf "${d}"; done
if [ "${#CURRENT[@]}" -gt 0 ]; then
  mv -f "${CURRENT[0]}" "${ROLLBACK_STORE}/" || fail "could not move the current version into the rollback store."
  # any additional stale live copies go away so a single live dir remains
  for d in "${CURRENT[@]:1}"; do rm -rf "${d}"; done
fi

mv -f "${EXTRACTED}" "${TARGET_DIR}" || fail "could not move the new version into place."

echo ""
echo "Updated to ${TARGET_NAME}."
PREV="$(ls -d "${ROLLBACK_STORE}"/GE-Proton*-aarch64 2>/dev/null | head -n1)"
[ -n "${PREV}" ] && echo "Previous version kept for rollback: $(basename "${PREV}")"
echo ""
echo "Fully close and relaunch Steam, then pick GE-Proton under a game's"
echo "Properties > Compatibility. Run \"Rollback Proton GE\" to switch back."
sleep 10
