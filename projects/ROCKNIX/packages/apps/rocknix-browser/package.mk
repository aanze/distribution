# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="rocknix-browser"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0"
PKG_SITE=""
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain rocknix-touchscreen-keyboard"
PKG_LONGDESC="A universal xdg-open handler for ROCKNIX: opens URLs in a real on-device browser (Firefox arm64, fetched on first use). Lets apps that delegate web login to xdg-open (e.g. OpenNOW) complete OAuth on the device, with no SSH or second computer."
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_DIR}/sources/rocknix-browser ${INSTALL}/usr/bin/rocknix-browser
  cp ${PKG_DIR}/sources/xdg-open ${INSTALL}/usr/bin/xdg-open
  chmod 0755 ${INSTALL}/usr/bin/rocknix-browser ${INSTALL}/usr/bin/xdg-open
}
