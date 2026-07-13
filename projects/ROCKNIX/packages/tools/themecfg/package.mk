# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="themecfg"
PKG_VERSION="0.1"
PKG_LICENSE="GPL-2.0-or-later"
PKG_SITE=""
PKG_URL=""
# gamepadcalibration provides the prebuilt aarch64 Pyxel venv the GUI reuses.
PKG_DEPENDS_TARGET="toolchain Python3 gamepadcalibration"
PKG_LONGDESC="Theme Manager for the steamlike theme: Pyxel GUI (look/art/backgrounds/SteamGridDB) launched from the ES UI Settings menu, SGDB art fetcher (sgdb-fetch), and tool cover-card generator."
PKG_TOOLCHAIN="manual"

make_target() {
  :
}

makeinstall_target() {
  # shared python core
  mkdir -p ${INSTALL}/usr/share/themecfg/app
  cp -f ${PKG_DIR}/sources/app/*.py ${INSTALL}/usr/share/themecfg/app/
  chmod 0644 ${INSTALL}/usr/share/themecfg/app/*.py

  # headless CLI backend + GUI launcher (system python3). The launcher lives in
  # /usr/bin (NOT /usr/config/modules) so it is NOT a Tools entry — it is
  # launched from the ES UI Settings menu (see the GuiMenu patch).
  mkdir -p ${INSTALL}/usr/bin
  cp -f ${PKG_DIR}/sources/bin/sgdb-fetch ${INSTALL}/usr/bin/sgdb-fetch
  cp -f "${PKG_DIR}/sources/scripts/Steamlike Theme Manager.sh" \
    ${INSTALL}/usr/bin/steamlike-theme-manager
  chmod 0755 ${INSTALL}/usr/bin/sgdb-fetch ${INSTALL}/usr/bin/steamlike-theme-manager

  # pre-baked 2:3 Tools cover-cards (shipped read-only). A common autostart
  # script re-points the Tools gamelist at these every boot; it only invokes
  # ImageMagick (timeout-guarded) for tools MISSING a cover, i.e. new upstream
  # tools that appear via OTA. A Theme Manager rebuild regenerates into
  # /storage/.config/themecfg/covers, which takes precedence.
  mkdir -p ${INSTALL}/usr/share/themecfg/covers
  cp -f ${PKG_DIR}/sources/covers/*.png ${INSTALL}/usr/share/themecfg/covers/
  chmod 0644 ${INSTALL}/usr/share/themecfg/covers/*.png

  # boot: re-point the Tools gamelist at the cover-cards (steamlike only). Named
  # "zzz-" so it runs LAST in the common scripts -- after 001-sync-modules reverts
  # the gamelist and after all first-boot setup -- so nothing reverts it after us.
  mkdir -p ${INSTALL}/usr/lib/autostart/common
  cp -f ${PKG_DIR}/sources/common/zzz-steamlike-toolcovers \
    ${INSTALL}/usr/lib/autostart/common/zzz-steamlike-toolcovers
  chmod 0755 ${INSTALL}/usr/lib/autostart/common/zzz-steamlike-toolcovers

  # ensure ES (essway.service) starts only AFTER rocknix-autostart finishes, so
  # the cover re-point above has run before ES reads the gamelist (otherwise ES
  # races autostart and the Tools shelf shows square .svg icons on a fresh boot).
  mkdir -p ${INSTALL}/usr/lib/systemd/system/essway.service.d
  cp -f ${PKG_DIR}/sources/systemd/essway.service.d/10-toolcovers-order.conf \
    ${INSTALL}/usr/lib/systemd/system/essway.service.d/10-toolcovers-order.conf
}
