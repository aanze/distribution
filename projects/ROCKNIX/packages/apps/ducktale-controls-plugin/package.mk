# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="ducktale-controls-plugin"
PKG_VERSION="0.7.6-aanze"
PKG_LICENSE="custom"
PKG_SITE="https://github.com/thefiqs/rocknix-control"
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="DUCKTALE-CONTROLS (aanze fork of thefiqs/rocknix-control): vendored Decky plugin for CPU/GPU/fan control. Prebuilt bundle shipped in the image and auto-deployed into Decky on boot. Changes vs upstream: track the Perf Control canonical active profile so a selection (incl. one set mid-game) persists across game launch/exit instead of reverting to Default, charging-mode selector (full / battery care / bypass), collapsible sections, DUCKTALE rebrand."
PKG_TOOLCHAIN="manual"

# Build the bundle at DEV time (see sources/plugin/README.aanze.md). The image
# build only ships the prebuilt dist/index.js — no node needed here.
make_target() { :; }

makeinstall_target() {
  local SRC="${PKG_DIR}/sources/plugin"
  local OUT="${INSTALL}/usr/share/ducktale-controls"

  # runtime payload Decky needs (plugin.json + main.py + dist/index.js); the
  # boot deploy copies this whole dir into /storage/homebrew/plugins/.
  mkdir -p "${OUT}/dist"
  cp -f "${SRC}/plugin.json"   "${OUT}/plugin.json"
  cp -f "${SRC}/package.json"  "${OUT}/package.json"
  cp -f "${SRC}/main.py"       "${OUT}/main.py"
  cp -f "${SRC}/dist/index.js" "${OUT}/dist/index.js"
  chmod 0755 "${OUT}/main.py"

  # The boot deploy only copies when this marker differs from the deployed one,
  # so it MUST track the payload. Deriving it from plugin.json (the version the
  # bundle itself declares) instead of PKG_VERSION removes the desync that
  # silently froze deploys: 0.7.4 shipped with PKG_VERSION left at 0.7.3, the
  # marker matched what was on the device and the new bundle was never copied.
  # Fall back to PKG_VERSION if the version line ever moves.
  local PLUGIN_VER
  PLUGIN_VER="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${SRC}/plugin.json" | head -1)"
  echo "${PLUGIN_VER:-${PKG_VERSION}}" > "${OUT}/.aanze-version"

  # deploy engine + boot hook
  mkdir -p "${INSTALL}/usr/bin"
  cp -f "${PKG_DIR}/sources/deploy/ducktale-controls-deploy" "${INSTALL}/usr/bin/ducktale-controls-deploy"
  chmod 0755 "${INSTALL}/usr/bin/ducktale-controls-deploy"

  mkdir -p "${INSTALL}/usr/lib/autostart/common"
  cp -f "${PKG_DIR}/sources/deploy/115-ducktale-controls-deploy" "${INSTALL}/usr/lib/autostart/common/115-ducktale-controls-deploy"
  chmod 0755 "${INSTALL}/usr/lib/autostart/common/115-ducktale-controls-deploy"
}
