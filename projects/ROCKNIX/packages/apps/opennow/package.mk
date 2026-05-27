# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="opennow"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0"
PKG_SITE="https://github.com/OpenCloudGaming/OpenNOW"
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain rocknix-browser"
PKG_LONGDESC="Launcher and on-device browser integration for OpenNOW, the GeForce NOW client. The AppImage itself is fetched at install time by the 'Install OpenNOW' tool."
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_DIR}/sources/start_opennow.sh ${INSTALL}/usr/bin/start_opennow.sh
  chmod 0755 ${INSTALL}/usr/bin/start_opennow.sh
  cp ${PKG_DIR}/sources/opennow-touchmouse-daemon ${INSTALL}/usr/bin/opennow-touchmouse-daemon
  chmod 0755 ${INSTALL}/usr/bin/opennow-touchmouse-daemon
}
