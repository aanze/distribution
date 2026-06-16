# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="modules"
PKG_VERSION="1.0"
PKG_LICENSE="custom"
PKG_SITE=""
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain rclone commander"
PKG_LONGDESC="OS Modules Package"
PKG_TOOLCHAIN="manual"

case ${DEVICE} in
  RK3399|RK3588|SM8250|SM8550|SM8650|SM8750|SM6115)
    PKG_DEPENDS_TARGET+=" gamepadtester qterminal"
    ;;
esac

# Perf Control (CPU/GPU underclock + fan-curve tool). Separate case block so
# this addition never collides with the shared line above on cherry-pick.
case ${DEVICE} in
  SM8250|SM8550|SM8750)
    PKG_DEPENDS_TARGET+=" perfcontrol"
    ;;
esac

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/config/modules
    cp -rf ${PKG_DIR}/sources/* ${INSTALL}/usr/config/modules
}

post_makeinstall_target() {
  case ${DEVICE} in
    SM8650|SM8750) rm -f ${INSTALL}/usr/config/modules/*32bit* ;;
  esac

  if [[ "${INSTALLER_SUPPORT}" != "yes" || "${DISPLAYSERVER}" != "wl" ]]; then
    rm -f ${INSTALL}/usr/config/modules/Install*
  fi
}

# DUCKTALE-CONTROLS (aanze fork) Decky plugin — shipped in the image and
# auto-deployed into Decky on boot. Dedicated case block at EOF so it never
# collides with other branches' additions to the deps lines near the top.
case ${DEVICE} in
  SM8250|SM8550|SM8650|SM8750)
    PKG_DEPENDS_TARGET+=" ducktale-controls-plugin"
    ;;
esac
