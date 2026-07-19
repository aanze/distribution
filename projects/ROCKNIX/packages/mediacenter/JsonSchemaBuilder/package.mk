# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2019-present Team LibreELEC (https://libreelec.tv)

#
# ROCKNIX overlay copy: literal "kodi" instead of ${MEDIACENTER} (unset here;
# kodi is the Plex/PM4K client backend, not the session mediacenter).
PKG_NAME="JsonSchemaBuilder"
PKG_VERSION="0"
PKG_LICENSE="GPL"
PKG_SITE="http://www.kodi.tv"
PKG_DEPENDS_HOST="cmake:host ninja:host"
PKG_DEPENDS_UNPACK="kodi"
PKG_LONGDESC="kodi-platform:"

PKG_CMAKE_SCRIPT="$(get_build_dir kodi)/tools/depends/native/JsonSchemaBuilder/src/CMakeLists.txt"

PKG_CMAKE_OPTS_HOST="-Wno-dev"

makeinstall_host() {
  mkdir -p ${TOOLCHAIN}/bin
    cp JsonSchemaBuilder ${TOOLCHAIN}/bin
}
