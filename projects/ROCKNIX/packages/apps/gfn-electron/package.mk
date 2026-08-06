# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="gfn-electron"
PKG_VERSION="3.0.2"
PKG_ARCH="aarch64"
PKG_LICENSE="GPL-3.0"
PKG_SITE="https://github.com/hmlendea/gfn-electron"
# 3.1.0: the app runs on a CUSTOM Electron 39 (Chromium 142) we build from
# source for arm64 with `use_v4l2_codec=true use_vaapi=false` so Chromium's
# stateful V4L2 decoder drives the Qualcomm iris hardware decoder (/dev/video0)
# for the GFN WebRTC H.264/VP9 stream. Device-verified: Chromium's GPU process
# opens /dev/video0 and enumerates iris h264 baseline/main/high + vp9 as HW
# decode. scripts/main.js enables the 'AcceleratedVideoDecoder' feature (the
# post-M132 rename of 'VaapiVideoDecoder', which is now a silent no-op).
# Build recipe + gotchas (v8 checks OFF, MT21 dtor, modern V4L2 UAPI headers):
# ~/src/electron-v4l2/build-electron-v4l2.sh (see rocknix-gfn-hw-decode memory).
#   compose: dist.zip runtime + patched resources/app -> stripped tarball.
# The local sources/ cache (sources/gfn-electron/) lets this build offline; the
# PKG_URL only matters for clean rebuilds on another host.
PKG_URL="https://github.com/Aanze/distribution/releases/download/gfn-electron-${PKG_VERSION}/gfn-electron-${PKG_VERSION}-arm64.tar.gz"
PKG_SOURCE_NAME="gfn-electron-${PKG_VERSION}-arm64.tar.gz"
# wvkbd (rocknix-touchscreen-keyboard) provides the on-screen keyboard the
# launcher summons for the first NVIDIA login.
PKG_DEPENDS_TARGET="toolchain rocknix-touchscreen-keyboard"
PKG_LONGDESC="GeForce NOW desktop client (hmlendea/gfn-electron) on a custom arm64 Electron 39 built with use_v4l2_codec=true, so the GFN WebRTC video stream HARDWARE-decodes on the Qualcomm iris V4L2 decoder (/dev/video0) instead of the CPU. Launched from EmulationStation; first login uses NVIDIA account or Discord (Google sign-in is blocked inside Electron)."
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  # Prebuilt arm64 Electron app tree -> read-only rootfs
  mkdir -p ${INSTALL}/usr/share/gfn-electron
  cp -rf ${PKG_BUILD}/* ${INSTALL}/usr/share/gfn-electron/

  # Steam-session window sizing: BrowserWindow reads GFN_WINDOW_W/H from the
  # environment (exported by the steam-shortcuts wrapper) so the window fills
  # the gamescope output deterministically; stock 800x600 in the ES session.
  patch -d ${INSTALL}/usr/share/gfn-electron -p1 \
    < ${PKG_DIR}/sources/gfn-window-size.patch

  # Launcher + the (instant, offline) install/uninstall helper
  mkdir -p ${INSTALL}/usr/bin
  cp ${PKG_DIR}/sources/start_gfn-electron.sh ${INSTALL}/usr/bin/start_gfn-electron.sh
  cp ${PKG_DIR}/sources/gfn-electron-setup    ${INSTALL}/usr/bin/gfn-electron-setup
  chmod 0755 ${INSTALL}/usr/bin/start_gfn-electron.sh \
             ${INSTALL}/usr/bin/gfn-electron-setup

  # InputPlumber session profile for the "GeForce NOW (Right Stick Mouse)"
  # entry (right stick -> mouse motion, back paddles -> clicks). Loaded by
  # start_gfn-electron.sh --stick-mouse.
  mkdir -p ${INSTALL}/usr/share/inputplumber/profiles
  cp ${PKG_DIR}/sources/right-stick-mouse.yaml \
     ${INSTALL}/usr/share/inputplumber/profiles/right-stick-mouse.yaml

  # Preinstall the section on boot (so a fresh flash shows GeForce NOW without
  # running "Install GeForce NOW"); respects an explicit Uninstall.
  mkdir -p ${INSTALL}/usr/lib/autostart/common
  cp ${PKG_DIR}/sources/030-geforcenow-preinstall \
     ${INSTALL}/usr/lib/autostart/common/030-geforcenow-preinstall
  chmod 0755 ${INSTALL}/usr/lib/autostart/common/030-geforcenow-preinstall
}
