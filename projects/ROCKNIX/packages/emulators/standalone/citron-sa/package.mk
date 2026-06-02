# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="citron-sa"
PKG_LICENSE="GPLv3"
PKG_SITE="https://citron-emu.org"
PKG_LONGDESC="Citron (Nintendo Switch) runtime scripts for ROCKNIX. The emulator AppImage itself is not bundled; it is fetched on demand by the 'Install Citron' tool into the writable storage tree."
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp -f ${PKG_DIR}/scripts/start_citron.sh ${INSTALL}/usr/bin/
  cp -f ${PKG_DIR}/scripts/citron-update   ${INSTALL}/usr/bin/
  chmod 0755 ${INSTALL}/usr/bin/start_citron.sh ${INSTALL}/usr/bin/citron-update
}
