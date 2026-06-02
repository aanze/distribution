# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="oledsaver"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0"
PKG_SITE=""
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain wayland make:host"
PKG_LONGDESC="OLED anti-image-retention screensaver overlay (wlr-layer-shell): a sweeping noise band painted over EmulationStation, input-transparent, driven by the ES screensaver-start/-stop events."

makeinstall_target() {
  make install DESTDIR=${INSTALL}

  # ES screensaver event hooks (seeded into /var/run by the autostart script)
  mkdir -p ${INSTALL}/usr/share/oledsaver
  cp ${PKG_DIR}/sources/screensaver-start ${INSTALL}/usr/share/oledsaver/
  cp ${PKG_DIR}/sources/screensaver-stop  ${INSTALL}/usr/share/oledsaver/
  chmod 0755 ${INSTALL}/usr/share/oledsaver/*

  # boot-time seeder
  mkdir -p ${INSTALL}/usr/lib/autostart/common
  cp ${PKG_DIR}/autostart/112-oledsaver ${INSTALL}/usr/lib/autostart/common/
  chmod 0755 ${INSTALL}/usr/lib/autostart/common/112-oledsaver
}
