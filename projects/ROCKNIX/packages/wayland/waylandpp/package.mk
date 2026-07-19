# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2016-present Team LibreELEC (https://libreelec.tv)
# ROCKNIX overlay copy: adds -DCMAKE_POLICY_VERSION_MINIMUM=3.5 (toolchain cmake >= 4
# refuses these packages' ancient cmake_minimum_required). Needed by the Kodi 21
# (Plex/PM4K) dependency chain.

PKG_NAME="waylandpp"
PKG_VERSION="1.0.0"
PKG_SHA256="b20b45917382c6b87e9380130c9a1a1c563da2f498de5830df12fbce326dd9f5"
PKG_LICENSE="GPL"
PKG_SITE="https://github.com/NilsBrause/waylandpp"
PKG_URL="https://github.com/NilsBrause/waylandpp/archive/${PKG_VERSION}.tar.gz"
PKG_DEPENDS_HOST="toolchain:host pugixml:host"
PKG_DEPENDS_TARGET="toolchain pugixml:host waylandpp:host wayland"
PKG_LONGDESC="Wayland C++ bindings"

configure_package() {
  if [ "${OPENGL_SUPPORT}" = "yes" ]; then
    PKG_DEPENDS_TARGET+=" ${OPENGL}"
  elif [ "${OPENGLES_SUPPORT}" = "yes" ]; then
    PKG_DEPENDS_TARGET+=" ${OPENGLES}"
  fi
}

PKG_CMAKE_OPTS_HOST="-DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DBUILD_SCANNER=ON \
                     -DBUILD_LIBRARIES=OFF"

PKG_CMAKE_OPTS_TARGET="-DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DBUILD_SCANNER=OFF \
                       -DBUILD_LIBRARIES=ON \
                       -DCMAKE_CROSSCOMPILING=ON \
                       -DWAYLAND_SCANNERPP=${TOOLCHAIN}/bin/wayland-scanner++"
