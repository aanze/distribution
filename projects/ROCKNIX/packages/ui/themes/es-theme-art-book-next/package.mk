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
    # DUCKTALE drop-in system logos: each feature branch ships its own
    # sources/logos/<system>.svg (the theme resolves carousel logos by
    # convention, logos/${system.theme}.svg) -- file-adds only, so feature
    # branches never edit this upstream file.
    if ls ${PKG_DIR}/sources/logos/*.svg >/dev/null 2>&1; then
      cp -f ${PKG_DIR}/sources/logos/*.svg ${INSTALL}/usr/share/themes/${PKG_NAME}/_inc/systems/logos/
    fi
}
