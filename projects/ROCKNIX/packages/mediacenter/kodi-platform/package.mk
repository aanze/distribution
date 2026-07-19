# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2009-2016 Stephan Raue (stephan@openelec.tv)
# Copyright (C) 2018-present Team LibreELEC (https://libreelec.tv)
#
# ROCKNIX overlay copy (LE 12.0 pin). The only change: the dependency is a
# literal "kodi:host" — ROCKNIX does not define the global MEDIACENTER
# variable (Kodi is not the session here, it is the Plex client backend).

PKG_NAME="kodi-platform"
PKG_VERSION="809c5e9d711e378561440a896fcb7dbcd009eb3d"
PKG_SHA256="159165ae641da5eb273885ce53b8a4b84e62a595c4974f9d12c1b5d1428ef25c"
PKG_LICENSE="GPL"
PKG_SITE="http://www.kodi.tv"
PKG_URL="https://github.com/xbmc/kodi-platform/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_TARGET="toolchain tinyxml kodi:host p8-platform"
PKG_LONGDESC="kodi-platform:"

PKG_CMAKE_OPTS_TARGET="-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
                       -DCMAKE_INSTALL_LIBDIR:STRING=lib \
                       -DCMAKE_INSTALL_LIBDIR_NOARCH:STRING=lib \
                       -DCMAKE_INSTALL_PREFIX_TOOLCHAIN=${SYSROOT_PREFIX}/usr \
                       -DBUILD_SHARED_LIBS=0"

post_makeinstall_target() {
  rm -rf ${INSTALL}/usr/lib/kodiplatform
}
