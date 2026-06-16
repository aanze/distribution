# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="es-theme-steamlike"
PKG_VERSION="0.1"
PKG_LICENSE="CC-BY-NC-SA"
PKG_SITE=""
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="ROCKNIX Steam-style EmulationStation theme (Big-Picture-like: tab carousel + per-game hero/cover from SteamGridDB)."
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  # The theme is the contents of sources/ verbatim. Same tree we rsync to
  # /storage/.config/emulationstation/themes/steamlike during live dev.
  mkdir -p ${INSTALL}/usr/share/themes/${PKG_NAME}
  cp -rf ${PKG_DIR}/sources/. ${INSTALL}/usr/share/themes/${PKG_NAME}/
}
