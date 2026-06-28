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
  # The autostart helper is not part of the theme tree itself.
  rm -f ${INSTALL}/usr/share/themes/${PKG_NAME}/012-sync-steamlike-theme

  # Mirror the image theme into the writable /storage copy ES actually reads, on
  # boot, so new per-system logos/backgrounds (GeForce NOW, ...) land without a
  # manual deploy. (ES uses /storage/.config/emulationstation/themes/steamlike.)
  mkdir -p ${INSTALL}/usr/lib/autostart/common
  cp ${PKG_DIR}/sources/012-sync-steamlike-theme \
     ${INSTALL}/usr/lib/autostart/common/012-sync-steamlike-theme
  chmod 0755 ${INSTALL}/usr/lib/autostart/common/012-sync-steamlike-theme
}
