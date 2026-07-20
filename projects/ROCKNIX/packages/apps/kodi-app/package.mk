# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)
#
# Kodi glue: the opt-in "Kodi" ES section (media center). Nothing appears
# until Tools > "Install Kodi" creates /storage/roms/kodi (see
# sources/kodi-setup). Bundles PM4K (script.plexmod, the community Plex
# client recommended by Plex staff on ARM64 Linux) plus its python module
# deps on top of the Kodi 21 backend (see mediacenter/kodi overlay), and
# Pillow so repo addons needing binary PIL work (e.g. weather.openmeteo).
#
# The tarball is a plain repack of unmodified addon zips from the official
# mirror (mirrors.kodi.tv/addons/omega) - composition + refresh procedure in
# NOTES.md. PM4K then self-updates from the official Kodi repository. The
# PKG_URL below is a placeholder for clean rebuilds; the build normally uses
# the local sources/kodi-app/ cache (same flow as gfn-electron).

PKG_NAME="kodi-app"
PKG_VERSION="1.0.0"
PKG_SHA256="529750732ac2065d64c6fb13420ec56ad7a02ddaf14fe2269b60387e13ab5db9"
PKG_ARCH="any"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/pannal/plex-for-kodi"
PKG_URL="https://github.com/Aanze/distribution/releases/download/kodi-app-${PKG_VERSION}/kodi-app-${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain kodi kodi-theme-Estuary peripheral.joystick Pillow"
PKG_TOOLCHAIN="manual"
PKG_LONGDESC="Kodi 21 media center + PM4K Plex client, opt-in ES section."

makeinstall_target() {
  # Bundled addon set (PM4K + module deps). The kodi package lists these ids
  # in addon-manifest.xml so Kodi auto-installs/enables them at first run.
  mkdir -p ${INSTALL}/usr/share/kodi/addons
    cp -r ${PKG_BUILD}/script.* ${INSTALL}/usr/share/kodi/addons/

  mkdir -p ${INSTALL}/usr/bin
    install -m 0755 ${PKG_DIR}/sources/start_kodi.sh ${INSTALL}/usr/bin/start_kodi.sh
    install -m 0755 ${PKG_DIR}/sources/kodi-setup ${INSTALL}/usr/bin/kodi-setup

  # boot hook: re-create the ES section for users who installed it
  mkdir -p ${INSTALL}/usr/lib/autostart/common
    install -m 0755 ${PKG_DIR}/sources/031-kodi-preinstall ${INSTALL}/usr/lib/autostart/common/031-kodi-preinstall

  # resume kick: revive Kodi's frozen wayland client after suspend (frame
  # callback deadlock; see sources/kodi-resume-kick)
  mkdir -p ${INSTALL}/usr/lib/systemd/system-sleep
    install -m 0755 ${PKG_DIR}/sources/kodi-resume-kick ${INSTALL}/usr/lib/systemd/system-sleep/kodi-resume-kick

  # first-run userdata seeds (consumed by kodi-setup ensure)
  mkdir -p ${INSTALL}/usr/share/kodi-app/seed
    cp ${PKG_DIR}/sources/seed/*.xml ${INSTALL}/usr/share/kodi-app/seed/
}
