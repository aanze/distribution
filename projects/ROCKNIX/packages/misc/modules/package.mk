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

  # DUCKTALE drop-in Tools entries: each feature branch ships its own fragment
  # (bare <game> blocks) in sources/gamelist.d/ instead of editing the shared
  # gamelist.xml -- file-adds only, so feature branches can never conflict
  # here on cherry-pick. Merged before </gameList>; ES sorts entries by name,
  # so append order is irrelevant.
  if ls ${PKG_DIR}/sources/gamelist.d/*.xml >/dev/null 2>&1; then
    sed -i '/<\/gameList>/d' ${INSTALL}/usr/config/modules/gamelist.xml
    cat ${PKG_DIR}/sources/gamelist.d/*.xml >> ${INSTALL}/usr/config/modules/gamelist.xml
    echo '</gameList>' >> ${INSTALL}/usr/config/modules/gamelist.xml
  fi
  rm -rf ${INSTALL}/usr/config/modules/gamelist.d
}

# DUCKTALE drop-in dependencies: each feature branch ships its own snippet in
# deps.d/ (typically a device-gated PKG_DEPENDS_TARGET+= block) instead of
# appending case blocks to this upstream file -- file-adds only, so feature
# branches can never conflict here on cherry-pick.
for _dropin in ${PKG_DIR}/deps.d/*.deps; do
  if [ -f "${_dropin}" ]; then
    . "${_dropin}"
  fi
done
unset _dropin
