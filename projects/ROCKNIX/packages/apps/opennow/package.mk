# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="opennow"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0"
PKG_SITE="https://github.com/OpenCloudGaming/OpenNOW"
PKG_URL=""
# No rocknix-browser dependency: current OpenNOW builds are expected to log in
# inside their own Electron window (like gfn-electron). If a future OpenNOW
# delegates the NVIDIA OAuth to xdg-open, add "rocknix-browser" back here and
# have start_opennow.sh pre-fetch it.
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Launcher + on-demand installer for OpenNOW, an open-source GeForce NOW client offered as an ALTERNATIVE inside the existing GeForce NOW main-menu section (gfn-electron stays the default). The AppImage itself is fetched at install time by the 'Install OpenNOW' tool."
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_DIR}/sources/start_opennow.sh          ${INSTALL}/usr/bin/start_opennow.sh
  cp ${PKG_DIR}/sources/opennow-touchmouse-daemon ${INSTALL}/usr/bin/opennow-touchmouse-daemon
  cp ${PKG_DIR}/sources/opennow-update            ${INSTALL}/usr/bin/opennow-update
  chmod 0755 ${INSTALL}/usr/bin/start_opennow.sh \
             ${INSTALL}/usr/bin/opennow-touchmouse-daemon \
             ${INSTALL}/usr/bin/opennow-update
}
