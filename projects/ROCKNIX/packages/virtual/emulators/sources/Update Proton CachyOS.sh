#!/bin/bash

# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Updates the Proton-CachyOS (ARM64) Steam compatibility tools in place, without
# re-running the full "Install Steam" routine. CachyOS ships two parallel release
# lines (e.g. 10.x and 11.x); this tool manages BOTH, keeping each line's latest
# arm64 build installed side by side. That way a fresh proton-10 release can
# never replace your proton-11 (the old single-slot behaviour) -- each line lives
# in its own directory and is updated independently.
#
# For every line it fetches the newest arm64 release from
# https://github.com/CachyOS/proton-cachyos, patches it for ARM (strips the
# require_tool_appid line that otherwise makes Steam fail with "unable to launch
# the compatibility tool"), and keeps the version you had as a per-line rollback.
#
# Layout:
#   compatibilitytools.d/proton-cachyos-<ver>-arm64       <- live (active) tools
#   <Steam>/.cachyos-rollback/<major>/proton-cachyos-<ver>-arm64
#                                                         <- one kept previous
#                                                            version per line
#
# The .cachyos-rollback store lives OUTSIDE compatibilitytools.d so Steam never
# shows it as a duplicate entry. Both stores are on /storage, so moving between
# them is an instant rename (no large copy).
#
# Safety:
#   - Download to a .part file, verified (size + xz magic) before extraction.
#   - Extract to a staging dir and validated (proton + files/) before going live.
#   - The previous good version of each line is kept for one-press rollback.
#   - Lock dir prevents concurrent update/rollback.
#   - Idempotent: skips any line whose live tool is already the latest release.
#   - A failure on one line never touches the other line's live tool.

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

trap cleanup EXIT

# Soft failure for a single line: report, clean scratch, but keep going so the
# other line still gets a chance to update. Returns non-zero.
line_fail() {
  echo "  ERROR: $*" >&2
  echo "  This line was left unchanged." >&2
  rm -f "${PART}"
  rm -rf "${STAGING}"
  return 1
}

# proton-cachyos-11.0-20260602-slr-arm64 -> 11
major_of() {
  local b="${1##*/}"
  b="${b#proton-cachyos-}"
  echo "${b%%.*}"
}

