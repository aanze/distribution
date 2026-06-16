# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="rocknix-control-plugin"
PKG_VERSION="0.2.0-aanze"
PKG_LICENSE="custom"
PKG_SITE="https://github.com/thefiqs/rocknix-control"
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="ROCKNIX Control (aanze fork): vendored Decky plugin for CPU/GPU/fan control. Prebuilt bundle shipped in the image and auto-deployed into Decky on boot. Fixes vs upstream: detect the live preset on load + restore the pre-game preset on game exit (no hardcoded Default)."
PKG_TOOLCHAIN="manual"

# Build the bundle at DEV time (see sources/plugin/README.aanze.md). The image
# build only ships the prebuilt dist/index.js — no node needed here.
make_target() { :; }

makeinstall_target() {
  local SRC="${PKG_DIR}/sources/plugin"
  local OUT="${INSTALL}/usr/share/rocknix-control"

  # runtime payload Decky needs (plugin.json + main.py + dist/index.js); the
  # boot deploy copies this whole dir into /storage/homebrew/plugins/.
  mkdir -p "${OUT}/dist"
  cp -f "${SRC}/plugin.json"   "${OUT}/plugin.json"
  cp -f "${SRC}/package.json"  "${OUT}/package.json"
  cp -f "${SRC}/main.py"       "${OUT}/main.py"
  cp -f "${SRC}/dist/index.js" "${OUT}/dist/index.js"
  chmod 0755 "${OUT}/main.py"
  echo "${PKG_VERSION}" > "${OUT}/.aanze-version"

  # deploy engine + boot hook
  mkdir -p "${INSTALL}/usr/bin"
  cp -f "${PKG_DIR}/sources/deploy/rocknix-control-deploy" "${INSTALL}/usr/bin/rocknix-control-deploy"
  chmod 0755 "${INSTALL}/usr/bin/rocknix-control-deploy"

  mkdir -p "${INSTALL}/usr/lib/autostart/common"
  cp -f "${PKG_DIR}/sources/deploy/115-rocknix-control-deploy" "${INSTALL}/usr/lib/autostart/common/115-rocknix-control-deploy"
  chmod 0755 "${INSTALL}/usr/lib/autostart/common/115-rocknix-control-deploy"
}
