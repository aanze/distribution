#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 ROCKNIX (https://github.com/ROCKNIX)
#
# Build a catalogue of glibc-ARM64 Mesa Turnip (Vulkan) drivers using the
# ROCKNIX build toolchain, then publish them (raw .so + manifest.json) to a
# GitHub Release that the on-device GPU Driver Manager fetches.
#
# WHY this runs on the ROCKNIX build host (not GitHub-hosted CI): a Turnip .so
# must match the image's exact ABI (glibc, libdrm, C++). The only way to
# guarantee that is to build it with the SAME toolchain that built the image.
# Your build host already has that toolchain warm, so one driver builds in
# ~2 min. A GitHub-hosted runner would have to build the whole toolchain from
# scratch (hours) first. A self-hosted runner (= your build host) can run the
# optional workflow in ci/workflow.yml that just calls this script.
#
# Usage (from the ROCKNIX repo root):
#   PROJECT=ROCKNIX DEVICE=SM8750 ARCH=aarch64 \
#     ./projects/ROCKNIX/packages/tools/gpu-driver/ci/build-turnip-catalog.sh \
#       --repo aanze/rocknix-turnip \
#       --tag  catalog \
#       stable:26.1.3 stable:26.1.2 git:origin/main:nightly
#
# Each positional VERSION is one of:
#   stable:<tag>            official Mesa release tag (e.g. stable:26.1.3)
#   git:<ref>[:<label>]     a mesa.git ref (commit/branch); label names the build
#   local:<path-to-.so>     a pre-built .so you produced by hand (perso/experimental)
#
# The manifest channel is inferred: stable -> "stable", git -> "git",
# local -> "perso". Notes can be edited into the manifest afterwards.

set -euo pipefail

# Mirror all output to a fixed, tailable log (like build.sh -> /tmp/rocknix-build.log)
# so a build kicked off from the .bat can be followed live from any WSL shell:
#   tail -f /tmp/turnip-build.log     (or from Windows:  wsl tail -f /tmp/turnip-build.log)
TURNIP_LOG="${TURNIP_LOG:-/tmp/turnip-build.log}"
if [ -z "${_TURNIP_LOGGING:-}" ]; then
  export _TURNIP_LOGGING=1
  exec > >(tee "${TURNIP_LOG}") 2>&1
  echo ">>> turnip build logging to ${TURNIP_LOG}  (tail -f ${TURNIP_LOG})"
fi

REPO="aanze/rocknix-turnip"
TAG="catalog"
API_VERSION="1.4.348"
PUBLISH=1
SOURCES_FILE=""
MESA_PKG="projects/ROCKNIX/packages/graphics/mesa/package.mk"
MESA_URL_BASE="https://gitlab.freedesktop.org/mesa/mesa/-/archive"

VERSIONS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --tag)  TAG="$2"; shift 2 ;;
    --api)  API_VERSION="$2"; shift 2 ;;
    --sources) SOURCES_FILE="$2"; shift 2 ;;
    --no-publish) PUBLISH=0; shift ;;
    *) VERSIONS+=("$1"); shift ;;
  esac
done

