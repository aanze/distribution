# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="steam-shortcuts"
PKG_VERSION="1.0"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE=""
PKG_URL=""
PKG_DEPENDS_TARGET="toolchain"
PKG_LONGDESC="Mirror ES sections into Steam non-Steam shortcuts: PS3 games (native RPCS3 through a FEX-escape wrapper) and the GeForce NOW / OpenNOW launchers, with EmulationStation-scraped art installed as Steam grid images. Driven by the 'Add PS3 Games To Steam' Tools entry."
PKG_TOOLCHAIN="manual"

# The shortcuts.vdf entries bake absolute Exe paths under
# /storage/.config/steam-shortcuts (stable appids => Steam per-app settings
# survive), so the LIVE copies live there and the Tools entry refreshes them
# from this read-only payload before every regeneration.
makeinstall_target() {
  mkdir -p ${INSTALL}/usr/share/steam-shortcuts
  cp -f ${PKG_DIR}/sources/app-launch.sh \
        ${PKG_DIR}/sources/ps3-launch.sh \
        ${PKG_DIR}/sources/steam-shortcuts-sync.py \
        ${INSTALL}/usr/share/steam-shortcuts/
  chmod 0755 ${INSTALL}/usr/share/steam-shortcuts/*
}