# Live dirs for a major line, oldest..newest by name (date sorts chronologically).
live_versions_for_major() {
  ls -d "${CTD}"/proton-cachyos-"${1}".*-arm64 2>/dev/null | sort
}
newest_live_for_major() {
  live_versions_for_major "${1}" | tail -n1
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

echo "Currently installed:"
shopt -s nullglob
INSTALLED=("${CTD}"/proton-cachyos-*-arm64)
shopt -u nullglob
if [ "${#INSTALLED[@]}" -gt 0 ]; then
  for d in "${INSTALLED[@]}"; do
    echo "  - $(basename "${d}")"
  done
else
  echo "  (none)"
fi
echo ""

echo "Querying the latest arm64 releases from CachyOS/proton-cachyos..."
META="$(curl -fsSL "${RELEASES_API}")" || {
  echo "ERROR: could not reach the GitHub API. Check your network."
  sleep 15
  exit 1
}

# All arm64 asset URLs, newest release first (API order).
mapfile -t ASSET_URLS < <(echo "${META}" \
  | grep -oE '"browser_download_url": *"[^"]*"' \
  | sed -E 's/.*"(https[^"]+)".*/\1/' \
  | grep -E 'arm64\.tar\.xz$')

if [ "${#ASSET_URLS[@]}" -eq 0 ]; then
  echo "ERROR: no arm64 .tar.xz asset found in the latest CachyOS releases"
  echo "(API rate limit or asset naming changed?)."
  sleep 15
  exit 1
fi

# Newest asset per major line (first time we see a major in API order = latest).
declare -A LATEST_FOR_MAJOR
MAJORS=()
for url in "${ASSET_URLS[@]}"; do
  name="${url##*/}"
  m="${name#proton-cachyos-}"
  m="${m%%.*}"
  [ -n "${m}" ] || continue
  [ -n "${LATEST_FOR_MAJOR[$m]}" ] && continue
  LATEST_FOR_MAJOR[$m]="${url}"
  MAJORS+=("${m}")
done

echo "Release lines available: ${MAJORS[*]}"
echo ""

# Download + validate + patch the asset for one line into STAGING, returning the
# validated staging dir path on stdout (and 0); non-zero on any failure.
stage_asset() {
  local url="$1" name target_name extracted size magic manifest
  name="${url##*/}"
  target_name="${name%.tar.xz}"

  rm -f "${PART}"
  echo "  Downloading: ${name}" >&2
  # busybox wget draws its progress bar (%, size, ETA) on stderr; keep it on
  # the tool console so the download never looks stuck (same UX as the
  # Install Steam tool). stdout must stay clean: it returns the staging path.
  wget -c -t 5 -O "${PART}" "${url}" 1>&2 || { line_fail "download failed."; return 1; }

  size="$(stat -c%s "${PART}" 2>/dev/null || echo 0)"
  if [ "${size}" -lt 50000000 ]; then
    line_fail "downloaded file is suspiciously small (${size} bytes)."; return 1
  fi
  magic="$(head -c6 "${PART}" | od -An -tx1 | tr -d ' \n')"
  if [ "${magic}" != "fd377a585a00" ]; then
    line_fail "downloaded file is not an xz archive (magic=${magic})."; return 1
  fi

  rm -rf "${STAGING}"
  mkdir -p "${STAGING}"
  echo "  Extracting (a few hundred MB, takes a minute or two)..." >&2
  tar -xf "${PART}" -C "${STAGING}" || { line_fail "extraction failed (corrupt download?)."; return 1; }
  echo "  Extraction done." >&2

  extracted="${STAGING}/${target_name}"
  if [ ! -d "${extracted}" ]; then
    extracted="$(find "${STAGING}" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  fi
  if [ -z "${extracted}" ] || [ ! -f "${extracted}/proton" ] || [ ! -d "${extracted}/files" ]; then
    line_fail "extracted tool is incomplete (proton/files missing)."; return 1
  fi

  # Patch for ARM64: drop require_tool_appid (points at an x86 runtime that can't
  # launch on ARM -- the classic "unable to launch the compatibility tool" crash).
  manifest="${extracted}/toolmanifest.vdf"
  if [ -f "${manifest}" ] && grep -q require_tool_appid "${manifest}"; then
    sed -i '/require_tool_appid/d' "${manifest}" || { line_fail "could not patch toolmanifest.vdf."; return 1; }
  fi

  echo "${extracted}"
}

UPDATED=()
SKIPPED=()
FAILED=()

for m in "${MAJORS[@]}"; do
  url="${LATEST_FOR_MAJOR[$m]}"
  name="${url##*/}"
  target_name="${name%.tar.xz}"
  target_dir="${CTD}/${target_name}"

  echo "Line ${m}.x -> latest: ${target_name}"

  if [ -d "${target_dir}" ] && [ -f "${target_dir}/proton" ]; then
    echo "  Already up to date."
    echo ""
    SKIPPED+=("${target_name}")
    continue
  fi

  extracted="$(stage_asset "${url}")" || { FAILED+=("${m}.x"); echo ""; continue; }

  # Rotate this line's rollback: keep the current live version as the single
  # "previous" for this line; discard any older leftovers for this line only.
  current="$(newest_live_for_major "${m}")"
  store="${ROLLBACK_STORE}/${m}"
  rm -rf "${store}"
  mkdir -p "${store}"
  if [ -n "${current}" ]; then
    mv -f "${current}" "${store}/" || { line_fail "could not move current version into the rollback store."; FAILED+=("${m}.x"); echo ""; continue; }
  fi
  # Remove any remaining (older) live copies of THIS line so only the new one
  # stays visible. Other lines are never touched.
  for d in $(live_versions_for_major "${m}"); do
    [ -d "${d}" ] && rm -rf "${d}"
  done

  if ! mv -f "${extracted}" "${target_dir}"; then
    line_fail "could not move the new version into place."
    FAILED+=("${m}.x")
    echo ""
    continue
  fi

  echo "  Updated to ${target_name}."
  prev="$(ls -d "${store}"/proton-cachyos-*-arm64 2>/dev/null | sort | tail -n1)"
  if [ -n "${prev}" ]; then
    echo "  Previous version kept for rollback: $(basename "${prev}")"
  fi
  echo ""
  UPDATED+=("${target_name}")
done

echo "=== Summary ==="
[ "${#UPDATED[@]}" -gt 0 ] && printf '  Updated:  %s\n' "${UPDATED[@]}"
[ "${#SKIPPED[@]}" -gt 0 ] && printf '  Current:  %s\n' "${SKIPPED[@]}"
[ "${#FAILED[@]}"  -gt 0 ] && printf '  Failed:   %s\n' "${FAILED[@]}"
echo ""

if [ "${#UPDATED[@]}" -gt 0 ]; then
  echo "Fully close and relaunch Steam, then pick the version you want under a"
  echo "game's Properties > Compatibility. Run \"Rollback Proton CachyOS\" to switch"
  echo "a line back to its kept previous version."
fi

if [ "${#FAILED[@]}" -gt 0 ]; then
  sleep 15
  exit 1
fi
sleep 10