# If no version was passed on the command line, read the catalogue source list
# (one spec per line, '#' comments / blanks ignored) — the 1-click workflow:
# edit catalog-sources.txt, re-run, the whole catalogue is rebuilt + published.
if [ ${#VERSIONS[@]} -eq 0 ] && [ -n "${SOURCES_FILE}" ]; then
  [ -f "${SOURCES_FILE}" ] || { echo "sources file not found: ${SOURCES_FILE}" >&2; exit 2; }
  while IFS= read -r line || [ -n "$line" ]; do
    spec="$(printf '%s' "$line" | sed 's/#.*//' | awk '{$1=$1;print}')"
    [ -n "$spec" ] && VERSIONS+=("$spec")
  done < "${SOURCES_FILE}"
fi

[ ${#VERSIONS[@]} -gt 0 ] || { echo "no versions given (pass specs, or --sources FILE)" >&2; exit 2; }

# Concurrency guard. This builder runs `scripts/build mesa` and temporarily
# rewrites projects/.../mesa/package.mk. A full image build (build_distro, e.g.
# build.sh / make) does the same in the SAME tree — running both at once
# corrupts both (mangled package.mk, half-written ninja dirs -> ".o.d: No such
# file or directory"). Refuse if an image build is already running.
# Match a real ./scripts/build_distro invocation, excluding our own process and
# parent shell (whose command line may merely mention the string).
if pgrep -f "scripts/build_distro" 2>/dev/null | grep -vw "$$" | grep -vqw "${PPID:-0}"; then
  echo "ERROR: a ROCKNIX image build (build_distro) is in progress." >&2
  echo "       It shares the build tree + mesa/package.mk with this script and they'd corrupt each other." >&2
  echo "       Wait for it to finish (tail -f /tmp/rocknix-build.log), then re-run." >&2
  exit 1
fi
[ -f "${MESA_PKG}" ] || { echo "run from the ROCKNIX repo root" >&2; exit 2; }
: "${PROJECT:?set PROJECT=ROCKNIX}" "${DEVICE:?set DEVICE=SM8750}" "${ARCH:?set ARCH=aarch64}"

OUT="$(mktemp -d)"
MANIFEST="${OUT}/manifest.json"
# GitHub asset download URL is /releases/download/<tag>/<asset>; the /latest/
# convenience alias is /releases/latest/download/<asset>. The CLI defaults to
# the /latest/ manifest, so mark the published release as "latest" on GitHub
# (or point GPU_DRIVER_MANIFEST_URL at this tag).
ASSET_BASE="https://github.com/${REPO}/releases/download/${TAG}"
[ "${TAG}" = "latest" ] && ASSET_BASE="https://github.com/${REPO}/releases/latest/download"

ORIG_PKG="$(mktemp)"; cp -f "${MESA_PKG}" "${ORIG_PKG}"
restore() { cp -f "${ORIG_PKG}" "${MESA_PKG}"; rm -f "${ORIG_PKG}"; }
# Restore the project mesa package.mk on ANY exit incl. Ctrl-C/kill, so an
# interrupted run never leaves the system mesa repointed at a src: tarball.
trap restore EXIT INT TERM HUP

entries=()

build_one() {
  local id="$1" channel="$2" so_src="$3" mesa_ver="$4"
  local asset="libvulkan_freedreno-${id}.so"
  cp -f "${so_src}" "${OUT}/${asset}"
  local sha; sha="$(sha256sum "${OUT}/${asset}" | cut -d' ' -f1)"
  [ -z "${mesa_ver}" ] && mesa_ver="$(strings -a "${OUT}/${asset}" | grep -oE 'Mesa [0-9][0-9.a-z-]*' | head -1 | cut -d' ' -f2)"
  entries+=("$(printf '{"id":"%s","mesa_version":"%s","channel":"%s","url":"%s/%s","sha256":"%s","api_version":"%s","notes":""}' \
    "${id}" "${mesa_ver:-?}" "${channel}" "${ASSET_BASE}" "${asset}" "${sha}" "${API_VERSION}")")
  echo ">> packaged ${id} (Mesa ${mesa_ver:-?}, ${sha:0:12}…)"
}

build_mesa() {  # $1 = version string used by package.mk; returns built .so path
  local pkgver="$1" url="$2"
  cp -f "${ORIG_PKG}" "${MESA_PKG}"
  sed -i "s|^PKG_VERSION=.*|PKG_VERSION=\"${pkgver}\"|" "${MESA_PKG}"
  [ -n "${url}" ] && sed -i "s|^PKG_URL=.*|PKG_URL=\"${url}\"|" "${MESA_PKG}"
  # Start this variant from a clean dir: a previous interrupted build can leave a
  # half-configured meson/ninja tree whose missing .o.d dirs make the next build
  # die with "opening dependency file ...: No such file or directory". Wiping
  # only THIS version's dirs (never the stock mesa-26.1.x) guarantees a fresh build.
  local bd="build.${PROJECT}-${DEVICE}.${ARCH}"
  rm -rf "${bd}/build/mesa-${pkgver}" "${bd}/install_pkg/mesa-${pkgver}" 2>/dev/null || true
  ./scripts/build mesa >&2
  echo "${bd}/install_pkg/mesa-${pkgver}/usr/lib/libvulkan_freedreno.so"
}

for v in "${VERSIONS[@]}"; do
  kind="${v%%:*}"; rest="${v#*:}"
  case "${kind}" in
    stable)
      tag="${rest}"
      # Fail fast, with an explanation, when the requested release tag does not
      # exist upstream (typically: asking for a Mesa series that has not been
      # released yet) — otherwise this surfaces as an opaque 404 mid-build.
      # Offline (ls-remote fails/empty) -> skip the check and try the download.
      if tags="$(git ls-remote --tags https://gitlab.freedesktop.org/mesa/mesa.git 'refs/tags/mesa-*' 2>/dev/null)" \
         && [ -n "${tags}" ] \
         && ! printf '%s\n' "${tags}" | grep -q "refs/tags/mesa-${tag}\$"; then
        latest="$(printf '%s\n' "${tags}" | sed 's|.*refs/tags/mesa-||' | grep -v '\^{}$' | sort -V | tail -1)"
        echo "stable:${tag}: Mesa has no release tag 'mesa-${tag}' (newest stable: ${latest})." >&2
        echo "An unreleased series only exists on mesa main — build it as mesa-git instead" >&2
        echo "(turnip-builder base option 3, or spec git:origin/main:<label>)." >&2
        exit 2
      fi
      url="${MESA_URL_BASE}/mesa-${tag}/mesa-mesa-${tag}.tar.gz"
      so="$(build_mesa "${tag}" "${url}")"
      build_one "turnip-${tag}-stable" "stable" "${so}" "${tag}"
      ;;
    git)
      ref="${rest%%:*}"; label="${rest#*:}"; [ "${label}" = "${ref}" ] && label="$(echo "${ref}" | tr '/:' '--')"
      # gitlab archive by ref; PKG_VERSION must be filesystem-safe
      pkgver="git-$(echo "${ref}" | tr '/:' '--')"
      url="${MESA_URL_BASE}/${ref}/mesa-${ref}.tar.gz"
      so="$(build_mesa "${pkgver}" "${url}")"
      build_one "turnip-${label}" "git" "${so}" ""
      ;;
    local)
      build_one "turnip-$(basename "${rest}" .so)-perso" "perso" "${rest}" ""
      ;;
    src)
      # src:<label>:<source-tarball> — build Turnip from a prepared (patched)
      # mesa source tree. The interactive turnip-builder.sh produces the tarball
      # (base + cherry-picked MRs + patches). file:// is handled by scripts/get
      # and scripts/unpack normalises the top dir to mesa-<label>.
      label="${rest%%:*}"; tarball="${rest#*:}"
      [ -f "${tarball}" ] || { echo "src tarball not found: ${tarball}" >&2; exit 2; }
      so="$(build_mesa "${label}" "file://${tarball}")"
      build_one "turnip-${label}" "perso" "${so}" ""
      ;;
    *) echo "unknown version spec: ${v}" >&2; exit 2 ;;
  esac
