# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="ducktale-stream-plugin"
PKG_VERSION="0.1.0-aanze"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/aanze"
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain"
PKG_TOOLCHAIN="manual"
PKG_LONGDESC="DUCKTALE-STREAM: Decky plugin that adds a Stream button to Steam game pages for games installed on the PC. Drives the Moonlight already installed and paired on ROCKNIX (Moonlight Embedded) and re-points a dedicated Sunshine entry at the chosen game via Sunshine's REST API. Backend is pure stdlib and per-game parameters travel through a file, so it works with Decky's x86 backend under FEX and with the native arm64 runner Steam starts."

# Bundle is built at DEV time (npm run build in sources/plugin); the image build
# only ships the prebuilt dist/index.js, like ducktale-controls-plugin.
make_target() { :; }

makeinstall_target() {
  local SRC="${PKG_DIR}/sources/plugin"
  local OUT="${INSTALL}/usr/share/ducktale-stream"

  mkdir -p "${OUT}/dist" "${OUT}/runner"
  cp -f "${SRC}/plugin.json"   "${OUT}/plugin.json"
  cp -f "${SRC}/package.json"  "${OUT}/package.json"
  cp -f "${SRC}/main.py"       "${OUT}/main.py"
  cp -f "${SRC}/dist/index.js" "${OUT}/dist/index.js"
  cp -f "${SRC}/runner/ducktale-stream-run.sh" "${OUT}/runner/ducktale-stream-run.sh"
  chmod 0755 "${OUT}/main.py" "${OUT}/runner/ducktale-stream-run.sh"

  # Marker derived from plugin.json, NOT PKG_VERSION: the deploy is gated on it
  # and ducktale-controls was frozen for weeks because the two drifted apart.
  local PLUGIN_VER
  PLUGIN_VER="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "${SRC}/plugin.json" | head -1)"
  echo "${PLUGIN_VER:-${PKG_VERSION}}" > "${OUT}/.aanze-version"

  mkdir -p "${INSTALL}/usr/bin"
  cp -f "${PKG_DIR}/sources/deploy/ducktale-stream-deploy" "${INSTALL}/usr/bin/ducktale-stream-deploy"
  chmod 0755 "${INSTALL}/usr/bin/ducktale-stream-deploy"

  mkdir -p "${INSTALL}/usr/lib/autostart/common"
  cp -f "${PKG_DIR}/sources/deploy/116-ducktale-stream-deploy" "${INSTALL}/usr/lib/autostart/common/116-ducktale-stream-deploy"
  chmod 0755 "${INSTALL}/usr/lib/autostart/common/116-ducktale-stream-deploy"
}
