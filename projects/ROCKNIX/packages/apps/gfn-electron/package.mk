# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="gfn-electron"
PKG_VERSION="3.0.0"
PKG_ARCH="aarch64"
PKG_LICENSE="GPL-3.0"
PKG_SITE="https://github.com/hmlendea/gfn-electron"
# Prebuilt arm64 bundle: upstream only ships x86_64, so we cross-build the arm64
# Electron app ourselves with electron-builder (pure-JS app, no native deps) and
# host the unpacked tree as a tarball. See the personal-mods notes / build recipe:
#   git clone https://github.com/hmlendea/gfn-electron && npm install \
#     && npx electron-builder --linux AppImage --arm64 --publish never
#   tar czf gfn-electron-${PKG_VERSION}-arm64.tar.gz -C dist linux-arm64-unpacked
# The local sources/ cache (sources/gfn-electron/) lets this build offline; the
# PKG_URL only matters for clean rebuilds on another host.
PKG_URL="https://github.com/Aanze/distribution/releases/download/gfn-electron-${PKG_VERSION}/gfn-electron-${PKG_VERSION}-arm64.tar.gz"
PKG_SOURCE_NAME="gfn-electron-${PKG_VERSION}-arm64.tar.gz"
# wvkbd (rocknix-touchscreen-keyboard) provides the on-screen keyboard the
# launcher summons for the first NVIDIA login.
PKG_DEPENDS_TARGET="toolchain rocknix-touchscreen-keyboard"
PKG_LONGDESC="GeForce NOW desktop client (hmlendea/gfn-electron), cross-built for arm64. A native-arm64 Electron wrapper of the GeForce NOW web app, so video decode rides the device's VAAPI/V4L2 (qcom-iris) path. Launched from EmulationStation; first login uses NVIDIA account or Discord (Google sign-in is blocked inside Electron)."
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  # Prebuilt arm64 Electron app tree -> read-only rootfs
  mkdir -p ${INSTALL}/usr/share/gfn-electron
  cp -rf ${PKG_BUILD}/* ${INSTALL}/usr/share/gfn-electron/

  # Launcher + the (instant, offline) install/uninstall helper
  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_DIR}/sources/start_gfn-electron.sh ${INSTALL}/usr/bin/start_gfn-electron.sh
  cp ${PKG_DIR}/sources/gfn-electron-setup    ${INSTALL}/usr/bin/gfn-electron-setup
  chmod 0755 ${INSTALL}/usr/bin/start_gfn-electron.sh \
             ${INSTALL}/usr/bin/gfn-electron-setup

  # Preinstall the section on boot (so a fresh flash shows GeForce NOW without
  # running "Install GeForce NOW"); respects an explicit Uninstall.
  mkdir -p ${INSTALL}/usr/lib/autostart/common
  cp ${PKG_DIR}/sources/030-geforcenow-preinstall \
     ${INSTALL}/usr/lib/autostart/common/030-geforcenow-preinstall
  chmod 0755 ${INSTALL}/usr/lib/autostart/common/030-geforcenow-preinstall
}