done

restore; trap - EXIT INT TERM HUP

# New drivers built THIS run, as a JSON array.
{
  echo '['
  for i in "${!entries[@]}"; do
    sep=","; [ "${i}" -eq $((${#entries[@]}-1)) ] && sep=""
    echo "  ${entries[$i]}${sep}"
  done
  echo ']'
} > "${OUT}/new.json"

# Fetch the EXISTING catalogue manifest and MERGE into it, so publishing one
# driver doesn't drop the rest (the catalogue is cumulative; new id overrides
# same id). Skipped for --no-publish (dry run) and on the very first publish.
OLD_MANIFEST="${OUT}/old.json"; echo '{"drivers":[]}' > "${OLD_MANIFEST}"
if [ "${PUBLISH}" -eq 1 ] && command -v gh >/dev/null \
   && gh release view "${TAG}" --repo "${REPO}" >/dev/null 2>&1; then
  gh release download "${TAG}" --repo "${REPO}" --pattern manifest.json \
     --output "${OLD_MANIFEST}" --clobber 2>/dev/null || echo '{"drivers":[]}' > "${OLD_MANIFEST}"
fi
# Asset list of the release: used to PRUNE manifest entries whose .so was
# deleted by hand from the release (otherwise a removed driver keeps showing
# as [download] on every device forever -- the merge is cumulative).
ASSET_LIST="${OUT}/assets.txt"; : > "${ASSET_LIST}"
if [ "${PUBLISH}" -eq 1 ] && command -v gh >/dev/null \
   && gh release view "${TAG}" --repo "${REPO}" >/dev/null 2>&1; then
  gh release view "${TAG}" --repo "${REPO}" --json assets \
     --jq '.assets[].name' > "${ASSET_LIST}" 2>/dev/null || : > "${ASSET_LIST}"
fi

ASSET_LIST_FILE="${ASSET_LIST}" python3 - "${OLD_MANIFEST}" "${OUT}/new.json" "${DEVICE}" > "${MANIFEST}" <<'PY'
import sys, json
old = json.load(open(sys.argv[1]))
new = json.load(open(sys.argv[2]))
device = sys.argv[3]
by = {d["id"]: d for d in old.get("drivers", [])}   # keep existing
# prune entries whose asset was deleted from the release by hand (an empty
# asset list means we could not read the release -- prune nothing)
import os
assets = set()
alist = os.environ.get("ASSET_LIST_FILE", "")
if alist and os.path.exists(alist):
    assets = {l.strip() for l in open(alist) if l.strip()}
if assets:
    def _aname(i, d):
        u = d.get("url", "")
        return u.rsplit("/", 1)[-1] if u else "libvulkan_freedreno-%s.so" % i
    by = {i: d for i, d in by.items() if _aname(i, d) in assets}
for d in new:                                        # add / override same id
    by[d["id"]] = d
json.dump({"schema": 1, "generated_for": device,
           "drivers": sorted(by.values(), key=lambda d: d["id"])},
          sys.stdout, indent=2)
print()
PY
rm -f "${OUT}/new.json" "${OLD_MANIFEST}" "${ASSET_LIST}"

echo "=== manifest.json (merged catalogue) ==="; cat "${MANIFEST}"
echo "=== assets in ${OUT} ==="; ls -lh "${OUT}"

if [ "${PUBLISH}" -eq 1 ]; then
  command -v gh >/dev/null || { echo "gh CLI not found; re-run with --no-publish" >&2; exit 1; }
  if gh release view "${TAG}" --repo "${REPO}" >/dev/null 2>&1; then
    gh release upload "${TAG}" --repo "${REPO}" --clobber "${OUT}"/*
  else
    gh release create "${TAG}" --repo "${REPO}" \
      --title "Turnip driver catalogue" \
      --notes "glibc-ARM64 Mesa Turnip drivers for the ROCKNIX GPU Driver Manager." \
      "${OUT}"/*
  fi
  echo "published to ${REPO} (${TAG})"
else
  echo "artifacts left in ${OUT} (not published)"
fi
