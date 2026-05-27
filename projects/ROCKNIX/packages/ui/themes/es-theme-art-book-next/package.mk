# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2024-present ROCKNIX (https://github.com/ROCKNIX)

PKG_NAME="es-theme-art-book-next"
PKG_VERSION="9a50ef366e750aabfab29e6915a2867607212971"
PKG_LICENSE="CUSTOM"
PKG_SITE="https://github.com/anthonycaccese/art-book-next-es"
PKG_URL="https://github.com/anthonycaccese/art-book-next-es/archive/${PKG_VERSION}.tar.gz"
PKG_LONGDESC="Art Book Next"
PKG_TOOLCHAIN="manual"

makeinstall_target() {
  mkdir -p ${INSTALL}/usr/share/themes/${PKG_NAME}
    cp -rf * ${INSTALL}/usr/share/themes/${PKG_NAME}
    rm -rf ${INSTALL}/usr/share/themes/${PKG_NAME}/_inc/systems/{artwork-circuit,artwork-classic,artwork-nintendont,artwork-noir,artwork-outline}
    sed -i '/<include name="\(noir\|nintendont\|circuit\|outline\)"/d' ${INSTALL}/usr/share/themes/${PKG_NAME}/theme.xml
    # ROCKNIX add-on: system logo for GeForce NOW (gfn-electron), not present
    # upstream. The theme resolves carousel logos by convention
    # (logos/${system.theme}.svg).
    cp -f ${PKG_DIR}/sources/geforcenow.svg ${INSTALL}/usr/share/themes/${PKG_NAME}/_inc/systems/logos/geforcenow.svg
}
